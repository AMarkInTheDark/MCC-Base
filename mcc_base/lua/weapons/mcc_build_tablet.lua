--[[
    MCC Builder Tablet.

    Based on Alydus's Fortification Builder Tablet (Steam Workshop 1461735659): the tablet model, its
    on-screen display and the viewmodel rendering (Clavus's SWEP Construction Kit code) come from it.
    Alydus: "Feel free to modify, but please leave appropriate credit. Do not reupload this (modified
    or original) to this workshop, however you may run modified versions on your servers."
    The placing logic (grid snapping, costs, piece health) is MCC's: lua/mcc/build/.

    Like Rust's building plan: right-click picks a piece, left-click builds, R rotates. Upgrading,
    repairing and removing are the Builder Hammer's (lua/weapons/mcc_hammer.lua).
]]

AddCSLuaFile()

SWEP.PrintName = "Builder Tablet"
SWEP.Author = "MCC (tablet by Alydus)"
SWEP.Instructions = "Right-click: pick a piece. Left-click: build. R: rotate. Use the Builder Hammer to upgrade."
SWEP.Category = "MCC"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Slot = 1
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.HoldType = "slam"
SWEP.ViewModelFOV = 65
SWEP.ViewModelFlip = false
SWEP.UseHands = false
SWEP.ViewModel = "models/weapons/v_grenade.mdl"
SWEP.WorldModel = "models/nirrti/tablet/tablet_sfm.mdl"
SWEP.ShowViewModel = true
SWEP.ShowWorldModel = false
SWEP.ViewModelBoneMods = {
    ["ValveBiped.Grenade_body"] = {scale = Vector(0.009, 0.009, 0.009), pos = Vector(0, 0, 0), angle = Angle(0, 0, 0)},
}
SWEP.VElements = {
    ["tablet"] = {type = "Model", model = "models/nirrti/tablet/tablet_sfm.mdl", bone = "ValveBiped.Bip01_R_Hand", rel = "",
        pos = Vector(5.714, 6.714, -3.636), angle = Angle(29, 100, -127.403), size = Vector(0.95, 0.95, 0.95),
        color = Color(255, 255, 255, 255), surpresslightning = false, material = "", skin = 1, bodygroup = {}},
}
SWEP.WElements = {
    ["tablet"] = {type = "Model", model = "models/nirrti/tablet/tablet_sfm.mdl", bone = "ValveBiped.Bip01_R_Hand", rel = "",
        pos = Vector(6.513, 5.714, -2.597), angle = Angle(26.882, 113.376, -127.403), size = Vector(0.82, 0.82, 0.82),
        color = Color(255, 255, 255, 255), surpresslightning = false, material = "", skin = 1, bodygroup = {}},
}

function SWEP:SetupDataTables()
    self:NetworkVar("String", 0, "Piece")
    self:NetworkVar("Float", 0, "Rot")
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    if CLIENT then
        self.VElements = table.Copy(self.VElements)
        self.WElements = table.Copy(self.WElements)
        self:CreateModels(self.VElements)
        self:CreateModels(self.WElements)
    end
end

function SWEP:Deploy()
    if SERVER and self:GetPiece() == "" and MCC.Build.Order[1] then self:SetPiece(MCC.Build.Order[1]) end
    if SERVER then self:GetOwner():EmitSound("npc/scanner/combat_scan4.wav", 60) end
    return true
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.3)
    if CLIENT then return end
    local ply = self:GetOwner()
    local ok, err = MCC.Build.Place(ply, self:GetPiece(), self:GetRot())
    if not ok and err then MCC.Inv.Notify(ply, err) end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if SERVER then MCC.Build.MenuFor(self:GetOwner()) end
end

function SWEP:Reload()
    if CLIENT then return end
    local ply = self:GetOwner()
    if not ply:KeyPressed(IN_RELOAD) then return end
    self:SetRot((self:GetRot() + 15) % 360)
    ply:EmitSound("buttons/lightswitch2.wav", 50)
end

function SWEP:GetViewModelPosition(pos, ang)
    self.SwayScale = 0
    self.BobScale = 0.1
    return pos, ang
end

function SWEP:Holster()
    if CLIENT and IsValid(self:GetOwner()) then
        local vm = self:GetOwner():GetViewModel()
        if IsValid(vm) then self:ResetBonePositions(vm) end
    end
    return true
end

function SWEP:OnRemove()
    self:Holster()
end

