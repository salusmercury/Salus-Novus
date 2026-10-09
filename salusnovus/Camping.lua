--[[ Salus Novus -- Camping (Quality of Life): Forever's campsites.

Data: every camping item from Wowhead's camping guide (Alex, 2026-10-03),
checked against the client's own tables (all 37 in ItemSparse, each with
its placement spell), plus four the guide doesn't link but the client's
camp spells do: the Iron Oven, the Alliance Faction Banner (the guide's is
the Horde one), the Scarlet Banner and Scrap Item (which shares the camping
cooldown). Three tiers per profession; a higher tier keeps the
lower tier's buff.

How a camp works (client spell data):
  - a campfire kit builds a campfire (Basic 3 / Journeyman 5 / Expert 10
    features); kits share a 5 minute cooldown;
  - every other feature needs a campfire nearby ("Campfire Nearby" aura)
    and shares ONE 1 hour cooldown;
  - sitting near a Welcoming Campfire for 1 min grants "Camp Benefits" and
    a "Boosted ..." buff per feature placed there, each for 1 hour (Legacy
    perks change both numbers: timers are read, never assumed).
]]

local _, ns = ...

local C = {}
ns.Camping = C

local Num = ns.Num

-- Auras (client spell IDs).
C.AURA = {
    nearby   = 1283391,                 -- Campfire Nearby
    sitting  = { 1229739, 1289723 },    -- Welcoming Campfire (the 1 min sit)
    benefits = 1229741,                 -- Camp Benefits
}

-- The buff each profession line gives (nil: a vendor/utility line).
C.LINES = {
    { key = "alchemy",        label = "Alchemy",        buff = 1230587, buffLabel = "Mana regeneration", feature = "Mana Well" },
    { key = "blacksmithing",  label = "Blacksmithing",  buff = 1230172, buffLabel = "Strength", feature = "Sharpening Wheel" },
    { key = "enchanting",     label = "Enchanting",     buff = 1230653, buffLabel = "Armor, stats, resistances", feature = "Enchanted Lute" },
    { key = "engineering",    label = "Engineering" },
    { key = "herbalism",      label = "Herbalism",      buff = 1229513, buffLabel = "Intellect", feature = "Incense Candle" },
    { key = "leatherworking", label = "Leatherworking", buff = 1229451, buffLabel = "Rested XP", feature = "Tent" },
    { key = "mining",         label = "Mining",         buff = 1230164, buffLabel = "Attack power", feature = "Lodestone" },
    { key = "skinning",       label = "Skinning",       buff = 1229519, buffLabel = "Critical strike", feature = "Camp Chair" },
    { key = "tailoring",      label = "Tailoring",      buff = 1229718, buffLabel = "Spirit", feature = "Faction Banner" },
    { key = "firstaid",       label = "First Aid",      buff = 1230124, buffLabel = "Stamina", feature = "First Aid Kit" },
    { key = "fishing",        label = "Fishing",        buff = 1230098, buffLabel = "All stats", feature = "Fish Bowl" },
    { key = "cooking",        label = "Cooking" },
    { key = "other",          label = "Other" },
}

