--[[ Salus Novus -- the camping panel (campingPos).

             CAMPING                (centered title)
  [======== Buffed for 42m ========]        (green duration bar while buffed,
               Sit for buffs                 else this near a campfire;
                                             neither: no row at all)
  [====== 41s ======]                 (above the panel: sitting, not buffed)
  buff icons, two rows: lit with time left, greyed when missing
  item buttons: every camping item you carry, count + cooldown sweep
  All icons sit edge to edge; each has a tooltip.
  A campfire in range: the panel's border glows (marching pixel lines).

When it shows: always, except inside instances (Camping.WantShown). The item
buttons are secure (a click uses the item), so the panel is never laid
out, shown or hidden in combat: changes wait for PLAYER_REGEN_ENABLED.
]]

local _, ns = ...

local U = {}
ns.CampingUI = U
local C = function() return ns.Camping end
local function T() return ns.Theme end

local PAD, ICON, GAP, PER_ROW = 8, 36, 2, 5
local W = PAD * 2 + PER_ROW * ICON + (PER_ROW - 1) * GAP

local frame
U.pinned = nil          -- nil = follow the settings (see Refresh)

local function O() return ns.db and ns.db.camping end

local function SavePosition() ns.SaveAnchor(frame, "campingPos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "campingPos", "CENTER", 260, 60, "CENTER")
end
ns.CampingRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "campingPos", restore = "CampingRestorePosition" })

local function InCombat()
    local ok, c = pcall(InCombatLockdown)
    return ok and c and true or false
end

local function Short(secs)
    if not ns.Num(secs) then return "" end
    if secs >= 3600 then return ("%dh"):format(math.floor(secs / 3600)) end
    if secs >= 60 then return ("%dm"):format(math.floor(secs / 60)) end
    return ("%ds"):format(math.floor(secs))
end
U.Short = Short

local function Alpha()
    local o = O()
    local a = o and tonumber(o.alpha)
    if not a or a ~= a then a = 90 end
    return math.max(0, math.min(100, a)) / 100
end

local function Icon(spellOrItem, isItem)
    local fn = isItem and (C_Item and C_Item.GetItemIconByID) or (C_Spell and C_Spell.GetSpellTexture)
    local ok, t = false, nil
    if fn then ok, t = pcall(fn, spellOrItem) end
    return ok and t or 134400
end

local function Tip(owner, fill)
    local tip = rawget(_G, "GameTooltip")
    if not tip then return end
    tip:SetOwner(owner, "ANCHOR_RIGHT")
    fill(tip)
    tip:Show()
end
local function HideTip() local tip = rawget(_G, "GameTooltip") if tip then tip:Hide() end end

-- A pixel glow: short lines marching round the edge (LibCustomGlow's
-- PixelGlow look, its line length too). Each line is drawn by up to four
-- textures, one per side it overlaps, so it turns the corners.
local GLOW_LINES, GLOW_T, GLOW_PERIOD = 8, 2, 4
local function Glow(b)
    local g = CreateFrame("Frame", nil, b)
    g:SetAllPoints()
    g:SetFrameLevel((b:GetFrameLevel() or 0) + 10)   -- over the icons
    g.tex = {}
    for i = 1, GLOW_LINES * 4 do
        local t = g:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetVertexColor(1.00, 0.78, 0.30, 1)
        t:Hide()
        g.tex[i] = t
    end
    g.phase = 0
    local function Draw()
        local w, h = b:GetWidth(), b:GetHeight()
        local P = 2 * (w + h)
        local GLOW_LEN = math.floor((w + h) * (2 / GLOW_LINES - 0.1))
        local sides = { { 0, w }, { w, w + h }, { w + h, 2 * w + h }, { 2 * w + h, P } }
        for i = 1, GLOW_LINES do
            local s = (g.phase * P + (i - 1) * P / GLOW_LINES) % P
            for k = 1, 4 do
                local t = g.tex[(i - 1) * 4 + k]
                local lo, hi = sides[k][1], sides[k][2]
                -- the line [s, s+len], and its wrapped copy past the start
                local a, z = math.max(lo, s), math.min(hi, s + GLOW_LEN)
                if z <= a then a, z = math.max(lo, s - P), math.min(hi, s + GLOW_LEN - P) end
                if z > a then
                    t:ClearAllPoints()
                    if k == 1 then
                        t:SetPoint("TOPLEFT", b, "TOPLEFT", a, 0) t:SetSize(z - a, GLOW_T)
                    elseif k == 2 then
                        t:SetPoint("TOPLEFT", b, "TOPLEFT", w - GLOW_T, -(a - w)) t:SetSize(GLOW_T, z - a)
                    elseif k == 3 then
                        t:SetPoint("TOPLEFT", b, "TOPLEFT", w - (z - (w + h)), -(h - GLOW_T)) t:SetSize(z - a, GLOW_T)
                    else
                        t:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -(h - (z - (2 * w + h)))) t:SetSize(GLOW_T, z - a)
                    end
                    t:Show()
                else
                    t:Hide()
                end
            end
        end
    end
    g:SetScript("OnUpdate", function(_, dt)
        g.phase = (g.phase + (dt or 0) / GLOW_PERIOD) % 1
        Draw()
    end)
    g.Draw = Draw
    g:Hide()
    return g
