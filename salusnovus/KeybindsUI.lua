--[[ Salus Novus -- the keybind map (/sn keys, and the settings sidebar).

A window like the Wishlist's: the layers down the sidebar (None, Shift,
Ctrl, Alt, each with how many keys are free), the keyboard on the right.
Each key: its name top left, the icon of what it does bottom right (a
spell, an item, a macro's spell for that layer), an M on macros, a short
name when there's no icon (interface commands). Free keys are red, a
macro's modifier branch purple ("via"), a binding that shadows a macro's
branch amber. Hover a key for the line underneath; a click pins it.
]]

local _, ns = ...

local UI = {}
ns.KeybindsUI = UI
local function K() return ns.Keybinds end
local function T() return ns.Theme end

-- The whole keyboard is ~26 keys across: the key size follows the screen
-- (Build sets UNIT, KEY_H and the window to fit), 54 px a key at the most.
local WIN_W, WIN_H, SIDEBAR_W, HEADER_H = 1210, 560, 210, 64
local UNIT, GAP, KEY_H, PAD = 50, 4, 54, 20
local F_GAP = 0.3                                                   -- the space under the F row, in rows
local NAV_ROW_H = 44
local ICON = 28

local STATE_COLORS = {
    free     = { border = { 0.31, 0.82, 0.37, 0.95 }, bg = { 0.31, 0.82, 0.37, 0.10 } },   -- open: green (Alex)
    via      = { border = { 0.52, 0.47, 0.88, 1 },    bg = { 0.52, 0.47, 0.88, 0.16 } },
    conflict = { border = { 0.93, 0.62, 0.15, 1 },    bg = { 0.93, 0.62, 0.15, 0.16 } },
    bound    = { border = { 1, 1, 1, 0.14 },          bg = { 1, 1, 1, 0.04 } },
}

local frame, shell
UI.layer = 1
UI.pinned = nil

local DEFAULT_DETAIL = ""                  -- (no prompt: Alex)

local function KeyCell(parent)
    local Th = T()
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(KEY_H)
    b.bg = Th.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.04)
    b.bg:SetAllPoints()
    b.border = ns.CreateBorder(b)
    b.border:Layout(b, 1, -1)
    b.border:Show()
    -- An ability's icon fills the whole key (Alex), cropped to the key's
    -- shape; a dark band behind the key's name keeps it readable on any icon
    b.edge = Th.SolidTex(b, "ARTWORK", 0, 0, 0, 1)        -- (unused now; kept hidden)
    b.edge:Hide()
    b.icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.shade = Th.SolidTex(b, "ARTWORK", 0, 0, 0, 0.62, 2)
    b.shade:SetPoint("TOPLEFT", 1, -1)
    b.shade:SetPoint("TOPRIGHT", -1, -1)
    b.shade:SetHeight(17)
    b.shade:Hide()
    b.name = Th.MakeText(b, 11, Th.TEXT_MUTE, "OUTLINE")
    b.name:SetPoint("TOPLEFT", 4, -3)
    b.name:SetPoint("RIGHT", b, "RIGHT", -2, 0)        -- inside its key, never past it (Alex)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.name:SetDrawLayer("OVERLAY", 7)
    -- The name, up to two lines (a cut-off "Toggl..." said nothing).
    b.text = Th.MakeText(b, 11, Th.TEXT_DIM)
    b.text:SetPoint("TOPLEFT", b.name, "BOTTOMLEFT", 0, -3)
    b.text:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    b.text:SetJustifyH("LEFT")
    b.text:SetJustifyV("BOTTOM")
    b.text:SetWordWrap(true)
    if b.text.SetMaxLines then b.text:SetMaxLines(2) end
    b:SetScript("OnEnter", function(self) UI.Detail(self) end)
    b:SetScript("OnLeave", function() UI.Detail(UI.pinned) end)
    b:SetScript("OnClick", function(self)
        UI.pinned = (UI.pinned == self) and nil or self
        UI.Detail(UI.pinned)
        UI.Refresh()
    end)
    return b
end

local function LayerRow(i)
    local Th = T()
    local r = CreateFrame("Button", nil, shell.side)
    r:SetSize(SIDEBAR_W - 10, NAV_ROW_H)
    r:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 5, -HEADER_H - 12 - (i - 1) * NAV_ROW_H)
    for _, part in ipairs(Th.DecorateNavRow(r)) do shell:Register(part) end
    Th.NavLabel(r, K().LAYERS[i].label)
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 22, -5)
    r.sub = Th.MakeText(r, 12, Th.TEXT_MUTE)
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
    r:SetScript("OnClick", function() UI.layer = i; UI.pinned = nil; UI.Refresh() end)
    return r
end

