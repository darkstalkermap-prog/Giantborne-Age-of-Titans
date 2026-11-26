"""The Frostbound Titan (D1): the fifth signature titan - an original giant of the old kings' northern watch 28.0 m
(91.9 ft) tall, bound in the ice of the Hoarcrown, as an asset (``build_people.py --frostbound``).

When the old giant kings chained the Worldbreaker under the mountains they set a watcher on the Hoarcrown's shoulder,
in a cairn of their own stones, and the cold took him there: he slept a thousand winters and the glacier grew over
him. The throne's fall broke the locks; the cairn split and he came down the ice. Underneath he is still a body - the
people's CC0 human with MakeHuman's macros, ``giant_body.proportioned`` with a table of his own and ``brute.reshape``
- so he stands and moves as an old, long-limbed giant, not a crystal golem: gaunt and stooped, the neck long and thrust
forward, the arms long enough to rake the ground, the face hollow-cheeked, long-nosed and deep-eyed. His skin is
cold grey-blue, rimed white where the frost settles (the tops of the shoulders, the brow, the hands), the fingers and
toes frost-black. Over it the ice he wears, each its own skinned mesh on the people's 23 bones:

  crown         the old kings' cairn: its capstones (dark weathered stone, the giant kings' own) frozen into a cap of
                blue ice over his brow and crown, ringed with upright ice spikes
  pauldron_l, pauldron_r
                ice crusted over each shoulder in slabs, broken into jutting shards along their outer edge
  serac         the ridge of the glacier on his back: a slab of ice over the shoulder blades, and out of it a crest
                of tall blade-shards along the spine, leaning back - his silhouette
  heart         the heart-ice: a slab of clear ice over his breast with a cold-glowing core of crystal in it
  gauntlet      the right forearm sheathed in ice and the fist inside a mass of it the size of a boulder, shards at
                the knuckles (his club)
  greave_l, greave_r
                ice down each shin, icicles at their lower rims
  beard         icicles hanging from his jaw and chin (gear: not a plate)
  rime          icicles hanging from the left forearm and the elbows, and from the belt's hem (gear)
  frostbound_far the idle's first key, decimated

The ice is drawn by ice_plate.gdshader on Stoneback's stone normal map (the chips and fractures): vertex colour alpha
1 ice (its colour the ice's depth: blue-white to deep blue), alpha 0 the cairn's stone (Stoneback's stone texture),
alpha 0.35 the heart's glow. No texture of his own beyond his atlas.

Clips on his skeleton (``frostbound_moves.py``): dormant (frozen kneeling), wake (his intro: he rises out of the ice
and roars), idle, walk, run, rake, fist, breath, stamp, sweep, roar2, hurl, nova, reel, kneel, rise, death.

``python frostbound.py frostbound <out dir> <work dir>`` writes frostbound.glb, frostbound_clips.glb, the atlas
(frostbound_albedo.png 512 px, _normal.png, _orm.png 256 px) and frostbound_info.json.
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

KIND = "frostbound"
HEIGHT_M = 28.0                    # 91.9 ft: over a stage-7 giant (23.77 m) by a head and shoulders, under stage 8's
DESIGN = pr.DESIGN_HEIGHT_M        # 29.26 m
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.36 * HEIGHT_M           # a long, slow stride (10.1 m): the legs are long, the weight on them old
TRIS = 9000
MARGIN_TRIS = 60
FAR_TRIS = 340
OUTFIT = ("kilt", "loincloth", "belt")
OUTFIT_MATERIAL = {"kilt": "leather", "loincloth": "dark_leather", "belt": "dark_leather"}

# ---- the body ------------------------------------------------------------------------------------------------------
# an old watcher's face, starved by the cold: long and narrow, the cheeks hollow under high bones, the nose long and
# hooked, the eyes small and deep under a heavy level brow, the mouth thin and wide, the jaw long
FROST_FACE = {"head/head-oval": 1.0, "head/head-age-decr-incr": 1.0, "head/head-scale-horiz-decr-incr": -0.45,
              "head/head-fat-decr-incr": -0.8, "cheek/cheek-bones-decr-incr": 1.0, "cheek/cheek-volume-decr-incr": -1.0,
              "cheek/cheek-inner-decr-incr": -0.7, "nose/nose-scale-vert-decr-incr": 0.75,
              "nose/nose-hump-decr-incr": 0.8, "nose/nose-scale-horiz-decr-incr": -0.15,
              "nose/nose-point-width-decr-incr": -0.3,
              "chin/chin-height-decr-incr": 0.7, "chin/chin-prominent-decr-incr": 0.55,
              "chin/chin-width-decr-incr": -0.25, "chin/chin-bones-decr-incr": 0.6,
              "eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -0.9,
              "eyebrows/eyebrows-angle-down-up": 0.2, "eyes/eye-scale-decr-incr": -0.45,
              "eyes/eye-bag-decr-incr": 0.9, "eyes/eye-eyefold-down-up": -0.6,
              "forehead/forehead-temple-decr-incr": 0.0, "forehead/forehead-scale-vert-decr-incr": 0.4,
              "mouth/mouth-scale-horiz-decr-incr": 0.35, "mouth/mouth-lowerlip-volume-decr-incr": 0.0,
              "mouth/mouth-upperlip-volume-decr-incr": -0.6, "mouth/mouth-angles-down-up": -0.6,
              "mouth/mouth-laugh-lines-in-out": 1.0, "neck/neck-scale-horiz-decr-incr": -0.4,
              "ears/ear-scale-decr-incr": 0.3, "ears/ear-lobe-decr-incr": 0.6}
# long in the leg and very long in the arm, narrow in the waist, the neck long, the head small (it reads gaunt), big
# hands and feet; stooped at the upper back, the head carried forward and lifted to look ahead
FROST_PROP = dict(legs=1.07, torso=0.99, neck=0.016, head=0.80, arms=1.15, hands=1.20, shoulders=0.024,
                  deltoids=0.002, trapezius=0.012, thighs=-0.03)
FROST_SHAPE = dict(hunch_deg=11.0, head_back_deg=9.0, jaw=(0.20, 0.016, 0.006), underbite_m=0.0, brow_m=0.030,
                   brow_band_m=0.012, nose=(0.006, 0.004), ears=0.0, hands=1.10, feet=1.10, gut_m=0.0, tusks=False)
VARIANT = dict(name=KIND, macro=br._macro(80, 0.78, 0.36, african=0.10, asian=0.25, caucasian=0.65),
               face=br._face(1.0, **FROST_FACE), prop=FROST_PROP, shape=FROST_SHAPE, height_m=HEIGHT_M)
FROST_GAITS = {
    "frostbound_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.05, min_drop=0.035, lean_deg=7.0,
                            pelvis_pitch_deg=4.0, roll_deg=3.5, sway=0.05, arm_swing_deg=10.0, heel_rocker=0.13,
                            lift=0.13),
    "frostbound_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.10, min_drop=0.08, lean_deg=14.0,
                           pelvis_pitch_deg=7.0, lift=0.34),
}

# ---- the colours (linear vertex colours; ice_plate.gdshader: alpha 1 ice, 0 the cairn's stone, 0.35 the heart's glow)
ICE_RGBA = (0.58, 0.70, 0.79, 1.0)                 # clear glacier ice, a pale grey-blue
DEEP_RGBA = (0.33, 0.48, 0.61, 1.0)                # thick ice, its blue deeper
RIME_RGBA = (0.84, 0.87, 0.90, 1.0)                # frost-white: rime on the ice's upper faces and the shard tips
CAIRN_RGBA = (0.78, 0.78, 0.80, 0.0)               # the cairn's capstones (the stone texture, a cold grey)
GLOW_RGBA = (0.42, 0.66, 0.86, 0.35)               # the heart's core
STONE_TILE_M = 3.4                 # Stoneback's stone normal map repeats every this many metres
SHARP_DEG = 20.0

# ---- the plates: Stoneback's slab code on his body (thicker: ice, not stone), with what makes them his --------------
# piece: (Stoneback's footprint, (thickness, gap, chamfer, cut faces, decimation budget) real metres)
SLABS = {
    "pauldron_l": ("plate_shoulder_l", (0.70, 0.06, 0.20, 3, 520)),
    "pauldron_r": ("plate_shoulder_r", (0.70, 0.06, 0.20, 3, 520)),
    "serac": ("plate_back", (0.80, 0.06, 0.26, 3, 560)),
    "crown": ("plate_brow", (0.46, 0.05, 0.12, 9, 360)),
    "heart": ("plate_chest", (0.80, 0.05, 0.22, 5, 460)),
    "gauntlet": ("plate_forearm_r", (0.58, 0.05, 0.16, 3, 300)),
    "greave_l": ("plate_shin_l", (0.60, 0.05, 0.15, 3, 300)),
    "greave_r": ("plate_shin_r", (0.60, 0.05, 0.15, 3, 300)),
}
PLATE_ORDER = ("crown", "pauldron_l", "pauldron_r", "serac", "heart", "gauntlet", "greave_l", "greave_r")
GEAR = ("beard", "rime")
# the regions the fight package names (data/enemies/frostbound.json): the plate -> its region
WEAK_POINTS = {"crown": "head", "pauldron_l": "shoulder_l", "pauldron_r": "shoulder_r", "serac": "back",
               "heart": "chest", "gauntlet": "forearm_r", "greave_l": "shin_l", "greave_r": "shin_r"}
# the main bone of each piece (the rig's break: where its shards fly from)
PIECE_BONE = {"crown": "head", "pauldron_l": "upperarm_l", "pauldron_r": "upperarm_r", "serac": "spine_03",
              "heart": "spine_03", "gauntlet": "hand_r", "greave_l": "calf_l", "greave_r": "calf_r", "beard": "head",
              "rime": "spine_01"}
# the crest on his back: (count, the tallest's length real m, its base's half width real m)
CREST = dict(count=7, tallest_m=6.4, base_m=0.95)
GAUNTLET = dict(radius_m=2.5, along_m=1.25, out_m=0.35, shards=9, shard_m=1.3)
GEAR_BUDGET = {"crown": 980, "pauldron_l": 860, "pauldron_r": 860, "serac": 1500, "heart": 1000, "gauntlet": 1100,
               "greave_l": 560, "greave_r": 560, "beard": 420, "rime": 620}
CLIP_LOOPS = ("idle", "walk", "run", "dormant")
# the plate footprint of his breast (Stoneback had none): the plate's form for the slab code
CHEST_FORM = dict(chips=13, deep=(0.14, 0.34), upper=None, crack=True, bands=(), most=1.3)
SHARD_SIDES = 5


def log(*a):
    print("[frostbound]", *a, flush=True)


r6 = br.r6
unit = sb.unit
_sstep = br._sstep


# ======================================================================================================================
# geometry helpers (design scale)
# ======================================================================================================================
def shard(base, direction, length, radius, rng, sides=5, bend=0.0, bend_dir=None, rings=4):
    """An ice shard: a faceted spike (``sides`` faces: crystal, not a cone) from ``base`` along ``direction``,
    ``length`` long, ``radius`` at its foot, tapering to a point, its axis bowed ``bend`` (a share of its length)
    toward ``bend_dir``. (V, T) wound outward."""
    d = unit(direction)
    if bend_dir is None:
        bend_dir = unit(np.cross(d, [0.0, 0.0, 1.0]) if abs(d[2]) < 0.95 else np.cross(d, [1.0, 0.0, 0.0]))
    bend_dir = unit(np.asarray(bend_dir) - d * float(np.asarray(bend_dir) @ d))
    ts = np.linspace(0.0, 1.0, rings)
    path = np.array([base + d * length * t + bend_dir * bend * length * t * t for t in ts])
    # the faces' widths a little uneven (a crystal), tapering faster near the tip
    jitter = rng.uniform(0.82, 1.18, sides)
    radii = np.array([[radius * (1.0 - t) ** 1.15 * jitter[s] + 1e-4 for s in range(sides)] for t in ts])
    radii[-1] = 1e-4
    V, T, _ring, _ang = sb.tube(path, radii, sides, close=(True, False), frame0=rng.normal(0.0, 1.0, 3))
    return V, T


def ice_colour(V, normals_up, rng, base=ICE_RGBA, deep=DEEP_RGBA, rime=RIME_RGBA, tip=None):
    """Each vertex's ice colour: the ice's own between clear and deep by a slow noise, white rime where the face looks
    up (``normals_up`` (n,) the normal's z), whiter toward a shard's tip (``tip`` (n,) 0..1)."""
    import people_bake as pbk
    n = len(V)
    depth = np.clip(pbk.fbm(np.asarray(V) * 3.0, 2.0, 901) * 1.4 - 0.2, 0.0, 1.0)
    c = np.asarray(base)[None, :3] * (1.0 - depth[:, None]) + np.asarray(deep)[None, :3] * depth[:, None]
    frost = _sstep(np.asarray(normals_up), 0.55, 0.95) * 0.55 * _sstep(pbk.fbm(np.asarray(V) * 2.0, 3.0, 903), 0.35, 0.6)
    if tip is not None:
        frost = np.maximum(frost, _sstep(np.asarray(tip), 0.70, 1.0) * 0.45)
    frost = np.clip(frost + rng.uniform(-0.05, 0.05, n), 0.0, 1.0)
    c = c * (1.0 - frost[:, None]) + np.asarray(rime)[None, :3] * frost[:, None]
    return np.concatenate([c, np.ones((n, 1))], axis=1)


def vertex_up(V, T):
    """Each vertex's normal's z (the mean of its faces' normals)."""
    V = np.asarray(V)
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    acc = np.zeros_like(V)
    for k in range(3):
        np.add.at(acc, T[:, k], nrm)
    acc /= np.maximum(np.linalg.norm(acc, axis=1, keepdims=True), 1e-12)
    return acc[:, 2]


def merge(parts, tile):
    """[(V, T, rgba (n,4) or one rgba)] -> V, T, rgba, corner uv (a box map at ``tile`` design m)."""
    Vs, Ts, Cs = [], [], []
    off = 0
    for V, T, C in parts:
        V = np.asarray(V, np.float64)
        T = np.asarray(T, np.int64)
        C = np.asarray(C, np.float64)
        if C.ndim == 1:
            C = np.tile(C, (len(V), 1))
        Ts.append(T + off)
        Vs.append(V)
        Cs.append(C)
        off += len(V)
    V, T = np.concatenate(Vs), np.concatenate(Ts)
    return V, T, np.concatenate(Cs), sb.box_uv(V, T, tile)


def nearest_groups(groups, src_V, V, kd=None):
    from scipy.spatial import cKDTree
    kd = kd or cKDTree(src_V)
    i = kd.query(V)[1]
    return {b: w[i] for b, w in groups.items()}


ICE_SEEDS = {"crown": 1001, "pauldron_l": 1002, "pauldron_r": 1003, "serac": 1004, "heart": 1005, "gauntlet": 1006,
             "greave_l": 1007, "greave_r": 1008}


def ice_piece(p):
    """A slab piece of Stoneback's code recoloured as ice: the stone's shade -> ice by depth and rime."""
    rng = np.random.default_rng(ICE_SEEDS[p.name])
    up = vertex_up(p.V, p.T)
    p.rgba = ice_colour(p.V, up, rng)
    return p


def add_parts(p, parts, tile):
    """The parts [(V, T, rgba)] merged into piece ``p``, each part's points weighted as the piece's nearest point."""
    import people_outfit as po
    from scipy.spatial import cKDTree
    Vn, Tn, Cn, UVn = merge(parts, tile)
    kd = cKDTree(p.V)
    g_new = nearest_groups(p.groups, p.V, Vn, kd)
    src_new = np.asarray(p.attach)[kd.query(Vn)[1]] if getattr(p, "attach", None) is not None else np.full(len(Vn), -1)
    V = np.concatenate([p.V, Vn])
    T = np.concatenate([p.T, Tn + len(p.V)])
    rgba = np.concatenate([np.asarray(p.rgba), Cn])
    uv = np.concatenate([np.asarray(p.uv), UVn])
    g = {b: np.concatenate([w, g_new[b]]) for b, w in p.groups.items()}
    q = po.Piece(p.name, V, T, np.full(len(T), po.MATS.index("metal")), g, np.concatenate([p.attach, src_new]))
    q.uv = uv
    q.rgba = rgba
    q.facts = dict(getattr(p, "facts", {}) or {})
    q.facts["tris"] = int(len(T))
    return q


def rigid_piece(name, V, T, rgba, uv, bone):
    import people_outfit as po
    p = po.Piece(name, V, T, np.full(len(T), po.MATS.index("metal")), {b: (np.ones(len(V)) if b == bone else
                                                                          np.zeros(len(V))) for b in pr.BONES},
                 np.full(len(V), -1))
    p.uv = uv
    p.rgba = rgba
    return p


def shard_part(base, direction, length, radius, rng, **kw):
    V, T = shard(base, direction, length, radius, rng, **kw)
    d = unit(direction)
    tip = np.clip(((V - base) @ d) / max(length, 1e-9), 0.0, 1.0)
    return V, T, ice_colour(V, vertex_up(V, T), rng, tip=tip)


# ======================================================================================================================
# the footprint of his breast (Stoneback's code knows the others)
# ======================================================================================================================
def chest_footprint(person):
    """The heart-ice's footprint: the breast between the nipples' line and the collar bones, the breastbone's middle,
    front-facing, clear of the arms and the neck."""
    bd = person.bd
    V = bd.verts[:N]
    J = bd.joints
    m = bd.masks
    nb = person.normals_h
    sh_l, sh_r = J["joint-l-shoulder"], J["joint-r-shoulder"]
    mid = 0.5 * (sh_l + sh_r)
    half = abs(sh_l[0] - sh_r[0]) * 0.5
    import people_bake as pbk
    c = np.array([0.0, mid[1], mid[2] - 0.075])
    Q = V - c
    d = np.sqrt((Q[:, 0] / (half * 0.80)) ** 2 + (Q[:, 2] / 0.12) ** 2)
    d = d * (0.85 + 0.3 * pbk.fbm(V * 3.0, 4.0, 943))
    w = (1.0 - _sstep(d, 0.80, 1.0)) * _sstep(-nb[:, 1], 0.10, 0.40) * (V[:, 1] < mid[1] + 0.02)
    w *= (m["m_upperarm"] < 0.3) & (m["m_head"] < 0.1) & (m["m_neck"] < 0.3) & (m["m_hand"] < 0.1)
    return w


def _install_footprints():
    """Stoneback's plate code learns the breast's footprint (this interpreter only)."""
    if getattr(sb.plate_footprint, "_frostbound", False):
        return
    orig = sb.plate_footprint

    def fp(person, name):
        if name == "plate_chest":
            return chest_footprint(person)
        return orig(person, name)
    fp._frostbound = True
    sb.plate_footprint = fp
    sb.PLATE_FORM["plate_chest"] = CHEST_FORM
    sb.PLATES.setdefault("plate_chest", SLABS["heart"][1])


def slab(person, name, body_T, groups, seed):
    """Stoneback's plate (sb.plate_piece) on this body, by its footprint (SLABS), as ice."""
    src, spec = SLABS[name]
    sb.PLATES[src] = spec
    # (ice has no iron bands: it holds by freezing to him)
    bands = sb.plate_bands
    sb.plate_bands = lambda *_a: []
    try:
        p = sb.plate_piece(person, src, body_T, groups, seed)
    finally:
        sb.plate_bands = bands
    p.name = name
    return ice_piece(p)


def top_points(p, n_dir):
    V = np.asarray(p.V)
    return V, V @ unit(n_dir)


def joints(person):
    S = person.S
    return {k: v * S for k, v in person.bd.joints.items()}


# ======================================================================================================================
# the pieces
# ======================================================================================================================
def crown_piece(person, body_T, groups):
    """The cairn's capstones frozen into a cap of ice over his brow and crown, ringed with upright spikes leaning out
    a little, the tallest over the brow; the stones dark among the ice."""
    p = slab(person, "crown", body_T, groups, 911)
    rng = np.random.default_rng(912)
    V, score = top_points(p, (0.0, 0.0, 1.0))
    top = V[score >= np.percentile(score, 55)]
    c = top.mean(axis=0)
    parts = []
    ring = 9
    for k in range(ring):
        a = 2.0 * math.pi * (k + 0.5) / ring + math.pi * 0.5
        d = np.array([math.cos(a), math.sin(a), 0.0])
        rim = top[np.argmax(top @ d)]
        front = max(0.0, -float(d[1]))
        length = (0.9 + 0.9 * front + 0.35 * rng.random()) / F
        out = unit(np.array([0.0, 0.0, 1.0]) + d * (0.25 + 0.15 * rng.random()))
        parts.append(shard_part(rim - out * 0.10 / F, out, length, (0.24 + 0.06 * rng.random()) / F, rng,
                                bend=0.06, bend_dir=d))
    # the capstones: three rough blocks of the old cairn bedded in the cap's top
    for k in range(3):
        a = 2.0 * math.pi * k / 3.0 + 0.7
        at = c + np.array([math.cos(a), math.sin(a), 0.0]) * 0.30 / F + np.array([0.0, 0.0, 0.22 / F])
        n = unit(np.array([math.cos(a) * 0.3, math.sin(a) * 0.3, 1.0]))
        u = unit(np.cross(n, [1.0, 0.0, 0.0]))
        v = np.cross(n, u)
        Vb, Tb = _block(at, u, v, n, (0.34 + 0.08 * rng.random()) / F, (0.26 + 0.06 * rng.random()) / F,
                        (0.20 + 0.05 * rng.random()) / F, rng)
        parts.append((Vb, Tb, np.asarray(CAIRN_RGBA)))
    return add_parts(p, parts, STONE_TILE_M / F)


def _block(c, u, v, n, hu, hv, hn, rng, taper=0.12):
    """A rough stone block (a box with its corners pushed about: weathered, not dressed)."""
    V = []
    for sn in (-1.0, 1.0):
        k = 1.0 - (taper if sn > 0 else 0.0)
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            jig = rng.uniform(0.82, 1.12, 3)
            V.append(c + u * su * hu * k * jig[0] + v * sv * hv * k * jig[1] + n * sn * hn * jig[2])
    V = np.asarray(V)
    T = np.array([(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5),
                  (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)], np.int64)
    return V, sb.outward(V, T, c)


def pauldron_piece(person, name, body_T, groups):
    """The ice over a shoulder: the slab and a row of shards jutting up and out along its outer edge, the biggest at
    the top of the shoulder."""
    sd = name[-1]
    s = 1.0 if sd == "l" else -1.0
    p = slab(person, name, body_T, groups, 921 if sd == "l" else 927)
    rng = np.random.default_rng(922 if sd == "l" else 928)
    J = joints(person)
    sh = J["joint-%s-shoulder" % sd]
    el = J["joint-%s-elbow" % sd]
    arm = unit(el - sh)
    out = unit(np.array([s * 0.75, 0.05, 0.65]))
    V, score = top_points(p, out)
    rim = V[score >= np.percentile(score, 70)]
    fb = np.array([0.0, 1.0, 0.0])
    t = rim @ fb
    lo, hi = np.percentile(t, 10), np.percentile(t, 90)
    parts = []
    count = 4
    for k in range(count):
        tt = lo + (hi - lo) * (k + 0.5) / count
        sel = np.abs(t - tt) < (hi - lo) / count * 0.6
        base = rim[sel][np.argmax(rim[sel] @ out)] if sel.any() else rim[np.argmin(np.abs(t - tt))]
        middle = 1.0 - abs((k + 0.5) / count - 0.5) * 1.6
        d = unit(out + np.array([0.0, 0.0, 0.5]) + fb * (tt - 0.5 * (lo + hi)) * 2.0 - arm * 0.25
                 + rng.normal(0.0, 0.08, 3))
        parts.append(shard_part(base - d * 0.12 / F, d, (0.9 + 1.0 * middle + 0.3 * rng.random()) / F,
                                (0.30 + 0.06 * rng.random()) / F, rng, bend=0.05, bend_dir=out))
    return add_parts(p, parts, STONE_TILE_M / F)


def serac_piece(person, body_T, groups):
    """The glacier's ridge on his back: the back's slab and the crest - CREST["count"] blade-shards along the spine
    from between the shoulder blades to the small of the back, flattened across (blades, not spikes), leaning back and
    out, the tallest at the shoulders; smaller shards either side of them."""
    p = slab(person, "serac", body_T, groups, 931)
    rng = np.random.default_rng(932)
    J = joints(person)
    sh = 0.5 * (J["joint-l-shoulder"] + J["joint-r-shoulder"])
    sp = J["joint-spine-2"] if "joint-spine-2" in J else sh - np.array([0.0, 0.0, 0.25 * person.S])
    V = np.asarray(p.V)
    back = V[:, 1] > np.percentile(V[:, 1], 40)
    Vb = V[back]
    xs = np.abs(Vb[:, 0])
    spine_pts = Vb[xs < np.percentile(xs, 25)]
    z_hi, z_lo = float(np.percentile(spine_pts[:, 2], 96)), float(np.percentile(spine_pts[:, 2], 8))
    parts = []
    count = CREST["count"]
    for k in range(count):
        f = k / max(count - 1, 1)
        z = z_hi + (z_lo - z_hi) * f
        near = spine_pts[np.argsort(np.abs(spine_pts[:, 2] - z))[:8]]
        base = near[np.argmax(near[:, 1])]
        size = 1.0 - 0.62 * f ** 0.8
        d = unit(np.array([rng.normal(0.0, 0.05), 0.38 + 0.40 * f, 1.0 - 0.40 * f]))
        length = CREST["tallest_m"] * size * (0.88 + 0.24 * rng.random()) / F
        Vs, Ts = shard(base - d * 0.25 / F, d, length, CREST["base_m"] * (0.55 + 0.45 * size) / F, rng, sides=4,
                       bend=0.10, bend_dir=np.array([0.0, 1.0, 0.0]))
        # flattened across the spine: a blade
        Vs[:, 0] = base[0] + (Vs[:, 0] - base[0]) * 0.45
        tip = np.clip(((Vs - base) @ d) / max(length, 1e-9), 0.0, 1.0)
        parts.append((Vs, Ts, ice_colour(Vs, vertex_up(Vs, Ts), rng, tip=tip)))
        if k in (0, 1, 3):
            for sgn in (-1.0, 1.0):
                b2 = base + np.array([sgn * (0.10 + 0.03 * k) * person.S, -0.01 * person.S, -0.02 * person.S])
                b2 = Vb[np.argmin(np.linalg.norm(Vb - b2, axis=1))]
                d2 = unit(d + np.array([sgn * 0.55, 0.15, -0.1]))
                parts.append(shard_part(b2 - d2 * 0.1 / F, d2, length * 0.42, CREST["base_m"] * 0.42 / F, rng,
                                        bend=0.06, bend_dir=np.array([sgn, 0.4, 0.0])))
    # icicles hanging from the slab's lower edge
    low = Vb[Vb[:, 2] < np.percentile(Vb[:, 2], 12)]
    for k in range(6):
        b = low[rng.integers(len(low))]
        parts.append(shard_part(b + np.array([0.0, 0.0, 0.05 / F]), np.array([0.0, 0.05, -1.0]),
                                (0.5 + 0.7 * rng.random()) / F, (0.14 + 0.05 * rng.random()) / F, rng))
    q = add_parts(p, parts, STONE_TILE_M / F)
    q.n_slab = len(p.V)
    q.facts["crest_top_m"] = r6(float(np.concatenate([x[0] for x in parts])[:, 2].max()) * F)
    return q


def heart_piece(person, body_T, groups):
    """The heart-ice: the breast's slab of clear ice and in its middle a cold-glowing core of crystal standing a
    little proud, ringed with small shards."""
    p = slab(person, "heart", body_T, groups, 941)
    rng = np.random.default_rng(942)
    V = np.asarray(p.V)
    front = V[V[:, 1] < np.percentile(V[:, 1], 30)]
    c = front.mean(axis=0)
    c = front[np.argmin(np.linalg.norm(front - c, axis=1))]
    parts = []
    Vi, Ti = sb.icosphere(1)
    r = 0.80 / F
    jig = rng.uniform(0.80, 1.15, len(Vi))
    Vc = Vi * (jig[:, None] * r) * np.array([0.9, 0.6, 1.3]) + c + np.array([0.0, -0.30 / F, 0.0])
    parts.append((Vc, sb.outward(Vc, Ti, c), np.asarray(GLOW_RGBA)))
    # crystals grown out of the ice round the core, leaning out from it, longer below (where the cold ran down)
    for k in range(11):
        a = 2.0 * math.pi * k / 11.0 + 0.3 * rng.random()
        ring_r = (0.75 + 0.55 * rng.random()) / F
        b = c + np.array([math.cos(a), 0.0, math.sin(a)]) * ring_r
        b = front[np.argmin(np.linalg.norm(front - b, axis=1))]
        d = unit(np.array([math.cos(a) * 0.55, -0.75, math.sin(a) * 0.55 - 0.15]))
        below = max(0.0, -math.sin(a))
        parts.append(shard_part(b - d * 0.08 / F, d, (0.50 + 0.45 * below + 0.25 * rng.random()) / F,
                                (0.17 + 0.06 * rng.random()) / F, rng))
    q = add_parts(p, parts, STONE_TILE_M / F)
    q.facts["core_m"] = [r6(x * F) for x in c]
    return q


def gauntlet_piece(person, holder, body_T, groups):
    """The ice over his right forearm (the slab, skinned) and round the fist a mass of ice the size of a boulder
    (rigid to the hand), faceted, shards at the knuckles and down the forearm's back."""
    p = slab(person, "gauntlet", body_T, groups, 951)
    rng = np.random.default_rng(952)
    r = person.rest
    g, ax = holder.grip["r"]
    hand = r.head["hand_r"]
    knuckles = 0.5 * (r.head["index_01_r"] + r.head["pinky_01_r"])
    along = unit(knuckles - hand)
    c = hand + along * (GAUNTLET["along_m"] / F) * 0.55
    R = GAUNTLET["radius_m"] / F
    Vi, Ti = sb.icosphere(2)
    jig = 1.0 + 0.22 * (rng.random(len(Vi)) - 0.5)
    # (longer along the fist, the knuckles' face flattened: a mass that strikes with its front)
    loc = Vi * jig[:, None]
    side = unit(np.cross(along, ax))
    up = unit(np.cross(side, along))
    M = np.stack([along, side, up], axis=1)
    k = loc @ np.diag([1.20, 0.92, 0.95])
    k[:, 0] = np.where(k[:, 0] > 0.75, 0.75 + (k[:, 0] - 0.75) * 0.3, k[:, 0])
    Vm = c + (k * R) @ M.T
    # faceted: snap the points into a few planes (cut faces) by quantising their distance along random normals
    for _ in range(9):
        n = unit(rng.normal(0.0, 1.0, 3))
        d = (Vm - c) @ n
        cut = float(np.percentile(d, 88))
        over = d > cut
        Vm[over] -= np.outer(d[over] - cut, n)
    parts = [(Vm, sb.outward(Vm, Ti, c), None)]
    up_ = vertex_up(Vm, Ti)
    parts[0] = (Vm, parts[0][1], ice_colour(Vm, up_, rng, base=DEEP_RGBA, deep=(0.30, 0.48, 0.70, 1.0)))
    for k_ in range(GAUNTLET["shards"]):
        a = 2.0 * math.pi * k_ / GAUNTLET["shards"]
        d = unit(along * (0.9 if k_ % 3 == 0 else 0.25) + side * math.cos(a) * 0.9 + up * math.sin(a) * 0.9)
        b = c + d * R * 0.78
        parts.append(shard_part(b, d, (GAUNTLET["shard_m"] * (0.6 + 0.5 * rng.random())) / F,
                                (0.30 + 0.08 * rng.random()) / F, rng))
    Vh, Th, Ch, UVh = merge(parts, STONE_TILE_M / F)
    mass = rigid_piece("gauntlet", Vh, Th, Ch, UVh, "hand_r")
    # the forearm's slab and its shards (skinned), then the mass (rigid to the hand) merged in as its own groups
    V = np.asarray(p.V)
    elbow, wrist = r.head["lowerarm_r"], r.head["hand_r"]
    fa = unit(wrist - elbow)
    sparts = []
    for k_ in range(4):
        t = 0.25 + 0.18 * k_
        b = elbow + (wrist - elbow) * t
        b = V[np.argmin(np.linalg.norm(V - b, axis=1) - 0.2 * ((V - b) @ np.array([-1.0, 0.0, 0.3])))]
        d = unit(-fa * 0.55 + np.array([-0.6, 0.15, 0.5]) + rng.normal(0.0, 0.08, 3))
        sparts.append(shard_part(b - d * 0.06 / F, d, (0.55 + 0.35 * rng.random()) / F, 0.20 / F, rng))
    p = add_parts(p, sparts, STONE_TILE_M / F)
    import people_outfit as po
    V2 = np.concatenate([p.V, mass.V])
    T2 = np.concatenate([p.T, mass.T + len(p.V)])
    g2 = {b: np.concatenate([p.groups[b], mass.groups.get(b, np.zeros(len(mass.V)))]) for b in p.groups}
    q = po.Piece("gauntlet", V2, T2, np.full(len(T2), po.MATS.index("metal")), g2,
                 np.concatenate([p.attach, np.full(len(mass.V), -1)]))
    q.uv = np.concatenate([np.asarray(p.uv), np.asarray(mass.uv)])
    q.rgba = np.concatenate([np.asarray(p.rgba), np.asarray(mass.rgba)])
    q.facts = dict(p.facts)
    q.facts.update({"tris": int(len(T2)), "mass_radius_m": GAUNTLET["radius_m"],
                    "mass_centre_rest_m": [r6(x * F) for x in c]})
    q.mass_centre = c
    return q


def greave_piece(person, name, body_T, groups):
    p = slab(person, name, body_T, groups, 961 if name.endswith("_l") else 967)
    rng = np.random.default_rng(962 if name.endswith("_l") else 968)
    V = np.asarray(p.V)
    low = V[V[:, 2] < np.percentile(V[:, 2], 14)]
    parts = []
    for k in range(4):
        b = low[rng.integers(len(low))]
        parts.append(shard_part(b + np.array([0.0, 0.0, 0.04 / F]), np.array([0.0, -0.1, -1.0]),
                                (0.35 + 0.35 * rng.random()) / F, (0.12 + 0.04 * rng.random()) / F, rng))
    return add_parts(p, parts, STONE_TILE_M / F)


def beard_piece(person, groups, kd):
    """Icicles hanging from his jaw and chin: a frozen beard (gear, rigid to the head)."""
    rng = np.random.default_rng(971)
    J = joints(person)
    V = person.body_V()
    m = person.bd.masks
    head = (m["m_head"] > 0.6)
    eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
    jaw = head & (V[:, 2] < eye[2] - 0.075 * person.S) & (V[:, 1] < eye[1] + 0.02 * person.S)
    pts = V[jaw]
    if len(pts) == 0:
        pts = V[head][np.argsort(V[head][:, 2])[:20]]
    parts = []
    for k in range(13):
        x = (k / 12.0 - 0.5) * 2.0
        target = np.array([x * 0.055 * person.S, float(pts[:, 1].min()) + 0.01 * person.S,
                           float(pts[:, 2].min()) + abs(x) * 0.03 * person.S])
        b = pts[np.argmin(np.linalg.norm(pts - target, axis=1))]
        length = (1.3 - 0.75 * abs(x) + 0.3 * rng.random()) / F
        parts.append(shard_part(b + np.array([0.0, -0.03 / F, 0.10 / F]), np.array([x * 0.15, -0.2, -1.0]),
                                length, (0.14 + 0.03 * rng.random()) / F, rng, sides=4))
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    p = rigid_piece("beard", Vm, Tm, Cm, UVm, "head")
    p.facts = {"tris": int(len(Tm)), "icicles": 13}
    return p


def rime_piece(person, groups, kd):
    """Icicles from his left forearm's underside, both elbows and the belt's hem (gear; each icicle weighted as the
    skin it hangs from)."""
    import people_outfit as po
    rng = np.random.default_rng(981)
    J = joints(person)
    V = person.body_V()
    parts = []
    spots = []
    el_l, wr_l = J["joint-l-elbow"], J["joint-l-hand"]
    for k in range(4):
        spots.append(el_l + (wr_l - el_l) * (0.2 + 0.2 * k) + np.array([0.0, 0.0, -0.035 * person.S]))
    for sd in ("l", "r"):
        spots.append(J["joint-%s-elbow" % sd] + np.array([0.0, 0.02 * person.S, -0.04 * person.S]))
    hip_z = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    for k in range(7):
        a = math.pi * (0.15 + 0.7 * k / 6.0)
        spots.append(np.array([math.cos(a) * 0.17 * person.S, -math.sin(a) * 0.12 * person.S + 0.02 * person.S,
                               hip_z + 0.02 * person.S]))
    for s_ in spots:
        b = V[kd.query(s_)[1]]
        parts.append(shard_part(b + np.array([0.0, 0.0, 0.06 / F]), np.array([rng.normal(0.0, 0.05), 0.0, -1.0]),
                                (0.4 + 0.6 * rng.random()) / F, (0.10 + 0.04 * rng.random()) / F, rng, sides=4))
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    src = kd.query(Vm)[1]
    g = {bn: w[src] for bn, w in groups.items()}
    g = sb.stiffen(g, Tm, len(Vm), 3)
    p = po.Piece("rime", Vm, Tm, np.full(len(Tm), po.MATS.index("metal")), g, src)
    p.uv = UVm
    p.rgba = Cm
    p.facts = {"tris": int(len(Tm)), "icicles": len(spots)}
    return p


# ======================================================================================================================
# his skin: Stoneback's hide, frozen
# ======================================================================================================================
def frost_skin(out_dir, LV, LT, Luv, S, masks_fn, hide_tris=None):
    """The repainted atlas's skin, frozen: a cold grey-blue cast over the hide, white rime settled where the frost
    lies (the tops of the shoulders and the arms, the brow, the backs of the hands, the scalp and the beard's
    stubble), the fingers, the toes, the nose and the ears frost-black at their ends, fine crazing over the rime."""
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
    # the cold cast: less red, more blue, a shade paler
    grey = col.mean(axis=1, keepdims=True)
    col = col * 0.55 + grey * 0.45
    col = col * np.array([0.88, 0.97, 1.10])[None, :]
    # rime where it settles: upward faces, the scalp, the brow, the hands' backs, in a patchy crust
    up = _sstep(Ns[:, 2], 0.15, 0.75)
    patch = _sstep(pbk.fbm(Ps, 9.0, 991), 0.40, 0.62)
    rime = np.clip(up * patch * 0.7 * (1.0 - 0.7 * mk["m_head"]) + 0.85 * mk["m_scalp"] + 0.4 * mk["m_beard"]
                   + 0.25 * mk["m_brow"] + 0.35 * mk["m_hand"] * patch, 0.0, 1.0)
    craze = 1.0 - _sstep(np.abs(np.sin(pbk.fbm(Ps, 40.0, 993) * 40.0)), 0.0, 0.12)
    rime_col = np.array([0.86, 0.90, 0.94])[None, :] * (1.0 - 0.10 * craze[:, None])
    col = col * (1.0 - rime[:, None] * 0.8) + rime_col * rime[:, None] * 0.8
    # frost-black at the extremities: the toes (the feet's lowest skin) and, in mottled patches, the hands
    toes = 1.0 - _sstep(Ps[:, 2], 0.02, 0.07)
    hands = mk["m_hand"] * _sstep(pbk.fbm(Ps, 6.0, 995), 0.50, 0.70)
    black = np.clip(toes * 0.7 + hands * 0.45, 0.0, 1.0)
    col = col * (1.0 - 0.6 * black[:, None]) + np.array([0.10, 0.11, 0.14])[None, :] * 0.6 * black[:, None]
    alb[ys[skin], xs[skin]] = np.clip(col, 0.0, 1.0)
    if hide_tris is not None:
        # the kilt's hide frozen stiff: its brown gone grey, rime on its upper folds and in patches
        kh = hide_tris[t] & ~skin
        hc = alb[ys[kh], xs[kh]]
        g = hc.mean(axis=1, keepdims=True)
        hc = (hc * 0.45 + g * 0.55) * np.array([0.92, 0.96, 1.02])[None, :]
        fr = _sstep(nrm[kh][:, 2], 0.2, 0.8) * 0.5 + 0.45 * _sstep(pbk.fbm(P[kh], 7.0, 997), 0.5, 0.7)
        fr = np.clip(fr, 0.0, 0.85)[:, None]
        hc = hc * (1.0 - fr) + np.array([0.78, 0.82, 0.86])[None, :] * fr
        alb[ys[kh], xs[kh]] = np.clip(hc, 0.0, 1.0)
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))


