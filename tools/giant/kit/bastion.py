"""The Broken Warden (C2): the Bastion Titan, the fourth signature titan - an original giant warden of the old kings'
toll road 22.4 m (73.5 ft) tall, bound into fortification, as an asset (``build_people.py --bastion``).

The giant kings set him at their toll-gate on the road into the Aldmere March; when the gate fell he took up its walls
and wore them. Underneath he is a living body - the people's CC0 human with MakeHuman's macros, ``giant_body.proportioned``
with a table of his own and ``brute.reshape`` - so he stands and moves as a heavy old soldier, not a tower on legs:
broad in the shoulder and the neck, long in the arm, deep-chested, upright. His skin is Stoneback's weathered hide
(``stoneback.hide``: grime, old sun and stone dust), and down his right side an old wound: a broken, ill-knit seam
from the armpit to the hip, its edges puckered, under the iron that holds it (the "broken" of his name). Over it, each
its own skinned mesh on the people's 23 bones:

  shield        the wall-shield on his left hand: a section of the old gatehouse wall - dressed ashlar in six courses
                with an arrow slit, two merlons on its top edge, its back the gate's iron-strapped oak and the bar he
                grips it by, iron bound round its edges (rigid to the left hand: it is the hand's)
  pauldron_l    the battlement pauldron: a quarried slab over the left shoulder (Stoneback's slab code) crowned with
                three merlons along its outer edge, banded on
  pauldron_r    the right shoulder's slab split through and clamped back together with iron staples (armour only)
  back          the portcullis: a slab of wall on his back with the gate's iron grille bolted over it, its spikes
                hanging below
  helm          a tower's cap: a stone helm over the brow and crown with four small merlons round it and an iron nasal
  greave_l, greave_r
                mason's greaves: dressed stone down each shin, banded
  mend          the mend of his broken side: iron bands round the right of his ribs and rows of staples across the old
                seam (its break opens the wound)
  bar           the gate's bar: a squared oak beam 13 m long, iron-shod at both ends and banded, his club (rigid to the
                right hand); two-handed once the shield is gone
  bastion_far   the idle's first key, decimated

The stone is Stoneback's tileable stone (``stoneback_stone_albedo/normal.png``), the bar's oak the Ogre King's
(``ogre_king_wood_*``): no texture of his own beyond his atlas. Iron is vertex alpha 0, untextured matte colours 0.5
(stone_plate.gdshader).

Clips on his skeleton (``bastion_moves.py``): dormant (bound into his wall), idle, walk, run, idle2, walk2, run2 (the
shield gone: the bar two-handed), roar, bash, hammer, sweep, charge, charge_run, stomp, reel, guardbreak, rearm,
smash2, sweep2, kneel, rise, death.

``python bastion.py bastion <out dir> <work dir>`` writes bastion.glb, bastion_clips.glb, the atlas
(bastion_albedo.png 512 px, _normal.png, _orm.png 256 px) and bastion_info.json.
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

KIND = "bastion"
HEIGHT_M = 22.4                    # 73.5 ft: over a stage-6 giant (18.90 m) by a head and more; the toll-keep's walls
DESIGN = pr.DESIGN_HEIGHT_M        # (14 m) reach his chest
F = HEIGHT_M / DESIGN              # design metres -> the file's metres
N = mh.N_BODY_VERTS
STEP_M = 0.30 * HEIGHT_M           # a soldier's measured step under the shield's weight (6.7 m)
TRIS = 9000
MARGIN_TRIS = 60
FAR_TRIS = 320
OUTFIT = ("kilt", "loincloth", "belt")
OUTFIT_MATERIAL = {"kilt": "leather", "loincloth": "dark_leather", "belt": "dark_leather"}

# ---- the body ------------------------------------------------------------------------------------------------------
# an old soldier's face: square and heavy-jawed, the brow low and level, the nose broken flat at the bridge, the
# cheekbones broad, deep lines from the nose to the mouth, the mouth set straight
WARDEN_FACE = {"head/head-square": 1.0, "head/head-age-decr-incr": 0.9, "chin/chin-width-decr-incr": 0.9,
               "chin/chin-prominent-decr-incr": 0.5, "chin/chin-bones-decr-incr": 0.8,
               "eyebrows/eyebrows-trans-backward-forward": 0.8, "eyebrows/eyebrows-trans-down-up": -0.6,
               "eyebrows/eyebrows-angle-down-up": -0.2, "forehead/forehead-trans-backward-forward": 0.4,
               "nose/nose-scale-horiz-decr-incr": 0.6, "nose/nose-scale-vert-decr-incr": -0.3,
               "nose/nose-volume-decr-incr": 0.4, "nose/nose-flaring-decr-incr": 0.4,
               "cheek/cheek-bones-decr-incr": 0.8, "mouth/mouth-laugh-lines-in-out": 0.8,
               "mouth/mouth-angles-down-up": -0.3, "mouth/mouth-scale-horiz-decr-incr": 0.3,
               "eyes/eye-scale-decr-incr": -0.35, "eyes/eye-bag-decr-incr": 0.5,
               "asym/asym-nose-2-l": 0.55, "asym/asym-jaw-1-l": 0.25}
# broad in the shoulder and the neck, long-armed, the head small on a thick neck (it reads larger), the legs a soldier's
WARDEN_PROP = dict(legs=1.00, torso=1.03, neck=-0.010, head=0.80, arms=1.06, hands=1.12, shoulders=0.020,
                   deltoids=0.012, trapezius=0.010, thighs=0.06)
WARDEN_SHAPE = dict(hunch_deg=4.0, head_back_deg=3.0, jaw=(0.30, 0.014, 0.012), underbite_m=0.002, brow_m=0.026,
                    brow_band_m=0.014, nose=(0.0, 0.0), ears=0.0, hands=1.08, feet=1.12, gut_m=0.010, tusks=False)
VARIANT = dict(name=KIND, macro=br._macro(58, 1.0, 0.72, african=0.30, asian=0.20, caucasian=0.50),
               face=br._face(1.35, **WARDEN_FACE), prop=WARDEN_PROP, shape=WARDEN_SHAPE, height_m=HEIGHT_M)
WARDEN_GAITS = {
    "bastion_walk": dict(br.BRUTE_GAITS["brute_walk"], top_drop=0.035, min_drop=0.02, lean_deg=3.0,
                         pelvis_pitch_deg=2.5, roll_deg=4.5, sway=0.08, arm_swing_deg=8.0, heel_rocker=0.14),
    "bastion_run": dict(br.BRUTE_GAITS["brute_run"], top_drop=0.08, min_drop=0.06, lean_deg=8.0,
                        pelvis_pitch_deg=5.0),
}

# ---- the colours (linear vertex colours; stone_plate.gdshader: alpha 1 the texture, 0 iron, 0.5 a matte colour) ----
IRON_RGBA = (0.150, 0.140, 0.130, 0.0)
RUST_RGBA = (0.200, 0.135, 0.095, 0.0)
OAK_RGBA = (0.30, 0.215, 0.140, 0.5)               # the shield's back: dark, iron-stained oak (matte)
MORTAR_RGBA = (0.62, 0.60, 0.56, 1.0)              # the stone texture paler and flatter in the joints
STONE_SHADES = (1.0, 0.93, 0.86, 1.06)             # dressed blocks a shade apart
WOOD_RGBA = (1.0, 1.0, 1.0, 1.0)                   # the bar's oak texture as it is
STONE_TILE_M = 3.4                 # Stoneback's stone texture repeats every this many metres
WOOD_TILE_M = 2.6                  # the Ogre King's oak's repeat along the bar
SHARP_DEG = 26.0

# ---- the wall-shield (real metres; in the idle it stands upright before his left side, its face to his front) ------
SHIELD = dict(width=5.8, height=13.4, thick=1.05, courses=5, merlon=(1.35, 1.3), slit=(0.40, 2.2),
              grip_up=-2.8, yaw_deg=30.0, standoff=0.45, out_share=0.5, band=(0.30, 0.16))
# ---- the bar (real metres): a squared oak beam gripped GRIP_SHARE from its butt
BAR = dict(length=13.0, side=1.05, grip_share=0.27, bands=(0.06, 0.42, 0.74, 0.96), shoe=0.9, segs=4)

# ---- the plates: Stoneback's slab code on his body, with what makes them this warden's -----------------------------
# piece: (Stoneback's footprint, (thickness, gap, chamfer, cut faces, decimation budget) real metres)
SLABS = {
    "pauldron_l": ("plate_shoulder_l", (0.62, 0.06, 0.16, 2, 520)),
    "pauldron_r": ("plate_shoulder_r", (0.50, 0.06, 0.14, 2, 460)),
    "back": ("plate_back", (0.70, 0.06, 0.22, 2, 560)),
    "helm": ("plate_brow", (0.30, 0.05, 0.10, 9, 340)),
    "greave_l": ("plate_shin_l", (0.55, 0.05, 0.13, 3, 300)),
    "greave_r": ("plate_shin_r", (0.55, 0.05, 0.13, 3, 300)),
}
PLATE_ORDER = ("shield", "pauldron_l", "back", "helm", "mend", "greave_l", "greave_r")
GEAR = ("pauldron_r", "bar")
# the regions the fight package names (data/enemies/bastion.json): the plate -> its region
WEAK_POINTS = {"shield": "shield", "pauldron_l": "shoulder_l", "back": "back", "helm": "head", "mend": "flank_r",
               "greave_l": "shin_l", "greave_r": "shin_r"}
# the main bone of each piece (the rig's break: where its debris flies from)
PIECE_BONE = {"shield": "hand_l", "pauldron_l": "upperarm_l", "pauldron_r": "upperarm_r", "back": "spine_03",
              "helm": "head", "mend": "spine_02", "greave_l": "calf_l", "greave_r": "calf_r", "bar": "hand_r"}
MERLONS = dict(pauldron=3, helm=4)
GRILLE = dict(cols=6, rows=4, bar_m=0.22, lift_m=0.30, spike_m=1.1)
STAPLES = dict(rows=7, span_m=1.5, wire_m=0.16)
GEAR_BUDGET = {"shield": 2200, "pauldron_l": 900, "pauldron_r": 760, "back": 1500, "helm": 700, "mend": 900,
               "greave_l": 420, "greave_r": 420, "bar": 600}
CLIP_LOOPS = ("idle", "walk", "run", "idle2", "walk2", "run2", "dormant", "charge_run")


def log(*a):
    print("[bastion]", *a, flush=True)


r6 = br.r6
unit = sb.unit
_sstep = br._sstep


# ======================================================================================================================
# geometry helpers (design scale)
# ======================================================================================================================
def box(c, u, v, n, hu, hv, hn, taper=0.0):
    """A box (8 corners, 12 triangles, wound outward) centred at ``c`` with half sizes along the unit axes u, v, n; its
    +n face shrunk by ``taper`` (a share of hu and hv: a dressed block's bevel, a merlon's weathering)."""
    c = np.asarray(c, np.float64)
    u, v, n = (np.asarray(x, np.float64) for x in (u, v, n))
    V = []
    for sn in (-1.0, 1.0):
        k = 1.0 - (taper if sn > 0 else 0.0)
        for su, sv in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            V.append(c + u * su * hu * k + v * sv * hv * k + n * sn * hn)
    V = np.asarray(V)
    T = np.array([(0, 2, 1), (0, 3, 2), (4, 5, 6), (4, 6, 7), (0, 1, 5), (0, 5, 4), (1, 2, 6), (1, 6, 5),
                  (2, 3, 7), (2, 7, 6), (3, 0, 4), (3, 4, 7)], np.int64)
    return V, sb.outward(V, T, c)


def merge(parts, tile):
    """[(V, T, rgba (n,4) or one rgba, corner uv (m,3,2) or None)] -> V, T, rgba, uv (a box map at ``tile`` design m
    where None)."""
    Vs, Ts, Cs, UVs = [], [], [], []
    off = 0
    for V, T, C, uv in parts:
        V = np.asarray(V, np.float64)
        T = np.asarray(T, np.int64)
        C = np.asarray(C, np.float64)
        if C.ndim == 1:
            C = np.tile(C, (len(V), 1))
        Ts.append(T + off)
        Vs.append(V)
        Cs.append(C)
        UVs.append(sb.box_uv(V, T, tile) if uv is None else np.asarray(uv, np.float64))
        off += len(V)
    return np.concatenate(Vs), np.concatenate(Ts), np.concatenate(Cs), np.concatenate(UVs)


def piece_of(name, V, T, rgba, uv, groups, src=None):
    import people_outfit as po
    p = po.Piece(name, V, T, np.full(len(T), po.MATS.index("metal")), groups,
                 np.full(len(V), -1) if src is None else src)
    p.uv = uv
    p.rgba = rgba
    return p


def to_rest(person, pose, bone, V):
    """Points posed by ``pose`` (design) carried back into the rest pose by ``bone``'s motion: a rigid piece made where
    it is seen (the shield before him in the idle) and skinned to the bone."""
    r = person.rest
    return r.head[bone] + (np.asarray(V) - pose.P[bone]) @ pose.D[bone]


def nearest_groups(groups, src_V, V, kd=None):
    """Each point of V the weights of the nearest of ``src_V`` (a part laid on a skinned piece moves with it)."""
    from scipy.spatial import cKDTree
    kd = kd or cKDTree(src_V)
    i = kd.query(V)[1]
    return {b: w[i] for b, w in groups.items()}


# ======================================================================================================================
# the wall-shield (built in the idle's first key, carried back to the rest pose by the left hand)
# ======================================================================================================================
def shield_frame(holder, idle):
    """The shield's frame in the idle (design): (the grip point, across (+ toward his left), up, out (his front: the
    face's normal)). The grip's line runs across the shield's back; the face turned SHIELD["yaw_deg"] to his left."""
    g, a = holder.grip_posed(idle, "l")
    yaw = math.radians(SHIELD["yaw_deg"])
    out = unit(np.array([math.sin(yaw), -math.cos(yaw), 0.0]))
    up = np.array([0.0, 0.0, 1.0])
    across = unit(np.cross(up, out))
    if across[0] < 0.0:
        across = -across
    return g, across, up, out