local function Build()
    if frame then return frame end
    local Th = T()
    local chrome = SIDEBAR_W + 1 + 2 * PAD
    local sw = UIParent and tonumber(UIParent:GetWidth()) or 1365
    local pitch = math.max(34, math.min(54, math.floor((sw * 0.96 - chrome) / K().WIDTH)))
    GAP = pitch >= 46 and 4 or 3
    UNIT = pitch - GAP
    KEY_H = UNIT + 4
    WIN_W = math.ceil(chrome + K().WIDTH * pitch)
    WIN_H = HEADER_H + 16 + math.ceil((6 + F_GAP) * (KEY_H + GAP)) + 70
    shell = Th.MakeShell("SalusNovusKeybinds", WIN_W, WIN_H, SIDEBAR_W, HEADER_H, "Keybind Visualizer")
    frame = shell.frame
    frame.shell = shell
    frame:SetScript("OnHide", function()
        if ns.ReturnToOptions then ns.ReturnToOptions() end
    end)
    shell.subtitle:SetText("")
    frame.layers = {}
    for i = 1, #K().LAYERS do frame.layers[i] = LayerRow(i) end

    local content = shell.content
    frame.board = CreateFrame("Frame", nil, content)
    frame.board:SetPoint("TOPLEFT", PAD, -16)
    frame.board:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    frame.cells = {}
    local pitch, rowH = UNIT + GAP, KEY_H + GAP
    local function RowY(row) return (row - 1) * rowH + (row > 1 and math.floor(F_GAP * rowH) or 0) end
    UI.rowY = {}
    for r = 1, 6 do UI.rowY[r] = RowY(r) end
    for _, k in ipairs(K().KEYS) do
        local c = KeyCell(frame.board)
        c.key, c.label, c.pad = k.key, k.label, k.key == nil
        c:SetWidth(k.w * UNIT + (k.w - 1) * GAP)
        c:SetHeight(k.h * KEY_H + (k.h - 1) * GAP)
        c:SetPoint("TOPLEFT", frame.board, "TOPLEFT", math.floor(k.x * pitch + 0.5), -RowY(k.row))
        c.name:SetText(c.label)
        if c.pad then c:EnableMouse(false) end           -- Shift, Ctrl, Alt...: drawn, not bound
        frame.cells[#frame.cells + 1] = c
    end
    UI.keysRight = 15 * pitch                            -- the main block's edge
    frame.board:SetHeight(RowY(6) + KEY_H)

    frame.detail = Th.MakeText(content, 14, Th.TEXT)
    frame.detail:SetPoint("TOPLEFT", frame.board, "BOTTOMLEFT", 0, -12)        -- (no legend: Alex)
    frame.detail:SetPoint("RIGHT", content, "RIGHT", -PAD, 0)
    frame.detail:SetJustifyH("LEFT")
    frame.detail:SetWordWrap(true)
    frame.detail:SetText(DEFAULT_DETAIL)
    if UISpecialFrames then table.insert(UISpecialFrames, "SalusNovusKeybinds") end
    return frame
end
UI.Build = Build

--- The line under the keyboard: what a key does on the shown layer.
function UI.Detail(cell)
    if not frame then return end
    if not (cell and cell.res) then frame.detail:SetText(DEFAULT_DETAIL) return end
    local L = K().LAYERS[UI.layer]
    local combo = (L.mod and (L.label .. "-") or "") .. cell.label
    frame.detail:SetText(combo .. ":  " .. (cell.res.detail or ""))
end

local function Paint(c, res)
    if c.pad then                                        -- a placeholder: a dim outline and its name
        c.bg:SetVertexColor(1, 1, 1, 0.015)
        c.border:SetColor(1, 1, 1, 0.07)
        c.icon:Hide() c.shade:Hide() c.text:Hide()
        local m = T().TEXT_MUTE
        c.name:SetTextColor(m[1], m[2], m[3], 0.6)
        return
    end
    c.res = res
    local col = STATE_COLORS[res.state] or STATE_COLORS.bound
    c.bg:SetVertexColor(col.bg[1], col.bg[2], col.bg[3], col.bg[4])
    c.border:SetColor(col.border[1], col.border[2], col.border[3], col.border[4])
    if UI.pinned == c then
        local r, g, b = T().Accent()
        c.border:SetColor(r, g, b, 1)
    end
    local hasIcon = res.icon ~= nil and res.state ~= "free"
    c.icon:SetShown(hasIcon)
    c.shade:Hide()                                       -- (no dark band: the outlined name reads on its own -- Alex)
    local square = true
    if hasIcon then
        c.icon:SetTexture(res.icon)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        c.icon:ClearAllPoints()
        local w, h = tonumber(c:GetWidth()) or KEY_H, tonumber(c:GetHeight()) or KEY_H
        square = math.abs(w - h) <= 0.12 * math.max(w, h)
        if square then                                   -- a square key: the icon fills it (Alex)
            c.icon:SetPoint("TOPLEFT", 1, -1)
            c.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        else
            -- any other shape (Space, Tab, Enter, the tall numpad keys...): a
            -- square icon at its left (Alex), the action's name beside or under it
            local side = math.min(w, h) - 2
            c.icon:SetSize(side, side)
            c.icon:SetPoint("TOPLEFT", 1, -1)
        end
        c.name:SetTextColor(1, 1, 1, 1)
    else
        local m = T().TEXT_MUTE
        c.name:SetTextColor(m[1], m[2], m[3], 1)
    end
    -- A macro's other spells (Blood Fury before Lightning Bolt): small icons
    -- in the main icon's bottom-right corner, right to left (Alex: option C)
    c.badges = c.badges or {}
    local extras = hasIcon and res.extras or {}
    local side = (hasIcon and tonumber(c.icon:GetWidth())) or 0
    if side <= 0 then side = (tonumber(c:GetHeight()) or KEY_H) - 2 end
    local bs = math.max(10, math.floor(side * 0.38 + 0.5))
    for i = 1, math.max(#extras, #c.badges) do
        local bdg = c.badges[i]
        if extras[i] and i <= 3 then
            if not bdg then
                bdg = { edge = c:CreateTexture(nil, "ARTWORK", nil, 3), tex = c:CreateTexture(nil, "ARTWORK", nil, 4) }
                bdg.edge:SetColorTexture(0, 0, 0, 1)
                bdg.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                c.badges[i] = bdg
            end
            bdg.tex:SetTexture(extras[i])
            bdg.tex:SetSize(bs, bs)
            bdg.tex:ClearAllPoints()
            bdg.tex:SetPoint("BOTTOMRIGHT", c.icon, "BOTTOMRIGHT", -2 - (i - 1) * (bs + 2), 2)
            bdg.edge:ClearAllPoints()
            bdg.edge:SetPoint("TOPLEFT", bdg.tex, "TOPLEFT", -1, 1)
            bdg.edge:SetPoint("BOTTOMRIGHT", bdg.tex, "BOTTOMRIGHT", 1, -1)
            bdg.tex:Show() bdg.edge:Show()
        elseif bdg then
            bdg.tex:Hide() bdg.edge:Hide()
        end
    end
    -- The action's name: with no icon to say it (interface commands), or
    -- beside a non-square key's icon
    c.text:ClearAllPoints()
    if hasIcon and not square then
        local w, h = tonumber(c:GetWidth()) or KEY_H, tonumber(c:GetHeight()) or KEY_H
        if w > h then c.text:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, -16)
        else c.text:SetPoint("TOPLEFT", c.icon, "BOTTOMLEFT", 3, -4) end
        c.text:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -3, 3)
        c.text:Show()
    else
        c.text:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -3)
        c.text:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -3, 3)
        c.text:SetShown(not hasIcon and (res.state ~= "free" or res.empty) and true or false)
    end
    c.text:SetText(res.label or "")
