-- FOBs, client side: the core menu, the zone boundary and range bubble, the zone banner and prop health.

local F = MCC.FOB

local COL = {
    bg = Color(16, 18, 18, 248), head = Color(34, 36, 34), line = Color(70, 72, 68), text = Color(214, 214, 204),
    dim = Color(128, 130, 122), barBG = Color(40, 42, 40, 230), hp = Color(150, 70, 66), store = Color(222, 182, 70),
    food = Color(120, 160, 90), btn = Color(30, 32, 30), btnHover = Color(54, 56, 52), red = Color(150, 50, 46),
    bad = Color(220, 90, 80), good = Color(130, 200, 120),
}

local cvRing = CreateClientConVar("mcc_fob_ring", "1", true, false, "Show FOB zone boundaries on the ground.")

local fonts
local function Fonts()
    if fonts then return end
    fonts = true
    for name, f in pairs({MCC_FobTitle = {20, 700}, MCC_FobLabel = {15, 700}, MCC_FobSmall = {13, 600}}) do
        surface.CreateFont(name, {font = "Bahnschrift", size = f[1], weight = f[2], extended = true})
    end
end

local function Act(core, a, extra)
    local t = extra or {}
    t.a, t.e = a, core:EntIndex()
    MCC.Net.Send("fob_act", t)
end

