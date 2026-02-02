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

    local yPos = -PADDING

    -- Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, yPos)
    title:SetText("GoldPH")
    hudFrame.title = title
    yPos = yPos - 18

    -- Session status (centered)
    local status = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOP", 0, yPos)
    status:SetText("No active session")
    hudFrame.status = status
    yPos = yPos - 16

    -- Separator line
    local sep1 = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sep1:SetPoint("TOPLEFT", LABEL_X, yPos)
    sep1:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    sep1:SetText("----------------")
    sep1:SetTextColor(0.5, 0.5, 0.5)
    yPos = yPos - ROW_HEIGHT

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
    goldHrLabel:SetTextColor(0.7, 0.7, 0.7)
    hudFrame.goldHrLabel = goldHrLabel

    local goldHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    goldHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    goldHrValue:SetJustifyH("RIGHT")
    goldHrValue:SetText("0g")
    goldHrValue:SetTextColor(0.7, 0.7, 0.7)
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

    -- Separator line before total
    local sep2 = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    sep2:SetPoint("TOPLEFT", LABEL_X, yPos)
    sep2:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    sep2:SetText("----------------")
    sep2:SetTextColor(0.5, 0.5, 0.5)
    yPos = yPos - ROW_HEIGHT

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
    totalHrLabel:SetTextColor(0.7, 0.7, 0.7)
    hudFrame.totalHrLabel = totalHrLabel

    local totalHrValue = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalHrValue:SetPoint("TOPRIGHT", -LABEL_X, yPos)
    totalHrValue:SetJustifyH("RIGHT")
    totalHrValue:SetText("0g")
    totalHrValue:SetTextColor(0.7, 0.7, 0.7)
    hudFrame.totalHrValue = totalHrValue

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
local function FormatAccountingShort(copper)
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

    -- Session status with duration
    hudFrame.status:SetText(string.format("#%d | %s",
        session.id,
        GoldPH_SessionManager:FormatDuration(metrics.durationSec)))

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

    -- Total value (cash + all inventory)
    hudFrame.totalValue:SetText(FormatAccounting(metrics.totalValue))
    hudFrame.totalHrValue:SetText(FormatAccountingShort(metrics.totalPerHour))
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

-- Export module
_G.GoldPH_HUD = GoldPH_HUD
