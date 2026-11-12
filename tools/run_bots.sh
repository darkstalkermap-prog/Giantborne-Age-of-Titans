#!/usr/bin/env bash
# Valley and world bot batch runner (plan M2-M5 §3.19, §5.6; P38: plan M6-M9 §6.1-§6.4). Starts each
# run as its own headless Godot process with a wall-clock limit, at most --jobs at once, and prints a
# summary table when all are done. Each run writes its AUTOPILOT_RESULT (JSON) to
# user://bot_runs/<tag>/<name>.json and its log next to it (<name>.log); <name> is
# <policy>_<skill>_<seed>[_assist][_loop]. A run that hits its time limit is a failure with its last
# objective (from the log). Every Godot call goes through tools/gd.sh, so user:// is this worktree's
# .userdata/ folder.
#
# Usage: tools/run_bots.sh [options] [RUN...]
#   RUN                  policy:skill:seed[:assist]   e.g. help_cache:novice:1  force:expert:2:assist
#                        P38: a world run names a world policy with "w." first: w.peaceful, w.conqueror,
#                        w.mixed (the presets of plan §6.1), w.order_march, w.order_wood, w.order_crown
#                        (each oath first with a stage-4 resolution), w.campaign (the Valley's New Game
#                        through the Kings' Door, --bot-campaign), e.g. w.conqueror:novice:2:assist
#   --preset=assisted    the four policies, novice, seed 1, assisted (the M4 complete-loop gate)
#   --preset=balance     P17b's matrix: novice x {help_cache, help_ogre, intimidate} x seeds 1-5,
#                        novice x force x seeds 1-3, expert x the four policies x seed 1
#   --preset=stability   the 30-minute run: --bot-loop --bot-assist, help_cache first, 1800 s
#   --preset=world_assisted   P38: the three world presets, novice, seed 1, assisted (the M9 acceptance)
#   --preset=world_orders     P38: each oath first (w.order_march, w.order_wood, w.order_crown), novice,
#                        seed 1, assisted (the M9 acceptance)
#   --preset=world_balance    P38/P39: novice x the three presets x seeds 1-3, expert x the three presets x
#                        seeds 1-3, unassisted, and the three orders once (plan §6.4; 3 jobs, 1,800 s each)
#   --preset=world_stability  P38/P39: the 60-minute world run: --bot-loop --bot-assist through the three
#                        presets from --mode=world --new-game, --autoplay=3600 (plan §6.2)
#   --preset=world_smoke P38: the long world smoke run: w.peaceful, novice, seed 1, assisted, with --perf
#   --jobs=N             runs at once (default 3)
#   --timeout=S          wall-clock limit of each run in seconds (default 900)
#   --autoplay=S         simulated-seconds limit of each run (default 2400; stability 1800)
#   --tag=NAME           the batch's folder under user://bot_runs/ (default: a time stamp)
#   --extra="ARGS"       more user args for every run (e.g. "--perf")
#   --dry-run            print the commands only
#   --summary            only print the summary table of an existing --tag
# Exit code: 0 when every run exited 0, 1 otherwise. Start it with run_in_background (or nohup) for
# long matrices: a balance matrix takes 25-35 minutes of wall time at 3 jobs.
# The Markdown tables of a batch (P17b; docs/HOW_IT_PLAYS.md, docs/BALANCE_LOG.md):
#   python3 tools/bot_report.py .userdata/godot/app_userdata/<project>/bot_runs/<tag> [section ...]
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GD="$ROOT/tools/gd.sh"
DATA="${GB_USERDATA:-$ROOT/.userdata}"
# user:// = $XDG_DATA_HOME/godot/app_userdata/<project name with : \ / ? * | < > " replaced by ->.
PROJECT_NAME="$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot | head -n 1 | sed 's#[:\\/?*|<>"]#-#g')"
USERDIR="$DATA/godot/app_userdata/$PROJECT_NAME"

JOBS=3
TIMEOUT=""
AUTOPLAY=""
# P38: world runs' defaults (a campaign takes far longer than the Valley's slice)
WORLD_TIMEOUT_DEFAULT=3600
TAG="$(date +%Y%m%d_%H%M%S)"
EXTRA=""
DRY=0
SUMMARY_ONLY=0
LOOP=0
RUNS=()

