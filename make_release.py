"""Build the release zip for Salus Novus: SalusNovus-<version>.zip whose
top-level folder is SalusNovus, so it extracts straight into
Interface\\AddOns. The version comes from the TOC.

    python make_release.py            -> dist/SalusNovus-<version>.zip

Attach the zip to a GitHub Release (github.com/<repo>/releases/new) so a
friend downloads one file, extracts it into AddOns, and is done.
"""
import io, os, re, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "salusnovus")
DIST = os.path.join(HERE, "dist")


def main():
    toc = io.open(os.path.join(SRC, "SalusNovus.toc"), encoding="utf-8").read()
    m = re.search(r"(?m)^## Version:\s*(\S+)", toc)
    version = m.group(1) if m else "0.0.0"
    if not os.path.isdir(DIST):
        os.makedirs(DIST)
    out = os.path.join(DIST, "SalusNovus-%s.zip" % version)
    n = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = [d for d in dirs if d != "__pycache__"]
            for f in sorted(files):
                if f.endswith((".pyc", ".log")):
                    continue
                path = os.path.join(root, f)
                rel = os.path.relpath(path, SRC).replace(os.sep, "/")
                z.write(path, "SalusNovus/" + rel)
                n += 1
    print("wrote %s (%d files, version %s)" % (out, n, version))


if __name__ == "__main__":
    main()
