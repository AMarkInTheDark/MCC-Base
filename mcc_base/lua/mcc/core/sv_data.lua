-- Server storage.
--   JSON files in garrysmod/data/mcc/ hold configuration server owners edit (items, traders, factions).
--   SQLite (sv.db) holds game state: inventories, stashes, FOBs, relations.
--
-- Game state uses one key-value table so modules don't each need their own schema:
--   MCC.Data.Set("stash", ply:SteamID64(), tbl)   -- stores tbl as JSON
--   MCC.Data.Get("stash", ply:SteamID64())        --> tbl or nil
--   MCC.Data.Delete("stash", sid)
--   MCC.Data.GetAll("fob")                        --> {key = tbl, ...}

MCC.Data = MCC.Data or {}

local DIR = "mcc"
local KV_TABLE = "mcc_kv"

local README = [[
MCC data files
==============
Edit these while the server is stopped, or edit them live and run mcc_reload_config.
Most changes can also be made in game with the mcc_* console commands (type mcc_help).

items.json
  Maps an item id to one of:
    a partial table  -> changes the built-in item:  "weapon_ar2": {"price": 1500, "w": 4}
    a full table     -> adds a new item (needs "name" and "kind")
    false            -> removes the item:            "weapon_rpg": false

  Item fields: name, kind, class, w, h, maxStack, weight, price, model, category, rarity, tags, data
  Kinds: weapon, ammo, mag, gear, armor, consumable, resource, misc
]]

local function Path(rel) return DIR .. "/" .. rel end

function MCC.Data.ReadJSON(rel)
    local raw = file.Read(Path(rel), "DATA")
    if not raw or raw == "" then return nil end
    local t = util.JSONToTable(raw)
    if not t then
        MCC.Error("data/%s is not valid JSON; using defaults. Fix the file and run mcc_reload_config.", Path(rel))
    end
    return t
end

function MCC.Data.WriteJSON(rel, tbl)
    file.CreateDir(DIR)
    file.Write(Path(rel), util.TableToJSON(tbl or {}, true))
end

-- Writes a file only if it doesn't exist yet, so owner edits are never overwritten.
function MCC.Data.EnsureJSON(rel, default)
    if not file.Exists(Path(rel), "DATA") then
        MCC.Data.WriteJSON(rel, default)
    end
end

-- SQLite -------------------------------------------------------------------------------

local function Query(q)
    local result = sql.Query(q)
    if result == false then
        MCC.Error("SQL error: %s\n  in: %s", tostring(sql.LastError()), q)
    end
    return result
end
MCC.Data.Query = Query

function MCC.Data.Set(scope, key, tbl)
    local json = util.TableToJSON(tbl)
    if not json then
        MCC.Error("MCC.Data.Set(%s, %s): value can't be stored as JSON", tostring(scope), tostring(key))
        return false
    end
    return Query(string.format("REPLACE INTO %s (scope, id, value, updated) VALUES (%s, %s, %s, %d)",
        KV_TABLE, sql.SQLStr(scope), sql.SQLStr(key), sql.SQLStr(json), os.time())) ~= false
end

function MCC.Data.Get(scope, key)
    local row = sql.QueryRow(string.format("SELECT value FROM %s WHERE scope = %s AND id = %s",
        KV_TABLE, sql.SQLStr(scope), sql.SQLStr(key)))
    return row and util.JSONToTable(row.value) or nil
end

function MCC.Data.Delete(scope, key)
    return Query(string.format("DELETE FROM %s WHERE scope = %s AND id = %s",
        KV_TABLE, sql.SQLStr(scope), sql.SQLStr(key))) ~= false
end

function MCC.Data.GetAll(scope)
    local rows = Query(string.format("SELECT id, value FROM %s WHERE scope = %s", KV_TABLE, sql.SQLStr(scope)))
    local out = {}
    for _, row in ipairs(rows or {}) do
        out[row.id] = util.JSONToTable(row.value)
    end
    return out
end

-- Runs several writes as one transaction (much faster for bulk saves).
function MCC.Data.Batch(fn)
    sql.Begin()
    local ok, err = pcall(fn)
    sql.Commit()
    if not ok then MCC.Error("Batch save failed: %s", tostring(err)) end
end

function MCC.Data.Init()
    file.CreateDir(DIR)
    file.Write(Path("README.txt"), README)
    MCC.Data.EnsureJSON("items.json", {})

    Query(string.format([[CREATE TABLE IF NOT EXISTS %s (
        scope TEXT NOT NULL,
        id TEXT NOT NULL,
        value TEXT NOT NULL,
        updated INTEGER NOT NULL,
        PRIMARY KEY (scope, id)
    )]], KV_TABLE))
end

-- Modules add hook.Add("MCC_Save", ...) to write their state; this runs it on a timer and on shutdown.
local function SaveAll(reason)
    MCC.Data.Batch(function()
        hook.Run("MCC_Save", reason)
    end)
end
MCC.Data.SaveAll = SaveAll

hook.Add("MCC_Ready", "MCC_SaveTimer", function()
    timer.Create("MCC_AutoSave", MCC.Config.Get("save_interval"), 0, function() SaveAll("timer") end)
end)

cvars.AddChangeCallback("mcc_save_interval", function(_, _, new)
    if timer.Exists("MCC_AutoSave") then
        timer.Adjust("MCC_AutoSave", math.max(15, tonumber(new) or 120))
    end
end, "MCC_SaveInterval")

hook.Add("ShutDown", "MCC_SaveOnShutdown", function() SaveAll("shutdown") end)
