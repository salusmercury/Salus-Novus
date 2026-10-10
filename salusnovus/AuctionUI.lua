--[[ Salus Novus -- the Snipe tab on the auction house.

A "Snipe" button hangs under the AH window's bottom-right corner (Blizzard's
tabs sit bottom-left, and other addons append theirs there; ours stays out
of that row). It shows our own panel over the AH's content -- nothing of
Blizzard's tab system is touched -- and any Blizzard tab, or closing the
AH, puts the panel away.

  top      Scan, and what the last scan found
  list     items listed below what a vendor pays: listed, cheapest, vendor,
           profit each; a click looks the item's listings up
  bottom   the selected item: how many are under vendor, the cost, the
           profit; Buy (one click per purchase), then Confirm for
           materials once the client has quoted the price
]]

local _, ns = ...

local UI = {}
ns.AuctionUI = UI
local function A() return ns.Auction end
local function T() return ns.Theme end

local ROW_H, MAX_ROWS = 26, 200
-- { header, x, width, justify }: the last column ends by x = 730, inside
-- the AH window's list (the old 770 clipped "Profit each").
local COLS = {
    { "Item", 34, 246, "LEFT" }, { "Listed", 290, 60 }, { "Cheapest", 360, 110 },
    { "Vendor", 480, 110 }, { "Profit each", 600, 130 },
}
local panel, tabButton

local function Money(c)
    if not ns.Num(c) then return "?" end
    c = math.floor(c + 0.5)
    local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|cffffd100g|r" end
    if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
    if k > 0 or #parts == 0 then parts[#parts + 1] = k .. "|cffeda55fc|r" end
    return table.concat(parts, " ")
end
UI.Money = Money

local QUALITY = {
    [0] = { 0.62, 0.62, 0.62 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 },
    [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 },
}
UI.QUALITY = QUALITY

local asked = {}
local function ItemBits(id)
    local ci = C_Item or {}
    local okN, name = pcall(ci.GetItemNameByID or function() end, id)
    local okQ, q = pcall(ci.GetItemQualityByID or function() end, id)
    local okI, icon = pcall(ci.GetItemIconByID or function() end, id)
    name = okN and ns.Str(name) or nil
    if not name then
        -- The AH often knows the name before the item's data loads (Alex saw
        -- "Item 7420" down the Buy list): ask it, by the plain item key
        local ah = rawget(_G, "C_AuctionHouse")
        local okK, key = pcall(ah and ah.MakeItemKey or function() end, id)
        local okA, info = pcall(ah and ah.GetItemKeyInfo or function() end, okK and key or nil)
        if okA and type(info) == "table" then
            name = ns.Str(info.itemName)
            if not (okQ and ns.Num(q)) and ns.Num(info.quality) then okQ, q = true, info.quality end
            if not (okI and icon) and info.iconFileID then okI, icon = true, info.iconFileID end
        end
    end
    if not name and not asked[id] and ci.RequestLoadItemDataByID then
        asked[id] = true
        pcall(ci.RequestLoadItemDataByID, id)
    end
    return name or ("Item " .. id), QUALITY[okQ and ns.Num(q) and q or 1] or QUALITY[1], okI and icon or 134400
end

UI.ItemBits = function(id) return ItemBits(id) end

local function Cell(row, x, w, justify)
    local t = T().MakeText(row, 13, T().TEXT)
    t:SetPoint("LEFT", row, "LEFT", x, 0)
    t:SetWidth(w)
    t:SetJustifyH(justify or "RIGHT")
    t:SetWordWrap(false)
    return t
end

UI.Cell = function(...) return Cell(...) end

