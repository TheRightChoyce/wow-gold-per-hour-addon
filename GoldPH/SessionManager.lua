--[[
    SessionManager.lua - Session lifecycle management for GoldPH

    Handles session creation, persistence, and metrics computation.
]]

local GoldPH_SessionManager = {}

-- Start a new session
function GoldPH_SessionManager:StartSession()
    if GoldPH_DB.activeSession then
        return false, "A session is already active. Stop it first with /goldph stop"
    end

    -- Increment session ID
    GoldPH_DB.meta.lastSessionId = GoldPH_DB.meta.lastSessionId + 1
    local sessionId = GoldPH_DB.meta.lastSessionId

    -- Create new session
    local session = {
        id = sessionId,
        startedAt = time(),
        endedAt = nil,
        durationSec = 0,

        zone = GetZoneText() or "Unknown",

        -- Phase 3: Item tracking
        items = {},      -- [itemID] = ItemAgg (count, expected value, etc.)
        holdings = {},   -- [itemID] = { count, lots = { Lot, ... } }

        -- Phase 6: Pickpocket tracking
        pickpocket = {
            gold = 0,
            value = 0,
            lockboxesLooted = 0,
            lockboxesOpened = 0,
            fromLockbox = { gold = 0, value = 0 },
        },

        -- Phase 6: Gathering nodes (for future metrics)
        gathering = {
            totalNodes = 0,
            nodesByType = {},
        },
    }

    -- Initialize ledger
    GoldPH_Ledger:InitializeLedger(session)

    -- Set as active session
    GoldPH_DB.activeSession = session

    return true, "Session #" .. sessionId .. " started"
end

-- Stop the active session
function GoldPH_SessionManager:StopSession()
    if not GoldPH_DB.activeSession then
        return false, "No active session"
    end

    local session = GoldPH_DB.activeSession

    -- Finalize session
    session.endedAt = time()
    session.durationSec = session.endedAt - session.startedAt

    -- Save to history
    GoldPH_DB.sessions[session.id] = session

    -- Clear active session
    GoldPH_DB.activeSession = nil

    return true, "Session #" .. session.id .. " stopped and saved (duration: " ..
                 self:FormatDuration(session.durationSec) .. ")"
end

-- Get the active session (or nil)
function GoldPH_SessionManager:GetActiveSession()
    return GoldPH_DB.activeSession
end

