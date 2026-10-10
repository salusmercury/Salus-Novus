--[[ Salus Novus -- Core: namespace, guards, defaults, apply pipeline, anchors, events, slash.

WoW Forever is retail's 12.x client serving vanilla content (measured; see
WoWDungeonData/wow_forever_notes.md). Two consequences shape every file:

  * Secret values are live. Anything from the client is checked with
    ns.IsSecret before it is formatted, compared or stored.
  * SavedVariables were not read back on the author's account until a client
    fix (2026-09-24). Salus Novus stays fully usable from defaults, and every
    saved value is checked on load (CopyDefaults, the migrations).

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

--- Plain (non-secret) number / string, or nil. Shared by the Quality of
-- Life modules and the probe.
function ns.Num(v) return type(v) == "number" and not ns.IsSecret(v) end
function ns.Str(v) return type(v) == "string" and not ns.IsSecret(v) and v or nil end

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
        desaturate = true, fade = 50, timeOnIcon = "none", labels = "lead", labelSize = 14,
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
    -- Messages: big text when a routed (on by default) ability lands.
    messages = {
        enabled = true, max = 3, hold = 2.5, spacing = 4, direction = "up",
        showIcon = true, size = 24, color = { r = 1, g = 0.82, b = 0 },
    },
    -- Health Bars: the engaged boss's health with a marker per
    -- health-triggered ability (cast at a health, not a time).
    healthBars = {
        enabled = true, width = 260, height = 20, showName = true, labelSize = 11,
        color = { r = 0.25, g = 0.80, b = 0.30 },
        -- A council fight stacks one bar per boss: growth, gap, where the
        -- name goes (above / inside / below / off), icons under the markers.
        -- Alex's picks (2026-09-20): up, 20 px gap, the name inside the bar.
        direction = "up", spacing = 20, namePos = "inside", showIcons = false,
    },
    -- Chat filter: lines whose text or sender contains a word here are
    -- dropped before any chat frame shows them (Alex, 2026-09-21).
    -- `words` is a SET (word -> true); a removed default is stored as
    -- false so this seeding does not bring it back. On/off is the Quality
    -- of Life module switch (modules.qol), not a setting of its own.
    chatFilter = { words = { asmon = true, olympus = true, trump = true, republican = true, democrat = true } },
    -- Sidebar sections fold: [moduleKey or "global"] = true (folded) /
    -- false (open). A module switch writes it; a click on the heading
    -- overrides it; both stick (Alex, 2026-09-21).
    sidebar = { collapsed = {} },
    -- Trainer catalogue (Quality of Life > Trainer): the captured list is
    -- SalusNovusDB.trainers[class] at the top level; these are the switches.
    trainer = { enabled = true },
    -- Quests (Quality of Life): the gold coin on the best-selling reward.
    quests = { goldMark = true, dungeonCheck = true },
    -- Session bar (Quality of Life): XP/h, gold/h and instance lockouts on one
    -- databar; per-character sessions in SalusNovusDB.session, the account's
    -- instance entries in SalusNovusDB.instances. `limit` = instances per hour
    -- until the client's own error teaches the real one.
    session = { enabled = true, xp = true, gold = true, instances = true, size = 12, limit = 5 },
    -- Camping (Quality of Life): the camp panel; show = "duration" (your
    -- campfire kit ready, or within kitMinutes of it, or a campfire in range)
    -- or "always"; alpha = the background's opacity, 0-100.
    camping = { enabled = true, alpha = 90 },
    -- Auction (Quality of Life): the Snipe tab on the auction house; a scan
    -- on opening it; the least profit per item worth showing (copper).
    -- Investing: a budget of investPct% of your gold, commodities with at
    -- least investMinListed units listed.
    -- autoScan: no scan on opening the AH by default (Alex)
    auction = { enabled = true, autoScan = false, minProfit = 5, investPct = 20, investMinListed = 250,
                investMinProfit = 1,       -- gold: the least total profit worth a buy
                investMaxShare = 10 },     -- percent: the most of a commodity's supply one buy may take
    -- Wishlist (Quality of Life): lists live in SalusNovusDB.wishlist[character].
    wishlist = {},
    abilities = {},             -- [tostring(spellID)] = Abilities.lua record
    unlocked = false,           -- when false, no anchor can be dragged
    -- Master switches, one per module in the options sidebar. Off: nothing
    -- of that module renders or arms in a fight; its pages stay listed.
    modules = { bossWarnings = true, qol = true },
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

--- Before 0.4.6 the chat filter had its own check box (chatFilter.enabled);
-- now it follows the Quality of Life switch and nothing reads the flag. A
-- save with it off gets every word removed instead, the stock ones as
-- FALSE so CopyDefaults does not seed them back, and loses the flag.
local function MigrateChatFilterOff(o)
    local cf = o.chatFilter
    if type(cf) ~= "table" or cf.enabled ~= false then return end
    local words = type(cf.words) == "table" and cf.words or {}
    local out = {}
    for k, v in pairs(words) do
        if type(k) == "string" then out[k] = false
        elseif type(v) == "string" then out[v:lower()] = false end
    end
    for k in pairs(ns.defaults.chatFilter.words) do out[k] = false end
    cf.words, cf.enabled = out, nil
end

function ns.InitDB()
    if type(SalusNovusDB) ~= "table" then SalusNovusDB = {} end
    if type(SalusNovusDB.options) ~= "table" then SalusNovusDB.options = {} end
    MigrateChatFilterOff(SalusNovusDB.options)
    -- Health Bars 0.4.0-0.4.4 saved only showName; a name turned off there
    -- stays off (the namePos default came first and turned it back on: the sweep)
    local hb = SalusNovusDB.options.healthBars
    -- (once: CopyDefaults had already seeded namePos='inside' for anyone on
    -- 0.4.5+, so the nil-only test missed them -- the sweep)
    if type(hb) == "table" and hb.showName == false and (hb.namePos == nil or hb.namePos == "inside") then
        hb.namePos = "off"
    end
    if type(hb) == "table" then hb.showName = nil end   -- no UI writes it now: never read again
    -- "Scan when the AH opens" went off by default (Alex, 2026-10-06): a save
    -- from before gets it off once; turned back on, it stays on
    local au = SalusNovusDB.options.auction
    if type(au) == "table" and not au.autoScanOff1 then au.autoScan = false end
    CopyDefaults(ns.defaults, SalusNovusDB.options, true)
    SalusNovusDB.options.auction.autoScanOff1 = true
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
        if type(c) == "table" and type(c.r) == "number" and type(c.g) == "number" and type(c.b) == "number" then
            return c.r, c.g, c.b
        end
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
    local scale = (g and tonumber(g.scale)) or 100
    if not scale or scale ~= scale or scale <= 0 or scale > 500 then scale = 100 end
    return scale / 100
end

-- ---------------------------------------------------------------- anchors

-- Movable frames register here so one toggle can lock/unlock them all.
local movables = {}
ns.movables = movables            -- SnapMovable aligns against the other anchors

-- Unlock mode looks like EllesmereUI's (Alex, 2026-10-03): a dark slate box
-- over the whole anchor, a thin light edge, the anchor's name centred.
-- Modules keep toggling their own unlockBg / unlockLabel; those are made
-- invisible and their Show/Hide/SetShown drive this overlay instead.
local UNLOCK_NAMES = {
    barsPos = "Timer Bars", queuePos = "Ability Queue", previewPos = "Ability Preview",
    messagesPos = "Messages", healthPos = "Health Bars", remindersPos = "Reminders",
    sessionPos = "Session", campingPos = "Camping", dungeonQuestsPos = "Dungeon Quests",
}
function ns.UnlockOverlay(frame, name)
    if frame.unlockOverlay then return frame.unlockOverlay end
    local driver = frame.unlockBg or frame.unlockLabel
    if not driver then return nil end
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints()
    o:SetFrameLevel((frame:GetFrameLevel() or 0) + 20)
    o:EnableMouse(false)                          -- the drag belongs to the anchor
    o.bg = o:CreateTexture(nil, "BACKGROUND")
    o.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    o.bg:SetAllPoints()
    o.bg:SetVertexColor(0.10, 0.13, 0.17, 0.92)
    o.border = ns.CreateBorder(o)
    o.border:Layout(o, 1, -1)
    o.border:SetColor(0.70, 0.72, 0.78, 0.55)
    o.border:Show()
    o.label = o:CreateFontString(nil, "OVERLAY")
    ns.SetFontSafe(o.label, 12, "")
    o.label:SetPoint("CENTER")
    o.label:SetTextColor(0.92, 0.93, 0.95, 1)
    o.label:SetText(name or "")
    o:Hide()
    frame.unlockOverlay = o
    if frame.unlockBg then frame.unlockBg:SetAlpha(0) end
    if frame.unlockLabel then frame.unlockLabel:SetAlpha(0) end
    -- Our own texture/fontstring: wrapping its methods touches nothing of Blizzard's.
    local show, hide, setShown = driver.Show, driver.Hide, driver.SetShown
    driver.Show = function(self, ...) o:Show() return show(self, ...) end
    driver.Hide = function(self, ...) o:Hide() return hide(self, ...) end
    driver.SetShown = function(self, v, ...) o:SetShown(v and true or false) return setShown(self, v, ...) end
    o:SetShown(driver:IsShown() and true or false)
    return o
end

function ns.RegisterMovable(frame, saveKey, origin, restore)
    movables[frame] = saveKey or true
    if type(saveKey) == "string" and (frame.unlockBg or frame.unlockLabel) then
        local label = frame.unlockLabel and frame.unlockLabel:GetText()
        label = type(label) == "string" and label:gsub("%s*\194\183.*$", "") or nil
        ns.UnlockOverlay(frame, UNLOCK_NAMES[saveKey] or label)
    end
    -- the size at Build (every module registers right after sizing it): the
    -- default's origin is worked out from this, not a later content size (the sweep)
    frame.__nominalW = frame.__nominalW or frame:GetWidth()
    frame.__nominalH = frame.__nominalH or frame:GetHeight()
    frame.__origin = origin       -- function -> the growth-origin point
    frame.__restore = restore     -- function -> the module's RestorePosition (re-layout after a scale change)
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    -- know when it's being dragged: a pull locking (and hiding) it mid-drag
    -- left it moving and unsaved (the sweep)
    if not frame.__dragWrapped then
        frame.__dragWrapped = true
        local sm, st = frame.StartMoving, frame.StopMovingOrSizing
        frame.StartMoving = function(self, ...) self.__dragging = true return sm(self, ...) end
        frame.StopMovingOrSizing = function(self, ...) self.__dragging = nil return st(self, ...) end
        frame:HookScript("OnHide", function(self) ns.EndDrag(self) end)
    end
    -- the lock state now: one built after ApplyLocks ran in this pass stayed
    -- click-through in unlock mode (the sweep)
    if ns.CombatLocked and ns.CombatLocked(frame) then ns.locksPending = true
    elseif frame.EnableMouse then frame:EnableMouse(ns.db and ns.db.unlocked and true or false) end
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

ns._pendingSave = {}
function ns.SaveAnchor(frame, key)
    -- Only for a frame living on the screen: during an options preview the
    -- frame is parented to a page stage, and saving from there would write a
    -- spot inside that little box and rip the frame off the stage.
    if frame:GetParent() ~= UIParent then return end
    -- a protected frame (the camp panel) can't be re-anchored in combat: a
    -- drag that ended in combat is saved when it ends (the sweep)
    if ns.CombatLocked and ns.CombatLocked(frame) then ns._pendingSave[frame] = key return end
    local point = (frame.__origin and frame.__origin()) or "CENTER"
    local x, y, s = OriginXY(frame, point)
    if not x then return end
    SalusNovusDB[key] = { point = point, x = x, y = y, v = 2 }
    frame.__pin = nil                               -- the record rules from here
    -- Re-anchor from the record just written: a drag leaves the frame pinned
    -- wherever the drag put it, and SnapMovable pins by CENTER.
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "BOTTOMLEFT", x / s, y / s)
end

