-- MCC inventory UI, laid out like Tarkov's gear screen:
--   left:   equipment (earpiece ... sheath) over a faint silhouette of your character
--   middle: tactical rig, pockets, special slots, backpack and pouch, each with its storage grid
--   right:  IN THE VICINITY (items, bodies and containers near you), or the body / container
--           you're searching, shown with the same layout as your own gear
-- Mouse: drag (R rotates while dragging), Ctrl+click quick move, Alt+click equip, right-click menu.
-- Drag and drop mechanics adapted from the Tarkov Inventory addon.

local Inv = MCC.Inv
Inv.State = Inv.State or {slots = {}}
Inv.LastClose = 0

-- userinfo, so the server can read it: in singleplayer key presses only reach the server
local cvKey = CreateClientConVar("mcc_inventory_key", tostring(KEY_I), true, true,
    "Key that opens the inventory (a KEY_ number).")

-- Look ------------------------------------------------------------------------------------

local C = {
    shade     = Color(6, 7, 6, 205),
    header    = Color(27, 28, 26, 245),
    headerLn  = Color(74, 76, 71),
    slot      = Color(13, 14, 13, 215),
    slotLn    = Color(58, 60, 56),
    grid      = Color(24, 25, 23, 225),
    gridLn    = Color(255, 255, 255, 14),
    stripe    = Color(255, 255, 255, 9),
    row       = Color(20, 21, 20, 225),
    rowHover  = Color(40, 42, 39, 235),
    text      = Color(214, 214, 204),
    dim       = Color(120, 121, 114),
    amber     = Color(221, 186, 92),
    good      = Color(110, 200, 100, 70),
    bad       = Color(210, 70, 70, 80),
    itemLn    = Color(92, 94, 88, 170),
    itemHover = Color(232, 232, 222, 210),
}

local ITEM_BG = {
    weapon     = Color(26, 27, 26, 240),
    ammo       = Color(36, 46, 33, 240),
    mag        = Color(34, 40, 36, 240),
    gear       = Color(44, 41, 30, 240),
    armor      = Color(30, 36, 44, 240),
    consumable = Color(52, 30, 30, 240),
    resource   = Color(40, 38, 34, 240),
    misc       = Color(34, 34, 40, 240),
}

local RARITY = {
    uncommon = Color(90, 150, 90),
    rare = Color(80, 130, 200),
    epic = Color(160, 100, 210),
}

local fontCell
local function MakeFonts(c)
    c = c or 64
    if c == fontCell then return end
    fontCell = c
    local s = math.max(0.6, c / 64)
    surface.CreateFont("MCC_InvTitle", {font = "Bahnschrift", size = math.floor(26 * s), weight = 700, extended = true})
    surface.CreateFont("MCC_InvLabel", {font = "Bahnschrift", size = math.floor(16 * s), weight = 700, extended = true})
    surface.CreateFont("MCC_InvSmall", {font = "Bahnschrift", size = math.floor(14 * s), weight = 600, extended = true})
    surface.CreateFont("MCC_InvCount", {font = "Bahnschrift", size = math.floor(17 * s), weight = 700, extended = true})
end
MakeFonts()

local blur = Material("pp/blurscreen")
local function Blur(amount)
    surface.SetDrawColor(255, 255, 255)
    surface.SetMaterial(blur)
    for i = 1, 3 do
        blur:SetFloat("$blur", i / 3 * amount)
        blur:Recompute()
        render.UpdateScreenEffectTexture()
        surface.DrawTexturedRect(0, 0, ScrW(), ScrH())
    end
end

-- Diagonal stripes in a rect. (x, y) is where to draw in the current panel; (sx, sy) its screen
-- position for clipping, when they differ (inside child panels).
local function Stripes(x, y, w, h, sx, sy)
    sx, sy = sx or x, sy or y
    render.SetScissorRect(sx, sy, sx + w, sy + h, true)
    surface.SetDrawColor(C.stripe)
    for i = -h, w, 9 do surface.DrawLine(x + i, y + h, x + i + h, y) end
    render.SetScissorRect(0, 0, 0, 0, false)
end

local function ItemName(def)
    return string.upper(MCC.Items.DisplayName(def))
end

-- Short name for the corner of an item, like Tarkov's.
local function ShortName(def)
    if def and def.data and def.data.short then return string.upper(def.data.short) end
    return ItemName(def)
end

local function IsMine(loc)
    local c = string.sub(loc or "", 1, 1)
    return c == "s" or c == "g"
end

-- Networking ------------------------------------------------------------------------------

function Inv.Act(tbl)
    MCC.Net.Send("inv_act", tbl)
end

-- Everything, or (diff) only the slots that changed, the ones that went, and the opened container if it changed.
MCC.Net.Receive("inv_sync", function(data)
    if data.diff and Inv.State then
        local slots = Inv.State.slots or {}
        for k, it in pairs(data.slots or {}) do slots[k] = it end
        for _, k in ipairs(data.gone or {}) do slots[k] = nil end
        Inv.State.slots = slots
        if data.oc then Inv.State.open = data.open end
    else
        Inv.State = {slots = data.slots or {}, open = data.open}
    end
    if IsValid(Inv.Panel) then Inv.Panel:Rebuild() end
end)

MCC.Net.Receive("inv_open", function()
    Inv.OpenUI(true)
end)

MCC.Net.Receive("inv_notify", function(data)
    notification.AddLegacy(tostring(data.msg or ""), NOTIFY_HINT, 3)
    surface.PlaySound("buttons/button15.wav")
end)

MCC.Net.Receive("inv_containers", function(data)
    Inv.ContainerModels = data.models or {}
end)

hook.Add("InitPostEntity", "MCC_InvHello", function()
    MCC.Net.Send("inv_hello", {})
end)

-- Model icons -----------------------------------------------------------------------------

