#!/usr/bin/env python3
"""Tests of the giant pipeline's tools (tools/check.sh --giant runs them before
build_giant.py --verify --skip-bake). Run with the shared venv:

  $GIANT_VENV/bin/python -B tools/giant/test_giant_tools.py

They read the committed outputs (assets/giant/) and exercise the pure parts of the kit on synthetic
data: the per-channel resize, the region encoding, the caps (no open cut on Body_Limbs or on any limb
garment part), the packing rule, the design generator's determinism, the --skip-bake read-back of AO
and thickness, the manifest round trip, the Cycles tolerance on another toolchain, the Web budget's
estimate rules and the vendored subset's file list; P43: the clips (every clip in giant_clips.glb on the
model's bones, the gaits' stride within 5 % of the brain's 3.2 m a cycle, no planted foot sliding).

P48 (plan M11 §3.1): the freeze (the body's positions, normals, UVs, region ids and weights, the 53
bones and M10's nine clips against fixtures/m10_freeze.json, read once from the 0.10.0-m10 files); the
leaf bones (71 joints, no body vertex on one); every card's root on head; the build weights (within
0..1, the same left and right within 2/255, nothing on the head); the parts (the index, the manifest
and the files agree; giant.glb holds the body, the eyes and the shadow proxy alone); the free cape on
its chains; the clips II within their rows.
"""
from __future__ import annotations

import json
import os
import struct
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(HERE, "kit"))
sys.path.insert(0, HERE)

import numpy as np  # noqa: E402
from PIL import Image  # noqa: E402

import designs  # noqa: E402
import freeze  # noqa: E402
import manifest  # noqa: E402
import pack  # noqa: E402
import split  # noqa: E402

ASSETS = os.path.join(ROOT, "assets", "giant")
LIMB_PARTS_OF = ("_limbs",)
WHOLE_LIMB_GARMENTS = ("Garment_bracers", "Garment_boots")


# --------------------------------------------------------------------------------------
# a minimal glTF binary reader (positions, indices, colours, skins)
# --------------------------------------------------------------------------------------
COMPONENT = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, length = struct.unpack_from("<4sII", data, 0)
    assert magic == b"glTF" and version == 2, "not a glTF 2 binary"
    pos = 12
    doc, binary = None, b""
    while pos < length:
        clen, ctype = struct.unpack_from("<I4s", data, pos)
        chunk = data[pos + 8: pos + 8 + clen]
        if ctype == b"JSON":
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = chunk
        pos += 8 + clen
    return doc, binary


def accessor(doc, binary, i):
    acc = doc["accessors"][i]
    bv = doc["bufferViews"][acc["bufferView"]]
    dt = np.dtype(COMPONENT[acc["componentType"]])
    width = WIDTH[acc["type"]]
    start = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride", 0) or dt.itemsize * width
    count = acc["count"]
    raw = np.frombuffer(binary, np.uint8, count=stride * (count - 1) + dt.itemsize * width, offset=start)
    rows = np.lib.stride_tricks.as_strided(raw, shape=(count, dt.itemsize * width), strides=(stride, 1))
    out = np.frombuffer(rows.copy().tobytes(), dt).reshape(count, width)
    if acc.get("normalized"):
        out = out.astype(np.float64) / float(np.iinfo(dt).max)
    return out


