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
import people_parts as pp  # noqa: E402
import people_roles as pr  # noqa: E402

N = mh.N_BODY_VERTS
F = pr.EXPORT_SCALE
MATS = tuple(pr.MATERIALS)                 # a face's material index
COVER_REACH_M = 0.12                       # at 1.8 m: skin (or inner cloth) under another piece this near is hidden
CULL_SLACK = 1.02                          # the cull reaches a little further than the test's check (float32 export)
EXTRA_TRIS = {"hair_crop": 260, "hair_long": 480, "beard_short": 150, "beard_full": 240, "iron_helm": 300,
              "iron_helm_guard": 320, "leather_cap": 240, "hood": 380, "tabard": 240, "pauldrons": 170, "skirt": 340,
              "eyes": 100}
SHARED_MARGIN = 20                         # triangles kept back from the shared budget
EYE_RINGS, EYE_SEGMENTS = 3, 10
UV_MARGIN = 0.008
FACE_ZOOM = 2.2                            # the face's islands' density over the scalp's (the head's rect)
DETAIL_FACTOR = 1.0                        # decimate's default detail strength (the horse's: kit/quadruped.py)
PEOPLE_DETAIL_FACTOR = 0.06                # P59b: the people's (the cost the face's and the hands' edges add in
#                                            Blender's collapse: at 1.0 the face kept nearly all its triangles and
#                                            starved the body and the clothes)
DETAIL_WEIGHT = {"face": 0.8, "hands": 0.3}
LONG_HAIR_VOLUME_M = 0.006                 # P65b: the long style's extra fullness over the crown (at 1.8 m)
# P65c: the long hair still lay on the skull like a cap (the women read boyish at 3 m): fuller toward the crown (this
# more at the top than over the ears) and wider down the back to the shoulder blades (its mass seen beside the neck
# from the front); a parting tried down the middle read as a bald wedge in the hairline and was dropped
LONG_HAIR_CROWN_M = 0.009
LONG_HAIR_WIDTH_M = (0.08, 0.075)           # the fall's half width at the neck, and how much wider at its end         # (a weight of 1 locks a vertex: never collapsed)


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


def object_arrays(ob, with_uv=False):
    """(V, faces, groups {bone: (n,)}) of a Blender mesh object with its modifiers but the armature applied; with
    ``with_uv`` also its faces' corner UVs (a list of (k, 2) arrays, None without a UV layer)."""
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
    fuv = None
    if with_uv and me.uv_layers:
        luv = np.empty(len(me.loops) * 2)
        me.uv_layers[0].data.foreach_get("uv", luv)
        luv = luv.reshape(-1, 2)
        fuv = [luv[p.loop_start:p.loop_start + p.loop_total] for p in me.polygons]
    names = [g.name for g in ob.vertex_groups]
    groups = {}
    for v in me.vertices:
        for g in v.groups:
            nm = names[g.group]
            groups.setdefault(nm, np.zeros(n))[v.index] = g.weight
    ev.to_mesh_clear()
    if with_uv:
        return V.reshape(-1, 3), faces, groups, fuv
    return V.reshape(-1, 3), faces, groups


def triangulate_uv(fuv):
    """Corner UVs (m, 3, 2) of polygons' corner UVs, fanned as ``triangulate`` fans the polygons."""
    out = []
    for f in fuv:
        for i in range(1, len(f) - 1):
            out.append((f[0], f[i], f[i + 1]))
    return np.asarray(out, np.float64).reshape(-1, 3, 2)


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
    """Build ``gids`` slot by slot (LAYER_ORDER) at their full place; returns them inside out. Two garments of one
    slot are worn in the role's order, the second over the first (P59b: the slot closed after each; P59 built them
    side by side, so the crew's vest lay inside the shirt and the mage's kilt inside the trousers, and showed through
    in patches). The footwear (people_roles.FOOTWEAR) is the people's own (footwear_piece), not the wardrobe's."""
    order = []
    for slot in LAYER_ORDER:
        for gid in gids:
            if gid in pr.FOOTWEAR:
                continue
            if gg.GARMENTS[gid]["slot"] == slot:
                w.mode = "full"
                getattr(w, "g_" + gid)()
                order.append(gid)
                w.close(slot)
        w.close(slot)
    return order


# The giant's slots in the order the people put them on (P59b): the belt over the armour (a belted hauberk; under
# it the mail pinched in at a waist nothing showed)
LAYER_ORDER = tuple(sl for sl in gg.LAYER_ORDER if sl != "waist")
LAYER_ORDER = LAYER_ORDER[:LAYER_ORDER.index("armour") + 1] + ("waist",) + LAYER_ORDER[LAYER_ORDER.index("armour") + 1:]
# The garments whose shells are smoothed before the merge (Taubin's, the open edges straightened along themselves):
# the mail dipped into the tunic's neck slit under it and its seat and hem were notched
SMOOTHED = {"mail_hauberk": 4, "kilt": 3, "tunic": 2, "shirt": 2}


# The skirted garments whose hips are drawn in to the body (tame_bulge): the giant's skirt spans each slice's convex
# hull round the seat, and a person's A-pose elbows hang at the waist, so it bulged out to them like a cushion
TAMED = ("mail_hauberk", "tunic", "jerkin")
TAME_SPAN_M = (0.22, 0.14)            # below and above the hip joints
TAME_EASE_M = {"mail_hauberk": 0.045, "tunic": 0.03, "jerkin": 0.04}
# P65b: the mail's span reaches its hem (its lower rows flared out behind and at the hips' sides)
TAME_SPAN_OF = {"mail_hauberk": (0.32, 0.14), "tunic": (0.32, 0.14), "jerkin": (0.32, 0.14)}
# P65b: the skirted garments whose back is spanned over the seat (span_seat): the decimated mail dipped into the cleft
# of the buttocks in a dark crease down the back, and the tunic under it showed through where it did
SPANNED = ("mail_hauberk", "tunic", "jerkin")
SEAT_SPAN_M = (0.32, 0.16)            # below and above the hip joints
MAIL_SMOOTH_ITERS = 4                 # (mail_over, P65c) the spanned back's smoothing passes
MAIL_UNDER_M = 0.006                  # (mail_over) the cloth under the mail's skirt kept this far inside it
# P65b: a woman's tunic (and tabard) drapes from the bust (drape_bust): built as a shell it followed the body into
# the crease under the bust, which the low mesh and the bake drew as a dark pasted shape
DRAPE_BAND_M = (0.10, 0.10)           # over the hips (+) and under the shoulders (-): the band the drape works in
DRAPE_REACH_M = 0.016                 # the neighbours (across, m) a vertex's drape line is taken over


