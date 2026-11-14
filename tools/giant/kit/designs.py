"""The design array (the step --designs): every tattoo, war paint, scar and ancestry mark of the
floor catalogue (plan §2.3), drawn as distance fields in 3D on the rest pose and packed into the
512 x 512 RGBA layers of ``designs.png`` (stacked vertically; imported as a 2D texture array).

Every texel's rest position and normal come from the bake (restpos.npy, restnrm.npy) and its body
region from regions.png, so a design has no UV seams and stays inside its own regions' texels.
Designs are drawn at the bake's 1024 px and box-filtered to 512 px.

The packing rule (plan §2.5, the S3TC compressor ghosts designs that share an area): within one
layer, the texels of any body region carry a design in at most one of R, G and B, plus at most one
in A; designs in different regions may share a channel. The four scars fill one layer of their own
(the shader's ``scar_layer`` and ``scar_on``); the others are placed greedily, the designs that touch
the most regions first.

Reading in play (plan §2.3, decision 18): the pieces the camera sees from behind at stage 1 or in
first person - arm_bands, arm_chevrons, back_wings, back_tree, shoulder_bands, forearm_slash,
knuckles, granite_veins, lightning_tree - are drawn with strokes at least 2.7 cm wide on the
human-scale rest body (4 cm at stage 1, x 1.4947).

Usage: python designs.py <bake dir> <out dir>   (writes designs.png and designs.json)
"""
from __future__ import annotations

import json
import math
import os
import sys

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import numpy as np  # noqa: E402

LAYER_SIZE = 512
AA = 0.0016                     # anti-aliasing ramp (m, human scale; about one 1024 px texel)
BOLD = 0.0135                   # half-width of a stroke that reads in play (2.7 cm wide, 4 cm at stage 1)
KINDS = ("tattoo", "paint", "scar", "mark")
SCAR_ORDER = ("scar_brow", "scar_forearm_slash", "scar_chest_claws", "scar_knuckles")
# design id -> (kind, body regions it may draw in)
CATALOGUE = {
    "tat_arm_bands": ("tattoo", (8,)),
    "tat_arm_chevrons": ("tattoo", (9,)),
    "tat_chest_spiral": ("tattoo", (3,)),
    "tat_chest_knot": ("tattoo", (3, 4)),
    "tat_back_wings": ("tattoo", (5,)),
    "tat_back_tree": ("tattoo", (5, 6)),
    "tat_face_lines": ("tattoo", (1,)),
    "tat_face_dots": ("tattoo", (1,)),
    "paint_face_stripes": ("paint", (1,)),
    "paint_shoulder_bands": ("paint", (8,)),
    "scar_brow": ("scar", (1,)),
    "scar_forearm_slash": ("scar", (9,)),
    "scar_chest_claws": ("scar", (3,)),
    "scar_knuckles": ("scar", (10,)),
    "mark_granite_veins": ("mark", (8, 9)),
    "mark_lightning_tree": ("mark", (5, 6, 8, 9)),
    "mark_claw_stripes": ("mark", (1, 3, 8)),
}


# --------------------------------------------------------------------------------------
# inputs
# --------------------------------------------------------------------------------------
def load_bake(bake_dir):
    """(P (H*W, 3), N (H*W, 3), region (H*W,) int, valid (H*W,) bool, size) of the bake."""
    from PIL import Image
    pos = np.load(os.path.join(bake_dir, "restpos.npy")).astype(np.float64)
    enc = np.load(os.path.join(bake_dir, "restnrm.npy")).astype(np.float64)
    size = pos.shape[0]
    reg = np.asarray(Image.open(os.path.join(bake_dir, "regions.png")).convert("L"), np.float64) / 255.0
    valid = np.linalg.norm(enc, axis=-1) > 0.3          # texels outside the islands stay empty
    nrm = enc * 2.0 - 1.0                                # the bake stores (n + 1) / 2
    region = np.floor(reg * 16.0).astype(np.int64)
    return pos.reshape(-1, 3), nrm.reshape(-1, 3), region.reshape(-1), valid.reshape(-1), size


