"""
Parse WoW combat logs into a dungeon dataset: every mob, every ability it cast,
what it hit for, how much health it had, and where it stood.

Why logs instead of an addon: the client already writes everything an addon
could observe, plus advanced-logging fields an addon has to work to get. The
logs going back months are a complete corpus that needs no further play.

Usage:
    python parse_logs.py                  # current patch only (default 12.1)
    python parse_logs.py --build 12.0     # widen to the previous patch
    python parse_logs.py --build ""       # every log, all builds

Output: dungeon_data.json next to this script.
"""

import argparse
import csv
import io
import json
import os
import re
from collections import defaultdict
from datetime import datetime

LOG_DIR = r"C:\Program Files (x86)\World of Warcraft\_retail_\Logs"


# Shared. The old rsplit("-", 1) returned None for a positive UTC offset, and
# an ENCOUNTER_START whose prefix will not parse drops the whole encounter
# with nothing printed -- see the unparsed-prefix counter below.
from log_time import line_time

# Subevents worth parsing. Everything else is skipped before any CSV work.
CAST_EVENTS = {"SPELL_CAST_START", "SPELL_CAST_SUCCESS"}
# SWING_DAMAGE_LANDED is a separate subevent from SWING_DAMAGE and carries its
# own advanced block -- 11k lines per log that were previously ignored.
SWING_EVENTS = {"SWING_DAMAGE", "SWING_DAMAGE_LANDED"}
DAMAGE_EVENTS = {"SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE"} | SWING_EVENTS
AURA_EVENTS = {"SPELL_AURA_APPLIED"}
# SPELL_SUMMON belongs here. Without it the `subevent not in WANTED` skip
# returns BEFORE the player-summon filter ~250 lines down, so that filter has
# never executed, stats["player_summons"] is always empty, and the line that
# prints "mobs dropped as player summons: 0" is structurally incapable of
# printing anything else. The module docstring credits that filter with
# catching Army of the Dead ghouls; mine_boss_schedules implements the same
# rule correctly, so the two parsers disagreed on a documented rule.
OTHER_EVENTS = {"SPELL_INTERRUPT", "UNIT_DIED", "ZONE_CHANGE", "CHALLENGE_MODE_START",
                "ENCOUNTER_START", "ENCOUNTER_END", "SPELL_SUMMON"}

# Casters ignored inside encounters: the seasonal affix "boss" casts on every
# fight and is not part of any encounter's own script.
ENCOUNTER_IGNORE_CASTERS = {"Xal'atath"}
WANTED = CAST_EVENTS | DAMAGE_EVENTS | AURA_EVENTS | OTHER_EVENTS

# Only these carry an advanced block. Verified against real 12.1.0 lines:
# SPELL_CAST_START and SPELL_AURA_APPLIED end at the school/aura field with no
# advanced data, so counting their absence as a failure just produces a scary
# meaningless number.
ADVANCED_EVENTS = DAMAGE_EVENTS | {"SPELL_CAST_SUCCESS"}

# Base fields every combat log event carries, in the FILE format:
#   subevent, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
#   destGUID, destName, destFlags, destRaidFlags   = 9
# The addon API (CombatLogGetCurrentEventInfo) additionally returns timestamp
# and hideCaster, so its spell fields sit 2 later. Do not copy offsets between
# the two -- that mistake silently dropped every SPELL_ event on the first run
# here, because int("0x1") just raises and the event gets skipped.
BASE = 9

# Advanced-logging block, present when the header says ADVANCED_LOG_ENABLED,1.
# It sits between the spell fields and the suffix fields:
#   infoGUID, ownerGUID, currentHP, maxHP, <8 stat/power fields>,
#   positionX, positionY, uiMapID, facing, level
# NOTE: the middle of this block has grown across expansions, so nothing here
# trusts a hardcoded offset blindly -- ReadAdvanced validates that the block
# actually looks like one (GUID first, plausible numbers at the end) and
# returns None instead of guessing when it doesn't.
# Verified by hand against a real 12.1.0 line, counting from infoGUID:
#   1 infoGUID  2 ownerGUID  3 currentHP  4 maxHP  5..14 stats/power
#   15 positionX  16 positionY  17 uiMapID  18 facing  19 level
ADV_LEN = 19
ADV_POS_X = 14   # 0-based within the block
ADV_POS_Y = 15
ADV_MAP = 16
ADV_LEVEL = 18

