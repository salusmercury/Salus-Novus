--[[ Salus Novus -- Trainer: what your class trainer would teach you, without the trip.

Quality of Life > Trainer (Alex, 2026-09-22). One visit to a class trainer
captures the trainer's whole catalogue -- the client lists every rank,
including the ones you cannot learn yet, once the "unavailable" and
"used" filters are on -- with name, rank, cost, level requirement,
prerequisite abilities, skill line and icon. The capture goes into
SalusNovusDB.trainers[class]; harvest_routes.py / build_route.py carry it
into Data/Trainers.lua (ns.Trainers[class]) so every character of that
class has it, on this account where saved variables never come back and
on any other.

The catalogue is matched against the spellbook by name and rank: an entry
is KNOWN when the book holds that name at that rank or a higher one,
LEARNABLE when unknown, the level is met and every prerequisite is known,
and LOCKED otherwise (shown with the level it opens at). Costs are as the
trainer quoted them at capture time (a reputation discount is baked in).
]]

local _, ns = ...

local T = {}
ns.Trainer = T

local Num, Str = ns.Num, ns.Str

local function O() return ns.db and ns.db.trainer end
local function Enabled()
    local o = O()
    return o and o.enabled ~= false and ns.ModuleOn("qol") and true or false
end
T.Enabled = Enabled

local function ClassTag()
    local ok, _, tag = pcall(UnitClass, "player")
    return ok and Str(tag) or nil
end
T.ClassTag = ClassTag

-- ------------------------------------------------------------ rank text

--- "Rank 3" -> 3; "" / nil -> nil. Tolerates "Rank  3" and lower case.
function T.RankNumber(text)
    if type(text) ~= "string" then return nil end
    local n = text:match("^%s*[Rr]ank%s+(%d+)%s*$")
    return n and tonumber(n) or nil
end

-- ------------------------------------------------------------ capture

local FILTERS = { "available", "unavailable", "used" }

