# Writing addons for WoW Forever — what the client actually is

Measured 2026-09-19 with APIProbe v2 on client **1.60.1 build 69913** (built
Sep 17 2026), the `wow_classic_beta` product, realm "Classic Beta PvP". Full
census dump and generated report are under `apiprobe/dumps/`; re-run with
`/census` in game and `python install_probe.py --fetch wow_classic_beta`.

A second census on **retail 12.1.0 build 69875**, same day, validated the
probe (every name known present on retail reported present, every name known
removed reported absent, no truncation) and grounds every comparison in §8.
Where §8 says "retail", that is **measured**, not recollection.

**Two kinds of statement in this document, never blurred:**

- **Measured** — read off the live client by the census. Trust it.
- **Recollection** — what I remember of retail as of mid-2026. Trust it as far
  as a memory of a moving target deserves. Every one is labelled.

---

## 1. The one-paragraph answer

WoW Forever is **retail's client**, wholesale, serving vanilla content. It
reports `WOW_PROJECT_ID == WOW_PROJECT_MAINLINE`, carries the 12.x secret-value
system, and exposes **269 `C_*` namespaces** including ones for content that
does not exist in 1.60 — `C_Housing`, `C_Garrison` (227 functions),
`C_MythicPlus`, `C_Traits`, `C_PetBattles`, `C_DelvesUI`. Its `_G` holds 694
`HOUSING_*` strings. The vanilla-era globals every 1.x addon was built on —
`GetSpellInfo`, `UnitAura`, `GetItemInfo`, `GetTalentInfo` — are **gone**.

So: **write it like a retail 12.x addon, not like a Classic Era addon.**
Everything MerkUI learned the hard way about secret values, `C_*` namespaces
and the `Settings` API transfers directly. What does *not* transfer is any
assumption that a namespace being present means its feature works here.

## 2. The facts that decide how you code (all measured)

| question | answer | how measured |
|---|---|---|
| TOC interface number | **`16001`** | client reports it via `GetBuildInfo()`; computed as `1*10000 + 60*100 + 1` and confirmed on login |
| Mainline client? | **yes** — `WOW_PROJECT_ID = 1 = WOW_PROJECT_MAINLINE` | stage 1 |
| Secret values in force? | **yes** — `issecretvalue` is a function | stage 1, census |
| Secret values met at rest, out of combat | **1** of 48,111 globals (`COMBO_FRAME_LAST_NUM_POINTS`) | census |
| Event validity predicate | `C_EventUtils.IsEventValid` present | census |
| `C_*` namespaces | **269**, 5,181 members, none empty | census |
| Bare globals | 48,111 — 26,481 strings, 10,152 objects, 5,958 functions | census |
| `Enum.*` / `Constants.*` | 12,617 entries | census |
| Creatable widget types | **47 of 50** asked; `Minimap`, `POIFrame`, `ModelFFX` are not | census |
| SavedVariables location | `_classic_beta_/WTF/Account/1736596#1/SavedVariables/<AddOn>.lua` | on disk |
| Addons installed before this | **none** — empty `AddOns/` folder | on disk |

`1736596#1` has a `#` in it. Quote the path.

## 3. The trap: presence is not function

The census walks names. It does not — by design — call anything. On this
client that distinction matters more than usual, because **the retail UI
codebase shipped essentially unmodified**:

- `C_Housing`, `C_HousingLayout`, `C_HousingDecor`, `C_HousingCatalog` — 184
  functions for a feature that does not exist in vanilla.
- `C_Garrison` is the single largest namespace at 227 functions.
- Events `CHALLENGE_MODE_START`, `TRAIT_CONFIG_UPDATED`,
  `PLAYER_SPECIALIZATION_CHANGED` all report **valid** — that means the client
  recognises the name, not that anything will ever fire it.
- `Blizzard_Deprecated`, `Blizzard_DeprecatedSpellScript`,
  `Blizzard_Deprecated_ArenaUI` and `Blizzard_TimerunningUtil` were loaded when
  the census ran. Whether `Blizzard_Deprecated` installs compatibility shims
  for any removed global is **unknown** — the census cannot tell a shim from a
  native function, and no vanilla-era name I checked is present either way.

