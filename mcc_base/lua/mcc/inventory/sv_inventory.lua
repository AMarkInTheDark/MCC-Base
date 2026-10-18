-- MCC inventory, server side: the authority on every item. Clients only ask for actions.
-- Mechanics adapted from the Tarkov Inventory addon (gear owns its contents, rig/pocket ammo
-- is the usable ammo, lootable bodies), rebuilt on the MCC item registry.

local Inv = MCC.Inv

-- Item instances ------------------------------------------------------------------------

local nextUID = 0
function Inv.NewUID()
    nextUID = nextUID + 1
    return nextUID
end

-- A new item of registry id, n units (clamped to its stack size). nil if the id is unknown.
-- Magazines start empty unless d.rounds says otherwise.
function Inv.NewItem(id, n, d)
    local def = MCC.Items.Get(id)
    if not def then return nil end
    local it = {u = Inv.NewUID(), id = id, d = d}
    if def.maxStack > 1 then it.n = math.Clamp(math.floor(n or 1), 1, def.maxStack) end
    if def.kind == "mag" then
        it.d = it.d or {}
        it.d.rounds = math.Clamp(math.floor(it.d.rounds or 0), 0, def.data.cap or 0)
    end
    local cells = def.kind == "gear" and def.data.cells
    if cells then
        it.cont = {}
        for i = 1, #cells do it.cont[i] = {} end
    end
    return it
end

function Inv.Get(ply)
    if not ply.MCCInv then ply.MCCInv = {slots = {}} end
    return ply.MCCInv
end

-- Gear compartment i -> width, height, item list.
local function GearGrid(gear, i)
    local cells = Inv.Cells(gear)
    local cell = cells and cells[i]
    if not cell then return nil end
    gear.cont = gear.cont or {}
    gear.cont[i] = gear.cont[i] or {}
    return cell.w, cell.h, gear.cont[i]
end
Inv.GearGrid = GearGrid

local function InReach(ply, ent)
    if not IsValid(ent) then return false end
    local sp = ply:GetShootPos()
    return sp:Distance(ent:NearestPoint(sp)) <= MCC.Config.Get("inv_use_distance") + 60
end
Inv.InReach = InReach

-- The body or container a player has open, if it still exists and is in reach.
function Inv.OpenTarget(ply)
    local e = ply.MCCInvOpen
    if not IsValid(e) or not e.MCCCont or not InReach(ply, e) then return nil end
    return e
end

local function OwnerInv(ply, owner)
    if owner == "p" then return Inv.Get(ply) end
    if owner == "b" then
        local e = Inv.OpenTarget(ply)
        return e and e.MCCCont.inv or nil
    end
end

-- Grid at a location -> width, height, list, the gear item that owns it (nil for a container).
function Inv.GetGrid(ply, loc)
    local owner, kind, key, i = Inv.ParseLoc(loc)
    if kind ~= "grid" then return nil end
    if owner == "c" then
        local e = Inv.OpenTarget(ply)
        local g = e and e.MCCCont.grids and e.MCCCont.grids[i]
        if g and Inv.SectionDone(ply, e, "c:" .. i) then return g.w, g.h, g.items, nil end
        return nil
    end
    local inv = OwnerInv(ply, owner)
    local gear = inv and inv.slots[key]
    if not gear then return nil end
    if owner == "b" and not Inv.SectionDone(ply, ply.MCCInvOpen, key) then return nil end -- not searched yet
    local w, h, list = GearGrid(gear, i)
    return w, h, list, gear
end

local function SearchInv(inv, u, sPrefix, gPrefix)
    for key, it in pairs(inv.slots) do
        if it.u == u then return it, sPrefix .. key end
        for i, list in ipairs(it.cont or {}) do
            for j, o in ipairs(list) do
                if o.u == u then return o, gPrefix .. key .. ":" .. i, list, j end
            end
        end
    end
end

-- Finds item u in the player's inventory or what they have open. Returns item, loc, list, index.
-- Items the player hasn't searched yet aren't found (see sv_inventory_search.lua).
function Inv.Find(ply, u)
    local it, loc, list, idx = SearchInv(Inv.Get(ply), u, "s:", "g:")
    if it then return it, loc, list, idx end
    local e = Inv.OpenTarget(ply)
    if not e then return nil end
    local C = e.MCCCont
    if C.inv then
        it, loc, list, idx = SearchInv(C.inv, u, "bs:", "bg:")
    else
        for i, g in ipairs(C.grids or {}) do
            for j, o in ipairs(g.items) do
                if o.u == u then it, loc, list, idx = o, "c:" .. i, g.items, j break end
            end
            if it then break end
        end
    end
    if not it or not Inv.Visible(ply, e, it, loc) then return nil end
    return it, loc, list, idx
end

-- Weapons ---------------------------------------------------------------------------------

local function WeaponClass(it)
    local def = Inv.Def(it)
    return def and def.kind == "weapon" and def.class or nil
end

-- Weapon state -----------------------------------------------------------------------------
-- Works with any weapon base without patches: rounds (clip 1 and 2) plus every network variable the
-- weapon declares (where most bases keep attachments, fire mode, magazine data...), minus timers and
-- animation states (mcc_weapon_state_skip). Bases that keep state elsewhere add an adapter:
--   hook.Add("MCC_SaveWeaponState", id, function(wep, d) d.mybase = ... end)
--   hook.Add("MCC_RestoreWeaponState", id, function(wep, d) ... end)

local skipStr, skipList = nil, {}
local function Skipped(name)
    local str = MCC.Config.Get("weapon_state_skip")
    if str ~= skipStr then
        skipStr, skipList = str, {}
        for part in string.gmatch(string.lower(str), "[^,%s]+") do skipList[#skipList + 1] = part end
    end
    local lname = string.lower(name)
    for _, part in ipairs(skipList) do
        if string.find(lname, part, 1, true) then return true end
    end
    return false
end

-- Reads a weapon entity's state into d (an item's instance data).
function Inv.CaptureWeaponState(w, d)
    if w:GetMaxClip1() > 0 then d.clip = math.Clamp(w:Clip1(), 0, w:GetMaxClip1()) end
    if w.GetMaxClip2 and w:GetMaxClip2() > 0 then d.clip2 = math.Clamp(w:Clip2(), 0, w:GetMaxClip2()) end
    if MCC.Config.Get("weapon_state") and w.GetNetworkVars then
        local ok, vars = pcall(w.GetNetworkVars, w)
        if ok and istable(vars) then
            local keep = {}
            for name, value in pairs(vars) do
                local t = type(value)
                if (t == "string" or t == "number" or t == "boolean") and not Skipped(name) then keep[name] = value end
            end
            d.nv = next(keep) and keep or nil
        end
    end
    hook.Run("MCC_SaveWeaponState", w, d)
end

