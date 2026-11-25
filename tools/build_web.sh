#!/usr/bin/env bash
# Builds the browser version of the game and prepares the files that the launcher page
# (web/launcher.html) loads when it is published as a claude.ai Artifact.
#
# Usage:  tools/build_web.sh [--preset=NAME] [--out=DIR] [--budget-mb=N] [--giant-share-mb=N]
#                             [--people-share-mb=N] [--version=V] [--parts=N] [--keep-export-cache]
#                             [path-to-godot-4.6.3]
#         tools/build_web.sh --check-size=DIR [--budget-mb=N] [--giant-share-mb=N]
#                             [--people-share-mb=N] [--version=V] [--parts=N]
#   --preset=Web          the release (default): no test content (scenes/test/, assets/test_world/,
#                         data/test/ are excluded; P22), into builds/web/
#   --preset="Web (test)" the same build with the test levels and records, for the web checks that
#                         need them (P24a's stream check), into builds/web_test/
#   --out=DIR             the output folder (default per preset, above; builds/web_parts<N> with
#                         --parts)
#   --budget-mb=N         the shipped index.pck budget in MB (default: the milestone's, from the
#                         project's version: 7.5 MB up to M6, 21 MB at M7, 23 MB at M8 and M9, 26 MB
#                         at M10 and M11, 32 MB at M12 and 44 MB from M13 on; decision 8, the owner's
#                         answer 1 of plan M10 §0.6 and plan M11 §2.12)
#   --version=V           P45: judge the build as version V (0.10.0-m10) instead of the project's
#                         config/version - only the milestone's budget reads it (tests use it)
#   --giant-share-mb=N    P41 (plan M10 §2.12): the most the realistic giant's files may add to the
#                         shipped pack (the GIANT_SHARE line, tools/pck_files.py --giant-share);
#                         default the budget less 18.4 MB: 4.6 MB at the 23 MB budget and 7.6 MB
#                         at M10's 26 MB, where the Web pack also holds the 1024 px maps (tex_hi/);
#                         13.6 MB at 32 MB and, from M13, the budget less 18.4 MB and less the
#                         people's share (13.6 MB at 44 MB)
#   --people-share-mb=N   P49 (plan M11 §2.12): the most the realistic people and creatures may add
#                         (the PEOPLE_SHARE line, tools/pck_files.py --people-share: assets/people/,
#                         assets/creatures/, their shaders and scenes); the line is printed for every
#                         build (0 until the files exist) and capped at 12.0 MB from M13 on - before
#                         that only when this option gives a cap
#   --keep-export-cache   P49: do not empty .godot/exported/ before the export. By default the
#                         build exports from an empty conversion cache, so that every text scene is
#                         converted by this run (see "Reproducible exports" below)
#   --parts=N             ship the packed pck in exactly N parts (P23: the forced two-part build of
#                         the M6 acceptance, --parts=2); without it the pck ships in as many parts
#                         of at most 15 MB as it needs, one part while it fits
#   --print-caps          export nothing and read no pack: print one CAPS line - the budget and the
#                         two shares' caps this build would be judged by - for every --version=
#                         given, in order (tests use it)
#   --check-size=DIR      export nothing and write nothing: pack DIR/index.pck (an earlier build's)
#                         in memory and judge it as a build would - the PCK_SIZE line, the part cap
#                         and the budget, with the same exit codes (M7 polish; tests use it)
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
#                                         and decodes and inflates them as they arrive: P49)
#   index.pck.sha256                      the pack's SHA-256 (the PCK_SHA256 line; P49: two exports
#                                         of one commit must print the same one)
#   poster.jpg                            still shown before Play
#   play.html                             the launcher wrapped like the Artifact host wraps it,
#                                         for testing with any static web server (play.html?args=a,b
#                                         passes engine arguments: web/launcher.html)
# The release build (--preset=Web into builds/web) also keeps the BUILD byte counts of
# web/launcher.html in step with itself; other builds only write them into their own play.html.
# The report: index.pck raw, gzipped and as shipped against the budget and its parts, the audio
# share of the pck (P23: AUDIO_SHARE), the giant's share (P41: GIANT_SHARE, failing over
# --giant-share-mb), the pck's test content (the release must have none: an error), and for the
# release the data it ships validated without data/test (tools/release_data_check.gd; a WARNING
# with the offending records).
# Reproducible exports (P49; the 0.10.0-m10 release's finding): the engine converts every text scene
# and resource to binary for the pack and keeps the conversions in .godot/exported/ (not in git);
# a scene file without node ids got random ones at each conversion, so two checkouts packed
# different bytes. The scene files now carry ids made from each node's path (tools/scene_kit.gd,
# stable_unique_ids), this script empties .godot/exported/ first, and the imported glTF scenes -
# whose node ids the importer draws at random at every import - are given stable ones before the
# export (tools/normalize_imports.gd, the NORMALIZE_IMPORTS line). A pack then depends on the
# commit alone: the PCK_SHA256 line is the same in every checkout.
# tests/slow/test_export_reproducible.gd converts scenes twice and normalizes an import;
# docs/PERFORMANCE.md has the two-checkout record.
# Exit codes: 0 built; 1 failed - the export, a part over 15 MB, a packed file over the host's
# 16 MB, the release's test content, or (M7 polish; plan §6.6) the shipped index.pck over the
# milestone's budget (--budget-mb=N overrides it), which fails after the PCK_SIZE line and the reason
# and before web/launcher.html is touched, or (P41) the giant's share over --giant-share-mb (also
# before the launcher is touched); 2 for a usage error.
set -euo pipefail
cd "$(dirname "$0")/.."