GUID_RE = re.compile(r"^(Creature|Vehicle|Player|Pet|GameObject)-")

# COMBATLOG_OBJECT_CONTROL_PLAYER. Player pets, guardians and totems (Rune
# Weapon, Wild Imp, Capacitor Totem) all get Creature- GUIDs, so without this
# they land in the dungeon's mob list looking like enemies -- one showed up as
# a level 302 "mob" with 800k health, which is what gave the game away.
CONTROL_PLAYER = 0x100
# COMBATLOG_OBJECT_REACTION_HOSTILE. Two more filters on top of the control
# flag (Alex, 2026-09-07: Lesser Ghoul, Magus of the Dead, Primal Fire
# Elemental, Lindormi, Ritual Snake all reached the Codex as "mobs"):
#   * anything a player SPELL_SUMMONs is a player's creature no matter what
#     flags it carries later -- Army of the Dead ghouls log as 0xa28 (NPC
#     control, neutral) on some events, so the control flag alone misses them;
#   * a creature never seen HOSTILE as a source (the keystone NPC, ritual
#     snakes, friendly escorts) isn't trash either.
REACTION_HOSTILE = 0x40


def player_controlled(flags):
    try:
        return bool(int(flags, 16) & CONTROL_PLAYER)
    except (ValueError, TypeError):
        return False


def npc_id_and_instance(guid):
    """Creature-0-3782-2993-43520-26125-00001A4278 -> (26125, 2993)."""
    if not guid or not guid.startswith(("Creature-", "Vehicle-")):
        return None, None
    parts = guid.split("-")
    if len(parts) < 7:
        return None, None
    try:
        return int(parts[5]), int(parts[3])
    except ValueError:
        return None, None


def read_advanced(fields, start):
    """Return the advanced block as a dict, or None if it doesn't validate."""
    block = fields[start:start + ADV_LEN]
    if len(block) < ADV_LEN:
        return None
    if not GUID_RE.match(block[0]):
        return None
    try:
        return {
            "info_guid": block[0],
            "current_hp": int(block[2]),
            "max_hp": int(block[3]),
            "x": float(block[ADV_POS_X]),
            "y": float(block[ADV_POS_Y]),
            "map": int(block[ADV_MAP]),
            "level": int(block[ADV_LEVEL]),
        }
    except (ValueError, IndexError):
        return None


def new_mob():
    return {
        "name": None,
        "level": None,
        "max_hp": 0,
        "deaths": 0,
        "events": 0,
        "hostile": False,         # seen as a hostile source at least once
        "positions": [],          # capped sample, for pack clustering later
        "map": None,
        "spells": defaultdict(lambda: {
            "name": None,
            "school": None,
            "cast_start": 0,
            "cast_success": 0,
            "hits": 0,
            "damage_total": 0,
            "damage_max": 0,
            "aura_applied": 0,
            "aura_type": None,
            "interrupted": 0,
        }),
    }


MAX_POSITION_SAMPLES = 300

# Distance (yards) within which two spawns on the same floor are treated as one
# pull. MDT encodes this as a hand-authored group id; here it has to be
# inferred, and 14 yards is about the radius of a normal trash pack -- close
# enough that they aggro together, far enough not to swallow the next camp.
PACK_RADIUS = 14.0


def mark_hostile(dungeons, guid, flags):
    """Flag the mob behind `guid` hostile from the flags on ITS side of the line.

    `hostile` used to be set only from source_flags, so a mob that never acted
    -- one that got focused down before casting, or that only ever takes hits
    -- never earned the flag and was deleted at output time. That cost 10 real
    trash mobs (Dominated Brawler, Enthralled Shaman, Spark Channeler and
    friends, all with recorded deaths) and 92 spawn positions, so whole camps
    were missing from the pack map.
    """
    npc, inst = npc_id_and_instance(guid)
    if npc is None or not inst:
        return
    try:
        if int(flags, 16) & REACTION_HOSTILE:
            dungeons[inst]["mobs"][npc]["hostile"] = True
    except (ValueError, TypeError):
        pass


