"""The design array (the step --designs): every tattoo, war paint, scar and ancestry mark of the
catalogue (plan §2.3: the floor, and the target's additions from the look pass), drawn as distance fields in 3D on the rest pose and packed into the
512 x 512 RGBA layers of ``designs.png`` (stacked vertically; imported as a 2D texture array).

Every texel's rest position and normal come from the bake (restpos.npy, restnrm.npy) and its body
region from regions.png, so a design has no UV seams and stays inside its own regions' texels.
Designs are drawn at the bake's 1024 px and box-filtered to 512 px.

The packing rule (plan §2.5, the S3TC compressor ghosts designs that share an area): within one
layer, the texels of any body region carry a design in at most one of R, G and B, plus at most one
in A; designs in different regions may share a channel. The scars fill layers of their own, four a
layer (the shader's ``scar_layer`` and ``scar_on``, and ``scar_layer_b`` and ``scar_on_b`` for the
fifth and sixth); the others are placed greedily, the designs that touch the most regions first.

Reading in play (plan §2.3, decision 18): the pieces the camera sees from behind at stage 1 or in
first person - arm_bands, arm_chevrons, back_wings, back_tree, shoulder_bands, forearm_slash,
knuckles, granite_veins, lightning_tree - are drawn with strokes at least 2.7 cm wide on the
human-scale rest body (4 cm at stage 1, x 1.4947 on the M10 body). W33frame: the stroke is set from the body's own
stage-1 scale (draw_all: BOLD = BOLD_M10 x M10_SCALE / the body's scale), so it stays 4 cm at stage 1 on any body -
the reproportioned body (W33body) is taller at human scale (x 1.3594 to stage 1) and its fixed 2.7 cm strokes drew
3.7 cm.

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
BOLD_M10 = 0.0135               # half-width of a stroke that reads in play on the M10 body (2.7 cm wide, 4 cm at stage 1)
M10_SCALE = 1.494689            # the M10 body's human scale to stage 1 (3.6576 m over its human height)
STAGE1_HEIGHT_M = 3.6576
BOLD = BOLD_M10                 # draw_all sets it from the body drawn on (4 cm at stage 1)
KINDS = ("tattoo", "paint", "scar", "mark")
SCAR_ORDER = ("scar_brow", "scar_forearm_slash", "scar_chest_claws", "scar_knuckles",
              "scar_cheek", "scar_back_lash",     # four a layer: the fifth and sixth fill a second scar layer
              "scar_lip", "scar_shoulder_bite", "scar_thigh_gash", "scar_ribs")   # P56: in the scar layers' free room
SCARS_PER_LAYER = 4
SCAR_LAYERS = 2                 # the skin shader reads two scar layers (scar_layer, scar_layer_b)
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
    # the target catalogue (P46): two more tattoos a region, two war paints, two scars
    "tat_arm_sleeve": ("tattoo", (8, 9)),
    "tat_arm_winding": ("tattoo", (8, 9)),
    "tat_chest_sun": ("tattoo", (3,)),
    "tat_chest_collar": ("tattoo", (3,)),
    "tat_back_shoulders": ("tattoo", (5, 8)),
    "tat_back_serpent": ("tattoo", (5, 6)),
    "tat_face_crown": ("tattoo", (1,)),
    "tat_face_bars": ("tattoo", (1,)),
    "paint_full_face": ("paint", (1,)),
    "paint_back_hand": ("paint", (5,)),
    "scar_cheek": ("scar", (1,)),
    "scar_back_lash": ("scar", (5, 6)),
    "mark_granite_veins": ("mark", (8, 9)),
    "mark_lightning_tree": ("mark", (5, 6, 8, 9)),
    "mark_claw_stripes": ("mark", (1, 3, 8)),
    # the catalogue II (P56; plan M11 §2.6): four tattoos for the legs (regions 11-13), two more a region elsewhere,
    # four war paints (two for the face, two for the body: a face paint and a body paint never share a region), and
    # four scars
    "tat_leg_bands": ("tattoo", (11,)),
    "tat_leg_serpent": ("tattoo", (11, 12, 13)),
    "tat_leg_runes": ("tattoo", (13,)),
    "tat_leg_claws": ("tattoo", (11,)),
    "tat_arm_runes": ("tattoo", (9,)),
    "tat_arm_spirals": ("tattoo", (8,)),
    "tat_chest_raven": ("tattoo", (3,)),
    "tat_chest_runes": ("tattoo", (3, 4)),
    "tat_back_wheel": ("tattoo", (5,)),
    "tat_back_spine": ("tattoo", (5, 6)),
    "tat_face_temples": ("tattoo", (1,)),
    "tat_face_tears": ("tattoo", (1,)),
    "paint_eye_band": ("paint", (1,)),
    "paint_half_face": ("paint", (1,)),
    "paint_chest_slash": ("paint", (3, 4)),
    "paint_leg_stripes": ("paint", (11, 13)),
    "scar_lip": ("scar", (1,)),
    "scar_shoulder_bite": ("scar", (8,)),
    "scar_thigh_gash": ("scar", (11,)),
    "scar_ribs": ("scar", (4,)),
}
# The war paint's two places (P56; plan M11 §2.5): a face paint draws in the face's region alone, a body paint never
# in it, so the two worn at once never share a region (the skin's region_paint holds one paint a region).
FACE_REGIONS = (1,)


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


def polyline_dist(P, pts):
    """The distance of points P to a 3D polyline ``pts`` (k, 3), and where along it (0-1) the nearest point lies."""
    best = np.full(len(P), np.inf)
    where = np.zeros(len(P))
    L = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(pts, axis=0), axis=1))])
    for i in range(len(pts) - 1):
        d, t = seg_dist(P, pts[i], pts[i + 1])
        s = (L[i] + t * (L[i + 1] - L[i])) / max(L[-1], 1e-9)
        closer = d < best
        best = np.where(closer, d, best)
        where = np.where(closer, s, where)
    return best, where


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


SCAR_FEATHER = 0.5            # the second look lane: a scar's edge eases off over this share of its half-width
SCAR_SPREAD = 1.85            # ... and is drawn this much wider than its line's half-width (its feathered edge and its
#                               pointed ends kept its reading area, the coverage over a half, at least M10's)
SCAR_GRAIN = 0.18             # ... and its healed tissue is uneven: a fine grain this deep (the relief's detail)


def scar_profile(d, half, P, seed=0):
    """A healed scar's coverage at distance ``d`` from its line of half-width ``half`` (the second look lane: it was a
    hard-edged band, a rectangle on the cheek): a feathered edge (SCAR_FEATHER of the half-width), the edge itself
    wandering a little (low noise along the skin) and the tissue grained (SCAR_GRAIN: fine noise the skin shader's
    relief turns into fine ridges)."""
    wander = 0.8 + 0.4 * _noise3(P, 70.0, 31 + seed)
    h = half * wander
    core = h * (1.0 - SCAR_FEATHER)
    x = np.clip((h - d) / np.maximum(h - core, 1e-6), 0.0, 1.0)
    m = x * x * (3.0 - 2.0 * x)
    grain = 1.0 - SCAR_GRAIN * _noise3(P, 250.0, 57 + seed)
    return m * grain


def _scar(P, segs, widen=1.0, min_half=0.0, seed=0):
    """Scars along segments [(A, B, half-width)]: each a spindle, widest in its middle and drawn out to a point at
    both ends (a healed cut), feathered (scar_profile)."""
    m = np.zeros(len(P))
    for k, (a, b, w) in enumerate(segs):
        half = max(w * widen, min_half)
        d, t = seg_dist(P, a, b)
        taper = 0.4 + 0.6 * np.sin(np.pi * t) ** 0.5
        # past an end the distance grows from the end point; the spindle closes there
        m = np.maximum(m, scar_profile(d, half * taper * SCAR_SPREAD, P, seed + k))
    return m


def d_scar_brow(P, N, J, ctx):
    # the second look lane: drawn a third longer either way (the spindle's pointed ends left only a blotch on the brow)
    (a, b, w), = ctx["scars"]["brow"]
    a, b = a + (a - b) * 0.35, b + (b - a) * 0.35
    return _scar(P, [(a, b, w)], widen=1.0, min_half=BOLD * 0.8)      # P51: the 4 cm rule (was 0.0026)


def d_scar_forearm_slash(P, N, J, ctx):
    # the second look lane: longer and broader (it barely read from the arms' framing; feathered, it read less still)
    (a, b, w), = ctx["scars"]["forearm_slash"]
    a, b = a + (a - b) * 0.15, b + (b - a) * 0.15
    return _scar(P, [(a, b, w)], min_half=BOLD * 1.4)


# (gate C) the claws' three strokes CLAW_SPACING apart (human m, centre to centre) across the left breast, from high
# by the breastbone down and out toward the arm: the kit's three (giant_skin.scar_segments) lay 3.2 cm apart, drawn
# at the 4 cm rule they ran together into one pink blob, and they ran down from the shoulder toward the breastbone,
# along a war harness's strap, which hid all of it but a blob at its edge (the rival giant). Across the strap's line,
# apart, they read as three healed claw marks with or without a harness.
CLAW_SPACING = 0.075
CLAW_HALF = 0.8                  # of BOLD: each stroke a little narrower than the rule's, the gaps between them kept


def d_scar_chest_claws(P, N, J, ctx):
    V = ctx["V"]
    sh = J["joint-l-shoulder"]
    chest = (V[:, 1] < sh[1] - 0.02) & (V[:, 2] > sh[2] - 0.40) & (V[:, 0] > 0.0)
    along = np.array([0.15, 0.0, -0.09])                 # down and out (x is his left), across the strap's line
    across = np.array([-0.5, 0.0, -0.87]) * CLAW_SPACING   # each claw lower and further in than the one before
    segs = []
    for k in range(3):
        c = sh + np.array([-0.11, -0.16, -0.10]) + across * (k - 1)
        a = surface_point(V, c - 0.5 * along, chest)
        b = surface_point(V, c + 0.5 * along, chest)
        segs.append((a, b, 0.0032))
    return _scar(P, segs, min_half=BOLD * CLAW_HALF)


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
    # W33frame: the veins are the field's iso-line drawn as a stroke of even width (the distance to it is the
    # field's offset over its gradient, in metres), BOLD wide: a band of the field's value (0.045 of it) drew blobs
    # where the field lay flat and hairlines where it was steep, so how much read hung on where the noise's lattice
    # fell on the body - on the reproportioned body (W33body) a third of M10's in the arms framing
    idx = np.nonzero(sel)[0]
    Q = P[idx]
    v = _vein_field(Q)
    # the iso-line at the field's median over the selected skin (not a fixed 0.5): where the lattice falls on a body
    # skews the field (its median over the arms read 0.42 on the reproportioned body) and a fixed level then crosses
    # it rarely
    level = float(np.median(v))
    h = 0.003
    g2 = np.zeros(len(Q))
    for ax in range(3):
        e = np.zeros(3)
        e[ax] = h
        g2 += ((_vein_field(Q + e) - _vein_field(Q - e)) / (2.0 * h)) ** 2
    d = np.abs(v - level) / np.maximum(np.sqrt(g2), 1e-6)
    out = np.zeros(len(P))
    out[idx] = band(d, BOLD * VEIN_HALF)
    return out


VEIN_HALF = 0.8   # the veins' half-width, of BOLD


def _vein_field(P):
    """The granite veins' field: two octaves of value noise (its 0.5 iso-line is the veins)."""
    return 0.7 * _noise3(P, 9.0, 3) + 0.3 * _noise3(P + 0.37, 21.0, 5)


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


