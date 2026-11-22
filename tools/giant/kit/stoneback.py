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

KIND = "stoneback"
HEIGHT_M = 16.8                    # 55 ft
DESIGN = pr.DESIGN_HEIGHT_M
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.44 * HEIGHT_M           # the brutes' stride for their height (the ogre's 1.5 m at 3.4 m)
TRIS = 9000                        # the body and the kilt (as a brute)
MARGIN_TRIS = 60
FAR_TRIS = 300
OUTFIT = ("kilt", "belt")
OUTFIT_MATERIAL = {"kilt": "leather", "belt": "dark_leather"}   # a hide kilt, a dark belt (no palette band)

# ---- the body ------------------------------------------------------------------------------------------------------
STONE_FACE = {"eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -0.8,
              "forehead/forehead-trans-backward-forward": 0.5, "nose/nose-scale-horiz-decr-incr": 0.8,
              "nose/nose-flaring-decr-incr": 0.6, "nose/nose-volume-decr-incr": 0.5, "nose/nose-hump-decr-incr": 0.6,
              "chin/chin-width-decr-incr": 1.0, "chin/chin-prominent-decr-incr": 0.6, "chin/chin-bones-decr-incr": 1.0,
              "head/head-square": 0.9, "mouth/mouth-scale-horiz-decr-incr": 0.5, "cheek/cheek-bones-decr-incr": 0.6,
              "eyes/eye-scale-decr-incr": -0.4, "mouth/mouth-lowerlip-volume-decr-incr": 0.3}
STONE_PROP = dict(legs=0.97, torso=1.02, neck=-0.025, head=0.84, arms=1.04, hands=1.14, shoulders=-0.050,
                  deltoids=0.0, trapezius=-0.034, thighs=0.08)
STONE_SHAPE = dict(hunch_deg=14.0, head_back_deg=11.0, jaw=(0.22, 0.010, 0.008), underbite_m=0.004, brow_m=0.020,
                   brow_band_m=0.014, nose=(0.0, 0.0), ears=0.0, hands=1.08, feet=1.12, gut_m=0.018, tusks=False)
VARIANT = dict(name=KIND, macro=br._macro(46, 1.0, 0.82, african=0.45, asian=0.1, caucasian=0.45),
               face=br._face(1.5, **STONE_FACE), prop=STONE_PROP, shape=STONE_SHAPE, height_m=HEIGHT_M)

# ---- the plates (real metres) --------------------------------------------------------------------------------------
# name: (thickness, gap over the skin, bevel width, the chisel's facet cell, decimation budget)
PLATES = {
    "plate_shoulder_l": (0.62, 0.05, 0.55, 1.50, 560),
    "plate_shoulder_r": (0.62, 0.05, 0.55, 1.50, 560),
    "plate_back": (0.70, 0.05, 0.65, 1.80, 680),
    "plate_brow": (0.34, 0.03, 0.26, 0.75, 320),
    "plate_forearm_l": (0.34, 0.04, 0.30, 1.00, 280),
    "plate_forearm_r": (0.34, 0.04, 0.30, 1.00, 280),
    "plate_shin_l": (0.38, 0.04, 0.32, 1.10, 300),
    "plate_shin_r": (0.38, 0.04, 0.32, 1.10, 300),
}
PLATE_SUBDIVIDE = 1                # the body's patch split once before the slab is shaped (room for the facets)
OUTLINE_NOISE = (7.0, 0.32)        # the outline's chips: the noise's scale (a human metre) and its reach
FACET_TILT = 0.12                  # a facet's plane tilted this much off its points' own (radians, about)
FACET_LIFT = 0.10                  # and raised or sunk this much (of the thickness)
FACET_PRESS = 0.85                 # the share of the way the points go onto their facet's plane
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
CLUB = dict(handle_m=1.0, length_m=6.9, root_r=1.5, roots=11, segs=14, rings=34)
BOULDER_R = 1.4
GEAR_BUDGET = {"shackles": 1800, "club": 2600, "boulder": 360}

CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "roar": 24, "overhead": 30, "charge": 24, "throw": 30}
CLIP_LOOPS = ("idle", "walk", "run")
WINDUPS = ("overhead", "charge", "throw")
# the trunk's line from the right fist (armature space: +x his left, -y his front, +z up) in the stance and the walk
CLUB_IDLE_DIR = (-0.30, -0.52, -0.80)
CLUB_WALK_DIR = (-0.28, -0.70, -0.66)


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
        up_out = (nb[:, 2] + 0.9 * s * nb[:, 0] + 0.3 * nb[:, 1]) > -0.25
        arm_t = ((V - sh) @ unit(el - sh)) / float(np.linalg.norm(el - sh))
        w = (1.0 - _sstep(d, 0.85, 1.05)) * side * up_out * (1.0 - _sstep(arm_t, 0.46, 0.58))
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
        eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
        hd = J["joint-head"]
        w = (m["m_head"] > 0.6) * _sstep(z, eye[2] + 0.018, eye[2] + 0.026) * (m["m_ears"] < 0.05)
        w *= (1.0 - _sstep(y, hd[1] + 0.03, hd[1] + 0.06))                   # the front and the top, not the nape
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


def plate_piece(person, name, body_T, groups, seed):
    """A plate (see the module's notes) as a people_outfit Piece (design scale), its corner UVs on the stone."""
    import people_bake as pbk
    import people_outfit as po
    thick, gap, bevel, cell, budget = (v / F if i < 4 else v for i, v in enumerate(PLATES[name]))
    S = person.S
    Vb = person.body_V()
    Nb = person.normals
    w = plate_footprint(person, name)
    # a chipped outline: the footprint's edge moved in and out by noise
    rough = pbk.fbm(person.bd.verts[:N], OUTLINE_NOISE[0], seed) - 0.5
    keep = (w + OUTLINE_NOISE[1] * rough) > 0.5
    Tk = body_T[keep[body_T].all(axis=1)]
    Tk = largest_component(Tk, N)
    used = np.unique(Tk)
    remap = -np.ones(N, np.int64)
    remap[used] = np.arange(len(used))
    T = remap[Tk]
    P = Vb[used]
    Nn = Nb[used]
    for _ in range(PLATE_SUBDIVIDE):
        P, Nn, used, T = subdivide(P, Nn, used, T)
    n = len(P)
    bnd = np.zeros(n, bool)
    u, c = edges_of(T)
    bnd[u[c == 1].ravel()] = True
    dist = boundary_distance(P, T, bnd)
    prof = _sstep(dist, 0.0, bevel)
    # the slab's top: the skin pushed out, smoothed into a slab (the body's muscles gone), never nearer the skin than
    # its edge's thickness
    base = P + Nn * gap
    top = base + Nn * (thick * (0.30 + 0.70 * prof))[:, None]
    top = taubin(top, T, 40, bnd)
    out_n = np.einsum("ij,ij->i", top - base, Nn)
    least = thick * (0.30 + 0.62 * prof)
    top = top + Nn * np.maximum(0.0, least - out_n)[:, None]
    # the chisel: flat facets, one tilted plane a cell (Voronoi cells over the slab)
    rng = np.random.default_rng(seed)
    lo, hi = top.min(axis=0), top.max(axis=0)
    k = max(4, int(np.prod(np.maximum(hi - lo, cell)) / cell ** 3 * 1.6))
    seeds = top[rng.choice(n, size=min(k, n), replace=False)]
    from scipy.spatial import cKDTree
    dd, ci = cKDTree(seeds).query(top, k=2)
    # each cell's points pressed toward the plane that fits them (a flat, quarried face), that plane tilted a
    # little and raised or sunk; the seams between faces a narrow groove; the slab never thinner than its edge's
    lab = ci[:, 0]
    flat = top.copy()
    for k_ in range(len(seeds)):
        sel = lab == k_
        if sel.sum() < 4:
            continue
        c_ = top[sel].mean(axis=0)
        _u, _s, Vt = np.linalg.svd(top[sel] - c_)
        pn = Vt[2] if float(Vt[2] @ Nn[sel].mean(axis=0)) > 0 else -Vt[2]
        pn = unit(pn + rng.normal(0.0, FACET_TILT, 3))
        c_ = c_ + pn * thick * rng.uniform(-FACET_LIFT, FACET_LIFT)
        off = (top[sel] - c_) @ pn
        flat[sel] = top[sel] - np.outer(off, pn)
    seam = 1.0 - _sstep(dd[:, 1] - dd[:, 0], 0.0, 0.05 * cell)
    flat -= Nn * (thick * 0.08 * seam)[:, None]
    top = top + (flat - top) * (FACET_PRESS * prof)[:, None]
    top += Nn * (thick * 0.04 * (pbk.fbm(top / S, 30.0, seed + 3) - 0.5) * prof)[:, None]
    out_n = np.einsum("ij,ij->i", top - base, Nn)
    top = top + Nn * np.maximum(0.0, thick * (0.25 + 0.45 * prof) - out_n)[:, None]
    # the rim: from the top's open edge down under the skin
    be = boundary_edges(T)
    rim_v = P[np.unique(be)] - Nn[np.unique(be)] * (RIM_SINK_M / F)
    rmap = -np.ones(n, np.int64)
    ub = np.unique(be)
    rmap[ub] = n + np.arange(len(ub))
    Vall = np.concatenate([top, rim_v])
    rim_T = []
    for a, b in be.tolist():
        rim_T += [(b, a, rmap[a]), (b, rmap[a], rmap[b])]
    Tall = np.concatenate([T, np.asarray(rim_T, np.int64).reshape(-1, 3)])
    src = np.concatenate([used, used[ub]])           # each vertex's body vertex (its weights)
    # the winding: out from the body (the triangles' normals along the skin's)
    nrm = np.cross(Vall[Tall[:, 1]] - Vall[Tall[:, 0]], Vall[Tall[:, 2]] - Vall[Tall[:, 0]])
    if float(np.einsum("ij,ij->i", nrm[:len(T)], Nn[T].mean(axis=1)).sum()) < 0:
        Tall = Tall[:, ::-1]
    mat = np.full(len(Tall), po.MATS.index("metal"))
    Vd, Td, _md, _uv = po.decimate(Vall, Tall, mat, budget, "_plate_" + name, symmetric=False)
    from scipy.spatial import cKDTree as KD
    near = KD(Vall).query(Vd)[1]
    g = {b: wv[src[near]] for b, wv in groups.items()}
    g = stiffen(g, Td, len(Vd), 4)
    centre = Vd.mean(axis=0)
    piece = po.Piece(name, Vd, Td, np.full(len(Td), po.MATS.index("metal")), g, src[near])
    piece.uv = box_uv(Vd, Td, STONE_TILE_M / F)
    piece.facts = {"tris": int(len(Td)), "body_vertices": int(n), "thick_m": r6(PLATES[name][0]),
                   "centre_m": [r6(v * F) for v in centre]}
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
    for k in range(CLUB["roots"]):
        az = 2.0 * math.pi * (k + rng.uniform(-0.3, 0.3)) / CLUB["roots"]
        d = math.cos(az) * ref + math.sin(az) * w_
        big_root = k % 3 != 2
        reach = R * (rng.uniform(0.85, 1.3) if big_root else rng.uniform(0.45, 0.7))
        fwd = rng.uniform(0.5, 1.1)
        twist = rng.uniform(-0.35, 0.35)
        pts = []
        for t in np.linspace(0.0, 1.0, 7):
            side = np.cross(ax, d) * twist * t * R
            pts.append(centre + ax * (rng.uniform(-0.15, 0.1) * R + fwd * R * t * t)
                       + d * (0.55 * R + reach * t) + side + ax * 0.06 * R * math.sin(6.0 * t + k))
        rr = np.array([0.40, 0.30, 0.22, 0.16, 0.11, 0.07, 0.03]) * R * (1.0 if big_root else 0.6)
        Vr, Tr, _r2, _a2 = tube(np.asarray(pts), rr, 6, close=(False, True))
        parts.append((Vr, Tr, "root", None, None))
    # three sawn-off branch stumps along the trunk
    for k, (st, az) in enumerate(((0.32, 0.6), (0.55, 2.7), (0.7, 4.6))):
        d = math.cos(az) * ref + math.sin(az) * w_
        c0 = g + ax * (st * L)
        r0 = float(np.interp(st * L, s, base_r))
        pts = [c0 + d * r0 * 0.4, c0 + d * (r0 + 0.35 / F) + ax * 0.12 / F, c0 + d * (r0 + 0.75 / F) + ax * 0.28 / F]
        Vr, Tr, _r2, _a2 = tube(np.asarray(pts), np.array([0.45, 0.36, 0.30]) * r0, 7)
        parts.append((Vr, Tr, "stump", None, None))
    Vs, Ts, UV = [], [], []
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
            uv = planar_uv(V, T, ax if what in ("ball", "root") else nrm, tile_u) + rng.uniform(0, 1, 2)
        Ts.append(T + sum(len(v) for v in Vs))
        Vs.append(V)
        UV.append(uv)
    V, T, uv = np.concatenate(Vs), np.concatenate(Ts), np.concatenate(UV)
    mat = np.full(len(T), po.MATS.index("leather"))
    p = po.Piece("club", V, T, mat, rigid(len(V), "hand_r"), np.full(len(V), -1))
    p.uv = uv
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
    c = g + unit(n) * R * 0.92
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
    Vb = c + U * (R * r)[:, None] * np.array([1.0, 0.9, 0.82])
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

            def layers(Q, vv):
                big = pbk.fbm(Q, 1.6, 201, 4)
                mid = pbk.fbm(Q, 3.2, 203, 4)
                fine = pbk.vnoise(Q, 14.0, 205)
                grain = pbk.vnoise(Q, 38.0, 207)
                strata = 0.5 + 0.5 * np.sin(2.0 * math.pi * (2.0 * vv + 0.7 * big))
                pits = np.clip((fine - 0.80) / 0.12, 0.0, 1.0)
                return big, mid, fine, grain, strata, pits

            def hfun(uu, vv):
                _big, mid, fine, grain, strata, pits = layers(_torus(uu, vv), vv)
                return 0.55 * mid + 0.18 * fine + 0.06 * grain - 0.25 * pits + 0.10 * strata
            big, mid, fine, grain, strata, pits = layers(P, v)
            # a weathered grey-ochre stone: strata of the quarried bed, ochre stains, pale lichen flecks, pits
            ochre = np.clip((pbk.fbm(P, 2.0, 209, 3) - 0.46) / 0.18, 0.0, 1.0)
            lichen = np.clip((pbk.vnoise(P, 9.0, 211) - 0.82) / 0.08, 0.0, 1.0) * np.clip((mid - 0.5) / 0.1, 0, 1)
            grey = np.array([0.33, 0.325, 0.31])
            och = np.array([0.42, 0.36, 0.28])
            col = grey[None, :] * (0.90 + 0.18 * (big - 0.5) + 0.10 * (mid - 0.5) + 0.05 * (grain - 0.5)
                                   + 0.05 * (strata - 0.5))[:, None]
            col = col * (1.0 - 0.45 * ochre[:, None]) + och[None, :] * (0.92 + 0.16 * mid)[:, None] * 0.45 * ochre[:, None]
            col = col * (1.0 - 0.45 * lichen[:, None]) + np.array([0.60, 0.62, 0.52])[None, :] * 0.45 * lichen[:, None]
            col *= (1.0 - 0.30 * pits)[:, None]
            height = hfun(u, v)
            amp = 0.9
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


