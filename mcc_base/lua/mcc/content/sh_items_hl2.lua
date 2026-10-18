-- Default content: Half-Life 2 weapons, ammo, magazines, consumables and starter gear.
-- Registered through the same public hook any expansion uses. Server owners can change or
-- remove any of these with data/mcc/items.json or mcc_item_set.
--
-- Prices are in Supply. For stackable items (ammo, resources) the price is per unit.
-- Weapon data.feed: "mag" (uses magazine items), "tube" and "cylinder" (loaded round by round),
-- "single" (one round at a time).

hook.Add("MCC_RegisterItems", "mcc_hl2", function(Items)
    local R = Items.Register

    -- Weapons ------------------------------------------------------------------------
    R("weapon_pistol", {name = "9mm Pistol", kind = "weapon", class = "weapon_pistol", w = 2, h = 1,
        weight = 0.9, price = 300, model = "models/weapons/w_pistol.mdl", rarity = "common",
        data = {clip = 18, slot = "holster", ammo = "Pistol", feed = "mag", mag = "mag_pistol"}})
    R("weapon_357", {name = ".357 Magnum", kind = "weapon", class = "weapon_357", w = 2, h = 1,
        weight = 1.1, price = 700, model = "models/weapons/w_357.mdl", rarity = "uncommon",
        data = {clip = 6, slot = "holster", ammo = "357", feed = "cylinder"}})
    R("weapon_smg1", {name = "SMG", kind = "weapon", class = "weapon_smg1", w = 3, h = 2,
        weight = 2.9, price = 900, model = "models/weapons/w_smg1.mdl", rarity = "common",
        data = {clip = 45, slot = "primary", ammo = "SMG1", feed = "mag", mag = "mag_smg1"}})
    R("weapon_ar2", {name = "Pulse Rifle", kind = "weapon", class = "weapon_ar2", w = 5, h = 2,
        weight = 3.8, price = 1800, model = "models/weapons/w_irifle.mdl", rarity = "rare",
        data = {clip = 30, slot = "primary", ammo = "AR2", feed = "mag", mag = "mag_ar2"}})
    R("weapon_shotgun", {name = "Shotgun", kind = "weapon", class = "weapon_shotgun", w = 5, h = 1,
        weight = 3.4, price = 1100, model = "models/weapons/w_shotgun.mdl", rarity = "uncommon",
        data = {clip = 6, slot = "primary", ammo = "Buckshot", feed = "tube"}})
    R("weapon_crossbow", {name = "Crossbow", kind = "weapon", class = "weapon_crossbow", w = 5, h = 2,
        weight = 3.0, price = 1500, model = "models/weapons/w_crossbow.mdl", rarity = "rare",
        data = {clip = 1, slot = "primary", ammo = "XBowBolt", feed = "single"}})
    R("weapon_rpg", {name = "RPG", kind = "weapon", class = "weapon_rpg", w = 5, h = 2,
        weight = 6.3, price = 4000, model = "models/weapons/w_rocket_launcher.mdl", rarity = "epic",
        data = {clip = 1, slot = "primary", ammo = "RPG_Round", feed = "single"}})
    R("weapon_frag", {name = "Frag Grenade", kind = "weapon", class = "weapon_frag", w = 1, h = 1,
        weight = 0.6, price = 150, model = "models/weapons/w_grenade.mdl", rarity = "uncommon",
        data = {slot = "grenade", ammo = "Grenade"}})
    R("weapon_crowbar", {name = "Crowbar", kind = "weapon", class = "weapon_crowbar", w = 3, h = 1,
        weight = 1.0, price = 50, model = "models/weapons/w_crowbar.mdl", rarity = "common",
        data = {slot = "melee"}})
    R("weapon_stunstick", {name = "Stunstick", kind = "weapon", class = "weapon_stunstick", w = 2, h = 1,
        weight = 1.0, price = 250, model = "models/weapons/w_stunbaton.mdl", rarity = "uncommon",
        data = {slot = "melee"}})

    -- Loose ammo (price per round) ---------------------------------------------------
    R("ammo_pistol", {name = "9mm Rounds", kind = "ammo", class = "Pistol", w = 1, h = 1, maxStack = 50,
        weight = 0.012, price = 2, model = "models/items/boxsrounds.mdl", data = {ammo = "Pistol"}})
    R("ammo_smg1", {name = "4.6mm Rounds", kind = "ammo", class = "SMG1", w = 1, h = 1, maxStack = 50,
        weight = 0.012, price = 3, model = "models/items/boxmrounds.mdl", data = {ammo = "SMG1"}})
    R("ammo_ar2", {name = "Pulse Cartridges", kind = "ammo", class = "AR2", w = 1, h = 1, maxStack = 50,
        weight = 0.015, price = 5, model = "models/items/combine_rifle_cartridge01.mdl", rarity = "uncommon",
        data = {ammo = "AR2"}})
    R("ammo_buckshot", {name = "12 Gauge Shells", kind = "ammo", class = "Buckshot", w = 1, h = 1, maxStack = 20,
        weight = 0.035, price = 6, model = "models/items/boxbuckshot.mdl", data = {ammo = "Buckshot"}})
    R("ammo_357", {name = ".357 Rounds", kind = "ammo", class = "357", w = 1, h = 1, maxStack = 24,
        weight = 0.02, price = 10, model = "models/items/357ammo.mdl", rarity = "uncommon", data = {ammo = "357"}})
    R("ammo_xbowbolt", {name = "Crossbow Bolts", kind = "ammo", class = "XBowBolt", w = 1, h = 2, maxStack = 10,
        weight = 0.1, price = 25, model = "models/items/crossbowrounds.mdl", rarity = "uncommon",
        data = {ammo = "XBowBolt"}})
    R("ammo_rpg", {name = "RPG Rocket", kind = "ammo", class = "RPG_Round", w = 2, h = 1, maxStack = 1,
        weight = 2.0, price = 400, model = "models/weapons/w_missile_closed.mdl", rarity = "rare",
        data = {ammo = "RPG_Round"}})
    R("ammo_smg1_grenade", {name = "SMG Grenade", kind = "ammo", class = "SMG1_Grenade", w = 1, h = 1, maxStack = 5,
        weight = 0.2, price = 150, model = "models/items/ar2_grenade.mdl", rarity = "rare",
        data = {ammo = "SMG1_Grenade"}})
    R("ammo_ar2altfire", {name = "Energy Ball", kind = "ammo", class = "AR2AltFire", w = 1, h = 1, maxStack = 3,
        weight = 0.3, price = 300, model = "models/items/combine_rifle_ammo01.mdl", rarity = "epic",
        data = {ammo = "AR2AltFire"}})

    -- Magazines (for data.feed = "mag" weapons). Rounds are kept per magazine in item.d.rounds.
    R("mag_pistol", {name = "Pistol Magazine (18)", kind = "mag", w = 1, h = 1, weight = 0.1, price = 40,
        model = "models/items/boxsrounds.mdl", data = {ammo = "Pistol", cap = 18}})
    R("mag_smg1", {name = "SMG Magazine (45)", kind = "mag", w = 1, h = 2, weight = 0.2, price = 60,
        model = "models/items/boxmrounds.mdl", data = {ammo = "SMG1", cap = 45}})
    R("mag_ar2", {name = "Pulse Magazine (30)", kind = "mag", w = 1, h = 2, weight = 0.25, price = 90,
        model = "models/items/combine_rifle_cartridge01.mdl", rarity = "uncommon", data = {ammo = "AR2", cap = 30}})

    -- Consumables ---------------------------------------------------------------------
    R("item_healthkit", {name = "Medkit", kind = "consumable", class = "item_healthkit", w = 2, h = 2,
        weight = 0.5, price = 150, model = "models/items/healthkit.mdl",
        data = {effect = "health", amount = 25, convar = "sk_healthkit"}})
    R("item_healthvial", {name = "Health Vial", kind = "consumable", class = "item_healthvial", w = 1, h = 1,
        weight = 0.1, price = 50, model = "models/healthvial.mdl",
        data = {effect = "health", amount = 10, convar = "sk_healthvial"}})
    R("item_battery", {name = "Suit Battery", kind = "consumable", class = "item_battery", w = 1, h = 2,
        weight = 0.3, price = 120, model = "models/items/battery.mdl",
        data = {effect = "armor", amount = 15, convar = "sk_battery"}})

    -- Starter gear (compartment layouts from the original Tarkov inventory addon) -----
    -- data.cells: each compartment is its own grid; x, y = where it's drawn, in cells.
    R("rig_chest", {name = "Chest Rig", kind = "gear", w = 3, h = 2, weight = 0.9, price = 450, rarity = "uncommon",
        model = "models/props_c17/BriefCase001a.mdl", data = {slot = "rig", cells = {
            {x = 0, y = 0, w = 1, h = 2}, {x = 1.1, y = 0, w = 1, h = 2},
            {x = 2.2, y = 0, w = 1, h = 2}, {x = 3.3, y = 0, w = 1, h = 2},
            {x = 0, y = 2.1, w = 1, h = 2}, {x = 1.1, y = 2.1, w = 1, h = 1},
            {x = 1.1, y = 3.2, w = 1, h = 1}, {x = 2.2, y = 2.1, w = 2, h = 2},
        }}})
    R("bp_daypack", {name = "Daypack", kind = "gear", w = 3, h = 3, weight = 0.7, price = 300,
        model = "models/props_c17/SuitCase001a.mdl", data = {slot = "backpack", cells = {
            {x = 0, y = 0, w = 5, h = 5},
        }}})
    R("bp_large", {name = "Tri-Zip", kind = "gear", w = 3, h = 3, weight = 1.4, price = 900, rarity = "rare",
        model = "models/props_c17/SuitCase001a.mdl", data = {slot = "backpack", cells = {
            {x = 0, y = 0, w = 6, h = 8},
        }}})
    R("dogtag", {name = "Dogtag", kind = "misc", w = 1, h = 1, maxStack = 1, weight = 0.02, price = 100,
        model = "models/props_lab/huladoll.mdl", tags = {"dogtag"}, data = {slot = "dogtag"}})

    -- Money: Tarkov's roubles, one stack up to 500,000 in a single square. Paid out by contracts (and traders,
    -- later). The model is an HL2 stand-in; mcc_item_set roubles model <path> swaps it.
    R("roubles", {name = "Roubles", kind = "misc", w = 1, h = 1, maxStack = 500000, weight = 0, price = 1,
        category = "money", model = "models/props_c17/paper01.mdl", tags = {"money"}})

    R("pouch_secure", {name = "Alpha Container", kind = "gear", w = 2, h = 2, weight = 0.3, rarity = "rare",
        model = "models/props_junk/cardboard_box004a.mdl", data = {slot = "pouch", keepOnDeath = true, cells = {
            {x = 0, y = 0, w = 2, h = 2},
        }}})
end)
