#!/usr/bin/env python3
"""The people pipeline (plan M11 §2.8, P59): regenerates every file of assets/people/ from the vendored CC0 data.

Run with the giant's shared venv under nice, as build_giant.py:
  nice -n 19 $GIANT_VENV/bin/python tools/giant/build_people.py [steps] [options]

Steps (none given: --all):
  --humans        every role of kit/people_roles.py (kit/people_outfit.py, one process a role): <role>.glb (the
                  role's variants on their 23-bone skeletons, its five crowd-pose meshes and its far mesh) and the
                  role's atlas <role>_albedo.png (512 px), <role>_normal.png and <role>_orm.png (256 px)
  --clips         people_clips.glb (kit/people_body.py: clips.py's generator on the reference man, 23 bones)
  --gear          gear.glb (kit/people_outfit.py: weapons, shields, the banner; the project's own shapes)
  --horse         the horse (kit/quadruped.py, P61) into assets/creatures/: horse.glb (the bare and the tacked horse on
                  their 25-bone skeleton), horse_poses.glb (the gait's extremes, a check), horse_albedo.png (512 px,
                  RGBA: A the mane's and the tail's strands), horse_normal.png and horse_orm.png (256 px); its own
                  manifest assets/creatures/manifest.json
  --brutes        the ogre and the troll (kit/brute.py, P63; one interpreter a kind) into assets/creatures/:
                  <kind>.glb (the variants on their 23-bone skeletons - the troll's whelp among them -, the bosses'
                  gear, a far mesh each), <kind>_clips.glb (the kind's clips), <kind>_albedo.png (512 px),
                  <kind>_normal.png and <kind>_orm.png (256 px)
  --stoneback     (A1) Stoneback, the quarry titan (kit/stoneback.py): stoneback.glb (the body, the stone plates each
                  its own mesh, the shackles, the trunk-club, the boulder, the far mesh), stoneback_clips.glb, his atlas
                  and the tileable stone and bark textures stoneback_{stone,bark}_{albedo,normal}.png (256 px)
  --rootwarden    (B3) the Rootwarden, the Greywood's titan (kit/rootwarden.py): rootwarden.glb (the body, the bark
                  plates and their sapwood each its own mesh, the root-arm, the crown of branches, the dead tree, the
                  far mesh), rootwarden_clips.glb, his atlas and the bark's tileable textures
                  rootwarden_bark_{albedo,normal}.png (256 px)
  --wolves        the wolf (kit/quadruped.py, P63): wolf.glb (the wolf with its fur cards, the fur shell's mesh, the
                  far mesh; the dire wolf is it at twice the size), wolf_poses.glb, the atlas (the albedo RGBA: A the
                  cards' strands) and wolf_fur.png (the shell's map: the fur's flow and length)
  --all           every step above
Options:
  --roles=a,b     only these roles (a development run; never with --verify)
  --jobs=N        roles built at once (default 3)
  --verify        regenerate everything into a temporary folder and compare with assets/people/manifest.json (and
                  the creatures' with assets/creatures/manifest.json):
                  bit-exact (the bake is the project's own numpy code and Blender's BVH, no Cycles), and the
                  committed files against the manifest; ends with PEOPLE VERIFY OK or PEOPLE VERIFY FAILED (exit 1)
  --skip-bake     every pass but the expensive one: the ambient occlusion is read back from the committed
                  <role>_orm.png (R); first checks that the expensive pass's inputs still hash to the manifest's
                  (else asks for the full regeneration, check.sh --people-full)
  --budget        estimate the people's shipped Web bytes (gzip then base64, as tools/build_web.sh counts) from
                  the measured rates, and fail over the people's share (plan §2.12: 12.0 MiB at 0.13)
  --out=DIR       write under DIR instead of the repository (DIR/assets/people/...)

Environment: GIANT_VENV's Python; nothing is cached (a full regeneration takes minutes, not hours).
"""
from __future__ import annotations

import fnmatch
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
KIT = HERE / "kit"
sys.path.insert(0, str(KIT))
sys.path.insert(0, str(HERE))
import manifest  # noqa: E402

ASSETS = "assets/people"
REL_MANIFEST = ASSETS + "/manifest.json"
GENERATED_BY = "tools/giant/build_people.py"
SCHEMA_VERSION = 1
STEPS = ("humans", "clips", "gear")
CREATURES = "assets/creatures"
REL_CREATURE_MANIFEST = CREATURES + "/manifest.json"
# the horse's inputs: the quadruped kit and the people's modules it borrows (decimation, unwrap, tangents, export,
# the bake's rasterizer and noise, the palette bands)
HORSE_SOURCES = ("quadruped.py", "people_outfit.py", "people_bake.py", "people_roles.py")
HORSE_FILES = ("horse.glb", "horse_poses.glb", "horse_albedo.png", "horse_normal.png", "horse_orm.png")
# the brutes' inputs (P63): the brute module and every module a person's body, outfit, bake and clips read
BRUTE_SOURCES = ("brute.py", "mh_data.py", "giant_body.py", "giant_garment.py", "giant_parts.py", "giant_hair.py",
                 "split.py", "clips.py", "people_roles.py", "people_body.py", "people_outfit.py", "people_bake.py")


STONEBACK_SOURCES = BRUTE_SOURCES + ("stoneback.py", "stoneback_moves.py")   # A2: his strikes
OGRE_KING_SOURCES = STONEBACK_SOURCES + ("ogre_king.py", "ogre_king_moves.py")   # B2: on Stoneback's helpers
ROOTWARDEN_SOURCES = STONEBACK_SOURCES + ("rootwarden.py", "rootwarden_moves.py")   # B3: on Stoneback's helpers