-- Compute derived metrics for display
function GoldPH_SessionManager:GetMetrics(session)
    if not session then
        return nil
    end

    local durationSec
    if session.endedAt then
        durationSec = session.durationSec
    else
        durationSec = time() - session.startedAt
    end

    local durationHours = durationSec / 3600

    -- Phase 1 & 2: Cash and expenses
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashPerHour = 0
    if durationHours > 0 then
        cashPerHour = math.floor(cash / durationHours)
    end

    -- Phase 2: Income breakdown
    local income = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    -- Phase 2: Expense breakdown
    local expenseRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")
    local expenseVendorBuys = GoldPH_Ledger:GetBalance(session, "Expense:VendorBuys")
    local expenseTravel = GoldPH_Ledger:GetBalance(session, "Expense:Travel")  -- Phase 5
    local totalExpenses = expenseRepairs + expenseVendorBuys + expenseTravel

    -- Phase 5: Quest income
    local incomeQuest = GoldPH_Ledger:GetBalance(session, "Income:Quest")

    -- Phase 3: Expected inventory value
    local invVendorTrash = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:VendorTrash")
    local invRareMulti = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:RareMulti")
    local invGathering = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")
    local expectedInventory = invVendorTrash + invRareMulti + invGathering

    local expectedPerHour = 0
    if durationHours > 0 then
        expectedPerHour = math.floor(expectedInventory / durationHours)
    end

    -- Phase 3: Total economic value (net worth change)
    local totalValue = cash + expectedInventory
    local totalPerHour = 0
    if durationHours > 0 then
        totalPerHour = math.floor(totalValue / durationHours)
    end

    -- Phase 6: Pickpocket metrics
    local pickpocketGold = 0
    local pickpocketValue = 0
    local lockboxesLooted = 0
    local lockboxesOpened = 0
    local fromLockboxGold = 0
    local fromLockboxValue = 0

    if session.pickpocket then
        pickpocketGold = session.pickpocket.gold or 0
        pickpocketValue = session.pickpocket.value or 0
        lockboxesLooted = session.pickpocket.lockboxesLooted or 0
        lockboxesOpened = session.pickpocket.lockboxesOpened or 0
        if session.pickpocket.fromLockbox then
            fromLockboxGold = session.pickpocket.fromLockbox.gold or 0
            fromLockboxValue = session.pickpocket.fromLockbox.value or 0
        end
    end

    -- Also get ledger balances for reporting (source of truth)
    local incomePickpocketCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Coin")
    local incomePickpocketItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:Items")
    local incomePickpocketFromLockboxCoin = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Coin")
    local incomePickpocketFromLockboxItems = GoldPH_Ledger:GetBalance(session, "Income:Pickpocket:FromLockbox:Items")

    return {
        durationSec = durationSec,
        durationHours = durationHours,
        cash = cash,
        cashPerHour = cashPerHour,

        -- Phase 2: Income/Expense details
        income = income,
        expenses = totalExpenses,
        expenseRepairs = expenseRepairs,
        expenseVendorBuys = expenseVendorBuys,
        expenseTravel = expenseTravel,  -- Phase 5
        incomeQuest = incomeQuest,  -- Phase 5

        -- Phase 3: Expected inventory value
        expectedInventory = expectedInventory,
        expectedPerHour = expectedPerHour,
        invVendorTrash = invVendorTrash,
        invRareMulti = invRareMulti,
        invGathering = invGathering,

        -- Phase 3: Total economic value
        totalValue = totalValue,
        totalPerHour = totalPerHour,

        -- Phase 6: Pickpocket metrics
        pickpocketGold = pickpocketGold,
        pickpocketValue = pickpocketValue,
        lockboxesLooted = lockboxesLooted,
        lockboxesOpened = lockboxesOpened,
        fromLockboxGold = fromLockboxGold,
        fromLockboxValue = fromLockboxValue,
        -- Ledger balances (for reporting/debug)
        incomePickpocketCoin = incomePickpocketCoin,
        incomePickpocketItems = incomePickpocketItems,
        incomePickpocketFromLockboxCoin = incomePickpocketFromLockboxCoin,
        incomePickpocketFromLockboxItems = incomePickpocketFromLockboxItems,
    }
end

-- Format duration in human-readable form
function GoldPH_SessionManager:FormatDuration(seconds)
    local hours = math.floor(seconds / 3600)
    local mins = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60

    if hours > 0 then
        return string.format("%dh %dm %ds", hours, mins, secs)
    elseif mins > 0 then
        return string.format("%dm %ds", mins, secs)
    else
        return string.format("%ds", secs)
    end
end

-- Get session by ID
function GoldPH_SessionManager:GetSession(sessionId)
    return GoldPH_DB.sessions[sessionId]
end

-- List all sessions (newest first)
function GoldPH_SessionManager:ListSessions(limit)
    local sessions = {}
    for _, session in pairs(GoldPH_DB.sessions) do
        table.insert(sessions, session)
    end

    -- Sort by ID descending (newest first)
    table.sort(sessions, function(a, b) return a.id > b.id end)

    if limit then
        local limited = {}
        for i = 1, math.min(limit, #sessions) do
            table.insert(limited, sessions[i])
        end
        return limited
    end

    return sessions
end

--------------------------------------------------
-- Phase 3: Item Aggregation
--------------------------------------------------

-- Add or update item in session.items aggregate
function GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)
    if not session.items[itemID] then
        -- Create new item aggregate
        session.items[itemID] = {
            itemID = itemID,
            name = itemName,
            quality = quality,
            bucket = bucket,
            count = 0,
            expectedTotal = 0,
        }
    end

    -- Update counts
    session.items[itemID].count = session.items[itemID].count + count
    session.items[itemID].expectedTotal = session.items[itemID].expectedTotal + (count * expectedEach)
end

-- Export module
_G.GoldPH_SessionManager = GoldPH_SessionManager
