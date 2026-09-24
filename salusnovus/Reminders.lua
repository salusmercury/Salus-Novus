--[[ Salus Novus -- Reminders: four triggers, one anchor.

MerkUI's Reminders anchor (MerkUI/Reminders.lua) carrying Salus Novus's
triggers: the ones measured to reach an addon on Forever (notes section
10): pull, time since pull, "boss is casting" (the spell id is secret, so
unnamed), and readable boss emotes. Nothing here reads the combat log
(closed) or Blizzard's timeline (off). Pull and end come from the hub.

A "time" reminder is armed at its moment minus its lead and counts down
on the anchor, then holds; pull, cast and emote reminders show at once and
hold. Every line is pooled, stacked from the anchor's edge, and taken
back on ENCOUNTER_END or death -- a countdown never outlives its pull.
Left behind from retail: phases, stages, difficulty scoping, TTS, shared
strings.
]]

local _, ns = ...

local R = {}
ns.Reminders = R

local function O() return ns.db and ns.db.reminders end
-- The page's Enable box AND the Boss Warnings master switch.
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local lines, active = {}, {}        -- pooled line frames / on-screen lines
local restack = false
local scheduled = {}                -- id -> C_Timer handle
local fired = {}                    -- ids shown this pull
local state = { encounter = nil, pullAt = nil, preview = nil, sampling = nil, lastCastFire = 0 }
R.state = state
R._fired = {}                       -- texts displayed, in order (test seam)

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------
function ns.ReminderList(encounterID, create)
    local opts = O()
    if not opts or not encounterID then return nil end
    opts.list = opts.list or {}
    if not opts.list[encounterID] and create then opts.list[encounterID] = {} end
    return opts.list[encounterID]
end

local nextId = 0
function ns.ReminderAdd(encounterID, r)
    local list = ns.ReminderList(encounterID, true)
    nextId = nextId + 1
    local stamp = (GetServerTime and GetServerTime()) or math.floor(GetTime())
    r.id = r.id or (tostring(stamp) .. ":" .. nextId)
    r.encounterID = encounterID
    r.enabled = r.enabled ~= false
    table.insert(list, r)
    return r
end

function ns.ReminderRemove(encounterID, id)
    local t = scheduled[id]
    if t then pcall(t.Cancel, t); scheduled[id] = nil end
    local list = ns.ReminderList(encounterID)
    if list then
        for i = #list, 1, -1 do if list[i].id == id then table.remove(list, i) end end
    end
    -- A shipped default cannot be deleted from the data file: hide it.
    local opts = O()
    if opts then
        opts.hidden = opts.hidden or {}
        for _, d in ipairs(ns.DefaultReminders or {}) do
            if d.id == id then opts.hidden[id] = true end
        end
    end
end

--- All reminders for an encounter: shipped defaults not hidden, then the
-- user's. Returns a fresh list; the records are the stored ones.
function R.For(encounterID)
    local out = {}
    local opts = O()
    local hidden = opts and opts.hidden or {}
    for _, r in ipairs(ns.DefaultReminders or {}) do
        if r.encounterID == encounterID and not hidden[r.id] then out[#out + 1] = r end
    end
    local list = ns.ReminderList(encounterID)
    if list then for _, r in ipairs(list) do out[#out + 1] = r end end
    return out
end

--------------------------------------------------------------------------------
-- Anchor
--------------------------------------------------------------------------------
local function SavePosition() ns.SaveAnchor(frame, "remindersPos") end
local function RestorePosition()
    -- Alex's layout (2026-09-23, read from his saved positions): centred,
    -- a little above the character. The other anchors' saved spots matched
    -- their defaults exactly; this one sat 7px higher.
    if frame then ns.RestoreAnchor(frame, "remindersPos", "BOTTOM", 0, 42, "CENTER") end
end
ns.RemindersRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "remindersPos", restore = "RemindersRestorePosition" })

