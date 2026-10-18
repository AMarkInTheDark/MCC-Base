# MCC Base

Core addon for the MCC-style FOB mod for Garry's Mod (Sandbox). Expansion addons (ZBase support,
custom weapon bases, events) build on it through hooks and never edit its files.

**0.17.0:** the generic Scav Vest (`rig_scav`) is gone; MCC Gear's Scav Vest (`rig_scav_vest`) replaces it. Saved ones
(inventories, extraction crates) load as Gear's, keeping what fits its pockets; without MCC Gear they're dropped.
`Inv.Renamed` maps retired item ids to their replacements.

**0.16.0 (performance):** bodies' ragdolls freeze once they've settled (`mcc_inv_body_freeze`, 10 s after death;
0 = never), and the body cap defaults to 30 (`mcc_inv_body_max`; servers keep what they set). Bodies further away than
`mcc_worn_body_distance` (each player's own, 1500; Q menu > Utilities > MCC > Inventory) don't build their worn-gear models.
Inventory syncs send only the slots that changed. The worn-gear scan and supply-drop markers no longer walk every
ragdoll or crate several times a second, and ammo syncing uses an index of grenade items instead of the whole registry
(`MCC.Items.GrenadeDefs()`).

**0.15.1:** grenades a weapon holds "in hand" (ARC9 keeps one in the clip and draws it from the reserve when you
equip it) count toward what you carry. Before, drawing one counted as a throw and deleted the item, so the last
grenade vanished as soon as you equipped it.

**0.15.0:** dogtags record who killed someone, with what weapon, and roughly when; the inspect window shows it
(Contracts adds the faction for NPC tags). New hook `MCC_BodyDespawn` (MCC Traders' Fence collects what's left on
bodies).

**0.14.0:** the Fulton is now equipment with its own SWEP: carried in the rig, pockets or a special slot, each
Fulton is a charge. With the MGSV Fulton Recovery System addon installed (Workshop 876405188), the balloon,
sounds and pop are MGSV's; the crate now lifts and swings under the balloon before the
yank. New hooks for expansions (MCC ARC9 uses them): `MCC_ItemIcon`, `MCC_ItemTooltip`, `MCC_InspectFill`,
`MCC_WeaponAmmo`, `MCC_MagFits`, `MCC_InventorySynced`.

**0.13.0:** a **Roubles** item (one stack holds 500,000; contracts pay in it, traders will), NPC bodies can carry
a name an expansion gives them (`npc.MCCName`), and item tooltips show an instance note (`it.d.note`).

**0.12.0:** the grid inventory with a Tarkov-style gear screen, HL2 magazines, containers,
lootable bodies and searching, JMod resources as items, extraction crates with the Fulton and flares,
FOBs that work like Rust's tool cupboard with a **stash you drag items into**, Rust building tiers with
the Builder Tablet and the new **Builder Hammer**, an Admin FOB, a range bubble, a Server Settings page,
and Esc closing every MCC window. NPC stealth and behaviors moved to their own expansion,
**MCC AI Behaviors** (`mcc_ai`), so this addon is just the core.

Expansions: **MCC AI Behaviors** (NPC stealth, behaviors, NPC FOB operations), **mcc_content_fortifications**
(the Builder Tablet's models). Each one is its own addon and needs this one installed.

JMod is optional but recommended. Without it MCC still runs; admins get a reminder on join
(turn it off with `mcc_compat_notice 0`).

## Controls
| Key | Does |
| --- | --- |
| **E** | Pick up the weapon or item you're looking at. Walking over them does nothing |
| **G** | Drop your active weapon (as an item, magazine included). Rebind in Q menu > Utilities > MCC > Controls, or `bind <key> mcc_drop` |
| **I** | Open or close the inventory (**Esc** and **Tab** close it too; Esc closes an inspect window first). Rebind in Q menu > Utilities > MCC > Inventory, or `bind <key> mcc_inventory` |
| **E** on a body or container | Loot it (it opens on the right, with the same layout as your gear) |
| **E** on your FOB core | Open its stash (same screen) |
| **Esc** | Closes the MCC window on top (inspect window, confirm box, FOB menu, build menus, inventory) instead of opening the pause menu |

In the inventory: drag with the left mouse button, **R** rotates while dragging, **Ctrl+click**
quick-moves, **Alt+click** equips, **right-click** for Inspect / Use / Load / Unload / Split stack / Equip / Drop.
**Inspect** opens an examine window: drag the model to rotate it, mouse wheel to zoom, double-click to
reset. It shows the item's stats (damage, fire rate, loaded rounds, caliber, attachments for weapons;
rounds and fitting guns for magazines; capacity and contents for gear), its details and description,
with Use/Load, Quick move and Drop buttons.
The right column, **IN THE VICINITY**, lists items, bodies and containers near you: drag items into
your gear, Ctrl+click to take, click a body or container to search it, drag your own items onto the
list to drop them, or onto a **container in the list** (a crate, a locker) to put them in it, whether
they're yours or lying on the ground nearby (they go in the first free spot).

The physgun, gravity gun, toolgun and camera can't be dropped (`mcc_drop_blacklist`).
If the Tarkov Inventory addon is installed, it handles E pickup itself and the drop key goes
through its inventory slots.

## Inventory rules
- **Equipment slots** (as on Tarkov's gear screen): earpiece, headwear, face cover, armband, body armor,
  eyewear, dogtag, on sling, on back, holster, sheath, tactical rig, 4 pockets, 3 special slots, backpack, pouch.
- Only weapons in **on sling / on back / holster / sheath** are actually in your hands. Grids are storage.
- **Ammo and grenades in your rig, pockets and special slots are usable**; reloads and throws take from
  them. Ammo in the backpack is only carried.
- Stacks hold up to the item's max per cell (50 by default). Drop a stack on a matching stack to merge.
- **Magazines** (pistol, SMG, pulse rifle): the gun reloads from the fullest loaded magazine in your
  rig, pockets or special slots. A reload swaps magazines: the rounds left in the gun go back as a
  partly full magazine. Load magazines by dragging loose rounds onto them or right-click > Load;
  right-click > Unload empties one. You can also right-click a gun > Load from loose rounds to fill
  its own magazine directly. The .357, shotgun, crossbow and RPG load loose rounds.
  `mcc_mags_required 0` turns magazines off (every gun uses loose rounds).
  Loaded magazines can be spawned from the spawn menu: Entities > MCC Magazines.
- Empty bags can be packed inside other bags.
- **Searching** (as in Tarkov): what a body is wearing is visible straight away, but its pockets and
  the inside of each piece of gear (rig, backpack...) are closed, each with a **SEARCH** button; a
  container compartment (each of the four lockers) is its own closed section. Searching a section reveals its items one at a time as "?" boxes
  turn into items (bigger items take longer). Click several SEARCH buttons and they queue. You can't
  put items into a section you haven't searched. Each player searches for themselves; what you put
  in, you can always see.
  `mcc_search_enabled`, `mcc_search_time` (seconds for a 1x1 item, default 0.6).
- **Weapon packs** (ARC9, TFA, ArcCW, M9K...) are supported weapon by weapon: a gun is only an
  inventory item once it's registered (in its own addon with the `MCC_RegisterItems` hook, see below,
  or by the server owner in `data/mcc/items.json` / `mcc_item_addweapon`). That's where each gun gets
  its size, weight, slot, caliber and price, and the pack's ammo types get their own ammo items.
  Guns that aren't registered are picked up normally and stay outside the inventory, and NPCs
  carrying them don't drop them as loot.
  A gun's state (attachments, fire mode, loaded rounds...) is kept when it goes into your inventory
  and restored when it comes back out, by saving the weapon's network vars. `mcc_weapon_state 0`
  turns it off; `mcc_weapon_state_skip` lists name fragments not to save (timers and animation
  state). Bases that keep state elsewhere can add it with the `MCC_SaveWeaponState` hook.
- **Worn gear**: a rig, backpack, armor or headgear item with `data.worn` shows on whoever wears it
  (other players see it too) and stays on their body after death. `worn` is a model path, which is
  bonemerged onto the character's skeleton (how playermodel gear addons are made), or a table
  `{model, skin, bodygroups, bone, pos, ang, scale}`; with `bone` set it's stuck to that bone at an
  offset instead, for props that weren't rigged. Works from items.json or the console, e.g.
  `mcc_item_set rig_chest data.worn models/path/to/rig.mdl`. Your own gear is hidden in first person
  unless `mcc_worn_firstperson 1`. The inventory silhouette shows it too.
- **JMod resources** (with JMod installed): **E** on a resource box (wood, steel, fuel, ammo...) puts
  it in your inventory. The item keeps the box's exact amount (shown on the tile, never 0), and
  dropping it puts a real JMod box back with that amount, so it still works with JMod machines,
  crates and the workbench. Hold JMod's alt key (Alt) with E for JMod's own actions (load into a
  tool, Alt+Shift+E to split). Sizes are set per resource (ores 2x2, ingots and diamonds 1x2, water,
  rubber, basic parts, chemicals, explosives and munitions 3x3, sand and fissile material 3x4, oil
  2x3, gas and propellant 1x3... full list in `lua/mcc/compat/sh_jmod_resources.lua`; anything
  unlisted is 1x1); weight is 5 kg for a full box and
  scales with the amount. Item ids are `jmod_<type>` (`jmod_wood`, `jmod_iron_ore`...), so sizes and
  weights can be changed with `mcc_item_set`. `mcc_jmod_resources 0` leaves the boxes to JMod.
- **Containers**: props whose model is listed in `data/mcc/containers.json` can be searched, with a
  grid size set per model (crates, lockers, cabinets, fridges, dumpsters... by default). They start
  empty. A container can have several compartments, each its own grid with its own SEARCH button:
  the HL2 lockers are 4 compartments of 2x8. `mcc_container_set <w> <h> [name] [compartments]` /
  `mcc_container_remove` while looking at a prop (e.g. `mcc_container_set 2 8 Lockers 4`). In the
  JSON, `"count": 4` gives identical compartments, `"cells": [{"w": 4, "h": 3}, {"w": 4, "h": 5}]`
  different sizes, and `"vertical": true` stacks them top to bottom like drawers (the tall filing
  cabinet: 4 drawers of 2x2; the short green one: a 2x1 drawer over a 2x2; the lab one: two 2x2; the
  tall wooden drawers: six 2x1; the wardrobe: two 3x6 sides). New default containers are added to an
  existing containers.json on startup; defaults removed with `mcc_container_remove` stay removed.
- **NPC bodies**: dead NPCs leave a body laid out like a player's, with their gun in its slot (partly
  used magazine) and spare magazines or loose rounds in the pockets. Turns on `ai_serverragdolls`.
