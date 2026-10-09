--[[ Salus Novus -- the wishlist window (/sn wish, or the sidebar launcher).

Laid out like the Boss Visualizer: a sidebar with a Mine / Party switch over
the dungeon list (multiselect rows, name and level range; opened on the
dungeons within 8 levels), and the content to the right. Mine: a slot filter
across the picked dungeons and a card per item you can equip, in two
columns: the item's own tooltip (exactly as on hover), and on a click its
spec and BIS/Upgrade tags (a right-click clears them). Party: dungeons ranked
by the group's wishes, by most wanted entries or by most party members.
]]

local _, ns = ...

local UI = {}
ns.WishlistUI = UI
local W = function() return ns.Wishlist end

local WIN_W, WIN_H, SIDEBAR_W, HEADER_H = 1000, 680, 250, 64     -- the least; Build sizes it to the screen
local PAD = 22
local ROW_H, ROW_H_TAGGED, CARD_GAP, ICON = 60, 94, 6, 40
local CARD_A, CARD_HOVER_A = 0.03, 0.09
local LINE_H, NAV_ROW_H = 22, 44
local SPAN = 8
local BIS_RED = "|cffff4040"
local QUALITY = { [0] = { 0.62, 0.62, 0.62 }, { 1, 1, 1 }, { 0.12, 1, 0 }, { 0, 0.44, 0.87 }, { 0.64, 0.21, 0.93 }, { 1, 0.5, 0 } }

local frame, shell
UI.pool, UI.slot, UI.view, UI.sort = {}, nil, "mine", "total"

local function T() return ns.Theme end

local function Chip(parent, text, size, onClick)
    local b = T().MakeButton(parent)
    b:SetText(text)
    T().SetDisplay(b.text, size or 11)
    b:SetHeight(size and size + 10 or 20)
    local w = (b.text.GetStringWidth and b.text:GetStringWidth() or 0)
    b:SetWidth(math.max(36, (tonumber(w) or 0) + 18))
    b:SetScript("OnClick", onClick)
    return b
end

--- Lay buttons out left to right, wrapping at maxW. Returns the height used.
local function Flow(buttons, parent, x0, y0, maxW, gap)
    local x, y, rowH = x0, y0, 0
    for _, b in ipairs(buttons) do
        local w, h = b:GetWidth() or 40, b:GetHeight() or 20
        if x > x0 and x + w > x0 + maxW then x = x0; y = y - rowH - gap; rowH = 0 end
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:Show()
        x = x + w + gap
        rowH = math.max(rowH, h)
    end
    return (y0 - y) + rowH
end

local function Label(parent, text)
    local l = T().MakeText(parent, 14, T().TEXT_MUTE)
    l:SetText(T().Upper(text))
    return l
end

local function Level()
    local ok, l = pcall(UnitLevel, "player")
    return ok and ns.Num(l) and l or 1
end