def tame_bulge(p, person):
    """``p`` with the points round the hips (TAME_SPAN_M) no further from the hips' middle than the body's own
    section there (its torso, pelvis and thighs: not the arms) and an ease (TAME_EASE_M), eased in and out."""
    bd, S = person.bd, person.S
    J = bd.joints
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    m = bd.masks
    B = bd.verts[:N]
    trunk = (m["m_torso"] + m["m_pelvis"] + m["m_upperleg"]) > 0.4
    trunk &= (m["m_upperarm"] + m["m_forearm"] + m["m_hand"]) < 0.05
    V = p.V / S
    c = np.array([0.0, float(np.median(B[trunk & (np.abs(B[:, 2] - hip) < 0.05), 1]))])
    ease = TAME_EASE_M.get(p.name, 0.04)
    span = TAME_SPAN_OF.get(p.name, TAME_SPAN_M)
    lo, hi = hip - span[0], hip + span[1]
    from scipy.spatial import ConvexHull
    out = V.copy()
    for z0 in np.arange(lo, hi, 0.01):
        band = (V[:, 2] >= z0) & (V[:, 2] < z0 + 0.01)
        sl = B[trunk & (np.abs(B[:, 2] - (z0 + 0.005)) < 0.02)][:, :2]
        if not band.any() or len(sl) < 8:
            continue
        eq = ConvexHull(sl).equations
        rel = V[band, :2] - c
        r = np.linalg.norm(rel, axis=1)
        D = rel / np.maximum(r, 1e-9)[:, None]
        reach = gg._hull_reach(np.tile(c, (len(D), 1)), D, eq)
        w = min(1.0, (z0 - lo) / 0.06, (hi - z0) / 0.06)               # eased in at the span's ends
        lim = np.where(np.isfinite(reach), reach + ease, np.inf)
        r2 = np.where(r > lim, r + (lim - r) * w, r)
        out[band, :2] = c + D * r2[:, None]
    p.V = out * S
    return p


def span_seat(p, person):
    """``p`` with its back (behind each slice's middle) pushed out to its own slice's convex hull round the seat
    (SEAT_SPAN_M): a skirted garment spans the cleft of the buttocks as cloth or mail hangs over them, eased in and
    out at the span's ends."""
    from scipy.spatial import ConvexHull
    J = person.bd.joints
    S = person.S
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    V = p.V / S
    out = V.copy()
    lo, hi = hip - SEAT_SPAN_M[0], hip + SEAT_SPAN_M[1]
    arm = np.zeros(len(V), bool)
    for b in ("upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r", "hand_l", "hand_r"):
        if b in p.groups:
            arm |= np.asarray(p.groups[b]) > 0.1
    for z0 in np.arange(lo, hi, 0.01):
        idx = np.nonzero((V[:, 2] >= z0) & (V[:, 2] < z0 + 0.01) & ~arm)[0]
        if len(idx) < 8:
            continue
        Q = V[idx, :2]
        try:
            eq = ConvexHull(Q).equations
        except Exception:
            continue
        c = np.array([0.0, float(Q[:, 1].mean())])
        back = idx[V[idx, 1] > c[1]]
        if not len(back):
            continue
        rel = V[back, :2] - c
        r = np.linalg.norm(rel, axis=1)
        D = rel / np.maximum(r, 1e-9)[:, None]
        reach = gg._hull_reach(np.tile(c, (len(D), 1)), D, eq)
        w = min(1.0, (z0 - lo) / 0.06, (hi - z0) / 0.06)
        r2 = np.where(np.isfinite(reach) & (reach > r), r + (reach - r) * w, r)
        out[back, :2] = c + D * r2[:, None]
    p.V = out * S
    return p


def _span_points(V, idx, person, lo, hi):
    """span_seat's rule on the points ``idx`` of V (human m, in place): the back pushed out to each 1 cm slice's
    convex hull of those points between ``lo`` and ``hi``."""
    from scipy.spatial import ConvexHull
    for z0 in np.arange(lo, hi, 0.01):
        sl = idx[(V[idx, 2] >= z0) & (V[idx, 2] < z0 + 0.01)]
        if len(sl) < 8:
            continue
        Q = V[sl, :2]
        try:
            eq = ConvexHull(Q).equations
        except Exception:
            continue
        c = np.array([0.0, float(Q[:, 1].mean())])
        back = sl[V[sl, 1] > c[1]]
        if not len(back):
            continue
        rel = V[back, :2] - c
        r = np.linalg.norm(rel, axis=1)
        D = rel / np.maximum(r, 1e-9)[:, None]
        reach = gg._hull_reach(np.tile(c, (len(D), 1)), D, eq)
        w = min(1.0, (z0 - lo) / 0.04, (hi - z0) / 0.04)
        r2 = np.where(np.isfinite(reach) & (reach > r), r + (reach - r) * w, r)
        V[back, :2] = c + D * r2[:, None]


def mail_over(Vk, LT, Lmat, person):
    """A variant's shared mesh (design scale) with its mail's back spanned over the seat again after the collapse
    (the low mesh's mail had dipped back into the cleft), and the triangles under the mail's skirt that are not mail
    (the tunic's, which came through it in red patches) dropped: returns (V, keep_tris)."""
    J = person.bd.joints
    S = person.S
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    V = Vk / S
    mail = Lmat == MATS.index("mail")
    mv = np.unique(LT[mail].ravel())
    lo = float(V[mv, 2].min())
    _span_points(V, mv, person, max(lo, hip - SEAT_SPAN_M[0]), hip + SEAT_SPAN_M[1])
    # P65c: the spanned back smoothed across (the decimated mail kept a fold down the cleft: a dark crease in its
    # shading): the mail's back points in the seat's band averaged with their mail neighbours
    yc = float(np.median(V[mv, 1]))
    band = np.zeros(len(V), bool)
    band[mv] = (V[mv, 2] > max(lo, hip - SEAT_SPAN_M[0]) + 0.01) & (V[mv, 2] < hip + 0.06) & (V[mv, 1] > yc)
    MT = LT[mail]
    ea = np.concatenate([MT[:, 0], MT[:, 1], MT[:, 2], MT[:, 1], MT[:, 2], MT[:, 0]])
    eb = np.concatenate([MT[:, 1], MT[:, 2], MT[:, 0], MT[:, 0], MT[:, 1], MT[:, 2]])
    for _ in range(MAIL_SMOOTH_ITERS):
        acc = np.zeros((len(V), 2))
        cnt = np.zeros(len(V))
        np.add.at(acc, ea, V[eb, :2])
        np.add.at(cnt, ea, 1.0)
        avg = acc / np.maximum(cnt, 1.0)[:, None]
        move = band & (cnt > 0)
        V[move, :2] = V[move, :2] * 0.5 + avg[move] * 0.5
    keep = np.ones(len(LT), bool)
    from scipy.spatial import ConvexHull, Delaunay
    under = ~mail & ~np.isin(Lmat, [MATS.index("skin"), MATS.index("lips"), MATS.index("leather"),
                                    MATS.index("dark_leather")])
    # the cloth under the mail's skirt drawn in inside it (each slice's hull of the mail, less MAIL_UNDER_M)
    uv_ = np.setdiff1d(np.unique(LT[under].ravel()), mv)
    for z0 in np.arange(lo, hip + 0.04, 0.01):
        sl = mv[(V[mv, 2] >= z0 - 0.01) & (V[mv, 2] < z0 + 0.02)]
        mine = uv_[(V[uv_, 2] >= z0) & (V[uv_, 2] < z0 + 0.01)]
        if len(sl) < 8 or not len(mine):
            continue
        try:
            eq = ConvexHull(V[sl, :2]).equations
        except Exception:
            continue
        c = np.array([0.0, float(V[sl, 1].mean())])
        rel = V[mine, :2] - c
        r = np.linalg.norm(rel, axis=1)
        D = rel / np.maximum(r, 1e-9)[:, None]
        reach = gg._hull_reach(np.tile(c, (len(D), 1)), D, eq) - MAIL_UNDER_M
        r2 = np.where(np.isfinite(reach) & (r > reach), np.maximum(reach, 0.0), r)
        V[mine, :2] = c + D * r2[:, None]
    for z0 in np.arange(lo, hip + 0.04, 0.02):
        band = V[mv, 2]
        sl = mv[(band >= z0 - 0.01) & (band < z0 + 0.03)]
        if len(sl) < 8:
            continue
        try:
            tri = Delaunay(V[sl, :2])
        except Exception:
            continue
        cen = V[LT].mean(axis=1)
        cand = np.nonzero(under & (cen[:, 2] >= z0) & (cen[:, 2] < z0 + 0.02))[0]
        if len(cand):
            inside = tri.find_simplex(cen[cand, :2]) >= 0
            keep[cand[inside]] = False
    # P65c: a decimated tunic triangle whose centre fell outside a slice's hull of the mail still came through it (a
    # small red mark low on the back): below the hips every cloth triangle wholly above the mail's hem and inside its
    # outline, widened by MAIL_UNDER_M, goes too
    cen = V[LT].mean(axis=1)
    cand = np.nonzero(under & keep & (cen[:, 2] < hip + 0.02) & (V[LT][:, :, 2].min(axis=1) > lo + 0.01))[0]
    if len(cand):
        for t in cand.tolist():
            zt = cen[t, 2]
            near = mv[np.abs(V[mv, 2] - zt) < 0.03]
            if len(near) < 8:
                continue
            try:
                eq = ConvexHull(V[near, :2]).equations
            except Exception:
                continue
            if (eq[:, :2] @ cen[t, :2] + eq[:, 2]).max() < MAIL_UNDER_M:
                keep[t] = False
    if os.environ.get("PEOPLE_DEBUG"):
        log("mail over: %d triangles under the mail dropped; mail z %.3f..%.3f, hip %.3f" % (
            int((~keep).sum()), lo, float(V[mv, 2].max()), hip))
    return V * S, keep


