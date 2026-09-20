"""Install APIProbe into a WoW client, and read its dump back out.

Two jobs, both of which exist because doing them by hand gets them wrong:

  1. The TOC interface number is NOT guessed. It is computed from the version
     string the installer reads out of the client's own `.build.info`
     (major*10000 + minor*100 + patch), so `1.60.1` -> `16001` and `12.1.0` ->
     `120100` without anyone reasoning about it. A wrong number costs a login
     to discover; this costs nothing.

  2. Finding the SavedVariables file. The account folder is not a name on
     every flavor -- the classic beta's is `1736596#1`, complete with a `#`
     that breaks naive shell paths -- and a `.lua.bak` (the PREVIOUS save)
     sits next to every dump waiting to be parsed by accident.

    python install_probe.py --list                  # what clients are here
    python install_probe.py --install wow_classic_beta
    python install_probe.py --fetch   wow_classic_beta

Exits non-zero on any problem, so it can gate a workflow.
"""

import io
import os
import re
import shutil
import sys

WOW = r"C:\Program Files (x86)\World of Warcraft"
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "apiprobe")
ADDON = "APIProbe"
SAVED = "APIProbeDB"

# Blizzard's own product -> install-folder mapping. There is no rule to derive
# this from; it is a fixed table in the launcher.
FLAVOR = {
    "wow": "_retail_",
    "wowt": "_ptr_",
    "wow_beta": "_beta_",
    "wow_classic": "_classic_",
    "wow_classic_era": "_classic_era_",
    "wow_classic_beta": "_classic_beta_",
    "wow_classic_ptr": "_classic_ptr_",
    "wow_classic_era_ptr": "_classic_era_ptr_",
}


def build_info():
    """[(product, version, build, flavor_dir)] for every installed client."""
    path = os.path.join(WOW, ".build.info")
    if not os.path.exists(path):
        die("no .build.info at %s -- is WOW set correctly?" % WOW)
    lines = io.open(path, encoding="utf-8", errors="replace").read().splitlines()
    if not lines:
        die(".build.info is empty")
    # The header names the columns with a TYPE suffix: "Version!STRING:0".
    cols = [c.split("!")[0] for c in lines[0].split("|")]
    try:
        iv, ip = cols.index("Version"), cols.index("Product")
    except ValueError:
        die(".build.info header has no Version/Product column: %r" % (cols,))
    out = []
    for line in lines[1:]:
        if not line.strip():
            continue
        f = line.split("|")
        if len(f) <= max(iv, ip):
            continue
        ver, product = f[iv], f[ip]
        # "12.1.0.69814" -> version 12.1.0, build 69814
        parts = ver.split(".")
        version, build = ".".join(parts[:3]), (parts[3] if len(parts) > 3 else "?")
        out.append((product, version, build, FLAVOR.get(product)))
    return out


def interface_number(version):
    """1.60.1 -> 16001, 12.1.0 -> 120100. The client's own convention."""
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)$", version)
    if not m:
        die("cannot read a version out of %r" % version)
    major, minor, patch = (int(x) for x in m.groups())
    if minor > 99 or patch > 99:
        # The convention has no room for it, and silently truncating would
        # produce a plausible-looking wrong number.
        die("version %s does not fit major*10000+minor*100+patch" % version)
    return major * 10000 + minor * 100 + patch


def die(msg):
    sys.stderr.write("install_probe: %s\n" % msg)
    sys.exit(1)


def find_client(product):
    for p, version, build, flavor in build_info():
        if p == product:
            if not flavor:
                die("product %r has no known install folder" % product)
            root = os.path.join(WOW, flavor)
            if not os.path.isdir(root):
                die("%s is in .build.info but %s does not exist" % (product, root))
            return root, version, build, flavor
    die("product %r is not installed (try --list)" % product)


def cmd_list():
    print("%-22s %-10s %-8s %s" % ("product", "version", "build", "installed at"))
    for product, version, build, flavor in build_info():
        root = os.path.join(WOW, flavor) if flavor else None
        where = flavor if root and os.path.isdir(root) else "(not on disk)"
        print("%-22s %-10s %-8s %-18s -> Interface %d"
              % (product, version, build, where, interface_number(version)))


