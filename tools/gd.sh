#!/usr/bin/env bash
# Runs Godot with this worktree's own user folder, so parallel worktrees (and tests) never
# share user:// (settings, saves, logs). On Linux, Godot puts user:// under
# $XDG_DATA_HOME/godot/app_userdata/<project name>.
#
#   tools/gd.sh --headless --path . --import
#   tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings
#
# Environment: GODOT (default "godot", the 4.6.3 binary), GB_USERDATA (default <worktree>/.userdata).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export XDG_DATA_HOME="${GB_USERDATA:-$ROOT/.userdata}"
mkdir -p "$XDG_DATA_HOME"
exec "${GODOT:-godot}" "$@"
