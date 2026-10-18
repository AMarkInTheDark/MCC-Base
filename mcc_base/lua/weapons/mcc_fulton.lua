--[[
    MCC Fulton Recovery Device: equipment for sending Extraction Crates up (lua/mcc/extract/).

    Carried in your rig, pockets or a special slot, each Fulton item is one charge; MCC Base mirrors them as
    this weapon's ammo, the way it does grenades, and takes the weapon away when you have none left.
    Aim at a crate with open sky above it and left-click.

    The viewmodel setup (a SLAM viewmodel with the SLAM scaled away, holding a package) follows kipper's
    MGSV Fulton Recovery System (Workshop 876405188); the element rendering is Clavus's SWEP Construction Kit.
]]

AddCSLuaFile()

SWEP.PrintName = "Fulton Recovery Device"
SWEP.Category = "MCC"
SWEP.Author = "MCC"
SWEP.Instructions = "Aim at an Extraction Crate with open sky above it and left-click to send it up."
SWEP.Spawnable = true
SWEP.AdminOnly = true
SWEP.Slot = 4
SWEP.SlotPos = 3
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = true

SWEP.UseHands = true
SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_package.mdl"
SWEP.ViewModelFOV = 72
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = 1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "mcc_fulton"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.ViewModelBoneMods = {
    ["Slam_base"] = {scale = Vector(0.009, 0.009, 0.009), pos = Vector(0, 0, 0), angle = Angle(0, 0, 0)},
    ["Detonator"] = {scale = Vector(0.009, 0.009, 0.009), pos = Vector(0, 0, 0), angle = Angle(0, 0, 0)},
}
SWEP.VElements = {
    ["package"] = {model = "models/weapons/w_package.mdl", bone = "Slam_base", pos = Vector(-3.164, -61.855, 23.315),
        angle = Angle(52.46, 11.729, 70.513), size = Vector(0.626, 0.626, 0.626)},
}
SWEP.WElements = {
    ["package"] = {model = "models/weapons/w_package.mdl", bone = "ValveBiped.Bip01_R_Hand", pos = Vector(4, 3, -1),
        angle = Angle(0, 0, 180), size = Vector(0.6, 0.6, 0.6)},
}

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
    self:SendWeaponAnim(ACT_SLAM_THROW_ND_DRAW)
    return true
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.6)
    if CLIENT then return end
    local ply = self:GetOwner()
    if not IsValid(ply) or self:Ammo1() <= 0 then return end
    local ok, err = MCC.Extract.UseFulton(ply)
    if not ok then
        if err then MCC.Inv.Notify(ply, err) end
        return
    end
    self:TakePrimaryAmmo(1) -- MCC Base takes one Fulton item out of your gear
    ply:SetAnimation(PLAYER_ATTACK1)
    self:SendWeaponAnim(ACT_SLAM_THROW_THROW_ND)
    self:SetNextPrimaryFire(CurTime() + 1.5)
end

function SWEP:SecondaryAttack() end
function SWEP:Reload() end

function SWEP:Holster()
    if CLIENT and IsValid(self:GetOwner()) then
        local vm = self:GetOwner():GetViewModel()
        if IsValid(vm) then self:ResetBonePositions(vm) end
    end
    return true
end

function SWEP:OnRemove()
    self:Holster()
    if CLIENT then
        for _, tab in ipairs({self.VElements, self.WElements}) do
            for _, v in pairs(tab or {}) do
                if IsValid(v.modelEnt) then v.modelEnt:Remove() end
            end
        end
    end
end

if CLIENT then
    -- SWEP Construction Kit rendering (Clavus), trimmed to models -------------------------------------

    local function Place(v, pos, ang)
        local m = v.modelEnt
        m:SetPos(pos + ang:Forward() * v.pos.x + ang:Right() * v.pos.y + ang:Up() * v.pos.z)
        ang:RotateAroundAxis(ang:Up(), v.angle.y)
        ang:RotateAroundAxis(ang:Right(), v.angle.p)
        ang:RotateAroundAxis(ang:Forward(), v.angle.r)
        m:SetAngles(ang)
        local matrix = Matrix()
        matrix:Scale(v.size)
        m:EnableMatrix("RenderMultiply", matrix)
        m:DrawModel()
    end

    local function BoneOrientation(ent, bone)
        local id = ent:LookupBone(bone)
        local m = id and ent:GetBoneMatrix(id)
        if not m then return nil end
        return m:GetTranslation(), m:GetAngles()
    end

    function SWEP:ViewModelDrawn()
        local vm = self:GetOwner():GetViewModel()
        if not IsValid(vm) then return end
        self:UpdateBonePositions(vm)
        for _, v in pairs(self.VElements or {}) do
            local pos, ang = BoneOrientation(vm, v.bone)
            if pos and IsValid(v.modelEnt) then Place(v, pos, ang) end
        end
    end

    function SWEP:DrawWorldModel()
        local owner = self:GetOwner()
        if not IsValid(owner) then
            self:DrawModel()
            return
        end
        for _, v in pairs(self.WElements or {}) do
            local pos, ang = BoneOrientation(owner, v.bone)
            if pos and IsValid(v.modelEnt) then Place(v, pos, ang) end
        end
    end

    function SWEP:CreateModels(tab)
        for _, v in pairs(tab or {}) do
            if v.model and not IsValid(v.modelEnt) and file.Exists(v.model, "GAME") then
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

    -- Bone scales don't carry down to child bones, so each bone gets its parents' scales multiplied in
    -- (the SCK workaround): scaling Slam_base hides the whole SLAM.
    function SWEP:UpdateBonePositions(vm)
        local count = vm:GetBoneCount()
        if not count or count <= 0 then return end
        local mods = self.ViewModelBoneMods
        for i = 0, count - 1 do
            local name = vm:GetBoneName(i)
            local own = mods[name]
            local s = own and Vector(own.scale.x, own.scale.y, own.scale.z) or Vector(1, 1, 1)
            local cur = vm:GetBoneParent(i)
            while cur and cur >= 0 do
                local pm = mods[vm:GetBoneName(cur)]
                if pm then s = Vector(s.x * pm.scale.x, s.y * pm.scale.y, s.z * pm.scale.z) end
                cur = vm:GetBoneParent(cur)
            end
            if vm:GetManipulateBoneScale(i) ~= s then vm:ManipulateBoneScale(i, s) end
        end
    end

    function SWEP:ResetBonePositions(vm)
        local count = vm:GetBoneCount()
        if not count then return end
        for i = 0, count - 1 do vm:ManipulateBoneScale(i, Vector(1, 1, 1)) end
    end
end