-- item ID -> { name, line, tier, kit = campfire kit }
C.ITEMS = {
    [279956] = { "Mana Well", "alchemy", 1 },          [279970] = { "Fermenter", "alchemy", 2 },
    [279990] = { "Alchemy Laboratory", "alchemy", 3 },
    [279944] = { "Sharpening Wheel", "blacksmithing", 1 }, [279988] = { "Anvil", "blacksmithing", 2 },
    [279955] = { "Master Forge", "blacksmithing", 3 },
    [279976] = { "Enchanted Lute", "enchanting", 1 },  [279985] = { "Arcane Salvager", "enchanting", 2 },
    [279987] = { "Arcane Forge", "enchanting", 3 },
    [279950] = { "Reagent Bot", "engineering", 1 },    [279949] = { "Repair Bot", "engineering", 2 },
    [279989] = { "Anarchist's Workbench", "engineering", 3 },
    [279962] = { "Incense Candle", "herbalism", 1 },   [279964] = { "Greenhouse", "herbalism", 2 },
    [279947] = { "Seed Hybridizer", "herbalism", 3 },
    [279978] = { "Camp Tent", "leatherworking", 1 },   [279941] = { "Tanning Rack", "leatherworking", 2 },
    [279945] = { "Sewing Machine", "leatherworking", 3 },
    [279960] = { "Lodestone", "mining", 1 },           [279948] = { "Rock Garden", "mining", 2 },
    [279952] = { "Molten Foundry", "mining", 3 },
    [279979] = { "Camp Chair", "skinning", 1 },        [279969] = { "Field Guide", "skinning", 2 },
    [279938] = { "Trapper's Workbench", "skinning", 3 },
    [279972] = { "Faction Banner", "tailoring", 1 },   [279973] = { "Faction Banner", "tailoring", 1 },
    [279943] = { "Spinning Wheel", "tailoring", 2 },
    [279959] = { "Loom", "tailoring", 3 },
    [279968] = { "First Aid Kit", "firstaid", 1 },     [279940] = { "Toxin Study", "firstaid", 2 },
    [279951] = { "Plague Doctor's Laboratory", "firstaid", 3 },
    [279967] = { "Fish Bowl", "fishing", 1 },          [279965] = { "Fishing Rack", "fishing", 2 },
    [279966] = { "Fishing Hut", "fishing", 3 },
    [279981] = { "Basic Campfire Kit", "cooking", 1, kit = true },
    [279961] = { "Journeyman Campfire Kit", "cooking", 2, kit = true },
    [279957] = { "Cookie's Feast", "cooking", 2 },
    [279974] = { "Expert Campfire Kit", "cooking", 3, kit = true },
    [279982] = { "Iron Oven", "cooking", 4 },
    [278030] = { "Scarlet Banner", "other", 1 },
    [272942] = { "Scrap Item", "other", 1 },
}

local LINE_ORDER = {}
for i, l in ipairs(C.LINES) do LINE_ORDER[l.key] = i end

local function O() return ns.db and ns.db.camping end
local function Enabled()
    local o = O()
    return o and o.enabled ~= false and ns.ModuleOn("qol") and true or false
end
C.Enabled = Enabled

local function Now() return (GetTime and GetTime()) or 0 end
local function DebugLeft(v) return ns.Num(v) and ("%ds left"):format(v) or "?" end

-- ------------------------------------------------------------ auras

-- The buff list, by spell ID and by name: GetPlayerAuraBySpellID lost Camp
-- Benefits after a /reload (Alex, 2026-10-03: on him, panel saw nothing),
-- so a miss there looks here. Built once per aura change (and at most a
-- second old, in case an aura change slips by).
local NAMES = { [1229741] = "Camp Benefits", [1283391] = "Campfire Nearby" }
local scan
local function Scan()
    if scan and Now() - scan.t < 1 then return scan end
    scan = { byID = {}, byName = {}, n = 0, t = Now() }
    local byIndex = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
    if not byIndex then return scan end
    for i = 1, 40 do
        local ok, a = pcall(byIndex, "player", i)
        if not ok or type(a) ~= "table" or ns.IsSecret(a) then break end
        scan.n = i
        local id, name = Num(a.spellId) and a.spellId, ns.Str(a.name)
        if id and not scan.byID[id] then scan.byID[id] = { aura = a, index = i } end
        if name and not scan.byName[name] then scan.byName[name] = { aura = a, index = i } end
    end
    return scan
end
C.Scan = Scan
ns.On("UNIT_AURA", function(unit) if unit == "player" then scan = nil end end)

local function Direct(spellID)
    local fn = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not fn then return nil end
    local ok, a = pcall(fn, spellID)
    if not ok or type(a) ~= "table" or ns.IsSecret(a) then return nil end
    return a
end

--- Where an aura was found: "direct", "list" (with its buff index), or nil.
function C.Find(spellID)
    local a = Direct(spellID)
    if a then return a, "direct" end
    local s = Scan()
    local hit = s.byID[spellID] or (NAMES[spellID] and s.byName[NAMES[spellID]])
    if hit then return hit.aura, "list", hit.index end
    return nil
end

local function InCombat()
    local ok, c = pcall(InCombatLockdown)
    return ok and c and true or false
end
C.InCombat = InCombat

-- In combat Forever hides aura data from addons (Alex, 2026-10-03: mid-fight
-- the buff list read 0 buffs and the panel went dark). So each aura's last
-- out-of-combat reading is kept, and combat plays it back: its expiry still
-- counts down, and it drops once that time passes.
local remembered = {}

