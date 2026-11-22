"""Stoneback (A1): the quarry titan, an original brute-giant 16.8 m (55 ft) tall, as an asset (no fight yet).

The body is a brute (``brute.py``: the people's CC0 human with MakeHuman's macros, ``giant_body.proportioned`` with a
table of his own and ``brute.reshape``) of believable proportions: legs, torso and shoulders a heavy man's, a little
hunch, a small head between broad trapezius, big hands and feet. He wears a hide kilt and a belt (the giant's garment
shells) on one shared mesh, decimated and unwrapped into one atlas (``people_bake``), its skin band repainted here: a
weathered umber hide with quarry dust on the shins, the forearms and the feet, and pale scarred skin where the stone
plates lie (so a plate taken off shows what was under it).

Separate skinned meshes on the same 23 bones, each its own node (a later package breaks them):
  plate_shoulder_l, plate_shoulder_r, plate_back, plate_brow    the weak points' plates (``WEAK_POINTS``)
  plate_forearm_l, plate_forearm_r, plate_shin_l, plate_shin_r  the limbs' plates
      each a slab of quarried stone: the body's own surface under its footprint, its top smoothed into a slab and
      chiselled into flat facets (``FACET_M`` cells), bevelled at its rim, which runs down into the skin; mapped on
      the tileable stone texture (``stoneback_stone_*.png``, repeated ``STONE_TILE_M``)
  shackles      iron cuffs on the wrists and the ankles, broken chain lengths hanging from them (the atlas's metal
                tile, dark iron)
  club          the uprooted tree trunk on the right hand (rigid to hand_r: its handle through the fist's grip
                landmark, along the grip's line), its root ball the head; on the bark texture (``stoneback_bark_*``)
  boulder       a rock in the left hand for the throw (rigid to hand_l), hidden but in the throw's stills
  stoneback_far the idle's first key, decimated

Clips on his skeleton (``CLIP_FRAMES``): idle, walk and run (the brutes' heavy gaits at his stride), roar, and the
three attacks' wind-ups, each from the stance to its peak (its last key; the strikes are the fight package's):
``overhead`` (the trunk raised two-handed over and behind the head), ``charge`` (the shoulder charge's lean, the
left shoulder leading) and ``throw`` (the boulder drawn back over the left shoulder). The arms that hold the trunk or
the boulder are solved to them (``hold``): a two-bone solve to the wrist and the hand turned onto the trunk's line, so
both hands lie on the trunk in the overhead.

``python stoneback.py stoneback <out dir> <work dir>`` (build_people.py --stoneback) writes stoneback.glb,
stoneback_clips.glb, the atlas (stoneback_albedo.png 512 px, _normal.png, _orm.png 256 px), the detail textures
(stoneback_stone_albedo.png, _stone_normal.png, _bark_albedo.png, _bark_normal.png, 256 px, tileable) and
stoneback_info.json.
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
import stoneback_moves as mv  # noqa: E402

KIND = "stoneback"
HEIGHT_M = 17.7                    # 58 ft (A3; A1 and A2: 16.8 m, 55 ft - docs/DECISIONS.md §2.7, A3-1)
DESIGN = pr.DESIGN_HEIGHT_M
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.33 * HEIGHT_M           # A3: a shorter stride than the brutes' 0.44 (the ogre's 1.5 m at 3.4 m): his legs
                                   # reach it with the pelvis carried high (a 0.1 m bob, not 1.2 m), so he walks tall
TRIS = 9000                        # the body and the kilt (as a brute)
MARGIN_TRIS = 60
FAR_TRIS = 300
OUTFIT = ("kilt", "loincloth", "belt")
# a hide kilt, a darker hide's flaps over it, a dark belt (no palette band)
OUTFIT_MATERIAL = {"kilt": "leather", "loincloth": "dark_leather", "belt": "dark_leather"}
BELT = dict(belt_height=0.11, belt_thickness=0.014)     # (human m) the giant's belt made heavier (his: 0.065 tall)
# the kilt (A1b): hide panels round the hips (KILT_PANELS), the slits between them from the hem up a share of the hang,
# each panel hanging its own length (torn: KILT_HANG of the hang, its hem slanted), every other one a little out (the
# panels lie over one another), its rows following the thigh behind them (no thigh through it in the wind-ups)
KILT_PANELS = 11
KILT_SLIT = 0.62                   # the slits run up this share of the hang
KILT_HANG = (0.70, 1.0)            # a panel's length's share of the hang
KILT_SLANT = 0.16                  # its hem slanted up to this share across it
KILT_LAYER_M = 0.010               # every other panel stands this much more out (human m)

# ---- the body ------------------------------------------------------------------------------------------------------
# A1b: an older, broken face: the head aged, a heavy brow low and forward over deep-set eyes (the cheekbones up), a
# broken nose (bent to one side: the vendored asymmetry target), a heavy dropped jaw a little crooked, the mouth's
# corners down, one brow pulled by a scar
STONE_FACE = {"eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -1.0,
              "eyebrows/eyebrows-angle-down-up": -0.6,
              "forehead/forehead-trans-backward-forward": 0.6, "nose/nose-scale-horiz-decr-incr": 0.8,
              "nose/nose-flaring-decr-incr": 0.6, "nose/nose-volume-decr-incr": 0.5, "nose/nose-hump-decr-incr": 1.0,
              "chin/chin-width-decr-incr": 1.0, "chin/chin-prominent-decr-incr": 0.7, "chin/chin-bones-decr-incr": 1.0,
              "chin/chin-jaw-drop-decr-incr": 0.6,
              "head/head-square": 1.0, "head/head-age-decr-incr": 1.0,
              "mouth/mouth-scale-horiz-decr-incr": 0.5, "mouth/mouth-angles-down-up": -0.7,
              "mouth/mouth-laugh-lines-in-out": 0.9, "cheek/cheek-bones-decr-incr": 1.0,
              "eyes/eye-scale-decr-incr": -0.5, "eyes/eye-bag-decr-incr": 0.8,
              "mouth/mouth-lowerlip-volume-decr-incr": 0.3,
              "asym/asym-nose-2-l": 1.0, "asym/asym-jaw-1-l": 0.45, "asym/asym-brown-1-r": 0.7}
STONE_PROP = dict(legs=0.97, torso=1.02, neck=-0.025, head=0.84, arms=1.04, hands=1.14, shoulders=0.0,
                  deltoids=0.0, trapezius=-0.034, thighs=0.08)
STONE_SHAPE = dict(hunch_deg=6.0, head_back_deg=5.0, jaw=(0.32, 0.014, 0.012), underbite_m=0.004, brow_m=0.030,
                   brow_band_m=0.016, nose=(0.0, 0.0), ears=0.0, hands=1.08, feet=1.12, gut_m=0.018, tusks=False)
VARIANT = dict(name=KIND, macro=br._macro(46, 1.0, 0.82, african=0.45, asian=0.1, caucasian=0.45),
               face=br._face(1.5, **STONE_FACE), prop=STONE_PROP, shape=STONE_SHAPE, height_m=HEIGHT_M)
# A3: his own gaits (the brutes' walk and run carried taller): the trunk leans less and the pelvis pitches less, so the
# head stays near his full height as he walks (the brutes' lean had it 1-2.3 m lower than in the idle)
STONE_GAITS = {
    "stone_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.04, min_drop=0.02, lean_deg=4.0, pelvis_pitch_deg=3.0,
                       roll_deg=4.0, sway=0.08, arm_swing_deg=10.0, strike_deg=-16.0, heel_rocker=0.12),
    "stone_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.10, min_drop=0.08, lean_deg=9.0, pelvis_pitch_deg=6.0),
}
# the free (left) hand's rest curl (A1b): a loose, heavy fist, the fingers closed together evenly and the thumb in (the
# people's graded curl held the index out: it hung half open, pointing); the right keeps the people's (its grip on the
# trunk)
LEFT_CURLS = {"index": 0.86, "middle": 0.90, "ring": 0.93, "pinky": 0.96, "thumb": 0.90}
LEFT_THUMB_DEG = (40.0, 18.0, 22.0)      # its thumb's three joints turned down along the fingers, to the index
BOULDER_SINK = 0.10                # the boulder sits so the hand's deepest point is this share of its radius in it


# ---- the plates (real metres) --------------------------------------------------------------------------------------
# A1b: each plate is one or two quarried slabs (a lower slab and a smaller one laid over it), each slab the body's
# patch under its footprint cut to a chipped outline of straight edges, its top the intersection of a few flat cut
# faces (so its edges are ridges and its sides walls of clear thickness), a narrow chamfer at the rim; iron bands
# round the body hold it on (in the plate's own mesh, so a plate taken off takes its bands with it).
# name: (thickness, gap over the skin, chamfer width, the cut faces of the lower slab, decimation budget)
PLATES = {
    "plate_shoulder_l": (0.38, 0.05, 0.12, 2, 460),
    "plate_shoulder_r": (0.38, 0.05, 0.12, 2, 460),
    "plate_back": (0.62, 0.05, 0.20, 2, 640),
    "plate_brow": (0.18, 0.03, 0.07, 9, 320),
    "plate_forearm_l": (0.34, 0.04, 0.10, 3, 260),
    "plate_forearm_r": (0.34, 0.04, 0.10, 3, 260),
    "plate_shin_l": (0.40, 0.04, 0.11, 3, 270),
    "plate_shin_r": (0.40, 0.04, 0.11, 3, 270),
}
# the plate's form: the chips cut into the outline (straight edges), the upper slab (its inset from the lower's edge
# (of the footprint's weight), its thickness's share, its cut faces) or None, the crack's groove, the iron bands
PLATE_FORM = {
    "plate_shoulder_l": dict(chips=9, deep=(0.12, 0.30), upper=(0.34, 0.75, 2), crack=True, bands=("arm",), most=1.5),
    "plate_shoulder_r": dict(chips=9, deep=(0.12, 0.30), upper=(0.34, 0.75, 2), crack=True, bands=("arm",), most=1.5),
    "plate_back": dict(chips=9, upper=(0.0, 0.62, 2), crack=True, bands=("bandolier_l", "bandolier_r")),
    "plate_brow": dict(chips=6, upper=None, crack=True, bands=("chin",), most=1.25),
    "plate_forearm_l": dict(chips=5, upper=None, crack=False, bands=(0.30, 0.62), most=1.05),
    "plate_forearm_r": dict(chips=5, upper=None, crack=False, bands=(0.30, 0.62), most=1.05),
    "plate_shin_l": dict(chips=5, upper=None, crack=False, bands=(0.28, 0.64), most=1.0),
    "plate_shin_r": dict(chips=5, upper=None, crack=False, bands=(0.28, 0.64), most=1.0),
}
PLATE_SUBDIVIDE = 1                # the body's patch split once before the slab is cut (straighter edges)
FACET_TILT = 0.10                  # a cut face's plane tilted this much off its points' own (radians, about)
SLAB_MIN, SLAB_MAX = 0.55, 1.75    # a slab's thickness held between these shares of its own
CHAMFER = 0.38                     # the rim's chamfer drops the top's edge this share of the thickness
BAND = dict(half_w=0.22, thick=0.10, gap=0.03)     # the iron bands (real metres)
IRON_RGBA = (0.150, 0.140, 0.130, 0.0)       # the bands' vertex colour (linear; alpha 0: iron, stone_plate.gdshader)
EARTH_RGBA = (0.115, 0.085, 0.060, 0.5)         # the club's earth (alpha 0.5: an untextured matte colour)
SHARP_DEG = 24.0                   # a plate's or the boulder's edge sharper than this is drawn sharp (a facet's)
PLATE_ORDER = tuple(PLATES)
# the weak points beneath (the fight package's): the plates that break to expose them
WEAK_POINTS = {"plate_shoulder_l": "shoulder_l", "plate_shoulder_r": "shoulder_r", "plate_back": "back",
               "plate_brow": "brow"}
RIM_SINK_M = 0.06                  # the rim runs this far under the skin (no gap at the plate's edge)
STONE_TILE_M = 3.4                 # the stone texture repeats every this many metres
BARK_TILE_M = (2.4, 4.0)           # the bark's repeat round and along the trunk
DETAIL_PX = 256
# ---- the shackles, the club and the boulder (real metres) -----------------------------------------------------------
CUFF = dict(gap=0.05, thick=0.16, half_w=0.30, segs=20)
LINK = dict(length=0.95, width=0.58, wire=0.14, segs=8, sides=5)
CHAINS = {"wrist_l": 4, "wrist_r": 3, "ankle_l": 3, "ankle_r": 2}
CLUB = dict(handle_m=1.0, length_m=7.5, root_r=1.5, roots=6, clods=6, segs=14, rings=34)
BOULDER_R = 1.4
GEAR_BUDGET = {"shackles": 1800, "club": 2600, "boulder": 360}

CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "roar": 24, "overhead": 30, "charge": 24, "throw": 30}
CLIP_LOOPS = ("idle", "walk", "run")
WINDUPS = ("overhead", "charge", "throw")
# A2: the strikes that finish the wind-ups, his reel, the boulder's rip and release, the charge's run and his death
# (stoneback_moves.py), keyed after A1's clips
A1_CLIPS = tuple(CLIP_FRAMES)
CLIP_FRAMES.update(mv.FRAMES)
CLIP_LOOPS = CLIP_LOOPS + mv.LOOPS
# the trunk's line from the right fist (armature space: +x his left, -y his front, +z up) in the stance and the walk
CLUB_IDLE_DIR = (-0.30, -0.52, -0.80)
CLUB_WALK_DIR = (-0.28, -0.70, -0.66)
# the idle's club (A1b): its lowest point this far over the ground in every key (club_at_rest: the hand turned between
# the steep and the flat line; CLUB_V the club's points, set by the build); CLUB_IDLE_DIR its line in the idle's first
# key (the other clips start from it)
CLUB_REST_M = 0.02
CLUB_STEEP, CLUB_FLAT = (-0.06, -0.14, -0.99), (-0.40, -0.78, -0.48)
CLUB_V = None


def log(*a):
    print("[stoneback]", *a, flush=True)


r6 = br.r6
_sstep = br._sstep


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


# ======================================================================================================================
# geometry helpers (design scale unless said)
# ======================================================================================================================
def edges_of(T):
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    return np.unique(e, axis=0, return_counts=True)


def largest_component(T, n):
    """The triangles of T's largest edge-connected component."""
    parent = np.arange(n)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for a, b, c in T.tolist():
        for u, v in ((a, b), (b, c)):
            ru, rv = find(u), find(v)
            if ru != rv:
                parent[ru] = rv
    roots = np.array([find(t[0]) for t in T.tolist()])
    vals, cnt = np.unique(roots, return_counts=True)
    return T[roots == vals[np.argmax(cnt)]]


def taubin(V, T, it, keep, lam=0.5, mu=-0.53):
    """Taubin smoothing of V over T's edges; ``keep`` (bool) held."""
    u, _c = edges_of(T)
    n = len(V)
    deg = np.zeros(n)
    np.add.at(deg, u[:, 0], 1.0)
    np.add.at(deg, u[:, 1], 1.0)
    deg = np.maximum(deg, 1.0)
    V = V.copy()
    for _ in range(it):
        for f in (lam, mu):
            acc = np.zeros_like(V)
            np.add.at(acc, u[:, 0], V[u[:, 1]])
            np.add.at(acc, u[:, 1], V[u[:, 0]])
            d = acc / deg[:, None] - V
            d[keep] = 0.0
            V = V + f * d
    return V


