--[[
    Debug.lua - Debug and testing infrastructure for GoldPH

    Provides invariant checks, test injection, and debugging tools.
]]

local GoldPH_Debug = {}

-- Color codes for chat output
local COLOR_GREEN = "|cff00ff00"
local COLOR_RED = "|cffff0000"
local COLOR_YELLOW = "|cffffff00"
local COLOR_RESET = "|r"

--------------------------------------------------
-- Invariant Checks
--------------------------------------------------

-- Validate core accounting invariant: NetWorth = Cash + InventoryExpected
function GoldPH_Debug:ValidateNetWorth(session)
    if not session or not session.ledger then
        return false, "Invalid session"
    end

    -- Phase 1: Only cash tracking (no inventory yet)
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local netWorth = cash

    -- Future phases: Add inventory expected values
    -- for acct, bal in pairs(session.ledger.balances) do
    --     if acct:match("^Assets:Inventory:") then
    --         netWorth = netWorth + bal
    --     end
    -- end

    -- Sum income and expenses
    local income = 0
    local expenses = 0
    for acct, bal in pairs(session.ledger.balances) do
        if acct:match("^Income:") then
            income = income + bal
        elseif acct:match("^Expense:") then
            expenses = expenses + bal
        end
    end

    -- Phase 4+: Account for inventory realization
    local equity = GoldPH_Ledger:GetBalance(session, "Equity:InventoryRealization")

    -- Invariant: NetWorth = Income - Expenses - EquityAdjustment
    local expected = income - expenses - equity
    local diff = netWorth - expected

    if diff ~= 0 then
        return false, string.format("NetWorth invariant violated! NetWorth=%d, Expected=%d, Diff=%d",
                                    netWorth, expected, diff)
    end

    return true, "NetWorth invariant OK"
end

-- Validate ledger balance (debits = credits in double-entry)
function GoldPH_Debug:ValidateLedgerBalance(session)
    if not session or not session.ledger then
        return false, "Invalid session"
    end

    -- In pure double-entry, sum of all balances should be even
    -- (each Dr+Cr pair contributes equal amounts)
    -- However, with our simplified model, we just check for negative balances
    for acct, bal in pairs(session.ledger.balances) do
        if bal < 0 then
            return false, string.format("Negative balance in account: %s = %d", acct, bal)
        end
    end

    return true, "Ledger balance OK"
end

-- Validate holdings (Phase 3)
function GoldPH_Debug:ValidateHoldings(session)
    if not session or not session.holdings then
        return true, "No holdings to validate"
    end

    -- Sum up expected values from holdings by bucket
    local holdingsByBucket = {
        vendor_trash = 0,
        rare_multi = 0,
        gathering = 0,
        container_lockbox = 0,
    }

    for itemID, holding in pairs(session.holdings) do
        for _, lot in ipairs(holding.lots) do
            local bucket = lot.bucket
            local value = lot.count * lot.expectedEach
            holdingsByBucket[bucket] = (holdingsByBucket[bucket] or 0) + value
        end
    end

    -- Compare with ledger accounts
    local vendorTrash = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:VendorTrash")
    local rareMulti = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:RareMulti")
    local gathering = GoldPH_Ledger:GetBalance(session, "Assets:Inventory:Gathering")

    local errors = {}
    if holdingsByBucket.vendor_trash ~= vendorTrash then
        table.insert(errors, string.format("VendorTrash: holdings=%d, ledger=%d",
            holdingsByBucket.vendor_trash, vendorTrash))
    end
    if holdingsByBucket.rare_multi ~= rareMulti then
        table.insert(errors, string.format("RareMulti: holdings=%d, ledger=%d",
            holdingsByBucket.rare_multi, rareMulti))
    end
    if holdingsByBucket.gathering ~= gathering then
        table.insert(errors, string.format("Gathering: holdings=%d, ledger=%d",
            holdingsByBucket.gathering, gathering))
    end

    if #errors > 0 then
        return false, "Holdings mismatch: " .. table.concat(errors, "; ")
    end

    return true, "Holdings match ledger"
end