def _brute_files(kind):
    return (kind + ".glb", kind + "_clips.glb", kind + "_albedo.png", kind + "_normal.png", kind + "_orm.png")


# The creatures' groups: each built by its kit script in its own interpreter (script args + out dir + info dir), its
# files, its inputs (the kit modules it reads; the brutes also the vendored CC0 lists).
CREATURE_GROUPS = {
    "horse": {"script": "quadruped.py", "args": ("horse",), "sources": HORSE_SOURCES, "files": HORSE_FILES},
    "wolf": {"script": "quadruped.py", "args": ("wolf",), "sources": HORSE_SOURCES,
             "files": ("wolf.glb", "wolf_poses.glb", "wolf_albedo.png", "wolf_normal.png", "wolf_orm.png",
                       "wolf_fur.png")},
    "ogre": {"script": "brute.py", "args": ("ogre",), "sources": BRUTE_SOURCES, "files": _brute_files("ogre"),
             "mpfb2": True},
    "troll": {"script": "brute.py", "args": ("troll",), "sources": BRUTE_SOURCES, "files": _brute_files("troll"),
              "mpfb2": True},
    # A1: Stoneback, the quarry titan (kit/stoneback.py on the brutes' modules): his body, plates, shackles, club and
    # boulder, his clips, his atlas and the stone's and the bark's tileable detail textures
    "stoneback": {"script": "stoneback.py", "args": ("stoneback",), "sources": STONEBACK_SOURCES,
                  "files": _brute_files("stoneback") + tuple("stoneback_%s_%s.png" % (w, k) for w in ("stone", "bark")
                                                             for k in ("albedo", "normal")),
                  "mpfb2": True},
    # B2: the Ogre King as a signature titan (kit/ogre_king.py on the brutes' and Stoneback's modules): his body, the
    # trophies each its own mesh, the chain belt, the ram, his clips, his atlas and the oak's tileable textures
    "ogre_king": {"script": "ogre_king.py", "args": ("ogre_king",), "sources": OGRE_KING_SOURCES,
                  "files": _brute_files("ogre_king") + tuple("ogre_king_wood_%s.png" % k for k in ("albedo", "normal")),
                  "mpfb2": True},
    # B3: the Rootwarden, the Greywood's titan (kit/rootwarden.py on the brutes' and Stoneback's modules): his body
    # of bark-skin, the bark plates and their sapwood each its own mesh, the root-arm, the crown of branches, the
    # dead tree he throws, his clips, his atlas and the bark's tileable textures
    "rootwarden": {"script": "rootwarden.py", "args": ("rootwarden",), "sources": ROOTWARDEN_SOURCES,
                   "files": _brute_files("rootwarden") + tuple("rootwarden_bark_%s.png" % k for k in ("albedo", "normal")),
                   "mpfb2": True},
}
CREATURE_ORDER = ("horse", "ogre", "troll", "wolf", "stoneback", "ogre_king", "rootwarden")
CREATURE_STEPS = {"--horse": ("horse",), "--brutes": ("ogre", "troll"), "--wolves": ("wolf",),
                  "--stoneback": ("stoneback",), "--ogre_king": ("ogre_king",), "--rootwarden": ("rootwarden",)}
# every kit module a person's geometry or bake reads (the giant's body, garment and clip code, the people's own)
SOURCES = ("mh_data.py", "giant_body.py", "giant_garment.py", "giant_parts.py", "giant_hair.py", "split.py",
           "clips.py", "people_roles.py", "people_body.py", "people_outfit.py", "people_bake.py")
CLIP_SOURCES = ("mh_data.py", "giant_body.py", "clips.py", "people_roles.py", "people_body.py")
GEAR_SOURCES = ("people_roles.py", "people_outfit.py")
EXPENSIVE_SETTINGS = {"ao": "ray cast", "rays": 24, "reach_m": 0.22}
# plan §2.12: 12.0 from 0.13.0-m13, 14.0 from 0.14.0-m14 (A1b, the owner's raised cap; build_web.sh PEOPLE_SHARE_CAP_MB),
# 16.0 from 0.15.0-m15 (B3: the Rootwarden)
PEOPLE_SHARE_MIB = 16.0
# Measured shipped rates (P59's Web test export of 0.13: gzip -9 of each imported file, then base64; see
# docs/systems/P59.md): a role's scene file per glTF vertex (its variants, crowd poses and far mesh with the
# importer's LODs and shadow meshes and the role's skeletons: mesh data barely compresses), textures per byte of
# VRAM data with mipmaps (the ORM map lossless: 3 bytes a texel), the clips per keyed bone and key.
RATE_VERTEX_B = 43.2
RATE_SKELETON_B = 0.0
RATE_CLIP_B_PER_BONE_KEY = 11.0
TEXTURE_FACTOR = {"albedo": 0.754, "normal": 0.772, "orm": 0.294}
GODOT_VERTEX_SPLIT = 1.0           # the glTF already splits at UV seams


def log(*a):
    print("[build_people]", *a, flush=True)


def source_hashes(names) -> dict:
    return {n: manifest.sha256_file(KIT / n) for n in names}


def mpfb2_hash() -> str:
    return manifest.hash_json({n: manifest.sha256_file(HERE / "mpfb2" / n) for n in ("FILES.sha256", "PEOPLE.sha256")})


def roles():
    import people_roles
    return list(people_roles.ROLE_ORDER)


def expensive_key(tool) -> str:
    return manifest.hash_json({"sources": source_hashes(SOURCES), "mpfb2": mpfb2_hash(), "settings": EXPENSIVE_SETTINGS,
                               "bpy": tool.get("bpy")})[:32]


