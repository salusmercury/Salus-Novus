--[[ Salus Novus -- Bars: the time-since-pull bars anchor.

MerkUI's Bars anchor (MerkUI/Bars.lua) as a hub listener: a stack of bars
at an edge, each draining from the pull toward the moment an ability was
observed, name on the left, seconds on the right, icon beside it, smooth
fill every frame with the seconds rewritten once a second, red under a
threshold, movable when unlocked. Every record comes from the hub
(Timers.lua); the label above the stack says which boss and how many pulls
the timings rest on. A bar that reaches zero reads "now" for the hub's
hold, then drops -- it is never slid forward. Left behind from retail:
LibSharedMedia textures, ability routing, instructions, specials.
]]

local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8x8"
local MAX_BARS = 8

local B = {}
ns.Bars = B

local function O() return ns.db and ns.db.bars end
-- The page's Enable box AND the Boss Warnings master switch.
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local bars = {}
B._bars = bars              -- exposed for the test harness only
local state = { preview = nil, previewBars = nil }
B.state = state

-- Corners: the stack's width changes when the icon side is toggled, which
-- slid the whole stack sideways under a centre-pinned origin.
local function Origin()
    local d = O() and O().direction or "down"
    if d == "up" then return "BOTTOMLEFT" end
    return "TOPLEFT"
end
local function SavePosition()
    ns.SaveAnchor(frame, "barsPos")
end

local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "barsPos", "BOTTOMLEFT", 314, 17, "CENTER")   -- Alex's layout
end
ns.BarsRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "barsPos", restore = "BarsRestorePosition" })

local function MakeBar()
    local f = CreateFrame("Frame", nil, frame)
    f:SetSize(220, 18)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetTexture(SOLID)
    f.bg:SetAllPoints()
    f.bg:SetVertexColor(0, 0, 0, 0.6)
    f.bar = CreateFrame("StatusBar", nil, f)
    f.bar:SetAllPoints()
    f.bar:SetStatusBarTexture(SOLID)
    f.bar:SetMinMaxValues(0, 1)
    f.bar:SetValue(1)
    f.border = ns.CreateBorder(f)
    f.border:Layout(f, 1, 0)
    f.border:SetColor(0, 0, 0, 0.9)
    f.border:Show()
    -- Icon in its own frame so it carries a border.
    f.iconFrame = CreateFrame("Frame", nil, f)
    f.iconFrame:SetSize(18, 18)
    f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconBorder = ns.CreateBorder(f.iconFrame)
    f.iconBorder:Layout(f.iconFrame, 1, 0)
    f.iconBorder:SetColor(0, 0, 0, 0.9)
    f.iconBorder:Show()
    f.iconFrame:Hide()
    f.text = f.bar:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(f.text, 11, "OUTLINE")
    f.text:SetPoint("LEFT", 6, 0)
    f.text:SetJustifyH("LEFT")
    f.time = f.bar:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(f.time, 11, "OUTLINE")
    f.time:SetPoint("RIGHT", -6, 0)
    -- Bound the name on the RIGHT too, against the seconds: a fontstring
    -- with one point and no width does not clip to its frame, so a long
    -- ability name drew straight through the countdown.
    f.text:SetPoint("RIGHT", f.time, "LEFT", -6, 0)
    f.text:SetWordWrap(false)
    f:Hide()
    return f
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusBars", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(220, 18)
    frame:Hide()
    for i = 1, MAX_BARS do bars[i] = MakeBar() end

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    -- One label above the stack: the boss and its pull count in a fight,
    -- the anchor's name while unlocked.
    frame.label = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.label, 10, "OUTLINE")
    frame.label:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.label:SetTextColor(0.60, 0.58, 0.66, 1)
    frame.label:Hide()

    ns.RegisterMovable(frame, "barsPos", Origin)
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

