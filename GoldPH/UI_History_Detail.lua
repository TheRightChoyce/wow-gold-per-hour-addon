--[[
    UI_History_Detail.lua - Detail pane with tabs for GoldPH History

    Shows session details across 4 tabs: Summary, Items, Gathering, Compare
]]

-- luacheck: globals GoldPH_Settings
-- Access pH brand colors
local pH_Colors = _G.pH_Colors

local GoldPH_History_Detail = {
    parent = nil,
    historyController = nil,

    -- Tab system
    tabs = {},
    activeTab = "summary",
    contentFrames = {},

    -- Current session
    currentSessionId = nil,
    currentSession = nil,
    currentMetrics = nil,
}

-- Item quality colors (WoW standard)
local QualityColors = {
    [0] = {0.6, 0.6, 0.6},  -- Poor (gray)
    [1] = {1, 1, 1},        -- Common (white)
    [2] = {0, 1, 0},        -- Uncommon (green)
    [3] = {0, 0.5, 1},      -- Rare (blue)
    [4] = {0.7, 0, 1},      -- Epic (purple)
    [5] = {1, 0.5, 0},      -- Legendary (orange)
}

--------------------------------------------------
-- Initialize
--------------------------------------------------
function GoldPH_History_Detail:Initialize(parent, historyController)
    self.parent = parent
    self.historyController = historyController

    -- Create tab buttons (4 tabs)
    local tabNames = {
        {key = "summary", label = "Summary"},
        {key = "items", label = "Items"},
        {key = "gathering", label = "Gathering"},
        {key = "compare", label = "Compare"},
    }

    local tabWidth = 90
    local tabHeight = 25
    local tabSpacing = 2

    for i, tabInfo in ipairs(tabNames) do
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(tabWidth, tabHeight)
        tab:SetPoint("TOPLEFT", parent, "TOPLEFT", 5 + (i - 1) * (tabWidth + tabSpacing), -5)
        tab:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 8,
            insets = {left = 2, right = 2, top = 2, bottom = 2}
        })
        local PH_BG_DARK = pH_Colors.BG_DARK
        local PH_DIVIDER = pH_Colors.DIVIDER
        tab:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.80)
        tab:SetBackdropBorderColor(PH_DIVIDER[1], PH_DIVIDER[2], PH_DIVIDER[3], 0.60)

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("CENTER")
        tabText:SetText(tabInfo.label)
        tab.text = tabText
        tab.key = tabInfo.key

        tab:SetScript("OnClick", function()
            GoldPH_History_Detail:SwitchTab(tabInfo.key)
        end)

        self.tabs[tabInfo.key] = tab
    end

    -- Create content frames for each tab
    for _, tabInfo in ipairs(tabNames) do
        local contentFrame = CreateFrame("ScrollFrame", nil, parent)
        contentFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", 5, -35)
        contentFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -5, 5)
        contentFrame:Hide()

        -- Scroll child
        local scrollChild = CreateFrame("Frame", nil, contentFrame)
        local scrollWidth = contentFrame:GetWidth() - 10
        scrollChild:SetSize(scrollWidth, 400)  -- Will expand as needed
        contentFrame:SetScrollChild(scrollChild)
        contentFrame.scrollChild = scrollChild

        -- Enable mouse wheel scrolling
        contentFrame:EnableMouseWheel(true)
        contentFrame:SetScript("OnMouseWheel", function(self, delta)
            local current = self:GetVerticalScroll()
            local maxScroll = self:GetVerticalScrollRange()
            local newScroll = math.max(0, math.min(maxScroll, current - (delta * 20)))
            self:SetVerticalScroll(newScroll)
        end)

        self.contentFrames[tabInfo.key] = contentFrame
    end

    -- Show summary tab by default
    self:SwitchTab("summary")
end

