--[[
    Events.lua - Event handling and routing for GoldPH

    Handles WoW events and routes them to accounting actions.
]]

local GoldPH_Events = {}

--------------------------------------------------
-- API Compatibility (Classic Anniversary uses C_Container)
--------------------------------------------------

-- Container API wrapper for GetContainerNumSlots
local function GetBagNumSlots(bag)
    if C_Container and C_Container.GetContainerNumSlots then
        return C_Container.GetContainerNumSlots(bag)
    else
        return GetContainerNumSlots(bag)
    end
end

-- Container API wrapper for GetContainerItemInfo
-- Returns: itemCount, itemLink (nil if slot is empty)
local function GetBagItemInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if info then
            return info.stackCount, info.hyperlink
        end
        return nil, nil
    else
        local _, itemCount, _, _, _, _, itemLink = GetContainerItemInfo(bag, slot)
        return itemCount, itemLink
    end
end

-- Runtime state (not persisted)
local state = {
    moneyLast = nil,

    -- Phase 2: Merchant tracking
    merchantOpen = false,

    -- Phase 5: Taxi tracking
    taxiOpen = false,
    moneyAtTaxiOpen = nil,
    taxiCostProcessed = false,

    -- Phase 6+: pickpocketActiveUntil, openingLockboxUntil, etc.
}

-- Initialize event system
function GoldPH_Events:Initialize(frame)
    -- Register events
    frame:RegisterEvent("CHAT_MSG_MONEY")
    frame:RegisterEvent("MERCHANT_SHOW")
    frame:RegisterEvent("MERCHANT_CLOSED")
    frame:RegisterEvent("CHAT_MSG_LOOT")  -- Phase 3
    frame:RegisterEvent("BAG_UPDATE")     -- Phase 4 (vendor sale detection)
    frame:RegisterEvent("PLAYER_MONEY")   -- Phase 5 (monitor money changes for taxi)
    frame:RegisterEvent("TAXIMAP_OPENED") -- Phase 5
    frame:RegisterEvent("TAXIMAP_CLOSED") -- Phase 5
    frame:RegisterEvent("QUEST_TURNED_IN") -- Phase 5

    -- Note: We do NOT set OnEvent handler here - init.lua maintains control
    -- and will route events to us via GoldPH_Events:OnEvent()

    -- Initialize money tracking
    state.moneyLast = GetMoney()

    -- Hook repair function (Phase 2)
    self:HookRepairFunctions()

    -- Hook vendor sales (Phase 4)
    self:HookVendorSales()
    
    -- Hook taxi node selection (Phase 5)
    self:HookTaxiFunctions()
end

-- Main event dispatcher
function GoldPH_Events:OnEvent(event, ...)
    if event == "CHAT_MSG_MONEY" then
        self:OnLootedCoin(...)
    elseif event == "CHAT_MSG_LOOT" then
        self:OnLootedItem(...)
    elseif event == "MERCHANT_SHOW" then
        self:OnMerchantShow()
    elseif event == "MERCHANT_CLOSED" then
        self:OnMerchantClosed()
    elseif event == "BAG_UPDATE" then
        self:OnBagUpdateAtMerchant()
    elseif event == "PLAYER_MONEY" then
        self:OnPlayerMoney()
    elseif event == "TAXIMAP_OPENED" then
        self:OnTaxiMapOpened()
    elseif event == "TAXIMAP_CLOSED" then
        self:OnTaxiMapClosed()
    elseif event == "QUEST_TURNED_IN" then
        self:OnQuestTurnedIn(...)
    end
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

--------------------------------------------------
-- Phase 3: Item Looting
--------------------------------------------------

