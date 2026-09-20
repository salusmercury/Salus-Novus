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
                refused = false, lastScan = 0, feeds = 0, refusals = 0 }
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

local function FindUnit(boss)
    local want = BossName(boss)
    if type(want) ~= "string" or ns.IsSecret(want) then return nil end
    if type(UnitExists) ~= "function" or type(UnitName) ~= "function" then return nil end
    for _, u in ipairs(CANDIDATES) do
        local okE, exists = pcall(UnitExists, u)
        if okE and exists and not ns.IsSecret(exists) then
            local okN, name = pcall(UnitName, u)
            if okN and type(name) == "string" and not ns.IsSecret(name) and name == want then
                return u
            end
        end
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

local function Apply()
    if not Enabled() then
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
    if state.boss and #state.abilities > 0 then
        Refresh()
        frame:Show()
    elseif unlocked then
        state.abilities = Placeholders()
        Refresh()
        frame.bar:SetMinMaxValues(0, 1)
        frame.bar:SetValue(0.6)
        frame:Show()
    else
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Health Bars")
H.Apply = Apply

-- A fight: the bar appears only when the boss has a health-triggered
-- ability; the unit is looked up on the pull and re-looked every second
-- while missing (the tank may not have it targeted yet).
local function OnEncounter(on)
    if not on then
        state.boss, state.unit, state.abilities = nil, nil, {}
        state.refused = false
        if frame then frame:SetAlpha(1); frame:Hide() end
        return
    end
    state.boss = ns.Timers.Boss()
    state.abilities = state.boss and AbilitiesFor(state.boss) or {}
    state.unit = nil
    state.lastScan = 0
    if not Enabled() or #state.abilities == 0 then
        if frame then frame:Hide() end
        return
    end
    Build()
    state.unit = FindUnit(state.boss)
    Refresh()
    if state.unit then Feed() end
    frame:Show()
end

ns.Timers.Register({ OnEncounter = OnEncounter })

-- Ten times a second while a boss is up: the fill follows the unit.
local ticker
local function EnsureTicker()
    if ticker then return end
    ticker = C_Timer.NewTicker(0.1, function()
        if state.preview or not frame or not frame:IsShown() or not state.boss then return end
        if not state.unit then
            local now = GetTime()
            if now - state.lastScan >= 1 then
                state.lastScan = now
                state.unit = FindUnit(state.boss)
            end
        end
        if state.unit then Feed() end
    end)
end
ns.On("PLAYER_ENTERING_WORLD", EnsureTicker)
EnsureTicker()

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
    ns.Print(string.format("health bars: boss=%s unit=%s markers=%d feeds=%d refused=%s (%d)",
        ns.S(state.boss and state.boss.name or "-"), tostring(state.unit), #state.abilities,
        state.feeds, tostring(state.refused), state.refusals))
end