def drape_bust(V, sel, person):
    """Design-scale points ``V`` with the front ones of ``sel`` (in the chest's band, DRAPE_BAND_M) brought forward
    to the upper convex hull of their neighbours' side profiles (within DRAPE_REACH_M across): cloth falls straight
    from the bust instead of following the crease under it. Returns a new array."""
    J = person.bd.joints
    S = person.S
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    sh = 0.5 * (J["joint-l-shoulder"][2] + J["joint-r-shoulder"][2])
    P = V / S
    yc = float(J["joint-spine-2"][1]) if "joint-spine-2" in J else float(np.median(P[sel, 1]))
    band = np.asarray(sel, bool) & (P[:, 2] > hip + DRAPE_BAND_M[0]) & (P[:, 2] < sh - DRAPE_BAND_M[1]) \
        & (P[:, 1] < yc) & (np.abs(P[:, 0]) < 0.2)
    idx = np.nonzero(band)[0]
    out = P.copy()
    for i in idx:
        nb = idx[np.abs(P[idx, 0] - P[i, 0]) < DRAPE_REACH_M]
        z, f = P[nb, 2], -P[nb, 1]
        o = np.argsort(z)
        z, f = z[o], f[o]
        # the upper hull of (z, f) (monotone chain), then its height at this vertex's z
        hz, hf = [], []
        for a, b in zip(z, f):
            while len(hz) >= 2 and (hz[-1] - hz[-2]) * (b - hf[-2]) - (hf[-1] - hf[-2]) * (a - hz[-2]) >= 0.0:
                hz.pop()
                hf.pop()
            hz.append(a)
            hf.append(b)
        fh = float(np.interp(P[i, 2], hz, hf))
        if fh > -P[i, 1]:
            out[i, 1] = -fh
    # the lift smoothed over its neighbours (a lone vertex lifted past the ones round it folded the cloth: a dark
    # speck in the normal map)
    d = out[idx, 1] - P[idx, 1]
    Q = P[idx][:, [0, 2]]
    from scipy.spatial import cKDTree as _kd
    nb = _kd(Q).query_ball_point(Q, DRAPE_REACH_M)
    out[idx, 1] = P[idx, 1] + np.array([d[n].mean() for n in nb])
    return out * S


def garment_material(gid, faction):
    if gid in faction:
        return "faction"
    if gid in pr.FOOTWEAR:
        return "leather"
    return pr.GARMENT_MATERIAL[gg.GARMENTS[gid]["detail"]]


def footwear_piece(gid, person, kd):
    """The boots or the shoes (people_parts.boots) as a Piece: its UVs the rings' own (the atlas re-lays them), each
    vertex riding on the skin vertex nearest it."""
    V, T = pp.boots(person, **pr.FOOTWEAR[gid])
    groups, near = nearest_groups(person, V, kd)
    return Piece(gid, V, T, np.full(len(T), MATS.index("leather")), groups, near, footwear_hint(V, T))


def footwear_hint(V, T):
    """Corner UVs that only mark the footwear's seams for the atlas's unwrap: the sole apart (planar), the upper
    round each leg's axis with its cut down the back of the heel and the shaft."""
    uv = np.zeros((len(T), 3, 2))
    n = face_normals(V, T)
    for sg in (1.0, -1.0):
        side = np.sign(V[T].mean(axis=1)[:, 0]) == sg
        ax = np.median(V[np.sign(V[:, 0]) == sg][:, :2], axis=0)
        sole = side & (n[:, 2] < -0.6)
        uv[sole] = V[T[sole]][:, :, :2] + (10.0 if sg > 0 else 20.0)
        up = np.nonzero(side & ~sole)[0]
        P = V[T[up]]
        ang = np.arctan2(P[..., 0] - ax[0], P[..., 1] - ax[1])           # 0: straight back (+Y)
        c = np.arctan2(P.mean(axis=1)[:, 0] - ax[0], P.mean(axis=1)[:, 1] - ax[1])
        ang = c[:, None] + np.angle(np.exp(1j * (ang - c[:, None])))       # unwrapped about each triangle's centre
        ang = np.where(c[:, None] < 0.0, ang + 2.0 * np.pi, ang)            # (the cut: straight back)
        uv[up] = np.stack([ang * 0.1, P[..., 2]], axis=-1) + (30.0 if sg > 0 else 40.0)
    return uv


def garment_piece(w, gid, person, mat_name, kd):
    ob, used = w.built[gid]
    V, faces, groups, fuv = object_arrays(ob, with_uv=True)
    ex = w.exact.get(gid)
    if ex is not None and len(ex) == len(V):
        attach = np.asarray(ex, np.int64)
    else:
        attach = kd.query(V / person.S)[1]
    T = triangulate(faces)
    uv = triangulate_uv(fuv) if fuv is not None else ring_hint(V, T, np.array([0.0, float(np.median(V[:, 1]))]))
    return Piece(gid, V, T, np.full(len(T), MATS.index(mat_name)), pr.fold_weights(groups), attach, uv)


def ring_hint(V, T, axis_xy, base=50.0):
    """Corner UVs that only mark seams for the atlas's unwrap (a piece built without UVs, a belt): round a
    vertical axis through ``axis_xy`` with the cut straight behind it, its height up."""
    P = V[T]
    ang = np.arctan2(P[..., 0] - axis_xy[0], P[..., 1] - axis_xy[1])           # 0: straight back (+Y)
    cen = P.mean(axis=1)
    c = np.arctan2(cen[:, 0] - axis_xy[0], cen[:, 1] - axis_xy[1])
    ang = c[:, None] + np.angle(np.exp(1j * (ang - c[:, None])))
    ang = np.where(c[:, None] < 0.0, ang + 2.0 * np.pi, ang)
    return np.stack([ang * 0.1, P[..., 2]], axis=-1) + base


