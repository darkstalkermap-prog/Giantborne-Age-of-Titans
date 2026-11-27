"""The Stormcaller (D2): the sixth signature titan - an original giant of the old kings' bell-wardens 34.0 m
(111.5 ft) tall, as an asset (``build_people.py --stormcaller``).

When the old giant kings drowned the lowland road to bar the Worldbreaker's way south, they set a warden over the
flooded steps with the kingdom's great bell on his back: he rang it and the storms came in off the hills and filled
the steps. The throne's fall broke the locks; the storm he sleeps in woke him, and he stands over the Drowned Steps
calling it down again. Underneath he is a body - the people's CC0 human with MakeHuman's macros,
``giant_body.proportioned`` with a table of his own and ``brute.reshape`` - so he stands and moves as a giant, not a
cloud: upright and broad (the Frostbound stoops, the Broken Warden is a wall behind his shield), long in the leg, the
chest deep, the head carried high; a stern, square face with a long straight nose and deep-set eyes. His skin is the
grey of slate in rain, a cold blue in it, and over the chest, the arms and the back the pale branching scars the
lightning has left on him for a thousand years. Over it what he wears, each its own skinned mesh on the people's 23
bones:

  crown         a band of copper over his brow, and out of it seven tall forked tines of green copper, branching like
                the lightning they draw (his crown is a rod for the storm)
  pauldron_l, pauldron_r
                plates of drowned bronze over each shoulder, green with the water
  bell          the great bell of the drowned kingdom slung on his back, mouth down, its yoke over his shoulder blades
                and two bronze straps over his shoulders: his silhouette (struck, it rings)
  lodestone     a slab of dark bronze over his breast and in it a lodestone bound in copper wire that holds the
                storm's light
  bracer        the right forearm bound in bronze and copper wire where he grips the rod
  greave_l, greave_r
                bronze down each shin
  rod           the storm-rod: a mast of black bog-oak as tall as he is, bound with copper, its head a three-tined fork
                (rigid to the right hand: gear, not a plate)
  beard         his beard in three heavy braids ringed with bronze (gear)
  stormcaller_far the idle's first key, decimated

The metal is drawn by storm_plate.gdshader on Stoneback's stone normal map (its pits and scores): vertex colour alpha
1 metal (bronze, copper, verdigris by the colour), alpha 0 what is not metal (the rod's oak, the beard), alpha 0.35
what glows (the lodestone's heart, the crown's tips). No texture of his own beyond his atlas.

Clips on his skeleton (``stormcaller_moves.py``): dormant (standing in the storm, both hands on the rod, the head
bowed), wake (his intro), idle, walk, run, slam, sweep, gust, call, stamp, roar2, chain, ring, reel, kneel, rise,
death.

``python stormcaller.py stormcaller <out dir> <work dir>`` writes stormcaller.glb, stormcaller_clips.glb, the atlas
(stormcaller_albedo.png 512 px, _normal.png, _orm.png 256 px) and stormcaller_info.json.
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import numpy as np  # noqa: E402

import brute as br  # noqa: E402
import frostbound as fbk  # noqa: E402
import mh_data as mh  # noqa: E402
import people_roles as pr  # noqa: E402
import stoneback as sb  # noqa: E402

KIND = "stormcaller"
HEIGHT_M = 34.0                    # 111.5 ft: over a stage-8 giant (29.26 m) by a head and shoulders, under stage 9's
DESIGN = pr.DESIGN_HEIGHT_M        # 3.6576 m (the stage-1 giant's height: every titan is built there and scaled)
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.38 * HEIGHT_M           # a long, measured stride (12.9 m)
TRIS = 9000
MARGIN_TRIS = 60
FAR_TRIS = 360
OUTFIT = ("kilt", "loincloth", "belt")
OUTFIT_MATERIAL = {"kilt": "leather", "loincloth": "dark_leather", "belt": "dark_leather"}

# ---- the body ------------------------------------------------------------------------------------------------------
# a stern old warden's face: square and long, the brow level and heavy, the eyes deep-set, the nose long and straight,
# the cheekbones high, the mouth wide and set, the jaw square (a beard in braids under it)
STORM_FACE = {"head/head-square": 0.8, "head/head-age-decr-incr": 0.6,
              "cheek/cheek-bones-decr-incr": 0.8, "cheek/cheek-volume-decr-incr": -0.5,
              "nose/nose-scale-vert-decr-incr": 0.6, "nose/nose-scale-horiz-decr-incr": -0.1,
              "nose/nose-point-width-decr-incr": -0.2, "nose/nose-hump-decr-incr": 0.15,
              "chin/chin-width-decr-incr": 0.6, "chin/chin-prominent-decr-incr": 0.5,
              "chin/chin-height-decr-incr": 0.3, "chin/chin-bones-decr-incr": 0.7,
              "eyebrows/eyebrows-trans-backward-forward": 0.9, "eyebrows/eyebrows-trans-down-up": -0.7,
              "eyebrows/eyebrows-angle-down-up": -0.3, "eyes/eye-scale-decr-incr": -0.35,
              "eyes/eye-bag-decr-incr": 0.5, "forehead/forehead-scale-vert-decr-incr": 0.3,
              "mouth/mouth-scale-horiz-decr-incr": 0.4, "mouth/mouth-angles-down-up": -0.5,
              "mouth/mouth-upperlip-volume-decr-incr": -0.3, "mouth/mouth-laugh-lines-in-out": 0.7,
              "neck/neck-scale-horiz-decr-incr": 0.3, "ears/ear-scale-decr-incr": 0.1}
# long in the leg, deep in the chest, broad across the shoulders, the neck strong, the head a little small for the
# frame (it reads tall), the arms long; upright: no stoop, the head carried high
STORM_PROP = dict(legs=1.06, torso=1.02, neck=0.010, head=0.84, arms=1.06, hands=1.12, shoulders=0.040,
                  deltoids=0.012, trapezius=0.004, thighs=0.02)
STORM_SHAPE = dict(hunch_deg=1.5, head_back_deg=2.0, jaw=(0.26, 0.016, 0.010), underbite_m=0.0, brow_m=0.026,
                   brow_band_m=0.012, nose=(0.0, 0.0), ears=0.0, hands=1.08, feet=1.10, gut_m=0.0, tusks=False)
VARIANT = dict(name=KIND, macro=br._macro(62, 0.95, 0.52, african=0.30, asian=0.15, caucasian=0.55),
               face=br._face(1.0, **STORM_FACE), prop=STORM_PROP, shape=STORM_SHAPE, height_m=HEIGHT_M)
STORM_GAITS = {
    "stormcaller_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.04, min_drop=0.025, lean_deg=3.0,
                             pelvis_pitch_deg=2.5, roll_deg=3.0, sway=0.05, arm_swing_deg=12.0, heel_rocker=0.13,
                             lift=0.15),
    "stormcaller_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.09, min_drop=0.07, lean_deg=10.0,
                            pelvis_pitch_deg=6.0, lift=0.32),
}

# ---- the colours (linear vertex colours; storm_plate.gdshader: alpha 1 metal, 0 not metal, 0.35 the glow) ----------
BRONZE_RGBA = (0.40, 0.25, 0.12, 1.0)              # drowned bronze, dark and warm
VERDIGRIS_RGBA = (0.22, 0.42, 0.36, 1.0)           # the green the water left on it
COPPER_RGBA = (0.55, 0.28, 0.14, 1.0)              # bright copper where it is worn (edges, wire)
DARK_RGBA = (0.10, 0.10, 0.11, 1.0)                # the lodestone's iron-dark stone (metal: it shines)
OAK_RGBA = (0.075, 0.060, 0.048, 0.0)              # bog-oak, near black
BRAID_RGBA = (0.060, 0.062, 0.070, 0.0)            # his beard, black-grey and wet
GLOW_RGBA = (0.55, 0.74, 1.0, 0.35)                # the storm's light (the lodestone's heart, the tines' points)
STONE_TILE_M = 3.4                 # Stoneback's stone normal map repeats every this many metres (the metal's pits)
SHARP_DEG = 24.0

# ---- the plates: Stoneback's slab code on his body (thinner: cast bronze, not quarried stone) -----------------------
# piece: (Stoneback's footprint, (thickness, gap, chamfer, cut faces, decimation budget) real metres)
SLABS = {
    "pauldron_l": ("plate_shoulder_l", (0.46, 0.06, 0.14, 2, 480)),
    "pauldron_r": ("plate_shoulder_r", (0.46, 0.06, 0.14, 2, 480)),
    "crown": ("plate_brow", (0.30, 0.05, 0.09, 9, 320)),
    "lodestone": ("plate_chest", (0.52, 0.05, 0.16, 5, 420)),
    "bracer": ("plate_forearm_r", (0.40, 0.05, 0.12, 3, 280)),
    "greave_l": ("plate_shin_l", (0.44, 0.05, 0.12, 3, 300)),
    "greave_r": ("plate_shin_r", (0.44, 0.05, 0.12, 3, 300)),
}
PLATE_ORDER = ("crown", "pauldron_l", "pauldron_r", "bell", "lodestone", "bracer", "greave_l", "greave_r")
GEAR = ("rod", "beard")
# the regions the fight package names (data/enemies/stormcaller.json): the plate -> its region
WEAK_POINTS = {"crown": "head", "pauldron_l": "shoulder_l", "pauldron_r": "shoulder_r", "bell": "back",
               "lodestone": "chest", "bracer": "forearm_r", "greave_l": "shin_l", "greave_r": "shin_r"}
# the main bone of each piece (the rig's break: where its pieces fly from)
PIECE_BONE = {"crown": "head", "pauldron_l": "upperarm_l", "pauldron_r": "upperarm_r", "bell": "spine_03",
              "lodestone": "spine_03", "bracer": "lowerarm_r", "greave_l": "calf_l", "greave_r": "calf_r",
              "rod": "hand_r", "beard": "head"}
# the bell (real metres): its height (lip to shoulder), its mouth's radius, its wall, how far its yoke sits over the
# shoulder blades' top and behind the back
BELL = dict(height_m=10.2, mouth_r_m=4.2, wall_m=0.34, top_gap_m=1.0, back_gap_m=0.55)
# the rod (real metres): the butt's length below the grip (it rests on the ground at his right foot in the idle), the
# head's above it, the shaft's radius, the fork's tines
ROD = dict(butt_m=15.0, head_m=18.5, radius_m=0.42, bands=6, tine_m=3.4, tine_r_m=0.22)
# the crown's tines: (count, the tallest's length real m, its base's radius real m)
TINES = dict(count=7, tallest_m=3.6, base_m=0.24)
GEAR_BUDGET = {"crown": 1300, "pauldron_l": 700, "pauldron_r": 700, "bell": 1700, "lodestone": 1350, "bracer": 700,
               "greave_l": 500, "greave_r": 500, "rod": 1450, "beard": 700}
CLIP_LOOPS = ("idle", "walk", "run", "dormant")
SHAFT_SIDES = 9


def log(*a):
    print("[stormcaller]", *a, flush=True)


r6 = br.r6
unit = sb.unit
_sstep = br._sstep
merge = fbk.merge
add_parts = fbk.add_parts
rigid_piece = fbk.rigid_piece
vertex_up = fbk.vertex_up


# ======================================================================================================================
# colours
# ======================================================================================================================
def bronze_colour(V, up, rng, base=BRONZE_RGBA, green=VERDIGRIS_RGBA, worn=COPPER_RGBA, edge=None, wet=0.55):
    """Each vertex's bronze: the metal's own dark brown, verdigris settled in patches and running down from where water
    stood (the upper faces), bright copper on the worn edges (``edge`` (n,) 0..1) and a little everywhere at random."""
    import people_bake as pbk
    n = len(V)
    V = np.asarray(V)
    patch = _sstep(pbk.fbm(V * 2.2, 2.0, 1201), 0.38, 0.62)
    runs = _sstep(np.asarray(up), -0.2, 0.6) * 0.5 + 0.5 * _sstep(pbk.fbm(V * np.array([4.0, 4.0, 1.0]), 3.0, 1203),
                                                                      0.45, 0.7)
    g = np.clip(patch * wet + runs * 0.35, 0.0, 1.0)
    c = np.asarray(base)[None, :3] * (1.0 - g[:, None]) + np.asarray(green)[None, :3] * g[:, None]
    w = np.clip(rng.uniform(-0.04, 0.04, n) + (0.0 if edge is None else 0.7 * np.asarray(edge)), 0.0, 1.0)
    c = c * (1.0 - w[:, None]) + np.asarray(worn)[None, :3] * w[:, None]
    return np.concatenate([c, np.ones((n, 1))], axis=1)


def bronze_piece(p, seed):
    rng = np.random.default_rng(seed)
    p.rgba = bronze_colour(p.V, vertex_up(p.V, p.T), rng)
    return p


def slab(person, name, body_T, groups, seed):
    """Stoneback's plate (sb.plate_piece) on this body, by its footprint (SLABS), as bronze (no iron bands: the
    bronze is strapped on under it)."""
    src, spec = SLABS[name]
    sb.PLATES[src] = spec
    bands = sb.plate_bands
    sb.plate_bands = lambda *_a: []
    try:
        p = sb.plate_piece(person, src, body_T, groups, seed)
    finally:
        sb.plate_bands = bands
    p.name = name
    return bronze_piece(p, seed + 7)


def joints(person):
    S = person.S
    return {k: v * S for k, v in person.bd.joints.items()}


def tube_part(path, radii, sides, rgba, close=(True, True), frame0=None):
    V, T, _r, _a = sb.tube(np.asarray(path, np.float64), np.asarray(radii, np.float64), sides, close=close,
                           frame0=frame0)
    return V, T, np.asarray(rgba) if np.ndim(rgba) == 1 else rgba


def ring_part(c, axis, R, r, rgba, segs=14, sides=5):
    """A torus (a band of wire, a ring) round ``c`` square to ``axis``: radius R, its section r."""
    axis = unit(axis)
    u = unit(np.cross(axis, [0.0, 0.0, 1.0]) if abs(axis[2]) < 0.9 else np.cross(axis, [1.0, 0.0, 0.0]))
    v = np.cross(axis, u)
    path = np.array([c + (u * math.cos(t) + v * math.sin(t)) * R for t in np.linspace(0.0, 2.0 * math.pi, segs + 1)])
    V, T, _r, _a = sb.tube(path, np.full(len(path), r), sides, close=(False, False))
    return V, T, np.asarray(rgba)


def lathe(profile, axis_c, axis, segs, frame0):
    """A surface of revolution: ``profile`` [(radius, along)] revolved round the line through ``axis_c`` along
    ``axis``. (V, T) - the rings joined in order, the faces' winding by the profile's own direction."""
    axis = unit(axis)
    u = unit(np.asarray(frame0) - axis * float(np.asarray(frame0) @ axis))
    v = np.cross(axis, u)
    V = []
    for rad, along in profile:
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            V.append(axis_c + axis * along + (u * math.cos(a) + v * math.sin(a)) * rad)
    T = []
    for i in range(len(profile) - 1):
        for k in range(segs):
            a, b = i * segs + k, i * segs + (k + 1) % segs
            c, d = a + segs, b + segs
            T.append((a, c, b))
            T.append((b, c, d))
    return np.asarray(V), np.asarray(T, np.int64)


# ======================================================================================================================
# the pieces
# ======================================================================================================================
def crown_piece(person, body_T, groups):
    """A copper band over his brow and round his head (the half-helm's footprint, thin) and out of it TINES["count"]
    tall forked tines of green copper, leaning out a little, the tallest over the brow, each with a side branch and
    the storm's light at its points."""
    p = slab(person, "crown", body_T, groups, 1311)
    rng = np.random.default_rng(1312)
    V = np.asarray(p.V)
    score = V[:, 2]
    top = V[score >= np.percentile(score, 50)]
    c = top.mean(axis=0)
    parts = []
    count = TINES["count"]
    for k in range(count):
        a = -math.pi * 0.5 + 2.0 * math.pi * (k - (count - 1) * 0.5) / (count + 2.2)
        d = np.array([math.cos(a), math.sin(a), 0.0])
        rim = top[np.argmax(top @ d)]
        front = max(0.0, -float(d[1]))
        size = 0.62 + 0.38 * front
        length = TINES["tallest_m"] * size * (0.9 + 0.2 * rng.random()) / F
        out = unit(np.array([0.0, 0.0, 1.0]) + d * (0.32 + 0.1 * rng.random()))
        base = rim - out * 0.12 / F
        path = [base + out * length * t + d * 0.05 * length * t * t for t in np.linspace(0.0, 1.0, 5)]
        radii = np.array([1.0, 0.82, 0.62, 0.42, 0.10]) * TINES["base_m"] / F
        Vt, Tt, _ = tube_part(path, radii, 6, None, close=(True, True))
        tip = np.clip(((Vt - base) @ out) / max(length, 1e-9), 0.0, 1.0)
        col = bronze_colour(Vt, vertex_up(Vt, Tt), rng, base=COPPER_RGBA, wet=0.75)
        col[tip > 0.93] = GLOW_RGBA
        parts.append((Vt, Tt, col))
        # its fork: a branch off it at two thirds, bent out to the side
        side = unit(np.cross(out, [0.0, 0.0, 1.0]) if abs(out[2]) < 0.97 else np.array([1.0, 0.0, 0.0]))
        side = side * (1.0 if k % 2 == 0 else -1.0)
        b0 = base + out * length * (0.48 + 0.1 * rng.random())
        bd = unit(out * 0.8 + side * 0.65)
        bl = length * 0.42
        bpath = [b0 + bd * bl * t + out * 0.15 * bl * t * t for t in np.linspace(0.0, 1.0, 4)]
        Vb, Tb, _ = tube_part(bpath, np.array([0.55, 0.42, 0.26, 0.06]) * TINES["base_m"] / F, 5, None)
        tipb = np.clip(((Vb - b0) @ bd) / max(bl, 1e-9), 0.0, 1.0)
        colb = bronze_colour(Vb, vertex_up(Vb, Tb), rng, base=COPPER_RGBA, wet=0.75)
        colb[tipb > 0.9] = GLOW_RGBA
        parts.append((Vb, Tb, colb))
    q = add_parts(p, parts, STONE_TILE_M / F)
    q.facts["tines"] = count
    q.facts["crown_top_m"] = r6(float(np.concatenate([x[0] for x in parts])[:, 2].max()) * F)
    return q


def pauldron_piece(person, name, body_T, groups):
    """Bronze over a shoulder: the slab and three raised ribs across its top, their edges worn bright."""
    sd = name[-1]
    s = 1.0 if sd == "l" else -1.0
    p = slab(person, name, body_T, groups, 1321 if sd == "l" else 1327)
    rng = np.random.default_rng(1322 if sd == "l" else 1328)
    J = joints(person)
    sh = J["joint-%s-shoulder" % sd]
    V = np.asarray(p.V)
    out = unit(np.array([s * 0.7, 0.0, 0.72]))
    score = V @ out
    rim = V[score >= np.percentile(score, 62)]
    fb = np.array([0.0, 1.0, 0.0])
    t = rim @ fb
    lo, hi = np.percentile(t, 12), np.percentile(t, 88)
    parts = []
    for k in range(3):
        tt = lo + (hi - lo) * (k + 0.5) / 3.0
        sel = np.abs(t - tt) < (hi - lo) / 6.0
        pts = rim[sel] if sel.any() else rim
        a = pts[np.argmin(pts[:, 0] * s)]
        b = pts[np.argmax(pts[:, 0] * s)]
        path = [a + (b - a) * u + out * (0.10 / F) * math.sin(math.pi * u) for u in np.linspace(0.0, 1.0, 6)]
        rr = np.full(6, 0.16 / F)
        Vr, Tr, _ = tube_part(path, rr, 5, None)
        parts.append((Vr, Tr, bronze_colour(Vr, vertex_up(Vr, Tr), rng, edge=np.full(len(Vr), 0.45))))
    del sh
    return add_parts(p, parts, STONE_TILE_M / F)


def bell_piece(person):
    """The great bell slung on his back, mouth down (rigid to spine_03): a cast bronze bell, its waist and shoulder
    and lip, an inner wall (it is hollow), its crown's yoke of oak across his shoulder blades, two bronze straps from
    the yoke over his shoulders to his breast."""
    rng = np.random.default_rng(1331)
    J = joints(person)
    V = person.body_V()
    sh_l, sh_r = J["joint-l-shoulder"], J["joint-r-shoulder"]
    mid = 0.5 * (sh_l + sh_r)
    back_y = float(V[(np.abs(V[:, 0]) < 0.15 * person.S) & (np.abs(V[:, 2] - mid[2] + 0.1 * person.S)
                                                            < 0.12 * person.S)][:, 1].max())
    H = BELL["height_m"] / F
    R = BELL["mouth_r_m"] / F
    wall = BELL["wall_m"] / F
    top_z = mid[2] + BELL["top_gap_m"] / F
    c_y = back_y + R * 0.92 + BELL["back_gap_m"] / F
    axis_c = np.array([0.0, c_y, top_z])
    axis = np.array([0.0, 0.0, -1.0])
    # the profile from the crown's top round the shoulder, down the waist, flaring to the lip, under it, and back up
    # the inside (radius share of R, depth share of H)
    outer = [(0.02, -0.02), (0.30, 0.0), (0.52, 0.05), (0.60, 0.14), (0.62, 0.32), (0.66, 0.52), (0.76, 0.72),
             (0.92, 0.88), (1.00, 0.97), (1.02, 1.0)]
    inner = [(1.02 - wall / R, 1.0), (0.94, 0.95), (0.80, 0.86), (0.66, 0.70), (0.58, 0.48), (0.55, 0.26),
             (0.46, 0.10), (0.20, 0.06), (0.02, 0.06)]
    prof = [(rr * R, dd * H) for rr, dd in outer + inner]
    Vb, Tb = lathe(prof, axis_c, axis, 22, np.array([1.0, 0.0, 0.0]))
    # (the lathe's winding: outward faces on the outer wall)
    test = np.cross(Vb[Tb[:, 1]] - Vb[Tb[:, 0]], Vb[Tb[:, 2]] - Vb[Tb[:, 0]])
    cen = (Vb[Tb[:, 0]] + Vb[Tb[:, 1]] + Vb[Tb[:, 2]]) / 3.0
    radial = cen - (axis_c + axis * ((cen - axis_c) @ axis)[:, None])
    n_outer = 9 * 22 * 2
    if float((test[:n_outer] * radial[:n_outer]).sum()) < 0.0:
        Tb = Tb[:, [0, 2, 1]]
    up = vertex_up(Vb, Tb)
    depth = ((Vb - axis_c) @ axis) / H
    lip = _sstep(depth, 0.9, 1.0)
    col = bronze_colour(Vb, up, rng, edge=lip * 0.8, wet=0.7)
    parts = [(Vb, Tb, col)]
    # bands cast round the bell: at its shoulder, its waist and above the lip (sound bows)
    for dd, rr in ((0.14, 0.61), (0.52, 0.665), (0.86, 0.90)):
        parts.append(ring_part(axis_c + axis * dd * H, axis, rr * R + 0.06 / F, 0.13 / F,
                               np.asarray(COPPER_RGBA), segs=22, sides=5))
    # the yoke: an oak beam across the bell's crown, from shoulder blade to shoulder blade
    yl = np.array([sh_l[0] * 0.75, c_y - R * 0.18, top_z + 0.25 / F])
    yr = np.array([sh_r[0] * 0.75, c_y - R * 0.18, top_z + 0.25 / F])
    parts.append(tube_part([yr, 0.5 * (yl + yr) + np.array([0.0, 0.0, 0.1 / F]), yl], np.full(3, 0.42 / F), 6,
                           np.asarray(OAK_RGBA)))
    # the straps: from the yoke's ends over the shoulders' tops to the breast
    for s, end in ((1.0, yl), (-1.0, yr)):
        sd = "l" if s > 0 else "r"
        shj = J["joint-%s-shoulder" % sd]
        # (the top of the shoulder between the neck and the deltoid: not the head's side, not the neck)
        mk = person.bd.masks
        topv = V[(np.sign(V[:, 0]) == s) & (np.abs(V[:, 0] - shj[0] * 0.62) < 0.03 * person.S)
                 & (mk["m_head"] < 0.05) & (mk["m_neck"] < 0.3) & (V[:, 2] < shj[2] + 0.10 * person.S)]
        crest = topv[np.argmax(topv[:, 2])] if len(topv) else shj
        over = crest + np.array([0.0, 0.0, 0.10 / F])
        front = np.array([shj[0] * 0.45, float(V[:, 1].min()) * 0.5 + shj[1] * 0.5 - 0.20 / F,
                          shj[2] - 0.11 * person.S])
        path = [end, 0.5 * (end + over) + np.array([0.0, 0.0, 0.25 / F]), over,
                0.5 * (over + front) + np.array([0.0, -0.25 / F, 0.0]), front]
        parts.append(tube_part(path, np.full(5, 0.20 / F), 5, np.asarray(BRONZE_RGBA)))
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    p = rigid_piece("bell", Vm, Tm, Cm, UVm, "spine_03")
    p.facts = {"tris": int(len(Tm)), "height_m": BELL["height_m"], "mouth_r_m": BELL["mouth_r_m"]}
    p.bell_centre = axis_c + axis * 0.5 * H
    return p


def lodestone_piece(person, body_T, groups):
    """A slab of dark bronze over his breast and in it the lodestone: a dark rounded stone standing proud, bound in
    turns of copper wire, the storm's light in its cracks (the glow)."""
    p = slab(person, "lodestone", body_T, groups, 1341)
    rng = np.random.default_rng(1342)
    V = np.asarray(p.V)
    front = V[V[:, 1] < np.percentile(V[:, 1], 30)]
    c = front.mean(axis=0)
    c = front[np.argmin(np.linalg.norm(front - c, axis=1))]
    Vi, Ti = sb.icosphere(2)
    r = 0.95 / F
    jig = rng.uniform(0.86, 1.10, len(Vi))
    Vc = Vi * (jig[:, None] * r) * np.array([1.0, 0.62, 1.2]) + c + np.array([0.0, -0.32 / F, 0.0])
    import people_bake as pbk
    vein = pbk.fbm(Vi * 3.0, 2.0, 1343)
    col = np.tile(np.asarray(DARK_RGBA), (len(Vc), 1))
    col[np.abs(vein - 0.5) < 0.05] = GLOW_RGBA
    parts = [(Vc, sb.outward(Vc, Ti, c + np.array([0.0, -0.32 / F, 0.0])), col)]
    for k in range(4):
        tilt = unit(np.array([0.0, 1.0, 0.0]) + np.array([0.0, 0.0, 0.35 * (k - 1.5)]))
        parts.append(ring_part(c + np.array([0.0, -0.32 / F, (k - 1.5) * 0.30 / F]), np.array([0.0, 0.0, 1.0]) * 0.2
                               + tilt * 0.0 + np.array([0.0, 0.0, 1.0]), r * (0.95 - 0.12 * abs(k - 1.5)) * 1.02,
                               0.07 / F, np.asarray(COPPER_RGBA), segs=16, sides=4))
    q = add_parts(p, parts, STONE_TILE_M / F)
    q.facts["core_m"] = [r6(x * F) for x in c]
    return q


def bracer_piece(person, body_T, groups):
    """The right forearm in bronze, and copper wire wound round it in four bands (skinned to the forearm)."""
    p = slab(person, "bracer", body_T, groups, 1351)
    J = joints(person)
    el, wr = J["joint-r-elbow"], J["joint-r-hand"]
    a = unit(wr - el)
    L = float(np.linalg.norm(wr - el))
    V = person.body_V()
    parts = []
    for k in range(4):
        t = 0.28 + 0.14 * k
        c = el + (wr - el) * t
        near = V[np.linalg.norm(V - c, axis=1) < 0.06 * person.S]
        rad = float(np.percentile(np.linalg.norm((near - c) - np.outer((near - c) @ a, a), axis=1), 85)) if len(near) \
            else 0.035 * person.S
        parts.append(ring_part(c, a, rad + 0.32 / F, 0.08 / F, np.asarray(COPPER_RGBA), segs=14, sides=4))
    del L
    return add_parts(p, parts, STONE_TILE_M / F)


def greave_piece(person, name, body_T, groups):
    return slab(person, name, body_T, groups, 1361 if name.endswith("_l") else 1367)


def rod_piece(person):
    """The storm-rod (rigid to hand_r, design scale at the rest hand): a mast of black bog-oak through the right fist's
    grip landmark along the grip's line, ROD["butt_m"] below it (a bronze shoe at its foot) and ROD["head_m"] above,
    copper bands along it, and at its head a fork of three copper tines (the middle straight, the outer two curving
    out and up), the storm's light at their points."""
    import people_bake as pbk
    g, ax = person.grip["r"]
    ax = unit(ax)
    rng = np.random.default_rng(1371)
    ref = unit(np.cross(ax, [0.0, 0.0, 1.0]) if abs(ax[2]) < 0.95 else np.cross(ax, [1.0, 0.0, 0.0]))
    w = np.cross(ax, ref)
    B, Hh, R = ROD["butt_m"] / F, ROD["head_m"] / F, ROD["radius_m"] / F
    r_grip = person.grip_radius
    rings = 26
    s = np.linspace(-B, Hh, rings)
    base_r = np.interp(s, [-B, -B + 0.6 / F, 0.0, 0.6 * Hh, Hh], [R * 0.85, R, r_grip * 1.02, R * 1.05, R * 0.95])
    bend = np.outer(np.sin((s + B) / (B + Hh) * 3.1) * 0.012 * (B + Hh), ref)
    path = g + np.outer(s, ax) + bend
    phs = 2.0 * math.pi * np.arange(SHAFT_SIDES) / SHAFT_SIDES
    radii = np.zeros((rings, SHAFT_SIDES))
    for i in range(rings):
        q = np.stack([np.cos(phs), np.sin(phs), np.full(SHAFT_SIDES, s[i] * 0.5)], axis=1) * F
        radii[i] = base_r[i] * (1.0 + 0.08 * (pbk.fbm(q * [1.0, 1.0, 0.3], 2.0, 1373) - 0.5))
    Vs, Ts, _ring, _ang = sb.tube(path, radii, SHAFT_SIDES, close=(True, True), frame0=ref)
    parts = [(Vs, Ts, np.asarray(OAK_RGBA))]
    # the bands and the shoe
    for k in range(ROD["bands"]):
        t = -B * 0.55 + (B * 0.55 + Hh * 0.92) * k / (ROD["bands"] - 1)
        if abs(t) < 1.2 / F:
            continue
        c = g + ax * t + np.sin((t + B) / (B + Hh) * 3.1) * 0.012 * (B + Hh) * ref
        parts.append(ring_part(c, ax, float(np.interp(t, s, base_r)) + 0.04 / F, 0.10 / F, np.asarray(COPPER_RGBA),
                               segs=12, sides=4))
    foot = g - ax * B
    parts.append(tube_part([foot - ax * 0.05 / F, foot + ax * 0.5 / F, foot + ax * 1.1 / F],
                           np.array([0.9, 1.05, 1.0]) * R * 1.1, 8, np.asarray(BRONZE_RGBA), frame0=ref))
    # the fork: a collar, then three tines
    head = g + ax * Hh + np.sin(3.1) * 0.012 * (B + Hh) * ref
    parts.append(tube_part([head - ax * 0.9 / F, head - ax * 0.2 / F, head + ax * 0.4 / F],
                           np.array([1.15, 1.35, 1.1]) * R, 8, np.asarray(COPPER_RGBA), frame0=ref))
    TL, TR = ROD["tine_m"] / F, ROD["tine_r_m"] / F
    tines = []
    for k, side in enumerate((-1.0, 0.0, 1.0)):
        b0 = head + ax * 0.3 / F + ref * side * R * 0.9
        pts = []
        for t in np.linspace(0.0, 1.0, 6):
            out = side * (0.9 * t - 0.5 * t * t) * TL * 0.75
            pts.append(b0 + ax * TL * (1.0 if side == 0.0 else 0.82) * t + ref * out)
        Vt, Tt, _ = tube_part(pts, np.array([1.0, 0.9, 0.78, 0.6, 0.4, 0.08]) * TR * (1.15 if side == 0 else 1.0), 6,
                              None)
        tip = np.clip(((Vt - b0) @ ax) / max(TL * 0.82, 1e-9), 0.0, 1.0)
        col = bronze_colour(Vt, vertex_up(Vt, Tt), rng, base=COPPER_RGBA, wet=0.5)
        col[tip > 0.92] = GLOW_RGBA
        parts.append((Vt, Tt, col))
        tines.append(pts[-1])
    del w
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    p = rigid_piece("rod", Vm, Tm, Cm, UVm, "hand_r")
    p.facts = {"tris": int(len(Tm)), "length_m": r6((B + Hh + TL) * F), "butt_m": ROD["butt_m"],
               "head_m": ROD["head_m"]}
    p.head_point = head + ax * TL * 0.5
    p.butt_point = foot
    return p


def beard_piece(person):
    """His beard in three heavy braids from the jaw (rigid to the head): twisted tubes, bronze rings at their ends."""
    J = joints(person)
    V = person.body_V()
    m = person.bd.masks
    head = m["m_head"] > 0.6
    eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
    jaw = head & (V[:, 2] < eye[2] - 0.075 * person.S) & (V[:, 1] < eye[1] + 0.02 * person.S)
    pts = V[jaw] if jaw.any() else V[head][np.argsort(V[head][:, 2])[:20]]
    chin_y, chin_z = float(pts[:, 1].min()), float(pts[:, 2].min())
    parts = []
    for k, x in enumerate((-1.0, 0.0, 1.0)):
        target = np.array([x * 0.035 * person.S, chin_y + 0.012 * person.S, chin_z + abs(x) * 0.02 * person.S])
        b = pts[np.argmin(np.linalg.norm(pts - target, axis=1))]
        length = (2.6 if x == 0.0 else 2.0) / F
        n = 10
        path = []
        for i in range(n):
            t = i / (n - 1)
            path.append(b + np.array([x * 0.25 * t / F, (-0.35 - 0.2 * t) * t / F, -length * t]))
        path = np.asarray(path)
        radii = (0.34 - 0.12 * np.linspace(0.0, 1.0, n)) / F
        # (a braid: the radius beaten in twists along it)
        radii = radii * (1.0 + 0.16 * np.cos(np.linspace(0.0, 1.0, n) * 2.0 * math.pi * 3.0))
        parts.append(tube_part(path, radii, 6, np.asarray(BRAID_RGBA)))
        parts.append(ring_part(path[-2], unit(path[-1] - path[-3]), float(radii[-2]) * 1.15, 0.06 / F,
                               np.asarray(BRONZE_RGBA), segs=10, sides=4))
        del k
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    p = rigid_piece("beard", Vm, Tm, Cm, UVm, "head")
    p.facts = {"tris": int(len(Tm)), "braids": 3}
    return p


# ======================================================================================================================
# his skin: Stoneback's hide, drenched, and the lightning's scars
# ======================================================================================================================
def lightning_scars(person, rng, kd):
    """The branching scars the lightning has left (human metres, rest): random walks over the skin from a few roots
    (the left breast, the right shoulder, the left forearm, the back between the shoulder blades, the right thigh),
    each branching as it goes, every point snapped to the nearest skin vertex. [(a, b, width)] segments."""
    J = person.bd.joints
    V = person.bd.verts[:N]
    roots = [(J["joint-l-shoulder"] * np.array([0.55, 1.0, 1.0]) + np.array([0.0, -0.10, -0.12]), (0.2, -0.1, -1.0)),
             (J["joint-r-shoulder"] + np.array([0.0, 0.0, 0.03]), (-0.5, -0.2, -1.0)),
             (J["joint-l-elbow"] + np.array([0.0, 0.0, 0.0]), (0.6, 0.0, -1.0)),
             (0.5 * (J["joint-l-shoulder"] + J["joint-r-shoulder"]) + np.array([0.0, 0.12, -0.05]), (0.3, 0.2, -1.0)),
             (J["joint-r-upper-leg"] + np.array([-0.02, -0.04, -0.06]), (-0.2, -0.3, -1.0))]
    segs = []

    def walk(p, d, width, steps, depth):
        for _ in range(steps):
            d = unit(np.asarray(d) + rng.normal(0.0, 0.55, 3))
            q = p + d * rng.uniform(0.012, 0.028)
            q = V[kd.query(q)[1]]
            segs.append((p, q, width))
            if depth < 3 and rng.random() < 0.28:
                walk(q, unit(d + rng.normal(0.0, 0.9, 3)), width * 0.62, max(2, steps // 2), depth + 1)
            p = q
            width *= 0.93
    for p0, d0 in roots:
        p = V[kd.query(p0)[1]]
        walk(p, unit(d0), 0.0040, 16, 0)
    return segs


def storm_skin(out_dir, LV, LT, Luv, S, masks_fn, scars, hide_tris=None):
    """The repainted atlas's skin, drenched: slate grey with a cold blue in it, darker and cooler than a man's, the
    lightning's scars pale and branching over it (a little raised and pinker at their trunks), the scalp dark; the
    kilt's hide sodden dark."""
    import people_bake as pbk
    from PIL import Image
    paths = {k: os.path.join(out_dir, "%s_%s.png" % (KIND, k)) for k in ("albedo", "orm")}
    alb = np.asarray(Image.open(paths["albedo"]).convert("RGB")).astype(np.float64) / 255.0
    orm = np.asarray(Image.open(paths["orm"]).convert("RGB")).copy()
    skin_b = pr.band_byte("skin")
    tri, bar = pbk.raster(Luv, pr.ALBEDO_PX)
    ys, xs = np.nonzero(tri >= 0)
    t = tri[ys, xs]
    b = bar[ys, xs]
    P = np.einsum("nk,nkj->nj", b, LV[LT[t]]) / S
    nrm = np.cross(LV[LT[t, 1]] - LV[LT[t, 0]], LV[LT[t, 2]] - LV[LT[t, 0]])
    nrm /= np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-12)
    oy = np.clip((ys * pr.ORM_PX) // pr.ALBEDO_PX, 0, pr.ORM_PX - 1)
    ox = np.clip((xs * pr.ORM_PX) // pr.ALBEDO_PX, 0, pr.ORM_PX - 1)
    skin = orm[oy, ox, 2] == skin_b
    Ps, Ns = P[skin], nrm[skin]
    mk = masks_fn(Ps)
    col = alb[ys[skin], xs[skin]]
    grey = col.mean(axis=1, keepdims=True)
    col = col * 0.30 + grey * 0.70
    col = col * np.array([0.93, 0.95, 0.99])[None, :] * 0.84
    # wet streaks: darker runs down the body where the rain runs
    runs = _sstep(pbk.fbm(Ps * np.array([6.0, 6.0, 0.8]), 4.0, 1391), 0.50, 0.72)
    col *= (1.0 - 0.12 * runs)[:, None]
    # the scars: the distance to the nearest scar segment (in chunks), pale and branching
    sc = np.zeros(len(Ps))
    if scars:
        A = np.array([s_[0] for s_ in scars])
        Bq = np.array([s_[1] for s_ in scars])
        W = np.array([s_[2] for s_ in scars])
        AB = Bq - A
        L2 = np.maximum((AB * AB).sum(axis=1), 1e-12)
        for i0 in range(0, len(Ps), 4096):
            Pc = Ps[i0:i0 + 4096]
            AP = Pc[:, None, :] - A[None, :, :]
            tt = np.clip((AP * AB[None]).sum(axis=2) / L2[None], 0.0, 1.0)
            D = np.linalg.norm(AP - tt[..., None] * AB[None], axis=2)
            val = 1.0 - _sstep(D / W[None, :], 0.35, 1.0)
            sc[i0:i0 + 4096] = val.max(axis=1)
    sc *= 1.0 - 0.9 * mk["m_head"]
    scar_col = np.array([0.66, 0.68, 0.72])
    col = col * (1.0 - 0.85 * sc[:, None]) + scar_col[None, :] * 0.85 * sc[:, None]
    # the scalp and the brows dark (wet hair cropped close), the lips a little darker
    hair = np.clip(mk["m_scalp"] * 1.1, 0.0, 1.0)
    col = col * (1.0 - 0.6 * hair[:, None]) + np.array([0.10, 0.10, 0.11])[None, :] * 0.6 * hair[:, None]
    col *= (1.0 - 0.45 * np.clip(mk["m_brow"], 0.0, 1.0))[:, None]
    alb[ys[skin], xs[skin]] = np.clip(col, 0.0, 1.0)
    if hide_tris is not None:
        kh = hide_tris[t] & ~skin
        hc = alb[ys[kh], xs[kh]]
        g = hc.mean(axis=1, keepdims=True)
        hc = (hc * 0.55 + g * 0.45) * np.array([0.78, 0.80, 0.84])[None, :] * 0.8
        alb[ys[kh], xs[kh]] = np.clip(hc, 0.0, 1.0)
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))
    return float(sc.mean())


def tracks(poses, rest_export):
    """The clips' keys as the exporter takes them: every bone's local rotation and the pelvis's offset (his scale)."""
    out = {}
    R_pelvis = rest_export["pelvis"][:3, :3]
    for name, keys in poses.items():
        seq = []
        for p in keys:
            basis = {}
            for b in pr.BONES:
                q = p.basis(b)
                basis[b] = (q.w, q.x, q.y, q.z)
            seq.append({"basis": basis, "loc": {"pelvis": R_pelvis.T @ (p.offset * F)}})
        out[name] = seq
    return out


# ======================================================================================================================
# the build
# ======================================================================================================================
def build(out_dir, work_dir):
    import bpy
    import giant_body as gb
    import giant_garment as gg
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
    # (the moves read this module's ROD as "stormcaller": the same module when run as a script)
    sys.modules["stormcaller"] = sys.modules[__name__]
    import stormcaller_moves as mv
    from scipy.spatial import cKDTree
    sb.F = F
    sb.KIND = KIND
    sb.BARK_TILE_M = (2.4, 4.0)
    fbk._install_footprints()
    sb.PLATE_FORM.setdefault("plate_chest", fbk.CHEST_FORM)
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    times = {}
    sb.stone_hands()
    gg.BRAIES.update(sb.BELT)
    p0 = br.brute_person(VARIANT)
    if not p0.bd.masks:
        p0.bd.compute_masks(p0.weights)
    times["body"] = round(time.time() - t0, 1)
    _x, faces, _fuv = p0.bd.group("body")
    body_T = po.triangulate(faces)
    p0.normals = po.vertex_normals(p0.body_V(), body_T)
    p0.normals_h = p0.normals
    p0.grip_radius = sb.grip_radius(p0)
    # ---- the outfit and the shared mesh (Stoneback's torn hide kilt, the loincloth, the belt: sodden)
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, OUTFIT)
    garments = [po.garment_piece(w0, gid, p0, OUTFIT_MATERIAL[gid], kd0) for gid in order]
    garments = [sb.kilt_panels(g, p0, seed=131) if gid == "kilt" else g for g, gid in zip(garments, order)]
    reach_c = po.COVER_REACH_M * po.CULL_SLACK / pr.EXPORT_SCALE
    body, culled_skin = po.cull(po.body_piece(p0), garments, reach_c, protect=br.crotch_of(p0))
    kept = [po.cull(g, garments[i + 1:], reach_c)[0] for i, g in enumerate(garments)]
    src = po.merge([body] + kept)
    src.n_body = len(body.V)
    m0 = p0.bd.masks
    detail = np.zeros(len(src.V))
    detail[:src.n_body] = np.maximum(np.clip(m0["m_head"], 0, 1) * br.HEAD_DETAIL,
                                     np.clip(m0["m_hand"], 0, 1) * 0.45)[body.attach]
    eyes = po.eye_piece(p0)
    eyes.uv = po.eye_uv(eyes)
    extras = [eyes]
    budget = TRIS - sum(p.tris() for p in extras) - MARGIN_TRIS
    LV, LT, Lmat, _ = po.decimate(src.V, src.T, src.mat, budget, "_shared_" + KIND, detail=detail)
    Luv = po.unwrap(LV, LT, "_uv_" + KIND)
    tri, bary, offset = po.correspond(src, LV)
    lgroups = {b: po.interpolate(w, src.T, tri, bary) for b, w in src.groups.items()}
    MATS = po.MATS
    Vk = po.interpolate(src.V, src.T, tri, bary) + offset
    skin_sel = np.isin(Lmat, [MATS.index("skin"), MATS.index("lips")])
    zeros = np.zeros(len(Vk), np.int64)
    skin = po.Piece("skin", Vk, LT[skin_sel], Lmat[skin_sel], lgroups, zeros, Luv[skin_sel])
    cloth = po.compact_piece(po.Piece("cloth", Vk, LT[~skin_sel], Lmat[~skin_sel], lgroups, zeros, Luv[~skin_sel]))
    skin_c, _dropped = po.cull(skin, [cloth], reach_c, protect=br.crotch_of(p0))
    mesh = po.merge([skin_c, cloth] + [po.Piece(p.name, p.V, p.T, p.mat, p.groups, np.zeros(len(p.V), np.int64), p.uv)
                                       for p in extras])
    if mesh.tris() > TRIS:
        raise SystemExit("stormcaller: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the pieces
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(STORM_GAITS)
    holder = sb.Holder(p0)
    groups23 = pr.fold_weights(p0.groups53())
    # the rod's butt is as long as the grip stands over the ground when his arm hangs a little bent at his side (so it
    # rests on the ground there); its head is the rest of his height
    rr = p0.rest
    g_r, _ax = p0.grip["r"]
    grip_off = float(np.linalg.norm(np.asarray(g_r) - rr.head["hand_r"]))
    butt = float(rr.head["upperarm_r"][2]) - 0.90 * (holder.l1["r"] + holder.l2["r"]) - grip_off
    import stormcaller_moves as mv0
    clips_probe = __import__("clips")
    clips_probe.configure(step_m=STEP_M / F)
    for _ in range(2):
        # (where the idle can really put the grip: the butt is that long, so it rests on the ground there)
        ROD["butt_m"] = r6(butt * F)
        mv0.ROD_HEAD = mv0.ROD_BUTT = None
        probe = mv0.idle0(holder, rr)
        g_now, a_now = holder.grip_posed(probe, "r")
        butt = float(g_now[2]) / max(float(a_now[2]), 0.5) - 0.02 / F
    ROD["butt_m"] = r6(butt * F)
    ROD["head_m"] = r6(HEIGHT_M - ROD["butt_m"])
    pieces = {"crown": crown_piece(p0, body_T, groups23),
              "pauldron_l": pauldron_piece(p0, "pauldron_l", body_T, groups23),
              "pauldron_r": pauldron_piece(p0, "pauldron_r", body_T, groups23),
              "bell": bell_piece(p0), "lodestone": lodestone_piece(p0, body_T, groups23),
              "bracer": bracer_piece(p0, body_T, groups23),
              "greave_l": greave_piece(p0, "greave_l", body_T, groups23),
              "greave_r": greave_piece(p0, "greave_r", body_T, groups23),
              "rod": rod_piece(p0), "beard": beard_piece(p0)}
    log("pieces: " + ", ".join("%s %d" % (n, p.tris()) for n, p in pieces.items()))
    for name, p in pieces.items():
        if p.tris() > GEAR_BUDGET[name]:
            raise SystemExit("stormcaller: %s has %d triangles, over %d" % (name, p.tris(), GEAR_BUDGET[name]))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses
    mv.ROD_HEAD = pieces["rod"].head_point
    mv.ROD_BUTT = pieces["rod"].butt_point
    poses, gaits, checks = mv.make_poses(p0, pieces, holder)
    # ---- the bake, Stoneback's hide repainted over it, drenched and scarred
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(KIND, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras)])
    under = np.zeros(N)
    for name, (plate, _spec) in SLABS.items():
        under = np.maximum(under, np.clip(sb.plate_footprint(p0, plate) * 1.2, 0.0, 1.0))
    ukd = cKDTree(p0.bd.verts[:N])

    def under_fn(P):
        d, i = ukd.query(P, k=4)
        wgt = 1.0 / np.maximum(d, 1e-5)
        return (under[i] * wgt).sum(axis=1) / wgt.sum(axis=1)
    masks_fn = (lambda P: sb.masks_at(P, ukd, p0.bd.masks))
    look = {"masks": masks_fn, "scars": []}
    sb.repaint(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, under_fn,
               hide_tris=np.isin(Lmat, [MATS.index("leather"), MATS.index("dark_leather")]), look=look)
    scars = lightning_scars(p0, np.random.default_rng(1381), ukd)
    scar_share = storm_skin(out_dir, LV, LT, Luv, p0.S, masks_fn, scars,
                            hide_tris=np.isin(Lmat, [MATS.index("leather"), MATS.index("dark_leather")]))
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("stormcaller_body")
    metal = bpy.data.materials.new("stormcaller_metal")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in PLATE_ORDER + GEAR:
        p = pieces[name]
        o = br.skinned_object(name, p, arm, coll, metal, F)
        ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(p.rgba, np.float32).ravel())
        o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        info_p = {"node": name, "tris": p.tris(), "material": "metal", "bone": PIECE_BONE[name],
                  "plate": name in PLATE_ORDER}
        info_p.update(getattr(p, "facts", {}) or {})
        if name in WEAK_POINTS:
            info_p["region"] = WEAK_POINTS[name]
        piece_info[name] = info_p
    rest = pbody.rest_matrices(arm)
    Hr = rest["hand_r"]
    for key, pt in (("head_local", pieces["rod"].head_point), ("butt_local", pieces["rod"].butt_point)):
        gc = np.asarray(pt) * F
        piece_info["rod"][key] = [r6(x) for x in (Hr[:3, :3].T @ (gc - Hr[:3, 3]))]
    trk = tracks(poses, rest)
    G = pbody.fk(rest, pbody.parents_of(arm), trk["idle"][0]["basis"], trk["idle"][0]["loc"])
    idx4, w4 = pr.top4(mesh.groups, len(mesh.V))
    Pp = pbody.skin_points(mesh.V * F, idx4, w4, rest, G) / F
    Vf, Tf, _mf, uvf = po.decimate(Pp, mesh.T, mesh.mat, FAR_TRIS, "_far_" + KIND, uv=mesh.uv)
    far = po.mesh_object(KIND + "_far", Vf * F, Tf, None, uvf, coll)
    far.data.materials.clear()
    far.data.materials.append(mat)
    exported.append(far)
    path = os.path.join(out_dir, KIND + ".glb")
    sb.export_glb(path, exported)
    height = float(mesh.V[:, 2].max()) * F
    crown_top = float(pieces["crown"].V[:, 2].max()) * F
    b53 = p0.rig.data.bones
    knuckle = (np.asarray(b53["middle_01_l"].head_local) - np.asarray(b53["hand_l"].head_local)) * F
    reach = (b53["upperarm_l"].length + b53["lowerarm_l"].length) * F + float(np.linalg.norm(knuckle))
    info = {"kind": KIND, "height_m": HEIGHT_M, "export_scale": r6(F), "times": times, "tris_max": TRIS,
            "bake": bake_info, "outfit": list(order),
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget), "culled_skin": culled_skin},
            "variants": {KIND: {"index": 0, "tris": mesh.tris(), "verts": int(len(mesh.V)), "height_m": r6(height),
                                "height_with_crown_m": r6(crown_top), "game_height_m": HEIGHT_M,
                                "game_scale": r6(HEIGHT_M / height), "pieces": [p.name for p in extras],
                                "joints": {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES},
                                "reach_m": r6(reach), "far": {"node": KIND + "_far", "tris": int(len(Tf))}}},
            "pieces": piece_info, "plates": list(PLATE_ORDER), "weak_points": WEAK_POINTS,
            "detail": {"metal": "stoneback_stone"}, "detail_tile_m": {"metal": STONE_TILE_M},
            "glow_alpha": GLOW_RGBA[3], "checks": checks, "scars": {"segments": len(scars),
                                                                    "skin_share": r6(scar_share)},
            "used_by": ["enemy.stormcaller (D2: StormcallerRig)", "tools/stormcaller_stills.gd"]}
    for sd in ("l", "r"):
        g, ax = p0.grip[sd]
        Hs = rest["hand_" + sd]
        info["variants"][KIND]["grip_local_" + sd] = [r6(x) for x in (Hs[:3, :3].T @ (g * F - Hs[:3, 3]))]
        info["variants"][KIND]["grip_axis_" + sd] = [r6(x) for x in (Hs[:3, :3].T @ ax)]
    info["glb_bytes"] = os.path.getsize(path)
    worst = 0.0
    where = ""
    for name in ("walk", "idle", "slam", "sweep", "dormant", "call"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            Gk = pbody.fk(rest, pbody.parents_of(arm), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "hand_l", "head", "pelvis"):
                off = float(np.linalg.norm(Gk[b][:3, 3] - poses[name][kk].P[b] * F))
                if off > worst:
                    worst, where = off, "%s[%d] %s" % (name, kk, b)
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("stormcaller clips: the keys do not reproduce the solved poses (%.6f m off at %s)" % (
            worst, where))
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    import clips
    sb.CLIP_FRAMES = {n: len(k) - 1 for n, k in poses.items()}
    sb.export_clips(os.path.join(out_dir, KIND + "_clips.glb"), arm, coll, trk)
    info["clips"] = {"fps": clips.FPS, "step_m": r6(STEP_M), "conversion_error_m": r6(worst),
                     "clips": {n: {"frames": len(k) - 1, "loop": n in CLIP_LOOPS, "bones": len(pr.BONES),
                                   "partial": False} for n, k in poses.items()},
                     "keys": mv.KEYS,
                     "gaits": {n: {kk: (r6(vv * F) if kk.endswith("_m") else vv)
                                   for kk, vv in clips.measure_gait(g).items()} for n, g in sorted(gaits.items())}}
    times["export"] = round(time.time() - t0 - sum(times.values()), 1)
    info["seconds"] = round(time.time() - t0, 1)
    os.makedirs(work_dir, exist_ok=True)
    with open(os.path.join(work_dir, KIND + "_info.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log("%s: body %d, pieces %s in %.1f s" % (KIND, mesh.tris(), ", ".join("%s %d" % (n, e["tris"])
                                                                         for n, e in piece_info.items()), info["seconds"]))
    return info


if __name__ == "__main__":
    if len(sys.argv) < 3 or sys.argv[1] != KIND:
        raise SystemExit("usage: stormcaller.py stormcaller <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
