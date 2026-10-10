--[[ Salus Novus -- the Buy tab on the auction house.

  left     Browse: the AH's own categories; Lists: your shopping lists
           (New, Import, Export, Delete)
  top      a search box (Search; with a list: Add to list, Search list),
           then the filters: level range, quality, usable only
  list     item, Exact (per list line), level, listed, price -- the
           headers sort; a browse loads more on "More results"; a list
           shows every line, greyed until searched or when nothing matches
  bottom   the clicked item: a commodity buys from the cheapest listing up
           (quantity starts at the cheapest listing's), an item the
           cheapest auction; Buy, then Confirm at the client's quote
]]

local _, ns = ...

local UI = {}
ns.BuyUI = UI
local function B() return ns.Buy end
local function AU() return ns.AuctionUI end
local function T() return ns.Theme end

local ROW_H, MAX_ROWS, SIDE_W, CAT_H = 26, 300, 170, 22
local COLS = { { "Item", 34, 200, "LEFT", "name" }, { "Exact", 238, 46, "CENTER" }, { "Level", 288, 44, nil, "level" },
               { "Listed", 336, 64, nil, "listed" }, { "Price", 404, 110, nil, "price" } }
UI.side = "browse"                                 -- the left column: "browse" | "lists"
local panel

--- Boxes still being typed in count before a click acts (a Button click
-- doesn't take an EditBox's focus): the level boxes before a browse, the
-- amount before a pick (sweep 3).
local function CommitBoxes()
    for _, eb in ipairs({ panel.minLevel, panel.maxLevel, panel.qty }) do
        if eb and eb:HasFocus() == true then eb:ClearFocus() end
    end
end
UI.CommitBoxes = CommitBoxes

local function Money(c) return AU().Money(c) end

-- ------------------------------------------------------------ the dialog

--- New list / Import / Export, over the panel.
local function Dialog()
    if panel.dialog then return panel.dialog end
    local Th = T()
    local d = CreateFrame("Frame", nil, panel)
    d:SetSize(380, 290)
    d:SetPoint("CENTER")
    d:SetFrameLevel(panel:GetFrameLevel() + 50)
    d:EnableMouse(true)
    d.bg = Th.SolidTex(d, "BACKGROUND", Th.BG[1] * 0.7, Th.BG[2] * 0.7, Th.BG[3] * 0.7, 1)
    d.bg:SetAllPoints()
    d.border = Th.Border(d)
    d.border:Layout(d, 1, 0)
    d.border:SetColor(1, 1, 1, 0.18)
    d.border:Show()
    d.title = Th.MakeText(d, 15, Th.TEXT)
    d.title:SetPoint("TOPLEFT", 14, -12)
    d.nameLabel = Th.MakeText(d, 13, Th.TEXT_DIM)
    d.nameLabel:SetPoint("TOPLEFT", 14, -44)
    d.nameLabel:SetText("Name")
    d.name = Th.MakeEditBox(d, 260)
    d.name:SetPoint("LEFT", d.nameLabel, "RIGHT", 10, 0)
    d.text = Th.MakeEditBox(d, 350)
    d.text:SetMultiLine(true)
    d.text:SetHeight(170)
    d.text:SetTextInsets(6, 6, 6, 6)
    d.text:SetPoint("TOPLEFT", 14, -74)
    d.text:SetScript("OnEnterPressed", nil)                  -- Enter is a new line here
    d.ok = Th.MakeButton(d)
    d.ok:SetSize(100, 26)
    d.ok:SetPoint("BOTTOMRIGHT", -14, 12)
    d.ok:SetPrimary(true)
    d.close = Th.MakeButton(d)
    d.close:SetSize(90, 26)
    d.close:SetPoint("RIGHT", d.ok, "LEFT", -8, 0)
    d.close:SetText("Cancel")
    d.close:SetScript("OnClick", function() d:Hide() end)
    d.ok:SetScript("OnClick", function()
        local b = B()
        if d.mode == "new" then
            if b.NewList(d.name:GetText()) then UI.detail = false d:Hide() UI.Refresh() end   -- out of a drill-down (sweep 6)
        elseif d.mode == "import" then
            if b.Import(d.name:GetText(), d.text:GetText()) then UI.detail = false d:Hide() UI.Refresh() end
        else
            d:Hide()
        end
    end)
    d:Hide()
    panel.dialog = d
    return d
end

function UI.OpenDialog(mode)
    local d = Dialog()
    d.mode = mode
    local cur, idx = B().Current()
    d.name:SetText("")
    d.text:SetText("")
    local showName, showText = mode ~= "export", mode ~= "new"
    d.nameLabel:SetShown(showName)
    d.name:SetShown(showName)
    d.text:SetShown(showText)
    if mode == "new" then
        d.title:SetText("New list")
        d.ok:SetText("Create")
    elseif mode == "import" then
        d.title:SetText("Import a list: one item name per line")
        d.ok:SetText("Import")
    else
        d.title:SetText(("Export: %s (copy with Ctrl+C)"):format(cur and cur.name or ""))
        d.text:SetText(B().Export(idx))
        d.ok:SetText("Close")
    end
    d.close:SetShown(mode ~= "export")
    d:Show()
    if mode == "export" then d.text:SetFocus() d.text:HighlightText() elseif showName then d.name:SetFocus() end
end

-- ------------------------------------------------------------ rows

local function Row(i)
    local list = panel.scroll.child
    local r = panel.rows[i]
    if r then return r end
    local Th = T()
    r = CreateFrame("Button", nil, list)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("RIGHT", list, "RIGHT", 0, 0)
    r.bg = Th.SolidTex(r, "BACKGROUND", 1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    r.bg:SetAllPoints()
    r.hl = Th.SolidTex(r, "HIGHLIGHT", 1, 1, 1, 0.07)
    r.hl:SetAllPoints()
    r.on = Th.SolidTex(r, "BORDER", 1, 1, 1, 0.12)
    r.on:SetAllPoints()
    r.on:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cells = {}
    for k, c in ipairs(COLS) do r.cells[k] = AU().Cell(r, c[2], c[3], c[4]) end
    r.exact = Th.MakeCheckBox(r, 14)
    r.exact:SetPoint("CENTER", r, "LEFT", COLS[2][2] + COLS[2][3] / 2, 0)
    r.exact:SetScript("OnClick", function(self)
        if self.line then B().SetExact(self.line, not self:GetChecked()) end
    end)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then UI.Back() return end     -- a right-click is Back (Alex)
        local v = self.view
        if not v then return end
        CommitBoxes()                               -- a typed amount first; the pick then sets it
        if v.listing then B().PickListing(v.listing) return end   -- drilled down: buy through / that one
        UI.line, UI.lineOf = v.line, B().Current()
        if v.id then
            -- everything listed for it (Alex) -- once it's the one picked (a
            -- refused pick drilled into the old item: sweep 3)
            if B().Select(v) then UI.detail = true end
            UI.Refresh()
        else UI.Refresh() end
    end)
    -- an auction row: that auction (its link, its version); a result row: the item
    AU().Hover(r, function(self) local v = self.view if v and v.id then return v.id, v.key or (B().sel and B().sel.key), v.link end end)
    panel.rows[i] = r
    return r
