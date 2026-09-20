--[[ Salus Novus -- Boss Visualizer: one lane per ability, a mark at every cast.

MerkUI's Fight Lanes window (MerkUI/FightLanes.lua) on Salus Novus's own
log-mined data: bosses in the sidebar with their model portraits, a fixed
time axis over lanes that scroll, a cursor line that follows the mouse and
reads the time, zoom and pan, and a reminder form that opens where you
click. Placed reminders live on their own lane at the top.

Left behind from retail: the Encounter Journal walk (portraits come from
our creature cache), difficulties, seasons, phases and stage clocks, the
Abilities editor's colours, TTS. Opened between pulls, never in combat by
design, so the client reads here (names, icons, descriptions) are in the
clean window.
]]

local _, ns = ...
local T = ns.Theme

local W, H, SIDEBAR_W, HEADER_H = 1180, 720, 250, 64
local LABEL_W, LANE_H, AXIS_H, MODEL = 230, 48, 63, 52
local LANES_MAX = 300        -- lanes scroll past this; the abilities keep the rest
local QUESTION_ICON = 134400

local V = {}
ns.Visualizer = V

local win, shell
local state = { enc = nil, zoom = 1, offset = 0, openInst = nil, mode = "dungeons" }
V.state = state
local instRows, bossRows, laneRows = {}, {}, {}
V._lanes = laneRows          -- test seam
V._instRows, V._bossRows = instRows, bossRows   -- test seams
local form

-- ---------------------------------------------------------------- data

local function Fight()
    if not state.enc then return nil end
    return (ns.BossByEncounter(state.enc))
end
V.Fight = Fight

-- The window reopens where you left it.
local function Remember()
    if not SalusNovusDB then return end
    SalusNovusDB.visualizer = SalusNovusDB.visualizer or {}
    SalusNovusDB.visualizer.enc = state.enc
end
local function Remembered()
    local r = SalusNovusDB and SalusNovusDB.visualizer
    if type(r) ~= "table" or not r.enc then return nil end
    if not ns.BossByEncounter(r.enc) then return nil end      -- the data was rebuilt
    return r.enc
end

local function fmt(t) return string.format("%d:%02d", math.floor(t / 60), math.floor(t % 60)) end
-- Same, keeping tenths when there are any (the reminder form round-trips it).
local function fmtExact(t)
    local s = t % 60
    if math.abs(s - math.floor(s)) < 0.05 then return fmt(t) end
    -- %04.1f rounds, so 59.97 came out "0:60.0" and ParseTime read it back
    -- as 60 -- a minute boundary silently moved the reminder. Round FIRST.
    if s >= 59.95 then return fmt(t + 0.05) end
    return string.format("%d:%04.1f", math.floor(t / 60), s)
end
V.fmt, V.fmtExact = fmt, fmtExact

local function ParseTime(s)
    if type(s) ~= "string" then return nil end
    local m, sec = s:match("^%s*(%d+):(%d+%.?%d*)%s*$")
    if m then return tonumber(m) * 60 + tonumber(sec) end
    -- Plain digits only: tonumber would also take "1e400" (inf), "0x1f"
    -- and "-5", and a negative or infinite time schedules before the pull
    -- or never shows.
    local bare = s:match("^%s*(%d+%.?%d*)%s*$")
    return bare and tonumber(bare) or nil
end
V.ParseTime = ParseTime

-- ----------------------------------------------------------- spell text

local pendingLoads = false
local spellEv = CreateFrame("Frame")
pcall(spellEv.RegisterEvent, spellEv, "SPELL_DATA_LOAD_RESULT")

-- Asked once per session: an id the client cannot load answers with
-- success=false and stays uncached, and re-asking on every answer would
-- re-render the panel forever.
local requested = {}
local function RequestSpell(id)
    if requested[id] then return end
    if C_Spell and C_Spell.RequestLoadSpellData then
        requested[id] = true
        pcall(C_Spell.RequestLoadSpellData, id)
        pendingLoads = true
    end
end

local function SpellName(id, fallback)
    if not id or ns.IsSecret(id) then return fallback or "?" end
    if C_Spell and C_Spell.GetSpellName then
        local ok, nm = pcall(C_Spell.GetSpellName, id)
        if ok and type(nm) == "string" and nm ~= "" and not ns.IsSecret(nm) then return nm end
    end
    if not (C_Spell and C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(id)) then RequestSpell(id) end
    return fallback or ("spell " .. id)
end

--- description, state: "ok" | "loading" | "none"
local function SpellDesc(id)
    if not id or ns.IsSecret(id) or not C_Spell then return nil, "none" end
    local ok, d = pcall(C_Spell.GetSpellDescription, id)
    if ok and type(d) == "string" and d ~= "" and not ns.IsSecret(d) then return d, "ok" end
    if C_Spell.IsSpellDataCached and C_Spell.IsSpellDataCached(id) then return nil, "none" end
    RequestSpell(id)
    return nil, "loading"
end

local function SpellIcon(id)
    if id and id ~= 0 and C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, id)
        if ok and tex and not ns.IsSecret(tex) then return tex end
    end
    return nil
end

-- ------------------------------------------------------------ geometry
-- seconds <-> x inside the track

local function TrackWidth() return win.trackW or 600 end
local function FightEnd(f) return ns.Schedule.FightEnd(f) end
local function Span() return FightEnd(Fight()) / state.zoom end
local function X(t) return (t - state.offset) / Span() * TrackWidth() end
local function Visible(t)
    local x = X(t)
    return x >= -2 and x <= TrackWidth() + 2, x
end
-- Cull a mark on its INTERVAL, not on its start point: a mark's width is its
-- cast length and its band reaches +-spread around it, so point-culling made
-- long effects disappear exactly when they mattered.
local function VisibleSpan(t, len, halfSpread)
    local x = X(t)
    local scale = TrackWidth() / Span()
    local right = x + math.max(len or 0, halfSpread or 0) * scale
    local left  = x - (halfSpread or 0) * scale
    return right >= -2 and left <= TrackWidth() + 2, x
end
local function ClampOffset()
    local len = FightEnd(Fight())
    state.offset = math.max(0, math.min(math.max(0, len - Span()), state.offset))
end
V.X, V.Span, V.FightEnd, V.VisibleSpan, V.TrackWidth = X, Span, function() return FightEnd(Fight()) end, VisibleSpan, TrackWidth

-- ------------------------------------------------------- small widgets

-- Square checkbox that fills with the accent when on.
local function MakeCheck(parent, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(18, 18)
    b.bg = T.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.06)
    b.bg:SetAllPoints()
    b.fill = T.SolidTex(b, "ARTWORK", 1, 1, 1, 1)
    b.fill:SetPoint("TOPLEFT", 3, -3)
    b.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    b.border = ns.CreateBorder(b)
    b.border:Layout(b, 1, 0)
    b.border:SetColor(1, 1, 1, 0.25)
    b.border:Show()
    b.text = T.MakeText(b, 12, T.TEXT)
    b.text:SetPoint("LEFT", b, "RIGHT", 8, 0)
    b.text:SetText(label)
    -- Only widen the hit rect when there IS a label to click; the colour
    -- checkbox has none and was swallowing clicks meant for the swatch.
    local lw = b.text:GetStringWidth() or 0
    if b.SetHitRectInsets then b:SetHitRectInsets(0, lw > 0 and -(lw + 10) or 0, 0, 0) end
    b.checked = false
    function b:SetChecked(v)
        self.checked = v and true or false
        local r, g, bb = T.Accent()
        if self.checked then self.fill:SetVertexColor(r, g, bb, 1); self.fill:Show(); self.border:SetColor(r, g, bb, 0.9)
        else self.fill:Hide(); self.border:SetColor(1, 1, 1, 0.25) end
    end
    function b:GetChecked() return self.checked end
    b:SetScript("OnClick", function(self)
        if self.enabledState == false then return end
        self:SetChecked(not self.checked)
        if self.onChange then self.onChange(self.checked) end
    end)
    b:SetChecked(false)
    return b
end

-- Segmented choice: the picked segment is filled with the accent.
local function MakeSegment(parent, label)
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(26)
    b.bg = T.SolidTex(b, "BACKGROUND", 1, 1, 1, 0.06)
    b.bg:SetAllPoints()
    b.text = T.MakeText(b, 13, T.TEXT_MUTE)
    b.text:SetPoint("CENTER", 0, 0)
    b.text:SetText(label)
    b:SetWidth(math.floor((b.text:GetStringWidth() or 40) + 28))
    function b:SetActive(on)
        local r, g, bb = T.Accent()
        if on then
            local tr, tg, tb = T.OnAccent()
            self.bg:SetVertexColor(r, g, bb, 0.9); self.text:SetTextColor(tr, tg, tb, 1)
        else self.bg:SetVertexColor(1, 1, 1, 0.06); self.text:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1) end
        self.active = on
    end
    b:SetScript("OnEnter", function(self) if not self.active then self.bg:SetVertexColor(1, 1, 1, 0.12) end end)
    b:SetScript("OnLeave", function(self) self:SetActive(self.active) end)
    b:SetActive(false)
    return b
end

