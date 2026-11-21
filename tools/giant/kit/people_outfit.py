"""A role's people dressed, merged, decimated and exported (plan M11 §2.8, P59).

For one role (``people_roles.ROLES``): every variant's body (``people_body.build_person``); the role's outfit, the
giant's garment shells (``giant_garment.Wardrobe``, slot by slot), built on the first variant's body; the skin and
the inner cloth no outer garment lets show removed; body and outfit merged into one mesh and decimated to the
role's shared budget; one UV atlas for it (``people_roles.MAIN_UV``); the other variants take the same mesh moved
with their own bodies (every outfit vertex rides on the skin vertex it was built over), so the role's one atlas
serves them all. Each variant then adds its own pieces - hair, a beard, a helm or a hood, the eyes, a tabard,
pauldrons or a skirt, each built on its own body and decimated to its own budget, their UVs in the atlas's tiles
(``people_roles.TILES``) - and loses every skin triangle those pieces or the outfit cover. A variant is one mesh with
one surface of at most ``TRIS_MAX`` triangles on its 23-bone skeleton. From the first variant: the five crowd-pose
meshes (``POSES``, each its clip's key, at most ``POSE_TRIS_MAX``) and the far mesh (``FAR_TRIS_MAX``).

``python people_outfit.py <role> <out dir> <work dir> [--ao-from=<orm.png>]`` writes ``<role>.glb`` and the three
maps (people_bake.py) into <out dir> and ``<role>_info.json`` into <work dir>. With --ao-from the ambient occlusion
(the expensive pass) is read from that map's R channel instead of being ray cast (build_people.py --skip-bake).
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402
from scipy.spatial import cKDTree  # noqa: E402

import giant_body as gb  # noqa: E402
import giant_garment as gg  # noqa: E402
import giant_parts as gp  # noqa: E402
import mh_data as mh  # noqa: E402
import people_bake as pbk  # noqa: E402
import people_body as pbody  # noqa: E402
import people_roles as pr  # noqa: E402

N = mh.N_BODY_VERTS
F = pr.EXPORT_SCALE
MATS = tuple(pr.MATERIALS)                 # a face's material index
COVER_REACH_M = 0.12                       # at 1.8 m: skin (or inner cloth) under another piece this near is hidden
CULL_SLACK = 1.02                          # the cull reaches a little further than the test's check (float32 export)
EXTRA_TRIS = {"hair_crop": 240, "hair_long": 520, "beard_short": 110, "beard_full": 190, "iron_helm": 240,
              "leather_cap": 220, "hood": 360, "tabard": 150, "pauldrons": 220, "skirt": 400, "eyes": 64}
SHARED_MARGIN = 40                         # triangles kept back from the shared budget
EYE_RINGS, EYE_SEGMENTS = 3, 8
UV_MARGIN = 0.008                          # between the shared mesh's UV islands (of its square)


def log(*a):
    print("[people_outfit]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


# --------------------------------------------------------------------------------------
# pieces: plain arrays at design scale
# --------------------------------------------------------------------------------------
class Piece:
    """V (n, 3) design scale; T (m, 3) triangles; mat (m,) material index; groups {bone of 23: (n,)}; attach (n,) the
    body vertex each vertex rides on; uv (m, 3, 2) corner UVs (tiles) or None; name."""

    def __init__(self, name, V, T, mat, groups, attach, uv=None):
        self.name, self.V, self.T, self.mat = name, np.asarray(V, np.float64), np.asarray(T, np.int64), np.asarray(mat)
        self.groups, self.attach, self.uv = groups, np.asarray(attach, np.int64), uv

    def tris(self):
        return len(self.T)


def triangulate(faces):
    out = []
    for f in faces:
        f = list(f)
        for i in range(1, len(f) - 1):
            out.append((f[0], f[i], f[i + 1]))
    return np.asarray(out, np.int64).reshape(-1, 3)


def face_normals(V, T):
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    return n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)


def vertex_normals(V, T):
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    out = np.zeros_like(V)
    for k in range(3):
        np.add.at(out, T[:, k], n)
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def compact(V, T, *per_vertex):
    used = np.unique(T.ravel())
    remap = -np.ones(len(V), np.int64)
    remap[used] = np.arange(len(used))
    return (V[used], remap[T]) + tuple(None if a is None else (
        {k: v[used] for k, v in a.items()} if isinstance(a, dict) else a[used]) for a in per_vertex)


def object_arrays(ob):
    """(V, faces, groups {bone: (n,)}) of a Blender mesh object with its modifiers but the armature applied."""
    for m in list(ob.modifiers):
        if m.type == "ARMATURE":
            ob.modifiers.remove(m)
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    me = ev.to_mesh()
    n = len(me.vertices)
    V = np.empty(n * 3)
    me.vertices.foreach_get("co", V)
    faces = [tuple(p.vertices) for p in me.polygons]
    names = [g.name for g in ob.vertex_groups]
    groups = {}
    for v in me.vertices:
        for g in v.groups:
            nm = names[g.group]
            groups.setdefault(nm, np.zeros(n))[v.index] = g.weight
    ev.to_mesh_clear()
    return V.reshape(-1, 3), faces, groups


def bvh(V, T):
    return BVHTree.FromPolygons([tuple(map(float, v)) for v in V], [tuple(map(int, t)) for t in T], all_triangles=True)


def covered(points, normals, tree, reach):
    """Per point: a ray along its normal (from just outside it) meets ``tree`` within ``reach``."""
    out = np.zeros(len(points), bool)
    eps = 1e-4
    for i, (p, n) in enumerate(zip(points, normals)):
        o = Vector((p + n * eps).tolist())
        hit = tree.ray_cast(o, Vector(n.tolist()), reach)
        out[i] = hit[0] is not None
    return out


# --------------------------------------------------------------------------------------
# the outfit (the giant's Wardrobe on a person's body)
# --------------------------------------------------------------------------------------
def wardrobe(person):
    heads = {b.name: np.asarray(b.head_local) for b in person.rig.data.bones}
    layout = gp.chain_layout(person.bd, person.S, heads)
    return gg.Wardrobe(person.bd, person.rig, person.coll, person.weights, person.S, layout)


def build_outfit(w, gids):
    """Build ``gids`` slot by slot (giant_garment.LAYER_ORDER) at their full place; returns them inside out."""
    order = []
    for slot in gg.LAYER_ORDER:
        for gid in gids:
            if gg.GARMENTS[gid]["slot"] == slot:
                w.mode = "full"
                getattr(w, "g_" + gid)()
                order.append(gid)
        w.close(slot)
    return order


def garment_material(gid, faction):
    if gid in faction:
        return "faction"
    return pr.GARMENT_MATERIAL[gg.GARMENTS[gid]["detail"]]


def garment_piece(w, gid, person, mat_name, kd):
    ob, used = w.built[gid]
    V, faces, groups = object_arrays(ob)
    ex = w.exact.get(gid)
    if ex is not None and len(ex) == len(V):
        attach = np.asarray(ex, np.int64)
    else:
        attach = kd.query(V / person.S)[1]
    T = triangulate(faces)
    return Piece(gid, V, T, np.full(len(T), MATS.index(mat_name)), pr.fold_weights(groups), attach)


def body_piece(person):
    _, faces, _ = person.bd.group("body")
    V = person.body_V()
    T = triangulate(faces)
    g = pr.fold_weights(person.groups53())
    lips = person.bd.masks["m_lips"]
    mat = np.where(lips[T].mean(axis=1) > 0.5, MATS.index("lips"), MATS.index("skin"))
    return Piece("body", V, T, mat, g, np.arange(N))


def cull(piece, outer, reach):
    """``piece`` less every triangle whose three corners and centre lie under ``outer`` (rays along the triangle's
    normal from them)."""
    if not outer:
        return piece, 0
    V = np.concatenate([p.V for p in outer])
    off = np.cumsum([0] + [len(p.V) for p in outer])[:-1]
    T = np.concatenate([p.T + o for p, o in zip(outer, off)])
    tree = bvh(V, T)
    fn = face_normals(piece.V, piece.T)
    drop = np.zeros(len(piece.T), bool)
    for t in range(len(piece.T)):
        pts = np.concatenate([piece.V[piece.T[t]], piece.V[piece.T[t]].mean(axis=0, keepdims=True)])
        drop[t] = bool(covered(pts, np.repeat(fn[t:t + 1], 4, axis=0), tree, reach).all())
    keep = ~drop
    if piece.uv is not None:
        uv = piece.uv[keep]
    else:
        uv = None
    T = piece.T[keep]
    V, T, groups, attach = compact(piece.V, T, piece.groups, piece.attach)
    return Piece(piece.name, V, T, piece.mat[keep], groups, attach, uv), int(drop.sum())


def compact_piece(p):
    V, T, groups, attach = compact(p.V, p.T, p.groups, p.attach)
    return Piece(p.name, V, T, p.mat, groups, attach, p.uv)


def merge(pieces):
    V = np.concatenate([p.V for p in pieces])
    off = np.cumsum([0] + [len(p.V) for p in pieces])[:-1]
    T = np.concatenate([p.T + o for p, o in zip(pieces, off)])
    mat = np.concatenate([p.mat for p in pieces])
    bones = sorted({b for p in pieces for b in p.groups})
    groups = {b: np.concatenate([p.groups.get(b, np.zeros(len(p.V))) for p in pieces]) for b in bones}
    attach = np.concatenate([p.attach for p in pieces])
    uv = None
    if all(p.uv is not None for p in pieces):
        uv = np.concatenate([p.uv for p in pieces])
    return Piece("+".join(p.name for p in pieces), V, T, mat, groups, attach, uv)


# --------------------------------------------------------------------------------------
# Blender helpers: decimation, UVs, tangents
# --------------------------------------------------------------------------------------
def mesh_object(name, V, T, mat=None, uv=None, coll=None):
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.asarray(V, np.float64).tolist(), [], np.asarray(T, np.int64).tolist())
    me.update()
    for m in MATS:
        mm = bpy.data.materials.get("pp_" + m) or bpy.data.materials.new("pp_" + m)
        me.materials.append(mm)
    if mat is not None:
        me.polygons.foreach_set("material_index", np.asarray(mat, np.int32))
    if uv is not None:
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", np.asarray(uv, np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), bool))
    ob = bpy.data.objects.new(name, me)
    (coll or bpy.context.scene.collection).objects.link(ob)
    return ob


def read_tris(me):
    n = len(me.vertices)
    V = np.empty(n * 3)
    me.vertices.foreach_get("co", V)
    T = np.empty(len(me.polygons) * 3, np.int64)
    if any(len(p.vertices) != 3 for p in me.polygons):
        raise SystemExit("people: a decimated mesh has a polygon that is not a triangle")
    me.polygons.foreach_get("vertices", T)
    mat = np.empty(len(me.polygons), np.int32)
    me.polygons.foreach_get("material_index", mat)
    uv = None
    if me.uv_layers:
        luv = np.empty(len(me.loops) * 2)
        me.uv_layers[0].data.foreach_get("uv", luv)
        uv = luv.reshape(-1, 3, 2)
    return V.reshape(-1, 3), T.reshape(-1, 3), mat, uv


def decimate(V, T, mat, budget, name, uv=None, symmetric=True):
    """(V, T, mat, uv) collapsed to at most ``budget`` triangles (Blender's Decimate, collapse, triangulated)."""
    if len(T) <= budget:
        return V, T, mat, uv
    ob = mesh_object(name, V, T, mat, uv)
    ratio = budget / float(len(T))
    for _attempt in range(12):
        for m in list(ob.modifiers):
            ob.modifiers.remove(m)
        d = ob.modifiers.new("Decimate", "DECIMATE")
        d.decimate_type = "COLLAPSE"
        d.ratio = ratio
        d.use_collapse_triangulate = True
        d.use_symmetry = symmetric
        d.symmetry_axis = "X"
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        out = read_tris(me)
        ev.to_mesh_clear()
        if len(out[1]) <= budget:
            break
        ratio *= 0.995 * budget / float(len(out[1]))
    else:
        raise SystemExit("people: %s could not be decimated to %d triangles" % (name, budget))
    me_old = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me_old)
    return out


