--[[ Salus Novus -- the Session bar's frame: one movable databar (sessionPos)
with the XP, Gold and Lockouts segments, and the breakdown window a click
opens. Ctrl-click XP or Gold resets that segment.

Movable frames take the mouse only in unlock mode (ns.ApplyLocks), but this
bar is clicked while locked: the clicks go to one child button per
segment, hidden while unlocked so a drag reaches the bar.
]]

local _, ns = ...

local B = {}
ns.SessionBar = B
local S = function() return ns.Session end
local function T() return ns.Theme end

local PADX, GAP, HEIGHT = 10, 14, 22

local function O() return ns.db and ns.db.session end

-- Which segments are on, in order.
local SEGMENTS = {
    { key = "xp",        text = function() return S().XPText() end },
    { key = "gold",      text = function() return S().GoldText() end },
    { key = "instances", text = function() return S().InstancesText() end },
}

local function SegmentOn(key)
    local o = O()
    if not o then return true end
    if key == "xp" and S().AtMaxLevel() then return false end
    -- Lockouts only while something is actually counting against you.
    if key == "instances" and #S().Recent() == 0 and #S().RaidSaves() == 0 then return false end
    return o[key] ~= false
end

local function Size()
    local o = O()
    local n = o and tonumber(o.size)
    return (n and n >= 8 and n <= 24) and n or 12
end

local frame, detail

local function SavePosition() ns.SaveAnchor(frame, "sessionPos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "sessionPos", "TOP", 0, -8, "TOP")
end
ns.SessionRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "sessionPos", restore = "SessionRestorePosition" })

-- ------------------------------------------------------------ breakdown

