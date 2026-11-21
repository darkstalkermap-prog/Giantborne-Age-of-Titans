"""A role's atlas (plan M11 §2.8, P59): albedo at 512 px, normal at 256 px, and one 256 px map holding ambient
occlusion (R), roughness (G) and the palette band (B, people_roles.BANDS).

Baked from the role's first variant: every texel of the shared mesh's UV square is found on its triangle (a
rasterizer here, in numpy), and read from the high mesh it was decimated from (the body and the outfit before
decimation, the nearest of its vertices of the same material, inverse-distance weighted): the material and its
masks (lips, brows, nails) give the albedo and the roughness, the high mesh's normal in the shared mesh's tangent
frame (Blender's MikkTSpace tangents, exported with the meshes) gives the normal map. The variants' own pieces take
the atlas's tiles (people_roles.TILES), painted here from the project's own procedural patterns. Everything is the
project's code and the CC0 MakeHuman masks; no Cycles: the bake is deterministic, so a regeneration is bit-exact.

The expensive pass is the ambient occlusion: rays from every high-mesh vertex over its hemisphere against the high
mesh and the first variant's own pieces (Blender's BVH), then the texels' inverse-distance mean. ``ao_from`` (the
committed ORM map, build_people.py --skip-bake) reads it back from that map's R channel instead.
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image

import people_roles as pr

BAKE_RAYS = 24
AO_REACH_M = 0.22            # at 1.8 m
AO_FLOOR = 0.35
DILATE_PX = 8
CONSERVATIVE_PX = 0.85
FACING_REACH_M = 0.02        # at 1.8 m: how much further a texel looks for high-mesh triangles facing its way
# P65b: the roles whose atlas draws age in the face's skin (age_lines): the elders'. The face's normal map is flat
# (P65a: each variant's face is shaded by its own vertex normals), so age is drawn in the albedo as soft creases:
# three lines across the forehead, the crow's feet, the folds from the nose's wings past the mouth, the lines from
# the mouth's corners down, and the shadow of the eyes' bags. Each its darkening (a share of the skin's albedo).
AGE_LINES = {"elder": {"forehead": 0.2, "crow": 0.22, "fold": 0.18, "marionette": 0.12, "bags": 0.12}}


def _hash3(i, j, k, seed):
    h = (i * 73856093) ^ (j * 19349663) ^ (k * 83492791) ^ (seed * 2654435761)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF).astype(np.float64) / 65535.0


def vnoise(P, scale, seed=0):
    """Value noise in [0, 1] at points P (n, 3), trilinear over an integer lattice of ``scale`` cells a unit."""
    Q = np.asarray(P, np.float64) * scale
    i0 = np.floor(Q).astype(np.int64)
    f = Q - i0
    f = f * f * (3.0 - 2.0 * f)
    out = np.zeros(len(Q))
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out += w * _hash3(i0[:, 0] + dx, i0[:, 1] + dy, i0[:, 2] + dz, seed)
    return out


def fbm(P, scale, seed=0, octaves=3):
    out = np.zeros(len(P))
    amp, tot = 1.0, 0.0
    for o in range(octaves):
        out += amp * vnoise(P, scale * (2 ** o), seed + o)
        tot += amp
        amp *= 0.5
    return out / tot


def raster(uv, size):
    """(tri id (size, size), -1 where empty; barycentrics (size, size, 3)) of corner UVs (m, 3, 2) (Blender's v up;
    image row 0 is v = 1)."""
    tri = -np.ones((size, size), np.int64)
    bar = np.zeros((size, size, 3))
    P = np.empty_like(uv)
    P[..., 0] = uv[..., 0] * size - 0.5
    P[..., 1] = (1.0 - uv[..., 1]) * size - 0.5
    for t in range(len(uv)):
        a, b, c = P[t]
        x0, y0 = np.floor(np.minimum(np.minimum(a, b), c)).astype(int)
        x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        v0, v1 = b - a, c - a
        den = v0[0] * v1[1] - v1[0] * v0[1]
        if abs(den) < 1e-12:
            continue
        px, py = xs - a[0], ys - a[1]
        l1 = (px * v1[1] - v1[0] * py) / den
        l2 = (v0[0] * py - px * v0[1]) / den
        l0 = 1.0 - l1 - l2
        inside = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
        tri[ys[inside], xs[inside]] = t
        bar[ys[inside], xs[inside]] = np.stack([l0[inside], l1[inside], l2[inside]], axis=-1)
    # conservative: a texel no triangle's centre test took, within CONSERVATIVE_PX of a triangle, takes the triangle's
    # nearest point (a sliver thinner than a texel still owns the texels it crosses: no neighbour's band there)
    exact = tri >= 0
    best = np.full((size, size), np.inf)
    for t in range(len(uv)):
        a, b, c = P[t]
        x0, y0 = np.floor(np.minimum(np.minimum(a, b), c) - CONSERVATIVE_PX).astype(int)
        x1, y1 = np.ceil(np.maximum(np.maximum(a, b), c) + CONSERVATIVE_PX).astype(int)
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        free = ~exact[ys, xs]
        if not free.any():
            continue
        q = np.stack([xs[free], ys[free]], axis=-1).astype(np.float64)
        d, w = _closest_on_triangle(q, a, b, c)
        take = d < np.minimum(CONSERVATIVE_PX, best[ys[free], xs[free]])
        yy, xx = ys[free][take], xs[free][take]
        tri[yy, xx] = t
        bar[yy, xx] = w[take]
        best[yy, xx] = d[take]
    return tri, bar


def _closest_on_triangle(q, a, b, c):
    """(distance, barycentrics) of each 2D point's nearest point on triangle abc (its edges when outside)."""
    best_d = np.full(len(q), np.inf)
    best_w = np.zeros((len(q), 3))
    for (p0, i0), (p1, i1) in (((a, 0), (b, 1)), ((b, 1), (c, 2)), ((c, 2), (a, 0))):
        e = p1 - p0
        ee = float(e @ e)
        s = np.clip(((q - p0) @ e) / ee, 0.0, 1.0) if ee > 1e-12 else np.zeros(len(q))
        pt = p0 + s[:, None] * e
        d = np.linalg.norm(q - pt, axis=1)
        w = np.zeros((len(q), 3))
        w[:, i0] = 1.0 - s
        w[:, i1] += s
        m = d < best_d
        best_d[m] = d[m]
        best_w[m] = w[m]
    return best_d, best_w