**Rule:** a namespace on Forever tells you the *shape* of the API you would
call. Whether it returns anything, or errors, or is a stub, is a behavioural
question the census cannot answer and must be tested on a throwaway
character before an addon depends on it.

## 4. Vanilla-era APIs that are gone, and where they went

All "absent" entries below are **measured** (the census walked the complete
`_G`, no truncation). The replacements are **recollection** of the retail
11.0–12.x removals, and the replacement namespace's *presence* on Forever is
measured. Whether the replacement *works* on vanilla content is not.

| gone (measured absent) | retail replacement (recollection) | replacement present here? (measured) |
|---|---|---|
| `GetSpellInfo`, `GetSpellCooldown`, `GetSpellTexture`, `GetSpellLink` | `C_Spell.GetSpellInfo` / `GetSpellCooldown` / `GetSpellTexture` / `GetSpellLink` | `C_Spell` — 72 functions |
| `UnitAura`, `UnitBuff`, `UnitDebuff` | `C_UnitAuras.GetAuraDataByIndex` / `GetBuffDataByIndex` / `GetDebuffDataByIndex`, `AuraUtil.ForEachAura` | `C_UnitAuras` — 39 functions |
| `GetItemInfo` | `C_Item.GetItemInfo` | `C_Item` — 121 functions |
| `GetContainerItemInfo` | `C_Container.GetContainerItemInfo` | `C_Container` — 47 functions |
| `LoadAddOn`, `IsAddOnLoaded`, `GetAddOnMetadata` | `C_AddOns.LoadAddOn` / `IsAddOnLoaded` / `GetAddOnMetadata` | `C_AddOns` — 29 functions |
| `InterfaceOptions_AddCategory` | `Settings.RegisterAddOnCategory` + `Settings.RegisterCanvasLayoutCategory` | `Settings` — present as a table (its members were not walked; it is not on the census allowlist) |
| `GetTalentInfo`, `GetNumTalents`, `GetActiveTalentGroup`, `GetSpecialization` | **unknown on this content** — see §7 | `C_Traits` (53), `C_SpellBook` (52), `C_ClassTalents` present |
| `CombatLogGetCurrentEventInfo` | — | **absent on retail 12.1 too (measured)** — a 12.x-wide removal, not a Forever quirk. `COMBAT_LOG_EVENT_UNFILTERED` is a valid event name on both. |
| `GetItemInfo`, `GetItemCount`, `GetItemIcon`, `GetItemCooldown`, `GetItemInfoInstant`, `GetActiveSpecGroup`, `GetCoinText` | `C_Item.*`, `C_SpecializationInfo.*` | **present on retail, absent on Forever.** See §8 — these are almost certainly deprecated-shim survivors on retail. |

**Survivors (measured present):** `GetInventoryItemLink`, `GetMacroInfo`,
`GetRaidRosterInfo`, `IsSpellKnown`, `UnitCastingInfo`. Do not read a pattern
into that list; it is five names I happened to check.

## 5. Idioms that exist here

**Measured present:** `C_*` namespaces (269), `Enum`, `Constants`, `Settings`,
`Mixin`, `CreateFromMixins`, `securecall`, `hooksecurefunc`, `C_Timer`,
`C_StringUtil` (12.x-only, recollection), `C_EventUtils.IsEventValid`,
`issecretvalue`, `CreateFrame("AuraContainer")`, `CreateFrame("EventFrame")`,
`CreateFrame("ItemButton")`, `CreateFrame("DropdownButton")`.

**Measured absent:** `InterfaceOptions_AddCategory` and the whole
`GetSpellInfo`-era global family.

### Secret values — the idiom that shapes everything

`issecretvalue` exists and only **one** global was secret at rest. That is
consistent with retail (recollection, and MerkUI's measured experience on
12.1): secret-ness is a *runtime, in-content* property — values go secret in
combat and in restricted content, not at the character select screen. So
the census cannot tell you which calls return secrets on Forever. What it
*can* tell you is that the machinery is live, so:

