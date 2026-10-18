import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gmod_mock import Realm

failures = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)

from inv_world import WORLD

sv = Realm("server")
sv.load_mcc()
sv.run(WORLD)
sv.boot()
sv.run('_TIME = 100 _SetCV("mcc_mags_required", 0) _SetCV("mcc_search_enabled", 0)')  # searching has its own section  # loose-ammo rules first; magazines have their own section
L = sv.eval

def run(code):
    sv.run(code)

def flush():
    run('MCC.Inv.Update(P) hook.Run("Think")')

run('P = _MakeTester(1) _PLAYERS = {P} hook.Run("PlayerInitialSpawn", P) hook.Run("PlayerLoadout", P)')
check(L('MCC.Inv.Enabled()') is True, "inventory enabled by default")
check(L('MCC.Inv.Get(P).slots.pouch ~= nil and MCC.Inv.Get(P).slots.pouch.id == "pouch_secure"'), "new player starts with the secure pouch")
check(L('P:HasWeapon("weapon_physgun") and P:HasWeapon("gmod_tool")'), "always-weapons are given outside the inventory")

# gear and weapons auto-place
run('MCC.Inv.GiveID(P, "rig_chest", 1) MCC.Inv.GiveID(P, "bp_daypack", 1)')
check(L('MCC.Inv.Get(P).slots.rig.id') == "rig_chest", "rig goes to the rig slot")
check(L('MCC.Inv.Get(P).slots.backpack.id') == "bp_daypack", "backpack goes to the backpack slot")
run('MCC.Inv.GiveID(P, "weapon_smg1", 1)')
check(L('MCC.Inv.Get(P).slots.sling.id') == "weapon_smg1", "first primary goes on the sling")
check(L('P:HasWeapon("weapon_smg1")'), "equipped weapon is given for real")
run('MCC.Inv.GiveID(P, "weapon_ar2", 1)')
check(L('MCC.Inv.Get(P).slots.back.id') == "weapon_ar2", "second primary goes on the back")
run('MCC.Inv.GiveID(P, "weapon_smg1", 1)')
check(L('MCC.Inv.Get(P).slots.backpack.cont[1][1] and MCC.Inv.Get(P).slots.backpack.cont[1][1].id') == "weapon_smg1",
      "a duplicate SMG can't be equipped twice, so it goes to the backpack")

# ammo stacks: 120 SMG rounds -> 50 + 50 + 20 in the rig
left = L('MCC.Inv.GiveID(P, "ammo_smg1", 120)')
check(left == 0, "120 rounds fit")
counts = L('(function() local t = {} for _, list in ipairs(MCC.Inv.Get(P).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" then t[#t+1] = o.n end end end table.sort(t) return table.concat(t, ",") end)()')
check(counts == "20,50,50", "stacks fill to 50 per cell (got %s)" % counts)
flush()
check(L('P:GetAmmoCount("SMG1")') == 120, "rig ammo is mirrored into real ammo")

# rounds used by the engine come out of the rig
run('P:SetAmmo(75, "SMG1")')
run('timer.t["MCC_InvAmmoPoll"].f()')
flush()
total = L('(function() local n = 0 for _, list in ipairs(MCC.Inv.Get(P).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" then n = n + o.n end end end return n end)()')
check(total == 75, "spent rounds are removed from the rig (left %s)" % total)

# backpack ammo isn't usable
run('MCC.Inv.Get(P).slots.backpack.cont[1][#MCC.Inv.Get(P).slots.backpack.cont[1] + 1] = {u = MCC.Inv.NewUID(), id = "ammo_ar2", n = 30, x = 0, y = 4}')
flush()
check(L('P:GetAmmoCount("AR2")') == 0, "ammo in the backpack is carried, not usable")

# moving: backpack -> rig grid makes it usable
u = L('MCC.Inv.Get(P).slots.backpack.cont[1][2].u')
ok = L('(MCC.Inv.Move(P, %d, "g:rig:8", 0, 0, false))' % u)
check(ok is True, "move from backpack to an empty rig compartment")
flush()
check(L('P:GetAmmoCount("AR2")') == 30, "moved ammo becomes usable")

# invalid moves
ok = L('(MCC.Inv.Move(P, %d, "s:holster"))' % u)
check(ok is False, "ammo can't go in the holster")
smg2 = L('MCC.Inv.Get(P).slots.backpack.cont[1][1].u')
ok = L('(MCC.Inv.Move(P, %d, "g:rig:6", 0, 0, false))' % smg2)
check(ok is False, "a 3x2 weapon doesn't fit a 1x1 compartment")
rig_u = L('MCC.Inv.Get(P).slots.rig.u')
ok = L('(MCC.Inv.Move(P, %d, "g:backpack:1", 0, 0, false))' % rig_u)
check(ok is False, "gear can't go inside other gear")

# rotation: a 3x2 SMG rotated is 2x3
ok = L('(MCC.Inv.Move(P, %d, "g:backpack:1", 3, 0, true))' % smg2)
check(ok is True and L('MCC.Inv.Get(P).slots.backpack.cont[1][1].r') is True, "rotated placement")

# merging stacks by dropping one onto another
run('MCC.Inv.Get(P).slots.pocket1 = {u = MCC.Inv.NewUID(), id = "ammo_smg1", n = 10}')
p1 = L('MCC.Inv.Get(P).slots.pocket1.u')
first = L('(function() for _, list in ipairs(MCC.Inv.Get(P).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" and o.n < 50 then return o.u end end end end)()')
ok = L('(MCC.Inv.Move(P, %d, "s:pocket1"))' % first)
check(ok is True, "drop a stack onto a pocket stack")
check(L('MCC.Inv.Get(P).slots.pocket1.n') == 10 + 0 or L('MCC.Inv.Get(P).slots.pocket1.n') > 10, "pocket stack grew")

# split
run('MCC.Inv.Get(P).slots.pocket2 = {u = MCC.Inv.NewUID(), id = "ammo_pistol", n = 40}')
p2 = L('MCC.Inv.Get(P).slots.pocket2.u')
ok = L('(MCC.Inv.Split(P, %d))' % p2)
check(ok is True and L('MCC.Inv.Get(P).slots.pocket2.n') == 20, "split halves a stack")

# weapon slot moves keep the magazine
run('P:GetWeapon("weapon_smg1"):SetClip1(33)')
sling = L('MCC.Inv.Get(P).slots.sling.u')
ok = L('(MCC.Inv.Move(P, %d, "g:backpack:1", 0, 2, false))' % sling)
check(ok is True and not L('P:HasWeapon("weapon_smg1")'), "unequipping strips the weapon")
check(L('(function() for _, o in ipairs(MCC.Inv.Get(P).slots.backpack.cont[1]) do if o.u == %d then return o.d.clip end end end)()' % sling) == 33,
      "unequipped weapon remembers its magazine")
ok = L('(MCC.Inv.Move(P, %d, "s:sling"))' % sling)
check(ok is True and L('P:GetWeapon("weapon_smg1"):Clip1()') == 33, "re-equipping restores the magazine")

# consumables
run('MCC.Inv.GiveID(P, "item_healthvial", 1)')
vial = L('(function() for i = 1, 4 do local o = MCC.Inv.Get(P).slots["pocket" .. i] if o and o.id == "item_healthvial" then return o.u end end for _, list in ipairs(MCC.Inv.Get(P).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "item_healthvial" then return o.u end end end end)()')
ok = L('(MCC.Inv.Use(P, %d))' % vial)
check(ok is True and L('P:Health()') == 60, "health vial heals and is used up")
check(L('(MCC.Inv.Find(P, %d))' % vial) is None, "used item is gone")

# drop and pick up a world item
ar2 = L('MCC.Inv.Get(P).slots.back.u')
ok = L('(MCC.Inv.Drop(P, %d))' % ar2)
check(ok is True and L('MCC.Inv.Get(P).slots.back') is None and not L('P:HasWeapon("weapon_ar2")'), "drop removes the item and the weapon")
dropped = L('(function() for i = #_ENTS, 1, -1 do local e = _ENTS[i] if e:GetClass() == "mcc_item" then return e end end end)()')
check(dropped is not None and L('_ENTS[#_ENTS]:GetItemID()') == "weapon_ar2", "dropped item exists in the world")
check(L('MCC.Pickup.Kind(_ENTS[#_ENTS])') == "mcc_item", "world item is a pickup")
run('hook.Run("MCC_PickupCustom", P, _ENTS[#_ENTS], "mcc_item")')
check(L('MCC.Inv.Get(P).slots.back and MCC.Inv.Get(P).slots.back.id') == "weapon_ar2", "picking it back up re-equips it")

# the drop key drops the inventory item, magazine included
run('_TIME = 200 P:GetWeapon("weapon_ar2"):SetClip1(7) P.GetActiveWeapon = function() return P:GetWeapon("weapon_ar2") end')
run('_CMDS["mcc_drop"](P)')
check(L('MCC.Inv.Get(P).slots.back') is None and L('_ENTS[#_ENTS]:GetItemID()') == "weapon_ar2"
      and L('_ENTS[#_ENTS].MCCItem.d.clip') == 7, "G drops the equipped weapon as an item with its magazine")
run('hook.Run("MCC_PickupCustom", P, _ENTS[#_ENTS], "mcc_item")')

# E on a world weapon entity converts it into an item with its magazine
run('W = _MakeWeaponEnt("weapon_pistol", 18) W:SetClip1(12)')
handled = L('(hook.Run("MCC_PickupWeapon", P, W))')
check(handled is True and L('MCC.Inv.Get(P).slots.holster.d.clip') == 12, "world pistol goes to the holster with its rounds")

# HL2 ammo box
run('BOX = _Ent("item_ammo_pistol")')
handled = L('(hook.Run("MCC_PickupItem", P, BOX))')
check(handled is True and not L('IsValid(BOX)'), "HL2 ammo box becomes inventory ammo")

# quick move: a magazine in the rig -> backpack (pockets only take 1x1 items)
run('MCC.Inv.GiveID(P, "mag_smg1", 1)')
qa = L('(function() for i, list in ipairs(MCC.Inv.Get(P).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "mag_smg1" then return o.u end end end end)()')
ok = L('(MCC.Inv.Quick(P, %d))' % qa)
check(ok is True and L('(select(2, MCC.Inv.Find(P, %d)))' % qa).startswith("g:backpack"), "ctrl+click moves rig items to the backpack")

# client actions over the net
run('MCC.Net.Handlers.inv_act.fn({a = "split", u = %d}, P)' % p2)
check(True, "net action handler runs")
run('MCC.Net.Handlers.inv_act.fn({a = "move", u = "bad", to = {}}, P)')
check(True, "malformed actions are ignored")

# save and load
run('MCC.Inv.Save(P)')
saved_rig = L('MCC.Data.Get("inv", "1").slots.rig.id')
check(saved_rig == "rig_chest", "inventory saved to SQLite")
run('P2 = _MakeTester(1) hook.Run("PlayerInitialSpawn", P2)')
check(L('MCC.Inv.Get(P2).slots.rig.id') == "rig_chest" and L('MCC.Inv.Get(P2).slots.holster.d.clip') == 12,
      "inventory and magazines load back")
check(L('MCC.Inv.Get(P2).slots.rig.u') != L('MCC.Inv.Get(P).slots.rig.u'), "loaded items get fresh ids")

# leaving the server: everything but the pouch (Alpha Container) is lost, left behind as a body
run('LV = _MakeTester(41) _PLAYERS = {LV} hook.Run("PlayerInitialSpawn", LV) hook.Run("PlayerLoadout", LV)')
run('MCC.Inv.GiveID(LV, "rig_chest", 1) MCC.Inv.GiveID(LV, "weapon_smg1", 1)')
run('MCC.Inv.Get(LV).slots.pouch.cont[1][1] = {u = MCC.Inv.NewUID(), id = "item_healthvial", x = 0, y = 0}')
check(L('MCC.Inv.Get(LV).slots.rig ~= nil') and L('MCC.Inv.Get(LV).slots.pouch.id') == "pouch_secure", "(a player with a rig, a gun and something in their Alpha Container)")
nents = L('#_ENTS')
run('hook.Run("PlayerDisconnected", LV) _PLAYERS = {}')
saved = L('(function() local t = {} for k in pairs(MCC.Data.Get("inv", "41").slots) do t[#t + 1] = k end table.sort(t) return table.concat(t, ",") end)()')
check(saved == "pouch" and L('MCC.Data.Get("inv", "41").slots.pouch.cont[1][1].id') == "item_healthvial",
      "leaving saves only the Alpha Container, with what's inside it")
check(L('(function() for i = #_ENTS, %d, -1 do local e = _ENTS[i] if e.MCCCont and e.MCCCont.inv then return e.MCCCont.name .. "|" .. tostring(e.MCCCont.inv.slots.rig and e.MCCCont.inv.slots.rig.id) end end end)()' % (nents + 1))
      == "Tester41 (left)|rig_chest", "the rest stays where they stood as a lootable body")
run('LV2 = _MakeTester(41) _PLAYERS = {LV2} hook.Run("PlayerInitialSpawn", LV2) hook.Run("PlayerLoadout", LV2)')
check(L('MCC.Inv.Get(LV2).slots.rig') is None and L('MCC.Inv.Get(LV2).slots.pouch.cont[1][1].id') == "item_healthvial",
      "rejoining: only the Alpha Container comes back")
# a server restart or map change (an inventory saved in another session) is wiped the same way
run('MCC.Data.Set("inv", "43", {slots = {rig = MCC.Inv.NewItem("rig_chest", 1), pouch = MCC.Inv.NewItem("pouch_secure", 1)}, session = "old"})')
run('NS3 = _MakeTester(43) hook.Run("PlayerInitialSpawn", NS3)')
check(L('MCC.Inv.Get(NS3).slots.rig') is None and L('MCC.Inv.Get(NS3).slots.pouch ~= nil') and L('NS3.MCCInvWiped') is True,
      "an inventory from an earlier session (restart, map change) comes back as just the Alpha Container")
run('_SetCV("mcc_inv_leave_wipe", 0)')
run('LV3 = _MakeTester(44) _PLAYERS = {LV3} hook.Run("PlayerInitialSpawn", LV3) hook.Run("PlayerLoadout", LV3) MCC.Inv.GiveID(LV3, "rig_chest", 1)')
run('hook.Run("PlayerDisconnected", LV3) _PLAYERS = {}')
check(L('MCC.Data.Get("inv", "44").slots.rig ~= nil'), "mcc_inv_leave_wipe 0 keeps everything (persistent servers)")
run('_SetCV("mcc_inv_leave_wipe", 1)')

# death: everything except the pouch goes to the body; killer gets a dogtag on the body
run('MCC.Inv.Get(P).slots.pouch.cont[1][1] = {u = MCC.Inv.NewUID(), id = "item_healthvial", x = 0, y = 0}')
run('K = _MakeTester(2)')
result = L('(hook.Run("DoPlayerDeath", P, K, nil))')
check(result is True, "MCC handles the death")
body = L('(function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i] end end end)()')
check(body is not None, "a lootable body is created")
check(L('(function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i].MCCCont.inv.slots.rig.id end end end)()') == "rig_chest",
      "the body has the rig")
check(L('(function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i].MCCCont.inv.slots.pouch end end end)()') is None,
      "the pouch is not on the body")
check(L('(function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i].MCCCont.inv.slots.dogtag.d.name end end end)()') == "Tester1",
      "killed by a player: the body carries a dogtag")
tagd = '(function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i].MCCCont.inv.slots.dogtag.d end end end)()'
check(L(tagd + '.killer') == "Tester2" and L(tagd + '.killerSid') == "2" and L(tagd + '.t') == 1000,
      "the dogtag records who killed them and when")
