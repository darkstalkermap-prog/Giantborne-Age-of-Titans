"""The brutes (plan M11 §2.8, P63): the ogre and the troll, the whelp, the Ogre King's and the Troll Matriarch's gear.

A brute is the people's human (``people_body``: the giant's CC0 MakeHuman data and code) with MakeHuman's muscle and
weight macros at their most, reshaped twice: first by the giant's own proportions function (``giant_body.proportioned``
with a brute's table: shorter legs, a longer torso, the head sunk between the shoulders, long arms, big hands), then by
this module's vertex functions on named regions (``reshape``): a hunched upper back with the head carried forward and
the face turned back up to look ahead, a heavier jaw (the ogre's underbite), a jutting brow, the troll's long nose and
pointed ears, thicker hands and feet, the ogre's gut. The joints are read from the reshaped mesh (the helpers move
with it), so the 53-bone rig fits the new body; it is folded to the people's 23 bones (``people_roles.BONES``).

Each kind is a "role" in the people's sense: one shared mesh (the first variant's body and outfit, the giant's
garment shells, culled, merged, decimated to ``TRIS``, unwrapped into one atlas), its variants moved onto their own
bodies through the hm08 topology they share (the whelp is the troll's mesh on a younger body), the atlas baked by
``people_bake`` (the palette bands; the skin band then repainted here with the kind's own hide and moss, and its
normal map given the hide's wrinkles and warts). The gear of the bosses is skinned to the same skeleton as separate
meshes (shown with the body): the Ogre King's crown, mantle and gilded belt; the Troll Matriarch's bone crown and hide
mantle. The ogre's tusks and the troll's claws are part of the body.

Clips: ``clips.py``'s generator on the kind's own rig (its own proportions; the brutes' stride, ActorRig's 1.5 m at
the ogre's 3.4 m): a heavier walk and run (the knees bent, the trunk pitched, the arms hanging wide), the idle, the
two-arm slam (the stance wide, both fists over the head, then down to the ground in front), the roar, the brace, the
death and the grips. The reach bands: each kind's shoulder joint, arm and palm against its box rig's weapon pivot and
arm length (``data/enemies/*.json``, as tools/builders/heavy.gd and big.gd built them): every grip the box rig's arm
can reach from its pivot lies within the brute's own reach, and the brute's reach is no longer than that by more than
``REACH_TOL`` (``reach_bands``).

``python brute.py <kind> <out dir> <work dir> [ao_from dir]`` builds one kind (run by build_people.py --brutes in its
own interpreter): ``<kind>.glb`` (the variants' meshes on their 23-bone skeletons, the gear, the far meshes),
``<kind>_clips.glb``, the atlas ``<kind>_albedo.png`` (512 px), ``<kind>_normal.png`` and ``<kind>_orm.png`` (256 px).
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

import mh_data as mh  # noqa: E402
import people_roles as pr  # noqa: E402

DESIGN = pr.DESIGN_HEIGHT_M        # built at the giant's stage-1 height (his garment code's units), exported at H
N = mh.N_BODY_VERTS
REACH_TOL = 0.05                   # the reach bands: within 5 % of the box rig's arm (plan §3.16)
TRIS = 9000                        # a brute's body and outfit (plan §2.8: about 9,000)
GEAR_TRIS_MAX = 3000               # a boss's gear (P65a: 2,400 before the mantle's collar and the belt's buckle)
FAR_TRIS = 300                     # the far mesh
TRIS_MAX = 9000                    # a variant: one mesh, one surface

# ---- the kinds -----------------------------------------------------------------------------------------------------
# macro: MakeHuman's sliders (muscle and weight at their most for the ogre); face: the giant's own face modifiers
# (mh_data.GIANT_MODIFIERS: the same vendored targets) scaled; prop: giant_body.proportioned's table; shape: this
# module's region functions (reshape); box: the box rig's gameplay numbers (data/enemies/<record>.json:
# height_m, weapon_pivot_m, arm_length_m) the reach bands are measured against.


def _macro(age, muscle, weight, african=0.25, asian=0.1, caucasian=0.65):
    return dict(gender=1.0, age=mh.age_years_to_value(age), muscle=muscle, weight=weight, height=0.5, proportions=0.2,
                african=african, asian=asian, caucasian=caucasian, cupsize=0.5, firmness=0.5)


def _face(scale, **over):
    out = {k: max(-1.0, min(1.0, v * scale)) for k, v in mh.GIANT_MODIFIERS.items()}
    out.update(over)
    return out


# the ogre's own face over the giant's: a short, broad, flat nose, a wide square jaw thrust forward, a heavy brow
OGRE_FACE = {"nose/nose-scale-vert-decr-incr": -0.7, "nose/nose-hump-decr-incr": 0.0, "nose/nose-flaring-decr-incr": 1.0,
             "nose/nose-nostrils-width-decr-incr": 1.0, "nose/nose-scale-horiz-decr-incr": 1.0,
             "nose/nose-point-width-decr-incr": 1.0, "nose/nose-volume-decr-incr": 1.0,
             "nose/nose-width1-decr-incr": 1.0, "nose/nose-width2-decr-incr": 1.0,
             "chin/chin-width-decr-incr": 1.0, "chin/chin-prominent-decr-incr": 1.0, "chin/chin-jaw-drop-decr-incr": 0.6,
             "chin/chin-bones-decr-incr": 1.0, "head/head-square": 1.0, "head/head-fat-decr-incr": 0.5,
             "mouth/mouth-scale-horiz-decr-incr": 1.0, "mouth/mouth-lowerlip-volume-decr-incr": 0.7,
             "eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -1.0,
             "forehead/forehead-trans-backward-forward": 0.7, "ears/ear-scale-decr-incr": 0.5}
# the troll's own face over the giant's (P65a: it read as an old man's): a wide mouth and a strong chin, the brows low
# and forward, large ears
TROLL_FACE = {"mouth/mouth-scale-horiz-decr-incr": 1.0, "mouth/mouth-lowerlip-volume-decr-incr": 0.5,
              "chin/chin-prominent-decr-incr": 0.7, "chin/chin-width-decr-incr": 0.8, "chin/chin-bones-decr-incr": 0.8,
              "eyebrows/eyebrows-trans-backward-forward": 1.0, "eyebrows/eyebrows-trans-down-up": -1.0,
              "forehead/forehead-trans-backward-forward": 0.6, "ears/ear-scale-decr-incr": 1.0,
              "head/head-square": 0.6}
OGRE_PROP = dict(legs=0.80, torso=1.04, neck=-0.035, head=0.86, arms=0.94, hands=1.12, shoulders=-0.045,
                 deltoids=0.0, trapezius=-0.030, thighs=0.0)
TROLL_PROP = dict(legs=0.90, torso=1.06, neck=-0.030, head=0.84, arms=1.05, hands=1.20, shoulders=-0.030,
                  deltoids=0.0, trapezius=-0.040, thighs=0.10)
WHELP_PROP = dict(TROLL_PROP, head=0.95, arms=1.07, hands=1.15, neck=-0.020)

OGRE_SHAPE = dict(hunch_deg=24.0, head_back_deg=18.0, jaw=(0.34, 0.014, 0.010), underbite_m=0.016, brow_m=0.020,
                  nose=(-0.016, -0.004), ears=0.0, hands=1.10, feet=1.18, gut_m=0.040, tusks=True)
TROLL_SHAPE = dict(hunch_deg=32.0, head_back_deg=24.0, jaw=(0.28, 0.012, 0.010), underbite_m=0.006, brow_m=0.034,
                   brow_band_m=0.016, ear_point=1.8, nose=(0.034, 0.014), ears=1.15, hands=1.12, feet=1.20, gut_m=0.0,
                   tusks=False)
WHELP_SHAPE = dict(TROLL_SHAPE, hunch_deg=24.0, head_back_deg=18.0, jaw=(0.06, 0.004, 0.004), brow_m=0.008,
                   brow_band_m=0.012, ear_point=1.0, nose=(0.024, 0.010), ears=0.45)

KINDS = {
    "ogre": dict(
        height_m=3.4, step_m=1.5, faction=(), outfit=("loincloth", "belt", "bracers"),
        variants=(dict(name="ogre", macro=_macro(34, 1.0, 1.0), face=_face(2.0, **OGRE_FACE), prop=OGRE_PROP, shape=OGRE_SHAPE,
                       box="ogre", height_m=3.4),),
        gear={"ogre_king": ("hide_mantle", "war_belt", "crown")},
        box={"ogre": dict(height_m=3.4, pivot=(0.88, 2.62, 0.0), arm=1.12),
             "ogre_king": dict(height_m=8.5, pivot=(2.2, 6.55, 0.0), arm=2.8)},
        used_by=("enemy.ogre", "enemy.ogre_king (with the ogre_king gear, x 2.5)")),
    "troll": dict(
        height_m=5.5, step_m=2.427, faction=(), outfit=("loincloth",),
        variants=(dict(name="troll", macro=_macro(40, 1.0, 0.9, 0.3, 0.1, 0.6), face=_face(1.8, **TROLL_FACE), prop=TROLL_PROP,
                       shape=TROLL_SHAPE, box="troll", height_m=5.5),
                  dict(name="whelp", macro=_macro(18, 0.95, 0.75, 0.3, 0.1, 0.6), face=_face(1.1), prop=WHELP_PROP,
                       shape=WHELP_SHAPE, box="troll_whelp", height_m=3.5)),
        gear={"troll_matriarch": ("hide_mantle", "bone_crown")},
        box={"troll": dict(height_m=5.5, pivot=(1.42, 4.24, 0.0), arm=1.8),
             "troll_whelp": dict(height_m=3.5, pivot=(0.9, 2.7, 0.0), arm=1.1),
             "troll_matriarch": dict(height_m=9.0, pivot=(2.32, 6.94, 0.0), arm=2.9)},
        used_by=("enemy.troll", "enemy.troll_whelp (the whelp variant)",
                 "enemy.troll_matriarch (with the troll_matriarch gear)")),
}
KIND_ORDER = ("ogre", "troll")
# The bosses: the kind's first variant at the boss's height with the boss's gear.
BOSSES = {"ogre_king": ("ogre", "ogre"), "troll_matriarch": ("troll", "troll")}


def log(*a):
    print("[brute]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


def _sstep(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---- the body: the reshape ------------------------------------------------------------------------------------------
def _rot_about(P, centre, axis, ang):
    """Points rotated about the axis through ``centre`` by per-point angles (radians, Rodrigues)."""
    k = np.asarray(axis, np.float64)
    k = k / np.linalg.norm(k)
    Q = P - centre
    c, s = np.cos(ang)[:, None], np.sin(ang)[:, None]
    return centre + Q * c + np.cross(k, Q) * s + k * (Q @ k)[:, None] * (1.0 - c)


def reshape(bm, verts_mh, shape):
    """This module's vertex functions on the morphed (and proportioned) vertices, MakeHuman units in and out: every
    vertex moves (the body, the helpers and their joint cubes), so the joints read afterwards follow."""
    J = {k: mh.mh_to_blender(v) for k, v in mh.joint_positions(bm, verts_mh).items()}
    V = mh.mh_to_blender(verts_mh)
    n = len(V)
    w = mh.load_weights()

    def wsum(prefixes):
        out = np.zeros(n)
        for bone, lst in w.items():
            if bone.startswith(prefixes):
                for vi, wt in lst:
                    if vi < n:
                        out[vi] += wt
        return np.clip(out, 0.0, 1.0)

    arm = wsum(("clavicle", "upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"))
    limb = wsum(("upperarm", "lowerarm", "hand", "thumb", "index", "middle", "ring", "pinky"))
    head = wsum(("head",))
    neck = wsum(("neck",))
    hands = wsum(("hand", "thumb", "index", "middle", "ring", "pinky"))
    feet = wsum(("foot", "ball"))
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    # ---- the gut: the belly pushed forward and down under the navel's line
    if shape["gut_m"]:
        sp1 = J["joint-spine-3"]
        pel = J["joint-pelvis"]
        mid = 0.5 * (sp1[2] + pel[2])
        t = np.exp(-((z - mid) / 0.11) ** 2) * np.exp(-(x / 0.16) ** 2) * _sstep(-(y - sp1[1]), -0.02, 0.06)
        t *= (1.0 - arm) * (1.0 - wsum(("thigh",)) * 0.7)
        V[:, 1] -= shape["gut_m"] * t
        V[:, 2] -= 0.4 * shape["gut_m"] * t
    # ---- the hunch: the upper back bent forward about the mid-back; the arms ride with their shoulders
    piv = J["joint-spine-2"].copy()
    sh_z = 0.5 * (J["joint-l-shoulder"][2] + J["joint-r-shoulder"][2])
    rise = sh_z - piv[2]
    t_own = _sstep(z, piv[2] - 0.04, piv[2] + 0.6 * rise)
    t_sh = float(_sstep(sh_z, piv[2] - 0.04, piv[2] + 0.6 * rise))
    t = (1.0 - arm) * t_own + arm * t_sh
    V = _rot_about(V, piv, (1.0, 0.0, 0.0), math.radians(shape["hunch_deg"]) * t)    # +x: the top goes forward (-y)
    # ---- the head turned back up about the neck's joint (the face looks ahead again; the neck carries it forward)
    nk = mh.mh_to_blender(mh.joint_positions(bm, _to_mh(V))["joint-neck"])
    th = np.clip(head + 0.5 * neck * _sstep(V[:, 2], nk[2] - 0.02, nk[2] + 0.04), 0.0, 1.0) * (1.0 - limb)
    V = _rot_about(V, nk, (1.0, 0.0, 0.0), -math.radians(shape["head_back_deg"]) * th)
    J = {k: mh.mh_to_blender(v) for k, v in mh.joint_positions(bm, _to_mh(V)).items()}
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    # ---- the face's regions (the head's own frame: its joints after the turn)
    jaw, mouth = J["joint-jaw"], J["joint-mouth"]
    eye = 0.5 * (J["joint-l-eye"] + J["joint-r-eye"])
    hd = J["joint-head"]
    front = _sstep(-(y - jaw[1]), -0.005, 0.03)                  # in front of the jaw's hinge
    low = _sstep(-(z - (mouth[2] + 0.005)), -0.004, 0.03)         # under the mouth's line
    jt = head * front * low
    kx, kdown, kfwd = shape["jaw"]
    V[:, 0] = x + x * kx * jt
    V[:, 2] = z - kdown * jt * _sstep(-(z - mouth[2]), 0.0, 0.05)
    V[:, 1] = y - (kfwd + shape["underbite_m"]) * jt * _sstep(-(z - mouth[2]), -0.01, 0.03)
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    # the brow ridge: forward, a band over the eyes
    bt = head * np.exp(-((z - (eye[2] + 0.022)) / shape.get("brow_band_m", 0.012)) ** 2) \
        * _sstep(-(y - eye[1]), -0.02, 0.01) * np.exp(-(x / 0.075) ** 2)
    V[:, 1] = y - shape["brow_m"] * bt
    V[:, 2] = z - 0.3 * shape["brow_m"] * bt
    # the nose: longer and hooked down
    if shape["nose"][0]:
        mid = np.abs(x) < 0.03
        sel = (head > 0.5) & mid & (np.abs(z - (eye[2] - 0.035)) < 0.03)
        tip_i = np.nonzero(sel)[0][np.argmin(V[sel, 1])]
        tip = V[tip_i].copy()
        d = np.linalg.norm((V - tip) * [1.0, 0.8, 0.9], axis=1)
        nt = head * (1.0 - _sstep(d, 0.008, 0.05)) * _sstep(-(y - (tip[1] + 0.035)), 0.0, 0.03)
        V[:, 1] -= shape["nose"][0] * nt
        V[:, 2] -= shape["nose"][1] * nt * _sstep(-(y - tip[1] - 0.01), 0.0, 0.03)
    # the ears (P65a: MPFB's ear mask; P63 pushed the head's widest vertices, which on the troll's broad head missed
    # the ears): each ear's upper part drawn out up, back and out into a long point, the more the higher on the ear
    if shape["ears"]:
        import giant_body as gb

        class _Shim:
            pass
        shim = _Shim()
        shim.bm = bm
        shim.group = lambda name: gb.BodyData.group(shim, name)
        em = np.zeros(n)
        em[:N] = np.clip((gb.uv_mask(shim, "mpfb_ears.jpg") - 0.15) / 0.35, 0.0, 1.0)
        for sx in (1.0, -1.0):
            side = (np.sign(V[:, 0]) == sx) & (em > 0.0)
            core = side & (em > 0.8)
            if core.sum() < 4:
                continue
            c = V[core].mean(axis=0)
            hh = max(float(np.ptp(V[core, 2])) * 0.5, 1e-3)
            hgt = np.clip((V[side, 2] - (c[2] - 0.2 * hh)) / (1.2 * hh), 0.0, 1.6)
            d = np.array([0.55 * sx, 0.55, 0.62])
            d /= np.linalg.norm(d)
            amt = shape["ears"] * 0.045 * hgt ** shape.get("ear_point", 1.0) * em[side]
            V[side] += amt[:, None] * d[None, :]
            # the whole ear turned a little out from the skull
            V[side, 0] += sx * shape["ears"] * 0.008 * em[side]
    # ---- the legs' outline eased (P65a): MakeHuman's muscle target at its most on the shortened legs bulged the
    # thighs and the calves and pinched the knees between them (a diamond, front and back)
    V = leg_fill(V, J, wsum(("thigh_l",)) + wsum(("calf_l",)), wsum(("thigh_r",)) + wsum(("calf_r",)),
                 shape.get("leg_ease", LEG_EASE))
    # ---- the hands and the feet thicker about the wrist and the ankle
    for s, side in ((1.0, "l"), (-1.0, "r")):
        sel = np.sign(V[:, 0]) == s
        wr = J["joint-%s-hand" % side]
        k = 1.0 + (shape["hands"] - 1.0) * hands
        V[sel] = wr + (V[sel] - wr) * k[sel, None]
        an = J["joint-%s-ankle" % side]
        k = 1.0 + (shape["feet"] - 1.0) * feet
        Q = V[sel] - an
        Q[:, 0] *= k[sel]
        Q[:, 1] *= k[sel]
        Q[:, 2] *= 1.0 + 0.4 * (k[sel] - 1.0)
        V[sel] = an + Q
    return _to_mh(V)


LEG_EASE = (0.45, 0.25)            # (a bulge kept, a pinch kept) of their depth against the leg's smoothed outline
LEG_EASE_SIGMA_M = 0.06            # the outline's smoothing along the leg (human m)
LEG_SECTORS = 16


def leg_fill(V, J, wl, wr, ease):
    """Each leg's surface (the body's vertices that are the thigh's and the calf's) eased toward its own smoothed outline:
    per sector of angle round the hip-knee-ankle line, the radius against the distance along it, smoothed along the leg
    (LEG_EASE_SIGMA_M) and a little round it; a vertex's depth over that outline (a bulge) is kept ``ease[0]``, its
    depth under it (a pinch) ``ease[1]``. Only from a third of the thigh down to two thirds of the calf; the feet, the
    hips and the crotch keep their shape. The joints' helper cubes do not move (the joints are read after)."""
    V = V.copy()
    for side, wts in (("l", wl), ("r", wr)):
        hip, kn, an = (J["joint-%s-%s" % (side, k)] for k in ("upper-leg", "knee", "ankle"))
        segs = ((hip, kn, 0.0), (kn, an, float(np.linalg.norm(kn - hip))))
        L1, L2 = float(np.linalg.norm(kn - hip)), float(np.linalg.norm(an - kn))
        ids = np.nonzero((np.arange(len(V)) < N) & (np.clip(wts, 0, 1) > 0.5))[0]
        P = V[ids]
        best = np.full(len(P), np.inf)
        s_ = np.zeros(len(P))
        foot = np.zeros((len(P), 3))
        axis = np.zeros((len(P), 3))
        for a, b, s0 in segs:
            ab = b - a
            t = np.clip(((P - a) @ ab) / float(ab @ ab), 0.0, 1.0)
            q = a + t[:, None] * ab
            d = np.linalg.norm(P - q, axis=1)
            m = d < best
            best[m] = d[m]
            s_[m] = s0 + t[m] * float(np.linalg.norm(ab))
            foot[m] = q[m]
            axis[m] = ab / np.linalg.norm(ab)
        R = P - foot
        r = np.linalg.norm(R, axis=1)
        fwd = np.array([0.0, -1.0, 0.0])
        f = fwd - axis * (axis @ fwd)[:, None]
        f /= np.maximum(np.linalg.norm(f, axis=1, keepdims=True), 1e-9)
        lat = np.cross(axis, f)
        ang = np.arctan2(np.einsum("ij,ij->i", R, lat), np.einsum("ij,ij->i", R, f)) % (2.0 * math.pi)
        sec = np.minimum((ang / (2.0 * math.pi) * LEG_SECTORS).astype(np.int64), LEG_SECTORS - 1)
        step = 0.01
        nb = int(math.ceil((L1 + L2) / step)) + 1
        b_ = np.clip((s_ / step).astype(np.int64), 0, nb - 1)
        tot = np.zeros((LEG_SECTORS, nb))
        cnt = np.zeros((LEG_SECTORS, nb))
        np.add.at(tot, (sec, b_), r)
        np.add.at(cnt, (sec, b_), 1.0)
        g = np.exp(-0.5 * (np.arange(-12, 13) * step / LEG_EASE_SIGMA_M) ** 2)
        tot_s = np.stack([np.convolve(row, g, "same") for row in tot])
        cnt_s = np.stack([np.convolve(row, g, "same") for row in cnt])
        tot_s = 0.5 * tot_s + 0.25 * (np.roll(tot_s, 1, 0) + np.roll(tot_s, -1, 0))
        cnt_s = 0.5 * cnt_s + 0.25 * (np.roll(cnt_s, 1, 0) + np.roll(cnt_s, -1, 0))
        prof = tot_s / np.maximum(cnt_s, 1e-9)
        sm = prof[sec, b_]
        k = np.where(r > sm, ease[0], ease[1])
        r_new = sm + (r - sm) * k
        reg = _sstep(s_, 0.30 * L1, 0.50 * L1) * (1.0 - _sstep(s_, L1 + 0.55 * L2, L1 + 0.75 * L2))
        reg *= np.clip((np.clip(wts[ids], 0, 1) - 0.5) / 0.3, 0.0, 1.0)
        r_out = r + reg * (r_new - r)
        V[ids] = foot + R / np.maximum(r, 1e-9)[:, None] * r_out[:, None]
    return V


