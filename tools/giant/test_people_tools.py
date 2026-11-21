#!/usr/bin/env python3
"""The people pipeline's tests (P59, plan M11 §3.12), on the committed assets/people/ and the kit's tables.

Run with the giant's venv (bpy's mathutils casts the rays):
  $GIANT_VENV/bin/python -B tools/giant/test_people_tools.py

  * the 23-bone reduction: the kept bones are the giant's skeleton's, every game_engine bone folds into one,
    the fingers into the hands, the weights' sums kept
  * a variant is one mesh with one surface, at most 5,000 triangles, on the 23 bones by name with four weights
  * no skin triangle under a garment survives (its corners and centre all under another piece within reach)
  * the palette bands decode (the third map's B channel)
  * every crowd-pose mesh matches its clip's pose within 1 cm at the joints (the clip read back from
    people_clips.glb onto the first variant's skeleton read back from the role's glTF)
  * the audit's file lists equal the vendored files' hashes; the women's targets are vendored (question 6)
  * the import settings, the manifest's index, the clips, the budget estimate within the share
  * P61, the horse (assets/creatures/): the bare and the tacked horse each one mesh with one surface of at most
    6,000 triangles on the 25 bones with four weights, every vertex weighted; the body closed and manifold (welded
    at the UV seams); the palette bands of the coat, the mane, the tack and the housing; the gait's extremes keep
    the body's volume and stand the stance hooves on the ground; the manifest and the import settings
"""
from __future__ import annotations

import json
import os
import struct
import sys
import unittest

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(HERE, "kit"))
sys.path.insert(0, HERE)
import build_people  # noqa: E402
import fetch_mpfb2  # noqa: E402
import manifest  # noqa: E402
import mh_data as mh  # noqa: E402
import people_roles as pr  # noqa: E402

ASSETS = os.path.join(ROOT, "assets", "people")
CREATURES = os.path.join(ROOT, "assets", "creatures")
COVER_REACH_M = 0.12            # people_outfit.COVER_REACH_M


def load_manifest():
    with open(os.path.join(ASSETS, "manifest.json"), encoding="utf-8") as fh:
        return json.load(fh)


# --------------------------------------------------------------------------------------
# a small glTF reader
# --------------------------------------------------------------------------------------
class Gltf:
    TYPES = {5120: np.int8, 5121: np.uint8, 5122: np.int16, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
    WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}

    def __init__(self, path):
        with open(path, "rb") as fh:
            data = fh.read()
        n = struct.unpack_from("<I", data, 12)[0]
        self.js = json.loads(data[20:20 + n])
        off = 20 + n
        m = struct.unpack_from("<I", data, off)[0]
        self.bin = data[off + 8:off + 8 + m]

    def accessor(self, i):
        a = self.js["accessors"][i]
        bv = self.js["bufferViews"][a["bufferView"]]
        dt = np.dtype(self.TYPES[a["componentType"]])
        w = self.WIDTH[a["type"]]
        start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
        stride = bv.get("byteStride", 0) or dt.itemsize * w
        raw = np.frombuffer(self.bin, dtype=np.uint8, count=stride * (a["count"] - 1) + dt.itemsize * w, offset=start)
        out = np.lib.stride_tricks.as_strided(raw, shape=(a["count"], dt.itemsize * w), strides=(stride, 1)).copy()
        arr = out.view(dt).reshape(a["count"], w)
        if a.get("normalized"):
            arr = arr.astype(np.float64) / np.iinfo(dt).max
        return arr if w > 1 else arr[:, 0]

    def node_index(self, name):
        return [i for i, nd in enumerate(self.js["nodes"]) if nd.get("name") == name]

    def mesh_nodes(self):
        return {nd["name"]: (i, nd) for i, nd in enumerate(self.js["nodes"]) if "mesh" in nd}

    def parents(self):
        out = {}
        for i, nd in enumerate(self.js["nodes"]):
            for c in nd.get("children", []):
                out[c] = i
        return out


def trs(nd):
    T = np.eye(4)
    t = nd.get("translation", [0, 0, 0])
    x, y, z, w = nd.get("rotation", [0, 0, 0, 1])
    s = nd.get("scale", [1, 1, 1])
    R = np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                  [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                  [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])
    T[:3, :3] = R * np.asarray(s)
    T[:3, 3] = t
    return T