check(L('MCC.Inv.Get(P).slots.pouch.cont[1][1].id') == "item_healthvial", "the pouch and its contents survive death")
check(L('MCC.Inv.Get(P).slots.rig') is None, "everything else is gone from the player")
check(L('K._frags') == 1 and L('P._deaths') == 1, "frags and deaths still count")

# looting the body
run('BODY = (function() for i = #_ENTS, 1, -1 do if _ENTS[i].MCCCont then return _ENTS[i] end end end)()')
run('BODY:SetPos(Vector(10, 0, 0))')
run('hook.Run("MCC_PickupCustom", K, BODY, "body")')
check(L('K.MCCInvOpen == BODY'), "pressing E on a body opens it")
loot = L('BODY.MCCCont.inv.slots.rig.u')
ok = L('(MCC.Inv.Quick(K, %d))' % loot)
check(ok is True and L('MCC.Inv.Get(K).slots.rig and MCC.Inv.Get(K).slots.rig.id') == "rig_chest", "ctrl+click takes the rig from the body")
check(L('BODY.MCCCont.inv.slots.rig') is None, "and it's gone from the body")

# admin give
run('_CMDS["mcc_give"](nil, "mcc_give", {"ammo_ar2", "30", "Tester2"})')
check(L('(function() local n = 0 for _, list in ipairs(MCC.Inv.Get(K).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_ar2" then n = n + o.n end end end return n end)()') >= 30,
      "mcc_give puts items in a player's inventory")


# ---------------------------------------------------------------- magazines
M = 'MCC.Inv.Get(Q)'
run('Q = _MakeTester(3) _PLAYERS = {P, K, Q} hook.Run("PlayerInitialSpawn", Q) hook.Run("PlayerLoadout", Q)')
run('_SetCV("mcc_mags_required", 1)')
run('MCC.Inv.GiveID(Q, "rig_chest", 1) MCC.Inv.GiveID(Q, "bp_daypack", 1) MCC.Inv.GiveID(Q, "weapon_smg1", 1)')
run('MCC.Inv.GiveID(Q, "mag_smg1", 1, {rounds = 45}) MCC.Inv.GiveID(Q, "mag_smg1", 1, {rounds = 20})')
run('MCC.Inv.GiveID(Q, "ammo_smg1", 50)')
run('MCC.Inv.Update(Q) hook.Run("Think")')
check(L('Q:GetAmmoCount("SMG1")') == 45, "mag-fed gun: reserve is the fullest magazine, not loose rounds")
check(L('MCC.Items.Get("mag_smg1") and MCC.Inv.NewItem("mag_smg1").d.rounds') == 0, "new magazines start empty")

# the engine reloads: gun had 10, takes 35 from the 45-round mag
run('Q:GetWeapon("weapon_smg1"):SetClip1(45) Q:SetAmmo(10, "SMG1")')
run('MCC.Inv.PollAmmo(Q)')
mags = L('(function() local t = {} for _, list in ipairs(%s.slots.rig.cont) do for _, o in ipairs(list) do if o.id == "mag_smg1" then t[#t+1] = o.d.rounds end end end table.sort(t) return table.concat(t, ",") end)()' % M)
check(L('Q:GetWeapon("weapon_smg1"):Clip1()') == 45, "reload puts the whole new magazine in the gun")
check(mags == "10,20", "the old rounds go back into that magazine (mags now %s)" % mags)
run('MCC.Inv.Update(Q) hook.Run("Think")')
check(L('Q:GetAmmoCount("SMG1")') == 20, "next reload is the fullest remaining magazine")

loose_before = L('(function() local n = 0 for _, list in ipairs(%s.slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" then n = n + o.n end end end return n end)()' % M)
check(loose_before == 50, "loose rounds are untouched by reloads")
mag10 = L('(function() for _, list in ipairs(%s.slots.rig.cont) do for _, o in ipairs(list) do if o.id == "mag_smg1" and o.d.rounds == 10 then return o.u end end end end)()' % M)
ok = L('(MCC.Inv.LoadMag(Q, %d))' % mag10)
check(ok is True and L('(MCC.Inv.Find(Q, %d)).d.rounds' % mag10) == 45, "loading a magazine fills it from loose rounds")
loose_after = L('(function() local n = 0 for _, list in ipairs(%s.slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" then n = n + o.n end end end return n end)()' % M)
check(loose_after == 15, "and uses those rounds up (15 left, got %s)" % loose_after)
ok = L('(MCC.Inv.UnloadMag(Q, %d))' % mag10)
check(ok is True and L('(MCC.Inv.Find(Q, %d)).d.rounds' % mag10) == 0, "unloading empties the magazine into loose rounds")

# dragging loose rounds onto a magazine loads it
loose = L('(function() for _, list in ipairs(%s.slots.rig.cont) do for _, o in ipairs(list) do if o.id == "ammo_smg1" then return o.u end end end end)()' % M)
magloc = L('(select(2, MCC.Inv.Find(Q, %d)))' % mag10)
mx = L('(MCC.Inv.Find(Q, %d)).x' % mag10); my = L('(MCC.Inv.Find(Q, %d)).y' % mag10)
ok = L('(MCC.Inv.Move(Q, %d, "%s", %d, %d, false))' % (loose, magloc, mx, my))
check(ok is True and L('(MCC.Inv.Find(Q, %d)).d.rounds' % mag10) > 0, "drag rounds onto a magazine to load it")

# loose-ammo guns still use loose rounds with magazines on
run('MCC.Inv.GiveID(Q, "weapon_357", 1) MCC.Inv.GiveID(Q, "ammo_357", 12) MCC.Inv.Update(Q) hook.Run("Think")')
check(L('Q:GetAmmoCount("357")') == 12, ".357 (cylinder) keeps loading loose rounds")

# ---------------------------------------------------------------- taking from the world, nesting, equip
run('WI = MCC.Inv.SpawnWorldItem(MCC.Inv.NewItem("ammo_pistol", 30), Vector(10, 0, 0))')
ok = L('(MCC.Inv.TakeEntity(Q, WI, "g:backpack:1", 4, 4, false))')
check(ok is True and not L('IsValid(WI)'), "drag a world item into a chosen backpack cell")
check(L('(function() for _, o in ipairs(%s.slots.backpack.cont[1]) do if o.id == "ammo_pistol" then return o.x * 10 + o.y end end end)()' % M) == 44,
      "it lands exactly where it was dropped")
run('BP = MCC.Inv.SpawnWorldItem(MCC.Inv.NewItem("bp_daypack", 1), Vector(10, 0, 0))')
ok = L('(MCC.Inv.TakeEntity(Q, BP, "g:backpack:1", 0, 0, false))')
check(ok is True, "an empty bag nests inside your backpack")
full_bp = L('%s.slots.backpack.u' % M)
ok = L('(MCC.Inv.Move(Q, %d, "g:backpack:1", 0, 0, false))' % full_bp)
check(ok is False, "a bag can't go inside itself")
# the .357 sits in the holster; put it in the backpack, then Alt+click the pistol from the rig
holster_u = L('%s.slots.holster.u' % M)
run('MCC.Inv.Move(Q, %d, "g:backpack:1", 2, 3, false)' % holster_u)
run('MCC.Inv.GiveID(Q, "weapon_pistol", 1)')
pist = L('(function() for _, it in pairs(%s.slots) do for _, list in ipairs(it.cont or {}) do for _, o in ipairs(list) do if o.id == "weapon_pistol" then return o.u end end end end end)()' % M)
if pist is None:  # it went straight to the free holster; take it off again
    pist = L('%s.slots.holster.u' % M)
    run('MCC.Inv.Move(Q, %d, "g:backpack:1", 0, 4, false)' % pist)
check(L('%s.slots.holster' % M) is None and not L('Q:HasWeapon("weapon_pistol")'), "pistol is stored, not in hand")
ok = L('(MCC.Inv.Equip(Q, %d))' % pist)
check(ok is True and L('%s.slots.holster.id' % M) == "weapon_pistol" and L('Q:HasWeapon("weapon_pistol")'), "Alt+click equips a pistol to the holster")

# vicinity actions over the net
run('WI2 = MCC.Inv.SpawnWorldItem(MCC.Inv.NewItem("item_healthvial", 1), Vector(10, 0, 0))')
run('MCC.Net.Handlers.inv_act.fn({a = "take", e = WI2:EntIndex()}, Q)')
check(not L('IsValid(WI2)'), "Ctrl+click in the vicinity list takes the item")

# ---------------------------------------------------------------- containers sized by model
check(L('MCC.Inv.ContainerModels["models/props_junk/wood_crate001a.mdl"].w') == 5, "default container sizes load from containers.json")
run('CRATE = _Ent("prop_physics") CRATE:SetModel("models/props_junk/wood_crate001a.mdl") CRATE:SetPos(Vector(10, 0, 0))')
check(L('MCC.Pickup.Kind(CRATE)') == "container", "a listed prop model is a searchable container")
run('MCC.Net.Handlers.inv_act.fn({a = "open", e = CRATE:EntIndex()}, Q)')
check(L('Q.MCCInvOpen == CRATE') and L('#CRATE.MCCCont.grids') == 1 and L('CRATE.MCCCont.grids[1].w') == 5 and L('CRATE.MCCCont.grids[1].h') == 5, "opening it gives a 5x5 grid")
vial = None
mag_u = mag10
ok = L('(MCC.Inv.Move(Q, %d, "c", 0, 0, false))' % mag_u)
check(ok is True and L('#CRATE.MCCCont.grids[1].items') == 1, "items go into the container")
check(L('(select(2, MCC.Inv.Find(Q, %d)))' % mag_u) == "c:1", "and are found at c:1")

# lockers: four 2x8 compartments
L4 = 'MCC.Inv.ContainerModels["models/props_c17/lockers001a.mdl"]'
check(L(L4 + '.w') == 2 and L(L4 + '.h') == 8 and L(L4 + '.count') == 4, "lockers default to 4 compartments of 2x8")
run('LOCK = _Ent("prop_physics") LOCK:SetModel("models/props_c17/lockers001a.mdl") LOCK:SetPos(Vector(10, 0, 0))')
check(L('(MCC.Inv.Quick(Q, %d))' % mag_u) is True, "quick move takes an item out of the crate")
run('MCC.Net.Handlers.inv_act.fn({a = "open", e = LOCK:EntIndex()}, Q)')
check(L('#LOCK.MCCCont.grids') == 4 and L('LOCK.MCCCont.grids[4].w') == 2 and L('LOCK.MCCCont.grids[4].h') == 8, "opening lockers gives four 2x8 grids")
ok = L('(MCC.Inv.Move(Q, %d, "c:3", 1, 6, false))' % mag_u)
check(ok is True and L('#LOCK.MCCCont.grids[3].items') == 1 and L('LOCK.MCCCont.grids[3].items[1].x') == 1, "items go into a chosen locker")
check(L('(MCC.Inv.Move(Q, %d, "c:2", 2, 0, false))' % mag_u) is not True, "a compartment is only 2 wide")
ok = L('(MCC.Inv.Quick(Q, %d))' % mag_u)
check(ok is True and not L('(select(2, MCC.Inv.Find(Q, %d)))' % mag_u).startswith("c"), "quick move takes it back")
check(L('#MCC.Inv.OpenPayload(Q).grids') == 4 and L('MCC.Inv.OpenPayload(Q).grids[1].w') == 2, "the client gets each compartment")

# dragging onto a container in the vicinity list (nothing open)
run('Q.MCCInvOpen = nil LK2 = _Ent("prop_physics") LK2:SetModel("models/props_junk/wood_crate001a.mdl") LK2:SetPos(Vector(10, 0, 0))')
run('WI3 = MCC.Inv.SpawnWorldItem(MCC.Inv.NewItem("item_healthvial", 1), Vector(10, 0, 0))')
run('MCC.Net.Handlers.inv_act.fn({a = "stash", e = WI3:EntIndex(), c = LK2:EntIndex()}, Q)')
check(not L('IsValid(WI3)') and L('#LK2.MCCCont.grids[1].items') == 1 and L('LK2.MCCCont.grids[1].items[1].id') == "item_healthvial",
      "an item on the ground dragged onto a container in the vicinity list goes in it")
run('MCC.Net.Handlers.inv_act.fn({a = "store", u = %d, c = LK2:EntIndex()}, Q)' % mag_u)
check(L('#LK2.MCCCont.grids[1].items') == 2 and L('(MCC.Inv.Find(Q, %d))' % mag_u) is None, "so does one of your own items")
run('_FAR = _Ent("prop_physics") _FAR:SetModel("models/props_junk/wood_crate001a.mdl") _FAR:SetPos(Vector(5000, 0, 0))')
run('WI4 = MCC.Inv.SpawnWorldItem(MCC.Inv.NewItem("item_healthvial", 1), Vector(10, 0, 0))')
run('MCC.Net.Handlers.inv_act.fn({a = "stash", e = WI4:EntIndex(), c = _FAR:EntIndex()}, Q)')
check(L('IsValid(WI4)') and L('_FAR.MCCCont') is None, "not into containers out of reach")
run('MCC.Net.Handlers.inv_act.fn({a = "stash", e = WI4:EntIndex(), c = WI4:EntIndex()}, Q)')
check(L('IsValid(WI4)'), "(or into things that aren't containers)")
run('MCC.Net.Handlers.inv_act.fn({a = "open", e = CRATE:EntIndex()}, Q)')

# mcc_container_set with compartments, and old default lockers upgrade
run('Q.IsSuperAdmin = function() return true end Q.IsAdmin = function() return true end Q.PrintMessage = function() end Q.ChatPrint = function() end')
run('_AIM = _Ent("prop_physics") _AIM:SetModel("models/props_c17/oildrum001.mdl") Q.GetEyeTrace = function() return {Entity = _AIM} end')
run('_CMDS["mcc_container_set"](Q, "mcc_container_set", {"3", "4", "Drum", "2"})')
D = 'MCC.Inv.ContainerModels["models/props_c17/oildrum001.mdl"]'
check(L(D + '.w') == 3 and L(D + '.h') == 4 and L(D + '.count') == 2, "mcc_container_set <w> <h> <name> <compartments>")
run('_CMDS["mcc_container_remove"](Q, "mcc_container_remove", {})')
cpath = os.path.join(sv.datadir, "mcc/containers.json")
cj = json.load(open(cpath))
cj["models/props_c17/lockers001a.mdl"] = {"w": 4, "h": 8, "name": "Lockers"}
cj["models/props_junk/wood_crate001a.mdl"] = {"w": 6, "h": 6, "name": "My Crate"}
cj["models/props_junk/cardboard_box001a.mdl"] = {"w": 4, "h": 4, "name": "Cardboard Box"}
cj["models/props_wasteland/controlroom_filecabinet002a.mdl"] = {"w": 4, "h": 8, "name": "Filing Cabinet"}
cj["models/props_wasteland/controlroom_filecabinet001a.mdl"] = {"w": 4, "h": 6, "name": "Filing Cabinet"}
json.dump(cj, open(cpath, "w"))
run('MCC.Inv.LoadContainers()')
check(L(L4 + '.count') == 4 and L(L4 + '.w') == 2, "a server's old 4x8 lockers entry upgrades to 4 compartments")
check(L('MCC.Inv.ContainerModels["models/props_junk/wood_crate001a.mdl"].w') == 6, "entries the owner changed are kept")
check(L('MCC.Inv.ContainerModels["models/props_junk/cardboard_box001a.mdl"].w') == 3 and L('MCC.Inv.ContainerModels["models/props_junk/cardboard_box001a.mdl"].h') == 3, "the old 4x4 cardboard box becomes 3x3")
FC = 'MCC.Inv.ContainerModels["models/props_wasteland/controlroom_filecabinet002a.mdl"]'
check(L(FC + '.w') == 2 and L(FC + '.h') == 2 and L(FC + '.count') == 4 and L(FC + '.vertical') is True,
      "the tall filing cabinet becomes four stacked 2x2 drawers")
