--[[ Salus Novus -- the Sell tab on the auction house.

  left     your bags as icons, grouped: recipes, weapons, armor, containers,
           consumables, trade goods, other (item tooltip on hover)
  right    the clicked item's live listings (cheapest first, yours marked),
           the price each (by Sell's rules, or what you type), quantity
           (everything you have), duration (8h until you pick another)
  bottom   what it posts for, what you get after the cut, the deposit; Post
           (inside your click), and the next item comes up on its own
]]

local _, ns = ...

local UI = {}
ns.SellUI = UI
local function S() return ns.Sell end
local function AU() return ns.AuctionUI end
local function T() return ns.Theme end

local ICON, GAP, PER_ROW, GRID_W = 38, 4, 5, 214     -- bigger icons (Alex)
local LADDER_ROWS = 7
local LADDER_H, LADDER_FONT = 22, 15     -- a bit bigger (Alex)
local panel

local function Money(c) return AU().Money(c) end

-- ------------------------------------------------------------ the grid

--- Whatever is half typed in the price or amount boxes is dropped, not
-- committed: another item picked, a ladder row clicked, Escape (sweep 3 --
-- the old item's digits were dropped or overrode the click; Escape saved).
local function Drop()
    if not panel then return end
    if panel.price then
        panel.price.typed, panel.price.forSel = false, nil
        for _, eb in ipairs(panel.price.parts) do if eb:HasFocus() == true then eb:ClearFocus() end end
    end
    if panel.qty then
        panel.qty.forSel = nil
        if panel.qty:HasFocus() == true then panel.qty:ClearFocus() end
    end
end
UI.Drop = Drop

local function Icon(i)
    local p = panel.icons[i]
    if p then return p end
    local Th = T()
    p = CreateFrame("Button", nil, panel.grid.child)
    p:SetSize(ICON, ICON)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetAllPoints()
    p.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    p.count = Th.MakeText(p, 11, Th.TEXT, "OUTLINE")
    p.count:SetPoint("BOTTOMRIGHT", -1, 1)
    p.border = Th.Border(p)
    p.border:Layout(p, 1, 0)
    p.border:Show()
    p.ring = Th.Border(p)
    p.ring:Layout(p, 2, -2)
    p:SetScript("OnClick", function(self) if self.entry then Drop() S().Select(self.entry) end end)
    p:SetScript("OnEnter", function(self)
        local e = self.entry
        if not (e and GameTooltip) then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")          -- out past the AH's edge, not over the listings (Alex)
        local l = e.locs[1]
        if l and GameTooltip.SetBagItem then GameTooltip:SetBagItem(l.bag, l.slot)
        elseif e.link then GameTooltip:SetHyperlink(e.link) end
        GameTooltip:Show()
    end)
    p:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    panel.icons[i] = p
    return p
end

local function Header(i)
    local h = panel.heads[i]
    if h then return h end
    h = T().MakeText(panel.grid.child, 12, T().TEXT_MUTE)
    panel.heads[i] = h
    return h
end

local function DrawGrid()
    local items = S().items
    local sel = S().sel
    local y, n, nh = 0, 0, 0
    local group
    local col = 0
    for _, e in ipairs(items) do
        if e.group ~= group then
            if group then y = y + ICON + GAP + 6 end
            group, col = e.group, 0
            nh = nh + 1
            local h = Header(nh)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", panel.grid.child, "TOPLEFT", 0, -y)
            h:SetText(S().GROUPS[e.group] or "")
            h:Show()
            y = y + 16
        elseif col == PER_ROW then
            col = 0
            y = y + ICON + GAP
        end
        n = n + 1
        local p = Icon(n)
        p.entry = e
        p:ClearAllPoints()
        p:SetPoint("TOPLEFT", panel.grid.child, "TOPLEFT", 2 + col * (ICON + GAP), -y)
        p.tex:SetTexture(e.icon or 134400)
        p.count:SetText(e.count > 1 and tostring(e.count) or "")
        local _, q = AU().ItemBits(e.id)
        if e.quality and AU().QUALITY and AU().QUALITY[e.quality] then q = AU().QUALITY[e.quality] end
        p.border:SetColor(q[1], q[2], q[3], 0.9)
        local on = sel ~= nil and sel.entry ~= nil and sel.entry.key == e.key     -- that very version, not every suffix of it
        if on then
            local r, g, b = T().Accent()
            p.ring:SetColor(r, g, b, 1)
            p.ring:Show()
        else
            p.ring:Hide()
        end
        p.selected = on
        p:Show()
        col = col + 1
    end
    for i = n + 1, #panel.icons do panel.icons[i]:Hide() panel.icons[i].entry = nil end
    for i = nh + 1, #panel.heads do panel.heads[i]:Hide() end
    panel.grid.child:SetHeight(math.max(10, y + ICON + GAP))
    panel.empty:SetShown(n == 0)
end

-- ------------------------------------------------------------ the price box

--- Gold, silver and copper boxes; typing in any of them sets the price.
local function MoneyBox(parent)
    local Th = T()
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(170, 22)
    box.parts = {}
    local prev
    -- Wide enough for two digits (Alex: 99c showed as "9", the box scrolled)
    for i, spec in ipairs({ { "g", 50, "|cffffd100g|r" }, { "s", 38, "|cffc7c7cfs|r" }, { "c", 38, "|cffeda55fc|r" } }) do
        local eb = Th.MakeEditBox(box, spec[2])
        eb:SetTextInsets(5, 5, 0, 0)
        eb.width = spec[2]
        if prev then eb:SetPoint("LEFT", prev, "RIGHT", 14, 0) else eb:SetPoint("LEFT", box, "LEFT", 0, 0) end
        local unit = Th.MakeText(box, 12, Th.TEXT_DIM)
        unit:SetPoint("LEFT", eb, "RIGHT", 3, 0)
        unit:SetText(spec[3])
        box.parts[i] = eb
        box.lastUnit = unit
        prev = eb
    end
    -- Silver and copper over 99 carry (150s is 1g 50s), and a value typed for
    -- one item never lands on the next (the box can lose focus after a post).
    local function Commit()
        local v = {}
        for i, eb in ipairs(box.parts) do v[i] = tonumber((eb:GetText() or ""):match("^%s*(%d+)")) or 0 end
        local c = v[1] * 10000 + v[2] * 100 + v[3]
        local sel = S().sel
        -- only what was TYPED counts: digits left on screen while a reprice
        -- landed (the box keeps them while focused) aren't a price (the sweep)
        if sel and sel == box.forSel and box.typed and c > 0 and c ~= sel.price then S().SetPrice(c) else box:Set(sel and sel.price) end
        box.typed = false
    end
    for _, eb in ipairs(box.parts) do
        eb:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()                            -- typing replaces it (Alex)
            box.forSel = S().sel
        end)
        eb:SetScript("OnTextChanged", function(self, user)
            if not user then return end
            box.typed = true
            box.forSel = S().sel                            -- for the item it's typed for
            -- Post takes a click now (a disabled button gets none, so a price
            -- typed where nothing is listed could never be posted: the sweep)
            local sel = S().sel
            if panel and panel.post and sel and sel.fresh then panel.post:SetEnabledState(true) end
        end)
        eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        eb:SetScript("OnEscapePressed", function() Drop() end)
        eb:SetScript("OnEditFocusLost", Commit)
    end
    function box:Set(c)
        for _, eb in ipairs(self.parts) do if eb:HasFocus() == true then return end end
        if not ns.Num(c) then for _, eb in ipairs(self.parts) do eb:SetText("") end return end
        self.parts[1]:SetText(tostring(math.floor(c / 10000)))
        self.parts[2]:SetText(tostring(math.floor(c / 100) % 100))
        self.parts[3]:SetText(tostring(c % 100))
    end
    return box
end

-- ------------------------------------------------------------ the panel

local function Build()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if panel or not ahf then return panel end
    local Th = T()
    panel = CreateFrame("Frame", "SalusNovusSell", ahf)
    panel:SetPoint("TOPLEFT", ahf, "TOPLEFT", 4, -26)
    panel:SetPoint("BOTTOMRIGHT", ahf, "BOTTOMRIGHT", -4, 4)
    pcall(panel.SetFrameStrata, panel, ahf:GetFrameStrata())
    panel:SetFrameLevel(math.min(9000, (ahf:GetFrameLevel() or 0) + 500))
    panel:EnableMouse(true)
    panel.bg = Th.SolidTex(panel, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 1)
    panel.bg:SetAllPoints()
    panel:Hide()

    -- left: the bags
    panel.grid = Th.MakeScrollArea(panel)
    panel.grid:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -14)
    panel.grid:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 92)
    panel.grid:SetWidth(GRID_W + 10)
    panel.grid.child:SetWidth(GRID_W)
    AU().Thick(panel.grid)
    panel.icons, panel.heads = {}, {}
    panel.empty = Th.MakeText(panel.grid.child, 13, Th.TEXT_MUTE)
    panel.empty:SetPoint("TOPLEFT", 0, -4)
    panel.empty:SetWidth(GRID_W)
    panel.empty:SetJustifyH("LEFT")
    panel.empty:SetText("Nothing in your bags the auction house will take.")
    panel.split = Th.SolidTex(panel, "ARTWORK", 1, 1, 1, 0.08)
    panel.split:SetWidth(1)
    panel.split:SetPoint("TOPLEFT", panel.grid, "TOPRIGHT", 8, 0)
    panel.split:SetPoint("BOTTOMLEFT", panel.grid, "BOTTOMRIGHT", 8, 0)

    -- right: the item, its listings, the post
    local right = CreateFrame("Frame", nil, panel)
    right:SetPoint("TOPLEFT", panel.grid, "TOPRIGHT", 22, 0)
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 92)
    panel.right = right
    panel.name = Th.MakeText(right, 15, Th.TEXT)
    panel.name:SetPoint("TOPLEFT", 0, 0)
    panel.pick = Th.MakeText(right, 13, Th.TEXT_MUTE)
    panel.pick:SetPoint("TOPLEFT", 0, -2)
    panel.pick:SetText("Pick something from your bags to sell.")

    local head = CreateFrame("Frame", nil, right)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", right, "TOPLEFT", 0, -28)
    head:SetPoint("RIGHT", right, "RIGHT", 0, 0)
    panel.head = head
    local cols = { { "Supply", 0, 60 }, { "Price", 80, 120 }, { "Yours", 220, 70 } }   -- supply first (Alex)
    for _, c in ipairs(cols) do
        local t = AU().Cell(head, c[2], c[3], c[4])
        T().SetFont(t, LADDER_FONT - 1)
        t:SetTextColor(Th.TEXT_MUTE[1], Th.TEXT_MUTE[2], Th.TEXT_MUTE[3], 1)
        t:SetText(c[1])
    end
    panel.ladder = {}
    for i = 1, LADDER_ROWS do
        local r = CreateFrame("Button", nil, right)
        r:SetHeight(LADDER_H)
        r:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -(i - 1) * LADDER_H)
        r:SetPoint("RIGHT", head, "RIGHT", 0, 0)
        r.hl = Th.SolidTex(r, "HIGHLIGHT", 1, 1, 1, 0.07)
        r.hl:SetAllPoints()
        r.on = Th.SolidTex(r, "BACKGROUND", 1, 1, 1, 0.12)
        r.on:SetAllPoints()
        r.on:Hide()
        -- A click prices 1c under this row (Alex)
        r:SetScript("OnClick", function(self) if self.unit then Drop() S().Undercut(self.unit, self.mine) end end)
        r.cells = {}
        for k, c in ipairs(cols) do
            r.cells[k] = AU().Cell(r, c[2], c[3], c[4])
            T().SetFont(r.cells[k], LADDER_FONT)
        end
        panel.ladder[i] = r
    end
    panel.lookup = Th.MakeText(right, 13, Th.TEXT_MUTE)
    panel.lookup:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)

    local y0 = -28 - 20 - LADDER_ROWS * LADDER_H - 14
    local function Label(text, y)
        local l = Th.MakeText(right, 13, Th.TEXT_DIM)
        l:SetPoint("TOPLEFT", right, "TOPLEFT", 0, y - 4)
        l:SetText(text)
        return l
    end
    Label("Price", y0)
    panel.price = MoneyBox(right)
    panel.price:SetPoint("TOPLEFT", right, "TOPLEFT", 90, y0)
    -- the market's under the vendor floor: selling to a vendor pays more (Alex)
    panel.vendorCue = Th.MakeText(right, 12, Th.TEXT_MUTE)
    panel.vendorCue:SetPoint("LEFT", panel.price.lastUnit, "RIGHT", 14, 0)
    panel.vendorCue:SetText("Vendor pays more")
    panel.vendorCue:Hide()

    Label("Quantity", y0 - 30)
    panel.qty = Th.MakeEditBox(right, 56)
    panel.qty:SetPoint("TOPLEFT", right, "TOPLEFT", 90, y0 - 30)
    panel.qty:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()                                -- typing replaces it (Alex)
        self.forSel = S().sel
    end)
    panel.qty:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    panel.qty:SetScript("OnEscapePressed", function() Drop() end)
    panel.qty:SetScript("OnTextChanged", function(self, user) if user then self.forSel = S().sel end end)
    panel.qty:SetScript("OnEditFocusLost", function(self)
        local n = tonumber((self:GetText() or ""):match("^%s*(%d+)"))
        if n and S().sel == self.forSel then S().SetQty(n) end
        UI.Refresh()
    end)
    panel.of = Th.MakeText(right, 12, Th.TEXT_MUTE)
    panel.of:SetPoint("LEFT", panel.qty, "RIGHT", 8, 0)

    Label("Duration", y0 - 60)
    panel.dur = {}
    local prev
    for d, h in ipairs(S().HOURS) do
        local b = Th.MakeButton(right)
        b:SetSize(48, 24)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 6, 0) else b:SetPoint("TOPLEFT", right, "TOPLEFT", 90, y0 - 60) end
        b:SetText(h .. "h")
        b:SetScript("OnClick", function() S().SetDuration(d) end)
        panel.dur[d] = b
        prev = b
    end

    -- bottom
    local foot = CreateFrame("Frame", nil, panel)
    foot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 10)
    foot:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 10)
    foot:SetHeight(72)
    foot.line = Th.SolidTex(foot, "ARTWORK", 1, 1, 1, 0.08)
    foot.line:SetHeight(1)
    foot.line:SetPoint("TOPLEFT")
    foot.line:SetPoint("TOPRIGHT")
    panel.selLine = Th.MakeText(foot, 13, Th.TEXT_DIM)
    panel.selLine:SetPoint("TOPLEFT", 0, -14)
    panel.selLine:SetPoint("RIGHT", foot, "RIGHT", -150, 0)
    panel.selLine:SetJustifyH("LEFT")
    panel.message = Th.MakeText(foot, 13, Th.TEXT_MUTE)
    panel.message:SetPoint("TOPLEFT", panel.selLine, "BOTTOMLEFT", 0, -6)
    panel.post = Th.MakeButton(foot)
    panel.post:SetSize(130, 30)
    panel.post:SetPoint("RIGHT", foot, "RIGHT", 0, -4)
    panel.post:SetPrimary(true)
    -- The post runs inside this click (the client requires it).
    panel.post:SetScript("OnClick", function(self)
        -- A box still being typed in counts first (clicking a button doesn't
        -- take its focus): post what's on screen, not what was there before.
        for _, eb in ipairs(panel.price.parts) do if eb:HasFocus() == true then eb:ClearFocus() end end
        if panel.qty:HasFocus() == true then panel.qty:ClearFocus() end
        if not self.enabledState then return end
        S().Post()
    end)
    return panel