def cmd_install(product):
    root, version, build, flavor = find_client(product)
    dest = os.path.join(root, "Interface", "AddOns", ADDON)
    iface = interface_number(version)

    if not os.path.isdir(SRC):
        die("no source at %s" % SRC)

    # The TOC's file list is LOAD ORDER and is copied as written. An earlier
    # version regenerated it from a sorted directory listing, which would
    # have loaded Census.lua before Guards.lua and left every ns.* it needs
    # nil -- an addon that installs cleanly and dies on first use.
    toc_src = io.open(os.path.join(SRC, ADDON + ".toc"), encoding="utf-8").read()
    lua = [ln.strip() for ln in toc_src.splitlines()
           if ln.strip().endswith(".lua") and not ln.startswith("#")]
    if not lua:
        die("%s.toc lists no .lua files" % ADDON)
    missing = [f for f in lua if not os.path.isfile(os.path.join(SRC, f))]
    if missing:
        die("%s.toc lists files that do not exist: %s" % (ADDON, ", ".join(missing)))
    stray = sorted(f for f in os.listdir(SRC) if f.endswith(".lua") and f not in lua)
    if stray:
        print("note: not in the TOC, not installed: %s" % ", ".join(stray))

    if not os.path.isdir(dest):
        os.makedirs(dest)
    for f in lua:
        # TOC entries may live in subfolders (Mercury: Data\HallOfThanes.lua).
        target = os.path.join(dest, f.replace("\\", os.sep))
        if not os.path.isdir(os.path.dirname(target)):
            os.makedirs(os.path.dirname(target))
        shutil.copy2(os.path.join(SRC, f.replace("\\", os.sep)), target)

    # Only the Interface line is rewritten: the checked-in TOC carries one
    # flavor's number, and copying it unchanged is how the addon silently
    # fails to load on every other flavor.
    toc = re.sub(r"(?m)^## Interface:.*$", "## Interface: %d" % iface, toc_src)
    if "## Interface: %d" % iface not in toc:
        die("could not rewrite the Interface line in %s.toc" % ADDON)
    io.open(os.path.join(dest, ADDON + ".toc"), "w", encoding="utf-8",
            newline="\r\n").write(toc)

    print("installed %s into %s" % (ADDON, dest))
    print("  client %s %s build %s -> ## Interface: %d" % (product, version, build, iface))
    print("  files: %s" % ", ".join(lua + [ADDON + ".toc"]))
    print("\nIn game: log in, run /apiprobe, then /reload (SavedVariables only")
    print("flush on reload or logout). Then: python install_probe.py --fetch %s" % product)


def saved_paths(root):
    """Every account's dump for this addon. Never returns a .bak."""
    acct = os.path.join(root, "WTF", "Account")
    hits = []
    if not os.path.isdir(acct):
        return hits
    for name in sorted(os.listdir(acct)):
        # The file is named after the ADDON, not after the saved variable.
        p = os.path.join(acct, name, "SavedVariables", ADDON + ".lua")
        if os.path.isfile(p):
            hits.append((name, p))
    return hits


def cmd_fetch(product):
    root, version, build, flavor = find_client(product)
    hits = saved_paths(root)
    if not hits:
        die("no %s.lua under %s\\WTF\\Account\\*\\SavedVariables\\ -- did the\n"
            "  addon load, and did you /reload afterwards? Nothing reaches disk\n"
            "  until reload or logout." % (ADDON, root))
    out_dir = os.path.join(HERE, "apiprobe", "dumps")
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    for acct, path in hits:
        size = os.path.getsize(path)
        safe = re.sub(r"[^A-Za-z0-9_.-]", "_", acct)  # the '#' in 1736596#1
        # Named by WHAT IS IN IT, not just who saved it. One file per account
        # meant a /dungeons fetch silently replaced the 2.8 MB census dump
        # with a 3.9 KB one -- and that got committed. Now each top-level
        # block the dump carries gets its own stable file, and nothing is
        # overwritten unless the same block was fetched again.
        # The whole file, not a prefix: the dungeons block sits AFTER the
        # 2.8 MB census block when both are present.
        text = io.open(path, encoding="utf-8", errors="replace").read()
        blocks = re.findall(r'^\["(\w+)"\] = \{', text, re.M)
        blocks = [b for b in blocks if b in ("stage1", "census", "dungeons", "cleu", "triggers", "lifecycle")] or ["unknown"]
        for b in dict.fromkeys(blocks):
            out = os.path.join(out_dir, "%s_%s_%s.lua" % (product, safe, b))
            shutil.copy2(path, out)
            print("%s  account %s  %.1f KB  [%s] -> %s" % (product, acct, size / 1024.0, b, out))
        out = os.path.join(out_dir, "%s_%s.lua" % (product, safe))
        shutil.copy2(path, out)
        # Echo the whole thing when it is small; stage 1 dumps are ~1 KB and
        # reading them is the entire point of the exercise.
        if size < 8192:
            print()
            sys.stdout.write(io.open(out, encoding="utf-8", errors="replace").read())


def main():
    global ADDON, SRC
    args = sys.argv[1:]
    # --addon NAME installs/fetches a different addon from HERE/<name lower>
    # (Mercury lives in mercury/). Same derived-TOC install, same fetch.
    if "--addon" in args:
        i = args.index("--addon")
        ADDON = args[i + 1]
        SRC = os.path.join(HERE, ADDON.lower())
        del args[i:i + 2]
    if not args or "--list" in args:
        cmd_list()
        return
    if args[0] == "--install" and len(args) > 1:
        cmd_install(args[1])
    elif args[0] == "--fetch" and len(args) > 1:
        cmd_fetch(args[1])
    else:
        die("usage: --list | --install <product> | --fetch <product>")


if __name__ == "__main__":
    main()