# --------------------------------------------------------------------------------------
# the target catalogue (P46)
# --------------------------------------------------------------------------------------
def d_arm_sleeve(P, N, J, ctx):
    """A full sleeve on the right arm, shoulder to wrist: bold rings with a lattice of two crossing
    windings between them (the arm the first-person view looks down at)."""
    out = np.zeros(len(P))
    sh, el, wr = J["joint-r-shoulder"], J["joint-r-elbow"], J["joint-r-hand"]
    for a, b, rmax, t0, t1 in ((sh, el, 0.15, 0.08, 0.97), (el, wr, 0.11, 0.03, 0.9)):
        t, r, th, Lx = limb_frame(P, a, b)
        sel = (r < rmax) & (t > t0) & (t < t1)
        along = t * Lx
        pitch = 0.1
        ring = band(np.abs((along / pitch) % 1.0 - 0.5) * pitch, BOLD * 0.8)
        turn = th / (2 * math.pi)
        w1 = band(np.abs((along / pitch + 2 * turn + 0.5) % 1.0 - 0.5) * pitch * 0.5, 0.0065)
        w2 = band(np.abs((along / pitch - 2 * turn + 0.5) % 1.0 - 0.5) * pitch * 0.5, 0.0065)
        out = np.maximum(out, np.where(sel, np.maximum(ring, np.maximum(w1, w2)), 0.0))
    return out


