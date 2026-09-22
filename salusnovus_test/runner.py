"""Load Salus Novus into the mock WoW client and run its test suite.

    python salusnovus_test/runner.py           # everything
    python salusnovus_test/runner.py -v        # each passing test too

Reuses merkui_test/wow_mock.lua -- the same real-Lua-5.1 mock client, with
both secret-value models -- and loads salusnovus/ from the TOC's own order.
Frames here are recorders, not widgets: this proves the code RUNS and the
logic is right, not that anything looks right.
"""
import io
import os
import sys
import traceback
from lupa import lua51

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ADDON = os.environ.get("MERCURY_PATH", os.path.join(ROOT, "salusnovus"))
MOCK = os.path.join(ROOT, "merkui_test", "wow_mock.lua")


def toc_files():
    order = []
    with io.open(os.path.join(ADDON, "SalusNovus.toc"), encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if line and not line.startswith("#") and line.lower().endswith(".lua"):
                order.append(line.replace("\\", os.sep))
    return order


class Harness:
    def __init__(self):
        self.L = lua51.LuaRuntime(unpack_returned_tuples=True)
        self.g = self.L.globals()
        self.load_errors = []
        LIVE.append(self)
        src = io.open(MOCK, encoding="utf-8").read()
        self.L.eval("function(src) return assert(loadstring(src, '@wow_mock.lua')) end")(src)()
        self.g.SalusNovusDB = None
        # Client pieces Salus Novus uses that the MerkUI mock does not define.
        self.L.execute("""
            UISpecialFrames = UISpecialFrames or {}
            -- ns.Print goes through the chat frame; route it to the mock's
            -- print so h.printed() sees it.
            DEFAULT_CHAT_FRAME = DEFAULT_CHAT_FRAME or { AddMessage = function(_, msg) print(msg) end }
            -- The mock answers unknown capitalised methods with a noop that
            -- returns the frame (truthy), so IsMouseEnabled would read as
            -- "enabled" forever. Record the flag for real.
            do
                local probe = CreateFrame("Frame")
                local mt = getmetatable(probe)
                local idx = mt.__index
                local function EnableMouse(self, on) rawset(self, "__mouse", on and true or false) end
                local function IsMouseEnabled(self) return rawget(self, "__mouse") or false end
                -- Button:Click() runs the OnClick handler (hooks included);
                -- the blanket noop made every pressed button a silent no-op.
                local function Click(self, button)
                    local h = self.__scripts and self.__scripts.OnClick
                    if h then h(self, button or "LeftButton") end
                end
                -- Desaturation is recorded so a test can read it back.
                local function SetDesaturated(self, on) rawset(self, "__desaturated", on and true or false) end
                local function IsDesaturated(self) return rawget(self, "__desaturated") or false end
                -- Textures are recorded so "the row has an icon" can be
                -- checked for real (the noop returned the frame: always truthy).
                local function SetTexture(self, tex) rawset(self, "__texture", tex) end
                local function GetTexture(self) return rawget(self, "__texture") end
                -- Vertex colours too: accent repaints are checked by reading them.
                local function SetVertexColor(self, r, g, b, a) rawset(self, "__vc", { r, g, b, a == nil and 1 or a }) end
                local function GetVertexColor(self)
                    local c = rawget(self, "__vc") or { 1, 1, 1, 1 }
                    return c[1], c[2], c[3], c[4]
                end
                local function SetTextColor(self, r, g, b, a) rawset(self, "__tc", { r, g, b, a == nil and 1 or a }) end
                local function GetTextColor(self)
                    local c = rawget(self, "__tc") or { 1, 1, 1, 1 }
                    return c[1], c[2], c[3], c[4]
                end
                mt.__index = function(t, k)
                    if k == "EnableMouse" then return EnableMouse end
                    if k == "IsMouseEnabled" then return IsMouseEnabled end
                    if k == "Click" then return Click end
                    if k == "SetDesaturated" then return SetDesaturated end
                    if k == "IsDesaturated" then return IsDesaturated end
                    if k == "SetTexture" then return SetTexture end
                    if k == "GetTexture" then return GetTexture end
                    if k == "SetVertexColor" then return SetVertexColor end
                    if k == "GetVertexColor" then return GetVertexColor end
                    if k == "SetTextColor" then return SetTextColor end
                    if k == "GetTextColor" then return GetTextColor end
                    return idx(t, k)
                end
            end
            SOUNDKIT = SOUNDKIT or { RAID_WARNING = 8959 }
            -- Hostility of a unit: set __hostile[unit] = false to make one friendly.
            __hostile = {}
            -- Units for the health bar: __units[unit] = { name=, hp=, max= }.
            __units = {}
            do
                local origName, origExists, origHP, origMax = UnitName, UnitExists, UnitHealth, UnitHealthMax
                UnitName = function(u) local r = __units[u] if r then return r.name end return origName(u) end
                UnitExists = function(u) if __units[u] then return true end return origExists(u) end
                UnitHealth = function(u) local r = __units[u] if r then return r.hp end return origHP(u) end
                UnitHealthMax = function(u) local r = __units[u] if r then return r.max end return origMax(u) end
            end
            UnitCanAttack = UnitCanAttack or function(_, unit)
                if __hostile[unit] == nil then return true end
                return __hostile[unit]
            end
            PlaySound = PlaySound or function() end
            GetCursorPosition = GetCursorPosition or function() return 0, 0 end
            C_Spell = C_Spell or {}
            C_Spell.GetSpellName = C_Spell.GetSpellName or function(id) return __spellNames and __spellNames[id] or nil end
            C_Spell.GetSpellTexture = C_Spell.GetSpellTexture or function(id) return 136 end
            C_Spell.GetSpellDescription = C_Spell.GetSpellDescription or function(id) return __spellDesc and __spellDesc[id] or "" end
            C_Spell.IsSpellDataCached = C_Spell.IsSpellDataCached or function(id) return true end
            C_Spell.RequestLoadSpellData = C_Spell.RequestLoadSpellData or function() end
            -- Chat filters are recorded (the shared mock's version is a
            -- no-op) so a test can push a line through them:
            -- W.chat(event, msg, author) returns true when a filter ate it.
            __chatFilters = {}
            ChatFrame_AddMessageEventFilter = function(event, fn)
                __chatFilters[event] = __chatFilters[event] or {}
                table.insert(__chatFilters[event], fn)
            end
            ChatFrame_RemoveMessageEventFilter = function(event, fn)
                local list = __chatFilters[event] or {}
                for i = #list, 1, -1 do if list[i] == fn then table.remove(list, i) end end
            end
            W.chat = function(event, msg, author)
                for _, fn in ipairs(__chatFilters[event] or {}) do
                    local block, m, a = fn(DEFAULT_CHAT_FRAME, event, msg, author)
                    if block then return true end
                    msg, author = m, a
                end
                return false, msg, author
            end
        """)
        self.ns = self.L.eval("{}")
        loader = self.L.eval("""
            function(src, name, addonName, ns)
                local chunk, err = loadstring(src, '@' .. name)
                if not chunk then return false, 'SYNTAX: ' .. tostring(err) end
                local ok, rerr = pcall(chunk, addonName, ns)
                if not ok then return false, tostring(rerr) end
                return true, nil
            end
        """)
        for fname in toc_files():
            path = os.path.join(ADDON, fname)
            if not os.path.exists(path):
                self.load_errors.append((fname, "FILE MISSING"))
                continue
            ok, err = loader(io.open(path, encoding="utf-8", errors="replace").read(), fname, "SalusNovus", self.ns)
            if not ok:
                self.load_errors.append((fname, err))

    def lua(self, src):
        fn = self.L.eval("function(src, ns) local f = assert(loadstring('local ns = ... ' .. src, '@test')) return f(ns) end")
        return fn(src, self.ns)

    def login(self, saved_lua=None):
        if saved_lua:
            self.lua(saved_lua)
        self.lua('W.fireEvent("ADDON_LOADED", "SalusNovus")')
        self.lua('W.fireEvent("PLAYER_LOGIN")')
        self.lua('W.fireEvent("PLAYER_ENTERING_WORLD")')
        return self

    def errors(self):
        n = int(self.lua("return #W.errors") or 0)
        return [str(self.lua("return W.errors[%d]" % i)) for i in range(1, n + 1)]

    def printed(self):
        n = int(self.lua("return #W.printed") or 0)
        return [str(self.lua("return W.printed[%d]" % i)) for i in range(1, n + 1)]


LIVE = []
ALLOW_ERRORS = set()
TESTS = []


def allow_errors(fn):
    ALLOW_ERRORS.add(fn)
    return fn


def test(name, group="general"):
    def deco(fn):
        TESTS.append((group, name, fn))
        return fn
    return deco


class Fail(AssertionError):
    pass


def ok(cond, msg):
    if not cond:
        raise Fail(msg)


def eq(got, want, msg):
    if got != want:
        raise Fail("%s\n      got:  %r\n      want: %r" % (msg, got, want))


def run(selected=None, verbose=False):
    groups = {}
    for group, name, fn in TESTS:
        if selected and group != selected:
            continue
        groups.setdefault(group, []).append((name, fn))
    passed = failed = 0
    for group in sorted(groups):
        print("\n%s\n%s" % (group, "-" * len(group)))
        for name, fn in groups[group]:
            try:
                del LIVE[:]
                fn()
                if fn not in ALLOW_ERRORS:
                    leaked = []
                    for h in LIVE:
                        try:
                            leaked += h.errors()
                        except Exception:
                            pass
                    if leaked:
                        raise Fail("the addon threw inside a handler and the test never looked:\n      "
                                   + "\n      ".join(leaked[:6]))
                passed += 1
                if verbose:
                    print("  PASS  %s" % name)
            except Fail as e:
                failed += 1
                print("  FAIL  %s\n        %s" % (name, str(e).replace("\n", "\n        ")))
            except Exception:
                failed += 1
                print("  ERROR %s\n        %s" % (name, traceback.format_exc(limit=3).replace("\n", "\n        ").strip()))
    print("\n%s\npassed %d   failed %d" % ("=" * 60, passed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.path.insert(0, HERE)
    # tests.py does `from runner import ...`; without this it would import a
    # SECOND copy of this module with its own empty TESTS list and the suite
    # would report "passed 0 failed 0" -- which it did, once.
    sys.modules["runner"] = sys.modules[__name__]
    import tests  # noqa: F401  (registers TESTS)
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    sys.exit(run(args[0] if args else None, "-v" in sys.argv))
