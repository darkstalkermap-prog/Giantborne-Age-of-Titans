"""The giant's meshes as skinned glTFs for Godot 4.6 (the steps --body, --garments, --hair).

Builds the kit's giant at the stage-1 height (3.6576 m; the game scales Visual/Body by
k = height / 3.6576) on the MPFB2 "game_engine" skeleton (53 bones) with its CC0 weights and the 18
leaf bones of P48 (giant_parts.py: 71 bones), no subdivision. ``giant.glb`` holds the skeleton, the
three body meshes, ``Eyes`` and ``ShadowProxy`` (the body at about 2,500 triangles, for the shadow
passes); every hair, beard and garment mesh is written to ``parts/<mesh id>.glb`` on the same
skeleton, so the game loads a style or a garment when a look shows it (plan M11 §2.2). The meshes:

  Body_Head, Body_Torso, Body_Limbs   the hm08 body split at the neck, shoulders and hips (split.py),
                                      every cut capped on both sides, the joined body's normals kept,
                                      the 16 region ids in COLOR_0.r
  Eyes                                both eyes (low-poly spheres, the pole looks along the gaze)
  Hair_long_back, Hair_crop,          cards grown on the unsubdivided surface (giant_hair.py)
  Beard_full, Beard_short
  Garment_<id>[_core|_limbs]          the seven garments (giant_garment.py); the braies and the tunic
                                      split at the body's boundary with their cut loops capped; the
                                      boots decimated toward 2,500 triangles

Vertex colour: ``COLOR.r`` the region id, ``COLOR.g`` and ``.b`` the build sliders' brawn and girth
weights as 0.5 + 0.5 w (giant_parts.build_weights); garments and cards inherit the weights of the
body vertex they sit on or grew from. Hair and beard cards are weighted along their length to the
leaf chains (their roots on ``head``), the cape hangs free on its three chains.

and ``export_info.json`` beside it: per mesh its node, category, render layer, dye slot, detail map,
triangles, the regions it covers, its cut loops and caps, the chains it is weighted to and (for a
part) its file; the chains; the landmarks (the skeleton's joints at stage 1 in the game frame: +X the
giant's right, +Y up, -Z his front; the grips, knuckles and toes) and the body's hash.

Usage (the shared venv): python export_game.py <out dir>
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import giant_body as gb  # noqa: E402
import giant_garment as gg  # noqa: E402
import giant_hair as gh  # noqa: E402
import giant_parts as gp  # noqa: E402
import mh_data as mh  # noqa: E402
import split  # noqa: E402

H = gb.STAGE1_HEIGHT_M
GLB_NAME = "giant.glb"
PARTS_DIR = "parts"
SHADOW_NAME = "ShadowProxy"
# The meshes that stay in giant.glb; every other mesh is a part (parts/<mesh id>.glb).
CORE_CATEGORIES = ("body", "eyes")
INFO_NAME = "export_info.json"
EYE_SEGMENTS, EYE_RINGS = 20, 14
GARMENT_CAP_LIFT_M = 0.02          # human scale: a garment's cap sits this far outside the skin's
# The braies' one cut loop runs round both thighs, so its cap spans the skin's two thigh caps: lifted this far
# it covers them (P46: in first person looking down, the skin's caps showed through the cloth's).
GARMENT_CAP_LIFT_OF = {"braies": 0.2}
COVER_SHARE = 0.97                 # a region a garment covers this much of sinks under it (covers)
COVER_RAY_M = 0.12                 # human scale: the longest skin-to-garment ray that still covers
FREE_COVER_RAY_M = 0.30            # the same for a free-hanging mesh (the cape stands off the small of the back)
FREE_COVER_SHARE = 0.85            # and its share: it hangs straight, so the flanks' rays pass beside it
# P54: a garment's part ("split", "torso", "limbs" or "head") and whether it hangs free are its gg.GARMENTS entry's;
# a split garment is cut along the body's own boundary, but for the braies (not a shell: by their weights)
SPLIT_BY_WEIGHT = ("braies",)
PART_LAYER = {0: 3, 1: 2, 2: 1}    # head, torso, limbs -> their render layers
HAIR_CUT_LEAST = 0.3               # a style cut shorter than this under a head garment is not drawn there
LIMB_ROOTS = ("upperarm_l", "upperarm_r", "thigh_l", "thigh_r")
TORSO_ROOTS = ("clavicle_l", "clavicle_r", "pelvis")


def log(*a):
    print("[export]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


# --------------------------------------------------------------------------------------
# mesh arrays <-> Blender objects
# --------------------------------------------------------------------------------------
def mesh_arrays(ob):
    """{"V", "faces" (list of tuples), "corner_uv" (list of lists of (u, v)), "groups" {bone: (n,)},
    "vnormal" (n, 3)} of an object's mesh (no modifiers applied)."""
    me = ob.data
    n = len(me.vertices)
    V = np.empty(n * 3)
    me.vertices.foreach_get("co", V)
    V = V.reshape(-1, 3)
    nrm = np.empty(n * 3)
    me.vertex_normals.foreach_get("vector", nrm)
    loop_v = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", loop_v)
    uvl = me.uv_layers.get("UVMap") or (me.uv_layers[0] if len(me.uv_layers) else None)
    uv = np.zeros(len(me.loops) * 2)
    if uvl is not None:
        uvl.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    faces, corner_uv = [], []
    for p in me.polygons:
        ls = range(p.loop_start, p.loop_start + p.loop_total)
        faces.append(tuple(int(loop_v[i]) for i in ls))
        corner_uv.append([(float(uv[i, 0]), float(uv[i, 1])) for i in ls])
    groups = {}
    names = [g.name for g in ob.vertex_groups]
    for v in me.vertices:
        for g in v.groups:
            nm = names[g.group]
            if nm not in groups:
                groups[nm] = np.zeros(n)
            groups[nm][v.index] = g.weight
    return {"V": V, "faces": faces, "corner_uv": corner_uv, "groups": groups,
            "vnormal": nrm.reshape(-1, 3)}


