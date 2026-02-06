--[[
    UI_History.lua - Main history frame controller for GoldPH

    Manages the session history window with filters, list, and detail panes.
]]

-- luacheck: globals GoldPH_Settings

local GoldPH_History = {
    frame = nil,
    listPane = nil,
    detailPane = nil,
    filtersPane = nil,
    isInitialized = false,

    -- Current state
    selectedSessionId = nil,
    filterState = {
        mode = "gold",
        search = "",
        sort = "totalPerHour",
        sortDesc = true,
        charKeys = nil,
        zone = nil,
        minPerHour = 0,
        hasGathering = false,
        hasPickpocket = false,
    },
}

--------------------------------------------------
-- Initialize
--------------------------------------------------
function GoldPH_History:Initialize()
    if self.isInitialized then
        return
    end

    -- Create main frame (640x480, centered)
    local frame = CreateFrame("Frame", "GoldPH_HistoryFrame", UIParent, "BackdropTemplate")
    frame:SetSize(640, 480)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:Hide()

    -- Enable Escape key to close (taint-free method)
    table.insert(UISpecialFrames, "GoldPH_HistoryFrame")

    -- Enable keyboard navigation
    frame:EnableKeyboard(true)
    frame:SetScript("OnKeyDown", function(self, key)
        GoldPH_History:OnKeyDown(key)
    end)

    -- Backdrop
    frame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Session History")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -5, -5)
    closeBtn:SetScript("OnClick", function()
        GoldPH_History:Hide()
    end)

    -- Filters pane (top, 40px height)
    local filtersPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    filtersPane:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -35)
    filtersPane:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -35)
    filtersPane:SetHeight(40)
    self.filtersPane = filtersPane

    -- List pane (left, 240px width)
    local listPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    listPane:SetPoint("TOPLEFT", filtersPane, "BOTTOMLEFT", 0, -5)
    listPane:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    listPane:SetWidth(240)
    listPane:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    listPane:SetBackdropColor(0.05, 0.05, 0.05, 1)
    listPane:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    self.listPane = listPane

    -- Detail pane (right, remaining width)
    local detailPane = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    detailPane:SetPoint("TOPLEFT", listPane, "TOPRIGHT", 5, 0)
    detailPane:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)
    detailPane:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}
    })
    detailPane:SetBackdropColor(0.05, 0.05, 0.05, 1)
    detailPane:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    self.detailPane = detailPane

    self.frame = frame

    -- Initialize sub-components
    GoldPH_History_Filters:Initialize(self.filtersPane, self)
    GoldPH_History_List:Initialize(self.listPane, self)
    GoldPH_History_Detail:Initialize(self.detailPane, self)

    self.isInitialized = true
end

--------------------------------------------------
-- Show/Hide/Toggle
--------------------------------------------------
function GoldPH_History:Show()
    if not self.isInitialized then
        self:Initialize()
    end

    -- Show frame first
    self.frame:Show()

    -- Build index if stale (with loading message)
    if GoldPH_Index.stale then
        -- Show loading message
        local loadingText = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        loadingText:SetPoint("CENTER", self.frame, "CENTER")
        loadingText:SetText("Building index...")
        loadingText:SetTextColor(1, 0.82, 0)

        -- Build index
        GoldPH_Index:Build()

        -- Remove loading message
        loadingText:Hide()
    end

    -- Restore position if saved
    if GoldPH_Settings.historyPosition then
        local pos = GoldPH_Settings.historyPosition
        self.frame:ClearAllPoints()
        self.frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    end

    -- Restore filter state
    if GoldPH_Settings.historyFilters then
        for k, v in pairs(GoldPH_Settings.historyFilters) do
            self.filterState[k] = v
        end
    end

    -- Apply filters and refresh list
    self:RefreshList()

    -- Auto-select first session if none selected
    if not self.selectedSessionId then
        local sessionIds = GoldPH_Index:QuerySessions(self.filterState)
        if #sessionIds > 0 then
            self:SelectSession(sessionIds[1])
        end
    end

    GoldPH_Settings.historyVisible = true
end

function GoldPH_History:Hide()
    if not self.frame then
        return
    end

    -- Save position
    local point, _, relativePoint, x, y = self.frame:GetPoint()
    GoldPH_Settings.historyPosition = {
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }

    -- Save filter state
    GoldPH_Settings.historyFilters = {}
    for k, v in pairs(self.filterState) do
        GoldPH_Settings.historyFilters[k] = v
    end

    self.frame:Hide()
    GoldPH_Settings.historyVisible = false
end

function GoldPH_History:Toggle()
    if not self.isInitialized then
        self:Show()
    elseif self.frame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

--------------------------------------------------
-- Refresh List (called when filters change)
--------------------------------------------------
function GoldPH_History:RefreshList()
    -- Query sessions with current filters
    local sessionIds = GoldPH_Index:QuerySessions(self.filterState)

    -- Update list component
    GoldPH_History_List:SetSessions(sessionIds)
end

--------------------------------------------------
-- Select Session (called when user clicks a session)
--------------------------------------------------
function GoldPH_History:SelectSession(sessionId)
    self.selectedSessionId = sessionId

    -- Notify list to update highlight
    GoldPH_History_List:SetSelection(sessionId)

    -- Notify detail pane to show session
    GoldPH_History_Detail:SetSession(sessionId)
end

--------------------------------------------------
-- Get Selected Session ID
--------------------------------------------------
function GoldPH_History:GetSelectedSession()
    return self.selectedSessionId
end

--------------------------------------------------
-- Keyboard Navigation
--------------------------------------------------
function GoldPH_History:OnKeyDown(key)
    if key == "UP" or key == "DOWN" then
        -- Get current filtered session list
        local sessionIds = GoldPH_Index:QuerySessions(self.filterState)
        if #sessionIds == 0 then
            return
        end

        -- Find current selection index
        local currentIndex = 1
        if self.selectedSessionId then
            for i, sessionId in ipairs(sessionIds) do
                if sessionId == self.selectedSessionId then
                    currentIndex = i
                    break
                end
            end
        end

        -- Move up or down
        if key == "UP" then
            currentIndex = math.max(1, currentIndex - 1)
        else -- DOWN
            currentIndex = math.min(#sessionIds, currentIndex + 1)
        end

        -- Select new session
        self:SelectSession(sessionIds[currentIndex])

        -- Scroll list to make selection visible
        GoldPH_History_List:ScrollToSelection(currentIndex)
    end
end

-- Export module
_G.GoldPH_History = GoldPH_History
