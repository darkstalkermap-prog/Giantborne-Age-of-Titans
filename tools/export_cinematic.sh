#!/usr/bin/env bash
# A4: renders a cutscene (the intro by default) to a video through Godot's movie maker: the game starts the cutscene
# alone in the world (--cinematic=<id>: a New Game that saves nothing), plays it to its end and quits
# (--quit-after-cinematic); --write-movie records every frame at --fixed-fps 30 (1280 x 720, the audio with it) into
# an AVI, which ffmpeg turns into an H.264 / AAC mp4. Needs xvfb-run (a display for the renderer; llvmpipe is
# enough, slowly: about a second a frame) and ffmpeg. Deterministic: the cutscene runs one tick a physics frame.
#
# The mp4 starts at the cutscene's first frame (the loading screen before it is cut: CutsceneScreen prints
# CUTSCENE_START with its frame into <out>/<id>.log).
#
# Usage: tools/export_cinematic.sh [--cutscene=intro] [--out=DIR] [--keep-avi]
#   --cutscene=ID   the cutscene record (cutscene.<ID>; default intro)
#   --out=DIR       where <ID>.mp4 (and with --keep-avi the AVI) go (default .userdata/cinematics)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CUT="intro"
OUT="${GB_USERDATA:-$ROOT/.userdata}/cinematics"
KEEP=0
for arg in "$@"; do
	case "$arg" in
		--cutscene=*) CUT="${arg#--cutscene=}" ;;
		--out=*) OUT="${arg#--out=}" ;;
		--keep-avi) KEEP=1 ;;
		-h|--help) sed -n '2,16p' "$0"; exit 0 ;;
		*) echo "export_cinematic.sh: unknown option '$arg'" >&2; exit 2 ;;
	esac
done
command -v xvfb-run >/dev/null || { echo "export_cinematic.sh: xvfb-run is missing" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "export_cinematic.sh: ffmpeg is missing" >&2; exit 1; }
mkdir -p "$OUT"
AVI="$OUT/$CUT.avi"
LOG="$OUT/$CUT.log"
xvfb-run -a -s "-screen 0 1280x720x24" "$ROOT/tools/gd.sh" --path . --rendering-driver opengl3 --fixed-fps 30 \
	--resolution 1280x720 --write-movie "$AVI" -- --no-user-settings --cinematic="$CUT" --quit-after-cinematic \
	>"$LOG" 2>&1 || { tail -n 20 "$LOG" >&2; exit 1; }
# the movie from the cutscene's first frame (the loading screen before it is cut; CutsceneScreen prints the frame)
START="$(sed -n 's/^CUTSCENE_START [^ ]* frame \([0-9]*\).*/\1/p' "$LOG" | head -n 1)"
SS="$(awk "BEGIN { printf \"%.3f\", ${START:-0} / 30.0 }")"
ffmpeg -loglevel error -y -ss "$SS" -i "$AVI" -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -c:a aac \
	-b:a 160k -movflags +faststart "$OUT/$CUT.mp4"
[ "$KEEP" = "1" ] || rm -f "$AVI"
echo "export_cinematic.sh: $OUT/$CUT.mp4"