def unwrap(V, T, name):
    """Corner UVs (m, 3, 2) of a mesh: Blender's smart projection, packed into people_roles.MAIN_UV's square."""
    ob = mesh_object(name, V, T)
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(62.0), island_margin=0.006, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(rotate=True, shape_method="CONCAVE", margin_method="SCALED", margin=UV_MARGIN)
    bpy.ops.object.mode_set(mode="OBJECT")
    luv = np.empty(len(ob.data.loops) * 2)
    ob.data.uv_layers[0].data.foreach_get("uv", luv)
    uv = luv.reshape(-1, 3, 2)
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    u0, v0, u1, v1 = pr.MAIN_UV
    lo, hi = uv.reshape(-1, 2).min(axis=0), uv.reshape(-1, 2).max(axis=0)
    span = float(max(hi - lo))
    uv = (uv - lo) / span
    return np.stack([u0 + uv[..., 0] * (u1 - u0), v0 + uv[..., 1] * (v1 - v0)], axis=-1)


def tangents(V, T, uv):
    """Per corner (m, 3): the mesh's MikkTSpace tangents (m, 3, 3), bitangent signs (m, 3) and normals (m, 3, 3)
    as Blender computes (and exports) them for a smooth-shaded mesh with these corner UVs."""
    ob = mesh_object("_tangents", V, T, None, uv)
    me = ob.data
    me.calc_tangents(uvmap="UVMap")
    nl = len(me.loops)
    tan = np.empty(nl * 3)
    me.loops.foreach_get("tangent", tan)
    sgn = np.empty(nl)
    me.loops.foreach_get("bitangent_sign", sgn)
    nor = np.empty(nl * 3)
    me.loops.foreach_get("normal", nor)
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    return tan.reshape(-1, 3, 3), sgn.reshape(-1, 3), nor.reshape(-1, 3, 3)


