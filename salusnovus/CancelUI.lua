--[[ Salus Novus -- the Cancel tab on the auction house.

  top      Refresh (your auctions again, re-checked), the progress, and
           "N auctions, M undercut"
  list     item, quantity, your price each, the cheapest that isn't yours,
           status (undercut first), time left
  bottom   the clicked auction: how far under you it is, what a cancel
           costs; Cancel (one per click), and Cancel next undercut
]]

local _, ns = ...

local UI = {}
ns.CancelUI = UI
local function C() return ns.Cancel end
local function AU() return ns.AuctionUI end
local function T() return ns.Theme end

local ROW_H, MAX_ROWS = 26, 200
local COLS = {
    { "Item", 34, 220, "LEFT" }, { "Qty", 258, 50 }, { "Yours", 312, 100 }, { "Cheapest", 416, 100 },
    { "Status", 520, 90 }, { "Left", 614, 60 },
}
local panel

local function Money(c) return AU().Money(c) end

local STATUS = {
    undercut = "|cffe86a5fUndercut|r", cheapest = "|cff4fd05fCheapest|r", alone = "|cff4fd05fOnly yours|r",
    checking = "|cff8a8a96...|r", unknown = "|cff8a8a96?|r",
}
local BANDS = { [0] = "<30m", [1] = "<2h", [2] = "<12h", [3] = "<48h" }

function UI.Left(row)
    local s = row.secs
    if s then
        if s >= 86400 then return ("%dd"):format(math.floor(s / 86400)) end
        if s >= 3600 then return ("%dh"):format(math.floor(s / 3600)) end
        return ("%dm"):format(math.max(1, math.floor(s / 60)))
    end
    return BANDS[row.band] or ""
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
    r.on = Th.SolidTex(r, "BORDER", 1, 1, 1, 0.12)
    r.on:SetAllPoints()
    r.on:Hide()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(20, 20)
    r.icon:SetPoint("LEFT", 6, 0)
    r.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.cells = {}
    for k, c in ipairs(COLS) do r.cells[k] = AU().Cell(r, c[2], c[3], c[4]) end
    r:SetScript("OnClick", function(self) if self.row then C().Select(self.row) end end)
    AU().Hover(r, function(self) local w = self.row if w then return w.id, w.key, w.link end end)
    panel.rows[i] = r
    return r
end

local function Build()
    local ahf = rawget(_G, "AuctionHouseFrame")
    if panel or not ahf then return panel end
    local Th = T()
    panel = CreateFrame("Frame", "SalusNovusCancel", ahf)
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

    panel.refresh = Th.MakeButton(panel)
    panel.refresh:SetSize(90, 26)
    panel.refresh:SetPoint("TOPLEFT", 12, -10)
    panel.refresh:SetText("Refresh")
    panel.refresh:SetScript("OnClick", function(self) if self.enabledState then C().Query() end end)
    panel.status = Th.MakeText(panel, 13, Th.TEXT_DIM)
    panel.status:SetPoint("LEFT", panel.refresh, "RIGHT", 14, 0)

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
    panel.scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -28, 92)
    panel.scroll.child:SetWidth(740)
    AU().Thick(panel.scroll)
    panel.rows = {}
    panel.empty = Th.MakeText(panel.scroll.child, 14, Th.TEXT_MUTE)
    panel.empty:SetPoint("TOPLEFT", 6, -8)

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
    panel.selLine:SetPoint("RIGHT", foot, "RIGHT", -330, 0)
    panel.selLine:SetJustifyH("LEFT")
    panel.message = Th.MakeText(foot, 13, Th.TEXT_MUTE)
    panel.message:SetPoint("TOPLEFT", panel.selLine, "BOTTOMLEFT", 0, -4)
    panel.cancel = Th.MakeButton(foot)
    panel.cancel:SetSize(110, 30)
    panel.cancel:SetPoint("RIGHT", foot, "RIGHT", 0, -4)
    panel.cancel:SetPrimary(true)
    panel.cancel:SetText("Cancel")
    -- Each cancel runs inside its click (the client requires it).
    panel.cancel:SetScript("OnClick", function(self) if self.enabledState then C().Cancel() end end)
    panel.next = Th.MakeButton(foot)
    panel.next:SetSize(190, 30)
    panel.next:SetPoint("RIGHT", panel.cancel, "LEFT", -8, 0)
    panel.next:SetText("Cancel next undercut")
    panel.next:SetScript("OnClick", function(self) if self.enabledState then C().CancelNext() end end)
    return panel
