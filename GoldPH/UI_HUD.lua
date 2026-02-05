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

-- Color helper function (for FontStrings)
local function SetValueColor(valueFontString, amount, isIncome, isExpense, isNet)
    if isExpense and amount < 0 then
        valueFontString:SetTextColor(1, 0.3, 0.3)  -- Red for expenses
    elseif isIncome and amount > 0 then
        valueFontString:SetTextColor(0.3, 1, 0.3)  -- Green for income
    elseif isNet then
        valueFontString:SetTextColor(1, 0.84, 0)  -- Gold/yellow for net/gold
    else
        valueFontString:SetTextColor(1, 1, 1)  -- White default
    end
end

-- Get color code string for text (for use in formatted strings)
function GoldPH_HUD:GetValueColorCode(amount, isIncome, isExpense, isNet)
    if isExpense and amount < 0 then
        return "|cffFF4D4D"  -- Red for expenses (1, 0.3, 0.3) -> FF4D4D
    elseif isIncome and amount > 0 then
        return "|cff4DFF4D"  -- Green for income (0.3, 1, 0.3) -> 4DFF4D
    elseif isNet then
        return "|cffFFD700"  -- Gold/yellow for net/gold (1, 0.84, 0) -> FFD700
    else
        return "|r"  -- White default (reset)
    end
end

-- Tooltip helper function
local function SetupTooltip(frame, tooltipText)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
end

-- Initialize HUD
function GoldPH_HUD:Initialize()
    -- Create main frame with BackdropTemplate for border support
    hudFrame = CreateFrame("Frame", "GoldPH_HUD_Frame", UIParent, "BackdropTemplate")
    hudFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    
    -- Restore saved position or use default
    if GoldPH_DB.settings.hudPoint then
        hudFrame:SetPoint(GoldPH_DB.settings.hudPoint, UIParent, GoldPH_DB.settings.hudRelativePoint, 
                         GoldPH_DB.settings.hudXOfs or 0, GoldPH_DB.settings.hudYOfs or 0)
    else
        hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)
    end
    
    -- Apply saved scale or use default
    hudFrame:SetScale(GoldPH_DB.settings.hudScale or 1.0)

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
        -- Save position to settings
        local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
        GoldPH_DB.settings.hudPoint = point
        GoldPH_DB.settings.hudRelativePoint = relativePoint
        GoldPH_DB.settings.hudXOfs = xOfs
        GoldPH_DB.settings.hudYOfs = yOfs
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
    SetupTooltip(headerContainer, "Total economic value (gold + inventory)")

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
    -- Tooltip already set on headerContainer above

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
    SetupTooltip(goldLabel, "Current gold balance (gold/silver/copper) in your bags")
    SetupTooltip(goldValue, "Current gold balance (gold/silver/copper) in your bags")
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
    SetupTooltip(goldHrLabel, "Gold earned per hour based on session duration")
    SetupTooltip(goldHrValue, "Gold earned per hour based on session duration")
    yPos = yPos - ROW_HEIGHT + 2

    -- Inventory row
    local invLabel, invValue = CreateRow("Inventory", yPos, false)
    hudFrame.invLabel = invLabel
    hudFrame.invValue = invValue
    SetupTooltip(invLabel, "Expected vendor/AH value of vendor trash and rare items (excluding gathering materials)")
    SetupTooltip(invValue, "Expected vendor/AH value of vendor trash and rare items (excluding gathering materials)")
    yPos = yPos - ROW_HEIGHT

    -- Gathering row
    local gathLabel, gathValue = CreateRow("Gathering", yPos, false)
    hudFrame.gathLabel = gathLabel
    hudFrame.gathValue = gathValue
    SetupTooltip(gathLabel, "Expected value of gathering materials (ore, herbs, leather, cloth)")
    SetupTooltip(gathValue, "Expected value of gathering materials (ore, herbs, leather, cloth)")
    yPos = yPos - ROW_HEIGHT

    -- Expenses row
    local expLabel, expValue = CreateRow("Expenses", yPos, false)
    hudFrame.expLabel = expLabel
    hudFrame.expValue = expValue
    SetupTooltip(expLabel, "Total expenses: repairs, vendor purchases, and travel costs")
    SetupTooltip(expValue, "Total expenses: repairs, vendor purchases, and travel costs")
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
    SetupTooltip(totalLabel, "Total economic value: gold + all inventory (expected liquidation value)")
    SetupTooltip(totalValue, "Total economic value: gold + all inventory (expected liquidation value)")
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
    SetupTooltip(totalHrLabel, "Total economic value per hour")
    SetupTooltip(totalHrValue, "Total economic value per hour")

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
function GoldPH_HUD:FormatAccounting(copper)
    if not copper then
        return "0g"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoney(math.abs(copper))
    
    if isNegative then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Format money short for accounting display (uses parentheses for negatives)
function GoldPH_HUD:FormatAccountingShort(copper)
    if not copper then
        return "0g"
    end
    
    local isNegative = copper < 0
    local formatted = GoldPH_Ledger:FormatMoneyShort(math.abs(copper))
    
    if isNegative then
        return "(" .. formatted .. ")"
    else
        return formatted
    end