def load(root: Path) -> dict:
    p = root / REL_MANIFEST
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def save(root: Path, doc: dict) -> Path:
    p = root / REL_MANIFEST
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(manifest.dumps(doc), encoding="utf-8")
    return p


def run_kit(script, *args):
    """A kit script in a fresh interpreter of this venv (Blender state never leaks between roles)."""
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    cmd = [sys.executable, "-B", str(KIT / script)] + [str(a) for a in args]
    t = time.time()
    r = subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        sys.stdout.write(r.stdout[-6000:])
        raise SystemExit("build_people: %s %s failed (exit %d)" % (script, " ".join(map(str, args[:1])), r.returncode))
    return time.time() - t, r.stdout


# --------------------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------------------
def build(steps, out_root: Path, skip_bake=False, only_roles=None, jobs=3, verbose=True) -> dict:
    old = load(out_root) or load(ROOT)
    tool = manifest.toolchain()
    key = expensive_key(tool)
    times = {}
    files = dict(old.get("files", {}))
    doc = {k: old[k] for k in ("roles", "clips", "gear") if k in old}
    assets = out_root / ASSETS
    assets.mkdir(parents=True, exist_ok=True)
    mp = mpfb2_hash()
    with tempfile.TemporaryDirectory(prefix="people_build_") as tmp:
        work = Path(tmp)
        if "humans" in steps:
            if skip_bake:
                old_key = load(ROOT).get("bake", {}).get("expensive_key")
                if old_key != key:
                    raise SystemExit("build_people: the expensive pass's inputs (the people's and the giant's body, "
                                     "garment and clip code, the CC0 lists, the settings) changed since the committed "
                                     "ambient occlusion was ray cast (%s, now %s): run the full regeneration "
                                     "(tools/check.sh --people-full, build_people.py --verify without --skip-bake, "
                                     "or --all)" % (str(old_key)[:12], key[:12]))
            todo = [r for r in roles() if only_roles is None or r in only_roles]
            inputs = manifest.hash_json({"sources": source_hashes(SOURCES), "mpfb2": mp})

            def one(role):
                args = [role, work / "out", work / "info"]
                if skip_bake:
                    orm = ROOT / ASSETS / (role + "_orm.png")
                    if not orm.exists():
                        raise SystemExit("build_people: --skip-bake needs the committed %s" % orm)
                    args.append("--ao-from=%s" % orm)
                secs, _out = run_kit("people_outfit.py", *args)
                return role, secs

            with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
                for role, secs in ex.map(one, todo):
                    times["role " + role] = round(secs, 1)
            roles_doc = dict(doc.get("roles", {}))
            for role in todo:
                info = json.loads((work / "info" / (role + "_info.json")).read_text())
                for k in ("seconds", "times"):
                    info.pop(k, None)
                roles_doc[role] = info
                for name in (role + ".glb", role + "_albedo.png", role + "_normal.png", role + "_orm.png"):
                    shutil.copyfile(work / "out" / name, assets / name)
                    files[ASSETS + "/" + name] = manifest.file_entry(out_root, ASSETS + "/" + name, "humans", inputs,
                                                                     False)
            doc["roles"] = {r: roles_doc[r] for r in roles() if r in roles_doc}
        if "clips" in steps:
            secs, _ = run_kit("people_body.py", work / "clips", work / "clips")
            times["clips"] = round(secs, 1)
            doc["clips"] = json.loads((work / "clips" / "people_clips_info.json").read_text())
            shutil.copyfile(work / "clips" / "people_clips.glb", assets / "people_clips.glb")
            inputs = manifest.hash_json({"sources": source_hashes(CLIP_SOURCES), "mpfb2": mp})
            files[ASSETS + "/people_clips.glb"] = manifest.file_entry(out_root, ASSETS + "/people_clips.glb", "clips",
                                                                      inputs, False)
        if "gear" in steps:
            secs, _ = run_kit("people_outfit.py", "--gear", work / "gear", work / "gear")
            times["gear"] = round(secs, 1)
            doc["gear"] = json.loads((work / "gear" / "gear_info.json").read_text())
            shutil.copyfile(work / "gear" / "gear.glb", assets / "gear.glb")
            inputs = manifest.hash_json({"sources": source_hashes(GEAR_SOURCES)})
            files[ASSETS + "/gear.glb"] = manifest.file_entry(out_root, ASSETS + "/gear.glb", "gear", inputs, False)
    for k in ("roles", "clips", "gear"):
        if k not in doc:
            raise SystemExit("build_people: no %s information yet: run --all first" % k)
    import people_roles as pr
    doc.update({
        "schema_version": SCHEMA_VERSION,
        "generated_by": GENERATED_BY,
        "toolchain": tool,
        "inputs": {"mpfb2": mp, "kit": source_hashes(sorted(set(SOURCES) | set(CLIP_SOURCES) | set(GEAR_SOURCES)))},
        "bake": {"expensive_key": key, "settings": EXPENSIVE_SETTINGS},
        "files": {k: files[k] for k in sorted(files) if (out_root / k).exists()},
        "index": index(doc, pr),
    })
    if verbose:
        log("times: " + json.dumps(times, sort_keys=True))
    doc["_times"] = times
    return doc


