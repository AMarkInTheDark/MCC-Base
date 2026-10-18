-- The inventory meeting the world: items on the ground, taking them (E or the vicinity list),
-- searchable containers sized by model, and lootable player and NPC bodies.

local Inv = MCC.Inv

-- World items ------------------------------------------------------------------------------

-- Expansions can put something else in the world instead (a JMod box for a JMod resource):
-- hook MCC_SpawnWorldItem(item, pos, dropper, permanent) -> the entity they spawned.
function Inv.SpawnWorldItem(it, pos, dropper, permanent)
    if not it then return nil end
    local custom = hook.Run("MCC_SpawnWorldItem", it, pos, dropper, permanent)
    if IsValid(custom) then
        local life = MCC.Config.Get("inv_item_lifetime")
        if life > 0 and not permanent then SafeRemoveEntityDelayed(custom, life) end
        return custom
    end
    local e = ents.Create("mcc_item")
    if not IsValid(e) then return nil end
    it.x, it.y, it.r = nil, nil, nil
    e:SetItemID(it.id)
    e:SetPos(pos)
    e:SetAngles(Angle(0, math.random(0, 359), 0))
    e:Spawn()
    e:SetItem(it)
    if IsValid(dropper) then
        local phys = e:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dropper:GetAimVector() * 120 + dropper:GetVelocity()) end
    end
    local life = MCC.Config.Get("inv_item_lifetime")
    if life > 0 and not permanent then SafeRemoveEntityDelayed(e, life) end
    return e
end

-- Spawn menu entries (lua/entities/mcc_mag_*.lua) call this: puts one item where the player is
-- looking. Magazines come loaded. Items placed this way don't expire.
function Inv.SpawnFromMenu(id, ply, tr)
    local def = MCC.Items.Get(id)
    if not def or not tr or not tr.Hit then return nil end
    local d = def.kind == "mag" and {rounds = def.data.cap} or nil
    local e = Inv.SpawnWorldItem(Inv.NewItem(id, 1, d), tr.HitPos + tr.HitNormal * 8, nil, true)
    return e
end

-- The inventory item an entity in the world stands for, or nil if it isn't one.
local function ItemFromEntity(ent)
    local class = ent:GetClass()
    if class == "mcc_item" then return ent.MCCItem end
    if ent:IsWeapon() then
        if IsValid(ent:GetOwner()) then return nil end
        local id = MCC.Items.FromClass(class)
        if not id then return nil end
        local it = Inv.NewItem(id, 1)
        it.d = {}
        Inv.CaptureWeaponState(ent, it.d)
        return it
    end
    local box = Inv.WorldAmmo[class]
    if box then
        local id = Inv.AmmoItem[box[1]]
        return id and Inv.NewItem(id, box[2]) or nil
    end
    local id = MCC.Items.FromClass(class)
    local def = id and MCC.Items.Get(id)
    if def and def.kind ~= "ammo" then
        local it = Inv.NewItem(id, 1)
        hook.Run("MCC_ItemFromEntity", ent, it, def) -- expansions copy entity state onto the item
        return it
    end
    return nil
end

-- Takes a world entity into the player's inventory: at a chosen location when `to` is given
-- (dragged from the vicinity list), otherwise wherever it fits (E). Whatever doesn't fit stays.
Inv.ItemFromEntity = function(ent) return ItemFromEntity(ent) end

function Inv.TakeEntity(ply, ent, to, x, y, rot)
    local it = ItemFromEntity(ent)
    if not it then return false end
    local before = Inv.Count(it)
    local ok, err
    if to then
        ok, err = Inv.PlaceAt(ply, it, to, x, y, rot)
    else
        ok = Inv.GiveItem(ply, it)
        if not ok then err = "No room" end
    end
    local placed = ok and (to == nil or Inv.Find(ply, it.u) ~= nil or Inv.Count(it) <= 0)

    if placed then
        ent:Remove()
    elseif Inv.Count(it) < before then
        -- part of a stack went in
        if ent:GetClass() == "mcc_item" then
            ent:SetCount(Inv.Count(it))
        else
            Inv.SpawnWorldItem(it, ent:GetPos())
            ent:Remove()
        end
        ok, err = true, nil
    end
    Inv.Update(ply)
    return ok, err
end

