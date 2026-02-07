--[[
    UI_HUD.lua - Heads-up display for GoldPH

    Shows real-time session metrics in accounting-style layout.
]]

local GoldPH_HUD = {}

local hudFrame = nil
local updateTimer = 0
local UPDATE_INTERVAL = 1.0 -- Update every 1 second

-- Layout constants
local PADDING = 12
local FRAME_WIDTH = 180
-- Base expanded height; actual height is dynamically adjusted based on visible rows
local FRAME_HEIGHT = 180
-- Calculate minimized height to match visual padding:
-- Top visual padding: PADDING (12px) - backdrop inset (4px) = 8px visual
-- Title: ~18px (GameFontNormalLarge)
-- Gap: 4px
-- HeaderLine: ~14px (GameFontNormalSmall)
-- Micro-bar tiles: ~50px (icon + text + bar)
-- Bottom visual padding: should match top (8px visual) + backdrop inset (4px) = 12px from frame bottom
-- Total: 12 (top) + 18 + 4 + 14 + 50 + 12 (bottom) = 110px
-- Reduced to 66px for compact design with micro-bars
local FRAME_HEIGHT_MINI = 66  -- Minimized height with micro-bars
local LABEL_X = PADDING
local VALUE_X = FRAME_WIDTH - PADDING  -- Right edge for right-aligned values
local ROW_HEIGHT = 14
local SECTION_GAP = 4

-- Muted semantic colors for micro-bars
local MICROBAR_COLORS = {
    GOLD = { fill = {1.00, 0.78, 0.22, 0.90}, bg = {0.10, 0.10, 0.10, 0.55} },
    XP = { fill = {0.35, 0.62, 0.95, 0.90}, bg = {0.10, 0.10, 0.10, 0.55} },
    REP = { fill = {0.35, 0.82, 0.45, 0.90}, bg = {0.10, 0.10, 0.10, 0.55} },
    HONOR = { fill = {0.72, 0.40, 0.90, 0.90}, bg = {0.10, 0.10, 0.10, 0.55} },
}

local METRIC_ICONS = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    xp = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Icon",
    rep = "Interface\\FriendsFrame\\FriendsFrameScrollIcon",
    honor = "Interface\\PVPFrame\\PVP-Currency-Alliance",
}

