-- Luacheck configuration for GoldPH WoW Addon
-- WoW Classic Anniversary uses Lua 5.1
-- Based on Questie's configuration (https://github.com/Questie/Questie/blob/master/.luacheckrc)
-- with GoldPH-specific additions

std = "lua51"
max_line_length = 140

-- Files to check
files = {
    "GoldPH/*.lua",
}

-- Exclude patterns
exclude_files = {
    -- Exclude any test files or generated files if we add them later
}

-- Ignore patterns (from Questie)
ignore = {
    "211", -- Unused local variable
    "212", -- Unused argument (e.g. "self")
    "213", -- Unused loop variable
    "431", -- Shadowing an upvalue
    "432", -- Shadowing an upvalue argument (e.g. "self")
    "611", -- A line consists of nothing but whitespace
    "612", -- A line contains trailing whitespace
    "614", -- Trailing whitespace in a comment
    "631", -- Line is too long
}

-- WoW API globals (from Questie's extensive list + GoldPH-specific additions)
globals = {
    -- GoldPH-specific globals (must be included)
    "_G",
    "GoldPH_DB",
    "GoldPH_Ledger",
    "GoldPH_SessionManager",
    "GoldPH_Events",
    "GoldPH_HUD",
    "GoldPH_Debug",
    "GoldPH_Valuation",
    "GoldPH_Holdings",
    "GoldPH_PriceSources",
    
    -- GoldPH-specific WoW API usage
    "TSM_API",  -- Optional addon, checked at runtime
    "TakeTaxiNode",  -- Taxi API (may not exist in all versions)
    "TaxiNodeCost",  -- Taxi API (may not exist in all versions)
    "SLASH_GOLDPH1",  -- Slash command registration
    "SLASH_GOLDPH2",  -- Slash command registration
    "SlashCmdList",  -- Slash command system
    
    -- WoW Events (used as strings, but luacheck may check them)
    "PLAYER_MONEY",
    "TAXIMAP_OPENED",
    "TAXIMAP_CLOSED",
    "QUEST_TURNED_IN",
    "UNIT_SPELLCAST_SUCCEEDED",
    
    -- Core WoW API (from Questie - most commonly used)
    "GetSpellInfo",
    "GetMoney",
    "GetTime",
    "time",
    "date",  -- WoW date formatting function
    "GetZoneText",
    "GetRealmName",
    "UnitName",
    "UnitFactionGroup",
    "GetItemInfo",
    "GetContainerNumSlots",
    "GetContainerItemInfo",
    "GetRepairAllCost",
    "RepairAllItems",
    "UseContainerItem",
    "CreateFrame",
    "UIParent",
    "hooksecurefunc",
    "print",
    "error",
    "tostring",
    "tonumber",
    "string",
    "math",
    "table",
    "pairs",
    "ipairs",
    "select",
    "type",
    "next",
    "unpack",
    "RegisterEvent",
    "SetScript",
    "OnEvent",
    "OnUpdate",
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontNormalLarge",
    "BackdropTemplate",
    "C_Container",
    "C_Timer",
    "C_TaxiMap",
    "C_Container.GetContainerNumSlots",
    "C_Container.GetContainerItemInfo",
    "C_Timer.After",
}
