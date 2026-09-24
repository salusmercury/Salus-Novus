--[[ Salus Novus -- Guide: play a recorded leveling route back on another character.

Leveling > Guide (Alex, 2026-09-21). Routes come from build_route.py
(Data/Routes.lua, ns.Routes): an ordered list of steps -- accept / do /
turnin (a quest, an objective index, a place, an NPC), level, train, bind,
fly, hearth, note -- with map coordinates where the builder stood.

WHERE YOU ARE is read from the client, never saved: an accept step is done
once the quest is in the log or flagged complete, a do step once its
objective is finished or the quest is ready to turn in, a turn-in once the
quest is flagged complete, a level step once you are that level. Steps the
client cannot vouch for (train, bind, fly, hearth, note) are done when
Skip is pressed, when their own event fires this session (a hearth bind, a
trainer window), or once ANY later checkable step is done. So a /reload,
or the saved-variables bug this account has, costs nothing: the place in
the route is recomputed from the quest log.

The frame shows the current step, the next few dimmed, and the distance
to it; Arrow.lua points the way. (The client's own user-waypoint pin was
tried and removed: Alex, "the arrow suffices".)
]]

local _, ns = ...

local G = {}
ns.Guide = G

local SOLID = "Interface\\Buttons\\WHITE8x8"

local function O() return ns.db and ns.db.guide end
local function Enabled()
    local o = O()
    return o and o.enabled ~= false and ns.ModuleOn("leveling") and true or false
end
G.Enabled = Enabled

local function Num(v) return type(v) == "number" and not ns.IsSecret(v) end
local function Str(v) return type(v) == "string" and not ns.IsSecret(v) and v or nil end

local function QL() return rawget(_G, "C_QuestLog") end

-- ------------------------------------------------------------ route pick

local function PlayerLevel()
    local ok, l = pcall(UnitLevel, "player")
    return ok and Num(l) and l or 0
end

local function Me()
    local okF, faction = pcall(UnitFactionGroup, "player")
    local okR, race = pcall(function() return select(2, UnitRace("player")) end)
    local okC, class = pcall(function() return select(2, UnitClass("player")) end)
    return okF and Str(faction) or nil, okR and Str(race) or nil, okC and Str(class) or nil
end

--- The route to follow: the chosen slug, or the best match for this
-- character (faction must match; race and class score).
function G.PickRoute()
    local routes = ns.Routes or {}
    local o = O()
    local want = o and o.route
    if want and want ~= "auto" then
        for _, r in ipairs(routes) do if r.slug == want then return r end end
    end
    local faction, race, class = Me()
    local level = PlayerLevel()
    local best, bestScore
    for _, r in ipairs(routes) do
        if not faction or not r.faction or r.faction == faction then
            local score = (r.race == race and 4 or 0) + (r.class == class and 2 or 0)
            local lv = r.levels
            if type(lv) == "table" and Num(lv[1]) and Num(lv[2]) and level >= lv[1] and level <= lv[2] then score = score + 1 end
            if not best or score > bestScore then best, bestScore = r, score end
        end
    end
    return best
end

-- ------------------------------------------------------------ progress

local skipped = {}          -- [routeSlug] = { [stepIndex] = true }, this session only
local arrived = {}          -- [routeSlug] = { [stepIndex] = true }: go steps reached this session
local hearthBoundAt, trainedAt = 0, 0

local function Flagged(questID)
    local ql = QL()
    if not ql or not ql.IsQuestFlaggedCompleted then return false end
    local ok, r = pcall(ql.IsQuestFlaggedCompleted, questID)
    return ok and r == true
end

local function OnQuest(questID)
    local ql = QL()
    if not ql or not ql.IsOnQuest then return false end
    local ok, r = pcall(ql.IsOnQuest, questID)
    return ok and r == true
end

local function ReadyForTurnIn(questID)
    local ql = QL()
    if not ql or not ql.ReadyForTurnIn then return false end
    local ok, r = pcall(ql.ReadyForTurnIn, questID)
    return ok and r == true
end

local function ObjectiveDone(questID, index)
    local ql = QL()
    if not ql or not ql.GetQuestObjectives then return false end
    local ok, list = pcall(ql.GetQuestObjectives, questID)
    if not ok or type(list) ~= "table" then return false end
    local ob = list[index or 1]
    return type(ob) == "table" and ob.finished == true
end

--- The objective's own text from the log (progress included), or nil.
local function LiveObjective(questID, index)
    local ql = QL()
    if not ql or not ql.GetQuestObjectives then return nil end
    local ok, list = pcall(ql.GetQuestObjectives, questID)
    if not ok or type(list) ~= "table" then return nil end
    local ob = list[index or 1]
    local t = type(ob) == "table" and ob.text
    if type(t) ~= "string" or ns.IsSecret(t) or t == "" then return nil end
    return t