def barycentric(P, A, B, C):
    v0, v1, v2 = B - A, C - A, P - A
    d00, d01, d11 = (v0 * v0).sum(-1), (v0 * v1).sum(-1), (v1 * v1).sum(-1)
    d20, d21 = (v2 * v0).sum(-1), (v2 * v1).sum(-1)
    den = np.where(np.abs(d00 * d11 - d01 * d01) < 1e-20, 1e-20, d00 * d11 - d01 * d01)
    v = (d11 * d20 - d01 * d21) / den
    w = (d00 * d21 - d01 * d20) / den
    return np.stack([1.0 - v - w, v, w], axis=-1)


def correspond(src, V):
    """Per point: (the src triangle nearest it, its barycentric weights there, the point's offset from it)."""
    tree = bvh(src.V, src.T)
    tri = np.zeros(len(V), np.int64)
    loc = np.zeros_like(V)
    for i, p in enumerate(V):
        hit = tree.find_nearest(Vector(p.tolist()))
        tri[i] = hit[2]
        loc[i] = np.asarray(hit[0])
    A, B, C = (src.V[src.T[tri, k]] for k in range(3))
    bary = np.clip(barycentric(loc, A, B, C), 0.0, 1.0)
    bary = bary / bary.sum(axis=1, keepdims=True)
    return tri, bary, V - loc


def interpolate(src_values, src_T, tri, bary):
    return np.einsum("nk,nk...->n...", bary, src_values[src_T[tri]])


# --------------------------------------------------------------------------------------
# a variant's own pieces
# --------------------------------------------------------------------------------------
def nearest_groups(person, P, kd):
    near = kd.query(P / person.S)[1]
    g = pr.fold_weights(person.groups53())
    return {b: w[near] for b, w in g.items()}, near


def shell_piece(name, person, keep, off_design, mat, kd, seed=0, hem_noise=0.0):
    """A shell of the body's faces under ``keep`` pushed out ``off_design`` (per body vertex) as a Piece."""
    bd = person.bd
    _, faces, fuv = bd.group("body")
    V = person.body_V()
    Nn = gg.vnormals(V / person.S, faces)
    ob, used = gg.shell("_" + name, person.coll, person.rig, V / person.S, Nn, faces, fuv, bd.bm.uvs, keep,
                        np.asarray(off_design) / person.S, person.weights, person.S, "giant_cloth", seed=seed,
                        hem_noise=hem_noise)
    Pv, faces2, groups = object_arrays(ob)
    bpy.data.objects.remove(ob, do_unlink=True)
    T = triangulate(faces2)
    return Piece(name, Pv, T, np.full(len(T), MATS.index(mat)), pr.fold_weights(groups), np.asarray(used))


