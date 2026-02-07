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
-- Calculate minimized height for horizontal bar:
-- Top padding: 12px (PADDING)
-- Title row: ~14px (12px font + line height)
-- Gap between title and tiles: 6px
-- Tile height: 18px (icon/text row 12px + 2px gap + bar 4px)
-- Bottom padding: 4px (reduced for compact layout)
-- Total: 12 + 14 + 6 + 18 + 4 = 54px
local FRAME_HEIGHT_MINI = 54  -- Minimized height with horizontal micro-bars
local LABEL_X = PADDING
local VALUE_X = FRAME_WIDTH - PADDING  -- Right edge for right-aligned values
local ROW_HEIGHT = 14
local SECTION_GAP = 4

-- pH Brand colors (from PH_BRAND_BRIEF.md - Classic-safe)
local PH_TEXT_PRIMARY = {0.86, 0.82, 0.70}
local PH_TEXT_MUTED = {0.62, 0.58, 0.50}
local PH_ACCENT_GOOD = {0.25, 0.78, 0.42}
local PH_ACCENT_NEUTRAL = {0.55, 0.70, 0.55}
local PH_BG_DARK = {0.08, 0.07, 0.06, 0.85}
local PH_BG_PARCHMENT = {0.18, 0.16, 0.13, 0.85}
local PH_BORDER_BRONZE = {0.52, 0.42, 0.28}

-- Additional pH brand tokens
local PH_ACCENT_WARNING = {0.90, 0.65, 0.20}  -- Warm amber for expenses/warnings
local PH_ACCENT_GOLD_INCOME = {1.00, 0.82, 0.00}  -- Classic gold for income highlights
local PH_TEXT_DISABLED = {0.45, 0.42, 0.38}  -- Darker muted for disabled/inactive
local PH_HOVER = {0.22, 0.20, 0.17, 0.60}  -- Subtle hover state
local PH_SELECTED = {0.35, 0.32, 0.26, 0.75}  -- Selected row/item
local PH_DIVIDER = {0.28, 0.25, 0.22, 0.50}  -- Separator lines

-- Micro-bar colors (pH brand palette)
local MICROBAR_COLORS = {
    GOLD = {
        fill = {1.00, 0.82, 0.00, 0.85},  -- Classic gold
        bg = PH_BG_DARK
    },
    XP = {
        fill = {0.58, 0.51, 0.79, 0.85},  -- Classic purple XP bar
        bg = PH_BG_DARK
    },
    REP = {
        fill = PH_ACCENT_GOOD,  -- Alchemy green
        bg = PH_BG_DARK
    },
    HONOR = {
        fill = {0.90, 0.60, 0.20, 0.85},  -- Classic honor orange
        bg = PH_BG_DARK
    },
}

local METRIC_ICONS = {
    gold = "Interface\\MoneyFrame\\UI-GoldIcon",
    xp = "Interface\\Icons\\INV_Misc_Book_11",  -- Book icon for learning/XP
    rep = "Interface\\Icons\\INV_Misc_Ribbon_01",  -- Ribbon for reputation
    honor = "Interface\\Icons\\inv_bannerpvp_02",  -- PvP banner (exists in Classic, wowhead 132486)
}

-- Color keys mapping for micro-bar colors
local colorKeys = { gold = "GOLD", xp = "XP", rep = "REP", honor = "HONOR" }

