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

--- The quests in the log: { questID, title, level, trivial }, headers,
-- hidden entries and world-quest tasks skipped. A throwing GetInfo or a
-- secret id skips that row rather than the whole list.
function Q.List()
    local out = {}
    local ql = QL()
    if not ql or not ql.GetNumQuestLogEntries or not ql.GetInfo then return out end
    local okN, n = pcall(ql.GetNumQuestLogEntries)
    if not okN or type(n) ~= "number" or ns.IsSecret(n) then return out end
    for i = 1, n do
        local ok, info = pcall(ql.GetInfo, i)
        if ok and type(info) == "table" and not info.isHeader and not info.isHidden then
            local id = info.questID
            if type(id) == "number" and not ns.IsSecret(id) and id > 0 then
                local task = false
                if ql.IsQuestTask then
                    local okT, t = pcall(ql.IsQuestTask, id)
                    task = okT and t == true
                end
                if not task then
                    out[#out + 1] = { questID = id, title = info.title, level = info.level, trivial = Q.IsTrivial(id, info.level) }
                end
            end
        end
    end
    return out
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

--- Abandon the given quests; returns how many went. The ids were
-- collected up front, so the shifting log does not matter here.
function Q.Abandon(list)
    local ql = QL()
    if not ql or not ql.SetSelectedQuest or not ql.SetAbandonQuest or not ql.AbandonQuest then return 0 end
    local n = 0
    for _, q in ipairs(list or {}) do
        if CanAbandon(ql, q.questID) then
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

function Q.AbandonAll()
    if not Enabled() then return 0 end
    return Q.Abandon(Q.List())
end

function Q.AbandonLowLevel()
    if not Enabled() then return 0 end
    return Q.Abandon(Q.LowLevel())
end
