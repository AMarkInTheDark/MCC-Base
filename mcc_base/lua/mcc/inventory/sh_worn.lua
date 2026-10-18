-- Worn gear: rigs, backpacks, armor and headgear show on the character wearing them (and stay on
-- their body after death). Any item gets a worn model through data.worn, in Lua or items.json:
--
--   data = {slot = "rig", worn = "models/eft/rigs/blackrock.mdl", cells = {...}}
--
-- or as a table for more control:
--
--   worn = {model = "...", skin = 1, bodygroups = "0110",   -- bodygroups: one digit per group, or {name = value}
--           bone = "ValveBiped.Bip01_Spine2", pos = {x, y, z}, ang = {p, y, r}, scale = 1}
--
-- Without `bone` the model is bonemerged: it follows the character's skeleton, which is how
-- playermodel gear addons are made. With `bone` it's stuck to that bone at the given offset, for
-- props that weren't rigged to a skeleton.

local Inv = MCC.Inv

MCC.Config.Define("inv_worn_models", true, "Show worn rigs, backpacks and armor on players and bodies (items with data.worn).")

-- Slots whose items can show on the character, in draw order.
Inv.WornSlots = {"armor", "rig", "backpack", "headwear", "facecover", "eyewear", "earpiece", "armband"}

-- The worn-model settings of an item definition, or nil.
function Inv.WornSpec(def)
    local w = def and def.data and def.data.worn
    if isstring(w) then w = {model = w} end
    if not istable(w) or not isstring(w.model) or w.model == "" then return nil end
    return w
end