def shield_piece(person, holder, idle):
    """The wall-shield (SHIELD): a block of the old gatehouse wall - its face six courses of dressed ashlar (each block
    its own box, set a little proud of the bed and of each other: the joints read), an arrow slit through the third
    course, two merlons on its top edge with the crenel between them; its back the gate's oak in vertical boards with
    two iron straps across and the grip-bar; an iron frame round its edges. Rigid to the left hand."""
    rng = np.random.default_rng(701)
    g, ac, up, out = shield_frame(holder, idle)
    W, H, D = SHIELD["width"] / F, SHIELD["height"] / F, SHIELD["thick"] / F
    share = SHIELD["out_share"]
    # its centre: before the knuckles by the standoff, the grip at grip_up of its height, more of it out to his left
    c = g + out * (SHIELD["standoff"] / F + D * 0.5) + ac * (W * (share - 0.5)) + up * (SHIELD["grip_up"] / F)
    parts = []
    # the bed: the wall's core behind the blocks
    Vb, Tb = box(c - out * D * 0.12, ac, up, out, W * 0.5, H * 0.5, D * 0.38)
    parts.append((Vb, Tb, np.asarray(MORTAR_RGBA), None))
    # the courses of blocks on its face (the slit's block left out, the merlons above the top course)
    courses = SHIELD["courses"]
    ch = H / courses
    face_n = out
    slit_w, slit_h = SHIELD["slit"][0] / F, SHIELD["slit"][1] / F
    for i in range(courses):
        zc = -H * 0.5 + ch * (i + 0.5)
        n_blocks = 2 if i % 2 == 0 else 3
        widths = rng.uniform(0.8, 1.2, n_blocks)
        widths = widths / widths.sum() * W
        x0 = -W * 0.5
        for k in range(n_blocks):
            bw = widths[k]
            xc = x0 + bw * 0.5
            x0 += bw
            if i == 3 and k == 1:
                # the arrow slit: two narrow blocks either side of a dark slot
                for sgn in (-1.0, 1.0):
                    hw = (bw - slit_w) * 0.25
                    cc = c + ac * (xc + sgn * (slit_w * 0.5 + hw)) + up * zc + face_n * D * 0.36
                    V, T = box(cc, ac, up, face_n, hw * 0.96, ch * 0.47, D * 0.14, taper=0.05)
                    parts.append((V, T, np.asarray((*(np.ones(3) * STONE_SHADES[k % 4]), 1.0)), None))
                cc = c + ac * xc + up * zc + face_n * D * 0.26
                V, T = box(cc, ac, up, face_n, slit_w * 0.5, slit_h * 0.5, D * 0.05)
                parts.append((V, T, np.asarray((0.04, 0.035, 0.03, 0.5)), None))
                continue
            proud = rng.uniform(0.0, 0.05) / F
            tilt = rng.normal(0.0, 0.015)
            n_k = unit(face_n + up * tilt + ac * rng.normal(0.0, 0.015))
            cc = c + ac * xc + up * zc + face_n * (D * 0.36 + proud)
            V, T = box(cc, ac, up, n_k, bw * 0.47, ch * 0.465, D * 0.14, taper=0.06)
            sh = STONE_SHADES[(i * 3 + k) % 4] * rng.uniform(0.94, 1.04)
            parts.append((V, T, np.asarray((sh, sh * 0.99, sh * 0.97, 1.0)), None))
    # the merlons: two blocks standing on the top edge, the crenel between them
    mw, mh_ = SHIELD["merlon"][0] / F, SHIELD["merlon"][1] / F
    for sgn in (-1.0, 1.0):
        cc = c + ac * sgn * (W * 0.5 - mw * 0.75) + up * (H * 0.5 + mh_ * 0.5) - out * D * 0.05
        V, T = box(cc, ac, up, out, mw * 0.5, mh_ * 0.5, D * 0.44, taper=0.0)
        parts.append((V, T, np.asarray((0.95, 0.94, 0.92, 1.0)), None))
        cap_c = cc + up * (mh_ * 0.5 + 0.08 / F)
        V, T = box(cap_c, ac, out, up, mw * 0.56, D * 0.48, 0.08 / F)
        parts.append((V, T, np.asarray((0.88, 0.87, 0.85, 1.0)), None))
    # the back: the gate's oak boards, vertical, a little proud of the bed, two iron straps across, the grip-bar
    back_c = c - out * D * 0.5
    boards = 7
    for k in range(boards):
        xc = -W * 0.5 + W * (k + 0.5) / boards
        V, T = box(back_c + ac * xc - out * 0.04 / F, ac, up, -out, W / boards * 0.48, H * 0.49, 0.10 / F)
        shade = 0.88 + 0.12 * ((k * 5) % 3) / 2.0
        parts.append((V, T, np.asarray((OAK_RGBA[0] * shade, OAK_RGBA[1] * shade, OAK_RGBA[2] * shade, 0.5)), None))
    bw_, bt_ = SHIELD["band"][0] / F, SHIELD["band"][1] / F
    for zc in (-H * 0.32, H * 0.30):
        V, T = box(back_c + up * zc - out * 0.18 / F, ac, up, -out, W * 0.5, bw_, bt_)
        parts.append((V, T, np.asarray(IRON_RGBA), None))
    # the grip-bar on the back, at the hand (its line the grip's): two posts and the bar
    gb_len = 1.6 / F
    for sgn in (-1.0, 1.0):
        V, T = box(g + ac * sgn * gb_len * 0.55 + out * (SHIELD["standoff"] / F) * 0.5, ac, up, out, 0.12 / F,
                   0.14 / F, SHIELD["standoff"] / F * 0.5)
        parts.append((V, T, np.asarray(IRON_RGBA), None))
    V, T = box(g, ac, up, out, gb_len * 0.62, 0.11 / F, 0.11 / F)
    parts.append((V, T, np.asarray(RUST_RGBA), None))
    # the iron frame round its edges (the sides and the foot; the top is the merlons')
    ft = 0.20 / F
    for sgn in (-1.0, 1.0):
        V, T = box(c + ac * sgn * (W * 0.5 + ft * 0.4), ac, up, out, ft * 0.6, H * 0.5, D * 0.52)
        parts.append((V, T, np.asarray(IRON_RGBA), None))
    V, T = box(c - up * (H * 0.5 + ft * 0.4), ac, up, out, W * 0.52, ft * 0.6, D * 0.52)
    parts.append((V, T, np.asarray(IRON_RGBA), None))
    # rivets on the frame's face (small iron studs down the sides)
    for sgn in (-1.0, 1.0):
        for k in range(7):
            zc = -H * 0.45 + H * 0.9 * k / 6.0
            V, T = box(c + ac * sgn * (W * 0.5 + ft * 0.4) + up * zc + out * (D * 0.52 + 0.05 / F), ac, up, out,
                       0.14 / F, 0.14 / F, 0.06 / F, taper=0.4)
            parts.append((V, T, np.asarray(IRON_RGBA), None))
    Vi, Ti, Ci, UVi = merge(parts, STONE_TILE_M / F)
    Vr = to_rest(person, idle, "hand_l", Vi)
    p = piece_of("shield", Vr, Ti, Ci, UVi, {"hand_l": np.ones(len(Vr))})
    p.facts = {"tris": int(len(Ti)), "width_m": r6(SHIELD["width"]), "height_m": r6(SHIELD["height"]),
               "top_m_idle": r6(float(Vi[:, 2].max()) * F), "bottom_m_idle": r6(float(Vi[:, 2].min()) * F),
               "centre_m_idle": [r6(x * F) for x in c]}
    p.idle_V = Vi
    return p


