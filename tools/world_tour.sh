#!/usr/bin/env bash
# The world screenshot tour (P40; tools/world_tour.gd): a world bot's campaign in a 1280 x 720 window under
# Xvfb with a screenshot as the bot reaches each place (the Kingsgate shelf's view first), or scripted
# placements for the places its route does not pass.
#
#   tools/world_tour.sh [--out=DIR] [--run=SPEC] [--places=LIST] [--render=always] [-- more user args]
#
#   --out=DIR        the shots, shots.jsonl and tour.log (default builds/world_tour/<time stamp>)
#   --run=SPEC       the bot's run as tools/run_bots.sh names a world run, policy:skill:seed[:assist] with
#                    policy w.peaceful, w.conqueror, w.mixed, w.order_march, w.order_wood or w.order_crown.
#                    Default w.order_crown:novice:1:assist, the crown-first order assisted: it breaches Fort
#                    Aldmere, fights the Iron Regiment and passes Brannock at stage 4 (none of the three
#                    presets takes the crown at their default two oaths).
#   --places=LIST    scripted placements instead of the bot (the names of PLACES in tools/world_tour.gd,
#                    e.g. drowned_steps)
#   --render=always  draw every frame (many times slower under a software renderer; the default draws only
#                    the frames of each shot, so the bot plays at its headless speed)
# The run's own result (AUTOPILOT_RESULT: completed, simulated seconds, deaths) is in tour.log. Godot runs
# through tools/gd.sh (user:// is this worktree's .userdata/); xvfb-run is used unless DISPLAY is set.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OUT="$ROOT/builds/world_tour/$(date +%Y%m%d_%H%M%S)"
SPEC="w.order_crown:novice:1:assist"
PLACES=""
RENDER=""
EXTRA=()
while [ $# -gt 0 ]; do
	case "$1" in
		--out=*) OUT="${1#--out=}" ;;
		--run=*) SPEC="${1#--run=}" ;;
		--places=*) PLACES="${1#--places=}" ;;
		--render=*) RENDER="${1#--render=}" ;;
		-h|--help) sed -n '2,21p' "$0"; exit 0 ;;
		--) shift; EXTRA=("$@"); break ;;
		*) echo "world_tour.sh: unknown option '$1'" >&2; exit 2 ;;
	esac
	shift
done
case "$OUT" in /*) ;; *) OUT="$ROOT/$OUT" ;; esac
mkdir -p "$OUT"
NAME="tour_$(date +%Y%m%d_%H%M%S)"
ARGS=(--no-user-settings "--save-dir=user://world_tour_saves/$NAME" --mode=world --new-game
	--deterministic-streaming "--tour-dir=$OUT")
if [ -n "$RENDER" ]; then ARGS+=("--tour-render=$RENDER"); fi
if [ -n "$PLACES" ]; then
	ARGS+=("--tour-places=$PLACES")
else
	IFS=':' read -r policy skill seed assist <<<"$SPEC"
	case "$policy" in
		w.peaceful|w.conqueror|w.mixed) ARGS+=("--bot-preset=${policy#w.}") ;;
		w.order_march) ARGS+=(--bot-preset=peaceful "--bot-oaths=march:help,crown:parley") ;;
		w.order_wood) ARGS+=(--bot-preset=peaceful "--bot-oaths=wood:drive,march:force") ;;
		w.order_crown) ARGS+=(--bot-preset=peaceful "--bot-oaths=crown:breach,wood:slay") ;;
		*) echo "world_tour.sh: unknown world policy '$policy' (w.peaceful, w.conqueror, w.mixed, w.order_*)" >&2; exit 2 ;;
	esac
	ARGS+=(--scenario=world --autoplay=7200 "--bot-skill=${skill:-novice}" "--bot-seed=${seed:-1}")
	if [ "${assist:-}" = "assist" ]; then ARGS+=(--bot-assist); fi
fi
ARGS+=("${EXTRA[@]}")
RUN=(tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy --fixed-fps 60
	-s res://tools/world_tour.gd -- "${ARGS[@]}")
echo "world_tour.sh: ${RUN[*]}" | tee "$OUT/command.txt"
start=$SECONDS
if [ -z "${DISPLAY:-}" ]; then
	xvfb-run -a -s "-screen 0 1280x720x24" "${RUN[@]}" >"$OUT/tour.log" 2>&1
else
	"${RUN[@]}" >"$OUT/tour.log" 2>&1
fi
code=$?
echo "world_tour.sh: exit $code after $((SECONDS - start)) s; $(grep -c '^TOUR_SHOT' "$OUT/tour.log") shots in $OUT"
exit $code