def colour_attribute(me, vregion, vbuild=None):
    """The "Color" point attribute: R the region id, G and B the build weights (0.5 = none), A 1."""
    n = len(me.vertices)
    if "Color" in me.color_attributes:
        me.color_attributes.remove(me.color_attributes["Color"])
    col = me.color_attributes.new("Color", "BYTE_COLOR", "POINT")
    rgba = np.zeros((n, 4), np.float32)
    rgba[:, 0] = split.encode_region(vregion)
    rgba[:, 1:3] = 0.5 if vbuild is None else gp.encode_build(vbuild)
    rgba[:, 3] = 1.0
    col.data.foreach_set("color", rgba.ravel())


def make_object(name, A, coll, rig, material, vregion=None):
    """A skinned mesh object from arrays: V, faces, corner_uv, groups, corner_normal (list per face),
    and the region per vertex (with the build weights A["vbuild"], when there) in a "Color" attribute
    when ``vregion`` is given."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.asarray(A["V"], np.float64).tolist(), [], [list(f) for f in A["faces"]])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", np.asarray([c for f in A["corner_uv"] for c in f], np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    me.normals_split_custom_set([tuple(c) for f in A["corner_normal"] for c in f])
    if vregion is not None:
        colour_attribute(me, vregion, A.get("vbuild"))
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    for bone in sorted(A["groups"]):
        w = A["groups"][bone]
        idx = np.nonzero(w > 1e-4)[0]
        if len(idx) == 0:
            continue
        vg = ob.vertex_groups.new(name=bone)
        for i in idx.tolist():
            vg.add([i], float(w[i]), "REPLACE")
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(bpy.data.materials.get(material) or bpy.data.materials.new(material))
    return ob


def triangles(A):
    return int(sum(len(f) - 2 for f in A["faces"]))


# --------------------------------------------------------------------------------------
# split and cap
# --------------------------------------------------------------------------------------
def split_part(A, face_part, part, vregion, root_bone, lift=0.0, cap_uv_of=None, skin_rims=False):
    """The arrays of one part of a mesh (its faces, their vertices) with every closed cut loop
    capped: rim copies of the loop's vertices (their skin weights, region 15, the cap's normal)
    and a centre vertex weighted 100 % to ``root_bone(part, centre, other part)``. ``skin_rims`` (P54, the
    garments): the rim copies keep their vertex's own normal and the centre takes no build push, so the build
    sliders move a garment's cap with the cloth round it (the cap's normal pushed the rim along the limb: the sleeve's
    edge stood off in steps at -1).
    Returns (arrays, regions per local vertex, {"loops", "capped", "open_chains"})."""
    faces = A["faces"]
    sel = [i for i, p in enumerate(face_part) if p == part]
    vids = sorted({v for i in sel for v in faces[i]})
    local = {v: k for k, v in enumerate(vids)}
    V = [A["V"][v] for v in vids]
    out_faces = [tuple(local[v] for v in faces[i]) for i in sel]
    out_uv = [list(A["corner_uv"][i]) for i in sel]
    out_nrm = [[tuple(A["vnormal"][v]) for v in faces[i]] for i in sel]
    groups = {b: [w[v] for v in vids] for b, w in A["groups"].items()}
    reg = [int(vregion[v]) for v in vids]
    src_build = A.get("vbuild")
    build = [tuple(src_build[v]) for v in vids] if src_build is not None else None
    # the cut: edges between a face of this part and a face of another
    ef = {}
    for i, f in enumerate(faces):
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            ef.setdefault((min(a, b), max(a, b)), []).append(i)
    cut, other_of = [], {}
    for (a, b), fs in ef.items():
        if len(fs) == 2 and (face_part[fs[0]] == part) != (face_part[fs[1]] == part):
            cut.append((a, b))
            other_of[(a, b)] = face_part[fs[1]] if face_part[fs[0]] == part else face_part[fs[0]]
    loops, chains, pinches = split.walk_loops(np.asarray(cut, np.int64).reshape(-1, 2))
    stats = {"loops": len(loops), "capped": 0, "open_chains": len(chains), "pinches": len(pinches),
             "source": list(vids)}
    part_faces = np.asarray([faces[i] for i in sel], dtype=object)
    # every corner UV of a vertex inside this part (the cap's UV is one of the loop's own)
    corner_uvs = {}
    for i in sel:
        for v, uv in zip(faces[i], A["corner_uv"][i]):
            corner_uvs.setdefault(v, uv)
    for loop in sorted(loops, key=lambda l: (len(l), min(l))):
        oriented = split.orient_loop(loop, [faces[i] for i in sel])
        P = np.asarray(A["V"], np.float64)
        centre, tris, nrm = split.fan_cap(oriented, P, lift)
        a0, b0 = sorted((oriented[0], oriented[1]))
        other = other_of[(a0, b0)]
        bone = root_bone(part, centre, other)
        uvs = np.asarray([corner_uvs[v] for v in oriented])
        cap_uv = tuple(uvs[int(np.argmin(np.linalg.norm(uvs - uvs.mean(axis=0), axis=1)))])
        if cap_uv_of is not None:
            cap_uv = cap_uv_of(cap_uv)
        rim = {}
        for v in oriented:
            rim[v] = len(V)
            stats["source"].append(v)
            V.append(A["V"][v])
            for b in groups:
                groups[b].append(A["groups"][b][v])
            reg.append(split.CAP_REGION)
            if build is not None:
                build.append(tuple(src_build[v]))
        c = len(V)
        stats["source"].append(-1)
        V.append(centre)
        for b in groups:
            groups[b].append(1.0 if b == bone else 0.0)
        if bone not in groups:
            groups[bone] = [0.0] * len(V)
            groups[bone][c] = 1.0
        reg.append(split.CAP_REGION)
        if build is not None:
            build.append((0.0, 0.0) if skin_rims else tuple(np.mean([src_build[v] for v in oriented], axis=0)))
        for (b, a, _c) in tris:
            out_faces.append((rim[b], rim[a], c))
            out_uv.append([cap_uv, cap_uv, cap_uv])
            if skin_rims:
                out_nrm.append([tuple(A["vnormal"][b]), tuple(A["vnormal"][a]), tuple(nrm)])
            else:
                out_nrm.append([tuple(nrm)] * 3)
        stats["capped"] += 1
    del part_faces
    arrays = {"V": np.asarray(V, np.float64), "faces": out_faces, "corner_uv": out_uv,
              "corner_normal": out_nrm, "groups": {b: np.asarray(w) for b, w in groups.items()}}
    if build is not None:
        arrays["vbuild"] = np.asarray(build, np.float64)
    return arrays, np.asarray(reg, np.int64), stats


def boundary_count(A):
    """Open boundary edges of a mesh's arrays, vertices welded by position."""
    weld = split.weld_positions(A["V"], 1e-6)
    tri = []
    for f in A["faces"]:
        for k in range(1, len(f) - 1):
            tri.append((f[0], f[k], f[k + 1]))
    return int(len(split.boundary_edges(np.asarray(tri, np.int64), weld)))


