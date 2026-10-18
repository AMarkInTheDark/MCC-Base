-- MCC Base: loader and boot sequence.
--
-- Expansion addons (ZBase support, weapon bases, events) never edit these files.
-- They hook into the boot sequence instead, which works whatever order GMod loads addons in:
--
--   hook.Add("MCC_Loaded", "my_expansion", function(MCC) ... end)          -- MCC exists, nothing registered yet
--   hook.Add("MCC_RegisterItems", "my_expansion", function(Items) ... end) -- add item definitions
--   hook.Add("MCC_Ready", "my_expansion", function(MCC) ... end)           -- everything loaded, data files applied
--
-- If your code may run after boot (Lua refresh), use MCC.OnReady(fn) once MCC exists.

AddCSLuaFile()

MCC = MCC or {}
MCC.Version = "0.17.0"
MCC.API_VERSION = 1
MCC.Ready = MCC.Ready or false

-- Includes a file in the right realm, chosen by its prefix: sv_ (server), cl_ (client), anything else shared.
function MCC.LoadFile(path)
    local prefix = string.sub(string.GetFileFromFilename(path), 1, 3)
    if prefix == "sv_" then
        if SERVER then include(path) end
    elseif prefix == "cl_" then
        if SERVER then AddCSLuaFile(path) else include(path) end
    else
        if SERVER then AddCSLuaFile(path) end
        include(path)
    end
end

local CORE = {
    "mcc/core/sh_util.lua",
    "mcc/core/sh_config.lua",
    "mcc/core/sh_perms.lua",
    "mcc/core/sh_net.lua",
    "mcc/core/sh_registry.lua",
    "mcc/core/sh_items.lua",
    "mcc/core/sv_data.lua",
    "mcc/core/sh_compat.lua",
    "mcc/core/sv_commands.lua",
    "mcc/core/sv_settings.lua",
    "mcc/core/cl_settings.lua",
    "mcc/core/cl_ui.lua",
    "mcc/core/sh_gameplay.lua",
    "mcc/core/sv_items_admin.lua",
    "mcc/content/sh_items_hl2.lua",
    "mcc/pickup/sh_pickup.lua",
    "mcc/pickup/sv_pickup.lua",
    "mcc/pickup/cl_pickup.lua",
    "mcc/compat/sv_tarkov_inventory.lua",
    "mcc/inventory/sh_inventory.lua",
    "mcc/inventory/sh_worn.lua",
    "mcc/inventory/sv_inventory.lua",
    "mcc/inventory/sv_inventory_search.lua",
    "mcc/inventory/sv_inventory_world.lua",
    "mcc/inventory/cl_inventory.lua",
    "mcc/inventory/cl_inspect.lua",
    "mcc/compat/sh_jmod_resources.lua",
    "mcc/compat/sv_jmod_recipes.lua",
    "mcc/extract/sh_extract.lua",
    "mcc/extract/sv_extract.lua",
    "mcc/extract/cl_extract.lua",
    "mcc/fob/sh_fob.lua",
    "mcc/fob/sv_fob.lua",
    "mcc/fob/cl_fob.lua",
    "mcc/build/sh_build.lua",
    "mcc/build/sv_build.lua",
    "mcc/build/cl_build.lua",
}

for _, path in ipairs(CORE) do
    MCC.LoadFile(path)
end

-- Runs fn now if MCC has finished booting, otherwise once it does.
function MCC.OnReady(id, fn)
    if MCC.Ready then
        fn(MCC)
    else
        hook.Add("MCC_Ready", id, fn)
    end
end

-- Boot runs after every addon's autorun files, so expansions have had the chance to add their hooks.
function MCC.Boot()
    hook.Run("MCC_Loaded", MCC)

    MCC.Items.BeginRegistration()
    hook.Run("MCC_RegisterItems", MCC.Items)
    MCC.Items.EndRegistration()

    if SERVER then
        MCC.Data.Init()
        MCC.Items.ApplyOverrides()
    end

    MCC.Compat.DetectAll()

    MCC.Ready = true
    MCC.Log("MCC Base %s ready (API %d, %d items)", MCC.Version, MCC.API_VERSION, MCC.Items.Count())
    hook.Run("MCC_Ready", MCC)
end

hook.Add("Initialize", "MCC_Boot", function()
    MCC.Boot()
end)
