--[[ Salus Novus -- Schedule: a boss's observed casts as one ordered event list.

The hub and the visualizer both read the log-mined data this way, so the
rule for what counts as "the boss" and how a cast bar and its landing
merge lives here once.
]]

local _, ns = ...

local S = {}
ns.Schedule = S

--- Which caster counts as "the boss" for the timeline and the bars:
-- npcs[1] -- the NPC sharing the encounter's name, or the one the generator
-- picked by health when none does (Infurnus is Magmatus). Everything else
-- in the window is trash pulled or summoned into the fight and is not shown.
function S.IsBossSource(boss, source)
    local first = boss.npcs and boss.npcs[1]
    if not first then return true end
    return source == first.name
end

--- Flatten a boss's observed casts into one sorted event list.
-- Each entry: { t = seconds after pull, name, spellID, pulls = n, kind }.
function S.EventsFor(boss)
    local out = {}
    for _, a in ipairs(boss.abilities or {}) do
        if S.IsBossSource(boss, a.source) then
            local lastStart = nil
            for _, c in ipairs(a.casts or {}) do
                local t, kind = c[1], c[2]
                -- A cast bar ("start") followed by its landing ("success")
                -- within a few seconds is one event, shown at the moment
                -- the bar began.
                if kind == "success" and lastStart and t - lastStart <= 4 then
                    lastStart = nil
                else
                    table.insert(out, { t = t, name = a.name, spellID = a.spellID, pulls = a.pulls or 1, kind = kind })
                    lastStart = (kind == "start") and t or nil
                end
            end
        end
    end
    table.sort(out, function(x, y) return x.t < y.t end)
    return out
end

-- The lanes view of one ability: casts clustered across pulls, each with the
-- pulls backing it and how far they disagreed. The generator writes this as
-- `ability.lanes`; when a data file predates it (or a test builds a boss by
-- hand) the same clustering runs here from the raw casts, so the window
-- never depends on regeneration. Greedy in time order: a cast joins the
-- open cluster when it is within CLUSTER_WINDOW of the cluster's first cast
-- and its pull is not already in it. One pull => support 1, spread 0,
-- which the visualizer must call UNCONFIRMED, never consistent.
local CLUSTER_WINDOW, PAIR_WINDOW = 6.0, 4.0

local function LaneEvents(a)
    local byPull = {}
    for _, c in ipairs(a.casts or {}) do
        local pi = c[3] or 1
        byPull[pi] = byPull[pi] or {}
        table.insert(byPull[pi], { c[1], c[2] })
    end
    local out, lengths = {}, {}
    for pi, rows in pairs(byPull) do
        table.sort(rows, function(x, y) return x[1] < y[1] end)
        local lastStart
        for _, r in ipairs(rows) do
            local t, kind = r[1], r[2]
            if kind == "success" and lastStart and t - lastStart <= PAIR_WINDOW then
                lengths[#lengths + 1] = t - lastStart
                lastStart = nil
            else
                out[#out + 1] = { t = t, pull = pi }
                lastStart = (kind == "start") and t or nil
            end
        end
    end
    table.sort(out, function(x, y) if x.t == y.t then return x.pull < y.pull end return x.t < y.t end)
    return out, lengths
end

function S.LanesOf(a)
    if a.lanes then return a.lanes end
    local events, lengths = LaneEvents(a)
    local clusters = {}
    for _, e in ipairs(events) do
        local c = clusters[#clusters]
        if c and e.t - c.first <= CLUSTER_WINDOW and not c.pulls[e.pull] then
            c.ts[#c.ts + 1] = e.t
            c.pulls[e.pull] = true
            c.n = c.n + 1
        else
            clusters[#clusters + 1] = { first = e.t, ts = { e.t }, pulls = { [e.pull] = true }, n = 1 }
        end
    end
    local lanes = { casts = {}, spread = {}, support = {}, cast = 0 }
    for i, c in ipairs(clusters) do
        table.sort(c.ts)
        local n = #c.ts
        local med = (n % 2 == 1) and c.ts[(n + 1) / 2] or (c.ts[n / 2] + c.ts[n / 2 + 1]) / 2
        local dev = 0
        for _, t in ipairs(c.ts) do dev = math.max(dev, math.abs(t - med)) end
        lanes.casts[i] = math.floor(med * 10 + 0.5) / 10
        lanes.spread[i] = math.floor(dev * 10 + 0.5) / 10
        lanes.support[i] = c.n
    end
    if #lengths > 0 then
        table.sort(lengths)
        lanes.cast = math.floor(lengths[math.floor((#lengths + 1) / 2)] * 10 + 0.5) / 10
    end
    a.lanes = lanes
    return lanes
end

--- Every boss-source ability with its lanes view, sorted by first cast.
--- Abilities the logs show to be HEALTH-triggered (cast at the same boss
-- health in every pull, at different times): never timed, never on the
-- lanes or the timed anchors; drawn as markers on the Health Bars anchor.
-- An ability cast at SEVERAL healths (VanCleef's add waves at 75% and
-- 50%: the same summon, twice) carries `health.pcts`; it comes back as
-- one entry per threshold so the anchor draws one marker each.
function S.HealthAbilities(boss)
    local out = {}
    for _, a in ipairs(boss and boss.abilities or {}) do
        if a.health and type(a.health.pct) == "number" and S.IsBossSource(boss, a.source) then
            local pcts = a.health.pcts
            if type(pcts) == "table" and #pcts > 1 then
                for _, p in ipairs(pcts) do
                    if type(p) == "number" then
                        out[#out + 1] = { spellID = a.spellID, name = a.name, source = a.source,
                                          health = { pct = p }, ability = a }
                    end
                end
            else
                out[#out + 1] = a
            end
        end
    end
    table.sort(out, function(x, y) return x.health.pct > y.health.pct end)
    return out
end

function S.Lanes(boss)
    local out = {}
    for _, a in ipairs(boss.abilities or {}) do
        if S.IsBossSource(boss, a.source) and not a.health then
            local l = S.LanesOf(a)
            if #l.casts > 0 then out[#out + 1] = { a = a, lanes = l, first = l.casts[1] } end
        end
    end
    table.sort(out, function(x, y) if x.first == y.first then return (x.a.name or "") < (y.a.name or "") end return x.first < y.first end)
    return out
end

--- The axis runs to the average kill OR the last observed cast, whichever
-- is later, plus a margin. A boss nothing has been logged for gets five
-- minutes, so reminders can still be placed on its lane.
function S.FightEnd(boss)
    if not boss then return 600 end
    local last = boss.avgLength or 0
    for _, e in ipairs(S.Lanes(boss)) do
        local c = e.lanes.casts[#e.lanes.casts]
        if c and c > last then last = c end
    end
    if last <= 0 then return 300 end
    return last + 3
end

--- The first boss in the data with any events: what previews draw from.
function S.SampleBoss()
    local mapIDs = {}
    for id in pairs(ns.Data or {}) do mapIDs[#mapIDs + 1] = id end
    table.sort(mapIDs)
    for _, id in ipairs(mapIDs) do
        for _, b in ipairs(ns.Data[id].bosses or {}) do
            if #S.EventsFor(b) > 0 then return b end
        end
    end
    return nil
end