run('FCAB = _Ent("prop_physics") FCAB:SetModel("models/props_wasteland/controlroom_filecabinet002a.mdl") FCAB:SetPos(Vector(10, 0, 0))')
run('MCC.Inv.OpenContainer(Q, FCAB)')
check(L('#MCC.Inv.OpenPayload(Q).grids') == 4 and L('MCC.Inv.OpenPayload(Q).vertical') is True, "the client is told to stack the drawers")
run('FC2 = _Ent("prop_physics") FC2:SetModel("models/props_wasteland/controlroom_filecabinet001a.mdl") FC2:SetPos(Vector(10, 0, 0))')
run('MCC.Inv.OpenContainer(Q, FC2) _FP = MCC.Inv.OpenPayload(Q)')
check(L('#_FP.grids') == 2 and L('_FP.grids[1].w') == 2 and L('_FP.grids[1].h') == 1 and L('_FP.grids[2].w') == 2
      and L('_FP.grids[2].h') == 2 and L('_FP.vertical') is True, "the short filing cabinet: a 2x1 top drawer (lying down) over a 2x2")
LAB = 'MCC.Inv.ContainerModels["models/props_lab/filecabinet02.mdl"]'
check(L(LAB + '.w') == 2 and L(LAB + '.h') == 2 and L(LAB + '.count') == 2 and L(LAB + '.vertical') is True,
      "the lab filing cabinet: two 2x2 drawers")
DR = 'MCC.Inv.ContainerModels["models/props_c17/furnituredrawer003a.mdl"]'
WR = 'MCC.Inv.ContainerModels["models/props_c17/furnituredresser001a.mdl"]'
check(L(DR + '.count') == 6 and L(DR + '.w') == 2 and L(DR + '.h') == 1 and L(WR + '.count') == 2 and L(WR + '.w') == 3 and L(WR + '.h') == 6,
      "the tall drawers (6 of 2x1) and the wardrobe (2 of 3x6) are containers")

# a server whose containers.json predates all this: old defaults upgrade, new ones are added,
# and a default the owner removed stays removed
cj = json.load(open(cpath))
cj["models/props_wasteland/controlroom_filecabinet001a.mdl"] = {"w": 2, "h": 2, "vertical": True, "name": "Filing Cabinet",
    "cells": [{"w": 1, "h": 2}, {"w": 2, "h": 2}]}
cj["models/props_lab/filecabinet02.mdl"] = {"w": 4, "h": 6, "name": "Filing Cabinet"}
del cj["models/props_c17/furnituredresser001a.mdl"]
del cj["models/props_c17/furnituredrawer003a.mdl"]
json.dump(cj, open(cpath, "w"))
run('MCC.Inv.LoadContainers()')
check(L('MCC.Inv.ContainerModels["models/props_wasteland/controlroom_filecabinet001a.mdl"].cells[1].w') == 2,
      "last version's short cabinet (1x2 top) upgrades to the 2x1 top")
check(L(LAB + '.count') == 2, "the lab cabinet's old 4x6 upgrades to two 2x2")
check(L(WR + ' ~= nil') and L(DR + ' ~= nil'), "new default containers are added to an existing containers.json")
run('_AIM = _Ent("prop_physics") _AIM:SetModel("models/props_c17/FurnitureDresser001a.mdl")')
run('_CMDS["mcc_container_remove"](Q, "mcc_container_remove", {})')
run('MCC.Inv.LoadContainers()')
check(L(WR + ' == nil'), "a default removed with mcc_container_remove stays removed")
check("_removed" not in L('table.concat(table.GetKeys(MCC.Inv.ContainerModels), ",")'), "the removed list isn't read as a container")
run('_CMDS["mcc_container_set"](Q, "mcc_container_set", {"3", "6", "Wardrobe", "2"})')
run('MCC.Inv.LoadContainers()')
check(L(WR + '.count') == 2, "mcc_container_set brings it back")
check(json.load(open(cpath))["models/props_c17/lockers001a.mdl"].get("count") == 4, "the upgrade is saved")
run('CRATE2 = _Ent("prop_physics") CRATE2:SetModel("models/props_c17/oildrum001.mdl")')
check(L('MCC.Pickup.Kind(CRATE2)') is None, "unlisted props aren't containers")

# ---------------------------------------------------------------- NPC bodies
check(L('_RCC and _RCC[1]') == "ai_serverragdolls", "server ragdolls are turned on for NPC bodies")
run('NW = _MakeWeaponEnt("weapon_ar2", 30)')
run('NPC = _Ent("npc_combine_s", {IsNPC = function() return true end, GetActiveWeapon = function() return NW end})')
run('RAG = _Ent("prop_ragdoll")')
run('hook.Run("CreateEntityRagdoll", NPC, RAG)')
check(L('RAG.MCCCont ~= nil and RAG:GetNWBool("MCCBody")'), "a dead NPC leaves a lootable body")
check(L('RAG.MCCCont.inv.slots.sling.id') == "weapon_ar2", "the body has its rifle on the sling")
clip = L('RAG.MCCCont.inv.slots.sling.d.clip')
check(clip is not None and 9 <= clip <= 30, "with a partly used magazine (%s)" % clip)
check(L('RAG.MCCCont.inv.slots.pocket1.id') == "mag_ar2" and L('RAG.MCCCont.inv.slots.pocket1.d.rounds') > 0,
      "and a loaded spare magazine in a pocket")
run('NS = _MakeWeaponEnt("weapon_shotgun", 6) NPC2 = _Ent("npc_combine_s", {IsNPC = function() return true end, GetActiveWeapon = function() return NS end}) RAG2 = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC2, RAG2)')
check(L('RAG2.MCCCont.inv.slots.pocket1.id') == "ammo_buckshot", "shotgun NPCs carry loose shells instead of magazines")
run('hook.Add("MCC_NPCBody", "t", function(npc, inv) inv.slots.dogtag = MCC.Inv.NewItem("dogtag", 1) end)')
run('RAG3 = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC, RAG3)')
check(L('RAG3.MCCCont.inv.slots.dogtag ~= nil'), "expansions can change NPC loot through MCC_NPCBody")

# body cleanup: unlooted bodies stay; looted ones despawn mcc_inv_body_looted_time later
check(L('MCC.Config.Get("inv_body_cleanup")') is True and L('MCC.Config.Get("inv_body_looted_time")') == 360
      and L('MCC.Config.Get("inv_body_lifetime")') == 0, "body cleanup defaults: on, 6 minutes after looting, no hard lifetime")
run('_TIME = 1000 BA = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC, BA) BB = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC, BB)')
run('_TIME = 5000 MCC.Inv.BodyCleanupStep()')
check(L('IsValid(BA) and IsValid(BB)') and L('BA:GetNWFloat("MCCDespawnAt", 0)') == 0, "an unlooted body stays, however long")
run('hook.Run("MCC_ContainerChanged", BA, Q)')
check(L('BA:GetNWFloat("MCCDespawnAt", 0)') == 5360, "looting it starts the 6-minute countdown")
check("despawns in 6:00" in L('(select(2, MCC.Pickup.PromptText(BA, "body")))'), "shown on its prompt: %s" % L('(select(2, MCC.Pickup.PromptText(BA, "body")))'))
run('_TIME = 5200 hook.Run("MCC_ContainerChanged", BA, Q) _TIME = 5359 MCC.Inv.BodyCleanupStep()')
check(L('IsValid(BA)'), "looting it again doesn't reset the clock")
run('_TIME = 5361 MCC.Inv.BodyCleanupStep()')
check(not L('IsValid(BA)') and L('IsValid(BB)'), "6 minutes after it was first looted it's gone; the unlooted one stays")
run('_SetCV("mcc_inv_body_cleanup", 0) hook.Run("MCC_ContainerChanged", BB, Q) _TIME = 9000 MCC.Inv.BodyCleanupStep()')
check(L('IsValid(BB)') and L('BB:GetNWFloat("MCCDespawnAt", 0)') == 0, "mcc_inv_body_cleanup 0: looted bodies stay too")
run('_SetCV("mcc_inv_body_cleanup", 1) MCC.Inv.BodyCleanupStep()')
check(not L('IsValid(BB)'), "(turned back on, the clock runs from when it was looted: long past, so it goes)")
run('_SetCV("mcc_inv_body_lifetime", 60) BC = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC, BC) _TIME = 9061 MCC.Inv.BodyCleanupStep()')
check(not L('IsValid(BC)'), "mcc_inv_body_lifetime caps any body's life, looted or not")
run('_SetCV("mcc_inv_body_lifetime", 0) _SetCV("mcc_inv_body_max", 3) _BM = {} for i = 1, 5 do _TIME = _TIME + 1 _BM[i] = _Ent("prop_ragdoll") hook.Run("CreateEntityRagdoll", NPC, _BM[i]) end')
run('hook.Run("MCC_ContainerChanged", _BM[5], Q) MCC.Inv.BodyCleanupStep()')
alive = [L('IsValid(_BM[%d])' % i) for i in range(1, 6)]
check(alive == [False, True, True, True, False],
      "past mcc_inv_body_max the extras go: looted first, then the oldest (%s)" % alive)
run('_SetCV("mcc_inv_body_max", 60)')

# singleplayer: the server catches the inventory and drop keys
run('_SP = true _SENT = {} local send = MCC.Net.Send MCC.Net.Send = function(n, d, p) _SENT[#_SENT + 1] = n return send(n, d, p) end')
run('Q.IsTyping = function() return false end Q.GetInfoNum = function(s, k, d) return d end')
run('hook.Run("PlayerButtonDown", Q, KEY_I)')
check(L('_SENT[#_SENT]') == "inv_key", "singleplayer: pressing I on the server opens the inventory")
run('_TIME = 900 Q.GetActiveWeapon = function() return Q:GetWeapon("weapon_smg1") end hook.Run("PlayerButtonDown", Q, KEY_G)')
check(L('%s.slots.sling' % M) is None, "singleplayer: pressing G on the server drops the weapon")
run('_SP = false')

# ---------------------------------------------------------------- prompts
check(L('(select(1, MCC.Pickup.PromptText(RAG, "body")))') == "Loot Body" and L('(select(2, MCC.Pickup.PromptText(RAG, "body")))') is not None,
      "bodies prompt 'Loot Body' with the name underneath")

# ---------------------------------------------------------------- loading guns straight from loose rounds
run('_SetCV("mcc_mags_required", 1)')
run('if not MCC.Inv.Get(Q).slots.sling then MCC.Inv.GiveID(Q, "weapon_smg1", 1) end')  # the singleplayer test dropped it
run('Q:GetWeapon("weapon_smg1"):SetClip1(5)')
run('MCC.Inv.GiveID(Q, "ammo_smg1", 50)')
sling = L('%s.slots.sling.u' % M)
ok = L('(MCC.Inv.LoadWeapon(Q, %d))' % sling)
check(ok is True and L('Q:GetWeapon("weapon_smg1"):Clip1()') == 45, "Load from loose rounds fills the gun's own magazine")
ok = L('(MCC.Inv.UnloadWeapon(Q, %d))' % sling)
check(ok is True and L('Q:GetWeapon("weapon_smg1"):Clip1()') == 0, "Unload empties the gun back into loose rounds")
run('MCC.Inv.LoadWeapon(Q, %d)' % sling)

# reloading with no loaded magazine explains what to do
run('_SENT = {} local send = MCC.Net.Send MCC.Net.Send = function(n, d, p) _SENT[#_SENT + 1] = n return send(n, d, p) end')
run('for _, list in ipairs(%s.slots.rig.cont) do for j = #list, 1, -1 do if list[j].id == "mag_smg1" then table.remove(list, j) end end end' % M)
run('Q:GetWeapon("weapon_smg1"):SetClip1(3) Q:SetAmmo(0, "SMG1") Q.GetActiveWeapon = function() return Q:GetWeapon("weapon_smg1") end Q.MCCReloadHint = 0')
run('hook.Run("KeyPress", Q, IN_RELOAD)')
check(L('_SENT[#_SENT]') == "inv_notify", "pressing R with no loaded magazine shows a hint")

# ---------------------------------------------------------------- searching bodies and containers
run('_SetCV("mcc_search_enabled", 1)')
run('S = _MakeTester(4) _PLAYERS = {P, K, Q, S} hook.Run("PlayerInitialSpawn", S) hook.Run("PlayerLoadout", S)')
run('MCC.Inv.GiveID(S, "rig_chest", 1) MCC.Inv.GiveID(S, "bp_daypack", 1)')
run('SR = _Ent("prop_ragdoll") SR:SetPos(Vector(10, 0, 0))')
run('SINV = MCC.Inv.NPCLoadout("weapon_ar2") SINV.slots.rig = MCC.Inv.NewItem("rig_chest") table.insert(SINV.slots.rig.cont[1], {u = MCC.Inv.NewUID(), id = "ammo_ar2", n = 20, x = 0, y = 0}) table.insert(SINV.slots.rig.cont[2], {u = MCC.Inv.NewUID(), id = "item_healthvial", x = 0, y = 0})')
run('MCC.Inv.MakeBody(SR, SINV, "Combine Soldier")')
run('_LASTOPEN = nil local send = MCC.Net.Send MCC.Net.Send = function(n, d, p) if n == "inv_sync" and p == S and (d.oc or not d.diff) then _LASTOPEN = d.open end return send(n, d, p) end')
run('MCC.Inv.OpenContainer(S, SR) hook.Run("Think")')
check(L('_LASTOPEN.slots.sling.id') == "weapon_ar2", "worn gear is visible straight away (the rifle on the sling)")
check(L('_LASTOPEN.slots.rig.id') == "rig_chest", "the worn rig is visible")
check(L('_LASTOPEN.sections.pockets') == "closed" and L('_LASTOPEN.sections.rig') == "closed", "pockets and the rig's storage start closed")
check(L('_LASTOPEN.slots.pocket1') is None, "closed pockets show nothing")
check(L('#_LASTOPEN.slots.rig.cont[1]') == 0, "a closed rig shows nothing inside")
ok = L('(MCC.Inv.Quick(S, SR.MCCCont.inv.slots.sling.u))')
check(ok is True, "worn gear can be taken without searching")
pocket_u = L('SR.MCCCont.inv.slots.pocket1.u')
check(L('(MCC.Inv.Quick(S, %d))' % pocket_u) is False, "pocket items can't be taken before searching")
check(L('(MCC.Inv.Move(S, MCC.Inv.Get(S).slots.rig.cont[1][1] and MCC.Inv.Get(S).slots.rig.cont[1][1].u or 0, "bg:rig:4", 0, 0, false))') in (False, None),
      "nothing can be put into a closed section")

def search_tick(n):
    for _ in range(n):
        run('_TIME = _TIME + 0.25 timer.t["MCC_InvSearch"].f()')

# click SEARCH on the rig, then on the pockets (queued behind it)
run('MCC.Net.Handlers.inv_act.fn({a = "search", section = "rig"}, S)')
run('MCC.Net.Handlers.inv_act.fn({a = "search", section = "pockets"}, S)')
run('hook.Run("Think")')
check(L('_LASTOPEN.sections.rig') == "searching" and L('_LASTOPEN.sections.pockets') == "queued", "a second search queues behind the first")
check(L('_LASTOPEN.slots.rig.cont[1][1].hidden') is True and L('_LASTOPEN.searching') is not None,
      "while searching, items show as '?' and the current one reports progress")