def index(doc, pr) -> dict:
    """What the game's PersonModel (P60) reads: per role its scene, maps, variants, poses and far mesh."""
    res = "res://" + ASSETS + "/"
    out = {"bones": list(pr.BONES), "bands": list(pr.BANDS), "band_decode": "int(B * %d.0)" % len(pr.BANDS),
           "height_m": pr.HEIGHT_M, "step_m": pr.STEP_M, "walk_cycle_m": doc["clips"]["cycle_m"],
           "run_cycle_m": doc["clips"]["run_cycle_m"], "tris_max": pr.TRIS_MAX, "pose_tris_max": pr.POSE_TRIS_MAX,
           "far_tris_max": pr.FAR_TRIS_MAX, "poses": list(pr.POSES), "clips": res + "people_clips.glb",
           "gear": res + "gear.glb", "role_order": list(pr.ROLE_ORDER),
           "seat": {"clip": "seated", "origin": "the seat between the sitting bones (place it on the saddle's seat)",
                    "seat_drop_m": pr.SEAT_DROP_M, "stirrup_m": list(pr.STIRRUP_M),
                    "horse": "res://assets/creatures/horse.glb (horse_tacked: saddle_seat, the stirrup irons)"},
           "roles": {}}
    for role, info in doc["roles"].items():
        out["roles"][role] = {
            "scene": res + role + ".glb",
            "albedo": res + role + "_albedo.png", "normal": res + role + "_normal.png", "orm": res + role + "_orm.png",
            "used_by": list(pr.ROLES[role]["used_by"]), "gear": list(pr.ROLES[role]["gear"]),
            "variants": [n for n, _e in sorted(info["variants"].items(), key=lambda kv: kv[1]["index"])],
            "poses": {p: e["node"] for p, e in sorted(info["poses"].items())}, "far": info["far"]["node"]}
    return out


def write(out_root: Path, doc: dict) -> Path:
    doc = {k: v for k, v in doc.items() if not k.startswith("_")}
    path = save(out_root, doc)
    if out_root.resolve() == ROOT.resolve():
        ensure_import_files(out_root, doc)
    return path


# --------------------------------------------------------------------------------------
# import settings: the committed .import files carry them
# --------------------------------------------------------------------------------------
IMPORT_SETTINGS = {
    # a role: its variants skinned (named skins), the importer's LODs, shadow meshes; tangents as exported (the
    # normal map was baked in Blender's MikkTSpace frame, which the glTF carries)
    "role": ("scene", "PackedScene", {"meshes/generate_lods": "true", "meshes/create_shadow_meshes": "true",
                                      "meshes/ensure_tangents": "false", "skins/use_named_skins": "true",
                                      "animation/import": "false"}),
    # A1b: Stoneback, the titan: no importer LODs (a 55 ft figure is seen near; his far mesh stands for the distance,
    # and the LODs of his plates' sharp facets cost the Web share more than they save; no shadow meshes either: the
    # shadows are drawn from the mesh itself)
    "stoneback.glb": ("scene", "PackedScene", {"meshes/generate_lods": "false", "meshes/create_shadow_meshes": "false",
                                               "meshes/ensure_tangents": "false", "skins/use_named_skins": "true",
                                               "animation/import": "false"}),
    # B2: the Ogre King, as Stoneback (a titan seen near; his far mesh for the distance)
    "ogre_king.glb": ("scene", "PackedScene", {"meshes/generate_lods": "false", "meshes/create_shadow_meshes": "false",
                                               "meshes/ensure_tangents": "false", "skins/use_named_skins": "true",
                                               "animation/import": "false"}),
    # B3: the Rootwarden, as Stoneback (a titan seen near; his far mesh for the distance)
    "rootwarden.glb": ("scene", "PackedScene", {"meshes/generate_lods": "false", "meshes/create_shadow_meshes": "false",
                                                "meshes/ensure_tangents": "false", "skins/use_named_skins": "true",
                                                "animation/import": "false"}),
    "gear.glb": ("scene", "PackedScene", {"meshes/generate_lods": "true", "meshes/create_shadow_meshes": "true",
                                          "meshes/ensure_tangents": "true", "animation/import": "false"}),
    "people_clips.glb": ("animation_library", "AnimationLibrary",
                         {"animation/import": "true", "animation/fps": "30", "animation/remove_immutable_tracks": "true"}),
    # the horse's gait extremes: one-frame clips on its 25 bones (a check; P62's QuadrupedRig drives the bones)
    "horse_poses.glb": ("animation_library", "AnimationLibrary",
                        {"animation/import": "true", "animation/fps": "30", "animation/remove_immutable_tracks": "false"}),
}


def import_params(rel: str):
    name = rel.rsplit("/", 1)[-1]
    if name in IMPORT_SETTINGS:
        return IMPORT_SETTINGS[name]
    if name.endswith("_clips.glb"):
        # a brute's clips (P63): as the people's
        return IMPORT_SETTINGS["people_clips.glb"]
    if name.endswith("_poses.glb"):
        return IMPORT_SETTINGS["horse_poses.glb"]
    if name.endswith("_fur.png"):
        # the fur shell's map (P63: the comb direction and the length, data): lossless
        return "texture", "CompressedTexture2D", {"compress/mode": "0", "mipmaps/generate": "true",
                                                   "compress/normal_map": "0"}
    if name.endswith(".glb"):
        return IMPORT_SETTINGS["role"]
    if name.endswith("_orm.png"):
        # the palette band (B) must decode exactly: lossless (a VRAM block's two end colours moved the band at the
        # border of two materials), read by the game with a nearest sampler
        return "texture", "CompressedTexture2D", {"compress/mode": "0", "mipmaps/generate": "true",
                                                   "compress/normal_map": "0"}
    if name.endswith(".png"):
        params = {"compress/mode": "2", "mipmaps/generate": "true",
                  "compress/normal_map": "1" if name.endswith("_normal.png") else "0"}
        return "texture", "CompressedTexture2D", params
    return None