--- An aura on the player by spell ID: { left = seconds or nil, dur } or nil.
-- Out of combat these are plain values; in combat, the last of those.
function C.Aura(spellID)
    if InCombat() then
        local m = remembered[spellID]
        if not m or (m.exp and m.exp <= Now()) then return nil end
        return { left = m.exp and math.max(0, m.exp - Now()) or nil, dur = m.dur, instance = m.instance, index = m.index }
    end
    local a, _, index = C.Find(spellID)
    if not a then remembered[spellID] = nil return nil end
    local exp, dur = a.expirationTime, a.duration
    exp = (Num(exp) and exp > 0) and exp or nil
    local r = { left = exp and math.max(0, exp - Now()) or nil, dur = Num(dur) and dur or nil,
        instance = Num(a.auraInstanceID) and a.auraInstanceID or nil, index = index }
    remembered[spellID] = { exp = exp, dur = r.dur, instance = r.instance, index = index }
    return r
end

function C.Nearby() return C.Aura(C.AURA.nearby) ~= nil end

--- The 1 minute sit: seconds left until benefits, or nil when not sitting.
function C.SitLeft()
    -- Combat stands you up and ends the sit: never play that one back.
    if InCombat() then return nil end
    for _, id in ipairs(C.AURA.sitting) do
        local a = C.Aura(id)
        if a then return a.left or 0, a.dur or 60 end
    end
    return nil
end

--- Camp Benefits: seconds left, or nil.
function C.BenefitsLeft()
    local a = C.Aura(C.AURA.benefits)
    return a and (a.left or 0) or nil
end

--- The boosts Camp Benefits lists, by feature name ("Lodestone" = true).
-- The "Boosted ..." auras are hidden from the addon aura API on Forever
-- (Alex, 2026-10-03: Lodestone's 1230164 was on him -- the Camp Benefits
-- tooltip printed it -- yet GetPlayerAuraBySpellID returned nothing), but
-- Camp Benefits' own tooltip names each one: "Lodestone: Melee Attack ...".
-- Camp Benefits' tooltip data: by its auraInstanceID, else by its place in
-- the buff list (in case the aura data carries no instance ID here).
local function BenefitsTooltip()
    local ti = C_TooltipInfo
    if not ti then return nil end
    local a = C.Aura(C.AURA.benefits)
    if not a then return nil end
    if a.instance and ti.GetUnitBuffByAuraInstanceID then
        local ok, data = pcall(ti.GetUnitBuffByAuraInstanceID, "player", a.instance)
        if ok and type(data) == "table" then return data end
    end
    if a.index and ti.GetUnitBuff then
        local ok, data = pcall(ti.GetUnitBuff, "player", a.index)
        if ok and type(data) == "table" then return data end
    end
    local byIndex = C_UnitAuras and C_UnitAuras.GetBuffDataByIndex
    if byIndex and ti.GetUnitBuff then
        for i = 1, 40 do
            local ok, aura = pcall(byIndex, "player", i)
            if not ok or type(aura) ~= "table" then break end
            if Num(aura.spellId) and aura.spellId == C.AURA.benefits then
                local okT, data = pcall(ti.GetUnitBuff, "player", i)
                if okT and type(data) == "table" then return data end
                break
            end
        end
    end
    return nil
end