-- Runtime state for micro-bars (not persisted)
local metricStates = {
    gold = { key = "gold", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    xp = { key = "xp", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    rep = { key = "rep", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    honor = { key = "honor", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
}

local lastUpdateTime = 0

--------------------------------------------------
-- Micro-Bar Helper Functions
--------------------------------------------------

-- Exponential smoothing for rate display
local function SmoothRate(prevDisplayRate, currentRate, alpha)
    if prevDisplayRate == 0 then
        return currentRate  -- First time: initialize
    end
    return (alpha * currentRate) + ((1 - alpha) * prevDisplayRate)
end

-- Normalize rate to [0,1] for micro-bar fill
local function NormalizeRate(displayRate, peak, minFloor)
    local refMax = math.max(peak, minFloor)
    if refMax == 0 then return 0 end
    return math.min(math.max(displayRate / refMax, 0), 1)
end

-- Optional peak decay over time
local function DecayPeak(currentPeak, currentRate, minutesSinceLastTick, cfg)
    if not cfg.peakDecay.enabled then
        return math.max(currentPeak, currentRate)
    end
    local decayFactor = 1 - (cfg.peakDecay.ratePerMin * minutesSinceLastTick)
    local decayedPeak = currentPeak * decayFactor
    return math.max(decayedPeak, currentRate)
end

-- Format rate for micro-bar display (compact)
local function FormatRateForMicroBar(metricKey, rate)
    if metricKey == "gold" then
        -- Inline FormatAccountingShort logic for gold
        if not rate or rate == 0 then
            return "0g/h"
        end
        local isNegative = rate < 0
        local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(rate))
        if isNegative and formatted ~= "0g" then
            return "(" .. formatted .. ")/h"
        else
            return formatted .. "/h"
        end
    elseif metricKey == "xp" then
        if rate >= 1000 then
            return string.format("%.1fk/h", rate / 1000)
        else
            return string.format("%d/h", rate)
        end
    elseif metricKey == "rep" then
        return string.format("%d/h", rate)
    elseif metricKey == "honor" then
        if rate >= 1000 then
            return string.format("%.1fk/h", rate / 1000)
        else
            return string.format("%d/h", rate)
        end
    end
end

-- Reposition active tiles horizontally (centered group)
local function RepositionActiveTiles(activeTiles)
    local tileCount = #activeTiles
    if tileCount == 0 then return end

    local tileWidth = 56
    local tileSpacing = 8
    local totalWidth = (tileCount * tileWidth) + ((tileCount - 1) * tileSpacing)
    local startX = -totalWidth / 2 + tileWidth / 2

    for i, state in ipairs(activeTiles) do
        local xOffset = startX + ((i - 1) * (tileWidth + tileSpacing))
        state.tile:ClearAllPoints()
        state.tile:SetPoint("TOP", hudFrame.title, "BOTTOM", xOffset, -8)
    end
end

-- Update micro-bars for collapsed state
local function UpdateMicroBars(session, metrics)
    local cfg = GoldPH_DB.settings.microBars

    -- Skip if paused (freeze bars)
    if GoldPH_SessionManager:IsPaused(session) then
        return
    end

    -- Time delta for peak decay
    local now = GetTime()
    local deltaMinutes = (now - lastUpdateTime) / 60
    lastUpdateTime = now

    local activeTiles = {}

    -- Update each metric
    for metricKey, state in pairs(metricStates) do
        local rawRate = 0
        local isActive = false

        -- Extract raw rate from metrics
        if metricKey == "gold" then
            rawRate = metrics.totalPerHour
            isActive = true
        elseif metricKey == "xp" then
            rawRate = metrics.xpPerHour or 0
            isActive = metrics.xpEnabled and rawRate > 0
        elseif metricKey == "rep" then
            rawRate = metrics.repPerHour or 0
            isActive = metrics.repEnabled and rawRate > 0
        elseif metricKey == "honor" then
            rawRate = metrics.honorPerHour or 0
            isActive = metrics.honorEnabled and rawRate > 0
        end

        if not isActive or not state.tile then
            if state.tile then state.tile:Hide() end
        else
            state.tile:Show()
            table.insert(activeTiles, state)

            -- Apply smoothing
            state.displayRate = SmoothRate(state.displayRate, rawRate, cfg.smoothingAlpha)

            -- Update peak (with optional decay)
            state.peak = DecayPeak(state.peak, state.displayRate, deltaMinutes, cfg.normalization)

            -- Normalize for bar
            local minFloor = cfg.minRefFloors[metricKey]
            local normalized = NormalizeRate(state.displayRate, state.peak, minFloor)

            -- Update bar fill
            state.bar:SetValue(normalized)

            -- Update text (avoid string churn)
            local newText = FormatRateForMicroBar(metricKey, state.displayRate)
            if state.lastUpdatedText ~= newText then
                state.valueText:SetText(newText)
                state.lastUpdatedText = newText
            end
        end
    end

    -- Reposition tiles horizontally
    RepositionActiveTiles(activeTiles)
end

-- Initialize HUD
function GoldPH_HUD:Initialize()
    -- Create main frame with BackdropTemplate for border support
    hudFrame = CreateFrame("Frame", "GoldPH_HUD_Frame", UIParent, "BackdropTemplate")
    hudFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)

    -- Apply WoW-themed backdrop (matches standard UI elements)
    hudFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    hudFrame:SetBackdropColor(0, 0, 0, 0.8)
    hudFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)

    -- Make it movable
    hudFrame:SetMovable(true)
    hudFrame:EnableMouse(true)
    hudFrame:RegisterForDrag("LeftButton")
    hudFrame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    hudFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
    end)

    -- Pause/Resume button (left of minimize) - same style as collapse/expand: two vertical lines (pause), right arrow (play)
    local pauseBtn = CreateFrame("Button", nil, hudFrame)
    pauseBtn:SetSize(16, 16)
    pauseBtn:SetPoint("TOPRIGHT", -4, -4)
    -- Same texture style as minMaxBtn (16x16 small button + same highlight)
    pauseBtn:SetNormalTexture("Interface\\Buttons\\UI-Button-Up")
    pauseBtn:SetPushedTexture("Interface\\Buttons\\UI-Button-Down")
    pauseBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    -- Symbol on top: two vertical lines (pause) or right arrow (play); updated in Update()
    local pauseBtnSymbol = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pauseBtnSymbol:SetPoint("CENTER", 0, 0)
    pauseBtnSymbol:SetText("||")  -- Pause: two vertical lines
    pauseBtnSymbol:SetTextColor(1, 1, 1)
    hudFrame.pauseBtnSymbol = pauseBtnSymbol
    pauseBtn:SetScript("OnClick", function()
        local session = GoldPH_SessionManager:GetActiveSession()
        if not session then return end
        if GoldPH_SessionManager:IsPaused(session) then
            GoldPH_SessionManager:ResumeSession()
        else
            GoldPH_SessionManager:PauseSession()
        end
        GoldPH_HUD:Update()
    end)
    pauseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local session = GoldPH_SessionManager:GetActiveSession()
        if session and GoldPH_SessionManager:IsPaused(session) then
            GameTooltip:SetText("Resume session")
        else
            GameTooltip:SetText("Pause session")
        end
        GameTooltip:Show()
    end)
    pauseBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    hudFrame.pauseBtn = pauseBtn

    -- Minimize/Maximize button (stock WoW +/- buttons)
    local minMaxBtn = CreateFrame("Button", nil, hudFrame)
    minMaxBtn:SetSize(16, 16)
    minMaxBtn:SetPoint("TOPRIGHT", pauseBtn, "TOPLEFT", -2, 0)
    minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
    minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    minMaxBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
    minMaxBtn:SetScript("OnClick", function()
        GoldPH_HUD:ToggleMinimize()
    end)
    hudFrame.minMaxBtn = minMaxBtn

    --------------------------------------------------
    -- Header (always visible in both collapsed and expanded states)
    --------------------------------------------------
    local headerYPos = -PADDING

    -- Title (always visible)
    local title = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, headerYPos)
    title:SetText("GoldPH")
    hudFrame.title = title

    -- Header line (gold + time) - split into two FontStrings for different colors
    -- Container frame to center both elements together
    local headerContainer = CreateFrame("Frame", nil, hudFrame)
    headerContainer:SetPoint("TOP", title, "BOTTOM", 0, -4)
    headerContainer:SetSize(FRAME_WIDTH, 14)  -- Height for one line
    hudFrame.headerContainer = headerContainer

    -- Gold portion (default color)
    local headerGold = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerGold:SetPoint("RIGHT", headerContainer, "CENTER", -6, 0)  -- Right side of center with spacing before separator
    headerGold:SetJustifyH("RIGHT")
    headerGold:SetText("0g")
    hudFrame.headerGold = headerGold

    -- Separator with spaces on both sides
    local headerSep = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerSep:SetPoint("CENTER", headerContainer, "CENTER", 0, 0)
    headerSep:SetText(" | ")  -- Space on both sides of pipe
    headerSep:SetTextColor(0.7, 0.7, 0.7)  -- Gray separator
    hudFrame.headerSep = headerSep

    -- Timer portion (different color - lighter/muted)
    local headerTimer = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTimer:SetPoint("LEFT", headerContainer, "CENTER", 6, 0)  -- Left side of center with spacing after separator
    headerTimer:SetJustifyH("LEFT")
    headerTimer:SetTextColor(0.8, 0.8, 0.8)  -- Lighter gray for timer
    headerTimer:SetText("0m")
    hudFrame.headerTimer = headerTimer

    --------------------------------------------------
    -- Micro-bar metric tiles (for collapsed state)
    --------------------------------------------------
    local tileWidth = 56
    local tileHeight = 50
    local colorKeys = { gold = "GOLD", xp = "XP", rep = "REP", honor = "HONOR" }

    for metricKey, state in pairs(metricStates) do
        -- Create tile container
        local tile = CreateFrame("Frame", nil, hudFrame)
        tile:SetSize(tileWidth, tileHeight)
        state.tile = tile

        -- Icon
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetPoint("TOP", tile, "TOP", 0, 0)
        icon:SetTexture(METRIC_ICONS[metricKey])
        state.icon = icon

        -- Rate text
        local rateText = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rateText:SetPoint("TOP", icon, "BOTTOM", 0, -2)
        rateText:SetJustifyH("CENTER")
        rateText:SetText("0/h")
        state.valueText = rateText

        -- Micro-bar background
        local barBg = CreateFrame("Frame", nil, tile, "BackdropTemplate")
        barBg:SetSize(tileWidth - 4, 6)
        barBg:SetPoint("TOP", rateText, "BOTTOM", 0, -2)
        barBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
        })
        local colorKey = colorKeys[metricKey]
        local bgColor = MICROBAR_COLORS[colorKey].bg
        barBg:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        -- StatusBar fill
        local bar = CreateFrame("StatusBar", nil, barBg)
        bar:SetAllPoints(barBg)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local fillColor = MICROBAR_COLORS[colorKey].fill
        bar:GetStatusBarTexture():SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
        state.bar = bar

        -- Initially hidden (will show when active)
        tile:Hide()
    end

    --------------------------------------------------
    -- Expanded display elements (shown only when expanded)
    --------------------------------------------------
    local yPos = headerYPos - 18 - 4 - 14  -- Title height + gap + headerLine height

    -- Separator line (WoW UI style horizontal rule)
    local sep1 = CreateFrame("Frame", nil, hudFrame)
    sep1:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, yPos - 4)  -- More top padding
    sep1:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -PADDING, yPos - 4)
    sep1:SetHeight(1)
    local sep1Tex = sep1:CreateTexture(nil, "ARTWORK")
    sep1Tex:SetAllPoints()
    sep1Tex:SetColorTexture(0.5, 0.5, 0.5, 0.5)  -- Gray semi-transparent line
    hudFrame.sep1 = sep1
    yPos = yPos - ROW_HEIGHT + 2  -- Less bottom padding

    -- Helper function to create a label/value row
    local function CreateRow(labelText, yOffset, isLarge)
        local font = isLarge and "GameFontNormal" or "GameFontNormalSmall"
        
        local label = hudFrame:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("TOPLEFT", LABEL_X, yOffset)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)
        
        local value = hudFrame:CreateFontString(nil, "OVERLAY", font)
        value:SetPoint("TOPRIGHT", -LABEL_X, yOffset)
        value:SetJustifyH("RIGHT")
        value:SetText("0g")
        
        return label, value
    end

    -- Gold row
    local goldLabel, goldValue = CreateRow("Gold", yPos, false)
    hudFrame.goldLabel = goldLabel
    hudFrame.goldValue = goldValue
    yPos = yPos - ROW_HEIGHT

    -- Gold per hour (indented)
    local goldHrLabel = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldHrLabel:SetPoint("TOPLEFT", LABEL_X + 10, yPos)
    goldHrLabel:SetJustifyH("LEFT")
    goldHrLabel:SetText("/hr")
    goldHrLabel:SetTextColor(1, 0.9, 0.5)  -- Lighter yellow instead of gray
    hudFrame.goldHrLabel = goldHrLabel

    local goldHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    goldHrValue:SetJustifyH("RIGHT")
    goldHrValue:SetText("0g")
    goldHrValue:SetTextColor(1, 0.9, 0.5)  -- Lighter yellow instead of gray
    hudFrame.goldHrValue = goldHrValue
    yPos = yPos - ROW_HEIGHT + 2

    -- Inventory row
    local invLabel, invValue = CreateRow("Inventory", yPos, false)
    hudFrame.invLabel = invLabel
    hudFrame.invValue = invValue
    yPos = yPos - ROW_HEIGHT

    -- Gathering row
    local gathLabel, gathValue = CreateRow("Gathering", yPos, false)
    hudFrame.gathLabel = gathLabel
    hudFrame.gathValue = gathValue
    yPos = yPos - ROW_HEIGHT

    -- Expenses row
    local expLabel, expValue = CreateRow("Expenses", yPos, false)
    hudFrame.expLabel = expLabel
    hudFrame.expValue = expValue
    yPos = yPos - ROW_HEIGHT

    -- Separator line before total (WoW UI style horizontal rule)
    local sep2 = CreateFrame("Frame", nil, hudFrame)
    sep2:SetPoint("TOPLEFT", hudFrame, "TOPLEFT", PADDING, yPos - 4)  -- More top padding
    sep2:SetPoint("TOPRIGHT", hudFrame, "TOPRIGHT", -PADDING, yPos - 4)
    sep2:SetHeight(1)
    local sep2Tex = sep2:CreateTexture(nil, "ARTWORK")
    sep2Tex:SetAllPoints()
    sep2Tex:SetColorTexture(0.5, 0.5, 0.5, 0.5)  -- Gray semi-transparent line
    hudFrame.sep2 = sep2
    yPos = yPos - ROW_HEIGHT + 2  -- Less bottom padding

    -- Total row (larger font)
    local totalLabel, totalValue = CreateRow("Total", yPos, true)
    hudFrame.totalLabel = totalLabel
    hudFrame.totalValue = totalValue
    yPos = yPos - ROW_HEIGHT - 2

    -- Total per hour (indented)
    local totalHrLabel = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalHrLabel:SetPoint("TOPLEFT", LABEL_X + 10, yPos)
    totalHrLabel:SetJustifyH("LEFT")
    totalHrLabel:SetText("/hr")
    totalHrLabel:SetTextColor(1, 0.9, 0.5)  -- Lighter yellow instead of gray
    hudFrame.totalHrLabel = totalHrLabel

    local totalHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    totalHrValue:SetJustifyH("RIGHT")
    totalHrValue:SetText("0g")
    totalHrValue:SetTextColor(1, 0.9, 0.5)  -- Lighter yellow instead of gray
    hudFrame.totalHrValue = totalHrValue

    -- Phase 9: XP/Rep/Honor rows (only shown if enabled; grouped below all gold totals)
    yPos = yPos - ROW_HEIGHT

    local xpLabel, xpValue = CreateRow("XP/hr", yPos, false)
    xpLabel:SetTextColor(0.6, 0.0, 1.0)   -- WoW-style purple for XP
    xpValue:SetTextColor(0.6, 0.0, 1.0)
    hudFrame.xpLabel = xpLabel
    hudFrame.xpValue = xpValue
    yPos = yPos - ROW_HEIGHT

    local repLabel, repValue = CreateRow("Rep/hr", yPos, false)
    repLabel:SetTextColor(0.0, 1.0, 0.0)  -- WoW-style green for reputation
    repValue:SetTextColor(0.0, 1.0, 0.0)
    hudFrame.repLabel = repLabel
    hudFrame.repValue = repValue
    yPos = yPos - ROW_HEIGHT

    local honorLabel, honorValue = CreateRow("Honor/hr", yPos, false)
    honorLabel:SetTextColor(1.0, 0.5, 0.0) -- WoW-style orange for honor
    honorValue:SetTextColor(1.0, 0.5, 0.0)
    hudFrame.honorLabel = honorLabel
    hudFrame.honorValue = honorValue

    -- Update loop
    hudFrame:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed

        -- Dynamic update interval
        local interval = UPDATE_INTERVAL  -- Default 1.0s
        local cfg = GoldPH_DB.settings.microBars
        if cfg.enabled and GoldPH_DB.settings.hudMinimized then
            interval = cfg.updateInterval  -- 0.25s for micro-bars
        end

        if updateTimer >= interval then
            GoldPH_HUD:Update()
            updateTimer = 0
        end
    end)

    -- Initial state: hide until session starts
    hudFrame:Hide()
