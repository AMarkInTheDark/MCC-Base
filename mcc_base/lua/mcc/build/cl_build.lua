-- Building, client side: the ghost preview, what's wrong with a spot, and the piece picker.

local B = MCC.Build

local COL = {
    bg = Color(16, 18, 18, 248), head = Color(34, 36, 34), line = Color(70, 72, 68), text = Color(214, 214, 204),
    dim = Color(128, 130, 122), amber = Color(222, 182, 70), red = Color(220, 80, 70), green = Color(46, 204, 113),
    tile = Color(30, 32, 30), tileHover = Color(54, 56, 52), sel = Color(222, 182, 70, 60),
}

MCC.Net.Receive("build_pieces", function(data)
    if istable(data.pieces) then B.SetPieces(data.pieces) end
    if istable(data.tiers) and #data.tiers > 0 then B.Tiers = data.tiers end
end)

hook.Add("InitPostEntity", "MCC_BuildHello", function()
    MCC.Net.Send("build_hello", {})
end)

local function Tablet()
    local lp = LocalPlayer()
    local w = IsValid(lp) and lp:GetActiveWeapon()
    if IsValid(w) and w:GetClass() == "mcc_build_tablet" then return w end
end

-- Which slots a building already has, from the pieces near where you're aiming.
local function HasNear(pos, radius)
    local cache = {}
    for _, e in ipairs(ents.FindInSphere(pos, radius)) do
        local id = e:GetNWInt("MCCBld", 0)
        if id > 0 then
            cache[id] = cache[id] or {}
            cache[id][e:GetNWString("MCCSlot", "")] = true
        end
    end
    return function(id, key) return cache[id] ~= nil and cache[id][key] == true end
end

-- The ghost ----------------------------------------------------------------------------------------

local ghost, state = nil, {}

local function ClearGhost()
    if IsValid(ghost) then ghost:Remove() end
    ghost = nil
end

hook.Add("Think", "MCC_BuildGhost", function()
    local wep = Tablet()
    local piece = wep and B.Pieces[wep:GetPiece()]
    if not piece then
        ClearGhost()
        state = {}
        return
    end
    local lp = LocalPlayer()
    local tr = lp:GetEyeTrace()
    local res = B.Solve(lp, piece, tr, wep:GetRot(), HasNear(tr.HitPos, 400))
    local ok, why = res.ok, res.reason
    if ok then
        local allowed, reason, core = B.Allowed(lp, piece, res.pos)
        ok, why = allowed, reason
        state.core = core
    end
    state.piece, state.ok, state.why, state.pos = piece, ok, why, res.pos

    if not res.pos then
        if IsValid(ghost) then ghost:SetNoDraw(true) end
        return
    end
    if not IsValid(ghost) or ghost:GetModel() ~= piece.model then
        ClearGhost()
        ghost = ClientsideModel(piece.model, RENDERGROUP_TRANSLUCENT)
        if not IsValid(ghost) then return end
        ghost:SetRenderMode(RENDERMODE_TRANSALPHA)
        ghost:DrawShadow(false)
    end
    ghost:SetNoDraw(false)
    ghost:SetMaterial(piece.material or "")
    ghost:SetPos(res.pos)
    ghost:SetAngles(res.ang)
    ghost:SetColor(ok and Color(46, 204, 113, 150) or Color(220, 60, 50, 120))
end)