--------------------------------------------------
-- Switch Tab
--------------------------------------------------
function GoldPH_History_Detail:SwitchTab(tabKey)
    -- Update tab appearance
    local SELECTED = pH_Colors.SELECTED
    local TEXT_PRIMARY = pH_Colors.TEXT_PRIMARY
    local PH_BG_DARK = pH_Colors.BG_DARK
    local TEXT_MUTED = pH_Colors.TEXT_MUTED

    for key, tab in pairs(self.tabs) do
        if key == tabKey then
            tab:SetBackdropColor(SELECTED[1], SELECTED[2], SELECTED[3], 1)
            tab.text:SetTextColor(TEXT_PRIMARY[1], TEXT_PRIMARY[2], TEXT_PRIMARY[3])
        else
            tab:SetBackdropColor(PH_BG_DARK[1], PH_BG_DARK[2], PH_BG_DARK[3], 0.80)
            tab.text:SetTextColor(TEXT_MUTED[1], TEXT_MUTED[2], TEXT_MUTED[3])
        end
    end

    -- Hide all content frames
    for key, frame in pairs(self.contentFrames) do
        frame:Hide()
    end

    -- Show active content frame
    self.activeTab = tabKey
    self.contentFrames[tabKey]:Show()

    -- Render tab content
    self:RenderActiveTab()

    -- Save active tab preference
    if GoldPH_Settings then
        GoldPH_Settings.historyActiveTab = tabKey
    end
end

--------------------------------------------------
-- Set Session (called when user selects a session)
--------------------------------------------------
function GoldPH_History_Detail:SetSession(sessionId)
    self.currentSessionId = sessionId
    self.currentSession = GoldPH_SessionManager:GetSession(sessionId)
    self.currentMetrics = self.currentSession and GoldPH_SessionManager:GetMetrics(self.currentSession) or nil

    -- Render active tab
    self:RenderActiveTab()
end

--------------------------------------------------
-- Render Active Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderActiveTab()
    if not self.currentSession or not self.currentMetrics then
        self:RenderEmptyState()
        return
    end

    if self.activeTab == "summary" then
        self:RenderSummaryTab()
    elseif self.activeTab == "items" then
        self:RenderItemsTab()
    elseif self.activeTab == "gathering" then
        self:RenderGatheringTab()
    elseif self.activeTab == "compare" then
        self:RenderCompareTab()
    end
end

--------------------------------------------------
-- Clear Content Helper
--------------------------------------------------
local function ClearScrollChild(scrollChild)
    -- Hide all children
    local children = {scrollChild:GetChildren()}
    for _, child in ipairs(children) do
        child:Hide()
        child:ClearAllPoints()
    end

    -- Hide all font strings
    local regions = {scrollChild:GetRegions()}
    for _, region in ipairs(regions) do
        if region.GetText then  -- It's a FontString
            region:Hide()
            region:ClearAllPoints()
        end
    end
end

--------------------------------------------------
-- Render Empty State
--------------------------------------------------
function GoldPH_History_Detail:RenderEmptyState()
    local frame = self.contentFrames[self.activeTab]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyText:SetPoint("CENTER", scrollChild, "CENTER")
    emptyText:SetText("No session selected")
    emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
end

--------------------------------------------------
-- Helper: Format friendly date
--------------------------------------------------
local function FormatFriendlyDate(timestamp)
    if not timestamp then return "Unknown" end

    local now = time()
    local diff = now - timestamp

    -- Less than 1 hour ago
    if diff < 3600 then
        local mins = math.floor(diff / 60)
        return mins .. " min" .. (mins ~= 1 and "s" or "") .. " ago"
    end

    -- Less than 24 hours ago
    if diff < 86400 then
        local hours = math.floor(diff / 3600)
        return hours .. " hour" .. (hours ~= 1 and "s" or "") .. " ago"
    end

    -- Less than 7 days ago
    if diff < 604800 then
        local days = math.floor(diff / 86400)
        return days .. " day" .. (days ~= 1 and "s" or "") .. " ago"
    end

    -- More than 7 days: show date
    return date("%b %d, %Y", timestamp)
end

