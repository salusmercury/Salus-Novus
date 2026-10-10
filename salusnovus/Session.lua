--[[ Salus Novus -- the Session bar (Quality of Life).

One movable databar with three segments (Alex, 2026-10-03):
  XP     -- XP per hour since the last reset, and time to the next level
  Gold   -- net gold per hour since the last reset
  Lockouts -- dungeon entries in the last hour against the limit, and
              when the next slot frees up
Click a segment for its breakdown; Ctrl-click XP or Gold to reset it.

Rates count logged-in time only, so a session survives logouts and reloads
until it is reset. XP is filed as kills (the combat XP message, which also
names the rested bonus), quests (the turn-in) or other (exploration...);
gold by what was open when the money moved (merchant, trainer, mailbox,
auction house, flight master, trade) or what just happened (loot, a quest
turn-in, a repair).

Lockouts are account-wide (SalusNovusDB.instances): an entry is a NEW
instance when that dungeon wasn't entered in the last hour, or it was
reset since ("has been reset."). Forever's limit is not documented: 5 by
default (Classic Era), learned from the "too many instances" error.
]]

local _, ns = ...

local S = {}
ns.Session = S

local Num, Str = ns.Num, ns.Str
local HOUR = 3600
local KILL_WINDOW, QUEST_WINDOW, MONEY_WINDOW = 1.0, 2.0, 2.0

local function O() return ns.db and ns.db.session end
local function Enabled()
    local o = O()
    return o and o.enabled ~= false and ns.ModuleOn("qol") and true or false
end
S.Enabled = Enabled

local function Now() return (GetTime and GetTime()) or 0 end
local function Epoch() return (time and time()) or 0 end

local function CharKey()
    local ok, name, realm = pcall(UnitFullName or UnitName, "player")
    name = ok and Str(name) or nil
    if not name then return nil end
    realm = ok and Str(realm) or nil
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

-- ------------------------------------------------------------ saved state

local function NewXP() return { secs = 0, total = 0, kill = 0, quest = 0, other = 0, rested = 0 } end
local function NewGold() return { secs = 0, inc = {}, out = {} } end

--- This character's session record (created on first use).
function S.State()
    if type(SalusNovusDB) ~= "table" then return nil end
    local key = CharKey()
    if not key then return nil end
    if type(SalusNovusDB.session) ~= "table" then SalusNovusDB.session = {} end
    local s = SalusNovusDB.session[key]
    if type(s) ~= "table" then s = {}; SalusNovusDB.session[key] = s end
    if type(s.xp) ~= "table" then s.xp = NewXP() end
    if type(s.gold) ~= "table" then s.gold = NewGold() end
    if type(s.zones) ~= "table" then s.zones = {} end
    return s
end

function S.ResetXP()
    local s = S.State()
    if s then s.xp = NewXP(); s.zones = {} end      -- (the zone breakdown resets with it: the sweep)
    if S.OnChanged then S.OnChanged() end
end

function S.ResetGold()
    local s = S.State()
    if s then s.gold = NewGold() end
    if S.OnChanged then S.OnChanged() end
end

--- Logged-in time accrues while the game runs (called by the ticker).
function S.Tick(dt)
    local s = S.State()
    if not s or not Num(dt) or dt <= 0 or dt > 60 then return end
    s.xp.secs = (s.xp.secs or 0) + dt
    s.gold.secs = (s.gold.secs or 0) + dt
end

-- ------------------------------------------------------------ XP

local lastXP, lastMax
local lastKill, lastKillRested, lastQuest = -100, 0, -100

local function ReadXP()
    local okX, xp = pcall(UnitXP, "player")
    local okM, max = pcall(UnitXPMax, "player")
    if okX and okM and Num(xp) and Num(max) then return xp, max end
    return nil
end

local function MaxLevel()
    local fn = rawget(_G, "GetMaxLevelForPlayerExpansion") or rawget(_G, "GetMaxPlayerLevel")
    local ok, n = false, nil
    if fn then ok, n = pcall(fn) end
    return ok and Num(n) and n or 60
end

local function Level()
    local ok, l = pcall(UnitLevel, "player")
    return ok and Num(l) and l or 1
end

function S.AtMaxLevel() return Level() >= MaxLevel() end

local function ZoneName()
    local fn = rawget(_G, "GetRealZoneText") or rawget(_G, "GetZoneText")
    local ok, z = false, nil
    if fn then ok, z = pcall(fn) end
    return ok and Str(z) or nil