end


--- Can the client vouch for this step at all?
function G.Checkable(step)
    local k = step.k
    return k == "accept" or k == "do" or k == "turnin" or k == "level"
end

--- Is a checkable step done, by the client's own state?
function G.StepDone(step)
    local k = step.k
    if k == "accept" then return OnQuest(step.q) or Flagged(step.q) end
    if k == "turnin" then return Flagged(step.q) end
    if k == "do" then return Flagged(step.q) or ReadyForTurnIn(step.q) or (OnQuest(step.q) and ObjectiveDone(step.q, step.o)) end
    if k == "level" then return PlayerLevel() >= (step.l or 0) end
    return false
end

--- Index of the current step (the first not done), or nil when the route
-- is finished. Uncheckable steps pass once skipped, once their own event
-- fired this session, or once any later checkable step is done.
function G.CurrentIndex(route)
    if not route then return nil end
    local steps = route.steps or {}
    local sk = skipped[route.slug] or {}
    -- the last checkable step that is done: everything before it passes
    local lastDone = 0
    for i = #steps, 1, -1 do
        if G.Checkable(steps[i]) and G.StepDone(steps[i]) then lastDone = i break end
    end
    for i, s in ipairs(steps) do
        local done
        if G.Checkable(s) then
            done = sk[i] or G.StepDone(s)              -- a skipped quest stays skipped this session
        else
            done = sk[i] or i < lastDone
                or (s.k == "bind" and hearthBoundAt > 0)
                or (s.k == "train" and trainedAt > 0)
                or (s.k == "go" and G.Arrived(route, i))
        end
        if not done then return i end
    end
    return nil
end

function G.Skip(route, index)
    if not route or not index then return end
    skipped[route.slug] = skipped[route.slug] or {}
    skipped[route.slug][index] = true
end

function G.ResetSkips() skipped = {}; arrived = {}; hearthBoundAt, trainedAt = 0, 0 end

--- Keep skips pointing at the same steps after the editor changes the
-- route: "del" at i drops it and shifts later ones down, "ins" after i
-- shifts later ones up, "up"/"down" swap i with its neighbour.
function G.AdjustSkips(route, op, at, to)
    local sk = route and skipped[route.slug]
    if not sk then return end
    local out = {}
    for i in pairs(sk) do
        local j = i
        if op == "mv" then
            if i == at then
                j = to
            else
                j = (i > at) and (i - 1) or i             -- after the removal
                if j >= to then j = j + 1 end              -- after the insert
            end
        elseif op == "del" then
            if i == at then j = nil elseif i > at then j = i - 1 end
        elseif op == "ins" then
            if i > at then j = i + 1 end
        elseif op == "up" then
            if i == at then j = at - 1 elseif i == at - 1 then j = at end
        elseif op == "down" then
            if i == at then j = at + 1 elseif i == at + 1 then j = at end
        end
        if j then out[j] = true end
    end
    skipped[route.slug] = out
end

-- ------------------------------------------------------------ text

local titleAsked = {}
local function QuestTitle(questID)
    local ql = QL()
    if ql and ql.GetTitleForQuestID then
        local ok, t = pcall(ql.GetTitleForQuestID, questID)
        if ok and Str(t) and t ~= "" then return t end
    end
    if ql and ql.RequestLoadQuestByID and not titleAsked[questID] then
        titleAsked[questID] = true
        pcall(ql.RequestLoadQuestByID, questID)
    end
    return "quest " .. tostring(questID)
end

function G.StepText(step)
    local k = step.k
    if k == "accept" then return ("Accept %s%s"):format(QuestTitle(step.q), step.n and (" from " .. step.n) or "") end
    if k == "turnin" then return ("Turn in %s%s"):format(QuestTitle(step.q), step.n and (" to " .. step.n) or "") end
    if k == "do" then
        -- Live from the log while the quest is in it (the client's own
        -- "2/8 Tough Wolf Meat"); stored text, if any, only as a fallback.
        local live = OnQuest(step.q) and LiveObjective(step.q, step.o)
        if live then return "Complete objective: " .. live end
        return "Complete objective" .. (step.text and (": " .. step.text) or "") .. " (" .. QuestTitle(step.q) .. ")"
    end
    if k == "level" then return ("Reach level %d"):format(step.l or 0) end
    if k == "train" then return "Train" .. (step.text and (": " .. step.text) or (step.n and (" at " .. step.n) or "")) end
    if k == "bind" then return "Set your hearth" .. (step.text and (": " .. step.text) or (step.n and (" at " .. step.n) or "")) end
    if k == "fly" then return "Take the flight path" .. (step.text and (": " .. step.text) or "") end
    if k == "go" then
        if step.text then return "Go to " .. step.text end
        if step.x and step.y then return ("Go to %.1f, %.1f"):format(step.x * 100, step.y * 100) end
        return "Go"
    end
    if k == "hearth" then return "Hearth" .. (step.text and (": " .. step.text) or "") end
    if k == "note" then return step.text or "" end
    return tostring(k)
