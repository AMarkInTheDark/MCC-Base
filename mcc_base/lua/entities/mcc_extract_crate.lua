-- Extraction Crate: a 5x5 container crafted at the JMod workbench. Fill it, then use a Fulton on it
-- to send it to your stash for the next session (lua/mcc/extract/). Dropped crates arrive by parachute.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Extraction Crate"
ENT.Category = "MCC"
ENT.Spawnable = true
ENT.AdminOnly = true
ENT.Model = "models/props_junk/wood_crate001a.mdl"

local FALL_SPEED = 260 -- units/s under the parachute

function ENT:SetupDataTables()
    self:NetworkVar("Bool", 0, "Chute")
end

if SERVER then
    function ENT:SpawnFunction(ply, tr, class)
        if not tr.Hit then return end
        local e = ents.Create(class)
        e:SetPos(tr.HitPos + tr.HitNormal * 24)
        e:Spawn()
        e:Activate()
        return e
    end

    function ENT:Initialize()
        self:SetModel(self.Model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetMass(120)
            phys:Wake()
        end
        self:SetNWString("MCCName", "Extraction Crate")
        if not self.MCCCont then
            -- a freshly crafted crate is empty: nothing to search
            self.MCCCont = {name = "Extraction Crate", noSearch = true, extract = true, grids = {
                {w = MCC.Config.Get("extract_crate_w"), h = MCC.Config.Get("extract_crate_h"), items = {}},
            }}
        end
    end

    -- Parachute: fall slowly until it lands.
    function ENT:Think()
        if self:GetChute() then
            local phys = self:GetPhysicsObject()
            if IsValid(phys) then
                local v = phys:GetVelocity()
                if v.z < -FALL_SPEED then
                    phys:SetVelocity(Vector(v.x * 0.9, v.y * 0.9, -FALL_SPEED))
                end
            end
            local tr = util.TraceLine({start = self:GetPos(), endpos = self:GetPos() - Vector(0, 0, 40), filter = self})
            if tr.Hit or (CurTime() - (self.MCCChuteStart or 0)) > 60 then
                self:SetChute(false)
                self:EmitSound("physics/wood/wood_box_impact_hard3.wav")
            end
        end
        if self.MCCFulton then MCC.Extract.FultonThink(self) end
        self:NextThink(CurTime())
        return true
    end

    function ENT:OnTakeDamage(dmg)
        self:TakePhysicsDamage(dmg)
    end
end

if CLIENT then
    local chuteModel = "models/props_phx/construct/metal_dome360.mdl"

    function ENT:Draw()
        self:DrawModel()
        if not self:GetChute() then
            if IsValid(self.MCCChute) then self.MCCChute:Remove() end
            return
        end
        -- a simple canopy on lines above the crate
        if not IsValid(self.MCCChute) then
            self.MCCChute = ClientsideModel(chuteModel, RENDERGROUP_OPAQUE)
            if IsValid(self.MCCChute) then
                self.MCCChute:SetNoDraw(true)
                self.MCCChute:SetModelScale(0.75, 0)
                self.MCCChute:SetMaterial("models/debug/debugwhite")
            end
        end
        local top = self:GetPos() + Vector(0, 0, 150 + math.sin(CurTime() * 1.3) * 4)
        if IsValid(self.MCCChute) then
            self.MCCChute:SetPos(top)
            self.MCCChute:SetAngles(Angle(0, CurTime() * 8 % 360, 0))
            render.SetColorModulation(0.42, 0.45, 0.34)
            self.MCCChute:DrawModel()
            render.SetColorModulation(1, 1, 1)
        end
        render.SetColorMaterial()
        local mins, maxs = self:OBBMins(), self:OBBMaxs()
        for _, c in ipairs({Vector(mins.x, mins.y, maxs.z), Vector(maxs.x, mins.y, maxs.z),
            Vector(mins.x, maxs.y, maxs.z), Vector(maxs.x, maxs.y, maxs.z)}) do
            local from = self:LocalToWorld(c)
            local to = top + (from - self:GetPos()):GetNormalized() * 30 - Vector(0, 0, 10)
            render.DrawBeam(from, to, 0.6, 0, 1, Color(30, 30, 26))
        end
    end

    function ENT:OnRemove()
        if IsValid(self.MCCChute) then self.MCCChute:Remove() end
    end
end
