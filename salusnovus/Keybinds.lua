--[[ Salus Novus -- Keybinds: what every key does, per modifier layer.

Read-only. For each key on a US keyboard (plus the mouse buttons) and each
layer (none, Shift, Ctrl, Alt) K.Resolve answers:

  free                       nothing bound
  bound  { label, icon }     a Blizzard command (Move forward, World map),
                             an action-bar slot (its spell / item / macro,
                             with the slot's icon), or an addon bar button
                             bound with CLICK (its action slot when it has one)
  via    { label, icon }     no binding of its own, but the bare key holds a
                             macro whose [mod:shift] (etc.) branch answers it
  conflict                   bound to something else, while the bare key's
                             macro has a branch for this modifier that can
                             therefore never fire

A key with a modifier and no binding of its own falls through to the bare
key's binding: that is what makes [mod:shift] macros work, and why a
separately bound Shift-key silently kills the macro's Shift branch.
]]

local _, ns = ...

local K = {}
ns.Keybinds = K

local Str, Num = ns.Str, ns.Num

K.LAYERS = {
    { prefix = "",       label = "None",  mod = nil },
    { prefix = "SHIFT-", label = "Shift", mod = "shift" },
    { prefix = "CTRL-",  label = "Ctrl",  mod = "ctrl" },
    { prefix = "ALT-",   label = "Alt",   mod = "alt" },
}

-- The whole keyboard (Alex), as a real one: the main block (the keys that
-- aren't bindable on their own -- Shift, Ctrl, Alt, Win, Menu -- drawn as
-- placeholders so it reads right), the navigation block, the numpad, and the
-- mouse as a block apart, off the bottom-right corner. Each cell: { key (nil:
-- a placeholder), label, x (in keys), row, w, h (in rows), dup = drawn twice }.
K.KEYS = {}
local function Add(key, label, x, row, w, h, dup)
    K.KEYS[#K.KEYS + 1] = { key = key, label = label or key, x = x, row = row, w = w or 1, h = h or 1, dup = dup }
end
local function Run(row, x, list)
    for _, k in ipairs(list) do Add(k[1], k[2], x, row, k[3]) x = x + (k[3] or 1) end
end
-- the main block: 15 keys wide
Add("ESCAPE", "Esc", 0, 1)
for n = 1, 12 do Add("F" .. n, "F" .. n, ({ 2, 2, 2, 2, 6.5, 6.5, 6.5, 6.5, 11, 11, 11, 11 })[n] + (n - 1) % 4, 1) end
Run(2, 0, { { "`" }, { "1" }, { "2" }, { "3" }, { "4" }, { "5" }, { "6" }, { "7" }, { "8" }, { "9" }, { "0" },
            { "-" }, { "=" }, { "BACKSPACE", "Back", 2 } })
Run(3, 0, { { "TAB", "Tab", 1.5 }, { "Q" }, { "W" }, { "E" }, { "R" }, { "T" }, { "Y" }, { "U" }, { "I" }, { "O" },
            { "P" }, { "[" }, { "]" }, { "\\", "\\", 1.5 } })
Run(4, 0, { { "CAPSLOCK", "Caps", 1.75 }, { "A" }, { "S" }, { "D" }, { "F" }, { "G" }, { "H" }, { "J" }, { "K" },
            { "L" }, { ";" }, { "'" }, { "ENTER", "Enter", 2.25 } })
Run(5, 0, { { nil, "Shift", 2.25 }, { "Z" }, { "X" }, { "C" }, { "V" }, { "B" }, { "N" }, { "M" }, { "," }, { "." },
            { "/" }, { nil, "Shift", 2.75 } })
Run(6, 0, { { nil, "Ctrl", 1.25 }, { nil, "Win", 1.25 }, { nil, "Alt", 1.25 }, { "SPACE", "Space", 6.25 },
            { nil, "Alt", 1.25 }, { nil, "Win", 1.25 }, { nil, "Menu", 1.25 }, { nil, "Ctrl", 1.25 } })
-- the navigation block
Run(1, 15.25, { { "PRINTSCREEN", "PrtSc" }, { "SCROLLLOCK", "ScrLk" }, { "PAUSE", "Pause" } })
Run(2, 15.25, { { "INSERT", "Ins" }, { "HOME", "Home" }, { "PAGEUP", "PgUp" } })
Run(3, 15.25, { { "DELETE", "Del" }, { "END", "End" }, { "PAGEDOWN", "PgDn" } })
Add("UP", "Up", 16.25, 5)
Run(6, 15.25, { { "LEFT", "Left" }, { "DOWN", "Down" }, { "RIGHT", "Right" } })
-- the numpad
Run(2, 18.5, { { "NUMLOCK", "Num Lk" }, { "NUMPADDIVIDE", "Num /" }, { "NUMPADMULTIPLY", "Num *" }, { "NUMPADMINUS", "Num -" } })
Run(3, 18.5, { { "NUMPAD7", "Num 7" }, { "NUMPAD8", "Num 8" }, { "NUMPAD9", "Num 9" } })
Add("NUMPADPLUS", "Num +", 21.5, 3, 1, 2)
Run(4, 18.5, { { "NUMPAD4", "Num 4" }, { "NUMPAD5", "Num 5" }, { "NUMPAD6", "Num 6" } })
Run(5, 18.5, { { "NUMPAD1", "Num 1" }, { "NUMPAD2", "Num 2" }, { "NUMPAD3", "Num 3" } })
Add("ENTER", "Enter", 21.5, 5, 1, 2, true)           -- the numpad's Enter binds as Enter
Add("NUMPAD0", "Num 0", 18.5, 6, 2)
Add("NUMPADDECIMAL", "Num .", 20.5, 6)
-- the mouse: a block of its own, a gap off the bottom-right corner
-- (square keys, like the rest: 1.3 wide, an icon left a sliver of name -- Alex)
-- (short names: "Mouse 3" ran past a square key -- Alex)
-- buttons down one column, the wheel down the next (Alex)
Add("BUTTON3", "M3", 23.25, 4) Add("MOUSEWHEELUP", "Wh up", 24.25, 4)
Add("BUTTON4", "M4", 23.25, 5) Add("MOUSEWHEELDOWN", "Wh dn", 24.25, 5)
Add("BUTTON5", "M5", 23.25, 6)
K.WIDTH = 25.25                                      -- keys across, the mouse block included

-- Blizzard's own bars: binding command prefix -> the button frames.
local BARS = {
    { cmd = "ACTIONBUTTON",           frame = "ActionButton" },
    { cmd = "MULTIACTIONBAR1BUTTON",  frame = "MultiBarBottomLeftButton" },
    { cmd = "MULTIACTIONBAR2BUTTON",  frame = "MultiBarBottomRightButton" },
    { cmd = "MULTIACTIONBAR3BUTTON",  frame = "MultiBarRightButton" },
    { cmd = "MULTIACTIONBAR4BUTTON",  frame = "MultiBarLeftButton" },
    { cmd = "MULTIACTIONBAR5BUTTON",  frame = "MultiBar5Button" },
    { cmd = "MULTIACTIONBAR6BUTTON",  frame = "MultiBar6Button" },
    { cmd = "MULTIACTIONBAR7BUTTON",  frame = "MultiBar7Button" },
}

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(fn, ...)
    if not ok then return nil end
    return a, b, c, d
end

--- The command a key combination runs ("" / nil when nothing).
function K.Action(combo)
    local a = Str(Call(rawget(_G, "GetBindingAction"), combo, true))
    if a == "" then return nil end
    return a
end

--- A key-sized name: "Toggle World Map" -> "World Map", "Open Chat" -> "Chat".
function K.Short(name)
    if type(name) ~= "string" then return name end
    local s = name:gsub("^Toggle ", ""):gsub("^Open ", "")
    return s
end

--- A human name for a Blizzard command: BINDING_NAME_<cmd>, else the cmd.
function K.CommandName(cmd)
    local n = Str(rawget(_G, "BINDING_NAME_" .. cmd))
    if n and n ~= "" then return n end
    return (cmd:gsub("_", " "):lower():gsub("^%l", string.upper))
end

--- The action slot behind a bar button frame (Blizzard's or an addon's).
local function SlotOfButton(btn)
    if type(btn) ~= "table" then return nil end
    local s = btn.action
    if not Num(s) then
        local ok, a = pcall(function() return btn:GetAttribute("action") end)
        s = ok and a or nil
    end
    s = tonumber(s)
    return (s and s > 0) and s or nil
end

--- The action slot a command drives, if it is an action-bar binding.
function K.SlotOf(cmd)
    for _, b in ipairs(BARS) do
        local n = cmd:match("^" .. b.cmd .. "(%d+)$")
        if n then
            n = tonumber(n)
            local s = SlotOfButton(rawget(_G, b.frame .. n))
            if s then return s end
            if b.cmd == "ACTIONBUTTON" then return n end     -- page 1 when the frame isn't there
            return nil
        end
    end
    local frameName = cmd:match("^CLICK ([^:]+)")
    if frameName then return SlotOfButton(rawget(_G, frameName)), frameName end
    return nil
end

local function SpellIcon(spell)
    local f = C_Spell and C_Spell.GetSpellTexture
    return Call(f, spell)
end

local function SpellName(id)
    local f = C_Spell and C_Spell.GetSpellName
    return Str(Call(f, id))
end

--- Does one macro condition hold with `held` down (nil, "shift", "ctrl",
-- "alt")? Only the modifier conditions decide; others (harm, @focus) are
-- taken as true. [mod] is any modifier, [mod:a/b] any of those, and "no"
-- negates ([nomod], [nomod:shift]) -- the hunt: [nomod:shift] read as a
-- Shift branch, and a bare [mod] was ignored.
-- The keys a modifier test names, left/right folded into one (the layers
-- are Shift/Ctrl/Alt). Bare [shift] / [noshift] count too (Alex's E macro:
-- "[harm,nodead,shift] Lightning Bolt" read as no Shift branch).
local MODKEY = { shift = "shift", lshift = "shift", rshift = "shift", ctrl = "ctrl", lctrl = "ctrl", rctrl = "ctrl",
                 alt = "alt", lalt = "alt", ralt = "alt" }
local function Holds(cond, held)
    cond = cond:match("^%s*(.-)%s*$")
    local no, rest = false, cond
    local b = cond:match("^no(.+)$")
    if b and (b:match("^mod") or MODKEY[b]) then no, rest = true, b end
    local name, arg = rest:match("^(%a+):?(.*)$")
    local hit = false
    if MODKEY[name] and arg == "" then
        hit = MODKEY[name] == held
    elseif name == "mod" or name == "modifier" then
        if arg == "" then hit = held ~= nil
        else
            for one in arg:gmatch("%a+") do
                local key = MODKEY[one]
                -- [mod:selfcast] / [mod:focuscast]: the key the game is set to
                -- (an unknown name read as "no modifier" and fired bare: the sweep)
                if not key and (one == "selfcast" or one == "focuscast") then
                    local gm = rawget(_G, "GetModifiedClick")
                    local okM, m = pcall(gm or function() return nil end, one:upper())
                    m = okM and type(m) == "string" and m:lower() or nil
                    key = m and MODKEY[m] or nil
                end
                if key ~= nil and key == held then hit = true end
            end
        end
    else
        -- not a modifier test: taken as true, flagged as one that can fail
        -- ([harm], [nodead]; a bare @unit only picks the target)
        return true, not (cond:match("^@") or cond:match("^target="))
    end
    if no then return not hit end
    return hit
end

--- A clause fires when any of its [groups] holds (all of a group's comma-
-- separated conditions), or when it has none. The second return is true when
-- it fires only through a non-modifier condition ([@mouseover,harm]) that
-- can fail, so a later clause is what the layer usually casts.
local function Fires(groups, held)
    if #groups == 0 then return true, false end
    local fired = false
    for _, g in ipairs(groups) do
        local all, cond = true, false
        for c in g:gmatch("[^,]+") do
            local h, nonmod = Holds(c, held)
            if not h then all = false break end
            if nonmod then cond = true end
        end
        if all and not cond then return true, false end
        if all then fired = true end
    end
    return fired, fired
end

--- A macro's /cast and /use lines by layer. Each line casts the first
-- clause that fires with that layer held (as the game picks it); a macro of
-- several lines casts one per line ("/cast Blood Fury" then "/cast
-- Lightning Bolt"). Returns
--   main   { base, shift, ctrl, alt } = the layer's main spell: the one
--          #showtooltip names, else the LAST line's (off-GCD buttons like
--          Blood Fury go first -- Alex)
--   extras { layer = { the others, in order } } (the key's corner badges)
--   seq    { layer = { every spell, in macro order } }
-- A modifier layer is only a branch when it casts something the bare key
-- doesn't: "[nomod] Frost Shock; Purge" gives Shift Purge; "/cast Fireball"
-- gives Shift nothing (a plain key, free to bind).
function K.ParseMacro(body)
    local out, extras, seq = {}, {}, {}
    if type(body) ~= "string" then return out, extras, seq end
    local LAYER_HELD = { { "base", nil }, { "shift", "shift" }, { "ctrl", "ctrl" }, { "alt", "alt" } }
    local tip, casts = nil, false
    -- each layer when every non-modifier condition fails (no mouseover
    -- target): "[@mouseover,harm] Moonfire; [mod:shift] Sunfire" is Shift
    -- Sunfire, not Moonfire on every layer (sweep 6)
    local plain = {}
    for line in body:gmatch("[^\r\n]+") do
        local t = line:match("^%s*#showtooltip%s+(.-)%s*$")
        if t and t ~= "" and not t:find("[%[;]") then tip = t:lower() end
        local rest = line:match("^%s*/cast%s+(.+)") or line:match("^%s*/use%s+(.+)")
        if rest then
            local got, gotPlain = {}, {}
            for clause in rest:gmatch("[^;]+") do
                local groups, spell = {}, clause
                spell = spell:gsub("%[([^%]]*)%]", function(c) groups[#groups + 1] = c:lower() return "" end)
                spell = spell:match("^%s*(.-)%s*$")
                if spell then spell = spell:gsub("^!%s*", "") end   -- '!Prowl' toggles: the spell is Prowl
                if spell and spell ~= "" then
                    casts = true
                    for _, l in ipairs(LAYER_HELD) do
                        local fires, cond = Fires(groups, l[2])
                        if not got[l[1]] and fires then
                            got[l[1]] = true
                            seq[l[1]] = seq[l[1]] or {}
                            table.insert(seq[l[1]], spell)
                        end
                        if not gotPlain[l[1]] and fires and not cond then
                            gotPlain[l[1]] = true
                            plain[l[1]] = plain[l[1]] or {}
                            table.insert(plain[l[1]], spell)
                        end
                    end
                end
            end
        end
    end
    -- a layer no clause fires on casts NOTHING: told apart from 'same as
    -- the bare key' (it showed the bare key's spell: sweep 2)
    local none = {}
    if casts then for _, m in ipairs({ "shift", "ctrl", "alt" }) do if not seq[m] then none[m] = true end end end
    local function same(a, b)
        a, b = a or {}, b or {}
        if #a ~= #b then return false end
        for i = 1, #a do if a[i] ~= b[i] then return false end end
        return true
    end
    -- a layer that matches the bare key only through a condition that can
    -- fail is a branch when, without it, it casts something else
    for _, m in ipairs({ "shift", "ctrl", "alt" }) do
        if seq[m] and same(seq[m], seq.base) and plain[m] and not same(plain[m], plain.base) then seq[m] = plain[m] end
    end
    for layer, list in pairs(seq) do
        local main = list[#list]
        if tip then for _, s in ipairs(list) do if s:lower() == tip then main = s end end end
        out[layer] = main
        local rest, skipped = {}, false
        for _, s in ipairs(list) do
            if s == main and not skipped then skipped = true else rest[#rest + 1] = s end
        end
        if #rest > 0 then extras[layer] = rest end
    end
    for _, m in ipairs({ "shift", "ctrl", "alt" }) do
        if out[m] ~= nil and out[m] == out.base and same(seq[m], seq.base) then out[m], extras[m], seq[m] = nil, nil, nil end
    end
    return out, extras, seq, none
end

--- An icon for what a macro line names: an equipped slot ("/use 13"), a
-- spell, or an item.
function K.IconOf(name)
    local slot = tonumber(name)
    if slot then return Call(rawget(_G, "GetInventoryItemTexture"), "player", slot) end
    local icon = SpellIcon(name)
    if icon then return icon end
    local ci = rawget(_G, "C_Item")
    return Call(ci and ci.GetItemIconByID, name)
end

local function Icons(list)
    local out = {}
    for _, s in ipairs(list or {}) do
        local icon = K.IconOf(s)
        if icon then out[#out + 1] = icon end
    end
    return #out > 0 and out or nil
end

--- What an action slot holds: { kind, label, icon, macro = body-branches }.
function K.SlotInfo(slot)
    local kind, id, sub = Call(rawget(_G, "GetActionInfo"), slot)
    kind = Str(kind)
    if not kind then return nil end
    local icon = Call(rawget(_G, "GetActionTexture"), slot)
    local info = { kind = kind, icon = icon, slot = slot }
    if kind == "spell" then
        info.label = SpellName(id) or ("Spell " .. tostring(id))
    elseif kind == "item" then
        local f = C_Item and C_Item.GetItemNameByID
        info.label = Str(Call(f, id)) or ("Item " .. tostring(id))
    elseif kind == "macro" then
        -- On this client a macro showing a spell answers ("macro", spellID,
        -- "spell"): the id isn't the macro's index. Find it by the macro's name.
        -- With no subtype the id IS the index: use it first, since the name finds
        -- the first macro so named (a general one shadowed a character one: sweep 5).
        local index
        if (sub == nil or sub == "") and Num(id) and id > 0 then index = id end
        local text = not index and Str(Call(rawget(_G, "GetActionText"), slot))
        if text then
            local i = Call(rawget(_G, "GetMacroIndexByName"), text)
            if Num(i) and i > 0 then index = i end
        end
        local name, mIcon, body
        if index then name, mIcon, body = Call(rawget(_G, "GetMacroInfo"), index) end
        info.label = Str(name) or "Macro"
        info.icon = info.icon or mIcon
        info.branches, info.extras, info.seq, info.none = K.ParseMacro(Str(body))
    else
        info.label = kind:gsub("^%l", string.upper)
    end
    return info
end

--- A key bound straight to a macro, spell or item ('MACRO Shocks', set by
-- SetBindingMacro/Spell/Item): read like a slot's (it showed as a lowercase
-- interface command, its macro never checked: sweep 2).
function K.DirectInfo(cmd)
    local kind, name = tostring(cmd or ""):match("^(%u+) (.+)$")
    if kind == "MACRO" then
        local i = Call(rawget(_G, "GetMacroIndexByName"), name)
        local mName, mIcon, body
        if Num(i) and i > 0 then mName, mIcon, body = Call(rawget(_G, "GetMacroInfo"), i) end
        local info = { kind = "macro", label = Str(mName) or name, icon = mIcon }
        info.branches, info.extras, info.seq, info.none = K.ParseMacro(Str(body))
        return info
    elseif kind == "SPELL" or kind == "ITEM" then
        return { kind = kind:lower(), label = name, icon = K.IconOf(name) }
    end
    return nil
end

--- One key on one layer: { state = "free"|"bound"|"via"|"conflict", label, icon, macro, detail }.
function K.Resolve(key, layer)
    local L = K.LAYERS[layer] or K.LAYERS[1]
    local cmd = K.Action(L.prefix .. key)
    local own, ownInfo
    if cmd then
        local slot, clickFrame = K.SlotOf(cmd)
        local info
        if slot then info = K.SlotInfo(slot) elseif not clickFrame then info = K.DirectInfo(cmd) end
        ownInfo = info
        if info then
            own = { state = "bound", label = info.label, icon = info.icon, macro = info.kind == "macro",
                    detail = (info.kind == "macro" and ("Macro '" .. info.label .. "'") or info.label)
                        .. (slot and (" (action slot %d)"):format(slot) or "") }
            -- pressed with this layer's modifier held: its branch fires (the
            -- no-modifier spell showed: the sweep)
            local lay = (L.mod and info.branches and info.branches[L.mod]) and L.mod or "base"
            if info.branches and info.branches[lay] then
                own.detail = own.detail .. ": " .. table.concat(info.seq[lay], ", then ")
                own.icon = K.IconOf(info.branches[lay]) or own.icon
                own.extras = Icons(info.extras[lay])
            end
            if L.mod and info.none and info.none[L.mod] then
                own.detail = own.detail .. ": casts nothing with " .. L.mod .. " held"
                own.icon, own.extras = nil, nil
            end
        elseif clickFrame and not slot then
            own = { state = "bound", label = clickFrame, detail = "Clicks " .. clickFrame }
        elseif slot then
            -- Bound to an empty slot: pressing it does nothing, so it's free
            -- for the audit (the binding is still named in the line).
            own = { state = "free", label = "Empty", empty = true,
                    detail = ("Free: bound to action slot %d, which is empty"):format(slot) }
        else
            local n = K.CommandName(cmd)
            own = { state = "bound", label = K.Short(n), detail = n .. " (interface)", ui = true }
        end
    end
    -- The bare key's macro: its branch for this layer
    if L.mod then
        local base = K.Action(key)
        local slot, clickB
        if base then slot, clickB = K.SlotOf(base) end
        local info
        if slot then info = K.SlotInfo(slot) elseif base and not clickB then info = K.DirectInfo(base) end
        local spell = info and info.branches and info.branches[L.mod]
        if spell then
            -- the combo bound to the bare key's own action runs the same macro
            -- with the modifier held: that's the branch firing, not a conflict (the sweep)
            if own and (cmd == base or (slot and K.SlotOf(cmd) == slot)) then return own end
            -- or the same macro from another slot or a MACRO binding (sweep 5)
            if own and ownInfo and ownInfo.kind == "macro" and info.kind == "macro" and ownInfo.label ~= "Macro"
                and ownInfo.label == info.label and ownInfo.branches and ownInfo.branches[L.mod] == spell then return own end
            if own then
                own.state = "conflict"
                own.detail = own.detail .. ". Conflict: " .. key .. "'s macro '" .. info.label .. "' has a ["
                    .. "mod:" .. L.mod .. "] " .. spell .. " branch that never fires while this is bound."
                return own
            end
            return { state = "via", label = spell, icon = K.IconOf(spell), macro = true,
                     extras = Icons(info.extras and info.extras[L.mod]),
                     detail = ("No binding of its own: %s's macro '%s' answers it with %s ([mod:%s])."):format(
                         key, info.label, table.concat(info.seq[L.mod], ", then "), L.mod) }
        end
    end
    return own or { state = "free", detail = "Free" }
end

--- Every key on a layer: { [key] = resolved }, and how many are free.
function K.Layer(layer)
    local out, free, total = {}, 0, 0
    local keys = {}
    for _, c in ipairs(K.KEYS) do if c.key and not c.dup then keys[#keys + 1] = c.key end end
    for _, key in ipairs(keys) do
        local r = K.Resolve(key, layer)
        out[key] = r
        total = total + 1
        if r.state == "free" then free = free + 1 end
    end
    return out, free, total
end
