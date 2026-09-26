--[[ Salus Novus -- TrainerUI: the unlearned spells as a tab in the spellbook.

Alex (2026-09-23): "Enable unlearned spells in spellbook" and nothing
else -- the list is a tab in Blizzard's spellbook, beside the skill-line
tabs (General / Frost / Fire ...), not a window of its own.

Forever's spellbook is retail's PlayerSpellsFrame: SpellBookFrame holds
CategoryTabSystem (the icon tabs along the top) and PagedSpellsFrame (the
parchment page). We add one tab button to the end of that row, the same
size as its neighbours. Clicking it hides the page and shows our list in
its place; clicking any of Blizzard's tabs, or the spellbook closing,
puts the page back. Nothing of Blizzard's is changed beyond Hide/Show on
the page container, and no secure spell button is touched.

Rows read like the trainer's: icon, "Name (Rank n)", the cost, and a
"Requires: Level n, Prerequisite (Rank n)" line with unmet parts in red.
Learnable-now rows come first (with the total), then the rest by level.
]]

local _, ns = ...

local UI = {}
ns.TrainerUI = UI
local T = function() return ns.Trainer end

local SOLID = ns.Theme.SOLID
local TAB_ICON = 133741                                         -- INV_Misc_Book_09
local TAB_FRAME_ATLAS = "spellbook-Tab-Frame-Glow-C60"          -- Blizzard's selected-tab frame
local TAB_GLOW_ATLAS = "spellbook-Tab-Frame-glow-gradient-C60"  -- and the glow under it
local ROW_H, HEAD_H = 40, 26
local RED = "|cffff4040"

local content, tab, rows = nil, nil, {}
local host = {}                 -- the Blizzard frames we found
UI.host = host                  -- the probe reports what the tab attached to
local PlaceTab                  -- defined with the tab; Refresh (above it) re-places

-- ------------------------------------------------------------ content

--- Just above the page the list replaces, and never above the tab row:
-- at page + 5 our background covered the bottom of Blizzard's tabs. Run
-- at build and at every show (Blizzard may re-level its frames later).
local function Layer()
    if not content or not content.under then return end
    local lvl = content.under:GetFrameLevel() + 1
    content:SetFrameLevel(lvl)
    if host.tabs and host.tabs.GetFrameLevel and host.tabs:GetFrameLevel() <= lvl then host.tabs:SetFrameLevel(lvl + 1) end
end

local function BuildContent(parent, region)
    if content then return content end
    local Th = ns.Theme
    content = CreateFrame("Frame", "SalusNovusTrainerTab", parent)
    content:SetAllPoints(region or parent)
    content.under = region or parent
    Layer()
    content:Hide()
    content.bg = content:CreateTexture(nil, "BACKGROUND")
    content.bg:SetTexture(SOLID)
    content.bg:SetAllPoints()
    content.bg:SetVertexColor(Th.BG[1], Th.BG[2], Th.BG[3], 0.97)
    content.rail = content:CreateTexture(nil, "ARTWORK")
    content.rail:SetTexture(SOLID)
    content.rail:SetWidth(Th.RAIL_W)
    content.rail:SetPoint("TOPLEFT", 0, 0)
    content.rail:SetPoint("BOTTOMLEFT", 0, 0)
    Th.Paint({ tex = content.rail, a = 1 })

    content.title = Th.MakeText(content, 20, Th.TEXT)
    Th.SetDisplay(content.title, 20)
    content.title:SetPoint("TOPLEFT", Th.RAIL_W + 14, -12)
    content.title:SetText(Th.Upper("Unlearned spells"))

    content.scroll = Th.MakeScrollArea(content)
    content.scroll:SetPoint("TOPLEFT", Th.RAIL_W + 4, -44)
    content.scroll:SetPoint("BOTTOMRIGHT", -14, 10)
    content.list = content.scroll.child
    content.list:SetHeight(10)
    -- A scroll child has no width of its own (the shared helper leaves it
    -- 1px): rows anchored to its edges, and the strings anchored to the
    -- rows, would draw nothing. Keep it as wide as the scroll frame.
    local function FitList() content.list:SetWidth(math.max(1, content.scroll:GetWidth() or 0)) end
    content.scroll:SetScript("OnSizeChanged", FitList)
    content.FitList = FitList

    content.empty = Th.MakeText(content, 13, Th.TEXT_MUTE)
    content.empty:SetPoint("TOP", content, "TOP", 0, -90)
    content.empty:SetPoint("LEFT", content, "LEFT", 30, 0)
    content.empty:SetPoint("RIGHT", content, "RIGHT", -30, 0)
    content.empty:SetJustifyH("CENTER")
    content.empty:SetWordWrap(true)
    content.empty:Hide()
    content:SetScript("OnShow", function() UI.Refresh() end)
    return content
