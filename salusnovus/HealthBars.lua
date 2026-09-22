--[[ Salus Novus -- Health Bars: one bar per boss with a marker per
health-triggered ability.

Some abilities are cast at a HEALTH, not a time (Durgen Dirgehammer's
Intimidating Shout: 47.4% and 47.8% in two pulls, 16 s and 11 s in).
The generator tags them (`ability.health = { pct }`), the timed anchors
leave them alone, and this anchor draws a bar per NPC that has such an
ability, with a vertical marker at each threshold (Alex's design). A
council fight -- several bosses with thresholds -- is a STACK of bars,
one per NPC, growing up or down with a gap; the boss's name sits above,
inside, below or nowhere; the ability's icon can hang under its marker
(Alex, 2026-09-20).

Boss health is a SECRET value on Forever: an addon cannot read or compare
it, but the client lets a StatusBar display it. Every SetValue is pcall'd;
if the client refuses, the fill goes dim, the markers stay, and `/sn
health` says so. Nothing here does arithmetic on the value.

Nothing here polls either. Like a nameplate, the bars are driven by the
client: UNIT_HEALTH / UNIT_MAXHEALTH for the units they follow (filtered
by RegisterUnitEvent when there is one unit and the client has it), and
a unit is re-resolved only when something that can change it fires -- the
target or focus changing, a nameplate appearing or going, the encounter
engage list -- never on a timer. Outside a fight nothing is registered.
]]

local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8x8"
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local MAX_MARKERS = 8
local MAX_ROWS = 5
local CANDIDATES = { "target", "focus", "boss1", "boss2", "boss3", "boss4", "boss5" }
for i = 1, 40 do CANDIDATES[#CANDIDATES + 1] = "nameplate" .. i end

local H = {}
ns.HealthBars = H

local function O() return ns.db and ns.db.healthBars end
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local rows = {}                 -- pooled row frames, one per boss on screen
H._rows = rows                  -- test seam
H._markers = nil                -- row 1's markers (test seam, set in Build)
-- `live` = the bosses of this pull: { name, unit, abilities, refused }.
-- state.unit / state.abilities mirror row 1 for callers that predate the
-- stack (and the tests).
local state = { boss = nil, unit = nil, abilities = {}, live = {}, preview = nil, previewTick = nil,
                refused = false, feeds = 0, refusals = 0, events = 0 }
H.state = state

local function Dir() local o = O(); return (o and o.direction == "down") and "down" or "up" end
local function Origin() return Dir() == "up" and "BOTTOM" or "TOP" end
local function SavePosition() ns.SaveAnchor(frame, "healthPos") end
local function RestorePosition()
    if not frame then return end
    -- Alex's layout (2026-09-20): top right, above the Bars column.
    ns.RestoreAnchor(frame, "healthPos", "TOP", 425, 235, "CENTER")
end
ns.HealthBarsRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "healthPos", restore = "HealthBarsRestorePosition" })

--- Where the name goes: "inside" (default, Alex), "above", "below", "off".
-- A stored showName = false from before the choice reads as "off".
local function NamePos(opts)
    local p = opts.namePos
    if p == "inside" or p == "below" or p == "off" then return p end
    if p == nil and opts.showName == false then return "off" end
    if p == "above" then return "above" end
    return "inside"
end

local function MakeMarker(row)
    local m = CreateFrame("Frame", nil, row)
    m:SetSize(2, 10)
    m.line = m:CreateTexture(nil, "OVERLAY")
    m.line:SetTexture(SOLID)
    m.line:SetAllPoints()
    m.label = m:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(m.label, 11, "OUTLINE")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 2)
    -- The ability's icon, hung under the marker (optional).
    m.icon = m:CreateTexture(nil, "ARTWORK")
    m.icon:SetSize(16, 16)
    m.icon:SetPoint("TOP", m, "BOTTOM", 0, -1)
    m.icon:Hide()
    m:Hide()
    return m
end

