--[[ Salus Novus -- Builder: a small window that appends the next step.

Alex (2026-09-21): "construct my own guide/steps as I go" -- a window
small enough to leave open, with a clickable menu that adds the NEXT step
of the route being built. Buttons: a quest picker (the log) with Accept /
Objective / Turn in; Note (custom text, no quest); Go here (a travel step
at the player's position); Train / Bind / Fly / Hearth; a text box with a
Coords button that drops the position into it; Undo (removes the last
step); a step counter. Steps append to the END of the route -- that is what
"next" means while building -- and, if the character has no route yet,
one is created first (RouteEditor.EnsureRoute), so a route can be built
from nothing.

Every append goes through RouteEditor: live into ns.Routes and into the
edit log the PC build applies. /sn build toggles the window; the Steps tab
has a button for it too.
]]

local _, ns = ...

local B = {}
ns.Builder = B

local SOLID = "Interface\\Buttons\\WHITE8x8"
local W, PAD = 324, 8

local frame

local function E() return ns.RouteEditor end

local function SavePosition() ns.SaveAnchor(frame, "builderPos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "builderPos", "RIGHT", -40, 0, "RIGHT")
end
ns.BuilderRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "builderPos", restore = "BuilderRestorePosition" })

local function Coords()
    local map, x, y = ns.Guide.PlayerPos()
    if not (map and x and y) then return nil end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

--- Append a step of `kind` and redraw. Returns the new index or nil.
function B.Add(kind)
    local text = frame and frame.text:GetText() or ""
    local questID = frame and frame.quest
    -- The step is built before any route is: a blank Note must not leave
    -- an empty route behind (bug hunt 8, lane 9).
    if not E().NewStep(kind, questID, text) then return nil end
    local route = E().EnsureRoute()
    if not route then return nil end
    local at = E().Append(route, kind, questID, text)
    if at and frame then
        frame.text:SetText("")
        frame.text:ClearFocus()
    end
    B.Refresh()
    return at
end

