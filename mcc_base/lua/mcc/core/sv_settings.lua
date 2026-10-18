-- Changing MCC settings from the Q menu (Utilities > MCC > Server Settings). Admins only.

MCC.Net.Receive("config_set", function(a, ply)
    local def = istable(a) and MCC.Config.Defs[tostring(a.name or "")]
    if not def then return end
    MCC.Perms.Check(ply, "MCC Admin", function(allowed)
        if not allowed then
            MCC.Util.Reply(ply, "Only admins can change MCC settings.")
            return
        end
        local v = a.value
        if def.kind == "boolean" then
            v = (v == true or v == 1 or v == "1") and "1" or "0"
        elseif def.kind == "number" then
            v = tonumber(v)
            if not v then return end
            if def.min then v = math.max(def.min, v) end
            if def.max then v = math.min(def.max, v) end
            v = tostring(v)
        else
            v = string.sub(tostring(v or ""), 1, 512)
        end
        RunConsoleCommand("mcc_" .. a.name, v)
        MCC.Log("%s set mcc_%s to %s", IsValid(ply) and ply:Nick() or "console", a.name, v)
    end)
end, {allowClient = true, maxBytes = 1024})