# ======================================================================================================================
# the bar (rigid to the right hand, along its grip)
# ======================================================================================================================
def bar_piece(person):
    """The gate's bar: a squared oak beam (BAR) along the right fist's grip line, the fist BAR["grip_share"] of its
    length from the butt; iron shoes over both ends and iron bands round it, studs on the striking end."""
    g, ax = person.grip["r"]
    ax = unit(ax)
    L, s = BAR["length"] / F, BAR["side"] / F
    ref = unit(np.cross(ax, [0.0, 0.0, 1.0]) if abs(ax[2]) < 0.9 else np.cross(ax, [1.0, 0.0, 0.0]))
    w = np.cross(ax, ref)
    butt = -L * BAR["grip_share"]
    tip = L * (1.0 - BAR["grip_share"])
    parts = []
    # the beam (a box tapering a little toward the butt), its oak along its length
    V, T = box(g + ax * (butt + tip) * 0.5, ref, w, ax, s * 0.5, s * 0.5, L * 0.5)
    along = (V - g) @ ax
    k = np.clip((along - butt) / L, 0.0, 1.0)
    V = g + np.outer(along, ax) + ((V - g) - np.outer(along, ax)) * (0.82 + 0.18 * k)[:, None]
    C = V[T]
    uv = np.zeros((len(T), 3, 2))
    nrm = np.cross(V[T[:, 1]] - V[T[:, 0]], V[T[:, 2]] - V[T[:, 0]])
    for i in range(len(T)):
        n = unit(nrm[i])
        across = ref if abs(float(n @ w)) > 0.5 else w
        uv[i] = np.stack([(C[i] - g) @ across / (WOOD_TILE_M / F) * 2.0, (C[i] - g) @ ax / (WOOD_TILE_M / F)], -1)
    parts.append((V, T, np.asarray(WOOD_RGBA), uv))
    # the shoes over both ends and the bands
    for at, ln in ((butt + BAR["shoe"] / F * 0.5, BAR["shoe"] / F), (tip - BAR["shoe"] / F * 0.5, BAR["shoe"] / F)):
        V, T = box(g + ax * at, ref, w, ax, s * 0.56, s * 0.56, ln * 0.5)
        parts.append((V, T, np.asarray(IRON_RGBA), None))
    for f in BAR["bands"]:
        at = butt + L * f
        V, T = box(g + ax * at, ref, w, ax, s * 0.54, s * 0.54, 0.16 / F)
        parts.append((V, T, np.asarray(RUST_RGBA if f > 0.5 else IRON_RGBA), None))
    # studs on the striking end: square bosses on each face
    for k in range(3):
        at = tip - L * (0.08 + 0.09 * k)
        for d in (ref, -ref, w, -w):
            V, T = box(g + ax * at + d * s * 0.52, unit(np.cross(d, ax)), ax, d, 0.16 / F, 0.16 / F, 0.10 / F,
                       taper=0.45)
            parts.append((V, T, np.asarray(IRON_RGBA), None))
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    p = piece_of("bar", Vm, Tm, Cm, UVm, {"hand_r": np.ones(len(Vm))})
    p.facts = {"tris": int(len(Tm)), "length_m": r6(BAR["length"]), "grip_share": BAR["grip_share"]}
    p.tip_point = g + ax * tip
    p.butt_point = g + ax * butt
    return p


