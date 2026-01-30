--[[
    UI_HUD.lua - Heads-up display for GoldPH

    Shows real-time session metrics.
]]

local GoldPH_HUD = {}

local hudFrame = nil
local updateTimer = 0
local UPDATE_INTERVAL = 1.0 -- Update every 1 second

-- Initialize HUD
function GoldPH_HUD:Initialize()
    -- Create main frame
    hudFrame = CreateFrame("Frame", "GoldPH_HUD_Frame", UIParent)
    hudFrame:SetSize(240, 175)  -- Increased size for Phase 3 inventory tracking
    hudFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -200)

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

    -- Background
    local bg = hudFrame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(true)
    bg:SetColorTexture(0, 0, 0, 0.7)

    -- Title
    local title = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -5)
    title:SetText("GoldPH")
    hudFrame.title = title

    -- Session status
    local status = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    status:SetPoint("TOPLEFT", 10, -25)
    status:SetText("No active session")
    status:SetJustifyH("LEFT")
    hudFrame.status = status

    -- Time
    local timeText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    timeText:SetPoint("TOPLEFT", 10, -40)
    timeText:SetText("Time: --")
    timeText:SetJustifyH("LEFT")
    hudFrame.timeText = timeText

    -- Cash
    local cashText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cashText:SetPoint("TOPLEFT", 10, -55)
    cashText:SetText("Cash: 0c")
    cashText:SetJustifyH("LEFT")
    hudFrame.cashText = cashText

    -- Cash per hour
    local cashPerHourText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cashPerHourText:SetPoint("TOPLEFT", 10, -70)
    cashPerHourText:SetText("Cash/hr: 0c")
    cashPerHourText:SetJustifyH("LEFT")
    hudFrame.cashPerHourText = cashPerHourText

    -- Phase 2: Income
    local incomeText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    incomeText:SetPoint("TOPLEFT", 10, -85)
    incomeText:SetText("Income: 0c")
    incomeText:SetJustifyH("LEFT")
    hudFrame.incomeText = incomeText

    -- Phase 2: Expenses
    local expensesText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expensesText:SetPoint("TOPLEFT", 10, -100)
    expensesText:SetText("Expenses: 0c")
    expensesText:SetJustifyH("LEFT")
    hudFrame.expensesText = expensesText

    -- Phase 2: Net
    local netText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    netText:SetPoint("TOPLEFT", 10, -115)
    netText:SetText("Net: 0c")
    netText:SetJustifyH("LEFT")
    hudFrame.netText = netText

    -- Phase 3: Separator line
    local separator = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    separator:SetPoint("TOPLEFT", 10, -130)
    separator:SetText("---")
    separator:SetJustifyH("LEFT")
    hudFrame.separator = separator

    -- Phase 3: Expected inventory value
    local expectedText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expectedText:SetPoint("TOPLEFT", 10, -140)
    expectedText:SetText("Expected: 0c")
    expectedText:SetJustifyH("LEFT")
    hudFrame.expectedText = expectedText

    -- Phase 3: Total economic value per hour
    local totalPerHourText = hudFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalPerHourText:SetPoint("TOPLEFT", 10, -155)
    totalPerHourText:SetText("Total/hr: 0c")
    totalPerHourText:SetJustifyH("LEFT")
    hudFrame.totalPerHourText = totalPerHourText

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

    -- Update display
    hudFrame.status:SetText(string.format("Session #%d", session.id))
    hudFrame.timeText:SetText(string.format("Time: %s", GoldPH_SessionManager:FormatDuration(metrics.durationSec)))
    hudFrame.cashText:SetText(string.format("Cash: %s", GoldPH_Ledger:FormatMoney(metrics.cash)))
    hudFrame.cashPerHourText:SetText(string.format("Cash/hr: %s", GoldPH_Ledger:FormatMoney(metrics.cashPerHour)))

    -- Phase 2: Income/Expense breakdown
    hudFrame.incomeText:SetText(string.format("Income: %s", GoldPH_Ledger:FormatMoney(metrics.income)))
    hudFrame.expensesText:SetText(string.format("Expenses: %s", GoldPH_Ledger:FormatMoney(metrics.expenses)))
    local netCash = metrics.income - metrics.expenses
    hudFrame.netText:SetText(string.format("Net: %s", GoldPH_Ledger:FormatMoney(netCash)))

    -- Phase 3: Expected inventory and total economic value
    hudFrame.expectedText:SetText(string.format("Expected: %s", GoldPH_Ledger:FormatMoney(metrics.expectedInventory)))
    hudFrame.totalPerHourText:SetText(string.format("Total/hr: %s", GoldPH_Ledger:FormatMoney(metrics.totalPerHour)))
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