PRESET="Web"
OUT=""
BUDGET_MB=""
GIANT_SHARE_MB=""
PEOPLE_SHARE_MB=""
KEEP_CACHE=0
PRINT_CAPS=0
VERSION=""
VERSIONS=""
PARTS=""
CHECK_SIZE=""
# The largest part of the packed pck (P23): under the host's 15 MB cap for binary files and its
# 16 MB cap for text.
PART_MAX=15000000
GODOT="${GODOT:-godot}"
for arg in "$@"; do
	case "$arg" in
		--preset=*) PRESET="${arg#--preset=}" ;;
		--out=*) OUT="${arg#--out=}" ;;
		--budget-mb=*) BUDGET_MB="${arg#--budget-mb=}" ;;
		--giant-share-mb=*) GIANT_SHARE_MB="${arg#--giant-share-mb=}" ;;
		--people-share-mb=*) PEOPLE_SHARE_MB="${arg#--people-share-mb=}" ;;
		--keep-export-cache) KEEP_CACHE=1 ;;
		--print-caps) PRINT_CAPS=1 ;;
		--version=*) VERSION="${arg#--version=}" ;;
		--parts=*) PARTS="${arg#--parts=}" ;;
		--check-size=*) CHECK_SIZE="${arg#--check-size=}" ;;
		-h|--help) sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d'; exit 0 ;;
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

