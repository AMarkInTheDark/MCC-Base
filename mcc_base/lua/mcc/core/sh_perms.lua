-- Permissions. Uses CAMI when an admin mod provides it (ULX, SAM, ServerGuard and others ship it),
-- so server owners grant MCC privileges from their admin mod. Without CAMI, MinAccess decides:
-- "user" = everyone, "admin" = IsAdmin(), "superadmin" = IsSuperAdmin().

MCC.Perms = MCC.Perms or {}
MCC.Perms.Defs = MCC.Perms.Defs or {}

local function FallbackAccess(ply, minAccess)
    if minAccess == "user" then return true end
    if minAccess == "admin" then return ply:IsAdmin() end
    return ply:IsSuperAdmin()
end

function MCC.Perms.Register(name, minAccess, description)
    assert(minAccess == "user" or minAccess == "admin" or minAccess == "superadmin",
        "MCC.Perms.Register: minAccess must be user, admin or superadmin")
    MCC.Perms.Defs[name] = {name = name, minAccess = minAccess, description = description}
    if CAMI and CAMI.RegisterPrivilege then
        CAMI.RegisterPrivilege({Name = name, MinAccess = minAccess, Description = description})
    end
end

-- Calls callback(allowed) once the answer is known; CAMI may answer asynchronously.
-- The server console (ply nil/NULL) is always allowed.
function MCC.Perms.Check(ply, name, callback)
    if not IsValid(ply) then
        callback(SERVER)
        return
    end
    local def = MCC.Perms.Defs[name]
    if not def then
        MCC.Error("Unknown privilege '%s'", tostring(name))
        callback(false)
        return
    end
    if CAMI and CAMI.PlayerHasAccess then
        CAMI.PlayerHasAccess(ply, name, function(allowed)
            callback(allowed and true or false)
        end)
        return
    end
    callback(FallbackAccess(ply, def.minAccess))
end

MCC.Perms.Register("MCC Admin", "superadmin", "Edit MCC configuration: items, traders, factions, reload data files.")
MCC.Perms.Register("MCC Moderator", "admin", "Use MCC moderation commands: give items, manage FOBs, start events.")