def tracks(poses, rest_export):
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
    import frostbound_moves as mv
    from scipy.spatial import cKDTree
    sb.F = F
    sb.KIND = KIND
    sb.BARK_TILE_M = (2.4, 4.0)
    _install_footprints()
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
    # ---- the outfit and the shared mesh (Stoneback's torn hide kilt, the loincloth, the belt: frozen stiff)
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, OUTFIT)
    garments = [po.garment_piece(w0, gid, p0, OUTFIT_MATERIAL[gid], kd0) for gid in order]
    garments = [sb.kilt_panels(g, p0, seed=97) if gid == "kilt" else g for g, gid in zip(garments, order)]
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
        raise SystemExit("frostbound: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the pieces
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(FROST_GAITS)
    holder = sb.Holder(p0)
    groups23 = pr.fold_weights(p0.groups53())
    kdb = cKDTree(p0.body_V())
    pieces = {"crown": crown_piece(p0, body_T, groups23),
              "pauldron_l": pauldron_piece(p0, "pauldron_l", body_T, groups23),
              "pauldron_r": pauldron_piece(p0, "pauldron_r", body_T, groups23),
              "serac": serac_piece(p0, body_T, groups23), "heart": heart_piece(p0, body_T, groups23),
              "gauntlet": gauntlet_piece(p0, holder, body_T, groups23),
              "greave_l": greave_piece(p0, "greave_l", body_T, groups23),
              "greave_r": greave_piece(p0, "greave_r", body_T, groups23),
              "beard": beard_piece(p0, groups23, kdb), "rime": rime_piece(p0, groups23, kdb)}
    log("pieces: " + ", ".join("%s %d" % (n, p.tris()) for n, p in pieces.items()))
    for name, p in pieces.items():
        if p.tris() > GEAR_BUDGET[name]:
            raise SystemExit("frostbound: %s has %d triangles, over %d" % (name, p.tris(), GEAR_BUDGET[name]))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses
    mv.GAUNTLET_C = pieces["gauntlet"].mass_centre
    poses, gaits, checks = mv.make_poses(p0, pieces, holder)
    # ---- the bake, Stoneback's hide repainted over it, frozen
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
    frost_skin(out_dir, LV, LT, Luv, p0.S, masks_fn,
               hide_tris=np.isin(Lmat, [MATS.index("leather"), MATS.index("dark_leather")]))
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("frostbound_body")
    ice = bpy.data.materials.new("frostbound_ice")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in PLATE_ORDER + GEAR:
        p = pieces[name]
        o = br.skinned_object(name, p, arm, coll, ice, F)
        ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(p.rgba, np.float32).ravel())
        o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        info_p = {"node": name, "tris": p.tris(), "material": "ice", "bone": PIECE_BONE[name],
                  "plate": name in PLATE_ORDER}
        info_p.update(getattr(p, "facts", {}) or {})
        if name in WEAK_POINTS:
            info_p["region"] = WEAK_POINTS[name]
        piece_info[name] = info_p
    rest = pbody.rest_matrices(arm)
    H = rest["hand_r"]
    gc = pieces["gauntlet"].mass_centre * F
    piece_info["gauntlet"]["mass_local"] = [r6(x) for x in (H[:3, :3].T @ (gc - H[:3, 3]))]
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
            "detail": {"ice": "stoneback_stone"}, "detail_tile_m": {"ice": STONE_TILE_M},
            "glow_alpha": GLOW_RGBA[3], "checks": checks,
            "used_by": ["enemy.frostbound (D1: FrostboundRig)", "tools/frostbound_stills.gd"]}
    for sd in ("l", "r"):
        g, ax = p0.grip[sd]
        Hs = rest["hand_" + sd]
        info["variants"][KIND]["grip_local_" + sd] = [r6(x) for x in (Hs[:3, :3].T @ (g * F - Hs[:3, 3]))]
        info["variants"][KIND]["grip_axis_" + sd] = [r6(x) for x in (Hs[:3, :3].T @ ax)]
    info["glb_bytes"] = os.path.getsize(path)
    worst = 0.0
    for name in ("walk", "idle", "rake", "fist"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            Gk = pbody.fk(rest, pbody.parents_of(arm), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "hand_l", "head", "pelvis"):
                worst = max(worst, float(np.linalg.norm(Gk[b][:3, 3] - poses[name][kk].P[b] * F)))
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("frostbound clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
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
        raise SystemExit("usage: frostbound.py frostbound <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