def ensure_import_files(root: Path, doc: dict) -> list:
    changed = []
    for rel in sorted(doc["files"]):
        spec = import_params(rel)
        if spec is None:
            continue
        importer, typ, params = spec
        path = root / (rel + ".import")
        if path.exists():
            text = path.read_text(encoding="utf-8")
            new = text
            for k, v in params.items():
                pat = re.compile(r"^%s=.*$" % re.escape(k), re.M)
                new = pat.sub("%s=%s" % (k, v), new) if pat.search(new) else new.rstrip("\n") + "\n%s=%s\n" % (k, v)
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
def shipped_problems(doc: dict, tree: str = ASSETS) -> list:
    out = []
    for rel, e in sorted(doc.get("files", {}).items()):
        p = ROOT / rel
        if not p.exists():
            out.append("%s: listed in the manifest but missing" % rel)
        elif manifest.sha256_file(p) != e.get("sha256"):
            out.append("%s: the committed file differs from the manifest (edited by hand?)" % rel)
    listed = set(doc.get("files", {}))
    for p in sorted((ROOT / tree).rglob("*")):
        if p.is_dir() or p.suffix == ".import" or p.name in ("manifest.json", "PROVENANCE.md") or p.name.endswith(".uid"):
            continue
        rel = str(p.relative_to(ROOT))
        if rel not in listed:
            out.append("%s: a file under %s that no step wrote" % (rel, tree))
    return out


def verify(skip_bake: bool, jobs: int) -> int:
    expected = load(ROOT)
    if not expected:
        print("PEOPLE VERIFY FAILED: there is no %s" % REL_MANIFEST)
        return 1
    t0 = time.time()
    creatures = ThreadPoolExecutor(max_workers=1)
    pending = creatures.submit(verify_creatures)          # the horse in its own interpreter, beside the roles
    with tempfile.TemporaryDirectory(prefix="people_verify_") as tmp:
        out_root = Path(tmp)
        (out_root / ASSETS).mkdir(parents=True)
        actual = build(list(STEPS), out_root, skip_bake=skip_bake, jobs=jobs, verbose=False)
        tool_diff = manifest.toolchain_diff(expected.get("toolchain", {}), actual["toolchain"])
        content = []
        for rel, e in sorted(expected.get("files", {}).items()):
            a = actual["files"].get(rel)
            if a is None:
                content.append("%s: in the manifest but not regenerated" % rel)
            elif a["sha256"] != e["sha256"]:
                content.append("%s: regenerated %s, manifest %s" % (rel, a["sha256"][:12], e["sha256"][:12]))
        for rel in sorted(set(actual["files"]) - set(expected.get("files", {}))):
            content.append("%s: regenerated but not in the manifest" % rel)
        content += ["manifest " + d for d in manifest.doc_diff(
            {k: v for k, v in expected.items() if k not in ("bake",)},
            {k: v for k, v in actual.items() if k not in ("bake", "_times")}, skip=("toolchain", "files", "inputs"))]
        if expected.get("bake", {}).get("expensive_key") != actual["bake"]["expensive_key"]:
            content.append("bake inputs: the expensive pass's key changed")
        if expected.get("inputs") != actual["inputs"]:
            for k in sorted(set(expected.get("inputs", {}).get("kit", {})) | set(actual["inputs"]["kit"])):
                if expected.get("inputs", {}).get("kit", {}).get(k) != actual["inputs"]["kit"].get(k):
                    content.append("inputs: kit/%s changed since the manifest was written" % k)
            if expected.get("inputs", {}).get("mpfb2") != actual["inputs"]["mpfb2"]:
                content.append("inputs: the vendored CC0 file lists changed")
        times = actual.get("_times", {})
    shipped = shipped_problems(expected)
    c_content, c_shipped, c_tool, c_n = pending.result()
    creatures.shutdown()
    content += c_content
    shipped += c_shipped
    tool_diff = sorted(set(tool_diff) | set(c_tool))
    for line in tool_diff:
        print("TOOLCHAIN DIFFERS: " + line)
    for line in content:
        print("CONTENT DIFFERS: " + line)
    for line in shipped:
        print("SHIPPED FILE: " + line)
    n = len(expected.get("files", {})) + c_n
    mode = "every pass but the ambient occlusion, read from the committed maps" if skip_bake else "every pass"
    print("PEOPLE VERIFY TIMES: %s (%.0f s in all)" % (json.dumps(times, sort_keys=True), time.time() - t0))
    if content or shipped:
        if tool_diff:
            print("note: the toolchain differs from the reference recorded in the manifest: regenerate on the "
                  "reference toolchain")
        print("PEOPLE VERIFY FAILED: %d content differences, %d shipped-file problems (of %d files; %s)" % (
            len(content), len(shipped), n, mode))
        return 1
    print("PEOPLE VERIFY OK: %d files regenerated bit-exact (%s)%s" % (
        n, mode, " (toolchain differs: %d keys)" % len(tool_diff) if tool_diff else ""))
    return 0


# --------------------------------------------------------------------------------------
# the creatures (P61: the horse; P63: the wolves and the brutes)
# --------------------------------------------------------------------------------------
def load_creatures(root: Path) -> dict:
    p = root / REL_CREATURE_MANIFEST
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else {}


def creature_inputs(group: str) -> str:
    g = CREATURE_GROUPS[group]
    doc = {"sources": source_hashes(g["sources"])}
    if g.get("mpfb2"):
        doc["mpfb2"] = mpfb2_hash()
    return manifest.hash_json(doc)