-- E on a weapon, an HL2 item or an MCC item puts it in the inventory.
hook.Add("MCC_PickupWeapon", "MCC_Inventory", function(ply, wep)
    if not Inv.Enabled() then return end
    -- weapons without an item definition are picked up normally, outside the inventory
    if not MCC.Items.FromClass(wep:GetClass()) then return end
    local ok, err = Inv.TakeEntity(ply, wep)
    if not ok then Inv.Notify(ply, err) end
    return true
end)

hook.Add("MCC_PickupItem", "MCC_Inventory", function(ply, ent)
    if not Inv.Enabled() then return end
    local id = Inv.WorldItemInfo(ent)
    if not id then return end -- not an MCC item: HL2's own pickup handles it
    local ok, err = Inv.TakeEntity(ply, ent)
    if not ok then Inv.Notify(ply, err) end
    return true
end)

hook.Add("MCC_PickupCustom", "MCC_Inventory", function(ply, ent, kind)
    if not Inv.Enabled() then return end
    if kind == "mcc_item" then
        local ok, err = Inv.TakeEntity(ply, ent)
        if not ok then Inv.Notify(ply, err) end
    elseif kind == "body" and ent.MCCCont then
        Inv.OpenContainer(ply, ent)
    elseif kind == "container" then
        Inv.OpenContainer(ply, ent)
    end
end)

-- The drop key drops the weapon's inventory item (with its rounds) instead of the bare weapon.
hook.Add("MCC_DropWeapon", "MCC_Inventory", function(ply, wep)
    if not Inv.Enabled() then return end
    local class = wep:GetClass()
    local inv = Inv.Get(ply)
    for _, key in ipairs(Inv.WeaponSlots) do
        local it = inv.slots[key]
        local def = it and Inv.Def(it)
        if def and def.class == class then
            Inv.Drop(ply, it.u)
            Inv.Update(ply)
            return true
        end
    end
    -- grenades are handed out from rig stock; drop them from the inventory screen instead
    local id = MCC.Items.FromClass(class)
    local def = id and MCC.Items.Get(id)
    if def and def.data.slot == "grenade" then return true end
end)

-- Containers sized by model -----------------------------------------------------------------
-- data/mcc/containers.json: {"<model path>": {"w": 5, "h": 5, "name": "Wooden Crate"}}
-- "count" splits it into that many w x h compartments, each searched separately (lockers: 4 of 2x8);
-- "cells": [{"w": 4, "h": 3}, {"w": 4, "h": 5}] gives compartments of different sizes;
-- "vertical": true stacks them top to bottom (drawers) instead of side by side.

local DEFAULT_CONTAINERS = {
    ["models/props_junk/wood_crate001a.mdl"] = {w = 5, h = 5, name = "Wooden Crate"},
    ["models/props_junk/wood_crate002a.mdl"] = {w = 8, h = 5, name = "Large Wooden Crate"},
    ["models/props_junk/cardboard_box001a.mdl"] = {w = 3, h = 3, name = "Cardboard Box"},
    ["models/props_junk/cardboard_box002a.mdl"] = {w = 4, h = 3, name = "Cardboard Box"},
    ["models/props_c17/lockers001a.mdl"] = {w = 2, h = 8, count = 4, name = "Lockers"},
    ["models/props_lab/filecabinet02.mdl"] = {w = 2, h = 2, count = 2, vertical = true, name = "Filing Cabinet"},
    ["models/props_wasteland/controlroom_filecabinet001a.mdl"] = {w = 2, h = 2, vertical = true, name = "Filing Cabinet",
        cells = {{w = 2, h = 1}, {w = 2, h = 2}}},
    ["models/props_wasteland/controlroom_filecabinet002a.mdl"] = {w = 2, h = 2, count = 4, vertical = true, name = "Filing Cabinet"},
    ["models/props_c17/furnituredrawer001a.mdl"] = {w = 4, h = 3, name = "Drawer"},
    ["models/props_c17/furnituredrawer003a.mdl"] = {w = 2, h = 1, count = 6, vertical = true, name = "Drawers"},
    ["models/props_c17/furnituredresser001a.mdl"] = {w = 3, h = 6, count = 2, name = "Wardrobe"},
    ["models/props_c17/furniturefridge001a.mdl"] = {w = 4, h = 6, name = "Fridge"},
    ["models/props_junk/trashdumpster01a.mdl"] = {w = 8, h = 6, name = "Dumpster"},
    ["models/props_c17/suitcase001a.mdl"] = {w = 4, h = 3, name = "Suitcase"},
}