for arg in "$@"; do
	case "$arg" in
		--preset=assisted)
			RUNS+=(help_cache:novice:1:assist help_ogre:novice:1:assist intimidate:novice:1:assist force:novice:1:assist) ;;
		--preset=balance)
			for p in help_cache help_ogre intimidate; do for s in 1 2 3 4 5; do RUNS+=("$p:novice:$s"); done; done
			for s in 1 2 3; do RUNS+=("force:novice:$s"); done
			for p in help_cache help_ogre intimidate force; do RUNS+=("$p:expert:1"); done ;;
		--preset=stability)
			LOOP=1
			RUNS+=(help_cache:novice:1:assist) ;;
		--preset=world_assisted)
			RUNS+=(w.peaceful:novice:1:assist w.conqueror:novice:1:assist w.mixed:novice:1:assist) ;;
		--preset=world_orders)
			RUNS+=(w.order_march:novice:1:assist w.order_wood:novice:1:assist w.order_crown:novice:1:assist) ;;
		--preset=world_balance)
			for p in peaceful conqueror mixed; do for s in 1 2 3; do RUNS+=("w.$p:novice:$s"); done; done
			for p in peaceful conqueror mixed; do for s in 1 2 3; do RUNS+=("w.$p:expert:$s"); done; done
			for o in order_march order_wood order_crown; do RUNS+=("w.$o:novice:1"); done
			WORLD_TIMEOUT_DEFAULT=1800 ;;
		--preset=world_stability)
			LOOP=1
			RUNS+=(w.peaceful:novice:1:assist) ;;
		--preset=world_smoke)
			EXTRA="${EXTRA:+$EXTRA }--perf"
			RUNS+=(w.peaceful:novice:1:assist) ;;
		--jobs=*) JOBS="${arg#--jobs=}" ;;
		--timeout=*) TIMEOUT="${arg#--timeout=}" ;;
		--autoplay=*) AUTOPLAY="${arg#--autoplay=}" ;;
		--tag=*) TAG="${arg#--tag=}" ;;
		--extra=*) EXTRA="${arg#--extra=}" ;;
		--dry-run) DRY=1 ;;
		--summary) SUMMARY_ONLY=1 ;;
		-h|--help) sed -n '2,40p' "$0"; exit 0 ;;
		--*) echo "run_bots.sh: unknown option '$arg'" >&2; exit 2 ;;
		*) RUNS+=("$arg") ;;
	esac
done
# P38: world runs (a spec starting "w.") get the world's limits unless given
WORLD_RUNS=0
for spec in "${RUNS[@]}"; do
	case "$spec" in w.*) WORLD_RUNS=1 ;; esac
done
if [ -z "$AUTOPLAY" ]; then
	if [ "$WORLD_RUNS" = "1" ]; then
		if [ "$LOOP" = "1" ]; then AUTOPLAY=3600; else AUTOPLAY=7200; fi
	elif [ "$LOOP" = "1" ]; then AUTOPLAY=1800; else AUTOPLAY=2400; fi
fi
if [ -z "$TIMEOUT" ]; then
	if [ "$WORLD_RUNS" = "1" ]; then TIMEOUT=$WORLD_TIMEOUT_DEFAULT; else TIMEOUT=900; fi
fi
OUT_REL="bot_runs/$TAG"
OUT="$USERDIR/$OUT_REL"
mkdir -p "$OUT"

run_limited() {
	local secs="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout --kill-after=30 "$secs" "$@"
	else
		"$@"
	fi
}

# name_of policy:skill:seed[:assist] -> policy_skill_seed[_assist][_loop] (a world policy w.<name> -> w_<name>)
name_of() {
	local IFS=':'
	read -r policy skill seed assist <<<"$1"
	policy="${policy/w./w_}"
	local n="${policy}_${skill:-novice}_${seed:-1}"
	if [ "${assist:-}" = "assist" ]; then n="${n}_assist"; fi
	if [ "$LOOP" = "1" ]; then n="${n}_loop"; fi
	echo "$n"
}

one_run() {
	local spec="$1"
	local IFS=':'
	read -r policy skill seed assist <<<"$spec"
	unset IFS
	local name
	name="$(name_of "$spec")"
	local args=(--headless --path . --fixed-fps 60 -- --no-user-settings
		"--save-dir=user://bot_saves/$TAG/$name")
	case "$policy" in
		w.*)
			# P38: a world run (plan M6-M9 §6.1): from world_start, or the whole campaign
			local wp="${policy#w.}"
			case "$wp" in
				campaign) args+=(--mode=valley --new-game --scenario=valley --bot-campaign --bot-village=help_cache) ;;
				*) args+=(--mode=world --new-game --scenario=world) ;;
			esac
			case "$wp" in
				peaceful|conqueror|mixed) args+=("--bot-preset=$wp") ;;
				order_march) args+=(--bot-preset=peaceful "--bot-oaths=march:help,crown:parley") ;;
				order_wood) args+=(--bot-preset=peaceful "--bot-oaths=wood:drive,march:force") ;;
				order_crown) args+=(--bot-preset=peaceful "--bot-oaths=crown:breach,wood:slay") ;;
				campaign) args+=(--bot-preset=peaceful) ;;
				*) echo "run_bots.sh: unknown world policy '$wp'" >&2 ;;
			esac
			args+=("--autoplay=$AUTOPLAY" "--bot-skill=${skill:-novice}" "--bot-seed=${seed:-1}"
				"--result-file=user://$OUT_REL/$name.json") ;;
		*)
			args+=(--mode=valley --new-game --scenario=valley
				"--autoplay=$AUTOPLAY" "--bot-village=$policy" "--bot-skill=${skill:-novice}" "--bot-seed=${seed:-1}"
				"--result-file=user://$OUT_REL/$name.json") ;;
	esac
	if [ "${assist:-}" = "assist" ]; then args+=(--bot-assist); fi
	if [ "$LOOP" = "1" ]; then args+=(--bot-loop); fi
	if [ -n "$EXTRA" ]; then
		# shellcheck disable=SC2206
		local extra=($EXTRA)
		args+=("${extra[@]}")
	fi
	if [ "$DRY" = "1" ]; then
		echo "tools/gd.sh ${args[*]}"
		return 0
	fi
	local start=$SECONDS
	run_limited "$TIMEOUT" "$GD" "${args[@]}" >"$OUT/$name.log" 2>&1
	local code=$?
	echo "$code $((SECONDS - start))" >"$OUT/$name.exit"
	return 0
}

