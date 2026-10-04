--[[ Salus Novus -- Wishlist: dungeon loot you want, tagged, and shared with
the group.

Quality of Life > Wishlist (Alex, 2026-10-02). Loot comes from AtlasLoot
Classic at RUNTIME (an optional dependency, never copied: Alex's choice,
2026-09-20) -- AtlasLoot.Loader:LoadModule loads its on-demand dungeon
module, AtlasLoot.ItemDB:Get returns every dungeon with its LevelRange and
per-boss { position, itemID } rows. The Encounter Journal is empty on
Forever, so MerkUI's journal route is out.

  * What you can equip: every proficiency is a known spell (One-Handed
    Axes 196 ... Mail 8737, Plate 750), so an item shows when the player
    knows its weapon or armor skill -- a shaman sees mail from 40, axes once
    a weapon master has taught them. Cloth and leather wearers' rules alike.
  * Tags: the class's three talent trees (several allowed) and BIS or
    Upgrade, per item, per character.
  * Owned: bags + bank + equipped. Items you own are marked in the browser;
    one you GAIN inside a dungeon or raid leaves the wishlist by itself
    (outside instances nothing is checked: Alex, no overfiring).
  * Party: the wishlist goes to the group over addon messages, the protocol
    MerkUI's Gear.lua settled on (chunked, bounded, roster-checked).
]]

local _, ns = ...

local W = {}
ns.Wishlist = W

local Num, Str = ns.Num, ns.Str
local MODULE = "AtlasLootClassic_DungeonsAndRaids"
local PREFIX = "SNWish"

local function O() return ns.db and ns.db.wishlist end
local function Enabled() return ns.ModuleOn("qol") and true or false end
W.Enabled = Enabled

-- ------------------------------------------------------------ specs

W.SPECS = {
    WARRIOR = { "Arms", "Fury", "Protection" },        PALADIN = { "Holy", "Protection", "Retribution" },
    HUNTER = { "Beast Mastery", "Marksmanship", "Survival" }, ROGUE = { "Assassination", "Combat", "Subtlety" },
    PRIEST = { "Discipline", "Holy", "Shadow" },        SHAMAN = { "Elemental", "Enhancement", "Restoration" },
    MAGE = { "Arcane", "Fire", "Frost" },               WARLOCK = { "Affliction", "Demonology", "Destruction" },
    DRUID = { "Balance", "Feral", "Restoration" },
}

local function ClassTag()
    local ok, _, tag = pcall(UnitClass, "player")
    return ok and Str(tag) or nil
end
W.ClassTag = ClassTag

function W.MySpecs() return W.SPECS[ClassTag() or ""] or {} end

-- ------------------------------------------------------------ items

local function CI() return rawget(_G, "C_Item") end

--- name, link, quality, ilvl, reqLevel, equipLoc, icon, classID, subclassID
-- for an item id, or nil while the client has not cached it (a request goes
-- out; GET_ITEM_INFO_RECEIVED refreshes the window).
local requested = {}
function W.Info(id)
    local ci = CI()
    local fn = ci and ci.GetItemInfo
    if not fn then return nil end
    local ok, name, link, quality, ilvl, req, _, _, _, equipLoc, icon, _, classID, subclassID = pcall(fn, id)
    if not ok or not Str(name) then
        -- Ask once, not on every redraw: each answer redraws, and the redraw
        -- re-asked for every item still missing (an id that never loads
        -- was asked for forever). Again after 30 s in case one was lost.
        local now = GetTime and GetTime() or 0
        if ci.RequestLoadItemDataByID and (not requested[id] or now - requested[id] > 30) then
            requested[id] = now
            pcall(ci.RequestLoadItemDataByID, id)
        end
        return nil
    end
    return { id = id, name = name, link = Str(link), quality = Num(quality) and quality or 1, ilvl = Num(ilvl) and ilvl or 0,
             req = Num(req) and req or 0, equipLoc = Str(equipLoc) or "", icon = icon, classID = classID, subclassID = subclassID }
end