def blender_to_gltf(p):
    return np.array([p[0], p[2], -p[1]])


def orm(role):
    from PIL import Image
    return np.asarray(Image.open(os.path.join(ASSETS, role + "_orm.png")).convert("RGB"))


def variant_mesh(g, node):
    m = g.js["meshes"][node["mesh"]]
    prim = m["primitives"][0]
    P = g.accessor(prim["attributes"]["POSITION"]).astype(np.float64)
    T = g.accessor(prim["indices"]).astype(np.int64).reshape(-1, 3)
    UV = g.accessor(prim["attributes"]["TEXCOORD_0"]).astype(np.float64)
    return m, prim, P, T, UV


def triangle_bands(img, UV, T):
    """The band at each triangle's centroid texel (glTF UVs: v down)."""
    c = UV[T].mean(axis=1)
    size = img.shape[0]
    x = np.clip((c[:, 0] * size).astype(int), 0, size - 1)
    y = np.clip((c[:, 1] * size).astype(int), 0, size - 1)
    return np.array([pr.decode_band(int(b)) for b in img[y, x, 2]])


class TestBones(unittest.TestCase):
    def test_the_23_bones_and_their_folding(self):
        self.assertEqual(len(pr.BONES), 23)
        rig = mh.load_rig()
        giant = load_giant_bones()
        for b in pr.BONES:
            self.assertIn(b, rig, "a kept bone is the game_engine rig's")
            self.assertIn(b, giant, "and the giant's skeleton's")
            p = rig[b].get("parent", "")
            self.assertTrue(p == "" or p in pr.BONES, "%s's parent is kept" % b)
        for b in rig:
            k = pr.fold_bone(b)
            self.assertIn(k, pr.BONES)
            if b.startswith(pr.FINGERS):
                self.assertEqual(k, "hand_" + b[-1], b)
            else:
                self.assertEqual(k, b)
        self.assertEqual(sum(1 for b in rig if pr.fold_bone(b) != b), 30, "the 30 finger bones fold")

    def test_folding_keeps_each_vertexs_weight(self):
        w = mh.load_weights()
        n = mh.N_BODY_VERTS
        g = {}
        for b, lst in w.items():
            a = np.zeros(n)
            for vi, x in lst:
                if vi < n:
                    a[vi] = x
            g[b] = a
        f = pr.fold_weights(g)
        self.assertEqual(set(f) - set(pr.BONES), set())
        self.assertTrue(np.allclose(sum(g.values()), sum(f.values())))
        idx, w4 = pr.top4(f, n)
        self.assertTrue(np.allclose(w4.sum(axis=1), 1.0))


def load_giant_bones():
    with open(os.path.join(ROOT, "assets", "giant", "manifest.json"), encoding="utf-8") as fh:
        return set(json.load(fh)["export"]["bones"])


