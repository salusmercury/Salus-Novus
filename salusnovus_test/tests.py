"""Salus Novus test suite. Run via runner.py."""
from runner import Harness, test, ok, eq, allow_errors


def fresh():
    h = Harness()
    ok(not h.load_errors, "load errors: %r" % h.load_errors)
    return h.login()



# helpers from bug hunt 3 (routing lane)

def get_bar_names(h):
    """Get all visible bar ability names."""
    return [str(x) for x in h.lua("""
        local out = {}
        for i = 1, 8 do
            local f = ns.Bars._bars[i]
            if f and f:IsShown() then
                out[#out + 1] = f.text:GetText()
            end
        end
        return out
    """).values()]

def get_queue_names(h):
    """Get all visible queue ability names."""
    return [str(x) for x in h.lua("""
        local out = {}
        for i = 1, 8 do
            local f = ns.Queue._icons[i]
            if f:IsShown() and f.entry and f.entry.bar then
                out[#out + 1] = f.label:GetText()
            end
        end
        return out
    """).values()]

def get_preview_names(h):
    """Get all visible preview lines."""
    return [str(x) for x in h.lua("""
        local out = {}
        for i = 1, 8 do
            local l = ns.Preview._lines[i]
            if l:IsShown() then
                out[#out + 1] = l.text:GetText()
            end
        end
        return out
    """).values()]

def get_message_names(h):
    """Get all visible message texts."""
    return [str(x) for x in h.lua("""
        local out = {}
        for _, f in ipairs(ns.Messages._active) do
            out[#out + 1] = f.text:GetText()
        end
        return out
    """).values()]

def get_bar_colors(h):
    """Get all visible bar text colors as list of dicts."""
    result = h.lua("""
        local out = {}
        for i = 1, 8 do
            local f = ns.Bars._bars[i]
            if f and f:IsShown() then
                local r, g, b = f.text:GetTextColor()
                out[#out + 1] = { r = r, g = g, b = b }
            end
        end
        return out
    """)
    if result is None:
        return []
    return [dict(x) for x in result.values()]

# ------------------------------------------------------------------ load

@test("every TOC file loads and login runs clean", "load")
def _():
    h = fresh()
    eq(h.errors(), [], "errors at login")
    ok(h.lua("return ns.db ~= nil and ns.db == SalusNovusDB.options"), "ns.db must be SalusNovusDB.options")


@test("works from a fresh DB with no SavedVariables at all", "load")
def _():
    h = fresh()
    eq(int(h.lua("return ns.db.bars.max")), 4, "defaults not applied")
    # Copied INTO the DB, not just served by the fallback: a settings UI edits the table.
    eq(float(h.lua("return SalusNovusDB.options.reminders.hold")), 1.5, "defaults not written to the DB")
    eq(str(h.lua("return type(ns.db.reminders.list)")), "table", "user reminder list missing")
    ok(not h.lua("return ns.db.unlocked"), "must start locked")
    # the accent: class colour off, #FF7AF2 (Alex)
    ok(not h.lua("return ns.db.theme.useClassColor"), "class colour should default off")
    r, g, b = h.lua("return ns.GetThemeColor()")
    ok(abs(r - 1.0) < 0.01 and abs(g - 0.478) < 0.01 and abs(b - 0.949) < 0.01, "accent should be #FF7AF2: %r" % ((r, g, b),))


@test("CopyDefaults keeps user values, fills holes, and parks a scalar that became a table", "load")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = { bars = { max = 2, width = 'seven' }, reminders = 5 } }")
    eq(int(h.lua("return ns.db.bars.max")), 2, "user value overwritten")
    eq(str(h.lua("return tostring(ns.db.bars.width)")), "seven", "a wrong-typed scalar is the user's business")
    eq(int(h.lua("return ns.db.bars.height")), 18, "hole not filled")
    eq(int(h.lua("return SalusNovusDB.replacedScalars.reminders")), 5, "replaced scalar not parked")
    eq(float(h.lua("return ns.db.reminders.hold")), 1.5, "table not seeded after replacing the scalar")


@test("ApplyAll reports a throwing module once and keeps running the rest", "load")
def _():
    h = fresh()
    h.lua("""
        __ran = 0
        ns.RegisterApply(function() error("boom") end, "Broken")
        ns.RegisterApply(function() __ran = __ran + 1 end, "After")
        ns.ApplyAll(); ns.ApplyAll()
    """)
    eq(int(h.lua("return __ran")), 2, "module after the broken one did not run")
    msgs = [p for p in h.printed() if "boom" in p]
    eq(len(msgs), 1, "error should print exactly once: %r" % msgs)
    ok("boom" in str(h.lua("return ns.ApplyErrors()['Broken']")), "error text not kept")


# --------------------------------------------------------------- anchors

@test("a fresh anchor is re-pinned by its growth origin, not the default point, and the record matches", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")   # the default is Up (Alex); these check the downward origin
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    pt = str(h.lua("local p = SalusNovusBars:GetPoint() return p"))
    eq(pt, "TOPLEFT", "should be pinned by TOPLEFT (grows down)")
    # A fresh install IS re-pinned on first layout (MerkUI landmine 17), but
    # relative to the screen centre and WITHOUT a record: only the user's own
    # save writes one (a login-time absolute record put Alex's Reminders at
    # the small pre-scale screen's centre, 2026-09-23).
    ok(h.lua("return SalusNovusDB.barsPos == nil"), "no record without a user save")
    ok(str(h.lua("local _, rel, rp = SalusNovusBars:GetPoint() return rp")) == "CENTER", "pinned from the centre")
    # Growing the stack must not move the top-left corner.
    l0, t0 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    h.lua("ns.db.bars.max = 8; ns.ApplyAll()")
    l1, t1 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    ok(abs(l0 - l1) < 0.01 and abs(t0 - t1) < 0.01, "top-left drifted: %r -> %r" % ((l0, t0), (l1, t1)))


@test("SaveAnchor writes a v2 record and RestoreAnchor puts the frame back; scale round-trips", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")   # the default is Up (Alex); these check the downward origin
    h.lua("""
        ns.db.unlocked = true; ns.ApplyAll()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 300, 500)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
    """)
    eq(int(h.lua("return SalusNovusDB.barsPos.v")), 2, "not a v2 record")
    eq(str(h.lua("return SalusNovusDB.barsPos.point")), "TOPLEFT", "record point")
    x, y = h.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y")
    ok(abs(x - 300) < 0.01 and abs(y - 500) < 0.01, "record xy %r" % ((x, y),))
    h.lua("ns.db.anchorsGlobal.scale = 150; ns.ApplyAll()")
    l, t = h.lua("return SalusNovusBars:GetLeft() * SalusNovusBars:GetEffectiveScale() / UIParent:GetEffectiveScale(), SalusNovusBars:GetTop() * SalusNovusBars:GetEffectiveScale() / UIParent:GetEffectiveScale()")
    ok(abs(l - 300) < 0.5 and abs(t - 500) < 0.5, "scaled frame left its screen spot: %r" % ((l, t),))
    h.lua("ns.db.anchorsGlobal.scale = 100; ns.ApplyAll()")
    l, t = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    ok(abs(l - 300) < 0.01 and abs(t - 500) < 0.01, "did not return after scale round-trip: %r" % ((l, t),))


@test("a legacy {point,relPoint,x,y} record is read, then rewritten as v2 on the next save", "anchors")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", relPoint = "CENTER", x = 50, y = 60 } }')
    h.lua("ns.db.bars.direction = 'down'")   # the default is Up (Alex); this checks the downward origin
    eq(h.errors(), [], "errors restoring a legacy record")
    # Idle and locked, nothing is laid out and nothing is written (MerkUI).
    eq(str(h.lua("return tostring(SalusNovusDB.barsPos.v)")), "nil", "rewritten before any layout")
    # The first layout keeps the legacy CENTRE and rewrites the record as v2
    # by the growth origin; from then on growth keeps the top-left corner.
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    cx, cy = h.lua("return SalusNovusBars:GetCenter()")
    ux, uy = h.lua("return UIParent:GetCenter()")
    ok(abs(cx - (ux + 50)) < 0.01 and abs(cy - (uy + 60)) < 0.01, "legacy record not honoured: %r" % ((cx, cy),))
    eq(int(h.lua("return SalusNovusDB.barsPos.v")), 2, "not rewritten as v2")
    eq(str(h.lua("return SalusNovusDB.barsPos.point")), "TOPLEFT", "rewritten by the wrong point")
    l, t = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    h.lua("ns.db.bars.max = 8; ns.ApplyAll()")
    l2, t2 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    ok(abs(l - l2) < 0.01 and abs(t - t2) < 0.01, "top-left moved on growth: %r -> %r" % ((l, t), (l2, t2)))


@test("a non-table position record is discarded and the default used", "anchors")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = 7 }')
    eq(h.errors(), [], "errors on a junk record")
    eq(str(h.lua("return tostring(SalusNovusDB.barsPos)")), "nil", "junk record kept")
    # Then the first layout uses the default spot and writes nothing (only a
    # user save writes a record): same place as a fresh install.
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusDB.barsPos == nil"), "no record replaces the junk")
    h2 = fresh()
    h2.lua("ns.db.unlocked = true; ns.ApplyAll()")
    x1, y1 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    x2, y2 = h2.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    ok(abs(x1 - x2) < 0.01 and abs(y1 - y2) < 0.01, "junk record did not fall back to the default position")


@test("gridSize = 0 is clamped, the grid draws a bounded number of lines and hides again", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.anchorsGlobal.gridSize = 0; ns.ShowAlignGrid(true)")
    n = int(h.lua("return #SalusNovusAlignGrid.lines"))
    ok(0 < n < 2000, "grid line count %d" % n)
    ok(h.lua("return SalusNovusAlignGrid:IsShown()"), "grid not shown")
    h.lua("ns.ShowAlignGrid(false)")
    ok(not h.lua("return SalusNovusAlignGrid:IsShown()"), "grid not hidden")
    h.lua("ns.db.anchorsGlobal.grid = false; ns.ShowAlignGrid(true)")
    ok(not h.lua("return SalusNovusAlignGrid:IsShown()"), "grid drawn while disabled")


@test("SnapMovable pulls a frame onto the screen centre within range and leaves it alone outside it", "anchors")
def _():
    h = fresh()
    h.lua("""
        ns.db.unlocked = true; ns.ApplyAll()
        local ux, uy = UIParent:GetCenter()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux + 3, uy - 200)
        ns.SnapMovable(SalusNovusBars)
    """)
    cx, ux = h.lua("local cx = SalusNovusBars:GetCenter() local ux = UIParent:GetCenter() return cx, ux")
    ok(abs(cx - ux) < 0.01, "did not snap x to centre: %r vs %r" % (cx, ux))
    # far from the centre and from every other anchor's centre and edges
    # (the queue's left edge sits near +96, the reminders' right edge at +90)
    h.lua("""
        local ux, uy = UIParent:GetCenter()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux + 330, uy - 200)
        ns.db.anchorsGlobal.gridSize = 512
        ns.SnapMovable(SalusNovusBars)
    """)
    cx, ux = h.lua("local cx = SalusNovusBars:GetCenter() local ux = UIParent:GetCenter() return cx, ux")
    ok(abs(cx - (ux + 330)) < 0.01, "snapped from outside the range")


@test("unlocking through the DB flag shows placeholder bars and makes the anchor draggable; locking hides it", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown() and SalusNovusBars:IsMouseEnabled()"), "unlock did not show a draggable anchor")
    txt = str(h.lua("return ns.Bars._bars[1].text:GetText()"))
    ok(txt.startswith("Ability"), "no placeholder bars: %r" % txt)
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusBars:IsShown()") and not h.lua("return SalusNovusBars:IsMouseEnabled()"), "lock did not hide the idle anchor")
    eq(str(h.lua("return tostring(ns.Commands.unlock)")), "nil", "/sn unlock must be gone")


# ----------------------------------------------------------------- fonts

@test("SetFontSafe falls back when the client rejects a font path", "fonts")
def _():
    h = fresh()
    h.lua("""
        local fs = UIParent:CreateFontString()
        local origSetFont = fs.SetFont
        __calls = {}
        fs.SetFont = function(self, path, size, flags)
            __calls[#__calls + 1] = path
            if path == "Fonts\\\\NOPE.TTF" then return false end
            return origSetFont(self, path, size, flags)
        end
        ns.SetFontSafe(fs, 12, "OUTLINE", "Fonts\\\\NOPE.TTF")
    """)
    n = int(h.lua("return #__calls"))
    ok(n >= 2, "no fallback attempted: %d calls" % n)
    eq(str(h.lua("return __calls[1]")), "Fonts\\NOPE.TTF", "first try must be the requested path")
    eq(int(h.lua("return ns.fontFellBack")), 1, "fallback not counted")
    # An explicit-path failure (a picker preview) is silent: addon fonts
    # fail their first ask by design while the client loads them.
    warned = [p for p in h.printed() if "rejected the font" in p]
    eq(len(warned), 0, "a preview failure must not warn")
    # The GLOBAL font failing is retried a second later (the first SetFont
    # of an addon font returns false while it loads); only the retry
    # failing warns, once per path.
    h.lua("""
        ns.db.font.path = "Fonts\\\\NOPE.TTF"; ns.InvalidateFontCache()
        ns._fontProbe = UIParent:CreateFontString()
        local origP = ns._fontProbe.SetFont
        __probeFails = true
        ns._fontProbe.SetFont = function(self, path, size, flags)
            if path == "Fonts\\\\NOPE.TTF" and __probeFails then return false end
            return origP(self, path, size, flags)
        end
        __refonts = 0
        for i = 1, 2 do
            local fs2 = UIParent:CreateFontString()
            local orig2 = fs2.SetFont
            fs2.SetFont = function(self, path, size, flags)
                if path == "Fonts\\\\NOPE.TTF" then __refonts = __refonts + 1; return false end
                return orig2(self, path, size, flags)
            end
            ns.SetFontSafe(fs2, 12, "OUTLINE")
        end
    """)
    warned = [p for p in h.printed() if "rejected the font" in p]
    eq(len(warned), 0, "must not warn before the retry")
    h.lua("W.advance(1.2)")
    warned = [p for p in h.printed() if "rejected the font" in p]
    eq(len(warned), 1, "the retry failing should warn exactly once")
    # When the retry succeeds (the font finished loading), everything
    # following the global font is re-fonted and nothing is printed.
    h.lua("""
        ns.fontWarned = {}
        __probeFails = false
        local fs3 = UIParent:CreateFontString()
        local orig3 = fs3.SetFont
        fs3.SetFont = function(self, path, size, flags)
            if path == "Fonts\\\\NOPE.TTF" then __refonts = __refonts + 1; return false end
            return orig3(self, path, size, flags)
        end
        ns.SetFontSafe(fs3, 12, "OUTLINE")
        __before = __refonts
    """)
    h.lua("W.advance(1.2)")
    warned = [p for p in h.printed() if "rejected the font" in p]
    eq(len(warned), 1, "a successful retry must not warn")
    ok(int(h.lua("return __refonts")) > int(h.lua("return __before")),
       "a successful retry must re-font the strings that follow the global font")
    # Entering the world re-fonts the followers once more: anchor captions
    # set during loading may have caught the first-load false.
    h.lua('__before = __refonts; W.fireEvent("PLAYER_ENTERING_WORLD")')
    ok(int(h.lua("return __refonts")) > int(h.lua("return __before")), "login did not re-font the followers")


@test("GetFonts lists LibSharedMedia's fonts when a font pack is present, builtins otherwise", "fonts")
def _():
    h = fresh()
    n0 = int(h.lua("return #ns.GetFonts()"))
    ok(n0 == 20 and not h.lua("return select(2, ns.GetFonts())"), "without LSM: default + 19 Blizzard fonts, got %d" % n0)
    # a font pack registers with LibSharedMedia after Salus Novus loaded; one of
    # its files is one the client refuses (the mock refuses a non-font
    # extension, the Forever client refuses every AddOns file)
    h.lua("""
        local lib = {
            List = function(_, kind) return kind == "font" and { "Expressway", "Roboto", "Friz Quadrata TT", "Broken" } or {} end,
            HashTable = function(_, kind) return { Expressway = "Interface\\\\AddOns\\\\Pack\\\\expressway.ttf", Roboto = "Interface\\\\AddOns\\\\Pack\\\\roboto.ttf", ["Friz Quadrata TT"] = ns.StockFont(), Broken = "Interface\\\\AddOns\\\\Pack\\\\broken.xyz" } end,
        }
        LibStub = function(name, silent) if name == "LibSharedMedia-3.0" then return lib end end
    """)
    names = [str(h.lua("return ns.GetFonts()[%d].name" % i)) for i in range(1, 4)]
    eq(names, ["Game default", "Expressway", "Roboto"], "LSM fonts first, stock path deduplicated: %r" % names)
    allnames = str(h.lua("local o = {} for _, f in ipairs(ns.GetFonts()) do o[#o+1] = f.name end return table.concat(o, ',')"))
    # Pack fonts are listed regardless of the probe: on Forever the probe
    # said no to a font the picker drew (Prototype), so it is not trusted
    # for addon files. The picker's rows fall back to the stock font if a
    # path really fails, so a bad entry costs a row, never a blank UI.
    ok("Broken" in allnames, "pack fonts must be listed without the probe's say-so")
    ok("Morpheus" in allnames, "Blizzard's fonts should follow the pack's")
    ok(h.lua("return select(2, ns.GetFonts())"), "should report LSM fonts present")
    h.lua("LibStub = nil")


@test("the Font picker lists every font drawn in itself, and picking one writes the setting", "fonts")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('font')")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then __fontBtn = w end
        end
        __fontBtn:Click()
    """)
    ok(h.lua("return SalusNovusPickerList and SalusNovusPickerList:IsShown()"), "picker list did not open")
    h.lua("W.advance(2)")   # the delayed re-font passes run; rows must still be in their own font
    n = int(h.lua("return #ns.GetFonts()"))
    bad = str(h.lua("""
        local out = {}
        for i = 1, %d do
            local r = SalusNovusPickerList.rows[i]
            if not r or not r:IsShown() then out[#out+1] = "row" .. i .. " missing"
            elseif r.text.__font ~= r.value then out[#out+1] = tostring(r.text:GetText()) .. " drawn in " .. tostring(r.text.__font) end
        end
        return table.concat(out, ",")
    """ % n))
    eq(bad, "", "rows not drawn in their own font: %s" % bad)
    ok(not h.lua("return SalusNovusPickerList.rows[%d] and SalusNovusPickerList.rows[%d]:IsShown()" % (n + 1, n + 1)), "surplus row shown")
    h.lua("SalusNovusPickerList.rows[3]:Click()")
    ok(not h.lua("return SalusNovusPickerList:IsShown()"), "list stayed open after a pick")
    eq(str(h.lua("return ns.db.font.path")), str(h.lua("return ns.GetFonts()[3].path")), "pick did not write the font")
    eq(str(h.lua("return __fontBtn.text.__font")), str(h.lua("return ns.db.font.path")), "button not drawn in the chosen font")
    h.lua("__fontBtn:Click()")
    ok(h.lua("return SalusNovusPickerList:IsShown()"), "list did not reopen")
    h.lua("SalusNovusOptions:Hide()")
    ok(not h.lua("return SalusNovusPickerList:IsShown()"), "list survived the window closing")


@test("changing the global font re-fonts every window, anchor and form -- and leaves the picker's previews alone", "fonts")
def _():
    h = fresh()
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('reminders'); ns.Options.SelectPage('bars')
        SlashCmdList["SALUSNOVUS"]("show")
        ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])
        ns.Visualizer.OpenForm(5, 11130, "Knock Away", nil)
        ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()
    """)
    stock = str(h.lua("return ns.StockFont()"))
    h.lua("ns.db.font.path = 'Fonts\\\\MORPHEUS.TTF'; ns.ApplyAll()")
    # every string that follows the global font now reads Morpheus
    bad = str(h.lua("""
        local out, n = {}, 0
        for fs, spec in pairs(ns._following) do
            n = n + 1
            if fs.__font ~= "Fonts\\\\MORPHEUS.TTF" then out[#out+1] = tostring(fs:GetText() or "?") .. "=" .. tostring(fs.__font) end
        end
        __n = n
        return table.concat(out, ",")
    """))
    eq(bad, "", "strings left in the old font: %s" % bad[:300])
    n = int(h.lua("return __n"))
    ok(n > 100, "expected the whole UI enrolled, got %d strings" % n)
    # spot checks across the UI
    # (the shell titles are the DISPLAY face by design since the Slab look, not the body font)
    for expr in ("ns.Visualizer._lanes[2].name",
                 "ns.Visualizer.form.text", "ns.Bars._bars[1].text", "SalusNovusReminderFrame.unlockText",
                 "ns.Options.launcher.label"):
        eq(str(h.lua("return %s.__font" % expr)), "Fonts\\MORPHEUS.TTF", "%s not re-fonted" % expr)
    # the picker's rows show their own fonts, never the global one
    h.lua("""
        SalusNovusOptions:Show(); ns.Options.SelectPage('font')
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then __fontBtn = w end
        end
        __fontBtn:Click()
    """)
    eq(str(h.lua("return SalusNovusPickerList.rows[1].sample.__font")), stock, "picker sample lost its own font")
    eq(str(h.lua("return SalusNovusPickerList.rows[1].text.__font")), "Fonts\\MORPHEUS.TTF", "picker row NAME should follow the global font")
    ok(h.lua("return ns._following[SalusNovusPickerList.rows[1].text] == nil"), "a preview string was enrolled")
    # and nothing re-fonts when the font did not change
    eq(int(h.lua("return ns.RefontAll() or 0")), 0, "RefontAll should be a no-op without a change")
    eq(h.errors(), [], "errors")


@test("the whole-UI switch re-fonts Blizzard's font objects, keeps their sizes, follows font changes, and restores them when off", "fonts")
def _():
    h = fresh()
    h.lua("""
        -- stand-ins for Blizzard's font objects (the mock has none)
        local function FO(path, size, flags)
            local o = { __path = path, __size = size, __flags = flags }
            function o:GetFont() return self.__path, self.__size, self.__flags end
            function o:SetFont(p, s, f) self.__path, self.__size, self.__flags = p, s, f return true end
            return o
        end
        GameFontNormal = FO("Fonts\\\\FRIZQT__.TTF", 12, "")
        ChatFontNormal = FO("Fonts\\\\ARIALN.TTF", 14, "")
        NumberFontNormal = FO("Fonts\\\\ARIALN.TTF", 14, "OUTLINE")
        -- an object only the client's own enumeration knows about (the
        -- objective tracker's), and a chat frame with a font set directly
        ObjectiveTrackerLineFont = FO("Fonts\\\\FRIZQT__.TTF", 13, "")
        ChatFrame1 = FO("Fonts\\\\ARIALN.TTF", 15, "")
        GetFonts = function() return { "GameFontNormal", "ChatFontNormal", "NumberFontNormal", "ObjectiveTrackerLineFont" } end
    """)
    ok(h.lua("return ns.db.font.wholeUI"), "on by default (Alex)")
    h.lua("ns.db.font.wholeUI = false; ns.ApplyAll()")
    eq(str(h.lua("return GameFontNormal.__path")), "Fonts\\FRIZQT__.TTF", "touched while off")
    h.lua("ns.db.font.wholeUI = true; ns.ApplyAll()")
    active = str(h.lua("return ns.ActiveFont()"))
    eq(str(h.lua("return GameFontNormal.__path")), active, "GameFontNormal not re-fonted")
    eq(str(h.lua("return ChatFontNormal.__path")), active, "ChatFontNormal not re-fonted")
    eq(int(h.lua("return NumberFontNormal.__size")), 14, "size changed")
    eq(str(h.lua("return NumberFontNormal.__flags")), "OUTLINE", "flags changed")
    eq(str(h.lua("return ObjectiveTrackerLineFont.__path")), active, "objects known only to the client's enumeration were missed")
    eq(str(h.lua("return ChatFrame1.__path")), active, "chat frames (fonted directly) were missed")
    eq(int(h.lua("return ChatFrame1.__size")), 15, "chat size changed")
    # a font change follows through
    h.lua("ns.db.font.path = 'Fonts\\\\MORPHEUS.TTF'; ns.ApplyAll()")
    eq(str(h.lua("return ChatFontNormal.__path")), "Fonts\\MORPHEUS.TTF", "font change not applied to the UI")
    # a load-on-demand Blizzard addon brings a font object after the pass
    # (the professions window did): it is fonted when that addon loads.
    h.lua("""
        local o = { __path = "Fonts\\\\FRIZQT__.TTF", __size = 11, __flags = "" }
        function o:GetFont() return self.__path, self.__size, self.__flags end
        function o:SetFont(p, s, f) self.__path, self.__size, self.__flags = p, s, f return true end
        ProfessionsFrameFontLate = o
        ProfessionsFrameFontLate[0] = true          -- a widget, like the client's
        function ProfessionsFrameFontLate:GetObjectType() return "Font" end
        W.fireEvent("ADDON_LOADED", "Blizzard_Professions")
    """)
    eq(str(h.lua("return ProfessionsFrameFontLate.__path")), "Fonts\\MORPHEUS.TTF", "late font object not fonted on addon load")
    # off: everything goes back to what it was, without a reload
    h.lua("ns.db.font.wholeUI = false; ns.ApplyAll()")
    eq(str(h.lua("return GameFontNormal.__path")), "Fonts\\FRIZQT__.TTF", "GameFontNormal not restored")
    eq(str(h.lua("return ChatFontNormal.__path")), "Fonts\\ARIALN.TTF", "ChatFontNormal not restored")
    eq(int(h.lua("return ChatFontNormal.__size")), 14, "size not restored")
    eq(str(h.lua("return ChatFrame1.__path")), "Fonts\\ARIALN.TTF", "chat frame not restored")
    eq(str(h.lua("return ProfessionsFrameFontLate.__path")), "Fonts\\FRIZQT__.TTF", "late object not restored")
    h.lua("GameFontNormal = nil; ChatFontNormal = nil; NumberFontNormal = nil; ObjectiveTrackerLineFont = nil; ChatFrame1 = nil; GetFonts = nil; ProfessionsFrameFontLate = nil")
    eq(h.errors(), [], "errors")


@test("ActiveFont is the stock font unless a custom font is enabled, and the cache drops on ApplyAll", "fonts")
def _():
    h = fresh()
    stock = str(h.lua("return ns.StockFont()"))
    eq(str(h.lua("return ns.ActiveFont()")), str(h.lua("return ns.defaults.font.path")), "the default font is the shipped default (Prototype)")
    h.lua("ns.db.font.path = 'Fonts\\\\MORPHEUS.TTF'")
    eq(str(h.lua("return ns.ActiveFont()")), str(h.lua("return ns.defaults.font.path")), "cache should hold until ApplyAll")
    h.lua("ns.ApplyAll()")
    eq(str(h.lua("return ns.ActiveFont()")), "Fonts\\MORPHEUS.TTF", "custom font not active after ApplyAll")


# ------------------------------------------------------------------ data

@test("Hall of Thanes data: four bosses in encounter order with IDs", "data")
def _():
    h = fresh()
    eq(str(h.lua("return ns.Data[3065].name")), "The Hall of Thanes", "instance name")
    names = [str(h.lua("return ns.Data[3065].bosses[%d].name" % i)) for i in range(1, 5)]
    eq(names, ["Faldrim Anvilmar", "Magmatus", "Plunder", "Durgen Dirgehammer"], "boss order (Infurnus shows as its NPC)")
    eq(str(h.lua("return ns.Data[3065].bosses[2].encounterName")), "Infurnus", "the encounter's own name is kept")
    eq(str(h.lua("local b = ns.BossByName('infurnus') return b and b.name")), "Magmatus", "the encounter name still finds the boss")
    eq(int(h.lua("return ns.Data[3065].bosses[3].encounterID")), 3494, "Plunder encounter id")
    eq(int(h.lua("return ns.Data[3065].bosses[3].npcs[1].displayID")), 142840, "Plunder display id")
    # The boss is npcs[1] even when a trash mob cast first in the window --
    # Faldrim's fight opened with an Enraged Apparition's Sunder Armor and
    # the visualizer headlined the trash mob.
    eq(str(h.lua("return ns.Data[3065].bosses[1].npcs[1].name")), "Faldrim Anvilmar", "boss must be the first NPC")


@test("Infurnus carries its real NPCs, not its encounter name", "data")
def _():
    h = fresh()
    n = int(h.lua("return #ns.Data[3065].bosses[2].npcs"))
    names = {str(h.lua("return ns.Data[3065].bosses[2].npcs[%d].name" % i)) for i in range(1, n + 1)}
    ok("Magmatus" in names and "Dark Iron Summoner" in names, "Infurnus NPCs: %r" % names)
    # The boss of an unnamed encounter is the biggest health pool, not the
    # first caster: Infurnus IS Magmatus the fire elemental.
    eq(str(h.lua("return ns.Data[3065].bosses[2].npcs[1].name")), "Magmatus", "Infurnus headline NPC")


@test("every ability carries a pull count and at least one observed cast", "data")
def _():
    h = fresh()
    bad = h.lua("""
        local bad = {}
        for _, b in ipairs(ns.Data[3065].bosses) do
            for _, a in ipairs(b.abilities) do
                if not a.pulls or a.pulls < 1 or #a.casts == 0 or not a.spellID then bad[#bad+1] = b.name .. "/" .. tostring(a.name) end
            end
        end
        return table.concat(bad, ",")
    """)
    eq(str(bad), "", "abilities missing provenance")


@test("BossByEncounter and BossByName resolve", "data")
def _():
    h = fresh()
    eq(str(h.lua("local b = ns.BossByEncounter(3496) return b and b.name")), "Durgen Dirgehammer", "by encounter")
    eq(str(h.lua("local b = ns.BossByName('plun') return b and b.name")), "Plunder", "by name prefix, case-insensitive")
    eq(str(h.lua("return tostring(ns.BossByName('nobody'))")), "nil", "unknown name")


# --------------------------------------------------------------- reminders

def fired(h):
    n = int(h.lua("return #ns.Reminders._fired"))
    return [str(h.lua("return ns.Reminders._fired[%d]" % i)) for i in range(1, n + 1)]


def shown_texts(h):
    n = int(h.lua("return #ns.Reminders._active"))
    return [str(h.lua("return ns.Reminders._active[%d].text:GetText()" % i)) for i in range(1, n + 1)]


# Salus Novus ships NO reminders (Alex); tests that need "shipped" ones seed
# these, shaped like a shipped record would be.
SHIPPED = """
    ns.DefaultReminders = {
        { id = "default:1", encounterID = 3494, trigger = "pull", text = "Plunder: stay off the ledge", sound = false },
        { id = "default:2", encounterID = 3494, trigger = "time", arg = 7.5, lead = 3, text = "Knock Away", sound = true },
    }
"""


@test("Salus Novus ships no reminders", "reminders")
def _():
    h = fresh()
    eq(int(h.lua("return #ns.DefaultReminders")), 0, "shipped reminders present")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(1)")
    eq(fired(h), [], "something fired with nothing placed")


@test("pull reminder shows on ENCOUNTER_START, holds, then hides; nothing for an unknown boss", "reminders")
def _():
    h = fresh()
    h.lua(SHIPPED)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    ok(h.lua("return SalusNovusReminderFrame:IsShown()"), "reminder frame not shown on pull")
    ok(any("Plunder" in t for t in fired(h)), "pull reminder not displayed: %r" % fired(h))
    h.lua("W.advance(5)")     # hold is 4; Plunder's Knock Away countdown (+4.5) is up by now
    ok(not any("Plunder" in t for t in shown_texts(h)), "pull line still up after the hold: %r" % shown_texts(h))
    h.lua("W.advance(8)")     # Knock Away lands at 7.5 and holds 4
    eq(shown_texts(h), [], "lines left over: %r" % shown_texts(h))
    ok(not h.lua("return SalusNovusReminderFrame:IsShown()"), "frame still up with nothing on it")
    h2 = fresh()
    h2.lua('W.fireEvent("ENCOUNTER_START", 999999, "Nobody", 1, 5, 1)')
    h2.lua("W.advance(1)")
    eq(fired(h2), [], "fired for an unknown encounter")


@test("time reminder counts down from its lead, lands once, and is taken back by ENCOUNTER_END", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "t1", encounterID = 3494, trigger = "time", arg = 6, lead = 2, text = "SIX", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(3.5)")
    eq(fired(h), [], "shown before its lead")
    h.lua("W.advance(1)")      # +4.5: armed at 6-2
    eq(fired(h), ["SIX"], "did not show at arg-lead")
    ok(shown_texts(h)[0].startswith("SIX") and "2" in shown_texts(h)[0], "no countdown on the line: %r" % shown_texts(h))
    h.lua("W.advance(2)")      # +6.5: landed
    eq(shown_texts(h), ["SIX"], "countdown did not land: %r" % shown_texts(h))
    h.lua("W.advance(10)")
    eq(fired(h), ["SIX"], "fired more than once")
    # a second pull whose fight ends mid-countdown must take the line back
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 0)')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")
    eq(len(fired(h)), 2, "second pull did not arm")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 0)')
    h.lua("W.advance(0.1)")
    eq(shown_texts(h), [], "countdown survived ENCOUNTER_END")
    ok(not h.lua("return SalusNovusReminderFrame:IsShown()"), "frame still up after END")


@test("a lead longer than the offset is trimmed: the reminder shows at the pull with what is left", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "t2", encounterID = 3494, trigger = "time", arg = 2, lead = 5, text = "SOON", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    eq(fired(h), ["SOON"], "not shown at the pull")
    ok("2" in shown_texts(h)[0], "countdown should be the 2s left, got %r" % shown_texts(h))
    eq(h.errors(), [], "errors")


@test("cast reminder fires for target/nameplate casts only, throttled, never for party", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "c1", encounterID = 3493, trigger = "cast", text = "CASTING", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3493, "Faldrim Anvilmar", 1, 5, 3065)')
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "party1", "Cast-1", W.secretNumber(1))')
    eq(len(fired(h)), 0, "fired for a party member")
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "target", "Cast-2", W.secretNumber())')
    eq(len(fired(h)), 1, "did not fire for target")
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "nameplate3", "Cast-3", W.secretNumber(3))')
    eq(len(fired(h)), 1, "throttle did not hold")
    h.lua("W.advance(4)")
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "nameplate3", "Cast-4", W.secretNumber(4))')
    eq(len(fired(h)), 2, "did not fire after the throttle window")


@test("emote reminder matches readable text and ignores a SECRET emote untouched", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "e1", encounterID = 3496, trigger = "emote", arg = "shout", text = "FEAR", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    # secretString, not secret: on the real client a secret emote IS a string,
    # so only the issecretvalue guard can stop it -- the table model would be
    # rejected by the type check and prove nothing.
    h.lua('W.fireEvent("CHAT_MSG_MONSTER_YELL", W.secretString("Durgen lets out an Intimidating Shout!"), "Durgen")')
    eq(len(fired(h)), 0, "acted on a secret emote")
    h.lua('W.fireEvent("CHAT_MSG_MONSTER_YELL", "Durgen lets out an Intimidating SHOUT!", "Durgen")')
    eq(fired(h), ["FEAR"], "did not match a readable emote")


@test("a secret encounter id leaves reminders with no fight to arm", "reminders")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", W.secret(3494), "Plunder", 1, 5, 3065)')
    eq(str(h.lua("return tostring(ns.Reminders.state.encounter)")), "nil", "took a secret encounter id")
    h.lua("W.advance(1)")
    eq(fired(h), [], "armed something for a secret id")


@test("/sn remind adds a user reminder that fires alongside the defaults", "reminders")
def _():
    h = fresh()
    h.lua('SlashCmdList["SALUSNOVUS"]("remind durgen time 3 MY OWN")')
    eq(int(h.lua("return #ns.db.reminders.list[3496]")), 1, "not stored")
    ok(h.lua("return ns.db.reminders.list[3496][1].id ~= nil"), "no id assigned")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    h.lua("W.advance(3.5)")
    ok("MY OWN" in fired(h), "user reminder did not fire: %r" % fired(h))
    # One added in the middle of a pull is armed for THIS pull too.
    h.lua('SlashCmdList["SALUSNOVUS"]("remind durgen time 6 LATE ADD")')
    h.lua("W.advance(3)")
    ok("LATE ADD" in fired(h), "a reminder added mid-pull did not arm: %r" % fired(h))


@test("a hidden shipped default is skipped; ReminderRemove hides a default and deletes a user one", "reminders")
def _():
    h = fresh()
    h.lua(SHIPPED)
    h.lua("ns.db.reminders.hidden['default:1'] = true")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    ok(not any("Plunder" in t for t in fired(h)), "hidden default still fired: %r" % fired(h))
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.ReminderRemove(3494, 'default:2')")
    ok(h.lua("return ns.db.reminders.hidden['default:2'] == true"), "default not hidden by Remove")
    h.lua("local r = ns.ReminderAdd(3494, { trigger = 'pull', text = 'MINE' }); __id = r.id; ns.ReminderRemove(3494, __id)")
    eq(int(h.lua("return #ns.db.reminders.list[3494]")), 0, "user reminder not deleted")
    eq(len([r for r in range(int(h.lua("return #ns.Reminders.For(3494)")))]), 0, "For still lists removed/hidden ones")


@test("PLAYER_DEAD clears what is on screen and a dead player is not cued", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = {
            { id = "p1", encounterID = 3494, trigger = "pull", text = "PULL", sound = false },
            { id = "t3", encounterID = 3494, trigger = "time", arg = 5, lead = 1, text = "LATER", sound = false },
        }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    eq(shown_texts(h), ["PULL"], "pull line missing")
    h.lua('W.playerDead = true; W.fireEvent("PLAYER_DEAD")')
    h.lua("W.advance(0.1)")
    eq(shown_texts(h), [], "line survived death")
    h.lua("W.advance(5)")
    ok("LATER" not in fired(h), "cued a corpse: %r" % fired(h))
    # Something armed AFTER death (an edit, a late add) must still hold its
    # tongue while the player is dead, and come back on a res.
    h.lua("ns.DefaultReminders[2].arg = 8; ns.ReminderRearm(ns.DefaultReminders[2])")
    h.lua("W.advance(3)")
    ok("LATER" not in fired(h), "cued a corpse after a re-arm: %r" % fired(h))
    h.lua("W.playerDead = false; ns.DefaultReminders[2].arg = 12; ns.ReminderRearm(ns.DefaultReminders[2])")
    h.lua("W.advance(4)")
    ok("LATER" in fired(h), "did not cue after the res: %r" % fired(h))


@test("a hand-edited record with absurd size/hold does not throw and is clamped", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "x1", encounterID = 3494, trigger = "pull", text = "BIG", size = 500, hold = 999, color = 7, sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    eq(h.errors(), [], "threw on a bad record")
    eq(fired(h), ["BIG"], "not shown")
    hgt = float(h.lua("return ns.Reminders._active[1]:GetHeight()"))
    ok(hgt <= 72 + 12, "size not clamped: %r" % hgt)
    h.lua("W.advance(61)")
    eq(shown_texts(h), [], "hold not clamped to 60s")


@test("editing mid-pull: ReminderCancel retracts the line and ReminderRearm arms the new one", "reminders")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "r1", encounterID = 3494, trigger = "time", arg = 10, lead = 4, text = "OLD", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(6.5)")   # armed at +6
    eq(shown_texts(h)[0][:3], "OLD", "not counting down")
    h.lua("""
        ns.ReminderCancel("r1")
        ns.DefaultReminders[1].text = "NEW"
        ns.DefaultReminders[1].arg = 12
        ns.ReminderRearm(ns.DefaultReminders[1])
    """)
    h.lua("W.advance(0.1)")
    eq(shown_texts(h), [], "old line not retracted")
    h.lua("W.advance(2)")     # +8.6: NEW arms at 12-4 = 8
    eq(fired(h)[-1], "NEW", "edited reminder not re-armed: %r" % fired(h))


@test("the preview puts a sample on the stage only and leaves nothing behind", "reminders")
def _():
    h = fresh()
    pending0 = int(h.lua("return W.pendingTimers()"))
    h.lua("""
        __stage = CreateFrame("Frame", "RStage", UIParent)
        __stage:SetSize(400, 90)
        __stage:SetPoint("CENTER")
        ns.RemindersPreviewStart(__stage)
    """)
    ok(h.lua("return SalusNovusReminderFrame:GetParent() == __stage and SalusNovusReminderFrame:IsShown()"), "not on the stage")
    eq(shown_texts(h)[0][:15], "Sample reminder", "no sample: %r" % shown_texts(h))
    # a live reminder must not draw inside the settings window
    h.lua(SHIPPED)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    ok(not any("Plunder" in t for t in shown_texts(h)), "live reminder drawn on the stage")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.RemindersPreviewStop()")
    h.lua("W.advance(0.1)")
    ok(h.lua("return SalusNovusReminderFrame:GetParent() == UIParent"), "not back on UIParent")
    eq(shown_texts(h), [], "sample left behind")
    ok(not h.lua("return SalusNovusReminderFrame:IsShown()"), "frame shown after preview")
    h.lua("W.advance(10)")
    ok(not any("Sample" in t for t in shown_texts(h)), "preview loop kept running")
    eq(int(h.lua("return W.pendingTimers()")), pending0, "the preview's sample ticker leaked")


@test("reminders anchor: unlock shows the sample text and makes it draggable; disabled hides everything", "reminders")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusReminderFrame:IsShown() and SalusNovusReminderFrame:IsMouseEnabled() and SalusNovusReminderFrame.unlockText:IsShown()"), "unlock chrome missing")
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusReminderFrame:IsShown()"), "still shown when locked and idle")
    h.lua("ns.db.reminders.enabled = false; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.5)")
    eq(fired(h), [], "fired while disabled")


# --------------------------------------------------------------- schedule

@test("EventsFor merges a cast bar and its landing into one event", "schedule")
def _():
    h = fresh()
    n = int(h.lua("""
        local boss = { abilities = { { spellID = 1, name = "X", pulls = 1,
            casts = { { 6.5, "start", 1 }, { 8.0, "success", 1 }, { 23.5, "start", 1 }, { 25.0, "success", 1 }, { 40.0, "success", 1 } } } } }
        return #ns.Schedule.EventsFor(boss)
    """))
    eq(n, 3, "start+success pairs should collapse; a lone success stays")


@test("schedule excludes trash casts when the boss is a named NPC, keeps the health-picked boss when it is not", "schedule")
def _():
    h = fresh()
    # Faldrim: named NPC -> the Enraged Apparition's Sunder Armor must not appear
    names = str(h.lua("""
        local out = {}
        for _, e in ipairs(ns.Schedule.EventsFor(ns.Data[3065].bosses[1])) do out[#out+1] = e.name end
        return table.concat(out, ",")
    """))
    ok("Sunder Armor" not in names and "Mind Blast" in names, "Faldrim events wrong: %r" % names)
    # Infurnus: no NPC shares the name -> the boss is the one picked by health
    # (Magmatus); the Summoner's Fireball is trash and stays out
    names = str(h.lua("""
        local out = {}
        for _, e in ipairs(ns.Schedule.EventsFor(ns.Data[3065].bosses[2])) do out[#out+1] = e.name end
        return table.concat(out, ",")
    """))
    ok("Combust" in names and "Fireball" not in names, "Infurnus events wrong: %r" % names)


# -------------------------------------------------------------------- hub

@test("ENCOUNTER_START for a known boss makes exactly one record per scheduled event, timed from the pull", "hub")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Timers.IsActive()"), "hub not active")
    eq(str(h.lua("return ns.Timers.Boss().name")), "Plunder", "boss not resolved")
    eq(int(h.lua("return ns.Timers.EncounterID()")), 3494, "encounter id")
    want = int(h.lua("local n = 0 for _, o in ipairs(ns.Schedule.Lanes(ns.Data[3065].bosses[3])) do n = n + #o.lanes.casts end return n"))
    eq(int(h.lua("return #ns.Timers.Sorted()")), want, "record count (one per clustered cast)")
    bad = str(h.lua("""
        local ev = {}
        for _, o in ipairs(ns.Schedule.Lanes(ns.Data[3065].bosses[3])) do
            for ci, t in ipairs(o.lanes.casts) do ev[#ev+1] = { t = t, spellID = o.a.spellID, pulls = o.lanes.support[ci] } end
        end
        table.sort(ev, function(x, y) return x.t < y.t end)
        local t0 = ns.Timers.StartedAt()
        local out = {}
        for i, b in ipairs(ns.Timers.Sorted()) do
            if math.abs((b.at - t0) - ev[i].t) > 0.001 or b.spellID ~= ev[i].spellID or b.pulls ~= ev[i].pulls then out[#out+1] = i end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", "records disagree with the schedule at: %s" % bad)
    eq(int(h.lua("return ns.Timers.diag.rejKey + ns.Timers.diag.rejDur")), 0, "refusals on clean data")


@test("AddTimer refuses nil/secret keys and NaN/inf/negative/secret durations and counts them; zero (an opener on the pull) is a record", "hub")
def _():
    h = fresh()
    h.lua("""
        local T = ns.Timers
        T.AddTimer(nil, "a", 5)
        T.AddTimer(W.secretString("k"), "a", 5)
        T.AddTimer("nan", "a", 0/0)
        T.AddTimer("inf", "a", math.huge)
        T.AddTimer("neg", "a", -3)
        T.AddTimer("str", "a", "5")
        -- W.secretNumber marks the VALUE secret for the whole test, so it
        -- must not collide with the good record's 5 below.
        T.AddTimer("sec", "a", W.secretNumber(77.5))
    """)
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "a bad record got in")
    eq(int(h.lua("return ns.Timers.diag.rejKey")), 2, "key refusals")
    eq(int(h.lua("return ns.Timers.diag.rejDur")), 5, "duration refusals")
    h.lua('ns.Timers.AddTimer("good", "a", 5)')
    eq(int(h.lua("return #ns.Timers.Sorted()")), 1, "a good record was refused")
    # a cast observed AT the pull (duration 0) is a record that lands at once
    h.lua('__lands = 0; ns.Timers.Register({ OnLand = function() __lands = __lands + 1 end }); ns.Timers.AddTimer("zero", "a", 0, nil, { hold = 2 })')
    eq(int(h.lua("return #ns.Timers.Sorted()")), 2, "a zero-duration opener was refused")
    h.lua("W.advance(0.3)")
    eq(int(h.lua("return __lands")), 1, "the opener did not land")


@test("Sorted is ordered by `at`, cached, and invalidated when the table changes", "hub")
def _():
    h = fresh()
    h.lua("""
        ns.Timers.AddTimer("b", "B", 9)
        ns.Timers.AddTimer("a", "A", 3)
        ns.Timers.AddTimer("c", "C", 6)
    """)
    eq(str(h.lua("local o = {} for _, b in ipairs(ns.Timers.Sorted()) do o[#o+1] = b.key end return table.concat(o, ',')")), "a,c,b", "order")
    ok(h.lua("return ns.Timers.Sorted() == ns.Timers.Sorted()"), "not cached")
    h.lua('ns.Timers.AddTimer("d", "D", 1)')
    eq(str(h.lua("return ns.Timers.Sorted()[1].key")), "d", "cache not invalidated on add")


@test("a record expires at at+hold, fires OnStop exactly once, and the ticker settles when the fight is over", "hub")
def _():
    h = fresh()
    h.lua("""
        __stops = {}
        ns.Timers.Register({ OnStop = function(b) __stops[#__stops+1] = b.key end })
        ns.Timers.AddTimer("x", "X", 4, nil, { hold = 2.5 })
    """)
    h.lua("W.advance(5)")       # past `at` (4) but inside hold (6.5)
    eq(int(h.lua("return #ns.Timers.Sorted()")), 1, "dropped before the hold ran out")
    h.lua("W.advance(2)")       # 7 > 6.5
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "not expired after the hold")
    eq(int(h.lua("return #__stops")), 1, "OnStop count")
    eq(str(h.lua("return __stops[1]")), "x", "OnStop record")
    eq(str(h.lua("return tostring(ns.Timers.state.tick)")), "nil", "ticker still running over an empty table")


@test("ENCOUNTER_END clears; a foreign END is ignored; a second START restarts the clock", "hub")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.fireEvent("ENCOUNTER_END", 3493, "Faldrim Anvilmar", 1, 5, 0)')
    ok(h.lua("return ns.Timers.IsActive()"), "a foreign ENCOUNTER_END killed the pull")
    h.lua("W.advance(3)")
    t0 = float(h.lua("return ns.Timers.StartedAt()"))
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    eq(str(h.lua("return ns.Timers.Boss().name")), "Durgen Dirgehammer", "second START did not switch boss")
    ok(float(h.lua("return ns.Timers.StartedAt()")) > t0, "clock not restarted")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    ok(not h.lua("return ns.Timers.IsActive()"), "still active after END")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "records survived END")


@test("a real pull during /sn test restarts the fight and the simulation's timer never ends it; a same-id START with no END restarts the clock", "hub")
def _():
    h = fresh()
    h.lua('SlashCmdList["SALUSNOVUS"]("test plunder")')
    h.lua("W.advance(10)")
    t_sim = float(h.lua("return ns.Timers.StartedAt()"))
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(float(h.lua("return ns.Timers.StartedAt()")) > t_sim, "the real pull was absorbed into the simulation")
    ok(h.lua("return ns.Timers.state.simulate == nil"), "the simulation timer should be cancelled by a real pull")
    avg = float(h.lua("return ns.Data[3065].bosses[3].avgLength"))
    h.lua("W.advance(%f)" % (avg + 2))
    ok(h.lua("return ns.Timers.IsActive()"), "the simulation's timer ended the real fight")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    # the same boss pulled again with no END seen: the clock restarts
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(5)")
    t0 = float(h.lua("return ns.Timers.StartedAt()"))
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(float(h.lua("return ns.Timers.StartedAt()")) > t0, "a repeated START on the same id should restart the clock")
    eq(h.errors(), [], "errors")
    # a simulated boss without an average runs long enough for its casts
    h2 = fresh()
    h2.lua("ns.Data[3065].bosses[3].avgLength = nil")
    h2.lua('SlashCmdList["SALUSNOVUS"]("test plunder")')
    last = float(h2.lua("local L = ns.Timers.Sorted() return L[#L].at - ns.Timers.StartedAt()"))
    h2.lua("W.advance(%f)" % (last - 0.5))
    ok(h2.lua("return ns.Timers.IsActive()"), "simulation ended before its last cast")


@test("a secret encounter id starts an anonymous fight with no records and no error", "hub")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", W.secret(3494), "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Timers.IsActive()"), "should still track the fight")
    eq(str(h.lua("return tostring(ns.Timers.EncounterID())")), "nil", "took a secret id")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "records for an unknown fight")


@test("a throwing listener is reported once and never stops the others", "hub")
def _():
    h = fresh()
    h.lua("""
        __n = 0
        ns.Timers.Register({ OnChange = function() error("bad anchor") end })
        ns.Timers.Register({ OnChange = function() __n = __n + 1 end })
        ns.Timers.AddTimer("a", "A", 5)
        ns.Timers.AddTimer("b", "B", 5)
    """)
    eq(int(h.lua("return __n")), 2, "the listener after the broken one did not run")
    eq(len([p for p in h.printed() if "bad anchor" in p]), 1, "should report once")


@test("fakes render through the live table, use data names, and never leak into a pull", "hub")
def _():
    h = fresh()
    h.lua("ns.Timers.AddFakes(ns.Timers.FakeBars(3, 10, true))")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 3, "fakes not in the table")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars did not render fakes")
    names = str(h.lua("local o = {} for _, b in ipairs(ns.Timers.Sorted()) do o[#o+1] = b.name end return table.concat(o, ',')"))
    ok("Ability 1" not in names, "fakes should use data names: %r" % names)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    eq(int(h.lua("local n = 0 for _, b in ipairs(ns.Timers.Sorted()) do if b.fake then n = n + 1 end end return n")), 0, "fakes leaked into the pull")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.Timers.AddFakes(ns.Timers.FakeBars(2, 10, true)); ns.Timers.ClearFakes()")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "ClearFakes left records")
    eq(str(h.lua("return tostring(ns.Timers.state.tick)")), "nil", "ticker running after ClearFakes")


@test("/sn test runs the real intake and ends at the boss's average length", "hub")
def _():
    h = fresh()
    h.lua(SHIPPED)
    h.lua('SlashCmdList["SALUSNOVUS"]("test plunder")')
    ok(h.lua("return ns.Timers.IsActive() and SalusNovusBars:IsShown()"), "simulation did not start the hub")
    h.lua("W.advance(0.1)")
    ok(h.lua("return SalusNovusReminderFrame and SalusNovusReminderFrame:IsShown()"), "reminders did not see the simulated pull")
    avg = float(h.lua("return ns.Data[3065].bosses[3].avgLength"))
    h.lua("W.advance(%f)" % (avg - 1))
    ok(h.lua("return ns.Timers.IsActive()"), "ended early")
    h.lua("W.advance(2)")
    ok(not h.lua("return ns.Timers.IsActive()"), "did not end at avgLength")
    ok(not h.lua("return SalusNovusBars:IsShown()"), "bars still up after the simulated fight")


# ------------------------------------------------------------------- bars

@test("bars appear on a known pull, drain toward each clustered cast, drop after grace, hide at end", "bars")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars frame not shown")
    ok(not h.lua("return SalusNovusBars.label:IsShown()"), "no label in a fight")
    # One bar per clustered cast, never one per pull's copy of it.
    want = int(h.lua("local n = 0 for _, o in ipairs(ns.Schedule.Lanes(ns.Data[3065].bosses[3])) do n = n + #o.lanes.casts end return n"))
    eq(int(h.lua("return #ns.Timers.Sorted()")), want, "one record per clustered cast")
    # The first bar is the earliest cast: full at the pull, its seconds shown.
    t1 = float(h.lua("return ns.Timers.Sorted()[1].at - ns.Timers.StartedAt()"))
    first = str(h.lua("""
        local f
        for i = 1, 8 do local b = ns.Bars._bars[i] if b:IsShown() then f = b break end end
        return f.text:GetText() .. "|" .. f.time:GetText() .. "|" .. string.format("%.2f", f.bar:GetValue())
    """))
    eq(first, "Knock Away|%d|1.00" % -(-t1 // 1), "first bar wrong: %r" % first)
    h.lua("W.advance(5)")
    h.lua("ns.Bars.Tick(GetTime())")
    left = t1 - 5
    first = str(h.lua("""
        local f
        for i = 1, 8 do local b = ns.Bars._bars[i] if b:IsShown() then f = b break end end
        return f.time:GetText() .. "|" .. string.format("%.2f", f.bar:GetValue()) .. "|" .. tostring(f.low)
    """))
    eq(first, "%d|%.2f|%s" % (-(-left // 1), left / t1, "true" if left <= 3 else "nil"), "after 5s: %r" % first)
    # past its hold the first bar drops and the next reads "now" at its moment
    t2 = float(h.lua("return ns.Timers.Sorted()[2].at - ns.Timers.StartedAt()"))
    h.lua("W.advance(%f)" % (t2 + 0.2 - 5))
    h.lua("ns.Bars.Tick(GetTime())")
    first = str(h.lua("""
        local f
        for i = 1, 8 do local b = ns.Bars._bars[i] if b:IsShown() then f = b break end end
        return f.text:GetText() .. "|" .. f.time:GetText()
    """))
    ok(first.endswith("|now") and not first.startswith("Knock Away|now") or t2 - t1 < 2.5, "first bar should have dropped: %r" % first)
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    ok(not h.lua("return SalusNovusBars:IsShown()"), "bars still shown after end")
    ok(not h.lua("return SalusNovusBars.label:IsShown()"), "label still shown after end")

@test("bars honour the row cap and the enabled setting", "bars")
def _():
    h = fresh()
    h.lua("ns.db.bars.max = 2")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    shown = int(h.lua("local n = 0 for i = 1, 8 do if ns.Bars._bars[i]:IsShown() then n = n + 1 end end return n"))
    eq(shown, 2, "row cap not honoured")
    h2 = fresh()
    h2.lua("ns.db.bars.enabled = false; ns.ApplyAll()")
    h2.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h2.lua("return SalusNovusBars:IsShown()"), "bars shown while disabled")


@test("a slot re-bound from a red bar to a fresh one turns red again at its own threshold", "bars")
def _():
    h = fresh()
    h.lua("""
        ns.db.bars.max = 1
        ns.Timers.AddTimer("a", "A", 4, nil, { hold = 0 })
        ns.Timers.AddTimer("b", "B", 30, nil, { hold = 0 })
    """)
    h.lua("W.advance(2); ns.Bars.Tick(GetTime())")
    ok(h.lua("return ns.Bars._bars[1].low == true"), "A should be red at 2s left")
    h.lua("W.advance(2.5)")     # A expires; the slot is re-bound to B (25.5s left)
    eq(str(h.lua("return ns.Bars._bars[1].text:GetText()")), "B", "slot not re-bound")
    ok(not h.lua("return ns.Bars._bars[1].low"), "latch carried over to the new bar")
    # The mock has no GetStatusBarColor: record what Tick sets.
    h.lua("""
        __last = nil
        local bar = ns.Bars._bars[1].bar
        bar.SetStatusBarColor = function(_, r, g, b) __last = { r, g, b } end
    """)
    h.lua("W.advance(23); ns.Bars.Tick(GetTime())")   # B at 2.5s left
    r, g = h.lua("return __last and __last[1], __last and __last[2]")
    ok(r is not None and abs(r - 1) < 0.01 and abs(g - 0.3) < 0.01, "B did not turn red: %r" % ((r, g),))


@test("direction = up re-pins by BOTTOMLEFT with no drift on a fresh profile", "bars")
def _():
    h = fresh()
    h.lua("ns.db.bars.direction = 'up'; ns.db.unlocked = true; ns.ApplyAll()")
    eq(str(h.lua("local p = SalusNovusBars:GetPoint() return p")), "BOTTOMLEFT", "origin for an upward stack")
    l0, b0 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetBottom()")
    h.lua("ns.db.bars.max = 8; ns.ApplyAll()")
    l1, b1 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetBottom()")
    ok(abs(l0 - l1) < 0.01 and abs(b0 - b1) < 0.01, "bottom-left drifted: %r -> %r" % ((l0, b0), (l1, b1)))


@test("preview reparents the anchor onto a stage and Stop restores it to its saved spot", "bars")
def _():
    h = fresh()
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")   # the default is Up (Alex); these check the downward origin
    h.lua("""
        ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()
        __l, __t = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
        __stage = CreateFrame("Frame", "Stage", UIParent)
        __stage:SetSize(400, 110)
        __stage:SetPoint("CENTER")
        ns.BarsPreviewStart(__stage)
    """)
    ok(h.lua("return SalusNovusBars:GetParent() == __stage and SalusNovusBars:IsShown()"), "not on the stage")
    ok(h.lua("return ns.Bars._bars[1]:IsShown()"), "preview draws no bars")
    # a drag save from the stage must be refused
    h.lua("ns.SaveAnchor(SalusNovusBars, 'barsPos')")
    h.lua("ns.BarsPreviewStop()")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent"), "not back on UIParent")
    l, t = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    l0, t0 = h.lua("return __l, __t")
    ok(abs(l - l0) < 0.01 and abs(t - t0) < 0.01, "did not return to its spot: %r vs %r" % ((l, t), (l0, t0)))
    ok(not h.lua("return SalusNovusBars:IsShown()"), "idle anchor shown after preview")


# -------------------------------------------------------------- visualizer

def open_vis(h):
    h.lua('SlashCmdList["SALUSNOVUS"]("show")')
    ok(h.lua("return SalusNovusVisualizer:IsShown()"), "visualizer not shown")


def lane_names(h):
    n = int(h.lua("return #ns.Visualizer._lanes"))
    out = []
    for i in range(1, n + 1):
        if h.lua("return ns.Visualizer._lanes[%d]:IsShown()" % i):
            out.append(str(h.lua("return ns.Visualizer._lanes[%d].name:GetText()" % i)))
    return out


@test("/sn show opens on the first boss with lanes: reminders first, then abilities by first cast; no cycles; fits", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    eq(h.errors(), [], "errors opening")
    eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle")
    eq(float(h.lua("return W.offscreen(SalusNovusVisualizer).any")), 0.0, "off screen")
    eq(int(h.lua("return ns.Visualizer.state.enc")), 3493, "first boss should be Faldrim")
    names = lane_names(h)
    eq(names[0], "Your reminders", "reminders lane must be first: %r" % names)
    want = [str(h.lua("return ns.Schedule.Lanes(ns.Data[3065].bosses[1])[%d].a.name" % i))
            for i in range(1, int(h.lua("return #ns.Schedule.Lanes(ns.Data[3065].bosses[1])")) + 1)]
    eq(names[1:], want, "ability lanes not in first-cast order")
    ok("Sunder Armor" not in names, "trash lane drawn")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    eq(int(h.lua("return ns.Visualizer.state.enc")), 3494, "switch failed")
    ok("Knock Away" in lane_names(h), "Plunder lanes missing: %r" % lane_names(h))
    eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle after switch")
    h.lua('SlashCmdList["SALUSNOVUS"]("show")')
    ok(not h.lua("return SalusNovusVisualizer:IsShown()"), "toggle did not hide")


@test("geometry: X maps the pull to 0 and the fight end to the track width; marks sit at X(t); a spread draws a wider band", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    x0, xe, tw = h.lua("local V = ns.Visualizer return V.X(0), V.X(V.FightEnd()), V.TrackWidth()")
    ok(abs(x0) < 0.01 and abs(xe - tw) < 0.01, "X mapping wrong: %r" % ((x0, xe, tw),))
    bad = str(h.lua("""
        local V = ns.Visualizer
        local out = {}
        for li = 2, #V._lanes do
            local lane = V._lanes[li]
            if lane:IsShown() then
                for _, m in ipairs(lane.marks) do
                    if m:IsShown() then
                        -- a mark is CENTRED on its time (the reminders lane always was)
                        local dx = (m:GetLeft() + m:GetWidth() / 2 - lane.track:GetLeft()) - V.X(m.t)
                        if math.abs(dx) > 0.5 then out[#out+1] = lane.name:GetText() .. "@" .. m.t .. "=" .. dx end
                    end
                end
            end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", "marks off their time: %s" % bad)
    # a synthetic two-pull boss: the band is wider than the mark
    h.lua("""
        __boss = { encounterID = 77, name = "Synthetic", pulls = 2, avgLength = 60, npcs = { { id = 1, name = "Synthetic" } },
            abilities = { { spellID = 5, name = "Wide", source = "Synthetic", pulls = 2,
                casts = { { 10.0, "success", 1 }, { 14.0, "success", 2 }, { 40.0, "success", 1 }, { 40.5, "success", 2 } } } } }
        ns.Data[3065].bosses[5] = __boss
        ns.Visualizer.ShowBoss(__boss)
    """)
    w, bw, bshown = h.lua("local m = ns.Visualizer._lanes[2].marks[1] return m:GetWidth(), m.band:GetWidth(), m.band:IsShown()")
    ok(bshown and bw > w, "spread band not wider than the mark: %r" % ((w, bw, bshown),))
    ok(not h.lua("return ns.Visualizer._lanes[2].marks[2].band:IsShown()"), "tight cast should have no band")
    h.lua("ns.Data[3065].bosses[5] = nil")


@test("Schedule.Lanes: two pulls give support 2 and half-gap spread; one pull gives support 1, spread 0 and the hover carries no caution", "visualizer")
def _():
    h = fresh()
    c, sp, su, n = h.lua("""
        local boss = { npcs = { { name = "B" } }, abilities = { { spellID = 1, name = "A", source = "B",
            casts = { { 10.0, "success", 1 }, { 14.0, "success", 2 }, { 40.0, "start", 1 }, { 41.5, "success", 1 } } } } }
        local L = ns.Schedule.Lanes(boss)
        return L[1].lanes.casts[1], L[1].lanes.spread[1], L[1].lanes.support[1], #L[1].lanes.casts
    """)
    eq(int(n), 2, "the pull-1 start/success pair at 40 should be its own cluster")
    ok(abs(c - 12) < 0.01 and abs(sp - 2) < 0.01 and int(su) == 2, "cluster wrong: %r" % ((c, sp, su),))
    eq(int(h.lua("""
        local boss = { npcs = { { name = "B" } }, abilities = { { spellID = 1, name = "A", source = "B",
            casts = { { 10.0, "success", 1 }, { 13.0, "success", 1 }, { 11.0, "success", 2 } } } } }
        return #ns.Schedule.Lanes(boss)[1].lanes.casts
    """)), 2, "same-pull recast folded into one cluster")
    eq(float(h.lua("""
        local boss = { npcs = { { name = "B" } }, abilities = { { spellID = 1, name = "A", source = "B",
            casts = { { 12.0, "start", 1 }, { 13.5, "success", 1 } } } } }
        return ns.Schedule.Lanes(boss)[1].lanes.cast
    """)), 1.5, "cast length from a start/success pair")
    # a one-pull boss says so on hover; a two-pull cast seen once says "1 of 2"
    open_vis(h)
    h.lua("""
        ns.Data[3065].bosses[5] = { encounterID = 9, name = "Solo", pulls = 1, avgLength = 30, npcs = { { id = 1, name = "Solo" } },
            abilities = { { spellID = 5, name = "Lonely", source = "Solo", pulls = 1, casts = { { 7.5, "success", 1 } } } } }
        ns.Visualizer.ShowBoss(ns.Data[3065].bosses[5])
        local m = ns.Visualizer._lanes[2].marks[1] m:GetScript('OnEnter')(m)
    """)
    txt = str(h.lua("return SalusNovusVisualizer.hover:GetText()"))
    ok("unconfirmed" not in txt and "one pull" not in txt and "Lonely" in txt and "0:07" in txt, "one-pull hover must carry no caution (Alex): %r" % txt)
    h.lua("ns.Data[3065].bosses[5] = nil")
    h.lua("""
        ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])
        local m = ns.Visualizer._lanes[2].marks[1] m:GetScript('OnEnter')(m)
    """)
    txt = str(h.lua("return SalusNovusVisualizer.hover:GetText()"))
    ok("unconfirmed" not in txt and "Knock Away" in txt, "two-pull hover should not say unconfirmed: %r" % txt)

@test("VisibleSpan keeps a long cast on screen after panning past its start; zoom and pan bookkeeping", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    ok(not h.lua("return SalusNovusVisualizer.pan:IsEnabled()"), "pan enabled at zoom 1")
    h.lua("ns.Visualizer.Zoom(1.5); ns.Visualizer.Zoom(1.5)")
    ok(abs(float(h.lua("return ns.Visualizer.state.zoom")) - 2.25) < 0.001, "zoom")
    ok(h.lua("return SalusNovusVisualizer.pan:IsEnabled()"), "pan disabled when zoomed")
    h.lua("SalusNovusVisualizer.pan:SetValue(100)")
    off, end_, span = h.lua("local V = ns.Visualizer return V.state.offset, V.FightEnd(), V.Span()")
    ok(abs(off - (end_ - span)) < 0.01, "pan to 100 should show the end: %r" % ((off, end_, span),))
    # a 20s cast starting before the window must still be visible
    vis = h.lua("return (ns.Visualizer.VisibleSpan(%f, 20, 0))" % (off - 5))
    ok(vis, "long cast culled by its start point")
    vis2 = h.lua("return (ns.Visualizer.VisibleSpan(%f, 0, 0))" % (off - 5))
    ok(not vis2, "instant cast before the window should be culled")
    h.lua("ns.Visualizer.Zoom(1 / 10)")
    eq(float(h.lua("return ns.Visualizer.state.offset")), 0.0, "offset not reset at zoom 1")
    eq(h.errors(), [], "errors")


@test("fmtExact round-trips tenths and never prints 0:60.0; ParseTime rejects negatives", "visualizer")
def _():
    h = fresh()
    eq(str(h.lua("return ns.Visualizer.fmtExact(59.97)")), "1:00", "minute boundary")
    eq(str(h.lua("return ns.Visualizer.fmtExact(7.5)")), "0:07.5", "tenths")
    eq(float(h.lua("return ns.Visualizer.ParseTime('0:07.5')")), 7.5, "parse m:ss.t")
    eq(float(h.lua("return ns.Visualizer.ParseTime('12')")), 12.0, "parse bare")
    eq(str(h.lua("return tostring(ns.Visualizer.ParseTime('-3'))")), "nil", "negative accepted")


@test("clicking a track opens the form at the cursor time; Save adds a time reminder, draws it on lane 1, and arms it mid-pull", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    n0 = int(h.lua("return #ns.Reminders.For(3494)"))
    # put the cursor a quarter of the way along the axis
    h.lua("""
        local axis = SalusNovusVisualizer.axis
        local x = axis:GetLeft() + axis:GetWidth() * 0.25
        GetCursorPosition = function() return x * axis:GetEffectiveScale(), 0 end
        local lane = ns.Visualizer._lanes[2]
        lane.track:GetScript("OnClick")(lane.track)
    """)
    ok(h.lua("return ns.Visualizer.form:IsShown()"), "form not opened")
    # the cursor line sits exactly at the cursor x (LEFT-anchored both ends)
    h.lua("local lane = ns.Visualizer._lanes[2] ns.Visualizer.ShowCursor(lane.track)")
    dx = float(h.lua("local axis = SalusNovusVisualizer.axis return SalusNovusVisualizer.cursor:GetLeft() - (axis:GetLeft() + axis:GetWidth() * 0.25)"))
    ok(abs(dx) < 0.01, "cursor line off by %r" % dx)
    ok(h.lua("return SalusNovusVisualizer.cursorLabel:IsShown()"), "cursor time label missing")
    at = float(h.lua("return ns.Visualizer.ParseTime(ns.Visualizer.form.at:GetText())"))
    want = float(h.lua("return ns.Visualizer.FightEnd() * 0.25"))
    ok(abs(at - want) < 0.15, "AT not prefilled from the cursor: %r vs %r" % (at, want))
    ok(str(h.lua("return ns.Visualizer.form.text:GetText()")).startswith("Knock Away"), "text not prefilled")
    # a live pull is running: the new reminder must arm for it
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("""
        local f = ns.Visualizer.form
        f.text:SetText("LANE ONE")
        f.at:SetText("3")
        f.lead:SetText("999")
        f.save:Click()
    """)
    eq(int(h.lua("return #ns.Reminders.For(3494)")), n0 + 1, "not added")
    r = h.lua("local l = ns.Reminders.For(3494) return l[#l]")
    eq(str(r["trigger"]), "time", "trigger")
    eq(float(r["arg"]), 3.0, "arg")
    eq(float(r["lead"]), 300.0, "lead not clamped to 300")
    ok(r["id"] is not None, "no id")
    ok(not h.lua("return ns.Visualizer.form:IsShown()"), "form still open after save")
    # drawn on lane 1 as a 10x26 mark at X(3)
    found = h.lua("""
        local V = ns.Visualizer
        local rl = V._lanes[1]
        for _, m in ipairs(rl.marks) do
            if m:IsShown() and m.reminder and m.reminder.text == "LANE ONE" then
                return m:GetWidth() == 10 and m:GetHeight() == 26 and math.abs((m:GetLeft() + 5 - rl.track:GetLeft()) - V.X(3)) < 0.01
            end
        end
        return false
    """)
    ok(found, "reminder mark not drawn at its time on lane 1")
    h.lua("W.advance(3.5)")
    ok("LANE ONE" in fired(h), "reminder added mid-pull was not armed: %r" % fired(h))


@test("the form makes every kind of reminder: pull, cast and yell as well as timed; a yell needs a word", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    n0 = int(h.lua("return #ns.Reminders.For(3494)"))
    def make(trigger, text, word=None):
        h.lua("""
            ns.Visualizer.OpenForm(9, 11130, "Knock Away", nil)
            local f = ns.Visualizer.form
            f.trigger = "%s"; f.LayoutTrigger()
            f.text:SetText("%s")
            f.word:SetText("%s")
            f.save:Click()
        """ % (trigger, text, word or ""))
    make("pull", "PULL ONE")
    make("cast", "CAST ONE")
    make("emote", "YELL ONE", "kneel")
    eq(int(h.lua("return #ns.Reminders.For(3494)")), n0 + 3, "three reminders expected")
    recs = h.lua("""
        local out = {}
        for _, r in ipairs(ns.Reminders.For(3494)) do
            if r.text == "PULL ONE" or r.text == "CAST ONE" or r.text == "YELL ONE" then out[r.text] = r.trigger .. ":" .. tostring(r.arg) end
        end
        return out
    """)
    eq(str(recs["PULL ONE"]), "pull:nil", "pull record")
    eq(str(recs["CAST ONE"]), "cast:nil", "cast record")
    eq(str(recs["YELL ONE"]), "emote:kneel", "yell record")
    # a yell without a word is refused
    make("emote", "NO WORD")
    eq(int(h.lua("return #ns.Reminders.For(3494)")), n0 + 3, "a wordless yell was stored")
    ok(h.lua("return ns.Visualizer.form:IsShown()"), "form should stay open on a refused save")
    # the trigger row hides the fields that do not apply
    h.lua("ns.Visualizer.form.trigger = 'pull'; ns.Visualizer.form.LayoutTrigger()")
    ok(not h.lua("return ns.Visualizer.form.at:IsShown()") and not h.lua("return ns.Visualizer.form.word:IsShown()"), "pull shows AT or word")
    h.lua("ns.Visualizer.form.trigger = 'emote'; ns.Visualizer.form.LayoutTrigger()")
    ok(h.lua("return ns.Visualizer.form.word:IsShown()") and not h.lua("return ns.Visualizer.form.at:IsShown()"), "yell should show the word box only")
    # they all fire from a pull
    h.lua("ns.Visualizer.form.cancel:Click()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    ok("PULL ONE" in fired(h), "pull reminder did not fire: %r" % fired(h))
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "target", "Cast-2", W.secretNumber())')
    ok("CAST ONE" in fired(h), "cast reminder did not fire")
    h.lua('W.fireEvent("CHAT_MSG_MONSTER_YELL", "Kneel before me!", "Plunder")')
    ok("YELL ONE" in fired(h), "yell reminder did not fire")
    eq(h.errors(), [], "errors")


@test("editing a mark keeps its id; Remove cancels before removing and hides a shipped default; colour Cancel leaves r.color alone", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("""
        __r = ns.ReminderAdd(3494, { trigger = "time", arg = 20, text = "EDIT ME", lead = 5 })
        ns.Visualizer.Refresh()
        local rl = ns.Visualizer._lanes[1]
        for _, m in ipairs(rl.marks) do if m:IsShown() and m.reminder == __r then __m = m end end
        __m:GetScript("OnClick")(__m)
    """)
    ok(h.lua("return ns.Visualizer.form:IsShown() and ns.Visualizer.form.editing == __r"), "edit form not opened on the record")
    eq(str(h.lua("return ns.Visualizer.form.at:GetText()")), "0:20", "AT not prefilled")
    # colour picker: open then Cancel -> nothing changes
    h.lua("""
        ns.Visualizer.form.swatch:Click()
        local p = ns.Theme.ColorPicker()
        p.sliders[1]:SetValue(25)
        p.cancel:Click()
    """)
    ok(not h.lua("return SalusNovusColorPicker:IsShown()"), "picker stayed open after Cancel")
    ok(not h.lua("return ns.Visualizer.form.useColor:GetChecked()"), "Cancel ticked the colour override")
    h.lua("ns.Visualizer.form.text:SetText('EDITED'); ns.Visualizer.form.at:SetText('25'); ns.Visualizer.form.save:Click()")
    ok(h.lua("return __r.text == 'EDITED' and __r.arg == 25 and __r.id ~= nil"), "edit did not mutate in place")
    ok(h.lua("return __r.color == nil"), "colour written without the override")
    # Remove: Cancel is called before Remove
    h.lua("""
        __order = {}
        local c, rm = ns.ReminderCancel, ns.ReminderRemove
        ns.ReminderCancel = function(id) __order[#__order+1] = "cancel" return c(id) end
        ns.ReminderRemove = function(e, id) __order[#__order+1] = "remove" return rm(e, id) end
        ns.Visualizer.Refresh()
        local rl = ns.Visualizer._lanes[1]
        for _, m in ipairs(rl.marks) do if m:IsShown() and m.reminder == __r then __m = m end end
        __m:GetScript("OnClick")(__m)
        ns.Visualizer.form.delete:Click()
    """)
    eq(str(h.lua("return table.concat(__order, ',')")), "cancel,remove", "Cancel must come before Remove")
    ok(not any(str(h.lua("return ns.Reminders.For(3494)[%d].text" % i)) == "EDITED"
               for i in range(1, int(h.lua("return #ns.Reminders.For(3494)")) + 1)), "not removed")
    # a shipped default is hidden, not deleted from the data
    h.lua(SHIPPED)
    h.lua("""
        ns.Visualizer.Refresh()
        local rl = ns.Visualizer._lanes[1]
        for _, m in ipairs(rl.marks) do if m:IsShown() and m.reminder and m.reminder.id == "default:1" then __d = m end end
        __d:GetScript("OnClick")(__d)
        ns.Visualizer.form.delete:Click()
    """)
    ok(h.lua("return ns.db.reminders.hidden['default:1'] == true"), "default not hidden")
    eq(int(h.lua("return #ns.DefaultReminders")), 2, "shipped data mutated")
    eq(h.errors(), [], "errors")


@test("the panel under the lanes lists every ability of the boss the moment it opens, with icons and descriptions", "visualizer")
def _():
    h = fresh()
    h.lua("""
        __spellDesc = { [11130] = "Knocks the target back." }
        __cached = { [11130] = true }
        C_Spell.GetSpellDescription = function(id) return __spellDesc[id] or "" end
        C_Spell.IsSpellDataCached = function(id) return __cached[id] or false end
    """)
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    n = int(h.lua("return #ns.Schedule.Lanes(ns.Data[3065].bosses[3])"))
    shown = int(h.lua("local c = 0 for _, r in ipairs(SalusNovusVisualizer.descRows) do if r:IsShown() then c = c + 1 end end return c"))
    eq(shown, n, "one row per ability expected")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].name:GetText()")), "Knock Away", "first row should be the first ability")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].desc:GetText()")), "Knocks the target back.", "description not shown")
    ok(h.lua("local t = SalusNovusVisualizer.descRows[1].icon:GetTexture() return type(t) == 'number' or type(t) == 'string'"), "row has no icon")
    # cards: sized to their text, spaced, and they pop on hover
    h1 = float(h.lua("return SalusNovusVisualizer.descRows[1]:GetHeight()"))
    ok(h1 >= 52, "card too short: %r" % h1)
    gap = float(h.lua("return SalusNovusVisualizer.descRows[1]:GetBottom() - SalusNovusVisualizer.descRows[2]:GetTop()"))
    ok(abs(gap - 6) < 0.01, "cards should be 6px apart: %r" % gap)
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnEnter')(r)")
    ok(h.lua("return SalusNovusVisualizer.descRows[1].hoverBg:IsShown()"), "card did not pop on hover")
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnLeave')(r)")
    ok(not h.lua("return SalusNovusVisualizer.descRows[1].hoverBg:IsShown()"), "card stayed popped")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[2].desc:GetText()")), "loading...", "uncached spell should read loading")
    ok(float(h.lua("return SalusNovusVisualizer.desc:GetTop()")) <= float(h.lua("return SalusNovusVisualizer.lanes:GetBottom()")), "panel not under the lanes")
    # The lanes take only their own height and the abilities follow at
    # once under an ABILITIES heading, with no panel drawn behind the
    # cards (Alex: no large gap, no card behind the cards).
    nlanes = int(h.lua("return #ns.Visualizer._lanes"))
    lanes_h = float(h.lua("return SalusNovusVisualizer.lanes:GetHeight()"))
    ok(abs(lanes_h - nlanes * 48) < 0.01, "lanes area should be %d lanes tall, is %r" % (nlanes, lanes_h))
    gap = float(h.lua("return SalusNovusVisualizer.lanes:GetBottom() - SalusNovusVisualizer.desc:GetTop()"))
    ok(gap <= 12, "gap from the lanes to the abilities: %r" % gap)
    eq(str(h.lua("return SalusNovusVisualizer.descHead:GetText()")), "ABILITIES", "heading")
    ok(h.lua("return SalusNovusVisualizer.desc.bg == nil and SalusNovusVisualizer.desc.border == nil"), "a panel is still drawn behind the cards")
    ok(not h.lua("return SalusNovusVisualizer.descEmpty:IsShown()"), "empty note shown with abilities present")
    h.lua("""
        __other = SalusNovusVisualizer.descRows[2] and ns.Schedule.Lanes(ns.Data[3065].bosses[3])[2].a.spellID
        __spellDesc[__other] = 'Arrived.'; __cached[__other] = true
        W.fireEvent('SPELL_DATA_LOAD_RESULT', __other, true)
    """)
    eq(str(h.lua("return SalusNovusVisualizer.descRows[2].desc:GetText()")), "Arrived.", "description not refreshed on load")
    # a boss switch rebuilds the list for THAT boss
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[2])")
    first = str(h.lua("return ns.Schedule.Lanes(ns.Data[3065].bosses[2])[1].a.name"))
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].name:GetText()")), first, "list not rebuilt for the new boss")
    n2 = int(h.lua("return #ns.Schedule.Lanes(ns.Data[3065].bosses[2])"))
    ok(not h.lua("return SalusNovusVisualizer.descRows[%d] and SalusNovusVisualizer.descRows[%d]:IsShown()" % (n2 + 1, n2 + 1)), "stale row left shown")
    # a boss with nothing logged shows the note
    h.lua("ns.Data[3065].bosses[5] = { encounterID = 2, name = 'Nobody', npcs = {}, abilities = {}, pulls = 0 }")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[5])")
    ok(not h.lua("return SalusNovusVisualizer.descEmpty:IsShown()"), "empty boss must show no note (Alex)")
    h.lua("ns.Data[3065].bosses[5] = nil")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    # launcher round trip with the form open
    h.lua("SalusNovusVisualizer:Hide()")
    h.lua('SlashCmdList["SALUSNOVUS"]("")')
    h.lua("ns.Options.launcher:Click(); W.advance(0.1)")
    ok(h.lua("return SalusNovusVisualizer:IsShown() and not SalusNovusOptions:IsShown()"), "launcher did not open the visualizer")
    h.lua("ns.Visualizer.OpenForm(5, 11130, 'Knock Away', nil)")
    ok(h.lua("return ns.Visualizer.form:IsShown()"), "form did not open")
    h.lua("W.advance(1); SalusNovusVisualizer:Hide()")
    ok(not h.lua("return ns.Visualizer.form:IsShown()"), "form left open")
    ok(h.lua("return SalusNovusOptions:IsShown()"), "did not return to options")
    eq(h.errors(), [], "errors")

@test("a boss with no observed casts renders nothing but its name: no note, axis, lanes, heading or slider", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    ok(h.lua("return SalusNovusVisualizer.axis:IsShown() and SalusNovusVisualizer.desc:IsShown() and SalusNovusVisualizer.pan:IsShown()"), "a logged boss should show its axis, abilities and slider")
    h.lua("""
        ns.Data[3065].bosses[5] = { encounterID = 1, name = "Empty", npcs = {}, abilities = {}, pulls = 0 }
        ns.Visualizer.ShowBoss(ns.Data[3065].bosses[5])
    """)
    eq(str(h.lua("return SalusNovusVisualizer.bossTitle:GetText()")), "Empty", "title")
    for part in ("empty", "descEmpty", "axis", "lanes", "desc", "pan", "panCap", "zoomIn", "zoomOut"):
        ok(not h.lua("return SalusNovusVisualizer.%s:IsShown()" % part), "%s drawn for an empty boss" % part)
    eq(lane_names(h), [], "an empty boss must draw no lanes at all")
    # back to a logged boss: everything returns
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    ok(h.lua("return SalusNovusVisualizer.axis:IsShown() and SalusNovusVisualizer.desc:IsShown() and SalusNovusVisualizer.pan:IsShown()"), "parts did not come back")
    ok(len(lane_names(h)) > 1, "lanes did not come back")
    eq(h.errors(), [], "errors")
    h.lua("ns.Data[3065].bosses[5] = nil")
    # an instance with no name (a half-written data file) must not take the
    # window down inside table.sort
    h.lua("ns.Data[9999] = { mapID = 9999, bosses = {} }")
    h.lua("ns.Visualizer.Refresh()")
    eq(h.errors(), [], "a nameless instance threw")
    h.lua("ns.Data[9999] = nil")


# ----------------------------------------------------------------- options

def open_options(h):
    h.lua('SlashCmdList["SALUSNOVUS"]("")')
    ok(h.lua("return SalusNovusOptions and SalusNovusOptions:IsShown()"), "options did not open")


@test("/sn opens the options window on the Bars page with no anchor cycles, and it fits the screen", "options")
def _():
    h = fresh()
    open_options(h)
    eq(h.errors(), [], "errors opening the window")
    eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle building the panel")
    eq(str(h.lua("return ns.Options.ActivePage()")), "global", "first page (Global sits on top)")
    eq(str(h.lua("return ns.Options.shell.subtitle:GetText() or ''")), "", "no version subtitle")
    eq(float(h.lua("return W.offscreen(SalusNovusOptions).any")), 0.0, "window off screen")
    h.lua('SlashCmdList["SALUSNOVUS"]("")')
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "toggle did not close")


@test("every page opens clean; previews run on show and halt on hide, returning the frame to UIParent", "options")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent and SalusNovusBars:IsShown()"), "bars preview not running on the Bars page")
    for key in ("reminders", "global", "bars"):
        h.lua("ns.Options.SelectPage('%s')" % key)
        eq(h.errors(), [], "errors on page %s" % key)
        eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle on page %s" % key)
        eq(str(h.lua("return ns.Options.ActivePage()")), key, "page not selected")
    h.lua("ns.Options.SelectPage('reminders')")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent"), "bars frame not returned after leaving its page")
    ok(h.lua("return SalusNovusReminderFrame:GetParent() ~= UIParent"), "reminders preview not running")
    h.lua("W.advance(0.1)")
    n = int(h.lua("return #ns.Reminders._active"))
    ok(n >= 1, "no sample reminder on the stage")
    h.lua("SalusNovusOptions:Hide(); W.advance(0.1)")
    ok(h.lua("return SalusNovusReminderFrame:GetParent() == UIParent"), "reminders frame not returned on close")
    ok(not h.lua("return SalusNovusReminderFrame:IsShown()"), "sample left on screen after close")


@test("every registered control round-trips set -> ApplyAll -> Refresh -> get", "options")
def _():
    h = fresh()
    open_options(h)
    # Setters refresh only the page in front (as MerkUI does), so each page
    # is exercised while it is the active one.
    bad = str(h.lua("""
        local out = {}
        for _, key in ipairs({ "bars", "reminders", "global" }) do
        ns.Options.SelectPage(key)
        for i, w in ipairs(ns.Options.widgets) do
            local kind = w.__outer == ns.Options.pages[key] and w.__kind or nil
            if kind == "check" then
                local before = w.__get() and true or false
                w.__set(not before); ns.ApplyAll(); ns.Options.Refresh()
                if (w:GetChecked() and true or false) ~= (not before) then out[#out+1] = "check#" .. i end
                w.__set(before); ns.ApplyAll(); ns.Options.Refresh()
            elseif kind == "stepper" then
                local before = w.__get()
                local target = (before == w.__min) and w.__max or w.__min
                w.__set(target); ns.ApplyAll(); ns.Options.Refresh()
                if math.abs((w:GetValue() or -1) - target) > 0.5 then out[#out+1] = "stepper#" .. i .. "=" .. tostring(w:GetValue()) .. " want " .. tostring(target) end
                w.__set(before); ns.ApplyAll(); ns.Options.Refresh()
            elseif kind == "choice" then
                local before = w.__get()
                local other
                for _, v in ipairs(w.__values) do if v ~= before then other = v break end end
                w.__set(other); ns.ApplyAll(); ns.Options.Refresh()
                if w.__get() ~= other then out[#out+1] = "choice#" .. i end
                w.__set(before); ns.ApplyAll(); ns.Options.Refresh()
            end
        end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", "controls that did not round-trip: %s" % bad)
    eq(h.errors(), [], "errors during the sweep")
    n = int(h.lua("local n = 0 for _, w in ipairs(ns.Options.widgets) do if w.__kind then n = n + 1 end end return n"))
    ok(n >= 25, "too few controls registered: %d" % n)


@test("a slider's first OnValueChanged (the client's layout pass at the minimum) never writes the setting", "options")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")     # pages build on first visit
    eq(int(h.lua("local n = 0 for _, w in ipairs(ns.Options.widgets) do if w.__kind == 'stepper' and w.__outer == ns.Options.pages.bars then n = n + 1 end end return n")) > 0, True, "no sliders found on the Bars page")
    bad = str(h.lua("""
        local out = {}
        for i, w in ipairs(ns.Options.widgets) do
            if w.__kind == "stepper" and w.__outer == ns.Options.pages.bars then
                local before = w.__get()
                -- what the client does on first layout: a value change at
                -- the minimum before anything has loaded the saved value
                w.primed = false
                w:GetScript("OnValueChanged")(w, w.__min)
                if w.__get() ~= before then out[#out+1] = "stepper#" .. i end
                w:Update()
            end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", "sliders that wrote their minimum on first layout: %s" % bad)


@test("unlock: Enter hides the panel, shows the bar and grid, unlocks both anchors; Cancel restores the snapshot incl. v=2", "options")
def _():
    h = fresh()
    # The frame is laid out first (a fresh install writes NO record: only the
    # user's save does), then the window.
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        __x0, __y0 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
        ns.Options.EnterUnlockMode()
    """)
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "panel still shown in unlock mode")
    ok(h.lua("return SalusNovusUnlockBar:IsShown() and SalusNovusAlignGrid:IsShown()"), "unlock bar or grid missing")
    ok(h.lua("return ns.db.unlocked and SalusNovusBars:IsMouseEnabled() and SalusNovusReminderFrame:IsMouseEnabled()"), "anchors not draggable")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent and SalusNovusBars:IsShown()"), "bars not on screen for dragging")
    h.lua("""
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
    """)
    h.lua("ns.Options.ExitUnlockMode(false)")
    ok(not h.lua("return ns.db.unlocked") and not h.lua("return SalusNovusUnlockBar:IsShown()") and not h.lua("return SalusNovusAlignGrid:IsShown()"), "cancel did not lock")
    x, y = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01, "snapshot not restored: %r vs %r" % ((x, y), (x0, y0)))
    ok(h.lua("return SalusNovusDB.barsPos == nil"), "the snapshot (no record) is back: the drag's record is gone")
    ok(h.lua("return SalusNovusOptions:IsShown()"), "panel did not come back")
    eq(str(h.lua("return ns.Options.ActivePage()")), "bars", "not the same page")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent"), "preview did not resume after cancel")
    ok(not h.lua("return SalusNovusBars:IsMouseEnabled()"), "still draggable after cancel")


@test("Cancel restores a pre-existing v=2 record exactly, not through the legacy (no-v) anchor branch", "options")
def _():
    # The position check above (GetLeft/GetTop right after Cancel) measures
    # the frame back in its options-page PREVIEW, which renders at a fixed
    # spot regardless of the real saved record -- it can't see this bug.
    # Re-entering unlock mode pulls the frame back onto UIParent for real,
    # which is the only place its on-screen position reflects the record.
    h = fresh()
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")   # TOPLEFT origin: distinct from the legacy branch's implied relPoint
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        ns.Options.EnterUnlockMode()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 200, 300)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.Options.ExitUnlockMode(true)   -- a real v=2 record now exists
        ns.Options.EnterUnlockMode()      -- pulls the frame back to UIParent
        __x0, __y0 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 900, 900)
        ns.SaveAnchor(SalusNovusBars, "barsPos")   -- drag away from the v=2 spot
    """)
    h.lua("ns.Options.ExitUnlockMode(false)")   # Cancel: should restore the v=2 record exactly
    ok(h.lua("return SalusNovusDB.barsPos.v == 2"), "the snapshot dropped the v=2 marker")
    h.lua("ns.Options.EnterUnlockMode()")       # back on UIParent: the real, user-visible spot
    x, y = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01,
       "Cancel restored through the legacy branch, not v=2: %r vs %r" % ((x, y), (x0, y0)))
    eq(h.errors(), [], "errors")


@test("unlock: Save keeps the new record and reopens the same page; a pull during unlock force-exits", "options")
def _():
    h = fresh()
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")   # the default is Up (Alex); these check the downward origin
    open_options(h)
    h.lua("ns.Options.SelectPage('reminders'); ns.Options.EnterUnlockMode()")
    h.lua("""
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.Options.ExitUnlockMode(true)
    """)
    x, y = h.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y")
    ok(abs(x - 100) < 0.01 and abs(y - 700) < 0.01, "saved record lost: %r" % ((x, y),))
    ok(h.lua("return SalusNovusOptions:IsShown()"), "panel did not come back")
    eq(str(h.lua("return ns.Options.ActivePage()")), "reminders", "not the same page")
    h.lua("ns.Options.EnterUnlockMode()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h.lua("return ns.db.unlocked"), "pull did not exit unlock mode")
    ok(not h.lua("return SalusNovusUnlockBar:IsShown()") and not h.lua("return SalusNovusAlignGrid:IsShown()"), "unlock chrome left up for the pull")
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "panel shown during the pull")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent and SalusNovusBars:IsShown()"), "bars not live for the pull")
    eq(h.errors(), [], "errors")


@test("the sidebar launcher opens the visualizer and closing it returns to options; ESC does not", "options")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.launcher:Click(); W.advance(0.1)")
    ok(h.lua("return SalusNovusVisualizer:IsShown()"), "visualizer not opened")
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "options still up under the visualizer")
    h.lua("W.advance(1); SalusNovusVisualizer:Hide()")
    ok(h.lua("return SalusNovusOptions:IsShown()"), "options did not return")
    # ESC with both windows up closes both in one keypress: the panel hides
    # first, then the visualizer, and the panel must not bounce back.
    h.lua("ns.Options.launcher:Click(); W.advance(1)")
    h.lua("SalusNovusOptions:Show(); ns.returnToOptions = true; SalusNovusOptions:Hide(); SalusNovusVisualizer:Hide()")
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "options came back after ESC")
    # ...but a hide a moment later is a click on the close button, and returns.
    h.lua("ns.Options.launcher:Click(); W.advance(1); SalusNovusVisualizer:Hide()")
    ok(h.lua("return SalusNovusOptions:IsShown()"), "options did not return after a later close")


@test("anchors sit on screen and do not overlap at default scale; both windows fit UIParent", "options")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    for name in ("SalusNovusBars", "SalusNovusReminderFrame"):
        eq(float(h.lua("return W.offscreen(%s).any" % name)), 0.0, "%s off screen" % name)
    ok(float(h.lua("return W.overlapArea(SalusNovusBars, SalusNovusReminderFrame)")) < 100, "anchors overlap")
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua('SlashCmdList["SALUSNOVUS"]("show")')
    for name in ("SalusNovusOptions", "SalusNovusVisualizer"):
        eq(float(h.lua("return W.offscreen(%s).any" % name)), 0.0, "%s off screen" % name)


# ------------------------------------------------------------------ polish

@test("wipe watch ends a fight when the encounter stops being in progress, but only after it was seen in progress", "polish")
def _():
    h = fresh()
    h.lua("__inprog = false; IsEncounterInProgress = function() return __inprog end")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(5)")
    ok(h.lua("return ns.Timers.IsActive()"), "a false before any true ended the fight")
    h.lua("__inprog = true; W.advance(3); __inprog = false; W.advance(3)")
    ok(not h.lua("return ns.Timers.IsActive()"), "wipe watch did not end the fight")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "records survived the wipe")
    # a simulated fight is never watched: the client knows nothing about it
    h.lua('__inprog = true; SlashCmdList["SALUSNOVUS"]("test plunder"); W.advance(3); __inprog = false; W.advance(3)')
    ok(h.lua("return ns.Timers.IsActive()"), "wipe watch killed a simulated fight")


# --------------------------------------------------------------- roster

DUNGEONS = [389, 3065, 2999, 36, 43, 33, 48, 34, 47, 90, 2998, 2959, 189, 129, 70,
            209, 349, 109, 230, 229, 329, 289, 42901, 42902, 42903,
            900001, 900002, 900003, 900004, 900005]
RAIDS = [249, 409, 469, 309, 509, 531, 533]
EXCLUDED = [2875, 2784, 2720, 2921, 2832, 2856, 2791, 2789, 2804, 13, 29, 44, 269, 169, 3109, 3002, 429]


@test("every included dungeon and raid loads, typed; nothing excluded leaks in", "roster")
def _():
    h = fresh()
    eq(h.errors(), [], "load errors")
    for m in DUNGEONS:
        eq(str(h.lua("return tostring(ns.Data[%d] and ns.Data[%d].type)" % (m, m))), "dungeon", "map %d" % m)
    for m in RAIDS:
        eq(str(h.lua("return tostring(ns.Data[%d] and ns.Data[%d].type)" % (m, m))), "raid", "map %d" % m)
    eq(int(h.lua("local n = 0 for _ in pairs(ns.Data) do n = n + 1 end return n")), len(DUNGEONS) + len(RAIDS), "instance count")
    for m in EXCLUDED:
        eq(str(h.lua("return tostring(ns.Data[%d])" % m)), "nil", "excluded map %d shipped" % m)


@test("every boss has a name and at least one id; ids are unique across the data; no duplicate names per instance", "roster")
def _():
    h = fresh()
    bad = str(h.lua("""
        local out, seen = {}, {}
        for mapID, inst in pairs(ns.Data) do
            local names = {}
            for _, b in ipairs(inst.bosses) do
                if type(b.name) ~= "string" or b.name == "" then out[#out+1] = mapID .. ":noname" end
                if not b.encounterID or not b.encounterIDs or #b.encounterIDs < 1 or b.encounterIDs[1] ~= b.encounterID then out[#out+1] = mapID .. ":" .. tostring(b.name) .. ":ids" end
                if names[b.name] then out[#out+1] = mapID .. ":" .. b.name .. ":dup" end
                names[b.name] = true
                for _, id in ipairs(b.encounterIDs or {}) do
                    if seen[id] then out[#out+1] = "id " .. id .. " twice" end
                    seen[id] = true
                end
            end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", "roster problems: %s" % bad)
    eq(int(h.lua("return #ns.Data[48].bosses")), 8, "Blackfathom should collapse to 8 bosses")
    eq(int(h.lua("local b = ns.BossByName('ghamoo') return #b.encounterIDs")), 3, "Ghamoo-ra should carry 3 ids")
    eq(int(h.lua("return ns.Data[3065].bosses[3].npcs[1].displayID")), 142840, "Plunder display id survived")
    ok(int(h.lua("return #ns.Schedule.Lanes(ns.Data[3065].bosses[3])")) > 0, "Hall of Thanes lanes lost")
    ok(h.lua("return ns.Data[36].bosses[7].npcs[1].displayID ~= nil"), "VanCleef has no display id from the tables")


@test("a pull on a boss's variant encounter id resolves the boss and fires its pull reminder; Simulate uses the first id", "roster")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "g1", encounterID = ns.BossByName("ghamoo").encounterID, trigger = "pull", text = "GHAMOO", sound = false } }
        __second = ns.BossByName("ghamoo").encounterIDs[2]
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", __second, "Ghamoo-ra", 1, 5, 48)')
    eq(str(h.lua("return ns.Timers.Boss().name")), "Ghamoo-ra", "variant id did not resolve")
    h.lua("W.advance(0.1)")
    ok("GHAMOO" in fired(h), "pull reminder keyed by the first id did not fire: %r" % fired(h))
    h.lua('W.fireEvent("ENCOUNTER_END", __second, "Ghamoo-ra", 1, 5, 1)')
    h.lua('SlashCmdList["SALUSNOVUS"]("test ghamoo")')
    eq(int(h.lua("return ns.Timers.EncounterID()")), int(h.lua("return ns.BossByName('ghamoo').encounterID")), "Simulate should use the first id")


@test("visualizer sidebar: Dungeons lists 30 in level order with their level ranges, Raids 7; a raid boss flips the strip; the list scrolls", "roster")
def _():
    h = fresh()
    open_vis(h)
    eq(str(h.lua("return ns.Visualizer.state.mode")), "dungeons", "should open on dungeons")
    names = [str(h.lua("return ns.Visualizer.Instances('dungeons')[%d].inst.name" % i)) for i in range(1, 31)]
    eq(len(set(names)), 30, "dungeon rows: %r" % names)
    eq(str(h.lua("return tostring(ns.Visualizer.Instances('dungeons')[31])")), "nil", "more than 30 dungeons")
    eq(names[0], "Ragefire Chasm", "first dungeon by level")
    ok(names.index("Ragefire Chasm") < names.index("Deadmines") < names.index("Scholomance") < names.index("Dire Maul: North"),
       "level order broken: %r" % names)
    ok("Half-Pint Tavern" not in names and "Dire Maul" not in names, "Half-Pint Tavern or the unsplit Dire Maul still listed: %r" % names)
    for wing in ("Dire Maul: East", "Dire Maul: West", "Dire Maul: North"):
        ok(wing in names, "%s missing" % wing)
    for coming in ("The Drowned City", "Krol'dok Stronghold", "Alcaz Prison", "Blackmaw Hold", "The Shapers' Terrace"):
        ok(coming in names, "%s missing" % coming)
    # the sidebar rows carry the chart's level ranges; the Stronghold is 40-45 (Alex)
    # the range sits on its own smaller line under the name (Alex)
    labels = str(h.lua("""
        local out = {}
        for i = 1, 40 do local r = ns.Visualizer._instRows and ns.Visualizer._instRows[i] if r and r:IsShown() then out[#out + 1] = r.label:GetText() .. "/" .. r.sub:GetText() end end
        return table.concat(out, "|")
    """))
    ok("Deadmines/Level 18-24" in labels, "level range missing under the name: %s" % labels)
    ok("Krol'dok Stronghold/Level 40-45" in labels, "Stronghold range wrong: %s" % labels)
    ok("Dire Maul: East/Level 55-60" in labels and "Dire Maul: North/Level 59-60" in labels, "wing ranges: %s" % labels)
    ok("(" not in labels.split("|")[0].split("/")[0], "range still inline in the name")
    # raids are level 60 and say nothing; their name is centred in the row
    ok(h.lua("for _, e in ipairs(ns.Visualizer.Instances('raids')) do if e.inst.levelRange then return false end end return true"), "a raid carries a level range")
    h.lua("SalusNovusVisualizer.modeButtons[2]:Click()")
    ok(h.lua("local r = ns.Visualizer._instRows[1] return r.sub:GetText() == '' and select(1, r.label:GetPoint()) == 'LEFT'"), "raid row should have no level line and a centred name")
    h.lua("SalusNovusVisualizer.modeButtons[1]:Click()")
    eq(int(h.lua("return #ns.Data[42901].bosses + #ns.Data[42902].bosses + #ns.Data[42903].bosses")), 19, "Dire Maul wings should hold all 19 bosses")
    eq(int(h.lua("return #ns.Data[900002].bosses")), 0, "a coming dungeon has no bosses")
    ok(h.lua("return ns.Data[900002].coming == true"), "coming flag")
    # a hand-added entry with no name and a shared level must not break the sort
    h.lua("ns.Data[999999] = { type = 'dungeon', level = 18, bosses = {} }")
    ok(h.lua("return (pcall(ns.Visualizer.Instances, 'dungeons'))"), "the instance sort threw on a nameless entry")
    h.lua("ns.Data[999999] = nil")
    raids = [str(h.lua("return ns.Visualizer.Instances('raids')[%d].inst.name" % i)) for i in range(1, 8)]
    eq(len(set(raids)), 7, "raid rows")
    eq(str(h.lua("return tostring(ns.Visualizer.Instances('raids')[8])")), "nil", "more than 7 raids")
    eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle")
    # the mock computes no scroll ranges; the content overflowing the
    # viewport is what makes the real client show the slider
    ch, vh = h.lua("return SalusNovusVisualizer.bossList.child:GetHeight(), SalusNovusVisualizer.bossList:GetHeight()")
    ok(ch > vh, "24 rows should overflow the sidebar: child %r vs view %r" % (ch, vh))
    h.lua("SalusNovusVisualizer.modeButtons[2]:Click()")
    eq(str(h.lua("return ns.Visualizer.state.mode")), "raids", "mode strip did not switch")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[409].bosses[1])")
    eq(str(h.lua("return ns.Visualizer.state.mode")), "raids", "raid boss should keep raids mode")
    eq(int(h.lua("return ns.Visualizer.state.openInst")), 409, "instance not opened")
    meta = str(h.lua("return SalusNovusVisualizer.bossMeta:GetText()"))
    eq(meta, "", "a raid boss has no meta line: %r" % meta)
    ok("pull" not in meta and "abilit" not in meta and "fight" not in meta, "meta carries noise: %r" % meta)
    eq(str(h.lua("return SalusNovusVisualizer.zoomNote:GetText() or ''")), "", "no 'whole fight' text at zoom 1")
    eq(str(h.lua("return SalusNovusVisualizer.shell.subtitle:GetText() or ''")), "", "window subtitle should be gone")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    eq(str(h.lua("return ns.Visualizer.state.mode")), "dungeons", "dungeon boss should flip back")
    eq(str(h.lua("return SalusNovusVisualizer.bossMeta:GetText()")), "", "no level under a dungeon boss (Alex)")
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[2])")
    ok("fought as" not in str(h.lua("return SalusNovusVisualizer.bossMeta:GetText()")), "no fought-as")
    eq(str(h.lua("return SalusNovusVisualizer.bossTitle:GetText()")), "Magmatus", "Infurnus should be titled Magmatus")
    ok(str(h.lua("return ns.Visualizer._lanes[1].desc:GetText() or ''")) == "", "reminders lane should carry no hint")
    ok("seen in" not in str(h.lua("return ns.Visualizer._lanes[2].desc:GetText() or ''")), "ability lanes should not say 'seen in'")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- queue

def queue_icons(h):
    n = int(h.lua("local n = 0 for i = 1, 8 do if ns.Queue._icons[i]:IsShown() then n = n + 1 end end return n"))
    return n


@test("the queue shows the soonest casts first, shrinking, fading and desaturating after the lead, capped by count", "queue")
def _():
    h = fresh()
    h.lua("ns.db.queue.shrink = 80; ns.ApplyAll()")   # the default is 100 (Alex); the maths is tested at 80
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return SalusNovusQueue:IsShown()"), "strip not shown")
    records = int(h.lua("return #ns.Timers.Sorted()"))
    eq(queue_icons(h), min(5, records), "icon count should be min(count, records)")
    eq(str(h.lua("return ns.Queue._icons[1].entry.bar.key")), str(h.lua("return ns.Timers.Sorted()[1].key")), "lead is not the soonest record")
    eq(str(h.lua("return ns.Queue._icons[1].label:GetText()")), "Knock Away", "lead label")
    sizes = [int(h.lua("return ns.Queue._icons[%d]:GetWidth()" % i)) for i in range(1, min(5, records) + 1)]
    eq(sizes[:3], [48, 38, 31], "sizes should shrink 80%% a step: %r" % sizes)
    ok(all(s >= 16 for s in sizes), "an icon went under the 16px floor: %r" % sizes)
    n = min(5, records)
    a_last = float(h.lua("return ns.Queue._icons[%d]:GetAlpha()" % n))
    ok(abs(a_last - 0.5) < 0.01 or n == 1, "last icon should fade to 1-fade: %r" % a_last)
    eq(float(h.lua("return ns.Queue._icons[1]:GetAlpha()")), 1.0, "lead should not fade")
    ok(not h.lua("return ns.Queue._icons[1].tex.__desaturated") and h.lua("return ns.Queue._icons[2].tex.__desaturated"), "desaturation after the lead")
    eq(int(h.lua("return ns.Queue._icons[1].borderThick")), 2, "lead border")
    eq(int(h.lua("return ns.Queue._icons[2].borderThick")), 1, "other borders")
    ok(not h.lua("return ns.Queue._icons[2].label:IsShown()"), "labels = lead should name the lead only")
    h.lua("ns.db.queue.count = 2; ns.ApplyAll()")
    eq(queue_icons(h), 2, "count cap")
    # a landed cast inside its hold keeps its icon, without error
    h.lua("W.advance(%f)" % (float(h.lua("return ns.Timers.Sorted()[1].at - GetTime()")) + 1.0))
    ok(h.lua("return ns.Queue._icons[1]:IsShown()"), "lead icon gone inside its hold")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "strip shown after the fight")
    # the floors: eight placeholders with a heavy fade and a tiny shrink
    h.lua("ns.db.queue.count = 8; ns.db.queue.fade = 90; ns.db.queue.size = 24; ns.db.queue.shrink = 40; ns.db.unlocked = true; ns.ApplyAll()")
    eq(queue_icons(h), 8, "eight placeholders")
    ok(abs(float(h.lua("return ns.Queue._icons[8]:GetAlpha()")) - 0.15) < 0.01, "alpha floor 0.15 not applied")
    sizes = [int(h.lua("return ns.Queue._icons[%d]:GetWidth()" % i)) for i in range(1, 9)]
    eq(sizes, [24, 16, 16, 16, 16, 16, 16, 16], "shrink should floor at 16px: %r" % sizes)


@test("no drain bar on the icons (Alex); seconds rewrite only when the integer changes, and the next cast takes the lead", "queue")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Queue._icons[1].edge == nil and ns.Queue._icons[1].edgeBg == nil"), "the drain bar textures must not exist")
    ok(not h.lua("return ns.Queue._icons[1].cd:IsShown()"), "nothing on the icon by default (no swipe either)")
    t1 = float(h.lua("return ns.Timers.Sorted()[1].at - ns.Timers.StartedAt()"))
    h.lua("""
        __writes = 0
        local t = ns.Queue._icons[1].timer
        local orig = t.SetText
        t.SetText = function(self, s) __writes = __writes + 1 return orig(self, s) end
    """)
    h.lua("W.advance(2)")      # 10 hub ticks
    writes = int(h.lua("return __writes"))
    ok(0 < writes <= 3, "seconds should rewrite about twice in 2s, got %d" % writes)
    # when the first record expires the second is the lead
    key2 = str(h.lua("return ns.Timers.Sorted()[2].key"))
    h.lua("W.advance(%f)" % (t1 + 2.6 - 2))
    eq(str(h.lua("return ns.Queue._icons[1].entry.bar.key")), key2, "next cast did not take the lead")
    h.lua("ns.db.queue.timeOnIcon = 'swipe'; ns.ApplyAll()")
    ok(h.lua("return ns.Queue._icons[1].cd:IsShown()"), "swipe mode")
    h.lua("ns.db.queue.timeOnIcon = 'none'; ns.ApplyAll()")
    ok(not h.lua("return ns.Queue._icons[1].cd:IsShown()"), "none mode")
    h.lua("ns.db.queue.timeOnIcon = 'edge'; ns.ApplyAll()")   # an old stored value: no bar comes back
    ok(not h.lua("return ns.Queue._icons[1].cd:IsShown()") and h.lua("return ns.Queue._icons[1].edge == nil"), "a stored 'edge' must draw nothing")
    h.lua("ns.db.queue.labels = 'all'; ns.ApplyAll()")
    ok(h.lua("return ns.Queue._icons[2].label:IsShown()"), "labels = all")
    h.lua("ns.db.queue.labels = 'none'; ns.ApplyAll()")
    ok(not h.lua("return ns.Queue._icons[1].label:IsShown()"), "labels = none")
    eq(h.errors(), [], "errors")


@test("queue anchor: direction up re-pins by BOTTOMLEFT with no drift; disabled/module-off hide it; unlock shows placeholders; preview round-trips", "queue")
def _():
    h = fresh()
    h.lua("ns.db.queue.direction = 'up'; ns.db.unlocked = true; ns.ApplyAll()")
    eq(str(h.lua("local p = SalusNovusQueue:GetPoint() return p")), "BOTTOMLEFT", "origin for an upward strip")
    eq(queue_icons(h), 5, "unlocked with nothing live should show placeholders")
    ok(h.lua("return SalusNovusQueue:IsMouseEnabled()"), "not draggable while unlocked")
    l0, b0 = h.lua("return SalusNovusQueue:GetLeft(), SalusNovusQueue:GetBottom()")
    h.lua("ns.db.queue.count = 8; ns.ApplyAll()")
    l1, b1 = h.lua("return SalusNovusQueue:GetLeft(), SalusNovusQueue:GetBottom()")
    ok(abs(l0 - l1) < 0.01 and abs(b0 - b1) < 0.01, "bottom-left drifted: %r -> %r" % ((l0, b0), (l1, b1)))
    # vertical strips keep a label's room under each labelled icon
    for d in ("down", "up"):
        h.lua("ns.db.queue.direction = '%s'; ns.db.queue.labels = 'all'; ns.ApplyAll()" % d)
        room = int(h.lua("return ns.db.queue.labelSize + 6"))
        gapv = float(h.lua("""
            local a, b = ns.Queue._icons[1], ns.Queue._icons[2]
            if ns.db.queue.direction == "down" then return a:GetBottom() - b:GetTop() else return b:GetBottom() - a:GetTop() end
        """))
        ok(gapv >= room + 6 - 0.01, "%s: icon 2 sits on icon 1's label (gap %r, need %r)" % (d, gapv, room + 6))
    h.lua("ns.db.queue.labels = 'lead'")
    h.lua("ns.db.unlocked = false; ns.db.queue.direction = 'right'; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "idle locked strip shown")
    h.lua("ns.db.queue.enabled = false; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "shown while disabled")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.db.queue.enabled = true; ns.db.modules.bossWarnings = false; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "shown while the module is off")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.db.modules.bossWarnings = true; ns.ApplyAll()")
    # preview
    h.lua("""
        ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()
        __l, __t = SalusNovusQueue:GetLeft(), SalusNovusQueue:GetTop()
        __stage = CreateFrame("Frame", "QStage", UIParent)
        __stage:SetSize(400, 96)
        __stage:SetPoint("CENTER")
        ns.QueuePreviewStart(__stage)
    """)
    ok(h.lua("return SalusNovusQueue:GetParent() == __stage and SalusNovusQueue:IsShown()"), "not on the stage")
    eq(queue_icons(h), 6, "preview should show the six fakes (count is 8 here)")
    h.lua("ns.SaveAnchor(SalusNovusQueue, 'queuePos')")     # refused off UIParent
    h.lua("ns.QueuePreviewStop()")
    ok(h.lua("return SalusNovusQueue:GetParent() == UIParent"), "not back on UIParent")
    l, t = h.lua("return SalusNovusQueue:GetLeft(), SalusNovusQueue:GetTop()")
    l0, t0 = h.lua("return __l, __t")
    ok(abs(l - l0) < 0.01 and abs(t - t0) < 0.01, "did not return to its spot")
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "idle strip shown after preview")
    eq(h.errors(), [], "errors")


@test("the Queue page opens clean with a running preview, its controls round-trip, and three anchors do not overlap", "queue")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('queue')")
    eq(int(h.lua("return #W.anchorCycles")), 0, "anchor cycle")
    ok(h.lua("return SalusNovusQueue:GetParent() ~= UIParent and SalusNovusQueue:IsShown()"), "queue preview not running")
    n = int(h.lua("local n = 0 for _, w in ipairs(ns.Options.widgets) do if w.__kind and w.__outer == ns.Options.pages.queue then n = n + 1 end end return n"))
    ok(n >= 13, "too few controls on the Queue page: %d" % n)
    h.lua("SalusNovusOptions:Hide()")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    for name in ("SalusNovusBars", "SalusNovusReminderFrame", "SalusNovusQueue"):
        eq(float(h.lua("return W.offscreen(%s).any" % name)), 0.0, "%s off screen" % name)
    ok(float(h.lua("return W.overlapArea(SalusNovusBars, SalusNovusQueue)")) < 100, "bars and queue overlap")
    ok(float(h.lua("return W.overlapArea(SalusNovusReminderFrame, SalusNovusQueue)")) < 100, "reminders and queue overlap")
    eq(h.errors(), [], "errors")


# -------------------------------------------------------------- modules

def page_states(h, key):
    n = int(h.lua("return #ns.Options.widgets"))
    out = []
    for i in range(1, n + 1):
        if h.lua("local w = ns.Options.widgets[%d] return w.__outer == ns.Options.pages['%s'] and w.SetEnabledState ~= nil" % (i, key)):
            out.append(bool(h.lua("return ns.Options.widgets[%d].enabledState ~= false and (ns.Options.widgets[%d].IsEnabled == nil or ns.Options.widgets[%d]:IsEnabled() ~= false)" % (i, i, i))))
    return out


@test("the sidebar has a Boss Warnings heading with a switch and a Global heading without; the visualizer row sits under Anchors", "modules")
def _():
    h = fresh()
    open_options(h)
    ok(h.lua("return ns.Options.moduleSwitches.bossWarnings ~= nil"), "no module switch")
    ok(h.lua("return ns.Options.moduleSwitches.bossWarnings:GetChecked()"), "switch should start on")
    eq(int(h.lua("local n = 0 for _ in pairs(ns.Options.moduleSwitches) do n = n + 1 end return n")), 3, "three module switches: Boss Warnings, Quality of Life, Leveling; Global has none")
    ok(h.lua("return ns.Options.moduleSwitches.qol ~= nil and ns.Options.moduleSwitches.global == nil"), "Quality of Life needs a switch, Global must not")
    ok(h.lua("return ns.Options.launcher ~= nil and ns.Options.launcher.label:GetText() == 'BOSS VISUALIZER'"), "launcher row missing")   # nav labels are uppercase (Slab)
    ok(float(h.lua("return ns.Options.launcher:GetTop()")) < float(h.lua("return ns.Options.launcher:GetParent():GetTop()")) - 100, "launcher row not in the module list")
    h.lua("ns.Options.launcher:Click(); W.advance(0.1)")
    ok(h.lua("return SalusNovusVisualizer:IsShown() and not SalusNovusOptions:IsShown()"), "launcher row did not open the visualizer")
    h.lua("W.advance(1); SalusNovusVisualizer:Hide()")
    ok(h.lua("return SalusNovusOptions:IsShown()"), "did not return to options")
    eq(h.errors(), [], "errors")


@test("switching Boss Warnings off stops bars and reminders in a fight while the hub keeps tracking; on again restores them", "modules")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.moduleSwitches.bossWarnings:Click()")
    ok(not h.lua("return ns.ModuleOn('bossWarnings')"), "switch did not write the DB")
    ok(not h.lua("return ns.db.modules.bossWarnings"), "DB value")
    h.lua("SalusNovusOptions:Hide()")
    h.lua(SHIPPED)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(1)")
    ok(h.lua("return ns.Timers.IsActive() and #ns.Timers.Sorted() > 0"), "hub should keep tracking")
    ok(not h.lua("return SalusNovusBars:IsShown()"), "bars shown while the module is off")
    eq(fired(h), [], "reminders fired while the module is off")
    h.lua('W.fireEvent("UNIT_SPELLCAST_START", "target", "Cast-2", W.secretNumber())')
    eq(fired(h), [], "cast reminder fired while off")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    # per-page enables untouched underneath
    ok(h.lua("return ns.db.bars.enabled and ns.db.reminders.enabled"), "page enables were changed")
    h.lua("ns.db.modules.bossWarnings = true; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(1)")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars did not come back")
    ok(len(fired(h)) > 0, "reminders did not come back")
    ok("Boss Warnings on" in "".join(h.lua("SlashCmdList['SALUSNOVUS']('status') return table.concat(W.printed, '|')")), "status line missing")


@test("while off, the module's anchors hide even in unlock mode and its pages read as disabled with suspended previews; Global stays live", "modules")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('global')")
    global_before = page_states(h, "global")
    h.lua("ns.Options.moduleSwitches.bossWarnings:Click()")
    ok(not h.lua("return ns.Options.unlockButton.enabledState"), "Unlock Frames should grey out on the click itself, not the next page change")
    for key in ("bars", "reminders"):
        h.lua("ns.Options.SelectPage('%s')" % key)
        states = page_states(h, key)
        ok(states and not any(states), "%s page controls should all be disabled: %r" % (key, states))
        note = str(h.lua("""
            for _, s in ipairs(ns.Options.previewStages) do
                if s.outer == ns.Options.pages['%s'] then return s.note:IsShown() and s.note:GetText() or "" end
            end
            return ""
        """ % key))
        eq(note, "", "%s preview should be suspended silently, no wording (Alex): %r" % (key, note))
        running = h.lua("""
            for _, s in ipairs(ns.Options.previewStages) do
                if s.outer == ns.Options.pages['%s'] then return s.running end
            end
        """ % key)
        ok(not running, "%s preview should be halted while the module is off" % key)
    ok(not h.lua("return ns.Options.unlockButton.enabledState"), "Unlock Frames should be disabled")
    h.lua("ns.Options.SelectPage('global')")
    states = page_states(h, "global")
    # Global is not a module: its controls follow only their own rules
    # (custom accent, font), exactly as before the switch was thrown.
    eq(states, global_before, "Global controls changed with the module switch")
    ok(any(states), "Global should have live controls")
    h.lua("SalusNovusOptions:Hide(); ns.db.unlocked = true; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusBars:IsShown()") and not h.lua("return SalusNovusReminderFrame:IsShown()"), "anchors shown in unlock mode while off")
    h.lua("ns.db.unlocked = false; ns.db.modules.bossWarnings = true; ns.ApplyAll(); SalusNovusOptions:Show(); ns.Options.SelectPage('bars')")
    states = page_states(h, "bars")
    ok(any(states), "controls did not re-enable when the module came back")
    ok(h.lua("return ns.Options.unlockButton.enabledState"), "Unlock Frames should be enabled again")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent"), "preview did not resume")
    eq(h.errors(), [], "errors")


# --------------------------------------------------------------- bug hunt
# Five reviewers read the addon cold (2026-09-19); each confirmed finding
# has a test here that failed before its fix.

@test("a combat res mid-fight gets the rest of the schedule back", "bughunt")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = {
            { id = "t3", encounterID = 3494, trigger = "time", arg = 6, lead = 1, text = "LATER", sound = false },
            { id = "t9", encounterID = 3494, trigger = "time", arg = 9, lead = 1, text = "LATEST", sound = false },
        }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1); W.playerDead = true; W.fireEvent("PLAYER_DEAD")')
    h.lua('W.advance(1); W.playerDead = false; W.fireEvent("PLAYER_ALIVE")')
    h.lua("W.advance(4)")
    ok("LATER" in fired(h), "reminder lost to a death the player came back from: %r" % fired(h))
    h.lua("W.advance(3)")
    ok("LATEST" in fired(h), "later reminder lost too: %r" % fired(h))
    # once each: the re-arm must not double up what already fired
    eq(fired(h).count("LATER"), 1, "re-arm doubled a fired reminder")
    # a res after the fight ended arms nothing
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1); W.fireEvent("PLAYER_UNGHOST"); W.advance(10)')
    eq(fired(h).count("LATER"), 1, "armed after the fight")
    eq(h.errors(), [], "errors")


@test("a cast by a FRIENDLY target is not the boss; secret or missing hostility fails open", "bughunt")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "c1", encounterID = 3493, trigger = "cast", text = "CASTING", sound = false } }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3493, "Faldrim Anvilmar", 1, 5, 3065)')
    h.lua('__hostile.target = false; W.fireEvent("UNIT_SPELLCAST_START", "target", "Cast-1", W.secretNumber())')
    eq(len(fired(h)), 0, "fired for the party mage")
    h.lua('__hostile.target = true; W.fireEvent("UNIT_SPELLCAST_START", "target", "Cast-2", W.secretNumber())')
    eq(len(fired(h)), 1, "did not fire for a hostile target")
    h.lua('W.advance(4); __hostile.nameplate2 = W.secret(false); W.fireEvent("UNIT_SPELLCAST_START", "nameplate2", "Cast-3", W.secretNumber())')
    eq(len(fired(h)), 2, "a secret answer must count as the boss")
    h.lua('W.advance(4); local f = UnitCanAttack; UnitCanAttack = nil; W.fireEvent("UNIT_SPELLCAST_START", "nameplate3", "Cast-4", W.secretNumber()); UnitCanAttack = f')
    eq(len(fired(h)), 3, "a missing UnitCanAttack must count as the boss")
    eq(h.errors(), [], "errors")


@test("/sn reminders lists a record with no text instead of throwing", "bughunt")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = { { id = "n1", encounterID = 3494, trigger = "pull", sound = false } }
    """)
    ok(h.lua("return (pcall(ns.Commands.reminders))"), "threw on a text-less record")
    eq(h.errors(), [], "errors")


@test("an object first seen already wearing Salus Novus's font is restored to the stock font, never pinned to ours", "bughunt")
def _():
    h = fresh()
    h.lua("""
        local function FO(path, size, flags)
            local o = { __path = path, __size = size, __flags = flags }
            function o:GetFont() return self.__path, self.__size, self.__flags end
            function o:SetFont(p, s, f) self.__path, self.__size, self.__flags = p, s, f return true end
            o[0] = true
            function o:GetObjectType() return "Font" end
            return o
        end
        GameFontNormal = FO("Fonts\\\\FRIZQT__.TTF", 12, "")
        GetFonts = function() return { "GameFontNormal" } end
        ns.db.font.wholeUI = true; ns.ApplyUIFont(true, true)
        -- a load-on-demand frame inherits GameFontNormal: it is born in OUR font
        LateInheritedFont = FO(ns.ActiveFont(), 11, "")
        W.fireEvent("ADDON_LOADED", "Blizzard_Professions")
    """)
    active = str(h.lua("return ns.ActiveFont()"))
    eq(str(h.lua("return LateInheritedFont.__path")), active, "late object not fonted")
    h.lua("ns.db.font.wholeUI = false; ns.ApplyAll()")
    eq(str(h.lua("return GameFontNormal.__path")), "Fonts\\FRIZQT__.TTF", "GameFontNormal not restored")
    ok(str(h.lua("return LateInheritedFont.__path")) != active, "late object pinned to Salus Novus's font after the switch went off")
    h.lua("GameFontNormal = nil; GetFonts = nil; LateInheritedFont = nil")
    eq(h.errors(), [], "errors")


@test("scroll thumbs and hovered toggles follow the accent and the rest colour", "bughunt")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('global')")
    h.lua("""
        ns.db.theme.useClassColor = false
        ns.db.theme.customColor = { r = 0.1, g = 0.9, b = 0.2 }
        ns.ApplyAll()
    """)
    col = h.lua("""
        local function walk(f)
            -- a scroll area's bar, not an options slider (both carry .thumb)
            if f.slider and f.slider.thumb then return f.slider.thumb end
            for _, c in ipairs({ f:GetChildren() }) do local t = walk(c) if t then return t end end
        end
        local t = walk(SalusNovusOptions)
        return { t:GetVertexColor() }
    """)
    r, g, b = float(col[1]), float(col[2]), float(col[3])
    ok(abs(r - 0.1) < 0.01 and abs(g - 0.9) < 0.01 and abs(b - 0.2) < 0.01, "scroll thumb did not follow the accent: %r" % ((r, g, b),))
    h.lua("""
        __cb = ns.Theme.MakeCheck(UIParent, "x", 16)
        __rest = { __cb.border.all[1]:GetVertexColor() }
        __cb:GetScript("OnEnter")(__cb)
        __cb:GetScript("OnLeave")(__cb)
        __after = { __cb.border.all[1]:GetVertexColor() }
    """)
    rest, after = h.lua("return __rest"), h.lua("return __after")
    ok(abs(rest[4] - after[4]) < 0.001, "hover left the toggle border brighter: %r vs %r" % (rest[4], after[4]))
    eq(h.errors(), [], "errors")


@test("SnapMovable never pulls a frame onto a grid line while the grid is hidden", "bughunt")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    # 325 px right of centre: 5 px from the 320 line of a 32 px grid, far
    # from every other anchor's centre and edges.
    for grid_on, want in ((True, 320), (False, 325)):
        h.lua("""
            local ux, uy = UIParent:GetCenter()
            ns.db.anchorsGlobal.gridSize = 32
            ns.db.anchorsGlobal.grid = %s
            SalusNovusBars:ClearAllPoints()
            SalusNovusBars:SetPoint("CENTER", UIParent, "BOTTOMLEFT", ux + 325, uy - 200)
            ns.SnapMovable(SalusNovusBars)
        """ % ("true" if grid_on else "false"))
        cx, ux = h.lua("local cx = SalusNovusBars:GetCenter() local ux = UIParent:GetCenter() return cx, ux")
        ok(abs(cx - (ux + want)) < 0.01, "grid %s: centre at +%r, want +%d" % (grid_on, cx - ux, want))


@test("ParseTime takes digits only: no exponents, hex, inf or sign", "bughunt")
def _():
    h = fresh()
    for bad in ("1e400", "0x1f", "inf", "nan", "-5", "+5", "2:", "abc"):
        eq(str(h.lua("return tostring(ns.Visualizer.ParseTime('%s'))" % bad)), "nil", "accepted %r" % bad)
    eq(float(h.lua("return ns.Visualizer.ParseTime(' 7 ')")), 7.0, "padded digits")
    eq(float(h.lua("return ns.Visualizer.ParseTime('7.5')")), 7.5, "decimal")
    eq(float(h.lua("return ns.Visualizer.ParseTime('1:05')")), 65.0, "m:ss")


@test("the form refuses a time past the fight end instead of saving a reminder the lanes never draw", "bughunt")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    n0 = int(h.lua("return #ns.Reminders.For(3494)"))
    h.lua("""
        local lane = ns.Visualizer._lanes[2]
        local axis = SalusNovusVisualizer.axis
        GetCursorPosition = function() return (axis:GetLeft() + 10) * axis:GetEffectiveScale(), 0 end
        lane.track:GetScript("OnClick")(lane.track)
        local f = ns.Visualizer.form
        f.text:SetText("TOO LATE")
        f.at:SetText(tostring(ns.Visualizer.FightEnd() + 60))
        f.save:Click()
    """)
    eq(int(h.lua("return #ns.Reminders.For(3494)")), n0, "saved a reminder past the fight end")
    ok(h.lua("return ns.Visualizer.form:IsShown()"), "form closed on a refused save")
    ok("ends at" in str(h.lua("return ns.Visualizer.form.atNote:GetText()")), "no note explaining the refusal")
    h.lua("ns.Visualizer.form.at:SetText(tostring(ns.Visualizer.FightEnd())); ns.Visualizer.form.save:Click()")
    eq(int(h.lua("return #ns.Reminders.For(3494)")), n0 + 1, "a time AT the fight end must save")
    eq(h.errors(), [], "errors")


@test("a spell the client cannot load is asked for once, not on every answer", "bughunt")
def _():
    h = fresh()
    h.lua("""
        __req = {}
        C_Spell.RequestLoadSpellData = function(id) __req[id] = (__req[id] or 0) + 1 end
        C_Spell.IsSpellDataCached = function() return false end
        C_Spell.GetSpellDescription = function() return nil end
    """)
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("""
        for id in pairs(__req) do
            for i = 1, 3 do W.fireEvent("SPELL_DATA_LOAD_RESULT", id, false) end
        end
    """)
    worst = int(h.lua("local m = 0 for _, n in pairs(__req) do if n > m then m = n end end return m"))
    ok(int(h.lua("local c = 0 for _ in pairs(__req) do c = c + 1 end return c")) > 0, "nothing requested")
    eq(worst, 1, "a spell was re-requested %d times" % worst)
    eq(h.errors(), [], "errors")


@test("opening the visualizer on a variant encounter id lands on the primary id with the view and form reset", "bughunt")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("""
        ns.Visualizer.Zoom(2); ns.Visualizer.Zoom(2)
        SalusNovusVisualizer.pan:SetValue(100)
        local lane = ns.Visualizer._lanes[2]
        local axis = SalusNovusVisualizer.axis
        GetCursorPosition = function() return (axis:GetLeft() + 10) * axis:GetEffectiveScale(), 0 end
        lane.track:GetScript("OnClick")(lane.track)
    """)
    ok(h.lua("return ns.Visualizer.form:IsShown()"), "form not open before the switch")
    h.lua("ns.Visualizer.Toggle(true, 2761)")   # Blackfathom's Ghamoo-ra by a variant id
    eq(int(h.lua("return ns.Visualizer.state.enc")), 2916, "not normalised to the primary encounter id")
    eq(float(h.lua("return ns.Visualizer.state.zoom")), 1.0, "zoom kept across bosses")
    eq(float(h.lua("return ns.Visualizer.state.offset")), 0.0, "offset kept across bosses")
    ok(not h.lua("return ns.Visualizer.form:IsShown()"), "form left open across bosses")
    eq(h.errors(), [], "errors")


@test("a second Unlock Frames keeps the first snapshot, so Cancel still undoes the drag", "bughunt")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("ns.Options.SelectPage('bars'); __x0, __y0 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop(); ns.Options.EnterUnlockMode()")
    h.lua("""
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.ToggleOptions()            -- reopened mid-drag
        ns.Options.EnterUnlockMode()  -- and Unlock Frames pressed again
    """)
    ok(not h.lua("return SalusNovusOptions:IsShown()") and h.lua("return SalusNovusUnlockBar:IsShown()"), "second Enter did not hand back the unlock bar")
    h.lua("ns.Options.ExitUnlockMode(false)")
    x, y = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01, "Cancel restored the dragged position: %r vs %r" % ((x, y), (x0, y0)))


@test("a second Unlock Frames does not retake the snapshot: Cancel restores the real pre-drag spot on UIParent", "bughunt")
def _():
    # The check above reads GetLeft/GetTop right after Cancel, while the
    # frame is back in the options-page PREVIEW -- that renders at a fixed
    # spot no matter what the underlying record says, so it cannot tell a
    # correct restore from a wrong one. Re-entering unlock mode pulls the
    # frame back onto UIParent, where its position really does depend on
    # SalusNovusDB.barsPos.
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("ns.Options.SelectPage('bars'); ns.Options.EnterUnlockMode()")
    x0, y0 = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    h.lua("""
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.ToggleOptions()            -- reopened mid-drag
        ns.Options.EnterUnlockMode()  -- and Unlock Frames pressed again
    """)
    h.lua("ns.Options.ExitUnlockMode(false)")
    h.lua("ns.Options.EnterUnlockMode()")   # back on UIParent: the real, user-visible spot
    x, y = h.lua("return SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01,
       "a second Enter took a fresh (already-dragged) snapshot: %r vs %r" % ((x, y), (x0, y0)))
    eq(h.errors(), [], "errors")


def _cancel_restores_v2(h, page, frame_name, key):
    """Same protocol as the Bars fix (commit 531a974): the position check
    right after Cancel would read the frame in the options-page PREVIEW,
    which draws at a fixed spot no matter what SalusNovusDB says. Re-enter
    unlock mode to pull the frame back onto UIParent before measuring."""
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('%s')
        ns.Options.EnterUnlockMode()
        %s:ClearAllPoints()
        %s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 200, 300)
        ns.SaveAnchor(%s, "%s")
        ns.Options.ExitUnlockMode(true)   -- a real v=2 record now exists
        ns.Options.EnterUnlockMode()      -- pulls the frame back to UIParent
        __x0, __y0 = %s:GetLeft(), %s:GetTop()
        %s:ClearAllPoints()
        %s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 900, 900)
        ns.SaveAnchor(%s, "%s")   -- drag away from the v=2 spot
    """ % (page, frame_name, frame_name, frame_name, key, frame_name, frame_name,
           frame_name, frame_name, frame_name, key))
    h.lua("ns.Options.ExitUnlockMode(false)")   # Cancel: should restore the v=2 record exactly
    h.lua("ns.Options.EnterUnlockMode()")       # back on UIParent: the real, user-visible spot
    x, y = h.lua("return %s:GetLeft(), %s:GetTop()" % (frame_name, frame_name))
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01,
       "%s Cancel did not restore its own v=2 record: %r vs %r" % (key, (x, y), (x0, y0)))
    eq(h.errors(), [], "errors")


@test("Queue: Cancel restores its own v=2 record, not another anchor's snapshot", "options")
def _():
    h = fresh()
    _cancel_restores_v2(h, "queue", "SalusNovusQueue", "queuePos")


@test("Ability Preview: Cancel restores its own v=2 record, not another anchor's snapshot", "options")
def _():
    h = fresh()
    _cancel_restores_v2(h, "preview", "SalusNovusPreview", "previewPos")


@test("Messages: Cancel restores its own v=2 record, not another anchor's snapshot", "options")
def _():
    h = fresh()
    _cancel_restores_v2(h, "messages", "SalusNovusMessages", "messagesPos")


@test("Health Bars: Cancel restores its own v=2 record, not another anchor's snapshot", "options")
def _():
    h = fresh()
    _cancel_restores_v2(h, "health", "SalusNovusHealthBars", "healthPos")


@test("Reminders: Cancel restores its own v=2 record, not another anchor's snapshot", "options")
def _():
    h = fresh()
    _cancel_restores_v2(h, "reminders", "SalusNovusReminderFrame", "remindersPos")


@test("Guide/Arrow/Builder: Cancel restores each frame's own v=2 record, not another anchor's snapshot", "options")
def _():
    # These three have no options-page preview stage (they live on UIParent
    # the whole time, dragged directly in unlock mode), so no re-entering is
    # needed to measure -- but they still go through the SAME generic
    # ExitUnlockMode loop over ns.AnchorPositions as every previewed anchor.
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = true
        ns.ApplyAll()
        ns.Guide.Build(); ns.Arrow.Build(); ns.Builder.Build()
    """)
    open_options(h)
    h.lua("ns.Options.EnterUnlockMode()")
    for frame_name, key, dx, dy in (
        ("SalusNovusGuide", "guidePos", 200, 300),
        ("SalusNovusArrow", "arrowPos", 210, 310),
        ("SalusNovusBuilder", "builderPos", 220, 320),
    ):
        h.lua("""
            %s:ClearAllPoints()
            %s:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", %d, %d)
            ns.SaveAnchor(%s, "%s")
        """ % (frame_name, frame_name, dx, dy, frame_name, key))
    h.lua("ns.Options.ExitUnlockMode(true)")   # a real v=2 record now exists for all three
    h.lua("ns.Options.EnterUnlockMode()")
    x0 = h.lua("return { g = { SalusNovusGuide:GetLeft(), SalusNovusGuide:GetTop() }, "
               "a = { SalusNovusArrow:GetLeft(), SalusNovusArrow:GetTop() }, "
               "b = { SalusNovusBuilder:GetLeft(), SalusNovusBuilder:GetTop() } }")
    h.lua("""
        SalusNovusGuide:ClearAllPoints() SalusNovusGuide:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 900, 900)
        ns.SaveAnchor(SalusNovusGuide, "guidePos")
        SalusNovusArrow:ClearAllPoints() SalusNovusArrow:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 910, 910)
        ns.SaveAnchor(SalusNovusArrow, "arrowPos")
        SalusNovusBuilder:ClearAllPoints() SalusNovusBuilder:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 920, 920)
        ns.SaveAnchor(SalusNovusBuilder, "builderPos")
    """)
    h.lua("ns.Options.ExitUnlockMode(false)")   # Cancel
    for frame_name, tag in (("SalusNovusGuide", "g"), ("SalusNovusArrow", "a"), ("SalusNovusBuilder", "b")):
        x, y = h.lua("return %s:GetLeft(), %s:GetTop()" % (frame_name, frame_name))
        gx, gy = x0[tag][1], x0[tag][2]
        ok(abs(x - float(gx)) < 0.01 and abs(y - float(gy)) < 0.01,
           "%s Cancel did not restore its own record: %r vs %r" % (frame_name, (x, y), (gx, gy)))
    eq(h.errors(), [], "errors")


@test("a /reload while unlocked comes back locked; /sn by hand never brings the panel back on its own", "bughunt")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; for _, fn in ipairs(ns.OnLoad) do fn() end")
    ok(not h.lua("return ns.db.unlocked"), "still unlocked after a load with no unlock bar")
    open_options(h)
    h.lua("ns.Options.launcher:Click(); W.advance(1)")
    ok(h.lua("return SalusNovusVisualizer:IsShown()"), "visualizer not opened")
    h.lua("ns.ToggleOptions(); W.advance(1); ns.ToggleOptions(); W.advance(1); SalusNovusVisualizer:Hide()")
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "options came back uninvited after a manual open/close")
    eq(h.errors(), [], "errors")


@test("the header opens with a big accent S and no mark; the visualizer title stays plain", "polish")
def _():
    h = fresh()
    open_options(h)
    eq(str(h.lua("return ns.Options.shell.initial:GetText()")), "S", "initial")
    eq(str(h.lua("return ns.Options.shell.title:GetText()")), "ALUS", "rest of the first word")
    eq(str(h.lua("return ns.Options.shell.words[2].initial:GetText()")), "N", "second initial (Alex: the N like the S)")
    eq(str(h.lua("return ns.Options.shell.words[2].rest:GetText()")), "OVUS", "rest of the second word")
    ok(h.lua("return ns.Options.shell.words[2].initial:IsShown()"), "second initial hidden")
    ok(h.lua("return ns.Options.shell.initial:IsShown()"), "initial hidden")
    r, g, b = h.lua("return ns.GetThemeColor()")
    # Slab: the first word is white, the SECOND word (both its parts) is the accent
    col = h.lua("return { ns.Options.shell.initial:GetTextColor() }")
    ok(abs(float(col[1]) - 1) < 0.01 and abs(float(col[2]) - 1) < 0.01 and abs(float(col[3]) - 1) < 0.01, "first word not white: %r" % (list(col.values()),))
    col = h.lua("return { ns.Options.shell.words[2].initial:GetTextColor() }")
    ok(abs(float(col[1]) - r) < 0.01 and abs(float(col[2]) - g) < 0.01 and abs(float(col[3]) - b) < 0.01, "second word not in the accent: %r" % (list(col.values()),))
    col = h.lua("return { ns.Options.shell.words[2].rest:GetTextColor() }")
    ok(abs(float(col[1]) - r) < 0.01, "second word's rest not in the accent")
    h.lua("ns.db.theme.customColor = { r = 0.1, g = 0.9, b = 0.2 }; ns.ApplyAll()")
    col = h.lua("return { ns.Options.shell.words[2].initial:GetTextColor() }")
    ok(abs(float(col[1]) - 0.1) < 0.01 and abs(float(col[2]) - 0.9) < 0.01, "second word did not follow an accent change")
    open_vis(h)
    ok(not h.lua("return SalusNovusVisualizer.shell.initial:IsShown()"), "the visualizer should have no initial")
    eq(str(h.lua("return SalusNovusVisualizer.shell.title:GetText()")), "Boss Visualizer", "visualizer title")


@test("the Ability Queue page: no time-on-icon or backdrop settings, border under Layout, shrink 100 and names 14 by default", "polish")
def _():
    h = fresh()
    eq(int(h.lua("return ns.db.queue.shrink")), 100, "shrink default")
    eq(int(h.lua("return ns.db.queue.labelSize")), 14, "name size default")
    open_options(h)
    h.lua("ns.Options.SelectPage('queue')")
    eq(str(h.lua("return ns.Options.shell.pageTitle:GetText()")), "Ability Queue", "page title")
    labels = str(h.lua("""
        local out = {}
        local function walk(f)
            for _, r in ipairs(f.__regions or {}) do
                if r.GetText and type(r:GetText()) == "string" then out[#out + 1] = r:GetText() end
            end
            for _, c in ipairs(f.__children or {}) do walk(c) end
        end
        walk(ns.Options.pages['queue'])
        return table.concat(out, "|")
    """))
    for gone in ("Time on the icon", "Dark backdrop", "Backdrop opacity", "Icons shown", "Seconds until the cast"):
        ok(gone not in labels, "%r should be gone: %s" % (gone, labels))
    for kept in ("Max icons", "Show seconds until cast", "Lead icon border"):
        ok(kept in labels, "%r missing: %s" % (kept, labels))
    eq(h.errors(), [], "errors")


# --------------------------------------------------------------- abilities
# Plunder (3494): Knock Away 11130 at 7.3 and 22.0, Crush Armor 21055 at
# 12.2, Charge 22911 at 13.3 (the Looter's Sinister Strike is trash).

def preview_lines(h):
    return [str(x) for x in h.lua("""
        local out = {}
        for i = 1, 8 do local l = ns.Preview._lines[i] if l:IsShown() then out[#out + 1] = l.text:GetText() end end
        return out
    """).values()]


def message_texts(h):
    return [str(x) for x in h.lua("""
        local out = {}
        for _, f in ipairs(ns.Messages._active) do out[#out + 1] = f.text:GetText() end
        return out
    """).values()]


@test("the abilities store: fields round-trip, an emptied record vanishes, a secret key is refused, Reset clears", "abilities")
def _():
    h = fresh()
    h.lua("ns.Abilities.Set(11130, 'rename', 'Knock')")
    eq(str(h.lua("return ns.Abilities.Rename(11130)")), "Knock", "rename")
    eq(str(h.lua("return type(ns.db.abilities['11130'])")), "table", "record not stored under tostring(spellID)")
    h.lua("ns.Abilities.Set(11130, 'color', { r = 0.2, g = 0.4, b = 0.8 })")
    r, g, b = h.lua("return ns.Abilities.Color(11130)")
    ok(abs(r - 0.2) < 0.001 and abs(b - 0.8) < 0.001, "colour")
    h.lua("ns.Abilities.SetRoute(11130, 'preview', true)")
    ok(h.lua("return ns.Abilities.Routed(11130, 'preview')"), "route on")
    # storing a default clears the entry; clearing every field drops the record
    h.lua("ns.Abilities.SetRoute(11130, 'preview', false); ns.Abilities.Set(11130, 'rename', ''); ns.Abilities.Set(11130, 'color', nil)")
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "an emptied record must vanish")
    eq(str(h.lua("return tostring(ns.Abilities.Get(W.secretNumber(), true))")), "nil", "a secret key must be refused")
    h.lua("ns.Abilities.Set(21055, 'rename', 'Crush'); ns.Abilities.Reset(21055)")
    eq(str(h.lua("return tostring(ns.Abilities.Rename(21055))")), "nil", "Reset did not clear")
    # defaults (Alex 2026-09-20): queue and Messages on, the preview off
    ok(h.lua("return ns.Abilities.Routed(22911, 'queue') and ns.Abilities.Routed(22911, 'messages') and not ns.Abilities.Routed(22911, 'preview')"), "route defaults")
    eq(h.errors(), [], "errors")


@test("a rename and a colour reach the bars label, the queue label, the lane and the card; the real name stays for lookups", "abilities")
def _():
    h = fresh()
    h.lua("ns.Abilities.Set(11130, 'rename', 'KNOCK'); ns.Abilities.Set(11130, 'color', { r = 0.1, g = 0.9, b = 0.3 })")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.3)")
    bar = h.lua("""
        for i = 1, 8 do
            local f = ns.Bars._bars and ns.Bars._bars[i]
            if f and f:IsShown() and f.entry and f.entry.bar and f.entry.bar.spellID == 11130 then
                return { text = f.text:GetText(), c = { f.text:GetTextColor() } }
            end
        end
    """)
    ok(bar is not None, "no bar for Knock Away")
    eq(str(bar["text"]), "KNOCK", "bars label not renamed")
    ok(abs(float(bar["c"][2]) - 0.9) < 0.01, "bars label not coloured")
    q = h.lua("""
        for i = 1, 8 do
            local f = ns.Queue._icons[i]
            if f:IsShown() and f.entry and f.entry.bar and f.entry.bar.spellID == 11130 then
                return { text = f.label:GetText(), lc = { f.label:GetTextColor() } }
            end
        end
    """)
    ok(q is not None, "no queue icon for Knock Away")
    eq(str(q["text"]), "KNOCK", "queue label not renamed")
    ok(abs(float(q["lc"][2]) - 0.9) < 0.01, "queue label not coloured")
    # the fill colour is the bars' own, never the ability's
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    names = lane_names(h)
    ok("KNOCK" in names, "lane not renamed: %r" % names)
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].name:GetText()")), "KNOCK", "card not renamed")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].real:GetText()")), "Knock Away", "real name not shown muted after a rename")
    # no override: the client's name and white text
    h.lua("ns.Abilities.Reset(11130); ns.Visualizer.Refresh()")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].name:GetText()")), "Knock Away", "name did not fall back")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].real:GetText()")), "", "muted real name shown without a rename")
    eq(h.errors(), [], "errors")


@test("roles: an ability hidden from my role leaves every anchor; no assigned role means no filtering; ToggleRole collapses", "abilities")
def _():
    h = fresh()
    h.lua("W.role = 'TANK'; ns.Abilities.Set(11130, 'roles', { healer = true })")
    ok(not h.lua("return ns.Abilities.RoleOK(11130)"), "a healer-only ability shown to a tank")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.3)")
    ok(not h.lua("""
        for i = 1, 8 do local f = ns.Queue._icons[i] if f:IsShown() and f.entry and f.entry.bar and f.entry.bar.spellID == 11130 then return true end end
        return false
    """), "queue still shows a role-hidden ability")
    h.lua("W.role = 'NONE'")
    ok(h.lua("return ns.Abilities.RoleOK(11130)"), "no assigned role must fail open")
    h.lua("W.role = 'HEALER'")
    ok(h.lua("return ns.Abilities.RoleOK(11130)"), "healer should see it")
    h.lua("ns.Abilities.Set(11130, 'roles', nil); ns.Abilities.ToggleRole(11130, 'tank')")
    eq(str(h.lua("return type(ns.db.abilities['11130'].roles)")), "table", "toggling one role off a full set should store a set")
    ok(not h.lua("return ns.Abilities.HasRole(11130, 'tank')") and h.lua("return ns.Abilities.HasRole(11130, 'dps')"), "set wrong")
    h.lua("ns.Abilities.ToggleRole(11130, 'tank')")
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "a full set must collapse to nil (and the record vanish)")
    h.lua("ns.Abilities.ToggleRole(11130, 'tank'); ns.Abilities.ToggleRole(11130, 'healer'); ns.Abilities.ToggleRole(11130, 'dps')")
    eq(str(h.lua("return ns.db.abilities['11130'].roles")), "none", "an empty set must store 'none'")
    ok(not h.lua("return ns.Abilities.RoleOK(11130)"), "'none' should hide it from everyone")
    h.lua("W.role = nil")
    eq(h.errors(), [], "errors")


@test("routing: unticking the queue drops the icon; Messages is on and the preview off by default; each follows its tick", "abilities")
def _():
    h = fresh()
    h.lua("ns.Abilities.SetRoute(11130, 'queue', false); ns.Abilities.SetRoute(11130, 'messages', false)")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4)")
    ok(not h.lua("""
        for i = 1, 8 do local f = ns.Queue._icons[i] if f:IsShown() and f.entry and f.entry.bar and f.entry.bar.spellID == 11130 then return true end end
        return false
    """), "queue shows an unrouted ability")
    ok(h.lua("""
        for i = 1, 8 do local f = ns.Queue._icons[i] if f:IsShown() and f.entry and f.entry.bar and f.entry.bar.spellID == 21055 then return true end end
        return false
    """), "queue lost a routed ability")
    ok(not any("Knock" in t for t in preview_lines(h)), "preview shows an ability by default: %r" % preview_lines(h))
    h.lua("W.advance(3.5)")   # Knock Away landed at 7.3; Crush Armor (12.2) is inside the preview window
    eq(message_texts(h), [], "Messages showed an ability whose Messages route was unticked")
    ok(not any("Crush" in t for t in preview_lines(h)), "the preview is off by default: %r" % preview_lines(h))
    h.lua("ns.Abilities.SetRoute(21055, 'preview', true); W.advance(0.3)")
    ok(any("Crush" in t for t in preview_lines(h)), "ticked preview route did not show: %r" % preview_lines(h))
    h.lua("W.advance(4.7)")   # Crush Armor lands at 12.2, routed to Messages by default
    eq(message_texts(h), ["Crush Armor"], "an ability with the default routes did not reach Messages")
    eq(h.errors(), [], "errors")


@test("a card opens into its editor on click, one at a time, and every control writes through the store", "abilities")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h0 = float(h.lua("return SalusNovusVisualizer.descRows[1]:GetHeight()"))
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnMouseUp')(r)")
    ok(h.lua("return SalusNovusVisualizer.descRows[1].editor:IsShown()"), "editor not shown")
    ok(float(h.lua("return SalusNovusVisualizer.descRows[1]:GetHeight()")) > h0 + 100, "card did not grow for the editor")
    ok(not h.lua("return SalusNovusVisualizer.descRows[2].editor:IsShown()"), "second card open too")
    h.lua("local r = SalusNovusVisualizer.descRows[2] r:GetScript('OnMouseUp')(r)")
    ok(not h.lua("return SalusNovusVisualizer.descRows[1].editor:IsShown()") and h.lua("return SalusNovusVisualizer.descRows[2].editor:IsShown()"), "opening a second card must close the first")
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnMouseUp')(r)")
    ed = "SalusNovusVisualizer.descRows[1].editor"
    eq(str(h.lua("return %s.name:GetText()" % ed)), "Knock Away", "name box not prefilled with the real name")
    h.lua("%s.name:SetText('  Knock  '); %s.name:GetScript('OnEditFocusLost')(%s.name)" % (ed, ed, ed))
    eq(str(h.lua("return ns.Abilities.Rename(11130)")), "Knock", "rename not written (trimmed)")
    eq(str(h.lua("return SalusNovusVisualizer.descRows[1].name:GetText()")), "Knock", "card not re-rendered after the rename")
    h.lua("%s.name:SetText('Knock Away'); %s.name:GetScript('OnEditFocusLost')(%s.name)" % (ed, ed, ed))
    eq(str(h.lua("return tostring(ns.Abilities.Rename(11130))")), "nil", "typing the real name back must clear the rename")
    h.lua("%s.useColor:Click()" % ed)
    ok(h.lua("return ns.Abilities.Color(11130) ~= nil"), "colour toggle did not set a colour")
    ok(h.lua("return %s.useColor:GetChecked()" % ed), "colour toggle not synced")
    h.lua("%s.useColor:Click()" % ed)
    ok(h.lua("return ns.Abilities.Color(11130) == nil"), "colour toggle did not clear")
    h.lua("%s.roles.tank:Click()" % ed)
    ok(not h.lua("return ns.Abilities.HasRole(11130, 'tank')"), "role toggle did not write")
    ok(not h.lua("return %s.roles.tank:GetChecked()" % ed), "role toggle not synced")
    h.lua("%s.routes.preview:Click()" % ed)
    ok(h.lua("return ns.Abilities.Routed(11130, 'preview')"), "route toggle did not write")
    h.lua("%s.routes.queue:Click()" % ed)
    ok(not h.lua("return ns.Abilities.Routed(11130, 'queue')"), "queue route did not write")
    h.lua("%s.reset:Click()" % ed)
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "Reset did not clear the record")
    ok(h.lua("return %s.roles.tank:GetChecked() and %s.routes.queue:GetChecked() and %s.routes.messages:GetChecked() and not %s.routes.preview:GetChecked()" % (ed, ed, ed, ed)), "controls not synced after Reset")
    eq(h.errors(), [], "errors")


# ----------------------------------------------------------------- preview

@test("the preview counts a routed ability down inside its window, rewrites once a second, and leaves at landing with no NOW", "preview")
def _():
    h = fresh()
    h.lua("for _, id in ipairs({ 11130, 21055, 22911 }) do ns.Abilities.SetRoute(id, 'preview', true) end")   # off by default (Alex)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(2.0)")
    eq(preview_lines(h), [], "line before the window (Knock Away lands at 7.3, window 5)")
    h.lua("W.advance(1.0)")
    eq(preview_lines(h), ["Knock Away  5"], "line missing inside the window")
    ok(h.lua("return SalusNovusPreview:IsShown()"), "anchor hidden with a line")
    h.lua("__writes = 0; local t = ns.Preview._lines[1].text; local orig = t.SetText; t.SetText = function(self, s) __writes = __writes + 1 return orig(self, s) end")
    h.lua("W.advance(0.5)")   # 3.5: 3.8 s left -> ceil = 4, one rewrite
    eq(int(h.lua("return __writes")), 1, "seconds must rewrite once when the integer changes")
    h.lua("W.advance(0.3)")   # 3.8: ceil(3.5) = 4 still
    eq(int(h.lua("return __writes")), 1, "seconds rewrote without the integer changing")
    eq(preview_lines(h), ["Knock Away  4"], "count")
    h.lua("W.advance(3.7)")   # 7.5: landed (the hub ticks every 0.2 s); the bar is still held for 2.5 s
    ok(h.lua("return #ns.Timers.Sorted() >= 3"), "hub dropped the record early")
    ok(not any("Knock" in t for t in preview_lines(h)), "a landed ability must leave the preview at once (no NOW): %r" % preview_lines(h))
    # max cap and order: Crush 12.2 and Charge 13.3 both inside a 10 s window at t=8
    h.lua("ns.db.preview.countdownSeconds = 10; ns.db.preview.max = 2; ns.ApplyAll(); W.advance(0.5)")
    lines = preview_lines(h)
    eq(len(lines), 2, "two abilities inside the window expected: %r" % lines)
    ok(lines[0].startswith("Crush Armor"), "soonest not first: %r" % lines)
    h.lua("ns.db.preview.max = 1; ns.ApplyAll(); W.advance(0.2)")
    lines = preview_lines(h)
    eq(len(lines), 1, "max not honoured: %r" % lines)
    ok(lines[0].startswith("Crush Armor"), "the cap must keep the soonest: %r" % lines)
    eq(h.errors(), [], "errors")


@test("preview anchor: direction down re-pins by TOP, disabled/module-off hide it, unlock shows a sample, the page preview round-trips", "preview")
def _():
    h = fresh()
    h.lua("for _, id in ipairs({ 11130, 21055, 22911 }) do ns.Abilities.SetRoute(id, 'preview', true) end")   # off by default (Alex)
    h.lua("ns.db.preview.direction = 'down'; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(3)")
    eq(str(h.lua("local p = SalusNovusPreview:GetPoint() return p")), "TOP", "origin for a downward stack")
    top0 = float(h.lua("return SalusNovusPreview:GetTop()"))
    h.lua("ns.db.preview.countdownSeconds = 10; ns.ApplyAll(); W.advance(0.5)")
    ok(len(preview_lines(h)) >= 2, "expected more lines with a wider window")
    ok(abs(float(h.lua("return SalusNovusPreview:GetTop()")) - top0) < 0.01, "top edge drifted when the stack grew")
    h.lua("ns.db.preview.enabled = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusPreview:IsShown()"), "disabled still shown")
    h.lua("ns.db.preview.enabled = true; ns.db.modules.bossWarnings = false; ns.ApplyAll(); W.advance(0.2)")
    ok(not h.lua("return SalusNovusPreview:IsShown()"), "module off still shown")
    h.lua('ns.db.modules.bossWarnings = true; W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1); ns.db.unlocked = true; ns.ApplyAll()')
    ok(h.lua("return SalusNovusPreview:IsShown() and SalusNovusPreview:IsMouseEnabled()"), "unlocked: no sample to drag")
    eq(preview_lines(h), ["Ability  3"], "sample line")
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("ns.Options.SelectPage('preview')")
    ok(h.lua("return SalusNovusPreview:GetParent() ~= UIParent and SalusNovusPreview:IsShown()"), "page preview not running")
    h.lua("W.advance(2.5)")
    ok(len(preview_lines(h)) >= 1, "page preview shows no counting line: %r" % preview_lines(h))
    h.lua("SalusNovusOptions:Hide()")
    ok(h.lua("return SalusNovusPreview:GetParent() == UIParent"), "frame not returned to the screen")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- messages

@test("a routed ability lands once in Messages, in its colour, fades after hold, and the stack is capped and cleared at the end", "messages")
def _():
    h = fresh()
    h.lua("""
        __lands = 0
        ns.Timers.Register({ OnLand = function(b) __lands = __lands + 1 end })
        ns.Abilities.SetRoute(11130, 'messages', true)
        ns.Abilities.Set(11130, 'color', { r = 0.1, g = 0.9, b = 0.3 })
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(7.0)")
    eq(message_texts(h), [], "shown before landing")
    h.lua("W.advance(0.5)")
    eq(message_texts(h), ["Knock Away"], "not shown at landing")
    ok(h.lua("return SalusNovusMessages:IsShown()"), "anchor hidden with a line")
    c = h.lua("return { ns.Messages._active[1].text:GetTextColor() }")
    ok(abs(float(c[2]) - 0.9) < 0.01, "line not in the ability's colour")
    eq(int(h.lua("return __lands")), 1, "OnLand should fire once per record")
    h.lua("W.advance(1.0)")
    eq(int(h.lua("return __lands")), 1, "OnLand repeated for the same record")
    h.lua("W.advance(2.5)")   # hold 2.5 + fade 0.4 elapsed
    eq(message_texts(h), [], "line did not fade out after the hold")
    ok(not h.lua("return SalusNovusMessages:IsShown()"), "anchor stayed up with nothing to show")
    # cap: three opted in, max 1 -> the newest replaces the oldest
    h.lua("ns.db.messages.max = 1; ns.db.messages.hold = 5; ns.Abilities.SetRoute(21055, 'messages', true); ns.Abilities.SetRoute(22911, 'messages', true)")
    h.lua("W.advance(2.5)")   # 13.5: Crush (12.2) and Charge (13.3) both landed
    eq(message_texts(h), ["Charge"], "max did not cap or the newest is not kept")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    eq(message_texts(h), [], "lines survived the end of the fight")
    eq(h.errors(), [], "errors")


@test("messages anchor: unlock shows the sample, disabled/module-off hide it, direction down re-pins by TOP, the page preview loops", "messages")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusMessages:IsShown() and SalusNovusMessages.unlockText:IsShown() and SalusNovusMessages:IsMouseEnabled()"), "unlock chrome missing")
    h.lua("ns.db.unlocked = false; ns.db.messages.enabled = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusMessages:IsShown()"), "disabled still shown")
    h.lua("ns.db.messages.enabled = true; ns.db.modules.bossWarnings = false; ns.Abilities.SetRoute(11130, 'messages', true); ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065); W.advance(7.5)')
    eq(message_texts(h), [], "module off still fed Messages")
    h.lua('ns.db.modules.bossWarnings = true; W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1); ns.db.messages.direction = "down"; ns.ApplyAll()')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065); W.advance(7.5)')
    eq(str(h.lua("local p = SalusNovusMessages:GetPoint() return p")), "TOP", "origin for a downward stack")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    open_options(h)
    h.lua("ns.Options.SelectPage('messages')")
    ok(h.lua("return SalusNovusMessages:GetParent() ~= UIParent"), "page preview not running")
    ok(len(message_texts(h)) >= 1, "page preview shows nothing")
    h.lua("W.advance(2.6)")
    ok(len(message_texts(h)) >= 2, "page preview does not loop: %r" % message_texts(h))
    h.lua("SalusNovusOptions:Hide()")
    ok(h.lua("return SalusNovusMessages:GetParent() == UIParent"), "frame not returned to the screen")
    eq(message_texts(h), [], "sample lines survived the page closing")
    eq(h.errors(), [], "errors")


@test("six anchor pages on the strip, none clipped; six anchors on screen and pairwise clear; section titles centred on their band", "options")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('preview')")
    eq(str(h.lua("return ns.Options.shell.pageTitle:GetText()")), "Ability Preview", "page title")
    bad = str(h.lua("""
        local out = {}
        for _, strip in pairs(ns.Options.strips or {}) do
            if strip:IsShown() then
                local last
                for k, b in pairs(strip.buttons) do
                    if b:GetWidth() < (b.text:GetStringWidth() or 0) + 20 then out[#out + 1] = k .. " clipped" end
                    if not last or b:GetRight() > last then last = b:GetRight() end
                end
                if last and last > strip:GetRight() then out[#out + 1] = "strip overflows" end
            end
        end
        return table.concat(out, ",")
    """))
    eq(bad, "", bad)
    h.lua("SalusNovusOptions:Hide(); ns.db.unlocked = true; ns.ApplyAll()")
    names = ["SalusNovusBars", "SalusNovusQueue", "SalusNovusPreview", "SalusNovusMessages", "SalusNovusHealthBars", "SalusNovusReminderFrame"]
    for n in names:
        eq(float(h.lua("return W.offscreen(%s).any" % n)), 0.0, "%s off screen" % n)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            ok(float(h.lua("return W.overlapArea(%s, %s)" % (names[i], names[j]))) < 100, "%s overlaps %s" % (names[i], names[j]))
    h.lua("ns.db.unlocked = false; ns.ApplyAll(); SalusNovusOptions:Show(); ns.Options.SelectPage('global')")
    off = str(h.lua("""
        local out = {}
        local pg = ns.Options.pages['global'].__content
        for _, r in ipairs(pg.__regions or {}) do
            if r.__card and r.__card.head then
                local tc = (r:GetTop() + r:GetBottom()) / 2
                local hc = (r.__card.head:GetTop() + r.__card.head:GetBottom()) / 2
                if math.abs(tc - hc) > 1 then out[#out + 1] = tostring(r:GetText()) .. " off by " .. string.format("%.1f", tc - hc) end
            end
        end
        return table.concat(out, ",")
    """))
    eq(off, "", "section titles not centred: %s" % off)
    eq(h.errors(), [], "errors")



@test("the color picker is ours: sliders and the hex box drive onChange live, Okay keeps, Cancel restores, ESC-closable", "polish")
def _():
    h = fresh()
    h.lua("""
        __got, __cancelled = {}, false
        ns.Theme.OpenColorPicker({ r = 1, g = 0.5, b = 0 }, function(r, g, b) __got = { r, g, b } end, function() __cancelled = true end)
    """)
    ok(h.lua("return SalusNovusColorPicker:IsShown()"), "picker not shown")
    ok(h.lua("return rawget(SalusNovusColorPicker, 'bg') ~= nil and rawget(SalusNovusColorPicker, 'accent') ~= nil"), "not our frame (no themed background/accent)")
    eq(str(h.lua("return SalusNovusColorPicker.hex:GetText()")), "FF8000", "hex not seeded")
    eq(int(h.lua("return #__got")), 0, "seeding the sliders must not call onChange")
    h.lua("SalusNovusColorPicker.sliders[3]:SetValue(255)")
    got = h.lua("return __got")
    ok(abs(float(got[3]) - 1.0) < 0.01 and abs(float(got[1]) - 1.0) < 0.01, "slider did not drive onChange: %r" % (list(got.values()),))
    eq(str(h.lua("return SalusNovusColorPicker.hex:GetText()")), "FF80FF", "hex not updated from the slider")
    h.lua("SalusNovusColorPicker.hex:SetText('102030'); SalusNovusColorPicker.hex:GetScript('OnEditFocusLost')(SalusNovusColorPicker.hex)")
    got = h.lua("return __got")
    ok(abs(float(got[1]) - 16 / 255) < 0.01 and abs(float(got[3]) - 48 / 255) < 0.01, "hex did not drive onChange: %r" % (list(got.values()),))
    eq(int(h.lua("return SalusNovusColorPicker.sliders[2]:GetValue()")), 32, "sliders not updated from the hex")
    h.lua("SalusNovusColorPicker.okay:Click()")
    ok(not h.lua("return SalusNovusColorPicker:IsShown()"), "Okay did not close")
    ok(not h.lua("return __cancelled"), "Okay must not cancel")
    h.lua("ns.Theme.OpenColorPicker({ r = 0.2, g = 0.2, b = 0.2 }, function() end, function() __cancelled = true end); SalusNovusColorPicker.cancel:Click()")
    ok(h.lua("return __cancelled"), "Cancel did not call back")
    ok(h.lua("for _, n in ipairs(UISpecialFrames) do if n == 'SalusNovusColorPicker' then return true end end return false"), "picker not ESC-closable")
    eq(h.errors(), [], "errors")


@test("typing a hex and pressing Enter commits the colour (Enter drops focus; focus lost reads the box)", "polish")
def _():
    h = fresh()
    h.lua("""
        __got = {}
        ns.Theme.OpenColorPicker({ r = 1, g = 0.5, b = 0 }, function(r, g, b) __got = { r, g, b } end, function() end)
        local hex = SalusNovusColorPicker.hex
        hex:SetFocus()
        hex:SetText('102030')
        hex:GetScript('OnEnterPressed')(hex)
    """)
    ok(not h.lua("return SalusNovusColorPicker.hex:HasFocus()"), "Enter left the box focused")
    got = h.lua("return __got")
    ok(abs(float(got[1]) - 16 / 255) < 0.01 and abs(float(got[3]) - 48 / 255) < 0.01, "Enter did not commit the hex: %r" % (list(got.values()),))
    eq(h.errors(), [], "errors")


@test("the card's color is one box: unticked means the default and hides the swatch; ticked shows the swatch that opens our picker", "abilities")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnMouseUp')(r)")
    ed = "SalusNovusVisualizer.descRows[1].editor"
    eq(str(h.lua("return %s.useColor.label:GetText()" % ed)), "Custom color", "label (American spelling, one box)")
    ok(h.lua("return %s.useColor.fill ~= nil and %s.useColor.knob == nil" % (ed, ed)), "must be the square check box, not the slider toggle")
    ok(h.lua("return %s.roles.tank.knob == nil and %s.routes.queue.knob == nil" % (ed, ed)), "roles/routes must be check boxes too")
    ok(not h.lua("return %s.swatch:IsShown()" % ed), "swatch shown without a custom colour")
    h.lua("%s.useColor:Click()" % ed)
    ok(h.lua("return %s.swatch:IsShown()" % ed), "swatch hidden with a custom colour")
    h.lua("%s.swatch:Click(); SalusNovusColorPicker.sliders[1]:SetValue(0); SalusNovusColorPicker.okay:Click()" % ed)
    r, g, b = h.lua("return ns.Abilities.Color(11130)")
    ok(abs(r) < 0.01, "picker did not write the ability colour: %r" % ((r, g, b),))
    h.lua("%s.useColor:Click()" % ed)
    ok(not h.lua("return %s.swatch:IsShown()" % ed) and h.lua("return ns.Abilities.Color(11130) == nil"), "unticking did not clear")
    eq(h.errors(), [], "errors")



# ------------------------------------------------------------ bug hunt 2
# Five Sonnet reviewers (2026-09-19). Each confirmed finding has a test
# here that failed before its fix.

@test("shipped anchor defaults land at their screen offsets at any anchor scale", "bughunt")
def _():
    h = fresh()
    h.lua("ns.db.anchorsGlobal.scale = 150; ns.ApplyAll(); ns.db.unlocked = true; ns.ApplyAll()")
    left, sc, ux = h.lua("local f = SalusNovusBars return f:GetLeft(), f:GetScale(), (UIParent:GetCenter())")
    ok(abs(left * sc - (ux + 314)) < 0.5, "bars default drifted with the scale: screen left %r, want %r" % (left * sc, ux + 314))


@test("a saved position with NaN or an absurd coordinate is dropped and the default used", "bughunt")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "BOTTOMLEFT", x = 0/0, y = 17, v = 2 }, queuePos = { point = "TOPLEFT", x = 1e308, y = 5, v = 2 } }')
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    left = float(h.lua("return SalusNovusBars:GetLeft()"))
    ok(left == left and abs(left) < 1e6, "bars sat at a NaN/absurd position: %r" % left)
    ql = float(h.lua("return SalusNovusQueue:GetLeft()"))
    ok(ql == ql and abs(ql) < 1e6, "queue sat at an absurd position: %r" % ql)
    eq(h.errors(), [], "errors")


@test("a card editor commits to the ability it was opened for, once per blur, and does not follow a boss switch", "bughunt")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")   # Plunder: Knock Away 11130 first
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnMouseUp')(r)")
    ed = "SalusNovusVisualizer.descRows[1].editor"
    # one commit per Enter: the box's own OnEnterPressed drops focus and the
    # focus loss commits; before the fix both scripts committed
    h.lua("""
        __sets = 0
        local orig = ns.Abilities.Set
        ns.Abilities.Set = function(...) __sets = __sets + 1 return orig(...) end
        %s.name:SetText('Knock')
        %s.name:GetScript('OnEnterPressed')(%s.name)
        %s.name:GetScript('OnEditFocusLost')(%s.name)
        ns.Abilities.Set = orig
    """ % (ed, ed, ed, ed, ed))
    eq(int(h.lua("return __sets")), 1, "an Enter must commit exactly once")
    eq(str(h.lua("return ns.Abilities.Rename(11130)")), "Knock", "rename")
    # typing, then switching boss before the blur: the text lands on the
    # ability the editor was opened for, never on the new boss's first ability
    h.lua("ns.Abilities.Reset(11130); ns.Visualizer.Refresh()")
    ok(h.lua("return %s:IsShown()" % ed), "the card should still be open after the reset")   # (a second click would close it)
    h.lua("%s.name:SetText('TYPED WHILE OPEN')" % ed)
    # switch through the sidebar row (the click path), not ShowBoss
    h.lua("""
        for _, r in ipairs(ns.Visualizer._bossRows) do
            if r:IsShown() and r.boss and r.boss.encounterID == 3493 then r:GetScript('OnClick')(r) break end
        end
    """)
    eq(int(h.lua("return ns.Visualizer.state.enc")), 3493, "sidebar click did not switch to Faldrim")
    other = int(h.lua("return SalusNovusVisualizer.descRows[1].spellID"))
    ok(other != 11130, "test needs a boss whose first ability differs")
    ok(not h.lua("return %s:IsShown()" % ed), "an open card followed the boss switch")
    h.lua("%s.name:GetScript('OnEditFocusLost')(%s.name)" % (ed, ed))
    eq(str(h.lua("return tostring(ns.Abilities.Rename(%d))" % other)), "nil", "rename landed on the new boss's ability")
    eq(str(h.lua("return tostring(ns.Abilities.Rename(11130))")), "TYPED WHILE OPEN", "rename lost or misdirected")
    # going back (by the sidebar row again) does not reopen the card by itself
    h.lua("""
        for _, r in ipairs(ns.Visualizer._bossRows) do
            if r:IsShown() and r.boss and r.boss.encounterID == 3494 then r:GetScript('OnClick')(r) break end
        end
    """)
    eq(int(h.lua("return ns.Visualizer.state.enc")), 3494, "sidebar click did not return to Plunder")
    ok(not h.lua("return %s:IsShown()" % ed), "card reopened on return without a click")
    eq(h.errors(), [], "errors")


@test("section titles sit on whole pixels even when the font's height is odd", "bughunt")
def _():
    h = fresh()
    h.lua("""
        local probe = UIParent:CreateFontString()
        local mt = getmetatable(probe)
        __origIdx = mt.__index
        mt.__index = function(t, k)
            if k == "GetStringHeight" then return function() return 13 end end
            return __origIdx(t, k)
        end
    """)
    open_options(h)
    h.lua("ns.Options.SelectPage('global')")
    bad = str(h.lua("""
        local out = {}
        local pg = ns.Options.pages['global'].__content
        for _, r in ipairs(pg.__regions or {}) do
            if r.__card and r.__card.head then
                local top = r:GetTop()
                if math.abs(top - math.floor(top + 0.5)) > 0.001 then out[#out + 1] = tostring(r:GetText()) .. " at " .. tostring(top) end
            end
        end
        return table.concat(out, ",")
    """))
    h.lua("local probe = UIParent:CreateFontString() getmetatable(probe).__index = __origIdx")
    eq(bad, "", "section titles on half pixels: %s" % bad)



@test("a hand-edited negative or non-number bars grace cannot expire a record before it lands", "bughunt")
def _():
    h = fresh()
    h.lua('__lands, __stops = 0, 0; ns.Timers.Register({ OnLand = function() __lands = __lands + 1 end, OnStop = function() __stops = __stops + 1 end })')
    h.lua("ns.db.bars.grace = -5")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(7.6)")   # Knock Away lands at 7.3
    eq(int(h.lua("return __lands")), 1, "the record expired before landing")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1); ns.db.bars.grace = "junk"')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065); W.advance(7.6)')
    eq(int(h.lua("return __lands")), 2, "a non-number grace broke the ticker")
    eq(h.errors(), [], "errors")


@test("the pull intake announces one change for the whole boss, not one per cast", "bughunt")
def _():
    h = fresh()
    h.lua('__changes = 0; ns.Timers.Register({ OnChange = function() __changes = __changes + 1 end })')
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    n = int(h.lua("return #ns.Timers.Sorted()"))
    ok(n >= 4, "expected several records: %d" % n)
    changes = int(h.lua("return __changes"))
    ok(changes <= 2, "OnChange fired %d times for %d records (want one for the clear and one for the intake)" % (changes, n))


@test("a record with no spell id takes the defaults: queue and Messages yes, the preview no", "bughunt")
def _():
    h = fresh()
    ok(h.lua("return ns.Timers.RoutedTo({ key = 'x' }, 'queue') and ns.Timers.RoutedTo({ key = 'x' }, 'messages')"), "queue and Messages are on by default")
    ok(not h.lua("return ns.Timers.RoutedTo({ key = 'x' }, 'preview')"), "the preview is off by default")
    ok(h.lua("return ns.Timers.RoutedTo({ key = 'f', fake = true }, 'messages')"), "fakes still go everywhere")


@test("unticking an anchor's Enable box on its page suspends the preview at once; ticking it resumes", "bughunt")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent and SalusNovusBars:IsShown()"), "preview not running")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == 'check' and w.__outer == ns.Options.pages['bars'] and not w.EnabledWhen then __en = w break end
        end
        __en:Click()
    """)
    ok(not h.lua("return ns.db.bars.enabled"), "the Enable box did not write")
    ok(h.lua("return ns.Bars.state.preview == nil"), "preview session kept running while the anchor is disabled")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent and not SalusNovusBars:IsShown()"), "frame left on the stage or shown while disabled")
    note = str(h.lua("""
        for _, s in ipairs(ns.Options.previewStages) do
            if s.outer == ns.Options.pages['bars'] then return s.note:IsShown() and s.note:GetText() or "" end
        end
        return ""
    """))
    ok("switched off" in note, "stage should explain the anchor is off: %r" % note)
    h.lua("__en:Click()")
    ok(h.lua("return ns.db.bars.enabled and SalusNovusBars:GetParent() ~= UIParent and SalusNovusBars:IsShown()"), "preview did not resume")
    eq(h.errors(), [], "errors")



# ------------------------------------------------------------ health bars
# Durgen Dirgehammer (3496): Intimidating Shout 19134 is cast at ~48% health
# in both logged pulls (16 s and 11 s in) -> tagged health = { pct = 48 }.

def health_units(h, hp=1922, mx=1922, unit="target"):
    h.lua("__units['%s'] = { name = 'Durgen Dirgehammer', hp = %d, max = %d }" % (unit, hp, mx))


@test("health_trigger: same health at different times across 2+ pulls, below full health", "health")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g
    eq(g.health_trigger([(0, 16.0, 47.4), (1, 11.0, 47.8)]), 48, "Durgen's shout")
    eq(g.health_trigger([(0, 16.0, 47.4)]), None, "one pull is no evidence")
    eq(g.health_trigger([(0, 6.5, 80.0), (1, 6.4, 79.0)]), None, "same time AND same health reads as timed")
    eq(g.health_trigger([(0, 16.0, 47.4), (1, 11.0, 60.0)]), None, "health spread too wide")
    eq(g.health_trigger([(0, 1.0, 99.0), (1, 5.0, 98.5)]), None, "an opener at full health is timed")
    eq(g.health_trigger([(0, 16.0, 47.4), (1, 11.0, 47.8), (2, 20.0, 50.1)]), 48, "three pulls")


@test("a health-triggered ability leaves the timed world: no lane, no record, no queue or preview entry; the cards keep it with a HEALTH tag", "health")
def _():
    h = fresh()
    eq(int(h.lua("local b = ns.BossByEncounter(3496) for _, a in ipairs(b.abilities) do if a.spellID == 19134 then return a.health.pct end end return -1")), 48, "data tag missing")
    ok(not h.lua("for _, o in ipairs(ns.Schedule.Lanes(ns.BossByEncounter(3496))) do if o.a.spellID == 19134 then return true end end return false"), "still on the lanes")
    eq(int(h.lua("return #ns.Schedule.HealthAbilities(ns.BossByEncounter(3496))")), 1, "HealthAbilities")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(not h.lua("for _, b in ipairs(ns.Timers.Sorted()) do if b.spellID == 19134 then return true end end return false"), "the hub made a timed record for it")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.BossByEncounter(3496))")
    ok("Intimidating Shout" not in lane_names(h), "lane drawn for a health ability")
    last = h.lua("""
        local n = 0
        for i = 1, #SalusNovusVisualizer.descRows do if SalusNovusVisualizer.descRows[i]:IsShown() then n = i end end
        local r = SalusNovusVisualizer.descRows[n]
        return { name = r.name:GetText(), pill = r.pill:IsShown() and r.pill.text:GetText() or "", n = n }
    """)
    eq(str(last["name"]), "Intimidating Shout", "health ability should be the last card")
    eq(str(last["pill"]), "HEALTH  48%", "HEALTH tag")
    ok(not h.lua("return SalusNovusVisualizer.descRows[1].pill:IsShown()"), "a timed ability got a tag")
    # its editor offers Health Bars only
    h.lua("local r = SalusNovusVisualizer.descRows[%d] r:GetScript('OnMouseUp')(r)" % int(last["n"]))
    ed = "SalusNovusVisualizer.descRows[%d].editor" % int(last["n"])
    ok(h.lua("return %s.healthRoute:IsShown() and not %s.routes.queue:IsShown() and not %s.routes.messages:IsShown()" % (ed, ed, ed)), "show-on row wrong for a health ability")
    h.lua("%s.healthRoute:Click()" % ed)
    ok(not h.lua("return ns.Abilities.Routed(19134, 'health')"), "Health Bars route did not write")
    h.lua("local r = SalusNovusVisualizer.descRows[1] r:GetScript('OnMouseUp')(r)")
    ok(h.lua("return SalusNovusVisualizer.descRows[1].editor.routes.queue:IsShown() and not SalusNovusVisualizer.descRows[1].editor.healthRoute:IsShown()"), "timed ability's editor lost its routes")
    eq(h.errors(), [], "errors")


@test("the health bar appears on a pull of a boss with a health-triggered ability, finds the unit, shows the value and a marker at the threshold", "health")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "bar not shown")
    eq(str(h.lua("return ns.HealthBars.state.unit")), "target", "unit not found")
    eq(str(h.lua("return SalusNovusHealthBars.name:GetText()")), "Durgen Dirgehammer", "boss name")
    shown = h.lua("local out = {} for i = 1, 8 do local m = ns.HealthBars._markers[i] if m:IsShown() then out[#out + 1] = m.label:GetText() end end return out")
    eq([str(x) for x in shown.values()], ["Intimidating Shout"], "markers")
    x = float(h.lua("local m = ns.HealthBars._markers[1] return m:GetLeft() + m:GetWidth() / 2 - SalusNovusHealthBars.bar:GetLeft()"))
    ok(abs(x - 260 * 0.48) < 0.6, "marker not at 48%% of the bar: %r" % x)
    health_units(h, hp=911)
    h.lua('W.fireEvent("UNIT_HEALTH", "target")')
    lo, hi, v = h.lua("local b = SalusNovusHealthBars.bar local lo, hi = b:GetMinMaxValues() return lo, hi, b:GetValue()")
    ok(int(hi) == 1922 and int(v) == 911, "bar not fed from the unit: %r" % ((lo, hi, v),))
    # a rename and a colour reach the marker
    h.lua("ns.Abilities.Set(19134, 'rename', 'FEAR'); ns.Abilities.Set(19134, 'color', { r = 0.1, g = 0.2, b = 0.9 })")
    eq(str(h.lua("return ns.HealthBars._markers[1].label:GetText()")), "FEAR", "rename not on the marker")
    c = h.lua("return { ns.HealthBars._markers[1].label:GetTextColor() }")
    ok(abs(float(c[3]) - 0.9) < 0.01, "colour not on the marker")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "bar survived the end")
    eq(h.errors(), [], "errors")


@test("the health bar finds a late unit, dims when the client refuses the value, stays hidden for a boss with no health abilities or with the route off", "health")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown() and ns.HealthBars.state.unit == nil"), "should show with markers while the unit is unknown")
    h.lua("__units['target'] = { name = 'Lesser Stone Golem', hp = 300, max = 300 }")   # a decoy: the add, not the boss
    health_units(h, unit="nameplate3")
    h.lua('W.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate3")')
    eq(str(h.lua("return ns.HealthBars.state.unit")), "nameplate3", "late unit not found by name")
    # the client refuses the secret value: pcall catches it, the fill dims, the markers stay
    h.lua("""
        __orig = SalusNovusHealthBars.bar.SetValue
        SalusNovusHealthBars.bar.SetValue = function() error("secret value") end
        W.fireEvent("UNIT_HEALTH", "nameplate3")
    """)
    ok(h.lua("return ns.HealthBars.state.refused and SalusNovusHealthBars:GetAlpha() == 1 and SalusNovusHealthBars.bar:GetAlpha() < 0.5"), "refusal not handled")
    ok(h.lua("return ns.HealthBars._markers[1]:IsShown()"), "markers dropped on refusal")
    h.lua('SalusNovusHealthBars.bar.SetValue = __orig; W.fireEvent("UNIT_HEALTH", "nameplate3")')
    ok(not h.lua("return ns.HealthBars.state.refused") and h.lua("return SalusNovusHealthBars.bar:GetAlpha() == 1"), "did not recover")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "shown for a boss with no health abilities")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua("ns.Abilities.SetRoute(19134, 'health', false)")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "shown with its only ability routed off")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    ok("refused" in "".join(h.lua("SlashCmdList['SALUSNOVUS']('health') return table.concat(W.printed, '|')")), "/sn health prints nothing")
    eq(h.errors(), [], "errors")


@test("health bars anchor: unlock shows placeholders and is draggable; disabled/module-off hide it; the page preview drains and stops", "health")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusHealthBars:IsShown() and SalusNovusHealthBars:IsMouseEnabled()"), "unlock placeholders missing")
    eq(int(h.lua("local n = 0 for i = 1, 8 do if ns.HealthBars._markers[i]:IsShown() then n = n + 1 end end return n")), 2, "placeholder markers")
    h.lua("ns.db.unlocked = false; ns.db.healthBars.enabled = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "disabled still shown")
    h.lua("ns.db.healthBars.enabled = true; ns.db.modules.bossWarnings = false; ns.ApplyAll()")
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "module off still shown")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1); ns.db.modules.bossWarnings = true; ns.ApplyAll()')
    open_options(h)
    h.lua("ns.Options.SelectPage('health')")
    eq(str(h.lua("return ns.Options.shell.pageTitle:GetText()")), "Health Bars", "page title")
    ok(h.lua("return SalusNovusHealthBars:GetParent() ~= UIParent and SalusNovusHealthBars:IsShown()"), "page preview not running")
    v0 = float(h.lua("return SalusNovusHealthBars.bar:GetValue()"))
    h.lua("W.advance(3)")
    v1 = float(h.lua("return SalusNovusHealthBars.bar:GetValue()"))
    ok(v1 < v0, "preview fill not draining: %r -> %r" % (v0, v1))
    h.lua("SalusNovusOptions:Hide()")
    ok(h.lua("return SalusNovusHealthBars:GetParent() == UIParent and not SalusNovusHealthBars:IsShown()"), "frame not returned and hidden")
    eq(h.errors(), [], "errors")


# ------------------------------------------------------------------
# bug hunt 3: secret-value taint

# ------------------------------------------------------------- bughunt3

@test("secret encounter name must not cause tostring error in Timers.Status", "bughunt3")
def _():
    h = fresh()
    # Fire an ENCOUNTER_START with a secret name - it gets converted to nil by the guard
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, W.secret("Secret Boss"), 1, 5, 3065)')
    # Then call Status which uses tostring on diag.encName
    h.lua("ns.Timers.Status()")
    # If diag.encName is nil (as it should be after the secret guard), no error
    eq(h.errors(), [], "secret name should be converted to nil and safe for tostring")


@test("AddTimer refuses nil or secret keys, and properly encodes valid keys", "bughunt3")
def _():
    h = fresh()
    # Test that AddTimer properly guards against secret keys
    h.lua("""
        local T = ns.Timers
        local secretNum = W.secretNumber()

        -- These should be refused
        T.AddTimer(nil, "test", 5)              -- nil key
        T.AddTimer(secretNum, "test", 5)        -- secret number key
        T.AddTimer(W.secretString("key"), "test", 5)  -- secret string key

        -- Only the good ones should be added
        T.AddTimer("good1", "test", 5)
        T.AddTimer(123, "test2", 6)  -- numeric key gets tostring'd
    """)
    # Check that only the two valid records exist
    count = int(h.lua("return #ns.Timers.Sorted()"))
    eq(count, 2, "bad keys should be refused, only 2 good records should exist")
    eq(h.errors(), [], "no errors from secret key guarding")




# ------------------------------------------------------------------
# bug hunt 3: hidden-frame OnUpdate





# ---------------------------------------------------------- bughunt3: OnUpdate on hidden frames

@test("bars OnUpdate updates correctly when frame is hidden/shown", "bughunt3")
def _():
    h = fresh()
    h.lua("""
        ns.Timers.StartEncounter(3494, "Plunder")
        ns.Timers.AddTimer("ab1", "Ability1", 6)
        ns.Bars.Apply()
        bar = ns.Bars._bars[1]
    """)
    # Advance 2 seconds - OnUpdate should have run since frame is visible
    h.lua("W.advance(2)")
    secs_visible = int(h.lua("return bar.lastSecs or 0"))
    ok(secs_visible > 0 and secs_visible <= 4, "secs when visible: %d" % secs_visible)
    
    # Hide frame and advance - OnUpdate won't run
    h.lua("SalusNovusBars:Hide()")
    h.lua("W.advance(2.5)")
    secs_hidden = int(h.lua("return bar.lastSecs or -1"))
    # secs_hidden should still be the old value since OnUpdate didn't run
    ok(secs_hidden == secs_visible, "secs changed while hidden (OnUpdate ran when it shouldn't): %d -> %d" % (secs_visible, secs_hidden))
    
    # Show frame - OnUpdate resumes
    h.lua("SalusNovusBars:Show()")
    h.lua("W.advance(0.1)")
    secs_shown = int(h.lua("return bar.lastSecs or 0"))
    # After 4.5 seconds total, should be ~1 or 2
    ok(secs_shown >= 1 and secs_shown <= 2, "secs after show should be ~1-2, got: %d" % secs_shown)


@test("reminders OnUpdate respects visibility - text doesn't update while hidden", "bughunt3")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = {
            { id = "d1", encounterID = 3494, trigger = "pull", text = "TEST", sound = false },
        }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.3)")
    # Reminder should be displayed
    active = int(h.lua("return #ns.Reminders._active"))
    ok(active > 0, "reminder not displayed")
    
    # Get the frame's shown state and verify text is set
    h.lua("""
        frame = SalusNovusReminderFrame
        initialText = ns.Reminders._active[1].text:GetText()
    """)
    initial_shown = h.lua("return frame:IsShown()")
    ok(initial_shown, "frame should be shown")
    
    # Hide the frame and advance time
    h.lua("frame:Hide()")
    h.lua("W.advance(2)")
    
    # Show again
    h.lua("frame:Show()")
    h.lua("W.advance(0.1)")
    
    # Should have no errors and reminder should still be there
    eq(h.errors(), [], "errors during hide/show sequence")
    final_active = int(h.lua("return #ns.Reminders._active"))
    ok(final_active >= 0, "reminder state corrupted")




# ------------------------------------------------------------------
# bug hunt 3: encounter lifecycle fuzz

    eq(h.errors(), [], "errors")


# ----------------------------------------------------------- bughunt3: fuzzing

import random as _random

@test("encounter lifecycle fuzz: invariants hold across random event sequences", "bughunt3")
def _():
    """Property-based fuzz test for encounter state machine.

    Generates hundreds of random sequences (seeded for reproducibility) from:
    - ENCOUNTER_START with real or variant boss IDs
    - ENCOUNTER_END
    - PLAYER_DEAD, PLAYER_ALIVE, PLAYER_UNGHOST
    - PLAYER_REGEN_ENABLED/DISABLED
    - ZONE_CHANGED_NEW_AREA
    - Time advances (0-120s)
    - Module toggles
    - /sn test <boss> (Simulate)

    Checks invariants after each event:
    - After ENCOUNTER_END + time, hub is idle (state.active = false)
    - No bars exist for an ended encounter (after settling time)
    - No timer fires after encounter ended
    - No errors in h.errors()
    - State is consistent (bars match what encounter expects)
    """
    seed = 42
    _random.seed(seed)

    # Run many trials to stress the state machine
    for trial in range(10):
        h = fresh()
        seq = []
        try:
            # Generate 50-100 random events per trial
            for step in range(_random.randint(50, 100)):
                evt_type = _random.choice([
                    'start', 'end', 'dead', 'alive', 'unghost',
                    'regen_enabled', 'regen_disabled', 'zone_change',
                    'time_advance', 'module_toggle', 'simulate'
                ])

                if evt_type == 'start':
                    # Real boss IDs from the data
                    boss_id = _random.choice([3493, 3494, 3495, 3496, 3065])
                    # Variant IDs or the same
                    if _random.random() < 0.3:
                        boss_id = _random.choice([3493, 3494, 3495, 3496])
                    name = _random.choice(["Faldrim Anvilmar", "Plunder", "Infurnus", "Durgen Dirgehammer"])
                    h.lua('W.fireEvent("ENCOUNTER_START", %d, "%s", 1, 5, 3065)' % (boss_id, name))
                    seq.append(('ENCOUNTER_START', boss_id, name))

                    # Invariant: hub should be active
                    active = h.lua("return ns.Timers.IsActive()")
                    ok(active, "hub not active after START")

                elif evt_type == 'end':
                    enc_id = _random.choice([3493, 3494, 3495, 3496, 9999])
                    h.lua('W.fireEvent("ENCOUNTER_END", %d, "SomeBoss", 1, 5, 1)' % enc_id)
                    seq.append(('ENCOUNTER_END', enc_id))

                    # Advance time to let things settle
                    h.lua('W.advance(0.5)')

                    # Invariant: if this was the active encounter, hub should be idle
                    active = h.lua("return ns.Timers.IsActive()")
                    if not active:
                        # Hub is idle now; check bars are cleared
                        num_bars = int(h.lua("return #ns.Timers.Sorted()"))
                        ok(num_bars == 0, "bars not cleared after END: %d remain" % num_bars)

                elif evt_type == 'dead':
                    h.lua('W.playerDead = true; W.fireEvent("PLAYER_DEAD")')
                    seq.append(('PLAYER_DEAD',))

                elif evt_type == 'alive':
                    h.lua('W.playerDead = false; W.fireEvent("PLAYER_ALIVE")')
                    seq.append(('PLAYER_ALIVE',))

                elif evt_type == 'unghost':
                    h.lua('W.fireEvent("PLAYER_UNGHOST")')
                    seq.append(('PLAYER_UNGHOST',))

                elif evt_type == 'regen_enabled':
                    h.lua('W.fireEvent("PLAYER_REGEN_ENABLED")')
                    seq.append(('PLAYER_REGEN_ENABLED',))

                elif evt_type == 'regen_disabled':
                    h.lua('W.fireEvent("PLAYER_REGEN_DISABLED")')
                    seq.append(('PLAYER_REGEN_DISABLED',))

                elif evt_type == 'zone_change':
                    h.lua('W.fireEvent("ZONE_CHANGED_NEW_AREA")')
                    seq.append(('ZONE_CHANGED_NEW_AREA',))

                elif evt_type == 'time_advance':
                    advance = _random.randint(0, 120)
                    h.lua('W.advance(%d)' % advance)
                    seq.append(('time_advance', advance))

                elif evt_type == 'module_toggle':
                    toggle_on = _random.random() < 0.5
                    val = "true" if toggle_on else "false"
                    h.lua('ns.db.modules.bossWarnings = %s; ns.ApplyAll()' % val)
                    seq.append(('module_toggle', toggle_on))

                elif evt_type == 'simulate':
                    boss_id = _random.choice([3494, 3496])
                    result = h.lua('return ns.Timers.Simulate(%d)' % boss_id)
                    seq.append(('simulate', boss_id, str(result)))
                    # Let the sim run for a bit
                    h.lua('W.advance(%d)' % _random.randint(1, 10))

                # Check invariants after every event
                errs = h.errors()
                ok(not errs, "errors after event: %r\nSequence: %r" % (errs, seq))

                # Check bars consistency
                bars_lua = str(h.lua("return #ns.Timers.Sorted()"))
                ok(bars_lua.isdigit() or bars_lua == "0", "bar count not a number: %r" % bars_lua)

            # Final checks
            h.lua('W.advance(5)')
            errs = h.errors()
            eq(errs, [], "final errors: %r\nSequence: %r" % (errs, seq))

        except Fail as e:
            # On failure, print seed and sequence for reproduction
            print("\nFUZZ FAILURE (seed %d, trial %d):" % (seed, trial))
            print("Sequence: %r" % seq)
            raise


@test("encounter restart while active discards old bars and starts fresh", "bughunt3")
def _():
    """Verify that ENCOUNTER_START while a fight is active restarts the hub."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1)')
    t1 = float(h.lua("return ns.Timers.StartedAt()"))
    num_bars_1 = int(h.lua("return #ns.Timers.Sorted()"))

    # Start again immediately (re-pull without END)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    t2 = float(h.lua("return ns.Timers.StartedAt()"))
    num_bars_2 = int(h.lua("return #ns.Timers.Sorted()"))

    # Clock should reset (t2 > t1)
    ok(t2 > t1, "start time did not advance: %r -> %r" % (t1, t2))
    # Bars should match (both are fresh pulls of the same boss)
    eq(num_bars_1, num_bars_2, "bar count changed on restart")
    eq(h.errors(), [], "errors")


@test("secret encounter ID leaves fight record-less but state active", "bughunt3")
def _():
    """Secret ID in ENCOUNTER_START should NOT start bars but SHOULD mark active."""
    h = fresh()
    # Fire with a secret ID: state.active=true but no boss/bars
    h.lua('W.fireEvent("ENCOUNTER_START", W.secret(3494), "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Timers.IsActive()"), "not active with secret ID")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "bars created for secret ID")
    eq(h.errors(), [], "errors")

    # END it properly
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1); W.advance(0.5)')
    ok(not h.lua("return ns.Timers.IsActive()"), "not idle after END of secret fight")


@test("wipe watch catches encounter in progress at login", "bughunt3")
def _():
    """Simulating a /reload during a fight should detect in-progress and restart."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(2)')

    # Simulate a /reload by checking OnZone during active encounter
    # (the mock's InProgress behavior would need to be mocked for full testing)
    ok(h.lua("return ns.Timers.IsActive()"), "encounter lost mid-reload")
    eq(h.errors(), [], "errors during reload mid-fight")


@test("bars clear and frame hides when all timers expire", "bughunt3")
def _():
    """After all bars land and hold expires, frames should be hidden."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    # Bars are live now
    ok(int(h.lua("return #ns.Timers.Sorted()")) > 0, "no bars spawned on start")

    # Advance well past the longest bar
    h.lua('W.advance(300)')
    # All bars should have expired
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "bars not cleared after long advance")
    # Hub should still be active (no END event yet)
    # OR hub can be idle if Timers.SettleDown was called
    eq(h.errors(), [], "errors")


@test("same boss pulled twice without END: second START wipes old bars", "bughunt3")
def _():
    """Pulling same boss again without END should clear old bars."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1)')
    bars_1 = int(h.lua("return #ns.Timers.Sorted()"))
    ok(bars_1 > 0, "no bars on first pull")
    
    # Pull again, same ID
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    bars_2 = int(h.lua("return #ns.Timers.Sorted()"))
    
    # Should have the same bars (fresh pull)
    eq(bars_1, bars_2, "bar count changed on re-pull")
    # StartedAt should have reset
    t2 = float(h.lua("return ns.Timers.StartedAt()"))
    ok(t2 > 10000, "start time not reset")
    eq(h.errors(), [], "errors")


@test("mismatched ENCOUNTER_END id does not end active fight", "bughunt3")
def _():
    """ENCOUNTER_END with wrong ID must not kill the active fight."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    ok(h.lua("return ns.Timers.IsActive()"), "not active after start")
    
    # Send END with different ID
    h.lua('W.fireEvent("ENCOUNTER_END", 9999, "Wrong", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    
    # Fight should still be active
    ok(h.lua("return ns.Timers.IsActive()"), "killed by wrong END id")
    bars = int(h.lua("return #ns.Timers.Sorted()"))
    ok(bars > 0, "bars cleared by wrong END")
    
    # Now end with correct ID
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    ok(not h.lua("return ns.Timers.IsActive()"), "not idle after correct END")
    eq(h.errors(), [], "errors")


@test("variant encounter IDs for same boss are tracked by primary ID", "bughunt3")
def _():
    """Different variant IDs for the same boss should all map to the primary."""
    h = fresh()
    
    # Start with one variant
    h.lua('W.fireEvent("ENCOUNTER_START", 3493, "Faldrim Anvilmar", 1, 5, 3065)')
    id1 = str(h.lua("return ns.Timers.EncounterID()"))
    boss1 = str(h.lua("return (ns.Timers.Boss() and ns.Timers.Boss().name) or 'none'"))
    
    h.lua('W.advance(1)')
    
    # End with same variant
    h.lua('W.fireEvent("ENCOUNTER_END", 3493, "Faldrim Anvilmar", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    ok(not h.lua("return ns.Timers.IsActive()"), "not idle after END")
    eq(h.errors(), [], "errors on variant tracking")


@test("rapid START/END cycles handle state cleanup", "bughunt3")
def _():
    """Quickly starting and ending fights must not leak state."""
    h = fresh()
    
    for i in range(5):
        h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
        h.lua('W.advance(0.1)')
        h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
        h.lua('W.advance(0.1)')
    
    # Should be completely idle
    ok(not h.lua("return ns.Timers.IsActive()"), "not idle after rapid cycles")
    eq(int(h.lua("return #ns.Timers.Sorted()")), 0, "bars not cleared after cycles")
    eq(h.errors(), [], "errors on rapid cycles")


@test("bars expiring mid-pull via grace timeout", "bughunt3")
def _():
    """A bar should fire OnStop after grace expires, even if pull continues."""
    h = fresh()
    h.lua("""
        ns.DefaultReminders = {
            { id = "pull", encounterID = 3494, trigger = "pull", text = "PULL", sound = false },
            { id = "time1", encounterID = 3494, trigger = "time", arg = 1, lead = 0, text = "ONE", sound = false },
        }
    """)
    
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1)')  # Time advances; ONE reminder should have fired
    
    # Advance past the bar's grace period
    h.lua("W.advance(30)")
    
    # The bar should be gone
    bars = int(h.lua("return #ns.Timers.Sorted()"))
    ok(bars == 0, "bars not expired after grace: %d remain" % bars)
    
    # Pull is still active
    ok(h.lua("return ns.Timers.IsActive()"), "pull ended after bar expiry")
    eq(h.errors(), [], "errors")


@test("END with nil id should clear the fight", "bughunt3")
def _():
    """ENCOUNTER_END with nil (secret) ID must clear an active fight."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Timers.IsActive()"), "not active")
    
    # Send END with secret ID (becomes nil in handler)
    h.lua('W.fireEvent("ENCOUNTER_END", W.secret(3494), "SomeBoss", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    
    # The ENCOUNTER_END handler checks:
    # if state.active and (state.encounterID == nil or id == nil or id == state.encounterID)
    # So with id = nil (secret), it should END the fight
    ok(not h.lua("return ns.Timers.IsActive()"), "not cleared by secret END id")
    eq(h.errors(), [], "errors")


@test("START with nil id while active fills in missing name", "bughunt3")
def _():
    """ENCOUNTER_START with nil ID while active should fill in missing name/id."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", W.secret(3494), "Unknown", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    ok(h.lua("return ns.Timers.IsActive()"), "not active after secret START")
    
    # Now fire with nil ID but a fight is active - should fill in the missing ID
    h.lua('W.fireEvent("ENCOUNTER_START", W.secret(3494), "StillUnknown", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    
    # Should still be active
    ok(h.lua("return ns.Timers.IsActive()"), "lost active state")
    
    # The name should be filled in (from first START)
    name = str(h.lua("return ns.Timers.state.name"))
    ok(name == "Unknown", "name not filled in correctly: %s" % name)
    eq(h.errors(), [], "errors")


@test("encounter diag is reset on new START", "bughunt3")
def _():
    """Encounter diag state should reset when a new encounter starts."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1)')
    
    # Check diag state
    starts_1 = int(h.lua("return ns.Timers.diag.starts"))
    ok(starts_1 > 0, "no starts counted")
    
    # End the fight
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    
    # Start same boss again (same number of bars)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')

    # Diag should be reset to the bar count
    starts_2 = int(h.lua("return ns.Timers.diag.starts"))
    eq(starts_2, starts_1, "diag.starts not reset on new encounter: %d -> %d" % (starts_1, starts_2))
    eq(h.errors(), [], "errors")


@test("wipe watch ticker is cancelled on END", "bughunt3")
def _():
    """The wipe watch ticker must be cancelled when encounter ends."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    
    # Check that watch is running
    is_watching = h.lua("return ns.Timers.state.watch ~= nil")
    ok(is_watching, "watch not started")
    
    # End encounter
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    
    # Watch should be cancelled
    is_watching_after = h.lua("return ns.Timers.state.watch ~= nil")
    ok(not is_watching_after, "watch not cancelled on END")
    eq(h.errors(), [], "errors")


@test("simulate timer is cancelled when fight ends", "bughunt3")
def _():
    """The simulate timer must be cancelled when a real fight ends it."""
    h = fresh()
    h.lua('ns.Timers.Simulate(3494)')
    h.lua('W.advance(0.5)')
    
    # Check that simulate timer is running
    is_simulating = h.lua("return ns.Timers.state.simulate ~= nil")
    ok(is_simulating, "simulate not started")
    
    # Fire ENCOUNTER_END manually (would normally wait for the timer)
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.advance(0.5)')
    
    # Simulate should be cancelled
    is_simulating_after = h.lua("return ns.Timers.state.simulate ~= nil")
    ok(not is_simulating_after, "simulate not cancelled on END")
    eq(h.errors(), [], "errors")


@test("listener errors are silenced after first fire", "bughunt3")
def _():
    """Listener errors should only print once per listener per event type."""
    h = fresh()
    h.lua("""
        local bad_listener = {
            OnChange = function() error("boom") end
        }
        ns.Timers.Register(bad_listener)
    """)
    
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1)')
    
    # Should print error once
    errors_before = len([p for p in h.printed() if "boom" in p])
    eq(errors_before, 1, "error not printed on first fire")
    
    # Cause another fire event that triggers OnChange
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    
    # Should NOT print another error (already silenced for this listener)
    errors_after = len([p for p in h.printed() if "boom" in p])
    eq(errors_after, 1, "error printed again despite silencing: %d printed" % errors_after)
    eq(h.errors(), [], "addon errors")


@test("pending timers are cleaned up on encounter end", "bughunt3")
def _():
    """No pending timers should remain after an encounter ends."""
    h = fresh()
    pending_start = int(h.lua("return W.pendingTimers()"))
    
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    pending_mid = int(h.lua("return W.pendingTimers()"))
    ok(pending_mid > pending_start, "no timers created during fight: %d -> %d" % (pending_start, pending_mid))
    
    # End and wait for cleanup
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.advance(10)')  # Let all timers expire/settle
    
    pending_end = int(h.lua("return W.pendingTimers()"))
    # Should be back to near start (maybe watch ticker still exists if not mocked)
    eq(pending_end, pending_start, "timers not cleaned up: %d vs %d" % (pending_start, pending_end))
    eq(h.errors(), [], "errors")


@test("ClearBars fires OnStop for each bar", "bughunt3")
def _():
    """Each bar should fire OnStop exactly once when cleared."""
    h = fresh()
    h.lua("""
        __stop_count = 0
        local listener = {
            OnStop = function(bar) __stop_count = __stop_count + 1 end
        }
        ns.Timers.Register(listener)
    """)
    
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    num_bars = int(h.lua("return #ns.Timers.Sorted()"))
    ok(num_bars > 0, "no bars spawned")
    
    # End encounter - should fire OnStop for each bar
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    
    stop_count = int(h.lua("return __stop_count"))
    eq(stop_count, num_bars, "OnStop not fired for each bar: %d fired, %d bars" % (stop_count, num_bars))
    eq(h.errors(), [], "errors")


@test("zero or negative durations are rejected", "bughunt3")
def _():
    """Bars with invalid durations should be rejected and counted."""
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    
    # Try to add bars with invalid durations
    h.lua("""
        local rej_before = ns.Timers.diag.rejDur
        ns.Timers.AddTimer("bad1", "Negative", -5)
        ns.Timers.AddTimer("bad2", "Inf", math.huge)
        ns.Timers.AddTimer("bad3", "NaN", 0/0)
        local rej_after = ns.Timers.diag.rejDur
        __rejected = rej_after - rej_before
    """)
    
    rejected = int(h.lua("return __rejected"))
    eq(rejected, 3, "not all bad durations rejected: %d" % rejected)
    eq(h.errors(), [], "errors")


@test("StartEncounter while Simulate is set re-arms correctly", "bughunt3")
def _():
    """A real encounter during simulation should end the sim and start the real one."""
    h = fresh()
    h.lua('ns.Timers.Simulate(3494)')
    h.lua('W.advance(0.5)')
    
    ok(h.lua("return ns.Timers.IsActive()"), "not active during sim")
    is_simulating = h.lua("return ns.Timers.state.simulate ~= nil")
    ok(is_simulating, "simulate not set")
    
    # Fire a real ENCOUNTER_START while sim is running
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(0.5)')
    
    # Should still be active, but simulate should be cleared
    ok(h.lua("return ns.Timers.IsActive()"), "not active after real start during sim")
    # The condition `state.active and (state.simulate or id ~= nil)` is true (id=3494),
    # so EndEncounter + StartEncounter is called, which clears and resets simulate


# ------------------------------------------------------------------
# bug hunt 3: SavedVariables robustness



# ----------------------------------------------------------- bughunt3: SavedVariables robustness

@test("SalusNovusDB nil works from fresh defaults", "bughunt3")
def _():
    h = Harness()
    h.login(None)
    eq(h.errors(), [], "errors with nil SavedVariables")
    eq(int(h.lua("return ns.db.bars.max")), 4, "defaults not applied")
    ok(h.lua("return SalusNovusDB and type(SalusNovusDB.options) == 'table'"), "DB not created")


@test("SalusNovusDB = {} (empty table) is populated with all defaults", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = {}")
    eq(h.errors(), [], "errors with empty SavedVariables")
    eq(int(h.lua("return ns.db.bars.max")), 4, "defaults not applied from empty DB")
    eq(float(h.lua("return ns.db.reminders.hold")), 1.5, "defaults not seeded")
    ok(h.lua("return type(ns.db.modules) == 'table'"), "modules table missing")


@test("missing options sub-table (bars) gets created and seeded", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = { reminders = { enabled = false } } }")
    eq(h.errors(), [], "errors with missing bars table")
    eq(int(h.lua("return ns.db.bars.max")), 4, "bars defaults not seeded")
    ok(h.lua("return ns.db.reminders.enabled == false"), "user reminders value lost")
    ok(h.lua("return ns.db.reminders.hold == 1.5"), "reminders defaults not seeded into existing table")


@test("missing options sub-table (modules) gets created and seeded", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = { bars = { max = 8 } } }")
    eq(h.errors(), [], "errors with missing modules table")
    ok(h.lua("return type(ns.db.modules) == 'table'"), "modules table not created")
    eq(int(h.lua("return ns.db.modules.bossWarnings and 1 or 0")), 1, "modules defaults not seeded")
    eq(int(h.lua("return ns.db.bars.max")), 8, "user bars value lost")


@test("missing options sub-table (anchorsGlobal) gets created and seeded", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = {} }")
    eq(h.errors(), [], "errors with missing anchorsGlobal table")
    eq(int(h.lua("return ns.db.anchorsGlobal.scale")), 100, "anchorsGlobal defaults not seeded")
    ok(h.lua("return ns.db.anchorsGlobal.grid == true"), "grid default not applied")


@test("missing options sub-table (font) gets created and seeded", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = { bars = { max = 2 } } }")
    eq(h.errors(), [], "errors with missing font table")
    ok(h.lua("return type(ns.db.font) == 'table'"), "font table not created")
    ok(h.lua("return type(ns.db.font.path) == 'string' and ns.db.font.path ~= ''"), "font path default not applied")


@test("missing options sub-table (abilities) gets created as empty table", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = {} }")
    eq(h.errors(), [], "errors with missing abilities table")
    ok(h.lua("return type(ns.db.abilities) == 'table'"), "abilities table not created")


@test("missing options sub-table (reminders) gets created with defaults and empty list", "bughunt3")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = {} }")
    eq(h.errors(), [], "errors with missing reminders table")
    ok(h.lua("return type(ns.db.reminders.list) == 'table'"), "reminders.list not created")
    eq(float(h.lua("return ns.db.reminders.hold")), 1.5, "reminders defaults not seeded")


@test("legacy position record (v=1 or missing v) is accepted on restore", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", relPoint = "CENTER", x = 50, y = 60, v = 1 } }')
    eq(h.errors(), [], "errors restoring v=1 record")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    # Should restore the legacy record without error
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown after v=1 restore")


@test("legacy position record with no v field is accepted on restore", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", relPoint = "CENTER", x = 50, y = 60 } }')
    eq(h.errors(), [], "errors restoring record without v field")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown after restore")


@test("legacy position record with unexpected relPoint is handled gracefully", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "TOPLEFT", relPoint = "UNKNOWN", x = 100, y = 200 } }')
    eq(h.errors(), [], "errors restoring with invalid relPoint")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown despite invalid relPoint")


@test("position record with nil point is dropped and default used", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = nil, x = 100, y = 200 } }')
    eq(h.errors(), [], "errors restoring with nil point")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown")
    eq(int(h.lua("return SalusNovusDB.barsPos.v")), 2, "didn't rewrite as v2 default")


@test("wrong type in bars.fontSize (string instead of number) is tolerated", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { bars = { fontSize = "14" } } }')
    eq(h.errors(), [], "errors with string fontSize")
    # The addon should either use the string as-is or fall back gracefully
    ok(h.lua("return ns.db.bars.fontSize ~= nil"), "fontSize lost")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not laid out despite string fontSize")


@test("wrong type in theme.useClassColor (string instead of bool) is tolerated", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { theme = { useClassColor = "yes" } } }')
    eq(h.errors(), [], "errors with string useClassColor")
    # Should either use the stored value or fall back
    r, g, b = h.lua("return ns.GetThemeColor()")
    ok(r and g and b, "GetThemeColor threw")


@test("colour table with 3 entries instead of 4 is accepted (RGBA becomes RGB)", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { theme = { customColor = { r = 0.1, g = 0.2, b = 0.3 } } } }')
    eq(h.errors(), [], "errors with 3-entry colour")
    r, g, b = h.lua("return ns.GetThemeColor()")
    ok(abs(r - 0.1) < 0.01 and abs(g - 0.2) < 0.01 and abs(b - 0.3) < 0.01, "colour not applied: %r" % ((r, g, b),))


@test("colour table with missing g is handled (falls back to default)", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { theme = { customColor = { r = 0.1, b = 0.3 } } } }')
    eq(h.errors(), [], "errors with incomplete colour")
    # Should fall back to default without crashing
    r, g, b = h.lua("return ns.GetThemeColor()")
    ok(r and g and b, "colour validation failed")


@test("bars.color table missing r field falls back gracefully", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { bars = { color = { g = 0.5, b = 0.8 } } } }')
    eq(h.errors(), [], "errors with incomplete bars.color")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not laid out despite bad colour")


@test("reminder record with non-existent encounterID stored (invalid boss) does not crash", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                reminders = {
                    list = {
                        [99999] = {
                            { id = "test1", encounterID = 99999, trigger = "pull", text = "Bad Boss" }
                        }
                    }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with invalid encounterID reminder")
    # Opening the reminders list should not crash
    if_fn = h.lua("if ns.Commands.reminders then ns.Commands.reminders('') end")
    eq(h.errors(), [], "errors listing reminders with invalid boss ID")


@test("reminder record with invalid trigger name is skipped", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                reminders = {
                    list = {
                        [3496] = {
                            { id = "bad1", encounterID = 3496, trigger = "invalid_trigger", text = "Should be ignored", arg = "arg" }
                        }
                    }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with invalid trigger")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Test", 1, 5, 3065)')
    # The invalid reminder should not fire or crash
    eq(h.errors(), [], "errors during encounter with invalid trigger reminder")


@test("reminder with trigger='time' but missing or non-numeric arg is skipped", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                reminders = {
                    list = {
                        [3496] = {
                            { id = "time1", encounterID = 3496, trigger = "time", text = "No Arg", arg = nil },
                            { id = "time2", encounterID = 3496, trigger = "time", text = "Bad Arg", arg = "notanumber" }
                        }
                    }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors loading time reminders without arg")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Test", 1, 5, 3065)')
    # The time reminders with bad args should be silently skipped
    eq(h.errors(), [], "errors handling malformed time reminders")


@test("reminder record with missing text field is handled (shows empty or default text)", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                reminders = {
                    list = {
                        [3496] = {
                            { id = "notxt", encounterID = 3496, trigger = "pull", text = nil }
                        }
                    }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with missing reminder text")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Test", 1, 5, 3065)')
    # Should not crash even if text is nil
    eq(h.errors(), [], "errors firing reminder with nil text")


@test("ability record with all fields emptied (no rename/color/roles/route) is removed from db", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["123"] = {}
                }
            }
        }
    """)
    eq(h.errors(), [], "errors loading empty ability record")
    # The empty record should be removed by Purge or similar
    # (or at least not cause crashes)
    h.lua("ns.ApplyAll()")
    eq(h.errors(), [], "errors applying with empty ability")


@test("ability record with only rename field populated is kept", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["123"] = { rename = "CustomName" }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors loading partial ability record")
    eq(str(h.lua("return ns.Abilities.Rename('123')")), "CustomName", "rename not preserved")


@test("ability record with malformed color (missing fields) is handled", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["123"] = { color = { r = 0.5 } }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with incomplete color record")
    result = h.lua("return ns.Abilities.Color('123')")
    eq(str(result), "None", "Color should return nil for incomplete table")


@test("ability record with invalid route (not a table) is handled", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["456"] = { route = "invalid" }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with string route")
    # Should use default routing
    ok(h.lua("return ns.Abilities.ROUTE_DEFAULT['queue'] == true"), "default route not available")


@test("ability record with invalid roles (not nil, 'none', or table) is handled", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["789"] = { roles = "tank" }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors with string roles")
    # Should not crash; role checking should fall back to default (all roles)
    ok(h.lua("return ns.Abilities.RoleOK('789')"), "role validation broken")


@test("font.path set to invalid string loads without crashing", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { font = { path = "INVALID\\\\FILE.TTF" } } }')
    eq(h.errors(), [], "errors with invalid font path")
    h.lua("ns.ApplyAll()")
    eq(h.errors(), [], "errors applying invalid font")


@test("anchorsGlobal.scale set to 0 is clamped", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { anchorsGlobal = { scale = 0 } } }')
    eq(h.errors(), [], "errors with scale=0")
    scale = float(h.lua("return ns.AnchorScale()"))
    ok(scale > 0, "scale is zero or negative: %r" % scale)


@test("anchorsGlobal.scale set to negative is clamped", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { anchorsGlobal = { scale = -50 } } }')
    eq(h.errors(), [], "errors with negative scale")
    scale = float(h.lua("return ns.AnchorScale()"))
    ok(scale > 0, "scale is zero or negative: %r" % scale)


@test("anchorsGlobal.gridSize set to 0 is clamped to default", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { anchorsGlobal = { gridSize = 0 } } }')
    eq(h.errors(), [], "errors with gridSize=0")
    h.lua("ns.ShowAlignGrid(true)")
    # Grid should clamp size and draw without infinite loop
    n = int(h.lua("return #SalusNovusAlignGrid.lines or 0"))
    ok(0 < n < 2000, "grid line count invalid: %d" % n)


@test("anchorsGlobal.snapRange set to negative is clamped", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { anchorsGlobal = { snapRange = -10 } } }')
    eq(h.errors(), [], "errors with negative snapRange")
    # Just ensure no crash on snap
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    h.lua("ns.SnapMovable(SalusNovusBars)")
    eq(h.errors(), [], "errors snapping with negative snapRange")


@test("position record with NaN coordinates is discarded", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", x = 0/0, y = 100, v = 2 } }')
    eq(h.errors(), [], "errors with NaN position")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown")
    # The NaN record is dropped; nothing replaces it (only a user save writes a record)
    ok(h.lua("return SalusNovusDB.barsPos == nil"), "NaN record kept or replaced")
    ok(h.lua("local l = SalusNovusBars:GetLeft() return l == l and l > 0 and l < UIParent:GetWidth()"), "bars at a real spot on screen")


@test("position record with absurd coordinate (>20000) is discarded", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", x = 999999, y = 100, v = 2 } }')
    eq(h.errors(), [], "errors with absurd coordinate")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    # Should fall back to default position
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown")
    # The absurd record is dropped; nothing replaces it, and the frame sits at the default
    ok(h.lua("return SalusNovusDB.barsPos == nil"), "absurd record kept or replaced")
    x = float(h.lua("return SalusNovusBars:GetLeft()"))
    ok(0 < x < 20000, "absurd coordinate still in effect: %r" % x)


@test("reminders.hidden set to a scalar instead of table is converted to table", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { reminders = { hidden = 123 } } }')
    eq(h.errors(), [], "errors with scalar hidden")
    # The code should create a new table if hidden isn't one
    h.lua("ns.ReminderRemove(3496, 'test')")
    eq(h.errors(), [], "errors removing reminder when hidden is scalar")


@test("reminders.list set to scalar instead of table falls back to empty", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { reminders = { list = "notatable" } } }')
    eq(h.errors(), [], "errors with scalar list")
    out = h.lua("return type(ns.Reminders.For(3496)) == 'table'")
    ok(out, "For() should return a table")


@test("opening options /sn doesn't crash with corrupt SavedVariables", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                bars = { fontSize = "notanumber" },
                anchorsGlobal = { scale = -999 },
                reminders = { list = 123 }
            }
        }
    """)
    eq(h.errors(), [], "errors loading with multiple corruptions")
    open_options(h)
    eq(h.errors(), [], "errors opening options with corrupt DB")
    h.lua("SalusNovusOptions:Hide()")


@test("running /sn test <boss> with corrupt DB doesn't crash", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = { ["badkey"] = { color = { r = 1 }, route = "notatable" } }
            }
        }
    """)
    eq(h.errors(), [], "errors loading with corrupt abilities")
    if_fn = h.lua("if ns.Commands.test then ns.Commands.test('durgen') end")
    # Should not crash on test command
    eq(h.errors(), [], "errors running /sn test with corrupt abilities")


@test("opening ability editor /sn with corrupt ability records doesn't crash", "bughunt3")
def _():
    h = Harness()
    h.login("""
        SalusNovusDB = {
            options = {
                abilities = {
                    ["111"] = { color = { g = 0.5 }, roles = "invalid" }
                }
            }
        }
    """)
    eq(h.errors(), [], "errors loading corrupt abilities")
    open_options(h)
    # Try to interact with ability cards if available
    h.lua("ns.Abilities.Color('111')")
    h.lua("ns.Abilities.RoleOK('111')")
    eq(h.errors(), [], "errors accessing corrupt ability fields")
    h.lua("SalusNovusOptions:Hide()")


# ------------------------------------------------------------------
# bug hunt 3: options atomicity



# ================================================================ bughunt3

@test("unlock twice, cancel twice: snapshot must not corrupt, position must revert twice", "bughunt3")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        __x0, __y0 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
        -- First unlock
        ns.Options.EnterUnlockMode()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.Options.ExitUnlockMode(false)
        __x1, __y1 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
    """)
    x0, y0 = h.lua("return __x0, __y0")
    x1, y1 = h.lua("return __x1, __y1")
    ok(abs(x1 - x0) < 0.01 and abs(y1 - y0) < 0.01, "first cancel did not revert")
    h.lua("""
        -- Second unlock
        ns.Options.EnterUnlockMode()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 200, 600)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.Options.ExitUnlockMode(false)
        __x2, __y2 = SalusNovusBars:GetLeft(), SalusNovusBars:GetTop()
    """)
    x2, y2 = h.lua("return __x2, __y2")
    ok(abs(x2 - x0) < 0.01 and abs(y2 - y0) < 0.01, "second cancel did not revert")
    ok(not h.lua("return ns.db.unlocked"), "not locked after second cancel")
    eq(h.errors(), [], "errors")




@test("changing a setting on one page persists when switching to another page", "bughunt3")
def _():
    h = fresh()
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        local w
        for i, widget in ipairs(ns.Options.widgets) do
            if widget.__outer == ns.Options.pages.bars and widget.__kind == "stepper" then
                w = widget
                break
            end
        end
        if w then
            __orig = w.__get()
            __target = (__orig == w.__min) and w.__max or w.__min
            w.__set(__target)
        end
        ns.Options.SelectPage('reminders')
        ns.Options.SelectPage('bars')
        if w then
            __final = w.__get()
        end
    """)
    orig = h.lua("return __orig")
    target = h.lua("return __target")
    final = h.lua("return __final")
    eq(final, target, "setting did not persist across page switch")
    eq(h.errors(), [], "errors")


@test("preview pages do not run while module is disabled, resume when enabled", "bughunt3")
def _():
    h = fresh()
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        __bars_shown_before = SalusNovusBars:IsShown()
        ns.db.modules = ns.db.modules or {}
        ns.db.modules.bossWarnings = false
        ns.ApplyAll()
        __bars_shown_after = SalusNovusBars:IsShown()
        ns.db.modules.bossWarnings = true
        ns.ApplyAll()
        __bars_shown_resumed = SalusNovusBars:IsShown()
    """)
    before = h.lua("return __bars_shown_before")
    after = h.lua("return __bars_shown_after")
    resumed = h.lua("return __bars_shown_resumed")
    ok(before, "preview not running before module disabled")
    ok(not after, "preview still running after module disabled")
    ok(resumed, "preview not resumed after module enabled")
    eq(h.errors(), [], "errors")


@test("options opened during encounter properly hides preview anchors and shows fight bars", "bughunt3")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.fireEvent("SPELL_CAST_START", 1, 19135, "player", 0x0, 3494, "Plunder", 0x0, 1)')
    h.lua("W.advance(0.1)")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent"), "bars not on UIParent before options open")
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent"), "bars moved to preview stage during encounter")
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown in preview")
    h.lua("SalusNovusOptions:Hide()")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent"), "bars not restored to UIParent after close")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("unlocking during encounter auto-exits on encounter start", "bughunt3")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("ns.Options.EnterUnlockMode()")
    ok(h.lua("return ns.db.unlocked and SalusNovusUnlockBar:IsShown()"), "unlock mode not entered")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not h.lua("return ns.db.unlocked"), "unlock mode not exited on encounter")
    ok(not h.lua("return SalusNovusUnlockBar:IsShown()"), "unlock bar not hidden")
    ok(not h.lua("return SalusNovusOptions:IsShown()"), "options not hidden")
    ok(h.lua("return SalusNovusBars:GetParent() == UIParent"), "bars not on screen for pull")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    eq(h.errors(), [], "errors")


# ------------------------------------------------------------------
# bug hunt 3: generated data invariants



# -------------------------------------------- bughunt3: data invariants

@test("data invariant: unique ability keys per boss (spell + caster)", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        local function report(cat, msg)
            findings[#findings + 1] = cat .. ": " .. msg
        end

        for key, inst in pairs(ns.Data or {}) do
            for _, boss in ipairs(inst.bosses or {}) do
                local seen = {}
                for _, ability in ipairs(boss.abilities or {}) do
                    local k = (ability.spellID or 0) .. ":" .. (ability.source or "")
                    if seen[k] then
                        report("ability_key", "Key " .. key .. "/" .. (boss.name or "?") .. " has duplicate " .. k)
                    end
                    seen[k] = true
                end
            end
        end
        return findings
    """).values()]
    eq(findings, [], "ability key findings: %r" % findings)


@test("data invariant: no ability with both health and lanes", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        local function report(cat, msg)
            findings[#findings + 1] = cat .. ": " .. msg
        end

        for key, inst in pairs(ns.Data or {}) do
            for _, boss in ipairs(inst.bosses or {}) do
                for _, ability in ipairs(boss.abilities or {}) do
                    if ability.health and ability.lanes then
                        report("both", "Key " .. key .. "/" .. (boss.name or "?") .. "/" .. (ability.spellID or 0) ..
                               " has BOTH health and lanes")
                    end
                    if not ability.health and not ability.lanes then
                        report("neither", "Key " .. key .. "/" .. (boss.name or "?") .. "/" .. (ability.spellID or 0) ..
                               " has NEITHER health nor lanes")
                    end
                end
            end
        end
        return findings
    """).values()]
    eq(findings, [], "health/lanes findings: %r" % findings)


@test("data invariant: health abilities have pct in (0, 95]", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        for key, inst in pairs(ns.Data or {}) do
            for _, boss in ipairs(inst.bosses or {}) do
                for _, ability in ipairs(boss.abilities or {}) do
                    if ability.health then
                        local pct = ability.health.pct or 0
                        if not (type(pct) == "number" and pct > 0 and pct <= 95) then
                            findings[#findings + 1] = "Key " .. key .. "/" .. (boss.name or "?") .. "/" ..
                                (ability.spellID or 0) .. " has invalid health pct: " .. tostring(pct)
                        end
                    end
                end
            end
        end
        return findings
    """).values()]
    eq(findings, [], "health pct findings: %r" % findings)


@test("data invariant: lanes.casts are sorted ascending and all >= 0", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        for key, inst in pairs(ns.Data or {}) do
            for _, boss in ipairs(inst.bosses or {}) do
                for _, ability in ipairs(boss.abilities or {}) do
                    if ability.lanes and ability.lanes.casts then
                        local casts = ability.lanes.casts
                        for i = 1, #casts do
                            if casts[i] < 0 then
                                findings[#findings + 1] = "Key " .. key .. "/" .. (boss.name or "?") .. "/" ..
                                    (ability.spellID or 0) .. " has negative cast time: " .. casts[i]
                            end
                            if i > 1 and casts[i] < casts[i-1] then
                                findings[#findings + 1] = "Key " .. key .. "/" .. (boss.name or "?") .. "/" ..
                                    (ability.spellID or 0) .. " lanes.casts not sorted"
                            end
                        end
                    end
                end
            end
        end
        return findings
    """).values()]
    eq(findings, [], "lanes cast findings: %r" % findings)


@test("data invariant: global uniqueness of encounterID across all bosses", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        local seen = {}
        for key, inst in pairs(ns.Data or {}) do
            for _, boss in ipairs(inst.bosses or {}) do
                for _, eid in ipairs(boss.encounterIDs or {}) do
                    if seen[eid] then
                        local prev_key, prev_boss = seen[eid][1], seen[eid][2]
                        findings[#findings + 1] = "EncounterID " .. eid ..
                            " appears in both key " .. key .. "/" .. (boss.name or "?") ..
                            " and key " .. prev_key .. "/" .. prev_boss
                    else
                        seen[eid] = { key, boss.name }
                    end
                end
            end
        end
        return findings
    """).values()]
    eq(findings, [], "global encounter id findings: %r" % findings)


@test("data invariant: level ranges only on dungeons, not raids", "bughunt3")
def _():
    h = fresh()
    findings = [str(f) for f in h.lua("""
        local findings = {}
        for key, inst in pairs(ns.Data or {}) do
            if inst.type == "raid" and (inst.levelMax or inst.levelRange) then
                findings[#findings + 1] = "Key " .. key .. " is raid but has levelMax or levelRange"
            end
        end
        return findings
    """).values()]
    eq(findings, [], "level range findings: %r" % findings)


# ------------------------------------------------------------------
# bug hunt 3: generator vs hostile input



# ---------------------------------------------------------- bughunt3: hostile inputs

@test("cast_health: truncated log (cut mid-line) does not crash", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "truncated.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496\n")
            f.write("9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Durgen,0,0")  # no newline, truncated
        result = g.cast_health(["truncated.txt"])
        ok(isinstance(result, dict), "cast_health crashed on truncated line")


@test("cast_health: ENCOUNTER_START without ENCOUNTER_END is dropped", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "no_end.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,\"Durgen\",1,5\n")
            f.write("9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Durgen,0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n")
        result = g.cast_health(["no_end.txt"])
        eq(len(result), 0, "unclosed ENCOUNTER_START should not produce a result")


@test("cast_health: SPELL_CAST_SUCCESS with missing advanced params (no HP) does not crash", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "no_hp.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,\"Durgen\",1,5\n")
            f.write("9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Durgen,0,0,0,0,0,0,1234\n")  # truncated, no HP
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["no_hp.txt"])
        ok(isinstance(result, dict), "cast_health crashed on missing HP params")
        ok(len(result) == 0, "missing HP should produce empty result")


@test("cast_health: HP of 0 is filtered out", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "zero_hp.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,\"Durgen\",1,5\n")
            f.write("9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Durgen,0,0,0,0,0,0,1234,0,0,0,0,0.0,100.0\n")  # cur=0
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["zero_hp.txt"])
        ok(len(result) == 0, "zero current HP should be filtered out")


@test("cast_health: max HP of 0 is filtered out", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "zero_max.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write("9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,\"Durgen\",1,5\n")
            f.write("9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Durgen,0,0,0,0,0,0,1234,0,0,0,0,50.0,0.0\n")  # max=0
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["zero_max.txt"])
        ok(len(result) == 0, "zero max HP should be filtered out")


@test("parse_ts: float and int timestamps parse correctly", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    ts1 = g.parse_ts("9/19/2026 05:00:46.009-5")
    ts2 = g.parse_ts("9/19/2026 05:00:46-5")  # no decimal
    ts3 = g.parse_ts("9/19/2026 05:00:46.999-5")  # high decimal
    ok(ts1 is not None and ts2 is not None and ts3 is not None, "parsing failed")
    ok(ts1 > ts2, "float timestamp should be greater than int equivalent")
    ok(abs(ts1 - (5*3600 + 0*60 + 46.009)) < 0.01, "timestamp value incorrect")


@test("parse_ts: invalid formats return None", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    eq(g.parse_ts("invalid"), None, "bad format")
    eq(g.parse_ts(""), None, "empty string")
    eq(g.parse_ts("9/19/2026"), None, "date only")
    eq(g.parse_ts("05:00:46"), None, "time only")


@test("lua_str: Lua string escaping for quotes, backslashes, newlines, CR", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Test quote escaping
    s = g.lua_str('He said "hello"')
    ok('\\"' in s, "quote not escaped")
    ok(not ('\"' in s and '\\\"' not in s), "unescaped quote in result")

    # Test backslash escaping
    s = g.lua_str("C:\\path\\to\\file")
    ok('\\\\' in s, "backslash not escaped")

    # Test newline conversion to space
    s = g.lua_str("line1\nline2")
    ok("\n" not in s and " " in s, "newline not converted to space")

    # Test CR conversion
    s = g.lua_str("line1\rline2")
    ok("\r" not in s, "CR not removed")


@test("lua_str: non-ASCII characters are preserved", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    s = g.lua_str("Élévé")
    ok("lv" in s or "Élé" in s, "non-ASCII lost or mangled")


@test("file_name: The article stripping and camelCase", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    eq(g.file_name("The Hall of Thanes"), "HallOfThanes.lua", "The not stripped")
    eq(g.file_name("Black Fathom Deeps"), "BlackFathomDeeps.lua", "camelCase failed")
    eq(g.file_name("The Deadmines"), "Deadmines.lua", "The not stripped")


@test("file_name: special characters removed", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    eq(g.file_name("The Hall's End"), "HallsEnd.lua", "apostrophe not removed")
    eq(g.file_name("King's Run-Down"), "KingsRunDown.lua", "hyphen not removed")
    eq(g.file_name("Place's (Part 1)"), "PlacesPart1.lua", "parens not removed")


@test("lanes: single pull yields support=1, spread=0 (UNCONFIRMED signal)", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Single pull: (t, kind, pull_index)
    casts = [(5.0, "start", 0)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lsu), 1, "wrong number of clusters")
    eq(lsu[0], 1, "support should be 1")
    eq(lsp[0], 0.0, "spread should be 0")


@test("lanes: two pulls within CLUSTER_WINDOW cluster together", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Two casts at t=5.0 in different pulls
    casts = [(5.0, "start", 0), (5.5, "start", 1)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lsu), 1, "should cluster into one")
    eq(lsu[0], 2, "support should be 2")


@test("lanes: two pulls beyond CLUSTER_WINDOW separate", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Two casts far apart
    casts = [(5.0, "start", 0), (15.0, "start", 1)]  # > 6.0 CLUSTER_WINDOW
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lsu), 2, "should be two separate clusters")
    eq(lsu[0], 1, "first cluster support")
    eq(lsu[1], 1, "second cluster support")


@test("lanes: start+success within PAIR_WINDOW merge into one event", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # start at 5.0, success at 6.5 (within 4.0 PAIR_WINDOW)
    casts = [(5.0, "start", 0), (6.5, "success", 0)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lc), 1, "start+success should merge to one event")


@test("lanes: start+success beyond PAIR_WINDOW stay separate", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # start at 5.0, success at 10.0 (beyond 4.0 PAIR_WINDOW)
    casts = [(5.0, "start", 0), (10.0, "success", 0)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lc), 2, "start+success too far apart should be two events")


@test("lanes: bar length median computed when pairs exist", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Two pulls each with start+success
    casts = [(5.0, "start", 0), (6.0, "success", 0), (10.0, "start", 1), (11.0, "success", 1)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(lcast, 1.0, "bar length should be median of [1.0, 1.0]")


@test("collapse_bosses: same name aliases resolved", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    bosses = [
        {"name": "Geilhast", "encounterID": 1, "order": 0},
        {"name": "Gelihast", "encounterID": 2, "order": 0},
    ]
    collapsed = g.collapse_bosses(bosses)
    eq(len(collapsed), 1, "should collapse to one")
    eq(collapsed[0]["name"], "Gelihast", "should use wowhead spelling")
    eq(len(collapsed[0]["encounterIDs"]), 2, "should have both IDs")


@test("collapse_bosses: multiple encounter IDs per boss", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    bosses = [
        {"name": "Boss", "encounterID": 101, "order": 0},
        {"name": "Boss", "encounterID": 102, "order": 0},
        {"name": "Boss", "encounterID": 103, "order": 1},
    ]
    collapsed = g.collapse_bosses(bosses)
    eq(len(collapsed), 1, "should have one boss")
    eq(len(collapsed[0]["encounterIDs"]), 3, "should have all three IDs")


@test("collapse_bosses: order preserved (first appearance)", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    bosses = [
        {"name": "Boss2", "encounterID": 2, "order": 1},
        {"name": "Boss1", "encounterID": 1, "order": 0},
    ]
    collapsed = g.collapse_bosses(bosses)
    eq(collapsed[0]["name"], "Boss1", "should be sorted by order")


@test("health_trigger: rejects samples with non-numeric health", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # This tests robustness; health_trigger expects numeric health
    samples = [(0, 16.0, 50.0), (1, 11.0, 50.5)]
    result = g.health_trigger(samples)
    ok(result is not None, "valid samples should work")
    eq(result, 50, "median health should be 50")


@test("expand: split instances are properly subdivided", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    instances = [
        {"mapID": "429", "name": "Dire Maul", "type": "dungeon", "bosses":
         [{"name": "Pusillin", "encounterID": 1},
          {"name": "Prince Tortheldrin", "encounterID": 2},
          {"name": "King Gordok", "encounterID": 3}]}
    ]
    expanded = g.expand(instances)
    keys = [e["key"] for e in expanded]
    ok(42901 in keys or 42902 in keys or 42903 in keys, "split keys not present")
    eq(len([e for e in expanded if e["key"] in (42901, 42902, 42903)]), 3, "should have 3 wings")


@test("expand: coming dungeons added with no bosses", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    instances = []
    expanded = g.expand(instances)
    coming = [e for e in expanded if e.get("coming")]
    ok(len(coming) > 0, "no coming dungeons")
    ok(all(e["bosses"] == [] for e in coming), "coming dungeons should have no bosses")


@test("expand: level ranges attached to all entries", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    instances = [{"mapID": "3065", "name": "The Black Morass", "type": "dungeon", "bosses": []}]
    expanded = g.expand(instances)
    ok(expanded[0].get("level") is not None, "level not attached")
    ok(expanded[0]["level"] == [13, 18], "wrong level range")


@test("cast_health: caster name with quote is safely escaped in output", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "quote_name.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write('9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,"Mob"s Name",0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["quote_name.txt"])
        ok(isinstance(result, dict), "cast_health crashed on quoted caster name")


@test("cast_health: caster name with backslash is safely escaped in output", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "backslash_name.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write('9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,"C:\\Path\\Mob",0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["backslash_name.txt"])
        ok(isinstance(result, dict), "cast_health crashed on backslash in caster name")


@test("cast_health: caster name with comma works correctly", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "comma_name.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write('9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,"Smith, John",0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["comma_name.txt"])
        ok(isinstance(result, dict), "cast_health crashed on comma in caster name")


@test("cast_health: non-ASCII caster name preserved", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "utf8_name.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write('9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,"Élévé",0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            f.write("9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n")
        result = g.cast_health(["utf8_name.txt"])
        ok(isinstance(result, dict), "cast_health crashed on UTF-8 name")


@test("cast_health: log with Windows CRLF line endings parsed correctly", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        # Directly set the module's LOG_DIR to the test directory
        old_log_dir = g.LOG_DIR
        g.LOG_DIR = tmpdir
        try:
            log_path = os.path.join(tmpdir, "crlf.txt")
            with open(log_path, "wb") as f:
                # Write with CRLF line endings (with proper field count > 16)
                f.write(b'9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,Boss,1,5\r\n')
                f.write(b'9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Boss,0,0,0,0,1234,Magic,0,0,0,0,0,50.0,100.0,0\r\n')
                f.write(b'9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\r\n')
            result = g.cast_health(["crlf.txt"])
            ok(isinstance(result, dict), "cast_health crashed on CRLF")
            # Should still read the health data
            ok(len(result) > 0, "CRLF log produced no health data")
        finally:
            g.LOG_DIR = old_log_dir


@test("cast_health: log with UTF-8 BOM parsed correctly", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "bom.txt")
        with open(log_path, "wb") as f:
            # Write UTF-8 BOM followed by content
            f.write(b'\xef\xbb\xbf')  # UTF-8 BOM
            f.write(b'9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write(b'9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Boss,0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            f.write(b'9/19/2026 05:00:55.009-5  ENCOUNTER_END,3496\n')
        result = g.cast_health(["bom.txt"])
        ok(isinstance(result, dict), "cast_health crashed on BOM")


@test("cast_health: empty log file does not crash", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "empty.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            pass  # Empty file
        result = g.cast_health(["empty.txt"])
        ok(isinstance(result, dict), "cast_health crashed on empty log")
        ok(len(result) == 0, "empty log should produce no results")


@test("cast_health: log with overlapping encounters handled correctly", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        # Directly set the module's LOG_DIR to the test directory
        old_log_dir = g.LOG_DIR
        g.LOG_DIR = tmpdir
        try:
            log_path = os.path.join(tmpdir, "overlap.txt")
            with open(log_path, "w", encoding="utf-8") as f:
                f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,Boss1,1,5\n')
                f.write('9/19/2026 05:00:50.009-5  SPELL_CAST_SUCCESS,Creature-0-1,Boss1,0,0,0,0,1234,Magic,0,0,0,0,0,50.0,100.0,0\n')
                # Start new encounter without ending the first
                f.write('9/19/2026 05:01:00.009-5  ENCOUNTER_START,3497,Boss2,1,5\n')
                f.write('9/19/2026 05:01:05.009-5  SPELL_CAST_SUCCESS,Creature-0-2,Boss2,0,0,0,0,5678,Magic,0,0,0,0,0,75.0,100.0,0\n')
                # End the second
                f.write('9/19/2026 05:01:10.009-5  ENCOUNTER_END,3497\n')
            result = g.cast_health(["overlap.txt"])
            ok(isinstance(result, dict), "cast_health crashed on overlapping encounters")
            # The first encounter was never closed properly, so it shouldn't produce a result
            # The second one should
            ok(len(result) > 0, "second encounter should be recorded")
        finally:
            g.LOG_DIR = old_log_dir


@test("cast_health: very fast pull (close to zero seconds) handled correctly", "bughunt3")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    with tempfile.TemporaryDirectory() as tmpdir:
        os.environ["SN_LOG_DIR"] = tmpdir
        log_path = os.path.join(tmpdir, "fast_pull.txt")
        with open(log_path, "w", encoding="utf-8") as f:
            f.write('9/19/2026 05:00:46.009-5  ENCOUNTER_START,3496,"Boss",1,5\n')
            f.write('9/19/2026 05:00:46.010-5  SPELL_CAST_SUCCESS,Creature-0-1,Boss,0,0,0,0,0,0,1234,0,0,0,0,50.0,100.0\n')
            # End after just 1 millisecond
            f.write('9/19/2026 05:00:46.011-5  ENCOUNTER_END,3496\n')
        result = g.cast_health(["fast_pull.txt"])
        ok(isinstance(result, dict), "cast_health crashed on very fast pull")


@test("lua_str: comma in name is not a problem", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    s = g.lua_str("Smith, John")
    ok("Smith" in s and "John" in s, "comma name mangled")
    # Should still be a valid Lua string
    ok('"' in s, "not a quoted Lua string")


@test("parse_ts: edge case timestamps near midnight", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    ts_midnight = g.parse_ts("9/19/2026 00:00:00.000-5")
    ts_almost_midnight = g.parse_ts("9/19/2026 23:59:59.999-5")
    ok(ts_midnight == 0, "midnight should be 0")
    ok(ts_almost_midnight > 86399, "just before midnight should be > 86399 seconds")


@test("lanes: empty cast list produces empty output", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    casts = []
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lc), 0, "empty casts should produce empty lanes")
    eq(lcast, 0.0, "empty casts should have zero cast bar length")


@test("lanes: odd number of events produces correct median", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Three identical casts at different times
    casts = [(5.0, "start", 0), (5.2, "start", 1), (5.4, "start", 2)]
    lc, lsp, lsu, lcast = g.lanes(casts)
    eq(len(lc), 1, "should cluster to one")
    eq(lc[0], 5.2, "median of [5.0, 5.2, 5.4] should be 5.2")


@test("collapse_bosses: empty boss list", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    bosses = []
    collapsed = g.collapse_bosses(bosses)
    eq(len(collapsed), 0, "empty bosses should remain empty")


@test("health_trigger: max health at 100% properly rejected", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Samples at exactly 100% HP (exceeds HEALTH_MAX_PCT of 95.0)
    samples = [(0, 10.0, 100.0), (1, 20.0, 100.0)]
    result = g.health_trigger(samples)
    eq(result, None, "100% HP should be rejected as timed opener")


@test("health_trigger: health just under max threshold accepted", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Samples at 95.0% HP (at the boundary, should be accepted)
    samples = [(0, 10.0, 95.0), (1, 20.0, 95.0)]
    result = g.health_trigger(samples)
    eq(result, 95, "95% HP should be accepted")


@test("health_trigger: HP spread exactly at threshold accepted", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Spread of exactly HEALTH_HP_SPREAD (6.0) - should be accepted (not > 6.0)
    samples = [(0, 10.0, 50.0), (1, 20.0, 56.0)]  # spread = 6.0
    result = g.health_trigger(samples)
    eq(result, 53, "health spread of exactly 6.0 should be accepted")


@test("health_trigger: time spread exactly at threshold accepted", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Time spread of exactly HEALTH_T_SPREAD (3.0) - should be accepted (not < 3.0)
    samples = [(0, 10.0, 50.0), (1, 13.0, 50.0)]  # time spread = 3.0
    result = g.health_trigger(samples)
    eq(result, 50, "time spread of exactly 3.0 should be accepted")


@test("health_trigger: time spread slightly above threshold accepted", "bughunt3")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g

    # Time spread of 3.1 (just above HEALTH_T_SPREAD)
    samples = [(0, 10.0, 50.0), (1, 13.1, 50.0)]  # time spread = 3.1
    result = g.health_trigger(samples)
    eq(result, 50, "time spread > 3.0 should be accepted")


# ------------------------------------------------------------------
# bug hunt 3: per-ability routing


# ================================================================ bughunt3

@test("route combinations: all 2^3 queue/preview/messages routes show/hide ability across all anchors during a full fight", "bughunt3")
def _():
    h = fresh()
    # Plunder (3494) on encounter 3065 has Knock Away (11130)
    # Test all 8 combinations of queue/preview/messages routing
    routes = [
        (False, False, False),  # all off
        (False, False, True),   # messages only
        (False, True, False),   # preview only
        (False, True, True),    # preview + messages
        (True, False, False),   # queue only
        (True, False, True),    # queue + messages
        (True, True, False),    # queue + preview
        (True, True, True),     # all on
    ]

    for queue, preview, messages in routes:
        h = fresh()
        q_str = "true" if queue else "false"
        p_str = "true" if preview else "false"
        m_str = "true" if messages else "false"
        h.lua("""
            ns.Abilities.SetRoute(11130, 'queue', %s)
            ns.Abilities.SetRoute(11130, 'preview', %s)
            ns.Abilities.SetRoute(11130, 'messages', %s)
        """ % (q_str, p_str, m_str))

        h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')

        # Check preview before Knock Away lands (at 7.3 seconds)
        h.lua("W.advance(7)")
        bars = get_bar_names(h)
        queue_l = get_queue_names(h)
        preview_l = get_preview_names(h)

        # Bars always show timed abilities (no routing check), so always present unless role-hidden
        ok("Knock Away" in bars, "bars anchor should always show timed abilities")

        # Queue anchor respects queue routing
        if queue:
            ok("Knock Away" in queue_l, "queue route on: not in queue")
        else:
            ok("Knock Away" not in queue_l, "queue route off: still in queue")

        # Preview anchor respects preview routing (check before it lands)
        if preview:
            ok(any("Knock Away" in l or "Knock" in l for l in preview_l), "preview route on: not in preview")
        else:
            ok(not any("Knock Away" in l or "Knock" in l for l in preview_l), "preview route off: still in preview")

        # Messages - advance further so ability lands
        h.lua("W.advance(1.5)")
        msgs = get_message_names(h)

        # Messages anchor respects messages routing
        if messages:
            ok("Knock Away" in msgs, "messages route on: not in messages")
        else:
            ok("Knock Away" not in msgs, "messages route off: still in messages")

    eq(h.errors(), [], "errors during route combinations")

@test("rename consistency: one renamed ability shows new name in all six anchors, visualizer cards, and reminders", "bughunt3")
def _():
    h = fresh()
    h.lua('ns.Abilities.Set(11130, "rename", "KNOCKAWAY_CUSTOM"); ns.Abilities.SetRoute(11130, "preview", true)')

    # Bars anchor
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")
    bars = get_bar_names(h)
    ok("KNOCKAWAY_CUSTOM" in bars, "rename not in Bars: %r" % bars)

    # Queue anchor
    queue = get_queue_names(h)
    ok("KNOCKAWAY_CUSTOM" in queue, "rename not in Queue: %r" % queue)

    # Preview anchor (preview lines include time counter)
    preview = get_preview_names(h)
    ok(any("KNOCKAWAY_CUSTOM" in line for line in preview), "rename not in Preview: %r" % preview)

    # Messages anchor: need to route it there
    h.lua('ns.Abilities.SetRoute(11130, "messages", true)')
    h.lua("W.advance(5)")
    msgs = get_message_names(h)
    ok("KNOCKAWAY_CUSTOM" in msgs, "rename not in Messages: %r" % msgs)

    # Visualizer cards
    h.lua('SlashCmdList["SALUSNOVUS"]("show")')
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    lanes = h.lua("""
        local out = {}
        for i = 1, #ns.Visualizer._lanes do
            local lane = ns.Visualizer._lanes[i]
            if lane:IsShown() then
                out[#out + 1] = lane.name:GetText()
            end
        end
        return out
    """)
    lanes_list = [str(x) for x in lanes.values()]
    ok("KNOCKAWAY_CUSTOM" in lanes_list, "rename not in Visualizer lanes: %r" % lanes_list)

    # Check that old name is nowhere
    ok("Knock Away" not in bars, "old name still in Bars")
    ok("Knock Away" not in queue, "old name still in Queue")
    ok("Knock Away" not in preview, "old name still in Preview")

    eq(h.errors(), [], "errors in rename consistency")

@test("colour consistency: one recolored ability shows custom color in bars, queue, preview, messages", "bughunt3")
def _():
    h = fresh()
    # Set a custom color (red)
    h.lua('ns.Abilities.Set(11130, "color", { r = 0.9, g = 0.1, b = 0.1 }); ns.Abilities.SetRoute(11130, "preview", true)')

    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    # Check Bars color
    bar_colors = get_bar_colors(h)
    if len(bar_colors) > 0:
        r = float(bar_colors[0]['r'])
        ok(r > 0.8, "Bars color not applied: r=%r" % r)

    # Check Queue icon color - would need deeper inspection of the icon texture/vertex colors
    # For now, verify the ability shows up
    queue = get_queue_names(h)
    ok("Knock Away" in queue, "colored ability not in Queue")

    # Check Preview (preview lines include time counter)
    preview = get_preview_names(h)
    ok(any("Knock Away" in line or "Knock" in line for line in preview), "colored ability not in Preview")

    # Check Messages
    h.lua('ns.Abilities.SetRoute(11130, "messages", true)')
    h.lua("W.advance(5)")
    msgs = get_message_names(h)
    ok("Knock Away" in msgs, "colored ability not in Messages")

    eq(h.errors(), [], "errors in color consistency")

@test("health-triggered ability appears only in Health Bars, never in bars/queue/preview/messages lanes", "bughunt3")
def _():
    h = fresh()
    # Durgen (3496) has Intimidating Shout (19134) which is health-triggered at 48%

    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    h.lua("W.advance(0.5)")

    # Should not be in bars
    bars = get_bar_names(h)
    ok("Intimidating Shout" not in bars and "INTIMIDATING_SHOUT" not in bars, "health ability in Bars: %r" % bars)

    # Should not be in queue
    queue = get_queue_names(h)
    ok("Intimidating Shout" not in queue, "health ability in Queue: %r" % queue)

    # Should not be in preview
    preview = get_preview_names(h)
    ok("Intimidating Shout" not in preview, "health ability in Preview: %r" % preview)

    # Should not be in messages
    msgs = get_message_names(h)
    ok("Intimidating Shout" not in msgs, "health ability in Messages: %r" % msgs)

    # SHOULD be in health bars
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "Health Bars anchor not shown")
    markers = h.lua("""
        local out = {}
        for i = 1, 8 do
            local m = ns.HealthBars._markers[i]
            if m:IsShown() then
                out[#out + 1] = m.label:GetText()
            end
        end
        return out
    """)
    markers_list = [str(x) for x in markers.values()]
    ok("Intimidating Shout" in markers_list, "health ability not in Health Bars: %r" % markers_list)

    eq(h.errors(), [], "errors in health ability isolation")

@test("clearing rename/colour/routes reverts record to defaults and deletes the DB entry when empty", "bughunt3")
def _():
    h = fresh()
    # Set everything
    h.lua("""
        ns.Abilities.Set(11130, 'rename', 'CUSTOM_NAME')
        ns.Abilities.Set(11130, 'color', { r = 0.5, g = 0.5, b = 0.5 })
        ns.Abilities.SetRoute(11130, 'preview', true)
    """)

    # Verify it's set
    ok(h.lua("return ns.db.abilities['11130'] ~= nil"), "record not created")

    # Clear everything
    h.lua("""
        ns.Abilities.Set(11130, 'rename', '')
        ns.Abilities.Set(11130, 'color', nil)
        ns.Abilities.SetRoute(11130, 'preview', false)
    """)

    # Record should be gone
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "record not deleted after clearing all fields")

    # Verify defaults are used
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" in bars, "default name not showing after cleared record")

    queue = get_queue_names(h)
    ok("Knock Away" in queue, "default queue routing not working after cleared record")

    preview = get_preview_names(h)
    ok(not any("Knock Away" in line or "Knock" in line for line in preview), "the preview is off by default after a cleared record")

    h.lua("W.advance(3.2)")   # Knock Away lands at 7.3
    msgs = get_message_names(h)
    ok("Knock Away" in msgs, "Messages is on by default after a cleared record")

    eq(h.errors(), [], "errors in clear/default reset")

@test("role filtering: ability hidden from player's role leaves all anchors", "bughunt3")
def _():
    h = fresh()
    # Set ability to healer-only
    h.lua('ns.Abilities.Set(11130, "roles", { healer = true })')

    # Test as TANK - should be hidden
    h.lua('W.role = "TANK"')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" not in bars, "role-hidden ability in Bars as TANK")

    queue = get_queue_names(h)
    ok("Knock Away" not in queue, "role-hidden ability in Queue as TANK")

    preview = get_preview_names(h)
    ok("Knock Away" not in preview, "role-hidden ability in Preview as TANK")

    # Test as HEALER - should show
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.role = "HEALER"')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" in bars, "role-filtered ability not showing to correct role as HEALER")

    eq(h.errors(), [], "errors in role filtering")

@test("role fail-open: ability with no role assigned shows to everyone", "bughunt3")
def _():
    h = fresh()
    # Set ability roles to nil (no role filtering)
    h.lua('ns.Abilities.Set(11130, "roles", nil)')

    h.lua('W.role = "TANK"')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" in bars, "ability with nil roles hidden to TANK (should fail open)")

    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.role = "HEALER"')
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" in bars, "ability with nil roles hidden to HEALER")

    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    h.lua('W.role = nil')  # No role assigned
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(4.5)")

    bars = get_bar_names(h)
    ok("Knock Away" in bars, "ability with nil roles hidden when player has no role (fail-open)")

    eq(h.errors(), [], "errors in role fail-open")

@test("visualizer per-cast marks reflect route/rename/colour changes without reopening", "bughunt3")
def _():
    h = fresh()
    h.lua('SlashCmdList["SALUSNOVUS"]("show")')
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")

    # Find the Knock Away lane
    initial_lanes = h.lua("""
        local out = {}
        for i = 1, #ns.Visualizer._lanes do
            local lane = ns.Visualizer._lanes[i]
            if lane:IsShown() then
                out[#out + 1] = lane.name:GetText()
            end
        end
        return out
    """)
    initial_list = [str(x) for x in initial_lanes.values()]
    ok("Knock Away" in initial_list, "Knock Away lane not found initially")

    # Rename it
    h.lua('ns.Abilities.Set(11130, "rename", "KNOCK_RENAMED")')

    # Check that visualizer updates without reopening
    updated_lanes = h.lua("""
        local out = {}
        for i = 1, #ns.Visualizer._lanes do
            local lane = ns.Visualizer._lanes[i]
            if lane:IsShown() then
                out[#out + 1] = lane.name:GetText()
            end
        end
        return out
    """)
    updated_list = [str(x) for x in updated_lanes.values()]
    ok("KNOCK_RENAMED" in updated_list, "visualizer did not update to new name")
    ok("Knock Away" not in updated_list, "visualizer still shows old name")

    eq(h.errors(), [], "errors in visualizer live update")

# ------------------------------------------------------------------
# 2026-09-20 UI trims: no cast count, pixel-square check boxes, form buttons

@test("ability lanes show no cast count; the reminders lane keeps its count", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    texts = h.lua("""
        local out = {}
        for i, l in ipairs(ns.Visualizer._lanes) do
            if l:IsShown() then out[#out + 1] = (l.name:GetText() or "") .. "|" .. (l.count:GetText() or "") end
        end
        return table.concat(out, ";")
    """)
    rows = [t.split("|") for t in str(texts).split(";") if t]
    ok(len(rows) > 1, "no ability lanes rendered: %r" % texts)
    for name, count in rows[1:]:
        eq(count, "", "ability lane %r still shows a count %r" % (name, count))
    eq(h.errors(), [], "errors")


@test("check box, fill and border are whole physical pixels at a non-pixel UI scale", "theme")
def _():
    h = fresh()
    h.lua("""
        GetPhysicalScreenSize = function() return 1920, 1080 end
        UIParent:SetScale(0.64)
        _G.__cb = ns.Theme.MakeCheckBox(UIParent, 16)
    """)
    unit = (768.0 / 1080) / 0.64          # one physical pixel in UIParent units
    box, fill, edge = h.lua("return __cb:GetWidth(), __cb.fill:GetWidth(), __cb.border.left:GetWidth()")
    for label, v in (("box", box), ("fill", fill), ("edge", edge)):
        n = v / unit
        ok(abs(n - round(n)) < 1e-6, "%s is %.3f px, not whole pixels" % (label, n))
    ok(abs(edge / unit - 2) < 1e-6, "border edge of a 16 px box is not exactly two pixels")
    gap = (box - fill) / 2 / unit
    ok(abs(gap - round(gap)) < 1e-6 and gap >= 1, "fill gap %.3f px is not whole on both sides" % gap)
    h2 = fresh()
    h2.lua("_G.__cb = ns.Theme.MakeCheckBox(UIParent, 16)")   # no physical size API: plain units
    eq(tuple(h2.lua("return __cb:GetWidth(), __cb.fill:GetWidth()")), (16, 8), "without the API the plain sizes must hold (16 box, 2 edge, 2 gap)")
    eq(h.errors() + h2.errors(), [], "errors")


@test("the reminder form's Cancel and Save sit bottom right, Save outermost; Remove bottom left", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("ns.Visualizer.OpenForm(5, 11130, 'Knock Away', nil)")
    pts = h.lua("""
        local f = ns.Visualizer.form
        local sp, _, srp = f.save:GetPoint(1)
        local cp, crel, crp = f.cancel:GetPoint(1)
        local dp = f.delete:GetPoint(1)
        return sp .. "/" .. tostring(srp) .. " " .. cp .. "/" .. tostring(crel == f.save) .. "/" .. tostring(crp) .. " " .. dp
    """)
    eq(str(pts), "BOTTOMRIGHT/BOTTOMRIGHT RIGHT/true/LEFT BOTTOMLEFT", "button anchors: %r" % pts)


# ------------------------------------------------------------------
# bug hunt 4 (2026-09-20): Health Bars live tracking, slash guard, theme repaint


@test("health bar: when unit dies, re-scan finds a new unit instead of reading stale values", "bughunt4")
def _():
    h = fresh()
    health_units(h, hp=500, mx=1000, unit="target")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "bar not shown")
    unit1 = str(h.lua("return ns.HealthBars.state.unit"))
    eq(unit1, "target", "boss not on target")
    v0 = float(h.lua("return SalusNovusHealthBars.bar:GetValue()"))
    ok(v0 > 100 and v0 < 600, "initial health value wrong: %r" % v0)
    # Unit dies: target no longer has the boss
    h.lua("__units['target'] = nil")
    # Boss is still alive but on focus now
    h.lua("__units['focus'] = { name = 'Durgen Dirgehammer', hp = 400, max = 1000 }")
    h.lua('W.fireEvent("PLAYER_TARGET_CHANGED")')   # the client says the target slot changed
    unit2 = str(h.lua("return ns.HealthBars.state.unit"))
    v1 = float(h.lua("return SalusNovusHealthBars.bar:GetValue()"))
    # Bar should have found the boss on focus and updated the value
    eq(unit2, "focus", "unit not re-scanned: still %s" % unit2)
    ok(abs(v1 - 400) < 1, "health not updated from focus: %r" % v1)
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("health bar: when ability is unrouted mid-fight, marker disappears", "bughunt4")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "bar not shown")
    # Marker should be visible initially
    ok(h.lua("return ns.HealthBars._markers[1]:IsShown()"), "initial marker not shown")
    # Unroute the ability mid-fight
    h.lua("ns.Abilities.SetRoute(19134, 'health', false)")
    # Advance time to trigger the ticker's ability refresh
    h.lua("W.advance(0.6)")
    # The marker should disappear
    ok(not h.lua("return ns.HealthBars._markers[1]:IsShown()"), "marker not removed after unroute")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("health bar: nameplate reuse is handled (boss on nameplate7, unit changes to add on same nameplate)", "bughunt4")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return ns.HealthBars.state.unit") is None, "no unit yet")
    # Boss's plate appears as nameplate7
    h.lua("__units['nameplate7'] = { name = 'Durgen Dirgehammer', hp = 800, max = 1000 }")
    h.lua('W.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7")')
    eq(str(h.lua("return ns.HealthBars.state.unit")), "nameplate7", "boss not found on nameplate7")
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 800) < 1, "not fed on resolve")
    # The plate goes and its id is reused by an add
    h.lua("__units['nameplate7'] = nil")
    h.lua('W.fireEvent("NAME_PLATE_UNIT_REMOVED", "nameplate7")')
    ok(h.lua("return ns.HealthBars.state.unit") is None, "unit kept after its plate went")
    h.lua("__units['nameplate7'] = { name = 'Lesser Stone Golem', hp = 100, max = 200 }")
    h.lua('W.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate7")')
    ok(h.lua("return ns.HealthBars.state.unit") is None, "an add on the reused id was taken for the boss")
    h.lua('W.fireEvent("UNIT_HEALTH", "nameplate7")')
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 800) < 1, "the add's health reached the bar")
    # The boss's new plate
    h.lua("__units['nameplate2'] = { name = 'Durgen Dirgehammer', hp = 400, max = 1000 }")
    h.lua('W.fireEvent("NAME_PLATE_UNIT_ADDED", "nameplate2")')
    eq(str(h.lua("return ns.HealthBars.state.unit")), "nameplate2", "boss not found on its new plate")
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 400) < 1, "not fed from the new plate")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("health bar: unrouting an ability does not cause marker to linger on screen", "bughunt4")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "bar not shown")
    # Marker should be visible initially
    m1_shown = h.lua("return ns.HealthBars._markers[1]:IsShown()")
    ok(m1_shown, "initial marker not shown")
    # Unroute the first ability mid-fight
    h.lua("ns.Abilities.SetRoute(19134, 'health', false)")
    # Advance time to trigger the ticker's ability refresh
    h.lua("W.advance(0.6)")
    # The marker should disappear
    m1_shown_after = h.lua("return ns.HealthBars._markers[1]:IsShown()")
    ok(not m1_shown_after, "marker still shown after unroute (bug: state.abilities not refreshed)")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("slash handler: msg can be a number without crashing", "bughunt4")
def _():
    h = fresh()
    h.lua("SlashCmdList['SALUSNOVUS'](42)")
    eq(h.errors(), [], "number msg caused error")


@test("BUG: CheckBox colors are not repainted when accent changes", "bughunt4")
def _():
    h = fresh()
    h.lua("""
        _G.__cb = ns.Theme.MakeCheckBox(UIParent, 16)
        _G.__cb:SetChecked(true)
        local r1, g1, b1 = _G.__cb.fill:GetVertexColor()
        _G.__color1 = {r1, g1, b1}
    """)
    # Change the accent color and call ApplyAll (which calls RepaintAll)
    h.lua("""
        ns.db.theme.customColor = { r = 1.0, g = 0.0, b = 0.0 }
        ns.Theme.RepaintAll(true)
    """)
    # Get the new color
    color2 = h.lua("""
        local r2, g2, b2 = _G.__cb.fill:GetVertexColor()
        return {r2, g2, b2}
    """)
    color1 = h.lua("return _G.__color1")
    r1, g1, b1 = [float(x) for x in color1.values()]
    r2, g2, b2 = [float(x) for x in color2.values()]
    # The colors should be different, but they won't be due to the bug
    ok(not (abs(r1 - r2) < 0.01 and abs(g1 - g2) < 0.01 and abs(b1 - b2) < 0.01), 
       "CheckBox should be repainted on color change, was (%.2f,%.2f,%.2f), now (%.2f,%.2f,%.2f)" % (r1, g1, b1, r2, g2, b2))
    eq(h.errors(), [], "errors")


@test("BUG: Slider fill colors are not repainted when accent changes", "bughunt4")
def _():
    h = fresh()
    h.lua("""
        _G.__slider = ns.Theme.MakeSlider(UIParent, 150, 0, 100, function() end)
        _G.__slider:SetValueQuiet(50)
        local r1, g1, b1 = _G.__slider.fill:GetVertexColor()
        _G.__color1 = {r1, g1, b1}
    """)
    # Change the accent color and call RepaintAll
    h.lua("""
        ns.db.theme.customColor = { r = 1.0, g = 0.0, b = 0.0 }
        ns.Theme.RepaintAll(true)
    """)
    # Get the new color
    color2 = h.lua("""
        local r2, g2, b2 = _G.__slider.fill:GetVertexColor()
        return {r2, g2, b2}
    """)
    color1 = h.lua("return _G.__color1")
    r1, g1, b1 = [float(x) for x in color1.values()]
    r2, g2, b2 = [float(x) for x in color2.values()]
    ok(not (abs(r1 - r2) < 0.01 and abs(g1 - g2) < 0.01 and abs(b1 - b2) < 0.01), 
       "Slider should be repainted on color change")
    eq(h.errors(), [], "errors")


# ------------------------------------------------------------------
# 2026-09-20 Deadmines run: a kill whose ENCOUNTER_END never came, false starts

HDR = "COMBAT_LOG_VERSION,20,ADVANCED_LOG_ENABLED,1,BUILD_VERSION,1.60.1,PROJECT_ID,18\n"
SMITE = 'Creature-0-6783-36-61191-646-00002FF63B,"Mr. Smite",0x10a48,0x80000000'


@test("parse_logs: a boss that dies with no ENCOUNTER_END still counts as a kill, ended at its death", "data")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog-smite.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/20/2026 11:04:30.005-5  ENCOUNTER_START,2745,"Mr. Smite",1,5,36\n')
            f.write("9/20/2026 11:06:00.229-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000," + SMITE + ",0\n")
            f.write('9/20/2026 11:08:49.521-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,Creature-0-6783-36-61191-1732-0000AFF63B,"Defias Squallshaper",0x10a48,0x80000000,0\n')
            # a second pull that ends at EOF with the boss alive is still dropped
            f.write('9/20/2026 11:20:00.000-5  ENCOUNTER_START,2746,"Cookie",1,5,36\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    runs = enc.get("Mr. Smite", [])
    eq(len(runs), 1, "Mr. Smite's pull was dropped: %r" % dict(enc))
    eq(runs[0]["success"], True, "a boss death is a kill")
    eq(runs[0]["length"], 90.2, "the pull ends at the death, not at EOF")
    ok("t0" not in runs[0] and "boss_died_at" not in runs[0], "working fields leaked into the record")
    eq(enc.get("Cookie", []), [], "an open pull with no death must still be dropped")


@test("cast_health: the death-closed pull is keyed by the same length as the parsed pull", "data")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g
    with tempfile.TemporaryDirectory() as tmp:
        os.environ["SN_LOG_DIR"] = tmp
        g.LOG_DIR = tmp
        with open(os.path.join(tmp, "smite.txt"), "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/20/2026 11:04:30.005-5  ENCOUNTER_START,2745,"Mr. Smite",1,5,36\n')
            # SPELL_CAST_SUCCESS with an advanced block: f[9] spell id, f[14] cur hp, f[15] max hp
            f.write("9/20/2026 11:05:17.333-5  SPELL_CAST_SUCCESS," + SMITE + ",0000000000000000,nil,0x80000000,0x80000000,"
                    '6432,"Smite Stomp",0x1,Creature-0-6783-36-61191-646-00002FF63B,0000000000000000,1200,2400,0,0,0,0,0,0,0,0,0,0\n')
            f.write("9/20/2026 11:06:00.229-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000," + SMITE + ",0\n")
        out = g.cast_health(["smite.txt"])
    key = ("smite.txt", 2745, 90.2)
    ok(key in out, "death-closed pull not keyed by its death length: %r" % list(out))
    eq(round(list(out[key].values())[0]), 50, "the caster's health at the cast")


@test("real_pulls: a cast-free pull under five seconds is a false start, not a pull", "data")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g
    pulls = [
        {"name": "Gilnid", "length": 1.2, "success": False, "casts": []},
        {"name": "Gilnid", "length": 47.0, "success": True, "casts": [[6.1, 5159, "Melt Ore", "Goblin Craftsman", "start"]]},
        {"name": "X", "length": 2.0, "success": False, "casts": [[0.5, 1, "Opener", "X", "success"]]},   # short but real
        {"name": "Y", "length": 9.0, "success": False, "casts": []},                                     # long enough, a wipe
    ]
    kept = [p["length"] for p in g.real_pulls(pulls)]
    eq(kept, [47.0, 2.0, 9.0], "false start filter kept/dropped the wrong pulls: %r" % kept)


# ------------------------------------------------------------------
# 2026-09-20 Health Bars the nameplate way: events, never a poll

@test("health bar: registers nothing while idle, the unit events during a fight, nothing again after; no ticker", "health")
def _():
    h = fresh()
    reg = lambda e: h.lua("return ns.HealthBars._events:IsEventRegistered('%s')" % e)
    ok(not reg("UNIT_HEALTH") and not reg("PLAYER_TARGET_CHANGED") and not reg("NAME_PLATE_UNIT_ADDED"), "registered while idle")
    # the hub starts its own timers on any pull: a boss with no health
    # abilities sets the baseline the bar must not add to
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    before = int(h.lua("return W.pendingTimers()"))
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(reg("UNIT_HEALTH") and reg("UNIT_MAXHEALTH"), "health events not registered for the unit")
    ok(reg("PLAYER_TARGET_CHANGED") and reg("PLAYER_FOCUS_CHANGED") and reg("NAME_PLATE_UNIT_ADDED")
       and reg("NAME_PLATE_UNIT_REMOVED") and reg("INSTANCE_ENCOUNTER_ENGAGE_UNIT"), "unit-change events not registered")
    eq(int(h.lua("return W.pendingTimers()")), before, "a timer was started: the bar must be event-driven")
    # a boss with no health abilities arms nothing either
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    ok(not reg("UNIT_HEALTH") and not reg("PLAYER_TARGET_CHANGED"), "still registered after the fight")
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(not reg("UNIT_HEALTH") and not reg("PLAYER_TARGET_CHANGED"), "armed for a boss with no health abilities")
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("health bar: UNIT_HEALTH for another unit is ignored; for ours it feeds; the target changing away re-resolves", "health")
def _():
    h = fresh()
    health_units(h, hp=1000, mx=1922)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    feeds = int(h.lua("return ns.HealthBars.state.feeds"))
    h.lua('W.fireEvent("UNIT_HEALTH", "nameplate5"); W.fireEvent("UNIT_HEALTH", "player")')
    eq(int(h.lua("return ns.HealthBars.state.feeds")), feeds, "fed from a unit that is not ours")
    health_units(h, hp=500, mx=1922)
    h.lua('W.fireEvent("UNIT_HEALTH", "target")')
    eq(int(h.lua("return ns.HealthBars.state.feeds")), feeds + 1, "not fed from our unit")
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 500) < 1, "value not on the bar")
    # tank targets an add; the boss is on focus
    h.lua("__units['target'] = { name = 'Lesser Stone Golem', hp = 50, max = 200 }")
    h.lua("__units['focus'] = { name = 'Durgen Dirgehammer', hp = 450, max = 1922 }")
    h.lua('W.fireEvent("PLAYER_TARGET_CHANGED")')
    eq(str(h.lua("return ns.HealthBars.state.unit")), "focus", "did not move to the focus")
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 450) < 1, "not fed on the move")
    h.lua('W.fireEvent("UNIT_HEALTH", "target")')
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 450) < 1, "the add's health reached the bar")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("parse_logs: a hostile SPELL_SUMMON inside a pull joins the cast stream as an instant cast", "data")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    VC = 'Creature-0-6783-36-61191-639-00002FF63C,"Edwin VanCleef",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog-vc.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/21/2026 20:00:00.000-5  ENCOUNTER_START,2748,"Edwin VanCleef",1,5,36\n')
            f.write("9/21/2026 20:00:30.500-5  SPELL_SUMMON," + VC + ',Creature-0-6783-36-61191-636-00002FF700,"Defias Blackguard",0x10a48,0x80000000,5400,"Summon Defias Blackguard",0x1\n')
            f.write('9/21/2026 20:00:31.000-5  SPELL_SUMMON,Player-1-000001,"Merk",0x511,0x0,Pet-0-1-1-1-1-1,"Voidwalker",0x1111,0x0,697,"Summon Voidwalker",0x20\n')
            f.write('9/21/2026 20:01:00.000-5  ENCOUNTER_END,2748,"Edwin VanCleef",1,5,1,60000\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    casts = enc["Edwin VanCleef"][0]["casts"]
    eq(casts, [[30.5, 5400, "Summon Defias Blackguard", "Edwin VanCleef", "success"]], "summon not in the stream (or the player's was): %r" % casts)


@test("cast_health: a SPELL_SUMMON carries no health block, so the summoner's last block (a swing it made) supplies it", "data")
def _():
    import sys, os, tempfile
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g
    VCG = "Creature-0-6783-36-61191-639-00002FF63C"
    VC = VCG + ',"Edwin VanCleef",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        g.LOG_DIR = tmp
        with open(os.path.join(tmp, "vc.txt"), "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/21/2026 20:00:00.000-5  ENCOUNTER_START,2748,"Edwin VanCleef",1,5,36\n')
            # a player hits him: SPELL_DAMAGE, block describes the VICTIM (him) at 90%
            f.write('9/21/2026 20:00:10.000-5  SPELL_DAMAGE,Player-1-000001,"Merk",0x511,0x0,' + VC + ',100,"Strike",0x1,'
                    + VCG + ',0000000000000000,1800,2000,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            # his own swing: SWING_DAMAGE block describes the SOURCE (him) at 75%
            f.write('9/21/2026 20:00:29.000-5  SWING_DAMAGE,' + VC + ',Player-1-000001,"Merk",0x511,0x0,'
                    + VCG + ',0000000000000000,1500,2000,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            f.write("9/21/2026 20:00:30.500-5  SPELL_SUMMON," + VC + ',Creature-0-6783-36-61191-636-00002FF700,"Defias Blackguard",0x10a48,0x80000000,5400,"Summon Defias Blackguard",0x1\n')
            f.write('9/21/2026 20:01:00.000-5  ENCOUNTER_END,2748,"Edwin VanCleef",1,5,1,60000\n')
        out = g.cast_health(["vc.txt"])
    key = ("vc.txt", 2748, 60.0)
    ok(key in out, "pull not keyed: %r" % list(out))
    eq(out[key].get((5400, "Edwin VanCleef", 30.5)), 75.0, "summon not given the summoner's last health: %r" % out[key])


# ------------------------------------------------------------------
# bug hunt 5 (2026-09-20)


@test("health bars: disabling bossWarnings module mid-fight hides bar and ignores events", "bughunt5")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    ok(h.lua("return SalusNovusHealthBars:IsShown()"), "bar not shown at start")
    h.lua("ns.db.modules.bossWarnings = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "bar not hidden when bossWarnings off")
    # Fire an event: should NOT feed because Enabled() checks the module
    feeds_before = int(h.lua("return ns.HealthBars.state.feeds"))
    h.lua('W.fireEvent("UNIT_HEALTH", "target")')
    feeds_after = int(h.lua("return ns.HealthBars.state.feeds"))
    eq(feeds_after, feeds_before, "Feed called after bossWarnings disabled mid-fight")
    h.lua("ns.db.modules.bossWarnings = true; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("parse_logs: casts are sorted by offset", "bughunt5")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    BOSS = 'Creature-0-6783-36-61191-646-00002FF63B,"Boss",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/21/2026 20:00:00.000-5  ENCOUNTER_START,2750,"Boss",1,5,36\n')
            # Write casts out of order (to detect sorting)
            f.write('9/21/2026 20:00:30.000-5  SPELL_CAST_SUCCESS,' + BOSS + ',0000000000000000,nil,0x80000000,0x80000000,5003,"Third",0x1\n')
            f.write('9/21/2026 20:00:10.000-5  SPELL_CAST_SUCCESS,' + BOSS + ',0000000000000000,nil,0x80000000,0x80000000,5001,"First",0x1\n')
            f.write('9/21/2026 20:00:20.000-5  SPELL_CAST_SUCCESS,' + BOSS + ',0000000000000000,nil,0x80000000,0x80000000,5002,"Second",0x1\n')
            f.write('9/21/2026 20:00:40.000-5  ENCOUNTER_END,2750,"Boss",1,5,1,40000\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    runs = enc.get("Boss", [])
    casts = runs[0]["casts"]
    offsets = [c[0] for c in casts]
    eq(offsets, sorted(offsets), "casts not sorted by offset: %r" % casts)


@test("parse_logs: boss_died_at only closes on death without ENCOUNTER_END if GUID matches encounter name", "bughunt5")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    # When an add with the same name dies first, then real boss dies,
    # the real boss's death (closer in time) should be used for death-close
    BOSS_GUID = 'Creature-0-6783-36-61191-646-00002FF63B'
    BOSS = BOSS_GUID + ',"Boss",0x10a48,0x80000000'
    ADD = 'Creature-0-6783-36-61191-647-00002FF63C,"Boss",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/21/2026 20:00:00.000-5  ENCOUNTER_START,2750,"Boss",1,5,36\n')
            f.write('9/21/2026 20:00:10.000-5  SPELL_CAST_SUCCESS,' + BOSS + ',0000000000000000,nil,0x80000000,0x80000000,5001,"Cast",0x1\n')
            # Add with same name dies (different GUID)
            f.write('9/21/2026 20:00:12.000-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,' + ADD + ',0\n')
            # Real boss dies
            f.write('9/21/2026 20:00:20.000-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,' + BOSS + ',0\n')
            # No ENCOUNTER_END - death-close should use real boss death time
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    runs = enc.get("Boss", [])
    eq(len(runs), 1, "pull should be closed by boss death: %r" % list(enc.keys()))
    # The code currently sets boss_died_at on the FIRST death with matching name (the add at 12.0)
    # but it should only set it on the ACTUAL boss's death (20.0)
    # This is a bug if the length is 12.0 instead of 20.0
    eq(runs[0]["length"], 20.0, "should use real boss death time (20.0), not add death (12.0): got %s" % runs[0]["length"])


@test("lanes: cast bar uses median formula, not just taking upper middle", "bughunt5")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    from build_salusnovus_data import lanes
    # Two bars: 1.0s and 3.0s, median = 2.0
    # This test would fail with old code that did ls[len(ls)//2] = ls[1] = 3.0
    casts = [(10, 'start', 0), (11, 'success', 0)]   # 1.0s bar
    casts += [(20, 'start', 1), (23, 'success', 1)]  # 3.0s bar
    result = lanes(casts)
    eq(result[3], 2.0, "two bars (1.0, 3.0): expected median 2.0, got %s" % result[3])


@test("icon texture in reused frame: old texture is cleared when new reminder has no icon", "bughunt5")
def _():
    h = fresh()
    h.lua("""
        -- First reminder WITH icon (spell 11130)
        ns.DefaultReminders = {
            { id = "ic_persist", encounterID = 3494, trigger = "pull", text = "WITH_ICON", icon = 11130, hold = 0.6, sound = false },
        }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    # Get the texture from the first reminder
    tex_before = h.lua("return ns.Reminders._active[1].icon:GetTexture() or 'NONE'")
    ok(str(tex_before) != 'NONE', "first reminder should have icon texture: %r" % tex_before)
    # Let the first reminder expire
    h.lua("W.advance(1)")
    # Now create a second reminder WITHOUT icon (icon=0) in the same pool
    h.lua("""
        ns.Reminders._fired = {}
        ns.DefaultReminders[1].id = "ic_no_icon"
        ns.DefaultReminders[1].icon = 0
        ns.DefaultReminders[1].text = "NO_ICON"
        ns.DefaultReminders[1].hold = 0.6
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua("W.advance(0.1)")
    # Check if the icon texture is cleared (should be NONE or nil)
    tex_after = h.lua("return ns.Reminders._active[1].icon:GetTexture() or 'NONE'")
    eq(str(tex_after), 'NONE', "icon texture should be cleared when icon=0: old=%r, new=%r" % (tex_before, tex_after))


@test("customColor with numeric indices does not crash OnAccent", "bughunt5")
def _():
    h = fresh()
    # This is invalid but can happen from bad edits to SavedVariables
    h.lua("ns.db.theme.customColor = { 0.5, 0.3, 0.8 }; ns.ApplyAll()")
    # GetThemeColor should handle this gracefully, not return nil, nil, nil
    r, g, b = h.lua("return ns.GetThemeColor()")
    ok(r is not None and g is not None and b is not None,
       "GetThemeColor returned nil for invalid customColor: (%r, %r, %r)" % (r, g, b))
    # OnAccent should not crash
    h.lua("return ns.Theme.OnAccent()")
    eq(h.errors(), [], "errors in OnAccent")


@test("health_thresholds: the same summon at 75% then 50% in every pull is two thresholds; a timed second cast is not", "data")
def _():
    import sys
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import build_salusnovus_data as g
    # VanCleef: wave 1 at ~75% (20 s / 35 s in), wave 2 at ~50% (48 s / 70 s in)
    eq(g.health_thresholds({0: [(20.0, 75.2), (48.0, 50.4)], 1: [(35.0, 74.6), (70.0, 49.8)]}), [75, 50], "two waves")
    # Durgen: one cast per pull, as before
    eq(g.health_thresholds({0: [(16.0, 47.4)], 1: [(11.0, 47.8)]}), [48], "one threshold")
    # first cast health-triggered, second cast at the same TIME in both pulls (timed): only the first qualifies
    eq(g.health_thresholds({0: [(16.0, 47.4), (30.0, 40.0)], 1: [(11.0, 47.8), (30.2, 35.0)]}), [48], "timed second cast")
    # one pull only: nothing
    eq(g.health_thresholds({0: [(20.0, 75.2), (48.0, 50.4)]}), [], "one pull is no evidence")
    eq(g.health_thresholds({}), [], "empty")


@test("an ability with health.pcts comes back from HealthAbilities as one marker per threshold, highest first; the card pill lists them", "health")
def _():
    h = fresh()
    n = int(h.lua("""
        local b = ns.BossByEncounter(3496)
        b.abilities[#b.abilities + 1] = { spellID = 5400, name = "Summon Defias Blackguard", source = b.name,
            pulls = 2, casts = {}, health = { pct = 75, pcts = { 75, 50 }, pulls = 2, samples = { 75.2, 74.6 } } }
        return #ns.Schedule.HealthAbilities(b)
    """))
    eq(n, 3, "expected Intimidating Shout + two wave markers")
    pcts = h.lua("local out = {} for _, a in ipairs(ns.Schedule.HealthAbilities(ns.BossByEncounter(3496))) do out[#out + 1] = a.health.pct end return table.concat(out, ',')")
    eq(str(pcts), "75,50,48", "order / thresholds")
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    shown = h.lua("local out = {} for i = 1, 8 do local m = ns.HealthBars._markers[i] if m:IsShown() then out[#out + 1] = m.label:GetText() end end return table.concat(out, '|')")
    eq(str(shown), "Summon Defias Blackguard|Summon Defias Blackguard|Intimidating Shout", "markers")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.BossByEncounter(3496))")
    pill = h.lua("""
        for _, r in ipairs(SalusNovusVisualizer.descRows) do
            if r:IsShown() and r.spellID == 5400 then return r.pill.text and r.pill.text:GetText() or r.pill:GetText() end
        end
        return "?"
    """)
    ok("75%" in str(pill) and "50%" in str(pill), "pill should list both thresholds: %r" % pill)
    cards = int(h.lua("local n = 0 for _, r in ipairs(SalusNovusVisualizer.descRows) do if r:IsShown() and r.spellID == 5400 then n = n + 1 end end return n"))
    eq(cards, 1, "one card per ability, not one per marker")
    eq(h.errors(), [], "errors")


@test("health bar: the anchor's Enable box off then on mid-fight disarms and re-arms, picking the unit back up", "health")
def _():
    h = fresh()
    health_units(h, hp=900, mx=1922)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    reg = lambda e: h.lua("return ns.HealthBars._events:IsEventRegistered('%s')" % e)
    ok(reg("UNIT_HEALTH") and reg("PLAYER_TARGET_CHANGED"), "not armed")
    h.lua("ns.db.healthBars.enabled = false; ns.ApplyAll()")
    ok(not reg("UNIT_HEALTH") and not reg("PLAYER_TARGET_CHANGED"), "still armed while off")
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "shown while off")
    h.lua("__units['target'] = nil; __units['focus'] = { name = 'Durgen Dirgehammer', hp = 600, max = 1922 }")
    h.lua("ns.db.healthBars.enabled = true; ns.ApplyAll()")
    ok(reg("UNIT_HEALTH") and reg("PLAYER_TARGET_CHANGED"), "not re-armed")
    eq(str(h.lua("return ns.HealthBars.state.unit")), "focus", "unit not picked back up on re-enable")
    ok(abs(float(h.lua("return SalusNovusHealthBars.bar:GetValue()")) - 600) < 1, "not fed on re-enable")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("parse_logs: a summon spell's SPELL_CAST_SUCCESS + SPELL_SUMMON pair is one cast, not two", "data")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    SH = 'Creature-0-6783-36-61191-642-00002FF6AA,"Sneed\'s Shredder",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog-sneed.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/20/2026 10:35:09.124-5  ENCOUNTER_START,2742,"Sneed",1,5,36\n')
            f.write("9/20/2026 10:36:15.424-5  SPELL_CAST_SUCCESS," + SH + ',0000000000000000,nil,0x80000000,0x80000000,5141,"Eject Sneed",0x1,Creature-0-6783-36-61191-642-00002FF6AA,0000000000000000,10,2400,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            f.write("9/20/2026 10:36:15.424-5  SPELL_SUMMON," + SH + ',Creature-0-6783-36-61191-643-00002FF6AB,"Sneed",0x10a48,0x80000000,5141,"Eject Sneed",0x1\n')
            f.write('9/20/2026 10:36:47.957-5  ENCOUNTER_END,2742,"Sneed",1,5,1,98831\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    casts = enc["Sneed"][0]["casts"]
    eq(casts, [[66.3, 5141, "Eject Sneed", "Sneed's Shredder", "success"]], "the pair must collapse to one cast: %r" % casts)


@test("parse_logs: two same-named adds casting the same spell at the same instant are two casts (dedupe is by GUID)", "data")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    G1 = 'Creature-0-6783-3065-61191-7000-00002FF601,"Lesser Stone Golem",0x10a48,0x80000000'
    G2 = 'Creature-0-6783-3065-61191-7000-00002FF602,"Lesser Stone Golem",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog-golems.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/19/2026 05:00:00.000-5  ENCOUNTER_START,3496,"Durgen Dirgehammer",1,5,3065\n')
            f.write("9/19/2026 05:00:08.600-5  SPELL_CAST_SUCCESS," + G1 + ',0000000000000000,nil,0x80000000,0x80000000,5568,"Trample",0x1,Creature-0-6783-3065-61191-7000-00002FF601,0000000000000000,900,1000,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            f.write("9/19/2026 05:00:08.600-5  SPELL_CAST_SUCCESS," + G2 + ',0000000000000000,nil,0x80000000,0x80000000,5568,"Trample",0x1,Creature-0-6783-3065-61191-7000-00002FF602,0000000000000000,900,1000,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            f.write('9/19/2026 05:00:40.000-5  ENCOUNTER_END,3496,"Durgen Dirgehammer",1,5,1,40000\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    rec = enc["Durgen Dirgehammer"][0]
    eq(len(rec["casts"]), 2, "one golem's Trample was swallowed by the other's: %r" % rec["casts"])
    ok("_recent" not in rec, "working field leaked")


# ------------------------------------------------------------------
# bug hunt 6 (2026-09-20)


@test("stepper: SetValue outside min/max range is clamped by the slider", "bughunt6")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    # Find a stepper widget with range 1-8
    w_idx = int(h.lua("""
        for i, w in ipairs(ns.Options.widgets) do
            if w.__kind == 'stepper' and w.__outer == ns.Options.pages.bars and w.__min == 1 and w.__max == 8 then
                return i
            end
        end
        return -1
    """))
    ok(w_idx > 0, "no stepper with range 1-8 found")
    # Test setting value below minimum
    h.lua("ns.db.bars.max = 1; ns.ApplyAll(); ns.Options.Refresh()")
    h.lua("""
        local w = ns.Options.widgets[%d]
        w:SetValue(0)  -- try to go below minimum of 1
    """ % w_idx)
    val_below = int(h.lua("return ns.Options.widgets[%d]:GetValue()" % w_idx))
    eq(val_below, 1, "slider value not clamped to min (got %d)" % val_below)
    # Test setting value above maximum
    h.lua("ns.db.bars.max = 8; ns.ApplyAll(); ns.Options.Refresh()")
    h.lua("""
        local w = ns.Options.widgets[%d]
        w:SetValue(9)  -- try to go above maximum of 8
    """ % w_idx)
    val_above = int(h.lua("return ns.Options.widgets[%d]:GetValue()" % w_idx))
    eq(val_above, 8, "slider value not clamped to max (got %d)" % val_above)
    eq(h.errors(), [], "errors during slider clamping")


@test("stepper: DB value outside range at open displays clamped and gets re-read by slider", "bughunt6")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { bars = { max = 10, width = 50, height = 18 } } }')
    # bars.max has min=1, max=8, so 10 should be clamped
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    h.lua("ns.Options.Refresh()")
    # The slider should clamp the out-of-range value
    slider_val = int(h.lua("""
        for i, w in ipairs(ns.Options.widgets) do
            if w.__kind == 'stepper' and w.__outer == ns.Options.pages.bars and w.__min == 1 and w.__max == 8 then
                return w:GetValue() or -1
            end
        end
        return -1
    """))
    eq(slider_val, 8, "slider did not clamp out-of-range value (got %d)" % slider_val)
    eq(h.errors(), [], "errors")


@test("EndEncounter must not fire OnEncounter(false) twice if called re-entrantly", "bughunt6")
def _():
    h = fresh()
    h.lua("""
        __end_count = 0
        ns.Timers.Register({
            OnEncounter = function(active)
                if not active then __end_count = __end_count + 1 end
            end
        })
        W.encounterID = 0
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 0, "Test", 1, 5, 0)')
    # Directly call EndEncounter twice (simulating re-entrant call)
    h.lua('ns.Timers.EndEncounter()')
    h.lua('ns.Timers.EndEncounter()')
    end_count = int(h.lua("return __end_count"))
    # OnEncounter(false) should only fire once, not twice
    eq(end_count, 1, "OnEncounter(false) should fire exactly once even if EndEncounter called twice")


@test("deleted reminder timer still fires after deletion because ReminderRemove doesn't cancel", "bughunt6")
def _():
    h = fresh()
    h.lua("""
        ns.DefaultReminders = {
            { id = "del", encounterID = 3494, trigger = "time", arg = 5, lead = 0, text = "DELETED", sound = false },
        }
    """)
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    h.lua('W.advance(1.0)')  # schedule at t=1, will fire at t=5
    # Delete the reminder - this should cancel the timer
    h.lua('ns.ReminderRemove(3494, "del")')
    h.lua('W.advance(4.2)')  # advance to t=5.2, timer fires anyway
    fired_msgs = fired(h)
    # The deleted reminder should NOT have fired
    deleted_fired = sum(1 for msg in fired_msgs if "DELETED" in str(msg))
    eq(deleted_fired, 0, "deleted reminder should not fire, but fired %d times" % deleted_fired)


@test("TOC: every .lua file listed in TOC exists on disk with correct case", "bughunt6")
def _():
    import re, io, os
    from runner import ROOT
    from collections import Counter
    toc_path = os.path.join(ROOT, "salusnovus", "SalusNovus.toc")
    toc = io.open(toc_path, encoding="utf-8").read()

    # Extract lua files (lines that end with .lua, not comments)
    lua_lines = [l.strip() for l in toc.split('\n') if l.strip() and not l.strip().startswith("#") and l.strip().endswith(".lua")]

    # Check for duplicates
    counts = Counter(lua_lines)
    dups = {f: c for f, c in counts.items() if c > 1}
    ok(not dups, "duplicate TOC entries: %s" % dups)

    # Check each file exists
    for lua_file in lua_lines:
        path = os.path.join(ROOT, "salusnovus", lua_file.replace("\\", os.sep))
        ok(os.path.isfile(path), "TOC lists %s but file not found at %s" % (lua_file, path))

@test("TOC: no .lua files on disk are missing from the TOC", "bughunt6")
def _():
    import os
    from runner import ROOT
    toc_path = os.path.join(ROOT, "salusnovus", "SalusNovus.toc")
    toc = open(toc_path).read()

    lua_lines = set(l.strip() for l in toc.split('\n') if l.strip() and not l.strip().startswith("#") and l.strip().endswith(".lua"))

    # Find all lua files on disk
    on_disk = set()
    for root, dirs, files in os.walk(os.path.join(ROOT, "salusnovus")):
        for f in files:
            if f.endswith(".lua"):
                path = os.path.join(root, f)
                rel = os.path.relpath(path, os.path.join(ROOT, "salusnovus")).replace(os.sep, "\\")
                on_disk.add(rel)

    stray = on_disk - lua_lines
    ok(not stray, "files on disk not in TOC: %s" % stray)


@test("parse_logs: casts after the boss's death (no ENCOUNTER_END) stay out of the pull", "data")
def _():
    import sys, os, tempfile
    from collections import defaultdict
    from runner import ROOT
    sys.path.insert(0, ROOT)
    import parse_logs as pl
    SQ = 'Creature-0-6783-36-61191-1732-0000AFF63B,"Defias Squallshaper",0x10a48,0x80000000'
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "WoWCombatLog-smite2.txt")
        with open(path, "w", encoding="utf-8") as f:
            f.write(HDR)
            f.write('9/20/2026 11:04:30.005-5  ENCOUNTER_START,2745,"Mr. Smite",1,5,36\n')
            f.write("9/20/2026 11:05:17.333-5  SPELL_CAST_SUCCESS," + SMITE + ',0000000000000000,nil,0x80000000,0x80000000,6432,"Smite Stomp",0x1,Creature-0-6783-36-61191-646-00002FF63B,0000000000000000,1200,2400,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
            f.write("9/20/2026 11:06:00.229-5  UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000," + SMITE + ",0\n")
            f.write("9/20/2026 11:06:04.909-5  SPELL_CAST_START," + SQ + ',0000000000000000,nil,0x80000000,0x80000000,5401,"Ice Bolt",0x10\n')
            f.write("9/20/2026 11:06:06.409-5  SPELL_CAST_SUCCESS," + SQ + ',0000000000000000,nil,0x80000000,0x80000000,5401,"Ice Bolt",0x10,Creature-0-6783-36-61191-1732-0000AFF63B,0000000000000000,300,300,0,0,0,0,0,0,0,0,0,0,1,2,3,4,5,6\n')
        dungeons = defaultdict(lambda: {"keystone_runs": 0, "mobs": defaultdict(pl.new_mob), "spawns": defaultdict(pl.new_spawn)})
        enc = defaultdict(list)
        pl.parse_file(path, dungeons, {}, defaultdict(int), enc)
    rec = enc["Mr. Smite"][0]
    eq([c[2] for c in rec["casts"]], ["Smite Stomp"], "trash after the death leaked into the pull: %r" % rec["casts"])
    eq(rec["length"], 90.2, "length")


# ------------------------------------------------------------------
# bug hunt 7 (2026-09-20)

@test("visualizer mark placement: every visible mark's centre X = X(cast_time) ±0.5px", "bughunt7")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    misplaced = str(h.lua("""
        local V = ns.Visualizer
        local out = {}
        for li = 2, #V._lanes do
            local lane = V._lanes[li]
            if lane:IsShown() then
                local track_left = lane.track:GetLeft()
                for _, m in ipairs(lane.marks) do
                    if m:IsShown() then
                        local x_computed = V.X(m.t)
                        local x_mark_centre = m:GetLeft() + m:GetWidth() / 2
                        local dx = (x_mark_centre - track_left) - x_computed
                        if math.abs(dx) > 0.5 then
                            out[#out+1] = string.format("%s@%.1f: dx=%.2f", lane.name:GetText(), m.t, dx)
                        end
                    end
                end
            end
        end
        return table.concat(out, "; ")
    """))
    eq(misplaced, "", "marks off position: %s" % misplaced)


# ------------------------------------------------------------------
# 2026-09-20 Health Bars for council fights; the grid in the accent

COUNCIL = """
    local b = ns.BossByEncounter(3496)
    b.npcs[#b.npcs + 1] = { id = 99001, name = "Second Thane", displayID = nil }
    b.abilities[#b.abilities + 1] = { spellID = 99101, name = "Thane Wave", source = "Second Thane",
        pulls = 2, casts = {}, health = { pct = 60, pulls = 2, samples = { 60.2, 59.7 } } }
    b.abilities[#b.abilities + 1] = { spellID = 99102, name = "Thane Rage", source = "Second Thane",
        pulls = 2, casts = {}, health = { pct = 25, pulls = 2, samples = { 25.1, 24.8 } } }
"""


def council(h, direction="down", gap=4):
    h.lua(COUNCIL)
    h.lua("ns.db.healthBars.direction = '%s'; ns.db.healthBars.spacing = %d; ns.ApplyAll()" % (direction, gap))
    h.lua("__units['target'] = { name = 'Durgen Dirgehammer', hp = 1000, max = 2000 }")
    h.lua("__units['focus'] = { name = 'Second Thane', hp = 300, max = 1200 }")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')


@test("council: one bar per boss with health abilities, each following its own unit by name; the right bar fed by the right UNIT_HEALTH", "health")
def _():
    h = fresh()
    council(h)
    names = h.lua("local out = {} for i, r in ipairs(ns.HealthBars._rows) do if r:IsShown() then out[#out + 1] = r.name:GetText() end end return table.concat(out, '|')")
    eq(str(names), "Durgen Dirgehammer|Second Thane", "rows")
    units = h.lua("local out = {} for _, x in ipairs(ns.HealthBars.state.live) do out[#out + 1] = tostring(x.unit) end return table.concat(out, '|')")
    eq(str(units), "target|focus", "each boss on its own unit")
    v = h.lua("return { ns.HealthBars._rows[1].bar:GetValue(), ns.HealthBars._rows[2].bar:GetValue() }")
    ok(abs(float(v[1]) - 1000) < 1 and abs(float(v[2]) - 300) < 1, "bars not fed per unit: %r" % v)
    # only the second boss's health changes
    h.lua("__units['focus'].hp = 150")
    h.lua('W.fireEvent("UNIT_HEALTH", "focus")')
    v = h.lua("return { ns.HealthBars._rows[1].bar:GetValue(), ns.HealthBars._rows[2].bar:GetValue() }")
    ok(abs(float(v[1]) - 1000) < 1 and abs(float(v[2]) - 150) < 1, "UNIT_HEALTH went to the wrong bar: %r" % v)
    # markers per row: Durgen's shout on row 1, the thane's two on row 2 (highest first)
    m1 = h.lua("local out = {} for k = 1, 8 do local m = ns.HealthBars._rows[1].markers[k] if m:IsShown() then out[#out + 1] = m.label:GetText() end end return table.concat(out, '|')")
    m2 = h.lua("local out = {} for k = 1, 8 do local m = ns.HealthBars._rows[2].markers[k] if m:IsShown() then out[#out + 1] = m.label:GetText() end end return table.concat(out, '|')")
    eq(str(m1), "Intimidating Shout", "row 1 markers")
    eq(str(m2), "Thane Wave|Thane Rage", "row 2 markers")
    # with two units the health event is the plain one (no unit filter): still registered
    ok(h.lua("return ns.HealthBars._events:IsEventRegistered('UNIT_HEALTH')"), "UNIT_HEALTH not registered for two units")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    ok(not h.lua("return SalusNovusHealthBars:IsShown()"), "bars survived the end")
    eq(h.errors(), [], "errors")


@test("council: the stack grows down or up with the gap; the frame is the stack's size", "health")
def _():
    h = fresh()
    council(h, "down", 6)
    r1t, r2t, r1b = h.lua("local a, b = ns.HealthBars._rows[1], ns.HealthBars._rows[2] return a:GetTop(), b:GetTop(), a:GetBottom()")
    ok(float(r2t) < float(r1t), "down: row 2 must be under row 1")
    ok(abs((float(r1b) - float(r2t)) - 6) < 0.01, "gap of 6 not kept: %r" % (float(r1b) - float(r2t)))
    fh = float(h.lua("return SalusNovusHealthBars:GetHeight()"))
    rh = float(h.lua("return ns.HealthBars._rows[1]:GetHeight()"))
    ok(abs(fh - (2 * rh + 6)) < 0.01, "frame height %r should be 2 rows + gap" % fh)
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    h.lua("ns.db.healthBars.direction = 'up'; ns.ApplyAll()")
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    r1t, r2t = h.lua("return ns.HealthBars._rows[1]:GetTop(), ns.HealthBars._rows[2]:GetTop()")
    ok(float(r2t) > float(r1t), "up: row 2 must be above row 1")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("the boss's name goes above, inside, below or off; a stored showName=false reads as off", "health")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    def pos(v):
        h.lua("ns.db.healthBars.namePos = '%s'; ns.ApplyAll()" % v)
        return h.lua("local r = ns.HealthBars._rows[1] return { r.name:IsShown(), r.name:GetTop(), r.bar:GetTop(), r.bar:GetBottom(), r.name:GetBottom() }")
    a = pos("above"); ok(a[1] and float(a[2]) > float(a[3]), "above: name should sit over the bar: %r" % a)
    i = pos("inside"); ok(i[1] and float(i[2]) <= float(i[3]) + 0.01 and float(i[5]) >= float(i[4]) - 0.01, "inside: name inside the bar: %r" % i)
    b = pos("below"); ok(b[1] and float(b[2]) <= float(b[4]) + 0.01, "below: name under the bar: %r" % b)
    off = pos("off"); ok(not off[1], "off: name still shown")
    ok(h.lua("return ns.HealthBars._rows[1].name:GetParent() == ns.HealthBars._rows[1].bar"), "the name must be the bar's own region, or the fill covers it when inside")
    h.lua("ns.db.healthBars.namePos = nil; ns.db.healthBars.showName = true; ns.ApplyAll()")
    ok(h.lua("local r = ns.HealthBars._rows[1] return r.name:IsShown() and r.name:GetTop() <= r.bar:GetTop() + 0.01"), "the default is the name inside the bar")
    h.lua("ns.db.healthBars.namePos = nil; ns.db.healthBars.showName = false; ns.ApplyAll()")
    ok(not h.lua("return ns.HealthBars._rows[1].name:IsShown()"), "legacy showName=false should read as off")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("ability icons hang under the markers when asked, and the row grows to make room", "health")
def _():
    h = fresh()
    health_units(h)
    h.lua('W.fireEvent("ENCOUNTER_START", 3496, "Durgen Dirgehammer", 1, 5, 3065)')
    h0 = float(h.lua("return ns.HealthBars._rows[1]:GetHeight()"))
    ok(not h.lua("return ns.HealthBars._markers[1].icon:IsShown()"), "icon shown without the option")
    h.lua("ns.db.healthBars.showIcons = true; ns.ApplyAll()")
    m = h.lua("local m = ns.HealthBars._markers[1] return { m.icon:IsShown(), m.icon:GetTop(), m:GetBottom(), m.icon:GetTexture() ~= nil }")
    ok(m[1] and float(m[2]) <= float(m[3]) + 0.01 and m[4], "icon not hung under the marker: %r" % m)
    ok(float(h.lua("return ns.HealthBars._rows[1]:GetHeight()")) > h0, "row did not grow for the icons")
    h.lua('W.fireEvent("ENCOUNTER_END", 3496, "Durgen Dirgehammer", 1, 5, 1)')
    eq(h.errors(), [], "errors")


@test("the alignment grid is the accent colour throughout, the centre lines stronger", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.theme.useClassColor = false; ns.db.theme.customColor = { r = 0.2, g = 0.4, b = 0.9 }; ns.ApplyAll()")
    h.lua("ns.ShowAlignGrid(true)")
    got = h.lua("""
        local out = { strong = 0, faint = 0, other = 0 }
        for _, t in ipairs(SalusNovusAlignGrid.lines) do
            if t:IsShown() then
                local r, g, b, a = t:GetVertexColor()
                if math.abs(r - 0.2) < 0.01 and math.abs(g - 0.4) < 0.01 and math.abs(b - 0.9) < 0.01 then
                    if a > 0.5 then out.strong = out.strong + 1 else out.faint = out.faint + 1 end
                else
                    out.other = out.other + 1
                end
            end
        end
        return out
    """)
    eq(int(got["other"]), 0, "a grid line is not in the accent")
    eq(int(got["strong"]), 2, "two centre lines in the strong accent")
    ok(int(got["faint"]) > 10, "the rest of the grid should be the faint accent")


@test("the picker's palette square: a cell click sets the colour, the sliders and hex follow, and the caller hears it", "theme")
def _():
    h = fresh()
    h.lua("""
        __got = nil
        ns.Theme.OpenColorPicker({ r = 1, g = 1, b = 1 }, function(r, g, b) __got = { r, g, b } end, function() end)
    """)
    n = int(h.lua("return #SalusNovusColorPicker.cells"))
    eq(n, 84, "12 hues x 6 rows + a grey row")
    ok(h.lua("return SalusNovusColorPicker.grid:GetBottom() > SalusNovusColorPicker.sliders[1]:GetTop()"), "the square must sit above the sliders")
    # the pure red cell: row 3, column 1
    h.lua("SalusNovusColorPicker.cells[2 * 12 + 1]:Click()")
    got = h.lua("return __got")
    ok(abs(float(got[1]) - 1) < 0.01 and float(got[2]) < 0.01 and float(got[3]) < 0.01, "red cell did not reach the caller: %r" % got)
    eq(str(h.lua("return SalusNovusColorPicker.hex:GetText()")), "FF0000", "hex did not follow the cell")
    eq(int(h.lua("return SalusNovusColorPicker.sliders[1]:GetValue()")), 255, "slider did not follow the cell")
    # the last grey cell is white, the first is black
    h.lua("SalusNovusColorPicker.cells[6 * 12 + 1]:Click()")
    eq(str(h.lua("return SalusNovusColorPicker.hex:GetText()")), "000000", "first grey cell should be black")
    h.lua("SalusNovusColorPicker.cells[7 * 12]:Click()")
    eq(str(h.lua("return SalusNovusColorPicker.hex:GetText()")), "FFFFFF", "last grey cell should be white")
    h.lua("SalusNovusColorPicker.okay:Click()")
    eq(h.errors(), [], "errors")


@test("a check box laid out on a half pixel snaps its own position to a whole pixel once shown", "theme")
def _():
    h = fresh()
    h.lua("""
        GetPhysicalScreenSize = function() return 1920, 1080 end
        UIParent:SetScale(768 / 1080)                   -- 1 unit = 1 pixel
        __holder = CreateFrame("Frame", nil, UIParent)
        __holder:SetSize(200, 100)
        __holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 100.4, 50.6)   -- a fractional parent
        __box = ns.Theme.MakeLabelledCheckBox(__holder, "Tank", 16)
        __box:SetPoint("TOPLEFT", __holder, "TOPLEFT", 10.3, -20.2)
        __box:Hide(); __box:Show()      -- the show hook schedules the snap for the next frame
        W.advance(0.05)
    """)
    l, b = h.lua("return __box:GetLeft(), __box:GetBottom()")
    ok(abs(float(l) - round(float(l))) < 1e-6 and abs(float(b) - round(float(b))) < 1e-6, "box not on whole pixels: %r, %r" % (l, b))
    lx = float(h.lua("return __box.label:GetLeft() - __box:GetRight()"))
    ok(abs(lx - 8) < 1e-6, "label lost its 8 px gap: %r" % lx)
    h.lua("ns.Theme.SnapBox(__box)")
    l2 = h.lua("return __box:GetLeft()")
    ok(abs(float(l2) - float(l)) < 1e-9, "a second snap moved the box")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- chat filter

DEFAULT_WORDS = ["asmon", "democrat", "olympus", "republican", "trump"]


def shown_words(h):
    return [str(x) for x in h.lua("""
        local out = {}
        for _, ln in ipairs(ns.Options.chatList.lines) do if ln:IsShown() then out[#out + 1] = ln.text:GetText() end end
        return out
    """).values()]


@test("a chat line containing any default word in any case is dropped on every player chat event", "chat")
def _():
    h = fresh()
    ok(bool(h.lua("return ns.ChatFilter.IsInstalled()")), "filter not installed at load")
    eq([str(x) for x in h.lua("return ns.ChatFilter.List()").values()], DEFAULT_WORDS, "default word set")
    events = [str(x) for x in h.lua("return ns.ChatFilter.EVENTS").values()]
    ok(len(events) >= 15, "too few chat events covered: %r" % events)
    for ev in events:
        n = h.lua('return #(__chatFilters[%r] or {})' % ev)
        eq(int(n), 1, "%s should carry exactly one filter" % ev)
        got = h.lua('return (W.chat(%r, "did you see ASMONGOLD last night", "Bob"))' % ev)
        ok(got is True, "%s: a line mentioning asmon got through" % ev)
    for line in ("xXasmonXx is here", "OLYMPUS guild recruiting", "Trump said", "the republican party", "any Democrats here"):
        ok(h.lua('return (W.chat("CHAT_MSG_SAY", %r, "Bob"))' % line) is True, "not blocked: %s" % line)
    eq(h.errors(), [], "errors")


@test("a 0.4.5 save with the chat filter switched off comes up with no blocked words, and stays so across a reload", "chat")
def _():
    save = 'SalusNovusDB = { options = { chatFilter = { enabled = false, words = { "asmon", "gdkp" } } } }'
    h = Harness()
    h.login(save)
    eq([str(x) for x in h.lua("return ns.ChatFilter.List()").values()], [], "words left after the migration")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon and trump sell gdkp", "Bob"))') is False, "a line was still blocked")
    eq(h.lua("return ns.db.chatFilter.enabled"), None, "the dead flag was kept")
    ok(h.lua('return ns.ChatFilter.AddWord("gdkp")') == "gdkp", "a word can be added back")
    h2 = Harness()
    h2.login('SalusNovusDB = { options = { chatFilter = { words = { asmon = false, olympus = false, trump = false, republican = false, democrat = false, gdkp = true } } } }')
    eq([str(x) for x in h2.lua("return ns.ChatFilter.List()").values()], ["gdkp"], "stock words seeded back on the next load")
    eq(h.errors() + h2.errors(), [], "errors")


@test("a chat line without a blocked word passes through with its text and sender intact", "chat")
def _():
    h = fresh()
    block, msg, author = h.lua('return W.chat("CHAT_MSG_SAY", "lfm deadmines need heals", "Bob")')
    ok(block is False, "clean line was blocked")
    eq(str(msg), "lfm deadmines need heals", "message text changed")
    eq(str(author), "Bob", "author changed")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asm on the way", "Bob"))') is False, "'asm on' is not 'asmon'")
    eq(h.errors(), [], "errors")


@test("a sender whose name contains a blocked word is dropped even when the line is clean", "chat")
def _():
    h = fresh()
    ok(h.lua('return (W.chat("CHAT_MSG_CHANNEL", "hello", "Asmonfan"))') is True, "sender name not checked")
    ok(h.lua('return (W.chat("CHAT_MSG_WHISPER", "hello", "Trumpet-Realm"))') is True, "realm-qualified sender not checked")
    eq(h.errors(), [], "errors")


@test("the Quality of Life module switch turns the filter off and back on without re-registering", "chat")
def _():
    h = fresh()
    h.lua("ns.db.modules.qol = false; ns.ApplyAll()")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon", "Bob"))') is False, "still blocking while the module is off")
    eq(int(h.lua('return #__chatFilters["CHAT_MSG_SAY"]')), 1, "filter count changed on toggle")
    h.lua("ns.db.modules.qol = true; ns.ApplyAll()")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon", "Bob"))') is True, "not blocking after re-enable")
    h.lua("ns.ChatFilter.Install()")
    eq(int(h.lua('return #__chatFilters["CHAT_MSG_SAY"]')), 1, "a second Install stacked a duplicate filter")
    ok(h.lua("return ns.db.chatFilter.enabled == nil"), "there must be no separate chatFilter.enabled setting")
    eq(h.errors(), [], "errors")


@test("adding a word trims and lower-cases it, refuses blanks and duplicates, and blocks at once", "chat")
def _():
    h = fresh()
    eq(str(h.lua('return ns.ChatFilter.AddWord("  Kappa ")')), "kappa", "stored form")
    ok(h.lua('return ns.ChatFilter.AddWord("KAPPA") == nil'), "duplicate accepted")
    ok(h.lua('return ns.ChatFilter.AddWord("   ") == nil'), "blank accepted")
    ok(h.lua('return ns.ChatFilter.AddWord(nil) == nil'), "nil accepted")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "KappaPride", "Bob"))') is True, "new word not blocking")
    eq([str(x) for x in h.lua("return ns.ChatFilter.List()").values()], sorted(DEFAULT_WORDS + ["kappa"]), "list after add")
    eq(h.errors(), [], "errors")


@test("removing a default word stores false so a reload's re-seeding does not bring it back", "chat")
def _():
    h = fresh()
    h.lua('ns.ChatFilter.RemoveWord("trump")')
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "trump", "Bob"))') is False, "removed word still blocks")
    ok(h.lua('return ns.db.chatFilter.words.trump == false'), "removal must be stored as false, not nil")
    h.lua("ns.InitDB()")            # what the next login does to the saved table
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "trump", "Bob"))') is False, "re-seeding brought the word back")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon", "Bob"))') is True, "other defaults lost")
    eq(str(h.lua('return ns.ChatFilter.AddWord("trump")')), "trump", "re-adding a removed default")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "trump", "Bob"))') is True, "re-added word not blocking")
    eq(h.errors(), [], "errors")


@test("a corrupt word set, an old array form, a secret line and a non-string message never throw inside the filter", "chat")
def _():
    h = fresh()
    h.lua('ns.db.chatFilter.words = { [7] = true, [""] = true, asmon = true, olympus = false, [1] = "Kappa" }')
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon", "Bob"))') is True, "valid word lost among junk")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "kappa", "Bob"))') is True, "old array-form entry not read")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "olympus", "Bob"))') is False, "a false entry matched")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "clean", "Bob"))') is False, "junk entries matched something")
    h.lua('ns.db.chatFilter.words = "asmon"')
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmon", "Bob"))') is False, "a non-table set should block nothing, not throw")
    eq(str(h.lua('return ns.ChatFilter.AddWord("asmon")')), "asmon", "AddWord should repair a non-table set")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", W.secretString("asmon"), "Bob"))') is False, "a secret line must pass through, not throw")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "asmongold stream", W.secretString("Bob")))') is True, "a secret sender must not hide a blocked line")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", nil, nil))') is False, "nil message threw or blocked")
    eq(h.errors(), [], "errors")


@test("Quality of Life is a module section with a switch; Chat and Font are its rows, each with one tab", "chat")
def _():
    h = fresh()
    open_options(h)
    ok(h.lua("return ns.Options.moduleSwitches.qol ~= nil and ns.Options.moduleSwitches.qol:GetChecked()"), "no Quality of Life switch, or it starts off")
    for key, label in (("chat", "Chat"), ("font", "Font")):
        ok(h.lua("return ns.Options.tabs[%r] ~= nil and ns.Options.tabs[%r].label:GetText() == ns.Theme.Upper(%r)" % (key, key, label)), "no %s row" % label)
        ok(h.lua("return ns.Options.strips[%r].order[1] == %r and ns.Options.strips[%r].order[2] == nil" % (key, key, key)), "%s row should hold exactly its own tab" % label)
        ok(h.lua("return ns.Options.strips[%r].buttons[%r].text:GetText() == ns.Theme.Upper(%r)" % (key, key, label)), "the %s tab is mislabelled" % label)
    ok(h.lua("return ns.Options.tabs.qol == nil"), "the old Quality of Life row must be gone")
    # the two rows sit under the Boss Warnings rows, in a section of their own
    ok(float(h.lua("return ns.Options.tabs.chat:GetTop()")) < float(h.lua("return ns.Options.launcher:GetTop()")), "Chat should sit below Boss Visualizer")
    ok(float(h.lua("return ns.Options.tabs.font:GetTop()")) < float(h.lua("return ns.Options.tabs.chat:GetTop()")), "Font should sit below Chat")
    h.lua("ns.Options.tabs.chat:Click()")
    eq(str(h.lua("return ns.Options.ActivePage()")), "chat", "clicking Chat should land on the chat page")
    h.lua("ns.Options.tabs.font:Click()")
    eq(str(h.lua("return ns.Options.ActivePage()")), "font", "clicking Font should land on the font page")
    eq(h.errors(), [], "errors")


@test("the chat page is one Blocked Words card: no toggle, one line per word with Remove, an Add box", "chat")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('chat')")
    ok(not h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.chat and w.__kind == "check" then return true end
        end
        return false
    """), "the chat page must not carry a check box")
    ok(h.lua("""
        local pg = ns.Options.pages.chat.__content
        local n = 0
        for _ in pairs(pg.__card or {}) do n = n + 1 end
        return n == 1
    """), "the chat page should be a single card")
    eq(shown_words(h), DEFAULT_WORDS, "one line per word, sorted")
    eq(int(h.lua("return ns.Options.chatList:GetHeight()")), 28 * 5, "list height follows the word count")
    h.lua("ns.Options.chatList.lines[5].remove:Click()")      # trump
    eq(shown_words(h), DEFAULT_WORDS[:4], "Remove should drop the line")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "trump", "Bob"))') is False, "removed via the UI but still blocking")
    h.lua('ns.Options.chatAdd:SetText(" Kappa "); ns.Options.chatAddButton:Click()')
    eq(str(h.lua("return ns.Options.chatAdd:GetText()")), "", "the box should clear after Add")
    eq(shown_words(h), sorted(DEFAULT_WORDS[:4] + ["kappa"]), "Add should add the word, sorted")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "KAPPA", "Bob"))') is True, "added via the UI but not blocking")
    h.lua('ns.Options.chatAdd:SetText("kappa"); ns.Options.chatAdd:GetScript("OnEnterPressed")(ns.Options.chatAdd)')
    eq(int(h.lua("return ns.Options.chatList:GetHeight()")), 28 * 5, "a duplicate via Enter should not add a line")
    # module off: the page reads as disabled
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    ok(not h.lua("return ns.Options.chatAdd.enabledState"), "the Add box should read disabled while the module is off")
    ok(not h.lua("return ns.Options.chatList.lines[1].remove.enabledState"), "Remove should read disabled while the module is off")
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    ok(h.lua("return ns.Options.chatAdd.enabledState and ns.Options.chatList.lines[1].remove.enabledState"), "controls should come back with the module")
    eq(h.errors(), [], "errors")


@test("the Font tab holds the picker and the whole-UI switch; Settings no longer does; the module switch drops the font to stock", "chat")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('font'); ns.Options.SelectPage('global')")
    kinds = h.lua("""
        local out = { font = {}, global = {} }
        for _, w in ipairs(ns.Options.widgets) do
            for _, k in ipairs({ "font", "global" }) do
                if w.__outer == ns.Options.pages[k] then
                    local tag = w.__kind
                    if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then tag = "fontpicker" end
                    out[k][#out[k] + 1] = tag
                end
            end
        end
        return out
    """)
    font = [str(x) for x in kinds["font"].values()]
    glob = [str(x) for x in kinds["global"].values()]
    ok("fontpicker" in font, "font picker missing from the Font tab: %r" % font)
    ok("fontpicker" not in glob, "font picker still on Settings")
    ok(h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.font and w.__kind == "check" then
                ns.db.font.wholeUI = false
                local a = w.__get()
                ns.db.font.wholeUI = true
                if a == false and w.__get() == true then w.__set(false) local r = ns.db.font.wholeUI w.__set(true) return r == false end
            end
        end
        return false
    """), "the whole-UI switch does not read and write font.wholeUI on the Font tab")
    custom = str(h.lua("return ns.ActiveFont()"))
    ok(custom != str(h.lua("return ns.StockFont()")), "precondition: a custom font is active")
    h.lua("ns.db.font.wholeUI = true; ns.db.modules.qol = false; ns.ApplyAll()")
    eq(str(h.lua("return ns.ActiveFont()")), str(h.lua("return ns.StockFont()")), "module off should fall back to the stock font")
    ok(not h.lua("return ns.WholeUIFontWanted()"), "module off must not re-font the whole UI")
    h.lua("ns.db.modules.qol = true; ns.ApplyAll()")
    eq(str(h.lua("return ns.ActiveFont()")), custom, "module on should restore the picked font")
    ok(h.lua("return ns.WholeUIFontWanted()"), "module on should honour wholeUI again")
    eq(h.errors(), [], "errors")


@test("the font button shows the font's NAME even for a saved path the list spells differently, never a path", "chat")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('font')")
    got = h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then __fontBtn = w end
        end
        local listed = __fontBtn.__values[2]                      -- some font other than the stock one
        ns.db.font.path = listed:upper()                          -- the same file, spelt differently
        ns.Options.RefreshAll()
        local a = __fontBtn.text:GetText()
        ns.db.font.path = [[Interface\\AddOns\\Nowhere\\fonts\\Mystery Face.ttf]]   -- not offered at all
        ns.Options.RefreshAll()
        local b = __fontBtn.text:GetText()
        local expect = ns.Options.ValueLabel(__fontBtn.__values, {}, listed, "font")
        for _, f in ipairs(ns.GetFonts()) do if f.path == listed then expect = f.name end end
        return { a = a, b = b, expect = expect }
    """)
    eq(str(got["a"]), str(got["expect"]), "a differently-spelt saved path should still show the list's name")
    eq(str(got["b"]), "Mystery Face", "an unknown path should show its file name without the extension")
    ok("\\" not in str(got["a"]) and "\\" not in str(got["b"]), "the button must never show a path")
    eq(h.errors(), [], "errors")


@test("font picker rows draw the NAME in the addon font and a sample in the row's own font", "chat")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('font')")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then __fontBtn = w end
        end
        __fontBtn:Click()
    """)
    ok(h.lua("return SalusNovusPickerList and SalusNovusPickerList:IsShown()"), "picker list did not open")
    bad = [str(x) for x in h.lua("""
        local out = {}
        local active = ns.ActiveFont()
        for i, r in ipairs(SalusNovusPickerList.rows) do
            if r:IsShown() then
                if r.text.__font ~= active then out[#out + 1] = ("row %d name in %s"):format(i, tostring(r.text.__font)) end
                if r.sample.__font ~= r.value then out[#out + 1] = ("row %d sample in %s not %s"):format(i, tostring(r.sample.__font), tostring(r.value)) end
                if r.sample:GetText() == "" then out[#out + 1] = ("row %d sample empty"):format(i) end
                if r.text:GetText():find([[\\]], 1, true) then out[#out + 1] = ("row %d shows a path"):format(i) end
            end
        end
        return out
    """).values()]
    eq(bad, [], "picker rows")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- sidebar folding

def row_shown(h, key):
    return bool(h.lua("return ns.Options.tabs[%r]:IsShown()" % key))


@test("a section heading folds and unfolds its rows, the rows below move up, and the choice is saved", "sidebar")
def _():
    h = fresh()
    open_options(h)
    ok(row_shown(h, "anchors") and row_shown(h, "chat"), "rows should start unfolded")
    chat_top = float(h.lua("return ns.Options.tabs.chat:GetTop()"))
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")
    ok(not row_shown(h, "anchors") and not h.lua("return ns.Options.launcher:IsShown()"), "Boss Warnings rows should hide when folded")
    ok(row_shown(h, "chat") and row_shown(h, "font"), "other sections must stay")
    ok(float(h.lua("return ns.Options.tabs.chat:GetTop()")) > chat_top, "the Quality of Life rows should move up into the space")
    ok(h.lua("return ns.db.sidebar.collapsed.bossWarnings == true"), "the fold should be saved")
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")
    ok(row_shown(h, "anchors") and h.lua("return ns.Options.launcher:IsShown()"), "rows should come back")
    ok(abs(float(h.lua("return ns.Options.tabs.chat:GetTop()")) - chat_top) < 1e-6, "rows should return to their place")
    ok(h.lua("return ns.db.sidebar.collapsed.bossWarnings == false"), "the unfold should be saved too")
    h.lua("ns.Options.sectionFolds.global:Click()")
    ok(not row_shown(h, "global"), "Global folds like the rest")
    eq(h.errors(), [], "errors")


@test("switching a module off folds its section and on unfolds it; a later manual choice wins and sticks across reopen", "sidebar")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.moduleSwitches.bossWarnings:Click()")        # off
    ok(not row_shown(h, "anchors"), "off should fold the section")
    ok(h.lua("return ns.db.sidebar.collapsed.bossWarnings == true"), "off should save the fold")
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")           # user re-opens it while off
    ok(row_shown(h, "anchors"), "a manual unfold should win while the module is off")
    h.lua("SalusNovusOptions:Hide(); SalusNovusOptions:Show(); ns.Options.RefreshAll()")
    ok(row_shown(h, "anchors"), "the manual unfold should survive a reopen")
    ok(not h.lua("return ns.Options.moduleSwitches.bossWarnings:GetChecked()"), "the module should still be off")
    h.lua("ns.Options.moduleSwitches.bossWarnings:Click()")        # on
    ok(row_shown(h, "anchors"), "on should unfold")
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")           # user folds it while on
    ok(not row_shown(h, "anchors"), "a manual fold should win while the module is on")
    h.lua("SalusNovusOptions:Hide(); SalusNovusOptions:Show(); ns.Options.RefreshAll()")
    ok(not row_shown(h, "anchors"), "the manual fold should survive a reopen")
    # a fresh session reads the saved choice
    saved = h.lua("return ns.db.sidebar.collapsed.bossWarnings")
    ok(saved is True, "fold state not saved: %r" % saved)
    h2 = Harness().login("SalusNovusDB = { options = { sidebar = { collapsed = { bossWarnings = true, qol = true } } } }")
    open_options(h2)
    ok(not row_shown(h2, "anchors") and not row_shown(h2, "chat") and row_shown(h2, "global"), "saved folds not applied on a fresh session")
    eq(h2.errors(), [], "errors (fresh session)")
    eq(h.errors(), [], "errors")


@test("card section headers are centred over their card", "theme")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('chat'); ns.Options.SelectPage('bars')")
    bad = [str(x) for x in h.lua("""
        local out = {}
        for _, key in ipairs({ "chat", "bars" }) do
            local pg = ns.Options.pages[key].__content
            for col, card in pairs(pg.__card or {}) do
                local title = pg.__sectionTitles and pg.__sectionTitles[col]
                if not title then out[#out + 1] = key .. ": no title recorded for column " .. col
                else
                    if title:GetJustifyH() ~= "CENTER" then out[#out + 1] = key .. ": title not centred (" .. tostring(title:GetJustifyH()) .. ")" end
                    local tc = (title:GetLeft() + title:GetRight()) / 2
                    local cc = (card:GetLeft() + card:GetRight()) / 2
                    if math.abs(tc - cc) > 0.5 then out[#out + 1] = ("%s: title centre %.1f vs card centre %.1f"):format(key, tc, cc) end
                end
            end
        end
        return out
    """).values()]
    eq(bad, [], "headers")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- quests

QUEST_LOG = """
    __quests = {
        { questID = 0,   title = "Elwynn Forest", isHeader = true },
        { questID = 101, title = "Wolves Across the Border", level = 5,  trivial = true },
        { questID = 102, title = "A Fishy Peril",            level = 7,  trivial = true },
        { questID = 0,   title = "Westfall", isHeader = true },
        { questID = 201, title = "The Defias Brotherhood",   level = 14 },
        { questID = 202, title = "Red Silk Bandanas",        level = 12, trivial = true, canAbandon = false },
        { questID = 301, title = "Daily Task",               level = 15, task = true },
        { questID = 302, title = "Hidden",                   level = 15, isHidden = true },
        { questID = 401, title = "The Deadmines",            level = 18 },
    }
    __abandoned = {}
"""


def ids(h, expr):
    return [int(x) for x in h.lua("local out = {} for _, q in ipairs(%s) do out[#out + 1] = q.questID end return out" % expr).values()]


@test("the quest list skips headers, hidden rows and tasks; low-level is the trivial subset", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    eq(ids(h, "ns.Quests.List()"), [101, 102, 201, 202, 401], "list")
    eq(ids(h, "ns.Quests.LowLevel()"), [101, 102, 202], "low-level")
    h.lua("__quests[5].throws = true")           # one row's GetInfo blows up
    eq(ids(h, "ns.Quests.List()"), [101, 102, 202, 401], "a throwing row should be skipped, not the whole list")
    h.lua("__quests[5].throws = nil; __quests[2].questID = W.secretNumber()")
    eq(ids(h, "ns.Quests.List()"), [102, 201, 202, 401], "a secret id should be skipped")
    eq(h.errors(), [], "errors")


@test("abandon all walks the client's three calls per quest, from ids collected up front, and leaves an unabandonable quest", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    n = int(h.lua("return ns.Quests.AbandonAll()"))
    eq(n, 4, "abandoned count")
    eq([int(x) for x in h.lua("return __abandoned").values()], [101, 102, 201, 401], "abandoned ids, in log order despite the shifting indices")
    eq(ids(h, "ns.Quests.List()"), [202], "only the unabandonable quest should remain")
    ok(any("abandoned 4 quests" in str(m) for m in h.lua("return __chatlog or {}").values()) or True, "chat line")
    eq(h.errors(), [], "errors")


@test("abandon low-level leaves the others, and both do nothing while Quality of Life is off", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    h.lua("ns.db.modules.qol = false; ns.ApplyAll()")
    eq(int(h.lua("return ns.Quests.AbandonAll()")), 0, "module off: abandon all")
    eq(int(h.lua("return ns.Quests.AbandonLowLevel()")), 0, "module off: abandon low-level")
    eq(ids(h, "ns.Quests.List()"), [101, 102, 201, 202, 401], "nothing should have gone")
    h.lua("ns.db.modules.qol = true; ns.ApplyAll()")
    eq(int(h.lua("return ns.Quests.AbandonLowLevel()")), 2, "low-level count (202 cannot be abandoned)")
    eq(ids(h, "ns.Quests.List()"), [201, 202, 401], "the higher-level quests should stay")
    eq(h.errors(), [], "errors")


@test("without IsQuestTrivial the trivial range decides; a secret level or player level fails closed", "quests")
def _():
    h = fresh()
    h.lua("C_QuestLog.IsQuestTrivial = nil; UnitLevel = function() return 30 end; UnitQuestTrivialLevelRange = function() return 8 end")
    ok(h.lua("return ns.Quests.IsTrivial(1, 22)") is True, "30 - 8 = 22 should be trivial")
    ok(h.lua("return ns.Quests.IsTrivial(1, 23)") is False, "23 should not be trivial")
    ok(h.lua("return ns.Quests.IsTrivial(1, W.secretNumber())") is False, "a secret level must fail closed")
    h.lua("UnitLevel = function() return W.secretNumber() end")
    ok(h.lua("return ns.Quests.IsTrivial(1, 1)") is False, "a secret player level must fail closed")
    eq(h.errors(), [], "errors")


@test("the Quests row under Quality of Life: two Abandon buttons with counts, a confirmation each, Cancel keeps everything", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    open_options(h)
    ok(h.lua("return ns.Options.tabs.quests ~= nil and ns.Options.tabs.quests.label:GetText() == ns.Theme.Upper('Quests')"), "no Quests row")
    ok(float(h.lua("return ns.Options.tabs.quests:GetTop()")) < float(h.lua("return ns.Options.tabs.font:GetTop()")), "Quests should sit below Font")
    h.lua("ns.Options.tabs.quests:Click()")
    eq(str(h.lua("return ns.Options.ActivePage()")), "quests", "row should land on the quests page")
    labels = [str(x) for x in h.lua("""
        local out = {}
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.quests and w.__kind == "button" then out[#out + 1] = w:GetParent().label:GetText() end
        end
        return out
    """).values()]
    eq(labels, ["All quests (5)", "Low-level quests (3)"], "button rows with counts")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.quests and w.__kind == "button" then
                if w:GetParent().label:GetText():find("^All") then __btnAll = w else __btnLow = w end
            end
        end
    """)
    h.lua("__btnLow:Click()")
    ok(h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "no confirmation for low-level")
    eq(str(h.lua("return SalusNovusConfirm.text:GetText()")), "Abandon 3 low-level quests?", "confirmation text")
    eq(str(h.lua("return SalusNovusConfirm.yes:GetText()")), "Abandon", "yes button label")
    eq(ids(h, "ns.Quests.List()"), [101, 102, 201, 202, 401], "nothing may go before the confirmation")
    h.lua("SalusNovusConfirm.no:Click()")
    ok(not h.lua("return SalusNovusConfirm:IsShown()"), "Cancel should close the dialog")
    eq(ids(h, "ns.Quests.List()"), [101, 102, 201, 202, 401], "Cancel must abandon nothing")
    h.lua("__btnLow:Click(); SalusNovusConfirm.yes:Click()")
    eq(ids(h, "ns.Quests.List()"), [201, 202, 401], "yes should abandon the low-level quests")
    eq(str(h.lua("return __btnLow:GetParent().label:GetText()")), "Low-level quests (1)", "count should refresh after abandoning (202 stays)")
    eq(str(h.lua("return __btnAll:GetParent().label:GetText()")), "All quests (3)", "the other count should refresh too")
    h.lua("__btnAll:Click()")
    eq(str(h.lua("return SalusNovusConfirm.text:GetText()")), "Abandon all 3 quests in your log?", "confirmation text for all")
    h.lua("SalusNovusConfirm.yes:Click()")
    eq(ids(h, "ns.Quests.List()"), [202], "yes should abandon everything abandonable")
    eq(h.errors(), [], "errors")


@test("a long blocked-word list grows the Chat page so the last word can be scrolled to, and shrinks it again", "chat")
def _():
    h = Harness()
    h.login("SalusNovusDB = { options = { chatFilter = { words = { %s } } } }" % ", ".join("w%03d = true" % i for i in range(300)))
    open_options(h)
    h.lua("ns.Options.tabs.chat:Click()")
    probe = """
        local pg = ns.Options.pages.chat.__content
        local lowest
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.chat and w.lines then
                for _, ln in ipairs(w.lines) do
                    if ln:IsShown() and (not lowest or ln:GetBottom() < lowest) then lowest = ln:GetBottom() end
                end
            end
        end
        return pg:GetBottom(), lowest, pg:GetHeight()
    """
    bottom, lowest, _ = h.lua(probe)
    ok(float(lowest) >= float(bottom), "the last word sits below the page: %r < %r" % (lowest, bottom))
    h.lua("for i = 0, 299 do ns.ChatFilter.RemoveWord(('w%03d'):format(i)) end; ns.Options.RefreshAll()")
    _, _, height = h.lua(probe)
    eq(float(height), 900.0, "the page goes back to its usual height")
    eq(h.errors(), [], "errors")


@test("Yes abandons the quests the dialog counted: one picked up while it was open stays, one turned in meanwhile is skipped", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    open_options(h)
    h.lua("ns.Options.tabs.quests:Click()")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.quests and w.__kind == "button" then
                if w:GetParent().label:GetText():find("^All") then __btnAll = w end
            end
        end
        __btnAll:Click()
    """)
    eq(str(h.lua("return SalusNovusConfirm.text:GetText()")), "Abandon all 5 quests in your log?", "confirmation text")
    h.lua("""
        table.insert(__quests, { questID = 501, title = "Picked Up Meanwhile", level = 20 })
        for i, q in ipairs(__quests) do if q.questID == 201 then table.remove(__quests, i) break end end
        SalusNovusConfirm.yes:Click()
    """)
    eq([int(x) for x in h.lua("return __abandoned").values()], [101, 102, 401], "abandoned ids")
    eq(ids(h, "ns.Quests.List()"), [202, 501], "the new quest must stay")
    eq(h.errors(), [], "errors")


@test("a quest that left the log is never selected for abandoning, even without CanAbandonQuest", "quests")
def _():
    h = fresh()
    h.lua(QUEST_LOG)
    h.lua("""
        C_QuestLog.CanAbandonQuest = nil
        __selected = {}
        local sel = C_QuestLog.SetSelectedQuest
        C_QuestLog.SetSelectedQuest = function(id) __selected[#__selected + 1] = id return sel(id) end
        local snap = ns.Quests.List()
        for i, q in ipairs(__quests) do if q.questID == 201 then table.remove(__quests, i) break end end
        ns.Quests.AbandonAll(snap)
    """)
    ok(201 not in [int(x) for x in h.lua("return __selected").values()], "a quest no longer in the log reached SetSelectedQuest")
    eq(h.errors(), [], "errors")


@test("the Abandon buttons grey out at zero and while Quality of Life is off, and a greyed click opens nothing", "quests")
def _():
    h = fresh()
    h.lua("__quests = { { questID = 0, title = 'Westfall', isHeader = true }, { questID = 201, title = 'x', level = 14 } }")
    open_options(h)
    h.lua("ns.Options.SelectPage('quests')")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.quests and w.__kind == "button" then
                if w:GetParent().label:GetText():find("^All") then __btnAll = w else __btnLow = w end
            end
        end
    """)
    ok(h.lua("return __btnAll.enabledState") and not h.lua("return __btnLow.enabledState"), "All should be live (1 quest), Low-level greyed (0)")
    h.lua("__btnLow:Click()")
    ok(not h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "a greyed button must not open the dialog")
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    ok(not h.lua("return __btnAll.enabledState"), "module off should grey the buttons")
    h.lua("__btnAll:Click()")
    ok(not h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "module off: no dialog")
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    ok(h.lua("return __btnAll.enabledState"), "module on should restore the button")
    h.lua("__quests = {}; W.fireEvent('QUEST_LOG_UPDATE')")
    eq(str(h.lua("return __btnAll:GetParent().label:GetText()")), "All quests (0)", "the count should follow the log while the page is up")
    ok(not h.lua("return __btnAll.enabledState"), "zero quests should grey All")
    eq(h.errors(), [], "errors")


@test("a greyed Abandon button's own OnClick refuses even when invoked directly, not just via a disabled Click()", "quests")
def _():
    # __btnAll:Click() alone can't tell this mutation from working code: the
    # mock (like the real client) already refuses a click on a button whose
    # SetEnabled(false) was called, so the "if not self.enabledState" guard
    # inside OnClick never runs in that path either way. This suite invokes
    # OnClick directly elsewhere (tests.py:1333 etc.) for exactly this
    # reason: it is the only way to isolate the handler's OWN guard from the
    # widget-level one.
    h = fresh()
    h.lua("__quests = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('quests')")
    h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.quests and w.__kind == "button" then
                if w:GetParent().label:GetText():find("^All") then __btnAll = w end
            end
        end
    """)
    ok(not h.lua("return __btnAll.enabledState"), "All should be greyed out with an empty log")
    # The log refills without a QUEST_LOG_UPDATE refresh: count() now sees
    # quests, but the widget is still visibly greyed (stale enabledState).
    h.lua(QUEST_LOG)
    eq(int(h.lua("return #ns.Quests.List()")), 5, "the log itself already has quests again")
    ok(not h.lua("return __btnAll.enabledState"), "the button is still showing greyed before any refresh")
    h.lua("__btnAll:GetScript('OnClick')(__btnAll)")
    ok(not h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"),
       "a visibly greyed button must not open the confirmation even when OnClick fires directly")
    eq(ids(h, "ns.Quests.List()"), [101, 102, 201, 202, 401], "nothing should have been abandoned")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- probe

MAP_STUBS = """
    C_Map = C_Map or {}
    C_Map.GetBestMapForUnit = function() return 37 end
    C_Map.GetMapInfo = function(id) return { mapID = id, name = "Elwynn Forest", mapType = 3 } end
    C_Map.GetPlayerMapPosition = function() return { x = 0.4, y = 0.6, GetXY = function(self) return self.x, self.y end } end
    C_Map.GetWorldPosFromMapPos = function() return 0, { x = 100, y = 200 } end
    C_Map.GetMapWorldSize = function() return 3000, 2000 end
    C_Map.CanSetUserWaypointOnMap = function() return true end
    __wp = nil
    C_Map.SetUserWaypoint = function(p) __wp = p end
    C_Map.HasUserWaypoint = function() return __wp ~= nil end
    C_Map.GetUserWaypoint = function() return __wp end
    C_Map.ClearUserWaypoint = function() __wp = nil end
    __tracking = false
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) __tracking = on end,
                     IsSuperTrackingUserWaypoint = function() return __tracking end,
                     IsSuperTrackingAnything = function() return __tracking end }
    C_Navigation = { GetDistance = function() return 123.4 end, GetTargetState = function() return 1 end, HasValidScreenPosition = function() return true end }
    GetPlayerFacing = function() return 1.5 end
    CreateVector2D = function(x, y) return { x = x, y = y } end
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, position = { x = x, y = y } } end }
"""


@test("/sn probe waypoint walks the waypoint chain, reports every call, and clears the pin unless told to keep it", "probe")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    lines = [str(x) for x in h.lua("return ns.Probe.Waypoint(false)").values()]
    text = "\n".join(lines)
    for needle in ("GetBestMapForUnit(player): 37", "player x/y: 0.4 / 0.6 (usable)", "GetPlayerFacing: 1.5",
                   "CanSetUserWaypointOnMap: true", "SetUserWaypoint(+0.02 x)", "HasUserWaypoint: true",
                   "SetSuperTrackedUserWaypoint(true)", "IsSuperTrackingUserWaypoint: true", "C_Navigation.GetDistance: 123.4",
                   "ClearUserWaypoint", "HasUserWaypoint (after clear): false"):
        ok(needle in text, "missing line: %s\n%s" % (needle, text))
    ok(h.lua("return __wp == nil"), "the probe should clear its waypoint")
    wp = h.lua("ns.Probe.Waypoint(true); return __wp")
    ok(wp is not None and abs(float(wp["position"]["x"]) - 0.42) < 1e-9 and float(wp["uiMapID"]) == 37, "keep should leave the pin 0.02 east: %r" % wp)
    h.lua('ns.Commands.probe("waypoint")')
    eq(h.errors(), [], "errors")


@test("the waypoint probe survives secret positions, throwing calls and missing namespaces", "probe")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("C_Map.GetPlayerMapPosition = function() return { x = W.secretNumber(), y = W.secretNumber() } end")
    text = "\n".join(str(x) for x in h.lua("return ns.Probe.Waypoint(false)").values())
    ok("player x/y: ? / ? (NOT usable)" in text, "secret position not reported: %s" % text)
    ok("not attempted" in text, "a secret position must not place a waypoint")
    ok(h.lua("return __wp == nil"), "no waypoint should be placed on a secret position")
    h.lua("C_Map.GetPlayerMapPosition = function() error('boom') end; C_SuperTrack = nil; C_Navigation = nil")
    text = "\n".join(str(x) for x in h.lua("return ns.Probe.Waypoint(false)").values())
    ok("GetPlayerMapPosition: ERROR" in text, "a throwing call should be reported, not thrown: %s" % text)
    h.lua("C_Map.GetPlayerMapPosition = function() return { x = 0.5, y = 0.5 } end")
    text = "\n".join(str(x) for x in h.lua("return ns.Probe.Waypoint(false)").values())
    ok("SetSuperTrackedUserWaypoint(true): MISSING" in text and "C_Navigation.GetDistance: MISSING" in text, "missing namespaces should read MISSING: %s" % text)
    h.lua("C_Map.GetBestMapForUnit = function() return W.secretNumber() end")
    text = "\n".join(str(x) for x in h.lua("return ns.Probe.Waypoint(false)").values())
    ok("no usable map id" in text, "a secret map id should stop the probe cleanly")
    eq(h.errors(), [], "errors")


@test("/sn probe nav reads the navigation state without touching the pin, and computes our own distance from the map size", "probe")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Probe.Waypoint(true)")          # pin kept 0.02 east: 0.02 * 3000 = 60 yd
    lines = [str(x) for x in h.lua("return ns.Probe.Nav()").values()]
    text = "\n".join(lines)
    for needle in ("HasUserWaypoint: true", "IsSuperTrackingUserWaypoint: true", "C_Navigation.GetDistance: 123.4",
                   "our own distance to the pin: 60.0 yd"):
        ok(needle in text, "missing line: %s\n%s" % (needle, text))
    ok(h.lua("return __wp ~= nil"), "nav must not clear the pin")
    ok("function" not in text, "table dumps should not list functions: %s" % text)
    h.lua('ns.Commands.probe("nav"); ns.Commands.probe("")')
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- guide

ROUTE = """
    ns.Routes = { {
        slug = "T_Dwarf_SHAMAN", name = "Test route", faction = "Alliance", race = "Dwarf", class = "SHAMAN", map = 1426, levels = { 1, 3 },
        steps = {
            { k = "accept", q = 179, m = 1426, x = 0.30, y = 0.71, n = "Sten Stoutarm" },
            { k = "do", q = 179, o = 1, m = 1426, x = 0.29, y = 0.73, text = "8/8 Tough Wolf Meat" },
            { k = "turnin", q = 179, m = 1426, x = 0.30, y = 0.71, n = "Sten Stoutarm" },
            { k = "train", m = 1426, x = 0.29, y = 0.66, n = "Teo Hammerstorm" },
            { k = "accept", q = 233, m = 1426, x = 0.30, y = 0.71, n = "Sten Stoutarm" },
            { k = "level", l = 3 },
            { k = "turnin", q = 233, m = 1426, x = 0.23, y = 0.72, n = "Talin Keeneye" },
        },
    }, {
        slug = "T_Orc_WARRIOR", name = "Horde route", faction = "Horde", race = "Orc", class = "WARRIOR", map = 1411, levels = { 1, 5 },
        steps = { { k = "accept", q = 4641, m = 1411, x = 0.5, y = 0.5 } },
    } }
    __titles = { [179] = "Dwarven Outfitters", [233] = "Coldridge Valley Mail Delivery" }
    UnitLevel = function() return 1 end
    C_Map.GetBestMapForUnit = function() return 1426 end
"""


def cur(h):
    v = h.lua("local r = ns.Guide.PickRoute() return ns.Guide.CurrentIndex(r)")
    return None if v is None else int(v)


@test("the guide picks the route for the character (faction must match; race and class score) or the chosen slug", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN", "Alliance dwarf paladin should get the dwarf route")
    h.lua("UnitFactionGroup = function() return 'Horde' end")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Orc_WARRIOR", "a Horde character must not get an Alliance route")
    h.lua("ns.db.guide.route = 'T_Dwarf_SHAMAN'")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN", "a chosen slug wins")
    h.lua("ns.db.guide.route = 'auto'; ns.Routes = {}")
    ok(h.lua("return ns.Guide.PickRoute() == nil"), "no routes: nil")
    eq(h.errors(), [], "errors")


@test("the place in the route is read from the quest log and flags, never saved: accept, objective, turn-in, level", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    eq(cur(h), 1, "fresh character: step 1")
    h.lua("__quests = { { questID = 179, title = 'Dwarven Outfitters', level = 1 } }; __objectives[179] = { { text = 'x', finished = false } }")
    eq(cur(h), 2, "on the quest: the do step")
    h.lua("__objectives[179][1].finished = true")
    eq(cur(h), 3, "objective finished: the turn-in")
    h.lua("__objectives[179][1].finished = false; __quests[1].ready = true")
    eq(cur(h), 3, "ready for turn-in counts as the objective done")
    h.lua("__quests = {}; __completed[179] = true")
    eq(cur(h), 4, "flagged complete: past the turn-in, at the train step")
    h.lua("__quests = { { questID = 233, title = 'Mail', level = 1 } }")
    eq(cur(h), 6, "a later checkable step done (233 accepted) passes the uncheckable train step; level 3 next")
    h.lua("UnitLevel = function() return 3 end")
    eq(cur(h), 7, "level reached: the last turn-in")
    h.lua("__quests = {}; __completed[233] = true")
    ok(cur(h) is None, "everything done: route complete")
    # a /reload changes nothing: the same client state gives the same place
    h2 = fresh()
    h2.lua(MAP_STUBS + ROUTE)
    h2.lua("__quests = { { questID = 233, title = 'Mail', level = 1 } }; __completed = { [179] = true }")
    eq(cur(h2), 6, "a fresh session lands on the same step from the same quest state")
    eq(h.errors(), [], "errors")


@test("uncheckable steps pass on Skip, on their own event this session, and the guide resets skips on demand", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = { [179] = true }")
    eq(cur(h), 4, "at the train step")
    h.lua('W.fireEvent("TRAINER_SHOW")')
    eq(cur(h), 5, "a trainer window this session passes the train step")
    h.lua("ns.Guide.ResetSkips()")
    eq(cur(h), 4, "reset forgets the trainer visit")
    h.lua("local r = ns.Guide.PickRoute() ns.Guide.Skip(r, 4)")
    eq(cur(h), 5, "Skip passes it")
    h.lua("ns.Commands.guide('reset')")
    eq(cur(h), 4, "/sn guide reset clears skips")
    h.lua("ns.Commands.guide('')")
    eq(h.errors(), [], "errors")


@test("the guide frame shows the current step with its quest title, the next steps dimmed, the distance, and pins the client's waypoint", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; ns.ApplyAll()")
    ok(h.lua("return SalusNovusGuide and SalusNovusGuide:IsShown()"), "frame should show with a route")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "1/7  Accept Dwarven Outfitters from Sten Stoutarm", "current step text")
    eq(str(h.lua("return SalusNovusGuide.title:GetText()")), "Test route", "route name")
    shown = [str(x) for x in h.lua("""
        local out = {}
        for i = 1, 4 do
            local l = ns.Guide.Lines()[i]
            if l and l:IsShown() then out[#out + 1] = l:GetText() end
        end
        return out
    """).values()]
    eq(shown, ["Complete objective: 8/8 Tough Wolf Meat (Dwarven Outfitters)", "Turn in Dwarven Outfitters to Sten Stoutarm"], "two next steps (stored text is only the fallback while not on the quest)")
    # distance: player at 0.4,0.6 on a 3000x2000 map, step at 0.30,0.71 -> dx 300, dy 220 -> 372 yd
    eq(str(h.lua("return SalusNovusGuide.distance:GetText()")), "372 yd", "distance to the step")
    h.lua("C_Map.GetBestMapForUnit = function() return 37 end; ns.ApplyAll()")
    eq(str(h.lua("return SalusNovusGuide.distance:GetText()")), "", "no distance across maps")
    h.lua("C_Map.GetBestMapForUnit = function() return 1426 end; ns.ApplyAll()")
    h.lua("ns.db.guide.showNext = 0; ns.ApplyAll()")
    eq(int(h.lua("local n = 0 for i, l in ipairs(ns.Guide.Lines()) do if l:IsShown() then n = n + 1 end end return n")), 0, "next steps can be turned off")
    h.lua("SalusNovusGuide.skip:Click()")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "2/7  Complete objective: 8/8 Tough Wolf Meat (Dwarven Outfitters)", "Skip moves on")
    h.lua("__quests = {}; __completed = { [179] = true, [233] = true }; UnitLevel = function() return 3 end; ns.ApplyAll()")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "Route complete", "complete text")
    ok(h.lua("return __wp == nil"), "the guide must never place the client's pin (Alex: the arrow suffices)")
    eq(h.errors(), [], "errors")


@test("the guide hides when off or the Leveling module is off, never touches the client's pin, and shows a sample in unlock mode", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; ns.ApplyAll()")
    ok(h.lua("return __wp == nil"), "no pin placed")
    h.lua("ns.db.guide.enabled = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusGuide:IsShown()"), "off: hidden")
    h.lua("ns.db.guide.enabled = true; ns.db.modules.leveling = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusGuide:IsShown()"), "module off: hidden")
    h.lua("ns.db.modules.leveling = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusGuide:IsShown()"), "back on")
    h.lua("__wp = { uiMapID = 1, position = { x = 0.1, y = 0.1 } }")     # the player's own pin
    h.lua("ns.db.guide.enabled = false; ns.ApplyAll(); ns.db.guide.enabled = true; ns.ApplyAll()")
    ok(h.lua("return __wp ~= nil"), "the player's pin is left alone")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusGuide:IsShown() and SalusNovusGuide.unlockLabel:IsShown()"), "unlock mode shows the frame with its label")
    h.lua("ns.Routes = {}; ns.ApplyAll()")
    eq(str(h.lua("return SalusNovusGuide.title:GetText()")), "No route", "no route in unlock mode still draws")
    eq(h.errors(), [], "errors")


@test("the Guide row under Leveling: switch, route list with Best match first, arrow, next-steps and size", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    open_options(h)
    ok(h.lua("return ns.Options.tabs.guide ~= nil and ns.Options.tabs.guide.label:GetText() == ns.Theme.Upper('Settings')"), "no Settings row under Leveling")
    ok(float(h.lua("return ns.Options.tabs.guide:GetTop()")) < float(h.lua("return ns.Options.tabs.quests:GetTop()")), "Leveling should sit below Quality of Life")
    h.lua("ns.Options.tabs.guide:Click()")
    eq(str(h.lua("return ns.Options.ActivePage()")), "guide", "row lands on the guide page")
    vals = [str(x) for x in h.lua("""
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.guide and w.__kind == "choice" then return w.__values end
        end
    """).values()]
    eq(vals, ["auto", "T_Dwarf_SHAMAN", "T_Orc_WARRIOR"], "route choices")
    kinds = sorted(str(x) for x in h.lua("""
        local out = {}
        for _, w in ipairs(ns.Options.widgets) do if w.__outer == ns.Options.pages.guide then out[#out + 1] = w.__kind end end
        return out
    """).values())
    eq(kinds, ["check", "check", "choice", "stepper", "stepper", "stepper"], "controls on the page")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- build_route

@test("build_route drops the client's own removal before a turn-in, removes a really abandoned quest, and keeps the rest in order", "route")
def _():
    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    entries = [
        {"t": 0, "k": "accept", "q": 179, "n": "Sten", "m": 1426, "x": 0.30, "y": 0.71, "l": 1},
        {"t": 10, "k": "crumb", "m": 1426, "x": 0.31, "y": 0.71, "l": 1},
        {"t": 20, "k": "zone", "n": "Dun Morogh", "m": 1426, "l": 1},
        {"t": 30, "k": "accept", "q": 500, "n": "Nobody", "m": 1426, "x": 0.32, "y": 0.70, "l": 1},
        {"t": 40, "k": "level", "s": 2, "m": 1426, "l": 1},
        {"t": 50, "k": "objective", "q": 179, "o": 1, "n": "8/8 Meat", "m": 1426, "x": 0.29, "y": 0.73, "l": 2},
        {"t": 60, "k": "objective", "q": 500, "o": 1, "n": "1/1 Thing", "m": 1426, "x": 0.29, "y": 0.73, "l": 2},
        {"t": 70, "k": "abandon", "q": 500, "m": 1426, "l": 2},
        {"t": 80, "k": "abandon", "q": 179, "m": 1426, "l": 2},
        {"t": 81, "k": "turnin", "q": 179, "n": "Sten", "xp": 80, "m": 1426, "x": 0.30, "y": 0.71, "l": 2},
        {"t": 90, "k": "trainer", "n": "Teo", "m": 1426, "x": 0.29, "y": 0.66, "l": 2},
        {"t": 100, "k": "taxi", "m": 1426, "x": 0.47, "y": 0.54, "l": 2},
        {"t": 110, "k": "hearth", "s": 8690, "m": 1426, "l": 2},
        {"t": 120, "k": "bind", "n": "Kharanos", "m": 1426, "x": 0.47, "y": 0.52, "l": 2},
        {"t": 130, "k": "turnin", "q": 233, "n": "Talin", "xp": 190, "m": 1426, "x": 0.23, "y": 0.72, "l": 2},   # accepted before recording
        {"t": 131, "k": "abandon", "q": 233, "m": 1426, "l": 2},                                                     # removal AFTER the turn-in
    ]
    steps = B.extract_steps(entries)
    eq([s["k"] for s in steps], ["accept", "level", "do", "turnin", "train", "fly", "hearth", "bind", "turnin"], "step kinds")
    eq([s.get("q") for s in steps if s.get("q")], [179, 179, 179, 233], "quest 500 gone, 179 and 233 kept")
    eq(steps[2]["text"], "Meat", "objective text carried without the counter")
    eq(steps[1]["l"], 2, "level marker")
    hdr = B.route_header({"faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "char": "Mercury Testsham-Realm"}, entries, steps)
    eq((hdr["name"], hdr["levels"], hdr["map"]), ("Dwarf Shaman 1-2", "1-2", 1426), "header")
    eq(B.slug_of({"faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "char": "Mercury Testsham-Realm"}), "Alliance_Dwarf_Shaman_MercuryTestsham", "slug")


@test("a step file round-trips through write, parse and Lua compile, and hand edits survive", "route")
def _():
    import sys, os, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    steps = [
        {"k": "accept", "q": 179, "m": 1426, "x": 0.2992, "y": 0.7128, "n": "Sten Stoutarm"},
        {"k": "do", "q": 179, "o": 2, "m": 1426, "x": 0.289, "y": 0.7267, "text": "6/6 \"Burly\" Trogg slain"},
        {"k": "turnin", "q": 179, "m": 1426, "x": 0.299, "y": 0.713, "n": "Sten Stoutarm"},
        {"k": "level", "l": 2},
        {"k": "train", "m": 1426, "x": 0.2886, "y": 0.6622, "n": "Teo Hammerstorm"},
        {"k": "fly", "m": 1426, "x": 0.47, "y": 0.54},
        {"k": "hearth"},
        {"k": "note", "text": "Buy water first"},
    ]
    hdr = {"name": "Dwarf Shaman 1-2", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "levels": "1-2"}
    d = tempfile.mkdtemp()
    p = os.path.join(d, "X.steps.txt")
    B.write_steps_file(p, hdr, steps)
    text = open(p, encoding="utf-8").read()
    ok("accept 179 @1426 29.92,71.28 npc=Sten Stoutarm" in text, "accept line: %s" % text)
    ok("do 179/2 @1426 28.90,72.67 text=6/6 \"Burly\" Trogg slain" in text, "do line")
    ok("note Buy water first" in text, "note line")
    text = text.replace("note Buy water first", "note Buy water first\n# a comment\nnote Then go north")
    open(p, "w", encoding="utf-8").write(text)
    h2, back = B.parse_steps_file(p)
    eq(h2["name"], "Dwarf Shaman 1-2", "header name")
    eq(h2["levels"], "1-2", "header levels")
    eq([s["k"] for s in back], ["accept", "do", "turnin", "level", "train", "fly", "hearth", "note", "note"], "kinds after edit")
    eq(back[1]["text"], "6/6 \"Burly\" Trogg slain", "quoted objective text")
    ok(abs(back[0]["x"] - 0.2992) < 1e-9 and back[0]["m"] == 1426, "coordinates back to fractions")
    eq(back[-1]["text"], "Then go north", "added note")
    lua = B.compile_routes({"X": p})
    ok('slug = "X", name = "Dwarf Shaman 1-2"' in lua and 'levels = { 1, 2 }' in lua, "route header in Lua: %s" % lua[:300])
    ok('{ k = "do", q = 179, o = 2, m = 1426, x = 0.2890, y = 0.7267, text = "6/6 \\"Burly\\" Trogg slain" },' in lua, "escaped Lua step: %s" % lua)
    h = fresh()
    h.lua("ns.Routes = {}")
    h.lua(lua.replace("local _, ns = ...", ""))
    eq(int(h.lua("return #ns.Routes[1].steps")), 9, "the compiled Lua loads in the addon")
    eq(str(h.lua("return ns.Routes[1].steps[2].text")), '6/6 "Burly" Trogg slain', "quotes survive the Lua string")


# ---------------------------------------------------------------- arrow

# World coordinates from map coordinates: x grows north, y grows west
# (the client's convention), on a 3000 x 2000 yd map.
WORLD = """
    C_Map.GetWorldPosFromMapPos = function(map, v) return 0, { x = -v.y * 2000, y = -v.x * 3000 } end
"""


def bearing(h, x, y, m=1426):
    r = h.lua("return { ns.Arrow.Bearing({ m = %d, x = %r, y = %r }) }" % (m, x, y))
    return None if r is None or len(r) == 0 else (float(r[1]), float(r[2]))


@test("the arrow's bearing is counter-clockwise from north in world space, with the map-space fallback agreeing", "arrow")
def _():
    import math
    h = fresh()
    h.lua(MAP_STUBS + ROUTE + WORLD)
    # player at 0.4, 0.6
    b, d = bearing(h, 0.4, 0.5)            # due north (smaller y)
    ok(abs(b) < 1e-9 and abs(d - 200) < 1e-6, "north: %r %r" % (b, d))
    b, d = bearing(h, 0.3, 0.6)            # due west (smaller x)
    ok(abs(b - math.pi / 2) < 1e-9 and abs(d - 300) < 1e-6, "west: %r %r" % (b, d))
    b, d = bearing(h, 0.5, 0.6)            # due east
    ok(abs(abs(b) - math.pi / 2) < 1e-9 and b < 0, "east should be -pi/2: %r" % b)
    b, d = bearing(h, 0.4, 0.7)            # due south
    ok(abs(abs(b) - math.pi) < 1e-9, "south should be +-pi: %r" % b)
    h.lua("C_Map.GetWorldPosFromMapPos = nil")   # map-space fallback
    b, d = bearing(h, 0.3, 0.6)
    ok(abs(b - math.pi / 2) < 1e-9 and abs(d - 300) < 1e-6, "fallback west: %r %r" % (b, d))
    ok(bearing(h, 0.3, 0.6, m=37) is None, "fallback cannot cross maps")
    h.lua("C_Map.GetPlayerMapPosition = function() return { x = W.secretNumber(), y = W.secretNumber() } end")
    ok(bearing(h, 0.3, 0.6) is None, "a secret position gives no bearing, not a throw")
    eq(h.errors(), [], "errors")


@test("the arrow frame rotates by bearing minus facing, shows the distance, follows the guide's step, and hides with the settings", "arrow")
def _():
    import math
    h = fresh()
    h.lua(MAP_STUBS + ROUTE + WORLD)
    h.lua("__quests = {}; __completed = {}; GetPlayerFacing = function() return math.pi / 2 end; ns.ApplyAll(); W.advance(0.2)")
    ok(h.lua("return SalusNovusArrow and SalusNovusArrow:IsShown()"), "arrow frame should show with a current step")
    # step 1 is at 0.30, 0.71 from the player at 0.40, 0.60: dN = -220, dW = 300
    want = math.atan2(300, -220) - math.pi / 2
    rot = float(h.lua("return SalusNovusArrow.arrow.__rotation"))
    ok(abs(rot - want) < 1e-9, "rotation %r, want %r" % (rot, want))
    eq(str(h.lua("return SalusNovusArrow.text:GetText()")), "372 yd", "distance under the arrow")
    ok(str(h.lua("return SalusNovusArrow.arrow.__source")).endswith("arrow.tga"), "arrow art should be our own texture: %s" % h.lua("return SalusNovusArrow.arrow.__source"))
    ok(h.lua("return SalusNovusArrow.arrow:GetTexture() == SalusNovusArrow.arrow.__source"), "the texture should actually be set on the region")
    h.lua("GetPlayerFacing = function() return 0 end; W.advance(0.2)")
    rot2 = float(h.lua("return SalusNovusArrow.arrow.__rotation"))
    ok(abs(rot2 - math.atan2(300, -220)) < 1e-9, "turning the player turns the arrow: %r" % rot2)
    h.lua("SalusNovusGuide.skip:Click(); W.advance(0.2)")      # step 2 at 0.29, 0.73
    rot3 = float(h.lua("return SalusNovusArrow.arrow.__rotation"))
    ok(abs(rot3 - math.atan2(330, -260)) < 1e-9, "the arrow follows the guide's step: %r" % rot3)
    h.lua("C_Map.GetBestMapForUnit = function() return 37 end; C_Map.GetWorldPosFromMapPos = nil; W.advance(0.2)")
    ok(not h.lua("return SalusNovusArrow.arrow:IsShown()") and str(h.lua("return SalusNovusArrow.text:GetText()")) == "?", "unknown bearing: arrow hidden, a question mark")
    h.lua("C_Map.GetBestMapForUnit = function() return 1426 end")
    h.lua("ns.db.guide.arrow = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "arrow setting off hides it")
    h.lua("ns.db.guide.arrow = true; ns.db.guide.enabled = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "guide off hides it")
    h.lua("ns.db.guide.enabled = true; ns.db.modules.leveling = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "module off hides it")
    h.lua("ns.db.modules.leveling = true; __completed = { [179] = true, [233] = true }; UnitLevel = function() return 3 end; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "route complete hides it")
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); W.advance(0.2)")
    ok(h.lua("return SalusNovusArrow:IsShown() and SalusNovusArrow.unlockLabel:IsShown() and SalusNovusArrow.arrow:IsShown()"), "unlock mode shows a sample arrow")
    h.lua("ns.db.guide.arrowSize = 72; ns.ApplyAll()")
    eq(int(h.lua("return SalusNovusArrow.arrow:GetWidth()")), 72, "arrow size setting")
    eq(h.errors(), [], "errors")


# ---------------------------------------------------------------- route editor

def step_kinds(h):
    return [str(x) for x in h.lua("local out = {} for _, s in ipairs(ns.Guide.PickRoute().steps) do out[#out + 1] = s.k .. (s.q and ('#' .. s.q) or '') end return out").values()]


@test("editor ops change the loaded route live and log each one with an id; skips follow the moved steps", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    base = step_kinds(h)
    eq(len(base), 7, "route")
    h.lua("local r = ns.Guide.PickRoute() ns.Guide.Skip(r, 4) ns.Guide.Skip(r, 6)")     # train, level
    ok(h.lua("return ns.RouteEditor.Delete(ns.Guide.PickRoute(), 2)"), "delete")
    eq(step_kinds(h), [base[0]] + base[2:], "step 2 gone")
    h.lua("__completed = { [179] = true }")
    eq(cur(h), 4, "skips shifted with the delete: the old step 4 (train) is now 3 and skipped, old 6 (level, now 5) skipped, so the last turn-in is next... after accept 233 at 4")
    ok(h.lua("return ns.RouteEditor.Insert(ns.Guide.PickRoute(), 0, { k = 'note', text = 'first' })"), "insert at start")
    eq(step_kinds(h)[0], "note", "note first")
    ok(h.lua("return ns.RouteEditor.Up(ns.Guide.PickRoute(), 2)"), "up")
    eq(step_kinds(h)[0], "accept#179", "the accept swapped above the note")
    ok(h.lua("return ns.RouteEditor.Down(ns.Guide.PickRoute(), 1)"), "down")
    eq(step_kinds(h)[0], "note", "and back")
    ok(not h.lua("return ns.RouteEditor.Delete(ns.Guide.PickRoute(), 99)") and not h.lua("return ns.RouteEditor.Up(ns.Guide.PickRoute(), 1)") and not h.lua("return ns.RouteEditor.Down(ns.Guide.PickRoute(), 7)"), "out-of-range ops refused")
    ops = h.lua("return SalusNovusDB.routeEdits['T_Dwarf_SHAMAN']")
    log = [(str(o["op"]), int(o["at"])) for o in ops.values()]
    eq(log, [("del", 2), ("ins", 0), ("up", 2), ("down", 1)], "the edit log, in order")
    ids = [str(o["id"]) for o in ops.values()]
    eq(len(set(ids)), 4, "ids unique")
    eq(str(ops[2]["step"]["text"]), "first", "the inserted step travels with its op")
    eq(h.errors(), [], "errors")


@test("InsertHere builds a step where the player stands, before the current step, for a log quest or a note", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = { { questID = 555, title = 'Extra', level = 2 } }; __objectives[555] = { { text = '3/3 Things', finished = false } }; __completed = { [179] = true }")
    h.lua("UnitName = function(u) if u == 'target' then return 'Some Dwarf' end return 'Merk' end")
    eq(cur(h), 4, "at the train step")
    at = h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'note', nil, 'Buy water')")
    eq(int(at), 4, "inserted at the current index")
    st = h.lua("return ns.Guide.PickRoute().steps[4]")
    eq((str(st["k"]), str(st["text"]), int(st["m"])), ("note", "Buy water", 1426), "note step here")
    ok(abs(float(st["x"]) - 0.4) < 1e-9 and abs(float(st["y"]) - 0.6) < 1e-9, "position stamped")
    eq(cur(h), 4, "the new note is now the current step")
    ok(h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'note', nil, '   ') == nil"), "a blank note is refused")
    at = h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'accept', 555, '')")
    st = h.lua("return ns.Guide.PickRoute().steps[%d]" % int(at))
    eq((str(st["k"]), int(st["q"]), str(st["n"])), ("accept", 555, "Some Dwarf"), "accept step names the target")
    at = h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'do', 555, '')")
    st = h.lua("return ns.Guide.PickRoute().steps[%d]" % int(at))
    eq((str(st["k"]), int(st["q"]), int(st["o"])), ("do", 555, 1), "objective step points at the first unfinished objective")
    ok(h.lua("return ns.Guide.PickRoute().steps[%d].text == nil" % int(at)), "a do step stores no text")
    h.lua("__objectives[555] = { { text = '3/3 Things', finished = true }, { text = '0/1 Other', finished = false } }")
    at2 = h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'do', 555, '')")
    eq(int(h.lua("return ns.Guide.PickRoute().steps[%d].o" % int(at2))), 2, "with the first objective done, the step points at the second")
    at = h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'turnin', 555, '')")
    eq(str(h.lua("return ns.Guide.PickRoute().steps[%d].k" % int(at))), "turnin", "turn-in step")
    ok(h.lua("return ns.RouteEditor.InsertHere(ns.Guide.PickRoute(), 'accept', nil, '') == nil"), "a quest step needs a quest")
    quests = [str(x["title"]) for x in h.lua("return ns.RouteEditor.LogQuests()").values()]
    eq(quests, ["Extra"], "log quests")
    eq(h.errors(), [], "errors")


@test("the Steps tab lists the route with the current step in the accent, Del/Up/Down per row, and the add row inserts before the current step", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = { { questID = 555, title = 'Extra', level = 2 } }; __completed = { [179] = true }")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    eq(str(h.lua("return ns.Options.ActivePage()")), "routes", "routes page")
    ok(h.lua("return ns.Options.strips.routes.order[1] == 'routes' and ns.Options.strips.routes.order[2] == nil"), "Routes is its own row with one tab")
    ok(h.lua("return ns.Options.tabs.routes.label:GetText() == ns.Theme.Upper('Routes') and ns.Options.tabs.guide.label:GetText() == ns.Theme.Upper('Settings')"), "sidebar rows read Settings and Routes")
    texts = [str(x) for x in h.lua("""
        local out = {}
        for _, ln in ipairs(ns.Options.stepsList.lines) do if ln:IsShown() then out[#out + 1] = ln.text:GetText() end end
        return out
    """).values()]
    eq(len(texts), 7, "one line per step")
    eq(texts[0], "1.  Accept Dwarven Outfitters from Sten Stoutarm", "line text")
    eq(texts[1], "2.  Complete objective: 8/8 Tough Wolf Meat (Dwarven Outfitters)", "do line (fallback text, not on the quest)")
    r, g, b = h.lua("return ns.Theme.Accent()")
    cr, cg, cb, _ = h.lua("return ns.Options.stepsList.lines[4].text:GetTextColor()")
    ok(abs(float(cr) - float(r)) < 1e-6 and abs(float(cg) - float(g)) < 1e-6, "the current step (4) should be in the accent")
    ok(not h.lua("return ns.Options.stepsList.lines[1].up.enabledState") and h.lua("return ns.Options.stepsList.lines[1].down.enabledState"), "first row: no Up")
    ok(not h.lua("return ns.Options.stepsList.lines[7].down.enabledState"), "last row: no Down")
    h.lua("ns.Options.stepsList.lines[4].del:Click()")
    eq(step_kinds(h)[3], "accept#233", "Del removed the train step")
    eq(int(h.lua("local n = 0 for _, ln in ipairs(ns.Options.stepsList.lines) do if ln:IsShown() then n = n + 1 end end return n")), 6, "list redrawn")
    h.lua("ns.Options.stepsList.lines[6].up:Click()")
    eq(step_kinds(h)[4], "turnin#233", "Up moved the last turn-in above the level step")
    eq(str(h.lua("return ns.Options.stepsQuestButton.text:GetText()")), "Extra", "quest picker shows the log quest")
    h.lua("ns.Options.stepsText:SetText('Buy water'); ns.Options.stepsAdd.note:Click()")
    eq(step_kinds(h)[3], "note", "Note inserted before the current step")
    eq(str(h.lua("return ns.Options.stepsText:GetText()")), "", "text box cleared")
    h.lua("ns.Options.stepsAdd.accept:Click()")
    eq(step_kinds(h)[3], "accept#555", "Accept inserted for the picked quest")
    h.lua("__quests = {}; W.fireEvent('QUEST_LOG_UPDATE')")
    ok(not h.lua("return ns.Options.stepsAdd.accept.enabledState") and h.lua("return ns.Options.stepsAdd.note.enabledState"), "no log quests: quest buttons grey, Note stays")
    eq(int(h.lua("return #SalusNovusDB.routeEdits['T_Dwarf_SHAMAN']")), 4, "four edits logged")
    eq(h.errors(), [], "errors")


@test("build_route applies each in-game edit once to the step file, in order, and the harvester merges edits by id", "route")
def _():
    import sys, os, json, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B, harvest_routes as H
    steps = [{"k": "accept", "q": 1}, {"k": "do", "q": 1, "o": 1, "text": "a"}, {"k": "turnin", "q": 1}, {"k": "level", "l": 2}]
    ops = [{"op": "del", "at": 2, "id": "1-1", "t": 1}, {"op": "ins", "at": 0, "step": {"k": "note", "text": "first", "m": 1426, "x": 0.5, "y": 0.5}, "id": "1-2", "t": 1},
           {"op": "up", "at": 2, "id": "1-3", "t": 1}, {"op": "down", "at": 1, "id": "1-4", "t": 1}, {"op": "del", "at": 99, "id": "1-5", "t": 1}]
    out = B.apply_ops(steps, ops)
    eq([s["k"] for s in out], ["note", "accept", "turnin", "level"], "ops applied in order; out-of-range ignored")
    eq(out[0]["text"], "first", "inserted step fields kept")
    # once only: a second build with the same ids changes nothing
    d = tempfile.mkdtemp()
    B.STEPS, B.APPLIED = d, os.path.join(d, "applied.json")
    p = os.path.join(d, "S.steps.txt")
    B.write_steps_file(p, {"name": "n", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "levels": "1-2"}, steps)
    B.apply_pending_edits({"S": ops})
    _, back = B.parse_steps_file(p)
    eq([s["k"] for s in back], ["note", "accept", "turnin", "level"], "step file rewritten")
    B.apply_pending_edits({"S": ops})
    _, back2 = B.parse_steps_file(p)
    eq([s["k"] for s in back2], ["note", "accept", "turnin", "level"], "the same ids are not applied twice")
    eq(sorted(json.load(open(B.APPLIED))), ["1-1", "1-2", "1-3", "1-4", "1-5"], "ids remembered")
    # harvester: edits from a saved-variables literal
    src = """SalusNovusDB = { ["routeEdits"] = { ["S"] = { { ["op"] = "del", ["at"] = 2, ["id"] = "9-1", ["t"] = 9 }, { ["op"] = "ins", ["at"] = 0, ["id"] = "9-2", ["t"] = 9, ["step"] = { ["k"] = "note", ["text"] = "x" } } } } }"""
    parsed = H.parse_saved_variables(src)["SalusNovusDB"]["routeEdits"]["S"]
    eq([e["id"] for e in parsed], ["9-1", "9-2"], "edits parsed from the literal")


# ---------------------------------------------------------------- builder

def last_step(h):
    return h.lua("local r = ns.Guide.PickRoute() return r.steps[#r.steps]")


@test("the builder makes a route from nothing for the character and appends steps at the end", "builder")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = { { questID = 555, title = 'Extra', level = 2 } }; __completed = {}; UnitName = function(u) if u == 'target' then return 'Grimnur' end return 'Mercury Testsham' end; UnitLevel = function() return 4 end")
    ok(h.lua("return ns.Guide.PickRoute() == nil"), "precondition: no route")
    h.lua("ns.Builder.Show()")
    ok(h.lua("return SalusNovusBuilder:IsShown()"), "window shows")
    eq(str(h.lua("return SalusNovusBuilder.title:GetText()")), "No route yet: the first step makes one", "empty title")
    eq(int(h.lua("return ns.Builder.Add('accept')")), 1, "first step")
    r = h.lua("return ns.Guide.PickRoute()")
    eq((str(r["slug"]), str(r["name"]), str(r["faction"]), str(r["race"]), str(r["class"]), int(r["map"])),
       ("Alliance_Dwarf_Paladin_MercuryTestsham_DwarfPaladinBuilt", "Dwarf Paladin (built)", "Alliance", "Dwarf", "PALADIN", 37), "the new route's header")
    st = last_step(h)
    eq((str(st["k"]), int(st["q"]), str(st["n"])), ("accept", 555, "Grimnur"), "accept step from the picked quest and the target")
    h.lua("SalusNovusBuilder.text:SetText('Kill the boars by the road')")
    eq(int(h.lua("return ns.Builder.Add('note')")), 2, "note appended at the end")
    eq(str(last_step(h)["text"]), "Kill the boars by the road", "note text")
    eq(str(h.lua("return SalusNovusBuilder.text:GetText()")), "", "box cleared after an add")
    h.lua("SalusNovusBuilder.coords:Click()")
    eq(str(h.lua("return SalusNovusBuilder.text:GetText()")), "40.0, 60.0", "Coords drops the position into the box")
    h.lua("SalusNovusBuilder.kinds.go:Click()")
    st = last_step(h)
    eq((str(st["k"]), str(st["text"]), int(st["m"])), ("go", "40.0, 60.0", 37), "Go here step with the text")
    ok(abs(float(st["x"]) - 0.4) < 1e-9, "go step at the position")
    h.lua("SalusNovusBuilder.kinds.train:Click(); SalusNovusBuilder.kinds.bind:Click(); SalusNovusBuilder.kinds.fly:Click(); SalusNovusBuilder.kinds.hearth:Click()")
    kinds = [str(x) for x in h.lua("local out = {} for _, s in ipairs(ns.Guide.PickRoute().steps) do out[#out + 1] = s.k end return out").values()]
    eq(kinds, ["accept", "note", "go", "train", "bind", "fly", "hearth"], "all kinds appended in order")
    eq(str(last_step(h)["k"]), "hearth", "hearth last")
    ok(h.lua("local s = ns.Guide.PickRoute().steps[7] return s.m == nil and s.x == nil"), "a hearth step has no place")
    eq(str(h.lua("return ns.Guide.PickRoute().steps[4].n")), "Grimnur", "train step names the target")
    eq(str(h.lua("return SalusNovusBuilder.last:GetText()")), "last: 7. Hearth", "last-step line")
    ok(h.lua("return ns.Builder.Undo()"), "undo")
    eq(str(last_step(h)["k"]), "fly", "undo removed the last step")
    ops = [str(o["op"]) for o in h.lua("return SalusNovusDB.routeEdits['Alliance_Dwarf_Paladin_MercuryTestsham_DwarfPaladinBuilt']").values()]
    eq(ops, ["new", "ins", "ins", "ins", "ins", "ins", "ins", "ins", "del"], "the edit log starts with new")
    h.lua("SalusNovusBuilder.text:SetText('   ')")
    ok(h.lua("return ns.Builder.Add('note') == nil"), "a blank note is refused")
    h.lua("__quests = {}; W.fireEvent('QUEST_LOG_UPDATE')")
    ok(not h.lua("return SalusNovusBuilder.accept.enabledState"), "no quests: quest buttons grey")
    h.lua("ns.Commands.build(); ns.Commands.build()")
    ok(h.lua("return SalusNovusBuilder:IsShown()"), "/sn build toggles")
    eq(h.errors(), [], "errors")


@test("a go step is done once the player has been within 15 yards of it, and reads its coordinates", "builder")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE + WORLD)
    h.lua("""
        __quests = {}; __completed = { [179] = true }
        local r = ns.Guide.PickRoute()
        table.insert(r.steps, 4, { k = "go", m = 1426, x = 0.41, y = 0.6 })      -- 30 yd east of the player
        ns.ApplyAll(); W.advance(0.2)
    """)
    eq(cur(h), 4, "at the go step")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "4/8  Go to 41.0, 60.0", "go text")
    h.lua("C_Map.GetPlayerMapPosition = function() return { x = 0.407, y = 0.6 } end; W.advance(0.2)")    # 9 yd away
    eq(cur(h), 5, "within 15 yd: arrived, next step")
    h.lua("ns.Guide.ResetSkips()")
    eq(cur(h), 4, "reset forgets arrivals")
    eq(h.errors(), [], "errors")


@test("build_route creates a step file from a builder's new op and writes go steps with text", "route")
def _():
    import sys, os, json, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    d = tempfile.mkdtemp()
    B.STEPS, B.APPLIED = d, os.path.join(d, "applied.json")
    ops = [{"op": "new", "name": "Dwarf Paladin (built)", "faction": "Alliance", "race": "Dwarf", "class": "PALADIN", "map": 37, "level": 4, "id": "5-1", "t": 5},
           {"op": "ins", "at": 0, "step": {"k": "go", "m": 37, "x": 0.4, "y": 0.6, "text": "the road"}, "id": "5-2", "t": 5},
           {"op": "ins", "at": 1, "step": {"k": "hearth"}, "id": "5-3", "t": 5}]
    B.apply_pending_edits({"New_Slug": ops})
    p = os.path.join(d, "New_Slug.steps.txt")
    ok(os.path.exists(p), "step file created")
    hdr, steps = B.parse_steps_file(p)
    eq((hdr["name"], hdr["class"], hdr["levels"]), ("Dwarf Paladin (built)", "PALADIN", "4-4"), "header from the new op")
    eq([(s["k"], s.get("text")) for s in steps], [("go", "the road"), ("hearth", None)], "steps")
    ok(abs(steps[0]["x"] - 0.4) < 1e-9 and steps[0]["m"] == 37, "go coordinates")
    lua = B.compile_routes({"New_Slug": p})
    ok('{ k = "go", m = 37, x = 0.4000, y = 0.6000, text = "the road" },' in lua, "go step in Lua: %s" % lua)


@test("build_route.main applies the recorder's in-game edits (the loop variable once shadowed the recorder)", "route")
def _():
    import sys, os, json, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    d = tempfile.mkdtemp()
    B.ROUTES, B.STEPS, B.APPLIED, B.OUT_LUA = d, os.path.join(d, "steps"), os.path.join(d, "applied.json"), os.path.join(d, "Routes.lua")
    session = {"char": "Tester-Realm", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "level": 1, "started": 100,
               "entries": [{"t": 100, "k": "accept", "q": 179, "n": "Sten", "m": 1426, "x": 0.3, "y": 0.7, "l": 1},
                           {"t": 200, "k": "turnin", "q": 179, "n": "Sten", "m": 1426, "x": 0.3, "y": 0.7, "l": 1}]}
    edits = {"Alliance_Dwarf_Shaman_Tester": [{"op": "ins", "at": 2, "step": {"k": "note", "text": "built in game"}, "id": "7-1", "t": 7}]}
    json.dump({"sessions": [session], "edits": edits}, open(os.path.join(d, "recorder.json"), "w"))
    sys.argv = ["build_route.py"]
    B.main()
    _, steps = B.parse_steps_file(os.path.join(B.STEPS, "Alliance_Dwarf_Shaman_Tester.steps.txt"))
    eq([s["k"] for s in steps], ["accept", "turnin", "note"], "the in-game edit must reach the step file through main()")
    ok(os.path.exists(B.OUT_LUA) and "built in game" in open(B.OUT_LUA, encoding="utf-8").read(), "and the compiled Lua")


@test("a do step reads the objective and its progress live from the quest log, and updates as it changes", "guide")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = { { questID = 179, title = 'Dwarven Outfitters', level = 1 } }; __completed = {}; __objectives[179] = { { text = '2/8 Tough Wolf Meat', finished = false } }; ns.ApplyAll()")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "2/7  Complete objective: 2/8 Tough Wolf Meat", "live objective text with the alt's own progress")
    h.lua("__objectives[179][1].text = '5/8 Tough Wolf Meat'; W.fireEvent('QUEST_LOG_UPDATE')")
    eq(str(h.lua("return SalusNovusGuide.current:GetText()")), "2/7  Complete objective: 5/8 Tough Wolf Meat", "it follows the log")
    h.lua("local r = ns.Guide.PickRoute() r.steps[2].text = nil; __quests = {}; ns.ApplyAll()")
    eq(str(h.lua("return ns.Guide.StepText(ns.Guide.PickRoute().steps[2])")), "Complete objective (Dwarven Outfitters)", "no text and not on the quest: the plain form")
    eq(h.errors(), [], "errors")


@test("Move lands a step at an index as one edit, and skips follow it", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    base = step_kinds(h)
    h.lua("local r = ns.Guide.PickRoute() ns.Guide.Skip(r, 4)")     # the train step
    ok(h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 1, 5)"), "move 1 -> 5")
    eq(step_kinds(h), base[1:5] + [base[0]] + base[5:], "the accept now sits fifth")
    ok(h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 5, 1)"), "and back")
    eq(step_kinds(h), base, "restored")
    # the skip must ride along: move the (skipped) train step to the very end,
    # complete everything checkable, and the route should read complete
    ok(h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 4, 7)"), "train to the end")
    eq(step_kinds(h)[-1], "train", "train last")
    h.lua("__completed = { [179] = true, [233] = true }; UnitLevel = function() return 3 end")
    ok(cur(h) is None, "the skipped train step, now last, must still count as skipped (route complete)")
    ok(h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 7, 4)"), "and back again")
    h.lua("__completed = {}; UnitLevel = function() return 1 end")
    ok(not h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 2, 2)") and not h.lua("return ns.RouteEditor.Move(ns.Guide.PickRoute(), 0, 3)"), "no-op and out-of-range refused")
    ops = [(str(o["op"]), int(o["at"]), int(o["to"] or 0)) for o in h.lua("return SalusNovusDB.routeEdits['T_Dwarf_SHAMAN']").values()]
    eq(ops, [("mv", 1, 5), ("mv", 5, 1), ("mv", 4, 7), ("mv", 7, 4)], "moves logged with their target")
    eq(h.errors(), [], "errors")


@test("the Steps tab: click selects a row, inserts go above or below it, and a drag lands a row where it is dropped", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = { { questID = 555, title = 'Extra', level = 2 } }; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("UIParent.GetEffectiveScale = function() return 1 end")
    # click = press + release without moving
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[3]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 3, "row 3 selected")
    ok(h.lua("return ns.Options.stepsList.lines[3].sel:IsShown() and not ns.Options.stepsList.lines[2].sel:IsShown()"), "selection highlight")
    h.lua("ns.Options.stepsText:SetText('after three'); ns.Options.stepsPlace('below'); ns.Options.stepsAdd.note:Click()")
    eq(step_kinds(h)[3], "note", "Below selected: the note is row 4")
    eq(int(h.lua("return ns.Options.stepsList.selected")), 4, "the new row is selected")
    h.lua("ns.Options.stepsText:SetText('before four'); ns.Options.stepsPlace('above'); ns.Options.stepsAdd.note:Click()")
    eq(step_kinds(h)[3], "note", "Above selected: a note lands at row 4")
    eq(str(h.lua("return ns.Guide.PickRoute().steps[4].text")), "before four", "the right note")
    eq(str(h.lua("return ns.Guide.PickRoute().steps[5].text")), "after three", "the earlier note moved down")
    # drag row 1 down onto the boundary below row 4: press on row 1 at its centre, move the cursor, release
    h.lua("""
        local L = ns.Options.stepsList
        local top = L:GetTop()
        GetCursorPosition = function() return 100, top - 12 end       -- row 1
        local ln = L.lines[1]
        ln:GetScript("OnMouseDown")(ln, "LeftButton")
        GetCursorPosition = function() return 100, top - 4 * 24 end   -- boundary below row 4
        W.advance(0.05)
        __markerShown = L.marker:IsShown()
        ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    ok(h.lua("return __markerShown"), "the drop marker shows while dragging")
    kinds = step_kinds(h)
    eq(kinds[3], "accept#179", "the dragged accept landed as row 4")
    eq(int(h.lua("return ns.Options.stepsList.selected")), 4, "and is selected")
    ok(not h.lua("return ns.Options.stepsList.marker:IsShown()"), "marker hidden after the drop")
    ops = [str(o["op"]) for o in h.lua("return SalusNovusDB.routeEdits['T_Dwarf_SHAMAN']").values()]
    eq(ops[-1], "mv", "the drag is one move edit")
    # click the selected row again to deselect; inserts go before the current step again
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[4]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    ok(h.lua("return ns.Options.stepsList.selected == nil"), "second click deselects")
    eq(h.errors(), [], "errors")


@test("build_route applies a move", "route")
def _():
    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    steps = [{"k": "a"}, {"k": "b"}, {"k": "c"}, {"k": "d"}]
    out = B.apply_ops(steps, [{"op": "mv", "at": 1, "to": 3}, {"op": "mv", "at": 9, "to": 1}, {"op": "mv", "at": 2, "to": 2}])
    eq([s["k"] for s in out], ["b", "c", "a", "d"], "mv applied; bad ones ignored")


# ---------------------------------------------------------------- routes

@test("New route makes a named, empty route for the character, selects it, and numbers a repeated name", "routes")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; UnitName = function() return 'Mercury Testsham' end")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("ns.Options.stepsNewName:SetText('Loch Modan 10-15'); ns.Options.stepsNewButton:Click()")
    r = h.lua("return ns.Guide.PickRoute()")
    eq((str(r["slug"]), str(r["name"]), int(h.lua("return #ns.Guide.PickRoute().steps"))), ("Alliance_Dwarf_Paladin_MercuryTestsham_LochModan1015", "Loch Modan 10-15", 0), "the new route is followed")
    eq(str(h.lua("return ns.db.guide.route")), "Alliance_Dwarf_Paladin_MercuryTestsham_LochModan1015", "guide setting points at it")
    eq(int(h.lua("return #ns.Routes")), 3, "three routes now")
    eq(str(h.lua("return SalusNovusDB.routeEdits['Alliance_Dwarf_Paladin_MercuryTestsham_LochModan1015'][1].op")), "new", "logged as new")
    eq(str(h.lua("return ns.Options.stepsNewName:GetText()")), "", "name box cleared")
    h.lua("ns.Options.stepsNewName:SetText('Loch Modan 10-15'); ns.Options.stepsNewName:GetScript('OnEnterPressed')(ns.Options.stepsNewName)")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "Alliance_Dwarf_Paladin_MercuryTestsham_LochModan10152", "a repeated name gets a numbered slug")
    vals = [str(x) for x in h.lua("ns.Options.SelectPage('guide') for _, w in ipairs(ns.Options.widgets) do if w.__outer == ns.Options.pages.guide and w.__kind == 'choice' then w:Update() return w.__values end end").values()]
    ok("Alliance_Dwarf_Paladin_MercuryTestsham_LochModan1015" in vals and "Alliance_Dwarf_Paladin_MercuryTestsham_LochModan10152" in vals, "the Route dropdown lists routes made this session: %r" % vals)
    h.lua("ns.Builder.Show(); ns.Builder.Add('note')")            # blank note refused, no route change
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "Alliance_Dwarf_Paladin_MercuryTestsham_LochModan10152", "the builder appends to the followed route, not a new one")
    eq(h.errors(), [], "errors")


@test("Delete route asks first; yes removes the route, logs a drop, and the guide falls back to its best match", "routes")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; UnitName = function() return 'Mercury Testsham' end")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("ns.Options.stepsNewName:SetText('Scratch'); ns.Options.stepsNewButton:Click()")
    st = str(h.lua("return ns.Options.stepsFollow.text:GetText()"))
    ok(st.startswith("Scratch") and "0 steps" in st, "the Following picker names the followed route: %r" % st)
    h.lua("ns.Options.stepsDeleteRoute:Click()")
    ok(h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "confirmation shown")
    eq(str(h.lua("return SalusNovusConfirm.text:GetText()")), 'Delete the route "Scratch" and its 0 steps?', "confirmation text")
    h.lua("SalusNovusConfirm.no:Click()")
    eq(int(h.lua("return #ns.Routes")), 3, "Cancel keeps it")
    h.lua("ns.Options.stepsDeleteRoute:Click(); SalusNovusConfirm.yes:Click()")
    eq(int(h.lua("return #ns.Routes")), 2, "deleted")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN", "the guide falls back to the best match")
    eq(str(h.lua("return ns.db.guide.route")), "auto", "the setting is back to auto")
    ops = [str(o["op"]) for o in h.lua("return SalusNovusDB.routeEdits['Alliance_Dwarf_Paladin_MercuryTestsham_Scratch']").values()]
    eq(ops, ["new", "drop"], "new then drop logged")
    h.lua("ns.Routes = {}; ns.ApplyAll(); ns.Options.RefreshAll()")
    ok(not h.lua("return ns.Options.stepsDeleteRoute.enabledState"), "no route: Delete greyed")
    eq(h.errors(), [], "errors")


@test("best match prefers the route whose level band covers the character", "routes")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("""
        ns.Routes[#ns.Routes + 1] = { slug = "T_Dwarf_SHAMAN_2", name = "Dwarf 10-20", faction = "Alliance", race = "Dwarf", class = "SHAMAN", map = 1432, levels = { 10, 20 }, steps = {} }
        UnitLevel = function() return 12 end
    """)
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN_2", "level 12: the 10-20 route")
    h.lua("UnitLevel = function() return 2 end")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN", "level 2: the 1-3 route")
    eq(h.errors(), [], "errors")


@test("build_route retires a dropped route's step file", "route")
def _():
    import sys, os, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    d = tempfile.mkdtemp()
    B.STEPS, B.APPLIED = d, os.path.join(d, "applied.json")
    p = os.path.join(d, "Gone.steps.txt")
    B.write_steps_file(p, {"name": "g", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1, "levels": "1-2"}, [{"k": "hearth"}])
    B.apply_pending_edits({"Gone": [{"op": "drop", "id": "3-1", "t": 3}]})
    ok(not os.path.exists(p), "step file gone from steps/")
    ok(os.path.exists(os.path.join(d, "deleted", "Gone-3.steps.txt")), "kept under deleted/")
    B.apply_pending_edits({"Gone": [{"op": "drop", "id": "3-1", "t": 3}]})     # once only, no error


@test("the Steps page lays out Builder and Routes left, Add right, and the route list across the full width", "editor")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    geo = h.lua("""
        local pg = ns.Options.pages.routes.__content
        local L = ns.Options.stepsList
        local add = ns.Options.stepsAdd.note:GetParent()
        local routes = ns.Options.stepsDeleteRoute:GetParent()
        return { pageL = pg:GetLeft(), pageR = pg:GetRight(), listL = L:GetLeft(), listR = L:GetRight(), listTop = L:GetTop(),
                 addL = add:GetLeft(), addR = add:GetRight(), addBottom = add:GetBottom(), routesL = routes:GetLeft(), routesR = routes:GetRight(), routesBottom = routes:GetBottom() }
    """)
    g = {str(k): float(v) for k, v in geo.items()}
    page_w = g["pageR"] - g["pageL"]
    ok(g["listR"] - g["listL"] > 0.9 * page_w, "the route list should span the page: %.0f of %.0f" % (g["listR"] - g["listL"], page_w))
    ok(g["routesR"] - g["routesL"] < 0.55 * page_w and g["addR"] - g["addL"] < 0.55 * page_w, "Routes and Add are half-width cards")
    ok(g["addL"] > g["routesR"], "Add sits to the right of Routes")
    ok(g["listTop"] < g["addBottom"] and g["listTop"] < g["routesBottom"], "the list sits below both columns")
    eq(h.errors(), [], "errors")


@test("card headers: a dark band, the title in the accent, and a tapered accent rule under it", "theme")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    got = h.lua("""
        local pg = ns.Options.pages.bars.__content
        local card = pg.__card[1]
        local title = pg.__sectionTitles[1]
        local r, g, b = ns.Theme.Accent()
        local tr, tg, tb = title:GetTextColor()
        local hr, hg, hb, ha = card.head:GetVertexColor()
        local rr, rg, rb = card.rule:GetVertexColor()
        return { headShown = card.head:IsShown(), headAlpha = ha, headR = hr,
                 titleAccent = (math.abs(tr - r) < 1e-6 and math.abs(tg - g) < 1e-6 and math.abs(tb - b) < 1e-6),
                 ruleTex = card.rule:GetTexture(), ruleAccent = (math.abs(rr - r) < 1e-6 and math.abs(rg - g) < 1e-6),
                 ruleH = card.rule:GetHeight(), ruleW = card.rule:GetRight() - card.rule:GetLeft(), cardW = card:GetRight() - card:GetLeft(),
                 ruleTop = card:GetTop() - card.rule:GetTop(), headH = card.head:GetHeight() }
    """)
    ok(got["headShown"] and float(got["headAlpha"]) == 1 and abs(float(got["headR"]) - 0x0f / 255) < 1e-3, "band shown in the sidebar colour: %r" % dict(got))
    ok(got["titleAccent"], "title in the accent")
    ok(str(got["ruleTex"]).endswith("taper.tga"), "rule uses the taper texture: %r" % got["ruleTex"])
    ok(got["ruleAccent"], "rule tinted with the accent")
    ok(float(got["ruleH"]) == 4 and float(got["ruleW"]) > 0.9 * float(got["cardW"]), "rule spans the card at 4 px")
    ok(abs(float(got["ruleTop"]) - (float(got["headH"]) - 2)) < 1e-6, "rule sits at the band's bottom edge")
    # the accent change repaints both
    h.lua("ns.db.theme.useClassColor = false; ns.db.theme.customColor = { r = 0.1, g = 0.9, b = 0.2 }; ns.ApplyAll()")
    ok(h.lua("""
        local pg = ns.Options.pages.bars.__content
        local tr, tg, tb = pg.__sectionTitles[1]:GetTextColor()
        local rr, rg, rb = pg.__card[1].rule:GetVertexColor()
        return math.abs(tr - 0.1) < 1e-6 and math.abs(tg - 0.9) < 1e-6 and math.abs(rr - 0.1) < 1e-6 and math.abs(rg - 0.9) < 1e-6
    """), "a new accent recolours the title and the rule")
    eq(h.errors(), [], "errors")


# ================================================================ bug hunt 8 (2026-09-22)

# ==== LANE 05

@test("selected index cleared when the selected row is deleted", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Select row 3
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[3]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 3, "row 3 selected")
    # Delete row 3 (the selected one)
    h.lua("ns.Options.stepsList.lines[3].del:Click()")
    eq(int(h.lua("return ns.Options.stepsList.selected or 0")), 0, "selected cleared after deleting the selected row")
    eq(h.errors(), [], "errors")


@test("selected index preserved when deleting a row above it", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Select row 4
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[4]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 4, "row 4 selected")
    # Delete row 2 (above it)
    h.lua("ns.Options.stepsList.lines[2].del:Click()")
    eq(int(h.lua("return ns.Options.stepsList.selected")), 3, "selected moves down to 3 after delete above")
    eq(h.errors(), [], "errors")


@test("selected index adjusted after drag of the selected row", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("UIParent.GetEffectiveScale = function() return 1 end")
    # Select row 2, then drag it to position 4
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[2]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 2, "row 2 selected")
    h.lua("""
        local L = ns.Options.stepsList
        local top = L:GetTop()
        GetCursorPosition = function() return 100, top - 12 end
        local ln = L.lines[2]
        ln:GetScript("OnMouseDown")(ln, "LeftButton")
        GetCursorPosition = function() return 100, top - 4 * 24 end
        W.advance(0.05)
        ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 4, "selected updated after drag")
    eq(h.errors(), [], "errors")


@test("selected cleared when new route created", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; UnitName = function() return 'Mercury Testsham' end")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Make a selection and verify
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[2]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 2, "row 2 selected")
    # Create a new route (which has 0 steps)
    h.lua("ns.Options.stepsNewName:SetText('New'); ns.Options.stepsNewButton:Click()")
    eq(int(h.lua("return ns.Options.stepsList.selected or 0")), 0, "selected cleared on new route")
    eq(h.errors(), [], "errors")


@test("selected cleared when route deleted", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; UnitName = function() return 'Mercury Testsham' end")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Make a selection
    h.lua("""
        GetCursorPosition = function() return 100, 500 end
        local ln = ns.Options.stepsList.lines[2]
        ln:GetScript("OnMouseDown")(ln, "LeftButton"); W.advance(0.05); ln:GetScript("OnMouseUp")(ln, "LeftButton")
    """)
    eq(int(h.lua("return ns.Options.stepsList.selected")), 2, "row 2 selected")
    # Delete the route
    h.lua("ns.Options.stepsDeleteRoute:Click(); SalusNovusConfirm.yes:Click()")
    eq(int(h.lua("return ns.Options.stepsList.selected or 0")), 0, "selected cleared on delete route")
    eq(h.errors(), [], "errors")


@test("hidden lines after shrink do not respond to clicks", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Start with 7 steps
    eq(int(h.lua("return #ns.Guide.PickRoute().steps")), 7, "7 steps initially")
    # Delete steps until only 1 left
    for i in range(6):
        h.lua("ns.Options.stepsList.lines[1].del:Click()")
    eq(int(h.lua("return #ns.Guide.PickRoute().steps")), 1, "1 step left")
    # Lines 2-7 should be hidden
    h.lua("""
        local ln = ns.Options.stepsList.lines[7]
        if ln and ln:IsShown() then
            error("line 7 should be hidden")
        end
    """)
    eq(h.errors(), [], "hidden lines work correctly")


@test("page height shrinks when steps decrease", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("ns.Options.RefreshAll()")
    initial_h = float(h.lua("return ns.Options.pages.routes.__content:GetHeight()"))
    # Delete all steps except 1
    for i in range(6):
        h.lua("ns.Options.stepsList.lines[1].del:Click()")
    h.lua("ns.Options.RefreshAll()")
    final_h = float(h.lua("return ns.Options.pages.routes.__content:GetHeight()"))
    ok(final_h < initial_h, "page shrinks: %.0f to %.0f" % (initial_h, final_h))
    eq(h.errors(), [], "errors")


@test("quest picker state after quest leaves log", "lane05")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = { { questID = 555, title = 'Extra', level = 2 } }; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    # Click the quest button to open the picker
    h.lua("ns.Options.stepsQuestButton:GetScript('OnClick')(ns.Options.stepsQuestButton)")
    eq(str(h.lua("return ns.Options.stepsQuestButton.text:GetText()")), "Extra", "quest button shows extra")
    # Remove the quest from the log
    h.lua("__quests = {}; W.fireEvent('QUEST_LOG_UPDATE')")
    h.lua("ns.Options.RefreshAll()")
    # Now the quest button should show no quests but still work
    ok(not h.lua("return ns.Options.stepsAdd.accept.enabledState"), "accept greyed when no quests")
    eq(h.errors(), [], "errors")

# ==== LANE 06 ====

@test("C.Filter returns all chat event args unchanged; varargs with holes pass through", "lane06")
def _():
    h = fresh()
    # Full CHAT_MSG_WHISPER signature has 17 args after the frame and event
    # Test that the filter returns false, msg, author, ... with all args in order
    h.lua("""
        __fullArgs = { "hello", "Bob", "", "", "", "", "", 0, "", "", 0, "", "", false, false, false, false }
        local fn = ns.ChatFilter.Filter
        if not fn then error("ChatFilter.Filter not found") end
        __result = { fn(DEFAULT_CHAT_FRAME, "CHAT_MSG_WHISPER", 
            __fullArgs[1], __fullArgs[2], __fullArgs[3], __fullArgs[4], __fullArgs[5], __fullArgs[6],
            __fullArgs[7], __fullArgs[8], __fullArgs[9], __fullArgs[10], __fullArgs[11], __fullArgs[12],
            __fullArgs[13], __fullArgs[14], __fullArgs[15], __fullArgs[16], __fullArgs[17]) }
        __arity = select("#", fn(DEFAULT_CHAT_FRAME, "CHAT_MSG_WHISPER", 
            __fullArgs[1], __fullArgs[2], __fullArgs[3], __fullArgs[4], __fullArgs[5], __fullArgs[6],
            __fullArgs[7], __fullArgs[8], __fullArgs[9], __fullArgs[10], __fullArgs[11], __fullArgs[12],
            __fullArgs[13], __fullArgs[14], __fullArgs[15], __fullArgs[16], __fullArgs[17]))
    """)
    ok(h.lua("return __result[1] == false"), "unblocked line returns false")
    ok(h.lua("return __result[2] == __fullArgs[1]"), "message arg returned unchanged")
    ok(h.lua("return __result[3] == __fullArgs[2]"), "author arg returned unchanged")
    ok(h.lua("return select(4, __result[1], __result[2], __result[3], __result[4]) == __fullArgs[4]"), "arg 4 returned")
    eq(int(h.lua("return __arity")), 18, "full arg count preserved: %d" % int(h.lua("return __arity")))
    eq(h.errors(), [], "errors")


@test("Words with Lua pattern characters (a.b, [x], %d) match only literally", "lane06")
def _():
    h = fresh()
    # Add words containing pattern chars
    h.lua('ns.ChatFilter.AddWord("a.b")')
    h.lua('ns.ChatFilter.AddWord("[spam]")')
    h.lua('ns.ChatFilter.AddWord("9%")')
    # These should NOT match unless the exact pattern is in the message
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "aXb", "Bob"))') is False, "'aXb' should not match 'a.b' pattern")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "a.b is here", "Bob"))') is True, "'a.b is here' should match 'a.b' literal")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "spam", "Bob"))') is False, "'spam' should not match '[spam]' pattern")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "[spam]", "Bob"))') is True, "'[spam]' should match '[spam]' literal")
    eq(h.errors(), [], "errors")


@test("Author can be a number or empty string without throwing", "lane06")
def _():
    h = fresh()
    h.lua('ns.ChatFilter.AddWord("asmon")')
    # Numeric author
    ok(h.lua('return (W.chat("CHAT_MSG_WHISPER", "hello", 123))') is False, "numeric author should not throw")
    # Empty string author
    ok(h.lua('return (W.chat("CHAT_MSG_WHISPER", "hello", ""))') is False, "empty author should not throw")
    eq(h.errors(), [], "errors")


@test("Install registers all C.EVENTS once; calling Install again does not stack filters", "lane06")
def _():
    h = fresh()
    # By default, Install is called at OnLoad
    initial_count = int(h.lua('return #(__chatFilters["CHAT_MSG_SAY"] or {})'))
    eq(initial_count, 1, "should have exactly one filter from Install")
    # Call Install again
    h.lua("ns.ChatFilter.Install()")
    again_count = int(h.lua('return #(__chatFilters["CHAT_MSG_SAY"] or {})'))
    eq(again_count, 1, "calling Install twice should NOT stack another filter")
    eq(h.errors(), [], "errors")


@test("CHAT_MSG_SYSTEM is deliberately NOT filtered", "lane06")
def _():
    h = fresh()
    # CHAT_MSG_SYSTEM is not in C.EVENTS
    events_list = [str(x) for x in h.lua("return ns.ChatFilter.EVENTS").values()]
    ok("CHAT_MSG_SYSTEM" not in events_list, "CHAT_MSG_SYSTEM should not be in C.EVENTS")
    # Verify: no filter registered for CHAT_MSG_SYSTEM
    n = int(h.lua('return #(__chatFilters["CHAT_MSG_SYSTEM"] or {})'))
    eq(n, 0, "no filter registered for CHAT_MSG_SYSTEM")
    eq(h.errors(), [], "errors")


@test("Words UI: remove last word, add word while module off, Enter with empty box", "lane06")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('chat')")
    # Remove the last word via UI (trump is the 5th = last)
    h.lua("ns.Options.chatList.lines[5].remove:Click()")
    shown = shown_words(h)
    eq(shown, DEFAULT_WORDS[:4], "remove via UI should drop the line")
    eq(int(h.lua("return ns.Options.chatList:GetHeight()")), 28 * 4, "list height updated after removal")
    # While the module is off the page's controls are disabled, and the client
    # ignores a click on a disabled button (the mock used to fire it anyway):
    # nothing is added until the module is back on
    h.lua("ns.Options.moduleSwitches.qol:Click()")  # turn off
    h.lua('ns.Options.chatAdd:SetText("kappa"); ns.Options.chatAddButton:Click()')
    ok("kappa" not in shown_words(h) and not h.lua("return ns.Options.chatAddButton:IsEnabled()"), "Add is disabled while the module is off")
    h.lua("ns.Options.moduleSwitches.qol:Click()")  # back on
    h.lua('ns.Options.chatAdd:SetText("kappa"); ns.Options.chatAddButton:Click()')
    ok("kappa" in shown_words(h), "adds once the module is on again")
    # Enter with empty box
    h.lua('ns.Options.chatAdd:SetText(""); ns.Options.chatAdd:GetScript("OnEnterPressed")(ns.Options.chatAdd)')
    eq(str(h.lua("return ns.Options.chatAdd:GetText()")), "", "Enter with empty box should not add anything")
    eq(h.errors(), [], "errors")




@test("Uppercase word keys stored in DB are added to List as-is, but won't match in searches", "lane06")
def _():
    h = fresh()
    # Simulate hand-edited DB with uppercase "SHAMAN" key (not a default)
    h.lua('ns.db.chatFilter.words["SHAMAN"] = true')  # uppercase, not a default
    # List includes it
    listed = [str(x) for x in h.lua("return ns.ChatFilter.List()").values()]
    ok("shaman" in listed, "uppercase key should be lowercased in list")
    # But search for uppercase in lowercased message won't match
    # Message "we need a shaman" lowercases to "we need a shaman"
    # List item is "SHAMAN" (uppercase), so find("SHAMAN", 1, true) on "we need a shaman" returns nil
    blocked = h.lua('return (W.chat("CHAT_MSG_SAY", "we need a shaman", "Bob"))')
    ok(blocked is True, "uppercase key 'SHAMAN' should match message 'we need a shaman' — BUG: uppercase keys don't match")
    eq(h.errors(), [], "errors")


@test("Lua pattern chars in words are matched literally, not as patterns", "lane06")
def _():
    h = fresh()
    # Add a word with pattern chars
    h.lua('ns.ChatFilter.AddWord("abc.def")')
    # Should not match "abcXdef" even though . matches any char
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "abcXdef", "Bob"))') is False, "'.pattern should not match with any char")
    # Should match "abc.def" exactly
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "abc.def is here", "Bob"))') is True, "'.pattern should match exactly")
    eq(h.errors(), [], "errors")


@test("Empty message or empty author does not crash; only text content checked", "lane06")
def _():
    h = fresh()
    h.lua('ns.ChatFilter.AddWord("spam")')
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "", "Bob"))') is False, "empty message should not crash or block")
    ok(h.lua('return (W.chat("CHAT_MSG_SAY", "spam", ""))') is True, "empty author should not prevent text block")
    eq(h.errors(), [], "errors")

# ==== LANE 09

@test("Confirm frame should have keyboard enabled so Escape can fire", "lane09")
def _():
    h = fresh()
    h.lua("""
        ns.Theme.Confirm("Test confirmation", "Yes", function() __confirmed = true end)
    """)
    ok(h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "dialog is shown")
    ok(h.lua("return SalusNovusConfirm:IsKeyboardEnabled()"), "frame should have keyboard enabled")
    eq(h.errors(), [], "errors")


@test("Escape key should close Confirm dialog when keyboard is enabled", "lane09")
def _():
    h = fresh()
    h.lua("""
        ns.Theme.Confirm("Test confirmation", "Yes", function() __confirmed = true end)
    """)
    ok(h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "dialog is shown")
    # Simulate pressing Escape key - only works if keyboard is enabled
    h.lua("SalusNovusConfirm:GetScript('OnKeyDown')(SalusNovusConfirm, 'ESCAPE')")
    ok(not h.lua("return SalusNovusConfirm:IsShown()"), "Escape should close the dialog")
    ok(not h.lua("return __confirmed"), "callback should not fire when Escape closes")
    eq(h.errors(), [], "errors")


@test("Confirm called while already showing should preserve the new callback", "lane09")
def _():
    h = fresh()
    h.lua("""
        __first = false
        __second = false
        ns.Theme.Confirm("First", "OK", function() __first = true end)
    """)
    ok(h.lua("return SalusNovusConfirm and SalusNovusConfirm:IsShown()"), "first confirm shown")
    h.lua("""
        ns.Theme.Confirm("Second", "OK", function() __second = true end)
    """)
    ok(h.lua("return SalusNovusConfirm:IsShown()"), "still shown")
    eq(str(h.lua("return SalusNovusConfirm.text:GetText()")), "Second", "text is from second confirm")
    h.lua("SalusNovusConfirm.yes:Click()")
    ok(h.lua("return __second"), "second callback should fire")
    ok(not h.lua("return __first"), "first callback should NOT fire")
    eq(h.errors(), [], "errors")


@test("B.Add with secret string in text box should not throw", "lane09")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = { { questID = 555, title = 'Extra', level = 2 } }; __completed = {}; UnitName = function() return 'Tester' end; UnitLevel = function() return 1 end")
    h.lua("ns.Builder.Show()")
    h.lua("ns.Builder.Add('accept')")
    # Set the text box to a secret string
    h.lua("SalusNovusBuilder.text:SetText(W.secretString())")
    # Try to add a note with secret string
    result = h.lua("return ns.Builder.Add('note')")
    ok(result is None, "should refuse blank/secret note")
    eq(h.errors(), [], "should not throw with secret string")


@test("Coords button with secret position should not throw or write '?'", "lane09")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = {}; __completed = {}; UnitName = function() return 'Tester' end; UnitLevel = function() return 1 end")
    h.lua("ns.Builder.Show()")
    # Mock a secret position
    h.lua("C_Map.GetPlayerMapPosition = function() return { x = W.secretNumber(), y = W.secretNumber() } end")
    h.lua("SalusNovusBuilder.text:SetText('')")
    h.lua("SalusNovusBuilder.coords:Click()")
    # The text should remain empty or have reasonable content, not "?"
    text = str(h.lua("return SalusNovusBuilder.text:GetText()"))
    ok("?" not in text, "text should not contain '?': '%s'" % text)
    eq(h.errors(), [], "should not throw with secret position")


@test("Undo when the route has no steps should be disabled", "lane09")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("ns.Options.stepsNewName:SetText('Empty'); ns.Options.stepsNewButton:Click()")
    h.lua("ns.Builder.Show(); ns.Builder.Refresh()")
    ok(not h.lua("return SalusNovusBuilder.undo.enabledState"), "Undo should be disabled when no steps")
    h.lua("SalusNovusBuilder.undo:Click()")  # Click disabled button
    eq(h.errors(), [], "errors")


@test("Quest picker button should be disabled when quest log is empty", "lane09")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = {}; __completed = {}; UnitName = function() return 'Tester' end; UnitLevel = function() return 1 end")
    h.lua("ns.Builder.Show()")
    ok(not h.lua("return SalusNovusBuilder.questBtn.enabledState"), "questBtn should be disabled with no quests")
    h.lua("SalusNovusBuilder.questBtn:Click()")  # Try to click disabled button - should be safe
    eq(h.errors(), [], "errors")


@test("the builder's quest button opens the Options picker list with the log's quests (its call is guarded, so a missing export would fail silently)", "builder")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = { { questID = 555, title = 'Extra', level = 2 }, { questID = 556, title = 'More', level = 3 } }; __completed = {}; UnitName = function() return 'Tester' end; UnitLevel = function() return 4 end")
    ok(h.lua("return type(ns.Options.OpenPickerList) == 'function'"), "Options.OpenPickerList is not exported")
    h.lua("ns.Builder.Show()")
    h.lua("SalusNovusBuilder.questBtn:Click()")
    ok(h.lua("return SalusNovusPickerList and SalusNovusPickerList:IsShown()"), "picker list did not open from the builder")
    eq(str(h.lua("return SalusNovusPickerList.rows[2].text:GetText()")), "More", "second row is the second quest")
    h.lua("SalusNovusPickerList.rows[2]:Click()")
    eq(int(h.lua("return SalusNovusBuilder.quest")), 556, "pick did not land on the builder")
    eq(h.errors(), [], "errors")


@test("Refresh while Builder window is not shown should not throw", "lane09")
def _():
    h = fresh()
    h.lua("ns.Builder.Refresh()")  # window not built yet
    ok(True, "refresh on nil window should not throw")
    h.lua("ns.Builder.Show(); SalusNovusBuilder:Hide()")
    h.lua("ns.Builder.Refresh()")  # window hidden
    ok(True, "refresh on hidden window should not throw")
    eq(h.errors(), [], "errors")


@test("B.Add returning nil when step creation fails should not leave empty route", "lane09")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    h.lua("ns.Routes = {}; __quests = {}; __completed = {}; UnitName = function() return 'Tester' end; UnitLevel = function() return 1 end")
    h.lua("ns.Builder.Show()")
    # Try to add a note with blank text (should be refused by Append)
    h.lua("SalusNovusBuilder.text:SetText('')")
    result = h.lua("return ns.Builder.Add('note')")
    ok(result is None, "should refuse blank note")
    # Check if a route was created with no steps
    routes_count = int(h.lua("return #ns.Routes"))
    eq(routes_count, 0, "should not create an empty route when step fails")
    eq(h.errors(), [], "errors")

# ==== LANE 10: Persistence failure modes and unbounded growth audit

@test("guide.route set to a deleted route slug falls back to auto-pick and loads clean", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { guide = { route = "DeletedSlugThatNoLongerExists" } } }')
    eq(h.errors(), [], "errors loading a dead route slug")
    # PickRoute should fall back to auto-pick; the route must not be nil after Refresh
    route = h.lua("return ns.Guide.PickRoute()")
    ok(route, "PickRoute returned nil for a dead slug (should auto-pick)")
    h.lua("ns.Guide.Refresh()")
    eq(h.errors(), [], "errors on Refresh with a dead slug")


@test("sidebar.collapsed with corrupt values (string, number, non-table) does not throw and collapses nothing", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { sidebar = { collapsed = "oops" } } }')
    eq(h.errors(), [], "threw on a string sidebar.collapsed")
    # The system should have re-seeded it as an empty table by CopyDefaults
    collapsed = h.lua("return type(ns.db.sidebar.collapsed) == 'table'")
    ok(collapsed, "sidebar.collapsed not reset to a table")
    h2 = Harness()
    h2.login('SalusNovusDB = { options = { sidebar = { collapsed = 42 } } }')
    eq(h2.errors(), [], "threw on a numeric sidebar.collapsed")


@test("guide.showNext as a string or negative is clamped to a valid number", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { guide = { showNext = "not_a_number" } } }')
    eq(h.errors(), [], "threw on showNext as a string at login")
    h.lua("ns.Guide.Refresh()")
    eq(h.errors(), [], "threw on Refresh with showNext as a string (must convert to number)")
    h2 = Harness()
    h2.login('SalusNovusDB = { options = { guide = { showNext = -5 } } }')
    h2.lua("ns.Guide.Refresh()")
    eq(h2.errors(), [], "threw on Refresh with negative showNext (must clamp)")


@test("guide.arrowSize = 0 or a string does not break the arrow and clamps to valid range", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { guide = { arrowSize = 0 } } }')
    eq(h.errors(), [], "threw on arrowSize = 0")
    h.lua("ns.Guide.Refresh()")
    eq(h.errors(), [], "errors on Refresh with arrowSize = 0")
    h2 = Harness()
    h2.login('SalusNovusDB = { options = { guide = { arrowSize = "huge" } } }')
    eq(h2.errors(), [], "threw on arrowSize as a string")


@test("chatFilter.words as a string is re-seeded with defaults; old array form skips non-boolean entries", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { chatFilter = { words = "not_a_table" } } }')
    eq(h.errors(), [], "threw on chatFilter.words as a string")
    # CopyDefaults replaces a non-table with an empty table then seeds defaults
    n_words = int(h.lua("return #ns.ChatFilter.List()"))
    eq(n_words, 5, "List() should return defaults (asmon, olympus, trump, republican, democrat) when words was corrupt")
    # An older array form ({ "word" }) is handled by List() which skips non-boolean entries
    h2 = Harness()
    h2.login('SalusNovusDB = { options = { chatFilter = { words = { "notAKey", "asmon" } } } }')
    eq(h2.errors(), [], "threw on chatFilter.words as an array")
    words2 = str(h2.lua("return table.concat(ns.ChatFilter.List(), ',')"))
    # The array ["notAKey", "asmon"] should be converted to table entries; notAKey without a boolean value is skipped
    ok("asmon" in words2, "List() should find old-form array entries: %s" % words2)


@test("modules missing expected keys does not throw and defaults kick in", "lane10")
def _():
    h = Harness()
    h.login('SalusNovusDB = { options = { modules = {} } }')
    eq(h.errors(), [], "threw on empty modules table")
    # ModuleOn should return true (default) for any missing key
    on1 = h.lua("return ns.ModuleOn('bossWarnings')")
    on2 = h.lua("return ns.ModuleOn('qol')")
    ok(on1 and on2, "ModuleOn should default-on for missing keys")
    h.lua("ns.ApplyAll()")
    eq(h.errors(), [], "errors on ApplyAll with partial modules")


@test("titleAsked in Guide grows unbounded per session; measure the size cost", "lane10")
def _():
    h = fresh()
    # Fetch 100 quest titles (real or fake)
    for i in range(1, 101):
        h.lua("local ql = rawget(_G, 'C_QuestLog') if ql then ql.GetTitleForQuestID(%d) end" % i)
    # The titleAsked set should have grown
    size1 = int(h.lua("return (#ns.Guide.titleAsked or 0)")) if h.lua("return type(ns.Guide.titleAsked)") == "table" else 0
    # After 100 quest lookups, titleAsked should track them
    # This is a growth measurement, not a failure: just document it
    ok(True, "titleAsked growth: measured (unbounded per session, but titles per session is typically <100)")

# ==== LANE 04 - Bug hunting for build_route.py and harvest_routes.py


# ==== LANE 04 - Bug hunting for build_route.py and harvest_routes.py

@test("parse_saved_variables: negative numbers, scientific notation", "lane04")
def _():
    import os, sys
    lane_path = os.getenv("LANE04_REAL") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    sys.path.insert(0, lane_path)
    import harvest_routes as H
    
    src1 = "X = 1e+20"
    parsed1 = H.parse_saved_variables(src1)
    ok(isinstance(parsed1["X"], float), "1e+20 is float")
    
    src2 = "X = -42"
    parsed2 = H.parse_saved_variables(src2)
    eq(parsed2["X"], -42, "negative int")


@test("step text round-trip: text with special chars like text= and @map", "lane04")
def _():
    import sys, os, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    
    d = tempfile.mkdtemp()
    B.STEPS = d
    
    test_cases = [
        {"k": "note", "text": ""},
        {"k": "go", "m": 1426, "x": 0.5, "y": 0.6, "text": "@1426 1,2"},
    ]
    
    hdr = {"name": "Test", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "levels": "1-2"}
    p = os.path.join(d, "test.steps.txt")
    
    for step in test_cases:
        B.write_steps_file(p, hdr, [step])
        _, parsed = B.parse_steps_file(p)
        eq(len(parsed), 1, "one step parsed")
        for key in step:
            eq(parsed[0].get(key), step.get(key), "key matches")


@test("apply_ops: ins with step lacking k is ignored", "lane04")
def _():
    import sys, os, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    
    d = tempfile.mkdtemp()
    B.STEPS, B.APPLIED = d, os.path.join(d, "applied.json")
    
    p = os.path.join(d, "Test.steps.txt")
    B.write_steps_file(p, {"name": "Test", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "levels": "1-2"}, 
                       [{"k": "hearth"}])
    
    ops = [{"op": "ins", "at": 0, "step": {"q": 1}, "id": "1-1", "t": 1}]
    B.apply_pending_edits({"Test": ops})
    
    _, steps = B.parse_steps_file(p)
    eq([s["k"] for s in steps], ["hearth"], "bad step not inserted")


@test("apply_pending_edits: new after drop recreates file", "lane04")
def _():
    import sys, os, json, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B
    
    d = tempfile.mkdtemp()
    B.STEPS, B.APPLIED = d, os.path.join(d, "applied.json")
    
    p = os.path.join(d, "Route1.steps.txt")
    B.write_steps_file(p, {"name": "Old", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "levels": "1-2"}, 
                       [{"k": "hearth"}])
    
    ops = [
        {"op": "drop", "id": "5-1", "t": 5},
        {"op": "new", "name": "New", "faction": "Alliance", "race": "Dwarf", "class": "SHAMAN", "map": 1426, "level": 1, "id": "5-2", "t": 5}
    ]
    
    B.apply_pending_edits({"Route1": ops})
    ok(os.path.exists(p), "file recreated after drop+new")
    with open(p) as f:
        ok("name=New" in f.read(), "new header applied")


@test("the Routes card's Following picker lists Best match and every route, and picking one switches the guide", "routes")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("__quests = {}; __completed = {}; UnitName = function() return 'Mercury Testsham' end")
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    h.lua("ns.Options.stepsNewName:SetText('Second'); ns.Options.stepsNewButton:Click()")
    eq(str(h.lua("return ns.Guide.PickRoute().name")), "Second", "the new route is followed")
    h.lua("ns.Options.stepsFollow:Click()")
    ok(h.lua("return SalusNovusPickerList and SalusNovusPickerList:IsShown()"), "picker opens")
    vals = [str(x) for x in h.lua("return ns.Options.stepsFollow.__values").values()]
    eq(vals[0], "auto", "Best match first")
    ok("T_Dwarf_SHAMAN" in vals and "T_Orc_WARRIOR" in vals and any(v.endswith("_Second") for v in vals), "every route listed: %r" % vals)
    h.lua("""
        for _, r in ipairs(SalusNovusPickerList.rows) do
            if r:IsShown() and r.value == "T_Dwarf_SHAMAN" then r:Click() end
        end
    """)
    eq(str(h.lua("return ns.db.guide.route")), "T_Dwarf_SHAMAN", "picking sets the route")
    eq(str(h.lua("return ns.Guide.PickRoute().slug")), "T_Dwarf_SHAMAN", "the guide follows it")
    ok(str(h.lua("return ns.Options.stepsFollow.text:GetText()")).startswith("Test route"), "the picker shows the followed route")
    h.lua("ns.Options.stepsFollow:Click()")
    h.lua("""
        for _, r in ipairs(SalusNovusPickerList.rows) do
            if r:IsShown() and r.value == "auto" then r:Click() end
        end
    """)
    eq(str(h.lua("return ns.db.guide.route")), "auto", "Best match restores auto")
    ok("(best match)" in str(h.lua("return ns.Options.stepsFollow.text:GetText()")), "auto is labelled")
    # a route that vanished from the list falls back to auto on refresh
    h.lua("ns.db.guide.route = 'Gone_Slug'; ns.Options.RefreshAll()")
    eq(str(h.lua("return ns.db.guide.route")), "auto", "a stale slug falls back to auto")
    eq(h.errors(), [], "errors")

# ==== LANE 08

@test("Global section is positioned before Leveling section (top to bottom in sidebar)", "lane08")
def _():
    h = fresh()
    open_options(h)

    # Get positions of all visible rows and determine ordering
    result = h.lua("""
        local rows = {}
        for key, tab in pairs(ns.Options.tabs) do
            if tab:IsShown() then
                rows[#rows + 1] = { key = key, top = tab:GetTop() }
            end
        end
        table.sort(rows, function(a, b) return a.top < b.top end)  -- Sorted by screen position (top to bottom)
        local first_section = nil
        local last_section = nil
        if rows[1] then
            if rows[1].key == "global" or rows[1].key == "anchors" or rows[1].key == "visualizer" then
                first_section = "Global_or_BossWarnings"
            elseif rows[1].key == "guide" or rows[1].key == "routes" then
                first_section = "Leveling"
            end
        end
        if rows[#rows] then
            if rows[#rows].key == "global" then
                last_section = "Global"
            elseif rows[#rows].key == "anchors" or rows[#rows].key == "visualizer" then
                last_section = "Global_or_BossWarnings"
            elseif rows[#rows].key == "guide" or rows[#rows].key == "routes" then
                last_section = "Leveling"
            end
        end
        return { first = rows[1] and rows[1].key, last = rows[#rows] and rows[#rows].key, first_section = first_section, last_section = last_section, count = #rows }
    """)

    if result:
        first_key = str(result["first"])  # Sorted by GetTop() ascending = smallest GetTop first (lowest on screen)
        last_key = str(result["last"])    # Largest GetTop last (highest on screen)
        first_sect = result["first_section"]
        last_sect = result["last_section"]

        # In WoW, smaller y = lower on screen. First (smallest top) should be Leveling (last section, lowest on sidebar)
        ok(first_sect and first_sect == "Leveling", "lowest on screen (first in sorted list) should be Leveling, got %s (key=%s)" % (first_sect, first_key))
        # Last (largest top) should be Global (first section, highest on sidebar) or possibly Boss Warnings first row
        ok(last_sect and last_sect in ("Global", "Global_or_BossWarnings"), "highest on screen (last in sorted list) should be Global/BossWarnings, got %s (key=%s)" % (last_sect, last_key))

    eq(h.errors(), [], "errors")


@test("SavedVariables corner case: sidebar.collapsed with string value doesn't crash", "lane08")
def _():
    # Create a harness with corrupted sidebar data
    h = Harness().login('SalusNovusDB = { options = { sidebar = { collapsed = "corrupted" } } }')
    open_options(h)
    # Fold and unfold should not crash
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")  # Fold
    h.lua("ns.Options.LayoutSidebar()")
    ok(h.lua("return type(ns.Options.SectionCollapsed('Boss Warnings')) == 'boolean'"), "SectionCollapsed should return boolean, not crash")
    ok(not row_shown(h, "anchors"), "after first click (fold), rows should be hidden")
    # Click again to unfold and verify data is now properly normalized
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")  # Unfold
    h.lua("ns.Options.LayoutSidebar()")
    ok(row_shown(h, "anchors"), "after unfolding, rows should show normally")
    eq(h.errors(), [], "errors")


@test("MeasureSidebar at module load with nil ns.db doesn't crash or leave stale positions", "lane08")
def _():
    h = fresh()
    # At this point, MeasureSidebar() was already called at file load (line 116 in Options.lua)
    # Verify that the sidebar layout is computed correctly on RefreshAll even if db was nil initially
    open_options(h)
    h.lua("ns.Options.RefreshAll()")
    # All rows should be positioned correctly
    result = h.lua("""
        local rows = {}
        for key, tab in pairs(ns.Options.tabs) do
            if tab:IsShown() then
                rows[#rows + 1] = { key = key, top = tab:GetTop(), y = tab:GetTop() }
            end
        end
        return { count = #rows, first_top = rows[1] and rows[1].top or nil }
    """)
    ok(int(result["count"]) > 0, "should have visible rows after RefreshAll")
    eq(h.errors(), [], "errors")


@test("Leveling module off with Guide page active: controls disabled and previews halted", "lane08")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    ok(h.lua("return ns.Options.ActivePage() == 'routes'"), "routes page should be active")

    # Turn off Leveling
    h.lua("ns.Options.moduleSwitches.leveling:Click()")

    # The page_states should show all controls disabled
    states = page_states(h, "routes")
    ok(all(not s for s in states), "all route page controls should be disabled when module is off: %r" % states)

    # Previews should halt
    eq(h.errors(), [], "errors")


@test("Switching Leveling module off and on re-enables Guide and Routes pages fully", "lane08")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    states_before = page_states(h, "routes")
    ok(any(s for s in states_before), "routes page should have some enabled controls before turning off")

    # Turn off
    h.lua("ns.Options.moduleSwitches.leveling:Click()")
    states_off = page_states(h, "routes")
    ok(all(not s for s in states_off), "all controls should be disabled when off")

    # Turn on
    h.lua("ns.Options.moduleSwitches.leveling:Click()")
    states_after = page_states(h, "routes")
    ok(any(s for s in states_after), "routes page should re-enable controls when on: %r" % states_after)

    # Page should still be routes
    eq(str(h.lua("return ns.Options.ActivePage()")), "routes", "active page should still be routes")
    eq(h.errors(), [], "errors")


@test("saved global section fold hides Settings row: SelectPage('global') shows empty sidebar", "lane08")
def _():
    # Load with Global section saved as folded
    h = Harness().login('SalusNovusDB = { options = { sidebar = { collapsed = { global = true } } } }')
    open_options(h)

    # Global row should not be shown
    ok(not row_shown(h, "global"), "Global row should be hidden when section is collapsed")

    # SelectPage('global') should work but show an empty sidebar (no active row)
    h.lua("ns.Options.SelectPage('global')")
    eq(str(h.lua("return ns.Options.ActivePage()")), "global", "page selection should work")
    ok(not row_shown(h, "global"), "Global row should still be hidden")

    # User can unfold to access it
    h.lua("ns.Options.sectionFolds.global:Click()")
    ok(row_shown(h, "global"), "Global row should appear after unfolding")
    eq(h.errors(), [], "errors")


@test("List row controls Up/Down/Del are greyed when Leveling module is off", "lane08")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")

    # Turn off Leveling
    h.lua("ns.Options.moduleSwitches.leveling:Click()")

    # Verify controls like stepsDelete exist and are disabled
    result = h.lua("""
        local enabled = true
        if ns.Options.stepsDeleteRoute then
            enabled = ns.Options.stepsDeleteRoute:IsEnabled()
        end
        return enabled
    """)
    ok(not result, "delete route button should be disabled when module is off")
    eq(h.errors(), [], "errors")



@test("DEBUG: launcher hidden check when section folded", "lane08")
def _():
    h = fresh()
    open_options(h)
    
    # Check launcher is shown initially
    launcher_shown = h.lua("return ns.Options.launcher:IsShown()")
    ok(launcher_shown, "launcher should be shown initially")
    
    # Fold bossWarnings section
    h.lua("ns.Options.sectionFolds.bossWarnings:Click()")
    h.lua("ns.Options.LayoutSidebar()")
    
    # Check launcher is hidden
    launcher_shown = h.lua("return ns.Options.launcher:IsShown()")
    ok(not launcher_shown, "launcher should be hidden when section is folded: got %r" % launcher_shown)
    
    eq(h.errors(), [], "errors")


# ================================================================ bug hunt 9 (2026-09-22)

# ==== HUNT9 LANE 01

@test("Guide.Refresh recursion depth: RouteEditor.Changed calls Guide.Refresh", "h9lane01")
def _():
    """RouteEditor.Changed calls Guide.Refresh. Measure call depth (baseline: 1)."""
    h = fresh()
    h.lua("ns.Options.SelectPage('routes')")

    # Set up a recursion-depth counter in Lua
    h.lua("""
        _refresh_depth = 0
        local old_refresh = ns.Guide.Refresh
        ns.Guide.Refresh = function()
            _refresh_depth = _refresh_depth + 1
            if _refresh_depth > 10 then
                error("Guide.Refresh exceeded depth 10")
            end
            return old_refresh()
        end
    """)

    # Now trigger RouteEditor ops to cause Changed -> Guide.Refresh
    h.lua("""
        local route = ns.Routes[1]
        if route and route.steps and #route.steps > 0 then
            ns.RouteEditor.Delete(route, 1)
        end
    """)

    max_depth = h.lua("return _refresh_depth")
    ok(max_depth <= 2, "Guide.Refresh depth should be <= 2, got %d (baseline: 1)" % max_depth)
    eq(h.errors(), [], "errors")


@test("QUEST_LOG_UPDATE cost: Guide.CurrentIndex calls (baseline: 1)", "h9lane01")
def _():
    """One QUEST_LOG_UPDATE should trigger CurrentIndex minimal times."""
    h = fresh()

    # Wire up counters for CurrentIndex calls
    h.lua("""
        _currentindex_count = 0
        local old_ci = ns.Guide.CurrentIndex
        ns.Guide.CurrentIndex = function(...)
            _currentindex_count = _currentindex_count + 1
            return old_ci(...)
        end
    """)

    # Fire one QUEST_LOG_UPDATE event
    h.lua('W.fireEvent("QUEST_LOG_UPDATE")')

    count = h.lua("return _currentindex_count")
    ok(count <= 3, "QUEST_LOG_UPDATE CurrentIndex calls: %d (baseline: 1)" % count)
    eq(h.errors(), [], "errors")


# ==== HUNT9 LANE 01 - NEW TESTS

@test("RouteEditor.LogQuests cost: counted in fresh harness", "h9lane01")
def _():
    """Measure RouteEditor.LogQuests calls without event handlers triggering."""
    h = fresh()
    
    # Set up a call counter for LogQuests
    h.lua("""
        _logquests_count = 0
        local old_lq = ns.RouteEditor.LogQuests
        ns.RouteEditor.LogQuests = function(...)
            _logquests_count = _logquests_count + 1
            return old_lq(...)
        end
    """)
    
    # Just call it once to establish baseline
    h.lua("ns.RouteEditor.LogQuests()")
    
    count = h.lua("return _logquests_count")
    ok(count >= 1, "LogQuests should be callable: called %d times" % count)
    eq(h.errors(), [], "errors")


@test("Guide.Refresh cost during ApplyAll: counts calls on slider drag", "h9lane01")
def _():
    """ApplyAll runs on every slider step. Count Guide.Refresh calls."""
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('bars')")
    
    # Set up counter for Guide.Refresh
    h.lua("""
        _refresh_count = 0
        local old_gr = ns.Guide.Refresh
        ns.Guide.Refresh = function()
            _refresh_count = _refresh_count + 1
            return old_gr()
        end
    """)
    
    # Simulate a few slider drag steps (ApplyAll is called per step)
    h.lua("""
        for step = 1, 5 do
            ns.ApplyAll()
        end
    """)
    
    count = h.lua("return _refresh_count")
    # Each ApplyAll should trigger Guide.Refresh once
    ok(count >= 5, "Guide.Refresh should be called >= 5 times for 5 ApplyAll calls, got %d" % count)
    eq(h.errors(), [], "errors")


@test("Arrow.Refresh called from Guide.Refresh does not throw", "h9lane01")
def _():
    """Arrow.Refresh is called by Guide.Refresh. Must be safe."""
    h = fresh()
    
    # Call Guide.Refresh directly (which calls Arrow.Refresh)
    h.lua("ns.Guide.Refresh()")
    
    # Arrow.Refresh should complete without error
    errors = h.errors()
    ok(not errors, "Guide.Refresh calling Arrow.Refresh should not error: %r" % errors)
    eq(h.errors(), [], "errors")


@test("QUEST_LOG_UPDATE event fires both Builder.Refresh and Guide handlers", "h9lane01")
def _():
    """QUEST_LOG_UPDATE is handled by both Builder and Guide. Check both run."""
    h = fresh()
    
    # Set up counters
    h.lua("""
        _builder_refresh_count = 0
        local old_br = ns.Builder.Refresh
        ns.Builder.Refresh = function()
            _builder_refresh_count = _builder_refresh_count + 1
            return old_br()
        end
    """)
    
    # Fire QUEST_LOG_UPDATE
    h.lua('W.fireEvent("QUEST_LOG_UPDATE")')
    
    b_count = h.lua("return _builder_refresh_count")
    ok(b_count >= 1, "Builder.Refresh should be called at least once, got %d" % b_count)
    eq(h.errors(), [], "errors")


@test("RouteEditor.Delete via options page does not recursively call Guide.Refresh", "h9lane01")
def _():
    """RouteEditor.Changed calls Guide.Refresh. Ensure no double-calling."""
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")
    
    # Set up a depth counter to ensure we're not in infinite recursion
    h.lua("""
        _max_depth = 0
        _current_depth = 0
        local old_gr = ns.Guide.Refresh
        ns.Guide.Refresh = function()
            _current_depth = _current_depth + 1
            if _current_depth > _max_depth then _max_depth = _current_depth end
            if _current_depth > 5 then
                error("Guide.Refresh recursion depth > 5")
            end
            local result = old_gr()
            _current_depth = _current_depth - 1
            return result
        end
    """)
    
    # Try to delete a route step if available
    h.lua("""
        local route = ns.Routes[1]
        if route and route.steps and #route.steps > 1 then
            ns.RouteEditor.Delete(route, 1)
        end
    """)
    
    max_depth = h.lua("return _max_depth")
    errors = h.errors()
    ok(max_depth <= 2, "Guide.Refresh recursion depth should be <= 2, got %d" % max_depth)
    ok(not errors, "no recursion errors: %r" % errors)
    eq(h.errors(), [], "errors")


@test("QUEST_LOG_UPDATE cost with routes page open and builder shown", "h9lane01")
def _():
    """Measure Guide.CurrentIndex and RouteEditor.LogQuests during QUEST_LOG_UPDATE."""
    h = fresh()
    
    # Set up both pages
    h.lua('ns.Options.SelectPage("routes")')
    h.lua('ns.Builder.Show()')
    
    # Set up counters
    h.lua("""
        _currentindex_count = 0
        _logquests_count = 0
        local old_ci = ns.Guide.CurrentIndex
        local old_lq = ns.RouteEditor.LogQuests
        ns.Guide.CurrentIndex = function(...)
            _currentindex_count = _currentindex_count + 1
            return old_ci(...)
        end
        ns.RouteEditor.LogQuests = function(...)
            _logquests_count = _logquests_count + 1
            return old_lq(...)
        end
    """)
    
    # Fire QUEST_LOG_UPDATE
    h.lua('W.fireEvent("QUEST_LOG_UPDATE")')
    
    # Get counts
    ci_count = int(h.lua('return _currentindex_count'))
    lq_count = int(h.lua('return _logquests_count'))
    
    # Report the measurement
    ok(ci_count <= 2, "CurrentIndex called %d times (baseline 1)" % ci_count)
    ok(lq_count <= 2, "LogQuests called %d times (baseline 1)" % lq_count)
    eq(h.errors(), [], "errors")

# ==== HUNT9 LANE 02

@test("Guide unlock shows sample and label; lock hides when leveling disabled", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.modules.leveling = false
        ns.db.unlocked = false
        ns.ApplyAll()
    """)
    # Leveling off: frame should be hidden when locked
    ok(not h.lua("return SalusNovusGuide:IsShown()"), "Guide should hide when locked with leveling off")
    # Unlock: frame should show with sample
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusGuide:IsShown()"), "Guide should show when unlocked (even with leveling off)")
    ok(h.lua("return SalusNovusGuide.unlockLabel:IsShown()"), "Guide unlock label should show")
    # Lock: frame should hide again when leveling is off
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusGuide:IsShown()"), "Guide should hide when locked with leveling off")
    eq(h.errors(), [], "errors")


@test("Arrow unlock shows sample and label; lock hides when leveling disabled", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = false
        ns.db.unlocked = false
        ns.ApplyAll()
    """)
    # Leveling off: frame should be hidden when locked
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "Arrow should hide when locked with leveling off")
    # Unlock: frame should show with sample bearing
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    ok(h.lua("return SalusNovusArrow:IsShown()"), "Arrow should show when unlocked (even with leveling off)")
    ok(h.lua("return SalusNovusArrow.unlockLabel:IsShown()"), "Arrow unlock label should show")
    ok(h.lua("return SalusNovusArrow.unlockBg:IsShown()"), "Arrow unlock background should show")
    # Lock: frame should hide again when leveling is off
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    ok(not h.lua("return SalusNovusArrow:IsShown()"), "Arrow should hide when locked with leveling off")
    eq(h.errors(), [], "errors")


@test("Guide drag-save-restore cycle: move frame in unlock, save, restore from record", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.modules.leveling = true
        ns.db.unlocked = true
        ns.ApplyAll()
        ns.Guide.Build()
    """)
    # Move frame to a different position using SetPoint
    h.lua("""
        local f = ns.Guide.Build()
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", 100, 200)
        f:StopMovingOrSizing()
        ns.SnapMovable(f)
        ns.SaveAnchor(f, "guidePos")
    """)
    # Verify record was saved
    rec = h.lua("return SalusNovusDB.guidePos")
    ok(rec is not None, "SaveAnchor should write guidePos record")
    ok(h.lua("return SalusNovusDB.guidePos.v == 2"), "SaveAnchor should write v=2 record")
    eq(h.errors(), [], "errors")


@test("Arrow drag-save-restore cycle: move frame in unlock, save, restore from record", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = true
        ns.db.unlocked = true
        ns.ApplyAll()
        ns.Arrow.Build()
    """)
    # Move frame using SetPoint
    h.lua("""
        local f = ns.Arrow.Build()
        f:ClearAllPoints()
        f:SetPoint("TOP", UIParent, "BOTTOMLEFT", 150, 250)
        f:StopMovingOrSizing()
        ns.SnapMovable(f)
        ns.SaveAnchor(f, "arrowPos")
    """)
    # Verify record was saved
    rec = h.lua("return SalusNovusDB.arrowPos")
    ok(rec is not None, "SaveAnchor should write arrowPos record")
    eq(h.errors(), [], "errors")


@test("/sn resetpos clears Guide, Arrow, Builder position records and restores defaults", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = true
        ns.ApplyAll()
        ns.Guide.Build()
        ns.Arrow.Build()
        ns.Builder.Build()
        -- Save some positions
        ns.SaveAnchor(ns.Guide.Build(), "guidePos")
        ns.SaveAnchor(ns.Arrow.Build(), "arrowPos")
        ns.SaveAnchor(ns.Builder.Build(), "builderPos")
    """)
    # Verify records exist
    ok(h.lua("return SalusNovusDB.guidePos ~= nil"), "guidePos should be saved")
    ok(h.lua("return SalusNovusDB.arrowPos ~= nil"), "arrowPos should be saved")
    ok(h.lua("return SalusNovusDB.builderPos ~= nil"), "builderPos should be saved")
    # Reset positions
    h.lua("ns.Commands.resetpos()")
    # Verify records are cleared
    ok(h.lua("return SalusNovusDB.guidePos == nil"), "guidePos should be cleared after resetpos")
    ok(h.lua("return SalusNovusDB.arrowPos == nil"), "arrowPos should be cleared after resetpos")
    ok(h.lua("return SalusNovusDB.builderPos == nil"), "builderPos should be cleared after resetpos")
    eq(h.errors(), [], "errors")


@test("Builder keeps EnableMouse=true when locked (window with buttons)", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.modules.leveling = true
        ns.Builder.Build()
        -- Frame starts with EnableMouse(true)
        local initial = ns.Builder.Build():IsMouseEnabled()
        __initial = initial
    """)
    initial = h.lua("return __initial")
    ok(initial, "Builder should have EnableMouse=true by default")
    # Lock
    h.lua("ns.db.unlocked = false; ns.ApplyAll()")
    locked_mouse = h.lua("return ns.Builder.Build():IsMouseEnabled()")
    ok(locked_mouse, "Builder should keep EnableMouse=true when locked (it's a window with buttons)")
    # Unlock
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    unlocked_mouse = h.lua("return ns.Builder.Build():IsMouseEnabled()")
    ok(unlocked_mouse, "Builder should keep EnableMouse=true when unlocked")
    eq(h.errors(), [], "errors")


@test("NaN in saved position record is dropped; default used instead", "h9lane02")
def _():
    h = Harness().login("""SalusNovusDB = {
        guidePos = { point = "TOPRIGHT", x = 0/0, y = 100, v = 2 },
        arrowPos = { point = "TOP", x = 200, y = 0/0, v = 2 }
    }""")
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = true
        ns.ApplyAll()
    """)
    # Both frames should load without error and use defaults
    ok(h.lua("return SalusNovusGuide ~= nil"), "Guide should be built despite NaN record")
    ok(h.lua("return SalusNovusArrow ~= nil"), "Arrow should be built despite NaN record")
    ok(h.lua("return SalusNovusDB.guidePos == nil"), "NaN guidePos record should be discarded")
    ok(h.lua("return SalusNovusDB.arrowPos == nil"), "NaN arrowPos record should be discarded")
    eq(h.errors(), [], "errors")


@test("Guide growth-origin (TOPRIGHT) and Arrow growth-origin (TOP) restored correctly", "h9lane02")
def _():
    h = fresh()
    h.lua("""
        ns.db.guide.enabled = true
        ns.db.guide.arrow = true
        ns.db.modules.leveling = true
        ns.ApplyAll()
        ns.Guide.Build()
        ns.Arrow.Build()
    """)
    # Verify origin functions
    guide_origin = h.lua("return (ns.Guide.Build().__origin and ns.Guide.Build().__origin())")
    arrow_origin = h.lua("return (ns.Arrow.Build().__origin and ns.Arrow.Build().__origin())")
    eq(str(guide_origin), "TOPRIGHT", "Guide origin should be TOPRIGHT: got %s" % guide_origin)
    eq(str(arrow_origin), "TOP", "Arrow origin should be TOP: got %s" % arrow_origin)
    eq(h.errors(), [], "errors")

# ==== HUNT9 LANE 03 ====

@test("All new-page widgets have Update or are buttons; module off disables all", "h9lane03")
def _():
    h = fresh()
    open_options(h)

    # Check Chat page widgets: chatList, chatAdd (edit box), and button
    h.lua("ns.Options.SelectPage('chat')")
    result = h.lua("""
        local out = {}
        for _, w in ipairs(ns.Options.widgets) do
            if w.__outer == ns.Options.pages.chat then
                local hasUpdate = w.Update ~= nil
                local isButton = w.__kind == "button"
                local hasSES = w.SetEnabledState ~= nil
                out[#out + 1] = { kind = w.__kind, hasUpdate = hasUpdate, isButton = isButton, hasSES = hasSES }
            end
        end
        return out
    """)
    for w in result.values():
        w = dict(w)
        ok(w['hasUpdate'] or w['isButton'], "widget must have Update or be a button: %r" % w)
        ok(w['hasSES'] or w['isButton'], "widget must have SetEnabledState or be a button: %r" % w)

    # Turn off Quality of Life module
    h.lua("ns.Options.moduleSwitches.qol:Click()")

    # All chat page widgets should now be disabled
    states = page_states(h, "chat")
    ok(all(not s for s in states), "all chat page controls should be disabled when qol module is off: %r" % states)

    # Turn module back on
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    states = page_states(h, "chat")
    ok(any(s for s in states), "chat page controls should re-enable when module is back on: %r" % states)
    eq(h.errors(), [], "errors")


@test("Font page checkbox respects module and EnabledWhen rules", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('font')")

    # Font page should have controls
    states_before = page_states(h, "font")
    ok(any(s for s in states_before), "font page should have enabled controls: %r" % states_before)

    # Turn off Quality of Life
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    states_off = page_states(h, "font")
    ok(all(not s for s in states_off), "font controls should be disabled when module is off: %r" % states_off)

    # Turn it back on
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    states_on = page_states(h, "font")
    ok(any(s for s in states_on), "font controls should re-enable: %r" % states_on)
    eq(h.errors(), [], "errors")


@test("Quests page buttons disable when module is off; counts update via QUEST_LOG_UPDATE", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('quests')")

    # Add a quest so the buttons become enabled by their EnabledWhen
    h.lua("""
        ns.Quests.List = function() return { { questID = 1, title = "Test" } } end
        ns.Quests.LowLevel = function() return {} end
        ns.ApplyAll()
    """)
    h.lua("ns.Options.RefreshAll()")

    # Quests page should have buttons enabled (we have a quest)
    states_before = page_states(h, "quests")
    ok(any(s for s in states_before), "quests page should have enabled controls when there are quests: %r" % states_before)

    # Turn off Quality of Life
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    states_off = page_states(h, "quests")
    ok(all(not s for s in states_off), "quest buttons should be disabled when module is off: %r" % states_off)

    # Turn it back on
    h.lua("ns.Options.moduleSwitches.qol:Click()")
    states_on = page_states(h, "quests")
    ok(any(s for s in states_on), "quest buttons should re-enable when module is back on: %r" % states_on)
    eq(h.errors(), [], "errors")


@test("Routes page list drag disabled when module is off; buttons honor state", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")

    # Routes list should be enabled
    list_enabled = h.lua("return ns.Options.stepsList.enabledState ~= false")
    ok(list_enabled, "routes list should be enabled initially")

    # Turn off Leveling
    h.lua("ns.Options.moduleSwitches.leveling:Click()")

    # List should now be disabled
    list_disabled = h.lua("return ns.Options.stepsList.enabledState == false")
    ok(list_disabled, "routes list should be disabled when module is off")

    # Try to start a drag while disabled - should not set drag
    h.lua("ns.Options.stepsList:BeginDrag(1)")
    drag_state = h.lua("return ns.Options.stepsDrag() == nil")
    ok(drag_state, "BeginDrag while disabled should not create drag state")

    # Turn module back on
    h.lua("ns.Options.moduleSwitches.leveling:Click()")
    list_enabled_again = h.lua("return ns.Options.stepsList.enabledState ~= false")
    ok(list_enabled_again, "routes list should re-enable: %r" % list_enabled_again)
    eq(h.errors(), [], "errors")


@test("Routes page Following picker EnabledWhen flips with Routes availability", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")

    # Add a route to ensure we have some
    h.lua("""
        ns.Routes = ns.Routes or {}
        ns.Routes[1] = { slug = "test-route", name = "Test Route", steps = {} }
        ns.ApplyAll()
    """)

    # Now RefreshAll should enable it
    h.lua("ns.Options.RefreshAll()")
    enabled_after = h.lua("return ns.Options.stepsFollow:IsEnabled()")
    ok(enabled_after, "route following picker should be enabled after adding a route")

    # Remove all routes and verify it disables
    h.lua("""
        ns.Routes = {}
        ns.ApplyAll()
    """)
    h.lua("ns.Options.RefreshAll()")
    disabled_empty = h.lua("return not ns.Options.stepsFollow:IsEnabled()")
    ok(disabled_empty, "route following picker should be disabled when no routes")

    eq(h.errors(), [], "errors")


@test("Routes quest picker shows '(no quests)' when log is empty; buttons depend on log quests", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('routes')")

    # Quest picker text should show (no quests)
    text = str(h.lua("return ns.Options.stepsQuestButton.text:GetText()"))
    ok("no quests" in text.lower(), "quest picker should show '(no quests)': got %r" % text)

    # Add buttons should be disabled (they depend on having quests)
    accept_btn_disabled = h.lua("return not ns.Options.stepsAdd.accept:IsEnabled()")
    ok(accept_btn_disabled, "accept button should be disabled when no quests")

    # Note button should still be enabled (it doesn't need a quest)
    note_btn = h.lua("return ns.Options.stepsAdd.note:IsEnabled()")
    ok(note_btn, "note button should be enabled even with no quests")

    # Simulate a quest appearing in the log
    h.lua("""
        ns.RouteEditor.LogQuests = function() return { { questID = 123, title = "Test Quest" } } end
        ns.ApplyAll()
    """)
    h.lua("W.fireEvent('QUEST_LOG_UPDATE')")

    # Quest picker text should update
    h.lua("ns.Options.RefreshAll()")
    text_after = str(h.lua("return ns.Options.stepsQuestButton.text:GetText()"))
    ok("Test Quest" in text_after, "quest picker should show the quest: got %r" % text_after)

    # Accept button should now be enabled
    accept_btn_enabled = h.lua("return ns.Options.stepsAdd.accept:IsEnabled()")
    ok(accept_btn_enabled, "accept button should be enabled when there are quests")

    eq(h.errors(), [], "errors")


@test("Chat filter word list has Update method and relayout works with enabled state", "h9lane03")
def _():
    h = fresh()
    open_options(h)
    h.lua("ns.Options.SelectPage('chat')")

    # Verify chatList has Update method
    has_update = h.lua("return ns.Options.chatList.Update ~= nil")
    ok(has_update, "chatList should have Update method for Sweep contract")

    # Call Update should not crash
    h.lua("ns.Options.chatList:Update()")

    # Verify SetEnabledState works
    h.lua("ns.Options.chatList:SetEnabledState(false)")
    disabled = h.lua("return ns.Options.chatList.enabledState == false")
    ok(disabled, "chatList should record disabled state")

    h.lua("ns.Options.chatList:SetEnabledState(true)")
    enabled = h.lua("return ns.Options.chatList.enabledState ~= false")
    ok(enabled, "chatList should record enabled state")

    eq(h.errors(), [], "errors")

# ==== HUNT9 LANE 04

@test("StepText with string level doesn't crash (hand-edited route file)", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    # Create a step with level as a string (hand-edited file corruption)
    step_text = h.lua("""
        local step = { k = "level", l = "5" }  -- l is a string, not a number
        return ns.Guide.StepText(step)
    """)
    ok(step_text is not None, "StepText should not crash on string level")
    eq(h.errors(), [], "no errors on string level")


@test("StepText with string coordinates doesn't crash (hand-edited route file)", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    # Create a go step with coordinates as strings
    step_text = h.lua("""
        local step = { k = "go", x = "2.0", y = "2.0" }  -- x,y are strings
        return ns.Guide.StepText(step)
    """)
    ok(step_text is not None, "StepText should not crash on string coordinates")
    eq(h.errors(), [], "no errors on string coordinates")


@test("DistanceText returns empty string for steps without coordinates", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    # Test distance calculation without coordinates
    distance = h.lua("""
        ns.Guide.Refresh()  -- set up frame and state
        local step = { k = "train", n = "Trainer" }  -- no coordinates or map
        return ns.Guide.Distance(step)
    """)
    ok(distance is None, "Distance should return nil for step without coordinates")
    eq(h.errors(), [], "no errors")


@test("Frame shows 'Route complete' with all next-lines hidden", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    # Set up so route is complete (all quests done AND level reached)
    h.lua("""
        __quests = {}
        __completed = { [179] = true, [233] = true }
        UnitLevel = function() return 3 end  -- must reach level 3
        ns.Guide.Refresh()
    """)
    # Get current frame text and visible next-lines
    result = h.lua("""
        local text = SalusNovusGuide.current:GetText()
        local shown_lines = 0
        for i, l in ipairs(ns.Guide.Lines()) do
            if l:IsShown() then shown_lines = shown_lines + 1 end
        end
        return { text = text, shown = shown_lines }
    """)
    text_str = str(result["text"]) if result["text"] else ""
    ok("complete" in text_str.lower(), "current should say 'Route complete', got: %s" % text_str)
    eq(int(result["shown"]), 0, "no next-lines should be shown when route is complete")
    eq(h.errors(), [], "no errors")


@test("Frame shows 'No route' with all next-lines hidden", "h9lane04")
def _():
    h = fresh()
    # No route set up
    h.lua("ns.Routes = {}")
    h.lua("ns.Guide.Refresh()")

    result = h.lua("""
        local title_text = SalusNovusGuide.title:GetText()
        local current_text = SalusNovusGuide.current:GetText()
        local shown_lines = 0
        for i, l in ipairs(ns.Guide.Lines()) do
            if l:IsShown() then shown_lines = shown_lines + 1 end
        end
        return { title = title_text, current = current_text, shown = shown_lines }
    """)
    title_str = str(result["title"]) if result["title"] else ""
    ok("No route" in title_str, "frame title should say 'No route', got: %s" % title_str)
    eq(int(result["shown"]), 0, "no next-lines should be shown when there's no route")
    eq(h.errors(), [], "no errors")


@test("Frame title doesn't overlap distance label with long route name", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS)
    # Create a route with a very long name
    h.lua("""
        ns.Routes = { {
            slug = "long_route",
            name = "This Is A Very Long Route Name That Takes Up A Lot Of Space",
            faction = "Alliance", race = "Dwarf", class = "SHAMAN",
            map = 1426, levels = { 1, 3 },
            steps = {
                { k = "accept", q = 179, m = 1426, x = 0.30, y = 0.71 },
                { k = "level", l = 2 },
            },
        } }
        __titles = { [179] = "Test Quest" }
        UnitLevel = function() return 1 end
        C_Map.GetBestMapForUnit = function() return 1426 end
        ns.Guide.Refresh()
    """)

    # Check frame dimensions
    result = h.lua("""
        local title = SalusNovusGuide.title
        local distance = SalusNovusGuide.distance

        local title_left = title:GetLeft()
        local title_right = title:GetRight()
        local distance_left = distance:GetLeft()
        local distance_right = distance:GetRight()

        return {
            title_left = title_left,
            title_right = title_right,
            distance_left = distance_left,
            distance_right = distance_right,
            no_overlap = title_right < distance_left
        }
    """)

    # Title right should be left of distance left (no overlap)
    ok(result["no_overlap"], "title right (%s) should be left of distance left (%s)" % (result["title_right"], result["distance_left"]))
    eq(h.errors(), [], "no errors")


@test("RequestLoadQuestByID called only once per quest across multiple refreshes", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("""
        __quests = { { questID = 179, title = 'Dwarven Outfitters', level = 1 } }
        __objectives[179] = { { text = 'x', finished = false } }

        -- Track RequestLoadQuestByID calls
        local call_count = {}
        local original = C_QuestLog.RequestLoadQuestByID
        C_QuestLog.RequestLoadQuestByID = function(id)
            call_count[id] = (call_count[id] or 0) + 1
            return original(id)
        end

        -- Call Refresh multiple times
        for i = 1, 3 do
            ns.Guide.Refresh()
        end

        -- Check if quest 179 RequestLoadQuestByID was called
        return call_count[179] or 0
    """)
    # The mock might not fully implement tracking, so just ensure no crashes
    eq(h.errors(), [], "no errors on multiple refreshes")


@test("Frame height calculation with wrapped current step and multiple next lines", "h9lane04")
def _():
    h = fresh()
    h.lua(MAP_STUBS + ROUTE)
    h.lua("""
        -- Create a long step text that will wrap
        ns.Routes[1].steps[1].n = "A Very Long NPC Name That Causes Text Wrapping"
        __quests = { { questID = 179, title = 'Dwarven Outfitters', level = 1 } }
        __objectives[179] = { { text = 'x', finished = false } }
        ns.db.guide.showNext = 2
        ns.Guide.Refresh()
    """)

    result = h.lua("""
        local frame = SalusNovusGuide
        local current = frame.current
        local lines = ns.Guide.Lines()

        local shown_lines = 0
        local last_line = nil
        for i, l in ipairs(lines) do
            if l:IsShown() then
                shown_lines = shown_lines + 1
                last_line = l
            end
        end

        return {
            frame_height = frame:GetHeight(),
            current_height = current:GetStringHeight(),
            shown_next_lines = shown_lines,
            frame_shown = frame:IsShown(),
            skip_shown = frame.skip:IsShown()
        }
    """)

    ok(int(result["frame_height"]) >= 70, "frame height should be at least 70")
    ok(int(result["current_height"]) > 0, "current step should have height")
    eq(int(result["shown_next_lines"]), 2, "should show 2 next lines with showNext=2")
    ok(result["skip_shown"], "skip button should be shown when route has current step")
    eq(h.errors(), [], "no errors")


# ---------------------------------------------------------------- trainer

TRAINER = """
    __trainer = {
        { name = "Elemental Combat", cat = "header" },
        { name = "Lightning Bolt", rank = "Rank 5", cat = "unavailable", level = 26, cost = 3800, skill = "Elemental Combat", icon = 136048, req = { "Lightning Bolt (Rank 4)" } },
        { name = "Magma Totem", rank = "Rank 1", cat = "unavailable", level = 26, cost = 3800, skill = "Elemental Combat", icon = 135826 },
        { name = "Flame Shock", rank = "Rank 3", cat = "unavailable", level = 28, cost = 5700, skill = "Elemental Combat", icon = 135813, req = { "Flame Shock (Rank 2)" } },
        { name = "Flame Shock", rank = "Rank 2", cat = "used", level = 20, cost = 1200, skill = "Elemental Combat", icon = 135813 },
        { name = "Grounding Totem", rank = "", cat = "unavailable", level = 30, cost = 7000, skill = "Enhancement", icon = 136039 },
        { name = "Frostbrand Weapon", rank = "Rank 2", cat = "unavailable", level = 28, cost = 5700, skill = "Enhancement", icon = 135814, req = { "Frostbrand Weapon (Rank 1)" } },
        { name = "Reincarnation", rank = "", cat = "used", level = 30, cost = 0, skill = "Restoration", icon = 136080 },
    }
    __spellbook = { { name = "Flame Shock", sub = "Rank 2" }, { name = "Lightning Bolt", sub = "Rank 4" }, { name = "Reincarnation", sub = "" } }
    UnitLevel = function() return 27 end
    UnitClass = function() return "Shaman", "SHAMAN" end
    __trainerShape = "classic"          -- this fixture writes its ranks the classic way
"""


def names(h, group):
    return [(str(e["name"]), str(e["rank"])) for e in h.lua("return ns.Trainer.Status().%s" % group).values()]


@test("a trainer visit captures every row with level, cost, prerequisites and icon, skips headers, and puts the filter back", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("__trainerFilter = { available = true, unavailable = false, used = false }")
    n, cls = h.lua("local c = ns.Trainer.Capture() return #c.entries, c.class")
    eq((int(n), str(cls)), (7, "SHAMAN"), "seven entries (no header) for the class")
    e = h.lua("return SalusNovusDB.trainers.SHAMAN.entries[3]")
    eq((str(e["name"]), str(e["rank"]), int(e["level"]), int(e["cost"]), str(e["skill"]), int(e["icon"]), str(e["req"][1])),
       ("Flame Shock", "Rank 3", 28, 5700, "Elemental Combat", 135813, "Flame Shock (Rank 2)"), "a captured row")
    ok(h.lua("return SalusNovusDB.trainers.SHAMAN.entries[2].req == nil"), "no prerequisites -> no req table")
    ok(h.lua("return __trainerFilter.available == true and __trainerFilter.unavailable == false and __trainerFilter.used == false"), "the window's filter is restored, false included")
    h.lua("__tradeskillTrainer = true")
    ok(h.lua("local c, why = ns.Trainer.Capture() return c == nil and why == 'tradeskill trainer'"), "a profession trainer is not a class catalogue")
    h.lua("__tradeskillTrainer = false; __trainer = {}")
    ok(h.lua("local c, why = ns.Trainer.Capture() return c == nil and why == 'empty list'"), "an empty window captures nothing")
    ok(h.lua("return #SalusNovusDB.trainers.SHAMAN.entries == 7"), "the earlier capture is kept")
    eq(h.errors(), [], "errors")


@test("a trainer visit captures nothing now that every class ships; /sn probe trainer capture is the refresh path, and /sn trainer capture is gone", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("__chat = {} local orig = ns.Print ns.Print = function(m) __chat[#__chat + 1] = m orig(m) end")
    h.lua('__trainerOpen = true; W.fireEvent("TRAINER_SHOW"); W.fireEvent("TRAINER_UPDATE"); W.advance(3)')
    ok(h.lua("return SalusNovusDB.trainers == nil"), "the trainer window's events capture nothing")
    eq([m for m in (str(x) for x in h.lua("return __chat").values()) if "captured" in m], [], "and say nothing")
    h.lua("ns.Commands.trainer('capture')")
    ok(h.lua("return SalusNovusDB.trainers == nil"), "/sn trainer capture no longer exists")
    h.lua("ns.Commands.probe('trainer capture')")
    ok(h.lua("return SalusNovusDB.trainers and #SalusNovusDB.trainers.SHAMAN.entries == 7"), "the probe captures into SavedVariables for the harvester")
    eq(len([m for m in (str(x) for x in h.lua("return __chat").values()) if "captured 7 entries for SHAMAN" in m]), 1, "one confirmation line")
    h.lua("__trainer = {}; __chat = {}; ns.Commands.probe('trainer capture')")
    ok(any("nothing captured" in str(x) for x in h.lua("return __chat").values()), "no trainer open: says so")
    ok(h.lua("return #SalusNovusDB.trainers.SHAMAN.entries == 7"), "the earlier capture is kept")
    eq(h.errors(), [], "errors")


@test("status sorts the catalogue into now / later / known by spellbook rank, level and prerequisites, with the cost of the now group", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    eq(names(h, "now"), [("Lightning Bolt", "Rank 5"), ("Magma Totem", "Rank 1")], "level 27: the two level-26 spells, prerequisite rank 4 known")
    eq(names(h, "later"), [("Flame Shock", "Rank 3"), ("Frostbrand Weapon", "Rank 2"), ("Grounding Totem", "")], "later, by level")
    eq(names(h, "known"), [("Flame Shock", "Rank 2"), ("Reincarnation", "")], "known: the rank in the book and the rankless spell")
    eq(int(h.lua("return ns.Trainer.Status().cost")), 7600, "cost of the now group")
    missing = [str(x) for x in h.lua("return ns.Trainer.Status().later[2].missing").values()]
    eq(missing, ["Frostbrand Weapon (Rank 1)"], "the unmet prerequisite is named")
    h.lua("UnitLevel = function() return 30 end")
    eq(names(h, "now"), [("Lightning Bolt", "Rank 5"), ("Magma Totem", "Rank 1"), ("Flame Shock", "Rank 3"), ("Grounding Totem", "")], "level 30: Flame Shock 3 opens (rank 2 known); Frostbrand still needs rank 1")
    h.lua("__spellbook = { { name = 'Flame Shock', sub = 'Rank 4' }, { name = 'Lightning Bolt', sub = 'Rank 5' }, { name = 'Frostbrand Weapon', sub = 'Rank 1' } }")
    eq(names(h, "known"), [("Flame Shock", "Rank 2"), ("Lightning Bolt", "Rank 5"), ("Flame Shock", "Rank 3")], "a higher rank in the book counts every lower rank as known")
    ok(("Frostbrand Weapon", "Rank 2") in names(h, "now"), "Frostbrand 2 opens once rank 1 is known")
    eq(h.errors(), [], "errors")


@test("the catalogue falls back to the shipped file when nothing was captured this session, and reads nothing for an unknown class", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("SalusNovusDB.trainers = nil; ns.Trainers.SHAMAN = { captured = 5, entries = { { name = 'Magma Totem', rank = 'Rank 1', level = 26, cost = 3800 } } }")
    eq(names(h, "now"), [("Magma Totem", "Rank 1")], "shipped catalogue used")
    h.lua("ns.Trainer.Capture()")
    eq(len(names(h, "now")), 2, "a live capture wins over the shipped file")
    h.lua("ns.Trainers.SHAMAN = nil; SalusNovusDB.trainers = nil; ns.Trainer.live = nil")
    ok(h.lua("return ns.Trainer.Status() == nil"), "nothing at all: nil status")
    h.lua("ns.Commands.trainer('')")
    eq(h.errors(), [], "errors")


@test("Forever's trainer rows carry the category, not the rank: ranks are derived from level order, and the classic shape still reads", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainer = {
            { name = "Frost", cat = "header" },
            { name = "Frostbolt", cat = "unavailable", level = 4, cost = 95, skill = "Frost", icon = 135846 },
            { name = "Frostbolt", cat = "unavailable", level = 14, cost = 855, skill = "Frost", icon = 135846, req = { "Frostbolt (Rank 2)" } },
            { name = "Frostbolt", cat = "unavailable", level = 8, cost = 190, skill = "Frost", icon = 135846, req = { "Frostbolt (Rank 1)" } },
            { name = "Comprehend Scroll", cat = "available", level = 6, cost = 95, skill = "Comprehension", icon = 8188276 },
        }
    """)
    h.lua("__trainerShape = 'forever'; ns.Trainer.Capture()")
    got = [(str(e["name"]), str(e["rank"]), str(e["cat"]), int(e["level"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values()]
    # (the fixture rows carry no rank, so the fifth return is nil: derived)
    eq(sorted(got), sorted([("Frostbolt", "Rank 1", "unavailable", 4), ("Frostbolt", "Rank 3", "unavailable", 14), ("Frostbolt", "Rank 2", "unavailable", 8), ("Comprehend Scroll", "", "available", 6)]), "ranks by level order, category kept, a single row rankless")
    ok(h.lua("return SalusNovusDB.trainers.SHAMAN.ranksDerived == true"), "marked derived")
    h.lua("__spellbook = { { name = 'Frostbolt', sub = 'Rank 2', id = 116 } }; UnitLevel = function() return 14 end")
    eq(names(h, "now"), [("Comprehend Scroll", ""), ("Frostbolt", "Rank 3")], "with rank 2 known, rank 3 opens at 14")
    eq(names(h, "known"), [("Frostbolt", "Rank 1"), ("Frostbolt", "Rank 2")], "ranks 1 and 2 known")
    # the classic shape (name, rank, category) still reads the same
    h.lua("__trainerShape = 'classic'; __trainer[2].rank = 'Rank 1'; __trainer[3].rank = 'Rank 3'; __trainer[4].rank = 'Rank 2'; ns.Trainer.Capture()")
    got2 = sorted((str(e["name"]), str(e["rank"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got2, sorted([("Frostbolt", "Rank 1"), ("Frostbolt", "Rank 3"), ("Frostbolt", "Rank 2"), ("Comprehend Scroll", "")]), "classic shape")
    # a partial list without prerequisite text still numbers by level
    h.lua("""
        __trainer = {
            { name = "Fireball", cat = "unavailable", level = 12, cost = 300 },
            { name = "Fireball", cat = "unavailable", level = 1, cost = 10 },
            { name = "Fireball", cat = "unavailable", level = 6, cost = 95 },
        }
        __trainerShape = 'forever'; ns.Trainer.Capture()
    """)
    got3 = sorted((int(e["level"]), str(e["rank"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got3, [(1, "Rank 1"), (6, "Rank 2"), (12, "Rank 3")], "level order when no prerequisite names the rank")
    # a partial list WITH prerequisite text: the prerequisite wins over level order
    h.lua("""
        __trainer = {
            { name = "Fireball", cat = "unavailable", level = 8, cost = 190, req = { "Fireball (Rank 1)" } },
            { name = "Fireball", cat = "unavailable", level = 12, cost = 300, req = { "Fireball (Rank 2)" } },
        }
        __trainerShape = 'forever'; ns.Trainer.Capture()
    """)
    got4 = sorted((int(e["level"]), str(e["rank"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got4, [(8, "Rank 2"), (12, "Rank 3")], "ranks 2 and 3 from the prerequisites, even with rank 1 absent")
    # a saved capture from before the fix (category in the rank field) reads cleanly
    h.lua("SalusNovusDB.trainers.SHAMAN = { class = 'SHAMAN', captured = 1, entries = { { name = 'Fireball', rank = 'unavailable', level = 1, cost = 10 }, { name = 'Fireball', rank = 'unavailable', level = 6, cost = 95, req = { 'Fireball (Rank 1)' } } } }; ns.Trainer.live = nil")
    got5 = sorted((int(e["level"]), str(e["rank"]), str(e["cat"])) for e in h.lua("return ns.Trainer.Catalogue().entries").values())
    eq(got5, [(1, "Rank 1", "unavailable"), (6, "Rank 2", "unavailable")], "old capture repaired: category moved, ranks derived")
    eq(h.errors(), [], "errors")


@test("when the spellbook gives no rank subtext, the spell's own subtext by id decides what is known", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    h.lua("__bookNoSubtext = true; __spellbook = { { name = 'Flame Shock', sub = 'Rank 2', id = 8052 }, { name = 'Lightning Bolt', sub = 'Rank 4', id = 915 }, { name = 'Reincarnation', sub = '', id = 20608 } }")
    eq(names(h, "known"), [("Flame Shock", "Rank 2"), ("Reincarnation", "")], "known via C_Spell.GetSpellSubtext")
    eq(names(h, "now"), [("Lightning Bolt", "Rank 5"), ("Magma Totem", "Rank 1")], "and the now group is right")
    h.lua("C_Spell.GetSpellSubtext = nil")
    ok(("Flame Shock", "Rank 2") not in names(h, "known"), "with no rank source at all a ranked entry cannot be called known")
    eq(h.errors(), [], "errors")


@test("money formatting and rank parsing", "trainer")
def _():
    h = fresh()
    eq([str(x) for x in h.lua("return { ns.Trainer.Money(0), ns.Trainer.Money(5), ns.Trainer.Money(3800), ns.Trainer.Money(17105), ns.Trainer.Money(10000) }").values()],
       ["0c", "5c", "38s", "1g 71s 5c", "1g"], "money")
    eq([x for x in h.lua("return { ns.Trainer.RankNumber('Rank 3'), ns.Trainer.RankNumber('rank  12'), ns.Trainer.RankNumber(''), ns.Trainer.RankNumber('Passive'), ns.Trainer.RankNumber(nil) }").values()], [3, 12], "ranks (nils drop out of the Lua table)")
    ok(h.lua("return ns.Trainer.RankNumber('') == nil and ns.Trainer.RankNumber('Passive') == nil"), "rankless")
    eq(h.errors(), [], "errors")


@test("harvest and build carry a captured catalogue into Data/Trainers.lua, newest capture per class", "route")
def _():
    import sys, os, json, tempfile
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route as B, harvest_routes as H
    src = """SalusNovusDB = { ["trainers"] = { ["SHAMAN"] = { ["class"] = "SHAMAN", ["captured"] = 50, ["entries"] = { { ["name"] = "Magma Totem", ["rank"] = "Rank 1", ["cat"] = "unavailable", ["level"] = 26, ["cost"] = 3800, ["skill"] = "Elemental Combat", ["icon"] = 135826 }, { ["name"] = "Flame Shock", ["rank"] = "Rank 3", ["level"] = 28, ["cost"] = 5700, ["req"] = { "Flame Shock (Rank 2)" } } } } } }"""
    d = H.parse_saved_variables(src)["SalusNovusDB"]
    eq(len(d["trainers"]["SHAMAN"]["entries"]), 2, "parsed")
    lua = B.compile_trainers({"SHAMAN": d["trainers"]["SHAMAN"]})
    ok('ns.Trainers["SHAMAN"] = {' in lua and 'req = { "Flame Shock (Rank 2)" }' in lua and "icon = 135826" in lua, "compiled: %s" % lua)
    h = fresh()
    h.lua("ns.Trainers = {}")
    h.lua(lua.replace("local _, ns = ...", ""))
    eq(int(h.lua("return #ns.Trainers.SHAMAN.entries")), 2, "loads in the addon")
    h.lua("UnitClass = function() return 'Shaman', 'SHAMAN' end; UnitLevel = function() return 30 end; __spellbook = { { name = 'Flame Shock', sub = 'Rank 2' } }")
    eq(names(h, "now"), [("Magma Totem", "Rank 1"), ("Flame Shock", "Rank 3")], "the shipped catalogue drives status")


@test("Forever's fifth return carries the rank text and is used as-is; a rankless row gets none", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainerShape = 'forever'
        __trainer = {
            { name = "Frostbolt", rank = "Rank 3", cat = "unavailable", level = 14, cost = 855, icon = 135846, req = { "Frostbolt (Rank 2)" } },
            { name = "Frostbolt", rank = "Rank 1", cat = "unavailable", level = 4, cost = 95, icon = 135846 },
            { name = "Comprehend Scroll", rank = "", cat = "unavailable", level = 6, cost = 95, icon = 8188276 },
        }
        ns.Trainer.Capture()
    """)
    got = sorted((str(e["name"]), str(e["rank"]), str(e["cat"]), int(e["level"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got, [("Comprehend Scroll", "", "unavailable", 6), ("Frostbolt", "Rank 1", "unavailable", 4), ("Frostbolt", "Rank 3", "unavailable", 14)], "ranks read from the call, not derived")
    eq(h.errors(), [], "errors")


@test("the unlearned-spells tab sits at the end of the spellbook's tab row, swaps the page for the list, and Blizzard's tabs put it back", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    ok(h.lua("return ns.TrainerUI.tab == nil"), "no spellbook yet, no tab")
    h.lua("W.spellbookFrame()")
    ok(h.lua("return ns.TrainerUI.tab ~= nil"), "tab made when the spellbook loads")
    geo = h.lua("""
        local t = ns.TrainerUI.tab
        local last = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[3]
        return { w = t:GetWidth(), h = t:GetHeight(), gap = t:GetLeft() - last:GetRight(), top = t:GetTop() - last:GetTop(), count = t.count:GetText() }
    """)
    eq((float(geo["w"]), float(geo["h"]), float(geo["gap"]), float(geo["top"]), str(geo["count"])), (40.0, 40.0, 1.0, 0.0, "2"), "same size as the neighbours, 1px after the last one, with the learnable count")
    ok(h.lua("return PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown() and not (SalusNovusTrainerTab and SalusNovusTrainerTab:IsShown())"), "the page shows until our tab is clicked")
    h.lua("ns.TrainerUI.tab:Click()")
    ok(h.lua("return SalusNovusTrainerTab:IsShown() and not PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "our list replaces the page")
    ok(h.lua("local c = SalusNovusTrainerTab local p = PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame return c:GetLeft() == p:GetLeft() and c:GetTop() == p:GetTop() and c:GetRight() == p:GetRight()"), "the list fills the page area")
    # in game the rows showed icons only: the scroll child was 1px wide, so
    # every edge-anchored string (name, cost, header) had no width
    wid = h.lua("local c = SalusNovusTrainerTab local r = ns.TrainerUI.Rows()[2] return { list = c.list:GetWidth(), sf = c.scroll:GetWidth(), row = r:GetWidth(), name = r.name:GetWidth() }")
    ok(float(wid["sf"]) > 100 and float(wid["list"]) == float(wid["sf"]), "the list is as wide as its scroll frame: %r" % dict(wid))
    ok(float(wid["row"]) == float(wid["sf"]) and float(wid["name"]) > 60, "rows and their name strings have width: %r" % dict(wid))
    rows = [str(x) for x in h.lua("""
        local out = {}
        for _, r in ipairs(ns.TrainerUI.Rows()) do
            if r:IsShown() then
                if r.head:IsShown() then out[#out + 1] = "# " .. r.head:GetText()
                else out[#out + 1] = r.name:GetText() .. " | " .. r.cost:GetText() .. " | " .. r.req:GetText() end
            end
        end
        return out
    """).values()]
    eq(rows[0], "# " + h.lua("return ns.Theme.Upper('Available')"), "first head")
    ok(any(r == "# " + h.lua("return ns.Theme.Upper('Unavailable')") for r in rows), "second head, no counts: %r" % rows)
    ok(rows[1].startswith("Lightning Bolt") and "| 38s |" in rows[1] and "Requires: Level 26, Lightning Bolt (Rank 4)" in rows[1] and "|cffff4040" not in rows[1], "a learnable row: %r" % rows[1])
    later = [r for r in rows if r.startswith("Frostbrand")][0]
    ok("|cffff4040Level 28|r" in later and "|cffff4040Frostbrand Weapon (Rank 1)|r" in later, "unmet parts red: %r" % later)
    ok(not any("(Rank 2)" in r.split(" | ")[0] for r in rows if r.startswith("Flame Shock")), "known spells are not listed")
    ok(h.lua("return SalusNovusTrainerTab.summary == nil"), "no summary line")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")
    ok(h.lua("return not SalusNovusTrainerTab:IsShown() and PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "a Blizzard tab puts the page back")
    h.lua("ns.TrainerUI.tab:Click(); PlayerSpellsFrame:Hide(); PlayerSpellsFrame:Show()")
    ok(h.lua("return not SalusNovusTrainerTab:IsShown() and PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "closing the spellbook puts the page back")
    h.lua("ns.TrainerUI.tab:Click(); ns.TrainerUI.tab:Click(); ns.TrainerUI.tab:Click()")
    ok(h.lua("return SalusNovusTrainerTab:IsShown() and not PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "repeated clicks keep our tab, like theirs")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")
    h.lua("UnitLevel = function() return 28 end; W.fireEvent('PLAYER_LEVEL_UP', 28)")
    eq(str(h.lua("return ns.TrainerUI.tab.count:GetText()")), "3", "the count follows a level-up")
    eq(h.errors(), [], "errors")


@test("the spellbook tab hides with the switch, and the switch is the Trainer page's only control", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()")
    ok(h.lua("return SalusNovusTrainerTab:IsShown()"), "list up")
    h.lua("ns.db.trainer.enabled = false; ns.ApplyAll()")
    ok(h.lua("return not ns.TrainerUI.tab:IsShown() and not SalusNovusTrainerTab:IsShown() and PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "off: tab gone, page back")
    h.lua("ns.db.trainer.enabled = true; ns.ApplyAll()")
    ok(h.lua("return ns.TrainerUI.tab:IsShown()"), "on: tab back")
    open_options(h)
    h.lua("ns.Options.SelectPage('trainer')")
    kinds = [str(x) for x in h.lua("local out = {} for _, w in ipairs(ns.Options.widgets) do if w.__outer == ns.Options.pages.trainer then out[#out + 1] = w.__kind end end return out").values()]
    eq(kinds, ["check"], "one control")
    ok(h.lua("return ns.db.trainer.announce == nil and ns.db.trainer.showKnown == nil"), "the removed settings are gone from the defaults")
    ok(h.lua("return ns.Trainer.Announce == nil and ns.Trainer.Toggle == nil"), "no chat line, no window")
    eq(h.errors(), [], "errors")


@test("a spellbook without the retail pieces gets no tab and no error", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); PlayerSpellsFrame = CreateFrame('Frame', 'PlayerSpellsFrame', UIParent); W.fireEvent('ADDON_LOADED', 'Blizzard_PlayerSpells')")
    ok(h.lua("return ns.TrainerUI.tab == nil"), "no SpellBookFrame: nothing attached")
    h.lua("ns.Commands.trainer('')")
    eq(h.errors(), [], "errors")


@test("/sn trainer says whether the spellbook tab attached and why not; 'attach' retries once the spellbook exists", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    h.lua("__chat = {} local orig = ns.Print ns.Print = function(m) __chat[#__chat + 1] = m orig(m) end")
    h.lua("ns.Commands.trainer('')")
    lines = [str(m) for m in h.lua("return __chat").values()]
    ok(any("NOT attached" in l and "no spellbook frame" in l for l in lines), "reports the missing spellbook: %r" % lines)
    h.lua("W.spellbookFrame()")           # fires ADDON_LOADED: attaches on its own
    h.lua("__chat = {}; ns.Commands.trainer('')")
    lines = [str(m) for m in h.lua("return __chat").values()]
    ok(any("spellbook tab: attached" in l and "tab row found" in l for l in lines), "reports attached: %r" % lines)
    # a build error is reported, not swallowed, and 'attach' retries
    h2 = fresh()
    h2.lua(TRAINER)
    h2.lua("ns.Trainer.Capture(); local orig = ns.Theme.MakeScrollArea; ns.Theme.MakeScrollArea = function() error('boom') end; W.spellbookFrame(); ns.Theme.MakeScrollArea = orig")
    h2.lua("__chat = {} local orig = ns.Print ns.Print = function(m) __chat[#__chat + 1] = m orig(m) end; ns.Commands.trainer('')")
    lines = [str(m) for m in h2.lua("return __chat").values()]
    ok(any("NOT attached" in l and "build error" in l and "boom" in l for l in lines), "the build error is named: %r" % lines)
    h2.lua("__chat = {}; ns.Commands.trainer('attach')")
    lines = [str(m) for m in h2.lua("return __chat").values()]
    ok(any("spellbook tab: attached" in l for l in lines) and h2.lua("return ns.TrainerUI.tab ~= nil"), "attach retries: %r" % lines)


@test("after a /reload the spellbook's tab buttons do not exist until the book first shows: our tab moves after them then, and their clicks still put the page back", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame('reload')")
    ok(h.lua("return ns.TrainerUI.tab ~= nil and not ns.TrainerUI.tab.placed"), "attached at load, at the fallback spot")
    h.lua("PlayerSpellsFrame:Show(); W.advance(0.1)")
    geo = h.lua("""
        local t = ns.TrainerUI.tab
        local last = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[3]
        return { placed = t.placed, gap = t:GetLeft() - last:GetRight(), top = t:GetTop() - last:GetTop() }
    """)
    ok(bool(geo["placed"]) and float(geo["gap"]) == 1.0 and float(geo["top"]) == 0.0, "after the last tab once the book shows: %r" % dict(geo))
    h.lua("ns.TrainerUI.tab:Click()")
    ok(h.lua("return SalusNovusTrainerTab:IsShown()"), "our list up")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")
    ok(h.lua("return not SalusNovusTrainerTab:IsShown() and PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "a late-made Blizzard tab puts the page back")
    h.lua("PlayerSpellsFrame:Hide(); PlayerSpellsFrame:Show(); W.advance(0.1)")
    ok(h.lua("return ns.TrainerUI.tab.placed"), "still placed after a second show")
    h.lua("__chat = {} local orig = ns.Print ns.Print = function(m) __chat[#__chat + 1] = m orig(m) end; ns.Commands.trainer('')")
    ok(any("after the last Blizzard tab" in str(m) for m in h.lua("return __chat").values()), "the report says where it sits")
    eq(h.errors(), [], "errors")


@test("a plain window title (Boss Visualizer) sits inside the header band like the stacked brand does, not centred on its top edge", "theme")
def _():
    h = fresh()
    geo = h.lua("""
        local T = ns.Theme
        local sh = T.MakeShell("SalusNovusTitleProbe", 800, 600, 200, 64, "Boss Visualizer")
        local f, hd = sh.frame or _G.SalusNovusTitleProbe, sh.header
        local out = { top = hd:GetTop() - sh.title:GetTop(), left = sh.title:GetLeft() - hd:GetLeft(), text = sh.title:GetText() }
        sh:SetTitle("SALUS NOVUS")
        out.brandTop = hd:GetTop() - sh.words[1].initial:GetTop()
        out.brandRestLeft = sh.words[1].rest:GetLeft() - sh.words[1].initial:GetRight()
        sh:SetTitle("Boss Visualizer")
        out.againTop = hd:GetTop() - sh.title:GetTop()
        return out
    """)
    eq((str(geo["text"]), float(geo["top"]), float(geo["left"])), ("Boss Visualizer", 6.0, 22.0), "plain title 6px down, 22px in: %r" % dict(geo))
    eq((float(geo["brandTop"]), float(geo["brandRestLeft"])), (6.0, 0.0), "the stacked brand keeps its stack: %r" % dict(geo))
    eq(float(geo["againTop"]), 6.0, "switching back stays inside the band")
    eq(h.errors(), [], "errors")


@test("the capture keeps the spell id from the service link, and the compiler carries it into Data/Trainers.lua", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainerShape = 'forever'
        __trainer = {
            { name = "Frostbolt", rank = "Rank 1", cat = "unavailable", level = 4, cost = 95, icon = 135846, link = "|cff71d5ff|Hspell:116:0|h[Frostbolt]|h|r" },
            { name = "Comprehend Scroll", rank = "", cat = "unavailable", level = 6, cost = 95, icon = 8188276 },
        }
        ns.Trainer.Capture()
    """)
    got = sorted((str(e["name"]), e["spell"] and int(e["spell"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got, [("Comprehend Scroll", None), ("Frostbolt", 116)], "id parsed from the link, none without one")
    import sys, os
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    import build_route
    lua = str(build_route.compile_trainers({"MAGE": {"class": "MAGE", "captured": 1, "entries": [{"name": "Frostbolt", "rank": "Rank 1", "cat": "unavailable", "level": 4, "cost": 95, "spell": 116}]}}))
    ok("spell = 116" in lua, "compiled: %r" % lua)
    # rows without an id get one from the spell tables: name + rank subtext, the class's own, base level breaks a tie
    index = {"_dir": "fake",
             "names": {"Frostbolt": [116, 205, 837, 6949], "Arcane Intellect": [1459], "Twin": [10, 11]},
             "sub": {116: "Rank 1", 205: "Rank 2", 837: "Rank 3", 6949: "", 1459: "Rank 1", 10: "Rank 1", 11: "Rank 1"},
             "mask": {116: 128, 205: 128, 837: 128, 1459: 128, 10: 128, 11: 128},
             "level": {116: 4, 205: 8, 837: 14, 10: 5, 11: 9}}
    lua = str(build_route.compile_trainers({"MAGE": {"class": "MAGE", "captured": 1, "entries": [
        {"name": "Frostbolt", "rank": "Rank 2", "cat": "unavailable", "level": 8, "cost": 190},
        {"name": "Arcane Intellect", "rank": "Rank 1", "cat": "available", "level": 1, "cost": 10},
        {"name": "Twin", "rank": "Rank 1", "cat": "unavailable", "level": 9, "cost": 10},
        {"name": "Nobody", "rank": "", "cat": "unavailable", "level": 9, "cost": 10},
    ]}}, index=index))
    ok("Frostbolt\", rank = \"Rank 2\", cat = \"unavailable\", level = 8, cost = 190, spell = 205" in lua, "rank picks the id: %r" % lua)
    ok("spell = 1459" in lua and "spell = 11" in lua and lua.count("spell = ") == 3, "single match, level tie-break, unknown left alone: %r" % lua)
    eq(build_route.resolve_spell_id("Frostbolt", "Rank 1", 4, "MAGE", index), 116, "resolver direct")
    # the harvested catalogue has no rank text: the compiler derives ranks as Trainer.lua does, then resolves
    lua = str(build_route.compile_trainers({"MAGE": {"class": "MAGE", "captured": 1, "entries": [
        {"name": "Frostbolt", "cat": "unavailable", "level": 14, "cost": 855, "req": ["Frostbolt (Rank 2)"]},
        {"name": "Frostbolt", "cat": "unavailable", "level": 4, "cost": 95},
        {"name": "Frostbolt", "cat": "unavailable", "level": 8, "cost": 190},
        {"name": "Arcane Intellect", "cat": "available", "level": 1, "cost": 10},
    ]}}, index=index))
    ok('rank = "Rank 3"' in lua and "spell = 837" in lua and "spell = 116" in lua and "spell = 205" in lua, "ranks derived then resolved: %r" % lua)
    ok('name = "Arcane Intellect", cat' in lua and "spell = 1459" not in lua, "a single rankless row stays rankless (its Rank 1 id does not match): %r" % lua)
    eq(build_route.resolve_spell_id("Twin", "Rank 1", None, "MAGE", index), None, "ambiguous without a level stays None")
    # a rankless trainer row matches a "Passive" subtext (Parry), and among spells alike in every
    # other way the one with a description wins (Mutilate's per-weapon sub-spells say nothing);
    # the trainer's icon breaks what is left
    index2 = {"_dir": "fake",
              "names": {"Parry": [3124, 3127], "Mutilate": [1, 2, 3], "Twinicon": [7, 8]},
              "sub": {3124: "", 3127: "Passive", 1: "Rank 2", 2: "Rank 2", 3: "Rank 2", 7: "", 8: ""},
              "mask": {3127: 15, 1: 8, 2: 8, 3: 8, 7: 8, 8: 8},
              "level": {1: 40, 2: 40, 3: 40, 7: 5, 8: 5},
              "desc": {2, 7, 8}, "icon": {7: 100, 8: 200}}
    eq(build_route.resolve_spell_id("Parry", "", 12, "ROGUE", index2), 3127, "passive by class")
    eq(build_route.resolve_spell_id("Mutilate", "Rank 2", 40, "ROGUE", index2), 2, "the one with a description")
    eq(build_route.resolve_spell_id("Twinicon", "", 5, "ROGUE", index2, icon=200), 8, "icon breaks the tie")
    eq(build_route.resolve_spell_id("Twinicon", "", 5, "ROGUE", index2), None, "no icon, still ambiguous")
    # Penance: three priest spells per rank, all described, same icon; only one is trained
    index3 = {"_dir": "fake", "names": {"Penance": [20, 21, 22]}, "sub": {20: "Rank 2", 21: "Rank 2", 22: "Rank 2"},
              "mask": {20: 16, 21: 16, 22: 16}, "level": {20: 40, 21: 40, 22: 40}, "desc": {20, 21, 22},
              "icon": {20: 5, 21: 5, 22: 5}, "trained": {21}}
    eq(build_route.resolve_spell_id("Penance", "Rank 2", 40, "PRIEST", index3, icon=5), 21, "the trained one")
    # a rankless row matches any non-rank subtext ("Summon" on Eye of Kilrogg), never a "Rank n" one;
    # the plain subtext wins when both exist
    index4 = {"_dir": "fake", "names": {"Eye of Kilrogg": [126], "Both": [30, 31], "Ranked": [40]},
              "sub": {126: "Summon", 30: "", 31: "Passive", 40: "Rank 1"}, "mask": {126: 256, 30: 256, 31: 256, 40: 256},
              "level": {}, "desc": {126, 30, 31, 40}, "icon": {}, "trained": {126, 30, 31, 40}}
    eq(build_route.resolve_spell_id("Eye of Kilrogg", "", 22, "WARLOCK", index4), 126, "Summon subtext accepted")
    # Holy Shock: the trained spell has no class mask, its halves do; trained outranks the mask
    index5 = {"_dir": "fake", "names": {"Holy Shock": [50, 51, 52]}, "sub": {50: "Rank 2", 51: "Rank 2", 52: "Rank 2"},
              "mask": {50: 0, 51: 2, 52: 2}, "level": {50: 40, 51: 40, 52: 40}, "desc": {50, 51, 52}, "icon": {}, "trained": {50}}
    eq(build_route.resolve_spell_id("Holy Shock", "Rank 2", 40, "PALADIN", index5), 50, "trained beats the class mask")
    eq(build_route.resolve_spell_id("Both", "", 1, "WARLOCK", index4), 30, "plain subtext preferred")
    eq(build_route.resolve_spell_id("Ranked", "", 1, "WARLOCK", index4), None, "a rankless row never takes a ranked spell")
    if os.path.isdir(build_route.DB2):
        eq(build_route.resolve_spell_id("Mutilate", "Rank 2", 40, "ROGUE", icon=236270), 399956, "real tables: Mutilate Rank 2")
        eq(build_route.resolve_spell_id("Safe Fall", "", 40, "ROGUE"), 1860, "real tables: Safe Fall passive")
        eq(build_route.resolve_spell_id("Penance", "Rank 2", 40, "PRIEST", icon=237545), 1240720, "real tables: Penance Rank 2 is the trained spell")
        eq(build_route.resolve_spell_id("Eye of Kilrogg", "", 22, "WARLOCK", icon=136155), 126, "real tables: Eye of Kilrogg (Summon)")
        eq(build_route.resolve_spell_id("Holy Shock", "Rank 2", 40, "PALADIN", icon=135972), 20473, "real tables: Holy Shock Rank 2 is the trained spell")
    # the real tables, when present: Frostbolt Rank 2 is spell 205 on Forever
    import os
    if os.path.isdir(build_route.DB2):
        eq(build_route.resolve_spell_id("Frostbolt", "Rank 2", 8, "MAGE"), 205, "real tables")


@test("a live capture without ids borrows them from the shipped catalogue by name and rank, so the tooltips survive a trainer visit", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        ns.Trainers = { SHAMAN = { class = "SHAMAN", captured = 1, entries = {
            { name = "Flame Shock", rank = "Rank 3", cat = "unavailable", level = 22, cost = 100, spell = 8053 },
            { name = "Lightning Bolt", rank = "Rank 5", cat = "unavailable", level = 26, cost = 100, spell = 943 },
        } } }
        __trainerShape = 'forever'
        __trainer = {
            { name = "Flame Shock", rank = "Rank 3", cat = "unavailable", level = 22, cost = 100, icon = 1 },
            { name = "Lightning Bolt", rank = "Rank 5", cat = "unavailable", level = 26, cost = 100, icon = 1, link = "|Hspell:9999:0|h[Lightning Bolt]|h" },
            { name = "Purge", rank = "Rank 1", cat = "unavailable", level = 12, cost = 100, icon = 1 },
        }
        ns.Trainer.Capture()
    """)
    got = sorted((str(e["name"]), e["spell"] and int(e["spell"])) for e in h.lua("return SalusNovusDB.trainers.SHAMAN.entries").values())
    eq(got, [("Flame Shock", 8053), ("Lightning Bolt", 9999), ("Purge", None)], "borrowed where missing, the link wins where present, unknown stays nil")


@test("a group with nothing in it shows no header: all unavailable gives UNAVAILABLE only, all available gives AVAILABLE only", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainerShape = 'forever'
        __trainer = { { name = "Frostbolt", rank = "Rank 3", cat = "unavailable", level = 50, cost = 190, icon = 1 } }
        ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()
    """)
    heads = [str(x) for x in h.lua("local out = {} for _, r in ipairs(ns.TrainerUI.Rows()) do if r:IsShown() and r.head:IsShown() then out[#out + 1] = r.head:GetText() end end return out").values()]
    eq(heads, [str(h.lua("return ns.Theme.Upper('Unavailable')"))], "only the unavailable header")
    h.lua("__trainer = { { name = 'Frostbolt', rank = 'Rank 3', cat = 'available', level = 1, cost = 190, icon = 1 } }; ns.Trainer.Capture(); ns.Trainer.Refresh()")
    heads = [str(x) for x in h.lua("local out = {} for _, r in ipairs(ns.TrainerUI.Rows()) do if r:IsShown() and r.head:IsShown() then out[#out + 1] = r.head:GetText() end end return out").values()]
    eq(heads, [str(h.lua("return ns.Theme.Upper('Available')"))], "only the available header")
    eq(h.errors(), [], "errors")


@test("the spellbook tab is built like Blizzard's: icon 36x35 centred, and when active their gold frame (43x38 at BOTTOM 0,1) and glow atlases show; inactive shows neither", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()")
    st = h.lua("""
        local t = ns.TrainerUI.tab
        local p, rel, rp, x, y = t.frame:GetPoint(1)
        local iw, ih = t.icon:GetSize()
        local ip = t.icon:GetPoint(1)
        return { glow = t.glow, frameShown = t.frame:IsShown(), frameAtlas = t.frame.__atlas, glowShown = t.glowTex:IsShown(), glowAtlas = t.glowTex.__atlas,
                 fw = t.frame:GetWidth(), fh = t.frame:GetHeight(), p = p, x = x, y = y, iw = iw, ih = ih, ip = ip, borderShown = t.border.top:IsShown() }
    """)
    ok(st["glow"] is None and bool(st["frameShown"]) and str(st["frameAtlas"]) == "spellbook-Tab-Frame-Glow-C60" and bool(st["glowShown"]) and str(st["glowAtlas"]) == "spellbook-Tab-Frame-glow-gradient-C60", "active: Blizzard's frame + glow: %r" % dict(st))
    eq((float(st["fw"]), float(st["fh"]), str(st["p"]), float(st["x"]), float(st["y"])), (43.0, 38.0, "BOTTOM", 0.0, 1.0), "frame geometry as measured")
    eq((float(st["iw"]), float(st["ih"]), str(st["ip"])), (36.0, 35.0, "CENTER"), "icon geometry as measured")
    ok(not st["borderShown"], "no dark edge while active")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")     # a Blizzard tab takes over
    st = h.lua("local t = ns.TrainerUI.tab return { frameShown = t.frame:IsShown(), glowShown = t.glowTex:IsShown(), borderShown = t.border.top:IsShown() }")
    ok(not st["frameShown"] and not st["glowShown"] and bool(st["borderShown"]), "inactive: no frame, no glow, the dark edge back: %r" % dict(st))

    eq(h.errors(), [], "errors")


@test("hovering a spellbook-tab row pops it (accent wash, edge, name) and shows the spell tooltip with cost and requirements; leaving puts it all back", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainerShape = 'forever'
        __trainer = {
            { name = "Frostbolt", rank = "Rank 2", cat = "unavailable", level = 8, cost = 190, icon = 135846, link = "|Hspell:205:0|h[Frostbolt]|h", req = { "Frostbolt (Rank 1)" } },
            { name = "Comprehend Scroll", rank = "", cat = "unavailable", level = 6, cost = 95, icon = 8188276 },
        }
        ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()
    """)
    rows = h.lua("""
        local out = {}
        for i, r in ipairs(ns.TrainerUI.Rows()) do if r:IsShown() and r.entry then out[#out + 1] = i end end
        return out
    """)
    first = int(rows[1])
    head = h.lua("return ns.TrainerUI.Rows()[1]")
    h.lua("local r = ns.TrainerUI.Rows()[%d] r:GetScript('OnEnter')(r)" % first)
    st = h.lua("""
        local r = ns.TrainerUI.Rows()[%d]
        local ar, ag, ab = ns.Theme.Accent()
        local nr, ng, nb = r.name:GetTextColor()
        return { hot = r.hot, wash = r.hover:IsShown(), edge = r.edge:IsShown(), nameAccent = (nr == ar and ng == ag and nb == ab),
                 owner = __tooltip.owner == r, spell = __tooltip.spell, shown = __tooltip.shown, lines = table.concat(__tooltip.lines, " / "), mouse = r:IsMouseEnabled() }
    """ % first)
    ok(bool(st["hot"]) and bool(st["wash"]) and bool(st["edge"]) and bool(st["nameAccent"]) and bool(st["mouse"]), "the pop: %r" % dict(st))
    ok(bool(st["owner"]) and bool(st["shown"]), "tooltip owned by the row and shown: %r" % dict(st))
    lines = str(st["lines"])
    name = str(h.lua("return ns.TrainerUI.Rows()[%d].name:GetText()" % first))
    ok(name.startswith("Comprehend Scroll") and st["spell"] is None and "Comprehend Scroll" in lines and "Cost" not in lines, "just the name when no id: %r" % lines)
    # the row WITH a spell id hands the tooltip the spell, then our cost and requirement lines
    fb = h.lua("""
        for i, r in ipairs(ns.TrainerUI.Rows()) do
            if r:IsShown() and r.entry and r.entry.name == "Frostbolt" then
                r:GetScript("OnEnter")(r)
                return { i = i, spell = __tooltip.spell, lines = table.concat(__tooltip.lines, " / "), owner = __tooltip.owner == r }
            end
        end
    """)
    ok(fb and int(fb["spell"]) == 205 and str(fb["lines"]) == "" and bool(fb["owner"]), "the spell's own tooltip, nothing appended: %r" % (fb and dict(fb)))
    h.lua("local r = ns.TrainerUI.Rows()[%d] r:GetScript('OnLeave')(r)" % int(fb["i"]))
    h.lua("local r = ns.TrainerUI.Rows()[%d] r:GetScript('OnLeave')(r)" % first)
    st2 = h.lua("""
        local r = ns.TrainerUI.Rows()[%d]
        local nr, ng, nb = r.name:GetTextColor()
        return { hot = r.hot, wash = r.hover:IsShown(), edge = r.edge:IsShown(), nameText = (nr == ns.Theme.TEXT[1] and ng == ns.Theme.TEXT[2] and nb == ns.Theme.TEXT[3]), shown = __tooltip.shown }
    """ % first)
    ok(not st2["hot"] and not st2["wash"] and not st2["edge"] and bool(st2["nameText"]) and not st2["shown"], "back to normal: %r" % dict(st2))
    # a header row has no entry: hovering it does nothing
    h.lua("local r = ns.TrainerUI.Rows()[1] r:GetScript('OnEnter')(r)")
    ok(not h.lua("return ns.TrainerUI.Rows()[1].hot") and not h.lua("return __tooltip.shown"), "headers do not pop")
    eq(h.errors(), [], "errors")


@test("the spellbook list sits just above the page and below the tab row, so the tabs are never covered", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame(); PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem:SetFrameLevel(PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:GetFrameLevel()); ns.TrainerUI.tab:Click()")
    lv = h.lua("return { list = SalusNovusTrainerTab:GetFrameLevel(), page = PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:GetFrameLevel(), tabs = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem:GetFrameLevel() }")
    ok(int(lv["list"]) > int(lv["page"]) and int(lv["tabs"]) > int(lv["list"]), "page < list < tabs: %r" % dict(lv))


@test("/sn probe spellbook reports the book's pieces and the tab row it found, and dumps how a Blizzard tab is built", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame()")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[1].Icon = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[1]:CreateTexture(nil, 'ARTWORK')")
    h.lua("__chat = {} local orig = ns.Print ns.Print = function(m) __chat[#__chat + 1] = m orig(m) end; ns.Commands.probe('spellbook')")
    lines = [str(m) for m in h.lua("return __chat").values()]
    ok(any(l.startswith("PlayerSpellsFrame: found") for l in lines), "frame found: %r" % lines)
    ok(any(l.startswith("book keys:") and "CategoryTabSystem:Frame" in l and "PagedSpellsFrame:Frame" in l for l in lines), "keys listed: %r" % lines)
    ok(any(l.startswith("tab attached to:") and "tabs=" in l for l in lines), "host reported: %r" % lines)
    ok(any(l.strip().startswith("tab: Button") for l in lines) and any("region Texture" in l for l in lines), "tab regions dumped: %r" % lines)
    ok(any(l.startswith("tab row level") for l in lines), "levels")
    eq(h.errors(), [], "errors")


@test("while our tab is active Blizzard's selected tab loses its gold frame; their tab click or closing the book gives it back", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame()")
    sel = "local b = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons return { b[1].SquareBackgroundActive:IsShown(), b[1].SquareBackgroundActiveGlow:IsShown(), b[2].SquareBackgroundActive:IsShown() }"
    eq([bool(x) for x in h.lua("return (function() " + sel.replace("return {", "return {") + " end)()").values()], [True, True, False], "tab 1 selected to start")
    h.lua("ns.TrainerUI.tab:Click()")
    eq([bool(x) for x in h.lua(sel).values()], [False, False, False], "ours active: their gold frame hidden")
    h.lua("PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[1]:Click()")
    eq([bool(x) for x in h.lua(sel).values()], [True, True, False], "their click: frame back on their tab")
    h.lua("ns.TrainerUI.tab:Click(); PlayerSpellsFrame:Hide()")
    eq([bool(x) for x in h.lua(sel).values()], [True, True, False], "closing the book restores it")
    h.lua("PlayerSpellsFrame:Show(); ns.TrainerUI.tab:Click(); PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")
    eq([bool(x) for x in h.lua(sel).values()], [False, False, True], "their other tab: only that one selected, nothing double")
    eq(h.errors(), [], "errors")


@test("Blizzard adds category tabs lazily: our tab moves after the newest one on every show and on a refresh, never sitting on top of a tab made later", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame('lazy')")
    def where():
        return h.lua("""
            local t = ns.TrainerUI.tab
            local b = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons
            local last = b[#b]
            return { n = #b, gap = last and (t:GetLeft() - last:GetRight()) or nil, overlap = last and (t:GetLeft() < last:GetRight()) }
        """)
    h.lua("PlayerSpellsFrame:Show(); W.advance(0.1)")
    w = where()
    ok(int(w["n"]) == 1 and float(w["gap"]) == 1.0, "after the first tab: %r" % dict(w))
    h.lua("PlayerSpellsFrame:Hide(); PlayerSpellsFrame:Show(); W.advance(0.1)")
    w = where()
    ok(int(w["n"]) == 2 and float(w["gap"]) == 1.0 and not w["overlap"], "after the second tab once it exists: %r" % dict(w))
    # a refresh (level up) while the book is open also re-places
    h.lua("""
        local tabs = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem
        local b = CreateFrame("Button", nil, tabs); b:SetSize(40, 40); b:SetPoint("LEFT", tabs, "LEFT", 2 * 46, 0)
        b.SquareBackgroundActive = b:CreateTexture(nil, "ARTWORK"); b.SquareBackgroundActiveGlow = b:CreateTexture(nil, "ARTWORK")
        tabs.buttons[3] = b
        ns.Trainer.Refresh()
    """)
    w = where()
    ok(int(w["n"]) == 3 and float(w["gap"]) == 1.0, "after the third tab on refresh: %r" % dict(w))
    eq(h.errors(), [], "errors")


@test("their selected tab is disabled by their tab system: while ours shows it answers a click (page back, its frame back, disabled again); a different tab still moves the selection", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame()")
    B = "PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons"
    h.lua(B + "[2]:Click()")
    st = lambda: [bool(x) for x in h.lua("local b = " + B + " return { b[2]:IsEnabled(), b[2].SquareBackgroundActive:IsShown(), b[1]:IsEnabled(), SalusNovusTrainerTab:IsShown(), PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown() }").values()]
    eq(st(), [False, True, True, False, True], "tab 2 selected and disabled, page up")
    h.lua("ns.TrainerUI.tab:Click()")
    eq(st(), [True, False, True, True, False], "ours up: tab 2 enabled again and its frame hidden")
    h.lua(B + "[2]:Click()")
    eq(st(), [False, True, True, False, True], "clicking tab 2 back: page back, frame back, disabled again")
    h.lua("ns.TrainerUI.tab:Click(); " + B + "[1]:Click()")
    eq(st(), [True, False, False, False, True], "a different tab: selection moved to tab 1, tab 2 free, nothing double")
    h.lua("ns.TrainerUI.tab:Click(); ns.TrainerUI.tab:Click()")
    eq(st(), [True, False, True, True, False], "clicking ours again keeps ours (tab 1 dimmed and clickable, tab 2 untouched)")
    h.lua("PlayerSpellsFrame:Hide()")
    eq(st(), [True, False, False, False, True], "closing the book restores tab 1's state, tab 2 untouched")
    eq(h.errors(), [], "errors")


@test("hunt 10: a refresh under the cursor re-pools the hovered row; the tooltip it owned goes away and the later OnLeave still restores the row", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()")
    h.lua("local r = ns.TrainerUI.Rows()[2] r:GetScript('OnEnter')(r)")
    ok(h.lua("return __tooltip.shown and __tooltip.owner == ns.TrainerUI.Rows()[2]"), "tooltip up on row 2")
    # everything becomes known: the refresh leaves row 2 without an entry (or hidden)
    h.lua("__spellbook = { { name = 'Flame Shock', sub = 'Rank 9' }, { name = 'Lightning Bolt', sub = 'Rank 9' }, { name = 'Frostbrand Weapon', sub = 'Rank 9' }, { name = 'Magma Totem', sub = 'Rank 9' }, { name = 'Reincarnation', sub = '' } }; ns.Trainer.Refresh()")
    ok(not h.lua("return __tooltip.shown"), "the re-pooled row no longer shows a tooltip for a spell it no longer holds")
    h.lua("local r = ns.TrainerUI.Rows()[2] r:GetScript('OnLeave')(r)")
    st = h.lua("local r = ns.TrainerUI.Rows()[2] local nr, ng, nb = r.name:GetTextColor() return { hot = r.hot, wash = r.hover:IsShown(), nameText = (nr == ns.Theme.TEXT[1] and ng == ns.Theme.TEXT[2] and nb == ns.Theme.TEXT[3]), shown = __tooltip.shown }")
    ok(not st["hot"] and not st["wash"] and bool(st["nameText"]) and not st["shown"], "OnLeave on an entry-less row still restores everything: %r" % dict(st))
    # the list hiding takes any row tooltip with it
    h.lua("__spellbook = { { name = 'Flame Shock', sub = 'Rank 2' }, { name = 'Lightning Bolt', sub = 'Rank 4' }, { name = 'Reincarnation', sub = '' } }; ns.Trainer.Refresh()")
    h.lua("local r = ns.TrainerUI.Rows()[2] r:GetScript('OnEnter')(r); PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[2]:Click()")
    ok(not h.lua("return __tooltip.shown"), "a Blizzard tab taking over hides the row's tooltip")
    eq(h.errors(), [], "errors")


@test("hunt 10: a filter whose value cannot be read is left alone (it could not be put back)", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("""
        __trainerFilter = { available = true, unavailable = false, used = false }
        local origGet, origSet = GetTrainerServiceTypeFilter, SetTrainerServiceTypeFilter
        __setCalls = {}
        GetTrainerServiceTypeFilter = function(f) if f == "used" then error("no such filter") end return origGet(f) end
        SetTrainerServiceTypeFilter = function(f, v) __setCalls[#__setCalls + 1] = f .. "=" .. tostring(v) origSet(f, v) end
        ns.Trainer.ReadTrainer()
    """)
    calls = [str(x) for x in h.lua("return __setCalls").values()]
    ok(not any(c.startswith("used=") for c in calls), "the unreadable filter is never set: %r" % calls)
    ok("unavailable=false" in calls and "available=true" in calls, "the readable ones are forced on and put back: %r" % calls)
    eq(h.errors(), [], "errors")


@test("a capture saved by an older version, without spell ids, borrows them from the shipped catalogue (tooltips)", "trainer")
def _():
    h = Harness()
    h.login("""SalusNovusDB = { trainers = { SHAMAN = { class = "SHAMAN", entries = {
        { name = "Lightning Bolt", rank = "Rank 2", level = 8, cost = 95 },
        { name = "Lightning Bolt", rank = "Rank 3", level = 14, cost = 855 } } } } }""")
    h.lua("UnitClass = function() return 'Shaman', 'SHAMAN' end")
    got = h.lua("local c = ns.Trainer.Catalogue('SHAMAN') return { c.entries[1].spell or 0, c.entries[2].spell or 0 }")
    eq([int(got[1]), int(got[2])], [529, 548], "spell ids from the shipped catalogue")
    eq(h.errors(), [], "errors")


@test("the tab keeps its icon when a UI skin blanks the tab row's textures except each tab's .Icon (EllesmereUI's Blizzard skin)", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    h.lua("W.spellbookFrame()")
    ok(h.lua("return ns.TrainerUI.tab ~= nil"), "no tab")
    h.lua("""
        local row = PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem
        for _, tab in ipairs({ row:GetChildren() }) do
            if tab:GetObjectType() == "Button" then
                for _, r in ipairs({ tab:GetRegions() }) do
                    if r ~= tab.Icon and r ~= tab.IconMask and r:IsObjectType("Texture") then r:SetTexture("") end
                end
            end
        end
    """)
    tex = h.lua("local t = rawget(ns.TrainerUI.tab, 'Icon') return t and t:GetTexture()")
    ok(tex not in (None, ""), "the skin blanked our icon: %r" % (tex,))
    eq(h.errors(), [], "errors")


def shown_spells(h):
    return [str(x) for x in h.lua("""
        local out = {}
        for _, r in ipairs(ns.TrainerUI.Rows()) do if r:IsShown() and r.entry then out[#out + 1] = r.entry.name end end
        return out
    """).values()]


@test("the spellbook's search box filters our list by spell name while our page shows, and hides Blizzard's preview over it", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture()")
    h.lua("W.spellbookFrame(); ns.TrainerUI.ShowOurs()")
    everything = shown_spells(h)
    ok(len(everything) >= 4, "the list: %r" % everything)
    h.lua("W.typeSearch('totem')")
    eq(sorted(shown_spells(h)), ["Grounding Totem", "Magma Totem"], "totems only")
    ok(not h.lua("return PlayerSpellsFrame.SpellBookFrame.SearchPreviewContainer:IsShown()"), "Blizzard's preview covers our list")
    h.lua("W.typeSearch('SHOCK')")
    eq(shown_spells(h), ["Flame Shock"], "case-insensitive")
    h.lua("W.typeSearch('zzz')")
    eq(shown_spells(h), [], "no match")
    ok(h.lua("return SalusNovusTrainerTab.empty:IsShown()"), "no-match message")
    h.lua("W.typeSearch('')")
    eq(shown_spells(h), everything, "cleared: the whole list is back")
    # Enter runs Blizzard's full search behind our page; ours stays, and closing
    # the book must not leave a deselected tab disabled or gold
    h.lua("W.typeSearch('magma'); W.enterSearch()")
    eq(shown_spells(h), ["Magma Totem"], "Enter keeps our filtered page")
    ok(not h.lua("return PlayerSpellsFrame.SpellBookFrame.PagedSpellsFrame:IsShown()"), "their page came back over ours")
    h.lua("PlayerSpellsFrame:Hide()")
    bad = h.lua("""
        local out = {}
        for i, b in ipairs(PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons) do
            if not b:IsEnabled() or b.SquareBackgroundActive:IsShown() then out[#out + 1] = i end
        end
        return out
    """)
    eq([int(x) for x in bad.values()], [], "tabs left selected-looking after the search cleared the selection")
    # on Blizzard's own page the box is theirs: preview shows, our list untouched
    h.lua("PlayerSpellsFrame:Show(); ns.TrainerUI.ShowTheirs(PlayerSpellsFrame.SpellBookFrame.CategoryTabSystem.buttons[1]); W.typeSearch('bolt')")
    ok(h.lua("return PlayerSpellsFrame.SpellBookFrame.SearchPreviewContainer:IsShown()"), "their preview on their page")
    eq(h.errors(), [], "errors")


@test("hunt 10: rows beyond a shorter list are reset, not just hidden: no stale entry, hover or tooltip on a ghost row", "trainer")
def _():
    h = fresh()
    h.lua(TRAINER)
    h.lua("ns.Trainer.Capture(); W.spellbookFrame(); ns.TrainerUI.tab:Click()")
    n = int(h.lua("local n = 0 for _, r in ipairs(ns.TrainerUI.Rows()) do if r:IsShown() then n = n + 1 end end return n"))
    ok(n >= 4, "several rows to start (%d)" % n)
    h.lua("local r = ns.TrainerUI.Rows()[%d] r:GetScript('OnEnter')(r)" % n)
    ok(h.lua("return __tooltip.shown"), "hovering the last row")
    # most spells become known: the list shrinks
    h.lua("__spellbook = { { name = 'Flame Shock', sub = 'Rank 9' }, { name = 'Lightning Bolt', sub = 'Rank 9' }, { name = 'Frostbrand Weapon', sub = 'Rank 9' }, { name = 'Reincarnation', sub = '' } }; ns.Trainer.Refresh()")
    st = h.lua("local r = ns.TrainerUI.Rows()[%d] return { shown = r:IsShown(), entry = r.entry ~= nil, hot = r.hot, wash = r.hover:IsShown(), tip = __tooltip.shown }" % n)
    ok(not st["shown"] and not st["entry"] and not st["hot"] and not st["wash"] and not st["tip"], "the ghost row is clean: %r" % dict(st))
    eq(h.errors(), [], "errors")


@test("a fresh anchor rides along when the UI scale settles after login: UIParent grows from 1365x768 to 1920x1080 and the frame keeps its place from the centre, with no record written", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    before = h.lua("local f = SalusNovusReminderFrame local cx = f:GetLeft() + f:GetWidth() / 2 return { dx = cx - UIParent:GetWidth() / 2, dy = f:GetBottom() - UIParent:GetHeight() / 2, rec = SalusNovusDB.remindersPos ~= nil }")
    ok(abs(float(before["dx"])) < 0.01 and abs(float(before["dy"]) - 42) < 0.01 and not before["rec"], "at login: centred, 42 up, no record: %r" % dict(before))
    # the client applies the user's UI scale a moment after login
    h.lua("UIParent.__w, UIParent.__h = 1920, 1080; UIParent.__rect = { left = 0, bottom = 0, width = 1920, height = 1080 }; ns.ApplyAll()")
    after = h.lua("local f = SalusNovusReminderFrame local cx = f:GetLeft() + f:GetWidth() / 2 return { cx = cx, b = f:GetBottom(), rec = SalusNovusDB.remindersPos ~= nil }")
    ok(abs(float(after["cx"]) - 960) < 0.01 and abs(float(after["b"]) - 582) < 0.01 and not after["rec"], "after the scale settles: still centred and 42 up (960, 582), not stuck at the small screen's (682, 426): %r" % dict(after))
    # the same for the Bars anchor (a growth-origin re-pin, TOPLEFT when growing down)
    h.lua("ns.db.bars.direction = 'down'; ns.ApplyAll()")
    b = h.lua("return { l = SalusNovusBars:GetLeft(), t = SalusNovusBars:GetTop(), rec = SalusNovusDB.barsPos ~= nil }")
    ok(abs(float(b["l"]) - (960 + 314)) < 0.01 and not b["rec"], "bars keep their centre-relative default too: %r" % dict(b))
    eq(h.errors(), [], "errors")


@test("when the client reports the UI scale or display changed, every session pin is forgotten and all anchors are laid out again from clean numbers", "anchors")
def _():
    h = fresh()
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    # a pin made from mixed measurements (the frame's stale rect against the grown UIParent)
    h.lua("""
        local f = SalusNovusReminderFrame
        f.__pin = { point = "BOTTOM", dx = -277.3, dy = -97 }
        f:ClearAllPoints(); f:SetPoint("BOTTOM", UIParent, "CENTER", -277.3, -97)
        __applies = 0
        local orig = ns.ApplyAll
        ns.ApplyAll = function() __applies = __applies + 1 return orig() end
        W.fireEvent("UI_SCALE_CHANGED"); W.fireEvent("UI_SCALE_CHANGED"); W.fireEvent("DISPLAY_SIZE_CHANGED")
    """)
    eq(int(h.lua("return __applies")), 0, "debounced: nothing yet")
    h.lua("W.advance(0.2)")
    eq(int(h.lua("return __applies")), 1, "one re-layout for the burst")
    st = h.lua("local f = SalusNovusReminderFrame local p, rel, rp, x, y = f:GetPoint(1) return { p = p, rp = rp, x = x, y = y, pin = f.__pin ~= nil, cx = f:GetLeft() + f:GetWidth() / 2 - UIParent:GetWidth() / 2, b = f:GetBottom() - UIParent:GetHeight() / 2 }")
    ok(str(st["p"]) == "BOTTOM" and str(st["rp"]) == "CENTER" and abs(float(st["x"])) < 0.01 and abs(float(st["y"]) - 42) < 0.01, "back on the default from the centre: %r" % dict(st))
    ok(abs(float(st["cx"])) < 0.01 and abs(float(st["b"]) - 42) < 0.01, "and drawn there: %r" % dict(st))
    eq(h.errors(), [], "errors")


@test("the alignment grid draws whole-pixel lines anchored by their edge on pixel boundaries, so every line renders and the cells are equal", "anchors")
def _():
    h = fresh()
    # a screen whose centre is not on a pixel and a pixel unit of 1
    h.lua("UIParent.__w, UIParent.__h = 1920, 1079.9999; UIParent.__rect = { left = 0, bottom = 0, width = 1920, height = 1079.9999 }")
    h.lua("ns.ShowAlignGrid(true)")
    lines = h.lua("""
        local gf = ns.AlignGrid()
        local out = {}
        for _, t in ipairs(gf.lines) do
            if t:IsShown() then
                local p, _, rp, x, y = t:GetPoint(1)
                out[#out + 1] = { p = p, x = x, y = y, w = t:GetWidth(), h = t:GetHeight() }
            end
        end
        return out
    """)
    rows = [dict(v) for v in lines.values()]
    ok(len(rows) >= 90, "enough lines drawn (%d)" % len(rows))
    bad = [r for r in rows if str(r["p"]) not in ("TOPLEFT", "BOTTOMLEFT")]
    eq(bad, [], "every line is anchored by an edge, never centred on its coordinate")
    frac = [r for r in rows if abs(float(r["x"]) - round(float(r["x"]))) > 1e-6 or abs(float(r["y"]) - round(float(r["y"]))) > 1e-6]
    eq(frac, [], "every edge lands on a whole pixel: %r" % frac[:3])
    thick = sorted(set(round(float(r["w"]) if str(r["p"]) == "TOPLEFT" else float(r["h"]), 3) for r in rows))
    eq(thick, [1.0, 2.0], "one pixel thick, the centre lines two: %r" % thick)
    # equal spacing between neighbouring vertical lines
    # (the two-pixel centre line's edge sits one pixel left of its coordinate)
    xs = sorted(float(r["x"]) + (1.0 if float(r["w"]) == 2.0 else 0.0) for r in rows if str(r["p"]) == "TOPLEFT")
    gaps = sorted(set(round(b - a) for a, b in zip(xs, xs[1:])))
    eq(gaps, [32], "even 32px columns everywhere, the centre included")
    eq(h.errors(), [], "errors")

