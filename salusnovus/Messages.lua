--[[ Salus Novus -- Messages: big text when a chosen ability lands.

MerkUI's Messages anchor (Messages.lua) without BigWigs: one kind of line,
fed by the hub's OnLand -- the moment a clustered cast reaches its time.
Only abilities routed to Messages on their card show here (opt-in, Alex),
in the ability's own colour when it has one. Lines stack from the anchor,
newest nearest it, and fade after `hold` seconds.
]]

local _, ns = ...

local SOLID = "Interface\\Buttons\\WHITE8x8"

local M = {}
ns.Messages = M

local function O() return ns.db and ns.db.messages end
local function Enabled()
    local o = O()
    return o and o.enabled and ns.ModuleOn("bossWarnings") and true or false
end

local frame
local pool, active = {}, {}
M._active = active             -- test seam
local state = { preview = nil, previewLoop = nil }
M.state = state

local function Origin()
    local d = O() and O().direction or "up"
    return d == "down" and "TOP" or "BOTTOM"
end
local function SavePosition()
    ns.SaveAnchor(frame, "messagesPos")
end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "messagesPos", "BOTTOM", 0, 189, "CENTER")   -- Alex's layout
end
ns.MessagesRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "messagesPos", restore = "MessagesRestorePosition" })

local function Build()
    if frame then return frame end
    frame = CreateFrame("Frame", "SalusNovusMessages", UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetSize(420, 34)
    frame:Hide()

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.unlockBg:SetTexture(SOLID)
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Messages  \194\183  drag to move")
    frame.unlockLabel:Hide()
    frame.unlockText = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockText, 24, "OUTLINE")
    frame.unlockText:SetPoint("CENTER")
    frame.unlockText:SetText("Sample message")
    frame.unlockText:Hide()

    ns.RegisterMovable(frame, "messagesPos", Origin)
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

local function Layout()
    local opts = O() or {}
    local up = (opts.direction or "up") ~= "down"
    local y = 0
    local tallest = 0
    for _, f in ipairs(active) do
        f:ClearAllPoints()
        if up then f:SetPoint("BOTTOM", frame, "BOTTOM", 0, y)
        else f:SetPoint("TOP", frame, "TOP", 0, -y) end
        y = y + (f.height or 34) + (opts.spacing or 4)
        tallest = f.height or 34
    end
    if #active > 0 then frame:SetHeight(math.max(tallest, y - (opts.spacing or 4))) end
    ns.SyncAnchorOrigin(frame, "messagesPos")
end

local function Retire(f)
    for i, af in ipairs(active) do
        if af == f then table.remove(active, i) break end
    end
    f:Hide()
    f.anim:Stop()
    table.insert(pool, f)
    Layout()
    if #active == 0 and not state.preview and not (ns.db and ns.db.unlocked) and frame then frame:Hide() end
end

local function Acquire()
    local f = table.remove(pool)
    if f then return f end
    f = CreateFrame("Frame", nil, frame)
    f:SetSize(420, 34)
    f.iconFrame = CreateFrame("Frame", nil, f)
    f.iconFrame:SetSize(28, 28)
    f.icon = f.iconFrame:CreateTexture(nil, "ARTWORK")
    f.icon:SetAllPoints()
    f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    f.iconBorder = ns.CreateBorder(f.iconFrame)
    f.iconBorder:Layout(f.iconFrame, 1, 0)
    f.iconBorder:SetColor(0, 0, 0, 0.9)
    f.iconBorder:Show()
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetPoint("CENTER")
    f.anim = f:CreateAnimationGroup()
    local fade = f.anim:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetDuration(0.4)
    f.fade = fade
    f.anim:SetScript("OnFinished", function() Retire(f) end)
    return f
end