def body_piece(person):
    _, faces, fuv = person.bd.group("body")
    V = person.body_V()
    # (the inside of the mouth is never seen: its faces go, so neither the decimation nor the bake reads them)
    mouth = person.bd.masks["m_mouth_inside"]
    keep = ~np.all(mouth[faces] > 0.5, axis=1)
    faces, fuv = faces[keep], fuv[keep]
    T = triangulate(faces)
    uv = triangulate_uv(np.asarray(person.bd.bm.uvs)[fuv])
    g = pr.fold_weights(person.groups53())
    lips = person.bd.masks["m_lips"]
    mat = np.where(lips[T].mean(axis=1) > 0.5, MATS.index("lips"), MATS.index("skin"))
    return Piece("body", V, T, mat, g, np.arange(N), uv)


def cull(piece, outer, reach, protect=None):
    """``piece`` less every triangle whose three corners and centre lie under ``outer`` (rays along the triangle's
    normal from them); ``protect`` (a function of the triangles' centres, or None): those it marks are kept."""
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
    if protect is not None:
        drop &= ~np.asarray(protect(piece.V[piece.T].mean(axis=1)), bool)
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


def decimate(V, T, mat, budget, name, uv=None, symmetric=True, detail=None, detail_factor=DETAIL_FACTOR):
    """(V, T, mat, uv) collapsed to at most ``budget`` triangles (Blender's Decimate, collapse, triangulated);
    ``detail`` (per vertex, 0..1) keeps more of the triangles there (the face, the hands)."""
    if len(T) <= budget:
        return V, T, mat, uv
    ob = mesh_object(name, V, T, mat, uv)
    if detail is not None:
        vg = ob.vertex_groups.new(name="detail")
        for w in np.unique(np.round(np.asarray(detail), 2)):
            if w > 0.0:
                vg.add(np.nonzero(np.round(np.asarray(detail), 2) == w)[0].tolist(), float(w), "REPLACE")
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
        if detail is not None:
            d.vertex_group = "detail"
            d.invert_vertex_group = True
            d.vertex_group_factor = detail_factor
        dg = bpy.context.evaluated_depsgraph_get()
        ev = ob.evaluated_get(dg)
        me = ev.to_mesh()
        out = read_tris(me)
        ev.to_mesh_clear()
        if os.environ.get("PEOPLE_DEBUG"):
            log("decimate %s: ratio %.4f -> %d (budget %d)" % (name, ratio, len(out[1]), budget))
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


def uv_islands(T, uv):
    """(m,) island index of each triangle: triangles joined across an edge whose two corners' UVs agree."""
    parent = np.arange(len(T))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    seen = {}
    q = np.round(np.asarray(uv) * 1e6).astype(np.int64)
    for t in range(len(T)):
        for k in range(3):
            a, b = int(T[t, k]), int(T[t, (k + 1) % 3])
            ua, ub = tuple(q[t, k]), tuple(q[t, (k + 1) % 3])
            key = (a, b, ua, ub) if a < b else (b, a, ub, ua)
            o = seen.get(key)
            if o is None:
                seen[key] = t
            else:
                ra, rb = find(o), find(t)
                if ra != rb:
                    parent[max(ra, rb)] = min(ra, rb)
    roots = np.array([find(t) for t in range(len(T))])
    return np.unique(roots, return_inverse=True)[1]


def _upright(V, T, uv, isl, ids):
    """The islands ``ids`` turned in UV so that height (+Z) runs up the texture (+v): rows of rings run level."""
    uv = uv.copy()
    for i in ids:
        sel = np.nonzero(isl == i)[0]
        P = V[T[sel]].reshape(-1, 3)
        Q = uv[sel].reshape(-1, 2)
        A = np.column_stack([Q, np.ones(len(Q))])
        g = np.linalg.lstsq(A, P[:, 2], rcond=None)[0][:2]            # d z / d (u, v)
        if np.linalg.norm(g) < 1e-9:
            continue
        a = math.atan2(g[0], g[1])                                   # turn g onto +v
        c, s_ = math.cos(a), math.sin(a)
        R = np.array([[c, -s_], [s_, c]])
        m = Q.mean(axis=0)
        uv[sel] = ((uv[sel] - m) @ R.T) + m
    return uv


def shelf_pack(uv, isl, rect, what, margin=0.008):
    """Islands (corner UVs ``uv``, island index ``isl`` per triangle) placed unscaled and unturned on shelves in
    ``rect`` (u0, v0, u1, v1): tallest first, each on the first shelf with room."""
    u0, v0, u1, v1 = rect
    out = uv.copy()
    boxes = []
    for i in range(isl.max() + 1):
        q = uv[isl == i].reshape(-1, 2)
        lo, hi = q.min(axis=0), q.max(axis=0)
        boxes.append((float(hi[1] - lo[1]), i, lo, hi))
    shelves = []                                   # [y, height, x]
    for h, i, lo, hi in sorted(boxes, key=lambda b: (-b[0], b[1])):
        w = float(hi[0] - lo[0])
        for sh in shelves:
            if sh[2] + w <= u1 - margin and h <= sh[1]:
                break
        else:
            y = shelves[-1][0] + shelves[-1][1] + margin if shelves else v0 + margin
            if y + h > v1 - margin or u0 + margin + w > u1 - margin:
                log("islands' boxes (w, h): %s" % ", ".join("%.3f x %.3f" % (b[3][0] - b[2][0], b[0]) for b in boxes))
                raise SystemExit("people: the %s's islands do not fit their rect at the fixed density" % what)
            sh = [y, h, u0 + margin]
            shelves.append(sh)
        out[isl == i] = uv[isl == i] - lo + np.array([sh[2], sh[0]])
        sh[2] += w + margin
    return out


