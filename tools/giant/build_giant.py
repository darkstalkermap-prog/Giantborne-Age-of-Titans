#!/usr/bin/env python3
"""The giant asset pipeline: regenerates every file of assets/giant/ from the vendored CC0 data.

Run with the shared venv's Python under nice (plan M10 §2.5):
  nice -n 19 $GIANT_VENV/bin/python tools/giant/build_giant.py [steps] [options]

Steps (none given: --all):
  --body, --garments, --hair   the export (kit/export_game.py): the skeleton, the body, the eyes and the
                               shadow proxy in giant.glb and every hair, beard and garment mesh in
                               parts/<mesh id>.glb on the same skeleton (one run, so the three steps run
                               together), the landmarks, the chains and the body's hash
  --bake                       the Cycles bakes (kit/bake.py) into GIANT_CACHE: the cheap passes and
                               AO and thickness
  --designs                    the design array designs.png (kit/designs.py; needs the cheap passes)
  --pack                       tex/, tex_hi/, the hair atlas, the cloth detail maps (kit/pack.py)
  --clips                      P43's computed-keyframe clips (kit/clips.py) when that file exists
  --all                        every step above
Options:
  --verify       regenerate everything into a temporary folder and compare with manifest.json:
                 bit-exact on the reference toolchain but for the bake's own jitter (a Cycles output
                 may differ in at most 64 texels by 1/255: TOLERATED), the Cycles outputs on another
                 toolchain within 2/255 per channel and 0.1/255 on average; prints TOOLCHAIN DIFFERS
                 apart from CONTENT DIFFERS, checks the shipped files against the manifest, and ends
                 with GIANT VERIFY OK or GIANT VERIFY FAILED (exit 1). It never reads the bake cache
                 (it re-bakes), but refreshes it unless --no-cache.
  --skip-bake    bake only the cheap passes and read AO and thickness back from the committed
                 tex_hi/orm.png (R and B, lossless); first checks that the expensive passes' inputs
                 (the body, its UVs, the skin code, the settings) still hash to the manifest's, and
                 asks for the full regeneration (check.sh --giant-full) when they do not
  --no-cache     neither read nor write GIANT_CACHE
  --budget       estimate the shipped size (gzip then base64, as tools/build_web.sh counts) of each
                 file the Web preset ships (its exclude_filter in export_presets.cfg leaves out the
                 manifest and tex_hi/) from the measured rates, and fail over the giant's Web share
                 (plan §2.12): build_web.sh's rule, the budget less 18.4 MiB (4.6 at 23 MiB) of the milestone
                 the assets are made for (ASSET_MILESTONE: 15, the share the script sets for it, 14.0 MiB;
                 B1 - 12 and 13.6 MiB from P54); --share-mib=N overrides it
  --out=DIR      write under DIR instead of the repository (DIR/assets/giant/...)

Environment: GIANT_CACHE (default $HOME/.cache/giantborn/giant-cache), BAKE_THREADS (default 2).
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
KIT = HERE / "kit"
sys.path.insert(0, str(KIT))
sys.path.insert(0, str(HERE))
import manifest  # noqa: E402

ASSETS = "assets/giant"
STEPS = ("export", "bake", "designs", "pack", "clips")
EXPORT_SOURCES = ("mh_data.py", "giant_body.py", "giant_hair.py", "giant_garment.py", "giant_parts.py", "split.py",
                  "export_game.py", "clips.py")
PARTS = ASSETS + "/parts"
DESIGN_SOURCES = ("designs.py", "giant_skin.py", "giant_body.py", "mh_data.py", "split.py")
PACK_SOURCES = ("pack.py",)
CLIP_SOURCES = ("clips.py",) + EXPORT_SOURCES
# the giant's share of the Web pack (plan §2.12: 4.6 MiB at the 23 MiB budget), shipped bytes: as
# tools/build_web.sh rules it, the Web budget less what everything else keeps (OTHER_MIB)
OTHER_MIB = 18.4
BUILD_WEB = "tools/build_web.sh"
PRESETS = "export_presets.cfg"
# Measured shipped rates (gzip -9 then base64 of the imported files; the M10 asset brief's test export):
# meshes per vertex (LODs and shadow meshes included), textures per byte of VRAM data with mipmaps.
RATE_MESH_B_PER_VERTEX = 61.0
# P48, measured on its Web test export (each imported scene gzipped alone, then base64): a garment part
# ships 70.7 B a glTF vertex and a card mesh 36.0 B (fits over the 12 and the 9 parts), plus 13.5 KB a file
# for the skeleton and the skin every part's scene carries; the clips 11.6 B a keyed bone and key.
RATE_CARD_B_PER_VERTEX = 33.4
RATE_PART_B_PER_VERTEX = 70.7     # the W33 look lane: refitted on its parts (a garment's UV2 and its push alpha)
# The W33 look lane, fitted on the imported parts (each .scn is compressed by the importer, so gzip keeps it and
# base64 adds a third): a part's file no longer carries the skeleton (part_import.gd), only its skin's 71 binds, 8 KB;
# a blend shape (a face key) costs about 20 B a glTF vertex more (P56's keys were not counted: the estimate read
# 10.78 MiB while the Web build shipped 13.31).
RATE_PART_FILE_B = 8000.0
RATE_KEY_B_PER_VERTEX = 20.4
# P61, refitted on its Web test export (each imported part gzipped alone, then base64): a bead set's face keys move
# each bead whole (the same offset for every vertex of a bead), which the importer's compression all but removes - the
# four bead sets shipped 412,820 bytes against 698,766 estimated with RATE_KEY_B_PER_VERTEX (0.59 of it); counted at
# the part's own rate, their keys free, they estimate within 3 %. Every other part kept its rates (garments 0.91 of
# the estimate, cards 1.02-1.03).
RATE_BEAD_KEY_B_PER_VERTEX = 0.0
RATE_PROXY_B_PER_VERTEX = 45.0     # the shadow proxy: no UVs (ASSUMED: inside giant.glb, not measured apart)
RATE_SKELETON_B = 13500.0
RATE_CLIP_B_PER_BONE_KEY = 11.6
GODOT_VERTEX_SPLIT = 1.08          # the importer splits vertices at UV seams and normals
TEXTURE_FACTOR = {"albedo": 0.51, "normal": 0.94, "orm": 0.78, "masks": 0.10, "hair_atlas": 0.66,
                  "designs": 0.07, "cloth": 0.8}


def log(*a):
    print("[build_giant]", *a, flush=True)


def cache_root() -> Path:
    return Path(os.environ.get("GIANT_CACHE") or Path.home() / ".cache" / "giantborn" / "giant-cache")


def source_hashes(names) -> dict:
    return {n: manifest.sha256_file(KIT / n) for n in names}


def mpfb2_hash() -> str:
    return manifest.sha256_file(HERE / "mpfb2" / "FILES.sha256")


def bake_module():
    import bake
    return bake


def bake_keys(tool) -> dict:
    """The cheap and the expensive passes' input keys (the cache folders and the --skip-bake check)."""
    bk = bake_module()
    base = {"sources": source_hashes(bk.SOURCES), "mpfb2": mpfb2_hash(), "settings": bk.SETTINGS,
            "bpy": tool.get("bpy")}
    return {"cheap": manifest.hash_json(dict(base, passes=list(bk.CHEAP)))[:32],
            "expensive": manifest.hash_json(dict(base, passes=list(bk.EXPENSIVE)))[:32]}