- every string, number or table that comes back from the client must be
  assumed possibly-secret until proven otherwise
- guard before `format`, `..`, `tostring`, comparison, arithmetic, `#`
- the MerkUI shim `local issecretvalue = _G.issecretvalue or function() return false end`
  is *not* needed for existence here (it exists) but costs nothing and keeps
  the code portable to a client where it does not

Two secret models the MerkUI harness already distinguishes apply unchanged:
a `W.secret(v)` table that throws on misuse proves misuse is fatal;
`W.secretString`/`secretNumber` that `issecretvalue` reports secret proves a
guard exists and is ordered right. Pick the wrong one and the test passes on
broken code.

### Widgets

47 of 50 types creatable. `Frame` has 218 methods, `Button` 260,
`ItemButton` 297, `Cooldown` 264, `GameTooltip` 248, `AuraContainer` 223 —
full lists in the generated report. The three that are not creatable —
`Minimap`, `POIFrame`, `ModelFFX` — error with `Unknown frame type`, and the
`Minimap` attempt raises a client-side Lua error popup even inside `pcall`
(harmless, but it is why `/census` shows a red box).

The discovery pass — every metatable `__index` seen on a *live* object that
matched no type the probe created — surfaced seven:

| live object | methods | what it is (recollection) |
|---|---|---|
| `Minimap` | 249 | the singleton `Minimap` widget type; not creatable, but its full method surface is readable off the live instance |
| `SlashCmdList` | 104 | Blizzard's metatable-driven slash command proxy, not a widget |
| `ChatTypeInfo` | 92 | a metatable-backed table |
| `QuestTitleFont` | 45 | a **`Font` object** — the census has no `CreateFont` path yet, so Font's surface is only known via this |
| `PET_BATTLE_AURA_ID_INFO` | 14 | a metatable-backed table |
| `Class_TutorialBase` | 7 | a Lua mixin, not a C type |
| `Object` | 6 | a Lua mixin |

### Events

**624 valid of 8,581 candidates.** Sampled, not enumerated: the candidates
are every `RegisterEvent` literal and every `SCREAMING_CASE` literal in 15,475
addon Lua files across four clients on this machine. An event no addon here
has ever mentioned is missing from the report — and, per §3, "valid" is not
"fires". `COMBAT_LOG_EVENT_UNFILTERED`, `UNIT_AURA`, `PLAYER_ENTERING_WORLD`,
`ENCOUNTER_START`, `GROUP_ROSTER_UPDATE`, `UNIT_SPELLCAST_START`,
`SPELLS_CHANGED`, `BAG_UPDATE` are all valid.

## 6. Practical loop

1. Put the addon under `_classic_beta_\Interface\AddOns\<Name>\`, TOC
   `## Interface: 16001`. `install_probe.py` shows the pattern: read the
   version from `.build.info`, compute the number, never hand-type it.
2. `## SavedVariables: <Var>`; nothing reaches disk until `/reload` or logout.
3. Gate every Lua file with `python lua_check.py <file>` — the client is Lua
   5.1 and `luaparser` alone accepts nine constructs it will reject.
4. The MerkUI headless harness (`merkui_test/`) runs real Lua 5.1 against a
   mock client and is the place to red-green logic before a login. It cannot
   validate *which APIs exist* — its `_G` is a curated subset and its frame
   metatable answers any capitalised method — so use it for "does it run",
   and the census dump for "does the name exist", and a throwaway character
   for "does it work".
5. Combat logging is enabled by hand, never automated.

## 7. What is still unknown, ranked by how much it would change an addon

1. **Which of two talent models serves the vanilla tree.** Both are present.
   Forever-only names point at a *spec-group* model —
   `C_SpecializationInfo.SetActiveSpecGroup`, `GetCombatConfigIDForSpecGroup`,
   `HasPlayerEarnedATalentPoint`, `IsSpecSelectionEnabled`, `Enum.RespecType`
   — while `C_Traits` (53 functions, shared with retail) and `C_ClassTalents`
   are also there. `Blizzard_SharedTalentUI` was loaded. Which one the 1.60
   tree actually answers through is a behavioural question; first thing to
   probe for any class-aware addon.