def d_arm_winding(P, N, J, ctx):
    """One broad band winding down each arm from the shoulder to the wrist."""
    out = np.zeros(len(P))
    for s, hand in (("l", 1.0), ("r", -1.0)):
        sh, el, wr = J[f"joint-{s}-shoulder"], J[f"joint-{s}-elbow"], J[f"joint-{s}-hand"]
        for a, b, rmax, t0, t1, off in ((sh, el, 0.15, 0.1, 0.95, 0.0), (el, wr, 0.11, 0.05, 0.88, 0.5)):
            t, r, th, Lx = limb_frame(P, a, b)
            sel = (r < rmax) & (t > t0) & (t < t1)
            pitch = 0.15
            ph = (t * Lx / pitch + hand * th / (2 * math.pi) + off) % 1.0
            out = np.maximum(out, np.where(sel, band(np.abs(ph - 0.5) * pitch, BOLD * 1.1), 0.0))
    return out


def _front_plane(P, N, J, cz, half_x, half_z):
    sp1 = J["joint-spine-1"]
    front = (N[:, 1] < -0.3) & (np.abs(P[:, 0]) < half_x) & (np.abs(P[:, 2] - cz) < half_z) & (P[:, 1] < sp1[1])
    return front, np.stack([P[:, 0], P[:, 2] - cz], axis=1)


def d_chest_sun(P, N, J, ctx):
    """A sun on the sternum: a ring, a dot and twelve rays."""
    cz = J["joint-spine-1"][2] - 0.06
    front, uv = _front_plane(P, N, J, cz, 0.17, 0.17)
    tt = np.linspace(0, 2 * math.pi, 600)
    curves = [np.stack([np.cos(tt), np.sin(tt)], axis=1) * 0.042]
    lin = np.linspace(0, 1, 80)[:, None]
    for k in range(12):
        a = 2 * math.pi * k / 12
        d = np.array([math.cos(a), math.sin(a)])
        curves.append(d * 0.062 + d * (0.075 if k % 2 == 0 else 0.045) * lin)
    m = curve2d_mask(uv, curves, 0.0062)
    m = np.maximum(m, band(np.linalg.norm(uv, axis=1), 0.014))
    return np.where(front, m, 0.0)


def d_chest_collar(P, N, J, ctx):
    """A torc under the collarbones, shoulder to shoulder, with seven hanging points."""
    sh = J["joint-l-shoulder"]
    cz = J["joint-spine-1"][2] + 0.02
    wide = abs(sh[0]) * 0.92
    front, uv = _front_plane(P, N, J, cz, wide + 0.03, 0.2)
    xs = np.linspace(-wide, wide, 500)

    def arc(drop):
        return np.stack([xs, 0.07 * (xs / wide) ** 2 - drop], axis=1)

    curves = [arc(0.07), arc(0.105)]
    lin = np.linspace(0, 1, 60)[:, None]
    for k in range(7):
        x0 = wide * 0.75 * (k - 3) / 3.0
        z0 = 0.07 * (x0 / wide) ** 2 - 0.105
        for dx in (-0.016, 0.016):
            curves.append(np.array([x0 + dx, z0]) + np.array([-dx, -0.04]) * lin)
    return np.where(front, curve2d_mask(uv, curves, 0.006), 0.0)


def d_back_shoulders(P, N, J, ctx):
    """The shoulder-to-shoulder piece: two rails across the upper back and onto the backs of both
    upper arms, a bold zigzag between them."""
    sh = J["joint-l-shoulder"]
    sp1 = J["joint-spine-1"]
    zc = sp1[2] + 0.075
    wide = abs(sh[0]) + 0.1
    back, uv = _back_plane(P, N, J, zc - 0.09, zc + 0.09)
    back &= np.abs(P[:, 0]) < wide
    xs = np.linspace(-wide, wide, 700)
    sag = -0.035 * (xs / wide) ** 2          # the piece follows the slope of the shoulders
    rails = [np.stack([xs, zc + 0.048 + sag], axis=1), np.stack([xs, zc - 0.048 + sag], axis=1)]
    period = 0.085
    tri = np.abs(((xs / period) % 1.0) - 0.5) * 2.0
    zig = [np.stack([xs, zc + (tri - 0.5) * 0.06 + sag], axis=1)]
    m = np.maximum(curve2d_mask(uv, rails, BOLD * 0.8), curve2d_mask(uv, zig, BOLD * 0.65))
    return np.where(back, m, 0.0)


def d_back_serpent(P, N, J, ctx):
    """A serpent up the spine: an S from the lower back to between the shoulder blades, its head a ring."""
    sp4, sp1 = J["joint-spine-4"], J["joint-spine-1"]
    z0, z1 = sp4[2] - 0.02, sp1[2] + 0.1
    back, uv = _back_plane(P, N, J, z0 - 0.04, z1 + 0.08)
    tt = np.linspace(0, 1, 500)
    body = np.stack([0.075 * np.sin(tt * 2.5 * 2 * math.pi) * (0.35 + 0.65 * tt), z0 + (z1 - z0) * tt], axis=1)
    m = np.zeros(len(P))
    # the body thickens towards the head
    for a, b, half in ((0, 170, BOLD * 0.8), (160, 340, BOLD * 1.1), (330, 500, BOLD * 1.4)):
        m = np.maximum(m, curve2d_mask(uv, [body[a:b]], half))
    head = body[-1] + np.array([0.0, 0.03])
    ring = np.linspace(0, 2 * math.pi, 200)
    m = np.maximum(m, curve2d_mask(uv, [head + np.stack([np.cos(ring) * 0.03, np.sin(ring) * 0.038], axis=1)], BOLD * 0.75))
    return np.where(back, m, 0.0)


def d_face_crown(P, N, J, ctx):
    """A row of points across the forehead, above the brows."""
    eyeL = J["joint-l-eye"]
    hs = ctx["hs"]
    face = _face(P, N, J)
    zlo, zhi = eyeL[2] + 0.028 * hs, eyeL[2] + 0.062 * hs
    wide = 0.058 * hs
    xs = np.linspace(-wide, wide, 500)
    tri = np.abs(((xs / (wide / 2.5)) % 1.0) - 0.5) * 2.0
    uv = np.stack([P[:, 0], P[:, 2]], axis=1)
    curves = [np.stack([xs, zlo + tri * (zhi - zlo)], axis=1), np.stack([xs, np.full_like(xs, zlo - 0.004 * hs)], axis=1)]
    sel = face & (P[:, 2] > zlo - 0.012 * hs) & (P[:, 2] < zhi + 0.008 * hs)
    return np.where(sel, curve2d_mask(uv, curves, 0.0032 * hs), 0.0)


