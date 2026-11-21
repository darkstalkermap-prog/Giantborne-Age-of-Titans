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
LOOKUP_K = 8


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


def tile_albedo(name, u, v):
    mat = pr.TILE_MATERIAL[name]
    base = srgb(pr.MATERIALS[mat]["albedo"])
    P = np.stack([u.ravel(), v.ravel(), np.zeros(u.size)], axis=-1)
    if name == "hair":
        streak = vnoise(np.stack([u.ravel() * 40.0, v.ravel() * 2.0, np.zeros(u.size)], -1), 1.0, 71)
        fine = vnoise(np.stack([u.ravel() * 140.0, v.ravel() * 4.0, np.zeros(u.size)], -1), 1.0, 73)
        val = 0.62 + 0.28 * streak + 0.14 * (fine - 0.5)
    elif name == "eye":
        d = np.hypot((u.ravel() - 0.5) * 1.0, (v.ravel() - 0.95) * 1.4)
        iris = d < 0.2
        pupil = d < 0.08
        col = np.where(iris[:, None], [0.30, 0.20, 0.12], base)
        col = np.where(pupil[:, None], [0.03, 0.03, 0.03], col)
        return col.reshape(u.shape + (3,))
    elif name in ("metal",):
        val = 0.8 + 0.3 * fbm(P * 3.0, 6.0, 81)
    elif name in ("leather", "fur"):
        val = 0.78 + 0.3 * fbm(P * 3.0, 5.0, 83)
    else:
        val = 0.86 + 0.12 * fbm(P * 3.0, 8.0, 85) + 0.05 * (vnoise(P, 90.0, 87) - 0.5)
    return (base[None, :] * val[:, None]).reshape(u.shape + (3,))


def tile_normal(name, u, v):
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


def bake_role(role, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, person, mats, ao_from=None, extra_meshes=()):
    """Writes <role>_albedo.png, <role>_normal.png and <role>_orm.png into out_dir; returns their facts."""
    from scipy.spatial import cKDTree
    S = person.S
    masks = person.bd.masks
    # per src vertex: its material (by its faces), its normal, its masks
    smat = np.full(len(src.V), -1, np.int64)
    for k in range(3):
        smat[src.T[:, k]] = src.mat
    sN = vertex_normals(src.V, src.T)
    body = np.arange(len(src.V)) < src.n_body
    sm = {"brow": np.zeros(len(src.V)), "nails": np.zeros(len(src.V))}
    sm["brow"][body] = masks["m_brow"][src.attach[body]]
    sm["nails"][body] = masks["m_nails"][src.attach[body]]
    groups = {}
    for i, m in enumerate(mats):
        key = "skin" if m in ("skin", "lips") else m
        groups.setdefault(key, []).append(i)
    trees = {}
    for key, ids in groups.items():
        sel = np.nonzero(np.isin(smat, ids))[0]
        if len(sel):
            trees[key] = (cKDTree(src.V[sel]), sel)
    # the expensive pass: per src vertex AO (unless read back)
    ao_v = None
    if ao_from is None:
        occ = [src] + list(extra_meshes)
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
        hiN = np.zeros_like(P)
        ao = np.ones(len(P))
        alb = np.zeros_like(P)
        rough = np.zeros(len(P))
        band = np.zeros(len(P), np.uint8)
        Ph = P / S
        for key, ids in groups.items():
            sel = np.nonzero(np.isin(mat_t, ids))[0]
            if not len(sel) or key not in trees:
                continue
            tree, sv = trees[key]
            d, j = tree.query(P[sel], k=LOOKUP_K)
            vi = sv[j]
            # the nearest vertices facing the texel's own way (a garment's inner side faces the skin)
            agree = np.clip(np.einsum("nkj,nj->nk", sN[vi], Nl[sel]), 0.0, 1.0) ** 2
            wgt = agree / np.maximum(d, 1e-5) ** 2
            none = wgt.sum(axis=1) <= 1e-12
            wgt[none] = 1.0 / np.maximum(d[none], 1e-5) ** 2
            wgt /= wgt.sum(axis=1, keepdims=True)
            n = np.einsum("nk,nkj->nj", wgt, sN[vi])
            hiN[sel] = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
            hiN[sel[none]] = Nl[sel[none]]
            if ao_v is not None:
                ao[sel] = np.einsum("nk,nk->n", wgt, ao_v[vi])
            for mi in ids:
                s2 = sel[mat_t[sel] == mi]
                if not len(s2):
                    continue
                jj = np.searchsorted(sel, s2)
                mk = {k: np.einsum("nk,nk->n", wgt[jj], v[vi[jj]]) for k, v in sm.items()}
                alb[s2] = material_albedo(mats[mi], Ph[s2], mk)
                rough[s2] = material_rough(mats[mi], Ph[s2])
                band[s2] = pr.band_byte(pr.MATERIALS[mats[mi]]["band"])
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
