-- MCC inventory: shared rules used by both the server (authority) and the UI (drag previews).
--
-- An inventory is {slots = {<slot key> = item}}. Gear items (rig, backpack, pouch) own their
-- contents: item.cont[i] is the list of items in compartment i (shapes in the item's data.cells).
-- Item instance: {u = unique id, id = registry id, n = count, x, y, r = rotated, cont, d = instance data}.
-- Everything else (size, stack, weight, model, name) comes from the item registry.
--
-- Location strings:
--   "s:<slot>"        a player slot             "g:<slot>:<i>"   compartment i of the gear in that slot
--   "bs:<slot>"       a slot on the open body   "bg:<slot>:<i>"  compartment i of the body's gear
--   "c:<i>"           compartment i of the open container ("c" alone means compartment 1)

MCC.Inv = MCC.Inv or {}
local Inv = MCC.Inv

MCC.Config.Define("inv_enabled", true, "Use the MCC inventory: grids, equipment slots, lootable bodies.")
MCC.Config.Define("inv_starter", "pouch_secure", "Items a player starts with when their inventory is empty (comma-separated ids).")
MCC.Config.Define("inv_always_weapons", "weapon_physgun,weapon_physcannon,gmod_tool,gmod_camera",
    "Weapons everyone always has, outside the inventory (comma-separated classes).")
MCC.Config.Define("inv_body_cleanup", true, "Bodies despawn once they've been looted (something taken out or put in), mcc_inv_body_looted_time later. Unlooted bodies stay.")
MCC.Config.Define("inv_body_looted_time", 360, "Seconds a body lasts after it's first looted (with mcc_inv_body_cleanup).", 0, 7200)
MCC.Config.Define("inv_body_lifetime", 0, "Seconds any body lasts at most, looted or not (0 = no limit).", 0, 7200)
MCC.Config.Define("inv_body_freeze", 10, "Seconds after death a body's ragdoll is frozen in place once it has settled (saves physics; 0 = never).", 0, 600)
MCC.Config.Define("inv_body_max", 30, "Most bodies on the map; past it the oldest go, unlooted ones only when there's no looted one left (0 = no limit).", 0, 1000)
MCC.Config.Define("inv_item_lifetime", 900, "Seconds a dropped item stays on the ground (0 = forever).", 0, 7200)
MCC.Config.Define("inv_use_distance", 120, "How close you must be to loot a body or container.", 50, 300)
MCC.Config.Define("mags_required", true, "Magazine-fed guns (pistol, SMG, AR2) reload only from loaded magazines in your rig or pockets.")
MCC.Config.Define("inv_leave_wipe", true, "Leaving the server (or a new session: map change, restart) loses everything but the pouch (Alpha Container).")
MCC.Config.Define("inv_leave_body", true, "What a leaving player loses stays where they stood as a lootable body.")
MCC.Config.Define("inv_npc_bodies", true, "NPCs leave lootable bodies carrying their weapon (turns on server-side ragdolls).")
MCC.Config.Define("weapon_state", true, "Remember a weapon's state (attachments, fire mode, rounds) when it's holstered, dropped or saved.")
MCC.Config.Define("weapon_state_skip", "reload,next,time,sprint,holster,deploy,inspect,lastfire,burst,draw",
    "Weapon variables NOT restored, matched as parts of their names (timers and animation states).")
MCC.Config.Define("search_enabled", true, "Bodies and containers must be searched: their items show up one at a time.")
MCC.Config.Define("search_time", 0.6, "Seconds to search one 1x1 item (bigger items take longer).", 0, 10)
MCC.Config.Define("inv_vicinity_range", 180, "How far the IN THE VICINITY list looks for items, bodies and containers.", 60, 600)

Inv.POCKETS = 4
Inv.SPECIALS = 3

-- Slot rules. Order matters only for display and auto-placement.
Inv.Slots = {
    earpiece  = {label = "EARPIECE",     armor = "earpiece"},
    headwear  = {label = "HEADWEAR",     armor = "headwear"},
    facecover = {label = "FACE COVER",   armor = "facecover"},
    armband   = {label = "ARMBAND",      armor = "armband"},
    armor     = {label = "BODY ARMOR",   armor = "body"},
    eyewear   = {label = "EYEWEAR",      armor = "eyewear"},
    dogtag    = {label = "DOGTAG",       dataSlot = "dogtag"},
    sling     = {label = "ON SLING",     weapon = "primary"},
    back      = {label = "ON BACK",      weapon = "primary"},
    holster   = {label = "HOLSTER",      weapon = "holster"},
    sheath    = {label = "SHEATH",       weapon = "melee"},
    rig       = {label = "TACTICAL RIG", gear = "rig"},
    backpack  = {label = "BACKPACK",     gear = "backpack"},
    pouch     = {label = "POUCH",        gear = "pouch"},
}
for i = 1, Inv.POCKETS do Inv.Slots["pocket" .. i] = {label = "", pocket = true} end
for i = 1, Inv.SPECIALS do Inv.Slots["special" .. i] = {label = "SPEC", special = true} end

Inv.WeaponSlots = {"sling", "back", "holster", "sheath"}
Inv.GearSlots = {"rig", "backpack", "pouch"}

local function HasTag(def, tag)
    for _, t in ipairs(def.tags or {}) do
        if t == tag then return true end
    end
    return false
end
Inv.HasTag = HasTag

function Inv.Def(it)
    return it and MCC.Items.Get(it.id)
end

function Inv.SlotAccepts(key, def)
    local s = Inv.Slots[key]
    if not s or not def then return false end
    local d = def.data or {}
    if s.weapon then return def.kind == "weapon" and d.slot == s.weapon end
    if s.gear then return def.kind == "gear" and d.slot == s.gear end
    if s.armor then return def.kind == "armor" and d.slot == s.armor end
    if s.dataSlot then return d.slot == s.dataSlot end
    if s.pocket then return def.w == 1 and def.h == 1 end
    if s.special then return def.w == 1 and def.h == 1 and HasTag(def, "special") end
    return false
end

-- Size on the grid, swapped when rotated.
function Inv.Size(it)
    local w, h
    if it.hidden then
        w, h = it.w or 1, it.h or 1 -- not searched yet: the client only knows its size
    else
        local def = Inv.Def(it)
        w, h = def and def.w or 1, def and def.h or 1
    end
    if it.r then return h, w end
    return w, h
end

function Inv.MaxStack(it)
    local def = Inv.Def(it)
    return def and def.maxStack or 1
end

function Inv.Count(it)
    return it.n or 1
end

-- Items in list that overlap it placed at (x, y), ignoring the item with u == ignore.
function Inv.Overlaps(list, it, x, y, ignore)
    local w, h = Inv.Size(it)
    local out = {}
    for _, o in ipairs(list or {}) do
        if o.u ~= ignore then
            local ow, oh = Inv.Size(o)
            if x < o.x + ow and x + w > o.x and y < o.y + oh and y + h > o.y then
                out[#out + 1] = o
            end
        end
    end
    return out
end

function Inv.CanFit(list, gw, gh, it, x, y, ignore)
    local w, h = Inv.Size(it)
    if x < 0 or y < 0 or x + w > gw or y + h > gh then return false end
    return #Inv.Overlaps(list, it, x, y, ignore) == 0
end

-- First free position scanning rows top to bottom; tries unrotated first. Returns x, y, r.
function Inv.FindSpot(list, gw, gh, it)
    local oldR = it.r
    local w, h = Inv.Size({id = it.id})
    local tries = (w == h) and {false} or {false, true}
    for _, r in ipairs(tries) do
        it.r = r
        for y = 0, gh - 1 do
            for x = 0, gw - 1 do
                if Inv.CanFit(list, gw, gh, it, x, y, it.u) then
                    it.r = oldR
                    return x, y, r
                end
            end
        end
    end
    it.r = oldR
end

-- Compartment layout of a gear item, or nil if it has no storage.
function Inv.Cells(it)
    local def = Inv.Def(it)
    return def and def.kind == "gear" and def.data and def.data.cells or nil
end

-- Bounding box of a gear item's compartments, in cells.
function Inv.CellBounds(it)
    local cells = Inv.Cells(it)
    if not cells then return nil end
    local w, h = 0, 0
    for _, c in ipairs(cells) do
        w = math.max(w, c.x + c.w)
        h = math.max(h, c.y + c.h)
    end
    return w, h
end

-- Total weight including contents (kg).
function Inv.Weight(it)
    local def = Inv.Def(it)
    local w = (def and def.weight or 0) * Inv.Count(it)
    -- items holding an amount (JMod boxes): weight is for a full one
    if def and def.data.full and it.d and it.d.amount then w = def.weight * it.d.amount / def.data.full end
    for _, list in ipairs(it.cont or {}) do
        for _, o in ipairs(list) do w = w + Inv.Weight(o) end
    end
    return w
end

function Inv.TotalWeight(inv)
    local w = 0
    for _, it in pairs(inv and inv.slots or {}) do w = w + Inv.Weight(it) end
    return w
end

function Inv.ParseLoc(loc)
    if type(loc) ~= "string" then return nil end
    local key = string.match(loc, "^s:(%w+)$")
    if key then return "p", "slot", key end
    local g, i = string.match(loc, "^g:(%w+):(%d+)$")
    if g then return "p", "grid", g, tonumber(i) end
    key = string.match(loc, "^bs:(%w+)$")
    if key then return "b", "slot", key end
    g, i = string.match(loc, "^bg:(%w+):(%d+)$")
    if g then return "b", "grid", g, tonumber(i) end
    if loc == "c" then return "c", "grid", nil, 1 end
    i = string.match(loc, "^c:(%d+)$")
    if i then return "c", "grid", nil, tonumber(i) end
    return nil
end

-- Items whose ammo and grenades you can actually use: rig compartments, pockets and special slots.
function Inv.IsUsableLoc(loc)
    local owner, kind, key = Inv.ParseLoc(loc)
    if owner ~= "p" then return false end
    if kind == "grid" then return key == "rig" end
    local s = Inv.Slots[key]
    return s and (s.pocket or s.special) and true or false
end

function Inv.Enabled()
    return MCC.Config.Get("inv_enabled") and not MCC.Compat.Has("tarkov_inventory")
end

-- Gear with nothing inside it can be packed into other gear (Tarkov-style nesting).
function Inv.IsEmptyGear(it)
    for _, list in ipairs(it.cont or {}) do
        if #list > 0 then return false end
    end
    return true
end

-- Magazines ------------------------------------------------------------------------------
-- A magazine item keeps its rounds in it.d.rounds; its registry entry says the ammo type and capacity.

function Inv.MagRounds(it)
    return it and it.d and it.d.rounds or 0
end

function Inv.MagCap(it)
    local def = Inv.Def(it)
    return def and def.data.cap or 0
end

-- True when the item is a magazine that ammo item `ammoDef` can be loaded into.
function Inv.MagTakes(mag, ammoDef)
    local def = Inv.Def(mag)
    return def ~= nil and def.kind == "mag" and ammoDef ~= nil and ammoDef.kind == "ammo"
        and def.data.ammo == ammoDef.data.ammo and Inv.MagRounds(mag) < (def.data.cap or 0)
end

-- World ammo boxes -------------------------------------------------------------------------
-- HL2 ammo box entity -> ammo type and rounds (HL2's own box sizes).
Inv.WorldAmmo = {
    item_ammo_pistol = {"Pistol", 20},        item_ammo_pistol_large = {"Pistol", 100},
    item_ammo_smg1 = {"SMG1", 45},            item_ammo_smg1_large = {"SMG1", 225},
    item_ammo_ar2 = {"AR2", 20},              item_ammo_ar2_large = {"AR2", 60},
    item_ammo_357 = {"357", 6},               item_ammo_357_large = {"357", 20},
    item_ammo_crossbow = {"XBowBolt", 6},     item_box_buckshot = {"Buckshot", 20},
    item_rpg_round = {"RPG_Round", 1},        item_ammo_smg1_grenade = {"SMG1_Grenade", 1},
    item_ammo_ar2_altfire = {"AR2AltFire", 1},
}

-- Ammo type -> ammo item id, rebuilt whenever the registry changes.
Inv.AmmoItem = Inv.AmmoItem or {}
local function RebuildAmmoIndex()
    Inv.AmmoItem = {}
    for id, def in pairs(MCC.Items.All()) do
        if def.kind == "ammo" and def.data.ammo then Inv.AmmoItem[def.data.ammo] = Inv.AmmoItem[def.data.ammo] or id end
    end
end
hook.Add("MCC_ItemsChanged", "MCC_InvAmmoIndex", RebuildAmmoIndex)
hook.Add("MCC_Ready", "MCC_InvAmmoIndex", RebuildAmmoIndex)

-- The registry item and count an entity in the world stands for, for the vicinity list and pickups.
function Inv.WorldItemInfo(ent)
    if ent:GetClass() == "mcc_item" then return ent:GetItemID(), ent:GetCount() end
    local box = Inv.WorldAmmo[ent:GetClass()]
    if box then return Inv.AmmoItem[box[1]], box[2] end
    return MCC.Items.FromClass(ent:GetClass()), 1
end

-- Containers --------------------------------------------------------------------------------
-- Props whose model is listed in data/mcc/containers.json can be searched; the model sets the grid.
Inv.ContainerModels = Inv.ContainerModels or {}

function Inv.ContainerDef(ent)
    local mdl = ent:GetModel()
    return mdl and Inv.ContainerModels[string.lower(mdl)] or nil
end

-- A container's compartments as {{w, h}, ...}: "count" identical w x h grids (lockers: 4 of 2x8),
-- or an explicit "cells" list for compartments of different sizes.
function Inv.ContainerCells(def)
    if not def then return {} end
    if istable(def.cells) and #def.cells > 0 then return def.cells end
    local out = {}
    for i = 1, math.max(1, def.count or 1) do out[i] = {w = def.w or 4, h = def.h or 4} end
    return out
end

local PROP_CLASSES = {prop_physics = true, prop_physics_multiplayer = true, prop_dynamic = true, prop_dynamic_override = true}

-- World items, bodies and containers are picked up / searched with E through the pickup system.
hook.Add("MCC_IsPickup", "MCC_Inventory", function(ent)
    if not Inv.Enabled() then return end
    if ent:GetClass() == "mcc_item" then return "mcc_item" end
    if ent:GetNWBool("MCCBody") then return "body" end
    if PROP_CLASSES[ent:GetClass()] and Inv.ContainerDef(ent) then return "container" end
end)

hook.Add("MCC_PickupPrompt", "MCC_Inventory", function(ent, kind)
    if kind == "container" then
        local def = Inv.ContainerDef(ent)
        return "Search", def and def.name or ent:GetNWString("MCCName", "Container")
    end
end)
