-- The Fulton balloon above a crate being extracted. Shooting it before the crate is pulled away
-- pops it and drops the crate (lua/mcc/extract/sv_extract.lua runs the lift and animation).
--
-- With the MGSV Fulton Recovery System addon installed (Workshop 876405188, by kipper) it's MGSV's balloon,
-- orange or blue, with its blinking red lamp; otherwise an olive HL2 balloon.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Fulton Balloon"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_BOTH
ENT.Model = "models/maxofs2d/balloon_classic.mdl"
ENT.MGSVModel = "models/mgsv/items/fulton.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Entity", 0, "Crate")
    self:NetworkVar("Bool", 0, "MGSV")
end

if SERVER then
    function ENT:Initialize()
        local mgsv = self.MCCMGSV == true
        self:SetMGSV(mgsv)
        if mgsv then
            self:SetModel(self.MGSVModel)
            self:SetSkin(math.random(1, 2)) -- orange or blue
        else
            self:SetModel(self.Model)
            self:SetColor(Color(70, 74, 60))
        end
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        self:SetModelScale(mgsv and 0.1 or 0.3, 0)
    end

    -- A sphere hull matching the inflated balloon, so shots that hit what you see pop it.
    function ENT:SetBalloonHull(radius)
        if self:GetMGSV() then
            local mn, mx = self:OBBMins(), self:OBBMaxs()
            radius = math.max(radius * 0.6, (mx - mn):Length() * 0.35)
        end
        self:PhysicsInitSphere(radius, "rubber")
        self:SetCollisionBounds(Vector(-radius, -radius, -radius), Vector(radius, radius, radius))
        self:SetSolid(SOLID_VPHYSICS)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
    end

    function ENT:OnTakeDamage(dmg)
        local crate = self:GetCrate()
        if IsValid(crate) then MCC.Extract.PopFulton(crate, dmg:GetAttacker()) end
    end
end

if CLIENT then
    local rope = Material("cable/rope")
    local glow = Material("sprites/light_glow02_add")

    function ENT:Draw()
        self:DrawModel()
    end

    function ENT:DrawTranslucent()
        local crate = self:GetCrate()
        local scale = self:GetModelScale()
        if IsValid(crate) then
            -- the line down to the crate
            local top = crate:LocalToWorld(Vector(0, 0, crate:OBBMaxs().z))
            local from = self:GetPos() - Vector(0, 0, (self:GetMGSV() and 2 or 8) * scale)
            render.SetMaterial(rope)
            render.DrawBeam(from, top, 1.2, 0, from:Distance(top) / 16, color_white)
        end
        if self:GetMGSV() then
            -- MGSV's red lamp, blinking
            local on = math.floor(CurTime() * 2.5) % 2 == 0
            if on then
                local pos = self:GetPos() + self:GetUp() * 14 * scale
                render.SetMaterial(glow)
                render.DrawSprite(pos, 16, 16, Color(255, 0, 0, 255))
                local dl = DynamicLight(self:EntIndex())
                if dl then
                    dl.pos, dl.r, dl.g, dl.b = pos, 255, 55, 55
                    dl.brightness, dl.Decay, dl.Size, dl.DieTime = 2, 1000, 128, CurTime() + 0.2
                end
            end
        end
    end
end
