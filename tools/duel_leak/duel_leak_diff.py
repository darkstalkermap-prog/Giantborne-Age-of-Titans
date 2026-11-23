#!/usr/bin/env python3
"""B5 (G11): the first tick and the fields at which two dumps of tools/duel_leak/test_duel_leak.gd part.

    python3 tools/duel_leak/duel_leak_diff.py <a.jsonl> <b.jsonl> [ignored,key,parts]

Each dump line is {"t": the duel's tick, "m": {field: value}}. Sim's tick is global, so two runs of one duel in
different processes (or after other fights) see absolute ticks that differ by a constant: the offset is read from the
giant's controller clock at the duel's first tick and taken out of every number of four or more digits that is at
least that large. A field is ignored when any of the given comma-separated parts occurs in its name (the default:
the attack instance counters, the camera rig - presentation - and the stored ticks of logs hashed by length, which
differ by the offset alone; the aim deferral's held swings, whose stale ones of an earlier fight are dropped only when
it next holds back more than 16 and never touch a later one). Prints "no difference in the common ticks" or the first differing tick and its fields.
Tools only.
"""
import json
import re
import sys

DEFAULT_IGNORED = ["instance", "camera_rig", "_ability_log", "_shock", "combat._seen", "G.proj", "_bursts",
                   "hazard_log", "G.hitfactory"]


def load(path):
    out = []
    with open(path) as f:
        for line in f:
            try:
                out.append(json.loads(line))
            except ValueError:
                break   # (a run still writing, or cut off)
    return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    a, b = load(argv[1]), load(argv[2])
    ignored = [i for i in argv[3].split(",") if i] if len(argv) > 3 else DEFAULT_IGNORED
    if not a or not b:
        print("an empty dump")
        return 2
    off = int(b[0]["m"]["P.entity.controller.now"]) - int(a[0]["m"]["P.entity.controller.now"])
    print("ticks %d and %d, Sim's tick offset %d" % (len(a), len(b), off))

    def norm(text):
        return re.sub(r"(?<![\d.])(\d{4,})(?![\d.])",
                      lambda m: str(int(m.group(1)) - off) if off - 300 <= int(m.group(1)) < 10 ** 7 else m.group(1), text)

    def same(x, y):
        if x == y:
            return True
        if isinstance(x, str) and isinstance(y, str) and norm(y) == x:
            return True
        try:
            return int(y) - int(x) == off
        except (TypeError, ValueError):
            return False

    for x, y in zip(a, b):
        ma, mb = x["m"], y["m"]
        diff = [k for k in sorted(set(ma) | set(mb))
                if not same(ma.get(k), mb.get(k)) and not any(i in k for i in ignored)]
        if diff:
            print("first difference at the duel's tick %d: %d fields" % (x["t"], len(diff)))
            for k in diff[:80]:
                print("  %s | %s | %s" % (k, str(ma.get(k))[:200], str(mb.get(k))[:200]))
            return 1
    print("no difference in the common ticks")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
