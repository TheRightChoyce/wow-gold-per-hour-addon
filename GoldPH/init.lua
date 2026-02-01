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
                hudVisible = true,  -- Track HUD visibility state
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
    end
end

-- Addon loaded event handler
GoldPH_MainFrame:RegisterEvent("ADDON_LOADED")
GoldPH_MainFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
GoldPH_MainFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "GoldPH" then
        InitializeSavedVariables()

        -- Initialize UI
        GoldPH_HUD:Initialize()

        -- Initialize event system (registers additional events)
        GoldPH_Events:Initialize(GoldPH_MainFrame)

        print("[GoldPH] Version 0.4.2 (Fish classification fix) loaded. Type /goldph help for commands.")
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Ensure hudVisible setting exists (for existing SavedVariables)
        if GoldPH_DB.settings.hudVisible == nil then
            GoldPH_DB.settings.hudVisible = true
        end

        -- Auto-restore HUD visibility if session is active
        if GoldPH_DB.activeSession then
            if GoldPH_DB.settings.hudVisible then
                GoldPH_HUD:Show()
            else
                GoldPH_HUD:Update()
            end
        end
    else
        -- Route other events to GoldPH_Events
        GoldPH_Events:OnEvent(event, addonName)
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
    print("")
    print("|cff00ff00=== Debug Commands ===|r")
    print("|cffffff00/goldph debug on|off|r - Enable/disable debug mode (auto-run invariants)")
    print("|cffffff00/goldph debug verbose on|off|r - Enable/disable verbose logging")
    print("|cffffff00/goldph debug dump|r - Dump current session state")
    print("|cffffff00/goldph debug ledger|r - Show ledger balances")
    print("|cffffff00/goldph debug holdings|r - Show holdings (Phase 3+)")
    print("|cffffff00/goldph debug prices|r - Show available price sources (TSM, Custom AH)")
    print("")
    print("|cff00ff00=== Test Commands ===|r")
    print("|cffffff00/goldph test run|r - Run automated test suite")
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
                                GoldPH_Ledger:FormatMoney(metrics.cashPerHour)))
        else
            print("[GoldPH] No active session")
        end

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
        else
            print("[GoldPH] Debug commands: on, off, verbose, dump, ledger, holdings, prices")
        end

    -- Test commands
    elseif cmd == "test" then
        local subCmd = args[2] or ""
        subCmd = subCmd:lower()

        if subCmd == "run" then
            GoldPH_Debug:RunTests()
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
            print("[GoldPH] Test commands: run, loot <copper>, repair <copper>, lootitem <itemID> <count>, vendoritem <itemID> <count>")
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
SlashCmdList["GOLDPH"] = HandleCommand
