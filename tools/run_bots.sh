#!/usr/bin/env bash
# Valley bot batch runner (plan §3.19, §5.6). Starts each run as its own headless Godot process with
# a wall-clock limit, at most --jobs at once, and prints a summary table when all are done. Each run
# writes its AUTOPILOT_RESULT (JSON) to user://bot_runs/<tag>/<name>.json and its log next to it
# (<name>.log); <name> is <policy>_<skill>_<seed>[_assist][_loop]. A run that hits its time limit is
# a failure with its last objective (from the log). Every Godot call goes through tools/gd.sh, so
# user:// is this worktree's .userdata/ folder.
#
# Usage: tools/run_bots.sh [options] [RUN...]
#   RUN                  policy:skill:seed[:assist]   e.g. help_cache:novice:1  force:expert:2:assist
#   --preset=assisted    the four policies, novice, seed 1, assisted (the M4 complete-loop gate)
#   --preset=balance     P17b's matrix: novice x {help_cache, help_ogre, intimidate} x seeds 1-5,
#                        novice x force x seeds 1-3, expert x the four policies x seed 1
#   --preset=stability   the 30-minute run: --bot-loop --bot-assist, help_cache first, 1800 s
#   --jobs=N             runs at once (default 3)
#   --timeout=S          wall-clock limit of each run in seconds (default 900)
#   --autoplay=S         simulated-seconds limit of each run (default 2400; stability 1800)
#   --tag=NAME           the batch's folder under user://bot_runs/ (default: a time stamp)
#   --extra="ARGS"       more user args for every run (e.g. "--perf")
#   --dry-run            print the commands only
#   --summary            only print the summary table of an existing --tag
# Exit code: 0 when every run exited 0, 1 otherwise. Start it with run_in_background (or nohup) for
# long matrices: a balance matrix takes 20-25 minutes of wall time at 3 jobs.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GD="$ROOT/tools/gd.sh"
DATA="${GB_USERDATA:-$ROOT/.userdata}"
# user:// = $XDG_DATA_HOME/godot/app_userdata/<project name with : \ / ? * | < > " replaced by ->.
PROJECT_NAME="$(sed -n 's/^config\/name="\(.*\)"$/\1/p' project.godot | head -n 1 | sed 's#[:\\/?*|<>"]#-#g')"
USERDIR="$DATA/godot/app_userdata/$PROJECT_NAME"

JOBS=3
TIMEOUT=900
AUTOPLAY=""
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
		--jobs=*) JOBS="${arg#--jobs=}" ;;
		--timeout=*) TIMEOUT="${arg#--timeout=}" ;;
		--autoplay=*) AUTOPLAY="${arg#--autoplay=}" ;;
		--tag=*) TAG="${arg#--tag=}" ;;
		--extra=*) EXTRA="${arg#--extra=}" ;;
		--dry-run) DRY=1 ;;
		--summary) SUMMARY_ONLY=1 ;;
		-h|--help) sed -n '2,27p' "$0"; exit 0 ;;
		--*) echo "run_bots.sh: unknown option '$arg'" >&2; exit 2 ;;
		*) RUNS+=("$arg") ;;
	esac
done
if [ -z "$AUTOPLAY" ]; then
	if [ "$LOOP" = "1" ]; then AUTOPLAY=1800; else AUTOPLAY=2400; fi
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

# name_of policy:skill:seed[:assist] -> policy_skill_seed[_assist][_loop]
name_of() {
	local IFS=':'
	read -r policy skill seed assist <<<"$1"
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
		"--save-dir=user://bot_saves/$TAG/$name" --mode=valley --new-game --scenario=valley
		"--autoplay=$AUTOPLAY" "--bot-village=$policy" "--bot-skill=${skill:-novice}" "--bot-seed=${seed:-1}"
		"--result-file=user://$OUT_REL/$name.json")
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
	echo "Valley bot runs in user://$OUT_REL ($OUT)"
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
    vb = res.get("valley_bot", {})
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
    rows.append([name, code, wall, str(vb.get("completed", "")), "%.0f" % float(vb.get("simulated_s", 0) or 0),
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
