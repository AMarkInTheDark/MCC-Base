-- JMod resource boxes (wood, steel, fuel, ammo...) as inventory items.
--
-- E takes a box into your inventory; the item keeps the box's exact amount (never 0: JMod deletes
-- boxes that drop below 1). Dropping it puts a real JMod box back in the world with that amount, so
-- it still works with JMod machines, crates and the workbench. Hold JMod's alt key (Alt by default)
-- while pressing E to use JMod's own actions instead (load into a tool, Alt+Shift+E to split).
--
-- Sizes are per resource type in Inv.JModSizes below (ores 2x2, ingots 1x2, anything unlisted 1x1). Weight is for a full box and scales with the amount.
-- Change any of them per resource with items.json or mcc_item_set, e.g.
--   mcc_item_set jmod_steel w 2      mcc_item_set jmod_wood weight 6

local Inv = MCC.Inv

MCC.Config.Define("jmod_resources", true,
    "JMod resource boxes are picked up into the inventory with E (hold JMod's alt key for JMod's own use).")

-- {w, h}; ores ("iron ore", "gold ore"...) are 2x2, anything not listed is 1x1
Inv.JModSizes = {
    ["wood"] = {2, 2},
    ["water"] = {3, 3},
    ["sand"] = {3, 4},              -- sandbag
    ["propellant"] = {1, 3},        -- bottle
    ["rubber"] = {3, 3},
    ["advanced parts"] = {2, 2},
    ["advanced textiles"] = {2, 2}, -- roll
    ["ammo"] = {1, 2},
    ["antimatter"] = {1, 3},
    ["basic parts"] = {3, 3},
    ["power"] = {1, 2},             -- battery
    ["ceramic"] = {2, 2},
    ["chemicals"] = {3, 3},
    ["cloth"] = {1, 2},             -- roll
    ["coal"] = {2, 2},
    ["coolant"] = {1, 2},           -- bottle
    ["diamond"] = {1, 2},
    ["explosives"] = {3, 3},
    ["fissile material"] = {3, 4},
    ["fuel"] = {2, 2},              -- can
    ["gas"] = {1, 3},               -- tank
    ["glass"] = {2, 2},
    ["medical supplies"] = {2, 2},
    ["munitions"] = {3, 3},
    ["nutrients"] = {1, 2},
    ["oil"] = {2, 3},               -- drum
    ["organics"] = {2, 2},
    ["paper"] = {1, 1},
    ["plastic"] = {2, 2},
    ["precision parts"] = {2, 2},
    ["concrete"] = {2, 2},
}
-- ingots
for _, metal in ipairs({"steel", "lead", "aluminum", "copper", "tungsten", "titanium", "silver", "gold", "uranium", "platinum"}) do
    Inv.JModSizes[metal] = {1, 2}
end
local ORE_SIZE = {2, 2}
local FULL_WEIGHT = 5 -- kg for a full box of 100

-- Item id for a JMod resource type: "iron ore" -> "jmod_iron_ore".
function Inv.JModResourceID(typ)
    return "jmod_" .. string.gsub(string.lower(typ), "[^%w]+", "_")
end

