--[[ Salus Novus -- Health Bars: the boss's health with a marker per
health-triggered ability.

Some abilities are cast at a HEALTH, not a time (Durgen Dirgehammer's
Intimidating Shout: 47.4% and 47.8% in two pulls, 16 s and 11 s in).
The generator tags them (`ability.health = { pct }`), the timed anchors
leave them alone, and this anchor draws one bar for the engaged boss with
a vertical marker per such ability at its threshold (Alex's design).

Boss health is a SECRET value on Forever: an addon cannot read or compare
it, but the client lets a StatusBar display it. Every SetValue is pcall'd;
if the client refuses, the fill goes dim, the markers stay, and `/sn
health` says so. Nothing here does arithmetic on the value.

Nothing here polls either. Like a nameplate, the bar is driven by the
client: UNIT_HEALTH / UNIT_MAXHEALTH for the one unit it follows (filtered
by RegisterUnitEvent where the client has it), and the unit itself is
re-resolved only when something that can change it fires -- the target
or focus changing, a nameplate appearing or going, the encounter engage
list -- never on a timer. Outside a fight nothing is registered at all.
]]

local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8x8"
local MAX_MARKERS = 8
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
local markers = {}
H._markers = markers            -- test seam
local state = { boss = nil, unit = nil, abilities = {}, preview = nil, previewTick = nil,
                refused = false, feeds = 0, refusals = 0, events = 0 }
H.state = state

local function Origin() return "TOP" end
local function SavePosition() ns.SaveAnchor(frame, "healthPos") end
local function RestorePosition()
    if not frame then return end
    -- Under the queue (TOPLEFT +156,-70), above the character's feet.
    ns.RestoreAnchor(frame, "healthPos", "TOP", 0, -150, "CENTER")
end
ns.HealthBarsRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "healthPos", restore = "HealthBarsRestorePosition" })

local function MakeMarker()
    local m = CreateFrame("Frame", nil, frame)
    m:SetSize(2, 10)
    m.line = m:CreateTexture(nil, "OVERLAY")
    m.line:SetTexture(SOLID)
    m.line:SetAllPoints()
    m.label = m:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(m.label, 11, "OUTLINE")
    m.label:SetPoint("BOTTOM", m, "TOP", 0, 2)
    m:Hide()
    return m
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusHealthBars", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(260, 40)
    frame:Hide()

    frame.name = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.name, 11, "OUTLINE")
    frame.name:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    frame.name:SetTextColor(0.9, 0.9, 0.95, 1)

    frame.bar = CreateFrame("StatusBar", nil, frame)
    frame.bar:SetPoint("BOTTOMLEFT", 0, 0)
    frame.bar:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.bar:SetHeight(16)
    frame.bar:SetStatusBarTexture(SOLID)
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(1)
    frame.bg = frame.bar:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetTexture(SOLID)
    frame.bg:SetAllPoints()
    frame.bg:SetVertexColor(0, 0, 0, 0.6)
    frame.border = ns.CreateBorder(frame.bar)
    frame.border:Layout(frame.bar, 1, 0)
    frame.border:SetColor(0, 0, 0, 0.9)
    frame.border:Show()
    for i = 1, MAX_MARKERS do markers[i] = MakeMarker() end

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame.name, "TOP", 0, 3)
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

--- Which unit is the boss? The first candidate whose name reads as the
-- boss's NPC name. A secret name cannot be compared, so it does not match.
local function BossName(boss)
    local npc = boss and boss.npcs and boss.npcs[1]
    return npc and npc.name or (boss and boss.name)
end

--- Does unit id `u` exist and carry the boss's name right now? Secret or
-- unreadable answers count as "no": the scan moves on, the tick lets go.
local function UnitIsBoss(u, boss)
    local want = BossName(boss)
    if type(want) ~= "string" or ns.IsSecret(want) then return false end
    if type(UnitExists) ~= "function" or type(UnitName) ~= "function" then return false end
    local okE, exists = pcall(UnitExists, u)
    if not (okE and exists and not ns.IsSecret(exists)) then return false end
    local okN, name = pcall(UnitName, u)
    return okN and type(name) == "string" and not ns.IsSecret(name) and name == want