# ======================================================================================================================
# the plates on his body: Stoneback's slabs, with the battlements, the grille, the staples
# ======================================================================================================================
def slab(person, name, body_T, groups, seed):
    """Stoneback's plate (sb.plate_piece) on this body, by its footprint (SLABS: the plate it borrows, its sizes)."""
    src, spec = SLABS[name]
    sb.PLATES[src] = spec
    p = sb.plate_piece(person, src, body_T, groups, seed)
    p.name = name
    return p


def top_points(p, n_dir):
    """The slab's stone points (not its iron) and their outward score along ``n_dir`` (design)."""
    stone = np.asarray(p.rgba)[:, 3] > 0.5
    V = np.asarray(p.V)[stone]
    return V, V @ unit(n_dir)


def add_parts(p, parts, tile):
    """The parts [(V, T, rgba, uv)] merged into piece ``p``, each part's points weighted as the piece's nearest point
    (they ride the slab they stand on)."""
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


def merlon_row(person, p, count, sd, rng):
    """``count`` merlons along the outer edge of a shoulder slab ``p`` (side sd): each a block standing on the slab's top
    near its rim (the rim's outermost points round the shoulder), upright on the slab's normal there."""
    S = person.S
    J = {k: v * S for k, v in person.bd.joints.items()}
    sh = J["joint-%s-shoulder" % sd]
    el = J["joint-%s-elbow" % sd]
    arm = unit(el - sh)
    out = unit(np.array([arm[0], 0.0, 0.0]) * 0.8 + np.array([0.0, 0.0, 1.0]) * 0.6)
    V, score = top_points(p, out)
    if len(V) < 4:
        return []
    cut = np.percentile(score, 72)
    rim = V[score >= cut]
    # along the front-back line over the shoulder
    fb = np.array([0.0, 1.0, 0.0])
    t = rim @ fb
    lo, hi = np.percentile(t, 12), np.percentile(t, 88)
    parts = []
    for k in range(count):
        tt = lo + (hi - lo) * (k + 0.5) / count
        sel = np.abs(t - tt) < (hi - lo) / count * 0.6
        base = rim[sel][np.argmax(rim[sel] @ out)] if sel.any() else rim[np.argmin(np.abs(t - tt))]
        nrm = unit(out + rng.normal(0.0, 0.04, 3))
        u = unit(np.cross(nrm, fb))
        v = unit(np.cross(u, nrm))
        size = (0.55 + 0.08 * rng.random()) / F
        tall = (0.95 + 0.15 * rng.random()) / F
        V_, T_ = box(base + nrm * (tall * 0.5 - 0.08 / F), u, v, nrm, size * 0.6, size * 0.5, tall * 0.5, taper=0.08)
        sh_ = 0.92 + 0.08 * rng.random()
        parts.append((V_, T_, np.asarray((sh_, sh_, sh_ * 0.98, 1.0)), None))
    return parts