-- Frames a model inside a w x h box (camera fitting from the Tarkov Inventory addon).
local function FrameModel(mp, def, w, h, rotated)
    local ent = mp:GetEntity()
    if not IsValid(ent) then return end
    local mn, mx = ent:GetRenderBounds()
    local sz, ctr = mx - mn, (mn + mx) / 2
    local fov = 30
    mp:SetFOV(fov)
    local t = math.tan(math.rad(fov / 2)) * 2
    local pw, ph = math.max(w - 8, 8), math.max(h - 8, 8)

    if def and def.kind == "weapon" then
        local a, b = math.max(sz.x, sz.y), sz.z
        local hw, vh = a, b
        if rotated then hw, vh = b, a end
        local d = math.max(hw, vh * pw / ph) * 1.15 / t
        local roll = rotated and -90 or 0
        if sz.x >= sz.y then
            mp:SetCamPos(ctr + Vector(0, -d, 0))
            mp:SetLookAng(Angle(0, 90, roll))
        else
            mp:SetCamPos(ctr + Vector(-d, 0, 0))
            mp:SetLookAng(Angle(0, 0, roll))
        end
    else
        local d = sz:Length() / t * math.max(1, pw / ph)
        local ang = Angle(25, 225, 0)
        mp:SetCamPos(ctr - ang:Forward() * d)
        mp:SetLookAng(ang)
    end
end

-- Expansions can show a flat picture instead of the 3D model (ARC9 attachments use their icons):
--   hook.Add("MCC_ItemIcon", id, function(def) return Material("entities/x.png") end) -- an IMaterial
local iconCache = {}
function Inv.ItemIcon(def)
    if not def then return nil end
    local m = hook.Run("MCC_ItemIcon", def)
    if m then return m end
    local path = def.data and def.data.icon
    if isstring(path) and path ~= "" then
        if iconCache[path] == nil then
            local mat = Material(path, "mips smooth")
            iconCache[path] = (mat and not mat:IsError()) and mat or false
        end
        return iconCache[path] or nil
    end
end

local function ImageIcon(parent, mat, x, y, w, h)
    local p = vgui.Create("DPanel", parent)
    p:SetPos(x, y)
    p:SetSize(w, h)
    p:SetMouseInputEnabled(false)
    p.Paint = function(_, pw, ph)
        local s = math.min(pw, ph) - 4
        surface.SetDrawColor(255, 255, 255, 255)
        surface.SetMaterial(mat)
        surface.DrawTexturedRect((pw - s) / 2, (ph - s) / 2, s, s)
    end
    return p
end

local function ModelIcon(parent, model, def, x, y, w, h, rotated, color)
    local icon = Inv.ItemIcon(def)
    if icon then return ImageIcon(parent, icon, x, y, w, h) end
    local mp = vgui.Create("DModelPanel", parent)
    mp:SetPos(x, y)
    mp:SetSize(w, h)
    mp:SetMouseInputEnabled(false)
    mp:SetModel(model or "models/error.mdl")
    if color then mp:SetColor(color) end
    mp.LayoutEntity = function() end
    FrameModel(mp, def, w, h, rotated)
    return mp
end

-- Item tile -------------------------------------------------------------------------------

local ITEM = {}

function ITEM:Setup(it, loc, w, h, inSlot)
    self.it, self.loc, self.inSlot = it, loc, inSlot
    self:SetSize(w, h)
    if it.hidden then
        self:SetTooltip("Not searched yet")
        return
    end
    self.def = Inv.Def(it)
    self:SetCursor("hand")

    local def = self.def
    local tip = ItemName(def)
    if def then
        tip = tip .. string.format("\n%.2f kg", Inv.Weight(it))
        if def.kind == "mag" then tip = tip .. string.format("\n%d / %d rounds", Inv.MagRounds(it), def.data.cap or 0) end
        if def.kind == "ammo" and string.find(loc, "^g:backpack") then tip = tip .. "\nMove to your rig or pockets to use it" end
        if def.kind == "consumable" then tip = tip .. "\nRight-click to use" end
        if it.d and it.d.name then tip = tip .. "\n" .. it.d.name end
        if it.d and isstring(it.d.note) then tip = tip .. "\n" .. it.d.note end
        -- expansions add lines: hook.Add("MCC_ItemTooltip", id, function(it, def) return "line" end)
        local extra = hook.Run("MCC_ItemTooltip", it, def)
        if isstring(extra) and extra ~= "" then tip = tip .. "\n" .. extra end
    end
    self:SetTooltip(tip)
    ModelIcon(self, def and def.model, def, 2, 2, w - 4, h - 4, it.r and not inSlot)
end