def _to_mh(V):
    back = np.empty_like(V)
    back[:, 0] = V[:, 0] * 10.0
    back[:, 1] = V[:, 2] * 10.0
    back[:, 2] = -V[:, 1] * 10.0
    return back


def body_data(v):
    """giant_body.BodyData of a brute variant: the phenotype, the giant's proportions function with the brute's table,
    then reshape; the joints, the ground and the height read from the result."""
    import giant_body as gb

    class BruteData(gb.BodyData):
        def __init__(self, spec):
            t = time.time()
            self.bm, self.verts_mh, self.target_weights = mh.build_phenotype(spec["macro"], spec["face"])
            self.verts_mh = gb.proportioned(self.bm, self.verts_mh, spec["prop"])
            self.verts_mh = reshape(self.bm, self.verts_mh, spec["shape"])
            self.joints_mh = mh.joint_positions(self.bm, self.verts_mh)
            ground = mh.mh_to_blender(self.joints_mh["joint-ground"])
            self.offset = np.array([0.0, 0.0, -ground[2]])
            self.verts = mh.mh_to_blender(self.verts_mh) + self.offset
            self.joints = {k: mh.mh_to_blender(p) + self.offset for k, p in self.joints_mh.items()}
            self.height = float(self.verts[:N, 2].max())
            self.masks = {}
            self.landmarks = None
            log("%s: %d targets, height %.3f m (%.1f s)" % (spec["name"], len(self.target_weights), self.height,
                                                             time.time() - t))
    return BruteData(v)


