-- FOBs: forward operating bases, run like Rust's tool cupboard.
--
-- Craft a FOB Kit at the JMod workbench and deploy it from your inventory (admins can also spawn an
-- Admin FOB from the spawn menu for testing). The FOB core has health (1000 at tier 1) and a zone around
-- it; only members build there. Props and Builder Tablet pieces in the zone belong to the FOB.
--
-- Stash: E on the core opens its stash in the inventory window, a grid (bigger each tier) you drag
-- anything into and out of. The JMod resource boxes in it are what the FOB pays with (Deposit in its
-- menu, or pushing JMod boxes into the core, puts them there too).
--
-- Upkeep: every 30 minutes it pays the upkeep of the core's tier and of every piece, each in its own
-- resource (twig and wood in wood, stone in concrete, sheet metal in steel, armored in titanium...),
-- out of the stash. Whatever it can't pay for decays: each piece over its tier's decay time (twig 1
-- hour ... armored 12 hours), the core over mcc_fob_core_decay_hours. Put the missing resource in the
-- stash and upkeep is paid straight away.
--
-- The owner adds members. When the owner leaves, the FOB passes to an online member, or is abandoned
-- and anyone can claim it by holding the core.
--
-- Data files: data/mcc/fob_tiers.json (tiers), data/mcc/fob_storage.json (what it stores, food values).

MCC.FOB = MCC.FOB or {}
local F = MCC.FOB

F.CLASS = "mcc_fob"
F.MODEL = "models/props_silo/silo_launchroom_monitor.mdl"

MCC.Config.Define("fob_enabled", true, "Players can deploy FOBs.")
MCC.Config.Define("fob_max_per_player", 1, "FOBs one player can own (admin FOBs don't count).", 1, 10)
MCC.Config.Define("fob_deploy_range", 200, "How far away you can place a FOB core.", 64, 600)
MCC.Config.Define("fob_core_model", F.MODEL, "Model of the FOB core.")
MCC.Config.Define("fob_upkeep_interval", 1800, "Seconds between upkeep payments (Rust-style: 30 minutes).", 10, 86400)
MCC.Config.Define("fob_core_decay_hours", 12, "Hours an unpaid FOB core takes to decay from full health to nothing.", 0.01, 1000)
MCC.Config.Define("fob_repair_rate", 5, "Percent of max health the core repairs per minute while its upkeep is paid.", 0, 100)
MCC.Config.Define("fob_bullet_mult", 0.25, "Bullet damage to FOB props and the core (explosives do full damage).", 0, 10)
MCC.Config.Define("fob_claim_time", 10, "Seconds to claim an abandoned FOB.", 0, 300)
MCC.Config.Define("fob_prop_hp_scale", 5, "Health per unit of size (cube root of volume) for ordinary props in a FOB.", 0.1, 100)
MCC.Config.Define("fob_prop_hp_min", 50, "Least health an ordinary FOB prop gets.", 1, 100000)
MCC.Config.Define("fob_prop_hp_max", 3000, "Most health an ordinary FOB prop gets.", 1, 100000)
MCC.Config.Define("fob_prop_tier", "wood", "Building tier whose upkeep and decay ordinary props in a FOB use.")
MCC.Config.Define("fob_admin_stock", 500, "Units of each building resource an Admin FOB starts with.", 0, 100000)
MCC.Config.Define("fob_drop_stores", true, "A destroyed or packed-up FOB drops everything in its stash.")
MCC.Config.Define("fob_admin_stash_w", 16, "Width of an Admin FOB's stash grid.", 1, 20)
MCC.Config.Define("fob_admin_stash_h", 14, "Height of an Admin FOB's stash grid.", 1, 20)

-- Tiers. health = core max health; radius = zone; stash = its grid (w x h cells);
-- maxProps = props it holds; upkeep = resources per upkeep period; upgradeCost = to reach this tier.
F.DEFAULT_TIERS = {
    {name = "Outpost", health = 1000, radius = 1024, stash = {w = 8, h = 10}, maxProps = 60,
        upkeep = {["wood"] = 10}},
    {name = "Forward Base", health = 2500, radius = 1536, stash = {w = 10, h = 12}, maxProps = 120,
        upkeep = {["wood"] = 15, ["steel"] = 10},
        upgradeCost = {["wood"] = 300, ["steel"] = 200, ["basic parts"] = 100}},
    {name = "Stronghold", health = 5000, radius = 2048, stash = {w = 12, h = 14}, maxProps = 200,
        upkeep = {["concrete"] = 20, ["steel"] = 20},
        upgradeCost = {["concrete"] = 500, ["steel"] = 400, ["precision parts"] = 50}},
}

