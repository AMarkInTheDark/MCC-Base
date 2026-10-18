-- Client side of pickup and drop: the drop key, the "[E] Pick up" prompt, and the settings page
-- (Q menu > Utilities > MCC > Controls).

local P = MCC.Pickup

local cvDropKey = CreateClientConVar("mcc_drop_key", tostring(KEY_G), true, true,
    "Key that drops your active weapon (a KEY_ number, 0 = none).")
local cvPrompt = CreateClientConVar("mcc_pickup_prompt", "1", true, false,
    "Show the [E] Pick up prompt when looking at a weapon or item.")

local function CanUseKeys(ply)
    return not ply:IsTyping() and not gui.IsGameUIVisible()
        and not vgui.CursorVisible() and not IsValid(vgui.GetKeyboardFocus())
end

-- Multiplayer only; in singleplayer the server catches the key (sv_pickup.lua).
hook.Add("PlayerButtonDown", "MCC_DropKey", function(ply, button)
    if game.SinglePlayer() or not IsFirstTimePredicted() or ply ~= LocalPlayer() then return end
    local key = cvDropKey:GetInt()
    if key == 0 or button ~= key or not CanUseKeys(ply) then return end
    RunConsoleCommand("mcc_drop")
end)

-- Prompt ------------------------------------------------------------------------------

surface.CreateFont("MCC_Prompt", {font = "Roboto", size = 20, weight = 600})
surface.CreateFont("MCC_PromptSub", {font = "Roboto", size = 15, weight = 500})

local TEXT = Color(235, 235, 235)
local OUTLINE = Color(0, 0, 0, 220)
local SUBTEXT = Color(175, 175, 168)

hook.Add("HUDPaint", "MCC_PickupPrompt", function()
    if not cvPrompt:GetBool() or not P.Active() then return end
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end

    local ent, kind = P.FindTarget(ply)
    if not ent then return end

    local useKey = string.upper(input.LookupBinding("+use", true) or "E")
    local text, sub = P.PromptText(ent, kind)
    local y = ScrH() * 0.58
    draw.SimpleTextOutlined("[" .. useKey .. "] " .. text, "MCC_Prompt",
        ScrW() / 2, y, TEXT, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, OUTLINE)
    if sub and sub ~= "" then
        draw.SimpleTextOutlined(sub, "MCC_PromptSub", ScrW() / 2, y + 20, SUBTEXT,
            TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 1, OUTLINE)
    end
end)

-- Settings page ------------------------------------------------------------------------

hook.Add("PopulateToolMenu", "MCC_ControlsMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "MCC", "mcc_controls", "Controls", "", "", function(panel)
        panel:ClearControls()
        panel:Help("Drop weapon key")
        local binder = vgui.Create("DBinder", panel)
        binder:SetTall(28)
        binder:SetValue(cvDropKey:GetInt())
        function binder:OnChange(num) RunConsoleCommand("mcc_drop_key", tostring(num)) end
        panel:AddItem(binder)
        panel:ControlHelp("You can also bind it yourself in the console: bind g mcc_drop")

        panel:CheckBox("Show the pick-up prompt", "mcc_pickup_prompt")

        panel:Help("Server settings (host or admin)")
        panel:CheckBox("Pick up weapons with E only", "mcc_pickup_use")
        panel:CheckBox("Pick up items with E only", "mcc_pickup_items_use")
        panel:CheckBox("Allow dropping weapons", "mcc_drop_enabled")
        panel:NumSlider("Pick-up reach", "mcc_pickup_range", 40, 300, 0)
    end)
end)