local function MakeRow(i)
    local r = CreateFrame("Frame", nil, frame)
    r:SetSize(260, 40)
    r.bar = CreateFrame("StatusBar", nil, r)
    r.bar:SetHeight(20)
    -- The name is the BAR's region so it draws over the fill when it sits
    -- inside (a region of the row would be under the bar, a child frame).
    r.name = r.bar:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(r.name, 11, "OUTLINE")
    r.name:SetTextColor(0.9, 0.9, 0.95, 1)
    r.bar:SetStatusBarTexture(SOLID)
    r.bar:SetMinMaxValues(0, 1)
    r.bar:SetValue(1)
    r.bg = r.bar:CreateTexture(nil, "BACKGROUND")
    r.bg:SetTexture(SOLID)
    r.bg:SetAllPoints()
    r.bg:SetVertexColor(0, 0, 0, 0.6)
    r.border = ns.CreateBorder(r.bar)
    r.border:Layout(r.bar, 1, 0)
    r.border:SetColor(0, 0, 0, 0.9)
    r.border:Show()
    r.markers = {}
    for k = 1, MAX_MARKERS do r.markers[k] = MakeMarker(r) end
    r:Hide()
    rows[i] = r
    return r
end

local function Row(i) return rows[i] or MakeRow(i) end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusHealthBars", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(260, 40)
    frame:Hide()

    local r1 = Row(1)
    -- Row 1's widgets under their old names: the bar, the name, the markers.
    frame.bar, frame.name = r1.bar, r1.name
    H._markers = r1.markers

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Health Bars  \194\183  drag to move")
    frame.unlockLabel:Hide()

    ns.RegisterMovable(frame, "healthPos", Origin)
    frame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)
    RestorePosition()
    return frame
end

--- The encounter's headline NPC name (the first npc, else the boss name).
local function BossName(boss)
    local npc = boss and boss.npcs and boss.npcs[1]
    return npc and npc.name or (boss and boss.name)
end

--- Does unit id `u` exist and carry `want` as its name right now? Secret
-- or unreadable answers count as "no": the scan moves on, the tick lets go.
local function UnitIsNamed(u, want)
    if type(want) ~= "string" or ns.IsSecret(want) then return false end
    if type(UnitExists) ~= "function" or type(UnitName) ~= "function" then return false end
    local okE, exists = pcall(UnitExists, u)
    if not (okE and exists and not ns.IsSecret(exists)) then return false end
    local okN, name = pcall(UnitName, u)
    return okN and type(name) == "string" and not ns.IsSecret(name) and name == want
end

--- The first candidate unit carrying `want`, skipping ids another boss of
-- this pull already holds.
local function FindUnit(want, taken)
    for _, u in ipairs(CANDIDATES) do
        if not (taken and taken[u]) and UnitIsNamed(u, want) then return u end
    end
    return nil
end

--- Put a unit's health on its bar. The values may be secret: they go
-- straight to the widget and are never compared or computed with.
local function Feed(e)
    if not frame or not e or not e.unit or not e.row then return end
    local u, r = e.unit, e.row
    local ok = pcall(function()
        local mx, cur = UnitHealthMax(u), UnitHealth(u)
        r.bar:SetMinMaxValues(0, mx)
        r.bar:SetValue(cur)
    end)
    state.feeds = state.feeds + 1
    if ok then
        if e.refused then
            e.refused = false
            r.bar:SetAlpha(1)
        end
    else
        state.refusals = state.refusals + 1
        if not e.refused then
            e.refused = true
            r.bar:SetAlpha(0.3)     -- the markers still mean something; the fill does not
        end
    end
    local any = false
    for _, x in ipairs(state.live) do if x.refused then any = true end end
    state.refused = any
end