def hair_piece(person, style, w, kd):
    bd, S = person.bd, person.S
    m = bd.masks
    scalp = m["m_scalp"]
    keep = scalp > 0.3
    base = 0.0105 * S
    off = np.full(N, base) * np.clip(scalp, 0.4, 1.0)
    if style == "long":
        L = bd.landmarks
        V = bd.verts[:N]
        head_cy = L["head_cy"]
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        sh = 0.5 * (bd.joints["joint-l-shoulder"][2] + bd.joints["joint-r-shoulder"][2])
        neck = bd.joints["joint-neck"][2]
        behind = y > head_cy + 0.005
        down = sh - 0.16                                 # to the shoulder blades
        width = 0.075 + 0.05 * np.clip((neck - z) / max(neck - down, 1e-3), 0.0, 1.0)
        curtain = behind & (z > down) & (z < L["ear_z"][1] + 0.02) & (np.abs(x) < width) \
            & ((m["m_head"] + m["m_neck"] + m["m_torso"]) > 0.4)
        keep = keep | curtain
        t = np.clip((L["ear_z"][1] - z) / max(L["ear_z"][1] - down, 1e-3), 0.0, 1.0)
        env = np.nan_to_num(w.C, nan=0.0) if w is not None else np.zeros(N)
        off = np.where(curtain & ~(scalp > 0.3), (0.012 + 0.03 * t) * S + env, off)
        off = np.maximum(off, np.where(curtain, env + 0.012 * S, 0.0))
        p = shell_piece("hair_long", person, keep, off, "hair", kd, seed=7, hem_noise=0.012)
    else:
        p = shell_piece("hair_crop", person, keep, off, "hair", kd)
    return p


def beard_piece(person, style, kd):
    m = person.bd.masks
    beard = m["m_beard"]
    keep = beard > 0.35
    L = person.bd.landmarks
    z = person.bd.verts[:N, 2]
    if style == "full":
        down = np.clip((L["lip_bot"] - z) / 0.06, 0.0, 1.0)
        off = (0.006 + 0.022 * down) * person.S * np.clip(beard, 0.5, 1.0)
        return shell_piece("beard_full", person, keep, off, "hair", kd, seed=3, hem_noise=0.006)
    off = np.full(N, 0.0045 * person.S)
    return shell_piece("beard_short", person, keep, off, "hair", kd)


def eye_piece(person):
    frames = gb.eye_frames(person.bd, person.S)
    V, T, uv, att = [], [], [], []
    for side in ("L", "R"):
        c, r, g = frames[side]
        z = np.asarray(g, float) / np.linalg.norm(g)
        xa = np.cross([0.0, 0.0, 1.0], z)
        xa /= np.linalg.norm(xa)
        ya = np.cross(z, xa)
        base = len(V)
        V.append(c + z * r * 1.02)                               # the pupil's pole
        for ri in range(1, EYE_RINGS + 1):
            th = 0.5 * np.pi * ri / EYE_RINGS * 1.3
            for s in range(EYE_SEGMENTS):
                ph = 2 * np.pi * s / EYE_SEGMENTS
                d = np.sin(th) * (np.cos(ph) * xa + np.sin(ph) * ya) + np.cos(th) * z
                V.append(c + d * r * 1.02)
        for s in range(EYE_SEGMENTS):
            a, b = base + 1 + s, base + 1 + (s + 1) % EYE_SEGMENTS
            T.append((base, a, b))
        for ri in range(EYE_RINGS - 1):
            for s in range(EYE_SEGMENTS):
                a = base + 1 + ri * EYE_SEGMENTS + s
                b = base + 1 + ri * EYE_SEGMENTS + (s + 1) % EYE_SEGMENTS
                T += [(a, a + EYE_SEGMENTS, b), (b, a + EYE_SEGMENTS, b + EYE_SEGMENTS)]
    V = np.asarray(V)
    T = np.asarray(T, np.int64)
    groups = {"head": np.ones(len(V))}
    return Piece("eyes", V, T, np.full(len(T), MATS.index("eye")), groups, np.full(len(V), -1))


def tabard_piece(person, w, kd):
    bd = person.bd
    V = bd.verts[:N]
    m = bd.masks
    x, z = V[:, 0], V[:, 2]
    hip = 0.5 * (bd.joints["joint-l-upper-leg"][2] + bd.joints["joint-r-upper-leg"][2])
    sh = 0.5 * (bd.joints["joint-l-shoulder"][2] + bd.joints["joint-r-shoulder"][2])
    keep = ((m["m_torso"] + m["m_pelvis"]) > 0.6) & (m["m_upperarm"] < 0.05) & (np.abs(x) < 0.15) \
        & (z > hip - 0.12) & (z < sh - 0.02) & (m["m_neck"] < 0.2)
    env = np.nan_to_num(w.C, nan=0.0)
    off = env + 0.014 * person.S
    return shell_piece("tabard", person, keep, off, "faction", kd, seed=5, hem_noise=0.004)