def creature_sources() -> tuple:
    return tuple(sorted({n for g in CREATURE_GROUPS.values() for n in g["sources"]}))


def _creature_index(group: str, info: dict) -> dict:
    res = "res://" + CREATURES + "/"
    if group == "horse":
        return {"horse": {"scene": res + "horse.glb", "poses": res + "horse_poses.glb",
                          "albedo": res + "horse_albedo.png", "normal": res + "horse_normal.png",
                          "orm": res + "horse_orm.png", "meshes": {"bare": "horse", "tacked": "horse_tacked"},
                          "bones": info["bones"], "landmarks": info["landmarks"], "poses_order": info["pose_order"],
                          "bands": info["atlas"]["materials"], "band_decode": "int(B * 5.0)",
                          "tris_max": 6000, "used_by": ["enemy.cavalry (P62)"]}}
    if group == "wolf":
        return {"wolf": {"scene": res + "wolf.glb", "poses": res + "wolf_poses.glb",
                         "albedo": res + "wolf_albedo.png", "normal": res + "wolf_normal.png",
                         "orm": res + "wolf_orm.png", "fur": res + "wolf_fur.png",
                         "meshes": info["meshes"], "bones": info["bones"], "landmarks": info["landmarks"],
                         "poses_order": info["pose_order"], "bands": info["atlas"]["materials"],
                         "band_decode": "int(B * 5.0)", "palettes": info["palettes"], "sizes": info["sizes"],
                         "shell": info["shell"], "tris_max": 6000, "used_by": ["enemy.wolf", "enemy.dire_wolf"]}}
    if group == "stoneback":
        v = info["variants"]["stoneback"]
        return {"stoneback": {"scene": res + "stoneback.glb", "clips": res + "stoneback_clips.glb",
                              "albedo": res + "stoneback_albedo.png", "normal": res + "stoneback_normal.png",
                              "orm": res + "stoneback_orm.png",
                              **{"%s_%s" % (w, k): res + "stoneback_%s_%s.png" % (w, k) for w in ("stone", "bark")
                                 for k in ("albedo", "normal")},
                              "bones": list(__import__("people_roles").BONES),
                              "variants": {"stoneback": {"node": "stoneback", "far": v["far"]["node"],
                                                         "game_height_m": v["game_height_m"],
                                                         "game_scale": v["game_scale"],
                                                         **{k: v[k] for k in ("grip_local_r", "grip_axis_r",
                                                                              "grip_local_l", "grip_axis_l")}}},
                              "pieces": info["pieces"], "plates": info["plates"], "weak_points": info["weak_points"],
                              "clips_order": list(info["clips"]["clips"]), "detail_tile_m": info["detail_tile_m"],
                              "band_decode": "int(B * 5.0)", "tris_max": info["tris_max"], "used_by": info["used_by"]}}
    if group == "ogre_king":
        v = info["variants"]["ogre_king"]
        return {"ogre_king": {"scene": res + "ogre_king.glb", "clips": res + "ogre_king_clips.glb",
                              "albedo": res + "ogre_king_albedo.png", "normal": res + "ogre_king_normal.png",
                              "orm": res + "ogre_king_orm.png", "wood_albedo": res + "ogre_king_wood_albedo.png",
                              "wood_normal": res + "ogre_king_wood_normal.png",
                              "bones": list(__import__("people_roles").BONES),
                              "variants": {"ogre_king": {"node": "ogre_king", "far": v["far"]["node"],
                                                         "game_height_m": v["game_height_m"],
                                                         "game_scale": v["game_scale"],
                                                         "height_with_crown_m": v["height_with_crown_m"],
                                                         **{k: v[k] for k in ("grip_local_r", "grip_axis_r",
                                                                              "grip_local_l", "grip_axis_l")}}},
                              "pieces": info["pieces"], "trophies": info["trophies"],
                              "clips_order": list(info["clips"]["clips"]), "clip_keys": info["clips"]["keys"],
                              "detail_tile_m": info["detail_tile_m"], "band_decode": "int(B * 5.0)",
                              "tris_max": info["tris_max"], "used_by": info["used_by"]}}
    if group == "rootwarden":
        v = info["variants"]["rootwarden"]
        return {"rootwarden": {"scene": res + "rootwarden.glb", "clips": res + "rootwarden_clips.glb",
                               "albedo": res + "rootwarden_albedo.png", "normal": res + "rootwarden_normal.png",
                               "orm": res + "rootwarden_orm.png", "bark_albedo": res + "rootwarden_bark_albedo.png",
                               "bark_normal": res + "rootwarden_bark_normal.png",
                               "bones": list(__import__("people_roles").BONES),
                               "variants": {"rootwarden": {"node": "rootwarden", "far": v["far"]["node"],
                                                           "game_height_m": v["game_height_m"],
                                                           "game_scale": v["game_scale"],
                                                           "height_with_antlers_m": v["height_with_antlers_m"],
                                                           **{k: v[k] for k in ("grip_local_r", "grip_axis_r",
                                                                                "grip_local_l", "grip_axis_l")}}},
                               "pieces": info["pieces"], "plates": info["plates"], "weak_points": info["weak_points"],
                               "clips_order": list(info["clips"]["clips"]), "clip_keys": info["clips"]["keys"],
                               "detail_tile_m": info["detail_tile_m"], "glow_alpha": info["glow_alpha"],
                               "band_decode": "int(B * 5.0)", "tris_max": info["tris_max"], "used_by": info["used_by"]}}
    return {group: {"scene": res + group + ".glb", "clips": res + group + "_clips.glb",
                    "albedo": res + group + "_albedo.png", "normal": res + group + "_normal.png",
                    "orm": res + group + "_orm.png", "bones": list(__import__("people_roles").BONES),
                    "variants": {n: {"node": n, "far": v["far"]["node"], "game_height_m": v["game_height_m"],
                                     "game_scale": v["game_scale"], "reach_bands": v["reach_bands"],
                                     **{k: v[k] for k in ("grip_local_r", "grip_axis_r", "grip_local_l", "grip_axis_l")
                                        if k in v}}
                                 for n, v in info["variants"].items()},
                    "gear": info["gear"], "clips_order": list(info["clips"]["clips"]),
                    "band_decode": "int(B * 5.0)", "tris_max": info["tris_max"], "used_by": info["used_by"]}}