end

--- The combat XP message: "X dies, you gain N experience. (+M exp Rested bonus)".
function S.OnCombatXP(msg)
    if ns.IsSecret(msg) or type(msg) ~= "string" then lastKill, lastKillRested = Now(), 0 return end
    lastKill = Now()
    lastKillRested = tonumber(msg:match("%+(%d+)[^%d]*[Rr]ested")) or 0
end

function S.OnQuestTurnedIn() lastQuest = Now() end

function S.OnXPUpdate()
    local xp, max = ReadXP()
    if not xp then return end
    if not lastXP then lastXP, lastMax = xp, max return end
    local gain
    -- A level up is the bar's size changing, not the XP going down: a big
    -- turn-in can leave more over than you had (100/400 + 700 -> 400/900).
    if max == lastMax and xp >= lastXP then gain = xp - lastXP
    else gain = ((lastMax or 0) - lastXP) + xp end         -- a level up in between
    lastXP, lastMax = xp, max
    if gain <= 0 or not Enabled() then return end
    local s = S.State()
    if not s then return end
    local x = s.xp
    x.total = (x.total or 0) + gain
    local now = Now()
    if now - lastKill <= KILL_WINDOW then
        x.kill = (x.kill or 0) + gain
        x.rested = (x.rested or 0) + math.min(lastKillRested or 0, gain)
        lastKill = -100
    elseif now - lastQuest <= QUEST_WINDOW then
        x.quest = (x.quest or 0) + gain
        lastQuest = -100
    else
        x.other = (x.other or 0) + gain
    end
    local zone = ZoneName()
    if zone then s.zones[zone] = (s.zones[zone] or 0) + gain end
    if S.OnChanged then S.OnChanged() end
end

--- XP per hour since the reset (nil before a minute has passed).
function S.XPRate()
    local s = S.State()
    local x = s and s.xp
    if not x or (x.secs or 0) < 60 then return nil end
    return (x.total or 0) / x.secs * HOUR
end

--- Seconds to the next level at that rate.
function S.TimeToLevel()
    local rate = S.XPRate()
    local xp, max = ReadXP()
    if not rate or rate <= 0 or not xp then return nil end
    return (max - xp) / rate * HOUR
end

function S.Rested()
    local fn = rawget(_G, "GetXPExhaustion")
    local ok, r = false, nil
    if fn then ok, r = pcall(fn) end
    return ok and Num(r) and r or 0
end

-- ------------------------------------------------------------ gold

local open = {}                 -- which money window is open
local closedAt = {}             -- when the flight map / trade closed (the money lands after it)
local lastMoney
local lastLoot, lastQuestMoney, lastRepair = -100, -100, -100

S.CATEGORY_ORDER = { "loot", "quest", "vendor", "repair", "training", "mail", "auction", "travel", "trade", "other" }
S.CATEGORY_LABEL = { loot = "Loot", quest = "Quests", vendor = "Vendor", repair = "Repairs", training = "Training",
    mail = "Mail", auction = "Auction house", travel = "Flights", trade = "Trade", other = "Other" }

function S.SetOpen(key, on) open[key] = on and true or nil end

local function Category(delta)
    local now = Now()
    if delta < 0 and now - lastRepair <= MONEY_WINDOW then return "repair" end
    -- a single item repaired with the repair cursor (only Repair All was hooked: the sweep)
    if delta < 0 then
        local irm = rawget(_G, "InRepairMode")
        local okR, rm = pcall(irm or function() return false end)
        if okR and rm == true then return "repair" end
    end
    if delta > 0 and now - lastLoot <= MONEY_WINDOW then return "loot" end
    if delta > 0 and now - lastQuestMoney <= MONEY_WINDOW then return "quest" end
    if open.trade or now - (closedAt.trade or -100) <= MONEY_WINDOW then return "trade" end
    if open.auction then return "auction" end
    if open.mail then return "mail" end
    if open.trainer then return "training" end
    if open.taxi or now - (closedAt.taxi or -100) <= MONEY_WINDOW then return "travel" end
    if open.merchant then return "vendor" end
    return "other"
end

local function ReadMoney()
    local ok, m = pcall(GetMoney)
    return ok and Num(m) and m or nil
end

