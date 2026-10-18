-- Extraction, server side: crate limits, the Fulton lift, stored crates, signal flares and airdrops,
-- and the JMod workbench recipes. See sh_extract.lua for the rules.

local X = MCC.Extract
local Inv = MCC.Inv

local INFLATE = 0.8 -- seconds for the balloon to fill
local YANK = 1.4    -- seconds from the yank until the crate is gone
local YANK_HEIGHT = 3200
local ROPE = 140    -- balloon height above the crate once inflated

-- Sounds and looks: MGSV's when its addon is installed (sh_extract.lua), HL2's otherwise.
local SND = {
    attach = {mgsv = "mgsv/items/fulton_place.wav", hl2 = "ambient/machines/steam_release_2.wav"},
    yank = {mgsv = "mgsv/items/fulton_fly.wav", hl2 = "ambient/machines/catapult_throw.wav"},
    pop = {mgsv = "mgsv/items/fulton_pop.wav", hl2 = "garrysmod/balloon_pop_cute.wav"},
}
local function Snd(key) return SND[key][X.MGSV() and "mgsv" or "hl2"] end

-- Client-side sound cue (cl_extract.lua): the plane that catches the Fulton flying over.
local function Cue(kind, target, extra)
    if not X.MGSV() then return end
    local data = extra or {}
    data.k = kind
    MCC.Net.Send("extract_fx", data, target)
end

-- With the MGSV addon on the server, players download it from the Workshop; its own Fulton SWEP (which
-- extracts anything) is kept to admins so it doesn't sidestep extraction crates.
hook.Add("MCC_Ready", "MCC_ExtractMGSV", function()
    if X.MGSV() and resource and resource.AddWorkshop then resource.AddWorkshop(X.MGSV_WORKSHOP) end
end)
local MGSV_SWEPS = {weapon_fulton = true, terror_fulton = true}
local function MGSVSwepAllowed(ply, class)
    if MGSV_SWEPS[class] and MCC.Config.Get("extract_mgsv_swep_admin") and not ply:IsAdmin() then return false end
end
hook.Add("PlayerGiveSWEP", "MCC_ExtractMGSV", MGSVSwepAllowed)
hook.Add("PlayerSpawnSWEP", "MCC_ExtractMGSV", MGSVSwepAllowed)

X.Pending = X.Pending or {} -- steamid64 -> flares thrown whose crate hasn't landed yet
X.Flares = X.Flares or {}   -- live flares waiting for their drop

-- Stored crates ------------------------------------------------------------------------------
-- data/mcc/extraction/<steamid64>.json: {crates = {{grids = {...}, t = os.time(), by = name}, ...}}, oldest first.

local function FileFor(sid) return "extraction/" .. sid .. ".json" end

function X.Stored(sid)
    local t = MCC.Data.ReadJSON(FileFor(sid))
    return istable(t) and istable(t.crates) and t.crates or {}
end

local function Save(sid, crates)
    file.CreateDir("mcc/extraction")
    MCC.Data.WriteJSON(FileFor(sid), {crates = crates})
end