if SERVER then
    -- "slot=id;slot=id" for what an inventory shows on its wearer.
    function Inv.WornString(inv)
        if not MCC.Config.Get("inv_worn_models") or not inv or not inv.slots then return "" end
        local parts = {}
        for _, key in ipairs(Inv.WornSlots) do
            local it = inv.slots[key]
            if it and Inv.WornSpec(MCC.Items.Get(it.id)) then parts[#parts + 1] = key .. "=" .. it.id end
        end
        return table.concat(parts, ";")
    end

    -- Networks what an entity (player or body) is wearing; only sends when it changed.
    function Inv.RefreshWorn(ent, inv)
        if not IsValid(ent) then return end
        if not inv then
            -- bodies and containers hold MCCCont; players hold MCCInv
            if ent.MCCCont then inv = ent.MCCCont.inv else inv = ent.MCCInv end
        end
        local s = Inv.WornString(inv)
        if ent:GetNWString("MCCWorn", "") ~= s then ent:SetNWString("MCCWorn", s) end
    end

    hook.Add("MCC_ItemsChanged", "MCC_WornRefresh", function()
        for _, ply in ipairs(player.GetAll()) do Inv.RefreshWorn(ply) end
    end)
end

if CLIENT then
    local cvDraw = CreateClientConVar("mcc_worn_draw", "1", true, false,
        "Draw worn rigs, backpacks and armor on characters.")
    local cvFirst = CreateClientConVar("mcc_worn_firstperson", "0", true, false,
        "Also draw your own worn gear in first person (for first-person body addons).")
    local cvBodyDist = CreateClientConVar("mcc_worn_body_distance", "1500", true, false,
        "Bodies further away than this don't show their worn gear (0 = no limit).", 0, 50000)

    local function V(t, ctor)
        if not istable(t) then return ctor() end
        return ctor(tonumber(t[1] or t.x or t.p) or 0, tonumber(t[2] or t.y) or 0, tonumber(t[3] or t.z or t.r) or 0)
    end

    -- A clientside model for one worn item, attached to ent. noDraw = drawn by hand (inventory doll).
    function Inv.MakeWornModel(ent, spec, noDraw)
        if not util.IsValidModel(spec.model) then return nil end
        local m = ClientsideModel(spec.model, RENDERGROUP_OPAQUE)
        if not IsValid(m) then return nil end
        if spec.skin then m:SetSkin(tonumber(spec.skin) or 0) end
        if isstring(spec.bodygroups) then
            for i = 1, #spec.bodygroups do
                m:SetBodygroup(i - 1, tonumber(spec.bodygroups:sub(i, i)) or 0)
            end
        elseif istable(spec.bodygroups) then
            for k, v in pairs(spec.bodygroups) do
                local id = isnumber(k) and k or m:FindBodygroupByName(k)
                if id and id >= 0 then m:SetBodygroup(id, tonumber(v) or 0) end
            end
        end
        if spec.scale then m:SetModelScale(tonumber(spec.scale) or 1, 0) end

        local bone = spec.bone and ent:LookupBone(spec.bone)
        if bone then
            m:FollowBone(ent, bone)
            m:SetLocalPos(V(spec.pos, Vector))
            m:SetLocalAngles(V(spec.ang, Angle))
        else
            m:SetParent(ent)
            m:AddEffects(EF_BONEMERGE)
            m:AddEffects(EF_BONEMERGE_FASTCULL)
        end
        m:SetNoDraw(noDraw and true or false)
        return m
    end

    -- Builds every worn model listed in a "slot=id;..." string.
    function Inv.MakeWornModels(ent, str, noDraw)
        local out = {}
        for _, id in string.gmatch(str or "", "(%w+)=([^;]+)") do
            local spec = Inv.WornSpec(MCC.Items.Get(id))
            local m = spec and Inv.MakeWornModel(ent, spec, noDraw)
            if m then out[#out + 1] = m end
        end
        return out
    end

    local function Clear(list)
        for _, m in ipairs(list or {}) do
            if IsValid(m) then m:Remove() end
        end
    end
    Inv.ClearWornModels = Clear

    local Tracked = {} -- ent -> {str, model, parts}

    local function Untrack(ent)
        local rec = Tracked[ent]
        if rec then Clear(rec.parts) end
        Tracked[ent] = nil
    end

    -- Bodies past mcc_worn_body_distance drop their gear models (made again when you come closer; a little
    -- slack so standing at the edge doesn't rebuild them over and over).
    local function TooFar(ent)
        local d = cvBodyDist:GetFloat()
        if d <= 0 or ent:IsPlayer() then return false end
        local lp = LocalPlayer()
        if not IsValid(lp) then return false end
        return ent:GetPos():Distance(lp:GetPos()) > d * (Tracked[ent] and 1.1 or 1)
    end
    Inv.WornTooFar = TooFar

    local function Check(ent)
        local str = ""
        if cvDraw:GetBool() and not ent:IsDormant() and not TooFar(ent) then str = ent:GetNWString("MCCWorn", "") end
        local rec = Tracked[ent]
        if str == "" then
            if rec then Untrack(ent) end
            return
        end
        local mdl = ent:GetModel()
        if rec and rec.str == str and rec.model == mdl then return end
        if rec then Clear(rec.parts) end
        Tracked[ent] = {str = str, model = mdl, parts = Inv.MakeWornModels(ent, str)}
    end

    -- Ragdolls are noted as they come into view (and the map is swept every few seconds, in case one was
    -- missed), so the scan below doesn't walk every entity four times a second.
    local Ragdolls, nextSweep = {}, 0
    hook.Add("OnEntityCreated", "MCC_WornRagdolls", function(ent)
        if IsValid(ent) and ent:GetClass() == "prop_ragdoll" then Ragdolls[ent] = true end
    end)

    -- Pick up changes (equips, deaths, bodies coming into view) a few times a second.
    function Inv.WornScan()
        for ent in pairs(Tracked) do
            if not IsValid(ent) then Untrack(ent) end
        end
        if CurTime() >= nextSweep then
            nextSweep = CurTime() + 5
            for _, rag in ipairs(ents.FindByClass("prop_ragdoll")) do Ragdolls[rag] = true end
        end
        for _, ply in ipairs(player.GetAll()) do Check(ply) end
        for rag in pairs(Ragdolls) do
            if not IsValid(rag) then
                Ragdolls[rag] = nil
            elseif rag:GetNWBool("MCCBody", false) then
                Check(rag)
            end
        end
    end
    timer.Create("MCC_WornScan", 0.25, 0, Inv.WornScan)

    -- Hide gear on dead players (their body wears it) and your own in first person.
    hook.Add("Think", "MCC_WornVisibility", function()
        if not next(Tracked) then return end
        local lp = LocalPlayer()
        for ent, rec in pairs(Tracked) do
            if IsValid(ent) then
                local hide = ent:GetNoDraw()
                if ent:IsPlayer() then
                    hide = hide or not ent:Alive()
                        or (ent == lp and not lp:ShouldDrawLocalPlayer() and not cvFirst:GetBool())
                end
                if rec.hidden ~= hide then
                    rec.hidden = hide
                    for _, m in ipairs(rec.parts) do
                        if IsValid(m) then m:SetNoDraw(hide) end
                    end
                end
            end
        end
    end)

    hook.Add("EntityRemoved", "MCC_WornCleanup", function(ent)
        if Tracked[ent] then Untrack(ent) end
        Ragdolls[ent] = nil
    end)
end