# resolve_caps: sets MILESTONE, BUDGET_MB, GIANT_SHARE_MB and PEOPLE_SHARE_MB for VERSION (or the project's
# version) from the options given (ARG_BUDGET_MB, ARG_GIANT_SHARE_MB, ARG_PEOPLE_SHARE_MB); exits 2 on a usage error.
resolve_caps() {
	BUDGET_MB="$ARG_BUDGET_MB"
	GIANT_SHARE_MB="$ARG_GIANT_SHARE_MB"
	PEOPLE_SHARE_MB="$ARG_PEOPLE_SHARE_MB"
	# The milestone's budget for the shipped index.pck (decision 8), from config/version (0.7.0-m7: 21 MB)
	# or --version. P45 (plan M10 §0.6, the owner's answer 1): 26 MB from -m10 on, still in parts of at
	# most 15 MB. P49 (plan M11 §2.12): 26 MB at -m11, 32 MB at -m12, 44 MB at -m13; A1b: 46 MB at -m14; B1: 50 MB
	# at -m15; C1: 56 MB from -m16 on.
	if [ -n "$VERSION" ]; then
		MILESTONE="$(printf '%s\n' "$VERSION" | sed -n 's/^.*-m\([0-9][0-9]*\)$/\1/p')"
		if [ -z "$MILESTONE" ]; then
			echo "build_web.sh: --version wants a version that ends in -m<milestone> (got '$VERSION')" >&2
			exit 2
		fi
	else
		MILESTONE="$(sed -n 's/^config\/version="[^"]*-m\([0-9]*\)"$/\1/p' project.godot | head -n 1)"
	fi
	MILESTONE="${MILESTONE:-6}"
	if [ -z "$BUDGET_MB" ]; then
		# The current milestone's default stays the LAST one assigned in this file: the giant pipeline's
		# estimate (tools/giant/build_giant.py, web_budget_mib) reads the last default it finds here. The
		# package that sets the version to -m12 (and later -m13) moves that milestone's branch to the end
		# (P58, the 0.12.0-m12 release: -m12's 32 MB was the last; P66, the 0.13.0-m13 release: -m13's 44 MB was
		# the last, and -m12's branch says "-eq 12" so that the giant pipeline still finds its own 32; A1b, the
		# expansion's working version 0.14.0-m14: the owner raised the download cap to 46 MB, and -m13's branch says
		# "-eq 13"; B1, 0.15.0-m15: the owner's standing permission to raise the cap as the expansion needs - 50 MB
		# from -m15 was the last, and -m14's branch says "-eq 14"; C1, 0.16.0-m16: 56 MB from -m16 is the last - the
		# land beyond the rim's chunks and the rimkin - and -m15's branch says "-eq 15").
		if [ "$MILESTONE" -le 6 ]; then BUDGET_MB=7.5
		elif [ "$MILESTONE" -le 7 ]; then BUDGET_MB=21
		elif [ "$MILESTONE" -le 9 ]; then BUDGET_MB=23
		elif [ "$MILESTONE" -le 11 ]; then BUDGET_MB=26
		elif [ "$MILESTONE" -eq 12 ]; then BUDGET_MB=32
		elif [ "$MILESTONE" -eq 13 ]; then BUDGET_MB=44
		elif [ "$MILESTONE" -eq 14 ]; then BUDGET_MB=46
		elif [ "$MILESTONE" -eq 15 ]; then BUDGET_MB=50
		else BUDGET_MB=56
		fi
	fi
	case "$BUDGET_MB" in
		''|.|*[!0-9.]*|*.*.*) echo "build_web.sh: --budget-mb wants a number of MB (got '$BUDGET_MB')" >&2; exit 2 ;;
	esac
	# P49 (plan M11 §2.12): the people's share (assets/people/, assets/creatures/, their shaders and scenes).
	# Its line is printed for every build; its cap, 12.0 MB, applies from -m13 on (earlier only when
	# --people-share-mb names one). A1b (the owner's raised cap): 14.0 MB from -m14 (Stoneback, the first
	# titan), so that the giant's share stays 46 - 18.4 - 14.0 = 13.6 MB.
	PEOPLE_FROM_MILESTONE=13
	PEOPLE_SHARE_CAP_MB=12.0
	if [ "$MILESTONE" -ge 14 ]; then PEOPLE_SHARE_CAP_MB=14.0; fi
	# B3 (0.15.0-m15, the owner's allowance for the third titan): 16.0 MB from -m15 - the Rootwarden's model, clips
	# and bark took the people's and creatures' files from 13.84 to 15.26 MB.
	if [ "$MILESTONE" -ge 15 ]; then PEOPLE_SHARE_CAP_MB=16.0; fi
	if [ -z "$PEOPLE_SHARE_MB" ] && [ "$MILESTONE" -ge "$PEOPLE_FROM_MILESTONE" ]; then
		PEOPLE_SHARE_MB="$PEOPLE_SHARE_CAP_MB"
	fi
	case "$PEOPLE_SHARE_MB" in
		'') ;;
		.|*[!0-9.]*|*.*.*) echo "build_web.sh: --people-share-mb wants a number of MB (got '$PEOPLE_SHARE_MB')" >&2; exit 2 ;;
	esac
	# P41 (plan M10 §2.12): the giant's share of the shipped pack, 4.6 MB at the 23 MB budget; it keeps the
	# same 18.4 MB for everything else when the budget changes (P45: 7.6 MB at M10's 26 MB; P49: 13.6 MB at
	# 32 MB, and from -m13 the people's share comes off as well: 44 - 18.4 - 12.0 = 13.6 MB; at -m14
	# 46 - 18.4 - 14.0 = 13.6 MB; from -m15 the giant's share is set, below).
	OTHER_SHARE_MB=18.4
	# B1 (0.15.0-m15): the giant's share is set, not the budget's remainder - what the functional armour's meshes
	# (the giant's files) need, frugally: 14.0 MB (A5 measured 13.27; the Quarry set's modelled stone and the nasal
	# helm add about 0.3); the rest of the 50 MB is for the content to come.
	# B3 (the owner's allowance): 15.0 MB from -m15 - the Warden set's three modelled pieces took the real share to
	# 13.86 MB and the giant pipeline's conservative estimate (build_giant.py --budget) to 14.13.
	if [ -z "$GIANT_SHARE_MB" ] && [ "$MILESTONE" -ge 15 ]; then GIANT_SHARE_MB=15.0; fi
	if [ -z "$GIANT_SHARE_MB" ]; then
		PEOPLE_OFF=0
		if [ "$MILESTONE" -ge "$PEOPLE_FROM_MILESTONE" ]; then PEOPLE_OFF="${PEOPLE_SHARE_MB:-0}"; fi
		GIANT_SHARE_MB="$(awk "BEGIN { v = $BUDGET_MB - $OTHER_SHARE_MB - $PEOPLE_OFF; if (v < 0) v = 0; printf \"%.1f\", v }")"
	fi
	case "$GIANT_SHARE_MB" in
		''|.|*[!0-9.]*|*.*.*) echo "build_web.sh: --giant-share-mb wants a number of MB (got '$GIANT_SHARE_MB')" >&2; exit 2 ;;
	esac
}
# Every --version= given, in order (--print-caps reports each; a build is judged by the last).
for arg in "$@"; do
	case "$arg" in --version=*) VERSIONS="$VERSIONS ${arg#--version=}" ;; esac