function B.Undo()
    local route = ns.Guide.PickRoute()
    if not route or #route.steps == 0 then return false end
    local ok = E().Delete(route, #route.steps)
    B.Refresh()
    return ok
end

local function MakeBtn(parent, label, w, onClick)
    local T = ns.Theme
    local b = T.MakeButton(parent)
    b:SetSize(w, 22)
    b:SetText(label)
    b:SetScript("OnClick", function(self) if self.enabledState then onClick(self) end end)
    return b
end

local function Build()
    if frame then return frame end
    local T = ns.Theme
    frame = CreateFrame("Frame", "SalusNovusBuilder", UIParent)
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:SetClampedToScreen(true)
    frame:SetSize(W, 150)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePosition() end)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetTexture(SOLID)
    frame.bg:SetAllPoints()
    frame.bg:SetVertexColor(T.BG[1], T.BG[2], T.BG[3], 0.96)
    frame.border = T.Border(frame)
    frame.border:Layout(frame, 1, 0)
    frame.border:SetColor(T.EDGE[1], T.EDGE[2], T.EDGE[3], 1)
    frame.border:Show()
    frame.rail = frame:CreateTexture(nil, "ARTWORK")
    frame.rail:SetTexture(SOLID)
    frame.rail:SetWidth(T.RAIL_W)
    frame.rail:SetPoint("TOPLEFT", 0, 0)
    frame.rail:SetPoint("BOTTOMLEFT", 0, 0)
    T.Paint({ tex = frame.rail, a = 1 })

    -- Title row: route name + count, close.
    frame.title = T.MakeText(frame, 11, T.TEXT_MUTE)
    frame.title:SetPoint("TOPLEFT", T.RAIL_W + PAD, -PAD)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -60, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)
    frame.close = MakeBtn(frame, "X", 22, function() frame:Hide() end)
    frame.close:SetPoint("TOPRIGHT", -PAD, -PAD + 2)
    frame.undo = MakeBtn(frame, "Undo", 48, function() B.Undo() end)
    frame.undo:SetPoint("RIGHT", frame.close, "LEFT", -4, 0)

    -- Quest row: picker + Accept / Objective / Turn in.
    frame.quest = nil
    frame.questBtn = T.MakeHeaderButton(frame, 120, function(self)
        local values, labels = {}, {}
        for _, q in ipairs(E().LogQuests()) do
            values[#values + 1] = q.questID
            labels[q.questID] = q.title
        end
        if #values == 0 then return end
        if ns.Options and ns.Options.OpenPickerList then
            ns.Options.OpenPickerList(self, values, labels, frame.quest, function(v)
                frame.quest = v
                B.Refresh()
            end)
        end
    end)
    frame.questBtn:SetHeight(22)
    frame.questBtn:SetPoint("TOPLEFT", T.RAIL_W + PAD, -PAD - 20)
    frame.accept = MakeBtn(frame, "Accept", 52, function() B.Add("accept") end)
    frame.accept:SetPoint("LEFT", frame.questBtn, "RIGHT", 4, 0)
    frame.objective = MakeBtn(frame, "Obj", 40, function() B.Add("do") end)
    frame.objective:SetPoint("LEFT", frame.accept, "RIGHT", 4, 0)
    frame.turnin = MakeBtn(frame, "Turn in", 60, function() B.Add("turnin") end)
    frame.turnin:SetPoint("LEFT", frame.objective, "RIGHT", 4, 0)

    -- Text row: box + Coords.
    frame.text = T.MakeEditBox(frame, W - T.RAIL_W - PAD * 2 - 64)
    frame.text:SetPoint("TOPLEFT", frame.questBtn, "BOTTOMLEFT", 0, -6)
    frame.coords = MakeBtn(frame, "Coords", 60, function()
        local c = Coords()
        if not c then return end
        local cur = frame.text:GetText() or ""
        frame.text:SetText((cur == "" and "" or (cur .. " ")) .. c)
    end)
    frame.coords:SetPoint("LEFT", frame.text, "RIGHT", 4, 0)

    -- Kind row: Note / Go here / Train / Bind / Fly / Hearth.
    local prev
    frame.kinds = {}
    for _, spec in ipairs({ { "Note", "note", 44 }, { "Go here", "go", 58 }, { "Train", "train", 46 }, { "Bind", "bind", 40 }, { "Fly", "fly", 36 }, { "Hearth", "hearth", 54 } }) do
        local b = MakeBtn(frame, spec[1], spec[3], function() B.Add(spec[2]) end)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else b:SetPoint("TOPLEFT", frame.text, "BOTTOMLEFT", 0, -6) end
        frame.kinds[spec[2]] = b
        prev = b
    end

    -- Last step line.
    frame.last = T.MakeText(frame, 11, T.TEXT_DIM)
    frame.last:SetPoint("TOPLEFT", frame.kinds.note, "BOTTOMLEFT", 0, -8)
    frame.last:SetPoint("RIGHT", frame, "RIGHT", -PAD, 0)
    frame.last:SetJustifyH("LEFT")
    frame.last:SetWordWrap(false)

    frame:SetHeight(PAD + 20 + 22 + 6 + 22 + 6 + 22 + 8 + 14 + PAD)
    RestorePosition()
    return frame
end
B.Build = Build

function B.Refresh()
    if not frame or not frame:IsShown() then return end
    local route = ns.Guide.PickRoute()
    local n = route and #route.steps or 0
    frame.title:SetText(route and ("%s  \194\183  %d step%s"):format(route.name or route.slug, n, n == 1 and "" or "s") or "No route yet: the first step makes one")
    local quests = E().LogQuests()
    local still = false
    for _, q in ipairs(quests) do if q.questID == frame.quest then still = true end end
    if not still then frame.quest = quests[1] and quests[1].questID or nil end
    local title = "(no quests)"
    for _, q in ipairs(quests) do if q.questID == frame.quest then title = q.title end end
    frame.questBtn.text:SetText(title)
    local haveQuest = frame.quest ~= nil
    frame.questBtn:SetEnabled(haveQuest)
    frame.accept:SetEnabledState(haveQuest)
    frame.objective:SetEnabledState(haveQuest)
    frame.turnin:SetEnabledState(haveQuest)
    frame.undo:SetEnabledState(n > 0)
    if n > 0 then
        frame.last:SetText(("last: %d. %s"):format(n, ns.Guide.StepText(route.steps[n])))
    else
        frame.last:SetText("")
    end
end

function B.Toggle()
    Build()
    if frame:IsShown() then frame:Hide() else frame:Show() B.Refresh() end
end
function B.Show() Build() frame:Show() B.Refresh() end
function B.IsShown() return frame ~= nil and frame:IsShown() end

ns.On("QUEST_LOG_UPDATE", function() B.Refresh() end)
ns.On("QUEST_ACCEPTED", function() B.Refresh() end)
ns.On("QUEST_TURNED_IN", function() B.Refresh() end)

ns.Commands = ns.Commands or {}
ns.Commands.build = function() B.Toggle() end