2. **Which values come back secret, and when.** Runtime, in-content. MerkUI's
   334-row secret audit on retail is the model for how to find out.
3. **Signatures and return shapes** for every function above. `C_Spell.GetSpellInfo`
   returning a table vs. a tuple is exactly the kind of thing that breaks silently.
4. **Whether the missing deprecated shims (§8) can be loaded on demand.**
   `C_AddOns.LoadAddOn("Blizzard_DeprecatedItemScript")` might restore
   `GetItemInfo` here, or the module might not ship. One call answers it.
5. **`Font` objects** — no `CreateFont` path in the census; the surface is known
   only via the live `QuestTitleFont`.

## 8. Forever vs retail 12.1 — measured, same day, same probe

Retail build **69875**; Forever build **69913**. Forever is on the *newer*
trunk, which explains most of what it has that retail lacks.

| | both | Forever only | retail only |
|---|---|---|---|
| `C_*` namespaces | 257 | 12 | 1 (`C_TableUtil`) |
| namespace members | 5,005 | 176 | 8 |
| bare globals | 43,134 | 4,977 | 4,601* |
| enum entries | 11,975 | 642 | 39 |
| widget methods | 9,844 | 228 | 0 |
| valid events | 623 | 1 (`UNIT_HAPPINESS`) | 0 |

\* retail had 44 more addons loaded (Ellesmere, BigWigs, Auctionator…), so
most retail-only globals are addon globals, not client API. Filter before
reading anything into that number.

### Forever-only surface that is just the newer engine (not vanilla)

`C_Intl` (27 — locale-aware formatting/collation), `C_BlizzCon2026`,
`C_GamepadUI`, `C_GamepadTargeting`, `C_InputInterfaceStyle`,
`C_AccountServices`, `C_VideoOptions`, `C_Timer.NewTimedSignalMap`,
`C_CVar.SetTempCVar`, and **six methods on every one of the 38 widget types**:
`FocusEnter`, `FocusExit`, `MouseDown`, `MouseUp`,
`GetRoundLayoutToNearestPixel`, `SetRoundLayoutToNearestPixel`. Expect these
to reach retail in a later build; do not build anything on them yet.

### Forever-only surface that IS the vanilla content API (measured present, absent on retail)

This is the list of what "replaced the old globals" for 1.60 content:

| area | names |
|---|---|
| skills | `C_SkillInfo` (8): `GetNumSkillLines`, `GetSkillLineInfo`, `GetSkillLineInfoByID`, `AbandonSkill`, … |
| game rules | `C_GameRules` (7): `IsHardcoreActive`, `IsSelfFoundAllowed`, `SelectClassicExperiencePreset` / `SelectModernExperiencePreset`, `AccountHasSDEnabled`, `IsSDHDToggleEnabled`, `SetSDHDToggleValue`; `Enum.GameRule` (21) |
| hunter pets | `C_PetInfo`: `GetPetHappiness`, `GetPetLoyalty`, `GetPetTrainingPoints`, `CanPetEatItem`, `GetPetFoodTypes`; event `UNIT_HAPPINESS`; `Constants.PetConsts` |
| talents | `C_SpecializationInfo`: `SetActiveSpecGroup`, `GetCombatConfigIDForSpecGroup`, `HasPlayerEarnedATalentPoint`, `IsSpecSelectionEnabled`, `GetAllClassIDs`; `Enum.RespecType`; `C_Traits.GetGroupCurrencyInfo` / `GetMaxAvailableTraitCurrency` |
| spell ranks | `C_SpellBook.IsSpellBookItemLowRank`, `GetClassSkillLineInfo`; `C_Spell.IsActiveSpell`, `CancelAutoRepeatSpell`, `GetTargetSpellID` |
| melee | `C_SwingTimer.IsTargetWithinSwingRange`, `EnableRangeCheck`; `Enum.EditModeSwingTimerSetting` |
| stats | globals `GetManaRegenFromSpirit`, `GetHealthRegenFromSpirit`, `GetArmorPenetration`, `GetCritChanceFromStat`, `GetSpellCritChanceFromStat`, `GetRangedAttackPowerForStat`, `GetRangedHitModifier`, `ExpectedSpellResistance`, `GetPetHitChanceModifier` |
| items | `C_PaperDollInfo.AmmoNeeded`, `C_Item.GetWeaponEnchantInfo`, `GetKeyRingSize`, `C_ActionBar.ShouldShowKeyring`; `Enum.BagIndex`, `Constants.LegacyConsts` |
| totems | `HasMultiCastActionBar`, `HasMultiCastActionPage`, `ChangeMultiCastActionPage` |
| group finder | `LFGBrowse*` globals (vanilla-style), `C_LFGListRoles`, `Blizzard_GroupFinder_VanillaStyle` loaded |
| misc | `C_Trainer.GetTrainerType`, `C_LootFrame.TryAutoLoot`, `C_AutoLoot`, `C_Weather.GetCurrentWeather`, `C_DateAndTime.IsDayTime`, `C_QuestLog.GetQuestTimers` / `IsEliteQuest` / `GetTrivialRange`, `C_StableInfo` (buy slots), `CanPortGraveyard`, `CheckHardcoreGuildLeadStatus` |

