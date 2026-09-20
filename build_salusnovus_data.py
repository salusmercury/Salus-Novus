"""Generate Salus Novus's per-instance data files from what is already on disk.

    python build_salusnovus_data.py            # every included instance
    python build_salusnovus_data.py 3065       # one instance

Inputs (all produced earlier in this repo, none hand-written):
  forever_instances.json         instance -> ordered bosses     (forever_bosses.py)
  forever_logs/encounters.json   per-pull boss cast lists      (parse_logs.py)
  forever_logs/dungeon_data.json mobs seen per instance         (parse_logs.py)
  forever_creatures.json         NPC id -> display ids          (parse_creaturecache.py)

Output: salusnovus/Data/<Instance>.lua, one table per instance, for every
instance in INCLUDED below -- with or without logged pulls, so a boss is in
the addon the moment its first pull is logged. Every timing is an
observation with its pull count attached; nothing is a "schedule" until
several pulls agree, and that judgement is the addon's to make at display
time, not this file's to bake in.

Spell names are carried only as a fallback label: Salus Novus asks the client
for names, icons and descriptions at display time so hotfixes show through.
"""

import io
import json
import os
import re
import sys
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "salusnovus", "Data")

# Which maps ship. Measured split (wow_forever_notes.md): a map present in
# Classic Era 1.15.9 is SoD content, one absent is new to Forever. SoD-only
# instances are not available on Forever and stay out; moving one in is a
# one-line change here.
INCLUDED = {
    # dungeons
    389, 3065, 2999, 36, 43, 33, 48, 34, 47, 90, 2998, 2959, 189, 129, 70,
    209, 349, 109, 230, 229, 329, 289, 429,
    # raids
    249, 409, 469, 309, 509, 531, 533,
}

# Level ranges from Blizzard's Forever dungeon chart (Alex, 2026-09-19;
# Krol'dok Stronghold corrected to 40-45). Keyed by the data key: a map id,
# or a wing key for a split instance. Shown after the name in the sidebar.
LEVELS = {
    389: (13, 19), 3065: (13, 18), 2999: (15, 20), 36: (18, 24), 43: (19, 25),
    33: (23, 29), 2998: (24, 29), 48: (25, 31), 34: (26, 32), 2959: (28, 33),
    47: (30, 36), 90: (31, 37), 189: (31, 45), 129: (38, 44), 70: (44, 50),
    209: (45, 51), 349: (48, 54), 109: (52, 58), 230: (52, 60), 229: (57, 60),
    289: (58, 60), 329: (59, 60),
    42901: (55, 60), 42902: (58, 60), 42903: (59, 60),
    900001: (35, 40), 900002: (40, 45), 900003: (48, 53), 900004: (55, 60), 900005: (58, 60),
}

# An instance the client keeps as one map but Forever runs as wings: one
# data entry per wing (key = map id * 100 + wing), bosses by name.
SPLIT = {
    429: [
        (42901, "Dire Maul: East", {"Pusillin", "Zevrim Thornhoof", "Hydrospawn", "Lethtendris", "Alzzin the Wildshaper"}),
        (42902, "Dire Maul: West", {"Tendris Warpwood", "Illyanna Ravenoak", "Magister Kalendris", "Immol'thar",
                                    "Prince Tortheldrin", "Lord Hel'nurath", "Tsu'zee"}),
        (42903, "Dire Maul: North", {"Guard Mol'dar", "Stomper Kreeg", "Guard Fengus", "Guard Slip'kik",
                                     "Captain Kromcrush", "Cho'Rush the Observer", "King Gordok"}),
    ],
}

# Dungeons on the chart that the client tables do not carry yet: listed
# with their level range and no bosses, so the roster reads complete.
COMING = [
    (900001, "The Drowned City"), (900002, "Krol'dok Stronghold"), (900003, "Alcaz Prison"),
    (900004, "Blackmaw Hold"), (900005, "The Shapers' Terrace"),
]
INCLUDED.update(k for k, _ in COMING)