summary() {
	echo ""
	echo "Bot runs in user://$OUT_REL ($OUT)"
	if command -v python3 >/dev/null 2>&1; then
		python3 - "$OUT" <<'PY'
import json, os, sys, glob
out = sys.argv[1]
rows = []
for exit_file in sorted(glob.glob(os.path.join(out, "*.exit"))):
    name = os.path.basename(exit_file)[:-5]
    code, wall = (open(exit_file).read().split() + ["?", "?"])[:2]
    res = {}
    path = os.path.join(out, name + ".json")
    if os.path.exists(path):
        try:
            res = json.load(open(path))
        except Exception:
            res = {}
    vb = res.get("valley_bot", {}) or res.get("world_bot", {})
    last = ""
    if not vb:
        log = os.path.join(out, name + ".log")
        if os.path.exists(log):
            for line in open(log, errors="replace"):
                if "breach" in line or "invariant" in line:
                    last = line.strip()[:60]
    breaches = vb.get("breaches", [])
    objectives = vb.get("objectives", [])
    last_obj = objectives[-1]["id"] if objectives else ""
    loop = bool(vb.get("bot", {}).get("loop", False))
    # A loop run's metrics restart with each new game: its simulated time is the Autopilot's.
    sim = res.get("simulated_s", 0) if loop else vb.get("simulated_s", 0)
    if "world_bot" in res and objectives:
        mains = [o["id"] for o in objectives if o["id"].startswith("quest.world_main:")]
        last_obj = mains[-1] if mains else last_obj
    rows.append([name, code, wall, str(vb.get("completed", "")), "%.0f" % float(sim or 0),
        "%.0f" % float(vb.get("human_estimate_s", 0) or 0), str(len(vb.get("deaths", []))),
        str(len(breaches)), ",".join(sorted({b.get("classification", "?") for b in breaches})),
        str(len(vb.get("invariant_failures", []))), str(res.get("errors", "?")),
        str(vb.get("loop_completed", "")), last_obj if code != "0" else "", last])
head = ["run", "exit", "wall_s", "done", "sim_s", "human_s", "deaths", "breaches", "class", "invar", "errors", "loops", "last objective", "note"]
widths = [max(len(str(r[i])) for r in rows + [head]) for i in range(len(head))]
print("  ".join(h.ljust(widths[i]) for i, h in enumerate(head)))
for r in rows:
    print("  ".join(str(c).ljust(widths[i]) for i, c in enumerate(r)))
PY
	else
		for f in "$OUT"/*.exit; do echo "$(basename "$f" .exit): exit $(cut -d' ' -f1 "$f")"; done
	fi
}

if [ "$SUMMARY_ONLY" = "1" ]; then
	summary
	exit 0
fi
if [ "${#RUNS[@]}" = "0" ]; then
	echo "run_bots.sh: no runs (give RUN specs or a --preset; --help)" >&2
	exit 2
fi

echo "run_bots.sh: ${#RUNS[@]} run(s), $JOBS at once, ${TIMEOUT} s limit each, --autoplay=$AUTOPLAY -> $OUT"
for spec in "${RUNS[@]}"; do
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do
		wait -n 2>/dev/null || sleep 1
	done
	echo "  start $(name_of "$spec")"
	one_run "$spec" &
done
wait
if [ "$DRY" = "1" ]; then
	exit 0
fi
summary
FAILED=0
for f in "$OUT"/*.exit; do
	[ "$(cut -d' ' -f1 "$f")" = "0" ] || FAILED=1
done
exit "$FAILED"