class TestVariants(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_manifest()
        cls.glb = {r: Gltf(os.path.join(ASSETS, r + ".glb")) for r in pr.ROLE_ORDER}

    def test_every_role_and_variant_is_built(self):
        self.assertEqual(self.doc["index"]["role_order"], list(pr.ROLE_ORDER))
        self.assertEqual(sorted(self.doc["index"]["roles"]), sorted(pr.ROLE_ORDER))
        for r in pr.ROLE_ORDER:
            self.assertEqual(self.doc["index"]["roles"][r]["variants"], [v["name"] for v in pr.ROLES[r]["variants"]])
        counts = {r: len(pr.ROLES[r]["variants"]) for r in pr.ROLE_ORDER}
        self.assertEqual(counts, {"soldier": 4, "archer": 2, "mage": 2, "crew": 2, "villager": 5, "elder": 2})
        self.assertEqual(list(self.doc["index"]["moved_to_p61"]), ["notable", "rider"])

    def test_women_among_the_villagers(self):
        sexes = [v["sex"] for v in pr.ROLES["villager"]["variants"]]
        self.assertEqual(sexes.count("female"), 2)
        for v in pr.ROLES["villager"]["variants"]:
            if v["sex"] == "female":
                self.assertTrue(any("female" in t for t in pr.variant_targets(v)), "a woman's macro targets")

    def test_a_variant_is_one_mesh_one_surface_on_23_bones_with_four_weights(self):
        for r, g in self.glb.items():
            nodes = g.mesh_nodes()
            for v in pr.ROLES[r]["variants"]:
                self.assertIn(v["name"], nodes, "%s's mesh node" % v["name"])
                _i, nd = nodes[v["name"]]
                m, prim, P, T, UV = variant_mesh(g, nd)
                self.assertEqual(len(m["primitives"]), 1, "%s: one surface" % v["name"])
                self.assertLessEqual(len(T), pr.TRIS_MAX, v["name"])
                self.assertGreater(len(T), 2500, "%s is a whole person" % v["name"])
                self.assertIn("skin", nd)
                skin = g.js["skins"][nd["skin"]]
                names = [g.js["nodes"][j]["name"] for j in skin["joints"]]
                self.assertEqual(sorted(names), sorted(pr.BONES), "%s: the 23 bones by name" % v["name"])
                a = prim["attributes"]
                self.assertIn("JOINTS_0", a)
                self.assertNotIn("JOINTS_1", a, "four weights at most")
                W = g.accessor(a["WEIGHTS_0"]).astype(np.float64)
                self.assertEqual(W.shape[1], 4)
                self.assertTrue(np.allclose(W.sum(axis=1), 1.0, atol=2e-3), "%s's weights sum to 1" % v["name"])
                self.assertIn("TANGENT", a, "tangents exported (the normal map's frame)")
                h = float(P[:, 1].max())
                self.assertTrue(1.70 < h < 1.95, "%s stands %.3f m" % (v["name"], h))

    def test_no_skin_triangle_under_a_garment_survives(self):
        import bpy  # noqa: F401  (mathutils comes with it)
        from mathutils import Vector
        from mathutils.bvhtree import BVHTree
        for r, g in self.glb.items():
            img = orm(r)
            nodes = g.mesh_nodes()
            for v in pr.ROLES[r]["variants"]:
                _m, _p, P, T, UV = variant_mesh(g, nodes[v["name"]][1])
                band = triangle_bands(img, UV, T)
                skin = np.nonzero(band == "skin")[0]
                other = np.nonzero(band != "skin")[0]
                self.assertGreater(len(skin), 200, "%s shows skin" % v["name"])
                tree = BVHTree.FromPolygons([tuple(map(float, p)) for p in P], [tuple(map(int, t)) for t in T[other]],
                                            all_triangles=True)
                n = np.cross(P[T[skin, 1]] - P[T[skin, 0]], P[T[skin, 2]] - P[T[skin, 0]])
                n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
                under = 0
                for k, t in enumerate(skin):
                    pts = list(P[T[t]]) + [P[T[t]].mean(axis=0)]
                    if all(tree.ray_cast(Vector((p + n[k] * 1e-4).tolist()), Vector(n[k].tolist()), COVER_REACH_M)[0]
                           is not None for p in pts):
                        under += 1
                self.assertEqual(under, 0, "%s: %d skin triangles under a garment" % (v["name"], under))

    def test_the_palette_bands_decode(self):
        for b in pr.BANDS:
            self.assertEqual(pr.decode_band(pr.band_byte(b)), b)
            self.assertEqual(int(pr.band_value(b) * len(pr.BANDS)), pr.BANDS.index(b), "int(B * 5) in the shader")
        allowed = {pr.band_byte(b) for b in pr.BANDS}
        for r in pr.ROLE_ORDER:
            img = orm(r)
            self.assertEqual(img.shape, (pr.ORM_PX, pr.ORM_PX, 3))
            self.assertEqual(set(np.unique(img[..., 2]).tolist()) - allowed, set(), "%s: only band values" % r)
            for tile, (u0, v0) in pr.TILES.items():
                x = int((u0 + pr.TILE_SIZE / 2) * pr.ORM_PX)
                y = int((1.0 - v0 - pr.TILE_SIZE / 2) * pr.ORM_PX)
                self.assertEqual(pr.decode_band(int(img[y, x, 2])), pr.MATERIALS[pr.TILE_MATERIAL[tile]]["band"],
                                 "%s: the %s tile's band" % (r, tile))
            nodes = self.glb[r].mesh_nodes()
            for v in pr.ROLES[r]["variants"]:
                _m, _p, P, T, UV = variant_mesh(self.glb[r], nodes[v["name"]][1])
                bands = set(triangle_bands(img, UV, T))
                self.assertTrue({"skin", "hair", "none"} <= bands, "%s: %s" % (v["name"], sorted(bands)))
                self.assertTrue(bands & {"cloth", "faction"}, "%s wears cloth" % v["name"])
            if pr.ROLES[r]["faction"]:
                self.assertIn(pr.band_byte("faction"), set(np.unique(img[..., 2]).tolist()), r)

    def test_the_maps_sizes(self):
        from PIL import Image
        for r in pr.ROLE_ORDER:
            for kind, px in (("albedo", pr.ALBEDO_PX), ("normal", pr.NORMAL_PX), ("orm", pr.ORM_PX)):
                with Image.open(os.path.join(ASSETS, "%s_%s.png" % (r, kind))) as im:
                    self.assertEqual(im.size, (px, px), "%s_%s" % (r, kind))


class TestPoses(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc = load_manifest()
        cls.clips = Gltf(os.path.join(ASSETS, "people_clips.glb"))

    def clip_key(self, clip, key):
        """{bone: {"rotation": (4,), "translation": (3,)}} of a clip's key."""
        g = self.clips
        anim = [a for a in g.js["animations"] if a["name"] == clip][0]
        out = {}
        for ch in anim["channels"]:
            nd = g.js["nodes"][ch["target"]["node"]]
            path = ch["target"]["path"]
            if path not in ("rotation", "translation"):
                continue
            vals = g.accessor(anim["samplers"][ch["sampler"]]["output"])
            out.setdefault(nd["name"], {})[path] = vals[key if key >= 0 else len(vals) + key]
        return out

    def test_every_crowd_pose_matches_its_clip_within_1_cm(self):
        for r in pr.ROLE_ORDER:
            g = Gltf(os.path.join(ASSETS, r + ".glb"))
            info = self.doc["roles"][r]
            v0 = pr.ROLES[r]["variants"][0]["name"]
            node = g.mesh_nodes()[v0][1]
            skin = g.js["skins"][node["skin"]]
            joints = skin["joints"]
            names = {j: g.js["nodes"][j]["name"] for j in joints}
            parent = g.parents()
            for pose, e in info["poses"].items():
                self.assertEqual((e["clip"], e["key"]), tuple(pr.POSE_CLIP[pose]))
                key = self.clip_key(e["clip"], e["key"])
                G = {}

                def world(j):
                    if j in G:
                        return G[j]
                    nd = dict(g.js["nodes"][j])
                    k = key.get(nd.get("name"), {})
                    if "rotation" in k:
                        nd["rotation"] = list(map(float, k["rotation"]))
                    if "translation" in k and nd.get("name") == "pelvis":
                        nd["translation"] = list(map(float, k["translation"]))
                    p = parent.get(j)
                    M = (world(p) if p is not None and p in names else
                         (node_world(g, p, parent) if p is not None else np.eye(4))) @ trs(nd)
                    G[j] = M
                    return M
                worst = 0.0
                for j in joints:
                    got = world(j)[:3, 3]
                    want = blender_to_gltf(np.asarray(e["joints"][names[j]]))
                    worst = max(worst, float(np.linalg.norm(got - want)))
                self.assertLess(worst, pr.POSE_JOINT_TOL_M, "%s %s: %.4f m off its clip at the worst joint" % (
                    r, pose, worst))
                pn = g.mesh_nodes()[e["node"]][1]
                _m, prim, P, T, _uv = variant_mesh(g, pn)
                self.assertLessEqual(len(T), pr.POSE_TRIS_MAX)
                self.assertNotIn("skin", pn, "a crowd pose is a static mesh")
                for b in ("head", "hand_l", "foot_r"):
                    j = blender_to_gltf(np.asarray(e["joints"][b]))
                    self.assertLess(float(np.min(np.linalg.norm(P - j, axis=1))), 0.12,
                                    "%s %s: the mesh is where its %s is" % (r, pose, b))
            far = g.mesh_nodes()[info["far"]["node"]][1]
            self.assertLessEqual(len(variant_mesh(g, far)[3]), pr.FAR_TRIS_MAX)
            corpse = variant_mesh(g, g.mesh_nodes()[info["poses"]["corpse"]["node"]][1])[2]
            self.assertLess(float(corpse[:, 1].max()), 0.6, "%s: the corpse lies down" % r)
            self.assertGreater(float(corpse[:, 1].min()), -0.05, "%s: and not under the ground" % r)

    def test_the_clips(self):
        g = self.clips
        names = {a["name"] for a in g.js["animations"]}
        self.assertEqual(names, set(pr.CLIP_FRAMES))
        info = self.doc["clips"]
        for n, f in pr.CLIP_FRAMES.items():
            self.assertEqual(info["clips"][n]["frames"], f)
            anim = [a for a in g.js["animations"] if a["name"] == n][0]
            bones = {g.js["nodes"][c["target"]["node"]]["name"] for c in anim["channels"]}
            self.assertEqual(bones, set(pr.PARTIAL_CLIPS.get(n, pr.BONES)), n)
        walk = info["gaits"]["walk"]
        self.assertAlmostEqual(walk["stride_m"], 2 * pr.STEP_M, places=3)
        self.assertLess(walk["slide_m"], 0.005)


def node_world(g, j, parent):
    M = trs(g.js["nodes"][j])
    p = parent.get(j)
    return (node_world(g, p, parent) if p is not None else np.eye(4)) @ M


class TestData(unittest.TestCase):
    def test_the_audit_lists_equal_the_vendored_files(self):
        people = fetch_mpfb2.read_people_list()
        giant = fetch_mpfb2.read_list()
        self.assertEqual(sorted(people), pr.people_only_files(), "PEOPLE.sha256 lists what the people read")
        self.assertEqual(set(people) & set(giant), set())
        self.assertEqual(fetch_mpfb2.vendored_people_files(), sorted(people))
        self.assertEqual(fetch_mpfb2.vendored_files(), sorted(giant), "the giant's list unchanged by the people's")
        for rel, h in people.items():
            self.assertEqual(manifest.sha256_file(os.path.join(fetch_mpfb2.VENDOR, rel)), h, rel)
        self.assertTrue(any("female" in r for r in people), "the women's macro targets (question 6)")
        size = sum(os.path.getsize(os.path.join(fetch_mpfb2.VENDOR, r)) for r in people)
        self.assertLessEqual(size, 4 * 1000 * 1000, "the added CC0 targets at most 4 MB (plan §2.12)")

    def test_the_import_settings(self):
        doc = load_manifest()
        for rel in doc["files"]:
            imp, typ, params = build_people.import_params(rel)
            path = os.path.join(ROOT, rel + ".import")
            self.assertTrue(os.path.exists(path), rel)
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn('importer="%s"' % imp, text, rel)
            for k, v in params.items():
                self.assertIn("\n%s=%s\n" % (k, v), text, "%s: %s" % (rel, k))

    def test_the_manifest_lists_every_file_with_its_hash(self):
        doc = load_manifest()
        self.assertEqual(build_people.shipped_problems(doc), [])
        want = {"assets/people/%s" % n for r in pr.ROLE_ORDER for n in (r + ".glb", r + "_albedo.png", r + "_normal.png",
                                                                      r + "_orm.png")}
        want |= {"assets/people/people_clips.glb", "assets/people/gear.glb"}
        self.assertEqual(set(doc["files"]), want)
        for e in doc["files"].values():
            self.assertFalse(e["cycles"], "no Cycles output: the bake is bit-exact")

    def test_the_gear(self):
        g = Gltf(os.path.join(ASSETS, "gear.glb"))
        nodes = g.mesh_nodes()
        for gid in ("sword", "spear", "shield", "banner", "bow", "quiver", "staff", "hammer"):
            self.assertIn("gear_" + gid, nodes)
        for r in pr.ROLE_ORDER:
            for gid in pr.ROLES[r]["gear"]:
                self.assertIn("gear_" + gid, nodes, "%s's %s" % (r, gid))

    def test_nothing_in_the_game_uses_them_yet(self):
        hits = []
        for top in ("scenes", "scripts", "data", "ui", "tools/builders"):
            for dp, _dn, fns in os.walk(os.path.join(ROOT, top)):
                for f in fns:
                    if f.endswith((".gd", ".tscn", ".tres", ".json")):
                        with open(os.path.join(dp, f), encoding="utf-8", errors="replace") as fh:
                            if "assets/people/" in fh.read():
                                hits.append(os.path.relpath(os.path.join(dp, f), ROOT))
        self.assertEqual(hits, [], "no scene, script or record of the game names assets/people before P60")

    def test_the_estimate_is_within_the_share(self):
        import io
        from contextlib import redirect_stdout
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = build_people.budget()
        self.assertEqual(code, 0, buf.getvalue()[-400:])


# --------------------------------------------------------------------------------------
# P61: the horse
# --------------------------------------------------------------------------------------
def load_creatures():
    with open(os.path.join(CREATURES, "manifest.json"), encoding="utf-8") as fh:
        return json.load(fh)


def weld_positions(P, T, tol=1e-5):
    """(positions, triangles) with the glTF's seam-split vertices welded."""
    q = np.round(P / tol).astype(np.int64)
    _u, idx, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    return P[idx], inv.ravel()[T]


class TestHorse(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        import quadruped as qd
        cls.qd = qd
        cls.g = Gltf(os.path.join(CREATURES, "horse.glb"))
        cls.doc = load_creatures()
        cls.info = cls.doc["horse"]

    def mesh(self, name):
        _i, nd = self.g.mesh_nodes()[name]
        return (nd,) + variant_mesh(self.g, nd)

    def test_one_mesh_one_surface_on_25_bones_every_vertex_weighted(self):
        self.assertEqual(len(self.qd.BONES), 25)
        for name in ("horse", "horse_tacked"):
            nd, m, prim, P, T, UV = self.mesh(name)
            self.assertEqual(len(m["primitives"]), 1, "%s: one surface" % name)
            self.assertLessEqual(len(T), self.qd.TRIS_MAX, name)
            skin = self.g.js["skins"][nd["skin"]]
            names = [self.g.js["nodes"][j]["name"] for j in skin["joints"]]
            self.assertEqual(sorted(names), sorted(self.qd.BONES), "%s: the 25 bones by name" % name)
            a = prim["attributes"]
            self.assertNotIn("JOINTS_1", a, "four weights at most")
            self.assertIn("TANGENT", a)
            W = self.g.accessor(a["WEIGHTS_0"]).astype(np.float64)
            self.assertTrue(np.allclose(W.sum(axis=1), 1.0, atol=2e-3), "%s's weights sum to 1" % name)
            self.assertGreater(float(W.max(axis=1).min()), 0.2, "%s: no vertex without a weight" % name)
            J = self.g.accessor(a["JOINTS_0"]).astype(np.int64)
            root = names.index("Root")
            self.assertFalse(((J == root) & (W > 0)).any(), "the Root bone moves nothing")
            self.assertLess(abs(float(P[:, 1].min())), 0.01, "%s stands on the ground" % name)
        bones = {self.g.js["nodes"][j]["name"]: j for j in self.g.js["skins"][0]["joints"]}
        parents = self.g.parents()
        for b, p in self.qd.PARENTS.items():
            if p:
                self.assertEqual(self.g.js["nodes"][parents[bones[b]]]["name"], p, "%s's parent" % b)

    def test_the_body_is_closed_and_manifold(self):
        _nd, _m, _prim, P, T, UV = self.mesh("horse")
        c = UV[T].mean(axis=1)                       # glTF v down: the body's rectangle is u < 0.75, v < 0.75
        body = T[(c[:, 0] < 0.75) & (c[:, 1] < 0.75)]
        self.assertEqual(len(body), self.info["triangles"]["body"], "the body's triangles by their atlas rectangle")
        V, W = weld_positions(P.astype(np.float64), body)
        self.assertTrue(self.qd.directed_edges_ok(W), "every edge has exactly two triangles, wound opposite")
        b, nm, _e = self.qd.mesh_stats(W)
        self.assertEqual((b, nm), (0, 0), "no open and no non-manifold edge")
        vol = float(np.einsum("ij,ij->i", V[W[:, 0]], np.cross(V[W[:, 1]], V[W[:, 2]])).sum() / 6.0)
        self.assertGreater(vol, 0.35, "wound outward, a horse's volume (%.3f m3)" % vol)

    def test_the_palette_bands(self):
        from PIL import Image
        img = np.asarray(Image.open(os.path.join(CREATURES, "horse_orm.png")).convert("RGB"))
        _nd, _m, _prim, P, T, UV = self.mesh("horse_tacked")
        bands = triangle_bands(img, UV, T)
        c = UV[T].mean(axis=1)
        body = (c[:, 0] < 0.75) & (c[:, 1] < 0.75)
        cap = (c[:, 0] < 0.75) & (c[:, 1] > 0.75)
        hair = (c[:, 0] > 0.75) & (c[:, 1] < 0.25)
        share = {b: float((bands[body] == b).mean()) for b in pr.BANDS}
        self.assertGreater(share["skin"], 0.6, "most of the coat takes the coat's colour (%s)" % share)
        self.assertGreater(share["hair"], 0.08, "the points take the mane's colour")
        self.assertGreater(share["none"], 0.01, "the hooves, the eyes and the white keep their own")
        self.assertTrue((bands[cap] == "faction").all(), "the housing is in the faction's colour")
        self.assertTrue((bands[hair] == "hair").all(), "the mane and the tail take the hair's colour")
        alb = np.asarray(Image.open(os.path.join(CREATURES, "horse_albedo.png")))
        self.assertEqual(alb.shape, (512, 512, 4), "RGBA: the strands' coverage in alpha")
        self.assertLess(int(alb[:128, 384:, 3].min()), 20, "the strands' tile has gaps")      # (row 0 is v = 1)
        self.assertEqual(int(alb[:384, :384, 3].min()), 255, "the body's texels are opaque")
        self.assertEqual(int(alb[384:, :384, 3].min()), 255, "the housing's texels are opaque")

    def test_the_gaits_extremes(self):
        poses = self.info["poses"]
        self.assertEqual(sorted(poses), sorted(self.qd.POSE_ORDER))
        for name, p in poses.items():
            self.assertTrue(0.95 < p["volume_ratio"] < 1.05, "%s keeps the body's volume (%.3f)" % (
                name, p["volume_ratio"]))
            self.assertGreater(p["lowest_m"], -0.035, "%s: nothing sinks into the ground" % name)
        self.assertEqual(set(poses["stand"]["soles_m"].values()), {0.0})
        trot = poses["trot_reach_left"]["soles_m"]
        self.assertLess(max(trot["fore_l"], trot["hind_r"]), 0.05, "the reaching diagonal lands")
        self.assertGreater(trot["fore_r"], 0.2, "the other fore is lifted")
        g = Gltf(os.path.join(CREATURES, "horse_poses.glb"))
        self.assertEqual(sorted(a["name"] for a in g.js["animations"]), sorted(self.qd.POSE_ORDER))

    def test_the_measures_and_the_budget(self):
        m = self.info["measures"]
        self.assertTrue(1.5 < m["withers_m"] < 1.7, "a riding horse's withers (%.3f)" % m["withers_m"])
        self.assertTrue(2.2 < m["length_m"] < 2.8)
        t = self.info["triangles"]
        self.assertLessEqual(t["horse"], 6000)
        self.assertLessEqual(t["horse_tacked"], 6000)
        self.assertEqual(t["horse"], t["body"] + t["mane"] + t["tail"])

    def test_the_manifest_and_the_import_settings(self):
        self.assertEqual(build_people.shipped_problems(self.doc, build_people.CREATURES), [])
        self.assertEqual(set(self.doc["files"]), {"assets/creatures/" + n for n in build_people.HORSE_FILES})
        for rel in self.doc["files"]:
            imp, typ, params = build_people.import_params(rel)
            with open(os.path.join(ROOT, rel + ".import"), encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn('importer="%s"' % imp, text, rel)
            for k, v in params.items():
                self.assertIn("\n%s=%s\n" % (k, v), text, "%s: %s" % (rel, k))
        self.assertEqual(self.doc["inputs"]["kit"], build_people.source_hashes(build_people.HORSE_SOURCES),
                         "the manifest was written from today's kit")

    def test_the_weights_follow_the_legs(self):
        qd = self.qd
        idx, w = qd.weights(np.array([[0.15, 0.53, 0.30], [-0.15, -0.71, 0.30], [0.0, 0.0, 1.55], [0.0, 1.3, 1.8]]))
        names = [[qd.BONES[i] for i, x in zip(r, wr) if x > 0.5] for r, wr in zip(idx, w)]
        self.assertEqual(names, [["fore_cannon_l"], ["hind_cannon_r"], ["spine_01"], ["head"]])


if __name__ == "__main__":
    unittest.main(verbosity=1)
