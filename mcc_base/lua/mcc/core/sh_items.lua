-- The item registry: the single source of truth for every item MCC knows about.
-- The inventory, traders, loot tables and expansions all read item definitions from here.
--
-- Register items inside the hook (registrations made anywhere else are cleared on boot and reload):
--
--   hook.Add("MCC_RegisterItems", "my_addon", function(Items)
--       Items.Register("weapon_smg1", {
--           name = "SMG", kind = "weapon", class = "weapon_smg1",
--           w = 3, h = 2, weight = 2.9, price = 900,
--           data = {slot = "primary", ammo = "SMG1", magFed = true, mag = "mag_smg1"},
--       })
--   end)
--
-- Server owners change or add items without Lua through data/mcc/items.json or the mcc_item_* commands.

MCC.Items = MCC.Items or {}
local Items = MCC.Items

-- Item kinds. stackable = several fit in one cell up to maxStack.
Items.Kinds = Items.Kinds or {
    weapon     = {stackable = false},
    ammo       = {stackable = true},
    mag        = {stackable = false},
    gear       = {stackable = false}, -- rigs, backpacks, pouches
    armor      = {stackable = false},
    consumable = {stackable = false},
    resource   = {stackable = true},  -- JMod resources and other materials
    misc       = {stackable = true},  -- loot, intel, junk
}

-- Expansions can add kinds, e.g. Items.RegisterKind("attachment", {stackable = false}).
function Items.RegisterKind(kind, opts)
    Items.Kinds[kind] = {stackable = opts and opts.stackable or false}
end

local function DefaultStack(def)
    local k = Items.Kinds[def.kind]
    if k and k.stackable then
        local cv = GetConVar("mcc_default_stack")
        return cv and cv:GetInt() or 50
    end
    return 1
end

Items.Schema = {
    name     = {type = "string", required = true},
    kind     = {type = "string", required = true, check = function(v)
        return Items.Kinds[v] ~= nil, "is not a known item kind"
    end},
    class    = {type = "string"},                       -- entity, weapon or ammo type this item maps to
    w        = {type = "number", default = 1, integer = true, min = 1, max = 10},
    h        = {type = "number", default = 1, integer = true, min = 1, max = 10},
    maxStack = {type = "number", default = DefaultStack, integer = true, min = 1},
    weight   = {type = "number", default = 0.1, min = 0},  -- kg
    price    = {type = "number", min = 0},              -- base Supply value; nil = can't be bought or sold
    model    = {type = "string", default = "models/props_junk/cardboard_box004a.mdl"},
    category = {type = "string", default = function(def) return def.kind end},
    rarity   = {type = "string", default = "common", enum = {"common", "uncommon", "rare", "epic"}},
    tags     = {type = "table", default = {}},
    data     = {type = "table", default = {}},          -- kind-specific settings
}

Items.Reg = Items.Reg or MCC.Registry.New("item", Items.Schema)
Items.Base = Items.Base or {}        -- definitions as registered by Lua, before data-file overrides
Items.Overrides = Items.Overrides or {} -- contents of data/mcc/items.json
Items.ByClass = Items.ByClass or {}

local registering = false

function Items.BeginRegistration()
    registering = true
    Items.Reg:Clear()
end

function Items.EndRegistration()
    registering = false
    Items.Base = {}
    for id, def in pairs(Items.Reg:All()) do
        Items.Base[id] = table.Copy(def)
    end
    Items.RebuildIndex()
end

function Items.Register(id, def)
    if not registering then
        MCC.Warn("Item '%s' registered outside the MCC_RegisterItems hook; it will be lost on reload", tostring(id))
    end
    local built = Items.Reg:Register(id, def)
    if built and not registering then Items.RebuildIndex() end
    return built
end

function Items.Get(id) return Items.Reg:Get(id) end
function Items.All() return Items.Reg:All() end
function Items.Count() return Items.Reg:Count() end
function Items.IDs() return Items.Reg:IDs() end

