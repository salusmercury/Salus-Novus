--[[ Salus Novus -- Theme: MerkUI's look and its UI toolkit, ported.

The palette, borders, cards, pills, scroll area, model panel, buttons,
toggle, slider, nav rows and the window shell are MerkUI's (Theme.lua,
Border.lua, DungeonCodex.lua), carried over so Salus Novus is the same family
as the retail UI. What did NOT come over: LibSharedMedia fonts, Ellesmere's
theme colour, the corner glow, challenge-mode art. Accent is
ns.GetThemeColor (class colour or the custom one). One copy of every
helper lives here; nothing else defines its own. Lua 5.1 only.
]]

local _, ns = ...

local T = {}
ns.Theme = T

T.SOLID = "Interface\\Buttons\\WHITE8x8"

-- Palette: "Slab / Soft" (Alex, 2026-09-20). Charcoal surfaces a step
-- apart (#141418 window, #0f0f12 sidebar, #1b1b21 cards), heavy uppercase
-- display type, thick accent rails, chunky controls, small radii where
-- the client can draw them (it cannot round a solid texture: squares).
T.BG        = { 0.078, 0.078, 0.094 }    -- #141418
T.SIDEBAR   = { 0.059, 0.059, 0.071 }    -- #0f0f12
T.HEADER    = { 0.078, 0.078, 0.094 }    -- same as the window: no header band
T.CARD      = { 0.106, 0.106, 0.129 }    -- #1b1b21
T.EDGE      = { 0.227, 0.227, 0.267 }    -- #3a3a44 button borders
T.LINE      = { 1, 1, 1, 0.08 }          -- #2a2a31-ish hairlines
T.TEXT      = { 0.925, 0.925, 0.94 }     -- #ececf0
T.HEAD_TEXT = { 1, 1, 1 }
T.TEXT_DIM  = { 0.81, 0.81, 0.84 }       -- #cfcfd6
T.TEXT_MUTE = { 0.455, 0.455, 0.50 }     -- #74747f
T.RAIL_W    = 6                          -- the accent rail on cards and sections

-- The display face: heavy, condensed, uppercase (Anton in the mock;
-- Impact from the font pack is its nearest cousin). Falls back to the
-- active font when the pack is absent (SetFontSafe never warns for a path).
T.DISPLAY = "Interface\\AddOns\\SharedMediaAdditionalFonts\\fonts\\impact.ttf"
function T.SetDisplay(fs, size)
    ns.SetFontSafe(fs, size, "", T.DISPLAY)
end
function T.Upper(s) return string.upper(tostring(s or "")) end

T.PILL = {
    boss = { 1.00, 0.81, 0.30 },
    add  = { 0.45, 0.66, 1.00 },
}

function T.Accent() return ns.GetThemeColor() end

--- Text drawn ON the accent (an active nav row, a picked segment): near
-- black when the accent is bright, white otherwise. A rogue's yellow made
-- white text unreadable (Alex).
function T.OnAccent()
    local r, g, b = T.Accent()
    local luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if luma > 0.55 then return 0.08, 0.08, 0.10 end
    return 1, 1, 1
end

function T.SolidTex(parent, layer, r, g, b, a, sub)
    local t = parent:CreateTexture(nil, layer or "ARTWORK", nil, sub)
    t:SetTexture(T.SOLID)
    t:SetVertexColor(r, g, b, a == nil and 1 or a)
    return t
end

-- Gradient from (r,g,b,a1) to (r,g,b,a2). HORIZONTAL left -> right, VERTICAL
-- bottom -> top. SetGradient wants ColorMixins on modern clients.
function T.Gradient(tex, r, g, b, a1, a2, orientation)
    if CreateColor and tex.SetGradient then
        pcall(tex.SetGradient, tex, orientation or "HORIZONTAL", CreateColor(r, g, b, a1), CreateColor(r, g, b, a2))
    elseif tex.SetGradientAlpha then
        pcall(tex.SetGradientAlpha, tex, orientation or "HORIZONTAL", r, g, b, a1, r, g, b, a2)
    end
end

-- Everything painted in the accent colour, so a theme change repaints once.
-- Part shapes: { tex, a } | { tex, gradient = true, a1, a2, orientation } |
-- { repaint = <object with :Repaint()> }.
T.accentParts = {}
function T.RepaintPart(part)
    local r, g, b = T.Accent()
    if part.repaint then
        part.repaint:Repaint()
    elseif part.gradient then
        part.tex:SetVertexColor(1, 1, 1, 1)
        T.Gradient(part.tex, r, g, b, part.a1, part.a2, part.orientation)
    else
        part.tex:SetVertexColor(r, g, b, part.a or 1)
    end
end
function T.Paint(part)
    table.insert(T.accentParts, part)
    T.RepaintPart(part)
end
T.Repaint = T.RepaintPart   -- older callers

-- Repaint every registered part, but only when the colour actually changed
-- (MerkUI repainted every page on every ApplyAll; ~21MB per slider drag).
local lastR, lastG, lastB
function T.RepaintAll(force)
    local r, g, b = T.Accent()
    if not force and r == lastR and g == lastG and b == lastB then return end
    lastR, lastG, lastB = r, g, b
    for _, part in ipairs(T.accentParts) do T.RepaintPart(part) end
end
ns.RegisterApply(function() T.RepaintAll() end, "Theme")

-- ---------------------------------------------------------------- font

function T.FontPath() return ns.ActiveFont() end

--- Set a font and check it took (Fonts.lua does the checking). No explicit
-- path: the string follows the global font and is re-fonted on a change.
function T.SetFont(fs, size, flags) ns.SetFontSafe(fs, size, flags or "") end

function T.MakeText(parent, size, color, flags)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    T.SetFont(fs, size, flags)
    local c = color or T.TEXT
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-- --------------------------------------------------------------- border

--- Four 1px edges around a frame (MerkUI/Border.lua). Memoised per parent.
-- Never SetBackdrop: it taints protected-frame arithmetic (landmine 2).
function T.Border(parent)
    if parent.__edges then return parent.__edges end
    local e = {}
    for _, k in ipairs({ "top", "bottom", "left", "right" }) do
        e[k] = parent:CreateTexture(nil, "OVERLAY")
        e[k]:SetTexture(T.SOLID)
    end
    e.all = { e.top, e.bottom, e.left, e.right }
    -- Layout(anchorTo, thickness, gap): gap > 0 floats the border outside,
    -- gap = -1 draws it INSIDE the rect (what a card in a ScrollFrame needs).
    function e:Layout(to, t, gap)
        to, t, gap = to or parent, t or 1, gap or 0
        local o, outer = gap, gap + t
        self.top:ClearAllPoints()
        self.top:SetPoint("BOTTOMLEFT", to, "TOPLEFT", -outer, o)
        self.top:SetPoint("BOTTOMRIGHT", to, "TOPRIGHT", outer, o)
        self.top:SetHeight(t)
        self.bottom:ClearAllPoints()
        self.bottom:SetPoint("TOPLEFT", to, "BOTTOMLEFT", -outer, -o)
        self.bottom:SetPoint("TOPRIGHT", to, "BOTTOMRIGHT", outer, -o)
        self.bottom:SetHeight(t)
        self.left:ClearAllPoints()
        self.left:SetPoint("TOPRIGHT", to, "TOPLEFT", -o, o)
        self.left:SetPoint("BOTTOMRIGHT", to, "BOTTOMLEFT", -o, -o)
        self.left:SetWidth(t)
        self.right:ClearAllPoints()
        self.right:SetPoint("TOPLEFT", to, "TOPRIGHT", o, o)
        self.right:SetPoint("BOTTOMLEFT", to, "BOTTOMRIGHT", o, -o)
        self.right:SetWidth(t)
    end
    function e:SetColor(r, g, b, a) for _, t in ipairs(self.all) do t:SetVertexColor(r, g, b, a or 1) end end
    function e:Show() for _, t in ipairs(self.all) do t:Show() end end
    function e:Hide() for _, t in ipairs(self.all) do t:Hide() end end
    parent.__edges = e
    return e
end
ns.CreateBorder = T.Border      -- so ported MerkUI code reads unchanged

-- ----------------------------------------------------------------- pill

--- A small tag: coloured text on a faint tinted background.
function T.MakePill(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    f.bg = T.SolidTex(f, "BACKGROUND", 1, 1, 1, 0.10)
    f.bg:SetAllPoints()
    f.text = T.MakeText(f, 10.5, T.TEXT)
    f.text:SetPoint("CENTER", 0, 0)
    function f:Set(label, r, g, b)
        self.text:SetText(label)
        self.text:SetTextColor(r, g, b, 1)
        self.bg:SetVertexColor(r, g, b, 0.16)
        self:SetWidth((self.text:GetStringWidth() or 40) + 12)
        self:Show()
    end
    return f
end

-- --------------------------------------------------------------- button

--- Slab button: card fill, 2px edge, uppercase display label, accent
-- edge on hover. SetPrimary(true) fills it with the accent (the Close /
-- Save of a screen). SetText / GetText like a Blizzard button and
-- SetEnabledState for the options sweep.
function T.MakeButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn.bg = T.SolidTex(btn, "BACKGROUND", T.CARD[1], T.CARD[2], T.CARD[3], 1)
    btn.bg:SetAllPoints()
    btn.border = T.Border(btn)
    btn.border:Layout(btn, 2, -2)
    btn.border:SetColor(T.EDGE[1], T.EDGE[2], T.EDGE[3], 1)
    btn.border:Show()
    local text = T.MakeText(btn, 15, T.TEXT)
    T.SetDisplay(text, 15)
    text:SetPoint("CENTER", 0, 0)
    text:SetJustifyH("CENTER")
    btn.text = text
    btn.raw = ""
    btn.SetText = function(_, t) btn.raw = tostring(t or ""); text:SetText(T.Upper(t)) end
    btn.GetText = function() return btn.raw end
    btn.enabledState, btn.primary = true, false
    local function Rest(self)
        if self.primary then
            local r, g, b = T.Accent()
            local a = self.enabledState and 1 or 0.4
            self.bg:SetVertexColor(r, g, b, a)
            self.border:SetColor(r, g, b, a)
            local tr, tg, tb = T.OnAccent()
            text:SetTextColor(tr, tg, tb, 1)
        else
            self.bg:SetVertexColor(T.CARD[1], T.CARD[2], T.CARD[3], 1)
            self.border:SetColor(T.EDGE[1], T.EDGE[2], T.EDGE[3], self.enabledState and 1 or 0.5)
            local c = self.enabledState and T.TEXT or T.TEXT_MUTE
            text:SetTextColor(c[1], c[2], c[3], 1)
        end
    end
    btn.Rest = Rest
    btn:SetScript("OnEnter", function(self)
        if not self.enabledState then return end
        local r, g, b = T.Accent()
        if self.primary then self.bg:SetVertexColor(r, g, b, 0.85)
        else self.border:SetColor(r, g, b, 1) end
    end)
    btn:SetScript("OnLeave", Rest)
    btn:SetScript("OnMouseDown", function(self)
        if self.enabledState then self.bg:SetVertexColor(1, 1, 1, 0.12) end
    end)
    btn:SetScript("OnMouseUp", Rest)
    btn.SetEnabledState = function(self, e)
        self.enabledState = e and true or false
        self:SetEnabled(self.enabledState)
        Rest(self)
    end
    btn.SetPrimary = function(self, on)
        self.primary = on and true or false
        Rest(self)
    end
    function btn:Repaint() Rest(self) end
    T.Paint({ repaint = btn })
    Rest(btn)
    return btn
end

--- Header control: dark box, thin border, label + caret texture.
function T.MakeHeaderButton(parent, width, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width, 30)
    local bg = T.SolidTex(btn, "BACKGROUND", 1, 1, 1, 0.04)
    bg:SetAllPoints()
    local border = T.Border(btn)
    border:Layout(btn, 1, 0)
    border:SetColor(1, 1, 1, 0.10)
    border:Show()
    btn.text = T.MakeText(btn, 13, T.TEXT)
    btn.text:SetPoint("LEFT", 10, 0)
    btn.text:SetPoint("RIGHT", -24, 0)
    btn.text:SetWordWrap(false)
    local caret = btn:CreateTexture(nil, "ARTWORK")
    caret:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
    caret:SetSize(10, 10)
    if caret.SetRotation then pcall(caret.SetRotation, caret, -math.pi / 2) end
    caret:SetVertexColor(T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1)
    caret:SetPoint("RIGHT", -7, 0)
    local hl = T.SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.05)
    hl:SetAllPoints()
    btn:SetScript("OnClick", function(self) onClick(self) end)
    return btn
end

--- Toggle switch: a pill track with a sliding knob, accent track when on.
-- Blizzard CheckButton surface (SetChecked / GetChecked).
function T.MakeCheck(parent, label, size)
    size = size or 18
    local cb = CreateFrame("Button", nil, parent)
    cb:SetSize(size * 2, size)
    cb.bg = T.SolidTex(cb, "BACKGROUND", 1, 1, 1, 0.10)
    cb.bg:SetAllPoints()
    cb.border = T.Border(cb)
    cb.border:Layout(cb, 1, -1)
    cb.border:SetColor(1, 1, 1, 0.10)
    cb.border:Show()
    cb.knob = T.SolidTex(cb, "ARTWORK", 1, 1, 1, 0.95)
    cb.knob:SetSize(size - 6, size - 6)
    cb.knob:SetPoint("LEFT", 3, 0)
    cb.text = T.MakeText(cb, 13, T.TEXT)
    cb.text:SetPoint("LEFT", cb, "RIGHT", 10, 0)
    cb.text:SetText(label or "")
    cb.checked, cb.enabledState = false, true
    function cb:SetChecked(v)
        self.checked = v and true or false
        self.knob:ClearAllPoints()
        if self.checked then
            local r, g, b = T.Accent()
            self.bg:SetVertexColor(r, g, b, 0.95)
            self.knob:SetPoint("RIGHT", -3, 0)
        else
            self.bg:SetVertexColor(1, 1, 1, 0.10)
            self.knob:SetPoint("LEFT", 3, 0)
        end
    end
    function cb:GetChecked() return self.checked end
    cb:SetScript("OnEnter", function(self) if self.enabledState then self.border:SetColor(1, 1, 1, 0.35) end end)
    cb:SetScript("OnLeave", function(self) self.border:SetColor(1, 1, 1, 0.10) end)   -- the rest colour above
    cb:SetScript("OnClick", function(self) self:SetChecked(not self.checked) end)
    return cb
end

--- Horizontal value slider: thin track, accent fill, square thumb, integer
-- steps. onChange fires only when the integer value changes, and never
-- before SetValueQuiet has loaded the saved value (the client fires
-- OnValueChanged on first layout at the minimum). No mouse wheel: a slider
-- that eats the wheel changes a setting as you scroll past it.
function T.MakeSlider(parent, width, minV, maxV, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    -- Slab: an 8 px track a step lighter than the card, the accent fill,
    -- a white bar for the thumb.
    s.track = T.SolidTex(s, "BACKGROUND", 1, 1, 1, 0.10)
    s.track:SetHeight(8)
    s.track:SetPoint("LEFT", 0, 0)
    s.track:SetPoint("RIGHT", 0, 0)
    s.fill = T.SolidTex(s, "BACKGROUND", 1, 1, 1, 1, 1)
    s.fill:SetHeight(8)
    s.fill:SetPoint("LEFT", 0, 0)
    s.fill:SetWidth(1)
    s:SetThumbTexture(T.SOLID)
    s.thumb = s:GetThumbTexture()
    if s.thumb then s.thumb:SetSize(10, 16) end
    s.quiet, s.last, s.primed = false, nil, false
    local function Paint()
        local r, g, b = T.Accent()
        local lo, hi = s:GetMinMaxValues()
        local v = s:GetValue() or lo
        local frac = (hi > lo) and ((v - lo) / (hi - lo)) or 0
        s.fill:SetWidth(math.max(1, frac * (s:GetWidth() or width)))
        local on = (not s.IsEnabled) or s:IsEnabled()
        s.fill:SetVertexColor(r, g, b, on and 1 or 0.35)
        if s.thumb then s.thumb:SetVertexColor(1, 1, 1, on and 1 or 0.4) end
    end
    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor((v or 0) + 0.5)
        Paint()
        if self.quiet or not self.primed then return end
        if v ~= self.last then
            self.last = v
            onChange(v)
        end
    end)
    s:SetScript("OnSizeChanged", Paint)
    function s:SetValueQuiet(v)
        -- A stored value outside the range (an older version's, a hand
        -- edit) shows clamped, as the anchor will use it.
        local lo, hi = self:GetMinMaxValues()
        if type(lo) == "number" and type(hi) == "number" then v = math.max(lo, math.min(hi, v)) end
        self.quiet = true
        self.last = v
        self:SetValue(v)
        self.quiet = false
        self.primed = true
        Paint()
    end
    s.Paint = Paint
    function s:Repaint() Paint() end
    T.Paint({ repaint = s })
    return s
end

--- Single-line text entry in the dark style. Escape/Enter drop focus.
function T.MakeEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    ns.SetFontSafe(eb, 13, "")
    eb:SetTextColor(1, 1, 1, 1)
    eb:SetTextInsets(6, 6, 0, 0)
    eb.bg = T.SolidTex(eb, "BACKGROUND", 1, 1, 1, 0.05)
    eb.bg:SetAllPoints()
    eb.border = T.Border(eb)
    eb.border:Layout(eb, 1, 0)
    eb.border:SetColor(1, 1, 1, 0.12)
    eb.border:Show()
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

-- --------------------------------------------------------------- scroll

--- ScrollFrame + child + a thin 4px slider, no Blizzard template.
function T.MakeScrollArea(parent)
    local sf = CreateFrame("ScrollFrame", nil, parent)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(1, 1)
    sf:SetScrollChild(child)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(4)
    slider:SetPoint("TOPRIGHT", sf, "TOPRIGHT", 8, 0)
    slider:SetPoint("BOTTOMRIGHT", sf, "BOTTOMRIGHT", 8, 0)
    slider:SetMinMaxValues(0, 0)
    slider:SetValue(0)
    slider:SetValueStep(1)
    local track = T.SolidTex(slider, "BACKGROUND", 1, 1, 1, 0.05)
    track:SetAllPoints()
    slider:SetThumbTexture(T.SOLID)
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetSize(4, 40)
        T.Paint({ tex = thumb, a = 0.7 })   -- follows an accent change
    end
    slider.thumb = thumb
    slider:Hide()
    local syncing = false
    sf:SetScript("OnScrollRangeChanged", function(self, _, yrange)
        yrange = math.max(0, math.floor(yrange or 0))
        slider:SetMinMaxValues(0, yrange)
        slider:SetShown(yrange > 1)
        if self:GetVerticalScroll() > yrange then self:SetVerticalScroll(yrange) end
    end)
    sf:SetScript("OnMouseWheel", function(self, delta)
        local _, max = slider:GetMinMaxValues()
        local v = math.max(0, math.min(max or 0, self:GetVerticalScroll() - delta * 48))
        syncing = true
        slider:SetValue(v)
        syncing = false
        self:SetVerticalScroll(v)
    end)
    sf:EnableMouseWheel(true)
    slider:SetScript("OnValueChanged", function(_, v) if not syncing then sf:SetVerticalScroll(v) end end)
    sf.child, sf.slider = child, slider
    return sf
end

-- ------------------------------------------------------------- nav rows

--- Slab nav row: the active one is a solid accent block (inset 12 px
-- from the sidebar's edges) with near-black text; the rest are dim
-- uppercase display labels with a faint wash on hover. Returns the accent
-- parts for the owner to register.
function T.DecorateNavRow(btn)
    btn.fill = T.SolidTex(btn, "BACKGROUND", 1, 1, 1, 1)
    btn.fill:SetPoint("TOPLEFT", 12, -3)
    btn.fill:SetPoint("BOTTOMRIGHT", -12, 3)
    btn.fill:Hide()
    -- Kept for callers that predate the block: never shown now.
    btn.indicator = T.SolidTex(btn, "ARTWORK", 1, 1, 1, 1)
    btn.indicator:SetWidth(0.01)
    btn.indicator:SetPoint("TOPLEFT", 0, 0)
    btn.indicator:Hide()
    btn.glow = btn.fill
    btn.hover = T.SolidTex(btn, "HIGHLIGHT", 1, 1, 1, 0.06)
    btn.hover:SetPoint("TOPLEFT", 12, -3)
    btn.hover:SetPoint("BOTTOMRIGHT", -12, 3)
    return {
        { tex = btn.fill, a = 1 },
    }
end

function T.SetNavActive(btn, active)
    btn.fill:SetShown(active)
    if btn.label then
        if active then
            local r, g, b = T.OnAccent()
            btn.label:SetTextColor(r, g, b, 1)
        else
            btn.label:SetTextColor(T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1)
        end
    end
end

function T.NavLabel(btn, text)
    btn.label = T.MakeText(btn, 18, T.TEXT_DIM)
    T.SetDisplay(btn.label, 18)
    btn.label:SetPoint("LEFT", 24, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -14, 0)
    btn.label:SetJustifyH("LEFT")
    btn.label:SetWordWrap(false)
    btn.label:SetText(T.Upper(text))
    return btn.label
end

-- ----------------------------------------------------------------- card

--- The card look: faint panel, thin border INSIDE the rect (a ScrollFrame
-- clipped the outside right edge), 3px accent edge on the left, hover pop.
--- One physical screen pixel in `frame`'s own units. At a UI scale that
-- is not 768/screen-height a "1px" edge is a fraction of a pixel, and the
-- client rounds each edge on its own: one side lands 1px, the other 2px
-- (Alex: the boxes look cut off / lopsided). Sizes built from this unit
-- land on whole pixels on every side.
function T.PixelUnit(frame)
    local ph
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        if ok and type(h) == "number" and h > 0 then ph = h end
    end
    if not ph then return 1 end
    local s = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
    if not s or s <= 0 then s = 1 end
    return (768 / ph) / s
end

--- `v` rounded to whole pixels of `unit`, never below one pixel.
function T.SnapPx(v, unit)
    local n = math.floor(v / unit + 0.5)
    if n < 1 then n = 1 end
    return n * unit
end

--- Whole-pixel sizes are not enough: a box whose POSITION lands on a
-- half pixel (under a text line of fractional height, say) loses a
-- border edge to the client's rounding -- the card editor's ROLES row
-- did (Alex, 2026-09-20). So every box snaps its own bottom-left to a
-- whole pixel once it is shown, whoever laid it out.
T.checkBoxes = {}
function T.SnapBox(b)
    if not b:IsShown() then return end
    local l, bt = b:GetLeft(), b:GetBottom()
    if not l or not bt then return end
    local u = T.PixelUnit(b)
    local dx = math.floor(l / u + 0.5) * u - l
    local dy = math.floor(bt / u + 0.5) * u - bt
    if math.abs(dx) < 0.001 and math.abs(dy) < 0.001 then return end
    local point, rel, relPoint, x, y = b:GetPoint(1)
    if not point then return end
    b:SetPoint(point, rel, relPoint, (x or 0) + dx, (y or 0) + dy)
end
function T.SnapCheckBoxes()
    for _, b in ipairs(T.checkBoxes) do T.SnapBox(b) end
end

--- The square check box (a filled square in the accent when on): the
-- options pages' style, and the ability cards' (Alex: "the checkbox
-- style, not the slider style").
function T.MakeCheckBox(parent, size)
    local b = CreateFrame("Button", nil, parent)
    -- Box, inset and edge are whole pixels so the fill sits centred with
    -- the same gap on every side and the border is 1px all round.
    local px = T.PixelUnit(b)
    local box = T.SnapPx(size or 18, px)
    -- Slab: a 3 px edge (2 px on a small box) drawn INSIDE the square, the
    -- fill inset by twice the edge so a gap of the edge's width shows.
    local edge = T.SnapPx((size or 18) >= 18 and 3 or 2, px)
    local inset = 2 * edge
    b:SetSize(box, box)
    b.bg = T.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.04)
    b.bg:SetAllPoints()
    b.fill = T.SolidTex(b, "ARTWORK", 1, 1, 1, 1)
    -- Sized and centred, not inset from the corners: two insets round
    -- apart on a fractional pixel and the square sits lopsided (Alex).
    b.fill:SetSize(box - 2 * inset, box - 2 * inset)
    b.fill:SetPoint("CENTER", 0, 0)
    b.fill:Hide()
    b.border = ns.CreateBorder(b)
    b.border:Layout(b, edge, -edge)
    b.border:SetColor(1, 1, 1, 0.28)
    b.border:Show()
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.checked = false
    b.enabledState = true
    function b:Paint()
        local r, g, bb = T.Accent()
        if self.checked then
            self.fill:SetVertexColor(r, g, bb, self.enabledState and 1 or 0.4)
            self.fill:Show()
            self.border:SetColor(r, g, bb, self.enabledState and 1 or 0.4)
        else
            self.fill:Hide()
            self.border:SetColor(1, 1, 1, self.enabledState and 0.28 or 0.12)
        end
    end
    function b:SetChecked(v) self.checked = v and true or false; self:Paint() end
    function b:GetChecked() return self.checked end
    function b:SetEnabled(e) self.enabledState = e and true or false; self:Paint() end
    function b:Repaint() self:Paint() end
    b:SetScript("OnClick", function(self)
        if not self.enabledState then return end
        self:SetChecked(not self.checked)
    end)
    b:SetScript("OnEnter", function(self)
        if self.enabledState and not self.checked then self.border:SetColor(1, 1, 1, 0.5) end
    end)
    b:SetScript("OnLeave", function(self) self:Paint() end)
    -- Snap a frame later: at OnShow the layout may not be resolved yet.
    b:HookScript("OnShow", function(self)
        if C_Timer and C_Timer.After then C_Timer.After(0, function() T.SnapBox(self) end) else T.SnapBox(self) end
    end)
    table.insert(T.checkBoxes, b)
    b:Paint()
    T.Paint({ repaint = b })
    return b
end

--- A check box with a label to its right, for a row of them.
function T.MakeLabelledCheckBox(parent, label, size)
    local b = T.MakeCheckBox(parent, size or 16)
    b.label = T.MakeText(b, 13, T.TEXT)
    b.label:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.label:SetText(label or "")
    return b
end

-- ---------------------------------------------------------- colour picker
-- Our own picker (Alex: Blizzard's frame has its art border): a preview,
-- three sliders, a hex box, Okay / Cancel. `onChange(r, g, b)` fires on
-- every move so the caller can preview live; Cancel calls `onCancel()`
-- (or puts the opening colour back through onChange).
local picker
local function Hex(r, g, b)
    return string.format("%02X%02X%02X", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end
--- HSV -> RGB for the palette square.
local function HSV(h, s, v)
    local i = math.floor(h * 6) % 6
    local f = h * 6 - math.floor(h * 6)
    local p, q, u = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    if i == 0 then return v, u, p elseif i == 1 then return q, v, p elseif i == 2 then return p, v, u
    elseif i == 3 then return p, q, v elseif i == 4 then return u, p, v else return v, p, q end
end

-- The palette: 12 hues across, six rows from pastel to dark, a grey row.
local PAL_COLS, PAL_ROWS, PAL_CELL, PAL_GAP = 12, 7, 16, 1
local PAL_SV = { { 0.35, 1.0 }, { 0.7, 1.0 }, { 1.0, 1.0 }, { 1.0, 0.8 }, { 1.0, 0.6 }, { 1.0, 0.4 } }
local function PaletteColor(row, col)
    if row == PAL_ROWS then
        local g = (col - 1) / (PAL_COLS - 1)
        return g, g, g
    end
    local sv = PAL_SV[row]
    return HSV((col - 1) / PAL_COLS, sv[1], sv[2])
end

local function BuildPicker()
    if picker then return picker end
    local palH = PAL_ROWS * (PAL_CELL + PAL_GAP)
    local W, H = 300, 236 + palH + 10
    picker = CreateFrame("Frame", "SalusNovusColorPicker", UIParent)
    picker:SetSize(W, H)
    picker:SetPoint("CENTER", 0, 60)
    picker:SetFrameStrata("FULLSCREEN_DIALOG")   -- above the options window (Alex: it opened behind)
    picker:SetToplevel(true)
    picker:SetClampedToScreen(true)
    picker:EnableMouse(true)
    picker:SetMovable(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", function(self) self:StartMoving() end)
    picker:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    picker.bg = T.SolidTex(picker, "BACKGROUND", T.BG[1], T.BG[2], T.BG[3], 0.98)
    picker.bg:SetAllPoints()
    picker.border = T.Border(picker)
    picker.border:Layout(picker, 1, 0)
    picker.border:SetColor(1, 1, 1, 0.12)
    picker.border:Show()
    picker.accent = T.SolidTex(picker, "ARTWORK", 1, 1, 1, 1)
    picker.accent:SetHeight(2)
    picker.accent:SetPoint("TOPLEFT", 0, 0)
    picker.accent:SetPoint("TOPRIGHT", 0, 0)
    T.Paint({ tex = picker.accent, a = 0.9 })
    picker.title = T.MakeText(picker, 12, T.TEXT_MUTE)
    picker.title:SetPoint("TOPLEFT", 16, -14)
    picker.title:SetText("COLOR")

    picker.preview = CreateFrame("Frame", nil, picker)
    picker.preview:SetSize(56, 56)
    picker.preview:SetPoint("TOPRIGHT", -16, -12)
    picker.preview.fill = T.SolidTex(picker.preview, "ARTWORK", 1, 1, 1, 1)
    picker.preview.fill:SetAllPoints()
    picker.preview.border = ns.CreateBorder(picker.preview)
    picker.preview.border:Layout(picker.preview, 1, 0)
    picker.preview.border:SetColor(1, 1, 1, 0.25)
    picker.preview.border:Show()

    picker.v = { 1, 1, 1 }
    picker.sliders = {}
    local function Push(fromHex)
        local r, g, b = picker.v[1], picker.v[2], picker.v[3]
        picker.preview.fill:SetVertexColor(r, g, b, 1)
        if not fromHex then picker.hex:SetText(Hex(r, g, b)) end
        if picker.onChange then picker.onChange(r, g, b) end
    end
    picker.Push = Push

    -- The square of every colour (Alex: "not just rgb sliders"): a cell
    -- click sets the colour and the sliders / hex follow.
    picker.grid = CreateFrame("Frame", nil, picker)
    picker.grid:SetSize(PAL_COLS * (PAL_CELL + PAL_GAP) - PAL_GAP, palH - PAL_GAP)
    picker.grid:SetPoint("TOPLEFT", picker.title, "BOTTOMLEFT", 0, -10)
    picker.cells = {}
    function picker.SetColor(r, g, b)
        picker.v[1], picker.v[2], picker.v[3] = r, g, b
        for i = 1, 3 do
            local n = math.floor(picker.v[i] * 255 + 0.5)
            picker.sliders[i]:SetValueQuiet(n)
            picker.val[i]:SetText(tostring(n))
        end
        Push(false)
    end
    for row = 1, PAL_ROWS do
        for col = 1, PAL_COLS do
            local cell = CreateFrame("Button", nil, picker.grid)
            cell:SetSize(PAL_CELL, PAL_CELL)
            cell:SetPoint("TOPLEFT", picker.grid, "TOPLEFT", (col - 1) * (PAL_CELL + PAL_GAP), -(row - 1) * (PAL_CELL + PAL_GAP))
            local r, g, b = PaletteColor(row, col)
            cell.color = { r, g, b }
            cell.fill = T.SolidTex(cell, "ARTWORK", r, g, b, 1)
            cell.fill:SetAllPoints()
            cell.hl = T.SolidTex(cell, "HIGHLIGHT", 1, 1, 1, 0.25)
            cell.hl:SetAllPoints()
            cell:SetScript("OnClick", function(self)
                local c = self.color
                picker.SetColor(c[1], c[2], c[3])
            end)
            picker.cells[#picker.cells + 1] = cell
        end
    end

    local prev = picker.grid
    for i, name in ipairs({ "R", "G", "B" }) do
        local cap = T.MakeText(picker, 12, T.TEXT_MUTE)
        cap:SetText(name)
        local s = T.MakeSlider(picker, 150, 0, 255, function(v)
            picker.v[i] = v / 255
            picker.val[i]:SetText(tostring(v))
            Push(false)
        end)
        if prev == picker.grid then cap:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -14)
        else cap:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -20) end
        s:SetPoint("LEFT", cap, "LEFT", 22, 0)
        local val = T.MakeText(picker, 12, T.TEXT)
        val:SetPoint("LEFT", s, "RIGHT", 10, 0)
        picker.val = picker.val or {}
        picker.val[i] = val
        picker.sliders[i] = s
        prev = cap
    end

    picker.hexCap = T.MakeText(picker, 12, T.TEXT_MUTE)
    picker.hexCap:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -22)
    picker.hexCap:SetText("#")
    picker.hex = T.MakeEditBox(picker, 90)
    picker.hex:SetPoint("LEFT", picker.hexCap, "LEFT", 22, 0)
    picker.hex:SetMaxLetters(6)
    local function ReadHex(self)
        local t = (self:GetText() or ""):gsub("^#", ""):upper()
        if #t ~= 6 or not t:match("^%x+$") then return end
        picker.v[1] = tonumber(t:sub(1, 2), 16) / 255
        picker.v[2] = tonumber(t:sub(3, 4), 16) / 255
        picker.v[3] = tonumber(t:sub(5, 6), 16) / 255
        for i = 1, 3 do
            picker.sliders[i]:SetValueQuiet(math.floor(picker.v[i] * 255 + 0.5))
            picker.val[i]:SetText(tostring(math.floor(picker.v[i] * 255 + 0.5)))
        end
        Push(true)
    end
    picker.hex:HookScript("OnEditFocusLost", ReadHex)   -- Enter drops focus, which commits once

    picker.okay = T.MakeButton(picker)
    picker.okay:SetSize(90, 26)
    picker.okay:SetPoint("BOTTOMRIGHT", -16, 14)
    picker.okay:SetText("Okay")
    picker.okay:SetScript("OnClick", function() picker:Hide() end)
    picker.cancel = T.MakeButton(picker)
    picker.cancel:SetSize(90, 26)
    picker.cancel:SetPoint("RIGHT", picker.okay, "LEFT", -8, 0)
    picker.cancel:SetText("Cancel")
    picker.cancel:SetScript("OnClick", function()
        local cb = picker.onCancel
        picker.onChange = nil
        picker:Hide()
        if cb then cb() end
    end)
    picker:Hide()
    if UISpecialFrames then table.insert(UISpecialFrames, "SalusNovusColorPicker") end
    return picker
end

function T.OpenColorPicker(c, onChange, onCancel)
    local p = BuildPicker()
    local r0, g0, b0 = c.r or 1, c.g or 1, c.b or 1
    p.onChange = nil     -- seeding the sliders must not fire the caller
    p.onCancel = onCancel or function() onChange(r0, g0, b0) end
    p.v[1], p.v[2], p.v[3] = r0, g0, b0
    for i = 1, 3 do
        local n = math.floor(p.v[i] * 255 + 0.5)
        p.sliders[i]:SetValueQuiet(n)
        p.val[i]:SetText(tostring(n))
    end
    p.preview.fill:SetVertexColor(r0, g0, b0, 1)
    p.hex:SetText(Hex(r0, g0, b0))
    p.onChange = onChange
    p:Show()
    p:Raise()
    return true
end
T.ColorPicker = function() return BuildPicker() end

function T.MakeCard(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:EnableMouse(true)
    row.bg = T.SolidTex(row, "BACKGROUND", T.CARD[1], T.CARD[2], T.CARD[3], 1)
    row.bg:SetAllPoints()
    row.hoverBg = T.SolidTex(row, "BACKGROUND", 1, 1, 1, 0.05, 1)
    row.hoverBg:SetAllPoints()
    row.hoverBg:Hide()
    row.border = T.Border(row)
    row.border:Layout(row, 1, -1)
    row.border:SetColor(1, 1, 1, 0)
    row.border:Show()
    row.accent = T.SolidTex(row, "ARTWORK", 1, 1, 1, 1)
    row.accent:SetWidth(T.RAIL_W)
    row.accent:SetPoint("TOPLEFT", 0, 0)
    row.accent:SetPoint("BOTTOMLEFT", 0, 0)
    T.Paint({ tex = row.accent, a = 1 })
    row:SetScript("OnEnter", function(self)
        local r, g, b = T.Accent()
        self.border:SetColor(r, g, b, 0.6)
        self.hoverBg:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.border:SetColor(1, 1, 1, 0)
        self.hoverBg:Hide()
    end)
    return row
end

-- ---------------------------------------------------------------- model

--- A PlayerModel in a bordered panel with the accent floor wash; drag to
-- rotate (self-disarming), wheel to zoom. Returns the panel; panel.model.
function T.MakeModelPanel(parent)
    local panel = CreateFrame("Frame", nil, parent)
    local bg = T.SolidTex(panel, "BACKGROUND", 0, 0, 0, 0.45)
    bg:SetAllPoints()
    local border = T.Border(panel)
    border:Layout(panel, 1, 0)
    border:SetColor(1, 1, 1, 0.08)
    border:Show()
    local floor = T.SolidTex(panel, "BACKGROUND", 1, 1, 1, 1, 1)
    floor:SetPoint("BOTTOMLEFT", 0, 0)
    floor:SetPoint("BOTTOMRIGHT", 0, 0)
    floor:SetHeight(70)
    T.Paint({ tex = floor, gradient = true, a1 = 0.10, a2 = 0.0, orientation = "VERTICAL" })
    local m = CreateFrame("PlayerModel", nil, panel)
    m:SetPoint("TOPLEFT", 4, -4)
    m:SetPoint("BOTTOMRIGHT", -4, 4)
    m:SetFrameLevel(panel:GetFrameLevel() + 1)
    m:EnableMouse(true)
    m:EnableMouseWheel(true)
    local function Rotate(self)
        if self.dragging and IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then self.dragging = false end
        if not self.dragging then self:SetScript("OnUpdate", nil) return end
        local x = GetCursorPosition()
        local dx = x - (self.lastX or x)
        self.lastX = x
        self.facing = (self.facing or 0) + dx * 0.01
        pcall(self.SetFacing, self, self.facing)
    end
    m:SetScript("OnMouseDown", function(self)
        self.dragging, self.lastX = true, GetCursorPosition()
        self:SetScript("OnUpdate", Rotate)
    end)
    m:SetScript("OnMouseUp", function(self) self.dragging = false self:SetScript("OnUpdate", nil) end)
    m:SetScript("OnMouseWheel", function(self, delta)
        self.zoom = math.max(0.4, math.min(3, (self.zoom or 1) - delta * 0.15))
        pcall(self.SetCamDistanceScale, self, self.zoom)
    end)
    panel.model = m
    local overlay = CreateFrame("Frame", nil, panel)
    overlay:SetAllPoints(panel)
    overlay:SetFrameLevel(m:GetFrameLevel() + 1)
    panel.note = T.MakeText(overlay, 11.5, T.TEXT_MUTE)
    panel.note:SetPoint("BOTTOM", 0, 6)
    panel.note:SetJustifyH("CENTER")
    return panel
end

-- ----------------------------------------------------------- corner glow

-- One soft haze in the accent colour in the header's far corner (MerkUI:
-- Alex picked this over a starfield). Blizzard's radial GenericGlow64
-- sprite, additive, very low alpha, two sizes stacked for a long falloff.
local HAZE = "Interface\\Glues\\Models\\UI_Draenei\\GenericGlow64"
local spaceLayers = {}

function T.CornerGlow(f, shell)
    local holder = CreateFrame("Frame", nil, f)
    holder:SetAllPoints()
    holder:SetFrameLevel(f:GetFrameLevel())
    holder.hazes = {}
    local spots = {
        { 900, 300, -60, 10, 0.10 },
        { 480, 190, -40, 16, 0.14 },
    }
    for i, sp in ipairs(spots) do
        local t = holder:CreateTexture(nil, "BACKGROUND", nil, 0)
        t:SetTexture(HAZE)
        if t.SetBlendMode then t:SetBlendMode("ADD") end
        t:SetSize(sp[1], sp[2])
        t:SetPoint("CENTER", holder, "TOPRIGHT", sp[3], -sp[4])
        t.alpha = sp[5]
        holder.hazes[i] = t
    end
    function holder:Repaint()
        local r, g, b = T.Accent()
        for _, t in ipairs(self.hazes) do t:SetVertexColor(r, g, b, t.alpha) end
    end
    holder:Repaint()
    spaceLayers[#spaceLayers + 1] = holder
    if shell then shell:Register({ repaint = holder }) end
    return holder
end

-- ---------------------------------------------------------------- shell

--- The window shell (MerkUI Theme.MakeShell): drop shadow, bg, border,
-- sidebar column, header band with accent line and halo, title block, close
-- square, ESC via UISpecialFrames. Returns shell{frame, side, header, title,
-- subtitle, close, border, content, accentParts, Register, Repaint}.
-- Shell accent API. A shell's parts also join the global registry.
local ShellProto = {}
function ShellProto:Register(part)
    table.insert(self.accentParts, part)
    T.Paint(part)
end
function ShellProto:Repaint()
    for _, p in ipairs(self.accentParts) do T.RepaintPart(p) end
    if self.border then self.border:SetColor(T.EDGE[1], T.EDGE[2], T.EDGE[3], 1) end
end

function T.MakeShell(name, w, h, sidebarW, headerH, titleText)
    local shell = setmetatable({ accentParts = {} }, { __index = ShellProto })
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(120)
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    shell.frame = f

    for i = 1, 3 do
        local s = T.SolidTex(f, "BACKGROUND", 0, 0, 0, 0.18 / i, -8 + i)
        s:SetPoint("TOPLEFT", -3 * i, 3 * i)
        s:SetPoint("BOTTOMRIGHT", 3 * i, -3 * i)
    end
    local bg = T.SolidTex(f, "BACKGROUND", T.BG[1], T.BG[2], T.BG[3], 0.985, -1)
    bg:SetAllPoints()
    shell.border = T.Border(f)
    shell.border:Layout(f, 1, 0)
    shell.border:Show()
    shell.space = T.CornerGlow(f, shell)

    local side = CreateFrame("Frame", nil, f)
    side:SetPoint("TOPLEFT", 0, 0)
    side:SetPoint("BOTTOMLEFT", 0, 0)
    side:SetWidth(sidebarW)
    local sideBg = T.SolidTex(side, "BACKGROUND", T.SIDEBAR[1], T.SIDEBAR[2], T.SIDEBAR[3], 1)
    sideBg:SetAllPoints()
    local divider = T.SolidTex(f, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", sidebarW, 0)
    divider:SetPoint("BOTTOMLEFT", sidebarW, 0)
    shell.side = side

    local header = CreateFrame("Frame", nil, f)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:SetHeight(headerH)
    local headerBg = T.SolidTex(header, "BACKGROUND", T.HEADER[1], T.HEADER[2], T.HEADER[3], 1)
    headerBg:SetAllPoints()
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() f:StartMoving() end)
    header:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    shell.header = header

    -- Slab: no accent line under the header; a hairline only.
    local headLine = T.SolidTex(f, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    headLine:SetHeight(1)
    headLine:SetPoint("TOPLEFT", sidebarW + 1, -headerH)
    headLine:SetPoint("TOPRIGHT", 0, -headerH)
    local sideLine = T.SolidTex(f, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    sideLine:SetHeight(1)
    sideLine:SetPoint("TOPLEFT", 0, -headerH)
    sideLine:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -headerH)

    -- The brand, Slab style (Alex, 2026-09-20): a capitals title stacks
    -- one word per line in the heavy display face, the first word white,
    -- the second in the accent (SALUS / NOVUS). Word pairs stay pooled in
    -- shell.words (initial + rest, both the same size and colour now);
    -- initial/title remain the first pair's strings. No mark.
    shell.words = {}
    local LINE_H = 26
    local function Pair(i)
        local w = shell.words[i]
        if w then return w end
        w = { initial = T.MakeText(header, LINE_H, T.TEXT), rest = T.MakeText(header, LINE_H, T.TEXT) }
        T.SetDisplay(w.initial, LINE_H)
        T.SetDisplay(w.rest, LINE_H)
        w.initial:SetPoint("TOPLEFT", header, "TOPLEFT", 22, -6 - (i - 1) * (LINE_H + 2))
        w.rest:SetPoint("LEFT", w.initial, "RIGHT", 0, 0)
        shell:Register({ repaint = { Repaint = function()
            if i >= 2 then
                local r, g, b = T.Accent()
                w.initial:SetTextColor(r, g, b, 1)
                w.rest:SetTextColor(r, g, b, 1)
            else
                w.initial:SetTextColor(1, 1, 1, 1)
                w.rest:SetTextColor(1, 1, 1, 1)
            end
        end } })
        shell.words[i] = w
        return w
    end
    Pair(1)
    shell.initial, shell.title = shell.words[1].initial, shell.words[1].rest
    function shell:SetTitle(text)
        text = tostring(text or "")
        local n = 0
        if text:match("^%u[%u ]+$") then
            for word in text:gmatch("%u+") do
                n = n + 1
                local w = Pair(n)
                w.initial:SetText(word:sub(1, 1)); w.initial:Show()
                w.rest:SetText(word:sub(2)); w.rest:Show()
            end
        else
            n = 1
            self.initial:SetText(""); self.initial:Hide()
            self.title:SetText(text); self.title:Show()
        end
        for i = n + 1, #self.words do self.words[i].initial:Hide(); self.words[i].rest:Hide() end
    end
    shell:SetTitle(titleText)
    shell.subtitle = T.MakeText(header, 11, T.TEXT_MUTE)
    shell.subtitle:SetPoint("TOPLEFT", shell.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, header)
    close:SetSize(36, 36)
    close:SetPoint("RIGHT", -16, 0)
    local cbg = T.SolidTex(close, "BACKGROUND", 1, 1, 1, 0.04)
    cbg:SetAllPoints()
    close.border = T.Border(close)
    close.border:Layout(close, 1, 0)
    close.border:SetColor(1, 1, 1, 0.10)
    close.border:Show()
    -- The X is two bars turned 45 degrees, centred and nearly the size of
    -- the button: a glyph sat off-centre and small in every font (Alex).
    close.bars = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local bar = T.SolidTex(close, "ARTWORK", T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1)
        bar:SetSize(24, 2)
        bar:SetPoint("CENTER", close, "CENTER", 0, 0)
        if bar.SetRotation then pcall(bar.SetRotation, bar, angle) end
        close.bars[i] = bar
    end
    function close:SetGlyphColor(r, g, b, a)
        for _, bar in ipairs(self.bars) do bar:SetVertexColor(r, g, b, a) end
    end
    close:SetScript("OnEnter", function(self) self.border:SetColor(1, 1, 1, 0.35) self:SetGlyphColor(1, 1, 1, 1) end)
    close:SetScript("OnLeave", function(self) self.border:SetColor(1, 1, 1, 0.10) self:SetGlyphColor(T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1) end)
    close:SetScript("OnClick", function() f:Hide() end)
    shell.close = close

    if name and UISpecialFrames then table.insert(UISpecialFrames, name) end

    local content = CreateFrame("Frame", nil, f)
    content:SetPoint("TOPLEFT", sidebarW + 1, -headerH - 2)
    content:SetPoint("BOTTOMRIGHT", 0, 0)
    shell.content = content

    shell:Repaint()
    return shell
end