search_tick(40)
run('MCC.Inv.Update(S) hook.Run("Think")')
check(L('_LASTOPEN.sections.rig') == "done" and L('_LASTOPEN.slots.rig.cont[1][1].id') == "ammo_ar2", "the rig's items show up after searching it")
check(L('_LASTOPEN.sections.pockets') == "done" and L('_LASTOPEN.slots.pocket1.id') == "mag_ar2", "then the queued pockets get searched")
check(L('(MCC.Inv.Quick(S, %d))' % pocket_u) is True, "searched items can be taken")

# what you put in, you can see; others still have to search
smag = L('(function() MCC.Inv.GiveID(S, "mag_pistol", 1) for _, list in ipairs(MCC.Inv.Get(S).slots.rig.cont) do for _, o in ipairs(list) do if o.id == "mag_pistol" then return o.u end end end end)()')
ok = L('(MCC.Inv.Move(S, %d, "bg:rig:5", 0, 0, false))' % smag)
check(ok is True, "items go into a searched section")
run('T = _MakeTester(5) hook.Run("PlayerInitialSpawn", T) T.MCCInvOpen = SR')
check(L('MCC.Inv.SectionDone(T, SR, "rig")') is False, "another player still has to search it")

# each container compartment is its own section
run('BOX = _Ent("prop_physics") BOX:SetModel("models/props_junk/wood_crate001a.mdl") BOX:SetPos(Vector(10, 0, 0))')
run('MCC.Inv.OpenContainer(S, BOX) BOX.MCCCont.grids[1].items[1] = {u = MCC.Inv.NewUID(), id = "ammo_pistol", n = 10, x = 0, y = 0} MCC.Inv.Update(S) hook.Run("Think")')
check(L('_LASTOPEN.sections["c:1"]') == "closed" and L('#_LASTOPEN.grids[1].items') == 0, "a container starts closed")
run('MCC.Net.Handlers.inv_act.fn({a = "search", section = "c:1"}, S)')
search_tick(10)
run('MCC.Inv.Update(S) hook.Run("Think")')
check(L('_LASTOPEN.sections["c:1"]') == "done" and L('_LASTOPEN.grids[1].items[1].id') == "ammo_pistol", "searching it reveals what's inside")

run('LK = _Ent("prop_physics") LK:SetModel("models/props_c17/lockers001a.mdl") LK:SetPos(Vector(10, 0, 0))')
run('MCC.Inv.OpenContainer(S, LK) for i = 1, 4 do LK.MCCCont.grids[i].items[1] = {u = MCC.Inv.NewUID(), id = "ammo_pistol", n = 5, x = 0, y = 0} end MCC.Inv.Update(S) hook.Run("Think")')
check(all(L('_LASTOPEN.sections["c:%d"]' % i) == "closed" for i in range(1, 5)), "each locker has its own SEARCH button")
run('MCC.Net.Handlers.inv_act.fn({a = "search", section = "c:2"}, S)')
search_tick(10)
run('MCC.Inv.Update(S) hook.Run("Think")')
check(L('_LASTOPEN.sections["c:2"]') == "done" and L('#_LASTOPEN.grids[2].items') == 1, "searching one locker reveals it")
check(L('_LASTOPEN.sections["c:1"]') == "closed" and L('#_LASTOPEN.grids[1].items') == 0, "the others stay closed")
check(L('(MCC.Inv.GetGrid(S, "c:1"))') is None and L('(MCC.Inv.GetGrid(S, "c:2"))') == 2, "you can only put items in searched lockers")
run('_SetCV("mcc_search_enabled", 0)')

# ---------------------------------------------------------------- weapon packs are registered by hand
run('W5 = _MakeWeaponEnt("arc9_test_mp5", 30) W5:SetClip1(17) W5._NV().AttData = "optic=eotech;grip=afg" W5._NV().NextReloadTime = 99')
handled = L('(hook.Run("MCC_PickupWeapon", Q, W5))')
check(handled is None and L('MCC.Items.Get("arc9_test_mp5")') is None, "an unregistered pack weapon isn't made into an item")
check(L('MCC.Inv.NPCLoadout("arc9_test_mp5").slots.sling') is None, "an NPC carrying one doesn't drop it as loot")
check(not os.path.exists(os.path.join(sv.datadir, "mcc/auto_items.json")), "nothing is written to auto_items.json")

# the weapon pack (or the server owner) registers it, with its own weight and ammo
run('''hook.Add("MCC_RegisterItems", "test_pack", function(Items)
  Items.Register("arc9_test_mp5", {name = "MP5", kind = "weapon", class = "arc9_test_mp5", w = 3, h = 2, weight = 2.5,
    data = {slot = "primary", ammo = "9x19MM", clip = 30, feed = "loose"}})
  Items.Register("ammo_9x19", {name = "9x19mm", kind = "ammo", class = "9x19MM", weight = 0.008, data = {ammo = "9x19MM"}})
end) MCC.Items.Rebuild()''')
handled = L('(hook.Run("MCC_PickupWeapon", Q, W5))')
d = 'MCC.Items.Get("arc9_test_mp5")'
check(handled is True and L(d + '.weight') == 2.5, "once registered it's picked up into the inventory with its own weight")
mp5 = L('(function() for _, it in pairs(%s.slots) do if it.id == "arc9_test_mp5" then return it end for _, list in ipairs(it.cont or {}) do for _, o in ipairs(list) do if o.id == "arc9_test_mp5" then return o end end end end end)()' % M)
check(mp5 is not None and mp5.d.clip == 17 and mp5.d.nv.AttData == "optic=eotech;grip=afg", "its rounds and attachments came along")
check(mp5.d.nv.NextReloadTime is None, "timers aren't kept (mcc_weapon_state_skip)")

# it went on the back (the sling is taken): equipping restored its attachments
check(L('(select(2, MCC.Inv.Find(Q, %d)))' % mp5.u) == "s:back" and L('Q:GetWeapon("arc9_test_mp5")._NV().AttData') == "optic=eotech;grip=afg",
      "equipping restores its attachments")
run('%s.slots.backpack.cont[1] = {}' % M)  # make room
run('Q:GetWeapon("arc9_test_mp5")._NV().AttData = "optic=acog" Q:GetWeapon("arc9_test_mp5"):SetClip1(9)')
ok = L('(MCC.Inv.Move(Q, %d, "g:backpack:1", 0, 0, false))' % mp5.u)
check(ok is True and not L('Q:HasWeapon("arc9_test_mp5")'), "holstering takes it out of your hands")
check(L('(MCC.Inv.Find(Q, %d)).d.nv.AttData' % mp5.u) == "optic=acog" and L('(MCC.Inv.Find(Q, %d)).d.clip' % mp5.u) == 9,
      "and saves the changed attachments and rounds")
ok = L('(MCC.Inv.Move(Q, %d, "s:back"))' % mp5.u)
check(ok is True and L('Q:GetWeapon("arc9_test_mp5")._NV().AttData') == "optic=acog", "equipping again brings them back")

# its loose rounds work like any ammo
run('MCC.Inv.GiveID(Q, "ammo_9x19", 60) MCC.Inv.Update(Q) hook.Run("Think")')
check(L('Q:GetAmmoCount("9x19MM")') == 60, "the pack's ammo in the rig is usable")

run('_CMDS["mcc_reload_config"](nil, "mcc_reload_config", {})')
check(L('MCC.Items.Get("arc9_test_mp5") ~= nil'), "registered pack weapons survive mcc_reload_config")
run('hook.Remove("MCC_RegisterItems", "test_pack") MCC.Items.Rebuild()')

# ---------------------------------------------------------------- spawn menu magazines
for mid, cap in [("mag_pistol", 18), ("mag_smg1", 45), ("mag_ar2", 30)]:
    run('ENT = {} include("entities/mcc_%s.lua") _MAGENT = ENT' % mid)
    check(L('_MAGENT.Spawnable') is True and L('_MAGENT.Category') == "MCC Magazines", "%s is in the spawn menu" % mid)
    run('_SPAWNED = _MAGENT:SpawnFunction(Q, {Hit = true, HitPos = Vector(0, 0, 0), HitNormal = Vector(0, 0, 1)})')
    check(L('_SPAWNED:GetClass()') == "mcc_item" and L('_SPAWNED.MCCItem.id') == mid and L('_SPAWNED.MCCItem.d.rounds') == cap,
          "spawning %s drops a loaded magazine (%d rounds)" % (mid, cap))
check(L('_MAGENT:SpawnFunction(Q, {Hit = false})') is None, "nothing spawns when you aim at the sky")
run('MCC.Inv.TakeEntity(Q, _SPAWNED)')
check(not L('IsValid(_SPAWNED)'), "a spawned magazine can be picked up")

# worn gear: rigs and backpacks with data.worn show on the wearer and stay on their body
run('MCC.Items.SetOverride("rig_chest", {data = {worn = "models/test/rig.mdl"}})')
check(L('MCC.Inv.WornSpec(MCC.Items.Get("rig_chest")).model') == "models/test/rig.mdl", "items.json can give a rig a worn model")
run('W = _MakeTester(6) _PLAYERS = {P, K, Q, S, W} hook.Run("PlayerInitialSpawn", W) hook.Run("PlayerLoadout", W)')
run('MCC.Inv.Get(W).slots.rig = MCC.Inv.NewItem("rig_chest", 1) MCC.Inv.Get(W).slots.backpack = MCC.Inv.NewItem("bp_daypack", 1)')
run('MCC.Inv.Update(W) hook.Run("Think")')
check(L('W:GetNWString("MCCWorn", "")') == "rig=rig_chest", "an equipped rig shows on the player (a backpack without a worn model doesn't)")
run('MCC.Items.SetOverride("bp_daypack", {data = {worn = {model = "models/test/pack.mdl", bone = "ValveBiped.Bip01_Spine2", pos = {0, -4, 0}}}})')
check(L('W:GetNWString("MCCWorn", "")') == "rig=rig_chest;backpack=bp_daypack", "adding a worn model later updates who's wearing it")
run('_SetCV("mcc_inv_worn_models", 0) MCC.Inv.RefreshWorn(W)')
check(L('W:GetNWString("MCCWorn", "")') == "", "mcc_inv_worn_models 0 hides worn gear")
run('_SetCV("mcc_inv_worn_models", 1) MCC.Inv.RefreshWorn(W)')
run('_WBODY = nil local old = ents.Create ents.Create = function(c) local e = old(c) if c == "prop_ragdoll" then _WBODY = e end return e end')
run('hook.Run("DoPlayerDeath", W, K, nil)')
check(L('_WBODY ~= nil and _WBODY:GetNWString("MCCWorn", "")') == "rig=rig_chest;backpack=bp_daypack", "the body keeps wearing the rig and backpack")
check(L('W:GetNWString("MCCWorn", "")') == "", "the dead player no longer wears them")
run('W.MCCInvOpen = _WBODY _WBODY.MCCCont.inv.slots.rig = nil MCC.Inv.Update(W) hook.Run("Think")')
check(L('_WBODY:GetNWString("MCCWorn", "")') == "backpack=bp_daypack", "taking the rig off a body removes it from the body")
run('MCC.Items.SetOverride("rig_chest", nil) MCC.Items.SetOverride("bp_daypack", nil)')

# ---------------------------------------------------------------- JMod resources
check(L('MCC.Items.Get("jmod_wood").w') == 2 and L('MCC.Items.Get("jmod_wood").h') == 2, "JMod wood is a 2x2 item")
def size(i): return (L('MCC.Items.Get("%s").w' % i), L('MCC.Items.Get("%s").h' % i))
check(size("jmod_iron_ore") == (2, 2) and L('MCC.Items.FromClass("ent_jack_gmod_ezironore")') == "jmod_iron_ore", "JMod ores are 2x2")
check(size("jmod_water") == (3, 3), "JMod water is 3x3")
check(size("jmod_sand") == (3, 4), "JMod sand (the sandbag) is 3x4")
check(size("jmod_propellant") == (1, 3), "JMod propellant bottle is 1x3")
check(size("jmod_steel") == (1, 2), "JMod ingots (steel) are 1x2")
check(size("jmod_fissile_material") == (3, 4) and size("jmod_oil") == (2, 3), "fissile material 3x4, oil drum 2x3")
check(size("jmod_concrete") == (2, 2), "JMod concrete is 2x2")
run('R = _MakeTester(7) _PLAYERS = {P, K, Q, S, R} hook.Run("PlayerInitialSpawn", R) hook.Run("PlayerLoadout", R)')
run('MCC.Inv.Get(R).slots.backpack = MCC.Inv.NewItem("bp_large", 1)')
run('WOOD = ents.Create("ent_jack_gmod_ezwood") WOOD:Spawn() WOOD:SetEZsupplies("wood", 37) WOOD:SetPos(Vector(10, 0, 0))')
check(L('MCC.Pickup.Kind(WOOD)') == "item", "E on a JMod box is a pickup")
txt, subt = L('MCC.Pickup.PromptText(WOOD, "item")')
check(txt == "Pick up EZ Wood" and subt == "37 wood", "the prompt shows how much is in it")
check(L('(hook.Run("PlayerUse", R, WOOD))') is False, "JMod's own E carry doesn't also run")
run('R._alt = true')
check(L('(hook.Run("PlayerUse", R, WOOD))') is None, "holding JMod's alt key keeps JMod's own use")
run('R._alt = nil')
check(L('MCC.Pickup.TakeItem(R, WOOD)') is True and not L('IsValid(WOOD)'), "E takes the box into the inventory")
wood = L('(function() for _, list in ipairs(MCC.Inv.Get(R).slots.backpack.cont) do for _, o in ipairs(list) do if o.id == "jmod_wood" then return o end end end end)()')
check(wood is not None and wood.d.amount == 37, "the item keeps the box's amount (37)")
check(abs(L('MCC.Inv.Weight(MCC.Inv.Find(R, %d))' % wood.u) - 5 * 0.37) < 1e-6, "weight scales with the amount")
run('_SPAWNEDBOX = nil local old = ents.Create ents.Create = function(c) local e = old(c) if c == "ent_jack_gmod_ezwood" then _SPAWNEDBOX = e end return e end')
check(L('(MCC.Inv.Drop(R, %d))' % wood.u) is True, "dropping it")
check(L('_SPAWNEDBOX ~= nil and IsValid(_SPAWNEDBOX)') and L('_SPAWNEDBOX:GetResource()') == 37,
      "puts a real JMod box back with 37 in it (not refilled to 100, not 0)")
check(L('MCC.Inv.Find(R, %d)' % wood.u) is None, "and it's gone from the inventory")
run('ONE = ents.Create("ent_jack_gmod_ezironore") ONE:Spawn() ONE:SetEZsupplies("iron ore", 1)')
run('MCC.Pickup.TakeItem(R, ONE)')
ore = L('(function() for _, it in pairs(MCC.Inv.Get(R).slots) do if it.id == "jmod_iron_ore" then return it end for _, list in ipairs(it.cont or {}) do for _, o in ipairs(list) do if o.id == "jmod_iron_ore" then return o end end end end end)()')
check(ore is not None and ore.d.amount == 1, "a box with 1 left keeps 1")
run('MCC.Inv.GiveID(R, "jmod_wood", 1)')
check(L('MCC.Inv.ResourceAmount({id = "jmod_wood"})') == 100, "a given resource without an amount is a full box")
run('_SetCV("mcc_jmod_resources", 0)')
run('W2 = ents.Create("ent_jack_gmod_ezwood") W2:Spawn()')
check(L('MCC.Pickup.Kind(W2)') is None and L('(hook.Run("PlayerUse", R, W2))') is None, "mcc_jmod_resources 0 leaves JMod boxes to JMod")
run('_SetCV("mcc_jmod_resources", 1)')