def wardrobe_extra(w, gid, person, mat, kd):
    """A head garment or pauldrons built on the variant's own wardrobe (after its outfit, for the envelope)."""
    getattr(w, "g_" + gid)()
    p = garment_piece(w, gid, person, mat, kd)
    ob, _ = w.built[gid]
    bpy.data.objects.remove(ob, do_unlink=True)
    return p


def skirt_piece(w, person, kd):
    z, wz, hp, an = w.z, w.waist_z, w.hip, w.ankle
    keep = w._legs(wz - 0.004, hp - gg.KILT_CUT_BELOW_HIP) & (z > hp - gg.KILT_CUT_BELOW_HIP)
    off = np.full(N, gg.SLOT_SHELL_M["legs"] + 0.006 * person.S)
    w.add_skirt("kilt", keep, off, an + 0.07, flare=0.09, pleats=0, pleat_depth=0.0, clear=0.03, rows=10,
                thigh_follow=0.4)
    p = garment_piece(w, "kilt", person, "cloth", kd)
    ob, _ = w.built["kilt"]
    bpy.data.objects.remove(ob, do_unlink=True)
    p.name = "skirt"
    return p


def tile_uv(piece, tile, centre, mode="head"):
    """Corner UVs in a tile of the atlas: |azimuth| about a vertical axis through ``centre`` (mirrored, so no seam)
    across, height up."""
    P = piece.V[piece.T]
    rel = P - centre
    az = np.abs(np.arctan2(rel[..., 0], -rel[..., 1])) / np.pi
    zlo, zhi = float(piece.V[:, 2].min()), float(piece.V[:, 2].max())
    h = (P[..., 2] - zlo) / max(zhi - zlo, 1e-6)
    u0, v0 = pr.TILES[tile]
    m = 0.06
    s = pr.TILE_SIZE
    return np.stack([u0 + s * (m + (1 - 2 * m) * az), v0 + s * (m + (1 - 2 * m) * h)], axis=-1)


def eye_uv(piece):
    """The eyes' tile: the pupil's pole at the tile's top centre, the rings down from it."""
    u0, v0 = pr.TILES["eye"]
    s = pr.TILE_SIZE
    n = 1 + EYE_RINGS * EYE_SEGMENTS
    uv = np.zeros((len(piece.V), 2))
    for e in range(2):
        uv[e * n] = (0.5, 0.95)
        for ri in range(EYE_RINGS):
            for k in range(EYE_SEGMENTS):
                ph = 2 * np.pi * k / EYE_SEGMENTS
                rr = 0.12 + 0.33 * (ri + 1) / EYE_RINGS
                uv[e * n + 1 + ri * EYE_SEGMENTS + k] = (0.5 + rr * math.cos(ph), 0.95 - rr * (0.6 + 0.4 * math.sin(ph) ** 2))
    uv = np.clip(uv, 0.04, 0.96)
    out = np.stack([u0 + s * uv[:, 0], v0 + s * uv[:, 1]], axis=-1)
    return out[piece.T]


def extras_for(v, role, person, w, kd):
    """A variant's own pieces (people_roles: hair, beard, head, extras), decimated, with tile UVs."""
    out = []
    head_c = np.array([0.0, person.bd.landmarks["head_cy"] * person.S, 0.0])
    torso_c = np.array([0.0, float(person.pelvis[1]), 0.0])
    faction = role in ("soldier", "archer", "mage")
    if v["head"]:
        gid = v["head"]
        mat = {"iron_helm": "metal", "leather_cap": "leather", "hood": "faction" if faction else "cloth"}[gid]
        p = wardrobe_extra(w, gid, person, mat, kd)
        out.append((p, {"metal": "metal", "leather": "leather", "faction": "faction", "cloth": "cloth"}[mat], head_c,
                    EXTRA_TRIS[gid]))
    if v["hair"]:
        p = hair_piece(person, v["hair"], w, kd)
        out.append((p, "hair", head_c, EXTRA_TRIS["hair_" + v["hair"]]))
    if v["beard"]:
        p = beard_piece(person, v["beard"], kd)
        out.append((p, "hair", head_c, EXTRA_TRIS["beard_" + v["beard"]]))
    for e in v["extras"]:
        if e == "tabard":
            out.append((tabard_piece(person, w, kd), "faction", torso_c, EXTRA_TRIS["tabard"]))
        elif e == "pauldrons":
            out.append((wardrobe_extra(w, "iron_pauldrons", person, "metal", kd), "metal", torso_c,
                        EXTRA_TRIS["pauldrons"]))
        elif e == "skirt":
            out.append((skirt_piece(w, person, kd), "cloth", torso_c, EXTRA_TRIS["skirt"]))
    pieces = []
    for p, tile, c, budget in out:
        V, T, mat, _uv = decimate(p.V, p.T, p.mat, budget, "_dec_" + p.name)
        groups, near = nearest_groups(person, V, kd)
        q = Piece(p.name, V, T, mat, groups, near)
        q.uv = tile_uv(q, tile, c)
        pieces.append(q)
    eyes = eye_piece(person)
    eyes.uv = eye_uv(eyes)
    pieces.append(eyes)
    return pieces


