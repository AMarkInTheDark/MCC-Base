-- MCC items crafted at the JMod workbench. Each feature registers its recipes here; the costs live
-- in data/mcc/jmod_recipes.json ({"Recipe Name": {"<JMod resource>": amount, ...}}) so server owners
-- can change them, and mcc_reload_config applies the changes.
--
--   MCC.JModRecipes.Add("FOB Kit", {results = "FUNC MCCFobKit", cost = {steel = 100}, description = "..."})
--   MCC.JModRecipes.AddBuildFunc("MCCFobKit", function(ply, pos, ang) ... end)
--
-- results is what JMod builds: an entity class, or "FUNC <name>" for a build function.

MCC.JModRecipes = MCC.JModRecipes or {list = {}, funcs = {}}
local R = MCC.JModRecipes

function R.Add(name, def)
    R.list[name] = def
end

function R.AddBuildFunc(name, fn)
    R.funcs[name] = fn
end

local function Defaults()
    local out = {}
    for name, def in pairs(R.list) do out[name] = table.Copy(def.cost or {}) end
    return out
end

-- Costs from the file, with recipes added since it was written filled in (and the old
-- extraction_recipes.json folded in once).
function R.Costs()
    local defaults = Defaults()
    local costs = MCC.Data.ReadJSON("jmod_recipes.json")
    local changed = false
    if not istable(costs) then
        costs = MCC.Data.ReadJSON("extraction_recipes.json") or {}
        changed = true
    end
    for name, cost in pairs(defaults) do
        if not istable(costs[name]) then
            costs[name] = cost
            changed = true
        end
    end
    if changed then MCC.Data.WriteJSON("jmod_recipes.json", costs) end
    return costs
end

-- Puts every MCC recipe into JMod's workbench list. False if JMod isn't loaded.
function R.Apply()
    if not (istable(JMod) and istable(JMod.Config) and istable(JMod.Config.Craftables)) then return false end
    JMod.LuaConfig = JMod.LuaConfig or {}
    JMod.LuaConfig.BuildFuncs = JMod.LuaConfig.BuildFuncs or {}
    for name, fn in pairs(R.funcs) do JMod.LuaConfig.BuildFuncs[name] = fn end

    local costs = R.Costs()
    for name, def in pairs(R.list) do
        local reqs = {}
        for typ, n in pairs(istable(costs[name]) and costs[name] or def.cost or {}) do
            if tonumber(n) and tonumber(n) > 0 then reqs[typ] = math.floor(tonumber(n)) end
        end
        JMod.Config.Craftables[name] = {results = def.results, craftingReqs = reqs, sizeScale = def.sizeScale or 1,
            category = def.category or "MCC", craftingType = def.craftingType or "workbench", description = def.description}
    end
    return true
end

-- JMod (re)loads its config: add ours before it sends the recipe list to players.
hook.Add("JMod_PostLuaConfigLoad", "MCC_JModRecipes", function() R.Apply() end)

local function ApplyAndSync()
    if R.Apply() and JMod.CraftablesSync then JMod.CraftablesSync() end
end
hook.Add("MCC_Ready", "MCC_JModRecipes", ApplyAndSync)
hook.Add("MCC_ReloadConfig", "MCC_JModRecipes", ApplyAndSync)