-- Runtime state for micro-bars (not persisted)
local metricStates = {
    gold = { key = "gold", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    xp = { key = "xp", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    rep = { key = "rep", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
    honor = { key = "honor", displayRate = 0, peak = 0, lastUpdatedText = "", tile = nil, bar = nil, valueText = nil, icon = nil },
}

-- Fixed order for metric display: gold, rep, xp, honor
local METRIC_ORDER = { "gold", "rep", "xp", "honor" }

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

-- Format rate for micro-bar display (ultra-compact, no /h suffix to save space)
local function FormatRateForMicroBar(metricKey, rate)
    if metricKey == "gold" then
        -- Inline FormatAccountingShort logic for gold
        if not rate or rate == 0 then
            return "0g"
        end
        local isNegative = rate < 0
        local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(rate))
        if isNegative and formatted ~= "0g" then
            return "(" .. formatted .. ")"
        else
            return formatted
        end
    elseif metricKey == "xp" then
        if rate >= 1000 then
            return string.format("%.1fk", rate / 1000)
        else
            return string.format("%d", rate)
        end
    elseif metricKey == "rep" then
        return string.format("%d", rate)
    elseif metricKey == "honor" then
        if rate >= 1000 then
            return string.format("%.1fk", rate / 1000)
        else
            return string.format("%d", rate)
        end
    end
end

-- Reposition tiles horizontally in fixed order (gold, rep, xp, honor)
local function RepositionTiles(isCollapsed)
    local tileWidth = 50
    local tileSpacing = 14
    local orderedTiles = {}
    
    -- Build ordered list of tiles (all tiles, in fixed order)
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile then
            table.insert(orderedTiles, state)
        end
    end
    
    local tileCount = #orderedTiles
    if tileCount == 0 then return end

    if isCollapsed then
        -- Horizontal layout: position tiles starting from left edge, below title row
        -- Position tiles so they don't overflow the top border
        for i, state in ipairs(orderedTiles) do
            state.tile:ClearAllPoints()
            if i == 1 then
                -- First tile: start at left edge (PADDING), below title row
                -- Use TOP anchor with negative offset to position below timer
                state.tile:SetPoint("TOP", hudFrame.headerTimer, "BOTTOM", 0, -6)
                state.tile:SetPoint("LEFT", hudFrame, "LEFT", PADDING, 0)
            else
                -- Subsequent tiles: position to right of previous tile, aligned at top
                state.tile:SetPoint("TOP", orderedTiles[1].tile, "TOP", 0, 0)
                state.tile:SetPoint("LEFT", orderedTiles[i-1].tile, "RIGHT", tileSpacing, 0)
            end
        end
    else
        -- Expanded layout: centered below header container
        local totalWidth = (tileCount * tileWidth) + ((tileCount - 1) * tileSpacing)
        local startX = -totalWidth / 2 + tileWidth / 2
        for i, state in ipairs(orderedTiles) do
            local xOffset = startX + ((i - 1) * (tileWidth + tileSpacing))
            state.tile:ClearAllPoints()
            state.tile:SetPoint("TOP", hudFrame.headerContainer, "BOTTOM", xOffset, -8)
        end
    end
end

-- Update micro-bars for collapsed state
local function UpdateMicroBars(session, metrics)
    local cfg = GoldPH_DB.settings.microBars
    if not cfg then return end

    -- Skip if paused (freeze bars)
    local isPaused = GoldPH_SessionManager:IsPaused(session)
    if isPaused then
        -- When paused, keep current display but don't update
        RepositionTiles(true)
        return
    end

    -- Time delta for peak decay
    local now = GetTime()
    local deltaMinutes = (now - lastUpdateTime) / 60
    lastUpdateTime = now

    -- Update each metric in fixed order
    for _, metricKey in ipairs(METRIC_ORDER) do
        local state = metricStates[metricKey]
        if state and state.tile then
            local rawRate = 0
            local isActive = false

            -- Extract raw rate from metrics
            if metricKey == "gold" then
                rawRate = metrics.totalPerHour
                isActive = true  -- Gold is always active
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

            -- Always show tiles, but gray out inactive ones
            state.tile:Show()
            state.icon:Show()  -- Ensure icon is always visible

            if isActive then
                -- Active: normal colors and updates
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

                -- Set active colors (full opacity)
                state.icon:SetVertexColor(1, 1, 1)  -- Full color, no tinting
                state.icon:SetAlpha(1.0)  -- Full opacity
                state.valueText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
                local colorKey = colorKeys[metricKey]
                local fillColor = MICROBAR_COLORS[colorKey].fill
                state.bar:GetStatusBarTexture():SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
            else
                -- Inactive: gray out (reduced opacity)
                state.bar:SetValue(0)  -- Empty bar
                state.valueText:SetText("0")
                
                -- Gray out icon (keep visible but muted - use gray tint with reduced opacity)
                state.icon:SetVertexColor(0.6, 0.6, 0.6)  -- Gray tint
                state.icon:SetAlpha(0.7)  -- Reduced opacity but still visible
                state.icon:Show()  -- Ensure icon is always visible
                state.valueText:SetTextColor(0.4, 0.4, 0.4, 0.5)
                -- Gray out bar fill
                state.bar:GetStatusBarTexture():SetVertexColor(0.3, 0.3, 0.3, 0.3)
            end
        end
    end

    -- Reposition tiles horizontally in fixed order (collapsed layout)
    RepositionTiles(true)
end

-- Initialize HUD
function GoldPH_HUD:Initialize()
    -- Create main frame with BackdropTemplate for border support
    hudFrame = CreateFrame("Frame", "GoldPH_HUD_Frame", UIParent, "BackdropTemplate")
    hudFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)

    -- Apply WoW-themed backdrop with pH brand colors
    hudFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    -- Use pH brand parchment background
    hudFrame:SetBackdropColor(PH_BG_PARCHMENT[1], PH_BG_PARCHMENT[2], PH_BG_PARCHMENT[3], PH_BG_PARCHMENT[4])
    -- Use pH brand bronze border
    hudFrame:SetBackdropBorderColor(PH_BORDER_BRONZE[1], PH_BORDER_BRONZE[2], PH_BORDER_BRONZE[3], 1)

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
    -- Symbol on top: two vertical bars (pause) or right arrow (play); updated in Update()
    local pauseBarLeft = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pauseBarLeft:SetPoint("CENTER", -2, 0)
    pauseBarLeft:SetText("|")
    pauseBarLeft:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    local pauseBarRight = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pauseBarRight:SetPoint("CENTER", 2, 0)
    pauseBarRight:SetText("|")
    pauseBarRight:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    local pausePlayArrow = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pausePlayArrow:SetPoint("CENTER", 0, 0)
    pausePlayArrow:SetText(">")
    pausePlayArrow:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])
    pausePlayArrow:Hide()
    hudFrame.pauseBarLeft = pauseBarLeft
    hudFrame.pauseBarRight = pauseBarRight
    hudFrame.pausePlayArrow = pausePlayArrow
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

    -- Title (always visible) - "pH" branding (lowercase p, uppercase H)
    local title = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PADDING, headerYPos)
    title:SetText("pH")
    title:SetTextColor(PH_TEXT_PRIMARY[1], PH_TEXT_PRIMARY[2], PH_TEXT_PRIMARY[3])  -- pH brand primary text
    -- Apply Friz Quadrata font per brand brief (WoW's built-in font)
    title:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    hudFrame.title = title

    -- Timer (always visible, next to title)
    local headerTimer = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTimer:SetPoint("LEFT", title, "RIGHT", 6, 0)
    headerTimer:SetJustifyH("LEFT")
    headerTimer:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])  -- pH brand muted text
    headerTimer:SetText("0m")
    hudFrame.headerTimer = headerTimer

    -- Header container (for backward compatibility, positioned below title row for expanded state)
    local headerContainer = CreateFrame("Frame", nil, hudFrame)
    headerContainer:SetPoint("TOP", title, "BOTTOM", 0, -4)
    headerContainer:SetSize(FRAME_WIDTH, 14)  -- Height for one line
    hudFrame.headerContainer = headerContainer

    -- Gold portion (for expanded state)
    local headerGold = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerGold:SetPoint("RIGHT", headerContainer, "CENTER", -6, 0)
    headerGold:SetJustifyH("RIGHT")
    headerGold:SetText("0g")
    hudFrame.headerGold = headerGold

    -- Separator (for expanded state)
    local headerSep = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerSep:SetPoint("CENTER", headerContainer, "CENTER", 0, 0)
    headerSep:SetText(" | ")
    headerSep:SetTextColor(0.7, 0.7, 0.7)
    hudFrame.headerSep = headerSep

    -- Timer duplicate for expanded state (keep for compatibility)
    local headerTimer2 = headerContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerTimer2:SetPoint("LEFT", headerContainer, "CENTER", 6, 0)
    headerTimer2:SetJustifyH("LEFT")
    headerTimer2:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
    headerTimer2:SetText("0m")
    hudFrame.headerTimer2 = headerTimer2

    --------------------------------------------------
    -- Micro-bar metric tiles (for collapsed state - single horizontal line)
    --------------------------------------------------
    local tileWidth = 50
    -- Tile height: 18px (icon/text row 12px + 2px gap + bar 4px)
    local tileHeight = 18

    for metricKey, state in pairs(metricStates) do
        -- Create tile container
        local tile = CreateFrame("Frame", nil, hudFrame)
        tile:SetSize(tileWidth, tileHeight)
        state.tile = tile

        -- Icon (compact, positioned at top left) - 12px for ultra-compact
        local icon = tile:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        icon:SetTexture(METRIC_ICONS[metricKey])
        state.icon = icon

        -- Rate text (pH brand muted color, compact) - positioned after icon, top-aligned
        local rateText = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rateText:SetPoint("LEFT", icon, "RIGHT", 2, 0)
        rateText:SetPoint("TOP", tile, "TOP", 0, 0)
        rateText:SetJustifyH("LEFT")
        rateText:SetText("0")
        rateText:SetTextColor(PH_TEXT_MUTED[1], PH_TEXT_MUTED[2], PH_TEXT_MUTED[3])
        state.valueText = rateText

        -- Micro-bar background (pH brand dark background) - full width below icon/text, 4px height
        local barBg = CreateFrame("Frame", nil, tile, "BackdropTemplate")
        -- Bar spans from left edge to right edge of tile (full width)
        barBg:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, -14)  -- Below icon/text row (12px + 2px gap)
        barBg:SetPoint("TOPRIGHT", tile, "TOPRIGHT", 0, -14)
        barBg:SetHeight(4)  -- 4px tall bar
        barBg:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            tile = true,
            tileSize = 16,
        })
        local colorKey = colorKeys[metricKey]
        local bgColor = MICROBAR_COLORS[colorKey].bg
        barBg:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

        -- StatusBar fill (pH brand colors)
        local bar = CreateFrame("StatusBar", nil, barBg)
        bar:SetAllPoints(barBg)
        bar:SetMinMaxValues(0, 1)
        bar:SetValue(0)
        bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
        local fillColor = MICROBAR_COLORS[colorKey].fill
        bar:GetStatusBarTexture():SetVertexColor(fillColor[1], fillColor[2], fillColor[3], fillColor[4])
        state.bar = bar

        -- Initially hidden (will be shown and positioned by UpdateMicroBars when session is active)
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
    sep1Tex:SetColorTexture(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], PH_DIVIDER[4])
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
    goldHrLabel:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
    hudFrame.goldHrLabel = goldHrLabel

    local goldHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    goldHrValue:SetJustifyH("RIGHT")
    goldHrValue:SetText("0g")
    goldHrValue:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
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
    sep2Tex:SetColorTexture(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], PH_DIVIDER[4])
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
    totalHrLabel:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
    hudFrame.totalHrLabel = totalHrLabel

    local totalHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    totalHrValue:SetJustifyH("RIGHT")
    totalHrValue:SetText("0g")
    totalHrValue:SetTextColor(PH_ACCENT_GOLD_INCOME[1], PH_ACCENT_GOLD_INCOME[2], PH_ACCENT_GOLD_INCOME[3])
    hudFrame.totalHrValue = totalHrValue

    -- Phase 9: XP/Rep/Honor rows (only shown if enabled; grouped below all gold totals)
    yPos = yPos - ROW_HEIGHT

    local xpLabel, xpValue = CreateRow("XP/hr", yPos, false)
    local xpColor = MICROBAR_COLORS.XP.fill
    xpLabel:SetTextColor(xpColor[1], xpColor[2], xpColor[3])
    xpValue:SetTextColor(xpColor[1], xpColor[2], xpColor[3])
    hudFrame.xpLabel = xpLabel
    hudFrame.xpValue = xpValue
    yPos = yPos - ROW_HEIGHT

    local repLabel, repValue = CreateRow("Rep/hr", yPos, false)
    local repColor = MICROBAR_COLORS.REP.fill
    repLabel:SetTextColor(repColor[1], repColor[2], repColor[3])
    repValue:SetTextColor(repColor[1], repColor[2], repColor[3])
    hudFrame.repLabel = repLabel
    hudFrame.repValue = repValue
    yPos = yPos - ROW_HEIGHT

    local honorLabel, honorValue = CreateRow("Honor/hr", yPos, false)
    local honorColor = MICROBAR_COLORS.HONOR.fill
    honorLabel:SetTextColor(honorColor[1], honorColor[2], honorColor[3])
    honorValue:SetTextColor(honorColor[1], honorColor[2], honorColor[3])
    hudFrame.honorLabel = honorLabel
    hudFrame.honorValue = honorValue

    -- Update loop
    hudFrame:SetScript("OnUpdate", function(self, elapsed)
        updateTimer = updateTimer + elapsed

        -- Dynamic update interval
        local interval = UPDATE_INTERVAL  -- Default 1.0s
        local cfg = GoldPH_DB.settings.microBars
        if cfg and cfg.enabled and GoldPH_DB.settings.hudMinimized then
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

    -- Pause button: two vertical bars (||) when running, right arrow (>) when paused
    if hudFrame.pauseBarLeft and hudFrame.pauseBarRight and hudFrame.pausePlayArrow then
        if isPaused then
            hudFrame.pauseBarLeft:Hide()
            hudFrame.pauseBarRight:Hide()
            hudFrame.pausePlayArrow:Show()
        else
            hudFrame.pauseBarLeft:Show()
            hudFrame.pauseBarRight:Show()
            hudFrame.pausePlayArrow:Hide()
        end
    end

    -- Update timers (both collapsed and expanded versions) with pH brand colors
    local timerText = GoldPH_SessionManager:FormatDuration(metrics.durationSec)
    -- Use pH ACCENT_BAD for paused (red), pH TEXT_MUTED for normal
    local timerColor = isPaused and {0.78, 0.32, 0.28} or PH_TEXT_MUTED

    hudFrame.headerTimer:SetText(timerText)
    hudFrame.headerTimer:SetTextColor(timerColor[1], timerColor[2], timerColor[3])

    if hudFrame.headerTimer2 then
        hudFrame.headerTimer2:SetText(timerText)
        hudFrame.headerTimer2:SetTextColor(timerColor[1], timerColor[2], timerColor[3])
    end

    -- Update gold in expanded header
    hudFrame.headerGold:SetText(FormatAccounting(metrics.totalValue))

    -- Update micro-bars if collapsed and enabled
    local cfg = GoldPH_DB.settings.microBars
    if cfg and cfg.enabled and GoldPH_DB.settings.hudMinimized then
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
        hudFrame.expValue:SetTextColor(PH_ACCENT_WARNING[1], PH_ACCENT_WARNING[2], PH_ACCENT_WARNING[3])
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

    -- Header: title always visible; gold | timer line only when expanded (collapsed uses micro-bar icons)
    if hudFrame.headerContainer then
        if isMinimized then
            hudFrame.headerContainer:Hide()
        else
            hudFrame.headerContainer:Show()
        end
    end

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
    -- When minimized: tiles are always shown (grayed out if inactive)
    -- When expanded: hide tiles (expanded view shows full details)
    if isMinimized then
        -- Tiles will be positioned and updated by UpdateMicroBars
        RepositionTiles(true)
    else
        -- Expanded: hide microbar tiles (full expanded view is shown instead)
        for _, metricKey in ipairs(METRIC_ORDER) do
            local state = metricStates[metricKey]
            if state and state.tile then
                state.tile:Hide()
            end
        end
    end

    -- Adjust frame size while maintaining top position
    -- Store current top position before changing size
    local point, relativeTo, relativePoint, xOfs, yOfs = hudFrame:GetPoint()

    if isMinimized then
        hudFrame:SetHeight(FRAME_HEIGHT_MINI)
        -- Frame width for exactly 4 metrics: left pad + 4*tile + 3*gap + right pad
        -- PADDING (12) + 4*50 + 3*14 + PADDING (12) = 12 + 200 + 42 + 12 = 266
        hudFrame:SetWidth(266)
    else
        hudFrame:SetHeight(FRAME_HEIGHT)
        hudFrame:SetWidth(FRAME_WIDTH)
    end

    -- Restore top position to prevent jumping
    hudFrame:ClearAllPoints()
    hudFrame:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)

    -- Update display
    self:Update()
end

-- Export module
_G.GoldPH_HUD = GoldPH_HUD