# ======================================================================================================================
# The build (Blender): ``python brute.py <kind> <out dir> <work dir>``
# ======================================================================================================================
HEAD_DETAIL = 0.92                 # the collapse's detail weight on the head (P65a 0.7, less a fifth on the scalp)
MARGIN_TRIS = 60                   # kept back from the shared budget
EXTRA_TRIS = {"tusks": 96, "eyes": 96}
GEAR_BUDGET = {"fur_mantle": 1300, "war_belt": 560, "hide_mantle": 1400, "collar": 520, "crown": 320,
               "bone_crown": 380}
GEAR_TILE = {"fur_mantle": "faction", "war_belt": "metal", "hide_mantle": "leather", "crown": "metal",
             "bone_crown": "fur"}
# (boss, garment): (material, tile) where a boss wears a garment otherwise: the Ogre King's mantle in his colour
GEAR_STYLE = {("ogre_king", "hide_mantle"): ("faction", "faction")}
GEAR_MATERIAL = {"fur_mantle": "faction", "war_belt": "metal", "hide_mantle": "leather", "crown": "metal",
                 "bone_crown": "leather"}
# The kinds' own colours in the atlas's tiles (the bake's tiles repainted): the ogre's metal is gold (the king's crown
# and belt) and its fur tile ivory (the tusks), the troll's fur tile is bone (the matriarch's crown); albedo sRGB,
# roughness.
TILE_REPAINT = {"ogre": {"metal": ((0.80, 0.62, 0.24), 0.30), "fur": ((0.86, 0.81, 0.66), 0.50)},
                "troll": {"fur": ((0.82, 0.77, 0.64), 0.55)}}
CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "slam": 36, "roar": 24, "brace": 1, "death": 30, "grip_r": 1,
               "grip_l": 1}
CLIP_LOOPS = ("idle", "walk", "run")
PARTIAL_CLIPS = {"grip_r": ("hand_r",), "grip_l": ("hand_l",)}
# The brutes' gaits: clips.py's walk and run made heavier (the knees bent, a short duty of the swing, the trunk pitched
# forward, the arms hanging out from the bulk and swinging less, the pelvis rolling more).
BRUTE_GAITS = {
    "brute_walk": dict(duty=0.60, foot_x=0.34, lift=0.16, lift_peak=0.45, strike_deg=-10.0, toe_off_deg=26.0,
                       heel_rocker=0.12, heel_off=0.66, bias=0.0, top_drop=0.10, min_drop=0.05, sway=0.07,
                       yaw_deg=6.0, roll_deg=5.0, pelvis_pitch_deg=6.0, lean_deg=9.0, arm_swing_deg=12.0,
                       elbow_deg=22.0, elbow_swing_deg=8.0, shoulder_counter=1.2),
    "brute_run": dict(duty=0.42, foot_x=0.30, lift=0.45, lift_peak=0.40, strike_deg=-6.0, toe_off_deg=34.0,
                      heel_rocker=0.10, heel_off=0.48, bias=0.03, top_drop=0.16, min_drop=0.16, sway=0.05,
                      yaw_deg=8.0, roll_deg=5.0, pelvis_pitch_deg=10.0, lean_deg=16.0, arm_swing_deg=30.0,
                      elbow_deg=60.0, elbow_swing_deg=12.0, shoulder_counter=1.2),
}
ARM_OUT_DEG = 20.0                 # the arms hang this far out from the bulk of the trunk


def export_scale(kind):
    return KINDS[kind]["height_m"] / DESIGN


def brute_person(v, ref=None):
    """people_body.build_person for a brute variant (its own BodyData)."""
    import giant_body as gb
    import people_body as pbody
    bd = body_data(v)
    p = pbody._pelvis_point(bd)
    if ref is None:
        S = DESIGN / bd.height
    else:
        S = float(ref.pelvis[2] / p[2])
        shift = np.array([0.0, float(ref.pelvis[1] / S - p[1]), 0.0])
        bd.offset = bd.offset + shift
        bd.verts = bd.verts + shift
        bd.joints = {k: q + shift for k, q in bd.joints.items()}
    objs = gb.build_giant({"height_m": bd.height * S, "name": v["name"], "collection": gb._collection(v["name"])},
                          bd=bd)
    person = pbody.Person(v["name"], bd, objs["info"]["scale"], objs)
    pbody.pose_hands(person)
    return person