end

local function Row(i)
    local Th = ns.Theme
    local r = rows[i]
    if r then return r end
    r = CreateFrame("Frame", nil, content.list)
    r:SetHeight(ROW_H)
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetTexture(SOLID)
    r.bg:SetAllPoints()
    r.bg:SetVertexColor(1, 1, 1, 0.035)
    -- hover: an accent wash, an accent left edge, the name in the accent, and the tooltip
    r.hover = r:CreateTexture(nil, "BORDER")
    r.hover:SetTexture(SOLID)
    r.hover:SetAllPoints()
    Th.Paint({ tex = r.hover, a = 0.10 })
    r.hover:Hide()
    r.edge = r:CreateTexture(nil, "ARTWORK")
    r.edge:SetTexture(SOLID)
    r.edge:SetWidth(3)
    r.edge:SetPoint("TOPLEFT", 0, 0)
    r.edge:SetPoint("BOTTOMLEFT", 0, 0)
    Th.Paint({ tex = r.edge, a = 1 })
    r.edge:Hide()
    r:EnableMouse(true)
    r:SetScript("OnEnter", function(self) UI.Hover(self, true) end)
    r:SetScript("OnLeave", function(self) UI.Hover(self, false) end)
    r.iconFrame = CreateFrame("Frame", nil, r)
    r.iconFrame:SetSize(30, 30)
    r.iconFrame:SetPoint("LEFT", 10, 0)
    r.icon = r.iconFrame:CreateTexture(nil, "ARTWORK")
    r.icon:SetAllPoints()
    r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    r.iconBorder = ns.CreateBorder(r.iconFrame)
    r.iconBorder:Layout(r.iconFrame, 1, 0)
    r.iconBorder:SetColor(0, 0, 0, 0.9)
    r.iconBorder:Show()
    r.name = Th.MakeText(r, 13, Th.TEXT)
    r.name:SetPoint("TOPLEFT", r.iconFrame, "TOPRIGHT", 8, -1)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.cost = Th.MakeText(r, 13, Th.TEXT_DIM)
    r.cost:SetPoint("TOPRIGHT", r, "TOPRIGHT", -12, -6)
    r.cost:SetJustifyH("RIGHT")
    r.name:SetPoint("RIGHT", r.cost, "LEFT", -8, 0)
    r.req = Th.MakeText(r, 11, Th.TEXT_MUTE)
    r.req:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -2)
    r.req:SetPoint("RIGHT", r, "RIGHT", -12, 0)
    r.req:SetJustifyH("LEFT")
    r.req:SetWordWrap(false)
    r.head = Th.MakeText(r, 14, Th.TEXT)
    Th.SetDisplay(r.head, 14)
    r.head:SetPoint("LEFT", 12, 0)
    r.head:SetPoint("RIGHT", -12, 0)
    r.head:SetJustifyH("LEFT")
    r.headRule = r:CreateTexture(nil, "ARTWORK")
    r.headRule:SetTexture(SOLID)
    r.headRule:SetHeight(1)
    r.headRule:SetPoint("BOTTOMLEFT", 10, 0)
    r.headRule:SetPoint("BOTTOMRIGHT", -10, 0)
    r.headRule:SetVertexColor(1, 1, 1, 0.1)
    rows[i] = r
    return r
end

--- Drop the tooltip if this row owns it (a refresh under the cursor
-- re-pools the row; the list hiding takes its tooltip along).
local function DropTip(r)
    local tt = rawget(_G, "GameTooltip")
    if tt and tt.GetOwner and tt:GetOwner() == r then tt:Hide() end
end

local function Reset(r)
    r.iconFrame:Hide(); r.name:Hide(); r.cost:Hide(); r.req:Hide(); r.head:Hide(); r.headRule:Hide(); r.bg:Hide()
    r.hover:Hide(); r.edge:Hide(); r.hot = false; r.entry = nil
    DropTip(r)
    r:Show()
