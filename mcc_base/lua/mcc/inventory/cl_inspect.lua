-- Inspect window (right-click an item > Inspect): a draggable examine panel with a model you can
-- rotate (drag) and zoom (mouse wheel), stat bars and details, styled like the inventory.
-- Adapted from the Tarkov Inventory addon's inspect window, reading MCC item definitions, so it
-- works for items from any weapon pack.

local Inv = MCC.Inv

local COL = {
    bg = Color(16, 18, 18, 248), line = Color(70, 72, 68), head = Color(34, 36, 34),
    text = Color(214, 214, 204), dim = Color(128, 130, 122), bar = Color(138, 140, 134, 210),
    barBG = Color(40, 42, 40, 230), amber = Color(222, 182, 70), red = Color(150, 50, 46),
    view = Color(24, 26, 26, 255), btn = Color(30, 32, 30), btnHover = Color(54, 56, 52),
    good = Color(140, 200, 120), bad = Color(200, 110, 100),
}

-- HL2 weapons have no SWEP table to read; these are HL2's default skill values.
local HL2 = {
    weapon_pistol   = {dmg = 5,   auto = false, hold = "pistol"},
    weapon_357      = {dmg = 40,  auto = false, hold = "revolver"},
    weapon_smg1     = {dmg = 4,   auto = true,  hold = "smg"},
    weapon_ar2      = {dmg = 8,   auto = true,  hold = "ar2"},
    weapon_shotgun  = {dmg = 8,   pellets = 7, auto = false, hold = "shotgun"},
    weapon_crossbow = {dmg = 100, auto = false, hold = "crossbow"},
    weapon_frag     = {dmg = 150, hold = "grenade"},
    weapon_rpg      = {dmg = 100, hold = "rpg"},
    weapon_crowbar  = {dmg = 10,  hold = "melee"},
    weapon_stunstick = {dmg = 40, hold = "melee"},
}

local DESC = {
    weapon_pistol   = "Standard-issue semi-automatic sidearm. Light, accurate and forgiving.",
    weapon_357      = "Heavy revolver chambered in .357 Magnum. Slow to fire, devastating on impact.",
    weapon_smg1     = "Compact automatic weapon with an underbarrel grenade launcher.",
    weapon_ar2      = "Pulse rifle of Combine design. Its secondary fire launches a dark energy ball.",
    weapon_shotgun  = "Pump-action combat shotgun. Secondary fire discharges two shells at once.",
    weapon_crossbow = "Rebar crossbow with a zoom scope. One bolt at a time, quiet and lethal.",
    weapon_frag     = "Fragmentation grenade. Pull the pin and throw. Usable from your rig, pockets or special slots.",
    weapon_rpg      = "Laser-guided rocket launcher. Heavy, loud, and very final.",
    weapon_crowbar  = "A crowbar. Opens crates, and other things.",
    weapon_stunstick = "Combine riot baton with an electric charge.",
    item_healthkit  = "Portable first aid kit. Right-click > Use to restore health.",
    item_healthvial = "A small vial of medicine. Right-click > Use to restore a little health.",
    item_battery    = "Suit battery. Right-click > Use to recharge your armor.",
    pouch_secure    = "Secure container. What's inside stays with you when you die.",
    dogtag          = "Identification tag taken from a fallen operator.",
}

local SLOT_NAMES = {primary = "On sling / on back", holster = "Holster", melee = "Sheath",
    grenade = "Rig, pockets or special slots", rig = "Tactical rig", backpack = "Backpack", pouch = "Pouch"}

local FEED_NAMES = {mag = "Magazines", loose = "Loose rounds", tube = "Tube (round by round)",
    cylinder = "Cylinder (round by round)", single = "One at a time"}

local function Num(v) return tonumber(v) end

local function Location(loc)
    loc = loc or ""
    local key = string.match(loc, "^s:(%w+)$")
    if key then
        local s = Inv.Slots[key]
        if key:find("^pocket") then return "Pocket " .. key:sub(7) end
        if key:find("^special") then return "Special slot " .. key:sub(8) end
        return s and ("Equipped: " .. string.lower(s.label)) or key
    end
    local gear = string.match(loc, "^g:(%w+):")
    if gear then return Inv.Slots[gear] and (string.lower(Inv.Slots[gear].label):gsub("^%l", string.upper)) or gear end
    if string.find(loc, "^b") then return "On the body you're looting" end
    if loc == "c" or string.find(loc, "^c:") then return "In the container" end
    return "-"