# --------------------------------------------------------------------------------------
# the role
# --------------------------------------------------------------------------------------
def build_role(role, out_dir, work_dir, ao_from=None):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    spec = pr.ROLES[role]
    vs = spec["variants"]
    times = {}
    ref = pbody.reference()
    rcoll = gb._collection("Export")
    ref_arm = pbody.export_rig(ref, ref, "_ref_rig", rcoll)
    poses, _gaits = pbody.make_poses(ref.rest)
    trk = pbody.tracks(poses, ref.rest, pbody.rest_matrices(ref_arm))
    people = [pbody.build_person(v["macro"], pr.FACES[v["face"]], v["name"], ref) for v in vs]
    times["bodies"] = round(time.time() - t0, 1)
    # ---- the shared outfit on the first variant's body -----------------------------------------------
    p0 = people[0]
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = wardrobe(p0)
    order = build_outfit(w0, spec["outfit"])
    garments = [garment_piece(w0, gid, p0, garment_material(gid, spec["faction"]), kd0) for gid in order]
    reach = COVER_REACH_M * CULL_SLACK / F
    body, culled_skin = cull(body_piece(p0), garments, reach)
    culled_cloth = 0
    kept = []
    for i, g in enumerate(garments):
        g2, d = cull(g, garments[i + 1:], reach)
        culled_cloth += d
        kept.append(g2)
    src = merge([body] + kept)
    src.n_body = len(body.V)
    times["outfit"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- each variant's own pieces (on its own wardrobe: the outfit for the envelope, then its pieces) ---------
    extras = []
    for k, (v, person) in enumerate(zip(vs, people)):
        kd = kd0 if k == 0 else cKDTree(person.bd.verts[:N])
        if k == 0:
            wk = w0
        else:
            wk = wardrobe(person)
            build_outfit(wk, spec["outfit"])
        extras.append(extras_for(v, role, person, wk, kd))
    worst_extra = max(sum(p.tris() for p in ex) for ex in extras)
    budget = pr.TRIS_MAX - worst_extra - SHARED_MARGIN
    times["extras"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the shared mesh: decimated, unwrapped, its corners' tangents ------------------------------------------
    LV, LT, Lmat, _ = decimate(src.V, src.T, src.mat, budget, "_shared_" + role)
    Luv = unwrap(LV, LT, "_uv_" + role)
    tri, bary, offset = correspond(src, LV)
    lgroups = {b: interpolate(w, src.T, tri, bary) for b, w in src.groups.items()}
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the variants ---------------------------------------------------------------------------------------------
    body0 = p0.body_V()
    variants_out = []
    for k, (v, person) in enumerate(zip(vs, people)):
        delta = person.body_V() - body0
        src_k = src.V + delta[src.attach]
        Vk = interpolate(src_k, src.T, tri, bary) + offset
        own = extras[k]
        skin_sel = np.isin(Lmat, [MATS.index("skin"), MATS.index("lips")])
        zeros = np.zeros(len(Vk), np.int64)
        skin = Piece("skin", Vk, LT[skin_sel], Lmat[skin_sel], lgroups, zeros, Luv[skin_sel])
        cloth = compact_piece(Piece("cloth", Vk, LT[~skin_sel], Lmat[~skin_sel], lgroups, zeros, Luv[~skin_sel]))
        skin_c, dropped = cull(skin, [cloth] + own, reach)
        final = merge([skin_c, cloth] + [Piece(p.name, p.V, p.T, p.mat, p.groups, np.zeros(len(p.V), np.int64), p.uv)
                                         for p in own])
        if final.tris() > pr.TRIS_MAX:
            raise SystemExit("people: %s has %d triangles, over %d" % (v["name"], final.tris(), pr.TRIS_MAX))
        variants_out.append({"v": v, "person": person, "mesh": final, "skin_dropped": dropped})
    times["variants"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the bake (people_bake: the atlas from the first variant's shared mesh and src) -------------------------
    tan, sgn, nor = tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(role, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS, ao_from=ao_from,
                              extra_meshes=[merge(extras[0])])
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the rigs, the meshes, the crowd poses, the far mesh; the export --------------------------------------------
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Role_" + role)
    mat = bpy.data.materials.new("person_" + role)
    exported = []
    info = {"role": role, "variants": {}, "poses": {}, "times": times, "tris_max": pr.TRIS_MAX,
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget),
                       "culled_skin": culled_skin, "culled_cloth": culled_cloth, "outfit": list(order)},
            "bake": bake_info}
    for k, rec in enumerate(variants_out):
        v, person, mesh = rec["v"], rec["person"], rec["mesh"]
        arm = pbody.export_rig(person, ref, v["name"] + "_rig", coll)
        ob = skinned_object(v["name"], mesh, arm, coll, mat)
        exported += [arm, ob]
        rest = pbody.rest_matrices(arm)
        info["variants"][v["name"]] = {
            "index": k, "tris": mesh.tris(), "verts": int(len(mesh.V)), "sex": v["sex"],
            "pieces": [p.name for p in extras[k]], "skin_culled": rec["skin_dropped"],
            "height_m": r6(float(mesh.V[:, 2].max()) * F),
            "natural_height_m": r6(1.0 if v["sex"] == "male" else 0.93),
            "joints": {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES},
            "palette": pr.preview_palette(role, k)}
        if k == 0:
            rest0, arm0, mesh0 = rest, arm, mesh
    parents = pbody.parents_of(arm0)
    idx4, w40 = pr.top4(mesh0.groups, len(mesh0.V))
    V0 = mesh0.V * F
    for pose in pr.POSES:
        clip, key = pr.POSE_CLIP[pose]
        kd_ = pbody.pose_key(trk, clip, key)
        G = pbody.fk(rest0, parents, kd_["basis"], kd_["loc"])
        P = pbody.skin_points(V0, idx4, w40, rest0, G) / F
        Vp, Tp, mp, uvp = decimate(P, mesh0.T, mesh0.mat, pr.POSE_TRIS_MAX, "_pose_" + pose, uv=mesh0.uv)
        name = "%s_pose_%s" % (role, pose)
        ob = static_object(name, Vp, Tp, uvp, coll, mat)
        exported.append(ob)
        info["poses"][pose] = {"node": name, "clip": clip, "key": key, "tris": int(len(Tp)),
                               "joints": {b: [r6(x) for x in G[b][:3, 3]] for b in pr.BONES}}
        if pose == "hold":
            Vf, Tf, mf, uvf = decimate(Vp, Tp, mp, pr.FAR_TRIS_MAX, "_far", uv=uvp)
            far = static_object(role + "_far", Vf, Tf, uvf, coll, mat)
            exported.append(far)
            info["far"] = {"node": role + "_far", "tris": int(len(Tf))}
    path = os.path.join(out_dir, role + ".glb")
    export(path, exported)
    info["glb_bytes"] = os.path.getsize(path)
    times["export"] = round(time.time() - t0 - sum(times.values()), 1)
    info["seconds"] = round(time.time() - t0, 1)
    os.makedirs(work_dir, exist_ok=True)
    with open(os.path.join(work_dir, role + "_info.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log("%s: %s in %.1f s" % (role, ", ".join("%s %d" % (n, e["tris"]) for n, e in info["variants"].items()),
                              info["seconds"]))
    return info


def skinned_object(name, mesh, arm, coll, mat):
    ob = mesh_object(name, mesh.V * F, mesh.T, None, mesh.uv, coll)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    idx, w4 = pr.top4(mesh.groups, len(mesh.V))
    for b in pr.BONES:
        ob.vertex_groups.new(name=b)
    for vi in range(len(mesh.V)):
        for j in range(4):
            if w4[vi, j] > 0.0:
                ob.vertex_groups[int(idx[vi, j])].add([vi], float(w4[vi, j]), "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    return ob


def static_object(name, V, T, uv, coll, mat):
    ob = mesh_object(name, V * F, T, None, uv, coll)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    return ob


def export(path, objects):
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objects:
        o.select_set(True)
        if o.type == "MESH":
            o.data.name = o.name
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=False, export_morph=False, export_materials="PLACEHOLDER",
                              export_vertex_color="NONE", export_yup=True, export_tangents=True,
                              export_extras=False, export_def_bones=False, export_leaf_bone=False,
                              export_rest_position_armature=True, export_cameras=False, export_lights=False)


# --------------------------------------------------------------------------------------
# gear.glb: weapons, shields, the banner (the project's own shapes, metres at 1.8 m)
# --------------------------------------------------------------------------------------
# Each piece: its grip at the origin, its length along +Z (the glTF's +Y), colours in COLOR_0 (RGB the albedo, A 1
# where the faction's colour tints it). Pieces: [(shape, args, colour, tinted)].
WOOD, DARK_WOOD, IRON, STEEL, CLOTH, LEATHER = ((0.42, 0.30, 0.18), (0.28, 0.19, 0.11), (0.42, 0.43, 0.45),
                                                (0.62, 0.64, 0.67), (0.85, 0.85, 0.85), (0.33, 0.22, 0.13))
GEAR = {
    "sword": [("cyl", (-0.10, 0.12, 0.016, 8), LEATHER, False), ("box", ((0, 0, 0.13), (0.20, 0.03, 0.025)), IRON, False),
              ("blade", (0.14, 0.86, 0.055, 0.008), STEEL, False), ("ball", ((0, 0, -0.12), 0.025), IRON, False)],
    "spear": [("cyl", (-1.2, 1.15, 0.018, 8), WOOD, False), ("blade", (1.15, 1.42, 0.05, 0.01), STEEL, False)],
    "shield": [("disc", ((0, -0.04, 0), 0.34, 0.02, 16), CLOTH, True), ("ball", ((0, -0.07, 0), 0.06), IRON, False),
               ("cyl", (-0.06, 0.06, 0.014, 6), LEATHER, False)],
    "banner": [("cyl", (-1.0, 1.7, 0.02, 8), DARK_WOOD, False), ("flag", ((0.02, 0, 1.6), 0.6, 0.85), CLOTH, True)],
    "bow": [("arc", (0.75, 0.18, 0.014, 10), DARK_WOOD, False), ("cyl", (-0.74, 0.74, 0.002, 3), CLOTH, False)],
    "quiver": [("cyl", (-0.30, 0.30, 0.055, 10), LEATHER, False), ("cyl", (0.30, 0.42, 0.04, 6), WOOD, False)],
    "staff": [("cyl", (-0.9, 0.95, 0.022, 8), DARK_WOOD, False), ("ball", ((0, 0, 0.97), 0.045), DARK_WOOD, False)],
    "hammer": [("cyl", (-0.25, 0.55, 0.02, 8), WOOD, False), ("box", ((0, 0, 0.6), (0.22, 0.09, 0.09)), IRON, False)],
}


def _cyl(z0, z1, r, n, x=0.0, y=0.0):
    V, T = [], []
    for z in (z0, z1):
        for k in range(n):
            a = 2 * math.pi * k / n
            V.append((x + r * math.cos(a), y + r * math.sin(a), z))
    for k in range(n):
        a, b = k, (k + 1) % n
        T += [(a, b, n + b), (a, n + b, n + a)]
    V += [(x, y, z0), (x, y, z1)]
    for k in range(n):
        T += [(2 * n, (k + 1) % n, k), (2 * n + 1, n + k, n + (k + 1) % n)]
    return V, T


def _box(c, s):
    hx, hy, hz = (0.5 * v for v in s)
    V = [(c[0] + sx * hx, c[1] + sy * hy, c[2] + sz * hz) for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)]
    T = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4),
         (1, 5, 7), (1, 7, 3)]
    return V, T