local function DetailLines(key)
    local s, lines = S(), {}
    local function Add(l, r, color) lines[#lines + 1] = { l, r or "", color } end
    if key == "xp" then
        local st = s.State()
        local x = st and st.xp or {}
        Add("XP since reset", s.Short(x.total or 0))
        Add("Time", s.Duration(x.secs or 0))
        Add("Per hour", s.XPRate() and s.Short(s.XPRate()) or "--")
        Add("To next level", s.TimeToLevel() and s.Duration(s.TimeToLevel()) or "--")
        Add(" ")
        Add("Kills", s.Short(x.kill or 0))
        Add("  of it rested bonus", s.Short(x.rested or 0), "mute")
        Add("Quests", s.Short(x.quest or 0))
        Add("Other", s.Short(x.other or 0))
        Add("Rested left", s.Short(s.Rested()))
        local zones = {}
        for z, n in pairs(st and st.zones or {}) do zones[#zones + 1] = { z, n } end
        table.sort(zones, function(a, b) return a[2] > b[2] end)
        if #zones > 0 then
            Add(" ")
            for i = 1, math.min(5, #zones) do Add(zones[i][1], s.Short(zones[i][2]), "mute") end
        end
        Add(" ")
        Add("Ctrl-click to reset", nil, "mute")
    elseif key == "gold" then
        local inc, out, g = s.GoldTotals()
        Add("Net since reset", s.Money(inc - out))
        Add("Time", s.Duration(g.secs or 0))
        Add("Per hour", s.GoldRate() and (s.Gold(s.GoldRate()) .. " gold") or "--")
        Add(" ")
        Add("Earned", s.Money(inc))
        for _, c in ipairs(s.CATEGORY_ORDER) do
            if (g.inc[c] or 0) > 0 then Add("  " .. s.CATEGORY_LABEL[c], s.Money(g.inc[c]), "mute") end
        end
        Add("Spent", s.Money(out))
        for _, c in ipairs(s.CATEGORY_ORDER) do
            if (g.out[c] or 0) > 0 then Add("  " .. s.CATEGORY_LABEL[c], s.Money(g.out[c]), "mute") end
        end
        Add(" ")
        Add("Ctrl-click to reset", nil, "mute")
    else
        local limit = s.Limit()
        local recent = s.Recent()
        Add("Last hour", ("%d of %d"):format(#recent, limit))
        if s.NextSlot() then Add("Next slot", s.Duration(s.NextSlot())) end
        local now = time and time() or 0
        for _, e in ipairs(recent) do
            Add("  " .. (e.name or "?"), ("%s ago"):format(s.Duration(now - e.t)), "mute")
        end
        local saves = s.RaidSaves()
        if #saves > 0 then
            Add(" ")
            Add("Saved")
            for _, v in ipairs(saves) do Add("  " .. v.name, s.Duration(v.left), "mute") end
        end
    end
    return lines
end
B.DetailLines = DetailLines

local function BuildDetail()
    if detail then return detail end
    local Th = T()
    detail = CreateFrame("Frame", "SalusNovusSessionDetail", UIParent)
    detail:SetFrameStrata("DIALOG")
    detail:SetClampedToScreen(true)
    detail:SetWidth(240)
    detail:Hide()
    detail.bg = Th.SolidTex(detail, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 0.95)
    detail.bg:SetAllPoints()
    detail.border = ns.CreateBorder(detail)
    detail.border:Layout(detail, 1, 0)
    detail.border:SetColor(1, 1, 1, 0.12)
    detail.border:Show()
    detail.rows = {}
    if UISpecialFrames then table.insert(UISpecialFrames, "SalusNovusSessionDetail") end
    -- Live while open: rates and timers move.
    local acc = 0
    detail:SetScript("OnUpdate", function(self, dt)
        acc = acc + (dt or 0)
        if acc < 1 then return end
        acc = 0
        B.FillDetail()
    end)
    return detail
end

function B.FillDetail()
    if not (detail and detail:IsShown() and detail.key) then return end
    local Th = T()
    local lines = DetailLines(detail.key)
    local y, widest = 8, 0
    for i, l in ipairs(lines) do
        local r = detail.rows[i]
        if not r then
            r = { left = Th.MakeText(detail, 12, Th.TEXT), right = Th.MakeText(detail, 12, Th.TEXT) }
            r.left:SetJustifyH("LEFT")
            r.right:SetJustifyH("RIGHT")
            detail.rows[i] = r
        end
        local c = l[3] == "mute" and Th.TEXT_MUTE or Th.TEXT
        r.left:SetTextColor(c[1], c[2], c[3], 1)
        r.right:SetTextColor(c[1], c[2], c[3], 1)
        r.left:SetText(l[1])
        r.right:SetText(l[2])
        r.left:ClearAllPoints()
        r.left:SetPoint("TOPLEFT", detail, "TOPLEFT", 10, -y)
        r.right:ClearAllPoints()
        r.right:SetPoint("TOPRIGHT", detail, "TOPRIGHT", -10, -y)
        r.left:Show()
        r.right:Show()
        -- The window grows to its widest line: the columns never overlap.
        local lw = tonumber(r.left:GetStringWidth()) or 0
        local rw = tonumber(r.right:GetStringWidth()) or 0
        widest = math.max(widest, lw + (rw > 0 and (rw + 24) or 0))
        y = y + 16
    end
    for i = #lines + 1, #detail.rows do detail.rows[i].left:Hide() detail.rows[i].right:Hide() end
    detail:SetHeight(y + 6)
    detail:SetWidth(math.max(180, widest + 20))
end

--- Toggle the breakdown for a segment (a second click on it closes it).
function B.ShowDetail(key, seg)
    BuildDetail()
    if detail:IsShown() and detail.key == key then detail:Hide() return end
    detail.key = key
    detail:ClearAllPoints()
    local below = frame and frame:GetBottom() and frame:GetBottom() > 200
    if below then detail:SetPoint("TOPLEFT", seg or frame, "BOTTOMLEFT", 0, -4)
    else detail:SetPoint("BOTTOMLEFT", seg or frame, "TOPLEFT", 0, 4) end
    detail:Show()
    B.FillDetail()
end

-- ------------------------------------------------------------ the bar

local function Build()
    if frame then return frame end
    local Th = T()
    frame = CreateFrame("Frame", "SalusNovusSession", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(200, HEIGHT)
    frame:Hide()
    frame.bg = Th.SolidTex(frame, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 0.85)
    frame.bg:SetAllPoints()
    frame.border = ns.CreateBorder(frame)
    frame.border:Layout(frame, 1, -1)
    frame.border:SetColor(1, 1, 1, 0.10)
    frame.border:Show()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Session  \194\183  drag to move")
    frame.unlockLabel:Hide()
    frame.segs = {}
    for i, def in ipairs(SEGMENTS) do
        local seg = CreateFrame("Button", nil, frame)
        seg.key = def.key
        seg:SetHeight(HEIGHT)
        seg:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        seg.text = Th.MakeText(seg, Size(), Th.TEXT)
        seg.text:SetPoint("CENTER", 0, 0)
        seg.hover = Th.SolidTex(seg, "HIGHLIGHT", 1, 1, 1, 0.06)
        seg.hover:SetAllPoints()
        seg:SetScript("OnClick", function(self)
            if IsControlKeyDown and IsControlKeyDown() then
                if self.key == "xp" then S().ResetXP() elseif self.key == "gold" then S().ResetGold() end
                B.Refresh()
                return
            end
            B.ShowDetail(self.key, self)
        end)
        if i > 1 then
            seg.sep = Th.SolidTex(frame, "ARTWORK", 1, 1, 1, 0.12)
            seg.sep:SetWidth(1)
        end
        frame.segs[i] = seg
    end
    ns.RegisterMovable(frame, "sessionPos", function() return "TOP" end, RestorePosition)
    frame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)
    -- Logged-in time, and the text once a second.
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 1 then return end
        acc = 0
        B.Layout()
    end)
    RestorePosition()
    return frame
end
B.Build = Build

--- Write each segment's text and lay the bar out to fit.
function B.Layout()
    if not frame then return end
    local x = PADX
    local any = false
    for _, seg in ipairs(frame.segs) do
        local on = SegmentOn(seg.key)
        if on then
            local def
            for _, d in ipairs(SEGMENTS) do if d.key == seg.key then def = d end end
            ns.SetFontSafe(seg.text, Size(), "")
            seg.text:SetText(def.text())
            local w = (tonumber(seg.text:GetStringWidth()) or 60) + 4
            seg:SetWidth(w)
            seg:ClearAllPoints()
            seg:SetPoint("LEFT", frame, "LEFT", x - 2, 0)
            if seg.sep then
                seg.sep:ClearAllPoints()
                seg.sep:SetPoint("TOP", frame, "TOPLEFT", x - GAP / 2, -4)
                seg.sep:SetPoint("BOTTOM", frame, "BOTTOMLEFT", x - GAP / 2, 4)
                seg.sep:SetShown(any)
            end
            seg:Show()
            x = x + w + GAP
            any = true
        else
            seg:Hide()
            if seg.sep then seg.sep:Hide() end
        end
    end
    frame:SetWidth(math.max(60, x - GAP + PADX))
    frame:SetHeight(math.max(HEIGHT, Size() + 10))
    if ns.SyncAnchorOrigin then ns.SyncAnchorOrigin(frame, "sessionPos") end
end

--- Show or hide with the settings; called from Apply.
function B.Refresh()
    if not (S() and S().Enabled()) and not (ns.db and ns.db.unlocked) then
        if frame then frame:Hide() end
        if detail then detail:Hide() end
        return
    end
    Build()
    local unlocked = ns.db and ns.db.unlocked and true or false
    frame.unlockLabel:SetShown(unlocked)
    -- Clicks while locked; a drag while unlocked.
    for _, seg in ipairs(frame.segs) do seg:EnableMouse(not unlocked) end
    local any = false
    for _, d in ipairs(SEGMENTS) do if SegmentOn(d.key) then any = true end end
    if unlocked or any then frame:Show() else frame:Hide() end
    B.Layout()
    B.FillDetail()
end

ns.Session.OnChanged = function() if frame and frame:IsShown() then B.Layout() B.FillDetail() end end
ns.RegisterApply(function() B.Refresh() end, "Session bar")