end

--- One category row: indented by depth; a click picks it (and opens or
-- closes its sub-categories) and browses it.
UI.open = {}
local function PathKey(path) return table.concat(path, ".") end
local function CatRow(i)
    local b = panel.catRows[i]
    if b then return b end
    local Th = T()
    b = CreateFrame("Button", nil, panel.cats.child)
    b:SetHeight(CAT_H)
    b:SetPoint("TOPLEFT", panel.cats.child, "TOPLEFT", 0, -(i - 1) * CAT_H)
    b:SetPoint("RIGHT", panel.cats.child, "RIGHT", 0, 0)
    b.on = Th.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.10)
    b.on:SetAllPoints()
    b.hl = Th.SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.06)
    b.hl:SetAllPoints()
    b.text = Th.MakeText(b, 13, Th.TEXT)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b:SetScript("OnClick", function(self)
        -- Only the picked branch stays open (Alex: from Consumables to
        -- Containers, Consumables folds); a second click folds the pick.
        local path = self.path
        local open = {}
        if path then
            for d = 1, #path - 1 do
                local up = {}
                for x = 1, d do up[x] = path[x] end
                open[PathKey(up)] = true
            end
            local key = PathKey(path)
            local same = B().cat and PathKey(B().cat) == key
            if self.hasSubs and not (same and UI.open[key]) then open[key] = true end
        end
        UI.open = open
        UI.detail = false
        CommitBoxes()
        B().PickCategory(path, panel.search:GetText())
    end)
    panel.catRows[i] = b
    return b
end


local function ListButton(i)
    local b = panel.listButtons[i]
    if b then return b end
    local Th = T()
    b = CreateFrame("Button", nil, panel.lists.child)          -- (in a scroll: past ~15 lists they ran under the buttons -- sweep 3)
    b:SetHeight(24)
    b:SetPoint("TOPLEFT", panel.lists.child, "TOPLEFT", 0, -(i - 1) * 26)
    b:SetPoint("RIGHT", panel.lists.child, "RIGHT", 0, 0)
    b.on = Th.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.10)
    b.on:SetAllPoints()
    b.hl = Th.SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.06)
    b.hl:SetAllPoints()
    b.text = Th.MakeText(b, 13, Th.TEXT)
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b:SetScript("OnClick", function(self)
        UI.line, UI.detail = nil, false
        local _, cur = B().Current()
        if B().mode == "list" and cur == self.index then UI.Refresh() return end   -- the picked one again: its results stay (sweep 5)
        B().Pick(self.index)
    end)
    panel.listButtons[i] = b
    return b
end

-- ------------------------------------------------------------ the panel