def _ball(c, r, n=6):
    V, T = [], []
    for i in range(n + 1):
        th = math.pi * i / n
        for k in range(n):
            ph = 2 * math.pi * k / n
            V.append((c[0] + r * math.sin(th) * math.cos(ph), c[1] + r * math.sin(th) * math.sin(ph), c[2] + r * math.cos(th)))
    for i in range(n):
        for k in range(n):
            a, b = i * n + k, i * n + (k + 1) % n
            T += [(a, a + n, b + n), (a, b + n, b)]
    return V, T


def _blade(z0, z1, w, t):
    V = [(0, 0, z0 - 0.0), (w / 2, 0, z0), (0, t, z0), (-w / 2, 0, z0), (0, -t, z0),
         (w / 2, 0, z1 - 0.12 * (z1 - z0)), (0, t, z1 - 0.12 * (z1 - z0)), (-w / 2, 0, z1 - 0.12 * (z1 - z0)),
         (0, -t, z1 - 0.12 * (z1 - z0)), (0, 0, z1)]
    T = []
    for k in range(4):
        a, b = 1 + k, 1 + (k + 1) % 4
        T += [(a, b, 5 + (k + 1) % 4), (a, 5 + (k + 1) % 4, 5 + k), (5 + k, 5 + (k + 1) % 4, 9), (0, b, a)]
    return V, T