end
U.Glow = Glow

-- ------------------------------------------------------------ build

local function Build()
    if frame then return frame end
    local Th = T()
    frame = CreateFrame("Frame", "SalusNovusCamping", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(W, 120)
    frame:Hide()
    frame.bg = Th.SolidTex(frame, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 1)   -- SetAlpha(Alpha()) in Layout is the only dial
    frame.bg:SetAllPoints()
    frame.border = ns.CreateBorder(frame)
    frame.border:Layout(frame, 1, -1)
    frame.border:SetColor(1, 1, 1, 0.10)
    frame.border:Show()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Camp  \194\183  drag to move")
    frame.unlockLabel:Hide()

    frame.title = Th.MakeText(frame, 16, Th.TEXT)
    frame.title:SetPoint("TOP", 0, -7)
    frame.title:SetText(Th.Upper("Camping"))
    -- Not buffed: the status sits where the duration bar would.
    frame.status = Th.MakeText(frame, 12, Th.TEXT_MUTE)
    frame.status:SetPoint("TOP", 0, -28)
    frame.status:SetJustifyH("CENTER")

    -- How long the camp buffs last: a green bar, the time inside it.
    frame.dur = CreateFrame("StatusBar", nil, frame)
    frame.dur:SetHeight(16)
    frame.dur:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -28)
    frame.dur:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -PAD, -28)
    frame.dur:SetStatusBarTexture(Th.SOLID)
    frame.dur:SetStatusBarColor(0.20, 0.72, 0.30, 1)
    frame.dur:SetMinMaxValues(0, 1)
    frame.dur.bg = Th.SolidTex(frame.dur, "BACKGROUND", 1, 1, 1, 0.08)
    frame.dur.bg:SetAllPoints()
    frame.dur.text = frame.dur:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.dur.text, 11, "OUTLINE")
    frame.dur.text:SetPoint("CENTER")
    frame.dur:Hide()

    -- The 1 minute sit.
    frame.sit = CreateFrame("StatusBar", nil, frame)
    frame.sit:SetHeight(12)
    frame.sit:SetStatusBarTexture(Th.SOLID)
    frame.sit:SetMinMaxValues(0, 1)
    frame.sit.bg = Th.SolidTex(frame.sit, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 1)   -- the panel's own background
    frame.sit.bg:SetAllPoints()
    frame.sit.border = ns.CreateBorder(frame.sit)       -- black edge, like the timer bars
    frame.sit.border:Layout(frame.sit, 1, 0)
    frame.sit.border:SetColor(0, 0, 0, 0.9)
    frame.sit.border:Show()
    frame.sit.text = Th.MakeText(frame.sit, 10, Th.TEXT)
    frame.sit.text:SetPoint("CENTER")
    frame.sit:Hide()

    frame.buffs, frame.btns = {}, {}
    frame.glow = Glow(frame)

    ns.RegisterMovable(frame, "campingPos", function() return "TOPLEFT" end, RestorePosition)
    frame:SetScript("OnDragStart", function(self)
        -- Protected (secure item buttons): no drag in combat.
        if ns.db and ns.db.unlocked and not InCombat() then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)
    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < 0.5 then return end
        acc = 0
        U.Tick()
    end)
    RestorePosition()
    return frame
