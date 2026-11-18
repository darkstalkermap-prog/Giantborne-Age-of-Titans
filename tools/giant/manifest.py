"""The giant manifest (assets/giant/manifest.json): every generated file of the giant, how it was
made and what it is, plus the giant index the scene builder writes into giant_model.tscn.

Top level (written with sorted keys and a fixed layout, so the same outputs rewrite it
byte-identically):
  schema_version, generated_by
  toolchain   Python, bpy, numpy, scipy, Pillow and OpenEXR versions and the CPU (model and a hash of
              its flags): the reference toolchain on which --verify must be bit-exact
  inputs      the sha256 of the vendored CC0 file list (mpfb2/FILES.sha256) and of every kit module
  bake        the Cycles settings, the cheap and the expensive passes' input keys (the expensive key
              is what --skip-bake checks before it reuses the committed AO and thickness)
  body_hash   the body's positions, faces, UVs, weights, parts, regions and rest skeleton (the freeze
              of decision 9)
  files       {repository-relative path: {step, inputs (a hash of the step's inputs), sha256, size,
              cycles (true when Cycles pixels reach the file: compared with a tolerance on another
              toolchain)}}
  index       the giant index (meshes, garments, designs, regions, landmarks, defaults, tiers,
              textures) that tools/builders/giant_model.gd writes into scenes/player/giant_model.tscn
"""
from __future__ import annotations

import hashlib
import json
import os
import platform
from pathlib import Path

SCHEMA_VERSION = 1
GENERATED_BY = "tools/giant/build_giant.py"
REL_PATH = "assets/giant/manifest.json"
# Cycles outputs on another toolchain: the largest and the mean difference allowed, per channel
CYCLES_MAX = 2.0 / 255.0
CYCLES_MEAN = 0.1 / 255.0
# The reference toolchain's own bake jitter: the same bake on the same inputs and machine can come out a
# texel different (measured on the tangent-space normal bake: one texel of 1,048,576 off by 1/255 in one
# channel, in 3 of 14 bakes with the tile made beforehand, every other pass the same). Within it a Cycles
# output counts as regenerated on the reference toolchain; anything more is a content difference.
JITTER_MAX = 1.0 / 255.0
JITTER_TEXELS = 64


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def hash_json(obj) -> str:
    return sha256_bytes(json.dumps(obj, sort_keys=True, separators=(",", ":")).encode("utf-8"))


def cpu() -> dict:
    model, flags = platform.machine(), ""
    try:
        with open("/proc/cpuinfo", encoding="utf-8") as fh:
            for line in fh:
                if line.startswith("model name") and model == platform.machine():
                    model = line.split(":", 1)[1].strip()
                elif line.startswith("flags") and not flags:
                    flags = " ".join(sorted(line.split(":", 1)[1].split()))
    except OSError:
        pass
    return {"model": model, "flags_sha256": sha256_bytes(flags.encode())[:16]}


def toolchain() -> dict:
    import numpy
    import PIL
    import scipy
    out = {"python": platform.python_version(), "numpy": numpy.__version__, "scipy": scipy.__version__,
           "pillow": PIL.__version__, "cpu": cpu()}
    try:
        import OpenEXR
        out["openexr"] = OpenEXR.__version__
    except ImportError:
        out["openexr"] = None
    try:
        import bpy
        out["bpy"] = bpy.app.version_string
    except ImportError:
        out["bpy"] = None
    return out


def dumps(doc: dict) -> str:
    return json.dumps(doc, sort_keys=True, indent=1, ensure_ascii=True) + "\n"


def load(root) -> dict:
    path = Path(root) / REL_PATH
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def save(root, doc: dict) -> Path:
    path = Path(root) / REL_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(dumps(doc), encoding="utf-8")
    return path


def toolchain_diff(expected: dict, actual: dict) -> list:
    out = []
    for key in sorted(set(expected) | set(actual)):
        if expected.get(key) != actual.get(key):
            out.append("%s: manifest %s, here %s" % (key, expected.get(key), actual.get(key)))
    return out


def _flatten(prefix, obj, out):
    if isinstance(obj, dict):
        for k in sorted(obj):
            _flatten("%s.%s" % (prefix, k) if prefix else str(k), obj[k], out)
    else:
        out[prefix] = obj


def doc_diff(expected: dict, actual: dict, skip=("toolchain", "files")) -> list:
    """Differences between two manifests outside ``skip`` (index, landmarks, body hash, inputs)."""
    a, b = {}, {}
    _flatten("", {k: v for k, v in expected.items() if k not in skip}, a)
    _flatten("", {k: v for k, v in actual.items() if k not in skip}, b)
    out = []
    for key in sorted(set(a) | set(b)):
        if a.get(key) != b.get(key):
            out.append("%s: manifest %s, regenerated %s" % (key, str(a.get(key))[:80], str(b.get(key))[:80]))
    return out


def image_close(path_a, path_b) -> tuple:
    """(within the Cycles tolerance, largest difference, mean difference) of two images (0..1 units)."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(path_a)).astype(np.float64) / 255.0
    b = np.asarray(Image.open(path_b)).astype(np.float64) / 255.0
    if a.shape != b.shape:
        return False, 1.0, 1.0
    d = np.abs(a - b)
    mx, mean = float(d.max()), float(d.mean())
    return (mx <= CYCLES_MAX + 1e-9 and mean <= CYCLES_MEAN + 1e-9), mx, mean


def image_jitter(path_a, path_b) -> tuple:
    """(within the reference toolchain's bake jitter, texels that differ, largest difference in 0..1) of
    two images: at most JITTER_TEXELS texels, none by more than JITTER_MAX."""
    import numpy as np
    from PIL import Image
    a = np.asarray(Image.open(path_a)).astype(np.int32)
    b = np.asarray(Image.open(path_b)).astype(np.int32)
    if a.shape != b.shape:
        return False, -1, 1.0
    d = np.abs(a - b)
    per_texel = d.max(axis=-1) if d.ndim == 3 else d
    n, mx = int((per_texel > 0).sum()), float(d.max()) / 255.0
    return (n <= JITTER_TEXELS and mx <= JITTER_MAX + 1e-9), n, mx


def file_entry(root, rel, step, inputs, cycles) -> dict:
    p = os.path.join(root, rel)
    return {"step": step, "inputs": inputs, "sha256": sha256_file(p), "size": os.path.getsize(p),
            "cycles": bool(cycles)}
