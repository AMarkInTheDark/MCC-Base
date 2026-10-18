import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gmod_mock import Realm

failures = []
def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        failures.append(msg)

SETUP = r'''
-- weapons and players as userdata, like GMod. Entities accept custom fields (ply.Foo = x) like GMod's.
local function Ent(methods)
  local u = newproxy(true) local m = getmetatable(u) m.valid = true
  local fields = {}
  m.__index = function(_, k) local v = methods[k] if v ~= nil then return v end return fields[k] end
  m.__newindex = function(_, k, v) fields[k] = v end
  return u
end
function _MakeWeapon(class, created, owner)
  return Ent({GetClass = function() return class end, GetCreationTime = function() return created end,
    IsWeapon = function() return true end, GetOwner = function() return owner end})
end
function _MakeGamer(active)
  _DROPS = {}
  return Ent({Alive = function() return true end, GetActiveWeapon = function() return active end,
    GetAimVector = function() return 1 end, GetVelocity = function() return 0 end,
    DropWeapon = function(self, w) _DROPS[#_DROPS + 1] = w:GetClass() end,
    PickupWeapon = function(self, w) return hook.Run("PlayerCanPickupWeapon", self, w) ~= false end,
    UserID = function() return 1 end})
end
'''

def fresh():
    sv = Realm("server")
    sv.load_mcc()
    sv.run(SETUP)
    return sv

sv = fresh()
sv.boot()
sv.run('_SetCV("mcc_inv_enabled", 0)')  # pickup and drop on their own; the inventory has its own tests
sv.run('_TIME = 50')
check(sv.eval('MCC.Pickup.Active()') is True, "pickup rules active without the Tarkov addon")
check(sv.eval('(hook.Run("PlayerCanPickupWeapon", _MakeGamer(), _MakeWeapon("weapon_smg1", 10)))') is False,
      "walking over a world weapon doesn't pick it up")
check(sv.eval('(hook.Run("PlayerCanPickupWeapon", _MakeGamer(), _MakeWeapon("weapon_smg1", 49.95)))') is None,
      "a weapon Give()n this instant (spawn menu, loadout) is allowed")
check(sv.eval('MCC.Pickup.TakeWeapon(_MakeGamer(), _MakeWeapon("weapon_smg1", 10))') is True,
      "E pickup is allowed through the no-auto rule")
check(sv.eval('(hook.Run("PlayerCanPickupItem", _MakeGamer(), {MCCAllowUntil = 0}))') is False,
      "walking over an item doesn't pick it up")
check(sv.eval('(hook.Run("PlayerCanPickupItem", _MakeGamer(), {MCCAllowUntil = 51}))') is None,
      "an item pressed with E is allowed")
check(sv.eval('MCC.Pickup.Kind(_MakeWeapon("weapon_ar2", 1, nil))') == "weapon", "unowned weapon is a pickup")
check(sv.eval('MCC.Pickup.Kind(_MakeWeapon("weapon_ar2", 1, _MakeGamer()))') is None, "held weapon is not a pickup")

# dropping
sv.run('_P = _MakeGamer(_MakeWeapon("weapon_smg1", 1))')
sv.run('_CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 1, "mcc_drop drops the active weapon")
sv.run('_CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 1, "drop has a short cooldown")
sv.run('_TIME = 60 _P = _MakeGamer(_MakeWeapon("weapon_physgun", 1)) _CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 0, "physgun can't be dropped")
sv.run('_TIME = 70 _SetCV("mcc_drop_blacklist", "weapon_rpg") _P = _MakeGamer(_MakeWeapon("weapon_rpg", 1)) _CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 0, "drop blacklist cvar is respected")
sv.run('_TIME = 80 _SetCV("mcc_drop_enabled", 0) _P = _MakeGamer(_MakeWeapon("weapon_smg1", 1)) _CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 0, "drop can be turned off")
sv.run('_SetCV("mcc_drop_enabled", 1)')
sv.run('_TIME = 90 hook.Add("MCC_DropWeapon", "inv", function() return true end) _P = _MakeGamer(_MakeWeapon("weapon_smg1", 1)) _CMDS["mcc_drop"](_P)')
check(sv.eval('#_DROPS') == 0, "an inventory can take over the drop through MCC_DropWeapon")

# Tarkov Inventory installed: MCC stands down on pickup and drops through it
tk = fresh()
tk.run(r'''
TK = {Config = {OpenKey = 1, GrenadeAmmo = {weapon_frag = "Grenade"}}}
_TKDROPPED = nil
local inv = {slots = {primary = {id = 42, class = "weapon_smg1"}}}
TK.Get = function() return inv end
TK.Drop = function(ply, id) _TKDROPPED = id end
TK.Update = function() end
''')
tk.boot()
tk.run('_TIME = 50')
check(tk.eval('MCC.Pickup.Active()') is False, "with Tarkov Inventory installed, MCC pickup stands down")
check(tk.eval('(hook.Run("PlayerCanPickupWeapon", _MakeGamer(), _MakeWeapon("weapon_smg1", 10)))') is None,
      "MCC doesn't block pickups the Tarkov addon handles")
tk.run('_P = _MakeGamer(_MakeWeapon("weapon_smg1", 1)) _CMDS["mcc_drop"](_P)')
check(tk.eval('_TKDROPPED') == 42 and tk.eval('#_DROPS') == 0, "drop key goes through the Tarkov inventory slot")
tk.run('_TIME = 60 _P = _MakeGamer(_MakeWeapon("weapon_frag", 1)) _CMDS["mcc_drop"](_P)')
check(tk.eval('#_DROPS') == 0, "rig grenades aren't dropped out from under the inventory")

# client loads (drop key cvar exists)
cl = Realm("client")
cl.load_mcc()
cl.boot()
check(cl.eval('GetConVar("mcc_drop_key"):GetInt()') == 17, "client drop key defaults to G")

print()
print("%d failure(s)" % len(failures))
sys.exit(1 if failures else 0)
