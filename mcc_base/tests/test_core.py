import glob, json, os, random, string, sys
sys.path.insert(0, os.path.dirname(__file__))
from gmod_mock import Realm, transfer, LUA_ROOT
from lupa.luajit21 import LuaRuntime

failures = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)

# 1. Syntax: every file compiles under LuaJIT 2.1 (GMod's Lua)
bare = LuaRuntime()
for path in sorted(glob.glob(LUA_ROOT + "/**/*.lua", recursive=True)):
    ok, err = bare.eval('function(p) local f, e = loadfile(p) return f ~= nil, e end')(path)
    check(ok, "compiles: " + os.path.relpath(path, LUA_ROOT) + ("" if ok else " -> " + str(err)))

# 2. Server boot
sv = Realm("server")
sv.load_mcc()
sv.boot()
check(sv.eval("MCC.Ready") is True, "server boots and MCC.Ready is set")
check(sv.eval("MCC.AI") is None, "MCC Base is just the core: NPC AI lives in the MCC AI Behaviors addon")
check(sv.eval("MCC.Items.Count()") == 36, "36 default items registered (roubles included, the old rig_scav gone) (got %s)" % sv.eval("MCC.Items.Count()"))
log = "\n".join(sv.log())
check("ready" in log, "ready line logged")
check("JMod not installed" in log, "missing JMod is reported")
check(sv.eval("MCC.Compat.Has('jmod')") is False, "Compat.Has('jmod') false without JMod")
check(sv.eval("MCC.Items.Get('ammo_pistol').maxStack") == 50, "ammo stack 50")
check(sv.eval("MCC.Items.Get('weapon_ar2').maxStack") == 1, "weapons don't stack")
check(sv.eval("MCC.Items.FromClass('weapon_smg1')") == "weapon_smg1", "class index works")
check(sv.eval("MCC.Items.Price('weapon_smg1')") == 900, "price with multiplier 1")
sv.run('_SetCV("mcc_price_mult", 1.5)')
check(sv.eval("MCC.Items.Price('weapon_smg1')") == 1350, "price multiplier applies")
sv.run('_SetCV("mcc_price_mult", 1)')
check(os.path.exists(os.path.join(sv.datadir, "mcc/items.json")), "items.json created")
check(os.path.exists(os.path.join(sv.datadir, "mcc/README.txt")), "README.txt created")

# 3. items.json overrides
with open(os.path.join(sv.datadir, "mcc/items.json"), "w") as f:
    json.dump({
        "weapon_ar2": {"price": 1500, "data": {"feed": "mag"}},
        "weapon_rpg": False,
        "custom_intel": {"name": "Intel Folder", "kind": "misc", "price": 400},
        "bad_item": {"name": "Broken", "kind": "nope"},
        "weapon_pistol": {"w": 99},
    }, f)
sv.run('_CMDS["mcc_reload_config"](nil, "mcc_reload_config", {})')
check(sv.eval("MCC.Items.Get('weapon_ar2').price") == 1500, "override changes price")
check(sv.eval("MCC.Items.Get('weapon_ar2').data.mag") == "mag_ar2", "override keeps untouched data fields (deep merge)")
check(sv.eval("MCC.Items.Get('weapon_rpg')") is None, "false removes an item")
check(sv.eval("MCC.Items.Get('custom_intel').maxStack") == 50, "new misc item gets default stack")
check(sv.eval("MCC.Items.Get('bad_item')") is None, "invalid kind rejected")
check(sv.eval("MCC.Items.Get('weapon_pistol').w") == 2, "out-of-range override ignored, original kept")
log = "\n".join(sv.log())
check("bad_item" in log and "weapon_pistol" in log, "rejected overrides are logged")

# 4. Admin commands (server console = always allowed)
def cmd(name, *args):
    sv.lua.globals()._CMDS[name](None, name, sv.lua.table_from(list(args)))