end

-- ------------------------------------------------------------ distance

local function PlayerPos()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, map = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or not Num(map) then return nil end
    local okP, pos = pcall(C_Map.GetPlayerMapPosition, map, "player")
    if not okP or type(pos) ~= "table" then return map end
    local x, y = pos.x, pos.y
    if type(pos.GetXY) == "function" then
        local okXY, gx, gy = pcall(pos.GetXY, pos)
        if okXY then x, y = gx, gy end
    end
    if not (Num(x) and Num(y)) then return map end
    return map, x, y
end
G.PlayerPos = PlayerPos

--- Yards from the player to a step, or nil (other map, secret position).
function G.Distance(step)
    if not (step and Num(step.m) and Num(step.x) and Num(step.y)) then return nil end
    local map, x, y = PlayerPos()
    if map ~= step.m or not x then return nil end
    if not C_Map.GetMapWorldSize then return nil end
    local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
    if not ok or not (Num(w) and Num(h)) then return nil end
    local dx, dy = (step.x - x) * w, (step.y - y) * h
    return math.sqrt(dx * dx + dy * dy)
end

-- ------------------------------------------------------------ arrival

-- A "go" step is done once the player has been within ARRIVE yards of it
-- this session (the arrow's tick reports that), or on Skip.
local ARRIVE = 15
G.ARRIVE = ARRIVE
function G.MarkArrived(route, index)
    if not route or not index then return end
    arrived[route.slug] = arrived[route.slug] or {}
    if arrived[route.slug][index] then return end
    arrived[route.slug][index] = true
    G.Refresh()
end
function G.Arrived(route, index)
    local a = route and arrived[route.slug]
    return a and a[index] == true or false
end

-- ------------------------------------------------------------ frame

local frame
local lines = {}
function G.Lines() return lines end             -- test seam
local state = { route = nil, index = nil }
G.state = state

local function SavePosition() ns.SaveAnchor(frame, "guidePos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "guidePos", "TOPRIGHT", -30, -220, "TOPRIGHT")
end
ns.GuideRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "guidePos", restore = "GuideRestorePosition" })

local function Build()
    if frame then return frame end
    local T = ns.Theme
    frame = CreateFrame("Frame", "SalusNovusGuide", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(320, 90)
    frame:Hide()
    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetTexture(SOLID)
    frame.bg:SetAllPoints()
    frame.bg:SetVertexColor(T.CARD[1], T.CARD[2], T.CARD[3], 0.92)
    frame.rail = frame:CreateTexture(nil, "ARTWORK")
    frame.rail:SetTexture(SOLID)
    frame.rail:SetWidth(T.RAIL_W)
    frame.rail:SetPoint("TOPLEFT", 0, 0)
    frame.rail:SetPoint("BOTTOMLEFT", 0, 0)
    T.Paint({ tex = frame.rail, a = 1 })

    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Guide  \194\183  drag to move")
    frame.unlockLabel:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.title, 10, "")
    frame.title:SetPoint("TOPLEFT", T.RAIL_W + 10, -8)
    frame.title:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1)

    frame.distance = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.distance, 10, "")
    frame.distance:SetPoint("TOPRIGHT", -10, -8)
    frame.distance:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1)
    -- a long route name stops short of the distance (hunt 9, lane 4)
    frame.title:SetPoint("RIGHT", frame.distance, "LEFT", -8, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    frame.current = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.current, 14, "")
    frame.current:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
    frame.current:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
    frame.current:SetJustifyH("LEFT")
    frame.current:SetWordWrap(true)

    frame.skip = T.MakeButton(frame)
    frame.skip:SetSize(60, 20)
    frame.skip:SetPoint("BOTTOMRIGHT", -8, 8)
    frame.skip:SetText("Skip")
    frame.skip:SetScript("OnClick", function()
        if state.route and state.index then
            G.Skip(state.route, state.index)
            G.Refresh()
        end
    end)

    ns.RegisterMovable(frame, "guidePos", function() return "TOPRIGHT" end)
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
G.Build = Build

local function NextLine(i)
    local T = ns.Theme
    local l = lines[i]
    if l then return l end
    l = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(l, 11, "")
    l:SetJustifyH("LEFT")
    l:SetWordWrap(false)
    l:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1)
    lines[i] = l
    return l