def new_spawn():
    return {"npc": None, "name": None, "map": None, "level": None,
            "hp": 0, "seen": 0, "xs": [], "ys": []}


def median(values):
    s = sorted(values)
    n = len(s)
    if not n:
        return None
    return s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2.0


def cluster_packs(spawns):
    """Single-linkage clustering of spawn centroids, per floor.

    Deliberately simple: mobs that stand within PACK_RADIUS of each other, on
    the same uiMapID, are one pack. This is inference, not ground truth -- a
    patrol logged mid-route can chain two camps together, and a mob only ever
    seen while dragged will sit where it died, not where it lived.
    """
    by_map = defaultdict(list)
    for s in spawns:
        if s["x"] is not None:
            by_map[s["map"]].append(s)

    pack_id = 0
    for _, group in sorted(by_map.items(), key=lambda kv: str(kv[0])):
        unassigned = list(group)
        while unassigned:
            seed = unassigned.pop()
            pack_id += 1
            seed["pack"] = pack_id
            frontier = [seed]
            while frontier:
                cur = frontier.pop()
                still = []
                for other in unassigned:
                    dx = other["x"] - cur["x"]
                    dy = other["y"] - cur["y"]
                    if (dx * dx + dy * dy) ** 0.5 <= PACK_RADIUS:
                        other["pack"] = pack_id
                        frontier.append(other)
                    else:
                        still.append(other)
                unassigned = still
    return pack_id