end
U.Build = Build

-- A square icon on a black edge, the time inside it at the bottom.
local function Square(b)
    local Th = T()
    b:SetSize(ICON, ICON)
    b.edge = Th.SolidTex(b, "BACKGROUND", 0, 0, 0, 1)
    b.edge:SetAllPoints()
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetPoint("TOPLEFT", 1, -1)
    b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.time = b:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(b.time, 11, "OUTLINE")
    b.time:SetPoint("BOTTOM", 0, 2)
    b.hover = Th.SolidTex(b, "HIGHLIGHT", 1, 1, 1, 0.12)
    b.hover:SetAllPoints()
end

local function BuffIcon(i)
    local b = frame.buffs[i]
    if b then return b end
    b = CreateFrame("Frame", nil, frame)
    Square(b)
    b:EnableMouse(true)
    b:SetScript("OnEnter", function(self)
        Tip(self, function(tip)
            if self.spell and tip.SetSpellByID then pcall(tip.SetSpellByID, tip, self.spell) end
            if self.left then tip:AddLine(("%s left"):format(Short(self.left)), 1, 1, 1)
            else tip:AddLine("Not active", 0.6, 0.6, 0.6) end
        end)
    end)
    b:SetScript("OnLeave", HideTip)
    frame.buffs[i] = b
    return b
end

local function ItemButton(i)
    local b = frame.btns[i]
    if b then return b end
    b = CreateFrame("Button", "SalusNovusCampItem" .. i, frame, "SecureActionButtonTemplate")
    Square(b)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type", "item")
    b.time:ClearAllPoints()
    b.time:SetPoint("BOTTOMRIGHT", -2, 2)              -- the stack count
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints(b.icon)
    b:SetScript("OnEnter", function(self)
        Tip(self, function(tip) if self.itemID then pcall(tip.SetItemByID, tip, self.itemID) end end)
    end)
    b:SetScript("OnLeave", HideTip)
    frame.btns[i] = b
    return b
end

local function Place(b, i, top)
    local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD + col * (ICON + GAP), -(top + row * (ICON + GAP)))
    b:Show()
end

-- ------------------------------------------------------------ layout