done
ARG_BUDGET_MB="$BUDGET_MB"
ARG_GIANT_SHARE_MB="$GIANT_SHARE_MB"
ARG_PEOPLE_SHARE_MB="$PEOPLE_SHARE_MB"
# --print-caps: the rule alone, one CAPS line for each --version given (or the project's), nothing
# exported or read (tests).
if [ "$PRINT_CAPS" = "1" ]; then
	for VERSION in ${VERSIONS:-""}; do
		resolve_caps
		echo "CAPS budget_mb=$BUDGET_MB giant_share_mb=$GIANT_SHARE_MB people_share_mb=${PEOPLE_SHARE_MB:-none}"
	done
	exit 0
fi
resolve_caps

size() { wc -c < "$1" | tr -d ' '; }
mb() { awk "BEGIN { printf \"%.2f\", $1 / 1048576 }"; }
# The parts the packed pck ships in: --parts, else as many of at most PART_MAX bytes as it needs.
part_count() { echo "${PARTS:-$(( ($1 + PART_MAX - 1) / PART_MAX ))}"; }
# The budget (decision 8; M7 polish: plan §6.6 has the build fail over it, not warn): exits 1 with
# the reason when the shipped (packed) pck of $1 bytes is over BUDGET_MB.
check_budget() {
	if awk "BEGIN { exit !($1 > $BUDGET_MB * 1048576) }"; then
		echo "build_web.sh: FAILED: the shipped index.pck ($(mb "$1") MB) is over the milestone's budget of $BUDGET_MB MB (decision 8; --budget-mb=N overrides it)" >&2
		exit 1
	fi
	echo "index.pck as shipped: $(mb "$1") MB, within the milestone's budget of $BUDGET_MB MB"
}
# The giant's share (P41, plan M10 §2.12): prints the GIANT_SHARE line of the pck at $1 and exits 1 over
# GIANT_SHARE_MB. A pack that python3 cannot read (no python3, not a Godot pack) prints a note instead.
check_giant_share() {
	local line shipped
	if ! command -v python3 >/dev/null 2>&1; then
		echo "GIANT_SHARE: not measured (python3 is missing)"
		return 0
	fi
	if ! line="$(python3 tools/pck_files.py --giant-share "$1" 2>/dev/null)"; then
		echo "GIANT_SHARE: not measured ($1 is not a Godot pack)"
		return 0
	fi
	echo "$line cap_mb=$GIANT_SHARE_MB"
	shipped="$(echo "$line" | sed -E 's/.* shipped=([0-9]+) .*/\1/')"
	if awk "BEGIN { exit !($shipped > $GIANT_SHARE_MB * 1048576) }"; then
		echo "build_web.sh: FAILED: the giant's files add $(mb "$shipped") MB to the shipped index.pck, over its share of $GIANT_SHARE_MB MB (plan M10 §2.12; --giant-share-mb=N overrides it)" >&2
		exit 1
	fi
}
# The people's share (P49, plan M11 §2.12): prints the PEOPLE_SHARE line of the pck at $1 (0 until the
# files exist) and, where a cap applies (from -m13, or --people-share-mb), exits 1 over it.
check_people_share() {
	local line shipped
	if ! command -v python3 >/dev/null 2>&1; then
		echo "PEOPLE_SHARE: not measured (python3 is missing)"
		return 0
	fi
	if ! line="$(python3 tools/pck_files.py --people-share "$1" 2>/dev/null)"; then
		echo "PEOPLE_SHARE: not measured ($1 is not a Godot pack)"
		return 0
	fi
	echo "$line cap_mb=${PEOPLE_SHARE_MB:-none}"
	[ -n "$PEOPLE_SHARE_MB" ] || return 0
	shipped="$(echo "$line" | sed -E 's/.* shipped=([0-9]+) .*/\1/')"
	if awk "BEGIN { exit !($shipped > $PEOPLE_SHARE_MB * 1048576) }"; then
		echo "build_web.sh: FAILED: the people's and creatures' files add $(mb "$shipped") MB to the shipped index.pck, over their share of $PEOPLE_SHARE_MB MB (plan M11 §2.12; --people-share-mb=N overrides it)" >&2
		exit 1
	fi
}
# The parts' report (P49): one PCK_PARTS line - how many parts, the size of each, the largest against
# the cap - for a pack of $1 bytes in $2 parts.
report_parts() {
	local per=$(( ($1 + $2 - 1) / $2 )) last
	last=$(( $1 - per * ($2 - 1) ))
	echo "PCK_PARTS parts=$2 part_bytes=$per last_part_bytes=$last part_max=$PART_MAX"
}