def unwrap_atlas(V, T, hint, region, name, mail=False, zoom=None):
    """Corner UVs (m, 3, 2) of the shared mesh in people_roles.ATLAS's regions (``region``: per triangle, an index of
    ATLAS_REGIONS). The seams are the high mesh's (``hint``: the corner UVs the decimation carried from MakeHuman's
    own layout and the garments', so the islands are few and large) and the regions' borders; Blender's angle-based
    unwrap lays each island out, every island at one density; then each region's islands are packed into its rect.
    With ``mail`` the side region holds the mail, at the fixed density MAIL_UV_PER_M, upright and unturned (the
    person shader's rings: people_roles.MAIL_RINGS_PER_UV). ``zoom`` (per triangle): its island's density over the
    region's others (the face's over the scalp's), a seam between triangles of two zooms."""
    import bmesh
    names = [r[0] for r in pr.ATLAS_REGIONS]
    region = np.asarray(region)
    if os.environ.get("PEOPLE_DEBUG"):
        log("atlas regions: %s triangles" % dict(zip(names, np.bincount(region, minlength=len(names)).tolist())))
    # two pinned triangles a region at its rect's corners hold the rect as the islands' box (pack: ORIGINAL_AABB)
    n0, m0 = len(V), len(T)
    dV, dT, dR = [], [], []
    for r in range(len(names)):
        for k in range(2):
            b = n0 + len(dV)
            o = np.array([100.0 + 3 * r + k, 100.0, 100.0])
            dV += [o, o + [1e-3, 0, 0], o + [0, 1e-3, 0]]
            dT.append((b, b + 1, b + 2))
            dR.append(r)
    V2 = np.concatenate([V, np.asarray(dV)])
    T2 = np.concatenate([T, np.asarray(dT, np.int64)])
    R2 = np.concatenate([region, np.asarray(dR)])
    Z2 = np.concatenate([np.ones(len(T)) if zoom is None else np.asarray(zoom, np.float64), np.ones(len(dT))])
    H2 = np.concatenate([hint, np.zeros((len(dT), 3, 2))])
    ob = mesh_object(name, V2, T2, None, H2)
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.seams_from_islands(mark_seams=True)
    me = ob.data
    bm = bmesh.from_edit_mesh(me)
    bm.faces.ensure_lookup_table()
    # (the mail cut in two, front and back at the sides: unrolled whole it is wider than the side rect. P65b: P59b
    # also cut it left and right down the middle, and the rings' and the shading's seam there read as a crease down
    # the back and the chest)
    C = V[T].mean(axis=1)
    front = np.concatenate([2 * (C[:, 1] < float(np.median(V[:, 1]))), np.zeros(len(dT), int)])
    side = names.index("side")
    for e in bm.edges:
        lf = e.link_faces
        if len(lf) != 2:
            continue
        a, b = lf[0].index, lf[1].index
        if mail and R2[a] == side and R2[b] == side and Z2[a] == Z2[b]:
            # (P65c) the mail's seams are the front/back cut only: the high mesh's seam down the back's middle
            # (MakeHuman's halves) broke the rings' rows along the cleft of the mail's skirt
            e.seam = bool(front[a] != front[b])
        elif R2[a] != R2[b] or Z2[a] != Z2[b] or (mail and R2[a] == side and front[a] != front[b]):
            e.seam = True
    bmesh.update_edit_mesh(me)
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.unwrap(method="ANGLE_BASED", fill_holes=True, correct_aspect=True, margin=0.0)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.average_islands_scale()
    bpy.ops.object.mode_set(mode="OBJECT")
    luv = np.empty(len(me.loops) * 2)
    me.uv_layers[0].data.foreach_get("uv", luv)
    uv = luv.reshape(-1, 3, 2)
    # the mail: upright, at its fixed density (UV per metre of the 1.8 m person)
    if mail:
        mi = names.index("side")
        sel = np.nonzero(R2[:m0] == mi)[0]
        if len(sel):
            isl = uv_islands(T2[sel], uv[sel])
            uvm = _upright(V2, T2[sel], uv[sel], isl, range(isl.max() + 1))
            P = V2[T2[sel]] * F
            a3 = np.linalg.norm(np.cross(P[:, 1] - P[:, 0], P[:, 2] - P[:, 0]), axis=1).sum()
            e1, e2 = uvm[:, 1] - uvm[:, 0], uvm[:, 2] - uvm[:, 0]
            a2 = np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]).sum()
            k = pr.MAIL_UV_PER_M / math.sqrt(a2 / max(a3, 1e-12))
            if os.environ.get("PEOPLE_DEBUG"):
                log("mail: %.3f m2, %d islands, UV area at the fixed density %.4f" % (a3 / 2, isl.max() + 1,
                                                                                     a3 / 2 * pr.MAIL_UV_PER_M ** 2))
            uv[sel] = shelf_pack(uvm * k, isl, pr.ATLAS_REGIONS[mi][1], "mail")
    # the zoomed islands scaled about their own centres (the packer keeps the islands' sizes relative)
    if zoom is not None and np.any(Z2[:m0] != 1.0):
        zsel = np.nonzero(Z2[:m0] != 1.0)[0]
        isl = uv_islands(T2[zsel], uv[zsel])
        for i in range(isl.max() + 1):
            t = zsel[isl == i]
            c = uv[t].reshape(-1, 2).mean(axis=0)
            uv[t] = c + (uv[t] - c) * Z2[t][:, None, None]
    # the pins at the corners; each region packed into its rect
    for j in range(len(dT)):
        r = dR[j]
        u0, v0, u1, v1 = pr.ATLAS_REGIONS[r][1]
        c = np.array([u0, v0]) if j % 2 == 0 else np.array([u1 - 2e-4, v1 - 2e-4])
        uv[m0 + j] = c + np.array([[0, 0], [2e-4, 0], [0, 2e-4]])
    for r, (rname, (u0, v0, u1, v1)) in enumerate(pr.ATLAS_REGIONS):
        sel = np.nonzero(R2[:m0] == r)[0]
        if not len(sel) or (mail and rname == "side"):
            continue
        q = uv[sel].reshape(-1, 2)
        lo, hi = q.min(axis=0), q.max(axis=0)
        sc = 0.98 * min((u1 - u0) / max(hi[0] - lo[0], 1e-9), (v1 - v0) / max(hi[1] - lo[1], 1e-9))
        uv[sel] = (uv[sel] - lo) * sc + np.array([u0, v0]) + 0.002
    me.uv_layers[0].data.foreach_set("uv", uv.astype(np.float32).ravel())
    bpy.ops.object.mode_set(mode="EDIT")
    for r, (rname, rect) in enumerate(pr.ATLAS_REGIONS):
        if not np.any(R2[:m0] == r) or (mail and rname == "side"):
            continue
        # (the other regions' faces hidden: the packer takes every UV it sees)
        bpy.ops.mesh.reveal(select=False)
        bpy.context.tool_settings.mesh_select_mode = (False, False, True)
        bm = bmesh.from_edit_mesh(me)
        bm.faces.ensure_lookup_table()
        uvl = bm.loops.layers.uv.active
        for f in bm.faces:
            f.hide_set(bool(R2[f.index] != r))
            dummy = f.index >= m0
            for lp in f.loops:
                lp[uvl].pin_uv = dummy
        bmesh.update_edit_mesh(me)
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.select_all(action="SELECT")
        fixed = mail and rname == "side"
        bpy.ops.uv.pack_islands(udim_source="ORIGINAL_AABB", rotate=not fixed, rotate_method="ANY", scale=not fixed,
                                margin_method="SCALED", margin=UV_MARGIN, pin=True, pin_method="LOCKED",
                                shape_method="CONCAVE")
        if os.environ.get("PEOPLE_DEBUG"):
            bm = bmesh.from_edit_mesh(me)
            uvl = bm.loops.layers.uv.active
            q = np.array([tuple(lp[uvl].uv) for f in bm.faces if R2[f.index] == r and f.index < m0 for lp in f.loops])
            log("pack %s: %s .. %s, selected %d" % (rname, q.min(axis=0), q.max(axis=0), sum(f.select for f in bm.faces)))
    bpy.ops.object.mode_set(mode="OBJECT")
    luv = np.empty(len(me.loops) * 2)
    me.uv_layers[0].data.foreach_get("uv", luv)
    uv = luv.reshape(-1, 3, 2)[:m0]
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    for r, (rname, (u0, v0, u1, v1)) in enumerate(pr.ATLAS_REGIONS):
        q = uv[region == r].reshape(-1, 2)
        if len(q) and (q.min(axis=0) < np.array([u0, v0]) - 1e-4).any() or len(q) and (
                q.max(axis=0) > np.array([u1, v1]) + 1e-4).any():
            raise SystemExit("people: the %s region's islands do not fit its rect (%s .. %s)" % (
                rname, q.min(axis=0), q.max(axis=0)))
    return uv


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