def boundary_distance(V, T, bnd, steps=60):
    """Each vertex's distance along T's edges from the boundary vertices ``bnd`` (bool) (Bellman-Ford)."""
    u, _c = edges_of(T)
    L = np.linalg.norm(V[u[:, 0]] - V[u[:, 1]], axis=1)
    d = np.where(bnd, 0.0, np.inf)
    for _ in range(steps):
        d2 = d.copy()
        np.minimum.at(d2, u[:, 0], d[u[:, 1]] + L)
        np.minimum.at(d2, u[:, 1], d[u[:, 0]] + L)
        if np.array_equal(d2, d):
            break
        d = d2
    return np.where(np.isfinite(d), d, d[np.isfinite(d)].max() if np.isfinite(d).any() else 0.0)


def boundary_edges(T):
    """The open edges of T, each in the direction its triangle runs it."""
    u, c = edges_of(T)
    open_ = {tuple(e) for e in u[c == 1].tolist()}
    out = []
    for a, b, cc in T.tolist():
        for x, y in ((a, b), (b, cc), (cc, a)):
            if (min(x, y), max(x, y)) in open_:
                out.append((x, y))
    return np.asarray(out, np.int64).reshape(-1, 2)


def planar_uv(P, T, normal, tile):
    """Corner UVs: the points projected on the plane across ``normal``, ``tile`` design metres a texture repeat."""
    n = unit(normal)
    a = unit(np.cross(n, [0.0, 0.0, 1.0] if abs(n[2]) < 0.9 else [1.0, 0.0, 0.0]))
    b = np.cross(n, a)
    C = P[T]
    return np.stack([(C @ a) / tile, (C @ b) / tile], axis=-1)


def box_uv(V, T, tile):
    """Corner UVs by a box map: each triangle projected along its normal's largest axis, ``tile`` design metres a
    texture repeat (no stretched faces on a curved slab)."""
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    C = V[T] / tile
    dom = np.argmax(np.abs(nrm), axis=1)
    uv = np.zeros((len(T), 3, 2))
    for k, (i, j) in enumerate(((1, 2), (0, 2), (0, 1))):
        sel = dom == k
        uv[sel] = C[sel][..., [i, j]] + 0.37 * k
    return uv


