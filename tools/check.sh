#!/usr/bin/env bash
# The definition-of-done sequence of the M2-M5 plan (§1.1), failing on the first bad step:
#   1. import   2. build scenes (only with --only=... or --build)   3. import again
#   4. full test suite, silent (--no-audio; audio suites switch audio on for their own tests),
#      plus the slow suites with --slow and the gate tier with --gate; it also parses every script;
#      the suite times are printed and kept in .userdata/check/suite_times.txt
#   5. 120 s autoplay with 0 errors; a soak of 120 s or more must also break a fence, fill the
#      debris pool and award loot (the M1 breakable path stays covered; M2 gate)
#
# Usage: tools/check.sh [--slow] [--gate] [--audio] [--only=<builder>[,<builder>]] [--build]
#                       [--build-args=<args>] [--autoplay=SECONDS]
#   --only=...    rebuild the named scene builders (before P04's builder split: all of them)
#   --build       rebuild every scene
#   --build-args=...  extra arguments for the builders, after "--" (P25: --build-args=--chunks=c2_6,c3_6
#                 makes the world builder rebuild those chunks and their eight neighbours); a build
#                 that ran the world builder is followed by the world's seam check on the chunks it
#                 rebuilt (tools/world/seam_check.gd: heights equal across the seams, no walkable border
#                 face over 35 degrees)
#   --autoplay=S  soak length in seconds (default 120; 0 skips the soak)
#   --slow        also run tests/slow (the tier's budget: 8 minutes)
#   --gate        also run tests/gate (walkthroughs, oath combinations, boss runs, soaks; P19)
#   --audio       before the suites: the audio pipeline's own tests (tools/audio/test_synth.py)
#                 and build_audio.py --verify (every master and every Ogg regenerated into a
#                 temporary folder and compared with assets/audio/manifest.json, bit-exact on the
#                 reference toolchain); skipped with a note when python3, numpy or ffmpeg with
#                 libvorbis is missing. The audio asset suites run in the default suite (P19).
# Every Godot call goes through tools/gd.sh (this worktree's own user:// folder). Logs of the
# last run are kept in .userdata/check/.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GD="$ROOT/tools/gd.sh"
LOGS="${GB_USERDATA:-$ROOT/.userdata}/check"
mkdir -p "$LOGS"

SLOW=0
GATE=0
AUDIO=0
BUILD=""
BUILD_EXTRA=""
AUTOPLAY=120
for arg in "$@"; do
	case "$arg" in
		--slow) SLOW=1 ;;
		--gate) GATE=1 ;;
		--audio) AUDIO=1 ;;
		--only=*) BUILD="$arg" ;;
		--build) BUILD="all" ;;
		--build-args=*) BUILD_EXTRA="${arg#--build-args=}" ;;
		--autoplay=*) AUTOPLAY="${arg#--autoplay=}" ;;
		-h|--help) sed -n '2,28p' "$0"; exit 0 ;;
		*) echo "check.sh: unknown option '$arg'" >&2; exit 2 ;;
	esac
done

# run_limited SECONDS COMMAND...: runs COMMAND, killed after SECONDS when coreutils timeout exists.
run_limited() {
	local secs="$1"
	shift
	if command -v timeout >/dev/null 2>&1; then
		timeout --kill-after=30 "$secs" "$@"
	else
		"$@"
	fi
}

fail() {
	echo "CHECK FAILED: $1" >&2
	if [ -n "${2:-}" ] && [ -f "$2" ]; then
		echo "---- last lines of $2 ----" >&2
		tail -n 40 "$2" >&2
	fi
	exit 1
}

step() {
	echo "== $1"
}

step "import"
run_limited 600 "$GD" --headless --path . --import >"$LOGS/import1.log" 2>&1 \
	|| fail "import exited with $?" "$LOGS/import1.log"

