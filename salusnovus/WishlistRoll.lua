--[[ Salus Novus -- the wishlist on loot rolls.

When a roll starts for an item someone in the group wished for (you
included -- the reminder to roll Need), a strip hangs under the roll frame:
one line per wanter, you first, in class colour with their specs, BIS in
red. Nobody wants it: the roll frame is left alone.

The strip is our own frame parented to UIParent, never a child of
Blizzard's roll frame (EllesmereUI re-skins those, and their container is a
managed-layout frame that taints if touched). No hooks on Blizzard frames:
while a roll is open a light ticker re-finds the frames and follows them.
A roll whose frame can't be found still gets its strip, under the loot
container or at the top of the screen.
]]

local _, ns = ...

local R = {}
ns.WishlistRoll = R
local W = function() return ns.Wishlist end
local function T() return ns.Theme end

local LINE_H, PAD = 18, 6
local active = {}     -- [rollID] = time the roll can be forgotten
local strips = {}     -- [rollID] = strip frame
-- Rolls once seen on a frame: when that frame hides (you rolled) the roll
-- stays open until everyone has, and must NOT come back as a fallback strip.
local framedOnce = {}
R.strips, R.active = strips, active

local function Enabled() return ns.ModuleOn("qol") and true or false end

-- Every roll frame the client has: GroupLootFrame1..N and the container's pool.
local function RollFrames()
    local out, seen = {}, {}
    local c = rawget(_G, "GroupLootContainer")
    local n = (type(c) == "table" and ns.Num(c.maxIndex) and c.maxIndex) or 4
    if n < 4 then n = 4 end
    for i = 1, n do
        local f = rawget(_G, "GroupLootFrame" .. i)
        if type(f) == "table" and not seen[f] then seen[f] = true; out[#out + 1] = f end
    end
    if type(c) == "table" and type(c.rollFrames) == "table" then
        for _, f in pairs(c.rollFrames) do
            if type(f) == "table" and not seen[f] then seen[f] = true; out[#out + 1] = f end
        end
    end
    return out
end

local function ItemOf(rollID)
    local fn = rawget(_G, "GetLootRollItemLink")
    if not fn then return nil end
    local ok, link = pcall(fn, rollID)
    if not ok or ns.IsSecret(link) or type(link) ~= "string" then return nil end
    return tonumber(link:match("item:(%d+)"))
end

--- One wanter as a line: "You (Enhancement) BIS", "Cosmo (Restoration) Upgrade".
function R.Line(w)
    local UI = ns.WishlistUI
    local name = w.me and "You" or ((UI and UI.ClassName) and UI.ClassName(w.player, w.class) or w.player)
    local spec = (w.specs and #w.specs > 0) and (" |cff9b98a3(" .. table.concat(w.specs, "/") .. ")|r") or ""
    local tag = w.tag == "bis" and (" " .. ((UI and UI.BIS_RED) or "|cffff4040") .. "BIS|r")
        or (w.tag == "up" and " |cff9b98a3Upgrade|r" or "")
    return name .. spec .. tag
end

local function Strip(rollID)
    local s = strips[rollID]
    if s then return s end
    local Th = T()
    s = CreateFrame("Frame", nil, UIParent)
    s:SetFrameStrata("DIALOG")
    s.bg = Th.SolidTex(s, "BACKGROUND", Th.BG[1], Th.BG[2], Th.BG[3], 0.95)
    s.bg:SetAllPoints()
    s.border = ns.CreateBorder(s)
    s.border:Layout(s, 1, -1)
    s.border:SetColor(1, 1, 1, 0.10)
    s.border:Show()
    s.bar = Th.SolidTex(s, "ARTWORK", 1, 1, 1, 1)
    s.bar:SetWidth(3)
    s.bar:SetPoint("TOPLEFT", 0, 0)
    s.bar:SetPoint("BOTTOMLEFT", 0, 0)
    s.lines = {}
    s:Hide()
    strips[rollID] = s
    return s
end

local function Fill(s, wanters)
    local Th = T()
    local r, g, b = Th.Accent()
    s.bar:SetVertexColor(r, g, b, 1)
    for i, w in ipairs(wanters) do
        local l = s.lines[i]
        if not l then
            l = Th.MakeText(s, 13, Th.TEXT)
            l:SetJustifyH("LEFT")
            l:SetWordWrap(false)
            s.lines[i] = l
        end
        l:ClearAllPoints()
        l:SetPoint("TOPLEFT", s, "TOPLEFT", 3 + 8, -PAD - (i - 1) * LINE_H)
        l:SetPoint("RIGHT", s, "RIGHT", -8, 0)
        l:SetText(R.Line(w))
        l:Show()
    end
    for i = #wanters + 1, #s.lines do s.lines[i]:Hide() end
    s:SetHeight(PAD * 2 + #wanters * LINE_H - 2)
end

local function Shown(f)
    if f.IsForbidden and f:IsForbidden() == true then return false end
    local ok, on = pcall(f.IsShown, f)
    return ok and on and true or false
end

-- The roll's wanters, or nil when nobody wants it.
local function Wanted(rollID)
    local w = W().WantersOf(ItemOf(rollID))
    return #w > 0 and w or nil
end

--- Re-find every open roll and put (or take away) its strip.
function R.Sweep()
    local used = {}
    if Enabled() and W() then
        local now = GetTime and GetTime() or 0
        for id, untilT in pairs(active) do if untilT < now then active[id] = nil; framedOnce[id] = nil end end
        local framed = {}
        -- Rolls on screen: the strip hangs under their frame.
        for _, f in ipairs(RollFrames()) do
            local rollID = ns.Num(f.rollID) and f.rollID or nil
            if rollID and Shown(f) then
                framed[rollID] = true
                framedOnce[rollID] = true
                local wanters = Wanted(rollID)
                if wanters then
                    local s = Strip(rollID)
                    Fill(s, wanters)
                    s:ClearAllPoints()
                    s:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 0, -1)
                    s:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", 0, -1)
                    s:SetFrameLevel((f:GetFrameLevel() or 0) + 5)
                    s:Show()
                    used[rollID] = true
                end
            end
        end
        -- Rolls whose frame wasn't found: stacked under the container, or at the top.
        local n = 0
        for rollID in pairs(active) do
            if not framed[rollID] and not framedOnce[rollID] then
                local wanters = Wanted(rollID)
                if wanters then
                    local s = Strip(rollID)
                    Fill(s, wanters)
                    s:ClearAllPoints()
                    s:SetWidth(280)
                    local c = rawget(_G, "GroupLootContainer")
                    if type(c) == "table" and c.GetBottom and Shown(c) then
                        s:SetPoint("TOP", c, "BOTTOM", 0, -4 - n * 70)
                    else
                        s:SetPoint("TOP", UIParent, "TOP", 0, -160 - n * 70)
                    end
                    s:Show()
                    used[rollID] = true
                    n = n + 1
                end
            end
        end
    end
    for rollID, s in pairs(strips) do if not used[rollID] then s:Hide() end end
    R.ticker:SetShown(next(active) ~= nil or next(used) ~= nil)
    return used
end

-- While a roll is open, follow the frames (they're pooled and re-laid out).
R.ticker = CreateFrame("Frame")
R.ticker:Hide()
local acc = 0
R.ticker:SetScript("OnUpdate", function(_, dt)
    acc = acc + (dt or 0)
    if acc < 0.25 then return end
    acc = 0
    R.Sweep()
end)

local function Soon()
    if C_Timer and C_Timer.After then C_Timer.After(0, R.Sweep) else R.Sweep() end
end

ns.On("START_LOOT_ROLL", function(rollID, rollTime)
    if not ns.Num(rollID) then return end
    local secs = ns.Num(rollTime) and rollTime / 1000 or 60
    active[rollID] = (GetTime and GetTime() or 0) + secs + 2
    Soon()
end)
ns.On("CANCEL_LOOT_ROLL", function(rollID)
    if ns.Num(rollID) then active[rollID] = nil; framedOnce[rollID] = nil end
    Soon()
end)