def glb_skins(path):
    """{node name: {"P", "UV", "C", "W": {bone: (n,)}}} of every skinned mesh node, and the joints' names."""
    doc, binary = read_glb(path)
    out = {}
    joints = [doc["nodes"][j]["name"] for j in doc["skins"][0]["joints"]] if doc.get("skins") else []
    for node in doc["nodes"]:
        if "mesh" not in node:
            continue
        prims = doc["meshes"][node["mesh"]]["primitives"]
        at = prims[0]["attributes"]
        P = accessor(doc, binary, at["POSITION"]).astype(np.float64)
        J = accessor(doc, binary, at["JOINTS_0"]).astype(np.int64)
        Wt = accessor(doc, binary, at["WEIGHTS_0"]).astype(np.float64)
        W = {}
        for k in range(J.shape[1]):
            for j in np.unique(J[:, k][Wt[:, k] > 0]):
                W.setdefault(joints[j], np.zeros(len(P)))[J[:, k] == j] += Wt[:, k][J[:, k] == j]
        out[node["name"]] = {"P": P, "W": W,
                             "UV": accessor(doc, binary, at["TEXCOORD_0"]) if "TEXCOORD_0" in at else None,
                             "C": accessor(doc, binary, at["COLOR_0"]) if "COLOR_0" in at else None,
                             "tris": int(doc["accessors"][prims[0]["indices"]]["count"]) // 3}
    return out, joints


def glb_meshes(path):
    """{node name: {"P": (n, 3), "T": (m, 3), "C": colours or None}} of every mesh node."""
    doc, binary = read_glb(path)
    out = {}
    for node in doc["nodes"]:
        if "mesh" not in node:
            continue
        mesh = doc["meshes"][node["mesh"]]
        Ps, Ts, Cs, off = [], [], [], 0
        for prim in mesh["primitives"]:
            P = accessor(doc, binary, prim["attributes"]["POSITION"]).astype(np.float64)
            T = accessor(doc, binary, prim["indices"]).reshape(-1, 3).astype(np.int64) + off
            C = accessor(doc, binary, prim["attributes"]["COLOR_0"]) if "COLOR_0" in prim["attributes"] else None
            Ps.append(P)
            Ts.append(T)
            Cs.append(C)
            off += len(P)
        out[node["name"]] = {"P": np.concatenate(Ps), "T": np.concatenate(Ts),
                             "C": None if any(c is None for c in Cs) else np.concatenate(Cs)}
    return out, doc


def all_meshes():
    """Every mesh of the giant: giant.glb's and every part's (P48: a glTF a part)."""
    meshes, _ = glb_meshes(os.path.join(ASSETS, "giant.glb"))
    parts = os.path.join(ASSETS, "parts")
    for name in sorted(os.listdir(parts)) if os.path.isdir(parts) else []:
        if name.endswith(".glb"):
            meshes.update(glb_meshes(os.path.join(parts, name))[0])
    return meshes


class ResizeTest(unittest.TestCase):
    def test_per_channel_resize_keeps_every_channel(self):
        """Pillow's RGBA resize premultiplies by alpha: a design in R where A is 0 vanishes. The
        pipeline resizes one channel at a time and keeps it (the research's broken 512 px masks)."""
        a = np.zeros((64, 64, 4), np.uint8)
        a[8:40, 8:40, 0] = 255          # a design in R ...
        a[30:60, 30:60, 3] = 200        # ... and another in A, mostly elsewhere
        naive = np.asarray(Image.fromarray(a, "RGBA").resize((32, 32), Image.LANCZOS))
        ours = pack.resize_channels(a, 32)
        self.assertEqual(ours.shape, (32, 32, 4))
        lit = lambda x, c: int((x[..., c] > 128).sum())  # noqa: E731
        self.assertGreater(lit(ours, 0), 200, "R survives the per-channel resize")
        self.assertGreater(lit(ours, 3), 150, "and so does A")
        self.assertLess(lit(naive, 0), lit(ours, 0) // 2, "the RGBA resize loses R where A is 0 (the regression)")


class RegionTest(unittest.TestCase):
    def test_region_ids_decode_with_truncation(self):
        ids = np.arange(16)
        enc = split.encode_region(ids)
        self.assertTrue(np.array_equal(split.decode_region(enc), ids))
        # Godot keeps vertex colours as 8-bit values: the round trip still decodes exactly
        q8 = np.round(enc * 255.0) / 255.0
        self.assertTrue(np.array_equal(split.decode_region(q8), ids))
        # Blender's byte colours are stored as sRGB bytes and exported linear (the export's path)
        srgb = np.where(enc <= 0.0031308, enc * 12.92, 1.055 * enc ** (1 / 2.4) - 0.055)
        back = np.round(srgb * 255.0) / 255.0
        lin = np.where(back <= 0.04045, back / 12.92, ((back + 0.055) / 1.055) ** 2.4)
        self.assertTrue(np.array_equal(split.decode_region(lin), ids))
        # rounding instead of truncation would be wrong (the creator brief's finding)
        self.assertFalse(np.array_equal(np.round(lin * 16.0).astype(int), ids))

    def test_exported_body_parts_carry_only_their_regions(self):
        meshes, _ = glb_meshes(os.path.join(ASSETS, "giant.glb"))
        for part, mesh in split.PART_MESH.items():
            m = meshes[mesh]
            self.assertIsNotNone(m["C"], "%s has COLOR_0" % mesh)
            r = set(np.unique(split.decode_region(m["C"][:, 0])).tolist())
            self.assertEqual(r, set(split.PART_REGIONS[part]) | {split.CAP_REGION}, mesh)


class CapTest(unittest.TestCase):
    def test_a_capped_tube_is_closed(self):
        """A tube cut in two: both halves capped by split.fan_cap are closed (pure numpy)."""
        seg, rings = 12, 6
        P = np.array([(np.cos(2 * np.pi * s / seg), np.sin(2 * np.pi * s / seg), z) for z in range(rings)
                      for s in range(seg)], float)
        faces = [(r * seg + s, r * seg + (s + 1) % seg, (r + 1) * seg + (s + 1) % seg, (r + 1) * seg + s)
                 for r in range(rings - 1) for s in range(seg)]
        part = np.array([0 if f[0] // seg < 2 else 1 for f in faces])
        for p in (0, 1):
            sel = [f for f, q in zip(faces, part) if q == p]
            cuts = [e for e in split.cut_edges(np.asarray(faces), part).tolist()]
            loops, chains, pinches = split.walk_loops(np.asarray(cuts))
            self.assertEqual((len(loops), chains, pinches), (1, [], []))
            loop = split.orient_loop(loops[0], sel)
            c, tris, nrm = split.fan_cap(loop, P)
            Q = np.vstack([P, c])
            tri = [t for f in sel for t in ((f[0], f[1], f[2]), (f[0], f[2], f[3]))]
            tri += [(b, a, len(P)) for b, a, _c in tris]
            open_edges = split.boundary_edges(np.asarray(tri))
            # the tube's far end stays open: only the other ring is a boundary
            far = 0 if p == 0 else rings - 1
            self.assertTrue(all(e[0] // seg == far and e[1] // seg == far for e in open_edges.tolist()),
                            "the cut is closed, only the tube's own end is open")
            self.assertEqual(len(open_edges), seg)
            # the cap faces away from its own half
            self.assertGreater(float(nrm[2]) * (1 if p == 0 else -1), 0.9)

    def test_body_limbs_and_limb_garment_parts_have_no_open_cut(self):
        meshes = all_meshes()
        limbs = meshes["Body_Limbs"]
        weld = split.weld_positions(limbs["P"], 1e-5)
        self.assertEqual(len(split.boundary_edges(limbs["T"], weld)), 0, "Body_Limbs is closed")
        info_meshes = manifest.load(ROOT)["export"]["meshes"]
        # P54: every garment drawn with the limbs (a split garment's _limbs part and the whole limb garments)
        names = [n for n in meshes if n.startswith("Garment_") and (n.endswith(LIMB_PARTS_OF) or n in WHOLE_LIMB_GARMENTS
                                                                     or info_meshes.get(n, {}).get("part") == "limbs")]
        self.assertGreaterEqual(len(names), 12, "the limb garment parts: %s" % names)
        for name in names:
            m = meshes[name]
            weld = split.weld_positions(m["P"], 1e-5)
            open_edges = split.boundary_edges(m["T"], weld)
            cap = np.zeros(len(m["P"]), bool)
            if m["C"] is not None:
                cap = split.decode_region(m["C"][:, 0]) == split.CAP_REGION
            cap_points = {tuple(np.round(p / 1e-5).astype(np.int64)) for p in m["P"][cap]}
            on_cut = [e for e in open_edges.tolist()
                      if tuple(np.round(m["P"][e[0]] / 1e-5).astype(np.int64)) in cap_points
                      and tuple(np.round(m["P"][e[1]] / 1e-5).astype(np.int64)) in cap_points]
            self.assertEqual(on_cut, [], "%s: every cut is capped (open edges are hems only)" % name)
        info = manifest.load(ROOT)["export"]["meshes"]
        for name, e in info.items():
            if "cut_loops" in e:
                self.assertEqual(e["caps"], e["cut_loops"], "%s: every cut loop capped" % name)
                self.assertEqual(e["open_chains"], 0, "%s: no open cut chain" % name)


class DesignTest(unittest.TestCase):
    def test_the_packing_rule_holds_in_every_layer(self):
        doc = manifest.load(ROOT)
        placed = {d: (v["layer"], v["channel"]) for d, v in doc["index"]["designs"].items()}
        cat = {d: (v["kind"], tuple(v["regions"])) for d, v in doc["index"]["designs"].items()}
        self.assertEqual(designs.check_rule(placed, cat), [])
        self.assertEqual(set(placed), set(designs.CATALOGUE), "every floor design is placed")
        # in the pixels: no texel carries two designs in R, G and B
        img = np.asarray(Image.open(os.path.join(ASSETS, "designs.png")).convert("RGBA"))
        layers = img.shape[0] // designs.LAYER_SIZE
        self.assertEqual(layers, doc["index"]["textures"]["design_layers"])
        for li in range(layers):
            ly = img[li * designs.LAYER_SIZE:(li + 1) * designs.LAYER_SIZE]
            both = ((ly[..., :3] > 24).sum(axis=-1) > 1).sum()
            self.assertEqual(int(both), 0, "layer %d: no texel lit in two of R, G and B" % li)
        # the scars fill layers of their own, four a layer (P46: the fifth and sixth on a second one; P56: the ten share
        # the two layers' channels by region, the skin shader's scar_regions)
        scar_layers = {placed[d][0] for d in designs.SCAR_ORDER}
        self.assertEqual(len(scar_layers), designs.SCAR_LAYERS)
        self.assertEqual(scar_layers, {0, 1})
        self.assertTrue(all(placed[d][0] not in scar_layers for d in placed if cat[d][0] != "scar"))

    def test_pack_respects_the_rule_on_crowded_regions(self):
        many = {"d%02d" % i: ("tattoo", (i % 3, 7)) for i in range(9)}
        many.update({s: ("scar", (10 + i,)) for i, s in enumerate(designs.SCAR_ORDER)})
        placed = designs.pack(many)
        self.assertEqual(designs.check_rule(placed, many), [])
        self.assertEqual(placed, designs.pack(many), "deterministic")

    def test_the_design_generator_is_deterministic(self):
        """Every design drawn twice on the same synthetic texels gives the same bytes."""
        bd = designs.body_frame()
        import mh_data as mh
        V = bd.verts[: mh.N_BODY_VERTS]
        rng = np.random.default_rng(1)
        pick = rng.choice(len(V), 6000, replace=False)
        P = V[pick] + rng.normal(scale=0.002, size=(6000, 3))
        N = rng.normal(size=(6000, 3))
        N /= np.linalg.norm(N, axis=1, keepdims=True)
        region = rng.integers(0, 16, 6000)
        valid = np.ones(6000, bool)
        a = designs.draw_all(P, N, region, valid, bd)
        b = designs.draw_all(P, N, region, valid, bd)
        self.assertEqual(sorted(a), sorted(designs.CATALOGUE))
        for d in a:
            self.assertEqual(a[d].tobytes(), b[d].tobytes(), d)


class SkipBakeTest(unittest.TestCase):
    def test_ao_and_thickness_read_back_reproduce_the_pack(self):
        """The full pack writes AO and thickness losslessly into tex_hi/orm.png's R and B, so a pack
        that reads them back (--skip-bake) gives the same bytes."""
        rng = np.random.default_rng(7)
        with tempfile.TemporaryDirectory() as tmp:
            bake = os.path.join(tmp, "bake")
            os.makedirs(bake)
            s = 64
            for name, mode in (("albedo.png", "RGB"), ("normal.png", "RGB"), ("masks_rgb.png", "RGB"),
                               ("masks2_rgb.png", "RGB")):
                Image.fromarray(rng.integers(0, 256, (s, s, 3), dtype=np.uint8), mode).save(os.path.join(bake, name))
            for name in ("rough.png", "ao.png", "thick.png"):
                Image.fromarray(rng.integers(0, 256, (s, s), dtype=np.uint8), "L").save(os.path.join(bake, name))
            yy, xx = np.mgrid[0:s, 0:s] / s
            sphere = np.stack([np.cos(xx * 6.28), np.sin(xx * 6.28), yy], axis=-1).astype(np.float32)
            np.save(os.path.join(bake, "restpos.npy"), sphere * 0.1)
            np.save(os.path.join(bake, "restnrm.npy"), (sphere * [1, 1, 0] + 1) / 2)
            old = (pack.LO, pack.HI, pack.CURV_SIZE)
            pack.LO = 32
            pack.CURV_SIZE = 32
            try:
                full = os.path.join(tmp, "full")
                pack.pack_tiers(bake, full)
                os.remove(os.path.join(bake, "ao.png"))
                os.remove(os.path.join(bake, "thick.png"))
                again = os.path.join(tmp, "again")
                pack.pack_tiers(bake, again, orm_from=os.path.join(full, "tex_hi", "orm.png"))
            finally:
                pack.LO, pack.HI, pack.CURV_SIZE = old
            for rel in ("tex/albedo.png", "tex/normal.png", "tex/orm.png", "tex/masks.png", "tex/curvature.png",
                        "tex_hi/normal.png", "tex_hi/orm.png"):
                self.assertEqual(manifest.sha256_file(os.path.join(full, rel)),
                                 manifest.sha256_file(os.path.join(again, rel)), rel)


class LookTwoTest(unittest.TestCase):
    """P51 (plan M11 §3.4): the skin's grade and lookup, the curvature, the shells' strands, the braids' tubes and
    the shell styles in the export."""

    def test_the_grade_pales_the_skin_and_keeps_the_lips(self):
        alb = np.array([[[208, 141, 106], [208, 141, 106]]], np.uint8)
        lips = np.array([[0, 255]], np.uint8)
        g = pack.grade_albedo(alb, lips).astype(int)
        self.assertLess(g[0, 0, 0] - g[0, 0, 2], 208 - 106, "less saturated")
        self.assertGreater(g[0, 1, 0] - g[0, 1, 2], g[0, 0, 0] - g[0, 0, 2], "the lips keep more of their red")

    def test_the_lookup_wraps_on_flat_skin_and_is_red_round_a_bend(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "lut.png")
            pack.make_skin_lut(path)
            lut = np.asarray(Image.open(path).convert("RGB")).astype(int)
        self.assertEqual(lut.shape, (pack.LUT, pack.LUT, 3))
        lit = lut[0, -1]
        self.assertTrue(np.all(lit >= 250), "flat skin facing the light takes all of it: %s" % lit)
        reach = int(np.ceil(max(pack.SKIN_WRAP) * pack.LUT / 2.0)) + 1
        self.assertTrue(np.all(lut[0, : pack.LUT // 2 - reach] <= 2), "flat skin facing away past the wrap takes none")
        edge = lut[0, pack.LUT // 2]
        self.assertTrue(np.all(edge >= 80), "flat skin at the terminator still takes some (Gate A's wrap): %s" % edge)
        self.assertGreaterEqual(int(edge[0]), int(edge[2]), "the red wraps at least as far as the blue")
        term = lut[-1, pack.LUT // 2]
        self.assertGreater(term[0], term[1] + 5, "at the terminator of a bend the red reaches furthest: %s" % term)
        self.assertGreaterEqual(term[1], term[2], "then the green")

    def test_the_curvature_follows_the_bend(self):
        with tempfile.TemporaryDirectory() as tmp:
            s = 128
            yy, xx = np.mgrid[0:s, 0:s] / s
            for r, name in ((0.1, "tight"), (0.4, "wide")):
                d = os.path.join(tmp, name)
                os.makedirs(d)
                a = xx * 2.0
                P = np.stack([np.cos(a) * r, np.sin(a) * r, yy * 0.3], axis=-1).astype(np.float32)
                N = np.stack([np.cos(a), np.sin(a), np.zeros_like(a)], axis=-1)
                np.save(os.path.join(d, "restpos.npy"), P)
                np.save(os.path.join(d, "restnrm.npy"), ((N + 1) / 2).astype(np.float32))
            tight = pack.curvature_map(os.path.join(tmp, "tight"))[s // 2, s // 2] / 255.0 * pack.CURV_MAX_PER_M
            wide = pack.curvature_map(os.path.join(tmp, "wide"))[s // 2, s // 2] / 255.0 * pack.CURV_MAX_PER_M
        # the mean of the two principal curvatures: a cylinder of radius r reads 1 / (2 r)
        self.assertAlmostEqual(tight, 5.0, delta=0.8, msg="1 / (2 x 0.1 m)")
        self.assertAlmostEqual(wide, 1.25, delta=0.5, msg="1 / (2 x 0.4 m)")

    def test_the_strands_tile_and_carry_a_length_and_an_id(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "s.png")
            pack.make_strands(path)
            a = np.asarray(Image.open(path).convert("RGB")).astype(int)
        self.assertEqual(a.shape[:2], (pack.STRANDS, pack.STRANDS))
        self.assertGreater(float((a[..., 0] > 128).mean()), 0.1, "the strands' axes cover a share of the tile")
        self.assertTrue(int(a[..., 1][a[..., 0] > 0].min()) >= int(0.55 * 255) - 1, "every strand is at least 0.55 long")
        inner = float(np.abs(a[64] - a[63]).mean())
        self.assertLess(float(np.abs(a[0] - a[-1]).mean()), 1.5 * inner + 1.0, "the tile wraps top to bottom as inside")

    def test_the_shell_styles_and_the_braids_in_the_export(self):
        from pathlib import Path
        import giant_hair as gh
        root = Path(ROOT)
        doc = manifest.load(root)
        meshes = doc["export"]["meshes"]
        for mid in gh.SHELLS:
            e = meshes[mid]
            self.assertIn("shell", e, mid)
            self.assertEqual(doc["index"]["meshes"][mid]["shell"], e["shell"], "%s: the index carries it" % mid)
            self.assertEqual(e["chains"], [], "%s: on the head" % mid)
            self.assertGreater(e["tris"], 500, "%s: the skin under its mask" % mid)
        for mid in ("Hair_long_braided", "Beard_braided"):
            self.assertGreater(meshes[mid]["braid_verts"], 0, "%s: braids" % mid)
        for mid in ("Beard_full", "Beard_forked"):
            self.assertIn("under_jaw", gh.STYLES[mid], "%s: cards under the jaw" % mid)
        for mid in ("Hair_long_back", "Hair_long_braided", "Hair_warrior_tail", "Hair_wild_mane"):
            self.assertIn("loose", gh.STYLES[mid], "%s: loose strands" % mid)
        for name in ("tex/skin_lut.png", "tex/curvature.png", "cloth_metal.png", "shell_strands.png"):
            self.assertIn("assets/giant/" + name, doc["files"], name)
        self.assertEqual(Image.open(root / "assets/giant/cloth_weave.png").size, (256, 256), "the detail maps at 256 px")


class ManifestTest(unittest.TestCase):
    def test_the_manifest_round_trips_and_lists_every_file(self):
        path = os.path.join(ROOT, manifest.REL_PATH)
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
        doc = json.loads(text)
        self.assertEqual(manifest.dumps(doc), text, "written with sorted keys and a fixed layout")
        for rel, e in doc["files"].items():
            p = os.path.join(ROOT, rel)
            self.assertTrue(os.path.exists(p), rel)
            self.assertEqual(manifest.sha256_file(p), e["sha256"], "%s matches the manifest" % rel)
            self.assertEqual(os.path.getsize(p), e["size"], rel)
        import build_giant
        self.assertEqual(build_giant.build_index(doc["export"], doc["designs"]), doc["index"],
                         "the index is the export's and the designs' information")
        self.assertEqual(build_giant.shipped_problems(doc), [])
        self.assertEqual(doc["body_hash"], doc["index"]["body_hash"])
        lm = doc["index"]["landmarks"]
        # (the body's proportions, 2026-11-20: 0.414 on the M10 body)
        self.assertAlmostEqual(lm["shoulder_r"][0], 0.404, delta=0.02)
        self.assertAlmostEqual(lm["reach_r"], 1.307, delta=0.02)          # (1.385 on the M10 body)


class ClipsTest(unittest.TestCase):
    """P43 (plan M10 §3.3 design 3): giant_clips.glb holds the computed clips on the model's skeleton, and
    the gaits' measures in the manifest (kit/clips.py measures them on the posed skeleton) keep the
    contract: a stride within 5 % of the brain's 3.2 m per cycle, the planted foot's ground point
    still (no slide, no lift), the keyed rotations reproducing the solved pose."""

    def setUp(self):
        with open(os.path.join(ROOT, manifest.REL_PATH), encoding="utf-8") as fh:
            self.doc = json.load(fh)
        if "clips" not in self.doc:
            self.skipTest("no clips in the manifest yet")

    def test_the_gaits_keep_the_brains_stride_and_plant_their_feet(self):
        info = self.doc["clips"]
        self.assertAlmostEqual(info["cycle_m"], 3.2, delta=1e-9, msg="two steps of the brain's 1.6 m")
        for name in ("walk", "run", "sprint"):
            g = info["gaits"][name]
            self.assertLess(abs(g["stride_error"]), 0.05, "%s: stride %.4f m within 5 %%" % (name, g["stride_m"]))
            self.assertLess(g["slide_m"], 0.002, "%s: the planted foot does not slide" % name)
            self.assertLess(g["contact_error_m"], 0.002, "%s: the posed contact is the planned one" % name)
            self.assertLess(g["ground_lift_m"], 0.002, "%s: the planted contact stays on the ground" % name)
            self.assertLess(g["pelvis_drop_m"], 0.45, "%s: the pelvis drops %.3f m at most" % (name, g["pelvis_drop_m"]))
        self.assertLess(info["conversion_error_m"], 1e-4, "the keys reproduce the solved poses")

    def test_the_clips_glb_animates_the_models_bones(self):
        doc, _binary = read_glb(os.path.join(ASSETS, "giant_clips.glb"))
        names = sorted(a["name"] for a in doc.get("animations", []))
        self.assertEqual(names, sorted(self.doc["clips"]["clips"]), "every clip, named as the game asks for it")
        model, _b = read_glb(os.path.join(ASSETS, "giant.glb"))
        bones = {n["name"] for n in model["nodes"] if "mesh" not in n}
        for a in doc["animations"]:
            for ch in a["channels"]:
                target = doc["nodes"][ch["target"]["node"]]["name"]
                self.assertIn(target, bones, "%s animates %s, a bone of giant.glb" % (a["name"], target))
        for name, c in self.doc["clips"]["clips"].items():
            self.assertEqual(c["loop"], name in ("idle", "walk", "run", "sprint"), name)

    def test_the_clips_two_are_all_there_within_their_rows(self):
        """P48 (plan M11 §2.3): 28 clips; every new one measured on its solved poses (kit/clips.py) and
        within its row."""
        info = self.doc["clips"]
        new = ["sprint", "turn_l", "turn_r", "stomp_r", "land", "brace", "roar", "flinch_f", "flinch_b", "flinch_l",
               "flinch_r", "grip_club", "grip_sword", "grip_hammer", "grip_axe", "grip_fist", "grip_tree",
               "carry_two_hand", "fp_rest"]
        self.assertEqual(sorted(info["clips"]), sorted(list(freeze.M10_CLIPS) + new), "M10's nine and the 19 of the clips II")
        self.assertEqual(len(info["clips"]), 28)
        self.assertGreater(info["gaits"]["sprint"]["duty"], 0.2)
        self.assertLess(info["gaits"]["sprint"]["duty"], info["gaits"]["run"]["duty"], "the sprint's flight is longer than the run's")
        m = info["measures"]
        for name, sign in (("turn_l", 1.0), ("turn_r", -1.0)):
            t = m[name]
            self.assertAlmostEqual(t["turn_deg"], 90.0 * sign, delta=0.5, msg="%s turns 90 degrees" % name)
            self.assertLess(t["slide_m"], 0.002, "%s: a standing foot stays where it stands in the world" % name)
            self.assertLess(t["foot_error_m"], 0.002, "%s: the legs reach their feet" % name)
            self.assertLess(t["end_to_start_m"], 0.002, "%s ends as it starts (a second turn follows on)" % name)
            self.assertTrue(0.05 <= t["step_lift_m"] <= 0.4, "%s: the stepping foot lifts %.3f m" % (name, t["step_lift_m"]))
        st = m["stomp_r"]
        self.assertTrue(0.5 <= st["lift_m"] <= 1.2, "the stomp lifts the foot %.2f m" % st["lift_m"])
        self.assertLess(st["plant_from_hip_m"], 0.15, "the plant point is under the hip")
        self.assertLess(st["plant_from_rest_m"], 0.002, "the foot lands where it stood (nothing to slide back)")
        self.assertLess(st["standing_foot_m"], 0.002, "the standing foot does not move")
        self.assertTrue(0.0 < st["lift_fraction"] < st["hold_fraction"] < st["plant_fraction"] < 1.0)
        self.assertTrue(0.25 <= m["land"]["pelvis_drop_m"] <= 0.6, "the knees take the landing")
        self.assertLess(m["land"]["foot_off_ground_m"], 0.002)
        self.assertTrue(0.08 <= m["brace"]["pelvis_drop_m"] <= 0.3, "the brace stands low")
        self.assertLess(m["brace"]["foot_off_ground_m"], 0.002)
        self.assertGreater(m["roar"]["feet_apart_m"], m["land"]["feet_apart_m"] + 0.25, "the roar sets the legs wide")
        self.assertLess(m["roar"]["pelvis_drop_m"], 0.3)
        for name in ("flinch_f", "flinch_b", "flinch_l", "flinch_r"):
            fl = m[name]
            self.assertTrue(6.0 <= fl["chest_deg"] <= 20.0, "%s: the chest turns %.1f degrees" % (name, fl["chest_deg"]))
            self.assertLess(fl["ends_deg"], 0.01, "%s starts and ends at nothing (it is added to a pose)" % name)
            self.assertAlmostEqual(fl["length_s"], 0.3, delta=1e-6)

    def test_a_partial_clip_carries_the_tracks_of_its_own_bones_only(self):
        """M10's follow-up: the hand clips (and P48's grips, flinches and arm rests) are written with their
        own bones' tracks; the full-body clips key every bone but Root."""
        doc, _binary = read_glb(os.path.join(ASSETS, "giant_clips.glb"))
        info = self.doc["clips"]["clips"]
        fingers = ("thumb", "index", "middle", "ring", "pinky")
        for a in doc["animations"]:
            bones = {doc["nodes"][ch["target"]["node"]]["name"] for ch in a["channels"]}
            c = info[a["name"]]
            if c["partial"]:
                self.assertEqual(len(bones), c["bones"], a["name"])
                self.assertEqual(len(a["channels"]), 3 * c["bones"], "%s: three tracks a bone" % a["name"])
            else:
                self.assertEqual(len(bones), 53, "%s keys the whole skeleton" % a["name"])
            if a["name"] in freeze.HAND_CLIPS:
                side = "_" + a["name"][-1]
                self.assertTrue(all(b.startswith(fingers) and b.endswith(side) for b in bones), a["name"])
                self.assertEqual(len(bones), 15)
            if a["name"].startswith("grip_") and a["name"] not in freeze.HAND_CLIPS:
                self.assertTrue(all(b.startswith(fingers) for b in bones) and len(bones) == 30, a["name"])
            if a["name"].startswith("flinch_"):
                self.assertEqual(bones, {"spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r"})


class FreezeTest(unittest.TestCase):
    """P48 design 1 (plan M11 §2.2): what stays bit-identical to 0.10.0-m10. The fixture was read once from
    the files committed at the release (freeze.py --write); nothing regenerates it."""

    @classmethod
    def setUpClass(cls):
        with open(os.path.join(HERE, "fixtures", "m10_freeze.json"), encoding="utf-8") as fh:
            cls.fixture = json.load(fh)

    def test_the_body_and_its_53_bones_are_m10s(self):
        want = self.fixture["body"]
        self.assertEqual(len(want["bones"]), 53)
        got = freeze.body_freeze(os.path.join(ASSETS, "giant.glb"), bones=list(want["bones"]))
        for bone, entry in want["bones"].items():
            self.assertEqual(got["bones"].get(bone), entry, "%s: its parent, rest and bind matrix are M10's" % bone)
        self.assertEqual(sorted(got["meshes"]), sorted(want["meshes"]))
        for mesh, hashes in want["meshes"].items():
            for what in ("vertices", "triangles", "positions", "normals", "uvs", "regions", "weights", "all", "faces"):
                self.assertEqual(got["meshes"][mesh][what], hashes[what], "%s: its %s are M10's" % (mesh, what))
        doc = manifest.load(ROOT)
        # (decision 9's M10 hash 9cd81c08... until the body's proportions, 2026-11-20: the freeze lifted and re-taken)
        self.assertEqual(doc["body_hash"], "52190c406ec66f23a3afe9ac050eaf15bd29160ea14d378801a674237182f133",
                         "the body hash of the proportioned body stands")

    def test_the_freeze_notices_a_change(self):
        """A positive control on synthetic data: the hashes are sets (order does not matter), and one
        moved vertex, one changed weight or one changed region id changes them."""
        rng = np.random.default_rng(5)
        P = rng.random((40, 3)).astype(np.float32)
        perm = rng.permutation(40)
        self.assertEqual(freeze._sha(freeze._sorted_rows(P)), freeze._sha(freeze._sorted_rows(P[perm])))
        Q = P.copy()
        Q[7, 1] += np.float32(1e-6)
        self.assertNotEqual(freeze._sha(freeze._sorted_rows(P)), freeze._sha(freeze._sorted_rows(Q)))

    def test_m10s_nine_clips_keep_their_tracks(self):
        want = self.fixture["clips"]
        self.assertEqual(sorted(want), sorted(freeze.M10_CLIPS))
        got = freeze.clip_freeze(os.path.join(ASSETS, "giant_clips.glb"), freeze.M10_CLIPS)
        for clip, tracks in want.items():
            self.assertEqual(len(tracks), 53)
            if clip in freeze.HAND_CLIPS:
                # the hand clips lost the tracks of the bones they never keyed; the fingers' are M10's
                self.assertEqual(len(got[clip]), 15, clip)
                for bone, h in got[clip].items():
                    self.assertEqual(h, tracks[bone], "%s/%s is M10's" % (clip, bone))
            else:
                self.assertEqual(got[clip], tracks, "%s: every bone's tracks are M10's, byte for byte" % clip)


class BodyTwoTest(unittest.TestCase):
    """P48 (plan M11 §2.2): leaf bones, card weights, build weights, parts, the shadow proxy, the cape."""

    @classmethod
    def setUpClass(cls):
        cls.doc = manifest.load(ROOT)
        cls.core, cls.joints = glb_skins(os.path.join(ASSETS, "giant.glb"))
        cls.parts = {}
        for mid, e in cls.doc["export"]["meshes"].items():
            if "file" in e:
                meshes, joints = glb_skins(os.path.join(ASSETS, e["file"]))
                cls.parts[mid] = (meshes, joints)

    def test_the_skeleton_has_71_bones_and_no_body_vertex_is_on_a_leaf(self):
        import giant_parts as gp
        self.assertEqual(len(gp.LEAF_BONES), 18)
        self.assertEqual(len(self.joints), 71)
        self.assertEqual(sorted(self.joints), sorted(self.doc["export"]["bones"] + list(gp.LEAF_BONES)))
        for mesh in ("Body_Head", "Body_Torso", "Body_Limbs", "Eyes", "ShadowProxy"):
            on_leaf = [b for b in self.core[mesh]["W"] if b in gp.LEAF_BONES]
            self.assertEqual(on_leaf, [], "%s has no vertex on a leaf bone" % mesh)
        chains = self.doc["index"]["chains"]
        self.assertEqual(sorted(chains), sorted(gp.CHAIN_ORDER))
        self.assertEqual(sorted(b for c in chains.values() for b in c["bones"]), sorted(gp.LEAF_BONES))
        doc, _b = read_glb(os.path.join(ASSETS, "giant.glb"))
        parent = {}
        for n in doc["nodes"]:
            for c in n.get("children", []):
                parent[doc["nodes"][c]["name"]] = n["name"]
        for name, c in chains.items():
            self.assertEqual(c["parent"], "spine_03" if c["kind"] == "cape" else "head", name)
            prev = c["parent"]
            for b in c["bones"]:
                self.assertEqual(parent[b], prev, "%s hangs under %s" % (b, prev))
                prev = b
            for k in ("stiffness", "drag", "gravity", "length_m"):
                self.assertGreater(c[k], 0.0, "%s.%s" % (name, k))

    def test_every_cards_root_is_on_the_head_and_long_cards_reach_their_chains(self):
        import giant_parts as gp
        import giant_hair as gh
        info = self.doc["export"]["meshes"]
        long_styles = 0
        for mid, e in sorted(info.items()):
            if e["category"] not in ("hair", "beard"):
                continue
            meshes, joints = self.parts[mid]
            self.assertEqual(len(joints), 71, "%s is on the model's skeleton" % mid)
            m = meshes[mid]
            total = sum(m["W"].values())
            self.assertTrue(np.allclose(total, 1.0, atol=1e-4), "%s: the weights sum to 1" % mid)
            root = m["UV"][:, 1] <= 1e-6                       # glTF v: 0 at a card's root
            head = m["W"].get("head", np.zeros(len(root)))
            off = int((root & (head < 0.9999)).sum())
            braids = e["braid_verts"]
            self.assertEqual(int(root.sum()), e["root_verts"], mid)
            if braids == 0:
                self.assertEqual(off, 0, "%s: every card's root is wholly on head" % mid)
            else:
                self.assertTrue(len(gh.STYLES[mid].get("braids", ())) > 0)
                self.assertLessEqual(off, braids // 3, "%s: only a braid's lobes start off the head (%d)" % (mid, off))
            allowed = {"head"} | {b for c in e["chains"] for b in gp.CHAINS[c][1]}
            self.assertTrue(set(m["W"]) <= allowed, "%s is weighted to head and its chains only: %s" % (mid, sorted(m["W"])))
            want = ("beard",) if e["category"] == "beard" else ("hair", "hair_l", "hair_r")
            self.assertTrue(set(e["chains"]) <= set(want), mid)
            self.assertEqual(self.doc["index"]["meshes"][mid].get("chains", []), e["chains"])
            if e["chains"]:
                long_styles += 1
                tips = m["UV"][:, 1] >= 0.999
                # the warrior's tail lies flat on the scalp but for its tail: some tips, not most
                if braids and (e["category"] == "beard" or mid in ("Hair_side_braids", "Hair_twin_braids")):
                    # P56: the side-shaved top's and the twin braids' cards lie on the head too; their braids hang
                    # P51: the braided beard's cards are short (on the head); its two braids hang on the chain
                    self.assertGreater(int((head[tips] < 0.5).sum()), 0, "%s: its braids' tips are on the chain" % mid)
                else:
                    self.assertLess(float(np.percentile(head[tips], 5)), 0.5, "%s: its hanging tips are on the chains" % mid)
        self.assertGreaterEqual(long_styles, 5, "the long styles hang on chains")
        self.assertEqual(info["Hair_crop"]["chains"], [], "the crop stays on the head")
        self.assertEqual(info["Beard_short"]["chains"], [], "and the short beard")

    def test_the_build_weights_are_signed_shares_the_same_left_and_right(self):
        from scipy.spatial import cKDTree
        idx = self.doc["index"]
        self.assertTrue(0.02 < idx["build_max_m"] < 0.2, "the largest push at stage 1: %s m" % idx["build_max_m"])
        build = self.doc["export"]["build"]
        self.assertAlmostEqual(max(build["brawn_max_m"], build["girth_max_m"]), idx["build_max_m"], delta=1e-6)
        self.assertGreater(min(build["brawn_max_m"], build["girth_max_m"]), 0.25 * idx["build_max_m"],
                           "both sliders use a fair share of the range")
        extremes = np.zeros(2)
        for mesh in ("Body_Head", "Body_Torso", "Body_Limbs"):
            m = self.core[mesh]
            C = m["C"]
            self.assertTrue(float(C[:, 1:3].min()) >= 0.0 and float(C[:, 1:3].max()) <= 1.0, mesh)
            # P56: the alpha carries the tangent's sign (1 for +1, 0 for -1; the skin shader rebuilds its binormal)
            self.assertTrue(np.all((np.abs(C[:, 3]) < 1e-3) | (np.abs(C[:, 3] - 1.0) < 1e-3)),
                            "%s: alpha is the tangent's sign, 0 or 1" % mesh)
            d, twin = cKDTree(m["P"]).query(m["P"] * [-1.0, 1.0, 1.0])
            ok = d < 1e-4
            if mesh != "Body_Head":       # the face is asymmetric by design (the asym targets); it carries no weight
                self.assertGreater(int(ok.sum()), 0.9 * len(ok), "%s is a symmetric mesh" % mesh)
            diff = np.abs(C[ok][:, 1:3] - C[twin[ok]][:, 1:3])
            self.assertLessEqual(float(diff.max()), 2.0 / 255.0 + 1e-9, "%s: left and right agree within 2/255" % mesh)
            extremes = np.maximum(extremes, np.abs(C[:, 1:3] - 0.5).max(axis=0) * 2.0)
        self.assertGreater(float(extremes.max()), 0.97, "the largest weight is a whole one")
        head = self.core["Body_Head"]
        face = split.decode_region(head["C"][:, 0]) == split.REGION_ID["face"]
        self.assertLess(float(np.abs(head["C"][face][:, 1:3] - 0.5).max()), 0.1, "the face keeps its shape")
        # garments and cards inherit the weights of the skin they sit on
        tunic = self.parts["Garment_tunic_core"][0]["Garment_tunic_core"]
        self.assertGreater(float(np.abs(tunic["C"][:, 1:3] - 0.5).max()), 0.2, "the tunic carries the torso's weights")
        torso = self.core["Body_Torso"]
        d, near = cKDTree(torso["P"]).query(tunic["P"])
        close = d < 0.06
        self.assertGreater(int(close.sum()), 200)
        self.assertLess(float(np.abs(tunic["C"][close][:, 1:3] - torso["C"][near[close]][:, 1:3]).mean()), 0.03,
                        "a garment's weights are those of the skin under it")
        for mid, (meshes, _j) in self.parts.items():
            self.assertIsNotNone(meshes[mid]["C"], "%s carries the build channels" % mid)

    def test_the_parts_the_index_the_manifest_and_the_files_agree(self):
        idx, files, info = self.doc["index"], self.doc["files"], self.doc["export"]
        self.assertEqual(sorted(self.core), ["Body_Head", "Body_Limbs", "Body_Torso", "Eyes", "ShadowProxy"],
                         "giant.glb holds the body, the eyes and the shadow proxy")
        on_disk = sorted(f for f in os.listdir(os.path.join(ASSETS, "parts")) if f.endswith(".glb"))
        part_ids = sorted(m for m, e in idx["meshes"].items() if "part_path" in e)
        self.assertEqual(on_disk, [m + ".glb" for m in part_ids], "a file a part, no other")
        # M10's (P48's) 21 parts and the wardrobe's (P54): 28 more garment meshes (25 garments, three of them split)
        # and the 8 accessories; the catalogue II's (P56) nine styles and three bead sets; P61's rival giants' gear: the
        # hide mantle, the war harness and the iron rings
        self.assertEqual(len(part_ids), 21 + 28 + 8 + 9 + 3 + 3 + 1 + 4 + 10 + 4)   # B1: the nasal helm, the Quarry
        # set's 4; B2: the Iron set's brim, breastplate and tassets, the Hide set's three lames, the Kingsfall set's
        # four; B3: the Warden set's mantle, bracers, greaves and heartwood amulet
        self.assertEqual(sorted(m for m, e in idx["meshes"].items() if "part_path" not in e),
                         ["Body_Head", "Body_Limbs", "Body_Torso", "Eyes"])
        for mid in part_ids:
            e = idx["meshes"][mid]
            self.assertEqual(e["part_path"], "res://assets/giant/parts/%s.glb" % mid)
            self.assertIn("assets/giant/parts/%s.glb" % mid, files)
            meshes, _joints = self.parts[mid]
            self.assertEqual(sorted(meshes), [mid], "%s.glb holds its one mesh" % mid)
            self.assertEqual(meshes[mid]["tris"], e["tris"], "%s: the index counts its triangles" % mid)
            self.assertIn(e["category"], ("hair", "beard", "garment", "accessory", "bead", "armour"))
        self.assertEqual(len(files), 13 + 4 + 2 + 91,
                         "M10's 13 files, P51's four maps, P54's two (mail, scale), the parts (P61: 72; B1: 77; B2: 87; "
                         "B3: 91)")
        proxy = info["shadow_proxy"]
        self.assertEqual(idx["shadow_proxy"], {"node": "ShadowProxy", "tris": proxy["tris"]})
        self.assertEqual(self.core["ShadowProxy"]["tris"], proxy["tris"])
        self.assertTrue(2300 <= proxy["tris"] <= 2700, "the proxy is the body at about 2,500 triangles (%d)" % proxy["tris"])
        self.assertNotIn("ShadowProxy", idx["meshes"], "the proxy is no look's mesh")
        import build_giant
        for rel in files:
            spec = build_giant.import_params(rel[len("assets/giant/"):], self.doc)
            if rel.endswith(".glb"):
                self.assertIsNotNone(spec, rel)
            if "/parts/" in rel:
                self.assertEqual(spec[2]["meshes/create_shadow_meshes"], "false", "a part casts through the proxy")
                self.assertEqual(spec[2]["skins/use_named_skins"], "true")
            imp = os.path.join(ROOT, rel + ".import")
            if spec is not None and os.path.exists(imp):
                with open(imp, encoding="utf-8") as fh:
                    text = fh.read()
                for k, v in spec[2].items():
                    self.assertIn("%s=%s" % (k, v), text, "%s.import: %s" % (rel, k))

    def test_the_proxy_lies_inside_the_skin_and_is_weighted_like_it(self):
        from scipy.spatial import cKDTree
        proxy = self.core["ShadowProxy"]
        body_P = np.concatenate([self.core[m]["P"] for m in ("Body_Head", "Body_Torso", "Body_Limbs")])
        d, _i = cKDTree(body_P).query(proxy["P"])
        self.assertLess(float(d.max()), 0.12, "the proxy follows the body")
        self.assertTrue(np.allclose(sum(proxy["W"].values()), 1.0, atol=1e-4))
        self.assertGreaterEqual(len(proxy["W"]), 40, "the proxy keeps the body's bones (%d)" % len(proxy["W"]))
        lo, hi = body_P.min(axis=0), body_P.max(axis=0)
        self.assertTrue(np.all(proxy["P"].min(axis=0) >= lo - 0.02) and np.all(proxy["P"].max(axis=0) <= hi + 0.02))

    def test_the_cape_hangs_free_on_its_three_chains(self):
        import giant_parts as gp
        e = self.doc["index"]["meshes"]["Garment_cape"]
        self.assertEqual(e["chains"], ["cape_c", "cape_l", "cape_r"])
        self.assertTrue(e["free"])
        # P54: the cape lies on the back down to below the shoulders' garments, so it covers the upper back too
        self.assertEqual(e["covers"], [5, 6], "the cape covers the back (the outfits' data: back)")
        cape = self.parts["Garment_cape"][0]["Garment_cape"]
        chains = self.doc["index"]["chains"]
        root_y = chains["cape_c"]["root"][1]
        W = cape["W"]
        chain_w = sum(W.get(b, 0.0) for b in gp.LEAF_BONES if b.startswith("cape"))
        top = cape["P"][:, 1] > root_y + 0.1
        # P54: it lies on the back down to below the shoulders' garments, then hangs from its chains
        low = cape["P"][:, 1] < root_y - 2.0 * chains["cape_c"]["length_m"] / 3.0 - 0.02
        self.assertGreater(int(top.sum()), 20, "the collar and the shoulders")
        self.assertLess(float(chain_w[top].max()), 0.05, "the collar stays on the body")
        self.assertGreater(float(chain_w[low].min()), 0.9, "below the shoulders' garments the cape is on its chains")
        # closed at the collar: vertices in front of the neck as well as behind it (glTF: +Z the giant's front)
        collar = cape["P"][cape["P"][:, 1] > cape["P"][:, 1].max() - 0.08]
        self.assertTrue(collar[:, 2].max() > 0.05 and collar[:, 2].min() < -0.05, "the collar goes round the neck")
        # a rest shape that hangs: the hem is further from the back than the M10 shell's 5 cm
        hem = cape["P"][cape["P"][:, 1] < cape["P"][:, 1].min() + 0.15]
        torso = self.core["Body_Torso"]["P"]
        from scipy.spatial import cKDTree
        d, _i = cKDTree(torso).query(hem)
        self.assertGreater(float(d.mean()), 0.12, "the hem hangs clear of the back (%.3f m)" % float(d.mean()))

    def test_the_new_landmarks_and_the_designs_sides(self):
        lm = self.doc["index"]["landmarks"]
        for s, sign in (("r", 1.0), ("l", -1.0)):
            for key in ("grip_", "knuckle_", "toe_", "grip_axis_", "grip_local_"):
                self.assertEqual(len(lm[key + s]), 3, key + s)
            grip, wrist, palm = np.array(lm["grip_" + s]), np.array(lm["wrist_" + s]), np.array(lm["palm_" + s])
            self.assertGreater(grip[0] * sign, 0.9, "grip_%s is on the giant's %s" % (s, "right" if s == "r" else "left"))
            self.assertLess(np.linalg.norm(grip - palm), 0.12, "the fist's centre is a few centimetres off the knuckle line")
            self.assertLess(np.linalg.norm(grip - wrist), np.linalg.norm(palm - wrist) + 0.02, "and nearer the wrist")
            self.assertAlmostEqual(float(np.linalg.norm(lm["grip_axis_" + s])), 1.0, delta=1e-4)
            self.assertLess(np.linalg.norm(np.array(lm["grip_local_" + s])), 0.3)
            self.assertLess(lm["toe_" + s][1], 0.08, "the toe is on the ground")
            self.assertLess(lm["toe_" + s][2], lm["ankle_" + s][2] - 0.3, "and in front of the ankle")
        self.assertEqual(lm["grip_local_r"][0], -lm["grip_local_l"][0])
        sides = {d: v["side"] for d, v in self.doc["index"]["designs"].items()}
        self.assertTrue(set(sides.values()) <= {"left", "right", "centre"})
        self.assertEqual(sides["tat_arm_sleeve"], "right", "the sleeve is on the right arm")
        self.assertEqual(sides["tat_chest_sun"], "centre")
        self.assertIn("left", sides.values(), "a design on the giant's left is framed from his left")


class ToleranceTest(unittest.TestCase):
    def test_cycles_outputs_compare_within_the_tolerance_on_another_toolchain(self):
        """--verify on a toolchain other than the manifest's accepts Cycles pixels within 2/255 per
        channel and 0.1/255 on average (manifest.image_close), and names what differs in the toolchain;
        on the reference toolchain only the bake's own jitter (manifest.image_jitter): at most 64 texels
        off by 1/255."""
        rng = np.random.default_rng(3)
        base = rng.integers(10, 240, (64, 64, 3), dtype=np.uint8)
        with tempfile.TemporaryDirectory() as tmp:
            def save(name, arr):
                path = os.path.join(tmp, name)
                Image.fromarray(arr, "RGB").save(path)
                return path
            a = save("a.png", base)
            near = base.copy()
            near[0, :10, 0] += 2                    # 10 values off by 2/255: the mean stays under 0.1/255
            far = base.copy()
            far[5, 5, 1] += 3                       # one value off by 3/255
            drift = base + 1                        # every value off by 1/255: the mean is over
            ok, mx, mean = manifest.image_close(a, save("near.png", near))
            self.assertTrue(ok, (mx, mean))
            self.assertAlmostEqual(mx, 2 / 255.0)
            self.assertFalse(manifest.image_close(a, save("far.png", far))[0], "over the largest difference")
            self.assertFalse(manifest.image_close(a, save("drift.png", drift))[0], "over the mean")
            self.assertFalse(manifest.image_close(a, save("small.png", base[:32]))[0], "another size")
            # the reference toolchain's own bake jitter: a few texels off by one step
            one = base.copy()
            one[7, 9, 0] += 1
            ok, texels, mx = manifest.image_jitter(a, save("one.png", one))
            self.assertTrue(ok and texels == 1 and abs(mx - 1 / 255.0) < 1e-9, (ok, texels, mx))
            self.assertTrue(manifest.image_jitter(a, save("near2.png", near))[0] is False, "off by 2/255")
            many = base.copy()
            many[:2, :40, 1] += 1                   # 80 texels off by 1/255: more than jitter
            self.assertFalse(manifest.image_jitter(a, save("many.png", many))[0], "more texels than jitter")
            self.assertEqual(manifest.image_jitter(a, a)[:2], (True, 0))
        old = {"bpy": "5.3.0", "numpy": "2.5.4", "cpu": {"model": "x"}}
        new = {"bpy": "5.3.0", "numpy": "2.6.0", "cpu": {"model": "y"}}
        diff = manifest.toolchain_diff(old, new)
        self.assertEqual(len(diff), 2, diff)
        self.assertTrue(any(d.startswith("numpy") for d in diff) and any(d.startswith("cpu") for d in diff))
        self.assertEqual(manifest.toolchain_diff(old, dict(old)), [])


class BudgetTest(unittest.TestCase):
    def test_the_estimate_follows_the_web_preset_and_build_web_rule(self):
        """--budget estimates only what the Web preset ships and judges it by build_web.sh's rule (its
        default budget less 18.4 MiB), so a change of either moves the estimate and its cap together.
        Since P45 (the owner's answer 1, plan §0.6) the last default is 26 MiB from -m10 on and the Web
        keeps tex_hi/; before it the values here were 23, 4.6 and tex_hi/ excluded. Since the 0.12.0-m12 release
        (P58) the last default was -m12's 32 MiB (the current milestone's branch moves to the end); since the
        0.13.0-m13 release (P66) it was -m13's 44 MiB; since the expansion's 0.14.0-m14 (A1b, the owner's raised cap)
        it was -m14's 46 MiB, and -m12's branch ("-eq 12") still gives the wardrobe's 32. B1 (0.15.0-m15): the last
        default is -m15's 50 MiB and the script sets the giant's share for -m15 (14.0 MiB: the functional armour's
        meshes; B3: 15.0, the Warden set), which the assets' milestone (15) reads."""
        import build_giant
        self.assertEqual(build_giant.web_budget_mib(milestone=None), 50.0, "build_web.sh's last default: -m15's")
        self.assertEqual(build_giant.web_budget_mib(milestone=13), 44.0, "-m13's own branch")
        self.assertEqual(build_giant.web_budget_mib(milestone=14), 46.0, "-m14's own branch")
        self.assertEqual(build_giant.web_budget_mib(milestone=12), 32.0, "build_web.sh's -m12 budget (the wardrobe's)")
        # B1: the armour's files are made for 0.15: the giant's share the script sets for it (14.0 MiB)
        self.assertEqual(build_giant.ASSET_MILESTONE, 15)
        self.assertEqual(build_giant.web_budget_mib(), 50.0, "build_web.sh's -m15 budget")
        self.assertEqual(build_giant.share_cap_mib(), 15.0, "the share build_web.sh sets from -m15 (B3: 15.0)")
        excluded = build_giant.web_excluded()
        for pat in ("assets/giant/manifest.json", "tests/*", "tools/*"):
            self.assertIn(pat, excluded)
        self.assertNotIn("assets/giant/tex_hi/*", excluded, "the Web keeps the 1024 px maps (P45)")
        self.assertNotIn("assets/giant/tex_hi/*", build_giant.web_excluded(preset="Linux"), "desktop keeps it")
        with tempfile.TemporaryDirectory() as tmp:
            root = build_giant.Path(tmp)
            (root / "tools").mkdir()
            (root / "tools" / "build_web.sh").write_text("\tif x; then BUDGET_MB=7.5\n\telse BUDGET_MB=23\n\tfi\n")
            self.assertEqual(build_giant.share_cap_mib(root), 4.6, "the rule follows the script: 23 gives 4.6")


class WardrobeTest(unittest.TestCase):
    """P54 (plan M11 §2.6, §3.7): the wardrobe's 35 garments in ten slots and 8 accessories, the index v2's fields, the
    shells' distances in four poses, the head garments' cut of the hair, the accessories' triangles and bones."""

    @classmethod
    def setUpClass(cls):
        cls.doc = manifest.load(ROOT)
        cls.idx = cls.doc["index"]
        cls.info = cls.doc["export"]

    def _gg(self):
        import giant_garment
        return giant_garment

    def test_the_slots_their_offsets_and_the_35_garments_in_the_index(self):
        gg = self._gg()
        self.assertEqual(gg.SLOT_SHELL_M, {"legs": 0.012, "chest": 0.014, "shins": 0.020, "feet": 0.024, "arms": 0.022,
                                           "waist": 0.030, "armour": 0.034, "shoulders": 0.046, "head": 0.020,
                                           "cape": 0.030}, "the plan's table (stage-1 metres; the cape hangs free)")
        self.assertEqual(len(gg.GARMENTS), 38, "35, P61's two npc garments and B1's nasal helm")
        self.assertEqual(len(gg.NEW_ORDER), 25)
        self.assertEqual(gg.NPC_ORDER, ("hide_mantle", "war_harness"))
        self.assertTrue(all(gg.GARMENTS[g].get("npc") for g in gg.NPC_ORDER))
        self.assertEqual(gg.ARMOUR_ORDER, ("nasal_helm",))
        self.assertTrue(all(gg.GARMENTS[g].get("armour") for g in gg.ARMOUR_ORDER))
        self.assertEqual(gg.ORDER[-3:], gg.NPC_ORDER + gg.ARMOUR_ORDER,
                         "after every other garment (theirs are as they were): the npc pieces, then B1's armour")
        self.assertEqual(set(gg.ORDER), set(gg.GARMENTS))
        self.assertEqual(sorted({g["slot"] for g in gg.GARMENTS.values()}), sorted(gg.SLOT_SHELL_M))
        self.assertEqual(sorted(self.idx["garments"]), sorted(gg.GARMENTS))
        for gid, spec in gg.GARMENTS.items():
            meshes = self.idx["garments"][gid]
            self.assertEqual(len(meshes), 2 if spec["part"] == "split" else 1, gid)
            for m in meshes:
                e = self.idx["meshes"][m]
                self.assertEqual((e["slot"], e["material"]), (spec["slot"], spec["material"]), m)
                self.assertAlmostEqual(e["shell"], gg.SLOT_SHELL_M[spec["slot"]], 6, m)
                self.assertEqual(e.get("hides_hair", "none"), spec.get("hides_hair", "none") if spec["slot"] == "head"
                                 else "none", m)
                self.assertLessEqual(e["tris"], 5000, "%s: a garment mesh at most 5,000 triangles" % m)
            rec = self.info["slots"][gid]
            # a shell never comes nearer the skin than its slot's offset (a band's or the braies' least is measured
            # over the skin vertex nearest each of its vertices, where its edge may stand nearer)
            if gid in ("braies", "belt", "war_belt", "sash"):
                continue
            self.assertGreaterEqual(rec["least_m"], gg.SLOT_SHELL_M[spec["slot"]] - 1e-4, gid)

    def test_the_shells_keep_apart_in_four_poses(self):
        """Every two garments of different slots that stand over the same skin keep at least 0.004 m apart at stage
        1 (k = 1) in the rest pose, an idle frame, a walk frame and a raised arm (the export measures it along each
        skin vertex's own skinned normal, export_game.shell_distances)."""
        self.assertEqual(self.info["shell_poses"], ["rest", "idle", "walk", "raised_arm"])
        d = self.info["shell_distances"]
        self.assertGreater(len(d), 150, "the overlapping pairs of the 35 garments")
        for pair in ("braies|tunic", "tunic|jerkin", "leg_wraps|boots", "shirt|mail_hauberk", "mail_hauberk|iron_pauldrons",
                     "trousers|greaves", "shirt|iron_vambraces", "mail_hauberk|long_cloak", "long_cloak|fur_mantle"):
            self.assertIn(pair, d, "the pair %s is measured" % pair)
        bad = {k: v for k, v in d.items() if v < 0.004}
        self.assertEqual(bad, {}, "pairs nearer than 0.004 m in some pose")

    def test_the_layering_table_pushes_a_garment_only_as_far_as_what_is_worn_under_it(self):
        """The W33 look lane: each garment mesh sits where it would over nothing; its push to its place over the loosest
        garment of every inner slot rides in the vertex colour's alpha (push_m the alpha's 1), and the index's layering
        gives the least share of that push for each worn inner garment (the export's shells' distances measure every
        pair at the inner garment's no push and full push with the outer one at the share the table gives it)."""
        gg = self._gg()
        lay = self.idx["layering"]
        self.assertEqual(lay["samples"], gg.PUSH_SAMPLES)
        all_rings = ["Accessory_" + a for a in gg.ACCESSORY_ORDER if gg.ACCESSORIES[a]["slot"] != "belt"]
        for r in all_rings:
            self.assertTrue(self.idx["meshes"][r].get("push_tangent"), "%s: its push rides in its tangents" % r)
        # a ring over the shirt's or the armour's envelope (the arm rings; a torc above the collars needs none)
        rings = [r for r in all_rings if self.idx["meshes"][r].get("push_m")]
        self.assertEqual(sorted(r for r in rings if "arm" in r), sorted(r for r in all_rings if "arm" in r))
        # the second look lane: a belt's trophy sits on the bare skin too and moves out along its side over what is
        # worn under it (it hung clear of the fullest wardrobe: the horn a hand off bare braies)
        trophies = ["Accessory_" + a for a in gg.ACCESSORY_ORDER if gg.ACCESSORIES[a]["slot"] == "belt"]
        for t in trophies:
            e = self.idx["meshes"][t]
            self.assertTrue(e.get("push_tangent") and e.get("push_m"), "%s: its push rides in its tangents" % t)
            self.assertIn("braies", lay["push"][t], "%s: moves out over the braies" % t)
            self.assertLess(max(lay["push"][t]["braies"]), 0.5, "%s: the braies need less than half its push" % t)
            self.assertGreater(max(lay["push"][t]["mail_hauberk"]), 2.0 * max(lay["push"][t]["braies"]),
                               "%s: a hauberk's skirt pushes it out further than braies" % t)
        # B1: the Quarry set's modelled pieces after them, each pushed over the slots it is built over (gg.rigid_push)
        armour = ["Armour_" + a for a in gg.ARMOUR_RIGID_ORDER if self.idx["meshes"]["Armour_" + a].get("push_m")]
        self.assertEqual(sorted(lay["order"]), sorted(list(gg.GARMENTS) + rings + trophies + armour),
                         "the garments, then the rings and the trophies, then the armour's pieces")
        layer = {g: gg.LAYER_ORDER.index(gg.GARMENTS[g]["slot"]) for g in gg.GARMENTS}
        layer.update({r: len(gg.LAYER_ORDER) for r in rings + trophies + armour})
        self.assertEqual([layer[g] for g in lay["order"]], sorted(layer[g] for g in lay["order"]), "from the skin out")
        for r in rings:
            self.assertIn("shirt", lay["push"][r], "%s: it sits on the bare skin and moves out over the shirt" % r)
        knots = lay["knots_m"]
        self.assertEqual(len(knots), len(gg.PUSH_KNOT_MARKS))
        self.assertEqual(knots, sorted(knots), "the knots from the thighs up")
        nk = len(knots)
        for outer, row in lay["push"].items():
            for inner, shares in row.items():
                self.assertLess(layer[inner], layer[outer], "%s over %s" % (outer, inner))
                self.assertEqual(len(shares), gg.PUSH_SAMPLES * nk, "a share a knot at each sample")
                self.assertTrue(all(0.0 <= x <= 1.0 for x in shares), (outer, inner, shares))
                for j in range(nk):
                    col = shares[j::nk]
                    self.assertEqual(col, sorted(col), "%s over %s: more push under, more push over" % (outer, inner))
        pushed = [m for m, e in self.idx["meshes"].items() if e.get("push_m")]
        self.assertGreater(len(pushed), 20, "the garments that stand over inner slots carry their push")
        # the default look (the Wanderer: braies and belt): the belt sits on the braies, nearer than its full place
        self.assertLess(max(lay["push"]["belt"]["braies"][:nk]), 0.5, "the belt over the braies alone")
        hauberk = lay["push"]["mail_hauberk"]["shirt"]
        self.assertLess(max(hauberk[:3]), 0.1, "a shirt under a hauberk pushes its chest, not its skirt")
        self.assertNotIn("braies", lay["push"], "the innermost slot is never pushed")

    def test_a_helm_cuts_or_hides_each_hair_style(self):
        gg = self._gg()
        styles = sorted(m for m, e in self.idx["meshes"].items() if e["category"] == "hair")
        for gid, spec in gg.GARMENTS.items():
            if spec["slot"] != "head":
                continue
            e = self.idx["meshes"]["Garment_" + gid]
            if spec["hides_hair"] == "all":
                self.assertNotIn("hair_cut", e, gid)
                continue
            cut = e["hair_cut"]
            self.assertEqual(sorted(cut), styles, "%s: a cut for every hair style" % gid)
            for style, length in cut.items():
                self.assertTrue(length == 0.0 or 0.3 <= length <= 1.0, "%s %s: %s" % (gid, style, length))
            self.assertEqual(cut["Hair_crop"], 1.0, "%s: the crop's shells stay under it" % gid)

    def test_the_accessories_rigid_on_one_bone_and_small(self):
        gg = self._gg()
        self.assertEqual(len(gg.ACCESSORIES), 8)
        slots = sorted(a["slot"] for a in gg.ACCESSORIES.values())
        self.assertEqual(slots, ["arm_ring"] * 3 + ["belt"] * 2 + ["neck"] * 3)
        self.assertEqual(sorted(self.idx["accessories"]), sorted(gg.ACCESSORIES))
        bone_of = {"neck": "spine_03", "arm_ring": "upperarm_l", "belt": "pelvis"}
        for aid, spec in gg.ACCESSORIES.items():
            mid = self.idx["accessories"][aid]
            e = self.idx["meshes"][mid]
            self.assertEqual((e["category"], e["slot"], e["bone"]), ("accessory", spec["slot"], bone_of[spec["slot"]]))
            self.assertLessEqual(e["tris"], 400, "%s: at most 400 triangles" % aid)
            meshes, joints = glb_skins(os.path.join(ROOT, e["part_path"][len("res://"):]))
            W = meshes[mid]["W"]
            self.assertEqual(sorted(b for b, w in W.items() if float(np.max(w)) > 0.0), [bone_of[spec["slot"]]],
                             "%s: all on its one bone" % aid)


class CatalogueTest(unittest.TestCase):
    """P56 (plan M11 §2.6, §3.9): the catalogue II - five hair and four beard styles with bead anchors, three bead sets,
    twenty designs under the packing and two-paint rules, six face keys."""
    NEW_STYLES = ("Hair_top_knot", "Hair_side_braids", "Hair_twin_braids", "Hair_long_loose", "Hair_circlet_braid",
                  "Beard_chin_braid", "Beard_long_forked", "Beard_mutton_chops", "Beard_braided_moustache")
    BEAD_SETS = ("Beads_bone", "Beads_bronze", "Beads_silver")
    FACE_KEYS = ("jaw", "chin", "nose", "brow", "cheeks", "age")

    @classmethod
    def setUpClass(cls):
        cls.doc = manifest.load(ROOT)
        cls.idx = cls.doc["index"]

    @staticmethod
    def _mesh(rel, name=None):
        doc, binary = read_glb(os.path.join(ROOT, rel))
        m = [x for x in doc["meshes"] if name is None or x["name"] == name][0]
        prim = m["primitives"][0]
        at = prim["attributes"]
        out = {"P": accessor(doc, binary, at["POSITION"]).astype(np.float64),
               "UV": accessor(doc, binary, at["TEXCOORD_0"]) if "TEXCOORD_0" in at else None,
               "UV2": accessor(doc, binary, at["TEXCOORD_1"]) if "TEXCOORD_1" in at else None,
               "names": (m.get("extras") or {}).get("targetNames", []),
               "targets": [accessor(doc, binary, t["POSITION"]).astype(np.float64) for t in prim.get("targets", [])],
               "target_attrs": [sorted(t) for t in prim.get("targets", [])]}
        return out

    def test_the_new_styles_carry_bead_anchors_and_the_sets_their_codes(self):
        meshes = self.idx["meshes"]
        for mid in self.NEW_STYLES:
            e = meshes[mid]
            self.assertGreater(e.get("bead_anchors", 0), 0, "%s has bead anchors" % mid)
            self.assertLessEqual(e["tris"], 6000 if mid.startswith("Hair_") else 4000, "%s under its cap" % mid)
        anchored = sorted(m for m, e in meshes.items() if e.get("bead_anchors"))
        self.assertTrue({"Hair_long_braided", "Beard_braided"} <= set(anchored), "M10's braided styles take beads too")
        for sid in self.BEAD_SETS:
            e = meshes[sid]
            self.assertEqual(e["category"], "bead")
            self.assertEqual(sorted(e["styles"]), anchored, "%s: a code for every anchored style" % sid)
            self.assertEqual(sorted(e["styles"].values()), list(range(1, len(anchored) + 1)))
            self.assertLessEqual(e["tris"], 3200, "%s: at most 3,200 triangles" % sid)
            m = self._mesh(e["part_path"].replace("res://", ""))
            codes = sorted({int(round(v)) for v in m["UV2"][:, 0]})
            self.assertEqual(codes, sorted(e["styles"].values()), "%s: every vertex carries a style's code" % sid)

    def test_the_designs_keep_the_packing_and_the_two_paint_rule(self):
        cat = {d: (v["kind"], tuple(v["regions"])) for d, v in self.idx["designs"].items()}
        kinds = {}
        for k, _r in cat.values():
            kinds[k] = kinds.get(k, 0) + 1
        self.assertEqual(kinds, {"tattoo": 28, "paint": 8, "scar": 10, "mark": 3})
        self.assertEqual(designs.paint_problems(cat), [], "a face paint on the face alone, a body paint off it")
        bad = dict(cat, paint_wrong=("paint", (1, 3)))
        self.assertEqual(len(designs.paint_problems(bad)), 1, "a paint on the face and the body is caught")
        legs = [d for d, (k, r) in cat.items() if k == "tattoo" and set(r) <= {11, 12, 13}]
        self.assertEqual(len(legs), 4, "four tattoos for the legs (regions 11-13)")
        self.assertLessEqual(self.idx["textures"]["design_layers"], 12, "at most twelve design layers (plan §2.12)")

    def test_the_face_keys_on_the_head_and_the_beards(self):
        """The head carries the six keys with morph normals and tangents; its base shape is the body's (the freeze
        test hashes it); every beard follows its skin: at -1 and +1 no card's root leaves the keyed skin by more than
        2 mm (plan §3.9)."""
        from scipy.spatial import cKDTree
        head = self._mesh("assets/giant/giant.glb", "Body_Head")
        self.assertEqual(head["names"], list(self.FACE_KEYS))
        self.assertTrue(all(a == ["NORMAL", "POSITION", "TANGENT"] for a in head["target_attrs"]),
                        "the head's keys carry morph normals and tangents (probe 3)")
        for k, d in zip(head["names"], head["targets"]):
            self.assertGreater(float(np.abs(d).max()), 0.004, "%s moves the face" % k)
        self.assertEqual(self.idx["meshes"]["Body_Head"]["face_keys"], list(self.FACE_KEYS))
        for mid, e in sorted(self.idx["meshes"].items()):
            if e["category"] != "beard" or e.get("shell"):
                continue
            m = self._mesh(e["part_path"].replace("res://", ""))
            self.assertTrue(set(m["names"]) <= set(self.FACE_KEYS) and {"jaw", "chin"} <= set(m["names"]), mid)
            self.assertNotIn("brow", m["names"], "%s: the brow keeps off the beard" % mid)
            self.assertTrue(all(a == ["POSITION"] for a in m["target_attrs"]), "%s: positions only" % mid)
            roots = m["UV"][:, 1] <= 1e-6
            if m["UV2"] is not None:
                roots &= m["UV2"][:, 0] < 0.5            # the cards' roots (a braid hangs off the skin from its start)
            R = m["P"][roots]
            _d, near = cKDTree(head["P"]).query(R)
            for k in head["names"]:
                # every head key: a key the beard does not carry must not move its roots' skin (the keys keep off it)
                hk = head["targets"][head["names"].index(k)][near]
                bk = m["targets"][m["names"].index(k)][roots] if k in m["names"] else np.zeros_like(hk)
                # a root moves with the skin under it: its offset from the nearest skin vertex changes by w (bk - hk)
                worst = float(np.max(np.linalg.norm(bk - hk, axis=1)))
                self.assertLessEqual(worst, 0.002, "%s: %s at -1 or +1 moves a root %.4f m off the skin" % (mid, k, worst))


class VendorTest(unittest.TestCase):
    def test_the_audit_file_list_equals_the_vendored_files(self):
        import fetch_mpfb2
        listed = fetch_mpfb2.read_list()
        self.assertEqual(fetch_mpfb2.vendored_files(), sorted(listed))
        for rel, h in listed.items():
            self.assertEqual(manifest.sha256_file(os.path.join(fetch_mpfb2.VENDOR, rel)), h, rel)
        self.assertTrue(os.path.exists(os.path.join(fetch_mpfb2.VENDOR, ".gdignore")), "Godot never imports it")
        import mh_data as mh
        self.assertEqual(mh.subset_files(), sorted(listed), "the kit reads exactly the vendored files")


if __name__ == "__main__":
    unittest.main(verbosity=2)
