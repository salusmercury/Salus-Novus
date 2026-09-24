--------------------------------------------------------------------------------
-- A mock WoW client, enough of one to LOAD and RUN MerkUI outside the game.
--
-- Why this exists: this machine has no WoW and Alex cannot hand-QA a thousand
-- lines of change. lua_check.py proves a file PARSES; this proves it RUNS --
-- nil globals, load-order mistakes, bad arithmetic on a nil, a comparison
-- against a secret value, an anchor that lands in the wrong place.
--
-- What it deliberately does NOT do: render anything, or claim that something
-- LOOKS right. A frame here is a recorder, not a widget. Anything about
-- appearance still needs eyes in the client.
--
-- Design notes:
--   * Frames answer any unknown method with a no-op that returns the frame,
--     so the addon can call the long tail of Blizzard widget API without this
--     file having to enumerate it. Methods the tests actually reason about
--     (points, size, text, scripts, shown) are real.
--   * GetTime() and C_Timer run off a VIRTUAL clock. Tests advance it, so a
--     30-second countdown takes no wall time and never races.
--   * issecretvalue() is real: W.secret(v) wraps a value, and touching it the
--     way 12.1 forbids (compare, concat, format, table key) throws, exactly
--     like the live client.
--------------------------------------------------------------------------------

W = {}                       -- the harness's own namespace, visible to tests

--------------------------------------------------------------------------------
-- Virtual clock
--------------------------------------------------------------------------------
local now = 10000.0          -- not 0: code that treats 0 as "unset" would lie
local timers = {}            -- { at, fn, cancelled, ticker, interval }

function GetTime() return now end
function time() return 1757600000 + math.floor(now) end
function GetServerTime() return time() end
function date(fmt, t) return "12:00:00" end
function debugprofilestop() return now * 1000 end

-- Advance the clock, firing every timer due along the way. Fires in time
-- order, and re-checks after each callback so a timer that schedules another
-- timer inside the same window still runs.
-- OnUpdate scripts are driven too, in FRAME_STEP slices. Several features
-- live entirely in an OnUpdate -- the reminder countdown and its spoken line,
-- the relay's fades, the lane cursor -- so without this any test of them
-- passes vacuously no matter what the code does. That is exactly how a
-- reminder-retraction test came out green against code that had no
-- retraction in it at all.
local FRAME_STEP = 0.05

-- The client runs OnUpdate only on VISIBLE frames, and visibility is the
-- whole parent chain, not this frame's own Shown flag: a shown child of a
-- hidden parent gets nothing. Driving it here made countdowns and fades run
-- in the harness that are frozen in game.
local function isVisible(f)
    if not f.__shown then return false end
    local p = f.__parent
    while p do
        if not p.__shown then return false end
        p = p.__parent
    end
    return true
end

-- Forward declaration: animation groups are defined with the frame methods,
-- far below, but W.advance has to drive them. A `local function` down there
-- would be invisible here and W.advance would silently call a nil global.
local runAnims

