"""Turn recorded leveling trails into guide routes for Salus Novus.

    python build_route.py              # extract new step files, compile them all
    python build_route.py --force      # re-extract step files even if they exist (edits lost!)
    python build_route.py --show       # print each compiled route

Pipeline:
  forever_routes/recorder.json  (from harvest_routes.py)
    -> forever_routes/steps/<slug>.steps.txt   one editable text file per route
    -> salusnovus/Data/Routes.lua              all routes, listed once in the TOC

A route = one character's sessions in order (the client on this account
starts a fresh session at every /reload, so a character's trail is its
sessions concatenated). Slug = <Faction>_<Race>_<Class>_<char>.

Step file format (one step per line; blank lines and # comments ignored):

  # route: name=Dwarf Shaman 1-6 faction=Alliance race=Dwarf class=SHAMAN map=1426 levels=1-6
  accept 179 @1426 29.92,71.28 npc=Sten Stoutarm
  do 179/1 @1426 28.90,72.70 text=8/8 Tough Wolf Meat
  turnin 179 @1426 29.90,71.30 npc=Sten Stoutarm
  level 2
  train @1426 28.90,66.20 npc=Teo Hammerstorm
  bind @1426 47.40,52.40 npc=Thunderbrew Distillery
  fly @1426 46.70,53.90
  hearth
  note Buy water before leaving town

Coordinates are map percentages (as the map shows them). Edit freely:
reorder, delete detours, add notes; the file is re-extracted only with
--force. Rules applied at extraction: crumbs and zone changes dropped; an
abandon within 2 s of the same quest's turn-in is the client's own
removal event, dropped; a real abandon removes that quest's earlier steps.
"""
import io, json, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROUTES = os.path.join(HERE, "forever_routes")
STEPS = os.path.join(ROUTES, "steps")
OUT_LUA = os.path.join(HERE, "salusnovus", "Data", "Routes.lua")
TRAINERS_JSON = os.path.join(ROUTES, "trainers.json")
TRAINERS_LUA = os.path.join(HERE, "salusnovus", "Data", "Trainers.lua")

TURNIN_REMOVAL_WINDOW = 2       # seconds: REMOVED right before TURNED_IN is not an abandon


APPLIED = os.path.join(ROUTES, "applied_edits.json")


def load_recorder():
    with io.open(os.path.join(ROUTES, "recorder.json"), encoding="utf-8") as fh:
        return json.load(fh)


def load_sessions():
    return load_recorder()["sessions"]


# ---------------------------------------------------------------- in-game edits

def apply_ops(steps, ops):
    """Apply RouteEditor ops (del / ins / up / down, indices as of each op) in order."""
    steps = list(steps)
    for op in ops:
        kind, at = op.get("op"), op.get("at")
        if not isinstance(at, int):
            continue
        if kind == "del" and 1 <= at <= len(steps):
            del steps[at - 1]
        elif kind == "ins" and 0 <= at <= len(steps) and isinstance(op.get("step"), dict):
            s = {k: v for k, v in op["step"].items() if k in ("k", "q", "o", "l", "m", "x", "y", "n", "text")}
            if s.get("k"):
                steps.insert(at, s)
        elif kind == "up" and 2 <= at <= len(steps):
            steps[at - 1], steps[at - 2] = steps[at - 2], steps[at - 1]
        elif kind == "down" and 1 <= at < len(steps):
            steps[at - 1], steps[at] = steps[at], steps[at - 1]
        elif kind == "mv":
            to = op.get("to")
            if isinstance(to, int) and 1 <= at <= len(steps) and 1 <= to <= len(steps) and at != to:
                steps.insert(to - 1, steps.pop(at - 1))
    return steps


