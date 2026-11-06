#!/usr/bin/env python3
"""Builds every generated sound of Giantborn (plan M6-M9, decision 4, section 3.1 design 6).

    python3 tools/audio/build_audio.py [--only=<family>[,<family>]] [--verify] [--budget]
                                       [--masters-out=<dir>] [--out=<dir>]

Every gen_<family>.py module beside this file exposes CUES, a list of dicts:

    name     unique within the family           path   res:// path of the shipped file
    seed     the cue's random seed              func   render(rng, **params) -> float64 array
    params   the render's parameters (dict)     kind   "sfx" (16-bit WAV, imported as QOA) |
                                                       "loop" | "oneshot" (Ogg Vorbis)
    rate     22050 by default                   quality  libvorbis -q:a for Ogg (default 0)
    norm     {"peak_db": x}, {"rms_db": x} or {"lufs": x} (K-weighted, gated loudness; P23's
             music and ambience), with "max_peak_db" (defaults: SFX peak -6 dBFS, the rest -3)
    bpm, beats, beats_per_bar, frame            music loops (the loop must be exactly
                                                beats x 60 / bpm seconds long)
    scope    "m6" (default) or "world"          est_kbps  Ogg size estimate (KB per second)

The build renders each cue with its own seeded generator (float64, single-threaded), normalises
it, checks it (clipping, DC, silence, SFX over 2.0 s, a loop seam, a loop of the wrong length),
prints the size arithmetic of plan section 4.5 and the registered SFX seconds per level and fails
over decision 8's budgets, writes the SFX WAV masters, encodes every Ogg with encode.py
(libvorbis, bit-exact) and rewrites assets/audio/manifest.json.

  --only=a,b        regenerate only these families (the manifest keeps the others' entries)
  --out=DIR         write everything under DIR instead of the repository (same relative paths)
  --verify          regenerate every master and every Ogg into a temporary folder and compare
                    every hash with the manifest; also hash the shipped files against it. A
                    toolchain difference (Python, numpy, ffmpeg, libvorbis) is reported apart
                    from a content difference. Exit 1 on any content difference.
  --budget          print the size arithmetic and the registered seconds from the manifest and
                    the banks (no rendering) and fail over the budgets
  --masters-out=DIR also write the lossless music and ambience masters as FLAC into DIR

Building or playing the game never needs Python or ffmpeg; only regenerating audio does.
"""

from __future__ import annotations

import os
import sys

sys.dont_write_bytecode = True   # no __pycache__ folders in the repository

