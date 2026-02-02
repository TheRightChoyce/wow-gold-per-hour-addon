-- Luacheck configuration for GoldPH WoW Addon
-- WoW Classic Anniversary uses Lua 5.1

-- Standard globals provided by WoW API
std = "min"

-- WoW API globals (common ones - not exhaustive)
read_globals = {
    -- WoW API
    "GetMoney",
    "GetTime",
    "time",
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
    
    -- WoW Classic Anniversary API
    "C_Container",
    "C_Timer",
    "C_TaxiMap",
    
    -- WoW Events
    "RegisterEvent",
    "SetScript",
    "OnEvent",
    "OnUpdate",
    
    -- WoW UI
    "GameFontNormal",
    "GameFontNormalSmall",
    "GameFontNormalLarge",
    "BackdropTemplate",
    
    -- Global module exports (our addon)
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
}

-- Ignore warnings for unused variables that are part of WoW API patterns
unused_args = false

-- Allow unused variables that start with underscore
ignore = {
    "212", -- unused argument
}

-- Files to check
files = {
    "GoldPH/*.lua",
}

-- Exclude patterns
exclude_files = {
    -- Exclude any test files or generated files if we add them later
}
