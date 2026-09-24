--[[ Salus Novus -- Queue: the strip of upcoming casts.

MerkUI's Ability Queue (MerkUI/BossQueue.lua) as a hub listener: the
soonest cast large, the ones after it smaller and fainter, the ability's
name under the lead (the draining bottom edge is gone -- Alex, 2026-09-20;
a cooldown swipe remains as `timeOnIcon = "swipe"`, off by default). Every record comes from the hub; nothing
is predicted beyond it. Left behind from retail: everything keyed on
BigWigs (emphasize, countdown glyph, roles, colours), nameplate timers
and their "xN" badge, specials, instructions, the caster line, the pulse.
]]

local _, ns = ...

local SOLID = ns.Theme.SOLID
local QUESTION_ICON = 134400
local MAX_ICONS = 8
local MIN_ICON = 16

local Q = {}
ns.Queue = Q

local function O() return ns.db and ns.db.queue end
-- The page's Enable box AND the Boss Warnings master switch.
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local icons = {}
Q._icons = icons             -- test seam
local state = { preview = nil, previewBars = nil }
Q.state = state

-- CORNERS, not edges: the strip's height changes with its content (the
-- label row), so an origin that pins the vertical centre made the icons
-- hop when a label appeared (landmine 17).
local function Origin()
    local d = O() and O().direction or "right"
    if d == "right" then return "TOPLEFT" elseif d == "left" then return "TOPRIGHT"
    elseif d == "down" then return "TOPLEFT" elseif d == "up" then return "BOTTOMLEFT" end
    return "CENTER"
end
local function SavePosition()
    ns.SaveAnchor(frame, "queuePos")
end
local function RestorePosition()
    if not frame then return end
    -- Below the reminders anchor's default (TOP -160), above the character.
    ns.RestoreAnchor(frame, "queuePos", "TOPLEFT", 156, -70, "CENTER")   -- Alex's layout
end
ns.QueueRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "queuePos", restore = "QueueRestorePosition" })

local function MakeIcon()
    local f = CreateFrame("Frame", nil, frame)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.border = ns.CreateBorder(f)
    f.border:Layout(f, 1, 0)
    f.border:SetColor(0, 0, 0, 0.9)
    f.border:Show()

    -- Time-on-icon, swipe flavour: a cooldown sweep over the face.
    f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    f.cd:SetAllPoints()
    if f.cd.SetDrawEdge then f.cd:SetDrawEdge(false) end
    if f.cd.SetDrawBling then f.cd:SetDrawBling(false) end
    if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(true) end
    if f.cd.SetSwipeColor then f.cd:SetSwipeColor(0, 0, 0, 0.6) end
    f.cd:Hide()

    -- Seconds until the cast.
    f.timer = f:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(f.timer, 11, "OUTLINE")
    f.timer:SetPoint("CENTER", 0, 0)
    f.timer:SetTextColor(1, 1, 1, 1)
    f.timer:Hide()

    -- The ability's name below.
    f.label = f:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(f.label, 11, "OUTLINE")
    f.label:SetPoint("TOP", f, "BOTTOM", 0, -3)
    f.label:SetTextColor(1, 1, 1, 1)
    f.label:Hide()

    f:Hide()
    return f
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusQueue", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(48, 48)
    frame:Hide()

    frame.backdrop = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.backdrop:SetTexture(SOLID)
    frame.backdrop:SetPoint("TOPLEFT", -6, 6)
    frame.backdrop:SetPoint("BOTTOMRIGHT", 6, -6)
    frame.backdrop:Hide()

    for i = 1, MAX_ICONS do icons[i] = MakeIcon() end

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Ability Queue  \194\183  drag to move")
    frame.unlockLabel:Hide()

    ns.RegisterMovable(frame, "queuePos", Origin, RestorePosition)
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