def pauldron_l_piece(person, body_T, groups):
    p = slab(person, "pauldron_l", body_T, groups, 811)
    rng = np.random.default_rng(812)
    return add_parts(p, merlon_row(person, p, MERLONS["pauldron"], "l", rng), STONE_TILE_M / F)


def pauldron_r_piece(person, body_T, groups):
    """The right shoulder's slab - split through and clamped: iron staples bridging its crack (its own battlements long
    gone)."""
    p = slab(person, "pauldron_r", body_T, groups, 821)
    rng = np.random.default_rng(822)
    S = person.S
    J = {k: v * S for k, v in person.bd.joints.items()}
    sh = J["joint-r-shoulder"]
    up = np.array([0.0, 0.0, 1.0])
    V, score = top_points(p, unit(np.array([-0.6, 0.0, 0.8])))
    top = V[score >= np.percentile(score, 55)]
    fb = np.array([0.0, 1.0, 0.0])
    t = top @ fb
    parts = []
    for k in range(4):
        tt = np.percentile(t, 15 + 70 * k / 3.0)
        near = top[np.argsort(np.abs(t - tt))[:6]]
        c = near.mean(axis=0)
        n = unit(c - (sh + up * 0.02 * S))
        a = unit(np.cross(n, fb))
        V_, T_ = box(c + n * 0.10 / F, a, fb, n, 0.55 / F, 0.10 / F, 0.08 / F)
        parts.append((V_, T_, np.asarray(IRON_RGBA), None))
        for sgn in (-1.0, 1.0):
            V_, T_ = box(c + a * sgn * 0.50 / F + n * 0.02 / F, a, fb, n, 0.09 / F, 0.09 / F, 0.18 / F)
            parts.append((V_, T_, np.asarray(RUST_RGBA), None))
    return add_parts(p, parts, STONE_TILE_M / F)