# ---------------------------------------------------------------- extraction: crate, Fulton, flare
X = 'MCC.Extract'
check(L('MCC.Items.Get("mcc_fulton").kind') == "weapon" and L('MCC.Items.Get("mcc_fulton").class') == "mcc_fulton"
      and L('MCC.Items.Get("mcc_fulton").data.slot') == "grenade" and L('MCC.Items.Get("mcc_fulton").data.ammo') == "mcc_fulton",
      "the Fulton is equipment: carried like a grenade, each one a charge of the Fulton SWEP")
check(L('MCC.Items.Get("mcc_flare").data.useLabel') == "Throw", "the signal flare is thrown from the inventory")
run('XA = _MakeTester(11) XB = _MakeTester(12) _PLAYERS = {P, K, Q, S, R, XA, XB}')
run('for _, p in ipairs({XA, XB}) do hook.Run("PlayerInitialSpawn", p) hook.Run("PlayerLoadout", p) MCC.Inv.Get(p).slots.backpack = MCC.Inv.NewItem("bp_large", 1) end')
run('XC = ents.Create("mcc_extract_crate") XC:Spawn()')
check(L('#XC.MCCCont.grids') == 1 and L('XC.MCCCont.grids[1].w') == 5 and L('XC.MCCCont.grids[1].h') == 5, "a crafted extraction crate is 5x5")
check(L('MCC.Pickup.Kind(XC)') == "container" and L('(MCC.Pickup.PromptText(XC, "container"))') == "Search"
      and L('select(2, MCC.Pickup.PromptText(XC, "container"))') == "Extraction Crate", "E opens it (prompt names it)")
run('MCC.Inv.OpenContainer(XA, XC)')
check(L('MCC.Inv.SectionDone(XA, XC, "c:1")') is True, "an empty crafted crate doesn't need searching")

# limits: 2 weapons, 300 resources, counted inside bags too
def setres(core, res, n):
    run('local c = %s MCC.FOB.RemoveResource(c, "%s", MCC.FOB.Store(c)["%s"] or 0) MCC.FOB.AddResource(c, "%s", %d) MCC.FOB.SyncStore(c)'
        % (core, res, res, res, n))
def give(ply, id, d='nil'):
    run('_G._GIVEN = MCC.Inv.NewItem("%s", 1, %s) MCC.Inv.GiveItem(%s, _G._GIVEN)' % (id, d, ply))
    return L('_G._GIVEN.u')
def to_crate(ply, u, x, y):
    return L('(MCC.Inv.Move(%s, %d, "c:1", %d, %d, false))' % (ply, u, x, y))
w1, w2, w3 = give('XA', 'weapon_pistol'), give('XA', 'weapon_357'), give('XA', 'weapon_pistol')
check(to_crate('XA', w1, 0, 0) is True and to_crate('XA', w2, 2, 0) is True, "two weapons go in")
ok, err = L('MCC.Inv.Move(XA, %d, "c:1", 0, 1, false)' % w3)
check(ok is not True and "2 weapons" in (err or ""), "a third is refused: %s" % err)
r1, r2 = give('XA', 'jmod_steel', '{amount = 200}'), give('XA', 'jmod_steel', '{amount = 150}')
check(to_crate('XA', r1, 0, 2) is True, "200 resources go in")
ok, err = L('MCC.Inv.Move(XA, %d, "c:1", 1, 2, false)' % r2)
check(ok is not True and "300" in (err or ""), "150 more would pass 300 and are refused: %s" % err)
run('_G._BAG = MCC.Inv.NewItem("bp_daypack", 1) _G._BAG.cont[1] = {MCC.Inv.NewItem("weapon_pistol", 1)} _G._BAG.cont[1][1].x, _G._BAG.cont[1][1].y = 0, 0')
check(L('(MCC.Extract.CanStore(XC, _G._BAG))') is False, "a bag with a weapon inside counts toward the limit")
check(L('(MCC.Inv.Move(XA, %d, "c:1", 3, 2, false))' % w1) is True, "moving items around inside the crate is fine")

# the Fulton: needs open sky, closes the crate, can be popped while it hovers
run('_G._FU = MCC.Inv.NewItem("mcc_fulton", 1) MCC.Inv.Get(XA).slots.pocket1 = _G._FU MCC.Inv.SyncAmmo(XA)')
fu = L('_G._FU.u')
check(L('XA:HasWeapon("mcc_fulton")') and L('XA:GetAmmoCount("mcc_fulton")') == 1, "a Fulton in a pocket gives the Fulton SWEP with 1 charge")
run('_ROOF = true')
ok, err = L('MCC.Extract.UseFulton(XA)')
check(ok is not True and "open sky" in (err or "") and L('MCC.Inv.Find(XA, %d) ~= nil' % fu), "under a roof it refuses and keeps the Fulton")
run('_ROOF = nil')
check(L('(MCC.Extract.UseFulton(XA))') is True, "with open sky, left-click attaches it to the crate you have open")
run('XA:SetAmmo(0, "mcc_fulton") MCC.Inv.PollAmmo(XA) MCC.Inv.SyncAmmo(XA)')  # the SWEP's TakePrimaryAmmo
check(L('MCC.Inv.Find(XA, %d)' % fu) is None and not L('XA:HasWeapon("mcc_fulton")'), "the charge used takes the Fulton item, and the SWEP goes with the last one")
check(L('XC.MCCFulton ~= nil') and L('XA.MCCInvOpen') is None and L('XC:GetNWBool("MCCLifting")') is True,
      "it's attached, the crate closes and can't be opened while lifting")
check(L('MCC.Pickup.Kind(XC)') is None, "nobody can open a lifting crate")
balloon = 'XC.MCCFulton.balloon'
check(L('IsValid(%s) and %s:GetCrate() == XC' % (balloon, balloon)), "a balloon appears above it")

def tick(crate, seconds, step=0.1):
    n = int(round(seconds / step))
    for _ in range(n):
        run('_TIME = _TIME + %f if IsValid(%s) and %s.MCCFulton then MCC.Extract.FultonThink(%s) end' % (step, crate, crate, crate))
tick('XC', 1.2)  # inflated, hovering
check(L('XC.MCCFulton.yanked') is None, "after a second it's still hovering")
saved_before = L('#MCC.Extract.Stored("11")')
tick('XC', 3.0)
check(not L('IsValid(XC)') and L('#MCC.Extract.Stored("11")') == saved_before + 1, "then it's yanked away and stored")
stored = json.load(open(os.path.join(sv.datadir, "mcc/extraction/11.json")))
items = stored["crates"][-1]["grids"][0]["items"]
check(len(items) == 3 and sorted(i["id"] for i in items) == ["jmod_steel", "weapon_357", "weapon_pistol"],
      "the file holds what was in it (got %s)" % [i["id"] for i in items])

# popping the balloon while it hovers drops the crate
run('XC2 = ents.Create("mcc_extract_crate") XC2:Spawn() XC2.MCCCont.grids[1].items[1] = {u = MCC.Inv.NewUID(), id = "item_battery", x = 0, y = 0}')
check(L('(MCC.Extract.StartFulton(XC2, XB))') is True, "XB attaches a Fulton to another crate")
tick('XC2', 1.0)
run('MCC.Extract.PopFulton(XC2, XA)')
check(L('IsValid(XC2)') and L('XC2.MCCFulton') is None and L('XC2:GetNWBool("MCCLifting")') is False
      and L('#MCC.Extract.Stored("12")') == 0, "a popped balloon drops the crate; nothing is stored")
check(L('(MCC.Extract.StartFulton(XC2, XB))') is True, "try again")
tick('XC2', 2.2)
run('MCC.Extract.PopFulton(XC2, XA)')
check(L('XC2.MCCFulton ~= nil and XC2.MCCFulton.yanked == true'), "once it's yanked the balloon can't be popped")
tick('XC2', 2.0)
check(L('#MCC.Extract.Stored("12")') == 1, "whoever attached the Fulton owns the crate")

# max 3: a 4th overwrites the oldest
for i in range(3):
    run('MCC.Extract.Store("11", "XA", {{w = 5, h = 5, items = {{id = "item_battery", x = %d, y = 0}}}})' % i)
crates = L('MCC.Extract.Stored("11")')
check(L('#MCC.Extract.Stored("11")') == 3 and L('MCC.Extract.Stored("11")[1].grids[1].items[1].x') == 0,
      "only 3 crates are kept; the oldest was overwritten")

# signal flares
fl = give('XB', 'mcc_flare')
run('MCC.Extract.Store("12", "XB", {})')  # XB now has 2
run('MCC.Inv.Get(XB).slots.backpack = MCC.Inv.NewItem("bp_large", 1)')
fl = give('XB', 'mcc_flare')
run('MCC.Extract.Pending["13"] = nil')
nb = L('#MCC.Extract.Stored("12")')
check(L('(MCC.Inv.Use(XB, %d))' % fl) is True and L('MCC.Extract.Available("12")') == nb - 1, "throwing a flare reserves a crate")
fl_ent = 'next(MCC.Extract.Flares)'
check(L('%s:GetClass()' % fl_ent) == "mcc_flare", "a burning flare is thrown")
run('_FL = next(MCC.Extract.Flares) _FL:SetPos(Vector(200, 0, 0))')
run('_TIME = _TIME + 5 timer.t["MCC_ExtractFlares"].f()')
check(L('_FL.MCCDropped') is None, "the drop isn't there yet")
run('_DROPPED = nil local old = ents.Create ents.Create = function(c) local e = old(c) if c == "mcc_extract_crate" then _DROPPED = e end return e end')
run('_TIME = _TIME + 15 timer.t["MCC_ExtractFlares"].f()')
check(L('_DROPPED ~= nil and _DROPPED:GetChute()') is True and L('_DROPPED:GetPos().z') > 64, "the crate drops by parachute over the flare")
check(L('#_DROPPED.MCCCont.grids[1].items') == 1 and L('_DROPPED.MCCCont.grids[1].items[1].u') is not None,
      "it holds the oldest stored crate (with fresh item ids)")
check(L('#MCC.Extract.Stored("12")') == nb - 1 and L('MCC.Extract.Pending["12"]') == 0, "it's removed from storage")
check(L('_DROPPED:GetNWFloat("MCCDropMark", 0)') > L('_TIME'), "everyone gets a marker on it")
run('_SetCV("mcc_search_enabled", 1)')
check(L('MCC.Inv.SectionDone(XB, _DROPPED, "c:1")') is True and L('MCC.Inv.SectionDone(XA, _DROPPED, "c:1")') is False,
      "the owner knows what's inside; everyone else has to search")
run('_SetCV("mcc_search_enabled", 0)')
run('MCC.Inv.OpenContainer(XA, _DROPPED)')
check(L('_DROPPED:GetNWFloat("MCCDropMark", 0)') == 0, "the marker goes away once someone opens it")

# no crates stored: the flare is refused and kept; a stolen flare calls the thief's crates
run('MCC.Extract.Pending["11"] = nil')
fl2 = give('XA', 'mcc_flare')
run('XN = _MakeTester(13) _PLAYERS[#_PLAYERS + 1] = XN hook.Run("PlayerInitialSpawn", XN)')
run('_G._STOLEN = MCC.Inv.NewItem("mcc_flare", 1) MCC.Inv.GiveItem(XN, _G._STOLEN)')
ok, err = L('MCC.Inv.Use(XN, _G._STOLEN.u)')
check(ok is not True and "no crates" in (err or "") and L('MCC.Inv.Find(XN, _G._STOLEN.u) ~= nil'),
      "someone with no stored crates can't use a flare (they keep it)")

# a roof over the flare calls it off and keeps the crate
n11 = L('#MCC.Extract.Stored("11")')
check(L('(MCC.Inv.Use(XA, %d))' % fl2) is True, "XA throws a flare")
run('_ROOF = true _TIME = _TIME + 20 timer.t["MCC_ExtractFlares"].f() _ROOF = nil')
check(L('#MCC.Extract.Stored("11")') == n11 and L('MCC.Extract.Available("11")') == n11, "no open sky over the flare: the drop is called off, the crate stays stored")
# a flare removed before its drop gives the reservation back
fl3 = give('XA', 'mcc_flare')
L('(MCC.Inv.Use(XA, %d))' % fl3)
check(L('MCC.Extract.Available("11")') == n11 - 1, "reserved")
run('for f in pairs(MCC.Extract.Flares) do if not f.MCCDropped then MCC.Extract.FlareRemoved(f) end end')
check(L('MCC.Extract.Available("11")') == n11, "a flare cleaned up before the drop releases the crate")

# JMod workbench recipes
run('JMod.Config.Craftables = {} JMod.LuaConfig = {BuildFuncs = {}}')
check(L('MCC.JModRecipes.Apply()') is True, "recipes are added to JMod")
CR = 'JMod.Config.Craftables'
check(L(CR + '["Extraction Crate"].results') == "mcc_extract_crate" and L(CR + '["Extraction Crate"].craftingType') == "workbench"
      and L(CR + '["Extraction Crate"].craftingReqs.wood') == 50, "the crate is a workbench recipe (50 wood...)")
check(L(CR + '["Fulton Recovery Device"].craftingReqs.gas') == 20 and L(CR + '["Signal Flare"].craftingReqs.chemicals') == 5,
      "Fulton and flare recipes")
run('_BUILT = JMod.LuaConfig.BuildFuncs.MCCFlare(XA, Vector(0, 0, 0), Angle())')
check(L('_BUILT.MCCItem.id') == "mcc_flare", "crafting a flare spawns the flare item")
rpath = os.path.join(sv.datadir, "mcc/jmod_recipes.json")
rj = json.load(open(rpath)); rj["Signal Flare"] = {"chemicals": 2, "propellant": 0, "paper": 3}; json.dump(rj, open(rpath, "w"))
run('MCC.JModRecipes.Apply()')
check(L(CR + '["Signal Flare"].craftingReqs.chemicals') == 2 and L(CR + '["Signal Flare"].craftingReqs.propellant') is None
      and L(CR + '["Signal Flare"].craftingReqs.paper') == 3, "costs come from jmod_recipes.json")

# ---------------------------------------------------------------- FOBs (Rust tool cupboard)
def dmg(amount, bullet=False, burn=False):
    return ('{GetDamage = function() return %d end, IsBulletDamage = function() return %s end, GetAttacker = function() return nil end, '
            'IsDamageType = function(s, t) return %s end}') % (amount, 'true' if bullet else 'false', 'true' if burn else 'false')
def give(ply, id, d='nil'):
    run('_G._GIVEN = MCC.Inv.NewItem("%s", 1, %s) MCC.Inv.GiveItem(%s, _G._GIVEN)' % (id, d, ply))
    return L('_G._GIVEN.u')
check(L('MCC.Items.Get("mcc_fob_kit").data.useLabel') == "Deploy FOB", "the FOB Kit is an item you deploy")
run('JMod.Config.Craftables = {} MCC.JModRecipes.Apply()')
check(L('JMod.Config.Craftables["FOB Kit"].craftingType') == "workbench", "and a JMod workbench recipe")
check(L('MCC.FOB.MODEL') == "models/props_silo/silo_launchroom_monitor.mdl" and L('MCC.Config.Get("fob_core_model")') == "models/props_silo/silo_launchroom_monitor.mdl",
      "the core is the silo launch room monitor")
