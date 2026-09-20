--[[ Salus Novus -- Options: the settings window. /sn

MerkUI's Options.lua (its chrome, controls, unlock flow and previews)
cut down to Salus Novus's three pages: Anchors -> Bars, Anchors -> Reminders,
and Global. GROUPS in the sidebar on the left, each group's pages in a
strip across the top of the content area; every control is a ROW (label
left, control right, faint banding) in two columns inside section cards;
a page with an anchor renders that anchor's REAL frame into a preview
stage at the top while the page is open.

Unlock Frames hides the window, unlocks every movable frame over the
alignment grid, and floats a small bar with Save Positions and Cancel.
Save locks and reopens the window on the page you left; Cancel also puts
every frame back where it was.

Left behind from retail: BigWigs pages, Abilities, Import/Export,
Auto Release, Group Finder links, the LibSharedMedia pickers, the Test
button, and the debts noted in the plan (RepaintTheme sweeping every page
on every ApplyAll; building every page on first open).
]]

local _, ns = ...
local T = ns.Theme

local PANEL_W, PANEL_H = 1100, 700
local SIDEBAR_W = 220
local HEADER_H  = 66
local STRIP_H   = 38
local NAV_ROW_H = 40
local ROW_H     = 36
local HEAD_H    = 26
local ROW_GAP   = 2
local LOOSE_GAP = 8

local CONTENT_W = PANEL_W - SIDEBAR_W - 1 - 10 - 14 - 4
local PAGE_PAD  = 10
local COL_GAP   = 16
local COL_W     = math.floor((CONTENT_W - PAGE_PAD * 2 - COL_GAP) / 2)
local COL_LEFT  = { PAGE_PAD, PAGE_PAD + COL_W + COL_GAP }

-- The sidebar is organised by MODULE: a heading with a master switch, and
-- the module's groups under it. Global is a heading with no switch. A
-- group with `launch` is a row that opens another window instead of pages.
local MODULES = {
    { key = "bossWarnings", label = "Boss Warnings" },
}
local MODULE_BY_SECTION = {}
for _, m in ipairs(MODULES) do MODULE_BY_SECTION[m.label] = m end

local GROUPS = {
    { section = "Global",                                 key = "global",     label = "Settings",        pages = { "global" } },
    { section = "Boss Warnings", module = "bossWarnings", key = "anchors",    label = "Anchors",         pages = { "bars", "queue", "preview", "messages", "health", "reminders" } },
    { section = "Boss Warnings", module = "bossWarnings", key = "visualizer", label = "Boss Visualizer", launch = true },
}
local PAGE_GROUP, PAGE_MODULE = {}, {}
for _, g in ipairs(GROUPS) do
    for i, p in ipairs(g.pages or {}) do
        PAGE_GROUP[p] = { group = g, index = i }
        PAGE_MODULE[p] = g.module
    end
end
local NAV_HEAD_H = 26
local NAV_SUB_H  = 32
local function LayoutSidebar()
    local y = 0
    local last
    for _, g in ipairs(GROUPS) do
        if g.section ~= last then
            if last then y = y + 10 end
            g.headY = y
            y = y + NAV_HEAD_H
            last = g.section
        end
        g.navY = y
        y = y + NAV_SUB_H
    end
    return y
end
LayoutSidebar()

local PAGE_STRIP_LABEL = { bars = "Bars", queue = "Ability Queue", preview = "Ability Preview", messages = "Messages", health = "Health Bars", reminders = "Reminders", global = "Settings" }

local panel
local shell
local widgets = {}        -- every widget, for RefreshAll
local pageWidgets = {}    -- page outer frame -> the widgets built on it
local pages = {}
local pageBuilt = {}      -- page bodies are built on first visit
local PAGE_BODY = {}
local tabs = {}
local strips = {}
local lastPage = {}
local activePage
local previewStages = {}

local O = {}
ns.Options = O
O.widgets, O.pages, O.previewStages = widgets, pages, previewStages

-- Forward: GroupTab's launcher row calls it and it is defined below
-- (a local used above its declaration is a silent nil global).
local OpenWindow

--------------------------------------------------------------------------------
-- Widget registry / refresh
--------------------------------------------------------------------------------
local function PageOf(p) return (p and p.__outer) or p end