def hair_piece(person, style, w, kd, covered_head=False):
    """The hair: a shell of the scalp whose thickness rises from under the skin at the mask's edge (the hairline is
    the smooth line where it leaves the skin, P59b), smoothed; the long style also falls down the back."""
    bd, S = person.bd, person.S
    m = bd.masks
    scalp = m["m_scalp"]
    keep = scalp > 0.25
    off = (0.0015 + 0.0095 * pp.sstep(scalp, 0.08, 0.75)) * S
    if style == "long":
        L = bd.landmarks
        V = bd.verts[:N]
        head_cy = L["head_cy"]
        x, y, z = V[:, 0], V[:, 1], V[:, 2]
        sh = 0.5 * (bd.joints["joint-l-shoulder"][2] + bd.joints["joint-r-shoulder"][2])
        neck = bd.joints["joint-neck"][2]
        behind = y > head_cy + 0.005
        down = sh - 0.16                                 # to the shoulder blades
        width = LONG_HAIR_WIDTH_M[0] + LONG_HAIR_WIDTH_M[1] * np.clip((neck - z) / max(neck - down, 1e-3), 0.0, 1.0)
        curtain = behind & (z > down) & (z < L["ear_z"][1] + 0.02) & (np.abs(x) < width) \
            & ((m["m_head"] + m["m_neck"] + m["m_torso"]) > 0.4)
        # P65b: fuller over the crown when nothing is worn over it (it lay tight as a cap, a man's short hair from the
        # front; under a hood the fuller hair came through it)
        keep = keep | curtain
        t = np.clip((L["ear_z"][1] - z) / max(L["ear_z"][1] - down, 1e-3), 0.0, 1.0)
        env = np.nan_to_num(w.C, nan=0.0) if w is not None else np.zeros(N)
        if not covered_head:
            crown = pp.sstep(z, L["ear_z"][1], L["top"] - 0.02)
            vol = (LONG_HAIR_VOLUME_M + LONG_HAIR_CROWN_M * crown) * pp.sstep(scalp, 0.3, 0.8)
            off = off + vol * S
        off = np.where(curtain & ~(scalp > 0.3), (0.012 + 0.03 * t) * S + env, off)
        off = np.maximum(off, np.where(curtain, env + 0.012 * S, off))
        p = shell_piece("hair_long", person, keep, off, "hair", kd)
    else:
        p = shell_piece("hair_crop", person, keep, off, "hair", kd)
    return smoothed(p, 4)


def beard_piece(person, style, kd):
    """A beard: a shell of the beard mask whose thickness rises from under the skin at the mask's edge (so the
    edge is a smooth line on the cheek and the throat, not the body's quads, P59b), the full beard deeper toward
    the chin and falling below it, smoothed."""
    m = person.bd.masks
    beard = m["m_beard"]
    keep = beard > 0.3
    L = person.bd.landmarks
    z = person.bd.verts[:N, 2]
    rise = pp.sstep(beard, 0.1, 0.7)
    if style == "full":
        down = np.clip((L["lip_bot"] - z) / 0.07, 0.0, 1.0)
        off = (0.0015 + (0.006 + 0.024 * down) * rise) * person.S
        return smoothed(shell_piece("beard_full", person, keep, off, "hair", kd), 6)
    off = (0.0015 + 0.004 * rise) * person.S
    return smoothed(shell_piece("beard_short", person, keep, off, "hair", kd), 4)


def smoothed(p, it):
    """A shell piece smoothed: its open edge first along itself (the body's quads' steps straightened into a smooth
    line), then the rest (people_parts.smooth_shell) with the edge held."""
    T = p.T
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    u, cnt = np.unique(e, axis=0, return_counts=True)
    b = u[cnt == 1]
    edge = np.zeros(len(p.V), bool)
    edge[b.ravel()] = True
    V = p.V.copy()
    nb = np.concatenate([b, b[:, ::-1]])
    deg = np.bincount(nb[:, 0], minlength=len(V)).astype(float)
    for _ in range(3 * it):
        acc = np.zeros_like(V)
        for k in range(3):
            acc[:, k] = np.bincount(nb[:, 0], weights=V[nb[:, 1], k], minlength=len(V))
        ok = edge & (deg == 2)
        V[ok] = 0.5 * V[ok] + 0.5 * acc[ok] / 2.0
    p.V = pp.smooth_shell(V, T, it=it, lam=0.5, keep=edge, mu=-0.53)
    return p


def part_piece(name, V, T, mat, person, kd):
    """A people_parts piece (V, T at the design scale) as a Piece: each vertex weighted as the skin nearest it."""
    groups, near = nearest_groups(person, V, kd)
    return Piece(name, V, np.asarray(T, np.int64), np.full(len(T), MATS.index(mat)), groups, near)


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
            th = _eye_ring_angle(ri)
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


def tabard_piece(person, w, kd, female=False):
    bd = person.bd
    V = bd.verts[:N]
    m = bd.masks
    x, z = V[:, 0], V[:, 2]
    hip = 0.5 * (bd.joints["joint-l-upper-leg"][2] + bd.joints["joint-r-upper-leg"][2])
    sh = 0.5 * (bd.joints["joint-l-shoulder"][2] + bd.joints["joint-r-shoulder"][2])
    # P65b: a straight-sided panel front and back joined over the shoulders, its edges smoothed (P59b's cut by the
    # masks' thresholds left notches at the arms and the neck and a point between the legs)
    neck = np.hypot(x, V[:, 1] - bd.joints["joint-neck"][1]) < 0.075
    keep = ((m["m_torso"] + m["m_pelvis"]) > 0.6) & (np.abs(x) < 0.135) & (z > hip - 0.09) & (z < sh + 0.06) \
        & ~(neck & (z > sh - 0.05)) & (m["m_upperarm"] < 0.3) & (m["m_upperleg"] < 0.3)
    env = np.nan_to_num(w.C, nan=0.0)
    off = env + 0.014 * person.S
    p = smoothed(shell_piece("tabard", person, keep, off, "faction", kd, seed=5, hem_noise=0.0), 4)
    if female:
        p.V = drape_bust(p.V, np.ones(len(p.V), bool), person)
    return p


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
    return smoothed(p, 3)


def tile_uv(piece, tile, centre, mode="head"):
    """Corner UVs in a tile of the atlas: |azimuth| about a vertical axis through ``centre`` (mirrored, so no seam)
    across, height up."""
    P = piece.V[piece.T]
    rel = P - centre
    az = np.abs(np.arctan2(rel[..., 0], -rel[..., 1])) / np.pi
    zlo, zhi = float(piece.V[:, 2].min()), float(piece.V[:, 2].max())
    h = (P[..., 2] - zlo) / max(zhi - zlo, 1e-6)
    u0, v0 = pr.TILES[tile]
    m = 0.24                   # (P59b: the tiles are 64 px; a wider margin keeps their mips off the neighbours'. P65b:
    #                            0.16 let the hood's front edge, at the tile's side, take the metal tile's pale grey)
    s = pr.TILE_SIZE
    return np.stack([u0 + s * (m + (1 - 2 * m) * az), v0 + s * (m + (1 - 2 * m) * h)], axis=-1)


def eye_uv(piece):
    """The eyes' tile, a polar map (people_bake's eye pattern): the gaze's pole at the tile's centre, each ring at
    its angle from the gaze (people_bake.EYE_UV_R a degree)."""
    import people_bake as pbk
    u0, v0 = pr.TILES["eye"]
    s = pr.TILE_SIZE
    n = 1 + EYE_RINGS * EYE_SEGMENTS
    uv = np.zeros((len(piece.V), 2))
    for e in range(2):
        uv[e * n] = (0.5, 0.5)
        for ri in range(EYE_RINGS):
            th = math.degrees(_eye_ring_angle(ri + 1))
            for k in range(EYE_SEGMENTS):
                ph = 2 * np.pi * k / EYE_SEGMENTS
                rr = pbk.EYE_UV_R * th
                uv[e * n + 1 + ri * EYE_SEGMENTS + k] = (0.5 + rr * math.cos(ph), 0.5 + rr * math.sin(ph))
    out = np.stack([u0 + s * uv[:, 0], v0 + s * uv[:, 1]], axis=-1)
    return out[piece.T]