-- Handle CHAT_MSG_LOOT event (items)
function GoldPH_Events:OnLootedItem(message)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Parse item from loot message
    -- Example: "You receive loot: [Item Link]x3."
    -- Example: "You receive loot: [Item Link]."
    local itemLink, count = self:ParseLootMessage(message)

    if not itemLink then
        return -- Not a valid item loot message
    end

    count = count or 1

    -- Extract itemID from itemLink
    local itemID = self:ExtractItemID(itemLink)
    if not itemID then
        return
    end

    -- Get item info (may be nil if not cached yet)
    local itemName, quality, itemClass, itemSubClass, vendorPrice = GoldPH_Valuation:GetItemInfo(itemID)

    if not itemName then
        -- Item not in cache yet, defer processing
        -- TODO Phase 3+: Queue for retry
        if GoldPH_DB.debug.verbose then
            print(string.format("[GoldPH] Item cache miss: itemID=%d, will retry", itemID))
        end
        return
    end

    -- Classify item into bucket
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    if bucket == "other" then
        -- Not tracked
        return
    end

    -- Compute expected value
    local expectedEach = GoldPH_Valuation:ComputeExpectedValue(itemID, bucket)

    -- Special handling for lockboxes (Phase 6)
    if bucket == "container_lockbox" then
        -- Lockboxes have 0 expected value, don't post to ledger
        -- Just track in items aggregate
        GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)
        return
    end

    -- Post to ledger: Dr Assets:Inventory:<bucket>, Cr Income:ItemsLooted:<bucket>
    local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucket)
    local incomeAccount = "Income:ItemsLooted:" .. self:BucketToAccountName(bucket)

    local expectedTotal = count * expectedEach
    GoldPH_Ledger:Post(session, assetAccount, incomeAccount, expectedTotal)

    -- Add to holdings (FIFO lot)
    GoldPH_Holdings:AddLot(session, itemID, count, expectedEach, bucket)

    -- Add to items aggregate
    GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)

    -- Debug logging
    if GoldPH_DB.debug.verbose then
        print(string.format("[GoldPH] Looted: %s x%d (%s, %s each)",
            itemName, count, bucket, GoldPH_Ledger:FormatMoney(expectedEach)))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

-- Parse item link and count from CHAT_MSG_LOOT message
function GoldPH_Events:ParseLootMessage(message)
    -- Pattern: "You receive loot: [Item Link]x3."
    -- Pattern: "You receive loot: [Item Link]."
    local itemLink, countStr = message:match("You receive loot: (|c%x+|H.+|h.+|h|r)x(%d+)")

    if itemLink and countStr then
        return itemLink, tonumber(countStr)
    end

    -- Try without count (single item)
    itemLink = message:match("You receive loot: (|c%x+|H.+|h.+|h|r)")

    if itemLink then
        return itemLink, 1
    end

    return nil, nil
end

-- Extract itemID from itemLink
function GoldPH_Events:ExtractItemID(itemLink)
    -- ItemLink format: |cXXXXXXXX|Hitem:itemID:...|h[Name]|h|r
    local itemID = itemLink:match("|Hitem:(%d+):")
    if itemID then
        return tonumber(itemID)
    end
    return nil
end

-- Convert bucket name to account name component
function GoldPH_Events:BucketToAccountName(bucket)
    if bucket == "vendor_trash" then
        return "VendorTrash"
    elseif bucket == "rare_multi" then
        return "RareMulti"
    elseif bucket == "gathering" then
        return "Gathering"
    elseif bucket == "container_lockbox" then
        return "Containers:Lockbox"
    else
        return "Other"
    end
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

    -- Initialize vendor sale tracking (Phase 4)
    state.bagSnapshot = self:SnapshotBags()
    state.lastMoneyCheck = GetMoney()

    if GoldPH_DB.debug.verbose then
        print("[GoldPH] Merchant window opened")
    end
end

-- Handle MERCHANT_CLOSED event
function GoldPH_Events:OnMerchantClosed()
    state.merchantOpen = false

    -- Clear vendor sale tracking (Phase 4)
    state.bagSnapshot = nil
    state.lastMoneyCheck = 0

    if GoldPH_DB.debug.verbose then
        print("[GoldPH] Merchant window closed")
    end
end

--------------------------------------------------
-- Phase 5: Travel (Flight Path) Expense Tracking
--------------------------------------------------