def tube(path, radii, segs, close=(True, True), frame0=None):
    """A closed tube along ``path`` (k, 3) with ``radii`` (k, segs) or (k,), capped at either end; returns (V, T,
    the ring index of each vertex, the angle of each vertex)."""
    path = np.asarray(path, np.float64)
    k = len(path)
    radii = np.asarray(radii, np.float64)
    if radii.ndim == 1:
        radii = np.repeat(radii[:, None], segs, axis=1)
    tang = np.gradient(path, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    ref = unit(frame0) if frame0 is not None else (np.array([1.0, 0.0, 0.0]) if abs(tang[0][0]) < 0.9
                                                    else np.array([0.0, 1.0, 0.0]))
    V, T, ring, ang = [], [], [], []
    u = unit(np.cross(tang[0], ref))
    for i in range(k):
        u = unit(u - tang[i] * float(u @ tang[i]))          # parallel transport
        w = np.cross(tang[i], u)
        for s in range(segs):
            ph = 2.0 * math.pi * s / segs
            V.append(path[i] + radii[i, s] * (math.cos(ph) * u + math.sin(ph) * w))
            ring.append(i)
            ang.append(ph)
    for i in range(k - 1):
        for s in range(segs):
            a0, b0 = i * segs + s, i * segs + (s + 1) % segs
            T += [(a0, b0 + segs, b0), (a0, a0 + segs, b0 + segs)]
    for end, i in ((0, 0), (1, k - 1)):
        if close[end]:
            c = len(V)
            V.append(path[i] + (tang[i] * (-1.0 if end == 0 else 1.0)) * float(radii[i].mean()) * 0.35)
            ring.append(i)
            ang.append(0.0)
            for s in range(segs):
                a0, b0 = i * segs + s, i * segs + (s + 1) % segs
                T.append((a0, b0, c) if end == 0 else (b0, a0, c))
    V, T = np.asarray(V), np.asarray(T, np.int64)
    ring = np.asarray(ring)
    # wound outward from the path
    nr = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    side = T[:, 0] < k * segs
    if float(np.einsum("ij,ij->i", nr[side], (V[T[side]].mean(axis=1) - path[ring[T[side, 0]]])).sum()) < 0:
        T = T[:, ::-1]
    return V, T, ring, np.asarray(ang)


def outward(V, T, centre):
    """T wound so that its normals point away from ``centre`` on the whole."""
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    if float(np.einsum("ij,ij->i", nrm, V[T].mean(axis=1) - centre).sum()) < 0:
        return T[:, ::-1]
    return T


# ======================================================================================================================
# the plates
# ======================================================================================================================
def plate_footprint(person, name):
    """(n,) footprint weight of the body's vertices (human metres in, a soft 0..1 out) of plate ``name``."""
    bd = person.bd
    V = bd.verts[:N]
    J = bd.joints
    m = bd.masks
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    nb = person.normals_h
    if name.startswith("plate_shoulder"):
        s = 1.0 if name.endswith("_l") else -1.0
        sd = "l" if s > 0 else "r"
        sh = J["joint-%s-shoulder" % sd]
        el = J["joint-%s-elbow" % sd]
        c = sh + np.array([s * 0.02, 0.018, 0.05])
        Q = V - c
        d = np.sqrt((Q[:, 0] / 0.16) ** 2 + (Q[:, 1] / 0.15) ** 2 + (Q[:, 2] / 0.13) ** 2)
        side = np.sign(x) == s
        # (A1b: the top of the shoulder and the deltoid's cap, not far down the arm: a slab laid over it)
        up_out = (nb[:, 2] + 0.9 * s * nb[:, 0] + 0.3 * nb[:, 1]) > 0.0
        arm_t = ((V - sh) @ unit(el - sh)) / float(np.linalg.norm(el - sh))
        w = (1.0 - _sstep(d, 0.85, 1.05)) * side * up_out * (1.0 - _sstep(arm_t, 0.34, 0.44))
        w *= _sstep(s * x, abs(sh[0]) * 0.34, abs(sh[0]) * 0.46)          # leaves the neck's sides bare
        w *= 1.0 - _sstep(-y + sh[1], 0.07, 0.10) * (nb[:, 1] < -0.3)        # not down the chest
        w *= (m["m_head"] < 0.1) & (m["m_hand"] < 0.1)
        return w
    if name == "plate_back":
        sh = 0.5 * (J["joint-l-shoulder"] + J["joint-r-shoulder"])
        sp = J["joint-spine-2"]
        top = sh[2] + 0.07
        low = sp[2] - 0.07
        half = abs(J["joint-l-shoulder"][0]) * 0.96
        w = (1.0 - _sstep(np.abs(x), half * 0.84, half)) * _sstep(z, low, low + 0.03) * (1.0 - _sstep(z, top - 0.03, top))
        w *= _sstep(nb[:, 1], -0.05, 0.25) * (y > sp[1] - 0.03)
        w *= (m["m_upperarm"] < 0.5) & (m["m_head"] < 0.1) & (m["m_neck"] < 0.5)
        return w
    if name == "plate_brow":
        # A1b: a half-helm: low over the brow at the front, over the crown, its back edge rising over the occiput
        # (the nape bare), clear of the ears
        eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
        hv = m["m_head"] > 0.6
        fy, by = float(y[hv].min()), float(y[hv].max())
        r = np.clip((y - fy) / max(by - fy, 1e-6), 0.0, 1.0)
        zc = eye[2] + 0.013 + 0.050 * _sstep(r, 0.45, 0.95)
        w = (m["m_head"] > 0.6) * _sstep(z, zc, zc + 0.008) * (1.0 - _sstep(m["m_ears"], 0.02, 0.08))
        w *= (nb[:, 2] > -0.2)
        return w
    if name.startswith("plate_forearm"):
        sd = name[-1]
        s = 1.0 if sd == "l" else -1.0
        el, wr = J["joint-%s-elbow" % sd], J["joint-%s-hand" % sd]
        a = wr - el
        L = float(np.linalg.norm(a))
        t = ((V - el) @ (a / L)) / L
        # the back of the forearm: out from the body at rest (the A-pose's palms face the thighs)
        dors = unit(np.array([s * 0.55, 0.45, 0.70]))
        Q = V - (el + np.outer(np.clip(t, 0, 1), a))
        Q -= np.outer(Q @ (a / L), a / L)
        facing = (Q / np.maximum(np.linalg.norm(Q, axis=1, keepdims=True), 1e-9)) @ dors
        w = _sstep(t, 0.16, 0.22) * (1.0 - _sstep(t, 0.70, 0.76)) * _sstep(facing, -0.35, -0.1)
        w *= (np.sign(x) == s) * (m["m_forearm"] + m["m_hand"] > 0.5) * (m["m_hand"] < 0.2)
        return w
    if name.startswith("plate_shin"):
        sd = name[-1]
        s = 1.0 if sd == "l" else -1.0
        kn, an = J["joint-%s-knee" % sd], J["joint-%s-ankle" % sd]
        a = an - kn
        L = float(np.linalg.norm(a))
        t = ((V - kn) @ (a / L)) / L
        Q = V - (kn + np.outer(np.clip(t, 0, 1), a))
        front = -Q[:, 1] / np.maximum(np.linalg.norm(Q[:, :2], axis=1), 1e-9)
        w = _sstep(t, 0.10, 0.16) * (1.0 - _sstep(t, 0.74, 0.80)) * _sstep(front, -0.30, -0.05)
        w *= (np.sign(x) == s) * (m["m_lowerleg"] > 0.5)
        return w
    raise KeyError(name)


def plate_depth_m(name):
    """A plate's nominal depth over the skin (real metres): its slab's thickness, and its upper slab's over it."""
    up = PLATE_FORM[name]["upper"]
    return PLATES[name][0] * (1.0 + (up[1] if up else 0.0))


def snap_patch(P, Nn, src, T, f):
    """The part of the mesh (P, Nn, src: each vertex's body vertex, T) where ``f`` > 0, its outline on f's zero: the
    triangles with a corner inside, each outside corner moved to where its edges into the inside cross zero (so the
    outline runs straight where f is a plane's distance); its largest connected piece. Returns (P, Nn, src, T, used:
    each vertex's index in the input)."""
    inside = f > 0.0
    Tk = T[inside[T].any(axis=1)]
    if not len(Tk):
        raise SystemExit("stoneback: a plate's footprint is empty")
    Tk = largest_component(Tk, len(P))
    used = np.unique(Tk)
    remap = -np.ones(len(P), np.int64)
    remap[used] = np.arange(len(used))
    T2 = remap[Tk]
    P2, N2, s2, f2 = P[used].copy(), Nn[used].copy(), src[used], f[used]
    u, _c = edges_of(T2)
    a, b = u[:, 0], u[:, 1]
    cr = (f2[a] > 0.0) != (f2[b] > 0.0)
    a, b = a[cr], b[cr]
    o = np.where(f2[a] > 0.0, b, a)
    i = np.where(f2[a] > 0.0, a, b)
    t = f2[o] / (f2[o] - f2[i])
    acc = np.zeros_like(P2)
    cnt = np.zeros(len(P2))
    np.add.at(acc, o, P2[o] + (P2[i] - P2[o]) * t[:, None])
    np.add.at(cnt, o, 1.0)
    out = cnt > 0
    P2[out] = acc[out] / cnt[out, None]
    ar = np.linalg.norm(np.cross(P2[T2[:, 1]] - P2[T2[:, 0]], P2[T2[:, 2]] - P2[T2[:, 0]]), axis=1)
    T2 = T2[ar > 1e-3 * float(np.median(ar))]
    keep = np.unique(T2)
    remap = -np.ones(len(P2), np.int64)
    remap[keep] = np.arange(len(keep))
    return P2[keep], N2[keep], s2[keep], remap[T2], used[keep]


def chip_cuts(P, Nn, w, rng, count, deep=(0.04, 0.20)):
    """``count`` straight chips cut into the outline of ``w`` > 0.5 over the mesh's points P (normals Nn): each a
    plane across the surface near an outline point (farthest from the others), facing inward a little turned, as
    (points, inward normals) - its distance (positive inside) is the cut's field."""
    inside = w > 0.5
    c = P[inside].mean(axis=0)
    L = float(np.linalg.norm(P[inside] - c, axis=1).mean())
    edge = np.nonzero(np.abs(w - 0.5) < 0.12)[0]
    if len(edge) < count:
        edge = np.nonzero(inside)[0]
    pick = [int(edge[rng.integers(len(edge))])]
    d = np.linalg.norm(P[edge] - P[pick[0]], axis=1)
    for _ in range(count - 1):
        k = int(edge[np.argmax(d)])
        pick.append(k)
        d = np.minimum(d, np.linalg.norm(P[edge] - P[k], axis=1))
    qs, ns = [], []
    for k in pick:
        n = Nn[k]
        inward = c - P[k]
        inward = unit(inward - n * float(inward @ n))
        ang = rng.uniform(-0.55, 0.55)
        inward = unit(math.cos(ang) * inward + math.sin(ang) * np.cross(n, inward))
        qs.append(P[k] + inward * L * rng.uniform(deep[0], deep[1]))
        ns.append(inward)
    return np.asarray(qs), np.asarray(ns), L


def cut_field(P, qs, ns):
    return ((P[:, None, :] - qs[None, :, :]) * ns[None, :, :]).sum(axis=2).min(axis=1)


def cut_faces(base, Nn, T, thick, k, rng):
    """The slab's cut faces: ``k`` planes (normals, offsets) over the patch, each the mean facing of its part of the
    smoothed slab (parts by farthest seeds) a little tilted, set where most of its part's points are under it."""
    import people_outfit as po
    sm = taubin(base + Nn * thick, T, 30, np.zeros(len(base), bool))
    sn = po.vertex_normals(sm, T)
    if float(np.einsum("ij,ij->i", sn, Nn).sum()) < 0:
        sn = -sn
    c = sm.mean(axis=0)
    seeds = [int(np.argmax(np.linalg.norm(sm - c, axis=1)))]
    d = np.linalg.norm(sm - sm[seeds[0]], axis=1)
    for _ in range(k - 1):
        s = int(np.argmax(d))
        seeds.append(s)
        d = np.minimum(d, np.linalg.norm(sm - sm[s], axis=1))
    lab = np.argmin(np.linalg.norm(sm[:, None, :] - sm[seeds][None, :, :], axis=2), axis=1)
    nk, dk = [], []
    for j in range(k):
        sel = lab == j
        if sel.sum() < 3:
            continue
        n = unit(sn[sel].mean(axis=0) + rng.normal(0.0, FACET_TILT, 3))
        nk.append(n)
        dk.append(float(np.percentile(sm[sel] @ n, 72)))
    return np.asarray(nk), np.asarray(dk)


def slab_height(base, Nn, planes, thick, most=SLAB_MAX):
    """How far along Nn from ``base`` the top of the slab cut by ``planes`` lies (the nearest cut face a ray meets),
    held between SLAB_MIN and SLAB_MAX of the thickness."""
    nk, dk = planes
    nd = Nn @ nk.T
    t = (dk[None, :] - base @ nk.T) / np.where(nd > 0.25, nd, 1.0)
    t = np.where(nd > 0.25, t, np.inf).min(axis=1)
    t = np.where(np.isfinite(t), t, thick)
    return np.clip(t, SLAB_MIN * thick, most * thick)


def crack_depth(P, T, bnd, rng, width, depth):
    """A crack's groove across the patch: a broken line between two outline points far apart, ``depth`` deep at it,
    nothing ``width`` from it."""
    b = np.nonzero(bnd)[0]
    p0 = b[rng.integers(len(b))]
    far = b[np.argmax(np.linalg.norm(P[b] - P[p0], axis=1))]
    a, z = P[p0], P[far]
    mid = 0.5 * (a + z)
    mid_i = int(np.argmin(np.linalg.norm(P - mid, axis=1)))
    pts = [a, P[mid_i] + (z - a) * rng.uniform(-0.12, 0.12), z]
    dmin = np.full(len(P), np.inf)
    for s0, s1 in zip(pts[:-1], pts[1:]):
        seg = s1 - s0
        tt = np.clip(((P - s0) @ seg) / max(float(seg @ seg), 1e-12), 0.0, 1.0)
        dmin = np.minimum(dmin, np.linalg.norm(P - (s0 + np.outer(tt, seg)), axis=1))
    return depth * (1.0 - _sstep(dmin, 0.0, width))


def slab_mesh(P, Nn, src, T, base, thick, chamfer_w, planes, sink, crack=None, most=SLAB_MAX):
    """A slab over the patch (P on the skin, Nn, T): its top ``base`` + Nn x the cut faces' height, chamfered at the
    rim, less the crack's groove; its walls from the top's outline down to ``sink`` under the patch's own outline.
    Returns (V, T, src, top) with the top's points first."""
    n = len(P)
    bnd = np.zeros(n, bool)
    u, c = edges_of(T)
    bnd[u[c == 1].ravel()] = True
    dist = boundary_distance(P, T, bnd)
    t = slab_height(base, Nn, planes, thick, most)
    t = t - CHAMFER * thick * (1.0 - _sstep(dist, 0.0, chamfer_w))
    if crack is not None:
        t = t - crack(P, T, bnd)
    top = base + Nn * t[:, None]
    be = boundary_edges(T)
    ub = np.unique(be)
    rmap = -np.ones(n, np.int64)
    rmap[ub] = n + np.arange(len(ub))
    rim_v = P[ub] - Nn[ub] * sink
    Vall = np.concatenate([top, rim_v])
    rim_T = []
    for a, b in be.tolist():
        rim_T += [(b, a, rmap[a]), (b, rmap[a], rmap[b])]
    Tall = np.concatenate([T, np.asarray(rim_T, np.int64).reshape(-1, 3)])
    nrm = np.cross(Vall[Tall[:, 1]] - Vall[Tall[:, 0]], Vall[Tall[:, 2]] - Vall[Tall[:, 0]])
    if float(np.einsum("ij,ij->i", nrm[:len(T)], Nn[T].mean(axis=1)).sum()) < 0:
        Tall = Tall[:, ::-1]
    return Vall, Tall, np.concatenate([src, src[ub]]), top


def band_ring(c, axis, pts, half_w, thick, gap, segs, hint=(0.0, 1.0, 0.0)):
    """An iron band (a rectangular section, ``segs`` round) about the line through ``c`` along ``axis`` lying over
    ``pts`` (the skin and the slab under it): at each angle the farthest of them within its width, plus ``gap``.
    Returns (V, T)."""
    a = unit(axis)
    hint = np.asarray(hint, np.float64)
    if abs(float(unit(hint) @ a)) > 0.9:
        hint = np.array([1.0, 0.0, 0.0])
    ref = unit(np.cross(a, hint))
    b = np.cross(a, ref)
    Q = pts - c
    al = Q @ a
    Q = Q[np.abs(al) < half_w * 0.8]
    ang = np.arctan2(Q @ b, Q @ ref)
    rad = np.linalg.norm(Q - np.outer(Q @ a, a), axis=1)
    R = np.full(segs, np.nan)
    bins = np.clip(((ang + math.pi) / (2.0 * math.pi) * segs).astype(np.int64), 0, segs - 1)
    np.fmax.at(R, bins, rad)
    ok = ~np.isnan(R)
    idx = np.arange(segs, dtype=np.float64)
    R = np.interp(idx, idx[ok], R[ok], period=segs)
    R = R / math.cos(math.pi / segs)
    V, T = [], []
    for s in range(segs):
        ph = -math.pi + 2.0 * math.pi * (s + 0.5) / segs
        d = math.cos(ph) * ref + math.sin(ph) * b
        r0, r1 = R[s] + gap * 0.2, R[s] + gap + thick
        V += [c + d * r0 - a * half_w, c + d * r1 - a * half_w * 0.9, c + d * r1 + a * half_w * 0.9,
              c + d * r0 + a * half_w]
    for s in range(segs):
        a0, b0 = 4 * s, 4 * ((s + 1) % segs)
        for i in range(4):
            j = (i + 1) % 4
            T += [(a0 + i, b0 + i, b0 + j), (a0 + i, b0 + j, a0 + j)]
    V, T = np.asarray(V), np.asarray(T, np.int64)
    return V, outward(V, T, c)


def plate_bands(person, name, slab_pts):
    """The iron bands that hold plate ``name`` on: [(V, T)] (design scale) round the body and the slab."""
    bd = person.bd
    S = person.S
    J = {k: v * S for k, v in bd.joints.items()}
    V = person.body_V()
    m = bd.masks
    hw, th, gp = BAND["half_w"] / F, BAND["thick"] / F, BAND["gap"] / F
    out = []
    form = PLATE_FORM[name]
    arms = (m["m_upperarm"] > 0.25) | (m["m_forearm"] > 0.1) | (m["m_hand"] > 0.1)
    if name == "plate_back":
        # two bandoliers crossed over the slab: each over one trapezius and under the other armpit
        sp1 = J["joint-spine-1"]
        shl, shr = J["joint-l-shoulder"], J["joint-r-shoulder"]
        torso = ~arms & (m["m_head"] < 0.1) & (m["m_neck"] < 0.5)
        pts = np.concatenate([V[torso], slab_pts])
        for s in (1.0, -1.0):
            sh_hi = shl if s > 0 else shr
            sh_lo = shr if s > 0 else shl
            hi = np.array([s * abs(sh_hi[0]) * 0.55, 0.0, sh_hi[2] + 0.03 * S])
            lo = np.array([-s * abs(sh_lo[0]) * 0.95, 0.0, sh_lo[2] - 0.13 * S])
            c = 0.5 * (hi + lo)
            near = torso & (np.abs(V[:, 2] - c[2]) < 0.05 * S) & (np.abs(V[:, 0]) < 0.05 * S)
            c[1] = 0.5 * (float(V[near, 1].min()) + float(V[near, 1].max())) if near.any() else float(sp1[1])
            d = unit(hi - lo)
            a = unit(np.array([-d[2], 0.0, d[0]]))         # the ring's plane holds d and the front-back line
            out.append(band_ring(c, a, pts, hw, th, gp, 22, hint=(0.0, 1.0, 0.0)))
    elif name.startswith("plate_shoulder"):
        sd = name[-1]
        s = 1.0 if sd == "l" else -1.0
        sh, el = J["joint-%s-shoulder" % sd], J["joint-%s-elbow" % sd]
        c = sh + (el - sh) * 0.36
        arm = (m["m_upperarm"] > 0.3) & (np.sign(V[:, 0]) == s)
        out.append(band_ring(c, el - sh, np.concatenate([V[arm], slab_pts]), hw * 0.75, th, gp, 16))
    elif name == "plate_brow":
        eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
        head = (m["m_head"] > 0.5) & (m["m_ears"] < 0.05)
        # a chin strap: over the helm's crown, down in front of the ears, under the jaw
        jaw = J["joint-jaw"]
        ears = m["m_ears"] > 0.5
        c = np.array([0.0, float(V[ears, 1].min()) - 0.006 * S, 0.5 * (eye[2] + jaw[2]) + 0.01 * S])
        out.append(band_ring(c, (0.0, 1.0, -0.35), np.concatenate([V[head], slab_pts]), hw * 0.35, th * 0.45, gp,
                             20, hint=(0.0, 0.0, 1.0)))
    else:
        sd = name[-1]
        s = 1.0 if sd == "l" else -1.0
        if name.startswith("plate_forearm"):
            j0, j1, mk = J["joint-%s-elbow" % sd], J["joint-%s-hand" % sd], "m_forearm"
        else:
            j0, j1, mk = J["joint-%s-knee" % sd], J["joint-%s-ankle" % sd], "m_lowerleg"
        limb = (m[mk] > 0.3) & (np.sign(V[:, 0]) == s)
        for t in form["bands"]:
            c = j0 + (j1 - j0) * t
            out.append(band_ring(c, j1 - j0, np.concatenate([V[limb], slab_pts]), hw * 0.7, th * 0.8, gp, 12))
    return out


def plate_piece(person, name, body_T, groups, seed):
    """A plate (see PLATES and PLATE_FORM) as a people_outfit Piece (design scale): its slabs (box-mapped corner UVs
    on the stone), its iron bands; ``rgba`` each vertex's colour (stone_plate.gdshader: alpha 1 stone, 0 iron)."""
    import people_outfit as po
    from scipy.spatial import cKDTree
    thick, gap, chamfer_w = (v / F for v in PLATES[name][:3])
    k_faces, budget = PLATES[name][3], PLATES[name][4]
    form = PLATE_FORM[name]
    S = person.S
    Vb = person.body_V()
    Nb = person.normals
    rng = np.random.default_rng(seed)
    w = plate_footprint(person, name)
    # the patch (with a margin) split, then the outline: the footprint's edge and the chips' straight cuts
    region = w > 0.12
    Tk = body_T[region[body_T].any(axis=1)]
    used = np.unique(Tk)
    remap = -np.ones(N, np.int64)
    remap[used] = np.arange(len(used))
    T = remap[Tk]
    P, Nn, src = Vb[used], Nb[used], used
    for _ in range(PLATE_SUBDIVIDE):
        P, Nn, src, T = subdivide(P, Nn, src, T)
    # the footprint's weight at the new points: the mean of their edge's ends (subdivide keeps the first end's body
    # vertex; the weight is read again from the nearest two body vertices)
    kd = cKDTree(Vb)
    dd, ii = kd.query(P, k=2)
    wt = 1.0 / np.maximum(dd, 1e-9)
    wp = (w[ii] * wt).sum(axis=1) / wt.sum(axis=1)
    qs, ns, L = chip_cuts(P, Nn, wp, rng, form["chips"], form.get("deep", (0.04, 0.20)))
    f = np.minimum((wp - 0.5) * 0.12 * S, cut_field(P, qs, ns))
    Pl, Nl, sl, Tl, ul = snap_patch(P, Nn, src, T, f)
    base = Pl + Nl * gap
    planes = cut_faces(base, Nl, Tl, thick, k_faces, rng)
    crack = None
    if form["crack"]:
        crack = (lambda P_, T_, b_, r=np.random.default_rng(seed + 1):
                 crack_depth(P_, T_, b_, r, 0.10 / F, 0.30 * thick))
    sink = RIM_SINK_M / F
    most = form.get("most", SLAB_MAX)
    V1, T1, s1, top1 = slab_mesh(Pl, Nl, sl, Tl, base, thick, chamfer_w, planes, sink, crack, most)
    slabs = [(V1, T1, s1, 1.0)]
    tops = [top1]
    if form["upper"] is not None:
        inset, share, k_up = form["upper"]
        fl = f[ul]
        if name == "plate_back":
            # the upper slab: the plate's top part, laid over the lower one (its lower edge chipped across)
            zs = float(np.percentile(Pl[:, 2], 45))
            q2, n2, _L = chip_cuts(Pl, Nl, np.clip(0.5 + (Pl[:, 2] - zs) / (0.05 * S), 0.0, 1.0), rng, 4)
            fu = np.minimum(fl - 0.04 * L, np.minimum(Pl[:, 2] - zs, cut_field(Pl, q2, n2)))
        else:
            q2, n2, _L = chip_cuts(Pl, Nl, np.clip(0.5 + 3.0 * (fl - inset * L) / max(L, 1e-9), 0.0, 1.0), rng, 4)
            fu = np.minimum(fl - inset * L, cut_field(Pl, q2, n2))
        Pu, Nu, su, Tu, uu = snap_patch(Pl, Nl, sl, Tl, fu)
        # its bed: the lower slab's top at its points (the nearest top points'), sunk a little into it
        dd, ii = cKDTree(Pl).query(Pu, k=3)
        wt = 1.0 / np.maximum(dd, 1e-9)
        bed = (top1[ii] * wt[..., None]).sum(axis=1) / wt.sum(axis=1)[:, None]
        t2 = thick * share
        planes2 = cut_faces(bed, Nu, Tu, t2, k_up, rng)
        V2, T2, s2, top2 = slab_mesh(bed - Nu * (0.05 * t2), Nu, su, Tu, bed, t2, chamfer_w * 0.8, planes2,
                                     0.0, None)
        # (its walls down into the lower slab: the rim's points at the bed less a third of the lower's thickness)
        V2[len(top2):] = bed[np.unique(boundary_edges(Tu))] - Nu[np.unique(boundary_edges(Tu))] * (0.3 * thick)
        slabs.append((V2, T2, s2, 0.86))
        tops.append(top2)
    # the bands
    slab_pts = np.concatenate(tops)
    bands = plate_bands(person, name, slab_pts)
    band_tris = sum(len(bt) for _bv, bt in bands)
    # the slabs merged and decimated (their colour a shade apart: the upper slab another stone)
    Vs, Ts, Ss, Cs = [], [], [], []
    for Vx, Tx, sx, shade in slabs:
        Ts.append(Tx + sum(len(v) for v in Vs))
        Vs.append(Vx)
        Ss.append(sx)
        Cs.append(np.full(len(Vx), shade))
    Vall, Tall, src_all, shade_all = (np.concatenate(Vs), np.concatenate(Ts), np.concatenate(Ss),
                                      np.concatenate(Cs))
    mat = np.full(len(Tall), po.MATS.index("metal"))
    Vd, Td, _md, _uv = po.decimate(Vall, Tall, mat, budget - band_tris, "_plate_" + name, symmetric=False)
    near = cKDTree(Vall).query(Vd)[1]
    src_d = src_all[near]
    shade = shade_all[near]
    uv = box_uv(Vd, Td, STONE_TILE_M / F)
    rgba = np.concatenate([np.repeat(shade[:, None], 3, axis=1), np.ones((len(Vd), 1))], axis=1)
    # the bands appended (their weights the nearest skin's)
    allV, allT, allS, allUV, allC = [Vd], [Td], [src_d], [uv], [rgba]
    off = len(Vd)
    for bv, bt in bands:
        allT.append(bt + off)
        allV.append(bv)
        allS.append(kd.query(bv)[1])
        P_ = bv[bt]
        allUV.append(P_[..., [0, 2]] / (STONE_TILE_M / F))
        allC.append(np.tile(np.asarray(IRON_RGBA), (len(bv), 1)))
        off += len(bv)
    V = np.concatenate(allV)
    Tq = np.concatenate(allT)
    srcq = np.concatenate(allS)
    g = {b: wv[srcq] for b, wv in groups.items()}
    g = stiffen(g, Tq, len(V), 4)
    piece = po.Piece(name, V, Tq, np.full(len(Tq), po.MATS.index("metal")), g, srcq)
    piece.uv = np.concatenate(allUV)
    piece.rgba = np.concatenate(allC)
    piece.facts = {"tris": int(len(Tq)), "slabs": len(slabs), "bands": len(bands), "body_vertices": int(len(Pl)),
                   "thick_m": r6(PLATES[name][0]), "centre_m": [r6(v * F) for v in Vd.mean(axis=0)]}
    return piece


def subdivide(P, Nn, src, T):
    """Each triangle split in four at its edges' middles (the new points' normals the mean, their body vertex the
    edge's first end's)."""
    u, _c = edges_of(T)
    n = len(P)
    key = {tuple(e): n + i for i, e in enumerate(u.tolist())}
    Pm = 0.5 * (P[u[:, 0]] + P[u[:, 1]])
    Nm = Nn[u[:, 0]] + Nn[u[:, 1]]
    Nm /= np.maximum(np.linalg.norm(Nm, axis=1, keepdims=True), 1e-12)
    out = []
    for a, b, c in T.tolist():
        ab, bc, ca = key[(min(a, b), max(a, b))], key[(min(b, c), max(b, c))], key[(min(c, a), max(c, a))]
        out += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
    return (np.concatenate([P, Pm]), np.concatenate([Nn, Nm]), np.concatenate([src, src[u[:, 0]]]),
            np.asarray(out, np.int64))


def stiffen(groups, T, n, it):
    """The weights averaged with their neighbours ``it`` times (a plate bends less than the skin under it)."""
    u, _c = edges_of(T)
    names = sorted(groups)
    W = np.stack([groups[b] for b in names], axis=1)
    deg = np.zeros(n)
    np.add.at(deg, u[:, 0], 1.0)
    np.add.at(deg, u[:, 1], 1.0)
    for _ in range(it):
        acc = W.copy()
        np.add.at(acc, u[:, 0], W[u[:, 1]])
        np.add.at(acc, u[:, 1], W[u[:, 0]])
        W = acc / (1.0 + deg)[:, None]
    W /= np.maximum(W.sum(axis=1, keepdims=True), 1e-12)
    return {b: W[:, i] for i, b in enumerate(names)}


# ======================================================================================================================
# the shackles, the club, the boulder
# ======================================================================================================================
def rigid(n, bone):
    return {bone: np.ones(n)}


def cuff_ring(person, c, axis, sel):
    """A cuff (a thick iron band, rectangular in section) round the body's vertices ``sel`` about the line through
    ``c`` (design) along ``axis``: (V, T)."""
    segs = CUFF["segs"]
    a = unit(axis)
    ref = unit(np.cross(a, [0.0, 1.0, 0.0] if abs(a[1]) < 0.9 else [1.0, 0.0, 0.0]))
    b = np.cross(a, ref)
    Vb = person.body_V()[sel] - c
    ang = np.arctan2(Vb @ b, Vb @ ref)
    rad = np.linalg.norm(Vb - np.outer(Vb @ a, a), axis=1)
    R = np.zeros(segs)
    for s in range(segs):
        ph = -math.pi + 2.0 * math.pi * (s + 0.5) / segs
        dif = np.abs((ang - ph + math.pi) % (2.0 * math.pi) - math.pi)
        near = dif < 2.0 * math.pi / segs
        R[s] = rad[near].max() if near.any() else rad.max()
    R = np.convolve(np.concatenate([R[-1:], R, R[:1]]), np.ones(3) / 3.0, "valid")
    g, t, hw = CUFF["gap"] / F, CUFF["thick"] / F, CUFF["half_w"] / F
    V, T = [], []
    for s in range(segs):
        ph = -math.pi + 2.0 * math.pi * (s + 0.5) / segs
        d = math.cos(ph) * ref + math.sin(ph) * b
        r0, r1 = R[s] + g, R[s] + g + t
        V += [c + d * r0 - a * hw, c + d * r1 - a * hw * 0.92, c + d * r1 + a * hw * 0.92, c + d * r0 + a * hw]
    for s in range(segs):
        a0, b0 = 4 * s, 4 * ((s + 1) % segs)
        for i in range(4):
            j = (i + 1) % 4
            T += [(a0 + i, b0 + i, b0 + j), (a0 + i, b0 + j, a0 + j)]
    V, T = np.asarray(V), np.asarray(T, np.int64)
    return V, outward(V, T, c), (ref, b, R + g + t)


def link_mesh(c, along, across, broken=False):
    """One chain link (an oval ring of round wire) centred at ``c``, its long axis ``along``, its plane holding
    ``across``; ``broken``: a gap cut in its far end (the chain's last, torn link)."""
    L, W, wr = LINK["length"] / F, LINK["width"] / F, LINK["wire"] / F
    segs, sides = LINK["segs"], LINK["sides"]
    al, ac = unit(along), unit(across)
    nrm = np.cross(al, ac)
    pts = []
    for i in range(segs):
        ph = 2.0 * math.pi * i / segs
        pts.append(c + al * (0.5 * (L - wr * 2)) * math.cos(ph) + ac * (0.5 * (W - wr * 2)) * math.sin(ph))
    pts = np.asarray(pts)
    if broken:
        # the torn link: its far end (along +along) cut away, the two ends capped
        cut = [i for i in range(segs) if abs(math.atan2(math.sin(2.0 * math.pi * i / segs),
                                                         math.cos(2.0 * math.pi * i / segs))) > 0.75]
        start = cut.index(min(cut, key=lambda i: (2.0 * math.pi * i / segs - 0.75) % (2.0 * math.pi)))
        path = np.asarray([pts[cut[(start + j) % len(cut)]] for j in range(len(cut))])
        V, T, _r, _a = tube(path, np.full(len(path), wr), sides, close=(True, True), frame0=nrm)
        return V, T
    V, T = [], []
    for i in range(segs):
        tang = unit(pts[(i + 1) % segs] - pts[i - 1])
        u = unit(np.cross(tang, nrm))
        w = np.cross(tang, u)
        for s in range(sides):
            ph = 2.0 * math.pi * s / sides
            V.append(pts[i] + wr * (math.cos(ph) * u + math.sin(ph) * w))
    for i in range(segs):
        for s in range(sides):
            a0, b0 = i * sides + s, i * sides + (s + 1) % sides
            a1, b1 = ((i + 1) % segs) * sides + s, ((i + 1) % segs) * sides + (s + 1) % sides
            T += [(a0, a1, b1), (a0, b1, b0)]
    V, T = np.asarray(V), np.asarray(T, np.int64)
    # wound outward from the wire's own centre line
    nr = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    cc = V[T].mean(axis=1)
    wire_c = pts[T[:, 0] // sides]
    if float(np.einsum("ij,ij->i", nr, cc - wire_c).sum()) < 0:
        T = T[:, ::-1]
    return V, T


def chain(start, down, side, count):
    """``count`` links hanging from ``start`` along ``down``, each turned a quarter from the last; the last torn."""
    L = LINK["length"] / F
    pitch = L - 2.0 * LINK["wire"] / F * 1.15
    Vs, Ts = [], []
    for i in range(count):
        c = start + down * (0.5 * L + i * pitch) + side * (0.012 / F * math.sin(1.7 * i))
        across = side if i % 2 == 0 else np.cross(down, side)
        V, T = link_mesh(c, down, across, broken=(i == count - 1))
        Ts.append(T + sum(len(v) for v in Vs))
        Vs.append(V)
    return np.concatenate(Vs), np.concatenate(Ts)


def shackles_piece(person, idle):
    """The four cuffs and their broken chains (the atlas's metal tile), each rigid to its bone; the wrists' chains
    hang straight down in the idle (built there, carried back to the rest)."""
    import people_outfit as po
    bd = person.bd
    J = {k: v * person.S for k, v in bd.joints.items()}
    V0 = person.body_V()
    m = bd.masks
    rest = person.rest
    Vs, Ts, G = [], [], []

    def add(V, T, bone):
        Ts.append(T + sum(len(v) for v in Vs))
        Vs.append(V)
        G.append((bone, len(V)))

    for sd, s in (("l", 1.0), ("r", -1.0)):
        el, wr = J["joint-%s-elbow" % sd], J["joint-%s-hand" % sd]
        a = unit(wr - el)
        c = wr - a * (0.30 / F)
        t = (V0 - c) @ a
        sel = (np.abs(t) < 0.20 / F) & (m["m_forearm"] + m["m_hand"] > 0.4) & (np.sign(V0[:, 0]) == s) \
            & (np.linalg.norm(V0 - c, axis=1) < 1.0 / F)
        Vc, Tc, (ref, b, R) = cuff_ring(person, c, a, sel)
        bone = "lowerarm_" + sd
        add(Vc, Tc, bone)
        # the chain: from the cuff's lowest point in the idle, straight down, carried back to the rest
        D, P = idle.D[bone], idle.P[bone]
        h = rest.head[bone]
        ring = [c + (math.cos(ph) * ref + math.sin(ph) * b) * R[k]
                for k, ph in enumerate(-math.pi + 2.0 * math.pi * (np.arange(CUFF["segs"]) + 0.5) / CUFF["segs"])]
        posed = [P + D @ (q - h) for q in ring]
        out = np.array([s, 0.0, 0.0])
        lowest = min(range(len(posed)), key=lambda k: posed[k][2] - 0.4 * float((posed[k] - P) @ out))
        start = posed[lowest] + np.array([0.0, 0.0, -0.02 / F])
        side = unit(np.cross([0.0, 0.0, -1.0], [0.0, 1.0, 0.0]))
        Vl, Tl = chain(start, np.array([0.0, 0.0, -1.0]), side, CHAINS["wrist_" + sd])
        Vl = h + (Vl - P) @ D            # back to the rest: h + D^T (p - P)
        add(Vl, Tl, bone)
    for sd, s in (("l", 1.0), ("r", -1.0)):
        kn, an = J["joint-%s-knee" % sd], J["joint-%s-ankle" % sd]
        a = unit(an - kn)
        c = an - a * (0.62 / F)
        t = (V0 - c) @ a
        sel = (np.abs(t) < 0.22 / F) & (m["m_lowerleg"] + m["m_foot"] > 0.4) & (np.sign(V0[:, 0]) == s) \
            & (np.linalg.norm(V0 - c, axis=1) < 1.2 / F)
        Vc, Tc, (ref, b, R) = cuff_ring(person, c, a, sel)
        add(Vc, Tc, "calf_" + sd)
        # the chain from the cuff's back and outer side, down along the heel
        ph = math.atan2(float(np.array([s * 0.5, 0.85, 0.0]) @ b), float(np.array([s * 0.5, 0.85, 0.0]) @ ref))
        k = int(round((ph + math.pi) / (2.0 * math.pi) * CUFF["segs"] - 0.5)) % CUFF["segs"]
        start = c + (math.cos(ph) * ref + math.sin(ph) * b) * (R[k] + 0.02 / F) - a * (CUFF["half_w"] / F * 0.6)
        Vl, Tl = chain(start, np.array([0.0, 0.25, -1.0]) / np.linalg.norm([0.0, 0.25, -1.0]),
                       np.array([1.0, 0.0, 0.0]), CHAINS["ankle_" + sd])
        add(Vl, Tl, "calf_" + sd)
    V = np.concatenate(Vs)
    T = np.concatenate(Ts)
    groups = {}
    off = 0
    for bone, cnt in G:
        groups.setdefault(bone, np.zeros(len(V)))[off:off + cnt] = 1.0
        off += cnt
    p = po.Piece("shackles", V, T, np.full(len(T), po.MATS.index("metal")), groups, np.full(len(V), -1))
    p.uv = po.tile_uv(p, "metal", np.array([0.0, float(V[:, 1].mean()), 0.0]))
    return p


def icosphere(subdiv):
    """A unit icosphere: (V, T), wound outward."""
    t = (1.0 + 5 ** 0.5) / 2.0
    V = [unit(v) for v in [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t),
                           (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]]
    F_ = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
          (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
          (8, 6, 7), (9, 8, 1)]
    for _ in range(subdiv):
        cache = {}
        nf = []

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                V.append(unit((np.asarray(V[a]) + np.asarray(V[b])) * 0.5))
                cache[key] = len(V) - 1
            return cache[key]
        for a, b, cc in F_:
            ab, bc, ca = mid(a, b), mid(b, cc), mid(cc, a)
            nf += [(a, ab, ca), (b, bc, ab), (cc, ca, bc), (ab, bc, ca)]
        F_ = nf
    V = np.asarray(V)
    return V, outward(V, np.asarray(F_, np.int64), np.zeros(3))


def club_piece(person):
    """The uprooted trunk (design scale, at the rest hand): its handle through the right fist's grip landmark along
    the grip's line, the thin broken top beyond the little finger, the root ball beyond the thumb; on the bark."""
    import people_bake as pbk
    import people_outfit as po
    g, ax = person.grip["r"]
    ax = unit(ax)
    rng = np.random.default_rng(91)
    ref = unit(np.cross(ax, [0.0, 0.0, 1.0]))
    L, hl, R = CLUB["length_m"] / F, CLUB["handle_m"] / F, CLUB["root_r"] / F
    r_grip = person.grip_radius
    rings, segs = CLUB["rings"], CLUB["segs"]
    s = np.linspace(-hl, L - 0.45 * R, rings)
    tt = (s + hl) / (L + hl)
    base_r = np.interp(s, [-hl, 0.0, 0.12 * L, 0.45 * L, 0.80 * L, L - 1.2 * R, L - 0.45 * R],
                       [0.85 * r_grip, r_grip, 1.7 * r_grip, 2.3 * r_grip, 2.8 * r_grip, 3.4 * r_grip,
                        4.6 * r_grip])
    bend = np.outer(np.sin(tt * 2.6) * 0.06 * L * 0.12, ref) + np.outer(np.sin(tt * 4.1 + 1.0) * 0.004 * L,
                                                                         np.cross(ax, ref))
    path = g + np.outer(s, ax) + bend
    phs = 2.0 * math.pi * np.arange(segs) / segs
    radii = np.zeros((rings, segs))
    for i in range(rings):
        q = np.stack([np.cos(phs), np.sin(phs), np.full(segs, s[i] * 0.6)], axis=1) * F
        furrow = pbk.fbm(q * [1.0, 1.0, 0.25], 2.0, 93) - 0.5
        radii[i] = base_r[i] * (1.0 + 0.16 * furrow + 0.05 * np.sin(5.0 * phs + 0.7 * i))
    Vt, Tt, ring, ang = tube(path, radii, segs, close=(True, False), frame0=ref)
    parts = [(Vt, Tt, "trunk", ring, ang)]
    # the root ball: the torn root plate, a flattened lumpy mass of earth and roots at the end; roots fan out from it
    # and bend on past it (the side away from the handle), long and short, thick at the base
    centre = g + ax * L
    w_ = np.cross(ax, ref)
    rb = float(base_r[-1])
    Vb, Tb, _r, _a = tube(np.array([centre - ax * R * 0.75, centre - ax * R * 0.35, centre, centre + ax * R * 0.35,
                                    centre + ax * R * 0.62]),
                          np.array([rb * 1.05, R * 0.82, R, R * 0.78, R * 0.30]), 18, frame0=ref)
    Pn = (Vb - centre) / R
    bump = pbk.fbm(Pn * 1.4 + 3.0, 2.0, 97) - 0.5
    clod = np.clip((pbk.vnoise(Pn * 1.0 + 7.0, 3.5, 99) - 0.6) / 0.3, 0.0, 1.0)
    Vb = centre + (Vb - centre) * (1.0 + 0.32 * bump + 0.18 * clod)[:, None]
    parts.append((Vb, Tb, "ball", None, None))
    # A1b: fewer, thick, gnarled roots (kinked, knotted, their broken ends blunt), and clods of earth caught in them
    for k in range(CLUB["roots"]):
        az = 2.0 * math.pi * (k + rng.uniform(-0.25, 0.25)) / CLUB["roots"]
        d = math.cos(az) * ref + math.sin(az) * w_
        reach = R * rng.uniform(0.75, 1.15)
        fwd = rng.uniform(0.35, 0.8)
        side_d = np.cross(ax, d)
        pts = []
        for i, t in enumerate(np.linspace(0.0, 1.0, 7)):
            kink = rng.normal(0.0, 0.10) * R * t
            pts.append(centre + ax * (rng.uniform(-0.12, 0.08) * R + fwd * R * t * t) + d * (0.45 * R + reach * t)
                       + side_d * kink + ax * rng.normal(0.0, 0.06) * R * t)
        knot = 1.0 + 0.22 * np.sin(np.arange(7) * 2.1 + k)
        rr = np.array([0.50, 0.42, 0.35, 0.29, 0.24, 0.20, 0.16]) * R * 0.62 * knot
        Vr, Tr, _r2, _a2 = tube(np.asarray(pts), rr, 7, close=(False, True))
        parts.append((Vr, Tr, "root", None, None))
    for k in range(CLUB["clods"]):
        az = 2.0 * math.pi * (k + 0.5 + rng.uniform(-0.2, 0.2)) / CLUB["clods"]
        d = math.cos(az) * ref + math.sin(az) * w_
        cc = centre + d * R * rng.uniform(0.55, 0.85) + ax * R * rng.uniform(-0.35, 0.35)
        Vc, Tc = icosphere(1)
        rad = R * rng.uniform(0.34, 0.50) * (1.0 + 0.35 * (pbk.fbm(Vc * 1.7 + k, 2.0, 95) - 0.5))
        Vc = cc + Vc * rad[:, None] * np.array([1.0, 0.85, 0.75])
        parts.append((Vc, Tc, "clod", None, None))
    # three sawn-off branch stumps along the trunk
    for k, (st, az) in enumerate(((0.32, 0.6), (0.55, 2.7), (0.7, 4.6))):
        d = math.cos(az) * ref + math.sin(az) * w_
        c0 = g + ax * (st * L)
        r0 = float(np.interp(st * L, s, base_r))
        pts = [c0 + d * r0 * 0.4, c0 + d * (r0 + 0.35 / F) + ax * 0.12 / F, c0 + d * (r0 + 0.75 / F) + ax * 0.28 / F]
        Vr, Tr, _r2, _a2 = tube(np.asarray(pts), np.array([0.45, 0.36, 0.30]) * r0, 7)
        parts.append((Vr, Tr, "stump", None, None))
    Vs, Ts, UV, COL = [], [], [], []
    tile_u, tile_v = BARK_TILE_M[0] / F, BARK_TILE_M[1] / F
    for V, T, what, ring_i, ang in parts:
        T = outward(V, T, V.mean(axis=0)) if what != "trunk" else T
        if what == "trunk":
            # round the trunk and along it (the seam's corners kept on one side: u unwrapped per triangle)
            circ = 2.0 * math.pi * np.repeat(base_r[:, None], segs, axis=1).ravel()
            circ = np.append(circ, [circ[:segs].mean()])
            uu = ang / (2.0 * math.pi)
            vv = (s[ring_i] + hl) / tile_v
            C = np.stack([uu, vv], axis=-1)[T]
            du = C[..., 0] - C[:, :1, 0]
            C[..., 0] = np.where(du > 0.5, C[..., 0] - 1.0, np.where(du < -0.5, C[..., 0] + 1.0, C[..., 0]))
            C[..., 0] *= circ[T].mean(axis=1, keepdims=True) / tile_u
            uv = C
        else:
            nrm = unit(np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]]).sum(axis=0) + 1e-9)
            uv = planar_uv(V, T, ax if what in ("ball", "root", "clod") else nrm, tile_u) + rng.uniform(0, 1, 2)
        Ts.append(T + sum(len(v) for v in Vs))
        Vs.append(V)
        UV.append(uv)
        rgba = EARTH_RGBA if what == "clod" else ((0.72, 0.64, 0.56, 1.0) if what == "ball" else (1.0, 1.0, 1.0, 1.0))
        COL.append(np.tile(np.asarray(rgba), (len(V), 1)))
    V, T, uv = np.concatenate(Vs), np.concatenate(Ts), np.concatenate(UV)
    mat = np.full(len(T), po.MATS.index("leather"))
    p = po.Piece("club", V, T, mat, rigid(len(V), "hand_r"), np.full(len(V), -1))
    p.uv = uv
    p.rgba = np.concatenate(COL)
    p.facts = {"length_m": r6((L + hl + 0.75 * R) * F), "handle_r_m": r6(r_grip * F), "root_ball_r_m": r6(R * F)}
    p.head_point = centre
    return p


