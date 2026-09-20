--[[ Salus Novus -- Core: namespace, guards, defaults, apply pipeline, anchors, events, slash.

WoW Forever is retail's 12.x client serving vanilla content (measured; see
WoWDungeonData/wow_forever_notes.md). Two consequences shape every file:

  * Secret values are live. Anything from the client is checked with
    ns.IsSecret before it is formatted, compared or stored.
  * SavedVariables do not survive a client restart on this account (client
    bug, reported). Salus Novus must be fully usable from defaults; SalusNovusDB is
    written but never relied on.

The apply pipeline, the anchor mechanics (growth-origin records, snapping,
the alignment grid, locks) and the theme colour are MerkUI's (Core.lua),
carried over because every line of them is a fixed bug. Lua 5.1 only.
]]

local ADDON, ns = ...

-- --------------------------------------------------------------- guards

local rawissecret = rawget(_G, "issecretvalue")
ns.HAS_SECRETS = type(rawissecret) == "function"

function ns.IsSecret(v)
    if not ns.HAS_SECRETS then return false end
    local ok, res = pcall(rawissecret, v)
    if not ok then return true end       -- could not even ask: treat as secret
    return res and true or false
end

--- A string that is safe to concatenate. nil -> "", secret -> a marker.
function ns.S(v)
    if v == nil then return "" end
    if ns.IsSecret(v) then return "?" end
    local ok, s = pcall(tostring, v)
    return ok and s or "?"
end

function ns.Print(msg)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7af2Salus Novus|r " .. ns.S(msg))
    end
end

-- ------------------------------------------------------------- defaults

