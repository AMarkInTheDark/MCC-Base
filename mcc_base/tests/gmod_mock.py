"""Minimal Garry's Mod API mock on LuaJIT (lupa) for testing MCC Base logic outside the game."""
import json, os, sqlite3, zlib, tempfile
from lupa.luajit21 import LuaRuntime

LUA_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lua")

PRELUDE = r"""
local realm = ...
SERVER = realm == "server"
CLIENT = realm == "client"
FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY = 128, 8192, 256
HUD_PRINTCONSOLE = 2
bit = require("bit")
DMG_GENERIC, DMG_BULLET, DMG_SLASH, DMG_BURN, DMG_BLAST, DMG_CLUB, DMG_NEVERGIB, DMG_BUCKSHOT = 0, 2, 4, 8, 64, 128, 4096, 536870912
_LOG = {}
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
function MsgC(...) local t = {} for _, v in ipairs({...}) do if type(v) == "string" then t[#t+1] = v end end _LOG[#_LOG+1] = table.concat(t) end
function istable(v) return type(v) == "table" end
function math.Clamp(v, lo, hi) return math.min(math.max(v, lo), hi) end
function math.Round(v, d) local m = 10 ^ (d or 0) return math.floor(v * m + 0.5) / m end
function isstring(v) return type(v) == "string" end
function IsValid(v)
  if type(v) == "userdata" then local m = getmetatable(v) return m and m.valid == true end
  return type(v) == "table" and v.valid == true
end
-- Players are userdata in GMod; newproxy gives the mock the same type.
function _MakePlayer(id, name, admin, superadmin)
  local p = newproxy(true)
  local m = getmetatable(p)
  m.valid = true
  m.__index = {UserID = function() return id end, Nick = function() return name end,
    IsAdmin = function() return admin end, IsSuperAdmin = function() return superadmin end,
    PrintMessage = function() end, ChatPrint = function() end, SteamID64 = function() return tostring(id) end}
  return p
end
function AddCSLuaFile() end
function string.GetFileFromFilename(p) return p:match("([^/]+)$") end
function table.Copy(t, seen)
  if type(t) ~= "table" then return t end
  seen = seen or {}
  if seen[t] then return seen[t] end
  local o = {} seen[t] = o
  for k, v in pairs(t) do o[k] = type(v) == "table" and table.Copy(v, seen) or v end
  return o
end
function table.Merge(dest, src)
  for k, v in pairs(src) do
    if type(v) == "table" and type(dest[k]) == "table" then table.Merge(dest[k], v) else dest[k] = v end
  end
  return dest
end
function table.GetKeys(t) local o = {} for k in pairs(t) do o[#o+1] = k end return o end
function table.Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end
function table.HasValue(t, v) for _, x in pairs(t) do if x == v then return true end end return false end
_TIME = 0
function CurTime() return _TIME end
_TICK = 0
engine = {TickCount = function() return _TICK end}
-- hooks
hook = {t = {}}
function hook.Add(ev, id, fn) hook.t[ev] = hook.t[ev] or {} hook.t[ev][id] = fn end
function hook.Remove(ev, id) if hook.t[ev] then hook.t[ev][id] = nil end end
function hook.Run(ev, ...) for _, fn in pairs(hook.t[ev] or {}) do local a, b = fn(...) if a ~= nil then return a, b end end end
-- timers
timer = {t = {}}
function timer.Create(n, d, r, f) timer.t[n] = {d = d, f = f} end
function timer.Exists(n) return timer.t[n] ~= nil end
function timer.Adjust(n, d) timer.t[n].d = d end
function timer.Simple(d, f) end
-- cvars
local CV = {}
local cvmeta = {__index = {
  GetBool = function(s) return tonumber(s.v) ~= 0 end,
  GetFloat = function(s) return tonumber(s.v) or 0 end,
  GetInt = function(s) return math.floor(tonumber(s.v) or 0) end,
  GetString = function(s) return s.v end,
}}
function CreateConVar(n, v, f, h, mn, mx) CV[n] = setmetatable({v = v}, cvmeta) return CV[n] end
function CreateClientConVar(n, v) return CreateConVar(n, v) end
KEY_G, IN_USE, IN_RELOAD, MASK_SHOT = 17, 32, 8192, 1174421507
surface = {CreateFont = function() end}
function Material() return {SetFloat = function() end, Recompute = function() end} end
vgui = {Register = function() end}
KEY_I, KEY_R, KEY_TAB, KEY_ESCAPE = 19, 28, 67, 70
player = {GetAll = function() return {} end}
list = {Get = function() return {} end}
game = {SinglePlayer = function() return _SP or false end}
function RunConsoleCommand(...) _RCC = {...} end
function Entity(i) return _ENTS and _ENTS[i] end
NULL = setmetatable({}, {__index = function() return function() end end})
if CLIENT then LocalPlayer = LocalPlayer or function() return NULL end end
_GLOBALS = {}
function SetGlobalFloat(k, v) _GLOBALS[k] = v end
function GetGlobalFloat(k, d) local v = _GLOBALS[k] if v == nil then return d or 0 end return v end
local function FindByClass(c)
  local o = {}
  for _, e in ipairs(_ENTS or {}) do if IsValid(e) and e:GetClass() == c then o[#o + 1] = e end end
  return o
end
_FindByClass = FindByClass
ents = ents or {FindByClass = FindByClass}
function Vector(x, y, z) return {x = x, y = y, z = z} end
function GetConVar(n) return CV[n] end
function _SetCV(n, v) CV[n].v = tostring(v) end
cvars = {AddChangeCallback = function() end}
-- concommands
_CMDS = {}
concommand = {Add = function(n, f) _CMDS[n] = f end}
-- weapons
weapons = {Get = function(c)
  if c == "tfa_test_ak" then return {PrintName = "Test AK", HoldType = "ar2", WorldModel = "models/w_ak.mdl", Category = "TFA", Primary = {Ammo = "AR2"}} end
  if c == "test_knife" then return {PrintName = "Knife", HoldType = "knife", WorldModel = ""} end
  if c == "arc9_test_mp5" then return {PrintName = "#arc9_mp5", HoldType = "smg", Slot = 2, WorldModel = "models/w_mp5.mdl",
    Category = "ARC9", Primary = {Ammo = "9x19MM", ClipSize = 30}} end
end}
-- net (records writes; Python moves messages between realms)
_OUT = {}
_NETRECV = {}
local cur
net = {}
function net.Start(n) cur = {name = n, vals = {}} end
local function w(v) cur.vals[#cur.vals+1] = v end
net.WriteString = w
net.WriteUInt = function(v) w(v) end
net.WriteData = function(d, n) w(d) end
local function finish(target) cur.target = target _OUT[#_OUT+1] = cur cur = nil end
net.Send = function(t) finish(t) end
net.Broadcast = function() finish("all") end
net.SendToServer = function() finish("server") end
function net.Receive(n, f) _NETRECV[n] = f end
local rd
function _NetDeliver(msg, ply) rd = {vals = msg.vals, i = 0} _NETRECV[msg.name](0, ply) end
local function r() rd.i = rd.i + 1 return rd.vals[rd.i] end
net.ReadString = r
net.ReadUInt = function() return r() end
net.ReadData = function() return r() end
-- other addons' lua folders (expansions) are searched after MCC Base's
function include(p)
  local f, err = loadfile(_ROOT .. "/" .. p)
  if not f then
    for _, r in ipairs(_EXTRA_ROOTS or {}) do
      local g = loadfile(r .. "/" .. p)
      if g then f = g break end
    end
  end
  assert(f, err)()
end
"""