def back_piece(person, body_T, groups):
    """The portcullis: the back's slab with the gate's iron grille over it - GRILLE["cols"] uprights and ["rows"]
    cross-bars standing a little off the stone, the uprights running on below its lower edge into spikes."""
    p = slab(person, "back", body_T, groups, 831)
    from scipy.spatial import cKDTree
    stone = np.asarray(p.rgba)[:, 3] > 0.5
    V = np.asarray(p.V)[stone]
    back = V[:, 1] > np.percentile(V[:, 1], 35)
    Vb = V[back]
    kd = cKDTree(Vb[:, [0, 2]])
    x0, x1 = np.percentile(Vb[:, 0], 6), np.percentile(Vb[:, 0], 94)
    z0, z1 = np.percentile(Vb[:, 2], 8), np.percentile(Vb[:, 2], 90)
    lift = GRILLE["lift_m"] / F
    r = GRILLE["bar_m"] / F * 0.5

    def surface(x, z):
        d, i = kd.query(np.array([x, z]), k=6)
        return float(Vb[i, 1].max()) + lift

    parts = []
    cols, rows = GRILLE["cols"], GRILLE["rows"]
    for k in range(cols):
        x = x0 + (x1 - x0) * (k + 0.5) / cols
        zs = np.linspace(z1, z0, 7)
        path = np.array([[x, surface(x, z), z] for z in zs])
        spike = GRILLE["spike_m"] / F
        path = np.vstack([path, path[-1] + np.array([0.0, 0.02 / F, -spike * 0.6])])
        radii = np.concatenate([np.full(len(path) - 1, r), [r * 0.25]])
        Vt, Tt, _ring, _ang = sb.tube(path, radii, 4, close=(True, True), frame0=(1.0, 0.0, 0.0))
        parts.append((Vt, Tt, np.asarray(IRON_RGBA if k % 2 else RUST_RGBA), None))
    for j in range(rows):
        z = z1 - (z1 - z0) * (j + 0.35) / rows
        xs = np.linspace(x0 - r, x1 + r, 8)
        path = np.array([[x, surface(x, z) + r * 1.1, z] for x in xs])
        Vt, Tt, _ring, _ang = sb.tube(path, np.full(len(path), r * 0.9), 4, close=(True, True),
                                      frame0=(0.0, 0.0, 1.0))
        parts.append((Vt, Tt, np.asarray(IRON_RGBA), None))
    return add_parts(p, parts, STONE_TILE_M / F)


def helm_piece(person, body_T, groups):
    """A tower's cap: the brow's slab (Stoneback's helm-stone, with its chin strap) crowned with four small merlons round
    the crown and an iron nasal down from its front edge."""
    p = slab(person, "helm", body_T, groups, 841)
    rng = np.random.default_rng(842)
    V, score = top_points(p, (0.0, 0.0, 1.0))
    top = V[score >= np.percentile(score, 70)]
    c = top.mean(axis=0)
    parts = []
    for k in range(MERLONS["helm"]):
        a = 2.0 * math.pi * (k + 0.5) / MERLONS["helm"] + math.pi * 0.25
        d = np.array([math.cos(a), math.sin(a), 0.0])
        rim = top[np.argmax(top @ d)]
        n = unit(np.array([0.0, 0.0, 1.0]) + d * 0.35)
        u = unit(np.cross(n, [0.0, 0.0, 1.0]) if abs(n[2]) < 0.95 else np.array([1.0, 0.0, 0.0]))
        v = np.cross(n, u)
        V_, T_ = box(rim + n * 0.18 / F, u, v, n, 0.26 / F, 0.22 / F, 0.32 / F, taper=0.1)
        parts.append((V_, T_, np.asarray((0.96, 0.95, 0.93, 1.0)), None))
    # the nasal: an iron bar from the front of the helm down over the nose's bridge
    front = V[np.argmin(V[:, 1] + 0.3 * np.abs(V[:, 0]))]
    J = person.bd.joints
    eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"]) * person.S
    tip = np.array([0.0, eye[1] - 0.012 * person.S, eye[2] - 0.035 * person.S])
    a = unit(tip - front)
    mid = 0.5 * (front + tip)
    V_, T_ = box(mid, np.array([1.0, 0.0, 0.0]), a, unit(np.cross(np.array([1.0, 0.0, 0.0]), a)) * -1.0,
                 0.12 / F, float(np.linalg.norm(tip - front)) * 0.5, 0.06 / F)
    parts.append((V_, T_, np.asarray(IRON_RGBA), None))
    return add_parts(p, parts, STONE_TILE_M / F)


def greave_piece(person, name, body_T, groups):
    return slab(person, name, body_T, groups, 851 if name.endswith("_l") else 857)