def hide(P, Nrm, under):
    """(albedo multiplier (n, 3), height field (n,)) of his skin at points P (human m, rest), normals Nrm; ``under``
    (n,) 0..1: under a plate (paler, scarred: the plate's weight wore the skin)."""
    import people_bake as pbk
    big = pbk.fbm(P, 5.0, 301)
    mid = pbk.fbm(P, 16.0, 303)
    fine = pbk.vnoise(P, 80.0, 307)
    z = P[:, 2]
    hz = z / max(float(z.max()), 1e-6)
    # (the base kept well under 1: the bake's skin is near white, and the pale skin under a plate is brighter still)
    grey = HIDE_BASE * (1.0 + 0.18 * (big - 0.5) + 0.11 * (mid - 0.5) + 0.06 * (fine - 0.5))
    back = np.clip(Nrm[:, 1], 0.0, 1.0)
    grey *= 1.0 - 0.06 * back * _sstep(hz, 0.5, 0.8)                  # sun-darkened shoulders and back
    mul = np.repeat(grey[:, None], 3, axis=1)
    # quarry dust: a pale grey crust on the feet, the shins and the forearms (blue raised against the warm skin)
    dust_w = np.clip(1.0 - hz / 0.34, 0.0, 1.0) ** 0.8
    dust = np.clip((dust_w * 0.9 + 0.8 * (pbk.fbm(P, 7.0, 311) - 0.5) - 0.25) / 0.25, 0.0, 1.0)
    dust_col = np.array([1.18, 1.16, 1.30])
    mul = mul * (1.0 - 0.6 * dust[:, None]) + dust_col[None, :] * grey[:, None] * 0.6 * dust[:, None]
    # under a plate: paler, a little pinker, scored with old welts and pressure scars
    welt = np.abs(np.sin(P[:, 0] * 140.0 + 9.0 * pbk.fbm(P, 6.0, 313) + P[:, 2] * 60.0))
    welt = 1.0 - _sstep(welt, 0.0, 0.16)
    scar = np.clip(welt * (pbk.vnoise(P, 22.0, 317) > 0.45), 0.0, 1.0)
    pale = np.array([1.36, 1.20, 1.14])
    u = np.clip(under, 0.0, 1.0)[:, None]
    mul = mul * (1.0 - u) + pale[None, :] * grey[:, None] * u
    mul = mul * (1.0 - 0.6 * scar[:, None] * u) + np.array([1.60, 1.12, 1.05])[None, :] * 0.6 * scar[:, None] * u
    height = 0.30 * mid + 0.18 * fine + 0.55 * scar * np.clip(under, 0, 1) + 0.15 * dust
    return mul, height