def d_face_bars(P, N, J, ctx):
    """Two bold bars across each cheek and one over the bridge of the nose."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    face = _face(P, N, J)
    m = np.zeros(len(P))
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        for k in range(2):
            a = surface_point(P, e + np.array([sgn * -0.012, -0.03, -0.03 - 0.016 * k]), face)
            b = surface_point(P, e + np.array([sgn * 0.045, -0.02, -0.036 - 0.016 * k]), face)
            m = np.maximum(m, polyline_mask(P, np.array([a, b]), 0.0042))
    a = surface_point(P, eyeL + np.array([-0.012, -0.03, -0.012]), face)
    b = surface_point(P, eyeR + np.array([0.012, -0.03, -0.012]), face)
    mid = surface_point(P, 0.5 * (eyeL + eyeR) + np.array([0.0, -0.05, -0.012]), face)
    m = np.maximum(m, polyline_mask(P, np.array([a, mid, b]), 0.0042))
    return np.where(face, m, 0.0)


def paint_edge(x, soft, P, seed, rag=1.0):
    """War paint's edge (the second look lane: the paints ended in straight, hard edges): 1 well inside (x > 0, in
    metres inside the edge), easing to 0 over ``soft`` metres, the edge itself ragged by ``rag`` x ``soft`` of
    two-scale noise along the skin, as a hand smears it."""
    n = 0.65 * _noise3(P, 55.0, seed) + 0.35 * _noise3(P, 170.0, seed + 1)
    y = (x + (n - 0.5) * 2.0 * soft * rag) / soft + 0.5
    y = np.clip(y, 0.0, 1.0)
    return y * y * (3.0 - 2.0 * y)


def paint_body(P, seed):
    """Paint's own thickness: a smear is not one flat colour (0.82-1)."""
    return 0.82 + 0.18 * _noise3(P, 90.0, seed)


def d_full_face(P, N, J, ctx):
    """War paint over the whole upper face, brow to cheekbones and temple to temple, its lower edge
    ragged where the fingers dragged it down; its edges soft and smeared, fading round the temples."""
    eyeL = J["joint-l-eye"]
    hs = ctx["hs"]
    face = (N[:, 1] < 0.25) & (P[:, 1] < eyeL[1] + 0.07 * hs)
    drag = 0.022 * hs * _noise3(np.stack([P[:, 0] * 90.0, P[:, 0] * 0.0, P[:, 0] * 0.0], axis=1), 1.0, 7)
    lower = eyeL[2] - 0.036 * hs - drag
    upper = eyeL[2] + 0.06 * hs
    soft = 0.007 * hs
    m = paint_edge(P[:, 2] - lower, soft, P, 71) * paint_edge(upper - P[:, 2], soft * 1.6, P, 73)
    # round the temples the paint thins out where the face turns away (it was cut off where the normal turned)
    m *= paint_edge(-0.05 - N[:, 1], 0.2, P, 75, rag=0.6)
    return np.where(face, m * paint_body(P, 77), 0.0)


def d_back_hand(P, N, J, ctx):
    """A hand print between the shoulder blades: the palm, four fingers and the thumb."""
    sp1 = J["joint-spine-1"]
    c = np.array([0.0, sp1[2] - 0.035])
    back, uv = _back_plane(P, N, J, c[1] - 0.12, c[1] + 0.2)
    q = uv - c
    m = band(np.sqrt((q[:, 0] / 0.058) ** 2 + (q[:, 1] / 0.064) ** 2) * 0.06, 0.06)     # the palm
    lin = np.linspace(0, 1, 60)[:, None]
    fingers = []
    for k, (x0, ang, length) in enumerate(((-0.042, 104, 0.085), (-0.014, 94, 0.1), (0.014, 86, 0.097), (0.041, 76, 0.08))):
        a = math.radians(ang)
        start = np.array([x0, 0.07])
        fingers.append(c + start + np.array([math.cos(a), math.sin(a)]) * length * lin)
    a = math.radians(18)
    fingers.append(c + np.array([0.058, -0.012]) + np.array([math.cos(a), math.sin(a)]) * 0.075 * lin)
    m = np.maximum(m, curve2d_mask(uv, fingers, 0.0125))
    return np.where(back, m, 0.0)


def d_scar_cheek(P, N, J, ctx):
    return _scar(P, ctx["scars"]["cheek"], min_half=BOLD)                # P51: the 4 cm rule (was 0.0036)


def d_scar_back_lash(P, N, J, ctx):
    """Three long lash scars slanting across the back, from the left shoulder blade to the right flank:
    the scars the game camera sees."""
    V = ctx["V"]
    sp1, sp3 = J["joint-spine-1"], J["joint-spine-3"]
    back_v = V[:, 1] > 0.02
    m = np.zeros(len(P))
    for k in range(3):
        dz = -0.075 * k
        a = np.array([0.17, sp1[1] + 0.14, sp1[2] + 0.07 + dz])
        b = np.array([-0.15, sp3[1] + 0.14, sp3[2] + 0.1 + dz])
        pts = np.array([surface_point(V, a + (b - a) * t, back_v) for t in np.linspace(0, 1, 9)])
        d, t = polyline_dist(P, pts)
        m = np.maximum(m, scar_profile(d, BOLD * SCAR_SPREAD * (1.0 - 0.12 * k) * (1.0 - 0.45 * t), P, k))
    return m


# --------------------------------------------------------------------------------------
# the catalogue II (P56)
# --------------------------------------------------------------------------------------
def _legs():
    return (("l", 1.0), ("r", -1.0))


def d_leg_bands(P, N, J, ctx):
    """Two bold rings round each thigh with a row of dots between them."""
    out = np.zeros(len(P))
    for s, _sg in _legs():
        hip, kn = J[f"joint-{s}-upper-leg"], J[f"joint-{s}-knee"]
        t, r, th, Lx = limb_frame(P, hip, kn)
        sel = (r < 0.17) & (t > 0.35) & (t < 0.9)
        ring = np.maximum(band(np.abs(t - 0.52) * Lx, BOLD), band(np.abs(t - 0.74) * Lx, BOLD))
        dots = band(np.hypot((t - 0.63) * Lx, ((th / (2 * math.pi) * 10.0 + 0.5) % 1.0 - 0.5) * 2 * math.pi * 0.08 / 10.0),
                    0.011)
        out = np.maximum(out, np.where(sel, np.maximum(ring, dots), 0.0))
    return out


