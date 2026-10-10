--[[ Salus Novus -- Quests: abandon every quest, or every low-level one.

Quality of Life > Quests (Alex, 2026-09-21). Two buttons, each behind a
confirmation: abandon all, abandon the low-level ones (the ones the client
calls trivial: grey in the log, C_QuestLog.IsQuestTrivial).

The abandon flow is the client's own three calls per quest --
SetSelectedQuest, SetAbandonQuest, AbandonQuest -- the same ones Alex's old
macro used. Two things the macro got away with that this does not: the
quest IDs are collected BEFORE anything is abandoned (each abandon shifts
the log indices under a live loop), and header rows are skipped (they have
no quest). A quest the client says cannot be abandoned is left alone.
]]

local _, ns = ...

local Q = {}
ns.Quests = Q

local function Enabled() return ns.ModuleOn("qol") and true or false end

local function QL() return rawget(_G, "C_QuestLog") end

--- Low-level = trivial to the client (grey). Falls back to the player's
-- trivial level range when IsQuestTrivial is missing or throws.
function Q.IsTrivial(questID, level)
    local ql = QL()
    if ql and ql.IsQuestTrivial then
        local ok, r = pcall(ql.IsQuestTrivial, questID)
        if ok and type(r) == "boolean" then return r end
    end
    if type(level) ~= "number" or ns.IsSecret(level) then return false end
    local okL, pl = pcall(UnitLevel, "player")
    if not okL or type(pl) ~= "number" or ns.IsSecret(pl) then return false end
    local range = 10
    if type(UnitQuestTrivialLevelRange) == "function" then
        local okR, r = pcall(UnitQuestTrivialLevelRange, "player")
        if okR and type(r) == "number" and not ns.IsSecret(r) then range = r end
    end
    return level <= pl - range
end

