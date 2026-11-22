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
  * P59b: the notable and rider roles (the named women among the notables), P59's variant lists unchanged, the
    face's share of the triangles, the atlas's regions and the mail's numbers equal to the person shader's, the
    grip landmarks, the natural walk (its pelvis drop) and each gait's stride without slide, the rider's seat on
    the tacked horse (the seat at the origin, the ankles over the stirrups' treads)
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
        self.assertEqual(counts, {"soldier": 4, "archer": 2, "mage": 2, "crew": 2, "villager": 5, "elder": 4,
                                  "notable": 8, "rider": 2})
        self.assertNotIn("moved_to_p61", self.doc["index"], "P59b built the notable and rider roles P59 left")
        # the variant lists the game hashes entity ids into are P59's, in P59's order (looks never reshuffle)
        p59 = {"soldier": ["soldier_a", "soldier_b", "soldier_c", "iron_guard"], "archer": ["archer_a", "archer_b"],
               "mage": ["mage_a", "mage_b"], "crew": ["crew_a", "crew_b"],
               "villager": ["villager_a", "villager_b", "villager_c", "villager_d", "villager_e"],
               "elder": ["elder_a", "elder_b"]}
        for r, names in p59.items():
            # (P65b appended the elders' two women: a variant list only ever grows at its end)
            self.assertEqual(self.doc["index"]["roles"][r]["variants"][:len(names)], names, r)
        self.assertEqual(self.doc["index"]["roles"]["elder"]["variants"][2:], ["elder_c", "elder_d"],
                         "P65b's old women (Elder Maren, Sedge)")
        self.assertEqual(self.doc["index"]["roles"]["notable"]["variants"],
                         ["edda", "reeve_tamsin", "sedge", "ferrywoman", "herald", "toll_captain", "deserter", "corvane"],
                         "the named characters of plan §3.15")

    def test_women_among_the_villagers(self):
        sexes = [v["sex"] for v in pr.ROLES["villager"]["variants"]]
        self.assertEqual(sexes.count("female"), 2)
        for v in pr.ROLES["villager"]["variants"]:
            if v["sex"] == "female":
                self.assertTrue(any("female" in t for t in pr.variant_targets(v)), "a woman's macro targets")

    def test_women_among_the_notables(self):
        sexes = {v["name"]: v["sex"] for v in pr.ROLES["notable"]["variants"]}
        self.assertEqual(sorted(n for n, s in sexes.items() if s == "female"),
                         ["edda", "ferrywoman", "herald", "reeve_tamsin", "sedge"], "the named women (their records)")

    def test_the_variants_keep_most_of_their_triangles_in_the_face(self):
        # P59b: the face's and the ears' share (the head's skin over the neck) of every variant's triangles
        for r, g in self.glb.items():
            nodes = g.mesh_nodes()
            img = orm(r)
            for v in pr.ROLES[r]["variants"]:
                _m, _p, P, T, UV = variant_mesh(g, nodes[v["name"]][1])
                band = triangle_bands(img, UV, T)
                c = P[T].mean(axis=1)
                info = self.doc["roles"][r]["variants"][v["name"]]
                neck = 0.5 * (info["joints"]["neck_01"][2] + info["joints"]["head"][2])
                face = (band == "skin") & (c[:, 1] > neck)
                self.assertGreater(int(face.sum()), 450, "%s: %d triangles of face" % (v["name"], int(face.sum())))
                self.assertLessEqual(len(T), pr.TRIS_MAX)

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
                self.assertEqual((e["clip"], e["key"]), tuple(pr.pose_clip(r, pose)))
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
        for gait in ("walk", "run", "flee"):
            m = info["gaits"][gait]
            self.assertAlmostEqual(m["stride_m"], 2 * pr.GAIT_STEP_M[gait], places=3, msg=gait)
            self.assertLess(m["slide_m"], 0.005, gait)
        # P59b: a natural walk at 1.8 m (P59's 0.9 m step dropped the pelvis 13.6 cm a step)
        self.assertLess(info["gaits"]["walk"]["pelvis_drop_m"], 0.08)
        self.assertAlmostEqual(self.doc["index"]["walk_cycle_m"], 2 * pr.GAIT_STEP_M["walk"], places=6)
        self.assertAlmostEqual(self.doc["index"]["run_cycle_m"], 2 * pr.GAIT_STEP_M["run"], places=6)

    def test_the_rider_sits_the_tacked_horse(self):
        # the seated clip read back onto the rider's skeleton: the seat at the model's origin, each ankle over its
        # stirrup's tread (the horse's manifest: the saddle's seat and the irons)
        g = Gltf(os.path.join(ASSETS, "rider.glb"))
        e = self.doc["roles"]["rider"]["poses"]["hold"]
        self.assertEqual((e["clip"], e["key"]), ("seated", 0))
        J = {b: blender_to_gltf(np.asarray(p)) for b, p in e["joints"].items()}
        hip = 0.5 * (J["thigh_l"] + J["thigh_r"])
        self.assertLess(abs(hip[1] - pr.SEAT_DROP_M), 0.03, "the hips over the seat (%.3f)" % hip[1])
        self.assertLess(abs(hip[2]), 0.05, "the seat under the hips")
        sx, sy, sz = pr.STIRRUP_M
        for side, sg in (("l", 1.0), ("r", -1.0)):
            want = np.array([sg * sx, sz + pr.RIDER_ANKLE_OVER_TREAD_M, -(sy + pr.RIDER_ANKLE_BEHIND_M)])
            got = J["foot_" + side]
            self.assertLess(float(np.linalg.norm(got - want)), 0.03, "the %s ankle in its stirrup (%s, %s)" % (
                side, np.round(got, 3), np.round(want, 3)))
        with open(os.path.join(CREATURES, "manifest.json"), encoding="utf-8") as fh:
            seat = json.load(fh)["index"]["horse"]["landmarks"]["saddle_seat"]["position"]
        self.assertAlmostEqual(seat[1] + pr.STIRRUP_M[2], 0.915, delta=0.03, msg="the treads' height on the horse")
        self.assertIn("rider_a", g.mesh_nodes())

    def test_the_grip_landmarks(self):
        # P59b: each variant's hands carry where a handle passes through the curled fingers (PersonRig's fist)
        for r in pr.ROLE_ORDER:
            for name, e in self.doc["roles"][r]["variants"].items():
                for side, sg in (("l", -1.0), ("r", 1.0)):
                    p = np.asarray(e["grip_local_" + side])
                    a = np.asarray(e["grip_axis_" + side])
                    self.assertTrue(0.06 < float(np.linalg.norm(p)) < 0.13, "%s %s: the grip %.3f m from the wrist" % (
                        name, side, float(np.linalg.norm(p))))
                    self.assertAlmostEqual(float(np.linalg.norm(a)), 1.0, places=4)
                    self.assertGreater(float(p[1]), 0.05, "%s: in front of the wrist, along the hand" % name)
                    self.assertGreater(abs(float(a[0])), 0.4, "%s: the handle runs across the palm" % name)


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

    def test_the_atlas_layout_and_the_mail_rings(self):
        # P59b: the regions and the tiles do not overlap; the mail's numbers are the person shader's
        rects = [r for _n, r in pr.ATLAS_REGIONS] + [(u, v, u + pr.TILE_SIZE, v + pr.TILE_SIZE)
                                                       for u, v in pr.TILES.values()]
        for i, a in enumerate(rects):
            self.assertTrue(0.0 <= a[0] < a[2] <= 1.0 and 0.0 <= a[1] < a[3] <= 1.0, a)
            for b in rects[i + 1:]:
                self.assertTrue(a[2] <= b[0] or b[2] <= a[0] or a[3] <= b[1] or b[3] <= a[1], "%s and %s" % (a, b))
        with open(os.path.join(ROOT, "assets", "shaders", "person.gdshader"), encoding="utf-8") as fh:
            shader = fh.read()
        import re
        num = lambda name: [float(x) for x in re.search(r"const \w+ %s = (?:vec\d\()?([^;)]*)" % name, shader).group(1).split(",")]  # noqa: E731
        self.assertAlmostEqual(num("MAIL_RINGS_PER_UV")[0], pr.MAIL_RINGS_PER_UV, places=3)
        self.assertAlmostEqual(num("MAIL_TILE_RINGS")[0], pr.MAIL_TILE_RINGS)
        self.assertAlmostEqual(num("TILE_SIZE")[0], pr.TILE_SIZE)
        u0, v0, u1, v1 = dict(pr.ATLAS_REGIONS)["side"]
        self.assertEqual(num("MAIL_RECT"), [u0, 1.0 - v1, u1, 1.0 - v0], "the side rect in Godot's UV (v down)")
        tu, tv = pr.TILES["mail"]
        self.assertEqual(num("MAIL_TILE"), [tu, 1.0 - tv - pr.TILE_SIZE])
        self.assertAlmostEqual(num("MAIL_SHADE")[0], sum(pr.MATERIALS["mail"]["albedo"]) / 3.0, places=3)
        # the mail tile's rings in the albedo (a pattern, not a flat colour)
        from PIL import Image
        im = np.asarray(Image.open(os.path.join(ASSETS, "soldier_albedo.png")).convert("L"), np.float64)
        n = im.shape[0]
        cell = im[int((1 - tv - pr.TILE_SIZE) * n):int((1 - tv) * n), int(tu * n):int((tu + pr.TILE_SIZE) * n)]
        self.assertGreater(float(cell.std()), 20.0, "the mail tile holds rings")

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
        self.assertEqual(t["horse"], t["body"] + t["eyes"] + t["mane"] + t["tail"])

    def test_the_manifest_and_the_import_settings(self):
        self.assertEqual(build_people.shipped_problems(self.doc, build_people.CREATURES), [])
        self.assertEqual(set(self.doc["files"]), {"assets/creatures/" + n for g in build_people.CREATURE_ORDER
                                                  for n in build_people.CREATURE_GROUPS[g]["files"]})
        for rel in self.doc["files"]:
            imp, typ, params = build_people.import_params(rel)
            with open(os.path.join(ROOT, rel + ".import"), encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn('importer="%s"' % imp, text, rel)
            for k, v in params.items():
                self.assertIn("\n%s=%s\n" % (k, v), text, "%s: %s" % (rel, k))
        self.assertEqual(self.doc["inputs"]["kit"], build_people.source_hashes(build_people.creature_sources()),
                         "the manifest was written from today's kit")

    def test_the_weights_follow_the_legs(self):
        qd = self.qd
        idx, w = qd.weights(np.array([[0.15, 0.53, 0.30], [-0.15, -0.71, 0.30], [0.0, 0.0, 1.55], [0.0, 1.3, 1.8]]))
        names = [[qd.BONES[i] for i, x in zip(r, wr) if x > 0.5] for r, wr in zip(idx, w)]
        self.assertEqual(names, [["fore_cannon_l"], ["hind_cannon_r"], ["spine_01"], ["head"]])


# --------------------------------------------------------------------------------------
# P63: the brutes and the wolves
# --------------------------------------------------------------------------------------
def enemy_record(name):
    with open(os.path.join(ROOT, "data", "enemies", name + ".json"), encoding="utf-8") as fh:
        return json.load(fh)


def joint_world(g, skin_index):
    """{bone: (3,) rest position, glTF frame} from a skin's inverse bind matrices."""
    sk = g.js["skins"][skin_index]
    ibm = g.accessor(sk["inverseBindMatrices"]).reshape(-1, 4, 4).transpose(0, 2, 1)
    return {g.js["nodes"][j]["name"]: np.linalg.inv(ibm[k])[:3, 3] for k, j in enumerate(sk["joints"])}


class TestBrutes(unittest.TestCase):
    """The ogre and the troll (the whelp its variant), the bosses' gear, the far meshes and the clips (plan §3.16)."""

    @classmethod
    def setUpClass(cls):
        import brute
        cls.br = brute
        cls.doc = load_creatures()
        cls.g = {k: Gltf(os.path.join(CREATURES, k + ".glb")) for k in brute.KIND_ORDER}

    def test_the_kinds_their_variants_gear_and_far_meshes(self):
        br = self.br
        for kind in br.KIND_ORDER:
            g, info = self.g[kind], self.doc[kind]
            nodes = g.mesh_nodes()
            want = {v["name"] for v in br.KINDS[kind]["variants"]} | {v["name"] + "_far" for v in
                                                                       br.KINDS[kind]["variants"]}
            want |= {b + "_gear" for b in br.KINDS[kind]["gear"]}
            self.assertEqual(set(nodes), want, kind)
            for name, (_i, nd) in nodes.items():
                m, prim, P, T, UV = variant_mesh(g, nd)
                self.assertEqual(len(m["primitives"]), 1, "%s: one surface" % name)
                limit = br.FAR_TRIS if name.endswith("_far") else (br.GEAR_TRIS_MAX if name.endswith("_gear")
                                                                    else br.TRIS_MAX)
                self.assertLessEqual(len(T), limit, name)
                if name.endswith("_far"):
                    continue
                skin = g.js["skins"][nd["skin"]]
                names = [g.js["nodes"][j]["name"] for j in skin["joints"]]
                self.assertEqual(sorted(names), sorted(pr.BONES), "%s: the 23 bones" % name)
                a = prim["attributes"]
                self.assertIn("TANGENT", a)
                self.assertNotIn("JOINTS_1", a)
                W = g.accessor(a["WEIGHTS_0"]).astype(np.float64)
                self.assertTrue(np.allclose(W.sum(axis=1), 1.0, atol=2e-3), name)
            for v in br.KINDS[kind]["variants"]:
                f = info["variants"][v["name"]]
                self.assertGreater(f["tris"], 7000, "%s: about 9,000 triangles" % v["name"])
                self.assertAlmostEqual(f["height_m"] * f["game_scale"], v["height_m"], places=4)
            self.assertAlmostEqual(info["variants"][br.KINDS[kind]["variants"][0]["name"]]["height_m"],
                                   br.KINDS[kind]["height_m"], delta=0.03, msg="%s at its height" % kind)

    def test_the_box_rigs_numbers_are_the_records(self):
        for kind, spec in self.br.KINDS.items():
            for rec, box in spec["box"].items():
                r = enemy_record(rec)
                self.assertEqual(box["height_m"], r["height_m"], rec)
                self.assertEqual(list(box["pivot"]), r["weapon_pivot_m"], rec)
                self.assertEqual(box["arm"], r["arm_length_m"], rec)

    def test_the_arms_reach_the_box_rigs_reach_bands_within_5_percent(self):
        """Every grip the box rig's arm reaches from its pivot is within the brute's own reach from its shoulder, and
        the brute's reach is no longer than that by more than 5 % (recomputed from the glTF's skeleton)."""
        br = self.br
        seen = set()
        for kind in br.KIND_ORDER:
            g, info = self.g[kind], self.doc[kind]
            nodes = g.mesh_nodes()
            for v in br.KINDS[kind]["variants"]:
                f = info["variants"][v["name"]]
                J = joint_world(g, nodes[v["name"]][1]["skin"])
                sh = J["upperarm_l"]
                el, wr = J["lowerarm_l"], J["hand_l"]
                arm = float(np.linalg.norm(el - sh) + np.linalg.norm(wr - el))
                knuckle = f["reach_m"] - arm
                self.assertTrue(0.03 * f["height_m"] < knuckle < 0.15 * f["height_m"], "%s: the palm" % v["name"])
                for rec, band in f["reach_bands"].items():
                    box = br.KINDS[kind]["box"][rec]
                    k = box["height_m"] / f["height_m"]
                    pivot = np.array([box["pivot"][0], box["pivot"][1], box["pivot"][2]])
                    shoulder = np.array([abs(sh[0]), sh[1], -sh[2]]) * k      # glTF +z is the model's front
                    need = float(np.linalg.norm(pivot - np.array([shoulder[0], shoulder[1], -shoulder[2]]))) + box["arm"]
                    reach = f["reach_m"] * k
                    self.assertAlmostEqual(reach / need, band["ratio"], delta=0.01, msg=rec)
                    self.assertLessEqual(abs(reach / need - 1.0), br.REACH_TOL, "%s: reach %.3f, need %.3f" % (
                        rec, reach, need))
                    seen.add(rec)
        self.assertEqual(seen, {r for spec in br.KINDS.values() for r in spec["box"]}, "every box record measured")

    def test_the_clips(self):
        br = self.br
        for kind in br.KIND_ORDER:
            g = Gltf(os.path.join(CREATURES, kind + "_clips.glb"))
            self.assertEqual(sorted(a["name"] for a in g.js["animations"]), sorted(br.CLIP_FRAMES), kind)
            clips = self.doc[kind]["clips"]
            self.assertLess(clips["conversion_error_m"], 1e-3)
            for n in ("walk", "run"):
                gait = clips["gaits"][n]
                self.assertEqual(gait["slide_m"], 0.0, "%s %s: no slide" % (kind, n))
                self.assertAlmostEqual(gait["stride_m"], 2.0 * br.KINDS[kind]["step_m"], places=2)
            for a in g.js["animations"]:
                bones = {g.js["nodes"][c["target"]["node"]]["name"] for c in a["channels"]}
                self.assertEqual(bones, set(br.PARTIAL_CLIPS.get(a["name"], pr.BONES)), a["name"])

    def test_the_skin_and_the_maps(self):
        from PIL import Image
        for kind in self.br.KIND_ORDER:
            img = np.asarray(Image.open(os.path.join(CREATURES, kind + "_orm.png")).convert("RGB"))
            self.assertEqual(img.shape, (256, 256, 3))
            with Image.open(os.path.join(CREATURES, kind + "_albedo.png")) as alb:
                self.assertEqual(alb.size, (512, 512))
            g = self.g[kind]
            name = self.br.KINDS[kind]["variants"][0]["name"]
            _m, _prim, _P, T, UV = variant_mesh(g, g.mesh_nodes()[name][1])
            bands = triangle_bands(img, UV, T)
            share = {b: float((bands == b).mean()) for b in pr.BANDS}
            self.assertGreater(share["skin"], 0.6, "%s: mostly its hide (%s)" % (kind, share))
            self.assertGreater(share["cloth"], 0.005, "%s's loincloth" % kind)
            gear = list(g.mesh_nodes()[b + "_gear"][1] for b in self.br.KINDS[kind]["gear"])
            for nd in gear:
                _m, _prim, _P, T2, UV2 = variant_mesh(g, nd)
                self.assertNotIn("skin", set(triangle_bands(img, UV2, T2)), "the gear is no skin")


class TestStoneback(unittest.TestCase):
    """A1: Stoneback, the quarry titan (kit/stoneback.py): 17.7 m (A3; 16.8 m before), his body, the stone plates each its own node, the
    shackles, the trunk-club, the boulder, the far mesh; his clips and maps."""

    @classmethod
    def setUpClass(cls):
        import stoneback
        cls.sb = stoneback
        cls.doc = load_creatures()
        cls.info = cls.doc["stoneback"]
        cls.g = Gltf(os.path.join(CREATURES, "stoneback.glb"))
        cls.nodes = cls.g.mesh_nodes()

    def test_every_piece_is_its_own_skinned_node(self):
        sb = self.sb
        want = {"stoneback", "stoneback_far", "shackles", "club", "boulder"} | set(sb.PLATE_ORDER)
        self.assertEqual(set(self.nodes), want)
        self.assertEqual(set(self.info["pieces"]), want - {"stoneback", "stoneback_far"})
        self.assertTrue({"plate_shoulder_l", "plate_shoulder_r", "plate_back", "plate_brow"} <= set(sb.PLATE_ORDER))
        self.assertEqual(self.info["weak_points"], {"plate_shoulder_l": "shoulder_l", "plate_shoulder_r": "shoulder_r",
                                                    "plate_back": "back", "plate_brow": "brow"})
        for name, (_i, nd) in self.nodes.items():
            m, prim, P, T, UV = variant_mesh(self.g, nd)
            self.assertEqual(len(m["primitives"]), 1, "%s: one surface" % name)
            if name.endswith("_far"):
                self.assertLessEqual(len(T), sb.FAR_TRIS)
                continue
            skin = self.g.js["skins"][nd["skin"]]
            names = [self.g.js["nodes"][j]["name"] for j in skin["joints"]]
            self.assertEqual(sorted(names), sorted(pr.BONES), "%s: the 23 bones" % name)
            a = prim["attributes"]
            self.assertIn("TANGENT", a, name)
            W = self.g.accessor(a["WEIGHTS_0"]).astype(np.float64)
            self.assertTrue(np.allclose(W.sum(axis=1), 1.0, atol=2e-3), name)
            budget = sb.TRIS if name == "stoneback" else (sb.PLATES[name][4] if name in sb.PLATES
                                                           else sb.GEAR_BUDGET[name])
            self.assertLessEqual(len(T), budget, name)
            self.assertGreater(len(T), 100, name)

    def test_his_height_is_58_feet(self):
        """A3: 17.7 m (58 ft; A1-A2: 16.8 m)."""
        _m, _prim, P, _T, _UV = variant_mesh(self.g, self.nodes["stoneback"][1])
        h = float(P[:, 1].max() - min(0.0, P[:, 1].min()))
        self.assertAlmostEqual(self.sb.HEIGHT_M, 17.7, places=6)
        self.assertAlmostEqual(h, 17.7, delta=17.7 * 0.02, msg="the body %.3f m" % h)
        self.assertAlmostEqual(self.info["variants"]["stoneback"]["height_m"], 17.7, delta=0.354)
        self.assertLess(self.info["variants"]["stoneback"]["height_with_plates_m"], 17.7 * 1.04, "the brow plate")

    def test_the_plates_lie_on_the_body(self):
        """Each plate's points lie over the skin it covers: none farther than its thickness and a little out, the rim
        no deeper than its sink (the rest pose, the glTF's metres). A1b: a plate of two slabs (one laid over the other)
        is measured against the two's thickness (stoneback.plate_depth_m); its bands lie on it."""
        from scipy.spatial import cKDTree
        _m, _prim, B, BT, _UV = variant_mesh(self.g, self.nodes["stoneback"][1])
        kd = cKDTree(B)
        for name in self.sb.PLATE_ORDER:
            _m, _prim, P, _T, _UV = variant_mesh(self.g, self.nodes[name][1])
            d, _i = kd.query(P)
            thick = self.sb.plate_depth_m(name)
            # (to the low mesh's vertices; A3: the measure is made at A1's 16.8 m and scaled with his height - the
            # body's triangles, so the distance from a plate's points to their nearest vertex, grew with him)
            k = self.sb.HEIGHT_M / 16.8
            self.assertLess(float(np.percentile(d, 95)), (2.0 * thick + 0.3) * k, name)
            self.assertLess(float(d.mean()), (thick + 0.15) * k, name)

    def test_the_club_and_the_boulder_are_rigid_in_their_hands(self):
        for name, bone in (("club", "hand_r"), ("boulder", "hand_l")):
            nd = self.nodes[name][1]
            _m, prim, _P, _T, _UV = variant_mesh(self.g, nd)
            J = self.g.accessor(prim["attributes"]["JOINTS_0"]).astype(np.int64)
            W = self.g.accessor(prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
            joints = self.g.js["skins"][nd["skin"]]["joints"]
            top = {self.g.js["nodes"][joints[j]]["name"] for j in J[np.arange(len(J)), np.argmax(W, axis=1)]}
            self.assertEqual(top, {bone}, name)
            self.assertTrue(np.allclose(W.max(axis=1), 1.0, atol=1e-3), name)
        self.assertGreater(self.info["pieces"]["club"]["length_m"], 7.0)
        self.assertEqual(len(self.info["pieces"]["club"]["head_local"]), 3)
        # the idle's root ball rests on the ground (A1b: on it, not in it: its lowest point 0 to 10 cm over it)
        self.assertGreaterEqual(self.info["checks"]["idle_club_lowest_m"], 0.0)
        self.assertLess(self.info["checks"]["idle_club_lowest_m"], 0.1)
        # the overhead's left fist lies on the trunk
        self.assertLess(self.info["checks"]["overhead_left_off_trunk_m"], 0.4)

    def test_the_plates_are_slabs_held_by_iron_bands(self):
        """A1b: each plate's mesh carries its iron bands (vertex colour alpha 0) beside its stone (alpha 1); the club
        its earth (alpha 0.5); the body none."""
        for name, (_i, nd) in self.nodes.items():
            _m, prim, _P, _T, _UV = variant_mesh(self.g, nd)
            has = "COLOR_0" in prim["attributes"]
            self.assertEqual(has, name in self.sb.PLATES or name == "club", name)
            if not has:
                continue
            C = self.g.accessor(prim["attributes"]["COLOR_0"]).astype(np.float64)
            C = C / (65535.0 if C.max() > 255.0 else (255.0 if C.max() > 1.0 else 1.0))
            a = C[:, 3]
            if name == "club":
                self.assertTrue(((a > 0.4) & (a < 0.6)).any(), "the club's earth")
                continue
            self.assertTrue((a < 0.1).sum() >= 96, "%s: its bands" % name)
            self.assertTrue((a > 0.9).sum() >= 50, "%s: its stone" % name)
            self.assertEqual(self.info["pieces"][name]["bands"], len(self.sb.PLATE_FORM[name]["bands"]), name)

    def test_the_clips(self):
        g = Gltf(os.path.join(CREATURES, "stoneback_clips.glb"))
        self.assertEqual(sorted(a["name"] for a in g.js["animations"]), sorted(self.sb.CLIP_FRAMES))
        clips = self.info["clips"]
        self.assertLess(clips["conversion_error_m"], 1e-3)
        self.assertEqual({n for n, c in clips["clips"].items() if c["windup"]}, {"overhead", "charge", "throw"})
        for n in ("walk", "run"):
            self.assertEqual(clips["gaits"][n]["slide_m"], 0.0, "%s: no slide" % n)
            self.assertAlmostEqual(clips["gaits"][n]["stride_m"], 2.0 * self.sb.STEP_M, delta=0.05)

    def test_he_stands_tall(self):
        """A3: he carries his head near his full height - in the idle, as he walks and runs, at each telegraph's peak
        (a heavy, forward stance, not a crouch): above a stage-5 giant (14.63 m) by a head and more."""
        H = self.sb.HEIGHT_M
        crown = self.info["checks"]["crown_m"]
        self.assertGreaterEqual(crown["idle"][0], 0.97 * H, crown["idle"])
        self.assertGreaterEqual(crown["walk"][0], 0.94 * H, crown["walk"])
        self.assertLessEqual(crown["walk"][1] - crown["walk"][0], 0.5, "the walk's bob %s" % crown["walk"])
        self.assertGreaterEqual(crown["run"][0], 0.92 * H, crown["run"])
        self.assertGreaterEqual(crown["roar"][0], 0.95 * H, crown["roar"])
        for peak in ("overhead_peak", "charge_peak", "throw_peak"):
            self.assertGreaterEqual(crown[peak], 0.89 * H, "%s %.2f" % (peak, crown[peak]))
        stage5 = 14.6304
        self.assertGreater(crown["walk"][0] - stage5, 2.0, "a head over the stage-5 giant as he walks")

    def test_he_goes_down_on_a_knee(self):
        """A4: the kneel's held pose (its last frame) puts his right knee on the ground and lowers his crown into a
        stage-5 giant's reach; the bones the gameplay body follows (tools/builders/titans.gd KNEEL_FOLLOW) are in the
        manifest for the idle and the kneel; the kneel and the rise are clips."""
        H = self.sb.HEIGHT_M
        k = self.info["checks"]["kneel"]
        self.assertLess(k["knee_on_ground_m"], 0.6, "the knee on the ground (%.2f m)" % k["knee_on_ground_m"])
        self.assertLess(k["kneel_crown_m"], 0.72 * H, "his crown comes down (%.2f m)" % k["kneel_crown_m"])
        self.assertGreater(k["kneel_crown_m"], 0.5 * H, "on a knee, not lying down")
        self.assertAlmostEqual(k["idle_crown_m"], self.info["checks"]["crown_m"]["idle"][0], delta=0.2)
        self.assertEqual(set(k["bones"]), set(self.sb.KNEEL_BONES))
        for b, v in k["bones"].items():
            self.assertEqual(set(v), {"idle", "kneel"}, b)
            for key in ("idle", "kneel"):
                self.assertEqual(len(v[key]["head"]), 3, b)
                self.assertEqual(len(v[key]["basis"]), 9, b)
        self.assertLess(k["bones"]["head"]["kneel"]["head"][1], k["bones"]["head"]["idle"]["head"][1] - 4.0)
        self.assertIn("kneel", self.info["clips"]["clips"])
        self.assertIn("rise", self.info["clips"]["clips"])

    def test_the_maps_and_the_detail_textures(self):
        from PIL import Image
        img = np.asarray(Image.open(os.path.join(CREATURES, "stoneback_orm.png")).convert("RGB"))
        self.assertEqual(img.shape, (256, 256, 3))
        _m, _prim, _P, T, UV = variant_mesh(self.g, self.nodes["stoneback"][1])
        bands = triangle_bands(img, UV, T)
        self.assertGreater(float((bands == "skin").mean()), 0.6, "mostly his skin")
        for what in ("stone", "bark"):
            for k in ("albedo", "normal"):
                a = np.asarray(Image.open(os.path.join(CREATURES, "stoneback_%s_%s.png" % (what, k))).convert("RGB"))
                a = a.astype(np.float64)
                self.assertEqual(a.shape, (256, 256, 3))
                # tileable: the edge's columns and rows join as closely as two neighbours inside
                inner = float(np.abs(a[:, 128] - a[:, 127]).mean()) + 1.0
                self.assertLess(float(np.abs(a[:, 0] - a[:, -1]).mean()), 2.5 * inner, "%s %s across" % (what, k))
                inner = float(np.abs(a[128] - a[127]).mean()) + 1.0
                self.assertLess(float(np.abs(a[0] - a[-1]).mean()), 2.5 * inner, "%s %s down" % (what, k))


class TestWolf(unittest.TestCase):
    """The wolf (the dire wolf by scale and palette): the body, its fur cards, the shell's mesh and map, the far mesh."""

    @classmethod
    def setUpClass(cls):
        import quadruped as qd
        cls.qd = qd
        cls.g = Gltf(os.path.join(CREATURES, "wolf.glb"))
        cls.doc = load_creatures()
        cls.info = cls.doc["wolf"]

    def mesh(self, name):
        _i, nd = self.g.mesh_nodes()[name]
        return (nd,) + variant_mesh(self.g, nd)

    def test_the_meshes_on_the_25_bones(self):
        self.assertEqual(set(self.g.mesh_nodes()), {"wolf", "wolf_shell", "wolf_far"})
        for name in ("wolf", "wolf_shell"):
            nd, m, prim, P, T, UV = self.mesh(name)
            self.assertEqual(len(m["primitives"]), 1)
            self.assertLessEqual(len(T), self.qd.TRIS_MAX)
            names = [self.g.js["nodes"][j]["name"] for j in self.g.js["skins"][nd["skin"]]["joints"]]
            self.assertEqual(sorted(names), sorted(self.qd.BONES))
            W = self.g.accessor(prim["attributes"]["WEIGHTS_0"]).astype(np.float64)
            self.assertTrue(np.allclose(W.sum(axis=1), 1.0, atol=2e-3))
            self.assertLess(abs(float(P[:, 1].min())), 0.012, "%s stands on the ground" % name)
        _nd, _m, _p, _P, T, _UV = self.mesh("wolf_far")
        self.assertLessEqual(len(T), self.qd.WOLF_FAR_TRIS)
        self.assertLessEqual(self.info["triangles"]["wolf_shell"], self.qd.WOLF_SHELL_TRIS)

    def test_the_body_is_closed_and_the_measures(self):
        _nd, _m, _prim, P, T, UV = self.mesh("wolf")
        c = UV[T].mean(axis=1)
        body = T[(c[:, 0] < 0.75) & (c[:, 1] < 0.75)]
        self.assertEqual(len(body), self.info["triangles"]["body"])
        V, W = weld_positions(P.astype(np.float64), body)
        self.assertTrue(self.qd.directed_edges_ok(W))
        m = self.info["measures"]
        self.assertTrue(0.75 < m["withers_m"] < 0.85, "a grey wolf's withers (%.3f)" % m["withers_m"])
        self.assertTrue(1.3 < m["length_m"] < 1.6)
        self.assertEqual(self.info["sizes"], {"wolf": 1.0, "dire_wolf": 2.0})

    def test_the_bands_the_fur_and_the_eyes(self):
        from PIL import Image
        img = np.asarray(Image.open(os.path.join(CREATURES, "wolf_orm.png")).convert("RGB"))
        _nd, _m, _prim, P, T, UV = self.mesh("wolf")
        bands = triangle_bands(img, UV, T)
        c = UV[T].mean(axis=1)
        body = (c[:, 0] < 0.75) & (c[:, 1] < 0.75)
        fur = (c[:, 0] < 0.75) & (c[:, 1] > 0.75)
        share = {b: float((bands[body] == b).mean()) for b in pr.BANDS}
        self.assertGreater(share["skin"], 0.8, "the coat (%s)" % share)
        self.assertGreater(share["hair"], 0.01, "the dark markings")
        self.assertTrue((bands[fur] == "skin").all(), "the fur cards take the coat's colour")
        eyes = c[:, 0] > 0.75
        self.assertIn("cloth", set(bands[eyes]), "the eyes take the palette's eye colour")
        alb = np.asarray(Image.open(os.path.join(CREATURES, "wolf_albedo.png")))
        self.assertEqual(alb.shape, (512, 512, 4))
        self.assertLess(int(alb[384:, :384, 3].min()), 20, "the fur tile has gaps")
        self.assertEqual(int(alb[:384, :384, 3].min()), 255, "the body is opaque")
        fm = np.asarray(Image.open(os.path.join(CREATURES, "wolf_fur.png")).convert("RGB")).astype(np.float64)
        self.assertEqual(fm.shape, (256, 256, 3))
        d = fm[:192, :192, :2] / 255.0 * 2.0 - 1.0
        n = np.linalg.norm(d, axis=-1)
        self.assertGreater(float((np.abs(n - 1.0) < 0.05).mean()), 0.8, "the flow is a unit direction")

    def test_the_poses(self):
        poses = self.info["poses"]
        self.assertEqual(sorted(poses), sorted(self.qd.WOLF_POSE_ORDER))
        for name, p in poses.items():
            self.assertTrue(0.95 < p["volume_ratio"] < 1.05, "%s: %.3f" % (name, p["volume_ratio"]))
            self.assertGreater(p["lowest_m"], -0.02, name)
            for k, v in p["stretch_p99"].items():
                self.assertLess(v, 2.0, "%s: the %s's skin" % (name, k))
        g = Gltf(os.path.join(CREATURES, "wolf_poses.glb"))
        self.assertEqual(sorted(a["name"] for a in g.js["animations"]), sorted(self.qd.WOLF_POSE_ORDER))
        idx, w = self.qd.weights(np.array([[0.072, 0.27, 0.10], [0.0, 0.0, 0.74], [0.0, 0.62, 0.85]]), self.qd.WOLF)
        names = [[self.qd.BONES[i] for i, x in zip(r, wr) if x > 0.5] for r, wr in zip(idx, w)]
        self.assertEqual(names, [["fore_cannon_l"], ["spine_01"], ["head"]])


class TestHorseCloseUp(unittest.TestCase):
    """P63's close-up pass on the horse: its skeleton and seat unchanged, the eyes, the mane's volume, the stirrups
    outside the housing, the skin over the shoulder and the stifle at the gallop's extremes."""

    @classmethod
    def setUpClass(cls):
        import quadruped as qd
        cls.qd = qd
        cls.info = load_creatures()["horse"]

    def test_the_skeleton_and_the_seat_are_p61s(self):
        self.assertEqual(self.info["landmarks"]["saddle_seat"], {"bone": "spine_01", "position": [0.0, 1.608, 0.16]})
        J = self.qd.joints()
        self.assertEqual([round(float(x), 6) for x in J["spine_01"][0]], [0.0, -0.16, 1.33])
        self.assertEqual([round(float(x), 6) for x in J["neck"][1]], [0.0, 1.03, 1.79])

    def test_the_close_up_pieces(self):
        t = self.info["triangles"]
        self.assertGreater(t["eyes"], 0)
        self.assertGreater(t["mane"], 220, "the mane has more cards than P61's")
        self.assertGreater(t["tail"], 70, "the tail has more cards than P61's")
        for name in ("gallop_extended", "gallop_gathered"):
            for k, v in self.info["poses"][name]["stretch_p99"].items():
                self.assertLess(v, 2.0, "%s: the %s's skin (P61's 4.2 and 3.6)" % (name, k))
        st = self.info["stirrups"]
        self.assertGreater(st["irons_x_min_m"], st["housing_x_max_m"], "the irons hang outside the housing")


class TestLookPass(unittest.TestCase):
    """P65a's look pass: the wolf's head and fur, the saddle's shape, the bosses' gear, the people's face normals."""

    def test_the_wolfs_head_and_fur(self):
        import quadruped as qd
        h = qd.WOLF
        # the muzzle (from the stop, where the upper muzzle begins, to the nose) about 45 % of the head's length
        stop = 0.656
        back = 0.570 - 0.082
        ratio = (h["muzzle"][1] - stop) / (h["muzzle"][1] - back)
        self.assertTrue(0.40 < ratio < 0.50, "the muzzle %.2f of the head" % ratio)
        info = load_creatures()["wolf"]
        self.assertLessEqual(info["triangles"]["fur"], 64, "the ruff is the body's volume: cards on the tail only")
        self.assertEqual(qd.TAIL_CARDS, 8, "the horse's tail keeps its cards (the wolf's constants are its own)")

    def test_the_saddle_has_a_pommel_and_a_cantle(self):
        import quadruped as qd

        def top(u):
            z = np.arange(1.90, 1.20, -0.002)
            P = np.stack([np.zeros_like(z), np.full_like(z, u), z], axis=1)
            inside = np.nonzero(qd.saddle_sdf(P) < 0.0)[0]
            return float(P[inside[0], 2])
        seat = top(qd.SEAT_U)
        self.assertAlmostEqual(seat, 1.608, places=3)
        self.assertGreater(top(0.355) - seat, 0.05, "the pommel")
        self.assertGreater(top(-0.065) - seat, 0.04, "the cantle")

    def test_the_bosses_gear(self):
        import brute
        doc = load_creatures()
        for kind, boss in (("ogre", "ogre_king"), ("troll", "troll_matriarch")):
            g = doc[kind]["gear"][boss]
            self.assertLessEqual(g["tris"], brute.GEAR_TRIS_MAX)
            self.assertIn("hide_mantle", g["pieces"])
        self.assertIn("collar_tile", brute.MANTLE["ogre_king"])

    def test_the_faces_keep_their_own_normals(self):
        from PIL import Image
        u0, v0, u1, v1 = dict(pr.ATLAS_REGIONS)["head"]
        for role in pr.ROLE_ORDER:
            n = np.asarray(Image.open(os.path.join(ASSETS, role + "_normal.png")).convert("RGB")).astype(np.int64)
            size = n.shape[0]
            rect = n[int((1 - v1) * size):int((1 - v0) * size), int(u0 * size):int(u1 * size)]
            flat = (np.abs(rect - np.array([128, 128, 255])).max(axis=-1) <= 2).mean()
            self.assertGreater(float(flat), 0.5, "%s: the head's skin texels flat (%.2f)" % (role, flat))


class TestLookPassC(unittest.TestCase):
    """P65c: the wolf's open mouth and teeth, its bare ears and muzzle in the fur map, the brutes' grip landmarks, the
    crotch kept under the loincloth, the bosses' mantles."""

    def test_the_wolfs_mouth_and_teeth(self):
        import quadruped as qd
        info = load_creatures()["wolf"]
        self.assertGreater(info["triangles"]["teeth"], 100)
        self.assertLessEqual(info["triangles"]["wolf"], qd.TRIS_MAX)
        t = qd.wolf_teeth()
        # every tooth hidden in the closed mouth: inside the body or inside the mouth's gap, never outside both
        outside = (qd.wolf_sdf(t.V) > 0.0) & (qd.wolf_mouth_cut(t.V) > 0.0)
        self.assertFalse(outside.any(), "a tooth shows through the closed lips")
        # the jaw bone carries what is under the gap, the head what is over it (the bite opens the mouth)
        a, b, _ra, _rb = qd._jaw_axis()
        mid = a + (b - a) * 0.6
        lower = mid + np.array([0.0, 0.0, -0.005])
        upper = mid.copy()
        upper[2] = qd._ray_to(qd.wolf_lower_jaw, mid, np.array([0.0, 0.0, 1.0]), qd.WOLF_GAP_M)[2] + 0.004
        idx, w = qd.weights(np.array([lower, upper]), qd.WOLF)
        names = [qd.BONES[i[0]] for i in idx]
        self.assertEqual(names, ["jaw", "head"])
        # the lip line runs straight or down toward the corner of the mouth (P65a's rose to it: a smile)
        def lo(u):                     # the flews' lower edge at x 2.2 cm
            return min(z for z in np.arange(0.70, 0.78, 0.0005) if qd.wolf_flews(np.array([[0.022, u, z]]))[0] < 0.0)
        self.assertLessEqual(lo(0.655), lo(0.745) + 1e-3)

    def test_the_ears_muzzle_and_shins_are_near_bare(self):
        import quadruped as qd
        P = np.array([[0.060, 0.550, 0.935], [0.0, 0.700, 0.800], [0.072, 0.285, 0.12], [0.0, 0.10, 0.75]])
        L = qd.wolf_fur_length(P)
        self.assertTrue((L[:3] < 0.1).all(), L)
        self.assertGreater(L[3], 0.4, "the back keeps its fur")

    def test_the_brutes_grip_landmarks(self):
        idx = load_creatures()["index"]
        for kind in ("ogre", "troll"):
            for name, v in idx[kind]["variants"].items():
                for sd in ("l", "r"):
                    g, ax = np.array(v["grip_local_" + sd]), np.array(v["grip_axis_" + sd])
                    self.assertAlmostEqual(float(np.linalg.norm(ax)), 1.0, places=3)
                    self.assertGreater(float(g[1]), 0.0, "%s: the grip lies toward the knuckles" % name)

    def test_the_crotch_kept_and_the_mantles(self):
        import brute
        self.assertGreater(brute.CROTCH_KEEP_M[0], 0.2)
        for boss in ("ogre_king", "troll_matriarch"):
            self.assertLessEqual(brute.MANTLE[boss]["hang_most"], 0.12, "the mantle falls close down the back")
        self.assertLess(brute.MANTLE["troll_matriarch"]["collar_flat"], 1.0, "a flat fold, not a roll")


def front_view_bands(P, T, bands, res=0.01, rows=(0.40, 0.82)):
    """The bands seen from the front (glTF +Z, y up; an orthographic z-buffer of ``res`` m pixels) in the body's
    band of heights ``rows`` (shares of the mesh's height): {band: share of the covered pixels}."""
    x, y, d = P[:, 0], P[:, 1], P[:, 2]
    x0, y0 = float(x.min()), float(y.min())
    W, H = int((x.max() - x0) / res) + 2, int((y.max() - y0) / res) + 2
    zb = np.full((H, W), -1e9)
    ib = np.full((H, W), -1)
    for i, tri in enumerate(T):
        A = np.stack([x[tri], y[tri]], 1)
        lo = np.floor((A.min(0) - [x0, y0]) / res).astype(int)
        hi = np.minimum(np.ceil((A.max(0) - [x0, y0]) / res).astype(int), [W - 1, H - 1])
        X, Y = np.meshgrid(x0 + (np.arange(lo[0], hi[0] + 1) + 0.5) * res, y0 + (np.arange(lo[1], hi[1] + 1) + 0.5) * res)
        v0, v1 = A[1] - A[0], A[2] - A[0]
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if X.size == 0 or abs(den) < 1e-12:
            continue
        px, py = X - A[0, 0], Y - A[0, 1]
        b1 = (px * v1[1] - v1[0] * py) / den
        b2 = (v0[0] * py - px * v0[1]) / den
        b0 = 1.0 - b1 - b2
        dep = b0 * d[tri[0]] + b1 * d[tri[1]] + b2 * d[tri[2]]
        sl = (slice(lo[1], hi[1] + 1), slice(lo[0], hi[0] + 1))
        m = (b0 >= 0) & (b1 >= 0) & (b2 >= 0) & (dep > zb[sl])
        zb[sl][m] = dep[m]
        ib[sl][m] = i
    h = (np.arange(H) + 0.5) * res / max(float(y.max()) - y0, 1e-6)
    seen = ib[(h > rows[0]) & (h < rows[1])]
    seen = seen[seen >= 0]
    b = bands[seen]
    return {k: float((b == k).mean()) for k in pr.BANDS}


def lab(hex_colour):
    """CIE L*a*b* (D65) of an sRGB colour "#rrggbb"."""
    c = np.array([int(hex_colour[i:i + 2], 16) / 255.0 for i in (1, 3, 5)])
    c = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    M = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = M @ c / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.array([116.0 * f[1] - 16.0, 500.0 * (f[0] - f[1]), 200.0 * (f[1] - f[2])])


class TestFactionReads(unittest.TestCase):
    """Gate C: a formation's side reads from the front at 60 m. Every soldier (the line, the pikes, the shields, the
    banners, the iron guard) wears a surcoat in the faction band over the mail, at every level: each variant, each
    crowd pose standing up and the far mesh show the faction band over at least a third of the body's front between
    the thighs and the shoulders (it was about 1 %: the mail and the helm); and the factions' colours differ."""

    FRONT_FACTION_MIN = 0.33
    DELTA_E_MIN = 15.0

    def test_the_soldiers_front_is_the_factions_colour_at_every_level(self):
        g = Gltf(os.path.join(ASSETS, "soldier.glb"))
        img = orm("soldier")
        nodes = g.mesh_nodes()
        names = [v["name"] for v in pr.ROLES["soldier"]["variants"]] + ["soldier_far"] + \
            ["soldier_pose_" + p for p in pr.POSES if p != "corpse"]
        for name in names:
            _m, _p, P, T, UV = variant_mesh(g, nodes[name][1])
            share = front_view_bands(P, T, triangle_bands(img, UV, T))["faction"]
            self.assertGreaterEqual(share, self.FRONT_FACTION_MIN, "%s: the faction band %.2f of the front" % (name, share))

    def test_the_factions_colours_differ_and_agree_across_the_roles(self):
        tables = {}
        for r in pr.ROLE_ORDER:
            with open(os.path.join(ROOT, "data", "people", "role_%s.json" % r), encoding="utf-8") as fh:
                tables[r] = json.load(fh).get("factions", {})
        ref = tables["soldier"]
        for r, t in tables.items():
            self.assertEqual(t, ref, "role %s: the same faction colours as the soldiers'" % r)
        keys = sorted(ref)
        for i, a in enumerate(keys):
            for b in keys[i + 1:]:
                de = float(np.linalg.norm(lab(ref[a]) - lab(ref[b])))
                self.assertGreaterEqual(de, self.DELTA_E_MIN, "%s %s and %s %s: delta E %.1f" % (a, ref[a], b, ref[b], de))


if __name__ == "__main__":
    unittest.main(verbosity=1)
