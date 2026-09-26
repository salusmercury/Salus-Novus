"""Harvest the leveling recorder's trail out of the Forever client.

The Recorder module (salusnovus/Recorder.lua) appends to SalusNovusDB.recorder,
which the client writes to the SavedVariables file at /reload and logout.
This script keeps a copy of every version of that file it sees, and turns
the newest one into JSON for build_route.py.

    python harvest_routes.py            # snapshot once if the file changed, then parse
    python harvest_routes.py --watch    # keep watching (poll every 5 s) until Ctrl-C
    python harvest_routes.py --dump     # also print the trail as readable lines

Snapshots: forever_routes/raw/SalusNovus-<mtime>.lua (never deleted). Until
           the client fix of 2026-09-24 the file was never read back at load,
           so old snapshots each hold one session; all of them are merged.
Parsed:    forever_routes/recorder.json (all sessions from all snapshots)  -- { sessions: [ { char, class, race,
           faction, level, started, entries: [ {t,k,m,x,y,l,q,o,n,s,xp}, ... ] } ] }
"""
import io, json, os, re, shutil, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
WTF = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\WTF\Account"
OUT = os.path.join(HERE, "forever_routes")
RAW = os.path.join(OUT, "raw")


def saved_variables_files():
    out = []
    if not os.path.isdir(WTF):
        return out
    for acct in os.listdir(WTF):
        p = os.path.join(WTF, acct, "SavedVariables", "SalusNovus.lua")
        if os.path.isfile(p):
            out.append(p)
    return out


