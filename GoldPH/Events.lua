--[[
    Events.lua - Event handling and routing for GoldPH

    Handles WoW events and routes them to accounting actions.
]]

local GoldPH_Events = {}

-- Runtime state (not persisted)
local state = {
    moneyLast = nil,

    -- Phase 2: Merchant tracking
    merchantOpen = false,

    -- Phase 5+: taxiOpen
    -- Phase 6+: pickpocketActiveUntil, openingLockboxUntil, etc.
}

-- Initialize event system
function GoldPH_Events:Initialize(frame)
    -- Register events
    frame:RegisterEvent("CHAT_MSG_MONEY")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    -- Phase 5+: TAXIMAP_OPENED, TAXIMAP_CLOSED, QUEST_TURNED_IN, etc.

    -- Set event handler
    frame:SetScript("OnEvent", function(self, event, ...)
        GoldPH_Events:OnEvent(event, ...)
    end)

    -- Initialize money tracking
    state.moneyLast = GetMoney()

    -- Hook repair function (Phase 2)
    self:HookRepairFunctions()
end

-- Main event dispatcher
function GoldPH_Events:OnEvent(event, ...)
    if event == "CHAT_MSG_MONEY" then
        self:OnLootedCoin(...)
    elseif event == "MERCHANT_SHOW" then
        self:OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        self:OnMerchantClosed()
    end
    -- Phase 5+: Handle other events
end

-- Handle CHAT_MSG_MONEY event (looted coin)
function GoldPH_Events:OnLootedCoin(message)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Parse copper amount from message
    -- Example messages:
    -- "You loot 1 Gold, 23 Silver, 45 Copper."
    -- "You loot 5 Silver, 12 Copper."
    -- "You loot 42 Copper."
    local copper = self:ParseMoneyMessage(message)

    if copper and copper > 0 then
        -- Post double-entry: Dr Assets:Cash, Cr Income:LootedCoin
        GoldPH_Ledger:Post(session, "Assets:Cash", "Income:LootedCoin", copper)

        -- Debug logging
        if GoldPH_DB.debug.verbose then
            print(string.format("[GoldPH] Looted: %s", GoldPH_Ledger:FormatMoney(copper)))
        end

        -- Run invariants if debug mode enabled
        if GoldPH_DB.debug.enabled then
            GoldPH_Debug:ValidateInvariants(session)
        end

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Parse copper amount from CHAT_MSG_MONEY message
function GoldPH_Events:ParseMoneyMessage(message)
    local totalCopper = 0

    -- Match gold
    local gold = message:match("(%d+) Gold")
    if gold then
        totalCopper = totalCopper + tonumber(gold) * 10000
    end

    -- Match silver
    local silver = message:match("(%d+) Silver")
    if silver then
        totalCopper = totalCopper + tonumber(silver) * 100
    end

    -- Match copper
    local copper = message:match("(%d+) Copper")
    if copper then
        totalCopper = totalCopper + tonumber(copper)
    end

    return totalCopper
end

-- Inject a looted coin event (for testing)
function GoldPH_Events:InjectLootedCoin(copper)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not copper or copper <= 0 then
        return false, "Invalid copper amount"
    end

    -- Post directly (bypass CHAT_MSG_MONEY parsing)
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:LootedCoin", copper)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected loot: %s", GoldPH_Ledger:FormatMoney(copper)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 2: Merchant & Repair Tracking
--------------------------------------------------

-- Handle MERCHANT_SHOW event
function GoldPH_Events:OnMerchantShow()
    state.merchantOpen = true

    if GoldPH_DB.debug.verbose then
        print("[GoldPH] Merchant window opened")
    end
end

-- Handle MERCHANT_CLOSED event
function GoldPH_Events:OnMerchantClosed()
    state.merchantOpen = false

    if GoldPH_DB.debug.verbose then
        print("[GoldPH] Merchant window closed")
    end
end

-- Hook repair functions to track costs
function GoldPH_Events:HookRepairFunctions()
    -- Hook RepairAllItems (repair all button)
    hooksecurefunc("RepairAllItems", function(guildBankRepair)
        self:OnRepairAll(guildBankRepair)
    end)

    -- Note: We could also hook individual item repairs via UseContainerItem
    -- but RepairAllItems is the most common use case for Phase 2
end

-- Handle repair all action
function GoldPH_Events:OnRepairAll(guildBankRepair)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Don't track guild bank repairs (player doesn't pay)
    if guildBankRepair then
        return
    end

    -- Get repair cost
    local repairCost = GetRepairAllCost()

    if repairCost and repairCost > 0 then
        -- Check if player can afford it
        local playerMoney = GetMoney()
        if playerMoney < repairCost then
            return -- Repair will fail, don't record
        end

        -- Post expense: Cr Assets:Cash (decrease), Dr Expense:Repairs
        GoldPH_Ledger:Post(session, "Expense:Repairs", "Assets:Cash", repairCost)

        -- Debug logging
        if GoldPH_DB.debug.verbose then
            print(string.format("[GoldPH] Repair cost: %s", GoldPH_Ledger:FormatMoney(repairCost)))
        end

        -- Run invariants if debug mode enabled
        if GoldPH_DB.debug.enabled then
            GoldPH_Debug:ValidateInvariants(session)
        end

        -- Update HUD
        GoldPH_HUD:Update()
    end
end

-- Inject a repair event (for testing)
function GoldPH_Events:InjectRepair(copper)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not copper or copper <= 0 then
        return false, "Invalid copper amount"
    end

    -- Post directly: Dr Expense:Repairs, Cr Assets:Cash
    GoldPH_Ledger:Post(session, "Expense:Repairs", "Assets:Cash", copper)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected repair: %s", GoldPH_Ledger:FormatMoney(copper)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

-- Export module
_G.GoldPH_Events = GoldPH_Events