def boulder_piece(person):
    """A boulder in the left palm (rigid to hand_l): a chiselled icosphere, its centre off the palm."""
    import people_bake as pbk
    import people_outfit as po
    import clips
    g, _ax = person.grip["l"]
    n, _across = clips.hand_frame(person.rest, "l")
    R = BOULDER_R / F
    # an icosphere (two subdivisions)
    t = (1.0 + 5 ** 0.5) / 2.0
    V = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
         (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    V = [unit(v) for v in V]
    F_ = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
          (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
          (8, 6, 7), (9, 8, 1)]
    for _ in range(2):
        cache = {}
        nf = []

        def mid(a, b):
            key = (min(a, b), max(a, b))
            if key not in cache:
                V.append(unit((np.asarray(V[a]) + np.asarray(V[b])) * 0.5))
                cache[key] = len(V) - 1
            return cache[key]
        for a, b, cc in F_:
            ab, bc, ca = mid(a, b), mid(b, cc), mid(cc, a)
            nf += [(a, ab, ca), (b, bc, ab), (cc, ca, bc), (ab, bc, ca)]
        F_ = nf
    U = np.asarray(V)
    rng = np.random.default_rng(57)
    planes = rng.normal(0, 1, (14, 3))
    planes /= np.linalg.norm(planes, axis=1, keepdims=True)
    r = np.ones(len(U)) * 1.1
    for pl in planes:                                   # cut by planes: flat quarried faces
        off = rng.uniform(0.72, 0.92)
        dots = U @ pl
        r = np.minimum(r, np.where(dots > 0.05, off / np.maximum(dots, 0.05), 9.0))
    r = np.clip(r, 0.62, 1.05) * (1.0 + 0.05 * (pbk.fbm(U * 2.0 + 5.0, 2.5, 59) - 0.5))
    shape = U * (R * r)[:, None] * np.array([1.0, 0.9, 0.82])
    # A1b: set into the curled fingers: the nearest place along the palm's normal where the hand's deepest point is
    # BOULDER_SINK of the radius inside it (the finger pads pressed into its faces, not the rock on the fingertips)
    from scipy.spatial import cKDTree
    Vh = person.body_V()
    hand = (person.bd.masks["m_hand"] > 0.4) & (Vh[:, 0] > 0.0)
    Hv = Vh[hand]
    kd = cKDTree(shape / np.linalg.norm(shape, axis=1, keepdims=True))

    def depth(cc):
        d = Hv - cc
        dist = np.linalg.norm(d, axis=1)
        i = kd.query(d / np.maximum(dist, 1e-9)[:, None])[1]
        return float((np.linalg.norm(shape[i], axis=1) - dist).max())
    for k in np.linspace(0.3, 1.6, 66):
        c = g + unit(n) * R * k
        if depth(c) <= BOULDER_SINK * R:
            break
    Vb = c + shape
    T = outward(Vb, np.asarray(F_, np.int64), c)
    p = po.Piece("boulder", Vb, T, np.full(len(T), po.MATS.index("metal")), rigid(len(Vb), "hand_l"),
                 np.full(len(Vb), -1))
    uv = box_uv(Vb, T, STONE_TILE_M / F)
    p.uv = uv
    return p


# ======================================================================================================================
# the detail textures (tileable): the stone and the bark
# ======================================================================================================================
def _torus(u, v):
    """Points on a torus in 4D folded into 3D noise space: periodic in u and v (0..1)."""
    a, b = 2.0 * math.pi * u, 2.0 * math.pi * v
    return np.stack([np.cos(a) + 0.37 * np.cos(b), np.sin(a) + 0.37 * np.sin(b), 0.6 * np.cos(b) + 0.4 * np.sin(a + b)],
                    axis=-1)


def _worley(u, v, cells, seed):
    """Tileable cellular noise over the unit square (``cells`` jittered points a side): (F1, F2) in cell units."""
    rng = np.random.default_rng(seed)
    pts = rng.uniform(0.0, 1.0, (cells, cells, 2))
    x, y = np.asarray(u) * cells, np.asarray(v) * cells
    ix, iy = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64)
    f1 = np.full(x.shape, np.inf)
    f2 = np.full(x.shape, np.inf)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            cx, cy = ix + dx, iy + dy
            p = pts[cx % cells, cy % cells]
            d = np.hypot(x - (cx + p[..., 0]), y - (cy + p[..., 1]))
            f2 = np.where(d < f1, f1, np.minimum(f2, d))
            f1 = np.minimum(f1, d)
    return f1, f2