local function Size(v, def, max) return math.Clamp(math.floor(tonumber(v) or def), 1, max) end

local function SanitizeContainers(raw)
    local out = {}
    for mdl, d in pairs(raw or {}) do
        if type(mdl) == "string" and type(d) == "table" and string.sub(mdl, 1, 1) ~= "_" then
            local c = {
                w = Size(d.w, 4, 12),
                h = Size(d.h, 4, 14),
                name = string.sub(tostring(d.name or "Container"), 1, 32),
            }
            if tonumber(d.count) and tonumber(d.count) > 1 then c.count = Size(d.count, 1, 8) end
            if d.vertical then c.vertical = true end -- compartments stacked top to bottom (drawers)
            if istable(d.cells) and #d.cells > 0 then
                c.cells = {}
                for i = 1, math.min(#d.cells, 8) do
                    local cell = istable(d.cells[i]) and d.cells[i] or {}
                    c.cells[i] = {w = Size(cell.w, 2, 12), h = Size(cell.h, 2, 14)}
                end
            end
            out[string.lower(mdl)] = c
        end
    end
    return out
end

-- Defaults that changed since they were first written to a server's containers.json: an entry
-- still exactly as the old default is moved to the new one; entries an owner changed are kept.
local OLD_DEFAULTS = {
    {"models/props_c17/lockers001a.mdl", {w = 4, h = 8, name = "Lockers"}},
    {"models/props_junk/cardboard_box001a.mdl", {w = 4, h = 4, name = "Cardboard Box"}},
    {"models/props_wasteland/controlroom_filecabinet002a.mdl", {w = 4, h = 8, name = "Filing Cabinet"}},
    {"models/props_wasteland/controlroom_filecabinet001a.mdl", {w = 4, h = 6, name = "Filing Cabinet"}},
    {"models/props_wasteland/controlroom_filecabinet001a.mdl", {w = 2, h = 2, vertical = true, name = "Filing Cabinet",
        cells = {{w = 1, h = 2}, {w = 2, h = 2}}}},
    {"models/props_lab/filecabinet02.mdl", {w = 4, h = 6, name = "Filing Cabinet"}},
}

local function Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for k, v in pairs(a) do if not Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

-- Default models an owner removed with mcc_container_remove, saved as "_removed" in the file so
-- they aren't added back as new defaults.
Inv.ContainerRemoved = Inv.ContainerRemoved or {}

local function WriteContainers()
    local out = table.Copy(Inv.ContainerModels)
    local removed = table.GetKeys(Inv.ContainerRemoved)
    if #removed > 0 then
        table.sort(removed)
        out._removed = removed
    end
    MCC.Data.WriteJSON("containers.json", out)
end

function Inv.LoadContainers()
    MCC.Data.EnsureJSON("containers.json", DEFAULT_CONTAINERS)
    local raw = MCC.Data.ReadJSON("containers.json") or {}
    Inv.ContainerRemoved = {}
    for _, mdl in ipairs(istable(raw._removed) and raw._removed or {}) do
        if isstring(mdl) then Inv.ContainerRemoved[string.lower(mdl)] = true end
    end
    local upgraded = false
    for _, entry in ipairs(OLD_DEFAULTS) do
        local mdl, old = entry[1], entry[2]
        local cur = raw[mdl] and SanitizeContainers({[mdl] = raw[mdl]})[mdl]
        if cur and Same(cur, SanitizeContainers({[mdl] = old})[mdl]) then
            raw[mdl] = table.Copy(DEFAULT_CONTAINERS[mdl])
            upgraded = true
        end
    end
    -- containers added to the defaults since the file was written
    for mdl, def in pairs(DEFAULT_CONTAINERS) do
        if raw[mdl] == nil and not Inv.ContainerRemoved[mdl] then
            raw[mdl] = table.Copy(def)
            upgraded = true
        end
    end
    Inv.ContainerModels = SanitizeContainers(raw)
    if upgraded then WriteContainers() end
end

function Inv.SyncContainers(ply)
    MCC.Net.Send("inv_containers", {models = Inv.ContainerModels}, ply)
end

hook.Add("MCC_Ready", "MCC_InvContainers", function() Inv.LoadContainers() end)
hook.Add("MCC_ReloadConfig", "MCC_InvContainers", function()
    Inv.LoadContainers()
    Inv.SyncContainers()
end)

-- Clients say hello once loaded; they get the container table and their inventory.
local hello = {}
MCC.Net.Receive("inv_hello", function(_, ply)
    if hello[ply] then return end
    hello[ply] = true
    ply.MCCSentSlots = nil -- a fresh client: the next sync sends everything
    Inv.SyncContainers(ply)
    if Inv.Enabled() then Inv.Update(ply) end
end, {allowClient = true, maxBytes = 64})
hook.Add("PlayerDisconnected", "MCC_InvHello", function(ply) hello[ply] = nil end)

local function SaveContainers()
    WriteContainers()
    Inv.SyncContainers()
end

local function AimedProp(ply)
    local e = IsValid(ply) and ply:GetEyeTrace().Entity
    if IsValid(e) and e:GetModel() then return e end
end

MCC.Command("container_set", "MCC Admin", "<width> <height> [name] [compartments]",
"Makes the prop model you're looking at a searchable container: [compartments] grids of width x height (default 1).",
function(ply, args)
    local e = AimedProp(ply)
    if not e then return MCC.Util.Reply(ply, "Look at a prop first.") end
    local w, h = tonumber(args[1] or ""), tonumber(args[2] or "")
    if not w or not h then return MCC.Util.Reply(ply, "Usage: mcc_container_set <width> <height> [name] [compartments]") end
    local mdl = string.lower(e:GetModel())
    local def = SanitizeContainers({[mdl] = {w = w, h = h, name = args[3] or "Container", count = tonumber(args[4] or "")}})[mdl]
    Inv.ContainerModels[mdl] = def
    Inv.ContainerRemoved[mdl] = nil
    SaveContainers()
    if def.count then
        MCC.Util.Reply(ply, "%s is now a container with %d compartments of %dx%d.", mdl, def.count, def.w, def.h)
    else
        MCC.Util.Reply(ply, "%s is now a %dx%d container.", mdl, def.w, def.h)
    end
end)

MCC.Command("container_remove", "MCC Admin", "", "Stops the prop model you're looking at from being a container.",
function(ply)
    local e = AimedProp(ply)
    if not e then return MCC.Util.Reply(ply, "Look at a prop first.") end
    local mdl = string.lower(e:GetModel())
    Inv.ContainerModels[mdl] = nil
    if DEFAULT_CONTAINERS[mdl] then Inv.ContainerRemoved[mdl] = true end
    SaveContainers()
    MCC.Util.Reply(ply, "%s is no longer a container.", mdl)
end)

-- Bodies -------------------------------------------------------------------------------------

-- Turns an entity (usually a ragdoll) into a lootable body holding inv. Public, so the
-- ZBase expansion can give NPC corpses their faction loadout.
function Inv.MakeBody(ent, inv, name)
    ent.MCCCont = {name = name or "Body", inv = inv}
    ent:SetNWBool("MCCBody", true)
    ent:SetNWString("MCCName", name or "Body")
    Inv.RefreshWorn(ent, inv)
    Inv.TrackBody(ent)
end

-- Body cleanup: a body stays until it's looted, then lasts mcc_inv_body_looted_time (mcc_inv_body_cleanup).
-- mcc_inv_body_lifetime caps any body's life, mcc_inv_body_max how many there are. Players see the
-- countdown: NW float MCCDespawnAt (0 = not despawning).
Inv.Bodies = Inv.Bodies or {} -- body entity -> {t = made, lootedAt = first looted}

function Inv.TrackBody(ent, from)
    if not IsValid(ent) then return end
    local old = from and Inv.Bodies[from]
    Inv.Bodies[ent] = {t = old and old.t or CurTime(), lootedAt = old and old.lootedAt}
    Inv.UpdateBodyTimer(ent)
end

-- When the body will go, or nil.
function Inv.BodyDespawnAt(ent)
    local b = Inv.Bodies[ent]
    if not b then return nil end
    local at
    local life = MCC.Config.Get("inv_body_lifetime")
    if life > 0 then at = b.t + life end
    if b.lootedAt and MCC.Config.Get("inv_body_cleanup") then
        local l = b.lootedAt + MCC.Config.Get("inv_body_looted_time")
        if not at or l < at then at = l end
    end
    return at
end

function Inv.UpdateBodyTimer(ent)
    local at = Inv.BodyDespawnAt(ent) or 0
    if ent.GetNWFloat and ent:GetNWFloat("MCCDespawnAt", 0) ~= at then ent:SetNWFloat("MCCDespawnAt", at) end
end

function Inv.BodyLooted(ent)
    local b = Inv.Bodies[ent]
    if not b or b.lootedAt then return end
    b.lootedAt = CurTime()
    Inv.UpdateBodyTimer(ent)
    hook.Run("MCC_BodyLooted", ent)
end

hook.Add("MCC_ContainerChanged", "MCC_BodyCleanup", function(ent)
    if Inv.Bodies[ent] then Inv.BodyLooted(ent) end
end)

-- A ragdoll that has come to rest: every bone slower than 8 units a second.
local function Settled(ent)
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) and phys:IsMotionEnabled() and phys:GetVelocity():Length() > 8 then return false end
    end
    return true
