"""The audio manifest (assets/audio/manifest.json): one entry per generated file.

An entry records where the file came from and what it is, so a test can check it and
build_audio.py --verify can regenerate it to the same bytes:

    family, generator (module), function, seed, params_hash (sha256 of the canonical JSON of the
    parameters), kind (sfx | loop | oneshot), scope (m6 | world), frames, rate, channels,
    seconds, loop, bpm, beats, beats_per_bar, frame (the music frame name), quality (Ogg -q:a),
    master_hash (sha256 of the master: the 16-bit WAV of an SFX, the float WAV of a music or
    ambience render), file_hash (sha256 of the shipped file), size (bytes of the shipped file)

and the top level records the reference toolchain (Python, numpy, ffmpeg, libvorbis). The file is
written with sorted keys and a fixed layout, so regenerating the same sounds rewrites it
byte-identically.
"""

from __future__ import annotations

import hashlib
import json
import platform
from pathlib import Path

SCHEMA_VERSION = 1
GENERATED_BY = "tools/audio/build_audio.py"
REL_PATH = "assets/audio/manifest.json"


def params_hash(params: dict) -> str:
    """sha256 of the parameters' canonical JSON (sorted keys, no spaces)."""
    text = json.dumps(params, sort_keys=True, separators=(",", ":"), default=_jsonable)
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _jsonable(value):
    if hasattr(value, "tolist"):
        return value.tolist()
    raise TypeError("parameter value %r is not JSON-serialisable" % (value,))


def toolchain(numpy_version: str, ffmpeg_version: str, libvorbis_version: str) -> dict:
    return {"python": platform.python_version(), "numpy": numpy_version,
            "ffmpeg": ffmpeg_version, "libvorbis": libvorbis_version}


def load(root: Path) -> dict:
    """The manifest under `root` (the repository), or an empty one."""
    path = Path(root) / REL_PATH
    if not path.exists():
        return {"schema_version": SCHEMA_VERSION, "generated_by": GENERATED_BY, "tools": {}, "files": {}}
    return json.loads(path.read_text(encoding="utf-8"))


def dumps(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, indent=1, ensure_ascii=True) + "\n"


def save(root: Path, doc: dict) -> Path:
    path = Path(root) / REL_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dumps(doc), encoding="utf-8")
    return path


def compare(expected: dict, actual: dict) -> dict:
    """Differences between two manifests: {"toolchain": [...], "content": [...]}. A toolchain
    difference is reported apart from a content difference, because the same generators give
    other bytes under another Python, numpy, ffmpeg or libvorbis (decision 4)."""
    out = {"toolchain": [], "content": []}
    et = expected.get("tools", {})
    at = actual.get("tools", {})
    for key in sorted(set(et) | set(at)):
        if et.get(key) != at.get(key):
            out["toolchain"].append("%s: manifest %s, here %s" % (key, et.get(key), at.get(key)))
    ef = expected.get("files", {})
    af = actual.get("files", {})
    for path in sorted(set(ef) | set(af)):
        if path not in af:
            out["content"].append("%s: in the manifest but not generated" % path)
            continue
        if path not in ef:
            out["content"].append("%s: generated but not in the manifest" % path)
            continue
        for key in ("master_hash", "file_hash", "frames", "rate", "channels", "params_hash", "seed"):
            if ef[path].get(key) != af[path].get(key):
                out["content"].append("%s: %s differs (manifest %s, regenerated %s)" % (
                    path, key, _short(ef[path].get(key)), _short(af[path].get(key))))
    return out


def _short(value) -> str:
    text = str(value)
    return text[:16] + "..." if len(text) > 19 else text