STRATA_BEDS = 6                    # the stone's bedding planes a texture repeat (about every 0.57 m)


def _stone_layers(u, v):
    """The quarried stone's parts at (u, v) (tileable): the bed (an index), the bedding lines, the cracks, the lichen,
    the mottling, the ochre stains."""
    import people_bake as pbk
    P = _torus(u, v)
    big = pbk.fbm(P, 1.6, 201, 4)
    mid = pbk.fbm(P, 3.2, 203, 4)
    grain = pbk.vnoise(P, 38.0, 207)
    # bedding: STRATA_BEDS beds down the repeat, their planes wavy and jittered
    rng = np.random.default_rng(231)
    edges = (np.arange(STRATA_BEDS) + rng.uniform(-0.25, 0.25, STRATA_BEDS)) / STRATA_BEDS
    vw = (v + 0.018 * np.sin(2.0 * math.pi * (u + 0.3 * big)) + 0.03 * (mid - 0.5)) % 1.0
    dv = np.abs(((vw[:, None] - edges[None, :]) + 0.5) % 1.0 - 0.5)
    bed = np.searchsorted(edges, vw) % STRATA_BEDS
    line = 1.0 - _sstep(dv.min(axis=1), 0.0, 0.010 + 0.006 * grain)
    # cracks: a cell network, only part of it open, and a finer one fainter
    f1, f2 = _worley(u, v, 5, 233)
    open_ = _sstep(pbk.fbm(P, 2.2, 235, 3), 0.56, 0.64)
    crack = (1.0 - _sstep(f2 - f1, 0.0, 0.035)) * open_
    g1, g2 = _worley(u, v, 11, 237)
    crack = np.maximum(crack, 0.4 * (1.0 - _sstep(g2 - g1, 0.0, 0.03)) * _sstep(pbk.fbm(P, 3.0, 239, 3), 0.62, 0.70))
    # lichen: crusty patches (pale grey-green, a few ochre-yellow) away from the cracks
    patch = _sstep(pbk.fbm(P, 3.4, 241, 4), 0.62, 0.68)
    speck = _sstep(pbk.vnoise(P, 30.0, 243), 0.35, 0.6)
    lichen = patch * (0.55 + 0.45 * speck) * (1.0 - crack)
    yellow = _sstep(pbk.fbm(P, 1.8, 245, 3), 0.66, 0.72)
    ochre = np.clip((pbk.fbm(P, 2.0, 209, 3) - 0.46) / 0.18, 0.0, 1.0)
    return dict(big=big, mid=mid, grain=grain, bed=bed, line=line, crack=crack, lichen=lichen, yellow=yellow,
                ochre=ochre)


def stone_height(u, v):
    L = _stone_layers(u, v)
    step = (np.asarray(L["bed"]) * 0.37 % 1.0) * 0.25                 # each bed a little proud of the next
    return 0.45 * L["mid"] + 0.06 * L["grain"] + step - 0.45 * L["line"] - 0.9 * L["crack"] + 0.12 * L["lichen"]


def stone_albedo(u, v):
    L = _stone_layers(u, v)
    tone = 0.92 + 0.24 * ((np.asarray(L["bed"]) * 0.61) % 1.0 - 0.5)  # each bed its own shade
    grey = np.array([0.36, 0.35, 0.33])
    shade = tone + 0.16 * (L["big"] - 0.5) + 0.10 * (L["mid"] - 0.5) + 0.06 * (L["grain"] - 0.5)
    col = grey[None, :] * shade[:, None]
    och = np.array([0.44, 0.37, 0.27])
    col = col * (1.0 - 0.4 * L["ochre"][:, None]) + och[None, :] * 0.4 * L["ochre"][:, None]
    col *= (1.0 - 0.38 * L["line"])[:, None]
    col *= (1.0 - 0.55 * L["crack"])[:, None]
    lc = np.array([0.50, 0.52, 0.44])[None, :] * (1.0 - L["yellow"][:, None]) \
        + np.array([0.56, 0.50, 0.32])[None, :] * L["yellow"][:, None]
    li = (0.6 * L["lichen"])[:, None]
    return col * (1.0 - li) + lc * li


def detail_textures(out_dir):
    """stoneback_stone_albedo.png / _normal.png and stoneback_bark_albedo.png / _normal.png (DETAIL_PX, tileable)."""
    import people_bake as pbk
    n = DETAIL_PX
    yy, xx = np.mgrid[0:n, 0:n]
    u, v = xx.ravel() / n, yy.ravel() / n
    paths = {}
    for what in ("stone", "bark"):
        if what == "stone":
            P = _torus(u, v)
            hfun = stone_height
            height = stone_height(u, v)
            col = stone_albedo(u, v)
            amp = 1.0
        else:
            # the bark: vertical plates split by deep furrows (stretched noise along v), grey-brown
            def bark_h(uu, vv):
                Q = _torus(uu, vv) * np.array([1.0, 1.0, 1.0])
                Qs = np.stack([np.cos(2 * math.pi * uu) * 3.0, np.sin(2 * math.pi * uu) * 3.0,
                               np.cos(2 * math.pi * vv) * 0.5 + np.sin(2 * math.pi * vv) * 0.4], axis=-1)
                ridge = pbk.fbm(Qs, 2.0, 221, 4)
                plates = np.clip((ridge - 0.35) / 0.25, 0.0, 1.0)
                return 0.7 * plates + 0.2 * pbk.fbm(Q, 9.0, 223, 3) + 0.1 * pbk.vnoise(Q, 40.0, 225)
            height = bark_h(u, v)
            hfun = bark_h
            P = _torus(u, v)
            tone = pbk.fbm(P, 3.0, 227, 3)
            col = np.array([0.30, 0.25, 0.20])[None, :] * (0.55 + 0.75 * height + 0.25 * (tone - 0.5))[:, None]
            moss = np.clip((pbk.fbm(P, 2.0, 229, 3) - 0.62) / 0.1, 0.0, 1.0) * (height > 0.5)
            col = col * (1.0 - 0.5 * moss[:, None]) + np.array([0.30, 0.34, 0.18])[None, :] * 0.5 * moss[:, None]
            amp = 3.0
        e = 1.0 / n
        dx = (hfun(u + e, v) - hfun(u - e, v)) / (2.0 * e) / n
        dy = (hfun(u, v + e) - hfun(u, v - e)) / (2.0 * e) / n
        # (the normal map's green runs down the texture, as the bake's: Godot's frame for a glTF's tangents)
        nrm = np.stack([-dx * amp * 6.0, dy * amp * 6.0, np.ones_like(dx)], axis=-1)
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
        alb = pbk.to_u8(np.clip(col, 0.0, 1.0).reshape(n, n, 3))
        nm = pbk.to_u8((nrm * 0.5 + 0.5).reshape(n, n, 3))
        for k, arr in (("albedo", alb), ("normal", nm)):
            p = os.path.join(out_dir, "%s_%s_%s.png" % (KIND, what, k))
            pbk.save_png(p, arr)
            paths["%s_%s" % (what, k)] = os.path.basename(p)
    return paths


# ======================================================================================================================
# the skin: Stoneback's hide over the bake's skin band; the scars under the plates
# ======================================================================================================================
HIDE_BASE = 0.66