cmd("mcc_item_set", "weapon_smg1", "price", "1000")
check(sv.eval("MCC.Items.Get('weapon_smg1').price") == 1000, "item_set changes price")
saved = json.load(open(os.path.join(sv.datadir, "mcc/items.json")))
check(saved.get("weapon_smg1", {}).get("price") == 1000, "item_set is saved to items.json")
cmd("mcc_item_set", "weapon_smg1", "w", "99")
check(sv.eval("MCC.Items.Get('weapon_smg1').w") == 3, "item_set rejects invalid value")
cmd("mcc_item_set", "weapon_smg1", "data.feed", "tube")
check(sv.eval("MCC.Items.Get('weapon_smg1').data.feed") == "tube", "item_set edits data.<key>")
check(sv.eval("MCC.Items.Get('weapon_smg1').data.mag") == "mag_smg1", "data edit keeps other data keys")
cmd("mcc_item_addweapon", "tfa_test_ak", "2500")
ak = sv.eval("MCC.Items.Get('tfa_test_ak')")
check(ak is not None and ak.w == 5 and ak.h == 2 and ak.price == 2500 and ak.data.slot == "primary",
      "addweapon sizes a SWEP from its hold type")
cmd("mcc_item_addweapon", "test_knife")
kn = sv.eval("MCC.Items.Get('test_knife')")
check(kn is not None and kn.data.slot == "melee" and kn.model == "models/props_junk/cardboard_box004a.mdl",
      "addweapon handles melee and empty world model")
cmd("mcc_item_addweapon", "not_a_weapon")
check(sv.eval("MCC.Items.Get('not_a_weapon')") is None, "addweapon refuses unknown classes")
cmd("mcc_item_remove", "weapon_crowbar")
check(sv.eval("MCC.Items.Get('weapon_crowbar')") is None, "item_remove removes")
cmd("mcc_item_reset", "weapon_crowbar")
check(sv.eval("MCC.Items.Get('weapon_crowbar')") is not None, "item_reset restores")
cmd("mcc_item_remove", "tfa_test_ak")
saved = json.load(open(os.path.join(sv.datadir, "mcc/items.json")))
check("tfa_test_ak" not in saved and sv.eval("MCC.Items.Get('tfa_test_ak')") is None,
      "removing a data-file-only item deletes its entry")
cmd("mcc_help")
cmd("mcc_version")

# 5. Client sync over chunked net
cl = Realm("client")
cl.load_mcc()
cl.boot()
sv.run('_SetCV("mcc_inv_enabled", 0)')  # this section tests networking only
# drain broadcasts queued by the reload/commands above (no client was listening yet)
for _ in range(50):
    sv.run('_TICK = _TICK + 1; hook.Run("Think")')
sv.outbox()
sv.run('_PLY = _MakePlayer(7, "Tester", false, false)')
ply = sv.eval("_PLY")
cl.run('hook.Run("InitPostEntity")')
n = transfer(cl, sv, ply)
check(n >= 1, "client asks for the item registry on join")
n = transfer(sv, cl)
check(n >= 1, "server answers with items_sync")
check(cl.eval("MCC.Items.Count()") == sv.eval("MCC.Items.Count()"),
      "client registry matches server (%s vs %s)" % (cl.eval("MCC.Items.Count()"), sv.eval("MCC.Items.Count()")))
check(cl.eval("MCC.Items.Get('weapon_ar2').price") == 1500, "client sees server overrides")
check(cl.eval("MCC.Items.Get('rig_chest').data.cells[8].w") == 2, "nested arrays survive the trip")

# request spam is ignored for 10 seconds
cl.run('MCC.Net.Send("items_request", {})')
transfer(cl, sv, ply)
check(transfer(sv, cl) == 0, "repeat request within 10s is ignored")

# 6. Large payloads split into chunks and rebuild exactly
blob = "".join(random.choice(string.ascii_letters) for _ in range(400000))
cl.run('_GOT = nil MCC.Net.Receive("bigtest", function(d) _GOT = d.blob end)')
sv.lua.globals().MCC.Net.Send("bigtest", sv.lua.table_from({"blob": blob}), ply)
first_tick = len(sv.outbox())
check(first_tick <= 4, "at most 4 chunks sent per tick (sent %d)" % first_tick)
# put them back by re-sending cleanly through transfer
cl.run('_GOT = nil')
sv.lua.globals().MCC.Net.Send("bigtest", sv.lua.table_from({"blob": blob}), ply)
n = transfer(sv, cl)
check(n > 1, "large payload used %d chunks" % n)
check(cl.eval("_GOT") == blob, "large payload rebuilt exactly")