-- JMod resources the core takes from JMod (pushed boxes, Deposit), and what counts as food (points per
-- unit) for traders and friendly NPCs. The stash itself takes any item dragged into it.
F.DEFAULT_STORAGE = {
    accepts = {"wood", "concrete", "steel", "titanium", "aluminum", "copper", "lead", "ceramic", "glass",
        "plastic", "rubber", "cloth", "paper", "sand", "basic parts", "precision parts",
        "organics", "nutrients", "water"},
    food = {["organics"] = 1, ["nutrients"] = 3, ["water"] = 0.5},
}

F.Tiers = F.Tiers or table.Copy(F.DEFAULT_TIERS)
F.Storage = F.Storage or table.Copy(F.DEFAULT_STORAGE)

function F.Enabled()
    return MCC.Config.Get("fob_enabled")
end

function F.Tier(core)
    return F.Tiers[core:GetTier()] or F.Tiers[1]
end

function F.All()
    return ents.FindByClass(F.CLASS)
end

-- The FOB whose zone pos is in (nil if none).
function F.At(pos)
    for _, core in ipairs(F.All()) do
        if IsValid(core) and pos:Distance(core:GetPos()) <= core:GetRadius() then return core end
    end
end

-- A zone where enemies and missions shouldn't spawn: an owned FOB's (abandoned ones don't protect).
function F.InSafeZone(pos)
    local core = F.At(pos)
    return core and not core:GetAbandoned() and core or nil
end

function F.IsMember(core, ply)
    if not IsValid(core) or not IsValid(ply) then return false end
    local sid = ply:SteamID64()
    return core:GetOwnerID() == sid or string.find(core:GetNWString("MCCMembers", ","), "," .. sid .. ",", 1, true) ~= nil
end

-- Who may build in, move and change a FOB's props and open its stash: members, anyone once it's
-- abandoned, superadmins.
function F.CanModify(core, ply)
    if not IsValid(core) then return true end
    if IsValid(ply) and ply.IsSuperAdmin and ply:IsSuperAdmin() then return true end
    return core:GetAbandoned() or F.IsMember(core, ply)
end

hook.Add("MCC_RegisterItems", "MCC_FOB", function(Items)
    Items.Register("mcc_fob_kit", {
        name = "FOB Kit", kind = "consumable", w = 2, h = 2, weight = 8, rarity = "rare",
        model = "models/props_lab/citizenradio.mdl", category = "fob",
        data = {effect = "fob_deploy", useLabel = "Deploy FOB",
            desc = "Look at flat ground and deploy to set up a Forward Operating Base. Build in its zone with the "
                .. "Builder Tablet, and keep its stash stocked with JMod resources so its upkeep is paid."},
    })
end)

-- Protection: only members build in or change a FOB (shared so the physgun doesn't stutter on clients).
local function Guard(ply, ent)
    if not IsValid(ent) then return end
    local core = ent:GetNWEntity("MCCFob")
    if ent:GetClass() == F.CLASS then core = ent end
    if IsValid(core) and not F.CanModify(core, ply) then return false end
end

hook.Add("PhysgunPickup", "MCC_FOB", Guard)
hook.Add("GravGunPickupAllowed", "MCC_FOB", Guard)
hook.Add("GravGunPunt", "MCC_FOB", Guard)
hook.Add("CanPlayerUnfreeze", "MCC_FOB", function(ply, ent) return Guard(ply, ent) end)
hook.Add("CanProperty", "MCC_FOB", function(ply, prop, ent) return Guard(ply, ent) end)
hook.Add("CanTool", "MCC_FOB", function(ply, tr, tool)
    if tr and IsValid(tr.Entity) then return Guard(ply, tr.Entity) end
end)