--- An item row's tooltip on hover (Alex), as on Blizzard's own AH: the
-- listed variant (level, suffix) when the client can, else the item.
function UI.ItemTip(owner, id, key, link)
    local tt = rawget(_G, "GameTooltip")
    if not (tt and owner and (id or link)) then return end
    tt:SetOwner(owner, "ANCHOR_RIGHT")
    if link and tt.SetHyperlink then tt:SetHyperlink(link)
    elseif type(key) == "table" and tt.SetItemKey and pcall(tt.SetItemKey, tt, key.itemID, key.itemLevel or 0, key.itemSuffix or 0) then
        -- shown
    elseif tt.SetItemByID then tt:SetItemByID(id) end
    tt:Show()
end
function UI.HideTip() local tt = rawget(_G, "GameTooltip") if tt then tt:Hide() end end
local function Hover(r, item)
    r:SetScript("OnEnter", function(self)
        local id, key, link = item(self)
        if id or link then UI.ItemTip(self, id, key, link) end
    end)
    r:SetScript("OnLeave", function() UI.HideTip() end)
end
UI.Hover = Hover

--- The AH tabs' scrollbars and progress bars, thick enough to grab (Alex):
-- one width for every tab.
UI.SCROLL_W, UI.BAR_H = 12, 6
function UI.Thick(sf)
    local s = sf and sf.slider
    if not s then return end
    local w = UI.SCROLL_W
    s:SetWidth(w)
    s:ClearAllPoints()
    s:SetPoint("TOPRIGHT", sf, "TOPRIGHT", w + 6, 0)
    s:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", w + 6, 0)
    if s.thumb then s.thumb:SetSize(w, 40) end
end

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
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.name = Cell(r, COLS[1][2], COLS[1][3], "LEFT")
    r.listed = Cell(r, COLS[2][2], COLS[2][3])
    r.price = Cell(r, COLS[3][2], COLS[3][3])
    r.vendor = Cell(r, COLS[4][2], COLS[4][3])
    r.profit = Cell(r, COLS[5][2], COLS[5][3])
    r:SetScript("OnClick", function(self) if self.snipe then A().Select(self.snipe) end end)
    Hover(r, function(self)
        local s = self.snipe
        if s then return s.id, { itemID = s.id, itemLevel = s.lvl, itemSuffix = s.sfx } end
    end)
    panel.rows[i] = r
    return r
end