- **Dying** leaves a lootable body with everything except your **pouch**, which you keep. Bodies of
  players killed by another player carry their dogtag.
- **Body cleanup** (`mcc_inv_body_cleanup`, on): bodies (players', NPCs', "left" ones) stay until someone
  loots them (takes something out or puts something in); then they despawn `mcc_inv_body_looted_time`
  (360 s) after that first loot, and the prompt shows the countdown ("despawns in 5:42"). Looting again
  doesn't reset it. `mcc_inv_body_lifetime` (0 = off) caps any body's life, looted or not, and
  `mcc_inv_body_max` (30) caps how many there are: past it, looted bodies go first, then the oldest.
- New players (and anyone with an empty inventory) get `mcc_inv_starter` items (an Alpha Container in the pouch).
- **Leaving the server** loses everything except your **pouch** (the Alpha Container and what's in it).
  The rest stays where you stood as a lootable body named "<you> (left)" (`mcc_inv_leave_body 0`: it's
  just gone). An inventory saved in an earlier session (the server restarted or changed map) is wiped the
  same way when you join. Bring gear across sessions in your Alpha Container or an extraction crate.
  `mcc_inv_leave_wipe 0` keeps everything (for a persistent server).
- Inventories save to SQLite on the autosave timer, on disconnect and on death.
- Not in yet: armor and special-slot items (the slots exist), weight effects, loot tables for
  containers, the FOB stash, the health screen.

## FOBs (forward operating bases)
A FOB works like Rust's tool cupboard: it has a stash, pays the upkeep of everything built in its zone
every 30 minutes out of the JMod resources in that stash, and whatever it can't pay for decays.

- **FOB Kit** (JMod workbench, MCC category: 100 steel, 100 wood, 50 basic parts, 10 precision parts):
  right-click it > **Deploy FOB** while looking at flat ground. One FOB per player; zones can't overlap.
- **The core** is the silo launch room monitor (`models/props_silo/silo_launchroom_monitor.mdl`, from
  Episode Two; if that isn't mounted it falls back to a lab cart; `mcc_fob_core_model` changes it).
  Its health and zone grow by tier:

  | Tier | Health | Zone radius | Stash | Props | Upkeep per 30 min | Upgrade cost |
  | --- | --- | --- | --- | --- | --- | --- |
  | 1 Outpost | 1000 | 1024 | 8x10 | 60 | 10 wood | (the kit) |
  | 2 Forward Base | 2500 | 1536 | 10x12 | 120 | 15 wood, 10 steel | 300 wood, 200 steel, 100 basic parts |
  | 3 Stronghold | 5000 | 2048 | 12x14 | 200 | 20 concrete, 20 steel | 500 concrete, 400 steel, 50 precision parts |

  The zone (a ring on the ground: green yours, red someone else's, grey abandoned) is a safe zone that
  later NPC and mission spawners will respect (`MCC.FOB.InSafeZone(pos)`).
- **The stash**: press **E** on the core. Its stash opens in the inventory window, on the right like a
  container: drag anything in or out (weapons, gear, ammo, JMod resource boxes...), Ctrl+click to
  quick-move. The **JMod resource boxes in the stash are what the FOB pays with**: upkeep and upgrades
  come out of them (emptiest boxes first), and they show up in the menu's totals. Other ways in: JMod
  boxes pushed into the core, and **Deposit all** in the FOB menu (every JMod resource you carry; part-full
  boxes in the stash are topped up first). The stash grows with the tier. Food (organics, nutrients,
  water) is counted for traders and friendly NPCs later.
  **FOB MENU >** at the top of the stash opens the FOB's menu, and **Open stash** in the menu goes back.
  Only members open the stash; once the FOB is abandoned, anyone can (and raid it). Others pressing E
  get the menu.
- **Upkeep**: every 30 minutes (`mcc_fob_upkeep_interval`) the FOB pays its tier's upkeep plus each
  piece's upkeep, **per resource**: wood pieces cost wood, stone costs concrete, sheet metal steel,
  armored titanium. The menu shows each resource's cost per payment, how much is stored, how long it
  lasts and when the next payment is due. **Upkeep is paid**: the core repairs itself. **A resource runs
  short**: none of it is taken, and every piece paid in it decays over its tier's decay time (twig 1
  hour, wood 3, stone 5, sheet metal 8, armored 12), as does the core (12 hours). Pieces paid in other
  resources are fine. Depositing the missing resource pays straight away. At 0 health a piece breaks
  and the core is destroyed; a destroyed FOB's stash spills on the ground (JMod resources as real JMod
  boxes) and its props become ordinary props.
- **Building**: pieces from the Builder Tablet (below), and any prop you or your members spawn in the
  zone, become part of the FOB. Ordinary props get health from their size and material (metal x2,
  concrete x3, glass x0.4...) and pay upkeep and decay like the `mcc_fob_prop_tier` building tier (wood).
  Aim at one to see its health and tier. Bullets do a quarter damage, explosives full damage, and fire
  doesn't hurt stone or metal. Only members can build in the zone or physgun, gravgun, tool or edit its
  props.
- **Upgrade** from the menu, paid from the resources in the stash.
- **Members**: the owner adds and removes members from the menu. When the owner leaves, an online member
  takes over; with nobody left the FOB is abandoned: no safe zone, anyone can touch its props, and anyone
  can **Claim** it by staying at the core for 10 seconds. **Pack up** returns the kit to the owner and
  spills the stash.

**Admin FOB** (for testing): spawn menu > Entities > MCC > **Admin FOB**, or `mcc_fob_spawn` while aiming.
Its stash is 16x14 (`mcc_fob_admin_stash_w/h`) and starts with 500 of every building resource
(`mcc_fob_admin_stock`); it doesn't count toward anyone's FOB limit and gives no kit back when packed up.

**Range bubble**: `mcc_fob_range` (or the button on the Server Settings page) toggles see-through
bubbles around every FOB, plus an outline of a new FOB's tier 1 range where you aim, so you can see the
space before deploying.

Tiers are in `data/mcc/fob_tiers.json` (`"stash": {"w": 8, "h": 10}` sets a tier's grid) and the JMod
resources the core takes from JMod (and what counts as food) in `data/mcc/fob_storage.json`;
`mcc_reload_config` applies changes. A 0.8.0 fob_tiers.json (with "capacity") just gets the default stash
sizes; one from 0.7.0 (the old supply format) is backed up to `fob_tiers_old.json` and replaced.
Commands: `mcc_fob_list` (moderator); admin: `mcc_fob_spawn`, and while aiming at a core
`mcc_fob_stock <resource|all> <amount>` (puts boxes in the stash, e.g. `mcc_fob_stock basic parts 200`;
a negative amount takes them out), `mcc_fob_upkeep` (pay now) and `mcc_fob_remove`. Settings: see the Server Settings page (all `mcc_fob_*`); client
`mcc_fob_ring`. Hooks: `MCC_FOBDeployed`, `MCC_FOBUpgraded`, `MCC_FOBUpkeep(core, unpaid)`,
`MCC_FOBDestroyed`, `MCC_FOBAbandoned`, `MCC_FOBClaimed`; `MCC.FOB.ConsumeFood(core, n)` for NPCs,
`MCC.FOB.Load(core, resource, amount)`, `MCC.FOB.Take(core, cost)`, `MCC.FOB.AddResource/RemoveResource`
and `MCC.FOB.Grid(core)` (the stash grid) for other systems.

Not in yet: power for benches (JMod handles its own power), storage limits by item type (with the money
system), NPC factions claiming FOBs, saving FOBs between sessions (persistent mode).

## Builder Tablet (Rust-style building)
Needs the **mcc_content_fortifications** addon installed too (the tablet and fortification models).
Get the tablet from the JMod workbench (Builder Tablet: 20 precision parts, 20 basic parts, 10 plastic)
or `mcc_give mcc_build_tablet`; it goes in your holster slot.

Like Rust, building is split between two tools. The **Builder Tablet** (Rust's building plan) places pieces:

| Input | Does |
| --- | --- |
| Right-click | Pick a piece |
| Left-click | Build it where the green ghost is (red = can't, and the reason shows under your crosshair) |
| R | Rotate 15 degrees (fortifications and a building's first foundation) |

The **Builder Hammer** (JMod workbench: 20 wood, 20 steel, or `mcc_give mcc_hammer`; it goes in your
sheath slot) works on what you built:

| Input | Does |
| --- | --- |
| Right-click a piece | Its menu: upgrade to a higher tier, repair to full, remove (refund) |
| Left-click | Swing. Hitting a damaged piece repairs a tenth of its health (`mcc_build_hammer_repair`) for that share of the repair cost. Anything else takes a light blow |

As in Rust, a piece can't be repaired for 30 seconds after it's damaged (`mcc_build_repair_delay`).
JMod has no hammer model (its EZ Toolbox is fists and a toolbox), so the hammer looks like the HL2 crowbar
for now; `mcc_build_hammer_viewmodel` / `mcc_build_hammer_worldmodel` swap in a real hammer model later.

- **Structure** (foundation, wall, floor: base Garry's Mod props) snaps Rust-style. The first foundation
  sets the building's grid: its size and facing. More foundations attach to its sides, walls stand on
  foundation and floor edges (or on top of other walls), floors go on top of walls. A piece needs
  something holding it up.
- **Tiers**, as in Rust. Every structure piece is placed as **Twig** for 20 wood, then upgraded with the
  hammer. Costs are paid from **your FOB's stash** first (you're building in its zone), and whatever it's
  short of comes from the JMod resources you carry, so you don't need to haul materials around
  (`mcc_build_use_fob_stash 0` makes it what you carry only):

  | Tier | Health | Decays in | Upgrade cost | Upkeep per 30 min | Fire |
  | --- | --- | --- | --- | --- | --- |
  | Twig | 10 | 1 hour | 20 wood (to place) | 1 wood | burns |
  | Wood | 1000 | 3 hours | 50 wood | 2 wood | burns |
  | Stone | 3500 | 5 hours | 75 concrete | 2 concrete | immune |
  | Sheet Metal | 8000 | 8 hours | 50 steel | 2 steel | immune |
  | Armored | 12000 | 12 hours | 25 titanium | 1 titanium | immune |

  You can skip tiers but not go down. Each tier has its own look (a material on the prop; placeholders
  for now, until the Rust models are in).
- **Repair** with the hammer: from 0 to full costs half its tier's cost (`mcc_build_repair_cost`).
  **Remove** gives back half its tier's cost into the FOB's stash, or your inventory if the stash is full
  (`mcc_build_refund`).
- **Fortifications** (Alydus's sandbags, Hesco, concrete walls and barriers, fences, police barricades)
  go wherever you aim, facing you; aim at the same piece to line the next one up flush against its side.
  Each has its own cost, health, upkeep and decay time (sandbags: 20 sand, 400 HP, 1 sand upkeep, 4 hours;
  concrete walls: concrete, up to 3500 HP; Hesco: sand and steel...).
- Pieces are built **inside a FOB you're a member of** and count toward its prop limit; the FOB pays
  their upkeep (see above).
- Tiers are in `data/mcc/build_tiers.json` (name, health, decay hours, cost, upkeep, material,
  fire-immune) and the catalog in `data/mcc/build_pieces.json` (name, category, model, kind:
  `foundation`, `wall`, `floor` snap to the grid, `free` doesn't; `stand`; and for free pieces cost,
  upkeep, health and decay hours). New pieces (the Rust models later) need no Lua. Pieces added to MCC's
  defaults are added to your file automatically. A 0.7.0 build_pieces.json is backed up to
  `build_pieces_old.json` (its metal and wood walls became one wall shape with tiers).
- Settings: `mcc_build_free` (no costs, for testing), `mcc_build_outside_fob`, `mcc_build_range`,
  `mcc_build_refund`, `mcc_build_repair_cost`, `mcc_build_hammer_repair`, `mcc_build_repair_delay`,
  `mcc_build_hammer_viewmodel`, `mcc_build_hammer_worldmodel`. Hooks: `MCC_PiecePlaced(ply, ent, piece)`,
  `MCC_PieceUpgraded(ply, ent, tier)`.

Not in yet: doorways and doors (no base Garry's Mod doorway prop; they come with the Rust content),
pieces collapsing when what holds them up is destroyed.

## Extraction (take gear into the next session)
1. **Extraction Crate** (JMod workbench, MCC category): a 5x5 crate that holds at most 2 weapons and
   300 JMod resource units (bags count what's inside them). E opens it like any container.
2. **Fulton Recovery Device** (workbench): open the crate (or look at it), right-click the Fulton >
   **Attach to crate**. It needs open sky. The balloon inflates, the crate hovers for about a second,
   then it's yanked into the sky. Shooting the balloon while it hovers drops the crate and wastes the
   Fulton. Whoever attached the Fulton owns the crate. Each player stores up to 3 crates; a 4th
   overwrites the oldest.
3. **Signal Flare** (workbench): right-click > **Throw**. Your oldest stored crate parachutes onto it
   after 15 seconds. Everyone sees red smoke and a SUPPLY DROP marker until someone opens it; you can
   open it straight away, others have to search it. A flare calls the thrower's own crates, so a stolen
   flare only helps someone with crates of their own. No open sky over the flare: the drop is called
   off and the crate stays stored. Keep flares in your Alpha Container or you lose them on death.

Stored crates are in `data/mcc/extraction/<steamid64>.json`. All MCC recipe costs (crate, Fulton, flare,
FOB Kit) are in `data/mcc/jmod_recipes.json` (JMod resource name -> amount; `mcc_reload_config` applies
changes; an old extraction_recipes.json is folded in).
Defaults: crate 50 wood, 20 steel, 10 precision parts; Fulton 20 gas, 10 cloth, 10 basic parts;
flare 5 chemicals, 5 propellant. Commands: `mcc_extract_list [player]` (moderator), `mcc_extract_clear <player>` (admin).
Settings: `mcc_extract_enabled`, `mcc_extract_max_crates`, `mcc_extract_crate_w/h`, `mcc_extract_max_weapons`,
`mcc_extract_max_resources`, `mcc_extract_fulton_hover`, `mcc_extract_drop_delay`, `mcc_extract_marker_time`;
client `mcc_extract_marker`. Hooks: `MCC_CanStore(ply, item, container)`, `MCC_ContainerOpened(ply, ent)`,
`MCC_CrateExtracted(steamid, crate)`, `MCC_CrateDropped(steamid, crate)`, `MCC_FultonPopped(crate, attacker)`.

Not in yet: the session wipe itself (logging off still saves your full inventory), money and its
limits, the random-loot flare event.

## Install
Copy the `mcc_base` folder into `garrysmod/addons/`. The first server start creates
`garrysmod/data/mcc/` with `items.json` and a `README.txt` explaining the format.

## Layout
```
lua/autorun/mcc_base_init.lua   loader + boot sequence
lua/mcc/core/
  sh_util.lua        logging, JSON-safe copies, console replies
  sh_config.lua      MCC.Config: settings as mcc_* cvars
  sh_perms.lua       MCC.Perms: CAMI privileges (ULX, SAM...), admin fallback
  sh_net.lua         MCC.Net: send tables of any size (chunked, compressed)
  sh_registry.lua    MCC.Registry: schema-checked registries
  sh_items.lua       MCC.Items: the item registry, items.json overrides, client sync
  sv_data.lua        MCC.Data: JSON config files + SQLite key-value store, autosave
  sh_compat.lua      MCC.Compat: optional addons (JMod), admin notice
  sv_commands.lua    MCC.Command + mcc_help, mcc_version, mcc_reload_config, mcc_save
  sv_items_admin.lua mcc_item_* commands
  sv_settings.lua / cl_settings.lua   the Server Settings page
  cl_ui.lua          Esc closes MCC windows (MCC.UI.Escapable(panel) for expansions' windows)
lua/mcc/pickup/      E pickup, no auto-pickup, drop key, prompt, Controls menu
lua/mcc/compat/      Tarkov Inventory hand-off, JMod resource boxes as items
lua/mcc/extract/     extraction crates, the Fulton, signal flares and airdrops
lua/mcc/fob/         FOBs: deploy, storage, tiers, upkeep and decay, prop health, members, claiming, menu, HUD, range bubble
lua/mcc/build/       Builder Tablet: building tiers, piece catalog, grid snapping, placing/upgrading/repairing/removing, ghost, menus
lua/entities/mcc_fob.lua, mcc_fob_admin.lua   the FOB core and the Admin FOB spawn entry
lua/weapons/mcc_build_tablet.lua   the tablet (model and screen from Alydus's tablet)
lua/weapons/mcc_hammer.lua         the Builder Hammer
lua/mcc/inventory/   inventory rules, server logic, searching, world items + bodies, UI, inspect window
lua/entities/mcc_item.lua   an item lying in the world
lua/entities/mcc_mag_*.lua  spawn menu entries for loaded HL2 magazines
lua/mcc/content/sh_items_hl2.lua   default HL2 weapons, ammo, magazines, consumables, gear
tests/                             logic tests on a mocked GMod API (not shipped)
```

## For expansion addons
Add hooks at file load; they fire in this order whatever order GMod loads addons in:
```lua
hook.Add("MCC_Loaded", "my_addon", function(MCC)
    MCC.Compat.Register("zbase", {name = "ZBase", detect = function() return ZBaseSpawnZBaseNPC ~= nil end})
end)

hook.Add("MCC_RegisterItems", "my_addon", function(Items)
    Items.Register("intel_ledger", {name = "Militia Ledger", kind = "misc", w = 1, h = 1, price = 250})
end)

-- a weapon pack's guns and ammo: one entry each
hook.Add("MCC_RegisterItems", "my_weapon_pack", function(Items)
    Items.Register("arc9_eft_mp5", {name = "MP5", kind = "weapon", class = "arc9_eft_mp5", w = 3, h = 2,
        weight = 2.5, price = 1200, data = {slot = "primary", ammo = "9x19MM", clip = 30, feed = "loose"}})
    Items.Register("ammo_9x19", {name = "9x19mm", kind = "ammo", class = "9x19MM", weight = 0.008,
        data = {ammo = "9x19MM"}})
end)

hook.Add("MCC_Ready", "my_addon", function(MCC) end) -- everything loaded, data files applied
```
Inventory API: `MCC.Inv.GiveID(ply, id, n, data)`, `MCC.Inv.NPCLoadout(weaponClass)`, hook `MCC_NPCBody(npc, inv, weaponClass)`,
`MCC.Inv.TakeEntity(ply, ent)`, `MCC.Inv.Get(ply)`, `MCC.Inv.MakeBody(ent, inv, name)` (e.g. NPC
corpses), `MCC.Inv.SpawnWorldItem(item, pos)`; hook `MCC_UseItem(ply, item, def)` for custom consumables.

Pickup hooks: `MCC_IsPickup(ent)`, `MCC_PickupWeapon(ply, wep)`, `MCC_PickupItem(ply, ent)`,
`MCC_CanDropWeapon(ply, wep)`, `MCC_DropWeapon(ply, wep)` (return true when you handled it).

Container hooks: `MCC_CanStore(ply, item, ent)` (return false, reason to refuse), `MCC_ContainerOpened(ply, ent)`,
`MCC_ContainerChanged(ent, ply)` (after a player moved items in or out). Any entity with an `MCCCont` table
(`{name, noSearch, grids = {{w, h, items}}}`) opens with `MCC.Inv.OpenContainer(ply, ent)`, as the FOB stash does.
Client windows: `MCC.UI.Escapable(frame)` makes Esc close it.

World item hooks: `MCC_ItemFromEntity(ent, item, def)` (copy an entity's state onto the item when it's
picked up) and `MCC_SpawnWorldItem(item, pos, dropper, permanent)` (return your own entity to put in the
world when it's dropped); the JMod resource support is built on these.

Weapon state hooks: `MCC_SaveWeaponState(wep, data)` (add fields to `data`, saved with the item) and
`MCC_RestoreWeaponState(wep, data)`. Client: `MCC.Inv.OpenInspect(item, loc)`.

Settings page (client): `MCC.Settings.AddGroup(title, {"prefix_"})` gives an expansion's `mcc_prefix_*`
settings their own section, `MCC.Settings.AddClientOption(cvar, label)` adds a player option.

Other hooks: `MCC_ItemsChanged` (registry rebuilt or synced), `MCC_ReloadConfig`, `MCC_Save(reason)`.

Useful calls: `MCC.Items.Get(id)`, `MCC.Items.FromClass(class)`, `MCC.Items.Price(id)`,
`MCC.Config.Define/Get`, `MCC.Perms.Register/Check`, `MCC.Net.Send/Receive`,
`MCC.Data.Set/Get/GetAll/Delete`, `MCC.Command(name, privilege, usage, help, fn)`.

## Item fields
| Field | Notes |
| --- | --- |
| `name`, `kind` | Required. Kinds: weapon, ammo, mag, gear, armor, consumable, resource, misc (expansions can add more) |
| `class` | Weapon, entity or ammo type the item maps to |
| `w`, `h` | Grid size, 1 to 10 |
| `maxStack` | Per cell. Default: `mcc_default_stack` (50) for ammo/resource/misc, 1 otherwise |
| `weight` | kg |
| `price` | Supply. Per unit for stackables. Omit = can't be bought or sold |
| `model`, `category`, `rarity`, `tags` | rarity: common, uncommon, rare, epic |
| `data` | Kind-specific, e.g. weapons: `slot`, `ammo`, `feed` (mag/tube/cylinder/single), `mag`; gear: `slot`, `cells`, `worn` |

## Server owner commands
| Command | Privilege |
| --- | --- |
| `mcc_help`, `mcc_version`, `mcc_item_list [filter]`, `mcc_item_info <id>` | MCC Moderator (admin) |
| `mcc_item_set <id> <field or data.key> <value>` | MCC Admin (superadmin) |
| `mcc_item_addweapon <class> [price]` (any installed SWEP) | MCC Admin |
| `mcc_item_remove <id>`, `mcc_item_reset <id>` | MCC Admin |
| `mcc_reload_config`, `mcc_save` | MCC Admin |
| `mcc_give <item id> [amount] [player]` (magazines come loaded) | MCC Moderator |
| `mcc_container_set <w> <h> [name] [compartments]`, `mcc_container_remove` (aim at a prop) | MCC Admin |
| `mcc_inv_clear [player]` | MCC Admin |
| `mcc_fob_list` | MCC Moderator |
| `mcc_fob_spawn`, `mcc_fob_stock <resource\|all> <amount>`, `mcc_fob_upkeep`, `mcc_fob_remove` | MCC Admin |
| `mcc_extract_list [player]` / `mcc_extract_clear <player>` | MCC Moderator / MCC Admin |

## Gameplay tweaks
- **Kill feed hidden** (`mcc_hide_killfeed`, on).
- **HL2 weapons hit harder**: `mcc_hl2_damage_mult` (1.25) for players, `mcc_hl2_damage_mult_npc` (1, stock)
  for NPCs, on bullets, buckshot, crossbow bolts and melee from the weapons in `mcc_hl2_damage_weapons`
  (pistol, .357, SMG, AR2, shotgun, crossbow, crowbar, stunstick); grenades and explosions are left alone.

## Settings
**Q menu > Utilities > MCC > Server Settings** lists every MCC server setting, grouped (Core, Pickup and
drop, Inventory, JMod, Extraction, FOB, Building), with checkboxes, sliders and text fields. Everyone
can see them; only admins (MCC Admin) can change them, and changes apply right away. Hover a control
for its console name and what it does. Your own client options are at the bottom.

From the console, `mcc_help` lists the commands, and every setting is an `mcc_*` convar.

Client: `mcc_drop_key`, `mcc_inventory_key` (KEY_ numbers), `mcc_pickup_prompt`, `mcc_worn_draw`,
`mcc_worn_firstperson`, `mcc_extract_marker`, `mcc_fob_ring`

## Credits
The Builder Tablet is based on **Alydus's Fortification Builder Tablet** (Steam Workshop 1461735659):
its tablet model, screen and fortification pack (in mcc_content_fortifications). Per Alydus's terms,
keep the credit and don't reupload it to the Workshop; running it on your own server is fine.

Weapon grid sizes, the rig/backpack compartment layouts, the model framing in item icons and the
inspect window and inventory mechanics (gear owns its contents, rig/pocket ammo is usable, lootable bodies, drag and
drop) are adapted from the Tarkov Inventory addon. The gear screen layout follows Escape from Tarkov's. Add its author's name here before publishing.

## Running the tests
Needs Python 3 and `pip install lupa`. Run `python3 tests/test_core.py`, `tests/test_pickup.py` and `tests/test_inventory.py`.
Expansions' tests use the mock in `tests/gmod_mock.py` (`Realm(realm, extra_roots=[their lua folder])`).
They cover the server logic only; the UI needs testing in game.