-- Segmented choice, as the visualizer's Dungeons / Raids switch.
local function MakeSegment(parent, label)
    local Th = T()
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    b.bg = Th.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.06)
    b.bg:SetAllPoints()
    b.text = Th.MakeText(b, 13, Th.TEXT_MUTE)
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    function b:SetActive(on)
        local r, g, bb = Th.Accent()
        if on then
            local tr, tg, tb = Th.OnAccent()
            self.bg:SetVertexColor(r, g, bb, 0.9); self.text:SetTextColor(tr, tg, tb, 1)
        else self.bg:SetVertexColor(1, 1, 1, 0.06); self.text:SetTextColor(Th.TEXT_MUTE[1], Th.TEXT_MUTE[2], Th.TEXT_MUTE[3], 1) end
        self.active = on
    end
    b:SetScript("OnEnter", function(self) if not self.active then self.bg:SetVertexColor(1, 1, 1, 0.12) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    b:SetActive(false)
    return b
end

-- ------------------------------------------------------------ build

local function MakeScroll(parent)
    local s = T().MakeScrollArea(parent)
    s.list = s.child
    s.list:SetHeight(10)
    local function Fit() s.list:SetWidth(math.max(1, s:GetWidth() or 0)) end
    s:SetScript("OnSizeChanged", Fit)
    s.Fit = Fit
    return s
end

local function Build()
    if frame then return frame end
    local Th = T()
    -- Tall as most of the screen (Alex: use the real estate); the width
    -- follows the three columns (UI.Fit)
    local sh = UIParent and UIParent:GetHeight()
    if ns.Num(sh) and sh > 0 then WIN_H = math.max(WIN_H, math.floor(sh * 0.94)) end
    shell = Th.MakeShell("SalusNovusWishlist", WIN_W, WIN_H, SIDEBAR_W, HEADER_H, "Wishlist")
    frame = shell.frame
    frame.shell = shell
    frame:SetFrameLevel(120)
    -- Opened from the settings sidebar, closing brings the settings back.
    frame:SetScript("OnHide", function()
        if ns.ReturnToOptions then ns.ReturnToOptions() end
    end)
    shell.subtitle:SetText("")

    -- Sidebar: Mine / Party, then the dungeons.
    frame.modeStrip = CreateFrame("Frame", nil, shell.side)
    frame.modeStrip:SetHeight(26)
    frame.modeStrip:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 12, -HEADER_H - 12)
    frame.modeStrip:SetPoint("TOPRIGHT", shell.side, "TOPRIGHT", -12, -HEADER_H - 12)
    frame.modeStrip.border = ns.CreateBorder(frame.modeStrip)
    frame.modeStrip.border:Layout(frame.modeStrip, 1, 0)
    frame.modeStrip.border:SetColor(1, 1, 1, 0.10)
    frame.modeStrip.border:Show()
    frame.modeButtons = {}
    for i, def in ipairs({ { "mine", "Mine" }, { "party", "Party" } }) do
        local b = MakeSegment(frame.modeStrip, def[2])
        b:SetPoint("TOPLEFT", frame.modeStrip, "TOPLEFT", (i - 1) * ((SIDEBAR_W - 24) / 2), 0)
        b:SetWidth((SIDEBAR_W - 24) / 2)
        b.view = def[1]
        b:SetScript("OnClick", function() UI.view = def[1] UI.Refresh() end)
        frame.modeButtons[i] = b
    end
    frame.tabMine, frame.tabParty = frame.modeButtons[1], frame.modeButtons[2]

    frame.dungeonList = Th.MakeScrollArea(shell.side)
    frame.dungeonList:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 0, -HEADER_H - 48)
    frame.dungeonList:SetPoint("BOTTOMRIGHT", shell.side, "BOTTOMRIGHT", -10, 12)
    frame.dungeonList.child:SetWidth(SIDEBAR_W - 10)
    frame.dungeonRows = {}

    local content = shell.content

    -- Mine
    local mine = CreateFrame("Frame", nil, content)
    mine:SetPoint("TOPLEFT", PAD, -14)
    mine:SetPoint("BOTTOMRIGHT", -PAD, 12)
    frame.mine = mine
    mine.title = Th.MakeText(mine, 24, Th.TEXT)
    mine.title:SetPoint("TOPLEFT", 0, 0)
    mine.slotLabel = Label(mine, "Slot")
    mine.slotButtons = {}
    mine.scroll = MakeScroll(mine)
    mine.rows = {}
    mine.empty = Th.MakeText(mine, 15, Th.TEXT_MUTE)
    mine.empty:SetWordWrap(true)
    mine.empty:SetJustifyH("LEFT")

    -- Party
    local party = CreateFrame("Frame", nil, content)
    party:SetPoint("TOPLEFT", PAD, -14)
    party:SetPoint("BOTTOMRIGHT", -PAD, 12)
    frame.party = party
    party.byTotal = Chip(party, "Most wanted", 16, function() UI.sort = "total" UI.Refresh() end)
    party.byTotal:SetPoint("TOPLEFT", 0, 0)
    party.byPeople = Chip(party, "Most party members", 16, function() UI.sort = "people" UI.Refresh() end)
    party.byPeople:SetPoint("LEFT", party.byTotal, "RIGHT", 4, 0)
    party.scroll = MakeScroll(party)
    party.scroll:SetPoint("TOPLEFT", 0, -42)
    party.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    party.lines, party.cards = {}, {}
    party.empty = Th.MakeText(party, 15, Th.TEXT_MUTE)
    party.empty:SetPoint("TOPLEFT", 0, -48)
    party.empty:SetPoint("RIGHT", party, "RIGHT", 0, 0)
    party.empty:SetWordWrap(true)
    party.empty:SetJustifyH("LEFT")

    frame:SetScript("OnShow", function() UI.Refresh() end)
    return frame
