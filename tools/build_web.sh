#!/usr/bin/env bash
# Builds the browser version of the game and prepares the files that the launcher page
# (web/launcher.html) loads when it is published as a claude.ai Artifact.
#
# Usage:  tools/build_web.sh [--preset=NAME] [--out=DIR] [--budget-mb=N] [--parts=N]
#                             [path-to-godot-4.6.3]
#   --preset=Web          the release (default): no test content (scenes/test/, assets/test_world/,
#                         data/test/ are excluded; P22), into builds/web/
#   --preset="Web (test)" the same build with the test levels and records, for the web checks that
#                         need them (P24a's stream check), into builds/web_test/
#   --out=DIR             the output folder (default per preset, above; builds/web_parts<N> with
#                         --parts)
#   --budget-mb=N         the shipped index.pck budget in MB (default: the milestone's, from the
#                         project's version: 7.5 MB up to M6, 21 MB at M7, 23 MB after; decision 8)
#   --parts=N             ship the packed pck in exactly N parts (P23: the forced two-part build of
#                         the M6 acceptance, --parts=2); without it the pck ships in as many parts
#                         of at most 15 MB as it needs, one part while it fits
# Needs the Godot 4.6.3 export templates (web_nothreads_release.zip), gzip, base64 and sed; python3
# for the pck content check. Run it without XDG_DATA_HOME (the templates live in the default Godot
# data folder).
#
# The Artifact host serves .js, .wasm, text and image files, but not .pck or archives, and caps
# binary files at 15 MB and text files at 16 MB. The engine (index.wasm) is about 36 MB, so the
# engine and the game data (index.pck) ship gzipped and base64-encoded as .txt files, and the
# launcher unpacks them in the browser.
#
# Output in DIR:
#   index.js, index.audio*.worklet.js     engine loader and audio helpers (served as is)
#   index.wasm.gz.b64.txt                 the engine, packed
#   index.pck.gz.b64.txt                  the game data, packed (one part), or
#   index.pck.gz.b64.<n>.txt              its parts n = 1, 2, ... of at most 15 MB each (P23: the
#                                         launcher downloads them in order with one progress meter
#                                         and joins the text before unpacking it)
#   poster.jpg                            still shown before Play
#   play.html                             the launcher wrapped like the Artifact host wraps it,
#                                         for testing with any static web server (play.html?args=a,b
#                                         passes engine arguments: web/launcher.html)
# The release build (--preset=Web into builds/web) also keeps the BUILD byte counts of
# web/launcher.html in step with itself; other builds only write them into their own play.html.
# The report: index.pck raw, gzipped and as shipped against the budget (a WARNING over it) and its
# parts, the audio share of the pck (P23: AUDIO_SHARE), the pck's test content (the release must
# have none: an error), and for the release the data it ships validated without data/test
# (tools/release_data_check.gd; a WARNING with the offending records).
set -euo pipefail
cd "$(dirname "$0")/.."

PRESET="Web"
OUT=""
BUDGET_MB=""
PARTS=""
# The largest part of the packed pck (P23): under the host's 15 MB cap for binary files and its
# 16 MB cap for text.
PART_MAX=15000000
GODOT="${GODOT:-godot}"
for arg in "$@"; do
	case "$arg" in
		--preset=*) PRESET="${arg#--preset=}" ;;
		--out=*) OUT="${arg#--out=}" ;;
		--budget-mb=*) BUDGET_MB="${arg#--budget-mb=}" ;;
		--parts=*) PARTS="${arg#--parts=}" ;;
		-h|--help) sed -n '2,40p' "$0"; exit 0 ;;
		--*) echo "build_web.sh: unknown option '$arg'" >&2; exit 2 ;;
		*) GODOT="$arg" ;;
	esac
done
case "$PRESET" in
	"Web") DEFAULT_OUT=builds/web ;;
	"Web (test)") DEFAULT_OUT=builds/web_test ;;
	*) echo "build_web.sh: unknown preset '$PRESET' (Web or \"Web (test)\")" >&2; exit 2 ;;