local function DrawHidden(self, w, h)
    surface.SetDrawColor(18, 19, 18, 245)
    surface.DrawRect(0, 0, w, h)
    local sx, sy = self:LocalToScreen(0, 0)
    Stripes(0, 0, w, h, sx, sy)
    local open = Inv.State.open
    if open and open.searching == self.it.u and open.dur and open.dur > 0 then
        local p = math.Clamp(1 - (open.ends - CurTime()) / open.dur, 0, 1)
        surface.SetDrawColor(221, 186, 92, 60)
        surface.DrawRect(0, h - h * p, w, h * p)
    end
    surface.SetDrawColor(C.itemLn)
    surface.DrawOutlinedRect(0, 0, w, h)
    draw.SimpleText("?", "MCC_InvCount", w / 2, h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function ITEM:Paint(w, h)
    if self.it.hidden then return DrawHidden(self, w, h) end
    local def = self.def
    surface.SetDrawColor(ITEM_BG[def and def.kind or "misc"] or ITEM_BG.misc)
    surface.DrawRect(0, 0, w, h)
end

function ITEM:PaintOver(w, h)
    if self.it.hidden then return end
    local it, def = self.it, self.def
    if def and def.kind == "ammo" and string.find(self.loc, "^g:backpack") then
        surface.SetDrawColor(0, 0, 0, 110)
        surface.DrawRect(0, 0, w, h)
    end
    local rc = def and RARITY[def.rarity]
    if rc then
        surface.SetDrawColor(rc.r, rc.g, rc.b, 160)
        surface.DrawRect(0, 0, w, 2)
    end
    surface.SetDrawColor(self:IsHovered() and C.itemHover or C.itemLn)
    surface.DrawOutlinedRect(0, 0, w, h)
    draw.SimpleText(ShortName(def), "MCC_InvSmall", w - 3, 2, C.text, TEXT_ALIGN_RIGHT)
    if it.n and it.n > 1 then
        draw.SimpleText(tostring(it.n), "MCC_InvCount", w - 3, h - 1, C.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    end
    if def and def.kind == "mag" then
        draw.SimpleText(Inv.MagRounds(it) .. "/" .. (def.data.cap or 0), "MCC_InvSmall", w - 3, h - 1, C.amber,
            TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
    elseif def and def.kind == "weapon" and it.d and it.d.clip then
        draw.SimpleText(tostring(it.d.clip), "MCC_InvSmall", 3, h - 1, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)
    elseif def and def.data.jmod and Inv.ResourceAmount then
        draw.SimpleText(tostring(Inv.ResourceAmount(it)), "MCC_InvCount", w - 3, h - 1, C.amber, TEXT_ALIGN_RIGHT,
            TEXT_ALIGN_BOTTOM)
    end
end

function ITEM:OnMousePressed(code)
    local main = Inv.Panel
    if not IsValid(main) or self.it.hidden then return end
    local u = self.it.u
    if code == MOUSE_LEFT then
        if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
            Inv.Act({a = "quick", u = u})
        elseif input.IsKeyDown(KEY_LALT) or input.IsKeyDown(KEY_RALT) then
            Inv.Act({a = "equip", u = u})
        else
            main:BeginDrag(self)
        end
    elseif code == MOUSE_RIGHT then
        local m = DermaMenu()
        local def = self.def
        local mine = IsMine(self.loc)
        local it, loc = self.it, self.loc
        m:AddOption("Inspect", function() Inv.OpenInspect(it, loc) end)
        if mine and def and def.kind == "consumable" then
            m:AddOption(def.data.useLabel or "Use", function() Inv.Act({a = "use", u = u}) end)
        end
        if mine and def and def.kind == "weapon" and (def.data.clip or 0) > 0 then
            m:AddOption("Load from loose rounds", function() Inv.Act({a = "loadgun", u = u}) end)
            if (self.it.d and self.it.d.clip or 0) > 0 then
                m:AddOption("Unload", function() Inv.Act({a = "unloadgun", u = u}) end)
            end
        end
        if mine and def and def.kind == "mag" then
            m:AddOption("Load from loose rounds", function() Inv.Act({a = "load", u = u}) end)
            if Inv.MagRounds(self.it) > 0 then m:AddOption("Unload", function() Inv.Act({a = "unload", u = u}) end) end
        end
        if (self.it.n or 1) > 1 then
            m:AddOption("Split stack", function() Inv.Act({a = "split", u = u}) end)
        end
        m:AddOption("Equip", function() Inv.Act({a = "equip", u = u}) end)
        m:AddOption("Quick move", function() Inv.Act({a = "quick", u = u}) end)
        m:AddOption("Drop", function() Inv.Act({a = "drop", u = u}) end)
        m:Open()
    end
end

vgui.Register("MCC_InvItem", ITEM, "Panel")

-- Vicinity -----------------------------------------------------------------------------------
-- Items, bodies and containers near you, found on the client; the server checks every action.

function Inv.ScanVicinity()
    local ply = LocalPlayer()
    if not IsValid(ply) then return {} end
    local range = MCC.Config.Get("inv_vicinity_range")
    local origin = ply:GetPos()
    local out = {}
    for _, e in ipairs(ents.FindInSphere(origin, range)) do
        local kind = MCC.Pickup.Kind(e)
        if kind == "body" or kind == "container" then
            out[#out + 1] = {ent = e, kind = kind, name = MCC.Pickup.Name(e), dist = origin:DistToSqr(e:GetPos())}
            if kind == "container" then
                local def = Inv.ContainerDef(e)
                out[#out].name = def and def.name or e:GetNWString("MCCName", "Container")
            end
        elseif kind then
            local id, n = Inv.WorldItemInfo(e)
            local def = id and MCC.Items.Get(id)
            if def then
                local name = MCC.Items.DisplayName(def)
                if def.data.jmod and e.GetResource then name = name .. " (" .. e:GetResource() .. ")" end
                out[#out + 1] = {ent = e, kind = "item", id = id, n = n, def = def, name = name,
                    dist = origin:DistToSqr(e:GetPos())}
            end
        end
    end
    table.sort(out, function(a, b) return a.dist < b.dist end)
    return out
end

local function VicinitySignature(list)
    local parts = {}
    for _, r in ipairs(list) do parts[#parts + 1] = r.ent:EntIndex() .. ":" .. (r.n or 0) end
    return table.concat(parts, ",")
end

local ROW = {}

function ROW:Setup(row, w, h)
    self.row = row
    self:SetSize(w, h)
    self:SetCursor("hand")
    if row.def then
        ModelIcon(self, row.def.model, row.def, 2, 2, h - 4, h - 4, false)
        self:SetTooltip("Drag into your gear, or Ctrl+click to take it")
    else
        self:SetTooltip("Click to search")
    end
end

function ROW:Paint(w, h)
    surface.SetDrawColor(self:IsHovered() and C.rowHover or C.row)
    surface.DrawRect(0, 0, w, h)
    surface.SetDrawColor(C.slotLn)
    surface.DrawOutlinedRect(0, 0, w, h)
    local r = self.row
    local tx = r.def and h + 4 or 8
    if r.def then
        local name = string.upper(r.name or "?")
        if r.n and r.n > 1 then name = name .. "  x" .. r.n end
        draw.SimpleText(name, "MCC_InvLabel", tx, h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    else
        -- "LOOT BODY" with the body's name in smaller text under it
        draw.SimpleText(r.kind == "body" and "LOOT BODY" or "SEARCH", "MCC_InvLabel", tx, h * 0.36, C.text,
            TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(r.name or "", "MCC_InvSmall", tx, h * 0.72, C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
        draw.SimpleText(">", "MCC_InvLabel", w - 8, h / 2, C.amber, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end
end

function ROW:OnMousePressed(code)
    local main = Inv.Panel
    local r = self.row
    if not IsValid(main) or not IsValid(r.ent) then return end
    if not r.def then
        if code == MOUSE_LEFT then Inv.Act({a = "open", e = r.ent:EntIndex()}) end
        return
    end
    if code == MOUSE_LEFT then
        if input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) then
            Inv.Act({a = "take", e = r.ent:EntIndex()})
        else
            main:BeginDragRow(self)
        end
    elseif code == MOUSE_RIGHT then
        local m = DermaMenu()
        m:AddOption("Take", function() Inv.Act({a = "take", e = r.ent:EntIndex()}) end)
        m:Open()
    end
end

vgui.Register("MCC_InvRow", ROW, "Panel")

-- Main panel ------------------------------------------------------------------------------

local PANEL = {}

-- Ghost models drawn in empty weapon slots, like the outlines in Tarkov's empty slots.
local GHOSTS = {
    sling = "models/weapons/w_irifle.mdl",
    back = "models/weapons/w_shotgun.mdl",
    holster = "models/weapons/w_pistol.mdl",
    sheath = "models/weapons/w_crowbar.mdl",
}

function PANEL:Init()
    self:SetSize(ScrW(), ScrH())
    self:SetPos(0, 0)
    self:MakePopup()
    self:SetKeyboardInputEnabled(true)
    self.vicinity = Inv.ScanVicinity()
    self.vicSig = VicinitySignature(self.vicinity)
    self.nextScan = 0
    self:Rebuild()
end

local function Prefixes(owner)
    if owner == "b" then return "bs:", "bg:" end
    return "s:", "g:"
end

function PANEL:AddSlot(owner, key, x, y, w, h, slots, noHeader)
    local sp = Prefixes(owner)
    local z = {slot = true, owner = owner, key = key, loc = sp .. key, x = x, y = y + (noHeader and 0 or self.hh),
        w = w * self.c, h = h * self.c, label = Inv.Slots[key].label, header = not noHeader,
        hx = x, hy = y, slots = slots, spec = Inv.Slots[key].special}
    self.Zones[#self.Zones + 1] = z
    return z
end

function PANEL:AddGrid(loc, x, y, cols, rows, items, gear)
    local z = {loc = loc, x = x, y = y, w = cols * self.c, h = rows * self.c, cols = cols, rows = rows,
        items = items or {}, gear = gear}
    self.Zones[#self.Zones + 1] = z
    return z
end

function PANEL:AddHeader(text, x, y, w)
    local hd = {text = text, x = x, y = y, w = w}
    self.Headers[#self.Headers + 1] = hd
    return hd
end

-- A closed part of what you're looting (pockets, a bag's storage, a container) with its SEARCH button.
function PANEL:AddSection(key, x, y, w, h)
    local open = Inv.State.open
    local state = open and open.sections and open.sections[key] or "done"
    self.Sections[#self.Sections + 1] = {key = key, x = x, y = y, w = w, h = h, state = state}
end

-- Which section a loot location belongs to (matches the server's rules).
local function SectionOfLoc(loc)
    if loc == "c" then return "c:1" end
    if string.find(loc or "", "^c:%d+$") then return loc end
    local key = string.match(loc or "", "^bs:(%w+)$")
    if key then
        local s = Inv.Slots[key]
        return (s and (s.pocket or s.special)) and "pockets" or nil
    end
    return string.match(loc or "", "^bg:(%w+):")
end

function PANEL:Locked(loc)
    local section = SectionOfLoc(loc)
    if not section then return false end
    local open = Inv.State.open
    local state = open and open.sections and open.sections[section]
    return state ~= nil and state ~= "done"
end

-- The storage grids of a gear item, drawn from (x, y). Returns their width and height in pixels.
function PANEL:AddGearGrids(prefix, key, gear, x, y)
    local cells = Inv.Cells(gear)
    if not cells then return 0, 0 end
    local c = self.c
    for i, cell in ipairs(cells) do
        self:AddGrid(prefix .. key .. ":" .. i, x + cell.x * c, y + cell.y * c, cell.w, cell.h,
            gear.cont and gear.cont[i] or {}, gear)
    end
    local bw, bh = Inv.CellBounds(gear)
    return bw * c, bh * c
end

-- Equipment column (Tarkov's left side). Returns width, height in pixels.
function PANEL:BuildEquipment(x, y, slots, owner)
    local c, hh, gap = self.c, self.hh, self.c * 0.25
    local colA, colB, colC = x, x + 2.4 * c, x + 4.8 * c
    local row = y

    self:AddSlot(owner, "earpiece", colA, row, 2, 2, slots)
    self:AddSlot(owner, "headwear", colB, row, 2, 2, slots)
    self:AddSlot(owner, "facecover", colC, row, 2, 2, slots)
    row = row + hh + 2 * c + gap

    self:AddSlot(owner, "armband", colA, row, 2, 1, slots)
    self:AddSlot(owner, "armor", colB, row, 2, 2, slots)
    self:AddSlot(owner, "eyewear", colC, row, 2, 2, slots)
    self:AddSlot(owner, "dogtag", colA, row + hh + c + gap, 2, 1, slots)
    row = row + hh + 2 * c + gap * 2

    self:AddSlot(owner, "sling", colA, row, 4.4, 2, slots)
    self:AddSlot(owner, "holster", colC, row, 2, 2, slots)
    row = row + hh + 2 * c + gap

    self:AddSlot(owner, "back", colA, row, 4.4, 2, slots)
    self:AddSlot(owner, "sheath", colC, row, 2, 2, slots)
    row = row + hh + 2 * c

    return 6.8 * c, row - y
end

-- Gear column (Tarkov's middle): rig, pockets + special slots, backpack, pouch.
function PANEL:BuildContainers(x, y, slots, owner)
    local c, hh, gap = self.c, self.hh, self.c * 0.35
    local _, gp = Prefixes(owner)
    local gx = x + 2.4 * c
    local row = y
    local width = 0

    local function block(key)
        self:AddSlot(owner, key, x, row, 2, 2, slots)
        local gw, gh = 0, 0
        if slots[key] then gw, gh = self:AddGearGrids(gp, key, slots[key], gx, row + hh) end
        if owner == "b" and gw > 0 then self:AddSection(key, gx, row + hh, gw, gh) end
        width = math.max(width, 2.4 * c + gw)
        row = row + hh + math.max(2 * c, gh) + gap
    end

    block("rig")

    self:AddHeader("POCKETS", x, row, Inv.POCKETS * 1.1 * c - 0.1 * c)
    for i = 1, Inv.POCKETS do
        self:AddSlot(owner, "pocket" .. i, x + (i - 1) * 1.1 * c, row + hh, 1, 1, slots, true)
    end
    local sx = x + Inv.POCKETS * 1.1 * c + 0.5 * c
    self:AddHeader("SPECIAL SLOTS", sx, row, Inv.SPECIALS * 1.1 * c - 0.1 * c)
    for i = 1, Inv.SPECIALS do
        self:AddSlot(owner, "special" .. i, sx + (i - 1) * 1.1 * c, row + hh, 1, 1, slots, true)
    end
    width = math.max(width, sx - x + Inv.SPECIALS * 1.1 * c)
    if owner == "b" then self:AddSection("pockets", x, row + hh, sx - x + Inv.SPECIALS * 1.1 * c - 0.1 * c, c) end
    row = row + hh + c + gap

    block("backpack")
    block("pouch")
    return width, row - y
end

-- Right column: what you're searching, or what's around you.
function PANEL:BuildRight(x, y)
    local c, hh = self.c, self.hh
    local open = Inv.State.open
    self.backButton, self.fobButton = nil, nil

    if open then
        local title = string.upper(open.name or "CONTAINER")
        if open.body then title = "LOOT BODY:  " .. title end
        local bw = open.fob and 5 * c or 8 * c
        self:AddHeader("<  " .. title, x, y, bw)
        self.backButton = {x = x, y = y, w = bw, h = hh}
        if open.fob then
            -- a FOB's stash: its menu (upkeep, upgrade, members) is one click away
            local fx = x + bw + c * 0.2
            self:AddHeader("FOB MENU  >", fx, y, 3 * c - c * 0.2)
            self.fobButton = {x = fx, y = y, w = 3 * c - c * 0.2, h = hh, e = open.fob}
        end
        local top = y + hh + c * 0.3
        if open.body then
            local slots = open.slots or {}
            local ew, eh = self:BuildEquipment(x, top, slots, "b")
            local mw, mh = self:BuildContainers(x + ew + c * 0.8, top, slots, "b")
            return ew + c * 0.8 + mw, hh + c * 0.3 + math.max(eh, mh)
        end
        -- one grid per compartment: side by side (lockers), wrapping if wide, or stacked (drawers)
        local gap = c * 0.3
        local maxW = math.max(8 * c, ScrW() - x - c)
        local cx, cy, rowH, width = x, top, 0, 8 * c
        for i, g in ipairs(open.grids or {}) do
            local gw, gh = g.w * c, g.h * c
            if cx > x and (open.vertical or cx + gw > x + maxW) then
                cx, cy, rowH = x, cy + rowH + gap, 0
            end
            self:AddGrid("c:" .. i, cx, cy, g.w, g.h, g.items)
            self:AddSection("c:" .. i, cx, cy, gw, gh)
            width = math.max(width, cx - x + gw)
            rowH = math.max(rowH, gh)
            cx = cx + gw + gap
        end
        return width, hh + c * 0.3 + (cy - top) + rowH
    end

    local w = 7 * c
    self:AddHeader("IN THE VICINITY", x, y, w)
    local rowH = math.floor(c * 0.9)
    local top = y + hh + c * 0.2
    local maxRows = math.max(3, math.floor((ScrH() - top - c * 1.2) / (rowH + 2)))
    self.vicZone = {vicinity = true, x = x, y = top, w = w, h = maxRows * (rowH + 2)}
    self.vicRows = {}
    for i, r in ipairs(self.vicinity) do
        if i > maxRows then break end
        self.vicRows[#self.vicRows + 1] = {row = r, x = x, y = top + (i - 1) * (rowH + 2), w = w, h = rowH}
    end
    return w, hh + c * 0.2 + self.vicZone.h
end

function PANEL:Layout(c)
    self.c, self.hh = c, math.floor(c * 0.36)
    self.Zones, self.Headers, self.Sections = {}, {}, {}
    self.vicZone, self.vicRows = nil, {}
    local slots = Inv.State.slots or {}
    local margin, top = c * 0.5, c * 1.3

    local ew, eh = self:BuildEquipment(margin, top, slots, "p")
    local mx = margin + ew + c * 0.8
    local mw, mh = self:BuildContainers(mx, top, slots, "p")
    local rx = mx + mw + c * 0.8
    local rw, rh = self:BuildRight(rx, top)
    self.eqX, self.eqY, self.eqW, self.eqH = margin, top, ew, eh
    return rx + rw + margin, top + math.max(eh, mh, rh) + c
end

function PANEL:Rebuild()
    self.drag = nil
    for _, ch in ipairs(self:GetChildren()) do ch:Remove() end

    -- fit on screen: lay out at full size, then shrink the cell size if needed
    local base = math.floor(math.Clamp(ScrH() / 16, 36, 72))
    local w, h = self:Layout(base)
    local c = math.floor(math.max(24, math.min(base, base * ScrW() / w, base * ScrH() / h)))
    if c ~= base then self:Layout(c) end
    MakeFonts(self.c)

    -- faint silhouette of your character behind the equipment, like Tarkov's
    local ply = LocalPlayer()
    if IsValid(ply) then
        local mp = vgui.Create("DModelPanel", self)
        mp:SetPos(self.eqX + self.eqW * 0.1, self.eqY)
        mp:SetSize(self.eqW * 0.8, self.eqH)
        mp:SetMouseInputEnabled(false)
        mp:SetModel(ply:GetModel())
        mp:SetColor(Color(255, 255, 255, 28))
        mp:SetFOV(36)
        mp:SetCamPos(Vector(120, 0, 40))
        mp:SetLookAt(Vector(0, 0, 36))
        mp.LayoutEntity = function(_, ent) ent:SetAngles(Angle(0, 0, 0)) end
        -- with the rig, backpack and armor you're wearing
        local ent = mp:GetEntity()
        if IsValid(ent) then
            ent:SetSkin(ply:GetSkin())
            for _, bg in ipairs(ply:GetBodyGroups() or {}) do ent:SetBodygroup(bg.id, ply:GetBodygroup(bg.id)) end
            mp.worn = Inv.MakeWornModels(ent, ply:GetNWString("MCCWorn", ""), true)
        end
        mp.PostDrawModel = function(s)
            for _, m in ipairs(s.worn or {}) do
                if IsValid(m) then m:DrawModel() end
            end
        end
        mp.OnRemove = function(s) Inv.ClearWornModels(s.worn) end
    end

    for _, z in ipairs(self.Zones) do
        if z.slot then
            local it = z.slots and z.slots[z.key]
            if it then
                self:PlaceItem(it, z)
            elseif GHOSTS[z.key] then
                ModelIcon(self, GHOSTS[z.key], {kind = "weapon"}, z.x + 4, z.y + 4, z.w - 8, z.h - 8, false,
                    Color(200, 200, 200, 30))
            end
        else
            for _, it in ipairs(z.items or {}) do self:PlaceItem(it, z) end
        end
    end

    for _, r in ipairs(self.vicRows or {}) do
        local p = vgui.Create("MCC_InvRow", self)
        p:SetPos(r.x, r.y)
        p:Setup(r.row, r.w, r.h)
    end
end

function PANEL:PlaceItem(it, z)
    local c = self.c
    local p = vgui.Create("MCC_InvItem", self)
    if z.slot then
        p:SetPos(z.x + 2, z.y + 2)
        p:Setup(it, z.loc, z.w - 4, z.h - 4, true)
    else
        local iw, ih = Inv.Size(it)
        p:SetPos(z.x + it.x * c + 1, z.y + it.y * c + 1)
        p:Setup(it, z.loc, iw * c - 2, ih * c - 2, false)
    end
end

local function DrawHeader(text, x, y, w, h, arrow)
    surface.SetDrawColor(C.header)
    surface.DrawRect(x, y, w, h)
    surface.SetDrawColor(C.headerLn)
    surface.DrawOutlinedRect(x, y, w, h)
    draw.SimpleText(text, "MCC_InvLabel", x + 6, y + h / 2, C.text, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    if arrow then draw.SimpleText(">", "MCC_InvLabel", x + w - 7, y + h / 2, C.text, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER) end
end

function PANEL:Paint(w, h)
    Blur(5)
    surface.SetDrawColor(C.shade)
    surface.DrawRect(0, 0, w, h)
    local c = self.c

    -- top bar, like Tarkov's preset name box
    local title = "INVENTORY"
    surface.SetFont("MCC_InvTitle")
    local tw, th = surface.GetTextSize(title)
    local bw, bh = math.max(tw + c * 2, c * 6), th + c * 0.25
    local bx, by = self.eqX + c * 1.2, c * 0.3
    surface.SetDrawColor(C.header)
    surface.DrawRect(bx, by, bw, bh)
    surface.SetDrawColor(C.headerLn)
    surface.DrawOutlinedRect(bx, by, bw, bh)
    draw.SimpleText(title, "MCC_InvTitle", bx + bw / 2, by + bh / 2, C.text, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%.1f KG", Inv.TotalWeight(Inv.State)), "MCC_InvLabel", bx + bw + c * 0.4, by + bh / 2,
        C.dim, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

    for _, hd in ipairs(self.Headers) do DrawHeader(hd.text, hd.x, hd.y, hd.w, self.hh, false) end

    for _, z in ipairs(self.Zones) do
        if z.slot then
            if z.header then DrawHeader(z.label, z.hx, z.hy, z.w, self.hh, true) end
            surface.SetDrawColor(C.slot)
            surface.DrawRect(z.x, z.y, z.w, z.h)
            Stripes(z.x, z.y, z.w, z.h)
            surface.SetDrawColor(C.slotLn)
            surface.DrawOutlinedRect(z.x, z.y, z.w, z.h)
            if z.spec and not (z.slots and z.slots[z.key]) then
                draw.SimpleText("SPEC", "MCC_InvSmall", z.x + z.w / 2, z.y + z.h / 2, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        else
            surface.SetDrawColor(C.grid)
            surface.DrawRect(z.x, z.y, z.w, z.h)
            surface.SetDrawColor(C.gridLn)
            for i = 1, z.cols - 1 do surface.DrawLine(z.x + i * c, z.y, z.x + i * c, z.y + z.h) end
            for j = 1, z.rows - 1 do surface.DrawLine(z.x, z.y + j * c, z.x + z.w, z.y + j * c) end
            surface.SetDrawColor(C.slotLn)
            surface.DrawOutlinedRect(z.x, z.y, z.w, z.h)
        end
    end

    if self.vicZone and #self.vicRows == 0 then
        draw.SimpleText("Nothing nearby", "MCC_InvSmall", self.vicZone.x + 6, self.vicZone.y + 4, C.dim)
    end

    local key = string.upper(input.GetKeyName(cvKey:GetInt()) or "I")
    draw.SimpleText("LMB drag   |   R rotate   |   CTRL+click quick move   |   ALT+click equip   |   RMB menu / inspect   |   "
        .. key .. " close", "MCC_InvLabel", w / 2, h - c * 0.4, C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Search state of each section (SEARCH button, QUEUED, SEARCHING...), drawn over the items and gear in it.
function PANEL:DrawSections()
    local c = self.c
    for _, sec in ipairs(self.Sections or {}) do
        if sec.state == "closed" or sec.state == "queued" then
            surface.SetDrawColor(8, 9, 8, 225)
            surface.DrawRect(sec.x, sec.y, sec.w, sec.h)
            local bw, bh = math.min(sec.w - 8, c * 2.6), math.min(sec.h - 8, self.hh * 1.3)
            local bx, by = sec.x + sec.w / 2 - bw / 2, sec.y + sec.h / 2 - bh / 2
            local hot = sec.state == "closed" and self:IsHoveredRect(sec)
            surface.SetDrawColor(hot and C.rowHover or C.header)
            surface.DrawRect(bx, by, bw, bh)
            surface.SetDrawColor(C.headerLn)
            surface.DrawOutlinedRect(bx, by, bw, bh)
            draw.SimpleText(sec.state == "closed" and "SEARCH" or "QUEUED", "MCC_InvLabel", bx + bw / 2, by + bh / 2,
                sec.state == "closed" and C.text or C.dim, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        elseif sec.state == "searching" then
            surface.SetFont("MCC_InvSmall")
            local tw, th = surface.GetTextSize("SEARCHING...")
            surface.SetDrawColor(8, 9, 8, 210)
            surface.DrawRect(sec.x + 2, sec.y + 2, tw + 6, th + 2)
            draw.SimpleText("SEARCHING...", "MCC_InvSmall", sec.x + 5, sec.y + 3, C.amber)
        end
    end
end

function PANEL:IsHoveredRect(r)
    local mx, my = self:CursorPos()
    return mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
end

function PANEL:OnMousePressed(code)
    if code ~= MOUSE_LEFT then return end
    for _, sec in ipairs(self.Sections or {}) do
        if sec.state == "closed" and self:IsHoveredRect(sec) then
            Inv.Act({a = "search", section = sec.key})
            sec.state = "queued" -- shown until the server answers
            return
        end
    end
    local fb = self.fobButton
    if fb and self:IsHoveredRect(fb) then
        MCC.Net.Send("fob_act", {a = "menu", e = fb.e})
        return
    end
    local b = self.backButton
    if not b then return end
    local mx, my = self:CursorPos()
    if mx >= b.x and mx < b.x + b.w and my >= b.y and my < b.y + b.h then
        Inv.Act({a = "close"})
        Inv.State.open = nil
        self:Rebuild()
    end
end

-- Drag and drop -----------------------------------------------------------------------------

function PANEL:BeginDrag(panel)
    self.drag = {it = panel.it, def = panel.def, loc = panel.loc, panel = panel,
        r = (panel.it.r and not panel.inSlot) and true or false}
    panel:SetVisible(false)
end

-- Dragging something out of the vicinity list: it isn't in any inventory yet (u = 0).
function PANEL:BeginDragRow(rowPanel)
    local r = rowPanel.row
    self.drag = {it = {id = r.id, n = r.n, u = 0, ent = r.ent:EntIndex()}, def = r.def, loc = "v", ent = r.ent:EntIndex(), panel = rowPanel, r = false}
end

-- Zone under the cursor, the cell the item would land on, and whether the server would accept it.
function PANEL:DropTarget(mx, my, it, rot)
    local c = self.c
    local def = Inv.Def(it)
    local v = self.vicZone
    if v and mx >= v.x and mx < v.x + v.w and my >= v.y and my < v.y + v.h then
        -- onto a container in the list: it goes in there
        for _, r in ipairs(self.vicRows or {}) do
            if r.row.kind == "container" and IsValid(r.row.ent) and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
                return {vicinity = true, store = r.row.ent, x = r.x, y = r.y, w = r.w, h = r.h}, 0, 0, it.u ~= 0 or r.row.ent:EntIndex() ~= it.ent
            end
        end
        -- anywhere else in the list: drop it on the ground (already there if it came from the list)
        return v, 0, 0, it.u ~= 0
    end
    for _, z in ipairs(self.Zones) do
        if mx >= z.x and mx < z.x + z.w and my >= z.y and my < z.y + z.h then
            if self:Locked(z.loc) then return z, 0, 0, false end
            if z.slot then
                local occ = z.slots and z.slots[z.key]
                local ok
                if occ and occ.u ~= it.u then
                    ok = Inv.MagTakes(occ, def)
                        or (occ.id == it.id and def.maxStack > 1 and (occ.n or 1) < def.maxStack)
                else
                    ok = Inv.SlotAccepts(z.key, def)
                end
                return z, 0, 0, ok
            end
            local probe = {id = it.id, u = it.u, r = rot}
            local iw, ih = Inv.Size(probe)
            local cx = math.Clamp(math.floor((mx - z.x) / c - iw / 2 + 0.5), 0, math.max(z.cols - iw, 0))
            local cy = math.Clamp(math.floor((my - z.y) / c - ih / 2 + 0.5), 0, math.max(z.rows - ih, 0))
            local ok = Inv.CanFit(z.items, z.cols, z.rows, probe, cx, cy, it.u)
            if not ok and def then
                local ov = Inv.Overlaps(z.items, probe, cx, cy, it.u)
                ok = #ov == 1 and (Inv.MagTakes(ov[1], def)
                    or (ov[1].id == it.id and def.maxStack > 1 and (ov[1].n or 1) < def.maxStack))
            end
            if it.cont and (z.gear == it or (not string.find(z.loc or "", "^c") and not Inv.IsEmptyGear(it))) then ok = false end
            return z, cx, cy, ok
        end
    end
end

function PANEL:EndDrag()
    local d = self.drag
    self.drag = nil
    if IsValid(d.panel) then d.panel:SetVisible(true) end
    local mx, my = self:CursorPos()
    local z, cx, cy, ok = self:DropTarget(mx, my, d.it, d.r)
    if not z or not ok then return end

    if z.store then
        if d.ent then
            Inv.Act({a = "stash", e = d.ent, c = z.store:EntIndex()})
        else
            Inv.Act({a = "store", u = d.it.u, c = z.store:EntIndex()})
        end
        return
    end
    if z.vicinity then
        if d.loc ~= "v" then Inv.Act({a = "drop", u = d.it.u}) end
        return
    end
    if d.ent then
        Inv.Act({a = "take", e = d.ent, to = z.loc, x = cx or 0, y = cy or 0, r = d.r})
        return
    end
    local same = z.loc == d.loc and (z.slot or (cx == d.it.x and cy == d.it.y and d.r == (d.it.r and true or false)))
    if same then return end
    Inv.Act({a = "move", u = d.it.u, to = z.loc, x = cx or 0, y = cy or 0, r = d.r})
end

function PANEL:Think()
    if self.drag and not input.IsMouseDown(MOUSE_LEFT) then self:EndDrag() end
    -- refresh the vicinity list when what's around you changes
    if not self.drag and not Inv.State.open and CurTime() > self.nextScan then
        self.nextScan = CurTime() + 0.5
        local list = Inv.ScanVicinity()
        local sig = VicinitySignature(list)
        if sig ~= self.vicSig then
            self.vicinity, self.vicSig = list, sig
            self:Rebuild()
        end
    end
end

function PANEL:PaintOver(w, h)
    self:DrawSections()
    local d = self.drag
    if not d then return end
    local c = self.c
    local mx, my = self:CursorPos()
    local z, cx, cy, ok = self:DropTarget(mx, my, d.it, d.r)
    local iw, ih = Inv.Size({id = d.it.id, r = d.r})

    if z then
        surface.SetDrawColor(ok and C.good or C.bad)
        if z.slot or z.vicinity then
            surface.DrawRect(z.x, z.y, z.w, z.h)
        else
            surface.DrawRect(z.x + cx * c, z.y + cy * c, iw * c, ih * c)
        end
    end

    local fx, fy = mx - iw * c / 2, my - ih * c / 2
    surface.SetDrawColor(30, 31, 29, 200)
    surface.DrawRect(fx, fy, iw * c, ih * c)
    surface.SetDrawColor(C.itemHover)
    surface.DrawOutlinedRect(fx, fy, iw * c, ih * c)
    draw.SimpleText(ShortName(d.def), "MCC_InvSmall", fx + iw * c / 2, fy + ih * c / 2, C.text,
        TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function PANEL:OnRemove()
    if IsValid(Inv.Inspect) then Inv.Inspect:Remove() end
    Inv.LastClose = CurTime()
    Inv.State.open = nil
    Inv.Panel = nil
    Inv.Act({a = "close"})
end

function PANEL:OnKeyCodePressed(key)
    if key == KEY_R and self.drag then self.drag.r = not self.drag.r end
end

vgui.Register("MCC_Inventory", PANEL, "EditablePanel")

-- fromServer: opened because you searched a body or container (its sync already arrived).
function Inv.OpenUI(fromServer)
    if IsValid(Inv.Panel) then
        Inv.Panel:Rebuild()
        return
    end
    if not fromServer then
        Inv.State.open = nil
        Inv.Act({a = "request"})
    end
    Inv.Panel = vgui.Create("MCC_Inventory")
    MCC.UI.Escapable(Inv.Panel)
end

concommand.Add("mcc_inventory", function()
    if IsValid(Inv.Panel) then Inv.Panel:Remove() else Inv.OpenUI() end
end)

local function TryOpen()
    if IsValid(Inv.Panel) or not Inv.Enabled() then return end
    if CurTime() - Inv.LastClose < 0.25 or gui.IsGameUIVisible() or LocalPlayer():IsTyping() then return end
    Inv.OpenUI()
end

-- Esc closes the inspect window first, then the inventory: lua/mcc/core/cl_ui.lua.
-- The inventory key and Tab close everything. A key held while the inventory opened has to be
-- let go first, so the press that opened it doesn't close it again.
local wasDown = {}
hook.Add("Think", "MCC_InventoryCloseKeys", function()
    if not IsValid(Inv.Panel) then
        if next(wasDown) then wasDown = {} end
        return
    end
    for _, key in ipairs({cvKey:GetInt(), KEY_TAB}) do
        local down = input.IsKeyDown(key)
        if down and wasDown[key] == false then
            wasDown = {}
            Inv.Panel:Remove()
            return
        end
        wasDown[key] = down
    end
end)

-- Multiplayer: the client sees its own key presses.
hook.Add("PlayerButtonDown", "MCC_InventoryKey", function(ply, key)
    if game.SinglePlayer() or not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
    if key == cvKey:GetInt() then TryOpen() end
end)

-- Singleplayer: GMod only runs key hooks on the server, which tells us to open.
MCC.Net.Receive("inv_key", function() TryOpen() end)

-- Inventory key binder (Q menu > Utilities > MCC > Inventory).
hook.Add("PopulateToolMenu", "MCC_InventoryControls", function()
    spawnmenu.AddToolMenuOption("Utilities", "MCC", "mcc_inventory_controls", "Inventory", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Inventory key")
        local binder = vgui.Create("DBinder", panel)
        binder:SetTall(28)
        binder:SetValue(cvKey:GetInt())
        function binder:OnChange(num) RunConsoleCommand("mcc_inventory_key", tostring(num)) end
        panel:AddItem(binder)
        panel:ControlHelp("Or bind any key in the console: bind i mcc_inventory")

        panel:NumSlider("Show worn gear on bodies within (units, 0 = all)", "mcc_worn_body_distance", 0, 10000, 0)
        panel:ControlHelp("Gear models on far bodies cost frames; closer ones get theirs back.")
        panel:Help("Server settings (host or admin)")
        panel:CheckBox("Use the MCC inventory", "mcc_inv_enabled")
        panel:CheckBox("Guns reload only from loaded magazines", "mcc_mags_required")
        panel:CheckBox("NPCs leave lootable bodies", "mcc_inv_npc_bodies")
        panel:NumSlider("Vicinity range", "mcc_inv_vicinity_range", 60, 600, 0)
        panel:CheckBox("Looted bodies despawn", "mcc_inv_body_cleanup")
        panel:NumSlider("Looted body despawns after (seconds)", "mcc_inv_body_looted_time", 0, 7200, 0)
        panel:NumSlider("Any body's max lifetime (0 = none)", "mcc_inv_body_lifetime", 0, 7200, 0)
        panel:NumSlider("Most bodies on the map (0 = no limit)", "mcc_inv_body_max", 0, 300, 0)
        panel:NumSlider("Freeze settled bodies after (seconds, 0 = never)", "mcc_inv_body_freeze", 0, 600, 0)
        panel:NumSlider("Dropped item lifetime (seconds)", "mcc_inv_item_lifetime", 0, 7200, 0)
    end)
end)