local function Button(parent, text, enabled, fn)
    local b = vgui.Create("DButton", parent)
    b:SetText("")
    b:SetEnabled(enabled)
    b.Paint = function(self, w, h)
        surface.SetDrawColor(self:IsHovered() and enabled and COL.btnHover or COL.btn)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText(string.upper(text), "MCC_FobLabel", w / 2, h / 2, enabled and COL.text or Color(80, 82, 78),
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    b.DoClick = fn
    return b
end

local function Bar(parent, label, getValue, getMax, col)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(24)
    p:DockMargin(12, 4, 12, 0)
    p.Paint = function(_, w, h)
        local v, m = getValue(), math.max(getMax(), 1)
        surface.SetDrawColor(COL.barBG)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(col)
        surface.DrawRect(0, 0, w * math.Clamp(v / m, 0, 1), h)
        draw.SimpleText(string.upper(label), "MCC_FobSmall", 8, h / 2, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(math.floor(v) .. " / " .. math.floor(m), "MCC_FobLabel", w - 8, h / 2, color_white,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

local function Row(parent, label, value, col)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(20)
    p:DockMargin(12, 2, 12, 0)
    p.Paint = function(_, w, h)
        draw.SimpleText(string.upper(label), "MCC_FobSmall", 0, h / 2, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(isfunction(value) and value() or tostring(value), "MCC_FobLabel", w, h / 2,
            isfunction(col) and col() or col or COL.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    return p
end

local function Header(parent, text)
    local p = vgui.Create("DPanel", parent)
    p:Dock(TOP)
    p:SetTall(24)
    p:DockMargin(12, 10, 12, 2)
    p.Paint = function(_, w, h)
        draw.SimpleText(string.upper(text), "MCC_FobSmall", 0, h - 4, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
        surface.SetDrawColor(COL.line)
        surface.DrawLine(0, h - 1, w, h - 1)
    end
end

local function Duration(sec)
    sec = math.max(0, math.floor(sec))
    if sec >= 3600 then return string.format("%dh %02dm", sec / 3600, (sec % 3600) / 60) end
    return string.format("%d:%02d", sec / 60, sec % 60)
end

local function CostText(cost)
    return MCC.Inv.CostText and MCC.Inv.CostText(cost) or ""
end

-- The core menu -------------------------------------------------------------------------------------

function F.OpenMenuUI(data)
    Fonts()
    local core = Entity(data.e or -1)
    if not IsValid(core) then return end
    local old = F.MenuFrame
    local x, y
    if IsValid(old) then
        x, y = old:GetPos()
        old:Remove()
    end
    local opened = CurTime()

    local f = vgui.Create("DFrame")
    F.MenuFrame = f
    f:SetSize(460, math.min(680, ScrH() - 40))
    if x then f:SetPos(x, y) else f:Center() end
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:SetDraggable(true)
    f:DockPadding(0, 34, 0, 10)
    f:MakePopup()
    MCC.UI.Escapable(f)
    f.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.head)
        surface.DrawRect(0, 0, w, 30)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        local title = IsValid(core) and (core:GetAbandoned() and "ABANDONED FOB" or (core:GetOwnerName() .. "'S FOB")) or "FOB"
        if data.admin then title = title .. "  [ADMIN]" end
        draw.SimpleText(string.upper(title), "MCC_FobTitle", 12, 15, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(string.upper(data.tierInfo.name or "") .. "  |  TIER " .. (data.tier or 1), "MCC_FobSmall",
            w - 42, 15, COL.dim, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    function f:Think()
        if not IsValid(core) or LocalPlayer():GetPos():Distance(core:GetPos()) > 260 then self:Remove() end
    end
    function f:OnKeyCodePressed(key)
        if key == KEY_ESCAPE or key == KEY_E or key == KEY_TAB then self:Remove() end
    end
    local close = vgui.Create("DButton", f)
    close:SetText("")
    close:SetSize(26, 22)
    close:SetPos(460 - 32, 4)
    close.Paint = function(self, w, h)
        surface.SetDrawColor(self:IsHovered() and COL.red or Color(80, 40, 38))
        surface.DrawRect(0, 0, w, h)
        draw.SimpleText("x", "MCC_FobLabel", w / 2, h / 2 - 1, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    close.DoClick = function() f:Remove() end

    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL)

    Header(scroll, "Status")
    Bar(scroll, "Health", function() return IsValid(core) and core:GetHP() or 0 end,
        function() return IsValid(core) and core:GetMaxHP() or 1 end, COL.hp)
    Bar(scroll, "Stash space (cells)", function() return IsValid(core) and core:GetNWInt("MCCStashUsed", 0) or 0 end,
        function() return IsValid(core) and core:GetNWInt("MCCStashCells", 1) or 1 end, COL.store)
    Row(scroll, "Resources in the stash", function() return IsValid(core) and math.floor(core:GetStored()) .. " units" or "-" end)
    Row(scroll, "Food", function() return IsValid(core) and math.floor(core:GetFood()) .. " points" or "-" end)
    Row(scroll, "Props", function() return (IsValid(core) and core:GetPropCount() or 0) .. " / " .. (data.tierInfo.maxProps or 0) end)
    Row(scroll, "Zone", math.floor((data.tierInfo.radius or 0) * 0.01905) .. " m")

    -- upkeep, per resource
    Header(scroll, "Upkeep every " .. Duration(data.interval or 1800))
    Row(scroll, "Next payment", function() return Duration((data.nextBill or 0) - (CurTime() - opened)) end)
    local needs = {}
    for res, n in pairs(data.needs or {}) do needs[#needs + 1] = {res, n} end
    table.sort(needs, function(a, b) return a[1] < b[1] end)
    if #needs == 0 then Row(scroll, "Nothing to pay", "-") end
    for _, nd in ipairs(needs) do
        local res, n = nd[1], nd[2]
        local have = data.store and data.store[res] or 0
        local unpaid = data.unpaid and data.unpaid[res]
        local periods = n > 0 and math.floor(have / n) or 0
        local lasts = n > 0 and Duration(periods * (data.interval or 1800) + (data.nextBill or 0)) or "-"
        Row(scroll, res, string.format("%d per payment  |  %d stored  |  %s", math.ceil(n), have,
            unpaid and "UNPAID: DECAYING" or ("lasts " .. lasts)), unpaid and COL.bad or COL.text)
    end

    -- actions
    local claiming = IsValid(core) and core:GetClaimEnds() > CurTime()
    local bar = vgui.Create("DPanel", scroll)
    bar:Dock(TOP)
    bar:SetTall(40)
    bar:DockMargin(12, 10, 12, 0)
    bar.Paint = function() end
    if IsValid(core) and core:GetAbandoned() then
        local b = Button(bar, claiming and "Claiming..." or "Claim FOB", not claiming, function() Act(core, "claim") end)
        b:Dock(FILL)
        Row(scroll, "Claim", "Stay within reach for " .. MCC.Config.Get("fob_claim_time") .. "s")
    else
        local stash = Button(bar, "Open stash", data.stash, function()
            Act(core, "stash")
            f:Remove()
        end)
        stash:Dock(LEFT)
        stash:SetWide(132)
        local dep = Button(bar, "Deposit all", data.mine, function() Act(core, "deposit") end)
        dep:Dock(LEFT)
        dep:SetWide(132)
        dep:DockMargin(8, 0, 0, 0)
        local up = Button(bar, data.next and "Upgrade tier" or "Max tier", data.next ~= nil and data.mine,
            function() Act(core, "upgrade") end)
        up:Dock(FILL)
        up:DockMargin(8, 0, 0, 0)
        if data.next then
            Row(scroll, "Upgrade to " .. (data.next.name or ""), CostText(data.next.upgradeCost))
        end
    end

    -- what the stash holds
    Header(scroll, "Resources in the stash")
    local stored = {}
    for res, n in pairs(data.store or {}) do stored[#stored + 1] = {res, n} end
    table.sort(stored, function(a, b) return a[1] < b[1] end)
    if #stored == 0 then Row(scroll, "None", "put JMod resources in the stash") end
    for _, s in ipairs(stored) do
        local food = data.food and data.food[s[1]]
        Row(scroll, s[1], math.floor(s[2]) .. (food and ("  (" .. math.floor(s[2] * food) .. " food)") or ""))
    end
    local l = vgui.Create("DLabel", scroll)
    l:Dock(TOP)
    l:DockMargin(12, 6, 12, 0)
    l:SetFont("MCC_FobSmall")
    l:SetTextColor(COL.dim)
    l:SetWrap(true)
    l:SetAutoStretchVertical(true)
    l:SetText("The stash holds anything you drag into it (E on the core). Upkeep and upgrades are paid from the JMod "
        .. "resource boxes in it: drag them in, push JMod boxes into the core, or Deposit all to put in every one you carry. "
        .. "Taken from JMod: " .. table.concat(data.accepts or {}, ", ") .. ".")

    -- members
    if not (IsValid(core) and core:GetAbandoned()) then
        Header(scroll, "Members")
        Row(scroll, "Owner", IsValid(core) and core:GetOwnerName() or "")
        for _, m in ipairs(data.members or {}) do
            local p = vgui.Create("DPanel", scroll)
            p:Dock(TOP)
            p:SetTall(24)
            p:DockMargin(12, 2, 12, 0)
            p.Paint = function(_, w, h)
                draw.SimpleText(m.name, "MCC_FobLabel", 0, h / 2, m.online and COL.text or COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end
            local mineRow = m.sid == LocalPlayer():SteamID64()
            if data.owner or mineRow then
                local k = Button(p, mineRow and "Leave" or "Remove", true, function() Act(core, "kick", {sid = m.sid}) end)
                k:Dock(RIGHT)
                k:SetWide(90)
            end
        end
        if data.owner then
            local add = vgui.Create("DComboBox", scroll)
            add:Dock(TOP)
            add:DockMargin(12, 6, 12, 0)
            add:SetTall(26)
            add:SetValue("Add a member...")
            for _, p in ipairs(player.GetAll()) do
                if p ~= LocalPlayer() then add:AddChoice(p:Nick(), p:SteamID64()) end
            end
            add.OnSelect = function(_, _, _, sid) Act(core, "add", {sid = sid}) end
        end
    end

    if data.owner then
        local pack = vgui.Create("DPanel", scroll)
        pack:Dock(TOP)
        pack:SetTall(36)
        pack:DockMargin(12, 14, 12, 0)
        pack.Paint = function() end
        local b = Button(pack, "Pack up (kit back, stash spills out)", true, function()
            MCC.UI.Escapable(Derma_Query("Pack up the FOB? Everything in its stash drops on the ground; your pieces stay as ordinary props.",
                "Pack up", "Pack up", function() Act(core, "packup") f:Remove() end, "Cancel"))
        end)
        b:Dock(FILL)
    end
end

MCC.Net.Receive("fob_menu", function(data) F.OpenMenuUI(data) end)

-- Zone boundary ring and the range bubble ------------------------------------------------------------

local bubble = false
concommand.Add("mcc_fob_range", function()
    bubble = not bubble
    chat.AddText(Color(222, 182, 70), "[MCC] ", color_white, bubble
        and "FOB range bubbles on. The outline at your crosshair is a new FOB's tier 1 range."
        or "FOB range bubbles off.")
end, nil, "Toggles see-through bubbles showing every FOB's range, plus a tier 1 preview where you aim.")

local function Bubble(pos, r, col)
    render.SetColorMaterial()
    render.DrawSphere(pos, r, 40, 40, col)                                -- outside
    render.DrawSphere(pos, -r, 40, 40, Color(col.r, col.g, col.b, col.a * 0.6)) -- inside, seen from within
    render.DrawWireframeSphere(pos, r, 20, 20, Color(col.r, col.g, col.b, math.min(255, col.a * 4)), true)
end

local function ZoneColor(core, lp, alpha)
    if core:GetAbandoned() then return Color(160, 160, 150, alpha) end
    return F.IsMember(core, lp) and Color(110, 190, 120, alpha) or Color(220, 80, 70, alpha)
end

hook.Add("PostDrawTranslucentRenderables", "MCC_FOBRing", function(depth, sky)
    if sky then return end
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    local me = lp:GetPos()

    if bubble then
        for _, core in ipairs(F.All()) do
            if core:GetRadius() > 0 then Bubble(core:GetPos(), core:GetRadius(), ZoneColor(core, lp, 18)) end
        end
        local tr = lp:GetEyeTrace()
        if tr.Hit then
            local r = GetGlobalFloat("MCCFobTier1Radius", (F.Tiers[1] and F.Tiers[1].radius) or 1024)
            render.DrawWireframeSphere(tr.HitPos, r, 24, 24, Color(222, 182, 70, 90), true)
        end
    end

    if not cvRing:GetBool() then return end
    for _, core in ipairs(F.All()) do
        local r = core:GetRadius()
        local c = core:GetPos()
        local d = me:Distance(c)
        if r > 0 and d < r + 600 and d > r - 600 then
            local col = ZoneColor(core, lp, math.Clamp(255 - math.abs(d - r) / 600 * 255, 0, 160))
            render.SetColorMaterial()
            local segs, z, prev = 96, me.z + 4, nil
            for i = 0, segs do
                local a = i / segs * math.pi * 2
                local p = Vector(c.x + math.cos(a) * r, c.y + math.sin(a) * r, z)
                if prev then render.DrawBeam(prev, p, 3, 0, 1, col) end
                prev = p
            end
        end
    end
end)

-- HUD: zone banner and prop health --------------------------------------------------------------------

hook.Add("HUDPaint", "MCC_FOBHud", function()
    local lp = LocalPlayer()
    if not IsValid(lp) then return end
    Fonts()
    local core = F.At(lp:GetPos())
    if IsValid(core) then
        local text
        if core:GetAbandoned() then
            text = "ABANDONED FOB"
        elseif F.IsMember(core, lp) then
            text = "YOUR FOB  |  " .. string.upper(core:GetNWString("MCCTierName", ""))
        else
            text = string.upper(core:GetOwnerName()) .. "'S FOB"
        end
        draw.SimpleTextOutlined(text, "MCC_FobLabel", ScrW() / 2, 18, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP,
            1, Color(0, 0, 0, 200))
        if core:GetNWBool("MCCDecaying") and F.IsMember(core, lp) then
            draw.SimpleTextOutlined("UPKEEP UNPAID (" .. string.upper(core:GetNWString("MCCUnpaid")) .. "): DECAYING",
                "MCC_FobSmall", ScrW() / 2, 38, COL.bad, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
        end
        if core:GetClaimEnds() > CurTime() then
            local frac = 1 - (core:GetClaimEnds() - CurTime()) / math.max(MCC.Config.Get("fob_claim_time"), 0.01)
            local w, x, y = 240, ScrW() / 2 - 120, ScrH() * 0.62
            surface.SetDrawColor(COL.barBG)
            surface.DrawRect(x, y, w, 10)
            surface.SetDrawColor(COL.store)
            surface.DrawRect(x, y, w * math.Clamp(frac, 0, 1), 10)
            draw.SimpleTextOutlined("CLAIMING FOB", "MCC_FobSmall", ScrW() / 2, y - 4, COL.text, TEXT_ALIGN_CENTER,
                TEXT_ALIGN_BOTTOM, 1, Color(0, 0, 0, 200))
        end
    end

    -- health of the FOB prop (or core) you're looking at
    local tr = lp:GetEyeTrace()
    local e = tr.Entity
    if not IsValid(e) or tr.HitPos:Distance(lp:GetShootPos()) > 400 then return end
    local hp, max
    if e:GetClass() == F.CLASS then
        hp, max = e:GetHP(), e:GetMaxHP()
    elseif e:GetNWInt("MCCFobMaxHP", 0) > 0 then
        hp, max = e:GetNWInt("MCCFobHP", 0), e:GetNWInt("MCCFobMaxHP", 0)
    end
    if not max then return end
    local w, x, y = 120, ScrW() / 2 - 60, ScrH() / 2 + 28
    surface.SetDrawColor(COL.barBG)
    surface.DrawRect(x, y, w, 8)
    surface.SetDrawColor(COL.hp)
    surface.DrawRect(x, y, w * math.Clamp(hp / math.max(max, 1), 0, 1), 8)
    local tier = e:GetNWString("MCCTierName", "")
    draw.SimpleTextOutlined((tier ~= "" and (string.upper(tier) .. "  ") or "") .. math.ceil(hp) .. " / " .. math.ceil(max),
        "MCC_FobSmall", ScrW() / 2, y + 10, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    if e:GetClass() == F.CLASS and tr.HitPos:Distance(lp:GetShootPos()) < 140 then
        draw.SimpleTextOutlined(F.CanModify(e, lp) and "[E]  OPEN STASH" or "[E]  FOB MENU", "MCC_FobLabel",
            ScrW() / 2, y + 28, COL.store, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    end
end)