def snapshot(path):
    """Copy `path` into RAW named by its mtime; return the copy, or None if seen."""
    os.makedirs(RAW, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S", time.localtime(os.path.getmtime(path)))
    dst = os.path.join(RAW, "SalusNovus-%s.lua" % stamp)
    if os.path.exists(dst) and os.path.getsize(dst) == os.path.getsize(path):
        return None
    shutil.copy2(path, dst)
    return dst


# ---------------------------------------------------------------- Lua reader
# The client writes a plain literal: nested {}, ["key"] = value, [n] = value,
# strings, numbers, booleans. A tiny recursive reader is enough; no Lua VM.

_TOKEN = re.compile(r'\s*(?:(\{)|(\})|(,)|(=)|(\[)|(\])|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?)|(true|false|nil)|([A-Za-z_]\w*))')


def tokens(src):
    pos = 0
    while pos < len(src):
        m = _TOKEN.match(src, pos)
        if not m or m.end() == pos:
            if src[pos:].strip() == "":
                return
            raise ValueError("bad Lua near %r" % src[pos:pos + 40])
        pos = m.end()
        yield m


def parse_saved_variables(src):
    """Return { globalName: value } for every top-level assignment."""
    it = tokens(src)
    out = {}

    def value(tok):
        if tok.group(1):                      # {
            return table()
        if tok.group(7):
            return json.loads(tok.group(7).replace("\\\n", "\\n"))
        if tok.group(8):
            n = float(tok.group(8))
            return int(n) if n == int(n) and "." not in tok.group(8) and "e" not in tok.group(8).lower() else n
        if tok.group(9):
            return {"true": True, "false": False, "nil": None}[tok.group(9)]
        raise ValueError("unexpected %r" % tok.group(0))

    def table():
        d, arr, i = {}, [], 1
        while True:
            tok = next(it)
            if tok.group(2):                  # }
                break
            if tok.group(3):                  # ,
                continue
            if tok.group(5):                  # [ key ] = value
                key = value(next(it))
                assert next(it).group(6)      # ]
                assert next(it).group(4)      # =
                d[key] = value(next(it))
            elif tok.group(10):               # name = value
                name = tok.group(10)
                assert next(it).group(4)
                d[name] = value(next(it))
            else:                             # positional
                d[i] = value(tok)
                i += 1
        # a pure 1..n table becomes a list
        if d and all(isinstance(k, int) for k in d) and sorted(d) == list(range(1, len(d) + 1)):
            return [d[k] for k in range(1, len(d) + 1)]
        return d

    for tok in it:
        if tok.group(10):
            name = tok.group(10)
            assert next(it).group(4), "expected = after %s" % name
            out[name] = value(next(it))
    return out


def parse_file(path):
    src = io.open(path, encoding="utf-8", errors="replace").read()
    db = parse_saved_variables(src).get("SalusNovusDB") or {}
    rec = db.get("recorder") or {}
    sessions = rec.get("sessions") or []
    if isinstance(sessions, dict):
        sessions = [sessions[k] for k in sorted(sessions)]
    edits = db.get("routeEdits") or {}
    if isinstance(edits, list):
        edits = {}
    for slug, ops in list(edits.items()):
        if isinstance(ops, dict):
            edits[slug] = [ops[k] for k in sorted(ops)]
    trainers = db.get("trainers") or {}
    if isinstance(trainers, list):
        trainers = {}
    return {"sessions": sessions, "edits": edits, "trainers": trainers}


KIND_TEXT = {
    "accept": "accept quest {q} from {n}", "objective": "objective {o} of quest {q} done: {n}",
    "turnin": "turn in quest {q} to {n} (+{xp} xp)", "abandon": "abandon quest {q}", "level": "level {s}",
    "zone": "enter {n}", "taxi": "fly", "hearth": "hearth", "bind": "bind hearth at {n}", "trainer": "train at {n}",
    "crumb": "...",
}


def dump(data):
    for s in data["sessions"]:
        print("== %s  %s %s %s  L%s  started %s  (%d entries)" % (
            s.get("char"), s.get("faction"), s.get("race"), s.get("class"), s.get("level"),
            time.strftime("%Y-%m-%d %H:%M", time.localtime(s.get("started") or 0)), len(s.get("entries") or [])))
        t0 = None
        for e in s.get("entries") or []:
            t0 = t0 or e.get("t") or 0
            fields = {k: e.get(k, "?") for k in ("q", "o", "n", "s", "xp")}
            where = "map %s %.1f,%.1f" % (e.get("m"), (e.get("x") or 0) * 100, (e.get("y") or 0) * 100) if e.get("x") is not None else "map %s ?,?" % e.get("m")
            print("  %6ds  L%-3s %-28s %s" % ((e.get("t") or 0) - t0, e.get("l", "?"), where, KIND_TEXT.get(e.get("k"), e.get("k")).format(**fields)))


def merge_snapshots():
    """Every session from every raw snapshot, one copy each (the longest).

    The client on this account starts SalusNovusDB from defaults at each
    load (measured 2026-09-21: a 149-entry session vanished at /reload while
    the harness keeps it), so each written file holds only the session since
    the last reload. The union of the snapshots is the trail."""
    best, edits, trainers = {}, {}, {}
    if os.path.isdir(RAW):
        for name in sorted(os.listdir(RAW)):
            if not name.endswith(".lua"):
                continue
            try:
                d = parse_file(os.path.join(RAW, name))
            except Exception as e:                # a half-written copy
                print("skipping %s: %s" % (name, e))
                continue
            for s in d["sessions"]:
                key = (s.get("char"), s.get("started"))
                if key not in best or len(s.get("entries") or []) > len(best[key].get("entries") or []):
                    best[key] = s
            # class trainer catalogues: the newest capture per class wins
            for cls, cap in (d.get("trainers") or {}).items():
                if isinstance(cap, dict) and isinstance(cap.get("entries"), (list, dict)):
                    if isinstance(cap["entries"], dict):
                        cap["entries"] = [cap["entries"][k] for k in sorted(cap["entries"])]
                    if cls not in trainers or (cap.get("captured") or 0) >= (trainers[cls].get("captured") or 0):
                        trainers[cls] = cap
            # in-game route edits: one copy per id, in the order they were made
            for slug, ops in (d.get("edits") or {}).items():
                seen = edits.setdefault(slug, {})
                for op in ops:
                    if isinstance(op, dict) and op.get("id"):
                        seen[op["id"]] = op
    sessions = [best[k] for k in sorted(best, key=lambda k: (k[1] or 0, str(k[0])))]

    def order(op):
        t, _, n = str(op.get("id", "")).partition("-")
        return (op.get("t") or 0, int(n) if n.isdigit() else 0)
    edits = {slug: [ops[k] for k in sorted(ops, key=lambda k: order(ops[k]))] for slug, ops in edits.items()}
    return {"sessions": sessions, "edits": edits, "trainers": trainers}


def harvest(do_dump=False):
    files = saved_variables_files()
    if not files:
        print("no SavedVariables/SalusNovus.lua under", WTF)
        return None
    newest = max(files, key=os.path.getmtime)
    copy = snapshot(newest)
    data = merge_snapshots()
    os.makedirs(OUT, exist_ok=True)
    with io.open(os.path.join(OUT, "recorder.json"), "w", encoding="utf-8") as fh:
        json.dump(data, fh, indent=1)
    with io.open(os.path.join(OUT, "trainers.json"), "w", encoding="utf-8") as fh:
        json.dump(data.get("trainers") or {}, fh, indent=1)
    n = sum(len(s.get("entries") or []) for s in data["sessions"])
    ne = sum(len(v) for v in (data.get("edits") or {}).values())
    nt = ", ".join("%s %d" % (c, len(v.get("entries") or [])) for c, v in sorted((data.get("trainers") or {}).items()))
    print("%s: %d session(s), %d entries, %d route edit(s), trainers: %s%s" % (
        time.strftime("%H:%M:%S"), len(data["sessions"]), n, ne, nt or "none", ("; snapshot " + os.path.basename(copy)) if copy else "; unchanged"))
    if do_dump:
        dump(data)
    return data


if __name__ == "__main__":
    args = sys.argv[1:]
    do_dump = "--dump" in args
    if "--watch" in args:
        last = None
        try:
            while True:
                files = saved_variables_files()
                m = max((os.path.getmtime(f) for f in files), default=None)
                if m != last:
                    last = m
                    harvest(do_dump)
                time.sleep(5)
        except KeyboardInterrupt:
            pass
    else:
        harvest(do_dump)
