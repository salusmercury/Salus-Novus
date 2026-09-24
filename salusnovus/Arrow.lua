--[[ Salus Novus -- Arrow: a direction arrow to the guide's current step.

The client's supertracked pin floats in the world but does not say which
way to turn (Alex, 2026-09-21: "I need the waypoint arrow thing to point
me"). This is that arrow: its own anchor (arrowPos), an arrow texture
rotated to the bearing of the current step relative to the player's
facing, the distance under it, updated a few times a second while shown.

Bearing: in WORLD space when both ends convert (C_Map.GetWorldPosFromMapPos:
x grows north, y grows west; so bearing = atan2(dWest, dNorth), counter-
clockwise from north like GetPlayerFacing), which also works when the
player stands on a different map of the same continent (a city inside the
zone). Fallback: map space on the same map, x east and y south, scaled by
GetMapWorldSize. The texture rotates by bearing - facing.
]]

local _, ns = ...

local A = {}
ns.Arrow = A

-- Our own 128 px arrow (make_arrow_texture.py): the client's atlas is a
-- small texture and went fuzzy scaled to 48 px (Alex, 2026-09-21).
local OWN_TEX = "Interface\\AddOns\\SalusNovus\\Textures\\arrow.tga"
local ATLAS = "Navigation-Tracked-Arrow"
local FALLBACK_TEX = "Interface\\Minimap\\MinimapArrow"
local TICK = 0.05

local function O() return ns.db and ns.db.guide end
local function Enabled()
    local o = O()
    return o and o.enabled ~= false and o.arrow ~= false and ns.ModuleOn("leveling") and true or false
end
A.Enabled = Enabled

local Num = ns.Num

local function Vec(x, y)
    if CreateVector2D then return CreateVector2D(x, y) end
    return { x = x, y = y }
end

local function WorldPos(map, x, y)
    if not (C_Map and C_Map.GetWorldPosFromMapPos) then return nil end
    local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, map, Vec(x, y))
    if not ok or type(pos) ~= "table" then return nil end
    local wx, wy = pos.x, pos.y
    if type(pos.GetXY) == "function" then
        local okXY, gx, gy = pcall(pos.GetXY, pos)
        if okXY then wx, wy = gx, gy end
    end
    if not (Num(wx) and Num(wy)) then return nil end
    return cont, wx, wy
end

--- Bearing (radians, counter-clockwise from north) and distance (yards)
-- from the player to a step, or nil when either end is unknown.
function A.Bearing(step)
    if not (step and Num(step.m) and Num(step.x) and Num(step.y)) then return nil end
    local map, px, py = ns.Guide.PlayerPos()
    if not (Num(map) and Num(px) and Num(py)) then return nil end
    local c1, n1, w1 = WorldPos(map, px, py)
    local c2, n2, w2 = WorldPos(step.m, step.x, step.y)
    if n1 and n2 and (c1 == c2 or c1 == nil or c2 == nil) then
        local dN, dW = n2 - n1, w2 - w1
        return math.atan2(dW, dN), math.sqrt(dN * dN + dW * dW)
    end
    if map ~= step.m or not (C_Map and C_Map.GetMapWorldSize) then return nil end
    local ok, w, h = pcall(C_Map.GetMapWorldSize, map)
    if not ok or not (Num(w) and Num(h)) then return nil end
    local dE, dS = (step.x - px) * w, (step.y - py) * h
    return math.atan2(-dE, -dS), math.sqrt(dE * dE + dS * dS)
end

local function Facing()
    if type(GetPlayerFacing) ~= "function" then return 0 end
    local ok, f = pcall(GetPlayerFacing)
    return ok and Num(f) and f or 0
end

-- ------------------------------------------------------------ frame

local frame

local function SavePosition() ns.SaveAnchor(frame, "arrowPos") end
local function RestorePosition()
    if not frame then return end
    ns.RestoreAnchor(frame, "arrowPos", "TOP", 0, -120, "TOP")
end
ns.ArrowRestorePosition = RestorePosition
table.insert(ns.AnchorPositions, { key = "arrowPos", restore = "ArrowRestorePosition" })

local function Size()
    local o = O()
    local n = o and tonumber(o.arrowSize)
    return (n and n > 0 and n == n) and n or 48
end

