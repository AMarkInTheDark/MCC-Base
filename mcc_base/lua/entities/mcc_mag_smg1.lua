-- Spawn menu entry: Entities > MCC Magazines > SMG Magazine (45).
-- Spawning it puts a loaded smg magazine in the world as an MCC item (press E to pick it up).

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "SMG Magazine (45)"
ENT.Category = "MCC Magazines"
ENT.Spawnable = true
ENT.MCCItemID = "mag_smg1"

function ENT:SpawnFunction(ply, tr)
    return MCC.Inv.SpawnFromMenu(self.MCCItemID, ply, tr)
end