end

-- Format money for accounting display (uses parentheses for negatives)
local function FormatAccounting(copper)
    if not copper or copper == 0 then
        return "0c"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoney(math.abs(copper))
    
    -- Never show parentheses for zero values
    if isNegative and formatted ~= "0c" then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Format money short for accounting display (uses parentheses for negatives)
local function FormatAccountingShort(copper)
    if not copper or copper == 0 then
        return "0g"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(copper))
    
    -- Never show parentheses for zero values
    if isNegative and formatted ~= "0g" then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Dynamically adjust HUD height based on the last visible row
local function UpdateHudHeight(lastElement)
    if not hudFrame or not lastElement or not lastElement:IsShown() then
        return
    end

    local top = hudFrame:GetTop()
    local bottom = lastElement:GetBottom()

    if not top or not bottom then
        return
    end

    -- Add a small padding below the last row
    local padding = 12
    local newHeight = (top - bottom) + padding

    -- Never shrink below the base expanded height
    if newHeight < FRAME_HEIGHT then
        newHeight = FRAME_HEIGHT
    end

    hudFrame:SetHeight(newHeight)
end

-- Update HUD display
function GoldPH_HUD:Update()
    if not hudFrame then
        return
    end

    local session = GoldPH_SessionManager:GetActiveSession()

    if not session then
        hudFrame:Hide()
        -- Reset metric states on session end
        for _, state in pairs(metricStates) do
            state.displayRate = 0
            state.peak = 0
            state.lastUpdatedText = ""
        end
        return
    end

    -- Show HUD if session active
    if not hudFrame:IsShown() then
        hudFrame:Show()
    end

    -- Get metrics
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local isPaused = GoldPH_SessionManager:IsPaused(session)

    -- Pause button symbol: two vertical lines (pause) when running, right arrow (play) when paused
    if hudFrame.pauseBtnSymbol then
        hudFrame.pauseBtnSymbol:SetText(isPaused and ">" or "||")
    end

    -- Header line (gold + time) - timer only; when paused use pronounced color (no extra text)
    hudFrame.headerGold:SetText(FormatAccounting(metrics.totalValue))
    hudFrame.headerTimer:SetText(GoldPH_SessionManager:FormatDuration(metrics.durationSec))
    if isPaused then
        hudFrame.headerTimer:SetTextColor(1, 0.45, 0.2)  -- Strong orange/amber when paused
    else
        hudFrame.headerTimer:SetTextColor(0.8, 0.8, 0.8)  -- Normal
    end

    -- Update micro-bars if collapsed and enabled
    local cfg = GoldPH_DB.settings.microBars
    if cfg.enabled and GoldPH_DB.settings.hudMinimized then
        UpdateMicroBars(session, metrics)
    end

    -- Gold (cash balance)
    hudFrame.goldValue:SetText(FormatAccounting(metrics.cash))
    hudFrame.goldHrValue:SetText(FormatAccountingShort(metrics.cashPerHour))

    -- Inventory (vendor trash + rare items, excluding gathering)
    local nonGatheringInventory = metrics.invVendorTrash + metrics.invRareMulti
    hudFrame.invValue:SetText(FormatAccounting(nonGatheringInventory))

    -- Gathering (ore, herbs, leather, cloth)
    hudFrame.gathValue:SetText(FormatAccounting(metrics.invGathering))

    -- Expenses (shown with parentheses since it's a deduction)
    if metrics.expenses > 0 then
        hudFrame.expValue:SetText("(" .. GoldPH_Ledger:FormatMoney(metrics.expenses) .. ")")
        hudFrame.expValue:SetTextColor(1, 0.5, 0.5)  -- Light red for expenses
    else
        hudFrame.expValue:SetText("0g")
        hudFrame.expValue:SetTextColor(1, 1, 1)
    end

    -- Phase 9: XP/Rep/Honor rows (only shown if metrics enabled and HUD expanded)
    local showMetricsRows = not GoldPH_DB.settings.hudMinimized

    -- XP row
    if showMetricsRows and metrics.xpEnabled and metrics.xpPerHour > 0 then
        local xpStr = metrics.xpPerHour >= 1000 and
            string.format("%.1fk", metrics.xpPerHour / 1000) or
            tostring(metrics.xpPerHour)
        hudFrame.xpValue:SetText(xpStr)
        hudFrame.xpLabel:Show()
        hudFrame.xpValue:Show()
    else
        hudFrame.xpLabel:Hide()
        hudFrame.xpValue:Hide()
    end

    -- Rep row
    if showMetricsRows and metrics.repEnabled and metrics.repPerHour > 0 then
        hudFrame.repValue:SetText(tostring(metrics.repPerHour))
        hudFrame.repLabel:Show()
        hudFrame.repValue:Show()
    else
        hudFrame.repLabel:Hide()
        hudFrame.repValue:Hide()
    end

    -- Honor row
    if showMetricsRows and metrics.honorEnabled and metrics.honorPerHour > 0 then
        hudFrame.honorValue:SetText(tostring(metrics.honorPerHour))
        hudFrame.honorLabel:Show()
        hudFrame.honorValue:Show()
    else
        hudFrame.honorLabel:Hide()
        hudFrame.honorValue:Hide()
    end

    -- Total value (cash + all inventory)
    hudFrame.totalValue:SetText(FormatAccounting(metrics.totalValue))
    hudFrame.totalHrValue:SetText(FormatAccountingShort(metrics.totalPerHour))

    -- Adjust HUD height based on the last visible row:
    -- default to totalHrLabel, but extend to last shown XP/Rep/Honor row if present
    local lastElement = hudFrame.totalHrLabel
    if showMetricsRows then
        if hudFrame.honorLabel:IsShown() then
            lastElement = hudFrame.honorLabel
        elseif hudFrame.repLabel:IsShown() then
            lastElement = hudFrame.repLabel
        elseif hudFrame.xpLabel:IsShown() then
            lastElement = hudFrame.xpLabel
        end
    end

    UpdateHudHeight(lastElement)
end

-- Show HUD
function GoldPH_HUD:Show()
    if hudFrame then
        hudFrame:Show()
        self:Update()

        -- Save visibility state
        GoldPH_DB.settings.hudVisible = true
    end
end

-- Hide HUD
function GoldPH_HUD:Hide()
    if hudFrame then
        hudFrame:Hide()

        -- Save visibility state
        GoldPH_DB.settings.hudVisible = false
    end
end

-- Toggle HUD visibility
function GoldPH_HUD:Toggle()
    if not hudFrame then
        return
    end

    if hudFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

-- Toggle minimize state
function GoldPH_HUD:ToggleMinimize()
    if not hudFrame then
        return
    end

    -- Toggle the minimized state
    GoldPH_DB.settings.hudMinimized = not GoldPH_DB.settings.hudMinimized
    self:ApplyMinimizeState()
end

-- Apply minimize/expand state to HUD
function GoldPH_HUD:ApplyMinimizeState()
    if not hudFrame then
        return
    end

    local isMinimized = GoldPH_DB.settings.hudMinimized

    -- Update button texture: "+" when minimized, "-" when expanded
    if isMinimized then
        hudFrame.minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
        hudFrame.minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-PlusButton-Down")
    else
        hudFrame.minMaxBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        hudFrame.minMaxBtn:SetPushedTexture("Interface\\Buttons\\UI-MinusButton-Down")
    end

    -- Header (title + headerLine) always visible in both states
    -- Only toggle expanded content below header
    local expandedElements = {
        hudFrame.sep1, hudFrame.sep2,
        hudFrame.goldLabel, hudFrame.goldValue,
        hudFrame.goldHrLabel, hudFrame.goldHrValue,
        hudFrame.invLabel, hudFrame.invValue,
        hudFrame.gathLabel, hudFrame.gathValue,
        hudFrame.expLabel, hudFrame.expValue,
        hudFrame.xpLabel, hudFrame.xpValue,      -- Phase 9
        hudFrame.repLabel, hudFrame.repValue,    -- Phase 9
        hudFrame.honorLabel, hudFrame.honorValue,-- Phase 9
        hudFrame.totalLabel, hudFrame.totalValue,
        hudFrame.totalHrLabel, hudFrame.totalHrValue,
    }

    for _, element in ipairs(expandedElements) do
        if isMinimized then
            element:Hide()
        else
            element:Show()
        end
    end

    -- Show/hide micro-bar tiles based on state
    -- When minimized: tiles will be shown/hidden by UpdateMicroBars based on activity
    -- When expanded: hide all tiles
    if not isMinimized then
        for _, state in pairs(metricStates) do
            if state.tile then
                state.tile:Hide()
            end
        end
    end

    -- Adjust frame height while maintaining top position
    -- Store current top position before changing height
    local point, relativeTo, relativePoint, xOfs, yOfs = hudFrame:GetPoint()
    
    if isMinimized then
        hudFrame:SetHeight(FRAME_HEIGHT_MINI)
    else
        hudFrame:SetHeight(FRAME_HEIGHT)
    end
    
    -- Restore top position to prevent jumping
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

    -- Update display
    self:Update()
end

-- Export module
_G.GoldPH_HUD = GoldPH_HUD
