--[[
    init.lua - Entry point for GoldPH

    Handles initialization, slash commands, and event frame setup.
    Account-wide: GoldPH_DB_Account (sessions). Per-character: GoldPH_DB (legacy migration), GoldPH_Settings (UI).
]]

-- luacheck: globals GoldPH_DB GoldPH_DB_Account GoldPH_Settings

-- Create main addon frame
local GoldPH_MainFrame = CreateFrame("Frame", "GoldPH_MainFrame")

-- Migration version: after migrating, set this so we can remove migration code later
local MIGRATION_VERSION = 2

-- Ensure account-wide DB exists and migrate from per-character if needed
local function EnsureAccountDB()
    if not GoldPH_DB_Account then
        GoldPH_DB_Account = {
            meta = { version = MIGRATION_VERSION, lastSessionId = 0 },
            priceOverrides = {},
            activeSession = nil,
            sessions = {},
            debug = { enabled = false, verbose = false, lastTestResults = {} },
        }
    end
    if not GoldPH_DB_Account.meta then
        GoldPH_DB_Account.meta = { version = MIGRATION_VERSION, lastSessionId = 0 }
    end
    if GoldPH_DB_Account.meta.lastSessionId == nil then
        GoldPH_DB_Account.meta.lastSessionId = 0
    end
end

-- Merge current character's sessions from per-char GoldPH_DB into GoldPH_DB_Account
local function MigrateFromPerCharacter()
    if not GoldPH_DB or not GoldPH_DB.sessions then
        return
    end
    EnsureAccountDB()
    local account = GoldPH_DB_Account
    local charSessions = GoldPH_DB.sessions
    local maxId = account.meta.lastSessionId or 0
    for sid, session in pairs(charSessions) do
        if account.sessions[sid] then
            -- ID conflict: assign new id
            maxId = maxId + 1
            session.id = maxId
            account.sessions[maxId] = session
        else
            account.sessions[sid] = session
            if sid > maxId then
                maxId = sid
            end
        end
        -- Backfill character metadata for old sessions
        if not session.character and GoldPH_DB.meta then
            session.character = GoldPH_DB.meta.character or "Unknown"
            session.realm = GoldPH_DB.meta.realm or "Unknown"
            session.faction = GoldPH_DB.meta.faction or "Unknown"
        end
    end
    account.meta.lastSessionId = maxId
    -- Merge activeSession if it belongs to this character (same as current)
    if GoldPH_DB.activeSession then
        account.activeSession = GoldPH_DB.activeSession
        if not account.activeSession.character and GoldPH_DB.meta then
            account.activeSession.character = GoldPH_DB.meta.character or "Unknown"
            account.activeSession.realm = GoldPH_DB.meta.realm or "Unknown"
            account.activeSession.faction = GoldPH_DB.meta.faction or "Unknown"
        end
    end
    -- Merge price overrides
    if GoldPH_DB.priceOverrides then
        for itemID, copper in pairs(GoldPH_DB.priceOverrides) do
            if not account.priceOverrides[itemID] then
                account.priceOverrides[itemID] = copper
            end
        end
    end
    -- Preserve debug if set
    if GoldPH_DB.debug then
        if GoldPH_DB.debug.verbose then
            account.debug.verbose = true
        end
        if GoldPH_DB.debug.enabled then
            account.debug.enabled = true
        end
    end
end

-- Initialize saved variables on first load
local function InitializeSavedVariables()
    EnsureAccountDB()
    -- Migrate from per-character DB (GoldPH_DB) into account DB
    MigrateFromPerCharacter()

    -- Per-character settings (UI state)
    if not GoldPH_Settings then
        GoldPH_Settings = {
            trackZone = true,
            hudVisible = true,
            hudMinimized = false,
            historyVisible = false,
            historyMinimized = false,
            historyPosition = nil,
            historyActiveTab = "summary",
            historyFilters = { sort = "totalPerHour" },
        }
        -- Copy from legacy if present
        if GoldPH_DB and GoldPH_DB.settings then
            for k, v in pairs(GoldPH_DB.settings) do
                GoldPH_Settings[k] = v
            end
        end
    end

    -- Rest of addon uses GoldPH_DB_Account (see SessionManager, Index, Events, UI_*, etc.)
end