def _eye_ring_angle(ri):
    """The angle from the gaze (radians) of the eye's ring ``ri`` (1 .. EYE_RINGS): the first just outside the iris."""
    return math.radians((34.0, 70.0, 112.0)[ri - 1])


def extras_for(v, role, person, w, kd):
    """A variant's own pieces (people_roles: hair, beard, head, extras), decimated, with tile UVs."""
    out = []
    head_c = np.array([0.0, person.bd.landmarks["head_cy"] * person.S, 0.0])
    torso_c = np.array([0.0, float(person.pelvis[1]), 0.0])
    faction = role in ("soldier", "archer", "mage")
    if v["head"]:
        gid = v["head"]
        mat = {"iron_helm": "metal", "iron_helm_guard": "metal", "leather_cap": "leather",
               "hood": "faction" if faction else "cloth"}[gid]
        V, T = pp.hood(person) if gid == "hood" else pp.helm(person, gid)
        p = part_piece(gid, V, T, mat, person, kd)
        out.append((p, {"metal": "metal", "leather": "leather", "faction": "faction", "cloth": "cloth"}[mat], head_c,
                    EXTRA_TRIS[gid]))
    if v["hair"]:
        p = hair_piece(person, v["hair"], w, kd, covered_head=bool(v["head"]))
        under = v["head"] in ("iron_helm", "iron_helm_guard", "leather_cap")
        out.append((p, "hair", head_c, EXTRA_TRIS["hair_" + v["hair"]] // (2 if under else 1)))
    if v["beard"]:
        p = beard_piece(person, v["beard"], kd)
        out.append((p, "hair", head_c, EXTRA_TRIS["beard_" + v["beard"]]))
    for e in v["extras"]:
        if e == "tabard":
            out.append((tabard_piece(person, w, kd, v["sex"] == "female"), "faction", torso_c, EXTRA_TRIS["tabard"]))
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


LAYER_PUSH_GAP_M = 0.004         # at 1.8 m: an outer garment's low surface this far over an inner one's at least
LAYER_PUSH_REACH_M = 0.03


def layer_push(src, LV, LT, piece_tris):
    """The decimated shared mesh's garments kept outside the ones under them (P59b): each low vertex belongs to the
    piece of the high triangle nearest it (``piece_tris``: the triangles of the body and of each garment in src, in
    the order they are worn); a garment's vertex that a ray along its normal finds under an inner piece's low surface
    (within LAYER_PUSH_REACH_M) moves out over it by LAYER_PUSH_GAP_M. The collapse had let an inner garment's
    flat triangles cut through an outer one's: the tunic's patches through the jerkin, the trousers' through the
    boots."""
    piece_of_tri = np.repeat(np.arange(len(piece_tris)), piece_tris)
    tree = bvh(src.V, src.T)
    near = np.zeros(len(LV), np.int64)
    for i, p in enumerate(LV):
        near[i] = piece_of_tri[tree.find_nearest(Vector(p.tolist()))[2]]
    # (the collapse never joins two pieces: each connected part of the low mesh is one piece, the one most of its
    # vertices lie nearest)
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    e = np.concatenate([LT[:, [0, 1]], LT[:, [1, 2]], LT[:, [2, 0]]])
    _n, comp = connected_components(coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(len(LV), len(LV))),
                                    directed=False)
    vpiece = np.zeros(len(LV), np.int64)
    for c in np.unique(comp):
        sel = comp == c
        vpiece[sel] = np.bincount(near[sel], minlength=len(piece_tris)).argmax()
    tpiece = vpiece[LT[:, 0]]
    N = vertex_normals(LV, LT)
    V = LV.copy()
    gap, reach = LAYER_PUSH_GAP_M / F, LAYER_PUSH_REACH_M / F
    moved = 0
    for layer in range(1, len(piece_tris)):
        inner = np.nonzero(tpiece < layer)[0]
        mine = np.nonzero(vpiece == layer)[0]
        if not len(inner) or not len(mine):
            continue
        t_in = bvh(V, LT[inner])
        for i in mine:
            o = V[i] - N[i] * 1e-4
            hit = t_in.ray_cast(Vector(o.tolist()), Vector(N[i].tolist()), reach)
            if hit[0] is not None:
                V[i] = np.asarray(hit[0]) + N[i] * gap
                moved += 1
    # ... and a piece's vertex that pokes out through a piece over it (a ray back along its normal meets the outer
    # piece's surface) is drawn in under it
    pulled = 0
    for layer in range(len(piece_tris) - 2, -1, -1):
        outer = np.nonzero(tpiece > layer)[0]
        mine = np.nonzero(vpiece == layer)[0]
        if not len(outer) or not len(mine):
            continue
        t_out = bvh(V, LT[outer])
        for i in mine:
            o = V[i] + N[i] * 1e-4
            hit = t_out.ray_cast(Vector(o.tolist()), Vector((-N[i]).tolist()), reach)
            if hit[0] is not None and float(np.dot(np.asarray(hit[1]), N[i])) > 0.0:
                V[i] = np.asarray(hit[0]) - N[i] * gap
                pulled += 1
    if os.environ.get("PEOPLE_DEBUG"):
        log("layer push: %d pulled in under an outer piece" % pulled)
    if os.environ.get("PEOPLE_DEBUG"):
        log("layer push: %d of %d vertices moved out over an inner piece; pieces %s" % (
            moved, len(V), np.bincount(vpiece).tolist()))
    return V


# P65a: a variant's own pieces worn over the shared garments (the iron guard's and the heralds' tabards over the mail):
# the decimated mail came through the tabard's chest in holes
OVER_SHARED = ("tabard",)


def over_shared(piece, cloth):
    """``piece`` with each vertex that a ray along its normal finds under the shared garments' low surface (within
    LAYER_PUSH_REACH_M) moved out over it by LAYER_PUSH_GAP_M (layer_push's rule, for a variant's own piece).
    P65b: not over the leather (the belt goes over a tabard: pushed out over the belt it bulged like a belly)."""
    under = cloth.mat != MATS.index("leather")
    if not under.any():
        return piece
    t_in = bvh(cloth.V, cloth.T[under])
    N = vertex_normals(piece.V, piece.T)
    V = piece.V.copy()
    gap, reach = LAYER_PUSH_GAP_M / F, LAYER_PUSH_REACH_M / F
    for i in range(len(V)):
        o = V[i] - N[i] * 1e-4
        hit = t_in.ray_cast(Vector(o.tolist()), Vector(N[i].tolist()), reach)
        if hit[0] is not None:
            V[i] = np.asarray(hit[0]) + N[i] * gap
    return Piece(piece.name, V, piece.T, piece.mat, piece.groups, piece.attach, piece.uv)


def atlas_regions(src, LV, LT, Lmat, tri, bary, person, spec):
    """Per shared triangle its atlas region (people_roles.ATLAS_REGIONS): the head's skin (face, ears, scalp); the
    mail, or (a role without mail) the garments below the crotch; the rest."""
    names = [r[0] for r in pr.ATLAS_REGIONS]
    head_v = np.zeros(len(src.V))
    body = np.arange(len(src.V)) < src.n_body
    head_v[body] = person.bd.masks["m_head"][src.attach[body]]
    head_l = interpolate(head_v, src.T, tri, bary)
    skin = np.isin(Lmat, [MATS.index("skin"), MATS.index("lips")])
    out = np.full(len(LT), names.index("main"))
    out[skin & (head_l[LT].mean(axis=1) > 0.5)] = names.index("head")
    # the face (the head's skin off the scalp) at FACE_ZOOM times the scalp's density in the head's rect
    scalp_v = np.zeros(len(src.V))
    scalp_v[body] = person.bd.masks["m_scalp"][src.attach[body]]
    scalp_l = interpolate(scalp_v, src.T, tri, bary)
    zoom = np.ones(len(LT))
    zoom[(out == names.index("head")) & (scalp_l[LT].mean(axis=1) < 0.5)] = FACE_ZOOM
    if "mail_hauberk" in spec["outfit"]:
        out[Lmat == MATS.index("mail")] = names.index("side")
    else:
        crotch = float(person.rest.head["pelvis"][2]) - 0.1 / F
        low = (LV[LT][:, :, 2].mean(axis=1) < crotch) & ~skin
        out[low] = names.index("side")
    return out, zoom


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
    garments = [tame_bulge(g, p0) if gid in TAMED else g for g, gid in zip(garments, order)]
    garments = [span_seat(g, p0) if gid in SPANNED else g for g, gid in zip(garments, order)]
    if vs[0]["sex"] == "female":
        for g in garments:
            g.V = drape_bust(g.V, np.ones(len(g.V), bool), p0)
    garments = [smoothed(g, SMOOTHED[gid]) if gid in SMOOTHED else g for g, gid in zip(garments, order)]
    for gid in spec["outfit"]:
        if gid in pr.FOOTWEAR:
            garments.append(footwear_piece(gid, p0, kd0))
            order.append(gid)
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
    # the face (the head's skin but the scalp) and the hands keep more triangles
    m0 = p0.bd.masks
    face = np.clip(m0["m_head"] - m0["m_scalp"], 0.0, 1.0) * DETAIL_WEIGHT["face"]
    hands = np.clip(m0["m_hand"], 0.0, 1.0) * DETAIL_WEIGHT["hands"]
    detail = np.zeros(len(src.V))
    detail[:src.n_body] = np.maximum(face, hands)[body.attach]
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
    LV, LT, Lmat, Lhint = decimate(src.V, src.T, src.mat, budget, "_shared_" + role, uv=src.uv, detail=detail,
                                   detail_factor=PEOPLE_DETAIL_FACTOR)
    LV = layer_push(src, LV, LT, [len(body.T)] + [len(g.T) for g in kept])
    tri, bary, offset = correspond(src, LV)
    reg, zoom = atlas_regions(src, LV, LT, Lmat, tri, bary, p0, spec)
    Luv = unwrap_atlas(LV, LT, Lhint, reg, "_uv_" + role, mail="mail_hauberk" in spec["outfit"], zoom=zoom)
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
        if "mail_hauberk" in spec["outfit"]:
            Vk, keep_t = mail_over(Vk, LT, Lmat, person)
        else:
            keep_t = np.ones(len(LT), bool)
        if v["sex"] == "female":
            cloth_v = np.zeros(len(Vk), bool)
            cloth_v[LT[~skin_sel].ravel()] = True
            Vk = drape_bust(Vk, cloth_v, person)
        zeros = np.zeros(len(Vk), np.int64)
        skin = Piece("skin", Vk, LT[skin_sel], Lmat[skin_sel], lgroups, zeros, Luv[skin_sel])
        cl = ~skin_sel & keep_t
        cloth = compact_piece(Piece("cloth", Vk, LT[cl], Lmat[cl], lgroups, zeros, Luv[cl]))
        own = [over_shared(p, cloth) if p.name in OVER_SHARED else p for p in own]
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
                              extra_meshes=[merge(extras[0])], face_rect=dict(pr.ATLAS_REGIONS)["head"])
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
        for sd in ("l", "r"):
            # the grip landmark in the hand bone's own frame at 1.8 m (people_body.grip_landmark; PersonRig's fist)
            g, ax = person.grip[sd]
            H = rest["hand_" + sd]
            info["variants"][v["name"]]["grip_local_" + sd] = [r6(x) for x in
                                                               (H[:3, :3].T @ (g * F - H[:3, 3]))]
            info["variants"][v["name"]]["grip_axis_" + sd] = [r6(x) for x in (H[:3, :3].T @ ax)]
        if k == 0:
            rest0, arm0, mesh0 = rest, arm, mesh
    parents = pbody.parents_of(arm0)
    idx4, w40 = pr.top4(mesh0.groups, len(mesh0.V))
    V0 = mesh0.V * F
    for pose in pr.POSES:
        clip, key = pr.pose_clip(role, pose)
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
            Vf, Tf, mf, uvf = far_mesh(P, mesh0.T, mesh0.uv)
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