-- Stores a crate's grids for a player. Returns how many they have stored and how many old ones were overwritten.
function X.Store(sid, name, grids)
    local crates = X.Stored(sid)
    crates[#crates + 1] = {grids = MCC.Util.JSONSafe(grids), t = os.time(), by = name}
    local overwritten = 0
    while #crates > MCC.Config.Get("extract_max_crates") do
        table.remove(crates, 1)
        overwritten = overwritten + 1
    end
    Save(sid, crates)
    return #crates, overwritten
end

-- Crates a player can still call in (stored minus flares already in the air).
function X.Available(sid)
    return #X.Stored(sid) - (X.Pending[sid] or 0)
end

local function TakeOldest(sid)
    local crates = X.Stored(sid)
    local c = table.remove(crates, 1)
    if c then Save(sid, crates) end
    return c
end

local function Notify(ply, msg, ...)
    if IsValid(ply) then Inv.Notify(ply, string.format(msg, ...)) end
end

local function NotifyAll(msg)
    for _, p in ipairs(player.GetAll()) do Inv.Notify(p, msg) end
end

-- Crate limits ---------------------------------------------------------------------------------

hook.Add("MCC_CanStore", "MCC_Extract", function(ply, it, ent)
    if not X.IsCrate(ent) then return end
    return X.CanStore(ent, it)
end)

-- Clears the "supply drop" marker the first time anyone opens a dropped crate.
hook.Add("MCC_ContainerOpened", "MCC_Extract", function(ply, ent)
    if X.IsCrate(ent) and ent:GetNWFloat("MCCDropMark", 0) > 0 then ent:SetNWFloat("MCCDropMark", 0) end
end)

-- The Fulton ------------------------------------------------------------------------------------

-- Open sky above the whole crate (props and roofs block it).
function X.OpenSky(ent)
    local mins, maxs = ent:OBBMins(), ent:OBBMaxs()
    local points = {Vector(0, 0, 0), Vector(mins.x, mins.y, 0), Vector(maxs.x, maxs.y, 0),
        Vector(mins.x, maxs.y, 0), Vector(maxs.x, mins.y, 0)}
    for _, p in ipairs(points) do
        local start = ent:LocalToWorld(Vector(p.x * 0.8, p.y * 0.8, maxs.z + 2))
        local tr = util.TraceLine({start = start, endpos = start + Vector(0, 0, 4096), filter = ent, mask = MASK_SOLID})
        if tr.Hit and not tr.HitSky then return false end
    end
    return true
end

local function CloseViewers(ent)
    for _, p in ipairs(player.GetAll()) do
        if p.MCCInvOpen == ent then
            p.MCCInvOpen = nil
            p.MCCSearch = nil
            Inv.Update(p)
        end
    end
end

function X.StartFulton(crate, ply)
    if crate.MCCFulton then return false, "A Fulton is already attached" end
    if crate:GetChute() then return false, "Wait for it to land" end
    if not X.OpenSky(crate) then return false, "The crate needs open sky above it" end

    CloseViewers(crate)
    local phys = crate:GetPhysicsObject()
    if IsValid(phys) then phys:EnableMotion(false) end
    crate:SetNWBool("MCCLifting", true)

    local mgsv = X.MGSV()
    local balloon = ents.Create("mcc_fulton_balloon")
    if IsValid(balloon) then
        balloon:SetPos(crate:GetPos() + Vector(0, 0, crate:OBBMaxs().z + 20))
        balloon:SetCrate(crate)
        balloon.MCCMGSV = mgsv
        balloon:Spawn()
    end
    crate.MCCFulton = {sid = ply:SteamID64(), name = ply:Nick(), ply = ply, start = CurTime(),
        base = crate:GetPos(), ang = crate:GetAngles(), balloon = balloon, hover = MCC.Config.Get("extract_fulton_hover"),
        full = mgsv and 1 or 3, seed = math.random() * 10}
    crate:EmitSound(Snd("attach"), 75, mgsv and 100 or 110)
    return true
end

-- The Fulton SWEP's left click: the crate you're looking at (or have open).
function X.UseFulton(ply)
    if not X.Enabled() then return false, "Extraction is turned off on this server" end
    local crate = X.TargetCrate(ply)
    if not crate then return false, "Aim at an extraction crate" end
    return X.StartFulton(crate, ply)
end

-- Runs every tick on a crate with a Fulton: the balloon inflates and rises on its line, the crate lifts
-- off and swings under it, then it's yanked into the sky.
function X.FultonThink(crate)
    local F = crate.MCCFulton
    local t = CurTime() - F.start
    local top = crate:OBBMaxs().z
    local full = F.full or 3
    local lift, height, scale, sway, drift = 0, 30, full * 0.1, 0, 0

    if t < INFLATE then
        local f = t / INFLATE
        local e = 1 - (1 - f) ^ 3 -- ease out: pops open fast, settles
        height, scale = 30 + (ROPE - 30) * e, full * (0.1 + 0.9 * e)
    elseif t < INFLATE + F.hover then
        if not F.sized and IsValid(F.balloon) then
            -- scaling a model doesn't scale its physics: give the full balloon a hit area its size
            F.sized = true
            if F.balloon.SetBalloonHull then F.balloon:SetBalloonHull(36) end
        end
        local f = math.min(1, (t - INFLATE) / 0.35)
        local w = t * 2.6 + (F.seed or 0)
        lift, height, scale = 40 * f, ROPE + math.sin(t * 6) * 3, full
        sway, drift = math.sin(w) * 5 * f, math.sin(w * 0.7) * 6 * f -- swinging on the line
    elseif t < INFLATE + F.hover + YANK then
        if not F.yanked then
            F.yanked = true
            crate:EmitSound(Snd("yank"), 90)
        end
        local u = (t - INFLATE - F.hover) / YANK
        lift, height, scale = 40 + YANK_HEIGHT * u ^ 2.2, ROPE, full
        sway = math.sin(t * 9) * 8 * (1 - u) -- jerked up, swinging less as it goes
    else
        return X.CompleteFulton(crate)
    end

    crate:SetPos(F.base + Vector(drift, 0, lift))
    if F.ang then crate:SetAngles(Angle(F.ang.p + sway, F.ang.y, F.ang.r + sway * 0.6)) end
    if IsValid(F.balloon) then
        F.balloon:SetPos(crate:GetPos() + Vector(-drift * 0.4, 0, top + height))
        F.balloon:SetModelScale(scale, 0)
    end
end

function X.CompleteFulton(crate)
    local F = crate.MCCFulton
    crate.MCCFulton = nil
    local count, overwritten = X.Store(F.sid, F.name, crate.MCCCont and crate.MCCCont.grids or {})
    if IsValid(F.ply) then
        if overwritten > 0 then
            Notify(F.ply, "Crate extracted. You had the max, so your oldest stored crate was overwritten (%d/%d).",
                count, MCC.Config.Get("extract_max_crates"))
        else
            Notify(F.ply, "Crate extracted (%d/%d stored). Throw a signal flare next session to call it in.",
                count, MCC.Config.Get("extract_max_crates"))
        end
    end
    hook.Run("MCC_CrateExtracted", F.sid, crate)
    Cue("flyover", nil) -- everyone hears the plane
    if IsValid(F.balloon) then F.balloon:Remove() end
    crate:Remove()
end

-- Shooting the balloon before the yank drops the crate (the Fulton is used up).
function X.PopFulton(crate, attacker)
    local F = crate.MCCFulton
    if not F or F.yanked then return end
    crate.MCCFulton = nil
    if IsValid(F.balloon) then
        local fx = EffectData()
        fx:SetOrigin(F.balloon:GetPos())
        if X.MGSV() then
            fx:SetStart(Vector(1, 1, 1))
            util.Effect("fulton_pop", fx) -- MGSV's effect plays its own pop
        else
            fx:SetStart(Vector(70, 74, 60))
            util.Effect("balloon_pop", fx)
            F.balloon:EmitSound(Snd("pop"), 90)
        end
        F.balloon:Remove()
    end
    crate:SetNWBool("MCCLifting", false)
    local phys = crate:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(true)
        phys:Wake()
    end
    Notify(F.ply, "Your Fulton balloon was shot down!")
    hook.Run("MCC_FultonPopped", crate, attacker)
end

-- Signal flares and airdrops ---------------------------------------------------------------------

function X.ThrowFlare(ply)
    local sid = ply:SteamID64()
    if X.Available(sid) <= 0 then return false, "You have no crates sent up to call in" end
    local flare = ents.Create("mcc_flare")
    if not IsValid(flare) then return false end
    local aim = ply:GetAimVector()
    flare:SetPos(ply:GetShootPos() + aim * 16)
    flare:SetAngles(Angle(math.random(0, 359), math.random(0, 359), 0))
    flare:Spawn()
    local phys = flare:GetPhysicsObject()
    if IsValid(phys) then
        phys:SetVelocity(aim * 650 + ply:GetVelocity() + Vector(0, 0, 120))
        phys:AddAngleVelocity(Vector(math.random(-400, 400), math.random(-400, 400), 0))
    end
    flare.MCCOwner, flare.MCCName = sid, ply:Nick()
    flare.MCCDropAt = CurTime() + MCC.Config.Get("extract_drop_delay")
    X.Pending[sid] = (X.Pending[sid] or 0) + 1
    X.Flares[flare] = true
    ply:EmitSound("weapons/slam/throw.wav")
    NotifyAll("A signal flare was thrown. Watch for red smoke: a supply drop is coming in.")
    return true
end

-- A flare that's removed before its drop (map cleanup) gives the crate back.
function X.FlareRemoved(flare)
    if not X.Flares[flare] then return end
    X.Flares[flare] = nil
    if not flare.MCCDropped then X.Pending[flare.MCCOwner] = math.max(0, (X.Pending[flare.MCCOwner] or 1) - 1) end
end

-- Puts a stored crate's grids back into a new crate (fresh item ids, removed items dropped).
local function Restore(saved)
    local grids = {}
    for i, g in ipairs(istable(saved.grids) and saved.grids or {}) do
        local items = istable(g.items) and g.items or {}
        Inv.Prune(items)
        for _, it in ipairs(items) do Inv.ReID(it) end
        grids[i] = {w = math.Clamp(tonumber(g.w) or 5, 1, 12), h = math.Clamp(tonumber(g.h) or 5, 1, 12), items = items}
    end
    if #grids == 0 then
        grids[1] = {w = MCC.Config.Get("extract_crate_w"), h = MCC.Config.Get("extract_crate_h"), items = {}}
    end
    return grids
end

function X.DropCrate(flare)
    flare.MCCDropped = true
    local sid = flare.MCCOwner
    X.Pending[sid] = math.max(0, (X.Pending[sid] or 1) - 1)
    local owner = player.GetBySteamID64(sid)
    local pos = flare:GetPos()

    local tr = util.TraceLine({start = pos + Vector(0, 0, 16), endpos = pos + Vector(0, 0, 4096), filter = flare, mask = MASK_SOLID})
    if tr.Hit and not tr.HitSky then
        Notify(owner, "No open sky over your flare. The drop was called off; your crate is still stored.")
        return nil
    end
    local saved = TakeOldest(sid)
    if not saved then return nil end

    local height = math.min(1800, (tr.HitPos - pos):Length() - 80)
    local crate = ents.Create(X.CRATE_CLASS)
    if not IsValid(crate) then return nil end
    local grids = Restore(saved)
    crate.MCCCont = {name = "Extraction Crate", extract = true, grids = grids}
    crate:SetPos(pos + Vector(0, 0, math.max(height, 64)))
    crate:SetAngles(Angle(0, math.random(0, 359), 0))
    crate:Spawn()
    crate:Activate()
    crate:SetChute(true)
    crate.MCCChuteStart = CurTime()
    crate:SetNWFloat("MCCDropMark", CurTime() + MCC.Config.Get("extract_marker_time"))
    -- whoever called it in knows what's inside; everyone else has to search
    if IsValid(owner) then
        for i = 1, #grids do Inv.MarkSectionDone(owner, crate, "c:" .. i) end
    end
    SafeRemoveEntityDelayed(flare, 30)
    NotifyAll("Supply drop inbound!")
    hook.Run("MCC_CrateDropped", sid, crate)
    return crate
end

timer.Create("MCC_ExtractFlares", 0.25, 0, function()
    for flare in pairs(X.Flares) do
        if not IsValid(flare) then
            X.Flares[flare] = nil
        elseif not flare.MCCDropped and CurTime() >= flare.MCCDropAt then
            X.DropCrate(flare)
        end
    end
end)

-- Using the items ---------------------------------------------------------------------------------

function X.TargetCrate(ply)
    local e = Inv.OpenTarget(ply)
    if X.IsCrate(e) then return e end
    local tr = ply:GetEyeTrace()
    if X.IsCrate(tr.Entity) and tr.HitPos:Distance(ply:GetShootPos()) <= MCC.Config.Get("inv_use_distance") + 30 then
        return tr.Entity
    end
end

-- The flare is thrown from the inventory; the Fulton is equipment with its own SWEP (lua/weapons/mcc_fulton.lua).
hook.Add("MCC_UseItem", "MCC_Extract", function(ply, it, def)
    if def.data.effect ~= "flare" then return end
    if not X.Enabled() then return false, "Extraction is turned off on this server" end
    return X.ThrowFlare(ply)
end)

-- JMod workbench recipes (costs in data/mcc/jmod_recipes.json) ---------------------------------

local JR = MCC.JModRecipes
JR.Add("Extraction Crate", {results = X.CRATE_CLASS, cost = {["wood"] = 50, ["steel"] = 20, ["precision parts"] = 10},
    description = "A 5x5 crate for gear you want to keep. Send it up with a Fulton; call it back next session with a signal flare."})
JR.Add("Fulton Recovery Device", {results = "FUNC MCCFulton", cost = {["gas"] = 20, ["cloth"] = 10, ["basic parts"] = 10},
    description = "Sends an extraction crate into the sky for next session. Needs open sky; the balloon can be shot down."})
JR.Add("Signal Flare", {results = "FUNC MCCFlare", cost = {["chemicals"] = 5, ["propellant"] = 5},
    description = "Throw it to call in your oldest stored extraction crate. Everyone can see the drop."})
JR.AddBuildFunc("MCCFulton", function(ply, pos)
    return Inv.SpawnWorldItem(Inv.NewItem("mcc_fulton", 1), pos, nil, true)
end)
JR.AddBuildFunc("MCCFlare", function(ply, pos)
    return Inv.SpawnWorldItem(Inv.NewItem("mcc_flare", 1), pos, nil, true)
end)

-- Admin ---------------------------------------------------------------------------------------------

local function FindPlayer(arg)
    if not arg then return nil end
    for _, p in ipairs(player.GetAll()) do
        if p:SteamID64() == arg or string.find(string.lower(p:Nick()), string.lower(arg), 1, true) then return p end
    end
end

MCC.Command("extract_list", "MCC Moderator", "[player]", "Lists a player's stored extraction crates.", function(ply, args)
    local target = FindPlayer(args[1]) or ply
    if not IsValid(target) then return MCC.Util.Reply(ply, "Usage: mcc_extract_list <player>") end
    local crates = X.Stored(target:SteamID64())
    MCC.Util.Reply(ply, "%s has %d stored crate(s):", target:Nick(), #crates)
    for i, c in ipairs(crates) do
        local n = 0
        for _, g in ipairs(c.grids or {}) do n = n + #(g.items or {}) end
        MCC.Util.Reply(ply, "  %d. %d item(s), sent up by %s, %s", i, n, tostring(c.by), os.date("%Y-%m-%d %H:%M", c.t or 0))
    end
end)

MCC.Command("extract_clear", "MCC Admin", "<player>", "Deletes a player's stored extraction crates.", function(ply, args)
    local target = FindPlayer(args[1])
    if not IsValid(target) then return MCC.Util.Reply(ply, "Usage: mcc_extract_clear <player>") end
    Save(target:SteamID64(), {})
    MCC.Util.Reply(ply, "Cleared %s's stored crates.", target:Nick())
end)