-- Addon loaded event handler
GoldPH_MainFrame:RegisterEvent("ADDON_LOADED")
GoldPH_MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GoldPH_MainFrame:RegisterEvent("PLAYER_LOGOUT")
GoldPH_MainFrame:SetScript("OnEvent", function(self, event, ...)
    local addonName = select(1, ...)

    if event == "ADDON_LOADED" and addonName == "GoldPH" then
        InitializeSavedVariables()

        -- Initialize UI
        GoldPH_HUD:Initialize()

        -- Initialize event system (registers additional events)
        GoldPH_Events:Initialize(GoldPH_MainFrame)

        local charName = UnitName("player") or "Unknown"
        local realm = GetRealmName() or "Unknown"
        print("[GoldPH] Version 0.8.0 (cross-character sessions) loaded. Type /goldph help for commands.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure settings exist
        if not GoldPH_Settings then
            GoldPH_Settings = {
                trackZone = true,
                hudVisible = true,
                hudMinimized = false,
                historyVisible = false,
                historyMinimized = false,
                historyPosition = nil,
                historyActiveTab = "summary",
                historyFilters = { sort = "totalPerHour" },
            }
        end
        if GoldPH_Settings.hudVisible == nil then
            GoldPH_Settings.hudVisible = true
        end
        if GoldPH_Settings.hudMinimized == nil then
            GoldPH_Settings.hudMinimized = false
        end

        -- Ensure active session has duration tracking fields
        local session = GoldPH_DB_Account.activeSession
        if session then
            local wasNewLogin = false
            if session.accumulatedDuration == nil then
                session.accumulatedDuration = 0
            end
            if session.currentLoginAt == nil then
                session.currentLoginAt = time()
                wasNewLogin = true
            end

            if GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format(
                    "[GoldPH Debug] PLAYER_ENTERING_WORLD | Session #%d | accumulatedDuration=%d | currentLoginAt=%s | wasNewLogin=%s",
                    session.id,
                    session.accumulatedDuration,
                    tostring(session.currentLoginAt),
                    tostring(wasNewLogin)
                ))
            end
        end

        -- Auto-restore HUD visibility and state if session is active
        if GoldPH_DB_Account.activeSession then
            if GoldPH_Settings.hudVisible then
                GoldPH_HUD:Show()
                GoldPH_HUD:ApplyMinimizeState()
            else
                GoldPH_HUD:Update()
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Fold the current login segment into the session accumulator on logout
        local session = GoldPH_DB_Account.activeSession
        if session and session.currentLoginAt then
            local now = time()
            local segmentDuration = now - session.currentLoginAt
            local oldAccumulated = session.accumulatedDuration
            session.accumulatedDuration = session.accumulatedDuration + segmentDuration
            session.currentLoginAt = nil

            if GoldPH_DB_Account.debug and GoldPH_DB_Account.debug.verbose then
                print(string.format(
                    "[GoldPH Debug] PLAYER_LOGOUT | Session #%d | segmentDuration=%ds | oldAccumulated=%d | newAccumulated=%d",
                    session.id,
                    segmentDuration,
                    oldAccumulated,
                    session.accumulatedDuration
                ))
            end
        end

        GoldPH_Events:OnEvent(event, ...)
    else
        GoldPH_Events:OnEvent(event, ...)
    end
end)

--------------------------------------------------
-- Slash Commands
--------------------------------------------------

local function ShowHelp()
    print("|cff00ff00=== GoldPH Commands ===|r")
    print("|cffffff00/goldph start|r - Start a new session")
    print("|cffffff00/goldph stop|r - Stop the active session")
    print("|cffffff00/goldph show|r - Show/hide the HUD")
    print("|cffffff00/goldph status|r - Show current session status")
    print("|cffffff00/goldph history|r - Open session history")
    print("")
    print("|cff00ff00=== Debug Commands ===|r")
    print("|cffffff00/goldph debug on|off|r - Enable/disable debug mode (auto-run invariants)")
    print("|cffffff00/goldph debug verbose on|off|r - Enable/disable verbose logging")
    print("|cffffff00/goldph debug dump|r - Dump current session state")
    print("|cffffff00/goldph debug ledger|r - Show ledger balances")
    print("|cffffff00/goldph debug holdings|r - Show holdings (Phase 3+)")
    print("|cffffff00/goldph debug prices|r - Show available price sources (TSM, Custom AH)")
    print("|cffffff00/goldph debug pickpocket|r - Show pickpocket statistics (Phase 6)")
    print("")
    print("|cff00ff00=== Test Commands ===|r")
    print("|cffffff00/goldph test run|r - Run automated test suite")
    print("|cffffff00/goldph test hud|r - Populate HUD with sample data for testing")
    print("|cffffff00/goldph test reset|r - Reset to fresh session")
    print("|cffffff00/goldph test loot <copper>|r - Inject looted coin event")
    print("|cffffff00/goldph test repair <copper>|r - Inject repair cost (Phase 2+)")
    print("|cffffff00/goldph test lootitem <itemID> <count>|r - Inject looted item (Phase 3+)")
    print("|cffffff00/goldph test vendoritem <itemID> <count>|r - Inject vendor sale (Phase 4+)")
    print("======================")
end