def mend_piece(person, groups, kd):
    """The mend of his broken right side: two iron bands round the right of his ribs (from the breastbone round under
    the arm to the spine, on the skin), and STAPLES["rows"] staples across the old seam between them - each a flat iron
    bar laid across the seam with its two legs driven in."""
    import people_outfit as po
    S = person.S
    J = {k: v * S for k, v in person.bd.joints.items()}
    V = person.body_V()
    m = person.bd.masks
    torso = (m["m_upperarm"] < 0.2) & (m["m_head"] < 0.1) & (m["m_neck"] < 0.4) & (m["m_hand"] < 0.1) \
        & (m["m_forearm"] < 0.1)
    sh = J["joint-r-shoulder"]
    hip = J["joint-r-upper-leg"]
    parts = []
    srcs = []
    # the seam: from under the right arm down the flank to the hip's front
    a = np.array([sh[0] * 0.92, sh[1] + 0.01 * S, sh[2] - 0.10 * S])
    b = np.array([hip[0] * 0.95, hip[1] - 0.04 * S, hip[2] + 0.06 * S])
    right = torso & (V[:, 0] < -0.02 * S)
    Vr = V[right]
    from scipy.spatial import cKDTree
    kd_r = cKDTree(Vr)
    rows = STAPLES["rows"]
    for k in range(rows):
        t = (k + 0.5) / rows
        p = a + (b - a) * t
        q = Vr[kd_r.query(p)[1]]
        # its outward direction: from the body's axis at that height
        axis_pt = np.array([0.0, float(Vr[:, 1].mean()), q[2]])
        n = unit(q - axis_pt)
        along = unit(b - a)
        across = unit(np.cross(n, along))
        span = STAPLES["span_m"] / F * (0.85 + 0.3 * ((k * 7) % 3) / 2.0)
        wire = STAPLES["wire_m"] / F
        V_, T_ = box(q + n * wire * 1.2, across, along, n, span * 0.5, wire * 0.9, wire * 0.6)
        parts.append((V_, T_, np.asarray(IRON_RGBA if k % 3 else RUST_RGBA), None))
        for sgn in (-1.0, 1.0):
            V_, T_ = box(q + across * sgn * span * 0.45 + n * wire * 0.2, across, along, n, wire * 0.6, wire * 0.6,
                         wire * 1.4)
            parts.append((V_, T_, np.asarray(IRON_RGBA), None))
    # the two bands: round the right ribs, at the seam's upper and lower third
    for f in (0.22, 0.70):
        c = a + (b - a) * f
        ring_c = np.array([0.0, float(V[torso & (np.abs(V[:, 2] - c[2]) < 0.02 * S), 1].mean()), c[2]])
        sel = torso & (np.abs(V[:, 2] - c[2]) < 0.04 * S) & (V[:, 0] < 0.04 * S)
        Vband, Tband = sb.band_ring(ring_c, np.array([0.0, 0.0, 1.0]), V[sel], 0.34 / F, 0.12 / F, 0.03 / F, 22)
        # only the right half (and over the breastbone and the spine a little): the band is a strap, not a hoop
        keep_v = Vband[:, 0] < 0.03 * S
        keep_t = keep_v[Tband].all(axis=1)
        Tk = Tband[keep_t]
        used = np.unique(Tk)
        remap = -np.ones(len(Vband), np.int64)
        remap[used] = np.arange(len(used))
        parts.append((Vband[used], remap[Tk], np.asarray(IRON_RGBA), None))
    Vm, Tm, Cm, UVm = merge(parts, STONE_TILE_M / F)
    src = kd.query(Vm)[1]
    g = {bn: w[src] for bn, w in groups.items()}
    g = sb.stiffen(g, Tm, len(Vm), 3)
    p = po.Piece("mend", Vm, Tm, np.full(len(Tm), po.MATS.index("metal")), g, src)
    p.uv = UVm
    p.rgba = Cm
    p.facts = {"tris": int(len(Tm)), "staples": rows, "seam_m": [[r6(x * F) for x in a], [r6(x * F) for x in b]]}
    p.seam = (a / S, b / S)
    return p


# ======================================================================================================================
# his skin: Stoneback's hide, and the old wound down his right side
# ======================================================================================================================
def wound_of(person, seam):
    """(P human m) -> 0..1: the old wound's scar - a band about the seam's line, ragged (its edges puckered), wider at
    the ribs."""
    import people_bake as pbk
    a, b = seam

    def fn(P):
        d = sb._seg_dist(P, np.asarray(a), np.asarray(b))
        rag = 0.012 + 0.010 * pbk.fbm(P, 30.0, 871)
        core = 1.0 - _sstep(d, 0.0, rag)
        halo = (1.0 - _sstep(d, rag, rag * 2.6)) * 0.45
        return np.clip(np.maximum(core, halo), 0.0, 1.0)
    return fn