end

--- The tooltip for an entry is the spell's own (its description), by the
-- id the capture holds. Cost and requirements are already on the row, so
-- they are not repeated (Alex). Without an id, just the name.
local function Tooltip(r, e)
    local tt = rawget(_G, "GameTooltip")
    if not tt or not e then return end
    tt:SetOwner(r, "ANCHOR_RIGHT")
    if e.spell then
        pcall(tt.SetSpellByID, tt, e.spell)
    else
        tt:AddLine(e.name .. ((e.rank and e.rank ~= "") and (" (" .. e.rank .. ")") or ""), 1, 1, 1)
    end
    tt:Show()
end

--- Hover in / out on an entry row (headers ignore it).
function UI.Hover(r, on)
    local Th = ns.Theme
    -- leaving always cleans up, even when a refresh cleared the entry
    -- meanwhile (hunt 10: the tooltip and the accent name stayed)
    if not on then
        r.hot = false
        r.hover:Hide()
        r.edge:Hide()
        r.name:SetTextColor(Th.TEXT[1], Th.TEXT[2], Th.TEXT[3], 1)
        r.iconBorder:SetColor(0, 0, 0, 0.9)
        DropTip(r)
        return
    end
    if not r.entry then return end
    r.hot = true
    r.hover:Show()
    r.edge:Show()
    local rr, g, b = Th.Accent()
    r.name:SetTextColor(rr, g, b, 1)
    r.iconBorder:SetColor(rr, g, b, 1)
    Tooltip(r, r.entry)
end

local function ShowHead(r, text)
    Reset(r)
    r:SetHeight(HEAD_H + 8)
    local rr, g, b = ns.Theme.Accent()
    r.head:SetTextColor(rr, g, b, 1)
    r.head:SetText(ns.Theme.Upper(text))
    r.head:Show(); r.headRule:Show()
end