HAIR_MUL = np.array([0.20, 0.18, 0.17])      # his cropped, matted hair and the stubble over the skin's colour
STUBBLE_MUL = np.array([0.30, 0.27, 0.26])
SKIN_ROUGH = 0.80                  # his skin's roughness (dry, weathered: the bake's left it looking oiled)


def _seg_dist(P, a, b):
    seg = b - a
    t = np.clip(((P - a) @ seg) / max(float(seg @ seg), 1e-12), 0.0, 1.0)
    return np.linalg.norm(P - (a + np.outer(t, seg)), axis=1)


def hide(P, Nrm, under, look=None):
    """(albedo multiplier (n, 3), height field (n,)) of his skin at points P (human m, rest), normals Nrm; ``under``
    (n,) 0..1: under a plate (a little paler, scarred: the plate's weight wore the skin); ``look``: {"masks": a
    function of P giving the body's region masks there, "scars": the face's scars as segments (human m)}."""
    import people_bake as pbk
    big = pbk.fbm(P, 5.0, 301)
    mid = pbk.fbm(P, 16.0, 303)
    fine = pbk.vnoise(P, 80.0, 307)
    z = P[:, 2]
    hz = z / max(float(z.max()), 1e-6)
    mk = look["masks"](P) if look else None
    # (the base kept well under 1: the bake's skin is near white)
    grey = HIDE_BASE * (1.0 + 0.20 * (big - 0.5) + 0.12 * (mid - 0.5) + 0.07 * (fine - 0.5))
    back = np.clip(Nrm[:, 1], 0.0, 1.0)
    grey *= 1.0 - 0.10 * back * _sstep(hz, 0.5, 0.8)                  # sun-darkened shoulders and back
    # A1b: weathering: grime and old sun in broad darker patches over the whole hide, the hands and forearms darker
    grime = _sstep(pbk.fbm(P, 3.0, 351, 4), 0.42, 0.66)
    grey *= 1.0 - 0.18 * grime
    if mk is not None:
        grey *= 1.0 - 0.10 * np.clip(mk["m_hand"] + 0.6 * mk["m_forearm"], 0.0, 1.0)
    mul = np.repeat(grey[:, None], 3, axis=1)
    mul *= np.array([1.0, 0.97, 0.95])[None, :] * (1.0 - 0.3 * grime[:, None]) + 0.3 * grime[:, None] \
        * np.array([0.96, 0.94, 0.94])[None, :]
    # quarry dust: a pale grey crust on the feet, the shins, the forearms and the hands, and in patches over the
    # chest, the thighs and the shoulders (the stone he carries)
    dust_w = np.clip(1.0 - hz / 0.34, 0.0, 1.0) ** 0.8
    if mk is not None:
        dust_w = np.maximum(dust_w, 0.55 * mk["m_forearm"] + 0.75 * mk["m_hand"])
    dust_w = np.maximum(dust_w, 0.55 * _sstep(pbk.fbm(P, 4.0, 353, 3), 0.55, 0.70))
    dust = np.clip((dust_w * 0.9 + 0.8 * (pbk.fbm(P, 7.0, 311) - 0.5) - 0.25) / 0.25, 0.0, 1.0)
    dust_col = np.array([1.12, 1.12, 1.22])
    mul = mul * (1.0 - 0.55 * dust[:, None]) + dust_col[None, :] * grey[:, None] * 0.55 * dust[:, None]
    # under a plate: the same skin a little paler and less red, scored with old welts and pressure scars (subtle)
    welt = np.abs(np.sin(P[:, 0] * 140.0 + 9.0 * pbk.fbm(P, 6.0, 313) + P[:, 2] * 60.0))
    welt = 1.0 - _sstep(welt, 0.0, 0.16)
    scar = np.clip(welt * (pbk.vnoise(P, 22.0, 317) > 0.45), 0.0, 1.0)
    pale = np.array([1.10, 1.08, 1.08])
    u = np.clip(under, 0.0, 1.0)[:, None]
    mul = mul * (1.0 - u) + pale[None, :] * mul * u
    mul = mul * (1.0 + scar[:, None] * u * np.array([0.10, 0.07, 0.07])[None, :])
    height = 0.30 * mid + 0.18 * fine + 0.45 * scar * np.clip(under, 0, 1) + 0.15 * dust + 0.10 * grime
    if mk is not None:
        # the head: cropped, matted hair over the scalp (seen with the brow's plate off), stubble over the jaw and the
        # lip, heavy dark brows, a lined forehead, crow's feet
        sp = pbk.vnoise(P, 900.0, 361)
        hair = mk["m_scalp"] * (0.78 + 0.22 * _sstep(sp, 0.3, 0.7)) * (0.85 + 0.3 * (pbk.fbm(P, 60.0, 363) - 0.5))
        hair = np.clip(hair, 0.0, 1.0)
        mul = mul * (1.0 - hair[:, None]) + HAIR_MUL[None, :] * hair[:, None]
        st = 0.85 * mk["m_beard"] * (0.45 + 0.55 * _sstep(pbk.vnoise(P, 1100.0, 365), 0.35, 0.6))
        mul = mul * (1.0 - st[:, None]) + STUBBLE_MUL[None, :] * st[:, None]
        brow = np.clip(mk["m_brow"] * 1.2, 0.0, 1.0) * (0.7 + 0.3 * sp)
        mul *= (1.0 - 0.65 * brow)[:, None]
        wave = np.abs(np.sin(P[:, 2] * 520.0 + 6.0 * pbk.fbm(P, 30.0, 367)))
        lines = mk["m_forehead"] * (1.0 - _sstep(wave, 0.0, 0.35))
        fan = np.abs(np.sin(np.arctan2(P[:, 2], P[:, 1]) * 90.0 + 40.0 * P[:, 0]))
        crow = mk["m_crow"] * (1.0 - _sstep(fan, 0.0, 0.3))
        wr = np.clip(lines + crow, 0.0, 1.0)
        mul *= (1.0 - 0.16 * wr)[:, None]
        height = height + 0.35 * hair * sp - 0.6 * wr + 0.2 * st
    if look and look.get("scars"):
        # the face's old scars (seen from the front: segments across x and z): pale, raised
        front = _sstep(-Nrm[:, 1], 0.1, 0.4) * (mk["m_head"] if mk is not None else 1.0)
        sc = np.zeros(len(P))
        for a_, b_, w_ in look["scars"]:
            d = _seg_dist(P[:, [0, 2]], np.asarray(a_), np.asarray(b_))
            sc = np.maximum(sc, 1.0 - _sstep(d, 0.4 * w_, w_))
        sc *= front
        mul = mul * (1.0 - 0.7 * sc[:, None]) + (mul * np.array([1.30, 1.18, 1.16])[None, :]) * 0.7 * sc[:, None]
        height = height + 0.8 * sc
    return mul, height


LOOK_MASKS = ("m_head", "m_scalp", "m_beard", "m_brow", "m_forehead", "m_crow", "m_hand", "m_forearm")


def masks_at(P, kd, masks):
    """The body's region masks (LOOK_MASKS) at points P (human m): the nearest four body vertices' by distance."""
    d, i = kd.query(P, k=4)
    w = 1.0 / np.maximum(d, 1e-5)
    w /= w.sum(axis=1, keepdims=True)
    return {k: (np.asarray(masks[k])[i] * w).sum(axis=1) for k in LOOK_MASKS}


def face_scars(person):
    """His face's old scars as (start, end, width) in x and z (human m, seen from the front): across the right
    cheekbone, over the broken nose's bridge, through the lip to the chin, and down the left brow."""
    J = person.bd.joints
    eL, eR = J["joint-l-eye"], J["joint-r-eye"]
    ez, ex = 0.5 * (eL[2] + eR[2]), 0.5 * (abs(eL[0]) + abs(eR[0]))
    mz = J["joint-mouth"][2]
    return [((-ex - 0.004, ez - 0.016), (-ex + 0.011, ez - 0.056), 0.0024),
            ((0.012, ez - 0.004), (-0.010, ez - 0.017), 0.0019),
            ((0.008, mz + 0.012), (0.015, mz - 0.024), 0.0019),
            ((ex - 0.010, ez + 0.042), (ex + 0.005, ez + 0.013), 0.0021)]


def repaint(out_dir, LV, LT, Luv, tan, sgn, nor, S, under_fn, hide_tris=None, look=None):
    """The bake's skin texels repainted with his hide (see hide); the hide's height into the normal map; the metal
    tile dark iron, the leather tile his hide's (the kilt)."""
    import people_bake as pbk
    from PIL import Image
    paths = {k: os.path.join(out_dir, "%s_%s.png" % (KIND, k)) for k in ("albedo", "normal", "orm")}
    alb = np.asarray(Image.open(paths["albedo"]).convert("RGB")).astype(np.float64) / 255.0
    nrm = np.asarray(Image.open(paths["normal"]).convert("RGB")).astype(np.float64) / 255.0 * 2.0 - 1.0
    orm = np.asarray(Image.open(paths["orm"]).convert("RGB")).copy()
    skin_b = pr.band_byte("skin")
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
        if img == "albedo" and hide_tris is not None:
            # the kilt's hide: mottled, darker patches, a greyer brown than the bake's leather
            kh = hide_tris[t]
            Pk = P[kh]
            mott = 0.80 + 0.34 * (pbk.fbm(Pk, 9.0, 341) - 0.5) + 0.12 * (pbk.vnoise(Pk, 60.0, 343) - 0.5)
            dark = np.clip((pbk.fbm(Pk, 4.0, 347) - 0.55) / 0.15, 0.0, 1.0)
            k_col = np.array([0.92, 0.86, 0.80])[None, :] * (mott * (1.0 - 0.3 * dark))[:, None]
            alb[ys[kh], xs[kh]] = np.clip(alb[ys[kh], xs[kh]] * k_col, 0.0, 1.0)
        skin = orm[oy, ox, 2] == skin_b
        under = under_fn(P[skin])
        mul, height = hide(P[skin], Nl[skin], under, look)
        if img == "albedo":
            alb[ys[skin], xs[skin]] = np.clip(alb[ys[skin], xs[skin]] * mul, 0.0, 1.0)
        else:
            e = 0.004
            Tl = np.einsum("nk,nkj->nj", b, tan[t])[skin]
            Bl = np.cross(Nl[skin], Tl) * np.sign(sgn[t[skin], 0])[:, None]
            Ps = P[skin]
            g1 = (hide(Ps + Tl * e, Nl[skin], under, look)[1] - height) / e
            g2 = (hide(Ps + Bl * e, Nl[skin], under, look)[1] - height) / e
            amp = 0.0040
            n0 = nrm[ys[skin], xs[skin]]
            n1 = n0 - amp * np.stack([g1, g2, np.zeros_like(g1)], axis=1)
            n1 /= np.maximum(np.linalg.norm(n1, axis=1, keepdims=True), 1e-9)
            nrm[ys[skin], xs[skin]] = n1
    rows = int(round((1.0 - pr.TILE_SIZE) * pr.ORM_PX))
    garment = orm[:rows, :, 2] != skin_b
    orm[:rows, :, 1] = np.where(~garment, np.maximum(orm[:rows, :, 1], int(round(SKIN_ROUGH * 255))), orm[:rows, :, 1])
    orm[:rows, :, 0] = np.where(garment, np.maximum(orm[:rows, :, 0], int(round(br.GARMENT_AO_FLOOR * 255))),
                                orm[:rows, :, 0])
    for name, (rgb, rough) in TILE_REPAINT.items():
        u0, v0 = pr.TILES[name]
        for size, arr in ((pr.ALBEDO_PX, alb), (pr.ORM_PX, orm)):
            x0, x1 = int(round(u0 * size)), int(round((u0 + pr.TILE_SIZE) * size))
            y0, y1 = int(round((1.0 - v0 - pr.TILE_SIZE) * size)), int(round((1.0 - v0) * size))
            if arr is alb:
                yy, xx = np.mgrid[y0:y1, x0:x1]
                Pq = np.stack([xx.ravel() / size, yy.ravel() / size, np.zeros(xx.size)], -1)
                val = 0.78 + 0.4 * pbk.fbm(Pq * 3.0, 6.0, 331)
                alb[y0:y1, x0:x1] = (np.array(rgb)[None, :] * val[:, None]).reshape(y1 - y0, x1 - x0, 3)
            else:
                orm[y0:y1, x0:x1, 1] = int(round(rough * 255))
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))
    pbk.save_png(paths["normal"], pbk.to_u8(nrm * 0.5 + 0.5))
    pbk.save_png(paths["orm"], orm)


# the atlas's tiles repainted: the shackles' iron dark and rusted (rough enough not to read as polished plate)
TILE_REPAINT = {"metal": ((0.17, 0.155, 0.145), 0.62)}


# ======================================================================================================================
# the clips
# ======================================================================================================================
class Holder:
    """The two hands' grip landmarks (rest, design) and the arms' rest lengths, for ``hold``."""

    def __init__(self, person):
        r = person.rest
        self.rest = r
        self.grip = {s: (np.asarray(person.grip[s][0]), unit(person.grip[s][1])) for s in ("l", "r")}
        self.l1, self.l2, self.pole0 = {}, {}, {}
        for s in ("l", "r"):
            sh, el, wr = (r.head[b + "_" + s] for b in ("upperarm", "lowerarm", "hand"))
            self.l1[s] = float(np.linalg.norm(el - sh))
            self.l2[s] = float(np.linalg.norm(wr - el))
            d = unit(wr - sh)
            q = el - sh
            self.pole0[s] = unit(q - d * float(q @ d))

    def grip_posed(self, pose, s):
        r = self.rest
        g, a = self.grip[s]
        h = "hand_" + s
        return pose.P[h] + pose.D[h] @ (g - r.head[h]), pose.D[h] @ a

    def orient_hand(self, pose, s, axis):
        """The hand turned onto ``axis`` (its grip line) by the least turn from its forearm's."""
        import clips
        pose.solve()
        D_lo = pose.D["lowerarm_" + s]
        D = clips.between(D_lo @ self.grip[s][1], axis) @ D_lo
        pose.set_abs("hand_" + s, D)
        return D

    def hold(self, pose, s, grip_at, axis, pole, iters=6, palm=None):
        """The arm solved so the hand's grip landmark is at ``grip_at`` with its line along ``axis``, the elbow
        toward ``pole`` (two bones; the hand by the least turn from the forearm). Returns the wrist's bend (deg)."""
        import clips
        r = self.rest
        g, a = self.grip[s]
        axis = unit(axis)
        if palm is not None:
            # the hand's turn given whole: its grip line on ``axis``, its palm's normal toward ``palm``
            n0 = np.asarray(clips.hand_frame(r, s)[0])
            D_fixed = clips.frame(axis, palm) @ clips.frame(a, n0).T
        D_h = clips.between(a, axis) if palm is None else D_fixed
        bend = 0.0
        for _ in range(iters):
            pose.solve()
            sh = pose.P["upperarm_" + s]
            wrist = grip_at - D_h @ (g - r.head["hand_" + s])
            d = wrist - sh
            l1, l2 = self.l1[s], self.l2[s]
            dist = float(np.clip(np.linalg.norm(d), abs(l1 - l2) + 1e-4, (l1 + l2) * 0.999))
            dn = unit(d)
            pv = unit(np.asarray(pole) - dn * float(np.asarray(pole) @ dn))
            aa = (l1 * l1 + dist * dist - l2 * l2) / (2.0 * dist)
            hh = math.sqrt(max(0.0, l1 * l1 - aa * aa))
            elbow = sh + dn * aa + pv * hh
            end = sh + dn * dist
            d0u = unit(r.head["lowerarm_" + s] - r.head["upperarm_" + s])
            d0l = unit(r.head["hand_" + s] - r.head["lowerarm_" + s])
            p0 = self.pole0[s]
            D_up = clips.frame(elbow - sh, pv) @ clips.frame(d0u, p0).T
            D_lo = clips.frame(end - elbow, pv) @ clips.frame(d0l, p0).T
            pose.set_abs("upperarm_" + s, D_up)
            pose.set_abs("lowerarm_" + s, D_lo)
            D_h = clips.between(D_lo @ a, axis) @ D_lo if palm is None else D_fixed
            pose.set_abs("hand_" + s, D_h)
            fore = D_lo @ d0l
            hand_long = D_h @ d0l
            bend = math.degrees(math.acos(float(np.clip(fore @ hand_long, -1.0, 1.0))))
        pose.solve()
        return bend


