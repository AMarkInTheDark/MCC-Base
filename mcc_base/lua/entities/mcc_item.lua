-- An MCC item lying in the world (dropped, or spilled from a full inventory). Press E to pick it up.
-- The item instance itself (with stack count, saved magazine, gear contents) lives on the server.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Item"
ENT.Spawnable = false

function ENT:SetupDataTables()
    self:NetworkVar("String", 0, "ItemID")
    self:NetworkVar("Int", 0, "Count")
end

if SERVER then
    function ENT:Initialize()
        local def = MCC.Items.Get(self:GetItemID())
        self:SetModel(def and def.model or "models/props_junk/cardboard_box004a.mdl")
        if not self:PhysicsInit(SOLID_VPHYSICS) then
            -- models without collision get a small box
            self:PhysicsInitBox(Vector(-6, -6, -3), Vector(6, 6, 3))
        end
        self:SetMoveType(MOVETYPE_VPHYSICS)
        self:SetSolid(SOLID_VPHYSICS)
        self:SetCollisionGroup(COLLISION_GROUP_WEAPON)
        self:SetUseType(SIMPLE_USE)
        local phys = self:GetPhysicsObject()
        if IsValid(phys) then phys:Wake() end
    end

    function ENT:SetItem(it)
        self.MCCItem = it
        self:SetItemID(it.id)
        self:SetCount(it.n or 1)
    end
end