# ---- pieces of the brutes' own -------------------------------------------------------------------------------------
def _tube(path, radii, segs, close_tip=True):
    """A tube along ``path`` (k, 3) with ``radii`` (k,) and ``segs`` sides; the tip closed to a point."""
    path = np.asarray(path, np.float64)
    k = len(path)
    tang = np.gradient(path, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    a = np.array([1.0, 0.0, 0.0]) if abs(tang[0][0]) < 0.9 else np.array([0.0, 1.0, 0.0])
    V, T = [], []
    for i in range(k):
        u = np.cross(tang[i], a)
        u /= np.linalg.norm(u)
        w = np.cross(tang[i], u)
        for s in range(segs):
            ph = 2.0 * math.pi * s / segs
            V.append(path[i] + radii[i] * (math.cos(ph) * u + math.sin(ph) * w))
    for i in range(k - 1):
        for s in range(segs):
            a0, b0 = i * segs + s, i * segs + (s + 1) % segs
            T += [(a0, b0, b0 + segs), (a0, b0 + segs, a0 + segs)]
    if close_tip:
        tip = len(V)
        V.append(path[-1] + tang[-1] * radii[-1])
        for s in range(segs):
            T.append(((k - 1) * segs + s, (k - 1) * segs + (s + 1) % segs, tip))
    return np.asarray(V), np.asarray(T, np.int64)


def tusks_piece(person):
    """The ogre's two lower tusks: from the lower lip's corners, up and out past the upper lip."""
    import people_outfit as po
    S = person.S
    bd = person.bd
    BV = bd.verts[:N]
    lips = bd.masks["m_lips"] > 0.5
    Vs, Ts = [], []
    for s in (1.0, -1.0):
        # the lower lip's corner: the lips' outermost vertices on this side, at their lower half
        side = lips & (np.sign(BV[:, 0]) == s)
        zc = np.median(BV[side, 2])
        lo = side & (BV[:, 2] <= zc)
        corner = BV[lo][np.argmax(np.abs(BV[lo, 0]))]
        base = (corner + np.array([-0.006 * s, 0.002, -0.012])) * S
        path = [base + np.array([0.004 * s * t, -0.010 * t, 0.026 * t]) * S + np.array([0.004 * s, -0.003, 0.0]) * S
                * t * t * 2.0 for t in np.linspace(0.0, 1.0, 4)]
        r = np.array([0.0085, 0.0072, 0.0052, 0.0030]) * S
        V, T = _tube(path, r, 6)
        Ts.append(T + sum(len(v) for v in Vs))
        Vs.append(V)
    V, T = np.concatenate(Vs), np.concatenate(Ts)
    p = po.Piece("tusks", V, T, np.full(len(T), po.MATS.index("fur")), {"head": np.ones(len(V))},
                 np.full(len(V), -1))
    # the fur tile, repainted ivory in the ogre's atlas (TILE_REPAINT)
    u0, v0 = pr.TILES["fur"]
    P = V[T]
    h = (P[..., 2] - V[:, 2].min()) / max(np.ptp(V[:, 2]), 1e-6)
    az = (np.arctan2(P[..., 1] - V[:, 1].mean(), np.abs(P[..., 0])) / math.pi + 1.0) * 0.5
    p.uv = np.stack([u0 + pr.TILE_SIZE * (0.1 + 0.8 * az), v0 + pr.TILE_SIZE * (0.06 + 0.3 * h)], axis=-1)
    return p


def _head_ring(person, dz_human, n=24):
    """(centre, radii (n,)) of the head's slice at the eyes' height plus dz (human metres), at design scale: per
    angle k (0 at the front, -y; counter-clockwise from above) the slice's farthest point within its sector."""
    S = person.S
    bd = person.bd
    eye = 0.5 * (bd.joints["joint-l-eye"] + bd.joints["joint-r-eye"])
    z = eye[2] + dz_human
    V = bd.verts[:N]
    head = person.bd.masks["m_head"] > 0.6
    sel = head & (np.abs(V[:, 2] - z) < 0.008)
    c = np.array([V[sel, 0].mean(), V[sel, 1].mean(), z])
    Q = (V[sel] - c)[:, :2]
    ang = np.arctan2(Q[:, 0], -Q[:, 1]) % (2.0 * math.pi)
    d = np.linalg.norm(Q, axis=1)
    radii = np.zeros(n)
    for k in range(n):
        a = 2.0 * math.pi * k / n
        diff = np.abs((ang - a + math.pi) % (2.0 * math.pi) - math.pi)
        near = diff < 2.0 * math.pi / n
        radii[k] = d[near].max() if near.any() else d.max()
    radii = np.convolve(np.concatenate([radii[-1:], radii, radii[:1]]), np.ones(3) / 3.0, "valid")
    return c * S, radii * S


def crown_piece(person, kind):
    """The Ogre King's gold crown (a band and six points over the brow) or the Matriarch's bone crown (a band of
    teeth and nine horn points, the front ones longest)."""
    import people_outfit as po
    bone = kind == "bone_crown"
    n = 24
    c, rr = _head_ring(person, 0.030 if not bone else 0.026, n)
    S = person.S
    rr = rr * 1.03 + 0.002 * S
    hgt = (0.024 if not bone else 0.018) * S
    V, T = [], []
    for k in range(n):
        a = 2.0 * math.pi * k / n
        d = np.array([math.sin(a), -math.cos(a), 0.0])        # k = 0 at the front (-y)
        r = rr[k]
        V += [c + d * r - np.array([0, 0, hgt * 0.4]), c + d * r + np.array([0, 0, hgt * 0.6]),
              c + d * (r + 0.004 * S) + np.array([0, 0, hgt * 0.6]), c + d * (r + 0.004 * S) - np.array([0, 0, hgt * 0.4])]
    for k in range(n):
        a0, b0 = 4 * k, 4 * ((k + 1) % n)
        for i in range(4):
            j = (i + 1) % 4
            T += [(a0 + i, b0 + i, b0 + j), (a0 + i, b0 + j, a0 + j)]
    V = list(V)
    points = 8 if not bone else 9
    for k in range(points):
        a = 2.0 * math.pi * (k + 0.5) / points if bone else 2.0 * math.pi * k / points
        d = np.array([math.sin(a), -math.cos(a), 0.0])
        front = 0.5 + 0.5 * math.cos(a)
        # P65a: the gold crown's eight points tall and short in turn (the front one tallest): P63's six short ones read
        # as a plain ring
        tall = ((0.040 + 0.020 * front) * (1.0 if k % 2 == 0 else 0.55) if not bone else (0.028 + 0.040 * front)) * S
        r = float(np.interp((a / (2.0 * math.pi)) * len(rr), np.arange(len(rr) + 1), np.append(rr, rr[0])))
        base = c + d * (r + 0.002 * S) + np.array([0, 0, hgt * 0.5])
        lean = d * (0.0 if not bone else 0.010 * S) 
        path = [base + lean * t + np.array([0, 0, tall * t]) for t in np.linspace(0, 1, 3)]
        # (P63 named these radii rr too, overwriting the head's ring: every point after the first stood inside the head)
        tr = np.array([0.010, 0.006, 0.0015]) * S if not bone else np.array([0.008, 0.005, 0.0015]) * S * 0.9
        pv, pt = _tube(path, tr, 4)
        T += [tuple(t + len(V)) for t in pt]
        V += list(pv)
    V = np.asarray(V)
    T = np.asarray(T, np.int64)
    mat = GEAR_MATERIAL[kind]
    return po.Piece(kind, V, T, np.full(len(T), po.MATS.index(mat)), {"head": np.ones(len(V))},
                    np.full(len(V), -1))


# P65a: the bosses' mantles (P63 used the giant's hide_mantle, which on a hunched brute read as a short ragged top):
# a heavy cloak over the shoulders and the upper back, hanging straight from the shoulder blades to the waist (not
# drawn into the small of the back), shallow in front, its hem a little uneven; a thick collar round the neck's base.
# (boss): the mantle's material and tile, the collar's, the hem's raggedness, how far down the back and the front.
# P65c: from behind both read as boxes (each column of the back pushed out to the hunch above it, up to 30 cm: the
# cloth stood off the small of the back like a crate) and the Matriarch's collar as a rolled sausage of hide round the
# shoulders. Now the back's cloth spans the spine's groove (hull_fill) and hangs at most ``hang_most`` (m) out from
# the back and spans the muscles' hollows (``bridge`` neighbour averages, the giant's 12), so it falls close down the back from the shoulders; the Matriarch's cloak reaches below the waist with a
# ragged hem and her collar is a flat fold of hide lying on the shoulders (``collar_flat``: the roll's height against
# its width), the King's ivory fur collar a softer, lower roll.
MANTLE = {"ogre_king": dict(mat="faction", tile="faction", collar_mat="fur", collar_tile="fur", hem_noise=0.02,
                            back_low=0.0, front_low=0.05, collar_m=0.026, hang_most=0.09, collar_flat=0.7,
                            bridge=40),
          "troll_matriarch": dict(mat="leather", tile="leather", collar_mat="leather", collar_tile="leather",
                                  hem_noise=0.06, back_low=-0.07, front_low=0.05, collar_m=0.030, hang_most=0.10,
                                  collar_flat=0.5, bridge=40,
                                  collar_back_only=True)}


# P65b: behind, the mantle reaches up the nape this far over the neck's joint (m): on the hunched back the shoulders'
# top stands above the neck's joint, and the cut there left a band of mossy skin between the collar and the mantle
MANTLE_NAPE_M = 0.07


def mantle_pieces(w, person, boss, kd):
    """The boss's mantle and its collar (two Pieces, the mantle named hide_mantle): shells of the first variant's
    skin built on its wardrobe after its outfit (so they clear the loincloth and the belt)."""
    import giant_garment as gg
    import people_outfit as po
    st = MANTLE[boss]
    B, z, V, Nn = w.B, w.z, w.V, w.N
    shoulder, neck_z, hip = w.shoulder, w.neck_z, w.hip
    n = w.n
    yc = float(w.J["joint-pelvis"][1])
    back = (Nn[:, 1] > -0.15) & (V[:, 1] > yc - 0.04)
    low = np.where(back, hip + st["back_low"], shoulder - st["front_low"])
    half = abs(float(w.J["joint-l-shoulder"][0]))
    torso_back = back & (np.abs(V[:, 0]) < 0.8 * half) & (B["upperarm"] < 0.5) & (B["lowerarm"] + B["hand"] < 0.05) \
        & (z < shoulder)
    keep = (((B["spine3"] + B["clav"] + B["upperarm"] * (z > shoulder - 0.14) + B["neck"] * 0.5
              + (B["spine2"] + B["spine1"] + 0.6 * B["pelvis"]) * back) > 0.42) | torso_back) \
        & (z > low) & (B["head"] < 0.02) & ((z < neck_z - 0.01) | (back & (z < neck_z + MANTLE_NAPE_M)
                                                                       & (B["neck"] < 0.6))) \
        & (B["lowerarm"] < 0.05) & (B["hand"] < 0.01) & ((w.t_up < 0.32) | (B["upperarm"] < 0.1))
    rng = np.random.default_rng(67)
    lumps = gg.smooth_field(rng.random(n), w.faces, n, 3)
    # (built as the cape's slot, nearer the skin than the shoulders' 4.6 cm: nothing lies under it on a brute)
    off = gg.SLOT_SHELL_M["cape"] + 0.004 + 0.006 * lumps
    off = w.hull_fill(off, keep, shoulder - 0.02, hip - 0.12)
    off = w.hang(off, keep, shoulder - 0.06, column=0.05, most=st["hang_most"])
    w.add_shell("cape", keep, off, seed=67, hem_noise=st["hem_noise"], mat="giant_leather", bridge=st["bridge"])
    mantle = po.garment_piece(w, "cape", person, st["mat"], kd)
    bpy_remove(w.built["cape"][0])
    mantle.name = "hide_mantle"
    return mantle, collar_piece(mantle, w.J["joint-neck"] * person.S, st["collar_m"] * person.S, st["collar_mat"],
                                st["collar_flat"], st.get("collar_back_only", False))


# (gate C) the spine's groove spanned on the collapsed mantle. Offset out from a deep, narrow groove (the spine's,
# between the brutes' heavy back muscles) the shell's sides crossed over its bottom, and the collapse kept slivers
# folded over the spine whose normals turned inward: a small pale diamond in the middle of the back from behind (both
# bosses; P65c's "bright fold"). Each horizontal slice of the back within SPINE_SPAN_REACH of the spine is raised to
# its upper hull (the cloth lies across the groove) within SPINE_SPAN_WIDTH, then that strip smoothed (SPINE_SMOOTH
# Taubin passes, the open edge held).
SPINE_SPAN_REACH = 0.16           # human m either side of the spine: the slice's points the hull is taken over
SPINE_SPAN_WIDTH = 0.07           # human m either side of the spine: the points raised to it
SPINE_SLICE = 0.02                # human m
SPINE_SMOOTH = 20


def _upper_hull(x, y):
    """The upper hull of points (x, y) (their most backward envelope), as sorted (xs, ys)."""
    o = np.lexsort((y, x))
    hull = []
    for p in zip(x[o].tolist(), y[o].tolist()):
        while len(hull) >= 2 and ((hull[-1][0] - hull[-2][0]) * (p[1] - hull[-2][1])
                                  - (hull[-1][1] - hull[-2][1]) * (p[0] - hull[-2][0])) >= 0.0:
            hull.pop()
        hull.append(p)
    h = np.asarray(hull)
    return h[:, 0], h[:, 1]


def span_spine(V, T, yc, S):
    """The mantle's points (design scale, the back +Y) behind the pelvis's middle ``yc`` raised across the spine's
    groove (SPINE_*), then smoothed there (its open edge held)."""
    import people_parts as pp
    V = np.asarray(V, np.float64).copy()
    back = V[:, 1] > yc
    step = SPINE_SLICE * S
    for z in np.arange(float(V[back, 2].min()), float(V[back, 2].max()), step):
        sl = np.nonzero(back & (V[:, 2] >= z - step) & (V[:, 2] < z + 2.0 * step)
                        & (np.abs(V[:, 0]) < SPINE_SPAN_REACH * S))[0]
        if len(sl) < 6 or V[sl, 0].min() > -SPINE_SPAN_WIDTH * S or V[sl, 0].max() < SPINE_SPAN_WIDTH * S:
            continue
        hx, hy = _upper_hull(V[sl, 0], V[sl, 1])
        own = sl[(V[sl, 2] >= z) & (V[sl, 2] < z + step) & (np.abs(V[sl, 0]) < SPINE_SPAN_WIDTH * S)]
        V[own, 1] = np.maximum(V[own, 1], np.interp(V[own, 0], hx, hy))
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    u, cnt = np.unique(e, axis=0, return_counts=True)
    edge = np.zeros(len(V), bool)
    edge[u[cnt == 1].ravel()] = True
    strip = back & (np.abs(V[:, 0]) < SPINE_SPAN_WIDTH * S * 1.5) & ~edge
    return pp.smooth_shell(V, T, it=SPINE_SMOOTH, lam=0.5, keep=~strip, mu=-0.53)

COLLAR_SEGS = (36, 7)              # along the neck's opening, round the roll


def collar_piece(mantle, neck, radius, mat, flat=1.0, back_only=False):
    """A thick roll (a tube of ``radius``, its thickness varying a little like fur) along the mantle's neck opening:
    the mantle's boundary loop nearest the neck's joint, resampled, the roll's middle a little outside it."""
    import people_outfit as po
    V, T = mantle.V, mantle.T
    e = np.sort(np.concatenate([T[:, [0, 1]], T[:, [1, 2]], T[:, [2, 0]]]), axis=1)
    u, c = np.unique(e, axis=0, return_counts=True)
    bnd = u[c == 1]
    nxt = {}
    for a_, b_ in bnd.tolist():
        nxt.setdefault(a_, []).append(b_)
        nxt.setdefault(b_, []).append(a_)
    loops, seen = [], set()
    for start in nxt:
        if start in seen:
            continue
        loop, prev, cur = [start], None, start
        seen.add(start)
        while True:
            cand = [q for q in nxt[cur] if q != prev and q not in seen]
            if not cand:
                break
            prev, cur = cur, cand[0]
            seen.add(cur)
            loop.append(cur)
        if len(loop) > 8:
            loops.append(loop)
    neck = np.asarray(neck, np.float64)
    best = min(loops, key=lambda L: float(np.linalg.norm(V[L].mean(axis=0) - neck)))
    P = V[best]
    cen = P.mean(axis=0)
    # resample the closed loop evenly, smoothed
    seg = np.linalg.norm(np.roll(P, -1, axis=0) - P, axis=1)
    sl = np.concatenate([[0.0], np.cumsum(seg)])
    k_, m_ = COLLAR_SEGS
    tq = np.linspace(0.0, sl[-1], k_, endpoint=False)
    Pc = np.concatenate([P, P[:1]])
    Q = np.stack([np.interp(tq, sl, Pc[:, j]) for j in range(3)], axis=1)
    for _ in range(4):
        Q = 0.5 * Q + 0.25 * (np.roll(Q, 1, axis=0) + np.roll(Q, -1, axis=0))
    tang = np.roll(Q, -1, axis=0) - np.roll(Q, 1, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    out = Q - cen
    out -= tang * np.einsum("ij,ij->i", out, tang)[:, None]
    out /= np.linalg.norm(out, axis=1, keepdims=True)
    up = np.cross(tang, out)
    up *= np.sign(up[:, 2:3] + 1e-9)
    rng = np.random.default_rng(73)
    fl = 1.0 + 0.18 * np.convolve(np.concatenate([rng.random(k_)] * 3) - 0.5, np.ones(3) / 3.0, "same")[k_:2 * k_]
    if back_only:
        # (P65c) the fold round the nape and the shoulders' backs only, thinning to nothing toward the front
        rel_y = (Q[:, 1] - neck[1]) / max(radius, 1e-9)
        fl = fl * np.clip((rel_y + 1.5) / 2.5, 0.0, 1.0) ** 0.7
    Vt = []
    # (flat < 1: a fold lying on the shoulders, wider out over the mantle than it is high)
    wide = 1.0 if flat >= 1.0 else 1.0 + 0.6 * (1.0 - flat)
    for i in range(k_):
        mid = Q[i] + out[i] * radius * (0.55 + 0.6 * (wide - 1.0)) + up[i] * radius * 0.25 * flat
        for j in range(m_):
            ph = 2.0 * math.pi * j / m_
            Vt.append(mid + radius * fl[i] * (math.cos(ph) * wide * out[i] + math.sin(ph) * flat * up[i]))
    Tt = []
    for i in range(k_):
        for j in range(m_):
            a0, b0 = i * m_ + j, i * m_ + (j + 1) % m_
            a1, b1 = ((i + 1) % k_) * m_ + j, ((i + 1) % k_) * m_ + (j + 1) % m_
            Tt += [(a0, a1, b1), (a0, b1, b0)]
    Vt, Tt = np.asarray(Vt), np.asarray(Tt, np.int64)
    nrm = np.cross(Vt[Tt[:, 1]] - Vt[Tt[:, 0]], Vt[Tt[:, 2]] - Vt[Tt[:, 0]])
    cc = Vt[Tt].mean(axis=1)
    ring_mid = Q[(Tt[:, 0] // m_)] + out[(Tt[:, 0] // m_)] * radius * (0.55 + 0.6 * (wide - 1.0))
    if float(np.einsum("ij,ij->i", nrm, cc - ring_mid).sum()) < 0:
        Tt = Tt[:, ::-1]
    return po.Piece("collar", Vt, Tt, np.full(len(Tt), po.MATS.index(mat)), {}, np.full(len(Vt), -1))


def bpy_remove(ob):
    import bpy
    bpy.data.objects.remove(ob, do_unlink=True)


def buckle_piece(belt, S):
    """The war belt's buckle plate: an oval boss at the belt's front (a rim, a raised field, a domed middle)."""
    import people_outfit as po
    V = belt.V
    fy = float(V[:, 1].min())
    front = V[:, 1] < fy + 0.03 * S
    zc = float(np.median(V[front, 2]))
    near = np.abs(V[:, 0]) < 0.06 * S
    hh = 0.5 * float(np.ptp(V[near, 2])) if near.sum() > 3 else 0.04 * S
    ax, az = 1.25 * hh, 0.95 * hh
    segs = 16
    rings = ((1.0, 0.002), (0.96, -0.010), (0.78, -0.012), (0.55, -0.019), (0.25, -0.024))
    P = []
    for rk, dy in rings:
        for k in range(segs):
            a = 2.0 * math.pi * k / segs
            P.append((ax * rk * math.cos(a), fy + dy * S, zc + az * rk * math.sin(a)))
    P.append((0.0, fy - 0.026 * S, zc))
    T = []
    for i in range(len(rings) - 1):
        for k in range(segs):
            a0, b0 = i * segs + k, i * segs + (k + 1) % segs
            T += [(a0, a0 + segs, b0 + segs), (a0, b0 + segs, b0)]
    c = len(P) - 1
    last = (len(rings) - 1) * segs
    T += [(last + k, c, last + (k + 1) % segs) for k in range(segs)]
    P, T = np.asarray(P), np.asarray(T, np.int64)
    # wind outward (toward -y, the front)
    nrm = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    if float(nrm[:, 1].sum()) > 0:
        T = T[:, ::-1]
    return po.Piece("buckle", P, T, np.full(len(T), po.MATS.index("metal")), {}, np.full(len(P), -1))


# ---- the skeleton and the meshes at the kind's scale ------------------------------------------------------------------
def export_rig(person, ref, name, coll, F):
    """people_body.export_rig at the scale F (the kind's height over the design height)."""
    import bpy
    src, rrig = person.rig, ref.rig
    arm = bpy.data.armatures.new(name)
    ob = bpy.data.objects.new(name, arm)
    coll.objects.link(ob)
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for b in pr.BONES:
        sb, rb = src.data.bones[b], rrig.data.bones[b]
        eb = arm.edit_bones.new(b)
        length = (rb.length if b == "Root" else sb.length) * F
        eb.head = (0.0, 0.0, 0.0)
        eb.tail = (0.0, length, 0.0)
        M = rb.matrix_local.to_3x3().to_4x4()
        M.translation = (rb.head_local if b == "Root" else sb.head_local) * F
        eb.matrix = M
        eb.use_deform = True
    for b in pr.BONES:
        p = rrig.data.bones[b].parent
        if p is not None:
            arm.edit_bones[b].parent = arm.edit_bones[p.name]
            arm.edit_bones[b].use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in ob.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return ob


def skinned_object(name, mesh, arm, coll, mat, F):
    import people_outfit as po
    ob = po.mesh_object(name, mesh.V * F, mesh.T, None, mesh.uv, coll)
    ob.data.materials.clear()
    ob.data.materials.append(mat)
    idx, w4 = pr.top4(mesh.groups, len(mesh.V))
    for b in pr.BONES:
        ob.vertex_groups.new(name=b)
    for vi in range(len(mesh.V)):
        for j in range(4):
            if w4[vi, j] > 0.0:
                ob.vertex_groups[int(idx[vi, j])].add([vi], float(w4[vi, j]), "REPLACE")
    ob.parent = arm
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = arm
    return ob


# ---- the clips -------------------------------------------------------------------------------------------------------
def slam_pose(rest, f, frames):
    """The two-arm slam: the feet step wide and the knees bend, both fists go up over the head (the trunk arched back),
    hang, then come down together to the ground in front (the trunk folds forward, the knees deep), and rise."""
    import clips
    t = f / float(frames)
    up = clips.smooth(t / 0.40) if t < 0.55 else 1.0 - clips.smooth((t - 0.55) / 0.12)
    hit = clips.smooth((t - 0.55) / 0.12) * (1.0 - clips.smooth((t - 0.78) / 0.22))
    wide = clips.smooth(t / 0.25) * (1.0 - clips.smooth((t - 0.85) / 0.15))
    pose = clips.Pose(rest)
    pose.offset = np.array([0.0, 0.05 * hit, 0.0])
    pose.set_rel("pelvis", clips.rot(clips.X, -4.0 * up + 24.0 * hit))
    for b, d in (("spine_01", 1.0), ("spine_02", 1.2), ("spine_03", 1.0)):
        pose.set_rel(b, clips.rot(clips.X, d * (-7.0 * up + 13.0 * hit)))
    pose.set_rel("neck_01", clips.rot(clips.X, -6.0 * up - 10.0 * hit))
    pose.set_rel("head", clips.rot(clips.X, -8.0 * up - 10.0 * hit))
    feet = {}
    for s, out in (("l", 1.0), ("r", -1.0)):
        a = clips.rest_ankle(rest, s) + np.array([out * 0.28 * wide, (-0.10 if s == "l" else 0.12) * wide, 0.0])
        feet[s] = (a, out * 14.0 * wide, 0.0, 0.0)
    clips.set_legs(pose, feet, drop=0.03 + 0.10 * wide + 0.36 * hit)
    for s in ("l", "r"):
        clips.set_arm(pose, s, -175.0 * up - 105.0 * hit, 30.0 * up + 6.0 * hit, out_deg=12.0 + 10.0 * (1.0 - up),
                      forward_deg=4.0)
    clips.relaxed_hands(pose, 0.6 + 0.4 * max(up, hit))
    return pose


def _clear_arms(pose):
    for b in ("upperarm_l", "lowerarm_l", "upperarm_r", "lowerarm_r"):
        pose.rel.pop(b, None)


def brute_idle(rest, f, frames):
    import clips
    pose = clips.idle_pose(rest, f, frames)
    _clear_arms(pose)
    ph = 2.0 * math.pi * f / frames
    b = math.sin(ph)
    clips.set_arm(pose, "l", 2.5 * b - 4.0, 22.0, out_deg=ARM_OUT_DEG)
    clips.set_arm(pose, "r", -2.5 * b - 4.0, 22.0, out_deg=ARM_OUT_DEG)
    pose.set_rel("spine_03", clips.rot(clips.X, -2.0 * b))
    return pose


def brute_gait_pose(gait, phi):
    import clips
    pose = gait.pose(phi)
    _clear_arms(pose)
    g = gait.g
    sw = g["arm_swing_deg"] * math.sin(phi)
    el = g["elbow_swing_deg"]
    clips.set_arm(pose, "l", sw, g["elbow_deg"] + el * max(0.0, -math.sin(phi)), out_deg=ARM_OUT_DEG)
    clips.set_arm(pose, "r", -sw, g["elbow_deg"] + el * max(0.0, math.sin(phi)), out_deg=ARM_OUT_DEG)
    return pose


def make_poses(rest, kind):
    import clips
    import people_body as pbody
    clips.configure(step_m=KINDS[kind]["step_m"] / export_scale(kind))
    clips.GAITS.update(BRUTE_GAITS)
    gaits = {"walk": clips.Gait(rest, "brute_walk", CLIP_FRAMES["walk"]),
             "run": clips.Gait(rest, "brute_run", CLIP_FRAMES["run"])}
    poses = {}
    for name, frames in CLIP_FRAMES.items():
        keys = []
        for f in range(frames + 1):
            phi = 2.0 * math.pi * f / frames
            if name == "idle":
                p = brute_idle(rest, f, frames)
            elif name in ("walk", "run"):
                p = brute_gait_pose(gaits[name], phi)
            elif name == "slam":
                p = slam_pose(rest, f, frames)
            elif name == "roar":
                p = clips.roar_pose(rest, f, frames)
            elif name == "brace":
                p = clips.brace_pose(rest, f, frames)
            elif name == "death":
                p = pbody.death_pose(rest, f, frames)
            else:
                p = pbody.grip_pose(rest, name[-1])
            keys.append(p.solve())
        poses[name] = keys
    return poses, gaits


def clip_bones(name):
    return PARTIAL_CLIPS.get(name, pr.BONES)


def tracks(poses, rest_export, F):
    out = {}
    R_pelvis = rest_export["pelvis"][:3, :3]
    for name, keys in poses.items():
        seq = []
        for p in keys:
            basis = {}
            for b in clip_bones(name):
                q = p.basis(b)
                basis[b] = (q.w, q.x, q.y, q.z)
            loc = {}
            if "pelvis" in clip_bones(name):
                loc["pelvis"] = R_pelvis.T @ (p.offset * F)
            seq.append({"basis": basis, "loc": loc})
        out[name] = seq
    return out


def key_actions(arm, trk):
    import bpy
    from mathutils import Quaternion, Vector
    for name in CLIP_FRAMES:
        act = bpy.data.actions.new(name)
        arm.animation_data_create()
        arm.animation_data.action = act
        bones = clip_bones(name)
        for f, k in enumerate(trk[name]):
            for pb in arm.pose.bones:
                pb.rotation_quaternion = Quaternion()
                pb.location = (0.0, 0.0, 0.0)
            for b in bones:
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
    import clips
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
    keep = {n: set(clip_bones(n)) for n in CLIP_FRAMES if n in PARTIAL_CLIPS}
    clips.strip_tracks(path, keep)
    bpy.data.objects.remove(anchor, do_unlink=True)


# ---- the reach bands ---------------------------------------------------------------------------------------------------
def reach_bands(kind, joints_m, height_m):
    """Per box record of the kind: the model (its export-scale joints {bone: (x, y, z) Blender, metres} of a variant
    exported ``height_m`` tall) scaled to the record's height; its shoulder, its reach (upper arm, forearm, wrist to the
    knuckles) against the box rig's pivot and arm: every grip on the box arm's sphere about its pivot is within the
    model's reach when reach >= |pivot - shoulder| + arm; ``ratio`` is reach over that, within 1 +- REACH_TOL."""
    out = {}
    for rec, box in KINDS[kind]["box"].items():
        k = box["height_m"] / height_m
        sh = np.array(joints_m["upperarm_l"]) * k
        reach = joints_m["reach_m"] * k
        # the box pivot in the model's frame: x out to the side, the forward axis -y (Blender), z up
        piv = np.array([box["pivot"][0], -box["pivot"][2], box["pivot"][1]])
        need = float(np.linalg.norm(piv - sh)) + box["arm"]
        out[rec] = {"scale": r6(k), "shoulder_m": [r6(abs(sh[0])), r6(-sh[1]), r6(sh[2])],
                    "pivot_m": [r6(v) for v in box["pivot"]], "arm_m": box["arm"],
                    "pivot_to_shoulder_m": r6(np.linalg.norm(piv - sh)), "reach_m": r6(reach), "need_m": r6(need),
                    "ratio": r6(reach / need), "ok": bool(abs(reach / need - 1.0) <= REACH_TOL)}
    return out


# ---- the skin: the kinds' hides repainted over the bake's skin band --------------------------------------------------
def hide(kind, P, Nrm):
    """(grey albedo multiplier (n,), moss (n,) 0..1, height field (n,)) of a brute's skin at points P (human metres,
    rest) with normals Nrm: the ogre's thick hide (large blotches, a darker back, pale belly, warts and creases), the
    troll's grey skin with moss on the top of the head, the shoulders, the back and the forearms' backs."""
    import people_bake as pbk
    big = pbk.fbm(P, 6.0, 101)
    mid = pbk.fbm(P, 18.0, 103)
    fine = pbk.vnoise(P, 90.0, 107)
    up = np.clip(Nrm[:, 2], -1.0, 1.0)
    back = np.clip(Nrm[:, 1], -1.0, 1.0)               # Blender's +y is the back
    if kind == "ogre":
        warts = np.clip((pbk.vnoise(P, 70.0, 109) - 0.78) / 0.10, 0.0, 1.0)
        grey = 0.86 + 0.16 * (big - 0.5) + 0.08 * (mid - 0.5) + 0.05 * (fine - 0.5)
        grey *= 1.0 - 0.10 * np.clip(back, 0.0, 1.0) * _sstep(P[:, 2], 0.8, 1.2)
        grey *= 1.0 + 0.08 * np.clip(-back, 0.0, 1.0) * _sstep(-P[:, 2], -1.1, -0.8)
        grey *= 1.0 - 0.05 * warts
        height = 0.6 * warts + 0.25 * mid + 0.15 * fine
        return grey, np.zeros(len(P)), height
    # P65a: the moss in patches (a sharper edge, clumps inside), on the shoulders, the back and the scalp, never the
    # face or the front's lower half; its clumps in the normal map
    moss_n = pbk.fbm(P * [1.0, 1.0, 0.6], 9.0, 113)
    clump = pbk.fbm(P, 45.0, 123)
    hz = P[:, 2] / max(float(P[:, 2].max()), 1e-6)
    fwd = np.clip(-back, 0.0, 1.0)
    where = np.clip(0.25 + 0.6 * up + 0.6 * np.clip(back, 0, 1), 0.0, 1.0) * _sstep(hz, 0.58, 0.72) \
        * (1.0 - 0.85 * _sstep(fwd, 0.15, 0.5) * (1.0 - _sstep(hz, 0.80, 0.84) * _sstep(up, 0.6, 0.85))) \
        * (1.0 - _sstep(hz, 0.84, 0.87) * _sstep(fwd, 0.05, 0.3))
    moss = np.clip((where * 0.7 + 1.25 * (moss_n - 0.5) + 0.35 * (clump - 0.5) - 0.42) / 0.07, 0.0, 1.0)
    grey = 0.84 + 0.12 * (big - 0.5) + 0.12 * (mid - 0.5) + 0.06 * (fine - 0.5)
    grey *= 1.0 - 0.18 * np.clip((pbk.vnoise(P, 30.0, 117) - 0.6) / 0.2, 0.0, 1.0)      # dark patches
    height = 0.35 * mid + 0.25 * fine + moss * (0.8 * clump + 0.6 * pbk.vnoise(P, 140.0, 119))
    return grey, moss, height


GARMENT_AO_FLOOR = 0.82
EAR_SOFT_M = (0.006, 0.022)        # round the ears (human m): the bake's normal and occlusion eased (see repaint)


def repaint(kind, out_dir, LV, LT, Luv, tan, sgn, nor, S, ears=None):
    """The bake's skin texels (band skin) repainted with the kind's hide and the troll's moss (a greener, darker tint of
    the skin's band); the hide's height field into the normal map; the kind's tiles. P65a: round the ears (``ears``:
    the ear's vertices, human m) the bake's normal is eased toward the low mesh's and its occlusion lightened - the
    decimated ear is far from the high one, so its texels read the ear's folds in dark blocks."""
    import people_bake as pbk
    from PIL import Image
    from scipy.spatial import cKDTree
    ear_tree = cKDTree(ears) if ears is not None and len(ears) else None
    paths = {k: os.path.join(out_dir, "%s_%s.png" % (kind, k)) for k in ("albedo", "normal", "orm")}
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
        skin = orm[oy, ox, 2] == skin_b
        grey, moss, height = hide(kind, P[skin], Nl[skin])
        if img == "albedo":
            col = alb[ys[skin], xs[skin]] * grey[:, None]
            # the moss: a darker, greener patch of the skin's own band (the palette's skin colour times this tint)
            # (P65b: lighter: from behind, the back read as a dark mass)
            moss_col = col * np.array([0.50, 0.68, 0.33]) * (0.68 + 0.62 * pbk.fbm(P[skin], 45.0, 123))[:, None]
            alb[ys[skin], xs[skin]] = col * (1.0 - moss[:, None]) + moss_col * moss[:, None]
        else:
            # the height field's slope along the tangent frame (finite differences in space)
            e = 0.004
            Tl = np.einsum("nk,nkj->nj", b, tan[t])[skin]
            Bl = np.cross(Nl[skin], Tl) * np.sign(sgn[t[skin], 0])[:, None]
            Ps = P[skin]
            g1 = (hide(kind, Ps + Tl / S * e * S, Nl[skin])[2] - height) / e
            g2 = (hide(kind, Ps + Bl / S * e * S, Nl[skin])[2] - height) / e
            amp = 0.0045 if kind == "ogre" else 0.0035 + 0.0035 * moss
            n0 = nrm[ys[skin], xs[skin]]
            n1 = n0 - np.reshape(amp, (-1, 1)) * np.stack([g1, g2, np.zeros_like(g1)], axis=1)
            n1 /= np.maximum(np.linalg.norm(n1, axis=1, keepdims=True), 1e-9)
            if ear_tree is not None:
                soft = 1.0 - _sstep(ear_tree.query(Ps)[0], EAR_SOFT_M[0], EAR_SOFT_M[1])
                n1 = n1 * (1.0 - 0.8 * soft[:, None]) + np.array([0.0, 0.0, 1.0]) * 0.8 * soft[:, None]
                n1 /= np.maximum(np.linalg.norm(n1, axis=1, keepdims=True), 1e-9)
                if size == pr.ORM_PX:
                    ao = orm[oy[skin], ox[skin], 0].astype(np.float64)
                    orm[oy[skin], ox[skin], 0] = np.round(ao + soft * np.maximum(0.0, 235.0 - ao)).astype(np.uint8)
            nrm[ys[skin], xs[skin]] = n1
    # P65a: the garments' occlusion floored (the loincloth's back flap over the buttocks' cleft read the cleft's
    # occlusion as a dark tear down its middle); the tiles' row along the bottom keeps its own
    rows = int(round((1.0 - pr.TILE_SIZE) * pr.ORM_PX))
    garment = orm[:rows, :, 2] != skin_b
    orm[:rows, :, 0] = np.where(garment, np.maximum(orm[:rows, :, 0], int(round(GARMENT_AO_FLOOR * 255))),
                                orm[:rows, :, 0])
    # the kind's tiles
    for name, (rgb, rough) in TILE_REPAINT.get(kind, {}).items():
        u0, v0 = pr.TILES[name]
        for size, arr in ((pr.ALBEDO_PX, alb), (pr.ORM_PX, orm)):
            x0, x1 = int(round(u0 * size)), int(round((u0 + pr.TILE_SIZE) * size))
            y0, y1 = int(round((1.0 - v0 - pr.TILE_SIZE) * size)), int(round((1.0 - v0) * size))
            if arr is alb:
                yy, xx = np.mgrid[y0:y1, x0:x1]
                P = np.stack([xx.ravel() / size, yy.ravel() / size, np.zeros(xx.size)], -1)
                val = 0.82 + 0.3 * pbk.fbm(P * 3.0, 6.0, 131)
                alb[y0:y1, x0:x1] = (np.array(rgb)[None, :] * val[:, None]).reshape(y1 - y0, x1 - x0, 3)
            else:
                orm[y0:y1, x0:x1, 1] = int(round(rough * 255))
    pbk.save_png(paths["albedo"], pbk.to_u8(np.clip(alb, 0, 1)))
    pbk.save_png(paths["normal"], pbk.to_u8(nrm * 0.5 + 0.5))
    pbk.save_png(paths["orm"], orm)


# ---- the kind ----------------------------------------------------------------------------------------------------------
# P65c: the skin of the crotch and the inner thighs is never culled under the loincloth: the variants carried on the
# shared mesh (the whelp on the troll's) moved the flaps off the hole the first variant's cull left (a gap at the
# crotch, the ground seen through it). (human m: under the hip joints, within this of the middle)
CROTCH_KEEP_M = (0.30, 0.03, 0.11)     # below the hip joints, above them, either side of the middle


def crotch_of(person):
    """A function of design-scale points: True for those in the crotch's band (CROTCH_KEEP_M)."""
    J = person.bd.joints
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    S = person.S
    lo, hi, half = hip - CROTCH_KEEP_M[0], hip + CROTCH_KEEP_M[1], CROTCH_KEEP_M[2]

    def inside(P):
        Q = np.asarray(P) / S
        return (Q[:, 2] > lo) & (Q[:, 2] < hi) & (np.abs(Q[:, 0]) < half)
    return inside


def build_kind(kind, out_dir, work_dir):
    import bpy
    import giant_body as gb
    import people_bake as pbk
    import people_body as pbody
    import people_outfit as po
    from scipy.spatial import cKDTree
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = 30
    spec = KINDS[kind]
    vs = spec["variants"]
    F = export_scale(kind)
    times = {}
    people = []
    for v in vs:
        people.append(brute_person(v, people[0] if people else None))
    p0 = people[0]
    for p in people:
        p.bd.compute_masks(p.weights) if not p.bd.masks else None
    times["bodies"] = round(time.time() - t0, 1)
    # ---- the shared outfit on the first variant's body
    kd0 = cKDTree(p0.bd.verts[:N])
    w0 = po.wardrobe(p0)
    order = po.build_outfit(w0, spec["outfit"])
    garments = [po.garment_piece(w0, gid, p0, po.garment_material(gid, spec["faction"]), kd0) for gid in order]
    reach_c = po.COVER_REACH_M * po.CULL_SLACK / pr.EXPORT_SCALE
    body, culled_skin = po.cull(po.body_piece(p0), garments, reach_c, protect=crotch_of(p0))
    kept = []
    for i, g in enumerate(garments):
        kept.append(po.cull(g, garments[i + 1:], reach_c)[0])
    src = po.merge([body] + kept)
    src.n_body = len(body.V)
    m0 = p0.bd.masks
    # (P65a: the skull's top kept rounder; P65c: the whole head kept more of its triangles, the scalp as the face: the
    # ogre's skull and the troll's cheeks and nose were faceted against the sky)
    face = np.clip(m0["m_head"], 0.0, 1.0) * HEAD_DETAIL
    hands = np.clip(m0["m_hand"], 0.0, 1.0) * 0.45
    detail = np.zeros(len(src.V))
    detail[:src.n_body] = np.maximum(face, hands)[body.attach]
    # ---- the gear (on the first variant, after the outfit) and the variants' own pieces
    gear = {}
    for boss, items in spec["gear"].items():
        pieces = []
        for gid in items:
            built = []                                          # (name, piece, tile, budget or None)
            if gid in ("crown", "bone_crown"):
                built.append((gid, crown_piece(p0, gid), GEAR_TILE[gid], None))   # (its points survive whole)
            elif gid == "hide_mantle":
                mantle, collar = mantle_pieces(w0, p0, boss, kd0)
                built += [(gid, mantle, MANTLE[boss]["tile"], GEAR_BUDGET[gid]),
                          ("collar", collar, MANTLE[boss]["collar_tile"], GEAR_BUDGET["collar"])]
            else:
                p = po.wardrobe_extra(w0, gid, p0, GEAR_STYLE.get((boss, gid), (GEAR_MATERIAL[gid],))[0], kd0)
                built.append((gid, p, GEAR_STYLE.get((boss, gid), (None, GEAR_TILE[gid]))[1], GEAR_BUDGET[gid]))
            for name, p, tile, budget in built:
                if budget is None:
                    V, T, mat = p.V, p.T, p.mat
                else:
                    # (gate C) the mantle collapsed without the mirror's seam: kept down the spine, the two halves'
                    # points beside it folded slivers over it, whose normals turned inward (a pale diamond at the
                    # middle of the back from behind, both bosses)
                    V, T, mat, _ = po.decimate(p.V, p.T, p.mat, budget, "_gear_" + name)
                    if name == "hide_mantle":
                        V = span_spine(V, T, float(w0.J["joint-pelvis"][1]) * p0.S, p0.S)
                if gid in ("crown", "bone_crown"):
                    groups = {"head": np.ones(len(V))}
                else:
                    groups, _near = po.nearest_groups(p0, V, kd0)
                q = po.Piece(name, V, T, mat, groups, np.full(len(V), -1))
                centre = np.array([0.0, float(p0.pelvis[1]), 0.0])
                if gid in ("crown", "bone_crown"):
                    centre = np.array([0.0, float(V[:, 1].mean()), 0.0])
                q.uv = po.tile_uv(q, tile, centre)
                pieces.append(q)
                if gid == "war_belt":
                    bk = buckle_piece(q, p0.S)
                    bk.groups, _near = po.nearest_groups(p0, bk.V, kd0)
                    bk.uv = po.tile_uv(bk, "metal", np.array([0.0, float(bk.V[:, 1].mean()), 0.0]))
                    pieces.append(bk)
        gear[boss] = po.merge(pieces)
        gear[boss].uv = np.concatenate([p.uv for p in pieces])
    extras = []
    for v, person in zip(vs, people):
        own = []
        eyes = po.eye_piece(person)
        eyes.uv = po.eye_uv(eyes)
        own.append(eyes)
        if v["shape"]["tusks"]:
            own.append(tusks_piece(person))
        extras.append(own)
    worst = max(sum(p.tris() for p in ex) for ex in extras)
    budget = TRIS - worst - MARGIN_TRIS
    times["outfit"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the shared mesh
    LV, LT, Lmat, _ = po.decimate(src.V, src.T, src.mat, budget, "_shared_" + kind, detail=detail)
    Luv = po.unwrap(LV, LT, "_uv_" + kind)
    tri, bary, offset = po.correspond(src, LV)
    lgroups = {b: po.interpolate(w, src.T, tri, bary) for b, w in src.groups.items()}
    body0 = p0.body_V()
    meshes = []
    MATS = po.MATS
    for k, (v, person) in enumerate(zip(vs, people)):
        delta = person.body_V() - body0
        Vk = po.interpolate(src.V + delta[src.attach], src.T, tri, bary) + offset
        skin_sel = np.isin(Lmat, [MATS.index("skin"), MATS.index("lips")])
        zeros = np.zeros(len(Vk), np.int64)
        skin = po.Piece("skin", Vk, LT[skin_sel], Lmat[skin_sel], lgroups, zeros, Luv[skin_sel])
        cloth = po.compact_piece(po.Piece("cloth", Vk, LT[~skin_sel], Lmat[~skin_sel], lgroups, zeros,
                                          Luv[~skin_sel]))
        skin_c, _dropped = po.cull(skin, [cloth], reach_c, protect=crotch_of(person))
        final = po.merge([skin_c, cloth] + [po.Piece(p.name, p.V, p.T, p.mat, p.groups, np.zeros(len(p.V), np.int64),
                                                     p.uv) for p in extras[k]])
        if final.tris() > TRIS_MAX:
            raise SystemExit("brute: %s has %d triangles, over %d" % (v["name"], final.tris(), TRIS_MAX))
        meshes.append(final)
    times["shared"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the bake and the hide
    tan, sgn, nor = po.tangents(LV, LT, Luv)
    os.makedirs(out_dir, exist_ok=True)
    bake_info = pbk.bake_role(kind, out_dir, LV, LT, Lmat, Luv, tan, sgn, nor, src, p0, MATS,
                              extra_meshes=[po.merge(extras[0])])
    repaint(kind, out_dir, LV, LT, Luv, tan, sgn, nor, p0.S, ears=p0.bd.verts[:N][p0.bd.masks["m_ears"] > 0.3])
    times["bake"] = round(time.time() - t0 - sum(times.values()), 1)
    # ---- the rigs, the meshes, the gear, the far meshes, the clips
    for o in list(bpy.data.objects):
        o.select_set(False)
    coll = gb._collection("Kind_" + kind)
    mat = bpy.data.materials.new("brute_" + kind)
    exported = []
    poses, gaits = make_poses(p0.rest, kind)
    info = {"kind": kind, "variants": {}, "gear": {}, "times": times, "tris_max": TRIS_MAX, "bake": bake_info,
            "export_scale": r6(F), "height_m": spec["height_m"], "outfit": list(order),
            "shared": {"src_tris": src.tris(), "tris": int(len(LT)), "budget": int(budget),
                       "culled_skin": culled_skin}, "used_by": list(spec["used_by"])}
    rest0 = None
    for k, (v, person, mesh) in enumerate(zip(vs, people, meshes)):
        arm = export_rig(person, p0, v["name"] + "_rig", coll, F)
        ob = skinned_object(v["name"], mesh, arm, coll, mat, F)
        exported += [arm, ob]
        rest = pbody.rest_matrices(arm)
        b53 = person.rig.data.bones
        knuckle = (np.asarray(b53["middle_01_l"].head_local) - np.asarray(b53["hand_l"].head_local)) * F
        reach = (b53["upperarm_l"].length + b53["lowerarm_l"].length) * F + float(np.linalg.norm(knuckle))
        joints = {b: [r6(x) for x in rest[b][:3, 3]] for b in pr.BONES}
        height = float(mesh.V[:, 2].max()) * F
        info["variants"][v["name"]] = {
            "index": k, "tris": mesh.tris(), "verts": int(len(mesh.V)), "height_m": r6(height),
            "game_height_m": v["height_m"], "game_scale": r6(v["height_m"] / height),
            "pieces": [p.name for p in extras[k]], "joints": joints,
            "reach_m": r6(reach),
            "reach_bands": reach_bands(kind, {"upperarm_l": rest["upperarm_l"][:3, 3], "reach_m": reach}, height)
            if k == 0 else {}}
        for sd in ("l", "r"):
            # P65c: the grip landmark in the hand bone's own frame (the file's metres), as the people's
            # (people_body.grip_landmark: where a handle passes through the rest hand's curled fingers, and its line)
            g, ax = person.grip[sd]
            H = rest["hand_" + sd]
            info["variants"][v["name"]]["grip_local_" + sd] = [r6(x) for x in (H[:3, :3].T @ (g * F - H[:3, 3]))]
            info["variants"][v["name"]]["grip_axis_" + sd] = [r6(x) for x in (H[:3, :3].T @ ax)]
        if k > 0:
            # the variant's own record (the whelp's) at its own height
            rec = v["box"]
            box = spec["box"][rec]
            sub = dict(KINDS[kind], box={rec: box})
            saved = KINDS[kind]
            KINDS[kind] = sub
            info["variants"][v["name"]]["reach_bands"] = reach_bands(
                kind, {"upperarm_l": rest["upperarm_l"][:3, 3], "reach_m": reach}, height)
            KINDS[kind] = saved
        else:
            info["variants"][v["name"]]["reach_bands"] = {
                r: e for r, e in info["variants"][v["name"]]["reach_bands"].items()
                if r == v["box"] or r in spec["gear"]}
        if k == 0:
            rest0, arm0 = rest, arm
        # the far mesh: the idle's first key, decimated
        trk_v = tracks({"idle": poses["idle"][:1]}, rest, F)
        G = pbody.fk(rest, pbody.parents_of(arm), trk_v["idle"][0]["basis"], trk_v["idle"][0]["loc"])
        idx4, w4 = pr.top4(mesh.groups, len(mesh.V))
        Pp = pbody.skin_points(mesh.V * F, idx4, w4, rest, G) / F
        Vf, Tf, _mf, uvf = po.decimate(Pp, mesh.T, mesh.mat, FAR_TRIS, "_far_" + v["name"], uv=mesh.uv)
        far = po.mesh_object(v["name"] + "_far", Vf * F, Tf, None, uvf, coll)
        far.data.materials.clear()
        far.data.materials.append(mat)
        exported.append(far)
        info["variants"][v["name"]]["far"] = {"node": v["name"] + "_far", "tris": int(len(Tf))}
    bad = ["%s %s %.3f" % (n, r, b["ratio"]) for n, v in info["variants"].items() for r, b in v["reach_bands"].items()
           if not b["ok"]]
    if bad:
        raise SystemExit("brute: the arms miss the box rigs' reach bands by more than %d %%: %s" % (
            round(REACH_TOL * 100), ", ".join(bad)))
    for boss, g in gear.items():
        if g.tris() > GEAR_TRIS_MAX:
            raise SystemExit("brute: %s's gear has %d triangles, over %d" % (boss, g.tris(), GEAR_TRIS_MAX))
        ob = skinned_object(boss + "_gear", g, arm0, coll, mat, F)
        exported.append(ob)
        info["gear"][boss] = {"node": boss + "_gear", "tris": g.tris(), "pieces": list(spec["gear"][boss]),
                              "on": vs[0]["name"], "game_height_m": spec["box"][boss]["height_m"],
                              "game_scale": r6(spec["box"][boss]["height_m"] / info["variants"][vs[0]["name"]]
                                               ["height_m"])}
    path = os.path.join(out_dir, kind + ".glb")
    po.export(path, exported)
    info["glb_bytes"] = os.path.getsize(path)
    # the clips on the first variant's skeleton
    trk = tracks(poses, rest0, F)
    worst = 0.0
    for name in ("walk", "slam", "death", "idle"):
        for kk in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            G = pbody.fk(rest0, pbody.parents_of(arm0), trk[name][kk]["basis"], trk[name][kk]["loc"])
            for b in ("foot_l", "hand_r", "head", "pelvis"):
                worst = max(worst, float(np.linalg.norm(G[b][:3, 3] - poses[name][kk].P[b] * F)))
    if worst > 1e-4 * F / pr.EXPORT_SCALE:
        raise SystemExit("brute clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    for o in list(bpy.data.objects):
        if o is not arm0 and o.type == "ARMATURE":
            bpy.data.objects.remove(o, do_unlink=True)
    import clips
    export_clips(os.path.join(out_dir, kind + "_clips.glb"), arm0, coll, trk)
    info["clips"] = {"fps": clips.FPS, "step_m": spec["step_m"], "conversion_error_m": r6(worst),
                     "clips": {n: {"frames": f, "loop": n in CLIP_LOOPS, "bones": len(clip_bones(n)),
                                   "partial": n in PARTIAL_CLIPS} for n, f in CLIP_FRAMES.items()},
                     "gaits": {n: {kk: (r6(vv * F) if kk.endswith("_m") else vv)
                                   for kk, vv in clips.measure_gait(g).items()} for n, g in sorted(gaits.items())}}
    times["export"] = round(time.time() - t0 - sum(times.values()), 1)
    info["seconds"] = round(time.time() - t0, 1)
    os.makedirs(work_dir, exist_ok=True)
    with open(os.path.join(work_dir, kind + "_info.json"), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log("%s: %s in %.1f s" % (kind, ", ".join("%s %d" % (n, e["tris"]) for n, e in info["variants"].items()),
                              info["seconds"]))
    return info


if __name__ == "__main__":
    build_kind(sys.argv[1], sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