-- A small colour swatch; clicking opens the game's picker. `snapshot`
-- returns a closure that puts everything back on Cancel: routing Cancel
-- through `set` also TICKED the override checkbox, pinning the reminder to
-- a hard-coded colour that looked like the default.
local function MakeSwatch(parent, get, set, snapshot)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(26, 20)
    b.fill = T.SolidTex(b, "ARTWORK", 1, 1, 1, 1)
    b.fill:SetAllPoints()
    b.border = ns.CreateBorder(b)
    b.border:Layout(b, 1, 0)
    b.border:SetColor(1, 1, 1, 0.25)
    b.border:Show()
    function b:Paint()
        local c = get() or { r = 1, g = 0.82, b = 0 }
        self.fill:SetVertexColor(c.r or 1, c.g or 0.82, c.b or 0, 1)
    end
    b:SetScript("OnClick", function(self)
        local c = get() or { r = 1, g = 0.82, b = 0 }
        local pr, pg, pb = c.r or 1, c.g or 0.82, c.b or 0
        local restore = snapshot and snapshot()
        local function Put(rr, gg, bb) set(rr, gg, bb); self:Paint() end
        T.OpenColorPicker({ r = pr, g = pg, b = pb }, Put, function()
            if restore then restore() else Put(pr, pg, pb) end
            self:Paint()
        end)
    end)
    return b
end

-- Icons offered in the picker: the player's own spellbook, guarded --
-- presence is not function on this client.
local iconChoices
ns.On("PLAYER_SPECIALIZATION_CHANGED", function() iconChoices = nil end)
ns.On("PLAYER_TALENT_UPDATE", function() iconChoices = nil end)