end

-- Freezes a body's ragdoll once it has settled (mcc_inv_body_freeze seconds after death): frozen bones cost
-- no physics. A physgun or anything else that unfreezes it is fine; it's frozen again on the next check.
function Inv.FreezeBody(ent, b, now)
    local after = MCC.Config.Get("inv_body_freeze")
    if after <= 0 or now - b.t < after or not ent.GetPhysicsObjectCount then return false end
    if ent:GetPhysicsObjectCount() <= 1 or not Settled(ent) then return false end
    local froze = false
    for i = 0, ent:GetPhysicsObjectCount() - 1 do
        local phys = ent:GetPhysicsObjectNum(i)
        if IsValid(phys) and phys:IsMotionEnabled() then
            phys:EnableMotion(false)
            froze = true
        end
    end
    return froze
end

function Inv.BodyCleanupStep()
    local now = CurTime()
    local list = {}
    for ent, b in pairs(Inv.Bodies) do
        if not IsValid(ent) then
            Inv.Bodies[ent] = nil
        else
            local at = Inv.BodyDespawnAt(ent)
            if at and now >= at then
                Inv.Bodies[ent] = nil
                hook.Run("MCC_BodyDespawn", ent) -- what's still on it, for expansions (the Fence's stock)
                ent:Remove()
            else
                Inv.UpdateBodyTimer(ent) -- settings may have changed
                Inv.FreezeBody(ent, b, now)
                list[#list + 1] = {ent, b}
            end
        end
    end
    local max = MCC.Config.Get("inv_body_max")
    if max > 0 and #list > max then
        -- looted ones first, then the oldest
        table.sort(list, function(a, b)
            if (a[2].lootedAt ~= nil) ~= (b[2].lootedAt ~= nil) then return a[2].lootedAt ~= nil end
            return a[2].t < b[2].t
        end)
        for i = 1, #list - max do
            Inv.Bodies[list[i][1]] = nil
            hook.Run("MCC_BodyDespawn", list[i][1])
            list[i][1]:Remove()
        end
    end
end
timer.Create("MCC_BodyCleanup", 5, 0, Inv.BodyCleanupStep)

-- A physics ragdoll posed like the player at the moment of death.
local function MakeRagdoll(ply, dmginfo)
    local rag = ents.Create("prop_ragdoll")
    if not IsValid(rag) then return nil end
    rag:SetModel(ply:GetModel())
    rag:SetPos(ply:GetPos())
    rag:SetAngles(ply:GetAngles())
    rag:SetSkin(ply:GetSkin())
    for _, bg in ipairs(ply:GetBodyGroups() or {}) do rag:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
    rag:Spawn()
    rag:Activate()
    rag:SetCollisionGroup(COLLISION_GROUP_WEAPON)

    local vel = ply:GetVelocity()
    if dmginfo then vel = vel + dmginfo:GetDamageForce() * 0.02 end
    for i = 0, rag:GetPhysicsObjectCount() - 1 do
        local phys = rag:GetPhysicsObjectNum(i)
        local pos, ang = ply:GetBonePosition(rag:TranslatePhysBoneToBone(i))
        if IsValid(phys) and pos then
            phys:SetPos(pos)
            phys:SetAngles(ang)
            phys:SetVelocity(vel)
        end
    end
    return rag
end

-- Who killed someone and with what, for the details on their dogtag (the inspect window shows them):
-- {killer = name, killerSid = SteamID64 of a player killer, weapon = class, t = os.time()}.
-- Expansions name factions: hook.Add("MCC_DogtagFaction", id, function(victim) return "Combine" end).
function Inv.DeathInfo(victim, attacker, inflictor)
    local info = {t = os.time()}
    if IsValid(attacker) then
        if attacker:IsPlayer() then
            info.killer, info.killerSid = attacker:Nick(), attacker:SteamID64()
        elseif attacker:IsNPC() then
            info.killer = isstring(attacker.MCCName) and attacker.MCCName ~= "" and attacker.MCCName or MCC.Pickup.Name(attacker)
        end
        -- the gun in their hands, unless something else did it (a grenade, a rocket, a prop)
        local w = attacker.GetActiveWeapon and attacker:GetActiveWeapon()
        if IsValid(inflictor) and inflictor ~= attacker and not (IsValid(w) and inflictor == w) then
            info.weapon = inflictor:GetClass()
        elseif IsValid(w) then
            info.weapon = w:GetClass()
        end
    end
    if attacker == victim then info.killer = "Themselves" end
    local f = hook.Run("MCC_DogtagFaction", victim)
    if isstring(f) and f ~= "" then info.faction = f end
    return info
end

-- Replaces the default death: a server ragdoll you can loot instead of a client-only one.
hook.Add("DoPlayerDeath", "MCC_InvDeath", function(ply, attacker, dmginfo)
    if not Inv.Enabled() then return end

    local inv = Inv.Get(ply)
    Inv.StampWeapons(ply)
    local keep = inv.slots.pouch
    inv.slots.pouch = nil

    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply and MCC.Items.Get("dogtag") and not inv.slots.dogtag then
        local d = Inv.DeathInfo(ply, attacker, dmginfo and dmginfo.GetInflictor and dmginfo:GetInflictor() or nil)
        d.name, d.sid = ply:Nick(), ply:SteamID64()
        inv.slots.dogtag = Inv.NewItem("dogtag", 1, d)
    end

    local rag = MakeRagdoll(ply, dmginfo)
    if IsValid(rag) then
        Inv.MakeBody(rag, inv, ply:Nick())
        ply:SpectateEntity(rag)
        ply:Spectate(OBS_MODE_CHASE)
    else
        -- no ragdoll for this model: leave a suitcase holding the gear instead
        local box = ents.Create("prop_physics")
        if IsValid(box) then
            box:SetModel("models/props_c17/SuitCase001a.mdl")
            box:SetPos(ply:GetPos() + Vector(0, 0, 16))
            box:Spawn()
            Inv.MakeBody(box, inv, ply:Nick())
        end
    end

    ply.MCCInv = {slots = {pouch = keep}}
    Inv.RefreshWorn(ply)
    ply.MCCAmmoMirror = nil
    ply.MCCInvOpen = nil
    Inv.Save(ply)

    -- what the default death would have done besides the ragdoll
    ply:AddDeaths(1)
    if IsValid(attacker) and attacker:IsPlayer() and attacker ~= ply then attacker:AddFrags(1) end
    return true
end)

-- Leaving the server: everything but the pouch stays behind as a lootable body where the player stood
-- (mcc_inv_leave_body), or is gone. The pouch (Alpha Container) is saved for next time.
function Inv.LeaveBehind(ply)
    local inv = Inv.Get(ply)
    if ply:Alive() then Inv.StampWeapons(ply) end
    local keep = inv.slots.pouch
    inv.slots.pouch = nil
    if next(inv.slots) and ply:Alive() and MCC.Config.Get("inv_leave_body") then
        local rag = MakeRagdoll(ply)
        if IsValid(rag) then
            Inv.MakeBody(rag, inv, ply:Nick() .. " (left)")
        else
            local box = ents.Create("prop_physics")
            if IsValid(box) then
                box:SetModel("models/props_c17/SuitCase001a.mdl")
                box:SetPos(ply:GetPos() + Vector(0, 0, 16))
                box:Spawn()
                Inv.MakeBody(box, inv, ply:Nick() .. " (left)")
            end
        end
    end
    ply.MCCInv = {slots = {pouch = keep}}
    ply.MCCInvOpen = nil
end

-- NPC bodies ----------------------------------------------------------------------------------
-- NPCs get server-side ragdolls (ai_serverragdolls 1) so their bodies can hold loot. The body gets
-- the same slots as a player: the NPC's gun in its slot with a partly used magazine, and spare
-- magazines or loose rounds in the pockets. Expansions (ZBase factions) change it with
-- hook.Add("MCC_NPCBody", id, function(npc, inv, weaponClass) ... end).

local SF_NPC_NO_WEAPON_DROP = 8192

local function NPCBodiesOn()
    return Inv.Enabled() and MCC.Config.Get("inv_npc_bodies")
end

hook.Add("MCC_Ready", "MCC_InvNPCRagdolls", function()
    if NPCBodiesOn() then RunConsoleCommand("ai_serverragdolls", "1") end
end)

-- The body keeps the gun, so the NPC doesn't also drop it.
hook.Add("OnEntityCreated", "MCC_InvNPCNoDrop", function(ent)
    if not ent:IsNPC() then return end
    timer.Simple(0, function()
        if IsValid(ent) and NPCBodiesOn() then
            ent:SetKeyValue("spawnflags", tostring(bit.bor(ent:GetSpawnFlags(), SF_NPC_NO_WEAPON_DROP)))
        end
    end)
end)

-- Remember the NPC's gun while it's alive; by the time the ragdoll exists it may be gone.
hook.Add("EntityTakeDamage", "MCC_InvNPCWeapon", function(ent)
    if not ent:IsNPC() then return end
    local w = ent:GetActiveWeapon()
    if IsValid(w) then
        ent.MCCWeapon = w
        ent.MCCWeaponClass = w:GetClass()
    end
end)

-- The name on an NPC's body: its own (npc.MCCName, set by expansions such as Contracts) or its class's.
local function NPCName(npc)
    if isstring(npc.MCCName) and npc.MCCName ~= "" then return npc.MCCName end
    local entry = list.Get("NPC")[npc:GetClass()]
    return entry and entry.Name or npc:GetClass()
end

-- The loot a dead NPC carries.
function Inv.NPCLoadout(weaponClass)
    local inv = {slots = {}}
    local id = weaponClass and MCC.Items.FromClass(weaponClass)
    local def = id and MCC.Items.Get(id)
    if not def or def.kind ~= "weapon" then return inv end

    local d = def.data
    local maxClip = d.clip or 0
    local wit = Inv.NewItem(id, 1)
    if maxClip > 1 then wit.d = {clip = math.random(math.floor(maxClip * 0.3), maxClip)} end
    for _, key in ipairs(Inv.WeaponSlots) do
        if Inv.SlotAccepts(key, def) then
            inv.slots[key] = wit
            break
        end
    end

    local pocket = 1
    if d.feed == "mag" and d.mag and MCC.Items.Get(d.mag) then
        local cap = MCC.Items.Get(d.mag).data.cap or maxClip
        for _ = 1, math.random(1, 2) do
            inv.slots["pocket" .. pocket] = Inv.NewItem(d.mag, 1, {rounds = math.random(math.floor(cap * 0.4), cap)})
            pocket = pocket + 1
        end
    elseif d.ammo and Inv.AmmoItem[d.ammo] then
        local ammoDef = MCC.Items.Get(Inv.AmmoItem[d.ammo])
        local n = math.max(1, math.random(math.ceil(ammoDef.maxStack * 0.2), math.ceil(ammoDef.maxStack * 0.6)))
        inv.slots["pocket" .. pocket] = Inv.NewItem(Inv.AmmoItem[d.ammo], n)
    end
    return inv
end

hook.Add("CreateEntityRagdoll", "MCC_InvNPCBody", function(owner, rag)
    if not NPCBodiesOn() or not IsValid(owner) or not owner:IsNPC() or not IsValid(rag) then return end

    local class = owner.MCCWeaponClass
    local w = owner:GetActiveWeapon()
    if IsValid(w) then class = w:GetClass() end
    -- if the engine dropped the gun anyway, the body has it now
    for _, dropped in ipairs({owner.MCCWeapon, w}) do
        if IsValid(dropped) and not IsValid(dropped:GetOwner()) then dropped:Remove() end
    end

    local inv = Inv.NPCLoadout(class)
    hook.Run("MCC_NPCBody", owner, inv, class)
    Inv.MakeBody(rag, inv, NPCName(owner))
end)
