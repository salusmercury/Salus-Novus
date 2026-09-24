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
                    if self.IsEnabled and not self:IsEnabled() then return end     -- the client ignores clicks on a disabled button
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
                -- Justification is recorded: "the title is centred" is a real check.
                local function EnableKeyboard(self, on) rawset(self, "__keyboard", on and true or false) end
                local function IsKeyboardEnabled(self) return rawget(self, "__keyboard") or false end
                local function SetPropagateKeyboardInput(self, on) rawset(self, "__propagate", on and true or false) end
                local function GetPropagateKeyboardInput(self) return rawget(self, "__propagate") or false end
                local function SetRotation(self, r) rawset(self, "__rotation", r) end
                local function GetRotation(self) return rawget(self, "__rotation") or 0 end
                local function SetAtlas(self, a) rawset(self, "__atlas", a) end
                local function SetJustifyH(self, j) rawset(self, "__justifyH", j) end
                local function GetJustifyH(self) return rawget(self, "__justifyH") or "LEFT" end
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
                    if k == "EnableKeyboard" then return EnableKeyboard end
                    if k == "IsKeyboardEnabled" then return IsKeyboardEnabled end
                    if k == "SetPropagateKeyboardInput" then return SetPropagateKeyboardInput end
                    if k == "GetPropagateKeyboardInput" then return GetPropagateKeyboardInput end
                    if k == "SetRotation" then return SetRotation end
                    if k == "GetRotation" then return GetRotation end
                    if k == "SetAtlas" then return SetAtlas end
                    if k == "SetJustifyH" then return SetJustifyH end
                    if k == "GetJustifyH" then return GetJustifyH end
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
            UnitRace = UnitRace or function() return "Dwarf", "Dwarf" end
            UnitFactionGroup = UnitFactionGroup or function() return "Alliance", "Alliance" end
            GetZoneText = GetZoneText or function() return __zone or "Dun Morogh" end
            GetBindLocation = GetBindLocation or function() return __bind or "Kharanos" end
            -- Objectives for the recorder's diff: __objectives[questID] = { { text=, finished= }, ... }
            __objectives = {}
            -- A class trainer for Trainer.lua: __trainer rows
            -- { name=, rank=, cat=, level=, cost=, skill=, icon=, req={...} } (cat "header" rows skipped);
            -- __trainerFilter holds the three filter flags; __tradeskillTrainer flips the kind.
            __trainer, __trainerFilter, __tradeskillTrainer = {}, { available = true, unavailable = false, used = false }, false
            GetNumTrainerServices = function() return #__trainer end
            -- __trainerShape = "forever" (name, category, expanded: no rank) or "classic" (name, rank, category)
            __trainerShape = "forever"
            GetTrainerServiceInfo = function(i)
                local r = __trainer[i] if not r then return nil end
                if __trainerShape == "classic" then return r.name, r.rank or "", r.cat or "available", false end
                -- measured on Forever: name, category, icon, level, rank (nil when rankless)
                local rank = r.rank
                if rank == "" then rank = nil end
                return r.name, r.cat or "available", r.icon or 0, r.level or 0, rank
            end
            GetTrainerServiceLevelReq = function(i) local r = __trainer[i] return r and r.level end
            GetTrainerServiceCost = function(i) local r = __trainer[i] return r and r.cost end
            GetTrainerServiceSkillLine = function(i) local r = __trainer[i] return r and r.skill end
            GetTrainerServiceIcon = function(i) local r = __trainer[i] return r and r.icon end
            GetTrainerServiceItemLink = function(i) local r = __trainer[i] return r and r.link end
            -- GameTooltip records what a hover put in it: __tooltip = { owner=, spell=, lines={}, shown= }
            __tooltip = { lines = {} }
            GameTooltip.SetOwner = function(self, owner, anchor) __tooltip = { owner = owner, anchor = anchor, lines = {} } end
            GameTooltip.GetOwner = function(self) return __tooltip.owner end
            GameTooltip.SetSpellByID = function(self, id) __tooltip.spell = id end
            GameTooltip.AddLine = function(self, text) __tooltip.lines[#__tooltip.lines + 1] = tostring(text) end
            GameTooltip.Show = function(self) __tooltip.shown = true end
            GameTooltip.Hide = function(self) __tooltip.shown = false __tooltip.owner = nil end
            GetTrainerServiceNumAbilityReq = function(i) local r = __trainer[i] return r and r.req and #r.req or 0 end
            GetTrainerServiceAbilityReq = function(i, j) local r = __trainer[i] return r and r.req and r.req[j], false end
            GetTrainerServiceTypeFilter = function(f) return __trainerFilter[f] end
            SetTrainerServiceTypeFilter = function(f, v)
                __trainerFilter[f] = v and true or false
                __trainerUpdates = (__trainerUpdates or 0) + 1
                if __trainerOpen then W.fireEvent("TRAINER_UPDATE") end          -- the client fires this on a filter change
            end
            IsTradeskillTrainer = function() return __tradeskillTrainer end
            -- A retail-shaped spellbook frame for the tab: W.spellbookFrame() makes
            -- PlayerSpellsFrame.SpellBookFrame with CategoryTabSystem (three tab
            -- buttons) and PagedSpellsFrame, and fires the on-demand ADDON_LOADED.
            -- W.spellbookFrame("reload") mimics a /reload: the frame exists
            -- but is hidden and its tab buttons only appear on the first show,
            -- as a tab pool does.
            W.spellbookFrame = function(mode)
                local psf = CreateFrame("Frame", "PlayerSpellsFrame", UIParent)
                psf:SetSize(700, 520); psf:SetPoint("CENTER")
                local sbf = CreateFrame("Frame", nil, psf); sbf:SetAllPoints(); psf.SpellBookFrame = sbf
                local tabs = CreateFrame("Frame", nil, sbf); tabs:SetSize(200, 40); tabs:SetPoint("TOPLEFT", 20, -10); sbf.CategoryTabSystem = tabs
                tabs.buttons = {}
                local function makeTabs()
                    for i = 1, 3 do
                        local b = CreateFrame("Button", nil, tabs); b:SetSize(40, 40)
                        b:SetPoint("LEFT", tabs, "LEFT", (i - 1) * 46, 0)
                        -- the selected-tab pieces, as measured on Forever; tab 1 starts selected
                        b.SquareBackgroundActive = b:CreateTexture(nil, "ARTWORK")
                        b.SquareBackgroundActiveGlow = b:CreateTexture(nil, "ARTWORK")
                        b.SquareBackgroundActive:SetShown(i == 1)
                        b.SquareBackgroundActiveGlow:SetShown(i == 1)
                        b:SetEnabled(i ~= 1)                       -- the tab system disables the selected tab
                        tabs.selected = tabs.selected or 1
                        b.index = i
                        b:SetScript("OnClick", function(self)
                            if tabs.selected == self.index then return end     -- re-selecting the selected tab is a no-op
                            tabs.selected = self.index
                            for _, o in ipairs(tabs.buttons) do
                                o.SquareBackgroundActive:SetShown(o == self)
                                o.SquareBackgroundActiveGlow:SetShown(o == self)
                                o:SetEnabled(o ~= self)
                            end
                        end)
                        tabs.buttons[i] = b
                    end
                end
                if mode == "reload" then
                    psf:Hide()
                    psf:SetScript("OnShow", function() if not tabs.buttons[1] then makeTabs() end end)
                elseif mode == "lazy" then
                    -- one tab at first, one more on every later show (a level 1 warrior gained
                    -- its second category after the first show and our tab sat on top of it)
                    psf:Hide()
                    psf:SetScript("OnShow", function()
                        local i = #tabs.buttons + 1
                        if i > 3 then return end
                        local b = CreateFrame("Button", nil, tabs); b:SetSize(40, 40)
                        b:SetPoint("LEFT", tabs, "LEFT", (i - 1) * 46, 0)
                        b.SquareBackgroundActive = b:CreateTexture(nil, "ARTWORK")
                        b.SquareBackgroundActiveGlow = b:CreateTexture(nil, "ARTWORK")
                        b.SquareBackgroundActive:SetShown(i == 1)
                        b.SquareBackgroundActiveGlow:SetShown(i == 1)
                        tabs.buttons[i] = b
                    end)
                else
                    makeTabs()
                end
                local page = CreateFrame("Frame", nil, sbf); page:SetPoint("TOPLEFT", 20, -60); page:SetPoint("BOTTOMRIGHT", -20, 20); sbf.PagedSpellsFrame = page
                W.fireEvent("ADDON_LOADED", "Blizzard_PlayerSpells")
                return psf
            end
            -- A spellbook: __spellbook = { { name=, sub= "Rank 2" }, ... } in one skill line.
            __spellbook = {}
            Enum = Enum or {}
            Enum.SpellBookSpellBank = Enum.SpellBookSpellBank or { Player = 0, Pet = 1 }
            C_SpellBook = C_SpellBook or {}
            C_SpellBook.GetNumSpellBookSkillLines = function() return 1 end
            C_SpellBook.GetSpellBookSkillLineInfo = function(i) return { name = "General", itemIndexOffset = 0, numSpellBookItems = #__spellbook } end
            C_SpellBook.GetSpellBookItemName = function(slot, bank) local s = __spellbook[slot] if not s then return nil end return s.name, (__bookNoSubtext and "" or (s.sub or "")) end
            C_SpellBook.GetSpellBookItemInfo = function(slot, bank) local s = __spellbook[slot] if not s then return nil end return { spellID = s.id or (100000 + slot), name = s.name } end
            C_Spell = C_Spell or {}
            C_Spell.GetSpellSubtext = function(id) for _, s in ipairs(__spellbook) do if (s.id or 0) == id then return s.sub or "" end end return nil end
            -- A quest log for the Quests page: __quests rows
            -- { questID=, title=, level=, isHeader=, isHidden=, task=, trivial=, canAbandon= }.
            -- The client's three-call abandon is modelled strictly: AbandonQuest
            -- without SetAbandonQuest on the selected quest throws, and an
            -- abandoned quest LEAVES the list (indices shift, as in the client).
            __quests, __abandoned = {}, {}
            local qSelected, qArmed
            local function qFind(id) for i, q in ipairs(__quests) do if q.questID == id then return q, i end end end
            C_QuestLog = C_QuestLog or {}
            C_QuestLog.GetNumQuestLogEntries = function() return #__quests end
            C_QuestLog.GetInfo = function(i)
                local q = __quests[i]
                if not q then return nil end
                if q.throws then error("GetInfo blew up") end
                return { questID = q.questID, title = q.title, level = q.level, isHeader = q.isHeader or false, isHidden = q.isHidden or false }
            end
            C_QuestLog.GetQuestObjectives = function(id)
                local out = {}
                for i, ob in ipairs(__objectives[id] or {}) do out[i] = { text = ob.text, finished = ob.finished == true, type = "monster" } end
                return out
            end
            -- Guide: __completed[questID] = true for flagged-complete quests; a
            -- __quests row may carry ready = true (all objectives done) and title.
            __completed = {}
            C_QuestLog.IsQuestFlaggedCompleted = function(id) return __completed[id] == true end
            C_QuestLog.IsOnQuest = function(id) return qFind(id) ~= nil end
            C_QuestLog.ReadyForTurnIn = function(id) local q = qFind(id) return q ~= nil and q.ready == true end
            C_QuestLog.GetTitleForQuestID = function(id) local q = qFind(id) return (q and q.title) or (__titles and __titles[id]) or nil end
            C_QuestLog.RequestLoadQuestByID = function() end
            C_QuestLog.IsQuestTrivial = function(id) local q = qFind(id) return q ~= nil and q.trivial == true end
            C_QuestLog.IsQuestTask = function(id) local q = qFind(id) return q ~= nil and q.task == true end
            C_QuestLog.CanAbandonQuest = function(id) local q = qFind(id) return q ~= nil and q.canAbandon ~= false end
            C_QuestLog.SetSelectedQuest = function(id) qSelected = id end
            C_QuestLog.GetSelectedQuest = function() return qSelected end
            C_QuestLog.SetAbandonQuest = function() qArmed = qSelected end
            C_QuestLog.AbandonQuest = function()
                if qArmed == nil or qArmed ~= qSelected then error("AbandonQuest without SetAbandonQuest on the selected quest") end
                local q, i = qFind(qSelected)
                if q then table.remove(__quests, i); __abandoned[#__abandoned + 1] = qSelected end
                qArmed = nil
                W.fireEvent("QUEST_LOG_UPDATE")
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
    wanted = set(selected.split(",")) if selected else None      # "a,b,c" runs several groups
    for group, name, fn in TESTS:
        if wanted and group not in wanted:
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