local function HandleCommand(msg)
    local args = {}
    for word in msg:gmatch("%S+") do
        table.insert(args, word)
    end

    local cmd = args[1] or "help"
    cmd = cmd:lower()

    local debugShortcuts = {
        dump = true, ledger = true, holdings = true, prices = true, pickpocket = true,
        on = true, off = true, verbose = true,
    }
    if debugShortcuts[cmd] then
        table.insert(args, 1, "debug")
        cmd = "debug"
    end

    if cmd == "start" then
        local ok, message = GoldPH_SessionManager:StartSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Show()
        end

    elseif cmd == "stop" then
        local ok, message = GoldPH_SessionManager:StopSession()
        print("[GoldPH] " .. message)
        GoldPH_HUD:Update()

    elseif cmd == "show" then
        GoldPH_HUD:Toggle()

    elseif cmd == "status" then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local metrics = GoldPH_SessionManager:GetMetrics(session)
            print(string.format("[GoldPH] Session #%d | Duration: %s | Cash: %s | Cash/hr: %s",
                                session.id,
                                GoldPH_SessionManager:FormatDuration(metrics.durationSec),
                                GoldPH_Ledger:FormatMoney(metrics.cash),
                                GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour)))
        else
            print("[GoldPH] No active session")
        end

    elseif cmd == "history" then
        GoldPH_History:Toggle()

    elseif cmd == "debug" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()
        if subCmd == "on" then
            GoldPH_DB_Account.debug.enabled = true
            print("[GoldPH] Debug mode enabled (invariants will auto-run)")
        elseif subCmd == "off" then
            GoldPH_DB_Account.debug.enabled = false
            print("[GoldPH] Debug mode disabled")
        elseif subCmd == "verbose" then
            local setting = (args[3] or ""):lower()
            if setting == "on" then
                GoldPH_DB_Account.debug.verbose = true
                print("[GoldPH] Verbose logging enabled")
            elseif setting == "off" then
                GoldPH_DB_Account.debug.verbose = false
                print("[GoldPH] Verbose logging disabled")
            else
                print("[GoldPH] Usage: /goldph debug verbose on|off")
            end
        elseif subCmd == "dump" then
            GoldPH_Debug:DumpSession()
        elseif subCmd == "ledger" then
            GoldPH_Debug:ShowLedger()
        elseif subCmd == "holdings" then
            GoldPH_Debug:ShowHoldings()
        elseif subCmd == "prices" then
            GoldPH_Debug:ShowPriceSources()
        elseif subCmd == "pickpocket" then
            GoldPH_Debug:ShowPickpocket()
        else
            print("[GoldPH] Debug commands: on, off, verbose, dump, ledger, holdings, prices, pickpocket")
        end

    elseif cmd == "test" then
        local subCmd = (args[2] or ""):lower()
        if subCmd == "run" then
            GoldPH_Debug:RunTests()
        elseif subCmd == "hud" then
            GoldPH_Debug:TestHUD()
        elseif subCmd == "reset" then
            GoldPH_Debug:ResetTestHUD()
        elseif subCmd == "loot" then
            local copper = tonumber(args[3])
            if not copper then
                print("[GoldPH] Usage: /goldph test loot <copper>")
            else
                local ok, message = GoldPH_Events:InjectLootedCoin(copper)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject loot"))
                end
            end
        elseif subCmd == "repair" then
            local copper = tonumber(args[3])
            if not copper then
                print("[GoldPH] Usage: /goldph test repair <copper>")
            else
                local ok, message = GoldPH_Events:InjectRepair(copper)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject repair"))
                end
            end
        elseif subCmd == "lootitem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[GoldPH] Usage: /goldph test lootitem <itemID> <count>")
            else
                local ok, message = GoldPH_Events:InjectLootItem(itemID, count)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject loot item"))
                end
            end
        elseif subCmd == "vendoritem" then
            local itemID = tonumber(args[3])
            local count = tonumber(args[4]) or 1
            if not itemID then
                print("[GoldPH] Usage: /goldph test vendoritem <itemID> <count>")
            else
                local ok, message = GoldPH_Events:InjectVendorSale(itemID, count)
                if not ok then
                    print("[GoldPH] " .. (message or "Failed to inject vendor sale"))
                end
            end
        else
            print("[GoldPH] Test commands: run, hud, reset, loot <copper>, repair <copper>, lootitem <itemID> <count>, vendoritem <itemID> <count>")
        end

    elseif cmd == "help" then
        ShowHelp()

    else
        print("[GoldPH] Unknown command. Type /goldph help for usage.")
    end
end

SLASH_GOLDPH1 = "/goldph"
SLASH_GOLDPH2 = "/gph"
SLASH_GOLDPH3 = "/ph"
SlashCmdList["GOLDPH"] = HandleCommand