--- Row 1 under the old names, for callers that predate the stack.
local function Mirror()
    local e = state.live[1]
    state.unit = e and e.unit or nil
    local all = {}
    for _, x in ipairs(state.live) do
        for _, a in ipairs(x.abilities) do all[#all + 1] = a end
    end
    state.abilities = all
end

--- Lay the rows out: one per live entry (or the preview / placeholder
-- set), stacked in the direction with the gap, markers at their
-- thresholds in the ability's colour, icons under them when asked.
local function Refresh()
    if not frame then return end
    local opts = O() or {}
    local w, h = opts.width or 260, opts.height or 20
    local namePos = NamePos(opts)
    local nameH = (namePos == "above" or namePos == "below") and ((opts.labelSize or 11) + 6) or 0
    local iconH = opts.showIcons and 20 or 0
    local rowH = h + nameH + iconH
    local gap = opts.spacing or 20
    local n = #state.live
    for i = 1, MAX_ROWS do
        local r, e = Row(i), state.live[i]
        if not e then
            for k = 1, MAX_MARKERS do r.markers[k]:Hide() end   -- off, not just under a hidden row
            r:Hide()
        else
            e.row = r
            r:SetSize(w, rowH)
            r:ClearAllPoints()
            local off = (i - 1) * (rowH + gap)
            if Dir() == "up" then
                r:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, off)
            else
                r:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -off)
            end
            -- The bar sits under the name (above) or at the top (else);
            -- icons hang under the bar; a "below" name goes under those.
            r.bar:ClearAllPoints()
            local barTop = (namePos == "above") and -nameH or 0
            r.bar:SetPoint("TOPLEFT", r, "TOPLEFT", 0, barTop)
            r.bar:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, barTop)
            r.bar:SetHeight(h)
            local c = opts.color or {}
            r.bar:SetStatusBarColor(c.r or 0.25, c.g or 0.8, c.b or 0.3, 1)
            r.name:ClearAllPoints()
            ns.SetFontSafe(r.name, opts.labelSize or 11, "OUTLINE")
            r.name:SetText(ns.S(e.name))
            if namePos == "off" then
                r.name:Hide()
            elseif namePos == "inside" then
                r.name:SetPoint("LEFT", r.bar, "LEFT", 4, 0)
                r.name:Show()
            elseif namePos == "below" then
                r.name:SetPoint("TOPLEFT", r.bar, "BOTTOMLEFT", 0, -(iconH + 2))
                r.name:Show()
            else
                r.name:SetPoint("BOTTOMLEFT", r.bar, "TOPLEFT", 0, 2)
                r.name:Show()
            end
            for k = 1, MAX_MARKERS do
                local m, a = r.markers[k], e.abilities[k]
                if not a then
                    m:Hide()
                else
                    local pct = math.max(0, math.min(100, a.health.pct))
                    m:SetHeight(h + 6)
                    m:ClearAllPoints()
                    m:SetPoint("BOTTOM", r.bar, "BOTTOMLEFT", w * pct / 100, -3)
                    local cr, cg, cb = ns.Abilities.Color(a.spellID)
                    m.line:SetVertexColor(cr or 1, cg or 1, cb or 1, 0.95)
                    ns.SetFontSafe(m.label, opts.labelSize or 11, "OUTLINE")
                    m.label:SetText(ns.Abilities.Rename(a.spellID) or ns.S(a.name))
                    m.label:SetTextColor(cr or 1, cg or 1, cb or 1, 1)
                    if opts.showIcons then
                        m.icon:SetTexture(ns.Timers.IconOf(a) or QUESTION_ICON)
                        m.icon:Show()
                    else
                        m.icon:Hide()
                    end
                    m:Show()
                end
            end
            r:Show()
        end
    end
    frame:SetSize(w, math.max(1, n) * rowH + math.max(0, n - 1) * gap)
    ns.SyncAnchorOrigin(frame, "healthPos")
end
H.Refresh = Refresh