--- Re-pin `frame` by `point` where it stands, as an offset from UIParent's
-- CENTRE, writing nothing. At login the client still runs at UI scale 1
-- (UIParent 1365.33x768); the user's scale settles a moment later and
-- UIParent grows to, say, 1920x1080. A pin measured in ABSOLUTE UIParent
-- coordinates at that moment stays put and the frame ends up low and to
-- the left (Alex's Reminders anchor, 2026-09-23: exactly the small
-- screen's centre, in the big screen). A centre-relative pin rides along.
-- The pin is remembered on the frame (frame.__pin) for the session so a
-- later RestoreAnchor without a record (growth, preview, scale change)
-- keeps the growth origin where it was instead of re-deriving it from the
-- default corner (a down-growing stack would otherwise grow upwards).
local function PinFromCentre(frame, point)
    if frame:GetParent() ~= UIParent then return false end   -- on an options preview stage: not a screen spot
    local x, y, s = OriginXY(frame, point)
    if not x then return false end
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local dx, dy = x - sw / 2, y - sh / 2                -- UIParent units, unscaled
    frame.__pin = { point = point, dx = dx, dy = dy }
    frame:ClearAllPoints()
    frame:SetPoint(point, UIParent, "CENTER", dx / s, dy / s)
    return true
end

--- Call from a module's layout AFTER the frame has its final size. Keeps the
-- frame where it is and re-pins it by the right corner. NO RECORD IS NOT
-- "NOTHING TO DO" -- a fresh install must be re-pinned too (landmine 17),
-- but relative to the screen centre and WITHOUT writing a record: only the
-- user's own save (the drag mode) writes one. A user record pinned by the
-- wrong point is rewritten by the right one.
function ns.SyncAnchorOrigin(frame, key)
    local rec = SalusNovusDB and SalusNovusDB[key]
    local want = (frame.__origin and frame.__origin()) or "CENTER"
    if type(rec) == "table" then                    -- the user's record (v2, or legacy): rewrite by the right point
        if rec.v == 2 and rec.point == want then return end
        if not frame:GetLeft() then return end      -- not laid out yet
        ns.SaveAnchor(frame, key)
        return
    end
    if not frame:GetLeft() then return end          -- not laid out yet
    -- already pinned by this point: kept (re-measured from a stack the screen
    -- edge had pushed in, the origin crept for the session: the sweep)
    if frame.__pin and frame.__pin.point == want then return end
    PinFromCentre(frame, want)
end

--- Re-anchor from the saved record, or the default point + offset. Call
-- again after a scale change. Writes NOTHING: an anchor the user never
-- touched stays untouched.
--- `relPoint` (default: `defaultPoint`) is the point of UIParent the default
-- offset is measured from: the shipped defaults are Alex's own layout, read
-- from his saved positions and expressed from the screen CENTRE so they
-- hold at any resolution.
-- A frame with a secure child (the camping panel's item buttons) is itself
-- protected: in combat it can't be moved, shown or have its mouse toggled.
-- Those calls wait here and replay when combat ends (a pcall would not
-- help: the client blocks the action, it doesn't raise an error).
local deferredRestore, locksPending = {}, false
ns._deferredRestore = deferredRestore
local function CombatLocked(frame)
    local okC, c = pcall(InCombatLockdown)
    if not (okC and c) then return false end
    local okP, p = pcall(frame.IsProtected, frame)
    return okP and p == true
end
ns.CombatLocked = CombatLocked
function ns.ReplayCombatDeferred()
    for frame, a in pairs(deferredRestore) do
        deferredRestore[frame] = nil
        pcall(ns.RestoreAnchor, frame, a[1], a[2], a[3], a[4], a[5])
    end
    if locksPending or ns.locksPending then ns.locksPending = nil ns.ApplyLocks() end
    for frame, key in pairs(ns._pendingSave) do ns._pendingSave[frame] = nil ns.SaveAnchor(frame, key) end
end

--- The default's growth origin, from the default point and a FIXED size --
-- the module's one-row size (frame.__nominal) or the frame's size when first
-- placed -- never its height now: a stack of placeholders, a preview's
-- fakes or a Build size moved a never-dragged anchor between sessions and
-- on every scale change (the sweeps). Pinned centre-relative.
local function Frac(p)
    local fx = p:find("LEFT") and 0 or (p:find("RIGHT") and 1 or 0.5)
    local fy = p:find("BOTTOM") and 0 or (p:find("TOP") and 1 or 0.5)
    return fx, fy
end
local function DefaultPin(frame, defaultPoint, want)
    if frame:GetParent() ~= UIParent then return end
    local x, y, s = OriginXY(frame, defaultPoint)      -- where the default point sits (size doesn't move it)
    if not x then return end
    local nw, nh
    if frame.__nominal then nw, nh = frame.__nominal() end
    if not (nw and nh) then
        frame.__nominalW = frame.__nominalW or frame:GetWidth()
        frame.__nominalH = frame.__nominalH or frame:GetHeight()
        nw, nh = frame.__nominalW, frame.__nominalH
    end
    local ax, ay = Frac(defaultPoint)
    local bx, by = Frac(want)
    x, y = x + (bx - ax) * nw * s, y + (by - ay) * nh * s
    local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
    local pin = { point = want, dx = x - sw / 2, dy = y - sh / 2 }
    frame.__pin = pin
    frame:ClearAllPoints()
    frame:SetPoint(want, UIParent, "CENTER", pin.dx / s, pin.dy / s)
end

function ns.RestoreAnchor(frame, key, defaultPoint, dx, dy, relPoint)
    -- held by an options preview stage: its stop restores it (resetpos tore
    -- the live preview off the stage: the sweep)
    if frame:GetParent() ~= UIParent then return end
    if CombatLocked(frame) then
        deferredRestore[frame] = { key, defaultPoint, dx, dy, relPoint }
        return
    end
    deferredRestore[frame] = nil
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
    local want = frame.__origin and frame.__origin()
    local pin = frame.__pin
    if p and p.v == 2 and p.point and p.x and p.y then
        local s = ScaleRatio(frame)
        frame:SetPoint(p.point, UIParent, "BOTTOMLEFT", p.x / s, p.y / s)
    elseif not p and pin and (not want or pin.point == want) then
        -- this session's centre-relative pin (no record): the growth origin stays put
        local s = ScaleRatio(frame)
        frame:SetPoint(pin.point, UIParent, "CENTER", pin.dx / s, pin.dy / s)
    elseif p and p.point then
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        -- Offsets are screen pixels; SetPoint takes the frame's own scaled
        -- units, so divide by the scale like every other path here.
        local s0 = ScaleRatio(frame)
        frame:SetPoint(defaultPoint, UIParent, relPoint or defaultPoint, (dx or 0) / s0, (dy or 0) / s0)
        if want and want ~= defaultPoint then DefaultPin(frame, defaultPoint, want) end     -- never an absolute pin at login
        
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

function ns.AlignGrid() return gridFrame end          -- the probe reads the frame itself, not a global name

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
    -- Whole pixels (Alex, 2026-09-23: the grid "not all squares"). A 1-unit
    -- line CENTRED on its coordinate spans half of two pixel rows at half
    -- the alpha each and shows or vanishes by rounding (measured: lines at
    -- 27.5..28.5). Each line is one pixel thick and anchored by its edge on
    -- a pixel boundary; the centre lines two pixels.
    local pu = (ns.Theme and ns.Theme.PixelUnit and ns.Theme.PixelUnit(gridFrame)) or 1
    if not pu or pu <= 0 then pu = 1 end
    local function Px(v) return math.floor(v / pu + 0.5) * pu end
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
        local thick = (center and 2 or 1) * pu
        local edge = Px(pos) - (center and pu or 0)          -- the centre line straddles its coordinate by a pixel each side
        if vertical then
            t:SetWidth(thick)
            t:SetPoint("TOPLEFT", UIParent, "TOPLEFT", edge, 0)
            t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", edge, 0)
        else
            t:SetHeight(thick)
            t:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, edge)
            t:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", 0, edge)
        end
        -- The accent throughout (Alex): the centre lines strong, the rest faint.
        if center then t:SetVertexColor(ar, ag, ab, 0.7) else t:SetVertexColor(ar, ag, ab, 0.18) end
        t:Show()
    end
    for x = cx, w, size do Line(true, x, x == cx) end
    for x = cx - size, 0, -size do Line(true, x, false) end
    for y = cy, h, size do Line(false, y, y == cy) end
    for y = cy - size, 0, -size do Line(false, y, false) end
    gridFrame.size = size
    gridFrame:Show()
end

--- Snap after a drag: another anchor's centre/edges, the screen centre, or
-- the grid. Re-anchors by CENTER; the module's SavePosition then stores the
-- growth-origin point.
function ns.SnapMovable(frame)
    if CombatLocked(frame) then return end                -- a protected frame can't move in combat (the sweep)
    local _, _, snapOn, range = GridOpts()
    if not snapOn then return end
    -- the grid that is DRAWN (its options can change while unlocked: a frame
    -- snapped to lines nobody could see -- the sweep)
    local gridOn = gridFrame ~= nil and gridFrame:IsShown()
    local size = gridFrame and gridFrame.size or 32
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

--- A drag still going when the frame locks or hides: stopped, snapped and
-- saved like a drop.
function ns.EndDrag(frame)
    if not frame.__dragging then return end
    frame:StopMovingOrSizing()
    local key = movables[frame]
    if type(key) == "string" and frame:GetParent() == UIParent then
        ns.SnapMovable(frame)
        ns.SaveAnchor(frame, key)
    end
end

function ns.ApplyLocks()
    local unlocked = ns.db and ns.db.unlocked
    locksPending = false
    if not unlocked then for frame in pairs(movables) do ns.EndDrag(frame) end end
    for frame in pairs(movables) do
        if CombatLocked(frame) then locksPending = true
        elseif frame.EnableMouse then frame:EnableMouse(unlocked and true or false) end
    end
end
ns.RegisterApply(ns.ApplyLocks, "Frame locks")
-- the grid redrawn from its settings while unlocked (a change waited for the
-- next unlock, and frames snapped to the old grid: the sweep)
ns.RegisterApply(function()
    if ns.db and ns.db.unlocked and ns.ShowAlignGrid then ns.ShowAlignGrid(true) end
end, "Align grid")

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

-- Moves and mouse toggles a protected frame couldn't take in combat.
ns.On("PLAYER_REGEN_ENABLED", function() ns.ReplayCombatDeferred() end)

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
    msg = (type(msg) == "string" and msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
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

-- ---------------------------------------------------------- scale settling
-- The client applies the user's UI scale a moment after login. A frame's
-- reported position lags a layout pass behind that change while UIParent's
-- size updates at once, so an anchor laid out inside that window is pinned
-- from mixed measurements (Alex's Reminders, 2026-09-23: BOTTOM -> CENTER
-- (-277, -97), and -277 is half of 1920 - 1365). The client says when the
-- scale or the display changed: forget every session pin and lay every
-- anchor out again from clean numbers. Debounced: the events come in
-- bursts.
local relayoutPending
local function Relayout()
    if relayoutPending then return end
    relayoutPending = true
    C_Timer.After(0.1, function()
        relayoutPending = nil
        for f in pairs(ns.movables or {}) do
            f.__pin = nil
            -- a frame on an options preview stage stays there (it was pulled
            -- onto the screen: the sweep); its preview's stop restores it
            if f.__restore and f:GetParent() == UIParent then pcall(f.__restore) end
        end
        if ns.db then ns.ApplyAll() end
        if ns.Theme and ns.Theme.ResnapCheckBoxes then ns.Theme.ResnapCheckBoxes() end
        if ns.db and ns.db.unlocked and ns.ShowAlignGrid then ns.ShowAlignGrid(true) end   -- (drawn for the old size: the sweep)
    end)
end
ns.On("UI_SCALE_CHANGED", Relayout)
ns.On("DISPLAY_SIZE_CHANGED", Relayout)

