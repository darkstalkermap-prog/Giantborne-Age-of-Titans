#!/usr/bin/env python3
"""Markdown tables of a bot batch: the Valley bot's (P17b; plan §5.6, §5.7; docs/HOW_IT_PLAYS.md,
docs/BALANCE_LOG.md) and the world bot's (P38; plan M6-M9 §6.1, §5.15).

    python3 tools/bot_report.py <batch dir> [section ...]

<batch dir> is a tools/run_bots.sh folder, user://bot_runs/<tag>/ (in this worktree:
.userdata/godot/app_userdata/<project>/bot_runs/<tag>/). Sections (all of the batch's kind when none is
named): the Valley's summary runs segments deaths growth abilities perf stuck states targets; the world's
(runs whose result has "world_bot") world_summary world_runs world_segments world_outcomes world_bosses
world_travel world_streaming world_formations world_siege world_music world_deaths world_stuck.
Every Valley number is read from the runs' AUTOPILOT_RESULT files (<run>.json) except two estimates,
both marked where they are printed:
- a segment's damage as a share of maximum health uses the giant's maximum health at the segment's
  end, rebuilt from the run's XP timeline and growth ticks the way the bot spends its points
  (Strength and Endurance alternating: 500 + 15 per Endurance point + 150 at stage 2, 300 at 3);
- the human estimate is the bot's own (plan §5.1): simulated seconds + 4 s per dialogue node +
  text at 15 characters per second + 8 s per screen + 10 s per district entered first.
Tools only: never exported, not part of the game.
"""
import collections
import glob
import json
import os
import statistics
import sys

SEGS = ["1_hollow", "2_forest", "3_grove", "4_village", "5_ruins", "6_boss", "7_return"]
SEG_NAMES = {"1_hollow": "Hollow", "2_forest": "Forest", "3_grove": "Grove", "4_village": "Village",
             "5_ruins": "Ruins", "6_boss": "Boss", "7_return": "Return"}
# Plan §4.9: target minutes (low, high) per segment.
SEG_TARGET = {"1_hollow": (3.0, 2, 4), "2_forest": (5.5, 4, 7), "3_grove": (2.0, 1.5, 2.5), "4_village": (4.0, 1.5, 7),
              "5_ruins": (4.0, 3, 5), "6_boss": (4.0, 2.5, 6), "7_return": (3.5, 2.5, 4.5)}
ABILITIES = ["ability.heavy_footfall", "ability.sweeping_blow", "ability.stone_skin", "ability.crushing_grip",
             "ability.boulder_hurl", "ability.runic_bolt", "ability.ancestral_mend", "ability.thunder_roar",
             "ability.titan_surge"]
XP_TO_NEXT = [100 + 50 * i for i in range(19)]   # spec §9: 100 + 50 (L - 1)
STAGE_HEALTH = {1: 0, 2: 150, 3: 300}           # data/growth/growth_0N.json resource_bonus.health


def level_of(xp):
    level, need = 1, 0
    for step in XP_TO_NEXT:
        need += step
        if xp < need:
            break
        level += 1
    return level


def max_health(level, stage):
    endurance_points = (3 * (level - 1)) // 2   # 3 points a level, Strength first, then alternating
    return 500 + 15 * endurance_points + STAGE_HEALTH.get(stage, 0)


