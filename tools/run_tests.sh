#!/usr/bin/env bash
# Runs the automated test suites headless. Usage: tools/run_tests.sh [--filter=unit] [--slow]
# Requires Godot 4.6.3 on PATH as "godot" (or set GODOT=/path/to/godot). Uses tools/gd.sh, so
# user:// is this worktree's .userdata/ folder.
set -euo pipefail
cd "$(dirname "$0")/.."
tools/gd.sh --headless --path . --import >/dev/null 2>&1 || true
tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings "$@"
