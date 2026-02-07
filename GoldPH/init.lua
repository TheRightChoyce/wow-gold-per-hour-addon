--[[
    init.lua - Entry point for GoldPH addon

    Handles initialization, slash commands, and event frame setup.
]]

-- Create main addon frame
local GoldPH_MainFrame = CreateFrame("Frame", "GoldPH_MainFrame")

-- Initialize saved variables on first load
local function InitializeSavedVariables()
    if not GoldPH_DB then
        GoldPH_DB = {
            meta = {
                version = 1,
                realm = GetRealmName() or "Unknown",
                faction = UnitFactionGroup("player") or "Unknown",
                character = UnitName("player") or "Unknown",
                lastSessionId = 0,
            },

            settings = {
                trackZone = true,
                hudVisible = true,   -- Track HUD visibility state
                hudMinimized = false, -- Track HUD minimize state
                historyVisible = false,
                historyMinimized = false,
                historyPosition = nil,
                historyActiveTab = "summary",
                historyFilters = {
                    sort = "totalPerHour",
                },
                microBars = {
                    enabled = true,
                    height = 6,
                    updateInterval = 0.25,
                    smoothingAlpha = 0.25,
                    normalization = {
                        mode = "sessionPeak",
                        peakDecay = { enabled = false, ratePerMin = 0.03 },
                    },
                    minRefFloors = {
                        gold = 50000,   -- 5g/h in copper
                        xp = 5000,
                        rep = 50,
                        honor = 100,
                    },
                    updateThresholds = {
                        gold = 1000,    -- 0.1g/h (to avoid string churn)
                        xp = 100,
                        rep = 5,
                        honor = 10,
                    },
                },
            },

            priceOverrides = {},

            activeSession = nil,

            sessions = {},

            debug = {
                enabled = false,
                verbose = false,
                lastTestResults = {},
            },
        }

        print("[GoldPH] Initialized for " .. GoldPH_DB.meta.character .. " on " .. GoldPH_DB.meta.realm)
    else
        -- TODO: Remove this migration once no longer needed (only for pre-microBars SavedVariables).
        -- Ensure microBars exists for existing SavedVariables (migration)
        if GoldPH_DB.settings and GoldPH_DB.settings.microBars == nil then
            GoldPH_DB.settings.microBars = {
                enabled = true,
                height = 6,
                updateInterval = 0.25,
                smoothingAlpha = 0.25,
                normalization = {
                    mode = "sessionPeak",
                    peakDecay = { enabled = false, ratePerMin = 0.03 },
                },
                minRefFloors = {
                    gold = 50000,
                    xp = 5000,
                    rep = 50,
                    honor = 100,
                },
                updateThresholds = {
                    gold = 1000,
                    xp = 100,
                    rep = 5,
                    honor = 10,
                },
            }
        end
    end
end

