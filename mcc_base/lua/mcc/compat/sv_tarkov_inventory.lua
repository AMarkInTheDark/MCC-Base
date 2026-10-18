-- While your friend's Tarkov Inventory addon is installed (before it's merged into MCC Base),
-- the drop key goes through its inventory so slots and saved state stay correct.

hook.Add("MCC_DropWeapon", "MCC_TarkovInventory", function(ply, wep)
    if not MCC.Compat.Has("tarkov_inventory") then return end
    if not (TK and TK.Get and TK.Drop and TK.Update) then return end

    local class = wep:GetClass()
    local inv = TK.Get(ply)
    for _, key in ipairs({"primary", "holster"}) do
        local it = inv.slots and inv.slots[key]
        if it and it.class == class then
            TK.Drop(ply, it.id)
            TK.Update(ply)
            return true
        end
    end

    -- Grenades are handed out from rig stock; dropping the weapon itself would desync it.
    if TK.Config.GrenadeAmmo and TK.Config.GrenadeAmmo[class] then return true end
end)