def _build_group(group: str, out_dir: Path, info_dir: Path) -> tuple:
    g = CREATURE_GROUPS[group]
    secs, _ = run_kit(g["script"], *g["args"], out_dir, info_dir)
    return group, secs, json.loads((info_dir / (group + "_info.json")).read_text())


def build_creatures(out_root: Path, groups=None, verbose=True, jobs=3) -> dict:
    """The creatures (each group's kit script in its own interpreter, ``jobs`` at once) into
    <out_root>/assets/creatures/ and its manifest; groups not built keep their manifest entries (from <out_root>'s
    manifest, else the repository's)."""
    old = load_creatures(out_root) or load_creatures(ROOT)
    groups = list(groups or CREATURE_ORDER)
    files = dict(old.get("files", {}))
    facts = {k: old[k] for k in CREATURE_ORDER if k in old}
    index = dict(old.get("index", {}))
    assets = out_root / CREATURES
    assets.mkdir(parents=True, exist_ok=True)
    times = {}
    with tempfile.TemporaryDirectory(prefix="creatures_build_") as tmp:
        work = Path(tmp)
        with ThreadPoolExecutor(max_workers=max(1, jobs)) as ex:
            done = list(ex.map(lambda gr: _build_group(gr, work / "out", work / "info"), groups))
        for group, secs, info in done:
            times[group] = round(secs, 1)
            for k in ("times", "seconds"):           # a build's own timings are not its content (verify compares it)
                info.pop(k, None)
            inputs = creature_inputs(group)
            for name in CREATURE_GROUPS[group]["files"]:
                shutil.copyfile(work / "out" / name, assets / name)
                files[CREATURES + "/" + name] = manifest.file_entry(out_root, CREATURES + "/" + name, group, inputs,
                                                                     False)
            facts[group] = info
            for k in [k for k, v in index.items() if k == group]:
                index.pop(k)
            index.update(_creature_index(group, info))
    doc = {
        "schema_version": SCHEMA_VERSION,
        "generated_by": GENERATED_BY,
        "toolchain": manifest.toolchain(),
        "inputs": {"kit": source_hashes(creature_sources()), "mpfb2": mpfb2_hash()},
        "files": {k: files[k] for k in sorted(files) if (out_root / k).exists()},
        "index": {k: index[k] for k in CREATURE_ORDER if k in index},
    }
    for k in CREATURE_ORDER:
        if k in facts:
            doc[k] = facts[k]
    if verbose:
        log("creatures times: " + json.dumps(times, sort_keys=True))
    doc["_times"] = times
    return doc


def write_creatures(out_root: Path, doc: dict) -> Path:
    doc = {k: v for k, v in doc.items() if not k.startswith("_")}
    p = out_root / REL_CREATURE_MANIFEST
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(manifest.dumps(doc), encoding="utf-8")
    if out_root.resolve() == ROOT.resolve():
        ensure_import_files(out_root, doc)
    return p


def verify_creatures() -> tuple:
    """(content differences, shipped-file problems, toolchain differences, files) of the creatures' tree."""
    expected = load_creatures(ROOT)
    if not expected:
        return [], [], [], 0
    with tempfile.TemporaryDirectory(prefix="creatures_verify_") as tmp:
        out_root = Path(tmp)
        actual = build_creatures(out_root, verbose=False)
    content = []
    for rel, e in sorted(expected.get("files", {}).items()):
        a = actual["files"].get(rel)
        if a is None:
            content.append("%s: in the manifest but not regenerated" % rel)
        elif a["sha256"] != e["sha256"]:
            content.append("%s: regenerated %s, manifest %s" % (rel, a["sha256"][:12], e["sha256"][:12]))
    for rel in sorted(set(actual["files"]) - set(expected.get("files", {}))):
        content.append("%s: regenerated but not in the manifest" % rel)
    content += ["creatures manifest " + d for d in manifest.doc_diff(
        expected, {k: v for k, v in actual.items() if k != "_times"}, skip=("toolchain", "files", "inputs"))]
    if expected.get("inputs") != actual["inputs"]:
        content.append("creatures inputs: a kit module changed since the manifest was written")
    tool = manifest.toolchain_diff(expected.get("toolchain", {}), actual["toolchain"])
    return content, shipped_problems(expected, CREATURES), tool, len(expected.get("files", {}))


# --------------------------------------------------------------------------------------
# budget
# --------------------------------------------------------------------------------------
def web_excluded(root: Path = ROOT, preset: str = "Web") -> list:
    text = (root / "export_presets.cfg").read_text()
    for section in re.split(r"(?m)^\[preset\.\d+\]\s*$", text)[1:]:
        if re.search(r'(?m)^name="%s"\s*$' % re.escape(preset), section):
            m = re.search(r'(?m)^exclude_filter="([^"]*)"', section)
            return [f.strip() for f in m.group(1).split(",") if f.strip()] if m else []
    return []