esac
if [ -n "$PARTS" ]; then
	case "$PARTS" in
		''|*[!0-9]*) echo "build_web.sh: --parts wants a whole number of parts" >&2; exit 2 ;;
	esac
	if [ "$PARTS" -lt 1 ]; then echo "build_web.sh: --parts wants at least 1" >&2; exit 2; fi
	DEFAULT_OUT="builds/web_parts$PARTS"
fi
OUT="${OUT:-$DEFAULT_OUT}"
RELEASE=0
if [ "$PRESET" = "Web" ] && [ "$OUT" = "builds/web" ] && [ -z "$PARTS" ]; then RELEASE=1; fi

# The milestone's budget for the shipped index.pck (decision 8), from config/version (0.7.0-m7: 21 MB).
if [ -z "$BUDGET_MB" ]; then
	MILESTONE="$(sed -n 's/^config\/version="[^"]*-m\([0-9]*\)"$/\1/p' project.godot | head -n 1)"
	MILESTONE="${MILESTONE:-6}"
	if [ "$MILESTONE" -le 6 ]; then BUDGET_MB=7.5
	elif [ "$MILESTONE" -le 7 ]; then BUDGET_MB=21
	else BUDGET_MB=23
	fi
fi

rm -rf "$OUT"
mkdir -p "$OUT"
# Godot must never import a build (P23): an earlier build's poster and icons would otherwise be
# imported as textures and packed into the next build's pck. builds/ is ignored as a whole; an
# output folder elsewhere gets its own .gdignore.
case "$OUT" in
	builds/*) : > builds/.gdignore ;;
	*) : > "$OUT/.gdignore" ;;
esac
"$GODOT" --headless --path . --export-release "$PRESET" "$OUT/index.html"
for f in index.wasm index.pck; do
	gzip -9 -n -c "$OUT/$f" | base64 | tr -d '\n' > "$OUT/$f.gz.b64.txt"
done
# The poster: the Valley at New Game (docs/screenshots/, rendered by tools/valley_tour.gd).
cp docs/screenshots/01_hollow_start.jpg "$OUT/poster.jpg"

size() { wc -c < "$1" | tr -d ' '; }
wasm=$(size "$OUT/index.wasm")
pck=$(size "$OUT/index.pck")
wasm_packed=$(size "$OUT/index.wasm.gz.b64.txt")
pck_packed=$(size "$OUT/index.pck.gz.b64.txt")
pck_gz=$(gzip -9 -n -c "$OUT/index.pck" | wc -c | tr -d ' ')

# The multi-part pck (P23): parts of at most PART_MAX bytes (or exactly --parts), cut anywhere in
# the base64 text (the launcher joins the text before decoding it); one part keeps its plain name.
pck_parts="${PARTS:-$(( (pck_packed + PART_MAX - 1) / PART_MAX ))}"
if [ "$pck_parts" -gt 1 ]; then
	per=$(( (pck_packed + pck_parts - 1) / pck_parts ))
	for i in $(seq 1 "$pck_parts"); do
		dd if="$OUT/index.pck.gz.b64.txt" of="$OUT/index.pck.gz.b64.$i.txt" bs=1M status=none \
			iflag=skip_bytes,count_bytes skip=$(( (i - 1) * per )) count="$per"
		part=$(size "$OUT/index.pck.gz.b64.$i.txt")
		if [ "$part" -le 0 ] || [ "$part" -gt "$PART_MAX" ]; then
			echo "build_web.sh: part $i of $pck_parts holds $part bytes (1 to $PART_MAX wanted)" >&2
			exit 1
		fi
	done
	joined=$(cat $(for i in $(seq 1 "$pck_parts"); do echo "$OUT/index.pck.gz.b64.$i.txt"; done) | cksum)
	if [ "$joined" != "$(cksum < "$OUT/index.pck.gz.b64.txt")" ]; then
		echo "build_web.sh: the pck's parts do not join back into the packed pck" >&2
		exit 1
	fi
	rm "$OUT/index.pck.gz.b64.txt"
fi

# The launcher's byte counts (used only for the progress bar) and the pck's part count.
build_line="{ wasm: $wasm, pck: $pck, wasmPacked: $wasm_packed, pckPacked: $pck_packed, pckParts: $pck_parts }"
sed -E "s|^(  const BUILD = ).*(; // set by tools/build_web.sh)$|\1$build_line\2|" \
	web/launcher.html > "$OUT/launcher.tmp"
if ! grep -qF "const BUILD = $build_line;" "$OUT/launcher.tmp"; then
	echo "build_web.sh: could not update the BUILD line in web/launcher.html" >&2
	exit 1
fi
if [ "$RELEASE" = "1" ]; then
	cp "$OUT/launcher.tmp" web/launcher.html
fi

{
	printf '<!doctype html><html><head><meta charset="utf-8">'
	printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
	printf '<style>body{margin:0}img{max-width:100%%}[hidden]{display:none!important}</style></head><body>\n'
	cat "$OUT/launcher.tmp"
	printf '\n</body></html>\n'
} > "$OUT/play.html"
rm -f "$OUT/launcher.tmp"

text_limit=16000000
for f in "$OUT"/index.wasm.gz.b64.txt "$OUT"/index.pck.gz.b64*.txt "$OUT"/index.js; do
	if [ "$(size "$f")" -gt "$text_limit" ]; then
		echo "build_web.sh: $(basename "$f") is over the 16 MB per-file limit for Artifact hosting" >&2
		exit 1
	fi
done

mb() { awk "BEGIN { printf \"%.2f\", $1 / 1048576 }"; }
echo "Web build ($PRESET) ready in $OUT: index.wasm $wasm bytes (packed $wasm_packed), index.pck $pck bytes (packed $pck_packed)."
echo "PCK_SIZE preset=\"$PRESET\" raw=$pck gzip=$pck_gz shipped=$pck_packed shipped_mb=$(mb "$pck_packed") budget_mb=$BUDGET_MB parts=$pck_parts"
if [ "$pck_parts" -gt 1 ]; then
	echo "index.pck ships in $pck_parts parts: $(for i in $(seq 1 "$pck_parts"); do printf '%s ' "index.pck.gz.b64.$i.txt ($(size "$OUT/index.pck.gz.b64.$i.txt") bytes)"; done)"
fi
# The audio's share of the pck (P23; decision 8: audio at most 4.0 MB imported at M6).
if command -v python3 >/dev/null 2>&1; then
	share_line="$(python3 tools/pck_files.py --audio-share "$OUT/index.pck")"
	echo "$share_line"
	audio_bytes="$(echo "$share_line" | sed -E 's/.*audio_bytes=([0-9]+).*/\1/')"
	echo "audio: $(mb "$audio_bytes") MB of the $(mb "$pck") MB pck ($(awk "BEGIN { printf \"%.0f\", 100 * $audio_bytes / $pck }") %)"