def d_leg_serpent(P, N, J, ctx):
    """A serpent coiling down the right leg from the hip to the ankle, its head on the shin."""
    hip, kn, an = J["joint-r-upper-leg"], J["joint-r-knee"], J["joint-r-ankle"]
    out = np.zeros(len(P))
    for a, b, rmax, t0, t1, ph, half in ((hip, kn, 0.17, 0.12, 1.0, 0.0, BOLD * 1.25), (kn, an, 0.12, 0.0, 0.8, 0.5,
                                                                                       BOLD * 1.0)):
        t, r, th, Lx = limb_frame(P, a, b)
        sel = (r < rmax) & (t > t0) & (t < t1)
        pitch = 0.22
        coil = (t * Lx / pitch + th / (2 * math.pi) + ph) % 1.0
        out = np.maximum(out, np.where(sel, band(np.abs(coil - 0.5) * pitch, half), 0.0))
    # the head: a ring on the front of the shin near its lower end
    t, r, th, Lx = limb_frame(P, kn, an)
    head = (N[:, 1] < -0.2) & (r < 0.12)
    c = kn + (an - kn) * 0.85
    d = np.linalg.norm((P - c) * [1.0, 0.0, 1.0], axis=1)
    out = np.maximum(out, np.where(head, np.maximum(band(np.abs(d - 0.028), BOLD * 0.6), band(d, 0.011)), 0.0))
    return out


def d_leg_runes(P, N, J, ctx):
    """A column of rune staves down the front of each shin."""
    out = np.zeros(len(P))
    for s, sg in _legs():
        kn, an = J[f"joint-{s}-knee"], J[f"joint-{s}-ankle"]
        front = (N[:, 1] < -0.25) & (np.abs(P[:, 0] - 0.5 * (kn[0] + an[0])) < 0.07)
        z0, z1 = an[2] + 0.06, kn[2] - 0.06
        x0 = 0.5 * (kn[0] + an[0])
        uv = np.stack([P[:, 0] - x0, P[:, 2]], axis=1)
        curves = []
        n = 4
        for k in range(n):
            zt = z1 - (z1 - z0) * k / n
            zb = zt - (z1 - z0) / n * 0.75
            lin = np.linspace(0, 1, 40)[:, None]
            curves.append(np.array([0.0, zt]) + np.array([0.0, zb - zt]) * lin)        # the stave
            w = 0.03 * (1 if k % 2 == 0 else -1)
            curves.append(np.array([0.0, zt]) + np.array([w, -0.035]) * lin)          # a branch
            curves.append(np.array([0.0, zt - 0.05]) + np.array([-w, -0.035]) * lin)
        out = np.maximum(out, np.where(front, curve2d_mask(uv, curves, BOLD * 0.65), 0.0))
    return out


def d_leg_claws(P, N, J, ctx):
    """Three claw stripes raking down the front and outer side of the left thigh."""
    hip, kn = J["joint-l-upper-leg"], J["joint-l-knee"]
    t, r, th, Lx = limb_frame(P, hip, kn)
    sel = (r < 0.17) & (t > 0.18) & (t < 0.8)
    m = np.zeros(len(P))
    for k in (-1, 0, 1):
        line = math.pi + 0.8 + 0.42 * k + 0.5 * (t - 0.5)    # the front of the outer side, slanting as it falls
        dth = np.abs((th - line + math.pi) % (2 * math.pi) - math.pi)
        along = np.clip((t - 0.18) / 0.62, 0.0, 1.0)
        m = np.maximum(m, band(dth * np.maximum(r, 0.05), BOLD * (1.0 - 0.5 * along)))
    return np.where(sel, m, 0.0)


def d_arm_runes(P, N, J, ctx):
    """A band of runes round each forearm between two rings."""
    out = np.zeros(len(P))
    for s in ("l", "r"):
        el, wr = J[f"joint-{s}-elbow"], J[f"joint-{s}-hand"]
        t, r, th, Lx = limb_frame(P, el, wr)
        sel = (r < 0.1) & (t > 0.3) & (t < 0.72)
        ring = np.maximum(band(np.abs(t - 0.36) * Lx, BOLD * 0.7), band(np.abs(t - 0.66) * Lx, BOLD * 0.7))
        cell = (th / (2 * math.pi) * 7.0) % 1.0
        stave = band(np.abs(cell - 0.5) * 0.16, 0.007) * (t > 0.4) * (t < 0.62)
        branch = band(np.abs((t - 0.4) * Lx - (cell - 0.5) * 0.09 - 0.03), 0.006) * (t > 0.4) * (t < 0.62) \
            * (np.abs(cell - 0.5) < 0.3)
        out = np.maximum(out, np.where(sel, np.maximum(ring, np.maximum(stave, branch)), 0.0))
    return out


def d_arm_spirals(P, N, J, ctx):
    """A double spiral on the outside of each upper arm."""
    out = np.zeros(len(P))
    for s, sg in (("l", 1.0), ("r", -1.0)):
        sh, el = J[f"joint-{s}-shoulder"], J[f"joint-{s}-elbow"]
        c = sh + (el - sh) * 0.42
        outer = (P[:, 0] * sg > c[0] * sg) & (np.linalg.norm(P - c, axis=1) < 0.13)
        uv = np.stack([P[:, 1] - c[1], P[:, 2] - c[2]], axis=1)
        curves = []
        for k, off in enumerate((-0.035, 0.035)):
            tt = np.linspace(0.0, 2.2 * math.pi, 500)
            rho = 0.0085 * tt
            ang = tt * (1 if k == 0 else -1) + (0.0 if k == 0 else math.pi)
            curves.append(np.array([0.0, off * 1.4]) + np.stack([rho * np.cos(ang), rho * np.sin(ang)], axis=1))
        out = np.maximum(out, np.where(outer, curve2d_mask(uv, curves, 0.0105), 0.0))
    return out