--- Lay the panel out (out of combat only: the item buttons are secure).
function U.Layout()
    if not frame then return end
    if InCombat() then U.pending = true return end
    U.pending = false
    local c = C()
    local unlocked = ns.db and ns.db.unlocked and true or false
    frame.bg:SetAlpha(Alpha())
    frame.sit.bg:SetAlpha(Alpha())
    -- Under the title; the duration bar / "Sit for buffs" row only when it
    -- has something to say (no campfire, not buffed: no row).
    local top = 28 + ((c.BenefitsLeft() or c.Nearby()) and 22 or 0)
    local buffs = c.Buffs()
    for i, bf in ipairs(buffs) do
        local b = BuffIcon(i)
        b.spell = bf.spell
        b.icon:SetTexture(Icon(bf.spell))
        b:EnableMouse(not unlocked)                     -- a drag reaches the panel while unlocked
        Place(b, i, top)
    end
    for i = #buffs + 1, #frame.buffs do frame.buffs[i]:Hide() end
    top = top + math.ceil(#buffs / PER_ROW) * (ICON + GAP)
    local items = c.Usables()
    for i, it in ipairs(items) do
        local b = ItemButton(i)
        b.itemID = it.id
        b:SetAttribute("item", "item:" .. it.id)
        b.icon:SetTexture(Icon(it.id, true))
        b.time:SetText(it.count > 1 and tostring(it.count) or "")
        b:EnableMouse(not unlocked)
        Place(b, i, top)
    end
    for i = #items + 1, #frame.btns do frame.btns[i]:Hide() frame.btns[i].itemID = nil end
    if #items > 0 then top = top + math.ceil(#items / PER_ROW) * (ICON + GAP) end
    frame:SetHeight(top - GAP + PAD)
    U.Tick()
end

--- Timers only: status, sit bar, buff times, cooldowns.
function U.Tick()
    if not frame or not frame:IsShown() then return end
    local c, Th = C(), T()
    local left = c.BenefitsLeft()
    frame.status:SetText(left and "" or (c.Nearby() and "Sit for buffs" or ""))
    if left then
        local a = c.Aura(c.AURA.benefits)
        local full = (a and a.dur and a.dur > 0) and a.dur or 3600
        frame.dur:SetValue(math.min(1, left / full))
        frame.dur.text:SetText("Buffed for " .. Short(left))
        frame.dur:Show()
    else
        frame.dur:Hide()
    end
    -- The sit bar only while it earns something: already buffed, staying
    -- seated restarts the client's minute, and the bar must not refill.
    local sitLeft, sitDur = c.SitLeft()
    if sitLeft and not left then
        local r, g, b = Th.Accent()
        frame.sit:SetStatusBarColor(r, g, b, 1)
        frame.sit:ClearAllPoints()
        frame.sit:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
        frame.sit:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 2)
        frame.sit:SetValue(1 - sitLeft / math.max(1, sitDur))
        frame.sit.text:SetText(("%ds"):format(math.ceil(sitLeft)))
        frame.sit:Show()
    else
        frame.sit:Hide()
    end
    for i, bf in ipairs(c.Buffs()) do
        local b = frame.buffs[i]
        if b then
            local on = bf.left ~= nil
            b.left = bf.left
            b.icon:SetDesaturated(not on)
            b.icon:SetAlpha(on and 1 or 0.35)
            b.time:SetText(on and Short(bf.left) or "")
        end
    end
    -- Campfire in range: the whole panel's border glows (Alex).
    local near = c.Nearby()
    if near ~= frame.glow:IsShown() then frame.glow:SetShown(near) end
    for _, b in ipairs(frame.btns) do
        if b:IsShown() and b.itemID then
            local start, dur = c.Cooldown(b.itemID)
            if b.cd.SetCooldown then b.cd:SetCooldown(start, dur) end
        end
    end
end

--- Show or hide with the settings and the pin. U.pinned: nil = follow the
-- settings, true = /sn camp opened it, false = /sn camp closed it. The
-- panel setting off, or an instance, wins over either.
function U.Refresh()
    local c = C()
    local want
    if ns.db and ns.db.unlocked then want = true
    elseif U.pinned == false then want = false
    elseif U.pinned == true then want = c.Enabled() and not c.InInstance()
    else want = c.WantShown() and true or false end
    if not frame and not want then return end
    Build()
    if InCombat() then U.pending = true return end
    local unlocked = ns.db and ns.db.unlocked and true or false
    frame.unlockLabel:SetShown(unlocked)
    if want then
        frame:Show()
        U.Layout()
    else
        frame:Hide()
    end
end

--- /sn camp and the Session bar's Camp segment: pin it open or closed.
function U.Toggle()
    -- The pin is what Refresh reads, so a close holds against the next
    -- aura or bag event, and one made in combat lands when combat ends.
    U.pinned = not (frame and frame:IsShown())
    U.Refresh()
end

ns.Camping.OnChanged = function()
    if InCombat() then U.pending = true return end
    U.Refresh()
end
ns.On("PLAYER_REGEN_ENABLED", function() if U.pending then U.Refresh() end end)
ns.RegisterApply(function() U.Refresh() end, "Camping")

ns.Commands = ns.Commands or {}
ns.Commands.camp = function() U.Toggle() end
