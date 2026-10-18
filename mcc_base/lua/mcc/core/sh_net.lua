-- Networking for tables of any size.
-- A single GMod net message is capped at 64 KB, which a FOB stash or a full item registry can exceed.
-- MCC.Net sends a table as JSON, compressed and split into chunks, and rebuilds it on the other side.
--
--   MCC.Net.Receive("inv_sync", function(data, ply) ... end)                      -- register a handler
--   MCC.Net.Send("inv_sync", tbl, ply)            -- server: one player, a table of players, or nil for everyone
--   MCC.Net.Send("loot_request", tbl)             -- client: always to the server
--
-- Clients may only send to handlers registered with {allowClient = true}, and those are size-capped.
-- Keep payload keys as strings or plain arrays: JSON can't preserve mixed numeric keys.

MCC.Net = MCC.Net or {}
MCC.Net.Handlers = MCC.Net.Handlers or {}

local CHUNK_SIZE = 60000
local CHUNKS_PER_TICK = 4
local BUFFER_TIMEOUT = 30
local CLIENT_CHUNKS_PER_SECOND = 20
local DEFAULT_CLIENT_MAX_BYTES = 16384

if SERVER then
    util.AddNetworkString("MCC_Chunk")
end

-- opts.allowClient: accept this message from clients (server side only matters)
-- opts.maxBytes:    largest compressed payload accepted from a client
function MCC.Net.Receive(name, fn, opts)
    opts = opts or {}
    MCC.Net.Handlers[name] = {
        fn = fn,
        allowClient = opts.allowClient and true or false,
        maxBytes = opts.maxBytes or DEFAULT_CLIENT_MAX_BYTES,
    }
end

-- Splits a string into CHUNK_SIZE pieces. Exposed for testing.
function MCC.Net.Split(str, size)
    size = size or CHUNK_SIZE
    local pieces = {}
    local len = #str
    if len == 0 then return {""} end
    for i = 1, len, size do
        pieces[#pieces + 1] = string.sub(str, i, i + size - 1)
    end
    return pieces
end

-- Sending ------------------------------------------------------------------------------

local queue = {}
local nextTransferID = 0
local budgetTick, budgetUsed = -1, 0

local function ResolveTargets(target)
    if target == nil then return nil end -- broadcast
    if istable(target) then
        local valid = {}
        for _, p in ipairs(target) do
            if IsValid(p) then valid[#valid + 1] = p end
        end
        return valid
    end
    return IsValid(target) and target or false
end

local function WriteChunk(entry)
    local targets
    if SERVER then
        targets = ResolveTargets(entry.target)
        if targets == false or (istable(targets) and #targets == 0) then return end -- everyone left
    end

    net.Start("MCC_Chunk")
    net.WriteString(entry.name)
    net.WriteUInt(entry.id, 16)
    net.WriteUInt(entry.index, 16)
    net.WriteUInt(entry.total, 16)
    net.WriteUInt(#entry.piece, 32)
    net.WriteData(entry.piece, #entry.piece)

    if CLIENT then
        net.SendToServer()
    elseif targets == nil then
        net.Broadcast()
    else
        net.Send(targets)
    end
end

local function Pump()
    local tick = engine.TickCount()
    if tick ~= budgetTick then
        budgetTick, budgetUsed = tick, 0
    end
    while queue[1] and budgetUsed < CHUNKS_PER_TICK do
        WriteChunk(table.remove(queue, 1))
        budgetUsed = budgetUsed + 1
    end
end

hook.Add("Think", "MCC_NetPump", function()
    if queue[1] then Pump() end
end)

function MCC.Net.Send(name, data, target)
    local json = util.TableToJSON(data or {})
    if not json then
        MCC.Error("MCC.Net.Send('%s'): payload can't be encoded as JSON", name)
        return false
    end
    local packed = util.Compress(json)
    if not packed then
        MCC.Error("MCC.Net.Send('%s'): compression failed", name)
        return false
    end

    local pieces = MCC.Net.Split(packed)
    if #pieces > 65535 then
        MCC.Error("MCC.Net.Send('%s'): payload too large (%d bytes)", name, #packed)
        return false
    end

    nextTransferID = (nextTransferID + 1) % 65536
    for i, piece in ipairs(pieces) do
        queue[#queue + 1] = {
            name = name, id = nextTransferID, index = i, total = #pieces,
            piece = piece, target = target,
        }
    end
    Pump()
    return true
end

-- Receiving ----------------------------------------------------------------------------

local buffers = {}
local clientRate = {}

local function Deliver(handler, name, packed, ply)
    -- Cap what a client's payload may decompress to; data from the server is trusted.
    local json = SERVER and util.Decompress(packed, handler.maxBytes * 20) or util.Decompress(packed)
    local data = json and util.JSONToTable(json)
    if not data then
        MCC.Error("Couldn't decode '%s' from %s", name, IsValid(ply) and ply:Nick() or "server")
        return
    end
    local ok, err = pcall(handler.fn, data, ply)
    if not ok then
        MCC.Error("Handler for '%s' failed: %s", name, tostring(err))
    end
end

-- Returns false when a client is sending chunks faster than allowed.
local function ClientWithinRate(ply)
    local now = CurTime()
    local r = clientRate[ply]
    if not r or now - r.start >= 1 then
        clientRate[ply] = {start = now, count = 1}
        return true
    end
    r.count = r.count + 1
    return r.count <= CLIENT_CHUNKS_PER_SECOND
end

net.Receive("MCC_Chunk", function(_, ply)
    local name = net.ReadString()
    local id = net.ReadUInt(16)
    local index = net.ReadUInt(16)
    local total = net.ReadUInt(16)
    local size = net.ReadUInt(32)
    if size > CHUNK_SIZE then return end
    local piece = net.ReadData(size)

    local handler = MCC.Net.Handlers[name]
    if not handler then
        MCC.Debug("No handler for '%s'", name)
        return
    end

    if SERVER then
        if not handler.allowClient then return end
        if not ClientWithinRate(ply) then return end
        if total > math.ceil(handler.maxBytes / CHUNK_SIZE) then return end
    end

    local key = (SERVER and ply:UserID() or "srv") .. ":" .. name .. ":" .. id
    local buf = buffers[key]
    if index == 1 then
        buf = {pieces = {}, total = total, bytes = 0, started = CurTime()}
        buffers[key] = buf
    end
    if not buf or buf.total ~= total or index ~= #buf.pieces + 1 then
        buffers[key] = nil -- out of order or joined mid-transfer: drop it
        return
    end

    buf.pieces[index] = piece
    buf.bytes = buf.bytes + #piece
    if SERVER and buf.bytes > handler.maxBytes then
        buffers[key] = nil
        return
    end

    if index == total then
        buffers[key] = nil
        Deliver(handler, name, table.concat(buf.pieces), ply)
    end
end)

timer.Create("MCC_NetCleanup", 10, 0, function()
    local now = CurTime()
    for key, buf in pairs(buffers) do
        if now - buf.started > BUFFER_TIMEOUT then buffers[key] = nil end
    end
    for ply in pairs(clientRate) do
        if not IsValid(ply) then clientRate[ply] = nil end
    end
end)