local function Build()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if panel or not ahf then return panel end
    local Th = T()
    panel = CreateFrame("Frame", "SalusNovusBuy", ahf)
    panel:SetPoint("TOPLEFT", ahf, "TOPLEFT", 4, -26)
    panel:SetPoint("BOTTOMRIGHT", ahf, "BOTTOMRIGHT", -4, 4)
    pcall(panel.SetFrameStrata, panel, ahf:GetFrameStrata())
    panel:SetFrameLevel(math.min(9000, (ahf:GetFrameLevel() or 0) + 500))
    panel:EnableMouse(true)
    panel.bg = Th.SolidTex(panel, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 1)
    panel.bg:SetAllPoints()
    panel:Hide()

    panel.bar = CreateFrame("StatusBar", nil, panel)
    panel.bar:SetHeight(AU().BAR_H)
    panel.bar:SetPoint("TOPLEFT")
    panel.bar:SetPoint("TOPRIGHT")
    panel.bar:SetStatusBarTexture(Th.SOLID)
    panel.bar:SetMinMaxValues(0, 1)
    panel.bar.bg = Th.SolidTex(panel.bar, "BACKGROUND", 1, 1, 1, 0.06)
    panel.bar.bg:SetAllPoints()
    panel.bar:Hide()

    -- left: the lists
    panel.side = CreateFrame("Frame", nil, panel)
    panel.side:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -12)
    panel.side:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 92)
    panel.side:SetWidth(SIDE_W)
    -- Browse | Lists
    panel.sideButtons = {}
    for k, def in ipairs({ { "browse", "Browse" }, { "lists", "Lists" } }) do
        local b = Th.MakeButton(panel.side)
        b:SetSize((SIDE_W - 12) / 2, 24)
        b:SetPoint("TOPLEFT", panel.side, "TOPLEFT", (k - 1) * ((SIDE_W - 12) / 2 + 4), 0)
        b:SetText(def[2])
        b:SetScript("OnClick", function()
            UI.side = def[1]
            if def[1] == "browse" and B().mode == "list" then UI.line, UI.detail = nil, false B().Pick(nil) end   -- out of the list (it held the column)
            UI.Refresh()
        end)
        b.side = def[1]
        panel.sideButtons[k] = b
    end
    panel.cats = Th.MakeScrollArea(panel.side)
    panel.cats:SetPoint("TOPLEFT", panel.side, "TOPLEFT", 0, -32)
    panel.cats:SetPoint("BOTTOMRIGHT", panel.side, "BOTTOMRIGHT", -20, 0)    -- room for the thick bar
    panel.cats.child:SetWidth(SIDE_W - 14)
    AU().Thick(panel.cats)
    panel.catRows = {}
    panel.sideHead = Th.MakeText(panel.side, 12, Th.TEXT_MUTE)
    panel.sideHead:SetPoint("TOPLEFT", 0, -34)
    panel.sideHead:SetText("LISTS")
    panel.lists = Th.MakeScrollArea(panel.side)
    panel.lists:SetPoint("TOPLEFT", panel.side, "TOPLEFT", 0, -56)
    panel.lists:SetPoint("BOTTOMRIGHT", panel.side, "BOTTOMRIGHT", -20, 54)   -- above New/Import/Export/Delete
    panel.lists.child:SetWidth(SIDE_W - 14)
    AU().Thick(panel.lists)
    panel.listButtons = {}
    panel.listActions = {}
    local acts = { { "New", function() UI.OpenDialog("new") end }, { "Import", function() UI.OpenDialog("import") end },
                   { "Export", function() if B().Current() then UI.OpenDialog("export") end end },
                   { "Delete", function() local _, i = B().Current() if i then UI.detail = false B().DeleteList(i) end end } }
    for k, a in ipairs(acts) do
        local b = Th.MakeButton(panel.side)
        b:SetSize(76, 22)
        b:SetPoint("BOTTOMLEFT", panel.side, "BOTTOMLEFT", ((k - 1) % 2) * 80, math.floor((k - 1) / 2) == 0 and 26 or 0)
        b:SetText(a[1])
        b:SetScript("OnClick", function(self) if self.enabledState ~= false then a[2]() end end)
        panel.listActions[a[1]] = b
    end
    panel.split = Th.SolidTex(panel, "ARTWORK", 1, 1, 1, 0.08)
    panel.split:SetWidth(1)
    panel.split:SetPoint("TOPLEFT", panel.side, "TOPRIGHT", 4, 0)
    panel.split:SetPoint("BOTTOMLEFT", panel.side, "BOTTOMRIGHT", 4, 0)

    -- right: search
    local x0 = 12 + SIDE_W + 16
    panel.search = Th.MakeEditBox(panel, 220)
    panel.search:SetPoint("TOPLEFT", panel, "TOPLEFT", x0, -12)
    panel.search:SetScript("OnEnterPressed", function(self) self:ClearFocus() CommitBoxes() UI.detail = false B().Search(self:GetText()) end)
    panel.go = Th.MakeButton(panel)
    panel.go:SetSize(80, 24)
    panel.go:SetPoint("LEFT", panel.search, "RIGHT", 6, 0)
    panel.go:SetText("Search")
    panel.go:SetScript("OnClick", function() panel.search:ClearFocus() CommitBoxes() UI.detail = false B().Search(panel.search:GetText()) end)
    panel.add = Th.MakeButton(panel)
    panel.add:SetSize(96, 24)
    panel.add:SetPoint("LEFT", panel.go, "RIGHT", 6, 0)
    panel.add:SetText("Add to list")
    panel.add:SetScript("OnClick", function(self)
        if self.enabledState and B().AddItem(panel.search:GetText()) then panel.search:SetText("") end
    end)
    panel.searchList = Th.MakeButton(panel)
    panel.searchList:SetSize(96, 24)
    panel.searchList:SetPoint("LEFT", panel.add, "RIGHT", 6, 0)
    panel.searchList:SetText("Search list")
    panel.searchList:SetScript("OnClick", function(self) if self.enabledState then UI.detail = false B().SearchList() end end)

    -- the filters, as the AH's own: level range, quality, usable only
    panel.lvlLabel = Th.MakeText(panel, 13, Th.TEXT_DIM)
    panel.lvlLabel:SetPoint("TOPLEFT", panel, "TOPLEFT", x0, -46)
    panel.lvlLabel:SetText("Level")
    local function LevelBox(key)
        local eb = Th.MakeEditBox(panel, 40)
        eb:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() UI.detail = false B().Browse(panel.search:GetText()) end)
        eb:SetScript("OnEditFocusLost", function(self)
            local n = tonumber((self:GetText() or ""):match("^%s*(%d+)%s*$"))
            B().SetFilter(key, (n and n > 0) and n or nil)
        end)
        return eb
    end
    panel.minLevel = LevelBox("minLevel")
    panel.minLevel:SetPoint("LEFT", panel.lvlLabel, "RIGHT", 8, 0)
    panel.lvlTo = Th.MakeText(panel, 13, Th.TEXT_DIM)
    panel.lvlTo:SetPoint("LEFT", panel.minLevel, "RIGHT", 6, 0)
    panel.lvlTo:SetText("to")
    panel.maxLevel = LevelBox("maxLevel")
    panel.maxLevel:SetPoint("LEFT", panel.lvlTo, "RIGHT", 6, 0)
    -- Quality: a dropdown, each choice filled in its colour (Alex)
    local function QualityFill(tex, q)
        local c = q and AU().QUALITY[q]
        if c then tex:SetVertexColor(c[1], c[2], c[3], q == 1 and 0.22 or 0.40)
        else tex:SetVertexColor(1, 1, 1, 0.06) end
    end
    UI.QualityFill = QualityFill
    panel.quality = CreateFrame("Button", nil, panel)
    panel.quality:SetSize(120, 24)
    panel.quality:SetPoint("LEFT", panel.maxLevel, "RIGHT", 12, 0)
    panel.quality.fill = Th.SolidTex(panel.quality, "BACKGROUND", 1, 1, 1, 0.06)
    panel.quality.fill:SetAllPoints()
    panel.quality.border = Th.Border(panel.quality)
    panel.quality.border:Layout(panel.quality, 1, 0)
    panel.quality.border:SetColor(1, 1, 1, 0.18)
    panel.quality.border:Show()
    panel.quality.text = Th.MakeText(panel.quality, 13, Th.TEXT)
    panel.quality.text:SetPoint("LEFT", 8, 0)
    -- A filled triangle, not a letter (Alex: "v" read as a v): a square with
    -- its bottom corners pulled to the middle
    panel.quality.arrow = Th.SolidTex(panel.quality, "OVERLAY", 0.85, 0.85, 0.9, 1)
    panel.quality.arrow:SetSize(9, 5)
    panel.quality.arrow:SetPoint("RIGHT", -8, 0)
    local okV = pcall(panel.quality.arrow.SetVertexOffset, panel.quality.arrow, 2, 4.5, 0)
    okV = okV and pcall(panel.quality.arrow.SetVertexOffset, panel.quality.arrow, 4, -4.5, 0)
    panel.quality.triangle = okV
    function panel.quality:SetText(t) self.text:SetText(t) end
    function panel.quality:GetText() return self.text:GetText() end
    panel.qualityMenu = CreateFrame("Frame", nil, panel)
    panel.qualityMenu:SetPoint("TOPLEFT", panel.quality, "BOTTOMLEFT", 0, -2)
    panel.qualityMenu:SetSize(120, #B().QUALITIES * 24)
    panel.qualityMenu:SetFrameLevel(panel:GetFrameLevel() + 60)
    panel.qualityMenu.bg = Th.SolidTex(panel.qualityMenu, "BACKGROUND", Th.BG[1] * 0.6, Th.BG[2] * 0.6, Th.BG[3] * 0.6, 1)
    panel.qualityMenu.bg:SetAllPoints()
    panel.qualityMenu:EnableMouse(true)
    panel.qualityMenu:Hide()
    panel.qualityItems = {}
    for k, q in ipairs(B().QUALITIES) do
        local it = CreateFrame("Button", nil, panel.qualityMenu)
        it:SetSize(120, 24)
        it:SetPoint("TOPLEFT", 0, -(k - 1) * 24)
        it.fill = Th.SolidTex(it, "BACKGROUND", 1, 1, 1, 0.06)
        it.fill:SetPoint("TOPLEFT", 1, -1)
        it.fill:SetPoint("BOTTOMRIGHT", -1, 1)
        QualityFill(it.fill, q[1])
        it.hl = Th.SolidTex(it, "HIGHLIGHT", 1, 1, 1, 0.10)
        it.hl:SetAllPoints()
        it.text = Th.MakeText(it, 13, Th.TEXT)
        it.text:SetPoint("LEFT", 8, 0)
        it.text:SetText(q[2])
        it:SetScript("OnClick", function()
            panel.qualityMenu:Hide()
            B().SetFilter("quality", q[1])
        end)
        panel.qualityItems[k] = it
    end
    panel.quality:SetScript("OnClick", function() panel.qualityMenu:SetShown(not panel.qualityMenu:IsShown()) end)
    panel.usable = Th.MakeLabelledCheckBox(panel, "Usable only", 16)
    panel.usable:SetPoint("LEFT", panel.quality, "RIGHT", 12, 0)
    panel.usable:SetScript("OnClick", function(self) B().SetFilter("usable", not self:GetChecked()) end)
    panel.unfilter = Th.MakeButton(panel)
    panel.unfilter:SetSize(84, 24)
    panel.unfilter:SetPoint("LEFT", panel.usable.label, "RIGHT", 14, 0)
    panel.unfilter:SetText("Unfilter")
    panel.unfilter:SetScript("OnClick", function()                -- back to All, everything folded (Alex)
        UI.open, UI.detail = {}, false
        panel.qualityMenu:Hide()
        -- a level being typed is dropped, not saved after the reset (sweep 3)
        for _, eb in ipairs({ panel.minLevel, panel.maxLevel }) do eb:SetText("") if eb:HasFocus() == true then eb:ClearFocus() end end
        B().Unfilter()
    end)
    panel.back = Th.MakeButton(panel)
    panel.back:SetSize(70, 24)
    panel.back:SetPoint("LEFT", panel.unfilter, "RIGHT", 6, 0)      -- in line with Unfilter (Alex)
    panel.back:SetText("Back")
    panel.back:SetScript("OnClick", function() UI.Back() end)
    -- a right-click anywhere on the panel is Back too
    panel:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then UI.Back() end end)
    panel.back:Hide()

    local head = CreateFrame("Frame", nil, panel)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", x0, -78)
    head:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    panel.heads = {}
    for k, c in ipairs(COLS) do
        local t = AU().Cell(head, c[2], c[3], c[4])
        t:SetTextColor(Th.TEXT_MUTE[1], Th.TEXT_MUTE[2], Th.TEXT_MUTE[3], 1)
        t:SetText(c[1])
        panel.heads[k] = t
        if c[5] then                                   -- a header that sorts
            local hb = CreateFrame("Button", nil, head)
            hb:SetPoint("TOPLEFT", head, "TOPLEFT", c[2] - (k == 1 and 34 or 0), 0)
            hb:SetSize(c[3] + (k == 1 and 34 or 0), 20)
            hb:SetScript("OnClick", function() B().SortBy(c[5]) end)
            t.sortKey, t.button = c[5], hb
        end
    end
    panel.scroll = Th.MakeScrollArea(panel)
    panel.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 92)
    panel.scroll.child:SetWidth(560)
    AU().Thick(panel.scroll)
    panel.scroll:EnableMouse(true)                       -- a right-click on the list's empty space is Back
    panel.scroll:SetScript("OnMouseUp", function(_, button) if button == "RightButton" then UI.Back() end end)
    panel.rows = {}
    panel.empty = Th.MakeText(panel.scroll.child, 14, Th.TEXT_MUTE)
    panel.empty:SetPoint("TOPLEFT", 6, -8)
    panel.empty:SetPoint("RIGHT", panel.scroll.child, "RIGHT", -6, 0)
    panel.empty:SetJustifyH("LEFT")
    panel.moreRow = Th.MakeButton(panel.scroll.child)
    panel.moreRow:SetSize(160, 24)
    panel.moreRow:SetText("More results")
    panel.moreRow:SetScript("OnClick", function() B().More() end)
    panel.moreRow:Hide()

    -- bottom
    local foot = CreateFrame("Frame", nil, panel)
    foot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
    foot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
    foot:SetHeight(72)
    foot.line = Th.SolidTex(foot, "ARTWORK", 1, 1, 1, 0.08)
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT")
    foot.line:SetPoint("TOPRIGHT")
    panel.selName = Th.MakeText(foot, 15, Th.TEXT)
    panel.selName:SetPoint("TOPLEFT", 0, -10)
    -- The amount sits by the Buy button and looks like one (Alex): button
    -- height, centred, a little larger
    panel.qtyLabel = Th.MakeText(foot, 13, Th.TEXT_DIM)      -- (kept hidden; nothing reads "Buy" twice)
    panel.qtyLabel:Hide()
    panel.qty = Th.MakeEditBox(foot, 72)
    panel.qty:SetHeight(30)
    ns.SetFontSafe(panel.qty, 15, "")
    if panel.qty.SetJustifyH then panel.qty:SetJustifyH("CENTER") end
    if panel.qty.border then panel.qty.border:SetColor(1, 1, 1, 0.28) end
    panel.qty:SetScript("OnEditFocusGained", function(self) self:HighlightText() self.forSel = B().sel end)
    panel.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- the Buy button follows the box as you type (Alex): no Enter needed
    panel.qty:SetScript("OnTextChanged", function(self, user)
        if not user then return end
        local n = tonumber((self:GetText() or ""):match("^%s*(%d+)%s*$"))
        if n and n > 0 and B().sel == self.forSel then B().SetQty(n) end
    end)
    panel.qty:SetScript("OnEditFocusLost", function(self)
        local n = tonumber((self:GetText() or ""):match("^%s*(%d+)%s*$"))
        if n and B().sel == self.forSel then B().SetQty(n) end
        UI.Refresh()
    end)
    panel.selLine = Th.MakeText(foot, 13, Th.TEXT_DIM)
    panel.selLine:SetPoint("TOPLEFT", panel.selName, "BOTTOMLEFT", 0, -8)
    panel.selLine:SetPoint("RIGHT", foot, "RIGHT", -420, 0)
    panel.selLine:SetJustifyH("LEFT")
    panel.message = Th.MakeText(foot, 13, Th.TEXT_MUTE)
    panel.message:SetPoint("TOPLEFT", panel.selLine, "BOTTOMLEFT", 0, -10)
    panel.buy = Th.MakeButton(foot)
    panel.buy:SetSize(150, 30)
    panel.buy:SetPoint("RIGHT", foot, "RIGHT", 0, -4)
    panel.buy:SetPrimary(true)
    -- The purchase runs inside this click (the client requires it).
    panel.buy:SetScript("OnClick", function(self)
        if panel.qty:HasFocus() == true then panel.qty:ClearFocus() end
        if not self.enabledState then return end
        local sel = B().sel
        if sel and sel.quote then B().Confirm() else B().Buy() end
    end)
    panel.cancel = Th.MakeButton(foot)
    panel.cancel:SetSize(90, 30)
    panel.cancel:SetPoint("RIGHT", panel.buy, "LEFT", -8, 0)
    panel.cancel:SetText("Cancel")
    panel.cancel:SetScript("OnClick", function() B().Cancel() end)
    panel.remove = Th.MakeButton(foot)
    panel.remove:SetSize(130, 30)
    panel.remove:SetPoint("RIGHT", panel.cancel, "LEFT", -8, 0)
    panel.remove:SetText("Remove from list")
    panel.remove:SetScript("OnClick", function()
        local i = UI.line
        if not i then return end
        UI.line = nil                                   -- before the redraw (it stayed lit: sweep 5)
        B().RemoveItem(i)
        UI.Refresh()
    end)
    return panel