-- Slot groups for browsing: equipLoc -> group key, and the order shown.
W.SLOT_ORDER = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
                 "Finger", "Trinket", "Main Hand", "Off Hand", "Two-Hand", "Ranged" }
local SLOT = {
    INVTYPE_HEAD = "Head", INVTYPE_NECK = "Neck", INVTYPE_SHOULDER = "Shoulder", INVTYPE_CLOAK = "Back",
    INVTYPE_CHEST = "Chest", INVTYPE_ROBE = "Chest", INVTYPE_WRIST = "Wrist", INVTYPE_HAND = "Hands",
    INVTYPE_WAIST = "Waist", INVTYPE_LEGS = "Legs", INVTYPE_FEET = "Feet", INVTYPE_FINGER = "Finger",
    INVTYPE_TRINKET = "Trinket", INVTYPE_WEAPON = "Main Hand", INVTYPE_WEAPONMAINHAND = "Main Hand",
    INVTYPE_WEAPONOFFHAND = "Off Hand", INVTYPE_SHIELD = "Off Hand", INVTYPE_HOLDABLE = "Off Hand",
    INVTYPE_2HWEAPON = "Two-Hand", INVTYPE_RANGED = "Ranged", INVTYPE_RANGEDRIGHT = "Ranged",
    INVTYPE_THROWN = "Ranged", INVTYPE_RELIC = "Ranged",
}
W.SLOT = SLOT

