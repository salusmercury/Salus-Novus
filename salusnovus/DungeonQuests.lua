--[[ Salus Novus -- dungeon quest check (Quality of Life).

Entering a dungeon in a group, a small card lists (Alex, 2026-10-03):
  - each of your quests for this dungeon that a party member lacks, with
    who lacks it and a Share button (your click; the game's own share);
  - quests a party member has for it that you lack (they need Salus Novus
    to say so: party lists go over addon messages, prefix SNDQ).
Nothing to act on, no card. It updates as quests are accepted or shared
and closes with its X until the next dungeon.

A dungeon's quests are the ones filed under its name in the quest log
(the log heads dungeon quests with the dungeon), matched loosely:
"The Deadmines" = "Deadmines".
]]

local _, ns = ...

local D = {}
ns.DungeonQuests = D

local Num, Str = ns.Num, ns.Str
local PREFIX = "SNDQ"

local function O() return ns.db and ns.db.quests end
local function Enabled()
    local o = O()
    return o and o.dungeonCheck ~= false and ns.ModuleOn("qol") and true or false
end
D.Enabled = Enabled

local function Key(s) return (tostring(s or ""):lower():gsub("^the ", ""):gsub("[^%a]", "")) end
D.Key = Key

local function QL() return rawget(_G, "C_QuestLog") end

-- ------------------------------------------------------------ where we are

--- The party dungeon we're in: name, or nil.
function D.Dungeon()
    local okI, inInst, kind = pcall(IsInInstance)
    if not okI or ns.IsSecret(inInst) or not inInst or kind ~= "party" then return nil end
    local ok, name = pcall(GetInstanceInfo)
    return ok and Str(name) or nil
end

local function InGroup()
    local fn = rawget(_G, "IsInGroup")
    local ok, g = false, false
    if fn then ok, g = pcall(fn) end
    return ok and g and not ns.IsSecret(g) and true or false
end

--- Party members: { {unit, name, class} }.
function D.Party()
    local out = {}
    for i = 1, 4 do
        local unit = "party" .. i
        local okE, exists = pcall(UnitExists, unit)
        if okE and exists and not ns.IsSecret(exists) then
            local okN, name = pcall(UnitName, unit)
            local okC, _, class = pcall(UnitClass, unit)
            name = okN and Str(name) or nil
            if name then out[#out + 1] = { unit = unit, name = name, class = okC and Str(class) or nil } end
        end
    end
    return out
end

-- ------------------------------------------------------------ quests

--- Your quests for a dungeon: { {questID, title} }.
function D.Mine(dungeon)
    local out, want = {}, Key(dungeon)
    if want == "" or not (ns.Quests and ns.Quests.List) then return out end
    for _, q in ipairs(ns.Quests.List()) do
        if Key(q.zone) == want then out[#out + 1] = { questID = q.questID, title = Str(q.title) or ("Quest " .. q.questID) } end
    end
    return out
end

--- Does `unit` have the quest? true / false / nil (the client can't say).
function D.UnitHas(unit, questID)
    local ql = QL()
    local fn = ql and ql.IsUnitOnQuest
    if not fn then return nil end
    local ok, on = pcall(fn, unit, questID)
    if not ok or ns.IsSecret(on) then return nil end
    return on and true or false
end

function D.Pushable(questID)
    local ql = QL()
    local fn = ql and ql.IsPushableQuest
    if not fn then return true end
    local ok, p = pcall(fn, questID)
    return not ok or (p and true or false)
end

--- Share a quest with the party (from a click).
function D.Share(questID)
    local ql = QL()
    if ql and ql.SetSelectedQuest then pcall(ql.SetSelectedQuest, questID) end
    local push = rawget(_G, "QuestLogPushQuest")
    if push then pcall(push) end
end

-- What party members said they have: [name] = { key = dungeonKey, quests = { {questID, title} } }.
D.party = {}

--- A quest you've already turned in (so a share can't land).
function D.Completed(questID)
    local f = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted
    if not f then return false end
    local ok, done = pcall(f, questID)
    return ok and not ns.IsSecret(done) and done == true
end

--- Everything to act on in this dungeon:
-- give = { {questID, title, missing = {names}} }, get = { {questID, title, from = {names}} }.
function D.Check(dungeon)
    local give, get = {}, {}
    if not dungeon then return give, get end
    local mine = D.Mine(dungeon)
    local have = {}
    local party = D.Party()
    for _, q in ipairs(mine) do
        have[q.questID] = true
        local missing = {}
        for _, m in ipairs(party) do
            if D.UnitHas(m.unit, q.questID) == false then missing[#missing + 1] = m end
        end
        if #missing > 0 then give[#give + 1] = { questID = q.questID, title = q.title, missing = missing } end
    end
    local key, at = Key(dungeon), {}
    local present = {}
    for _, m in ipairs(party) do present[m.name] = m end
    for name, rec in pairs(D.party) do
        if present[name] and rec.key == key then
            for _, q in ipairs(rec.quests) do
                -- A quest you've done can't be shared to you. (Their list stays
                -- current because dropping a quest re-sends it; the client's
                -- IsUnitOnQuest may not answer for quests outside your log.)
                if not have[q.questID] and not D.Completed(q.questID) then
                    local e = at[q.questID]
                    if not e then e = { questID = q.questID, title = q.title, from = {} }; at[q.questID] = e; get[#get + 1] = e end
                    e.from[#e.from + 1] = present[name]
                end
            end
        end
    end
    table.sort(get, function(a, b) return a.title < b.title end)
    return give, get
end

-- ------------------------------------------------------------ comms

local prefixOK = false
local function RegisterPrefix()
    if prefixOK then return end
    local ci = rawget(_G, "C_ChatInfo")
    if not (ci and ci.RegisterAddonMessagePrefix) then return end
    local ok, r = pcall(ci.RegisterAddonMessagePrefix, PREFIX)
    prefixOK = ok and (r == true or r == 0 or r == 2)
end

local function Channel()
    if not InGroup() then return nil end
    local fn = rawget(_G, "IsInGroup")
    local inst = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
    if fn and inst then
        local ok, i = pcall(fn, inst)
        if ok and i and not ns.IsSecret(i) then return "INSTANCE_CHAT" end
    end
    return "PARTY"
end

local function Clean(s) return (tostring(s or ""):gsub("[|;:~]", "")) end

--- Tell the group our quests for this dungeon (one message, 240 bytes).
function D.Broadcast(dungeon)
    local ci = rawget(_G, "C_ChatInfo")
    local ch = Channel()
    if not (ci and ci.SendAddonMessage and ch and dungeon) then return end
    RegisterPrefix()
    local msg = "DQ|" .. Key(dungeon) .. "|"
    local first = true
    for _, q in ipairs(D.Mine(dungeon)) do
        local piece = q.questID .. ":" .. Clean(q.title)
        if #msg + #piece + 1 > 240 then break end
        msg = msg .. (first and "" or ";") .. piece
        first = false
    end
    pcall(ci.SendAddonMessage, PREFIX, msg, ch)
end

local function Short(name)
    local amb = rawget(_G, "Ambiguate")
    if amb then local ok, s = pcall(amb, name, "none") if ok and Str(s) then return s end end
    return name
end

function D.OnAddonMessage(prefix, msg, channel, sender)
    if ns.IsSecret(prefix) or prefix ~= PREFIX or ns.IsSecret(msg) or type(msg) ~= "string" then return end
    if ns.IsSecret(channel) or ns.IsSecret(sender) then return end
    if channel ~= "PARTY" and channel ~= "INSTANCE_CHAT" and channel ~= "RAID" then return end
    local who = Short(Str(sender) or "")
    local okN, me = pcall(UnitName, "player")
    if who == "" or (okN and who == me) then return end
    if ns.Wishlist and ns.Wishlist.InMyGroup and not ns.Wishlist.InMyGroup(who) then return end
    local key, body = msg:match("^DQ|([%a]*)|(.*)$")
    if not key then return end
    local quests = {}
    for id, title in body:gmatch("(%d+):([^;]*)") do
        local n = tonumber(id)
        if n and n > 0 and #quests < 40 then quests[#quests + 1] = { questID = n, title = title ~= "" and title or ("Quest " .. n) } end
    end
    D.party[who] = { key = key, quests = quests }
    if D.OnChanged then D.OnChanged() end
end

-- ------------------------------------------------------------ the card

local frame
D.dismissed = nil      -- the dungeon whose card was closed

local function SavePosition() ns.SaveAnchor(frame, "dungeonQuestsPos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "dungeonQuestsPos", "TOP", 0, -80, "TOP")
end
ns.DungeonQuestsRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "dungeonQuestsPos", restore = "DungeonQuestsRestorePosition" })

local W, PAD, ROW = 300, 10, 34

local function Names(list)
    local out = {}
    local cn = ns.WishlistUI and ns.WishlistUI.ClassName
    for _, m in ipairs(list) do out[#out + 1] = cn and cn(m.name, m.class) or m.name end
    return table.concat(out, ", ")
end

local function Build()
    if frame then return frame end
    local T = ns.Theme
    frame = CreateFrame("Frame", "SalusNovusDungeonQuests", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(W, 60)
    frame:Hide()
    frame.bg = T.SolidTex(frame, "BACKGROUND", T.BG[1], T.BG[2], T.BG[3], 0.92)
    frame.bg:SetAllPoints()
    frame.border = ns.CreateBorder(frame)
    frame.border:Layout(frame, 1, -1)
    frame.border:SetColor(1, 1, 1, 0.10)
    frame.border:Show()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    frame.unlockLabel:Hide()
    frame.title = T.MakeText(frame, 13, T.TEXT)
    frame.title:SetPoint("TOPLEFT", PAD, -8)
    frame.title:SetText(T.Upper("Dungeon quests"))
    frame.close = CreateFrame("Button", nil, frame)
    -- A big X in the corner (Alex): two crossed bars like the options
    -- window's close button, brighter on hover.
    frame.close:SetSize(24, 24)
    frame.close:SetPoint("TOPRIGHT", -3, -3)
    frame.close.bars = {}
    for i, angle in ipairs({ math.pi / 4, -math.pi / 4 }) do
        local bar = T.SolidTex(frame.close, "ARTWORK", T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1)
        bar:SetSize(18, 2)
        bar:SetPoint("CENTER")
        if bar.SetRotation then pcall(bar.SetRotation, bar, angle) end
        frame.close.bars[i] = bar
    end
    local function CloseColor(r, g, b) for _, bar in ipairs(frame.close.bars) do bar:SetVertexColor(r, g, b, 1) end end
    frame.close:SetScript("OnEnter", function() CloseColor(1, 1, 1) end)
    frame.close:SetScript("OnLeave", function() CloseColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3]) end)
    frame.close:SetScript("OnClick", function()
        D.dismissed = D.Dungeon()
        frame:Hide()
    end)
    frame.rows = {}
    ns.RegisterMovable(frame, "dungeonQuestsPos", function() return "TOP" end, RestorePosition)
    frame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)
    RestorePosition()
    return frame
end
D.Build = Build

local function Row(i)
    local r = frame.rows[i]
    if r then return r end
    local T = ns.Theme
    r = CreateFrame("Frame", nil, frame)
    r:SetHeight(ROW)
    r.title = T.MakeText(r, 13, T.TEXT)
    r.title:SetPoint("TOPLEFT", 0, -2)
    r.title:SetPoint("RIGHT", r, "RIGHT", -76, 0)
    r.title:SetJustifyH("LEFT")
    r.title:SetWordWrap(false)
    r.sub = T.MakeText(r, 11, T.TEXT_MUTE)
    r.sub:SetPoint("TOPLEFT", r.title, "BOTTOMLEFT", 0, -2)
    r.sub:SetPoint("RIGHT", r, "RIGHT", -76, 0)
    r.sub:SetJustifyH("LEFT")
    r.sub:SetWordWrap(false)
    r.share = T.MakeButton(r)
    r.share:SetSize(66, 22)
    r.share:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.share:SetText("Share")
    r.share:SetScript("OnClick", function(self) if self.questID then D.Share(self.questID) end end)
    frame.rows[i] = r
    return r
end

--- Redraw: the card shows only in a party dungeon with something to act on.
function D.Refresh()
    local unlocked = ns.db and ns.db.unlocked
    local dungeon = D.Dungeon()
    local give, get = {}, {}
    if Enabled() and dungeon and InGroup() and D.dismissed ~= dungeon then give, get = D.Check(dungeon) end
    if not unlocked and #give == 0 and #get == 0 then
        if frame then frame:Hide() end
        return
    end
    Build()
    frame.unlockLabel:SetShown(unlocked and true or false)
    local n, y = 0, 30
    for _, q in ipairs(give) do
        n = n + 1
        local r = Row(n)
        r.title:SetText(q.title)
        r.sub:SetText("Missing: " .. Names(q.missing))
        r.share.questID = q.questID
        r.share:SetShown(D.Pushable(q.questID))
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
        r:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        r:Show()
        y = y + ROW
    end
    for _, q in ipairs(get) do
        n = n + 1
        local r = Row(n)
        r.title:SetText(q.title)
        r.sub:SetText("You're missing it  \194\183  " .. Names(q.from) .. " can share")
        r.share.questID = nil
        r.share:Hide()
        r:ClearAllPoints()
        r:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -y)
        r:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
        r:Show()
        y = y + ROW
    end
    for i = n + 1, #frame.rows do frame.rows[i]:Hide() end
    frame:SetHeight(math.max(44, y + 6))
    frame:Show()
end

-- ------------------------------------------------------------ events

local queued = false
local function Queue()
    -- Only where a card can be: no timers spent outside dungeons.
    if queued or not (D.Dungeon() or (frame and frame:IsShown()) or (ns.db and ns.db.unlocked)) then return end
    queued = true
    local function Go() queued = false D.Refresh() end
    if C_Timer and C_Timer.After then C_Timer.After(0.5, Go) else Go() end
end
D.OnChanged = Queue

ns.On("PLAYER_ENTERING_WORLD", function()
    RegisterPrefix()
    local dungeon = D.Dungeon()
    if dungeon ~= D.dismissed then D.dismissed = nil end
    if dungeon and Enabled() then D.Broadcast(dungeon) end
    Queue()
end)
ns.On("GROUP_ROSTER_UPDATE", function()
    local dungeon = D.Dungeon()
    if dungeon and Enabled() then D.Broadcast(dungeon) end
    Queue()
end)
ns.On("QUEST_ACCEPTED", function()
    local dungeon = D.Dungeon()
    if dungeon and Enabled() then D.Broadcast(dungeon) end
    Queue()
end)
-- Dropping or turning in a quest changes what we can share: say so, or the
-- others keep "<name> can share" for a quest we no longer have.
ns.On("QUEST_REMOVED", function()
    local dungeon = D.Dungeon()
    if dungeon and Enabled() then D.Broadcast(dungeon) end
    Queue()
end)
ns.On("UNIT_QUEST_LOG_CHANGED", Queue)
ns.On("CHAT_MSG_ADDON", function(...) D.OnAddonMessage(...) end)
ns.RegisterApply(function() D.Refresh() end, "Dungeon quests")