def run_row(path):
    """One run's numbers from its AUTOPILOT_RESULT."""
    name = os.path.basename(path)[:-5]
    exit_path = path[:-5] + ".exit"
    code, wall = (open(exit_path).read().split() + ["?", "?"])[:2] if os.path.exists(exit_path) else ("?", "?")
    try:
        r = json.load(open(path))
    except (OSError, ValueError):
        return {"name": name, "exit": code, "wall": wall, "error": "no result"}
    vb = r.get("valley_bot", {})
    segs = {s["id"]: s for s in vb.get("segments", [])}
    deaths = vb.get("deaths", [])
    dseg = collections.Counter(d.get("segment") for d in deaths)
    dcause = collections.Counter("%s/%s" % (d.get("killer_archetype"), d.get("action_id", "").replace("ability.", ""))
                                 for d in deaths)
    stage_end = {o["id"][11:]: o.get("end_tick", 0) for o in vb.get("objectives", []) if o["id"].startswith("quest.main:")}
    timeline = vb.get("xp_timeline", [])    # [tick, level, total xp]
    growth = vb.get("growth_ticks", [])     # [tick, stage]
    seg_damage_frac = {}
    for sid, s in segs.items():
        end = max([stage_end.get(st, 0) for st in s.get("stages", [])] + [0])
        xp = 0
        for e in timeline:
            if e[0] <= end:
                xp = e[2] if len(e) >= 3 else e[1]
        stage = 1
        for g in growth:
            if g[0] <= end:
                stage = g[1]
        seg_damage_frac[sid] = round(s.get("damage_taken", 0) / max_health(level_of(xp), stage), 2)
    boss_deaths = dseg.get("6_boss", 0)
    boss_attempts = max(1, boss_deaths + (1 if vb.get("completed") else 0))
    ab = vb.get("abilities", {})
    used = {a: int(ab.get("uses", {}).get(a, 0)) for a in ABILITIES}
    share = ab.get("damage_share", {})
    ai = vb.get("ai_states", {})

    def soldier_share(stage, keys):
        s = ai.get(str(stage), {}).get("soldier", {})
        engaged = s.get("engaged", 0)
        return round(sum(s.get(k, 0) for k in keys) / engaged, 2) if engaged > 0 else None

    ttk = vb.get("ttk", {}).get("soldier", {})
    t1 = ttk.get("1", {}).get("mean_s")
    t2 = ttk.get("2", {}).get("mean_s")
    rd = vb.get("readability", {})
    cpu = r.get("perf", {}).get("cpu_tick_ms", {})
    return {
        "name": name, "exit": code, "wall": wall, "policy": vb.get("bot", {}).get("policy"),
        "skill": vb.get("bot", {}).get("skill"), "seed": vb.get("bot", {}).get("seed"),
        "completed": bool(vb.get("completed")), "finish": vb.get("finish_reason"),
        "sim_s": vb.get("simulated_s", 0), "human_s": vb.get("human_estimate_s", 0),
        "deaths": len(deaths), "boss_deaths": boss_deaths,
        "max_other_seg_deaths": max([v for k, v in dseg.items() if k != "6_boss"] + [0]),
        "dseg": dict(dseg), "dcause": dict(dcause),
        "seg_raw": {k: v.get("raw_s", 0) for k, v in segs.items()},
        "seg_human": {k: v.get("human_estimate_s", 0) for k, v in segs.items()},
        "seg_damage_frac": seg_damage_frac,
        "boss_dmg_per_attempt": round(seg_damage_frac["6_boss"] / boss_attempts, 2) if "6_boss" in seg_damage_frac
        and segs["6_boss"].get("raw_s", 0) > 0 else None,
        "abilities_used": used, "max_share": max(share.items(), key=lambda kv: kv[1]) if share else None,
        "hold1": soldier_share(1, ["Hold"]), "hold2": soldier_share(2, ["Hold"]),
        "flee3": soldier_share(3, ["Flee", "Routed"]),
        "ttk1": t1, "ttk2": t2, "ttk_ratio": round(t2 / t1, 2) if t1 and t2 else None,
        "off_cam": rd.get("off_camera_share"), "late_tel": rd.get("late_telegraph_share"),
        "last_obj": (vb.get("objectives") or [{}])[-1].get("id", ""),
        "breaches": [(b.get("classification"), b.get("objective"), b.get("reason")) for b in vb.get("breaches", [])],
        "cpu_p95": cpu.get("p95"), "max_active": vb.get("max_active_enemies"),
        "max_hostiles_near": vb.get("max_hostiles_near"), "errors": r.get("errors"),
        "teleports": vb.get("teleports"), "invariant_failures": len(vb.get("invariant_failures", [])),
        "level": vb.get("level"), "growth_ticks": growth, "stuck": len(vb.get("stuck_events", [])),
        "stuck_events": vb.get("stuck_events", []),
        "ai_states": ai, "ttk_all": vb.get("ttk", {}),
    }


def load(batch_dir):
    rows = [run_row(p) for p in sorted(glob.glob(os.path.join(batch_dir, "*.json")))]
    return [r for r in rows if "error" not in r]


def med(values):
    values = [v for v in values if v is not None]
    return statistics.median(values) if values else None


def fmt(x, digits=1):
    if x is None:
        return "-"
    if isinstance(x, float):
        return ("%." + str(digits) + "f") % x
    return str(x)