-- Addon loaded event handler
GoldPH_MainFrame:RegisterEvent("ADDON_LOADED")
GoldPH_MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GoldPH_MainFrame:RegisterEvent("PLAYER_LOGOUT")
GoldPH_MainFrame:SetScript("OnEvent", function(self, event, ...)
    local addonName = select(1, ...)  -- First vararg for ADDON_LOADED event
    
    if event == "ADDON_LOADED" and addonName == "GoldPH" then
        InitializeSavedVariables()

        -- Initialize UI
        GoldPH_HUD:Initialize()

        -- Initialize event system (registers additional events)
        GoldPH_Events:Initialize(GoldPH_MainFrame)

        print("[GoldPH] Version 0.7.0 (Phase 7: Gathering & Sessions UI) loaded. Type /goldph help for commands.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure settings exist (for existing SavedVariables)
        if GoldPH_DB.settings.hudVisible == nil then
            GoldPH_DB.settings.hudVisible = true
        end
        if GoldPH_DB.settings.hudMinimized == nil then
            GoldPH_DB.settings.hudMinimized = false
        end

        -- Ensure active session has duration tracking fields
        local session = GoldPH_DB.activeSession
        if session then
            local wasNewLogin = false
            if session.accumulatedDuration == nil then
                session.accumulatedDuration = 0
            end
            -- Only start/resume the clock if not paused (pause state persists across logout)
            if session.currentLoginAt == nil and not session.pausedAt then
                session.currentLoginAt = time()
                wasNewLogin = true
            end

            -- Verbose debug: log login segment initialization
            if GoldPH_DB.debug.verbose then
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
        if GoldPH_DB.activeSession then
            if GoldPH_DB.settings.hudVisible then
                GoldPH_HUD:Show()
                GoldPH_HUD:ApplyMinimizeState()
            else
                GoldPH_HUD:Update()
            end
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Fold the current login segment into the session accumulator on logout
        local session = GoldPH_DB.activeSession
        if session and session.currentLoginAt then
            local now = time()
            local segmentDuration = now - session.currentLoginAt
            local oldAccumulated = session.accumulatedDuration
            session.accumulatedDuration = session.accumulatedDuration + segmentDuration
            session.currentLoginAt = nil

            -- Verbose debug: log logout segment folding
            if GoldPH_DB.debug.verbose then
                print(string.format(
                    "[GoldPH Debug] PLAYER_LOGOUT | Session #%d | segmentDuration=%ds | oldAccumulated=%d | newAccumulated=%d",
                    session.id,
                    segmentDuration,
                    oldAccumulated,
                    session.accumulatedDuration
                ))
            end
        end

        -- Route logout to event system as well (in case it needs it)
        GoldPH_Events:OnEvent(event, ...)
    else
        -- Route other events to GoldPH_Events
        -- Pass all event arguments (not just addonName) for events like QUEST_TURNED_IN
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
    print("|cffffff00/goldph pause|r - Pause the session (clock and events)")
    print("|cffffff00/goldph resume|r - Resume a paused session")
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

    -- Allow short debug-style commands to fall through, e.g.:
    -- "/ph dump" -> "/goldph debug dump"
    -- This also works for other debug subcommands like ledger, holdings, prices, pickpocket, etc.
    local debugShortcuts = {
        dump = true,
        ledger = true,
        holdings = true,
        prices = true,
        pickpocket = true,
        on = true,
        off = true,
        verbose = true,
    }

    if debugShortcuts[cmd] then
        table.insert(args, 1, "debug")
        cmd = "debug"
    end

    -- Session commands
    if cmd == "start" then
        local ok, message = GoldPH_SessionManager:StartSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Show()  -- Explicitly show HUD when starting session
        end

    elseif cmd == "stop" then
        local ok, message = GoldPH_SessionManager:StopSession()
        print("[GoldPH] " .. message)
        GoldPH_HUD:Update()

    elseif cmd == "pause" then
        local ok, message = GoldPH_SessionManager:PauseSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Update()
        end

    elseif cmd == "resume" then
        local ok, message = GoldPH_SessionManager:ResumeSession()
        print("[GoldPH] " .. message)
        if ok then
            GoldPH_HUD:Update()
        end

    elseif cmd == "show" then
        GoldPH_HUD:Toggle()

    elseif cmd == "status" then
        local session = GoldPH_SessionManager:GetActiveSession()
        if session then
            local metrics = GoldPH_SessionManager:GetMetrics(session)
            local pausedStr = GoldPH_SessionManager:IsPaused(session) and " (paused)" or ""
            print(string.format("[GoldPH] Session #%d%s | Duration: %s | Cash: %s | Cash/hr: %s",
                                session.id,
                                pausedStr,
                                GoldPH_SessionManager:FormatDuration(metrics.durationSec),
                                GoldPH_Ledger:FormatMoney(metrics.cash),
                                GoldPH_Ledger:FormatMoneyShort(metrics.cashPerHour)))
        else
            print("[GoldPH] No active session")
        end

    elseif cmd == "history" then
        GoldPH_History:Toggle()

    -- Debug commands
    elseif cmd == "debug" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()

        if subCmd == "on" then
            GoldPH_DB.debug.enabled = true
            print("[GoldPH] Debug mode enabled (invariants will auto-run)")
        elseif subCmd == "off" then
            GoldPH_DB.debug.enabled = false
            print("[GoldPH] Debug mode disabled")
        elseif subCmd == "verbose" then
            local setting = args[3] or ""
            setting = setting:lower()
            if setting == "on" then
                GoldPH_DB.debug.verbose = true
                print("[GoldPH] Verbose logging enabled")
            elseif setting == "off" then
                GoldPH_DB.debug.verbose = false
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

    -- Test commands
    elseif cmd == "test" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()

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

    -- Help
    elseif cmd == "help" then
        ShowHelp()

    else
        print("[GoldPH] Unknown command. Type /goldph help for usage.")
    end
end

-- Register slash commands
SLASH_GOLDPH1 = "/goldph"
SLASH_GOLDPH2 = "/gph"
SLASH_GOLDPH3 = "/ph"
SlashCmdList["GOLDPH"] = HandleCommand
