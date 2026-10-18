-- FOBs, server side. See sh_fob.lua for the rules.

local F = MCC.FOB
local Inv = MCC.Inv

F.Props = F.Props or {}     -- core -> {prop = true}
F.Members = F.Members or {} -- core -> {steamid64 = name}

local TICK = 10

local function Notify(ply, msg, ...)
    if IsValid(ply) then Inv.Notify(ply, select("#", ...) > 0 and string.format(msg, ...) or msg) end
end

-- Data files -------------------------------------------------------------------------------------

local function Cost(t)
    local out = {}
    for res, n in pairs(istable(t) and t or {}) do
        if isstring(res) and tonumber(n) and tonumber(n) > 0 then out[res] = tonumber(n) end
    end
    return out
end
F.SanitizeCost = Cost

local function SanitizeTiers(raw)
    local out = {}
    for i, t in ipairs(istable(raw) and raw or {}) do
        if istable(t) then
            local d = F.DEFAULT_TIERS[math.min(i, #F.DEFAULT_TIERS)]
            out[i] = {
                name = isstring(t.name) and t.name or ("Tier " .. i),
                health = math.max(1, tonumber(t.health) or d.health),
                radius = math.Clamp(tonumber(t.radius) or d.radius, 128, 16384),
                stash = {w = math.Clamp(math.floor(tonumber(istable(t.stash) and t.stash.w) or d.stash.w), 1, 20),
                         h = math.Clamp(math.floor(tonumber(istable(t.stash) and t.stash.h) or d.stash.h), 1, 20)},
                maxProps = math.max(0, math.floor(tonumber(t.maxProps) or d.maxProps)),
                upkeep = Cost(t.upkeep or d.upkeep),
                upgradeCost = i > 1 and Cost(t.upgradeCost or d.upgradeCost) or nil,
            }
        end
    end
    return #out > 0 and out or table.Copy(F.DEFAULT_TIERS)
end

-- A fob_tiers.json from before upkeep was paid in resources (0.6/0.7) is set aside for the new one.
-- (0.8's files, with "capacity" instead of "stash", just get the default stash sizes.)
local function OldTierFormat(raw)
    if not istable(raw) then return false end
    for _, t in ipairs(raw) do
        if istable(t) and (isnumber(t.upkeep) or isnumber(t.upgradeCost)) then return true end
    end
    return false
end

function F.LoadConfig()
    local raw = MCC.Data.ReadJSON("fob_tiers.json")
    if OldTierFormat(raw) then
        MCC.Data.WriteJSON("fob_tiers_old.json", raw)
        MCC.Data.WriteJSON("fob_tiers.json", F.DEFAULT_TIERS)
        MCC.Log("fob_tiers.json was in the old supply format; saved it as fob_tiers_old.json and wrote the new defaults")
    end
    MCC.Data.EnsureJSON("fob_tiers.json", F.DEFAULT_TIERS)
    MCC.Data.EnsureJSON("fob_storage.json", F.DEFAULT_STORAGE)
    F.Tiers = SanitizeTiers(MCC.Data.ReadJSON("fob_tiers.json"))
    local st = MCC.Data.ReadJSON("fob_storage.json")
    F.Storage = {accepts = {}, food = Cost(istable(st) and st.food or F.DEFAULT_STORAGE.food)}
    for _, res in ipairs(istable(st) and istable(st.accepts) and st.accepts or F.DEFAULT_STORAGE.accepts) do
        if isstring(res) then F.Storage.accepts[#F.Storage.accepts + 1] = res end
    end
    if SetGlobalFloat then SetGlobalFloat("MCCFobTier1Radius", F.Tiers[1].radius) end
    for _, core in ipairs(F.All()) do
        core.EZconsumes = F.Storage.accepts
        F.ApplyTier(core, core:GetTier(), true)
    end
end
hook.Add("MCC_Ready", "MCC_FOB", F.LoadConfig)
hook.Add("MCC_ReloadConfig", "MCC_FOB", F.LoadConfig)

function F.Accepts(res)
    for _, r in ipairs(F.Storage.accepts) do
        if r == res then return true end
    end
    return false
end

-- Members ----------------------------------------------------------------------------------------

local function SyncMembers(core)
    local list = {}
    for sid in pairs(F.Members[core] or {}) do list[#list + 1] = sid end
    core:SetNWString("MCCMembers", "," .. table.concat(list, ",") .. ",")
end

local function SetOwner(core, ply)
    core:SetOwnerID(IsValid(ply) and ply:SteamID64() or "")
    core:SetOwnerName(IsValid(ply) and ply:Nick() or "")
    core:SetAbandoned(not IsValid(ply))
    if IsValid(ply) and F.Members[core] then F.Members[core][ply:SteamID64()] = nil end
    SyncMembers(core)
end

-- FOBs a player owns (admin FOBs don't count toward the limit).
function F.Owned(ply, includeAdmin)
    local out = {}
    for _, core in ipairs(F.All()) do
        if core:GetOwnerID() == ply:SteamID64() and (includeAdmin or not core:GetNWBool("MCCAdmin")) then
            out[#out + 1] = core
        end
    end
    return out
end

-- The stash --------------------------------------------------------------------------------------
-- The core is an inventory container (opened with E, shown in the inventory window). Anything can go
-- in it; the JMod resource boxes in it are what the FOB pays upkeep and upgrades with.

local function StashSize(core, tier)
    if core:GetNWBool("MCCAdmin") then return MCC.Config.Get("fob_admin_stash_w"), MCC.Config.Get("fob_admin_stash_h") end
    local st = (tier or F.Tier(core)).stash or {w = 8, h = 10}
    return st.w, st.h
end

-- The stash grid {w, h, items}.
function F.Grid(core)
    if not core.MCCCont then
        core.MCCCont = {name = "FOB Stash", noSearch = true, fob = true, grids = {{w = 1, h = 1, items = {}}}}
    end
    return core.MCCCont.grids[1]
end

-- Grows the grid to its tier's size (it never shrinks under what's in it).
local function ResizeStash(core, tier)
    local g = F.Grid(core)
    local w, h = StashSize(core, tier)
    g.w, g.h = math.max(g.w, w), math.max(g.h, h)
end

local function ResOf(it)
    local def = Inv.Def(it)
    return def and def.data and def.data.jmod or nil
end

local function RemoveItem(list, it)
    for i = #list, 1, -1 do
        if list[i] == it then table.remove(list, i) return end
    end
end

-- Resource units in the stash: {resource = units}.
function F.Store(core)
    local out = {}
    for _, it in ipairs(F.Grid(core).items) do
        local res = ResOf(it)
        if res then out[res] = (out[res] or 0) + Inv.ResourceAmount(it) end
    end
    return out
end

function F.StoredTotal(core)
    local n = 0
    for _, v in pairs(F.Store(core)) do n = n + v end
    return n
end

-- Cells taken in the stash.
function F.StashUsed(core)
    local n = 0
    for _, it in ipairs(F.Grid(core).items) do
        local w, h = Inv.Size(it)
        n = n + w * h
    end
    return n
end

local function SyncStore(core)
    local store, food, total = F.Store(core), 0, 0
    for _, v in pairs(store) do total = total + v end
    for res, rate in pairs(F.Storage.food) do food = food + (store[res] or 0) * rate end
    core:SetStored(total)
    core:SetFood(food)
    -- per resource, for clients (the builder's green/red ghost): "steel=40;wood=300"
    local parts = {}
    for res, n in pairs(store) do parts[#parts + 1] = res .. "=" .. math.floor(n) end
    table.sort(parts)
    core:SetNWString("MCCStore", table.concat(parts, ";"))
    local g = F.Grid(core)
    core:SetNWInt("MCCStashUsed", F.StashUsed(core))
    core:SetNWInt("MCCStashCells", g.w * g.h)
end
F.SyncStore = SyncStore

-- After the FOB changes its stash itself (upkeep, deposits): anyone looking at it sees the change.
function F.Changed(core)
    SyncStore(core)
    for _, p in ipairs(player.GetAll()) do
        if p.MCCInvOpen == core then Inv.Update(p) end
    end
end

-- Puts units of a JMod resource in the stash: tops up part-full boxes, then adds boxes where they fit.
-- Returns how many units went in.
function F.AddResource(core, res, amount)
    local id = Inv.JModResourceID and Inv.JModResourceID(res)
    amount = math.floor(tonumber(amount) or 0)
    if not id or not MCC.Items.Get(id) or amount <= 0 then return 0 end
    local g, full, added = F.Grid(core), Inv.JModFull(), 0
    for _, it in ipairs(g.items) do
        if amount <= 0 then break end
        if it.id == id then
            local have = Inv.ResourceAmount(it)
            local add = math.min(amount, full - have)
            if add > 0 then
                it.d = it.d or {}
                it.d.amount = have + add
                amount, added = amount - add, added + add
            end
        end
    end
    while amount > 0 do
        local n = math.min(amount, full)
        local it = Inv.NewItem(id, 1, {amount = n})
        local x, y, r = Inv.FindSpot(g.items, g.w, g.h, it)
        if not x then break end
        it.x, it.y, it.r = x, y, r
        g.items[#g.items + 1] = it
        amount, added = amount - n, added + n
    end
    return added
end

-- Takes units of a resource out of the stash, emptiest boxes first. Returns how many it took.
function F.RemoveResource(core, res, amount)
    amount = math.ceil(tonumber(amount) or 0)
    local g, boxes, took = F.Grid(core), {}, 0
    for _, it in ipairs(g.items) do
        if ResOf(it) == res then boxes[#boxes + 1] = it end
    end
    table.sort(boxes, function(a, b) return Inv.ResourceAmount(a) < Inv.ResourceAmount(b) end)
    for _, it in ipairs(boxes) do
        if amount <= 0 then break end
        local have = Inv.ResourceAmount(it)
        local t = math.min(have, amount)
        if t >= have then
            RemoveItem(g.items, it)
        else
            it.d = it.d or {}
            it.d.amount = have - t
        end
        amount, took = amount - t, took + t
    end
    return took
end

-- Loads up to `amount` units of a JMod resource (pushed into the core, Deposit); returns how many it took.
function F.Load(core, typ, amount)
    if not F.Accepts(typ) or (amount or 0) <= 0 then return 0 end
    local units = F.AddResource(core, typ, amount)
    if units > 0 then
        F.PayUnpaid(core) -- something was decaying: pay its upkeep now
        F.Changed(core)
    end
    return units
end

-- Takes a cost from the stash (all or nothing); false + "Needs ..." when short.
function F.Take(core, cost)
    local store, missing = F.Store(core), {}
    for res, n in pairs(cost or {}) do
        if (store[res] or 0) < n then missing[#missing + 1] = math.ceil(n - (store[res] or 0)) .. " more " .. res end
    end
    if #missing > 0 then
        table.sort(missing)
        return false, "The FOB's stash needs " .. table.concat(missing, ", ")
    end
    for res, n in pairs(cost or {}) do F.RemoveResource(core, res, n) end
    F.Changed(core)
    return true
end

-- Moves every JMod resource the player carries into the stash. Returns units loaded, or false + reason.
function F.Deposit(core, ply)
    local items = {}
    local function scan(it)
        local def = Inv.Def(it)
        if def and def.data.jmod then items[#items + 1] = it end
        for _, list in ipairs(it.cont or {}) do
            for _, o in ipairs(list) do scan(o) end
        end
    end
    for _, it in pairs(Inv.Get(ply).slots) do scan(it) end
    if #items == 0 then return false, "You aren't carrying any JMod resources" end

    local loaded, full = 0, false
    for _, it in ipairs(items) do
        local def = Inv.Def(it)
        local have = Inv.ResourceAmount(it)
        local took = F.Load(core, def.data.jmod, have)
        loaded = loaded + took
        if took >= have then
            local found, loc, list, idx = Inv.Find(ply, it.u)
            if found then Inv.Detach(ply, found, loc, list, idx) end
        elseif took > 0 then
            it.d = it.d or {}
            it.d.amount = have - took
            full = true
        elseif F.Accepts(def.data.jmod) then
            full = true
        end
    end
    Inv.Update(ply)
    if loaded == 0 then
        return false, full and "The FOB's stash is full" or "The FOB doesn't take those resources"
    end
    core:EmitSound("items/ammo_pickup.wav")
    return loaded
end

-- For traders and friendly NPCs (later): uses up food points from the food resources.
function F.ConsumeFood(core, points)
    if core:GetFood() < points then return false end
    local store = F.Store(core)
    local types = {}
    for res, rate in pairs(F.Storage.food) do types[#types + 1] = {res, rate} end
    table.sort(types, function(a, b) return a[2] > b[2] end)
    for _, t in ipairs(types) do
        if points <= 0 then break end
        local units = math.min(store[t[1]] or 0, math.ceil(points / t[2]))
        points = points - F.RemoveResource(core, t[1], units) * t[2]
    end
    F.Changed(core)
    return true
end

-- Spills everything in the stash on the ground (JMod resources as real JMod boxes).
function F.DropStores(core)
    local g = core.MCCCont and core.MCCCont.grids and core.MCCCont.grids[1]
    if not g then return end
    if MCC.Config.Get("fob_drop_stores") then
        for i, it in ipairs(g.items) do
            it.x, it.y, it.r = nil, nil, nil
            local off = Vector(math.random(-60, 60), math.random(-60, 60), 30 + (i % 10) * 6)
            Inv.SpawnWorldItem(it, core:GetPos() + off)
        end
    end
    g.items = {}
end

-- Opens the stash in the player's inventory window.
function F.OpenStash(ply, core)
    if not F.CanModify(core, ply) then return false, "Only the FOB's members can open its stash" end
    F.Grid(core)
    SyncStore(core)
    return Inv.OpenContainer(ply, core)
end

-- E on the core: members (and anyone, once it's abandoned) get the stash, others the FOB menu.
function F.Use(ply, core)
    if F.CanModify(core, ply) then
        F.OpenStash(ply, core)
    else
        F.OpenMenu(ply, core)
    end
end

-- Only members put things in the stash.
hook.Add("MCC_CanStore", "MCC_FOB", function(ply, it, ent)
    if IsValid(ent) and ent:GetClass() == F.CLASS and not F.CanModify(ent, ply) then
        return false, "Only the FOB's members can use its stash"
    end
end)

-- A player moved something in or out of the stash: update the totals and pay what was unpaid.
hook.Add("MCC_ContainerChanged", "MCC_FOB", function(ent)
    if not IsValid(ent) or ent:GetClass() ~= F.CLASS then return end
    SyncStore(ent)
    F.PayUnpaid(ent)
end)

-- Tiers ---------------------------------------------------------------------------------------------

-- Sets a core's tier; health scales up with it (keep = config reload: same tier, keep the fraction).
function F.ApplyTier(core, tier, keep)
    tier = math.Clamp(tier, 1, #F.Tiers)
    local t = F.Tiers[tier]
    local frac = core:GetMaxHP() > 0 and core:GetHP() / core:GetMaxHP() or 1
    local gained = t.health - core:GetMaxHP()
    core:SetTier(tier)
    core:SetNWString("MCCTierName", t.name)
    core:SetNWInt("MCCMaxProps", t.maxProps)
    ResizeStash(core, t)
    SyncStore(core)
    core:SetMaxHP(t.health)
    if keep then
        core:SetHP(t.health * frac)
    else
        core:SetHP(math.min(t.health, core:GetHP() + math.max(0, gained)))
    end
    core:SetRadius(t.radius)
end

function F.Upgrade(core, ply)
    if not F.IsMember(core, ply) then return false, "Only the FOB's members can upgrade it" end
    local nextTier = F.Tiers[core:GetTier() + 1]
    if not nextTier then return false, "Already at the highest tier" end
    local ok, err = F.Take(core, nextTier.upgradeCost)
    if not ok then return false, err end
    F.ApplyTier(core, core:GetTier() + 1)
    core:EmitSound("buttons/button9.wav")
    hook.Run("MCC_FOBUpgraded", core, ply)
    return true
end

-- Deploying -------------------------------------------------------------------------------------------

-- Places a FOB core for a player. opts.admin = an Admin FOB (stocked, doesn't count toward the limit).
function F.SpawnCore(ply, pos, yaw, opts)
    opts = opts or {}
    local core = ents.Create(F.CLASS)
    if not IsValid(core) then return nil end
    core:SetPos(pos)
    core:SetAngles(Angle(0, yaw or 0, 0))
    core:Spawn()
    core:Activate()
    F.Props[core], F.Members[core] = {}, {}
    core:SetNWBool("MCCAdmin", opts.admin == true)
    SetOwner(core, ply)
    F.ApplyTier(core, 1)
    core:SetHP(core:GetMaxHP())
    core.MCCUnpaid = {}
    core.MCCNextBill = CurTime() + MCC.Config.Get("fob_upkeep_interval")
    core:SetNWFloat("MCCNextBill", core.MCCNextBill)
    if opts.admin then
        -- biggest boxes first so they pack
        local n, list = MCC.Config.Get("fob_admin_stock"), {}
        for _, res in ipairs({"wood", "concrete", "steel", "titanium", "sand", "plastic", "basic parts", "organics"}) do
            local def = Inv.JModResourceID and MCC.Items.Get(Inv.JModResourceID(res))
            if def and F.Accepts(res) then list[#list + 1] = {res, def.w * def.h} end
        end
        table.sort(list, function(a, b) return a[2] > b[2] end)
        for _, r in ipairs(list) do F.AddResource(core, r[1], n) end
    end
    SyncStore(core)
    core:EmitSound("items/ammocrate_open.wav")
    hook.Run("MCC_FOBDeployed", core, ply)
    return core
end

local function TooClose(pos, radius, skip)
    for _, other in ipairs(F.All()) do
        if other ~= skip and pos:Distance(other:GetPos()) < radius + other:GetRadius() then return true end
    end
    return false
end

function F.Deploy(ply)
    if not F.Enabled() then return false, "FOBs are turned off on this server" end
    if #F.Owned(ply) >= MCC.Config.Get("fob_max_per_player") then return false, "You already have a FOB" end
    local start = ply:GetShootPos()
    local tr = util.TraceLine({start = start, endpos = start + ply:GetAimVector() * MCC.Config.Get("fob_deploy_range"),
        filter = ply, mask = MASK_SOLID})
    if not tr.Hit or (tr.HitNormal and tr.HitNormal.z < 0.7) then return false, "Look at flat ground to deploy it" end
    if TooClose(tr.HitPos, F.Tiers[1].radius) then return false, "Too close to another FOB" end
    local core = F.SpawnCore(ply, tr.HitPos, ply:EyeAngles().y + 180)
    return core ~= nil
end

-- Admin FOB: anywhere, stocked, outside the per-player limit (spawn menu or mcc_fob_spawn).
function F.SpawnAdmin(ply, pos)
    return F.SpawnCore(ply, pos, IsValid(ply) and ply:EyeAngles().y + 180 or 0, {admin = true})
end

-- FOB props -------------------------------------------------------------------------------------------

local MATERIALS = {
    {"metal", 2}, {"concrete", 3}, {"rock", 3}, {"brick", 3}, {"wood", 1}, {"glass", 0.4},
    {"plastic", 0.6}, {"rubber", 0.6}, {"flesh", 0.5}, {"dirt", 0.5},
}

-- Health of an ordinary prop: from its size (cube root of its volume) and what it's made of.
function F.PropHealth(prop)
    local mins, maxs = prop:OBBMins(), prop:OBBMaxs()
    local size = math.max(1, (maxs.x - mins.x) * (maxs.y - mins.y) * (maxs.z - mins.z)) ^ (1 / 3)
    local mult = 1
    local phys = prop:GetPhysicsObject()
    local mat = IsValid(phys) and string.lower(phys:GetMaterial() or "") or ""
    for _, m in ipairs(MATERIALS) do
        if string.find(mat, m[1], 1, true) then
            mult = m[2]
            break
        end
    end
    local hp = size * MCC.Config.Get("fob_prop_hp_scale") * mult
    return math.Round(math.Clamp(hp, MCC.Config.Get("fob_prop_hp_min"), MCC.Config.Get("fob_prop_hp_max")))
end

-- Adds a prop to a FOB. hp, upkeep ({resource = units per period}) and decayHours come from the
-- Builder Tablet; ordinary props get size-based health and the mcc_fob_prop_tier tier's upkeep.
function F.AddProp(core, prop, hp, upkeep, decayHours)
    F.Props[core] = F.Props[core] or {}
    if F.Props[core][prop] then return true end
    if table.Count(F.Props[core]) >= F.Tier(core).maxProps then return false end
    hp = tonumber(hp) or F.PropHealth(prop)
    F.Props[core][prop] = true
    prop.MCCFob = core
    prop.MCCUpkeep, prop.MCCDecayHours = upkeep, decayHours
    F.SetPropMax(prop, hp)
    core:SetPropCount(table.Count(F.Props[core]))
    return true
end

-- Sets a prop's max health and fills it (upgrades).
function F.SetPropMax(prop, hp)
    prop.MCCFobHP = hp
    prop:SetNWEntity("MCCFob", prop.MCCFob)
    prop:SetNWInt("MCCFobMaxHP", hp)
    prop:SetNWInt("MCCFobHP", hp)
end

function F.PropHP(prop)
    return prop.MCCFobHP or prop:GetNWInt("MCCFobHP", 0)
end

-- Upkeep and decay time for a prop.
function F.PropUpkeep(prop)
    if prop.MCCUpkeep then return prop.MCCUpkeep, prop.MCCDecayHours or 3 end
    local tier = MCC.Build and MCC.Build.TierByID and MCC.Build.TierByID(MCC.Config.Get("fob_prop_tier"))
    if tier then return tier.upkeep, tier.decayHours end
    return {}, 3
end

function F.RemoveProp(prop)
    local core = prop.MCCFob
    prop.MCCFob, prop.MCCFobHP = nil, nil
    if IsValid(core) and F.Props[core] then
        F.Props[core][prop] = nil
        core:SetPropCount(table.Count(F.Props[core]))
    end
    if IsValid(prop) then
        prop:SetNWEntity("MCCFob", NULL)
        prop:SetNWInt("MCCFobHP", 0)
        prop:SetNWInt("MCCFobMaxHP", 0)
    end
end

local function BreakProp(prop)
    F.RemoveProp(prop)
    prop:EmitSound("physics/wood/wood_crate_break" .. math.random(1, 5) .. ".wav")
    if prop.GibBreakClient then prop:GibBreakClient(Vector(0, 0, 0)) end
    prop:Remove()
end

function F.SetPropHP(prop, hp)
    hp = math.min(prop:GetNWInt("MCCFobMaxHP", 0), hp)
    if hp <= 0 then
        BreakProp(prop)
        return
    end
    prop.MCCFobHP = hp
    prop:SetNWInt("MCCFobHP", math.ceil(hp))
end
local SetPropHP = F.SetPropHP

hook.Add("PlayerSpawnedProp", "MCC_FOB", function(ply, model, prop)
    local core = F.At(prop:GetPos())
    if not core then return end
    if not F.CanModify(core, ply) then
        prop:Remove()
        return Notify(ply, "You can't build in someone else's FOB")
    end
    if not F.AddProp(core, prop) then
        prop:Remove()
        Notify(ply, "This FOB holds at most %d props. Upgrade it for more.", F.Tier(core).maxProps)
    end
end)

-- A prop that's part of a player FOB (never an NPC or player, whatever fields other addons set on them).
function F.IsFOBProp(ent)
    return ent.MCCFob ~= nil and ent.MCCFobHP ~= nil and not (ent.IsNPC and ent:IsNPC()) and not (ent.IsPlayer and ent:IsPlayer())
end

hook.Add("EntityRemoved", "MCC_FOB", function(ent)
    if F.IsFOBProp(ent) then F.RemoveProp(ent) end
end)

-- Damage --------------------------------------------------------------------------------------------

local function Scaled(dmg)
    local amount = dmg:GetDamage()
    if dmg:IsBulletDamage() then amount = amount * MCC.Config.Get("fob_bullet_mult") end
    return amount
end

function F.Destroy(core, attacker)
    if core.MCCDestroyed then return end
    core.MCCDestroyed = true
    hook.Run("MCC_FOBDestroyed", core, attacker)
    local fx = EffectData()
    fx:SetOrigin(core:GetPos())
    util.Effect("Explosion", fx)
    Notify(player.GetBySteamID64(core:GetOwnerID()), "Your FOB was destroyed!")
    F.DropStores(core)
    core:Remove()
end

hook.Add("EntityTakeDamage", "MCC_FOB", function(ent, dmg)
    if ent:GetClass() == F.CLASS then
        ent:SetHP(math.max(0, ent:GetHP() - Scaled(dmg)))
        if ent:GetHP() <= 0 then F.Destroy(ent, dmg:GetAttacker()) end
        return true
    end
    if F.IsFOBProp(ent) then
        -- stone and better don't burn
        if ent.MCCFireImmune and dmg.IsDamageType and dmg:IsDamageType(DMG_BURN) then return true end
        local amount = Scaled(dmg)
        if amount > 0 then ent.MCCLastHurt = CurTime() end -- no repairs for a while (Rust)
        SetPropHP(ent, F.PropHP(ent) - amount)
        return true
    end
end)

-- A removed core leaves its props behind as ordinary props.
function F.CoreRemoved(core)
    for prop in pairs(F.Props[core] or {}) do
        if IsValid(prop) then F.RemoveProp(prop) end
    end
    F.Props[core], F.Members[core] = nil, nil
end

-- Upkeep ----------------------------------------------------------------------------------------------

-- What the FOB owes each period: its tier's upkeep plus every prop's.
function F.UpkeepNeeds(core)
    local needs = {}
    for res, n in pairs(F.Tier(core).upkeep or {}) do needs[res] = (needs[res] or 0) + n end
    for prop in pairs(F.Props[core] or {}) do
        if IsValid(prop) then
            for res, n in pairs((F.PropUpkeep(prop))) do needs[res] = (needs[res] or 0) + n end
        end
    end
    return needs
end

local function SyncUnpaid(core)
    local unpaid = core.MCCUnpaid or {}
    core:SetNWBool("MCCDecaying", next(unpaid) ~= nil)
    local list = table.GetKeys(unpaid)
    table.sort(list)
    core:SetNWString("MCCUnpaid", table.concat(list, ", "))
end

-- Pays upkeep for a period out of the stash. Resources it can't cover in full aren't taken, and
-- everything that needs them decays until they're paid.
function F.Bill(core)
    local store, unpaid = F.Store(core), {}
    for res, n in pairs(F.UpkeepNeeds(core)) do
        if (store[res] or 0) >= n then
            F.RemoveResource(core, res, n)
        else
            unpaid[res] = true
        end
    end
    core.MCCUnpaid = unpaid
    core.MCCNextBill = CurTime() + MCC.Config.Get("fob_upkeep_interval")
    core:SetNWFloat("MCCNextBill", core.MCCNextBill)
    SyncUnpaid(core)
    F.Changed(core)
    hook.Run("MCC_FOBUpkeep", core, unpaid)
    return next(unpaid) == nil
end

-- Pays whatever is unpaid now that the stash has it (the rest of this period was already paid).
function F.PayUnpaid(core)
    local unpaid = core.MCCUnpaid
    if not unpaid or not next(unpaid) then return false end
    local needs, store, paid = F.UpkeepNeeds(core), F.Store(core), false
    for _, res in ipairs(table.GetKeys(unpaid)) do
        local n = needs[res] or 0
        if (store[res] or 0) >= n then
            if n > 0 then F.RemoveResource(core, res, n) end
            unpaid[res] = nil
            paid = true
        end
    end
    if paid then
        SyncUnpaid(core)
        F.Changed(core)
    end
    return paid
end

function F.IsPaid(core, upkeep)
    for res in pairs(upkeep or {}) do
        if core.MCCUnpaid and core.MCCUnpaid[res] then return false end
    end
    return true
end

function F.Tick(core)
    if CurTime() >= (core.MCCNextBill or 0) then F.Bill(core) end

    -- the core repairs itself while its upkeep is paid, and decays while it isn't
    local t = F.Tier(core)
    if F.IsPaid(core, t.upkeep) then
        local heal = core:GetMaxHP() * MCC.Config.Get("fob_repair_rate") / 100 * TICK / 60
        core:SetHP(math.min(core:GetMaxHP(), core:GetHP() + heal))
    else
        core:SetHP(core:GetHP() - core:GetMaxHP() / (MCC.Config.Get("fob_core_decay_hours") * 3600) * TICK)
        if core:GetHP() <= 0 then
            F.Destroy(core)
            return
        end
    end

    -- each prop decays over its own tier's time if its resource wasn't paid
    for prop in pairs(table.Copy(F.Props[core] or {})) do
        if IsValid(prop) then
            local upkeep, hours = F.PropUpkeep(prop)
            if not F.IsPaid(core, upkeep) then
                SetPropHP(prop, F.PropHP(prop) - prop:GetNWInt("MCCFobMaxHP", 0) / (math.max(hours, 0.001) * 3600) * TICK)
            end
        end
    end
end

timer.Create("MCC_FOBUpkeep", TICK, 0, function()
    for _, core in ipairs(F.All()) do
        if IsValid(core) and not core.MCCDestroyed then F.Tick(core) end
    end
end)

-- Leaving and claiming ---------------------------------------------------------------------------

-- The owner left: an online member takes over, or the FOB is abandoned.
hook.Add("PlayerDisconnected", "MCC_FOB", function(ply)
    local sid = ply:SteamID64()
    for _, core in ipairs(F.All()) do
        if core:GetOwnerID() == sid then
            local heir
            for msid in pairs(F.Members[core] or {}) do
                local p = player.GetBySteamID64(msid)
                if IsValid(p) and p ~= ply then heir = p break end
            end
            SetOwner(core, heir)
            if heir then
                Notify(heir, "%s left. You now own their FOB.", ply:Nick())
            else
                hook.Run("MCC_FOBAbandoned", core, ply)
            end
        end
    end
end)

function F.StartClaim(core, ply)
    if not core:GetAbandoned() then return false, "This FOB isn't abandoned" end
    if #F.Owned(ply) >= MCC.Config.Get("fob_max_per_player") then return false, "You already have a FOB" end
    if core.MCCClaim and IsValid(core.MCCClaim.ply) and core.MCCClaim.ply ~= ply then
        return false, "Someone else is claiming it"
    end
    core.MCCClaim = {ply = ply, ends = CurTime() + MCC.Config.Get("fob_claim_time")}
    core:SetClaimEnds(core.MCCClaim.ends)
    return true
end

local function FinishClaim(core, ply)
    core.MCCClaim = nil
    core:SetClaimEnds(0)
    F.Members[core] = {}
    SetOwner(core, ply)
    core:EmitSound("buttons/button9.wav")
    Notify(ply, "You claimed this FOB.")
    hook.Run("MCC_FOBClaimed", core, ply)
end

-- Claiming means staying close and alive until the timer runs out.
timer.Create("MCC_FOBClaims", 0.25, 0, function()
    for _, core in ipairs(F.All()) do
        local c = core.MCCClaim
        if c then
            local p = c.ply
            if not IsValid(p) or not p:Alive() or p:GetPos():Distance(core:GetPos()) > 160 or not core:GetAbandoned() then
                core.MCCClaim = nil
                core:SetClaimEnds(0)
            elseif CurTime() >= c.ends then
                FinishClaim(core, p)
            end
        end
    end
end)

-- Packing up: the owner gets the kit back and the stash spills out; props stay as ordinary props.
function F.PackUp(core, ply)
    if core:GetOwnerID() ~= ply:SteamID64() then return false, "Only the owner can pack up the FOB" end
    if not core:GetNWBool("MCCAdmin") then
        local it = Inv.NewItem("mcc_fob_kit", 1)
        if not Inv.GiveItem(ply, it) then Inv.SpawnWorldItem(it, ply:GetPos() + Vector(0, 0, 20)) end
        Inv.Update(ply)
    end
    F.DropStores(core)
    core:Remove()
    return true
end

-- The kit ------------------------------------------------------------------------------------------

hook.Add("MCC_UseItem", "MCC_FOB", function(ply, it, def)
    if def.data.effect ~= "fob_deploy" then return end
    return F.Deploy(ply)
end)

MCC.JModRecipes.Add("FOB Kit", {results = "FUNC MCCFobKit",
    cost = {["steel"] = 100, ["wood"] = 100, ["basic parts"] = 50, ["precision parts"] = 10},
    description = "Deploy it to set up a Forward Operating Base. Build in its zone; keep it stocked for upkeep."})
MCC.JModRecipes.AddBuildFunc("MCCFobKit", function(ply, pos)
    return Inv.SpawnWorldItem(Inv.NewItem("mcc_fob_kit", 1), pos, nil, true)
end)

-- Menu ----------------------------------------------------------------------------------------------

function F.MenuData(core, ply)
    local members = {}
    for sid, name in pairs(F.Members[core] or {}) do
        local p = player.GetBySteamID64(sid)
        members[#members + 1] = {sid = sid, name = IsValid(p) and p:Nick() or name, online = IsValid(p)}
    end
    table.sort(members, function(a, b) return a.name < b.name end)
    return {
        e = core:EntIndex(), tier = core:GetTier(), tierInfo = F.Tier(core), next = F.Tiers[core:GetTier() + 1],
        store = F.Store(core), needs = F.UpkeepNeeds(core), unpaid = core.MCCUnpaid or {},
        nextBill = math.max(0, (core.MCCNextBill or 0) - CurTime()), interval = MCC.Config.Get("fob_upkeep_interval"),
        accepts = F.Storage.accepts, food = F.Storage.food, members = members, admin = core:GetNWBool("MCCAdmin"),
        mine = F.IsMember(core, ply), owner = core:GetOwnerID() == ply:SteamID64(), stash = F.CanModify(core, ply),
    }
end

function F.OpenMenu(ply, core)
    MCC.Net.Send("fob_menu", F.MenuData(core, ply), ply)
end

local ACTIONS = {
    deposit = function(core, ply)
        if not F.IsMember(core, ply) and not core:GetAbandoned() then return false, "Only members can stock this FOB" end
        local n, err = F.Deposit(core, ply)
        if not n then return false, err end
        Notify(ply, "Stored %d resources in the FOB.", n)
        return true
    end,
    upgrade = F.Upgrade,
    claim = F.StartClaim,
    menu = function() return true end,
    stash = function(core, ply) return F.OpenStash(ply, core) end,
    packup = F.PackUp,
    add = function(core, ply, a)
        if core:GetOwnerID() ~= ply:SteamID64() then return false, "Only the owner can add members" end
        local p = player.GetBySteamID64(tostring(a.sid or ""))
        if not IsValid(p) or p == ply then return false end
        F.Members[core][p:SteamID64()] = p:Nick()
        SyncMembers(core)
        Notify(p, "%s added you to their FOB.", ply:Nick())
        return true
    end,
    kick = function(core, ply, a)
        local sid = tostring(a.sid or "")
        if core:GetOwnerID() ~= ply:SteamID64() and sid ~= ply:SteamID64() then return false end
        F.Members[core][sid] = nil
        SyncMembers(core)
        return true
    end,
}

MCC.Net.Receive("fob_act", function(a, ply)
    if not istable(a) or not ACTIONS[a.a] then return end
    local core = Entity(tonumber(a.e) or -1)
    if not IsValid(core) or core:GetClass() ~= F.CLASS or ply:GetPos():Distance(core:GetPos()) > 250 then return end
    local ok, err = ACTIONS[a.a](core, ply, a)
    if ok == false and err then Notify(ply, err) end
    if IsValid(core) and a.a ~= "packup" and a.a ~= "stash" then F.OpenMenu(ply, core) end
end, {allowClient = true, maxBytes = 256})

-- Admin -------------------------------------------------------------------------------------------

local function AimedCore(ply)
    local e = IsValid(ply) and ply:GetEyeTrace().Entity
    if IsValid(e) and e:GetClass() == F.CLASS then return e end
end

MCC.Command("fob_list", "MCC Moderator", "", "Lists every FOB.", function(ply)
    local all = F.All()
    MCC.Util.Reply(ply, "%d FOB(s):", #all)
    for _, core in ipairs(all) do
        MCC.Util.Reply(ply, "  #%d %s%s tier %d, %d/%d hp, %d resources, stash %d/%d cells, %d props%s", core:EntIndex(),
            core:GetAbandoned() and "(abandoned)" or core:GetOwnerName(), core:GetNWBool("MCCAdmin") and " [admin]" or "",
            core:GetTier(), core:GetHP(), core:GetMaxHP(), core:GetStored(), core:GetNWInt("MCCStashUsed"),
            core:GetNWInt("MCCStashCells"), core:GetPropCount(),
            core:GetNWBool("MCCDecaying") and (", DECAYING: " .. core:GetNWString("MCCUnpaid")) or "")
    end
end)

MCC.Command("fob_spawn", "MCC Admin", "", "Spawns an Admin FOB where you're looking (stocked, no per-player limit).",
function(ply)
    if not IsValid(ply) then return end
    local tr = ply:GetEyeTrace()
    if not tr.Hit then return MCC.Util.Reply(ply, "Look at the ground.") end
    F.SpawnAdmin(ply, tr.HitPos)
    MCC.Util.Reply(ply, "Admin FOB spawned.")
end)

MCC.Command("fob_stock", "MCC Admin", "<resource|all> <amount>",
"Adds JMod resources to the stash of the FOB core you're looking at (\"all\" = every resource it takes; negative removes).",
function(ply, args)
    local core = AimedCore(ply)
    if not core then return MCC.Util.Reply(ply, "Look at a FOB core.") end
    local res, n = args[1], tonumber(args[#args] or "")
    if not res or not n then return MCC.Util.Reply(ply, "Usage: mcc_fob_stock <resource|all> <amount>") end
    local name = table.concat(args, " ", 1, #args - 1)
    local function Stock(r)
        if not MCC.Items.Get(Inv.JModResourceID(r)) then return true end -- that JMod resource isn't installed
        if n >= 0 then return F.AddResource(core, r, n) >= n end
        F.RemoveResource(core, r, -n)
        return true
    end
    local fit = true
    if name == "all" then
        for _, r in ipairs(F.Storage.accepts) do fit = Stock(r) and fit end
    elseif F.Accepts(name) then
        fit = Stock(name)
    else
        return MCC.Util.Reply(ply, "The FOB doesn't take '%s'.", name)
    end
    F.PayUnpaid(core)
    F.Changed(core)
    MCC.Util.Reply(ply, "Done. The stash holds %d resource units%s.", F.StoredTotal(core), fit and "" or " (it's full, not everything fit)")
end)

MCC.Command("fob_upkeep", "MCC Admin", "", "Runs the upkeep payment now for the FOB core you're looking at.", function(ply)
    local core = AimedCore(ply)
    if not core then return MCC.Util.Reply(ply, "Look at a FOB core.") end
    local paid = F.Bill(core)
    MCC.Util.Reply(ply, paid and "Upkeep paid." or ("Couldn't pay: " .. core:GetNWString("MCCUnpaid") .. " (decaying)"))
end)

MCC.Command("fob_remove", "MCC Admin", "", "Removes the FOB core you're looking at.", function(ply)
    local core = AimedCore(ply)
    if not core then return MCC.Util.Reply(ply, "Look at a FOB core.") end
    core:Remove()
    MCC.Util.Reply(ply, "FOB removed.")
end)