def summary_table(rows):
    by = collections.defaultdict(list)
    for r in rows:
        by[(r["skill"], r["policy"])].append(r)
    out = ["| Skill | Policy | Completed | Human est. median (min) | Raw median (min) | Deaths median (boss) | Max deaths in another segment (median) |",
           "| --- | --- | --- | --- | --- | --- | --- |"]
    for (skill, policy), rs in sorted(by.items(), key=lambda kv: (kv[0][0] != "novice", kv[0][1])):
        done = [r for r in rs if r["completed"]]
        out.append("| %s | %s | %d / %d | %s | %s | %s (%s) | %s |" % (
            skill, policy, len(done), len(rs), fmt(med([r["human_s"] / 60 for r in done])),
            fmt(med([r["sim_s"] / 60 for r in done])), fmt(med([r["deaths"] for r in rs]), 0),
            fmt(med([r["boss_deaths"] for r in rs]), 0), fmt(med([r["max_other_seg_deaths"] for r in rs]), 0)))
    return "\n".join(out)


def runs_table(rows):
    out = ["| Run | Done | Raw (min) | Human est. (min) | Deaths (boss) | Level | " + " | ".join(SEG_NAMES[s] for s in SEGS)
           + " | Stopped at |",
           "| --- | --- | --- | --- | --- | --- | " + " | ".join("---" for _ in SEGS) + " | --- |"]
    for r in rows:
        segs = " | ".join(("%.1f" % (r["seg_human"][s] / 60)) if r["seg_human"].get(s) else "-" for s in SEGS)
        why = "" if r["completed"] else "%s (%s)" % (r["last_obj"].replace("quest.main:", ""),
                                                     ", ".join(b[2] for b in r["breaches"]) or r["finish"])
        out.append("| %s | %s | %.1f | %.1f | %d (%d) | %s | %s | %s |" % (
            r["name"], "yes" if r["completed"] else "no", r["sim_s"] / 60, r["human_s"] / 60, r["deaths"],
            r["boss_deaths"], r["level"], segs, why))
    return "\n".join(out)


def segments_table(rows):
    novice = [r for r in rows if r["skill"] == "novice"]
    done = [r for r in novice if r["completed"]]
    out = ["| Segment | Target (range), min | Novice human est. median, min | Raw median, min | Damage / max health, median (estimate) | Deaths (all novice runs) |",
           "| --- | --- | --- | --- | --- | --- |"]
    for s in SEGS:
        t = SEG_TARGET[s]
        out.append("| %s | %.1f (%s-%s) | %s | %s | %s | %d |" % (
            SEG_NAMES[s], t[0], fmt(t[1]), fmt(t[2]), fmt(med([r["seg_human"].get(s, 0) / 60 for r in done])),
            fmt(med([r["seg_raw"].get(s, 0) / 60 for r in done])),
            fmt(med([r["seg_damage_frac"].get(s) for r in done]), 2), sum(r["dseg"].get(s, 0) for r in novice)))
    return "\n".join(out)


def deaths_table(rows):
    out = []
    for skill in ["novice", "expert"]:
        causes = collections.Counter()
        for r in rows:
            if r["skill"] == skill:
                causes.update(r["dcause"])
        out.append("%s deaths (%d): %s" % (skill, sum(causes.values()),
                                           ", ".join("%s %d" % (k, v) for k, v in causes.most_common()) or "none"))
    segs = collections.Counter()
    for r in rows:
        if r["skill"] == "novice":
            segs.update(r["dseg"])
    out.append("novice deaths by segment: %s" % ", ".join("%s %d" % (SEG_NAMES.get(k, k), v) for k, v in segs.most_common()))
    return "\n\n".join(out)


def growth_table(rows):
    novice = [r for r in rows if r["skill"] == "novice"]
    out = ["| Measure | Target | Median (novice) | Range |", "| --- | --- | --- | --- |"]
    for key, label, target in [("hold1", "Soldiers in HOLD, stage 1 (share of engaged time)", "0"),
                               ("hold2", "Soldiers in HOLD, stage 2", ">= 0.5"),
                               ("flee3", "Soldiers in FLEE or ROUTED, stage 3", ">= 0.5"),
                               ("ttk_ratio", "Soldier time-to-kill, stage 2 / stage 1", "<= 0.6")]:
        v = [r[key] for r in novice if r[key] is not None]
        out.append("| %s | %s | %s | %s |" % (label, target, fmt(med(v), 2),
                                             "%s-%s" % (fmt(min(v), 2), fmt(max(v), 2)) if v else "-"))
    out.append("| Soldier time-to-kill, stage 1 / stage 2 (s) | - | %s / %s | - |" % (
        fmt(med([r["ttk1"] for r in novice])), fmt(med([r["ttk2"] for r in novice]))))
    return "\n".join(out)