end

local function FindUnit(boss)
    for _, u in ipairs(CANDIDATES) do
        if UnitIsBoss(u, boss) then return u end
    end
    return nil
end

--- Put the unit's health on the bar. The values may be secret: they go
-- straight to the widget and are never compared or computed with.
local function Feed()
    if not frame or not state.unit then return end
    local u = state.unit
    local ok = pcall(function()
        local mx, cur = UnitHealthMax(u), UnitHealth(u)
        frame.bar:SetMinMaxValues(0, mx)
        frame.bar:SetValue(cur)
    end)
    state.feeds = state.feeds + 1
    if ok then
        if state.refused then
            state.refused = false
            frame.bar:SetAlpha(1)
        end
    else
        state.refusals = state.refusals + 1
        if not state.refused then
            state.refused = true
            frame.bar:SetAlpha(0.3)     -- the markers still mean something; the fill does not
        end
    end
end

--- The markers: one per health-triggered ability routed here, at its
-- threshold, in the ability's colour when it has one.
local function Refresh()
    if not frame then return end
    local opts = O() or {}
    local w, h = opts.width or 260, opts.height or 16
    frame:SetSize(w, h + 24)
    frame.bar:SetHeight(h)
    local c = opts.color or {}
    frame.bar:SetStatusBarColor(c.r or 0.25, c.g or 0.8, c.b or 0.3, 1)
    frame.name:SetShown(opts.showName ~= false)
    frame.name:SetText(state.preview and "Sample boss" or ns.S(BossName(state.boss)))
    local list = state.abilities
    for i = 1, MAX_MARKERS do
        local m, a = markers[i], list[i]
        if not a then
            m:Hide()
        else
            local pct = math.max(0, math.min(100, a.health.pct))
            m:SetHeight(h + 6)
            m:ClearAllPoints()
            m:SetPoint("BOTTOM", frame.bar, "BOTTOMLEFT", w * pct / 100, -3)
            local cr, cg, cb = ns.Abilities.Color(a.spellID)
            m.line:SetVertexColor(cr or 1, cg or 1, cb or 1, 0.95)
            ns.SetFontSafe(m.label, opts.labelSize or 11, "OUTLINE")
            m.label:SetText(ns.Abilities.Rename(a.spellID) or ns.S(a.name))
            m.label:SetTextColor(cr or 1, cg or 1, cb or 1, 1)
            m:Show()
        end
    end
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

local function Placeholders()
    return {
        { spellID = nil, name = "Ability at 50%", health = { pct = 50 } },
        { spellID = nil, name = "Ability at 20%", health = { pct = 20 } },
    }
end

-- ------------------------------------------------------------ the unit
-- The bar's own event frame. Armed on a pull of a boss that has health
-- abilities, disarmed at the end: while idle it costs nothing.
local ev = CreateFrame("Frame")
H._events = ev                  -- test seam
local HEALTH_EVENTS = { "UNIT_HEALTH", "UNIT_MAXHEALTH" }
-- Anything that can move the boss to another unit id, or take it away.
local UNIT_EVENTS = { "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED",
                      "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
                      "INSTANCE_ENCOUNTER_ENGAGE_UNIT" }

--- Follow unit id `u` (or none). Health events are filtered to the one
-- unit by the client where RegisterUnitEvent exists; otherwise every
-- UNIT_HEALTH arrives and the handler drops the ones for other units.
local function SetUnit(u)
    state.unit = u
    for _, e in ipairs(HEALTH_EVENTS) do pcall(ev.UnregisterEvent, ev, e) end
    if not u then return end
    for _, e in ipairs(HEALTH_EVENTS) do
        -- Trust the registration only if the frame says it took (Core.lua's
        -- bus does the same): a client without the unit form, or a stub
        -- that swallows the call, falls back to the plain event.
        local took = false
        if ev.RegisterUnitEvent then
            local ok = pcall(ev.RegisterUnitEvent, ev, e, u)
            local ok2, r = pcall(ev.IsEventRegistered, ev, e)
            took = ok and ok2 and r and true or false
        end
        if not took then pcall(ev.RegisterEvent, ev, e) end
    end
    Feed()