def lua_to_py(lua, v):
    if lua_type(lua, v) == "table":
        keys = list(v.keys())
        if keys and all(isinstance(k, int) for k in keys) and sorted(keys) == list(range(1, len(keys) + 1)):
            return [lua_to_py(lua, v[k]) for k in range(1, len(keys) + 1)]
        if not keys:
            return {}
        return {str(k): lua_to_py(lua, v[k]) for k in keys}
    return v

def lua_type(lua, v):
    return lua.globals().type(v)

def py_to_lua(lua, v):
    if isinstance(v, dict):
        return lua.table_from({k: py_to_lua(lua, x) for k, x in v.items()})
    if isinstance(v, list):
        return lua.table_from([py_to_lua(lua, x) for x in v])
    return v


class Realm:
    def __init__(self, realm, datadir=None, extra_roots=()):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g._ROOT = LUA_ROOT
        g._EXTRA_ROOTS = self.lua.table_from([os.path.abspath(r) for r in extra_roots])
        self.lua.execute(PRELUDE, realm)
        self.datadir = datadir or tempfile.mkdtemp()
        self.db = sqlite3.connect(":memory:")
        self.db.row_factory = sqlite3.Row
        self.last_sql_error = None
        lua = self.lua

        def to_json(t, pretty=False):
            return json.dumps(lua_to_py(lua, t), indent=2 if pretty else None)

        def from_json(s):
            try:
                return py_to_lua(lua, json.loads(s))
            except Exception:
                return None

        def compress(s):
            import base64
            return base64.b64encode(zlib.compress(s.encode() if isinstance(s, str) else s)).decode()

        def decompress(s, limit=None):
            import base64
            out = zlib.decompress(base64.b64decode(s)).decode()
            if limit is not None and len(out) > limit:
                return None
            return out

        g.util = lua.table_from({"TableToJSON": to_json, "JSONToTable": from_json,
                                 "Compress": compress, "Decompress": decompress,
                                 "AddNetworkString": lambda n: None})

        def fpath(p):
            return os.path.join(self.datadir, p)

        def fread(p, where):
            try:
                return open(fpath(p)).read()
            except FileNotFoundError:
                return None

        def fwrite(p, s):
            os.makedirs(os.path.dirname(fpath(p)), exist_ok=True)
            open(fpath(p), "w").write(s)

        g.file = lua.table_from({"Read": fread, "Write": fwrite,
                                 "Exists": lambda p, w: os.path.exists(fpath(p)),
                                 "CreateDir": lambda p: os.makedirs(fpath(p), exist_ok=True)})

        def query(q):
            try:
                cur = self.db.execute(q)
                rows = cur.fetchall()
                self.db.commit()
                if not rows:
                    return None
                return lua.table_from([lua.table_from(dict(r)) for r in rows])
            except Exception as e:
                self.last_sql_error = str(e)
                return False

        def query_row(q):
            res = query(q)
            if not res:
                return None
            return res[1]

        g.sql = lua.table_from({"Query": query, "QueryRow": query_row,
                                "SQLStr": lambda s: "'" + str(s).replace("'", "''") + "'",
                                "LastError": lambda: self.last_sql_error,
                                "Begin": lambda: None, "Commit": lambda: None})
        g.os.time = lambda: 1000

    def run(self, code, *args):
        return self.lua.execute(code, *args)

    def eval(self, code):
        return self.lua.eval(code)

    def load_mcc(self):
        self.run('include("autorun/mcc_base_init.lua")')

    def boot(self):
        self.run('hook.Run("Initialize")')

    def outbox(self):
        g = self.lua.globals()
        msgs = [g._OUT[i] for i in range(1, len(g._OUT) + 1)]
        self.run("_OUT = {}")
        return msgs

    def log(self):
        g = self.lua.globals()
        return [g._LOG[i] for i in range(1, len(g._LOG) + 1)]


def transfer(src, dst, sender_ply=None):
    """Move every queued net message from src to dst. Pumps the sender's queue first."""
    delivered = 0
    for _ in range(1000):
        src.run('_TICK = _TICK + 1; hook.Run("Think")')
        msgs = src.outbox()
        if not msgs:
            # queue may still hold chunks; one more pump
            src.run('_TICK = _TICK + 1; hook.Run("Think")')
            msgs = src.outbox()
            if not msgs:
                break
        for m in msgs:
            copy = dst.lua.table_from({"name": m.name, "vals": dst.lua.table_from([m.vals[i] for i in range(1, len(m.vals) + 1)])})
            dst.lua.globals()._NetDeliver(copy, sender_ply)
            delivered += 1
    return delivered