local function ShowEntry(r, e, stripe)
    local Th = ns.Theme
    Reset(r)
    r.entry = e
    r:SetHeight(ROW_H)
    r.bg:SetShown(stripe)
    if e.icon then r.icon:SetTexture(e.icon) else r.icon:SetTexture(nil) end
    r.iconFrame:Show()
    r.name:SetText(e.name .. ((e.rank and e.rank ~= "") and ("  |cff9a9aa4(" .. e.rank .. ")|r") or ""))
    r.name:SetTextColor(Th.TEXT[1], Th.TEXT[2], Th.TEXT[3], 1)
    r.name:Show()
    r.cost:SetText(e.cost and T().Money(e.cost) or "")
    r.cost:Show()
    local parts = {}
    local okL, lvl = pcall(UnitLevel, "player")
    if e.level then
        local met = okL and type(lvl) == "number" and lvl >= e.level
        parts[#parts + 1] = (met and "" or RED) .. "Level " .. e.level .. (met and "" or "|r")
    end
    local missing = {}
    for _, m in ipairs(e.missing or {}) do missing[m] = true end
    for _, req in ipairs(e.req or {}) do
        parts[#parts + 1] = (missing[req] and RED or "") .. req .. (missing[req] and "|r" or "")
    end
    r.req:SetText(#parts > 0 and ("Requires: " .. table.concat(parts, ", ")) or "")
    r.req:Show()
end

--- The spellbook's search text, lower-cased; nil when empty.
local function SearchText()
    local box = host.book and rawget(host.book, "SearchBox")
    if type(box) ~= "table" or not box.GetText then return nil end
    local ok, t = pcall(box.GetText, box)
    t = ok and ns.Str(t)
    t = t and t:gsub("^%s+", ""):gsub("%s+$", ""):lower()
    return t ~= "" and t or nil
end

--- Redraw the list from the current status.
function UI.Refresh()
    if not content or not content:IsShown() then return end
    content.FitList()
    local st = T().Status()
    local used, y = 0, 0
    local function place(r)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", content.list, "TOPLEFT", 0, -y)
        r:SetPoint("RIGHT", content.list, "RIGHT", 0, 0)
        y = y + r:GetHeight()
    end
    if not st then
        for _, r in ipairs(rows) do r:Hide() end
        content.empty:SetText("No trainer list for this class yet. Open a class trainer once and it is captured.")
        content.empty:Show()
        content.list:SetHeight(10)
        return
    end
    content.empty:Hide()
    -- the spellbook's search box filters by spell name while our page shows
    local q = SearchText()
    local function Match(list)
        if not q then return list end
        local out = {}
        for _, e in ipairs(list) do
            if type(e.name) == "string" and e.name:lower():find(q, 1, true) then out[#out + 1] = e end
        end
        return out
    end
    -- a group with nothing in it shows no header (Alex)
    for _, g in ipairs({ { "Available", Match(st.now) }, { "Unavailable", Match(st.later) } }) do
        local title, list = g[1], g[2]
        if #list > 0 then
            used = used + 1
            local r = Row(used)
            ShowHead(r, title)
            place(r)
            for i, e in ipairs(list) do
                used = used + 1
                local er = Row(used)
                ShowEntry(er, e, i % 2 == 1)
                place(er)
            end
        end
    end
    for i = used + 1, #rows do Reset(rows[i]) rows[i]:Hide() end     -- no stale entry/hover/tooltip on a ghost row
    if q and used == 0 then
        content.empty:SetText("No unlearned spell matches the search.")
        content.empty:Show()
    end
    content.list:SetHeight(math.max(10, y))
end
-- a refresh (level up, spells changed) can add a category tab: re-place
ns.Trainer.Refresh = function() UI.Refresh() if tab then PlaceTab() tab:Update() end end
function UI.Rows() return rows end                      -- test seam

-- ------------------------------------------------------------ the tab

local hidPage = false

-- Blizzard's selected tab keeps its gold frame when ours is clicked (their
-- tab system does not know about us), so two tabs read as selected. While
-- ours is active their selected pieces (SquareBackgroundActive and its
-- glow, measured with /sn probe spellbook) are hidden; a Blizzard tab
-- click or the book closing puts them back.
local dimmed = {}
local dimmedTab, dimmedWasDisabled          -- their selected tab while ours shows

local function DimTheirs()
    if not host.tabs then return end
    for _, k in ipairs({ host.tabs:GetChildren() }) do
        if k ~= tab then
            for _, key in ipairs({ "SquareBackgroundActive", "SquareBackgroundActiveGlow" }) do
                local tex = rawget(k, key)
                if type(tex) == "table" and tex.IsShown and tex:IsShown() then
                    tex:Hide()
                    dimmed[#dimmed + 1] = tex
                    dimmedTab = k
                end
            end
        end
    end
    -- their tab system disables the selected tab, so a click on it would
    -- do nothing (Alex: "clicking back on that tab doesn't do anything");
    -- while ours shows it must answer a click
    if dimmedTab and dimmedTab.IsEnabled and not dimmedTab:IsEnabled() and dimmedTab.Enable then
        dimmedTab:Enable()
        dimmedWasDisabled = true
    end
end

-- `restore` re-shows what was hidden and re-disables that tab (the book
-- closed, ours toggled off, or that same tab was clicked); a click on
-- another Blizzard tab has already moved their selection, so then the
-- hidden pieces are simply forgotten.
local function UndimTheirs(restore)
    if restore then
        for _, tex in ipairs(dimmed) do tex:Show() end
        if dimmedWasDisabled and dimmedTab and dimmedTab.Disable then dimmedTab:Disable() end
    end
    dimmed = {}
    dimmedTab, dimmedWasDisabled = nil, nil
end

local function ShowOurs()
    if not content then return end
    if host.page and host.page:IsShown() then host.page:Hide() hidPage = true end
    if host.book and type(host.book.HidePreviewResultSearch) == "function" then pcall(host.book.HidePreviewResultSearch, host.book) end
    Layer()
    content:Show()
    DimTheirs()
    tab.active = true
    tab:Update()
end

-- `clicked` is the Blizzard tab that was clicked, nil for the book
-- closing or ours toggling off. Their selection moved only when a
-- DIFFERENT tab than the dimmed one was clicked.
local function ShowTheirs(clicked)
    if content then
        for _, r in ipairs(rows) do DropTip(r) end
        content:Hide()
    end
    if hidPage and host.page then host.page:Show() end
    hidPage = false
    UndimTheirs(clicked == nil or clicked == dimmedTab)
    if tab then tab.active = false tab:Update() end
end
UI.ShowOurs, UI.ShowTheirs = ShowOurs, ShowTheirs       -- test seams

--- Find the spellbook's pieces. Retail: PlayerSpellsFrame.SpellBookFrame
-- { CategoryTabSystem, PagedSpellsFrame }. Nil where the client differs.
local function FindHost()
    local psf = rawget(_G, "PlayerSpellsFrame")
    local sbf = type(psf) == "table" and psf.SpellBookFrame or rawget(_G, "SpellBookFrame")
    if type(sbf) ~= "table" then return nil end
    host.book = sbf
    host.top = type(psf) == "table" and psf or sbf          -- the window that opens and closes
    host.tabs = type(sbf.CategoryTabSystem) == "table" and sbf.CategoryTabSystem or nil
    host.page = type(sbf.PagedSpellsFrame) == "table" and sbf.PagedSpellsFrame or nil
    return host
end

--- The last of Blizzard's tab buttons (the rightmost), and its size.
local function LastTab()
    local tabs = host.tabs
    if not tabs then return nil end
    local last, w, h
    local kids = { tabs:GetChildren() }
    for _, k in ipairs(kids) do
        if k ~= tab and k.IsShown and k:IsShown() and k.GetObjectType and k:GetObjectType() == "Button" then
            if not last or (k:GetLeft() or 0) > (last:GetLeft() or 0) then last = k end
        end
    end
    if last then w, h = last:GetWidth(), last:GetHeight() end
    return last, w or 40, h or 40
end

local hooked = {}

--- Anchor our tab after the rightmost Blizzard tab and hook those tabs.
-- Runs at build AND every time the book shows: after a /reload the book
-- has not been laid out yet (its tab buttons have no rect, or do not exist
-- until the first show), so the build-time placement is a guess that the
-- first show corrects.
function PlaceTab()
    if not tab then return end
    local last, w, h = LastTab()
    tab:SetSize(w, h)
    tab:ClearAllPoints()
    if last then tab:SetPoint("LEFT", last, "RIGHT", 1, 0)         -- Blizzard's tabs sit 1px apart (measured)
    else tab:SetPoint("TOPLEFT", host.book, "TOPLEFT", 12, -8) end
    tab.placed = last ~= nil
    if host.tabs then
        for _, k in ipairs({ host.tabs:GetChildren() }) do
            if k ~= tab and not hooked[k] and k.HookScript and k.GetObjectType and k:GetObjectType() == "Button" then
                hooked[k] = true
                k:HookScript("OnClick", function(self) ShowTheirs(self) end)
            end
        end
    end
end
UI.PlaceTab = PlaceTab

local function BuildTab()
    if tab or not host.book then return tab end
    local Th = ns.Theme
    tab = CreateFrame("Button", "SalusNovusTrainerTabButton", host.tabs or host.book)
    -- Built like Blizzard's category tab (measured with /sn probe spellbook,
    -- 2026-09-23): a 44x32 button, the icon 36x35 centred (it overhangs the
    -- box), and for the selected tab a gold frame atlas 43x38 anchored
    -- BOTTOM (0,1) with a glow gradient atlas 43x38 at BOTTOM (0,0).
    -- .Icon, as on Blizzard's tabs: skins that restyle the tab row blank
    -- every texture but a tab's Icon (EllesmereUI's Blizzard skin, 2026-09-25)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.icon = tab.Icon
    tab.icon:SetTexture(TAB_ICON)
    tab.icon:SetSize(36, 35)
    tab.icon:SetPoint("CENTER", 0, 0)
    tab.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    tab.frame = tab:CreateTexture(nil, "ARTWORK", nil, 1)
    tab.frame:SetSize(43, 38)
    tab.frame:SetPoint("BOTTOM", 0, 1)
    tab.frame:SetAtlas(TAB_FRAME_ATLAS)
    tab.frame:Hide()
    tab.glowTex = tab:CreateTexture(nil, "ARTWORK", nil, -1)
    tab.glowTex:SetSize(43, 38)
    tab.glowTex:SetPoint("BOTTOM", 0, 0)
    tab.glowTex:SetAtlas(TAB_GLOW_ATLAS)
    tab.glowTex:Hide()
    -- a thin dark edge keeps the unselected tab readable on the parchment
    tab.border = ns.CreateBorder(tab)
    tab.border:Layout(tab, 1, 0)
    tab.border:SetColor(0, 0, 0, 0.6)
    tab.border:Show()
    tab.count = Th.MakeText(tab, 11, Th.TEXT)
    tab.count:SetPoint("BOTTOMRIGHT", -2, 2)
    tab.count:SetShadowColor(0, 0, 0, 1)
    tab.count:SetShadowOffset(1, -1)
    tab.hl = tab:CreateTexture(nil, "HIGHLIGHT")
    tab.hl:SetTexture(SOLID)
    tab.hl:SetAllPoints()
    tab.hl:SetVertexColor(1, 1, 1, 0.12)
    tab.active = false
    tab.Update = function(self)
        local st = T().Status()
        local n = st and #st.now or 0
        self.count:SetText(n > 0 and tostring(n) or "")
        -- active: Blizzard's own gold frame and glow, as on their selected tab
        self.frame:SetShown(self.active)
        self.glowTex:SetShown(self.active)
        if self.active then self.border:Hide() else self.border:Show() end
        self.icon:SetDesaturated(not self.active and n == 0)
    end
    -- like Blizzard's tabs: clicking ours again keeps ours (Alex); only
    -- their tabs or the book closing leave it
    tab:SetScript("OnClick", function() if not (content and content:IsShown()) then ShowOurs() end end)
    -- the whole window closing (or the book alone, where they differ) puts the page back;
    -- showing re-places the tab (Blizzard's tabs may only exist from the first show)
    for _, f in ipairs(host.top == host.book and { host.book } or { host.top, host.book }) do
        f:HookScript("OnHide", function() ShowTheirs(nil) end)
        f:HookScript("OnShow", function()
            if not tab then return end
            -- every show, and again next frame: Blizzard makes category
            -- tabs lazily (the warrior's second tab appeared after the
            -- first show and ours sat on top of it)
            PlaceTab()
            C_Timer.After(0, PlaceTab)
            tab:Update()
        end)
    end
    -- The search box: while our page shows, typing filters our list and
    -- Blizzard's preview (which would cover it) stays hidden. Enter still
    -- runs their full search behind our page; that clears their selected
    -- tab, so the one we dimmed is no longer theirs to restore.
    local book, box = host.book, rawget(host.book, "SearchBox")
    local function Ours() return content and content:IsShown() end
    if type(box) == "table" and box.HookScript then
        box:HookScript("OnTextChanged", function() if Ours() then UI.Refresh() end end)
    end
    if type(book.SetPreviewResultSearch) == "function" and type(book.HidePreviewResultSearch) == "function" then
        hooksecurefunc(book, "SetPreviewResultSearch", function(self) if Ours() then self:HidePreviewResultSearch() end end)
    end
    if type(book.SetFullResultSearch) == "function" then
        hooksecurefunc(book, "SetFullResultSearch", function() if Ours() then UndimTheirs(false) UI.Refresh() end end)
    end
    PlaceTab()
    tab:Update()
    UI.tab = tab
    return tab
end

local function TryAttach()
    if tab then return true end
    if not T().Enabled() then UI.why = "the setting is off" return false end
    if not FindHost() then UI.why = "no spellbook frame yet (PlayerSpellsFrame / SpellBookFrame)" return false end
    local ok, err = pcall(function()
        BuildContent(host.book, host.page)
        BuildTab()
    end)
    if not ok then UI.why = "build error: " .. ns.S(err) return false end
    UI.why = nil
    return true
end
UI.TryAttach = TryAttach

--- One line for /sn trainer: is the tab there, and if not, why.
function UI.Report()
    if tab then
        return ("spellbook tab: attached (%s, %s, %s)"):format(host.tabs and "tab row found" or "no tab row",
            tab.placed and "after the last Blizzard tab" or "at the fallback spot: no Blizzard tab button seen yet", host.page and "page found" or "no page")
    end
    return "spellbook tab: NOT attached -- " .. (UI.why or "never tried")
end

ns.On("ADDON_LOADED", function(name)
    if name == "Blizzard_PlayerSpells" or name == "Blizzard_SpellBook" then TryAttach() end
end)
ns.On("PLAYER_LOGIN", TryAttach)

ns.RegisterApply(function()
    local on = T().Enabled()
    if not tab and on then TryAttach() end
    if tab then
        tab:SetShown(on)
        if on then tab:Update() else ShowTheirs() end
    end
end, "Trainer")
