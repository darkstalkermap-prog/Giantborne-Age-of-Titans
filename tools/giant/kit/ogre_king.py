"""The Ogre King (B2): the Valley's boss raised to a signature titan, an original crowned ogre 8.5 m (28 ft) tall, as
an asset (``build_people.py --ogre_king``).

The body is a brute (``brute.py``: the people's CC0 human with MakeHuman's macros, ``giant_body.proportioned`` with a
table of his own and ``brute.reshape``): an old ogre gone to fat - short heavy legs, a broad trunk carried less
hunched than the ogres' (so he stands taller than the stage-3 giant who fights him), a great gut pushed out and down,
a heavy jaw with its tusks, big hands. He wears the ogres' hide loincloth and belt (the giant's garment shells, one
shared mesh with the body, decimated and unwrapped into one atlas: ``people_bake``; the skin band repainted with the
ogres' hide), and over it the war-gear he took from the people of the Valley, each piece its own skinned mesh on the
same 23 bones (a later fight breaks them - wood and iron, so they splinter and fall, not shatter as Stoneback's stone):

  trophy_crown    a gate's iron ring hammered round his brow, the shards of seven shields riveted to it as its points
                  (rigid to the head)
  trophy_bell     the Valley's great bell, split and beaten into an oval breastplate over his gut, lashed on with two
                  iron straps round his trunk (each vertex on the weights of the skin under it, stiffened)
  trophy_wheel_l, trophy_wheel_r
                  a broken cart wheel dished over each shoulder (spokes missing, a length of its rim gone, the iron
                  tyre), bent onto the shoulder's round (rigid on the blended weights of the shoulder's top)
  trophy_keg      a hooped cask slung across the small of his back on a strap (on the weights of the back under it)
  chain_belt      not a trophy that breaks: a heavy chain round his hips sagging under the gut, five men's helmets
                  hung from it by their chin straps
  ram             his weapon: a town's battering ram - an oak log with an iron cap and bands, carrying rings, a rope
                  grip - rigid to hand_r, carried on his right shoulder
  ogre_king_far   the idle's first key, decimated

The trophies' wood (the shields, the wheels, the keg, the ram's log) is mapped in metres on a tileable oak texture
(``ogre_king_wood_albedo.png``, ``_normal.png``, 256 px, repeated ``WOOD_TILE_M``; the grain along V); their iron and
the bell's bronze are vertex colours (alpha 0: stone_plate.gdshader's metal path), the shields' paint the wood's tint.

Clips on his skeleton (``CLIP_FRAMES``; ``ogre_king_moves.py``): idle, walk and run with the ram on his shoulder, the
phase roar, the two-blow combo, the slam, the charge's wind-up and run with the ram levelled as a ram, the reel, the
kneel and the rise (the keg burst), his death.

``python ogre_king.py ogre_king <out dir> <work dir>`` writes ogre_king.glb, ogre_king_clips.glb, the atlas
(ogre_king_albedo.png 512 px, _normal.png, _orm.png 256 px), the wood textures and ogre_king_info.json.
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

KIND = "ogre_king"
HEIGHT_M = 8.5                     # P11a's 8.5 m (the record's height: his fight's reach, hurtboxes and lock are set to it)
DESIGN = pr.DESIGN_HEIGHT_M
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.36 * HEIGHT_M           # a fat ogre's short stride (the ogres' 0.44, Stoneback's 0.33)
TRIS = 9000
MARGIN_TRIS = 60
FAR_TRIS = 300
OUTFIT = ("loincloth", "belt")
OUTFIT_MATERIAL = {"loincloth": "leather", "belt": "dark_leather"}

# ---- the body ------------------------------------------------------------------------------------------------------
# an old ogre's face: the ogres' broad flat nose and jaw, aged, the brow heavy, the cheeks fat, the mouth turned down
KING_FACE = dict(br.OGRE_FACE, **{"head/head-age-decr-incr": 0.9, "head/head-fat-decr-incr": 0.9,
                                  "cheek/cheek-bones-decr-incr": 0.4, "mouth/mouth-angles-down-up": -0.6,
                                  "eyes/eye-bag-decr-incr": 0.9, "eyes/eye-scale-decr-incr": -0.4,
                                  "chin/chin-jaw-drop-decr-incr": 0.8, "mouth/mouth-laugh-lines-in-out": 0.7})
KING_PROP = dict(legs=0.84, torso=1.04, neck=-0.035, head=0.86, arms=0.96, hands=1.12, shoulders=-0.030,
                 deltoids=0.0, trapezius=-0.020, thighs=0.10)
KING_SHAPE = dict(hunch_deg=14.0, head_back_deg=10.0, jaw=(0.34, 0.014, 0.010), underbite_m=0.014, brow_m=0.024,
                  nose=(-0.014, -0.004), ears=0.0, hands=1.10, feet=1.18, gut_m=0.15, tusks=True)
VARIANT = dict(name=KIND, macro=br._macro(56, 0.85, 1.0, african=0.3, asian=0.1, caucasian=0.6),
               face=br._face(2.0, **KING_FACE), prop=KING_PROP, shape=KING_SHAPE, height_m=HEIGHT_M)
KING_GAITS = {
    "king_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.05, min_drop=0.03, lean_deg=6.0, pelvis_pitch_deg=4.0,
                      roll_deg=6.0, sway=0.10, arm_swing_deg=8.0, heel_rocker=0.10),
    "king_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.10, min_drop=0.08, lean_deg=12.0, pelvis_pitch_deg=7.0),
}

# ---- the trophies (real metres) ------------------------------------------------------------------------------------
IRON_RGBA = (0.150, 0.140, 0.130, 0.0)
RUST_RGBA = (0.230, 0.150, 0.100, 0.0)
BRONZE_RGBA = (0.300, 0.245, 0.150, 0.0)   # B3: an old bell's dark olive bronze (B2's read coppery-orange)
VERDIGRIS_RGBA = (0.250, 0.350, 0.290, 0.0)
ROPE_RGBA = (0.44, 0.36, 0.25, 0.5)
WOOD_RGBA = (1.0, 1.0, 1.0, 1.0)
# the shields' faded paint over the wood (each shard one of these, the wood showing through)
PAINT = ((0.62, 0.22, 0.18), (0.26, 0.34, 0.52), (0.78, 0.66, 0.38), (0.84, 0.82, 0.74), (0.30, 0.42, 0.28),
         (0.62, 0.22, 0.18), (0.78, 0.66, 0.38))
WOOD_TILE_M = 1.6                  # the oak texture repeats every this many metres
DETAIL_PX = 256
SHARP_DEG = 30.0
CROWN = dict(below_top_m=0.30, band_m=0.22, thick=0.06, gap=0.04, segs=30, points=7, shard_w=0.46, shard_h=0.95,
             shard_t=0.06, lean_deg=10.0)
BELL = dict(gap=0.10, thick=0.09, cover_deg=100.0, rings=11, segs=20, flare_m=0.42, strap_w=0.13, strap_t=0.05)
WHEEL = dict(r=0.95, dish=0.30, spokes=10, missing=(3, 4), rim_gap_deg=(108.0, 178.0), hub_r=0.20, hub_l=0.36,
             felloe=(0.17, 0.12), tyre=(0.18, 0.035), spoke_r=0.07, gap=0.05)
KEG = dict(r=0.50, length=1.45, staves=16, rings=9, hoops=(0.08, 0.30, 0.70, 0.92), gap=0.05, strap_w=0.16)
CHAIN = dict(links=26, length=0.46, width=0.30, wire=0.09, sag_m=0.30, helmets=5)
RAM = dict(handle_m=0.85, length_m=5.0, r=0.27, cap_m=0.75, segs=12, bands=(1.55, 2.75, 3.85), rings=(2.15, 3.35))
GEAR_BUDGET = {"trophy_crown": 700, "trophy_bell": 1300, "trophy_wheel_l": 1000, "trophy_wheel_r": 1000,
               "trophy_keg": 800, "chain_belt": 2000, "ram": 900}
TROPHIES = ("trophy_crown", "trophy_bell", "trophy_wheel_l", "trophy_wheel_r", "trophy_keg")
GEAR = ("chain_belt", "ram")
# the main bone of each piece (the rig's break: where its splinters fly from, which bone carries its fall)
PIECE_BONE = {"trophy_crown": "head", "trophy_bell": "spine_01", "trophy_wheel_l": "upperarm_l",
              "trophy_wheel_r": "upperarm_r", "trophy_keg": "spine_01", "chain_belt": "pelvis", "ram": "hand_r"}

CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32}
CLIP_LOOPS = ("idle", "walk", "run")


def log(*a):
    print("[ogre_king]", *a, flush=True)


r6 = br.r6
unit = sb.unit


# ======================================================================================================================
# geometry helpers (design scale)
# ======================================================================================================================
def merge(parts):
    """[(V, T, rgba (n,4), uv (m,3,2) or None)] -> V, T, rgba, uv (corner UVs; a box map where None: the metal's
    wear and its dents read the texture's light)."""
    Vs, Ts, Cs, UVs = [], [], [], []
    off = 0
    for V, T, C, uv in parts:
        Ts.append(np.asarray(T, np.int64) + off)
        Vs.append(np.asarray(V, np.float64))
        Cs.append(np.asarray(C, np.float64))
        UVs.append(sb.box_uv(np.asarray(V, np.float64), np.asarray(T, np.int64), WOOD_TILE_M / F) if uv is None
                   else np.asarray(uv, np.float64))
        off += len(V)
    return np.concatenate(Vs), np.concatenate(Ts), np.concatenate(Cs), np.concatenate(UVs)


def colour(n, rgba):
    return np.tile(np.asarray(rgba, np.float64), (n, 1))


def slab(outline, o, ux, uy, n, thick):
    """An extruded flat plate: ``outline`` (k, 2) in the plane (o, ux, uy), ``thick`` along -n (its back) - its face,
    its back and its walls. Returns (V, T) wound outward."""
    k = len(outline)
    front = np.array([o + ux * a + uy * b for a, b in outline])
    back = front - n * thick
    V = np.concatenate([front, back])
    T = []
    for i in range(1, k - 1):
        T.append((0, i, i + 1))
        T.append((k, k + i + 1, k + i))
    for i in range(k):
        j = (i + 1) % k
        T += [(i, j, k + j), (i, k + j, k + i)]
    V = np.asarray(V)
    return V, sb.outward(V, np.asarray(T, np.int64), o - n * thick * 0.5)


def tube_uv(path, radii, segs, ring, ang, tile):
    """Corner UVs of a sb.tube: round the tube (by its mean circumference) across, along its path down the grain."""
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    r = np.asarray(radii, np.float64)
    r = r.mean(axis=1) if r.ndim == 2 else r
    circ = 2.0 * math.pi * float(r.mean())
    return s, circ, tile


def tube_corner_uv(V, T, path, ring, ang, circ, tile):
    s = np.concatenate([[0.0], np.cumsum(np.linalg.norm(np.diff(path, axis=0), axis=1))])
    uu = ang / (2.0 * math.pi)
    vv = s[ring] / tile
    C = np.stack([uu, vv], axis=-1)[T]
    du = C[..., 0] - C[:, :1, 0]
    C[..., 0] = np.where(du > 0.5, C[..., 0] - 1.0, np.where(du < -0.5, C[..., 0] + 1.0, C[..., 0]))
    C[..., 0] *= circ / tile
    return C


def wood_tube(path, radii, segs, close=(True, True), frame0=None, rgba=WOOD_RGBA):
    V, T, ring, ang = sb.tube(path, radii, segs, close=close, frame0=frame0)
    r = np.asarray(radii, np.float64)
    circ = 2.0 * math.pi * float((r.mean(axis=1) if r.ndim == 2 else r).mean())
    uv = tube_corner_uv(V, T, np.asarray(path, np.float64), ring, ang, circ, WOOD_TILE_M / F)
    return V, T, colour(len(V), rgba), uv


def iron_tube(path, radii, segs, close=(True, True), frame0=None, rgba=IRON_RGBA):
    V, T, _r, _a = sb.tube(path, radii, segs, close=close, frame0=frame0)
    return V, T, colour(len(V), rgba), None


def ring_path(c, axis, R, ref=None):
    """Points of a ring about ``c`` along ``axis`` at radii R (one a bin, from -pi)."""
    a = unit(axis)
    ref = unit(np.cross(a, [0.0, 1.0, 0.0] if ref is None else ref))
    b = np.cross(a, ref)
    segs = len(R)
    return np.array([c + (math.cos(ph) * ref + math.sin(ph) * b) * R[k]
                     for k, ph in enumerate(-math.pi + 2.0 * math.pi * (np.arange(segs) + 0.5) / segs)])


def section(P, c, axis, half_w, segs, ref_hint=(0.0, 1.0, 0.0)):
    """The farthest of points ``P`` from the line through ``c`` along ``axis`` in each of ``segs`` angular bins (from
    -pi, the reference across the axis from ``ref_hint``), within ``half_w`` of the plane; empty bins interpolated."""
    a = unit(axis)
    ref = unit(np.cross(a, ref_hint))
    b = np.cross(a, ref)
    Q = P - c
    Q = Q[np.abs(Q @ a) < half_w]
    ang = np.arctan2(Q @ b, Q @ ref)
    rad = np.linalg.norm(Q - np.outer(Q @ a, a), axis=1)
    R = np.full(segs, np.nan)
    bins = np.clip(((ang + math.pi) / (2.0 * math.pi) * segs).astype(np.int64), 0, segs - 1)
    np.fmax.at(R, bins, rad)
    ok = ~np.isnan(R)
    idx = np.arange(segs, dtype=np.float64)
    return np.interp(idx, idx[ok], R[ok], period=segs) / math.cos(math.pi / segs), ref, b


def push_out(P, kd, Vb, Nb, gap):
    """Each point moved out along the nearest skin vertex's normal until it stands ``gap`` off the skin."""
    P = np.asarray(P, np.float64).copy()
    for _ in range(3):
        _d, i = kd.query(P)
        h = np.einsum("ij,ij->i", P - Vb[i], Nb[i])
        need = np.maximum(0.0, gap - h)
        P += Nb[i] * need[:, None]
    return P


def skin_weights(kd, groups, P, stiff_T=None, it=0):
    """Each point on the weights of the skin vertex nearest it (``stiffen``ed over ``stiff_T`` ``it`` times)."""
    src = kd.query(P)[1]
    g = {b: w[src] for b, w in groups.items()}
    if stiff_T is not None and it > 0:
        g = sb.stiffen(g, stiff_T, len(P), it)
    return g, src


def fixed_weights(groups, k, n):
    """Every one of ``n`` points on the blended weights of skin vertex ``k`` (a rigid piece strapped there)."""
    g = {b: np.full(n, float(w[k])) for b, w in groups.items() if float(w[k]) > 1e-4}
    tot = sum(g.values())
    return {b: w / tot for b, w in g.items()}


def piece_of(name, V, T, rgba, uv, groups, src=None):
    import people_outfit as po
    p = po.Piece(name, V, T, np.full(len(T), po.MATS.index("metal")), groups,
                 np.full(len(V), -1) if src is None else src)
    p.uv = uv
    p.rgba = rgba
    return p


# ======================================================================================================================
# the trophies
# ======================================================================================================================
def head_points(person):
    m = person.bd.masks
    V = person.body_V()
    return V[(m["m_head"] + m["m_scalp"] > 0.5)]


def crown_piece(person, seed=301):
    """The gate ring round his brow and the seven shield shards riveted to it as its points (rigid to the head)."""
    rng = np.random.default_rng(seed)
    Hp = head_points(person)
    top = float(Hp[:, 2].max())
    zc = top - CROWN["below_top_m"] / F
    axis = unit(np.array([0.0, -0.10, 1.0]))      # its front tipped up a little, as it sits on the brow
    yc = float(Hp[np.abs(Hp[:, 2] - zc) < 0.08 / F, 1].mean())
    c = np.array([0.0, yc, zc])
    hw = CROWN["band_m"] / F * 0.5
    segs = CROWN["segs"]
    R, ref, b = section(Hp, c, axis, hw * 1.2, segs)
    R = np.convolve(np.concatenate([R[-2:], R, R[:2]]), np.ones(5) / 5.0, "valid")
    g, t = CROWN["gap"] / F, CROWN["thick"] / F
    parts = []
    V, T = [], []
    for s in range(segs):
        ph = -math.pi + 2.0 * math.pi * (s + 0.5) / segs
        d = math.cos(ph) * ref + math.sin(ph) * b
        r0, r1 = R[s] + g, R[s] + g + t
        V += [c + d * r0 - axis * hw, c + d * r1 - axis * hw * 0.9, c + d * r1 + axis * hw * 0.9, c + d * r0 + axis * hw]
    for s in range(segs):
        a0, b0 = 4 * s, 4 * ((s + 1) % segs)
        for i in range(4):
            j = (i + 1) % 4
            T += [(a0 + i, b0 + i, b0 + j), (a0 + i, b0 + j, a0 + j)]
    V = np.asarray(V)
    T = sb.outward(V, np.asarray(T, np.int64), c)
    band_c = np.array([RUST_RGBA if (s * 7) % 5 == 0 else IRON_RGBA for s in range(segs) for _ in range(4)])
    parts.append((V, T, band_c, None))
    # the shards: from the front round both sides (none at the back of the head), each leaning out a little
    k = CROWN["points"]
    front = np.array([0.0, -1.0, 0.0])
    ph_front = math.atan2(float(front @ b), float(front @ ref))       # his front's angle in the ring
    for i in range(k):
        rel = (i - (k - 1) / 2.0) / ((k - 1) / 2.0)          # -1 .. 1, 0 the front
        ph = ph_front + rel * math.radians(128.0)
        d = math.cos(ph) * ref + math.sin(ph) * b
        si = int(((ph + math.pi) % (2.0 * math.pi)) / (2.0 * math.pi) * segs) % segs
        out_r = R[si] + g + t
        lean = math.radians(CROWN["lean_deg"])
        n_ = unit(d * math.cos(lean) - axis * math.sin(lean))
        up = unit(axis * math.cos(lean) + d * math.sin(lean))
        side = unit(np.cross(up, n_))
        w = CROWN["shard_w"] / F * (1.0 - 0.12 * abs(rel))
        h = CROWN["shard_h"] / F * (1.0 - 0.35 * abs(rel)) * rng.uniform(0.85, 1.1)
        base = c + d * (out_r - 0.01 / F) - axis * hw * 0.6
        # a broken shield's shard: a broad foot riveted to the band, its top split into two or three jagged points
        tips = rng.integers(2, 4)
        outline = [(-0.5 * w, 0.0), (0.5 * w, 0.0), (0.46 * w, 0.55 * h)]
        for j in range(tips):
            x0 = 0.42 * w - (j + 0.5) * 0.84 * w / tips
            outline.append((x0 + 0.18 * w / tips, h * rng.uniform(0.70, 0.80)))
            outline.append((x0, h * (1.0 if j == tips // 2 else rng.uniform(0.82, 0.95))))
            outline.append((x0 - 0.22 * w / tips, h * rng.uniform(0.66, 0.78)))
        outline.append((-0.46 * w, 0.52 * h))
        Vs, Ts = slab(outline, base, side, up, n_, CROWN["shard_t"] / F)
        paint = np.asarray(PAINT[i % len(PAINT)])
        mix = 0.55 + 0.25 * rng.uniform()
        rgb = paint * mix + np.ones(3) * (1.0 - mix)
        Cs = colour(len(Vs), (rgb[0], rgb[1], rgb[2], 1.0))
        uv = sb.planar_uv(Vs, Ts, n_, WOOD_TILE_M / F) + rng.uniform(0.0, 1.0, 2)
        parts.append((Vs, Ts, Cs, uv))
        # the iron rim of the shield along the shard's outer edge (its old edge) and a rivet-boss at its foot
        if i == (k - 1) // 2:
            boss_c = base + up * (0.34 * h) + n_ * (0.01 / F)
            Vb_, Tb_ = sb.icosphere(1)
            Vb_ = boss_c + (Vb_ * np.array([1.0, 1.0, 1.0])) * (0.07 / F)
            parts.append((Vb_, Tb_, colour(len(Vb_), IRON_RGBA), None))
    V, T, C, uv = merge(parts)
    p = piece_of("trophy_crown", V, T, C, uv, sb.rigid(len(V), "head"))
    p.facts = {"points": k, "ring_centre_m": [r6(x * F) for x in c], "top_m": r6(float(V[:, 2].max()) * F)}
    return p


def bell_piece(person, groups, kd, seed=311):
    """The great bell split and beaten into an oval shell over his gut (its mouth's lip flared at the bottom, its
    mouldings raised), lashed on with two iron straps round his trunk; its points on the skin's weights, stiffened."""
    rng = np.random.default_rng(seed)
    rest = person.rest
    Vb = person.body_V()
    m = person.bd.masks
    torso = (m["m_torso"] + m["m_pelvis"] > 0.4) & (np.abs(Vb[:, 0]) < 0.30 * float(np.ptp(Vb[:, 0])))
    z1 = float(rest.head["spine_03"][2]) + 0.12 / F
    z0 = float(rest.head["pelvis"][2]) - 0.08 / F
    yc = float(Vb[torso & (np.abs(Vb[:, 2] - 0.5 * (z0 + z1)) < 0.3 / F), 1].mean())
    rings, segs = BELL["rings"], BELL["segs"]
    cover = math.radians(BELL["cover_deg"])
    zs = np.linspace(z1, z0, rings)
    nb = 72
    Rz = []
    for z in zs:
        R, ref, b = section(Vb[torso], np.array([0.0, yc, z]), (0.0, 0.0, 1.0), 0.10 / F, nb, ref_hint=(1.0, 0.0, 0.0))
        Rz.append(R)
    Rz = np.asarray(Rz)
    # smooth over the rings and round each ring (the shell is beaten bronze, not a cast of his belly)
    for _ in range(3):
        Rz = 0.25 * np.roll(Rz, 1, axis=1) + 0.5 * Rz + 0.25 * np.roll(Rz, -1, axis=1)
        Rz[1:-1] = 0.25 * Rz[:-2] + 0.5 * Rz[1:-1] + 0.25 * Rz[2:]
    # (the bins' angle: atan2(p.b, p.ref); ref = (0,0,1) x (1,0,0) = (0,1,0) -> his back at 0, his front at +-pi)
    ang_bins = -math.pi + 2.0 * math.pi * (np.arange(nb) + 0.5) / nb
    t_ = np.linspace(0.0, 1.0, rings)
    # the bell's profile over his belly: its shoulder curling in to meet him at the top, its waist, its flared lip
    flare = BELL["flare_m"] / F * np.clip((t_ - 0.50) / 0.50, 0.0, 1.0) ** 2 \
        - 0.07 / F * np.clip(1.0 - t_ / 0.14, 0.0, 1.0) ** 2
    mould = 0.025 / F * (np.exp(-((t_ - 0.18) / 0.04) ** 2) + np.exp(-((t_ - 0.62) / 0.04) ** 2))
    g, th = BELL["gap"] / F, BELL["thick"] / F
    outer, inner = [], []
    for i, z in enumerate(zs):
        for s in range(segs):
            u = -cover + 2.0 * cover * s / (segs - 1)       # 0 his front
            ph = math.pi + u
            phw = (ph + math.pi) % (2.0 * math.pi) - math.pi
            r = float(np.interp(phw, ang_bins, Rz[i], period=2.0 * math.pi))
            d = math.cos(phw) * ref + math.sin(phw) * b
            ro = r + g + flare[i] + mould[i]
            outer.append(np.array([0.0, yc, z]) + d * ro)
            inner.append(np.array([0.0, yc, z]) + d * (r + g * 0.6 + flare[i] * 0.85))
    outer, inner = np.asarray(outer), np.asarray(inner)
    # the outer face is pushed clear of the skin wherever the rings' smoothing let it in
    outer = push_out(outer, kd, Vb, person.normals, g + th)
    inner = push_out(inner, kd, Vb, person.normals, g * 0.5)
    V = np.concatenate([outer, inner])
    n0 = len(outer)
    T = []
    for i in range(rings - 1):
        for s in range(segs - 1):
            a0, b0, a1, b1 = i * segs + s, i * segs + s + 1, (i + 1) * segs + s, (i + 1) * segs + s + 1
            T += [(a0, a1, b1), (a0, b1, b0)]
            T += [(n0 + a0, n0 + b1, n0 + a1), (n0 + a0, n0 + b0, n0 + b1)]
    # the rims: the top, the lip, the two cut sides
    for s in range(segs - 1):
        for i in (0, rings - 1):
            a0, b0 = i * segs + s, i * segs + s + 1
            T += [(a0, b0, n0 + b0), (a0, n0 + b0, n0 + a0)]
    for i in range(rings - 1):
        for s in (0, segs - 1):
            a0, a1 = i * segs + s, (i + 1) * segs + s
            T += [(a0, n0 + a1, a1), (a0, n0 + a0, n0 + a1)]
    T = np.asarray(T, np.int64)
    centre = np.array([0.0, yc + 0.0, 0.5 * (z0 + z1)])
    T = sb.outward(V, T, centre + np.array([0.0, 0.25 / F, 0.0]))
    # the bronze, patched with verdigris, darker in the mouldings and toward the lip
    C = []
    for k in range(len(V)):
        i = (k % n0) // segs
        v = rng.uniform()
        base = np.asarray(BRONZE_RGBA) * (0.92 + 0.16 * v)
        if rng.uniform() < 0.18:
            base = np.asarray(VERDIGRIS_RGBA) * (0.9 + 0.2 * v)
        if mould[i] > 0.01 / F:
            base = base * 0.82
        base[3] = 0.0
        C.append(base)
    parts = [(V, T, np.asarray(C), None)]
    # the straps: iron bands round his trunk over the shell's top and over its middle
    # (B3: the shell's outer face sampled at the strap's own height - its rings lie farther apart than the strap is
    # wide, so the band once passed under the shell and showed only its two ends at the sides)
    grid = outer.reshape(rings, segs, 3)
    for t in (0.20, 0.62):
        z = z1 + (z0 - z1) * t
        at_z = []
        for s in range(segs):
            col = grid[:, s, :]
            order = np.argsort(col[:, 2])
            at_z.append([float(np.interp(z, col[order, 2], col[order, k])) for k in range(3)])
        at_z = np.asarray(at_z)
        at_z[:, 2] = z
        ring_pts = np.concatenate([Vb[(np.abs(Vb[:, 2] - z) < 0.12 / F) & (m["m_torso"] + m["m_pelvis"] > 0.3)],
                                   outer[np.abs(outer[:, 2] - z) < 0.12 / F], at_z])
        Vs, Ts = sb.band_ring(np.array([0.0, yc, z]), (0.0, 0.0, 1.0), ring_pts, BELL["strap_w"] / F * 0.5,
                              BELL["strap_t"] / F, 0.02 / F, 24)
        parts.append((Vs, Ts, colour(len(Vs), IRON_RGBA), None))
    V, T, C, uv = merge(parts)
    g_, src = skin_weights(kd, groups, V, T, 6)
    p = piece_of("trophy_bell", V, T, C, uv, g_, src)
    p.facts = {"top_m": r6(z1 * F), "bottom_m": r6(z0 * F), "front_m": r6(float(-V[:, 1].max()) * F)}
    return p


def shoulder_top(person, side):
    """The skin's highest vertex over the shoulder joint on ``side`` (index, design point)."""
    Vb = person.body_V()
    sh = person.rest.head["upperarm_" + side]
    sgn = 1.0 if side == "l" else -1.0
    near = (np.linalg.norm(Vb[:, :2] - sh[:2], axis=1) < 0.16) & (np.sign(Vb[:, 0]) == sgn) & (Vb[:, 2] > sh[2] - 0.1)
    idx = np.where(near)[0]
    k = int(idx[np.argmax(Vb[idx, 2] + 0.35 * np.abs(Vb[idx, 0] - sh[0]) * 0.0)])
    return k, Vb[k]


def wheel_piece(person, side, groups, kd, seed=321):
    """A broken cart wheel dished over the shoulder: hub, spokes (some gone, stubs left), felloe and iron tyre (a
    length of both gone), each rim point bent out onto the shoulder's round; rigid on the shoulder top's weights."""
    rng = np.random.default_rng(seed + (0 if side == "l" else 17))
    Vb, Nb = person.body_V(), person.normals
    k, top = shoulder_top(person, side)
    sgn = 1.0 if side == "l" else -1.0
    # the wheel's axis: the shoulder's normal there, turned a little outward over the deltoid
    n = unit(Nb[k] + np.array([0.55 * sgn, 0.0, 0.0]))
    hub_base = top + n * (WHEEL["gap"] / F)
    hub_top = hub_base + n * (WHEEL["hub_l"] / F)
    ref = unit(np.cross(n, [0.0, 1.0, 0.0]))
    b = np.cross(n, ref)
    Rw = WHEEL["r"] / F
    segs = 40
    rim = []
    for s in range(segs):
        ph = 2.0 * math.pi * s / segs
        rim.append(hub_base + (math.cos(ph) * ref + math.sin(ph) * b) * Rw - n * (WHEEL["dish"] / F))
    rim = push_out(np.asarray(rim), kd, Vb, Nb, (WHEEL["gap"] + WHEEL["felloe"][1]) / F)
    gap0, gap1 = (math.radians(a) for a in WHEEL["rim_gap_deg"])
    # (the gap toward his back and down: phase measured from ref)
    keep = []
    for s in range(segs):
        ph = 2.0 * math.pi * s / segs
        keep.append(not (gap0 <= ph <= gap1))
    parts = []
    # the felloe and the tyre: the kept run of the rim (one open arc)
    start = next(s for s in range(segs) if keep[s] and not keep[s - 1])
    run = [rim[(start + j) % segs] for j in range(segs) if keep[(start + j) % segs]]
    run = np.asarray(run)
    fr = WHEEL["felloe"][0] / F * 0.5
    parts.append(wood_tube(run, np.full(len(run), fr), 5, close=(True, True), frame0=n))
    tyre = run + np.asarray([unit(p - hub_base) for p in run]) * (fr + WHEEL["tyre"][1] / F * 0.5)
    parts.append(iron_tube(tyre, np.full(len(run), WHEEL["tyre"][1] / F * 0.9), 4, frame0=n, rgba=RUST_RGBA))
    # the hub
    hub = np.array([hub_base - n * (0.04 / F), 0.5 * (hub_base + hub_top), hub_top])
    hr = WHEEL["hub_r"] / F
    parts.append(wood_tube(hub, np.array([hr * 0.9, hr, hr * 0.8]), 10, frame0=ref))
    parts.append(iron_tube(np.array([hub_top - n * (0.06 / F), hub_top + n * (0.01 / F)]), np.full(2, hr * 0.85), 10,
                           frame0=ref))
    # the spokes: from the hub's side out to the rim (missing ones: a stub)
    sp = WHEEL["spokes"]
    for i in range(sp):
        ph = 2.0 * math.pi * (i + 0.5) / sp
        s = int(round(ph / (2.0 * math.pi) * segs)) % segs
        a = hub_base + n * (0.12 / F) + (math.cos(ph) * ref + math.sin(ph) * b) * hr * 0.8
        end = rim[s]
        if i in WHEEL["missing"] or not keep[s]:
            end = a + (end - a) * rng.uniform(0.22, 0.38)
        mid = 0.5 * (a + end)
        parts.append(wood_tube(np.array([a, mid, end]), np.array([1.1, 1.0, 0.9]) * WHEEL["spoke_r"] / F, 5,
                               frame0=n))
    V, T, C, uv = merge(parts)
    p = piece_of("trophy_wheel_" + side, V, T, C, uv, fixed_weights(groups, k, len(V)))
    p.facts = {"hub_m": [r6(x * F) for x in hub_top], "radius_m": WHEEL["r"]}
    return p


def keg_piece(person, groups, kd, seed=331):
    """A hooped cask across the small of his back (bulged staves, four iron hoops, its heads), on a strap round his
    trunk over the bell's lower strap height; on the back skin's weights, stiffened."""
    rng = np.random.default_rng(seed)
    rest = person.rest
    Vb, m = person.body_V(), person.bd.masks
    z = float(rest.head["spine_01"][2]) + 0.06 / F
    back = (m["m_torso"] + m["m_pelvis"] > 0.4) & (np.abs(Vb[:, 0]) < 0.25) & (np.abs(Vb[:, 2] - z) < 0.12 / F)
    yb = float(Vb[back, 1].max())
    rk, L = KEG["r"] / F, KEG["length"] / F
    c = np.array([0.0, yb + rk * 0.88 + KEG["gap"] / F, z])
    xs = np.linspace(-0.5 * L, 0.5 * L, KEG["rings"])
    prof = rk * (0.84 + 0.16 * np.cos(np.linspace(-1.0, 1.0, KEG["rings"]) * math.pi * 0.5))
    path = c + np.outer(xs, [1.0, 0.0, 0.0])
    staves = KEG["staves"]
    radii = np.repeat(prof[:, None], staves, axis=1) * (1.0 + 0.025 * rng.standard_normal(staves))[None, :]
    parts = [wood_tube(path, radii, staves, close=(True, True), frame0=(0.0, 0.0, 1.0))]
    for h in KEG["hoops"]:
        x = -0.5 * L + h * L
        r = float(np.interp(x, xs, prof)) * 1.04
        parts.append(iron_tube(np.array([c + np.array([x - 0.035 / F, 0.0, 0.0]), c + np.array([x + 0.035 / F, 0.0, 0.0])]),
                               np.full(2, r), staves, close=(False, False), frame0=(0.0, 0.0, 1.0)))
    V, T, C, uv = merge(parts)
    # the strap round his trunk under the cask (over the bell's front when one is worn)
    zs = z - rk * 0.15
    ring_pts = np.concatenate([Vb[(np.abs(Vb[:, 2] - zs) < 0.12 / F) & (m["m_torso"] + m["m_pelvis"] > 0.3)], V])
    ring_pts = ring_pts[np.abs(ring_pts[:, 2] - zs) < 0.15 / F]
    Vs, Ts = sb.band_ring(np.array([0.0, float(Vb[back, 1].mean()) - 0.3, zs]), (0.0, 0.0, 1.0), ring_pts,
                          KEG["strap_w"] / F * 0.5, 0.04 / F, 0.03 / F, 32)
    V, T, C, uv = merge([(V, T, C, uv), (Vs, Ts, colour(len(Vs), ROPE_RGBA), None)])
    g_, src = skin_weights(kd, groups, V, T, 8)
    p = piece_of("trophy_keg", V, T, C, uv, g_, src)
    p.facts = {"centre_m": [r6(x * F) for x in c], "radius_m": KEG["r"]}
    return p


def link(c, along, across, L, W, wr, segs=6, sides=4):
    al, ac = unit(along), unit(across)
    nrm = np.cross(al, ac)
    pts = np.array([c + al * (0.5 * (L - wr * 2)) * math.cos(2.0 * math.pi * i / segs)
                    + ac * (0.5 * (W - wr * 2)) * math.sin(2.0 * math.pi * i / segs) for i in range(segs)])
    V, T = [], []
    for i in range(segs):
        tang = unit(pts[(i + 1) % segs] - pts[i - 1])
        u = unit(np.cross(tang, nrm))
        w = np.cross(tang, u)
        for s in range(sides):
            ph = 2.0 * math.pi * s / sides + math.pi / sides
            V.append(pts[i] + wr * (math.cos(ph) * u + math.sin(ph) * w))
    for i in range(segs):
        for s in range(sides):
            a0, b0 = i * sides + s, i * sides + (s + 1) % sides
            a1, b1 = ((i + 1) % segs) * sides + s, ((i + 1) % segs) * sides + (s + 1) % sides
            T += [(a0, a1, b1), (a0, b1, b0)]
    V, T = np.asarray(V), np.asarray(T, np.int64)
    nr = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    if float(np.einsum("ij,ij->i", nr, V[T].mean(axis=1) - pts[T[:, 0] // sides]).sum()) < 0:
        T = T[:, ::-1]
    return V, T


def helmet(c, down, face, kind, rng):
    """A man's helmet hung by its strap: a kettle hat (a dome and a broad brim) or a nasal helm (a tall cap and its
    nasal), its crown toward ``-down``, its front toward ``face``."""
    up = -unit(down)
    f = unit(face - up * float(face @ up))
    s = np.cross(up, f)
    r = 0.19 / F
    Vs, Ts = [], []
    rings, segs = 5, 10
    V = []
    for i in range(rings + 1):
        a = (math.pi * 0.5) * i / rings
        rr = r * math.cos(a) * (1.0 if kind == "kettle" else 0.92)
        hz = r * math.sin(a) * (1.0 if kind == "kettle" else 1.35)
        for k in range(segs):
            ph = 2.0 * math.pi * k / segs
            V.append(c + up * hz + (math.cos(ph) * f + math.sin(ph) * s) * max(rr, 1e-5))
    T = []
    for i in range(rings):
        for k in range(segs):
            a0, b0 = i * segs + k, i * segs + (k + 1) % segs
            T += [(a0, b0, b0 + segs), (a0, b0 + segs, a0 + segs)]
    V = np.asarray(V)
    T = sb.outward(V, np.asarray(T, np.int64), c + up * r * 0.3)
    Vs.append(V)
    Ts.append(T)
    if kind == "kettle":
        brim = [c + (math.cos(2.0 * math.pi * k / segs) * f + math.sin(2.0 * math.pi * k / segs) * s) * r * w
                - up * (0.02 / F) * (1.0 if w > 1.2 else 0.0) for w in (0.98, 1.55) for k in range(segs)]
        Vbm = np.asarray(brim)
        Tb = []
        for k in range(segs):
            a0, b0 = k, (k + 1) % segs
            Tb += [(a0, b0, segs + b0), (a0, segs + b0, segs + a0)]
        Tb = np.asarray(Tb, np.int64)
        Vs.append(Vbm)
        Ts.append(np.concatenate([Tb, Tb[:, ::-1]]))
    else:
        nas = [c + f * r * 0.95 + up * (0.02 / F), c + f * r * 1.02 - up * (0.11 / F)]
        Vn, Tn, _r, _a = sb.tube(np.asarray(nas), np.full(2, 0.022 / F), 4)
        Vs.append(Vn)
        Ts.append(Tn)
    off = 0
    TT = []
    for V_, T_ in zip(Vs, Ts):
        TT.append(T_ + off)
        off += len(V_)
    Vall = np.concatenate(Vs)
    rust = rng.uniform() < 0.5
    return Vall, np.concatenate(TT), colour(len(Vall), RUST_RGBA if rust else IRON_RGBA)


def chain_belt_piece(person, groups, kd, seed=341):
    """A heavy chain round his hips over the belt, sagging under the gut in front, five men's helmets hung from it
    (kettle hats and nasal helms); every link on the weights of the skin under it, stiffened."""
    rng = np.random.default_rng(seed)
    rest = person.rest
    Vb, m = person.body_V(), person.bd.masks
    hip = float(rest.head["thigh_l"][2])
    z = hip + 0.20 / F
    band = (m["m_torso"] + m["m_pelvis"] + m["m_upperleg"] > 0.3) & (np.abs(Vb[:, 2] - z) < 0.30 / F)
    pts = Vb[band]
    yc = float(pts[:, 1].mean())
    nl = CHAIN["links"]
    R, ref, b = section(pts, np.array([0.0, yc, z]), (0.0, 0.0, 1.0), 0.30 / F, nl, ref_hint=(1.0, 0.0, 0.0))
    R = np.convolve(np.concatenate([R[-1:], R, R[:1]]), np.ones(3) / 3.0, "valid")
    path = []
    for i in range(nl):
        ph = -math.pi + 2.0 * math.pi * (i + 0.5) / nl
        d = math.cos(ph) * ref + math.sin(ph) * b
        front = max(0.0, float(-d[1]))                     # 1 at his front
        sag = CHAIN["sag_m"] / F * front ** 2.5
        p = np.array([0.0, yc, z]) + d * (R[i] + 0.05 / F) - np.array([0.0, 0.0, sag])
        path.append(p)
    path = push_out(np.asarray(path), kd, Vb, person.normals, 0.07 / F)
    parts = []
    L, W, wr = CHAIN["length"] / F, CHAIN["width"] / F, CHAIN["wire"] / F
    for i in range(nl):
        a, c_ = path[i], path[(i + 1) % nl]
        along = c_ - a
        out = unit(np.cross(along, [0.0, 0.0, 1.0]))
        across = np.array([0.0, 0.0, 1.0]) if i % 2 == 0 else out
        Vl, Tl = link(0.5 * (a + c_), along, across, max(L, float(np.linalg.norm(along)) * 1.25), W, wr)
        parts.append((Vl, Tl, colour(len(Vl), IRON_RGBA if i % 3 else RUST_RGBA), None))
    # the helmets: on the links of his front and sides
    want = np.linspace(-0.75, 0.75, CHAIN["helmets"])
    for j, w in enumerate(want):
        ph = math.atan2(-1.0, 0.0) + w * math.pi * 0.62
        i = int(((ph + math.pi) / (2.0 * math.pi) * nl)) % nl
        hang = path[i] + np.array([0.0, 0.0, -0.20 / F])
        out = unit(np.array([hang[0], hang[1] - yc, 0.0]))
        c_ = hang + out * (0.10 / F)
        Vh, Th, Ch = helmet(c_, np.array([0.0, 0.0, -1.0]) * 0.6 + out * 0.8, out, "kettle" if j % 2 == 0 else "nasal",
                            rng)
        parts.append((Vh, Th, Ch, None))
        Vs_, Ts_, _r, _a = sb.tube(np.array([path[i], c_ + np.array([0.0, 0.0, 0.08 / F])]), np.full(2, 0.02 / F), 4)
        parts.append((Vs_, Ts_, colour(len(Vs_), ROPE_RGBA), None))
    V, T, C, uv = merge(parts)
    g_, src = skin_weights(kd, groups, V, T, 10)
    p = piece_of("chain_belt", V, T, C, uv, g_, src)
    p.facts = {"links": nl, "helmets": CHAIN["helmets"]}
    return p


def ram_piece(person):
    """The battering ram (rigid to hand_r): an oak log through the right fist along its grip line, a rope grip, three
    iron bands, two carrying rings, an iron cap on its head."""
    g, ax = person.grip["r"]
    ax = unit(ax)
    ref = unit(np.cross(ax, [0.0, 0.0, 1.0]))
    rg = person.grip_radius
    hl, L, R, cap = RAM["handle_m"] / F, RAM["length_m"] / F, RAM["r"] / F, RAM["cap_m"] / F
    s = np.array([-hl, -0.2 * hl, 0.25 / F, 0.65 / F, 1.4 / F, 2.4 / F, 3.4 / F, L - cap - 0.05 / F])
    r = np.array([rg * 1.05, rg, rg * 1.05, R * 0.82, R * 0.95, R, R * 1.02, R * 1.04])
    path = g + np.outer(s, ax)
    parts = [wood_tube(path, r, RAM["segs"], close=(True, False), frame0=ref)]
    # the rope grip over the handle
    s2 = np.linspace(-hl * 0.95, 0.28 / F, 6)
    r2 = np.interp(s2, s, r) * 1.10
    parts.append(iron_tube(g + np.outer(s2, ax), r2, 8, frame0=ref, rgba=ROPE_RGBA))
    for bs in RAM["bands"]:
        bs_ = bs / F
        rr = float(np.interp(bs_, s, r)) * 1.07
        parts.append(iron_tube(g + np.outer([bs_ - 0.06 / F, bs_ + 0.06 / F], ax), np.full(2, rr), RAM["segs"],
                               close=(False, False), frame0=ref))
    w = np.cross(ax, ref)
    for rs in RAM["rings"]:
        rs_ = rs / F
        rr = float(np.interp(rs_, s, r))
        for side in (1.0, -1.0):
            c = g + ax * rs_ + w * side * (rr + 0.10 / F)
            pts = [c + (math.cos(2.0 * math.pi * k / 10) * ax + math.sin(2.0 * math.pi * k / 10) * w * side) * (0.12 / F)
                   for k in range(11)]
            parts.append(iron_tube(np.asarray(pts), np.full(11, 0.03 / F), 4, frame0=ref))
    # the iron cap: a sleeve over the head, flaring to a blunt boss
    cs = L - cap + np.array([-0.05, 0.0, 0.25, 0.55, 0.72, 0.80]) / F * (cap * F / 0.75)
    cr = np.array([R * 1.06, R * 1.10, R * 1.12, R * 1.20, R * 1.05, R * 0.55])
    parts.append(iron_tube(g + np.outer(cs, ax), cr, RAM["segs"], close=(False, True), frame0=ref))
    V, T, C, uv = merge(parts)
    p = piece_of("ram", V, T, C, uv, sb.rigid(len(V), "hand_r"))
    head = g + ax * (L - 0.1 / F)
    p.head_point = head
    p.facts = {"length_m": r6((L + hl) * F), "grip_r_m": r6(rg * F), "head_r_m": r6(R * 1.2 * F)}
    return p


# ======================================================================================================================
# the wood texture
# ======================================================================================================================
def wood_textures(out_dir):
    """ogre_king_wood_albedo.png / _normal.png (DETAIL_PX, tileable): weathered oak, the grain down V, its checks
    (dark splits along the grain), a few knots, the boards' tone apart."""
    import people_bake as pbk
    n = DETAIL_PX
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx.ravel() / n, yy.ravel() / n

    def height(uu, vv):
        Q = np.stack([np.cos(2 * math.pi * uu) * 6.0, np.sin(2 * math.pi * uu) * 6.0,
                      np.cos(2 * math.pi * vv) * 0.6 + np.sin(2 * math.pi * vv) * 0.5], axis=-1)
        grain = pbk.fbm(Q, 2.0, 251, 4)
        rings = 0.5 + 0.5 * np.sin(2 * math.pi * (uu * 9.0 + 0.6 * grain))
        P = sb._torus(uu, vv)
        check = np.clip((pbk.fbm(Q * np.array([1.5, 1.5, 0.5]), 3.0, 253, 3) - 0.66) / 0.06, 0.0, 1.0)
        knot_f1, _f2 = sb._worley(uu, vv, 3, 255)
        knot = np.clip(1.0 - knot_f1 / 0.12, 0.0, 1.0) * (pbk.vnoise(P, 2.0, 257) > 0.55)
        return 0.55 * grain + 0.25 * rings - 0.8 * check + 0.3 * knot, grain, rings, check, knot

    h, grain, rings, check, knot = height(u, v)
    P = sb._torus(u, v)
    tone = pbk.fbm(P, 1.5, 259, 3)
    base = np.array([0.40, 0.30, 0.20])
    col = base[None, :] * (0.62 + 0.55 * grain + 0.18 * rings + 0.30 * (tone - 0.5))[:, None]
    grey = np.array([0.42, 0.40, 0.37])
    weather = np.clip((pbk.fbm(P, 2.5, 261, 3) - 0.45) / 0.25, 0.0, 1.0)[:, None] * 0.45
    col = col * (1.0 - weather) + grey[None, :] * (0.7 + 0.5 * grain[:, None]) * weather
    col *= (1.0 - 0.65 * check)[:, None]
    col = col * (1.0 - 0.4 * knot[:, None]) + np.array([0.22, 0.15, 0.10])[None, :] * 0.4 * knot[:, None]
    e = 1.0 / n
    dx = (height(u + e, v)[0] - height(u - e, v)[0]) / (2.0 * e) / n
    dy = (height(u, v + e)[0] - height(u, v - e)[0]) / (2.0 * e) / n
    nrm = np.stack([-dx * 14.0, dy * 14.0, np.ones_like(dx)], axis=-1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    paths = {}
    for k, arr in (("albedo", pbk.to_u8(np.clip(col, 0.0, 1.0).reshape(n, n, 3))),
                   ("normal", pbk.to_u8((nrm * 0.5 + 0.5).reshape(n, n, 3)))):
        p = os.path.join(out_dir, "%s_wood_%s.png" % (KIND, k))
        pbk.save_png(p, arr)
        paths["wood_" + k] = os.path.basename(p)
    return paths


# ======================================================================================================================
# the build
# ======================================================================================================================
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


def repaint_ogre(out_dir, LV, LT, Luv, tan, sgn, nor, S, ears):
    """The ogres' hide (brute.repaint's "ogre") over the King's bake: its files written under the ogres' names in a
    scratch folder and moved to his."""
    import shutil
    import tempfile
    with tempfile.TemporaryDirectory(prefix="ogre_king_paint_") as tmp:
        for k in ("albedo", "normal", "orm"):
            shutil.copyfile(os.path.join(out_dir, "%s_%s.png" % (KIND, k)), os.path.join(tmp, "ogre_%s.png" % k))
        br.repaint("ogre", tmp, LV, LT, Luv, tan, sgn, nor, S, ears=ears)
        for k in ("albedo", "normal", "orm"):
            shutil.copyfile(os.path.join(tmp, "ogre_%s.png" % k), os.path.join(out_dir, "%s_%s.png" % (KIND, k)))


def build(out_dir, work_dir):
    import bpy
    import giant_body as gb
    import ogre_king_moves as mv
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
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
    extras = [eyes, br.tusks_piece(p0)]
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
        raise SystemExit("ogre_king: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the pieces
    groups23 = pr.fold_weights(p0.groups53())
    kdb = cKDTree(p0.body_V())
    pieces = {"trophy_crown": crown_piece(p0), "trophy_bell": bell_piece(p0, groups23, kdb),
              "trophy_wheel_l": wheel_piece(p0, "l", groups23, kdb), "trophy_wheel_r": wheel_piece(p0, "r", groups23, kdb),
              "trophy_keg": keg_piece(p0, groups23, kdb), "chain_belt": chain_belt_piece(p0, groups23, kdb),
              "ram": ram_piece(p0)}
    log("pieces: " + ", ".join("%s %d" % (n, p.tris()) for n, p in pieces.items()))
    for name, p in pieces.items():
        if p.tris() > GEAR_BUDGET[name]:
            raise SystemExit("ogre_king: %s has %d triangles, over %d" % (name, p.tris(), GEAR_BUDGET[name]))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(KING_GAITS)
    poses, gaits, checks = mv.make_poses(p0, pieces["ram"])
    # ---- the bake and the hide
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(KIND, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras)])
    repaint_ogre(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, p0.bd.verts[:N][p0.bd.masks["m_ears"] > 0.3])
    detail_files = wood_textures(out_dir)
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("ogre_king_body")
    wood = bpy.data.materials.new("ogre_king_wood")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    rest_h = pbody.rest_matrices(arm)["hand_r"]
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in TROPHIES + GEAR:
        p = pieces[name]
        o = br.skinned_object(name, p, arm, coll, wood, F)
        ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(p.rgba, np.float32).ravel())
        o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        info_p = {"node": name, "tris": p.tris(), "material": "wood", "bone": PIECE_BONE[name],
                  "trophy": name in TROPHIES}
        info_p.update(getattr(p, "facts", {}) or {})
        if name == "ram":
            H = rest_h
            info_p["head_local"] = [r6(x) for x in (H[:3, :3].T @ (p.head_point * F - H[:3, 3]))]
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
    crown_top = float(pieces["trophy_crown"].V[:, 2].max()) * F
    # the idle's crown height (the top of the head carried by the head bone, and the crown's top)
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
            "pieces": piece_info, "trophies": list(TROPHIES), "detail": detail_files,
            "detail_tile_m": {"wood": WOOD_TILE_M}, "checks": checks,
            "used_by": ["enemy.ogre_king (B2: OgreKingRig)", "tools/ogre_king_stills.gd"]}
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
        raise SystemExit("ogre_king clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
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
        raise SystemExit("usage: ogre_king.py ogre_king <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