# --------------------------------------------------------------------------------------
# eyes
# --------------------------------------------------------------------------------------
def eye_arrays(frames):
    """Both eyes in one mesh: UV spheres whose pole looks along the gaze; uv.y = 1 - polar angle / pi
    (Blender's v: the pupil at the top of the texture space, uv.y = 0 in Godot)."""
    V, F, UVs, N = [], [], [], []
    for side in ("L", "R"):
        c, r, g = frames[side]
        base = len(V)
        verts, uvs_v = [], []
        for ri in range(EYE_RINGS + 1):
            th = np.pi * ri / EYE_RINGS
            for s in range(EYE_SEGMENTS + 1):
                ph = 2 * np.pi * s / EYE_SEGMENTS
                verts.append((np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), np.cos(th)))
                uvs_v.append((s / EYE_SEGMENTS, 1.0 - ri / EYE_RINGS))
        z = np.asarray(g, float) / np.linalg.norm(g)
        x = np.cross([0.0, 0.0, 1.0], z)
        x /= np.linalg.norm(x)
        y = np.cross(z, x)
        R = np.stack([x, y, z], axis=1)
        unit = np.asarray(verts) @ R.T
        V.extend((unit * (r * 1.02) + np.asarray(c)).tolist())
        N.extend(unit.tolist())
        UVs.extend(uvs_v)
        for ri in range(EYE_RINGS):
            for s in range(EYE_SEGMENTS):
                a = base + ri * (EYE_SEGMENTS + 1) + s
                F.append((a, a + EYE_SEGMENTS + 1, a + EYE_SEGMENTS + 2, a + 1))
    V = np.asarray(V)
    return {"V": V, "faces": F, "corner_uv": [[UVs[v] for v in f] for f in F],
            "corner_normal": [[tuple(N[v]) for v in f] for f in F], "groups": {"head": np.ones(len(V))}}


# --------------------------------------------------------------------------------------
# landmarks, hash, coverage
# --------------------------------------------------------------------------------------
def godot(v):
    """Blender (+X the giant's left, -Y his front, +Z up) -> the game's actor frame after the
    180 degree turn GiantModel applies (+X right, +Y up, -Z front)."""
    return [r6(-v[0]), r6(v[2]), r6(v[1])]


def landmarks(rig, eye_centres):
    bones = rig.data.bones

    def head(b):
        return np.asarray(bones[b].head_local, np.float64)

    out = {}
    for s in ("r", "l"):
        sh, el, wr = head(f"upperarm_{s}"), head(f"lowerarm_{s}"), head(f"hand_{s}")
        palm = (head(f"index_01_{s}") + head(f"middle_01_{s}") + head(f"ring_01_{s}")) / 3.0
        out[f"shoulder_{s}"] = godot(sh)
        out[f"elbow_{s}"] = godot(el)
        out[f"wrist_{s}"] = godot(wr)
        out[f"palm_{s}"] = godot(palm)
        out[f"hip_{s}"] = godot(head(f"thigh_{s}"))
        out[f"knee_{s}"] = godot(head(f"calf_{s}"))
        out[f"ankle_{s}"] = godot(head(f"foot_{s}"))
        out[f"reach_{s}"] = r6(np.linalg.norm(el - sh) + np.linalg.norm(wr - el) + np.linalg.norm(palm - wr))
    out["eye_mid"] = godot((np.asarray(eye_centres["L"]) + np.asarray(eye_centres["R"])) / 2.0)
    out["head"] = godot(head("head"))
    out["neck"] = godot(head("neck_01"))
    out["pelvis"] = godot(head("pelvis"))
    # P48 (plan M11 §2.2): the closed fist's centre and the handle's line through it, the knuckles, the toes.
    # grip_local_* and grip_axis_* are in the hand bone's own space (the same in Blender and in the game).
    for k, v in sorted(gp.hand_landmarks(rig).items()):
        out[k] = [r6(x) for x in v] if k.startswith(("grip_local", "grip_axis")) else godot(v)
    return out


def body_hash(V, faces, fuv, uvs, weights, part, face_region, rig):
    """sha256 of what decision 9 freezes after W25: the body's positions, faces, UVs, weights,
    parts and regions, and the skeleton's rest bones (the 53 game_engine bones: P48's leaf bones are
    not part of the freeze, so the hash is M10's)."""
    h = hashlib.sha256()
    h.update(np.round(np.asarray(V, np.float64), 6).astype(np.float32).tobytes())
    h.update(np.asarray(faces, np.int64).tobytes())
    h.update(np.round(np.asarray(uvs)[np.asarray(fuv)], 6).astype(np.float32).tobytes())
    for b in sorted(weights):
        h.update(b.encode())
        h.update(np.asarray(sorted(map(tuple, weights[b])), np.float64).round(6).tobytes())
    h.update(np.asarray(part, np.int64).tobytes())
    h.update(np.asarray(face_region, np.int64).tobytes())
    for bone in sorted(rig.data.bones, key=lambda x: x.name):
        if bone.name in gp.LEAF_BONES:
            continue
        h.update(bone.name.encode())
        h.update(np.round(np.asarray([*bone.head_local, *bone.tail_local]), 6).astype(np.float32).tobytes())
    return h.hexdigest()


