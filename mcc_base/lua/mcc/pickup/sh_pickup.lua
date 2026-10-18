-- Pickup and drop: weapons and items are picked up with E (walking over them does nothing),
-- and the active weapon is dropped with a rebindable key (default G) or the mcc_drop command.
--
-- Hooks for the inventory and expansions:
--   MCC_IsPickup(ent)               -> return "weapon" / "item" / a custom kind to make ent pickable
--   MCC_PickupWeapon(ply, wep)      -> return true if you handled it (e.g. moved it into the inventory)
--   MCC_PickupItem(ply, ent)        -> same, for items
--   MCC_CanDropWeapon(ply, wep)     -> return false to block a drop
--   MCC_DropWeapon(ply, wep)        -> return true if you handled the drop yourself

MCC.Pickup = MCC.Pickup or {}

MCC.Config.Define("pickup_use", true, "Pick up weapons with E instead of walking over them.")
MCC.Config.Define("pickup_items_use", true, "Pick up item_* entities (ammo, health, batteries) with E only.")
MCC.Config.Define("pickup_range", 100, "How far away E reaches for pickups, in units.", 40, 300)
MCC.Config.Define("drop_enabled", true, "Let players drop their active weapon (drop key or mcc_drop).")
MCC.Config.Define("drop_blacklist", "weapon_physgun,weapon_physcannon,gmod_tool,gmod_camera,weapon_fists,none",
    "Comma-separated weapon classes that can never be dropped.")

-- Your friend's Tarkov Inventory does its own E pickup; MCC stands down while it's installed.
MCC.Compat.Register("tarkov_inventory", {
    name = "Tarkov Inventory",
    detect = function() return istable(TK) and istable(TK.Config) and TK.Config.OpenKey ~= nil end,
})

-- True when MCC's own pickup rules are in charge.
function MCC.Pickup.Active()
    return MCC.Config.Get("pickup_use") and not MCC.Compat.Has("tarkov_inventory")
end

local function IsWorldItem(class)
    return string.sub(class, 1, 5) == "item_"
        and not string.find(class, "crate", 1, true)
        and not string.find(class, "charger", 1, true)
end

-- Returns "weapon", "item", a custom kind from MCC_IsPickup, or nil.
function MCC.Pickup.Kind(ent)
    if not IsValid(ent) then return nil end
    local custom = hook.Run("MCC_IsPickup", ent)
    if custom then return custom end
    if ent:IsWeapon() then
        if IsValid(ent:GetOwner()) then return nil end -- someone is holding it
        return "weapon"
    end
    if IsWorldItem(ent:GetClass()) then return "item" end
    return nil
end

-- The pickup the player is aiming at. Forgiving: if the trace just misses a small item,
-- the closest pickup within a few units of where it landed counts.
function MCC.Pickup.FindTarget(ply)
    local range = MCC.Config.Get("pickup_range")
    local start = ply:GetShootPos()
    local tr = util.TraceLine({
        start = start,
        endpos = start + ply:GetAimVector() * range,
        filter = ply,
        mask = MASK_SHOT,
    })

    local kind = MCC.Pickup.Kind(tr.Entity)
    if kind then return tr.Entity, kind end

    local best, bestKind, bestDist
    for _, e in ipairs(ents.FindInSphere(tr.HitPos, 24)) do
        local k = MCC.Pickup.Kind(e)
        if k then
            local d = e:GetPos():DistToSqr(tr.HitPos)
            if not best or d < bestDist then best, bestKind, bestDist = e, k, d end
        end
    end
    if best and start:Distance(best:GetPos()) <= range + 24 then return best, bestKind end
    return nil
end

-- Display name: the item registry's name if the class is registered, else the entity's own.
function MCC.Pickup.Name(ent)
    if ent:GetNWBool("MCCBody") then return ent:GetNWString("MCCName", "Body") end
    local id = ent.GetItemID and ent:GetItemID() or MCC.Items.FromClass(ent:GetClass())
    local def = id and MCC.Items.Get(id)
    if def then return MCC.Items.DisplayName(def) end
    if ent.GetPrintName then
        local n = ent:GetPrintName()
        if n and n ~= "" then return language and language.GetPhrase(n) or n end
    end
    return ent:GetClass()
end

-- Prompt text and an optional smaller line under it, e.g. "Pick up SMG", or "Loot Body" over
-- "Combine Soldier". Expansions can override with MCC_PickupPrompt(ent, kind) -> text, subtext.
function MCC.Pickup.PromptText(ent, kind)
    local custom, sub = hook.Run("MCC_PickupPrompt", ent, kind)
    if custom then return custom, sub end
    local name = MCC.Pickup.Name(ent)
    if kind == "body" then
        -- a looted body counting down to despawning (mcc_inv_body_cleanup)
        local at = ent.GetNWFloat and ent:GetNWFloat("MCCDespawnAt", 0) or 0
        if at > 0 then
            local left = math.max(0, math.ceil(at - CurTime()))
            name = string.format("%s  (despawns in %d:%02d)", name, math.floor(left / 60), left % 60)
        end
        return "Loot Body", name
    end
    local n = ent.GetCount and ent:GetCount() or 1
    if n > 1 then name = name .. " (" .. n .. ")" end
    return "Pick up " .. name
end

local blacklistStr, blacklist = nil, {}
function MCC.Pickup.IsNoDrop(wep)
    local str = MCC.Config.Get("drop_blacklist")
    if str ~= blacklistStr then
        blacklistStr, blacklist = str, {}
        for class in string.gmatch(str, "[^,%s]+") do blacklist[class] = true end
    end
    return blacklist[wep:GetClass()] or wep.MCCNoDrop == true
end
