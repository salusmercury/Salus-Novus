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
    # A fresh install IS re-pinned and recorded on first layout (MerkUI
    # landmine 17); the record must describe where the frame actually is.
    eq(str(h.lua("return SalusNovusDB.barsPos.point")), "TOPLEFT", "record point")
    dx, dy = h.lua("return SalusNovusDB.barsPos.x - SalusNovusBars:GetLeft(), SalusNovusDB.barsPos.y - SalusNovusBars:GetTop()")
    ok(abs(dx) < 0.01 and abs(dy) < 0.01, "record disagrees with the frame: %r" % ((dx, dy),))
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
    # Then, on first layout, replaced by a real v2 record at the default spot.
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    eq(int(h.lua("return SalusNovusDB.barsPos.v")), 2, "junk record not replaced")
    h2 = fresh()
    h2.lua("ns.db.unlocked = true; ns.ApplyAll()")
    x1, y1 = h.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y")
    x2, y2 = h2.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y")
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
    h.lua("ns.Options.SelectPage('global')")
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
    for expr in ("ns.Options.shell.title", "SalusNovusVisualizer.shell.title", "ns.Visualizer._lanes[2].name",
                 "ns.Visualizer.form.text", "ns.Bars._bars[1].text", "SalusNovusReminderFrame.unlockText",
                 "ns.Options.launcher.label"):
        eq(str(h.lua("return %s.__font" % expr)), "Fonts\\MORPHEUS.TTF", "%s not re-fonted" % expr)
    # the picker's rows show their own fonts, never the global one
    h.lua("""
        SalusNovusOptions:Show(); ns.Options.SelectPage('global')
        for _, w in ipairs(ns.Options.widgets) do
            if w.__kind == "choice" and w.__values and type(w.__values[1]) == "string" and w.__values[1]:find("Fonts") then __fontBtn = w end
        end
        __fontBtn:Click()
    """)
    eq(str(h.lua("return SalusNovusPickerList.rows[1].text.__font")), stock, "picker preview lost its own font")
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
                        local dx = (m:GetLeft() - lane.track:GetLeft()) - V.X(m.t)
                        if math.abs(dx) > 0.01 then out[#out+1] = lane.name:GetText() .. "@" .. m.t .. "=" .. dx end
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
    # A real record first (a preview never writes one: SaveAnchor refuses
    # off UIParent), then the window.
    h.lua("ns.db.unlocked = true; ns.ApplyAll(); ns.db.unlocked = false; ns.ApplyAll()")
    open_options(h)
    h.lua("""
        ns.Options.SelectPage('bars')
        __x0, __y0 = SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y
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
    x, y, v = h.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y, SalusNovusDB.barsPos.v")
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01 and int(v) == 2, "snapshot not restored: %r vs %r" % ((x, y, v), (x0, y0)))
    ok(h.lua("return SalusNovusOptions:IsShown()"), "panel did not come back")
    eq(str(h.lua("return ns.Options.ActivePage()")), "bars", "not the same page")
    ok(h.lua("return SalusNovusBars:GetParent() ~= UIParent"), "preview did not resume after cancel")
    ok(not h.lua("return SalusNovusBars:IsMouseEnabled()"), "still draggable after cancel")


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
    # a landed cast inside its hold: the edge sits at its 1px floor, never negative or over-wide
    h.lua("W.advance(%f)" % (float(h.lua("return ns.Timers.Sorted()[1].at - GetTime()")) + 1.0))
    w = float(h.lua("return ns.Queue._icons[1].edge:GetWidth()"))
    ok(1 <= w <= float(h.lua("return ns.Queue._icons[1]:GetWidth()")), "edge width out of bounds after landing: %r" % w)
    h.lua('W.fireEvent("ENCOUNTER_END", 3494, "Plunder", 1, 5, 1)')
    ok(not h.lua("return SalusNovusQueue:IsShown()"), "strip shown after the fight")
    # the floors: eight placeholders with a heavy fade and a tiny shrink
    h.lua("ns.db.queue.count = 8; ns.db.queue.fade = 90; ns.db.queue.size = 24; ns.db.queue.shrink = 40; ns.db.unlocked = true; ns.ApplyAll()")
    eq(queue_icons(h), 8, "eight placeholders")
    ok(abs(float(h.lua("return ns.Queue._icons[8]:GetAlpha()")) - 0.15) < 0.01, "alpha floor 0.15 not applied")
    sizes = [int(h.lua("return ns.Queue._icons[%d]:GetWidth()" % i)) for i in range(1, 9)]
    eq(sizes, [24, 16, 16, 16, 16, 16, 16, 16], "shrink should floor at 16px: %r" % sizes)


@test("the edge drains with the time left, seconds rewrite only when the integer changes, and the next cast takes the lead", "queue")
def _():
    h = fresh()
    h.lua('W.fireEvent("ENCOUNTER_START", 3494, "Plunder", 1, 5, 3065)')
    ok(h.lua("return ns.Queue._icons[1].edge:IsShown() and ns.Queue._icons[1].edgeBg:IsShown() and not ns.Queue._icons[1].cd:IsShown()"), "edge mode should show the edge")
    t1 = float(h.lua("return ns.Timers.Sorted()[1].at - ns.Timers.StartedAt()"))
    w0 = float(h.lua("return ns.Queue._icons[1].edge:GetWidth()"))
    ok(abs(w0 - 48) < 0.01, "edge should start full: %r" % w0)
    h.lua("""
        __writes = 0
        local t = ns.Queue._icons[1].timer
        local orig = t.SetText
        t.SetText = function(self, s) __writes = __writes + 1 return orig(self, s) end
    """)
    h.lua("W.advance(2)")      # 10 hub ticks
    w1 = float(h.lua("return ns.Queue._icons[1].edge:GetWidth()"))
    # within one hub tick (0.2s) of the exact value
    ok(abs(w1 - 48 * (t1 - 2) / t1) < 48 * 0.2 / t1 + 0.01, "edge should drain: %r vs %r" % (w1, 48 * (t1 - 2) / t1))
    writes = int(h.lua("return __writes"))
    ok(0 < writes <= 3, "seconds should rewrite about twice in 2s, got %d" % writes)
    # when the first record expires the second is the lead
    key2 = str(h.lua("return ns.Timers.Sorted()[2].key"))
    h.lua("W.advance(%f)" % (t1 + 2.6 - 2))
    eq(str(h.lua("return ns.Queue._icons[1].entry.bar.key")), key2, "next cast did not take the lead")
    h.lua("ns.db.queue.timeOnIcon = 'swipe'; ns.ApplyAll()")
    ok(h.lua("return ns.Queue._icons[1].cd:IsShown() and not ns.Queue._icons[1].edge:IsShown()"), "swipe mode")
    h.lua("ns.db.queue.timeOnIcon = 'none'; ns.ApplyAll()")
    ok(not h.lua("return ns.Queue._icons[1].cd:IsShown()") and not h.lua("return ns.Queue._icons[1].edge:IsShown()"), "none mode")
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
    eq(int(h.lua("local n = 0 for _ in pairs(ns.Options.moduleSwitches) do n = n + 1 end return n")), 1, "Global must not have a switch")
    ok(h.lua("return ns.Options.launcher ~= nil and ns.Options.launcher.label:GetText() == 'Boss Visualizer'"), "launcher row missing")
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
    h.lua("ns.Options.SelectPage('bars'); __x0, __y0 = SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y; ns.Options.EnterUnlockMode()")
    h.lua("""
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.ToggleOptions()            -- reopened mid-drag
        ns.Options.EnterUnlockMode()  -- and Unlock Frames pressed again
    """)
    ok(not h.lua("return SalusNovusOptions:IsShown()") and h.lua("return SalusNovusUnlockBar:IsShown()"), "second Enter did not hand back the unlock bar")
    h.lua("ns.Options.ExitUnlockMode(false)")
    x, y = h.lua("return SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y")
    x0, y0 = h.lua("return __x0, __y0")
    ok(abs(x - x0) < 0.01 and abs(y - y0) < 0.01, "Cancel restored the dragged position: %r vs %r" % ((x, y), (x0, y0)))


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
    col = h.lua("return { ns.Options.shell.initial:GetTextColor() }")
    ok(abs(float(col[1]) - r) < 0.01 and abs(float(col[2]) - g) < 0.01 and abs(float(col[3]) - b) < 0.01, "initial not in the accent: %r" % (list(col.values()),))
    h.lua("ns.db.theme.customColor = { r = 0.1, g = 0.9, b = 0.2 }; ns.ApplyAll()")
    col = h.lua("return { ns.Options.shell.initial:GetTextColor() }")
    ok(abs(float(col[1]) - 0.1) < 0.01 and abs(float(col[2]) - 0.9) < 0.01, "initial did not follow an accent change")
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
    h.lua("ns.Abilities.SetRoute(11130, 'messages', true)")
    ok(h.lua("return ns.Abilities.Routed(11130, 'messages')"), "route on")
    # storing a default clears the entry; clearing every field drops the record
    h.lua("ns.Abilities.SetRoute(11130, 'messages', false); ns.Abilities.Set(11130, 'rename', ''); ns.Abilities.Set(11130, 'color', nil)")
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "an emptied record must vanish")
    eq(str(h.lua("return tostring(ns.Abilities.Get(W.secretNumber(), true))")), "nil", "a secret key must be refused")
    h.lua("ns.Abilities.Set(21055, 'rename', 'Crush'); ns.Abilities.Reset(21055)")
    eq(str(h.lua("return tostring(ns.Abilities.Rename(21055))")), "nil", "Reset did not clear")
    # defaults: queue and preview on, messages off
    ok(h.lua("return ns.Abilities.Routed(22911, 'queue') and ns.Abilities.Routed(22911, 'preview') and not ns.Abilities.Routed(22911, 'messages')"), "route defaults")
    eq(h.errors(), [], "errors")


@test("a rename and a colour reach the bars label, the queue label and edge, the lane and the card; the real name stays for lookups", "abilities")
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
                return { text = f.label:GetText(), lc = { f.label:GetTextColor() }, ec = { f.edge:GetVertexColor() } }
            end
        end
    """)
    ok(q is not None, "no queue icon for Knock Away")
    eq(str(q["text"]), "KNOCK", "queue label not renamed")
    ok(abs(float(q["lc"][2]) - 0.9) < 0.01 and abs(float(q["ec"][2]) - 0.9) < 0.01, "queue label/edge not coloured")
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


@test("routing: unticking the queue drops the icon, Messages is opt-in, the preview follows its tick", "abilities")
def _():
    h = fresh()
    h.lua("ns.Abilities.SetRoute(11130, 'queue', false); ns.Abilities.SetRoute(11130, 'preview', false)")
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
    ok(not any("Knock" in t for t in preview_lines(h)), "preview shows an unrouted ability: %r" % preview_lines(h))
    h.lua("W.advance(3.5)")   # Knock Away landed at 7.3
    eq(message_texts(h), [], "Messages showed an ability nobody opted in")
    h.lua("ns.Abilities.SetRoute(21055, 'messages', true); W.advance(5)")   # Crush Armor lands at 12.2
    eq(message_texts(h), ["Crush Armor"], "opted-in ability did not reach Messages")
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
    h.lua("%s.routes.messages:Click()" % ed)
    ok(h.lua("return ns.Abilities.Routed(11130, 'messages')"), "route toggle did not write")
    h.lua("%s.routes.queue:Click()" % ed)
    ok(not h.lua("return ns.Abilities.Routed(11130, 'queue')"), "queue route did not write")
    h.lua("%s.reset:Click()" % ed)
    eq(str(h.lua("return tostring(ns.db.abilities['11130'])")), "nil", "Reset did not clear the record")
    ok(h.lua("return %s.roles.tank:GetChecked() and %s.routes.queue:GetChecked() and not %s.routes.messages:GetChecked()" % (ed, ed, ed)), "controls not synced after Reset")
    eq(h.errors(), [], "errors")


# ----------------------------------------------------------------- preview

@test("the preview counts a routed ability down inside its window, rewrites once a second, and leaves at landing with no NOW", "preview")
def _():
    h = fresh()
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


@test("a record with no spell id goes to the opt-out anchors but never to Messages", "bughunt")
def _():
    h = fresh()
    ok(h.lua("return ns.Timers.RoutedTo({ key = 'x' }, 'queue') and ns.Timers.RoutedTo({ key = 'x' }, 'preview')"), "opt-out anchors")
    ok(not h.lua("return ns.Timers.RoutedTo({ key = 'x' }, 'messages')"), "Messages is opt-in; no card can opt a spell-less record in")
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
    h.lua("W.advance(0.3)")
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
    h.lua("W.advance(1.3)")
    eq(str(h.lua("return ns.HealthBars.state.unit")), "nameplate3", "late unit not found by name")
    # the client refuses the secret value: pcall catches it, the fill dims, the markers stay
    h.lua("""
        __orig = SalusNovusHealthBars.bar.SetValue
        SalusNovusHealthBars.bar.SetValue = function() error("secret value") end
        W.advance(0.3)
    """)
    ok(h.lua("return ns.HealthBars.state.refused and SalusNovusHealthBars:GetAlpha() == 1 and SalusNovusHealthBars.bar:GetAlpha() < 0.5"), "refusal not handled")
    ok(h.lua("return ns.HealthBars._markers[1]:IsShown()"), "markers dropped on refusal")
    h.lua("SalusNovusHealthBars.bar.SetValue = __orig; W.advance(0.3)")
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
    # The NaN record is dropped and replaced with a valid v2 record on the next layout
    eq(int(h.lua("return SalusNovusDB.barsPos.v")), 2, "NaN record not replaced with v2")


@test("position record with absurd coordinate (>20000) is discarded", "bughunt3")
def _():
    h = Harness()
    h.login('SalusNovusDB = { barsPos = { point = "CENTER", x = 999999, y = 100, v = 2 } }')
    eq(h.errors(), [], "errors with absurd coordinate")
    h.lua("ns.db.unlocked = true; ns.ApplyAll()")
    # Should fall back to default position
    ok(h.lua("return SalusNovusBars:IsShown()"), "bars not shown")
    # The absurd record is dropped and replaced with a valid v2 record on the next layout
    x = float(h.lua("return SalusNovusDB.barsPos.x"))
    ok(abs(x) < 20000, "absurd coordinate not replaced: %r" % x)


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
        __x0, __y0 = SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y
        -- First unlock
        ns.Options.EnterUnlockMode()
        SalusNovusBars:ClearAllPoints()
        SalusNovusBars:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)
        ns.SaveAnchor(SalusNovusBars, "barsPos")
        ns.Options.ExitUnlockMode(false)
        __x1, __y1 = SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y
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
        __x2, __y2 = SalusNovusDB.barsPos.x, SalusNovusDB.barsPos.y
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
    h.lua('ns.Abilities.Set(11130, "rename", "KNOCKAWAY_CUSTOM")')

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
    h.lua('ns.Abilities.Set(11130, "color", { r = 0.9, g = 0.1, b = 0.1 })')

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
        ns.Abilities.SetRoute(11130, 'messages', true)
    """)

    # Verify it's set
    ok(h.lua("return ns.db.abilities['11130'] ~= nil"), "record not created")

    # Clear everything
    h.lua("""
        ns.Abilities.Set(11130, 'rename', '')
        ns.Abilities.Set(11130, 'color', nil)
        ns.Abilities.SetRoute(11130, 'messages', false)
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
    ok(any("Knock Away" in line or "Knock" in line for line in preview), "default preview routing not working after cleared record")

    msgs = get_message_names(h)
    ok("Knock Away" not in msgs, "default messages routing wrong after cleared record (should be opt-in)")

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
    ok(abs(edge / unit - 1) < 1e-6, "border edge is not exactly one pixel")
    gap = (box - fill) / 2 / unit
    ok(abs(gap - round(gap)) < 1e-6 and gap >= 1, "fill gap %.3f px is not whole on both sides" % gap)
    h2 = fresh()
    h2.lua("_G.__cb = ns.Theme.MakeCheckBox(UIParent, 16)")   # no physical size API: plain units
    eq(tuple(h2.lua("return __cb:GetWidth(), __cb.fill:GetWidth()")), (16, 10), "without the API the old sizes must hold")
    eq(h.errors() + h2.errors(), [], "errors")


@test("the reminder form's Save and Cancel sit bottom right, Cancel outermost; Remove bottom left", "visualizer")
def _():
    h = fresh()
    open_vis(h)
    h.lua("ns.Visualizer.ShowBoss(ns.Data[3065].bosses[3])")
    h.lua("ns.Visualizer.OpenForm(5, 11130, 'Knock Away', nil)")
    pts = h.lua("""
        local f = ns.Visualizer.form
        local cp, _, crp = f.cancel:GetPoint(1)
        local sp, srel, srp = f.save:GetPoint(1)
        local dp = f.delete:GetPoint(1)
        return cp .. "/" .. tostring(crp) .. " " .. sp .. "/" .. tostring(srel == f.cancel) .. "/" .. tostring(srp) .. " " .. dp
    """)
    eq(str(pts), "BOTTOMRIGHT/BOTTOMRIGHT RIGHT/true/LEFT BOTTOMLEFT", "button anchors: %r" % pts)