--------------------------------------------------
-- Render Summary Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderSummaryTab()
    local frame = self.contentFrames["summary"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics
    local yOffset = -10

    -- Helper function to add section header
    local function AddHeader(text)
        local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
        header:SetText(text)
        header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
        yOffset = yOffset - 20
        return header
    end

    -- Helper function to add label + value row
    local function AddRow(label, value, valueColor)
        local labelText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        labelText:SetText(label .. ":")
        labelText:SetJustifyH("LEFT")
        labelText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        local valueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        valueText:SetPoint("LEFT", labelText, "RIGHT", 10, 0)
        valueText:SetText(value)
        valueText:SetJustifyH("LEFT")
        if valueColor then
            valueText:SetTextColor(valueColor[1], valueColor[2], valueColor[3])
        else
            valueText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        end

        yOffset = yOffset - 18
        return labelText, valueText
    end

    -- Session Info (compact)
    AddHeader("Session #" .. session.id .. " - " .. (session.zone or "Unknown"))
    AddRow("Started", FormatFriendlyDate(session.startedAt), pH_Colors.TEXT_MUTED)
    AddRow("Duration", GoldPH_SessionManager:FormatDuration(metrics.durationSec))

    yOffset = yOffset - 10

    -- Economic Summary
    AddHeader("Economic Summary")
    AddRow("Total Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.totalPerHour) .. "/hr", pH_Colors.TEXT_MUTED)
    AddRow("Cash Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour) .. "/hr", pH_Colors.ACCENT_GOOD)
    AddRow("Expected Per Hour", GoldPH_Ledger:FormatMoneyShort(metrics.expectedPerHour) .. "/hr", pH_Colors.TEXT_MUTED)

    yOffset = yOffset - 10

    -- Cash Flow Breakdown
    AddHeader("Cash Flow")
    AddRow("Looted Coin", GoldPH_Ledger:FormatMoney(metrics.income))
    AddRow("Quest Rewards", GoldPH_Ledger:FormatMoney(metrics.incomeQuest))
    AddRow("Vendor Sales", GoldPH_Ledger:FormatMoney(GoldPH_Ledger:GetBalance(session, "Income:VendorSales")))
    -- Expenses: only show negative sign and red color if value is non-zero
    local repairsText = metrics.expenseRepairs > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseRepairs)) or GoldPH_Ledger:FormatMoney(metrics.expenseRepairs)
    AddRow("Repairs", repairsText, metrics.expenseRepairs > 0 and pH_Colors.ACCENT_BAD or nil)
    local vendorBuysText = metrics.expenseVendorBuys > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseVendorBuys)) or GoldPH_Ledger:FormatMoney(metrics.expenseVendorBuys)
    AddRow("Vendor Purchases", vendorBuysText, metrics.expenseVendorBuys > 0 and pH_Colors.ACCENT_BAD or nil)
    local travelText = metrics.expenseTravel > 0 and ("-" .. GoldPH_Ledger:FormatMoney(metrics.expenseTravel)) or GoldPH_Ledger:FormatMoney(metrics.expenseTravel)
    AddRow("Travel", travelText, metrics.expenseTravel > 0 and pH_Colors.ACCENT_BAD or nil)

    yOffset = yOffset - 10

    -- Inventory Breakdown
    AddHeader("Inventory Expected")
    AddRow("Vendor Trash", GoldPH_Ledger:FormatMoney(metrics.invVendorTrash))
    AddRow("Rare/Multi", GoldPH_Ledger:FormatMoney(metrics.invRareMulti))
    AddRow("Gathering", GoldPH_Ledger:FormatMoney(metrics.invGathering))

    -- Pickpocket Summary (if present)
    if session.pickpocket and (metrics.pickpocketGold > 0 or metrics.pickpocketValue > 0) then
        yOffset = yOffset - 10
        AddHeader("Pickpocket")
        AddRow("Coin", GoldPH_Ledger:FormatMoney(metrics.pickpocketGold))
        AddRow("Items Value", GoldPH_Ledger:FormatMoney(metrics.pickpocketValue))
        AddRow("Lockboxes Looted", tostring(metrics.lockboxesLooted))
        AddRow("Lockboxes Opened", tostring(metrics.lockboxesOpened))
        if metrics.fromLockboxGold > 0 or metrics.fromLockboxValue > 0 then
            AddRow("From Lockbox Coin", GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold))
            AddRow("From Lockbox Items", GoldPH_Ledger:FormatMoney(metrics.fromLockboxValue))
        end
    end

    -- Gathering Summary (if present)
    if session.gathering and session.gathering.totalNodes and session.gathering.totalNodes > 0 then
        yOffset = yOffset - 10
        AddHeader("Gathering")
        AddRow("Total Nodes", tostring(session.gathering.totalNodes))

        local nodesPerHour = 0
        if metrics.durationHours > 0 then
            nodesPerHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end
        AddRow("Nodes Per Hour", tostring(nodesPerHour))
    end

    -- Phase 9: XP Summary (if present)
    if metrics.xpEnabled and metrics.xpGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Experience")
        AddRow("XP Gained", string.format("%d", metrics.xpGained))
        AddRow("XP Per Hour", string.format("%d/hr", metrics.xpPerHour), {0.5, 0.8, 1})  -- Blue
    end

    -- Phase 9: Reputation Summary (if present)
    if metrics.repEnabled and metrics.repGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Reputation")
        AddRow("Rep Gained", string.format("%d", metrics.repGained))
        AddRow("Rep Per Hour", string.format("%d/hr", metrics.repPerHour), {0.3, 1, 0.3})  -- Green

        -- Show top 3 factions
        if metrics.repTopFactions and #metrics.repTopFactions > 0 then
            yOffset = yOffset - 5
            local topFactionsLabel = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            topFactionsLabel:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
            topFactionsLabel:SetText("Top Factions:")
            topFactionsLabel:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
            yOffset = yOffset - 16

            for _, factionData in ipairs(metrics.repTopFactions) do
                AddRow("  " .. factionData.name, string.format("+%d", factionData.gain), {0.7, 0.7, 0.7})
            end
        end
    end

    -- Phase 9: Honor Summary (if present)
    if metrics.honorEnabled and metrics.honorGained > 0 then
        yOffset = yOffset - 10
        AddHeader("Honor")
        AddRow("Honor Gained", string.format("%d", metrics.honorGained))
        AddRow("Honor Per Hour", string.format("%d/hr", metrics.honorPerHour), {1, 0.5, 0.3})  -- Orange
        if metrics.honorKills > 0 then
            AddRow("Honorable Kills", tostring(metrics.honorKills))
        end
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Render Items Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderItemsTab()
    local frame = self.contentFrames["items"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession

    -- Check if session has items
    if not session.items or next(session.items) == nil then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("No items looted in this session")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    -- Convert items table to sorted array
    local itemsArray = {}
    for itemID, itemData in pairs(session.items) do
        table.insert(itemsArray, itemData)
    end

    -- Sort by total value descending
    table.sort(itemsArray, function(a, b)
        return a.expectedTotal > b.expectedTotal
    end)

    local yOffset = -10

    -- Add header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Items Looted")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Column headers
    local colHeaders = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colHeaders:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    colHeaders:SetText("Item Name")
    colHeaders:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colQty = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colQty:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -150, yOffset)
    colQty:SetText("Qty")
    colQty:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colValue = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colValue:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -50, yOffset)
    colValue:SetText("Value")
    colValue:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Render each item
    for _, itemData in ipairs(itemsArray) do
        -- Item name with quality color
        local itemName = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemName:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        itemName:SetText(itemData.name or "Unknown Item")
        itemName:SetJustifyH("LEFT")

        -- Apply quality color
        local quality = itemData.quality or 1
        local qColor = QualityColors[quality] or QualityColors[1]
        itemName:SetTextColor(qColor[1], qColor[2], qColor[3])

        -- Quantity
        local qtyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        qtyText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -150, yOffset)
        qtyText:SetText(tostring(itemData.count))
        qtyText:SetJustifyH("RIGHT")

        -- Value
        local valueText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        valueText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
        valueText:SetText(GoldPH_Ledger:FormatMoneyShort(itemData.expectedTotal))
        valueText:SetJustifyH("RIGHT")

        yOffset = yOffset - 16
    end

    -- Summary at bottom
    yOffset = yOffset - 10
    local totalItems = 0
    local totalValue = 0
    for _, itemData in ipairs(itemsArray) do
        totalItems = totalItems + itemData.count
        totalValue = totalValue + itemData.expectedTotal
    end

    local summaryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    summaryText:SetText(string.format("Total: %d items worth %s",
        totalItems,
        GoldPH_Ledger:FormatMoney(totalValue)))
    summaryText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    yOffset = yOffset - 20

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Render Gathering Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderGatheringTab()
    local frame = self.contentFrames["gathering"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics

    -- Check if session has gathering data
    if not session.gathering or not session.gathering.totalNodes or session.gathering.totalNodes == 0 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("No gathering data for this session")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    local yOffset = -10

    -- Add header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Gathering Statistics")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Total nodes summary
    local totalNodes = session.gathering.totalNodes
    local nodesPerHour = 0
    if metrics.durationHours > 0 then
        nodesPerHour = math.floor(totalNodes / metrics.durationHours)
    end

    local summaryText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    summaryText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    summaryText:SetText(string.format("Total Nodes: %d  |  Nodes/Hour: %d", totalNodes, nodesPerHour))
    summaryText:SetTextColor(pH_Colors.ACCENT_GOOD[1], pH_Colors.ACCENT_GOOD[2], pH_Colors.ACCENT_GOOD[3])
    yOffset = yOffset - 25

    -- Node breakdown header
    local breakdownHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    breakdownHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    breakdownHeader:SetText("Node Breakdown")
    breakdownHeader:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 20

    -- Column headers
    local colNode = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colNode:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    colNode:SetText("Node Type")
    colNode:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colCount = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colCount:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -100, yOffset)
    colCount:SetText("Count")
    colCount:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colPercent = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colPercent:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
    colPercent:SetText("% of Total")
    colPercent:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Sort nodes by count
    local nodesArray = {}
    if session.gathering.nodesByType then
        for nodeName, count in pairs(session.gathering.nodesByType) do
            table.insert(nodesArray, {name = nodeName, count = count})
        end
    end

    table.sort(nodesArray, function(a, b)
        return a.count > b.count
    end)

    -- Render each node type
    for _, nodeData in ipairs(nodesArray) do
        local nodeName = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nodeName:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        nodeName:SetText(nodeData.name)
        nodeName:SetJustifyH("LEFT")

        local nodeCount = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nodeCount:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -100, yOffset)
        nodeCount:SetText(tostring(nodeData.count))
        nodeCount:SetJustifyH("RIGHT")

        local percent = math.floor((nodeData.count / totalNodes) * 100)
        local percentText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        percentText:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -10, yOffset)
        percentText:SetText(percent .. "%")
        percentText:SetJustifyH("RIGHT")

        yOffset = yOffset - 16
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