function S.OnMoney()
    local m = ReadMoney()
    if not m then return end
    if not lastMoney then lastMoney = m return end
    local delta = m - lastMoney
    lastMoney = m
    if delta == 0 or not Enabled() then return end
    local s = S.State()
    if not s then return end
    local cat = Category(delta)
    local bucket = delta > 0 and s.gold.inc or s.gold.out
    bucket[cat] = (bucket[cat] or 0) + math.abs(delta)
    if cat == "repair" then lastRepair = -100 end
    if cat == "travel" then closedAt.taxi = nil elseif cat == "trade" then closedAt.trade = nil end
    if S.OnChanged then S.OnChanged() end
end

function S.OnLootMoney() lastLoot = Now() end
function S.OnQuestMoney() lastQuestMoney = Now() end
function S.OnRepair() lastRepair = Now() end

local function Sum(t) local n = 0 for _, v in pairs(t or {}) do n = n + (tonumber(v) or 0) end return n end

--- Net copper per hour since the reset (nil before a minute has passed).
function S.GoldRate()
    local s = S.State()
    local g = s and s.gold
    if not g or (g.secs or 0) < 60 then return nil end
    return (Sum(g.inc) - Sum(g.out)) / g.secs * HOUR
end

function S.GoldTotals()
    local s = S.State()
    local g = s and s.gold or NewGold()
    return Sum(g.inc), Sum(g.out), g
end

-- ------------------------------------------------------------ lockouts

local function Log()
    if type(SalusNovusDB) ~= "table" then return nil end
    local l = SalusNovusDB.instances
    if type(l) ~= "table" then l = {}; SalusNovusDB.instances = l end
    if type(l.entries) ~= "table" then l.entries = {} end
    if type(l.reset) ~= "table" then l.reset = {} end
    return l
end
S.Log = Log

--- A limit set by hand replaces a learned one (a first error counted only
-- the entries the bar saw, and could cap the account low for good with
-- the setting greyed out: the sweep).
function S.SetLimit(v)
    local o = O()
    if o then o.limit = v end
    local l = Log()
    if l then l.learned = nil end
    if S.OnChanged then S.OnChanged() end
end

--- Instances per hour: the learned limit, else the setting, else 5.
function S.Limit()
    local l = Log()
    if l and Num(l.learned) and l.learned > 0 then return l.learned, true end
    local o = O()
    local n = o and tonumber(o.limit)
    return (n and n > 0) and n or 5, false
end

