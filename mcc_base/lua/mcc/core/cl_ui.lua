-- Esc closes MCC's menus. Every MCC window registers itself with MCC.UI.Escapable(panel); Esc closes
-- the most recently opened one that's still up (the inspect window before the inventory, a confirm box
-- before the FOB menu) instead of opening the pause menu. With no MCC window up, Esc works as usual.

MCC.UI = MCC.UI or {}
local UI = MCC.UI
UI.Stack = UI.Stack or {}

-- Registers a window (a DFrame, the inventory...). onEscape(panel) can replace the default Remove.
function UI.Escapable(panel, onEscape)
    if not IsValid(panel) then return panel end
    for i = #UI.Stack, 1, -1 do
        if UI.Stack[i].panel == panel then table.remove(UI.Stack, i) end
    end
    UI.Stack[#UI.Stack + 1] = {panel = panel, fn = onEscape}
    return panel
end

local function Prune()
    for i = #UI.Stack, 1, -1 do
        local p = UI.Stack[i].panel
        if not IsValid(p) or (p.IsVisible and not p:IsVisible()) then table.remove(UI.Stack, i) end
    end
end

function UI.AnyOpen()
    Prune()
    return #UI.Stack > 0
end

-- Closes the top window. True if there was one.
function UI.CloseTop()
    Prune()
    local top = table.remove(UI.Stack)
    if not top then return false end
    if top.fn then top.fn(top.panel) else top.panel:Remove() end
    return true
end

hook.Add("OnPauseMenuShow", "MCC_Escape", function()
    if UI.CloseTop() then return false end
end)

-- Builds without OnPauseMenuShow open the pause menu anyway: hide it and close the window instead.
hook.Add("Think", "MCC_EscapeFallback", function()
    if #UI.Stack > 0 and gui.IsGameUIVisible() and UI.AnyOpen() then
        gui.HideGameUI()
        UI.CloseTop()
    end
end)