end
UI.Build = Build

-- ------------------------------------------------------------ sidebar

local function DungeonRow(i)
    local r = frame.dungeonRows[i]
    if r then return r end
    local Th = T()
    r = CreateFrame("Button", nil, frame.dungeonList.child)
    r:SetSize(SIDEBAR_W - 10, NAV_ROW_H)
    for _, part in ipairs(Th.DecorateNavRow(r)) do shell:Register(part) end
    Th.NavLabel(r, "")
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 22, -5)
    r.label:SetPoint("RIGHT", r, "RIGHT", -44, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.sub = Th.MakeText(r, 12, Th.TEXT_MUTE)
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -2)
    r.sub:SetWordWrap(false)
    r.count = Th.MakeText(r, 13, Th.TEXT_MUTE)
    r.count:SetPoint("RIGHT", r, "RIGHT", -20, 0)
    r:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    -- Picked rows are accent blocks; their small lines follow the label's
    -- dark text, or they vanish into the accent.
    function r.SetPicked(on)
        Th.SetNavActive(r, on)
        local c = on and { Th.OnAccent() } or Th.TEXT_MUTE
        r.sub:SetTextColor(c[1], c[2], c[3], on and 0.8 or 1)
        r.count:SetTextColor(c[1], c[2], c[3], 1)
    end
    r:SetScript("OnLeave", function(self) self.SetPicked(UI.pool[self.key] and true or false) end)
    r:SetScript("OnClick", function(self)
        UI.pool[self.key] = not UI.pool[self.key] or nil
        W().SavePool(UI.pool)
        UI.Refresh()
    end)
    frame.dungeonRows[i] = r
    return r
end

-- Wishes per dungeon (by name, as the catalog files its sources).
local function WishCounts()
    local n, cat = {}, W().catalog
    for _, id in ipairs(W().Shared()) do                  -- (an owned one's hidden flag isn't counted)
        local src = cat and cat.source[id]
        if src then n[src.dungeon] = (n[src.dungeon] or 0) + 1 end
    end
    return n
end

local function DrawSidebar()
    local Th = T()
    for _, b in ipairs(frame.modeButtons) do b:SetActive(b.view == UI.view) end
    local cat = W().catalog
    local counts = WishCounts()
    local y = 0
    local list = cat and cat.dungeons or {}
    for i, d in ipairs(list) do
        local r = DungeonRow(i)
        r.key = d.key
        -- "Scarlet Monastery - Graveyard": the wing alone is the name (the
        -- full one was cut off); the level line is just the levels.
        local wing = d.name:match("^.-%s+%-%s+(.+)$")
        r.label:SetText(wing or d.name)
        r.sub:SetText(("Level %d-%d"):format(d.range[2], d.range[3]))
        r.count:SetText(counts[d.name] and tostring(counts[d.name]) or "")
        r.SetPicked(UI.pool[d.key] and true or false)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame.dungeonList.child, "TOPLEFT", 0, -y)
        r:Show()
        y = y + NAV_ROW_H
    end
    for i = #list + 1, #frame.dungeonRows do frame.dungeonRows[i]:Hide() frame.dungeonRows[i].key = nil end
    frame.dungeonList.child:SetHeight(math.max(1, y))
end

-- Scroll the list to the first picked dungeon, or with nothing picked to
-- the first one near your level (the list is long; level 40 starts mid-way).
local function ScrollToPool()
    local cat = W().catalog
    local near = {}
    for _, key in ipairs(W().NearDungeons(Level(), SPAN)) do near[key] = true end
    local target
    for i, d in ipairs(cat and cat.dungeons or {}) do
        if UI.pool[d.key] then target = i break end
        if not target and near[d.key] and not next(UI.pool) then target = i end
    end
    if target then
        local sf = frame.dungeonList
        if sf.SetVerticalScroll then pcall(sf.SetVerticalScroll, sf, (target - 1) * NAV_ROW_H) end
    end
end

-- ------------------------------------------------------------ rows