end

function UI.Refresh()
    if not (frame and frame:IsShown()) then return end
    local res, free, total = K().Layer(UI.layer)
    for _, c in ipairs(frame.cells) do Paint(c, res[c.key] or { state = "free" }) end
    for i, r in ipairs(frame.layers) do
        T().SetNavActive(r, i == UI.layer)
        local _, f = K().Layer(i)
        r.sub:SetText(("%d free"):format(f))
    end
    UI.free, UI.total = free, total
    shell:SetTitle("Keybind Visualizer")
    shell.subtitle:SetText("")
    UI.Detail(UI.pinned)
end

function UI.Shown() return frame ~= nil and frame:IsShown() end

function UI.Open()
    Build()
    shell:Repaint()
    frame:Show()
    if frame.Raise then frame:Raise() end
    UI.Refresh()
end

--- Toggle, or with `forceShow` always show (the settings launcher).
function UI.Toggle(forceShow)
    if frame and frame:IsShown() and not forceShow then frame:Hide() else UI.Open() end
end

-- Bindings, bars and macros changing redraw an open map (once per frame).
local queued = false
local function Queue()
    if queued or not (frame and frame:IsShown()) then return end
    queued = true
    local function Go() queued = false UI.Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0, Go) else Go() end
end
for _, ev in ipairs({ "UPDATE_BINDINGS", "ACTIONBAR_SLOT_CHANGED", "UPDATE_MACROS", "ACTIONBAR_PAGE_CHANGED",
                      "UPDATE_BONUS_ACTIONBAR", "SPELLS_CHANGED" }) do
    ns.On(ev, Queue)
end

ns.Commands = ns.Commands or {}
ns.Commands.keys = function() UI.Toggle() end
ns.Commands.binds = ns.Commands.keys
