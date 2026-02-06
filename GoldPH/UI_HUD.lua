--[[
    UI_HUD.lua - Heads-up display for GoldPH

    Shows real-time session metrics in accounting-style layout.
]]

-- luacheck: globals GoldPH_Settings

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
-- Bottom visual padding: should match top (8px visual) + backdrop inset (4px) = 12px from frame bottom
-- Total: 12 (top) + 18 + 4 + 14 + 12 (bottom) = 60px
-- Reduced to 54px for better visual balance: 12 + 18 + 4 + 14 + 6 = 54px (~6px visual bottom padding)
local FRAME_HEIGHT_MINI = 54  -- Minimized height with consistent visual padding
local LABEL_X = PADDING
local VALUE_X = FRAME_WIDTH - PADDING  -- Right edge for right-aligned values
local ROW_HEIGHT = 14
local SECTION_GAP = 4

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

    -- Minimize/Maximize button (stock WoW +/- buttons)
    local minMaxBtn = CreateFrame("Button", nil, hudFrame)
    minMaxBtn:SetSize(16, 16)
    minMaxBtn:SetPoint("TOPRIGHT", -4, -4)  -- Tight in top-right corner
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
        if updateTimer >= UPDATE_INTERVAL then
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
        return
    end

    -- Show HUD if session active
    if not hudFrame:IsShown() then
        hudFrame:Show()
    end

    -- Get metrics
    local metrics = GoldPH_SessionManager:GetMetrics(session)

    -- Header line (gold + time) - update separately for different colors
    hudFrame.headerGold:SetText(FormatAccounting(metrics.totalValue))
    hudFrame.headerTimer:SetText(GoldPH_SessionManager:FormatDuration(metrics.durationSec))

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
    local showMetricsRows = not GoldPH_Settings.hudMinimized

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
        GoldPH_Settings.hudVisible = true
    end
end

-- Hide HUD
function GoldPH_HUD:Hide()
    if hudFrame then
        hudFrame:Hide()

        -- Save visibility state
        GoldPH_Settings.hudVisible = false
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
    GoldPH_Settings.hudMinimized = not GoldPH_Settings.hudMinimized
    self:ApplyMinimizeState()
end

-- Apply minimize/expand state to HUD
function GoldPH_HUD:ApplyMinimizeState()
    if not hudFrame then
        return
    end

    local isMinimized = GoldPH_Settings.hudMinimized

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