-- An item card, shared by both tabs: square icon (Blizzard's rounded rim
-- cropped off) on a crisp black frame, the item's real tooltip beside it --
-- a GameTooltip of its own, so it reads exactly as on hover (Alex: not split
-- into columns) -- and a line under it (where it drops, who wants it).
local tipN = 0
local function ItemCard(parent)
    local Th = T()
    local r = CreateFrame("Button", nil, parent)
    r:SetHeight(ROW_H)
    r.bg = Th.SolidTex(r, "BACKGROUND", 1, 1, 1, CARD_A)
    r.bg:SetAllPoints()
    r.border = ns.CreateBorder(r)
    r.border:Layout(r, 1, -1)       -- inside the card: the scroll frame clips anything outside
    r.border:SetColor(1, 1, 1, 0.06)
    r.border:Show()
    r.iconEdge = Th.SolidTex(r, "ARTWORK", 0, 0, 0, 1, 0)
    r.iconEdge:SetSize(ICON + 2, ICON + 2)
    r.iconEdge:SetPoint("TOPLEFT", 9, -9)
    r.iconTex = r:CreateTexture(nil, "ARTWORK", nil, 1)
    r.iconTex:SetSize(ICON, ICON)
    r.iconTex:SetPoint("CENTER", r.iconEdge, "CENTER", 0, 0)
    r.iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tipN = tipN + 1
    r.tip = CreateFrame("GameTooltip", "SalusNovusWishTip" .. tipN, r, "GameTooltipTemplate")
    r.sub = Th.MakeText(r, 13, Th.TEXT_MUTE)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(true)
    -- hovered: the accent, kept through redraws (a redraw repainted it at
    -- rest the next frame -- the blue only flashed: Alex)
    r:SetScript("OnEnter", function(self) self.hover = true self.Rest() end)
    r:SetScript("OnLeave", function(self) self.hover = false self.Rest() end)
    --- At rest: an owned item's card is green (Alex) -- a light green
    -- ground, a dark green edge; the rest plain
    function r.Rest()
        if r.hover then
            r.bg:SetVertexColor(1, 1, 1, CARD_HOVER_A)
            local ar, ag, ab = Th.Accent()
            r.border:SetColor(ar, ag, ab, 0.9)
        elseif r.owned then
            r.bg:SetVertexColor(0.31, 0.82, 0.37, 0.10)
            r.border:SetColor(0.12, 0.45, 0.16, 1)
        elseif r.wanted then
            r.bg:SetVertexColor(0.91, 0.42, 0.37, 0.10)
            r.border:SetColor(0.50, 0.14, 0.12, 1)
        else
            r.bg:SetVertexColor(1, 1, 1, CARD_A)
            r.border:SetColor(1, 1, 1, 0.06)
        end
    end
    return r
end

--- Show the card's item in its own tooltip, inside the card (in the card's
-- strata, so the scroll clips it); returns its height (0 until the item is
-- in the cache -- the card fills in when it arrives).
local function FillTip(r)
    local tip = r.tip
    if not (tip and r.id) then return 0 end
    pcall(tip.SetOwner, tip, r, "ANCHOR_NONE")
    pcall(tip.SetClampedToScreen, tip, false)      -- with its card, not pushed on screen over the others
    pcall(tip.SetItemByID, tip, r.id)
    tip:ClearAllPoints()
    tip:SetPoint("TOPLEFT", r.iconEdge, "TOPRIGHT", 8, 1)
    pcall(tip.SetFrameStrata, tip, r:GetFrameStrata())
    pcall(tip.SetFrameLevel, tip, (r:GetFrameLevel() or 0) + 2)
    tip:Show()
    local h = tonumber(tip:GetHeight()) or 0
    -- not in the cache yet: its arrival redraws (only then -- every item
    -- answer redrew the window, and the redraw asked again: a loop)
    if h <= 0 or not W().Info(r.id) then UI.waiting[r.id] = true end
    return h > 0 and h or 0
end
UI.FillTip = FillTip
UI.waiting = {}

--- Fill a card's icon and item; the name is the tooltip's first line.
local function FillCard(r, id, info)
    r.id = id
    info = info or W().Info(id)
    r.iconTex:SetTexture(info and info.icon or 134400)
end