def coverage(garment_obs, body_V, body_N, region_of_vertex, S, reach=None):
    """{region id: share of its body vertices whose outward ray meets one of the objects within
    ``reach`` (COVER_RAY_M when None; human-scale reach, scene units)}."""
    reach = COVER_RAY_M if reach is None else reach
    dg = bpy.context.evaluated_depsgraph_get()
    trees = [BVHTree.FromObject(ob, dg) for ob in garment_obs]
    hit = np.zeros(len(body_V), bool)
    for i, (p, n) in enumerate(zip(body_V, body_N)):
        o = p * S + n * 0.001
        for t in trees:
            loc, _nrm, _idx, dist = t.ray_cast(o.tolist(), n.tolist(), reach * S)
            if loc is not None:
                hit[i] = True
                break
    out = {}
    for r in np.unique(region_of_vertex):
        if r < 0:
            continue
        sel = region_of_vertex == r
        out[int(r)] = r6(hit[sel].mean())
    return out


# --------------------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------------------
def card_coordinates(ob):
    """(V (n, 3), t (n,), arc (n,)): a card mesh's vertices, each one's root-to-tip coordinate (0 the root;
    the cards' UVs run from v = 1 at the root to 0 at the tip) and its distance from its card's root along
    the card (a card is a connected strip of rows; a row's place is the mean of its vertices)."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    me = ob.data
    n = len(me.vertices)
    V = np.empty(n * 3)
    me.vertices.foreach_get("co", V)
    V = V.reshape(-1, 3)
    lv = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", lv)
    uv = np.empty(len(me.loops) * 2)
    me.uv_layers[0].data.foreach_get("uv", uv)
    t = np.zeros(n)
    t[lv] = 1.0 - uv.reshape(-1, 2)[:, 1]
    t = np.clip(t, 0.0, 1.0)
    edges = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", edges)
    edges = edges.reshape(-1, 2)
    graph = coo_matrix((np.ones(len(edges)), (edges[:, 0], edges[:, 1])), shape=(n, n))
    _count, label = connected_components(graph, directed=False)
    arc = np.zeros(n)
    order = np.lexsort((np.round(t, 6), label))
    start = 0
    while start < n:
        end = start
        while end < n and label[order[end]] == label[order[start]]:
            end += 1
        ids = order[start:end]
        levels, inverse = np.unique(np.round(t[ids], 6), return_inverse=True)
        rows = np.stack([V[ids][inverse == k].mean(axis=0) for k in range(len(levels))])
        along = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(rows, axis=0), axis=1))])
        arc[ids] = along[inverse]
        start = end
    return V, t, arc


def braid_vertices(mesh_id, n):
    """A mask of a style's braid vertices: giant_hair.build_styles appends each braid's lobes (three
    points a lobe, four lobes a step) and its core card last. Since P51 build_styles records the mask itself
    (its braids are tubes and beads: giant_hair.BRAID_MASKS)."""
    known = gh.BRAID_MASKS.get(mesh_id)
    if known is not None and len(known) == n:
        return np.asarray(known, bool)
    mask = np.zeros(n, bool)
    count = 0
    for br in gh.STYLES[mesh_id].get("braids", ()):
        steps = max(4, int(round(br["length"] / br["step"])))
        count += 4 * steps * 3 * 2 + (steps + 2) * 2
    if count:
        mask[n - count:] = True
    return mask


def hair_cut(gid, w, hair, V, N, kd, S):
    """{hair style: the share of its length drawn under the head garment ``gid``} (P54, plan M11 §2.6: a helm cuts
    the long styles by length or hides them): a card is cut where its first vertex stands within LAYER_GAP_M of the
    garment's shell or beyond it over the garment's footprint (the cards' root-to-tip coordinate, rounded down to
    0.05), and a style that would keep less than HAIR_CUT_LEAST is not drawn (0). A shell style keeps all of it when
    its layers stay under the garment."""
    used, off = w.shells[gid]
    n = len(V)
    foot = np.zeros(n, bool)
    foot[used] = True
    offb = np.full(n, np.inf)
    offb[used] = off
    out = {}
    for mid in sorted(hair):
        if not mid.startswith("Hair_"):
            continue
        ob, _cards = hair[mid]
        if ob is None:
            sh = gh.SHELLS[mid]
            top = (sh["height"] + sh["lift"]) * S
            least = float(np.min(off)) if len(off) else 0.0
            out[mid] = 1.0 if top < least - gg.LAYER_GAP_M else 0.0
            continue
        CV, t, _arc = card_coordinates(ob)
        _, near = kd.query(CV / S)
        hgt = np.einsum("ij,ij->i", CV - V[near] * S, N[near])
        bad = foot[near] & (hgt > offb[near] - gg.LAYER_GAP_M)
        keep = 1.0 if not bad.any() else math.floor(float(t[bad].min()) * 20.0 + 1e-9) / 20.0
        out[mid] = r6(keep if keep >= HAIR_CUT_LEAST else 0.0)
    return out


SHELL_POSES = ("rest", "idle", "walk", "raised_arm")


def _poses(rig):
    """The four poses of the shells' check (plan M11 §2.6): the rest, an idle frame, the walk's left heel strike
    (the legs at their widest) and a raised arm (the left arm 70 degrees out, the right forward and bent), from
    the clips' own solver."""
    import clips as cl
    rest = cl.Rest(rig)
    walk = cl.Gait(rest, "walk", cl.CLIP_FRAMES["walk"])
    raised = cl.Pose(rest)
    cl.set_arm(raised, "l", 0.0, 25.0, out_deg=8.0, raise_deg=70.0)
    cl.set_arm(raised, "r", -45.0, 70.0, out_deg=10.0, forward_deg=20.0)
    return rest, {"rest": None, "idle": cl.idle_pose(rest, 15, cl.CLIP_FRAMES["idle"]).solve(),
                  "walk": walk.pose(cl.LEFT_STRIKE).solve(), "raised_arm": raised.solve()}


