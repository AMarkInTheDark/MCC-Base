-- Searching bodies and containers, Tarkov style.
--
-- What a body is wearing (guns, armor, the rig and backpack themselves) is visible straight away.
-- Its pockets and the inside of each piece of gear are closed sections, each with a SEARCH button;
-- each compartment of a container (one locker of four) is its own closed section. Searching a section reveals its items one at a time (bigger
-- items take longer). Each player searches for themselves; searches you start while one is running
-- are queued. Items you put somewhere are always visible to you.

local Inv = MCC.Inv

-- Per entity, per player: {done = {section = true}, seen = {item uid = true}}.
local function State(ent, ply)
    ent.MCCSearchState = ent.MCCSearchState or setmetatable({}, {__mode = "k"})
    local s = ent.MCCSearchState[ply]
    if not s then
        s = {done = {}, seen = {}}
        ent.MCCSearchState[ply] = s
    end
    return s
end

local function Enabled()
    return MCC.Config.Get("search_enabled")
end

-- The closed section a location belongs to: "pockets", a gear slot key ("rig", "backpack"...),
-- "c:<i>" for a container compartment, or nil for what a body is wearing (always visible).
function Inv.SectionOf(loc)
    if loc == "c" then return "c:1" end
    if string.find(loc or "", "^c:%d+$") then return loc end
    local key = string.match(loc or "", "^bs:(%w+)$")
    if key then
        local s = Inv.Slots[key]
        return (s and (s.pocket or s.special)) and "pockets" or nil
    end
    return string.match(loc or "", "^bg:(%w+):")
end

function Inv.SectionDone(ply, ent, section)
    if not section or not Enabled() or not IsValid(ent) then return true end
    if ent.MCCCont and ent.MCCCont.noSearch then return true end
    return State(ent, ply).done[section] == true
end

-- Marks a section as searched for a player (a crate you sent up yourself comes back known).
function Inv.MarkSectionDone(ply, ent, section)
    if IsValid(ent) and IsValid(ply) then State(ent, ply).done[section] = true end
end

function Inv.IsSeen(ply, ent, it)
    if not Enabled() or not IsValid(ent) then return true end
    return State(ent, ply).seen[it.u] == true
end

-- Marks an item (and whatever is packed inside it) as known to the player.
function Inv.MarkSeen(ply, ent, it)
    if not IsValid(ent) or not it then return end
    State(ent, ply).seen[it.u] = true
    for _, list in ipairs(it.cont or {}) do
        for _, o in ipairs(list) do Inv.MarkSeen(ply, ent, o) end
    end
end

function Inv.Visible(ply, ent, it, loc)
    local section = Inv.SectionOf(loc)
    return Inv.SectionDone(ply, ent, section) or Inv.IsSeen(ply, ent, it)
end

