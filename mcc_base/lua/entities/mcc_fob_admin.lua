-- Spawn menu entry for an Admin FOB (Entities > MCC > Admin FOB): a FOB core owned by you, stocked
-- with mcc_fob_admin_stock of each building resource and outside the one-FOB-per-player limit. For testing.

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Admin FOB"
ENT.Category = "MCC"
ENT.Spawnable = true
ENT.AdminOnly = true

function ENT:SpawnFunction(ply, tr)
    if not tr.Hit then return end
    return MCC.FOB.SpawnAdmin(ply, tr.HitPos)
end

if SERVER then
    function ENT:Initialize() self:Remove() end -- never exists itself
end
