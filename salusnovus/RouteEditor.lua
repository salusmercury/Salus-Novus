--[[ Salus Novus -- RouteEditor: change a route from inside the game.

Leveling > Guide > Steps (Alex, 2026-09-21): see every step of the route
the guide is following, delete steps, move them, and insert new ones at
the current step -- a note, or an accept / objective / turn-in for a quest
in the log -- placed where the player stands.

Two things happen on every edit. The loaded route (ns.Routes) is changed
in place, so the guide and the arrow follow at once. And the edit is
appended to SalusNovusDB.routeEdits[slug] with a unique id, because this
account's client never reads saved variables back: harvest_routes.py
collects the edits from the snapshots and build_route.py applies each one
ONCE to the route's step file (forever_routes/applied_edits.json remembers
the ids), then recompiles Data/Routes.lua. Until that rebuild is copied
in, a /reload shows the route as last built.

Ops: { op = "del", at = i }               remove step i
     { op = "ins", at = i, step = {...} } insert AFTER step i (0 = first)
     { op = "up",  at = i }               swap with the step before
     { op = "down", at = i }              swap with the step after
     { op = "mv",  at = i, to = j }       move step i to index j (drag and drop)
Indices refer to the route AS IT WAS when the op was made, applied in order.
]]

local _, ns = ...

local E = {}
ns.RouteEditor = E

local function Num(v) return type(v) == "number" and not ns.IsSecret(v) end
local function Str(v) return type(v) == "string" and not ns.IsSecret(v) and v or nil end

-- ------------------------------------------------------------ log

