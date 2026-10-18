-- FOB core: the heart of a forward operating base (lua/mcc/fob/), its tool cupboard. E opens its menu.
-- JMod resource boxes pushed into it are stored for upkeep.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "FOB Core"
ENT.Category = "MCC"
ENT.Spawnable = false
ENT.Model = "models/props_silo/silo_launchroom_monitor.mdl"

function ENT:SetupDataTables()
    self:NetworkVar("Int", 0, "Tier")
    self:NetworkVar("Int", 1, "PropCount")
    self:NetworkVar("Float", 0, "HP")
    self:NetworkVar("Float", 1, "MaxHP")
    self:NetworkVar("Float", 2, "Stored")
    self:NetworkVar("Float", 3, "Food")
    self:NetworkVar("Float", 4, "Radius")
    self:NetworkVar("Float", 5, "ClaimEnds")
    self:NetworkVar("Bool", 0, "Abandoned")
    self:NetworkVar("String", 0, "OwnerID")
    self:NetworkVar("String", 1, "OwnerName")
end

if SERVER then
    function ENT:Initialize()
        -- the silo monitor is Episode Two content; fall back to an HL2 model if it isn't mounted
        local mdl = MCC.Config.Get("fob_core_model")
        if not util.IsValidModel(mdl) then mdl = util.IsValidModel(self.Model) and self.Model or "models/props_lab/reciever_cart.mdl" end
        self:SetModel(mdl)
        self:PhysicsInit(SOLID_VPHYSICS)
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:EnableMotion(false) end
        -- JMod boxes load into anything that lists what it consumes
        self.EZconsumes = MCC.FOB.Storage.accepts
    end

    function ENT:Use(ply)
        if IsValid(ply) and ply:IsPlayer() then MCC.FOB.Use(ply, self) end
    end

    function ENT:TryLoadResource(typ, amount)
        return MCC.FOB.Load(self, typ, amount)
    end

    function ENT:OnRemove()
        MCC.FOB.CoreRemoved(self)
    end
end

if CLIENT then
    function ENT:Draw()
        self:DrawModel()
    end
end