hook.Add("HUDPaint", "MCC_BuildHud", function()
    if not Tablet() or not state.piece then return end
    local x, y = ScrW() / 2, ScrH() / 2 + 40
    draw.SimpleTextOutlined(string.upper(state.piece.name), "DermaDefaultBold", x, y, COL.text, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
    local line
    if state.ok then
        line = MCC.Config.Get("build_free") and "Free" or MCC.Inv.CostText(B.PlaceCost(state.piece))
        if B.IsStructure(state.piece) and B.Tiers[1] then line = line .. "   (" .. B.Tiers[1].name .. ")" end
    else
        line = state.why or ""
    end
    draw.SimpleTextOutlined(line, "DermaDefault", x, y + 16, state.ok and COL.amber or COL.red, TEXT_ALIGN_CENTER,
        TEXT_ALIGN_TOP, 1, Color(0, 0, 0, 200))
end)

-- The piece picker (right-click) ------------------------------------------------------------------------

function B.OpenMenu()
    if IsValid(B.Menu) then B.Menu:Remove() end
    local wep = Tablet()
    local f = vgui.Create("DFrame")
    B.Menu = f
    f:SetSize(math.min(760, ScrW() - 40), math.min(560, ScrH() - 40))
    f:Center()
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:DockPadding(0, 34, 0, 8)
    f:MakePopup()
    MCC.UI.Escapable(f)
    f.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.head)
        surface.DrawRect(0, 0, w, 30)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        draw.SimpleText("BUILDER TABLET", "DermaLarge", 12, 15, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText("Click a piece  |  costs come from the JMod resources you carry", "DermaDefault", w - 12, 15, COL.dim,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
    function f:OnKeyCodePressed(key)
        if key == KEY_ESCAPE or key == KEY_TAB or key == KEY_Q then self:Remove() end
    end

    local scroll = vgui.Create("DScrollPanel", f)
    scroll:Dock(FILL)
    scroll:DockMargin(8, 0, 8, 0)

    local cats, order = {}, {}
    for _, id in ipairs(B.Order) do
        local p = B.Pieces[id]
        local c = p.category or "Other"
        if not cats[c] then cats[c] = {} order[#order + 1] = c end
        table.insert(cats[c], p)
    end

    for _, c in ipairs(order) do
        local head = scroll:Add("DPanel")
        head:Dock(TOP)
        head:SetTall(26)
        head:DockMargin(4, 8, 4, 2)
        head.Paint = function(_, w, h)
            draw.SimpleText(string.upper(c), "DermaDefaultBold", 0, h - 4, COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
            surface.SetDrawColor(COL.line)
            surface.DrawLine(0, h - 1, w, h - 1)
        end
        local grid = scroll:Add("DIconLayout")
        grid:Dock(TOP)
        grid:SetSpaceX(6)
        grid:SetSpaceY(6)
        grid:DockMargin(4, 4, 4, 0)
        for _, p in ipairs(cats[c]) do
            local tile = grid:Add("DButton")
            tile:SetSize(112, 128)
            tile:SetText("")
            local costText = MCC.Inv.CostText(B.PlaceCost(p))
            local hpText = B.IsStructure(p) and ((B.Tiers[1] and B.Tiers[1].name or "Twig") .. ", upgrade with the hammer")
                or ((p.health or "?") .. " health")
            tile:SetTooltip(p.name .. "\n" .. costText .. "\n" .. hpText)
            local selected = IsValid(wep) and wep:GetPiece() == p.id
            tile.Paint = function(self, w, h)
                surface.SetDrawColor(self:IsHovered() and COL.tileHover or COL.tile)
                surface.DrawRect(0, 0, w, h)
                if selected then
                    surface.SetDrawColor(COL.sel)
                    surface.DrawRect(0, 0, w, h)
                end
                surface.SetDrawColor(selected and COL.amber or COL.line)
                surface.DrawOutlinedRect(0, 0, w, h)
                draw.SimpleText(p.name, "DermaDefault", w / 2, h - 30, COL.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                draw.SimpleText(costText, "DermaDefault", w / 2, h - 14, COL.amber, TEXT_ALIGN_CENTER,
                    TEXT_ALIGN_CENTER)
            end
            local icon = vgui.Create("SpawnIcon", tile)
            icon:SetModel(p.model)
            icon:SetSize(80, 80)
            icon:SetPos(16, 6)
            icon:SetMouseInputEnabled(false)
            tile.DoClick = function()
                MCC.Net.Send("build_select", {id = p.id})
                surface.PlaySound("buttons/lightswitch2.wav")
                f:Remove()
            end
        end
    end
end

MCC.Net.Receive("build_menu", function() B.OpenMenu() end)

-- The piece menu (the hammer's right-click on a built piece): upgrade, repair, remove ---------------------

function B.OpenPieceMenu(data)
    if IsValid(B.Menu) then B.Menu:Remove() end
    local f = vgui.Create("DFrame")
    B.Menu = f
    local rows = #(data.upgrades or {})
    f:SetSize(420, 150 + rows * 46)
    f:Center()
    f:SetTitle("")
    f:ShowCloseButton(false)
    f:DockPadding(10, 64, 10, 10)
    f:MakePopup()
    MCC.UI.Escapable(f)
    f.Paint = function(_, w, h)
        surface.SetDrawColor(COL.bg)
        surface.DrawRect(0, 0, w, h)
        surface.SetDrawColor(COL.head)
        surface.DrawRect(0, 0, w, 30)
        surface.SetDrawColor(COL.line)
        surface.DrawOutlinedRect(0, 0, w, h)
        local title = string.upper(data.name or "Piece") .. ((data.tier or "") ~= "" and ("  |  " .. string.upper(data.tier)) or "")
        draw.SimpleText(title, "DermaLarge", 12, 15, COL.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        if (data.max or 0) > 0 then
            surface.SetDrawColor(40, 42, 40, 230)
            surface.DrawRect(12, 38, w - 24, 16)
            surface.SetDrawColor(150, 70, 66)
            surface.DrawRect(12, 38, (w - 24) * math.Clamp((data.hp or 0) / data.max, 0, 1), 16)
            draw.SimpleText((data.hp or 0) .. " / " .. data.max .. " HP", "DermaDefaultBold", w / 2, 46, color_white,
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
    function f:OnKeyCodePressed(key)
        if key == KEY_ESCAPE or key == KEY_TAB or key == KEY_Q then self:Remove() end
    end

    local function Btn(text, sub, fn, enabled)
        local b = vgui.Create("DButton", f)
        b:Dock(TOP)
        b:SetTall(40)
        b:DockMargin(0, 0, 0, 6)
        b:SetText("")
        b:SetEnabled(enabled ~= false)
        b.Paint = function(self, w, h)
            surface.SetDrawColor(self:IsHovered() and COL.tileHover or COL.tile)
            surface.DrawRect(0, 0, w, h)
            surface.SetDrawColor(COL.line)
            surface.DrawOutlinedRect(0, 0, w, h)
            draw.SimpleText(text, "DermaDefaultBold", 10, h / 2 - 7, self:IsEnabled() and COL.text or COL.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            draw.SimpleText(sub, "DermaDefault", 10, h / 2 + 8, COL.amber, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        end
        b.DoClick = function()
            fn()
            f:Remove()
        end
    end
    local function Send(a, extra)
        local t = extra or {}
        t.a, t.e = a, data.e
        MCC.Net.Send("build_piece_act", t)
    end
    local costs = function(c) return data.free and "free" or MCC.Inv.CostText(c) end

    for _, u in ipairs(data.upgrades or {}) do
        Btn("Upgrade to " .. u.name .. "  (" .. u.health .. " HP, decays in " .. u.decayHours .. " h without upkeep)",
            costs(u.cost), function() Send("upgrade", {tier = u.i}) end)
    end
    local damaged = next(data.repair or {}) ~= nil
    local wait = data.wait or 0
    Btn(not damaged and "Repair (not damaged)" or wait > 0 and ("Repair (recently damaged: wait " .. wait .. "s)") or "Repair to full",
        damaged and costs(data.repair) or "-", function() Send("repair") end, damaged and wait <= 0)
    Btn("Remove", "refund: " .. costs(data.refund), function() Send("remove") end)
end

MCC.Net.Receive("build_piece_menu", function(data) B.OpenPieceMenu(data) end)