def dilate(img, filled):
    """Every empty texel takes its nearest filled texel's value (mip bleeding off the islands)."""
    from scipy import ndimage
    if filled.all():
        return img
    _d, (iy, ix) = ndimage.distance_transform_edt(~filled, return_indices=True)
    return img[iy, ix]


def hemisphere(n):
    """BAKE_RAYS fixed directions, cosine-weighted about +Z (a Fibonacci spiral)."""
    k = np.arange(n) + 0.5
    r = np.sqrt(k / n)
    th = k * math.pi * (3.0 - math.sqrt(5.0))
    return np.stack([r * np.cos(th), r * np.sin(th), np.sqrt(1.0 - r * r)], axis=-1)


def vertex_ao(V, Nrm, occluder_V, occluder_T):
    """Per vertex: the share of BAKE_RAYS cosine rays that leave unoccluded within AO_REACH_M (a hit near counts
    whole, at the reach nothing)."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([tuple(map(float, v)) for v in occluder_V],
                                [tuple(map(int, t)) for t in occluder_T], all_triangles=True)
    H = hemisphere(BAKE_RAYS)
    reach = AO_REACH_M / pr.EXPORT_SCALE
    out = np.ones(len(V))
    for i in range(len(V)):
        n = Nrm[i]
        a = np.array([1.0, 0.0, 0.0]) if abs(n[0]) < 0.9 else np.array([0.0, 1.0, 0.0])
        t = np.cross(n, a)
        t /= np.linalg.norm(t)
        b = np.cross(n, t)
        dirs = H[:, 0:1] * t + H[:, 1:2] * b + H[:, 2:3] * n
        o = Vector((V[i] + n * 2e-3).tolist())
        occ = 0.0
        for d in dirs:
            hit = tree.ray_cast(o, Vector(d.tolist()), reach)
            if hit[0] is not None:
                occ += 1.0 - hit[3] / reach
        out[i] = 1.0 - occ / BAKE_RAYS
    return out


def vertex_normals(V, T):
    n = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    out = np.zeros_like(V)
    for k in range(3):
        np.add.at(out, T[:, k], n)
    return out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-12)


def srgb(c):
    return np.asarray(c, np.float64)


def material_albedo(name, P, masks):
    """Albedo (n, 3) in 0..1 (sRGB) of texels of one material at rest points P (human m)."""
    spec = pr.MATERIALS[name]
    base = srgb(spec["albedo"])[None, :].repeat(len(P), 0)
    if name in ("skin", "lips"):
        mott = fbm(P, 9.0, 11) - 0.5
        out = base * (1.0 + 0.07 * mott[:, None])
        out *= (1.0 - 0.45 * masks["brow"])[:, None]
        out = out * (1.0 - masks["nails"][:, None] * 0.0) + masks["nails"][:, None] * 0.06
        return out
    if name in ("cloth", "faction"):
        mott = fbm(P, 14.0, 21)
        fine = vnoise(P, 160.0, 23)
        return base * (0.86 + 0.12 * mott + 0.05 * (fine - 0.5))[:, None]
    if name in ("leather", "dark_leather"):
        mott = fbm(P, 11.0, 31)
        return base * (0.78 + 0.3 * mott)[:, None]
    if name in ("metal", "mail"):
        mott = fbm(P, 18.0, 41)
        rings = vnoise(P, 220.0, 43) if name == "mail" else 0.5
        return base * (0.8 + 0.28 * mott + (0.18 * (rings - 0.5) if name == "mail" else 0.0))[:, None]
    if name == "fur":
        mott = fbm(P * [1.0, 1.0, 0.25], 60.0, 51)
        return base * (0.7 + 0.5 * mott)[:, None]
    return base


def _segment_dist2(Q, a, b):
    """Distance of 2-d points Q to the segment a-b."""
    ab = b - a
    t = np.clip(((Q - a) @ ab) / max(float(ab @ ab), 1e-12), 0.0, 1.0)
    return np.linalg.norm(Q - (a + t[:, None] * ab), axis=1)


def age_lines(P, N, masks, L, strength):
    """The age's darkening (n,) of skin texels at rest points P (human m) facing N, from the first variant's face
    landmarks ``L`` (giant_body.derived_masks: the eyes, the lips, the chin, the head's size ``hs``) and its masks
    (forehead, crow, undereye) interpolated at the texels."""
    hs = float(L["hs"])
    x, z = P[:, 0], P[:, 2]
    front = np.clip((-N[:, 1] - 0.2) / 0.4, 0.0, 1.0)
    w = 0.0013 * hs                                  # a crease's half width
    out = np.zeros(len(P))
    # the forehead: three lines, curving up toward the temples, fading at the ends
    for k, dz in enumerate((0.024, 0.036, 0.048)):
        zl = L["brow_z"] + dz * hs + 0.004 * hs * (x / (0.05 * hs)) ** 2
        g = np.exp(-0.5 * ((z - zl) / w) ** 2) * (1.0 - np.clip(np.abs(x) / (0.055 * hs), 0.0, 1.0)) ** 0.5
        out = np.maximum(out, g * strength["forehead"] * (1.0 - 0.15 * k) * masks["forehead"])
    # the crow's feet: three short lines fanning from each eye's outer corner
    for side in ("L", "R"):
        c = np.asarray(L["canthus_" + side])
        sg = 1.0 if side == "L" else -1.0
        dx, dz = (x - c[0]) * sg, z - c[2]
        r = np.hypot(dx, dz)
        ang = np.arctan2(dz, np.maximum(dx, 1e-6))
        rad = (r > 0.004 * hs) & (r < 0.02 * hs) & (dx > 0.0)
        for a in (-0.45, 0.0, 0.4):
            g = np.exp(-0.5 * ((ang - a) * r / w) ** 2) * rad * (1.0 - r / (0.02 * hs))
            out = np.maximum(out, g * strength["crow"] * np.clip(masks["crow"] * 2.0, 0.0, 1.0))
    # the folds from the nose's wings past the mouth's corners, and from the corners down
    mid = 0.5 * (L["lip_top"] + L["lip_bot"])
    for sg in (1.0, -1.0):
        Q = np.stack([x, z], axis=1)
        a = np.array([sg * 0.017 * hs, L["subnasale"] + 0.004 * hs])
        b = np.array([sg * 0.029 * hs, mid - 0.012 * hs])
        g = np.exp(-0.5 * (_segment_dist2(Q, a, b) / (1.3 * w)) ** 2)
        out = np.maximum(out, g * strength["fold"] * front)
        a2 = np.array([sg * 0.025 * hs, L["lip_bot"] - 0.002 * hs])
        b2 = np.array([sg * 0.022 * hs, L["chin"] + 0.016 * hs])
        g2 = np.exp(-0.5 * (_segment_dist2(Q, a2, b2) / w) ** 2)
        out = np.maximum(out, g2 * strength["marionette"] * front)
    out = np.maximum(out, strength["bags"] * np.clip(masks["undereye"] * 1.5, 0.0, 1.0))
    return out


def material_rough(name, P):
    r = pr.MATERIALS[name]["rough"]
    return np.clip(r + 0.08 * (fbm(P, 20.0, 61) - 0.5), 0.05, 1.0)


def tile_pixels(size):
    """{tile: (rows, cols, u, v)} of each tile's texels (u, v in 0..1 inside the tile)."""
    out = {}
    for name, (u0, v0) in pr.TILES.items():
        x0 = int(round(u0 * size))
        x1 = int(round((u0 + pr.TILE_SIZE) * size))
        y0 = int(round((1.0 - v0 - pr.TILE_SIZE) * size))
        y1 = int(round((1.0 - v0) * size))
        ys, xs = np.mgrid[y0:y1, x0:x1]
        u = (xs - x0 + 0.5) / (x1 - x0)
        v = 1.0 - (ys - y0 + 0.5) / (y1 - y0)
        out[name] = (ys, xs, u, v)
    return out


def mail_height(u, v):
    """The mail tile's height field (0 the gaps, 1 the tops of the wires) at tile coordinates in [0, 1): a grid of
    MAIL_TILE_RINGS x MAIL_TILE_RINGS round rings, every other row offset half a ring and each ring overlapping its
    neighbours (riveted mail seen flat); it tiles."""
    n = pr.MAIL_TILE_RINGS
    R, w = 0.40 / n, 0.12 / n
    h = np.zeros(np.shape(u))
    for j in range(-1, n + 1):
        for i in range(-1, n + 1):
            cx, cy = (i + 0.5 + 0.5 * (j % 2)) / n, (j + 0.5) / n
            d = np.hypot(u - cx, v - cy)
            ring = np.sqrt(np.clip(w * w - (d - R) ** 2, 0.0, None)) / w
            h = np.maximum(h, ring * (0.85 + 0.15 * ((i + j) % 2)))
    return h


def tile_albedo(name, u, v):
    mat = pr.TILE_MATERIAL[name]
    base = srgb(pr.MATERIALS[mat]["albedo"])
    P = np.stack([u.ravel(), v.ravel(), np.zeros(u.size)], axis=-1)
    if name == "mail":
        h = mail_height(u.ravel(), v.ravel())
        val = 0.28 + 0.95 * h ** 0.7
        return (base[None, :] * val[:, None]).reshape(u.shape + (3,))
    if name == "hair":
        streak = vnoise(np.stack([u.ravel() * 40.0, v.ravel() * 2.0, np.zeros(u.size)], -1), 1.0, 71)
        fine = vnoise(np.stack([u.ravel() * 140.0, v.ravel() * 4.0, np.zeros(u.size)], -1), 1.0, 73)
        val = 0.62 + 0.28 * streak + 0.14 * (fine - 0.5)
    elif name == "eye":
        # the eyeball's polar map (eye_uv): the gaze at the tile's centre, the angle from it outward; a pupil, an
        # iris with a darker limbal ring and lighter flecks, the white shaded toward the corners
        d = np.hypot(u.ravel() - 0.5, v.ravel() - 0.5) / EYE_UV_R          # the angle from the gaze, in degrees
        ang = np.degrees(np.arctan2(v.ravel() - 0.5, u.ravel() - 0.5))
        fleck = vnoise(np.stack([np.cos(np.radians(ang)) * 6.0, np.sin(np.radians(ang)) * 6.0, d * 0.4], -1), 1.0, 91)
        iris_c = np.array([0.36, 0.25, 0.15]) * (0.8 + 0.5 * fleck)[:, None]
        iris_c = iris_c * (1.0 - 0.55 * sstep_np(d, 22.0, 29.0))[:, None]
        white = base[None, :] * (1.0 - 0.18 * sstep_np(d, 40.0, 100.0))[:, None]
        col = np.where((d < 29.0)[:, None], iris_c, white)
        col = np.where((d < 11.0)[:, None], np.array([0.02, 0.02, 0.02]), col)
        return col.reshape(u.shape + (3,))
    elif name in ("metal",):
        val = 0.8 + 0.3 * fbm(P * 3.0, 6.0, 81)
    elif name in ("leather", "fur"):
        val = 0.78 + 0.3 * fbm(P * 3.0, 5.0, 83)
    else:
        val = 0.86 + 0.12 * fbm(P * 3.0, 8.0, 85) + 0.05 * (vnoise(P, 90.0, 87) - 0.5)
    return (base[None, :] * val[:, None]).reshape(u.shape + (3,))


def sstep_np(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


EYE_UV_R = 0.42 / 120.0           # tile units a degree from the gaze (people_outfit.eye_uv)


def tile_normal(name, u, v):
    if name == "mail":
        # the rings' relief: (-dh/du, -dh/dv, 1) in the island's frame, green down the texture (the bake's frame)
        e = 0.5 / 64.0
        k = 0.012 * pr.MAIL_TILE_RINGS
        du = (mail_height(u + e, v) - mail_height(u - e, v)) / (2 * e) * k
        dv = (mail_height(u, v + e) - mail_height(u, v - e)) / (2 * e) * k
        n = np.stack([-du, dv, np.ones_like(du)], axis=-1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        return n * 0.5 + 0.5
    if name != "hair":
        return np.tile(np.array([0.5, 0.5, 1.0]), u.shape + (1,))
    e = 1.0 / 128.0
    f = lambda uu: vnoise(np.stack([uu.ravel() * 40.0, v.ravel() * 2.0, np.zeros(uu.size)], -1), 1.0, 71)  # noqa: E731
    dx = (f(u + e) - f(u - e)).reshape(u.shape) / (2 * e) * 0.004
    n = np.stack([-dx, np.zeros_like(dx), np.ones_like(dx)], axis=-1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return n * 0.5 + 0.5


def to_u8(x):
    return np.clip(np.round(np.asarray(x) * 255.0), 0, 255).astype(np.uint8)


def save_png(path, arr):
    Image.fromarray(arr).save(path, format="PNG", optimize=False, compress_level=9)


def _nearest_on(V, T, P, Nrm, reach):
    """(triangle index into T, barycentrics (n, 3)) of each point's nearest point on the mesh (V, T) (Blender's BVH)
    among the triangles facing the point's own way (``Nrm``; a lip's texel never reads the inside of the mouth, nor
    a garment's the skin under it), within ``reach`` of its nearest point at all."""
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree
    tree = BVHTree.FromPolygons([tuple(map(float, v)) for v in V], [tuple(map(int, t)) for t in T], all_triangles=True)
    fn = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    tri = np.zeros(len(P), np.int64)
    loc = np.zeros((len(P), 3))
    for i, p in enumerate(P):
        co = Vector((float(p[0]), float(p[1]), float(p[2])))
        hit = tree.find_nearest(co)
        tri[i] = hit[2]
        loc[i] = hit[0]
        if float(fn[hit[2]] @ Nrm[i]) < 0.25:
            best = None
            for h in tree.find_nearest_range(co, float(hit[3]) + reach):
                if float(fn[h[2]] @ Nrm[i]) >= 0.25 and (best is None or h[3] < best[3]):
                    best = h
            if best is not None:
                tri[i] = best[2]
                loc[i] = best[0]
    A, B, C = (V[T[tri, k]] for k in range(3))
    v0, v1, v2 = B - A, C - A, loc - A
    d00, d01, d11 = (v0 * v0).sum(-1), (v0 * v1).sum(-1), (v1 * v1).sum(-1)
    d20, d21 = (v2 * v0).sum(-1), (v2 * v1).sum(-1)
    den = np.where(np.abs(d00 * d11 - d01 * d01) < 1e-20, 1e-20, d00 * d11 - d01 * d01)
    b1 = (d11 * d20 - d01 * d21) / den
    b2 = (d00 * d21 - d01 * d20) / den
    bar = np.clip(np.stack([1.0 - b1 - b2, b1, b2], axis=-1), 0.0, 1.0)
    return tri, bar / np.maximum(bar.sum(axis=1, keepdims=True), 1e-12)


def bake_role(role, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, person, mats, ao_from=None, extra_meshes=(),
              face_rect=None):
    """Writes <role>_albedo.png, <role>_normal.png and <role>_orm.png into out_dir; returns their facts.

    P59b: each texel reads the high mesh at its nearest point on the high mesh's triangles of the texel's own
    material (the vertex normals, the occlusion and the masks interpolated across that triangle: P59 took the
    inverse-distance mean of the nearest vertices, which drew the low mesh's facets back in), and the normal map's
    green channel runs down the texture (the frame Godot reads a glTF's tangents in: P59's ran up, which turned
    every correction the wrong way and doubled the facets).

    P65a: ``face_rect`` (u0, v0, u1, v1; the atlas's head region): the skin's texels there keep the low mesh's own
    normal (a flat texel). The map is the first variant's, and every variant's face differs, so its face read on
    another variant's (a woman's on a men's role) as soft smudges on the cheeks and round the mouth; each variant's
    face is then shaded by its own vertex normals."""
    S = person.S
    masks = person.bd.masks
    sN = vertex_normals(src.V, src.T)
    body = np.arange(len(src.V)) < src.n_body
    sm = {"brow": np.zeros(len(src.V)), "nails": np.zeros(len(src.V))}
    sm["brow"][body] = masks["m_brow"][src.attach[body]]
    sm["nails"][body] = masks["m_nails"][src.attach[body]]
    aged = AGE_LINES.get(role)
    if aged:
        for k in ("forehead", "crow", "undereye"):
            sm[k] = np.zeros(len(src.V))
            sm[k][body] = masks["m_" + k][src.attach[body]]
    groups = {}
    for i, m in enumerate(mats):
        key = "skin" if m in ("skin", "lips") else m
        groups.setdefault(key, []).append(i)
    # the expensive pass: per src vertex AO (unless read back)
    ao_v = None
    if ao_from is None:
        occ = [src]             # (P59b: not the first variant's own pieces: its helm darkened every variant's brow)
        OV = np.concatenate([p.V for p in occ])
        off = np.cumsum([0] + [len(p.V) for p in occ])[:-1]
        OT = np.concatenate([p.T + o for p, o in zip(occ, off)])
        ao_v = vertex_ao(src.V, sN, OV, OT)
    out = {}
    tile_mask = {}
    for size in sorted({pr.ALBEDO_PX, pr.NORMAL_PX, pr.ORM_PX}):
        tri, bar = raster(Luv, size)
        filled = tri >= 0
        ys, xs = np.nonzero(filled)
        t = tri[ys, xs]
        b = bar[ys, xs]
        P = np.einsum("nk,nkj->nj", b, LV[LT[t]])
        Nl = np.einsum("nk,nkj->nj", b, nor[t])
        Nl /= np.maximum(np.linalg.norm(Nl, axis=1, keepdims=True), 1e-12)
        Tl = np.einsum("nk,nkj->nj", b, tan[t])
        Tl = Tl - Nl * np.einsum("ij,ij->i", Tl, Nl)[:, None]
        Tl /= np.maximum(np.linalg.norm(Tl, axis=1, keepdims=True), 1e-12)
        Bl = np.cross(Nl, Tl) * np.sign(sgn[t, 0])[:, None]
        mat_t = Lmat[t]
        hiN = Nl.copy()
        ao = np.ones(len(P))
        alb = np.zeros_like(P)
        rough = np.zeros(len(P))
        band = np.zeros(len(P), np.uint8)
        Ph = P / S
        for key, ids in groups.items():
            sel = np.nonzero(np.isin(mat_t, ids))[0]
            stri = np.nonzero(np.isin(src.mat, ids))[0]
            if not len(sel) or not len(stri):
                continue
            k, w = _nearest_on(src.V, src.T[stri], P[sel], Nl[sel], FACING_REACH_M / pr.EXPORT_SCALE)
            corners = src.T[stri[k]]                                    # (n, 3) src vertex ids
            n = np.einsum("nk,nkj->nj", w, sN[corners])
            hiN[sel] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            if ao_v is not None:
                ao[sel] = np.einsum("nk,nk->n", w, ao_v[corners])
            mk = {name: np.einsum("nk,nk->n", w, v[corners]) for name, v in sm.items()}
            for mi in ids:
                s2 = np.nonzero(mat_t[sel] == mi)[0]
                if not len(s2):
                    continue
                alb[sel[s2]] = material_albedo(mats[mi], Ph[sel[s2]], {name: v[s2] for name, v in mk.items()})
                if aged and mats[mi] in ("skin", "lips"):
                    dark = age_lines(Ph[sel[s2]], hiN[sel[s2]], {name: v[s2] for name, v in mk.items()},
                                     person.bd.landmarks, aged)
                    alb[sel[s2]] *= (1.0 - dark)[:, None]
                rough[sel[s2]] = material_rough(mats[mi], Ph[sel[s2]])
                band[sel[s2]] = pr.band_byte(pr.MATERIALS[mats[mi]]["band"])
        if face_rect is not None:
            uvt = np.einsum("nk,nkj->nj", b, Luv[t])
            skin_ids = [i for i, m in enumerate(mats) if m in ("skin", "lips")]
            flat = np.isin(mat_t, skin_ids) & (uvt[:, 0] > face_rect[0]) & (uvt[:, 1] > face_rect[1]) \
                & (uvt[:, 0] < face_rect[2]) & (uvt[:, 1] < face_rect[3])
            hiN[flat] = Nl[flat]
        if os.environ.get("PEOPLE_DEBUG_NORMAL") == "up":
            hiN = np.tile([0.0, 0.0, 1.0], (len(hiN), 1)) * 0.9 + Nl * 0.1
        ts = np.stack([np.einsum("ij,ij->i", hiN, Tl), np.einsum("ij,ij->i", hiN, Bl),
                       np.einsum("ij,ij->i", hiN, Nl)], axis=-1)
        ts[:, 2] = np.maximum(ts[:, 2], 0.05)
        ts /= np.linalg.norm(ts, axis=1, keepdims=True)
        img = {"albedo": np.zeros((size, size, 3)), "normal": np.tile([0.5, 0.5, 1.0], (size, size, 1)),
               "orm": np.zeros((size, size, 3))}
        img["albedo"][ys, xs] = alb
        img["normal"][ys, xs] = ts * 0.5 + 0.5
        img["orm"][ys, xs, 0] = np.clip(ao, AO_FLOOR, 1.0)
        img["orm"][ys, xs, 1] = rough
        img["orm"][ys, xs, 2] = band / 255.0
        tp = tile_pixels(size)
        done = filled.copy()
        for name, (ty, tx, u, v) in tp.items():
            mat = pr.TILE_MATERIAL[name]
            img["albedo"][ty, tx] = tile_albedo(name, u, v)
            img["normal"][ty, tx] = tile_normal(name, u, v)
            img["orm"][ty, tx, 0] = 1.0
            img["orm"][ty, tx, 1] = pr.MATERIALS[mat]["rough"]
            img["orm"][ty, tx, 2] = pr.band_byte(pr.MATERIALS[mat]["band"]) / 255.0
            done[ty, tx] = True
        for k in img:
            img[k] = dilate(img[k], done)
        out[size] = img
        tile_mask[size] = float(filled.mean())
    alb = to_u8(out[pr.ALBEDO_PX]["albedo"])
    nrm = to_u8(out[pr.NORMAL_PX]["normal"])
    orm = to_u8(out[pr.ORM_PX]["orm"])
    if ao_from is not None:
        old = np.asarray(Image.open(ao_from).convert("RGB"))
        if old.shape != orm.shape:
            raise SystemExit("people bake: %s is not a %d px map" % (ao_from, pr.ORM_PX))
        orm[..., 0] = old[..., 0]
    paths = {}
    for kind, arr in (("albedo", alb), ("normal", nrm), ("orm", orm)):
        p = os.path.join(out_dir, "%s_%s.png" % (role, kind))
        save_png(p, arr)
        paths[kind] = os.path.basename(p)
    bands = {pr.decode_band(int(b)): int(c) for b, c in zip(*np.unique(orm[..., 2], return_counts=True))}
    return {"files": paths, "sizes": {"albedo": pr.ALBEDO_PX, "normal": pr.NORMAL_PX, "orm": pr.ORM_PX},
            "coverage": {str(k): round(v, 4) for k, v in tile_mask.items()}, "band_texels": bands,
            "rays": BAKE_RAYS}
