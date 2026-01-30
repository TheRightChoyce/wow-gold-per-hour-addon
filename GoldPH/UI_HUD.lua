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
    hudFrame:SetSize(200, 100)
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

    -- Phase 3+: Add expected inventory and total economic value
    -- hudFrame.expectedText:SetText(...)
    -- hudFrame.totalPerHourText:SetText(...)
end

-- Show HUD
function GoldPH_HUD:Show()
    if hudFrame then
        hudFrame:Show()
        self:Update()
    end
end

-- Hide HUD
function GoldPH_HUD:Hide()
    if hudFrame then
        hudFrame:Hide()
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
