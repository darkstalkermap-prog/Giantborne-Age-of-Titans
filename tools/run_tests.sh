#!/usr/bin/env bash
# Runs the automated test suites headless. Usage: tools/run_tests.sh [--filter=unit]
# Requires Godot 4.6.3 on PATH as "godot" (or set GODOT=/path/to/godot).
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --import --path . >/dev/null 2>&1 || true
"$GODOT" --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings "$@"
