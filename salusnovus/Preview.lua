--[[ Salus Novus -- Ability Preview: a countdown line per approaching cast.

MerkUI's Ability Preview (BigWigsRelay.lua) reduced to its countdown
tickers: as a routed ability comes within `countdownSeconds` of landing,
one line shows its icon, its name and the whole seconds left, the number
rewriting once a second. At landing the line simply goes (no NOW flash --
Alex). Every record comes from the hub; nothing is predicted beyond it.
]]

local _, ns = ...

local SOLID = ns.Theme.SOLID
local MAX_LINES = 8

local P = {}
ns.Preview = P

local function O() return ns.db and ns.db.preview end
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local lines = {}
P._lines = lines               -- test seam
local state = { preview = nil, previewBars = nil, previewTick = nil }
P.state = state

-- Edge origins (landmine 17): the stack's height changes with its lines,
-- so the anchor point is the edge the lines grow away from.
local function Origin()
    local d = O() and O().direction or "up"
    return d == "down" and "TOP" or "BOTTOM"
end
local function SavePosition()
    ns.SaveAnchor(frame, "previewPos")
end
local function RestorePosition()
    if not frame then return end
    -- Between the queue (CENTER +140) and the reminders anchor (TOP -160).
    ns.RestoreAnchor(frame, "previewPos", "BOTTOM", 0, 102, "CENTER")   -- Alex's layout
end
ns.PreviewRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "previewPos", restore = "PreviewRestorePosition" })

local function MakeLine()
    local f = CreateFrame("Frame", nil, frame)
    f.iconFrame = CreateFrame("Frame", nil, f)
    f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.iconBorder = ns.CreateBorder(f.iconFrame)
    f.iconBorder:Layout(f.iconFrame, 1, 0)
    f.iconBorder:SetColor(0, 0, 0, 0.9)
    f.iconBorder:Show()
    f.text = f:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(f.text, 28, "OUTLINE")
    f.text:SetPoint("CENTER", 0, 0)
    f:Hide()
    return f
end

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusPreview", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(320, 36)
    frame:Hide()
    for i = 1, MAX_LINES do lines[i] = MakeLine() end

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Ability Preview  \194\183  drag to move")
    frame.unlockLabel:Hide()

    ns.RegisterMovable(frame, "previewPos", Origin, RestorePosition)
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

--- The records within the countdown window, soonest first, capped; or a
-- sample while unlocked with nothing live.
local function Entries(now, placeholder)
    local opts = O() or {}
    local within = opts.countdownSeconds or 5
    local max = math.min(opts.max or 4, MAX_LINES)
    local out = {}
    if placeholder then
        out[1] = { key = 0, name = "Ability", secs = 3, placeholder = true }
        return out
    end
    for _, b in ipairs(state.previewBars or ns.Timers.Sorted()) do
        if #out >= max then break end
        local left = b.at - now
        if left > 0 and left <= within and ns.Timers.RoutedTo(b, "preview") then
            out[#out + 1] = { bar = b, key = b.key, secs = math.ceil(left) }
        end
    end
    return out
end
P.Entries = Entries

local function Refresh(placeholder)
    if not frame then return end
    local opts = O() or {}
    local now = GetTime()
    local entries = Entries(now, placeholder)
    local size = opts.fontSize or 28
    local spacing = opts.spacing or 4
    local up = (opts.direction or "up") ~= "down"
    local lineH = size + 8
    local widest = 120
    local pos = 0
    for i = 1, MAX_LINES do
        local f = lines[i]
        local e = entries[i]
        if not e then
            f:Hide()
            f.entry, f.lastSecs, f.lastKey = nil, nil, nil
        else
            local b = e.bar
            if f.lastKey ~= e.key then
                -- A different ability in this slot: everything is re-set.
                f.lastKey, f.lastSecs = e.key, nil
                ns.SetFontSafe(f.text, size, "OUTLINE")
                local cr, cg, cb
                if b then cr, cg, cb = ns.Timers.AbilityColor(b) end
                local c = opts.color or {}
                f.text:SetTextColor(cr or c.r or 1, cg or c.g or 0.82, cb or c.b or 0, 1)
                f.name = e.placeholder and e.name or ns.Timers.AbilityName(b)
                if opts.showIcon ~= false then
                    f.icon:SetTexture(e.placeholder and 134400 or ns.Timers.IconOf(b))
                    f.iconFrame:SetSize(size, size)
                    f.iconFrame:ClearAllPoints()
                    f.iconFrame:SetPoint("RIGHT", f.text, "LEFT", -8, 0)
                    f.iconFrame:Show()
                else
                    f.iconFrame:Hide()
                end
            end
            if f.lastSecs ~= e.secs then
                f.lastSecs = e.secs
                f.text:SetText(string.format("%s  %d", f.name, e.secs))
            end
            f:SetHeight(lineH)
            f:ClearAllPoints()
            if up then f:SetPoint("BOTTOM", frame, "BOTTOM", 0, pos)
            else f:SetPoint("TOP", frame, "TOP", 0, -pos) end
            f:SetWidth(math.max(120, (f.text:GetStringWidth() or 100) + size + 24))
            widest = math.max(widest, f:GetWidth())
            pos = pos + lineH + spacing
            f.entry = e
            f:Show()
        end
    end
    frame:SetSize(widest, math.max(lineH, pos - spacing))
    ns.SyncAnchorOrigin(frame, "previewPos")
    local unlocked = ns.db and ns.db.unlocked
    if #entries > 0 or state.preview or unlocked then frame:Show() else frame:Hide() end
end
P.Refresh = Refresh

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
        Refresh(true)
    else
        frame:Hide()
    end
end
ns.RegisterApply(Apply, "Preview")
P.Apply = Apply

-- The window of "within N seconds" moves every tick, so the line set is
-- rebuilt on the tick as well as on a change; the latches keep the text
-- writes to one per second.
ns.Timers.Register({
    OnChange = function()
        if state.preview or not Enabled() then return end
        Build()
        Refresh()
    end,
    OnTick = function()
        if state.preview or not Enabled() or not frame then return end
        Refresh()
    end,
})

-- Preview stage: three fakes counting down, re-armed when they run out.
local function ArmPreviewBars()
    state.previewBars = ns.Timers.FakeBars(3, 2, false)
end
function ns.PreviewPreviewStart(stage)
    Build()
    state.preview = stage
    ArmPreviewBars()
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", stage, "CENTER", 0, 0)
    Apply()
    if state.previewTick then state.previewTick:Cancel() end
    state.previewTick = C_Timer.NewTicker(0.2, function()
        if not state.preview then return end
        local now = GetTime()
        local alive = false
        for _, b in ipairs(state.previewBars or {}) do if b.at > now then alive = true break end end
        if not alive then ArmPreviewBars() end
        Refresh()
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", stage, "CENTER", 0, 0)
    end)
end

function ns.PreviewPreviewStop()
    if state.previewTick then
        state.previewTick:Cancel()
        state.previewTick = nil
    end
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