end
UI.Build = Build

local function DrawItem()
    local s = S()
    panel.vendorCue:Hide()
    local sel = s.sel
    local show = sel ~= nil
    panel.pick:SetShown(not show)
    for _, f in ipairs({ panel.name, panel.head, panel.price, panel.qty, panel.of, panel.lookup }) do f:SetShown(show) end
    for _, b in ipairs(panel.dur) do b:SetShown(show) end
    for d, b in ipairs(panel.dur) do b:SetPrimary(d == s.Duration()) end
    panel.message:SetText(s.message or "")
    panel.post:SetShown(show)
    for i = 1, LADDER_ROWS do panel.ladder[i]:Hide() end
    if not sel then panel.selLine:SetText("") return end
    local name, q = AU().ItemBits(sel.id)
    panel.name:SetText(("%s  |cff8a8a96x%d|r"):format(name, sel.entry.count))
    panel.name:SetTextColor(q[1], q[2], q[3], 1)
    panel.lookup:SetText(sel.fresh and (#sel.levels == 0 and "Nothing listed" or "") or "Looking it up...")
    -- One row per price: an item's copies are separate auctions (seven
    -- Mining Picks at 1s read as seven rows)
    local levels, at = {}, {}
    for _, l in ipairs(sel.levels) do
        local row = at[l.unit]
        if row then row.qty, row.mine = row.qty + l.qty, row.mine or l.mine
        else row = { unit = l.unit, qty = l.qty, mine = l.mine } at[l.unit] = row levels[#levels + 1] = row end
    end
    table.sort(levels, function(a, b) return a.unit < b.unit end)
    for i = 1, math.min(LADDER_ROWS, #levels) do
        local r, l = panel.ladder[i], levels[i]
        r.cells[1]:SetText(tostring(l.qty))
        r.cells[2]:SetText(Money(l.unit))
        r.cells[3]:SetText(l.mine and "|cff4fd05fyours|r" or "")
        r.unit, r.mine = l.unit, l.mine
        local on = sel.level == l.unit
        if on then
            local cr, cg, cb = T().Accent()
            r.on:SetVertexColor(cr, cg, cb, 0.25)
        end
        r.on:SetShown(on)
        r.selected = on
        r:Show()
    end
    panel.price:Set(sel.price)
    -- the 1c-under price lands below the vendor floor: the market won't beat a vendor
    local _, mwhy = s.Price(sel.levels or {}, s.Vendor(sel.id))
    panel.vendorCue:SetShown(sel.fresh and mwhy == "floor" and true or false)
    if panel.qty:HasFocus() ~= true then panel.qty:SetText(tostring(sel.qty)) end
    panel.of:SetText(("of %d"):format(sel.entry.count))
    if sel.fresh and ns.Num(sel.price) then
        local total = sel.qty * sel.price
        local dep = s.Deposit()
        panel.selLine:SetText(("Post %d at %s: %s, you get %s after the cut.%s"):format(sel.qty, Money(sel.price), Money(total),
            Money(s.Net(sel.qty, sel.price)), dep and (" Deposit " .. Money(dep) .. ".") or ""))
    else
        panel.selLine:SetText("")
    end
    panel.post:SetText(sel.confirm and "Confirm post" or "Post")
    panel.post:SetEnabledState(sel.fresh and ns.Num(sel.price) and sel.price > 0 and true or false)
end

function UI.Refresh()
    if not (panel and panel:IsShown()) then return end
    DrawGrid()
    DrawItem()
end

function UI.Show()
    if not Build() then return end
    panel:Show()
    S().Refresh()
    -- Coming back: look the item up again (its listings may have moved)
    if S().sel then S().Select(S().sel.entry)
    elseif S().items[1] then S().Select(S().items[1]) end
    UI.Refresh()
end
function UI.Hide() if panel then panel:Hide() end end
function UI.Shown() return panel ~= nil and panel:IsShown() end

ns.Sell.OnChange = function() UI.Refresh() end
AU().AddView({ key = "sell", label = "Sell", show = UI.Show, hide = UI.Hide, shown = UI.Shown })