local function ApplyWeaponState(w, d)
    if not IsValid(w) or not d then return end
    if d.nv and MCC.Config.Get("weapon_state") and w.RestoreNetworkVars then
        pcall(w.RestoreNetworkVars, w, d.nv)
    end
    if w:GetMaxClip1() > 0 then w:SetClip1(math.Clamp(d.clip or 0, 0, w:GetMaxClip1())) end
    if d.clip2 and w.GetMaxClip2 and w:GetMaxClip2() > 0 then w:SetClip2(math.Clamp(d.clip2, 0, w:GetMaxClip2())) end
    hook.Run("MCC_RestoreWeaponState", w, d)
end

function Inv.GiveWeapon(ply, it)
    local class = WeaponClass(it)
    if not class or not ply:Alive() then return end
    ply.MCCInvGiving = true
    local w = ply:Give(class, true)
    ply.MCCInvGiving = nil
    if not IsValid(w) then return end
    local d = it.d or {}
    ApplyWeaponState(w, d)
    -- some bases reset their variables while equipping; apply once more on the next tick
    timer.Simple(0, function()
        if IsValid(w) and IsValid(ply) and w:GetOwner() == ply then ApplyWeaponState(w, d) end
    end)
end

-- Saves the live weapon's state into the item.
local function StampWeapon(ply, it)
    local class = WeaponClass(it)
    local w = class and ply:GetWeapon(class)
    if IsValid(w) then
        it.d = it.d or {}
        Inv.CaptureWeaponState(w, it.d)
    end
end

function Inv.StampWeapons(ply)
    local inv = Inv.Get(ply)
    for _, key in ipairs(Inv.WeaponSlots) do
        if inv.slots[key] then StampWeapon(ply, inv.slots[key]) end
    end
end

local function TakeWeaponAway(ply, it)
    StampWeapon(ply, it)
    local class = WeaponClass(it)
    if class and ply:HasWeapon(class) then ply:StripWeapon(class) end
end

local function IsWeaponSlot(key)
    return Inv.Slots[key] and Inv.Slots[key].weapon ~= nil
end

local function CarriesClass(inv, class, exceptKey)
    for _, key in ipairs(Inv.WeaponSlots) do
        local it = inv.slots[key]
        if key ~= exceptKey and it and WeaponClass(it) == class then return true end
    end
    return false
end

-- Removing and merging ----------------------------------------------------------------------

-- Removes an item from wherever it is.
local function Detach(ply, it, loc, list, idx)
    local owner, kind, key = Inv.ParseLoc(loc)
    if kind == "slot" then
        local inv = OwnerInv(ply, owner)
        if owner == "p" and IsWeaponSlot(key) then TakeWeaponAway(ply, it) end
        if inv and inv.slots[key] == it then inv.slots[key] = nil end
    elseif list then
        if list[idx] ~= it then
            idx = nil
            for j, o in ipairs(list) do
                if o == it then idx = j break end
            end
        end
        if idx then table.remove(list, idx) end
    end
end
Inv.Detach = Detach

-- Pours src into dst (same item id). Returns how many moved and whether src is now empty.
local function Merge(dst, src)
    local moved = math.min(Inv.MaxStack(dst) - Inv.Count(dst), Inv.Count(src))
    if moved <= 0 then return 0, false end
    dst.n = Inv.Count(dst) + moved
    src.n = Inv.Count(src) - moved
    return moved, src.n <= 0
end

-- Loads loose rounds (ammo item) into a magazine. Returns rounds moved and whether the stack is empty.
local function LoadInto(mag, ammo)
    local moved = math.min(Inv.MagCap(mag) - Inv.MagRounds(mag), Inv.Count(ammo))
    if moved <= 0 then return 0, false end
    mag.d = mag.d or {}
    mag.d.rounds = Inv.MagRounds(mag) + moved
    ammo.n = Inv.Count(ammo) - moved
    return moved, ammo.n <= 0
end

-- Placing -----------------------------------------------------------------------------------
-- One path for every way an item lands somewhere: moved inside the inventory (from ~= nil) or
-- new from the world (from == nil). Returns ok, err. A stack that was only partly merged returns
-- ok with the remainder still in it.n.