local seq = 0
local function Log(route, op)
    if type(SalusNovusDB) ~= "table" or not route or not route.slug then return end
    SalusNovusDB.routeEdits = SalusNovusDB.routeEdits or {}
    local list = SalusNovusDB.routeEdits[route.slug]
    if type(list) ~= "table" then list = {}; SalusNovusDB.routeEdits[route.slug] = list end
    seq = seq + 1
    op.id = ("%d-%d"):format(time(), seq)
    op.t = time()
    list[#list + 1] = op
end

function E.Edits(route)
    local l = type(SalusNovusDB) == "table" and SalusNovusDB.routeEdits and route and SalusNovusDB.routeEdits[route.slug]
    return type(l) == "table" and l or {}
end

-- ------------------------------------------------------------ ops

local function Changed(route, op, at, to)
    if ns.Guide and ns.Guide.AdjustSkips then ns.Guide.AdjustSkips(route, op, at, to) end
    if ns.Guide and ns.Guide.Refresh then ns.Guide.Refresh() end
end

--- Delete step i.
function E.Delete(route, i)
    local steps = route and route.steps
    if not steps or not Num(i) or i < 1 or i > #steps then return false end
    table.remove(steps, i)
    Log(route, { op = "del", at = i })
    Changed(route, "del", i)
    return true
end

--- Insert `step` after index i (0 = at the start).
function E.Insert(route, i, step)
    local steps = route and route.steps
    if not steps or type(step) ~= "table" or not Num(i) or i < 0 or i > #steps then return false end
    table.insert(steps, i + 1, step)
    local copy = {}
    for k, v in pairs(step) do if type(v) ~= "table" then copy[k] = v end end
    Log(route, { op = "ins", at = i, step = copy })
    Changed(route, "ins", i)
    return true
end

function E.Up(route, i)
    local steps = route and route.steps
    if not steps or not Num(i) or i < 2 or i > #steps then return false end
    steps[i], steps[i - 1] = steps[i - 1], steps[i]
    Log(route, { op = "up", at = i })
    Changed(route, "up", i)
    return true
end

function E.Down(route, i)
    local steps = route and route.steps
    if not steps or not Num(i) or i < 1 or i >= #steps then return false end
    steps[i], steps[i + 1] = steps[i + 1], steps[i]
    Log(route, { op = "down", at = i })
    Changed(route, "down", i)
    return true
end

--- Move step i so that it ends up at index j (a drag and drop).
function E.Move(route, i, j)
    local steps = route and route.steps
    if not steps or not Num(i) or not Num(j) or i < 1 or i > #steps or j < 1 or j > #steps or i == j then return false end
    local step = table.remove(steps, i)
    table.insert(steps, j, step)
    Log(route, { op = "mv", at = i, to = j })
    Changed(route, "mv", i, j)
    return true
end

-- ------------------------------------------------------------ new steps

--- Where the player stands, as step fields (empty when unknown).
local function Here()
    local map, x, y = ns.Guide.PlayerPos()
    if not (Num(map) and Num(x) and Num(y)) then return {} end
    return { m = map, x = math.floor(x * 10000 + 0.5) / 10000, y = math.floor(y * 10000 + 0.5) / 10000 }
end

--- The quests in the log: { { questID, title }, ... }.
function E.LogQuests()
    local out = {}
    local ql = rawget(_G, "C_QuestLog")
    if not (ql and ql.GetNumQuestLogEntries and ql.GetInfo) then return out end
    local okN, n = pcall(ql.GetNumQuestLogEntries)
    if not okN or not Num(n) then return out end
    for i = 1, n do
        local ok, info = pcall(ql.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and Num(info.questID) and info.questID > 0 then
            out[#out + 1] = { questID = info.questID, title = Str(info.title) or ("quest " .. info.questID) }
        end
    end
    return out
end

local function Trim(text)
    local t = Str(text)
    if not t then return nil end
    t = t:gsub("^%s+", ""):gsub("%s+$", "")
    return t ~= "" and t or nil
end

-- Kinds that need no quest: a note needs text; the others carry the
-- player's position (and any text as a hint).
local FREE = { note = true, go = true, train = true, bind = true, fly = true, hearth = true }

--- Build a step of `kind` for a quest (or a free step) where the player is.
function E.NewStep(kind, questID, text)
    local s = Here()
    s.k = kind
    if FREE[kind] then
        s.text = Trim(text)
        if kind == "note" and not s.text then return nil end
        if kind == "go" and not s.m then return nil end            -- nowhere to go
        if (kind == "train" or kind == "bind") and not s.text then
            local ok, name = pcall(UnitName, "target")
            s.n = ok and Str(name) or nil
        end
        if kind == "hearth" then s.m, s.x, s.y = nil, nil, nil end -- no place
        return s
    end
    if not Num(questID) then return nil end
    s.q = questID
    if kind == "accept" or kind == "turnin" then
        local ok, name = pcall(UnitName, "target")
        s.n = ok and Str(name) or nil
    elseif kind == "do" then
        -- No text is stored (Alex, 2026-09-22): the guide reads the
        -- objective and its progress from the alt's own quest log. The
        -- step points at the first objective not yet finished.
        s.o = 1
        local ql = rawget(_G, "C_QuestLog")
        if ql and ql.GetQuestObjectives then
            local okO, list = pcall(ql.GetQuestObjectives, questID)
            if okO and type(list) == "table" then
                for i, ob in ipairs(list) do
                    if type(ob) == "table" and ob.finished ~= true then s.o = i break end
                end
            end
        end
    else
        return nil
    end
    return s
end

-- ------------------------------------------------------------ routes

--- The slug build_route.py would give this character (same rule: each
-- word capitalised, non-alphanumerics dropped, joined).
local function Clean(v)
    local out = {}
    for w in tostring(v or "x"):gmatch("%w+") do out[#out + 1] = w:sub(1, 1):upper() .. w:sub(2):lower() end
    return #out > 0 and table.concat(out) or "X"
end
function E.SlugForPlayer()
    local okF, faction = pcall(UnitFactionGroup, "player")
    local okR, race = pcall(function() return select(2, UnitRace("player")) end)
    local okC, class = pcall(function() return select(2, UnitClass("player")) end)
    local okN, name = pcall(UnitName, "player")
    return ("%s_%s_%s_%s"):format(Clean(okF and faction), Clean(okR and race), Clean(okC and class), Clean(okN and name)),
        okF and Str(faction) or nil, okR and Str(race) or nil, okC and Str(class) or nil
end

--- A new empty route for this character, named `name` (or after the
-- race and class), selected in the guide, logged as a "new" op so
-- build_route.py creates its step file. A second route with the same name
-- gets a numbered slug.
function E.NewRoute(name)
    local base, faction, race, class = E.SlugForPlayer()
    local map = ns.Guide.PlayerPos()
    local okL, level = pcall(UnitLevel, "player")
    level = okL and Num(level) and level or nil
    name = Trim(name) or ("%s %s (built)"):format(race or "?", class and (class:sub(1, 1) .. class:sub(2):lower()) or "?")
    local slug = base .. "_" .. Clean(name)
    ns.Routes = ns.Routes or {}
    local taken = {}
    for _, r in ipairs(ns.Routes) do taken[r.slug] = true end
    local n, candidate = 1, slug
    while taken[candidate] do n = n + 1; candidate = slug .. n end
    slug = candidate
    local route = {
        slug = slug, name = name, faction = faction, race = race, class = class, map = Num(map) and map or nil,
        levels = { level, level }, steps = {},
    }
    ns.Routes[#ns.Routes + 1] = route
    Log(route, { op = "new", name = route.name, faction = faction, race = race, class = class, map = route.map, level = level })
    if ns.db and ns.db.guide then ns.db.guide.route = slug end     -- follow it now
    if ns.Guide.Refresh then ns.Guide.Refresh() end
    return route
end

--- The route the guide follows, or a new one for this character.
function E.EnsureRoute()
    return ns.Guide.PickRoute() or E.NewRoute(nil)
end

--- Delete a route: gone from ns.Routes, logged as a "drop" op so
-- build_route.py retires its step file. The guide falls back to its
-- best match.
function E.DeleteRoute(route)
    if not route then return false end
    Log(route, { op = "drop" })
    for i, r in ipairs(ns.Routes or {}) do
        if r == route then table.remove(ns.Routes, i) break end
    end
    if ns.db and ns.db.guide and ns.db.guide.route == route.slug then ns.db.guide.route = "auto" end
    if ns.Guide.Refresh then ns.Guide.Refresh() end
    return true
end

--- Append a step at the END of the route (the builder's "next step").
function E.Append(route, kind, questID, text)
    if not route then return nil end
    local step = E.NewStep(kind, questID, text)
    if not step then return nil end
    if not E.Insert(route, #route.steps, step) then return nil end
    return #route.steps
end

--- Insert after the guide's current step (or at the end when the route is
-- complete). Returns the new step's index or nil.
function E.InsertHere(route, kind, questID, text)
    if not route then return nil end
    local step = E.NewStep(kind, questID, text)
    if not step then return nil end
    local at = (ns.Guide.CurrentIndex(route) or (#route.steps + 1)) - 1
    -- "insert at the current step" reads as: the new step becomes the one to
    -- do next, so it goes BEFORE the current one.
    if not E.Insert(route, at, step) then return nil end
    return at + 1
end
