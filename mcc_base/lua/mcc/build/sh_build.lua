-- Building with the Builder Tablet, Rust style, inside your FOB.
--
-- Structure (foundations, walls, floors made from base Garry's Mod props) is built as Twig and snaps to
-- a building grid: the first foundation sets the grid (its size and facing), more foundations attach to
-- its sides, walls stand on foundation and floor edges, floors sit on top of walls. As in Rust, the
-- Builder Hammer upgrades pieces (right-click one), repairs them (hit them) and removes them; the tiers:
--
--   Twig 10 HP (decays in 1 h) > Wood 1000 (3 h) > Stone 3500 (5 h, fire-proof) > Sheet Metal 8000 (8 h)
--   > Armored 12000 (12 h)
--
-- Placing, upgrading and repairing cost JMod resources: from your FOB's stash first (in its zone), then
-- what you carry. Every piece also has upkeep: JMod resources
-- the FOB pays every 30 minutes (lua/mcc/fob/); if it can't, the piece decays over its tier's time.
-- Fortifications (sandbags, Hesco, barriers, fences) are placed freely, line up with the same piece,
-- and have their own cost, health and upkeep.
--
-- data/mcc/build_tiers.json and data/mcc/build_pieces.json hold all of it, so new pieces (the Rust
-- models later) need no Lua: kind "foundation", "wall" or "floor" snap and use the tiers; "free" don't.

MCC.Build = MCC.Build or {}
local B = MCC.Build

MCC.Config.Define("build_free", false, "Building, upgrading and repairing cost nothing.")
MCC.Config.Define("build_outside_fob", false, "Allow building outside FOBs (pieces there have no upkeep and don't decay).")
MCC.Config.Define("build_range", 300, "How far away the tablet can place pieces.", 64, 1000)
MCC.Config.Define("build_refund", 0.5, "Share of a piece's current tier cost you get back when you remove it.", 0, 1)
MCC.Config.Define("build_repair_cost", 0.5, "Repairing from 0 to full costs this share of the tier's cost.", 0, 10)
MCC.Config.Define("build_use_fob_stash", true, "Building, upgrading and repairing in your FOB pay from its stash first, then from what you carry; refunds go to the stash.")
MCC.Config.Define("build_hammer_repair", 0.1, "Share of a piece's max health one hammer hit repairs.", 0.01, 1)
MCC.Config.Define("build_repair_delay", 30, "Seconds after a piece is damaged before it can be repaired (Rust: 30).", 0, 600)
MCC.Config.Define("build_hammer_viewmodel", "models/weapons/c_crowbar.mdl", "First-person model of the Builder Hammer (a c_ model with hands).")
MCC.Config.Define("build_hammer_worldmodel", "models/weapons/w_crowbar.mdl", "Third-person model of the Builder Hammer.")

-- Rust's building tiers. cost = to place (twig) or upgrade to it; upkeep = per FOB payment (30 min);
-- decayHours = full health to nothing when its upkeep isn't paid; material = how the piece looks.
B.DEFAULT_TIERS = {
    {id = "twig", name = "Twig", health = 10, decayHours = 1, cost = {["wood"] = 20}, upkeep = {["wood"] = 1},
        material = "models/props_wasteland/wood_fence01a"},
    {id = "wood", name = "Wood", health = 1000, decayHours = 3, cost = {["wood"] = 50}, upkeep = {["wood"] = 2},
        material = "phoenix_storms/wood"},
    {id = "stone", name = "Stone", health = 3500, decayHours = 5, fireImmune = true, cost = {["concrete"] = 75},
        upkeep = {["concrete"] = 2}, material = "phoenix_storms/concrete0"},
    {id = "metal", name = "Sheet Metal", health = 8000, decayHours = 8, fireImmune = true, cost = {["steel"] = 50},
        upkeep = {["steel"] = 2}, material = "phoenix_storms/metalset_1-2"},
    {id = "armored", name = "Armored", health = 12000, decayHours = 12, fireImmune = true, cost = {["titanium"] = 25},
        upkeep = {["titanium"] = 1}, material = "phoenix_storms/metalfloor_2-3"},
}

-- kind: foundation / wall / floor (grid, tiered) or free. stand = stood upright (panels as walls).
-- Free pieces: cost and upkeep in JMod resources, fixed health, decayHours.
local function Free(id, name, cat, model, cost, upkeep, health, hours)
    return {id = id, name = name, category = cat, kind = "free", model = model, cost = cost, upkeep = upkeep,
        health = health, decayHours = hours}
end
B.DEFAULT_PIECES = {
    -- structure (base Garry's Mod props; the tier sets health and look)
    {id = "foundation", name = "Foundation", category = "Structure", kind = "foundation",
        model = "models/hunter/blocks/cube2x2x05.mdl"},
    {id = "wall", name = "Wall", category = "Structure", kind = "wall", stand = true,
        model = "models/props_phx/construct/wood/wood_panel2x2.mdl"},
    {id = "floor", name = "Floor", category = "Structure", kind = "floor",
        model = "models/props_phx/construct/wood/wood_panel2x2.mdl"},
    -- fortifications (from Alydus's Fortification Builder Tablet)
    Free("sandbags_corner1", "Sandbags Corner 1", "Sandbags", "models/props_fortifications/sandbags_corner1.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("sandbags_corner1_tall", "Sandbags Corner 1 Tall", "Sandbags", "models/props_fortifications/sandbags_corner1_tall.mdl", {sand = 30}, {sand = 1}, 600, 4),
    Free("sandbags_corner2", "Sandbags Corner 2", "Sandbags", "models/props_fortifications/sandbags_corner2.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("sandbags_corner2_tall", "Sandbags Corner 2 Tall", "Sandbags", "models/props_fortifications/sandbags_corner2_tall.mdl", {sand = 30}, {sand = 1}, 600, 4),
    Free("sandbags_corner3", "Sandbags Corner 3", "Sandbags", "models/props_fortifications/sandbags_corner3.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("sandbags_line1", "Sandbags Line 1", "Sandbags", "models/props_fortifications/sandbags_line1.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("sandbags_line1_tall", "Sandbags Line 1 Tall", "Sandbags", "models/props_fortifications/sandbags_line1_tall.mdl", {sand = 30}, {sand = 1}, 600, 4),
    Free("sandbags_line2", "Sandbags Line 2", "Sandbags", "models/props_fortifications/sandbags_line2.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("sandbags_line2_tall", "Sandbags Line 2 Tall", "Sandbags", "models/props_fortifications/sandbags_line2_tall.mdl", {sand = 30}, {sand = 1}, 600, 4),
    Free("sandbags_line3", "Sandbags Line 3", "Sandbags", "models/props_fortifications/sandbags_line2b.mdl", {sand = 20}, {sand = 1}, 400, 4),
    Free("concrete_wall", "Concrete Wall", "Concrete", "models/props_fortifications/concrete_wall001_96_reference.mdl", {concrete = 60}, {concrete = 2}, 3500, 6),
    Free("concrete_barrier1", "Concrete Barrier 1", "Concrete", "models/props_c17/concrete_barrier001a.mdl", {concrete = 40}, {concrete = 1}, 2500, 6),
    Free("concrete_barrier2_small", "Concrete Barrier 2 Small", "Concrete", "models/props_fortifications/concrete_barrier001_96_reference.mdl", {concrete = 35}, {concrete = 1}, 2000, 6),
    Free("concrete_barrier2_large", "Concrete Barrier 2 Large", "Concrete", "models/props_fortifications/concrete_barrier001_128_reference.mdl", {concrete = 45}, {concrete = 1}, 2800, 6),
    Free("concrete_barrier3", "Concrete Barrier 3", "Concrete", "models/jbarnes/props/concrete barricade.mdl", {concrete = 40}, {concrete = 1}, 2500, 6),
    Free("fence_small", "Small Fence", "Fences", "models/props_c17/fence01b.mdl", {steel = 10}, {steel = 1}, 300, 4),
    Free("fence_medium", "Medium Fence", "Fences", "models/props_c17/fence01a.mdl", {steel = 15}, {steel = 1}, 400, 4),
    Free("fence_large", "Large Fence", "Fences", "models/props_c17/fence03a.mdl", {steel = 25}, {steel = 1}, 600, 4),
    Free("anticlimb_small", "Small Anti-Climb Fence", "Fences", "models/props_wasteland/exterior_fence002b.mdl", {steel = 20}, {steel = 1}, 500, 4),
    Free("anticlimb_medium", "Medium Anti-Climb Fence", "Fences", "models/props_wasteland/exterior_fence002c.mdl", {steel = 30}, {steel = 1}, 700, 4),
    Free("anticlimb_large", "Large Anti-Climb Fence", "Fences", "models/props_wasteland/exterior_fence002d.mdl", {steel = 40}, {steel = 2}, 900, 4),
    Free("police_single", "Police Barricade Single", "Barricades", "models/props_street/police_barricade.mdl", {plastic = 10}, {plastic = 1}, 100, 3),
    Free("police_triple", "Police Barricade Triple", "Barricades", "models/props_street/police_barricade2.mdl", {plastic = 15}, {plastic = 1}, 150, 3),
    Free("hesco_small", "Hesco Small", "Hesco", "models/static_afghan/prop_fortification_hesco_small.mdl", {sand = 40, steel = 10}, {sand = 2}, 2000, 6),
    Free("hesco_tall", "Hesco Tall", "Hesco", "models/iraq/ir_hesco_basket_01.mdl", {sand = 60, steel = 20}, {sand = 2}, 3000, 6),
    Free("hesco_leaning", "Hesco Tall Leaning", "Hesco", "models/iraq/ir_hesco_basket_01b.mdl", {sand = 60, steel = 20}, {sand = 2}, 3000, 6),
}

B.Tiers = B.Tiers or table.Copy(B.DEFAULT_TIERS)

function B.TierByID(id)
    for i, t in ipairs(B.Tiers) do
        if t.id == id then return t, i end
    end
end

function B.IsStructure(piece)
    return piece and (piece.kind == "foundation" or piece.kind == "wall" or piece.kind == "floor")
end

-- What placing a piece costs: twig for structure, the piece's own cost otherwise.
function B.PlaceCost(piece)
    if B.IsStructure(piece) then return (B.Tiers[1] or {}).cost or {} end
    return istable(piece.cost) and piece.cost or {}
end

B.Pieces = B.Pieces or {}
B.Order = B.Order or {}

function B.SetPieces(list)
    B.Pieces, B.Order = {}, {}
    for _, p in ipairs(list or {}) do
        if istable(p) and isstring(p.id) and isstring(p.model) then
            B.Pieces[p.id] = p
            B.Order[#B.Order + 1] = p.id
        end
    end
end
if #B.Order == 0 then B.SetPieces(B.DEFAULT_PIECES) end

-- Model bounds, cached (a throwaway entity reads them on either realm).
B.Bounds = B.Bounds or {}
function B.ModelBounds(model)
    local c = B.Bounds[model]
    if c then return c[1], c[2] end
    local e = SERVER and ents.Create("prop_physics") or ClientsideModel(model)
    if not IsValid(e) then return Vector(-24, -24, -24), Vector(24, 24, 24) end
    if SERVER then e:SetModel(model) end
    local mins, maxs = e:OBBMins(), e:OBBMaxs()
    e:Remove()
    B.Bounds[model] = {mins, maxs}
    return mins, maxs
end

-- The piece's box in the building's axes, for a stand-up flag and a yaw of 0/90/180/270.
local function Box(mins, maxs, stand, syaw)
    local x0, x1, y0, y1, z0, z1
    if stand then
        -- rolled 90 degrees: model Y points up, model Z (its thin side) lies along the building's -Y
        x0, x1, y0, y1, z0, z1 = mins.x, maxs.x, -maxs.z, -mins.z, mins.y, maxs.y
    else
        x0, x1, y0, y1, z0, z1 = mins.x, maxs.x, mins.y, maxs.y, mins.z, maxs.z
    end
    for _ = 1, math.floor((syaw or 0) / 90 + 0.5) % 4 do
        x0, x1, y0, y1 = -y1, -y0, x0, x1
    end
    return x0, x1, y0, y1, z0, z1
end
B.Box = Box

-- Building frames: every piece carries its building's id and grid on networked vars.
--   O = ground point under the first foundation's centre, yaw = its facing,
--   G = cell size (that foundation's width), T = its height (where walls and level 0 start).
function B.FrameOf(ent)
    if not IsValid(ent) or ent:GetNWInt("MCCBld", 0) == 0 then return nil end
    return {id = ent:GetNWInt("MCCBld"), O = ent:GetNWVector("MCCBldO"), yaw = ent:GetNWFloat("MCCBldYaw"),
        G = ent:GetNWFloat("MCCBldG"), T = ent:GetNWFloat("MCCBldT")}
end

local function ToLocal(F, p)
    local d = p - F.O
    local r = -math.rad(F.yaw)
    local c, s = math.cos(r), math.sin(r)
    return d.x * c - d.y * s, d.x * s + d.y * c, d.z
end

local function ToWorld(F, x, y, z)
    local r = math.rad(F.yaw)
    local c, s = math.cos(r), math.sin(r)
    return F.O + Vector(x * c - y * s, x * s + y * c, z)
end
B.ToLocal, B.ToWorld = ToLocal, ToWorld

local function Round(v) return math.floor(v + 0.5) end
local function Sign(v) return v >= 0 and 1 or -1 end

local function WallCells(a, b)
    if a % 2 ~= 0 then return {{(a - 1) / 2, b / 2}, {(a + 1) / 2, b / 2}} end
    return {{a / 2, (b - 1) / 2}, {a / 2, (b + 1) / 2}}
end

-- Is there something that holds this slot up?
local function Supported(kind, i, j, k, a, b, has)
    if kind == "foundation" then
        return has("f:" .. (i + 1) .. ":" .. j) or has("f:" .. (i - 1) .. ":" .. j)
            or has("f:" .. i .. ":" .. (j + 1)) or has("f:" .. i .. ":" .. (j - 1))
    elseif kind == "wall" then
        if has("w:" .. a .. ":" .. b .. ":" .. (k - 1)) then return true end
        for _, c in ipairs(WallCells(a, b)) do
            if k == 0 and has("f:" .. c[1] .. ":" .. c[2]) then return true end
            if k > 0 and has("fl:" .. c[1] .. ":" .. c[2] .. ":" .. k) then return true end
        end
        return false
    elseif kind == "floor" then
        for _, e in ipairs({{2 * i + 1, 2 * j}, {2 * i - 1, 2 * j}, {2 * i, 2 * j + 1}, {2 * i, 2 * j - 1}}) do
            if has("w:" .. e[1] .. ":" .. e[2] .. ":" .. (k - 1)) then return true end
        end
        return has("fl:" .. (i + 1) .. ":" .. j .. ":" .. k) or has("fl:" .. (i - 1) .. ":" .. j .. ":" .. k)
            or has("fl:" .. i .. ":" .. (j + 1) .. ":" .. k) or has("fl:" .. i .. ":" .. (j - 1) .. ":" .. k)
    end
end

-- Finds the building the player is aiming at (the piece under the crosshair, or one close by).
local function FindFrame(tr)
    local F = B.FrameOf(tr.Entity)
    if F then return F, tr.Entity end
    local best, bestD
    for _, e in ipairs(ents.FindInSphere(tr.HitPos, 160)) do
        local f = B.FrameOf(e)
        if f then
            local d = e:GetPos():DistToSqr(tr.HitPos)
            if not bestD or d < bestD then best, bestD = e, d end
        end
    end
    if best then return B.FrameOf(best), best end
end

-- Where a piece would go. Shared: the client draws it as a ghost, the server builds it.
--   tr = the player's eye trace, rot = the player's extra rotation (degrees),
--   has(id, key) = whether building `id` already has something in slot `key`.
-- Returns {ok, reason, pos, ang, frame, key, root}.
function B.Solve(ply, piece, tr, rot, has)
    local out = {ok = false}
    if not piece or not tr or not tr.Hit then out.reason = "Aim at the ground" return out end
    if tr.HitPos:Distance(ply:GetShootPos()) > MCC.Config.Get("build_range") then out.reason = "Too far" return out end
    local mins, maxs = B.ModelBounds(piece.model)
    rot = rot or 0

    if piece.kind == "free" then
        local yaw = ply:EyeAngles().y - 180 + rot
        local target = tr.Entity
        if IsValid(target) and target:GetNWString("MCCPiece", "") == piece.id then
            -- line up with the same piece: flush against its longer side
            local alongX = (maxs.x - mins.x) >= (maxs.y - mins.y)
            local axis = alongX and target:GetForward() or target:GetRight()
            local len = alongX and (maxs.x - mins.x) or (maxs.y - mins.y)
            local s = Sign((tr.HitPos - target:GetPos()):Dot(axis))
            out.pos = target:GetPos() + axis * (s * len)
            out.ang = target:GetAngles()
        else
            out.pos = tr.HitPos - tr.HitNormal * mins.z
            out.ang = Angle(0, yaw, 0)
        end
        out.ok = true
        return out
    end

    local F, near = FindFrame(tr)
    if not F then
        if piece.kind ~= "foundation" then out.reason = "Build a foundation first" return out end
        -- the first foundation of a new building: on the ground, facing where you look
        if tr.HitNormal and tr.HitNormal.z < 0.7 then out.reason = "Needs flat ground" return out end
        local yaw = math.floor((ply:EyeAngles().y + rot) / 15 + 0.5) * 15
        local x0, x1, y0, y1, z0, z1 = Box(mins, maxs, false, 0)
        out.pos = tr.HitPos - Vector(0, 0, z0)
        local r = math.rad(yaw)
        local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        out.pos = out.pos - Vector(cx * math.cos(r) - cy * math.sin(r), cx * math.sin(r) + cy * math.cos(r), 0)
        out.ang = Angle(0, yaw, 0)
        out.root = {O = tr.HitPos, yaw = yaw, G = x1 - x0, T = z1 - z0}
        out.key = "f:0:0"
        out.ok = true
        return out
    end

    out.frame = F
    local G, T = F.G, F.T
    local px, py, pz = ToLocal(F, tr.HitPos)
    local function Has(key) return has(F.id, key) end
    local i, j = Round(px / G), Round(py / G)
    local key, cx, cy, cz, syaw, stand = nil, nil, nil, nil, 0, piece.stand and true or false
    local k, a, b = 0, 0, 0

    if piece.kind == "foundation" then
        key = "f:" .. i .. ":" .. j
        local x0, x1, y0, y1, z0, z1 = Box(mins, maxs, stand, 0)
        cx, cy, cz = i * G, j * G, (z1 - z0) / 2
    elseif piece.kind == "floor" then
        k = math.max(1, Round((pz - T) / G))
        key = "fl:" .. i .. ":" .. j .. ":" .. k
        local x0, x1, y0, y1, z0, z1 = Box(mins, maxs, stand, 0)
        cx, cy, cz = i * G, j * G, T + k * G - (z1 - z0) / 2
    elseif piece.kind == "wall" then
        k = math.max(0, math.floor((pz - T) / G + 0.05))
        local fx, fy = px / G - i, py / G - j
        if math.abs(fx) >= math.abs(fy) then
            a, b = 2 * i + Sign(fx), 2 * j
        else
            a, b = 2 * i, 2 * j + Sign(fy)
        end
        key = "w:" .. a .. ":" .. b .. ":" .. k
        -- turn the wall so its thin side faces across the edge
        local acrossX = a % 2 ~= 0
        local best
        for _, y in ipairs({0, 90}) do
            local x0, x1, y0, y1 = Box(mins, maxs, stand, y)
            local thick = acrossX and (x1 - x0) or (y1 - y0)
            if not best or thick < best then best, syaw = thick, y end
        end
        local x0, x1, y0, y1, z0, z1 = Box(mins, maxs, stand, syaw)
        cx, cy, cz = a * G / 2, b * G / 2, T + k * G + (z1 - z0) / 2
    else
        out.reason = "Unknown piece kind"
        return out
    end

    out.key = key
    local x0, x1, y0, y1, z0, z1 = Box(mins, maxs, stand, syaw)
    out.pos = ToWorld(F, cx - (x0 + x1) / 2, cy - (y0 + y1) / 2, cz - (z0 + z1) / 2)
    out.ang = Angle(0, F.yaw + syaw, stand and 90 or 0)
    if Has(key) then out.reason = "Something is already there" return out end
    if not Supported(piece.kind, i, j, k, a, b, Has) then out.reason = "Nothing to hold it up" return out end
    out.ok = true
    return out
end

-- Rules both realms check after the geometry: your FOB, its prop limit, and the resources you carry.
function B.Allowed(ply, piece, pos)
    local core = MCC.FOB and MCC.FOB.At(pos)
    if not core then
        if not MCC.Config.Get("build_outside_fob") then return false, "Build inside your FOB" end
    else
        if not MCC.FOB.CanModify(core, ply) then return false, "This isn't your FOB" end
        if core:GetPropCount() >= core:GetNWInt("MCCMaxProps", 1e9) then return false, "The FOB's prop limit is reached" end
    end
    local ok, err = B.CanAfford(ply, B.PlaceCost(piece), core)
    if not ok then return false, err end
    return true, nil, core
end

-- Resources in a FOB's stash, on both realms (clients read the core's MCCStore string).
function B.FOBStore(core)
    if not IsValid(core) then return {} end
    if SERVER then return MCC.FOB.Store(core) end
    local out = {}
    for res, n in string.gmatch(core:GetNWString("MCCStore", ""), "([^=;]+)=(%d+)") do out[res] = tonumber(n) end
    return out
end

-- The FOB whose stash pays for this player's work there (nil: only what they carry).
function B.PayingFOB(ply, core)
    if not IsValid(core) or not MCC.Config.Get("build_use_fob_stash") then return nil end
    if not MCC.FOB.CanModify(core, ply) then return nil end
    return core
end

-- Whether the FOB's stash and what the player carries cover a cost; false + "Needs 20 wood" when not.
function B.CanAfford(ply, cost, core)
    if MCC.Config.Get("build_free") then return true end
    local carried, stash = MCC.Inv.CountResources(ply), B.FOBStore(B.PayingFOB(ply, core))
    local missing = {}
    for res, n in pairs(cost or {}) do
        if (carried[res] or 0) + (stash[res] or 0) < n then missing[#missing + 1] = math.ceil(n) .. " " .. res end
    end
    if #missing > 0 then
        table.sort(missing)
        return false, "Needs " .. table.concat(missing, ", ")
    end
    return true
end

hook.Add("MCC_RegisterItems", "MCC_Build", function(Items)
    Items.Register("mcc_build_tablet", {
        name = "Builder Tablet", kind = "weapon", class = "mcc_build_tablet", w = 2, h = 2, weight = 1, rarity = "uncommon",
        model = "models/nirrti/tablet/tablet_sfm.mdl", category = "tools",
        data = {slot = "holster", desc = "Build foundations, walls, floors and fortifications inside your FOB, Rust style. "
            .. "Right-click to pick a piece, left-click to build, R to rotate. Upgrade, repair and remove pieces with the "
            .. "Builder Hammer. Costs come from your FOB's stash, then the JMod resources you carry."},
    })
    Items.Register("mcc_hammer", {
        name = "Builder Hammer", kind = "weapon", class = "mcc_hammer", w = 2, h = 1, weight = 1, rarity = "uncommon",
        model = "models/weapons/w_crowbar.mdl", category = "tools",
        data = {slot = "melee", desc = "Rust's hammer. Right-click a built piece to upgrade it (Twig > Wood > Stone > Sheet "
            .. "Metal > Armored), repair it or remove it; hit a damaged piece to repair it a bit at a time. "
            .. "Costs come from your FOB's stash, then the JMod resources you carry."},
    })
end)
