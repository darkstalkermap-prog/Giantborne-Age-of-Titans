"""The people's own pieces (P59b, plan M11 §2.8): the headgear, the hood, the boots, and the hair's and the beards'
shells, built for a person's body as clean parametric surfaces.

P59 dressed the people in the giant's own garment shells (giant_garment), which are the body's faces pushed out:
right for a giant seen whole, but decimated to a person's few hundred triangles a helm kept the shell's ragged rim
and the ears' flaps, a hood crumpled, a boot followed the toes and a beard stood off the jaw as a block with stepped
edges. Here each piece is laid out on a grid of its own around the body (rings round the head, sections along the
foot), its size read from the body itself (rays from inside the head to the skull, the foot's and the calf's
sections), so it reads as the thing it is at the size it is seen, and its edges are straight or smooth curves:

  * ``helm``      a rounded iron cap over the skull with a brow band, a rolled rim and a nasal (the iron guard's:
                  cheek plates too); ``cap``: the leather cap, lower, with a rolled band;
  * ``hood``      a hood whose face opening is a smooth oval, loose over the crown and drawn to a soft point behind,
                  falling into a short cape over the shoulders;
  * ``boot``      a boot round each foot: a rounded toe box, a sole with its welt, a heel, a shaft up the calf with a
                  turned-down cuff (the ``shoe``: the same, cut at the ankle);
  * ``hair_shell`` and ``beard_shell``: the body's scalp or beard skin pushed out by a thickness that rises smoothly
                  from below the skin at the edge, so the hairline and the beard's edge are the smooth line where the
                  shell leaves the skin, not the stepped edge of the body's quads, and the shell itself smoothed.

Every function works at the design scale (people_roles.DESIGN_HEIGHT_M; the giant's frame: +X the person's left,
-Y the front, +Z up) and returns (V, T) or a people_outfit.Piece. numpy and Blender's BVH (mathutils).
"""
from __future__ import annotations

import math
import os
import sys

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import numpy as np  # noqa: E402
from mathutils import Vector  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import mh_data as mh  # noqa: E402

N = mh.N_BODY_VERTS