# --check-size=DIR: an earlier build's index.pck judged without exporting or writing anything.
if [ -n "$CHECK_SIZE" ]; then
	if [ ! -f "$CHECK_SIZE/index.pck" ]; then
		echo "build_web.sh: --check-size: there is no $CHECK_SIZE/index.pck" >&2
		exit 2
	fi
	pck=$(size "$CHECK_SIZE/index.pck")
	pck_gz=$(gzip -9 -n -c "$CHECK_SIZE/index.pck" | wc -c | tr -d ' ')
	# base64 without line breaks is four characters for every three bytes, the last group padded.
	pck_packed=$(( (pck_gz + 2) / 3 * 4 ))
	pck_parts=$(part_count "$pck_packed")
	echo "PCK_SIZE preset=\"check-size\" raw=$pck gzip=$pck_gz shipped=$pck_packed shipped_mb=$(mb "$pck_packed") budget_mb=$BUDGET_MB parts=$pck_parts"
	per=$(( (pck_packed + pck_parts - 1) / pck_parts ))
	if [ "$per" -gt "$PART_MAX" ]; then
		echo "build_web.sh: FAILED: a part of the $pck_parts would hold $per bytes (at most $PART_MAX)" >&2
		exit 1
	fi
	report_parts "$pck_packed" "$pck_parts"
	check_budget "$pck_packed"
	check_giant_share "$CHECK_SIZE/index.pck"
	check_people_share "$CHECK_SIZE/index.pck"
	exit 0
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
# P49: export from an empty conversion cache (see "Reproducible exports" above): every text scene and
# resource is converted by this run, from files whose node ids are in git.
if [ "$KEEP_CACHE" != "1" ]; then
	rm -rf .godot/exported
