"""Parse a WoW combat-log timestamp prefix. One copy; there were three.

The client writes `9/5/2026 20:24:11.387-5`, where the trailing part is the
UTC offset. Every script here assumed that offset is NEGATIVE:

  * boss_timings.py did `prefix.rsplit("-", 1)[0]`, which on a `+2` line finds
    no "-", hands the whole string to strptime and raises ValueError UNCAUGHT.
  * parse_logs.py did the same inside a try, so a `+2` line silently returned
    None -- and an ENCOUNTER_START whose prefix will not parse drops the whole
    encounter with nothing printed.
  * mine_boss_schedules.py's LINE_RE had `(?:-\\d+)?`, which does not match a
    `+2` line AT ALL, so every line is skipped: zero pulls, an empty mined/,
    and a FightData.lua that quietly loses its 70 log-mined schedules.

None of those is reachable from the logs on this machine (all `-5`/`-6`), and
that is exactly why it went unnoticed: it needs one user east of Greenwich, or
one half-hour zone, and the failure is silent in two of the three cases.

`+05:30` and `-0530` are accepted too -- India and Newfoundland write them.

Run directly to self-test:  python log_time.py
"""

import re
from datetime import datetime

# The offset is optional, may be + or -, and may carry minutes with or
# without a colon. The date/time half is deliberately permissive about
# 1-or-2-digit month/day/hour, which is how the client writes them.
TS_RE = re.compile(
    r"^\s*(\d{1,2})/(\d{1,2})/(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\.(\d{1,6})"
    r"(?:([+-])(\d{1,2})(?::?(\d{2}))?)?\s*$"
)

# The same shape, embedded: date, time, then the rest of the line.
LINE_RE = re.compile(
    r"^(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+)\.(\d+)"
    r"(?:[+-]\d{1,2}(?::?\d{2})?)?\s+(.*)$"
)


def strip_offset(prefix):
    """`prefix` with any trailing UTC offset removed."""
    return re.sub(r"[+-]\d{1,2}(?::?\d{2})?\s*$", "", str(prefix).strip())


def line_time(prefix):
    """Seconds since the epoch for a timestamp prefix, or None.

    The offset is stripped rather than applied: every consumer here measures
    DIFFERENCES within one log, so a consistent local clock is what matters.
    Applying it would be wrong for the DST fall-back hour, where the offset is
    the only thing that disambiguates two identical wall-clock readings -- if
    that ever matters, use `parse_with_offset` instead.
    """
    try:
        return datetime.strptime(
            strip_offset(prefix), "%m/%d/%Y %H:%M:%S.%f"
        ).timestamp()
    except (ValueError, TypeError):
        return None


def parse_with_offset(prefix):
    """(seconds, offset_minutes) or (None, None). Keeps the offset."""
    m = TS_RE.match(str(prefix))
    if not m:
        return None, None
    mo, d, y, hh, mm, ss, frac, sign, oh, om = m.groups()
    try:
        t = datetime(
            int(y), int(mo), int(d), int(hh), int(mm), int(ss),
            int(frac.ljust(6, "0")[:6]),
        ).timestamp()
    except ValueError:
        return None, None
    if sign is None:
        return t, None
    off = int(oh) * 60 + int(om or 0)
    return t, (-off if sign == "-" else off)


def _self_test():
    bad = 0

    def check(what, got, want):
        nonlocal bad
        if got != want:
            print("  FAIL %s -> %r, wanted %r" % (what, got, want))
            bad += 1

    base = "9/5/2026 20:24:11.387"
    ref = line_time(base)
    check("no offset parses", ref is not None, True)
    for suffix in ("-5", "+2", "-06", "+05:30", "-0330", "+0", ""):
        got = line_time(base + suffix)
        check("offset %r parses" % suffix, got, ref)

    check("garbage returns None", line_time("not a timestamp"), None)
    check("None returns None", line_time(None), None)

    # LINE_RE must match every offset form, and capture the same rest.
    for suffix in ("-5", "+2", "+05:30", "-0330", ""):
        m = LINE_RE.match(base + suffix + "  SPELL_CAST_START,Creature-0")
        if not m:
            print("  FAIL LINE_RE did not match offset %r" % suffix)
            bad += 1
        else:
            check("LINE_RE rest for %r" % suffix, m.group(8),
                  "SPELL_CAST_START,Creature-0")

    # The bug this file exists for: the old rsplit approach on a + offset.
    old = lambda p: p.rsplit("-", 1)[0]
    try:
        datetime.strptime(old(base + "+2"), "%m/%d/%Y %H:%M:%S.%f")
        print("  FAIL the old rsplit was expected to raise on a + offset")
        bad += 1
    except ValueError:
        pass

    # ...and the old regex, which silently matched nothing.
    old_re = re.compile(r"^(\d+)/(\d+)/(\d+) (\d+):(\d+):(\d+)\.(\d+)(?:-\d+)?\s+(.*)$")
    if old_re.match(base + "+2  X"):
        print("  FAIL the old LINE_RE was expected to reject a + offset")
        bad += 1

    t, off = parse_with_offset(base + "+05:30")
    check("offset minutes captured", off, 330)
    t, off = parse_with_offset(base + "-5")
    check("negative offset minutes", off, -300)

    print("log_time self-test: %s"
          % ("PASSED" if bad == 0 else "%d FAILURE(S)" % bad))
    return bad == 0


if __name__ == "__main__":
    import sys
    sys.exit(0 if _self_test() else 1)