-- What a full box holds (100, times JMod's MaxResourceMult setting).
function Inv.JModFull()
    local cfg = JMod and JMod.Config and JMod.Config.ResourceEconomy
    return math.floor(100 * (cfg and cfg.MaxResourceMult or 1))
end

-- How much a resource item holds. Items given without an amount (mcc_give) count as full boxes.
function Inv.ResourceAmount(it)
    local def = Inv.Def(it)
    if not def or not def.data.jmod then return nil end
    local n = tonumber(it.d and it.d.amount)
    return math.max(1, math.floor(n or Inv.JModFull()))
end

local function IsJModResource(ent)
    return IsValid(ent) and ent.IsJackyEZresource == true and isstring(ent.EZsupplies) and ent.GetResource ~= nil
end
Inv.IsJModResource = IsJModResource

hook.Add("MCC_RegisterItems", "MCC_JModResources", function(Items)
    if not (istable(JMod) and istable(JMod.EZ_RESOURCE_ENTITIES)) then return end
    for typ, class in pairs(JMod.EZ_RESOURCE_ENTITIES) do
        local ENT = scripted_ents.Get(class) or {}
        local size = Inv.JModSizes[typ] or (string.find(typ, " ore$") and ORE_SIZE) or {1, 1}
        local model = ENT.Model or (istable(ENT.Models) and ENT.Models[1]) or nil
        Items.Register(Inv.JModResourceID(typ), {
            name = (isstring(ENT.PrintName) and ENT.PrintName ~= "") and ENT.PrintName or ("EZ " .. typ),
            kind = "resource", class = class,
            w = size[1], h = size[2], maxStack = 1, weight = FULL_WEIGHT,
            model = model, category = "jmod", tags = {"jmod"},
            data = {jmod = typ, full = 100},
        })
    end
end)

local function Enabled()
    return Inv.Enabled() and MCC.Config.Get("jmod_resources")
end

local function AltUsing(ply)
    return JMod and JMod.IsAltUsing and JMod.IsAltUsing(ply) or false
end

-- E on a JMod box is an inventory pickup (JMod's alt-use stays JMod's).
hook.Add("MCC_IsPickup", "MCC_JModResources", function(ent)
    if not Enabled() or not IsJModResource(ent) then return end
    if not MCC.Items.FromClass(ent:GetClass()) then return end
    if CLIENT and IsValid(LocalPlayer()) and AltUsing(LocalPlayer()) then return end
    return "item"
end)

hook.Add("MCC_PickupPrompt", "MCC_JModResources", function(ent, kind)
    if kind ~= "item" or not IsJModResource(ent) then return end
    return "Pick up " .. MCC.Pickup.Name(ent), ent:GetResource() .. " " .. ent.EZsupplies
end)

if SERVER then
    -- Keep JMod's own E (pick the box up physically) from running when MCC takes it instead.
    hook.Add("PlayerUse", "MCC_JModResources", function(ply, ent)
        if not Enabled() or not MCC.Pickup.Active() or not IsJModResource(ent) then return end
        if AltUsing(ply) or not MCC.Items.FromClass(ent:GetClass()) then return end
        return false
    end)

    -- The box's amount goes onto the item.
    hook.Add("MCC_ItemFromEntity", "MCC_JModResources", function(ent, it, def)
        if not def.data.jmod or not IsJModResource(ent) then return end
        it.d = it.d or {}
        it.d.amount = math.max(1, math.floor(ent:GetResource() or Inv.JModFull()))
    end)

    -- Dropping puts a real JMod box back with the same amount.
    hook.Add("MCC_SpawnWorldItem", "MCC_JModResources", function(it, pos, dropper)
        local def = Inv.Def(it)
        if not def or not def.data.jmod or not def.class then return end
        local e = ents.Create(def.class)
        if not IsValid(e) then return end
        e:SetPos(pos)
        e:SetAngles(Angle(0, math.random(0, 359), 0))
        e:Spawn()
        e:Activate()
        -- after Spawn: JMod's Initialize fills every new box to 100
        e:SetEZsupplies(e.EZsupplies or def.data.jmod, Inv.ResourceAmount(it))
        if IsValid(dropper) then
            if JMod and JMod.SetEZowner then JMod.SetEZowner(e, dropper) end
            local phys = e:GetPhysicsObject()
            if IsValid(phys) then phys:SetVelocity(dropper:GetAimVector() * 120 + dropper:GetVelocity()) end
        end
        return e
    end)
end

-- Carried resources -------------------------------------------------------------------------------
-- Building costs come out of the JMod resources in your inventory (anywhere in it, bags included).

-- The inventory slots of a player: the server's copy, or on the client your own synced one.
function Inv.SlotsOf(ply)
    if SERVER then return Inv.Get(ply).slots end
    return ply == LocalPlayer() and Inv.State and Inv.State.slots or {}
end

-- {resource type = units} the player carries.
function Inv.CountResources(ply)
    local out = {}
    local function scan(it)
        local def = Inv.Def(it)
        if def and def.data.jmod then out[def.data.jmod] = (out[def.data.jmod] or 0) + Inv.ResourceAmount(it) end
        for _, list in ipairs(it.cont or {}) do
            for _, o in ipairs(list) do scan(o) end
        end
    end
    for _, it in pairs(Inv.SlotsOf(ply) or {}) do scan(it) end
    return out
end

-- Whether the player carries a cost ({resource = units}); false + "Needs 20 wood" when not.
function Inv.CanAfford(ply, cost)
    local have = Inv.CountResources(ply)
    local missing = {}
    for res, n in pairs(cost or {}) do
        if (have[res] or 0) < n then missing[#missing + 1] = n .. " " .. res end
    end
    if #missing > 0 then
        table.sort(missing)
        return false, "Needs " .. table.concat(missing, ", ")
    end
    return true
end

-- "20 wood, 10 steel"
function Inv.CostText(cost)
    local parts = {}
    for res, n in pairs(cost or {}) do parts[#parts + 1] = math.ceil(n) .. " " .. res end
    table.sort(parts)
    return #parts > 0 and table.concat(parts, ", ") or "free"
end

if SERVER then
    -- Takes a cost out of the player's carried resources (all or nothing).
    function Inv.TakeResources(ply, cost)
        local ok, err = Inv.CanAfford(ply, cost)
        if not ok then return false, err end
        for res, need in pairs(cost or {}) do
            local items = {}
            local function scan(it)
                local def = Inv.Def(it)
                if def and def.data.jmod == res then items[#items + 1] = it end
                for _, list in ipairs(it.cont or {}) do
                    for _, o in ipairs(list) do scan(o) end
                end
            end
            for _, it in pairs(Inv.Get(ply).slots) do scan(it) end
            -- smallest boxes first, so partly used ones get finished off
            table.sort(items, function(a, b) return Inv.ResourceAmount(a) < Inv.ResourceAmount(b) end)
            for _, it in ipairs(items) do
                if need <= 0 then break end
                local have = Inv.ResourceAmount(it)
                if have <= need then
                    need = need - have
                    local found, loc, list, idx = Inv.Find(ply, it.u)
                    if found then Inv.Detach(ply, found, loc, list, idx) end
                else
                    it.d = it.d or {}
                    it.d.amount = have - need
                    need = 0
                end
            end
        end
        Inv.Update(ply)
        return true
    end

    -- Gives resources as JMod resource items (full boxes of up to 100), dropped at the player's feet if
    -- they don't fit.
    function Inv.GiveResources(ply, amounts, pos)
        local full = Inv.JModFull()
        for res, n in pairs(amounts or {}) do
            n = math.floor(n)
            local id = Inv.JModResourceID(res)
            while n > 0 and MCC.Items.Get(id) do
                local take = math.min(n, full)
                n = n - take
                local it = Inv.NewItem(id, 1, {amount = take})
                if not (IsValid(ply) and Inv.GiveItem(ply, it)) then
                    Inv.SpawnWorldItem(it, pos or (IsValid(ply) and ply:GetPos() + Vector(0, 0, 24)) or vector_origin)
                end
            end
        end
        if IsValid(ply) then Inv.Update(ply) end
    end
end