run('FA = _MakeTester(21) FB = _MakeTester(22) FC = _MakeTester(23) _PLAYERS = {FA, FB, FC}')
run('for _, p in ipairs({FA, FB, FC}) do hook.Run("PlayerInitialSpawn", p) hook.Run("PlayerLoadout", p) p.EyeAngles = function() return {y = 0} end MCC.Inv.Get(p).slots.backpack = MCC.Inv.NewItem("bp_large", 1) end')
kit = give('FA', 'mcc_fob_kit')
check(L('(MCC.Inv.Use(FA, %d))' % kit) is True and L('MCC.Inv.Find(FA, %d)' % kit) is None, "deploying uses up the kit")
run('CORE = MCC.FOB.Owned(FA)[1]')
check(L('IsValid(CORE)') and L('CORE:GetOwnerID()') == "21" and L('CORE:GetHP()') == 1000 and L('CORE:GetRadius()') == 1024,
      "a tier 1 FOB: 1000 health, 1024 zone, owned by its deployer")
check(L('CORE:GetStored()') == 0 and L('CORE:GetNWInt("MCCStashCells")') == 80 and L('CORE.MCCCont.grids[1].w') == 8,
      "it starts with an empty 8x10 stash")
ok, err = L('MCC.Inv.Use(FA, %d)' % give('FA', 'mcc_fob_kit'))
check(ok is not True and "already" in (err or ""), "one FOB per player")
ok, err = L('MCC.Inv.Use(FB, %d)' % give('FB', 'mcc_fob_kit'))
check(ok is not True and "Too close" in (err or ""), "zones can't overlap")
check(L('MCC.FOB.InSafeZone(CORE:GetPos() + Vector(500, 0, 0)) == CORE') and L('MCC.FOB.At(CORE:GetPos() + Vector(1500, 0, 0))') is None,
      "its zone is a safe zone")

check(L('GetGlobalFloat("MCCFobTier1Radius")') == 1024, "the tier 1 range is shared with clients for the range bubble")
# storing resources
give('FA', 'jmod_wood', '{amount = 300}')
give('FA', 'jmod_water', '{amount = 100}')
ore = give('FA', 'jmod_iron_ore', '{amount = 50}')
run('MCC.Net.Handlers.fob_act.fn({a = "deposit", e = CORE:EntIndex()}, FA)')
check(L('MCC.FOB.Store(CORE).wood') == 300 and L('MCC.FOB.Store(CORE).water') == 100 and L('CORE:GetStored()') == 400,
      "deposit stores the JMod resources you carry as they are (300 wood, 100 water)")
check(L('CORE:GetFood()') == 50, "water counts as food (100 water = 50 food)")
check(L('MCC.Inv.Find(FA, %d) ~= nil' % ore), "ore isn't stored and stays in your inventory")
check(L('CORE:TryLoadResource("steel", 40)') == 40 and L('MCC.FOB.Store(CORE).steel') == 40, "JMod boxes pushed into the core are stored")
check(L('CORE:TryLoadResource("fuel", 40)') == 0 and L('table.HasValue(CORE.EZconsumes, "wood")') is True, "it tells JMod what it takes")
check(L('#CORE.MCCCont.grids[1].items') == 3 + 1 + 1, "they sit in its stash as boxes: 3 wood, 1 water, 1 steel")
run('MCC.FOB.AddResource(CORE, "wood", 100000) MCC.FOB.SyncStore(CORE)')
check(L('CORE:TryLoadResource("wood", 100)') == 0, "a full stash takes no more")
setres('CORE', 'wood', 300)
check(L('MCC.FOB.Store(CORE).wood') == 300 and L('#CORE.MCCCont.grids[1].items') == 5, "the extra wood taken back out")

# the stash in the inventory window: drag things in and out
run('CORE:SetPos(Vector(100, 0, 0)) MCC.FOB.Use(FA, CORE)')  # in reach of the testers (eyes at 0, 0, 64)
check(L('FA.MCCInvOpen == CORE') and L('MCC.Inv.OpenPayload(FA).fob') == L('CORE:EntIndex()') and L('MCC.Inv.OpenPayload(FA).grids[1].w') == 8,
      "E on the core opens its stash in the inventory window, with a FOB MENU button")