def abilities_table(rows):
    novice = [r for r in rows if r["skill"] == "novice" and r["completed"]] or [r for r in rows if r["skill"] == "novice"]
    out = ["| Ability | Runs using it (novice) | Median uses |", "| --- | --- | --- |"]
    for a in ABILITIES:
        uses = [r["abilities_used"].get(a, 0) for r in novice]
        out.append("| %s | %d / %d | %s |" % (a.replace("ability.", ""), sum(1 for u in uses if u > 0), len(uses),
                                              fmt(med(uses), 0)))
    shares = [r["max_share"] for r in novice if r["max_share"]]
    out.append("")
    out.append("Largest single-ability share of ability damage per run: %s" % (
        ", ".join("%s %.2f" % (s[0].replace("ability.", ""), s[1]) for s in shares) or "-"))
    return "\n".join(out)


def perf_table(rows):
    cpu = [r["cpu_p95"] for r in rows if r["cpu_p95"]]
    oc = [r["off_cam"] for r in rows if r["off_cam"] is not None]
    lt = [r["late_tel"] for r in rows if r["late_tel"] is not None]
    act = [r["max_active"] for r in rows if r["max_active"] is not None]
    near = [r["max_hostiles_near"] for r in rows if r["max_hostiles_near"] is not None]
    return ("CPU per tick p95: median %s ms, max %s ms; peak active enemies %s; peak hostiles within 40 m %s; "
            "hits from attackers off camera at their windup: median %s of the hits taken (max %s); hits within 0.45 s "
            "of their telegraph: max %s; errors %d; invariant failures %d; teleports %d; stuck events %d" % (
                fmt(med(cpu), 2), fmt(max(cpu) if cpu else None, 2), max(act) if act else "-", max(near) if near else "-",
                fmt(med(oc), 2), fmt(max(oc) if oc else None, 2), fmt(max(lt) if lt else None, 2),
                sum(int(r["errors"] or 0) for r in rows), sum(r["invariant_failures"] for r in rows),
                sum(int(r["teleports"] or 0) for r in rows), sum(r["stuck"] for r in rows)))


def targets_table(rows):
    """Plan §5.6's targets against the batch (novice, unassisted, median over seeds)."""
    novice = [r for r in rows if r["skill"] == "novice"]
    done = [r for r in novice if r["completed"]]
    experts = [r for r in rows if r["skill"] == "expert"]
    by_policy = collections.defaultdict(list)
    for r in novice:
        by_policy[r["policy"]].append(r)
    total_h = med([r["human_s"] / 60 for r in done])
    raw = med([r["sim_s"] / 60 for r in done])
    seg_ok = []
    for s in SEGS:
        m = med([r["seg_human"].get(s, 0) / 60 for r in done])
        seg_ok.append("%s %s" % (SEG_NAMES[s], fmt(m)))
    dmg = {s: med([r["seg_damage_frac"].get(s) for r in done]) for s in ["2_forest", "4_village", "5_ruins"]}
    boss_att = med([r["boss_dmg_per_attempt"] for r in novice])
    oc = med([r["off_cam"] for r in novice])
    shares = [r["max_share"][1] for r in novice if r["max_share"]]
    unused = sum(1 for r in done if any(v == 0 for v in r["abilities_used"].values()))
    lines = ["| Target (plan §5.6) | Measured |", "| --- | --- |",
             "| Human estimate 20-30 min in total | %s min (median of completed runs) |" % fmt(total_h),
             "| Raw simulated time 13-26 min | %s min |" % fmt(raw),
             "| Each segment within its §4.9 range (human est., min) | %s |" % ", ".join(seg_ok),
             "| Deaths 1-4 in total | %s |" % fmt(med([r["deaths"] for r in novice]), 0),
             "| 1-2 of them at the boss | %s |" % fmt(med([r["boss_deaths"] for r in novice]), 0),
             "| At most 2 in any other segment | %s |" % fmt(med([r["max_other_seg_deaths"] for r in novice]), 0),
             "| Damage <= 0.6 x max health in segments 2, 4, 5 (estimate) | %s |" % ", ".join(
                 "%s %s" % (SEG_NAMES[k], fmt(v, 2)) for k, v in dmg.items()),
             "| Damage <= 1.0 x max health per boss attempt (estimate) | %s |" % fmt(boss_att, 2),
             "| At least 4 of 5 seeds complete each policy | %s |" % ", ".join(
                 "%s %d/%d" % (p, sum(1 for r in rs if r["completed"]), len(rs)) for p, rs in sorted(by_policy.items())),
             "| Under 20 %% of hits from off-camera or late telegraphs | median %s |" % fmt(oc, 2),
             "| Every ability used once per run; none above 40 %% of ability damage | %d of %d completed runs left one unused; largest share %s |" % (
                 unused, len(done), fmt(max(shares) if shares else None, 2)),
             "| Expert completes all four policies with 0-1 deaths | %s |" % ", ".join(
                 "%s %s/%d" % (r["policy"], "done" if r["completed"] else "not done", r["deaths"]) for r in experts)]
    return "\n".join(lines)


