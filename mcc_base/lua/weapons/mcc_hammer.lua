--[[
    MCC Builder Hammer: Rust's hammer for the pieces you build with the Builder Tablet.

    Left-click: swing. Hitting a damaged piece in your FOB repairs part of it (mcc_build_hammer_repair of
    its max health per hit), paid from the JMod resources you carry; not within mcc_build_repair_delay
    seconds of it being damaged. Anything else takes a light blow.
    Right-click a piece: its menu (upgrade to a higher tier, repair fully, remove for a refund).

    JMod has no hammer model, so it uses the HL2 crowbar until there's one:
    mcc_build_hammer_viewmodel / mcc_build_hammer_worldmodel swap the models.
]]

AddCSLuaFile()

SWEP.PrintName = "Builder Hammer"
SWEP.Author = "MCC"
SWEP.Instructions = "Right-click a built piece: upgrade, repair, remove. Left-click: hit a damaged piece to repair it."
SWEP.Category = "MCC"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.Slot = 0
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.UseHands = true
SWEP.ViewModelFOV = 54
SWEP.HoldType = "melee"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"
SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local REACH = 80
local SWING_DELAY = 0.6
local BLOW_DAMAGE = 10

-- The models from the settings, when they exist.
function SWEP:ApplyModels()
    local vm, wm = MCC.Config.Get("build_hammer_viewmodel"), MCC.Config.Get("build_hammer_worldmodel")
    if isstring(vm) and vm ~= "" and util.IsValidModel(vm) then self.ViewModel = vm end
    if isstring(wm) and wm ~= "" and util.IsValidModel(wm) then
        self.WorldModel = wm
        self:SetModel(wm)
    end
end

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self:ApplyModels()
end

function SWEP:Deploy()
    self:ApplyModels()
    self:SendWeaponAnim(ACT_VM_DRAW)
    return true
end

-- What the swing hits: a straight line, then a small hull so near misses still connect.
function SWEP:SwingTrace()
    local owner = self:GetOwner()
    local start = owner:GetShootPos()
    local stop = start + owner:GetAimVector() * REACH
    local tr = util.TraceLine({start = start, endpos = stop, filter = owner, mask = MASK_SHOT_HULL})
    if not tr.Hit then
        tr = util.TraceHull({start = start, endpos = stop, filter = owner, mask = MASK_SHOT_HULL,
            mins = Vector(-8, -8, -8), maxs = Vector(8, 8, 8)})
    end
    return tr
end

-- A piece of a FOB the player may work on.
local function OwnPiece(ply, ent)
    if not IsValid(ent) or ent:GetNWString("MCCPiece", "") == "" then return false end
    local core = ent:GetNWEntity("MCCFob")
    return not IsValid(core) or MCC.FOB.CanModify(core, ply)
end

function SWEP:PrimaryAttack()
    local owner = self:GetOwner()
    if not IsValid(owner) then return end
    self:SetNextPrimaryFire(CurTime() + SWING_DELAY)
    owner:SetAnimation(PLAYER_ATTACK1)
    if owner.LagCompensation then owner:LagCompensation(true) end
    local tr = self:SwingTrace()
    if owner.LagCompensation then owner:LagCompensation(false) end
    self:SendWeaponAnim(tr.Hit and ACT_VM_HITCENTER or ACT_VM_MISSCENTER)
    if not tr.Hit then
        self:EmitSound("Weapon_Crowbar.Single")
        return
    end
    if CLIENT then return end

    local ent = tr.Entity
    if OwnPiece(owner, ent) then
        local ok, err = MCC.Build.HammerHit(owner, ent)
        if ok then
            ent:EmitSound("physics/wood/wood_plank_impact_hard" .. math.random(1, 5) .. ".wav")
        else
            ent:EmitSound("physics/wood/wood_solid_impact_soft" .. math.random(1, 3) .. ".wav")
            if err and err ~= "It isn't damaged" then MCC.Inv.Notify(owner, err) end
        end
        return
    end

    self:EmitSound(IsValid(ent) and "Weapon_Crowbar.Melee_Hit" or "Weapon_Crowbar.Melee_HitWorld")
    if IsValid(ent) then
        local dmg = DamageInfo()
        dmg:SetDamage(BLOW_DAMAGE)
        dmg:SetDamageType(DMG_CLUB)
        dmg:SetAttacker(owner)
        dmg:SetInflictor(self)
        dmg:SetDamagePosition(tr.HitPos)
        dmg:SetDamageForce(owner:GetAimVector() * 2000)
        ent:TakeDamageInfo(dmg)
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.3)
    if CLIENT then return end
    local owner = self:GetOwner()
    local ok, err = MCC.Build.PieceMenu(owner)
    if not ok then MCC.Inv.Notify(owner, err == "Look at a built piece" and "Aim at a piece you built to upgrade it" or err) end
end

function SWEP:Reload() end

if CLIENT then
    function SWEP:DrawHUD()
        local tr = LocalPlayer():GetEyeTrace()
        local ent = tr.Entity
        if not OwnPiece(LocalPlayer(), ent) or tr.HitPos:Distance(LocalPlayer():GetShootPos()) > 400 then return end
        local hp, max = ent:GetNWInt("MCCFobHP", 0), ent:GetNWInt("MCCFobMaxHP", 0)
        local text = "RMB  upgrade / repair / remove"
        if max > 0 and hp < max then text = "LMB  repair     " .. text end
        draw.SimpleTextOutlined(text, "DermaDefaultBold", ScrW() / 2, ScrH() / 2 + 70, Color(222, 182, 70),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    end
end