local function Origin()
    local d = O() and O().direction or "up"
    return d == "up" and "BOTTOM" or "TOP"
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusReminderFrame", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetSize(420, 34)
    frame:Hide()
    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.unlockBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Reminders  \194\183  drag to move")
    frame.unlockLabel:Hide()
    frame.unlockText = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockText, 20, "OUTLINE")
    frame.unlockText:SetPoint("CENTER")
    frame.unlockText:SetText("Sample reminder  5")
    frame.unlockText:Hide()
    ns.RegisterMovable(frame, "remindersPos", Origin)
    frame:SetScript("OnDragStart", function(self) if ns.db and ns.db.unlocked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)
    frame:SetScript("OnUpdate", function()
        local now = GetTime()
        for i = #active, 1, -1 do
            local f = active[i]
            if f.until_ and now >= f.until_ then
                f:Hide(); table.remove(active, i); table.insert(lines, f)
                restack = true
            elseif f.fireAt and now < f.fireAt then
                -- The number changes once a second; this loop runs at framerate.
                local secs = math.ceil(f.fireAt - now)
                if secs ~= f.lastSecs then
                    f.lastSecs = secs
                    f.text:SetText(("%s  |cffffffff%d|r"):format(f.label, secs))
                end
            elseif f.fireAt then
                f.text:SetText(f.label)
                f.fireAt = nil
                R.Sound(f.sound)
            end
        end
        -- Restack only when the set actually changed.
        if restack then
            restack = false
            local opts = O() or {}
            local up = (opts.direction or "up") == "up"
            local y = 0
            for _, f in ipairs(active) do
                f:ClearAllPoints()
                if up then f:SetPoint("BOTTOM", frame, "BOTTOM", 0, y) else f:SetPoint("TOP", frame, "TOP", 0, -y) end
                y = y + f:GetHeight() + (opts.spacing or 4)
            end
        end
        if #active == 0 and not (ns.db and ns.db.unlocked) and not state.preview then frame:Hide() end
    end)
    RestorePosition()
    return frame
end
R.Frame = function() return frame end
R._active = active                  -- test seam

function R.Sound(on)
    local opts = O() or {}
    if on and opts.sound ~= false and PlaySound then
        local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
        pcall(PlaySound, kit, "Master")
    end
end

local function Acquire()
    local f = table.remove(lines)
    if f then return f end
    f = CreateFrame("Frame", nil, frame)
    f:SetSize(420, 34)
    f.iconFrame = CreateFrame("Frame", nil, f)
    f.iconFrame:SetSize(28, 28)
    f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconBorder = ns.CreateBorder(f.iconFrame)
    f.iconBorder:Layout(f.iconFrame, 1, 0)
    f.iconBorder:SetColor(0, 0, 0, 0.9)
    f.iconBorder:Show()
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    return f
end