fi
if awk "BEGIN { exit !($pck_packed > $BUDGET_MB * 1048576) }"; then
	echo "WARNING: the shipped index.pck ($(mb "$pck_packed") MB) is over the milestone's budget of $BUDGET_MB MB (decision 8)"
fi

# Test content in the pck: none in the release (an error), counted for the Web (test) build.
if command -v python3 >/dev/null 2>&1; then
	if [ "$PRESET" = "Web" ]; then
		python3 tools/pck_files.py --check-no-test "$OUT/index.pck" \
			|| { echo "build_web.sh: the Web release packs test content" >&2; exit 1; }
	else
		echo "test files packed: $(python3 tools/pck_files.py "$OUT/index.pck" | grep -cE '^(scenes/test|assets/test_world|data/test)/' || true)"
	fi
else
	echo "build_web.sh: python3 is missing: the pck content check was skipped"
fi

# The release's data without data/test, through the game's own validator.
if [ "$PRESET" = "Web" ]; then
	check_line="$("$GODOT" --headless --path . -s res://tools/release_data_check.gd 2>/dev/null | grep -m1 '^RELEASE_DATA_CHECK ' || true)"
	if echo "$check_line" | grep -q '"errors":\[\]'; then
		echo "release data: every record validates without data/test"
	else
		echo "WARNING: the release's data does not validate without data/test - the game would stop at its data error screen:"
		echo "  ${check_line:-no RELEASE_DATA_CHECK line}" | cut -c1-2000
	fi
fi
echo "Test locally: serve $OUT with any static web server and open play.html (play.html?args=--mode=valley,--new-game passes arguments)."