local function IconChoices()
    if iconChoices then return iconChoices end
    iconChoices = {}
    local SB = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    if SB and bank and SB.GetNumSpellBookSkillLines and SB.GetSpellBookSkillLineInfo and SB.GetSpellBookItemInfo then
        local seen = {}
        local okN, lines = pcall(SB.GetNumSpellBookSkillLines)
        for i = 1, (okN and tonumber(lines) or 0) do
            local okL, info = pcall(SB.GetSpellBookSkillLineInfo, i)
            if okL and type(info) == "table" and info.itemIndexOffset and info.numSpellBookItems then
                for j = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
                    local okI, item = pcall(SB.GetSpellBookItemInfo, j, bank)
                    if okI and type(item) == "table" and item.spellID and item.iconID
                        and not seen[item.spellID] and not ns.IsSecret(item.iconID) and not ns.IsSecret(item.spellID) then
                        seen[item.spellID] = true
                        iconChoices[#iconChoices + 1] = { id = item.spellID, icon = item.iconID, name = item.name }
                    end
                    if #iconChoices >= 48 then break end
                end
            end
            if #iconChoices >= 48 then break end
        end
    end
    return iconChoices
end

-- ---------------------------------------------------------- reminder form

local Refresh   -- forward
local TRIGGER_LABEL = { pull = "on the pull", time = "at a time", cast = "when the boss casts", emote = "when the boss yells" }

local function BuildForm()
    form = CreateFrame("Frame", nil, win)
    form:SetSize(400, 348)
    form:SetFrameLevel(win:GetFrameLevel() + 40)
    form:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -24, 60)
    form.bg = T.SolidTex(form, "BACKGROUND", T.SIDEBAR[1], T.SIDEBAR[2], T.SIDEBAR[3], 0.99)
    form.bg:SetAllPoints()
    form.border = ns.CreateBorder(form)
    form.border:Layout(form, 1, 0)
    form.border:SetColor(1, 1, 1, 0.25)
    form.border:Show()
    form:EnableMouse(true)
    form:Hide()
    V.form = form

    form.title = T.MakeText(form, 14, T.TEXT)
    form.title:SetPoint("TOPLEFT", 14, -12)
    form.title:SetWidth(320)
    form.title:SetJustifyH("LEFT")
    form.title:SetWordWrap(false)
    form.icon = form:CreateTexture(nil, "ARTWORK")
    form.icon:SetSize(24, 24)
    form.icon:SetPoint("TOPRIGHT", -14, -10)
    form.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local function Cap(text, x, y)
        local c = T.MakeText(form, 11, T.TEXT_MUTE)
        c:SetPoint("TOPLEFT", x, y)
        c:SetText(text)
        return c
    end
    Cap("TEXT (what shows)", 14, -40)
    form.text = T.MakeEditBox(form, 352)
    form.text:SetPoint("TOPLEFT", 14, -54)

    -- Every kind of reminder is made here (Alex: only on the visualizer):
    -- on the pull, at a time, when the boss casts, when the boss yells.
    Cap("TRIGGER", 14, -88)
    form.trigger = "time"
    form.triggerButtons = {}
    local prevSeg
    for i, def in ipairs({ { "pull", "On pull" }, { "time", "At time" }, { "cast", "Boss casts" }, { "emote", "Boss yells" } }) do
        local b = MakeSegment(form, def[2])
        b:SetHeight(24)
        if prevSeg then b:SetPoint("LEFT", prevSeg, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 14, -102) end
        b.value = def[1]
        b:SetScript("OnClick", function()
            form.trigger = def[1]
            form.LayoutTrigger()
        end)
        form.triggerButtons[i] = b
        prevSeg = b
    end

    form.atCap = Cap("AT", 14, -136)
    form.at = T.MakeEditBox(form, 70)
    form.at:SetPoint("TOPLEFT", 14, -150)
    form.atNote = T.MakeText(form, 11, T.TEXT_MUTE)
    form.atNote:SetPoint("LEFT", form.at, "RIGHT", 8, 0)
    form.atNote:SetWidth(120)
    form.atNote:SetJustifyH("LEFT")
    -- The yell box sits where AT does; only one of them shows.
    form.wordCap = Cap("YELL CONTAINS", 14, -136)
    form.word = T.MakeEditBox(form, 190)
    form.word:SetPoint("TOPLEFT", 14, -150)

    form.leadCap = Cap("COUNT DOWN", 224, -136)
    form.lead = T.MakeEditBox(form, 50)
    form.lead:SetPoint("TOPLEFT", 224, -150)
    form.leadNote = T.MakeText(form, 11, T.TEXT_MUTE)
    form.leadNote:SetPoint("LEFT", form.lead, "RIGHT", 6, 0)
    form.leadNote:SetText("s before")

    function form.LayoutTrigger()
        local t = form.trigger
        for _, b in ipairs(form.triggerButtons) do b:SetActive(b.value == t) end
        local timed, yell = (t == "time"), (t == "emote")
        form.atCap:SetShown(timed); form.at:SetShown(timed); form.atNote:SetShown(timed)
        form.wordCap:SetShown(yell); form.word:SetShown(yell)
        form.leadCap:SetShown(timed); form.lead:SetShown(timed); form.leadNote:SetShown(timed)
    end

    -- How this one reminder looks. Blank or unticked = follow the anchor's
    -- settings on the Reminders page.
    Cap("COLOR", 14, -188)
    form.useColor = MakeCheck(form, "")
    form.useColor:SetPoint("TOPLEFT", 14, -204)
    form.swatch = MakeSwatch(form,
        function() return form.colorValue end,
        function(r, g, b)
            form.colorValue = { r = r, g = g, b = b }
            form.useColor:SetChecked(true)
        end,
        function()
            local prev, wasOn = form.colorValue, form.useColor:GetChecked() and true or false
            return function()
                form.colorValue = prev
                form.useColor:SetChecked(wasOn)
            end
        end)
    form.swatch:SetPoint("LEFT", form.useColor, "RIGHT", 8, 0)
    form.useColor.onChange = function(on)
        if on and not form.colorValue then
            local d = ns.db.reminders.color or {}
            form.colorValue = { r = d.r or 1, g = d.g or 0.82, b = d.b or 0 }
        end
        form.swatch:Paint()
    end

    Cap("SIZE", 118, -188)
    form.size = T.MakeEditBox(form, 44)
    form.size:SetPoint("TOPLEFT", 118, -202)

    Cap("HOLD", 180, -188)
    form.hold = T.MakeEditBox(form, 44)
    form.hold:SetPoint("TOPLEFT", 180, -202)

    Cap("ICON", 242, -188)
    form.iconBtn = CreateFrame("Button", nil, form)
    form.iconBtn:SetSize(26, 26)
    form.iconBtn:SetPoint("TOPLEFT", 242, -202)
    form.iconBtn.tex = form.iconBtn:CreateTexture(nil, "ARTWORK")
    form.iconBtn.tex:SetAllPoints()
    form.iconBtn.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    form.iconBtn.hl = T.SolidTex(form.iconBtn, "HIGHLIGHT", 1, 1, 1, 0.25)
    form.iconBtn.hl:SetAllPoints()
    -- CreateBorder memoises per parent, so the button gets a holder of its
    -- own rather than stealing the form's four edge textures.
    local iconHolder = CreateFrame("Frame", nil, form.iconBtn)
    iconHolder:SetAllPoints()
    form.iconBtn.brd = ns.CreateBorder(iconHolder)
    form.iconBtn.brd:Layout(iconHolder, 1, 0)
    form.iconBtn.brd:SetColor(1, 1, 1, 0.25)
    form.iconBtn.brd:Show()
    form.iconNote = T.MakeText(form, 11, T.TEXT_MUTE)
    form.iconNote:SetPoint("LEFT", form.iconBtn, "RIGHT", 8, 0)
    form.iconNote:SetWidth(96)
    form.iconNote:SetJustifyH("LEFT")
    form.iconNote:SetWordWrap(false)

    local lookNote = T.MakeText(form, 11, T.TEXT_MUTE)
    lookNote:SetPoint("TOPLEFT", 14, -236)
    lookNote:SetWidth(372)
    lookNote:SetJustifyH("LEFT")
    lookNote:SetText("Blank size and hold follow the Reminders page.")

    form.sound = MakeCheck(form, "Raid-warning sound when it lands")
    form.sound:SetPoint("TOPLEFT", 14, -258)

    -- Save / Cancel sit bottom RIGHT, Cancel outermost (Alex); Remove,
    -- shown only for an existing reminder, takes the bottom left.
    form.cancel = T.MakeButton(form)
    form.cancel:SetSize(80, 26)
    form.cancel:SetPoint("BOTTOMRIGHT", -14, 12)
    form.cancel:SetText("Cancel")
    form.save = T.MakeButton(form)
    form.save:SetSize(90, 26)
    form.save:SetPoint("RIGHT", form.cancel, "LEFT", -8, 0)
    form.save:SetText("Save")
    form.delete = T.MakeButton(form)
    form.delete:SetSize(90, 26)
    form.delete:SetPoint("BOTTOMLEFT", 14, 12)
    form.delete:SetText("Remove")

    -- Icon picker: the ability's own icon, none, then the player's spells.
    -- 10 columns x at most 5 rows: the form sits 60 up from the window's
    -- bottom, so a taller grid would draw above the window.
    form.picker = CreateFrame("Frame", nil, form)
    form.picker:SetPoint("BOTTOMRIGHT", form, "TOPRIGHT", 0, 6)
    form.picker:SetSize(10 * 30 + 16, 40)
    form.picker:SetFrameLevel(form:GetFrameLevel() + 10)
    form.picker.bg = T.SolidTex(form.picker, "BACKGROUND", T.SIDEBAR[1], T.SIDEBAR[2], T.SIDEBAR[3], 0.99)
    form.picker.bg:SetAllPoints()
    form.picker.border = ns.CreateBorder(form.picker)
    form.picker.border:Layout(form.picker, 1, 0)
    form.picker.border:SetColor(1, 1, 1, 0.25)
    form.picker.border:Show()
    form.picker:EnableMouse(true)
    form.picker:Hide()
    form.picker.cells = {}

    local function SetIcon(id)
        form.iconValue = id
        local tex = id and id ~= 0 and SpellIcon(id)
        form.iconBtn.tex:SetTexture(tex or QUESTION_ICON)
        if form.iconBtn.tex.SetDesaturated then form.iconBtn.tex:SetDesaturated(not tex) end
        if id == 0 then
            form.iconNote:SetText("none")
        elseif id and id ~= form.spellId then
            form.iconNote:SetText(SpellName(id, "chosen"))
        else
            form.iconNote:SetText("the ability's")
        end
    end
    form.SetIcon = SetIcon

    local function FillPicker()
        local list = {}
        if form.spellId then list[#list + 1] = { id = form.spellId, label = "The ability's own icon" } end
        list[#list + 1] = { id = 0, label = "No icon" }
        for _, c in ipairs(IconChoices()) do
            list[#list + 1] = { id = c.id, icon = c.icon, label = c.name }
        end
        local cols = 10
        for i = 1, math.min(#list, cols * 5) do
            local item = list[i]
            local cell = form.picker.cells[i]
            if not cell then
                cell = CreateFrame("Button", nil, form.picker)
                cell:SetSize(26, 26)
                cell.tex = cell:CreateTexture(nil, "ARTWORK")
                cell.tex:SetAllPoints()
                cell.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                cell.hl = T.SolidTex(cell, "HIGHLIGHT", 1, 1, 1, 0.3)
                cell.hl:SetAllPoints()
                -- No tooltips (Alex); the icon's name shows in the note
                -- beside the button once picked.
                cell:SetScript("OnClick", function(self)
                    SetIcon(self.value)
                    form.picker:Hide()
                end)
                form.picker.cells[i] = cell
            end
            local row, col = math.floor((i - 1) / cols), (i - 1) % cols
            cell:ClearAllPoints()
            cell:SetPoint("TOPLEFT", form.picker, "TOPLEFT", 8 + col * 30, -8 - row * 30)
            local tex = item.icon or (item.id ~= 0 and SpellIcon(item.id))
            cell.tex:SetTexture(tex or QUESTION_ICON)
            if cell.tex.SetDesaturated then cell.tex:SetDesaturated(not tex) end
            cell.label = item.label
            cell.value = item.id
            cell:Show()
        end
        local shown = math.min(#list, cols * 5)
        for i = shown + 1, #form.picker.cells do form.picker.cells[i]:Hide() end
        form.picker:SetHeight(16 + math.max(1, math.ceil(shown / cols)) * 30)
    end

    form.iconBtn:SetScript("OnClick", function()
        if form.picker:IsShown() then form.picker:Hide(); return end
        FillPicker()
        form.picker:Show()
    end)

    function form.UpdateAtNote()
        form.atNote:SetText("m:ss from pull")
    end
    form.at:HookScript("OnTextChanged", form.UpdateAtNote)

    form.cancel:SetScript("OnClick", function() form:Hide() end)
    form.save:SetScript("OnClick", function()
        local f = Fight()
        if not f then return end
        local r = form.editing or {}
        local trig = form.trigger or "time"
        local t = ParseTime(form.at:GetText())
        if trig == "time" and not t then
            -- An empty or unparseable AT box used to make Save a dead button.
            form.atNote:SetText("|cffff6666need a time, like 2:30|r")
            return
        end
        if trig == "time" and t > FightEnd(f) then
            -- Past the axis it would be saved but never drawn, so never
            -- editable again from here.
            form.atNote:SetText("|cffff6666the fight ends at " .. fmt(FightEnd(f)) .. "|r")
            return
        end
        local word = (form.word:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if trig == "emote" and word == "" then
            form.wordCap:SetText("|cffff6666YELL CONTAINS -- needs a word|r")
            return
        end
        form.wordCap:SetText("YELL CONTAINS")
        local text = form.text:GetText()
        if text == "" then text = form.abilityName or "Reminder" end
        r.text = text
        r.trigger = trig
        if trig == "time" then r.arg = t
        elseif trig == "emote" then r.arg = word
        else r.arg = nil end
        -- Clamped to the SAME range the arming code uses (0..300), or the
        -- stored number and the effective one disagree silently.
        r.lead = math.max(0, math.min(300, tonumber(form.lead:GetText()) or (ns.db.reminders.lead or 5)))
        r.spellId = form.spellId
        r.sound = form.sound:GetChecked() and true or false
        r.color = form.useColor:GetChecked() and form.colorValue or nil
        local sz, hd = tonumber(form.size:GetText()), tonumber(form.hold:GetText())
        r.size = sz and math.max(8, math.min(72, sz)) or nil
        r.hold = hd and math.max(0.5, math.min(60, hd)) or nil
        r.icon = form.iconValue
        if r.icon == nil then r.icon = form.spellId end
        if form.editing then
            -- Cancel first: the old timing is still armed. Then re-arm.
            if r.id then ns.ReminderCancel(r.id) end
        else
            ns.ReminderAdd(state.enc, r)
        end
        -- Arm BOTH paths: a reminder created during a live pull must fire
        -- for the fight you are placing it during. No-ops outside a pull.
        if r.enabled ~= false then ns.ReminderRearm(r) end
        form:Hide()
        Refresh()
    end)
    form.delete:SetScript("OnClick", function()
        -- Cancel BEFORE removing: ReminderCancel also retracts the line the
        -- cue may already be showing, and it needs the id to do it.
        if form.editing and form.editing.id then
            ns.ReminderCancel(form.editing.id)
            ns.ReminderRemove(state.enc, form.editing.id)
        end
        form:Hide()
        Refresh()
    end)
end

local function OpenForm(t, spellId, abilityName, existing)
    if not form then BuildForm() end
    local f = Fight()
    if not f then return end
    form.editing = existing
    form.spellId = spellId
    form.abilityName = abilityName
    form.title:SetText(existing and "Edit reminder" or (abilityName and ("Reminder for " .. abilityName) or "New reminder"))
    local tex = SpellIcon(spellId)
    if tex then form.icon:SetTexture(tex); form.icon:Show() else form.icon:Hide() end
    if existing then
        form.trigger = existing.trigger or "time"
        form.text:SetText(existing.text or "")
        form.at:SetText(existing.trigger == "time" and fmtExact(tonumber(existing.arg) or 0) or fmtExact(t or 0))
        form.word:SetText(existing.trigger == "emote" and tostring(existing.arg or "") or "")
        form.lead:SetText(tostring(existing.lead or ns.db.reminders.lead or 5))
        form.sound:SetChecked(existing.sound and true or false)
        form.size:SetText(existing.size and tostring(existing.size) or "")
        form.hold:SetText(existing.hold and tostring(existing.hold) or "")
        form.colorValue = existing.color
        form.useColor:SetChecked(existing.color ~= nil)
        form.SetIcon(existing.icon or spellId)
        form.delete:Show()
    else
        form.trigger = "time"
        form.text:SetText(abilityName and (abilityName .. " soon") or "")
        form.at:SetText(fmtExact(t))
        form.word:SetText("")
        form.lead:SetText(tostring(ns.db.reminders.lead or 5))
        form.sound:SetChecked(true)
        form.size:SetText("")
        form.hold:SetText("")
        form.colorValue = nil
        form.useColor:SetChecked(false)
        form.SetIcon(spellId)
        form.delete:Hide()
    end
    form.wordCap:SetText("YELL CONTAINS")
    form.LayoutTrigger()
    form.picker:Hide()
    form.swatch:Paint()
    form.UpdateAtNote()
    form:Show()
    form.text:SetFocus()
    form.text:HighlightText()
end
V.OpenForm = OpenForm

-- ---------------------------------------------------------------- window

local function Pool(list, i, make)
    local f = list[i]
    if not f then f = make(); list[i] = f end
    return f
end

-- Fight time under the mouse, and the x within the track.
local function CursorTime(frameForScale)
    local x = select(1, GetCursorPosition()) / frameForScale:GetEffectiveScale() - win.axis:GetLeft()
    return math.max(0, state.offset + x / TrackWidth() * Span()), x
end
V.CursorTime = CursorTime

local function ShowCursor(frameForScale)
    local t, x = CursorTime(frameForScale)
    if x < 0 or x > TrackWidth() then win.cursor:Hide(); win.cursorLabel:Hide(); return nil end
    win.cursor:ClearAllPoints()
    -- TOP and BOTTOM each fix the centre, so x would be set twice:
    -- LEFT-anchored on both ends instead.
    win.cursor:SetPoint("TOPLEFT", win.axis, "TOPLEFT", x, 0)
    win.cursor:SetPoint("BOTTOMLEFT", win.lanes, "BOTTOMLEFT", x + LABEL_W, 0)
    win.cursor:Show()
    win.cursorLabel:ClearAllPoints()
    win.cursorLabel:SetPoint("BOTTOM", win.axis, "TOPLEFT", x, 2)
    win.cursorLabel:SetText(fmt(t))
    win.cursorLabel:Show()
    return t
end
V.ShowCursor = ShowCursor
local function HideCursor()
    win.cursor:Hide(); win.cursorLabel:Hide(); win.hover:SetText("")
end

-- The description panel under the lanes lists EVERY ability of the shown
-- boss -- icon, name and the client's description -- the moment the boss
-- opens (Alex). Rows are pooled; a description that has not loaded reads
-- "loading..." and fills in when the client answers.
local RenderDesc   -- defined below; the cards' click handlers call it
local EDIT_H = 118 -- the open editor under a card

-- The editor a card opens into: rename, colour, roles, and which anchors
-- the ability goes to (Abilities.lua). Every control writes straight to
-- the store and re-renders; nothing is buffered.
local function MakeCardEditor(row)
    local A = ns.Abilities
    local ed = CreateFrame("Frame", nil, row)
    ed:SetPoint("TOPLEFT", row, "TOPLEFT", 12, 0)     -- re-pinned per render
    ed:SetPoint("RIGHT", row, "RIGHT", -12, 0)
    ed:SetHeight(EDIT_H)
    ed:Hide()
    -- The ability the editor was OPENED for, captured by Sync: rows are
    -- pooled by index, so row.spellID changes under a boss switch while a
    -- focused name box is still armed.
    local function key() return ed.spellID end
    local function Rerender() RenderDesc(Fight()) end

    ed.nameCap = T.MakeText(ed, 11, T.TEXT_MUTE)
    ed.nameCap:SetPoint("TOPLEFT", 0, -6)
    ed.nameCap:SetText("NAME")
    ed.name = T.MakeEditBox(ed, 220)
    ed.name:SetPoint("LEFT", ed.nameCap, "RIGHT", 10, 0)
    local function Commit(self)
        local k = key()
        if not k then return end
        local t = (self:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if t == "" or t == row.realName then t = nil end
        A.Set(k, "rename", t)
        Rerender()
    end
    -- Enter drops focus (the box's own script) and the focus loss commits:
    -- hooking both committed twice per keypress.
    ed.name:HookScript("OnEditFocusLost", Commit)

    -- One box: unticked = the anchors' default colour; ticked = a custom
    -- colour, with the swatch beside it opening the picker (Alex).
    ed.useColor = T.MakeLabelledCheckBox(ed, "Custom color", 16)
    ed.useColor:SetPoint("LEFT", ed.name, "RIGHT", 24, 0)
    ed.swatch = CreateFrame("Button", nil, ed)
    ed.swatch:SetSize(22, 22)
    ed.swatch:SetPoint("LEFT", ed.useColor.label, "RIGHT", 10, 0)
    ed.swatch.fill = T.SolidTex(ed.swatch, "ARTWORK", 1, 1, 1, 1)
    ed.swatch.fill:SetAllPoints()
    ed.swatch.border = ns.CreateBorder(ed.swatch)
    ed.swatch.border:Layout(ed.swatch, 1, 0)
    ed.swatch.border:SetColor(1, 1, 1, 0.25)
    ed.swatch.border:Show()
    ed.useColor:HookScript("OnClick", function(self)
        local k = key()
        if not k then return end
        if self:GetChecked() then
            local r, g, b = T.Accent()
            A.Set(k, "color", { r = r, g = g, b = b })
        else
            A.Set(k, "color", nil)
        end
        Rerender()
    end)
    ed.swatch:SetScript("OnClick", function()
        local k = key()
        if not k then return end
        local r, g, b = A.Color(k)
        if not r then r, g, b = T.Accent() end
        local prev = { r = r, g = g, b = b }
        T.OpenColorPicker(prev, function(nr, ng, nb)
            A.Set(k, "color", { r = nr, g = ng, b = nb })
            Rerender()
        end, function()
            A.Set(k, "color", prev)
            Rerender()
        end)
    end)

    ed.rolesCap = T.MakeText(ed, 11, T.TEXT_MUTE)
    ed.rolesCap:SetPoint("TOPLEFT", ed.nameCap, "BOTTOMLEFT", 0, -22)
    ed.rolesCap:SetText("ROLES")
    ed.roles = {}
    local prev
    for _, r in ipairs({ { "tank", "Tank" }, { "healer", "Healer" }, { "dps", "DPS" } }) do
        local cb = T.MakeLabelledCheckBox(ed, r[2], 16)
        if prev then cb:SetPoint("LEFT", prev.label, "RIGHT", 18, 0)
        else cb:SetPoint("LEFT", ed.rolesCap, "RIGHT", 10, 0) end
        cb:HookScript("OnClick", function()
            local k = key()
            if k then A.ToggleRole(k, r[1]); Rerender() end
        end)
        ed.roles[r[1]] = cb
        prev = cb
    end

    ed.showCap = T.MakeText(ed, 11, T.TEXT_MUTE)
    ed.showCap:SetPoint("TOPLEFT", ed.rolesCap, "BOTTOMLEFT", 0, -22)
    ed.showCap:SetText("SHOW ON")
    ed.healthRoute = T.MakeLabelledCheckBox(ed, "Health Bars", 16)
    ed.healthRoute:SetPoint("LEFT", ed.showCap, "RIGHT", 10, 0)
    ed.healthRoute:HookScript("OnClick", function(self)
        local k = key()
        if k then A.SetRoute(k, "health", self:GetChecked()); Rerender() end
    end)
    ed.routes = {}
    prev = nil
    for _, r in ipairs({ { "queue", "Ability Queue" }, { "preview", "Ability Preview" }, { "messages", "Messages" } }) do
        local cb = T.MakeLabelledCheckBox(ed, r[2], 16)
        if prev then cb:SetPoint("LEFT", prev.label, "RIGHT", 18, 0)
        else cb:SetPoint("LEFT", ed.showCap, "RIGHT", 10, 0) end
        cb:HookScript("OnClick", function(self)
            local k = key()
            if k then A.SetRoute(k, r[1], self:GetChecked()); Rerender() end
        end)
        ed.routes[r[1]] = cb
        prev = cb
    end

    ed.reset = T.MakeButton(ed)
    ed.reset:SetSize(64, 22)
    ed.reset:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", 0, 6)
    ed.reset:SetText("Reset")
    ed.reset:SetScript("OnClick", function()
        local k = key()
        if k then A.Reset(k); Rerender() end
    end)

    --- Read the store into the controls.
    function ed:Sync()
        self.spellID = row.spellID
        local k = key()
        if not k then return end
        self.name:SetText(A.Rename(k) or row.realName or "")
        local r, g, b = A.Color(k)
        self.useColor:SetChecked(r ~= nil)
        self.swatch:SetShown(r ~= nil)     -- the swatch only exists for a custom colour
        if r then self.swatch.fill:SetVertexColor(r, g, b, 1) end
        for role, cb in pairs(self.roles) do cb:SetChecked(A.HasRole(k, role)) end
        local timed = not row.health
        for anchor, cb in pairs(self.routes) do
            local v = A.Route(k, anchor)
            if v == nil then v = A.ROUTE_DEFAULT[anchor] ~= false end
            cb:SetChecked(v)
            cb:SetShown(timed)
        end
        local hv = A.Route(k, "health")
        if hv == nil then hv = true end
        self.healthRoute:SetChecked(hv)
        self.healthRoute:SetShown(not timed)
    end
    return ed
end

local function DescRow(i)
    local content = win.descScroll.child
    local row = win.descRows[i]
    if row then return row end
    -- The card look (border inside the rect, accent edge, hover pop), the
    -- same as the Dungeon Codex's ability cards.
    row = T.MakeCard(content)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(36, 36)
    row.icon:SetPoint("TOPLEFT", 10, -8)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local holder = CreateFrame("Frame", nil, row)
    holder:SetAllPoints(row.icon)
    local ib = ns.CreateBorder(holder)
    ib:Layout(holder, 1, 0)
    ib:SetColor(0, 0, 0, 0.8)
    ib:Show()
    row.name = T.MakeText(row, 13, T.TEXT)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 10, -1)
    row.name:SetWordWrap(false)
    row.desc = T.MakeText(row, 12, T.TEXT_DIM)
    row.desc:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -4)
    row.desc:SetJustifyH("LEFT")
    row.desc:SetWordWrap(true)
    row.desc:SetSpacing(2)
    local onEnter, onLeave = row:GetScript("OnEnter"), row:GetScript("OnLeave")
    row:SetScript("OnEnter", function(self)
        onEnter(self)
        self.name:SetTextColor(1, 1, 1, 1)
        self.desc:SetTextColor(0.82, 0.80, 0.86, 1)
    end)
    row:SetScript("OnLeave", function(self)
        onLeave(self)
        local cr, cg, cb
        if self.nameColor then cr, cg, cb = unpack(self.nameColor) end
        self.name:SetTextColor(cr or T.TEXT[1], cg or T.TEXT[2], cb or T.TEXT[3], 1)
        self.desc:SetTextColor(T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1)
    end)
    -- The real name, muted, after a rename.
    row.pill = T.MakePill(row)
    row.pill:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.pill:Hide()
    row.real = T.MakeText(row, 12, T.TEXT_MUTE)
    row.real:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
    row.real:SetWordWrap(false)
    -- Click: the card opens into its editor (one open at a time).
    row:SetScript("OnMouseUp", function(self)
        if not self.spellID then return end
        state.openCard = (state.openCard ~= self.spellID) and self.spellID or nil
        RenderDesc(Fight())
    end)
    row.editor = MakeCardEditor(row)
    win.descRows[i] = row
    return row
end

RenderDesc = function(f)
    if not win then return end
    local lanes = f and ns.Schedule.Lanes(f) or {}
    -- Health-triggered abilities have no lane but keep their card, after
    -- the timed ones, tagged with the health they fire at.
    -- One card per ABILITY: a multi-threshold one comes back from
    -- HealthAbilities as one entry per marker, and its card lists them all.
    local seen = {}
    for _, ha in ipairs(f and ns.Schedule.HealthAbilities(f) or {}) do
        local a = ha.ability or ha
        if not seen[a] then
            seen[a] = true
            lanes[#lanes + 1] = { a = a, health = true }
        end
    end
    local content = win.descScroll.child
    local w = math.max(200, (win.descScroll:GetWidth() or 200))
    content:SetWidth(w)
    local y = 4
    local A = ns.Abilities
    for i, o in ipairs(lanes) do
        local row = DescRow(i)
        local a = o.a
        -- Explicit widths BEFORE measuring: a string anchored by RIGHT has no
        -- settled width in the frame it is laid out, and GetStringHeight then
        -- reports one line.
        row:SetWidth(w)
        row.desc:SetWidth(w - 62)
        row.spellID = a.spellID
        row.icon:SetTexture(SpellIcon(a.spellID) or QUESTION_ICON)
        local real = SpellName(a.spellID, a.name)
        local mine = A.Rename(a.spellID)
        row.realName = real
        row.name:SetText(mine or real)
        row.real:SetText(mine and real or "")
        row.health = a.health and a.health.pct or nil
        if row.health then
            local pcts = a.health.pcts
            local label
            if type(pcts) == "table" and #pcts > 1 then
                local parts = {}
                for _, p in ipairs(pcts) do parts[#parts + 1] = string.format("%d%%", p) end
                label = "HEALTH  " .. table.concat(parts, " / ")
            else
                label = string.format("HEALTH  %d%%", row.health)
            end
            row.pill:Set(label, 1.00, 0.55, 0.30)
            row.real:ClearAllPoints(); row.real:SetPoint("LEFT", row.pill, "RIGHT", 8, 0)
        else
            row.pill:Hide()
            row.real:ClearAllPoints(); row.real:SetPoint("LEFT", row.name, "RIGHT", 8, 0)
        end
        local cr, cg, cb = A.Color(a.spellID)
        row.nameColor = cr and { cr, cg, cb } or nil
        row.name:SetTextColor(cr or T.TEXT[1], cg or T.TEXT[2], cb or T.TEXT[3], 1)
        local d, st = SpellDesc(a.spellID)
        if st == "ok" then
            row.desc:SetText(d)
            row.desc:SetTextColor(T.TEXT_DIM[1], T.TEXT_DIM[2], T.TEXT_DIM[3], 1)
        else
            row.desc:SetText(st == "loading" and "loading..." or "no description in the client data")
            row.desc:SetTextColor(T.TEXT_MUTE[1], T.TEXT_MUTE[2], T.TEXT_MUTE[3], 1)
        end
        row.desc:SetWidth(w - 66)
        local base = math.max(52, 8 + 16 + 4 + (row.desc:GetStringHeight() or 12) + 10)
        local open = state.openCard ~= nil and state.openCard == a.spellID
        if open then
            row.editor:ClearAllPoints()
            row.editor:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -base)
            row.editor:SetPoint("RIGHT", row, "RIGHT", -12, 0)
            row.editor:Sync()
            row.editor:Show()
        else
            if row.editor:IsShown() then row.editor.name:ClearFocus() end   -- disarm a mid-edit box
            row.editor:Hide()
        end
        row:SetHeight(base + (open and EDIT_H or 0))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        row:Show()
        y = y + row:GetHeight() + 6
    end
    for i = #lanes + 1, #win.descRows do win.descRows[i]:Hide() end
    win.descEmpty:Hide()   -- no wording for an empty boss (Alex)
    content:SetHeight(math.max(1, y))
end
V.RenderDesc = RenderDesc

local function Build()
    if win then return win end
    shell = T.MakeShell("SalusNovusVisualizer", W, H, SIDEBAR_W, HEADER_H, "Boss Visualizer")
    win = shell.frame
    win.shell = shell
    win:SetFrameLevel(120)
    win:SetScript("OnHide", function() if form then form:Hide() end; if ns.ReturnToOptions then ns.ReturnToOptions() end end)
    shell.subtitle:SetText("")

    -- Sidebar: Raids / Dungeons switch, then instances, then the picked
    -- instance's bosses with portraits (MerkUI: "a high-level picker that
    -- expands"). The sidebar frame lives on the shell table (shell.side):
    -- win.side is nil and would parent the list to UIParent.
    win.modeStrip = CreateFrame("Frame", nil, shell.side)
    win.modeStrip:SetHeight(26)
    win.modeStrip:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 12, -HEADER_H - 12)
    win.modeStrip:SetPoint("TOPRIGHT", shell.side, "TOPRIGHT", -12, -HEADER_H - 12)
    win.modeStrip.border = ns.CreateBorder(win.modeStrip)
    win.modeStrip.border:Layout(win.modeStrip, 1, 0)
    win.modeStrip.border:SetColor(1, 1, 1, 0.10)
    win.modeStrip.border:Show()
    win.modeButtons = {}
    for i, def in ipairs({ { "dungeons", "Dungeons" }, { "raids", "Raids" } }) do
        local b = MakeSegment(win.modeStrip, def[2])
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", win.modeStrip, "TOPLEFT", (i - 1) * ((SIDEBAR_W - 24) / 2), 0)
        b:SetWidth((SIDEBAR_W - 24) / 2)
        b.mode = def[1]
        b:SetScript("OnClick", function()
            state.mode = def[1]
            state.openInst = nil
            Refresh()
        end)
        win.modeButtons[i] = b
    end

    win.bossList = T.MakeScrollArea(shell.side)
    win.bossList:SetPoint("TOPLEFT", shell.side, "TOPLEFT", 0, -HEADER_H - 48)
    win.bossList:SetPoint("BOTTOMRIGHT", shell.side, "BOTTOMRIGHT", -10, 12)
    win.bossList.child:SetWidth(SIDEBAR_W - 10)

    -- Content
    local content = CreateFrame("Frame", nil, win)
    content:SetPoint("TOPLEFT", win, "TOPLEFT", SIDEBAR_W + 1, -HEADER_H - 2)
    content:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", 0, 0)
    win.content = content

    win.bossTitle = T.MakeText(content, 20, T.TEXT)
    win.bossTitle:SetPoint("TOPLEFT", 22, -14)
    win.bossMeta = T.MakeText(content, 12, T.TEXT_MUTE)
    win.bossMeta:SetPoint("TOPLEFT", win.bossTitle, "BOTTOMLEFT", 0, -3)

    -- Zoom (+/-) and the window readout. Ctrl+wheel over the tracks zooms
    -- too; the slider under the lanes pans.
    win.zoomIn = T.MakeButton(content); win.zoomIn:SetSize(28, 24); win.zoomIn:SetText("+")
    win.zoomOut = T.MakeButton(content); win.zoomOut:SetSize(28, 24); win.zoomOut:SetText("-")
    -- Bigger glyphs in the same boxes (Alex).
    T.SetFont(win.zoomIn.text, 22, "")
    T.SetFont(win.zoomOut.text, 22, "")
    win.zoomIn:SetPoint("TOPRIGHT", content, "TOPRIGHT", -22, -16)
    win.zoomOut:SetPoint("RIGHT", win.zoomIn, "LEFT", -4, 0)
    win.zoomNote = T.MakeText(content, 11, T.TEXT_MUTE)
    win.zoomNote:SetPoint("RIGHT", win.zoomOut, "LEFT", -10, 0)
    local function Zoom(factor, centerT)
        local f = Fight(); if not f then return end
        local before = Span()
        state.zoom = math.max(1, math.min(10, state.zoom * factor))
        local after = Span()
        if centerT then
            local frac = (centerT - state.offset) / before
            state.offset = centerT - frac * after
        else
            state.offset = state.offset + (before - after) / 2
        end
        if state.zoom == 1 then state.offset = 0 end
        ClampOffset()
        Refresh()
    end
    win.Zoom = Zoom
    V.Zoom = Zoom
    win.zoomIn:SetScript("OnClick", function() Zoom(1.5) end)
    win.zoomOut:SetScript("OnClick", function() Zoom(1 / 1.5) end)

    -- Axis (fixed) + lanes (vertical scroll) + time slider (pan).
    win.axis = CreateFrame("Frame", nil, content)
    win.axis:SetPoint("TOPLEFT", content, "TOPLEFT", 22 + LABEL_W, -84)
    win.axis:SetPoint("TOPRIGHT", content, "TOPRIGHT", -44, -84)
    win.axis:SetHeight(AXIS_H)
    win.axisTicks = {}
    win.axisLine = T.SolidTex(win.axis, "ARTWORK", 1, 1, 1, 0.18)
    win.axisLine:SetHeight(1)
    win.axisLine:SetPoint("BOTTOMLEFT"); win.axisLine:SetPoint("BOTTOMRIGHT")

    -- The lanes take only the height they need (Refresh sets it, capped at
    -- LANES_MAX); the abilities follow directly beneath. (Alex: no large
    -- gap from the lanes to the abilities.)
    win.lanes = T.MakeScrollArea(content)
    win.lanes:SetPoint("TOPLEFT", content, "TOPLEFT", 22, -84 - AXIS_H)
    win.lanes:SetPoint("TOPRIGHT", content, "TOPRIGHT", -44, -84 - AXIS_H)
    win.lanes:SetHeight(LANE_H)

    -- Abilities: a heading and the cards, no panel behind them (Alex).
    win.desc = CreateFrame("Frame", nil, content)
    win.desc:SetPoint("TOPLEFT", win.lanes, "BOTTOMLEFT", 0, -10)
    win.desc:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -44, 50)
    win.descHead = T.MakeText(win.desc, 12, T.TEXT_MUTE)
    win.descHead:SetPoint("TOPLEFT", win.desc, "TOPLEFT", 6, 0)
    win.descHead:SetText("ABILITIES")
    win.descLine = T.SolidTex(win.desc, "ARTWORK", T.LINE[1], T.LINE[2], T.LINE[3], T.LINE[4])
    win.descLine:SetHeight(1)
    win.descLine:SetPoint("TOPLEFT", win.descHead, "BOTTOMLEFT", -6, -4)
    win.descLine:SetPoint("RIGHT", win.desc, "RIGHT", -10, 0)
    win.descScroll = T.MakeScrollArea(win.desc)
    win.descScroll:SetPoint("TOPLEFT", win.descLine, "BOTTOMLEFT", 0, -6)
    win.descScroll:SetPoint("BOTTOMRIGHT", win.desc, "BOTTOMRIGHT", -10, 0)
    win.descRows = {}
    win.descEmpty = T.MakeText(win.desc, 12, T.TEXT_MUTE)
    win.descEmpty:SetPoint("CENTER", 0, 0)
    win.descEmpty:SetText("No abilities observed for this boss yet -- log a pull.")
    win.descEmpty:Hide()

    win.cursor = T.SolidTex(content, "OVERLAY", 1, 1, 1, 0.35)
    win.cursor:SetWidth(1)
    win.cursor:Hide()
    win.cursorLabel = T.MakeText(content, 11, T.TEXT)
    win.cursorLabel:Hide()

    -- Time slider: where the visible window starts (only matters zoomed in).
    win.pan = T.MakeSlider(content, 200, 0, 100, function(v)
        local f = Fight(); if not f then return end
        state.offset = math.max(0, (FightEnd(f) - Span())) * (v / 100)
        ClampOffset()
        Refresh(true)
    end)
    win.pan:SetPoint("BOTTOMLEFT", content, "BOTTOMLEFT", 22 + LABEL_W, 18)
    win.pan:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -44, 18)
    win.pan:SetValueQuiet(0)
    -- Thicker than the options sliders: it is a scrollbar here.
    win.pan:SetHeight(22)
    win.pan.track:SetHeight(8)
    win.pan.fill:SetHeight(8)
    if win.pan.thumb then win.pan.thumb:SetSize(18, 18) end
    win.panCap = T.MakeText(content, 11, T.TEXT_MUTE)
    win.panCap:SetPoint("RIGHT", win.pan, "LEFT", -12, 0)
    win.panCap:SetText("Scroll in time")

    win.empty = T.MakeText(content, 13, T.TEXT_MUTE)
    win.empty:SetPoint("CENTER", content, "CENTER", 0, 20)
    win.empty:SetWidth(520)
    win.empty:SetJustifyH("CENTER")
    win.empty:SetText("No casts observed for this boss yet -- log a pull.")
    win.empty:Hide()

    -- Hover readout: up in the header row, left of the zoom controls (under
    -- the lanes it collided with the last row). A second line carries the
    -- client's description of the spell.
    win.hover = T.MakeText(content, 12, T.TEXT)
    win.hover:SetPoint("RIGHT", win.zoomNote, "LEFT", -18, 0)
    win.hover:SetWidth(440)
    win.hover:SetJustifyH("RIGHT")
    win.hover:SetWordWrap(false)
    -- A spell record answering later refreshes the description panel once.
    spellEv:SetScript("OnEvent", function(_, _, spellID, success)
        if success == false then return end   -- nothing new to draw
        if pendingLoads and win:IsShown() then
            pendingLoads = false
            RenderDesc(Fight())
        end
    end)
    return win
end

-- ------------------------------------------------------------- rendering

local function MakeLane()
    local lane = CreateFrame("Frame", nil, win.lanes.child)
    lane:SetHeight(LANE_H)
    lane.line = T.SolidTex(lane, "BACKGROUND", 1, 1, 1, 0.05)
    lane.line:SetHeight(1); lane.line:SetPoint("BOTTOMLEFT"); lane.line:SetPoint("BOTTOMRIGHT")
    lane.name = T.MakeText(lane, 14, T.TEXT)
    lane.name:SetPoint("TOPLEFT", 6, -7)
    lane.name:SetWidth(LABEL_W - 44)
    lane.name:SetJustifyH("LEFT")
    lane.name:SetWordWrap(false)
    lane.desc = T.MakeText(lane, 11, T.TEXT_MUTE)
    lane.desc:SetPoint("TOPLEFT", lane.name, "BOTTOMLEFT", 0, -3)
    lane.desc:SetWidth(LABEL_W - 44)
    lane.desc:SetJustifyH("LEFT")
    lane.desc:SetWordWrap(false)
    lane.count = T.MakeText(lane, 11, T.TEXT_MUTE)
    lane.count:SetPoint("TOPRIGHT", lane, "TOPLEFT", LABEL_W - 10, -8)
    lane.track = CreateFrame("Button", nil, lane)
    lane.track:SetPoint("TOPLEFT", lane, "TOPLEFT", LABEL_W, 0)
    lane.track:SetPoint("BOTTOMRIGHT", lane, "BOTTOMRIGHT", 0, 0)
    lane.track.hl = T.SolidTex(lane.track, "HIGHLIGHT", 1, 1, 1, 0.04)
    lane.track.hl:SetAllPoints()
    lane.track:SetScript("OnClick", function(self)
        local t = CursorTime(self)
        OpenForm(t, lane.spellId, lane.abilityName, nil)
    end)
    lane.track:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", function(s)
            local t = ShowCursor(s)
            -- Only when the displayed second changes: a stationary cursor
            -- was rebuilding the same string every frame.
            if t then
                local label = fmt(t)
                if label ~= s.lastHover then
                    s.lastHover = label
                    win.hover:SetText(string.format("%s  |cff888888at|r  %s", lane.abilityName or "", label))
                end
            end
        end)
    end)
    lane.track:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        self.lastHover = nil
        HideCursor()
    end)
    -- Wheel over the timeline scrolls the lanes like anywhere else; Ctrl +
    -- wheel zooms at the cursor.
    lane.track:EnableMouseWheel(true)
    lane.track:SetScript("OnMouseWheel", function(self, delta)
        if IsControlKeyDown and IsControlKeyDown() then
            win.Zoom(delta > 0 and 1.3 or 1 / 1.3, (CursorTime(self)))
        else
            local h = win.lanes:GetScript("OnMouseWheel")
            if h then h(win.lanes, delta) end
        end
    end)
    lane.marks = {}
    return lane
end

local function LaneMark(lane, i)
    local m = lane.marks[i]
    if not m then
        m = CreateFrame("Button", nil, lane.track)
        m:SetSize(6, 22)
        m.tex = T.SolidTex(m, "ARTWORK", 1, 1, 1, 1)
        m.tex:SetAllPoints()
        m.rim = ns.CreateBorder(m)
        m.rim:Layout(m, 1, 0)
        m.rim:SetColor(0, 0, 0, 0.8)
        m.rim:Show()
        -- A faint band behind the mark shows how far the pulls disagreed
        -- (+- spread). Tight = scripted, wide = reactive.
        m.band = T.SolidTex(lane.track, "BACKGROUND", 1, 1, 1, 0.16)
        m.band:SetPoint("CENTER", m, "CENTER", 0, 0)
        m.band:SetHeight(LANE_H - 8)
        m.band:Hide()
        m:SetScript("OnEnter", function(self)
            local when = self.reminder and self.reminder.trigger ~= "time"
                and (TRIGGER_LABEL[self.reminder.trigger] or "") or fmt(self.t)
            -- A single pull is its own case and MUST be said out loud: zero
            -- spread from one sample is UNKNOWN, not CONSISTENT.
            win.hover:SetText(string.format("%s  |cff888888at|r  %s%s%s%s", self.abilityName or "", when,
                self.cast and self.cast > 0 and string.format("  |cff888888(%ds cast)|r", self.cast) or "",
                self.spread and self.spread > 0.5 and string.format("  |cff888888(+-%.0fs across pulls)|r", self.spread) or "",
                -- (The one-pull caution is gone from the readout -- Alex.)
                (self.support and self.pulls and self.support < self.pulls)
                    and string.format("  |cff888888(seen in %d of %d pulls)|r", self.support, self.pulls) or ""))
            self.tex:SetVertexColor(1, 1, 1, 1)
            ShowCursor(self)
        end)
        m:SetScript("OnLeave", function(self)
            self.tex:SetVertexColor(self.r, self.g, self.b, self.alpha or 1)
            HideCursor()
        end)
        m:SetScript("OnClick", function(self) OpenForm(self.t, self.spellId, self.abilityName, self.reminder) end)
        m:EnableMouseWheel(true)
        m:SetScript("OnMouseWheel", function(self, delta)
            if IsControlKeyDown and IsControlKeyDown() then
                win.Zoom(delta > 0 and 1.3 or 1 / 1.3, self.t)
            else
                local h = win.lanes:GetScript("OnMouseWheel")
                if h then h(win.lanes, delta) end
            end
        end)
        lane.marks[i] = m
    end
    return m
end

local function RenderAxis()
    local span = Span()
    local step = span > 400 and 60 or span > 150 and 30 or span > 60 and 15 or 5
    local n = 0
    local t = math.ceil(state.offset / step) * step
    while t <= state.offset + span do
        n = n + 1
        local tick = win.axisTicks[n]
        if not tick then
            tick = T.SolidTex(win.axis, "ARTWORK", 1, 1, 1, 0.18)
            tick:SetSize(1, 8)
            tick.label = T.MakeText(win.axis, 11, T.TEXT_MUTE)
            tick.label:SetPoint("BOTTOMLEFT", tick, "TOPLEFT", 3, 1)
            win.axisTicks[n] = tick
        end
        tick:ClearAllPoints()
        tick:SetPoint("BOTTOMLEFT", win.axis, "BOTTOMLEFT", X(t), 0)
        tick.label:SetText(fmt(t))
        tick:Show(); tick.label:Show()
        t = t + step
    end
    for i = n + 1, #win.axisTicks do win.axisTicks[i]:Hide(); win.axisTicks[i].label:Hide() end
end

-- Instances of one kind in level order (unknown levels last, then by
-- name), each with its bosses in encounter order. A levelling server
-- reads better by level than MerkUI's name order.
local function Instances(mode)
    local out = {}
    local wantRaid = (mode or state.mode) == "raids"
    for mapID, inst in pairs(ns.Data or {}) do
        local isRaid = inst.type == "raid"
        if isRaid == wantRaid then out[#out + 1] = { mapID = mapID, inst = inst } end
    end
    -- `or ""` / `or 999`: a nil field throws INSIDE table.sort, which takes
    -- the window with it.
    table.sort(out, function(a, b)
        local la, lb = tonumber(a.inst.level) or 999, tonumber(b.inst.level) or 999
        if la ~= lb then return la < lb end
        return (a.inst.name or "") < (b.inst.name or "")
    end)
    return out
end
V.Instances = Instances

local function MakeBossRow(width)
    local r = CreateFrame("Button", nil, win.bossList.child)
    r:SetSize(width, MODEL + 12)
    for _, part in ipairs(T.DecorateNavRow(r)) do shell:Register(part) end
    local mf = CreateFrame("Frame", nil, r)
    mf:SetSize(MODEL, MODEL)
    mf:SetPoint("LEFT", 22, 0)
    local mbg = T.SolidTex(mf, "BACKGROUND", 0, 0, 0, 0.45)
    mbg:SetAllPoints()
    local mb = ns.CreateBorder(mf)
    mb:Layout(mf, 1, 0)
    mb:SetColor(1, 1, 1, 0.10)
    mb:Show()
    r.model = CreateFrame("PlayerModel", nil, mf)
    r.model:SetAllPoints()
    r.model:EnableMouse(false)
    r.model:SetFrameLevel(mf:GetFrameLevel() + 1)
    r.fallback = mf:CreateTexture(nil, "ARTWORK")
    r.fallback:SetAllPoints()
    r.fallback:SetTexture(QUESTION_ICON)
    r.fallback:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    r.fallback:SetAlpha(0.35)
    r.label = T.MakeText(r, 14, T.TEXT_DIM)
    r.label:SetPoint("LEFT", mf, "RIGHT", 10, 0)
    r.label:SetPoint("RIGHT", r, "RIGHT", -8, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(true)
    r.label:SetShadowColor(0, 0, 0, 0.9)
    r.label:SetShadowOffset(1, -1)
    r:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    r:SetScript("OnLeave", function(self) T.SetNavActive(self, self.enc == state.enc) end)
    return r
end

local function MakeInstRow(width)
    local r = CreateFrame("Button", nil, win.bossList.child)
    r:SetSize(width, 40)
    for _, part in ipairs(T.DecorateNavRow(r)) do shell:Register(part) end
    T.NavLabel(r, "")
    r.label:ClearAllPoints()
    r.label:SetPoint("TOPLEFT", r, "TOPLEFT", 22, -5)
    r.label:SetPoint("RIGHT", r, "RIGHT", -44, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    -- The level range on its own line, smaller (Alex: the names were cut off).
    r.sub = T.MakeText(r, 10, T.TEXT_MUTE)
    r.sub:SetPoint("TOPLEFT", r.label, "BOTTOMLEFT", 0, -1)
    r.sub:SetWordWrap(false)
    r.count = T.MakeText(r, 11, T.TEXT_MUTE)
    r.count:SetPoint("RIGHT", r, "RIGHT", -14, 0)
    r:SetScript("OnEnter", function(self) self.label:SetTextColor(1, 1, 1, 1) end)
    r:SetScript("OnLeave", function(self) T.SetNavActive(self, self.mapID == state.openInst) end)
    return r
end

local function RenderBossList()
    for _, b in ipairs(win.modeButtons) do b:SetActive(b.mode == state.mode) end
    local ni, nr, y = 0, 0, 0
    local width = SIDEBAR_W - 10
    for _, e in ipairs(Instances()) do
        ni = ni + 1
        local row = Pool(instRows, ni, function() return MakeInstRow(width) end)
        local open = (e.mapID == state.openInst)
        row.mapID = e.mapID
        row.label:SetText(e.inst.name or "?")
        -- Dungeons carry a level line; raids are level 60 and get none (Alex),
        -- so their name sits centred in the row instead of at its top.
        local range = e.inst.type ~= "raid" and e.inst.levelRange or nil
        row.sub:SetText(range and ("Level " .. range) or "")
        row.label:ClearAllPoints()
        if range then row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 22, -5)
        else row.label:SetPoint("LEFT", row, "LEFT", 22, 0) end
        row.label:SetPoint("RIGHT", row, "RIGHT", -44, 0)
        row.count:SetText(open and "-" or "+")
        row:SetScript("OnClick", function()
            -- (not `open and nil or inst`: nil falls through the `or`)
            if open then state.openInst = nil else state.openInst = e.mapID end
            Refresh()
        end)
        T.SetNavActive(row, open)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", win.bossList.child, "TOPLEFT", 0, -y); row:Show()
        y = y + 40
        if open then
            for _, b in ipairs(e.inst.bosses or {}) do
                nr = nr + 1
                local br = Pool(bossRows, nr, function() return MakeBossRow(width) end)
                br.enc = b.encounterID
                br.label:SetText(ns.S(b.name))
                local npc = b.npcs and b.npcs[1]
                local did = npc and npc.displayID
                if did and br.displayId ~= did then
                    local ok = pcall(function()
                        br.model:SetDisplayInfo(did)
                        br.model:SetPortraitZoom(1)
                        br.model:SetPosition(0, 0, 0)
                    end)
                    -- Only on success, and always both: a pooled row kept
                    -- whichever of model/fallback the PREVIOUS boss left.
                    br.displayId = ok and did or nil
                    br.model:SetShown(ok); br.fallback:SetShown(not ok)
                elseif not did then
                    br.displayId = nil
                    br.model:Hide(); br.fallback:Show()
                end
                br:SetScript("OnClick", function()
                    state.enc = b.encounterID; state.offset = 0; state.zoom = 1
                    state.openCard = nil     -- an open card does not follow to another boss
                    if form then form:Hide() end
                    Remember()
                    Refresh()
                end)
                br.boss = b
                T.SetNavActive(br, b.encounterID == state.enc)
                br:ClearAllPoints(); br:SetPoint("TOPLEFT", win.bossList.child, "TOPLEFT", 0, -y); br:Show()
                y = y + MODEL + 12
            end
        end
    end
    for i = ni + 1, #instRows do instRows[i]:Hide() end
    for i = nr + 1, #bossRows do bossRows[i]:Hide() end
    win.bossList.child:SetHeight(math.max(1, y))
end

Refresh = function(fromSlider)
    if not win then return end
    win.trackW = math.max(100, win.axis:GetWidth() or 0)
    win.lanes.child:SetWidth(math.max(100, win.lanes:GetWidth() or 0))
    -- A pan drag cannot change the sidebar; rebuilding it per 1% step was waste.
    if not fromSlider then RenderBossList() end

    local f, inst = Fight(), nil
    if state.enc then
        local _b
        _b, inst = ns.BossByEncounter(state.enc)
    end
    local lanes = f and ns.Schedule.Lanes(f) or {}
    if not f then
        win.bossTitle:SetText("Boss Visualizer")
        win.bossMeta:SetText("")
        win.empty:Show()
        for _, l in ipairs(laneRows) do l:Hide() end
        for _, tk in ipairs(win.axisTicks) do tk:Hide(); tk.label:Hide() end
        win.zoomNote:SetText("")
        RenderDesc(nil)
        return
    end
    -- A boss with nothing logged shows its name and nothing else: no axis,
    -- no lanes, no heading, no note (Alex: "just don't render anything").
    win.empty:Hide()
    local has = #lanes > 0
    for _, w in ipairs({ win.axis, win.lanes, win.desc, win.pan, win.panCap, win.zoomIn, win.zoomOut, win.zoomNote }) do
        if w then w:SetShown(has) end
    end
    if not has then
        win.bossTitle:SetText(ns.S(f.name))
        win.bossMeta:SetText("")
        for _, l in ipairs(laneRows) do l:Hide() end
        for _, tk in ipairs(win.axisTicks) do tk:Hide(); tk.label:Hide() end
        if form then form:Hide() end
        RenderDesc(nil)
        return
    end
    local npc = f.npcs and f.npcs[1]
    local pulls = f.pulls or 0
    win.bossTitle:SetText(ns.S(f.name))
    -- Just where the boss is and who it is fought as; the fight length,
    -- ability count and log wording are noise here (Alex). The one-pull
    -- caution lives on the marks' hover readout.
    win.bossMeta:SetText("")   -- no level under the boss (Alex)
    RenderDesc(f)
    win.zoomNote:SetText(state.zoom > 1 and string.format("%s - %s", fmt(state.offset), fmt(state.offset + Span())) or "")
    if not fromSlider then
        local room = FightEnd(f) - Span()
        win.pan:SetValueQuiet(room > 0 and math.floor(state.offset / room * 100 + 0.5) or 0)
    end
    win.pan:SetAlpha(state.zoom > 1 and 1 or 0.35)
    -- Fading it was not enough: the thumb still dragged and still took the
    -- wheel, moving under the mouse while the lanes did not budge.
    win.pan:SetEnabled(state.zoom > 1)
    if win.pan.Paint then win.pan.Paint() end
    RenderAxis()

    local li, ly = 0, 0
    local function NextLane()
        li = li + 1
        local lane = Pool(laneRows, li, MakeLane)
        lane:ClearAllPoints()
        lane:SetPoint("TOPLEFT", win.lanes.child, "TOPLEFT", 0, -ly)
        lane:SetPoint("TOPRIGHT", win.lanes.child, "TOPRIGHT", 0, -ly)
        ly = ly + LANE_H
        lane:Show()
        for _, m in ipairs(lane.marks) do m:Hide(); if m.band then m.band:Hide() end end
        return lane
    end

    -- Reminders lane: every reminder for this boss, timed ones at their
    -- moment, the others (pull, cast, yell) at the pull.
    local rl = NextLane()
    rl.name:SetText("Your reminders")
    local ar, ag, ab = T.Accent()
    rl.name:SetTextColor(ar, ag, ab, 1)
    rl.desc:SetText("")
    rl.abilityName, rl.spellId = nil, nil
    local list = ns.Reminders.For(state.enc)
    rl.count:SetText(#list > 0 and ("x" .. #list) or "")
    local mi = 0
    for _, r in ipairs(list) do
        local abs = (r.trigger == "time" and tonumber(r.arg)) or 0
        local vis, x = Visible(abs)
        if vis then
            mi = mi + 1
            local m = LaneMark(rl, mi)
            m:SetSize(10, 26)
            m.t, m.spellId, m.abilityName, m.reminder, m.cast = abs, r.spellId, r.text, r, nil
            -- Reset what a pooled ability mark would have left behind.
            m.support, m.pulls, m.spread = nil, nil, nil
            m.band:Hide()
            m.r, m.g, m.b = ar, ag, ab
            m.alpha = (r.enabled == false) and 0.3 or ((r.id or ""):find("^default:") and 0.6 or 1)
            m.tex:SetVertexColor(ar, ag, ab, m.alpha)
            m:ClearAllPoints(); m:SetPoint("CENTER", rl.track, "LEFT", x, 0); m:Show()
        end
    end

    for _, o in ipairs(lanes) do
        local lane = NextLane()
        local a, L = o.a, o.lanes
        lane.name:SetText(ns.Abilities.Rename(a.spellID) or SpellName(a.spellID, a.name))
        local cr, cg, cb = ns.Abilities.Color(a.spellID)
        lane.name:SetTextColor(cr or T.TEXT[1], cg or T.TEXT[2], cb or T.TEXT[3], 1)
        lane.desc:SetText((L.cast or 0) > 0 and string.format("%.1fs cast", L.cast) or "")
        lane.count:SetText("")          -- no cast count on abilities (Alex)
        lane.abilityName, lane.spellId = lane.name:GetText(), a.spellID
        local r, g, b = ar, ag, ab
        local k = 0
        for ci, t in ipairs(L.casts) do
            local span = L.cast or 0
            local sp = L.spread and L.spread[ci]
            local vis, x = VisibleSpan(t, span, (sp and sp > 1) and sp or 0)
            if vis then
                k = k + 1
                local m = LaneMark(lane, k)
                local wpx = span > 0 and math.max(6, span / Span() * TrackWidth()) or 6
                m:SetSize(wpx, 22)
                m.t, m.spellId, m.abilityName, m.reminder, m.cast = t, a.spellID, lane.abilityName, nil, L.cast
                m.support = L.support and L.support[ci] or nil
                m.pulls = pulls > 0 and pulls or nil
                m.r, m.g, m.b, m.alpha = r, g, b, 0.9
                m.tex:SetVertexColor(r, g, b, 0.9)
                m:ClearAllPoints(); m:SetPoint("CENTER", lane.track, "LEFT", x, 0); m:Show()
                m.spread = sp
                if sp and sp > 1 then
                    m.band:SetWidth(math.max(wpx, 2 * sp / Span() * TrackWidth()))
                    m.band:SetVertexColor(r, g, b, 0.16)
                    m.band:Show()
                else
                    m.band:Hide()
                end
            end
        end
    end
    for i = li + 1, #laneRows do laneRows[i]:Hide() end
    win.lanes.child:SetHeight(math.max(1, ly))
    win.lanes:SetHeight(math.min(math.max(ly, LANE_H), LANES_MAX))   -- the abilities start where the lanes end
end
V.Refresh = Refresh

-- First open: the first boss with any logged casts, dungeons before raids;
-- else the first boss of the lowest dungeon.
local function DefaultEncounter()
    for _, mode in ipairs({ "dungeons", "raids" }) do
        for _, e in ipairs(Instances(mode)) do
            for _, b in ipairs(e.inst.bosses or {}) do
                if #ns.Schedule.Lanes(b) > 0 then return b.encounterID end
            end
        end
    end
    local first = Instances("dungeons")[1] or Instances("raids")[1]
    local b = first and first.inst.bosses and first.inst.bosses[1]
    return b and b.encounterID or nil
end

-- ------------------------------------------------------------ entry points

function V.Shown() return win ~= nil and win:IsShown() end

--- Toggle, or with `forceShow` always show (the options launcher).
function V.Toggle(forceShow, encounterID)
    Build()
    if win:IsShown() and not (encounterID or forceShow) then win:Hide(); return end
    if encounterID then
        local boss = ns.BossByEncounter(encounterID)
        -- Same resets as a sidebar click, and the PRIMARY id: a variant id
        -- (BFD 2761) would file reminders where the hub never arms them.
        if boss and boss.encounterID ~= state.enc then
            state.enc = boss.encounterID
            state.offset, state.zoom = 0, 1
            state.openCard = nil
            if form then form:Hide() end
        end
    end
    if not state.enc then state.enc = Remembered() or DefaultEncounter() end
    local _, inst = ns.BossByEncounter(state.enc or -1)
    if inst then
        state.openInst = inst.mapID
        state.mode = (inst.type == "raid") and "raids" or "dungeons"
    end
    shell:Repaint()
    win:Show()
    Refresh()
end
ns.VisualizerToggle = function(forceShow) V.Toggle(forceShow) end
ns.VisualizerShown = V.Shown

function V.ShowBoss(boss)
    if type(boss) == "table" and boss.encounterID then V.Toggle(true, boss.encounterID) end
end

ns.RegisterApply(function()
    if win and win:IsShown() then
        shell:Repaint()
        Refresh()
    end
end, "Boss Visualizer")

ns.Commands.show = function() V.Toggle() end
