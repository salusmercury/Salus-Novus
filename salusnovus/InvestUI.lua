--[[ Salus Novus -- the Investing tab on the auction house.

  top      Scan (an AH scan, then one search per qualifying commodity), the
           progress, and the budget: N% of your gold
  list     each commodity worth it: listed, buy (qty), cost, relist at,
           profit, margin -- widest margin first
  bottom   the clicked commodity, re-searched fresh: "Buy N for X, relist
           at Y: +Z (M%)"; Buy, then Confirm once the client has quoted
]]

local _, ns = ...

local UI = {}
ns.InvestUI = UI
local function I() return ns.Invest end
local function AU() return ns.AuctionUI end
local function T() return ns.Theme end

local ROW_H, MAX_ROWS = 26, 200
local COLS = {
    { "Item", 34, 168, "LEFT" }, { "Listed", 206, 52 }, { "Buy", 262, 52 }, { "Share", 318, 50 },
    { "Cost", 372, 90 }, { "Relist at", 466, 84 }, { "Profit", 554, 90 }, { "Margin", 648, 56 },
}
local panel

local function Money(c) return AU().Money(c) end

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
    r.cells = {}
    for k, c in ipairs(COLS) do r.cells[k] = AU().Cell(r, c[2], c[3], c[4]) end
    r:SetScript("OnClick", function(self) if self.result then I().Select(self.result) end end)
    AU().Hover(r, function(self) if self.result then return self.result.id end end)
    panel.rows[i] = r
    return r
end

local function Build()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if panel or not ahf then return panel end
    local Th = T()
    panel = CreateFrame("Frame", "SalusNovusInvest", ahf)
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

    panel.scan = Th.MakeButton(panel)
    panel.scan:SetSize(90, 26)
    panel.scan:SetPoint("TOPLEFT", 12, -10)
    panel.scan:SetText("Scan")
    panel.scan:SetScript("OnClick", function(self) if self.enabledState then I().Scan() end end)
    panel.status = Th.MakeText(panel, 13, Th.TEXT_DIM)
    panel.status:SetPoint("LEFT", panel.scan, "RIGHT", 14, 0)

    local head = CreateFrame("Frame", nil, panel)
    head:SetHeight(20)
    head:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -46)
    head:SetPoint("RIGHT", panel, "RIGHT", -28, 0)
    for _, c in ipairs(COLS) do
        local t = AU().Cell(head, c[2], c[3], c[4])
        t:SetTextColor(Th.TEXT_MUTE[1], Th.TEXT_MUTE[2], Th.TEXT_MUTE[3], 1)
        t:SetText(c[1])
    end
    panel.scroll = Th.MakeScrollArea(panel)
    panel.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 120)
    panel.scroll.child:SetWidth(740)
    AU().Thick(panel.scroll)
    panel.rows = {}
    panel.empty = Th.MakeText(panel.scroll.child, 14, Th.TEXT_MUTE)
    panel.empty:SetPoint("TOPLEFT", 6, -8)
    panel.empty:SetPoint("RIGHT", panel.scroll.child, "RIGHT", -6, 0)
    panel.empty:SetJustifyH("LEFT")

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
    panel.selLine:SetPoint("RIGHT", foot, "RIGHT", -230, 0)
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
        local sel = I().sel
        if sel and sel.quote then I().Confirm() else I().Buy() end
    end)
    panel.cancel = Th.MakeButton(foot)
    panel.cancel:SetSize(90, 30)
    panel.cancel:SetPoint("RIGHT", panel.buy, "LEFT", -8, 0)
    panel.cancel:SetText("Cancel")
    panel.cancel:SetScript("OnClick", function() I().Cancel() end)

    local o = function() return ns.db.auction end
    panel.strip = AU().Strip(panel, {
        { label = "Budget %", width = 44, min = 1, max = 100,
          get = function() return tonumber(o().investPct) or 20 end, set = function(v) o().investPct = v end },
        { label = "Min listed", width = 56, min = 50, max = 2000,                -- the options page's ranges
          get = function() return tonumber(o().investMinListed) or 250 end, set = function(v) o().investMinListed = v end },
        { label = "Min profit (g)", width = 56, min = 0, max = 100, scale = 10000,
          get = function() return tonumber(o().investMinProfit) or 1 end, set = function(v) o().investMinProfit = v end },
        { label = "Max share %", width = 44, min = 1, max = 100,
          get = function() return tonumber(o().investMaxShare) or 10 end, set = function(v) o().investMaxShare = v end },
    })
    return panel