-- The next `count` records, soonest first (the hub's order), or
-- placeholders while unlocked with nothing live.
local function VisibleEntries(placeholder)
    local opts = O()
    local count = math.min((opts and opts.count) or 5, MAX_ICONS)
    local out = {}
    if placeholder then
        for i = 1, count do out[i] = { key = 0, name = "Ability " .. i, placeholder = true } end
        return out
    end
    for _, b in ipairs(state.previewBars or ns.Timers.Sorted()) do
        if #out >= count then break end
        -- An ability unticked for the queue, or hidden from my role, skips.
        if ns.Timers.RoutedTo(b, "queue") then
            out[#out + 1] = { bar = b, key = b.key }
        end
    end
    return out
end

local function ApplyTimeOnIcon(f, e, opts, now)
    local b = e.bar
    if e.placeholder or (opts.timeOnIcon or "none") ~= "swipe" then
        f.cd:Hide()
        return
    end
    local dur = b.duration or 0
    local left = state.preview and (dur * 0.6) or (b.at - now)
    if state.preview then
        pcall(f.cd.SetCooldown, f.cd, now - (dur - left), dur)
        if f.cd.Pause then pcall(f.cd.Pause, f.cd) end
    else
        pcall(f.cd.SetCooldown, f.cd, b.at - dur, dur)
        if f.cd.Resume then pcall(f.cd.Resume, f.cd) end
    end
    f.cd:Show()
end

local function Refresh(placeholder)
    if not frame then return end
    local opts = O() or {}
    local entries = VisibleEntries(placeholder)
    local now = GetTime()
    local _, ag, ab = ns.GetThemeColor()

    -- Sizes: lead = size, each next one shrink% of the previous, floored.
    local size = opts.size or 48
    local shrink = math.max(40, math.min(100, opts.shrink or 80)) / 100
    local gap = opts.gap or 6
    local dir = opts.direction or "right"
    local fade = math.max(0, math.min(90, opts.fade or 50)) / 100
    local sizes = {}
    local s = size
    for i = 1, #entries do
        sizes[i] = math.max(MIN_ICON, math.floor(s + 0.5))
        s = s * shrink
    end

    -- Room below for labels. A horizontal strip reserves one row under
    -- the icons; a vertical one reserves it under EACH labelled icon, or
    -- the lead's label landed on icon 2 (direction "down").
    local labelsOn = opts.labels and opts.labels ~= "none"
    local labelRoom = labelsOn and ((opts.labelSize or 11) + 6) or 0
    local function Labelled(i) return (opts.labels == "all") or (opts.labels == "lead" and i == 1) end

    local total = 0
    for i = 1, #entries do total = total + sizes[i] + (i > 1 and gap or 0) end
    local lead = sizes[1] or size
    local horizontal = (dir == "right" or dir == "left")
    if horizontal then
        frame:SetSize(math.max(total, lead), lead + labelRoom)
    else
        local rooms = 0
        for i = 1, #entries do if Labelled(i) then rooms = rooms + labelRoom end end
        frame:SetSize(lead, math.max(total, lead) + rooms)
    end
    ns.SyncAnchorOrigin(frame, "queuePos")

    local pos = 0
    for i = 1, MAX_ICONS do
        local f = icons[i]
        local e = entries[i]
        if not e then
            f:Hide()
            f.entry = nil
            f.lastSecs = nil
        else
            local b = e.bar
            local sz = sizes[i]
            if f.entry and f.entry.key ~= e.key then
                f.lastSecs = nil       -- reused for a different ability
            end
            f:SetSize(sz, sz)
            f:ClearAllPoints()
            local room = (not horizontal and Labelled(i)) and labelRoom or 0
            if dir == "right" then
                f:SetPoint("TOPLEFT", frame, "TOPLEFT", pos, 0)
            elseif dir == "left" then
                f:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -pos, 0)
            elseif dir == "down" then
                f:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -pos)
            else -- up: the label's room sits under the icon
                f:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, pos + room)
            end
            pos = pos + sz + gap + room

            -- Alpha falloff + desaturation after the lead.
            local a = 1 - fade * ((i - 1) / math.max(1, #entries - 1))
            f:SetAlpha(math.max(0.15, a))
            f.tex:SetTexture(e.placeholder and QUESTION_ICON or ns.Timers.IconOf(b))
            f.tex:SetDesaturated(opts.desaturate ~= false and i > 1)
            f.entry = e

            if opts.showTimers and b and b.at then
                local left = state.preview and (b.duration or 0) or (b.at - now)
                local tp = opts.timerPos or "center"
                f.timer:ClearAllPoints()
                if tp == "topleft" then f.timer:SetPoint("TOPLEFT", 2, -2)
                elseif tp == "topright" then f.timer:SetPoint("TOPRIGHT", -2, -2)
                elseif tp == "bottomleft" then f.timer:SetPoint("BOTTOMLEFT", 2, 4)
                elseif tp == "bottomright" then f.timer:SetPoint("BOTTOMRIGHT", -2, 4)
                else f.timer:SetPoint("CENTER", 0, 0) end
                ns.SetFontSafe(f.timer, opts.timerSize or 12, "OUTLINE")
                local secs = math.max(0, math.ceil(left))
                f.lastSecs = secs
                f.timer:SetText(string.format("%d", secs))
                f.timer:Show()
            else
                f.timer:Hide()
            end
            ApplyTimeOnIcon(f, e, opts, now)

            -- Borders stay plain black. Layout is 12 widget calls per
            -- icon, so only when the thickness actually changes.
            local thick = (i == 1) and (opts.border or 2) or 1
            if f.borderThick ~= thick then
                f.borderThick = thick
                f.border:Layout(f, thick, 0)
                f.border:SetColor(0, 0, 0, 0.9)
            end
            -- The ability's own colour (Abilities.lua) takes the name;
            -- otherwise white.
            local cr, cg, cb
            if not e.placeholder then cr, cg, cb = ns.Timers.AbilityColor(b) end

            local showLabel = Labelled(i)
            if showLabel then
                ns.SetFontSafe(f.label, (opts.labelSize or 11) + (i == 1 and 1 or 0), "OUTLINE")
                f.label:SetText(e.placeholder and ("Ability " .. i) or ns.Timers.AbilityName(b))
                f.label:SetTextColor(cr or 1, cg or 1, cb or 1, 1)
                f.label:Show()
            else
                f.label:Hide()
            end
            f:Show()
        end
    end

    if opts.backdrop then
        frame.backdrop:SetVertexColor(0, 0, 0, (opts.backdropAlpha or 40) / 100)
        frame.backdrop:Show()
    else
        frame.backdrop:Hide()
    end

    local unlocked = ns.db and ns.db.unlocked
    if #entries > 0 or state.preview or unlocked then frame:Show() else frame:Hide() end
end
Q.Refresh = Refresh

--- The hub's 0.2s tick: seconds rewritten only when the integer changes.
local function Tick(now)
    if not frame or not frame:IsShown() or state.preview then return end
    local opts = O() or {}
    for i = 1, MAX_ICONS do
        local f = icons[i]
        local e = f.entry
        if f:IsShown() and e and e.bar then
            local b = e.bar
            if opts.showTimers then
                local secs = math.max(0, math.ceil(b.at - now))
                if secs ~= f.lastSecs then
                    f.lastSecs = secs
                    f.timer:SetText(string.format("%d", secs))
                end
            end
        end
    end
end
Q.Tick = Tick

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
    if ns.Timers.Any() then
        Refresh()
    elseif unlocked then
        Refresh(true)     -- placeholders, so there is a strip to drag
    else
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Queue")
Q.Apply = Apply

ns.Timers.Register({
    OnChange = function()
        if state.preview then return end
        if not Enabled() then return end
        Build()
        Refresh()
    end,
    OnTick = Tick,
})

function ns.QueuePreviewStart(stage)
    Build()
    state.preview = stage
    state.previewBars = ns.Timers.FakeBars(6, 7, true)
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, 6)
    Apply()
end

function ns.QueuePreviewStop()
    if not state.preview then return end
    state.preview = nil
    state.previewBars = nil
    if frame then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("MEDIUM")
        RestorePosition()
    end
    Apply()
end