--- Read the open trainer window. Returns the capture (or nil, reason).
function T.ReadTrainer()
    if type(GetNumTrainerServices) ~= "function" or type(GetTrainerServiceInfo) ~= "function" then return nil, "no trainer API" end
    if type(IsTradeskillTrainer) == "function" then
        local ok, trade = pcall(IsTradeskillTrainer)
        if ok and trade then return nil, "tradeskill trainer" end
    end
    -- Every row, whatever the window's filter says; put the filter back after.
    local before = {}
    if type(GetTrainerServiceTypeFilter) == "function" and type(SetTrainerServiceTypeFilter) == "function" then
        for _, f in ipairs(FILTERS) do
            local ok, v = pcall(GetTrainerServiceTypeFilter, f)
            if ok then
                before[f] = v and true or false                 -- a false must be put back too
                pcall(SetTrainerServiceTypeFilter, f, true)     -- only what can be put back is touched
            end
        end
    end
    local okN, n = pcall(GetNumTrainerServices)
    local entries = {}
    if okN and Num(n) then
        for i = 1, n do
            local res = { pcall(GetTrainerServiceInfo, i) }
            local ok, name = res[1], Str(res[2])
            -- Forever returns (name, category, icon, level, "Rank n") -- the
            -- rank is the FIFTH value and nil for a rankless spell (measured
            -- 2026-09-23 with /sn probe trainer). Older clients: (name, rank,
            -- category). Scan every return for what it is.
            local rank, category = "", ""
            for k = 3, #res do
                local v = res[k]
                if type(v) == "string" and not ns.IsSecret(v) then
                    if v == "available" or v == "unavailable" or v == "used" or v == "header" then category = v
                    elseif rank == "" and v:match("^%s*[Rr]ank%s+%d+%s*$") then rank = v end
                end
            end
            if name and category ~= "header" then
                local e = { name = name, rank = rank, cat = category }
                local okL, lvl = pcall(GetTrainerServiceLevelReq, i)
                if okL and Num(lvl) then e.level = lvl end
                local okC, cost = pcall(GetTrainerServiceCost, i)
                if okC and Num(cost) then e.cost = cost end
                if type(GetTrainerServiceSkillLine) == "function" then
                    local okS, skill = pcall(GetTrainerServiceSkillLine, i)
                    if okS and Str(skill) then e.skill = skill end
                end
                if type(GetTrainerServiceIcon) == "function" then
                    local okI, icon = pcall(GetTrainerServiceIcon, i)
                    if okI and (Num(icon) or Str(icon)) then e.icon = icon end
                end
                -- the service link carries the spell id ("|Hspell:133|h..."): the tooltip needs it
                if type(GetTrainerServiceItemLink) == "function" then
                    local okK, link = pcall(GetTrainerServiceItemLink, i)
                    local id = okK and Str(link) and tonumber(link:match("spell:(%d+)")) or nil
                    if id then e.spell = id end
                end
                if type(GetTrainerServiceNumAbilityReq) == "function" and type(GetTrainerServiceAbilityReq) == "function" then
                    local okR, nreq = pcall(GetTrainerServiceNumAbilityReq, i)
                    if okR and Num(nreq) and nreq > 0 then
                        e.req = {}
                        for j = 1, nreq do
                            local okA, aname = pcall(GetTrainerServiceAbilityReq, i, j)
                            if okA and Str(aname) then e.req[#e.req + 1] = aname end
                        end
                        if #e.req == 0 then e.req = nil end
                    end
                end
                entries[#entries + 1] = e
            end
        end
    end
    for f, v in pairs(before) do pcall(SetTrainerServiceTypeFilter, f, v) end
    if #entries == 0 then return nil, "empty list" end
    return { class = ClassTag(), captured = time(), entries = entries }
end

--- Fill in "Rank n" for entries the client listed without rank text.
-- Each later rank names the one before as its prerequisite ("Frostbolt
-- (Rank 2)" on the rank-3 row), so that is read first; rows of one name
-- without such a prerequisite are ordered by level then cost and numbered
-- from 1. A name with a single row stays rankless. Idempotent; safe on
-- shipped data too.
function T.DeriveRanks(cap)
    if not cap or type(cap.entries) ~= "table" then return cap end
    local byName = {}
    for _, e in ipairs(cap.entries) do
        -- a capture from before 2026-09-23 put the category where the rank goes
        if e.rank == "available" or e.rank == "unavailable" or e.rank == "used" then
            if not e.cat or e.cat == "" then e.cat = e.rank end
            e.rank = ""
        end
        if type(e.name) == "string" and (e.rank == nil or e.rank == "") then
            byName[e.name] = byName[e.name] or {}
            table.insert(byName[e.name], e)
        end
    end
    for name, list in pairs(byName) do
        if #list > 1 then
            local rest = {}
            for _, e in ipairs(list) do
                local got
                for _, req in ipairs(e.req or {}) do
                    local rname, rk = req:match("^(.-)%s*%(Rank%s+(%d+)%)%s*$")
                    if rname == name and rk then got = tonumber(rk) + 1 end
                end
                if got then e.rank = "Rank " .. got else rest[#rest + 1] = e end
            end
            table.sort(rest, function(x, y)
                local lx, ly = x.level or 0, y.level or 0
                if lx ~= ly then return lx < ly end
                return (x.cost or 0) < (y.cost or 0)
            end)
            for i, e in ipairs(rest) do e.rank = "Rank " .. i end
        end
    end
    cap.ranksDerived = true
    return cap
end

--- Store a capture for the character's class (in memory + SavedVariables).
-- `say` prints the one-line confirmation (the event path says it once per
-- visit; /sn trainer capture always does).
--- A capture made at the trainer has no spell ids when the client gives no
-- service link; the shipped catalogue (ids resolved at build time from
-- the spell tables) lends them by name and rank.
function T.BorrowIds(cap)
    if not cap or type(cap.entries) ~= "table" then return cap end
    local shipped = ns.Trainers and cap.class and ns.Trainers[cap.class]
    if type(shipped) ~= "table" or type(shipped.entries) ~= "table" then return cap end
    local byKey = {}
    for _, e in ipairs(shipped.entries) do
        if e.spell then byKey[tostring(e.name) .. "|" .. tostring(e.rank or "")] = e.spell end
    end
    for _, e in ipairs(cap.entries) do
        if not e.spell then e.spell = byKey[tostring(e.name) .. "|" .. tostring(e.rank or "")] end
    end
    return cap
end

function T.Capture(say)
    if say == nil then say = true end
    local cap, why = T.ReadTrainer()
    if not cap or not cap.class then return nil, why or "no class" end
    T.DeriveRanks(cap)
    T.BorrowIds(cap)
    if type(SalusNovusDB) == "table" then
        SalusNovusDB.trainers = SalusNovusDB.trainers or {}
        SalusNovusDB.trainers[cap.class] = cap
    end
    T.live = T.live or {}
    T.live[cap.class] = cap
    if say and ns.Print then ns.Print(("trainer: captured %d entries for %s"):format(#cap.entries, cap.class)) end
    if T.Refresh then T.Refresh() end
    return cap
end

--- The catalogue for a class: this session's capture wins over the shipped file.
function T.Catalogue(class)
    class = class or ClassTag()
    if not class then return nil end
    local live = T.live and T.live[class]
    if live then return live end
    local saved = type(SalusNovusDB) == "table" and SalusNovusDB.trainers and SalusNovusDB.trainers[class]
    if type(saved) == "table" and type(saved.entries) == "table" then return T.DeriveRanks(saved) end
    local shipped = ns.Trainers and ns.Trainers[class]
    if type(shipped) == "table" and type(shipped.entries) == "table" then return T.DeriveRanks(shipped) end
    return nil
end

-- ------------------------------------------------------------ spellbook

--- { [name] = highest rank number known (0 for a rankless spell) }.
function T.KnownSpells()
    local known = {}
    local sb = rawget(_G, "C_SpellBook")
    if not (sb and sb.GetNumSpellBookSkillLines and sb.GetSpellBookSkillLineInfo and sb.GetSpellBookItemName) then return known end
    local bank = (rawget(_G, "Enum") and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local okN, lines = pcall(sb.GetNumSpellBookSkillLines)
    if not okN or not Num(lines) then return known end
    for i = 1, lines do
        local okI, info = pcall(sb.GetSpellBookSkillLineInfo, i)
        if okI and type(info) == "table" and Num(info.itemIndexOffset) and Num(info.numSpellBookItems) then
            for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                local okS, name, sub = pcall(sb.GetSpellBookItemName, slot, bank)
                name = okS and Str(name) or nil
                if name then
                    local r = T.RankNumber(sub)
                    if not r and sb.GetSpellBookItemInfo then
                        -- the book may give no subtext: ask the spell itself
                        local okI, item = pcall(sb.GetSpellBookItemInfo, slot, bank)
                        local id = okI and type(item) == "table" and item.spellID
                        local cs = rawget(_G, "C_Spell")
                        if Num(id) and cs and cs.GetSpellSubtext then
                            local okT, t = pcall(cs.GetSpellSubtext, id)
                            r = okT and T.RankNumber(Str(t)) or nil
                        end
                    end
                    r = r or 0
                    if not known[name] or known[name] < r then known[name] = r end
                end
            end
        end
    end
    return known
end

-- ------------------------------------------------------------ status

local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    return ok and Num(l) and l or 0
end

--- Is a trainer entry known, by the spellbook map?
local function IsKnown(e, known)
    local have = known[e.name]
    if have == nil then return false end
    local r = T.RankNumber(e.rank)
    if not r then return true end
    return have >= r
end

--- A prerequisite string "Flame Shock (Rank 2)" or "Flame Shock" -> known?
local function ReqMet(req, known)
    local name, rank = req:match("^(.-)%s*%((Rank%s+%d+)%)%s*$")
    name = name or req
    local have = known[name]
    if have == nil then return false end
    local r = rank and T.RankNumber(rank)
    return not r or have >= r
end

--- The catalogue sorted into { now = {...}, later = {...}, known = {...} },
-- each entry decorated with .state, .missing (unmet prerequisites).
function T.Status(class)
    local cat = T.Catalogue(class)
    if not cat then return nil end
    local known = T.KnownSpells()
    local level = PlayerLevel()
    local out = { now = {}, later = {}, known = {}, cost = 0, class = cat.class, captured = cat.captured }
    for _, e in ipairs(cat.entries) do
        local d = {}
        for k, v in pairs(e) do d[k] = v end
        if IsKnown(e, known) then
            d.state = "known"
            out.known[#out.known + 1] = d
        else
            d.missing = {}
            for _, req in ipairs(e.req or {}) do
                if not ReqMet(req, known) then d.missing[#d.missing + 1] = req end
            end
            local levelOk = not Num(e.level) or level >= e.level
            if levelOk and #d.missing == 0 then
                d.state = "now"
                out.now[#out.now + 1] = d
                out.cost = out.cost + (Num(e.cost) and e.cost or 0)
            else
                d.state = "later"
                out.later[#out.later + 1] = d
            end
        end
    end
    local function byLevel(a, b)
        local la, lb = a.level or 0, b.level or 0
        if la ~= lb then return la < lb end
        if a.name ~= b.name then return a.name < b.name end
        return (T.RankNumber(a.rank) or 0) < (T.RankNumber(b.rank) or 0)
    end
    table.sort(out.now, byLevel); table.sort(out.later, byLevel); table.sort(out.known, byLevel)
    return out
end

--- Copper -> "1g 71s 5c" (zero parts dropped; "0c" for nothing).
function T.Money(copper)
    if not Num(copper) or copper <= 0 then return "0c" end
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "g" end
    if s > 0 then parts[#parts + 1] = s .. "s" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "c" end
    return table.concat(parts, " ")
end

-- ------------------------------------------------------------ events

-- All nine class catalogues ship in Data/Trainers.lua (2026-09-23), so a
-- trainer visit no longer captures anything. The capture itself stays as
-- a probe: /sn probe trainer capture reads the open trainer into
-- SavedVariables for harvest_routes.py / build_route.py to refresh the
-- shipped data. Own frame, quiet registration: only the events that
-- change what the spellbook tab should show.
local own = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LEVEL_UP", "LEARNED_SPELL_IN_TAB", "SPELLS_CHANGED" }) do
    pcall(own.RegisterEvent, own, ev)
end
own:SetScript("OnEvent", function()
    if not Enabled() then return end
    if T.Refresh then T.Refresh() end
end)

ns.Commands = ns.Commands or {}
ns.Commands.trainer = function(rest)
    local arg = (rest or ""):match("^(%S*)"):lower()
    if arg == "attach" and ns.TrainerUI then ns.TrainerUI.TryAttach() end
    local st = T.Status()
    if not st then ns.Print("trainer: no catalogue for this class yet; visit a class trainer once")
    else ns.Print(("trainer: %d to learn now (%s), %d later, %d known"):format(#st.now, T.Money(st.cost), #st.later, #st.known)) end
    if ns.TrainerUI and ns.TrainerUI.Report then ns.Print(ns.TrainerUI.Report()) end
end