def expand(instances):
    """Client instance refs -> data entries: split wings, add the coming
    dungeons, and carry the chart's level range on every entry."""
    out = []
    for ref in instances:
        map_id = int(ref["mapID"])
        if map_id in SPLIT:
            for key, name, names in SPLIT[map_id]:
                sub = dict(ref)
                sub["key"], sub["name"] = key, name
                sub["bosses"] = [b for b in ref["bosses"] if b["name"] in names]
                out.append(sub)
        else:
            sub = dict(ref)
            sub["key"] = map_id
            out.append(sub)
    for key, name in COMING:
        out.append({"mapID": key, "key": key, "name": name, "type": "dungeon", "bosses": [], "coming": True})
    for e in out:
        lv = LEVELS.get(e["key"])
        if lv:
            e["level"] = [lv[0], lv[1]]
    return out


EXCLUDED_WHY = {
    3002: "not in the game yet (Half-Pint Tavern -- Alex)",
    2875: "SoD-only (Karazhan Crypts)", 2784: "SoD-only (Demon Fall Canyon)",
    2720: "SoD-only (The Searing Basin)", 2921: "SoD-only (second Naxxramas map)",
    2832: "SoD-only (Nightmare Grove)", 2856: "SoD-only (Scarlet Enclave)",
    2791: "SoD-only (Storm Cliffs)", 2789: "SoD-only (The Tainted Scar)",
    2804: "SoD-only (The Crystal Vale)",
    2806: "SoD event map, no bosses", 2817: "SoD event map, no bosses",
    2807: "SoD event map, no bosses", 2853: "SoD event map, no bosses",
    2902: "SoD event map, no bosses",
    13: "test map", 29: "test map", 44: "unused map",
    269: "no bosses (Caverns of Time)", 169: "no bosses (Emerald Dream)",
    3109: "new to Forever but 0 encounter rows in this build (Manor Mistmantle)",
}


def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"').replace("\r", " ").replace("\n", " ") + '"'


def load_json(rel):
    return json.load(io.open(os.path.join(HERE, rel), encoding="utf-8"))


def file_name(inst_name):
    # "The Hall of Thanes" -> HallOfThanes.lua, matching the TOC entry.
    words = re.sub(r"[^A-Za-z0-9 ]", "", re.sub(r"^The\s+", "", inst_name)).split()
    return "".join(w[:1].upper() + w[1:] for w in words) + ".lua"


CLUSTER_WINDOW = 6.0     # seconds: casts this close across pulls are "the same cast"
PAIR_WINDOW = 4.0        # a cast bar and its landing within this are one event


def lane_events(casts):
    """Per pull, merge a cast bar ("start") with its landing ("success")
    within PAIR_WINDOW into one event at the bar's start -- the same rule as
    salusnovus/Schedule.lua EventsFor. Returns (events, bar_lengths):
    events = [(t, pull)], bar_lengths = [success - start] for merged pairs."""
    by_pull = defaultdict(list)
    for t, kind, pi in casts:
        by_pull[pi].append((t, kind))
    events, lengths = [], []
    for pi, rows in by_pull.items():
        rows.sort()
        last_start = None
        for t, kind in rows:
            if kind == "success" and last_start is not None and t - last_start <= PAIR_WINDOW:
                lengths.append(t - last_start)
                last_start = None
            else:
                events.append((t, pi))
                last_start = t if kind == "start" else None
    return events, lengths