--- Entries in the last hour (oldest first), pruning older ones.
function S.Recent()
    local l = Log()
    if not l then return {} end
    local now, keep, out = Epoch(), {}, {}
    for _, e in ipairs(l.entries) do
        if type(e) == "table" and Num(e.t) and now - e.t < 24 * HOUR then
            keep[#keep + 1] = e
            if now - e.t < HOUR then out[#out + 1] = e end
        end
    end
    l.entries = keep
    table.sort(out, function(a, b) return a.t < b.t end)
    return out
end

--- Seconds until the oldest entry of the last hour drops off.
function S.NextSlot()
    local r = S.Recent()
    if #r == 0 then return nil end
    return math.max(0, r[1].t + HOUR - Epoch())
end

local function InstanceNow()
    local okI, inInst, kind = pcall(IsInInstance)
    if not okI or ns.IsSecret(inInst) or not inInst then return nil end
    if kind ~= "party" and kind ~= "raid" then return nil end
    local ok, name, _, _, _, _, _, _, mapID = pcall(GetInstanceInfo)
    if not ok then return nil end
    -- The wing: Scarlet Monastery's four share map 189, but each is its own
    -- instance (sweep 6), one floor each, so the floor's uiMapID tells them
    -- apart. Elsewhere a floor is just a floor (a summon can land you deep).
    if mapID ~= 189 then return Num(mapID) and mapID or nil, Str(name), kind end
    local okW, wing = pcall(C_Map and C_Map.GetBestMapForUnit, "player")
    return mapID, Str(name), kind, okW and Num(wing) and wing or nil
end

--- On entering the world: a dungeon not entered in the last hour, or reset
-- since, counts as a new instance. Another wing of the same map is another
-- instance; a login or /reload can stand on any floor, so it matches by map.
function S.OnEnterWorld(isLogin, isReload)
    if not Enabled() then return end
    local map, name, kind, wing = InstanceNow()
    if isLogin or isReload then wing = nil end
    if not map then return end
    local l = Log()
    if not l then return end
    local who = CharKey()
    if not who then return end            -- no name yet: never file an entry under a stand-in
    local now = Epoch()
    local seen = false
    for _, e in ipairs(l.entries) do
        if type(e) == "table" and e.map == map and not e.pre and (e.wing == nil or wing == nil or e.wing == wing) and e.char == who and Num(e.t) and now - e.t < HOUR then seen = true end
    end
    -- The reset flag is this character's: another character's reset says
    -- nothing about the instance this one is walking back into.
    local rk = who .. ":" .. map
    if seen and not l.reset[rk] then return end
    -- a reset makes every earlier entry of this map stale, not just the
    -- wing walked into first: the other Scarlet Monastery wings are new too
    -- (they still count toward the hour)
    if l.reset[rk] then
        for _, e in ipairs(l.entries) do
            if type(e) == "table" and e.map == map and e.char == who then e.pre = true end
        end
    end
    l.reset[rk] = nil
    l.entries[#l.entries + 1] = { t = now, map = map, wing = wing, name = name, char = who, raid = kind == "raid" or nil }
    if S.OnChanged then S.OnChanged() end
end

--- Left or joined a group: the next entry into a dungeon of the last hour
-- is another instance (no 'has been reset' line comes: sweep 2). The one
-- you stand in now keeps its ID -- unless you left the group: its instance
-- stays with the group, and a solo re-entry is a new one.
function S.OnGroupChange(left)
    local l = Log()
    local who = CharKey()
    if not (l and who) then return end
    local here = InstanceNow()
    local now = Epoch()
    for _, e in ipairs(l.entries) do
        if type(e) == "table" and e.char == who and Num(e.map) and (left or e.map ~= here) and Num(e.t) and now - e.t < HOUR then
            l.reset[who .. ":" .. e.map] = true
        end
    end
    -- re-invited inside before the port-out: you stay in that instance
    if not left and here then l.reset[who .. ":" .. here] = nil end
end

local function Pattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    return "^" .. p:gsub("%%%%s", "(.+)") .. "$"
end

--- System messages: "X has been reset." marks X as new on the next entry;
-- "too many instances" teaches the limit.
function S.OnSystem(msg)
    if ns.IsSecret(msg) or type(msg) ~= "string" then return end
    local l = Log()
    if not l then return end
    local resetPat = Pattern(rawget(_G, "INSTANCE_RESET_SUCCESS") or "%s has been reset.")
    local name = resetPat and msg:match(resetPat)
    if name then
        local who = CharKey()
        for _, e in ipairs(l.entries) do
            if type(e) == "table" and e.name == name and Num(e.map) and who and e.char == who then
                l.reset[who .. ":" .. e.map] = true
            end
        end
        return
    end
    local tooMany = Str(rawget(_G, "TRANSFER_ABORT_TOO_MANY_INSTANCES")) or "You have entered too many instances recently."
    if msg == tooMany or msg:find("too many instances", 1, true) then
        local n = #S.Recent()
        if n > 0 then
            -- Only ever raised: entries made while the bar was off aren't
            -- logged, so a low count would cap every character for good.
            l.learned = math.max(Num(l.learned) and l.learned or 0, n)
            ns.Print(("the instance limit here looks like %d per hour."):format(n))
            if S.OnChanged then S.OnChanged() end
        end
    end
end

--- Raid saves from the client: { {name, seconds left, difficulty} }.
function S.RaidSaves()
    local out = {}
    local okN, n = pcall(GetNumSavedInstances)
    if not okN or not Num(n) then return out end
    for i = 1, n do
        local ok, name, _, reset, _, locked, _, _, isRaid, _, diffName = pcall(GetSavedInstanceInfo, i)
        if ok and Str(name) and locked and Num(reset) and reset > 0 then
            out[#out + 1] = { name = name, left = reset, raid = isRaid and true or false, diff = Str(diffName) }
        end
    end
    return out
end

-- ------------------------------------------------------------ text

local function Short(n)
    if n >= 1e6 then return ("%.1fm"):format(n / 1e6) end
    if n >= 1e4 then return ("%.0fk"):format(n / 1e3) end
    if n >= 1e3 then return ("%.1fk"):format(n / 1e3) end
    return ("%d"):format(n)
end
S.Short = Short

function S.Duration(secs)
    if not Num(secs) then return "--" end
    secs = math.floor(secs + 0.5)
    if secs >= 86400 * 2 then return ("%dd"):format(math.floor(secs / 86400)) end
    local h, m = math.floor(secs / 3600), math.floor((secs % 3600) / 60)
    if h > 0 then return ("%dh %dm"):format(h, m) end
    if m > 0 then return ("%dm"):format(m) end
    return ("%ds"):format(secs)
end

--- Copper as "2g 41s" ("41s 12c" under a gold, "-" for a loss).
function S.Money(c)
    if not Num(c) then return "--" end
    local neg = c < 0
    c = math.floor(math.abs(c) + 0.5)
    local g, s, cp = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local out
    if g > 0 then out = ("%dg %ds"):format(g, s)
    elseif s > 0 then out = ("%ds %dc"):format(s, cp)
    else out = ("%dc"):format(cp) end
    return (neg and "-" or "") .. out
end

function S.XPText()
    if S.AtMaxLevel() then return "Max level" end
    local rate = S.XPRate()
    if not rate then return "XP --/h" end
    local ttl = S.TimeToLevel()
    return ("%s xp/h  \194\183  %s"):format(Short(rate), ttl and S.Duration(ttl) or "--")
end

--- Copper as gold with up to two decimals: 2200 -> "0.22", 15000 -> "1.5".
function S.Gold(c)
    if not Num(c) then return "--" end
    local t = ("%.2f"):format(c / 10000):gsub("0+$", ""):gsub("%.$", "")
    if t == "-0" then t = "0" end
    return t
end

function S.GoldText()
    local rate = S.GoldRate()
    if not rate then return "-- gold/h" end
    return S.Gold(rate) .. " gold/h"
end

function S.InstancesText()
    local n, limit = #S.Recent(), S.Limit()
    local nxt = S.NextSlot()
    if n == 0 then return ("Instances 0/%d"):format(limit) end
    return ("Instances %d/%d  \194\183  %s"):format(n, limit, S.Duration(nxt))
end

-- ------------------------------------------------------------ events

ns.On("PLAYER_XP_UPDATE", function() S.OnXPUpdate() end)
ns.On("CHAT_MSG_COMBAT_XP_GAIN", function(msg) S.OnCombatXP(msg) end)
ns.On("QUEST_TURNED_IN", function(_, _, money)
    S.OnQuestTurnedIn()
    if Num(money) and money > 0 then S.OnQuestMoney() end
end)
ns.On("PLAYER_MONEY", function() S.OnMoney() end)
ns.On("CHAT_MSG_MONEY", function() S.OnLootMoney() end)
ns.On("LOOT_OPENED", function() S.OnLootMoney() end)
for ev, key in pairs({ MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer", MAIL_SHOW = "mail",
                       AUCTION_HOUSE_SHOW = "auction", TAXIMAP_OPENED = "taxi", TRADE_SHOW = "trade" }) do
    ns.On(ev, function() S.SetOpen(key, true) end)
end
for ev, key in pairs({ MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "trainer", MAIL_CLOSED = "mail",
                       AUCTION_HOUSE_CLOSED = "auction" }) do
    ns.On(ev, function() S.SetOpen(key, false) end)
end
-- the flight fee and trade gold arrive after the window closes
for ev, key in pairs({ TAXIMAP_CLOSED = "taxi", TRADE_CLOSED = "trade" }) do
    ns.On(ev, function() closedAt[key] = Now(); S.SetOpen(key, false) end)
end
ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    lastXP, lastMax = ReadXP()
    lastMoney = ReadMoney()
    S.OnEnterWorld(isLogin, isReload)
end)
ns.On("CHAT_MSG_SYSTEM", function(msg) S.OnSystem(msg) end)
ns.On("GROUP_LEFT", function() S.OnGroupChange(true) end)
ns.On("GROUP_JOINED", function() S.OnGroupChange() end)
ns.On("UI_ERROR_MESSAGE", function(_, msg) S.OnSystem(msg) end)

-- Logged-in time, whether or not the bar is shown (a hidden bar must not
-- skew the rate when it comes back).
S.ticker = CreateFrame("Frame")
local tickAcc = 0
S.ticker:SetScript("OnUpdate", function(_, dt)
    tickAcc = tickAcc + (dt or 0)
    if tickAcc < 1 then return end
    if Enabled() then S.Tick(tickAcc) end
    tickAcc = 0
end)

-- A repair spends money at a merchant; say which (hooked when it exists).
table.insert(ns.OnLoad, function()
    -- the guild bank paying (RepairAllItems(true)) spends nothing of yours: not a repair to file
    if rawget(_G, "RepairAllItems") then hooksecurefunc("RepairAllItems", function(guild) if guild ~= true then S.OnRepair() end end) end
end)