local function Register(page, w)
    widgets[#widgets + 1] = w
    local outer = PageOf(page)
    w.__outer = outer
    w.__module = outer and outer.__module or nil
    if not outer then return end
    local list = pageWidgets[outer]
    if not list then list = {}; pageWidgets[outer] = list end
    list[#list + 1] = w
end

-- Per widget, not per sweep: one throwing control must not leave every
-- control after it stale. Reported once each (Refresh runs per slider step).
local sweepErrShown = {}
local function Sweep(list)
    for _, w in ipairs(list) do
        local ok, err = pcall(function()
            if w.Update then w:Update() end
            -- A page whose module is switched off reads as disabled whole;
            -- its own EnabledWhen rules only matter while the module is on.
            if w.__module and not ns.ModuleOn(w.__module) then
                if w.SetEnabledState then w:SetEnabledState(false) end
            elseif w.EnabledWhen and w.SetEnabledState then
                w:SetEnabledState(w.EnabledWhen())
            elseif w.__module and w.SetEnabledState then
                w:SetEnabledState(true)        -- back on after the module was off
            end
        end)
        if not ok and not sweepErrShown[w] then
            sweepErrShown[w] = true
            ns.Print("a settings control failed to refresh: " .. tostring(err))
        end
    end
end

local function Refresh()
    local outer = activePage and pages[activePage]
    local list = outer and pageWidgets[outer]
    if list then Sweep(list) else Sweep(widgets) end
    for _, st in ipairs(previewStages) do
        if st.enabledWhen and st:IsShown() then
            local on = st.enabledWhen() and true or false
            if st.lastEnabled ~= on then
                st.lastEnabled = on
                st:Resume()
            end
        end
    end
end
O.Refresh = Refresh

local function RefreshAll() Sweep(widgets) end
O.RefreshAll = RefreshAll

--------------------------------------------------------------------------------
-- Rows, sections, previews
--------------------------------------------------------------------------------
local function MakeRow(page, anchor, height)
    local col = (anchor and anchor.__col) or 1
    local row = CreateFrame("Frame", nil, page)
    row:SetHeight(height or ROW_H)
    row:SetWidth(COL_W)
    local gap = (anchor and anchor.__loose) and LOOSE_GAP or ROW_GAP
    row:SetPoint("TOP", anchor, "BOTTOM", 0, -gap)
    row:SetPoint("LEFT", page, "LEFT", COL_LEFT[col], 0)
    row.__col = col
    local card = page.__card and page.__card[col]
    if card then
        card:SetPoint("BOTTOM", row, "BOTTOM", 0, -8)
        row:SetFrameLevel(card:GetFrameLevel() + 2)
    end
    page.__rows = page.__rows or {}
    page.__rows[col] = (page.__rows[col] or 0) + 1
    if page.__rows[col] % 2 == 1 then
        row.bg = T.SolidTex(row, "BACKGROUND", 1, 1, 1, 0.035)
        row.bg:SetAllPoints()
    end
    row.label = T.MakeText(row, 13, T.TEXT)
    row.label:SetPoint("LEFT", 12, 0)
    row.label:SetPoint("RIGHT", row, "RIGHT", -250, 0)
    row.label:SetWordWrap(false)
    function row:SetLabelEnabled(e)
        local c = e and T.TEXT or T.TEXT_MUTE
        self.label:SetTextColor(c[1], c[2], c[3], 1)
    end
    function row:SetControl(ctrl)
        self.label:SetPoint("RIGHT", ctrl, "LEFT", -10, 0)
    end
    row:EnableMouse(true)
    -- No tooltips (Alex: keep the addon simple).
    return row
end

local function MakeTitle(page, text)
    local outer = page.__outer or page
    outer.__title = text
    page.__rows = {}
    local a = CreateFrame("Frame", nil, page)
    a:SetSize(1, 1)
    a:SetPoint("TOPLEFT", COL_LEFT[1], -2)
    a.__loose = true
    a.__col = 1
    return a
end

-- The LABEL is positioned first and the card hangs off it, NOT the other
-- way round: MakeRow anchors the card's BOTTOM to the row and the row to the
-- label, so a label anchored to the card closes an anchor cycle.
local function MakeSection(page, anchor, text, column)
    local fs = T.MakeText(page, 15, T.HEAD_TEXT)
    fs:SetJustifyH("CENTER")
    fs:SetWidth(COL_W - 6)
    local col = (column == 2) and 2 or ((anchor and anchor.__col) or 1)
    fs.__col = col
    fs:SetText(text)
    fs.__loose = true
    -- Centred on the card's head band by geometry, from the SAME anchor
    -- the card hangs from: rows hang from this title and the card's bottom
    -- from the last row, so the title must not hang from the card (cycle).
    local h = fs:GetStringHeight() or 15
    local drop = math.floor((HEAD_H - h) / 2 + 0.5)   -- whole pixels: a half-pixel row draws the boxes lopsided
    if column == 2 then
        fs:SetPoint("TOPLEFT", page, "TOPLEFT", COL_LEFT[2] + 3, -23 - drop)
    else
        fs:SetPoint("TOP", anchor, "BOTTOM", 0, -20 - drop)
        fs:SetPoint("LEFT", page, "LEFT", COL_LEFT[col] + 3, 0)
    end

    -- The card is placed from the section's anchor and the title is
    -- centred on the card's head band (Alex: "vertically centered").
    local card = CreateFrame("Frame", nil, page)
    card:SetFrameLevel(page:GetFrameLevel())
    if column == 2 then
        card:SetPoint("TOP", page, "TOP", 0, -23)
    else
        card:SetPoint("TOP", anchor, "BOTTOM", 0, -20)
    end
    card:SetPoint("LEFT", page, "LEFT", COL_LEFT[col], 0)
    card:SetWidth(COL_W)
    card:SetHeight(40)
    card.bg = T.SolidTex(card, "BACKGROUND", 1, 1, 1, 0.035)
    card.bg:SetAllPoints()
    card.border = ns.CreateBorder(card)
    card.border:Layout(card, 1, 0)
    card.border:SetColor(1, 1, 1, 0.08)
    card.border:Show()
    card.accent = T.SolidTex(card, "ARTWORK", 1, 1, 1, 1)
    card.accent:SetWidth(3)
    card.accent:SetPoint("TOPLEFT", 0, 0)
    card.accent:SetPoint("BOTTOMLEFT", 0, 0)
    T.Paint({ tex = card.accent, a = 0.55 })
    card.head = T.SolidTex(card, "BACKGROUND", 1, 1, 1, 1, 1)
    card.head:SetHeight(HEAD_H)
    card.head:SetPoint("TOPLEFT", card, "TOPLEFT", 3, 0)
    card.head:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    T.Paint({ tex = card.head, a = 0.22 })

    page.__card = page.__card or {}
    page.__card[col] = card
    fs.__card = card
    return fs
end

--- A live preview stage at the top of a page: the module renders its REAL
-- frame into it while the page is open. Suspended while frames are
-- unlocked (the frame is out on screen) or the feature is switched off.
local function MakePreview(page, anchor, height, start, stop, enabledWhen)
    local outer = page.__outer or page
    local stage = CreateFrame("Frame", nil, outer)
    stage:SetHeight(height)
    stage:SetPoint("TOPLEFT", outer, "TOPLEFT", PAGE_PAD, 0)
    stage:SetWidth(CONTENT_W - PAGE_PAD * 2)
    if stage.SetClipsChildren then stage:SetClipsChildren(true) end
    if outer.__scroll then
        outer.__scroll:SetPoint("TOPLEFT", outer, "TOPLEFT", 0, -(height + 10))
    end
    stage.bg = T.SolidTex(stage, "BACKGROUND", 1, 1, 1, 0.07)
    stage.bg:SetAllPoints()
    stage.sheen = T.SolidTex(stage, "BACKGROUND", 1, 1, 1, 1)
    stage.sheen:SetAllPoints()
    if stage.sheen.SetDrawLayer then stage.sheen:SetDrawLayer("BACKGROUND", 1) end
    T.Gradient(stage.sheen, 1, 1, 1, 0.06, 0.0, "VERTICAL")
    stage.border = ns.CreateBorder(stage)
    stage.border:Layout(stage, 1, 0)
    stage.border:SetColor(1, 1, 1, 0.14)
    stage.border:Show()
    stage.tag = T.MakeText(stage, 10, T.TEXT_MUTE)
    stage.tag:SetPoint("TOPLEFT", 10, -7)
    stage.tag:SetText("PREVIEW")
    stage.note = T.MakeText(stage, 12, T.TEXT_MUTE)
    stage.note:SetPoint("CENTER", 0, 0)
    stage.note:Hide()
    stage.outer = outer
    stage.running = false

    function stage:Run()
        if self.running or not self.outer:IsShown() then return end
        self.running = true
        self.note:Hide()
        if start then start(self) end
    end
    function stage:Halt()
        if not self.running then return end
        self.running = false
        if stop then stop() end
    end
    function stage:Suspend(reason)
        self:Halt()
        self.note:SetText(reason or "")
        self.note:SetShown(reason ~= nil and reason ~= "")
    end
    function stage:Resume()
        local mod = self.outer.__module
        if mod and not ns.ModuleOn(mod) then
            local label = mod
            for _, m in ipairs(MODULES) do if m.key == mod then label = m.label end end
            self:Suspend(nil)   -- the stage just goes quiet; no wording (Alex)
        elseif ns.db and ns.db.unlocked then
            self:Suspend("Frames are unlocked -- drag them on screen. Save or Cancel to resume the preview.")
        elseif self.enabledWhen and not self.enabledWhen() then
            self:Suspend("This is switched off, so nothing will show in a fight. Tick the box below to enable it.")
        else
            self:Run()
        end
    end
    outer:HookScript("OnShow", function() stage:Resume() end)
    outer:HookScript("OnHide", function() stage:Halt() end)
    stage.enabledWhen = enabledWhen
    stage.stop = function() stage:Halt() end
    table.insert(previewStages, stage)
    return anchor
end

local function SyncPreviews()
    for _, s in ipairs(previewStages) do
        if s.outer and s.outer:IsShown() then s:Resume() end
    end
end

--------------------------------------------------------------------------------
-- Unlock mode
--------------------------------------------------------------------------------
local unlockBar
local unlockSnapshot
local lastPanelHide

local function CopyPos(p)
    if not p then return nil end
    -- Whole record: dropping the v=2 marker made Cancel restore growth-
    -- origin coordinates through the legacy branch (anchors jumped).
    local c = {}
    for k, v in pairs(p) do c[k] = v end
    return c
end

local ExitUnlockMode

local function BuildUnlockBar()
    if unlockBar then return unlockBar end
    local f = CreateFrame("Frame", "SalusNovusUnlockBar", UIParent)
    f:SetSize(420, 56)
    f:SetPoint("TOP", UIParent, "TOP", 0, -110)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f.bg = T.SolidTex(f, "BACKGROUND", 0, 0, 0, 0.82)
    f.bg:SetAllPoints()
    f.border = ns.CreateBorder(f)
    f.border:Layout(f, 1, 0)
    f.border:SetColor(1, 1, 1, 0.16)
    f.border:Show()
    f.accent = T.SolidTex(f, "ARTWORK", 1, 1, 1, 1)
    f.accent:SetHeight(2)
    f.accent:SetPoint("TOPLEFT", 0, 0)
    f.accent:SetPoint("TOPRIGHT", 0, 0)
    T.Paint({ tex = f.accent, a = 1 })
    f.text = T.MakeText(f, 13, T.TEXT)
    f.text:SetPoint("LEFT", 16, 0)
    f.text:SetText("Drag the frames into place")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f.cancel = T.MakeButton(f)
    f.cancel:SetSize(80, 26)
    f.cancel:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    f.cancel:SetText("Cancel")
    f.cancel:SetScript("OnClick", function() ExitUnlockMode(false) end)
    f.save = T.MakeButton(f)
    f.save:SetSize(120, 26)
    f.save:SetPoint("RIGHT", f.cancel, "LEFT", -8, 0)
    f.save:SetText("Save Positions")
    f.save:SetScript("OnClick", function() ExitUnlockMode(true) end)
    f:Hide()
    unlockBar = f
    return f
end

local function EnterUnlockMode()
    -- Already unlocked (the panel was reopened mid-drag): keep the
    -- snapshot, or Cancel would restore the dragged positions.
    if ns.db.unlocked and unlockSnapshot then
        BuildUnlockBar():Show()
        if panel then panel:Hide() end
        return
    end
    unlockSnapshot = {}
    for _, a in ipairs(ns.AnchorPositions) do
        unlockSnapshot[a.key] = CopyPos(SalusNovusDB[a.key])
    end
    -- Build the way OUT before committing to the state: the flag persists
    -- across /reload, so anything throwing in between would strand the user.
    local bar = BuildUnlockBar()
    ns.db.unlocked = true
    if panel then panel:Hide() end      -- halts the previews; frames go on screen
    bar:Show()
    ns.ShowAlignGrid(true)
    ns.ApplyAll()
    RefreshAll()
    SyncPreviews()
end
O.EnterUnlockMode = EnterUnlockMode

ExitUnlockMode = function(save)
    if not save and unlockSnapshot then
        for _, a in ipairs(ns.AnchorPositions) do
            SalusNovusDB[a.key] = unlockSnapshot[a.key]
            if ns[a.restore] then pcall(ns[a.restore]) end
        end
    end
    unlockSnapshot = nil
    ns.db.unlocked = false
    if unlockBar then unlockBar:Hide() end
    ns.ShowAlignGrid(false)
    ns.ApplyAll()
    RefreshAll()
    if panel then panel:Show() end      -- same page as before; OnShow resumes its preview
    SyncPreviews()
end
ns.ExitUnlockMode = function(save) return ExitUnlockMode(save) end
O.ExitUnlockMode = ExitUnlockMode

--------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------
-- The square check box lives in Theme now (the ability cards use it too).
local function MakeBlueSquare(parent, size) return T.MakeCheckBox(parent, size) end

local function MakeCheckbox(page, label, anchor, get, set, enabledWhen)
    local row = MakeRow(page, anchor)
    row.label:SetText(label)
    local cb = MakeBlueSquare(row, 18)
    cb:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    cb.text:Hide()
    row:SetControl(cb)
    cb:HookScript("OnClick", function(self)
        set(self:GetChecked() and true or false)
        ns.ApplyAll()
        Refresh()   -- the sweep suspends or resumes the page's preview stage
    end)
    row:SetScript("OnMouseUp", function()
        if cb.enabledState then cb:Click() end
    end)
    cb.Update = function(self) self:SetChecked(get()) end
    cb.EnabledWhen = enabledWhen
    cb.SetEnabledState = function(self, e)
        self.enabledState = e and true or false
        self:SetEnabled(self.enabledState)
        self:SetAlpha(e and 1 or 0.45)
        row:SetLabelEnabled(e)
    end
    cb.__kind, cb.__get, cb.__set = "check", get, set
    Register(page, cb)
    return row
end

-- No notes or tooltips (Alex): MakeNote is a pass-through so page bodies
-- keep their shape.
local function MakeNote(page, anchor, text)
    return anchor
end

local function MakeStepper(page, label, anchor, minV, maxV, get, set, fmt, enabledWhen)
    local row = MakeRow(page, anchor)
    row.label:SetText(label)
    local box = CreateFrame("Frame", nil, row)
    box:SetSize(56, 24)
    box:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    box.bg = T.SolidTex(box, "BACKGROUND", 1, 1, 1, 0.05)
    box.bg:SetAllPoints()
    box.border = ns.CreateBorder(box)
    box.border:Layout(box, 1, 0)
    box.border:SetColor(1, 1, 1, 0.10)
    box.border:Show()
    box.text = T.MakeText(box, 12, T.TEXT)
    box.text:SetPoint("CENTER", 0, 0)
    box.text:SetJustifyH("CENTER")

    local slider = T.MakeSlider(row, 170, minV, maxV, function(v)
        set(v)
        ns.ApplyAll()
        Refresh()
    end)
    slider:SetPoint("RIGHT", box, "LEFT", -12, 0)
    row:SetControl(slider)
    slider.Update = function(self)
        local v = get()
        self:SetValueQuiet(v)
        box.text:SetText(fmt and fmt(v) or tostring(v))
    end
    slider.EnabledWhen = enabledWhen
    slider.SetEnabledState = function(self, e)
        self:SetEnabled(e)
        self.Paint()
        local c = e and T.TEXT or T.TEXT_MUTE
        box.text:SetTextColor(c[1], c[2], c[3], 1)
        row:SetLabelEnabled(e)
    end
    slider.__kind, slider.__get, slider.__set, slider.__min, slider.__max = "stepper", get, set, minV, maxV
    Register(page, slider)
    return row
end

local function MakeColorSwatch(page, label, anchor, getColor, enabledWhen)
    local row = MakeRow(page, anchor)
    row.label:SetText(label)
    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(26, 20)
    swatch:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    row:SetControl(swatch)
    swatch.fill = T.SolidTex(swatch, "BACKGROUND", 1, 1, 1, 1)
    swatch.fill:SetAllPoints()
    swatch.border = ns.CreateBorder(swatch)
    swatch.border:Layout(swatch, 1, 0)
    swatch.border:SetColor(1, 1, 1, 0.25)
    swatch.border:Show()
    swatch.Update = function(self)
        local c = getColor()
        self.fill:SetVertexColor(c.r, c.g, c.b, 1)
    end
    swatch.EnabledWhen = enabledWhen
    swatch.SetEnabledState = function(self, e)
        self:SetEnabled(e)
        self.fill:SetAlpha(e and 1 or 0.35)
        row:SetLabelEnabled(e)
    end
    swatch.__kind, swatch.__get = "color", getColor
    Register(page, swatch)
    swatch:SetScript("OnClick", function()
        local c = getColor()
        local prevR, prevG, prevB = c.r, c.g, c.b
        local function Set(r, g, b)
            local live = getColor() or c
            live.r, live.g, live.b = r, g, b
            ns.ApplyAll()
            Refresh()
        end
        T.OpenColorPicker(c, Set, function() Set(prevR, prevG, prevB) end)
    end)
    return row, swatch
end

local SEG_MAX_VALUES = 6
local SEG_MAX_WIDTH  = 300
local function MakeSegmented(parent, values, labels, get, choose)
    local seg = CreateFrame("Frame", nil, parent)
    seg:SetHeight(24)
    seg.buttons = {}
    seg.enabledState = true
    local total, prev = 0, nil
    for i, v in ipairs(values) do
        local b = CreateFrame("Button", nil, seg)
        b:SetHeight(24)
        b.bg = T.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.06)
        b.bg:SetAllPoints()
        b.text = T.MakeText(b, 12, T.TEXT_MUTE)
        b.text:SetPoint("CENTER", 0, 0)
        b.text:SetText(labels[v] or tostring(v))
        b:SetWidth(math.floor((b.text:GetStringWidth() or 30) + 22))
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", 2, 0)
            total = total + 2
        else
            b:SetPoint("LEFT", seg, "LEFT", 0, 0)
        end
        total = total + b:GetWidth()
        b.value = v
        b:SetScript("OnClick", function() if seg.enabledState then choose(v) end end)
        b:SetScript("OnEnter", function(self)
            if seg.enabledState and not self.active then self.bg:SetVertexColor(1, 1, 1, 0.14) end
        end)
        b:SetScript("OnLeave", function() seg:Paint() end)
        seg.buttons[i] = b
        prev = b
    end
    seg:SetWidth(total)
    seg.border = ns.CreateBorder(seg)
    seg.border:Layout(seg, 1, 0)
    seg.border:SetColor(1, 1, 1, 0.10)
    seg.border:Show()
    -- Widths measured at build time come out too small (the font isn't
    -- applied yet); re-measure whenever the strip paints.
    function seg:Relayout()
        local natural = 0
        for _, b in ipairs(self.buttons) do natural = natural + (b.text:GetStringWidth() or 30) + 22 end
        natural = natural + 2 * (#self.buttons - 1)
        local pad = (natural > SEG_MAX_WIDTH) and 12 or 22
        local tot, pv = 0, nil
        for _, b in ipairs(self.buttons) do
            local w = math.floor((b.text:GetStringWidth() or 30) + pad)
            if w > 24 and w ~= b:GetWidth() then b:SetWidth(w) end
            b:ClearAllPoints()
            if pv then b:SetPoint("LEFT", pv, "RIGHT", 2, 0); tot = tot + 2
            else b:SetPoint("LEFT", self, "LEFT", 0, 0) end
            tot = tot + b:GetWidth()
            pv = b
        end
        if tot > 0 and tot ~= self:GetWidth() then self:SetWidth(tot) end
    end
    function seg:Paint()
        self:Relayout()
        local cur = get()
        local r, g, bb = T.Accent()
        local e = self.enabledState
        for _, b in ipairs(self.buttons) do
            b.active = (b.value == cur)
            if b.active then
                b.bg:SetVertexColor(r, g, bb, e and 0.9 or 0.3)
                local tr, tg, tb = T.OnAccent()
                b.text:SetTextColor(tr, tg, tb, e and 1 or 0.6)
            else
                b.bg:SetVertexColor(1, 1, 1, 0.06)
                b.text:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], e and 1 or 0.5)
            end
        end
    end
    function seg:SetEnabled(e) self.enabledState = e and true or false end
    return seg
