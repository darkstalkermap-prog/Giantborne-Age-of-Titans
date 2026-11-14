#!/usr/bin/env python3
"""Tests of the giant pipeline's tools (tools/check.sh --giant runs them before
build_giant.py --verify --skip-bake). Run with the shared venv:

  $GIANT_VENV/bin/python -B tools/giant/test_giant_tools.py

They read the committed outputs (assets/giant/) and exercise the pure parts of the kit on synthetic
data: the per-channel resize, the region encoding, the caps (no open cut on Body_Limbs or on any limb
garment part), the packing rule, the design generator's determinism, the --skip-bake read-back of AO
and thickness, the manifest round trip, the Cycles tolerance on another toolchain, the Web budget's
estimate rules and the vendored subset's file list.
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
        meshes, _ = glb_meshes(os.path.join(ASSETS, "giant.glb"))
        limbs = meshes["Body_Limbs"]
        weld = split.weld_positions(limbs["P"], 1e-5)
        self.assertEqual(len(split.boundary_edges(limbs["T"], weld)), 0, "Body_Limbs is closed")
        names = [n for n in meshes if n.startswith("Garment_") and (n.endswith(LIMB_PARTS_OF) or n in WHOLE_LIMB_GARMENTS)]
        self.assertGreaterEqual(len(names), 4, "the limb garment parts: %s" % names)
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
        # the scars fill a layer of their own
        scar_layers = {placed[d][0] for d in designs.SCAR_ORDER}
        self.assertEqual(len(scar_layers), 1)
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
            old = (pack.LO, pack.HI)
            pack.LO = 32
            try:
                full = os.path.join(tmp, "full")
                pack.pack_tiers(bake, full)
                os.remove(os.path.join(bake, "ao.png"))
                os.remove(os.path.join(bake, "thick.png"))
                again = os.path.join(tmp, "again")
                pack.pack_tiers(bake, again, orm_from=os.path.join(full, "tex_hi", "orm.png"))
            finally:
                pack.LO, pack.HI = old
            for rel in ("tex/albedo.png", "tex/normal.png", "tex/orm.png", "tex/masks.png", "tex_hi/normal.png",
                        "tex_hi/orm.png"):
                self.assertEqual(manifest.sha256_file(os.path.join(full, rel)),
                                 manifest.sha256_file(os.path.join(again, rel)), rel)


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
        self.assertAlmostEqual(lm["shoulder_r"][0], 0.414, delta=0.02)
        self.assertAlmostEqual(lm["reach_r"], 1.385, delta=0.02)


class ToleranceTest(unittest.TestCase):
    def test_cycles_outputs_compare_within_the_tolerance_on_another_toolchain(self):
        """--verify on a toolchain other than the manifest's accepts Cycles pixels within 2/255 per
        channel and 0.1/255 on average (manifest.image_close), and names what differs in the toolchain."""
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
        old = {"bpy": "5.3.0", "numpy": "2.5.4", "cpu": {"model": "x"}}
        new = {"bpy": "5.3.0", "numpy": "2.6.0", "cpu": {"model": "y"}}
        diff = manifest.toolchain_diff(old, new)
        self.assertEqual(len(diff), 2, diff)
        self.assertTrue(any(d.startswith("numpy") for d in diff) and any(d.startswith("cpu") for d in diff))
        self.assertEqual(manifest.toolchain_diff(old, dict(old)), [])


class BudgetTest(unittest.TestCase):
    def test_the_estimate_follows_the_web_preset_and_build_web_rule(self):
        """--budget estimates only what the Web preset ships and judges it by build_web.sh's rule (its
        default budget less 18.4 MiB), so a change of either (P45: the owner's 26 MiB, the Web keeping
        tex_hi/) moves the estimate and its cap together."""
        import build_giant
        self.assertEqual(build_giant.web_budget_mib(), 23.0, "build_web.sh's default after M7")
        self.assertEqual(build_giant.share_cap_mib(), 4.6, "plan §2.12")
        excluded = build_giant.web_excluded()
        for pat in ("assets/giant/manifest.json", "assets/giant/tex_hi/*", "tests/*", "tools/*"):
            self.assertIn(pat, excluded)
        self.assertNotIn("assets/giant/tex_hi/*", build_giant.web_excluded(preset="Linux"), "desktop keeps it")
        with tempfile.TemporaryDirectory() as tmp:
            root = build_giant.Path(tmp)
            (root / "tools").mkdir()
            (root / "tools" / "build_web.sh").write_text("\tif x; then BUDGET_MB=7.5\n\telse BUDGET_MB=26\n\tfi\n")
            self.assertEqual(build_giant.share_cap_mib(root), 7.6, "the 26 MiB answer gives the giant 7.6")


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