def repaint(out_dir, LV, LT, Luv, tan, sgn, nor, S, under_fn, hide_tris=None):
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
        mul, height = hide(P[skin], Nl[skin], under)
        if img == "albedo":
            alb[ys[skin], xs[skin]] = np.clip(alb[ys[skin], xs[skin]] * mul, 0.0, 1.0)
        else:
            e = 0.004
            Tl = np.einsum("nk,nkj->nj", b, tan[t])[skin]
            Bl = np.cross(Nl[skin], Tl) * np.sign(sgn[t[skin], 0])[:, None]
            Ps = P[skin]
            g1 = (hide(Ps + Tl * e, Nl[skin], under)[1] - height) / e
            g2 = (hide(Ps + Bl * e, Nl[skin], under)[1] - height) / e
            amp = 0.0040
            n0 = nrm[ys[skin], xs[skin]]
            n1 = n0 - amp * np.stack([g1, g2, np.zeros_like(g1)], axis=1)
            n1 /= np.maximum(np.linalg.norm(n1, axis=1, keepdims=True), 1e-9)
            nrm[ys[skin], xs[skin]] = n1
    rows = int(round((1.0 - pr.TILE_SIZE) * pr.ORM_PX))
    garment = orm[:rows, :, 2] != skin_b
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
    pose = clips.Pose(rest)
    pose.offset = np.array([0.0, -0.10 * t, 0.0])
    pose.set_rel("pelvis", clips.rot(clips.X, 14.0 * t) @ clips.rot(clips.Z, -12.0 * t))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        pose.set_rel(b, clips.rot(clips.X, 6.0 * k * t) @ clips.rot(clips.Z, -9.0 * k * t)
                     @ clips.rot(clips.Y, 3.0 * k * t))
    pose.set_rel("clavicle_l", clips.rot(clips.Z, -6.0 * t) @ clips.rot(clips.Y, 6.0 * t))
    pose.set_rel("neck_01", clips.rot(clips.X, -10.0 * t) @ clips.rot(clips.Z, 12.0 * t))
    pose.set_rel("head", clips.rot(clips.X, -12.0 * t) @ clips.rot(clips.Z, 8.0 * t))
    feet = {"l": (clips.rest_ankle(rest, "l") + np.array([0.04, -0.52, 0.0]) * t, 12.0 * t, 0.0, 0.0),
            "r": (clips.rest_ankle(rest, "r") + np.array([-0.04, 0.50, 0.03]) * t, -16.0 * t, 14.0 * t, -20.0 * t)}
    clips.set_legs(pose, feet, drop=0.05 + 0.20 * t)
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
    holder = Holder(person)
    gaits = {"walk": clips.Gait(rest, "brute_walk", CLIP_FRAMES["walk"]),
             "run": clips.Gait(rest, "brute_run", CLIP_FRAMES["run"])}
    poses = {}
    bends = {}
    for name, frames in CLIP_FRAMES.items():
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
    # the overhead's two hands on the trunk: the left grip's distance from the trunk's line (a check)
    last = poses["overhead"][-1]
    gr, ar = holder.grip_posed(last, "r")
    gl, _al = holder.grip_posed(last, "l")
    q = gl - gr
    off = float(np.linalg.norm(q - ar * float(q @ ar))) * F
    bends["overhead_left_off_trunk_m"] = r6(off)
    return poses, gaits, holder, bends


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
    # ---- the clips' poses (the shackles' chains hang in the idle)
    poses, gaits, _holder, checks = make_poses(p0)
    # ---- the pieces
    groups53 = pr.fold_weights(p0.groups53())
    pieces = {}
    for i, name in enumerate(PLATE_ORDER):
        pieces[name] = plate_piece(p0, name, body_T, groups53, 401 + 7 * i)
    pieces["shackles"] = shackles_piece(p0, poses["idle"][0])
    pieces["club"] = club_piece(p0)
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
    repaint(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, under_fn, hide_tris=(Lmat == MATS.index("leather")))
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
    po.export(path, exported)
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