fi
# P49: the imported glTF scenes get their stable node ids too (tools/normalize_imports.gd: the importer
# gives them random ones at every import, and the pack holds the imported file as it is). The import
# first, so that nothing is imported - with new random ids - by the export itself.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
norm_line="$("$GODOT" --headless --path . -s res://tools/normalize_imports.gd 2>/dev/null | grep -m1 '^NORMALIZE_IMPORTS ' || true)"
echo "${norm_line:-NORMALIZE_IMPORTS: not run (tools/normalize_imports.gd printed nothing)}"
if echo "$norm_line" | grep -qv '"failed":\[\]'; then
	echo "build_web.sh: FAILED: an imported scene could not be given its stable node ids" >&2
	exit 1
fi
"$GODOT" --headless --path . --export-release "$PRESET" "$OUT/index.html"
for f in index.wasm index.pck; do
	gzip -9 -n -c "$OUT/$f" | base64 | tr -d '\n' > "$OUT/$f.gz.b64.txt"
done
# The poster: the Valley at New Game (docs/screenshots/, rendered by tools/valley_tour.gd).
cp docs/screenshots/01_hollow_start.jpg "$OUT/poster.jpg"

wasm=$(size "$OUT/index.wasm")
pck=$(size "$OUT/index.pck")
wasm_packed=$(size "$OUT/index.wasm.gz.b64.txt")
pck_packed=$(size "$OUT/index.pck.gz.b64.txt")
pck_gz=$(gzip -9 -n -c "$OUT/index.pck" | wc -c | tr -d ' ')

# The multi-part pck (P23): parts of at most PART_MAX bytes (or exactly --parts), cut anywhere in
# the base64 text (the launcher joins the text before decoding it); one part keeps its plain name.
pck_parts=$(part_count "$pck_packed")
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

# The pack's checksum (P49): two exports of one commit must print the same one.
if command -v sha256sum >/dev/null 2>&1; then
	pck_sha="$(sha256sum "$OUT/index.pck" | cut -d' ' -f1)"
	echo "$pck_sha  index.pck" > "$OUT/index.pck.sha256"
	echo "PCK_SHA256 preset=\"$PRESET\" sha256=$pck_sha"
fi
# The pck's sizes against the budget, before anything outside the build folder is touched.
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
report_parts "$pck_packed" "$pck_parts"
check_budget "$pck_packed"
check_giant_share "$OUT/index.pck"
check_people_share "$OUT/index.pck"

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

echo "Web build ($PRESET) ready in $OUT: index.wasm $wasm bytes (packed $wasm_packed), index.pck $pck bytes (packed $pck_packed)."

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