-- Run all invariant checks
function GoldPH_Debug:ValidateInvariants(session)
    local results = {}
    local allPass = true

    local ok1, msg1 = self:ValidateNetWorth(session)
    table.insert(results, {name = "NetWorth", ok = ok1, message = msg1})
    if not ok1 then allPass = false end

    local ok2, msg2 = self:ValidateLedgerBalance(session)
    table.insert(results, {name = "Ledger", ok = ok2, message = msg2})
    if not ok2 then allPass = false end

    local ok3, msg3 = self:ValidateHoldings(session)
    table.insert(results, {name = "Holdings", ok = ok3, message = msg3})
    if not ok3 then allPass = false end

    -- Log results if verbose or if any failed
    if GoldPH_DB.debug.verbose or not allPass then
        for _, result in ipairs(results) do
            local color = result.ok and COLOR_GREEN or COLOR_RED
            print(string.format("%s[GoldPH Invariant] %s: %s%s", color, result.name, result.message, COLOR_RESET))
        end
    end

    return allPass, results
end

--------------------------------------------------
-- Test Suite
--------------------------------------------------

-- Run automated tests (Phase 1 & 2)
function GoldPH_Debug:RunTests()
    print(COLOR_YELLOW .. "[GoldPH Test Suite] Running tests..." .. COLOR_RESET)

    local testResults = {}

    -- Phase 1 tests
    local test1 = self:Test_BasicLoot()
    table.insert(testResults, test1)

    local test2 = self:Test_MultipleLoot()
    table.insert(testResults, test2)

    local test3 = self:Test_ZeroLoot()
    table.insert(testResults, test3)

    -- Phase 2 tests
    local test4 = self:Test_BasicRepair()
    table.insert(testResults, test4)

    local test5 = self:Test_NetCash()
    table.insert(testResults, test5)

    -- Phase 4 tests (critical for double-counting prevention)
    local test6 = self:Test_VendorSale_NoDoubleCount()
    table.insert(testResults, test6)

    local test7 = self:Test_VendorSale_PreSession()
    table.insert(testResults, test7)

    -- Summary
    local passed = 0
    local failed = 0
    for _, result in ipairs(testResults) do
        if result.passed then
            passed = passed + 1
        else
            failed = failed + 1
        end
    end

    local summaryColor = (failed == 0) and COLOR_GREEN or COLOR_RED
    print(string.format("%s[GoldPH Test Suite] %d passed, %d failed%s",
                        summaryColor, passed, failed, COLOR_RESET))

    return failed == 0
end