--- One line: text in (r, g, b), an icon texture or nil.
local function Show(text, r, g, b, iconTexture)
    local opts = O() or {}
    Build()
    if not state.preview and frame:GetParent() ~= UIParent then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("HIGH")
        RestorePosition()
    end
    local max = opts.max or 3
    while #active >= max do
        local oldest = active[#active]
        if oldest then Retire(oldest) else break end
    end
    local size = opts.size or 24
    local c = opts.color or {}
    r, g, b = r or c.r or 1, g or c.g or 0.82, b or c.b or 0

    local f = Acquire()
    f.height = size + 10
    f:SetHeight(f.height)
    ns.SetFontSafe(f.text, size, "OUTLINE")
    f.text:SetTextColor(r, g, b, 1)
    f.text:SetText(ns.S(text))
    f.text:ClearAllPoints()
    f.text:SetPoint("CENTER")
    if opts.showIcon ~= false and iconTexture then
        f.icon:SetTexture(iconTexture)
        f.iconFrame:SetSize(size + 6, size + 6)
        f.iconFrame:ClearAllPoints()
        f.iconFrame:SetPoint("RIGHT", f.text, "LEFT", -8, 0)
        f.iconFrame:Show()
    else
        f.iconFrame:Hide()
    end
    f:SetAlpha(1)
    f:Show()
    table.insert(active, 1, f)
    Layout()
    f.fade:SetStartDelay(opts.hold or 2.5)
    f.anim:Stop()
    f.anim:Play()
    frame:Show()
end
M.Show = Show

local function OnLand(b)
    if not Enabled() or state.preview then return end
    if b.fake and not b.sample then return end
    if not ns.Timers.RoutedTo(b, "messages") then return end
    local r, g, bb = ns.Timers.AbilityColor(b)
    Show(ns.Timers.AbilityName(b), r, g, bb, ns.Timers.IconOf(b))
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
        frame.unlockText:Hide()
        frame:EnableMouse(false)
        frame:Show()
        return
    end
    frame.unlockBg:SetShown(unlocked)
    frame.unlockLabel:SetShown(unlocked)
    frame.unlockText:SetShown(unlocked and #active == 0)
    frame:EnableMouse(unlocked and true or false)
    if unlocked or #active > 0 then frame:Show() else frame:Hide() end
end
ns.RegisterApply(Apply, "Messages")
M.Apply = Apply

ns.Timers.Register({
    OnLand = OnLand,
    OnEncounter = function(on)
        if not on then
            for i = #active, 1, -1 do Retire(active[i]) end
        end
    end,
})

-- Preview: three sample lines from the data, looping.
function ns.MessagesPreviewStart(stage)
    Build()
    state.preview = stage
    frame:SetParent(stage)
    frame:SetFrameStrata(stage:GetFrameStrata())
    frame:SetFrameLevel(stage:GetFrameLevel() + 5)
    frame:ClearAllPoints()
    local opts = O() or {}
    local up = (opts.direction or "up") ~= "down"
    frame:SetPoint("CENTER", stage, "CENTER", 0, up and -22 or 22)
    Apply()
    if state.previewLoop then state.previewLoop:Cancel() end
    local samples = ns.Timers.FakeBars(3, 1, true)
    local i = 0
    local function step()
        i = i % #samples + 1
        local s = samples[i]
        local r, g, b = ns.Timers.AbilityColor(s)
        Show(ns.Timers.AbilityName(s), r, g, b, ns.Timers.IconOf(s))
        state.previewLoop = C_Timer.NewTimer(1.2, step)
    end
    for j = #active, 1, -1 do Retire(active[j]) end
    step()
end

function ns.MessagesPreviewStop()
    if state.previewLoop then
        state.previewLoop:Cancel()
        state.previewLoop = nil
    end
    if not state.preview then return end
    state.preview = nil
    for j = #active, 1, -1 do Retire(active[j]) end
    if frame then
        frame:SetParent(UIParent)
        frame:SetFrameStrata("HIGH")
        RestorePosition()
    end
    Apply()
end
