-- Extraction: take some gear out of a session and bring it into the next one.
--
--   1. Craft an Extraction Crate at the JMod workbench (5x5, limited weapons and resources).
--   2. Fill it, then craft a Fulton: it's equipment, like a grenade. Carried in your rig, pockets or a
--      special slot it gives you the Fulton SWEP (one charge per Fulton carried). Aim at the crate and
--      left-click: it needs open sky, the balloon inflates, the crate lifts and sways for a moment (a
--      rival can pop the balloon), then it's yanked into the sky. Whoever attached the Fulton owns the
--      crate. Each player stores up to 3; a 4th overwrites the oldest.
--      With the MGSV Fulton Recovery System addon installed (Workshop 876405188, by kipper) the balloon,
--      sounds and pop effect are MGSV's; without it, HL2 stand-ins.
--   3. Next session, craft a Signal Flare and throw it: your oldest stored crate parachutes onto it.
--      Everyone sees the drop, and anyone can loot it. A flare calls the thrower's own crates, so a
--      stolen flare only helps someone who has crates of their own.
--
-- Stored crates live in data/mcc/extraction/<steamid64>.json. Recipe costs: data/mcc/jmod_recipes.json.

MCC.Extract = MCC.Extract or {}
local X = MCC.Extract
local Inv = MCC.Inv

MCC.Config.Define("extract_enabled", true, "Extraction crates, the Fulton and signal flares.")
MCC.Config.Define("extract_max_crates", 3, "Crates each player can have stored; sending up another overwrites the oldest.", 1, 20)
MCC.Config.Define("extract_crate_w", 5, "Extraction crate grid width.", 1, 12)
MCC.Config.Define("extract_crate_h", 5, "Extraction crate grid height.", 1, 12)
MCC.Config.Define("extract_max_weapons", 2, "Weapons an extraction crate can hold (0 = none, -1 = no limit).", -1, 50)
MCC.Config.Define("extract_max_resources", 300, "JMod resource units an extraction crate can hold (-1 = no limit).", -1, 100000)
MCC.Config.Define("extract_mgsv_swep_admin", true, "With the MGSV Fulton addon installed, only admins can spawn its own Fulton SWEP (it extracts anything).")
MCC.Config.Define("extract_fulton_hover", 1, "Seconds the crate hovers before the Fulton yanks it up (the balloon can be popped).", 0, 10)
MCC.Config.Define("extract_drop_delay", 15, "Seconds between throwing a signal flare and the crate landing.", 0, 300)
MCC.Config.Define("extract_marker_time", 90, "Seconds everyone sees a dropped crate on their HUD (until it's first opened).", 0, 900)

X.CRATE_CLASS = "mcc_extract_crate"
X.FULTON_CLASS = "mcc_fulton" -- the SWEP (lua/weapons/mcc_fulton.lua), the item and its ammo type
X.MGSV_WORKSHOP = "876405188"
X.MGSV_MODEL = "models/mgsv/items/fulton.mdl"

-- The Fulton's charges are an ammo type the inventory mirrors from the Fultons you carry (like grenades).
if game and game.AddAmmoType then
    game.AddAmmoType({name = X.FULTON_CLASS, dmgtype = DMG_GENERIC or 0, tracer = TRACER_NONE or 0, maxcarry = 9999})
end
if CLIENT and language and language.Add then language.Add(X.FULTON_CLASS .. "_ammo", "Fulton") end

-- MGSV Fulton Recovery System (Steam Workshop 876405188, by kipper): its balloon model, sounds and effect.
MCC.Compat.Register("mgsv_fulton", {
    name = "MGSV Fulton Recovery System",
    detect = function() return file.Exists(X.MGSV_MODEL, "GAME") end,
})

function X.MGSV()
    return MCC.Compat.Has("mgsv_fulton")
end

function X.Enabled()
    return MCC.Config.Get("extract_enabled")
end

function X.IsCrate(ent)
    return IsValid(ent) and ent:GetClass() == X.CRATE_CLASS
end

hook.Add("MCC_RegisterItems", "MCC_Extract", function(Items)
    -- Equipment: carried in the rig, pockets or a special slot, each one is a charge of the Fulton SWEP.
    Items.Register("mcc_fulton", {
        name = "Fulton Recovery Device", kind = "weapon", class = X.FULTON_CLASS, w = 1, h = 1, weight = 1.5,
        rarity = "rare", model = "models/weapons/w_package.mdl", category = "extraction", tags = {"special"},
        data = {slot = "grenade", ammo = X.FULTON_CLASS,
            desc = "Equipment. Carry it in your rig, pockets or a special slot to get the Fulton. Aim at an "
                .. "Extraction Crate with open sky above it and left-click to send it up. The crate hangs under "
                .. "the balloon for a moment before it's pulled away; shooting the balloon drops it. "
                .. "You'll own the crate next session."},
    })
    Items.Register("mcc_flare", {
        name = "Signal Flare", kind = "consumable", w = 1, h = 1, weight = 0.3, rarity = "uncommon",
        model = "models/props_junk/flare.mdl", category = "extraction",
        data = {effect = "flare", useLabel = "Throw",
            desc = "Throw it where you want your oldest stored crate to land. Everyone can see the drop. "
                .. "Keep it in your Alpha Container or you'll lose it when you die."},
    })
end)

-- Weapons and JMod resource units in a list of items (and anything packed inside them).
function X.Tally(list, skip, acc)
    acc = acc or {weapons = 0, resources = 0}
    for _, o in ipairs(list or {}) do
        if o ~= skip then
            local def = Inv.Def(o)
            if def then
                if def.kind == "weapon" then acc.weapons = acc.weapons + 1 end
                if def.data.jmod and Inv.ResourceAmount then acc.resources = acc.resources + Inv.ResourceAmount(o) end
            end
            for _, sub in ipairs(o.cont or {}) do X.Tally(sub, skip, acc) end
        end
    end
    return acc
end

-- Can `it` go into this crate? false + reason when it would break a limit.
function X.CanStore(crate, it)
    local have = {weapons = 0, resources = 0}
    for _, g in ipairs(crate.MCCCont and crate.MCCCont.grids or {}) do X.Tally(g.items, it, have) end
    local add = X.Tally({it})
    local maxW, maxR = MCC.Config.Get("extract_max_weapons"), MCC.Config.Get("extract_max_resources")
    if maxW >= 0 and add.weapons > 0 and have.weapons + add.weapons > maxW then
        return false, maxW == 0 and "Weapons can't go in an extraction crate"
            or string.format("An extraction crate holds at most %d weapon%s", maxW, maxW == 1 and "" or "s")
    end
    if maxR >= 0 and add.resources > 0 and have.resources + add.resources > maxR then
        return false, string.format("An extraction crate holds at most %d resources (%d in it)", maxR, have.resources)
    end
    return true
end

-- E opens an extraction crate like any container.
hook.Add("MCC_IsPickup", "MCC_Extract", function(ent)
    if X.IsCrate(ent) and Inv.Enabled() and not ent:GetNWBool("MCCLifting") then return "container" end
end)
