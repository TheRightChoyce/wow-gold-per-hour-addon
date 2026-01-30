--[[
    Ledger.lua - Double-entry bookkeeping for GoldPH

    Provides core accounting functions following double-entry principles.
    All values are in copper (integers).
]]

local GoldPH_Ledger = {}

-- Initialize ledger structure in a session
function GoldPH_Ledger:InitializeLedger(session)
    session.ledger = {
        balances = {
            -- Assets
            ["Assets:Cash"] = 0,

            -- Income
            ["Income:LootedCoin"] = 0,

            -- Expenses (Phase 2)
            ["Expense:Repairs"] = 0,
            ["Expense:VendorBuys"] = 0,

            -- Note: Additional accounts will be added in later phases:
            -- Assets:Inventory:*, Income:ItemsLooted:*, Equity:*
        }
    }
end

-- Post a double-entry transaction
-- @param session: Current session object
-- @param debitAccount: Account to debit
-- @param creditAccount: Account to credit
-- @param amountCopper: Amount in copper (integer, must be positive)
-- @param meta: Optional metadata table {tags = {...}, ...}
--
-- Accounting Rules:
-- - Assets/Expenses: Debit increases, Credit decreases
-- - Income/Equity: Debit decreases, Credit increases
function GoldPH_Ledger:Post(session, debitAccount, creditAccount, amountCopper, meta)
    if not session or not session.ledger then
        error("GoldPH_Ledger:Post - Invalid session")
    end

    if amountCopper < 0 then
        error("GoldPH_Ledger:Post - Amount must be positive: " .. amountCopper)
    end

    if amountCopper == 0 then
        return -- No-op for zero amounts
    end

    -- Ensure accounts exist
    if not session.ledger.balances[debitAccount] then
        session.ledger.balances[debitAccount] = 0
    end
    if not session.ledger.balances[creditAccount] then
        session.ledger.balances[creditAccount] = 0
    end

    -- Apply double-entry with proper debit/credit rules
    -- Debit: Add to Assets/Expenses, Subtract from Income/Equity
    if debitAccount:match("^Assets:") or debitAccount:match("^Expense:") then
        session.ledger.balances[debitAccount] = session.ledger.balances[debitAccount] + amountCopper
    else -- Income or Equity
        session.ledger.balances[debitAccount] = session.ledger.balances[debitAccount] - amountCopper
    end

    -- Credit: Subtract from Assets/Expenses, Add to Income/Equity
    if creditAccount:match("^Assets:") or creditAccount:match("^Expense:") then
        session.ledger.balances[creditAccount] = session.ledger.balances[creditAccount] - amountCopper
    else -- Income or Equity
        session.ledger.balances[creditAccount] = session.ledger.balances[creditAccount] + amountCopper
    end

    -- Optional: Store posting for audit trail (Phase 1 MVP: skip this)
    -- if GoldPH_DB.debug.verbose then
    --     table.insert(session.ledger.postings, {...})
    -- end
end

-- Add to a balance directly (use with caution - prefer Post() for double-entry)
-- This is useful for adjustments where the offsetting entry is complex
function GoldPH_Ledger:AddBalance(session, account, deltaCopper)
    if not session or not session.ledger then
        error("GoldPH_Ledger:AddBalance - Invalid session")
    end

    if not session.ledger.balances[account] then
        session.ledger.balances[account] = 0
    end

    session.ledger.balances[account] = session.ledger.balances[account] + deltaCopper
end

-- Get current balance for an account
function GoldPH_Ledger:GetBalance(session, account)
    if not session or not session.ledger then
        return 0
    end
    return session.ledger.balances[account] or 0
end

-- Get all balances matching a pattern
function GoldPH_Ledger:GetBalancesMatching(session, pattern)
    local result = {}
    if not session or not session.ledger then
        return result
    end

    for account, balance in pairs(session.ledger.balances) do
        if account:match(pattern) then
            result[account] = balance
        end
    end

    return result
end

-- Format copper amount as gold.silver.copper string
function GoldPH_Ledger:FormatMoney(copper)
    if not copper or copper == 0 then
        return "0c"
    end

    -- Handle negative values
    local isNegative = copper < 0
    local absCopper = math.abs(copper)

    local gold = math.floor(absCopper / 10000)
    local silver = math.floor((absCopper % 10000) / 100)
    local copperRem = absCopper % 100

    local result = ""

    if gold > 0 then
        if silver > 0 or copperRem > 0 then
            result = string.format("%dg %ds %dc", gold, silver, copperRem)
        else
            result = string.format("%dg", gold)
        end
    elseif silver > 0 then
        if copperRem > 0 then
            result = string.format("%ds %dc", silver, copperRem)
        else
            result = string.format("%ds", silver)
        end
    else
        result = string.format("%dc", copperRem)
    end

    -- Add negative sign if needed
    if isNegative then
        return "-" .. result
    else
        return result
    end
end

-- Export module
_G.GoldPH_Ledger = GoldPH_Ledger
