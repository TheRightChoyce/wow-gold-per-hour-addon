--[[
    UI_Sessions.lua - Session history browser for GoldPH

    Uses AceGUI Frame (same as Questie) for consistent UI styling.
]]

local GoldPH_SessionsUI = {}

local sessionsFrame = nil
local isVisible = false
local selectedSessionId = nil

-- Layout constants (matching Questie's dimensions)
local FRAME_WIDTH = 1000
local FRAME_HEIGHT = 650
local ACTIVITY_LOG_HEIGHT = 120
local SESSION_LIST_WIDTH = 250
local SESSION_DETAILS_WIDTH = FRAME_WIDTH - SESSION_LIST_WIDTH - 50 -- Account for padding

-- Initialize the sessions UI (using AceGUI Frame like Questie)
function GoldPH_SessionsUI:Initialize()
    if not sessionsFrame then
        -- Get AceGUI (same way Questie does)
        local AceGUI = LibStub and LibStub("AceGUI-3.0", true)
        
        if not AceGUI then
            print("[GoldPH] Error: AceGUI-3.0 not found. Please install Ace3 library.")
            return
        end
        
        -- Create frame using AceGUI (exact same as Questie)
        sessionsFrame = AceGUI:Create("Frame")
        sessionsFrame:SetCallback("OnClose", function()
            isVisible = false
        end)
        sessionsFrame:SetTitle("GoldPH Session History")
        sessionsFrame:SetLayout("Fill")
        sessionsFrame:EnableResize(true)
        sessionsFrame:SetWidth(FRAME_WIDTH)
        sessionsFrame:SetHeight(FRAME_HEIGHT)
        
        -- Register for ESC key (matching Questie's UISpecialFrames)
        table.insert(UISpecialFrames, sessionsFrame.frame)
        
        -- Get the content frame (where we add our UI elements)
        local content = sessionsFrame.content
        
        -- Top section: Activity log
        local activityFrame = CreateFrame("ScrollFrame", "GoldPH_Sessions_Activity", content, "UIPanelScrollFrameTemplate")
        activityFrame:SetSize(FRAME_WIDTH - 50, ACTIVITY_LOG_HEIGHT)
        activityFrame:SetPoint("TOPLEFT", content, "TOPLEFT", 10, -10)
        activityFrame:SetPoint("TOPRIGHT", content, "TOPRIGHT", -10, -10)
        
        local activityContent = CreateFrame("Frame", nil, activityFrame)
        activityContent:SetSize(FRAME_WIDTH - 80, ACTIVITY_LOG_HEIGHT)
        activityFrame:SetScrollChild(activityContent)
        
        -- Title container (matching AceGUI Heading style: line-title-line)
        local titleContainer = CreateFrame("Frame", nil, activityContent)
        titleContainer:SetPoint("TOPLEFT", activityContent, "TOPLEFT", 3, 0)
        titleContainer:SetPoint("TOPRIGHT", activityContent, "TOPRIGHT", -3, 0)
        titleContainer:SetHeight(18)
        
        -- Title label (centered)
        local activityTitle = titleContainer:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
        activityTitle:SetPoint("TOP", titleContainer, "TOP")
        activityTitle:SetPoint("BOTTOM", titleContainer, "BOTTOM")
        activityTitle:SetJustifyH("CENTER")
        activityTitle:SetText("Recent Activity")
        
        -- Left line (from left edge to 5px before label)
        local leftLine = titleContainer:CreateTexture(nil, "BACKGROUND")
        leftLine:SetHeight(8)
        leftLine:SetPoint("LEFT", titleContainer, "LEFT", 0, 0)
        leftLine:SetPoint("RIGHT", activityTitle, "LEFT", -5, 0)
        leftLine:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        leftLine:SetTexCoord(0.81, 0.94, 0.5, 1)
        
        -- Right line (from 5px after label to right edge)
        local rightLine = titleContainer:CreateTexture(nil, "BACKGROUND")
        rightLine:SetHeight(8)
        rightLine:SetPoint("RIGHT", titleContainer, "RIGHT", 0, 0)
        rightLine:SetPoint("LEFT", activityTitle, "RIGHT", 5, 0)
        rightLine:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        rightLine:SetTexCoord(0.81, 0.94, 0.5, 1)
        
        local activityText = activityContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        activityText:SetPoint("TOPLEFT", titleContainer, "BOTTOMLEFT", 0, -5)
        activityText:SetPoint("RIGHT", activityContent, "RIGHT", -5, 0)
        activityText:SetJustifyH("LEFT")
        activityText:SetJustifyV("TOP")
        activityText:SetText("Loading activity...")
        sessionsFrame.activityText = activityText
        sessionsFrame.activityContent = activityContent
        
        -- Session History header (matching AceGUI Heading style: line-title-line)
        local sessionHistoryHeader = CreateFrame("Frame", nil, content)
        sessionHistoryHeader:SetPoint("TOPLEFT", activityFrame, "BOTTOMLEFT", 3, -10)
        sessionHistoryHeader:SetPoint("TOPRIGHT", activityFrame, "BOTTOMRIGHT", -3, -10)
        sessionHistoryHeader:SetHeight(18)
        
        -- Title label (centered)
        local sessionHistoryTitle = sessionHistoryHeader:CreateFontString(nil, "BACKGROUND", "GameFontNormal")
        sessionHistoryTitle:SetPoint("TOP", sessionHistoryHeader, "TOP")
        sessionHistoryTitle:SetPoint("BOTTOM", sessionHistoryHeader, "BOTTOM")
        sessionHistoryTitle:SetJustifyH("CENTER")
        sessionHistoryTitle:SetText("Session History")
        
        -- Left line (from left edge to 5px before label)
        local sessionHistoryLeftLine = sessionHistoryHeader:CreateTexture(nil, "BACKGROUND")
        sessionHistoryLeftLine:SetHeight(8)
        sessionHistoryLeftLine:SetPoint("LEFT", sessionHistoryHeader, "LEFT", 0, 0)
        sessionHistoryLeftLine:SetPoint("RIGHT", sessionHistoryTitle, "LEFT", -5, 0)
        sessionHistoryLeftLine:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        sessionHistoryLeftLine:SetTexCoord(0.81, 0.94, 0.5, 1)
        
        -- Right line (from 5px after label to right edge)
        local sessionHistoryRightLine = sessionHistoryHeader:CreateTexture(nil, "BACKGROUND")
        sessionHistoryRightLine:SetHeight(8)
        sessionHistoryRightLine:SetPoint("RIGHT", sessionHistoryHeader, "RIGHT", 0, 0)
        sessionHistoryRightLine:SetPoint("LEFT", sessionHistoryTitle, "RIGHT", 5, 0)
        sessionHistoryRightLine:SetTexture("Interface\\Tooltips\\UI-Tooltip-Border")
        sessionHistoryRightLine:SetTexCoord(0.81, 0.94, 0.5, 1)
        
        -- Bottom section: Sessions list (left) and details (right)
        local bottomFrame = CreateFrame("Frame", nil, content)
        bottomFrame:SetPoint("TOPLEFT", sessionHistoryHeader, "BOTTOMLEFT", 0, -5)
        bottomFrame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -10, 10)
        sessionsFrame.bottomFrame = bottomFrame
        
        -- Sessions list (left side)
        local sessionsListFrame = CreateFrame("ScrollFrame", "GoldPH_Sessions_List", bottomFrame, "UIPanelScrollFrameTemplate")
        sessionsListFrame:SetSize(SESSION_LIST_WIDTH, bottomFrame:GetHeight())
        sessionsListFrame:SetPoint("LEFT", bottomFrame, "LEFT", 10, 0)  -- Add padding from left edge
        
        local sessionsListContent = CreateFrame("Frame", nil, sessionsListFrame)
        sessionsListContent:SetSize(SESSION_LIST_WIDTH - 30, bottomFrame:GetHeight())  -- -30 accounts for scrollbar + padding
        sessionsListFrame:SetScrollChild(sessionsListContent)
        
        local sessionsListTitle = sessionsListContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sessionsListTitle:SetPoint("TOPLEFT", sessionsListContent, "TOPLEFT", 5, 0)
        sessionsListTitle:SetText("Sessions")
        
        sessionsFrame.sessionsListContent = sessionsListContent
        
        -- Session details (right side)
        local detailsFrame = CreateFrame("ScrollFrame", "GoldPH_Sessions_Details", bottomFrame, "UIPanelScrollFrameTemplate")
        detailsFrame:SetSize(SESSION_DETAILS_WIDTH, bottomFrame:GetHeight())
        detailsFrame:SetPoint("LEFT", sessionsListFrame, "RIGHT", 10, 0)
        detailsFrame:SetPoint("RIGHT", bottomFrame, "RIGHT", -10, 0)  -- Add padding from right edge
        
        -- Content frame needs to account for scrollbar width (~20px) and padding
        local detailsContent = CreateFrame("Frame", nil, detailsFrame)
        detailsContent:SetSize(SESSION_DETAILS_WIDTH - 30, bottomFrame:GetHeight())  -- -30 accounts for scrollbar + padding
        detailsFrame:SetScrollChild(detailsContent)
        
        local detailsTitle = detailsContent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        detailsTitle:SetPoint("TOPLEFT", detailsContent, "TOPLEFT", 5, 0)
        detailsTitle:SetText("Session Details")
        
        local detailsText = detailsContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detailsText:SetPoint("TOPLEFT", detailsTitle, "BOTTOMLEFT", 0, -5)
        detailsText:SetPoint("RIGHT", detailsContent, "RIGHT", -25, 0)  -- Extra padding to avoid scrollbar overlap
        detailsText:SetJustifyH("LEFT")
        detailsText:SetJustifyV("TOP")
        detailsText:SetText("Select a session to view details.")
        sessionsFrame.detailsText = detailsText
        sessionsFrame.detailsContent = detailsContent
        
        -- Initially hidden
        sessionsFrame:Hide()
    end
end

-- Update activity log
function GoldPH_SessionsUI:UpdateActivityLog()
    if not sessionsFrame or not sessionsFrame.activityText then
        return
    end
    
    local session = GoldPH_SessionManager:GetActiveSession()
    local lines = {}
    
    if not session then
        table.insert(lines, "No active session.")
    else
        -- Ensure eventLog exists
        if not session.eventLog then
            session.eventLog = {}
        end
        
        -- Filter events: only show those worth at least 20 silver (2000 copper)
        -- Use absolute value for expenses (we want to show significant expenses too)
        local MIN_VALUE_COPPER = 2000  -- 20 silver
        local filteredEvents = {}
        for i = #session.eventLog, 1, -1 do
            local event = session.eventLog[i]
            local absValue = math.abs(event.valueCopper or 0)
            if absValue >= MIN_VALUE_COPPER then
                table.insert(filteredEvents, event)
            end
        end
        
        if #filteredEvents == 0 then
            table.insert(lines, "No significant activity recorded yet.")
            table.insert(lines, "(Showing events worth at least 20s)")
        else
            -- Show last 20 filtered events (most recent first)
            local displayCount = math.min(20, #filteredEvents)
            for i = 1, displayCount do
                local event = filteredEvents[i]
                
                -- Questie-style formatting: "[ Day, Month DD @ HH:MM ]  Action description"
                local timeStr
                if date then
                    -- Get day name (0-6, where 0=Sunday)
                    local dayOfWeek = tonumber(date('%w', event.timestamp))
                    local dayName = CALENDAR_WEEKDAY_NAMES[dayOfWeek + 1] or "Unknown"
                    
                    -- Get month name (1-12)
                    local monthNum = tonumber(date('%m', event.timestamp))
                    local monthName = CALENDAR_FULLDATE_MONTH_NAMES[monthNum] or "Unknown"
                    
                    -- Format: "[ Day, Month DD @ HH:MM ]  "
                    timeStr = date('[ ' .. dayName .. ', ' .. monthName .. ' %d @ %H:%M ]  ', event.timestamp)
                else
                    -- Fallback if date() not available
                    timeStr = string.format("[ %s ]  ", tostring(event.timestamp))
                end
                
                table.insert(lines, timeStr .. event.message)
            end
        end
    end
    
    sessionsFrame.activityText:SetText(table.concat(lines, "\n"))
    
    -- Update scroll height
    local textHeight = sessionsFrame.activityText:GetStringHeight()
    sessionsFrame.activityContent:SetHeight(math.max(ACTIVITY_LOG_HEIGHT, textHeight + 30))
end

-- Update sessions list
function GoldPH_SessionsUI:UpdateSessionsList()
    if not sessionsFrame or not sessionsFrame.sessionsListContent then
        return
    end
    
    -- Clear existing buttons
    for i = 1, sessionsFrame.sessionsListContent:GetNumChildren() do
        local child = select(i, sessionsFrame.sessionsListContent:GetChildren())
        if child and child:GetName() and string.find(child:GetName(), "GoldPH_SessionButton") then
            child:Hide()
            child:SetParent(nil)
        end
    end
    
    local sessions = GoldPH_SessionManager:ListSessions()
    
    if #sessions == 0 then
        local noSessionsText = sessionsFrame.sessionsListContent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        noSessionsText:SetPoint("TOPLEFT", sessionsFrame.sessionsListContent, "TOPLEFT", 5, -30)
        noSessionsText:SetText("No sessions found")
        return
    end
    
    local buttonHeight = 40
    local yOffset = -30
    
    for i, session in ipairs(sessions) do
        local button = CreateFrame("Button", "GoldPH_SessionButton_" .. session.id, sessionsFrame.sessionsListContent, "BackdropTemplate")
        button:SetSize(SESSION_LIST_WIDTH - 35, buttonHeight)
        button:SetPoint("TOPLEFT", sessionsFrame.sessionsListContent, "TOPLEFT", 5, yOffset)
        
        -- Highlight if selected
        if selectedSessionId == session.id then
            button:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            button:SetBackdropColor(0.2, 0.4, 0.8, 0.5)
            button:SetBackdropBorderColor(0.4, 0.6, 1, 1)
        else
            button:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true,
                tileSize = 16,
                edgeSize = 8,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            button:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
            button:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.5)
        end
        
        -- Session info text
        local metrics = GoldPH_SessionManager:GetMetrics(session)
        local dateStr
        if date then
            dateStr = date("%m/%d %H:%M", session.startedAt)
        else
            dateStr = tostring(session.startedAt)
        end
        
        local status = session.endedAt and "" or " [ACTIVE]"
        local gold = GoldPH_Ledger:FormatMoneyShort(metrics.cash)
        
        local sessionText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        sessionText:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -5)
        sessionText:SetPoint("RIGHT", button, "RIGHT", -5, 0)
        sessionText:SetJustifyH("LEFT")
        sessionText:SetText(string.format("Session #%d%s\n%s | %s", session.id, status, dateStr, gold))
        
        -- Click handler
        button:SetScript("OnClick", function()
            selectedSessionId = session.id
            GoldPH_SessionsUI:UpdateSessionsList()
            GoldPH_SessionsUI:UpdateSessionDetails(session)
        end)
        
        -- Hover effect
        button:SetScript("OnEnter", function(self)
            if selectedSessionId ~= session.id then
                self:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
            end
        end)
        button:SetScript("OnLeave", function(self)
            if selectedSessionId ~= session.id then
                self:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
            end
        end)
        
        yOffset = yOffset - buttonHeight - 5
    end
    
    -- Update content height for scrolling
    sessionsFrame.sessionsListContent:SetHeight(math.abs(yOffset) + 10)