def glb_vertices(path: Path) -> tuple:
    """(glTF vertices of every primitive, skins) of a .glb."""
    import struct
    data = path.read_bytes()
    n = struct.unpack_from("<I", data, 12)[0]
    js = json.loads(data[20:20 + n])
    verts = sum(js["accessors"][p["attributes"]["POSITION"]]["count"] for m in js["meshes"] for p in m["primitives"])
    return verts, len(js.get("skins", []))


def estimate(rel: str, doc: dict, cdoc: dict | None = None) -> float:
    name = rel.rsplit("/", 1)[-1]
    p = ROOT / rel
    if name == "people_clips.glb":
        return RATE_CLIP_B_PER_BONE_KEY * sum(c["bones"] * (c["frames"] + 1) for c in doc["clips"]["clips"].values())
    if name.endswith("_clips.glb") and cdoc and name[:-len("_clips.glb")] in cdoc:
        clips = cdoc[name[:-len("_clips.glb")]]["clips"]["clips"]
        return RATE_CLIP_B_PER_BONE_KEY * sum(c["bones"] * (c["frames"] + 1) for c in clips.values())
    if name.endswith(".glb"):
        v, skins = glb_vertices(p)
        return v * GODOT_VERTEX_SPLIT * RATE_VERTEX_B + skins * RATE_SKELETON_B
    if name.endswith(".png"):
        from PIL import Image
        with Image.open(p) as im:
            w, h = im.size
            alpha = im.mode == "RGBA"
        kind = name.rsplit("_", 1)[-1][:-4]
        bpt = 1.0 if kind == "normal" else (3.0 if kind == "orm" else 0.5)     # the ORM map lossless
        if kind == "albedo" and alpha:
            bpt = 1.0                                                           # with alpha: a 16-byte block
        return w * h * bpt * 4.0 / 3.0 * TEXTURE_FACTOR.get(kind, 0.8)
    if name == "manifest.json" or rel == REL_CREATURE_MANIFEST:
        return p.stat().st_size * 0.25 * 4.0 / 3.0
    return 0.0


def budget(share_mib: float | None = None) -> int:
    doc = load(ROOT)
    if not doc:
        print("build_people: no manifest yet")
        return 1
    share = PEOPLE_SHARE_MIB if share_mib is None else share_mib
    excluded = web_excluded()
    total = 0.0
    rels = sorted(doc["files"]) + [REL_MANIFEST]
    cdoc = load_creatures(ROOT)
    if cdoc:
        rels += sorted(cdoc["files"]) + [REL_CREATURE_MANIFEST]
    for rel in rels:
        if any(fnmatch.fnmatch(rel, pat) for pat in excluded):
            print("WEB_EXCLUDED %s" % rel)
            continue
        b = estimate(rel, doc, cdoc)
        total += b
        print("ESTIMATE %-44s %9.0f bytes shipped" % (rel, b))
    mib = total / 1048576.0
    nvar = sum(len(r["variants"]) for r in doc["roles"].values())
    print("PEOPLE_ESTIMATE shipped_mib=%.2f cap_mib=%.2f variants=%d (the real share: tools/build_web.sh's PEOPLE_SHARE "
          "line)" % (mib, share, nvar))
    if mib > share:
        print("OVER BUDGET: the people's files are estimated at %.2f MiB shipped, over %.2f MiB" % (mib, share))
        return 1
    return 0


# --------------------------------------------------------------------------------------
def main(argv) -> int:
    steps, out, verify_mode, skip, do_budget, only, jobs, share = [], None, False, False, False, None, 3, None
    cgroups = []
    flags = {"--humans": "humans", "--clips": "clips", "--gear": "gear"}
    for a in argv:
        if a in flags:
            if flags[a] not in steps:
                steps.append(flags[a])
        elif a in CREATURE_STEPS:
            cgroups += [g for g in CREATURE_STEPS[a] if g not in cgroups]
        elif a == "--all":
            steps = list(STEPS)
            cgroups = list(CREATURE_ORDER)
        elif a == "--verify":
            verify_mode = True
        elif a == "--skip-bake":
            skip = True
        elif a == "--budget":
            do_budget = True
        elif a.startswith("--roles="):
            only = [r for r in a.split("=", 1)[1].split(",") if r]
        elif a.startswith("--jobs="):
            jobs = int(a.split("=", 1)[1])
        elif a.startswith("--share-mib="):
            share = float(a.split("=", 1)[1])
        elif a.startswith("--out="):
            out = Path(a.split("=", 1)[1]).resolve()
        elif a in ("-h", "--help"):
            print(__doc__)
            return 0
        else:
            print("build_people.py: unknown option %s" % a, file=sys.stderr)
            return 2
    if verify_mode:
        if only:
            print("build_people.py: --roles is for development runs, not --verify", file=sys.stderr)
            return 2
        return verify(skip, jobs)
    if do_budget and not steps and not cgroups:
        return budget(share)
    out_root = out or ROOT
    if cgroups:
        cdoc = build_creatures(out_root, [g for g in CREATURE_ORDER if g in cgroups], jobs=jobs)
        path = write_creatures(out_root, cdoc)
        log("wrote %d files; manifest %s" % (len(cdoc["files"]), path))
        if not steps:
            return budget(share) if do_budget else 0
    steps = steps or list(STEPS)
    doc = build(steps, out_root, skip_bake=skip, only_roles=only, jobs=jobs)
    path = write(out_root, doc)
    log("wrote %d files; manifest %s" % (len(doc["files"]), path))
    return budget(share) if do_budget else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