function Items.RebuildIndex()
    Items.ByClass = {}
    Items.Grenades = {} -- weapon items that are grenades (ammo syncing walks these, not the whole registry)
    for id, def in pairs(Items.Reg:All()) do
        if def.class then
            Items.ByClass[def.class] = Items.ByClass[def.class] or id
            if def.kind == "weapon" and def.data and def.data.slot == "grenade" then Items.Grenades[#Items.Grenades + 1] = def end
        end
    end
    table.sort(Items.Grenades, function(a, b) return a.id < b.id end)
end

-- Grenade weapon items, from the index above.
function Items.GrenadeDefs()
    if not Items.Grenades then Items.RebuildIndex() end
    return Items.Grenades
end

-- The item id that represents a weapon/entity class, if one is registered.
function Items.FromClass(class)
    return Items.ByClass[class]
end

function Items.MaxStack(id)
    local def = Items.Get(id)
    return def and def.maxStack or 1
end

-- Price after the server-wide multiplier, or nil if the item isn't for sale.
function Items.Price(id)
    local def = Items.Get(id)
    if not def or not def.price then return nil end
    return math.max(0, math.floor(def.price * MCC.Config.Get("price_mult") + 0.5))
end

-- Default grid sizes by weapon hold type, for weapons with no definition of their own
-- (sizes from the original Tarkov inventory addon).
Items.HoldTypeSizes = {
    pistol = {2, 1}, revolver = {2, 1}, duel = {2, 1},
    smg = {3, 2},
    ar2 = {5, 2}, rifle = {5, 2}, crossbow = {5, 2},
    shotgun = {5, 1},
    grenade = {1, 1},
    rpg = {5, 2},
    melee = {2, 1}, melee2 = {3, 1}, knife = {1, 2},
}

local HOLSTER_HOLDS = {pistol = true, revolver = true, duel = true}
local MELEE_HOLDS = {melee = true, melee2 = true, knife = true, fist = true}
local GRENADE_HOLDS = {grenade = true, slam = true}

-- A starting definition for a scripted weapon, read from its SWEP table, for mcc_item_addweapon.
-- Returns nil if the class isn't a SWEP. Weapons are only inventory items once registered.
function Items.DefaultsForWeapon(class)
    local swep = weapons.Get(class)
    if not swep then return nil end
    local hold = string.lower(swep.HoldType or "")
    local size = Items.HoldTypeSizes[hold] or {2, 2}

    local slot = "primary"
    if HOLSTER_HOLDS[hold] then slot = "holster"
    elseif MELEE_HOLDS[hold] then slot = "melee"
    elseif GRENADE_HOLDS[hold] then slot = "grenade"
    elseif swep.Slot == 1 then slot = "holster"
    elseif swep.Slot == 0 then slot = "melee" end

    local primary = istable(swep.Primary) and swep.Primary or {}
    local ammo = isstring(primary.Ammo) and primary.Ammo or nil
    if ammo == "" or (ammo and string.lower(ammo) == "none") then ammo = nil end
    local clip = tonumber(primary.ClipSize) or 0

    local model = swep.WorldModel
    if not isstring(model) or model == "" then model = nil end
    local name = (isstring(swep.PrintName) and swep.PrintName ~= "") and swep.PrintName or class
    return {
        name = name,
        kind = "weapon", class = class,
        w = size[1], h = size[2],
        weight = math.Round(size[1] * size[2] * 0.35, 2),
        model = model,
        category = isstring(swep.Category) and swep.Category or "weapon",
        -- "loose": reloads from loose rounds in the rig and pockets, which works with any weapon base
        data = {slot = slot, ammo = ammo, clip = clip > 0 and clip or nil, feed = (ammo and clip > 0) and "loose" or nil},
    }
end

-- The name to show: names from weapon packs are often "#language_keys".
function Items.DisplayName(def)
    local n = def and def.name or "?"
    if CLIENT and string.sub(n, 1, 1) == "#" then n = language.GetPhrase(string.sub(n, 2)) end
    return n
end

-- Data-file overrides (server) ---------------------------------------------------------
-- items.json maps an item id to:
--   a partial table -> merged over the Lua definition ({"price": 1500})
--   a full table    -> adds a new item (needs name and kind)
--   false           -> removes the item

if SERVER then
    function Items.ApplyOverrides()
        local overrides = MCC.Data.ReadJSON("items.json") or {}
        Items.Overrides = overrides
        local changed, added, removed = 0, 0, 0

        for id, patch in pairs(overrides) do
            if patch == false then
                if Items.Reg:Remove(id) then removed = removed + 1 end
            elseif type(patch) == "table" then
                local base = Items.Base[id]
                local merged = base and table.Merge(table.Copy(base), table.Copy(patch)) or patch
                local ok, err = Items.Reg:Build(id, merged)
                if ok then
                    Items.Reg:Register(id, merged)
                    if base then changed = changed + 1 else added = added + 1 end
                else
                    MCC.Error("items.json: '%s' ignored: %s", id, err)
                end
            else
                MCC.Error("items.json: '%s' must be a table or false", id)
            end
        end

        Items.RebuildIndex()
        if changed + added + removed > 0 then
            MCC.Log("items.json: %d changed, %d added, %d removed", changed, added, removed)
        end
    end

    -- Saves one override entry (nil clears it) and re-applies everything.
    function Items.SetOverride(id, value)
        Items.Overrides[id] = value
        MCC.Data.WriteJSON("items.json", Items.Overrides)
        Items.Rebuild()
    end

    -- Re-runs Lua registration and the data file, then updates every client.
    function Items.Rebuild()
        Items.BeginRegistration()
        hook.Run("MCC_RegisterItems", Items)
        Items.EndRegistration()
        Items.ApplyOverrides()
        Items.Sync()
        hook.Run("MCC_ItemsChanged")
    end

    -- Sends the final registry to one player, or to everyone when ply is nil.
    function Items.Sync(ply)
        MCC.Net.Send("items_sync", {defs = MCC.Util.JSONSafe(Items.Reg:All())}, ply)
    end

    local lastRequest = {}
    MCC.Net.Receive("items_request", function(_, ply)
        if (lastRequest[ply] or 0) > CurTime() then return end
        lastRequest[ply] = CurTime() + 10
        Items.Sync(ply)
    end, {allowClient = true, maxBytes = 256})

    hook.Add("PlayerDisconnected", "MCC_ItemsRequestCleanup", function(ply) lastRequest[ply] = nil end)
end

if CLIENT then
    MCC.Net.Receive("items_sync", function(data)
        Items.Reg:Clear()
        for id, def in pairs(data.defs or {}) do
            Items.Reg:Register(id, def)
        end
        Items.RebuildIndex()
        hook.Run("MCC_ItemsSynced")
        hook.Run("MCC_ItemsChanged")
    end)

    hook.Add("InitPostEntity", "MCC_ItemsRequest", function()
        MCC.Net.Send("items_request", {})
    end)
end