-- Handle PLAYER_MONEY event (monitor for taxi cost deduction)
function GoldPH_Events:OnPlayerMoney()
    -- Update money tracking
    local currentMoney = GetMoney()
    
    -- Debug: Always log money changes when taxi is open
    if state.taxiOpen and GoldPH_DB.debug.verbose then
        print(string.format("[GoldPH] PLAYER_MONEY: taxiOpen=%s, moneyAtTaxiOpen=%s, currentMoney=%s", 
            tostring(state.taxiOpen), 
            state.moneyAtTaxiOpen and GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen) or "nil",
            GoldPH_Ledger:FormatMoney(currentMoney)))
    end
    
    -- Check if taxi map is open and money decreased (flight cost deducted)
    -- Only process if we haven't already recorded it via TakeTaxiNode hook
    if state.taxiOpen and state.moneyAtTaxiOpen and not state.taxiCostProcessed and state.moneyAtTaxiOpen > currentMoney then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local cost = state.moneyAtTaxiOpen - currentMoney
            self:RecordTaxiCost(session, cost, "PLAYER_MONEY")
        end
    end
    
    -- Update money tracking for future events
    state.moneyLast = currentMoney
end

-- Handle TAXIMAP_OPENED event
function GoldPH_Events:OnTaxiMapOpened()
    state.taxiOpen = true
    state.moneyAtTaxiOpen = GetMoney()
    state.taxiCostProcessed = false  -- Track if we've already recorded the cost

    if GoldPH_DB.debug.verbose then
        print("[GoldPH] TAXIMAP_OPENED: money=" .. GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen))
    end
end

-- Handle TAXIMAP_CLOSED event
function GoldPH_Events:OnTaxiMapClosed()
    if GoldPH_DB.debug.verbose then
        print(string.format("[GoldPH] TAXIMAP_CLOSED: taxiOpen=%s, moneyAtTaxiOpen=%s, costProcessed=%s",
            tostring(state.taxiOpen),
            state.moneyAtTaxiOpen and GoldPH_Ledger:FormatMoney(state.moneyAtTaxiOpen) or "nil",
            tostring(state.taxiCostProcessed)))
    end
    
    -- Flight cost should already be captured via PLAYER_MONEY or TakeTaxiNode hook
    -- But check one more time in case those didn't fire (edge case)
    if state.taxiOpen and state.moneyAtTaxiOpen and not state.taxiCostProcessed then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local currentMoney = GetMoney()
            local cost = state.moneyAtTaxiOpen - currentMoney

            -- Only post expense if cost > 0
            if cost > 0 then
                -- Post double-entry: Dr Expense:Travel, Cr Assets:Cash
                GoldPH_Ledger:Post(session, "Expense:Travel", "Assets:Cash", cost)

                if GoldPH_DB.debug.verbose then
                    print(string.format("[GoldPH] Flight cost (fallback on TAXIMAP_CLOSED): %s", GoldPH_Ledger:FormatMoney(cost)))
                end

                -- Run invariants if debug mode enabled
                if GoldPH_DB.debug.enabled then
                    GoldPH_Debug:ValidateInvariants(session)
                end

                -- Update HUD
                GoldPH_HUD:Update()
                
                state.taxiCostProcessed = true
            end
        end
    end

    -- Clear taxi state
    state.taxiOpen = false
    state.moneyAtTaxiOpen = nil
    state.taxiCostProcessed = nil
end

--------------------------------------------------
-- Phase 5: Quest Gold Income Tracking
--------------------------------------------------

-- Handle QUEST_TURNED_IN event
-- @param questID: Quest ID
-- @param xpReward: Experience reward (unused)
-- @param moneyReward: Money reward in copper
function GoldPH_Events:OnQuestTurnedIn(questID, xpReward, moneyReward)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return -- No active session
    end

    -- Only process if quest gave money reward
    if not moneyReward or moneyReward <= 0 then
        return
    end

    -- Post double-entry: Dr Assets:Cash, Cr Income:Quest
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:Quest", moneyReward)

    if GoldPH_DB.debug.verbose then
        print(string.format("[GoldPH] Quest reward: %s (Quest ID: %d)", 
            GoldPH_Ledger:FormatMoney(moneyReward), questID))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
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

