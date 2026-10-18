-- Console commands. Every MCC command is "mcc_<name>", checks a privilege, and works from
-- the server console too. Expansions add theirs the same way:
--
--   MCC.Command("event_start", "MCC Moderator", "<event id>", "Starts an event now.", function(ply, args) ... end)

MCC.Commands = MCC.Commands or {}

function MCC.Command(name, privilege, usage, help, fn)
    MCC.Commands[name] = {privilege = privilege, usage = usage, help = help}
    concommand.Add("mcc_" .. name, function(ply, _, args)
        MCC.Perms.Check(ply, privilege, function(allowed)
            if not allowed then
                MCC.Util.Reply(ply, "You don't have permission to use mcc_%s.", name)
                return
            end
            local ok, err = pcall(fn, ply, args)
            if not ok then
                MCC.Error("mcc_%s failed: %s", name, tostring(err))
                MCC.Util.Reply(ply, "mcc_%s failed; see the server console.", name)
            end
        end)
    end, nil, help)
end

MCC.Command("help", "MCC Moderator", "", "Lists MCC commands.", function(ply)
    local names = table.GetKeys(MCC.Commands)
    table.sort(names)
    for _, name in ipairs(names) do
        local c = MCC.Commands[name]
        MCC.Util.Reply(ply, "mcc_%s %s  -  %s", name, c.usage, c.help)
    end
end)

MCC.Command("version", "MCC Moderator", "", "Shows the MCC version and detected addons.", function(ply)
    MCC.Util.Reply(ply, "MCC Base %s (API %d)", MCC.Version, MCC.API_VERSION)
    for id, def in pairs(MCC.Compat.Defs) do
        local state = MCC.Compat.Has(id) and "active"
            or (MCC.Compat.Installed(id) and "installed, turned off" or "not installed")
        MCC.Util.Reply(ply, "  %s: %s", def.name, state)
    end
end)

MCC.Command("reload_config", "MCC Admin", "", "Re-reads every MCC data file and updates clients.", function(ply)
    MCC.Items.Rebuild()
    hook.Run("MCC_ReloadConfig")
    MCC.Util.Reply(ply, "Reloaded. %d items.", MCC.Items.Count())
end)

MCC.Command("save", "MCC Admin", "", "Saves all MCC data now.", function(ply)
    MCC.Data.SaveAll("command")
    MCC.Util.Reply(ply, "Saved.")
end)