end

local function Usable(loc)
    return Inv.IsUsableLoc(loc)
end

-- Weapon stats from HL2's values or the weapon's own SWEP table (any weapon pack).
local function WeaponStats(def)
    local st = {}
    for k, v in pairs(HL2[def.class or ""] or {}) do st[k] = v end
    local t = def.class and weapons.Get(def.class)
    if t then
        local p = istable(t.Primary) and t.Primary or {}
        local delay = Num(p.Delay)
        st.dmg = st.dmg or Num(p.Damage) or Num(t.Damage)
        st.pellets = st.pellets or Num(p.NumShots) or Num(p.NumBullets) or Num(t.NumBullets)
        st.rpm = st.rpm or Num(t.RPM) or Num(p.RPM) or ((delay and delay > 0) and 60 / delay or nil)
        if st.auto == nil then st.auto = p.Automatic end
        st.hold = st.hold or t.HoldType
        if isstring(t.Purpose) and t.Purpose ~= "" then st.purpose = t.Purpose end
    end
    return st
end

-- Names of registered weapons that fire this ammo type (or take this magazine).
local function UsedBy(field, value)
    local out = {}
    for _, d in pairs(MCC.Items.All()) do
        if d.kind == "weapon" and d.data[field] == value then out[#out + 1] = MCC.Items.DisplayName(d) end
    end
    table.sort(out)
    if #out > 8 then
        local extra = #out - 8
        for i = #out, 9, -1 do out[i] = nil end
        out[#out + 1] = "+" .. extra .. " more"
    end
    return out
end

-- Row helpers ---------------------------------------------------------------------------------

local function AddHead(scroll, text)
    local p = scroll:Add("DPanel")
    p:Dock(TOP)
    p:SetTall(24)
    p:DockMargin(10, 6, 10, 0)
    p.Paint = function(_, w, h)
        draw.SimpleText(string.upper(text), "MCC_InvSmall", 2, h - 4, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        surface.SetDrawColor(COL.line)
        surface.DrawLine(0, h - 1, w, h - 1)
    end
end

local function AddBar(scroll, label, value, frac, col)
    local p = scroll:Add("DPanel")
    p:Dock(TOP)
    p:SetTall(22)
    p:DockMargin(10, 3, 10, 0)
    p.Paint = function(_, w, h)
        surface.SetDrawColor(COL.barBG)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(col or COL.bar)
        surface.DrawRect(0, 0, w * math.Clamp(frac or 0, 0, 1), h)
        draw.SimpleText(string.upper(label), "MCC_InvSmall", 8, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(value), "MCC_InvLabel", w - 8, h / 2, color_white, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

local function AddRow(scroll, label, value, col)
    local p = scroll:Add("DPanel")
    p:Dock(TOP)
    p:SetTall(21)
    p:DockMargin(10, 2, 10, 0)
    p.Paint = function(_, w, h)
        draw.SimpleText(string.upper(label), "MCC_InvSmall", 2, h / 2, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(tostring(value), "MCC_InvLabel", w - 2, h / 2, col or COL.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

local function AddText(scroll, text, col)
    local l = scroll:Add("DLabel")
    l:Dock(TOP)
    l:DockMargin(10, 6, 10, 2)
    l:SetFont("MCC_InvLabel")
    l:SetTextColor(col or COL.dim)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:SetText(text)
end

-- "about 20 min ago" for a server os.time() stamp.
function Inv.AgoText(t)
    local s = math.max(0, os.time() - (tonumber(t) or 0))
    if s < 90 then return "Just now" end
    if s < 3600 then return string.format("About %d min ago", math.floor(s / 60 + 0.5)) end
    if s < 172800 then return string.format("About %d h ago", math.floor(s / 3600 + 0.5)) end
    return string.format("About %d days ago", math.floor(s / 86400 + 0.5))
end

-- A weapon (or whatever did the killing) by name.
local KILLER_CLASSES = {npc_grenade_frag = "Frag grenade", rpg_missile = "RPG rocket", crossbow_bolt = "Crossbow bolt",
    grenade_ar2 = "SMG grenade", prop_combine_ball = "Combine energy ball", entityflame = "Fire", env_fire = "Fire",
    prop_physics = "A thrown object", prop_ragdoll = "A thrown body", worldspawn = "A fall", npc_satchel = "Satchel charge",
    npc_tripmine = "Tripmine", env_explosion = "An explosion", trigger_hurt = "The environment"}
function Inv.WeaponText(class)
    if not isstring(class) then return "Unknown" end
    local id = MCC.Items.FromClass(class)
    local def = id and MCC.Items.Get(id)
    if def then return MCC.Items.DisplayName(def) end
    if KILLER_CLASSES[class] then return KILLER_CLASSES[class] end
    local stored = weapons and weapons.Get and weapons.Get(class)
    local phrase = language and language.GetPhrase or function(x) return x end
    if stored and isstring(stored.PrintName) then return phrase(stored.PrintName) end
    return phrase(class)
end

-- The stat list ----------------------------------------------------------------------------------

local function Fill(scroll, it, loc, def)
    local d = def.data or {}
    local desc = d.desc or DESC[it.id]

    if def.kind == "weapon" then
        local st = WeaponStats(def)
        local clip, max = it.d and it.d.clip, d.clip
        local key = string.match(loc or "", "^s:(%w+)$")
        if key and Inv.Slots[key] and Inv.Slots[key].weapon then -- equipped: read the live weapon
            local w = LocalPlayer():GetWeapon(def.class or "")
            if IsValid(w) and w:GetMaxClip1() > 0 then clip, max = w:Clip1(), w:GetMaxClip1() end
        end

        AddHead(scroll, "Combat")
        if max and max > 0 then
            clip = math.min(clip or 0, max)
            AddBar(scroll, d.feed == "mag" and "Magazine" or "Loaded", clip .. "/" .. max, clip / max, COL.amber)
        end
        if st.dmg then
            local total = st.dmg * (st.pellets or 1)
            AddBar(scroll, "Damage", st.pellets and (st.dmg .. " x" .. st.pellets) or math.Round(st.dmg, 1), total / 100)
        end
        if st.rpm then AddBar(scroll, "Fire rate", math.Round(st.rpm) .. " rpm", st.rpm / 1200) end
        if st.auto ~= nil then AddRow(scroll, "Type of fire", st.auto and "Full auto" or "Semi-auto") end
        if d.ammo then AddRow(scroll, "Caliber", d.ammo) end
        if d.feed then
            local feed = FEED_NAMES[d.feed] or d.feed
            if d.feed == "mag" and d.mag and MCC.Items.Get(d.mag) then feed = MCC.Items.DisplayName(MCC.Items.Get(d.mag)) end
            AddRow(scroll, "Reloads from", feed)
        end

        local nv = it.d and it.d.nv
        if nv then
            local shown = 0
            for name, value in pairs(nv) do
                if string.find(string.lower(name), "att", 1, true) and isstring(value) and value ~= "" then
                    if shown == 0 then AddHead(scroll, "Attachments") end
                    for part in string.gmatch(value, "[^;,]+") do
                        local slot, att = string.match(part, "^%s*([^=]+)=(.+)$")
                        AddRow(scroll, slot or name, att or part)
                        shown = shown + 1
                    end
                end
            end
        end
        AddHead(scroll, "Item")
        AddRow(scroll, "Slot", SLOT_NAMES[d.slot] or "Storage only")
        if st.hold then AddRow(scroll, "Hold type", st.hold) end
        desc = desc or st.purpose

    elseif def.kind == "mag" then
        local rounds, cap = Inv.MagRounds(it), d.cap or 0
        AddHead(scroll, "Magazine")
        AddBar(scroll, "Rounds", rounds .. "/" .. cap, cap > 0 and rounds / cap or 0, COL.amber)
        AddRow(scroll, "Caliber", d.ammo or "-")
        local fits = UsedBy("mag", it.id)
        if #fits > 0 then AddRow(scroll, "Fits", table.concat(fits, ", ")) end
        AddRow(scroll, "Usable here", Usable(loc) and "Yes" or "No (rig, pockets or special slots)",
            Usable(loc) and COL.good or COL.bad)
        desc = desc or "A detachable magazine. Load it by dragging loose rounds onto it, or right-click > Load."

    elseif def.kind == "ammo" then
        local n = it.n or 1
        AddHead(scroll, "Ammunition")
        AddBar(scroll, "Stack", n .. "/" .. def.maxStack, n / def.maxStack, COL.amber)
        AddRow(scroll, "Caliber", d.ammo or "-")
        local used = UsedBy("ammo", d.ammo)
        if #used > 0 then AddRow(scroll, "Used by", table.concat(used, ", ")) end
        AddRow(scroll, "Usable here", Usable(loc) and "Yes" or "No (rig, pockets or special slots)",
            Usable(loc) and COL.good or COL.bad)
        desc = desc or "Loose rounds. Load them into magazines, or into guns that take loose rounds."

    elseif def.kind == "gear" then
        local cells = Inv.Cells(it) or {}
        local total, used = 0, 0
        local tally, order = {}, {}
        for i, cell in ipairs(cells) do
            total = total + cell.w * cell.h
            for _, o in ipairs(it.cont and it.cont[i] or {}) do
                local ow, oh = Inv.Size(o)
                used = used + ow * oh
                if not o.hidden then
                    local name = MCC.Items.DisplayName(Inv.Def(o))
                    if not tally[name] then tally[name] = 0 order[#order + 1] = name end
                    tally[name] = tally[name] + (o.n or 1)
                end
            end
        end
        AddHead(scroll, "Storage")
        AddBar(scroll, "Capacity", used .. "/" .. total .. " cells", total > 0 and used / total or 0, COL.amber)
        AddRow(scroll, "Compartments", #cells)
        AddRow(scroll, "Worn in", SLOT_NAMES[d.slot] or "-")
        if d.keepOnDeath then AddRow(scroll, "On death", "You keep it", COL.good) end
        AddHead(scroll, "Contents")
        if #order == 0 then
            AddRow(scroll, "Empty", "-")
        else
            table.sort(order)
            for i, name in ipairs(order) do
                if i > 12 then AddRow(scroll, "...", "+" .. (#order - 12) .. " more") break end
                AddRow(scroll, name, "x" .. tally[name])
            end
        end

    elseif def.data.jmod and Inv.ResourceAmount then
        local amount, full = Inv.ResourceAmount(it), Inv.JModFull()
        AddHead(scroll, "JMod resource")
        AddBar(scroll, "Amount", amount .. "/" .. full, amount / full, COL.amber)
        AddRow(scroll, "Type", d.jmod)
        AddRow(scroll, "Dropped as", "A JMod box with this amount")
        desc = desc or "A JMod resource box. Drop it to use it with JMod machines, crates and the workbench."

    elseif def.kind == "consumable" then
        AddHead(scroll, "Effect")
        local cv = d.convar and GetConVar(d.convar)
        local amount = cv and cv:GetInt() or d.amount or 0
        if d.effect == "health" then
            AddBar(scroll, "Restores", "+" .. amount .. " HP", amount / 100, Color(150, 70, 66))
        elseif d.effect == "armor" then
            AddBar(scroll, "Recharges", "+" .. amount .. " armor", amount / 100, Color(80, 120, 160))
        end
        AddRow(scroll, "Used from", "Right-click > Use")
    end

    -- dogtags: whose, and how they died (Inv.DeathInfo)
    local dd = it.d
    if dd and (def.data.slot == "dogtag") and (dd.killer or dd.t or dd.weapon) then
        AddHead(scroll, "Dogtag")
        if dd.name then AddRow(scroll, "Name", dd.name) end
        if dd.faction then AddRow(scroll, "Faction", dd.faction) end
        if dd.t then AddRow(scroll, "Killed", Inv.AgoText(dd.t)) end
        if dd.killer then AddRow(scroll, "Killed by", dd.killer) end
        if dd.weapon then AddRow(scroll, "Weapon", Inv.WeaponText(dd.weapon)) end
    end

    -- expansions add sections: hook.Add("MCC_InspectFill", id, function(ui, it, loc, def) ui.head("X") ui.row("A", "b") end)
    hook.Run("MCC_InspectFill", {scroll = scroll,
        head = function(t) AddHead(scroll, t) end, row = function(l, v, c) AddRow(scroll, l, v, c) end,
        text = function(t, c) AddText(scroll, t, c) end, bar = function(l, v, f, c) AddBar(scroll, l, v, f, c) end}, it, loc, def)

    AddHead(scroll, "Details")
    AddRow(scroll, "Footprint", def.w .. " x " .. def.h .. " cells")
    AddRow(scroll, "Weight", string.format("%.2f kg", Inv.Weight(it)))
    local price = MCC.Items.Price(it.id)
    if price then AddRow(scroll, "Value", price .. " Supply") end
    AddRow(scroll, "Rarity", def.rarity or "common")
    AddRow(scroll, "Location", Location(loc))
    AddRow(scroll, "ID", it.id)

    if desc then
        AddHead(scroll, "Description")
        AddText(scroll, desc)
    end
end

-- The window ------------------------------------------------------------------------------------

local function StyledButton(parent, text, enabled, onClick)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetEnabled(enabled)
    b.Paint = function(self, w, h)
        surface.SetDrawColor(self:IsHovered() and enabled and COL.btnHover or COL.btn)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(string.upper(text), "MCC_InvLabel", w / 2, h / 2, enabled and COL.text or Color(80, 82, 78),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = onClick
    return b
end

function Inv.OpenInspect(it, loc)
    if IsValid(Inv.Inspect) then Inv.Inspect:Remove() end
    local def = Inv.Def(it)
    if not def then return end

    local W = math.floor(math.Clamp(ScrW() * 0.3, 420, 620))
    local H = math.floor(ScrH() * 0.84)
    local title = string.upper(MCC.Items.DisplayName(def))

    local f = vgui.Create("DFrame")
    Inv.Inspect = f
    f:SetSize(W, H)
    f:Center()
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetSizable(false)
    f:SetDraggable(true)
    f:SetScreenLock(true)
    f:DockPadding(0, 28, 0, 0)
    f:MakePopup()
    f:SetKeyboardInputEnabled(true)
    MCC.UI.Escapable(f)

    local modelH = math.floor(H * 0.30)
    f.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.head)
        surface.DrawRect(0, 0, w, 28)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        surface.SetDrawColor(COL.view)
        surface.DrawRect(1, 29, w - 2, modelH)
        -- magnifier glyph
        surface.DrawCircle(15, 13, 6, 200, 200, 190, 255)
        surface.SetDrawColor(200, 200, 190, 255)
        surface.DrawLine(19, 17, 24, 22)
        draw.SimpleText("EXAMINE: " .. title, "MCC_InvLabel", 34, 14, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.format("%.3f KG", Inv.Weight(it)), "MCC_InvLabel", w - 40, 14, COL.text,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- ESC, the inventory key and Tab are handled in cl_inventory.lua, wherever focus is

    local x = vgui.Create("DButton", f)
    x:SetText("")
    x:SetSize(26, 22)
    x:SetPos(W - 32, 3)
    x.Paint = function(self, w, h)
        surface.SetDrawColor(self:IsHovered() and COL.red or Color(80, 40, 38))
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("x", "MCC_InvLabel", w / 2, h / 2 - 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    x.DoClick = function() f:Remove() end

    -- rotating model
    local mp = vgui.Create("DModelPanel", f)
    mp:Dock(TOP)
    mp:DockMargin(1, 1, 1, 0)
    mp:SetTall(modelH)
    mp:SetFOV(30)
    mp:SetModel(def.model or "models/error.mdl")
    mp:SetCursor("sizeall")
    mp.zoom, mp.pitch = 1, 0

    local ent = mp:GetEntity()
    mp.ctr, mp.radius, mp.yaw = vector_origin, 20, 0
    if IsValid(ent) then
        local mn, mx = ent:GetRenderBounds()
        local sz = mx - mn
        mp.ctr = (mn + mx) / 2
        mp.radius = math.max(sz:Length() / 2, 1)
        if def.kind == "weapon" and sz.y > sz.x then mp.yaw = -90 end -- long axis sideways
    end
    mp.startYaw = mp.yaw

    function mp:LayoutEntity(e)
        if not self.dragging and not self.touched then self.yaw = self.yaw + FrameTime() * 18 end
        local ang = Angle(self.pitch, self.yaw, 0)
        e:SetAngles(ang)
        local c = Vector(self.ctr)
        c:Rotate(ang)
        e:SetPos(-c) -- spin around the model's centre rather than its origin
        local dist = self.radius * 1.15 / math.tan(math.rad(15)) * math.max(1, self:GetWide() / self:GetTall()) / self.zoom
        if def.kind == "weapon" then
            self:SetCamPos(Vector(0, -dist, 0))
            self:SetLookAng(Angle(0, 90, 0))
        else
            local a = Angle(25, 225, 0)
            self:SetCamPos(-a:Forward() * dist)
            self:SetLookAng(a)
        end
    end
    function mp:OnMousePressed(k)
        if k ~= MOUSE_LEFT then return end
        self.dragging, self.touched = true, true
        self.lx, self.ly = gui.MouseX(), gui.MouseY()
        self:MouseCapture(true)
    end
    function mp:OnMouseReleased()
        self.dragging = false
        self:MouseCapture(false)
    end
    function mp:OnCursorMoved()
        if not self.dragging then return end
        local mx, my = gui.MouseX(), gui.MouseY()
        self.yaw = self.yaw + (mx - self.lx) * 0.6
        self.pitch = math.Clamp(self.pitch + (my - self.ly) * 0.4, -80, 80)
        self.lx, self.ly = mx, my
    end
    function mp:OnMouseWheeled(delta)
        self.touched = true
        self.zoom = math.Clamp(self.zoom * (1 + delta * 0.12), 0.5, 3.5)
        return true
    end
    function mp:DoDoubleClick()
        self.yaw, self.pitch, self.zoom, self.touched = self.startYaw, 0, 1, false
    end
    mp.DoClick = function() end

    -- actions
    local bar = vgui.Create("DPanel", f)
    bar:Dock(TOP)
    bar:SetTall(40)
    bar:DockPadding(10, 6, 10, 6)
    bar.Paint = function(_, w, h)
        surface.SetDrawColor(COL.line)
        surface.DrawLine(0, h - 1, w, h - 1)
    end

    local mine = string.find(loc or "", "^[sg]:") ~= nil
    local function Act(a)
        Inv.Act({a = a, u = it.u})
        f:Remove()
    end
    local firstLabel, firstAction, firstOn = def.data.useLabel or "Use", "use", mine and def.kind == "consumable"
    if def.kind == "mag" then
        firstLabel, firstAction, firstOn = "Load", "load", mine
    elseif def.kind == "weapon" and (def.data.clip or 0) > 0 then
        firstLabel, firstAction, firstOn = "Load", "loadgun", mine
    end
    local third = math.floor((W - 20) / 3) - 4
    local use = StyledButton(bar, firstLabel, firstOn and true or false, function() Act(firstAction) end)
    use:Dock(LEFT)
    use:SetWide(third)
    local quick = StyledButton(bar, "Quick move", true, function() Act("quick") end)
    quick:Dock(LEFT)
    quick:DockMargin(6, 0, 0, 0)
    quick:SetWide(third)
    local drop = StyledButton(bar, "Drop", true, function() Act("drop") end)
    drop:Dock(FILL)
    drop:DockMargin(6, 0, 0, 0)

    -- stats
    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL)
    scroll:DockMargin(0, 0, 0, 6)
    local vbar = scroll:GetVBar()
    vbar:SetWide(6)
    vbar.Paint = function() end
    vbar.btnUp.Paint, vbar.btnDown.Paint = function() end, function() end
    vbar.btnGrip.Paint = function(_, w, h)
        surface.SetDrawColor(COL.line)
        surface.DrawRect(0, 0, w, h)
    end

    Fill(scroll, it, loc, def)
end