def _disc(c, r, t, n):
    V, T = _cyl(-t / 2, t / 2, r, n)
    R = np.array([[1, 0, 0], [0, 0, -1], [0, 1, 0]], float)      # its face toward -Y (the front)
    V = [tuple(R @ np.array(v) + np.array(c)) for v in V]
    return V, T


def _flag(c, w, h):
    x0, y0, z0 = c
    V = [(x0, y0 - 0.004, z0), (x0 + w, y0 - 0.004, z0), (x0 + w, y0 - 0.004, z0 - h), (x0, y0 - 0.004, z0 - h),
         (x0, y0 + 0.004, z0), (x0 + w, y0 + 0.004, z0), (x0 + w, y0 + 0.004, z0 - h), (x0, y0 + 0.004, z0 - h)]
    T = [(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5), (2, 3, 7), (2, 7, 6),
         (3, 0, 4), (3, 4, 7)]
    return V, T


def _arc(half, depth, r, n):
    V, T = [], []
    pts = []
    for i in range(n + 1):
        t = -1.0 + 2.0 * i / n
        pts.append((0.0, -depth * (1.0 - t * t), half * t))
    m = 6
    for p in pts:
        for k in range(m):
            a = 2 * math.pi * k / m
            V.append((p[0] + r * math.cos(a), p[1] + r * math.sin(a), p[2]))
    for i in range(n):
        for k in range(m):
            a, b = i * m + k, i * m + (k + 1) % m
            T += [(a, b, b + m), (a, b + m, a + m)]
    return V, T


def gear_main(out_dir, work_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = gb._collection("Gear")
    info = {"pieces": {}}
    objs = []
    for gid in sorted(GEAR):
        V, T, C = [], [], []
        tinted = False
        for shape, args, col, tint in GEAR[gid]:
            fn = {"cyl": lambda a: _cyl(*a), "box": lambda a: _box(*a), "ball": lambda a: _ball(*a),
                  "blade": lambda a: _blade(*a), "disc": lambda a: _disc(*a), "flag": lambda a: _flag(*a),
                  "arc": lambda a: _arc(*a)}[shape]
            v, t = fn(args)
            base = len(V)
            V += v
            T += [(a + base, b + base, c + base) for a, b, c in t]
            C += [tuple(col) + (1.0 if tint else 0.0,)] * len(v)
            tinted = tinted or tint
        name = "gear_" + gid
        me = bpy.data.meshes.new(name)
        me.from_pydata(V, [], T)
        me.update()
        ca = me.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(C, np.float32).ravel())
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        mat = bpy.data.materials.get("person_gear") or bpy.data.materials.new("person_gear")
        me.materials.append(mat)
        objs.append(ob)
        Va = np.asarray(V)
        info["pieces"][gid] = {"node": name, "tris": len(T), "length_m": r6(Va[:, 2].max() - Va[:, 2].min()),
                               "tinted": tinted}
    for o in bpy.data.objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "gear.glb")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_animations=False, export_materials="PLACEHOLDER", export_vertex_color="NAME",
                              export_vertex_color_name="Color", export_all_vertex_colors=False, export_yup=True,
                              export_extras=False, export_cameras=False, export_lights=False)
    os.makedirs(work_dir, exist_ok=True)
    with open(os.path.join(work_dir, "gear_info.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log("gear: %d pieces, %d bytes" % (len(objs), os.path.getsize(path)))


if __name__ == "__main__":
    if "--gear" in sys.argv[1:]:
        args = [a for a in sys.argv[1:] if not a.startswith("--")]
        gear_main(args[0], args[1])
        sys.exit(0)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    ao = None
    for a in sys.argv[1:]:
        if a.startswith("--ao-from="):
            ao = a.split("=", 1)[1]
    build_role(args[0], args[1], args[2], ao_from=ao)
