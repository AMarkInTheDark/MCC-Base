"""The simulated world the inventory tests (and expansions' tests) run in: entities that take custom fields,
JMod boxes, players with weapons and ammo, open-sky traces. Run WORLD before load_mcc()."""

WORLD = r'''
-- Vectors with the operators the inventory uses
local VM = {}
VM.__index = VM
VM.__add = function(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
VM.__mul = function(a, b) if type(a) == "number" then a, b = b, a end return Vector(a.x * b, a.y * b, a.z * b) end
VM.__sub = function(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
VM.__div = function(a, b) return Vector(a.x / b, a.y / b, a.z / b) end
function VM:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VM:Dot(o) return self.x * o.x + self.y * o.y + self.z * o.z end
function VM:DistToSqr(o) return (self.x - o.x)^2 + (self.y - o.y)^2 + (self.z - o.z)^2 end
_MODELBOUNDS = {}
function VM:Distance(o) return math.sqrt((self.x - o.x)^2 + (self.y - o.y)^2 + (self.z - o.z)^2) end
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VM) end
function Angle(p, y, r) return {p = p or 0, y = y or 0, r = r or 0} end
function SafeRemoveEntityDelayed() end
OBS_MODE_CHASE, COLLISION_GROUP_WEAPON = 5, 11

-- Entities: userdata that accept custom fields, like GMod's
_ENTS = {}
function _Ent(class, methods)
  local u = newproxy(true) local m = getmetatable(u) m.valid = true
  local fields = {}
  local base = {
    GetClass = function() return class end,
    Remove = function() m.valid = false end,
    SetPos = function(s, p) fields._pos = p end, GetPos = function() return fields._pos or Vector() end,
    SetAngles = function(s, a) fields._ang = a end, GetAngles = function() return fields._ang or Angle() end,
    GetForward = function() local y = math.rad((fields._ang or Angle()).y) return Vector(math.cos(y), math.sin(y), 0) end,
    GetRight = function() local y = math.rad((fields._ang or Angle()).y) return Vector(math.sin(y), -math.cos(y), 0) end,
    GetUp = function() return Vector(0, 0, 1) end, SetMaterial = function(s, m) fields._mat = m end,
    SetNWVector = function(s, k, v) fields["nw_" .. k] = v end, GetNWVector = function(s, k) return fields["nw_" .. k] or Vector() end,
    Spawn = function() end, Activate = function() end,
    SetModel = function(s, mdl) fields._model = mdl end, SetSkin = function() end,
    SetCollisionGroup = function() end, SetBodygroup = function() end,
    GetPhysicsObject = function() return nil end, GetPhysicsObjectCount = function() return 0 end,
    SetNWBool = function(s, k, v) fields["nw_" .. k] = v end, GetNWBool = function(s, k) return fields["nw_" .. k] or false end,
    SetNWString = function(s, k, v) fields["nw_" .. k] = v end, GetNWString = function(s, k, d) return fields["nw_" .. k] or d end,
    NearestPoint = function() return fields._pos or Vector() end,
    EntIndex = function() return fields._idx end,
    IsWeapon = function() return false end, IsNPC = function() return false end,
    GetModel = function() return fields._model end,
    EmitSound = function() end, StopSound = function() end,
    SetNWFloat = function(s, k, v) fields["nw_" .. k] = v end, GetNWFloat = function(s, k, d) return fields["nw_" .. k] or d end,
    SetNWEntity = function(s, k, v) fields["nw_" .. k] = v end, GetNWEntity = function(s, k) return fields["nw_" .. k] or NULL end,
    SetNWInt = function(s, k, v) fields["nw_" .. k] = v end, GetNWInt = function(s, k, d) return fields["nw_" .. k] or d or 0 end,
    OBBMins = function() local b = _MODELBOUNDS[fields._model or ""] return b and b[1] or Vector(-20, -20, -20) end,
    OBBMaxs = function() local b = _MODELBOUNDS[fields._model or ""] return b and b[2] or Vector(20, 20, 20) end,
    LocalToWorld = function(s, v) return (fields._pos or Vector()) + v end,
    SetModelScale = function(s, n) fields._scale = n end, GetModelScale = function() return fields._scale or 1 end,
    SetCrate = function(s, c) fields._crate = c end, GetCrate = function() return fields._crate end,
    SetChute = function(s, b) fields._chute = b end, GetChute = function() return fields._chute == true end,
  }
  for k, v in pairs(methods or {}) do base[k] = v end
  m.__index = function(_, k) local v = base[k] if v ~= nil then return v end return fields[k] end
  m.__newindex = function(_, k, v) fields[k] = v end
  _ENTS[#_ENTS + 1] = u
  fields._idx = #_ENTS
  return u
end

-- JMod, enough of it: resource types, their box entities and the alt-use key
JMod = {EZ_RESOURCE_ENTITIES = {wood = "ent_jack_gmod_ezwood", ["iron ore"] = "ent_jack_gmod_ezironore",
    water = "ent_jack_gmod_ezwater", sand = "ent_jack_gmod_ezsand", propellant = "ent_jack_gmod_ezpropellant",
    steel = "ent_jack_gmod_ezsteel", concrete = "ent_jack_gmod_ezconcrete", ["fissile material"] = "ent_jack_gmod_ezfissilematerial",
    oil = "ent_jack_gmod_ezoil", titanium = "ent_jack_gmod_eztitanium", ["basic parts"] = "ent_jack_gmod_ezbasicparts"},
  Config = {ResourceEconomy = {MaxResourceMult = 1}},
  IsAltUsing = function(ply) return ply._alt == true end, SetEZowner = function() end}
local SENTS = {ent_jack_gmod_ezwood = {PrintName = "EZ Wood", Model = "models/jmod/resources/ez_wood.mdl", EZsupplies = "wood"},
  ent_jack_gmod_ezironore = {PrintName = "EZ Iron Ore", Model = "models/jmod/resources/rock05a.mdl", EZsupplies = "iron ore"},
  ent_jack_gmod_ezwater = {PrintName = "EZ Water", EZsupplies = "water"}, ent_jack_gmod_ezsand = {PrintName = "EZ Sand", EZsupplies = "sand"},
  ent_jack_gmod_ezpropellant = {PrintName = "EZ Propellant Bottle", EZsupplies = "propellant"},
  ent_jack_gmod_ezsteel = {PrintName = "EZ Steel", EZsupplies = "steel"},
  ent_jack_gmod_ezconcrete = {PrintName = "EZ Concrete", EZsupplies = "concrete"},
  ent_jack_gmod_ezfissilematerial = {PrintName = "EZ Fissile Material", EZsupplies = "fissile material"},
  ent_jack_gmod_ezoil = {PrintName = "EZ Oil", EZsupplies = "oil"}}
scripted_ents = {Get = function(c) return SENTS[c] end}
function _JModBox(class)
  local res = 0
  local e
  e = _Ent(class, {
    GetResource = function() return res end,
    SetResource = function(s, n) res = n end,
    Spawn = function() res = 100 end, -- JMod's Initialize fills new boxes
    SetEZsupplies = function(s, typ, amt) if typ ~= e.EZsupplies then return end res = amt if amt < 1 then e:Remove() end end,
  })
  e.IsJackyEZresource = true
  e.EZsupplies = SENTS[class].EZsupplies
  return e
end

ents = {Create = function(class)
  if SENTS[class] then return _JModBox(class) end
  if class == "mcc_fob" then
    local nv = {Tier = 0, PropCount = 0, HP = 0, MaxHP = 0, Stored = 0, Food = 0, Radius = 0, ClaimEnds = 0,
      Abandoned = false, OwnerID = "", OwnerName = ""}
    local m = {}
    for k in pairs(nv) do
      m["Get" .. k] = function() return nv[k] end
      m["Set" .. k] = function(s, v) nv[k] = v end
    end
    local e
    m.Spawn = function() e.EZconsumes = MCC.FOB.Storage.accepts end
    m.TryLoadResource = function(s, typ, n) return MCC.FOB.Load(e, typ, n) end
    m.Remove = function() getmetatable(e).valid = false MCC.FOB.CoreRemoved(e) end
    e = _Ent(class, m)
    return e
  end
  if class == "mcc_extract_crate" then
    local e
    e = _Ent(class, {Spawn = function()
      e:SetNWString("MCCName", "Extraction Crate")
      if not e.MCCCont then
        e.MCCCont = {name = "Extraction Crate", noSearch = true, extract = true,
          grids = {{w = MCC.Config.Get("extract_crate_w"), h = MCC.Config.Get("extract_crate_h"), items = {}}}}
      end
    end})
    return e
  end
  if class == "mcc_item" then
    local e
    e = _Ent("mcc_item", {
      SetItemID = function(s, id) e._id = id end, GetItemID = function() return e._id end,
      SetCount = function(s, n) e._n = n end, GetCount = function() return e._n end,
      SetItem = function(s, it) e.MCCItem = it e._id = it.id e._n = it.n or 1 end,
    })
    return e
  end
  return _Ent(class)
end, FindInSphere = function() return {} end, FindByClass = function(c) return _FindByClass(c) end}

-- A weapon the "engine" hands out
local function MakeWeaponEnt(class, maxClip)
  local clip = 0
  local nv = {}
  local w
  w = _Ent(class, {GetMaxClip1 = function() return maxClip end, Clip1 = function() return clip end,
    SetClip1 = function(s, n) clip = n end, GetCreationTime = function() return 0 end,
    IsWeapon = function() return true end, GetOwner = function() return w._owner end,
    GetNetworkVars = function() local t = {} for k, v in pairs(nv) do t[k] = v end return t end,
    RestoreNetworkVars = function(s, t) for k, v in pairs(t) do nv[k] = v end w._restored = (w._restored or 0) + 1 end,
    _NV = function() return nv end})
  return w
end
_MakeWeaponEnt = MakeWeaponEnt
local CLIPS = {weapon_smg1 = 45, weapon_ar2 = 30, weapon_pistol = 18, weapon_frag = -1, weapon_crowbar = -1,
  weapon_physgun = -1, gmod_tool = -1, weapon_physcannon = -1, gmod_camera = -1}

function _MakeTester(sid)
  local weps, ammo = {}, {}
  local hp, ap = 50, 0
  local p
  p = _Ent("player", {
    Alive = function() return true end, Nick = function() return "Tester" .. sid end,
    SteamID64 = function() return tostring(sid) end, UserID = function() return sid end,
    IsPlayer = function() return true end,
    Give = function(s, class, noAmmo)
      if hook.Run("PlayerCanPickupWeapon", p, MakeWeaponEnt(class, 0)) == false and not p.MCCInvGiving and not p.MCCPickupBypass then
        -- blocked: mimic the engine refusing
      end
      weps[class] = weps[class] or (_WEAPON_FACTORY and _WEAPON_FACTORY(class, p)) or MakeWeaponEnt(class, CLIPS[class] or 10)
      return weps[class]
    end,
    HasWeapon = function(s, c) return weps[c] ~= nil end,
    GetWeapon = function(s, c) return weps[c] end,
    StripWeapon = function(s, c) weps[c] = nil end,
    SetAmmo = function(s, n, name) ammo[name] = n end,
    GetAmmoCount = function(s, name) return ammo[name] or 0 end,
    Health = function() return hp end, SetHealth = function(s, v) hp = v end, GetMaxHealth = function() return 100 end,
    Armor = function() return ap end, SetArmor = function(s, v) ap = v end, GetMaxArmor = function() return 100 end,
    EmitSound = function() end,
    GetShootPos = function() return Vector(0, 0, 64) end, GetAimVector = function() return Vector(1, 0, 0) end,
    GetVelocity = function() return Vector() end, GetModel = function() return "models/player/kleiner.mdl" end,
    GetSkin = function() return 0 end, GetBodyGroups = function() return {} end, GetAngles = function() return {} end,
    SpectateEntity = function() end, Spectate = function() end,
    AddDeaths = function() p._deaths = (p._deaths or 0) + 1 end, AddFrags = function() p._frags = (p._frags or 0) + 1 end,
    PickupWeapon = function() return true end,
  })
  p._weps, p._ammo = weps, ammo
  return p
end
player = {GetAll = function() return _PLAYERS or {} end,
  GetBySteamID64 = function(sid) for _, p in ipairs(_PLAYERS or {}) do if p:SteamID64() == sid then return p end end return false end}
-- traces: everything is open sky unless _ROOF is set
util.TraceLine = function(t) if _ROOF then return {Hit = true, HitSky = false, HitPos = t.start + Vector(0, 0, 60)} end
  return {Hit = true, HitSky = true, HitPos = t.endpos} end
util.Effect = function() end
function EffectData() return setmetatable({}, {__index = function() return function() end end}) end
'''