-- Hook taxi functions to track flight costs (Phase 5)
function GoldPH_Events:HookTaxiFunctions()
    -- Hook TakeTaxiNode - called when player selects a destination
    -- This fires BEFORE the money is deducted, so we capture money state here
    if TakeTaxiNode then
        hooksecurefunc("TakeTaxiNode", function(nodeIndex)
            self:OnTakeTaxiNode(nodeIndex)
        end)
    end
end

-- Handle TakeTaxiNode hook (when player clicks a destination)
function GoldPH_Events:OnTakeTaxiNode(nodeIndex)
    -- Only process if taxi map was open (we tracked the initial money)
    if not state.taxiOpen or not state.moneyAtTaxiOpen or state.taxiCostProcessed then
        return
    end

    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Get current money (should be before deduction, but check anyway)
    local currentMoney = GetMoney()
    
    -- Try to get cost from API if available
    local cost = nil
    if TaxiNodeCost then
        cost = TaxiNodeCost(nodeIndex)
    end
    
    -- If we can't get cost from API, use money delta
    if not cost or cost == 0 then
        -- Wait a tiny bit for money to be deducted, then check
        -- Use a frame update to check after the deduction happens
        C_Timer.After(0.1, function()
            local newMoney = GetMoney()
            local deltaCost = state.moneyAtTaxiOpen - newMoney
            if deltaCost > 0 then
                self:RecordTaxiCost(session, deltaCost, "TakeTaxiNode (delta)")
            end
        end)
    else
        -- Use the API cost directly
        self:RecordTaxiCost(session, cost, "TakeTaxiNode (API)")
    end
end

-- Helper function to record taxi cost (prevents double-counting)
function GoldPH_Events:RecordTaxiCost(session, cost, source)
    if not session or not cost or cost <= 0 or state.taxiCostProcessed then
        return
    end

    -- Post double-entry: Dr Expense:Travel, Cr Assets:Cash
    GoldPH_Ledger:Post(session, "Expense:Travel", "Assets:Cash", cost)

    if GoldPH_DB.debug.verbose then
        print(string.format("[GoldPH] Flight cost recorded (%s): %s", source, GoldPH_Ledger:FormatMoney(cost)))
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
    
    -- Mark as processed to prevent double-counting
    state.taxiCostProcessed = true
    state.moneyAtTaxiOpen = nil  -- Clear so PLAYER_MONEY doesn't double-count
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

--------------------------------------------------
-- Phase 4: Vendor Sales & FIFO Reversals
--------------------------------------------------

-- Track bag contents for vendor sale detection
state.bagSnapshot = nil
state.lastMoneyCheck = 0

-- Hook vendor sales to track items sold
function GoldPH_Events:HookVendorSales()
    -- In Classic, UseContainerItem isn't hookable, so we use BAG_UPDATE events instead
    -- The merchant events (MERCHANT_SHOW/CLOSED) are already registered
    -- We'll detect sales via BAG_UPDATE + money changes
end

-- Take snapshot of bag contents
function GoldPH_Events:SnapshotBags()
    local snapshot = {}

    for bag = 0, 4 do
        local numSlots = GetBagNumSlots(bag)
        for slot = 1, numSlots do
            local itemCount, itemLink = GetBagItemInfo(bag, slot)
            if itemLink and itemCount then
                local itemID = self:ExtractItemID(itemLink)
                if itemID then
                    snapshot[itemID] = (snapshot[itemID] or 0) + itemCount
                end
            end
        end
    end

    return snapshot
end