end
UI.Build = Build

local function DrawLists()
    local lists = B().Lists()
    local _, cur = B().Current()
    for i, l in ipairs(lists) do
        local b = ListButton(i)
        b.index = i
        b.text:SetText(("%s  |cff8a8a96%d|r"):format(l.name, #l.items))
        b.on:SetShown(i == cur)
        b:Show()
    end
    for i = #lists + 1, #panel.listButtons do panel.listButtons[i]:Hide() end
    panel.lists.child:SetHeight(math.max(10, #lists * 26))
    panel.listActions.Export:SetEnabledState(cur ~= nil)
    panel.listActions.Delete:SetEnabledState(cur ~= nil)
    panel.add:SetEnabledState(cur ~= nil)
    panel.searchList:SetEnabledState(cur ~= nil and B().run.state ~= "searching")
end

--- The category tree: "All", then each category, its open ones' children.
local function DrawCategories()
    local rows = { { name = "All", path = nil, depth = 0 } }
    local function Walk(list, prefix, depth)
        for i, c in ipairs(list or {}) do
            if B().Shown(c) then                        -- no WoW Token (Alex)
                local path = {}
                for _, x in ipairs(prefix) do path[#path + 1] = x end
                path[#path + 1] = i
                local subs = type(c.subCategories) == "table" and #c.subCategories > 0
                rows[#rows + 1] = { name = c.name or "?", path = path, depth = depth, subs = subs }
                if subs and UI.open[PathKey(path)] then Walk(c.subCategories, path, depth + 1) end
            end
        end
    end
    Walk(B().Categories(), {}, 0)
    local sel = B().cat and PathKey(B().cat) or nil
    for i, row in ipairs(rows) do
        local b = CatRow(i)
        b.path, b.hasSubs = row.path, row.subs
        b.text:ClearAllPoints()
        b.text:SetPoint("LEFT", 6 + row.depth * 12, 0)
        b.text:SetPoint("RIGHT", -4, 0)
        local picked = (row.path and PathKey(row.path) or nil) == sel
        local c = row.depth == 0 and T().TEXT or T().TEXT_DIM
        b.text:SetText(row.name)
        b.picked = picked
        if picked then                                -- what's filtering, in the accent (Alex)
            local ar, ag, ab = T().Accent()
            local tr, tg, tb = T().OnAccent()
            b.on:SetVertexColor(ar, ag, ab, 0.9)
            b.text:SetTextColor(tr, tg, tb, 1)
        else
            b.text:SetTextColor(c[1], c[2], c[3], 1)
        end
        b.on:SetShown(picked)
        b:Show()
    end
    for i = #rows + 1, #panel.catRows do panel.catRows[i]:Hide() end
    panel.cats.child:SetHeight(math.max(10, #rows * CAT_H))
end

local function DrawSelection()
    local b = B()
    local sel = b.sel
    panel.message:SetText(b.message or "")
    if UI.line and UI.lineOf ~= b.Current() then UI.line = nil end   -- another list now (Delete, New, Import)
    panel.remove:SetShown(b.mode == "list" and UI.line ~= nil)
    panel.cancel:Hide()
    -- right to left from Buy: Cancel (with a quote), the amount, Remove from list
    local function Chain()
        local anchor = panel.buy
        for _, f in ipairs({ panel.cancel, panel.qty, panel.remove }) do
            if f:IsShown() then
                f:ClearAllPoints()
                f:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
                anchor = f
            end
        end
    end
    UI.Chain = Chain
    if not sel then
        Chain()
        panel.selName:SetText("")
        panel.selLine:SetText("")
        panel.qty:Hide() panel.qtyLabel:Hide() panel.buy:Hide()
        return
    end
    local name, q = AU().ItemBits(sel.id)
    panel.selName:SetText(name)
    panel.selName:SetTextColor(q[1], q[2], q[3], 1)
    panel.buy:Show()
    if not sel.fresh then
        panel.qty:Hide()
        panel.selLine:SetText("Looking it up...")
        panel.buy:SetText("Buy")
        panel.buy:SetEnabledState(false)
        Chain()
        return
    end
    if #sel.levels == 0 then
        panel.qty:Hide()
        panel.selLine:SetText("None for sale")
        panel.buy:SetText("Buy")
        panel.buy:SetEnabledState(false)
        Chain()
        return
    end
    panel.selLine:SetText("")                        -- no supply/cost line (Alex): the button says it
    if sel.commodity then
        panel.qty:SetShown(not sel.asked)                -- a quote out: its amount stands, no box to type in
        if sel.asked and panel.qty:HasFocus() == true then panel.qty:ClearFocus() end
        if panel.qty:HasFocus() ~= true then panel.qty:SetText(tostring(sel.qty or sel.levels[1].qty)) end
        local qty = sel.qty or sel.levels[1].qty
        if sel.quote then
            panel.buy:SetText("Confirm " .. Money(sel.quote.total))
            panel.cancel:Show()
        else
            panel.buy:SetText(("Buy %d"):format(qty))
        end
        panel.buy:SetEnabledState(not sel.asked or sel.quote ~= nil)
    else
        panel.qty:Hide()
        local a = sel.levels[sel.pick or 1]
        panel.buy:SetText("Buy " .. Money(a.buyout))
        panel.buy:SetEnabledState(not sel.pending)
    end
    Chain()
end

function UI.Refresh()
    if not (panel and panel:IsShown()) then return end
    local b = B()
    if b.mode == "list" then UI.side = "lists" end       -- a list picked or made: its column
    local browse = UI.side == "browse"
    for _, sb in ipairs(panel.sideButtons) do sb:SetPrimary(sb.side == UI.side) end
    panel.cats:SetShown(browse)
    panel.sideHead:SetShown(not browse)
    panel.lists:SetShown(not browse)
    for _, a in pairs(panel.listActions) do a:SetShown(not browse) end
    for _, lb in ipairs(panel.listButtons) do lb:Hide() end
    panel.add:SetShown(not browse)
    panel.searchList:SetShown(not browse)
    if browse then DrawCategories() else DrawLists() end
    local f = b.filters
    if panel.minLevel:HasFocus() ~= true then panel.minLevel:SetText(f.minLevel and tostring(f.minLevel) or "") end
    if panel.maxLevel:HasFocus() ~= true then panel.maxLevel:SetText(f.maxLevel and tostring(f.maxLevel) or "") end
    for _, q in ipairs(b.QUALITIES) do if q[1] == f.quality then panel.quality:SetText(q[2]) end end
    UI.QualityFill(panel.quality.fill, f.quality)
    panel.usable:SetChecked(f.usable)
    for _, t in ipairs(panel.heads) do                -- the sorted column in the accent colour
        if t.sortKey == b.sort.key and b.mode ~= "list" then local r, g, bb = T().Accent() t:SetTextColor(r, g, bb, 1)
        else local m = T().TEXT_MUTE t:SetTextColor(m[1], m[2], m[3], 1) end
    end
    local view = b.View()
    local detail = UI.detail and b.sel ~= nil
    panel.back:SetShown(detail)
    local HEAD = detail and (b.sel.commodity and { "Price each", "", "", "Available", "Through here" }
        or { "Item", "", "", "Qty", "Buyout" })
        or { "Item", "Exact", "Level", "Listed", "Price" }
    for k, t in ipairs(panel.heads) do t:SetText(HEAD[k]) end
    if detail then
        -- Everything listed for the item, cheapest first: a commodity's price
        -- levels (a click buys through that level), an item's auctions (a
        -- click picks that one)
        view = {}
        local sel, cum = b.sel, 0
        for i, l in ipairs(sel.fresh and sel.levels or {}) do
            cum = cum + l.qty
            local cost = b.Cost(cum)
            view[i] = { listing = i, id = sel.id, unit = l.unit, qty = l.qty, through = cost, buyout = l.buyout, name = l.name,
                        key = l.key, link = l.link,
                        on = sel.commodity and (sel.qty or 0) >= cum or (not sel.commodity and (sel.pick or 1) == i) }
        end
    end
    local n = math.min(#view, MAX_ROWS)
    local listMode = b.mode == "list"
    for i = 1, n do
        local v = view[i]
        local r = Row(i)
        r.view = v
        local vals
        if v.listing then
            local _, _, icon = AU().ItemBits(v.id)
            r.icon:SetTexture(icon)
            r.icon:Show()
            if b.sel.commodity then
                vals = { Money(v.unit), "", "", tostring(v.qty), v.through and Money(v.through) or "" }
                local t = T().TEXT
                r.cells[1]:SetTextColor(t[1], t[2], t[3], 1)
            else
                -- gear: each auction under its own name ("... of the Monkey")
                local name, q = AU().ItemBits(v.id)
                vals = { v.name or name, "", "", tostring(v.qty), Money(v.buyout) }
                r.cells[1]:SetTextColor(q[1], q[2], q[3], 1)
            end
        elseif v.id then
            local name, q, icon = AU().ItemBits(v.id)
            r.icon:SetTexture(icon)
            r.icon:Show()
            vals = { name, "", (v.level and v.level > 0) and tostring(v.level) or "", tostring(v.listed or 0),
                     v.cheapest and Money(v.cheapest) or "" }
            r.cells[1]:SetTextColor(q[1], q[2], q[3], 1)
        else
            r.icon:Hide()
            vals = { v.lineName, "", "", "", v.none and "none" or "" }
            local m = T().TEXT_MUTE
            r.cells[1]:SetTextColor(m[1], m[2], m[3], 1)
        end
        for k, t in ipairs(r.cells) do t:SetText(vals[k]) end
        -- drilled down, the Exact and Level columns are empty: the name runs to Qty
        r.cells[1]:SetWidth(v.listing and (COLS[4][2] - COLS[1][2] - 8) or COLS[1][3])
        local showExact = listMode and v.first and not v.listing
        r.exact:SetShown(showExact and true or false)
        if showExact then r.exact.line = v.line r.exact:SetChecked(v.exact) end
        local on = v.listing and v.on or (not v.listing and ((b.sel and v.id and b.sel.id == v.id) or (listMode and UI.line == v.line and not v.id)))
        r.on:SetShown(on and true or false)
        r:Show()
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() panel.rows[i].view = nil end
    local more = not listMode and not detail and b.HasMore() and n > 0
    panel.moreRow:SetShown(more and true or false)
    if more then
        panel.moreRow:ClearAllPoints()
        panel.moreRow:SetPoint("TOPLEFT", panel.scroll.child, "TOPLEFT", 6, -(n * ROW_H) - 6)
        panel.moreRow:SetEnabledState(b.run.state == "idle")
    end
    panel.scroll.child:SetHeight(math.max(10, n * ROW_H + (more and 36 or 0)))
    panel.empty:SetShown(n == 0)
    panel.empty:SetText((detail and b.sel) and (b.sel.fresh and "None for sale." or "Looking it up...")
        or listMode and "This list is empty: type a name above and Add to list."
        or (b.query and b.run.state == "idle") and "Nothing found."
        or (browse and "Search by name, or pick a category." or "Search by name, or pick a list."))
    local p = b.Progress()            -- the bar says it; no text (it ran off the panel's edge: Alex)
    panel.bar:SetShown(p ~= nil)
    if p then
        local cr, cg, cb = T().Accent()
        panel.bar:SetStatusBarColor(cr, cg, cb, 1)
        panel.bar:SetValue(p)
    end
    DrawSelection()
end

--- A shift-clicked item (bags, links) while Buy is open searches for it
-- (Alex). Bag frames call HandleModifiedItemClick, chat links and some bag
-- addons ChatEdit_InsertLink -- both are watched; one click searches once.
local lastName, lastAt
local function FromLink(link)
    if not (UI.Shown() and type(link) == "string") then return end
    if IsShiftKeyDown and not IsShiftKeyDown() then return end
    -- an item or a caged pet only (a spell, quest or achievement link browsed its name: sweep 6)
    if not (link:find("|Hitem:", 1, true) or link:find("|Hbattlepet:", 1, true)) then return end
    local name = link:match("|h%[(.-)%]|h") or link:match("%[(.-)%]")
    if not name or name == "" then return end
    local now = (GetTime and GetTime()) or 0
    if name == lastName and lastAt and now - lastAt < 0.3 then return end
    lastName, lastAt = name, now
    panel.search:SetText(name)
    UI.detail = false                               -- out of a drill-down, to the new search
    B().Search(name)
end
UI.FromLink = FromLink

local hooked = false
local function Hook()
    if hooked or not hooksecurefunc then return end
    hooked = true
    for _, fn in ipairs({ "HandleModifiedItemClick", "ChatEdit_InsertLink" }) do
        if type(rawget(_G, fn)) == "function" then pcall(hooksecurefunc, fn, FromLink) end
    end
end

--- Out of a drill-down, back to the results.
function UI.Back()
    if not UI.detail then return end
    UI.detail = false
    UI.Refresh()
end

function UI.Show()
    if not Build() then return end
    Hook()
    B().Store()                                     -- the list saved last session picked now, not mid-browse (sweep 5)
    panel:Show()
    UI.Refresh()
end
function UI.Hide()
    if panel then
        panel:Hide()
        if panel.dialog then panel.dialog:Hide() end
    end
end
function UI.Shown() return panel ~= nil and panel:IsShown() end

ns.Buy.OnChange = function() UI.Refresh() end
AU().AddView({ key = "buy", label = "Buy", show = UI.Show, hide = UI.Hide, shown = UI.Shown })