-- Proficiency spells (verified in Forever's SpellName table, 2026-10-02).
local WEAPON_SKILL = { [0] = 196, [1] = 197, [2] = 264, [3] = 266, [4] = 198, [5] = 199, [6] = 200,
                       [7] = 201, [8] = 202, [10] = 227, [13] = 15590, [15] = 1180, [16] = 2567,
                       [18] = 5011, [19] = 5009 }
local ARMOR_SKILL = { [1] = 9078, [2] = 9077, [3] = 8737, [4] = 750, [6] = 9116 }
local RELIC_CLASS = { [7] = "PALADIN", [8] = "DRUID", [9] = "SHAMAN" }
local WEAPON, ARMOR = 2, 4

local function Knows(spell)
    local f = rawget(_G, "IsPlayerSpell") or rawget(_G, "IsSpellKnown")
    if not f then return true end                   -- no way to ask: don't hide
    local ok, r = pcall(f, spell)
    return not ok or r == true
end

--- Can the player equip this item (its weapon or armor skill is known)?
function W.CanEquip(info)
    if not info then return false end
    if info.classID == WEAPON then
        local spell = WEAPON_SKILL[info.subclassID]
        if spell then return Knows(spell) end
        return info.subclassID ~= 20                -- fishing poles are not dungeon loot
    elseif info.classID == ARMOR then
        if RELIC_CLASS[info.subclassID] then return RELIC_CLASS[info.subclassID] == ClassTag() end
        local spell = ARMOR_SKILL[info.subclassID]
        if spell then return Knows(spell) end
        return true                                 -- rings, necks, trinkets
    end
    return false
end

--- Bags, bank or worn.
function W.Owned(id)
    local ci = CI()
    local count = ci and ci.GetItemCount or rawget(_G, "GetItemCount")
    if count then
        local ok, n = pcall(count, id, true)
        if ok and Num(n) and n > 0 then return true end
    end
    local eq = (ci and ci.IsEquippedItem) or rawget(_G, "IsEquippedItem")
    if eq then
        local ok, r = pcall(eq, id)
        if ok and r == true then return true end
    end
    return false
end

-- ------------------------------------------------------------ AtlasLoot

W.catalog = nil      -- { dungeons = { {key, name, range = {min,lo,hi}, bosses = { {name, items = {ids}} } } }, source = { [id] = {dungeon, boss} } }

local function AL() return rawget(_G, "AtlasLoot") end

--- Is AtlasLoot there at all?
function W.HasAtlasLoot()
    local al = AL()
    return type(al) == "table" and type(al.ItemDB) == "table" and type(al.Loader) == "table"
end

--- Read the loaded module into W.catalog.
function W.ReadCatalog()
    local al = AL()
    local db = al and al.ItemDB
    local store = db and db.Get and select(2, pcall(db.Get, db, MODULE))
    if type(store) ~= "table" then return nil end
    local keys = {}
    local list = db.GetModuleList and select(2, pcall(db.GetModuleList, db, MODULE))
    if type(list) == "table" and #list > 0 then
        for _, k in ipairs(list) do keys[#keys + 1] = k end
    else
        for k, v in pairs(store) do if type(v) == "table" and type(v.items) == "table" then keys[#keys + 1] = k end end
        table.sort(keys)
    end
    local cat = { dungeons = {}, source = {} }
    local shared = {}
    for _, key in ipairs(keys) do
        local c = store[key]
        local id = type(c) == "table" and c.InstanceID
        if Num(id) then shared[id] = (shared[id] or 0) + 1 end
    end
    for _, key in ipairs(keys) do
        local c = store[key]
        if type(c) == "table" and type(c.items) == "table" and W.IsDungeon(c) then
            local r = type(c.LevelRange) == "table" and c.LevelRange or {}
            local d = { key = key, name = W.Clean(W.ContentName(c)), range = { Num(r[1]) and r[1] or 0, Num(r[2]) and r[2] or 0, Num(r[3]) and r[3] or 0 }, bosses = {}, order = #cat.dungeons }
            -- The visualizer's levels beat AtlasLoot's (Alex): same dungeon by
            -- instance ID, else by name (Dire Maul's wings carry no ID).
            -- Wings that share one of our instances (Scarlet Monastery's
            -- four, Lower/Upper Blackrock Spire) keep AtlasLoot's per-wing
            -- range: ours covers the whole building.
            local lo, hi = W.OurLevels(c.InstanceID, d.name)
            if lo and not (Num(c.InstanceID) and (shared[c.InstanceID] or 0) > 1) then d.range[2], d.range[3] = lo, hi end
            for b, boss in ipairs(c.items) do
                local dif = c.LoadDifficulty or 1
                local okT, rows = true, nil
                if db.GetItemTable then okT, rows = pcall(db.GetItemTable, db, MODULE, key, b, dif) end
                if not okT or type(rows) ~= "table" then rows = type(boss) == "table" and boss[dif] or nil end
                local ids = {}
                local bossName = W.Clean(type(boss) == "table" and boss.name)
                for _, row in ipairs(type(rows) == "table" and rows or {}) do
                    local id = type(row) == "table" and row[2]
                    if Num(id) and id > 0 then
                        ids[#ids + 1] = id
                        cat.source[id] = cat.source[id] or { dungeon = d.name, boss = bossName }
                    end
                end
                if #ids > 0 then d.bosses[#d.bosses + 1] = { name = bossName, items = ids } end
            end
            if #d.bosses > 0 then cat.dungeons[#cat.dungeons + 1] = d end
        end
    end
    -- By level, so Forever's dungeons sit among the old ones, not at the end.
    table.sort(cat.dungeons, function(a, b)
        if a.range[2] ~= b.range[2] then return a.range[2] < b.range[2] end
        if a.range[3] ~= b.range[3] then return a.range[3] < b.range[3] end
        return a.order < b.order          -- SM's wings share one range: keep AtlasLoot's wing order
    end)
    W.catalog = cat
    return cat
end

local function Key(s) return (tostring(s or ""):lower():gsub("^the ", ""):gsub("[^%a]", "")) end

--- Level range from the visualizer's dungeon data (ns.Data, keyed by
-- instance ID): lo, hi, or nil when the dungeon is not there.
function W.OurLevels(instanceID, name)
    local data = ns.Data
    if type(data) ~= "table" then return nil end
    local inst = Num(instanceID) and data[instanceID]
    if type(inst) ~= "table" then
        inst = nil
        local want = Key(name)
        for _, i in pairs(data) do
            if type(i) == "table" and Key(i.name) == want then inst = i break end
        end
    end
    if not (inst and inst.type ~= "raid") then return nil end
    local lo, hi = tostring(inst.levelRange or ""):match("^(%d+)%s*%-%s*(%d+)$")
    if lo then return tonumber(lo), tonumber(hi) end
    return nil
end

--- A content's name: most carry one, but a dozen dungeons (Gnomeregan,
-- Uldaman, Stratholme...) only have a MapID and AtlasLoot names them from
-- the map (ContentProto:GetName).
function W.ContentName(c)
    if type(c.GetName) == "function" then
        local ok, n = pcall(c.GetName, c, true)
        if ok and Str(n) then return n end
    end
    if Str(c.name) then return c.name end
    local area = C_Map and C_Map.GetAreaInfo
    if area and Num(c.MapID) then
        local ok, n = pcall(area, c.MapID)
        if ok and Str(n) then return n end
    end
    return nil
end

--- Dungeons only: AtlasLoot's raids and World Bosses are not dungeon loot.
-- Its content types are named "Dungeons" (localized) and "Forever Dungeons".
function W.IsDungeon(c)
    if type(c.GetContentType) == "function" then
        local ok, typ = pcall(c.GetContentType, c)
        if ok and Str(typ) then
            local L = AL() and AL().Locales
            local okL, dungeons = pcall(function() return L["Dungeons"] end)
            if not okL then dungeons = nil end
            return typ == dungeons or typ == "Dungeons" or typ == "Forever Dungeons"
        end
    end
    -- Unknown type: a level range is the best tell (World Bosses has none).
    local r = type(c.LevelRange) == "table" and c.LevelRange
    return r and Num(r[3]) and r[3] > 0 and true or false
end

--- AtlasLoot names carry colour codes and inline textures (the "NEW" tag,
-- |TInterface\AddOns\AtlasLootClassic\ltn2.tga:15:56:2:0|t): text only.
function W.Clean(s)
    s = Str(s)
    if not s then return "?" end
    s = s:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or "?"
end

--- Load AtlasLoot's dungeon module (on demand, out of combat) and read it.
-- cb(catalog or nil, why) runs once it is ready.
function W.LoadCatalog(cb)
    if W.catalog then if cb then cb(W.catalog) end return end
    if not W.HasAtlasLoot() then if cb then cb(nil, "AtlasLoot Classic is not installed") end return end
    local loader = AL().Loader
    -- Every path ends in one FINAL answer (in combat a "loads after combat"
    -- note comes first, then the data): the window must never sit on
    -- "Loading..." (a module AtlasLoot does not know returns nil and never
    -- calls back; BANNED / INTERFACE_VERSION / CORRUPT return a state).
    local settled = false
    local function Finish(c, why)
        if settled then return end
        settled = true
        if cb then cb(c, why) end
    end
    local function Done() local c = W.ReadCatalog() Finish(c, c and nil or "AtlasLoot's dungeon data did not load") end
    local ok, state = pcall(loader.LoadModule, loader, MODULE, Done)
    if not ok then Finish(nil, "AtlasLoot's loader failed") return end
    if state == "InCombat" then
        -- Not settled: AtlasLoot calls Done once combat ends.
        if cb then cb(nil, "AtlasLoot loads its data after combat") end
        return
    end
    if type(state) == "string" then
        Finish(nil, "AtlasLoot's Dungeons and Raids module is " .. state:lower():gsub("_", " "))
        return
    end
    if settled then return end
    local function Late() if not settled then Done() end end
    if C_Timer and C_Timer.After then C_Timer.After(1, Late) else Late() end
end

--- Dungeons whose recommended range comes within `span` levels of `level`.
function W.NearDungeons(level, span)
    local out = {}
    for _, d in ipairs(W.catalog and W.catalog.dungeons or {}) do
        local lo, hi = d.range[2], d.range[3]
        if lo > 0 and hi > 0 and lo <= level + span and hi >= level - span then out[#out + 1] = d.key end
    end
    return out
end

--- Browse: the loot of the chosen dungeons, optionally one slot group,
-- that the player can equip. { {id, info, dungeon, boss, owned}, ... }
function W.Browse(pool, slot)
    local out, seen = {}, {}
    for _, d in ipairs(W.catalog and W.catalog.dungeons or {}) do
        if pool[d.key] then
            for _, b in ipairs(d.bosses) do
                for _, id in ipairs(b.items) do
                    if not seen[id] then
                        local info = W.Info(id)
                        local group = info and SLOT[info.equipLoc]
                        if group and (not slot or slot == group) and W.CanEquip(info) then
                            seen[id] = true
                            out[#out + 1] = { id = id, info = info, dungeon = d.name, boss = b.name, slot = group }
                        end
                    end
                end
            end
        end
    end
    return out
end

-- ------------------------------------------------------------ my list

local function CharKey()
    local ok, name, realm = pcall(UnitFullName or UnitName, "player")
    name = ok and Str(name) or "?"
    realm = ok and Str(realm) or nil
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end
W.CharKey = CharKey

-- The dungeons each character last picked: SalusNovusDB.wishlistPool[char]
-- = { [contentKey] = true }. Kept apart from SalusNovusDB.wishlist, whose
-- keys are characters' item lists.
local function PoolKey()
    local key = CharKey()
    if key:match("^%?") then return nil end      -- no name yet: never a shared "?" pick
    return key
end

--- This character's saved pick ({} for a first-timer: nothing selected).
function W.SavedPool()
    local out = {}
    local all = type(SalusNovusDB) == "table" and SalusNovusDB.wishlistPool
    local key = PoolKey()
    local p = type(all) == "table" and key and all[key]
    if type(p) == "table" then
        for k, v in pairs(p) do if v == true and type(k) == "string" then out[k] = true end end
    end
    return out
end

function W.SavePool(pool)
    local key = PoolKey()
    if type(SalusNovusDB) ~= "table" or not key then return end
    if type(SalusNovusDB.wishlistPool) ~= "table" then SalusNovusDB.wishlistPool = {} end
    local copy = {}
    for k, v in pairs(pool or {}) do if v and type(k) == "string" then copy[k] = true end end
    SalusNovusDB.wishlistPool[key] = copy
end

local function List(create)
    if type(SalusNovusDB) ~= "table" then return nil end
    if type(SalusNovusDB.wishlist) ~= "table" then
        if not create then return nil end
        SalusNovusDB.wishlist = {}
    end
    local key = CharKey()
    -- No name yet (or a secret one): never file a list under "?", where
    -- every character in that state would share it.
    if key == "?" or key:sub(1, 2) == "?-" then return nil end
    local l = SalusNovusDB.wishlist[key]
    if type(l) ~= "table" then
        if not create then return nil end
        l = {}
        SalusNovusDB.wishlist[key] = l
    end
    return l
end

--- The record for an item on my list, or nil.
function W.Get(id)
    local l = List(false)
    local r = l and l[tostring(id)]
    return type(r) == "table" and r or nil
end

local baseline = {}            -- [id] = owned when wished / when entering an instance
function W._ForgetBaseline(id) baseline[id] = nil end   -- test seam

function W.Wish(id, on)
    local l = List(true)
    if not l then return end
    if on then
        l[tostring(id)] = l[tostring(id)] or { spec = {} }
        baseline[id] = W.Owned(id)
    else
        l[tostring(id)] = nil
        baseline[id] = nil
    end
    W.Broadcast()
    if W.OnChanged then W.OnChanged() end
end

function W.ToggleSpec(id, spec)
    local r = W.Get(id)
    if not r then return end
    r.spec = type(r.spec) == "table" and r.spec or {}
    r.spec[spec] = not r.spec[spec] or nil
    W.Broadcast()                      -- specs travel with the list now
    if W.OnChanged then W.OnChanged() end
end

--- tag: "bis" | "up" | nil (a second click on the same tag clears it)
function W.SetTag(id, tag)
    local r = W.Get(id)
    if not r then return end
    r.tag = (r.tag ~= tag) and tag or nil
    W.Broadcast()
    if W.OnChanged then W.OnChanged() end
end

--- My wished ids, sorted.
function W.MyItems()
    local out = {}
    for k, r in pairs(List(false) or {}) do
        local id = tonumber(k)
        if id and type(r) == "table" then out[#out + 1] = id end
    end
    table.sort(out)
    return out
end

-- ------------------------------------------------------------ delist

local function InInstance()
    local f = rawget(_G, "IsInInstance")
    if not f then return false end
    local ok, inside, kind = pcall(f)
    return ok and inside == true and (kind == "party" or kind == "raid")
end
W.InInstance = InInstance

--- Inside a dungeon or raid: an item wished while not owned, now owned,
-- leaves the list. Returns the ids delisted.
function W.CheckGained()
    if not (Enabled() and InInstance()) then return {} end
    local gone = {}
    for _, id in ipairs(W.MyItems()) do
        -- No snapshot (it is taken on wish and on entering): count it as
        -- owned now, so an unknown never reads as a fresh gain.
        if baseline[id] == nil then baseline[id] = W.Owned(id) end
        if not baseline[id] and W.Owned(id) then gone[#gone + 1] = id end
    end
    for _, id in ipairs(gone) do
        local l = List(false)
        if l then l[tostring(id)] = nil end
        baseline[id] = nil
        local info = W.Info(id)
        ns.Print(("got %s -- off your wishlist"):format(info and (info.link or info.name) or ("item " .. id)))
    end
    if #gone > 0 then
        W.Broadcast()
        if W.OnChanged then W.OnChanged() end
    end
    return gone
end

-- Entering an instance: what you already own there cannot be "gained".
ns.On("PLAYER_ENTERING_WORLD", function()
    if not InInstance() then return end
    for _, id in ipairs(W.MyItems()) do baseline[id] = W.Owned(id) end
end)
-- CheckGained itself returns at once outside an instance (one guard, one place).
ns.On("BAG_UPDATE_DELAYED", function() W.CheckGained() end)
ns.On("PLAYER_EQUIPMENT_CHANGED", function() W.CheckGained() end)

-- ------------------------------------------------------------ party

-- The protocol is MerkUI's (Gear.lua): "WL|<class>|<ids>" then "WLC|..."
-- continuations, each under 240 bytes, at most 12; "REQ" asks the group to
-- send theirs. An id may carry a tag letter: 12345b (BIS), 12345u (upgrade).
W.party = {}         -- name -> { classFile, items = { {id, tag} }, at }
W.sendOK, W.sendFail = 0, 0

W.prefixOK = false
function W.RegisterPrefix()
    if W.prefixOK then return true end
    local ci = rawget(_G, "C_ChatInfo")
    if not (ci and ci.RegisterAddonMessagePrefix) then return false end
    local ok, res = pcall(ci.RegisterAddonMessagePrefix, PREFIX)
    -- 0 Success, 2 AlreadyRegistered: we can receive. 3 TooMany (the cap is
    -- shared by every addon): sends succeed and nothing ever arrives.
    W.prefixOK = (ok and (res == nil or res == true or res == 0 or res == 2)) and true or false
    return W.prefixOK
end
W.RegisterPrefix()

local function Channel()
    local raid, group = rawget(_G, "IsInRaid"), rawget(_G, "IsInGroup")
    if raid and raid() then return "RAID" end
    if group and group() then return "PARTY" end
    return nil
end

local function Send(msg, ch)
    local ci = rawget(_G, "C_ChatInfo")
    if not (ci and ci.SendAddonMessage) then return end
    local ok = pcall(ci.SendAddonMessage, PREFIX, msg, ch)
    if ok then W.sendOK = W.sendOK + 1 else W.sendFail = W.sendFail + 1 end
end

local function Later(fn)
    if C_Timer and C_Timer.After then C_Timer.After(1, fn) else fn() end
end

local pendingSend = false
function W.Broadcast()
    if pendingSend then return end
    pendingSend = true
    Later(function()
        pendingSend = false
        local ch = Channel()
        if not ch then return end
        local class = ClassTag() or ""
        local head, cont = ("WL|%s|"):format(class), ("WLC|%s|"):format(class)
        local BUDGET = 240
        local chunks, cur = {}, nil
        for _, id in ipairs(W.MyItems()) do
            local r = W.Get(id)
            -- id, then b/u for BIS/Upgrade, then ".13": the class's specs by index
            local piece = tostring(id) .. ((r and r.tag == "bis" and "b") or (r and r.tag == "up" and "u") or "")
            local sp = ""
            for i, name in ipairs(W.MySpecs()) do if r and r.spec and r.spec[name] then sp = sp .. i end end
            if sp ~= "" then piece = piece .. "." .. sp end
            local prefixLen = (#chunks == 0) and #head or #cont
            if cur == nil then cur = piece
            elseif prefixLen + #cur + 1 + #piece <= BUDGET then cur = cur .. "," .. piece
            else chunks[#chunks + 1] = cur; cur = piece end
        end
        if cur then chunks[#chunks + 1] = cur end
        if #chunks == 0 then chunks[1] = "" end
        for i = 1, math.min(#chunks, 12) do Send((i == 1 and head or cont) .. chunks[i], ch) end
    end)
end

local pendingReq = false
function W.Request()
    if pendingReq then return end
    pendingReq = true
    Later(function()
        pendingReq = false
        local ch = Channel()
        if ch then Send("REQ", ch) end
    end)
end

local function Short(name)
    local amb = rawget(_G, "Ambiguate")
    if amb then local ok, s = pcall(amb, name, "none") if ok and Str(s) then return s end end
    return name
end

local function UnitKey(unit)
    local ok, name, realm = pcall(UnitName, unit)
    if not ok or not Str(name) then return nil end
    realm = Str(realm)
    return realm and realm ~= "" and (name .. "-" .. realm) or name
end

function W.InMyGroup(name)
    local group = rawget(_G, "IsInGroup")
    if not name or name == "" or not (group and group()) then return false end
    local raid = rawget(_G, "IsInRaid")
    local inRaid = raid and raid()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    for i = 1, n do
        if UnitKey((inRaid and "raid" or "party") .. i) == name then return true end
    end
    return false
end

local MAX_IDS = 240
function W.OnAddonMessage(prefix, msg, channel, sender)
    if ns.IsSecret(prefix) or prefix ~= PREFIX or type(msg) ~= "string" then return end
    if ns.IsSecret(msg) or ns.IsSecret(channel) or ns.IsSecret(sender) then return end
    if channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
    local who = Short(sender or "")
    if who == UnitKey("player") or who == Str(UnitName("player")) then return end
    if not W.InMyGroup(who) then return end
    if msg == "REQ" then W.Broadcast() return end
    local append = false
    local class, ids = msg:match("^WL|(%a*)|(.*)$")
    if not class then
        class, ids = msg:match("^WLC|(%a*)|(.*)$")
        append = class ~= nil
    end
    if not class then return end
    local prev = W.party[who]
    if append and not prev then return end
    local items = (append and prev.items) or {}
    local seen = {}
    for _, it in ipairs(items) do seen[it.id] = true end
    local names = W.SPECS[class] or {}
    for tok in ids:gmatch("[^,]+") do
        if #items >= MAX_IDS then break end
        local id, flag, sp = tok:match("^(%d+)([bu]?)%.?([123]*)$")
        local n = tonumber(id)
        if n and n > 0 and n < 1e9 and not seen[n] then
            seen[n] = true
            local specs, had = {}, {}
            for d in (sp or ""):gmatch("%d") do
                local nm = names[tonumber(d)]
                if nm and not had[nm] then had[nm] = true; specs[#specs + 1] = nm end
            end
            items[#items + 1] = { id = n, tag = (flag == "b" and "bis") or (flag == "u" and "up") or nil, specs = specs }
        end
    end
    W.party[who] = { classFile = class ~= "" and class or nil, items = items, at = GetTime and GetTime() or 0 }
    if W.OnChanged then W.OnChanged() end
end
ns.On("CHAT_MSG_ADDON", function(...) W.OnAddonMessage(...) end)

-- Roster changes: forget who left, ask the group for their lists.
ns.On("GROUP_ROSTER_UPDATE", function()
    for name in pairs(W.party) do if not W.InMyGroup(name) then W.party[name] = nil end end
    if Channel() then W.Request() end
    if W.OnChanged then W.OnChanged() end
end)
ns.On("PLAYER_ENTERING_WORLD", function() W.RegisterPrefix() end)

--- Who wants one item: me first (me = true), then the group by name.
-- { {player, class, tag, specs = {names}, me}, ... }; empty when nobody.
function W.WantersOf(id)
    local out = {}
    id = tonumber(id)
    if not id then return out end
    local mine = W.Get(id)
    if mine then
        local specs = {}
        for _, nm in ipairs(W.MySpecs()) do if mine.spec and mine.spec[nm] then specs[#specs + 1] = nm end end
        out[1] = { player = Str(UnitName("player")) or "?", class = ClassTag(), tag = mine.tag, specs = specs, me = true }
    end
    local names = {}
    for name in pairs(W.party) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        local rec = W.party[name]
        for _, it in ipairs(rec.items) do
            if it.id == id then
                out[#out + 1] = { player = name, class = rec.classFile, tag = it.tag, specs = it.specs or {} }
                break
            end
        end
    end
    return out
end

--- Dungeons by what the group wants from them.
-- sortBy "total" = most wanted entries, "people" = most party members.
-- { {name, total, people, lines = { {player, id, tag, boss} } } }
function W.Rank(sortBy)
    local per = {}
    local function Add(player, class, id, tag, specs)
        local src = W.catalog and W.catalog.source[id]
        if not src then return end
        local e = per[src.dungeon]
        if not e then e = { name = src.dungeon, total = 0, who = {}, lines = {}, items = {}, byItem = {} }; per[src.dungeon] = e end
        e.total = e.total + 1
        e.who[player] = true
        e.lines[#e.lines + 1] = { player = player, class = class, id = id, tag = tag, boss = src.boss }
        -- One entry per item, with everyone who wants it.
        local it = e.byItem[id]
        if not it then it = { id = id, boss = src.boss, wanters = {} }; e.byItem[id] = it; e.items[#e.items + 1] = it end
        it.wanters[#it.wanters + 1] = { player = player, class = class, tag = tag, specs = specs or {} }
    end
    local me = Str(UnitName("player")) or "?"
    local okC, _, myClass = pcall(UnitClass, "player")
    myClass = okC and Str(myClass) or nil
    for _, id in ipairs(W.MyItems()) do
        local r = W.Get(id)
        local specs = {}
        for _, nm in ipairs(W.MySpecs()) do if r and r.spec and r.spec[nm] then specs[#specs + 1] = nm end end
        Add(me, myClass, id, r and r.tag, specs)
    end
    for name, rec in pairs(W.party) do for _, it in ipairs(rec.items) do Add(name, rec.classFile, it.id, it.tag, it.specs) end end
    local out = {}
    for _, e in pairs(per) do
        local n = 0
        for _ in pairs(e.who) do n = n + 1 end
        e.people = n
        table.sort(e.lines, function(a, b)
            if a.player ~= b.player then
                if a.player == me then return true end
                if b.player == me then return false end
                return a.player < b.player
            end
            return a.id < b.id
        end)
        -- Most-wanted item first, then by name of the first who wants it.
        table.sort(e.items, function(a, b)
            if #a.wanters ~= #b.wanters then return #a.wanters > #b.wanters end
            return a.id < b.id
        end)
        for _, it in ipairs(e.items) do
            table.sort(it.wanters, function(a, b)
                if a.player == me then return b.player ~= me end
                if b.player == me then return false end
                return a.player < b.player
            end)
        end
        e.byItem = nil
        out[#out + 1] = e
    end
    table.sort(out, function(a, b)
        if sortBy == "people" then
            if a.people ~= b.people then return a.people > b.people end
            if a.total ~= b.total then return a.total > b.total end
        else
            if a.total ~= b.total then return a.total > b.total end
            if a.people ~= b.people then return a.people > b.people end
        end
        return a.name < b.name
    end)
    return out
end

ns.On("GET_ITEM_INFO_RECEIVED", function() if W.OnItemInfo then W.OnItemInfo() end end)