def d_chest_raven(P, N, J, ctx):
    """A raven with spread wings across the chest, its head on the sternum."""
    cz = J["joint-spine-1"][2] - 0.03
    front, uv = _front_plane(P, N, J, cz, 0.24, 0.16)
    curves = []
    for side in (1.0, -1.0):
        for k in range(4):
            tt = np.linspace(0, 1, 160)[:, None]
            start = np.array([side * 0.02, -0.01 - 0.012 * k])
            d1 = np.array([side * math.cos(math.radians(14 - 12 * k)), math.sin(math.radians(14 - 12 * k))])
            curves.append(start + d1 * (0.2 - 0.035 * k) * tt + np.array([0.0, 0.04]) * np.sin(tt * math.pi))
    tt = np.linspace(0, 1, 80)[:, None]
    curves.append(np.array([0.0, 0.035]) + np.array([0.0, -0.11]) * tt)      # the body
    m = curve2d_mask(uv, curves, BOLD * 0.75)
    m = np.maximum(m, band(np.linalg.norm(uv - np.array([0.0, 0.05]), axis=1), 0.02))     # the head
    return np.where(front, m, 0.0)


def d_chest_runes(P, N, J, ctx):
    """A column of rune staves down the sternum to the belly."""
    sp1, sp3 = J["joint-spine-1"], J["joint-spine-3"]
    front = (N[:, 1] < -0.3) & (np.abs(P[:, 0]) < 0.07) & (P[:, 2] < sp1[2] + 0.02) & (P[:, 2] > sp3[2])
    uv = np.stack([P[:, 0], P[:, 2]], axis=1)
    curves = []
    z1, z0 = sp1[2], sp3[2] + 0.03
    n = 5
    lin = np.linspace(0, 1, 40)[:, None]
    for k in range(n):
        zt = z1 - (z1 - z0) * k / n
        zb = zt - (z1 - z0) / n * 0.75
        curves.append(np.array([0.0, zt]) + np.array([0.0, zb - zt]) * lin)
        w = 0.028 * (1 if k % 2 == 0 else -1)
        curves.append(np.array([0.0, zt]) + np.array([w, -0.03]) * lin)
        curves.append(np.array([0.0, zt - 0.025]) + np.array([w, -0.03]) * lin)
    return np.where(front, curve2d_mask(uv, curves, BOLD * 0.6), 0.0)


def d_back_wheel(P, N, J, ctx):
    """A sun wheel between the shoulder blades: two rings and eight spokes."""
    sp1 = J["joint-spine-1"]
    c = np.array([0.0, sp1[2] + 0.02])
    back, uv = _back_plane(P, N, J, c[1] - 0.2, c[1] + 0.2)
    q = uv - c
    rr = np.linalg.norm(q, axis=1)
    m = np.maximum(band(np.abs(rr - 0.13), BOLD), band(np.abs(rr - 0.06), BOLD * 0.7))
    ang = np.arctan2(q[:, 1], q[:, 0])
    spoke = band(np.abs(((ang / (2 * math.pi) * 8.0 + 0.5) % 1.0 - 0.5)) * 2 * math.pi / 8.0 * rr, BOLD * 0.6)
    m = np.maximum(m, spoke * (rr > 0.06) * (rr < 0.13))
    return np.where(back, m, 0.0)


def d_back_spine(P, N, J, ctx):
    """A line of chevrons down the spine from the neck to the small of the back."""
    sp4, sp1 = J["joint-spine-4"], J["joint-spine-1"]
    z0, z1 = sp4[2] - 0.02, sp1[2] + 0.12
    back, uv = _back_plane(P, N, J, z0 - 0.03, z1 + 0.03)
    back &= np.abs(P[:, 0]) < 0.08
    period = 0.07
    ph = ((uv[:, 1] - z0) + 0.6 * np.abs(uv[:, 0])) / period % 1.0
    m = band(np.abs(ph - 0.5) * period, BOLD * 0.7) * (np.abs(uv[:, 0]) < 0.055)
    m *= (uv[:, 1] > z0) & (uv[:, 1] < z1)
    return np.where(back, m, 0.0)


