-- Server side of pickup and drop.

local P = MCC.Pickup

-- Weapons created this recently were just Give()n (spawn menu, loadout, other addons), not
-- lying in the world, so they go straight to the player.
local FRESH_WEAPON_TIME = 0.1

function P.TakeWeapon(ply, wep)
    if hook.Run("MCC_PickupWeapon", ply, wep) == true then return true end
    ply.MCCAllowPickup = wep
    local ok = ply:PickupWeapon(wep)
    ply.MCCAllowPickup = nil
    return ok
end

-- HL2 items only give themselves on touch, so the item is briefly allowed and moved to the
-- player's feet (approach from the original Tarkov Inventory addon). If the player doesn't need it
-- (full health, say) it simply stays there.
function P.TakeItem(ply, ent)
    if hook.Run("MCC_PickupItem", ply, ent) == true then return true end
    ent.MCCAllowUntil = CurTime() + 0.4
    ent:SetPos(ply:GetPos() + Vector(0, 0, 10))
    return true
end

hook.Add("PlayerCanPickupWeapon", "MCC_NoAutoPickup", function(ply, wep)
    if ply.MCCInvGiving then return end -- the inventory equipping a weapon it already holds
    if not P.Active() then return end
    if ply.MCCAllowPickup == wep or ply.MCCPickupBypass then return end
    if CurTime() - wep:GetCreationTime() < FRESH_WEAPON_TIME then
        -- spawn-menu or loadout gives: the inventory may take the weapon into a slot or grid
        if hook.Run("MCC_PickupWeapon", ply, wep) == true then return false end
        return
    end
    return false
end)

hook.Add("PlayerCanPickupItem", "MCC_NoAutoPickupItems", function(ply, ent)
    if not P.Active() or not MCC.Config.Get("pickup_items_use") then return end
    if ply.MCCPickupBypass or (ent.MCCAllowUntil or 0) > CurTime() then return end
    return false
end)

hook.Add("KeyPress", "MCC_UsePickup", function(ply, key)
    if key ~= IN_USE or not P.Active() or not ply:Alive() then return end
    if (ply.MCCPickupCD or 0) > CurTime() then return end

    local ent, kind = P.FindTarget(ply)
    if not ent then return end
    ply.MCCPickupCD = CurTime() + 0.3

    if kind == "weapon" then
        P.TakeWeapon(ply, ent)
    elseif kind == "item" then
        if MCC.Config.Get("pickup_items_use") then P.TakeItem(ply, ent) end
    else
        hook.Run("MCC_PickupCustom", ply, ent, kind)
    end
end)

-- Lets other code hand a player weapons/items without the E rule getting in the way.
function P.Bypass(ply, fn)
    ply.MCCPickupBypass = true
    local ok, err = pcall(fn)
    ply.MCCPickupBypass = nil
    if not ok then MCC.Error("Pickup bypass failed: %s", tostring(err)) end
end

-- Dropping ---------------------------------------------------------------------------

function P.Drop(ply)
    if not IsValid(ply) or not ply:Alive() or not MCC.Config.Get("drop_enabled") then return false end
    if (ply.MCCDropCD or 0) > CurTime() then return false end
    ply.MCCDropCD = CurTime() + 0.4

    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or P.IsNoDrop(wep) then return false end
    if hook.Run("MCC_CanDropWeapon", ply, wep) == false then return false end
    if hook.Run("MCC_DropWeapon", ply, wep) == true then return true end

    ply:DropWeapon(wep, nil, ply:GetAimVector() * 250 + ply:GetVelocity())
    return true
end

-- Clients send this from their drop key; it can also be bound directly: bind g mcc_drop
concommand.Add("mcc_drop", function(ply) P.Drop(ply) end, nil, "Drop your active weapon.")

-- In singleplayer GMod runs key hooks only on the server, so the drop key is caught here.
hook.Add("PlayerButtonDown", "MCC_DropKeySP", function(ply, button)
    if not game.SinglePlayer() or ply:IsTyping() then return end
    local key = ply:GetInfoNum("mcc_drop_key", KEY_G)
    if key ~= 0 and button == key then P.Drop(ply) end
end)