--- Health-triggered abilities of the boss that are routed to this anchor.
local function AbilitiesFor(boss)
    local out = {}
    for _, a in ipairs(ns.Schedule.HealthAbilities(boss)) do
        if ns.Abilities.Routed(a.spellID, "health") then out[#out + 1] = a end
    end
    return out
end

--- One entry per NPC that has a routed health ability, in first-seen
-- order (a council fight is several). Units carried over from `prev` by
-- name so a route toggle mid-fight does not lose the boss.
local function LiveFor(boss, prev)
    local out, byName = {}, {}
    local fallback = BossName(boss)
    for _, a in ipairs(AbilitiesFor(boss)) do
        local nm = a.source or fallback
        local e = byName[nm]
        if not e and #out < MAX_ROWS then
            e = { name = nm, unit = nil, abilities = {}, refused = false }
            byName[nm] = e
            out[#out + 1] = e
        end
        if e then e.abilities[#e.abilities + 1] = a end
    end
    for _, p in ipairs(prev or {}) do
        local e = byName[p.name]
        if e then e.unit, e.refused = p.unit, p.refused end
    end
    -- Rows in the order the pull lists its NPCs: the headline boss on top,
    -- whatever its thresholds; a source the list lacks goes last.
    local rank = {}
    for i, n in ipairs(boss and boss.npcs or {}) do rank[n.name] = rank[n.name] or i end
    for i, e in ipairs(out) do e.rank = rank[e.name] or (1000 + i) end
    table.sort(out, function(a, b) return a.rank < b.rank end)
    return out
end

local function Placeholders()
    return {
        { name = "Sample boss", unit = nil, refused = false, abilities = {
            { spellID = nil, name = "Ability at 50%", health = { pct = 50 } },
            { spellID = nil, name = "Ability at 20%", health = { pct = 20 } } } },
        { name = "Second boss", unit = nil, refused = false, abilities = {
            { spellID = nil, name = "Ability at 35%", health = { pct = 35 } } } },
    }
end

-- ------------------------------------------------------------ the units
-- The anchor's own event frame. Armed on a pull of a boss that has health
-- abilities, disarmed at the end: while idle it costs nothing.
local ev = CreateFrame("Frame")
H._events = ev                  -- test seam
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
-- Anything that can move a boss to another unit id, or take it away.
local UNIT_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
                      "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                      "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }

--- Register the health events for the units in play. One unit: the
-- client filters (RegisterUnitEvent, trusted only if the frame says it
-- took -- Core.lua's bus does the same; a stub that swallows the call
-- falls back). Several: the plain event, filtered in the handler.
local function SetUnits()
    for _, e in ipairs(HEALTH_EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    local units = {}
    for _, x in ipairs(state.live) do if x.unit then units[#units + 1] = x.unit end end
    Mirror()
    if #units == 0 then return end
    for _, e in ipairs(HEALTH_EVENTS) do
        local took = false
        if #units == 1 and ev.RegisterUnitEvent then
            local ok = pcall(ev.RegisterUnitEvent, ev, e, units[1])
            local ok2, r = pcall(ev.IsEventRegistered, ev, e)
            took = ok and ok2 and r and true or false
        end
        if not took then pcall(ev.RegisterEvent, ev, e) end
    end
    for _, x in ipairs(state.live) do Feed(x) end
end

local function Arm()
    for _, e in ipairs(UNIT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
end
local function Disarm()
    pcall(ev.UnregisterAllEvents, ev)
    for _, x in ipairs(state.live) do x.unit = nil end   -- stale by the time we re-arm
    Mirror()
end

--- A unit id is only a slot: the tank retargets, a nameplate id is reused
-- by an add. Each boss keeps its id while it still holds it, else looks
-- again -- never at an id another boss of this pull holds.
local function Resolve()
    if not state.boss then return end
    local taken = {}
    for _, x in ipairs(state.live) do
        if x.unit and UnitIsNamed(x.unit, x.name) then taken[x.unit] = true else x.unit = nil end
    end
    for _, x in ipairs(state.live) do
        if not x.unit then
            x.unit = FindUnit(x.name, taken)
            if x.unit then taken[x.unit] = true end
        end
    end
    SetUnits()
end

ev:SetScript("OnEvent", function(_, event, unit)
    if state.preview or not state.boss then return end
    state.events = state.events + 1
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        for _, x in ipairs(state.live) do
            if x.unit == unit then Feed(x) end
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- A plate while some boss has no unit, or a reused id.
        local care = false
        for _, x in ipairs(state.live) do
            if not x.unit or x.unit == unit then care = true end
        end
        if care then Resolve() end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local hit = false
        for _, x in ipairs(state.live) do
            if x.unit == unit then x.unit = nil; hit = true end
        end
        if hit then Resolve() end
    else
        Resolve()
    end
end)

local function Apply()
    if not Enabled() then
        Disarm()                    -- off mid-fight: nothing runs, not even for a hidden bar
        if frame then frame:Hide() end
        return
    end
    Build()
    if ns.SetMovableScale(frame, state.preview and 1 or ns.AnchorScale()) and not state.preview then RestorePosition() end
    local unlocked = ns.db and ns.db.unlocked
    if state.preview then
        frame.unlockBg:Hide()
        frame.unlockLabel:Hide()
        Refresh()
        frame:Show()
        return
    end
    frame.unlockBg:SetShown(unlocked)
    frame.unlockLabel:SetShown(unlocked)
    -- A route toggled mid-fight comes through ApplyAll: re-read the list,
    -- or an unrouted ability keeps its marker until the next pull.
    if state.boss then state.live = LiveFor(state.boss, state.live) end
    Mirror()
    if state.boss and #state.live > 0 then
        Refresh()
        frame:Show()
        Arm()                       -- back on mid-fight: pick the units up again
        Resolve()
    elseif unlocked then
        Disarm()
        state.live = { Placeholders()[1] }      -- one sample bar on screen while dragging
        Refresh()
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.6)
        frame:Show()
    else
        Disarm()
        if state.boss then Refresh() end     -- markers off too, not just the frame
        if not state.boss then state.live = {} end
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Health Bars")
H.Apply = Apply

-- A fight: the bars appear only when the boss has a health-triggered
-- ability; the units are looked up on the pull and again whenever the
-- client says a unit id changed (the tank may not have it targeted yet).
local function OnEncounter(on)
    if not on then
        Disarm()
        state.boss, state.live = nil, {}
        state.refused = false
        Mirror()
        if frame then
            frame:SetAlpha(1)
            for _, r in ipairs(rows) do r.bar:SetAlpha(1) end
            frame:Hide()
        end
        return
    end
    state.boss = ns.Timers.Boss()
    state.live = state.boss and LiveFor(state.boss) or {}
    Mirror()
    if not Enabled() or #state.live == 0 then
        Disarm()
        if frame then frame:Hide() end
        return
    end
    Build()
    Refresh()
    frame:Show()
    Arm()
    Resolve()
end

ns.Timers.Register({ OnEncounter = OnEncounter })

-- Options-page preview: two bosses, markers, fills draining over twelve seconds.
function ns.HealthBarsPreviewStart(stage)
    Build()
    state.preview = stage
    state.live = Placeholders()
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, -4)
    Apply()
    for _, x in ipairs(state.live) do if x.row then x.row.bar:SetMinMaxValues(0, 100) end end
    local t0 = GetTime()
    if state.previewTick then state.previewTick:Cancel() end
    state.previewTick = C_Timer.NewTicker(0.1, function()
        if not state.preview then return end
        local v = 100 - ((GetTime() - t0) % 12) / 12 * 100
        for i, x in ipairs(state.live) do
            if x.row then x.row.bar:SetValue(math.max(0, v - (i - 1) * 25)) end
        end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", stage, "CENTER", 0, -4)
    end)
    for _, x in ipairs(state.live) do if x.row then x.row.bar:SetValue(100) end end
end

function ns.HealthBarsPreviewStop()
    if state.previewTick then
        state.previewTick:Cancel()
        state.previewTick = nil
    end
    if not state.preview then return end
    state.preview = nil
    state.live = state.boss and LiveFor(state.boss) or {}
    Mirror()
    if frame then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("MEDIUM")
        RestorePosition()
    end
    Apply()
end

--- /sn health: is the client letting the bars show the secret value?
ns.Commands.health = function()
    local parts = {}
    for _, x in ipairs(state.live) do
        parts[#parts + 1] = ns.S(x.name) .. "=" .. ns.S(x.unit or "-") .. (x.refused and " (refused)" or "")
    end
    ns.Print(string.format("health bars: boss=%s units=[%s] markers=%d events=%d feeds=%d refused=%s (%d)",
        ns.S(state.boss and state.boss.name or "-"), table.concat(parts, ", "), #state.abilities,
        state.events, state.feeds, tostring(state.refused), state.refusals))
end