### The deprecated-shim gotcha (measured presence; the mechanism is inference)

On retail, `GetItemInfo`, `GetItemCount`, `GetItemIcon`, `GetItemCooldown`,
`GetItemInfoInstant`, `GetActiveSpecGroup`, `GetCoinText`, `GetItemFamily`,
`EquipItemByName` and a few dozen more are **present**. On Forever they are
**absent**. Retail's load list included `Blizzard_DeprecatedItemScript`,
`Blizzard_DeprecatedCurrencyScript`, `Blizzard_DeprecatedSpecialization`,
`Blizzard_DeprecatedLFG`, `Blizzard_DeprecatedPvpScript`,
`Blizzard_DeprecatedSoundScript`; Forever's included only
`Blizzard_Deprecated`, `Blizzard_DeprecatedSpellScript`,
`Blizzard_DeprecatedGuildScript`, `Blizzard_Deprecated_ArenaUI`.

The names line up too well to be coincidence, but the census cannot *prove*
the shim is the source — that is recollection of what those modules do. What
it proves is the practical part: **a retail addon that survives on
`GetItemInfo` will not survive here.** Use `C_Item.GetItemInfo` (121-function
namespace, present on both) from the start.

## 9. Dungeons, bosses, loot — what the client will and won't give (measured)

Probed with `/dungeons` (Dungeons.lua), the project's first probe that
*calls* things — read-only Encounter Journal and LFG calls, out of combat,
every value secret-checked before storage.

| want | source on Forever | result |
|---|---|---|
| **dungeon list** | `GetLFGDungeonInfo(id)` walked over IDs | **yes** — 71 entries with level: Wailing Caverns (17) … Molten Core (60). `forever_dungeons.md` / `.json` |
| **bosses per dungeon** | Encounter Journal | **no** — `EJ_GetNumTiers()` = 0, no errors, no missing functions. The 57-function API is present; the data behind it is not. |
| **loot per boss** | Encounter Journal | **no** — same reason, and loot tables were never client-side in any version; they are server data. |
| dungeon map IDs | `C_Map.GetMapInfo(id)` walked | first build filtered by `Enum.UIMapType.Dungeon` and got 0; now records every map annotated — re-run to populate |