FAR_LAYER_REACH = 0.12           # (design metres) how far outside a far triangle its colour's ray starts


def far_mesh(P, T, uv):
    """The far mesh (P59b): the hold pose's surface welded (one closed skin, no UV seams for the collapse to tear at:
    P59's far meshes were spiky at the feet) and collapsed to FAR_TRIS_MAX, each triangle then coloured from the
    pose's outermost triangle over its centre (along its normal; else the nearest) (its three corners' UVs inside
    that triangle: one colour, no smear across an island's edge)."""
    q = np.round(P / 1e-4).astype(np.int64)
    _u, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    W, WT = P[first], inv.ravel()[T]
    WT = WT[(WT[:, 0] != WT[:, 1]) & (WT[:, 1] != WT[:, 2]) & (WT[:, 0] != WT[:, 2])]
    Vf, Tf, mf, _ = decimate(W, WT, np.zeros(len(WT), np.int32), pr.FAR_TRIS_MAX, "_far", symmetric=False)
    tree = bvh(P, T)
    C = Vf[Tf].mean(axis=1)
    Nf = np.cross(Vf[Tf[:, 1]] - Vf[Tf[:, 0]], Vf[Tf[:, 2]] - Vf[Tf[:, 0]])
    Nf /= np.maximum(np.linalg.norm(Nf, axis=1, keepdims=True), 1e-12)
    uvf = np.zeros((len(Tf), 3, 2))
    for i, c in enumerate(C):
        # (gate C) the outermost layer along the triangle's normal: a ray from FAR_LAYER_REACH outside it inward.
        # The nearest point to the collapsed centre (inside the body) was an inner layer's: the soldiers' far mesh
        # took the mail's grey where the pose wears the surcoat over it.
        o = c + Nf[i] * FAR_LAYER_REACH
        hit = tree.ray_cast(Vector(o.tolist()), Vector((-Nf[i]).tolist()), 2.0 * FAR_LAYER_REACH)
        if hit[0] is None:
            hit = tree.find_nearest(Vector(c.tolist()))
        t = hit[2]
        A, B, D = P[T[t, 0]], P[T[t, 1]], P[T[t, 2]]
        b = np.clip(barycentric(np.asarray(hit[0])[None], A[None], B[None], D[None]), 0.0, 1.0)[0]
        b /= b.sum()
        mid = b @ uv[t]
        # (the corners a little toward the triangle's own corners, so the far mesh is not one flat colour a face)
        uvf[i] = mid + 0.25 * (uv[t] - mid)
    return Vf, Tf, mf, uvf


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