--- Lay a card out: tooltip, the line under it (when it has one), and
-- (Mine, opened) the chips; returns its height.
local function LayoutCard(r, width, chips)
    local tipH = FillTip(r)
    -- a column narrowed to fit the screen: the tooltip shrinks with it (it
    -- spilled over the next card: the sweep)
    if r.tip then
        local tw, avail = tonumber(r.tip:GetWidth()) or 0, width - 77
        local sc = (tw > 0 and tw > avail and avail > 0) and avail / tw or 1
        pcall(r.tip.SetScale, r.tip, sc)
        tipH = tipH * sc
    end
    local top = 9 + math.max(ICON + 2, tipH)
    local h = top + 9
    local text = r.sub:GetText()
    r.sub:SetShown(text ~= nil and text ~= "")
    if r.sub:IsShown() then
        r.sub:ClearAllPoints()
        r.sub:SetPoint("TOPLEFT", r, "TOPLEFT", 9, -(top + 6))
        r.sub:SetWidth(math.max(80, width - 18))
        local subH = tonumber(r.sub:GetStringHeight()) or 0
        if subH <= 0 then subH = 14 end
        h = top + 6 + subH + 9
    end
    -- Opened, the buttons come in over the card's foot -- the card keeps its
    -- size, so nothing below it moves (Alex)
    local bar = r.chipBar
    if bar then
        if chips and #chips > 0 then
            bar:SetWidth(width - 2)
            local fh = Flow(chips, bar, 8, -8, width - 18, 6)
            bar:SetHeight(fh + 16)
            bar:ClearAllPoints()
            bar:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 1, 1)
            bar:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -1, 1)
            bar:Show()
        else
            bar:Hide()
        end
    end
    return h
end

local function ItemRow(i)
    local m = frame.mine
    local r = m.rows[i]
    if r then return r end
    -- Mine (Alex): a click opens the card's spec / BIS / Upgrade buttons and a
    -- second click folds them away, picks kept; a right-click clears them all.
    r = ItemCard(m.scroll.list)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        if not self.id then return end
        if button == "RightButton" then
            if W().Get(self.id) then W().Wish(self.id, false) end
            return
        end
        -- something you own isn't flagged at all (Alex): no buttons
        if W().Owned(self.id) then UI.open[self.id] = nil return end
        UI.open[self.id] = not UI.open[self.id] or nil
        UI.Refresh()
    end)
    r.chips = {}
    -- the strip the buttons come in on: solid, over the tooltip
    r.chipBar = CreateFrame("Frame", nil, r)
    r.chipBar:SetFrameLevel((r:GetFrameLevel() or 0) + 8)
    r.chipBar.bg = T().SolidTex(r.chipBar, "BACKGROUND", T().BG[1], T().BG[2], T().BG[3], 0.96)
    r.chipBar.bg:SetAllPoints()
    r.chipBar.line = T().SolidTex(r.chipBar, "ARTWORK", 1, 1, 1, 0.10)
    r.chipBar.line:SetHeight(1)
    r.chipBar.line:SetPoint("TOPLEFT")
    r.chipBar.line:SetPoint("TOPRIGHT")
    r.chipBar:Hide()
    m.rows[i] = r
    return r
end
UI.open = {}