# Single-threaded numerical code (decision 4): set before numpy is imported anywhere.
for _var in ("OMP_NUM_THREADS", "OPENBLAS_NUM_THREADS", "MKL_NUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(_var, "1")

import importlib.util
import json
import math
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

import numpy as np  # noqa: E402

import encode  # noqa: E402
import manifest  # noqa: E402
from synth import core  # noqa: E402

KINDS = ("sfx", "loop", "oneshot")
SCOPES = ("m6", "world")
# Decision 8 (plan section 4.5): imported sizes and registered SFX seconds.
BUDGET_M6_BYTES = 4.0 * 1024 * 1024
BUDGET_ALL_BYTES = 9.5 * 1024 * 1024
REGISTERED_S_CAP = {"level.valley": 110.0, "level.world": 170.0}
OGG_HEADER_BYTES = 3.7 * 1024
OGG_IMPORT_FACTOR = 1.03
QOA_IMPORT_BYTES = 370
# KB per second of Ogg by (quality, channels) when a cue gives no est_kbps (section 4.5 rates).
OGG_KBPS = {(0, 1): 3.2, (1, 1): 4.0, (2, 1): 4.6, (0, 2): 5.5, (1, 2): 7.0, (2, 2): 8.5}
DEFAULT_NORM = {"sfx": {"peak_db": -6.0}, "loop": {"peak_db": -3.0}, "oneshot": {"peak_db": -3.0}}


class BuildError(RuntimeError):
    pass


# --------------------------------------------------------------------------- generators


def generator_files() -> list:
    return sorted(HERE.glob("gen_*.py"))


def load_generator(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    if not hasattr(module, "CUES"):
        raise BuildError("%s has no CUES list" % path.name)
    return module


def family_of(module) -> str:
    return str(getattr(module, "FAMILY", module.__name__[len("gen_"):]))


def collect(only: set | None) -> list:
    """[(family, module_name, cue dict)] of every generator (or only the named families)."""
    out = []
    seen_paths = {}
    for path in generator_files():
        module = load_generator(path)
        fam = family_of(module)
        if only and fam not in only:
            continue
        names = set()
        for cue in module.CUES:
            for key in ("name", "path", "seed", "func", "params", "kind"):
                if key not in cue:
                    raise BuildError("%s: a cue lacks '%s'" % (path.name, key))
            if cue["name"] in names:
                raise BuildError("%s: duplicate cue name %s" % (path.name, cue["name"]))
            names.add(cue["name"])
            if cue["kind"] not in KINDS:
                raise BuildError("%s/%s: kind must be one of %s" % (fam, cue["name"], KINDS))
            if cue.get("scope", "m6") not in SCOPES:
                raise BuildError("%s/%s: scope must be one of %s" % (fam, cue["name"], SCOPES))
            want_ext = ".wav" if cue["kind"] == "sfx" else ".ogg"
            if not str(cue["path"]).startswith("res://assets/audio/") or not str(cue["path"]).endswith(want_ext):
                raise BuildError("%s/%s: path must be res://assets/audio/...%s" % (fam, cue["name"], want_ext))
            if cue["path"] in seen_paths:
                raise BuildError("%s/%s: path %s is also written by %s" % (fam, cue["name"], cue["path"],
                                                                         seen_paths[cue["path"]]))
            seen_paths[cue["path"]] = "%s/%s" % (fam, cue["name"])
            out.append((fam, path.stem, cue))
    return out


def rel_path(res_path: str) -> str:
    return res_path[len("res://"):]


# --------------------------------------------------------------------------- rendering


def render(fam: str, cue: dict) -> dict:
    """Renders, normalises and checks one cue: {"x", "rate", "channels", "problems"}."""
    rate = int(cue.get("rate", core.DEFAULT_RATE))
    rng = core.cue_rng(int(cue["seed"]))
    x = np.asarray(cue["func"](rng, **cue["params"]), dtype=np.float64)
    if x.ndim not in (1, 2) or (x.ndim == 2 and x.shape[1] not in (1, 2)):
        raise BuildError("%s/%s: render must be (n,) or (n, 2)" % (fam, cue["name"]))
    if x.ndim == 2 and x.shape[1] == 1:
        x = x[:, 0]
    norm = dict(DEFAULT_NORM[cue["kind"]])
    norm.update(cue.get("norm", {}))
    if "lufs" in norm:
        x = core.normalize_lufs(x, rate, float(norm["lufs"]), float(norm.get("max_peak_db", -1.0)))
    elif "rms_db" in norm:
        x = core.normalize_rms(x, float(norm["rms_db"]), float(norm.get("max_peak_db", -1.0)))
    else:
        x = core.normalize_peak(x, float(norm.get("peak_db", -6.0)))
    loop = bool(cue.get("loop", cue["kind"] == "loop"))
    problems = core.check_signal(x, rate, cue["kind"], loop)
    if "bpm" in cue or "beats" in cue:
        want = int(round(float(cue["beats"]) * 60.0 / float(cue["bpm"]) * rate))
        if x.shape[0] != want:
            problems.append("loop is %d frames, %s beats at %s bpm is %d" % (x.shape[0], cue["beats"],
                                                                           cue["bpm"], want))
    return {"x": x, "rate": rate, "channels": 1 if x.ndim == 1 else 2, "loop": loop,
            "problems": problems}


def entry_for(fam: str, module_name: str, cue: dict, r: dict) -> dict:
    frames = int(r["x"].shape[0])
    e = {"family": fam, "generator": module_name, "function": getattr(cue["func"], "__name__", "?"),
         "seed": int(cue["seed"]), "params_hash": manifest.params_hash(cue["params"]),
         "kind": cue["kind"], "scope": cue.get("scope", "m6"), "frames": frames, "rate": r["rate"],
         "channels": r["channels"], "seconds": round(frames / r["rate"], 6), "loop": r["loop"]}
    for key in ("bpm", "beats", "beats_per_bar", "frame"):
        if key in cue:
            e[key] = cue[key]
    if cue["kind"] != "sfx":
        e["quality"] = float(cue.get("quality", 0))
        if "est_kbps" in cue:
            e["est_kbps"] = float(cue["est_kbps"])
    return e


# --------------------------------------------------------------------------- budget


def qoa_bytes(frames: int, channels: int) -> int:
    """Godot's QOA data size (exact, docs/plans/briefs/audio_tech.md section 2)."""
    per = 8 + 24 * math.ceil(frames / 5120) + 8 * math.ceil(frames / 20)
    return channels * per


def estimate_bytes(e: dict) -> float:
    """The imported size of one manifest entry, by the arithmetic of plan section 4.5."""
    if e["kind"] == "sfx":
        return qoa_bytes(int(e["frames"]), int(e["channels"])) + QOA_IMPORT_BYTES
    kbps = e.get("est_kbps", OGG_KBPS.get((int(round(e.get("quality", 0))), int(e["channels"])), 5.5))
    return (float(e["seconds"]) * float(kbps) * 1024.0 + OGG_HEADER_BYTES) * OGG_IMPORT_FACTOR


def imported_bytes(e: dict) -> float:
    """The imported size of a built entry: the exact QOA formula for WAVs, the Ogg file x 1.03."""
    if e["kind"] == "sfx":
        return qoa_bytes(int(e["frames"]), int(e["channels"])) + QOA_IMPORT_BYTES
    return float(e.get("size", 0)) * OGG_IMPORT_FACTOR if "size" in e else estimate_bytes(e)


def bank_cues(root: Path) -> list:
    """Every cue of data/audio/bank_*.json: [(cue_id, cue dict)]."""
    out = []
    for path in sorted((Path(root) / "data" / "audio").glob("bank_*.json")):
        doc = json.loads(path.read_text(encoding="utf-8"))
        for cue_id, cue in sorted(doc.get("cues", {}).items()):
            out.append((cue_id, cue))
    return out


def registered_seconds(files: dict, root: Path) -> dict:
    """Seconds of SFX samples each level registers (plan section 4.5): every WAV of a cue on the
    SFX or UI bus counts once per level, global cues (levels []) for every level. Keys: the
    capped levels plus every level a cue names."""
    per_level = {}
    global_files = set()
    level_files = {}
    for _cue_id, cue in bank_cues(root):
        wavs = [f for f in cue.get("files", []) if str(f).endswith(".wav")]
        levels = cue.get("levels", [])
        if not levels:
            global_files.update(wavs)
        for lv in levels:
            level_files.setdefault(lv, set()).update(wavs)
    for lv in sorted(set(REGISTERED_S_CAP) | set(level_files)):
        names = global_files | level_files.get(lv, set())
        per_level[lv] = round(sum(float(files.get(f, {}).get("seconds", 0.0)) for f in names), 3)
    return per_level


def budget_report(files: dict, root: Path, actual: bool) -> tuple:
    """(lines, problems) for the size budget of decision 8 and the registered seconds."""
    lines = ["%-62s %-7s %-5s %8s %10s" % ("file", "kind", "scope", "seconds", "KB")]
    total = {"m6": 0.0, "world": 0.0}
    for path in sorted(files):
        e = files[path]
        size = imported_bytes(e) if actual else estimate_bytes(e)
        total[e.get("scope", "m6")] = total.get(e.get("scope", "m6"), 0.0) + size
        lines.append("%-62s %-7s %-5s %8.3f %10.1f" % (path[len("res://assets/audio/"):], e["kind"],
                                                       e.get("scope", "m6"), float(e["seconds"]), size / 1024.0))
    all_bytes = sum(total.values())
    lines.append("%s imported size: M6 %.3f MB (cap %.1f), world %.3f MB, all %.3f MB (cap %.1f)" % (
        "built" if actual else "estimated", total["m6"] / 1048576.0, BUDGET_M6_BYTES / 1048576.0,
        total["world"] / 1048576.0, all_bytes / 1048576.0, BUDGET_ALL_BYTES / 1048576.0))
    problems = []
    if total["m6"] > BUDGET_M6_BYTES:
        problems.append("M6 audio is %.3f MB, over the %.1f MB budget" % (total["m6"] / 1048576.0,
                                                                         BUDGET_M6_BYTES / 1048576.0))
    if all_bytes > BUDGET_ALL_BYTES:
        problems.append("all audio is %.3f MB, over the %.1f MB budget" % (all_bytes / 1048576.0,
                                                                          BUDGET_ALL_BYTES / 1048576.0))
    reg = registered_seconds(files, root)
    for lv in sorted(reg):
        cap = REGISTERED_S_CAP.get(lv)
        lines.append("registered SFX seconds in %s: %.2f%s" % (lv, reg[lv], (" (cap %.0f)" % cap) if cap else ""))
        if cap is not None and reg[lv] > cap:
            problems.append("%s registers %.1f s of SFX, over its %.0f s cap" % (lv, reg[lv], cap))
    return lines, problems


# --------------------------------------------------------------------------- the build


def build(only: set | None, out_root: Path, masters_out: Path | None, quiet: bool) -> dict:
    """Renders and writes the cues; returns the new manifest document (not yet saved)."""
    cues = collect(only)
    needs_ogg = any(c["kind"] != "sfx" for _f, _m, c in cues)
    if needs_ogg:
        encode.check_encoder()
    rendered = []
    problems = []
    for fam, module_name, cue in cues:
        r = render(fam, cue)
        for p in r["problems"]:
            problems.append("%s/%s (%s): %s" % (fam, cue["name"], cue["path"], p))
        rendered.append((fam, module_name, cue, r))
    if problems:
        raise BuildError("generated cues failed their checks:\n  " + "\n  ".join(problems))
    old = manifest.load(ROOT)
    files = {} if only is None else {p: e for p, e in old.get("files", {}).items() if e.get("family") not in only}
    for fam, module_name, cue, r in rendered:
        files[cue["path"]] = entry_for(fam, module_name, cue, r)
    lines, over = budget_report(files, ROOT, actual=False)
    if not quiet:
        print("\n".join(lines))
    if over:
        raise BuildError("over budget (decision 8):\n  " + "\n  ".join(over))
    with tempfile.TemporaryDirectory() as tmp:
        for fam, _module_name, cue, r in rendered:
            dest = Path(out_root) / rel_path(cue["path"])
            dest.parent.mkdir(parents=True, exist_ok=True)
            e = files[cue["path"]]
            if cue["kind"] == "sfx":
                data = core.wav_bytes_pcm16(r["x"], r["rate"])
                dest.write_bytes(data)
                e["master_hash"] = core.sha256(data)
            else:
                master = core.wav_bytes_f32(r["x"], r["rate"])
                e["master_hash"] = core.sha256(master)
                src = Path(tmp) / ("%s_%s.wav" % (fam, cue["name"]))
                src.write_bytes(master)
                encode.encode_ogg(src, dest, float(cue.get("quality", 0)), r["rate"], r["channels"])
                if masters_out is not None:
                    core.export_flac(r["x"], r["rate"], Path(masters_out) / fam / (cue["name"] + ".flac"))
            data = dest.read_bytes()
            e["file_hash"] = core.sha256(data)
            e["size"] = len(data)
    lines, over = budget_report(files, ROOT, actual=True)
    if not quiet:
        print(lines[-1 - len(registered_seconds(files, ROOT))])
    if over:
        raise BuildError("over budget after encoding (decision 8):\n  " + "\n  ".join(over))
    tools = manifest.toolchain(np.__version__, encode.ffmpeg_version() if needs_ogg else old.get("tools", {}).get("ffmpeg", "unknown"),
                               encode.libvorbis_version() if needs_ogg else old.get("tools", {}).get("libvorbis", "unknown"))
    return {"schema_version": manifest.SCHEMA_VERSION, "generated_by": manifest.GENERATED_BY,
            "tools": tools, "files": dict(sorted(files.items()))}


def shipped_problems(doc: dict) -> list:
    """Shipped files that differ from their manifest entry, and audio files nobody generated."""
    out = []
    for path, e in sorted(doc.get("files", {}).items()):
        f = ROOT / rel_path(path)
        if not f.exists():
            out.append("%s: listed in the manifest but missing" % path)
        elif core.sha256(f.read_bytes()) != e.get("file_hash"):
            out.append("%s: the shipped file differs from the manifest (edited by hand?)" % path)
    listed = set(doc.get("files", {}))
    for f in sorted((ROOT / "assets" / "audio").rglob("*")):
        if f.suffix in (".wav", ".ogg") and ("res://" + str(f.relative_to(ROOT))) not in listed:
            out.append("res://%s: an audio file no generator wrote" % f.relative_to(ROOT))
    return out


def verify() -> int:
    expected = manifest.load(ROOT)
    with tempfile.TemporaryDirectory() as tmp:
        actual = build(None, Path(tmp), None, quiet=True)
    diff = manifest.compare(expected, actual)
    shipped = shipped_problems(expected)
    for line in diff["toolchain"]:
        print("TOOLCHAIN DIFFERS: " + line)
    for line in diff["content"]:
        print("CONTENT DIFFERS: " + line)
    for line in shipped:
        print("SHIPPED FILE: " + line)
    n = len(expected.get("files", {}))
    if diff["content"] or shipped:
        if diff["toolchain"]:
            print("note: the toolchain differs from the reference recorded in the manifest, which "
                  "changes bytes by itself; regenerate on the reference toolchain to compare content")
        print("AUDIO VERIFY FAILED: %d content differences, %d shipped-file problems (of %d files)" % (
            len(diff["content"]), len(shipped), n))
        return 1
    print("AUDIO VERIFY OK: %d files regenerated bit-exact%s" % (
        n, " (toolchain differs: %d keys)" % len(diff["toolchain"]) if diff["toolchain"] else ""))
    return 0


def main(argv: list) -> int:
    only = None
    out_root = ROOT
    masters_out = None
    do_verify = False
    do_budget = False
    for arg in argv:
        if arg.startswith("--only="):
            only = {s.strip() for s in arg[len("--only="):].split(",") if s.strip()}
        elif arg.startswith("--out="):
            out_root = Path(arg[len("--out="):]).resolve()
        elif arg.startswith("--masters-out="):
            masters_out = Path(arg[len("--masters-out="):]).resolve()
        elif arg == "--verify":
            do_verify = True
        elif arg == "--budget":
            do_budget = True
        elif arg in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print("build_audio.py: unknown option %s" % arg, file=sys.stderr)
            return 2
    try:
        if do_verify:
            return verify()
        if do_budget:
            lines, over = budget_report(manifest.load(ROOT).get("files", {}), ROOT, actual=True)
            print("\n".join(lines))
            for p in over:
                print("OVER BUDGET: " + p)
            return 1 if over else 0
        doc = build(only, out_root, masters_out, quiet=False)
        path = manifest.save(out_root, doc)
        print("wrote %d files; manifest %s" % (len(doc["files"]), path))
        return 0
    except (BuildError, encode.EncoderError) as err:
        print("build_audio.py: %s" % err, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
