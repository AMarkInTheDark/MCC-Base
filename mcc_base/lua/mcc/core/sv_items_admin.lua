-- Item commands for server owners. Every change is saved to data/mcc/items.json and sent to clients.

local Items = MCC.Items

local EDITABLE = {
    name = true, kind = true, class = true, w = true, h = true, maxStack = true,
    weight = true, price = true, model = true, category = true, rarity = true,
}

-- What the item would look like with this patch, or nil and an error.
local function Preview(id, patch)
    local base = Items.Base[id]
    local merged = base and table.Merge(table.Copy(base), table.Copy(patch)) or patch
    return Items.Reg:Build(id, merged)
end

-- Sets field (or data.<key>) in a copy of the item's current override.
local function PatchWith(id, field, value)
    local current = Items.Overrides[id]
    local patch = istable(current) and table.Copy(current) or {}
    local sub = string.match(field, "^data%.([%w_]+)$")
    if sub then
        patch.data = patch.data or {}
        patch.data[sub] = value
    else
        patch[field] = value
    end
    return patch
end

MCC.Command("item_list", "MCC Moderator", "[filter]", "Lists item ids, optionally only those containing filter.",
function(ply, args)
    local filter = args[1] and string.lower(args[1])
    local shown = 0
    for _, id in ipairs(Items.IDs()) do
        local def = Items.Get(id)
        if not filter or string.find(string.lower(id .. " " .. def.name), filter, 1, true) then
            MCC.Util.Reply(ply, "%-28s %-10s %dx%d  price %s", id, def.kind, def.w, def.h, tostring(def.price or "-"))
            shown = shown + 1
        end
    end
    MCC.Util.Reply(ply, "%d of %d items", shown, Items.Count())
end)

MCC.Command("item_info", "MCC Moderator", "<id>", "Shows every field of an item.", function(ply, args)
    local def = Items.Get(args[1] or "")
    if not def then return MCC.Util.Reply(ply, "No item '%s'.", tostring(args[1])) end
    MCC.Util.Reply(ply, "%s", util.TableToJSON(MCC.Util.JSONSafe(def), true))
    if Items.Overrides[def.id] ~= nil then MCC.Util.Reply(ply, "(changed by items.json)") end
end)

MCC.Command("item_set", "MCC Admin", "<id> <field|data.key> <value>",
"Changes one field of an item, e.g. mcc_item_set weapon_ar2 price 1500.", function(ply, args)
    local id, field, raw = args[1], args[2], args[3]
    if not (id and field and raw) then return MCC.Util.Reply(ply, "Usage: mcc_item_set <id> <field> <value>") end
    if not Items.Base[id] and not istable(Items.Overrides[id]) then
        return MCC.Util.Reply(ply, "No item '%s'. Use mcc_item_addweapon for new weapons.", id)
    end
    if not EDITABLE[field] and not string.match(field, "^data%.[%w_]+$") then
        return MCC.Util.Reply(ply, "Can't edit '%s'. Editable: %s, data.<key>", field,
            table.concat(table.GetKeys(EDITABLE), ", "))
    end

    local value = MCC.Util.ParseValue(raw)
    if raw == "nil" then value = nil end
    local patch = PatchWith(id, field, value)
    local ok, err = Preview(id, patch)
    if not ok then return MCC.Util.Reply(ply, "Not changed: %s", err) end

    Items.SetOverride(id, patch)
    MCC.Util.Reply(ply, "%s.%s = %s", id, field, tostring(value))
end)

MCC.Command("item_remove", "MCC Admin", "<id>", "Removes an item from the game (saved in items.json).",
function(ply, args)
    local id = args[1]
    if not id or not Items.Get(id) then return MCC.Util.Reply(ply, "No item '%s'.", tostring(id)) end
    if Items.Base[id] then
        Items.SetOverride(id, false)
    else
        Items.SetOverride(id, nil) -- added by items.json only: just delete the entry
    end
    MCC.Util.Reply(ply, "Removed %s.", id)
end)

MCC.Command("item_reset", "MCC Admin", "<id>", "Undoes every items.json change to an item.", function(ply, args)
    local id = args[1]
    if not id or Items.Overrides[id] == nil then return MCC.Util.Reply(ply, "'%s' has no changes.", tostring(id)) end
    Items.SetOverride(id, nil)
    MCC.Util.Reply(ply, "Reset %s.", id)
end)

MCC.Command("item_addweapon", "MCC Admin", "<weapon class> [price]",
"Adds any installed SWEP as an item, sized from its hold type.", function(ply, args)
    local class, price = args[1], tonumber(args[2] or "")
    if not class then return MCC.Util.Reply(ply, "Usage: mcc_item_addweapon <weapon class> [price]") end

    local existing = Items.FromClass(class)
    if existing then
        if price then
            Items.SetOverride(existing, PatchWith(existing, "price", price))
            return MCC.Util.Reply(ply, "%s is already item '%s'; price set to %d.", class, existing, price)
        end
        return MCC.Util.Reply(ply, "%s is already item '%s'.", class, existing)
    end

    local def = Items.DefaultsForWeapon(class)
    if not def then return MCC.Util.Reply(ply, "'%s' isn't an installed scripted weapon.", class) end
    def.price = price
    local ok, err = Items.Reg:Build(class, def)
    if not ok then return MCC.Util.Reply(ply, "Couldn't add: %s", err) end

    Items.SetOverride(class, MCC.Util.JSONSafe(def))
    MCC.Util.Reply(ply, "Added %s as a %dx%d %s weapon. Adjust it with mcc_item_set.", class, def.w, def.h, def.data.slot)
end)