end

-- Our own picker list for the font choice: a scrolling column where every
-- entry IS its preview, drawn in that font, so many can be compared at
-- once. (The client's menu forbids SetFont on its buttons.)
local pickerList
local function OpenPickerList(anchorBtn, values, labels, current, onPick)
    if pickerList and pickerList:IsShown() and pickerList.owner == anchorBtn then
        pickerList:Hide()
        return
    end
    if not pickerList then
        local f = CreateFrame("Frame", "SalusNovusPickerList", UIParent)
        f:SetFrameStrata("TOOLTIP")
        f:SetClampedToScreen(true)
        f:SetSize(300, 300)
        f.bg = T.SolidTex(f, "BACKGROUND", 0.06, 0.06, 0.08, 0.98)
        f.bg:SetAllPoints()
        f.border = ns.CreateBorder(f)
        f.border:Layout(f, 1, 0)
        f.border:SetColor(1, 1, 1, 0.16)
        f.border:Show()
        f.scroll = T.MakeScrollArea(f)
        f.scroll:SetPoint("TOPLEFT", 4, -4)
        f.scroll:SetPoint("BOTTOMRIGHT", -16, 4)
        f.rows = {}
        f:EnableMouse(true)
        -- Click anywhere outside to close: a catcher under the list.
        f.catcher = CreateFrame("Button", nil, f)
        f.catcher:SetFrameStrata("TOOLTIP")
        f.catcher:SetFrameLevel(f:GetFrameLevel() - 1)
        f.catcher:SetAllPoints(UIParent)
        f.catcher:SetScript("OnClick", function() f:Hide() end)
        f:SetScript("OnHide", function() f.owner = nil end)
        f:Hide()
        pickerList = f
        O.pickerList = f
    end
    local f = pickerList
    f.owner = anchorBtn
    local ROW = 24
    local content = f.scroll.child
    content:SetWidth(280)
    local n = #values
    for i, v in ipairs(values) do
        local r = f.rows[i]
        if not r then
            r = CreateFrame("Button", nil, content)
            r:SetSize(276, ROW - 2)
            r.bar = r:CreateTexture(nil, "BORDER")
            r.bar:SetTexture(T.SOLID)
            r.bar:SetPoint("TOPLEFT", 1, -1)
            r.bar:SetPoint("BOTTOMRIGHT", -1, 1)
            r.hl = r:CreateTexture(nil, "HIGHLIGHT")
            r.hl:SetTexture(T.SOLID)
            r.hl:SetAllPoints()
            r.hl:SetVertexColor(1, 1, 1, 0.12)
            r.text = T.MakeText(r, 13, T.TEXT)
            r.text:SetPoint("LEFT", 8, 0)
            r.text:SetPoint("RIGHT", -8, 0)
            r.text:SetJustifyH("LEFT")
            r.text:SetWordWrap(false)
            r.text:SetShadowColor(0, 0, 0, 0.9)
            r.text:SetShadowOffset(1, -1)
            f.rows[i] = r
        end
        r.value = v
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content, "TOPLEFT", 2, -(i - 1) * ROW - 2)
        r.text:SetText(labels[v] or tostring(v))
        r.bar:SetVertexColor(1, 1, 1, (v == current) and 0.10 or 0.03)
        -- The entry in its own font; a rejected path falls back to the
        -- active font inside SetFontSafe, so the row never goes blank.
        ns.SetFontSafe(r.text, 14, "", type(v) == "string" and v or T.FontPath())
        r.text:SetTextColor(1, 1, 1, 1)
        r:SetScript("OnClick", function()
            f:Hide()
            onPick(v)
        end)
        r:Show()
    end
    for i = n + 1, #f.rows do f.rows[i]:Hide() end
    content:SetHeight(n * ROW + 4)
    f:SetHeight(math.min(420, n * ROW + 12))
    f:ClearAllPoints()
    f:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -2)
    f.scroll:SetVerticalScroll(0)
    f:Show()
    -- Fonts load in the background the first time they are asked for, and
    -- a row asked in the same frame as sixty others drew nothing until it
    -- was re-set (measured: the fonts worked, the names did not show).
    -- Re-apply every row a moment later, twice, while the list is up.
    f.pass = (f.pass or 0) + 1
    local pass = f.pass
    local function Refont()
        if not f:IsShown() or f.pass ~= pass then return end
        for i = 1, n do
            local r = f.rows[i]
            if r and r:IsShown() then
                ns.SetFontSafe(r.text, 14, "", type(r.value) == "string" and r.value or T.FontPath())
                r.text:SetText(labels[r.value] or tostring(r.value))
            end
        end
    end
    C_Timer.After(0.25, Refont)
    C_Timer.After(1.5, Refont)
