#!/usr/bin/env bash
# Builds the browser version of the game into builds/web/ and prepares the files that the
# launcher page (web/launcher.html) loads when it is published as a claude.ai Artifact.
#
# Usage:  tools/build_web.sh [path-to-godot-4.6.3]
# Needs the Godot 4.6.3 export templates (web_nothreads_release.zip), gzip, base64 and sed.
#
# The Artifact host serves .js, .wasm, text and image files, but not .pck or archives, and caps
# binary files at 15 MB and text files at 16 MB. The engine (index.wasm) is about 36 MB, so the
# engine and the game data (index.pck) ship gzipped and base64-encoded as .txt files, and the
# launcher unpacks them in the browser.
#
# Output in builds/web/:
#   index.js, index.audio*.worklet.js     engine loader and audio helpers (served as is)
#   index.wasm.gz.b64.txt                 the engine, packed
#   index.pck.gz.b64.txt                  the game data, packed
#   poster.jpg                            still shown before Play
#   play.html                             the launcher wrapped like the Artifact host wraps it,
#                                         for testing with any static web server
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${1:-${GODOT:-godot}}"
OUT=builds/web

rm -rf "$OUT"
mkdir -p "$OUT"
"$GODOT" --headless --path . --export-release "Web" "$OUT/index.html"
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

# Keep the launcher's byte counts (used only for the progress bar) in step with this build.
build_line="{ wasm: $wasm, pck: $pck, wasmPacked: $wasm_packed, pckPacked: $pck_packed }"
sed -E "s|^(  const BUILD = ).*(; // set by tools/build_web.sh)$|\1$build_line\2|" \
	web/launcher.html > "$OUT/launcher.tmp"
if ! grep -qF "const BUILD = $build_line;" "$OUT/launcher.tmp"; then
	echo "build_web.sh: could not update the BUILD line in web/launcher.html" >&2
	exit 1
fi
mv "$OUT/launcher.tmp" web/launcher.html

{
	printf '<!doctype html><html><head><meta charset="utf-8">'
	printf '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
	printf '<style>body{margin:0}img{max-width:100%%}[hidden]{display:none!important}</style></head><body>\n'
	cat web/launcher.html
	printf '\n</body></html>\n'
} > "$OUT/play.html"

text_limit=16000000
for f in index.wasm.gz.b64.txt index.pck.gz.b64.txt index.js; do
	if [ "$(size "$OUT/$f")" -gt "$text_limit" ]; then
		echo "build_web.sh: $f is over the 16 MB per-file limit for Artifact hosting" >&2
		exit 1
	fi
done
echo "Web build ready in $OUT: index.wasm $wasm bytes (packed $wasm_packed), index.pck $pck bytes (packed $pck_packed)."
echo "Test locally: serve $OUT with any static web server and open play.html."