def scar_skin(out_dir, LV, LT, Luv, nor, S, wound):
    """The repainted atlas's skin over the old wound: the seam dark and ridged, its halo pale and drawn; and a dusting of
    mortar-grey over his shoulders and arms (the walls he carries)."""
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
    oy = np.clip((ys * pr.ORM_PX) // pr.ALBEDO_PX, 0, pr.ORM_PX - 1)
    ox = np.clip((xs * pr.ORM_PX) // pr.ALBEDO_PX, 0, pr.ORM_PX - 1)
    skin = orm[oy, ox, 2] == skin_b
    Ps = P[skin]
    w = wound(Ps)
    core = np.clip((w - 0.5) / 0.5, 0.0, 1.0)
    halo = np.clip(w / 0.5, 0.0, 1.0) * (1.0 - core)
    col = alb[ys[skin], xs[skin]]
    col = col * (1.0 - 0.55 * core[:, None]) * np.array([1.0, 0.86, 0.84])[None, :] ** core[:, None]
    col = col * (1.0 + 0.12 * halo[:, None]) * np.array([1.0, 0.97, 0.97])[None, :] ** halo[:, None]
    hz = Ps[:, 2] / max(float(P[:, 2].max()), 1e-6)
    dust = _sstep(pbk.fbm(Ps, 5.0, 873), 0.55, 0.72) * _sstep(hz, 0.55, 0.75)
    col = col * (1.0 - 0.25 * dust[:, None]) + np.array([0.70, 0.69, 0.66])[None, :] * 0.25 * dust[:, None]
    alb[ys[skin], xs[skin]] = np.clip(col, 0.0, 1.0)
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))


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
    import giant_garment as gg
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
    import bastion_moves as mv
    from scipy.spatial import cKDTree
    # Stoneback's slab, band, repaint and clip code works in its module's design-to-file scale: here, his
    sb.F = F
    sb.KIND = KIND
    sb.BARK_TILE_M = (2.4, 4.0)
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
    # ---- the outfit and the shared mesh (Stoneback's: the torn hide kilt, the loincloth, the belt)
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, OUTFIT)
    garments = [po.garment_piece(w0, gid, p0, OUTFIT_MATERIAL[gid], kd0) for gid in order]
    garments = [sb.kilt_panels(g, p0, seed=79) if gid == "kilt" else g for g, gid in zip(garments, order)]
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
        raise SystemExit("bastion: the body has %d triangles, over %d" % (mesh.tris(), TRIS))
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the idle's first key (the shield is made where it stands in it), then the pieces
    clips_mod = __import__("clips")
    clips_mod.configure(step_m=STEP_M / F)
    clips_mod.GAITS.update(br.BRUTE_GAITS)
    clips_mod.GAITS.update(WARDEN_GAITS)
    holder = sb.Holder(p0)
    idle = mv.idle0(holder, p0.rest)
    groups23 = pr.fold_weights(p0.groups53())
    kdb = cKDTree(p0.body_V())
    pieces = {"shield": shield_piece(p0, holder, idle), "pauldron_l": pauldron_l_piece(p0, body_T, groups23),
              "pauldron_r": pauldron_r_piece(p0, body_T, groups23), "back": back_piece(p0, body_T, groups23),
              "helm": helm_piece(p0, body_T, groups23), "mend": mend_piece(p0, groups23, kdb),
              "greave_l": greave_piece(p0, "greave_l", body_T, groups23),
              "greave_r": greave_piece(p0, "greave_r", body_T, groups23), "bar": bar_piece(p0)}
    log("pieces: " + ", ".join("%s %d" % (n, p.tris()) for n, p in pieces.items()))
    for name, p in pieces.items():
        if p.tris() > GEAR_BUDGET[name]:
            raise SystemExit("bastion: %s has %d triangles, over %d" % (name, p.tris(), GEAR_BUDGET[name]))
    times["pieces"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the clips' poses
    mv.BAR_V = pieces["bar"].V
    poses, gaits, checks = mv.make_poses(p0, pieces, holder)
    # ---- the bake, Stoneback's hide repainted over it, the old wound
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(KIND, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras)])
    under = np.zeros(N)
    for name, (plate, _spec) in SLABS.items():
        if name != "pauldron_r":
            under = np.maximum(under, np.clip(sb.plate_footprint(p0, plate) * 1.3, 0.0, 1.0))
    ukd = cKDTree(p0.bd.verts[:N])

    def under_fn(P):
        d, i = ukd.query(P, k=4)
        wgt = 1.0 / np.maximum(d, 1e-5)
        return (under[i] * wgt).sum(axis=1) / wgt.sum(axis=1)
    look = {"masks": lambda P: sb.masks_at(P, ukd, p0.bd.masks), "scars": sb.face_scars(p0)[1:3]}
    sb.repaint(out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, under_fn,
               hide_tris=np.isin(Lmat, [MATS.index("leather"), MATS.index("dark_leather")]), look=look)
    scar_skin(out_dir, LV, LT, Luv, nor, p0.S, wound_of(p0, pieces["mend"].seam))
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the skeleton, the meshes, the far mesh
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + KIND)
    mat = bpy.data.materials.new("bastion_body")
    stone = bpy.data.materials.new("bastion_stone")
    oak = bpy.data.materials.new("bastion_oak")
    arm = br.export_rig(p0, p0, KIND + "_rig", coll, F)
    rest_h = pbody.rest_matrices(arm)
    ob = br.skinned_object(KIND, mesh, arm, coll, mat, F)
    exported = [arm, ob]
    piece_info = {}
    for name in PLATE_ORDER + GEAR:
        p = pieces[name]
        o = br.skinned_object(name, p, arm, coll, oak if name == "bar" else stone, F)
        ca = o.data.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        ca.data.foreach_set("color", np.asarray(p.rgba, np.float32).ravel())
        o.data.set_sharp_from_angle(angle=math.radians(SHARP_DEG))
        exported.append(o)
        info_p = {"node": name, "tris": p.tris(), "material": "oak" if name == "bar" else "stone",
                  "bone": PIECE_BONE[name], "plate": name in PLATE_ORDER}
        info_p.update(getattr(p, "facts", {}) or {})
        if name in WEAK_POINTS:
            info_p["region"] = WEAK_POINTS[name]
        if name == "bar":
            H = rest_h["hand_r"]
            info_p["tip_local"] = [r6(x) for x in (H[:3, :3].T @ (p.tip_point * F - H[:3, 3]))]
            info_p["butt_local"] = [r6(x) for x in (H[:3, :3].T @ (p.butt_point * F - H[:3, 3]))]
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
    helm_top = float(pieces["helm"].V[:, 2].max()) * F
    b53 = p0.rig.data.bones
    knuckle = (np.asarray(b53["middle_01_l"].head_local) - np.asarray(b53["hand_l"].head_local)) * F
    reach = (b53["upperarm_l"].length + b53["lowerarm_l"].length) * F + float(np.linalg.norm(knuckle))
    info = {"kind": KIND, "height_m": HEIGHT_M, "export_scale": r6(F), "times": times, "tris_max": TRIS,
            "bake": bake_info, "outfit": list(order),
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget), "culled_skin": culled_skin},
            "variants": {KIND: {"index": 0, "tris": mesh.tris(), "verts": int(len(mesh.V)), "height_m": r6(height),
                                "height_with_helm_m": r6(helm_top), "game_height_m": HEIGHT_M,
                                "game_scale": r6(HEIGHT_M / height), "pieces": [p.name for p in extras],
                                "joints": {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES},
                                "reach_m": r6(reach), "far": {"node": KIND + "_far", "tris": int(len(Tf))}}},
            "pieces": piece_info, "plates": list(PLATE_ORDER), "weak_points": WEAK_POINTS,
            "detail": {"stone": "stoneback_stone", "oak": "ogre_king_wood"},
            "detail_tile_m": {"stone": STONE_TILE_M, "oak": WOOD_TILE_M}, "checks": checks,
            "used_by": ["enemy.bastion (C2: BastionRig)", "tools/bastion_stills.gd"]}
    for sd in ("l", "r"):
        g, ax = p0.grip[sd]
        H = rest["hand_" + sd]
        info["variants"][KIND]["grip_local_" + sd] = [r6(x) for x in (H[:3, :3].T @ (g * F - H[:3, 3]))]
        info["variants"][KIND]["grip_axis_" + sd] = [r6(x) for x in (H[:3, :3].T @ ax)]
    info["glb_bytes"] = os.path.getsize(path)
    worst = 0.0
    for name in ("walk", "idle", "bash", "smash2"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            Gk = pbody.fk(rest, pbody.parents_of(arm), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "hand_l", "head", "pelvis"):
                worst = max(worst, float(np.linalg.norm(Gk[b][:3, 3] - poses[name][kk].P[b] * F)))
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("bastion clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    import clips
    sb.CLIP_FRAMES = {n: len(k) - 1 for n, k in poses.items()}   # (sb.key_actions keys the clips it lists)
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
        raise SystemExit("usage: bastion.py bastion <out dir> <work dir>")
    build(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
