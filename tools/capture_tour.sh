#!/usr/bin/env bash
# Scripted screenshot tour (third person, first person, fence, Footfall, lock-on, block, debug panel).
# Needs a display; on a headless Linux box it uses Xvfb. Usage: tools/capture_tour.sh [output_dir]
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="${1:-$PWD/builds/captures}"
mkdir -p "$OUT"
RUN=("$GODOT" --path . --fixed-fps 60 --resolution 1280x720 -- --no-user-settings --scenario=capture "--capture-dir=$OUT")
if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null; then
  xvfb-run -a -s "-screen 0 1280x720x24" "${RUN[@]}"
else
  "${RUN[@]}"
fi
echo "Screenshots written to $OUT"