end

-- Local wrappers for internal use (backward compatibility)
local function FormatAccounting(copper)
    return GoldPH_HUD:FormatAccounting(copper)
end

local function FormatAccountingShort(copper)
    return GoldPH_HUD:FormatAccountingShort(copper)
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
    SetValueColor(hudFrame.headerGold, metrics.totalValue, false, false, true)
    hudFrame.headerTimer:SetText(GoldPH_SessionManager:FormatDuration(metrics.durationSec))

    -- Gold balance
    hudFrame.goldValue:SetText(FormatAccounting(metrics.cash))
    SetValueColor(hudFrame.goldValue, metrics.cash, false, false, true)
    hudFrame.goldHrValue:SetText(FormatAccountingShort(metrics.cashPerHour))
    SetValueColor(hudFrame.goldHrValue, metrics.cashPerHour, false, false, true)

    -- Inventory (vendor trash + rare items, excluding gathering)
    local nonGatheringInventory = metrics.invVendorTrash + metrics.invRareMulti
    hudFrame.invValue:SetText(FormatAccounting(nonGatheringInventory))
    -- Keep white (neutral)

    -- Gathering (ore, herbs, leather, cloth)
    hudFrame.gathValue:SetText(FormatAccounting(metrics.invGathering))
    -- Keep white (neutral)
    -- Update gathering tooltip with node counts if available
    if metrics.gatheringTotalNodes and metrics.gatheringTotalNodes > 0 then
        local tooltipText = "Expected value of gathering materials (ore, herbs, leather, cloth)\nTotal nodes: " .. metrics.gatheringTotalNodes
        if metrics.gatheringNodesPerHour and metrics.gatheringNodesPerHour > 0 then
            tooltipText = tooltipText .. "\nNodes/hour: " .. metrics.gatheringNodesPerHour
        end
        -- Update tooltip dynamically (overrides the one set in Initialize)
        hudFrame.gathValue:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltipText, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end)
    else
        -- Restore default tooltip if no nodes
        SetupTooltip(hudFrame.gathValue, "Expected value of gathering materials (ore, herbs, leather, cloth)")
    end

    -- Expenses (shown with parentheses since it's a deduction)
    if metrics.expenses > 0 then
        hudFrame.expValue:SetText("(" .. GoldPH_Ledger:FormatMoney(metrics.expenses) .. ")")
        SetValueColor(hudFrame.expValue, -metrics.expenses, false, true, false)  -- Red for expenses
    else
        hudFrame.expValue:SetText("0g")
        hudFrame.expValue:SetTextColor(1, 1, 1)
    end

    -- Total value (gold + all inventory)
    hudFrame.totalValue:SetText(FormatAccounting(metrics.totalValue))
    SetValueColor(hudFrame.totalValue, metrics.totalValue, false, false, true)
    hudFrame.totalHrValue:SetText(FormatAccountingShort(metrics.totalPerHour))
    SetValueColor(hudFrame.totalHrValue, metrics.totalPerHour, false, false, true)
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
    -- Always use current frame position (not saved) to avoid stale values
    local topY = hudFrame:GetTop()
    local currentPoint, _, currentRelativePoint, currentXOfs, currentYOfs = hudFrame:GetPoint()
    
    -- Normalize anchor point to TOP-based (preserve horizontal component)
    local topAnchor = "TOP"
    if currentPoint == "TOPLEFT" or currentPoint == "LEFT" then
        topAnchor = "TOPLEFT"
    elseif currentPoint == "TOPRIGHT" or currentPoint == "RIGHT" then
        topAnchor = "TOPRIGHT"
    end
    
    -- Normalize relative point similarly
    local relativeTopAnchor = "TOP"
    if currentRelativePoint == "TOPLEFT" or currentRelativePoint == "LEFT" then
        relativeTopAnchor = "TOPLEFT"
    elseif currentRelativePoint == "TOPRIGHT" or currentRelativePoint == "RIGHT" then
        relativeTopAnchor = "TOPRIGHT"
    end
    
    -- Change height
    if isMinimized then
        hudFrame:SetHeight(FRAME_HEIGHT_MINI)
    else
        hudFrame:SetHeight(FRAME_HEIGHT)
    end
    
    -- Restore position: maintain top Y and preserve horizontal anchor
    hudFrame:ClearAllPoints()
    -- Calculate Y offset to maintain the same top Y position
    local relativeTopY = UIParent:GetTop()
    local yOfs = topY - relativeTopY
    hudFrame:SetPoint(topAnchor, UIParent, relativeTopAnchor, currentXOfs, yOfs)
    
    -- Update saved position with new Y offset but preserve anchor point
    GoldPH_DB.settings.hudPoint = topAnchor
    GoldPH_DB.settings.hudRelativePoint = relativeTopAnchor
    GoldPH_DB.settings.hudXOfs = currentXOfs
    GoldPH_DB.settings.hudYOfs = yOfs

    -- Update display
    self:Update()
end

-- Set HUD scale
function GoldPH_HUD:SetScale(scale)
    if hudFrame then
        hudFrame:SetScale(scale)
    end
end

-- Export module
_G.GoldPH_HUD = GoldPH_HUD