end

local function DistanceText()
    local step = state.route and state.index and state.route.steps[state.index]
    local d = step and G.Distance(step)
    if not d then return "" end
    return ("%d yd"):format(d + 0.5)
end

--- Recompute the place in the route and redraw.
function G.Refresh()
    local T = ns.Theme
    local o = O() or {}
    Build()
    local unlocked = ns.db and ns.db.unlocked
    if not Enabled() and not unlocked then
        state.route, state.index = nil, nil
        frame:Hide()
        if ns.Arrow then ns.Arrow.Refresh() end
        return
    end
    local route = G.PickRoute()
    local index = route and G.CurrentIndex(route) or nil
    state.route, state.index = route, index
    ns.SetFontSafe(frame.current, tonumber(o.size) or 14, "")
    frame.unlockLabel:SetShown(unlocked and true or false)
    if not route then
        frame.title:SetText("No route")
        frame.current:SetText("Open the builder (/sn build) to start one.")
        frame.distance:SetText("")
        for _, l in ipairs(lines) do l:Hide() end
        frame.skip:Hide()
        frame:SetHeight(70)
        frame:SetShown(unlocked and true or false)
        if ns.Arrow then ns.Arrow.Refresh() end
        return
    end
    frame.title:SetText(route.name or route.slug)
    local y
    if not index then
        frame.current:SetText("Route complete")
        frame.distance:SetText("")
        for _, l in ipairs(lines) do l:Hide() end
        frame.skip:Hide()
        y = 70
    else
        local step = route.steps[index]
        frame.current:SetText(("%d/%d  %s"):format(index, #route.steps, G.StepText(step)))
        frame.distance:SetText(DistanceText())
        frame.skip:Show()
        local shown = 0
        local anchor = frame.current
        local want = tonumber(o.showNext) or 2
        if want < 0 or want ~= want then want = 2 end      -- a hand-edited file (bug hunt 8, lane 10)
        for i = index + 1, math.min(#route.steps, index + want) do
            shown = shown + 1
            local l = NextLine(shown)
            l:ClearAllPoints()
            l:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -4)
            l:SetPoint("RIGHT", frame, "RIGHT", -10, 0)
            l:SetText(G.StepText(route.steps[i]))
            l:Show()
            anchor = l
        end
        for i = shown + 1, #lines do lines[i]:Hide() end
        local curH = frame.current:GetStringHeight() or 16
        y = 8 + 12 + 6 + curH + shown * 17 + 8 + 20 + 8
    end
    frame:SetHeight(math.max(70, y))
    frame:Show()
    -- No SyncAnchorOrigin here: the frame hangs from its TOPRIGHT, so a
    -- height change keeps the origin, and the sync re-saved a record that
    -- /sn resetpos had just cleared (hunt 9, lane 2).
    if ns.Arrow then ns.Arrow.Refresh() end
end

-- ------------------------------------------------------------ events

local function Bump(fn)
    return function(...)
        fn(...)
        if Enabled() then G.Refresh() end
    end
end

for _, ev in ipairs({ "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE", "UNIT_QUEST_LOG_CHANGED",
                      "PLAYER_LEVEL_UP", "PLAYER_ENTERING_WORLD", "QUEST_DATA_LOAD_RESULT" }) do
    ns.On(ev, Bump(function() end))
end
ns.On("HEARTHSTONE_BOUND", Bump(function() hearthBoundAt = time() end))

-- Uncheckable events that the bus may not know: own frame, quiet.
local own = CreateFrame("Frame")
pcall(own.RegisterEvent, own, "TRAINER_SHOW")
own:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" then
        trainedAt = time()
        if Enabled() then G.Refresh() end
    end
end)

-- The distance line follows the player.
local ticker
ns.On("PLAYER_LOGIN", function()
    if ticker then return end
    ticker = C_Timer.NewTicker(1, function()
        if frame and frame:IsShown() and state.index then frame.distance:SetText(DistanceText()) end
    end)
end)

ns.RegisterApply(function() G.Refresh() end, "Guide")

ns.Commands = ns.Commands or {}
ns.Commands.guide = function(rest)
    local arg = (rest or ""):match("^(%S*)"):lower()
    if arg == "reset" then
        G.ResetSkips()
        G.Refresh()
        ns.Print("guide: skips cleared")
        return
    end
    local route = G.PickRoute()
    if not route then ns.Print("guide: no route for this character (" .. #(ns.Routes or {}) .. " loaded)") return end
    local index = G.CurrentIndex(route)
    ns.Print(("guide: %s -- step %s of %d%s"):format(route.name or route.slug, tostring(index or "done"), #route.steps,
        index and (": " .. G.StepText(route.steps[index])) or ""))
end