end

-- A choice among values: a button strip for a few, a dropdown (the
-- client's menu, or cycling when it is absent) for many. `preview =
-- "font"` opens the picker list above and draws the button in the font.
local function MakeDropdown(page, label, anchor, values, labels, get, set, enabledWhen, preview)
    local row = MakeRow(page, anchor)
    row.label:SetText(label)
    local function Choose(v)
        set(v)
        ns.ApplyAll()
        Refresh()
    end
    if #values <= SEG_MAX_VALUES and not preview then
        local seg = MakeSegmented(row, values, labels, get, Choose)
        if seg:GetWidth() <= SEG_MAX_WIDTH then
            seg:SetPoint("RIGHT", row, "RIGHT", -12, 0)
            row:SetControl(seg)
            seg.Update = function(self) self:Paint() end
            seg.EnabledWhen = enabledWhen
            seg.SetEnabledState = function(self, e)
                self:SetEnabled(e)
                self:Paint()
                row:SetLabelEnabled(e)
            end
            seg.__kind, seg.__get, seg.__set, seg.__values = "choice", get, set, values
            Register(page, seg)
            return row
        end
        seg:Hide()
    end
    local btn = T.MakeHeaderButton(row, 200, function(self)
        if preview then
            OpenPickerList(self, values, labels, get(), Choose)
        elseif MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                local current = get()
                for _, v in ipairs(values) do
                    local text = labels[v] or tostring(v)
                    if v == current then text = "|cffffffff" .. text .. "|r" end
                    root:CreateButton(text, function() Choose(v) end)
                end
            end)
        else
            local i = 1
            for k, val in ipairs(values) do if val == get() then i = k end end
            Choose(values[(i % #values) + 1])
        end
    end)
    btn:SetHeight(26)
    btn:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    btn.Update = function(self)
        local v = get()
        self.text:SetText(labels[v] or tostring(v))
        if preview == "font" then
            ns.SetFontSafe(self.text, 13, "", type(v) == "string" and v or T.FontPath())
        end
    end
    btn.EnabledWhen = enabledWhen
    btn.SetEnabledState = function(self, e)
        self:SetEnabled(e)
        local c = e and T.TEXT or T.TEXT_MUTE
        self.text:SetTextColor(c[1], c[2], c[3], 1)
        row:SetLabelEnabled(e)
    end
    btn.__kind, btn.__get, btn.__set, btn.__values = "choice", get, set, values
    Register(page, btn)
    return row
end

--------------------------------------------------------------------------------
-- Tabs / pages
--------------------------------------------------------------------------------
local function SelectPage(key)
    local pg = PAGE_GROUP[key]
    local groupKey = pg and pg.group.key or key
    if pages[key] and not pageBuilt[key] and PAGE_BODY[key] then
        pageBuilt[key] = true
        PAGE_BODY[key]()
    end
    -- HIDE the outgoing pages first, THEN show the incoming one (landmine 24).
    for k, page in pairs(pages) do
        if k ~= key then page:Hide() end
    end
    if pages[key] then pages[key]:Show() end
    for k, tab in pairs(tabs) do T.SetNavActive(tab, k == groupKey) end
    for k, strip in pairs(strips) do
        strip:SetShown(k == groupKey)
        if k == groupKey and strip.Relayout then strip:Relayout() end
        for pk, btn in pairs(strip.buttons) do btn:SetActive(pk == key) end
        -- Unlock Frames greys out while the strip's module is off: its
        -- anchors are hidden, so there is nothing to drag.
        if strip.unlock then strip.unlock:SetEnabledState(not strip.module or ns.ModuleOn(strip.module)) end
    end
    activePage = key
    lastPage[groupKey] = key
    local page = pages[key]
    if shell and shell.pageTitle then
        shell.pageTitle:SetText(page and page.__title or PAGE_STRIP_LABEL[key] or "")
    end
    Refresh()
end
O.SelectPage = SelectPage
function O.ActivePage() return activePage end

local sectionHeads = {}
local NAV_BASE = HEADER_H + 14

local function GroupTab(g, order)
    if tabs[g.key] then return tabs[g.key] end
    if g.section and g.headY and not sectionHeads[g.section] then
        local head = T.MakeText(shell.side, 12, T.TEXT_MUTE)
        head:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 22, -NAV_BASE - g.headY - 8)
        head:SetText(string.upper(g.section))
        local line = T.SolidTex(shell.side, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
        line:SetPoint("RIGHT", shell.side, "RIGHT", -14, 0)
        sectionHeads[g.section] = head
        -- A module heading carries its master switch at the right edge.
        local m = MODULE_BY_SECTION[g.section]
        if m then
            local sw = T.MakeCheck(shell.side, "", 16)
            sw:SetPoint("RIGHT", shell.side, "RIGHT", -14, 0)
            sw:SetPoint("TOP", head, "TOP", 0, 2)
            sw:SetChecked(ns.ModuleOn(m.key))
            sw:HookScript("OnClick", function(self)
                ns.db.modules = ns.db.modules or {}
                ns.db.modules[m.key] = self:GetChecked() and true or false
                ns.ApplyAll()
                RefreshAll()
                SyncPreviews()
                -- Unlock Frames greys out at once, not on the next page change.
                for _, strip in pairs(strips) do
                    if strip.unlock and strip.module == m.key then strip.unlock:SetEnabledState(ns.ModuleOn(m.key)) end
                end
            end)
            sw.Update = function(self) self:SetChecked(ns.ModuleOn(m.key)) end
            sw.__kind, sw.__get, sw.__set = "check",
                function() return ns.ModuleOn(m.key) end,
                function(v) ns.db.modules = ns.db.modules or {}; ns.db.modules[m.key] = v and true or false end
            Register(nil, sw)
            O.moduleSwitches = O.moduleSwitches or {}
            O.moduleSwitches[m.key] = sw
        end
    end
    local tab = CreateFrame("Button", nil, shell.side)
    tab:SetSize(SIDEBAR_W, NAV_SUB_H)
    tab:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 0, -NAV_BASE - (g.navY or ((order - 1) * NAV_SUB_H)))
    for _, part in ipairs(T.DecorateNavRow(tab)) do shell:Register(part) end
    T.NavLabel(tab, g.label)
    ns.SetFontSafe(tab.label, 13.5, "")
    tab.label:ClearAllPoints()
    tab.label:SetPoint("LEFT", 36, 0)
    tab:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    tab:SetScript("OnLeave", function(self)
        local cur = PAGE_GROUP[activePage]
        T.SetNavActive(self, cur and cur.group.key == g.key)
    end)
    if g.launch then
        -- A launcher row: opens the other window; the panel comes back
        -- when it closes (ReturnToOptions).
        tab:SetScript("OnClick", function() OpenWindow(ns.VisualizerToggle, ns.VisualizerShown) end)
    else
        tab:SetScript("OnClick", function() SelectPage(lastPage[g.key] or g.pages[1]) end)
    end
    tabs[g.key] = tab
    return tab
end

local function GroupStrip(g)
    if strips[g.key] then return strips[g.key] end
    local strip = CreateFrame("Frame", nil, panel)
    strip:SetHeight(STRIP_H)
    strip:SetPoint("TOPLEFT", panel, "TOPLEFT", SIDEBAR_W + 1, -HEADER_H)
    strip:SetPoint("RIGHT", panel, "RIGHT", 0, 0)
    strip.band = T.SolidTex(strip, "BACKGROUND", 0, 0, 0, 0.18)
    strip.band:SetAllPoints()
    strip.line = T.SolidTex(strip, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    strip.line:SetHeight(1)
    strip.line:SetPoint("BOTTOMLEFT", 0, 0)
    strip.line:SetPoint("BOTTOMRIGHT", 0, 0)
    strip.buttons = {}
    strip.order = {}
    strip.module = g.module
    -- Unlock Frames, in the header left of the close X, for the group
    -- whose pages own movable frames.
    if g.key == "anchors" then
        local unlock = T.MakeButton(strip)
        unlock:SetSize(120, 24)
        unlock:SetPoint("RIGHT", shell.close, "LEFT", -12, 0)
        unlock:SetText("Unlock Frames")
        unlock:SetScript("OnClick", function() EnterUnlockMode() end)
        strip.unlock = unlock
        O.unlockButton = unlock
    end
    strip:Hide()
    strips[g.key] = strip
    return strip
end

local function StripButton(strip, key, label, index)
    local b = CreateFrame("Button", nil, strip)
    b:SetHeight(STRIP_H)
    b.text = T.MakeText(b, 13, T.TEXT_MUTE)
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b:SetWidth(math.max(60, (b.text:GetStringWidth() or 30) + 30))
    b.hover = T.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.04)
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.line = T.SolidTex(b, "ARTWORK", 1, 1, 1, 1)
    b.line:SetHeight(2)
    b.line:SetPoint("BOTTOMLEFT", 8, 0)
    b.line:SetPoint("BOTTOMRIGHT", -8, 0)
    T.Paint({ tex = b.line, a = 1 })
    function b:SetActive(on)
        self.active = on
        self.line:SetShown(on)
        local c = on and T.TEXT or T.TEXT_MUTE
        self.text:SetTextColor(c[1], c[2], c[3], 1)
    end
    b:SetScript("OnEnter", function(self) self.hover:Show() self.text:SetTextColor(1, 1, 1, 1) end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() self:SetActive(self.active) end)
    b:SetScript("OnClick", function() SelectPage(key) end)
    strip.buttons[key] = b
    strip.order[index] = key
    function strip:Relayout()
        local prev
        for i = 1, #self.order do
            local k = self.order[i]
            local btn = k and self.buttons[k]
            if btn then
                btn:SetWidth(math.max(60, math.ceil(btn.text:GetStringWidth() or 30) + 30))
                btn:ClearAllPoints()
                if prev then btn:SetPoint("LEFT", prev, "RIGHT", 2, 0)
                else btn:SetPoint("LEFT", self, "LEFT", 18, 0) end
                prev = btn
            end
        end
    end
    strip:Relayout()
    b:SetActive(false)
    return b
end

local function MakeTab(key, label)
    local pg = PAGE_GROUP[key]
    local g = pg.group
    local groupOrder = 1
    for i, gg in ipairs(GROUPS) do if gg == g then groupOrder = i end end
    GroupTab(g, groupOrder)
    local strip = GroupStrip(g)
    StripButton(strip, key, PAGE_STRIP_LABEL[key] or label, pg.index)

    local outer = CreateFrame("Frame", nil, panel)
    outer:SetPoint("TOPLEFT", SIDEBAR_W + 1, -HEADER_H - STRIP_H - 10)
    outer:SetPoint("BOTTOMRIGHT", -10, 62)
    outer:Hide()
    outer.__module = PAGE_MODULE[key]
    pages[key] = outer

    local sf = T.MakeScrollArea(outer)
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -14, 0)
    outer.__scroll = sf
    local content = sf.child
    content:SetWidth(CONTENT_W)
    content:SetHeight(900)
    content.__outer = outer
    outer.__content = content
    return content
end

--------------------------------------------------------------------------------
-- Page bodies (built on first visit)
--------------------------------------------------------------------------------
PAGE_BODY.bars = function()
    local pg = pages.bars.__content
    local t = MakeTitle(pg, "Bars")
    local br = function() return ns.db.bars end
    local brOn = function() return ns.db.bars.enabled end
    local stage = MakePreview(pg, t, 110,
        function(s) ns.BarsPreviewStart(s) end,
        function() ns.BarsPreviewStop() end,
        brOn)
    local sBars = MakeSection(pg, stage, "BARS")
    local brBox = MakeCheckbox(pg, "Enable Bars", sBars,
        function() return br().enabled end, function(v) br().enabled = v end)
    local brMax = MakeStepper(pg, "Maximum bars:", brBox, 1, 8,
        function() return br().max end, function(v) br().max = v end, nil, brOn)
    local brDir = MakeDropdown(pg, "Grow direction:", brMax,
        { "down", "up" }, { down = "Down", up = "Up" },
        function() return br().direction or "down" end, function(v) br().direction = v end, brOn)
    local brW = MakeStepper(pg, "Width:", brDir, 100, 500,
        function() return br().width end, function(v) br().width = v end,
        function(v) return v .. " px" end, brOn)
    local brH = MakeStepper(pg, "Height:", brW, 8, 40,
        function() return br().height end, function(v) br().height = v end,
        function(v) return v .. " px" end, brOn)
    local brSp = MakeStepper(pg, "Spacing:", brH, 0, 20,
        function() return br().spacing end, function(v) br().spacing = v end,
        function(v) return v .. " px" end, brOn)
    MakeStepper(pg, "Hold at zero:", brSp, 0, 100,
        function() return math.floor((br().grace or 2.5) * 10) end, function(v) br().grace = v / 10 end,
        function(v) return string.format("%.1f s", v / 10) end, brOn)

    local sLook = MakeSection(pg, nil, "LOOK", 2)
    -- (No Fill choice: bars drain, full stop -- Alex.)
    local brIcon = MakeDropdown(pg, "Icon:", sLook,
        { "left", "right", "none" }, { left = "Left", right = "Right", none = "None" },
        function() return br().icon or "left" end, function(v) br().icon = v end, brOn)
    local brText = MakeDropdown(pg, "Text:", brIcon,
        { "both", "name", "time" }, { both = "Name + Time", name = "Name", time = "Time" },
        function() return br().text or "both" end, function(v) br().text = v end, brOn)
    local brFont = MakeStepper(pg, "Text size:", brText, 8, 18,
        function() return br().fontSize end, function(v) br().fontSize = v end,
        function(v) return v .. " pt" end, brOn)
    local brColor = MakeColorSwatch(pg, "Default color:", brFont,
        function() return br().color end, brOn)
    local brRem = MakeCheckbox(pg, "Turn red near end", brColor,
        function() return br().byRemaining end, function(v) br().byRemaining = v end, brOn)
    MakeStepper(pg, "Red under:", brRem, 1, 60,
        function() return br().byRemainingAt or 3 end, function(v) br().byRemainingAt = v end,
        function(v) return v .. " s" end,
        function() return br().enabled and br().byRemaining end)
end

PAGE_BODY.queue = function()
    local pg = pages.queue.__content
    local t = MakeTitle(pg, "Ability Queue")
    local q = function() return ns.db.queue end
    local qOn = function() return ns.db.queue.enabled end
    local stage = MakePreview(pg, t, 96,
        function(s) ns.QueuePreviewStart(s) end,
        function() ns.QueuePreviewStop() end,
        qOn)
    local sLayout = MakeSection(pg, stage, "LAYOUT")
    local qBox = MakeCheckbox(pg, "Enable Ability Queue", sLayout,
        function() return q().enabled end, function(v) q().enabled = v end)
    local qCount = MakeStepper(pg, "Max icons:", qBox, 2, 8,
        function() return q().count end, function(v) q().count = v end, nil, qOn)
    local qSize = MakeStepper(pg, "Lead icon size:", qCount, 24, 96,
        function() return q().size end, function(v) q().size = v end,
        function(v) return v .. " px" end, qOn)
    local qShrink = MakeStepper(pg, "Shrink per icon:", qSize, 40, 100,
        function() return q().shrink end, function(v) q().shrink = v end,
        function(v) return v .. " %" end, qOn)
    local qGap = MakeStepper(pg, "Gap between icons:", qShrink, 0, 20,
        function() return q().gap end, function(v) q().gap = v end,
        function(v) return v .. " px" end, qOn)
    local qDir = MakeDropdown(pg, "Grow direction:", qGap,
        { "right", "left", "down", "up" }, { right = "Right", left = "Left", down = "Down", up = "Up" },
        function() return q().direction or "right" end, function(v) q().direction = v end, qOn)
    local qBorder = MakeStepper(pg, "Lead icon border:", qDir, 1, 3,
        function() return q().border end, function(v) q().border = v end,
        function(v) return v .. " px" end, qOn)
    local sUp = MakeSection(pg, qBorder, "UPCOMING ICONS")
    local qDesat = MakeCheckbox(pg, "Desaturate the icons after the lead", sUp,
        function() return q().desaturate ~= false end, function(v) q().desaturate = v end, qOn)
    MakeStepper(pg, "Fade across the queue:", qDesat, 0, 90,
        function() return q().fade end, function(v) q().fade = v end,
        function(v) return v .. " %" end, qOn)
    -- The draining edge is the only time-on-icon; no setting for it (Alex).

    local sLabels = MakeSection(pg, nil, "TEXT", 2)
    local qLabels = MakeDropdown(pg, "Ability names:", sLabels,
        { "none", "lead", "all" }, { none = "None", lead = "Next only", all = "All icons" },
        function() return q().labels or "lead" end, function(v) q().labels = v end, qOn)
    local qLabelSize = MakeStepper(pg, "Name size:", qLabels, 8, 16,
        function() return q().labelSize end, function(v) q().labelSize = v end,
        function(v) return v .. " pt" end,
        function() return q().enabled and (q().labels or "lead") ~= "none" end)
    local qTimers = MakeCheckbox(pg, "Show seconds until cast", qLabelSize,
        function() return q().showTimers end, function(v) q().showTimers = v end, qOn)
    local qTimersOn = function() return q().enabled and q().showTimers end
    local qTimerPos = MakeDropdown(pg, "Seconds position:", qTimers,
        { "center", "topleft", "topright", "bottomleft", "bottomright" },
        { center = "Center", topleft = "Top L", topright = "Top R", bottomleft = "Bottom L", bottomright = "Bottom R" },
        function() return q().timerPos or "center" end, function(v) q().timerPos = v end, qTimersOn)
    MakeStepper(pg, "Seconds size:", qTimerPos, 8, 24,
        function() return q().timerSize or 12 end, function(v) q().timerSize = v end,
        function(v) return v .. " pt" end, qTimersOn)
    -- No backdrop settings (Alex); the strip draws none by default.
end

PAGE_BODY.preview = function()
    local pg = pages.preview.__content
    local t = MakeTitle(pg, "Ability Preview")
    local pv = function() return ns.db.preview end
    local pvOn = function() return ns.db.preview.enabled end
    local stage = MakePreview(pg, t, 96,
        function(s) ns.PreviewPreviewStart(s) end,
        function() ns.PreviewPreviewStop() end,
        pvOn)
    local sLayout = MakeSection(pg, stage, "LAYOUT")
    local pvBox = MakeCheckbox(pg, "Enable Ability Preview", sLayout,
        function() return pv().enabled end, function(v) pv().enabled = v end)
    local pvFrom = MakeStepper(pg, "Count down from:", pvBox, 2, 10,
        function() return pv().countdownSeconds or 5 end, function(v) pv().countdownSeconds = v end,
        function(v) return v .. " s" end, pvOn)
    local pvSize = MakeStepper(pg, "Text size:", pvFrom, 16, 40,
        function() return pv().fontSize or 28 end, function(v) pv().fontSize = v end,
        function(v) return v .. " pt" end, pvOn)
    local pvDir = MakeDropdown(pg, "Grow direction:", pvSize,
        { "up", "down" }, { up = "Up", down = "Down" },
        function() return pv().direction or "up" end, function(v) pv().direction = v end, pvOn)
    local pvGap = MakeStepper(pg, "Gap between lines:", pvDir, 0, 20,
        function() return pv().spacing or 4 end, function(v) pv().spacing = v end,
        function(v) return v .. " px" end, pvOn)
    MakeStepper(pg, "Max lines:", pvGap, 1, 8,
        function() return pv().max or 4 end, function(v) pv().max = v end, nil, pvOn)
    local sText = MakeSection(pg, nil, "TEXT", 2)
    local pvIcon = MakeCheckbox(pg, "Show the ability's icon", sText,
        function() return pv().showIcon ~= false end, function(v) pv().showIcon = v end, pvOn)
    MakeColorSwatch(pg, "Default color:", pvIcon,
        function() return pv().color end, pvOn)
end

PAGE_BODY.messages = function()
    local pg = pages.messages.__content
    local t = MakeTitle(pg, "Messages")
    local ms = function() return ns.db.messages end
    local msOn = function() return ns.db.messages.enabled end
    local stage = MakePreview(pg, t, 96,
        function(s) ns.MessagesPreviewStart(s) end,
        function() ns.MessagesPreviewStop() end,
        msOn)
    local sLayout = MakeSection(pg, stage, "LAYOUT")
    local msBox = MakeCheckbox(pg, "Enable Messages", sLayout,
        function() return ms().enabled end, function(v) ms().enabled = v end)
    local msSize = MakeStepper(pg, "Text size:", msBox, 12, 40,
        function() return ms().size or 24 end, function(v) ms().size = v end,
        function(v) return v .. " pt" end, msOn)
    local msHold = MakeStepper(pg, "Hold for:", msSize, 10, 100,
        function() return math.floor((ms().hold or 2.5) * 10) end, function(v) ms().hold = v / 10 end,
        function(v) return string.format("%.1f s", v / 10) end, msOn)
    local msDir = MakeDropdown(pg, "Grow direction:", msHold,
        { "up", "down" }, { up = "Up", down = "Down" },
        function() return ms().direction or "up" end, function(v) ms().direction = v end, msOn)
    local msGap = MakeStepper(pg, "Gap between lines:", msDir, 0, 20,
        function() return ms().spacing or 4 end, function(v) ms().spacing = v end,
        function(v) return v .. " px" end, msOn)
    MakeStepper(pg, "Max lines:", msGap, 1, 6,
        function() return ms().max or 3 end, function(v) ms().max = v end, nil, msOn)
    local sText = MakeSection(pg, nil, "TEXT", 2)
    local msIcon = MakeCheckbox(pg, "Show the ability's icon", sText,
        function() return ms().showIcon ~= false end, function(v) ms().showIcon = v end, msOn)
    MakeColorSwatch(pg, "Default color:", msIcon,
        function() return ms().color end, msOn)
    -- Which abilities show here is chosen per ability on the Boss
    -- Visualizer's cards (opt-in).
end

PAGE_BODY.health = function()
    local pg = pages.health.__content
    local t = MakeTitle(pg, "Health Bars")
    local hb = function() return ns.db.healthBars end
    local hbOn = function() return ns.db.healthBars.enabled end
    local stage = MakePreview(pg, t, 96,
        function(s) ns.HealthBarsPreviewStart(s) end,
        function() ns.HealthBarsPreviewStop() end,
        hbOn)
    local sLayout = MakeSection(pg, stage, "LAYOUT")
    local hbBox = MakeCheckbox(pg, "Enable Health Bars", sLayout,
        function() return hb().enabled end, function(v) hb().enabled = v end)
    local hbWidth = MakeStepper(pg, "Width:", hbBox, 120, 600,
        function() return hb().width or 260 end, function(v) hb().width = v end,
        function(v) return v .. " px" end, hbOn)
    local hbHeight = MakeStepper(pg, "Height:", hbWidth, 8, 40,
        function() return hb().height or 16 end, function(v) hb().height = v end,
        function(v) return v .. " px" end, hbOn)
    MakeColorSwatch(pg, "Bar color:", hbHeight,
        function() return hb().color end, hbOn)
    local sText = MakeSection(pg, nil, "TEXT", 2)
    local hbName = MakeCheckbox(pg, "Show the boss's name", sText,
        function() return hb().showName ~= false end, function(v) hb().showName = v end, hbOn)
    MakeStepper(pg, "Marker label size:", hbName, 8, 16,
        function() return hb().labelSize or 11 end, function(v) hb().labelSize = v end,
        function(v) return v .. " pt" end, hbOn)
    -- Which abilities get a marker is decided by the logs (cast at a health,
    -- not a time) and per ability on the Boss Visualizer's cards.
end

PAGE_BODY.reminders = function()
    local pg = pages.reminders.__content
    local t = MakeTitle(pg, "Reminders")
    local rm = function() return ns.db.reminders end
    local rmOn = function() return ns.db.reminders.enabled end
    local stage = MakePreview(pg, t, 90,
        function(s) ns.RemindersPreviewStart(s) end,
        function() ns.RemindersPreviewStop() end,
        rmOn)
    local sRM = MakeSection(pg, stage, "ANCHOR")
    local rmBox = MakeCheckbox(pg, "Enable Reminders", sRM,
        function() return rm().enabled end, function(v) rm().enabled = v end)
    local rmLead = MakeStepper(pg, "Count down from:", rmBox, 0, 30,
        function() return rm().lead or 5 end, function(v) rm().lead = v end,
        function(v) return v == 0 and "no countdown" or (v .. " s") end, rmOn)
    local rmHold = MakeStepper(pg, "Hold after:", rmLead, 5, 150,
        function() return math.floor((rm().hold or 4) * 10) end, function(v) rm().hold = v / 10 end,
        function(v) return string.format("%.1f s", v / 10) end, rmOn)
    local rmSize = MakeStepper(pg, "Text size:", rmHold, 12, 40,
        function() return rm().size or 22 end, function(v) rm().size = v end,
        function(v) return v .. " pt" end, rmOn)
    local rmColor = MakeColorSwatch(pg, "Default color:", rmSize,
        function() return rm().color end, rmOn)
    local rmSpacing = MakeStepper(pg, "Spacing:", rmColor, 0, 20,
        function() return rm().spacing or 4 end, function(v) rm().spacing = v end,
        function(v) return v .. " px" end, rmOn)
    local rmIcon = MakeCheckbox(pg, "Show the ability's icon", rmSpacing,
        function() return rm().showIcon ~= false end, function(v) rm().showIcon = v end, rmOn)
    -- (Sound is per reminder, on the visualizer's form; the cast-reminder
    -- throttle stays at its default -- Alex trimmed both from here.)
    MakeDropdown(pg, "Grow direction:", rmIcon,
        { "up", "down" }, { up = "Up", down = "Down" },
        function() return rm().direction or "up" end, function(v) rm().direction = v end, rmOn)
    -- Reminders are made, edited and removed on the Boss Visualizer only.
end

PAGE_BODY.global = function()
    local pg = pages.global.__content
    local t = MakeTitle(pg, "Settings")
    -- (No anchor scale setting -- Alex; the anchors draw at 100 %.)
    local sLook = MakeSection(pg, t, "GENERAL")
    local gClass = MakeCheckbox(pg, "Use my class color as the accent", sLook,
        function() return ns.db.theme.useClassColor ~= false end,
        function(v) ns.db.theme.useClassColor = v end)
    local gAccent = MakeColorSwatch(pg, "Custom accent:", gClass,
        function() return ns.db.theme.customColor end,
        function() return ns.db.theme.useClassColor == false end)
    local sGrid = MakeSection(pg, gAccent, "UNLOCK MODE")
    local gGrid = MakeCheckbox(pg, "Alignment grid while frames are unlocked", sGrid,
        function() return ns.db.anchorsGlobal.grid ~= false end,
        function(v) ns.db.anchorsGlobal.grid = v end)
    local gGridSize = MakeStepper(pg, "Grid spacing:", gGrid, 8, 128,
        function() return ns.db.anchorsGlobal.gridSize or 32 end,
        function(v) ns.db.anchorsGlobal.gridSize = v end,
        function(v) return v .. " px" end,
        function() return ns.db.anchorsGlobal.grid ~= false end)
    local gSnap = MakeCheckbox(pg, "Snap dropped frames", gGridSize,
        function() return ns.db.anchorsGlobal.snap ~= false end,
        function(v) ns.db.anchorsGlobal.snap = v end)
    MakeStepper(pg, "Snap within:", gSnap, 2, 30,
        function() return ns.db.anchorsGlobal.snapRange or 8 end,
        function(v) ns.db.anchorsGlobal.snapRange = v end,
        function(v) return v .. " px" end,
        function() return ns.db.anchorsGlobal.snap ~= false end)

    local sFont = MakeSection(pg, nil, "FONT", 2)
    local fontValues, fontLabels = {}, {}
    for _, f in ipairs(ns.GetFonts()) do
        table.insert(fontValues, f.path)
        fontLabels[f.path] = f.name
    end
    -- One picker; "Game default" is the stock font, stored as its path so
    -- the choice survives CopyDefaults (a nil would be re-seeded).
    local gFont = MakeDropdown(pg, "Font:", sFont, fontValues, fontLabels,
        function() return ns.db.font.path or ns.StockFont() end,
        function(v) ns.db.font.path = v end,
        nil, "font")
    MakeCheckbox(pg, "Apply this font to the whole game UI", gFont,
        function() return ns.db.font.wholeUI == true end,
        function(v) ns.db.font.wholeUI = v end)
end

--------------------------------------------------------------------------------
-- Panel
--------------------------------------------------------------------------------
-- Toggle fills, slider fills and segmented strips carry the accent: sweep
-- the widgets when the colour changes (only then -- not on every ApplyAll).
local lastR, lastG, lastB
ns.RegisterApply(function()
    if not shell then return end
    local r, g, b = T.Accent()
    if r == lastR and g == lastG and b == lastB then return end
    lastR, lastG, lastB = r, g, b
    shell:Repaint()
    RefreshAll()
end, "Options theme")

-- Opening the visualizer from the sidebar: hide this window, remember to
-- come back, and always SHOW the target. If it refuses to open, undo.
OpenWindow = function(open, shown)
    if not open then return end
    panel:Hide()
    ns.returnToOptions = true
    open(true)
    C_Timer.After(0, function()
        if ns.returnToOptions and not (shown and shown()) then
            ns.returnToOptions = nil
            if not panel:IsShown() then RefreshAll(); panel:Show() end
        end
    end)
end

local function BuildPanel()
    if panel then return panel end
    shell = T.MakeShell("SalusNovusOptions", PANEL_W, PANEL_H, SIDEBAR_W, HEADER_H, "SALUS NOVUS")
    panel = shell.frame
    O.panel, O.shell = panel, shell
    panel:HookScript("OnHide", function()
        for _, s in ipairs(previewStages) do
            if s.stop then s.stop() end
        end
        if pickerList then pickerList:Hide() end
        lastPanelHide = GetTime()
    end)
    shell.subtitle:SetText("")

    shell.pageTitle = T.MakeText(shell.header, 22, T.TEXT)
    shell.pageTitle:SetPoint("LEFT", shell.header, "LEFT", SIDEBAR_W + 26, 0)

    -- Footer: Reload UI and Close, bottom-right.
    local footerLine = T.SolidTex(panel, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    footerLine:SetHeight(1)
    footerLine:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", SIDEBAR_W + 1, 56)
    footerLine:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 56)
    local footerClose = T.MakeButton(panel)
    footerClose:SetSize(110, 30)
    footerClose:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -18, 14)
    footerClose:SetText("Close")
    footerClose:SetScript("OnClick", function() panel:Hide() end)
    local footerReload = T.MakeButton(panel)
    footerReload:SetSize(110, 30)
    footerReload:SetPoint("RIGHT", footerClose, "LEFT", -10, 0)
    footerReload:SetText("Reload UI")
    footerReload:SetScript("OnClick", function() if ReloadUI then ReloadUI() end end)

    MakeTab("global", "Global")
    MakeTab("bars", "Bars")
    MakeTab("queue", "Ability Queue")
    MakeTab("preview", "Ability Preview")
    MakeTab("messages", "Messages")
    MakeTab("health", "Health Bars")
    MakeTab("reminders", "Reminders")
    -- The Boss Visualizer row sits under Anchors in its module: a launcher,
    -- not a page, so it is made here rather than by MakeTab.
    for i, g in ipairs(GROUPS) do
        if g.launch then O.launcher = GroupTab(g, i) end
    end
    SelectPage("global")
    lastR, lastG, lastB = T.Accent()
    shell:Repaint()
    return panel
end

function ns.ToggleOptions()
    local p = BuildPanel()
    if p:IsShown() then
        p:Hide()
    else
        -- Opened by hand: closing the visualizer later must not bring the
        -- panel back on its own.
        ns.returnToOptions = nil
        RefreshAll()
        p:Show()
        SyncPreviews()   -- the page's preview resumes without relying on OnShow
    end
end

-- The unlocked flag persists, the Save/Cancel bar does not: a /reload
-- while unlocked would leave every anchor draggable with no way out.
-- Positions are saved on drag-stop, so nothing is lost by locking.
table.insert(ns.OnLoad, function()
    if ns.db and ns.db.unlocked then ns.db.unlocked = false end
end)

function ns.OptionsShown()
    return panel and panel:IsShown() or false
end

-- The visualizer, opened from the sidebar, calls this on hide: the settings
-- come back where they were. One ESC should close everything, not close
-- the other window and leave Settings up: if the panel was hidden a moment
-- ago it was the same keypress, not a click on the launcher.
function ns.ReturnToOptions()
    if not ns.returnToOptions then return end
    ns.returnToOptions = nil
    if lastPanelHide and (GetTime() - lastPanelHide) < 0.15 then return end
    local p = BuildPanel()
    if not p:IsShown() then
        Refresh()
        p:Show()
    end
end

-- A fight starting with the window open would leave a previewing anchor
-- parented to a page stage, dead for the pull; with frames unlocked, the
-- grid up and every anchor eating clicks. Closing the panel stops every
-- preview and puts the anchors back.
ns.Timers.Register({
    OnEncounter = function(active)
        if not active then return end
        if ns.db and ns.db.unlocked then pcall(ExitUnlockMode, true) end
        if panel and panel:IsShown() then panel:Hide() end
    end,
})