--------------------------------------------------
-- Helper: Format percentage difference
--------------------------------------------------
local function FormatPercentDiff(current, baseline)
    if baseline == 0 then return "N/A" end
    local diff = current - baseline
    local percent = math.floor((diff / baseline) * 100)

    if percent > 0 then
        return string.format("|cff00ff00^%d%%|r", percent)  -- Green up arrow
    elseif percent < 0 then
        return string.format("|cffff0000v%d%%|r", math.abs(percent))  -- Red down arrow
    else
        return "|cff888888=0%|r"  -- Gray equals for equal
    end
end

--------------------------------------------------
-- Render Compare Tab
--------------------------------------------------
function GoldPH_History_Detail:RenderCompareTab()
    local frame = self.contentFrames["compare"]
    local scrollChild = frame.scrollChild

    -- Clear existing content
    ClearScrollChild(scrollChild)

    local session = self.currentSession
    local metrics = self.currentMetrics

    -- Get zone aggregates
    local zoneAgg = GoldPH_Index:GetZoneAggregates()
    local thisZone = session.zone or "Unknown"
    local zoneStats = zoneAgg[thisZone]

    -- Check if we have comparison data
    if not zoneStats or zoneStats.sessionCount < 2 then
        local emptyText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        emptyText:SetPoint("CENTER", scrollChild, "CENTER")
        emptyText:SetText("Not enough sessions in this zone for comparison\n(Need at least 2 sessions)")
        emptyText:SetTextColor(pH_Colors.TEXT_DISABLED[1], pH_Colors.TEXT_DISABLED[2], pH_Colors.TEXT_DISABLED[3])
        return
    end

    local yOffset = -10

    -- Header
    local header = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    header:SetText("Zone Performance Comparison")
    header:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 25

    -- Subheader
    local subheader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subheader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    subheader:SetText(string.format("Comparing against %d session%s in %s",
        zoneStats.sessionCount - 1,  -- Exclude current session
        (zoneStats.sessionCount - 1) ~= 1 and "s" or "",
        thisZone))
    subheader:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    yOffset = yOffset - 25

    -- Comparison table header
    local function AddComparisonRow(label, thisValue, avgValue, bestValue)
        -- Label
        local labelText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        labelText:SetText(label)
        labelText:SetJustifyH("LEFT")

        -- This session value
        local thisText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        thisText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 180, yOffset)
        thisText:SetText(thisValue)
        thisText:SetJustifyH("LEFT")

        -- Zone average
        local avgText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        avgText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 250, yOffset)
        avgText:SetText(avgValue)
        avgText:SetJustifyH("LEFT")
        avgText:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

        -- Difference
        local diffText = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffText:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 320, yOffset)

        -- Calculate numeric values for comparison
        local thisNumeric = tonumber(thisValue:match("%d+")) or 0
        local avgNumeric = tonumber(avgValue:match("%d+")) or 0
        diffText:SetText(FormatPercentDiff(thisNumeric, avgNumeric))
        diffText:SetJustifyH("LEFT")

        yOffset = yOffset - 18
    end

    -- Column headers
    local colThis = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colThis:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 180, yOffset)
    colThis:SetText("This")
    colThis:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colAvg = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colAvg:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 250, yOffset)
    colAvg:SetText("Zone Avg")
    colAvg:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    local colDiff = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    colDiff:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 320, yOffset)
    colDiff:SetText("Diff")
    colDiff:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])

    yOffset = yOffset - 20

    -- Gold/hour comparison
    AddComparisonRow(
        "Total g/hr",
        GoldPH_Ledger:FormatMoneyShort(metrics.totalPerHour),
        GoldPH_Ledger:FormatMoneyShort(zoneStats.avgTotalPerHour),
        nil
    )

    AddComparisonRow(
        "Cash g/hr",
        GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour),
        "N/A",  -- We don't track cash avg in zoneAgg yet
        nil
    )

    AddComparisonRow(
        "Expected g/hr",
        GoldPH_Ledger:FormatMoneyShort(metrics.expectedPerHour),
        "N/A",  -- We don't track expected avg in zoneAgg yet
        nil
    )

    -- Gathering comparison (if applicable)
    if session.gathering and session.gathering.totalNodes > 0 and zoneStats.avgNodesPerHour > 0 then
        yOffset = yOffset - 10

        local nodesPerHour = 0
        if metrics.durationHours > 0 then
            nodesPerHour = math.floor(session.gathering.totalNodes / metrics.durationHours)
        end

        AddComparisonRow(
            "Nodes/hr",
            tostring(nodesPerHour),
            tostring(math.floor(zoneStats.avgNodesPerHour)),
            nil
        )
    end

    yOffset = yOffset - 15

    -- Insights section
    local insightsHeader = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    insightsHeader:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 10, yOffset)
    insightsHeader:SetText("Insights")
    insightsHeader:SetTextColor(pH_Colors.ACCENT_GOLD[1], pH_Colors.ACCENT_GOLD[2], pH_Colors.ACCENT_GOLD[3])
    yOffset = yOffset - 20

    -- Calculate rank in zone
    local allZoneSessions = GoldPH_Index.byZone[thisZone] or {}
    local rank = 1
    for _, otherSessionId in ipairs(allZoneSessions) do
        if otherSessionId ~= session.id then
            local otherSummary = GoldPH_Index:GetSummary(otherSessionId)
            if otherSummary and otherSummary.totalPerHour > metrics.totalPerHour then
                rank = rank + 1
            end
        end
    end

    -- Insight: Performance vs average
    local perfDiff = metrics.totalPerHour - zoneStats.avgTotalPerHour
    local perfPercent = math.floor((perfDiff / zoneStats.avgTotalPerHour) * 100)
    local perfInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    perfInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)

    if perfPercent > 10 then
        perfInsight:SetText(string.format("* Great session! %d%% above zone average", perfPercent))
        perfInsight:SetTextColor(pH_Colors.ACCENT_GOOD[1], pH_Colors.ACCENT_GOOD[2], pH_Colors.ACCENT_GOOD[3])
    elseif perfPercent < -10 then
        perfInsight:SetText(string.format("* Below average by %d%% - room for improvement", math.abs(perfPercent)))
        perfInsight:SetTextColor(pH_Colors.ACCENT_BAD[1], pH_Colors.ACCENT_BAD[2], pH_Colors.ACCENT_BAD[3])
    else
        perfInsight:SetText("* Performing close to zone average")
        perfInsight:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
    end
    yOffset = yOffset - 18

    -- Insight: Rank
    local rankInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
    rankInsight:SetText(string.format("* Ranked #%d of %d sessions in this zone", rank, #allZoneSessions))
    rankInsight:SetTextColor(pH_Colors.TEXT_PRIMARY[1], pH_Colors.TEXT_PRIMARY[2], pH_Colors.TEXT_PRIMARY[3])
    yOffset = yOffset - 18

    -- Insight: Best session reference
    if zoneStats.bestSessionId and zoneStats.bestSessionId ~= session.id then
        local bestInsight = scrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        bestInsight:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 15, yOffset)
        bestInsight:SetText(string.format("* Best session in zone: %s/hr (Session #%d)",
            GoldPH_Ledger:FormatMoneyShort(zoneStats.bestTotalPerHour),
            zoneStats.bestSessionId))
        bestInsight:SetTextColor(pH_Colors.TEXT_MUTED[1], pH_Colors.TEXT_MUTED[2], pH_Colors.TEXT_MUTED[3])
        yOffset = yOffset - 18
    end

    -- Update scroll child height
    scrollChild:SetHeight(math.abs(yOffset) + 20)
end

-- Export module
_G.GoldPH_History_Detail = GoldPH_History_Detail