end
UI.Build = Build

local function DrawSelection()
    local c = C()
    local sel = c.sel
    panel.message:SetText(c.message or "")
    local _, under = c.Counts()
    panel.next:SetEnabledState(under > 0 and c.run.state ~= "loading")
    panel.cancel:SetEnabledState(sel ~= nil and not sel.cancelling)
    if not sel then
        panel.selName:SetText("")
        panel.selLine:SetText(#c.rows > 0 and "Click an auction to cancel it." or "")
        return
    end
    local name, q = AU().ItemBits(sel.id)
    panel.selName:SetText(("%s  |cff8a8a96x%d|r"):format(name, sel.qty))
    panel.selName:SetTextColor(q[1], q[2], q[3], 1)
    local cost = c.Cost(sel)
    local costText = (cost and cost > 0) and (" Cancelling costs " .. Money(cost) .. ".") or ""
    local line
    if sel.status == "undercut" and sel.unit and sel.cheapest then
        line = ("Undercut by %s each.%s The deposit isn't refunded."):format(Money(sel.unit - sel.cheapest), costText)
    elseif sel.status == "checking" then
        line = "Checking the listings..." .. costText
    elseif sel.status == "unknown" then
        line = (sel.unit and "Couldn't check the listings.%s" or "No buyout to compare.%s"):format(costText)
    else
        line = ("Nobody is under you.%s"):format(costText)
    end
    panel.selLine:SetText(line)
end

function UI.Status()
    if not panel then return end
    local p, label = C().Progress()
    panel.bar:SetShown(p ~= nil)
    panel.refresh:SetEnabledState(p == nil)
    if p then
        local r, g, b = T().Accent()
        panel.bar:SetStatusBarColor(r, g, b, 1)
        panel.bar:SetValue(p)
        panel.status:SetText(label)
        return
    end
    local n, under = C().Counts()
    panel.status:SetText(("%d auctions  \194\183  %d undercut"):format(n, under))
end

function UI.Refresh()
    if not (panel and panel:IsShown()) then return end
    local c = C()
    local list = c.rows
    local n = math.min(#list, MAX_ROWS)
    for i = 1, n do
        local row = list[i]
        local r = Row(i)
        local name, q, icon = AU().ItemBits(row.id)
        r.row = row
        r.icon:SetTexture(icon)
        local vals = { name, tostring(row.qty), row.unit and Money(row.unit) or "?", row.cheapest and Money(row.cheapest) or "",
                       STATUS[row.status] or "", UI.Left(row) }
        for k, t in ipairs(r.cells) do t:SetText(vals[k]) end
        r.cells[1]:SetTextColor(q[1], q[2], q[3], 1)
        r.on:SetShown(c.sel == row)
        -- undercut: the whole row tinted red (Alex)
        if row.status == "undercut" then r.bg:SetVertexColor(0.91, 0.42, 0.37, 0.16)
        else r.bg:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0) end
        r.undercut = row.status == "undercut"
        r.selected = c.sel == row
        r:Show()
    end
    for i = n + 1, #panel.rows do panel.rows[i]:Hide() panel.rows[i].row = nil end
    panel.scroll.child:SetHeight(math.max(10, n * ROW_H))
    panel.empty:SetShown(n == 0)
    panel.empty:SetText(c.run.state == "loading" and "" or "You have no auctions up.")
    UI.Status()
    DrawSelection()
end

function UI.Show()
    if not Build() then return end
    panel:Show()
    C().Query()
    UI.Refresh()
end
function UI.Hide() if panel then panel:Hide() end end
function UI.Shown() return panel ~= nil and panel:IsShown() end

ns.Cancel.OnChange = function() UI.Refresh() end
AU().AddView({ key = "cancel", label = "Cancel", show = UI.Show, hide = UI.Hide, shown = UI.Shown })