if [ -n "$BUILD" ]; then
	step "build scenes (${BUILD}${BUILD_EXTRA:+ $BUILD_EXTRA})"
	BUILD_ARGS=()
	if [ "$BUILD" != "all" ]; then
		BUILD_ARGS=(-- "$BUILD")
	fi
	if [ -n "$BUILD_EXTRA" ]; then
		[ ${#BUILD_ARGS[@]} -eq 0 ] && BUILD_ARGS=(--)
		# shellcheck disable=SC2206
		BUILD_ARGS+=($BUILD_EXTRA)
	fi
	# P25: the world builder needs about a minute (several on a slow machine): the limit is 1,500 s.
	run_limited 1500 "$GD" --headless --path . res://tools/build_scenes.tscn ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
		>"$LOGS/build.log" 2>&1 || fail "scene build exited with $?" "$LOGS/build.log"
	if grep -E "SCRIPT ERROR|^ERROR" "$LOGS/build.log" >/dev/null; then
		fail "errors while building scenes" "$LOGS/build.log"
	fi
	# P25: the world's seams, on the chunks the world builder rebuilt (all without --chunks=).
	if grep -q "^build_scenes: world -> " "$LOGS/build.log"; then
		SEAM_ARGS=()
		for a in $BUILD_EXTRA; do
			case "$a" in --chunks=*) SEAM_ARGS=(-- "$a") ;; esac
		done
		step "world seam check${SEAM_ARGS[1]:+ (${SEAM_ARGS[1]})}"
		run_limited 600 "$GD" --headless --path . -s res://tools/world/seam_check.gd ${SEAM_ARGS[@]+"${SEAM_ARGS[@]}"} \
			>"$LOGS/seam_check.log" 2>&1 || fail "the world's seam check failed" "$LOGS/seam_check.log"
		grep -m1 "^SEAM_CHECK" "$LOGS/seam_check.log"
	fi
fi

step "import (register new classes and resources)"
run_limited 600 "$GD" --headless --path . --import >"$LOGS/import2.log" 2>&1 \
	|| fail "second import exited with $?" "$LOGS/import2.log"

# P19: the audio pipeline (generators, bit-exact regeneration, budgets) before the suites.
if [ "$AUDIO" = "1" ]; then
	if ! command -v python3 >/dev/null 2>&1; then
		echo "== audio: SKIPPED (python3 is not installed; the generators need Python 3 and numpy)"
	elif ! python3 -c "import numpy" >/dev/null 2>&1; then
		echo "== audio: SKIPPED (numpy is not installed)"
	elif ! command -v ffmpeg >/dev/null 2>&1 || ! ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libvorbis; then
		echo "== audio: SKIPPED (ffmpeg with the libvorbis encoder is not installed)"
	else
		step "audio pipeline tests (tools/audio/test_synth.py)"
		run_limited 600 python3 tools/audio/test_synth.py >"$LOGS/audio_synth.log" 2>&1 \
			|| fail "the audio pipeline's tests failed" "$LOGS/audio_synth.log"
		step "audio regeneration (build_audio.py --verify)"
		run_limited 1800 python3 tools/audio/build_audio.py --verify >"$LOGS/audio_verify.log" 2>&1
		VERIFY_EXIT=$?
		grep -E "^(AUDIO VERIFY|TOOLCHAIN DIFFERS|CONTENT DIFFERS|SHIPPED FILE)" "$LOGS/audio_verify.log" | head -n 40
		[ "$VERIFY_EXIT" = "0" ] || fail "audio regeneration is not bit-exact" "$LOGS/audio_verify.log"
		run_limited 300 python3 tools/audio/build_audio.py --budget >"$LOGS/audio_budget.log" 2>&1 \
			|| fail "the audio is over its budget (decision 8)" "$LOGS/audio_budget.log"
		grep -E "imported size|registered SFX" "$LOGS/audio_budget.log"
	fi
fi

TEST_ARGS=(-- --no-user-settings --no-audio)
TIERS="tests"
if [ "$SLOW" = "1" ]; then
	TEST_ARGS+=(--slow)
	TIERS="$TIERS, slow suites"
fi
if [ "$GATE" = "1" ]; then
	TEST_ARGS+=(--gate)
	TIERS="$TIERS, gate suites"
fi
step "$TIERS"
run_limited 3600 "$GD" --headless --path . --fixed-fps 60 res://tests/run_tests.tscn "${TEST_ARGS[@]}" \
	>"$LOGS/tests.log" 2>&1
TEST_EXIT=$?
grep -E "^RESULT:|^FAIL|^TIMES:" "$LOGS/tests.log" | head -n 60
[ "$TEST_EXIT" = "0" ] || fail "tests exited with $TEST_EXIT" "$LOGS/tests.log"
grep -q "^RESULT: .* 0 failures" "$LOGS/tests.log" || fail "no passing RESULT line" "$LOGS/tests.log"
# The suite times (decision 34: default under 75 s, slow under 8 minutes, gate under 50 minutes),
# kept for the wave merge's record.
TIMES_LINE="$(grep -m1 "^TIMES:" "$LOGS/tests.log" || true)"
if [ -n "$TIMES_LINE" ]; then
	echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $(git rev-parse --short HEAD 2>/dev/null || echo '?') $TIMES_LINE" \
		>>"$LOGS/suite_times.txt"
	DEFAULT_S="$(echo "$TIMES_LINE" | sed -E 's/^TIMES: default ([0-9.]+) s.*/\1/')"
	if awk "BEGIN { exit !($DEFAULT_S > 75) }" 2>/dev/null; then
		echo "WARNING: the default suite took ${DEFAULT_S} s, over its 75 s budget (decision 34)"
	fi
fi

if [ "$AUTOPLAY" != "0" ]; then
	step "autoplay ${AUTOPLAY} s"
	run_limited 1200 "$GD" --headless --path . --fixed-fps 60 -- --no-user-settings \
		"--autoplay=$AUTOPLAY" >"$LOGS/autoplay.log" 2>&1
	AUTO_EXIT=$?
	RESULT_LINE="$(grep -m1 "^AUTOPILOT_RESULT " "$LOGS/autoplay.log" || true)"
	echo "${RESULT_LINE:-no AUTOPILOT_RESULT line}" | cut -c1-400
	[ "$AUTO_EXIT" = "0" ] || fail "autoplay exited with $AUTO_EXIT" "$LOGS/autoplay.log"
	[ -n "$RESULT_LINE" ] || fail "autoplay printed no AUTOPILOT_RESULT" "$LOGS/autoplay.log"
	echo "$RESULT_LINE" | grep -q '"errors":0[,}]' || fail "autoplay logged errors" "$LOGS/autoplay.log"
	# Coverage: the seeded sandbox soak must keep exercising the breakable, the debris pool and
	# loot. (After P04 added the wolf pack it silently stopped breaking the fence.)
	if [ "$AUTOPLAY" -ge 120 ] 2>/dev/null; then
		for key in fence_breaks max_debris loot_awards; do
			value="$(echo "$RESULT_LINE" | grep -o "\"$key\":[0-9]*" | head -n 1 | cut -d: -f2)"
			[ "${value:-0}" -ge 1 ] || fail "the soak no longer covers the breakable path (${key}: ${value:-missing})" "$LOGS/autoplay.log"
		done
	fi
fi

echo "CHECK PASSED"
