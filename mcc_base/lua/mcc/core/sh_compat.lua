-- Optional integrations with other addons.
-- MCC works without any of them; features that need one check MCC.Compat.Has(id) first.
--
-- Expansions register their own (e.g. ZBase support) in the MCC_Loaded hook:
--   MCC.Compat.Register("zbase", {
--       name = "ZBase", detect = function() return ZBaseSpawnZBaseNPC ~= nil end,
--   })

MCC.Compat = MCC.Compat or {}
MCC.Compat.Defs = MCC.Compat.Defs or {}
MCC.Compat.Found = MCC.Compat.Found or {}

-- opts.name:       display name
-- opts.detect:     function returning true when the addon is installed
-- opts.cvar:       optional MCC setting name that turns the integration off when false
-- opts.encouraged: tell admins on join when it's missing
-- opts.url:        where to get it
-- opts.pitch:      one line on what it adds, shown in the admin notice
function MCC.Compat.Register(id, opts)
    MCC.Compat.Defs[id] = opts
end

function MCC.Compat.DetectAll()
    for id, def in pairs(MCC.Compat.Defs) do
        local ok, found = pcall(def.detect)
        MCC.Compat.Found[id] = ok and found and true or false
        if MCC.Compat.Found[id] then
            MCC.Log("%s detected", def.name)
        elseif def.encouraged then
            MCC.Warn("%s not installed. %s %s", def.name, def.pitch or "", def.url or "")
        end
    end
end

-- True when the addon is installed and its integration setting (if any) is on.
function MCC.Compat.Has(id)
    if not MCC.Compat.Found[id] then return false end
    local def = MCC.Compat.Defs[id]
    if def and def.cvar then return MCC.Config.Get(def.cvar) end
    return true
end

-- Installed, regardless of whether the integration is switched off.
function MCC.Compat.Installed(id)
    return MCC.Compat.Found[id] or false
end

MCC.Compat.Register("jmod", {
    name = "JMod",
    detect = function()
        return istable(JMod) and istable(JMod.EZ_RESOURCE_TYPES)
    end,
    cvar = "jmod_integration",
    encouraged = true,
    url = "https://steamcommunity.com/sharedfiles/filedetails/?id=1919689921",
    pitch = "MCC works without it, but JMod adds resource gathering, refining, FOB machines and supply drops.",
})

-- Admin notice for missing encouraged addons --------------------------------------------

if SERVER then
    hook.Add("PlayerInitialSpawn", "MCC_CompatNotice", function(ply)
        timer.Simple(8, function()
            if not IsValid(ply) or not MCC.Ready or not MCC.Config.Get("compat_notice") then return end
            MCC.Perms.Check(ply, "MCC Admin", function(allowed)
                if not allowed or not IsValid(ply) then return end
                for id, def in pairs(MCC.Compat.Defs) do
                    if def.encouraged and not MCC.Compat.Installed(id) then
                        ply:ChatPrint(string.format("[MCC] %s isn't installed. %s", def.name, def.pitch or ""))
                        if def.url then ply:ChatPrint("[MCC] " .. def.url) end
                    end
                end
            end)
        end)
    end)
end
