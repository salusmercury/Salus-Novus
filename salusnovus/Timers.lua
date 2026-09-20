--[[ Salus Novus -- Timers: the hub every anchor listens to.

MerkUI's Timers.lua with the BigWigs intake replaced by our own log-mined
schedule (Schedule.lua). On ENCOUNTER_START for a boss we know, one record
per observed cast, timed from the pull; anchors render them and never read
the data file themselves. What is NOT here: BigWigs, Blizzard's timeline,
nameplate timers, pause/resume, stages, specials -- none of which exist or
work on Forever (measured; wow_forever_notes.md section 10).

A record that reaches its moment is not removed at once: it holds for
`hold` seconds reading "now" (the bar's grace), then leaves and announces
itself with OnStop. Nothing is ever slid forward.
]]

local _, ns = ...

local T = {}
ns.Timers = T

--------------------------------------------------------------------------------
-- State (all declared up here: a local used above its declaration line is a
-- silent nil global -- that has bitten this codebase twice)
--------------------------------------------------------------------------------
local bars = {}
T.bars = bars

local state = {
    active = false,      -- a boss is engaged
    name = nil,
    encounterID = nil,
    boss = nil,          -- ns.Data record for the engaged boss, if known
    startedAt = nil,
    tick = nil,          -- 0.2s ticker while anything is live
    sorted = nil,        -- cached sort, invalidated on change
    simulate = nil,      -- C_Timer handle ending a /sn test fight
    watch = nil,         -- wipe-watch ticker
    sawInProgress = false,
}
T.state = state

local listeners = {}

local diag = {
    encName = nil, encID = nil, bossFound = nil,
    starts = 0, expired = 0,
    -- Timers the intake REFUSED. Printed even when zero: "the log had no
    -- casts" and "we threw every cast away" must not read the same.
    rejKey = 0, rejDur = 0, lastRej = nil,
}
T.diag = diag

--------------------------------------------------------------------------------
-- Listeners
--------------------------------------------------------------------------------
-- listener = { OnChange=fn(), OnTick=fn(now), OnEncounter=fn(active),
--              OnStart=fn(bar), OnStop=fn(bar) }
-- Every field is optional; Fire skips a listener that does not define one.
function T.Register(l)
    listeners[#listeners + 1] = l
end

-- One report per listener per event, per session. OnTick fires five times a
-- second, so a throwing listener would make chat unusable mid-pull.
local fireErrShown = {}
local function Fire(what, ...)
    for _, l in ipairs(listeners) do
        local fn = l[what]
        if fn then
            local ok, err = pcall(fn, ...)
            if not ok then
                local seen = fireErrShown[l]
                if not seen then seen = {}; fireErrShown[l] = seen end
                if not seen[what] then
                    seen[what] = true
                    ns.Print("anchor error in " .. what .. ": " .. tostring(err))
                    ns.Print("(further " .. what .. " errors from this anchor are silenced; /reload to reset)")
                end
            end
        end
    end
end
T._fireErrShown = fireErrShown     -- test seam

-- Forward: ClearFakes (above the definition) and the ticker both call it
-- (MerkUI landmine 10).
local SettleDown

local function Changed()
    state.sorted = nil
    Fire("OnChange")
end

--------------------------------------------------------------------------------
-- Reads
--------------------------------------------------------------------------------
function T.Sorted()
    if state.sorted then return state.sorted end
    local list = {}
    for _, b in pairs(bars) do list[#list + 1] = b end
    table.sort(list, function(a, b)
        if a.at == b.at then return tostring(a.id) < tostring(b.id) end
        return a.at < b.at
    end)
    state.sorted = list
    return list
end

function T.IsActive() return state.active end
function T.Any() return next(bars) ~= nil end
function T.Boss() return state.boss end
function T.EncounterID() return state.encounterID end
--- The id reminders and data are keyed by: the boss's first id when the
-- fight is a known boss (a pull may arrive on one of its variant ids).
function T.BossEncounterID()
    return (state.boss and state.boss.encounterID) or state.encounterID
end
function T.StartedAt() return state.startedAt end

--- Client name when it has one and it is not secret; our fallback otherwise.
-- In combat the fallback is what shows, which is why the data file carries
-- names at all.
function T.AbilityName(b)
    -- Alex's rename first (Abilities.lua), then the client, then the data.
    if ns.Abilities and b.spellID then
        local mine = ns.Abilities.Rename(b.spellID)
        if mine then return mine end
    end
    if b.spellID and C_Spell and C_Spell.GetSpellName then
        local ok, nm = pcall(C_Spell.GetSpellName, b.spellID)
        if ok and type(nm) == "string" and nm ~= "" and not ns.IsSecret(nm) then return nm end
    end
    return ns.S(b.name)
end

--- The colour Alex gave the ability's name, or nil (anchors use their own).
function T.AbilityColor(b)
    if ns.Abilities and b and b.spellID then return ns.Abilities.Color(b.spellID) end
    return nil
end

--- Does this record go to `anchor`? Fakes and placeholders always do.
function T.RoutedTo(b, anchor)
    if not ns.Abilities or not b or b.fake then return true end
    -- No spell id, no card to opt it in: Messages is opt-in, so it stays
    -- out; the opt-out anchors still show it.
    if not b.spellID then return ns.Abilities.ROUTE_DEFAULT[anchor] ~= false end
    return ns.Abilities.Routed(b.spellID, anchor)
end

function T.IconOf(b)
    if b.icon and not ns.IsSecret(b.icon) then return b.icon end
    if b.spellID and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, b.spellID)
        if ok and tex and not ns.IsSecret(tex) then return tex end
    end
    return 134400
end

--------------------------------------------------------------------------------
-- Fakes (option-page previews and tests)
--------------------------------------------------------------------------------
-- Drawn from the data so a preview shows real ability names: n timers,
-- `spacing` seconds apart, frozen far in the future when `frozen`.
function T.FakeBars(n, spacing, frozen)
    local out = {}
    local now = GetTime()
    local boss = ns.Schedule and ns.Schedule.SampleBoss()
    local events = boss and ns.Schedule.EventsFor(boss) or {}
    for i = 1, (n or 6) do
        local e = events[i]
        local d = spacing * i + 2
        out[#out + 1] = {
            id = "fake:" .. i, key = "fake:" .. i,
            name = e and e.name or ("Ability " .. i), spellID = e and e.spellID or nil,
            pulls = e and e.pulls or 1,
            duration = d, at = now + d + (frozen and 100000 or 0), hold = 0, fake = true,
        }
    end
    return out
end

-- On-screen tests: put fake records into the live table so every anchor
-- renders them exactly as it would real ones. They run out on their own;
-- ClearFakes removes any left.
local StartTickRef      -- set below once StartTick exists
function T.AddFakes(list)
    for _, b in ipairs(list) do bars[b.id] = b end
    if StartTickRef then StartTickRef() end
    Changed()
end

function T.ClearFakes()
    local n = 0
    for id, b in pairs(bars) do
        if b.fake then
            bars[id] = nil
            n = n + 1
            Fire("OnStop", b)
        end
    end
    if n > 0 then Changed(); SettleDown() end
end

--------------------------------------------------------------------------------
-- Records
--------------------------------------------------------------------------------
local function ClearBars()
    -- Fire OnStop for each so listeners with their own timers cancel too.
    for id, b in pairs(bars) do
        bars[id] = nil
        Fire("OnStop", b)
    end
end

local function StartTick()
    if state.tick then return end
    state.tick = C_Timer.NewTicker(0.2, function()
        local now = GetTime()
        local changed = false
        for id, b in pairs(bars) do
            -- The moment a cast lands, once per record: Messages' cue.
            if not b.landed and b.at <= now then
                b.landed = true
                Fire("OnLand", b)
            end
            if b.at + (b.hold or 0) <= now then
                bars[id] = nil
                diag.expired = diag.expired + 1
                changed = true
                -- Every removal path fires OnStop, or a listener keyed by
                -- b.id leaks (MerkUI measured 600 entries over 50 pulls).
                Fire("OnStop", b)
            end
        end
        if changed then
            Changed()
            SettleDown()
        else
            Fire("OnTick", now)
        end
    end)
end
StartTickRef = StartTick

local function StopTick()
    if state.tick then
        state.tick:Cancel()
        state.tick = nil
    end
end

SettleDown = function()
    if next(bars) ~= nil or state.active then return end
    StopTick()
end

--- The one way a record enters the table. A degenerate row is refused and
-- counted, never shown: NaN/inf durations pass `<= 0` and would squat on
-- every anchor until an encounter boundary.
-- `silent` skips the change broadcast: the pull intake adds every cast
-- at once and announces once after (one refresh per anchor, not one per
-- cast).
local function AddTimer(key, text, duration, icon, extra, silent)
    if key == nil or ns.IsSecret(key) then
        diag.rejKey = diag.rejKey + 1
        diag.lastRej = (key == nil) and "nil key" or "secret key"
        return
    end
    if type(duration) ~= "number" or ns.IsSecret(duration)
        or duration ~= duration or duration >= math.huge or duration < 0 then   -- 0 = an opener on the pull
        diag.rejDur = diag.rejDur + 1
        diag.lastRej = ns.IsSecret(duration) and "secret duration"
            or (type(duration) ~= "number" and "duration is not a number")
            or "duration out of range"
        return
    end
    StartTick()
    diag.starts = diag.starts + 1
    local name = text
    local b = {
        id = key, key = key, name = name,
        nameLower = (type(name) == "string" and not ns.IsSecret(name)) and name:lower() or nil,
        at = GetTime() + duration, duration = duration, icon = icon,
    }
    if extra then
        b.spellID, b.pulls, b.kind, b.seq = extra.spellID, extra.pulls, extra.kind, extra.seq
        -- The hold comes from a saved setting: a hand-edited negative or
        -- non-number would expire the record before it lands (no OnLand).
        local hold = tonumber(extra.hold)
        b.hold = (hold and hold == hold and hold >= 0) and math.min(60, hold) or 0
    end
    bars[b.id] = b
    if not silent then Changed() end
    Fire("OnStart", b)
    return b
end
T.AddTimer = AddTimer

--------------------------------------------------------------------------------
-- Encounter lifecycle
--------------------------------------------------------------------------------
local StartEncounter, EndEncounter

local function InProgress()
    if not IsEncounterInProgress then return nil end
    local ok, r = pcall(IsEncounterInProgress)
    if ok and not ns.IsSecret(r) then return r and true or false end
    return nil
end

-- ENCOUNTER_END is not foolproof (evade bugs, sloppy dungeon scripting, a
-- disconnect). Poll IsEncounterInProgress while a fight is up; only trust
-- a "false" after a "true". Not for a simulated fight, which the client
-- never knows about.
local function StartWatch()
    if state.watch then state.watch:Cancel() end
    state.watch = nil
    if state.simulate or not IsEncounterInProgress then return end
    state.sawInProgress = false
    state.watch = C_Timer.NewTicker(2, function()
        if not state.active then return end
        local p = InProgress()
        if p == true then
            state.sawInProgress = true
        elseif p == false and state.sawInProgress then
            EndEncounter()
        end
    end)
end

StartEncounter = function(encounterID, name)
    state.active = true
    state.startedAt = GetTime()
    state.name, state.encounterID = name, encounterID
    state.boss = encounterID and ns.BossByEncounter(encounterID) or nil
    diag.encName, diag.encID = name, encounterID
    diag.bossFound = state.boss and state.boss.name or false
    diag.starts, diag.expired = 0, 0
    diag.rejKey, diag.rejDur, diag.lastRej = 0, 0, nil
    ClearBars()
    StartTick()
    Changed()
    Fire("OnEncounter", true)
    -- The intake: one record per CLUSTERED cast (Schedule.Lanes -- the same
    -- casts the visualizer draws), timed from the pull. Raw per-pull events
    -- would put every pull's copy of a cast on the bars once a boss has
    -- been logged twice.
    if state.boss then
        local hold = (ns.db and ns.db.bars and ns.db.bars.grace) or 2.5
        local seq = 0
        for _, o in ipairs(ns.Schedule.Lanes(state.boss)) do
            for ci, t in ipairs(o.lanes.casts) do
                seq = seq + 1
                AddTimer(tostring(o.a.spellID) .. "#" .. seq, o.a.name, t, nil,
                    { spellID = o.a.spellID, pulls = o.lanes.support and o.lanes.support[ci] or 1,
                      seq = seq, hold = hold }, true)
            end
        end
        Changed()   -- once for the whole intake
    end
    StartWatch()
end

EndEncounter = function()
    if not state.active then return end   -- wipe watch AND a late END: one end, one OnEncounter(false)
    if state.watch then
        state.watch:Cancel()
        state.watch = nil
    end
    if state.simulate then
        pcall(state.simulate.Cancel, state.simulate)
        state.simulate = nil
    end
    state.active = false
    state.startedAt = nil
    state.name, state.encounterID, state.boss = nil, nil, nil
    ClearBars()
    SettleDown()
    Changed()
    Fire("OnEncounter", false)
end

T.StartEncounter, T.EndEncounter = StartEncounter, EndEncounter

--- /sn test: the real StartEncounter, ended after the boss's average
-- fight length, so bars, reminders and the label all take the live path.
function T.Simulate(encounterID)
    local boss = ns.BossByEncounter(encounterID)
    if not boss then return false end
    if state.active then EndEncounter() end
    encounterID = boss.encounterID or encounterID
    state.simulate = true                    -- so StartEncounter skips the wipe watch
    StartEncounter(encounterID, boss.name)
    state.simulate = nil
    if C_Timer and C_Timer.NewTimer then
        -- The boss's average kill, else long enough for every scheduled
        -- cast to land (capped at 60 s for a boss with no logged length).
        local length = boss.avgLength or math.min(60, ns.Schedule.FightEnd(boss))
        state.simulate = C_Timer.NewTimer(length, function()
            state.simulate = nil
            if state.active and state.encounterID == encounterID then EndEncounter() end
        end)
    end
    return true
end

ns.On("ENCOUNTER_START", function(id, name)
    if ns.IsSecret(id) then id = nil else id = tonumber(id) end
    if ns.IsSecret(name) then name = nil end
    if state.active and (state.simulate or id ~= nil) then
        -- A real pull always restarts: a DIFFERENT boss without the last one
        -- ending, the SAME boss pulled again with no END seen, and any pull
        -- during a /sn test (the simulation must never absorb a real
        -- fight and then end it from its own timer). Only a start with no
        -- readable id while a fight is up is a fill-in.
        EndEncounter()
        StartEncounter(id, name)
    elseif state.active then
        state.encounterID = state.encounterID or id
        state.name = state.name or name
        diag.encName, diag.encID = state.name, state.encounterID
    else
        StartEncounter(id, name)
    end
end)

ns.On("ENCOUNTER_END", function(id)
    if ns.IsSecret(id) then id = nil else id = tonumber(id) end
    -- Only the fight we are tracking; a foreign END must not kill the pull.
    if state.active and (state.encounterID == nil or id == nil or id == state.encounterID) then
        EndEncounter()
    end
end)

local function OnZone()
    local inProg = InProgress()
    if inProg == true then
        -- A /reload or a disconnect lands here mid-fight.
        if not state.active then StartEncounter(nil, nil) end
    elseif state.active then
        EndEncounter()
    elseif next(bars) ~= nil then
        ClearBars()
        Changed()
        SettleDown()
    end
end
ns.On("PLAYER_ENTERING_WORLD", OnZone)
ns.On("ZONE_CHANGED_NEW_AREA", OnZone)
ns.On("PLAYER_REGEN_ENABLED", function()
    if state.active and not state.simulate and InProgress() == false then EndEncounter() end
end)

--------------------------------------------------------------------------------
-- Status
--------------------------------------------------------------------------------
function T.Status()
    ns.Print(("hub: engaged=%s  live timers=%d"):format(tostring(state.active), #T.Sorted()))
    ns.Print("  modules: Boss Warnings " .. (ns.ModuleOn("bossWarnings") and "on" or "off"))
    if diag.encName or diag.encID then
        ns.Print(("  last encounter: %s (id %s) -- boss data %s"):format(
            tostring(diag.encName), tostring(diag.encID), tostring(diag.bossFound)))
    else
        ns.Print("  no boss engaged since login/reload")
    end
    ns.Print(("  timers: started %d, ran out %d  |  REFUSED %d (secret or nil key %d, bad duration %d)%s"):format(
        diag.starts, diag.expired, diag.rejKey + diag.rejDur, diag.rejKey, diag.rejDur,
        diag.lastRej and ("  -- last: " .. tostring(diag.lastRej)) or ""))
    local now = GetTime()
    local live = T.Sorted()
    if #live > 0 then
        local bits = {}
        for _, b in ipairs(live) do
            bits[#bits + 1] = ("%s in %.0fs"):format(ns.S(b.name), b.at - now)
        end
        ns.Print("  live now: " .. table.concat(bits, ",  "))
    end
end
ns.Commands.status = function() T.Status() end
