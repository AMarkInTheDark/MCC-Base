-- Shared helpers: logging and small table utilities.

local PREFIX_COLOR = Color(90, 170, 255)
local TEXT_COLOR = Color(220, 220, 220)
local WARN_COLOR = Color(255, 180, 60)
local ERROR_COLOR = Color(255, 90, 90)

local function Format(msg, ...)
    if select("#", ...) > 0 then
        return string.format(msg, ...)
    end
    return tostring(msg)
end

function MCC.Log(msg, ...)
    MsgC(PREFIX_COLOR, "[MCC] ", TEXT_COLOR, Format(msg, ...), "\n")
end

function MCC.Warn(msg, ...)
    MsgC(PREFIX_COLOR, "[MCC] ", WARN_COLOR, Format(msg, ...), "\n")
end

-- Reports a problem without stopping the code that called it.
function MCC.Error(msg, ...)
    MsgC(PREFIX_COLOR, "[MCC] ", ERROR_COLOR, Format(msg, ...), "\n")
end

function MCC.Debug(msg, ...)
    local cv = GetConVar("mcc_debug")
    if cv and cv:GetBool() then
        MsgC(PREFIX_COLOR, "[MCC debug] ", TEXT_COLOR, Format(msg, ...), "\n")
    end
end

MCC.Util = MCC.Util or {}

-- Copies only what survives JSON: strings, numbers, booleans and tables of them. Functions and entities are dropped.
function MCC.Util.JSONSafe(value, depth)
    depth = depth or 0
    local t = type(value)
    if t == "string" or t == "number" or t == "boolean" then return value end
    if t ~= "table" or depth > 16 then return nil end
    local out = {}
    for k, v in pairs(value) do
        local kt = type(k)
        if kt == "string" or kt == "number" then
            local safe = MCC.Util.JSONSafe(v, depth + 1)
            if safe ~= nil then out[k] = safe end
        end
    end
    return out
end

-- Parses a console argument: "true"/"false" become booleans, numbers become numbers, the rest stays a string.
function MCC.Util.ParseValue(str)
    if str == "true" then return true end
    if str == "false" then return false end
    local n = tonumber(str)
    if n ~= nil then return n end
    return str
end

-- Sends a line to a player's console, or to the server console when ply is nil/NULL.
function MCC.Util.Reply(ply, msg, ...)
    local text = Format(msg, ...)
    if IsValid(ply) then
        ply:PrintMessage(HUD_PRINTCONSOLE, "[MCC] " .. text)
    else
        MCC.Log("%s", text)
    end
end