end

local function Arm()
    for _, e in ipairs(UNIT_EVENTS) do pcall(ev.RegisterEvent, ev, e) end
end
local function Disarm()
    pcall(ev.UnregisterAllEvents, ev)
    state.unit = nil                -- whatever we followed is stale by the time we re-arm
end

--- The unit id is only a slot: the tank retargets, a nameplate id is
-- reused by an add. Keep it while it still holds the boss, else look again.
local function Resolve()
    if not state.boss then return end
    if state.unit and UnitIsBoss(state.unit, state.boss) then return end
    SetUnit(FindUnit(state.boss))
end

ev:SetScript("OnEvent", function(_, event, unit)
    if state.preview or not state.boss then return end
    state.events = state.events + 1
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        if unit == state.unit then Feed() end
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        -- A plate for the boss while we have no unit (or a reused id).
        if not state.unit or unit == state.unit then Resolve() end
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if unit == state.unit then SetUnit(nil); Resolve() end
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
    if state.boss then state.abilities = AbilitiesFor(state.boss) end
    if state.boss and #state.abilities > 0 then
        Refresh()
        frame:Show()
        Arm()                       -- back on mid-fight: pick the unit up again
        if not state.unit then SetUnit(FindUnit(state.boss)) end
    elseif unlocked then
        Disarm()
        state.abilities = Placeholders()
        Refresh()
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.6)
        frame:Show()
    else
        Disarm()
        if state.boss then Refresh() end     -- markers off too, not just the frame
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Health Bars")
H.Apply = Apply

-- A fight: the bar appears only when the boss has a health-triggered
-- ability; the unit is looked up on the pull and again whenever the
-- client says a unit id changed (the tank may not have it targeted yet).
local function OnEncounter(on)
    if not on then
        Disarm()
        state.boss, state.unit, state.abilities = nil, nil, {}
        state.refused = false
        if frame then frame:SetAlpha(1); frame:Hide() end
        return
    end
    state.boss = ns.Timers.Boss()
    state.abilities = state.boss and AbilitiesFor(state.boss) or {}
    state.unit = nil
    if not Enabled() or #state.abilities == 0 then
        Disarm()
        if frame then frame:Hide() end
        return
    end
    Build()
    Refresh()
    frame:Show()
    Arm()
    SetUnit(FindUnit(state.boss))
end

ns.Timers.Register({ OnEncounter = OnEncounter })

-- Options-page preview: two markers and a fill draining over twelve seconds.
function ns.HealthBarsPreviewStart(stage)
    Build()
    state.preview = stage
    state.abilities = Placeholders()
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, -4)
    Apply()
    frame.bar:SetMinMaxValues(0, 100)
    local t0 = GetTime()
    if state.previewTick then state.previewTick:Cancel() end
    state.previewTick = C_Timer.NewTicker(0.1, function()
        if not state.preview then return end
        local v = 100 - ((GetTime() - t0) % 12) / 12 * 100
        frame.bar:SetValue(v)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", stage, "CENTER", 0, -4)
    end)
    frame.bar:SetValue(100)
end

function ns.HealthBarsPreviewStop()
    if state.previewTick then
        state.previewTick:Cancel()
        state.previewTick = nil
    end
    if not state.preview then return end
    state.preview = nil
    state.abilities = state.boss and AbilitiesFor(state.boss) or {}
    if frame then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("MEDIUM")
        RestorePosition()
    end
    Apply()
end

--- /sn health: is the client letting the bar show the secret value?
ns.Commands.health = function()
    ns.Print(string.format("health bars: boss=%s unit=%s markers=%d events=%d feeds=%d refused=%s (%d)",
        ns.S(state.boss and state.boss.name or "-"), ns.S(state.unit or "-"), #state.abilities,
        state.events, state.feeds, tostring(state.refused), state.refusals))
end