def apply_pending_edits(edits):
    """Apply each in-game edit ONCE to its route's step file; remember the ids.

    Ops run in order. A "new" creates the file (or replaces a dropped one), a
    "drop" retires it under steps/deleted/, and a later "new" for the same
    slug starts it again -- delete-then-recreate in one batch used to lose
    the recreation (bug hunt 8, lane 4)."""
    applied = set()
    if os.path.exists(APPLIED):
        with io.open(APPLIED, encoding="utf-8") as fh:
            applied = set(json.load(fh))
    for slug, ops in (edits or {}).items():
        pending = [op for op in ops if op.get("id") and op["id"] not in applied]
        if not pending:
            continue
        path = os.path.join(STEPS, slug + ".steps.txt")
        hdr, steps, live = None, None, os.path.exists(path)
        if live:
            h, st = parse_steps_file(path)
            hdr = {"name": h.get("name", slug), "faction": h.get("faction", ""), "race": h.get("race", ""),
                   "class": h.get("class", ""), "map": h.get("map", ""), "levels": h.get("levels", "")}
            steps = st
        touched = 0
        for op in pending:
            kind = op.get("op")
            if kind == "drop":
                if live and os.path.exists(path):
                    dead = os.path.join(STEPS, "deleted")
                    os.makedirs(dead, exist_ok=True)
                    os.replace(path, os.path.join(dead, slug + "-" + str(int(op.get("t") or 0)) + ".steps.txt"))
                    print("retired %s (deleted in game)" % os.path.relpath(path, HERE))
                hdr, steps, live = None, None, False
            elif kind == "new":
                lv = op.get("level")
                hdr = {"name": op.get("name") or slug, "faction": op.get("faction") or "", "race": op.get("race") or "",
                       "class": op.get("class") or "", "map": op.get("map") or "", "levels": ("%s-%s" % (lv, lv)) if lv else ""}
                steps, live = [], True
                touched += 1
            elif live:
                steps = apply_ops(steps, [op])
                touched += 1
            else:
                print("edit for %s (%s) with no step file; skipped" % (slug, kind))
        if live:
            write_steps_file(path, hdr, steps)
            if touched:
                print("applied %d in-game edit(s) to %s" % (touched, os.path.relpath(path, HERE)))
        applied.update(op["id"] for op in pending)
    with io.open(APPLIED, "w", encoding="utf-8") as fh:
        json.dump(sorted(applied), fh, indent=1)


def by_character(sessions):
    """{ char: [entries...] } in time order, with the header of the first session."""
    chars = {}
    for s in sorted(sessions, key=lambda s: s.get("started") or 0):
        key = s.get("char") or "?"
        rec = chars.setdefault(key, {"header": s, "entries": []})
        rec["entries"].extend(s.get("entries") or [])
    return chars


def slug_of(header):
    def clean(v):
        words = re.split(r"[^A-Za-z0-9]+", str(v or "x"))
        return "".join(w[:1].upper() + w[1:].lower() for w in words if w) or "X"
    return "%s_%s_%s_%s" % (clean(header.get("faction")), clean(header.get("race")), clean(header.get("class")),
                            clean((header.get("char") or "?").split("-")[0]))


# ---------------------------------------------------------------- extraction

def extract_steps(entries):
    """Recorder entries -> step dicts (see the module doc for the kinds)."""
    entries = [e for e in entries if e.get("k") not in ("crumb", "zone")]
    # 1. drop the client's own removal that precedes a turn-in
    drop = set()
    for i, e in enumerate(entries):
        if e.get("k") == "abandon":
            for j in range(i + 1, len(entries)):
                f = entries[j]
                if (f.get("t") or 0) - (e.get("t") or 0) > TURNIN_REMOVAL_WINDOW:
                    break
                if f.get("k") == "turnin" and f.get("q") == e.get("q"):
                    drop.add(i)
                    break
            # the same pair in the other order (a turn-in whose removal came after)
            for j in range(i - 1, -1, -1):
                f = entries[j]
                if (e.get("t") or 0) - (f.get("t") or 0) > TURNIN_REMOVAL_WINDOW:
                    break
                if f.get("k") == "turnin" and f.get("q") == e.get("q"):
                    drop.add(i)
                    break
    entries = [e for i, e in enumerate(entries) if i not in drop]
    # 2. a real abandon removes the quest's earlier steps and itself
    steps = []
    for e in entries:
        k = e.get("k")
        if k == "abandon":
            steps = [s for s in steps if s.get("q") != e.get("q")]
            continue
        pos = {"m": e.get("m"), "x": e.get("x"), "y": e.get("y")}
        if k == "accept":
            steps.append(dict(k="accept", q=e.get("q"), n=e.get("n"), **pos))
        elif k == "objective":
            text = re.sub(r"^\d+\s*/\s*\d+\s+", "", e.get("n") or "") or None   # "8/8 Meat" -> "Meat"
            steps.append(dict(k="do", q=e.get("q"), o=e.get("o"), text=text, **pos))
        elif k == "turnin":
            steps.append(dict(k="turnin", q=e.get("q"), n=e.get("n"), **pos))
        elif k == "level":
            steps.append(dict(k="level", l=e.get("s")))
        elif k == "trainer":
            steps.append(dict(k="train", n=e.get("n"), **pos))
        elif k == "bind":
            steps.append(dict(k="bind", n=e.get("n"), **pos))
        elif k == "taxi":
            steps.append(dict(k="fly", **pos))
        elif k == "hearth":
            steps.append(dict(k="hearth"))
    # 3. a quest turned in without a recorded accept (accepted before the
    #    recorder was on) keeps its steps: the alt still has to do them.
    return steps