--- Put a reminder on screen: counts down `lead` seconds, then holds.
-- `text` is always OUR string, never client data.
local function Display(r, lead)
    local opts = O() or {}
    -- With the options page open, `frame` is parented to the preview stage
    -- and clipped to it, so a live reminder would be drawn inside the
    -- settings window. The preview's own sample sets state.sampling.
    if state.preview and not state.sampling then return end
    Build()
    if not state.preview and frame:GetParent() ~= UIParent then
        frame:SetParent(UIParent); frame:SetFrameStrata("HIGH"); RestorePosition()
    end
    -- Per-reminder overrides, clamped: a typo in a hand-edited record would
    -- otherwise mint a 500px reminder that never goes away.
    local size = math.max(8, math.min(72, tonumber(r.size) or opts.size or 22))
    local f = Acquire()
    f:SetHeight(size + 12)
    ns.SetFontSafe(f.text, size, "OUTLINE")
    local c = (type(r.color) == "table" and r.color) or opts.color or { r = 1, g = 0.82, b = 0 }
    local function ch(v, d) return (type(v) == "number" and v >= 0 and v <= 1) and v or d end
    f.text:SetTextColor(ch(c.r, 1), ch(c.g, 0.82), ch(c.b, 0), 1)
    f.rid = r.id          -- so ReminderCancel can retract THIS line
    f.label = (type(r.text) == "string" and r.text ~= "" and r.text) or "Reminder"
    f.sound = r.sound and true or false
    local now = GetTime()
    f.fireAt = (lead and lead > 0) and (now + lead) or nil
    local hold = math.max(0.5, math.min(60, tonumber(r.hold) or opts.hold or 4))
    f.until_ = now + (lead or 0) + hold
    f.text:SetText(f.fireAt and ("%s  |cffffffff%d|r"):format(f.label, math.ceil(lead)) or f.label)
    if f.fireAt == nil then R.Sound(f.sound) end
    -- r.icon: a spell id whose icon to show, or 0 for none.
    local iconId = tonumber(r.icon)
    local tex = nil
    if iconId and iconId ~= 0 and C_Spell and C_Spell.GetSpellTexture then
        local ok, t = pcall(C_Spell.GetSpellTexture, iconId)
        if ok and t and not ns.IsSecret(t) then tex = t end
    end
    if opts.showIcon ~= false and tex then
        f.icon:SetTexture(tex)
        f.iconFrame:SetSize(size + 6, size + 6)
        f.iconFrame:ClearAllPoints()
        f.iconFrame:SetPoint("RIGHT", f.text, "LEFT", -8, 0)
        f.iconFrame:Show()
    else
        f.icon:SetTexture(nil)
        f.iconFrame:Hide()
    end
    f.lastSecs = nil          -- pooled frames keep the old value
    f:Show()
    table.insert(active, 1, f)
    restack = true
    frame:Show()
    R._fired[#R._fired + 1] = f.label
end
R.Display = Display

--------------------------------------------------------------------------------
-- Cancel / retract / clear
--------------------------------------------------------------------------------
local function Cancel(id)
    local t = scheduled[id]
    if t then pcall(t.Cancel, t); scheduled[id] = nil end
end
local function CancelAll()
    for id in pairs(scheduled) do Cancel(id) end
end

-- Retract the line a single reminder is currently showing (an edit or a
-- delete mid-countdown must not leave the old line running).
local function RetractShown(id)
    if id == nil then return end
    for i = #active, 1, -1 do
        local f = active[i]
        if f.rid == id then
            f.fireAt, f.until_, f.rid = nil, nil, nil
            f:Hide()
            table.remove(active, i)
            table.insert(lines, f)
            restack = true
        end
    end
end

-- Take back anything already on screen: a reminder mid-countdown when the
-- pull ended must not keep counting.
local function ClearShown()
    for i = #active, 1, -1 do
        local f = active[i]
        f.rid = nil
        f.fireAt, f.until_ = nil, nil
        f:Hide()
        table.remove(active, i)
        table.insert(lines, f)
        restack = true
    end
    if frame and not state.preview and not (ns.db and ns.db.unlocked) then frame:Hide() end
end

--------------------------------------------------------------------------------
-- Arming
--------------------------------------------------------------------------------
local function Arm(r, showAt, lead)
    if type(r) ~= "table" or r.id == nil then return end
    local id = r.id
    local lead0 = lead
    Cancel(id)
    if fired[id] then return end
    local now = GetTime()
    -- Past its moment already (lead longer than the offset): show it at
    -- once with what is left.
    local delay = showAt - now
    if delay < 0 then
        lead = math.max(0, lead + delay)
        delay = 0
    end
    if lead <= 0 and showAt + lead0 < now - 1 then return end   -- long gone
    scheduled[id] = C_Timer.NewTimer(delay, function()
        scheduled[id] = nil
        -- Dead men need no cues; not marked fired, so a res gets it back.
        if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then return end
        Display(r, lead)
        fired[id] = true
    end)
end

local function Lead(r, opts)
    return math.max(0, math.min(300, tonumber(r.lead) or opts.lead or 5))
end

--- Arm every pull/time reminder for the fight, measured from `origin`.
local function ScheduleFor(origin)
    local opts = O()
    if not (Enabled() and state.encounter) then return end
    for _, r in ipairs(R.For(state.encounter)) do
        if r.enabled ~= false then
            if r.trigger == "pull" then
                Arm(r, origin, 0)
            elseif r.trigger == "time" and tonumber(r.arg) then
                local lead = Lead(r, opts)
                Arm(r, origin + tonumber(r.arg) - lead, lead)
            end
        end
    end
end

function ns.ReminderCancel(id)
    Cancel(id)
    fired[id] = nil
    RetractShown(id)
end

--- Re-arm ONE reminder in the middle of a live pull (after an edit).
-- No-ops harmlessly when no pull is running.
function ns.ReminderRearm(r)
    local opts = O()
    if not (Enabled() and state.encounter and state.pullAt) then return end
    if type(r) ~= "table" or r.id == nil or r.enabled == false then return end
    if r.trigger == "pull" then
        Arm(r, state.pullAt, 0)
    elseif r.trigger == "time" and tonumber(r.arg) then
        local lead = Lead(r, opts)
        Arm(r, state.pullAt + tonumber(r.arg) - lead, lead)
    end
end

--------------------------------------------------------------------------------
-- Triggers
--------------------------------------------------------------------------------
function R.OnPull(encounterID)
    state.encounter = encounterID
    state.pullAt = GetTime()
    state.lastCastFire = 0
    wipe(fired)
    CancelAll()
    ClearShown()
    ScheduleFor(state.pullAt)
end

function R.OnEnd()
    state.encounter = nil
    state.pullAt = nil
    CancelAll()
    ClearShown()
    wipe(fired)
end

--- A unit we care about started casting. Spell is secret on Forever, so
-- every "cast" reminder for the fight fires, throttled.
function R.OnCast(unit)
    if not state.encounter then return end
    local opts = O()
    if not Enabled() then return end
    if ns.IsSecret(unit) or type(unit) ~= "string" then return end
    if not (unit == "target" or unit:match("^boss%d$") or unit:match("^nameplate%d+$")) then return end
    -- A friendly target or nameplate (the party mage) is not the boss.
    -- Fail open: a secret or missing answer still counts as the boss, so a
    -- client change can't silence every cast reminder.
    if type(UnitCanAttack) == "function" then
        local okA, hostile = pcall(UnitCanAttack, "player", unit)
        if okA and not ns.IsSecret(hostile) and hostile == false then return end
    end
    local now = GetTime()
    if now - state.lastCastFire < (opts.castThrottle or 3) then return end
    local any = false
    for _, r in ipairs(R.For(state.encounter)) do
        if r.trigger == "cast" and r.enabled ~= false then Display(r, 0) any = true end
    end
    if any then state.lastCastFire = now end
end

--- A boss emote or yell. Secret text is dropped without being touched.
function R.OnEmote(text)
    if not state.encounter then return end
    if not Enabled() then return end
    if ns.IsSecret(text) or type(text) ~= "string" then return end
    local lower = text:lower()
    for _, r in ipairs(R.For(state.encounter)) do
        if r.trigger == "emote" and r.enabled ~= false and type(r.arg) == "string"
            and lower:find(r.arg:lower(), 1, true) then
            Display(r, 0)
        end
    end
end

--------------------------------------------------------------------------------
-- Wiring
--------------------------------------------------------------------------------
-- Pull and end come from the hub, so a simulated fight (/sn test)
-- reaches reminders by the same path as a real one.
ns.Timers.Register({
    OnEncounter = function(on)
        if on then R.OnPull(ns.Timers.BossEncounterID()) else R.OnEnd() end
    end,
})
ns.On("UNIT_SPELLCAST_START", function(unit) R.OnCast(unit) end)
ns.On("UNIT_SPELLCAST_CHANNEL_START", function(unit) R.OnCast(unit) end)
ns.On("CHAT_MSG_RAID_BOSS_EMOTE", function(text) R.OnEmote(text) end)
ns.On("CHAT_MSG_MONSTER_YELL", function(text) R.OnEmote(text) end)
-- A wipe ends the encounter only when the last player dies; the schedule
-- must not keep firing at a corpse.
ns.On("PLAYER_DEAD", function() CancelAll() ClearShown() end)
-- A combat res mid-fight gets the rest of the schedule back: everything
-- not yet fired is re-armed from the pull, and Arm drops what is past.
local function Resurrected()
    if state.encounter and state.pullAt then ScheduleFor(state.pullAt) end
end
ns.On("PLAYER_ALIVE", Resurrected)
ns.On("PLAYER_UNGHOST", Resurrected)

--------------------------------------------------------------------------------
-- Apply / preview / test
--------------------------------------------------------------------------------
local function Apply()
    local opts = O()
    Build()
    restack = true
    if ns.SetMovableScale(frame, state.preview and 1 or ns.AnchorScale()) and not state.preview then RestorePosition() end
    local unlocked = ns.db and ns.db.unlocked
    if not Enabled() then
        CancelAll()
        ClearShown()
        frame.unlockBg:Hide(); frame.unlockLabel:Hide(); frame.unlockText:Hide()
        if #active == 0 then frame:Hide() end
        return
    end
    frame.unlockBg:SetShown(unlocked and not state.preview)
    frame.unlockLabel:SetShown(unlocked and not state.preview)
    frame.unlockText:SetShown(unlocked and not state.preview)
    if unlocked then
        frame:Show()
    elseif #active == 0 and not state.preview then
        frame:Hide()          -- locking an idle anchor hides it at once
    end
    ns.SyncAnchorOrigin(frame, "remindersPos")
end
ns.RegisterApply(Apply, "Reminders")
R.Apply = Apply

-- Sample for the page preview and the strip's Test button. Deliberately
-- not a real reminder's wording: it must never be mistaken for one.
function ns.TestReminder()
    state.sampling = true
    Display({ text = "Sample reminder", icon = 11130 }, 5)
    state.sampling = nil
end

local previewLoop
function ns.RemindersPreviewStart(stage)
    Build()
    ClearShown()
    state.preview = stage
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, 0)
    Apply()
    if previewLoop then previewLoop:Cancel() end
    ns.TestReminder()
    previewLoop = C_Timer.NewTicker(9, function()
        if not state.preview then return end
        ns.TestReminder()
    end)
