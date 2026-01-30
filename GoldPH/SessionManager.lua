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

        -- Additional fields added in later phases:
        -- items = {},
        -- holdings = {},
        -- gathering = {},
        -- pickpocket = {},
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

    -- Phase 1: Only cash tracking
    local cash = GoldPH_Ledger:GetBalance(session, "Assets:Cash")
    local cashPerHour = 0
    if durationHours > 0 then
        cashPerHour = math.floor(cash / durationHours)
    end

    return {
        durationSec = durationSec,
        durationHours = durationHours,
        cash = cash,
        cashPerHour = cashPerHour,

        -- Phase 3+: Expected inventory value
        -- expectedInventory = 0,
        -- expectedPerHour = 0,

        -- Phase 3+: Total economic value
        -- totalValue = cash,
        -- totalPerHour = cashPerHour,
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

-- Export module
_G.GoldPH_SessionManager = GoldPH_SessionManager