local function Insert(ply, it, to, x, y, rot, from)
    local def = Inv.Def(it)
    if not def then return false end
    local owner, kind, key = Inv.ParseLoc(to)
    if not owner then return false end
    local function detach()
        if from then Detach(ply, it, from.loc, from.list, from.idx) end
    end

    -- dropped onto something that can absorb it: a matching stack or a magazine for loose rounds
    local function absorb(target)
        if owner ~= "p" and not Inv.IsSeen(ply, ply.MCCInvOpen, target) and not Inv.SectionDone(ply, ply.MCCInvOpen, Inv.SectionOf(to)) then
            return false
        end
        local moved, emptied
        if def.kind == "ammo" and Inv.MagTakes(target, def) then
            moved, emptied = LoadInto(target, it)
        elseif target.id == it.id and def.maxStack > 1 then
            moved, emptied = Merge(target, it)
        else
            return false
        end
        if moved <= 0 then return false end
        if emptied then detach() end
        return true
    end

    if kind == "slot" then
        local inv = OwnerInv(ply, owner)
        if not inv then return false end
        if owner == "b" and Inv.SectionOf(to) and not Inv.SectionDone(ply, ply.MCCInvOpen, Inv.SectionOf(to)) then
            return false, "Search it first"
        end
        local occ = inv.slots[key]
        if occ == it then return true end
        if occ then
            if absorb(occ) then return true end
            return false, "That slot is taken"
        end
        if not Inv.SlotAccepts(key, def) then return false, "That doesn't go there" end
        if owner == "p" and IsWeaponSlot(key) then
            local fromKey = from and select(3, Inv.ParseLoc(from.loc))
            if CarriesClass(inv, def.class, (from and Inv.ParseLoc(from.loc) == "p") and fromKey or nil) then
                return false, "You already carry one of those"
            end
        end
        detach()
        it.x, it.y, it.r = nil, nil, nil
        inv.slots[key] = it
        if owner == "p" and IsWeaponSlot(key) then Inv.GiveWeapon(ply, it) end
        if owner ~= "p" then Inv.MarkSeen(ply, ply.MCCInvOpen, it) end
        return true
    end

    local gw, gh, list, ownerGear = Inv.GetGrid(ply, to)
    if not list then return false end
    -- containers can refuse items (extraction crate limits); moving inside one isn't re-checked
    if owner == "c" and not (from and Inv.ParseLoc(from.loc) == "c") then
        local ok, err = hook.Run("MCC_CanStore", ply, it, ply.MCCInvOpen)
        if ok == false then return false, err end
    end
    if it.cont then
        if ownerGear == it then return false, "It can't go inside itself" end
        if owner ~= "c" and not Inv.IsEmptyGear(it) then return false, "Empty it first to pack it inside other gear" end
    end
    x, y = math.floor(tonumber(x) or 0), math.floor(tonumber(y) or 0)
    local probe = {id = it.id, u = it.u, r = rot and true or false}

    local ov = Inv.Overlaps(list, probe, x, y, it.u)
    if #ov == 1 and absorb(ov[1]) then return true end
    if not Inv.CanFit(list, gw, gh, probe, x, y, it.u) then return false, "No room there" end

    detach()
    it.x, it.y, it.r = x, y, probe.r
    list[#list + 1] = it
    if owner ~= "p" then Inv.MarkSeen(ply, ply.MCCInvOpen, it) end
    return true
end

function Inv.Move(ply, u, to, x, y, rot)
    local it, loc, list, idx = Inv.Find(ply, u)
    if not it then return false end
    return Insert(ply, it, to, x, y, rot, {loc = loc, list = list, idx = idx})
end

-- Puts an item that isn't in any inventory yet at a chosen location.
function Inv.PlaceAt(ply, it, to, x, y, rot)
    return Insert(ply, it, to, x, y, rot, nil)
end

-- Puts an item into a container in the world (dragged onto it in the vicinity list), in the first free
-- spot of any of its compartments. from = where it was in the player's inventory (nil: off the ground).
function Inv.StoreIn(ply, ent, it, from)
    local C = Inv.EnsureContainer(ent)
    if not C or not C.grids then return false, "That can't hold items" end
    local ok, err = hook.Run("MCC_CanStore", ply, it, ent)
    if ok == false then return false, err end
    for i, g in ipairs(C.grids) do
        local x, y, r = Inv.FindSpot(g.items, g.w, g.h, it)
        if x then
            if from then Detach(ply, it, from.loc, from.list, from.idx) end
            it.x, it.y, it.r = x, y, r and true or false
            g.items[#g.items + 1] = it
            if Inv.MarkSeen then Inv.MarkSeen(ply, ent, it) end
            hook.Run("MCC_ContainerChanged", ent, ply)
            for _, other in ipairs(player.GetAll()) do
                if other ~= ply and other.MCCInvOpen == ent then Inv.Update(other) end
            end
            return true
        end
    end
    return false, "No room in there"
end

-- Grids to fill automatically, in order: rig, pockets, backpack (never the pouch).
local function AutoLocs(inv, it)
    local locs = {}
    local function addGear(key)
        local gear = inv.slots[key]
        for i = 1, #(Inv.Cells(gear) or {}) do locs[#locs + 1] = "g:" .. key .. ":" .. i end
    end
    addGear("rig")
    local def = Inv.Def(it)
    if def and def.w == 1 and def.h == 1 then
        for i = 1, Inv.POCKETS do locs[#locs + 1] = "s:pocket" .. i end
    end
    addGear("backpack")
    return locs
end

-- Tries each location in order, finding a free cell in grids. from = nil for new items.
local function TryLocs(ply, it, locs, from)
    for _, to in ipairs(locs) do
        if not from or to ~= from.loc then
            local _, kind = Inv.ParseLoc(to)
            if kind == "slot" then
                if Insert(ply, it, to, 0, 0, false, from) then return true end
            else
                local gw, gh, list = Inv.GetGrid(ply, to)
                if list then
                    local x, y, r = Inv.FindSpot(list, gw, gh, it)
                    if x and Insert(ply, it, to, x, y, r, from) then return true end
                end
            end
        end
    end
    return false
end

-- Every stack of item id the player carries in rig, pockets and backpack (for topping up).
local function StacksOf(ply, id)
    local inv = Inv.Get(ply)
    local out = {}
    local function scan(gear)
        for _, list in ipairs(gear and gear.cont or {}) do
            for _, o in ipairs(list) do
                if o.id == id then out[#out + 1] = o end
            end
        end
    end
    scan(inv.slots.rig)
    for i = 1, Inv.POCKETS do
        local o = inv.slots["pocket" .. i]
        if o and o.id == id then out[#out + 1] = o end
    end
    scan(inv.slots.backpack)
    return out
end

-- Gives an item that isn't in any inventory yet: equipment slot if free, then stacks, then grids.
-- Returns true when all of it fit; a partly-placed stack keeps the remainder in it.n.
function Inv.GiveItem(ply, it)
    local inv = Inv.Get(ply)
    local def = Inv.Def(it)
    if not def then return false end

    if def.kind == "weapon" and def.class and not CarriesClass(inv, def.class) then
        for _, key in ipairs(Inv.WeaponSlots) do
            if not inv.slots[key] and Inv.SlotAccepts(key, def) then
                inv.slots[key] = it
                Inv.GiveWeapon(ply, it)
                return true
            end
        end
    end
    for key, s in pairs(Inv.Slots) do
        if (s.gear or s.armor or s.dataSlot) and not inv.slots[key] and Inv.SlotAccepts(key, def) then
            inv.slots[key] = it
            return true
        end
    end
    if def.maxStack > 1 then
        for _, stack in ipairs(StacksOf(ply, it.id)) do
            if select(2, Merge(stack, it)) then return true end
        end
    end
    if it.cont and not Inv.IsEmptyGear(it) then return false end
    return TryLocs(ply, it, AutoLocs(inv, it), nil)
end

-- Creates and gives `n` of item id. Returns how many didn't fit.
function Inv.GiveID(ply, id, n, d)
    n = math.max(1, math.floor(n or 1))
    if not MCC.Items.Get(id) then return n end
    while n > 0 do
        local it = Inv.NewItem(id, n, d and table.Copy(d) or nil)
        local made = Inv.Count(it)
        if not Inv.GiveItem(ply, it) then
            return n - (made - Inv.Count(it))
        end
        n = n - made
    end
    return 0
end

-- Hotkeys ----------------------------------------------------------------------------------

-- Ctrl+click: send an item to the most sensible other place.
function Inv.Quick(ply, u)
    local it, loc, list, idx = Inv.Find(ply, u)
    if not it then return false end
    local def = Inv.Def(it)
    local from = {loc = loc, list = list, idx = idx}
    local inv = Inv.Get(ply)
    local order = {}

    if Inv.ParseLoc(loc) ~= "p" then
        -- looting: equipment slot first, then rig / pockets / backpack
        for _, key in ipairs({"sling", "back", "holster", "sheath", "rig", "backpack", "armor", "headwear",
            "earpiece", "facecover", "eyewear", "armband", "dogtag"}) do
            if Inv.SlotAccepts(key, def) then order[#order + 1] = "s:" .. key end
        end
        for _, l in ipairs(AutoLocs(inv, it)) do order[#order + 1] = l end
    else
        local e = Inv.OpenTarget(ply)
        if e and e.MCCCont.grids then
            for i = 1, #e.MCCCont.grids do order[#order + 1] = "c:" .. i end
        elseif e and e.MCCCont.inv then
            for _, key in ipairs({"backpack", "rig"}) do
                for i = 1, #(Inv.Cells(e.MCCCont.inv.slots[key]) or {}) do order[#order + 1] = "bg:" .. key .. ":" .. i end
            end
        end
        local _, _, fromKey = Inv.ParseLoc(loc)
        for _, l in ipairs(AutoLocs(inv, it)) do
            local _, _, key = Inv.ParseLoc(l)
            if key ~= fromKey then order[#order + 1] = l end
        end
    end

    if TryLocs(ply, it, order, from) then return true end
    return false, "No room"
end

-- Alt+click: put the item on (weapon slots, gear and armor slots).
function Inv.Equip(ply, u)
    local it, loc, list, idx = Inv.Find(ply, u)
    if not it then return false end
    local def = Inv.Def(it)
    local inv = Inv.Get(ply)
    local locs = {}
    for _, key in ipairs({"sling", "back", "holster", "sheath", "rig", "backpack", "pouch", "armor", "headwear",
        "earpiece", "facecover", "eyewear", "armband", "dogtag"}) do
        if Inv.SlotAccepts(key, def) and not inv.slots[key] then locs[#locs + 1] = "s:" .. key end
    end
    if #locs == 0 then return false, "Nothing free to put that on" end
    if TryLocs(ply, it, locs, {loc = loc, list = list, idx = idx}) then return true end
    return false, "Can't equip that"
end

-- Splits a stack in half into a free spot in the same grid (or anywhere the player has room).
function Inv.Split(ply, u)
    local it, from, list = Inv.Find(ply, u)
    if not it or Inv.Count(it) < 2 then return false end
    local half = math.floor(Inv.Count(it) / 2)
    local part = {u = Inv.NewUID(), id = it.id, n = half}
    if list then
        local gw, gh = Inv.GetGrid(ply, from)
        local x, y, r = Inv.FindSpot(list, gw, gh, part)
        if x then
            part.x, part.y, part.r = x, y, r
            list[#list + 1] = part
            it.n = it.n - half
            return true
        end
    end
    if TryLocs(ply, part, AutoLocs(Inv.Get(ply), part), nil) then
        it.n = it.n - half
        return true
    end
    return false, "No room to split"
end

function Inv.Drop(ply, u)
    local it, from, list, idx = Inv.Find(ply, u)
    if not it then return false end
    Detach(ply, it, from, list, idx)
    Inv.SpawnWorldItem(it, ply:GetShootPos() + ply:GetAimVector() * 40, ply)
    return true
end

-- Consumables: used from anywhere in the player's own inventory.
function Inv.Use(ply, u)
    local it, from, list, idx = Inv.Find(ply, u)
    if not it or Inv.ParseLoc(from) ~= "p" then return false end
    local def = Inv.Def(it)
    if not def or def.kind ~= "consumable" then return false end
    local d = def.data or {}
    local amount = d.amount or 0
    local cv = d.convar and GetConVar(d.convar)
    if cv then amount = cv:GetInt() end

    if d.effect == "health" then
        if ply:Health() >= ply:GetMaxHealth() then return false, "Already at full health" end
        ply:SetHealth(math.min(ply:GetMaxHealth(), ply:Health() + amount))
        ply:EmitSound("items/smallmedkit1.wav")
    elseif d.effect == "armor" then
        if ply:Armor() >= ply:GetMaxArmor() then return false, "Armor is already full" end
        ply:SetArmor(math.min(ply:GetMaxArmor(), ply:Armor() + amount))
        ply:EmitSound("items/battery_pickup.wav")
    else
        local ok, err = hook.Run("MCC_UseItem", ply, it, def)
        if ok ~= true then return false, err end
    end

    if def.maxStack > 1 and Inv.Count(it) > 1 then
        it.n = it.n - 1
    else
        Detach(ply, it, from, list, idx)
    end
    return true
end

-- Magazines -----------------------------------------------------------------------------------

-- Every loose stack of an ammo type the player carries, anywhere in their own gear.
local function LooseAmmo(ply, ammoType)
    local inv = Inv.Get(ply)
    local out = {}
    for key, it in pairs(inv.slots) do
        local def = Inv.Def(it)
        if def and def.kind == "ammo" and def.data.ammo == ammoType then out[#out + 1] = {it = it, key = key} end
        for _, list in ipairs(it.cont or {}) do
            for j, o in ipairs(list) do
                local od = Inv.Def(o)
                if od and od.kind == "ammo" and od.data.ammo == ammoType then out[#out + 1] = {it = o, list = list} end
            end
        end
    end
    return out
end

-- Takes up to `need` loose rounds of an ammo type out of the player's gear. Returns how many.
local function TakeLoose(ply, ammoType, need)
    local loaded = 0
    for _, s in ipairs(LooseAmmo(ply, ammoType)) do
        if need <= 0 then break end
        local take = math.min(need, Inv.Count(s.it))
        s.it.n = Inv.Count(s.it) - take
        need, loaded = need - take, loaded + take
        if s.it.n <= 0 then
            if s.key then
                Inv.Get(ply).slots[s.key] = nil
            else
                for j, o in ipairs(s.list) do
                    if o == s.it then table.remove(s.list, j) break end
                end
            end
        end
    end
    return loaded
end

-- Fills a magazine from loose rounds in the player's gear.
function Inv.LoadMag(ply, u)
    local mag, loc = Inv.Find(ply, u)
    local def = Inv.Def(mag)
    if not mag or not def or def.kind ~= "mag" or Inv.ParseLoc(loc) ~= "p" then return false end
    local need = (def.data.cap or 0) - Inv.MagRounds(mag)
    if need <= 0 then return false, "Already full" end
    local loaded = TakeLoose(ply, def.data.ammo, need)
    if loaded == 0 then return false, "No loose rounds for it" end
    mag.d = mag.d or {}
    mag.d.rounds = Inv.MagRounds(mag) + loaded
    return true
end

-- The live weapon for an equipped weapon item, if it's in one of the player's hands slots.
local function LiveWeapon(ply, it, loc)
    local _, kind, key = Inv.ParseLoc(loc)
    if kind ~= "slot" or not IsWeaponSlot(key) then return nil end
    local w = ply:GetWeapon(WeaponClass(it) or "")
    return IsValid(w) and w or nil
end

-- Loads loose rounds straight into a gun (its own magazine, tube or cylinder).
function Inv.LoadWeapon(ply, u)
    local it, loc = Inv.Find(ply, u)
    local def = Inv.Def(it)
    if not it or not def or def.kind ~= "weapon" or Inv.ParseLoc(loc) ~= "p" then return false end
    local live = LiveWeapon(ply, it, loc)
    local cap, ammo = def.data.clip or 0, Inv.WeaponAmmo(ply, it)
    if live and live:GetMaxClip1() > 0 then cap = live:GetMaxClip1() end
    if cap <= 0 or not ammo then return false end
    local cur = live and live:Clip1() or (it.d and it.d.clip or 0)
    if cur >= cap then return false, "Already full" end
    local got = TakeLoose(ply, ammo, cap - cur)
    if got == 0 then return false, "No loose rounds for it" end
    it.d = it.d or {}
    it.d.clip = cur + got
    if live then live:SetClip1(cur + got) end
    return true
end

-- Takes the rounds out of a gun as loose rounds.
function Inv.UnloadWeapon(ply, u)
    local it, loc = Inv.Find(ply, u)
    local def = Inv.Def(it)
    if not it or not def or def.kind ~= "weapon" or Inv.ParseLoc(loc) ~= "p" then return false end
    local live = LiveWeapon(ply, it, loc)
    local cur = live and live:Clip1() or (it.d and it.d.clip or 0)
    local ammoType = Inv.WeaponAmmo(ply, it)
    local ammoID = ammoType and Inv.AmmoItem[ammoType]
    if cur <= 0 or not ammoID then return false, "It's empty" end
    local left = Inv.GiveID(ply, ammoID, cur)
    if left == cur then return false, "No room for the rounds" end
    it.d = it.d or {}
    it.d.clip = left
    if live then live:SetClip1(left) end
    return true
end

-- Pressing reload with nothing loaded explains what to do instead of silently failing.
hook.Add("KeyPress", "MCC_InvReloadHint", function(ply, key)
    if key ~= IN_RELOAD or not Inv.Enabled() or not MCC.Config.Get("mags_required") then return end
    local w = ply:GetActiveWeapon()
    if not IsValid(w) then return end
    local id = MCC.Items.FromClass(w:GetClass())
    local def = id and MCC.Items.Get(id)
    if not def or def.data.feed ~= "mag" then return end
    local ammoName = game.GetAmmoName and game.GetAmmoName(w:GetPrimaryAmmoType()) or def.data.ammo
    if ply:GetAmmoCount(ammoName or def.data.ammo) > 0 then return end
    if w:Clip1() >= w:GetMaxClip1() or (ply.MCCReloadHint or 0) > CurTime() then return end
    ply.MCCReloadHint = CurTime() + 4
    Inv.Notify(ply, "No loaded magazine. In the inventory, right-click a magazine or your gun > Load from loose rounds")
end)

-- Empties a magazine into loose rounds (whatever doesn't fit stays in the magazine).
function Inv.UnloadMag(ply, u)
    local mag, loc = Inv.Find(ply, u)
    local def = Inv.Def(mag)
    if not mag or not def or def.kind ~= "mag" or Inv.ParseLoc(loc) ~= "p" then return false end
    local rounds = Inv.MagRounds(mag)
    local ammoID = Inv.AmmoItem[def.data.ammo]
    if rounds <= 0 or not ammoID then return false, "It's empty" end
    local left = Inv.GiveID(ply, ammoID, rounds)
    mag.d.rounds = left
    if left == rounds then return false, "No room for the rounds" end
    return true
end

-- Ammo and grenades ----------------------------------------------------------------------
-- What's in the rig, pockets and special slots is mirrored into the player's real ammo so the
-- engine reloads from it. For magazine-fed guns the mirrored amount is the fullest magazine, and
-- a reload swaps magazines (see the poll below). Backpack contents are only carried.

local function ForUsable(inv, fn)
    local rig = inv.slots.rig
    for _, list in ipairs(rig and rig.cont or {}) do
        for j = #list, 1, -1 do fn(list[j], list, j) end
    end
    for key, s in pairs(Inv.Slots) do
        if (s.pocket or s.special) and inv.slots[key] then fn(inv.slots[key], nil, nil, key) end
    end
end

-- The ammo type a weapon item fires right now. Weapon bases where it changes (ARC9 magazines that switch
-- caliber) answer through hook.Add("MCC_WeaponAmmo", id, function(ply, it, def) return "ammo type" end).
function Inv.WeaponAmmo(ply, it)
    local def = Inv.Def(it)
    if not def then return nil end
    local a = hook.Run("MCC_WeaponAmmo", ply, it, def)
    if isstring(a) and a ~= "" then return a end
    return def.data.ammo
end

-- Does magazine item mag fit weapon item it? By default any magazine of the gun's ammo type does;
-- hook.Add("MCC_MagFits", id, function(ply, it, mag, magDef) return true/false end) narrows it (one gun's mags).
function Inv.MagFits(ply, it, mag)
    local magDef = Inv.Def(mag)
    if not magDef or magDef.kind ~= "mag" then return false end
    local r = hook.Run("MCC_MagFits", ply, it, mag, magDef)
    if r ~= nil then return r end
    return magDef.data.ammo == Inv.WeaponAmmo(ply, it)
end

-- Ammo types fed by magazines right now: the equipped mag-fed weapons' types -> weapon item. When two
-- equipped guns share an ammo type, the one in your hands wins.
local function MagFedTypes(inv, ply)
    local out = {}
    if not MCC.Config.Get("mags_required") then return out end
    local active = IsValid(ply) and ply.GetActiveWeapon and ply:GetActiveWeapon()
    local activeClass = IsValid(active) and active:GetClass() or nil
    for _, key in ipairs(Inv.WeaponSlots) do
        local it = inv.slots[key]
        local def = it and Inv.Def(it)
        if def and def.data.feed == "mag" then
            local ammo = Inv.WeaponAmmo(ply, it)
            if ammo and (not out[ammo] or def.class == activeClass) then out[ammo] = it end
        end
    end
    return out
end

-- The fullest usable magazine that fits the weapon item (or, without one, of the ammo type).
local function BestMag(inv, ammoType, weaponIt, ply)
    local best
    ForUsable(inv, function(it)
        local def = Inv.Def(it)
        if def and def.kind == "mag" and Inv.MagRounds(it) > 0 then
            local fits
            if weaponIt then fits = Inv.MagFits(ply, weaponIt, it) else fits = def.data.ammo == ammoType end
            if fits and (not best or Inv.MagRounds(it) > Inv.MagRounds(best)) then best = it end
        end
    end)
    return best
end

local function UsableTotals(inv, ply)
    local ammo, grenades, mags = {}, {}, {}
    local magFed = MagFedTypes(inv, ply)
    ForUsable(inv, function(it)
        local def = Inv.Def(it)
        if not def then return end
        if def.kind == "ammo" and def.data.ammo and not magFed[def.data.ammo] then
            ammo[def.data.ammo] = (ammo[def.data.ammo] or 0) + Inv.Count(it)
        elseif def.kind == "weapon" and def.data.slot == "grenade" and def.data.ammo then
            ammo[def.data.ammo] = (ammo[def.data.ammo] or 0) + Inv.Count(it)
            grenades[def.class] = true
        end
    end)
    for ammoType, weaponIt in pairs(magFed) do
        local mag = BestMag(inv, ammoType, weaponIt, ply)
        ammo[ammoType] = mag and Inv.MagRounds(mag) or 0
        mags[ammoType] = mag and mag.u or nil
    end
    return ammo, grenades, mags
end

-- Grenades some weapon bases keep "in hand" (ARC9 holds one in the clip and draws it out of the reserve when
-- you equip it). Those count toward what you carry, so moving one between hand and reserve isn't a throw.
local function GrenadeInHand(ply, name)
    local n = 0
    for _, def in ipairs(MCC.Items.GrenadeDefs()) do
        if def.data.ammo == name then
            local w = ply.GetWeapon and ply:GetWeapon(def.class)
            if IsValid(w) and w.Clip1 then n = n + math.max(0, w:Clip1() or 0) end
        end
    end
    return n
end
Inv.GrenadeInHand = GrenadeInHand

local function GrenadeTypes()
    local t = {}
    for _, def in ipairs(MCC.Items.GrenadeDefs()) do
        if def.data.ammo then t[def.data.ammo] = true end
    end
    return t
end

function Inv.SyncAmmo(ply)
    if not ply:Alive() then return end
    local inv = Inv.Get(ply)
    local ammo, grenades, mags = UsableTotals(inv, ply)
    for name in pairs(ply.MCCAmmoMirror or {}) do
        if not ammo[name] then ply:SetAmmo(0, name) end
    end
    local gTypes = GrenadeTypes()
    for name, n in pairs(ammo) do
        if gTypes[name] then n = math.max(0, n - GrenadeInHand(ply, name)) end
        ply:SetAmmo(n, name)
    end
    ply.MCCAmmoMirror = ammo
    ply.MCCMagMirror = mags

    for _, def in ipairs(MCC.Items.GrenadeDefs()) do
        do
            local has = ply:HasWeapon(def.class)
            if grenades[def.class] and not has then
                ply.MCCInvGiving = true
                ply:Give(def.class, true)
                ply.MCCInvGiving = nil
            elseif not grenades[def.class] and has then
                ply:StripWeapon(def.class)
            end
        end
    end
end

-- Takes n rounds of a loose-ammo type (or grenades) out of usable storage.
local function RemoveAmmo(ply, name, n)
    local inv = Inv.Get(ply)
    ForUsable(inv, function(it, list, j, slotKey)
        if n <= 0 then return end
        local def = Inv.Def(it)
        if not def or def.data.ammo ~= name then return end
        if def.kind ~= "ammo" and not (def.kind == "weapon" and def.data.slot == "grenade") then return end
        local take = math.min(Inv.Count(it), n)
        n = n - take
        if def.maxStack > 1 and Inv.Count(it) > take then
            it.n = it.n - take
        elseif list then
            table.remove(list, j)
        else
            inv.slots[slotKey] = nil
        end
    end)
end

-- A magazine-fed gun reloaded: the engine moved `taken` rounds from the mirrored magazine into
-- the gun. Make it a real swap: the gun gets that whole magazine, the rounds that were left in the
-- gun go back into the same magazine item, which stays in the rig as a partly full (or empty) mag.
local function MagReloaded(ply, weaponItem, magU, taken)
    local wep = ply:GetWeapon(WeaponClass(weaponItem) or "")
    local mag
    ForUsable(Inv.Get(ply), function(it) if it.u == magU then mag = it end end)
    if not IsValid(wep) or not mag then return end
    local before = math.max(0, wep:Clip1() - taken)
    local newClip = math.min(Inv.MagRounds(mag), wep:GetMaxClip1())
    wep:SetClip1(newClip)
    mag.d = mag.d or {}
    mag.d.rounds = math.min(before, Inv.MagCap(mag))
end

-- Adds rounds gained outside the inventory (ammo crates, Give commands). Leftovers drop at the feet.
local function AddAmmo(ply, name, n)
    local id = Inv.AmmoItem[name]
    if not id then return end
    local left = Inv.GiveID(ply, id, n)
    if left > 0 then
        Inv.SpawnWorldItem(Inv.NewItem(id, left), ply:GetPos() + Vector(0, 0, 20), ply)
    end
end

-- Watches each player's real ammo: shots, reloads and throws come out of the rig, gains go in.
function Inv.PollAmmo(ply)
    if not ply.MCCInv or not ply:Alive() or not ply.MCCAmmoMirror then return end
    local inv = ply.MCCInv
    local magFed = MagFedTypes(inv, ply)
    local changed = false
    local names = {}
    for name in pairs(ply.MCCAmmoMirror) do names[name] = true end
    for name in pairs(Inv.AmmoItem) do names[name] = true end
    local gTypes = GrenadeTypes()
    for name in pairs(names) do
        local have, want = ply:GetAmmoCount(name), ply.MCCAmmoMirror[name] or 0
        local inHand = gTypes[name] and GrenadeInHand(ply, name) or 0
        have = have + inHand
        if inHand > 0 and have > want then
            -- a grenade the weapon put in your hand by itself (ARC9 does on first draw): not a real gain
            local extra = have - want
            local reserve = ply:GetAmmoCount(name)
            local fromReserve = math.min(extra, reserve)
            ply:SetAmmo(reserve - fromReserve, name)
            extra = extra - fromReserve
            if extra > 0 then
                for _, def in ipairs(MCC.Items.GrenadeDefs()) do
                    local w = extra > 0 and def.data.ammo == name and ply:GetWeapon(def.class)
                    if IsValid(w) and (w:Clip1() or 0) > 0 then
                        local take = math.min(extra, w:Clip1())
                        w:SetClip1(w:Clip1() - take)
                        extra = extra - take
                    end
                end
            end
        elseif have > want then
            if magFed[name] then ply:SetAmmo(want, name) end -- gains of mag-fed ammo arrive as loose rounds
            AddAmmo(ply, name, have - want)
            changed = true
        elseif have < want then
            if magFed[name] then
                MagReloaded(ply, magFed[name], ply.MCCMagMirror and ply.MCCMagMirror[name], want - have)
            else
                RemoveAmmo(ply, name, want - have)
            end
            changed = true
        end
    end
    if changed then Inv.Update(ply) end
end

timer.Create("MCC_InvAmmoPoll", 0.2, 0, function()
    if not Inv.Enabled() then return end
    for _, ply in ipairs(player.GetAll()) do Inv.PollAmmo(ply) end
end)

-- Sync -------------------------------------------------------------------------------------

local dirty = {}

-- Marks a player's inventory as changed; it's mirrored and sent once at the end of the tick.
function Inv.Update(ply)
    if IsValid(ply) then dirty[ply] = true end
end

-- Sends a player their inventory: only the slots that changed since the last send (and what they're
-- looking into, if that changed), or everything when full is set or nothing was sent yet. A slot holds its
-- whole contents (a backpack and what's in it), so firing a gun re-sends the rig, not the whole kit.
function Inv.Send(ply, full)
    local slots, open = Inv.Get(ply).slots, Inv.OpenPayload(ply)
    local sent = ply.MCCSentSlots
    local openJSON = util.TableToJSON(open and MCC.Util.JSONSafe(open) or {}) or ""
    if full or not sent then
        sent = {}
        for k, it in pairs(slots) do sent[k] = util.TableToJSON(MCC.Util.JSONSafe(it)) or "" end
        ply.MCCSentSlots, ply.MCCSentOpen = sent, openJSON
        MCC.Net.Send("inv_sync", {slots = slots, open = open}, ply)
        return true
    end
    local changed, gone, any = {}, {}, false
    for k, it in pairs(slots) do
        local j = util.TableToJSON(MCC.Util.JSONSafe(it)) or ""
        if sent[k] ~= j then
            sent[k], changed[k], any = j, it, true
        end
    end
    for k in pairs(sent) do
        if slots[k] == nil then
            sent[k] = nil
            gone[#gone + 1] = k
            any = true
        end
    end
    local d = {diff = true, slots = changed, gone = gone}
    if openJSON ~= ply.MCCSentOpen then
        ply.MCCSentOpen = openJSON
        d.oc, d.open, any = true, open, true
    end
    if not any then return false end
    MCC.Net.Send("inv_sync", d, ply)
    return true
end

hook.Add("Think", "MCC_InvFlush", function()
    if not next(dirty) then return end
    local list = dirty
    dirty = {}
    for ply in pairs(list) do
        if IsValid(ply) then
            Inv.SyncAmmo(ply)
            Inv.Send(ply)
            Inv.RefreshWorn(ply)
            hook.Run("MCC_InventorySynced", ply)
            -- anyone else looking at the same body or container sees the change too
            local e = ply.MCCInvOpen
            if IsValid(e) then
                if e.MCCCont and e.MCCCont.inv then Inv.RefreshWorn(e) end
                if e.MCCCont then hook.Run("MCC_ContainerChanged", e, ply) end
                for _, other in ipairs(player.GetAll()) do
                    if other ~= ply and other.MCCInvOpen == e and not list[other] then Inv.Send(other) end
                end
            end
        end
    end
end)

-- A container's contents, set up the first time it's used.
function Inv.EnsureContainer(ent)
    if not IsValid(ent) then return nil end
    if not ent.MCCCont then
        local def = Inv.ContainerDef(ent)
        if not def then return nil end
        local grids = {}
        for i, cell in ipairs(Inv.ContainerCells(def)) do grids[i] = {w = cell.w, h = cell.h, items = {}} end
        ent.MCCCont = {name = def.name, grids = grids, vertical = def.vertical}
    end
    local C = ent.MCCCont
    if C.items and not C.grids then -- opened before compartments existed (Lua refresh)
        C.grids = {{w = C.w or 4, h = C.h or 4, items = C.items}}
        C.items, C.w, C.h = nil, nil, nil
    end
    return C
end

function Inv.OpenContainer(ply, ent)
    if not Inv.EnsureContainer(ent) then return false end
    if ply.MCCInvOpen ~= ent then ply.MCCSearch = nil end
    ply.MCCInvOpen = ent
    hook.Run("MCC_ContainerOpened", ply, ent)
    Inv.Send(ply)
    MCC.Net.Send("inv_open", {}, ply)
    return true
end

-- Client requests --------------------------------------------------------------------------

local function Notify(ply, msg)
    if msg then MCC.Net.Send("inv_notify", {msg = msg}, ply) end
end
Inv.Notify = Notify

local ACTIONS = {
    move = function(ply, a) return Inv.Move(ply, a.u, a.to, a.x, a.y, a.r) end,
    quick = function(ply, a) return Inv.Quick(ply, a.u) end,
    equip = function(ply, a) return Inv.Equip(ply, a.u) end,
    drop = function(ply, a) return Inv.Drop(ply, a.u) end,
    use = function(ply, a) return Inv.Use(ply, a.u) end,
    split = function(ply, a) return Inv.Split(ply, a.u) end,
    load = function(ply, a) return Inv.LoadMag(ply, a.u) end,
    unload = function(ply, a) return Inv.UnloadMag(ply, a.u) end,
    loadgun = function(ply, a) return Inv.LoadWeapon(ply, a.u) end,
    unloadgun = function(ply, a) return Inv.UnloadWeapon(ply, a.u) end,
    -- an item of yours dragged onto a container in the vicinity list (c = its entity index)
    store = function(ply, a)
        local cont = type(a.c) == "number" and Entity(a.c)
        if not cont or not InReach(ply, cont) or MCC.Pickup.Kind(cont) ~= "container" then return false end
        local it, loc, list, idx = SearchInv(Inv.Get(ply), a.u, "s:", "g:")
        if not it then return false end
        return Inv.StoreIn(ply, cont, it, {loc = loc, list = list, idx = idx})
    end,
}

-- Actions on entities in the vicinity: e = entity index.
local WORLD_ACTIONS = {
    take = function(ply, a, ent) return Inv.TakeEntity(ply, ent, a.to, a.x, a.y, a.r) end,
    -- something on the ground dragged onto a container in the vicinity list
    stash = function(ply, a, ent)
        local cont = type(a.c) == "number" and Entity(a.c)
        if not cont or cont == ent or not InReach(ply, cont) or MCC.Pickup.Kind(cont) ~= "container" then return false end
        local it = Inv.ItemFromEntity(ent)
        if not it then return false end
        local ok, err = Inv.StoreIn(ply, cont, it, nil)
        if ok then ent:Remove() end
        return ok, err
    end,
    open = function(ply, a, ent)
        local kind = MCC.Pickup.Kind(ent)
        if kind == "body" and ent.MCCCont then return Inv.OpenContainer(ply, ent) end
        if kind == "container" then return Inv.OpenContainer(ply, ent) end
        return false
    end,
}

MCC.Net.Receive("inv_act", function(a, ply)
    if not Inv.Enabled() or not IsValid(ply) then return end
    if a.a == "close" then
        ply.MCCInvOpen = nil
        return
    end
    if a.a == "search" then
        if type(a.section) == "string" and Inv.OpenTarget(ply) then Inv.QueueSearch(ply, a.section) end
        Inv.Update(ply)
        return
    end
    if a.a == "request" then
        ply.MCCInvOpen = nil
        Inv.Send(ply)
        return
    end
    if not ply:Alive() then return end
    if a.to ~= nil and type(a.to) ~= "string" then return end

    local ok, err
    local wfn = WORLD_ACTIONS[a.a]
    if wfn then
        if type(a.e) ~= "number" then return end
        local ent = Entity(a.e)
        if not InReach(ply, ent) then return end
        ok, err = wfn(ply, a, ent)
    else
        local fn = ACTIONS[a.a]
        if not fn or type(a.u) ~= "number" then return end
        ok, err = fn(ply, a)
    end
    if not ok then Notify(ply, err) end
    Inv.Update(ply)
end, {allowClient = true, maxBytes = 512})

-- Save / load ------------------------------------------------------------------------------

local function ReID(it)
    it.u = Inv.NewUID()
    for _, list in ipairs(it.cont or {}) do
        for _, o in ipairs(list) do ReID(o) end
    end
end

-- Items that were retired in favour of another: saved ones come back as the new item (when it's
-- registered). Gear keeps what fits in its new pockets, compartment by compartment; the rest is lost.
Inv.Renamed = Inv.Renamed or {}
Inv.Renamed.rig_scav = "rig_scav_vest" -- MCC Base's generic Scav Vest (0.17.0) -> MCC Gear's

function Inv.Rename(it)
    local to = it and Inv.Renamed[it.id]
    if not to or not MCC.Items.Get(to) then return it end
    it.id = to
    local cells = (MCC.Items.Get(to).data or {}).cells
    if it.cont and cells then
        local cont = {}
        for i, cell in ipairs(cells) do
            cont[i] = {}
            for _, o in ipairs(it.cont[i] or {}) do
                local w, h = Inv.Size(o)
                if (o.x or 0) + w <= cell.w and (o.y or 0) + h <= cell.h then table.insert(cont[i], o) end
            end
        end
        it.cont = cont
    end
    return it
end

-- Drops items whose registry id no longer exists (an admin removed them).
local function Prune(list)
    for j = #list, 1, -1 do
        Inv.Rename(list[j])
        if not MCC.Items.Get(list[j].id) then
            table.remove(list, j)
        else
            for _, sub in ipairs(list[j].cont or {}) do Prune(sub) end
        end
    end
end
Inv.ReID, Inv.Prune = ReID, Prune -- for restoring saved item lists (extraction crates)

-- This session: a saved inventory from another one (the server restarted or changed map) is wiped
-- down to the pouch when it loads, like leaving.
Inv.Session = Inv.Session or (tostring(os.time()) .. "-" .. math.random(1000, 9999))

function Inv.Save(ply)
    if not ply.MCCInv or not ply.MCCInvLoaded then return end
    if ply:Alive() then Inv.StampWeapons(ply) end
    MCC.Data.Set("inv", ply:SteamID64(), {slots = ply.MCCInv.slots, session = Inv.Session})
end

function Inv.Load(ply)
    ply.MCCInvLoaded = true
    local saved = MCC.Data.Get("inv", ply:SteamID64())
    if not saved or not saved.slots then
        ply.MCCInv = {slots = {}}
        return
    end
    local inv = {slots = {}}
    local wiped = MCC.Config.Get("inv_leave_wipe") and saved.session ~= Inv.Session
    for key, it in pairs(saved.slots) do
        if wiped and key ~= "pouch" then
            ply.MCCInvWiped = true -- left in another session: only the pouch comes back
        elseif Inv.Slots[key] and MCC.Items.Get(Inv.Rename(it).id) then
            ReID(it)
            for _, sub in ipairs(it.cont or {}) do Prune(sub) end
            inv.slots[key] = it
        end
    end
    ply.MCCInv = inv
end

function Inv.GiveStarter(ply)
    for id in string.gmatch(MCC.Config.Get("inv_starter"), "[^,%s]+") do
        if MCC.Items.Get(id) then Inv.GiveID(ply, id, 1) end
    end
end

hook.Add("PlayerInitialSpawn", "MCC_InvLoad", function(ply)
    if Inv.Enabled() then Inv.Load(ply) end
end)

hook.Add("PlayerLoadout", "MCC_InvLoadout", function(ply)
    if not Inv.Enabled() then return end
    if not ply.MCCInvLoaded then Inv.Load(ply) end

    MCC.Pickup.Bypass(ply, function()
        for class in string.gmatch(MCC.Config.Get("inv_always_weapons"), "[^,%s]+") do ply:Give(class) end
    end)

    local inv = Inv.Get(ply)
    if next(inv.slots) == nil then Inv.GiveStarter(ply) end
    if ply.MCCInvWiped then
        ply.MCCInvWiped = nil
        timer.Simple(2, function()
            if IsValid(ply) then Inv.Notify(ply, "New session: you kept only what was in your Alpha Container.") end
        end)
    end
    for _, key in ipairs(Inv.WeaponSlots) do
        if inv.slots[key] then Inv.GiveWeapon(ply, inv.slots[key]) end
    end
    ply.MCCAmmoMirror = {}
    Inv.Update(ply)
    return true -- skip the Sandbox default loadout
end)

hook.Add("MCC_Save", "MCC_InvSave", function()
    for _, ply in ipairs(player.GetAll()) do Inv.Save(ply) end
end)

-- Leaving: everything but the pouch is lost (left behind as a body, see sv_inventory_world.lua).
hook.Add("PlayerDisconnected", "MCC_InvSave", function(ply)
    if Inv.Enabled() and MCC.Config.Get("inv_leave_wipe") and ply.MCCInvLoaded and ply.MCCInv and Inv.LeaveBehind then
        Inv.LeaveBehind(ply)
    end
    Inv.Save(ply)
    dirty[ply] = nil
end)

-- In singleplayer GMod runs key hooks only on the server, so the inventory key is caught here.
hook.Add("PlayerButtonDown", "MCC_InventoryKeySP", function(ply, key)
    if not game.SinglePlayer() or not Inv.Enabled() or ply:IsTyping() then return end
    if key == ply:GetInfoNum("mcc_inventory_key", KEY_I) then MCC.Net.Send("inv_key", {}, ply) end
end)

-- Admin -----------------------------------------------------------------------------------

local function FindPlayer(caller, name)
    if not name then return caller end
    local want = string.lower(name)
    for _, p in ipairs(player.GetAll()) do
        if string.find(string.lower(p:Nick()), want, 1, true) then return p end
    end
end

MCC.Command("give", "MCC Moderator", "<item id> [amount] [player name]",
"Puts items into a player's inventory. Magazines come loaded.", function(caller, args)
    local id, n = args[1], tonumber(args[2] or "1") or 1
    local def = id and MCC.Items.Get(id)
    if not def then return MCC.Util.Reply(caller, "No item '%s'. See mcc_item_list.", tostring(id)) end
    local target = FindPlayer(caller, args[3])
    if not IsValid(target) then return MCC.Util.Reply(caller, "Player not found.") end
    local d = def.kind == "mag" and {rounds = def.data.cap} or nil
    local left = Inv.GiveID(target, id, n, d)
    Inv.Update(target)
    MCC.Util.Reply(caller, "Gave %d %s to %s%s", n - left, id, target:Nick(), left > 0 and (" (" .. left .. " didn't fit)") or "")
end)

MCC.Command("inv_clear", "MCC Admin", "[player name]", "Empties a player's inventory.", function(caller, args)
    local target = FindPlayer(caller, args[1])
    if not IsValid(target) then return MCC.Util.Reply(caller, "Player not found.") end
    for _, key in ipairs(Inv.WeaponSlots) do
        local it = Inv.Get(target).slots[key]
        if it then TakeWeaponAway(target, it) end
    end
    target.MCCInv = {slots = {}}
    Inv.Update(target)
    MCC.Util.Reply(caller, "Cleared %s's inventory.", target:Nick())
end)