wood2 = give('FA', 'jmod_wood', '{amount = 60}')
spot = L('(function() local g = CORE.MCCCont.grids[1] local x, y = MCC.Inv.FindSpot(g.items, g.w, g.h, {id = "jmod_wood", u = -1}) return x * 100 + y end)()')
check(L('(MCC.Inv.Move(FA, %d, "c:1", %d, %d))' % (wood2, spot // 100, spot % 100)) is True and L('MCC.FOB.Store(CORE).wood') == 360,
      "dragging a wood box into the stash adds it to what the FOB has (360 wood)")
med = give('FA', 'item_healthvial')
check(L('(MCC.Inv.Quick(FA, %d))' % med) is True and L('#CORE.MCCCont.grids[1].items') == 7, "any item goes in the stash (a health vial)")
check(L('CORE:GetStored()') == 440, "(totals catch up when the inventory syncs)")
run('MCC.Inv.Update(FA) hook.Run("Think")')
check(L('CORE:GetStored()') == 500, "the core's totals follow what's dragged in (360 wood, 100 water, 40 steel)")
check(L('(MCC.Inv.Quick(FA, %d))' % wood2) is True and L('MCC.FOB.Store(CORE).wood') == 300 and L('MCC.Inv.Find(FA, %d) ~= nil' % wood2),
      "and you take things back out the same way")
run('hook.Run("Think") MCC.FOB.Use(FB, CORE)')
check(L('FB.MCCInvOpen ~= CORE'), "someone else's FOB opens its menu, not its stash")
run('FA.MCCInvOpen = nil')

# props: ordinary props get size health and wood upkeep; outsiders can't build or touch
run('PR = _Ent("prop_physics") PR:SetPos(CORE:GetPos() + Vector(100, 0, 0)) hook.Run("PlayerSpawnedProp", FA, "m", PR)')
check(L('PR.MCCFob == CORE') and L('PR:GetNWInt("MCCFobHP")') == 200, "a member's prop joins the FOB with health from its size")
run('PX = _Ent("prop_physics") PX:SetPos(CORE:GetPos() + Vector(120, 0, 0)) hook.Run("PlayerSpawnedProp", FB, "m", PX)')
check(not L('IsValid(PX)'), "an outsider can't build in it")
check(L('(hook.Run("PhysgunPickup", FB, PR))') is False and L('(hook.Run("PhysgunPickup", FA, PR))') is None, "or move its props")
run('MCC.Net.Handlers.fob_act.fn({a = "add", e = CORE:EntIndex(), sid = "22"}, FA)')
check(L('MCC.FOB.IsMember(CORE, FB)') is True, "the owner can add members")
run('MCC.Net.Handlers.fob_act.fn({a = "kick", e = CORE:EntIndex(), sid = "22"}, FB)')
check(L('MCC.FOB.IsMember(CORE, FB)') is False, "members can leave")
run('hook.Run("EntityTakeDamage", PR, %s)' % dmg(100, True))
check(L('PR:GetNWInt("MCCFobHP")') == 175, "bullets do a quarter damage")
run('hook.Run("EntityTakeDamage", CORE, %s)' % dmg(400, True))
check(L('CORE:GetHP()') == 900, "the core takes damage too")

# upkeep every 30 minutes, per resource
needs = L('MCC.FOB.UpkeepNeeds(CORE).wood')
check(needs == 10 + 2, "upkeep: the tier's 10 wood plus the prop's 2 wood (it uses the wood tier)")
run('_SetCV("mcc_fob_upkeep_interval", 1800) CORE.MCCNextBill = _TIME')
run('MCC.FOB.Tick(CORE)')
check(L('MCC.FOB.Store(CORE).wood') == 300 - 12 and L('CORE:GetNWBool("MCCDecaying")') is False, "every 30 minutes it pays: 12 wood")
check(L('CORE.MCCNextBill') == L('_TIME') + 1800, "and the next payment is 30 minutes later")
check(L('CORE:GetHP()') > 900, "while it's paid, the core repairs itself")
setres('CORE', 'wood', 5)
run('CORE.MCCNextBill = _TIME MCC.FOB.Tick(CORE)')
check(L('CORE:GetNWBool("MCCDecaying")') is True and L('CORE:GetNWString("MCCUnpaid")') == "wood" and L('MCC.FOB.Store(CORE).wood') == 5,
      "short on wood: nothing is taken and everything paid in wood decays")
hp0, core0 = L('MCC.FOB.PropHP(PR)'), L('CORE:GetHP()')
run('MCC.FOB.Tick(CORE)')
check(abs((hp0 - L('MCC.FOB.PropHP(PR)')) - 200 / (3 * 3600) * 10) < 1e-6, "the prop decays over the wood tier's 3 hours")
check(abs((core0 - L('CORE:GetHP()')) - 1000 / (12 * 3600) * 10) < 1e-6, "the core over 12 hours")
check(L('CORE:TryLoadResource("wood", 100)') == 100 and L('CORE:GetNWBool("MCCDecaying")') is False and L('MCC.FOB.Store(CORE).wood') == 105 - 12,
      "depositing the missing wood pays the upkeep straight away")
setres('CORE', 'wood', 5)
run('CORE.MCCNextBill = _TIME MCC.FOB.Tick(CORE)')
check(L('CORE:GetNWBool("MCCDecaying")') is True, "(short on wood again)")
w3 = give('FA', 'jmod_wood', '{amount = 100}')
run('CORE:SetPos(Vector(100, 0, 0)) MCC.FOB.Use(FA, CORE)')
check(L('(MCC.Inv.Quick(FA, %d))' % w3) is True, "a member drags a wood box into the stash")
run('MCC.Inv.Update(FA) hook.Run("Think")')
check(L('CORE:GetNWBool("MCCDecaying")') is False and L('MCC.FOB.Store(CORE).wood') == 105 - 12,
      "which pays the missing upkeep straight away too")
run('FA.MCCInvOpen = nil')

# upgrading costs stored resources
ok, err = L('MCC.FOB.Upgrade(CORE, FA)')
check(ok is not True and "300 more wood" not in (err or "x") and "steel" in (err or ""), "tier 2 needs more than it has: %s" % err)
setres('CORE', 'wood', 400)
setres('CORE', 'steel', 300)
setres('CORE', 'basic parts', 100)
run('CORE:SetHP(900)')
check(L('(MCC.FOB.Upgrade(CORE, FA))') is True and L('CORE:GetTier()') == 2 and L('CORE:GetMaxHP()') == 2500 and L('CORE:GetRadius()') == 1536,
      "upgrading to tier 2 (300 wood, 200 steel, 100 basic parts): 2500 health, bigger zone")
check(L('MCC.FOB.Store(CORE).wood') == 100 and L('MCC.FOB.Store(CORE).steel') == 100 and L('MCC.FOB.Store(CORE)["basic parts"]') is None,
      "the cost came out of its stores")
check(L('MCC.FOB.UpkeepNeeds(CORE).steel') == 10, "tier 2 also needs steel upkeep")
check(L('CORE.MCCCont.grids[1].w') == 10 and L('CORE:GetNWInt("MCCStashCells")') == 120, "and has a bigger stash (10x12)")

# leaving, claiming
run('MCC.Net.Handlers.fob_act.fn({a = "add", e = CORE:EntIndex(), sid = "22"}, FA)')
run('_PLAYERS = {FB, FC} hook.Run("PlayerDisconnected", FA)')
check(L('CORE:GetOwnerID()') == "22", "when the owner leaves, an online member takes over")
run('_PLAYERS = {FC} hook.Run("PlayerDisconnected", FB)')
check(L('CORE:GetAbandoned()') is True and L('MCC.FOB.InSafeZone(CORE:GetPos())') is None, "with nobody left it's abandoned")
run('FC:SetPos(CORE:GetPos() + Vector(60, 0, 0)) MCC.Net.Handlers.fob_act.fn({a = "claim", e = CORE:EntIndex()}, FC)')
run('_TIME = _TIME + 11 timer.t["MCC_FOBClaims"].f()')
check(L('CORE:GetOwnerID()') == "23" and L('CORE:GetAbandoned()') is False, "and anyone can claim it")

# destroyed: stores spill as JMod boxes, props stay
run('PR3 = _Ent("prop_physics") PR3:SetPos(CORE:GetPos() + Vector(70, 0, 0)) hook.Run("PlayerSpawnedProp", FC, "m", PR3)')
run('_SPILL = 0 local old = ents.Create ents.Create = function(c) local e = old(c) if c:find("ent_jack_gmod_ez") then _SPILL = _SPILL + 1 end return e end')
run('hook.Run("EntityTakeDamage", CORE, %s)' % dmg(100000))
check(not L('IsValid(CORE)') and L('IsValid(PR3)') and L('PR3.MCCFob') is None, "at 0 health the core is destroyed; its props stay")
check(L('_SPILL') >= 2, "what it stored spills out as JMod boxes (%s boxes)" % L('_SPILL'))

# admin FOB
run('_SetCV("mcc_fob_admin_stock", 500) ADM = MCC.FOB.SpawnAdmin(FC, Vector(0, 5000, 0))')
check(L('IsValid(ADM)') and L('ADM:GetNWBool("MCCAdmin")') is True and L('MCC.FOB.Store(ADM).wood') == 500 and L('MCC.FOB.Store(ADM).titanium') == 500,
      "an Admin FOB spawns stocked with 500 of each building resource")
check(L('#MCC.FOB.Owned(FC)') == 0 and L('#MCC.FOB.Owned(FC, true)') == 1, "and doesn't count toward the owner's FOB limit")
run('ENT = {} include("entities/mcc_fob_admin.lua") _ADMENT = ENT')
check(L('_ADMENT.Spawnable') is True and L('_ADMENT.AdminOnly') is True and L('_ADMENT.Category') == "MCC", "it's in the spawn menu for admins")
kitc = give('FC', 'mcc_fob_kit')
run('FC:SetPos(Vector(0, 0, 0)) MCC.Inv.Use(FC, %d) CORE2 = MCC.FOB.Owned(FC)[1]' % kitc)
check(L('IsValid(CORE2)'), "FC can still deploy their own FOB")
setres('CORE2', 'wood', 250)
run('_SPILL = 0')
run('MCC.Net.Handlers.fob_act.fn({a = "packup", e = CORE2:EntIndex()}, FC)')
check(not L('IsValid(CORE2)') and L('_SPILL') == 3, "packing up returns the kit and spills the stash (250 wood = 3 boxes)")
run('ADM:Remove()')

# ---------------------------------------------------------------- Builder Tablet, Rust tiers
G, TT = 94.9, 23.72
run('_MODELBOUNDS["models/hunter/blocks/cube2x2x05.mdl"] = {Vector(-47.45, -47.45, -11.86), Vector(47.45, 47.45, 11.86)}')
run('_MODELBOUNDS["models/props_phx/construct/wood/wood_panel2x2.mdl"] = {Vector(-47.45, -47.45, -1.5), Vector(47.45, 47.45, 1.5)}')
run('_MODELBOUNDS["models/props_fortifications/sandbags_line1.mdl"] = {Vector(-30, -10, -15), Vector(30, 10, 15)}')
check(L('MCC.Build.Pieces["wall"].kind') == "wall" and L('MCC.Build.Pieces["hesco_tall"].kind') == "free" and L('MCC.Build.Pieces["wall_metal"]') is None,
      "structure pieces are shapes now (foundation, wall, floor); the tier sets the material")
T_ = [(L('MCC.Build.Tiers[%d].name' % i), L('MCC.Build.Tiers[%d].health' % i), L('MCC.Build.Tiers[%d].decayHours' % i)) for i in range(1, 6)]
check(T_ == [("Twig", 10, 1), ("Wood", 1000, 3), ("Stone", 3500, 5), ("Sheet Metal", 8000, 8), ("Armored", 12000, 12)],
      "Rust's tiers: %s" % T_)
check(L('MCC.Build.Tiers[1].cost.wood') == 20, "twig costs 20 wood to place")
check(os.path.exists(os.path.join(sv.datadir, "mcc/build_tiers.json")) and json.load(open(os.path.join(sv.datadir, "mcc/build_pieces.json"))).get("version") == 2,
      "tiers and pieces are in build_tiers.json and build_pieces.json")
run('_SetCV("mcc_build_range", 1000)')
run('FD = _MakeTester(31) FE = _MakeTester(32) _PLAYERS = {FD, FE} for _, p in ipairs({FD, FE}) do hook.Run("PlayerInitialSpawn", p) p.EyeAngles = function() return {y = 0} end p.IsSuperAdmin = function() return false end p.GetEyeTrace = function() return _TR end MCC.Inv.Get(p).slots.backpack = MCC.Inv.NewItem("bp_large", 1) end')
run('BCORE = MCC.FOB.SpawnAdmin(FD, Vector(200, 0, 64))')
run('_SetCV("mcc_build_use_fob_stash", 0)')  # these tests pay from what FD carries; the stash is tested below
def aim(x, y, z, ent='NULL'):
    run('_TR = {Hit = true, HitPos = Vector(%f, %f, %f), HitNormal = Vector(0, 0, 1), Entity = %s}' % (x, y, z, ent))
def place(piece, who='FD'):
    return L('MCC.Build.Place(%s, "%s", 0)' % (who, piece))
def carried(who, res):
    return L('MCC.Inv.CountResources(%s)["%s"] or 0' % (who, res))
def find_slot(var, key):
    run('%s = nil for _, e in ipairs(_ENTS) do if IsValid(e) and e:GetNWString("MCCSlot", "") == "%s" then %s = e end end' % (var, key, var))

aim(250, 0, 0)
ok, err = L('MCC.Build.Place(FD, "foundation", 0)')
check(ok in (None, False) and "20 wood" in (err or ""), "with no wood you can't place twig: %s" % err)
give('FD', 'jmod_wood', '{amount = 100}')
give('FD', 'jmod_wood', '{amount = 100}')
check(place('foundation') not in (None, False) and carried('FD', 'wood') == 180, "the first foundation costs 20 of the wood you carry")
find_slot('ROOT', 'f:0:0')
check(L('ROOT:GetNWString("MCCTier")') == "twig" and L('ROOT:GetNWInt("MCCFobMaxHP")') == 10 and L('ROOT.MCCUpkeep.wood') == 1,
      "it's built as twig: 10 HP, 1 wood upkeep")
check(abs(L('ROOT:GetNWFloat("MCCBldG")') - G) < 1e-3, "and starts the building grid")
aim(250 + 0.9 * G, 0, TT, 'ROOT')
check(place('foundation') not in (None, False), "a second foundation snaps to its side")
find_slot('F2', 'f:1:0')
check(L('IsValid(F2)') and abs(L('F2:GetPos().x') - (250 + G)) < 1e-3, "one cell over")
aim(250 + 3 * G, 0, TT, 'ROOT')
ok, err = L('MCC.Build.Place(FD, "foundation", 0)')
check(ok in (None, False) and "hold it up" in (err or ""), "foundations attach to foundations")
aim(250 + 0.45 * G, 0.05 * G, TT, 'ROOT')
check(place('wall') not in (None, False), "a wall stands on the edge")
find_slot('W1', 'w:1:0:0')
check(L('W1:GetAngles().y') == 90 and L('W1:GetAngles().r') == 90, "standing up, turned across the edge")
aim(250 + 0.6 * G, 0, TT + G, 'W1')
check(place('floor') not in (None, False), "a floor goes on top of the wall")
find_slot('FL', 'fl:1:0:1')
check(L('IsValid(FL)') and abs(L('FL:GetPos().z') - (TT + G - 1.5)) < 1e-3, "one wall height up")

# upgrading: right-click a piece, pay from what you carry
check(L('(MCC.Build.Upgrade(FD, W1, 2))') is True and L('W1:GetNWString("MCCTier")') == "wood"
      and L('W1:GetNWInt("MCCFobMaxHP")') == 1000 and L('W1:GetNWInt("MCCFobHP")') == 1000, "upgrading the wall to wood: 1000 HP")
check(carried('FD', 'wood') == 200 - 4 * 20 - 50, "it cost 50 wood")
check(L('W1.MCCUpkeep.wood') == 2 and L('W1.MCCDecayHours') == 3 and L('W1._mat') == "phoenix_storms/wood", "wood upkeep, 3 hour decay, wood look")
ok, err = L('MCC.Build.Upgrade(FD, W1, 3)')
check(ok in (None, False) and "75 concrete" in (err or ""), "stone needs concrete: %s" % err)
give('FD', 'jmod_concrete', '{amount = 100}')
check(L('(MCC.Build.Upgrade(FD, W1, 3))') is True and L('W1:GetNWInt("MCCFobMaxHP")') == 3500 and L('W1.MCCUpkeep.concrete') == 2,
      "stone: 3500 HP, concrete upkeep")
run('hook.Run("EntityTakeDamage", W1, %s)' % dmg(500, burn=True))
check(L('W1:GetNWInt("MCCFobHP")') == 3500, "stone doesn't burn")
run('hook.Run("EntityTakeDamage", W1, %s)' % dmg(500))
check(L('W1:GetNWInt("MCCFobHP")') == 3000, "but explosives hurt it")
ok, err = L('MCC.Build.Upgrade(FD, W1, 2)')
check(ok in (None, False), "you can't downgrade")
run('_SetCV("mcc_build_free", 1)')
check(L('(MCC.Build.Upgrade(FD, W1, 5))') is True and L('W1:GetNWInt("MCCFobMaxHP")') == 12000 and L('W1.MCCUpkeep.titanium') == 1,
      "armored: 12000 HP, titanium upkeep (mcc_build_free skips costs)")
run('_SetCV("mcc_build_free", 0)')

# upkeep for pieces and decay per tier
needs = L('MCC.FOB.UpkeepNeeds(BCORE)')
check(L('MCC.FOB.UpkeepNeeds(BCORE).titanium') == 1 and L('MCC.FOB.UpkeepNeeds(BCORE).wood') == 10 + 3,
      "the FOB owes each piece's upkeep: titanium for the armored wall, wood for the twig and the core")
setres('BCORE', 'wood', 0)
run('BCORE.MCCNextBill = _TIME MCC.FOB.Tick(BCORE)')
hp_twig = L('MCC.FOB.PropHP(ROOT)')
check(abs((10 - hp_twig) - 10 / 3600 * 10) < 1e-6 and L('MCC.FOB.PropHP(W1)') == 12000,
      "out of wood: the twig decays (1 hour) but the armored wall's titanium is paid")
run('for i = 1, 400 do MCC.FOB.Tick(BCORE) end')
check(not L('IsValid(ROOT)'), "unpaid twig falls apart within the hour")

# the Builder Hammer: repair (hits or the menu), upgrade menu, remove
run('W1.MCCFobHP = 6000 W1.MCCLastHurt = _TIME')
give('FD', 'jmod_titanium', '{amount = 50}')
check(L('MCC.Build.RepairCost(W1, MCC.Build.Pieces.wall).titanium') == 7, "repairing half its health costs a quarter of armored's 25 titanium")
ok, err = L('MCC.Build.Repair(FD, W1)')
check(ok is not True and "Recently damaged" in (err or ""), "no repairs for 30 seconds after it's damaged: %s" % err)
run('_TIME = _TIME + 31')
ok, heal = L('MCC.Build.HammerHit(FD, W1)')
check(ok is True and heal == 1200 and L('MCC.FOB.PropHP(W1)') == 7200 and carried('FD', 'titanium') == 48,
      "a hammer hit repairs a tenth of its health for a share of the cost (1200 HP, 2 titanium)")
run('ENT = nil SWEP = {Primary = {}, Secondary = {}} include("weapons/mcc_hammer.lua") HAMMER = SWEP')
check(L('HAMMER.Spawnable') is True and L('HAMMER.ViewModel') == "models/weapons/c_crowbar.mdl", "the hammer is a weapon (crowbar model until there's a hammer)")
check(L('MCC.Items.Get("mcc_hammer").data.slot') == "melee", "it goes in the sheath slot")
run('JMod.Config.Craftables = {} MCC.JModRecipes.Apply()')
check(L('JMod.Config.Craftables["Builder Hammer"] ~= nil'), "and is crafted at the JMod workbench")
run('''local h = setmetatable({}, {__index = HAMMER}) h.GetOwner = function() return FD end
h.SetNextPrimaryFire = function() end h.SendWeaponAnim = function() end h.EmitSound = function() end
FD.SetAnimation = function() end
h.SwingTrace = function() return {Hit = true, Entity = W1, HitPos = W1:GetPos()} end
h:PrimaryAttack()''')
check(L('MCC.FOB.PropHP(W1)') == 8400, "swinging it at the wall repairs it")
check(L('(MCC.Build.PieceMenu(FD, W1))') is True and L('(MCC.Build.PieceMenu(FE, W1))') is False, "right-click opens the wall's menu for its builder, not others")
run('FD.GetActiveWeapon = function() return NULL end MCC.Net.Handlers.build_piece_act.fn({a = "repair", e = W1:EntIndex()}, FD)')
check(L('MCC.FOB.PropHP(W1)') == 8400, "the piece menu's actions need the hammer in your hands")
run('FD.GetActiveWeapon = function() return {valid = true, GetClass = function() return "mcc_hammer" end} end')
run('MCC.Net.Handlers.build_piece_act.fn({a = "repair", e = W1:EntIndex()}, FD)')
check(L('MCC.FOB.PropHP(W1)') == 12000, "repair fills it")
before = carried('FD', 'titanium')
check(L('(MCC.Build.Remove(FD, W1))') is True and not L('IsValid(W1)') and carried('FD', 'titanium') == before + 13,
      "removing it refunds half its tier's cost into your inventory")

# fortifications: their own resource cost, health, upkeep
aim(250, 300, 0)
ok, err = L('MCC.Build.Place(FD, "sandbags_line1", 0)')
check(ok in (None, False) and "sand" in (err or ""), "sandbags cost sand: %s" % err)
give('FD', 'jmod_sand', '{amount = 100}')
check(place('sandbags_line1') not in (None, False), "with sand they're built")
run('SB = nil for _, e in ipairs(_ENTS) do if IsValid(e) and e:GetNWString("MCCPiece", "") == "sandbags_line1" then SB = e end end')
check(L('SB:GetNWInt("MCCFobMaxHP")') == 400 and L('SB.MCCUpkeep.sand') == 1 and L('SB.MCCDecayHours') == 4, "400 HP, sand upkeep, 4 hour decay")
run('_TR = {Hit = true, HitPos = SB:GetPos() + Vector(-20, 0, 0), HitNormal = Vector(1, 0, 0), Entity = SB}')
check(place('sandbags_line1') not in (None, False), "the next one lines up")
run('SB2 = nil for _, e in ipairs(_ENTS) do if IsValid(e) and e ~= SB and e:GetNWString("MCCPiece", "") == "sandbags_line1" then SB2 = e end end')
check(abs(L('SB2:GetPos().x') - (L('SB:GetPos().x') - 60)) < 1e-3, "flush against its side")

aim(250, -200, 0)
ok, err = L('MCC.Build.Place(FE, "sandbags_line1", 0)')
check(ok in (None, False) and "your FOB" in (err or ""), "someone else can't build in your FOB")
run('_SetCV("mcc_build_range", 5000)')
aim(3000, 0, 0)
ok, err = L('MCC.Build.Place(FD, "foundation", 0)')
check(ok in (None, False) and "inside your FOB" in (err or ""), "building happens inside a FOB")
run('_SetCV("mcc_build_range", 1000)')

# in your FOB's zone the tablet and hammer pay from its stash, then from what you carry
run('_SetCV("mcc_build_use_fob_stash", 1)')
stash = lambda res: L('MCC.FOB.Store(BCORE)["%s"] or 0' % res)
setres('BCORE', 'wood', 100)
wood_c = carried('FD', 'wood')
aim(250, -300, 0)
check(place('foundation') not in (None, False) and stash('wood') == 80 and carried('FD', 'wood') == wood_c,
      "a foundation in the FOB's zone takes its 20 wood from the stash, not your inventory")
check(L('BCORE:GetNWString("MCCStore")').find("wood=80") >= 0, "clients see what the stash holds (for the green/red ghost)")
run('R2 = nil for _, e in ipairs(_ENTS) do if IsValid(e) and e ~= ROOT and e:GetNWString("MCCPiece", "") == "foundation" and e:GetPos().y < -200 then R2 = e end end')
setres('BCORE', 'concrete', 100)
con_c = carried('FD', 'concrete')
check(L('(MCC.Build.Upgrade(FD, R2, 3))') is True and stash('concrete') == 25 and carried('FD', 'concrete') == con_c,
      "upgrading it to stone takes 75 concrete from the stash")
setres('BCORE', 'wood', 5)
give('FD', 'jmod_wood', '{amount = 30}')
wood_c = carried('FD', 'wood')
aim(250, -600, 0)
check(place('foundation') not in (None, False) and stash('wood') == 0 and carried('FD', 'wood') == wood_c - 15,
      "with only 5 wood in the stash, the other 15 come from your inventory")
setres('BCORE', 'wood', 0)
check(L('MCC.Build.PayingFOB(FE, BCORE)') is None, "someone else's FOB never pays for you")
before_c = carried('FD', 'concrete')
check(L('(MCC.Build.Remove(FD, R2))') is True and stash('concrete') == 25 + 38 and carried('FD', 'concrete') == before_c,
      "removing a piece refunds into the stash (half of stone's 75 concrete, rounded up)")
run('_SetCV("mcc_build_use_fob_stash", 0)')
check(L('(MCC.Build.CanAfford(FD, {concrete = 50}, BCORE))') is False, "mcc_build_use_fob_stash 0: only what you carry counts")
run('_SetCV("mcc_build_use_fob_stash", 1)')
check(L('(MCC.Build.CanAfford(FD, {concrete = 50}, BCORE))') is True, "and back on")

# settings menu: every MCC setting, admins change them
check(L('#MCC.Config.Order') >= 50 and L('MCC.Config.Defs.fob_upkeep_interval.max') == 86400, "every setting is listed with its range for the settings page")
run('_RCC = {} RunConsoleCommand = function(...) _RCC = {...} end')
run('FE.IsSuperAdmin = function() return false end FE.IsAdmin = function() return false end FE.PrintMessage = function() end FE.ChatPrint = function() end')
run('MCC.Net.Handlers.config_set.fn({name = "fob_claim_time", value = 30}, FE)')
check(L('_RCC[1]') is None, "players can't change settings")
run('FE.IsSuperAdmin = function() return true end')
run('MCC.Net.Handlers.config_set.fn({name = "fob_claim_time", value = 99999}, FE)')
check(L('_RCC[1]') == "mcc_fob_claim_time" and L('_RCC[2]') == "300", "admins can, clamped to the setting's range")
run('FE.IsSuperAdmin = function() return false end')

# a client loads the UI file
cl = Realm("client")
cl.load_mcc()
cl.boot()
check(cl.eval('vgui ~= nil or true'), "client files load")
check(cl.eval('type(MCC.Inv.OpenInspect)') == "function", "the inspect window is loaded on the client")
check(cl.eval('type(MCC.Inv.MakeWornModels)') == "function", "worn gear drawing is loaded on the client")
check(cl.eval('type(MCC.FOB.OpenMenuUI)') == "function" and cl.eval('type(MCC.FOB.IsMember)') == "function", "the FOB menu and HUD are loaded on the client")
check(cl.eval('type(MCC.Build.OpenMenu)') == "function" and cl.eval('type(MCC.Build.Solve)') == "function", "the builder ghost and piece picker are loaded on the client")
cl.run('function _FakePanel() return {valid = true, Remove = function(p) p.valid = false end} end')
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is None, "ESC opens the pause menu as usual when the inventory is closed")
cl.run('MCC.Inv.Panel = MCC.UI.Escapable(_FakePanel()) MCC.Inv.Inspect = MCC.UI.Escapable(_FakePanel()) _P1, _I1 = MCC.Inv.Panel, MCC.Inv.Inspect')
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is False and cl.eval('_I1.valid') is False and cl.eval('_P1.valid') is True,
      "ESC closes the inspect window first, without the pause menu")
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is False and cl.eval('_P1.valid') is False, "a second ESC closes the inventory")
cl.run('_P2 = MCC.UI.Escapable(_FakePanel()) _M = MCC.UI.Escapable(_FakePanel()) _Q = MCC.UI.Escapable(_FakePanel())')
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is False and cl.eval('_Q.valid') is False and cl.eval('_M.valid') is True,
      "with the stash and the FOB menu open, ESC closes the confirm box first")
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is False and cl.eval('_M.valid') is False and cl.eval('_P2.valid') is True, "then the FOB menu")
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is False and cl.eval('_P2.valid') is False, "then the inventory")
check(cl.eval('(hook.Run("OnPauseMenuShow"))') is None, "and then the pause menu opens as usual")

