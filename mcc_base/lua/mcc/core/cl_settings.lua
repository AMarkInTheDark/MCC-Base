-- Q menu > Utilities > MCC > Server Settings: every MCC setting in one place, grouped by system.
-- Admins change them here (the server checks); everyone can see them. Your own client options are
-- at the bottom.
--
-- Expansions add their own section and player options (client side, at file load):
--   MCC.Settings.AddGroup("AI (stealth and tactics)", {"ai_"})        -- settings named mcc_ai_*
--   MCC.Settings.AddClientOption("mcc_ai_text", "Show what NPCs are doing above them")

MCC.Settings = MCC.Settings or {}

local GROUPS = {
    {"Core", {"debug", "price_mult", "save_interval", "jmod_integration", "compat_notice", "default_stack"}},
    {"Pickup and drop", {"pickup_", "drop_"}},
    {"Inventory", {"inv_", "mags_", "search_", "weapon_"}},
    {"JMod", {"jmod_"}},
    {"Extraction", {"extract_"}},
    {"FOB", {"fob_"}},
    {"Building", {"build_"}},
    {"Gameplay", {"hide_killfeed", "hl2_"}},
}

local CLIENT_OPTIONS = {
    {"mcc_pickup_prompt", "Show the pickup prompt"},
    {"mcc_worn_draw", "Draw worn rigs, backpacks and armor"},
    {"mcc_worn_firstperson", "Draw your own worn gear in first person"},
    {"mcc_extract_marker", "Show supply drop markers"},
    {"mcc_fob_ring", "Show FOB zone rings on the ground"},
}

-- A section for settings whose names start with one of the prefixes (or equal one without a "_" end).
function MCC.Settings.AddGroup(title, prefixes)
    for _, g in ipairs(GROUPS) do
        if g[1] == title then
            g[2] = prefixes
            return
        end
    end
    GROUPS[#GROUPS + 1] = {title, prefixes}
end

-- A checkbox for one of the player's own convars, under "Your own options".
function MCC.Settings.AddClientOption(cvar, label)
    for _, o in ipairs(CLIENT_OPTIONS) do
        if o[1] == cvar then return end
    end
    CLIENT_OPTIONS[#CLIENT_OPTIONS + 1] = {cvar, label}
end

local function GroupOf(name)
    for i, g in ipairs(GROUPS) do
        for _, p in ipairs(g[2]) do
            if name == p or (string.sub(p, -1) == "_" and string.sub(name, 1, #p) == p) then return i end
        end
    end
    return #GROUPS + 1
end

local function Set(name, value)
    MCC.Net.Send("config_set", {name = name, value = value})
end

local function Pretty(name)
    return (string.gsub(string.gsub(name, "_", " "), "^%l", string.upper))
end

local function Build(panel)
    panel:ClearControls()
    panel:Help("Every MCC server setting. Only admins can change them; changes apply right away and are saved.")
    panel:Button("Toggle FOB range bubbles", "mcc_fob_range")

    local buckets = {}
    for _, name in ipairs(MCC.Config.Order) do
        local i = GroupOf(name)
        buckets[i] = buckets[i] or {}
        table.insert(buckets[i], name)
    end

    for i = 1, #GROUPS + 1 do
        local list = buckets[i]
        if list then
            local cat = vgui.Create("DCollapsibleCategory", panel)
            cat:SetLabel(GROUPS[i] and GROUPS[i][1] or "Other")
            cat:SetExpanded(i <= 1)
            local body = vgui.Create("DPanelList", cat)
            body:SetAutoSize(true)
            body:SetSpacing(4)
            body:SetPadding(6)
            cat:SetContents(body)
            panel:AddItem(cat)
            for _, name in ipairs(list) do
                local def = MCC.Config.Defs[name]
                local cvar = "mcc_" .. name
                local ctrl
                if def.kind == "boolean" then
                    ctrl = vgui.Create("DCheckBoxLabel")
                    ctrl:SetText(Pretty(name))
                    ctrl:SetDark(true)
                    ctrl:SetValue(def.cvar:GetBool())
                    ctrl.OnChange = function(_, v) Set(name, v and 1 or 0) end
                elseif def.kind == "number" then
                    ctrl = vgui.Create("DNumSlider")
                    ctrl:SetText(Pretty(name))
                    ctrl:SetDark(true)
                    ctrl:SetMin(def.min or 0)
                    ctrl:SetMax(def.max or math.max(100, def.default * 4))
                    local whole = math.floor(def.default) == def.default and (def.max or 0) - (def.min or 0) >= 10
                    ctrl:SetDecimals(whole and 0 or 2)
                    ctrl:SetValue(def.cvar:GetFloat())
                    local pending
                    ctrl.OnValueChanged = function(_, v)
                        pending = v
                        timer.Create("MCC_Setting_" .. name, 0.4, 1, function() Set(name, pending) end)
                    end
                else
                    ctrl = vgui.Create("DPanel")
                    ctrl:SetTall(42)
                    ctrl.Paint = function() end
                    local l = vgui.Create("DLabel", ctrl)
                    l:Dock(TOP)
                    l:SetDark(true)
                    l:SetText(Pretty(name) .. " (press Enter to apply)")
                    local t = vgui.Create("DTextEntry", ctrl)
                    t:Dock(TOP)
                    t:SetValue(def.cvar:GetString())
                    t.OnEnter = function(self) Set(name, self:GetValue()) end
                end
                ctrl:SetTooltip(cvar .. "\n" .. (def.help or ""))
                body:AddItem(ctrl)
            end
        end
    end

    panel:Help("")
    panel:Help("Your own options:")
    for _, o in ipairs(CLIENT_OPTIONS) do
        if GetConVar(o[1]) then panel:CheckBox(o[2], o[1]) end
    end
end

hook.Add("PopulateToolMenu", "MCC_SettingsMenu", function()
    spawnmenu.AddToolMenuOption("Utilities", "MCC", "mcc_server_settings", "Server Settings", "", "", Build)
end)
