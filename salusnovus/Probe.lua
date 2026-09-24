--[[ Salus Novus -- Probe: in-game checks of client calls we may build on.

    /sn probe waypoint     -- can we place and supertrack a user waypoint
                              where the player stands, and read the numbers
                              a leveling arrow would need?

Every call is pcall'd and every result is printed through ns.S, so a
secret value shows as "?" instead of throwing. Nothing here changes a
setting; the waypoint it places is cleared again at the end unless
"keep" is passed (/sn probe waypoint keep) so it can be seen on the map.
]]

local _, ns = ...

local P = {}
ns.Probe = P

local function Call(out, label, fn, ...)
    if type(fn) ~= "function" then
        out[#out + 1] = label .. ": MISSING"
        return nil
    end
    local res = { pcall(fn, ...) }
    if not res[1] then
        out[#out + 1] = label .. ": ERROR " .. ns.S(res[2])
        return nil
    end
    local parts = {}
    for i = 2, #res do
        local v = res[i]
        if type(v) == "table" and not ns.IsSecret(v) then
            local kv = {}
            for k, x in pairs(v) do
                if type(x) ~= "function" then kv[#kv + 1] = ns.S(k) .. "=" .. ns.S(x) end
            end
            table.sort(kv)
            parts[#parts + 1] = "{" .. table.concat(kv, " ") .. "}"
        else
            parts[#parts + 1] = ns.S(v)
        end
    end
    out[#out + 1] = label .. ": " .. (#parts > 0 and table.concat(parts, ", ") or "nil")
    return unpack(res, 2)
end

local function Num(v) return type(v) == "number" and not ns.IsSecret(v) end

--- Returns the report lines; the slash command prints them.
function P.Waypoint(keep)
    local out = {}
    local map = Call(out, "GetBestMapForUnit(player)", C_Map and C_Map.GetBestMapForUnit, "player")
    if not Num(map) then
        out[#out + 1] = "no usable map id: stopping"
        return out
    end
    Call(out, "GetMapInfo", C_Map.GetMapInfo, map)
    local pos = Call(out, "GetPlayerMapPosition", C_Map.GetPlayerMapPosition, map, "player")
    local x, y
    if type(pos) == "table" then
        x, y = pos.x, pos.y
        if type(pos.GetXY) == "function" then
            local ok, gx, gy = pcall(pos.GetXY, pos)
            if ok then x, y = gx, gy end
        end
    end
    out[#out + 1] = ("player x/y: %s / %s (%s)"):format(ns.S(x), ns.S(y), (Num(x) and Num(y)) and "usable" or "NOT usable")
    Call(out, "GetPlayerFacing", GetPlayerFacing)
    if Num(x) and Num(y) then
        Call(out, "GetWorldPosFromMapPos", C_Map.GetWorldPosFromMapPos, map, CreateVector2D and CreateVector2D(x, y) or pos)
    end
    Call(out, "GetMapWorldSize", C_Map.GetMapWorldSize, map)
    local can = Call(out, "CanSetUserWaypointOnMap", C_Map.CanSetUserWaypointOnMap, map)
    if Num(x) and Num(y) then
        local tx = math.min(0.99, x + 0.02)
        local point
        if UiMapPoint and UiMapPoint.CreateFromCoordinates then
            local ok, p = pcall(UiMapPoint.CreateFromCoordinates, map, tx, y)
            if ok then point = p end
        end
        if not point then point = { uiMapID = map, position = CreateVector2D and CreateVector2D(tx, y) or { x = tx, y = y } } end
        Call(out, "SetUserWaypoint(+0.02 x)", C_Map.SetUserWaypoint, point)
        Call(out, "HasUserWaypoint", C_Map.HasUserWaypoint)
        Call(out, "GetUserWaypoint", C_Map.GetUserWaypoint)
        Call(out, "SetSuperTrackedUserWaypoint(true)", C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint, true)
        Call(out, "IsSuperTrackingUserWaypoint", C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)
        Call(out, "IsSuperTrackingAnything", C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything)
        Call(out, "C_Navigation.GetDistance", C_Navigation and C_Navigation.GetDistance)
        Call(out, "C_Navigation.GetTargetState", C_Navigation and C_Navigation.GetTargetState)
        Call(out, "C_Navigation.HasValidScreenPosition", C_Navigation and C_Navigation.HasValidScreenPosition)
        if not keep then
            Call(out, "ClearUserWaypoint", C_Map.ClearUserWaypoint)
            Call(out, "HasUserWaypoint (after clear)", C_Map.HasUserWaypoint)
        else
            out[#out + 1] = "waypoint kept: look at the minimap / map; /sn probe waypoint to clear it"
        end
    else
        out[#out + 1] = "no usable position: SetUserWaypoint not attempted (CanSetUserWaypointOnMap said " .. ns.S(can) .. ")"
    end
    return out
end

--- Read-only: the navigation and supertrack state right now. Run it a
-- moment after "/sn probe waypoint keep", once the client has drawn a
-- frame with the pin (the numbers in the same frame as the set read 0).
function P.Nav()
    local out = {}
    Call(out, "HasUserWaypoint", C_Map and C_Map.HasUserWaypoint)
    Call(out, "GetUserWaypoint", C_Map and C_Map.GetUserWaypoint)
    Call(out, "IsSuperTrackingUserWaypoint", C_SuperTrack and C_SuperTrack.IsSuperTrackingUserWaypoint)
    Call(out, "IsSuperTrackingAnything", C_SuperTrack and C_SuperTrack.IsSuperTrackingAnything)
    Call(out, "GetHighestPrioritySuperTrackingType", C_SuperTrack and C_SuperTrack.GetHighestPrioritySuperTrackingType)
    Call(out, "C_Navigation.GetDistance", C_Navigation and C_Navigation.GetDistance)
    Call(out, "C_Navigation.GetTargetState", C_Navigation and C_Navigation.GetTargetState)
    Call(out, "C_Navigation.HasValidScreenPosition", C_Navigation and C_Navigation.HasValidScreenPosition)
    Call(out, "C_Navigation.WasClampedToScreen", C_Navigation and C_Navigation.WasClampedToScreen)
    local f = Call(out, "C_Navigation.GetFrame", C_Navigation and C_Navigation.GetFrame)
    if type(f) == "table" then
        Call(out, "  nav frame shown", f.IsShown, f)
        Call(out, "  nav frame centre", f.GetCenter, f)
    end
    local map = Call(out, "GetBestMapForUnit(player)", C_Map and C_Map.GetBestMapForUnit, "player")
    if Num(map) then
        local pos = Call(out, "GetPlayerMapPosition", C_Map.GetPlayerMapPosition, map, "player")
        local wp = C_Map and C_Map.GetUserWaypoint and select(2, pcall(C_Map.GetUserWaypoint))
        if type(pos) == "table" and type(wp) == "table" and type(wp.position) == "table"
            and Num(pos.x) and Num(pos.y) and Num(wp.position.x) and Num(wp.position.y) and wp.uiMapID == map then
            local okW, w, h = pcall(C_Map.GetMapWorldSize, map)
            if okW and Num(w) and Num(h) then
                local dx, dy = (wp.position.x - pos.x) * w, (wp.position.y - pos.y) * h
                out[#out + 1] = ("our own distance to the pin: %.1f yd (dx %.1f, dy %.1f)"):format(math.sqrt(dx * dx + dy * dy), dx, dy)
            end
        end
    end
    return out
end

--- The first rows of an open trainer, raw, and the first spellbook items
-- with every rank source: tells which call carries the rank on this client.
function P.Trainer()
    local out = {}
    local okN, n = pcall(GetNumTrainerServices)
    out[#out + 1] = "GetNumTrainerServices: " .. ns.S(okN and n)
    for i = 1, math.min(6, (okN and Num(n)) and n or 0) do
        local res = { pcall(GetTrainerServiceInfo, i) }
        local parts = {}
        for k = 2, #res do parts[#parts + 1] = ns.S(res[k]) end
        out[#out + 1] = ("  row %d GetTrainerServiceInfo -> %s"):format(i, table.concat(parts, " | "))
        local okR, nreq = pcall(GetTrainerServiceNumAbilityReq, i)
        local req = {}
        for j = 1, (okR and Num(nreq)) and nreq or 0 do
            local okA, a, b = pcall(GetTrainerServiceAbilityReq, i, j)
            req[#req + 1] = ns.S(a) .. "/" .. ns.S(b)
        end
        out[#out + 1] = ("        level %s cost %s skill %s icon %s req [%s]"):format(
            ns.S(select(2, pcall(GetTrainerServiceLevelReq, i))), ns.S(select(2, pcall(GetTrainerServiceCost, i))),
            ns.S(select(2, pcall(GetTrainerServiceSkillLine, i))), ns.S(select(2, pcall(GetTrainerServiceIcon, i))), table.concat(req, ", "))
        local link = type(GetTrainerServiceItemLink) == "function" and select(2, pcall(GetTrainerServiceItemLink, i)) or "no GetTrainerServiceItemLink"
        out[#out + 1] = "        link " .. ns.S(link):gsub("|", "||")
    end
    return out
end

function P.Spellbook()
    local out = {}
    local sb = rawget(_G, "C_SpellBook")
    if not sb then out[#out + 1] = "C_SpellBook: MISSING" return out end
    local bank = (rawget(_G, "Enum") and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player) or 0
    local okN, lines = pcall(sb.GetNumSpellBookSkillLines)
    out[#out + 1] = "skill lines: " .. ns.S(okN and lines)
    local shown = 0
    for i = 1, (okN and Num(lines)) and lines or 0 do
        local okI, info = pcall(sb.GetSpellBookSkillLineInfo, i)
        if okI and type(info) == "table" then
            out[#out + 1] = ("  line %d %s offset %s items %s"):format(i, ns.S(info.name), ns.S(info.itemIndexOffset), ns.S(info.numSpellBookItems))
            for slot = (info.itemIndexOffset or 0) + 1, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0) do
                if shown >= 10 then break end
                local okS, name, sub = pcall(sb.GetSpellBookItemName, slot, bank)
                local okT, item = pcall(sb.GetSpellBookItemInfo, slot, bank)
                local id = okT and type(item) == "table" and item.spellID or nil
                local cs = rawget(_G, "C_Spell")
                local subtext = cs and cs.GetSpellSubtext and select(2, pcall(cs.GetSpellSubtext, id)) or nil
                out[#out + 1] = ("    slot %d name %s | book sub %s | id %s | C_Spell.GetSpellSubtext %s"):format(slot, ns.S(name), ns.S(sub), ns.S(id), ns.S(subtext))
                shown = shown + 1
            end
        end
    end
    -- how Blizzard builds a category tab button, so ours can copy it.
    -- First what is there at all: the book's frame-typed keys and children.
    local psf = rawget(_G, "PlayerSpellsFrame")
    out[#out + 1] = "PlayerSpellsFrame: " .. (type(psf) == "table" and "found" or "MISSING") .. "  SpellBookFrame(global): " .. (rawget(_G, "SpellBookFrame") and "found" or "none")
    local sbf = type(psf) == "table" and psf.SpellBookFrame or rawget(_G, "SpellBookFrame")
    local function Name(o) return ns.S(type(o) == "table" and ((o.GetDebugName and o:GetDebugName()) or (o.GetName and o:GetName())) or o) end
    if type(sbf) == "table" then
        local keys = {}
        for k, v in pairs(sbf) do
            if type(v) == "table" and type(v.GetObjectType) == "function" then keys[#keys + 1] = tostring(k) .. ":" .. ns.S(select(2, pcall(v.GetObjectType, v))) end
        end
        table.sort(keys)
        out[#out + 1] = "book keys: " .. table.concat(keys, ", ")
        local kids = {}
        for _, c in ipairs({ sbf:GetChildren() }) do kids[#kids + 1] = Name(c) .. ":" .. ns.S(select(2, pcall(c.GetObjectType, c))) end
        out[#out + 1] = "book children: " .. table.concat(kids, ", ")
    else
        out[#out + 1] = "book: MISSING"
    end
    local h = ns.TrainerUI and ns.TrainerUI.host or {}
    out[#out + 1] = ("tab attached to: top=%s book=%s tabs=%s page=%s"):format(Name(h.top), Name(h.book), Name(h.tabs), Name(h.page))
    local tabs = h.tabs or (type(sbf) == "table" and sbf.CategoryTabSystem) or nil
    if type(tabs) ~= "table" then
        -- our tab's parent, then: whatever holds the row
        local ours = rawget(_G, "SalusNovusTrainerTabButton")
        tabs = ours and ours:GetParent() or nil
        out[#out + 1] = "tab row: not a CategoryTabSystem key; using our tab's parent " .. Name(tabs)
    end
    if type(tabs) ~= "table" then out[#out + 1] = "tab row: not found" return out end
    local function Describe(obj, indent)
        local okT, ty = pcall(obj.GetObjectType, obj)
        local okS, w, h = pcall(obj.GetSize, obj)
        local okP, p, rel, rp, x, y = pcall(obj.GetPoint, obj, 1)
        local line = ("%s%s %s %sx%s %s -> %s %s (%s,%s) shown=%s"):format(indent, ns.S(okT and ty), ns.S(obj.GetDebugName and obj:GetDebugName() or obj:GetName()),
            ns.S(okS and w), ns.S(okS and h), ns.S(okP and p), ns.S(okP and rel and (rel.GetDebugName and rel:GetDebugName() or rel:GetName()) or nil), ns.S(okP and rp), ns.S(okP and x), ns.S(okP and y),
            ns.S(select(2, pcall(obj.IsShown, obj))))
        if okT and ty == "Texture" then
            line = line .. (" atlas=%s file=%s layer=%s"):format(ns.S(select(2, pcall(obj.GetAtlas, obj))), ns.S(select(2, pcall(obj.GetTexture, obj))), ns.S(select(2, pcall(obj.GetDrawLayer, obj))))
        end
        out[#out + 1] = line
    end
    local n = 0
    for _, k in ipairs({ tabs:GetChildren() }) do
        n = n + 1
        if n <= 2 then
            Describe(k, "  tab: ")
            out[#out + 1] = ("       level %s strata %s"):format(ns.S(k:GetFrameLevel()), ns.S(k:GetFrameStrata()))
            for _, r in ipairs({ k:GetRegions() }) do Describe(r, "       region ") end
            for _, c in ipairs({ k:GetChildren() }) do Describe(c, "       child ") end
        end
    end
    out[#out + 1] = ("tab row level %s, page level %s, %d children"):format(ns.S(tabs:GetFrameLevel()), ns.S(psf.SpellBookFrame.PagedSpellsFrame and psf.SpellBookFrame.PagedSpellsFrame:GetFrameLevel()), n)
    return out
end

ns.Commands = ns.Commands or {}
ns.Commands.probe = function(rest)
    local what, arg = (rest or ""):match("^(%S*)%s*(%S*)")
    if what == "waypoint" then
        for _, line in ipairs(P.Waypoint(arg == "keep")) do ns.Print(line) end
    elseif what == "nav" then
        for _, line in ipairs(P.Nav()) do ns.Print(line) end
    elseif what == "trainer" and arg == "capture" then
        -- refresh a class catalogue: open the class trainer, run this, /reload,
        -- then harvest_routes.py + build_route.py compile it into Data/Trainers.lua
        local cap, why = ns.Trainer.Capture(true)
        if not cap then ns.Print("probe: nothing captured (" .. tostring(why) .. "); open a class trainer first") end
    elseif what == "trainer" then
        for _, line in ipairs(P.Trainer()) do ns.Print(line) end
    elseif what == "spellbook" then
        for _, line in ipairs(P.Spellbook()) do ns.Print(line) end
    else
        ns.Print("probes: /sn probe waypoint [keep]  |  /sn probe nav  |  /sn probe trainer [capture]  |  /sn probe spellbook")
    end
end