def body_frame():
    """Joints and landmarks of the rest body (human-scale Blender metres)."""
    import giant_body as gb
    import mh_data as mh
    bd = gb.BodyData()
    bd.compute_masks(mh.load_weights())
    return bd


# --------------------------------------------------------------------------------------
# primitives
# --------------------------------------------------------------------------------------
def band(d, half, aa=AA):
    """1 inside a stroke of half-width ``half`` around the distance ``d``, anti-aliased."""
    return np.clip((half - d) / aa + 0.5, 0.0, 1.0)


def seg_dist(P, A, B):
    """Distance of points P (n, 3) to the segment A-B, and the parameter t along it."""
    AB = B - A
    t = np.clip(((P - A) @ AB) / max(float(AB @ AB), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (A + t[:, None] * AB), axis=1), t


def polyline_mask(P, pts, half, taper=0.0):
    """A stroke along a 3D polyline ``pts`` (k, 3); ``taper`` thins it to (1 - taper) at the end."""
    out = np.zeros(len(P))
    L = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    for i in range(len(pts) - 1):
        d, t = seg_dist(P, pts[i], pts[i + 1])
        s = (L[i] + t * (L[i + 1] - L[i])) / max(L[-1], 1e-9)
        out = np.maximum(out, band(d, half * (1.0 - taper * s)))
    return out


def curve2d_mask(Q, curves, half):
    """Distance of 2D points Q (n, 2) to densely sampled polylines -> an anti-aliased line mask."""
    from scipy.spatial import cKDTree
    pts = np.concatenate([c for c in curves])
    d, _ = cKDTree(pts).query(Q, distance_upper_bound=half * 6)
    d = np.where(np.isfinite(d), d, 1.0)
    return band(d, half)


def limb_frame(P, a, b):
    """Cylinder coordinates about the axis a->b: t along (0 at a, 1 at b), r, theta."""
    ax = b - a
    Lx = np.linalg.norm(ax)
    ax = ax / Lx
    rel = P - a
    t = rel @ ax / Lx
    radial = rel - np.outer(rel @ ax, ax)
    r = np.linalg.norm(radial, axis=1)
    ref = np.cross(ax, [0.0, -1.0, 0.0])
    ref /= np.linalg.norm(ref)
    ref2 = np.cross(ax, ref)
    th = np.arctan2(radial @ ref2, radial @ ref)
    return t, r, th, Lx


def surface_point(V, target, pred=None):
    d = np.linalg.norm(V - target, axis=1)
    if pred is not None:
        d = np.where(pred, d, np.inf)
    return V[int(np.argmin(d))]


# --------------------------------------------------------------------------------------
# the designs (each returns a float mask over the texels; gated by its regions afterwards)
# --------------------------------------------------------------------------------------
def d_arm_bands(P, N, J, ctx):
    out = np.zeros(len(P))
    for s in ("l", "r"):
        sh, el = J[f"joint-{s}-shoulder"], J[f"joint-{s}-elbow"]
        t, r, th, Lx = limb_frame(P, sh, el)
        sel = (r < 0.13) & (t > 0.2) & (t < 0.85)
        # two bold rings and a braid between them
        ring = np.maximum(band(np.abs(t - 0.42) * Lx, BOLD), band(np.abs(t - 0.66) * Lx, BOLD))
        s1 = 0.54 + 0.07 * np.sin(4 * th)
        s2 = 0.54 - 0.07 * np.sin(4 * th)
        braid = np.maximum(band(np.abs(t - s1) * Lx, 0.007), band(np.abs(t - s2) * Lx, 0.007))
        out = np.maximum(out, np.where(sel, np.maximum(ring, braid), 0.0))
    return out


def d_arm_chevrons(P, N, J, ctx):
    out = np.zeros(len(P))
    for s in ("l", "r"):
        el, wr = J[f"joint-{s}-elbow"], J[f"joint-{s}-hand"]
        t, r, th, Lx = limb_frame(P, el, wr)
        sel = (r < 0.1) & (t > 0.26) & (t < 0.74)
        # V-shaped stripes: the V points down the arm on its outer and inner faces
        period = 0.07
        phase = (t * Lx + 0.035 * np.abs(np.sin(th))) / period % 1.0
        m = band(np.abs(phase - 0.5) * period, BOLD * 0.85)
        out = np.maximum(out, np.where(sel, m, 0.0))
    return out


def d_chest_spiral(P, N, J, ctx):
    rsh = J["joint-r-shoulder"]
    c = np.array([rsh[0] * 0.55, 0.0, rsh[2] - 0.17])
    front = (N[:, 1] < -0.35) & (np.abs(P[:, 0] - c[0]) < 0.12) & (np.abs(P[:, 2] - c[2]) < 0.12) \
        & (P[:, 1] < J["joint-spine-1"][1])
    uv = np.stack([P[:, 0] - c[0], P[:, 2] - c[2]], axis=1)
    curves = []
    R0 = 0.032
    for k in range(3):
        a0 = 2 * math.pi * k / 3 + math.pi / 2
        cc = np.array([math.cos(a0), math.sin(a0)]) * R0
        tt = np.linspace(0.0, 2.6 * math.pi, 600)
        rho = 0.0045 * tt
        ang = tt + a0 + math.pi
        curves.append(cc + np.stack([rho * np.cos(ang), rho * np.sin(ang)], axis=1))
        a1 = a0 + 2 * math.pi / 3
        tt = np.linspace(0, 1, 200)
        arc_c = (cc + np.array([math.cos(a1), math.sin(a1)]) * R0) * 0.5
        p0 = curves[-1][-1]
        p1 = np.array([math.cos(a1), math.sin(a1)]) * R0 * 1.55
        ctrl = arc_c * -0.6
        curves.append(((1 - tt) ** 2)[:, None] * p0 + (2 * (1 - tt) * tt)[:, None] * ctrl + (tt ** 2)[:, None] * p1)
    ring = np.linspace(0, 2 * math.pi, 900)
    curves.append(np.stack([np.cos(ring), np.sin(ring)], axis=1) * R0 * 2.25)
    return np.where(front, curve2d_mask(uv, curves, 0.005), 0.0)


def d_chest_knot(P, N, J, ctx):
    """A shield knot on the sternum: four interlaced loops in a ring."""
    sp1 = J["joint-spine-1"]
    c = np.array([0.0, 0.0, sp1[2] - 0.07])
    front = (N[:, 1] < -0.3) & (np.abs(P[:, 0]) < 0.14) & (np.abs(P[:, 2] - c[2]) < 0.14) & (P[:, 1] < sp1[1])
    uv = np.stack([P[:, 0] - c[0], P[:, 2] - c[2]], axis=1)
    tt = np.linspace(0, 2 * math.pi, 700)
    curves = [np.stack([np.cos(tt), np.sin(tt)], axis=1) * 0.085]
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        cc = np.array([math.cos(a), math.sin(a)]) * 0.06
        curves.append(cc + np.stack([np.cos(tt), np.sin(tt)], axis=1) * 0.034)
    return np.where(front, curve2d_mask(uv, curves, 0.0055), 0.0)


def _back_plane(P, N, J, zlo, zhi):
    back = (N[:, 1] > 0.25) & (P[:, 2] > zlo) & (P[:, 2] < zhi)
    return back, np.stack([P[:, 0], P[:, 2]], axis=1)


def d_back_wings(P, N, J, ctx):
    """Two spread wings over the shoulder blades: five long feathers a side, fanning from the spine."""
    sp1, sp2 = J["joint-spine-1"], J["joint-spine-2"]
    back, uv = _back_plane(P, N, J, sp2[2] - 0.02, sp1[2] + 0.17)
    curves = []
    root_z = sp1[2] - 0.02
    for side in (1.0, -1.0):
        for k in range(5):
            ang = math.radians(78 - 17 * k)          # from steeply up-and-out to nearly down
            length = 0.22 - 0.02 * abs(k - 1)
            tt = np.linspace(0, 1, 160)[:, None]
            start = np.array([side * 0.03, root_z - 0.025 * k])
            d1 = np.array([side * math.cos(ang), math.sin(ang)])
            bend = np.array([side * 0.04, -0.06])
            pts = start + d1 * length * tt + bend * (tt ** 2)
            curves.append(pts)
    return np.where(back, curve2d_mask(uv, curves, BOLD), 0.0)


def d_back_tree(P, N, J, ctx):
    """A tree up the spine: the trunk from the lower back, branches over the shoulder blades, roots."""
    sp4, sp1 = J["joint-spine-4"], J["joint-spine-1"]
    back, uv = _back_plane(P, N, J, sp4[2] - 0.05, sp1[2] + 0.2)
    rng = np.random.default_rng(17)
    curves = [np.stack([np.zeros(200), np.linspace(sp4[2] + 0.02, sp1[2] + 0.05, 200)], axis=1)]
    trunk_mask = curve2d_mask(uv, curves, BOLD * 1.25)
    branches = []
    for side in (1.0, -1.0):
        for k, z0 in enumerate((sp1[2] - 0.12, sp1[2] - 0.05, sp1[2] + 0.02)):
            tt = np.linspace(0, 1, 120)[:, None]
            ang = math.radians(25 + 15 * k + rng.uniform(-4, 4))
            d1 = np.array([side * math.cos(ang), math.sin(ang)])
            branches.append(np.array([0.0, z0]) + d1 * (0.15 - 0.02 * k) * tt + np.array([0.0, 0.03]) * tt ** 2)
        for z0 in (sp4[2] + 0.03,):
            tt = np.linspace(0, 1, 100)[:, None]
            branches.append(np.array([0.0, z0]) + np.array([side * 0.09, -0.05]) * tt)
    m = np.maximum(trunk_mask, curve2d_mask(uv, branches, BOLD * 0.75))
    return np.where(back, m, 0.0)


def _face(P, N, J):
    eyeL = J["joint-l-eye"]
    return (N[:, 1] < -0.2) & (P[:, 1] < eyeL[1] + 0.03)


def d_face_lines(P, N, J, ctx):
    """A line down the forehead and two over each cheekbone."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    hs = ctx["hs"]
    face = _face(P, N, J)
    m = np.where((P[:, 2] > eyeL[2] + 0.03 * hs) & (P[:, 2] < eyeL[2] + 0.075 * hs),
                 band(np.abs(P[:, 0]), 0.003), 0.0)
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        for k in range(2):
            a = e + np.array([sgn * (0.006 + 0.008 * k), -0.03, -0.022 - 0.008 * k]) * 1.0
            b = e + np.array([sgn * (0.036 + 0.008 * k), -0.02, -0.03 - 0.008 * k]) * 1.0
            pa = surface_point(P, a, face)
            pb = surface_point(P, b, face)
            m = np.maximum(m, polyline_mask(P, np.array([pa, pb]), 0.0025))
    return np.where(face, m, 0.0)


def d_face_dots(P, N, J, ctx):
    """Rows of dots over the cheekbones and a row above the brows."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    face = _face(P, N, J)
    m = np.zeros(len(P))
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        for k in range(4):
            c = surface_point(P, e + np.array([sgn * (0.004 + 0.011 * k), -0.03, -0.028 - 0.004 * k]), face)
            m = np.maximum(m, band(np.linalg.norm(P - c, axis=1), 0.0034))
        for k in range(3):
            c = surface_point(P, e + np.array([sgn * (0.012 * k - 0.004), -0.03, 0.036]), face)
            m = np.maximum(m, band(np.linalg.norm(P - c, axis=1), 0.003))
    return np.where(face, m, 0.0)


def d_face_stripes(P, N, J, ctx):
    """The research's war paint: three stripes under each eye and a band across the brow ridge."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    face = (N[:, 1] < -0.2) & (P[:, 1] < eyeL[1] + 0.02) & (P[:, 2] > eyeL[2] - 0.09) & (P[:, 2] < eyeL[2] + 0.05)
    m = np.zeros(len(P))
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        for k, dx in enumerate((-0.011, 0.0, 0.011)):
            x0 = e[0] + sgn * dx
            ztop = e[2] - 0.016
            zbot = e[2] - 0.05 - 0.008 * (1 - abs(k - 1))
            along = np.clip((ztop - P[:, 2]) / (ztop - zbot), 0, 1)
            half = 0.0048 * (1.0 - 0.6 * along)
            d = np.abs(P[:, 0] - (x0 + sgn * 0.004 * along))
            inside = (P[:, 2] < ztop) & (P[:, 2] > zbot)
            m = np.maximum(m, np.where(inside, band(d, half), 0.0))
    brow = band(np.abs(P[:, 2] - (eyeL[2] + 0.004)), 0.0075) * (np.abs(P[:, 0]) < 0.07)
    m = np.maximum(m, brow * 0.95)
    return np.where(face, m, 0.0)


def d_shoulder_bands(P, N, J, ctx):
    """Three broad bands round each shoulder and upper arm."""
    out = np.zeros(len(P))
    for s in ("l", "r"):
        sh, el = J[f"joint-{s}-shoulder"], J[f"joint-{s}-elbow"]
        t, r, th, Lx = limb_frame(P, sh, el)
        sel = (r < 0.15) & (t > -0.05) & (t < 0.5)
        m = np.zeros(len(P))
        for tc in (0.06, 0.2, 0.34):
            m = np.maximum(m, band(np.abs(t - tc) * Lx, BOLD * 1.15))
        out = np.maximum(out, np.where(sel, m, 0.0))
    return out


def _scar(P, segs, widen=1.0, min_half=0.0):
    m = np.zeros(len(P))
    for a, b, w in segs:
        half = max(w * widen, min_half)
        d, t = seg_dist(P, a, b)
        taper = 0.7 + 0.3 * np.sin(np.pi * t)
        m = np.maximum(m, band(d, half * taper))
    return m


def d_scar_brow(P, N, J, ctx):
    return _scar(P, ctx["scars"]["brow"], widen=1.0, min_half=0.0026)


def d_scar_forearm_slash(P, N, J, ctx):
    return _scar(P, ctx["scars"]["forearm_slash"], min_half=BOLD)


def d_scar_chest_claws(P, N, J, ctx):
    return _scar(P, ctx["scars"]["chest_claws"], min_half=0.005)


def d_scar_knuckles(P, N, J, ctx):
    """A slash across the left hand's knuckles (the kit's nick, made bold enough to read)."""
    ks = [J[f"joint-l-finger-{f}-1"] for f in (2, 3, 4, 5)]
    hand = np.linalg.norm(P - np.mean(ks, axis=0), axis=1) < 0.09
    back = N[:, 1] > -0.2
    a = surface_point(P, ks[0] + np.array([0.0, 0.02, 0.012]), hand & back)
    b = surface_point(P, ks[-1] + np.array([0.0, 0.02, -0.012]), hand & back)
    return np.where(hand, _scar(P, [(a, b, 0.0)], min_half=0.0095), 0.0)


def _noise3(P, scale, seed):
    """Deterministic smooth 3D value noise in [0, 1] (trilinear over a hashed lattice)."""
    q = P * scale
    i = np.floor(q).astype(np.int64)
    f = q - i
    f = f * f * (3 - 2 * f)

    def h(ix, iy, iz):
        v = (ix * 73856093) ^ (iy * 19349663) ^ (iz * 83492791) ^ (seed * 2654435761)
        v = (v ^ (v >> 13)) * 1274126177
        return ((v ^ (v >> 16)) & 0xFFFF) / 65535.0

    out = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[:, 0] if dx else 1 - f[:, 0]) * (f[:, 1] if dy else 1 - f[:, 1]) * (f[:, 2] if dz else 1 - f[:, 2])
                out = out + w * h(i[:, 0] + dx, i[:, 1] + dy, i[:, 2] + dz)
    return out


def d_granite_veins(P, N, J, ctx):
    """Stoneblood: branching grey veins over both shoulders and forearms (ridged noise iso-lines)."""
    sel = np.zeros(len(P), bool)
    for s in ("l", "r"):
        sh, el, wr = J[f"joint-{s}-shoulder"], J[f"joint-{s}-elbow"], J[f"joint-{s}-hand"]
        t1, r1, _, _ = limb_frame(P, sh, el)
        t2, r2, _, _ = limb_frame(P, el, wr)
        sel |= (r1 < 0.15) & (t1 > -0.05) & (t1 < 0.42)
        sel |= (r2 < 0.1) & (t2 > 0.25) & (t2 < 0.85)
    n1 = _noise3(P, 9.0, 3)
    n2 = _noise3(P + 0.37, 21.0, 5)
    v = 0.7 * n1 + 0.3 * n2
    # gradient-normalised distance to the 0.5 iso-line, so the vein width stays even
    m = band(np.abs(v - 0.5), 0.045, 0.02)
    return np.where(sel, m, 0.0)


def d_lightning_tree(P, N, J, ctx):
    """Stormborn: a branching bolt from the left shoulder down across the back and along the arm."""
    V = ctx["V"]
    rng = np.random.default_rng(29)
    sh, el, wr = J["joint-l-shoulder"], J["joint-l-elbow"], J["joint-l-hand"]
    sp1, sp3 = J["joint-spine-1"], J["joint-spine-3"]
    back_v = V[:, 1] > 0.02

    def path(a, b, n, jitter, pred):
        pts = []
        for k in range(n + 1):
            t = k / n
            p = a + (b - a) * t
            if 0 < k < n:
                p = p + rng.normal(size=3) * jitter
            pts.append(surface_point(V, p, pred))
        return np.array(pts)

    main = path(np.array([sh[0] * 0.75, sh[1] + 0.12, sh[2] + 0.02]),
                np.array([-0.05, sp3[1] + 0.12, sp3[2]]), 9, 0.018, back_v)
    arm_v = np.linalg.norm(V - 0.5 * (sh + wr), axis=1) < 0.55
    arm = path(sh + np.array([0.05, 0.05, 0.0]), el + 0.6 * (wr - el) + np.array([0.0, 0.05, 0.0]), 10, 0.012,
               arm_v & (V[:, 0] > sh[0] - 0.05))
    m = np.maximum(polyline_mask(P, main, BOLD, taper=0.5), polyline_mask(P, arm, BOLD * 0.9, taper=0.5))
    for src, n_br in ((main, 4), (arm, 3)):
        for k in range(n_br):
            i = 2 + 2 * k
            if i >= len(src) - 1:
                break
            a = src[i]
            dirv = rng.normal(size=3)
            b = a + dirv / np.linalg.norm(dirv) * 0.09
            br = path(a, b, 3, 0.01, back_v | arm_v)
            m = np.maximum(m, polyline_mask(P, br, BOLD * 0.55, taper=0.6))
    return m


def d_claw_stripes(P, N, J, ctx):
    """Wildheart: three parallel claw stripes on the left cheek, across the chest and on the outer
    left upper arm."""
    V = ctx["V"]
    eyeL = J["joint-l-eye"]
    sh, el = J["joint-l-shoulder"], J["joint-l-elbow"]
    sp1 = J["joint-spine-1"]
    face = V[:, 1] < eyeL[1] + 0.02
    chest = (V[:, 1] < sp1[1] - 0.05) & (V[:, 2] > sp1[2] - 0.3) & (V[:, 2] < sh[2])
    outer_arm = V[:, 0] > sh[0] + 0.02
    m = np.zeros(len(P))
    for k in range(3):
        o = np.array([0.0, 0.0, -0.012 * k])
        a = surface_point(V, eyeL + np.array([0.025, -0.02, -0.025]) + o, face)
        b = surface_point(V, eyeL + np.array([0.012, -0.03, -0.07]) + o, face)
        m = np.maximum(m, polyline_mask(P, np.array([a, b]), 0.003, taper=0.5))
        o = np.array([0.0, 0.0, -0.05 * k])
        a = surface_point(V, sh + np.array([-0.06, -0.18, -0.02]) + o, chest)
        b = surface_point(V, sh + np.array([-0.24, -0.2, -0.14]) + o, chest)
        m = np.maximum(m, polyline_mask(P, np.array([a, b]), 0.011, taper=0.5))
        o = el - sh
        a = surface_point(V, sh + o * (0.15 + 0.17 * k) + np.array([0.06, 0.0, 0.03]), outer_arm)
        b = surface_point(V, sh + o * (0.25 + 0.17 * k) + np.array([0.06, 0.0, -0.03]), outer_arm)
        m = np.maximum(m, polyline_mask(P, np.array([a, b]), BOLD, taper=0.5))
    return m


DRAW = {
    "tat_arm_bands": d_arm_bands, "tat_arm_chevrons": d_arm_chevrons, "tat_chest_spiral": d_chest_spiral,
    "tat_chest_knot": d_chest_knot, "tat_back_wings": d_back_wings, "tat_back_tree": d_back_tree,
    "tat_face_lines": d_face_lines, "tat_face_dots": d_face_dots, "paint_face_stripes": d_face_stripes,
    "paint_shoulder_bands": d_shoulder_bands, "scar_brow": d_scar_brow,
    "scar_forearm_slash": d_scar_forearm_slash, "scar_chest_claws": d_scar_chest_claws,
    "scar_knuckles": d_scar_knuckles, "mark_granite_veins": d_granite_veins,
    "mark_lightning_tree": d_lightning_tree, "mark_claw_stripes": d_claw_stripes,
}


def draw_all(P, N, region, valid, bd):
    """{design id: float mask over the texels} with every design restricted to its regions."""
    import giant_skin as gs
    import mh_data as mh
    J = bd.joints
    ctx = {"hs": bd.landmarks["hs"], "scars": gs.scar_segments(bd), "V": bd.verts[: mh.N_BODY_VERTS]}
    out = {}
    for did in sorted(CATALOGUE):
        _kind, regions = CATALOGUE[did]
        m = DRAW[did](P, N, J, ctx)
        gate = valid & np.isin(region, regions)
        out[did] = np.clip(np.where(gate, m, 0.0), 0.0, 1.0)
    return out


# --------------------------------------------------------------------------------------
# packing
# --------------------------------------------------------------------------------------
def pack(designs):
    """Place every design on a layer and channel under the packing rule. ``designs`` is
    {id: (kind, regions)}. Returns {id: (layer, channel)}: the scars first, on a layer of their
    own in SCAR_ORDER; then the others, most regions first, each in the first layer and channel
    where none of its regions already uses that channel, and, for R, G or B, none of its regions
    already has another of R, G and B."""
    placed = {}
    scars = [d for d in SCAR_ORDER if d in designs]
    others = sorted((d for d in designs if d not in scars), key=lambda d: (-len(designs[d][1]), d))
    layers = []   # per layer: {"scar": bool, "used": {channel: set(regions)}}
    if scars:
        if len(scars) > 4:
            raise ValueError("pack: more than four scars need a second scar layer (P46's scar_layer_b)")
        layers.append({"scar": True, "used": {c: set() for c in range(4)}})
        for c, d in enumerate(scars):
            placed[d] = (0, c)
            layers[0]["used"][c] |= set(designs[d][1])
    for d in others:
        regs = set(designs[d][1])
        spot = None
        for li, ly in enumerate(layers):
            if ly["scar"]:
                continue
            for c in range(4):
                if ly["used"][c] & regs:
                    continue
                if c < 3 and any(ly["used"][o] & regs for o in range(3) if o != c):
                    continue
                spot = (li, c)
                break
            if spot:
                break
        if spot is None:
            layers.append({"scar": False, "used": {c: set() for c in range(4)}})
            spot = (len(layers) - 1, 0)
        placed[d] = spot
        layers[spot[0]]["used"][spot[1]] |= regs
    return placed


def check_rule(placed, designs):
    """Problems with a placement under the packing rule (an empty list when it holds)."""
    problems = []
    by_layer = {}
    for d, (li, c) in placed.items():
        by_layer.setdefault(li, []).append((d, c))
    for li, items in sorted(by_layer.items()):
        for i, (d1, c1) in enumerate(items):
            for d2, c2 in items[i + 1:]:
                shared = set(designs[d1][1]) & set(designs[d2][1])
                if not shared:
                    continue
                if c1 == c2:
                    problems.append("layer %d: %s and %s share channel %d in regions %s" % (li, d1, d2, c1, sorted(shared)))
                elif c1 < 3 and c2 < 3:
                    problems.append("layer %d: %s (%d) and %s (%d) are both in R, G or B over regions %s" % (
                        li, d1, c1, d2, c2, sorted(shared)))
    scar_layers = {placed[d][0] for d in placed if designs[d][0] == "scar"}
    for li in scar_layers:
        if any(designs[d][0] != "scar" for d, (l2, _c) in placed.items() if l2 == li):
            problems.append("layer %d holds scars and other designs" % li)
    return problems


# The edges after the downsample: steepened around 0.5 (the stroke's width is kept), then put on the
# S3TC colour block's own levels (0, 1/3, 2/3, 1). The compressor fits a 4 x 4 block's R, G and B to two
# endpoints and two levels between them, so a thin anti-aliased stroke whose block held 0, 0.5 and 1
# came back with 1 at 0.95 and 0.5 at 0.65: up to 0.07 off on average (test_design_array).
EDGE_LO, EDGE_HI = 0.25, 0.75
LEVELS = 3


def downsample(mask, size, out_size=LAYER_SIZE):
    """Box-filter a (size*size,) mask to out_size x out_size, steepen its edges and quantize it."""
    f = size // out_size
    m = mask.reshape(out_size, f, out_size, f).mean(axis=(1, 3))
    t = np.clip((m - EDGE_LO) / (EDGE_HI - EDGE_LO), 0.0, 1.0)
    return np.round(t * t * (3.0 - 2.0 * t) * LEVELS) / LEVELS


def build(bake_dir, out_dir):
    """Draw, pack and write designs.png (512 x 512*layers RGBA) and designs.json."""
    from PIL import Image
    P, N, region, valid, size = load_bake(bake_dir)
    bd = body_frame()
    masks = draw_all(P, N, region, valid, bd)
    placed = pack(CATALOGUE)
    problems = check_rule(placed, CATALOGUE)
    if problems:
        raise ValueError("designs: the packing rule fails: %s" % problems)
    n_layers = 1 + max(li for li, _c in placed.values())
    img = np.zeros((n_layers * LAYER_SIZE, LAYER_SIZE, 4), np.float64)
    stats = {}
    for did in sorted(placed):
        li, c = placed[did]
        small = downsample(masks[did], size)
        rows = slice(li * LAYER_SIZE, (li + 1) * LAYER_SIZE)
        img[rows, :, c] = np.maximum(img[rows, :, c], small)
        kind, regions = CATALOGUE[did]
        stats[did] = {"layer": li, "channel": c, "kind": kind, "regions": list(regions),
                      "texels_512": int((small > 0.5).sum()), "texels_1024": int((masks[did] > 0.5).sum())}
        if stats[did]["texels_512"] == 0:
            raise ValueError("designs: %s draws nothing" % did)
    os.makedirs(out_dir, exist_ok=True)
    out = (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)
    Image.fromarray(out, "RGBA").save(os.path.join(out_dir, "designs.png"), optimize=True)
    info = {"layers": n_layers, "layer_size": LAYER_SIZE, "designs": stats}
    with open(os.path.join(out_dir, "designs.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    return info


if __name__ == "__main__":
    info = build(sys.argv[1], sys.argv[2])
    print(json.dumps(info, indent=1, sort_keys=True))