-- A nil value is NOT a default: pairs() never yields it, so a commented-out
-- key documents rather than seeds (MerkUI Core.lua:244).
ns.defaults = {
    theme = {
        useClassColor = false,                              -- Alex: off
        customColor   = { r = 1.00, g = 0.478, b = 0.949 }, -- #FF7AF2 (Alex)
    },
    font = {
        -- Prototype from the SharedMediaAdditionalFonts pack (Alex's pick).
        -- SetFontSafe falls back to the stock font when the pack is absent.
        -- Always a string: picking "Game default" stores the stock path, so
        -- CopyDefaults never re-seeds this over a deliberate choice.
        path = "Interface\\AddOns\\SharedMediaAdditionalFonts\\fonts\\Prototype.ttf",
        wholeUI = true,         -- also re-font Blizzard's own font objects (Alex: on)
    },
    anchorsGlobal = {
        scale     = 100,        -- % applied to every anchor frame
        grid      = true,       -- alignment grid while frames are unlocked
        gridSize  = 32,
        snap      = true,
        snapRange = 8,
    },
    bars = {
        enabled = true, width = 220, height = 18, spacing = 4, max = 4,
        direction = "up", fill = "drain", icon = "left", text = "both",
        fontSize = 11, color = { r = 0.3, g = 0.6, b = 1 },
        byRemaining = true, byRemainingAt = 3,
        grace = 2.5,            -- seconds a landed bar reads "now" before it drops
    },
    queue = {
        enabled = true, count = 5, size = 48, shrink = 100, gap = 6, direction = "right",
        desaturate = true, fade = 50, timeOnIcon = "edge", labels = "lead", labelSize = 14,
        showTimers = true, timerPos = "center", timerSize = 12, border = 2,
        backdrop = false, backdropAlpha = 40,
    },
    reminders = {
        enabled = true, lead = 5, hold = 1.5, size = 14, showIcon = true,
        sound = true, castThrottle = 3, direction = "up", spacing = 4,
        color = { r = 1, g = 0.82, b = 0 },
        list = {},              -- [encounterID] = { reminder, ... }
        hidden = {},            -- [defaultReminderId] = true
    },
    -- Ability Preview: a countdown line per routed ability as it approaches.
    preview = {
        enabled = true, countdownSeconds = 5, showIcon = true, fontSize = 28,
        direction = "up", spacing = 4, max = 4, color = { r = 1, g = 0.82, b = 0 },
    },
    -- Messages: big text when a routed (opt-in) ability lands.
    messages = {
        enabled = true, max = 3, hold = 2.5, spacing = 4, direction = "up",
        showIcon = true, size = 24, color = { r = 1, g = 0.82, b = 0 },
    },
    abilities = {},             -- [tostring(spellID)] = Abilities.lua record
    unlocked = false,           -- when false, no anchor can be dragged
    -- Master switches, one per module in the options sidebar. Off: nothing
    -- of that module renders or arms in a fight; its pages stay listed.
    modules = { bossWarnings = true },
}

function ns.ModuleOn(key)
    local m = ns.db and ns.db.modules
    return not (m and m[key] == false)
end

-- Positions are NOT in ns.db: SaveAnchor writes SalusNovusDB.<key> at the top
-- level, so a settings reset never moves an anchor (MerkUI Core.lua:235).

local SEED_ONLY = {}

local function CopyDefaults(src, dst, top)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                -- The ONLY line in the load path that discards a user value.
                -- Keep it where it can be recovered.
                if dst[k] ~= nil then
                    SalusNovusDB.replacedScalars = SalusNovusDB.replacedScalars or {}
                    SalusNovusDB.replacedScalars[k] = dst[k]
                end
                dst[k] = {}
                CopyDefaults(v, dst[k])
            elseif not (top and SEED_ONLY[k]) then
                CopyDefaults(v, dst[k])
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end
ns.CopyDefaults = CopyDefaults

function ns.InitDB()
    if type(SalusNovusDB) ~= "table" then SalusNovusDB = {} end
    if type(SalusNovusDB.options) ~= "table" then SalusNovusDB.options = {} end
    CopyDefaults(ns.defaults, SalusNovusDB.options, true)
    ns.db = SalusNovusDB.options
end

-- ----------------------------------------------------------- apply pipeline

local applyFns, applyLabels = {}, {}

--- `label` is only for diagnostics, but without it ApplyAll could only say
-- "module error" with no way to tell which of many modules threw.
function ns.RegisterApply(fn, label)
    table.insert(applyFns, fn)
    applyLabels[#applyFns] = label
end

local applyErrShown, applyErrText = {}, {}
function ns.ApplyErrors()
    local out = {}
    for i, err in pairs(applyErrText) do
        out[applyLabels[i] or ("module #" .. i)] = err
    end
    return out
end

--- Re-run every module's Apply. One report per module per session: this
-- runs on every slider step, and a throwing module made chat unusable.
function ns.ApplyAll()
    if ns.InvalidateFontCache then ns.InvalidateFontCache() end
    for i, fn in ipairs(applyFns) do
        local ok, err = pcall(fn)
        if ok then
            applyErrText[i] = nil
        elseif applyErrShown[i] then
            applyErrText[i] = tostring(err)      -- recorded even while silenced
        else
            applyErrShown[i] = true
            applyErrText[i] = tostring(err)
            ns.Print(("module error [%s]: %s"):format(tostring(applyLabels[i] or ("#" .. i)), tostring(err)))
            ns.Print("(further errors from this module are silenced; /reload to reset)")
        end
    end
end

-- ------------------------------------------------------------------ theme

--- Class colour by default, or the custom colour. Deliberately uncached so
-- a spec/class change is picked up on the next ApplyAll.
function ns.GetThemeColor()
    local theme = ns.db and ns.db.theme
    if theme and not theme.useClassColor and theme.customColor then
        local c = theme.customColor
        return c.r, c.g, c.b
    end
    local _, token = UnitClass("player")
    local color = C_ClassColor and C_ClassColor.GetClassColor and token and C_ClassColor.GetClassColor(token)
    if color and not ns.IsSecret(color) then return color.r, color.g, color.b end
    local rc = RAID_CLASS_COLORS and token and RAID_CLASS_COLORS[token]
    if rc then return rc.r, rc.g, rc.b end
    return 0.60, 0.80, 1.00
end

function ns.AnchorScale()
    local g = ns.db and ns.db.anchorsGlobal
    return ((g and g.scale) or 100) / 100
end

-- ---------------------------------------------------------------- anchors

-- Movable frames register here so one toggle can lock/unlock them all.
local movables = {}
ns.movables = movables            -- SnapMovable aligns against the other anchors
function ns.RegisterMovable(frame, saveKey, origin)
    movables[frame] = saveKey or true
    frame.__origin = origin       -- function -> the growth-origin point
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
end

-- A position is stored as the frame's GROWTH ORIGIN point (LEFT for a
-- right-growing strip, TOPLEFT for a downward stack ...) in UIParent
-- coordinates from UIParent's BOTTOMLEFT, independent of the frame's size
-- AND its scale: { point, x, y, v = 2 }. A content-sized strip pinned by
-- CENTER re-centres every time its content changes (MerkUI landmine 17).
-- Legacy records ({point, relPoint, x, y}) are read and rewritten on save.
local function ScaleRatio(frame)
    local fs, us = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not fs or fs == 0 or not us or us == 0 then return 1 end
    return fs / us
end

local function OriginXY(frame, point)
    local l, b, w, h = frame:GetLeft(), frame:GetBottom(), frame:GetWidth(), frame:GetHeight()
    if not l or not b then return nil end
    local s = ScaleRatio(frame)
    l, b, w, h = l * s, b * s, w * s, h * s
    local x, y
    if point:find("LEFT") then x = l elseif point:find("RIGHT") then x = l + w else x = l + w / 2 end
    if point:find("BOTTOM") then y = b elseif point:find("TOP") then y = b + h else y = b + h / 2 end
    return x, y, s
end
ns.OriginXY = OriginXY

function ns.SaveAnchor(frame, key)
    -- Only for a frame living on the screen: during an options preview the
    -- frame is parented to a page stage, and saving from there would write a
    -- spot inside that little box and rip the frame off the stage.
    if frame:GetParent() ~= UIParent then return end
    local point = (frame.__origin and frame.__origin()) or "CENTER"
    local x, y, s = OriginXY(frame, point)
    if not x then return end
    SalusNovusDB[key] = { point = point, x = x, y = y, v = 2 }
    -- Re-anchor from the record just written: a drag leaves the frame pinned
    -- wherever the drag put it, and SnapMovable pins by CENTER.
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "BOTTOMLEFT", x / s, y / s)
end