end

function ns.RemindersPreviewStop()
    if not state.preview then return end
    state.preview = nil
    if previewLoop then previewLoop:Cancel(); previewLoop = nil end
    ClearShown()
    if frame then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("HIGH")
        RestorePosition()
    end
    Apply()
end

--------------------------------------------------------------------------------
-- Slash
--------------------------------------------------------------------------------
-- /sn remind <boss> pull <text>
-- /sn remind <boss> time <seconds> <text>
-- /sn remind <boss> cast <text>
-- /sn remind <boss> emote <word> <text>
ns.Commands.remind = function(rest)
    local bossText, trigger, tail = rest:match("^(%S+)%s+(%a+)%s*(.*)$")
    local boss = bossText and ns.BossByName(bossText)
    if not boss then
        ns.Print("usage: /sn remind <boss> <pull|time N|cast|emote WORD> <text>")
        return
    end
    trigger = (trigger or ""):lower()
    local r = { trigger = trigger, sound = true }
    if trigger == "time" then
        local n, text = tail:match("^(%d+%.?%d*)%s+(.+)$")
        if not n then ns.Print("time needs seconds then text") return end
        r.arg, r.text = tonumber(n), text
    elseif trigger == "emote" then
        local word, text = tail:match("^(%S+)%s+(.+)$")
        if not word then ns.Print("emote needs a word then text") return end
        r.arg, r.text = word, text
    elseif trigger == "pull" or trigger == "cast" then
        if tail == "" then ns.Print("needs text") return end
        r.text = tail
    else
        ns.Print("trigger must be pull, time, cast or emote")
        return
    end
    ns.ReminderAdd(boss.encounterID, r)
    ns.ReminderRearm(r)
    ns.Print(("reminder added for %s (%s%s) -- note: saved data does not survive a client restart on this account yet")
        :format(boss.name, trigger, r.arg and (" " .. tostring(r.arg)) or ""))
end

ns.Commands.reminders = function()
    local n = 0
    for _, inst in pairs(ns.Data or {}) do
        for _, b in ipairs(inst.bosses) do
            for _, r in ipairs(R.For(b.encounterID)) do
                n = n + 1
                ns.Print(("%s: %s%s -> %s"):format(b.name, r.trigger, r.arg and (" " .. tostring(r.arg)) or "", ns.S(r.text)))
            end
        end
    end
    if n == 0 then ns.Print("no reminders") end
end

-- /sn test <boss>: simulate a pull so reminders and the bars can be
-- seen without a dungeon. The hub's real StartEncounter, ended after the
-- boss's average fight length.
ns.Commands.test = function(rest)
    local boss = ns.BossByName(rest)
    if not boss then ns.Print("usage: /sn test <boss>") return end
    ns.Print("simulating pull of " .. boss.name .. " for " .. tostring(boss.avgLength or 30) .. "s")
    ns.Timers.Simulate(boss.encounterID)
end