def parse_file(path, dungeons, zone_names, stats, encounters):
    with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
        header = fh.readline()
        advanced = "ADVANCED_LOG_ENABLED,1" in header
        current_enc = None   # the ENCOUNTER_START..END we're inside, if any

        def close_on_death():
            # Forever sometimes never sends ENCOUNTER_END (Mr. Smite, Deadmines
            # 2026-09-20: he died at 11:06:00, the log ran on for 7 minutes with
            # no END). The boss's own UNIT_DIED is then the end of the pull, as
            # a kill. Anything else left open at the next START / EOF is dropped.
            nonlocal current_enc
            enc = current_enc
            current_enc = None
            if not enc or enc.get("t0") is None or enc.get("boss_died_at") is None:
                return
            enc["length"] = round(enc["boss_died_at"] - enc["t0"], 1)
            enc["success"] = True
            enc["closed_by"] = "boss death (no ENCOUNTER_END)"
            finish(enc)
            encounters[enc["name"]].append(enc)

        def finish(enc):
            # Working fields out; casts in time order (the client writes a
            # few lines out of order, and every consumer assumes sorted).
            for k in ("t0", "boss_died_at", "boss_guid", "_recent"):
                enc.pop(k, None)
            enc["casts"].sort(key=lambda c: c[0])

        for line in fh:
            # Split the "M/D/YYYY HH:MM:SS.mmm-Z  PAYLOAD" prefix off cheaply.
            split = line.split("  ", 1)
            if len(split) != 2:
                continue
            payload = split[1].rstrip("\n")

            comma = payload.find(",")
            if comma == -1:
                continue
            subevent = payload[:comma]
            if subevent not in WANTED:
                continue

            try:
                fields = next(csv.reader([payload]))
            except (csv.Error, StopIteration):
                stats["unparseable"] += 1
                continue

            if subevent == "ENCOUNTER_START":
                # ENCOUNTER_START,<encounterID>,"<name>",<difficulty>,<groupSize>,<instanceID>
                close_on_death()
                t0 = line_time(split[0])
                current_enc = {
                    "name": fields[2] if len(fields) > 2 else "?",
                    "encounter_id": int(fields[1]) if len(fields) > 1 and fields[1].isdigit() else None,
                    "difficulty": fields[3] if len(fields) > 3 else None,
                    "file": os.path.basename(path),
                    "t0": t0,
                    "boss_guid": None, # the first unit with the boss's name to act
                    "casts": [],       # [offset, spellID, spellName, caster, "start"|"success"]
                }
                continue
            if subevent == "ENCOUNTER_END":
                if current_enc and current_enc["t0"] is not None:
                    t1 = line_time(split[0])
                    current_enc["length"] = round(t1 - current_enc["t0"], 1) if t1 else None
                    current_enc["success"] = (fields[5] == "1") if len(fields) > 5 else None
                    finish(current_enc)
                    encounters[current_enc["name"]].append(current_enc)
                current_enc = None
                continue

            if subevent == "ZONE_CHANGE":
                # ZONE_CHANGE,2993,"Altar of Fangs" -- the id matches the
                # instance field inside creature GUIDs, which is how mobs get
                # attributed to a dungeon without needing a keystone start.
                try:
                    zone_names[int(fields[1])] = fields[2]
                except (ValueError, IndexError):
                    pass
                continue

            if subevent == "CHALLENGE_MODE_START":
                try:
                    inst = int(fields[2])
                    zone_names[inst] = fields[1]
                    dungeons[inst]["keystone_runs"] += 1
                except (ValueError, IndexError):
                    pass
                continue

            source_guid = fields[1] if len(fields) > 1 else ""
            source_name = fields[2] if len(fields) > 2 else ""
            source_flags = fields[3] if len(fields) > 3 else ""
            dest_guid = fields[5] if len(fields) > 5 else ""
            dest_name = fields[6] if len(fields) > 6 else ""
            dest_flags = fields[7] if len(fields) > 7 else ""

            if subevent == "SPELL_SUMMON" and source_guid.startswith(("Player-", "Pet-")):
                snpc, _ = npc_id_and_instance(dest_guid)
                if snpc:
                    stats.setdefault("player_summons", set()).add(snpc)
                continue

            if subevent == "UNIT_DIED":
                # The boss's death: by GUID once one unit of that name has
                # acted (an add with the boss's name must not close the pull),
                # by name until then.
                if current_enc is not None and current_enc.get("boss_died_at") is None:
                    bg = current_enc.get("boss_guid")
                    if (bg and dest_guid == bg) or (not bg and dest_name == current_enc["name"]):
                        current_enc["boss_died_at"] = line_time(split[0])
                npc, inst = npc_id_and_instance(dest_guid)
                if npc and not player_controlled(dest_flags):
                    mob = dungeons[inst]["mobs"][npc]
                    mob["name"] = mob["name"] or dest_name
                    mob["deaths"] += 1
                    mark_hostile(dungeons, dest_guid, dest_flags)
                continue

            if subevent == "SPELL_INTERRUPT":
                # Credit the interrupt to the spell that got kicked, which is
                # the "extra" spell -- its position depends on whether the
                # advanced block is present, so locate it from the end.
                npc, inst = npc_id_and_instance(dest_guid)
                if npc and not player_controlled(dest_flags) and len(fields) >= 3:
                    try:
                        extra_id = int(fields[-3])
                        extra_name = fields[-2]
                        mob = dungeons[inst]["mobs"][npc]
                        spell = mob["spells"][extra_id]
                        spell["name"] = spell["name"] or extra_name
                        spell["interrupted"] += 1
                        mark_hostile(dungeons, dest_guid, dest_flags)
                    except (ValueError, IndexError):
                        pass
                continue

            # Where the advanced block would start for this event, worked out
            # BEFORE deciding whose event it is -- because the block is worth
            # harvesting even when a player caused the event (see below).
            if subevent in SWING_EVENTS:
                spell_id, spell_name, school = 0, "Melee", None
                adv_start = BASE
            else:
                try:
                    spell_id = int(fields[BASE])
                except (ValueError, IndexError):
                    continue
                spell_name = fields[BASE + 1] if len(fields) > BASE + 1 else None
                school = fields[BASE + 2] if len(fields) > BASE + 2 else None
                adv_start = BASE + 3

            # --- Spawn harvesting -------------------------------------------
            # The advanced block describes whichever unit its own leading GUID
            # names: the CASTER for a cast, the VICTIM for damage. So every
            # time one of your players hits a mob, the log states that mob's
            # position and health. Those player-sourced lines are ~75% of the
            # file, so harvesting them is the difference between "positions for
            # mobs that happened to cast" and "positions for every mob anyone
            # ever touched".
            #
            # Spawns are keyed by the FULL GUID, not npcID: the same npcID is
            # spawned in packs all over a dungeon, and averaging them together
            # produced a "Primal Serpent" whose position samples spanned 408
            # yards -- a centroid of nothing real.
            if advanced and subevent in ADVANCED_EVENTS:
                adv = read_advanced(fields, adv_start)
                if adv:
                    stats["advanced_ok"] += 1
                    info_guid = adv["info_guid"]
                    if info_guid == source_guid:
                        info_name, info_flags = source_name, source_flags
                    elif info_guid == dest_guid:
                        info_name, info_flags = dest_name, dest_flags
                    else:
                        info_name, info_flags = None, None
                    if info_name is not None and not player_controlled(info_flags):
                        mark_hostile(dungeons, info_guid, info_flags)
                        inpc, iinst = npc_id_and_instance(info_guid)
                        if inpc is not None and iinst:
                            sp = dungeons[iinst]["spawns"][info_guid]
                            if sp["npc"] is None:
                                sp["npc"] = inpc
                                sp["name"] = info_name
                                sp["map"] = adv["map"]
                                sp["level"] = adv["level"]
                            sp["hp"] = max(sp["hp"], adv["max_hp"])
                            sp["seen"] += 1
                            if len(sp["xs"]) < MAX_POSITION_SAMPLES:
                                sp["xs"].append(adv["x"])
                                sp["ys"].append(adv["y"])
                            stats["spawn_samples"] += 1
                else:
                    # A genuine surprise: an event that should have carried a
                    # block and didn't validate. Worth watching after a patch.
                    stats["advanced_bad"] += 1

            # --- Ability aggregation, mob-sourced events only ----------------
            npc, inst = npc_id_and_instance(source_guid)
            if npc is None:
                continue
            if player_controlled(source_flags):
                stats["player_pets_skipped"] += 1
                continue

            # Inside a boss encounter, record the hostile cast stream with its
            # offset from the pull -- this is what the boss ability queue is
            # learned from. Cast START is the sequence; SUCCESS gives cast time.
            # A hostile SPELL_SUMMON is an ability too (VanCleef's add waves):
            # it lands in the stream as a "success" so the generator treats it
            # like any instant cast, and cast_health reads the summoner's
            # health off its last advanced block.
            # Nothing after the boss's death belongs to the pull: with no
            # ENCOUNTER_END the pull stays open and the trash that follows
            # would pour in (Mr. Smite: 25 Squallshaper casts, 2026-09-20).
            if current_enc is not None and (subevent in CAST_EVENTS or subevent == "SPELL_SUMMON") \
                    and source_name not in ENCOUNTER_IGNORE_CASTERS and current_enc["t0"] is not None \
                    and current_enc.get("boss_died_at") is None:
                t = line_time(split[0])
                if t is not None:
                    if current_enc["boss_guid"] is None and source_name == current_enc["name"]:
                        current_enc["boss_guid"] = source_guid
                    off = round(t - current_enc["t0"], 1)
                    kind = "start" if subevent == "SPELL_CAST_START" else "success"
                    # A summon spell logs SPELL_CAST_SUCCESS and SPELL_SUMMON for
                    # the same cast at the same instant (Eject Sneed): one entry.
                    # Keyed by the caster's GUID, not its name: two Lesser Stone
                    # Golems trampling at 8.6 s are two casts (Hall of Thanes).
                    recent = current_enc.setdefault("_recent", [])
                    dup = kind == "success" and any(
                        g == source_guid and sid == spell_id and abs(o - off) <= 0.2 for g, sid, o in recent)
                    if not dup:
                        current_enc["casts"].append([off, spell_id, spell_name, source_name, kind])
                        if kind == "success":
                            recent.append((source_guid, spell_id, off))
                            del recent[:-8]

            bucket = dungeons[inst]
            mob = bucket["mobs"][npc]
            mob["name"] = mob["name"] or source_name
            mob["events"] += 1
            try:
                if int(source_flags, 16) & REACTION_HOSTILE:
                    mob["hostile"] = True
            except (ValueError, TypeError):
                pass
            stats["mob_events"] += 1

            spell = mob["spells"][spell_id]
            spell["name"] = spell["name"] or spell_name
            spell["school"] = spell["school"] or school

            if subevent in CAST_EVENTS:
                key = "cast_start" if subevent == "SPELL_CAST_START" else "cast_success"
                spell[key] += 1
            elif subevent in AURA_EVENTS:
                spell["aura_applied"] += 1
                # Aura type trails the spell fields; validate rather than assume.
                for candidate in fields[BASE + 3:BASE + 5]:
                    if candidate in ("BUFF", "DEBUFF"):
                        spell["aura_type"] = candidate
                        break

            if subevent in DAMAGE_EVENTS:
                # Damage amount is the first suffix field, after the advanced
                # block when present.
                amount_at = adv_start + (ADV_LEN if advanced else 0)
                try:
                    amount = int(fields[amount_at])
                except (ValueError, IndexError):
                    continue
                spell["hits"] += 1
                spell["damage_total"] += amount
                spell["damage_max"] = max(spell["damage_max"], amount)


        close_on_death()   # a kill whose END never came, at end of file
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default="12.1",
                    help="only parse logs whose BUILD_VERSION starts with this")
    ap.add_argument("--logs", default=LOG_DIR)
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                  "dungeon_data.json"))
    args = ap.parse_args()

    files = []
    for name in sorted(os.listdir(args.logs)):
        if not name.startswith("WoWCombatLog-") or not name.endswith(".txt"):
            continue
        path = os.path.join(args.logs, name)
        with io.open(path, "r", encoding="utf-8", errors="replace") as fh:
            header = fh.readline()
        m = re.search(r"BUILD_VERSION,([0-9.]+)", header)
        build = m.group(1) if m else "?"
        if args.build and not build.startswith(args.build):
            continue
        files.append((path, build, os.path.getsize(path)))

    if not files:
        print("No logs matched build filter %r." % args.build)
        return

    dungeons = defaultdict(lambda: {"keystone_runs": 0,
                                    "mobs": defaultdict(new_mob),
                                    "spawns": defaultdict(new_spawn)})
    zone_names = {}
    stats = defaultdict(int)
    encounters = defaultdict(list)   # encounter name -> [run, run, ...]

    total_mb = sum(sz for _, _, sz in files) / 1024 / 1024
    print("Parsing %d log(s), %.0f MB total..." % (len(files), total_mb))
    for path, build, size in files:
        print("  %s (%s, %.0f MB)" % (os.path.basename(path), build, size / 1024 / 1024))
        parse_file(path, dungeons, zone_names, stats, encounters)

    # Only keep instances that actually look like dungeons: they have a zone
    # name and at least one mob. Open-world creatures land under instance 0.
    out = {}
    for inst, bucket in dungeons.items():
        if inst == 0 or not bucket["mobs"]:
            continue
        name = zone_names.get(inst)
        if not name:
            continue
        mobs = {}
        summons = stats.get("player_summons", set())
        for npc, mob in bucket["mobs"].items():
            if npc in summons:
                stats["mobs_dropped_summoned"] += 1
                continue
            if not mob["hostile"]:
                stats["mobs_dropped_friendly"] += 1
                continue
            spells = {}
            for sid, s in mob["spells"].items():
                spells[str(sid)] = {k: v for k, v in s.items() if v}
            mobs[str(npc)] = {
                "name": mob["name"],
                "level": mob["level"],
                "max_hp": mob["max_hp"],
                "deaths": mob["deaths"],
                "events": mob["events"],
                "map": mob["map"],
                "positions": mob["positions"],
                "spells": spells,
            }
        # Collapse each spawn's samples to a median point -- medians rather
        # than means because a mob dragged across the room during a pull leaves
        # a trail of outliers, and the median sits where it actually stood.
        spawns = []
        for guid, sp in bucket["spawns"].items():
            if sp["npc"] is None or str(sp["npc"]) not in mobs:
                continue     # dropped mob (summon / never hostile): no spawn either
            spawns.append({
                "guid": guid.split("-")[-1],
                "npc": sp["npc"],
                "name": sp["name"],
                "map": sp["map"],
                "level": sp["level"],
                "hp": sp["hp"],
                "seen": sp["seen"],
                "x": median(sp["xs"]),
                "y": median(sp["ys"]),
                "pack": None,
            })
        # The "is this a dungeon" test ran on the UNFILTERED bucket, so a
        # zone whose every mob was then dropped still shipped as a dungeon
        # with mobs: {} and spawns: [] (Vaults of Atal'Utek, Harandar).
        if not mobs:
            continue

        packs = cluster_packs(spawns)

        # Fold the spawn observations back onto the mob. level, map, max_hp
        # and positions were declared in new_mob() and NEVER written by any
        # code path -- 245 mobs, 0 with a level, 0 with health, 0 with a
        # position. Downstream that made the codex's "boss" test
        # (max_hp > 20M) permanently False, obsHealth never emitted at all,
        # and the dashboard's "sort by health" a sort on a constant 0. The
        # data was always there, one table over, in spawns[].
        #
        # positions stays a LIST of per-spawn points, deliberately: one mob
        # spawns in packs all over a dungeon, and a centroid of those is a
        # point it never stood on (the Primal Serpent spanning 408 yards).
        for sp in spawns:
            m = mobs.get(str(sp["npc"]))
            if not m:
                continue
            if m["level"] is None:
                m["level"] = sp["level"]
            if m["map"] is None:
                m["map"] = sp["map"]
            m["max_hp"] = max(m["max_hp"] or 0, sp["hp"] or 0)
            if sp["x"] is not None and len(m["positions"]) < MAX_POSITION_SAMPLES:
                m["positions"].append([sp["x"], sp["y"], sp["map"]])

        out[str(inst)] = {
            "name": name,
            "instance_id": inst,
            "keystone_runs": bucket["keystone_runs"],
            "mobs": mobs,
            "spawns": spawns,
            "packs": packs,
        }

    # Provenance, under a key the consumers skip. Three scripts iterate this
    # file's top level as dungeons, so a sibling would be safer -- but every
    # one of them keys on an integer-ish instance id, and "_meta" is not one.
    # Without this, nothing could tell that DungeonCodexData.lua and
    # FightData.lua were built from different corpora: this script defaults to
    # --build 12.1 (9 of the 50 logs on disk) and mine_boss_schedules defaults
    # to all of them.
    out["_meta"] = {
        "built": __import__("datetime").date.today().isoformat(),
        "build_filter": getattr(args, "build", None),
        "logs": sorted(os.path.basename(p) for p, _, _ in files),
        "builds": sorted({b for _, b, _ in files}),
        "encounters": sum(len(r) for r in encounters.values()),
    }

    with io.open(args.out, "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=1)

    # Encounter cast streams, separate file: consumers of dungeon_data.json
    # iterate its top level as dungeons, and this is a different shape.
    enc_path = os.path.join(os.path.dirname(args.out), "encounters.json")
    with io.open(enc_path, "w", encoding="utf-8") as fh:
        json.dump(encounters, fh, indent=1)

    print("\nWrote %s" % args.out)
    print("Wrote %s  (%d encounters, %d runs)" % (
        enc_path, len(encounters), sum(len(r) for r in encounters.values())))
    print("  mob-attributed events: %d" % stats["mob_events"])
    print("  advanced blocks read:  %d ok, %d unexpected failures" % (stats["advanced_ok"], stats["advanced_bad"]))
    print("  unparseable lines:     %d" % stats["unparseable"])
    print("  player pet events skipped: %d" % stats["player_pets_skipped"])
    print("  mobs dropped as player summons: %d, as never hostile: %d" % (
        stats["mobs_dropped_summoned"], stats["mobs_dropped_friendly"]))
    print("  spawn position samples:    %d" % stats["spawn_samples"])
    print("")
    # Skip the provenance key. It is added to `out` above, and THIS loop --
    # in the same file as that addition -- was the fourth consumer that
    # iterates the top level as dungeons. Three others were guarded and this
    # one was missed, so the run crashed on its own summary AFTER writing both
    # files correctly.
    for inst, d in sorted(((k, v) for k, v in out.items() if k != "_meta"),
                          key=lambda kv: -len(kv[1]["mobs"])):
        spell_count = sum(len(m["spells"]) for m in d["mobs"].values())
        with_pos = sum(1 for m in d["mobs"].values() if m["positions"])
        located = sum(1 for sp in d["spawns"] if sp["x"] is not None)
        print("  %-24s %3d mobs, %4d abilities, %4d spawns (%d located) in %d packs"
              % (d["name"], len(d["mobs"]), spell_count, len(d["spawns"]), located, d["packs"]))


if __name__ == "__main__":
    main()