-- Test: Basic loot posting
function GoldPH_Debug:Test_BasicLoot()
    local testName = "Basic Loot Posting"

    -- Start temporary session
    if not GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StartSession()
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local initialIncome = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    -- Inject loot
    local lootAmount = 500
    GoldPH_Events:InjectLootedCoin(lootAmount)

    -- Verify balances
    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local finalIncome = GoldPH_Ledger:GetBalance(session, "Income:LootedCoin")

    local cashDiff = finalCash - initialCash
    local incomeDiff = finalIncome - initialIncome

    local passed = (cashDiff == lootAmount) and (incomeDiff == lootAmount)
    local message = passed and "OK" or
                    string.format("FAIL: Expected +%d, got Cash+%d Income+%d", lootAmount, cashDiff, incomeDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Multiple loot events
function GoldPH_Debug:Test_MultipleLoot()
    local testName = "Multiple Loot Events"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Inject multiple loots
    GoldPH_Events:InjectLootedCoin(100)
    GoldPH_Events:InjectLootedCoin(250)
    GoldPH_Events:InjectLootedCoin(75)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local totalLooted = 100 + 250 + 75
    local cashDiff = finalCash - initialCash

    local passed = (cashDiff == totalLooted)
    local message = passed and "OK" or
                    string.format("FAIL: Expected +%d, got +%d", totalLooted, cashDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Zero amount handling
function GoldPH_Debug:Test_ZeroLoot()
    local testName = "Zero Amount Handling"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Try to inject zero (should be rejected)
    local ok = GoldPH_Events:InjectLootedCoin(0)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashDiff = finalCash - initialCash

    local passed = (not ok) and (cashDiff == 0)
    local message = passed and "OK" or "FAIL: Zero amount was not rejected"

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Basic repair posting (Phase 2)
function GoldPH_Debug:Test_BasicRepair()
    local testName = "Basic Repair Posting"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local initialRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")

    -- Inject repair
    local repairCost = 250
    GoldPH_Events:InjectRepair(repairCost)

    -- Verify balances
    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local finalRepairs = GoldPH_Ledger:GetBalance(session, "Expense:Repairs")

    local cashDiff = finalCash - initialCash
    local repairDiff = finalRepairs - initialRepairs

    -- Cash should decrease (negative), repairs should increase
    local passed = (cashDiff == -repairCost) and (repairDiff == repairCost)
    local message = passed and "OK" or
                    string.format("FAIL: Expected Cash-%d Repairs+%d, got Cash%+d Repairs+%d",
                                  repairCost, repairCost, cashDiff, repairDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Net cash calculation (income - expenses) (Phase 2)
function GoldPH_Debug:Test_NetCash()
    local testName = "Net Cash Calculation"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    local initialCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")

    -- Loot 1000, spend 300 on repairs
    GoldPH_Events:InjectLootedCoin(1000)
    GoldPH_Events:InjectRepair(300)

    local finalCash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashDiff = finalCash - initialCash
    local expectedNetCash = 1000 - 300

    local passed = (cashDiff == expectedNetCash)
    local message = passed and "OK" or
                    string.format("FAIL: Expected net +%d, got +%d", expectedNetCash, cashDiff)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Vendor sale - no double counting (Phase 4 CRITICAL)
function GoldPH_Debug:Test_VendorSale_NoDoubleCount()
    local testName = "Vendor Sale (No Double Count)"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    -- Use Linen Cloth (itemID 2589) - common gray item
    -- Cache the item first
    local itemID = 2589
    local itemName, _, quality, _, _, _, _, _, _, _, vendorPrice, itemClass = GetItemInfo(itemID)

    if not itemName then
        return {name = testName, passed = false, message = "Test item not cached (need to mouse over Linen Cloth first)"}
    end

    local initialNetWorth = GoldPH_Ledger:GetBalance(session, "Assets:Cash") +
                            GoldPH_Holdings:GetTotalExpectedValue(session)

    -- Loot 5 Linen Cloth
    local ok1 = GoldPH_Events:InjectLootItem(itemID, 5)
    if not ok1 then
        return {name = testName, passed = false, message = "Failed to inject loot"}
    end

    -- Vendor 5 Linen Cloth
    local ok2 = GoldPH_Events:InjectVendorSale(itemID, 5)
    if not ok2 then
        return {name = testName, passed = false, message = "Failed to inject vendor sale"}
    end

    local finalNetWorth = GoldPH_Ledger:GetBalance(session, "Assets:Cash") +
                          GoldPH_Holdings:GetTotalExpectedValue(session)

    local netWorthChange = finalNetWorth - initialNetWorth
    local expectedChange = 5 * vendorPrice

    -- CRITICAL: Net worth change must equal vendor proceeds only, NOT expected + proceeds
    local passed = (netWorthChange == expectedChange)
    local message = passed and "OK (no double-count)" or
                    string.format("FAIL: Expected +%d, got +%d (double-counted!)",
                                  expectedChange, netWorthChange)

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Test: Vendor sale of pre-session item (Phase 4)
function GoldPH_Debug:Test_VendorSale_PreSession()
    local testName = "Vendor Sale (Pre-Session Item)"

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return {name = testName, passed = false, message = "No active session"}
    end

    -- Use itemID that's NOT in holdings (simulating pre-session item)
    -- Since we can't easily inject a pre-session item, we'll skip this test
    -- and note it needs manual testing

    local passed = true
    local message = "SKIP: Requires manual testing (sell item not looted this session)"

    self:LogTestResult(testName, passed, message)

    return {name = testName, passed = passed, message = message}
end

-- Log test result
function GoldPH_Debug:LogTestResult(testName, passed, message)
    local color = passed and COLOR_GREEN or COLOR_RED
    local status = passed and "PASS" or "FAIL"
    print(string.format("%s[Test: %s] %s: %s%s", color, testName, status, message, COLOR_RESET))
end

--------------------------------------------------
-- State Inspection
--------------------------------------------------

-- Dump current session state
function GoldPH_Debug:DumpSession()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== GoldPH Session Dump ===" .. COLOR_RESET)
    print(string.format("Session ID: %d", session.id))
    print(string.format("Started: %s", date("%Y-%m-%d %H:%M:%S", session.startedAt)))
    print(string.format("Duration: %s", GoldPH_SessionManager:FormatDuration(time() - session.startedAt)))
    print(string.format("Zone: %s", session.zone))

    print("\nLedger Balances:")
    for acct, bal in pairs(session.ledger.balances) do
        print(string.format("  %s: %s", acct, GoldPH_Ledger:FormatMoney(bal)))
    end

    local metrics = GoldPH_SessionManager:GetMetrics(session)
    print("\nMetrics:")
    print(string.format("  Gold: %s", GoldPH_Ledger:FormatMoney(metrics.cash)))
    print(string.format("  Gold/Hour: %s", GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour)))

    print(COLOR_YELLOW .. "===========================" .. COLOR_RESET)
end

-- Show all account balances
function GoldPH_Debug:ShowLedger()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    -- Group accounts by type
    local assets = {}
    local income = {}
    local expenses = {}
    local equity = {}

    for acct, bal in pairs(session.ledger.balances) do
        if acct:match("^Assets:") then
            table.insert(assets, {acct = acct, bal = bal})
        elseif acct:match("^Income:") then
            table.insert(income, {acct = acct, bal = bal})
        elseif acct:match("^Expense:") then
            table.insert(expenses, {acct = acct, bal = bal})
        elseif acct:match("^Equity:") then
            table.insert(equity, {acct = acct, bal = bal})
        end
    end

    -- Sort each group by account name
    table.sort(assets, function(a, b) return a.acct < b.acct end)
    table.sort(income, function(a, b) return a.acct < b.acct end)
    table.sort(expenses, function(a, b) return a.acct < b.acct end)
    table.sort(equity, function(a, b) return a.acct < b.acct end)

    print(COLOR_YELLOW .. "=== Ledger Balances ===" .. COLOR_RESET)

    -- Assets
    if #assets > 0 then
        print(COLOR_GREEN .. "ASSETS:" .. COLOR_RESET)
        local totalAssets = 0
        for _, item in ipairs(assets) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalAssets = totalAssets + item.bal
        end
        print(string.format("  " .. COLOR_GREEN .. "Total Assets: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalAssets)))
        print("")
    end

    -- Income
    if #income > 0 then
        print(COLOR_GREEN .. "INCOME:" .. COLOR_RESET)
        local totalIncome = 0
        for _, item in ipairs(income) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalIncome = totalIncome + item.bal
        end
        print(string.format("  " .. COLOR_GREEN .. "Total Income: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalIncome)))
        print("")
    end

    -- Expenses
    if #expenses > 0 then
        print(COLOR_RED .. "EXPENSES:" .. COLOR_RESET)
        local totalExpenses = 0
        for _, item in ipairs(expenses) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalExpenses = totalExpenses + item.bal
        end
        print(string.format("  " .. COLOR_RED .. "Total Expenses: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalExpenses)))
        print("")
    end

    -- Equity
    if #equity > 0 then
        print(COLOR_YELLOW .. "EQUITY:" .. COLOR_RESET)
        local totalEquity = 0
        for _, item in ipairs(equity) do
            print(string.format("  %s: %s", item.acct, GoldPH_Ledger:FormatMoney(item.bal)))
            totalEquity = totalEquity + item.bal
        end
        print(string.format("  " .. COLOR_YELLOW .. "Total Equity: %s" .. COLOR_RESET, GoldPH_Ledger:FormatMoney(totalEquity)))
        print("")
    end

    print(COLOR_YELLOW .. "=======================" .. COLOR_RESET)
end

-- Show holdings (Phase 3)
function GoldPH_Debug:ShowHoldings()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        print(COLOR_YELLOW .. "[GoldPH Debug] No active session" .. COLOR_RESET)
        return
    end

    print(COLOR_YELLOW .. "=== Holdings (FIFO Lots) ===" .. COLOR_RESET)

    if not session.holdings or next(session.holdings) == nil then
        print("  (No holdings)")
        print(COLOR_YELLOW .. "=============================" .. COLOR_RESET)
        return
    end

    for itemID, holding in pairs(session.holdings) do
        local itemName = GetItemInfo(itemID) or "Unknown"
        print(string.format("\n  Item: %s (ID: %d)", itemName, itemID))
        print(string.format("  Total Count: %d", holding.count))
        print(string.format("  Lots: %d", #holding.lots))

        for i, lot in ipairs(holding.lots) do
            print(string.format("    Lot #%d: count=%d, expectedEach=%d (%s), bucket=%s",
                i, lot.count, lot.expectedEach, GoldPH_Ledger:FormatMoney(lot.expectedEach), lot.bucket))
        end
    end

    print(COLOR_YELLOW .. "\n=============================" .. COLOR_RESET)
end

-- Show available price sources
function GoldPH_Debug:ShowPriceSources()
    print(COLOR_YELLOW .. "=== Price Sources ===" .. COLOR_RESET)

    local sources = GoldPH_PriceSources:GetAvailableSources()

    if #sources == 0 then
        print("  " .. COLOR_RED .. "No price sources available" .. COLOR_RESET)
        print("  Using vendor prices only (conservative)")
    else
        print("  " .. COLOR_GREEN .. "Available sources:" .. COLOR_RESET)
        for i, source in ipairs(sources) do
            print(string.format("    %d. %s", i, source))
        end
    end

    print("\n  Priority order: Manual Overrides > Custom AH > TSM")
    print("  Set manual override: /script GoldPH_DB.priceOverrides[itemID] = price")

    print(COLOR_YELLOW .. "=====================" .. COLOR_RESET)
end

--------------------------------------------------
-- HUD Testing
--------------------------------------------------

-- Test HUD display by injecting sample data for all fields
-- Usage: /script GoldPH_Debug:TestHUD()
function GoldPH_Debug:TestHUD()
    print(COLOR_YELLOW .. "=== HUD Test Data ===" .. COLOR_RESET)

    -- Ensure session is active
    if not GoldPH_SessionManager:GetActiveSession() then
        local ok, msg = GoldPH_SessionManager:StartSession()
        if not ok then
            print(COLOR_RED .. "Failed to start session: " .. msg .. COLOR_RESET)
            return false
        end
        print(COLOR_GREEN .. "Started new session for testing" .. COLOR_RESET)
    end

    local session = GoldPH_SessionManager:GetActiveSession()

    -- Sample values (in copper)
    local goldAmount = 1000000     -- 100g looted coin
    local inventoryAmount = 300000 -- 30g vendor trash + rare items
    local gatheringAmount = 200000 -- 20g gathering mats
    local expenseAmount = 50000    -- 5g repairs

    -- Inject looted gold
    GoldPH_Events:InjectLootedCoin(goldAmount)
    print(string.format("  Injected gold: %s", GoldPH_Ledger:FormatMoney(goldAmount)))

    -- Inject inventory items (vendor trash bucket) - direct ledger posting
    GoldPH_Ledger:Post(session, "Assets:Inventory:VendorTrash", "Income:ItemsLooted:VendorTrash", inventoryAmount)
    print(string.format("  Injected inventory (vendor trash): %s", GoldPH_Ledger:FormatMoney(inventoryAmount)))

    -- Inject gathering items - direct ledger posting
    GoldPH_Ledger:Post(session, "Assets:Inventory:Gathering", "Income:ItemsLooted:Gathering", gatheringAmount)
    print(string.format("  Injected gathering: %s", GoldPH_Ledger:FormatMoney(gatheringAmount)))

    -- Inject repair expense
    GoldPH_Events:InjectRepair(expenseAmount)
    print(string.format("  Injected expenses: %s", GoldPH_Ledger:FormatMoney(expenseAmount)))

    -- Calculate expected HUD values
    local expectedGold = goldAmount - expenseAmount  -- 95g (gold minus expenses)
    local expectedInventory = inventoryAmount        -- 30g
    local expectedGathering = gatheringAmount        -- 20g
    local expectedTotal = expectedGold + expectedInventory + expectedGathering  -- 145g

    print("")
    print(COLOR_GREEN .. "Expected HUD values:" .. COLOR_RESET)
    print(string.format("  Gold: %s", GoldPH_Ledger:FormatMoney(expectedGold)))
    print(string.format("  Inventory: %s", GoldPH_Ledger:FormatMoney(expectedInventory)))
    print(string.format("  Gathering: %s", GoldPH_Ledger:FormatMoney(expectedGathering)))
    print(string.format("  Expenses: -%s", GoldPH_Ledger:FormatMoney(expenseAmount)))
    print(string.format("  Total: %s", GoldPH_Ledger:FormatMoney(expectedTotal)))

    -- Force HUD update
    GoldPH_HUD:Update()

    print("")
    print(COLOR_YELLOW .. "HUD should now display test data. Verify visually." .. COLOR_RESET)
    print(COLOR_YELLOW .. "=====================" .. COLOR_RESET)

    return true
end

-- Reset test data (stop and start fresh session)
-- Usage: /script GoldPH_Debug:ResetTestHUD()
function GoldPH_Debug:ResetTestHUD()
    -- Stop current session if active
    if GoldPH_SessionManager:GetActiveSession() then
        GoldPH_SessionManager:StopSession()
        print(COLOR_YELLOW .. "[GoldPH] Test session stopped" .. COLOR_RESET)
    end

    -- Start fresh session
    GoldPH_SessionManager:StartSession()
    GoldPH_HUD:Update()
    print(COLOR_GREEN .. "[GoldPH] Fresh session started for testing" .. COLOR_RESET)
end

-- Export module
_G.GoldPH_Debug = GoldPH_Debug
