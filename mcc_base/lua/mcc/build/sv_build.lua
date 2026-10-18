-- Building, server side: the tier and piece files, placing, upgrading, repairing and removing pieces.

local B = MCC.Build
local F = MCC.FOB
local Inv = MCC.Inv

B.Slots = B.Slots or {} -- building id -> {slot key -> entity}
B.NextID = B.NextID or 0

local function Notify(ply, msg) if IsValid(ply) and msg then Inv.Notify(ply, msg) end end

local function Cost(t)
    local out = {}
    for res, n in pairs(istable(t) and t or {}) do
        if isstring(res) and tonumber(n) and tonumber(n) > 0 then out[res] = tonumber(n) end
    end
    return out
end

-- Data files ----------------------------------------------------------------------------------------

local function SanitizeTiers(raw)
    local out = {}
    for i, t in ipairs(istable(raw) and raw or {}) do
        if istable(t) and isstring(t.id) then
            out[#out + 1] = {id = t.id, name = isstring(t.name) and t.name or t.id,
                health = math.max(1, tonumber(t.health) or 100), decayHours = math.max(0.001, tonumber(t.decayHours) or 3),
                cost = Cost(t.cost), upkeep = Cost(t.upkeep), material = isstring(t.material) and t.material or nil,
                fireImmune = t.fireImmune == true}
        end
    end
    return #out > 0 and out or table.Copy(B.DEFAULT_TIERS)
end