def sstep(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def body_tree(person):
    """Blender's BVH of the person's skin (design scale)."""
    _, faces, _ = person.bd.group("body")
    V = person.body_V()
    tris = [(int(f[0]), int(f[1]), int(f[2])) for f in faces] + [(int(f[0]), int(f[2]), int(f[3])) for f in faces]
    return BVHTree.FromPolygons([tuple(map(float, v)) for v in V], tris, all_triangles=True)


def reach(tree, origin, dirs, far):
    """The distance from ``origin`` along each direction to the skin (``far`` where nothing is hit)."""
    o = Vector(tuple(map(float, origin)))
    out = np.full(len(dirs), far)
    for i, d in enumerate(dirs):
        hit = tree.ray_cast(o, Vector(tuple(map(float, d))), far)
        if hit[0] is not None:
            out[i] = hit[3]
    return out


def smooth_grid(R, it, closed=True, axis_rows=True, keep_ends=False):
    """A (rows, cols) field smoothed by neighbour averaging (the columns wrap when ``closed``)."""
    R = np.asarray(R, np.float64).copy()
    for _ in range(it):
        S = R.copy()
        if closed:
            S[:, :] = 0.5 * R + 0.25 * (np.roll(R, 1, axis=1) + np.roll(R, -1, axis=1))
        else:
            S[:, 1:-1] = 0.5 * R[:, 1:-1] + 0.25 * (R[:, :-2] + R[:, 2:])
        if axis_rows:
            S2 = S.copy()
            S2[1:-1] = 0.5 * S[1:-1] + 0.25 * (S[:-2] + S[2:])
            S = S2
        R = S
    return R


def grid_tris(rows, cols, closed=True, base=0):
    """Quads (as triangles) of a rows x cols grid of vertices, row-major (columns wrap when ``closed``)."""
    T = []
    cc = cols if closed else cols - 1
    for r in range(rows - 1):
        for c in range(cc):
            a = base + r * cols + c
            b = base + r * cols + (c + 1) % cols
            d = base + (r + 1) * cols + c
            e = base + (r + 1) * cols + (c + 1) % cols
            T += [(a, b, e), (a, e, d)]
    return T


def orient_out(V, T, centre):
    """Triangles wound so their normals point away from ``centre`` (a point or, (n, 3), one per triangle)."""
    T = np.asarray(T, np.int64)
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    c = V[T].mean(axis=1) - np.asarray(centre)
    flip = np.einsum("ij,ij->i", n, c) < 0
    T[flip] = T[flip][:, ::-1]
    return T


# --------------------------------------------------------------------------------------
# headgear
# --------------------------------------------------------------------------------------
def head_centre(person):
    L = person.bd.landmarks
    S = person.S
    return np.array([0.0, L["head_cy"] * S, 0.5 * (L["ear_z"][1] + L["eye_z"]) * S])


def rim_height(person, phi, front, side, back):
    """A rim's height (design m) round the head at azimuth ``phi`` (0 the front, pi the back): ``front`` over the
    brows, ``side`` over the ears, ``back`` at the nape (human m), blended smoothly."""
    c = np.cos(phi)
    a = np.abs(c)
    z = np.where(c >= 0.0, side + (front - side) * a ** 1.5, side + (back - side) * a ** 1.2)
    return z * person.S


def dome(person, tree, rim_front, rim_side, rim_back, stand, crown_lift=0.0, cols=24, rows=8, point=0.0):
    """A cap over the skull: (P (rows, cols, 3) design m, rim heights (cols,)). Each column rises from the rim to
    the crown along a meridian; at every point the skull's distance along the ray from the head's centre plus
    ``stand(s)`` (s: 0 at the rim, 1 at the crown; design m), smoothed; ``point`` lifts the crown to a soft peak."""
    S = person.S
    c = head_centre(person)
    phi = np.linspace(0.0, 2.0 * np.pi, cols, endpoint=False)
    zr = rim_height(person, phi, rim_front, rim_side, rim_back)
    s = np.linspace(0.0, 1.0, rows)
    P = np.zeros((rows, cols, 3))
    Rr = np.zeros((rows, cols))
    D = np.zeros((rows, cols, 3))
    for j in range(cols):
        # the rim's elevation seen from the centre (a first guess of the skull's radius there: 0.09 m)
        e0 = math.atan2(zr[j] - c[2], 0.09 * S)
        e = e0 + (0.5 * np.pi * 0.985 - e0) * (1.0 - (1.0 - s) ** 1.15)
        d = np.stack([np.cos(e) * np.sin(phi[j]), -np.cos(e) * np.cos(phi[j]), np.sin(e)], axis=-1)
        D[:, j] = d
        Rr[:, j] = reach(tree, c, d, 0.25 * S)
    Rr = smooth_grid(Rr, 3)
    for i in range(rows):
        Rr[i] += stand(s[i]) + point * S * sstep(s[i], 0.6, 1.0) ** 2
    P = c + D * Rr[..., None]
    # (the rim's row moved onto the rim's height exactly: a level line, not the rays' stepped one)
    P[0, :, 2] = zr
    return P, zr


def _cap_mesh(P, top_close=True):
    rows, cols, _ = P.shape
    V = P.reshape(-1, 3).tolist()
    T = grid_tris(rows, cols)
    if top_close:
        apex = np.mean(P[-1], axis=0)
        V.append(apex.tolist())
        a = len(V) - 1
        base = (rows - 1) * cols
        T += [(base + c, base + (c + 1) % cols, a) for c in range(cols)]
    return np.asarray(V), T


def _rolled_rim(P, out_m, down_m, under_m, S):
    """Rows under a cap's rim row: out and down (a rolled edge), then back in under it (the thickness)."""
    rim = P[0]
    c = rim.mean(axis=0)
    radial = rim - c
    radial[:, 2] = 0.0
    radial /= np.maximum(np.linalg.norm(radial, axis=1, keepdims=True), 1e-9)
    lip = rim + radial * out_m * S + np.array([0, 0, -down_m * S])
    under = rim - radial * under_m * S + np.array([0, 0, -down_m * 1.4 * S])
    return np.concatenate([under[None], lip[None], P], axis=0)


def helm(person, kind="iron_helm"):
    """The iron helm (a skull cap: a brow band, a rolled rim and a nasal) or, ``kind`` "iron_helm_guard", the iron
    guard's heavier one (deeper, with cheek plates), or "leather_cap" (lower, rounder, a rolled band, no nasal).
    Returns (V, T) at the design scale."""
    L = person.bd.landmarks
    S = person.S
    tree = body_tree(person)
    hair = 0.011 * S                          # the crop under it
    if kind == "leather_cap":
        P, zr = dome(person, tree, L["brow_z"] + 0.018, L["ear_z"][1] + 0.006, L["ear_z"][1] - 0.01,
                     lambda s: hair + 0.002 * S + 0.001 * S * s, cols=22, rows=7)
        P = _rolled_rim(P, 0.005, 0.003, 0.004, S)
        V, T = _cap_mesh(P)
        return V, orient_out(V, T, head_centre(person))
    deep = kind == "iron_helm_guard"
    P, zr = dome(person, tree, L["brow_z"] + 0.004, L["ear_z"][1] - (0.006 if deep else 0.0),
                 L["ear_z"][1] - (0.035 if deep else 0.022),
                 lambda s: hair + 0.006 * S + 0.002 * S * s, cols=24, rows=8, point=0.012)
    rows, cols, _ = P.shape
    # the brow band: the lowest rows stand a little further out
    c0 = P[0].mean(axis=0)
    for i, lift in ((1, 0.0035), (2, 0.0025)):
        rad = P[i] - c0
        rad[:, 2] = 0.0
        rad /= np.maximum(np.linalg.norm(rad, axis=1, keepdims=True), 1e-9)
        P[i] = P[i] + rad * lift * S
    rad0 = P[0] - c0
    rad0[:, 2] = 0.0
    rad0 /= np.maximum(np.linalg.norm(rad0, axis=1, keepdims=True), 1e-9)
    P[0] = P[0] + rad0 * 0.0035 * S
    P = _rolled_rim(P, 0.003, 0.003, 0.004, S)
    V, T = _cap_mesh(P)
    V = V.tolist()
    T = list(T)
    # the nasal: a strip down the nose's bridge from the band
    eye_z = L["eye_z"] * S
    face_y = L["face_y"] * S
    nz = np.linspace(L["brow_z"] * S + 0.006 * S, eye_z - 0.03 * S, 4)
    half = 0.0075 * S
    base = len(V)
    for z in nz:
        # the bridge's front at this height: a ray from behind it
        o = np.array([0.0, face_y + 0.06 * S, z])
        r = reach(tree, o, np.array([[0.0, -1.0, 0.0]]), 0.2 * S)[0]
        y = o[1] - r - 0.0015 * S
        V += [[-half, y + 0.002 * S, z], [-half * 0.6, y, z], [half * 0.6, y, z], [half, y + 0.002 * S, z]]
    for k in range(len(nz) - 1):
        a = base + 4 * k
        for m in range(3):
            T += [(a + m, a + m + 1, a + 4 + m + 1), (a + m, a + 4 + m + 1, a + 4 + m)]
    if deep:
        # cheek plates: down from the band over each cheek, in front of the ear
        for sg in (1.0, -1.0):
            base = len(V)
            pl = []
            for zz in np.linspace(0.0, 1.0, 3):
                for t in np.linspace(0.0, 1.0, 3):
                    ph = sg * (1.0 + 0.62 * t)               # from the cheekbone back to the ear's front
                    z = rim_height(person, np.array([ph]), L["brow_z"] + 0.004, L["ear_z"][1] - 0.006,
                                   L["ear_z"][1] - 0.035)[0] + 0.004 * S - zz * (0.075 - 0.02 * t) * S
                    d = np.array([math.sin(ph), -math.cos(ph), 0.0])
                    o = head_centre(person).copy()
                    o[2] = z
                    r = reach(tree, o, d[None], 0.3 * S)[0]
                    pl.append((o + d * (r + 0.016 * S - 0.004 * S * zz)).tolist())
            V += pl
            T += [tuple(base + q for q in t) for t in grid_tris(3, 3, closed=False)]
    V = np.asarray(V)
    return V, orient_out(V, T, head_centre(person))


# --------------------------------------------------------------------------------------
# the hood
# --------------------------------------------------------------------------------------
def hood(person, cols=26):
    """A hood: rows of rays from the head's centre, from the crown down past the chin to a short cape over the
    shoulders' tops; each point the skin's distance along its ray plus the cloth's looseness (more over the crown
    and behind, where the hood is drawn to a soft point). Over the face the rows span only the arc outside a smooth
    oval opening, so its edge is a clean curve; under the chin the rows close round the neck. Returns (V, T) at the
    design scale."""
    L = person.bd.landmarks
    S = person.S
    tree = body_tree(person)
    c = head_centre(person)
    brow, chin = L["brow_z"] * S, L["chin"] * S
    face_d = abs(L["face_y"] * S - c[1])
    e_top = math.atan2(brow + 0.028 * S - c[2], face_d)
    e_bot = math.atan2(chin - 0.03 * S - c[2], face_d * 0.8)
    o_half = math.radians(64.0)
    elev = np.radians(np.array([84.0, 72.0, 58.0, 44.0, 30.0, 16.0, 2.0, -12.0, -26.0, -38.0, -48.0, -56.0, -63.0]))
    rows = len(elev)
    P = np.zeros((rows, cols + 1, 3))
    opens = []
    for i, e in enumerate(elev):
        if e_bot < e < e_top:
            t = (e - 0.5 * (e_top + e_bot)) / (0.5 * (e_top - e_bot))
            a0 = o_half * math.sqrt(max(0.0, 1.0 - t * t)) ** 0.7
        else:
            a0 = 0.0
        opens.append(a0 > 0.0)
        phi = np.linspace(a0, 2.0 * np.pi - a0, cols + 1)
        d = np.stack([np.cos(e) * np.sin(phi), -np.cos(e) * np.cos(phi), np.full(cols + 1, math.sin(e))], axis=-1)
        r = reach(tree, c, d, 0.5 * S)
        miss = r >= 0.5 * S
        if miss.any():
            r[miss] = np.median(r[~miss]) if (~miss).any() else 0.1 * S
        back = sstep(-np.cos(phi), -0.3, 0.9)
        up = sstep(math.sin(e), -0.2, 0.9)
        cape = sstep(-math.sin(e), 0.55, 0.85)
        loose = (0.016 + 0.01 * up + 0.012 * back * up + 0.01 * cape) * S
        P[i] = c + d * (r + loose)[:, None]
    # the crown drawn back to a soft fold (not a point: from afar a pointed hood read as a cap of a gnome)
    for i, e in enumerate(elev):
        w = sstep(math.sin(e), 0.3, 1.0)
        P[i, :, 1] += 0.014 * S * w ** 1.5
    R = P.copy()
    for _ in range(2):
        R[:, 1:-1] = 0.5 * R[:, 1:-1] + 0.25 * (R[:, :-2] + R[:, 2:])
        R[1:-1] = 0.6 * R[1:-1] + 0.2 * (R[:-2] + R[2:])
    P = R
    V = P.reshape(-1, 3).tolist()
    T = grid_tris(rows, cols + 1, closed=False)
    remap = np.arange(len(V))
    for i in range(rows):
        if not opens[i]:
            remap[i * (cols + 1) + cols] = i * (cols + 1)
    T = [tuple(int(remap[q]) for q in t) for t in T]
    T = [t for t in T if len(set(t)) == 3]
    apex = P[0].mean(axis=0) + np.array([0.0, 0.0, 0.006 * S])
    V.append(apex.tolist())
    a = len(V) - 1
    T += [(int(remap[q]), int(remap[q + 1]), a) for q in range(cols)]
    V = np.asarray(V)
    used = np.unique(np.asarray(T).ravel())
    m = -np.ones(len(V), np.int64)
    m[used] = np.arange(len(used))
    V = V[used]
    T = m[np.asarray(T)]
    return V, orient_out(V, T, c)


# --------------------------------------------------------------------------------------
# boots
# --------------------------------------------------------------------------------------
def _hull(P):
    from scipy.spatial import ConvexHull
    h = ConvexHull(P)
    T = orient_out(P, h.simplices, P[h.vertices].mean(axis=0))
    return P, T


def _remeshed(parts, voxel, smooth_it, name, tris=1600):
    """One closed surface round the union of closed meshes ``parts`` [(V, T)] (Blender's voxel remesh, smoothed,
    and collapsed to about ``tris`` triangles: the role's decimation takes it from there): (V, T)."""
    import bpy
    V = np.concatenate([p[0] for p in parts])
    off = np.cumsum([0] + [len(p[0]) for p in parts])[:-1]
    T = np.concatenate([np.asarray(p[1]) + o for p, o in zip(parts, off)])
    me = bpy.data.meshes.new(name)
    me.from_pydata(V.tolist(), [], T.tolist())
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = ob.modifiers.new("Remesh", "REMESH")
    m.mode = "VOXEL"
    m.voxel_size = voxel
    m.use_smooth_shade = True
    sm = ob.modifiers.new("Smooth", "LAPLACIANSMOOTH")
    sm.iterations = smooth_it
    sm.lambda_factor = 0.6
    sm.use_volume_preserve = True
    dg = bpy.context.evaluated_depsgraph_get()
    n0 = len(ob.evaluated_get(dg).data.polygons)
    dm = ob.modifiers.new("Decimate", "DECIMATE")
    dm.decimate_type = "COLLAPSE"
    dm.use_collapse_triangulate = True
    dm.ratio = min(1.0, tris / max(2.0 * n0, 1.0))
    dg = bpy.context.evaluated_depsgraph_get()
    ev = ob.evaluated_get(dg)
    em = ev.to_mesh()
    n = len(em.vertices)
    Vo = np.empty(n * 3)
    em.vertices.foreach_get("co", Vo)
    em.calc_loop_triangles()
    To = np.empty(len(em.loop_triangles) * 3, np.int64)
    em.loop_triangles.foreach_get("vertices", To)
    ev.to_mesh_clear()
    bpy.data.objects.remove(ob, do_unlink=True)
    bpy.data.meshes.remove(me)
    return Vo.reshape(-1, 3), To.reshape(-1, 3)


def _cylinder(c0, c1, r0, r1, n=14):
    """A closed tapered cylinder from c0 to c1 (vertical: (x, y, z) centres), radii (rx, ry) at each end."""
    ang = np.linspace(0.0, 2.0 * np.pi, n, endpoint=False)
    V = []
    for c, r in ((c0, r0), (c1, r1)):
        V += [[c[0] + r[0] * math.cos(a), c[1] + r[1] * math.sin(a), c[2]] for a in ang]
    V += [list(c0), list(c1)]
    T = grid_tris(2, n) + [(2 * n, (k + 1) % n, k) for k in range(n)] + [(2 * n + 1, n + k, n + (k + 1) % n)
                                                                         for k in range(n)]
    V = np.asarray(V, np.float64)
    return V, orient_out(V, T, 0.5 * (np.asarray(c0) + np.asarray(c1)))


def boots(person, shaft=0.5, cuff=True):
    """Both boots (or, with a low ``shaft``, shoes): each the union, remeshed into one smooth closed surface, of
    the foot's convex hull pushed out by the leather (a rounded toe box over the toes, never the toes themselves),
    a sole slab a little wider than the foot under it (the welt) with a heel block, and the shaft: a tapered
    cylinder round the leg's sections from the ankle up to ``shaft`` of the way to the knee, with a wider band at
    its top (the turned-down cuff). Returns (V, T) at the design scale."""
    bd = person.bd
    S = person.S
    J = bd.joints
    V = person.body_V()
    m = bd.masks
    leather = 0.007 * S
    parts = []
    for s, sg in (("l", 1.0), ("r", -1.0)):
        ankle = J["joint-%s-ankle" % s] * S
        knee = J["joint-%s-knee" % s] * S
        side = np.sign(V[:, 0]) == sg
        F = V[side & (m["m_foot"] > 0.4)]
        F = F[F[:, 2] < ankle[2] + 0.02 * S]
        cF = F.mean(axis=0)
        # the foot pushed out from its own axis (the hull's centre line), then its hull: the toes' gaps spanned
        rel = F - np.array([cF[0], 0.0, cF[2] * 0.6])
        rel[:, 1] = 0.0
        n = np.linalg.norm(rel, axis=1, keepdims=True)
        Fo = F + rel / np.maximum(n, 1e-9) * leather
        toe_y, heel_y = float(F[:, 1].min()), float(F[:, 1].max())
        Fo[:, 1] = np.clip(Fo[:, 1], toe_y - 0.006 * S, heel_y + 0.006 * S)
        Fo[:, 2] = np.maximum(Fo[:, 2], 0.012 * S)
        # the toe box: the toes' tips' corners rounded off (the hull of the front points pulled in)
        front = (Fo[:, 1] - toe_y) / (heel_y - toe_y) < 0.12
        Fo[front, 0] = cF[0] + (Fo[front, 0] - cF[0]) * 0.85
        parts.append(_hull(Fo))
        # the sole and the heel: a slab under the foot's outline, a little wider
        o = F[:, :2]
        oc = o.mean(axis=0)
        ring = oc + (o - oc) * 1.0
        sole_top, sole_bot = 0.016 * S, 0.0
        Q = np.concatenate([np.column_stack([ring + (ring - oc) / np.maximum(np.linalg.norm(ring - oc, axis=1,
                                                                                            keepdims=True), 1e-9)
                                             * (leather + 0.006 * S), np.full(len(ring), z)])
                            for z in (sole_bot, sole_top)])
        parts.append(_hull(Q))
        heel = F[(F[:, 1] - toe_y) / (heel_y - toe_y) > 0.72]
        hx0, hx1 = heel[:, 0].min() - leather, heel[:, 0].max() + leather
        hy0, hy1 = heel[:, 1].min(), heel[:, 1].max() + leather + 0.002 * S
        Hb = np.array([[x, y, z] for x in (hx0, hx1) for y in (hy0, hy1) for z in (0.0, 0.045 * S)])
        parts.append(_hull(Hb))
        # the shaft
        legs = []
        for t in np.linspace(0.05, shaft, 4):
            z = ankle[2] + (knee[2] - ankle[2]) * t
            Q2 = V[side & (m["m_lowerleg"] + m["m_foot"] > 0.3) & (np.abs(V[:, 2] - z) < 0.02 * S)]
            if len(Q2) < 4:
                continue
            cx, cy = float(np.mean(Q2[:, 0])), float(np.mean(Q2[:, 1]))
            # (over the trousers: their shell stands about 1.2 cm off the leg at 1.8 m)
            rx = float(np.percentile(np.abs(Q2[:, 0] - cx), 96)) + leather + 0.016 * S
            ry = float(np.percentile(np.abs(Q2[:, 1] - cy), 96)) + leather + 0.016 * S
            legs.append((np.array([cx, cy, z]), (rx, ry)))
        for (c0, r0), (c1, r1) in zip(legs[:-1], legs[1:]):
            parts.append(_cylinder(c0 - np.array([0, 0, 0.01 * S]), c1, r0, r1))
        # the ankle filled to the foot (the shaft meets the instep)
        c0, r0 = legs[0]
        parts.append(_cylinder(np.array([c0[0], c0[1] + 0.004 * S, 0.012 * S]), c0, (r0[0] * 1.05, r0[1] * 1.15), r0))
        if cuff:
            c1, r1 = legs[-1]
            parts.append(_cylinder(c1 - np.array([0, 0, 0.04 * S]), c1 + np.array([0, 0, 0.006 * S]),
                                   (r1[0] + 0.011 * S, r1[1] + 0.011 * S), (r1[0] + 0.009 * S, r1[1] + 0.009 * S)))
    return _remeshed(parts, 0.005 * S, 2, "_boots")


# --------------------------------------------------------------------------------------
# hair and beards
# --------------------------------------------------------------------------------------
def smooth_shell(V, T, it=6, lam=0.5, keep=None, mu=None):
    """A shell's vertices moved toward their neighbours' mean (``keep``: per vertex, held still where true); with
    ``mu`` (negative) each pass is followed by one away from it (Taubin's: the shell keeps its size)."""
    V = np.asarray(V, np.float64).copy()
    e = np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=len(V)).astype(float)
    for _ in range(it):
        for f in ((lam, mu) if mu is not None else (lam,)):
            acc = np.zeros_like(V)
            for k in range(3):
                acc[:, k] = np.bincount(e[:, 0], weights=V[e[:, 1], k], minlength=len(V))
            mean = acc / np.maximum(deg, 1)[:, None]
            step = f * (mean - V)
            if keep is not None:
                step[keep] = 0.0
            V = V + step
    return V