local function Build()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if panel or not ahf then return panel end
    local Th = T()
    panel = CreateFrame("Frame", "SalusNovusSnipe", ahf)
    panel:SetPoint("TOPLEFT", ahf, "TOPLEFT", 4, -26)
    panel:SetPoint("BOTTOMRIGHT", ahf, "BOTTOMRIGHT", -4, 4)
    -- Above everything in the AH window: its own sub-tabs ("Auctions",
    -- "Bids") sit high enough to poke through a +50 panel (seen in game).
    pcall(panel.SetFrameStrata, panel, ahf:GetFrameStrata())
    panel:SetFrameLevel(math.min(9000, (ahf:GetFrameLevel() or 0) + 500))
    panel:EnableMouse(true)                          -- nothing clicks through to the AH under it
    panel.bg = Th.SolidTex(panel, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 1)
    panel.bg:SetAllPoints()
    panel:Hide()

    -- The scan's progress: an accent bar across the top while it runs.
    panel.bar = CreateFrame("StatusBar", nil, panel)
    panel.bar:SetHeight(UI.BAR_H)
    panel.bar:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    panel.bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    panel.bar:SetStatusBarTexture(Th.SOLID)
    panel.bar:SetMinMaxValues(0, 1)
    panel.bar.bg = Th.SolidTex(panel.bar, "BACKGROUND", 1, 1, 1, 0.06)
    panel.bar.bg:SetAllPoints()
    panel.bar:Hide()

    panel.scan = Th.MakeButton(panel)
    panel.scan:SetSize(90, 26)
    panel.scan:SetPoint("TOPLEFT", 12, -10)
    panel.scan:SetText("Scan")
    panel.scan:SetScript("OnClick", function(self) if self.enabledState then A().Scan() end end)
    panel.status = Th.MakeText(panel, 13, Th.TEXT_DIM)
    panel.status:SetPoint("LEFT", panel.scan, "RIGHT", 14, 0)

    local head = CreateFrame("Frame", nil, panel)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -46)
    head:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    for _, c in ipairs(COLS) do
        local t = Cell(head, c[2], c[3], c[4])
        t:SetTextColor(Th.TEXT_MUTE[1], Th.TEXT_MUTE[2], Th.TEXT_MUTE[3], 1)
        t:SetText(c[1])
    end

    panel.scroll = Th.MakeScrollArea(panel)
    panel.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 120)
    panel.scroll.child:SetWidth(740)
    UI.Thick(panel.scroll)
    panel.rows = {}
    panel.empty = Th.MakeText(panel.scroll.child, 14, Th.TEXT_MUTE)
    panel.empty:SetPoint("TOPLEFT", 6, -8)

    -- the selected item
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
    panel.selLine = Th.MakeText(foot, 13, Th.TEXT_DIM)
    panel.selLine:SetPoint("TOPLEFT", panel.selName, "BOTTOMLEFT", 0, -6)
    panel.selLine:SetPoint("RIGHT", foot, "RIGHT", -260, 0)
    panel.selLine:SetJustifyH("LEFT")
    panel.message = Th.MakeText(foot, 13, Th.TEXT_MUTE)
    panel.message:SetPoint("TOPLEFT", panel.selLine, "BOTTOMLEFT", 0, -4)
    panel.buy = Th.MakeButton(foot)
    panel.buy:SetSize(120, 30)
    panel.buy:SetPoint("RIGHT", foot, "RIGHT", 0, -4)
    panel.buy:SetPrimary(true)
    -- The purchase runs inside this click (the client requires it).
    panel.buy:SetScript("OnClick", function(self)
        if not self.enabledState then return end
        local sel = A().sel
        if sel and sel.quote then A().Confirm() else A().Buy() end
    end)
    panel.cancel = Th.MakeButton(foot)
    panel.cancel:SetSize(90, 30)
    panel.cancel:SetPoint("RIGHT", panel.buy, "LEFT", -8, 0)
    panel.cancel:SetText("Cancel")
    panel.cancel:SetScript("OnClick", function() A().Cancel() end)

    local o = function() return ns.db.auction end
    panel.strip = UI.Strip(panel, {
        { label = "Min profit each", money = true, min = 1, max = 100000,       -- gold, silver, copper; the options page's range
          get = function() return tonumber(o().minProfit) or 5 end, set = function(v) o().minProfit = v end },
        { label = "Scan on open", check = true,
          get = function() return o().autoScan ~= false end, set = function(v) o().autoScan = v end },
    })

    panel:SetScript("OnUpdate", function(self, dt)
        self.acc = (self.acc or 0) + (dt or 0)
        if self.acc < 1 then return end
        self.acc = 0
        UI.Status()
    end)
    return panel
end
UI.Build = Build

--- The line beside Scan.
function UI.Status()
    if not panel then return end
    local a = A()
    local p, total = a.Progress()
    panel.bar:SetShown(p ~= nil)
    panel.scan:SetEnabledState(p == nil)            -- greyed while a scan runs
    if p then
        local r, g, b = T().Accent()
        panel.bar:SetStatusBarColor(r, g, b, 1)
        panel.bar:SetValue(p)
        panel.status:SetText(("Scanning... page %d of ~%d"):format(a.scan.pages or 1, total))
        return
    end
    local s = a.Store()
    if not (s and s.lastScan) then panel.status:SetText("Not scanned yet") return end
    local ago = math.max(0, ((time and time()) or 0) - s.lastScan)
    local when = ago < 60 and ("%ds"):format(ago) or ago < 3600 and ("%dm"):format(ago / 60) or ("%dh"):format(ago / 3600)
    panel.status:SetText(("%d items, scanned %s ago"):format(s.lastCount or 0, when))