local function Entries(placeholder)
    local opts = O() or {}
    local count = math.min(opts.max or 4, MAX_BARS)
    local out = {}
    if placeholder then
        for i = 1, count do out[i] = { placeholder = true, key = 0, left = 12 * i, dur = 30 * i } end
        return out
    end
    local now = GetTime()
    local list = {}
    for _, b in ipairs(state.previewBars or ns.Timers.Sorted()) do
        local left = state.preview and (b.duration or 0) * 0.6 or (b.at - now)
        list[#list + 1] = { bar = b, key = b.key, left = left, dur = b.duration or 0 }
    end
    for i = 1, math.min(count, #list) do out[i] = list[i] end
    return out
end

local function Label()
    if not frame then return end
    local boss = not state.preview and ns.Timers.Boss()
    if boss then
        -- No label in a fight at all (Alex): the bars speak for themselves.
        frame.label:Hide()
    elseif ns.db and ns.db.unlocked and not state.preview then
        frame.label:SetText("Bars  \194\183  drag to move")
        frame.label:Show()
    else
        frame.label:Hide()
    end
end

local function Refresh(placeholder)
    if not frame then return end
    local opts = O() or {}
    local entries = Entries(placeholder)
    local w, h = opts.width or 220, opts.height or 18
    local spacing = opts.spacing or 4
    local up = (opts.direction or "down") == "up"
    local iconSide = opts.icon or "left"
    local n = #entries
    local pos = 0
    local c = opts.color or { r = 0.3, g = 0.6, b = 1 }
    for i = 1, MAX_BARS do
        local f = bars[i]
        local e = entries[i]
        if not e then
            f:Hide()
            f.entry = nil
        else
            local b = e.bar
            f:SetSize(w, h)
            f:ClearAllPoints()
            local x = (iconSide == "left") and (h + 2) or 0
            if up then f:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, pos)
            else f:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -pos) end
            pos = pos + h + spacing

            f.bar:SetReverseFill((opts.fill or "drain") == "fill")
            local frac = (e.dur > 0) and math.max(0, math.min(1, e.left / e.dur)) or 0
            f.bar:SetValue((opts.fill or "drain") == "fill" and (1 - frac) or frac)

            local r, g, bb = c.r or 0.3, c.g or 0.6, c.b or 1
            local low = opts.byRemaining and e.left <= (opts.byRemainingAt or 3)
            if low then r, g, bb = 1, 0.3, 0.3 end
            f.bar:SetStatusBarColor(r, g, bb, 0.9)
            -- Re-bound to a different timer: the Tick latch has to go with
            -- it, or this slot never turns red again for the session.
            f.low = low or nil
            f.lastSecs = nil          -- pooled frames keep the old value

            if iconSide ~= "none" then
                f.icon:SetTexture(e.placeholder and 134400 or ns.Timers.IconOf(b))
                f.iconFrame:SetSize(h, h)
                f.iconFrame:ClearAllPoints()
                if iconSide == "left" then f.iconFrame:SetPoint("RIGHT", f, "LEFT", -2, 0)
                else f.iconFrame:SetPoint("LEFT", f, "RIGHT", 2, 0) end
                f.iconFrame:Show()
            else
                f.iconFrame:Hide()
            end

            local size = opts.fontSize or 11
            ns.SetFontSafe(f.text, size, "OUTLINE")
            ns.SetFontSafe(f.time, size, "OUTLINE")
            local name = e.placeholder and ("Ability " .. i) or ns.Timers.AbilityName(b)
            local textMode = opts.text or "both"
            f.text:SetText((textMode == "time") and "" or name)
            -- The ability's own colour goes on its NAME, never the fill.
            local cr, cg, cb
            if not e.placeholder then cr, cg, cb = ns.Timers.AbilityColor(b) end
            f.text:SetTextColor(cr or 1, cg or 1, cb or 1, 1)
            local secs = math.ceil(math.max(0, e.left))
            f.time:SetText((textMode == "name") and "" or (secs > 0 and tostring(secs) or "now"))
            f.entry = e
            f:Show()
        end
    end
    frame:SetSize(w + ((iconSide ~= "none") and (h + 2) or 0), math.max(h, pos - spacing))
    ns.SyncAnchorOrigin(frame, "barsPos")
    Label()
    local unlocked = ns.db and ns.db.unlocked
    if n > 0 or state.preview or unlocked then frame:Show() else frame:Hide() end
end
B.Refresh = Refresh

--- Every frame: the fill moves smoothly; the seconds change once a second;
-- a bar past its moment reads "now" until the hub drops it.
local function Tick(now)
    if not frame or not frame:IsShown() or state.preview then return end
    local opts = O() or {}
    for i = 1, MAX_BARS do
        local f = bars[i]
        local e = f.entry
        if f:IsShown() and e and e.bar then
            local left = e.bar.at - now
            local frac = (e.dur > 0) and math.max(0, math.min(1, left / e.dur)) or 0
            f.bar:SetValue((opts.fill or "drain") == "fill" and (1 - frac) or frac)
            if (opts.text or "both") ~= "name" then
                local secs = left > 0 and math.ceil(left) or 0
                if secs ~= f.lastSecs then
                    f.lastSecs = secs
                    f.time:SetText(secs > 0 and tostring(secs) or "now")
                end
            end
            -- Once, on the crossing: this loop runs at framerate.
            if opts.byRemaining and left <= (opts.byRemainingAt or 3) and not f.low then
                f.low = true
                f.bar:SetStatusBarColor(1, 0.3, 0.3, 0.9)
            end
        end
    end
end
B.Tick = Tick

local function Apply()
    if not Enabled() then
        if frame then frame:Hide() end
        return
    end
    Build()
    -- Values move every frame, not on the hub's 0.2s tick.
    if not frame.smooth then
        frame.smooth = true
        frame:SetScript("OnUpdate", function() Tick(GetTime()) end)
    end
    if ns.SetMovableScale(frame, state.preview and 1 or ns.AnchorScale()) and not state.preview then RestorePosition() end
    local unlocked = ns.db and ns.db.unlocked
    if state.preview then
        frame.unlockBg:Hide()
        Refresh()
        frame:Show()
        return
    end
    frame.unlockBg:SetShown(unlocked)
    if ns.Timers.Any() then
        Refresh()
    elseif unlocked then
        Refresh(true)
    else
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Bars")
B.Apply = Apply

ns.Timers.Register({
    OnChange = function()
        if state.preview then return end
        if not Enabled() then return end
        Build()
        Refresh()
    end,
    -- No OnTick: the frame's own OnUpdate drives values every frame.
})

function ns.BarsPreviewStart(stage)
    Build()
    state.preview = stage
    state.previewBars = ns.Timers.FakeBars(3, 40, true)
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, 0)
    Apply()
end

function ns.BarsPreviewStop()
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