def d_face_temples(P, N, J, ctx):
    """A spiral on each temple, beside the eye."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    hs = ctx["hs"]
    m = np.zeros(len(P))
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        side = (P[:, 0] * sgn > e[0] * sgn + 0.01 * hs) & (P[:, 1] < e[1] + 0.06 * hs)
        c = surface_point(P, e + np.array([sgn * 0.045 * hs, 0.02 * hs, 0.012 * hs]), side)
        q = np.stack([P[:, 1] - c[1], P[:, 2] - c[2]], axis=1)
        tt = np.linspace(0.0, 2.4 * math.pi, 400)
        rho = 0.0032 * hs * tt
        curve = np.stack([rho * np.cos(tt), rho * np.sin(tt)], axis=1)
        m = np.maximum(m, np.where(side & (np.abs(P[:, 0] - c[0]) < 0.03 * hs), curve2d_mask(q, [curve], 0.0032 * hs), 0.0))
    return m


def d_face_tears(P, N, J, ctx):
    """Two bold lines from under each eye's outer corner down over the cheekbone, above the beard's line."""
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    hs = ctx["hs"]
    face = _face(P, N, J)
    m = np.zeros(len(P))
    for e, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        for k in range(2):
            a = surface_point(P, e + np.array([sgn * (0.008 + 0.012 * k), -0.03, -0.018]) * hs, face)
            b = surface_point(P, e + np.array([sgn * (0.016 + 0.014 * k), -0.026, -0.05]) * hs, face)
            m = np.maximum(m, polyline_mask(P, np.array([a, b]), 0.0045 * hs, taper=0.4))
    return np.where(face, m, 0.0)


def d_eye_band(P, N, J, ctx):
    """War paint in a band across both eyes, temple to temple, its edges dragged and soft, its ends smeared out at
    the temples (the second look lane: it was a rectangle with hard edges)."""
    eyeL = J["joint-l-eye"]
    hs = ctx["hs"]
    face = (N[:, 1] < 0.2) & (P[:, 1] < eyeL[1] + 0.07 * hs) & (np.abs(P[:, 0]) < 0.1 * hs)
    drag = 0.008 * hs * _noise3(np.stack([P[:, 0] * 120.0, P[:, 0] * 0.0, P[:, 0] * 0.0], axis=1), 1.0, 11)
    lower = eyeL[2] - 0.02 * hs - drag
    upper = eyeL[2] + 0.016 * hs + drag * 0.5
    soft = 0.0055 * hs
    m = paint_edge(P[:, 2] - lower, soft, P, 81) * paint_edge(upper - P[:, 2], soft, P, 83)
    m *= paint_edge(0.072 * hs - np.abs(P[:, 0]), 0.014 * hs, P, 85)
    return np.where(face, m * paint_body(P, 87), 0.0)


def d_half_face(P, N, J, ctx):
    """War paint over the left half of the face, brow to jaw, its edge down the middle a straight line."""
    eyeL = J["joint-l-eye"]
    hs = ctx["hs"]
    L = ctx["L"]
    face = (N[:, 1] < 0.3) & (P[:, 1] < eyeL[1] + 0.06 * hs)
    # the second look lane: the middle line stays straight but not cut (a 3 mm ease), the brow's and the jaw's edges
    # smeared
    m = paint_edge(P[:, 0], 0.003 * hs, P, 91, rag=0.3) * paint_edge(eyeL[2] + 0.045 * hs - P[:, 2], 0.007 * hs, P, 93)
    m *= paint_edge(P[:, 2] - (L["chin"] + 0.01 * hs), 0.007 * hs, P, 95)
    m *= paint_edge(0.1 - N[:, 1], 0.2, P, 99, rag=0.6)     # thinning out round the side of the head
    return np.where(face, m * paint_body(P, 97), 0.0)


def d_chest_slash(P, N, J, ctx):
    """War paint in one broad slash across the chest, from the left shoulder to the right of the belly."""
    V = ctx["V"]
    sh, sp3 = J["joint-l-shoulder"], J["joint-spine-3"]
    front_v = V[:, 1] < J["joint-spine-1"][1] - 0.04
    a = surface_point(V, sh + np.array([-0.04, -0.15, -0.04]), front_v)
    b = surface_point(V, np.array([-0.13, sp3[1] - 0.15, sp3[2] + 0.02]), front_v)
    pts = np.array([surface_point(V, a + (b - a) * t, front_v) for t in np.linspace(0, 1, 9)])
    return polyline_mask(P, pts, BOLD * 1.9, taper=0.35) * (N[:, 1] < -0.2)


def d_leg_stripes(P, N, J, ctx):
    """War paint: three vertical stripes down the front of each thigh and each shin."""
    out = np.zeros(len(P))
    for s, sg in _legs():
        for a, b in ((J[f"joint-{s}-upper-leg"], J[f"joint-{s}-knee"]), (J[f"joint-{s}-knee"], J[f"joint-{s}-ankle"])):
            t, r, th, Lx = limb_frame(P, a, b)
            sel = (r < 0.17) & (t > 0.15) & (t < 0.85) & (N[:, 1] < -0.1)
            x0 = 0.5 * (a[0] + b[0])
            m = np.zeros(len(P))
            for dx in (-0.04, 0.0, 0.04):
                m = np.maximum(m, band(np.abs(P[:, 0] - (x0 + dx)), BOLD * 0.75))
            out = np.maximum(out, np.where(sel, m, 0.0))
    return out


def d_scar_lip(P, N, J, ctx):
    """An old cut through the right side of the lips down onto the chin."""
    hs = ctx["hs"]
    L = ctx["L"]
    V = ctx["V"]
    front = V[:, 1] < J["joint-head"][1] - 0.06
    a = surface_point(V, np.array([-0.012 * hs, L["face_y"], L["lip_top"] + 0.012 * hs]), front)
    b = surface_point(V, np.array([-0.022 * hs, L["face_y"] + 0.01 * hs, L["chin"] + 0.012 * hs]), front)
    return _scar(P, [(a, b, 0.0)], min_half=BOLD * 0.45)


def d_scar_shoulder_bite(P, N, J, ctx):
    """A beast's bite on the outside of the right shoulder (the arm the creator frames): two arcs of tooth marks."""
    V = ctx["V"]
    sh, el = J["joint-r-shoulder"], J["joint-r-elbow"]
    c = sh + (el - sh) * 0.28 + np.array([-0.08, 0.02, 0.0])
    back = (V[:, 0] < c[0] + 0.05) & (np.linalg.norm(V - c, axis=1) < 0.2)
    m = np.zeros(len(P))
    for row, dz in ((0, 0.06), (1, -0.06)):
        for k in range(5):
            ang = math.radians(-50 + 25 * k)
            p = c + np.array([0.0, 0.07 * math.sin(ang), dz * math.cos(ang) - (0.02 if row else -0.02)])
            q = surface_point(V, p, back)
            m = np.maximum(m, scar_profile(np.linalg.norm(P - q, axis=1), BOLD * SCAR_SPREAD, P, 5 * row + k))
    return m


def d_scar_thigh_gash(P, N, J, ctx):
    """A long gash slanting across the front of the right thigh."""
    hip, kn = J["joint-r-upper-leg"], J["joint-r-knee"]
    t, r, th, Lx = limb_frame(P, hip, kn)
    sel = (r < 0.17) & (t > 0.28) & (t < 0.68)
    line = -math.pi / 2 + 0.35 + 3.0 * (t - 0.48)             # the front (-Y), crossing from the outside in
    dth = np.abs((th - line + math.pi) % (2 * math.pi) - math.pi)
    along = np.clip((t - 0.28) / 0.4, 0.0, 1.0)
    return np.where(sel, scar_profile(dth * np.maximum(r, 0.05), BOLD * SCAR_SPREAD * (0.35 + 0.85 * np.sin(math.pi * along) ** 0.6), P), 0.0)


def d_scar_ribs(P, N, J, ctx):
    """A spear's scar under the left ribs."""
    sp2 = J["joint-spine-2"]
    front = (N[:, 1] < -0.3) & (P[:, 0] > 0.0) & (np.abs(P[:, 2] - sp2[2] + 0.06) < 0.12)
    uv = np.stack([P[:, 0], P[:, 2]], axis=1)
    lin = np.linspace(0, 1, 120)[:, None]
    curve = np.array([0.05, sp2[2] - 0.01]) + np.array([0.13, -0.09]) * lin
    from scipy.spatial import cKDTree
    d, i = cKDTree(curve).query(uv, distance_upper_bound=BOLD * 8)
    along = np.where(np.isfinite(d), np.minimum(i, len(curve) - 1) / (len(curve) - 1), 0.0)
    d = np.where(np.isfinite(d), d, 1.0)
    return np.where(front, scar_profile(d, BOLD * SCAR_SPREAD * 1.1 * (0.3 + 0.7 * np.sin(math.pi * along) ** 0.6), P), 0.0)