def _set_pose(rig, rest, pose):
    from mathutils import Quaternion, Vector
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = Vector((0.0, 0.0, 0.0))
    if pose is not None:
        for b in rest.order:
            if b != "Root":
                rig.pose.bones[b].rotation_quaternion = pose.basis(b)
        rig.pose.bones["pelvis"].location = pose.pelvis_location()
    bpy.context.view_layer.update()


def skinned_normals(rig, W, bones, N):
    """Each skin vertex's rest normal carried by the posed bones as the skin carries it (the linear blend of the
    bones' rotations, by the vertex's weights), unit length: the line a shell vertex over it moves along. (The
    posed skin's own face normals fold over in the armpit when the arm comes down; every garment there folds the
    same way, so the gaps are measured along the vertex's own line.)"""
    R = np.zeros((len(bones), 3, 3))
    for j, b in enumerate(bones):
        M = rig.pose.bones[b].matrix @ rig.data.bones[b].matrix_local.inverted()
        R[j] = np.array([list(r) for r in M.to_3x3()])
    Nn = np.einsum("vj,jab,vb->va", W, R, N)
    return Nn / np.maximum(np.linalg.norm(Nn, axis=1, keepdims=True), 1e-9)


def shell_distances(rig, body, w, parts, n, S):
    """({"inner|outer": the smallest gap (stage-1 m)}, the poses): for every two garments of different slots that
    stand over the same skin, in each of the four poses, the least height of the outer garment's vertices over a
    posed skin vertex less the greatest height of the inner one's over it (gg.heights: each vertex measured along
    the normal of the posed skin vertex it stands over; the inner slot is the one earlier in gg.LAYER_ORDER). A
    negative value is an intersection. A cloak counts its cloth that lies on the body (not what hangs from the chains,
    which the springs pose in play), with its hanging cloth kept HANG_MARGIN_M clear at rest."""
    from scipy.spatial import cKDTree
    rest, poses = _poses(rig)
    order = {s: i for i, s in enumerate(gg.LAYER_ORDER)}
    bones = [b.name for b in rig.data.bones]
    col = {b: j for j, b in enumerate(bones)}
    W = np.zeros((n, len(bones)))
    for bone, lst in w.weights.items():
        if bone in col:
            for vi, wt in lst:
                if vi < n:
                    W[vi, col[bone]] = wt
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-9)
    body_N = w.N
    gids = [g for g in gg.ORDER if g in parts]
    # the skin both garments of a pair stand on at rest: a pair is measured there in every pose (the plan's "slots
    # whose regions overlap"; an arm's garment that comes near a belt in a pose is not a layering)
    foot = {}
    for g in gids:
        m = np.zeros(n, bool)
        m[np.asarray(sorted(w.footprint[g]), np.int64)] = True
        foot[g] = m
    out = {}
    for pname in SHELL_POSES:
        _set_pose(rig, rest, poses[pname])
        dg = bpy.context.evaluated_depsgraph_get()
        be = body.evaluated_get(dg)
        me = be.to_mesh()
        BV = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", BV)
        BV = BV.reshape(-1, 3)[:n]
        be.to_mesh_clear()
        BN = skinned_normals(rig, W, bones, body_N)
        kd = cKDTree(BV)
        lo, hi = {}, {}
        for g in gids:
            Ps, Bs = [], []
            for o in parts[g]:
                oe = o.evaluated_get(dg)
                m = oe.to_mesh()
                P = np.empty(len(m.vertices) * 3)
                m.vertices.foreach_get("co", P)
                oe.to_mesh_clear()
                Ps.append(P.reshape(-1, 3))
                Bs.append(np.asarray(o["body_ids"], np.int64))
            P = np.concatenate(Ps)
            bid = np.concatenate(Bs)
            P, bid = P[bid != -2], bid[bid != -2]
            a = np.full(n, np.nan)
            b = np.full(n, np.nan)
            own = bid >= 0
            if own.any():
                # a shell: each vertex over its own skin vertex, along that vertex's posed normal
                h = np.einsum("ij,ij->i", P[own] - BV[bid[own]], BN[bid[own]])
                np.fmin.at(a, bid[own], h)
                np.fmax.at(b, bid[own], h)
            if (~own).any() and not gg.GARMENTS[g].get("free"):
                # the rest (a band, the braies): over the skin vertex nearest it. A free cloak's hanging cloth is not
                # measured: it hangs from the cape chains, whose pose in play is the springs' (P50), not a clip's
                ids, hmin, hmax = gg.heights(P[~own], BV, BN, kd)
                a[ids] = np.fmin(a[ids], hmin)
                b[ids] = np.fmax(b[ids], hmax)
            lo[g], hi[g] = a, b
        for ai, a in enumerate(gids):
            for b in gids[ai + 1:]:
                sa, sb = gg.GARMENTS[a]["slot"], gg.GARMENTS[b]["slot"]
                if sa == sb:
                    continue
                inner, outer = (a, b) if order[sa] < order[sb] else (b, a)
                both = np.isfinite(hi[inner]) & np.isfinite(lo[outer]) & foot[inner] & foot[outer]
                if not both.any():
                    continue
                gap = float(np.min(lo[outer][both] - hi[inner][both]))
                key = "%s|%s" % (inner, outer)
                out[key] = min(out.get(key, gap), gap)
                if os.environ.get("GIANT_SHELL_DEBUG") and gap < 0.004:
                    k = np.nonzero(both)[0][int(np.argmin(lo[outer][both] - hi[inner][both]))]
                    log("shell %s %s %.4f at body vertex %d (%.3f %.3f %.3f)" % (pname, key, gap, k, *BV[k]))
    _set_pose(rig, rest, None)
    return {k: r6(v) for k, v in sorted(out.items())}, list(SHELL_POSES)


