-- Spawn menu entry: Entities > MCC Magazines > Pulse Magazine (30).
-- Spawning it puts a loaded pulse magazine in the world as an MCC item (press E to pick it up).

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Pulse Magazine (30)"
ENT.Category = "MCC Magazines"
ENT.Spawnable = true
ENT.MCCItemID = "mag_ar2"

function ENT:SpawnFunction(ply, tr)
    return MCC.Inv.SpawnFromMenu(self.MCCItemID, ply, tr)
end
