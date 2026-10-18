-- Spawn menu entry: Entities > MCC Magazines > Pistol Magazine (18).
-- Spawning it puts a loaded pistol magazine in the world as an MCC item (press E to pick it up).

AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Pistol Magazine (18)"
ENT.Category = "MCC Magazines"
ENT.Spawnable = true
ENT.MCCItemID = "mag_pistol"

function ENT:SpawnFunction(ply, tr)
    return MCC.Inv.SpawnFromMenu(self.MCCItemID, ply, tr)
end