def states_table(rows):
    """The AI-state histogram per growth stage (plan §5.7's growth evidence): for each archetype the
    share of its engaged time in each state, pooled over the novice runs, and its median time-to-kill."""
    novice = [r for r in rows if r["skill"] == "novice"]
    states = ["Approach", "Attack", "Recover", "Staggered", "Hold", "Reposition", "Flee", "Routed"]
    out = ["| Stage | Archetype | Engaged (s, all runs) | " + " | ".join(states) + " | Time-to-kill median (s) |",
           "| --- | --- | --- | " + " | ".join("---" for _ in states) + " | --- |"]
    for stage in ["1", "2", "3"]:
        pooled = collections.defaultdict(collections.Counter)
        for r in novice:
            for arch, st in r["ai_states"].get(stage, {}).items():
                for k, v in st.items():
                    pooled[arch][k] += v
        for arch in sorted(pooled):
            c = pooled[arch]
            eng = c.get("engaged", 0.0)
            if eng <= 0:
                continue
            ttk = med([r["ttk_all"].get(arch, {}).get(stage, {}).get("mean_s") for r in novice])
            out.append("| %s | %s | %.0f | %s | %s |" % (stage, arch, eng, " | ".join(
                ("%.0f %%" % (100.0 * c.get(k, 0.0) / eng)) if c.get(k, 0.0) > 0 else "-" for k in states), fmt(ttk)))
    return "\n".join(out)