-- Handle BAG_UPDATE when merchant is open (detects vendor sales)
function GoldPH_Events:OnBagUpdateAtMerchant()
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    -- Only track if merchant window is open
    if not state.merchantOpen then
        return
    end

    -- Take new snapshot
    local newSnapshot = self:SnapshotBags()

    -- If we don't have an old snapshot, save this one and return
    if not state.bagSnapshot then
        state.bagSnapshot = newSnapshot
        state.lastMoneyCheck = GetMoney()
        return
    end

    -- Check for money increase (vendor proceeds)
    local currentMoney = GetMoney()
    local moneyGained = currentMoney - state.lastMoneyCheck

    if moneyGained <= 0 then
        -- No money gained, not a sale (or it's a purchase)
        state.bagSnapshot = newSnapshot
        state.lastMoneyCheck = currentMoney
        return
    end

    -- Find items that decreased in quantity
    for itemID, oldCount in pairs(state.bagSnapshot) do
        local newCount = newSnapshot[itemID] or 0
        local countSold = oldCount - newCount

        if countSold > 0 then
            -- Item was sold, process it
            local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)

            if itemName and vendorSellEach and vendorSellEach > 0 then
                -- Calculate expected proceeds for this item
                local expectedProceeds = countSold * vendorSellEach

                -- Only process if this accounts for the money gained
                -- (handles case where multiple items sold at once)
                if expectedProceeds <= moneyGained then
                    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)
                    self:ProcessVendorSale(session, itemID, itemName, countSold, expectedProceeds, bucket)

                    -- Update money tracking
                    moneyGained = moneyGained - expectedProceeds
                end
            end
        end
    end

    -- Update snapshot for next check
    state.bagSnapshot = newSnapshot
    state.lastMoneyCheck = currentMoney
end

-- Legacy function for compatibility (now unused but kept for test injection)
function GoldPH_Events:OnUseContainerItem(bag, slot)
    -- This function is no longer called by hooks, but kept for test injection
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return
    end

    if not state.merchantOpen then
        return
    end

    local itemCount, itemLink = GetBagItemInfo(bag, slot)
    if not itemLink or not itemCount then
        return
    end

    local itemID = self:ExtractItemID(itemLink)
    if not itemID then
        return
    end

    local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)
    if not itemName then
        return
    end

    if not vendorSellEach or vendorSellEach == 0 then
        return
    end

    -- Calculate total vendor proceeds
    local vendorProceeds = itemCount * vendorSellEach

    -- Classify item to get bucket
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    -- Process vendor sale
    self:ProcessVendorSale(session, itemID, itemName, itemCount, vendorProceeds, bucket)
end

-- Process a vendor sale (called by hook or test injection)
function GoldPH_Events:ProcessVendorSale(session, itemID, itemName, count, vendorProceeds, bucket)
    -- Post cash proceeds: Dr Assets:Cash, Cr Income:VendorSales
    GoldPH_Ledger:Post(session, "Assets:Cash", "Income:VendorSales", vendorProceeds)

    -- Consume FIFO lots to get held expected value by bucket
    local bucketValues = GoldPH_Holdings:ConsumeFIFO(session, itemID, count)

    -- Reverse inventory expected value for each bucket
    for bucketName, heldValue in pairs(bucketValues) do
        if heldValue > 0 then
            local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucketName)
            local equityAccount = "Equity:InventoryRealization"

            -- Cr Assets:Inventory (decrease), Dr Equity:InventoryRealization
            GoldPH_Ledger:Post(session, equityAccount, assetAccount, heldValue)
        end
    end

    -- Update item aggregate (decrement count)
    if session.items[itemID] then
        session.items[itemID].count = session.items[itemID].count - count
        if session.items[itemID].count <= 0 then
            -- Remove item from aggregates if count reaches zero
            session.items[itemID] = nil
        end
    end

    -- Debug logging
    if GoldPH_DB.debug.verbose then
        local totalHeldValue = 0
        for _, val in pairs(bucketValues) do
            totalHeldValue = totalHeldValue + val
        end

        print(string.format("[GoldPH] Vendor sale: %s x%d, proceeds=%s, held expected=%s",
            itemName, count,
            GoldPH_Ledger:FormatMoney(vendorProceeds),
            GoldPH_Ledger:FormatMoney(totalHeldValue)))

        if totalHeldValue == 0 then
            print("[GoldPH]   (Pre-session item - no inventory reversal)")
        end
    end

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()
end