def set_groups(ob, groups):
    """Replaces an object's vertex groups by {bone: (n,) weights}."""
    for vg in list(ob.vertex_groups):
        ob.vertex_groups.remove(vg)
    for bone in sorted(groups):
        w = groups[bone]
        idx = np.nonzero(w > 1e-4)[0]
        if len(idx) == 0:
            continue
        vg = ob.vertex_groups.new(name=bone)
        for i in idx.tolist():
            vg.add([i], float(w[i]), "REPLACE")


def export_glb(path, rig, meshes, vertex_colour=True):
    """One glTF binary: the armature and the given mesh objects."""
    for o in bpy.data.objects:
        o.select_set(False)
    for o in [rig] + list(meshes):
        o.select_set(True)
        if o.type == "MESH":
            o.data.name = o.name
    bpy.context.view_layer.objects.active = rig
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=False, export_morph=False,
                              export_materials="PLACEHOLDER", export_vertex_color="NAME",
                              export_vertex_color_name="Color", export_all_vertex_colors=False,
                              export_yup=True, export_tangents=False, export_extras=False,
                              export_def_bones=False, export_leaf_bone=False,
                              export_rest_position_armature=True)
    return os.path.getsize(path)


def run(out_dir):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = gb.build_giant({"height_m": H, "name": "Giant"})
    rig, body, bd, weights = objs["rig"], objs["body"], objs["bd"], objs["weights"]
    coll = objs["collection"]
    S = objs["info"]["scale"]
    n = mh.N_BODY_VERTS
    _, faces, fuv = bd.group("body")
    V = bd.verts[:n]
    sp = split.body_split(V, faces, weights, bd.masks, bd.joints)
    fp = sp["face_part"]
    heads = {b.name: np.asarray(b.head_local) for b in rig.data.bones}
    base_bones = sorted(heads)
    # ---- P48: the 18 leaf bones (hair, beard and cape chains); no body vertex is weighted to them ----
    layout = gp.chain_layout(bd, S, heads)
    gp.add_leaf_bones(rig, layout)

    def root_bone(part, centre, other):
        if part == 0 or (part == 1 and other == 0):
            return "neck_01"
        if part == 2:
            return split.nearest_bone(centre, heads, LIMB_ROOTS)
        return split.nearest_bone(centre, heads, TORSO_ROOTS)

    info = {"meshes": {}, "garments": {}, "scale": r6(S), "height_m": H}
    # ---- hair: grown on the whole, unsubdivided body (its masks are point attributes) -----------
    hair = gh.build_styles(body, rig, coll, bd, S)
    # ---- the body: three parts, every cut capped ------------------------------------------------
    A = mesh_arrays(body)
    # P48: the build sliders' weights (brawn, girth) per body vertex, from the MakeHuman muscle and weight targets
    vbuild, build_max, build_stats = gp.build_weights(bd, A["vnormal"], faces, S)
    A["vbuild"] = vbuild
    region_any = np.full(n, -1, np.int64)
    for pi, part in enumerate(split.PARTS):
        arrays, reg, st = split_part(A, fp, pi, sp["vregion"][part], root_bone)
        name = split.PART_MESH[part]
        make_object(name, arrays, coll, rig, "giant_skin", reg)
        info["meshes"][name] = {"category": "body", "layer": split.PART_LAYER[part], "dye": "none",
                                "tris": triangles(arrays), "verts": len(arrays["V"]), "cut_loops": st["loops"],
                                "caps": st["capped"], "open_chains": st["open_chains"],
                                "boundary_edges": boundary_count(arrays),
                                "regions": sorted({int(r) for r in reg})}
        region_any = np.where(sp["vregion"][part] >= 0, np.where(region_any >= 0, region_any, sp["vregion"][part]),
                              region_any)
    body_N = A["vnormal"].copy()
    # ---- P48: the shadow proxy (the whole body, decimated, a little inside the skin) ----------------
    proxy = gp.shadow_proxy(body, rig, coll, S, body_V=V * S, vbuild=vbuild)
    info["shadow_proxy"] = {"node": SHADOW_NAME, "tris": int(sum(len(p.vertices) - 2 for p in proxy.data.polygons)),
                            "verts": len(proxy.data.vertices), "inset_m": gp.SHADOW_INSET_M}
    # ---- eyes -----------------------------------------------------------------------------------
    frames = gb.eye_frames(bd, S)
    eyes = eye_arrays(frames)
    make_object("Eyes", eyes, coll, rig, "giant_eye")
    info["meshes"]["Eyes"] = {"category": "eyes", "layer": 3, "dye": "none", "tris": triangles(eyes),
                              "verts": len(eyes["V"])}
    from scipy.spatial import cKDTree
    kd = cKDTree(V)
    head_cy = bd.landmarks["head_cy"] * S
    for mesh_id, (ob, cards) in hair.items():
        cat = "hair" if mesh_id.startswith("Hair_") else "beard"
        if ob is None:
            # P51: a shell style - the skin under its mask, lifted a little; the game stacks its layers
            sh = gh.SHELLS[mesh_id]
            arrays, ids = gh.shell_cap(A, np.asarray(bd.masks[sh["mask"]])[:n], S, sh["threshold"], sh["lift"])
            arrays["vbuild"] = vbuild[ids]
            make_object(mesh_id, arrays, coll, rig, "giant_hair",
                        np.full(len(ids), split.REGION_ID["scalp" if cat == "hair" else "face"]))
            info["meshes"][mesh_id] = {"category": cat, "layer": 3, "dye": "none", "cards": 0,
                                       "tris": triangles(arrays), "verts": len(arrays["V"]),
                                       "shell": {"mask": sh["channel"], "height_m": r6(sh["height"] * S)},
                                       "chains": [], "root_verts": 0, "roots_on_head": 0, "braid_verts": 0}
            continue
        # P48: the cards' skin along their length (the root on head), and the build weights of the skin they
        # grew from (a whole card takes its root's)
        CV, t, arc = card_coordinates(ob)
        groups = gp.fold_weak_chains(gp.card_weights(CV, arc, cat, layout, head_cy, S, braid_vertices(mesh_id, len(CV))))
        set_groups(ob, groups)
        _, near = kd.query(CV / S)
        colour_attribute(ob.data, np.full(len(CV), split.REGION_ID["scalp" if cat == "hair" else "face"]), vbuild[near])
        roots = t <= 1e-6
        on_head = roots & (groups.get("head", np.zeros(len(CV))) > 0.9999)
        info["meshes"][mesh_id] = {"category": cat, "layer": 3, "dye": "none", "cards": cards,
                                   "tris": int(sum(len(p.vertices) - 2 for p in ob.data.polygons)),
                                   "verts": len(ob.data.vertices), "atlas": "hair_atlas",
                                   "chains": gp.chains_of(groups), "root_verts": int(roots.sum()),
                                   "roots_on_head": int(on_head.sum()),
                                   "braid_verts": int(braid_vertices(mesh_id, len(CV)).sum())}
    # ---- garments (P54: slot by slot, gg.Wardrobe) and accessories ----------------------------------------
    wardrobe = gg.Wardrobe(bd, rig, coll, weights, S, layout)
    built = wardrobe.build()
    body_face_of = {frozenset(f.tolist()): i for i, f in enumerate(faces)}
    vregion_flat = region_any
    garment_parts = {}
    for gid in gg.ORDER:
        spec = gg.GARMENTS[gid]
        ob, body_ids = built[gid]
        for m in list(ob.modifiers):
            if m.type == "SOLIDIFY":
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.modifier_apply(modifier=m.name)
        if gid == "boots":
            tris_now = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            dec = ob.modifiers.new("Decimate", "DECIMATE")
            dec.decimate_type = "COLLAPSE"
            dec.ratio = gg.BOOTS_TRIANGLES / float(tris_now)
            bpy.ops.object.select_all(action="DESELECT")
            bpy.context.view_layer.objects.active = ob
            ob.modifiers.move(len(ob.modifiers) - 1, 0)
            bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.name = "_source_" + gid
        ob.data.name = "_source_" + gid
        G = mesh_arrays(ob)
        exact = len(body_ids) == len(G["V"])
        if exact:
            gbody = np.asarray(body_ids)             # a shell's (or a free mesh's) own body vertex, not the nearest
        else:
            _, gbody = kd.query(G["V"] / S)
        if spec["part"] == "split" and gid not in SPLIT_BY_WEIGHT and exact:
            face_part = []
            for f in G["faces"]:
                bf = body_face_of.get(frozenset(int(gbody[v]) for v in f))
                face_part.append(int(fp[bf]) if bf is not None else 1)
            face_part = np.asarray(face_part)
        elif spec["part"] == "split":
            quads = np.asarray([f for f in G["faces"]])
            face_part = split.assign_parts(quads, sp["part_w"][gbody], min_island=12)
        else:
            face_part = np.full(len(G["faces"]), split.PARTS.index(spec["part"]))
        greg = vregion_flat[np.asarray(gbody)]
        G["vbuild"] = vbuild[np.asarray(gbody)]      # P48: a garment inherits the build weights of the skin under it
        # P54: a shell's vertex takes the normal of the skin vertex it stands on: the build sliders push it along that
        # normal as they push the skin (the cloth shader's push follows NORMAL), so the layers move together and
        # keep their order at any build (P53's follow-up: at -1 the tunic's sleeve hem stood off in steps)
        # (every garment: a band's, the braies' and a cloak's hanging cloth's the skin vertex nearest it, or the one it
        # was cut from: so the hanging cloth pushes as the back it was cut from does)
        G["vnormal"] = body_N[np.asarray(gbody)]
        parts = sorted(set(int(p) for p in face_part))
        made = []
        for pi in parts:
            suffix = "" if len(parts) == 1 else ("_core" if pi != 2 else "_limbs")
            name = f"Garment_{gid}{suffix}"
            arrays, reg, st = split_part(G, face_part, pi, greg, root_bone, lift=GARMENT_CAP_LIFT_OF.get(gid, GARMENT_CAP_LIFT_M) * S,
                                         skin_rims=True)
            mat = ob.data.materials[0].name if len(ob.data.materials) else "giant_cloth"
            gob = make_object(name, arrays, coll, rig, mat, reg)
            src = np.asarray(st["source"], np.int64)
            # a shell's own body vertex per vertex (-1: a cap's centre, or a garment that is not a shell)
            ex = wardrobe.exact.get(gid)
            ids = np.asarray(ex)[np.maximum(src, 0)] if ex is not None and len(ex) == len(G["V"]) \
                else np.full(len(src), -1)
            gob["body_ids"] = np.where(src >= 0, ids, -2).tolist()      # -2: a cap's centre (inside the limb)
            made.append(gob)
            info["meshes"][name] = {"category": "garment", "layer": PART_LAYER[pi], "dye": gg.DYE[gid],
                                    "detail": gg.DETAIL[gid], "tris": triangles(arrays), "verts": len(arrays["V"]),
                                    "cut_loops": st["loops"], "caps": st["capped"], "open_chains": st["open_chains"],
                                    "boundary_edges": boundary_count(arrays), "part": split.PARTS[pi],
                                    "chains": gp.chains_of(arrays["groups"]), "slot": spec["slot"],
                                    "shell": r6(gg.SLOT_SHELL_M[spec["slot"]]), "material": spec["material"]}
            if spec.get("free"):
                info["meshes"][name]["free"] = True
            if spec["slot"] == "head":
                info["meshes"][name]["hides_hair"] = spec.get("hides_hair", "none")
        info["garments"][gid] = [o.name for o in made]
        garment_parts[gid] = made
        bpy.data.objects.remove(ob, do_unlink=True)
        # the regions this garment covers (its parts together), assigned to the part they belong to
        # a free mesh hangs off the skin: its rays reach further (it still hides the designs under it)
        cov = coverage(made, V, body_N, region_any, S, FREE_COVER_RAY_M if spec.get("free") else COVER_RAY_M)
        need = FREE_COVER_SHARE if spec.get("free") else COVER_SHARE
        covered = [r for r, share in sorted(cov.items()) if share >= need and r != split.CAP_REGION]
        for o in made:
            e = info["meshes"][o.name]
            e["coverage"] = {str(r): s for r, s in sorted(cov.items()) if s > 0}
            part_regions = set(split.PART_REGIONS["limbs"]) if e["part"] == "limbs" else \
                set(split.PART_REGIONS["torso"]) | set(split.PART_REGIONS["head"])
            e["covers"] = [r for r in covered if r in part_regions]
    info["slot_shell_m"] = {k: r6(v) for k, v in sorted(gg.SLOT_SHELL_M.items())}
    info["layer_order"] = list(gg.LAYER_ORDER)
    info["slots"] = {g: {k: r6(v) for k, v in sorted(rec.items())} for g, rec in sorted(wardrobe.record.items())}
    # ---- P54: the accessories, rigid on one bone each, clear of the whole wardrobe at the fullest build ---------
    # the rigid trophies keep clear of the skin at the fullest build; the rings move with it (build_accessories)
    wardrobe.push = (np.abs(vbuild[:, 0]) + np.abs(vbuild[:, 1])) * build_max
    for aid, aob in gg.build_accessories(wardrobe).items():
        spec = gg.ACCESSORIES[aid]
        name = aob.name
        A = mesh_arrays(aob)
        _, near = kd.query(A["V"] / S)
        A["corner_normal"] = [[tuple(A["vnormal"][v]) for v in f] for f in A["faces"]]
        bpy.data.objects.remove(aob, do_unlink=True)
        if spec["slot"] != "belt":
            # a ring (the neck's, the arm's) takes the skin's build weights and the skin's normal under each vertex: the
            # build sliders push it as they push the skin under it, so it keeps its place round a neck or an arm that
            # swells or thins; a trophy hangs rigid (no push: it is placed clear of the fullest build)
            A["vbuild"] = vbuild[near]
            A["corner_normal"] = [[tuple(body_N[near[v]]) for v in f] for f in A["faces"]]
        acc = make_object(name, A, coll, rig, "giant_bone" if spec["detail"] == "bone" else "giant_metal",
                          region_any[near].clip(0))
        layer = 1 if spec["bone"].startswith("upperarm") else 2
        info["meshes"][name] = {"category": "accessory", "layer": layer, "dye": "none", "detail": spec["detail"],
                                "tris": triangles(A), "verts": len(A["V"]), "slot": spec["slot"], "bone": spec["bone"],
                                "color": spec["color"], "chains": [], "covers": []}
        info.setdefault("accessories", {})[aid] = name
    # ---- P54: the head garments' cut of the hair (hides_hair "top": the length a style keeps under it) ---------
    for gid in gg.ORDER:
        spec = gg.GARMENTS[gid]
        if spec.get("hides_hair") != "top":
            continue
        cut = hair_cut(gid, wardrobe, hair, V, body_N, kd, S)
        for name in info["garments"][gid]:
            info["meshes"][name]["hair_cut"] = cut
    # ---- P54: the shells' distances in four poses -----------------------------------------------------------
    info["shell_distances"], info["shell_poses"] = shell_distances(rig, body, wardrobe, garment_parts, n, S)
    # ---- landmarks, hash ----------------------------------------------------------------------------
    eye_c = {k: np.asarray(v[0]) for k, v in frames.items()}
    info["landmarks"] = landmarks(rig, eye_c)
    info["body_hash"] = body_hash(V, faces, fuv, bd.bm.uvs, weights, fp, sp["face_region"], rig)
    info["bones"] = base_bones
    info["leaf_bones"] = list(gp.LEAF_BONES)
    info["chains"] = gp.chain_index(layout, godot)
    info["build_max_m"] = r6(build_max)
    info["build"] = {k: r6(v) for k, v in sorted(build_stats.items())}
    info["body_vertices"] = n
    info["cut_loop_lengths"] = {"%s|%s" % k: sorted(len(l) for l in v) for k, v in sp["loops"].items()}
    info["region_names"] = list(split.REGIONS)
    bpy.data.objects.remove(body, do_unlink=True)
    # ---- export: giant.glb (the skeleton, the body, the eyes, the shadow proxy) and one glTF a part -----
    by_name = {o.name: o for o in coll.objects if o.type == "MESH"}
    core = sorted(m for m, e in info["meshes"].items() if e["category"] in CORE_CATEGORIES) + [SHADOW_NAME]
    path = os.path.join(out_dir, GLB_NAME)
    info["glb_bytes"] = export_glb(path, rig, [by_name[m] for m in core])
    info["parts"] = {}
    for mid in sorted(m for m in info["meshes"] if m not in core):
        rel = "%s/%s.glb" % (PARTS_DIR, mid)
        size = export_glb(os.path.join(out_dir, PARTS_DIR, mid + ".glb"), rig, [by_name[mid]])
        info["meshes"][mid]["file"] = rel
        info["parts"][mid] = rel
        info["glb_bytes"] += size
    info["seconds"] = round(time.time() - t0, 1)
    with open(os.path.join(out_dir, INFO_NAME), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log(f"wrote {path} and {len(info['parts'])} parts ({info['glb_bytes']} bytes) in {info['seconds']} s")
    return info


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "giant_out"))