def stuck_table(rows, cell=20.0):
    """The stuck-event heatmap: events per 20 m cell of the Valley (x, z of the cell's centre), with
    the objectives the bot was on and how it got out (replan, retrace, teleport)."""
    cells = collections.defaultdict(lambda: [0, collections.Counter(), collections.Counter()])
    for r in rows:
        for e in r["stuck_events"]:
            p = e.get("position", [0, 0, 0])
            key = (int((p[0] // cell) * cell + cell / 2), int((p[2] // cell) * cell + cell / 2))
            cells[key][0] += 1
            cells[key][1][str(e.get("objective", "")).replace("quest.main:", "")] += 1
            cells[key][2][str(e.get("recovered_by", ""))] += 1
    out = ["| Cell centre (x, z) | Stuck events | Objectives | Recovered by |", "| --- | --- | --- | --- |"]
    for key, (n, objs, how) in sorted(cells.items(), key=lambda kv: -kv[1][0]):
        out.append("| (%d, %d) | %d | %s | %s |" % (key[0], key[1], n, ", ".join("%s %d" % kv for kv in objs.most_common()),
                                                    ", ".join("%s %d" % kv for kv in how.most_common())))
    if len(out) == 2:
        out.append("| - | 0 | - | - |")
    return "\n".join(out)


# --------------------------------------------------------------------------- the world bot (P38)

# Plan M6-M9 §5.15: the segments after the Valley, target minutes (target, low, high).
WSEGS = ["w1_opening", "w2_first_oath", "w3_second_oath", "w4_roaming", "w5_stonehold"]
WSEG_NAMES = {"w1_opening": "Opening", "w2_first_oath": "First oath", "w3_second_oath": "Second oath",
              "w4_roaming": "Growth to 5, roaming", "w5_stonehold": "Stonehold"}
WSEG_TARGET = {"w1_opening": (10, 7, 14), "w2_first_oath": (20, 10, 30), "w3_second_oath": (25, 18, 35),
               "w4_roaming": (15, 0, 40), "w5_stonehold": (24, 15, 32)}
WMAIN_TARGET = (94, 60, 140)


def world_row(path):
    """One world run's numbers from its AUTOPILOT_RESULT ("world_bot")."""
    name = os.path.basename(path)[:-5]
    exit_path = path[:-5] + ".exit"
    code, wall = (open(exit_path).read().split() + ["?", "?"])[:2] if os.path.exists(exit_path) else ("?", "?")
    try:
        r = json.load(open(path))
    except (OSError, ValueError):
        return None
    wb = r.get("world_bot")
    if not isinstance(wb, dict):
        return None
    w = wb.get("world", {})
    pol = wb.get("policy", {})
    segs = {s["id"]: s for s in wb.get("segments", [])}
    deaths = wb.get("deaths", [])
    return {
        "name": name, "exit": code, "wall": wall, "r": r, "wb": wb, "w": w, "segs": segs,
        "preset": pol.get("preset") or "-", "oaths": ",".join("%s:%s" % (o[0], o[1]) for o in pol.get("oaths", [])),
        "skill": wb.get("bot", {}).get("skill"), "seed": wb.get("bot", {}).get("seed"),
        "assist": bool(wb.get("bot", {}).get("assist")),
        "completed": bool(wb.get("campaign_completed")), "finish": wb.get("finish_reason"),
        "sim_s": wb.get("simulated_s", 0), "human_s": wb.get("human_estimate_s", 0),
        "deaths": deaths, "breaches": wb.get("breaches", []), "invariants": wb.get("invariant_failures", []),
        "stage": wb.get("main_stage"), "outcomes": wb.get("outcomes", {}), "errors": r.get("errors"),
        "cpu_p95": r.get("perf", {}).get("cpu_tick_ms", {}).get("p95"),
    }


def load_world(batch_dir):
    rows = [world_row(p) for p in sorted(glob.glob(os.path.join(batch_dir, "*.json")))]
    return [r for r in rows if r is not None]


def _who(r):
    return "%s %s%s s%s" % (r["preset"], r["skill"], " assisted" if r["assist"] else "", r["seed"])


def world_summary(rows):
    by = collections.defaultdict(list)
    for r in rows:
        by[(r["skill"], r["assist"], r["preset"], r["oaths"])].append(r)
    out = ["| Skill | Assisted | Preset | Oaths | Completed | Human est. median (min) | Raw median (min) | Deaths median | world_blocked |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for (skill, assist, preset, oaths), rs in sorted(by.items(), key=lambda kv: (str(kv[0][0]), kv[0][2], kv[0][3])):
        done = [r for r in rs if r["completed"]]
        blocked = sum(1 for r in rs for b in r["breaches"] if b.get("classification") == "world_blocked")
        out.append("| %s | %s | %s | %s | %d / %d | %s | %s | %s | %d |" % (
            skill, "yes" if assist else "no", preset, oaths, len(done), len(rs), fmt(med([r["human_s"] / 60 for r in done])),
            fmt(med([r["sim_s"] / 60 for r in done])), fmt(med([len(r["deaths"]) for r in rs]), 0), blocked))
    return "\n".join(out)


def world_runs(rows):
    out = ["| Run | Preset | Oaths | Done | Raw (min) | Human est. (min) | Wall (s) | Deaths | Stage reached | Watchdogs | Invariants | Errors |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        wd = "; ".join("%s: %s (%s)" % (b.get("classification"), b.get("objective"), b.get("reason")) for b in r["breaches"]) or "none"
        inv = "; ".join(str(f.get("failure")) for f in r["invariants"]) or "none"
        out.append("| %s | %s | %s | %s | %.1f | %.1f | %s | %d | %s | %s | %s | %s |" % (
            r["name"], r["preset"], r["oaths"], "yes" if r["completed"] else "no (%s)" % r["finish"], r["sim_s"] / 60,
            r["human_s"] / 60, r["wall"], len(r["deaths"]), r["stage"], wd, inv, r["errors"]))
    return "\n".join(out)


def world_segments(rows):
    done = [r for r in rows if r["completed"]]
    out = ["| Segment | Target (range), min | Human est. median, min | Raw median, min | Combat / traversal median, min | Map screens, fast travels | Regions, POIs | Deaths (all runs) |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for s in WSEGS:
        t = WSEG_TARGET[s]
        seg = [r["segs"].get(s, {}) for r in done]
        out.append("| %s | %d (%d-%d) | %s | %s | %s / %s | %s, %s | %s, %s | %d |" % (
            WSEG_NAMES[s], t[0], t[1], t[2], fmt(med([g.get("human_estimate_s", 0) / 60 for g in seg])),
            fmt(med([g.get("raw_s", 0) / 60 for g in seg])), fmt(med([g.get("combat_s", 0) / 60 for g in seg])),
            fmt(med([g.get("traversal_s", 0) / 60 for g in seg])), fmt(med([g.get("map_screens", 0) for g in seg]), 0),
            fmt(med([g.get("fast_travels", 0) for g in seg]), 0), fmt(med([g.get("regions_entered", 0) for g in seg]), 0),
            fmt(med([g.get("pois", 0) for g in seg]), 0), sum(1 for r in rows for d in r["deaths"] if d.get("segment") == s)))
    out.append("| Main path after the Valley | %d (%d-%d) | %s | %s | | | | %d |" % (
        WMAIN_TARGET[0], WMAIN_TARGET[1], WMAIN_TARGET[2], fmt(med([r["human_s"] / 60 for r in done])),
        fmt(med([r["sim_s"] / 60 for r in done])), sum(len(r["deaths"]) for r in rows)))
    return "\n".join(out)


def world_outcomes(rows):
    keys = ["march", "wood", "crown", "boss.matriarch", "boss.corvane", "boss.harrok", "skarn", "throne", "ancestry"]
    out = ["| Run | " + " | ".join(k.replace("boss.", "") for k in keys) + " | Yields decided |",
           "| --- | " + " | ".join("---" for _ in keys) + " | --- |"]
    for r in rows:
        o = r["outcomes"]
        yd = ", ".join("%s %s" % (str(y[1]).split(".")[-1], y[2]) for y in r["wb"].get("yields_decided", [])) or "-"
        out.append("| %s | %s | %s |" % (r["name"], " | ".join(str(o.get(k, "")).replace("ancestry.", "") or "-" for k in keys), yd))
    return "\n".join(out)


def world_bosses(rows):
    out = ["| Run | Boss | Attempts | Engaged | Disengaged | Yields | Phases | Outcome |", "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        for bid, b in sorted(r["w"].get("bosses", {}).items()):
            out.append("| %s | %s | %s | %s | %s | %s | %s | %s |" % (
                r["name"], bid, b.get("attempts", 0), b.get("engaged", 0),
                ", ".join(str(d[1]) for d in b.get("disengaged", [])) or "-", b.get("yields", 0),
                ", ".join(str(p[1]) for p in b.get("phases", [])) or "-", b.get("outcome") or ("defeated" if b.get("defeated") else "-")))
    return "\n".join(out)


def world_travel(rows):
    out = ["| Run | Regions (s) | Discovered | Map screens | Fast travels (refused) | Refusals | Stage seconds |",
           "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        w = r["w"]
        regions = ", ".join("%s %.0f" % (k.replace("region.", ""), v.get("s", 0)) for k, v in sorted(w.get("regions", {}).items()))
        ft = w.get("fast_travels", [])   # [tick, from, to, ok, message]
        refused = sum(1 for f in ft if len(f) > 3 and not f[3])
        out.append("| %s | %s | %s | %s | %d (%d) | %d | %s |" % (
            r["name"], regions or "-", w.get("discovered", 0), w.get("map_screens", 0), len(ft), refused,
            len(w.get("refusals", [])), ", ".join("%s: %.0f" % kv for kv in sorted(w.get("stage_s", {}).items()))))
    return "\n".join(out)


def world_streaming(rows):
    out = ["| Run | Loads | Unloads | Thrash | Smallest margin (m) | Worst work frame (ms) | Path queries per tick p95 / max | Save max (bytes) | Counted combatants max (s over 12) | CPU per tick p95 (ms) |",
           "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        w = r["w"]
        st = w.get("streaming", {})
        q = w.get("path_queries_per_tick", {})
        b = r["wb"].get("budget", {})
        out.append("| %s | %s | %s | %s | %s | %s | %s / %s | %s | %s (%s) | %s |" % (
            r["name"], st.get("loads", "-"), st.get("unloads", "-"), st.get("thrash", "-"), fmt(st.get("min_margin_m")),
            fmt(st.get("work_ms_max")), q.get("p95", "-"), q.get("max", "-"), w.get("save_bytes_max", "-"),
            b.get("max_counted", "-"), fmt(b.get("over_cap_s")), fmt(r["cpu_p95"], 2)))
    return "\n".join(out)


def world_formations(rows):
    out = ["| Run | Formations seen | Group / banner / single lock samples (stage 4+) | Group lock share | Banners felled | Broken | Routed | Sweeps |",
           "| --- | --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        f = r["w"].get("formations", {})
        out.append("| %s | %s | %s / %s / %s | %s | %s | %s | %s | %s |" % (
            r["name"], f.get("seen", 0), f.get("group_lock_samples", 0), f.get("banner_lock_samples", 0),
            f.get("single_lock_samples", 0), fmt(r["w"].get("formation_lock_share"), 2), f.get("banners_felled", 0),
            f.get("broken", 0), f.get("routed", 0), f.get("sweeps", 0)))
    return "\n".join(out)


def world_siege(rows):
    out = ["| Run | Engines destroyed | Engines thrown | Engine shots at the giant | Damage taken from engines | Wander spawns | World events |",
           "| --- | --- | --- | --- | --- | --- | --- |"]
    for r in rows:
        sg = r["w"].get("siege", {})
        dmg = sum(v for k, v in r["wb"].get("damage_taken_by_archetype", {}).items() if k.startswith("prop.siege"))
        ev = ", ".join("%s %s" % (k.replace("event.", ""), "/".join(v.get("outcomes", [])) or "started %d" % v.get("started", 0))
                       for k, v in sorted(r["w"].get("world_events", {}).items())) or "-"
        out.append("| %s | %s | %s | %s | %d | %s | %s |" % (
            r["name"], sg.get("engines_destroyed", 0), sg.get("engines_thrown", 0), sg.get("shots_at_giant", 0), dmg,
            r["w"].get("wander", {}).get("spawns", 0), ev))
    return "\n".join(out)


def world_music(rows):
    out = ["| Run | Stage | Explore | Danger | Combat |", "| --- | --- | --- | --- | --- |"]
    for r in rows:
        for stage, m in sorted(r["w"].get("music", {}).items()):
            total = sum(m.values()) or 1.0
            out.append("| %s | %s | %s | %s | %s |" % (r["name"], stage, *("%.0f %%" % (100.0 * m.get(k, 0.0) / total)
                                                                          for k in ["explore", "danger", "combat"])))
    return "\n".join(out)


def world_deaths(rows):
    causes = collections.Counter()
    segs = collections.Counter()
    for r in rows:
        for d in r["deaths"]:
            causes["%s/%s" % (d.get("killer_archetype"), str(d.get("action_id", "")).replace("ability.", ""))] += 1
            segs[WSEG_NAMES.get(d.get("segment"), d.get("segment"))] += 1
    return "deaths (%d): %s\n\ndeaths by segment: %s" % (
        sum(causes.values()), ", ".join("%s %d" % kv for kv in causes.most_common()) or "none",
        ", ".join("%s %d" % kv for kv in segs.most_common()) or "none")


def world_stuck(rows, cell=50.0):
    """Stuck events per 50 m cell of the world, with the objectives and how the bot got out."""
    cells = collections.defaultdict(lambda: [0, collections.Counter(), collections.Counter()])
    for r in rows:
        for e in r["wb"].get("stuck_events", []):
            p = e.get("position", [0, 0, 0])
            key = (int((p[0] // cell) * cell + cell / 2), int((p[2] // cell) * cell + cell / 2))
            cells[key][0] += 1
            cells[key][1][str(e.get("objective", "")).replace("quest.world_main:", "")] += 1
            cells[key][2][str(e.get("recovered_by", ""))] += 1
    out = ["| Cell centre (x, z) | Stuck events | Objectives | Recovered by |", "| --- | --- | --- | --- |"]
    for key, (n, objs, how) in sorted(cells.items(), key=lambda kv: -kv[1][0])[:25]:
        out.append("| (%d, %d) | %d | %s | %s |" % (key[0], key[1], n, ", ".join("%s %d" % kv for kv in objs.most_common(3)),
                                                    ", ".join("%s %d" % kv for kv in how.most_common())))
    if len(out) == 2:
        out.append("| - | 0 | - | - |")
    return "\n".join(out)


SECTIONS = {"summary": summary_table, "runs": runs_table, "segments": segments_table, "deaths": deaths_table,
            "growth": growth_table, "abilities": abilities_table, "perf": perf_table, "stuck": stuck_table, "states": states_table,
            "targets": targets_table}
WORLD_SECTIONS = {"world_summary": world_summary, "world_runs": world_runs, "world_segments": world_segments,
                  "world_outcomes": world_outcomes, "world_bosses": world_bosses, "world_travel": world_travel,
                  "world_streaming": world_streaming, "world_formations": world_formations, "world_siege": world_siege,
                  "world_music": world_music, "world_deaths": world_deaths, "world_stuck": world_stuck}

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    world = load_world(sys.argv[1])
    valley = [] if world and not sys.argv[2:] else load(sys.argv[1])
    for section in (sys.argv[2:] or (list(WORLD_SECTIONS) if world else list(SECTIONS))):
        print("### " + section)
        if section in WORLD_SECTIONS:
            print(WORLD_SECTIONS[section](world))
        else:
            print(SECTIONS[section](valley))
        print()
