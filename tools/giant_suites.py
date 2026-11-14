#!/usr/bin/env python3
"""The test suites that load the player's giant (plan M10 §1.7 rule 2), found by grep, and their times.

A package's cost (§1.7 rule 2) is the sum of its own suites' times plus the change, before and after, in
the suites that load scenes/player/giant.tscn - which P43 makes the skinned model's scene. This lists
them, so each package can rerun the same list:

  python3 tools/giant_suites.py                       the suites, one per line: tier, name, why
  python3 tools/giant_suites.py LOG [LOG ...]         with each suite's milliseconds in each test log
                                                      (the runner's "name  N checks  F failures  (MS ms)"
                                                      lines: .userdata/check/tests.log, a --slow run's
                                                      log, a base's logs), and the sum per tier and log

A suite (a .gd file under tests/unit, tests/integration, tests/slow or tests/gate) loads the giant when
its text has any of:
  spawn_player(                      IntegrationSuite.spawn_player instances giant.tscn
  player/giant.tscn                  instanced directly
  make_root(true                     TinyWorld's WorldRoot with the giant
  LivingWorldFixtures.make(          the same, through the living world's fixtures
  a scene's res:// path              a scene under scenes/ that instances giant.tscn (the levels, the test
                                     levels, the sandbox)
  start_new_valley(, continue_valley(, start_world_for_tests(, travel_to(, change_mode("valley" or
  change_mode("world"                GameSession's paths that load a level with the player in it
Level ids are not matched (most suites name "level.valley" or "level.world" as data without loading the
level). The grep can count a suite that only names such a scene without loading it; it misses a suite
that reaches the giant some other way (a level loaded by an id alone, a path assembled at run time). Only the standard library is used.
"""
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
TIERS = [("default", "tests/unit"), ("default", "tests/integration"), ("slow", "tests/slow"), ("gate", "tests/gate")]
GIANT = "res://scenes/player/giant.tscn"
FIXED = [("spawn_player(", "spawn_player"), ("player/giant.tscn", "giant.tscn"), ("make_root(true", "tiny world"),
         ("LivingWorldFixtures.make(", "living world"), ("start_new_valley(", "session"), ("continue_valley(", "session"),
         ("start_world_for_tests(", "session"), ("travel_to(", "session"), ('change_mode("valley"', "session"),
         ('change_mode("world"', "session")]
LINE = re.compile(r"^\s+(test_\w+)\s+\d+ checks\s+\d+ failures\s+\((\d+) ms\)")


def _walk(top, ext):
    for d, _dirs, files in os.walk(os.path.join(ROOT, top)):
        if os.path.basename(d).startswith("."):
            continue
        for f in sorted(files):
            if f.endswith(ext):
                yield os.path.join(d, f)


def giant_scenes():
    """res:// paths of the scenes under scenes/ that instance giant.tscn."""
    out = []
    for p in _walk("scenes", ".tscn"):
        if p.endswith("giant.tscn") and "/player/" in p:
            continue
        with open(p, encoding="utf-8", errors="replace") as fh:
            if GIANT in fh.read():
                out.append("res://" + os.path.relpath(p, ROOT).replace(os.sep, "/"))
    return out


def suites():
    """[(tier, name, reason)] of the suites that load the giant, by tier and name."""
    marks = FIXED + [(s, "scene " + os.path.basename(s)) for s in giant_scenes()]
    out = []
    for tier, top in TIERS:
        for p in _walk(top, ".gd"):
            name = os.path.basename(p)[:-3]
            if not name.startswith("test_"):
                continue
            with open(p, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            why = [r for m, r in marks if m in text]
            if why:
                out.append((tier, name, ", ".join(sorted(set(why)))))
    return out


def times(log):
    """{suite name: ms} from a test log."""
    out = {}
    with open(log, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = LINE.match(line)
            if m:
                out[m.group(1)] = int(m.group(2))
    return out


def main(argv):
    if any(a in ("-h", "--help") for a in argv):
        print(__doc__)
        return 0
    found = suites()
    logs = [(a, times(a)) for a in argv]
    sums = {}
    for tier, name, why in found:
        cols = []
        for i, (_path, t) in enumerate(logs):
            ms = t.get(name)
            cols.append("%7s" % ("-" if ms is None else ms))
            if ms is not None:
                sums[(tier, i)] = sums.get((tier, i), 0) + ms
        print("%-8s %-44s %s  %s" % (tier, name, " ".join(cols), why))
    counts = {}
    for tier, _n, _w in found:
        counts[tier] = counts.get(tier, 0) + 1
    print("GIANT_SUITES " + " ".join("%s=%d" % (t, counts.get(t, 0)) for t in ("default", "slow", "gate")))
    for i, (path, _t) in enumerate(logs):
        print("GIANT_SUITES_MS log=%s %s" % (os.path.basename(path), " ".join(
            "%s=%d" % (t, sums.get((t, i), 0)) for t in ("default", "slow", "gate"))))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