end
UI.Build = Build

local function Pct(m) return ("%d%%"):format(math.floor(m * 100 + 0.5)) end

function UI.Status()
    if not panel then return end
    local p, label, paused = I().Progress()
    panel.bar:SetShown(p ~= nil)
    panel.scan:SetEnabledState(p == nil)
    if p then
        local m = T().TEXT_MUTE
        local r, g, b = T().Accent()
        if paused then r, g, b = m[1], m[2], m[3] end          -- grey while a click holds the queue
        panel.bar.paused = paused
        panel.bar:SetStatusBarColor(r, g, b, 1)
        panel.bar:SetValue(p)
        panel.status:SetText(label)
        return
    end
    panel.status:SetText("")                        -- idle: nothing (the budget line went: Alex)
end

local function DrawSelection()
    local inv = I()
    local sel = inv.sel
    panel.message:SetText(inv.message or "")
    panel.buy:Hide(); panel.cancel:Hide()
    if not sel then
        panel.selName:SetText("")
        panel.selLine:SetText((#inv.results > 0) and "Click a commodity to buy up to its best cut." or "")
        return
    end
    local name, q = AU().ItemBits(sel.id)
    panel.selName:SetText(name)
    panel.selName:SetTextColor(q[1], q[2], q[3], 1)
    if not sel.fresh then panel.selLine:SetText("Looking it up...") return end
    local b = sel.best
    if not b then panel.selLine:SetText("Not worth it any more at this budget.") return end
    local listed = I().Listed(sel.id)
    local share = listed > 0 and (" (%s of supply)"):format(Pct(b.qty / listed)) or ""
    -- With a quote in, what Confirm really spends (the hunt: the line kept the pre-quote cost)
    local cost, profit = b.cost, b.profit
    if sel.quote then cost, profit = sel.quote.total, sel.quote.profit end
    panel.selLine:SetText(("Buy %d%s for %s, relist at %s each: +%s (%s)"):format(
        b.qty, share, Money(cost), Money(b.relist), Money(profit), Pct(cost > 0 and profit / cost or 0)))
    panel.buy:Show()
    if sel.quote then
        panel.buy:SetText("Confirm " .. Money(sel.quote.total))
        panel.cancel:Show()
    else
        panel.buy:SetText(("Buy %d"):format(b.qty))
    end
    panel.buy:SetEnabledState(not sel.asked or sel.quote ~= nil)
end

function UI.Refresh()
    if not (panel and panel:IsShown()) then return end
    local list = I().results
    local n = math.min(#list, MAX_ROWS)
    for i = 1, n do
        local res = list[i]
        local r = Row(i)
        local name, q, icon = AU().ItemBits(res.id)
        local b = res.best
        r.result = res
        r.icon:SetTexture(icon)
        local listed = I().Listed(res.id)                -- one lookup, not a store walk per row
        -- Share: how much of the whole supply this buy is (Alex)
        local share = listed > 0 and Pct(b.qty / listed) or "?"
        local vals = { name, tostring(listed), tostring(b.qty), share, Money(b.cost), Money(b.relist),
                       "|cff4fd05f" .. Money(b.profit) .. "|r", Pct(b.margin) }
        for k, t in ipairs(r.cells) do t:SetText(vals[k]) end
        r.cells[1]:SetTextColor(q[1], q[2], q[3], 1)
        r:Show()
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() panel.rows[i].result = nil end
    panel.scroll.child:SetHeight(math.max(10, n * ROW_H))
    panel.empty:SetShown(n == 0)
    local state = I().run.state
    local r = I().run
    panel.empty:SetText(state ~= "idle" and "" or (r.cut == "closed" and "The auction house closed before the run finished."
        or r.cut and "The scan didn't finish; try again."
        or (r.gaveUp or 0) > 0 and ("The auction house didn't answer for %d; scan again."):format(r.gaveUp)
        or r.queue and "Nothing worth buying at this budget right now."
        or "Scan to check every commodity with enough listed for a cheap tail worth buying and relisting."))
    UI.Status()
    DrawSelection()
    panel.strip:Update()
end

function UI.Show() if Build() then panel:Show() UI.Refresh() end end
function UI.Hide() if panel then panel:Hide() end end
function UI.Shown() return panel ~= nil and panel:IsShown() end

ns.Invest.OnChange = function() UI.Refresh() end
AU().AddView({ key = "invest", label = "Investing", show = UI.Show, hide = UI.Hide, shown = UI.Shown })
