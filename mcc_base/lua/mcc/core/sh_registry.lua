-- Generic registry with schema validation. Items use it now; traders, factions and events will too.
--
--   local Reg = MCC.Registry.New("factions", {
--       name  = {type = "string", required = true},
--       color = {type = "table", default = function() return {255, 255, 255} end},
--   })
--   Reg:Register("militia", {name = "Local Militia"})
--
-- Field rules: type ("string" | "number" | "boolean" | "table"), required, default (value or
-- function(def) returning one), min, max, integer, enum (list), check (function(value, def) -> ok, err).
-- Fields not in the schema are kept as they are, so expansions can attach their own data.

MCC.Registry = MCC.Registry or {}

local Registry = {}
Registry.__index = Registry

function MCC.Registry.New(name, schema)
    return setmetatable({name = name, schema = schema, defs = {}, count = 0}, Registry)
end

local function CheckField(key, rule, value, def)
    if value == nil then
        if rule.required then return false, "'" .. key .. "' is required" end
        return true
    end
    if rule.type and type(value) ~= rule.type then
        return false, string.format("'%s' must be a %s (got %s)", key, rule.type, type(value))
    end
    if rule.type == "number" then
        if rule.integer and value ~= math.floor(value) then
            return false, "'" .. key .. "' must be a whole number"
        end
        if rule.min and value < rule.min then return false, string.format("'%s' must be at least %s", key, rule.min) end
        if rule.max and value > rule.max then return false, string.format("'%s' must be at most %s", key, rule.max) end
    end
    if rule.enum then
        local ok = false
        for _, allowed in ipairs(rule.enum) do
            if allowed == value then ok = true break end
        end
        if not ok then
            return false, string.format("'%s' must be one of: %s", key, table.concat(rule.enum, ", "))
        end
    end
    if rule.check then
        local ok, err = rule.check(value, def)
        if not ok then return false, "'" .. key .. "' " .. (err or "is invalid") end
    end
    return true
end

-- Returns a validated copy of def with defaults filled in, or nil and an error message.
function Registry:Build(id, def)
    if type(id) ~= "string" or id == "" then return nil, "id must be a non-empty string" end
    if type(def) ~= "table" then return nil, "definition must be a table" end

    local out = table.Copy(def)
    out.id = id
    -- Defaults first, so later checks (and default functions) can see every field.
    for key, rule in pairs(self.schema) do
        if out[key] == nil and rule.default ~= nil then
            if type(rule.default) == "function" then
                out[key] = rule.default(out)
            elseif type(rule.default) == "table" then
                out[key] = table.Copy(rule.default)
            else
                out[key] = rule.default
            end
        end
    end
    for key, rule in pairs(self.schema) do
        local ok, err = CheckField(key, rule, out[key], out)
        if not ok then return nil, err end
    end
    return out
end

function Registry:Register(id, def)
    local built, err = self:Build(id, def)
    if not built then
        MCC.Error("%s '%s' rejected: %s", self.name, tostring(id), err)
        return nil, err
    end
    if not self.defs[id] then self.count = self.count + 1 end
    self.defs[id] = built
    return built
end

function Registry:Get(id) return self.defs[id] end
function Registry:All() return self.defs end
function Registry:Count() return self.count end

function Registry:Remove(id)
    if self.defs[id] then
        self.defs[id] = nil
        self.count = self.count - 1
        return true
    end
    return false
end

function Registry:Clear()
    self.defs = {}
    self.count = 0
end

-- Sorted list of ids, for stable menus and command output.
function Registry:IDs()
    local ids = table.GetKeys(self.defs)
    table.sort(ids)
    return ids
end
