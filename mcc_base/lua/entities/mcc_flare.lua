-- A thrown signal flare: burns red with smoke so everyone can see where the crate is coming down.
-- The drop itself is scheduled by lua/mcc/extract/sv_extract.lua.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Signal Flare"
ENT.Spawnable = false
ENT.Model = "models/props_junk/flare.mdl"
ENT.RenderGroup = RENDERGROUP_BOTH

if SERVER then
    function ENT:Initialize()
        self:SetModel(self.Model)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
        self:EmitSound("weapons/flaregun/burn.wav", 70)
    end

    function ENT:OnRemove()
        self:StopSound("weapons/flaregun/burn.wav")
        MCC.Extract.FlareRemoved(self)
    end
end

if CLIENT then
    function ENT:Initialize()
        self.Emitter = ParticleEmitter(self:GetPos())
        self.NextPuff = 0
    end

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        local pos = self:GetPos()
        render.SetMaterial(Material("sprites/light_glow02_add"))
        render.DrawSprite(pos, 48 + math.random(0, 10), 48 + math.random(0, 10), Color(255, 40, 30))
    end

    function ENT:Think()
        local pos = self:GetPos()
        local dl = DynamicLight(self:EntIndex())
        if dl then
            dl.pos = pos
            dl.r, dl.g, dl.b = 255, 40, 30
            dl.brightness = 3
            dl.decay = 1000
            dl.size = 320 + math.random(0, 40)
            dl.dietime = CurTime() + 0.2
        end
        -- a column of red smoke, tall enough to see over buildings
        if self.Emitter and CurTime() > self.NextPuff then
            self.NextPuff = CurTime() + 0.05
            self.Emitter:SetPos(pos)
            local p = self.Emitter:Add("particle/particle_smokegrenade", pos)
            if p then
                p:SetVelocity(Vector(math.Rand(-12, 12), math.Rand(-12, 12), math.Rand(90, 140)))
                p:SetDieTime(math.Rand(6, 9))
                p:SetStartAlpha(170)
                p:SetEndAlpha(0)
                p:SetStartSize(12)
                p:SetEndSize(90)
                p:SetRoll(math.Rand(0, 360))
                p:SetRollDelta(math.Rand(-0.4, 0.4))
                p:SetColor(200, 40, 34)
                p:SetAirResistance(20)
                p:SetGravity(Vector(0, 0, 12))
            end
        end
        self:SetNextClientThink(CurTime())
        return true
    end

    function ENT:OnRemove()
        if self.Emitter then self.Emitter:Finish() end
    end
end
