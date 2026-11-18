#!/usr/bin/env bash
# Creates the giant pipeline's shared virtual environment and cache, outside every worktree:
#   GIANT_VENV  (default $HOME/.cache/giantborn/giant-venv): Python 3.13 with bpy 5.3.0, numpy,
#               scipy, Pillow and OpenEXR at the pins of tools/giant/requirements.txt (about 1.2 GB:
#               bpy alone is about 930 MB installed); never inside a worktree
#   GIANT_CACHE (default $HOME/.cache/giantborn/giant-cache): the content-addressed bake cache
#               and the audited CC0 data wheel (tools/giant/fetch_mpfb2.py)
#
#   tools/giant/setup_venv.sh [--python=python3.13] [--force]
#
# An existing venv whose `pip freeze` already equals the pins is kept (exit 0); --force rebuilds it.
# Needs Python 3.13 and the package index (or pip's cache) once.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="${GIANT_VENV:-$HOME/.cache/giantborn/giant-venv}"
CACHE="${GIANT_CACHE:-$HOME/.cache/giantborn/giant-cache}"
PY=python3.13
FORCE=0
for arg in "$@"; do
	case "$arg" in
		--python=*) PY="${arg#--python=}" ;;
		--force) FORCE=1 ;;
		-h|--help) sed -n '2,14p' "$0"; exit 0 ;;
		*) echo "setup_venv.sh: unknown option '$arg'" >&2; exit 2 ;;
	esac
done
case "$VENV" in
	"$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || echo /nonexistent)"/*)
		echo "setup_venv.sh: GIANT_VENV ($VENV) is inside the repository; keep it outside every worktree" >&2
		exit 2 ;;
esac
mkdir -p "$CACHE"
pins() { grep -E '^[A-Za-z]' "$HERE/requirements.txt" | sed -E 's/ .*//' | tr 'A-Z_' 'a-z-' | sort; }
if [ "$FORCE" = "0" ] && [ -x "$VENV/bin/python" ]; then
	have="$("$VENV/bin/pip" freeze 2>/dev/null | grep -vE '^(pip|setuptools|wheel)==' | tr 'A-Z_' 'a-z-' | sort)"
	if [ "$have" = "$(pins)" ]; then
		echo "setup_venv.sh: $VENV already holds the pinned toolchain"
		exit 0
	fi
	echo "setup_venv.sh: $VENV differs from the pins; rebuilding it"
fi
rm -rf "$VENV"
"$PY" -m venv "$VENV"
"$VENV/bin/python" -m pip install --upgrade --quiet pip
"$VENV/bin/pip" install --require-hashes --no-deps --only-binary=:all: -r "$HERE/requirements.txt"
"$VENV/bin/python" -c "import bpy, numpy, scipy, PIL, OpenEXR, sys; print('setup_venv.sh: Python', sys.version.split()[0], 'bpy', bpy.app.version_string, 'numpy', numpy.__version__, 'scipy', scipy.__version__, 'Pillow', PIL.__version__, 'OpenEXR', OpenEXR.__version__)"
echo "setup_venv.sh: GIANT_VENV=$VENV GIANT_CACHE=$CACHE"