def route_header(header, entries, steps):
    levels = [e.get("l") for e in entries if isinstance(e.get("l"), int)]
    first_map = next((s.get("m") for s in steps if s.get("m")), None)
    lo, hi = (min(levels), max(levels)) if levels else (None, None)
    for s in steps:
        if s.get("k") == "level" and isinstance(s.get("l"), int):
            hi = max(hi or 0, s["l"])
    race = header.get("race") or "?"
    cls = (header.get("class") or "?").title()
    name = "%s %s %s-%s" % (race, cls, lo, hi) if lo else "%s %s" % (race, cls)
    return {"name": name, "faction": header.get("faction"), "race": race, "class": header.get("class"),
            "map": first_map, "levels": "%s-%s" % (lo, hi) if lo else ""}


# ---------------------------------------------------------------- step files

def fmt_pos(s):
    if s.get("m") and s.get("x") is not None and s.get("y") is not None:
        return " @%d %.2f,%.2f" % (s["m"], s["x"] * 100, s["y"] * 100)
    return ""


def write_steps_file(path, hdr, steps):
    lines = ["# route: name=%s faction=%s race=%s class=%s map=%s levels=%s" % (
        hdr["name"], hdr["faction"], hdr["race"], hdr["class"], hdr["map"], hdr["levels"])]
    for s in steps:
        k = s["k"]
        if k == "accept":
            lines.append("accept %d%s npc=%s" % (s["q"], fmt_pos(s), s.get("n") or ""))
        elif k == "do":
            lines.append("do %d/%d%s text=%s" % (s["q"], s.get("o") or 1, fmt_pos(s), s.get("text") or ""))
        elif k == "turnin":
            lines.append("turnin %d%s npc=%s" % (s["q"], fmt_pos(s), s.get("n") or ""))
        elif k == "level":
            lines.append("level %s" % s.get("l"))
        elif k in ("train", "bind"):
            lines.append("%s%s npc=%s" % (k, fmt_pos(s), s.get("n") or ""))
        elif k in ("fly", "go", "hearth"):
            lines.append("%s%s%s" % (k, fmt_pos(s), (" text=" + s["text"]) if s.get("text") else ""))
        elif k == "note":
            lines.append("note %s" % s.get("text", ""))
    with io.open(path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


_POS = re.compile(r"@(\d+)\s+(-?[\d.]+),(-?[\d.]+)")


def parse_steps_file(path):
    hdr, steps = {}, []
    with io.open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            if line.startswith("# route:"):
                for m in re.finditer(r"(\w+)=(.*?)(?=\s+\w+=|$)", line[len("# route:"):].strip()):
                    hdr[m.group(1)] = m.group(2).strip()
                continue
            if line.startswith("#"):
                continue
            kind, _, rest = line.partition(" ")
            s = {"k": kind}
            pm = _POS.search(rest)
            if pm:
                s["m"], s["x"], s["y"] = int(pm.group(1)), float(pm.group(2)) / 100, float(pm.group(3)) / 100
                rest = (rest[:pm.start()] + rest[pm.end():]).strip()
            if kind == "note":
                s["text"] = rest
                steps.append(s)
                continue
            head, _, tail = rest.partition(" ")
            if kind in ("accept", "turnin"):
                s["q"] = int(head)
            elif kind == "do":
                q, _, o = head.partition("/")
                s["q"], s["o"] = int(q), int(o or 1)
            elif kind == "level":
                s["l"] = int(head)
            else:
                tail = rest
            for m in re.finditer(r"(npc|text)=(.*)$", tail.strip()):
                s["n" if m.group(1) == "npc" else "text"] = m.group(2).strip()
            steps.append(s)
    return hdr, steps


# ---------------------------------------------------------------- Lua

def lua_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def step_lua(s):
    parts = ['k = %s' % lua_str(s["k"])]
    for key in ("q", "o", "l", "m"):
        if s.get(key) is not None:
            parts.append("%s = %d" % (key, int(s[key])))
    for key in ("x", "y"):
        if s.get(key) is not None:
            parts.append("%s = %.4f" % (key, float(s[key])))
    for key in ("n", "text"):
        if s.get(key):
            parts.append("%s = %s" % (key, lua_str(s[key])))
    return "        { " + ", ".join(parts) + " },"


DB2 = os.path.join(HERE, "db2", "1.60.1.69913")
CLASS_BIT = {"WARRIOR": 1, "PALADIN": 2, "HUNTER": 4, "ROGUE": 8, "PRIEST": 16, "DEATHKNIGHT": 32,
             "SHAMAN": 64, "MAGE": 128, "WARLOCK": 256, "MONK": 512, "DRUID": 1024}
_spell_index = None


def spell_index(db2=None):
    """The wago tables the resolver needs: name -> ids, id -> rank subtext,
    id -> class mask (SkillLineAbility), id -> base level (SpellLevels).
    Missing files give an empty index (ids then stay unresolved)."""
    global _spell_index
    db2 = db2 or DB2
    if _spell_index is not None and _spell_index.get("_dir") == db2:
        return _spell_index
    import csv
    idx = {"_dir": db2, "names": {}, "sub": {}, "mask": {}, "level": {}, "desc": set(), "icon": {}, "trained": set()}
    def rows(fname):
        p = os.path.join(db2, fname)
        if not os.path.isfile(p):
            return
        with io.open(p, encoding="utf-8", newline="") as f:
            for r in csv.DictReader(f):
                yield r
    for r in rows("SpellName.csv"):
        idx["names"].setdefault(r["Name_lang"], []).append(int(r["ID"]))
    for r in rows("Spell.csv"):
        idx["sub"][int(r["ID"])] = r["NameSubtext_lang"] or ""
        if (r["Description_lang"] or "").strip():
            idx["desc"].add(int(r["ID"]))
    for r in rows("SpellMisc.csv"):
        if (r.get("DifficultyID") or "0") == "0":
            idx["icon"][int(r["SpellID"] or 0)] = int(r["SpellIconFileDataID"] or 0)
    for r in rows("SkillLineAbility.csv"):
        sid = int(r["Spell"] or 0)
        idx["mask"][sid] = idx["mask"].get(sid, 0) | int(r["ClassMask"] or 0)
        if (r.get("AcquireMethod") or "0") == "0":        # 0 = trained; 3 = comes along with another spell
            idx["trained"].add(sid)
    for r in rows("SpellLevels.csv"):
        if (r["DifficultyID"] or "0") == "0":
            idx["level"][int(r["SpellID"] or 0)] = int(r["BaseLevel"] or 0)
    _spell_index = idx
    return idx


def resolve_spell_id(name, rank, level, cls, index=None, icon=None):
    """The spell id for a trainer row: same name and rank subtext (a row
    without rank text also matches a "Passive" subtext: Parry, Safe Fall);
    the class's own spell when SkillLineAbility says so; then the base
    level, then one a trainer teaches (SkillLineAbility AcquireMethod 0:
    Penance's damage and heal halves are rank-alike sub-spells acquired
    with it), then a spell that has a description (Mutilate's per-weapon
    sub-spells share its name, rank and level but say nothing), then the
    trainer's icon. None when nothing or several remain."""
    idx = index or spell_index()
    # a row with rank text matches that subtext exactly; a rankless row
    # matches any subtext that is not a rank ("", "Passive", "Summon" on
    # Eye of Kilrogg...), the empty one first when both exist
    def sub_ok(i):
        sub = idx["sub"].get(i, "")
        if rank:
            return sub == rank
        return not RANK_SUB.match(sub)
    ids = [i for i in idx["names"].get(name, []) if sub_ok(i)]
    def narrow(keep):
        nonlocal ids
        if len(ids) > 1:
            kept = [i for i in ids if keep(i)]
            ids = kept or ids
    # trained first: Holy Shock's trained spell carries no class mask while
    # its damage and heal halves carry the paladin's, so the mask alone
    # would throw the right answer away
    narrow(lambda i: i in idx.get("trained", ()))
    bit = CLASS_BIT.get(cls or "", 0)
    narrow(lambda i: idx["mask"].get(i, 0) & bit)
    if level is not None:
        narrow(lambda i: idx["level"].get(i) == level)
    narrow(lambda i: i in idx.get("desc", ()))
    if icon:
        narrow(lambda i: idx.get("icon", {}).get(i) == icon)
    if not rank:
        narrow(lambda i: idx["sub"].get(i, "") == "")      # last: the plain subtext over "Passive"/"Summon"
    return ids[0] if len(ids) == 1 else None


RANK_REQ = re.compile(r"^(.*?)\s*\(Rank\s+(\d+)\)\s*$")
RANK_SUB = re.compile(r"^\s*Rank\s+\d+\s*$")


def derive_ranks(entries):
    """Trainer.lua's DeriveRanks, for the compiler: rows of one name without
    rank text get "Rank n" -- from a prerequisite naming the rank before
    ("Frostbolt (Rank 2)" on the rank-3 row), else by level then cost from 1.
    A single row of a name stays rankless. Idempotent."""
    by_name = {}
    for e in entries:
        if isinstance(e.get("name"), str) and not (e.get("rank") or "") and e.get("rank") not in ("available", "unavailable", "used"):
            by_name.setdefault(e["name"], []).append(e)
    for name, rows in by_name.items():
        if len(rows) < 2:
            continue
        rest = []
        for e in rows:
            got = None
            for req in e.get("req") or []:
                m = RANK_REQ.match(req)
                if m and m.group(1) == name:
                    got = int(m.group(2)) + 1
            if got:
                e["rank"] = "Rank %d" % got
            else:
                rest.append(e)
        rest.sort(key=lambda e: (e.get("level") or 0, e.get("cost") or 0))
        for i, e in enumerate(rest, 1):
            e["rank"] = "Rank %d" % i
    return entries


def compile_trainers(trainers, index=None):
    """{ class: capture } -> Data/Trainers.lua (ns.Trainers[class] = { captured, entries }).
    Rows without a spell id get one from the wago tables when it is unambiguous."""
    out = ["-- Generated by build_route.py from forever_routes/trainers.json (class trainer",
           "-- catalogues captured in game by Trainer.lua). Do not edit.",
           "local _, ns = ...", "ns.Trainers = ns.Trainers or {}", ""]
    for cls in sorted(trainers or {}):
        cap = trainers[cls]
        entries = cap.get("entries") or []
        for e in entries:                         # an early capture put the category in the rank slot
            if e.get("rank") in ("available", "unavailable", "used"):
                e["cat"], e["rank"] = e.get("cat") or e["rank"], ""
        entries = derive_ranks(entries)
        for e in entries:
            if not isinstance(e.get("spell"), (int, float)):
                sid = resolve_spell_id(e.get("name", ""), e.get("rank") or "", e.get("level"), cls, index,
                                       e.get("icon") if isinstance(e.get("icon"), (int, float)) else None)
                if sid:
                    e["spell"] = sid
        out.append("ns.Trainers[%s] = {" % lua_str(cls))
        out.append("    class = %s," % lua_str(cls))
        out.append("    captured = %d," % int(cap.get("captured") or 0))
        out.append("    entries = {")
        for e in entries:
            parts = ["name = %s" % lua_str(e.get("name", ""))]
            rank, cat = e.get("rank") or "", e.get("cat") or ""
            if rank in ("available", "unavailable", "used"):     # an early capture put the category here
                rank, cat = "", cat or rank
            if rank:
                parts.append("rank = %s" % lua_str(rank))
            if cat:
                parts.append("cat = %s" % lua_str(cat))
            for key in ("level", "cost"):
                if isinstance(e.get(key), (int, float)):
                    parts.append("%s = %d" % (key, int(e[key])))
            if e.get("skill"):
                parts.append("skill = %s" % lua_str(e["skill"]))
            if isinstance(e.get("spell"), (int, float)):
                parts.append("spell = %d" % int(e["spell"]))
            if isinstance(e.get("icon"), (int, float)):
                parts.append("icon = %d" % int(e["icon"]))
            elif e.get("icon"):
                parts.append("icon = %s" % lua_str(e["icon"]))
            if e.get("req"):
                parts.append("req = { %s }" % ", ".join(lua_str(x) for x in e["req"]))
            out.append("        { " + ", ".join(parts) + " },")
        out.append("    },")
        out.append("}")
        out.append("")
    return "\n".join(out)


def compile_routes(route_files):
    out = ["-- Generated by build_route.py from forever_routes/steps/*.steps.txt. Do not edit; edit the step files.",
           "local _, ns = ...", "ns.Routes = ns.Routes or {}", ""]
    for slug, path in sorted(route_files.items()):
        hdr, steps = parse_steps_file(path)
        levels = hdr.get("levels", "")
        lo, _, hi = levels.partition("-")
        out.append("ns.Routes[#ns.Routes + 1] = {")
        out.append("    slug = %s, name = %s," % (lua_str(slug), lua_str(hdr.get("name", slug))))
        out.append("    faction = %s, race = %s, class = %s," % (lua_str(hdr.get("faction", "")), lua_str(hdr.get("race", "")), lua_str(hdr.get("class", ""))))
        out.append("    map = %s, levels = { %s, %s }," % (hdr.get("map") or "nil", lo or "nil", hi or "nil"))
        out.append("    steps = {")
        out.extend(step_lua(s) for s in steps)
        out.append("    },")
        out.append("}")
        out.append("")
    return "\n".join(out)


def main():
    force = "--force" in sys.argv
    show = "--show" in sys.argv
    os.makedirs(STEPS, exist_ok=True)
    recorder = load_recorder()
    chars = by_character(recorder["sessions"])
    for char, rec in chars.items():
        steps = extract_steps(rec["entries"])
        if not steps:
            continue
        slug = slug_of(rec["header"])
        path = os.path.join(STEPS, slug + ".steps.txt")
        if force or not os.path.exists(path):
            write_steps_file(path, route_header(rec["header"], rec["entries"], steps), steps)
            print("wrote %s (%d steps)" % (os.path.relpath(path, HERE), len(steps)))
        else:
            print("kept  %s (edit it; --force to re-extract)" % os.path.relpath(path, HERE))
    apply_pending_edits(recorder.get("edits") or {})
    files = {f[:-len(".steps.txt")]: os.path.join(STEPS, f) for f in os.listdir(STEPS) if f.endswith(".steps.txt")}
    lua = compile_routes(files)
    os.makedirs(os.path.dirname(OUT_LUA), exist_ok=True)
    with io.open(OUT_LUA, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(lua)
    print("compiled %d route(s) -> %s" % (len(files), os.path.relpath(OUT_LUA, HERE)))
    trainers = {}
    if os.path.exists(TRAINERS_JSON):
        with io.open(TRAINERS_JSON, encoding="utf-8") as fh:
            trainers = json.load(fh)
    with io.open(TRAINERS_LUA, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(compile_trainers(trainers))
    print("compiled %d trainer catalogue(s) -> %s" % (len(trainers), os.path.relpath(TRAINERS_LUA, HERE)))
    if show:
        for slug, path in sorted(files.items()):
            hdr, steps = parse_steps_file(path)
            print("\n== %s: %s (%d steps)" % (slug, hdr.get("name"), len(steps)))
            for s in steps:
                print("  ", s)


if __name__ == "__main__":
    main()
