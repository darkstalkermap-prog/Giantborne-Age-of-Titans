"""The Rootwarden (B3): the Greywood's signature titan, an original warden of flesh, bark and root 21.3 m (70 ft) tall,
as an asset (``build_people.py --rootwarden``).

The giant kings set him over the Greywood; over the centuries the wood has grown into him. Underneath he is a living
body - the people's CC0 human with MakeHuman's macros, ``giant_body.proportioned`` with a table of his own and
``brute.reshape`` (``brute.py``) - so he moves as something alive, not a walking log: tall and long-limbed (long legs,
long arms, big hands, a small head carried a little forward, the shoulders rounded by age), gaunt rather than heavy.
His skin is bark-skin (the bake's skin band repainted: furrowed grey-brown bark along his limbs, lichen and moss over
the shoulders, the back and the crown of the head, pale amber sapwood under each plate). Over it, each its own
skinned mesh on the people's 23 bones:

  bark_shoulder_l, bark_shoulder_r
                living bark grown over each shoulder: a thick furrowed shell over the deltoid's cap and the trapezius,
                a second, smaller scale of bark shingled over it, shelf-fungi glowing at its lower edge
  bark_back     a broad shell of bark over the shoulder blades and down the spine, its furrows running down him
  bark_forearm_r
                bark wrapped round the right forearm (a bracer grown on)
  bark_shin_l, bark_shin_r
                bark grown down the front and sides of each shin over a knee-cap of burl
  bark_knot     the root-arm's knot: a great burl on the back of the left forearm where the roots leave him, split by
                glowing sap seams - the root-arm's heart (its break withers the roots: no regrowth for a long while)
  sap_<plate>   under each plate the sapwood it covers (amber, glowing): hidden while the plate holds, shown when it
                breaks (the weak point); covered again as the bark regrows
  roots         the root-arm: roots wound round the left forearm and the hand, running on past the fingers in a
                trailing bundle long enough to reach the ground from the hanging hand (his rooted stance drives them
                into the soil)
  antlers       a crown of branches grown from his brow and temples, mossed, with lichen hanging from them (rigid to
                the head)
  tree          a dead tree he tears out of the grove and hurls: shown only in the rip and the hurl (rigid to the right
                hand)
  rootwarden_far the idle's first key, decimated

The bark pieces are mapped round and along their limb on a tileable bark texture (``rootwarden_bark_albedo.png``,
``_normal.png``, 256 px, repeated ``BARK_TILE_M``; the furrows down V); the sapwood, the fungi and the sap seams are
vertex colours with alpha GLOW_ALPHA (stone_plate.gdshader's glow path: they shine).

Clips on his skeleton (``CLIP_FRAMES``; ``rootwarden_moves.py``): dormant (rooted, head bowed), idle, walk, run, roar,
uproot (phase 2: he tears his roots out of the ground), lash, erupt, snare, rip, hurl, stomp, reel, kneel, rise,
death.

``python rootwarden.py rootwarden <out dir> <work dir>`` writes rootwarden.glb, rootwarden_clips.glb, the atlas
(rootwarden_albedo.png 512 px, _normal.png, _orm.png 256 px), the bark textures and rootwarden_info.json.
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
import mh_data as mh  # noqa: E402
import people_roles as pr  # noqa: E402
import stoneback as sb  # noqa: E402

KIND = "rootwarden"
HEIGHT_M = 21.3                    # 70 ft: a stage-5 giant (14.63 m) looks up at him, a stage-6 (18.90 m) comes under
DESIGN = pr.DESIGN_HEIGHT_M
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.29 * HEIGHT_M           # a long, careful stride (6.2 m): long legs, carried level
TRIS = 9000
MARGIN_TRIS = 60
FAR_TRIS = 320
OUTFIT = ("loincloth",)
OUTFIT_MATERIAL = {"loincloth": "leather"}

# ---- the body ------------------------------------------------------------------------------------------------------
# an old, gaunt face: long, the cheeks hollow, the brow heavy and low, the nose long and narrow, the chin long
WARDEN_FACE = {"head/head-age-decr-incr": 1.0, "head/head-fat-decr-incr": -0.8, "head/head-oval": 0.6,
               "head/head-scale-horiz-decr-incr": -0.4, "cheek/cheek-bones-decr-incr": 0.9,
               "cheek/cheek-volume-decr-incr": -0.9, "chin/chin-height-decr-incr": 0.7,
               "chin/chin-prominent-decr-incr": 0.5, "nose/nose-scale-vert-decr-incr": 0.7,
               "nose/nose-scale-horiz-decr-incr": -0.4, "nose/nose-hump-decr-incr": 0.7,
               "eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -0.8,
               "forehead/forehead-trans-backward-forward": 0.8, "eyes/eye-bag-decr-incr": 0.8,
               "eyes/eye-scale-decr-incr": -0.5, "mouth/mouth-angles-down-up": -0.5,
               "mouth/mouth-scale-horiz-decr-incr": -0.2}
WARDEN_PROP = dict(legs=1.09, torso=0.99, neck=0.006, head=0.80, arms=1.12, hands=1.20, shoulders=0.010,
                   deltoids=0.0, trapezius=0.006, thighs=-0.05)
WARDEN_SHAPE = dict(hunch_deg=10.0, head_back_deg=7.0, jaw=(0.06, 0.006, 0.004), underbite_m=0.0, brow_m=0.030,
                    brow_band_m=0.014, nose=(0.010, 0.004), ears=0.0, hands=1.08, feet=1.10, gut_m=0.0,
                    tusks=False, leg_ease=(0.6, 0.35))
VARIANT = dict(name=KIND, macro=br._macro(78, 0.78, 0.42, african=0.35, asian=0.15, caucasian=0.5),
               face=br._face(1.4, **WARDEN_FACE), prop=WARDEN_PROP, shape=WARDEN_SHAPE, height_m=HEIGHT_M)
WARDEN_GAITS = {
    "warden_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.025, min_drop=0.015, lean_deg=3.0,
                        pelvis_pitch_deg=2.0, roll_deg=4.0, sway=0.06, arm_swing_deg=10.0, heel_rocker=0.16),
    "warden_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.05, min_drop=0.035, lean_deg=9.0,
                       pelvis_pitch_deg=5.0),
}

# ---- the colours (linear vertex colours; stone_plate.gdshader) ------------------------------------------------------
GLOW_ALPHA = 0.35                  # a vertex colour with this alpha glows (the shader's glow path)
SAP_RGBA = (0.92, 0.52, 0.12, GLOW_ALPHA)          # the sapwood and its seams: amber
FUNGUS_RGBA = (0.80, 0.56, 0.24, GLOW_ALPHA)       # the lantern-fungi: a warm, faint glow
MOSS_RGBA = (0.085, 0.105, 0.045, 0.5)             # moss tufts (a matte colour)
LICHEN_RGBA = (0.20, 0.21, 0.17, 0.5)
BARK_RGBA = (1.0, 1.0, 1.0, 1.0)                   # the bark texture as it is
ROOT_RGBA = (0.78, 0.66, 0.56, 1.0)                # the roots: browner, younger wood
ANTLER_RGBA = (1.15, 1.10, 1.02, 1.0)              # the crown's older, greyer wood
DEAD_RGBA = (1.30, 1.25, 1.18, 1.0)                # the dead tree's silvered wood
EARTH_RGBA = (0.115, 0.085, 0.060, 0.5)
BARK_TILE_M = (2.0, 3.2)           # the bark texture repeats every this many metres round and along a limb
DETAIL_PX = 256
SHARP_DEG = 38.0

# ---- the plates (real metres): (thickness, gap over the skin, rim chamfer width, furrows round, decimation budget,
# shingled over it: None or (inset share, thickness share), glowing fungi along its lower edge)
PLATES = {
    "bark_shoulder_l": dict(thick=0.44, gap=0.04, chamfer=0.30, furrows=7, budget=820, upper=(0.50, 0.42), fungi=2),
    "bark_shoulder_r": dict(thick=0.44, gap=0.04, chamfer=0.30, furrows=7, budget=820, upper=(0.50, 0.42), fungi=2),
    "bark_back": dict(thick=0.58, gap=0.05, chamfer=0.40, furrows=11, budget=980, upper=(0.50, 0.42), fungi=3),
    "bark_forearm_r": dict(thick=0.40, gap=0.04, chamfer=0.24, furrows=6, budget=520, upper=None, fungi=0),
    "bark_shin_l": dict(thick=0.46, gap=0.04, chamfer=0.26, furrows=6, budget=560, upper=None, fungi=1),
    "bark_shin_r": dict(thick=0.46, gap=0.04, chamfer=0.26, furrows=6, budget=560, upper=None, fungi=1),
    "bark_knot": dict(thick=1.15, gap=0.05, chamfer=0.30, furrows=5, budget=620, upper=None, fungi=0),
}
PLATE_ORDER = tuple(PLATES)
# the regions the fight package names (data/enemies/rootwarden.json): the plate -> its weak point's region
WEAK_POINTS = {"bark_shoulder_l": "shoulder_l", "bark_shoulder_r": "shoulder_r", "bark_back": "back",
               "bark_forearm_r": "forearm_r", "bark_shin_l": "shin_l", "bark_shin_r": "shin_r", "bark_knot": "knot"}
# the main bone of each piece (the rig's break: where its splinters fly from, which bone carries its fall)
PIECE_BONE = {"bark_shoulder_l": "upperarm_l", "bark_shoulder_r": "upperarm_r", "bark_back": "spine_03",
              "bark_forearm_r": "lowerarm_r", "bark_shin_l": "calf_l", "bark_shin_r": "calf_r",
              "bark_knot": "lowerarm_l", "roots": "hand_l", "antlers": "head", "tree": "hand_r"}
RIM_SINK_M = 0.08
SAP_BUDGET = 160
ROOTS = dict(count=9, trail_m=11.0, wrap_turns=1.15, r_m=(0.30, 0.05), segs=6, rings=16, tendrils=7)
ANTLERS = dict(main_m=3.6, r_m=0.24, tines=3, twigs=4, segs=6)
TREE = dict(length_m=13.0, r_m=0.80, grip_m=4.6, branches=5, roots=6, segs=12, rings=26)
GEAR_BUDGET = {"roots": 2600, "antlers": 2000, "tree": 1500}
GEAR = ("roots", "antlers", "tree")

CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32}
CLIP_LOOPS = ("idle", "walk", "run")


def log(*a):
    print("[rootwarden]", *a, flush=True)


r6 = br.r6
unit = sb.unit
_sstep = br._sstep


# ======================================================================================================================
# helpers (design scale)
# ======================================================================================================================
def colour(n, rgba):
    return np.tile(np.asarray(rgba, np.float64), (n, 1))


def merge(parts):
    """[(V, T, rgba (n,4), corner uv (m,3,2) or None)] -> V, T, rgba, uv (a box map where None)."""
    Vs, Ts, Cs, UVs = [], [], [], []
    off = 0
    for V, T, C, uv in parts:
        V = np.asarray(V, np.float64)
        T = np.asarray(T, np.int64)
        Ts.append(T + off)
        Vs.append(V)
        Cs.append(np.asarray(C, np.float64))
        UVs.append(sb.box_uv(V, T, BARK_TILE_M[0] / F) if uv is None else np.asarray(uv, np.float64))
        off += len(V)
    return np.concatenate(Vs), np.concatenate(Ts), np.concatenate(Cs), np.concatenate(UVs)


def piece_of(name, V, T, rgba, uv, groups, src=None):
    import people_outfit as po
    p = po.Piece(name, V, T, np.full(len(T), po.MATS.index("metal")), groups,
                 np.full(len(V), -1) if src is None else src)
    p.uv = uv
    p.rgba = rgba
    return p


def frame_of(axis):
    """Two unit vectors across ``axis`` (the first in the plane of the axis and +Y, his back)."""
    a = unit(axis)
    ref = np.array([0.0, 1.0, 0.0]) if abs(float(a[1])) < 0.9 else np.array([1.0, 0.0, 0.0])
    u = unit(ref - a * float(ref @ a))
    return u, np.cross(a, u)


def cyl_coords(P, origin, axis):
    """(along (n,), round (n,) radians, radius (n,)) of points P about the line through ``origin`` along ``axis``."""
    a = unit(axis)
    u, w = frame_of(a)
    Q = P - origin
    along = Q @ a
    R = Q - np.outer(along, a)
    return along, np.arctan2(R @ w, R @ u), np.linalg.norm(R, axis=1)


def wood_uv(V, T, origin, axis, tile):
    """Corner UVs round (u) and along (v) a line: the bark's furrows run along the limb (the texture's V); the seam's
    corners kept on one side."""
    along, ang, rad = cyl_coords(V, origin, axis)
    circ = 2.0 * math.pi * max(float(np.median(rad)), 1e-6)
    C = np.stack([ang / (2.0 * math.pi), along / tile[1]], axis=-1)[T]
    du = C[..., 0] - C[:, :1, 0]
    C[..., 0] = np.where(du > 0.5, C[..., 0] - 1.0, np.where(du < -0.5, C[..., 0] + 1.0, C[..., 0]))
    C[..., 0] *= circ / tile[0]
    return C


def tube_wood(path, radii, segs, close=(True, True), frame0=None, rgba=BARK_RGBA):
    V, T, ring, ang = sb.tube(path, radii, segs, close=close, frame0=frame0)
    path = np.asarray(path, np.float64)
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    r = np.asarray(radii, np.float64)
    circ = 2.0 * math.pi * float((r.mean(axis=1) if r.ndim == 2 else r).mean())
    tile = (BARK_TILE_M[0] / F, BARK_TILE_M[1] / F)
    C = np.stack([ang / (2.0 * math.pi), s[ring] / tile[1]], axis=-1)[T]
    du = C[..., 0] - C[:, :1, 0]
    C[..., 0] = np.where(du > 0.5, C[..., 0] - 1.0, np.where(du < -0.5, C[..., 0] + 1.0, C[..., 0]))
    C[..., 0] *= circ / tile[0]
    return V, T, colour(len(V), rgba), C


def blob(c, radius, rng, squash=(1.0, 1.0, 1.0), rough=0.3, subdiv=1):
    """A lumpy ball (moss, a clod, a fungus's cap) at ``c``."""
    import people_bake as pbk
    V, T = sb.icosphere(subdiv)
    n = pbk.fbm(V * 1.6 + rng.uniform(0, 9, 3), 2.0, int(rng.integers(1, 999))) - 0.5
    V = c + V * (radius * (1.0 + rough * n))[:, None] * np.asarray(squash)
    return V, sb.outward(V, T, c)


def shelf(c, n, up, radius, rng):
    """A shelf-fungus (a lantern-fungus): a thick bracket standing out from the bark at ``c`` along its normal ``n``,
    its domed cap facing ``up`` (tan, textured), its underside glowing (GLOW_ALPHA). Returns (V, T, rgba)."""
    n = unit(n)
    up = unit(up - n * float(up @ n))
    side = np.cross(up, n)
    k = 11
    ang = np.linspace(-math.pi * 0.6, math.pi * 0.6, k)
    rr = radius * (1.0 + 0.12 * rng.normal(0, 1, k))
    rim = np.array([c + n * (r * math.cos(a)) + side * (r * math.sin(a) * 1.15) for a, r in zip(ang, rr)])
    mid = np.array([c + (p - c) * 0.55 + up * radius * 0.42 for p in rim])
    top_c = c + n * radius * 0.25 + up * radius * 0.55
    bot_c = c + n * radius * 0.15 - up * radius * 0.10
    V = np.concatenate([[top_c, bot_c], mid, rim + up * radius * 0.06, rim - up * radius * 0.06])
    T = []
    m0, r0, b0 = 2, 2 + k, 2 + 2 * k
    for i in range(k - 1):
        T.append((0, m0 + i, m0 + i + 1))
        T += [(m0 + i, r0 + i, r0 + i + 1), (m0 + i, r0 + i + 1, m0 + i + 1)]
        T += [(r0 + i, b0 + i, b0 + i + 1), (r0 + i, b0 + i + 1, r0 + i + 1)]
        T.append((1, b0 + i + 1, b0 + i))
    V = np.asarray(V)
    T = sb.outward(V, np.asarray(T, np.int64), c - n * radius * 0.2)
    rgba = np.zeros((len(V), 4))
    rgba[:] = (1.25, 1.05, 0.80, 1.0)
    rgba[[1] + list(range(b0, b0 + k))] = FUNGUS_RGBA
    return V, T, rgba


# ======================================================================================================================
# the plates: living bark over the body
# ======================================================================================================================
def plate_frame(person, name):
    """The line the plate's furrows run along: (origin, axis) in design metres."""
    S = person.S
    J = {k: v * S for k, v in person.bd.joints.items()}
    if name.startswith("bark_shoulder"):
        sd = name[-1]
        return J["joint-%s-shoulder" % sd], J["joint-%s-elbow" % sd] - J["joint-%s-shoulder" % sd]
    if name == "bark_back":
        return J["joint-spine-2"], np.array([0.0, 0.0, 1.0])
    if name in ("bark_forearm_r", "bark_knot"):
        sd = "r" if name.endswith("_r") else "l"
        return J["joint-%s-elbow" % sd], J["joint-%s-hand" % sd] - J["joint-%s-elbow" % sd]
    sd = name[-1]
    return J["joint-%s-knee" % sd], J["joint-%s-ankle" % sd] - J["joint-%s-knee" % sd]


def plate_footprint(person, name):
    """(n,) footprint weight (0..1) of the body's vertices for plate ``name`` (human metres)."""
    import people_bake as pbk
    bd = person.bd
    V = bd.verts[:N]
    J = bd.joints
    m = bd.masks
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    nb = person.normals_h
    lobes = pbk.fbm(V * [1.0, 1.0, 0.7], 14.0, 401) - 0.5       # an irregular, grown edge
    if name.startswith("bark_shoulder"):
        s = 1.0 if name.endswith("_l") else -1.0
        sd = "l" if s > 0 else "r"
        sh, el = J["joint-%s-shoulder" % sd], J["joint-%s-elbow" % sd]
        arm_t = ((V - sh) @ unit(el - sh)) / float(np.linalg.norm(el - sh))
        c = sh + np.array([s * 0.0, 0.012, 0.045])
        Q = V - c
        d = np.sqrt((Q[:, 0] / 0.17) ** 2 + (Q[:, 1] / 0.16) ** 2 + (Q[:, 2] / 0.14) ** 2)
        up_out = (nb[:, 2] + 0.8 * s * nb[:, 0] + 0.2 * nb[:, 1]) > 0.10
        w = (1.0 - _sstep(d + 0.12 * lobes, 0.80, 1.0)) * (np.sign(x) == s) * up_out
        w *= 1.0 - _sstep(arm_t + 0.08 * lobes, 0.36, 0.46)
        w *= _sstep(s * x, abs(sh[0]) * 0.28, abs(sh[0]) * 0.40)
        w *= 1.0 - _sstep(-y + sh[1] + 0.3 * lobes * 0.1, 0.06, 0.10) * (nb[:, 1] < -0.4)
        w *= (m["m_head"] < 0.1) & (m["m_hand"] < 0.1)
        return np.clip(w, 0.0, 1.0)
    if name == "bark_back":
        sh = 0.5 * (J["joint-l-shoulder"] + J["joint-r-shoulder"])
        sp = J["joint-spine-3"]
        top = sh[2] + 0.05
        low = sp[2] - 0.01
        half = abs(J["joint-l-shoulder"][0]) * 0.95
        w = (1.0 - _sstep(np.abs(x) + 0.03 * lobes, half * 0.80, half))
        # the lower edge rises to a point over the spine's sides (grown down the spine)
        lowz = low + 0.12 * _sstep(np.abs(x), 0.03, half * 0.7) + 0.02 * lobes
        w *= _sstep(z, lowz, lowz + 0.03) * (1.0 - _sstep(z, top - 0.03, top))
        w *= _sstep(nb[:, 1], -0.05, 0.25) * (y > sp[1] - 0.03)
        w *= (m["m_upperarm"] < 0.5) & (m["m_head"] < 0.1) & (m["m_neck"] < 0.5)
        return np.clip(w, 0.0, 1.0)
    if name in ("bark_forearm_r", "bark_knot"):
        sd = "r" if name.endswith("_r") else "l"
        s = 1.0 if sd == "l" else -1.0
        el, wr = J["joint-%s-elbow" % sd], J["joint-%s-hand" % sd]
        a = wr - el
        L = float(np.linalg.norm(a))
        t = ((V - el) @ (a / L)) / L
        Q = V - (el + np.outer(np.clip(t, 0, 1), a))
        Q -= np.outer(Q @ (a / L), a / L)
        dors = unit(np.array([s * 0.55, 0.45, 0.70]))
        facing = (Q / np.maximum(np.linalg.norm(Q, axis=1, keepdims=True), 1e-9)) @ dors
        side = (np.sign(x) == s) * (m["m_forearm"] + m["m_hand"] > 0.5) * (m["m_hand"] < 0.2)
        if name == "bark_knot":
            # a round burl on the back of the forearm, a little below its middle
            d = np.sqrt(((t - 0.46) / 0.24) ** 2 + ((1.0 - facing) / 0.95) ** 2)
            return np.clip((1.0 - _sstep(d + 0.25 * lobes, 0.80, 1.0)) * side, 0.0, 1.0)
        w = _sstep(t + 0.06 * lobes, 0.10, 0.17) * (1.0 - _sstep(t + 0.06 * lobes, 0.80, 0.88))
        w *= _sstep(facing + 0.4 * lobes, -0.65, -0.40) * side
        return np.clip(w, 0.0, 1.0)
    if name.startswith("bark_shin"):
        sd = name[-1]
        s = 1.0 if sd == "l" else -1.0
        kn, an = J["joint-%s-knee" % sd], J["joint-%s-ankle" % sd]
        a = an - kn
        L = float(np.linalg.norm(a))
        t = ((V - kn) @ (a / L)) / L
        Q = V - (kn + np.outer(np.clip(t, 0, 1), a))
        front = -Q[:, 1] / np.maximum(np.linalg.norm(Q[:, :2], axis=1), 1e-9)
        w = _sstep(t + 0.05 * lobes, -0.10, -0.03) * (1.0 - _sstep(t + 0.05 * lobes, 0.74, 0.82))
        w *= _sstep(front + 0.3 * lobes, 0.20, 0.45)
        w *= (np.sign(x) == s) * ((m["m_lowerleg"] > 0.5) | ((t < 0.05) & (m["m_upperleg"] > 0.2)))
        return np.clip(w, 0.0, 1.0)
    raise KeyError(name)


def furrows(P, origin, axis, count, seed, knot=False):
    """(n,) 0..1 the bark's ridges at P: meandering fissures (a ridged noise stretched along the limb), about
    ``count`` round it, between broad ridges; a knot's burl swirls round its centre instead."""
    import people_bake as pbk
    along, ang, _rad = cyl_coords(P, origin, axis)
    if knot:
        ang = ang + 2.2 * np.sin(along * 9.0)
    c = count / (2.0 * math.pi)
    q = np.stack([np.cos(ang) * c, np.sin(ang) * c, along * 1.6], -1)
    n1 = pbk.fbm(q, 1.0, seed, 3)
    fiss = 1.0 - _sstep(np.abs(n1 - 0.5), 0.0, 0.075)
    n2 = pbk.fbm(q * 1.9 + 3.1, 1.0, seed + 1, 2)
    fiss = np.maximum(fiss, 0.6 * (1.0 - _sstep(np.abs(n2 - 0.5), 0.0, 0.04)))
    return 1.0 - fiss


def shell_mesh(P, Nn, src, T, base, t, sink):
    """A shell over the patch (P on the skin, normals Nn, T): its top ``base`` + Nn x t, its walls from the top's
    outline down to ``sink`` under the patch's outline. Returns (V, T, src, top) with the top's points first."""
    n = len(P)
    top = base + Nn * t[:, None]
    be = sb.boundary_edges(T)
    ub = np.unique(be)
    rmap = -np.ones(n, np.int64)
    rmap[ub] = n + np.arange(len(ub))
    Vall = np.concatenate([top, P[ub] - Nn[ub] * sink])
    rim_T = []
    for a, b in be.tolist():
        rim_T += [(b, a, rmap[a]), (b, rmap[a], rmap[b])]
    Tall = np.concatenate([T, np.asarray(rim_T, np.int64).reshape(-1, 3)])
    nrm = np.cross(Vall[Tall[:, 1]] - Vall[Tall[:, 0]], Vall[Tall[:, 2]] - Vall[Tall[:, 0]])
    if float(np.einsum("ij,ij->i", nrm[:len(T)], Nn[T].mean(axis=1)).sum()) < 0:
        Tall = Tall[:, ::-1]
    return Vall, Tall, np.concatenate([src, src[ub]]), top


def patch_of(person, w, body_T, subdiv):
    """The body's patch where ``w`` > 0.12, split ``subdiv`` times, and the footprint read at its points."""
    from scipy.spatial import cKDTree
    Vb = person.body_V()
    Nb = person.normals
    region = w > 0.12
    Tk = body_T[region[body_T].any(axis=1)]
    used = np.unique(Tk)
    remap = -np.ones(N, np.int64)
    remap[used] = np.arange(len(used))
    T = remap[Tk]
    P, Nn, src = Vb[used], Nb[used], used
    for _ in range(subdiv):
        P, Nn, src, T = sb.subdivide(P, Nn, src, T)
    kd = cKDTree(Vb)
    dd, ii = kd.query(P, k=3)
    wt = 1.0 / np.maximum(dd, 1e-9)
    wp = (w[ii] * wt).sum(axis=1) / wt.sum(axis=1)
    return P, Nn, src, T, wp


def bark_piece(person, name, body_T, groups, seed):
    """A plate of living bark (PLATES) as a people_outfit Piece (design scale): a furrowed shell grown over the
    skin, a second scale shingled over a shoulder's or the back's upper part, fungi along its lower edge; and its
    sapwood (``sap_<name>``: the patch it covers, glowing) as a second Piece."""
    import people_outfit as po
    from scipy.spatial import cKDTree
    spec = PLATES[name]
    thick, gap, chamfer_w = spec["thick"] / F, spec["gap"] / F, spec["chamfer"] / F
    S = person.S
    rng = np.random.default_rng(seed)
    w = plate_footprint(person, name)
    knot = name == "bark_knot"
    P, Nn, src, T, wp = patch_of(person, w, body_T, 2 if knot or "forearm" in name else 1)
    f = (wp - 0.5) * 0.12 * S
    Pl, Nl, sl, Tl, _ul = sb.snap_patch(P, Nn, src, T, f)
    # the normals smoothed over the patch (a shell grown over the body's form, not its every crease)
    Ns = Nl.copy()
    u, _c = sb.edges_of(Tl)
    for _ in range(10):
        acc = Ns.copy()
        np.add.at(acc, u[:, 0], Ns[u[:, 1]])
        np.add.at(acc, u[:, 1], Ns[u[:, 0]])
        Ns = acc / np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
    origin, axis = plate_frame(person, name)
    bnd = np.zeros(len(Pl), bool)
    ue, ce = sb.edges_of(Tl)
    bnd[ue[ce == 1].ravel()] = True
    dist = sb.boundary_distance(Pl, Tl, bnd)
    ridge = furrows(Pl, origin, axis, spec["furrows"], seed + 3, knot)
    if knot:
        # the burl: domed over its middle, lumpy, its furrows swirling
        dmax = max(float(dist.max()), 1e-6)
        dome = np.sqrt(np.clip(dist / dmax, 0.0, 1.0)) * (1.0 + 0.25 * (__import__("people_bake").fbm(Pl, 25.0,
                                                                                                        seed + 5) - 0.5))
        t = thick * (0.30 + 0.70 * dome) * (0.78 + 0.22 * ridge)
    else:
        t = thick * (0.45 + 0.55 * np.sqrt(np.clip(ridge, 0.0, 1.0)))
    t = t * (0.45 + 0.55 * _sstep(dist, 0.0, chamfer_w))
    base = Pl + Ns * gap
    V1, T1, s1, top1 = shell_mesh(Pl, Ns, sl, Tl, base, t, RIM_SINK_M / F)
    layers = [(V1, T1, s1, ridge, top1)]
    if spec["upper"] is not None:
        inset, share = spec["upper"]
        # the upper scale: the plate's upper part, grown over the lower (its edge lobed)
        import people_bake as pbk
        zt = float(np.percentile(Pl[:, 2], 100.0 * inset))
        lob = (pbk.fbm(Pl, 30.0, seed + 7) - 0.5) * 0.05 * S
        fu = np.minimum(dist - chamfer_w * 0.9, (Pl[:, 2] - zt) + lob)
        Pu, Nu, su, Tu, uu = sb.snap_patch(Pl, Ns, sl, Tl, fu)
        bed = top1[uu] - Nu * (thick * 0.25)
        bu = np.zeros(len(Pu), bool)
        eu, cu = sb.edges_of(Tu)
        bu[eu[cu == 1].ravel()] = True
        du = sb.boundary_distance(Pu, Tu, bu)
        ru = furrows(Pu, origin, axis, spec["furrows"] + 2, seed + 11)
        tu = thick * share * (0.7 + 0.3 * ru) * (0.35 + 0.65 * _sstep(du, 0.0, chamfer_w * 0.8)) + thick * 0.25
        V2, T2, s2, top2 = shell_mesh(Pu, Nu, su, Tu, bed, tu, 0.0)
        V2[len(top2):] = bed[np.unique(sb.boundary_edges(Tu))] - Nu[np.unique(sb.boundary_edges(Tu))] * (0.3 * thick)
        layers.append((V2, T2, s2, ru, top2))
    # merged and decimated; colours: the bark (its furrows' floors darker), sap seams in a knot's furrows
    Vs, Ts, Ss, Rs = [], [], [], []
    for Vx, Tx, sx, rx, topx in layers:
        Ts.append(Tx + sum(len(v) for v in Vs))
        Vs.append(Vx)
        Ss.append(sx)
        Rs.append(np.concatenate([rx, np.zeros(len(Vx) - len(rx))]))
    Vall, Tall, src_all, ridge_all = np.concatenate(Vs), np.concatenate(Ts), np.concatenate(Ss), np.concatenate(Rs)
    mat = np.full(len(Tall), po.MATS.index("metal"))
    fungi_n = spec["fungi"]
    budget = spec["budget"] - fungi_n * 66
    Vd, Td, _md, _uv = po.decimate(Vall, Tall, mat, budget, "_bark_" + name, symmetric=False)
    near = cKDTree(Vall).query(Vd)[1]
    src_d = src_all[near]
    rd = ridge_all[near]
    uv = wood_uv(Vd, Td, origin, axis, (BARK_TILE_M[0] / F, BARK_TILE_M[1] / F))
    shade = 0.62 + 0.38 * rd
    rgba = np.concatenate([np.repeat(shade[:, None], 3, axis=1), np.ones((len(Vd), 1))], axis=1)
    if knot:
        seam = rd < 0.35
        rgba[seam] = SAP_RGBA
    parts = [(Vd, Td, rgba, uv)]
    srcs = [src_d]
    # the lantern-fungi along the lower edge of the top shell
    if fungi_n:
        top = top1
        lowish = np.nonzero(bnd)[0]
        order = lowish[np.argsort(top[lowish, 2])]
        picks = []
        for k in order:
            if all(np.linalg.norm(top[k] - top[j]) > 0.06 * S for j in picks):
                picks.append(k)
            if len(picks) >= fungi_n:
                break
        for k in picks:
            r = (0.42 + 0.18 * rng.random()) / F
            c = top[k] + Ns[k] * (0.05 / F) - np.array([0, 0, 0.04 / F])
            Vf, Tf, Cf = shelf(c, Ns[k], np.array([0.0, 0.0, 1.0]), r, rng)
            parts.append((Vf, Tf, Cf, None))
            srcs.append(np.full(len(Vf), sl[k]))
    Vm, Tm, Cm, UVm = merge(parts)
    srcq = np.concatenate(srcs)
    g = {b: wv[srcq] for b, wv in groups.items()}
    g = sb.stiffen(g, Tm, len(Vm), 5)
    piece = piece_of(name, Vm, Tm, Cm, UVm, g, srcq)
    piece.facts = {"tris": int(len(Tm)), "layers": len(layers), "fungi": fungi_n, "body_vertices": int(len(Pl)),
                   "thick_m": r6(spec["thick"]), "centre_m": [r6(v * F) for v in Vd.mean(axis=0)]}
    # the sapwood under it: the patch a little inside its outline, just over the skin
    fs = f - 0.010 * S
    Ps, Nsap, ss, Tsap, _us = sb.snap_patch(P, Nn, src, T, fs)
    Psap = Ps + Nsap * (gap * 0.45)
    msap = np.full(len(Tsap), po.MATS.index("metal"))
    Vsd, Tsd, _m2, _u2 = po.decimate(Psap, Tsap, msap, SAP_BUDGET, "_sap_" + name, symmetric=False)
    near2 = cKDTree(Psap).query(Vsd)[1]
    s_src = ss[near2]
    import people_bake as pbk
    glow = 0.75 + 0.5 * pbk.fbm(Vsd, 30.0, seed + 13)
    rs = np.concatenate([np.clip(np.asarray(SAP_RGBA[:3])[None, :] * glow[:, None], 0.0, 1.0),
                         np.full((len(Vsd), 1), GLOW_ALPHA)], axis=1)
    gs = {b: wv[s_src] for b, wv in groups.items()}
    sap = piece_of("sap_" + name, Vsd, Tsd, rs, sb.box_uv(Vsd, Tsd, BARK_TILE_M[0] / F), gs, s_src)
    sap.facts = {"tris": int(len(Tsd)), "plate": name}
    return piece, sap


# ======================================================================================================================
# the root-arm, the crown of branches, the dead tree
# ======================================================================================================================
def roots_piece(person, groups, kd):
    """The root-arm: roots wound round the left forearm and hand (on the weights of the skin under them), running on
    past the fingers in a trailing bundle (rigid to the hand) long enough to reach the ground from the hanging hand."""
    import people_bake as pbk
    rng = np.random.default_rng(611)
    J = person.bd.joints
    S = person.S
    Vb = person.body_V()
    # (design units: the body's own; joints are in human m: to design by S)
    el, wr = J["joint-l-elbow"] * S, J["joint-l-hand"] * S
    tip_dir = unit(wr - el)
    hand = Vb[(person.bd.masks["m_hand"] > 0.5) & (Vb[:, 0] > 0)]
    fingers = hand[np.argmax(hand @ tip_dir)]
    u0, w0 = frame_of(tip_dir)
    trail = ROOTS["trail_m"] / F
    count = ROOTS["count"]
    parts, srcs, rigid_from = [], [], []
    r_base, r_tip = ROOTS["r_m"][0] / F, ROOTS["r_m"][1] / F
    for k in range(count):
        ph0 = 2.0 * math.pi * k / count + rng.uniform(-0.2, 0.2)
        start_t = rng.uniform(-0.05, 0.25)
        turns = ROOTS["wrap_turns"] * rng.uniform(0.6, 1.2) * (1 if k % 2 else -1)
        pts = []
        # wound round the forearm: from the elbow's side down to the wrist, on the skin
        steps = 9
        for i in range(steps):
            s = start_t + (1.0 - start_t) * i / (steps - 1)
            c = el + (wr - el) * s
            ph = ph0 + turns * 2.0 * math.pi * s
            d = math.cos(ph) * u0 + math.sin(ph) * w0
            # the skin's surface along that direction (the nearest body point to a ray from the axis)
            probe = c + d * 0.12 * S
            near = Vb[kd.query(probe, k=6)[1]]
            surf = near[np.argmax((near - c) @ d)]
            pts.append(surf + d * (0.05 / F + r_base * 0.9))
        n_wrap = len(pts)
        # over the back of the hand, then on past the fingers, spreading and hanging, kinked
        spread = rng.uniform(0.15, 0.45)
        side = math.cos(ph0) * u0 + math.sin(ph0) * w0
        last = pts[-1]
        for i in range(1, ROOTS["rings"] - steps + 1):
            q = i / (ROOTS["rings"] - steps)
            along = float((fingers - wr) @ tip_dir) * 0.8 + trail * (q ** 1.1) * rng.uniform(0.85, 1.1)
            p = wr + tip_dir * along + side * (spread * trail * 0.10 * q) \
                + (u0 * rng.normal(0, 1) + w0 * rng.normal(0, 1)) * (0.04 * trail * q)
            pts.append(0.5 * (p + last) if i == 1 else p)
            last = p
        pts = np.asarray(pts)
        knot = 1.0 + 0.25 * np.sin(np.arange(len(pts)) * 1.9 + k)
        rr = np.interp(np.arange(len(pts)), [0, n_wrap - 1, len(pts) - 1], [r_base * 0.8, r_base, r_tip]) * knot
        rr *= rng.uniform(0.75, 1.15)
        V, T, C, uv = tube_wood(pts, rr, ROOTS["segs"], close=(True, True), rgba=ROOT_RGBA)
        ring = np.repeat(np.arange(len(pts)), ROOTS["segs"])
        ring = np.concatenate([ring, [0, len(pts) - 1]])
        parts.append((V, T, C, uv))
        rigid_from.append(ring >= n_wrap)
        srcs.append(kd.query(V)[1])
    # tendrils: thin roots off the bundle's end
    for k in range(ROOTS["tendrils"]):
        a0 = wr + tip_dir * (trail * rng.uniform(0.55, 0.85))
        d = unit(tip_dir + (u0 * rng.normal(0, 1) + w0 * rng.normal(0, 1)) * 0.55)
        pts = np.array([a0 + d * (trail * 0.35 * q) + u0 * rng.normal(0, 0.02) * trail for q in np.linspace(0, 1, 5)])
        V, T, C, uv = tube_wood(pts, np.linspace(r_tip * 1.6, r_tip * 0.4, 5), 4, close=(True, True), rgba=ROOT_RGBA)
        parts.append((V, T, C, uv))
        rigid_from.append(np.ones(len(V), bool))
        srcs.append(kd.query(V)[1])
    V, T, C, UV = merge(parts)
    rig = np.concatenate(rigid_from)
    src = np.concatenate(srcs)
    g = {b: wv[src].copy() for b, wv in groups.items()}
    for b in g:
        g[b][rig] = 1.0 if b == "hand_l" else 0.0
    g = sb.stiffen(g, T, len(V), 3)
    p = piece_of("roots", V, T, C, UV, g, src)
    p.facts = {"roots": count, "trail_m": r6(ROOTS["trail_m"]), "tris": int(len(T))}
    p.tip_point = wr + tip_dir * trail
    return p


def antlers_piece(person):
    """A crown of branches grown from his brow and temples (rigid to the head): two great antler-boughs rising back
    and out with their tines, smaller twigs over the crown, moss at their roots, lichen hanging from them."""
    rng = np.random.default_rng(621)
    V = person.body_V()
    m = person.bd.masks
    hv = V[m["m_head"] > 0.6]
    top = hv[np.argmax(hv[:, 2])]
    front_y = float(hv[:, 1].min())
    L = ANTLERS["main_m"] / F
    r0 = ANTLERS["r_m"] / F
    parts = []

    def bough(a, d, length, r, depth, curl):
        pts = []
        p = a.copy()
        dd = unit(d)
        n = 6 if depth == 2 else 4
        for i in range(n):
            pts.append(p.copy())
            dd = unit(dd + curl + rng.normal(0, 0.10, 3))
            p = p + dd * (length / (n - 1))
        pts = np.asarray(pts)
        rr = np.linspace(r, r * 0.22, n) * (1.0 + 0.15 * np.sin(np.arange(n) * 2.3))
        parts.append(tube_wood(pts, rr, ANTLERS["segs"], rgba=ANTLER_RGBA))
        if depth > 0:
            for k in range(ANTLERS["tines"] if depth == 2 else 1):
                i = int(rng.integers(2, n - 1))
                side = unit(np.cross(pts[min(i + 1, n - 1)] - pts[i - 1], [0.0, 0.0, 1.0]) * (1 if k % 2 else -1)
                            + np.array([0.0, 0.0, 0.8]) + rng.normal(0, 0.25, 3))
                bough(pts[i], side, length * rng.uniform(0.28, 0.42), rr[i] * 0.7, depth - 1, curl * 0.5)
        return pts

    for s in (1.0, -1.0):
        base = np.array([s * 0.055 * person.S, front_y + 0.04 * person.S, top[2] - 0.035 * person.S])
        near = hv[np.argmin(np.linalg.norm(hv - base, axis=1))]
        d = np.array([s * 0.55, 0.55, 0.65])
        pts = bough(near - np.array([0, 0, 0.01]) * person.S, d, L, r0, 2, np.array([s * 0.04, 0.05, -0.02]))
        # moss at its root, lichen hanging from the bough
        Vm, Tm = blob(near, r0 * 0.95, rng, squash=(1.1, 1.1, 0.6), rough=0.5)
        parts.append((Vm, Tm, colour(len(Vm), MOSS_RGBA), None))
        for i in (2, 4):
            a = pts[i]
            hang = np.array([a, a - np.array([0, 0, 0.25 / F]) + rng.normal(0, 0.03, 3) / F,
                             a - np.array([0, 0, 0.6 / F])])
            parts.append(tube_wood(hang, np.array([0.07, 0.05, 0.02]) / F, 4, rgba=LICHEN_RGBA))
    for k in range(ANTLERS["twigs"]):
        a = 2.0 * math.pi * (k + 0.5) / ANTLERS["twigs"]
        base = top + np.array([math.cos(a) * 0.045, math.sin(a) * 0.05 + 0.02, -0.02]) * person.S
        near = hv[np.argmin(np.linalg.norm(hv - base, axis=1))]
        bough(near, np.array([math.cos(a) * 0.4, math.sin(a) * 0.4 + 0.3, 1.0]), L * rng.uniform(0.25, 0.38),
              r0 * 0.45, 0, np.array([0.0, 0.03, -0.01]))
        Vm, Tm = blob(near, r0 * 0.8, rng, squash=(1.2, 1.2, 0.5), rough=0.5)
        parts.append((Vm, Tm, colour(len(Vm), MOSS_RGBA), None))
    # a beard of lichen and fine roots hanging from his jaw and chin
    J = person.bd.joints
    chin = hv[np.argmin(hv[:, 2] + 0.6 * hv[:, 1])]
    for k in range(5):
        a = (k - 2) / 2.0 + rng.uniform(-0.2, 0.2)
        base = chin + np.array([a * 0.040 * person.S, 0.025 * person.S * abs(a), 0.012 * person.S * abs(a)])
        near = hv[np.argmin(np.linalg.norm(hv - base, axis=1))]
        ln = (1.6 + 1.4 * rng.random() - 0.5 * abs(a)) / F
        n_ = 6
        pts = [near + np.array([0.0, -0.01, 0.0]) * person.S]
        for i in range(1, n_):
            q = i / (n_ - 1)
            pts.append(near + np.array([a * 0.10 * q / F + rng.normal(0, 0.05) / F,
                                        (-0.12 * math.sin(q * math.pi) + rng.normal(0, 0.04)) / F, -ln * q]))
        parts.append(tube_wood(np.asarray(pts), np.linspace(0.08, 0.02, n_) / F, 4,
                               rgba=LICHEN_RGBA if k % 2 else (0.50, 0.42, 0.36, 1.0)))
    V, T, C, UV = merge(parts)
    p = piece_of("antlers", V, T, C, UV, {"head": np.ones(len(V))})
    p.facts = {"tris": int(len(T)), "top_m": r6(float(V[:, 2].max()) * F)}
    return p


def tree_piece(person):
    """A dead tree as he tears it out of the grove (rigid to the right hand): a silvered trunk, broken branches, its
    root plate with earth at the foot; the right fist grips it TREE["grip_m"] up from the root plate."""
    import people_bake as pbk
    rng = np.random.default_rng(631)
    g, ax = person.grip["r"]
    ax = unit(ax)
    L, R, G = TREE["length_m"] / F, TREE["r_m"] / F, TREE["grip_m"] / F
    rings, segs = TREE["rings"], TREE["segs"]
    s = np.linspace(-G, L - G, rings)                         # 0 at the grip; the root plate at -G, the top at L - G
    tt = (s + G) / L
    base_r = R * np.interp(tt, [0.0, 0.06, 0.3, 0.7, 1.0], [1.5, 1.05, 0.85, 0.55, 0.22])
    ref = unit(np.cross(ax, [0.0, 0.0, 1.0]))
    w_ = np.cross(ax, ref)
    bend = np.outer(np.sin(tt * 3.0) * 0.05 * L * tt, ref)
    path = g + np.outer(s, ax) + bend
    phs = 2.0 * math.pi * np.arange(segs) / segs
    radii = np.zeros((rings, segs))
    for i in range(rings):
        q = np.stack([np.cos(phs), np.sin(phs), np.full(segs, s[i] * 0.5)], axis=1) * F
        radii[i] = base_r[i] * (1.0 + 0.18 * (pbk.fbm(q * [1.0, 1.0, 0.3], 2.0, 633) - 0.5))
    parts = [tube_wood(path, radii, segs, close=(True, True), frame0=ref, rgba=DEAD_RGBA)]
    for k in range(TREE["branches"]):
        st = rng.uniform(0.35, 0.85)
        az = 2.0 * math.pi * rng.random()
        d = unit(math.cos(az) * ref + math.sin(az) * w_ + ax * 0.9)
        c0 = g + ax * (st * L - G)
        r0 = float(np.interp(st * L - G, s, base_r))
        ln = L * rng.uniform(0.12, 0.25)
        pts = np.array([c0, c0 + d * ln * 0.5 + rng.normal(0, 0.03, 3) * ln, c0 + d * ln])
        parts.append(tube_wood(pts, np.array([0.55, 0.35, 0.16]) * r0, 6, rgba=DEAD_RGBA))
    foot = g - ax * G
    for k in range(TREE["roots"]):
        az = 2.0 * math.pi * (k + rng.uniform(-0.2, 0.2)) / TREE["roots"]
        d = math.cos(az) * ref + math.sin(az) * w_
        pts = np.array([foot + d * R * 0.6 + ax * R * 0.3, foot + d * R * 1.6 - ax * R * 0.2,
                        foot + d * R * 2.5 - ax * R * 0.9 + rng.normal(0, 0.2, 3) * R])
        parts.append(tube_wood(pts, np.array([0.55, 0.38, 0.12]) * R, 6, rgba=DEAD_RGBA))
    Vb, Tb = blob(foot - ax * R * 0.4, R * 1.6, rng, squash=(1.0, 1.0, 0.7), rough=0.45, subdiv=2)
    parts.append((Vb, Tb, colour(len(Vb), EARTH_RGBA), None))
    V, T, C, UV = merge(parts)
    p = piece_of("tree", V, T, C, UV, {"hand_r": np.ones(len(V))})
    p.facts = {"length_m": r6(TREE["length_m"]), "tris": int(len(T))}
    p.head_point = g + ax * (L - G)
    p.foot_point = foot
    return p


# ======================================================================================================================
# textures: the bark
# ======================================================================================================================
def bark_textures(out_dir):
    """rootwarden_bark_albedo.png and _normal.png (DETAIL_PX, tileable): an old oak's bark, deep furrows running down
    the texture (V) between broad flat-topped ridges broken across by checks, lichen in the furrows."""
    import people_bake as pbk
    n = DETAIL_PX
    yy, xx = np.mgrid[0:n, 0:n]
    u = xx / n
    v = yy / n
    ring = np.stack([np.cos(2 * math.pi * u), np.sin(2 * math.pi * u), np.cos(2 * math.pi * v),
                     np.sin(2 * math.pi * v)], -1).reshape(-1, 4)
    P3 = ring[:, :3] * 0.6 + ring[:, [1, 2, 3]] * 0.4
    # fissures: a ridged noise on the torus, stretched down V (the furrows run along the limb)
    Q = np.stack([np.cos(2 * math.pi * u) * 1.6, np.sin(2 * math.pi * u) * 1.6, np.cos(2 * math.pi * v) * 0.45,
                  np.sin(2 * math.pi * v) * 0.45], -1).reshape(-1, 4)
    Q3 = Q[:, :3] + Q[:, [3, 3, 3]] * np.array([0.0, 0.0, 1.0])
    n1 = pbk.fbm(Q3, 1.6, 641, 4).reshape(n, n)
    fiss = 1.0 - _sstep(np.abs(n1 - 0.5), 0.0, 0.06)
    n2 = pbk.fbm(Q3 * 2.1 + 1.3, 1.6, 642, 3).reshape(n, n)
    fiss = np.maximum(fiss, 0.55 * (1.0 - _sstep(np.abs(n2 - 0.5), 0.0, 0.035)))
    ridge = 1.0 - fiss
    fine = pbk.fbm(P3, 7.0, 645).reshape(n, n)
    height = 0.80 * ridge + 0.20 * fine
    grey = 0.19 + 0.22 * ridge + 0.07 * (fine - 0.5)
    lichen = _sstep(pbk.fbm(P3, 2.4, 647).reshape(n, n), 0.60, 0.72) * ridge
    col = np.stack([grey * 1.0, grey * 0.90, grey * 0.76], -1)
    col = col * (1.0 - 0.45 * lichen[..., None]) + np.array([0.30, 0.31, 0.24]) * 0.45 * lichen[..., None]
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5 * n / 24.0
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5 * n / 24.0
    nrm = np.stack([-gx, gy, np.ones_like(gx)], -1)
    nrm /= np.linalg.norm(nrm, axis=-1, keepdims=True)
    paths = {}
    for k, arr in (("albedo", np.clip(col, 0, 1)), ("normal", nrm * 0.5 + 0.5)):
        p = os.path.join(out_dir, "%s_bark_%s.png" % (KIND, k))
        pbk.save_png(p, pbk.to_u8(arr))
        paths[k] = os.path.basename(p)
    return paths


# ======================================================================================================================
# his skin: bark
# ======================================================================================================================
HIDE_BASE = 0.62
BONE_SEGS = (("joint-l-upper-leg", "joint-l-knee"), ("joint-l-knee", "joint-l-ankle"),
             ("joint-r-upper-leg", "joint-r-knee"), ("joint-r-knee", "joint-r-ankle"),
             ("joint-l-shoulder", "joint-l-elbow"), ("joint-l-elbow", "joint-l-hand"),
             ("joint-r-shoulder", "joint-r-elbow"), ("joint-r-elbow", "joint-r-hand"),
             ("joint-pelvis", "joint-neck"), ("joint-neck", "joint-head"))


def limb_frame(P, J):
    """Each point's nearest limb segment's (along, round) coordinates (human m): the bark's furrows follow the limb."""
    best = np.full(len(P), np.inf)
    along = np.zeros(len(P))
    ang = np.zeros(len(P))
    for a, b in BONE_SEGS:
        A, B = J[a], J[b]
        ax = B - A
        Lsq = max(float(ax @ ax), 1e-12)
        t = np.clip(((P - A) @ ax) / Lsq, 0.0, 1.0)
        d = np.linalg.norm(P - (A + np.outer(t, ax)), axis=1)
        sel = d < best
        best[sel] = d[sel]
        al, an, _r = cyl_coords(P[sel], A, ax)
        along[sel] = al
        ang[sel] = an
    return along, ang


def bark_skin(P, Nrm, J, under, masks):
    """(albedo multiplier (n, 3), height (n,)) of his bark-skin at P (human m, rest): meandering fissures along his
    limbs between grey ridges, lichen, moss over his shoulders, back and scalp, and pale amber sapwood under the
    plates (``under`` 0..1). His face keeps a face: the bark only in its lines."""
    import people_bake as pbk
    along, ang = limb_frame(P, J)
    c = 13.0 / (2.0 * math.pi)
    q = np.stack([np.cos(ang) * c * 0.05, np.sin(ang) * c * 0.05, along * 0.9], -1)
    n1 = pbk.fbm(q + P * 0.15, 16.0, 651, 3)
    fiss = 1.0 - _sstep(np.abs(n1 - 0.5), 0.0, 0.06)
    n2 = pbk.fbm(q * 2.0 + P * 0.3, 16.0, 653, 2)
    fiss = np.maximum(fiss, 0.55 * (1.0 - _sstep(np.abs(n2 - 0.5), 0.0, 0.035)))
    big = pbk.fbm(P, 5.0, 655)
    fine = pbk.vnoise(P, 70.0, 657)
    face = masks["m_head"] * (1.0 - masks["m_scalp"]) if masks is not None else 0.0
    fiss = fiss * (1.0 - 0.45 * face)
    ridge = 1.0 - fiss
    grey = HIDE_BASE * (0.70 + 0.30 * ridge + 0.14 * (big - 0.5) + 0.06 * (fine - 0.5))
    mul = np.repeat(grey[:, None], 3, axis=1) * np.array([1.0, 0.97, 0.92])[None, :]
    up = np.clip(Nrm[:, 2], -1.0, 1.0)
    back = np.clip(Nrm[:, 1], -1.0, 1.0)
    hz = P[:, 2] / max(float(P[:, 2].max()), 1e-6)
    moss_n = pbk.fbm(P * [1.0, 1.0, 0.6], 9.0, 659)
    where = np.clip(0.2 + 0.7 * up + 0.5 * np.clip(back, 0, 1), 0.0, 1.0) * _sstep(hz, 0.62, 0.76)
    moss = np.clip((where * 0.7 + 1.2 * (moss_n - 0.5) - 0.42) / 0.08, 0.0, 1.0) * (1.0 - face)
    moss *= 0.6 + 0.4 * ridge
    moss_col = mul * np.array([0.52, 0.62, 0.34])[None, :] * (0.65 + 0.4 * pbk.fbm(P, 45.0, 661))[:, None]
    mul = mul * (1.0 - moss[:, None]) + moss_col * moss[:, None]
    lichen = _sstep(pbk.fbm(P, 22.0, 663), 0.62, 0.72) * (1.0 - moss) * (1.0 - face) * ridge
    mul = mul * (1.0 - 0.45 * lichen[:, None]) + np.array([1.20, 1.24, 1.08])[None, :] * grey[:, None] * 0.45 * lichen[:, None]
    # earth and old leaf-mould on the feet and the ankles (he has stood in the grove for centuries)
    soil = _sstep(-hz, -0.07, -0.02) * (0.7 + 0.3 * pbk.fbm(P, 12.0, 667))
    mul = mul * (1.0 - 0.45 * soil[:, None]) + np.array([0.42, 0.36, 0.28])[None, :] * 0.45 * soil[:, None]
    # under a plate: the sapwood - pale, warm, smooth, faintly ringed
    u = np.clip(under, 0.0, 1.0)[:, None]
    sap = np.array([1.45, 1.08, 0.60])[None, :] * HIDE_BASE * (0.9 + 0.1 * np.sin(along * 160.0))[:, None]
    mul = mul * (1.0 - u) + sap * u
    height = 0.75 * ridge * (1.0 - u[:, 0] * 0.8) + 0.12 * fine + 0.30 * moss * pbk.vnoise(P, 140.0, 665)
    return mul, height


def repaint_bark(out_dir, LV, LT, Luv, tan, sgn, nor, S, person, under_fn, kd):
    """The bake's skin texels repainted with his bark-skin; its height into the normal map; the loincloth's leather
    re-dyed as a hanging skirt of moss and bark."""
    import people_bake as pbk
    from PIL import Image
    paths = {k: os.path.join(out_dir, "%s_%s.png" % (KIND, k)) for k in ("albedo", "normal", "orm")}
    alb = np.asarray(Image.open(paths["albedo"]).convert("RGB")).astype(np.float64) / 255.0
    nrm = np.asarray(Image.open(paths["normal"]).convert("RGB")).astype(np.float64) / 255.0 * 2.0 - 1.0
    orm = np.asarray(Image.open(paths["orm"]).convert("RGB")).copy()
    skin_b = pr.band_byte("skin")
    J = person.bd.joints
    masks = person.bd.masks
    for size, img in ((pr.ALBEDO_PX, "albedo"), (pr.NORMAL_PX, "normal")):
        tri, bar = pbk.raster(Luv, size)
        ys, xs = np.nonzero(tri >= 0)
        t = tri[ys, xs]
        b = bar[ys, xs]
        P = np.einsum("nk,nkj->nj", b, LV[LT[t]]) / S
        Nl = np.einsum("nk,nkj->nj", b, nor[t])
        Nl /= np.maximum(np.linalg.norm(Nl, axis=1, keepdims=True), 1e-12)
        oy = np.clip((ys * pr.ORM_PX) // size, 0, pr.ORM_PX - 1)
        ox = np.clip((xs * pr.ORM_PX) // size, 0, pr.ORM_PX - 1)
        skin = orm[oy, ox, 2] == skin_b
        Ps = P[skin]
        d, i = kd.query(Ps, k=4)
        wt = 1.0 / np.maximum(d, 1e-6)
        wt /= wt.sum(axis=1, keepdims=True)
        mk = {k: (np.asarray(masks[k])[i] * wt).sum(axis=1) for k in ("m_head", "m_scalp")}
        under = under_fn(Ps)
        mul, height = bark_skin(Ps, Nl[skin], J, under, mk)
        if img == "albedo":
            alb[ys[skin], xs[skin]] = np.clip(alb[ys[skin], xs[skin]] * mul, 0.0, 1.0)
            cloth = ~skin
            Pc = P[cloth]
            moss = 0.75 + 0.4 * (pbk.fbm(Pc, 20.0, 671) - 0.5)
            alb[ys[cloth], xs[cloth]] = np.clip(alb[ys[cloth], xs[cloth]] * np.array([0.62, 0.78, 0.48])[None, :]
                                                * moss[:, None], 0.0, 1.0)
        else:
            e = 0.004
            Tl = np.einsum("nk,nkj->nj", b, tan[t])[skin]
            Bl = np.cross(Nl[skin], Tl) * np.sign(sgn[t[skin], 0])[:, None]
            g1 = (bark_skin(Ps + Tl * e, Nl[skin], J, under, mk)[1] - height) / e
            g2 = (bark_skin(Ps + Bl * e, Nl[skin], J, under, mk)[1] - height) / e
            n0 = nrm[ys[skin], xs[skin]]
            n1 = n0 - 0.0055 * np.stack([g1, g2, np.zeros_like(g1)], axis=1)
            n1 /= np.maximum(np.linalg.norm(n1, axis=1, keepdims=True), 1e-9)
            nrm[ys[skin], xs[skin]] = n1
    rows = int(round((1.0 - pr.TILE_SIZE) * pr.ORM_PX))
    garment = orm[:rows, :, 2] != skin_b
    orm[:rows, :, 1] = np.where(~garment, np.maximum(orm[:rows, :, 1], int(round(0.90 * 255))), orm[:rows, :, 1])
    orm[:rows, :, 0] = np.where(garment, np.maximum(orm[:rows, :, 0], int(round(br.GARMENT_AO_FLOOR * 255))),
                                orm[:rows, :, 0])
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))
    pbk.save_png(paths["normal"], pbk.to_u8(nrm * 0.5 + 0.5))
    pbk.save_png(paths["orm"], orm)


def tracks(poses, rest_export):
    """stoneback.tracks at his scale: every bone's rotation per frame and the pelvis's offset in real metres."""
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
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
    import rootwarden_moves as mv
    from scipy.spatial import cKDTree
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    times = {}
    p0 = br.brute_person(VARIANT)
    if not p0.bd.masks:
        p0.bd.compute_masks(p0.weights)
    times["body"] = round(time.time() - t0, 1)
    _x, faces, _fuv = p0.bd.group("body")
    body_T = po.triangulate(faces)
    p0.normals = po.vertex_normals(p0.body_V(), body_T)
    p0.normals_h = p0.normals
    p0.grip_radius = sb.grip_radius(p0)
    # ---- the outfit and the shared mesh
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, OUTFIT)
    garments = [po.garment_piece(w0, gid, p0, OUTFIT_MATERIAL[gid], kd0) for gid in order]
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
        raise SystemExit("rootwarden: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the pieces
    groups23 = pr.fold_weights(p0.groups53())
    kdb = cKDTree(p0.body_V())
    pieces, saps = {}, {}
    for k, name in enumerate(PLATE_ORDER):
        pieces[name], saps["sap_" + name] = bark_piece(p0, name, body_T, groups23, 501 + 10 * k)
    pieces["roots"] = roots_piece(p0, groups23, kdb)
    pieces["antlers"] = antlers_piece(p0)
    pieces["tree"] = tree_piece(p0)
    pieces.update(saps)
    log("pieces: " + ", ".join("%s %d" % (n, p.tris()) for n, p in pieces.items()))
    for name, p in pieces.items():
        cap = PLATES[name]["budget"] + 40 if name in PLATES else (SAP_BUDGET + 10 if name.startswith("sap_")
                                                                   else GEAR_BUDGET[name])
        if p.tris() > cap:
            raise SystemExit("rootwarden: %s has %d triangles, over %d" % (name, p.tris(), cap))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(WARDEN_GAITS)
    poses, gaits, checks = mv.make_poses(p0, pieces)
    # ---- the bake and the bark-skin
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(KIND, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras)])
    feet = {n: plate_footprint(p0, n) for n in PLATE_ORDER}
    under_all = _sstep(np.max(np.stack([feet[n] for n in PLATE_ORDER]), axis=0), 0.55, 0.85)
    Vh = p0.bd.verts[:N]

    def under_fn(P):
        d, i = kd0.query(P, k=3)
        wt = 1.0 / np.maximum(d, 1e-6)
        return (under_all[i] * wt).sum(axis=1) / wt.sum(axis=1)
    repaint_bark(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, p0, under_fn, cKDTree(Vh))
    detail_files = bark_textures(out_dir)
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("rootwarden_body")
    wood = bpy.data.materials.new("rootwarden_bark")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    rest_h = pbody.rest_matrices(arm)
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in PLATE_ORDER + GEAR + tuple("sap_" + n for n in PLATE_ORDER):
        p = pieces[name]
        o = br.skinned_object(name, p, arm, coll, wood, F)
        ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(p.rgba, np.float32).ravel())
        o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        bone = PIECE_BONE.get(name, PIECE_BONE.get(name[4:], "spine_02")) if name.startswith("sap_") \
            else PIECE_BONE[name]
        info_p = {"node": name, "tris": p.tris(), "material": "bark", "bone": bone,
                  "plate": name in PLATES, "sap": name.startswith("sap_")}
        info_p.update(getattr(p, "facts", {}) or {})
        if name == "tree":
            H = rest_h["hand_r"]
            info_p["head_local"] = [r6(x) for x in (H[:3, :3].T @ (p.head_point * F - H[:3, 3]))]
            info_p["foot_local"] = [r6(x) for x in (H[:3, :3].T @ (p.foot_point * F - H[:3, 3]))]
        if name == "roots":
            H = rest_h["hand_l"]
            info_p["tip_local"] = [r6(x) for x in (H[:3, :3].T @ (p.tip_point * F - H[:3, 3]))]
        piece_info[name] = info_p
    rest = pbody.rest_matrices(arm)
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
    antler_top = float(pieces["antlers"].V[:, 2].max()) * F
    b53 = p0.rig.data.bones
    knuckle = (np.asarray(b53["middle_01_l"].head_local) - np.asarray(b53["hand_l"].head_local)) * F
    reach = (b53["upperarm_l"].length + b53["lowerarm_l"].length) * F + float(np.linalg.norm(knuckle))
    info = {"kind": KIND, "height_m": HEIGHT_M, "export_scale": r6(F), "times": times, "tris_max": TRIS,
            "bake": bake_info, "outfit": list(order),
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget), "culled_skin": culled_skin},
            "variants": {KIND: {"index": 0, "tris": mesh.tris(), "verts": int(len(mesh.V)), "height_m": r6(height),
                                "height_with_antlers_m": r6(antler_top), "game_height_m": HEIGHT_M,
                                "game_scale": r6(HEIGHT_M / height), "pieces": [p.name for p in extras],
                                "joints": {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES},
                                "reach_m": r6(reach), "far": {"node": KIND + "_far", "tris": int(len(Tf))}}},
            "pieces": piece_info, "plates": list(PLATE_ORDER), "weak_points": WEAK_POINTS, "detail": detail_files,
            "detail_tile_m": {"bark": list(BARK_TILE_M)}, "glow_alpha": GLOW_ALPHA, "checks": checks,
            "used_by": ["enemy.rootwarden (B3: RootwardenRig)", "tools/rootwarden_stills.gd"]}
    for sd in ("l", "r"):
        g, ax = p0.grip[sd]
        H = rest["hand_" + sd]
        info["variants"][KIND]["grip_local_" + sd] = [r6(x) for x in (H[:3, :3].T @ (g * F - H[:3, 3]))]
        info["variants"][KIND]["grip_axis_" + sd] = [r6(x) for x in (H[:3, :3].T @ ax)]
    info["glb_bytes"] = os.path.getsize(path)
    worst = 0.0
    for name in ("walk", "idle"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            Gk = pbody.fk(rest, pbody.parents_of(arm), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "hand_l", "head", "pelvis"):
                worst = max(worst, float(np.linalg.norm(Gk[b][:3, 3] - poses[name][kk].P[b] * F)))
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("rootwarden clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    import clips
    sb.CLIP_FRAMES = {n: len(k) - 1 for n, k in poses.items()}   # (sb.key_actions keys the clips it lists)
    sb.export_clips(os.path.join(out_dir, KIND + "_clips.glb"), arm, coll, trk)
    info["clips"] = {"fps": clips.FPS, "step_m": r6(STEP_M), "conversion_error_m": r6(worst),
                     "clips": {n: {"frames": len(k) - 1, "loop": n in mv.LOOPS, "bones": len(pr.BONES),
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
        raise SystemExit("usage: rootwarden.py rootwarden <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