if CLIENT then
    local fontsMade
    local function Fonts()
        if fontsMade then return end
        fontsMade = true
        surface.CreateFont("MCC_Tablet_Title", {font = "Roboto Condensed", size = 60})
        surface.CreateFont("MCC_Tablet_Sub", {font = "Roboto Condensed", size = 52})
    end
    local wrenchMat, nextMat, shieldMat = Material("alydus/icons/wrench.png"), Material("alydus/icons/next.png"),
        Material("alydus/icons/shield.png")

    -- The tablet's screen: the selected piece, its cost and the controls.
    function SWEP:PostDrawViewModel(vm)
        if not IsValid(vm) then return end
        local bone = vm:LookupBone("ValveBiped.Bip01_R_Hand")
        local m = bone and vm:GetBoneMatrix(bone)
        if not m then return end
        Fonts()
        local pos, ang = m:GetTranslation(), m:GetAngles()
        ang:RotateAroundAxis(ang:Right(), 90)
        ang:RotateAroundAxis(ang:Right(), 20)
        ang:RotateAroundAxis(ang:Forward(), -11)
        ang:RotateAroundAxis(ang:Up(), 57)
        local piece = MCC.Build.Pieces[self:GetPiece()]
        cam.Start3D2D(pos - ang:Right() * 4 - ang:Forward() * 8.5, ang, 0.012)
            draw.SimpleText(piece and piece.name or "Builder", "MCC_Tablet_Title", 15, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(piece and MCC.Inv.CostText(MCC.Build.PlaceCost(piece)) or "Right-click to pick a piece", "MCC_Tablet_Sub",
                15, 60, Color(222, 182, 70), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            surface.SetDrawColor(255, 255, 255, 255)
            surface.SetMaterial(wrenchMat)
            surface.DrawTexturedRect(-250, 100, 40, 40)
            draw.SimpleText("LMB build  |  RMB pieces", "MCC_Tablet_Sub", 15, 120, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            surface.SetMaterial(nextMat)
            surface.DrawTexturedRect(-250, 160, 40, 40)
            draw.SimpleText("R rotate  |  Hammer to upgrade", "MCC_Tablet_Sub", 15, 180, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            surface.SetMaterial(shieldMat)
            surface.DrawTexturedRect(-250, 220, 40, 40)
            draw.SimpleText(#MCC.Build.Order .. " pieces", "MCC_Tablet_Sub", 15, 240, Color(100, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        cam.End3D2D()
    end

    -- SWEP Construction Kit rendering (from Alydus's tablet) --------------------------------------

    local function DrawElement(self, v, pos, ang)
        local model = v.modelEnt
        if v.type ~= "Model" or not IsValid(model) then return end
        model:SetPos(pos + ang:Forward() * v.pos.x + ang:Right() * v.pos.y + ang:Up() * v.pos.z)
        ang:RotateAroundAxis(ang:Up(), v.angle.y)
        ang:RotateAroundAxis(ang:Right(), v.angle.p)
        ang:RotateAroundAxis(ang:Forward(), v.angle.r)
        model:SetAngles(ang)
        local matrix = Matrix()
        matrix:Scale(v.size)
        model:EnableMatrix("RenderMultiply", matrix)
        if v.skin and v.skin ~= model:GetSkin() then model:SetSkin(v.skin) end
        render.SetColorModulation(v.color.r / 255, v.color.g / 255, v.color.b / 255)
        render.SetBlend(v.color.a / 255)
        model:DrawModel()
        render.SetBlend(1)
        render.SetColorModulation(1, 1, 1)
    end

    function SWEP:ViewModelDrawn()
        local vm = self:GetOwner():GetViewModel()
        if not IsValid(vm) or not self.VElements then return end
        self:UpdateBonePositions(vm)
        for _, v in pairs(self.VElements) do
            local pos, ang = self:GetBoneOrientation(v, vm)
            if pos then DrawElement(self, v, pos, ang) end
        end
    end

    function SWEP:DrawWorldModel()
        local ent = IsValid(self:GetOwner()) and self:GetOwner() or self
        if not IsValid(self:GetOwner()) then self:DrawModel() return end
        for _, v in pairs(self.WElements or {}) do
            local pos, ang = self:GetBoneOrientation(v, ent)
            if pos then DrawElement(self, v, pos, ang) end
        end
    end

    function SWEP:GetBoneOrientation(tab, ent)
        local bone = ent:LookupBone(tab.bone)
        if not bone then return end
        local m = ent:GetBoneMatrix(bone)
        if not m then return Vector(), Angle() end
        return m:GetTranslation(), m:GetAngles()
    end

    function SWEP:CreateModels(tab)
        for _, v in pairs(tab or {}) do
            if v.type == "Model" and v.model and not IsValid(v.modelEnt) and file.Exists(v.model, "GAME") then
                v.modelEnt = ClientsideModel(v.model, RENDERGROUP_VIEWMODEL)
                if IsValid(v.modelEnt) then
                    v.modelEnt:SetPos(self:GetPos())
                    v.modelEnt:SetAngles(self:GetAngles())
                    v.modelEnt:SetParent(self)
                    v.modelEnt:SetNoDraw(true)
                end
            end
        end
    end

    function SWEP:UpdateBonePositions(vm)
        for name, v in pairs(self.ViewModelBoneMods or {}) do
            local bone = vm:LookupBone(name)
            if bone then
                if vm:GetManipulateBoneScale(bone) ~= v.scale then vm:ManipulateBoneScale(bone, v.scale) end
                if vm:GetManipulateBoneAngles(bone) ~= v.angle then vm:ManipulateBoneAngles(bone, v.angle) end
                if vm:GetManipulateBonePosition(bone) ~= v.pos then vm:ManipulateBonePosition(bone, v.pos) end
            end
        end
    end

    function SWEP:ResetBonePositions(vm)
        if not vm:GetBoneCount() then return end
        for i = 0, vm:GetBoneCount() do
            vm:ManipulateBoneScale(i, Vector(1, 1, 1))
            vm:ManipulateBoneAngles(i, Angle(0, 0, 0))
            vm:ManipulateBonePosition(i, Vector(0, 0, 0))
        end
    end
end