-- Sections that exist on what the player has open.
local function Sections(ent)
    local C = ent.MCCCont
    local out = {}
    if not C then return out end
    if not C.inv then
        for i = 1, #(C.grids or {}) do out[i] = "c:" .. i end
        return out
    end
    out[1] = "pockets"
    for _, key in ipairs(Inv.GearSlots) do
        if C.inv.slots[key] and Inv.Cells(C.inv.slots[key]) then out[#out + 1] = key end
    end
    return out
end

local function ReadingOrder(list)
    local sorted = {}
    for _, o in ipairs(list or {}) do sorted[#sorted + 1] = o end
    table.sort(sorted, function(a, b)
        if (a.y or 0) ~= (b.y or 0) then return (a.y or 0) < (b.y or 0) end
        return (a.x or 0) < (b.x or 0)
    end)
    return sorted
end

-- Every item in a section, in the order it's searched.
local function SectionItems(ent, section)
    local C = ent.MCCCont
    local out = {}
    local ci = tonumber(string.match(section, "^c:(%d+)$") or "")
    if ci then return ReadingOrder(C.grids and C.grids[ci] and C.grids[ci].items) end
    if not C.inv then return out end
    if section == "pockets" then
        for i = 1, Inv.POCKETS do out[#out + 1] = C.inv.slots["pocket" .. i] end
        for i = 1, Inv.SPECIALS do out[#out + 1] = C.inv.slots["special" .. i] end
        return out
    end
    local gear = C.inv.slots[section]
    for _, list in ipairs(gear and gear.cont or {}) do
        for _, o in ipairs(ReadingOrder(list)) do out[#out + 1] = o end
    end
    return out
end

local function NextUnseen(ply, ent, section)
    local st = State(ent, ply)
    for _, it in ipairs(SectionItems(ent, section)) do
        if not st.seen[it.u] then return it end
    end
end

-- Bigger items take longer: about search_time for 1x1, double that for a rifle.
function Inv.SearchTime(it)
    local def = Inv.Def(it)
    local cells = def and def.w * def.h or 1
    return MCC.Config.Get("search_time") * (0.5 + 0.5 * math.sqrt(cells))
end

-- Starts the next queued section. A section with nothing in it finishes at once.
local function StartNext(ply, job)
    while #job.queue > 0 do
        local section = table.remove(job.queue, 1)
        local it = NextUnseen(ply, job.ent, section)
        if it then
            local dur = Inv.SearchTime(it)
            job.section, job.item, job.u, job.dur, job.ends = section, it, it.u, dur, CurTime() + dur
            return true
        end
        State(job.ent, ply).done[section] = true
    end
    ply.MCCSearch = nil
    return false
end

-- Asks to search a section of what the player has open; queued behind a running search.
function Inv.QueueSearch(ply, section)
    local e = Inv.OpenTarget(ply)
    if not e or not Enabled() then return false end
    local valid = false
    for _, s in ipairs(Sections(e)) do
        if s == section then valid = true break end
    end
    if not valid or Inv.SectionDone(ply, e, section) then return false end

    local job = ply.MCCSearch
    if not job or job.ent ~= e then
        job = {ent = e, queue = {}}
        ply.MCCSearch = job
    end
    if job.section == section then return true end
    for _, q in ipairs(job.queue) do
        if q == section then return true end
    end
    job.queue[#job.queue + 1] = section
    if not job.section then StartNext(ply, job) end
    return true
end

timer.Create("MCC_InvSearch", 0.1, 0, function()
    if not Inv.Enabled() or not Enabled() then return end
    for _, ply in ipairs(player.GetAll()) do
        local job = ply.MCCSearch
        if job then
            local e = Inv.OpenTarget(ply)
            if e ~= job.ent then
                ply.MCCSearch = nil
            elseif job.section and CurTime() >= job.ends then
                Inv.MarkSeen(ply, e, job.item)
                local it = NextUnseen(ply, e, job.section)
                if it then
                    local dur = Inv.SearchTime(it)
                    job.item, job.u, job.dur, job.ends = it, it.u, dur, CurTime() + dur
                else
                    State(e, ply).done[job.section] = true
                    job.section = nil
                    StartNext(ply, job)
                end
                Inv.Update(ply)
            end
        end
    end
end)

-- What the player is sent ----------------------------------------------------------------------

local function SectionState(ply, e, section)
    if Inv.SectionDone(ply, e, section) then return "done" end
    local job = ply.MCCSearch
    if job and job.ent == e then
        if job.section == section then return "searching" end
        for _, q in ipairs(job.queue) do
            if q == section then return "queued" end
        end
    end
    return "closed"
end

-- An item as the player may see it: itself, a sized "?" while its section is being searched, or
-- nothing at all while the section is still closed.
local function Shown(ply, e, it, state)
    if state == "done" or Inv.IsSeen(ply, e, it) then
        if not it.cont then return it end
        local copy = {}
        for k, v in pairs(it) do copy[k] = v end
        copy.cont = {}
        for i, list in ipairs(it.cont) do
            copy.cont[i] = {}
            for _, o in ipairs(list) do
                local shown = Shown(ply, e, o, state)
                if shown then copy.cont[i][#copy.cont[i] + 1] = shown end
            end
        end
        return copy
    end
    if state == "closed" or state == "queued" then return nil end
    local def = Inv.Def(it)
    return {u = it.u, hidden = true, w = def and def.w or 1, h = def and def.h or 1, x = it.x, y = it.y, r = it.r}
end

function Inv.OpenPayload(ply)
    local e = Inv.OpenTarget(ply)
    if not e then return nil end
    local C = e.MCCCont
    local out = {name = C.name, sections = {}, fob = C.fob and e:EntIndex() or nil}
    for _, s in ipairs(Sections(e)) do out.sections[s] = SectionState(ply, e, s) end

    if C.inv then
        out.body, out.slots = true, {}
        for key, it in pairs(C.inv.slots) do
            local slot = Inv.Slots[key]
            if slot and (slot.pocket or slot.special) then
                out.slots[key] = Shown(ply, e, it, out.sections.pockets)
            elseif it.cont then
                -- worn gear is visible; what's inside follows its own section
                local copy = {}
                for k, v in pairs(it) do copy[k] = v end
                local state = out.sections[key] or "done"
                copy.cont = {}
                for i, list in ipairs(it.cont) do
                    copy.cont[i] = {}
                    for _, o in ipairs(list) do
                        local shown = Shown(ply, e, o, state)
                        if shown then copy.cont[i][#copy.cont[i] + 1] = shown end
                    end
                end
                out.slots[key] = copy
            else
                out.slots[key] = it
            end
        end
    else
        out.grids, out.vertical = {}, C.vertical
        for i, g in ipairs(C.grids or {}) do
            local items = {}
            for _, o in ipairs(g.items) do
                local shown = Shown(ply, e, o, out.sections["c:" .. i])
                if shown then items[#items + 1] = shown end
            end
            out.grids[i] = {w = g.w, h = g.h, items = items}
        end
    end

    local job = ply.MCCSearch
    if job and job.ent == e and job.u then
        out.searching, out.ends, out.dur = job.u, job.ends, job.dur
    end
    return out
end