def idle_pose(holder, rest, f, frames, walk=False, gait=None, phi=0.0):
    import clips
    if walk:
        pose = br.brute_gait_pose(gait, phi)
    else:
        pose = br.brute_idle(rest, f, frames)
    # the club arm: hanging a little forward and out, the hand turned so the trunk runs down to its root ball
    ph = 2.0 * math.pi * f / max(frames, 1)
    sw = (-6.0 - (gait.g["arm_swing_deg"] * 0.35 * math.sin(phi) if walk else 1.5 * math.sin(ph)))
    clips.set_arm(pose, "r", sw, 16.0 if not walk else 20.0, out_deg=br.ARM_OUT_DEG + 4.0)
    pose.solve()
    if not walk and CLUB_V is not None:
        club_at_rest(holder, pose)
    else:
        holder.orient_hand(pose, "r", unit(CLUB_WALK_DIR if walk else CLUB_IDLE_DIR))
    return pose


def overhead_pose(holder, rest, f, frames):
    """The trunk raised in both hands over and behind the head: the right hand at the handle's end, the left above
    it; the back arched, the chest up, the left foot forward, the knees bent."""
    import clips
    t = clips.smooth(f / float(frames))
    pose = clips.Pose(rest)
    pose.offset = np.array([0.0, 0.03 * t, 0.0])
    pose.set_rel("pelvis", clips.rot(clips.X, -5.0 * t) @ clips.rot(clips.Z, 4.0 * t))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        pose.set_rel(b, clips.rot(clips.X, -8.0 * k * t) @ clips.rot(clips.Z, 3.0 * k * t))
    pose.set_rel("clavicle_l", clips.rot(clips.Y, -10.0 * t))
    pose.set_rel("clavicle_r", clips.rot(clips.Y, 10.0 * t))
    pose.set_rel("neck_01", clips.rot(clips.X, 6.0 * t))
    pose.set_rel("head", clips.rot(clips.X, 6.0 * t))
    feet = {"l": (clips.rest_ankle(rest, "l") + np.array([0.06, -0.34, 0.0]) * t, 8.0 * t, 0.0, 0.0),
            "r": (clips.rest_ankle(rest, "r") + np.array([-0.08, 0.30, 0.0]) * t, -22.0 * t, 0.0, 0.0)}
    clips.set_legs(pose, feet, drop=0.03 + 0.14 * t)
    pose.solve()
    head = pose.P["head"]
    # the grips from the idle's hold to over the head: the right fist above and behind the crown, the trunk down
    # the back behind the right shoulder; the left fist on the trunk a hand above the right
    idle = idle_pose(holder, rest, 0, 1)
    g0, a0 = holder.grip_posed(idle, "r")
    g1 = head + np.array([-0.06, 0.10, 0.30])
    a1 = unit(np.array([-0.22, 0.45, -0.86]))
    g = g0 * (1.0 - t) + g1 * t
    a = unit(a0 * (1.0 - t) + a1 * t)
    holder.hold(pose, "r", g, a, pole=(-0.6, 0.15, -0.3) if t > 0.3 else (-0.6, 0.4, -0.6))
    gl = g + a * (0.62 / F)
    w = clips.smooth((f / float(frames) - 0.15) / 0.5)
    if w > 0.0:
        pose.solve()
        idle_l = pose.P["upperarm_l"] + np.array([0.12, -0.10, -0.55])
        holder.hold(pose, "l", idle_l * (1.0 - w) + gl * w, a, pole=(0.7, 0.2, -0.4))
    else:
        clips.set_arm(pose, "l", -4.0, 22.0, out_deg=br.ARM_OUT_DEG)
    return pose


def charge_pose(holder, rest, f, frames):
    """The shoulder charge's lean: the trunk pitched forward and turned so the left shoulder leads, the left arm
    tucked across the chest, the head down behind the shoulder; a long stride, the left foot forward; the trunk
    trailing low in the right hand."""
    import clips
    t = clips.smooth(f / float(frames))
    # A3, the anticipation: the weight rocks back onto the planted rear foot through the middle of the wind-up
    # before it is thrown forward over the leading shoulder
    rock = math.sin(math.pi * min(1.0, max(0.0, (f / float(frames) - 0.2) / 0.7)))
    pose = clips.Pose(rest)
    pose.offset = np.array([0.0, -0.10 * t + 0.07 * rock, 0.0])
    # A3: a heavier, taller lean (pelvis 14 -> 10 degrees, the knees' drop 0.25 -> 0.14): the telegraph reads as a
    # braced shoulder, not a crouch
    pose.set_rel("pelvis", clips.rot(clips.X, 10.0 * t - 5.0 * rock) @ clips.rot(clips.Z, -12.0 * t))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        pose.set_rel(b, clips.rot(clips.X, 6.0 * k * t) @ clips.rot(clips.Z, -9.0 * k * t)
                     @ clips.rot(clips.Y, 3.0 * k * t))
    pose.set_rel("clavicle_l", clips.rot(clips.Z, -6.0 * t) @ clips.rot(clips.Y, 6.0 * t))
    pose.set_rel("neck_01", clips.rot(clips.X, -10.0 * t) @ clips.rot(clips.Z, 12.0 * t))
    pose.set_rel("head", clips.rot(clips.X, -12.0 * t) @ clips.rot(clips.Z, 8.0 * t))
    feet = {"l": (clips.rest_ankle(rest, "l") + np.array([0.04, -0.52, 0.0]) * t, 12.0 * t, 0.0, 0.0),
            "r": (clips.rest_ankle(rest, "r") + np.array([-0.04, 0.56, 0.04]) * t, -16.0 * t, 18.0 * t, -28.0 * t)}
    clips.set_legs(pose, feet, drop=0.04 + 0.10 * t + 0.04 * rock)
    pose.solve()
    # the left arm braced: the fist before the chest, the elbow out and down, the forearm across
    shl, shr = pose.P["upperarm_l"], pose.P["upperarm_r"]
    chest = 0.5 * (shl + shr) + np.array([0.0, -0.30, -0.30])
    hang = shl + np.array([0.12, -0.10, -0.55])
    clips.set_arm(pose, "l", -4.0, 22.0, out_deg=br.ARM_OUT_DEG)
    holder.hold(pose, "l", hang * (1.0 - t) + chest * t, unit(np.array([-1.0, -0.15, 0.25])),
                pole=(0.8, -0.2, -0.5), palm=(0.0, 1.0, 0.0))
    # the right arm low and back beside the hip, the trunk trailing behind and down
    pose.solve()
    hip = pose.P["thigh_r"]
    g0, _a0 = holder.grip_posed(idle_pose(holder, rest, 0, 1), "r")
    g1 = hip + np.array([-0.30, 0.42, -0.05])
    a = unit(np.asarray(CLUB_IDLE_DIR) * (1.0 - t) + np.array([-0.30, 0.62, -0.72]) * t)
    holder.hold(pose, "r", g0 * (1.0 - t) + g1 * t, a, pole=(-0.6, 0.3, -0.4) if t > 0.2 else (-0.6, 0.6, -0.2))
    return pose


def throw_pose(holder, rest, f, frames):
    """The boulder throw's wind-up: the boulder in the left hand drawn back high over the left shoulder, the trunk
    turned away (to the left) and leaning back on the left leg, the right arm with the trunk forward for balance."""
    import clips
    t = clips.smooth(f / float(frames))
    pose = clips.Pose(rest)
    pose.offset = np.array([0.0, 0.08 * t, 0.0])
    pose.set_rel("pelvis", clips.rot(clips.Z, 16.0 * t) @ clips.rot(clips.X, -4.0 * t))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.1)):
        pose.set_rel(b, clips.rot(clips.Z, 10.0 * k * t) @ clips.rot(clips.X, -6.0 * k * t)
                     @ clips.rot(clips.Y, 4.0 * k * t))
    pose.set_rel("neck_01", clips.rot(clips.Z, -16.0 * t))
    pose.set_rel("head", clips.rot(clips.Z, -14.0 * t) @ clips.rot(clips.X, 4.0 * t))
    pose.set_rel("clavicle_l", clips.rot(clips.Y, -12.0 * t))
    feet = {"l": (clips.rest_ankle(rest, "l") + np.array([0.10, 0.30, 0.0]) * t, 24.0 * t, 0.0, 0.0),
            "r": (clips.rest_ankle(rest, "r") + np.array([-0.06, -0.36, 0.0]) * t, -6.0 * t, 0.0, 0.0)}
    clips.set_legs(pose, feet, drop=0.03 + 0.16 * t)
    pose.solve()
    sh = pose.P["upperarm_l"]
    head = pose.P["head"]
    # the boulder's hand up and back over the shoulder, the palm toward the target (forward)
    low = sh + np.array([0.14, -0.10, -0.62])
    high = sh + np.array([0.28, 0.34, 0.34])
    g = low * (1.0 - t) + high * t
    axis = unit(np.array([-1.0, -0.15, 0.0]) * t + np.array([0.0, -1.0, 0.0]) * (1.0 - t))
    palm = unit(np.array([0.15, 0.25, 0.95]) * t + np.array([-1.0, 0.0, 0.0]) * (1.0 - t))
    holder.hold(pose, "l", g, axis, pole=(1.0, -0.25, -0.25 - 0.5 * (1.0 - t)), palm=palm)
    del head
    clips.set_arm(pose, "r", -12.0 * t - 4.0, 24.0 + 6.0 * t, out_deg=br.ARM_OUT_DEG + 2.0)
    pose.solve()
    holder.orient_hand(pose, "r", unit(np.asarray(CLUB_IDLE_DIR) * (1.0 - t) + np.array([-0.35, -0.75, -0.55]) * t))
    return pose


def roar_pose(holder, rest, f, frames):
    import clips
    pose = clips.roar_pose(rest, f, frames)
    pose.solve()
    t = f / float(frames)
    e = clips.smooth(t / 0.3) * (1.0 - 0.5 * clips.smooth((t - 0.82) / 0.18))
    holder.orient_hand(pose, "r", unit(np.asarray(CLUB_IDLE_DIR) * (1.0 - e) + np.array([-0.85, -0.2, -0.45]) * e))
    return pose


def make_poses(person):
    import clips
    rest = person.rest
    clips.configure(step_m=STEP_M / F)
    clips.GAITS.update(br.BRUTE_GAITS)
    clips.GAITS.update(STONE_GAITS)
    holder = Holder(person)
    gaits = {"walk": clips.Gait(rest, "stone_walk", CLIP_FRAMES["walk"]),
             "run": clips.Gait(rest, "stone_run", CLIP_FRAMES["run"])}
    poses = {}
    bends = {}
    for name, frames in CLIP_FRAMES.items():
        if name not in A1_CLIPS:
            continue
        keys = []
        for f in range(frames + 1):
            phi = 2.0 * math.pi * f / frames
            if name == "idle":
                p = idle_pose(holder, rest, f, frames)
            elif name in ("walk", "run"):
                p = idle_pose(holder, rest, f, frames, walk=True, gait=gaits[name], phi=phi)
            elif name == "roar":
                p = roar_pose(holder, rest, f, frames)
            elif name == "overhead":
                p = overhead_pose(holder, rest, f, frames)
            elif name == "charge":
                p = charge_pose(holder, rest, f, frames)
            else:
                p = throw_pose(holder, rest, f, frames)
            keys.append(p.solve())
        poses[name] = keys
    poses.update(mv.make(holder, rest, gaits))   # A2
    # the overhead's two hands on the trunk: the left grip's distance from the trunk's line (a check)
    last = poses["overhead"][-1]
    gr, ar = holder.grip_posed(last, "r")
    gl, _al = holder.grip_posed(last, "l")
    q = gl - gr
    off = float(np.linalg.norm(q - ar * float(q @ ar))) * F
    bends["overhead_left_off_trunk_m"] = r6(off)
    bends["crown_m"] = crowns(person, poses)
    bends["kneel"] = kneel_frames(person, poses)   # A4
    return poses, gaits, holder, bends


# A4: the bones the gameplay body's hurtboxes and lock anchors follow when he is down on his knee
KNEEL_BONES = ("pelvis", "spine_02", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l", "lowerarm_r",
               "thigh_l", "thigh_r", "calf_l", "calf_r")
# kit armature space (+x his left, -y his front, z up) -> his actor's space (his left -X, up +Y, his front -Z)
TO_ACTOR = np.array([[-1.0, 0.0, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0, 0.0]])


def kneel_frames(person, poses):
    """A4: each of KNEEL_BONES's head and frame in the idle's first key and in the kneel's last (the pose held
    while he is down), in his actor's space and real metres, and the crown there: tools/builders/titans.gd moves
    each hurtbox and lock anchor with its bone (TitanEnemy follows the kneel)."""
    rest = person.rest
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = TO_ACTOR @ p.D[b] @ TO_ACTOR.T
            d[key] = {"head": [r6(x) for x in TO_ACTOR @ p.P[b] * F], "basis": [r6(x) for x in R.ravel()]}
        out[key + "_crown_m"] = r6(float((p.P["head"] + p.D["head"] @ local)[2]) * F)
    knee = poses["kneel"][-1].P["calf_r"]
    out["knee_on_ground_m"] = r6(float(knee[2]) * F)
    out["pelvis_m"] = r6(float(poses["kneel"][-1].P["pelvis"][2]) * F)
    return out


# A3: the clips whose every frame is a standing pose (the idle, the gaits, the roar) and the wind-ups whose peak (the
# telegraph's pose, held while the giant reads it) carry his head near his full height
CROWN_CLIPS = ("idle", "walk", "run", "roar")
CROWN_PEAKS = ("overhead", "charge", "throw")


def crowns(person, poses):
    """A3: the crown's height (real m) over each standing clip's frames [lowest, highest] and at each wind-up's peak:
    the top of the head at rest carried by the head bone."""
    rest = person.rest
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]

    def crown(p):
        return float((p.P["head"] + p.D["head"] @ local)[2]) * F
    out = {}
    for c in CROWN_CLIPS:
        hs = [crown(p) for p in poses[c]]
        out[c] = [r6(min(hs)), r6(max(hs))]
    for c in CROWN_PEAKS:
        out[c + "_peak"] = r6(crown(poses[c][-1]))
    return out


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


def key_actions(arm, trk):
    import bpy
    from mathutils import Quaternion, Vector
    for name in CLIP_FRAMES:
        act = bpy.data.actions.new(name)
        arm.animation_data_create()
        arm.animation_data.action = act
        for f, k in enumerate(trk[name]):
            for pb in arm.pose.bones:
                pb.rotation_quaternion = Quaternion()
                pb.location = (0.0, 0.0, 0.0)
            for b in pr.BONES:
                pb = arm.pose.bones[b]
                pb.rotation_quaternion = Quaternion(k["basis"][b])
                pb.keyframe_insert("rotation_quaternion", frame=f)
                if b == "pelvis":
                    pb.location = Vector(k["loc"]["pelvis"].tolist())
                    pb.keyframe_insert("location", frame=f)
        act.use_fake_user = True
        track = arm.animation_data.nla_tracks.new()
        track.name = name
        track.strips.new(name, 0, act)
        arm.animation_data.action = None