--------------------------------------------------
-- Phase 3: Test Injection - Items
--------------------------------------------------

-- Inject a looted item event (for testing)
-- @param itemID: Item ID (must be valid)
-- @param count: Number of items
function GoldPH_Events:InjectLootItem(itemID, count)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not itemID or not count or count <= 0 then
        return false, "Invalid itemID or count"
    end

    -- Get item info (may fail if not cached)
    local itemName, quality, itemClass, itemSubClass, vendorPrice = GoldPH_Valuation:GetItemInfo(itemID)

    if not itemName then
        return false, string.format("Item not in cache: itemID=%d (try mousing over it first)", itemID)
    end

    -- Classify and value item
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    if bucket == "other" then
        return false, string.format("Item not tracked: %s (bucket=other)", itemName)
    end

    local expectedEach = GoldPH_Valuation:ComputeExpectedValue(itemID, bucket)

    -- Post to ledger (unless lockbox)
    if bucket ~= "container_lockbox" then
        local assetAccount = "Assets:Inventory:" .. self:BucketToAccountName(bucket)
        local incomeAccount = "Income:ItemsLooted:" .. self:BucketToAccountName(bucket)

        local expectedTotal = count * expectedEach
        GoldPH_Ledger:Post(session, assetAccount, incomeAccount, expectedTotal)

        -- Add to holdings
        GoldPH_Holdings:AddLot(session, itemID, count, expectedEach, bucket)
    end

    -- Add to items aggregate
    GoldPH_SessionManager:AddItem(session, itemID, itemName, quality, bucket, count, expectedEach)

    -- Debug logging
    print(string.format("[GoldPH Test] Injected loot: %s x%d (bucket=%s, %s each)",
        itemName, count, bucket, GoldPH_Ledger:FormatMoney(expectedEach)))

    -- Run invariants if debug mode enabled
    if GoldPH_DB.debug.enabled then
        GoldPH_Debug:ValidateInvariants(session)
    end

    -- Update HUD
    GoldPH_HUD:Update()

    return true
end

--------------------------------------------------
-- Phase 4: Test Injection - Vendor Sales
--------------------------------------------------

-- Inject a vendor sale event (for testing)
-- @param itemID: Item ID (must be valid and in holdings)
-- @param count: Number of items to sell
function GoldPH_Events:InjectVendorSale(itemID, count)
    local session = GoldPH_SessionManager:GetActiveSession()
    if not session then
        return false, "No active session"
    end

    if not itemID or not count or count <= 0 then
        return false, "Invalid itemID or count"
    end

    -- Get item info
    local itemName, _, quality, _, _, _, _, _, _, _, vendorSellEach, itemClass, itemSubClass = GetItemInfo(itemID)

    if not itemName then
        return false, string.format("Item not in cache: itemID=%d (try mousing over it first)", itemID)
    end

    if not vendorSellEach or vendorSellEach == 0 then
        return false, string.format("Item has no vendor value: %s", itemName)
    end

    -- Check if item is in holdings
    local holdingsCount = GoldPH_Holdings:GetCount(session, itemID)
    if holdingsCount < count then
        return false, string.format("Not enough in holdings: have %d, trying to sell %d", holdingsCount, count)
    end

    -- Calculate vendor proceeds
    local vendorProceeds = count * vendorSellEach

    -- Classify item
    local bucket = GoldPH_Valuation:ClassifyItem(itemID, itemName, quality, itemClass, itemSubClass)

    -- Process vendor sale
    self:ProcessVendorSale(session, itemID, itemName, count, vendorProceeds, bucket)

    print(string.format("[GoldPH Test] Injected vendor sale: %s x%d for %s",
        itemName, count, GoldPH_Ledger:FormatMoney(vendorProceeds)))

    return true
end

-- Export module
_G.GoldPH_Events = GoldPH_Events
