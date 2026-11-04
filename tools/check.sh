#!/usr/bin/env bash
# The definition-of-done sequence of the M2-M5 plan (§1.1), failing on the first bad step:
#   1. import   2. build scenes (only with --only=... or --build)   3. import again
#   4. full test suite (plus the slow suites with --slow)   5. 120 s autoplay with 0 errors
#
# Usage: tools/check.sh [--slow] [--only=<builder>[,<builder>]] [--build] [--autoplay=SECONDS]
#   --only=...    rebuild the named scene builders (before P04's builder split: all of them)
#   --build       rebuild every scene
#   --autoplay=S  soak length in seconds (default 120; 0 skips the soak)
# Every Godot call goes through tools/gd.sh (this worktree's own user:// folder). Logs of the
# last run are kept in .userdata/check/.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GD="$ROOT/tools/gd.sh"
LOGS="${GB_USERDATA:-$ROOT/.userdata}/check"
mkdir -p "$LOGS"

SLOW=0
BUILD=""
AUTOPLAY=120
for arg in "$@"; do
	case "$arg" in
		--slow) SLOW=1 ;;
		--only=*) BUILD="$arg" ;;
		--build) BUILD="all" ;;
		--autoplay=*) AUTOPLAY="${arg#--autoplay=}" ;;
		-h|--help) sed -n '2,13p' "$0"; exit 0 ;;
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

# A script that fails to parse shows up in the import log; catch it before running anything.
check_import_log() {
	if grep -E "SCRIPT ERROR|Parse Error|Failed to load script|Compile Error" "$1" >/dev/null; then
		fail "script errors during import (see $1)" "$1"
	fi
}

step "import"
run_limited 600 "$GD" --headless --path . --import >"$LOGS/import1.log" 2>&1 \
	|| fail "import exited with $?" "$LOGS/import1.log"

if [ -n "$BUILD" ]; then
	step "build scenes (${BUILD})"
	BUILD_ARGS=()
	if [ "$BUILD" != "all" ]; then
		BUILD_ARGS=(-- "$BUILD")
	fi
	run_limited 900 "$GD" --headless --path . res://tools/build_scenes.tscn ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"} \
		>"$LOGS/build.log" 2>&1 || fail "scene build exited with $?" "$LOGS/build.log"
	if grep -E "SCRIPT ERROR|^ERROR" "$LOGS/build.log" >/dev/null; then
		fail "errors while building scenes" "$LOGS/build.log"
	fi
fi

step "import (register new classes and resources)"
run_limited 600 "$GD" --headless --path . --import >"$LOGS/import2.log" 2>&1 \
	|| fail "second import exited with $?" "$LOGS/import2.log"
check_import_log "$LOGS/import2.log"

TEST_ARGS=(-- --no-user-settings)
if [ "$SLOW" = "1" ]; then
	TEST_ARGS+=(--slow)
fi
if [ "$SLOW" = "1" ]; then step "tests (with the slow suites)"; else step "tests"; fi
run_limited 1800 "$GD" --headless --path . --fixed-fps 60 res://tests/run_tests.tscn "${TEST_ARGS[@]}" \
	>"$LOGS/tests.log" 2>&1
TEST_EXIT=$?
grep -E "^RESULT:|^FAIL" "$LOGS/tests.log" | head -n 60
[ "$TEST_EXIT" = "0" ] || fail "tests exited with $TEST_EXIT" "$LOGS/tests.log"
grep -q "^RESULT: .* 0 failures" "$LOGS/tests.log" || fail "no passing RESULT line" "$LOGS/tests.log"

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
fi

echo "CHECK PASSED"