def export_clips(path, arm, coll, trk):
    import bpy
    import people_body as pbody
    from mathutils import Quaternion
    rest = pbody.rest_matrices(arm)
    verts, faces = [], []
    for i, b in enumerate(pr.BONES):
        h = rest[b][:3, 3]
        verts += [tuple(h), tuple(h + np.array([0.002, 0.0, 0.0])), tuple(h + np.array([0.0, 0.0, 0.002]))]
        faces.append((3 * i, 3 * i + 1, 3 * i + 2))
    me = bpy.data.meshes.new("ClipsAnchor")
    me.from_pydata(verts, [], faces)
    me.update()
    anchor = bpy.data.objects.new("ClipsAnchor", me)
    coll.objects.link(anchor)
    for i, b in enumerate(pr.BONES):
        anchor.vertex_groups.new(name=b).add([3 * i, 3 * i + 1, 3 * i + 2], 1.0, "REPLACE")
    anchor.parent = arm
    anchor.modifiers.new("Armature", "ARMATURE").object = arm
    key_actions(arm, trk)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        o.select_set(False)
    arm.select_set(True)
    anchor.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False, export_reset_pose_bones=True,
                              export_morph=False, export_materials="NONE", export_yup=True,
                              export_def_bones=False, export_leaf_bone=False, export_extras=False,
                              export_cameras=False, export_lights=False, export_rest_position_armature=True)
    bpy.data.objects.remove(anchor, do_unlink=True)


# ======================================================================================================================
# the build
# ======================================================================================================================
def stone_hands():
    """The people's rest hands with LEFT_CURLS for his free hand (people_body.hand_rest_spec wrapped: this
    interpreter only)."""
    import people_body as pbody
    orig = pbody.hand_rest_spec
    if getattr(orig, "_stoneback", False):
        return

    def spec(rest, side):
        if side != "l":
            return orig(rest, side)
        saved = dict(pr.HAND_CURLS)
        pr.HAND_CURLS.update(LEFT_CURLS)
        try:
            spec_l = orig(rest, side)
            # the thumb laid down along the curled index (its rest turn left it standing out across the body)
            import clips
            _n, across = clips.hand_frame(rest, "l")
            along = clips.unit(0.5 * (rest.head["index_01_l"] + rest.head["pinky_01_l"]) - rest.head["hand_l"])
            to = clips.unit(along * 0.7 - across * 0.3)
            for k, deg in (("thumb_01_l", LEFT_THUMB_DEG[0]), ("thumb_02_l", LEFT_THUMB_DEG[1]),
                           ("thumb_03_l", LEFT_THUMB_DEG[2])):
                spec_l[k] = [("toward", tuple(to), deg)]
            return spec_l
        finally:
            pr.HAND_CURLS.clear()
            pr.HAND_CURLS.update(saved)
    spec._stoneback = True
    pbody.hand_rest_spec = spec


def kilt_panels(p, person, seed=71):
    """The kilt (a giant's skirt piece, design scale) cut into torn hide panels (see KILT_PANELS): each panel's rows
    shortened to its own slanted length, the slits between the panels open from the hem, every other panel a little
    out, the hanging rows weighted to the thigh behind their panel. Returns the new piece."""
    import giant_garment as gg
    import people_outfit as po
    S = person.S
    J = person.bd.joints
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    z_top = (hip - gg.KILT_CUT_BELOW_HIP) * S
    V = p.V.copy()
    z_hem = float(V[:, 2].min())
    hang = np.clip((z_top - V[:, 2]) / max(z_top - z_hem, 1e-9), 0.0, 1.0)
    cy = float(V[hang > 0.0, 1].mean())
    th = np.arctan2(V[:, 0], -(V[:, 1] - cy))                        # 0 at the front, + toward his left
    n = KILT_PANELS
    pos = (th % (2.0 * math.pi)) / (2.0 * math.pi / n)               # (a slit at the front and the back)
    k = np.floor(pos).astype(np.int64) % n
    local = pos - np.floor(pos)
    rng = np.random.default_rng(seed)
    length = rng.uniform(KILT_HANG[0], KILT_HANG[1], n)
    slant = rng.uniform(-KILT_SLANT, KILT_SLANT, n)
    frac = np.clip(length[k] + slant[k] * (local - 0.5), 0.55, 1.0)
    V[:, 2] = np.where(hang > 0.0, z_top - (z_top - V[:, 2]) * frac, V[:, 2])
    out = (k % 2 == 1) & (hang > 0.0)
    rad = V[:, :2] - np.array([0.0, cy])
    rad /= np.maximum(np.linalg.norm(rad, axis=1, keepdims=True), 1e-9)
    V[out, :2] += rad[out] * (KILT_LAYER_M * S * _sstep(hang[out], 0.0, 0.2))[:, None]
    # the slits: the triangles across two panels, from the hem up KILT_SLIT of the hang
    T = p.T
    kt = k[T]
    across = (kt[:, 0] != kt[:, 1]) | (kt[:, 1] != kt[:, 2])
    keep = ~(across & (hang[T].mean(axis=1) > 1.0 - KILT_SLIT))
    # the rows follow the thigh behind their panel (its middle's side)
    mid_x = np.sin((k + 0.5) * 2.0 * math.pi / n)
    a = 0.9 * _sstep(hang, 0.0, 0.45) * _sstep(np.abs(mid_x), 0.05, 0.3)
    g = {b: w * (1.0 - a) for b, w in p.groups.items()}
    for side, sel in (("thigh_l", mid_x > 0.0), ("thigh_r", mid_x <= 0.0)):
        g[side] = g.get(side, np.zeros(len(V))) + a * sel
    q = po.Piece(p.name, V, T[keep], p.mat[keep], g, p.attach, None if p.uv is None else p.uv[keep])
    return po.compact_piece(q)


def club_at_rest(holder, pose):
    """The club hand turned (between CLUB_STEEP and CLUB_FLAT) so the club's lowest point lies CLUB_REST_M over the
    ground in this pose: its root ball rests on the ground in every key of the idle. Returns the line."""
    h0 = holder.rest.head["hand_r"]
    a, b = 0.0, 1.0
    steep, flat = np.asarray(CLUB_STEEP), np.asarray(CLUB_FLAT)
    for _ in range(14):
        m_ = 0.5 * (a + b)
        holder.orient_hand(pose, "r", unit(steep * (1.0 - m_) + flat * m_))
        pose.solve()
        low = float(((CLUB_V - h0) @ pose.D["hand_r"].T + pose.P["hand_r"])[:, 2].min()) * F
        if low < CLUB_REST_M:
            a = m_
        else:
            b = m_
    line = unit(steep * (1.0 - b) + flat * b)
    holder.orient_hand(pose, "r", line)
    return line


def export_glb(path, objects):
    """people_outfit.export with the pieces' vertex colours (the attribute "Color": the plates' iron bands, the club's
    earth; the body has none)."""
    import bpy
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
                              export_vertex_color="NAME", export_vertex_color_name="Color",
                              export_all_vertex_colors=False, export_yup=True, export_tangents=True,
                              export_extras=False, export_def_bones=False, export_leaf_bone=False,
                              export_rest_position_armature=True, export_cameras=False, export_lights=False)


def grip_radius(person):
    """The right fist's opening about its grip line (design m): the hand's nearest vertices to the line."""
    g, ax = person.grip["r"]
    ax = unit(ax)
    V = person.body_V()
    hand = (person.bd.masks["m_hand"] > 0.5) & (np.sign(V[:, 0]) < 0)
    Q = V[hand] - g
    along = Q @ ax
    d = np.linalg.norm(Q - np.outer(along, ax), axis=1)
    near = np.abs(along) < 0.03 * person.S / 1.0
    return float(np.percentile(d[near], 4.0)) if near.sum() > 8 else float(np.percentile(d, 4.0))


def build(out_dir, work_dir):
    import bpy
    import giant_body as gb
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
    from scipy.spatial import cKDTree
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    times = {}
    import giant_garment as gg
    stone_hands()
    gg.BRAIES.update(BELT)
    p0 = br.brute_person(VARIANT)
    if not p0.bd.masks:
        p0.bd.compute_masks(p0.weights)
    times["body"] = round(time.time() - t0, 1)
    _x, faces, _fuv = p0.bd.group("body")
    body_T = po.triangulate(faces)
    p0.normals = po.vertex_normals(p0.body_V(), body_T)
    p0.normals_h = p0.normals
    p0.grip_radius = grip_radius(p0)
    # ---- the outfit and the shared mesh
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, OUTFIT)
    garments = [po.garment_piece(w0, gid, p0, OUTFIT_MATERIAL[gid], kd0) for gid in order]
    garments = [kilt_panels(g, p0) if gid == "kilt" else g for g, gid in zip(garments, order)]
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
        raise SystemExit("stoneback: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses (the shackles' chains hang in the idle; the club's line in the idle set by its root ball)
    club = club_piece(p0)
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(STONE_GAITS)
    global CLUB_V, CLUB_IDLE_DIR
    CLUB_V = club.V
    h_ = Holder(p0)
    p_ = br.brute_idle(p0.rest, 0, CLIP_FRAMES["idle"])
    clips_mod.set_arm(p_, "r", -6.0, 16.0, out_deg=br.ARM_OUT_DEG + 4.0)
    p_.solve()
    CLUB_IDLE_DIR = tuple(float(x) for x in club_at_rest(h_, p_))
    poses, gaits, _holder, checks = make_poses(p0)
    checks["club_idle_dir"] = [r6(x) for x in CLUB_IDLE_DIR]
    # ---- the pieces
    groups53 = pr.fold_weights(p0.groups53())
    pieces = {}
    for i, name in enumerate(PLATE_ORDER):
        pieces[name] = plate_piece(p0, name, body_T, groups53, 401 + 7 * i)
    pieces["shackles"] = shackles_piece(p0, poses["idle"][0])
    pieces["club"] = club
    pieces["boulder"] = boulder_piece(p0)
    for name in ("shackles", "club", "boulder"):
        p = pieces[name]
        if p.tris() > GEAR_BUDGET[name]:
            raise SystemExit("stoneback: %s has %d triangles, over %d" % (name, p.tris(), GEAR_BUDGET[name]))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the bake and the hide (the plates' footprints: the skin under them)
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(KIND, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras)])
    under = np.zeros(N)
    for name in PLATE_ORDER:
        under = np.maximum(under, np.clip(plate_footprint(p0, name) * 1.3, 0.0, 1.0))
    ukd = cKDTree(p0.bd.verts[:N])

    def under_fn(P):
        d, i = ukd.query(P, k=4)
        wgt = 1.0 / np.maximum(d, 1e-5)
        return (under[i] * wgt).sum(axis=1) / wgt.sum(axis=1)
    look = {"masks": lambda P: masks_at(P, ukd, p0.bd.masks), "scars": face_scars(p0)}
    repaint(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, under_fn, hide_tris=np.isin(Lmat, [MATS.index("leather"),
            MATS.index("dark_leather")]), look=look)
    detail_files = detail_textures(out_dir)
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("stoneback_body")
    stone = bpy.data.materials.new("stoneback_stone")
    bark = bpy.data.materials.new("stoneback_bark")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    rest_h = pbody.rest_matrices(arm)["hand_r"]
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in PLATE_ORDER + ("shackles", "club", "boulder"):
        p = pieces[name]
        m = mat if name == "shackles" else (bark if name == "club" else stone)
        o = br.skinned_object(name, p, arm, coll, m, F)
        rgba = getattr(p, "rgba", None)
        if rgba is not None:
            ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
            ca.data.foreach_set("color", np.asarray(rgba, np.float32).ravel())
        if name.startswith("plate_") or name == "boulder":
            o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        info_p = {"node": name, "tris": p.tris(), "material": "body" if name == "shackles" else
                  ("bark" if name == "club" else "stone")}
        info_p.update(getattr(p, "facts", {}) or {})
        if name == "club":
            H = rest_h
            info_p["head_local"] = [r6(x) for x in (H[:3, :3].T @ (p.head_point * F - H[:3, 3]))]
        if name in WEAK_POINTS:
            info_p["weak_point"] = WEAK_POINTS[name]
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
    export_glb(path, exported)
    height = float(mesh.V[:, 2].max()) * F
    full_h = max(height, max(float(pieces[n].V[:, 2].max()) * F for n in PLATE_ORDER))
    # the idle's club: its root ball's lowest point over the ground (a check: it rests on it)
    club_V = pieces["club"].V
    Hh = rest["hand_r"]
    Gi = G["hand_r"]
    posed_club = (Gi[:3, :3] @ (Hh[:3, :3].T @ (club_V * F - Hh[:3, 3]).T)).T + Gi[:3, 3]
    checks["idle_club_lowest_m"] = r6(float(posed_club[:, 2].min()))
    b53 = p0.rig.data.bones
    knuckle = (np.asarray(b53["middle_01_l"].head_local) - np.asarray(b53["hand_l"].head_local)) * F
    reach = (b53["upperarm_l"].length + b53["lowerarm_l"].length) * F + float(np.linalg.norm(knuckle))
    info = {"kind": KIND, "height_m": HEIGHT_M, "export_scale": r6(F), "times": times, "tris_max": TRIS,
            "bake": bake_info, "outfit": list(order),
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget), "culled_skin": culled_skin},
            "variants": {KIND: {"index": 0, "tris": mesh.tris(), "verts": int(len(mesh.V)), "height_m": r6(height),
                                "height_with_plates_m": r6(full_h), "game_height_m": HEIGHT_M,
                                "game_scale": r6(HEIGHT_M / height), "pieces": [p.name for p in extras],
                                "joints": {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES},
                                "reach_m": r6(reach), "far": {"node": KIND + "_far", "tris": int(len(Tf))}}},
            "pieces": piece_info, "plates": list(PLATE_ORDER), "weak_points": dict(WEAK_POINTS),
            "detail": detail_files, "detail_tile_m": {"stone": STONE_TILE_M, "bark": list(BARK_TILE_M)},
            "checks": checks, "used_by": ["tools/character_sheet.gd sheet d (A1; no encounter yet)"]}
    for sd in ("l", "r"):
        g, ax = p0.grip[sd]
        H = rest["hand_" + sd]
        info["variants"][KIND]["grip_local_" + sd] = [r6(x) for x in (H[:3, :3].T @ (g * F - H[:3, 3]))]
        info["variants"][KIND]["grip_axis_" + sd] = [r6(x) for x in (H[:3, :3].T @ ax)]
    info["glb_bytes"] = os.path.getsize(path)
    # the clips
    worst = 0.0
    for name in ("walk", "idle", "overhead", "throw"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            Gk = pbody.fk(rest, pbody.parents_of(arm), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "hand_l", "head", "pelvis"):
                worst = max(worst, float(np.linalg.norm(Gk[b][:3, 3] - poses[name][kk].P[b] * F)))
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("stoneback clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    import clips
    export_clips(os.path.join(out_dir, KIND + "_clips.glb"), arm, coll, trk)
    info["clips"] = {"fps": clips.FPS, "step_m": r6(STEP_M), "conversion_error_m": r6(worst),
                     "clips": {n: {"frames": f, "loop": n in CLIP_LOOPS, "bones": len(pr.BONES), "partial": False,
                                   "windup": n in WINDUPS} for n, f in CLIP_FRAMES.items()},
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
        raise SystemExit("usage: stoneback.py stoneback <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
