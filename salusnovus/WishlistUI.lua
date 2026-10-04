--[[ Salus Novus -- the wishlist window (/sn wish, or the sidebar launcher).

Laid out like the Boss Visualizer: a sidebar with a Mine / Party switch over
the dungeon list (multiselect rows, name and level range; opened on the
dungeons within 8 levels), and the content to the right. Mine: a slot filter
across the picked dungeons and one row per item you can equip, with spec and
BIS/Upgrade tags and a wish box. Party: dungeons ranked by the group's
wishes, by most wanted entries or by most party members.
]]

local _, ns = ...

local UI = {}
ns.WishlistUI = UI
local W = function() return ns.Wishlist end

local WIN_W, WIN_H, SIDEBAR_W, HEADER_H = 1000, 680, 250, 64
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
    shell = Th.MakeShell("SalusNovusWishlist", WIN_W, WIN_H, SIDEBAR_W, HEADER_H, "Wishlist")
    frame = shell.frame
    frame.shell = shell
    frame:SetFrameLevel(120)
    -- Opened from the settings sidebar, closing brings the settings back.
    frame:SetScript("OnHide", function()
        if itemTip then itemTip:Hide() end
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
    for _, id in ipairs(W().MyItems()) do
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

-- Our own tooltip, not GameTooltip: GameTooltip compares with what you
-- have equipped (a second panel; Alex wants only the hovered item), and
-- switching that off on Blizzard's shared tooltip from an addon taints it.
-- A fresh GameTooltip never opts into comparison.
local itemTip
local function ItemTip()
    if itemTip then return itemTip end
    local ok, t = pcall(CreateFrame, "GameTooltip", "SalusNovusItemTooltip", UIParent, "GameTooltipTemplate")
    if not ok or not t then return rawget(_G, "GameTooltip") end
    t:SetFrameStrata("TOOLTIP")
    t.supportsItemComparison = false
    itemTip = t
    return t
end
UI.ItemTip = ItemTip

-- An item card, shared by both tabs: square icon (Blizzard's rounded rim
-- cropped off) on a crisp black frame, quality-coloured name, a detail
-- line; hover lifts it and shows the item's tooltip.
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
    r.name = Th.MakeText(r, 15, Th.TEXT)
    r.name:SetPoint("TOPLEFT", r.iconEdge, "TOPRIGHT", 12, -2)
    r.name:SetPoint("RIGHT", r, "RIGHT", -48, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.sub = Th.MakeText(r, 13, Th.TEXT_MUTE)
    r.sub:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -48, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self.bg:SetVertexColor(1, 1, 1, CARD_HOVER_A)
        local ar, ag, ab = Th.Accent()
        self.border:SetColor(ar, ag, ab, 0.9)
        local tip = ItemTip()
        if tip and self.id then
            tip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 18, -8)   -- by the cursor, not out past the card's right edge
            local ok = tip.SetItemByID and pcall(tip.SetItemByID, tip, self.id)
            if not ok and tip.SetHyperlink then pcall(tip.SetHyperlink, tip, "item:" .. self.id) end
            tip:Show()
        end
    end)
    r:SetScript("OnLeave", function(self)
        self.bg:SetVertexColor(1, 1, 1, CARD_A)
        self.border:SetColor(1, 1, 1, 0.06)
        local tip = ItemTip()
        if tip then tip:Hide() end
    end)
    return r
end

--- Fill a card's icon and name from the item cache.
local function FillCard(r, id, info)
    r.id = id
    info = info or W().Info(id)
    r.iconTex:SetTexture(info and info.icon or 134400)
    local q = QUALITY[info and info.quality] or QUALITY[1]
    r.name:SetText(info and info.name or ("item " .. id))
    r.name:SetTextColor(q[1], q[2], q[3], 1)
end

local function ItemRow(i)
    local m = frame.mine
    local r = m.rows[i]
    if r then return r end
    local Th = T()
    -- Mine: the whole card toggles the wish; the chips and the box keep
    -- their own clicks.
    r = ItemCard(m.scroll.list)
    local function Toggle()
        if not r.id then return end
        W().Wish(r.id, not W().Get(r.id))
    end
    r.wish = Th.MakeCheckBox(r, 20)
    r.wish:SetPoint("RIGHT", r, "RIGHT", -14, 0)
    if r.wish.text then r.wish.text:Hide() end
    r.wish:SetScript("OnClick", Toggle)
    r:SetScript("OnClick", Toggle)
    r.chips = {}
    m.rows[i] = r
    return r
end

local function RowChips(r, e, rec)
    -- Always shown (Alex); a click on an item not yet wished wishes it.
    for _, c in ipairs(r.chips) do c:Hide() end
    rec = rec or {}
    local labels = {}
    for _, s in ipairs(W().MySpecs()) do labels[#labels + 1] = { "spec", s } end
    labels[#labels + 1] = { "tag", "bis", "BIS" }
    labels[#labels + 1] = { "tag", "up", "Upgrade" }
    local x = 9 + ICON + 2 + 12
    for i, l in ipairs(labels) do
        local c = r.chips[i]
        if not c then
            c = Chip(r, l[3] or l[2], 15, nil)
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
        c:ClearAllPoints()
        c:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 9)
        c:Show()
        x = x + c:GetWidth() + 6
    end
end

local function DrawMine()
    local m = frame.mine
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
    local list = W().Browse(UI.pool, UI.slot)
    table.sort(list, function(a, b)
        if a.info.req ~= b.info.req then return a.info.req < b.info.req end
        return a.info.name < b.info.name
    end)
    m.title:SetText(UI.slot or "All slots")
    local ry = 0
    for i, e in ipairs(list) do
        local r = ItemRow(i)
        FillCard(r, e.id, e.info)
        -- The slot only on All: under a slot filter it says nothing.
        local parts = {}
        if not UI.slot then parts[#parts + 1] = e.slot end
        parts[#parts + 1] = e.boss
        parts[#parts + 1] = e.dungeon
        if W().Owned(e.id) then parts[#parts + 1] = "OWNED" end
        r.sub:SetText(table.concat(parts, "  \194\183  "))
        local rec = W().Get(e.id)
        r.wish:SetChecked(rec ~= nil)
        RowChips(r, e, rec)
        local h = ROW_H_TAGGED
        r:SetHeight(h)
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", m.scroll.list, "TOPLEFT", 0, -ry)
        r:SetPoint("RIGHT", m.scroll.list, "RIGHT", -6, 0)
        r:Show()
        ry = ry + h + CARD_GAP
    end
    for i = #list + 1, #m.rows do m.rows[i]:Hide() m.rows[i].id = nil end
    m.scroll.list:SetHeight(math.max(10, ry))
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
        -- One card per item: who wants it, in class colour, after the boss.
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
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", p.scroll.list, "TOPLEFT", 0, -y)
            r:SetPoint("RIGHT", p.scroll.list, "RIGHT", -6, 0)
            r:Show()
            y = y + ROW_H + CARD_GAP
        end
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
ns.Wishlist.OnItemInfo = Queue

ns.Commands = ns.Commands or {}
ns.Commands.wish = function() UI.Toggle() end