**Bosses ARE obtainable — from the client's data tables, not its API.**
wago.tools serves every `.db2` table of build 1.60.1.69913 as CSV;
`fetch_db2.py` pulls them into `db2/<build>/` with a provenance manifest and
`forever_bosses.py` joins `DungeonEncounter.MapID → Map.ID` into
`forever_instances.md/.json`: 38 dungeon maps, 13 raid maps, 340 bosses in
order, each with the encounter ID `ENCOUNTER_START` fires with. Measured
quirks of this build: `LFGDungeons.MapID` is 0 on every row (levels join by
name, annotated); the `Journal*` tables do not exist at all ("table not
found"), which settles the Encounter Journal from the files side.

**The roster is not vanilla's — and the split is measured**, by comparing
the Map and DungeonEncounter tables against Classic Era 1.15.9 (the SoD
client): a map present in Era is SoD, one absent is new.

- *SoD, identical boss lists in both builds:* Karazhan Crypts (11), Scarlet
  Enclave (40-man, 8), Demon Fall Canyon (7), Nightmare Grove (raid, 4), the
  world-boss arenas Storm Cliffs / The Tainted Scar / The Crystal Vale (1
  each), The Searing Basin (1), a second Naxxramas map (2921, 1), and the
  boss-less event maps Shadow Hold, Starfall Barrow Den, Burning of Andorhal,
  Deadwind Pass, The Scarab Dais.
- *New to Forever:* The Hall of Thanes (4 bosses, level 13), City of Dalaran
  (9, level 28), Ruins of Lordaeron (7, level 15), Excavation Site: Wetlands
  (4, level 26), Half-Pint Tavern (2), Manor Mistmantle (0 yet), Hyjal Crater
  (arena, 0), and two battlegrounds, Darkspear Islands and Battle for Gilneas.

Forever's data is SoD's plus new content; 341 boss rows vs Era's 307.

**Boss models (for a codex-style viewer) — obtainable, by a different route
than retail.** MerkUI's viewer did `PlayerModel:SetDisplayInfo(id)` with IDs
from `EJ_GetCreatureInfo`; the journal is empty here, and `Creature.db2` on
this build holds only 178 rows (pets and mounts), so boss → display ID is
server data. But the client writes every NPC it sees to
`Cache/WDB/enUS/creaturecache.wdb` — NPC ID, name, and the display IDs with
scale/probability. `parse_creaturecache.py` reads it (layout measured on
build 69913: 24-byte header, `(entry, length, payload)` frames, name at byte
15, model block `count, total, (displayID, scale, prob)×count`; every
displayID is validated against `CreatureDisplayInfo`, 14,092 rows) into
`forever_creatures.json`, and `forever_bosses.py` joins it in. After one
visit to a dungeon its bosses are in the cache; `PlayerModel` is creatable
here (census), so the viewer is the same code with a different ID source.
Measured 2026-09-19: 1,075 cached NPCs, all decoded; the 8 bosses of Hall
of Thanes and Ruins of Lordaeron already resolved (e.g. Plunder npc 261311 →
display 142840). Reading the cache is reading our own client's file; it is
never written.

**Loot is still not obtainable from the client** — in no table, any
version. Routes: Wowhead-style aggregation (which will not know the new
instances for a while), or your own `CHAT_MSG_LOOT` observation; the
`ItemSparse` table (19,172 items, IDs up to 286427) resolves any observed
item ID to name/quality/level/slot offline.

## 10. Live encounter feeds — what a boss mod could be built on here

**Blizzard's Encounter Timeline: machinery present, data absent.** The census
measured the whole `C_EncounterTimeline` namespace (40 functions), all six
`ENCOUNTER_TIMELINE_*` events valid, and the string
`COMBAT_WARNINGS_ENABLE_ENCOUNTER_TIMELINE_NOT_AVAILABLE`. Alex's
observation (2026-09-19, low-level dungeons): no timeline ever appears, and
it is not offered in Edit Mode / settings — which is what Blizzard's own UI
does when `IsFeatureAvailable()` is false. Treat it as deliberately off for
this content. Not probe-measured; one call would confirm.

**How BigWigs works, read from its source in `_retail_`:** two engines. The
retail 12.x `BossPrototype.lua` is timeline-driven (60 `GetEventState`
calls, `ENCOUNTER_TIMELINE_EVENT_ADDED` in 47 places) plus unit spellcast,
engage and target events; its CLEU registration code is still present but
MerkUI measured CLEU as `ADDON_ACTION_FORBIDDEN` on 12.1. The
Vanilla/TBC/Wrath builds load `BossPrototype_Classic.lua`: CLEU + boss
emotes/yells + `INSTANCE_ENCOUNTER_ENGAGE_UNIT` + spellcast + nameplates,
hard-coded timers fired by observed events.

**`COMBAT_LOG_EVENT_UNFILTERED` is CLOSED to addons on Forever — measured
2026-09-19.** CleuTest.lua's one `RegisterEvent` at login raised the
"blocked from an action only available to the Blizzard UI" popup
(`ADDON_ACTION_FORBIDDEN`) in the open world, before any combat — identical
to retail 12.1 (landmine 18). The recorded mechanism matters for anyone
writing defensive code here: **the call does not throw.** `pcall` returned
true, `ADDON_ACTION_FORBIDDEN` fired with payload `APIProbe`, `UNKNOWN()`,
and `IsEventRegistered` read **false** afterwards. So a protected registration
fails silently to the caller; the only detection is the forbidden event or
checking `IsEventRegistered` after the fact. `CombatLogGetCurrentEventInfo`
is absent besides, so even a delivered event would have had no readable
payload. With the timeline also off, this is the world
a live boss mod on Forever lives in:

- BigWigs Vanilla's engine (CLEU-driven) **cannot** work here as written.
- What an addon can observe live: `UNIT_SPELLCAST_START/SUCCEEDED/
  CHANNEL_START/INTERRUPTED` on units it can see (boss, target, nameplates),
  `CHAT_MSG_RAID_BOSS_EMOTE` / `CHAT_MSG_MONSTER_YELL`, `INSTANCE_ENCOUNTER_
  ENGAGE_UNIT`, `ENCOUNTER_START/END`, `UNIT_HEALTH`, `BOSS_KILL` — with 12.x
  secret-value rules on the payloads in combat.
- Timing knowledge must come from **outside** the live client: the combat
  log file, mined into per-boss schedules. A time-since-pull display keyed
  on `ENCOUNTER_START` is therefore the primary live tool, not a fallback.
  Alex's bars-only rule is consciously relaxed for Forever on that basis;
  the display must be labelled as learned and gated on cross-pull agreement.

**The combat log FILE is unaffected either way**: written below Lua, no
secrets, same 12.x format `parse_logs.py` already reads (`--logs` and
`--build 1.60` are the only switches). It answers the schedule question
regardless of what the live feeds do.

**What the live client delivers in a dungeon boss fight — measured
2026-09-19, Faldrim Anvilmar (encounter 3493), TriggerProbe.lua:**

| trigger | delivered? | readable? | verdict |
|---|---|---|---|
| pull — `ENCOUNTER_START` | yes | encounter ID **readable** (3493) | **works** |
| time since pull | follows from pull + `GetTime()` | — | **works** |
| boss unit frames — `boss1` | **does not exist** 1s after pull | — | casts/health only via `target` / nameplates |
| boss cast — `UNIT_SPELLCAST_START/SUCCEEDED` on target/nameplate | yes, on time (+6.5s matched the file's Mind Blast) | spell ID **secret 7/7**, cast GUID secret | "target started casting *something*" works; "cast X" does not |
| boss health — `UnitHealth(target)` | event fires (912×) | value **secret 912/912** | dead |
| boss emote — `CHAT_MSG_MONSTER_YELL` | 2 yells | **1 readable, 1 secret** (death yell readable, pull yell not) | partial; needs more fights to see the rule |
| own casts — `UNIT_SPELLCAST_SUCCEEDED` player | 95 | (not split in this probe) | expected readable per retail measurement |

The same pull in the file log: `ENCOUNTER_START,3493,"Faldrim Anvilmar",1,5,3065`,
the boss GUID carrying NPC 261306, `SPELL_CAST_START … "Mind Blast"` at
+6.5s, `"Anvilmar's Curse"` at +11.3s, kill at 26s. Header:
`BUILD_VERSION,1.60.1,PROJECT_ID,18` — the log calls Forever project **18**
while Lua's `WOW_PROJECT_ID` says 1. Advanced logging works.

**So Mercury's live vocabulary is pull, time-since-pull, "boss is casting"
(unnamed), and some emotes; every named ability and every timing comes from
the file.** Which is the design already chosen; now it is measured.

## 11. SavedVariables do not survive a client restart — measured

**The rule (build 69913, account `1736596#1`, 2026-09-19):** a SavedVariables
file that already exists on disk when `WowB.exe` starts is **never loaded** in
that process — not at login, not on any later `/reload`. A file the running
process creates itself is restored on every `/reload` after. Writing always
works; only the read of a pre-existing file fails.

How it was pinned down, because the path there was five wrong theories long:

| process | file existed at launch? | restored on later reloads? |
|---|---|---|
| 1 | no — first login created it | yes; `runs` climbed 1→5 |
| 2 (02:35) | APIProbe: yes | never |
| 3 (03:53) | APIProbe yes / SVTest no | APIProbe never / SVTest yes |
| 4 | both yes | neither, two reloads |
| 5 — files held aside, launch, reload | both no | **both restored (#1 → #2)** — the prediction |

Every on-disk version parses and executes under real Lua 5.1; the client
reports the addon `loadable`, `security=INSECURE`, `enable=2`; no
`ADDON_ACTION_FORBIDDEN`; no `SAVED_VARIABLES_TOO_LARGE`; size irrelevant
(34-byte and 2.8 MB files behave identically). SVTest (`svtest/`) is a
one-file control addon that reproduces it.

**It hits Blizzard's own UI too — measured.** Alex created a Combat Log
chat-tab filter ("amgtest") and `/reload`ed: the filter was gone from the
UI, and `Blizzard_CombatLog.lua` on disk (written 04:10:50) contains it.
`Blizzard_CombatLog.lua` has existed since Sep 17, so in every process
since it is a pre-existing file: written, never read. Blizzard's data
follows the same rule as addon data, which makes this a client bug, not an
addon-loading policy, and bug-report material (`Blizzard_PTRFeedback` is
loaded on this client — the in-game beta feedback tool is the channel).

**Likely cause (not measured):** the account folder is `1736596#1`, and a
`#` in a path is exactly what a startup-time directory scan might treat as a
comment or fragment while the write path, which never parses the path,
works.

**What it means for building here:**
- Any addon's settings and data are lost on every client restart, on this
  account, until Blizzard fixes it. A per-character test
  (`## SavedVariablesPerCharacter`) is the one untried variant; the path
  still contains the `#`, so expect the same.
- For the probes it does not matter: SavedVariables still work as an
  *output* channel — the file is written at `/reload`, and `install_probe.py
  --fetch` reads the file, not the client. Fetch after every reload; never
  expect a dump to survive a launch.
- Three working rules that each cost something today: the client owns its
  SavedVariables files while it runs (an on-disk edit is overwritten before
  it is read); `/reload` re-enters the same process; check the process
  start time before reasoning about "sessions".

## 12. What the census structurally cannot say

Stated here so this document is not over-read: no signatures, no return
shapes, no behaviour, no "it works", no "you're allowed to call it", no
event payloads, no event coverage beyond the candidate list, nothing inside a
`Blizzard_*` module that had not loaded, no XML / templates / intrinsic
attributes, no string contents. Every one of those needs a behavioural probe,
which is a different tool with a different safety argument.

## 13. Addon-supplied fonts DO load; the first SetFont lies (corrected 2026-09-19)

An earlier version of this section said the client refuses every font file
under `Interface/AddOns/...`. That was a probe artefact. What is actually
measured: the FIRST `FontString:SetFont()` on an addon font that the client
has not loaded yet returns false while the file loads in the background;
the string then renders in that font once loading finishes, and every later
SetFont of the same path returns true. A probe that sets sixty fonts once,
in one frame, and reads the return values therefore reports every addon
font as rejected while Bazooka and Mercury draw them fine. A missing file
still errors ("Invalid font asset ... file not found"). Blizzard's own
`Fonts/*.ttf` return true at once because they are already loaded.

Consequences in Mercury (`mercury/Fonts.lua`): LibSharedMedia fonts are
listed without probing; the picker re-applies its rows 0.25 s and 1.5 s
after opening; a global-font failure is retried a second later and only
the retry failing prints a warning; login re-fonts every string that
follows the global font.