DRAW = {
    "tat_arm_bands": d_arm_bands, "tat_arm_chevrons": d_arm_chevrons, "tat_chest_spiral": d_chest_spiral,
    "tat_chest_knot": d_chest_knot, "tat_back_wings": d_back_wings, "tat_back_tree": d_back_tree,
    "tat_face_lines": d_face_lines, "tat_face_dots": d_face_dots, "paint_face_stripes": d_face_stripes,
    "paint_shoulder_bands": d_shoulder_bands, "scar_brow": d_scar_brow,
    "scar_forearm_slash": d_scar_forearm_slash, "scar_chest_claws": d_scar_chest_claws,
    "scar_knuckles": d_scar_knuckles, "mark_granite_veins": d_granite_veins,
    "mark_lightning_tree": d_lightning_tree, "mark_claw_stripes": d_claw_stripes,
    "tat_arm_sleeve": d_arm_sleeve, "tat_arm_winding": d_arm_winding, "tat_chest_sun": d_chest_sun,
    "tat_chest_collar": d_chest_collar, "tat_back_shoulders": d_back_shoulders, "tat_back_serpent": d_back_serpent,
    "tat_face_crown": d_face_crown, "tat_face_bars": d_face_bars, "paint_full_face": d_full_face,
    "paint_back_hand": d_back_hand, "scar_cheek": d_scar_cheek, "scar_back_lash": d_scar_back_lash,
    "tat_leg_bands": d_leg_bands, "tat_leg_serpent": d_leg_serpent, "tat_leg_runes": d_leg_runes,
    "tat_leg_claws": d_leg_claws, "tat_arm_runes": d_arm_runes, "tat_arm_spirals": d_arm_spirals,
    "tat_chest_raven": d_chest_raven, "tat_chest_runes": d_chest_runes, "tat_back_wheel": d_back_wheel,
    "tat_back_spine": d_back_spine, "tat_face_temples": d_face_temples, "tat_face_tears": d_face_tears,
    "paint_eye_band": d_eye_band, "paint_half_face": d_half_face, "paint_chest_slash": d_chest_slash,
    "paint_leg_stripes": d_leg_stripes, "scar_lip": d_scar_lip, "scar_shoulder_bite": d_scar_shoulder_bite,
    "scar_thigh_gash": d_scar_thigh_gash, "scar_ribs": d_scar_ribs,
}


def bold_half(human_height_m):
    """The half-width (human-scale metres) of a stroke 4 cm wide at stage 1 on a body ``human_height_m`` tall."""
    return BOLD_M10 * M10_SCALE * human_height_m / STAGE1_HEIGHT_M


def draw_all(P, N, region, valid, bd):
    """{design id: float mask over the texels} with every design restricted to its regions."""
    import giant_skin as gs
    import mh_data as mh
    global BOLD
    BOLD = bold_half(bd.height)
    J = bd.joints
    ctx = {"hs": bd.landmarks["hs"], "scars": gs.scar_segments(bd), "V": bd.verts[: mh.N_BODY_VERTS], "L": bd.landmarks}
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
    {id: (kind, regions)}. Returns {id: (layer, channel)}: the scars first, on layers of their
    own in SCAR_ORDER (four a layer); then the others, most regions first, each in the first layer and channel
    where none of its regions already uses that channel, and, for R, G or B, none of its regions
    already has another of R, G and B."""
    placed = {}
    scars = [d for d in SCAR_ORDER if d in designs]
    others = sorted((d for d in designs if d not in scars), key=lambda d: (-len(designs[d][1]), d))
    layers = []   # per layer: {"scar": bool, "used": {channel: set(regions)}}
    # the scars fill layers of their own, four a layer (the shader's scar_layer and scar_layer_b); P56: a scar past the
    # first six shares a channel of those two layers with scars of other regions (the skin shader gates each scar
    # channel by the worn scars' regions, scar_regions), under the packing rule
    for i, d in enumerate(scars):
        if i < 6:
            li, c = divmod(i, SCARS_PER_LAYER)
            if li == len(layers):
                layers.append({"scar": True, "used": {ch: set() for ch in range(4)}})
        else:
            li, c = _free_spot(layers, set(designs[d][1]), lambda ly: ly["scar"])
            if li is None:
                raise ValueError("pack: no room for the scar %s in the %d scar layers" % (d, SCAR_LAYERS))
        placed[d] = (li, c)
        layers[li]["used"][c] |= set(designs[d][1])
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


def _free_spot(layers, regs, which):
    """The first (layer, channel) of the layers ``which`` keeps where ``regs`` may go under the packing rule, or
    (None, None)."""
    for li, ly in enumerate(layers):
        if not which(ly):
            continue
        for c in range(4):
            if ly["used"][c] & regs:
                continue
            if c < 3 and any(ly["used"][o] & regs for o in range(3) if o != c):
                continue
            return li, c
    return None, None


def paint_problems(designs):
    """The two-paint rule (P56; plan M11 §3.9): a face paint draws in the face's region alone and a body paint never
    in it, so a face paint and a body paint worn together never share a region's area. Problems, [] when it holds."""
    out = []
    for d, (kind, regions) in sorted(designs.items()):
        if kind != "paint":
            continue
        face = set(regions) & set(FACE_REGIONS)
        if face and set(regions) - set(FACE_REGIONS):
            out.append("%s: a war paint is on the face or on the body, not both (regions %s)" % (d, sorted(regions)))
    return out


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


SIDE_SHARE = 0.8          # a design with this share of its ink on one side of the body is that side's
SIDE_MID_M = 0.01         # human scale: texels this near the middle belong to neither side


def side_of(mask, P):
    """"left" | "right" | "centre": where a design's ink lies on the giant (his own left is +X in the bake's
    rest positions; P48, plan M11 §2.2: the creator frames a design from its side)."""
    w = np.asarray(mask, np.float64).reshape(-1)
    x = np.asarray(P, np.float64).reshape(-1, 3)[:, 0]
    total = float(w.sum())
    if total <= 0.0:
        return "centre"
    left = float(w[x > SIDE_MID_M].sum()) / total
    right = float(w[x < -SIDE_MID_M].sum()) / total
    return "left" if left >= SIDE_SHARE else ("right" if right >= SIDE_SHARE else "centre")


def build(bake_dir, out_dir):
    """Draw, pack and write designs.png (512 x 512*layers RGBA) and designs.json."""
    from PIL import Image
    P, N, region, valid, size = load_bake(bake_dir)
    bd = body_frame()
    masks = draw_all(P, N, region, valid, bd)
    placed = pack(CATALOGUE)
    problems = check_rule(placed, CATALOGUE) + paint_problems(CATALOGUE)
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
                      "side": side_of(masks[did], P),
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
