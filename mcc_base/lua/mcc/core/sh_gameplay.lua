-- Gameplay tweaks: hiding the kill feed, and a damage buff for HL2's own weapons.

MCC.Config.Define("hide_killfeed", true, "Hide the kill feed (death notices in the top right).")
MCC.Config.Define("hl2_damage_mult", 1.25, "Damage multiplier for HL2's weapons in players' hands (1 = stock).", 0, 10)
MCC.Config.Define("hl2_damage_mult_npc", 1, "Damage multiplier for HL2's weapons in NPCs' hands (1 = stock).", 0, 10)
MCC.Config.Define("hl2_damage_weapons", "weapon_pistol,weapon_357,weapon_smg1,weapon_ar2,weapon_shotgun,weapon_crossbow,weapon_crowbar,weapon_stunstick",
    "Weapons the HL2 damage multipliers apply to (comma separated classes).")

if CLIENT then
    hook.Add("DrawDeathNotice", "MCC_HideKillfeed", function()
        if MCC.Config.Get("hide_killfeed") then return false end
    end)
end

if SERVER then
    local listStr, list = nil, {}
    local function Listed(class)
        local s = MCC.Config.Get("hl2_damage_weapons")
        if s ~= listStr then
            listStr, list = s, {}
            for c in string.gmatch(s, "[^,%s]+") do list[c] = true end
        end
        return list[class]
    end

    -- bullets, buckshot, bolts and melee from a listed weapon (not its grenades or energy balls)
    local KINDS = bit.bor(DMG_BULLET, DMG_BUCKSHOT, DMG_CLUB, DMG_SLASH, DMG_NEVERGIB)

    function MCC.HL2DamageMult(attacker, dmg)
        if not IsValid(attacker) or not dmg.GetDamageType or not (attacker:IsPlayer() or attacker:IsNPC()) then return 1 end
        if bit.band(dmg:GetDamageType(), KINDS) == 0 or dmg:IsExplosionDamage() then return 1 end
        local w = attacker.GetActiveWeapon and attacker:GetActiveWeapon()
        if not IsValid(w) or not Listed(w:GetClass()) then return 1 end
        return MCC.Config.Get(attacker:IsPlayer() and "hl2_damage_mult" or "hl2_damage_mult_npc")
    end

    hook.Add("EntityTakeDamage", "MCC_HL2Damage", function(ent, dmg)
        local m = MCC.HL2DamageMult(dmg:GetAttacker(), dmg)
        if m ~= 1 then dmg:ScaleDamage(m) end
    end)
end