--- Call from a module's layout AFTER the frame has its final size. Keeps the
-- frame where it is and re-pins it by the right corner. NO RECORD IS NOT
-- "NOTHING TO DO" -- a fresh install must be re-pinned too (landmine 17).
function ns.SyncAnchorOrigin(frame, key)
    local rec = SalusNovusDB and SalusNovusDB[key]
    if rec and rec.v == 2 then
        local want = (frame.__origin and frame.__origin()) or "CENTER"
        if rec.point == want then return end
    end
    if not frame:GetLeft() then return end          -- not laid out yet
    ns.SaveAnchor(frame, key)
end

--- Re-anchor from the saved record, or the default point + offset. Call
-- again after a scale change. Writes NOTHING: an anchor the user never
-- touched stays untouched.
--- `relPoint` (default: `defaultPoint`) is the point of UIParent the default
-- offset is measured from: the shipped defaults are Alex's own layout, read
-- from his saved positions and expressed from the screen CENTRE so they
-- hold at any resolution.
function ns.RestoreAnchor(frame, key, defaultPoint, dx, dy, relPoint)
    frame:ClearAllPoints()
    local p = SalusNovusDB and SalusNovusDB[key]
    if p ~= nil and type(p) ~= "table" then     -- hand-edited or downgraded
        SalusNovusDB[key] = nil
        p = nil
    end
    -- A hand-edited record with NaN, inf or an absurd coordinate is dropped
    -- like a junk one: the frame would sit at NaN and nothing self-heals.
    local function Sane(v) return type(v) == "number" and v == v and v > -20000 and v < 20000 end
    if p and p.v == 2 and not (Sane(p.x) and Sane(p.y)) then
        SalusNovusDB[key] = nil
        p = nil
    end
    if p and p.v == 2 and p.point and p.x and p.y then
        local s = ScaleRatio(frame)
        frame:SetPoint(p.point, UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
    elseif p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        -- Offsets are screen pixels; SetPoint takes the frame's own scaled
        -- units, so divide by the scale like every other path here.
        local s0 = ScaleRatio(frame)
        frame:SetPoint(defaultPoint, UIParent, relPoint or defaultPoint, (dx or 0) / s0, (dy or 0) / s0)
        local want = frame.__origin and frame.__origin()
        if want and want ~= defaultPoint then
            local x, y, s = OriginXY(frame, want)
            if x then
                frame:ClearAllPoints()
                frame:SetPoint(want, UIParent, "BOTTOMLEFT", x / s, y / s)
            end
        end
    end
end

--- true when the scale changed (the caller then restores the position).
function ns.SetMovableScale(frame, scale)
    if math.abs((frame:GetScale() or 1) - scale) < 0.001 then return false end
    frame:SetScale(scale)
    return true
end

-- Alignment grid + snapping for unlock mode. gridSize is CLAMPED, not
-- defaulted: 0 is truthy, and `for x = cx, w, 0` loops forever in 5.1
-- allocating a texture per iteration (MerkUI measured 55,248 and no return).
local gridFrame
local function GridOpts()
    local g = ns.db and ns.db.anchorsGlobal or {}
    local size = tonumber(g.gridSize) or 32
    if size ~= size or size < 4 or size > 512 then size = 32 end
    local snapR = tonumber(g.snapRange) or 8
    if snapR ~= snapR or snapR < 0 or snapR > 512 then snapR = 8 end
    return g.grid ~= false, size, g.snap ~= false, snapR
end

function ns.ShowAlignGrid(show)
    local on, size = GridOpts()
    if not show or not on then
        if gridFrame then gridFrame:Hide() end
        return
    end
    if not gridFrame then
        gridFrame = CreateFrame("Frame", "SalusNovusAlignGrid", UIParent)
        gridFrame:SetAllPoints(UIParent)
        gridFrame:SetFrameStrata("BACKGROUND")
        gridFrame:SetFrameLevel(0)
        gridFrame.lines = {}
    end
    for _, l in ipairs(gridFrame.lines) do l:Hide() end
    local w, h = UIParent:GetWidth(), UIParent:GetHeight()
    local cx, cy = w / 2, h / 2
    local ar, ag, ab = ns.GetThemeColor()
    local n = 0
    local function Line(vertical, pos, center)
        n = n + 1
        local t = gridFrame.lines[n]
        if not t then
            t = gridFrame:CreateTexture(nil, "BACKGROUND")
            t:SetTexture("Interface\\Buttons\\WHITE8x8")
            gridFrame.lines[n] = t
        end
        t:ClearAllPoints()
        if vertical then
            t:SetWidth(center and 2 or 1)
            t:SetPoint("TOP", UIParent, "TOPLEFT", pos, 0)
            t:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", pos, 0)
        else
            t:SetHeight(center and 2 or 1)
            t:SetPoint("LEFT", UIParent, "BOTTOMLEFT", 0, pos)
            t:SetPoint("RIGHT", UIParent, "BOTTOMRIGHT", 0, pos)
        end
        if center then t:SetVertexColor(ar, ag, ab, 0.7) else t:SetVertexColor(1, 1, 1, 0.08) end
        t:Show()
    end
    for x = cx, w, size do Line(true, x, x == cx) end
    for x = cx - size, 0, -size do Line(true, x, false) end
    for y = cy, h, size do Line(false, y, y == cy) end
    for y = cy - size, 0, -size do Line(false, y, false) end
    gridFrame:Show()
end

--- Snap after a drag: another anchor's centre/edges, the screen centre, or
-- the grid. Re-anchors by CENTER; the module's SavePosition then stores the
-- growth-origin point.
function ns.SnapMovable(frame)
    local gridOn, size, snapOn, range = GridOpts()
    if not snapOn then return end
    local cx, cy = frame:GetCenter()
    if not cx then return end
    local fs = ScaleRatio(frame)
    cx, cy = cx * fs, cy * fs
    local w, h = frame:GetWidth() * fs, frame:GetHeight() * fs
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local candX, candY = { sw / 2 }, { sh / 2 }
    for other in pairs(movables) do
        if other ~= frame and other:IsShown() and other:GetCenter() then
            local os = ScaleRatio(other)
            local ox, oy = other:GetCenter()
            ox, oy = ox * os, oy * os
            local ow, oh = other:GetWidth() * os, other:GetHeight() * os
            candX[#candX + 1] = ox
            candX[#candX + 1] = ox - ow / 2 + w / 2
            candX[#candX + 1] = ox + ow / 2 - w / 2
            candY[#candY + 1] = oy
            candY[#candY + 1] = oy + oh / 2 - h / 2
            candY[#candY + 1] = oy - oh / 2 + h / 2
        end
    end
    local function Best(v, cands)
        local best, bd = nil, range + 0.001
        for _, c in ipairs(cands) do
            local d = math.abs(c - v)
            if d < bd then best, bd = c, d end
        end
        return best
    end
    local nx, ny = Best(cx, candX), Best(cy, candY)
    -- The grid only pulls while it is SHOWN: a frame jumping to a line
    -- nobody can see reads as a bug.
    if not nx and gridOn then
        local g = sw / 2 + math.floor((cx - sw / 2) / size + 0.5) * size
        if math.abs(g - cx) <= range then nx = g end
    end
    if not ny and gridOn then
        local g = sh / 2 + math.floor((cy - sh / 2) / size + 0.5) * size
        if math.abs(g - cy) <= range then ny = g end
    end
    if not nx and not ny then return end
    nx, ny = nx or cx, ny or cy
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", nx / fs, ny / fs)
end

function ns.ApplyLocks()
    local unlocked = ns.db and ns.db.unlocked
    for frame in pairs(movables) do
        if frame.EnableMouse then frame:EnableMouse(unlocked and true or false) end
    end
end
ns.RegisterApply(ns.ApplyLocks, "Frame locks")

-- --------------------------------------------------------------- lookups

function ns.Instance(mapID)
    return ns.Data and ns.Data[mapID] or nil
end

--- Boss record and its instance for an encounter id, or nil. A boss may
-- carry several ids (era/SoD variants of one fight): any of them matches.
function ns.BossByEncounter(encounterID)
    if not ns.Data or encounterID == nil then return nil end
    for _, inst in pairs(ns.Data) do
        for _, b in ipairs(inst.bosses) do
            if b.encounterID == encounterID then return b, inst end
            for _, id in ipairs(b.encounterIDs or {}) do
                if id == encounterID then return b, inst end
            end
        end
    end
    return nil
end

--- Case-insensitive boss lookup by (a prefix of) name, for slash commands.
function ns.BossByName(text)
    if not ns.Data or type(text) ~= "string" or text == "" then return nil end
    local q = text:lower()
    for _, inst in pairs(ns.Data) do
        for _, b in ipairs(inst.bosses) do
            if b.name:lower():find(q, 1, true) == 1 then return b, inst end
            -- the encounter's own name, when the boss shows under its NPC's
            if b.encounterName and b.encounterName:lower():find(q, 1, true) == 1 then return b, inst end
        end
    end
    return nil
end

-- ------------------------------------------------------------ event bus

-- One frame, one dispatcher, the ONLY place RegisterEvent is called. A
-- protected registration fails SILENTLY on this client (measured: the call
-- returns, the event never arrives), so every registration is verified with
-- IsEventRegistered and reported once rather than discovered in a fight.
local bus = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        local ok = pcall(bus.RegisterEvent, bus, event)
        local took = ok
        if bus.IsEventRegistered then
            local ok2, r = pcall(bus.IsEventRegistered, bus, event)
            took = ok2 and r and true or false
        end
        if not took then ns.Print("could not register " .. event) end
    end
    table.insert(handlers[event], fn)
end

bus:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then ns.Print(event .. " handler error: " .. ns.S(err)) end
    end
end)

--- Modules append to this to run after the DB exists (before ApplyAll).
ns.OnLoad = {}

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON then return end
    ns.InitDB()
    for _, fn in ipairs(ns.OnLoad) do
        local ok, err = pcall(fn)
        if not ok then ns.Print("load error: " .. ns.S(err)) end
    end
    ns.ApplyAll()
end)

-- ------------------------------------------------------------------ slash

ns.Commands = {}

SLASH_SALUSNOVUS1 = "/sn"
SLASH_SALUSNOVUS2 = "/salusnovus"
SlashCmdList["SALUSNOVUS"] = function(msg)
    msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = (cmd or ""):lower()
    local fn = ns.Commands[cmd]
    if fn then
        fn(rest or "")
    elseif cmd == "" then
        if ns.ToggleOptions then ns.ToggleOptions()
        elseif ns.Commands.show then ns.Commands.show("") end
    else
        ns.Print("commands: /sn  |  /sn show  |  /sn test <boss>  |  /sn remind <boss> <pull|time N|cast|emote WORD> <text>  |  /sn reminders  |  /sn resetpos")
    end
end

-- Every anchor registers its position key + restore function here, so the
-- unlock flow's Cancel and /sn resetpos can reach all of them.
ns.AnchorPositions = {}    -- { { key = "barsPos", restore = "BarsRestorePosition" }, ... }

ns.Commands.resetpos = function()
    for _, a in ipairs(ns.AnchorPositions) do
        SalusNovusDB[a.key] = nil
        if ns[a.restore] then pcall(ns[a.restore]) end
    end
    ns.ApplyAll()
    ns.Print("every anchor position reset to its default.")
end