def lanes(casts):
    """Cluster one ability's casts across pulls: greedy in time order, a
    cast joins the open cluster if it is within CLUSTER_WINDOW of the
    cluster's first cast and its pull is not already in it. Per cluster:
    median time, pulls backing it, and the max deviation. One pull gives
    support 1 / spread 0, which the visualizer must call UNCONFIRMED, not
    consistent (MerkUI's rule)."""
    events, lengths = lane_events(casts)
    events.sort()
    clusters = []
    for t, pi in events:
        c = clusters[-1] if clusters else None
        if c and t - c["first"] <= CLUSTER_WINDOW and pi not in c["pulls"]:
            c["ts"].append(t)
            c["pulls"].add(pi)
        else:
            clusters.append({"first": t, "ts": [t], "pulls": {pi}})
    out_casts, out_spread, out_support = [], [], []
    for c in clusters:
        ts = sorted(c["ts"])
        n = len(ts)
        med = ts[n // 2] if n % 2 else (ts[n // 2 - 1] + ts[n // 2]) / 2.0
        out_casts.append(round(med, 1))
        out_spread.append(round(max(abs(t - med) for t in ts), 1))
        out_support.append(len(c["pulls"]))
    cast = 0.0
    if lengths:
        ls = sorted(lengths)
        cast = round(ls[len(ls) // 2], 1)
    return out_casts, out_spread, out_support, cast


# The client tables spell one boss two ways across its variant rows; the
# wowhead spelling wins.
NAME_ALIASES = {"Geilhast": "Gelihast"}


def collapse_bosses(bosses):
    """Several DungeonEncounter rows share one boss name (SoD/era variants
    of Blackfathom, Gnomeregan, Sunken Temple). One boss per name, in the
    order of its first row, carrying every encounter id."""
    out, by_name = [], {}
    for b in sorted(bosses, key=lambda x: (x.get("order", 0), x["encounterID"])):
        b = dict(b, name=NAME_ALIASES.get(b["name"], b["name"]))
        key = b["name"]
        if key in by_name:
            by_name[key]["encounterIDs"].append(b["encounterID"])
            continue
        rec = dict(b)
        rec["encounterIDs"] = [b["encounterID"]]
        by_name[key] = rec
        out.append(rec)
    return out


def main():
    only = int(sys.argv[1]) if len(sys.argv) > 1 else None
    enc_json = load_json("forever_logs/encounters.json")
    pulls = enc_json if isinstance(enc_json, list) else [x for v in enc_json.values()
                                                          for x in (v if isinstance(v, list) else [v])]
    dungeon = load_json("forever_logs/dungeon_data.json")
    instances = load_json("forever_instances.json")["instances"]
    # Keyed by NPC id: three cache rows share the name "Stalker", and
    # first-of-name would hand every one of them the same model.
    creatures = {}
    for c in load_json("forever_creatures.json")["creatures"]:
        creatures.setdefault(int(c.get("id") or c.get("npcID") or 0), c)

    by_enc = defaultdict(list)
    for p in pulls:
        by_enc[int(p["encounter_id"])].append(p)

    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    written, toc = 0, []
    for ref in sorted(expand(instances), key=lambda r: (r["type"] != "dungeon", r.get("level") or [999], r["name"])):
        map_id = int(ref["mapID"])
        key = ref["key"]
        if ref["type"] not in ("dungeon", "raid"):
            continue
        if map_id not in INCLUDED:
            if only is None and map_id not in EXCLUDED_WHY:
                print("  map %d %s: not in INCLUDED and no reason recorded" % (map_id, ref["name"]))
            continue
        if only and map_id != only:
            continue
        inst = dungeon.get(str(map_id), {})
        mobs = inst.get("mobs", {})
        name_to_npc = {m["name"]: int(npc) for npc, m in mobs.items()}
        bosses = collapse_bosses(ref["bosses"])
        level = ref["level"][0] if ref.get("level") else None
        level_max = ref["level"][1] if ref.get("level") and len(ref["level"]) > 1 else None

        L = []
        w = L.append
        logs = sorted({p["file"] for b in bosses for e in b["encounterIDs"] for p in by_enc.get(e, [])})
        w("-- GENERATED by build_salusnovus_data.py -- do not edit by hand.")
        w("-- Source: client tables (forever_instances.json)%s. Every timing is an observation with its pull count."
          % ((" + logs " + ", ".join(logs)) if logs else "; no pulls logged yet"))
        w("local _, ns = ...")
        w("ns.Data = ns.Data or {}")
        w("ns.Data[%d] = {" % key)
        w("    name = %s," % lua_str(ref["name"]))
        w("    mapID = %d," % map_id)
        w("    type = %s," % lua_str(ref["type"]))
        w("    level = %s," % (level if level else "nil"))
        if level and level_max:
            w("    levelMax = %d, levelRange = %s," % (level_max, lua_str("%d-%d" % (level, level_max))))
        if ref.get("coming"):
            w("    coming = true,   -- on Blizzard's chart, not in the client tables yet")
        total_pulls = sum(len(by_enc.get(e, [])) for b in bosses for e in b["encounterIDs"])
        w("    pulls = %d," % total_pulls)
        w("    bosses = {")
        for b in bosses:
            ps = [p for e in b["encounterIDs"] for p in by_enc.get(e, [])]
            # NPCs in this fight: the encounter's own name if it is an NPC, plus
            # every hostile source that cast during a pull. With no pulls, the
            # client tables' NPC id and wowhead's display id.
            sources = []
            for p in ps:
                for t, sid, sname, src, kind in p["casts"]:
                    if src in name_to_npc and src not in sources:
                        sources.append(src)
            if b["name"] in name_to_npc:
                if b["name"] in sources:
                    sources.remove(b["name"])
                sources.insert(0, b["name"])
            else:
                # No NPC shares the encounter's name (Infurnus): the boss is the
                # caster with the biggest health pool (Magmatus, not the
                # Summoner that cast first -- Alex).
                sources.sort(key=lambda s: -mobs[str(name_to_npc[s])].get("max_hp", 0))
            def display_id(npc_id, nm):
                c = creatures.get(npc_id)
                did = c["models"][0]["displayID"] if c and c["models"] else None
                # The client table's own display id covers a boss the
                # creature cache never saw (the cache misses ~10/145).
                if not did and nm == b["name"]:
                    did = (b.get("displayIDs") or [None])[0]
                return did
            npcs = []
            for s in sources:
                npcs.append((name_to_npc[s], s, display_id(name_to_npc[s], s)))
            if not npcs and b.get("npcID"):
                npcs.append((b["npcID"], b["name"], display_id(b["npcID"], b["name"])))

            abil = {}
            for pi, p in enumerate(ps):
                for t, sid, sname, src, kind in p["casts"]:
                    if src not in name_to_npc:
                        continue          # players and pets
                    # One record per (spell, caster): an add's Sunder Armor is
                    # not the boss's, and the Lua filters on source.
                    a = abil.setdefault((sid, src), {"name": sname, "source": src, "casts": [], "pulls": set()})
                    a["casts"].append((round(t, 1), kind, pi))
                    a["pulls"].add(pi)

            # The boss is called what its NPC is called. An encounter whose
            # name is not an NPC (Infurnus) shows as the NPC that was picked
            # as the boss (Magmatus); the encounter's own name is kept for
            # lookups. (Alex: "relabel Infurnus to Magmatus".)
            shown = npcs[0][1] if (npcs and b["name"] not in name_to_npc and npcs[0][1] != b["name"]) else b["name"]
            w("        {")
            w("            encounterID = %d, encounterIDs = { %s }," % (
                b["encounterIDs"][0], ", ".join(str(e) for e in b["encounterIDs"])))
            w("            name = %s," % lua_str(shown))
            if shown != b["name"]:
                w("            encounterName = %s," % lua_str(b["name"]))
            w("            order = %d," % b.get("order", 0))
            w("            pulls = %d, kills = %d," % (len(ps), sum(1 for p in ps if p["success"])))
            if ps:
                w("            avgLength = %.1f," % (sum(p["length"] for p in ps) / len(ps)))
            w("            npcs = {")
            for npc_id, nm, did in npcs:
                w("                { id = %d, name = %s, displayID = %s }," % (npc_id, lua_str(nm), did if did else "nil"))
            w("            },")
            w("            abilities = {")
            for (sid, _src), a in sorted(abil.items(), key=lambda kv: min(c[0] for c in kv[1]["casts"])):
                w("                { spellID = %d, name = %s, source = %s, pulls = %d," % (
                    sid, lua_str(a["name"]), lua_str(a["source"]), len(a["pulls"])))
                w("                  casts = { %s }," % ", ".join(
                    "{ %.1f, %s, %d }" % (t, lua_str(kind), pi + 1) for t, kind, pi in a["casts"]))
                lc, lsp, lsu, lcast = lanes(a["casts"])
                w("                  lanes = { casts = { %s }, spread = { %s }, support = { %s }, cast = %.1f } }," % (
                    ", ".join("%.1f" % t for t in lc), ", ".join("%.1f" % s for s in lsp),
                    ", ".join(str(s) for s in lsu), lcast))
            w("            },")
            w("        },")
        w("    },")
        w("}")
        fname = file_name(ref["name"])
        path = os.path.join(OUT_DIR, fname)
        io.open(path, "w", encoding="utf-8", newline="\n").write("\n".join(L) + "\n")
        n_ab = sum(1 for _ in re.finditer(r"spellID =", "\n".join(L)))
        print("  wrote %-28s %-8s %d bosses, %d abilities, %d pulls" % (fname, ref["type"], len(bosses), n_ab, total_pulls))
        toc.append("Data\\" + fname)
        written += 1
    print("%d data file(s)" % written)
    if only is None:
        print("\nTOC block:")
        for line in toc:
            print(line)


if __name__ == "__main__":
    main()