function B.LoadPieces()
    MCC.Data.EnsureJSON("build_tiers.json", B.DEFAULT_TIERS)
    B.Tiers = SanitizeTiers(MCC.Data.ReadJSON("build_tiers.json"))

    -- build_pieces.json: {"version": 2, "pieces": [...]}. A 0.7 file (a plain list, costs in supply) is
    -- set aside as build_pieces_old.json.
    local raw = MCC.Data.ReadJSON("build_pieces.json")
    if istable(raw) and raw.version == nil and raw[1] ~= nil then
        MCC.Data.WriteJSON("build_pieces_old.json", raw)
        raw = nil
        MCC.Log("build_pieces.json was in the 0.7 format; saved it as build_pieces_old.json and wrote the new defaults")
    end
    if not istable(raw) or not istable(raw.pieces) then
        raw = {version = 2, pieces = table.Copy(B.DEFAULT_PIECES)}
        MCC.Data.WriteJSON("build_pieces.json", raw)
    end
    -- pieces added to MCC's defaults since the file was written are added to it
    local have, added = {}, false
    for _, p in ipairs(raw.pieces) do if istable(p) and p.id then have[p.id] = true end end
    for _, p in ipairs(B.DEFAULT_PIECES) do
        if not have[p.id] then
            raw.pieces[#raw.pieces + 1] = table.Copy(p)
            added = true
        end
    end
    if added then MCC.Data.WriteJSON("build_pieces.json", raw) end
    for _, p in ipairs(raw.pieces) do
        if istable(p) and p.kind == "free" then
            p.cost, p.upkeep = Cost(p.cost), Cost(p.upkeep)
            p.health = math.max(1, tonumber(p.health) or 500)
            p.decayHours = math.max(0.001, tonumber(p.decayHours) or 4)
        end
    end
    B.SetPieces(raw.pieces)
    B.SyncPieces()
end

function B.SyncPieces(ply)
    local list = {}
    for _, id in ipairs(B.Order) do list[#list + 1] = B.Pieces[id] end
    MCC.Net.Send("build_pieces", {pieces = list, tiers = B.Tiers}, ply)
end

hook.Add("MCC_Ready", "MCC_Build", B.LoadPieces)
hook.Add("MCC_ReloadConfig", "MCC_Build", B.LoadPieces)

local hello = {}
MCC.Net.Receive("build_hello", function(_, ply)
    if hello[ply] then return end
    hello[ply] = true
    B.SyncPieces(ply)
end, {allowClient = true, maxBytes = 64})
hook.Add("PlayerDisconnected", "MCC_Build", function(ply) hello[ply] = nil end)

-- Placing -------------------------------------------------------------------------------------------

function B.Has(id, key)
    local e = B.Slots[id] and B.Slots[id][key]
    return IsValid(e)
end

local function SetFrame(ent, Fr)
    ent:SetNWInt("MCCBld", Fr.id)
    ent:SetNWVector("MCCBldO", Fr.O)
    ent:SetNWFloat("MCCBldYaw", Fr.yaw)
    ent:SetNWFloat("MCCBldG", Fr.G)
    ent:SetNWFloat("MCCBldT", Fr.T)
end

local function Effect(ent)
    local fx = EffectData()
    fx:SetOrigin(ent:GetPos() + ent:GetUp() * ent:OBBMaxs().z / 2)
    fx:SetMagnitude(3)
    fx:SetScale(5)
    fx:SetRadius(2)
    util.Effect("cball_explode", fx, true, true)
end

-- Gives a structure piece a tier: its look, health (full), upkeep, decay time and fire resistance.
function B.ApplyTier(ent, tier)
    if tier.material then ent:SetMaterial(tier.material) end
    ent:SetNWString("MCCTier", tier.id)
    ent:SetNWString("MCCTierName", tier.name)
    ent.MCCFireImmune = tier.fireImmune == true
    if ent.MCCFob then
        ent.MCCUpkeep, ent.MCCDecayHours = tier.upkeep, tier.decayHours
        F.SetPropMax(ent, tier.health)
    end
end

-- Pays a cost: from the FOB's stash first (when building in your FOB), the rest from what you carry.
local function Pay(ply, cost, core)
    if MCC.Config.Get("build_free") then return true end
    local ok, err = B.CanAfford(ply, cost, core)
    if not ok then return false, err end
    core = B.PayingFOB(ply, core)
    local rest = {}
    for res, n in pairs(cost or {}) do
        local took = core and F.RemoveResource(core, res, n) or 0
        if n - took > 0 then rest[res] = n - took end
    end
    if core then F.Changed(core) end
    if next(rest) then return Inv.TakeResources(ply, rest) end
    return true
end
B.Pay = Pay

-- Builds piece `id` where the player is aiming. Returns the entity, or false + reason.
function B.Place(ply, id, rot)
    local piece = B.Pieces[id or ""]
    if not piece then return false, "Pick a piece first (right-click)" end
    local tr = ply:GetEyeTrace()
    local res = B.Solve(ply, piece, tr, rot, B.Has)
    if not res.ok then return false, res.reason end
    local allowed, why, core = B.Allowed(ply, piece, res.pos)
    if not allowed then return false, why end
    if core and table.Count(F.Props[core] or {}) >= F.Tier(core).maxProps then return false, "The FOB's prop limit is reached" end
    local paid, err = Pay(ply, B.PlaceCost(piece), core)
    if not paid then return false, err end

    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return false end
    ent:SetModel(piece.model)
    if piece.material then ent:SetMaterial(piece.material) end
    ent:SetPos(res.pos)
    ent:SetAngles(res.ang)
    ent:Spawn()
    ent:Activate()
    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
        phys:SetMass(50000)
    end
    ent:SetNWString("MCCPiece", piece.id)
    ent.MCCBuiltBy = ply

    if res.key then
        local frame = res.frame
        if res.root then
            B.NextID = B.NextID + 1
            frame = {id = B.NextID, O = res.root.O, yaw = res.root.yaw, G = res.root.G, T = res.root.T}
        end
        B.Slots[frame.id] = B.Slots[frame.id] or {}
        B.Slots[frame.id][res.key] = ent
        SetFrame(ent, frame)
        ent:SetNWString("MCCSlot", res.key)
    end

    local tier = B.IsStructure(piece) and B.Tiers[1] or nil
    if core then
        if tier then
            F.AddProp(core, ent, tier.health, tier.upkeep, tier.decayHours)
        else
            F.AddProp(core, ent, piece.health, piece.upkeep, piece.decayHours)
        end
    end
    if tier then B.ApplyTier(ent, tier) end

    ent:EmitSound("physics/wood/wood_box_impact_hard" .. math.random(1, 3) .. ".wav")
    Effect(ent)
    if undo then
        undo.Create("MCC Build")
            undo.AddEntity(ent)
            undo.SetPlayer(ply)
        undo.Finish()
    end
    hook.Run("MCC_PiecePlaced", ply, ent, piece)
    return ent
end

-- Upgrading, repairing, removing --------------------------------------------------------------------

-- The built piece a player may work on: theirs (or their FOB's) and within reach.
local function Workable(ply, ent)
    if not IsValid(ent) or ent:GetNWString("MCCPiece", "") == "" then return nil, "Look at a built piece" end
    if ent:GetPos():Distance(ply:GetShootPos()) > MCC.Config.Get("build_range") + 100 then return nil, "Too far" end
    local core = ent.MCCFob
    if IsValid(core) then
        if not F.CanModify(core, ply) then return nil, "This isn't your FOB" end
    elseif ent.MCCBuiltBy ~= ply and not ply:IsSuperAdmin() then
        return nil, "You didn't build that"
    end
    return B.Pieces[ent:GetNWString("MCCPiece")]
end

local function CurrentTier(ent)
    return B.TierByID(ent:GetNWString("MCCTier", ""))
end

-- The cost that values a piece as it stands: its tier's, or a fortification's own.
local function ValueCost(ent, piece)
    local tier = CurrentTier(ent)
    if tier then return tier.cost end
    return piece and piece.cost or {}
end

local function Scale(cost, f)
    local out = {}
    for res, n in pairs(cost or {}) do
        local v = math.ceil(n * f)
        if v > 0 then out[res] = v end
    end
    return out
end

function B.Upgrade(ply, ent, tierIndex)
    local piece, err = Workable(ply, ent)
    if not piece then return false, err end
    if not B.IsStructure(piece) then return false, "Only foundations, walls and floors have tiers" end
    local _, cur = CurrentTier(ent)
    local tier = B.Tiers[tonumber(tierIndex) or 0]
    if not tier or (cur and tonumber(tierIndex) <= cur) then return false, "Pick a higher tier" end
    local paid, why = Pay(ply, tier.cost, ent.MCCFob)
    if not paid then return false, why end
    B.ApplyTier(ent, tier)
    ent:EmitSound("physics/metal/metal_solid_impact_hard" .. math.random(1, 5) .. ".wav")
    Effect(ent)
    hook.Run("MCC_PieceUpgraded", ply, ent, tier)
    return true
end

-- What a full repair would cost right now (empty when it's undamaged).
function B.RepairCost(ent, piece)
    local max = ent:GetNWInt("MCCFobMaxHP", 0)
    if max <= 0 then return {} end
    local missing = 1 - F.PropHP(ent) / max
    if missing <= 0 then return {} end
    return Scale(ValueCost(ent, piece), missing * MCC.Config.Get("build_repair_cost"))
end

-- Rust: a piece can't be repaired for a while after it's damaged. Returns seconds left (0 = can repair).
function B.RepairWait(ent)
    local since = CurTime() - (ent.MCCLastHurt or -math.huge)
    return math.max(0, MCC.Config.Get("build_repair_delay") - since)
end

local function CanRepair(ply, ent)
    local piece, err = Workable(ply, ent)
    if not piece then return nil, err end
    if not ent.MCCFob or F.PropHP(ent) >= ent:GetNWInt("MCCFobMaxHP", 0) then return nil, "It isn't damaged" end
    local wait = B.RepairWait(ent)
    if wait > 0 then return nil, string.format("Recently damaged: you can repair it in %ds", math.ceil(wait)) end
    return piece
end

function B.Repair(ply, ent)
    local piece, err = CanRepair(ply, ent)
    if not piece then return false, err end
    local paid, why = Pay(ply, B.RepairCost(ent, piece), ent.MCCFob)
    if not paid then return false, why end
    F.SetPropHP(ent, ent:GetNWInt("MCCFobMaxHP", 0))
    ent:EmitSound("buttons/lever7.wav")
    return true
end

-- One hit of the hammer: repairs build_hammer_repair of its max health, paying for that share.
-- Returns true + health repaired, or false + reason.
function B.HammerHit(ply, ent)
    local piece, err = CanRepair(ply, ent)
    if not piece then return false, err end
    local max, hp = ent:GetNWInt("MCCFobMaxHP", 0), F.PropHP(ent)
    local heal = math.min(max - hp, max * MCC.Config.Get("build_hammer_repair"))
    local paid, why = Pay(ply, Scale(ValueCost(ent, piece), heal / max * MCC.Config.Get("build_repair_cost")), ent.MCCFob)
    if not paid then return false, why end
    F.SetPropHP(ent, hp + heal)
    return true, heal
end

-- Removes a piece; part of its current tier's cost goes back into your inventory.
function B.Remove(ply, ent)
    ent = ent or ply:GetEyeTrace().Entity
    local piece, err = Workable(ply, ent)
    if not piece then return false, err end
    if not MCC.Config.Get("build_free") then
        -- the refund goes to the FOB's stash (what doesn't fit, to you)
        local refund, core = Scale(ValueCost(ent, piece), MCC.Config.Get("build_refund")), B.PayingFOB(ply, ent.MCCFob)
        if core then
            for res, n in pairs(table.Copy(refund)) do
                local put = F.AddResource(core, res, n)
                refund[res] = n - put > 0 and n - put or nil
            end
            F.Changed(core)
        end
        Inv.GiveResources(ply, refund)
    end
    Effect(ent)
    ent:EmitSound("physics/wood/wood_box_break" .. math.random(1, 2) .. ".wav")
    ent:Remove()
    return true
end

hook.Add("EntityRemoved", "MCC_Build", function(ent)
    local id = ent.GetNWInt and ent:GetNWInt("MCCBld", 0) or 0
    if id == 0 then return end
    local slots = B.Slots[id]
    local key = ent:GetNWString("MCCSlot", "")
    if slots and slots[key] == ent then slots[key] = nil end
end)

-- The tablet's right-click: the piece picker.
function B.MenuFor(ply)
    MCC.Net.Send("build_menu", {}, ply)
end

-- The hammer's right-click on a built piece: upgrade, repair, remove. False + reason if it can't.
function B.PieceMenu(ply, ent)
    ent = ent or ply:GetEyeTrace().Entity
    local piece, err = Workable(ply, ent)
    if not piece then return false, err end
    local _, cur = CurrentTier(ent)
    local ups = {}
    if B.IsStructure(piece) then
        for i, t in ipairs(B.Tiers) do
            if i > (cur or 0) then ups[#ups + 1] = {i = i, name = t.name, health = t.health, cost = t.cost, decayHours = t.decayHours} end
        end
    end
    MCC.Net.Send("build_piece_menu", {
        e = ent:EntIndex(), name = piece.name, tier = ent:GetNWString("MCCTierName", ""),
        hp = math.ceil(F.PropHP(ent)), max = ent:GetNWInt("MCCFobMaxHP", 0), upgrades = ups,
        repair = B.RepairCost(ent, piece), refund = Scale(ValueCost(ent, piece), MCC.Config.Get("build_refund")),
        free = MCC.Config.Get("build_free"), wait = math.ceil(B.RepairWait(ent)),
    }, ply)
    return true
end

local function Target(ply, a)
    local ent = Entity(tonumber(a.e) or -1)
    return IsValid(ent) and ent or nil
end

MCC.Net.Receive("build_piece_act", function(a, ply)
    local ent = Target(ply, a)
    if not ent then return end
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "mcc_hammer" then return Notify(ply, "Hold the Builder Hammer") end
    local ok, err
    if a.a == "upgrade" then
        ok, err = B.Upgrade(ply, ent, a.tier)
    elseif a.a == "repair" then
        ok, err = B.Repair(ply, ent)
    elseif a.a == "remove" then
        ok, err = B.Remove(ply, ent)
    end
    if not ok and err then Notify(ply, err) end
end, {allowClient = true, maxBytes = 128})

-- The tablet picks a piece from its menu.
MCC.Net.Receive("build_select", function(a, ply)
    local wep = ply:GetActiveWeapon()
    if not IsValid(wep) or wep:GetClass() ~= "mcc_build_tablet" or not B.Pieces[tostring(a.id or "")] then return end
    wep:SetPiece(a.id)
    wep:SetRot(0)
end, {allowClient = true, maxBytes = 128})

-- Crafting the tablet and the hammer at the JMod workbench.
MCC.JModRecipes.Add("Builder Tablet", {results = "FUNC MCCBuildTablet",
    cost = {["precision parts"] = 20, ["basic parts"] = 20, ["plastic"] = 10},
    description = "Build and upgrade foundations, walls, floors and fortifications inside your FOB."})
MCC.JModRecipes.AddBuildFunc("MCCBuildTablet", function(ply, pos)
    return Inv.SpawnWorldItem(Inv.NewItem("mcc_build_tablet", 1), pos, nil, true)
end)

MCC.JModRecipes.Add("Builder Hammer", {results = "FUNC MCCBuildHammer",
    cost = {["wood"] = 20, ["steel"] = 20},
    description = "Upgrade, repair and remove the pieces you build with the Builder Tablet, Rust style."})
MCC.JModRecipes.AddBuildFunc("MCCBuildHammer", function(ply, pos)
    return Inv.SpawnWorldItem(Inv.NewItem("mcc_hammer", 1), pos, nil, true)
end)
