-- Server settings as console variables.
-- Cvars hold single values (numbers, on/off switches, short strings). Lists such as
-- items, traders and factions live in JSON data files instead (see sv_data.lua).
--
-- Every module defines its own settings here so they all share one place and one naming scheme:
--   MCC.Config.Define("fob_safe_radius", 2000, "Units around a FOB where enemies can't spawn.", 500, 10000)
--   MCC.Config.Get("fob_safe_radius") --> 2000 (typed from the default)

MCC.Config = MCC.Config or {}
MCC.Config.Defs = MCC.Config.Defs or {}
MCC.Config.Order = MCC.Config.Order or {}

local FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

-- Must run in both realms (shared file) so clients see replicated values.
function MCC.Config.Define(name, default, help, min, max)
    local kind = type(default)
    assert(kind == "number" or kind == "boolean" or kind == "string",
        "MCC.Config.Define: default for '" .. name .. "' must be a number, boolean or string")

    local cvarName = "mcc_" .. name
    local stored = default
    if kind == "boolean" then
        stored = default and "1" or "0"
        min, max = 0, 1
    end

    local cv = GetConVar(cvarName) or CreateConVar(cvarName, tostring(stored), FLAGS, help or "", min, max)
    if not MCC.Config.Defs[name] then MCC.Config.Order[#MCC.Config.Order + 1] = name end
    MCC.Config.Defs[name] = {cvar = cv, kind = kind, default = default, help = help, min = min, max = max}
    return cv
end

function MCC.Config.Get(name)
    local def = MCC.Config.Defs[name]
    if not def then
        MCC.Error("Unknown setting '%s'", tostring(name))
        return nil
    end
    if def.kind == "boolean" then return def.cvar:GetBool() end
    if def.kind == "number" then return def.cvar:GetFloat() end
    return def.cvar:GetString()
end

-- Core settings. Feature modules add their own when they load.
MCC.Config.Define("debug", false, "Print MCC debug messages to the console.")
MCC.Config.Define("price_mult", 1, "Multiplier applied to every trader price.", 0, 100)
MCC.Config.Define("save_interval", 120, "Seconds between automatic saves of player and FOB data.", 15, 3600)
MCC.Config.Define("jmod_integration", true, "Use JMod for resources, refining and machines when JMod is installed.")
MCC.Config.Define("compat_notice", true, "Tell admins on join when a recommended addon such as JMod isn't installed.")
MCC.Config.Define("default_stack", 50, "Max stack per 1x1 cell for stackable items that don't set their own.", 1, 100000)