end

local function DrawSelection()
    local a = A()
    local sel = a.sel
    panel.message:SetText(a.message or "")
    if not sel then
        panel.selName:SetText("")
        panel.selLine:SetText("Click an item to see its listings.")
        panel.buy:Hide(); panel.cancel:Hide()
        return
    end
    local name, q = ItemBits(sel.id)
    panel.selName:SetText(name)
    panel.selName:SetTextColor(q[1], q[2], q[3], 1)
    if not sel.rows then
        panel.selLine:SetText("Looking it up...")
        panel.buy:Hide(); panel.cancel:Hide()
        return
    end
    local u = A().Under(sel) or { qty = 0, cost = 0, profit = 0 }    -- as of today's min profit (sweep 3)
    if u.qty == 0 then
        panel.selLine:SetText(("Nothing under vendor (%s each) any more."):format(Money(sel.vendor)))
        panel.buy:Hide(); panel.cancel:Hide()
        return
    end
    panel.selLine:SetText(("%d under vendor: costs %s, a vendor pays %s, profit %s"):format(
        u.qty, Money(u.cost), Money(sel.vendor * u.qty), Money(u.profit)))
    panel.buy:Show()
    if sel.quote then
        panel.buy:SetText("Confirm " .. Money(sel.quote.total))
        panel.cancel:Show()
    elseif sel.kind == "item" then
        local first
        for _, r in ipairs(sel.rows) do if r.unit <= A().Cap(sel) then first = r break end end   -- what the click buys
        panel.buy:SetText(first and ("Buy for " .. Money(first.buyout)) or "Buy")
        panel.cancel:Hide()
    else
        panel.buy:SetText(("Buy %d"):format(u.qty))
        panel.cancel:Hide()
    end
    panel.buy:SetEnabledState(not sel.pending and not sel.asked or sel.quote ~= nil)
end