--- The quests in the log: { questID, title, level, trivial, zone }, headers,
-- hidden entries and world-quest tasks skipped (a quest's zone is the
-- header it sits under). A throwing GetInfo or a secret id skips that row
-- rather than the whole list.
function Q.List()
    local out = {}
    local ql = QL()
    if not ql or not ql.GetNumQuestLogEntries or not ql.GetInfo then return out end
    local okN, n = pcall(ql.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" or ns.IsSecret(n) then return out end
    local zone
    for i = 1, n do
        local ok, info = pcall(ql.GetInfo, i)
        if ok and type(info) == "table" and info.isHeader then zone = ns.Str(info.title) end
        if ok and type(info) == "table" and not info.isHeader and not info.isHidden then
            local id = info.questID
            if type(id) == "number" and not ns.IsSecret(id) and id > 0 then
                local task = false
                if ql.IsQuestTask then
                    local okT, t = pcall(ql.IsQuestTask, id)
                    task = okT and t == true
                end
                if not task then
                    out[#out + 1] = { questID = id, title = info.title, level = info.level, trivial = Q.IsTrivial(id, info.level), zone = zone or "Other" }
                end
            end
        end
    end
    return out
end

--- The log by zone, in log order: { { zone = name, quests = { ... } }, ... }.
function Q.Zones()
    local out, at = {}, {}
    for _, q in ipairs(Q.List()) do
        local name = q.zone or "Other"
        local z = at[name]
        if not z then z = { zone = name, quests = {} }; at[name] = z; out[#out + 1] = z end
        z.quests[#z.quests + 1] = q
    end
    return out
end

--- The quests of one zone.
function Q.InZone(zone)
    for _, z in ipairs(Q.Zones()) do if z.zone == zone then return z.quests end end
    return {}
end

--- The low-level subset.
function Q.LowLevel()
    local out = {}
    for _, q in ipairs(Q.List()) do
        if q.trivial then out[#out + 1] = q end
    end
    return out
end

local function CanAbandon(ql, id)
    if not ql.CanAbandonQuest then return true end
    local ok, r = pcall(ql.CanAbandonQuest, id)
    return not (ok and r == false)
end

--- Still in the log? A quest turned in since the list was taken must not
-- reach SetSelectedQuest (the abandon would hit whatever stays selected).
local function OnLog(ql, id)
    if not ql.IsOnQuest then return true end
    local ok, r = pcall(ql.IsOnQuest, id)
    return not (ok and r == false)
end

--- Abandon the given quests; returns how many went. The ids were
-- collected up front, so the shifting log does not matter here.
function Q.Abandon(list)
    local ql = QL()
    if not ql or not ql.SetSelectedQuest or not ql.SetAbandonQuest or not ql.AbandonQuest then return 0 end
    local n = 0
    for _, q in ipairs(list or {}) do
        if OnLog(ql, q.questID) and CanAbandon(ql, q.questID) then
            local ok = pcall(function()
                ql.SetSelectedQuest(q.questID)
                ql.SetAbandonQuest()
                ql.AbandonQuest()
            end)
            if ok then n = n + 1 end
        end
    end
    ns.Print(("abandoned %d quest%s"):format(n, n == 1 and "" or "s"))
    return n
end

--- `list`: the quests a confirmation named (taken when it opened), so one
-- picked up or gone low-level while it was open is left alone.
function Q.AbandonAll(list)
    if not Enabled() then return 0 end
    return Q.Abandon(list or Q.List())
end

function Q.AbandonZone(list)
    if not Enabled() then return 0 end
    return Q.Abandon(list or {})
end

function Q.AbandonLowLevel(list)
    if not Enabled() then return 0 end
    return Q.Abandon(list or Q.LowLevel())
end

-- ------------------------------------------------------------ best reward

--[[ A gold coin on the quest reward that sells for the most (Alex,
2026-10-01): vendor price x count, among the choices offered at a
turn-in (and in the quest log / map view). Ties all get one; nothing is
marked when there is a single choice or nothing sells. The coin is our
own small frame on the tile, not a texture of the tile: Ellesmere's skin
fades the tile's own art (it erased the spellbook tab's icon before).
]]

local COIN_ATLAS = "coin-gold"
local COIN_FILE = "Interface\\MoneyFrame\\UI-GoldIcon"

local function MarkOn() local o = ns.db and ns.db.quests return Enabled() and not (o and o.goldMark == false) end

--- Vendor value of choice i: sell price x count, nil while the item is not cached.
function Q.ChoiceValue(i, questLog)
    local link, count
    if questLog then
        local fl = rawget(_G, "GetQuestLogItemLink")
        link = fl and select(2, pcall(fl, "choice", i))
        local fi = rawget(_G, "GetQuestLogChoiceInfo")
        if fi then local ok, _, _, n = pcall(fi, i) count = ok and n or nil end
    else
        local fl = rawget(_G, "GetQuestItemLink")
        link = fl and select(2, pcall(fl, "choice", i))
        local fi = rawget(_G, "GetQuestItemInfo")
        if fi then local ok, _, _, n = pcall(fi, "choice", i) count = ok and n or nil end
    end
    if not ns.Str(link) then return nil end
    local ci = rawget(_G, "C_Item")
    local info = ci and ci.GetItemInfo
    if not info then return nil end
    local ok, name, _, _, _, _, _, _, _, _, _, price = pcall(info, link)
    if not ok or not name then return nil end
    return (ns.Num(price) and price or 0) * (ns.Num(count) and count > 0 and count or 1)
end

local function Coin(btn)
    if btn.snGold then return btn.snGold end
    local f = CreateFrame("Frame", nil, btn)
    f:SetSize(14, 14)
    -- inside the item icon's top-left corner (the tile itself is wider than
    -- its icon, and Ellesmere crops the icon square: Alex, 2026-10-02)
    local icon = rawget(btn, "Icon")
    if type(icon) == "table" and icon.GetObjectType then
        f:SetPoint("TOPLEFT", icon, "TOPLEFT", 1, -1)
    else
        f:SetPoint("TOPLEFT", btn, "TOPLEFT", 1, -1)
    end
    f:SetFrameLevel((btn:GetFrameLevel() or 1) + 5)
    f.tex = f:CreateTexture(nil, "OVERLAY")
    f.tex:SetAllPoints()
    local okA = f.tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(COIN_ATLAS)
    if okA then f.tex:SetAtlas(COIN_ATLAS) else f.tex:SetTexture(COIN_FILE) end
    f:Hide()
    btn.snGold = f
    return f
end

local waiting = false
--- Mark the best-selling choice in one rewards frame. Returns the indices marked.
function Q.MarkRewards(frame, questLog)
    local marked = {}
    if not (frame and type(frame.RewardButtons) == "table") then return marked end
    local choices = {}
    for _, btn in ipairs(frame.RewardButtons) do
        if btn.snGold then btn.snGold:Hide() end
        if btn.type == "choice" and btn:IsShown() then choices[#choices + 1] = btn end
    end
    -- a closed frame's tiles keep their shown flag: never wait on those
    -- (every item-info event re-walked them for the session: sweep 2). The
    -- map draws its quest details before showing them: live while it's open
    local map = rawget(_G, "WorldMapFrame")
    local live = not frame.IsVisible or frame:IsVisible()
        or (frame == rawget(_G, "MapQuestInfoRewardsFrame") and map and map:IsVisible())
    if not MarkOn() or #choices < 2 then return marked end
    local best, values = 0, {}
    for _, btn in ipairs(choices) do
        local v = Q.ChoiceValue(btn:GetID(), questLog)
        if v == nil and live then waiting = true end
        values[btn] = v or 0
        if (v or 0) > best then best = v end
    end
    if best <= 0 then return marked end
    for _, btn in ipairs(choices) do
        if values[btn] == best then
            Coin(btn):Show()
            marked[#marked + 1] = btn:GetID()
        end
    end
    return marked
end

local function MarkAll()
    waiting = false
    local qif = rawget(_G, "QuestInfoFrame")
    Q.MarkRewards(rawget(_G, "QuestInfoRewardsFrame"), qif and qif.questLog and true or false)
    Q.MarkRewards(rawget(_G, "MapQuestInfoRewardsFrame"), true)
end
Q.MarkAll = MarkAll

local hooked = false
function Q.HookRewards()
    if hooked or type(rawget(_G, "QuestInfo_Display")) ~= "function" then return hooked end
    hooksecurefunc("QuestInfo_Display", MarkAll)
    hooked = true
    return true
end
Q.HookRewards()
ns.On("PLAYER_LOGIN", function() Q.HookRewards() end)
ns.On("ADDON_LOADED", function() Q.HookRewards() end)
-- an uncached reward's price arrives later: look again once it does
ns.On("GET_ITEM_INFO_RECEIVED", function() if waiting then MarkAll() end end)
ns.On("QUEST_FINISHED", function() waiting = false end)