local lastNames = {}
function C.BenefitNames()
    -- In combat the tooltip is as hidden as the auras: the last reading,
    -- while Camp Benefits (remembered) lasts.
    if InCombat() then return C.Aura(C.AURA.benefits) and lastNames or {} end
    local out = {}
    lastNames = out
    local data = BenefitsTooltip()
    if not (data and type(data.lines) == "table") then return out end
    for _, line in ipairs(data.lines) do
        local text = type(line) == "table" and ns.Str(line.leftText)
        -- The description is ONE tooltip line with line breaks inside
        -- ("Gained the following camp benefits:", a blank line, "Enchanted
        -- Lute: ..."): each feature starts its own inner line.
        if text then
            for part in text:gmatch("[^\r\n]+") do
                local name = part:match("^%s*([^:]+):")
                if name then out[name] = true end
            end
        end
    end
    return out
end

--- Each buff line: { line, label, spell, left (nil = missing) }. Lit by its
-- own aura when the API shows it, else by Camp Benefits naming it (the
-- boosts all run out with Camp Benefits).
function C.Buffs()
    local out = {}
    local names, benefits
    for _, l in ipairs(C.LINES) do
        if l.buff then
            local a = C.Aura(l.buff)
            local left = a and (a.left or 0) or nil
            if not left and l.feature then
                names = names or C.BenefitNames()
                if names[l.feature] then
                    benefits = benefits or C.BenefitsLeft() or 0
                    left = benefits
                end
            end
            out[#out + 1] = { line = l.key, label = l.buffLabel, spell = l.buff, left = left }
        end
    end
    return out
end

--- /sn campdebug: what the client says about Camp Benefits and each boost.
function C.Debug()
    local a = C.Aura(C.AURA.benefits)
    local _, how, index = C.Find(C.AURA.benefits)
    ns.Print(("Camp Benefits: %s, found %s%s, instance %s"):format(a and DebugLeft(a.left) or "not found",
        how or "nowhere", index and (" #" .. index) or "", a and tostring(a.instance) or "-"))
    local _, nearHow = C.Find(C.AURA.nearby)
    ns.Print(("Campfire Nearby: %s; buff list read %d buffs; %s"):format(nearHow or "not found", Scan().n,
        InCombat() and "IN COMBAT (aura data hidden: showing the last reading)" or "out of combat"))
    local names = {}
    for n in pairs(C.BenefitNames()) do names[#names + 1] = n end
    ns.Print("tooltip names: " .. (#names > 0 and table.concat(names, ", ") or "none"))
    for _, l in ipairs(C.LINES) do
        if l.buff then
            ns.Print(("%s (%d): %s"):format(l.label, l.buff, C.Aura(l.buff) and "aura found" or "no aura"))
        end
    end
end

-- ------------------------------------------------------------ bags

local function Count(id)
    local fn = (C_Item and C_Item.GetItemCount) or rawget(_G, "GetItemCount")
    if not fn then return 0 end
    local ok, n = pcall(fn, id)
    return ok and Num(n) and n or 0
end
C.Count = Count

--- Camping items you carry, by line then tier: { {id, name, line, tier, kit, count} }.
function C.Usables()
    local out = {}
    for id, it in pairs(C.ITEMS) do
        local n = Count(id)
        if n > 0 then
            out[#out + 1] = { id = id, name = it[1], line = it[2], tier = it[3], kit = it.kit or false, count = n }
        end
    end
    table.sort(out, function(a, b)
        if a.kit ~= b.kit then return a.kit end            -- campfires first
        local la, lb = LINE_ORDER[a.line] or 99, LINE_ORDER[b.line] or 99
        if la ~= lb then return la < lb end
        if a.tier ~= b.tier then return a.tier < b.tier end
        return a.id < b.id
    end)
    return out
end

--- An item's cooldown: start, duration (0, 0 when ready).
function C.Cooldown(id)
    local fn = (C_Container and C_Container.GetItemCooldown) or rawget(_G, "GetItemCooldown")
    if not fn then return 0, 0 end
    local ok, start, dur = pcall(fn, id)
    if not ok or not (Num(start) and Num(dur)) then return 0, 0 end
    return start, dur
end

--- Seconds until the shared feature cooldown is up (0 = ready), read from
-- any non-kit item carried; and the same for campfire kits.
function C.Shared(kit)
    for id, it in pairs(C.ITEMS) do
        if (it.kit or false) == (kit or false) and Count(id) > 0 then
            local start, dur = C.Cooldown(id)
            if dur > 0 then return math.max(0, start + dur - Now()) end
            return 0
        end
    end
    return nil                 -- nothing carried of that kind
end

--- Camping doesn't work inside instances (dungeons, raids, battlegrounds):
-- nothing camping shows there, whatever the mode or pin.
function C.InInstance()
    local ok, inInst = pcall(IsInInstance)
    if not ok or ns.IsSecret(inInst) then return false end
    return inInst and true or false
end

--- Should the panel be up? Always (Alex), except inside instances.
function C.WantShown()
    if ns.db and ns.db.unlocked then return true end
    return Enabled() and not C.InInstance()
end

ns.Commands = ns.Commands or {}
ns.Commands.campdebug = function() C.Debug() end

-- Aura and bag changes redraw the panel (the UI sets OnChanged).
local function Changed() if C.OnChanged then C.OnChanged() end end
ns.On("UNIT_AURA", function(unit) if unit == "player" then Changed() end end)
ns.On("BAG_UPDATE_DELAYED", Changed)
ns.On("BAG_UPDATE_COOLDOWN", Changed)
ns.On("PLAYER_REGEN_ENABLED", Changed)
ns.On("PLAYER_ENTERING_WORLD", Changed)