--- The card's spec / BIS / Upgrade chips (shown when the card is open); a
-- click on an item not yet wished wishes it. Returns the shown chips.
local function RowChips(r, e, rec)
    for _, c in ipairs(r.chips) do c:Hide() end
    if not UI.open[e.id] or r.owned then return {} end
    rec = rec or {}
    local shown = {}
    local labels = {}
    for _, s in ipairs(W().MySpecs()) do labels[#labels + 1] = { "spec", s } end
    labels[#labels + 1] = { "tag", "bis", "BIS" }
    labels[#labels + 1] = { "tag", "up", "Upgrade" }
    for i, l in ipairs(labels) do
        local c = r.chips[i]
        if not c then
            c = Chip(r.chipBar or r, l[3] or l[2], 15, nil)
            r.chips[i] = c
        end
        c:SetText(l[3] or l[2])
        T().SetDisplay(c.text, 15)
        c:SetWidth(math.max(44, (tonumber(c.text:GetStringWidth()) or 0) + 22))
        c:SetHeight(26)
        local on = (l[1] == "spec" and rec.spec and rec.spec[l[2]]) or (l[1] == "tag" and rec.tag == l[2])
        if c.SetPrimary then c:SetPrimary(on and true or false) end
        c:SetScript("OnClick", function()
            if not W().Get(e.id) then W().Wish(e.id, true) end
            if l[1] == "spec" then W().ToggleSpec(e.id, l[2]) else W().SetTag(e.id, l[2]) end
        end)
        shown[#shown + 1] = c
    end
    return shown
end

--- What you picked for an item, for its line while the chips are folded.
local function Picks(rec)
    if not rec then return nil end
    local out = {}
    for _, s in ipairs(W().MySpecs()) do if rec.spec and rec.spec[s] then out[#out + 1] = s end end
    if rec.tag == "bis" then out[#out + 1] = BIS_RED .. "BIS|r" elseif rec.tag == "up" then out[#out + 1] = "Upgrade" end
    return #out > 0 and table.concat(out, ", ") or nil            -- never just "Wished" (Alex)
end

--- Three columns (Alex), each as wide as the widest tooltip shown: every
-- card goes under the shortest column, and the window fits the three snugly.
local COLS, TIP_W, SCROLLBAR = 3, 250, 12
--- The widest tooltip seen this session (never below TIP_W): the window
-- only ever grows, so a slot filter with narrow items doesn't jump it about
-- (Alex: "some slot selections are causing the window to resize").
UI.tipW = TIP_W
local function ColumnWidth(cards)
    for _, r in ipairs(cards) do
        FillTip(r)
        local tw = tonumber(r.tip:GetWidth()) or 0
        if tw > UI.tipW then UI.tipW = math.ceil(tw) end
    end
    return UI.tipW + 9 + ICON + 2 + 8 + 9
end
local function Chrome() return SIDEBAR_W + 1 + 2 * PAD + (COLS - 1) * CARD_GAP + 6 + SCROLLBAR end
--- The window fits the columns, but never past the screen: there the columns
-- give (returns the width they get).
function UI.Fit(colW)
    if not frame then return colW end
    local sw = UIParent and tonumber(UIParent:GetWidth()) or nil
    if sw and sw > 0 and Chrome() + COLS * colW > sw - 20 then colW = math.floor((sw - 20 - Chrome()) / COLS) end
    frame:SetWidth(math.max(WIN_W, Chrome() + COLS * colW))
    return colW
end
local function Place(r, list, colY, colW, h)
    local c = 1
    for k = 2, COLS do if colY[k] < colY[c] then c = k end end
    r:SetWidth(colW)
    r:SetHeight(h)
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", list, "TOPLEFT", (c - 1) * (colW + CARD_GAP), -colY[c])
    r:Show()
    colY[c] = colY[c] + h + CARD_GAP
end

local function DrawMine()
    local m = frame.mine
    -- The cards first: their tooltips size the window, and the slot buttons
    -- wrap to the width it ends up (they spilled past the edge when the
    -- window resized after them).
    local list, pending = W().Browse(UI.pool, UI.slot)
    for _, id in ipairs(pending or {}) do UI.waiting[id] = true end   -- (their answers show them: the sweep)
    table.sort(list, function(a, b)
        if a.info.req ~= b.info.req then return a.info.req < b.info.req end
        return a.info.name < b.info.name
    end)
    local cards = {}
    for i, e in ipairs(list) do
        local r = ItemRow(i)
        FillCard(r, e.id, e.info)
        cards[i] = r
    end
    local colW = UI.Fit(ColumnWidth(cards))
    local width = (frame:GetWidth() or WIN_W) - SIDEBAR_W - 1 - 2 * PAD
    local picked = 0
    for _ in pairs(UI.pool) do picked = picked + 1 end
    -- slots
    local slots = { "All" }
    for _, s in ipairs(W().SLOT_ORDER) do slots[#slots + 1] = s end
    local y = -42
    m.slotLabel:ClearAllPoints()
    m.slotLabel:SetPoint("TOPLEFT", 0, y)
    y = y - 22
    local sb = {}
    for i, s in ipairs(slots) do
        local b = m.slotButtons[i]
        if not b then b = Chip(m, s, 16, nil) m.slotButtons[i] = b end
        b.slot = s ~= "All" and s or nil
        b:SetScript("OnClick", function(self) UI.slot = self.slot UI.Refresh() end)
        if b.SetPrimary then b:SetPrimary(UI.slot == b.slot) end
        sb[#sb + 1] = b
    end
    y = y - Flow(sb, m, 0, y, width, 4) - 12
    m.scroll:ClearAllPoints()
    m.scroll:SetPoint("TOPLEFT", 0, y)
    m.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    m.scroll.Fit()
    -- rows
    m.title:SetText(UI.slot or "All slots")
    local colY = { 0, 0, 0 }
    for i, e in ipairs(list) do
        local r = cards[i]
        -- No source line (Alex: the tooltip says enough); folded, what you
        -- picked -- the one sign it's wished, with no check box.
        local rec = W().Get(e.id)
        local picks = Picks(rec)                        -- open or folded: the same line, the same height
        local parts = {}
        r.owned = W().Owned(e.id) and true or false
        -- wanted and not had: red, as owned is green (Alex)
        r.wanted = not r.owned and W().Complete(rec)
        if r.owned then parts[#parts + 1] = "|cff4fd05fOWNED|r" end
        r.Rest()
        if picks and not r.owned then parts[#parts + 1] = (r.wanted and "|cffe86a5f" or "|cffd8d6e0") .. picks .. "|r" end
        r.sub:SetText(table.concat(parts, "  ·  "))
        r.wished = rec ~= nil
        local chips = RowChips(r, e, rec)
        Place(r, m.scroll.list, colY, colW, LayoutCard(r, colW, chips))
    end
    for i = #list + 1, #m.rows do m.rows[i]:Hide() m.rows[i].id = nil end
    m.scroll.list:SetHeight(math.max(10, math.max(colY[1], colY[2], colY[3])))
    m.empty:ClearAllPoints()
    m.empty:SetPoint("TOPLEFT", m.scroll, "TOPLEFT", 0, -6)
    m.empty:SetPoint("RIGHT", m, "RIGHT", 0, 0)
    if #list == 0 then
        m.empty:SetText(picked > 0 and "Nothing you can equip drops in these dungeons for this slot." or "Pick dungeons on the left.")
        m.empty:Show()
    else
        m.empty:Hide()
    end
    m.count = #list
end

local function PartyHeading(i)
    local p = frame.party
    local l = p.lines[i]
    if l then return l end
    l = T().MakeText(p.scroll.list, 18, T().TEXT)
    T().SetDisplay(l, 18)
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    p.lines[i] = l
    return l
end

local function PartyCard(i)
    local p = frame.party
    p.cards[i] = p.cards[i] or ItemCard(p.scroll.list)
    return p.cards[i]
end

--- A name in its class colour (white when the class is unknown).
local function ClassName(player, class)
    local r, g, b = 1, 1, 1
    local cc = class and C_ClassColor and C_ClassColor.GetClassColor
    local ok, c = false, nil
    if cc then ok, c = pcall(cc, class) end
    if ok and type(c) == "table" and not (ns.IsSecret and ns.IsSecret(c)) and ns.Num(c.r) and ns.Num(c.g) and ns.Num(c.b) then
        r, g, b = c.r, c.g, c.b
    else
        local rc = class and rawget(_G, "RAID_CLASS_COLORS") and RAID_CLASS_COLORS[class]
        if rc then r, g, b = rc.r, rc.g, rc.b end
    end
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5), player)
end
UI.ClassName = ClassName
UI.BIS_RED = BIS_RED

local function DrawParty()
    local p, Th = frame.party, T()
    if p.byTotal.SetPrimary then p.byTotal:SetPrimary(UI.sort == "total") end
    if p.byPeople.SetPrimary then p.byPeople:SetPrimary(UI.sort == "people") end
    p.scroll.Fit()
    local ranked = W().Rank(UI.sort)
    local nh, nc, y = 0, 0, 0
    -- every card first, to measure the columns
    local all = {}
    for _, d in ipairs(ranked) do
        for _, it in ipairs(d.items) do
            local r = PartyCard(#all + 1)
            FillCard(r, it.id)
            all[#all + 1] = r
        end
    end
    local colW = ColumnWidth(all)
    colW = UI.Fit(colW)
    p.scroll.Fit()
    for di, d in ipairs(ranked) do
        if di > 1 then y = y + 14 end
        nh = nh + 1
        local l = PartyHeading(nh)
        l:SetText(d.name)
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", p.scroll.list, "TOPLEFT", 0, -y)
        l:SetPoint("RIGHT", p.scroll.list, "RIGHT", 0, 0)
        l:Show()
        y = y + 28
        -- One card per item, two columns under the dungeon: who wants it, in
        -- class colour, after the boss.
        local colY = { y, y, y }
        for _, it in ipairs(d.items) do
            nc = nc + 1
            local r = PartyCard(nc)
            FillCard(r, it.id)
            local who = {}
            for _, w in ipairs(it.wanters) do
                -- "Cosmo (Restoration) BIS": the specs it is for, BIS in red,
                -- Upgrade in the line's own grey.
                local spec = #w.specs > 0 and (" (" .. table.concat(w.specs, "/") .. ")") or ""
                local tag = w.tag == "bis" and (" " .. BIS_RED .. "BIS|r") or (w.tag == "up" and " Upgrade" or "")
                who[#who + 1] = ClassName(w.player, w.class) .. spec .. tag
            end
            r.sub:SetText(it.boss .. "  \194\183  " .. table.concat(who, ", "))
            Place(r, p.scroll.list, colY, colW, LayoutCard(r, colW))
        end
        y = math.max(colY[1], colY[2], colY[3])
    end
    for i = nh + 1, #p.lines do p.lines[i]:Hide() end
    for i = nc + 1, #p.cards do p.cards[i]:Hide() p.cards[i].id = nil end
    p.scroll.list:SetHeight(math.max(10, y))
    p.empty:SetShown(#ranked == 0)
    p.empty:SetText("Nobody has wished for anything yet. Lists arrive from party members who run Salus Novus.")
    p.count = #ranked
end

function UI.Refresh()
    if not frame or not frame:IsShown() then return end
    frame.mine:SetShown(UI.view == "mine")
    frame.party:SetShown(UI.view == "party")
    DrawSidebar()
    if not W().catalog then
        -- No loot data (no AtlasLoot, or still loading): say so on either
        -- tab; the party's wishes cannot be placed in dungeons without it.
        local why = UI.why or "Loading AtlasLoot's dungeon data..."
        if UI.why and not W().HasAtlasLoot() then why = why .. ". The wishlist reads its loot tables from AtlasLoot Classic." end
        frame.mine.title:SetText("")
        for _, m in ipairs({ frame.mine, frame.party }) do
            if m.scroll then m.scroll.list:SetHeight(10) end
            for _, c in ipairs(m.rows or m.cards or {}) do c:Hide() end
            for _, l in ipairs(m.lines or {}) do l:Hide() end
            for _, b in ipairs(m.slotButtons or {}) do b:Hide() end
            m.empty:SetText(why)
            m.empty:ClearAllPoints()
            m.empty:SetPoint("TOPLEFT", 0, m == frame.party and -48 or -4)
            m.empty:SetPoint("RIGHT", m, "RIGHT", 0, 0)
            m.empty:Show()
        end
        if frame.mine.slotLabel then frame.mine.slotLabel:Hide() end
        return
    end
    if frame.mine.slotLabel then frame.mine.slotLabel:Show() end
    if UI.view == "mine" then DrawMine() else DrawParty() end
end

function UI.Shown() return frame ~= nil and frame:IsShown() end

--- Open: load the data, pick what this character picked last time
-- (nothing, the first time).
function UI.Open()
    Build()
    shell:Repaint()
    frame:Show()
    if frame.Raise then frame:Raise() end      -- over the visualizer when both are open
    W().LoadCatalog(function(cat, why)
        UI.why = why
        if cat then
            -- Only dungeons that still exist (an AtlasLoot update can rename one).
            UI.pool = {}
            local saved = W().SavedPool()
            for _, d in ipairs(cat.dungeons) do if saved[d.key] then UI.pool[d.key] = true end end
        end
        UI.Refresh()
        if cat then ScrollToPool() end
    end)
    UI.Refresh()
    W().Request()
end

--- Toggle, or with `forceShow` always show (the settings launcher).
function UI.Toggle(forceShow)
    if frame and frame:IsShown() and not forceShow then frame:Hide() else UI.Open() end
end

-- Changes from the list, the group or the item cache redraw (once per frame).
local queued = false
local function Queue()
    if queued or not (frame and frame:IsShown()) then return end
    queued = true
    local function Go() queued = false UI.Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0, Go) else Go() end
end
ns.Wishlist.OnChanged = Queue
-- party traffic and roster changes redraw only the party view (every
-- message rebuilt every card of Mine: the sweep)
ns.Wishlist.OnPartyChanged = function() if UI.view == "party" then Queue() end end
-- An item answer redraws only for a card still waiting on it
ns.Wishlist.OnItemInfo = function(id)
    if id ~= nil and not UI.waiting[id] then return end
    if id ~= nil then UI.waiting[id] = nil end
    Queue()
end

ns.Commands = ns.Commands or {}
ns.Commands.wish = function() UI.Toggle() end