local function Build()
    if frame then return frame end
    local T = ns.Theme
    frame = CreateFrame("Frame", "SalusNovusArrow", UIParent)
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(Size() + 8, Size() + 24)
    frame:Hide()

    frame.unlockBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.unlockBg:SetTexture("Interface\\Buttons\\WHITE8x8")
    frame.unlockBg:SetAllPoints()
    frame.unlockBg:SetVertexColor(1, 1, 1, 0.12)
    frame.unlockBg:Hide()
    frame.unlockLabel = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.unlockLabel, 10, "OUTLINE")
    frame.unlockLabel:SetPoint("BOTTOM", frame, "TOP", 0, 3)
    frame.unlockLabel:SetText("Arrow  \194\183  drag to move")
    frame.unlockLabel:Hide()

    frame.arrow = frame:CreateTexture(nil, "ARTWORK")
    frame.arrow:SetPoint("TOP", 0, -4)
    local okT, setT = pcall(frame.arrow.SetTexture, frame.arrow, OWN_TEX)
    if okT and setT ~= false then
        frame.arrow.__source = OWN_TEX                     -- test seam
    else
        local okA = frame.arrow.SetAtlas and pcall(frame.arrow.SetAtlas, frame.arrow, ATLAS)
        if not okA then frame.arrow:SetTexture(FALLBACK_TEX) end
        frame.arrow.__source = okA and ATLAS or FALLBACK_TEX
    end
    -- A rotated texture snapped to the pixel grid shimmers and blurs;
    -- both calls exist on this client (retail 8.x+), guarded anyway.
    if frame.arrow.SetSnapToPixelGrid then pcall(frame.arrow.SetSnapToPixelGrid, frame.arrow, false) end
    if frame.arrow.SetTexelSnappingBias then pcall(frame.arrow.SetTexelSnappingBias, frame.arrow, 0) end
    local r, g, b = T.Accent()
    frame.arrow:SetVertexColor(r, g, b, 1)

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(frame.text, 12, "OUTLINE")
    frame.text:SetPoint("TOP", frame.arrow, "BOTTOM", 0, -2)
    frame.text:SetText("")

    ns.RegisterMovable(frame, "arrowPos", function() return "TOP" end, RestorePosition)
    frame:SetScript("OnDragStart", function(self)
        if ns.db and ns.db.unlocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if ns.SnapMovable then ns.SnapMovable(self) end
        SavePosition()
    end)

    local acc = 0
    frame:SetScript("OnUpdate", function(_, dt)
        acc = acc + (dt or 0)
        if acc < TICK then return end
        acc = 0
        A.Tick()
    end)
    RestorePosition()
    return frame
end
A.Build = Build

--- The current step of the guide, or nil.
local function Step()
    local st = ns.Guide and ns.Guide.state
    if not (st and st.route and st.index) then return nil end
    return st.route.steps[st.index]
end

--- One update: rotate to the step, write the distance.
function A.Tick()
    if not frame then return end
    local step = Step()
    local bearing, dist = A.Bearing(step)
    if not bearing then
        if ns.db and ns.db.unlocked and not step then
            bearing, dist = 0.6, 42            -- a sample while placing the frame
        else
            frame.arrow:Hide()
            frame.text:SetText(step and "?" or "")
            return
        end
    end
    local rot = bearing - Facing()
    frame.arrow:Show()
    frame.arrow:SetRotation(rot)
    frame.text:SetText(("%d yd"):format(dist + 0.5))
    if step and step.k == "go" and dist <= ns.Guide.ARRIVE then
        local st = ns.Guide.state
        ns.Guide.MarkArrived(st.route, st.index)
    end
end

--- Show or hide with the settings; called from Apply and the guide.
function A.Refresh()
    Build()
    local unlocked = ns.db and ns.db.unlocked
    local size = Size()
    frame:SetSize(size + 8, size + 24)
    frame.arrow:SetSize(size, size)
    local r, g, b = ns.Theme.Accent()
    frame.arrow:SetVertexColor(r, g, b, 1)
    frame.unlockBg:SetShown(unlocked and true or false)
    frame.unlockLabel:SetShown(unlocked and true or false)
    if unlocked or (Enabled() and Step()) then
        frame:Show()
        A.Tick()
    else
        frame:Hide()
    end
end

ns.RegisterApply(function() A.Refresh() end, "Arrow")