local function runOnUpdates(dt)
    for _, f in ipairs(W.frames) do
        local h = f.__scripts and f.__scripts.OnUpdate
        if h and isVisible(f) then
            local ok, err = pcall(h, f, dt)
            if not ok then
                W.errors[#W.errors + 1] = "OnUpdate: " .. tostring(err)
            end
        end
    end
end

local function fireDue(target)
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 10000 then error("timer storm: 10000 callbacks in one advance") end
        local nextAt, nextIdx
        for i, t in ipairs(timers) do
            if not t.cancelled and t.at <= target then
                if nextAt == nil or t.at < nextAt then nextAt, nextIdx = t.at, i end
            end
        end
        if not nextIdx then return end
        local t = timers[nextIdx]
        now = t.at
        if t.ticker then
            t.at = t.at + t.interval
        else
            t.cancelled = true
        end
        local ok, err = pcall(t.fn)
        if not ok then
            W.errors[#W.errors + 1] = "timer callback: " .. tostring(err)
        end
    end
end

-- `elapsed` is the time since the LAST OnUpdate pass, not the time since the
-- last timer fired. The old `stop - now` measured the latter, so every timer
-- that landed mid-slice stole that much from the frame's elapsed: 2.0s of
-- clock arrived as 1.43s of `elapsed` with twenty timers in flight, and any
-- OnUpdate that accumulates `elapsed` (the relay's reflow ease, BossQueue's
-- pulse) ran slow against a GetTime() that did not.
local advancing = false
function W.advance(seconds)
    -- Re-entering (a W.advance inside an OnUpdate or a timer callback) used
    -- to SILENTLY lose the inner advance: the outer loop's `now = stop`
    -- overwrote the clock the inner one had moved, so 0.2 + 1.0 came out as
    -- 0.2 and every assertion after it read a clock that never ran.
    if advancing then error("W.advance re-entered from inside a callback", 2) end
    advancing = true
    local okAdv, errAdv = pcall(function()
    local target = now + seconds
    local last = now
    while now < target do
        local stop = math.min(now + FRAME_STEP, target)
        fireDue(stop)
        now = stop
        local dt = now - last
        last = now
        if dt > 0 then
            if runAnims then runAnims() end
            runOnUpdates(dt)
        end
    end
    fireDue(target)
    now = target
    if runAnims then runAnims() end
    end)
    advancing = false
    if not okAdv then error(errAdv, 0) end
end

-- Advance with NO OnUpdate driving, for the rare test that wants only timers.
function W.advanceTimersOnly(seconds)
    local target = now + seconds
    fireDue(target)
    now = target
end

function W.pendingTimers()
    local n = 0
    for _, t in ipairs(timers) do if not t.cancelled then n = n + 1 end end
    return n
end

local function newTimer(delay, fn, ticker, interval)
    local t = { at = now + delay, fn = fn, ticker = ticker, interval = interval }
    timers[#timers + 1] = t
    local handle = {}
    function handle:Cancel() t.cancelled = true end
    function handle:IsCancelled() return t.cancelled end
    return handle
end

C_Timer = {
    After = function(delay, fn) newTimer(delay, fn, false) end,
    NewTimer = function(delay, fn) return newTimer(delay, fn, false) end,
    NewTicker = function(interval, fn) return newTimer(interval, fn, true, interval) end,
}

--------------------------------------------------------------------------------
-- Secret values (12.1). Touching one the forbidden way throws, as in the client.
--------------------------------------------------------------------------------
local SECRET = {}
SECRET.__index = SECRET
local function boom() error("attempted to use a secret value", 2) end
SECRET.__eq, SECRET.__lt, SECRET.__le = boom, boom, boom
SECRET.__concat, SECRET.__add, SECRET.__sub = boom, boom, boom
SECRET.__mul, SECRET.__div, SECRET.__len = boom, boom, boom
SECRET.__mod, SECRET.__pow, SECRET.__unm = boom, boom, boom
-- tostring() on a secret THROWS in the client (see MerkUI landmine notes in
-- Timers.lua OnStartBreak). Returning "<secret>" let every `or tostring(x)`
-- fallback pass here and crash in game.
SECRET.__tostring = boom
--
-- Two things this CANNOT model, and every secret test has to be read knowing
-- them:
--   * `secret == "text"` does NOT throw. Lua 5.1 only calls __eq when both
--     operands are tables sharing the handler, so the single commonest
--     misuse -- comparing a secret against a string or number -- is silent.
--   * `t[secret] = 1` does NOT throw. A metatable cannot trap table-key use.
-- And `type(secret)` is "table" here, where the client reports the value's
-- underlying type. Every MerkUI guard is written `type(x) == "string" and
-- not issecretvalue(x)`, and the type half alone rejects these stand-ins, so
-- a test using W.secret proves the TYPE check fires -- never the
-- issecretvalue() check.

function W.secret(v)
    return setmetatable({ __v = v }, SECRET)
end

-- The OTHER half of the model, and the one that tests the real guard.
-- W.secret is a table, so `type(x) == "string"` rejects it before
-- issecretvalue is ever consulted -- which means a test using it proves the
-- TYPE check fires and nothing more. These are genuine Lua strings/numbers
-- that issecretvalue() reports as secret, so the value sails through every
-- type check and ONLY the issecretvalue guard can stop it. Use these to test
-- that the guard exists and is correctly ordered; use W.secret to test that
-- misusing a secret is fatal.
--
-- HAZARD, and it is not small: Lua interns strings and numbers ARE their own
-- identity, so `secretValues` is keyed by VALUE, not by object. Marking a
-- value secret marks EVERY occurrence of that value anywhere in the state,
-- for the rest of the test. The old defaults made this a trap: W.secretNumber()
-- defaulted to 30, and 30 is the duration in nearly every bar the suite starts
-- -- so one call to it silently turned every ordinary 30-second timer into a
-- secret, and OnStartBar's `issecretvalue(time)` guard threw them all away.
-- The test that called it would have gone green for the wrong reason and taken
-- unrelated tests with it.
--
-- So: no defaults that could collide with real data. Each call mints a value
-- no ordinary code path produces, and a caller who passes an explicit value
-- is trusted to have picked one nothing else in that test uses.
local secretValues = {}
local secretSeq = 0
function W.secretString(s)
    if s == nil then
        secretSeq = secretSeq + 1
        s = "\1MerkUISecret#" .. secretSeq      -- cannot collide with a spell name
    end
    secretValues[s] = true
    return s
end
function W.secretNumber(n)
    if n == nil then
        secretSeq = secretSeq + 1
        -- A fractional, implausible magnitude: no bar duration, spell id,
        -- stage number or encounter id in this addon is ever near it.
        n = -987654.321 - secretSeq
    end
    secretValues[n] = true
    return n
end
-- Un-mark a value, for a test that has to hand the same literal back clean.
function W.unsecret(v) secretValues[v] = nil end

-- ...and the half of the model that was MISSING, which is why a confirmed
-- crash could not be reproduced here. In the client, formatting a secret
-- THROWS -- that is the whole failure mode (landmines 1 and 19). The mock's
-- secretString is a genuine Lua string, so string.format was perfectly
-- happy with it and a handler that formatted BigWigs bar text looked fine.
-- Measured 2026-09-12: the relay's always-on event log did exactly that and
-- killed the countdown display for a whole pull; the suite saw nothing.
--
-- Only string.format is intercepted. `..` on two strings never consults a
-- metamethod in 5.1, so concat cannot be modelled this way; guards that
-- concat a secret still need W.secret (the table) to prove fatality.
local rawFormat = string.format
function string.format(fmt, ...)
    if secretValues[fmt] then
        error("attempt to use a secret value in string.format", 2)
    end
    for i = 1, select("#", ...) do
        if secretValues[(select(i, ...))] then
            error("attempt to use a secret value in string.format", 2)
        end
    end
    return rawFormat(fmt, ...)
end
function issecretvalue(v)
    if type(v) == "table" and getmetatable(v) == SECRET then return true end
    return secretValues[v] == true
end

--------------------------------------------------------------------------------
-- Output capture
--------------------------------------------------------------------------------
W.printed = {}
W.errors = {}
W.anchorCycles = {}          -- SetPoint calls that would close an anchor loop
function print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    W.printed[#W.printed + 1] = table.concat(parts, " ")
end
function W.clearOutput() W.printed, W.errors, W.anchorCycles = {}, {}, {} end
function W.printedMatching(pat)
    local out = {}
    for _, line in ipairs(W.printed) do if line:find(pat, 1, true) then out[#out + 1] = line end end
    return out
end

--------------------------------------------------------------------------------
-- Frames
--------------------------------------------------------------------------------
local frameCount = 0
W.frames = {}

-- Resolve a frame's screen rect from its points. Only the cases the addon
-- actually uses: a single point against a parent, or TOPLEFT+BOTTOMRIGHT.
-- Each point pins ONE named spot of this frame to a spot on another, and the
-- two axes are independent: "LEFT" constrains x and leaves y centred. Width
-- is derived only when BOTH a left and a right edge are pinned; otherwise it
-- comes from SetWidth, and likewise for height. The old version special-cased
-- "exactly two points" as a corner-to-corner stretch and took the bounding
-- box of the two anchors, which gave a LEFT+RIGHT stretch bar zero height
-- (GetTop() == GetBottom() while GetHeight() still said 20), ignored the
-- third point of a three-point layout entirely, and skipped the scale
-- conversion the single-point branch does.
-- A FontString that was never given an explicit width measures its TEXT in
-- the client -- GetWidth() == GetStringWidth(). Here it used to be 0, which
-- made W.textOverflow() return 0 for every unsized FontString (its
-- `if have <= 0 then return 0 end` guard), i.e. for the normal case: the one
-- function in the layout layer whose whole job is "does this text fit" could
-- not answer yes or no for anything. It also put every label's rect at zero
-- width, so nothing anchored to a label's RIGHT edge landed where it will.
local function naturalW(f)
    if f.__type == "FontString" and (f.__w or 0) == 0 then
        return #(f.__text or "") * 6
    end
    return f.__w or 0
end
local function naturalH(f)
    if f.__type == "FontString" and (f.__h or 0) == 0 then
        return (f.__text and f.__text ~= "" and 12) or 0        -- "" has no height, as in the client
    end
    return f.__h or 0
end

local function resolveRect(f)
    if f.__rect then return f.__rect end
    if #f.__points == 0 then return nil end
    if f.__resolving then return nil end       -- an anchor cycle, not a stack overflow
    f.__resolving = true
    local w, h = naturalW(f), naturalH(f)
    -- A frame's own coordinates are in ITS effective scale while the anchor
    -- target's are in the target's; the client converts between them, and
    -- landmine 17 is entirely about that conversion.
    local selfScale = f:GetEffectiveScale() or 1
    local xs, ys = {}, {}
    for _, pt in ipairs(f.__points) do
        local rx, ry = W.pointOn(pt.rel, pt.relPoint)
        if rx then
            local relScale = (pt.rel and pt.rel.GetEffectiveScale) and pt.rel:GetEffectiveScale() or 1
            if selfScale ~= 0 and relScale ~= selfScale then
                rx, ry = rx * relScale / selfScale, ry * relScale / selfScale
            end
            local x, y = rx + (pt.x or 0), ry + (pt.y or 0)
            local p = pt.point
            -- FIRST-wins on the IMPLIED centre, last-wins on a named edge.
            -- "TOP" names no x edge so it lands in xs.C -- correct, the
            -- client's TOP does pin centre-x. But a following "BOTTOM" then
            -- OVERWROTE it with its own anchor's centre-x, so 112px of
            -- horizontal position was decided by the order the two SetPoint
            -- calls happened to be written in. Not a client behaviour, a
            -- modelling error: it made every Boss Visualizer phase line
            -- resolve to the SAME x, fabricating a collision on a clean
            -- difficulty while hiding the real one. A named edge still wins
            -- downstream, where `if xs.L ... elseif xs.C` prefers it.
            if p:find("LEFT") then xs.L = x
            elseif p:find("RIGHT") then xs.R = x
            elseif xs.C == nil then xs.C = x end
            if p:find("BOTTOM") then ys.B = y
            elseif p:find("TOP") then ys.T = y
            elseif ys.C == nil then ys.C = y end
        end
    end
    f.__resolving = nil
    local left, width
    if xs.L and xs.R then left, width = xs.L, xs.R - xs.L
    elseif xs.L then left, width = xs.L, w
    elseif xs.R then left, width = xs.R - w, w
    elseif xs.C then left, width = xs.C - w / 2, w
    else return nil end
    local bottom, height
    if ys.B and ys.T then bottom, height = ys.B, ys.T - ys.B
    elseif ys.B then bottom, height = ys.B, h
    elseif ys.T then bottom, height = ys.T - h, h
    elseif ys.C then bottom, height = ys.C - h / 2, h
    else return nil end
    return { left = left, bottom = bottom, width = width, height = height }
end

-- Coordinates of a named point on a frame.
function W.pointOn(frame, point)
    if not frame then return nil end
    local r = resolveRect(frame)
    if not r then return nil end
    local x
    if point:find("LEFT") then x = r.left
    elseif point:find("RIGHT") then x = r.left + r.width
    else x = r.left + r.width / 2 end
    local y
    if point:find("BOTTOM") then y = r.bottom
    elseif point:find("TOP") then y = r.bottom + r.height
    else y = r.bottom + r.height / 2 end
    return x, y
end

local FrameMT = {}

local function makeFrame(ftype, name, parent)
    frameCount = frameCount + 1
    local f = {
        __type = ftype or "Frame", __name = name, __parent = parent,
        __points = {}, __scripts = {}, __events = {}, __shown = true,
        __w = 0, __h = 0, __scale = 1, __alpha = 1, __strata = "MEDIUM",
        __level = (parent and (parent.__level or 1) + 1) or 1,
        __children = {}, __regions = {}, __id = frameCount,
    }
    setmetatable(f, FrameMT)
    if parent then parent.__children[#parent.__children + 1] = f end
    if name then _G[name] = f end
    W.frames[#W.frames + 1] = f
    return f
end

local methods = {}

function methods:SetPoint(point, rel, relPoint, x, y)
    -- SetPoint(point) / (point, x, y) / (point, rel, x, y) / (point, rel, relPoint, x, y)
    if type(rel) == "number" then
        x, y, rel, relPoint = rel, relPoint, self.__parent, point
    elseif type(relPoint) == "number" then
        -- (point, relativeTo, x, y): a legal client form that used to reach
        -- W.pointOn with a NUMBER for the point name and throw there.
        x, y, relPoint = relPoint, x, point
    elseif rel ~= nil and relPoint == nil then
        relPoint = point
    elseif rel == nil then
        rel, relPoint = self.__parent, point
    end
    if type(rel) == "string" then rel = _G[rel] end
    -- replace a point of the same name, like the client does
    for i, p in ipairs(self.__points) do
        if p.point == point then table.remove(self.__points, i) break end
    end
    local target = rel or UIParent
    -- ANCHOR CYCLES. The client refuses these outright ("Cannot anchor to a
    -- region dependent on it") and throws; the mock happily stored them, so a
    -- cycle built during BuildPanel was invisible here and only showed up as
    -- a lua error in game. That is exactly how a centred options-card header
    -- shipped broken on 2026-09-12: row -> label -> card -> row.
    --
    -- Recorded rather than thrown. The client's test is per-axis, so a naive
    -- reachability walk is STRICTER than the real thing (A left-of B while B
    -- sits above A is legal and would be flagged here). Throwing on that
    -- would turn a false positive into a red suite; a list a test can assert
    -- on keeps the signal without the blast radius.
    if target ~= self then
        local seen, stack = {}, { target }
        while #stack > 0 do
            local f = table.remove(stack)
            if f == self then
                W.anchorCycles[#W.anchorCycles + 1] = {
                    frame = self, point = point, rel = target, relPoint = relPoint,
                }
                break
            end
            if not seen[f] and type(f) == "table" and f.__points then
                seen[f] = true
                for _, pp in ipairs(f.__points) do
                    if pp.rel then stack[#stack + 1] = pp.rel end
                end
            end
        end
    end
    self.__points[#self.__points + 1] = {
        point = point, rel = target, relPoint = relPoint or point,
        x = tonumber(x) or 0, y = tonumber(y) or 0,
    }
    self.__rect = nil
    return self
end
function methods:ClearAllPoints() self.__points, self.__rect = {}, nil; return self end
function methods:SetAllPoints(other)
    other = other or self.__parent
    self:ClearAllPoints()
    self:SetPoint("TOPLEFT", other, "TOPLEFT", 0, 0)
    self:SetPoint("BOTTOMRIGHT", other, "BOTTOMRIGHT", 0, 0)
    return self
end
function methods:GetNumPoints() return #self.__points end
function methods:GetPoint(i)
    local p = self.__points[i or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
end
function methods:SetSize(w, h) self.__w, self.__h, self.__rect = w, h, nil; return self end
function methods:SetWidth(w) self.__w, self.__rect = w, nil; return self end
function methods:SetHeight(h) self.__h, self.__rect = h, nil; return self end
-- Points win over SetSize when they actually span the axis, as in the client:
-- SetSize(999,999) then SetAllPoints(a 100x50) is 100x50, and GetWidth() used
-- to say 999 while GetRight()-GetLeft() said 100.
function methods:GetWidth()
    local r = resolveRect(self)
    if r then return r.width end
    return naturalW(self)
end
function methods:GetHeight()
    local r = resolveRect(self)
    if r then return r.height end
    return naturalH(self)
end
function methods:GetSize() return self:GetWidth(), self:GetHeight() end
function methods:GetLeft() local r = resolveRect(self); return r and r.left end
function methods:GetBottom() local r = resolveRect(self); return r and r.bottom end
function methods:GetRight() local r = resolveRect(self); return r and (r.left + r.width) end
function methods:GetTop() local r = resolveRect(self); return r and (r.bottom + r.height) end
function methods:GetCenter()
    local r = resolveRect(self)
    if not r then return nil end
    return r.left + r.width / 2, r.bottom + r.height / 2
end

function methods:SetScale(s) self.__scale = s; return self end
function methods:GetScale() return self.__scale or 1 end
function methods:GetEffectiveScale()
    local s = self.__scale or 1
    local p = self.__parent
    while p do s = s * (p.__scale or 1); p = p.__parent end
    return s
end
function methods:SetParent(p) self.__parent = p; self.__rect = nil; return self end
function methods:GetParent() return self.__parent end
-- The client fires OnShow/OnHide only on a CHANGE: Show() on an already-shown
-- frame runs nothing. Firing them unconditionally made every OnShow/OnHide
-- ordering question (which page mutes the preview channel last) answerable
-- here in a way the client would not reproduce.
function methods:Show()
    if self.__shown then return end
    self.__shown = true
    local h = self.__scripts.OnShow; if h then pcall(h, self) end
end
function methods:Hide()
    if not self.__shown then return end
    self.__shown = false
    local h = self.__scripts.OnHide; if h then pcall(h, self) end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() return self.__shown and true or false end
function methods:IsVisible()
    if not self.__shown then return false end
    local p = self.__parent
    while p do if not p.__shown then return false end; p = p.__parent end
    return true
end
function methods:SetAlpha(a) self.__alpha = a end
function methods:GetAlpha() return self.__alpha or 1 end
function methods:SetFrameStrata(s) self.__strata = s end
function methods:GetFrameStrata() return self.__strata end
function methods:SetFrameLevel(l) self.__level = l end
function methods:GetFrameLevel() return self.__level or 1 end

function methods:SetScript(k, fn) self.__scripts[k] = fn; return self end
function methods:GetScript(k) return self.__scripts[k] end
function methods:HookScript(k, fn)
    local prev = self.__scripts[k]
    self.__scripts[k] = function(...)
        if prev then prev(...) end
        return fn(...)
    end
end
function methods:RegisterEvent(e) self.__events[e] = true; return true end
function methods:UnregisterEvent(e) self.__events[e] = nil end
function methods:UnregisterAllEvents() self.__events = {} end
function methods:IsEventRegistered(e) return self.__events[e] and true or false end

-- Text
function methods:SetText(t) self.__text = t; return self end
function methods:GetText() return self.__text end
function methods:SetFont(path, size, flags)
    -- The real thing returns FALSE for a bad path; it does not error, and it
    -- does not clear the previous font. Landmine 23.
    -- The client takes .ttf, .ttc AND .otf; LibSharedMedia ships plenty of
    -- .otf, so rejecting it here sent a perfectly good path to the fallback.
    -- Still a weaker model than the client in the direction that matters: a
    -- path that ENDS .ttf but names no file returns true here and false in
    -- game, which is exactly the shape a bad `font.path` off a shared
    -- settings string takes. The realistic landmine-23 case is untestable.
    if type(path) ~= "string" or path == ""
        or not (path:find("%.[Tt][Tt][FfCc]") or path:find("%.[Oo][Tt][Ff]")) then
        return false
    end
    self.__font, self.__fontSize, self.__fontFlags = path, size, flags
    return true
end
-- SetScrollChild was never implemented, so it fell through to
-- W.unknownMethods and the scroll child kept ZERO points -- making it and
-- every descendant unresolvable. Measured: 533 of 650 visible frames in the
-- Boss Visualizer, 313 in the Codex, 158 in Options. Every lane, cast mark,
-- ability row and options widget lives in a scroll area, so the layout layer
-- was answering nil for most of the UI while looking like it worked
-- (W.anchors drops a nil rect rather than complaining, and layout_map.py
-- only draws anchors, which are not in scroll frames).
--
-- CAVEAT for anything sweeping the interior: there is still no CLIPPING
-- model, so content scrolled out of view now reads as real geometry. A sweep
-- must intersect each rect with its nearest ScrollFrame ancestor before
-- believing an overlap or an off-screen result.
function methods:SetScrollChild(child)
    self.__scrollChild = child
    if child then
        child:SetParent(self)
        child:ClearAllPoints()
        child:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
    end
    return self
end
function methods:GetScrollChild() return self.__scrollChild end

function methods:GetFont() return self.__font, self.__fontSize, self.__fontFlags end
function methods:GetStringWidth()
    -- Deterministic stand-in: ~6px per character. Enough to test that a
    -- measurement HAPPENS and is re-taken, not what it renders as.
    return #(self.__text or "") * 6
end
function methods:GetStringHeight() return 12 end
function methods:SetHitRectInsets(l, r, t, b) self.__hit = { l, r, t, b } end
function methods:GetHitRectInsets()
    local h = self.__hit or { 0, 0, 0, 0 }
    return h[1], h[2], h[3], h[4]
end

-- Region factories
function methods:CreateTexture(name, layer, template, sublevel)
    local t = makeFrame("Texture", name, self)
    t.__layer, t.__sublevel = layer, sublevel or 0
    self.__regions[#self.__regions + 1] = t
    return t
end
function methods:CreateFontString(name, layer, template)
    local fs = makeFrame("FontString", name, self)
    fs.__layer = layer
    self.__regions[#self.__regions + 1] = fs
    return fs
end
function methods:CreateMaskTexture(name, layer)
    return makeFrame("MaskTexture", name, self)
end
-- Animation groups run on the VIRTUAL CLOCK, like everything else here.
--
-- They used not to. Play() set a flag and the comment said "tests call
-- W.finishAnim" -- a function that did not exist. So OnFinished never fired
-- for anything, and OnFinished is where Messages.lua and BigWigsRelay.lua
-- return a frame to the pool (`f.anim:SetScript("OnFinished", function()
-- Retire(f) end)`). Every message ever shown stayed in `active` forever in
-- the harness, so the whole pooling/retire path -- and any test of leaks,
-- of the max-messages cap, or of a fade completing -- was vacuous.
W.animGroups = {}

function methods:CreateAnimationGroup()
    local g = makeFrame("AnimationGroup", nil, self)
    g.__playing = false
    g.__anims = {}
    function g:CreateAnimation(kind)
        local a = makeFrame("Animation", nil, g)
        a.__kind, a.__duration, a.__startDelay = kind, 0, 0
        function a:SetDuration(d) self.__duration = tonumber(d) or 0; return self end
        function a:GetDuration() return self.__duration or 0 end
        function a:SetStartDelay(d) self.__startDelay = tonumber(d) or 0; return self end
        function a:GetStartDelay() return self.__startDelay or 0 end
        g.__anims[#g.__anims + 1] = a
        return a
    end
    -- Total run time = the latest (startDelay + duration) of its children,
    -- which is what the client's OnFinished waits for.
    function g:__span()
        local span = 0
        for _, a in ipairs(self.__anims) do
            local t = (a.__startDelay or 0) + (a.__duration or 0)
            if t > span then span = t end
        end
        return span
    end
    function g:Play()
        self.__playing = true
        self.__finishAt = now + self:__span()
        W.animGroups[self] = true
    end
    function g:Stop()
        -- The client fires OnStop only on a group that was actually PLAYING;
        -- Stop() on an idle group runs nothing. Messages.lua calls
        -- `f.anim:Stop()` unconditionally before every Play(), so firing it
        -- regardless made OnStop look reachable on a path the client never
        -- takes.
        if not self.__playing then return end
        self.__playing = false
        self.__finishAt = nil
        W.animGroups[self] = nil
        local h = self.__scripts.OnStop
        if h then pcall(h, self) end
    end
    function g:IsPlaying() return self.__playing and true or false end
    return g
end

-- Fire OnFinished for every group whose span has elapsed. Driven by
-- W.advance, so a 0.4s fade with a 2.5s hold retires its frame 2.9s later
-- without any test having to know that.
runAnims = function()
    local due = {}
    for g in pairs(W.animGroups) do
        if g.__playing and g.__finishAt and g.__finishAt <= now then due[#due + 1] = g end
    end
    -- Deterministic order: pairs over a table keyed by frames is not.
    table.sort(due, function(a, b)
        if a.__finishAt ~= b.__finishAt then return a.__finishAt < b.__finishAt end
        return (a.__id or 0) < (b.__id or 0)
    end)
    for _, g in ipairs(due) do
        g.__playing = false
        g.__finishAt = nil
        W.animGroups[g] = nil
        local h = g.__scripts.OnFinished
        if h then
            local okA, err = pcall(h, g, false)   -- (self, requested) as in the client
            if not okA then W.errors[#W.errors + 1] = "OnFinished: " .. tostring(err) end
        end
    end
end

-- Finish a group NOW, for a test that does not want to wait out its span.
function W.finishAnim(g)
    if not g or not g.__playing then return false end
    g.__playing = false
    g.__finishAt = nil
    W.animGroups[g] = nil
    local h = g.__scripts.OnFinished
    if h then
        local okA, err = pcall(h, g, false)
        if not okA then W.errors[#W.errors + 1] = "OnFinished: " .. tostring(err) end
    end
    return true
end
function methods:GetRegions() return unpack(self.__regions) end
function methods:GetChildren() return unpack(self.__children) end
function methods:GetNumChildren() return #self.__children end
function methods:GetObjectType() return self.__type end
function methods:GetName() return self.__name end
function methods:GetLayer() return self.__layer end
function methods:GetDrawLayer() return self.__layer, self.__sublevel end
function methods:SetEnabled(v) self.__enabled = v and true or false end
function methods:Enable() self.__enabled = true end
function methods:Disable() self.__enabled = false end
function methods:IsEnabled()
    if self.__enabled == nil then return true end
    return self.__enabled
end
-- The client clamps a StatusBar/Slider value to its range. A secret passes
-- through untouched (the client draws it; Lua cannot compare it), and so
-- does anything before a range is set.
local function clampValue(self, v)
    if type(v) ~= "number" or issecretvalue(v) then return v end
    local lo, hi = self.__min, self.__max
    if type(lo) ~= "number" or type(hi) ~= "number" or issecretvalue(lo) or issecretvalue(hi) then return v end
    if v < lo then return lo elseif v > hi then return hi end
    return v
end
function methods:SetValue(v)
    v = clampValue(self, v)
    self.__value = v
    local h = self.__scripts.OnValueChanged
    if h then pcall(h, self, v) end
end
function methods:GetValue() return self.__value or 0 end
function methods:SetMinMaxValues(a, b)
    self.__min, self.__max = a, b
    if self.__value ~= nil then self.__value = clampValue(self, self.__value) end
end
function methods:GetMinMaxValues() return self.__min or 0, self.__max or 0 end
function methods:GetThumbTexture()
    self.__thumb = self.__thumb or makeFrame("Texture", nil, self)
    return self.__thumb
end
function methods:GetChecked() return self.__checked and true or false end
function methods:SetChecked(v) self.__checked = v and true or false end

-- EditBox focus: one box holds it at a time. SetFocus on another box takes
-- it (the old one gets OnEditFocusLost); ClearFocus only fires on the box
-- that has it. Before this, HasFocus fell to the no-op stub and returned
-- the frame -- always truthy -- and ClearFocus fired nothing.
local focused
local function fireFocus(box, k)
    local h = box.__scripts[k]; if h then pcall(h, box) end
end
function methods:SetFocus()
    if focused == self then return end
    local old = focused
    focused = self
    if old then fireFocus(old, "OnEditFocusLost") end
    fireFocus(self, "OnEditFocusGained")
end
function methods:ClearFocus()
    if focused ~= self then return end
    focused = nil
    fireFocus(self, "OnEditFocusLost")
end
function methods:HasFocus() return focused == self end

-- Fire a frame's registered handler for an event, the way the client does.
function methods:__fire(event, ...)
    if not self.__events[event] then return false end
    local h = self.__scripts.OnEvent
    if not h then return false end
    local ok, err = pcall(h, self, event, ...)
    if not ok then W.errors[#W.errors + 1] = event .. ": " .. tostring(err) end
    return true
end

-- Anything not defined above is a no-op returning the frame. This is what
-- keeps the mock small: the addon calls a long tail of widget API whose
-- behaviour no test reasons about.
--
-- It hides two things, and neither is small:
--   * a TYPO or a renamed Blizzard method succeeds here and hard-errors in
--     game -- `f:SetPointt("CENTER")` returns the frame without complaint --
--     so every "did not throw" test (01 load, 12 slash, 13 windows) is blind
--     to the commonest widget mistake there is;
--   * the no-op returns the FRAME, which is TRUTHY, so `f:IsObjectType(...)`,
--     `f:HasFocus()`, `f:IsForbidden()` and friends always take the yes
--     branch, and `f:GetVerticalScroll()` hands arithmetic a table.
-- W.unknownMethods is the lever: every name that fell through lands here, so
-- a reviewer (or a test) can read the list and spot the misspelling.
W.unknownMethods = {}
-- Capitalized keys the ADDON stores on a frame as data or optional
-- callbacks. Reading one that was never assigned must answer nil, not a
-- truthy noop.
W.dataKeys = {
    EnabledWhen = true, Update = true, SetEnabledState = true,
    SetLabelEnabled = true,
}
-- NOT Pause/Resume/Refresh: those ARE real widget API (Cooldown:Pause,
-- Cooldown:Resume), and Rings.lua calls them on a live Cooldown.
local noop = function(self) return self end
FrameMT.__index = function(t, k)
    local m = methods[k]
    if m then return m end
    if type(k) == "string" and k:match("^%u") then
        -- The blanket version made every capitalized field truthy, so
        -- Options' `if w.EnabledWhen and w.SetEnabledState` fired for EVERY
        -- control and each got SetEnabledState(noop()) == nil: the whole
        -- panel read as disabled, and any test asserting a greyed-out
        -- control passed for the wrong reason.
        if W.dataKeys[k] then return nil end
        W.unknownMethods[k] = (W.unknownMethods[k] or 0) + 1
        rawset(t, k, noop)
        return noop
    end
    return nil
end

function CreateFrame(ftype, name, parent, template, id)
    return makeFrame(ftype, name, parent)
end

-- Broadcast an event to every frame that registered it.
function W.fireEvent(event, ...)
    local hit = 0
    for _, f in ipairs(W.frames) do
        if f.__events and f.__events[event] then
            if f:__fire(event, ...) then hit = hit + 1 end
        end
    end
    return hit
end

--------------------------------------------------------------------------------
-- Globals the addon reads
--------------------------------------------------------------------------------
_G = _G or getfenv(0)
UIParent = makeFrame("Frame", "UIParent", nil)
UIParent.__w, UIParent.__h = 1365.33, 768
UIParent.__rect = { left = 0, bottom = 0, width = 1365.33, height = 768 }

UIErrorsFrame = makeFrame("Frame", "UIErrorsFrame", UIParent)
UISpecialFrames = {}

-- Lua 5.1 HAS a global `unpack`; do not shadow it with a broken wrapper.
-- The previous definition fell through to a nonexistent `_unpack`, so every
-- call through hooksecurefunc below threw and no hooked path was testable.
if not unpack and table.unpack then unpack = table.unpack end

function wipe(t) for k in pairs(t) do t[k] = nil end return t end
-- Lua 5.1's gmatch on "[^|]*" yields an EXTRA empty capture after every
-- match, so the old version turned "a|b" into four values ("a","","b","")
-- instead of two. Anything written against it would have been tested against
-- a splitter the client does not have.
function strsplit(sep, s)
    s = tostring(s)
    local class = "[" .. tostring(sep):gsub("(%W)", "%%%1") .. "]"
    local out, start = {}, 1
    while true do
        local i = s:find(class, start)
        if not i then out[#out + 1] = s:sub(start) break end
        out[#out + 1] = s:sub(start, i - 1)
        start = i + 1
    end
    return unpack(out)
end
function strjoin(sep, ...) return table.concat({ ... }, sep) end
function strtrim(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
function Ambiguate(name, kind)
    if kind == "none" then return (tostring(name):gsub("%-.*$", "")) end
    return name
end
function GetCursorPosition() return 100, 100 end
function InCombatLockdown() return W.inCombat and true or false end
function IsInGroup() return W.inGroup and true or false end
function IsInRaid() return W.inRaid and true or false end
function GetNumGroupMembers() return W.groupSize or 0 end
function IsInInstance() return W.inInstance and true or false, W.instanceType or "none" end
function GetInstanceInfo()
    return W.zoneName or "Test Zone", W.instanceType or "none", W.difficultyID or 8,
        "Mythic Keystone", 5, 0, false, W.instanceMapID or 2660
end
function UnitName(u) return "Merk" end
function UnitFullName(u) return "Merk", W.realm or "Illidan" end
function UnitClass(u) return "Paladin", "PALADIN" end
function UnitGUID(u) return "Player-1234-0000ABCD" end
function UnitIsDeadOrGhost(u) return W.playerDead and true or false end
function UnitAffectingCombat(u) return W.inCombat and true or false end
function UnitGroupRolesAssigned(u) return W.role or "DAMAGER" end
function GetSpecialization() return W.specIndex end
function GetSpecializationInfo(i) return 70, "Retribution", "", 135873, "DAMAGER" end
function GetSpecializationInfoByID(id) return id, "Retribution", "", 135873, "DAMAGER" end
function GetSpecializationRole(i) return "DAMAGER" end
function IsEncounterInProgress() return W.encounterInProgress and true or false end
function PlaySound(id, chan) W.sounds[#W.sounds + 1] = { id = id, chan = chan } end
function PlaySoundFile(f, chan) W.sounds[#W.sounds + 1] = { file = f, chan = chan } end
function RepopMe() W.repopped = (W.repopped or 0) + 1 end
function GetReleaseTimeRemaining() return 0 end
W.sounds = {}

-- WoW's global aliases for the Lua standard library, plus the unit helpers.
-- Missing ones show up as "attempt to call global 'x' (a nil value)", which
-- is the same failure the live client gives, so they are worth having rather
-- than working around in tests.
tinsert, tremove, tsort, twipe = table.insert, table.remove, table.sort, wipe
format, gsub, gmatch, strfind = string.format, string.gsub, string.gmatch, string.find
strsub, strlower, strupper, strrep = string.sub, string.lower, string.upper, string.rep
strlen, strbyte, strchar = string.len, string.byte, string.char
floor, ceil, abs, max, min, sqrt = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt
mod, random = math.fmod, math.random
function tContains(t, v) for _, x in ipairs(t or {}) do if x == v then return true end end return false end
function tDeleteItem(t, v)
    for i = #t, 1, -1 do if t[i] == v then table.remove(t, i) end end
end
function UnitIsDead(u) return W.playerDead and true or false end
function UnitIsGhost(u) return false end
function UnitExists(u) return u == "player" end
function UnitHealth(u) return 100 end
function UnitHealthMax(u) return 100 end
function UnitIsUnit(a, b) return a == b end
function UnitInParty(u) return false end
function UnitInRaid(u) return false end
-- GetBuildInfo() here says 12.1, so the mock has to CARRY 12.1's globals.
-- While these were missing, every `if CreateColor then ... else <legacy> end`
-- fork in the addon took the legacy branch: ns.Theme.Gradient exercised
-- SetGradientAlpha (removed from the client in 10.0) and never once ran the
-- SetGradient call the live client actually reaches.
function CreateColor(r, g, b, a)
    return { r = r, g = g, b = b, a = a,
             GetRGB = function(s) return s.r, s.g, s.b end,
             GetRGBA = function(s) return s.r, s.g, s.b, s.a end }
end
-- Present but answering "no unit": the guarded call in Timers.OnStartNameplate
-- used to fail on a nil global instead, so the mock could not tell a nameplate
-- whose unit is off-screen from one the API does not exist for.
function UnitTokenFromGUID(guid) return W.guidTokens and W.guidTokens[guid] or nil end
function GetTexCoordsForRole(r) return 0, 1, 0, 1 end
function BreakUpLargeNumbers(n) return tostring(n) end
function FormatLargeNumber(n) return tostring(n) end
function GetTime_Precise() return GetTime() end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsModifiedClick() return false end
function GetMouseFocus() return nil end
function GetScreenWidth() return UIParent:GetWidth() end
function GetScreenHeight() return UIParent:GetHeight() end
function PlaySoundKitID() end
function StaticPopup_Show() end
function ChatFrame_AddMessageEventFilter() end
function ReloadUI() end
function securecall(f, ...) if type(f) == "function" then return f(...) end end
function issecure() return false end
function GetFramerate() return 60 end
function collectgarbage_count() return 0 end
function UpdateAddOnMemoryUsage() end
function GetAddOnMemoryUsage() return 0 end
function UpdateAddOnCPUUsage() end
function GetAddOnCPUUsage() return 0 end
function ResetCPUUsage() end
function GetNumSpecializations() return 3 end
function GetInspectSpecialization() return 0 end
function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end
GameTooltip = makeFrame("GameTooltip", "GameTooltip", UIParent)
-- Character-dump APIs. These were absent, which is why /mui talents and
-- /mui equipment -- the two slash branches that call raw globals with no
-- `if ns.X then` guard -- were the only ones the suite could not drive.
-- One talent node and one action-bar slot is enough to prove the dump
-- walks its loops and writes what it found.
function UnitLevel() return 80 end
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 577, "Havoc" end
function GetActionInfo(slot)
    if slot == 1 then return "spell", 162794 end
    return nil
end
function GetInventoryItemLink(_, slot)
    if slot == 1 then return "|cffa335ee|Hitem:212014::::::::80:::::|h[Helm]|h|r" end
    return nil
end
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
    GetConfigInfo   = function() return { treeIDs = { 786 } } end,
    GetTreeNodes    = function() return { 91046 } end,
    GetNodeInfo     = function() return { maxRanks = 1, subTreeID = nil,
                          activeEntry = { entryID = 1, rank = 1 } } end,
    GetEntryInfo    = function() return { definitionID = 1 } end,
    GetDefinitionInfo = function() return { spellID = 162794 } end,
}
C_TooltipInfo = {
    GetInventoryItem = function() return { lines = { { leftText = "Helm" } } } end,
}

GameFontNormal = { GetFont = function() return "Fonts\FRIZQT__.TTF", 12, "" end }
GameFontHighlight = GameFontNormal
NORMAL_FONT_COLOR = { r = 1, g = 0.82, b = 0 }
LE_PARTY_CATEGORY_HOME = 1

RAID_CLASS_COLORS = { PALADIN = { r = 0.96, g = 0.55, b = 0.73 } }
C_ClassColor = { GetClassColor = function(c) return RAID_CLASS_COLORS[c] end }

C_AddOns = {
    GetAddOnMetadata = function(addon, field)
        if addon == "MerkUI" and field == "Version" then return "3.5.0" end
        return nil
    end,
    GetAddOnInfo = function(n) return n, n, "", W.addonLoadable ~= false, "MISSING" end,
    IsAddOnLoaded = function(n) return W.loadedAddons and W.loadedAddons[n] or false end,
    LoadAddOn = function(n) return false, "MISSING" end,
    GetNumAddOns = function() return 0 end,
}

C_Spell = {
    GetSpellName = function(id) return W.spellNames and W.spellNames[id] or nil end,
    GetSpellTexture = function(id) return 135873 end,
    GetSpellDescription = function(id) return "" end,
    RequestLoadSpellData = function(id) end,
    IsSpellDataCached = function(id) return true end,
}
C_Item = {
    GetItemStats = function(link) return W.itemStats and W.itemStats[link] or nil end,
    GetItemInfo = function(x) return nil end,
    RequestLoadItemDataByID = function(id) end,
}
C_ChatInfo = {
    RegisterAddonMessagePrefix = function(p) return W.prefixResult or 0 end,
    SendAddonMessage = function(...) W.sentAddonMessages[#W.sentAddonMessages + 1] = { ... } end,
}
W.sentAddonMessages = {}
C_ChallengeMode = {
    RequestMapInfo = function() end,
    GetMapTable = function() return W.cmMaps or {} end,
    GetMapUIInfo = function(id) return W.cmNames and W.cmNames[id] or nil end,
}
C_VoiceChat = { SpeakText = function(...) W.spoken[#W.spoken + 1] = select(2, ...) end }
W.spoken = {}
Enum = {
    VoiceTtsDestination = { LocalPlayback = 1 },
    RegisterAddonMessagePrefixResult = { Success = 0, TooLong = 1, AlreadyRegistered = 2, TooMany = 3 },
    DamageMeterType = { Interrupts = 5 },
}
C_CVar = { GetCVar = function(k) return W.cvars and W.cvars[k] end,
           SetCVar = function(k, v) W.cvars = W.cvars or {}; W.cvars[k] = v end }
GetCVar = C_CVar.GetCVar
SetCVar = C_CVar.SetCVar

-- Encounter Journal. The TIER is a CVar-backed selection the addon must
-- restore (landmine 21); the harness tracks it so a test can prove it did.
W.ejTier = 3
W.ejInstance = nil
W.ejTierSelections = 0
function EJ_GetNumTiers() return 11 end
function EJ_GetCurrentTier() return W.ejTier end
function EJ_SelectTier(t) W.ejTier = t; W.ejTierSelections = W.ejTierSelections + 1 end
function EJ_SelectInstance(i) W.ejInstance = i end
function EJ_GetInstanceByIndex(i, isRaid) return nil end
function EJ_GetEncounterInfoByIndex(j, inst) return nil end
function EJ_GetCreatureInfo(i, enc) return nil end
function EJ_GetInstanceInfo(i) return nil end
function EJ_GetSectionInfo(i) return nil end
function EJ_GetLootInfoByIndex(i) return nil end
function EJ_SetLootFilter() end
function EJ_ResetLootFilter() end
function EJ_GetNumLoot() return 0 end

LibStub = nil                -- no LibSharedMedia by default; tests can add one

function GetLocale() return "enUS" end
function GetRealmName() return "Illidan" end
function GetNormalizedRealmName() return "Illidan" end
function GetBuildInfo() return "12.1.0", "60000", "Sep 01 2026", 120100 end
function InterfaceOptions_AddCategory() end
Settings = {
    RegisterCanvasLayoutCategory = function(f, name) return { ID = 1 } end,
    RegisterAddOnCategory = function(c) end,
    OpenToCategory = function(id) end,
}
SlashCmdList = {}
hooksecurefunc = function(a, b, c)
    if type(a) == "string" then a, b, c = _G, a, b end
    local orig = a[b]
    if type(orig) ~= "function" then return end
    a[b] = function(...) local r = { orig(...) }; pcall(c, ...); return unpack(r) end
end

ColorPickerFrame = makeFrame("Frame", "ColorPickerFrame", UIParent)
function ColorPickerFrame:SetupColorPickerAndShow(info)
    W.colorPicker = info
end
function ColorPickerFrame:GetColorRGB() return W.pickedColor and W.pickedColor[1] or 1,
    W.pickedColor and W.pickedColor[2] or 1, W.pickedColor and W.pickedColor[3] or 1 end

--------------------------------------------------------------------------------
-- BigWigs stand-in
--
-- The hub and the relay both take ALL their input from BigWigs callbacks, so
-- the realistic way to drive them is to be BigWigs: register the way the
-- loader does, then send the same messages with the same argument positions.
-- Landmine 19 lives here -- eventId is the FOURTH argument of StopBar and the
-- EIGHTH of StartBar -- so the mock sends them exactly where BigWigs does,
-- and a test that gets a bar to stop has proved the addon reads them right.
--------------------------------------------------------------------------------
W.bwCallbacks = {}
W.bwPlugins = {}     -- name -> plugin stub; tests add Colors / Sounds here

function W.installBigWigs()
    -- CallbackHandler is keyed by (event, TARGET): registering twice with
    -- the same target REPLACES, it does not add a second listener.
    -- Appending hid the exact bug MerkUI already shipped once -- two modules
    -- passing the shared `ns` table, the second silently killing the first.
    local function register(target, msg, fn)
        local list = W.bwCallbacks[msg]
        if not list then list = {}; W.bwCallbacks[msg] = list end
        local handler = fn
        if type(fn) == "string" then handler = function(...) return target[fn](target, ...) end
        elseif fn == nil then handler = function(...) return target[msg](target, ...) end end
        for i, e in ipairs(list) do
            if e.target == target then
                list[i] = { target = target, fn = handler }
                return
            end
        end
        table.insert(list, { target = target, fn = handler })
    end
    local function unregister(target, msg)
        local list = W.bwCallbacks[msg]
        if not list then return end
        for i, e in ipairs(list) do
            if e.target == target then table.remove(list, i); return end
        end
    end
    W.bwUnregister = unregister
    BigWigsLoader = {
        RegisterMessage = function(target, msg, fn) register(target, msg, fn) end,
        UnregisterMessage = function(target, msg) unregister(target, msg) end,
        UnregisterAllMessages = function(target)
            for msg in pairs(W.bwCallbacks) do unregister(target, msg) end
        end,
        LoadZone = function() end,
    }
    BigWigs = {
        IterateBossModules = function() return function() return nil end, nil end,
        -- A METHOD: BigWigs:GetPlugin(name). The old stub had no `self`, so
        -- every lookup got the BigWigs table as the name and missed, leaving
        -- the Colors branch and the GetSoundFile branch unreachable.
        GetPlugin = function(self, name, silent)
            if type(self) == "string" then self, name = nil, self end
            return W.bwPlugins[name]
        end,
        db = { profile = {} },
    }
    return BigWigsLoader
end

-- Send a BigWigs message to every MerkUI callback registered for it.
-- A BigWigs BOSS MODULE, which the mock did not have at all. Every hub and
-- relay test drove with module = nil, so Timers.Info, BOTH AbilityDisabled
-- implementations, ModuleName, BarByText's same-module tiebreak (the
-- landmine-24 fix) and OnStopBars' module filter were never exercised by the
-- suite -- and the pause/resume bug, which is precisely a module-identity
-- bug, was invisible.
--
-- Field shapes checked against the installed BigWigs v424.7 BossPrototype:
-- GetEncounterID is a VARARG (19 installed modules register several ids),
-- IsEncounterID is the supported test, and GetRename ERRORS when the module
-- has no rename for that key, which is the normal case.
function W.bwModule(opts)
    opts = opts or {}
    local ids = opts.encounterIDs or { opts.encounterID or 2900 }
    local m = {
        moduleName  = opts.name or "MockBoss",
        displayName = opts.displayName or opts.name or "MockBoss",
        journalId   = opts.journalId,
        instanceId  = opts.instanceId or 2769,
        db = { profile = { toggles = opts.toggles or {} } },
    }
    -- T.Info's FIRST gate is `m.toggleDefaults[key] ~= nil` -- a real boss
    -- module's option table. Without it T.Info returned nil for every mock
    -- module, so emph/countdown/dispel/roleOK/rename/color -- 20 call sites
    -- across Bars, Rings, BossQueue and Editor -- were unreachable no matter
    -- what else the mock did.
    m.toggleDefaults = opts.toggleDefaults or { [2900] = 0 }
    if opts.flags then
        for k in pairs(opts.flags) do m.toggleDefaults[k] = 0 end
    end
    if opts.toggles then
        for k in pairs(opts.toggles) do m.toggleDefaults[k] = 0 end
    end
    function m:CanPassRoleRestrictions(key)
        if opts.roleFail and opts.roleFail[key] then return false end
        return true
    end
    function m:GetEncounterID() return unpack(ids) end
    function m:IsEncounterID(id)
        for _, v in ipairs(ids) do if v == id then return true end end
        return false
    end
    function m:IsTrashModule() return opts.trash and true or false end
    if opts.stage then function m:GetStage() return opts.stage end end
    function m:CheckOption(key, flag)
        local t = opts.flags and opts.flags[key]
        return t and t[flag] and true or false
    end
    function m:GetRename(key)
        local r = opts.renames and opts.renames[key]
        -- The real one raises rather than returning nil. Callers pcall it.
        if r == nil then error("no rename for " .. tostring(key), 2) end
        return r
    end
    function m:HasRenames() return opts.renames ~= nil end
    function m:IsRenameAvailable(key) return (opts.renames and opts.renames[key]) ~= nil end
    return m
end

-- Drive IsEncounterInProgress, which several recovery paths branch on.
function W.setEncounterInProgress(on) W.encounterInProgress = on and true or false end

function W.bwSend(msg, ...)
    local list = W.bwCallbacks[msg]
    if not list then return 0 end
    local n = 0
    for _, e in ipairs(list) do
        local ok, err = pcall(e.fn, msg, ...)
        if not ok then
            W.errors[#W.errors + 1] = msg .. ": " .. tostring(err)
        else
            n = n + 1
        end
    end
    return n
end

-- The PAIRS BigWigs really sends. Driving one message at a time is a shape
-- no client ever produces, and it hides every duplicate-intake bug.
--
-- BossPrototype:Bar() (BigWigs_Core/BossPrototype.lua:4455-4461) sends
-- BigWigs_StartBar -- only when the BAR flag is on -- and then ALWAYS
-- BigWigs_Timer, with the module in slot 1 and eventId in StartBar's NINTH
-- argument (slot 8 is maxTime).
function W.bwModuleBar(m, key, text, time, opts)
    opts = opts or {}
    local maxTime = opts.maxTime
    local icon = opts.icon
    local barEnabled = opts.barEnabled ~= false
    if barEnabled then
        W.bwSend("BigWigs_StartBar", m, key, text, time, icon,
                 opts.isApprox or false, maxTime, nil, opts.eventId)
    end
    W.bwSend("BigWigs_Timer", m, key, time, maxTime, text,
             opts.counter or 0, icon, false, barEnabled)
end

-- A Timeline / blizzbars bar: NO module, NO key, and the eventId in BOTH
-- slot 8 and slot 9 (BigWigs_Plugins/Timeline.lua:383, and every
-- "[B] name" backup bar a boss module emits, e.g.
-- BigWigs_MarchOnQuelDanas/Beloren.lua:186).
function W.bwTimelineBar(eventId, text, time, opts)
    opts = opts or {}
    W.bwSend("BigWigs_StartBar", nil, nil, text, time, opts.icon,
             opts.maxQueueDuration, opts.maxTime, eventId, eventId)
end

function W.bwRegistered(msg)
    return W.bwCallbacks[msg] and #W.bwCallbacks[msg] or 0
end

--------------------------------------------------------------------------------
-- Reset between tests
--------------------------------------------------------------------------------
function W.resetWorld()
    W.clearOutput()
    W.sounds, W.spoken, W.sentAddonMessages = {}, {}, {}
    W.inCombat, W.playerDead, W.encounterInProgress = false, false, false
    W.inGroup, W.inRaid, W.groupSize = false, false, 0
    W.inInstance, W.instanceType, W.difficultyID = false, "none", 8
    W.ejTier, W.ejTierSelections = 3, 0
end
W.resetWorld()

--------------------------------------------------------------------------------
-- Layout inspection
--
-- Everything here is ARITHMETIC over points and sizes -- where a frame is,
-- how big, what it overlaps, whether it fits on screen. None of it needs
-- rendering, so all of it is testable outside the client. What is NOT here,
-- and cannot be: actual pixels. Font rasterisation, texture art, blend
-- modes, draw order between equal layers. GetStringWidth is 6px a character,
-- so text-fit answers are approximate and only gross overflow is meaningful.
--
-- Coordinates are UIParent's: x right from its left edge, y up from its
-- bottom, both scaled to UIParent's own space so frames at different scales
-- are comparable.
--------------------------------------------------------------------------------

-- Screen rect of a frame, in UIParent units. nil when it has no resolvable
-- position (no points, or an anchor chain that leads nowhere).
function W.rect(f)
    if not f or not f.GetLeft then return nil end
    local l, b = f:GetLeft(), f:GetBottom()
    if not l or not b then return nil end
    local s = f.GetEffectiveScale and f:GetEffectiveScale() or 1
    local us = UIParent:GetEffectiveScale()
    local k = (us ~= 0) and (s / us) or 1
    return {
        left = l * k, bottom = b * k,
        width = (f:GetWidth() or 0) * k, height = (f:GetHeight() or 0) * k,
        right = (l + (f:GetWidth() or 0)) * k,
        top = (b + (f:GetHeight() or 0)) * k,
        name = f.__name, frame = f,
    }
end

-- CLIPPING. A ScrollFrame is a window: its child is bigger than it and only
-- the part inside the viewport is on screen. Without this every row scrolled
-- out of view reads as real geometry -- false overlaps between rows nobody
-- can see at once, and false off-screen hits for content parked above the
-- viewport. Returns the rect actually visible, or nil when the frame is
-- scrolled entirely out.
function W.visibleRect(f)
    local r = W.rect(f)
    if not r then return nil end
    local p = f.__parent
    while p do
        if p.__scrollChild then
            local sr = W.rect(p)
            if sr then
                local left = math.max(r.left, sr.left)
                local bottom = math.max(r.bottom, sr.bottom)
                local right = math.min(r.right, sr.right)
                local top = math.min(r.top, sr.top)
                if right - left <= 0 or top - bottom <= 0 then return nil end
                r = { left = left, bottom = bottom, right = right, top = top,
                      width = right - left, height = top - bottom,
                      name = r.name, frame = r.frame, clipped = true }
            end
        end
        p = p.__parent
    end
    return r
end

-- True when no part of the frame survives the ScrollFrame viewports above it.
function W.isClipped(f) return f ~= nil and W.rect(f) ~= nil and W.visibleRect(f) == nil end

-- Overlapping area of two frames in square UIParent units, 0 when disjoint.
function W.overlapArea(a, b)
    local ra, rb = W.visibleRect(a), W.visibleRect(b)
    if not ra or not rb then return 0 end
    local w = math.min(ra.right, rb.right) - math.max(ra.left, rb.left)
    local h = math.min(ra.top, rb.top) - math.max(ra.bottom, rb.bottom)
    if w <= 0 or h <= 0 then return 0 end
    return w * h
end

-- How far a frame falls outside UIParent, per edge. All zero when it fits.
function W.offscreen(f)
    -- Clipped content is not off screen, it is behind the viewport edge; a
    -- frame scrolled entirely out has no on-screen geometry to judge.
    local r = W.visibleRect(f)
    if not r then return nil end
    local W_, H = UIParent:GetWidth(), UIParent:GetHeight()
    return {
        left   = math.max(0, -r.left),
        bottom = math.max(0, -r.bottom),
        right  = math.max(0, r.right - W_),
        top    = math.max(0, r.top - H),
        any    = math.max(0, -r.left) + math.max(0, -r.bottom)
               + math.max(0, r.right - W_) + math.max(0, r.top - H),
    }
end

-- Two points pinning the SAME axis disagree unless they happen to coincide.
-- The client picks one and the layout silently stops tracking the other --
-- the FightLanes cursor line is over-constrained on X this way.
function W.overConstrained(f)
    if not f or not f.__points then return nil end
    -- Bucket each point by WHICH reference of this frame it fixes, so a
    -- left+right stretch is not confused with two conflicting centres.
    local xs, ys = { LEFT = {}, RIGHT = {}, CENTER = {} }, { TOP = {}, BOTTOM = {}, CENTER = {} }
    -- Did an author EXPLICITLY name a centre on this axis? "TOP" also lands
    -- in xs.CENTER (the client's TOP does pin centre-x), but treating that
    -- as an x constraint turns the ordinary TOP+LEFT idiom into a conflict.
    local namedCx, namedCy = false, false
    for _, p in ipairs(f.__points) do
        local px, py = W.pointOn(p.rel, p.relPoint)
        if px then
            if p.point == "CENTER" then namedCx, namedCy = true, true end
            local xk = p.point:find("LEFT") and "LEFT"
                or p.point:find("RIGHT") and "RIGHT" or "CENTER"
            table.insert(xs[xk], px + (p.x or 0))
            local yk = p.point:find("TOP") and "TOP"
                or p.point:find("BOTTOM") and "BOTTOM" or "CENTER"
            table.insert(ys[yk], py + (p.y or 0))
        end
    end
    -- Pinning a LEFT edge and a RIGHT edge is a stretch: legitimate, and it
    -- defines the width. The conflict is two points fixing the SAME reference
    -- -- two centres, or two lefts -- which disagree unless they coincide.
    --
    -- The per-bucket test alone had a hole big enough to walk through. Because
    -- SetPoint REPLACES a point of the same name, a bucket only ever gets two
    -- entries from two DIFFERENT names that happen to fix the same reference
    -- (LEFT + TOPLEFT, say). The commonest real conflict -- a CENTRE pin and
    -- an EDGE pin on the same axis, with the size fixed by SetWidth -- landed
    -- one entry in each bucket and scored ZERO. A frame pinned CENTER at x=200
    -- and LEFT at x=900 is 650 units from where one of its two authors thought
    -- it was, and W.overConstrained called it clean. The old comment said to
    -- "leave that to the caller's tolerance"; the caller (21 layout's
    -- over-constrained test) has no way to see it at all, so it is handled here.
    local function conflict(t, lowKey, highKey, size, namedCentre)
        local worst = 0
        for _, list in pairs(t) do
            if #list > 1 then
                local lo, hi = list[1], list[1]
                for _, v in ipairs(list) do lo, hi = math.min(lo, v), math.max(hi, v) end
                worst = math.max(worst, hi - lo)
            end
        end
        -- Cross-kind: once the size is known every pin implies a CENTRE.
        -- Skip when both edges are pinned -- that is the stretch, and there
        -- the edges define the size rather than disagreeing with it.
        local low, high, mid = t[lowKey], t[highKey], t.CENTER
        if namedCentre and not (#low > 0 and #high > 0) then
            local centres = {}
            for _, v in ipairs(low) do centres[#centres + 1] = v + size / 2 end
            for _, v in ipairs(high) do centres[#centres + 1] = v - size / 2 end
            for _, v in ipairs(mid) do centres[#centres + 1] = v end
            if #centres > 1 then
                local lo, hi = centres[1], centres[1]
                for _, v in ipairs(centres) do lo, hi = math.min(lo, v), math.max(hi, v) end
                worst = math.max(worst, hi - lo)
            end
        end
        return worst
    end
    local w, h = f.__w or 0, f.__h or 0
    return { x = conflict(xs, "LEFT", "RIGHT", w, namedCx),
             y = conflict(ys, "BOTTOM", "TOP", h, namedCy) }
end

-- Does a FontString's text fit the frame it is meant to sit in? Approximate
-- (6px a character) -- use it for gross overflow, not for kerning.
function W.textOverflow(fs, container)
    if not fs or not fs.GetStringWidth then return 0 end
    local need = fs:GetStringWidth()
    local have = (container or fs):GetWidth() or 0
    if have <= 0 then return 0 end
    return math.max(0, need - have)
end

-- Every registered anchor, by its saved-variable key, with its rect. This is
-- the addon's own movables registry, so it is exactly the set the user can
-- drag and exactly the set /mui resetpos touches.
function W.anchors(ns)
    local out = {}
    for frame, key in pairs((ns and ns.movables) or {}) do
        if frame and frame.IsObjectType then
            local r = W.rect(frame)
            if r then
                r.key = (type(key) == "string") and key or (frame.__name or "?")
                r.shown = frame:IsShown() and true or false
                out[#out + 1] = r
            end
        end
    end
    table.sort(out, function(a, b) return tostring(a.key) < tostring(b.key) end)
    return out
end