end

-- Use shared formatting functions from UI_HUD
local FormatAccounting = function(copper) return GoldPH_HUD:FormatAccounting(copper) end
local FormatAccountingShort = function(copper) return GoldPH_HUD:FormatAccountingShort(copper) end
local GetValueColorCode = function(amount, isIncome, isExpense, isNet) return GoldPH_HUD:GetValueColorCode(amount, isIncome, isExpense, isNet) end

local COLOR_RESET = "|r"

-- Update session details panel
function GoldPH_SessionsUI:UpdateSessionDetails(session)
    if not sessionsFrame or not sessionsFrame.detailsText or not session then
        return
    end
    
    local metrics = GoldPH_SessionManager:GetMetrics(session)
    local lines = {}
    
    -- Basic info
    local dateStr
    if date then
        dateStr = date("%Y-%m-%d %H:%M:%S", session.startedAt)
    else
        dateStr = tostring(session.startedAt)
    end
    
    table.insert(lines, string.format("Session #%d", session.id))
    table.insert(lines, string.format("Started: %s", dateStr))
    
    if session.endedAt then
        local endDateStr
        if date then
            endDateStr = date("%Y-%m-%d %H:%M:%S", session.endedAt)
        else
            endDateStr = tostring(session.endedAt)
        end
        table.insert(lines, string.format("Ended: %s", endDateStr))
    else
        table.insert(lines, "Status: ACTIVE")
    end
    
    table.insert(lines, string.format("Duration: %s", GoldPH_SessionManager:FormatDuration(metrics.durationSec)))
    table.insert(lines, string.format("Zone: %s", session.zone or "Unknown"))
    table.insert(lines, "")
    
    -- Gold metrics (HUD-style: label on left, value on right, gold color)
    local cashColor = GetValueColorCode(metrics.cash, false, false, true)
    local cashHrColor = GetValueColorCode(metrics.cashPerHour, false, false, true)
    table.insert(lines, "Gold")
    table.insert(lines, string.format("  Cash: %s%s%s", cashColor, FormatAccounting(metrics.cash), COLOR_RESET))
    table.insert(lines, string.format("  Cash/Hour: %s%s%s", cashHrColor, FormatAccountingShort(metrics.cashPerHour), COLOR_RESET))
    table.insert(lines, "")
    
    -- Income breakdown (green color)
    if metrics.income > 0 or metrics.incomeQuest > 0 then
        table.insert(lines, "Income")
        if metrics.income > 0 then
            local incomeColor = GetValueColorCode(metrics.income, true, false, false)
            table.insert(lines, string.format("  Looted Coin: %s%s%s", incomeColor, FormatAccounting(metrics.income), COLOR_RESET))
        end
        if metrics.incomeQuest > 0 then
            local questColor = GetValueColorCode(metrics.incomeQuest, true, false, false)
            table.insert(lines, string.format("  Quest Rewards: %s%s%s", questColor, FormatAccounting(metrics.incomeQuest), COLOR_RESET))
        end
        table.insert(lines, "")
    end
    
    -- Expense breakdown (red color)
    if metrics.totalExpenses ~= 0 then
        table.insert(lines, "Expenses")
        if metrics.expenseRepairs ~= 0 then
            local repairColor = GetValueColorCode(-metrics.expenseRepairs, false, true, false)
            table.insert(lines, string.format("  Repairs: %s%s%s", repairColor, FormatAccounting(metrics.expenseRepairs), COLOR_RESET))
        end
        if metrics.expenseVendorBuys ~= 0 then
            local vendorColor = GetValueColorCode(-metrics.expenseVendorBuys, false, true, false)
            table.insert(lines, string.format("  Vendor Purchases: %s%s%s", vendorColor, FormatAccounting(metrics.expenseVendorBuys), COLOR_RESET))
        end
        if metrics.expenseTravel ~= 0 then
            local travelColor = GetValueColorCode(-metrics.expenseTravel, false, true, false)
            table.insert(lines, string.format("  Travel: %s%s%s", travelColor, FormatAccounting(metrics.expenseTravel), COLOR_RESET))
        end
        local totalExpColor = GetValueColorCode(-metrics.totalExpenses, false, true, false)
        table.insert(lines, string.format("  Total Expenses: %s%s%s", totalExpColor, FormatAccounting(metrics.totalExpenses), COLOR_RESET))
        table.insert(lines, "")
    end
    
    -- Inventory value (white/neutral)
    table.insert(lines, "Inventory")
    table.insert(lines, string.format("  Expected Value: %s", FormatAccounting(metrics.expectedInventory)))
    table.insert(lines, string.format("  Expected/Hour: %s", FormatAccountingShort(metrics.expectedPerHour)))
    table.insert(lines, "")
    
    -- Total value (gold color)
    local totalColor = GetValueColorCode(metrics.totalValue, false, false, true)
    local totalHrColor = GetValueColorCode(metrics.totalPerHour, false, false, true)
    table.insert(lines, "Total Economic Value")
    table.insert(lines, string.format("  Total: %s%s%s", totalColor, FormatAccounting(metrics.totalValue), COLOR_RESET))
    table.insert(lines, string.format("  Total/Hour: %s%s%s", totalHrColor, FormatAccountingShort(metrics.totalPerHour), COLOR_RESET))
    table.insert(lines, "")
    
    -- Gathering nodes (white/neutral)
    if metrics.gatheringTotalNodes and metrics.gatheringTotalNodes > 0 then
        table.insert(lines, "Gathering")
        table.insert(lines, string.format("  Total Nodes: %d", metrics.gatheringTotalNodes))
        table.insert(lines, string.format("  Nodes/Hour: %d", metrics.gatheringNodesPerHour or 0))
        if metrics.gatheringNodesByType and next(metrics.gatheringNodesByType) then
            table.insert(lines, "By Type:")
            local sortedTypes = {}
            for nodeName, count in pairs(metrics.gatheringNodesByType) do
                table.insert(sortedTypes, {name = nodeName, count = count})
            end
            table.sort(sortedTypes, function(a, b) return a.count > b.count end)
            for _, node in ipairs(sortedTypes) do
                table.insert(lines, string.format("  %s: %d", node.name, node.count))
            end
        end
        table.insert(lines, "")
    end
    
    -- Pickpocket stats
    if metrics.pickpocketGold > 0 or metrics.pickpocketValue > 0 or metrics.lockboxesLooted > 0 then
        table.insert(lines, "=== Pickpocket ===")
        table.insert(lines, string.format("Coin: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketGold)))
        table.insert(lines, string.format("Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.pickpocketValue)))
        table.insert(lines, string.format("Lockboxes Looted: %d", metrics.lockboxesLooted))
        table.insert(lines, string.format("Lockboxes Opened: %d", metrics.lockboxesOpened))
        if metrics.fromLockboxGold > 0 or metrics.fromLockboxValue > 0 then
            table.insert(lines, "From Lockboxes:")
            table.insert(lines, string.format("  Coin: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxGold)))
            table.insert(lines, string.format("  Items Value: %s", GoldPH_Ledger:FormatMoney(metrics.fromLockboxValue)))
        end
        table.insert(lines, "")
    end
    
    sessionsFrame.detailsText:SetText(table.concat(lines, "\n"))
    
    -- Update scroll height
    local textHeight = sessionsFrame.detailsText:GetStringHeight()
    local bottomHeight = sessionsFrame.bottomFrame and sessionsFrame.bottomFrame:GetHeight() or (FRAME_HEIGHT - ACTIVITY_LOG_HEIGHT - 100)
    sessionsFrame.detailsContent:SetHeight(math.max(bottomHeight, textHeight + 30))
end

-- Show the sessions UI
function GoldPH_SessionsUI:Show()
    if not sessionsFrame then
        self:Initialize()
    end
    
    if sessionsFrame then
        sessionsFrame:Show()
        isVisible = true
        
        -- Update all panels
        self:UpdateActivityLog()
        self:UpdateSessionsList()
        
        -- Select first session if available
        local sessions = GoldPH_SessionManager:ListSessions(1)
        if #sessions > 0 then
            selectedSessionId = sessions[1].id
            self:UpdateSessionsList()
            self:UpdateSessionDetails(sessions[1])
        end
    end
end

-- Hide the sessions UI
function GoldPH_SessionsUI:Hide()
    if sessionsFrame then
        sessionsFrame:Hide()
    end
    isVisible = false
end

-- Toggle the sessions UI
function GoldPH_SessionsUI:Toggle()
    if isVisible then
        self:Hide()
    else
        self:Show()
    end
end

-- Export module
_G.GoldPH_SessionsUI = GoldPH_SessionsUI