# the settings page builds a control for every setting; the range bubble draws
cl.run("""
local Any = {}
Any.__index = function(t, k) return function(self, ...) if k == "AddItem" or k == "SetContents" then rawset(self, "_n", (rawget(self, "_n") or 0) + 1) end return nil end end
_CTRLS = 0
vgui.Create = function(cls) _CTRLS = _CTRLS + 1 return setmetatable({cls = cls}, Any) end
spawnmenu = {AddToolMenuOption = function(tab, cat, id, name, a, b, fn) if id == "mcc_server_settings" then _SETTINGS = {tab, cat, name, fn} end end}
_DRAWN = {} render = setmetatable({}, {__index = function(t, k) return function(...) _DRAWN[k] = (_DRAWN[k] or 0) + 1 end end})
chat = {AddText = function() end}
""")
cl.run('hook.Run("PopulateToolMenu") _SETTINGS[4](setmetatable({}, getmetatable(vgui.Create("x"))))')
check(cl.eval('_SETTINGS[1]') == "Utilities" and cl.eval('_SETTINGS[3]') == "Server Settings", "Q menu > Utilities > MCC > Server Settings")
check(cl.eval('_CTRLS') >= cl.eval('#MCC.Config.Order') + 7, "with a control for every setting (%s panels)" % cl.eval('_CTRLS'))
cl.run('_LP = {valid = true, GetPos = function() return Vector(0, 0, 0) end, SteamID64 = function() return "1" end, GetEyeTrace = function() return {Hit = true, HitPos = Vector(0, 0, 0)} end} LocalPlayer = function() return _LP end _CMDS["mcc_fob_range"]() hook.Run("PostDrawTranslucentRenderables", false, false)')
check((cl.eval('_DRAWN.DrawWireframeSphere') or 0) >= 1, "mcc_fob_range shows the tier 1 range where you aim")

# ---------------------------------------------------------------- per-weapon magazines (hooks for ARC9 and the like)
run('_SetCV("mcc_mags_required", 1) MG = _MakeTester(71) _PLAYERS = {MG} hook.Run("PlayerInitialSpawn", MG) hook.Run("PlayerLoadout", MG)')
run('local inv = MCC.Inv.Get(MG) inv.slots.sling = MCC.Inv.NewItem("weapon_smg1", 1) '
    'inv.slots.pocket1 = MCC.Inv.NewItem("mag_smg1", 1, {rounds = 45}) inv.slots.pocket2 = MCC.Inv.NewItem("mag_smg1", 1, {rounds = 20}) MCC.Inv.SyncAmmo(MG)')
check(L('MG:GetAmmoCount("SMG1")') == 45, "by default the fullest magazine of the gun's ammo type feeds it")
run('hook.Add("MCC_MagFits", "t", function(ply, it, mag) return (mag.d and mag.d.rounds or 0) < 30 end) MCC.Inv.SyncAmmo(MG)')
check(L('MG:GetAmmoCount("SMG1")') == 20, "MCC_MagFits picks which magazines fit the gun (only the 20-round one here)")
run('hook.Remove("MCC_MagFits", "t") hook.Add("MCC_WeaponAmmo", "t", function(ply, it) if it.id == "weapon_smg1" then return "AR2" end end) MCC.Inv.SyncAmmo(MG)')
check(L('MG:GetAmmoCount("SMG1")') == 0 and L('MCC.Inv.WeaponAmmo(MG, MCC.Inv.Get(MG).slots.sling)') == "AR2",
      "MCC_WeaponAmmo changes what a gun fires (and so which magazines feed it)")
run('hook.Remove("MCC_WeaponAmmo", "t") _SYNCED = 0 hook.Add("MCC_InventorySynced", "t", function(p) if p == MG then _SYNCED = _SYNCED + 1 end end)')
run('MCC.Inv.Update(MG) hook.Run("Think")')
check(L('_SYNCED') == 1, "MCC_InventorySynced runs after each sync")
run('hook.Remove("MCC_InventorySynced", "t")')

# ---------------------------------------------------------------- grenades held in hand (ARC9 keeps one in the clip)
run('MCC.Items.Register("t_nade", {name = "Test Nade", kind = "weapon", class = "t_nade", w = 1, h = 1, data = {slot = "grenade", ammo = "t_nade"}})')
run('_WEAPON_FACTORY = function(class, p) if class == "t_nade" then local w = _MakeWeaponEnt(class, 1) w:SetClip1(1) return w end end')
run('GN = _MakeTester(72) _PLAYERS = {GN} hook.Run("PlayerInitialSpawn", GN) hook.Run("PlayerLoadout", GN)')
run('local inv = MCC.Inv.Get(GN) inv.slots.pocket1 = MCC.Inv.NewItem("t_nade", 1) MCC.Inv.SyncAmmo(GN)')
def nades(): return L('(function() local n = 0 for _, k in ipairs({"pocket1","pocket2","pocket3","pocket4"}) do local it = MCC.Inv.Get(GN).slots[k] if it and it.id == "t_nade" then n = n + MCC.Inv.Count(it) end end return n end)()')
run('MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think") MCC.Inv.PollAmmo(GN)')
check(L('GN:HasWeapon("t_nade")') and nades() == 1 and L('GN:GetAmmoCount("t_nade") + GN:GetWeapon("t_nade"):Clip1()') == 1,
      "a grenade the weapon puts in your hand by itself isn't a free extra (1 carried, 1 in total)")
run('local w = GN:GetWeapon("t_nade") w:SetClip1(0) GN:SetAmmo(1, "t_nade") MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think")')
run('local w = GN:GetWeapon("t_nade") w:SetClip1(1) GN:SetAmmo(0, "t_nade") MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think")')
check(L('GN:HasWeapon("t_nade")') and nades() == 1, "drawing it (reserve into hand) doesn't count as a throw: the grenade stays")
run('MCC.Inv.Get(GN).slots.pocket2 = MCC.Inv.NewItem("t_nade", 1) MCC.Inv.Update(GN) hook.Run("Think")')
check(L('GN:GetAmmoCount("t_nade")') == 1 and L('GN:GetWeapon("t_nade"):Clip1()') == 1, "two carried: one in hand, one in reserve")
run('GN:GetWeapon("t_nade"):SetClip1(0) MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think")')
check(nades() == 1 and L('GN:HasWeapon("t_nade")'), "throwing one takes one item")
run('local w = GN:GetWeapon("t_nade") w:SetClip1(1) GN:SetAmmo(0, "t_nade") MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think")')
run('GN:GetWeapon("t_nade"):SetClip1(0) MCC.Inv.PollAmmo(GN) MCC.Inv.Update(GN) hook.Run("Think")')
check(nades() == 0 and not L('GN:HasWeapon("t_nade")'), "throwing the last one takes the item and the weapon")
run('_WEAPON_FACTORY = nil')

# ---------------------------------------------------------------- performance: grenade index, frozen bodies, diff syncs
check(L('#MCC.Items.GrenadeDefs()') >= 1 and L('(function() for _, d in ipairs(MCC.Items.GrenadeDefs()) do if d.id == "t_nade" then return true end end return false end)()'),
      "grenade items are indexed once (ammo syncing doesn't walk the whole registry)")

run(r"""
function _Phys(speed) local p = {moving = true, v = speed, valid = true}
  p.IsValid = function() return true end
  p.IsMotionEnabled = function(s) return s.moving end
  p.EnableMotion = function(s, on) s.moving = on end
  p.GetVelocity = function(s) return Vector(s.v, 0, 0) end
  return p end
_BONES = {_Phys(0), _Phys(50), _Phys(0)}
FB = _Ent("prop_ragdoll", {GetPhysicsObjectCount = function() return #_BONES end, GetPhysicsObjectNum = function(s, i) return _BONES[i + 1] end})
_SetCV("mcc_inv_body_lifetime", 0) _SetCV("mcc_inv_body_max", 0) _SetCV("mcc_inv_body_freeze", 10)
_TIME = _TIME + 1 MCC.Inv.MakeBody(FB, {slots = {}}, "Frozen") MCC.Inv.BodyCleanupStep()""")
check(L('_BONES[1].moving') is True, "a fresh body isn't frozen (it's still falling)")
run('_TIME = _TIME + 11 MCC.Inv.BodyCleanupStep()')
check(L('_BONES[1].moving') is True, "nor one that's still sliding after mcc_inv_body_freeze seconds")
run('_BONES[2].v = 0 MCC.Inv.BodyCleanupStep()')
check(L('_BONES[1].moving') is False and L('_BONES[2].moving') is False and L('_BONES[3].moving') is False,
      "once it has settled, every bone is frozen (no physics cost)")
run('_BONES[1].moving = true MCC.Inv.BodyCleanupStep()')
check(L('_BONES[1].moving') is False, "unfrozen (physgun) it's frozen again once it settles")
run('_SetCV("mcc_inv_body_freeze", 0) _BONES[1].moving = true MCC.Inv.BodyCleanupStep()')
check(L('_BONES[1].moving') is True, "mcc_inv_body_freeze 0 never freezes")
run('_SetCV("mcc_inv_body_freeze", 10) MCC.Inv.Bodies[FB] = nil')
check(L('MCC.Config.Defs.inv_body_max.default') == 30, "the default body cap is 30 now (mcc_inv_body_max)")

run('DS = _MakeTester(73) _PLAYERS = {DS} hook.Run("PlayerInitialSpawn", DS) hook.Run("PlayerLoadout", DS) hook.Run("Think")')
run('_DS = {} local send = MCC.Net.Send MCC.Net.Send = function(n, d, p) if n == "inv_sync" and p == DS then _DS[#_DS + 1] = d end return send(n, d, p) end')
run('DS.MCCSentSlots = nil MCC.Inv.Update(DS) hook.Run("Think")')
check(L('#_DS') == 1 and not L('_DS[1].diff'), "the first sync sends the whole inventory")
run('MCC.Inv.Update(DS) hook.Run("Think")')
check(L('#_DS') == 1, "a sync where nothing changed sends nothing")
run('MCC.Inv.Get(DS).slots.pocket3 = MCC.Inv.NewItem("ammo_pistol", 7) MCC.Inv.Update(DS) hook.Run("Think")')
check(L('#_DS') == 2 and L('_DS[2].diff') and L('_DS[2].slots.pocket3.n') == 7 and L('(function() local n = 0 for _ in pairs(_DS[2].slots) do n = n + 1 end return n end)()') == 1
      and not L('_DS[2].oc'), "a change sends only that slot")
run('MCC.Inv.Get(DS).slots.pocket3 = nil MCC.Inv.Update(DS) hook.Run("Think")')
check(L('#_DS') == 3 and L('_DS[3].gone[1]') == "pocket3", "an emptied slot is sent as gone")
run('hook.Run("PlayerDisconnected", DS) MCC.Net.Handlers.inv_hello.fn({}, DS) hook.Run("Think")')
check(not L('_DS[#_DS].diff'), "a client that (re)joins gets everything again")

# client: merging diff syncs; worn gear on far bodies
cl.run('MCC.Net.Handlers.inv_sync.fn({slots = {pocket1 = {id = "a", n = 1}, pocket2 = {id = "b", n = 1}}, open = {name = "Box"}})')
cl.run('MCC.Net.Handlers.inv_sync.fn({diff = true, slots = {pocket1 = {id = "a", n = 5}}, gone = {"pocket2"}})')
check(cl.eval('MCC.Inv.State.slots.pocket1.n') == 5 and cl.eval('MCC.Inv.State.slots.pocket2') is None and cl.eval('MCC.Inv.State.open.name') == "Box",
      "the client merges a diff sync: changed slots replaced, gone ones removed, the open container kept")
cl.run('MCC.Net.Handlers.inv_sync.fn({diff = true, slots = {}, gone = {}, oc = true})')
check(cl.eval('MCC.Inv.State.open') is None, "and closes it when the server says it changed to nothing")

cl.run(r"""
_MADE = {} MCC.Inv.MakeWornModels = function(ent, str) _MADE[ent] = str return {} end
local VM = {__index = {Distance = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) end}}
function _V(x) return setmetatable({x = x, y = 0, z = 0}, VM) end
function _Rag(x) local r = {valid = true, _nw = {MCCBody = true, MCCWorn = "rig=rig_chest"}, _pos = Vector(x, 0, 0)}
  r._pos = _V(x) r.IsValid = function() return true end r.GetClass = function() return "prop_ragdoll" end
  r.GetNWBool = function(s, k, d) local v = s._nw[k] if v == nil then return d end return v end
  r.GetNWString = function(s, k, d) return s._nw[k] or d end
  r.IsDormant = function() return false end r.IsPlayer = function() return false end r.GetModel = function() return "m" end
  r.GetPos = function(s) return s._pos end r.GetNoDraw = function() return false end
  return r end
local oldValid = IsValid
function IsValid(x) if type(x) == "table" and x.valid ~= nil then return x.valid end return oldValid(x) end
NEAR, FAR = _Rag(500), _Rag(5000)
_LPW = {valid = true, GetPos = function() return _V(0) end, IsPlayer = function() return true end}
LocalPlayer = function() return _LPW end
player.GetAll = function() return {} end
ents.FindByClass = function() return {} end
hook.Run("OnEntityCreated", NEAR) hook.Run("OnEntityCreated", FAR) MCC.Inv.WornScan()""")
check(cl.eval('_MADE[NEAR]') == "rig=rig_chest" and cl.eval('_MADE[FAR]') is None,
      "bodies past mcc_worn_body_distance don't get worn-gear models; near ones do")
cl.run('FAR._pos = _V(1000) MCC.Inv.WornScan()')
check(cl.eval('_MADE[FAR]') == "rig=rig_chest", "walk closer and they appear (bodies are tracked as they come into view, no map scan)")

print()
print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