# 7. Clients can't send to handlers that don't allow it, or past maxBytes
sv.run('_HIT = 0 MCC.Net.Receive("server_only", function() _HIT = _HIT + 1 end)')
cl.run('MCC.Net.Send("server_only", {x = 1})')
transfer(cl, sv, ply)
check(sv.eval("_HIT") == 0, "client can't reach a server-only handler")
sv.run('_TIME = 100')
cl.run('local t = {} for i = 1, 5000 do t[i] = string.char(math.random(65, 90)) end MCC.Net.Send("items_request", {pad = table.concat(t)})')
transfer(cl, sv, ply)
check(transfer(sv, cl) == 0, "oversized client payload dropped")
cl.run('MCC.Net.Send("items_request", {})')
transfer(cl, sv, ply)
check(transfer(sv, cl) >= 1, "normal request after cooldown still answered")

# 8. SQLite key-value store
sv.run('MCC.Data.Set("stash", "765", {items = {{id = "ammo_pistol", n = 30}}})')
check(sv.eval('MCC.Data.Get("stash", "765").items[1].n') == 30, "Data.Set/Get round trip")
sv.run('MCC.Data.Set("stash", "765", {items = {}})')
check(sv.eval('#MCC.Data.Get("stash", "765").items') == 0, "Data.Set replaces")
sv.run('MCC.Data.Set("stash", "999", {a = 1})')
check(sv.eval('MCC.Data.GetAll("stash")["999"].a') == 1, "Data.GetAll")
sv.run('MCC.Data.Delete("stash", "999")')
check(sv.eval('MCC.Data.Get("stash", "999")') is None, "Data.Delete")
check(sv.eval("(function() local saved = false hook.Add('MCC_Save', 't', function() saved = true end) MCC.Data.SaveAll('test') return saved end)()"),
      "SaveAll runs MCC_Save hooks")

# 9. Expansion boot order: an expansion that adds hooks before MCC exists still loads
ex = Realm("server")
ex.run('''
hook.Add("MCC_Loaded", "exp", function(M) _LOADED = M.API_VERSION end)
hook.Add("MCC_RegisterItems", "exp", function(I)
    I.RegisterKind("attachment", {stackable = false})
    I.Register("att_scope", {name = "Scope", kind = "attachment"})
end)
hook.Add("MCC_Ready", "exp", function() _READY = true end)
''')
ex.load_mcc()
ex.boot()
check(ex.eval("_LOADED") == 1 and ex.eval("_READY") is True, "expansion hooks fire in order")
check(ex.eval("MCC.Items.Get('att_scope') ~= nil"), "expansion can add a new kind and item")
ex.run('MCC.Items.Rebuild()')
check(ex.eval("MCC.Items.Get('att_scope') ~= nil"), "expansion items survive a rebuild")

# ---------------------------------------------------------------- gameplay tweaks
check(cl.eval('hook.t.DrawDeathNotice.MCC_HideKillfeed()') is False, "the kill feed is hidden by default (mcc_hide_killfeed)")
cl.run('_SetCV("mcc_hide_killfeed", 0)')
check(cl.eval('hook.t.DrawDeathNotice.MCC_HideKillfeed()') is None, "and shows with mcc_hide_killfeed 0")
sv.run('''
_W = function(c) return {valid = true, GetClass = function() return c end} end
_PL = {valid = true, IsPlayer = function() return true end, IsNPC = function() return false end, GetActiveWeapon = function() return _W("weapon_smg1") end}
_NP = {valid = true, IsPlayer = function() return false end, IsNPC = function() return true end, GetActiveWeapon = function() return _W("weapon_ar2") end}
_D = function(t) return {GetDamageType = function() return t end, IsExplosionDamage = function() return t == DMG_BLAST end} end
''')
check(sv.eval('MCC.HL2DamageMult(_PL, _D(DMG_BULLET))') == 1.25, "HL2 guns hit 25% harder in players' hands (mcc_hl2_damage_mult)")
check(sv.eval('MCC.HL2DamageMult(_NP, _D(DMG_BULLET))') == 1, "NPCs' stay stock (mcc_hl2_damage_mult_npc)")
check(sv.eval('MCC.HL2DamageMult(_PL, _D(DMG_BLAST))') == 1, "explosions (SMG grenades) aren't buffed")
sv.run('_PL.GetActiveWeapon = function() return _W("arc9_m4") end')
check(sv.eval('MCC.HL2DamageMult(_PL, _D(DMG_BULLET))') == 1, "other weapon packs aren't touched")

print()
print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