def run_kit(script, *args):
    """Run a kit script in a fresh interpreter of this venv (Blender state never leaks between steps)."""
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    env.setdefault("BAKE_THREADS", "2")
    cmd = [sys.executable, "-B", str(KIT / script)] + [str(a) for a in args]
    t = time.time()
    r = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        sys.stdout.write(r.stdout[-6000:])
        raise SystemExit("build_giant: %s failed (exit %d)" % (script, r.returncode))
    return time.time() - t, r.stdout


# --------------------------------------------------------------------------------------
# the bakes and their cache
# --------------------------------------------------------------------------------------
def make_micro_tile(path: Path) -> None:
    """Writes the skin's micro-relief tile (skin_textures.make_micro) at ``path`` unless it exists, in an
    interpreter of its own, so the bake's process does the same work whether or not the tile was cached
    (the tangent-space normal bake is sensitive to its process's history: with the tile made inside it,
    one texel came out 1/255 off in 3 of 4 bakes; manifest.JITTER_TEXELS)."""
    if path.exists():
        return
    code = "import sys; sys.path.insert(0, sys.argv[1]); import skin_textures; skin_textures.make_micro(sys.argv[2])"
    r = subprocess.run([sys.executable, "-B", "-c", code, str(KIT), str(path)],
                       env=dict(os.environ, PYTHONDONTWRITEBYTECODE="1"),
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0 or not path.exists():
        sys.stdout.write(r.stdout[-4000:])
        raise SystemExit("build_giant: the micro-relief tile could not be made (exit %d)" % r.returncode)


def bake_dir(keys, want_expensive, read_cache, write_cache, work: Path, times: dict) -> Path:
    """A folder holding the cheap passes (and AO and thickness when ``want_expensive``)."""
    bk = bake_module()
    groups = [("cheap", bk.CHEAP)] + ([("expensive", bk.EXPENSIVE)] if want_expensive else [])
    out = work / "bake"
    out.mkdir(parents=True, exist_ok=True)
    missing = []
    for name, passes in groups:
        cdir = cache_root() / "bake" / keys[name]
        files = [f for p in passes for f in bk.FILES[p]]
        if read_cache and all((cdir / f).exists() for f in files):
            for f in files:
                shutil.copyfile(cdir / f, out / f)
            log("bake %s: from the cache (%s)" % (name, keys[name][:12]))
        else:
            missing.append((name, passes))
    if missing:
        passes = [p for _n, ps in missing for p in ps]
        # The skin's micro-relief tile: in the cache under the hash of its generator, so a changed
        # generator never meets a stale tile; a run that reads no cache (--verify, --no-cache) makes its own.
        micro_dir = (cache_root() / "micro" / manifest.hash_json(source_hashes(("skin_textures.py",)))[:16]
                     if read_cache else out)
        micro_dir.mkdir(parents=True, exist_ok=True)
        make_micro_tile(micro_dir / "skin_micro.png")
        secs, _ = run_kit("bake.py", out, ",".join(passes), micro_dir)
        times["bake " + "+".join(n for n, _p in missing)] = round(secs, 1)
        try:
            times.update({"bake." + k: v for k, v in json.loads((out / "bake_times.json").read_text()).items()})
        except (OSError, ValueError):
            pass
        if write_cache:
            for name, ps in missing:
                cdir = cache_root() / "bake" / keys[name]
                tmp = cdir.with_name(cdir.name + ".part%d" % os.getpid())
                tmp.mkdir(parents=True, exist_ok=True)
                for f in [f for p in ps for f in bk.FILES[p]]:
                    shutil.copyfile(out / f, tmp / f)
                if cdir.exists():
                    shutil.rmtree(cdir)
                os.replace(tmp, cdir)
    return out


# --------------------------------------------------------------------------------------
# the index
# --------------------------------------------------------------------------------------
def build_index(export_info: dict, design_info: dict) -> dict:
    import split
    res = "res://" + ASSETS + "/"
    meshes = {}
    for mid, e in sorted(export_info["meshes"].items()):
        entry = {"node": mid, "category": e["category"], "layer": e["layer"], "dye": e["dye"],
                 "covers": e.get("covers", []), "tris": e["tris"]}
        # P54 (plan M11 §2.6, the index v2): a garment's slot, its slot's shell offset (stage-1 m), its material, a head
        # garment's cut of the hair; an accessory's slot, bone and natural colour
        # P56: a style's bead anchors (how many), a bead set's style codes (style mesh -> its code in UV2.x), the face keys a
        # mesh carries
        for k in ("atlas", "detail", "part", "chains", "free", "shell", "slot", "material", "hides_hair", "hair_cut",
                  "bone", "color", "bead_anchors", "styles", "face_keys", "push_m", "push_tangent", "band"):
            if k in e:
                entry[k] = e[k]
        if "file" in e:
            # P48 (plan M11 §2.2): the mesh is a part, loaded when a look shows it (GiantModel.ensure_part).
            # "part" already names a garment's body part (torso | limbs), so the file is "part_path".
            entry["part_path"] = res + e["file"]
        if "coverage" in e:
            entry["coverage"] = {r: s for r, s in e["coverage"].items() if s >= 0.5}
        meshes[mid] = entry
    designs = {d: {"layer": v["layer"], "channel": v["channel"], "kind": v["kind"], "regions": v["regions"],
                   "side": v.get("side", "centre")}
               for d, v in sorted(design_info["designs"].items())}
    scar_layers = sorted({v["layer"] for v in designs.values() if v["kind"] == "scar"})
    return {
        "chains": export_info.get("chains", {}),
        "build_max_m": export_info.get("build_max_m", 0.0),
        "shadow_proxy": {k: export_info["shadow_proxy"][k] for k in ("node", "tris")} if "shadow_proxy" in export_info else {},
        "meshes": meshes,
        "garments": {g: list(m) for g, m in sorted(export_info["garments"].items())},
        "accessories": dict(sorted(export_info.get("accessories", {}).items())),
        # B1: the functional armour's rigid pieces (the Quarry set): piece id -> its mesh (category accessory)
        "armour": dict(sorted(export_info.get("armour", {}).items())),
        "slots": {"shell_m": export_info.get("slot_shell_m", {}), "layers": export_info.get("layer_order", [])},
        # the W33 look lane: the garments from the skin out and, per outer garment and worn inner garment, the least
        # share of its push (its index push_m) at each share of the inner one's (GiantLook.garment_pushes)
        "layering": {k: export_info["layering"][k] for k in ("order", "samples", "knots_m", "y_norm_m", "push")}
        if "layering" in export_info
        else {},
        "designs": designs,
        "regions": [{"id": i, "name": n} for i, n in enumerate(split.REGIONS)],
        "design_regions": {k: list(v) for k, v in sorted(split.DESIGN_REGIONS.items())},
        "landmarks": export_info["landmarks"],
        "defaults": {"shown": ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes", "Hair_long_back", "Beard_full"]
                     + sorted(export_info["garments"]["braies"]) + sorted(export_info["garments"]["belt"])},
        "tiers": {"web": res + "tex/", "hi": res + "tex_hi/"},
        "textures": {"designs": res + "designs.png", "design_layers": design_info["layers"],
                     "scar_layer": scar_layers[0] if scar_layers else -1,
                     "scar_layer_b": scar_layers[1] if len(scar_layers) > 1 else -1, "hair_atlas": res + "hair_atlas.png",
                     "detail_weave": res + "cloth_weave.png", "detail_leather": res + "cloth_leather.png",
                     "detail_fur": res + "cloth_fur.png", "detail_metal": res + "cloth_metal.png",
                     "detail_mail": res + "cloth_mail.png", "detail_scale": res + "cloth_scale.png",
                     "detail_bone": res + "cloth_leather.png",
                     "detail_stone": res + "cloth_metal.png",
                     "skin_lut": res + "tex/skin_lut.png", "shell_strands": res + "shell_strands.png"},
        "body_hash": export_info["body_hash"],
    }


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------
def build(steps, out_root: Path, read_cache=True, write_cache=True, skip_bake=False, verbose=True) -> dict:
    """Run ``steps`` with outputs under out_root/assets/giant; returns the new manifest."""
    old = manifest.load(out_root) or manifest.load(ROOT)
    tool = manifest.toolchain()
    keys = bake_keys(tool)
    times = {}
    files = dict(old.get("files", {}))
    doc = {k: old[k] for k in ("export", "designs", "clips") if k in old}
    assets = out_root / ASSETS
    assets.mkdir(parents=True, exist_ok=True)
    mp = mpfb2_hash()
    with tempfile.TemporaryDirectory(prefix="giant_build_") as tmp:
        work = Path(tmp)
        if "export" in steps:
            secs, _ = run_kit("export_game.py", work / "export")
            times["export"] = round(secs, 1)
            shutil.copyfile(work / "export" / "giant.glb", assets / "giant.glb")
            info = json.loads((work / "export" / "export_info.json").read_text())
            for k in ("seconds", "glb_bytes"):
                info.pop(k, None)
            doc["export"] = info
            inputs = manifest.hash_json({"sources": source_hashes(EXPORT_SOURCES), "mpfb2": mp})
            files[ASSETS + "/giant.glb"] = manifest.file_entry(out_root, ASSETS + "/giant.glb", "export", inputs, False)
            # P48: one glTF a part; a part the export no longer writes leaves the folder and the manifest
            (assets / "parts").mkdir(exist_ok=True)
            wanted = {Path(rel).name for rel in info.get("parts", {}).values()}
            for old_part in sorted((assets / "parts").glob("*.glb")):
                if old_part.name not in wanted:
                    old_part.unlink()
                    for extra in (".import",):
                        Path(str(old_part) + extra).unlink(missing_ok=True)
            for rel in [k for k in files if k.startswith(PARTS + "/")]:
                del files[rel]
            for mid, rel in sorted(info.get("parts", {}).items()):
                shutil.copyfile(work / "export" / rel, assets / rel)
                files[ASSETS + "/" + rel] = manifest.file_entry(out_root, ASSETS + "/" + rel, "export", inputs, False)
        need_bake = any(s in steps for s in ("bake", "designs", "pack"))
        if need_bake:
            if skip_bake:
                old_key = old.get("bake", {}).get("expensive_key")
                if old_key and old_key != keys["expensive"]:
                    raise SystemExit("build_giant: the expensive bake's inputs (the body, its UVs, the skin code, "
                                     "the settings) changed since the committed AO and thickness were baked "
                                     "(%s, now %s): run the full regeneration (tools/check.sh --giant-full, "
                                     "build_giant.py --verify without --skip-bake, or --all)" % (old_key[:12], keys["expensive"][:12]))
            bdir = bake_dir(keys, not skip_bake and ("pack" in steps or "bake" in steps), read_cache, write_cache,
                            work, times)
        if "designs" in steps:
            import designs
            t = time.time()
            dinfo = designs.build(str(bdir), str(work / "designs"))
            times["designs"] = round(time.time() - t, 1)
            shutil.copyfile(work / "designs" / "designs.png", assets / "designs.png")
            doc["designs"] = dinfo
            inputs = manifest.hash_json({"sources": source_hashes(DESIGN_SOURCES), "bake": keys["cheap"]})
            files[ASSETS + "/designs.png"] = manifest.file_entry(out_root, ASSETS + "/designs.png", "designs", inputs, True)
        if "pack" in steps:
            import pack
            t = time.time()
            orm_from = str(ROOT / ASSETS / "tex_hi" / "orm.png") if skip_bake else None
            if orm_from and not os.path.exists(orm_from):
                raise SystemExit("build_giant: --skip-bake needs the committed %s/tex_hi/orm.png" % ASSETS)
            written = pack.pack_all(str(bdir), str(assets), orm_from)
            times["pack"] = round(time.time() - t, 1)
            inputs = manifest.hash_json({"sources": source_hashes(PACK_SOURCES),
                                         "bake": [keys["cheap"], keys["expensive"]]})
            for rel in written:
                cyc = rel.startswith(("tex/", "tex_hi/"))
                files[ASSETS + "/" + rel] = manifest.file_entry(out_root, ASSETS + "/" + rel, "pack", inputs, cyc)
        if "clips" in steps:
            if (KIT / "clips.py").exists():
                # P43: the computed-keyframe clips; their gait measures (stride, slide) join the manifest
                secs, _ = run_kit("clips.py", assets, work / "clips")
                times["clips"] = round(secs, 1)
                doc["clips"] = json.loads((work / "clips" / "clips_info.json").read_text())
                inputs = manifest.hash_json({"sources": source_hashes(CLIP_SOURCES), "mpfb2": mp})
                files[ASSETS + "/giant_clips.glb"] = manifest.file_entry(out_root, ASSETS + "/giant_clips.glb", "clips",
                                                                         inputs, False)
            elif verbose:
                log("clips: skipped (kit/clips.py is P43's and does not exist yet)")
    if "export" not in doc or "designs" not in doc:
        raise SystemExit("build_giant: no export or design information yet: run --all first")
    doc.update({
        "schema_version": manifest.SCHEMA_VERSION,
        "generated_by": manifest.GENERATED_BY,
        "toolchain": tool,
        "inputs": {"mpfb2": mp, "kit": source_hashes(sorted(p.name for p in KIT.glob("*.py")))},
        "bake": {"settings": bake_module().SETTINGS, "cheap_key": keys["cheap"], "expensive_key": keys["expensive"]},
        "body_hash": doc["export"]["body_hash"],
        "files": {k: files[k] for k in sorted(files) if (out_root / k).exists()},
        "index": build_index(doc["export"], doc["designs"]),
    })
    if verbose:
        log("times: " + json.dumps(times, sort_keys=True))
    try:
        cache_root().mkdir(parents=True, exist_ok=True)
        (cache_root() / "last_build_times.json").write_text(json.dumps(times, indent=1, sort_keys=True))
    except OSError:
        pass
    doc["_times"] = times
    return doc


def write(out_root: Path, doc: dict) -> Path:
    doc = {k: v for k, v in doc.items() if not k.startswith("_")}
    path = manifest.save(out_root, doc)
    if out_root.resolve() == ROOT.resolve():
        ensure_import_files(out_root, doc)
    return path


# --------------------------------------------------------------------------------------
# import settings (plan §2.5): the committed .import files carry them
# --------------------------------------------------------------------------------------
IMPORT_TEXTURE = {"compress/mode": "2", "mipmaps/generate": "true"}
IMPORT_SETTINGS = {
    # P56 (probe 3): giant.glb carries its own tangents and the head's morph tangents (the face keys); the importer's
    # ensure_tangents regenerated the keys' tangents and drew a dark quad between the brows at a key's +1
    # (the second look lane: part_import.gd gives the body's meshes their far levels, far_lods.gd)
    "giant.glb": ("scene", "PackedScene", {"meshes/generate_lods": "true", "meshes/create_shadow_meshes": "true",
                                           "meshes/ensure_tangents": "false", "skins/use_named_skins": "true",
                                           "animation/import": "false",
                                           "import_script/path": '"res://tools/giant/part_import.gd"'}),
    # P48: a part is one mesh on the model's skeleton, bound by its named skin; it casts no shadow of its own
    # (the shadow proxy does; a free cape draws its own with its drawn mesh)
    # (the W33 look lane: part_import.gd keeps the skinned mesh and its skin and drops the 71-bone skeleton the glTF
    # carries, which GiantModel never uses: about 7.7 KB a part off the Web pack; the second look lane: and gives
    # every part its far levels, a hair style's and a beard's its strand levels, far_lods.gd)
    "parts/*.glb": ("scene", "PackedScene", {"meshes/generate_lods": "true", "meshes/create_shadow_meshes": "false",
                                             "meshes/ensure_tangents": "true", "skins/use_named_skins": "true",
                                             "animation/import": "false",
                                             "import_script/path": '"res://tools/giant/part_import.gd"'}),
    "designs.png": ("2d_array_texture", "CompressedTexture2DArray",
                    {"compress/mode": "2", "mipmaps/generate": "true", "slices/horizontal": "1"}),
    # P51: the skin's subsurface lookup is read by (N.L, curvature) in light(): exact values, no mipmaps
    "skin_lut.png": ("texture", "CompressedTexture2D", {"compress/mode": "0", "mipmaps/generate": "false"}),
    # P51: the shells' strands, a cell a strand: exact values with mipmaps (they thin out with distance)
    "shell_strands.png": ("texture", "CompressedTexture2D", {"compress/mode": "0", "mipmaps/generate": "true"}),
    # P43: the clips as an AnimationLibrary (loops are set in code: imported clips have loop off)
    "giant_clips.glb": ("animation_library", "AnimationLibrary",
                        {"animation/import": "true", "animation/fps": "30", "animation/remove_immutable_tracks": "true"}),
}


def import_params(rel: str, doc: dict):
    """(importer, type, {param: value}) of a generated file, or None for files Godot must not import."""
    name = rel.rsplit("/", 1)[-1]
    if rel.startswith("parts/") and name.endswith(".glb"):
        name = "parts/*.glb"
    if name in IMPORT_SETTINGS:
        imp, typ, params = IMPORT_SETTINGS[name]
        params = dict(params)
        if name == "designs.png":
            params["slices/vertical"] = str(doc["designs"]["layers"])
        return imp, typ, params
    if rel.endswith(".png"):
        params = dict(IMPORT_TEXTURE)
        params["compress/normal_map"] = "1" if name == "normal.png" else "0"
        return "texture", "CompressedTexture2D", params
    return None


def ensure_import_files(root: Path, doc: dict) -> list:
    """Write or patch every generated file's .import with the settings of plan §2.5 (Godot keeps the
    params when it re-imports and fills in the rest). Returns the files changed."""
    changed = []
    for rel in sorted(doc["files"]):
        spec = import_params(rel[len(ASSETS) + 1:], doc)
        if spec is None:
            continue
        importer, typ, params = spec
        path = root / (rel + ".import")
        if path.exists():
            text = path.read_text(encoding="utf-8")
            new = text
            for k, v in params.items():
                pat = re.compile(r"^%s=.*$" % re.escape(k), re.M)
                if pat.search(new):
                    new = pat.sub("%s=%s" % (k, v), new)
                else:
                    new = new.rstrip("\n") + "\n%s=%s\n" % (k, v)
            if new != text:
                path.write_text(new, encoding="utf-8")
                changed.append(str(path.relative_to(root)))
        else:
            lines = ["[remap]", "", 'importer="%s"' % importer, 'type="%s"' % typ, "", "[params]", ""]
            lines += ["%s=%s" % (k, v) for k, v in params.items()]
            path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            changed.append(str(path.relative_to(root)))
    return changed


# --------------------------------------------------------------------------------------
# verify
# --------------------------------------------------------------------------------------
def shipped_problems(doc: dict) -> list:
    """Committed files that differ from their manifest entry, and files under assets/giant that no
    step wrote."""
    out = []
    for rel, e in sorted(doc.get("files", {}).items()):
        p = ROOT / rel
        if not p.exists():
            out.append("%s: listed in the manifest but missing" % rel)
        elif manifest.sha256_file(p) != e.get("sha256"):
            out.append("%s: the committed file differs from the manifest (edited by hand?)" % rel)
    listed = set(doc.get("files", {}))
    for p in sorted((ROOT / ASSETS).rglob("*")):
        if p.is_dir() or p.suffix in (".import",) or p.name in ("manifest.json", "PROVENANCE.md") or p.name.endswith(".uid"):
            continue
        rel = str(p.relative_to(ROOT))
        if rel not in listed:
            out.append("%s: a file under %s that no step wrote" % (rel, ASSETS))
    return out


def verify(skip_bake: bool, use_cache_write: bool) -> int:
    expected = manifest.load(ROOT)
    if not expected:
        print("GIANT VERIFY FAILED: there is no %s" % manifest.REL_PATH)
        return 1
    t0 = time.time()
    with tempfile.TemporaryDirectory(prefix="giant_verify_") as tmp:
        out_root = Path(tmp)
        (out_root / ASSETS).mkdir(parents=True)
        steps = ["export", "designs", "pack"] + (["clips"] if (KIT / "clips.py").exists() else [])
        actual = build(steps, out_root, read_cache=False, write_cache=use_cache_write, skip_bake=skip_bake,
                       verbose=False)
        tool_diff = manifest.toolchain_diff(expected.get("toolchain", {}), actual["toolchain"])
        content = []
        tolerated = []
        for rel, e in sorted(expected.get("files", {}).items()):
            a = actual["files"].get(rel)
            if a is None:
                content.append("%s: in the manifest but not regenerated" % rel)
                continue
            if a["sha256"] == e["sha256"]:
                continue
            if e.get("cycles") and tool_diff and rel.endswith(".png"):
                ok, mx, mean = manifest.image_close(ROOT / rel, out_root / rel)
                if ok:
                    tolerated.append("%s: within the Cycles tolerance (max %.4f, mean %.5f)" % (rel, mx, mean))
                    continue
                content.append("%s: differs beyond the Cycles tolerance (max %.4f, mean %.5f)" % (rel, mx, mean))
                continue
            if e.get("cycles") and rel.endswith(".png"):
                ok, texels, mx = manifest.image_jitter(ROOT / rel, out_root / rel)
                if ok:
                    tolerated.append("%s: %d texel(s) off by at most 1/255, the bake's own jitter" % (rel, texels))
                    continue
            content.append("%s: regenerated %s, manifest %s" % (rel, a["sha256"][:12], e["sha256"][:12]))
        for rel in sorted(set(actual["files"]) - set(expected.get("files", {}))):
            content.append("%s: regenerated but not in the manifest" % rel)
        content += ["manifest " + d for d in manifest.doc_diff(
            {k: v for k, v in expected.items() if k not in ("bake",)},
            {k: v for k, v in actual.items() if k not in ("bake", "_times")}, skip=("toolchain", "files", "inputs"))]
        if expected.get("bake", {}).get("cheap_key") != actual["bake"]["cheap_key"]:
            content.append("bake inputs: the cheap passes' key changed (%s -> %s)" % (
                expected.get("bake", {}).get("cheap_key"), actual["bake"]["cheap_key"]))
        if expected.get("inputs") != actual["inputs"]:
            for k in sorted(set(expected.get("inputs", {}).get("kit", {})) | set(actual["inputs"]["kit"])):
                if expected.get("inputs", {}).get("kit", {}).get(k) != actual["inputs"]["kit"].get(k):
                    content.append("inputs: kit/%s changed since the manifest was written" % k)
            if expected.get("inputs", {}).get("mpfb2") != actual["inputs"]["mpfb2"]:
                content.append("inputs: the vendored CC0 file list changed")
        times = actual.get("_times", {})
    shipped = shipped_problems(expected)
    for line in tool_diff:
        print("TOOLCHAIN DIFFERS: " + line)
    for line in tolerated:
        print("TOLERATED: " + line)
    for line in content:
        print("CONTENT DIFFERS: " + line)
    for line in shipped:
        print("SHIPPED FILE: " + line)
    n = len(expected.get("files", {}))
    mode = "the cheap passes, AO and thickness from tex_hi/orm.png" if skip_bake else "every bake pass"
    print("GIANT VERIFY TIMES: %s (%.0f s in all)" % (json.dumps(times, sort_keys=True), time.time() - t0))
    if content or shipped:
        if tool_diff:
            print("note: the toolchain differs from the reference recorded in the manifest; outside the "
                  "Cycles outputs that changes bytes by itself: regenerate on the reference toolchain")
        print("GIANT VERIFY FAILED: %d content differences, %d shipped-file problems (of %d files; %s)" % (
            len(content), len(shipped), n, mode))
        return 1
    print("GIANT VERIFY OK: %d files regenerated %s (%s)%s" % (
        n, "bit-exact" if not tolerated else "bit-exact or within the bake's tolerance (TOLERATED)", mode,
        " (toolchain differs: %d keys)" % len(tool_diff) if tool_diff else ""))
    return 0


# --------------------------------------------------------------------------------------
# budget
# --------------------------------------------------------------------------------------
def estimate(rel: str, doc: dict) -> float:
    """The estimated shipped bytes of one generated file (measured rates; plan §2.12)."""
    name = rel.rsplit("/", 1)[-1]
    meshes = doc["export"]["meshes"]
    if name == "giant.glb":
        total = RATE_SKELETON_B
        for mid, e in meshes.items():
            if "file" not in e:
                total += e["verts"] * GODOT_VERTEX_SPLIT * (RATE_MESH_B_PER_VERTEX
                                                            + len(e.get("face_keys", [])) * RATE_KEY_B_PER_VERTEX)
        total += doc["export"].get("shadow_proxy", {}).get("verts", 0) * RATE_PROXY_B_PER_VERTEX
        return total
    if "/parts/" in rel and name.endswith(".glb"):
        e = meshes.get(name[:-4], {})
        rate = RATE_CARD_B_PER_VERTEX if e.get("category") in ("hair", "beard") else RATE_PART_B_PER_VERTEX
        key_rate = RATE_BEAD_KEY_B_PER_VERTEX if e.get("category") == "bead" else RATE_KEY_B_PER_VERTEX
        rate += len(e.get("face_keys", [])) * key_rate
        return RATE_PART_FILE_B + e.get("verts", 0) * GODOT_VERTEX_SPLIT * rate
    if name == "giant_clips.glb":
        return RATE_CLIP_B_PER_BONE_KEY * sum(c["bones"] * (c["frames"] + 1)
                                              for c in doc.get("clips", {}).get("clips", {}).values())
    if not name.endswith(".png"):
        return 0.0
    from PIL import Image
    with Image.open(ROOT / rel) as im:
        w, h = im.size
        has_alpha = im.mode in ("RGBA", "LA")
    if name == "skin_lut.png":
        return w * h * 4.0 * 0.6                                     # lossless, no mipmaps (P51)
    if name == "shell_strands.png":
        return w * h * 4.0 * 4.0 / 3.0 * 0.8                         # lossless with mipmaps (P51)
    bpt = 1.0 if (has_alpha or name == "normal.png") else 0.5       # DXT5 / RGTC: 1 byte a texel, DXT1: 0.5
    raw = w * h * bpt * 4.0 / 3.0
    key = "cloth" if name.startswith("cloth_") else name[:-4]
    return raw * TEXTURE_FACTOR.get(key, 0.8)


# P54 (plan M11 §2.12): the release the committed giant assets are made for. Part B's wardrobe ships in 0.12, so its
# files are judged by build_web.sh's -m12 budget (32 MiB: the giant's share 13.6) while the version string still
# reads -m11 until P58 sets it; the estimate falls back on the last default when the script names no such branch.
ASSET_MILESTONE = 15   # B1: the functional armour's milestone (its own giant share in build_web.sh); 12 before


def web_budget_mib(root: Path = ROOT, milestone: int | None = ASSET_MILESTONE) -> float:
    """The Web pack's budget in MiB for ``milestone``: the branch of tools/build_web.sh that assigns it ("-eq N"),
    else the last default the script assigns (26 MiB from -m10 on, the owner's answer 1, plan §0.6; 23 MiB before
    P45)."""
    text = (root / BUILD_WEB).read_text()
    if milestone is not None:
        own = re.findall(r'-eq %d \]; then BUDGET_MB=([0-9]+(?:\.[0-9]+)?)\b' % milestone, text)
        if own:
            return float(own[-1])
    found = re.findall(r"\bBUDGET_MB=([0-9]+(?:\.[0-9]+)?)\b", text)
    return float(found[-1]) if found else 23.0


def share_cap_mib(root: Path = ROOT) -> float:
    """The giant's share of the Web pack: build_web.sh's rule (its GIANT_SHARE cap) - B1: the share the script sets
    for the assets' milestone ("-ge N ]; then GIANT_SHARE_MB=X" with N at or below ASSET_MILESTONE), else the budget
    less OTHER_MIB."""
    text = (root / BUILD_WEB).read_text()
    set_shares = [(int(n), float(v)) for n, v in
                  re.findall(r'-ge ([0-9]+) \]; then GIANT_SHARE_MB=([0-9]+(?:\.[0-9]+)?)\b', text)]
    own = [v for n, v in set_shares if ASSET_MILESTONE is not None and n <= ASSET_MILESTONE]
    if own:
        return own[-1]
    return round(max(0.0, web_budget_mib(root) - OTHER_MIB), 1)


def web_excluded(root: Path = ROOT, preset: str = "Web") -> list:
    """The exclude_filter patterns of the Web preset in export_presets.cfg."""
    text = (root / PRESETS).read_text()
    for section in re.split(r"(?m)^\[preset\.\d+\]\s*$", text)[1:]:
        if re.search(r'(?m)^name="%s"\s*$' % re.escape(preset), section):
            m = re.search(r'(?m)^exclude_filter="([^"]*)"', section)
            return [f.strip() for f in m.group(1).split(",") if f.strip()] if m else []
    return []


def budget(share_mib: float | None = None) -> int:
    import fnmatch
    doc = manifest.load(ROOT)
    if not doc:
        print("build_giant: no manifest yet")
        return 1
    if share_mib is None:
        share_mib = share_cap_mib()
    excluded = web_excluded()
    total = 0.0
    for rel in sorted(doc["files"]):
        if any(fnmatch.fnmatch(rel, pat) for pat in excluded):
            print("WEB_EXCLUDED %s (the Web preset leaves it out)" % rel)
            continue
        b = estimate(rel, doc)
        total += b
        print("ESTIMATE %-40s %9.0f bytes shipped" % (rel, b))
    mib = total / 1048576.0
    print("GIANT_ESTIMATE shipped_mib=%.2f cap_mib=%.2f (the real share: tools/build_web.sh's GIANT_SHARE line)" % (
        mib, share_mib))
    if mib > share_mib:
        print("OVER BUDGET: the giant's files are estimated at %.2f MiB shipped, over %.2f MiB" % (mib, share_mib))
        return 1
    return 0


# --------------------------------------------------------------------------------------
def main(argv) -> int:
    steps, out, verify_mode, skip, no_cache, do_budget = [], None, False, False, False, False
    share = None
    step_flags = {"--body": "export", "--garments": "export", "--hair": "export", "--bake": "bake",
                  "--designs": "designs", "--pack": "pack", "--clips": "clips"}
    for a in argv:
        if a in step_flags:
            if step_flags[a] not in steps:
                steps.append(step_flags[a])
        elif a == "--all":
            steps = list(STEPS)
        elif a == "--verify":
            verify_mode = True
        elif a == "--skip-bake":
            skip = True
        elif a == "--no-cache":
            no_cache = True
        elif a == "--budget":
            do_budget = True
        elif a.startswith("--share-mib="):
            share = float(a.split("=", 1)[1])
        elif a.startswith("--out="):
            out = Path(a.split("=", 1)[1]).resolve()
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print("build_giant.py: unknown option %s" % a, file=sys.stderr)
            return 2
    if verify_mode:
        return verify(skip, not no_cache)
    if do_budget and not steps:
        return budget(share)
    steps = steps or list(STEPS)
    if "bake" in steps and skip:
        steps.remove("bake")
    out_root = out or ROOT
    doc = build(steps, out_root, read_cache=not no_cache, write_cache=not no_cache, skip_bake=skip)
    path = write(out_root, doc)
    log("wrote %d files; manifest %s" % (len(doc["files"]), path))
    return budget(share) if do_budget else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