function UI.Refresh()
    if not (panel and panel:IsShown()) then return end
    local list = A().Snipes()
    local n = math.min(#list, MAX_ROWS)
    for i = 1, n do
        local s = list[i]
        local r = Row(i)
        local name, q, icon = ItemBits(s.id)
        r.snipe = s
        r.icon:SetTexture(icon)
        r.name:SetText(name)
        r.name:SetTextColor(q[1], q[2], q[3], 1)
        r.listed:SetText(tostring(s.listed))
        r.price:SetText(Money(s.price))
        r.vendor:SetText(Money(s.vendor))
        r.profit:SetText("|cff4fd05f" .. Money(s.profit) .. "|r")
        r:Show()
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() panel.rows[i].snipe = nil end
    panel.scroll.child:SetHeight(math.max(10, n * ROW_H))
    local s = A().Store()
    panel.empty:SetShown(n == 0)
    panel.empty:SetText((s and s.lastScan) and "Nothing is listed below vendor price right now." or "Scan to find items listed below what a vendor pays.")
    UI.Status()
    DrawSelection()
    panel.strip:Update()
end

function UI.Show()
    if not Build() then return end
    panel:Show()
    UI.Refresh()
end
function UI.Hide() if panel then panel:Hide() end end
function UI.Shown() return panel ~= nil and panel:IsShown() end

-- The tabs under the AH window, right to left: { key, label, show, hide, shown }.
-- Each owns its own panel; opening one puts the others away.
UI.views = { { key = "snipe", label = "Snipe", show = UI.Show, hide = UI.Hide, shown = UI.Shown } }
-- Left to right under the AH (Alex): Buy, Sell, Cancel, Investing, Snipe
UI.ORDER = { buy = 1, sell = 2, cancel = 3, invest = 4, snipe = 5 }
UI.buttons = {}
function UI.AddView(v) table.insert(UI.views, v) end
function UI.HideAll() for _, v in ipairs(UI.views) do v.hide() end end
--- Scanning runs only while Snipe or Investing is showing (Alex).
function UI.Gate()
    local on = false
    for _, v in ipairs(UI.views) do
        if (v.key == "snipe" or v.key == "invest") and v.shown() then on = true end
    end
    if ns.Auction.SetPaused then ns.Auction.SetPaused(not on) end
    if ns.Invest and ns.Invest.SetPaused then ns.Invest.SetPaused(not on) end
end

local function Lit()
    UI.Gate()
    for _, b in ipairs(UI.buttons) do
        if b.SetPrimary then
            local on = false
            for _, v in ipairs(UI.views) do if v.key == b.view and v.shown() then on = true end end
            b:SetPrimary(on)
        end
    end
end

--- A tab button: open that view, or put it away if it's the one showing.
function UI.Open(key)
    for _, v in ipairs(UI.views) do
        if v.key == key then
            local was = v.shown()
            UI.HideAll()
            if not was then v.show() end
        end
    end
    Lit()
end

--- Show a view (not a toggle: the probe opening Investing mustn't close it).
function UI.Show(key)
    for _, v in ipairs(UI.views) do
        if v.key == key and not v.shown() then UI.HideAll() v.show() end
    end
    Lit()
end

--- The button under the AH window, and the hooks that put the panel away.
local function Attach()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if not ahf or tabButton then return end
    local Th = T()
    -- Laid out from the right edge, last first, so they read in UI.ORDER
    -- left to right.
    local views = {}
    for _, v in ipairs(UI.views) do views[#views + 1] = v end
    table.sort(views, function(a, b) return (UI.ORDER[a.key] or 99) < (UI.ORDER[b.key] or 99) end)
    local anchor
    local made = {}
    for i = #views, 1, -1 do
        local v = views[i]
        local b = Th.MakeButton(ahf)
        b:SetSize(96, 28)
        if anchor then b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
        else b:SetPoint("TOPRIGHT", ahf, "BOTTOMRIGHT", -8, 2) end
        b:SetText(v.label)
        b.view = v.key
        -- shows its tab, never hides it (a second click hid ours and left
        -- Blizzard's AH showing -- Alex)
        b:SetScript("OnClick", function() UI.Show(v.key) end)
        made[i] = b
        if v.key == "snipe" then tabButton = b end
        anchor = b
    end
    for i = 1, #views do UI.buttons[#UI.buttons + 1] = made[i] end      -- left to right
    UI.tabButton = tabButton
    local function Away() UI.HideAll() UI.Open(nil) end
    for _, tab in ipairs(ahf.Tabs or {}) do
        if tab.HookScript then
            tab:HookScript("OnClick", Away)
            -- Ours replace Blizzard's (Alex): kept hidden while the module is on
            tab:HookScript("OnShow", function(self) if A().Enabled() then self:Hide() end end)
        end
    end
    ahf:HookScript("OnHide", Away)
    -- Each opening lands on our Buy tab (after Blizzard's own OnShow has set
    -- its display, which would put ours away)
    ahf:HookScript("OnShow", function() if A().Enabled() then UI.Show("buy") end end)
    -- Any switch of the AH's own display puts ours away, however it came
    -- (a right-clicked bag item goes to Blizzard's Sell display, no tab click)
    if type(ahf.SetDisplayMode) == "function" then pcall(hooksecurefunc, ahf, "SetDisplayMode", Away) end
end
UI.Attach = Attach

-- ------------------------------------------------------------ settings strip

--- The panel's settings, mirrored from the options page in a strip above
-- the bottom (Alex: easier to change them where they're used). `fields`:
--   { label, width, get = fn -> number, set = fn(number), min, max, scale }
--     a box you type in; Enter or clicking away saves, clamped to min..max
--     and rounded to 1/`scale` (1 = whole numbers, 10000 = gold to the copper)
--   { label, check = true, get = fn -> bool, set = fn(bool) }
-- Each change saves and runs ApplyAll (which redraws the panels).
function UI.Strip(panel, fields)
    local Th = T()
    local strip = CreateFrame("Frame", nil, panel)
    strip:SetHeight(24)
    strip:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 12, 88)
    strip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -12, 88)
    strip.items = {}
    local prev
    for _, f in ipairs(fields) do
        local it
        if f.check then
            it = Th.MakeLabelledCheckBox(strip, f.label, 16)
            it:SetPoint("LEFT", prev or strip, prev and "RIGHT" or "LEFT", prev and 22 or 0, 0)
            it:SetScript("OnClick", function(self)
                if not self.enabledState then return end
                f.set(not self:GetChecked())
                ns.ApplyAll()
            end)
            it.Update = function(self) self:SetChecked(f.get()) end
            prev = it.label
        elseif f.money then
            -- An amount of money: gold, silver and copper boxes (Alex: not
            -- just copper); silver/copper over 99 carry
            local lab = Th.MakeText(strip, 13, Th.TEXT_DIM)
            lab:SetText(f.label)
            lab:SetPoint("LEFT", prev or strip, prev and "RIGHT" or "LEFT", prev and 22 or 0, 0)
            it = CreateFrame("Frame", nil, strip)
            it:SetSize(150, 22)
            it:SetPoint("LEFT", lab, "RIGHT", 6, 0)
            it.label, it.parts = lab, {}
            local last
            for k, spec in ipairs({ { 40, "|cffffd100g|r" }, { 30, "|cffc7c7cfs|r" }, { 30, "|cffeda55fc|r" } }) do
                local eb = Th.MakeEditBox(it, spec[1])
                eb:SetTextInsets(4, 4, 0, 0)
                if last then eb:SetPoint("LEFT", last, "RIGHT", 12, 0) else eb:SetPoint("LEFT", it, "LEFT", 0, 0) end
                local unit = Th.MakeText(it, 12, Th.TEXT_DIM)
                unit:SetPoint("LEFT", eb, "RIGHT", 2, 0)
                unit:SetText(spec[2])
                it.parts[k] = eb
                last = eb
            end
            local function Focused() for _, eb in ipairs(it.parts) do if eb:HasFocus() == true then return true end end end
            it.Update = function(self)
                if Focused() then return end
                local v = math.floor(f.get() or 0)
                self.parts[1]:SetText(tostring(math.floor(v / 10000)))
                self.parts[2]:SetText(tostring(math.floor(v / 100) % 100))
                self.parts[3]:SetText(tostring(v % 100))
            end
            local function Commit()
                if it.escaping then it.escaping = nil it:Update() return end   -- Escape: nothing saved (the sweep)
                local n = {}
                for k, eb in ipairs(it.parts) do
                    local t = (eb:GetText() or ""):match("^%s*(.-)%s*$")
                    n[k] = t == "" and 0 or tonumber(t:match("^(%d+)$"))
                end
                if n[1] and n[2] and n[3] then
                    local v = math.max(f.min or 0, math.min(f.max or math.huge, n[1] * 10000 + n[2] * 100 + n[3]))
                    if v ~= f.get() then f.set(v) ns.ApplyAll() end
                end
                it:Update()
            end
            for _, eb in ipairs(it.parts) do
                eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                eb:SetScript("OnEditFocusLost", Commit)
                eb:SetScript("OnEscapePressed", function(self) it.escaping = true self:ClearFocus() it.escaping = nil it:Update() end)
            end
            prev = it.parts[3]
        else
            local lab = Th.MakeText(strip, 13, Th.TEXT_DIM)
            lab:SetText(f.label)
            lab:SetPoint("LEFT", prev or strip, prev and "RIGHT" or "LEFT", prev and 22 or 0, 0)
            it = Th.MakeEditBox(strip, f.width or 56)
            it:SetPoint("LEFT", lab, "RIGHT", 6, 0)
            it.label = lab
            local scale = f.scale or 1
            it.Update = function(self)
                if self:HasFocus() == true then return end          -- not while typing in it
                local v = f.get()
                self:SetText(scale == 1 and ("%d"):format(v) or (("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")))
            end
            local function Commit(self)
                local v = tonumber((self:GetText() or ""):match("^%s*(%d*%.?%d+)%s*$"))   -- "1,000" isn't 1
                if v then
                    v = math.floor(v * scale + 0.5) / scale
                    v = math.max(f.min or 0, math.min(f.max or v, v))
                    if v ~= f.get() then f.set(v) ns.ApplyAll() end
                end
                self:Update()                                     -- a bad entry puts the value back
            end
            it:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            it:SetScript("OnEditFocusLost", Commit)
            it:SetScript("OnEscapePressed", function(self)
                self:SetText("")                                  -- nothing to save
                self:ClearFocus()
                self:Update()
            end)
            prev = it
        end
        strip.items[#strip.items + 1] = it
    end
    function strip:Update() for _, it in ipairs(self.items) do it:Update() end end
    return strip
end

--- Blizzard's Buy / Sell / Auctions tabs: hidden while ours are on.
function UI.BlizzardTabs(show)
    local ahf = rawget(_G, "AuctionHouseFrame")
    for _, tab in ipairs(ahf and ahf.Tabs or {}) do
        if tab.SetShown then tab:SetShown(show) end
    end
    -- a bigger close X while ours are up (Alex)
    local x = ahf and ahf.CloseButton
    if type(x) == "table" and x.SetScale then x:SetScale(show and 1 or 1.5) end
end

function UI.Apply()
    local on = A().Enabled()
    if on and #UI.buttons == 0 and A().IsOpen() then Attach() end   -- switched on with the AH open
    for _, b in ipairs(UI.buttons) do b:SetShown(on) end
    if #UI.buttons > 0 then UI.BlizzardTabs(not on) end
    if not on then
        UI.HideAll() Lit()
        -- a held quote is dropped: off, it cancelled Blizzard's own purchase (sweep 5)
        local p = A().purchase
        if p and not p.confirming then
            if p.owner == "invest" and ns.Invest then ns.Invest.Cancel()
            elseif p.owner == "snipe" then A().Cancel()
            elseif p.owner == "buy" and ns.Buy then ns.Buy.Cancel() end
        end
    end
    UI.Refresh()                                   -- a setting changed: min profit, scan on open
end
ns.RegisterApply(UI.Apply, "Auction")

ns.Auction.OnChange = function()
    UI.Refresh()
    if ns.InvestUI then ns.InvestUI.Refresh() end      -- its progress rides the scan too
end
ns.On("AUCTION_HOUSE_SHOW", function()
    if not A().Enabled() then return end
    local first = #UI.buttons == 0
    Attach()
    UI.Apply()
    -- the first opening: the OnShow hook came too late for it
    if first then
        if C_Timer and C_Timer.After then C_Timer.After(0, function() if A().IsOpen() then UI.Show("buy") end end)
        else UI.Show("buy") end
    end
end)
-- Item names arriving: one redraw for the lot, not one per item.
local queued = false
--- Names in: whichever AH tab is showing redraws (only Snipe did).
local function Redraw()
    if queued then return end
    local any = false
    for _, v in ipairs(UI.views) do if v.shown() then any = true end end
    if not any then return end
    queued = true
    local function Go()
        queued = false
        UI.Refresh()
        for _, m in ipairs({ ns.BuyUI, ns.SellUI, ns.CancelUI, ns.InvestUI }) do if m and m.Shown and m.Shown() then m.Refresh() end end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, Go) else Go() end
end
ns.On("ITEM_DATA_LOAD_RESULT", Redraw)
ns.On("ITEM_KEY_ITEM_INFO_RECEIVED", Redraw)
ns.On("GET_ITEM_INFO_RECEIVED", Redraw)
