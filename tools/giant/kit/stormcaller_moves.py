"""The Stormcaller's clips (D2): key poses solved as the other titans' (``clips.Pose``, the legs by their feet, a hand
placed by ``stoneback.Holder.hold``) and slerped between on eases (``stoneback_moves.keyed``).

He fights with the storm-rod in his right hand - a mast as tall as he is, held a little below its middle (its butt
rests on the ground at his right foot when he stands) - and with his open left hand, which throws the wind. He is
upright and unhurried: between strikes he stands tall with the rod planted beside him; every blow is drawn up high
and brought down with his whole height behind it.

  dormant   (90, a loop) standing in the storm, waiting: the rod planted before him, both hands folded on it, the head
            bowed over them
  wake      (120) his intro: the head lifts, the rod is raised high over him (the storm answers), he roars (WAKE_ROAR)
            and settles into his stance
  idle, walk, run
            upright, the rod planted at his right side (carried leaning forward as he walks), the left hand loose
  slam      (84) the rod raised two-handed over his right shoulder and brought down onto the ground ahead (SLAM_HIT):
            its fork strikes about 20 m out
  sweep     (72) the rod drawn back low on his right, two-handed, and swung round across his front at knee height to
            his left (SWEEP_HIT)
  gust      (66) the left hand drawn back across his chest and flung out open at the giant: the wind (GUST_HIT)
  call      (108) the rod raised high over his head, the left hand raised with it, held while the bolts come down
            (CALL_UP to CALL_END)
  stamp     (42) the right knee raised high, the foot driven down beside him (STAMP_HIT)
  roar2     (78) his second phase: he crouches, then rises with the rod and the left hand thrown up and roars
  chain     (84) the rod levelled two-handed at his right hip and thrust out ahead: the lightning runs along the ground
            (CHAIN_HIT)
  ring      (96) the rod raised upright in both hands over his head and driven down butt-first into the ground before
            him (RING_HIT)
  reel      (60) staggered: a step back, the head snapped back, the rod swinging out
  kneel, rise (24, 36) a greave broken or the storm grounded through him: down on his right knee, the rod planted
            beside him; up again
  death     (120) he sags to his knees, the rod falls from upright, he falls forward on his face, the rod across the
            ground beside him

Body keys are in design metres (the stage-1 giant's, as every titan's), Z up, -Y his front, +X his left; the rod's
offsets are given in real metres and turned into design metres by ``m``.
"""
from __future__ import annotations

import math

import numpy as np

import frostbound_moves as fm
import stoneback_moves as sm

FPS = sm.FPS
FRAMES = {"dormant": 90, "wake": 120, "slam": 84, "sweep": 72, "gust": 66, "call": 108, "stamp": 42, "roar2": 78,
          "chain": 84, "ring": 96, "reel": 60, "kneel": 24, "rise": 36, "death": 120}
LOOPS = ("idle", "walk", "run", "dormant")
SLAM_HIT = 1.65
SWEEP_HIT = 1.25
GUST_HIT = 1.10
CALL_UP = 1.20
CALL_END = 2.80
STAMP_HIT = 0.78
CHAIN_HIT = 1.50
RING_HIT = 2.20
KNEEL_HIT = 0.55
WAKE_ROAR = 2.80
ROAR2_PEAK = 1.45
# the rig's keys of each strike: [start, wound (the end of the draw), hit (the first active tick), past (the end of the
# active phase), end] (scripts/presentation/stormcaller_rig.gd reads them from the manifest)
KEYS = {"slam": [0.0, 1.20, SLAM_HIT, 2.00, FRAMES["slam"] / FPS],
        "sweep": [0.0, 0.90, SWEEP_HIT, 1.65, FRAMES["sweep"] / FPS],
        "gust": [0.0, 0.80, GUST_HIT, 1.60, FRAMES["gust"] / FPS],
        "call": [0.0, CALL_UP, CALL_UP + 0.1, CALL_END, FRAMES["call"] / FPS],
        "stamp": [0.0, 0.50, STAMP_HIT, 0.98, FRAMES["stamp"] / FPS],
        "chain": [0.0, 1.10, CHAIN_HIT, 2.00, FRAMES["chain"] / FPS],
        "ring": [0.0, 1.60, RING_HIT, 2.60, FRAMES["ring"] / FPS],
        "kneel_hit": KNEEL_HIT, "wake_roar": WAKE_ROAR, "roar2_peak": ROAR2_PEAK, "call_up": CALL_UP,
        "call_end": CALL_END}
# the rod's head (the fork's middle) and butt in the rest pose (design; set by the build)
ROD_HEAD = None
ROD_BUTT = None
UP = np.array([0.0, 0.0, 1.0])
# the left hand on the rod: this far (real m) from the right hand's grip toward the butt
LEFT_ON_ROD_M = 2.4
ROD_CLEAR_M = 0.25   # real m: the rod's lowest point is kept this far over the ground in a stance


def _sc():
    import stormcaller as sc
    return sc


def m(x):
    """Real metres -> design metres."""
    return x / _sc().F


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


def arm_len(holder, s):
    return holder.l1[s] + holder.l2[s]


def butt_len():
    sc = _sc()
    return sc.ROD["butt_m"] / sc.F


def head_len():
    sc = _sc()
    return sc.ROD["head_m"] / sc.F


# ----------------------------------------------------------------------------------------------- the rod

def rod_ends(holder, pose):
    """The rod's head and butt posed (design)."""
    r = holder.rest
    h = pose.P["hand_r"]
    D = pose.D["hand_r"]
    if ROD_HEAD is None:
        g, a = holder.grip_posed(pose, "r")
        return g + a * head_len(), g - a * butt_len()
    return h + D @ (ROD_HEAD - r.head["hand_r"]), h + D @ (ROD_BUTT - r.head["hand_r"])


def rod_low(holder, pose):
    hd, bt = rod_ends(holder, pose)
    return min(float(hd[2]), float(bt[2]))


def rod(holder, pose, grip, axis, pole=(-0.7, 0.3, -0.3), left=None, pole_l=(0.7, 0.3, -0.4)):
    """The right hand's grip at ``grip`` with the rod along ``axis`` (toward its head); the left hand on it
    ``left`` real m from the grip toward the butt (None: the left arm is the caller's)."""
    axis = unit(axis)
    holder.hold(pose, "r", np.asarray(grip, np.float64), axis, pole=pole)
    if left is not None:
        holder.hold(pose, "l", np.asarray(grip, np.float64) - axis * m(left), axis, pole=pole_l)
    return pose.solve()


def planted(holder, pose, at_xy, axis=(-0.05, -0.10, 1.0), pole=(-0.7, 0.3, -0.3), left=None):
    """The rod planted: its butt on the ground at ``at_xy`` (design x, y) leaning along ``axis``; the right hand where
    that puts the grip."""
    axis = unit(axis)
    butt = np.array([at_xy[0], at_xy[1], m(0.02)])
    grip = butt + axis * butt_len()
    return rod(holder, pose, grip, axis, pole=pole, left=left)


def lift_rod(holder, pose, clear=ROD_CLEAR_M, pole=(-0.7, 0.3, -0.3), left=None):
    """The rod's grip raised (if need be) until both its ends stand ``clear`` real m over the ground."""
    c = m(clear)
    for _ in range(8):
        low = rod_low(holder, pose)
        if low >= c - 1e-4:
            break
        g, a = holder.grip_posed(pose, "r")
        rod(holder, pose, g + UP * (c - low + m(0.01)), a, pole=pole, left=left)
    return pose


def keep_rod_up(holder, frames, clear=0.1):
    """Every frame of a one-handed clip with the rod lifted where the blend between keys took it into the ground."""
    for p in frames:
        lift_rod(holder, p, clear=clear)
    return frames


def ground_axis(grip, forward, sideways=0.0, clear=0.20):
    clear = m(clear)
    """The rod's line from ``grip`` that puts its head on the ground (``clear`` over it) ahead along ``forward`` (a
    horizontal direction), tilted ``sideways`` toward his left."""
    g = np.asarray(grip, np.float64)
    L = head_len()
    z = (clear - float(g[2])) / L
    z = max(-0.98, min(0.3, z))
    h = math.sqrt(max(1e-6, 1.0 - z * z))
    d = np.array([forward[0] + sideways, forward[1], 0.0])
    d = d / max(np.linalg.norm(d), 1e-6) * h
    return np.array([d[0], d[1], z])


def free_left(pose, swing=-4.0, elbow=20.0, out=None):
    import brute as br
    import clips
    clips.set_arm(pose, "l", swing, elbow, out_deg=br.ARM_OUT_DEG if out is None else out)
    return pose.solve()


def claw(holder, pose, at, palm, along=None, pole=(0.8, 0.3, -0.3)):
    return fm.claw(holder, pose, at, palm, along=along, pole=pole)


# ----------------------------------------------------------------------------------------------- stances

STANCE = {"l": ((0.06, -0.10, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.05, 0.0), -10.0, 0.0, 0.0)}


def idle_pose(holder, rest, f, frames):
    """Upright, the chest out, the head high; the rod planted at his right side leaning a little forward, the right
    hand on it; the left arm hanging loose; a slow breath."""
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    pose = sm.body(rest, pelvis=(1.0, 0.0, 2.0), spine=(-1.0 + 0.8 * b, 0.0, 1.0), neck=(-2.0, 0.0),
                   head=(-3.0 - 0.5 * b, 0.0, -2.0), drop=0.05 + 0.004 * b, clav=(-1.0 - 1.5 * b, -1.0 - 1.5 * b),
                   feet=STANCE)
    sh = pose.P["upperarm_r"]
    L = arm_len(holder, "r")
    planted(holder, pose, (sh[0] - 0.30 * L, sh[1] - 0.26 * L), axis=(-0.03, -0.10, 1.0))
    free_left(pose, -4.0 + 2.0 * b, 18.0)
    return pose.solve()


def idle0(holder, rest):
    return idle_pose(holder, rest, 0, 60)


def gait_pose(holder, gait, phi, run=False):
    import brute as br
    pose = br.brute_gait_pose(gait, phi)
    pose.solve()
    sw = math.sin(phi)
    sh = pose.P["upperarm_r"]
    L = arm_len(holder, "r")
    k = 1.5 if run else 1.0
    grip = sh + np.array([-0.20 * L, -0.30 * L - 0.14 * L * sw * k, -0.74 * L])
    rod(holder, pose, grip, (-0.05, -0.50 - (0.25 if run else 0.0), 1.0))
    lift_rod(holder, pose, clear=0.6)
    return pose.solve()


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0, bow=0.0):
    """Down on his right knee (Stoneback's kneel's legs), the left foot forward, the left hand on the raised left knee;
    the rod planted beside the right knee."""
    l1, l2 = sm._leg_lengths(rest, "r")
    pel = (7.0 * lean + 6.0 * bow, 0.0, -4.0)
    spine = (8.0 * lean + 12.0 * bow, 0.0, -2.0)
    probe = sm.body(rest, pelvis=pel, spine=spine, drop=0.03)
    hip = probe.P["thigh_r"].copy()
    want_z = l1 * 0.985 + sm.KNEE_R + settle
    full = max(0.03, float(hip[2]) + 0.03 - want_z)
    drop = 0.03 + (full - 0.03) * depth
    hip_z = float(hip[2]) + 0.03 - drop
    knee = np.array([hip[0] - 0.02, hip[1] - 0.04, hip_z - l1 * 0.985])
    back = math.sqrt(max(1e-6, l2 * l2 * 0.97 - max(0.0, knee[2] - 0.15) ** 2))
    ankle_r = np.array([knee[0] + 0.02, knee[1] + back * depth + 0.08 * (1.0 - depth), 0.15])
    ankle_r[2] = max(ankle_r[2], float(rest.head["foot_r"][2]))
    feet = {"l": ((0.08, -0.62 * min(1.0, depth * 1.4), 0.0), 10.0, 0.0, 0.0),
            "r": (tuple(ankle_r - rest.head["foot_r"]), -8.0, 58.0 * depth, 34.0 * depth)}
    k = sm.body(rest, pelvis=pel, spine=spine, neck=(8.0 * lean + 16.0 * bow, -4.0),
                head=(8.0 * lean + 14.0 * bow, 0.0, -6.0), feet=feet, drop=drop, clav=(4.0, 6.0))
    kn = k.P["calf_l"]
    claw(holder, k, kn + np.array([-0.02, -0.06, 0.10]), (0.0, 0.0, -1.0), along=(-0.2, -1.0, -0.2))
    sh = k.P["upperarm_r"]
    L = arm_len(holder, "r")
    planted(holder, k, (sh[0] - 0.34 * L, sh[1] - 0.30 * L), axis=(-0.06, -0.12, 1.0))
    lift_rod(holder, k, clear=0.0)
    return k.solve()


def dormant_pose(holder, rest, f, frames):
    """Waiting in the storm: the rod planted before him, both hands folded on it at its grip, the head bowed."""
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    k = sm.body(rest, pelvis=(3.0, 0.0, 0.0), spine=(6.0 + 0.6 * b, 0.0, 0.0), neck=(12.0, 0.0),
                head=(16.0 + 0.8 * b, 0.0, 0.0), drop=0.07, feet={"l": ((0.10, -0.06, 0.0), 12.0, 0.0, 0.0),
                                                                 "r": ((-0.10, -0.02, 0.0), -12.0, 0.0, 0.0)},
                clav=(6.0, 6.0))
    pel = k.P["pelvis"]
    # (the left hand above the right on the rod: left=-1.1 puts it 1.1 m toward the head)
    planted(holder, k, (pel[0] - m(0.4), pel[1] - m(4.6)), axis=(0.0, 0.03, 1.0), pole=(-0.6, 0.2, -0.8), left=-1.1)
    return k.solve()


# ----------------------------------------------------------------------------------------------- strikes

def _raised_key(holder, rest, wide=1.0, crouch=0.0, head_back=1.0):
    """The rod raised high over his right shoulder, upright, the left hand thrown up and out, the head back (the
    call, the wake's roar, his second phase's)."""
    k = sm.body(rest, pelvis=(-3.0 + 10.0 * crouch, 0.0, 0.0), spine=(-8.0 * wide + 16.0 * crouch, 0.0, 0.0),
                neck=(-12.0 * head_back, 0.0), head=(-18.0 * head_back, 0.0, 0.0), drop=0.08 + 0.22 * crouch,
                clav=(-12.0 * wide, -14.0 * wide),
                feet={"l": ((0.12, -0.18, 0.0), 14.0, 0.0, 0.0), "r": ((-0.12, 0.12, 0.0), -14.0, 0.0, 0.0)})
    sh = k.P["upperarm_r"]
    L = arm_len(holder, "r")
    grip = sh + np.array([-0.26 * L, -0.08 * L, (0.88 * wide - 0.5 * crouch) * L])
    rod(holder, k, grip, (-0.10, -0.12, 1.0), pole=(-0.8, 0.4, 0.2))
    sl = k.P["upperarm_l"]
    claw(holder, k, sl + np.array([0.62 * L, -0.25 * L, (0.62 * wide - 0.5 * crouch) * L]), (0.0, -1.0, 0.3),
         along=(0.6, -0.2, 0.7))
    lift_rod(holder, k, clear=0.0)
    return k.solve()


def wake(holder, rest):
    k0 = dormant_pose(holder, rest, 0, FRAMES["dormant"])
    k1 = sm.body(rest, pelvis=(2.0, 0.0, 0.0), spine=(2.0, 0.0, 0.0), neck=(-2.0, 0.0), head=(-6.0, 0.0, 0.0),
                 drop=0.07, feet={"l": ((0.10, -0.06, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, -0.02, 0.0), -12.0, 0.0, 0.0)},
                 clav=(4.0, 4.0))
    pel = k1.P["pelvis"]
    planted(holder, k1, (pel[0] - m(0.4), pel[1] - m(4.6)), axis=(0.0, 0.03, 1.0), pole=(-0.6, 0.2, -0.8), left=-1.1)
    kc = _raised_key(holder, rest, 0.4, crouch=0.5, head_back=0.2)
    kr = _raised_key(holder, rest, 1.0)
    keys = [(0.0, k0, "smooth"), (0.80, k1, "smooth"), (1.70, kc, "smooth"), (WAKE_ROAR, kr, "out"),
            (3.40, kr, "linear"), (FRAMES["wake"] / FPS, idle0(holder, rest), "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["wake"])


def roar2(holder, rest):
    k0 = idle0(holder, rest)
    kc = _raised_key(holder, rest, 0.2, crouch=1.0, head_back=0.0)
    kr = _raised_key(holder, rest, 1.1)
    keys = [(0.0, k0, "smooth"), (0.70, kc, "smooth"), (ROAR2_PEAK, kr, "out"), (2.15, kr, "linear"),
            (FRAMES["roar2"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["roar2"])


def call(holder, rest):
    """The rod raised high over his head and held, the left hand up with it, the head back to the sky."""
    k0 = idle0(holder, rest)
    kc = _raised_key(holder, rest, 0.35, crouch=0.35, head_back=0.3)
    kr = _raised_key(holder, rest, 1.0)
    kh = _raised_key(holder, rest, 1.05, head_back=1.2)
    keys = [(0.0, k0, "smooth"), (0.55, kc, "smooth"), (CALL_UP, kr, "out"), (2.0, kh, "smooth"),
            (CALL_END, kr, "smooth"), (FRAMES["call"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["call"])


def slam(holder, rest):
    """The rod raised two-handed over his right shoulder, its head back and up, and brought down onto the ground
    ahead: the fork strikes about 20 m out, the butt swinging up behind him past his right shoulder."""
    k0 = idle0(holder, rest)
    feet = {"l": ((0.10, -0.36, 0.0), 8.0, 0.0, 0.0), "r": ((-0.14, 0.24, 0.0), -18.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(-6.0, 0.0, -14.0), spine=(-10.0, 0.0, -14.0), neck=(-4.0, 8.0), head=(-6.0, 0.0, 10.0),
                 drop=0.14, feet=feet, clav=(-12.0, -18.0))
    hd = kw.P["head"]
    L = arm_len(holder, "r")
    rod(holder, kw, hd + np.array([-0.32 * L, 0.10 * L, 0.20 * L]), (0.10, 0.55, 0.83), pole=(-0.6, 0.6, -0.4),
        left=LEFT_ON_ROD_M, pole_l=(0.6, 0.0, -0.8))
    kh = sm.body(rest, pelvis=(26.0, 0.0, 8.0), spine=(14.0, 0.0, 6.0), neck=(-14.0, -4.0), head=(-12.0, 0.0, -6.0),
                 drop=0.40, feet=feet, clav=(2.0, 10.0))
    sh = kh.P["upperarm_r"]
    # (the grip held out at his right side, the rod's line beside him: its butt swings up past his right shoulder)
    g = sh + np.array([-0.42 * L, -0.62 * L, -0.78 * L])
    rod(holder, kh, g, ground_axis(g, (0.0, -1.0), sideways=0.22, clear=0.5), pole=(-0.8, 0.4, 0.2),
        left=LEFT_ON_ROD_M, pole_l=(0.7, 0.2, 0.2))
    kp = sm.body(rest, pelvis=(29.0, 0.0, 9.0), spine=(16.0, 0.0, 7.0), neck=(-16.0, -4.0), head=(-14.0, 0.0, -8.0),
                 drop=0.44, feet=feet, clav=(2.0, 10.0))
    hd_pt, _bt = rod_ends(holder, kh)
    sh = kp.P["upperarm_r"]
    g2 = sh + np.array([-0.42 * L, -0.62 * L, -0.84 * L])
    to = hd_pt - g2
    rod(holder, kp, g2, to / np.linalg.norm(to), pole=(-0.8, 0.4, 0.2), left=LEFT_ON_ROD_M, pole_l=(0.7, 0.2, 0.2))
    keys = [(0.0, k0, "smooth"), (1.20, kw, "out"), (SLAM_HIT, kh, "in"), (2.00, kp, "out"), (2.25, kp, "linear"),
            (FRAMES["slam"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["slam"])


def sweep(holder, rest):
    """The rod drawn back low on his right, two-handed, and swung round across his front at knee height to his left."""
    k0 = idle0(holder, rest)
    L = arm_len(holder, "r")
    wide = {"l": ((0.14, -0.22, 0.0), 14.0, 0.0, 0.0), "r": ((-0.18, 0.18, 0.0), -24.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(6.0, 0.0, -26.0), spine=(5.0, 3.0, -22.0), neck=(0.0, 20.0), head=(-4.0, 0.0, 14.0),
                 drop=0.30, feet=wide, side=0.05)
    sh = kw.P["upperarm_r"]
    g = sh + np.array([-0.45 * L, 0.10 * L, -0.80 * L])
    rod(holder, kw, g, (-0.55, 0.80, -0.22), pole=(-0.5, 0.6, -0.4), left=LEFT_ON_ROD_M, pole_l=(0.3, 0.6, -0.4))
    lift_rod(holder, kw, left=LEFT_ON_ROD_M)
    kh = sm.body(rest, pelvis=(8.0, 0.0, 8.0), spine=(6.0, -2.0, 10.0), neck=(0.0, -4.0), head=(-6.0, 0.0, -4.0),
                 feet=wide, drop=0.32)
    sh = kh.P["upperarm_r"]
    g = sh + np.array([-0.30 * L, -0.55 * L, -0.80 * L])
    rod(holder, kh, g, (0.18, -0.95, -0.30), pole=(-0.7, 0.0, -0.5), left=LEFT_ON_ROD_M, pole_l=(0.7, 0.0, -0.5))
    lift_rod(holder, kh, left=LEFT_ON_ROD_M)
    kf = sm.body(rest, pelvis=(8.0, 0.0, 30.0), spine=(5.0, -4.0, 24.0), neck=(0.0, -14.0), head=(-4.0, 0.0, -12.0),
                 feet=wide, drop=0.28, side=-0.03)
    sh = kf.P["upperarm_r"]
    g = sh + np.array([0.20 * L, -0.62 * L, -0.72 * L])
    rod(holder, kf, g, (0.88, -0.38, -0.25), pole=(-0.4, -0.4, -0.5), left=LEFT_ON_ROD_M, pole_l=(0.6, 0.3, -0.5))
    lift_rod(holder, kf, left=LEFT_ON_ROD_M)
    keys = [(0.0, k0, "smooth"), (0.90, kw, "out"), (SWEEP_HIT, kh, "in"), (1.65, kf, "out"),
            (FRAMES["sweep"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["sweep"])


def gust(holder, rest):
    """The left hand drawn back across his chest and flung out open toward the giant, his weight thrown after it; the
    rod stays planted at his right."""
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    feet = {"l": ((0.10, -0.30, 0.0), 10.0, 0.0, 0.0), "r": ((-0.10, 0.20, 0.0), -14.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(2.0, 0.0, -16.0), spine=(2.0, 0.0, -18.0), neck=(-4.0, 8.0), head=(-4.0, 0.0, 10.0),
                 drop=0.14, feet=feet, clav=(12.0, 0.0))
    sh_r = kw.P["upperarm_r"]
    claw(holder, kw, sh_r + np.array([0.0, -0.32 * L, 0.05 * L]), (-1.0, 0.0, 0.0), along=(-0.3, -0.2, 1.0),
         pole=(0.2, 0.6, -0.8))
    sh = kw.P["upperarm_r"]
    planted(holder, kw, (sh[0] - 0.30 * L, sh[1] - 0.22 * L), axis=(-0.04, -0.06, 1.0))
    kh = sm.body(rest, pelvis=(10.0, 0.0, 14.0), spine=(10.0, 0.0, 16.0), neck=(-10.0, -6.0), head=(-10.0, 0.0, -8.0),
                 drop=0.24, feet=feet, clav=(-10.0, 0.0))
    sl = kh.P["upperarm_l"]
    claw(holder, kh, sl + np.array([0.10 * L, -0.92 * L, 0.18 * L]), (0.0, -1.0, 0.1), along=(0.0, -0.15, 1.0),
         pole=(0.8, 0.2, -0.6))
    sh = kh.P["upperarm_r"]
    planted(holder, kh, (sh[0] - 0.36 * L, sh[1] - 0.30 * L), axis=(-0.04, -0.14, 1.0))
    kf = sm.body(rest, pelvis=(10.0, 0.0, 18.0), spine=(10.0, 0.0, 18.0), neck=(-10.0, -8.0), head=(-10.0, 0.0, -10.0),
                 drop=0.24, feet=feet, clav=(-8.0, 0.0))
    sl = kf.P["upperarm_l"]
    claw(holder, kf, sl + np.array([0.30 * L, -0.86 * L, 0.10 * L]), (0.3, -1.0, 0.0), along=(0.2, -0.2, 1.0),
         pole=(0.8, 0.2, -0.6))
    sh = kf.P["upperarm_r"]
    planted(holder, kf, (sh[0] - 0.36 * L, sh[1] - 0.30 * L), axis=(-0.04, -0.14, 1.0))
    keys = [(0.0, k0, "smooth"), (0.80, kw, "out"), (GUST_HIT, kh, "in"), (1.60, kf, "out"),
            (FRAMES["gust"] / FPS, k0, "smooth")]
    return keep_rod_up(holder, sm.keyed(holder, rest, keys, FRAMES["gust"]))


def stamp(holder, rest):
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    ku = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-4.0, 0.0, 0.0), neck=(4.0, 0.0), head=(10.0, 0.0, 0.0),
                 drop=0.10, side=0.05,
                 feet={"l": ((0.04, 0.02, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, -0.22, 0.40), -6.0, -18.0, 0.0)})
    sl = ku.P["upperarm_l"]
    claw(holder, ku, sl + np.array([0.55 * L, -0.25 * L, -0.55 * L]), (0.6, -0.4, 0.0), along=(0.6, -0.3, -0.7))
    sh = ku.P["upperarm_r"]
    rod(holder, ku, sh + np.array([-0.40 * L, -0.10 * L, -0.62 * L]), (-0.10, -0.25, 1.0))
    lift_rod(holder, ku, clear=0.4)
    kh = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(10.0, 0.0, 0.0), neck=(-6.0, 0.0), head=(-8.0, 0.0, 0.0),
                 drop=0.30, side=-0.02,
                 feet={"l": ((0.06, 0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.08, -0.32, 0.0), -10.0, 0.0, 0.0)})
    sl = kh.P["upperarm_l"]
    claw(holder, kh, sl + np.array([0.45 * L, -0.30 * L, -0.65 * L]), (0.6, -0.4, 0.0), along=(0.5, -0.3, -0.8))
    sh = kh.P["upperarm_r"]
    planted(holder, kh, (sh[0] - 0.42 * L, sh[1] - 0.28 * L), axis=(-0.06, -0.10, 1.0))
    keys = [(0.0, k0, "smooth"), (0.50, ku, "out"), (STAMP_HIT, kh, "in"), (0.98, kh, "linear"),
            (FRAMES["stamp"] / FPS, k0, "smooth")]
    return keep_rod_up(holder, sm.keyed(holder, rest, keys, FRAMES["stamp"]))


def chain(holder, rest):
    """The rod levelled two-handed at his right hip, drawn back, and thrust out ahead and down: its fork points at the
    ground 15-20 m before him, where the lightning runs out along the ground."""
    k0 = idle0(holder, rest)
    L = arm_len(holder, "r")
    feet = {"l": ((0.10, -0.40, 0.0), 8.0, 0.0, 0.0), "r": ((-0.12, 0.26, 0.0), -20.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(-2.0, 0.0, -18.0), spine=(-4.0, 0.0, -16.0), neck=(-2.0, 10.0), head=(-4.0, 0.0, 12.0),
                 drop=0.20, feet=feet, back=0.05)
    sh = kw.P["upperarm_r"]
    g = sh + np.array([-0.30 * L, 0.20 * L, -0.55 * L])
    rod(holder, kw, g, (0.08, -0.96, 0.10), pole=(-0.8, 0.4, -0.2), left=LEFT_ON_ROD_M, pole_l=(0.6, 0.4, -0.6))
    lift_rod(holder, kw, left=LEFT_ON_ROD_M)
    kh = sm.body(rest, pelvis=(16.0, 0.0, 6.0), spine=(14.0, 0.0, 8.0), neck=(-12.0, -4.0), head=(-12.0, 0.0, -6.0),
                 drop=0.36, feet=feet)
    sh = kh.P["upperarm_r"]
    g = sh + np.array([-0.06 * L, -0.80 * L, -0.42 * L])
    rod(holder, kh, g, (0.10, -0.92, -0.38), pole=(-0.8, 0.3, -0.3), left=LEFT_ON_ROD_M, pole_l=(0.7, 0.3, -0.5))
    lift_rod(holder, kh, left=LEFT_ON_ROD_M)
    kp = sm.body(rest, pelvis=(18.0, 0.0, 6.0), spine=(15.0, 0.0, 8.0), neck=(-12.0, -4.0), head=(-12.0, 0.0, -6.0),
                 drop=0.38, feet=feet)
    sh = kp.P["upperarm_r"]
    g = sh + np.array([-0.06 * L, -0.84 * L, -0.46 * L])
    rod(holder, kp, g, (0.10, -0.90, -0.42), pole=(-0.8, 0.3, -0.3), left=LEFT_ON_ROD_M, pole_l=(0.7, 0.3, -0.5))
    lift_rod(holder, kp, left=LEFT_ON_ROD_M)
    keys = [(0.0, k0, "smooth"), (1.10, kw, "out"), (CHAIN_HIT, kh, "in"), (2.00, kp, "out"),
            (FRAMES["chain"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["chain"])


def ring(holder, rest):
    """The rod raised upright in both hands high before him, then driven down butt-first into the ground at his feet."""
    k0 = idle0(holder, rest)
    feet = {"l": ((0.16, -0.12, 0.0), 14.0, 0.0, 0.0), "r": ((-0.16, 0.10, 0.0), -14.0, 0.0, 0.0)}
    kr = sm.body(rest, pelvis=(-4.0, 0.0, 0.0), spine=(-10.0, 0.0, 0.0), neck=(-10.0, 0.0), head=(-14.0, 0.0, 0.0),
                 drop=0.04, lift=0.03, feet=feet, clav=(-16.0, -16.0))
    pel = kr.P["pelvis"]
    hd = kr.P["head"]
    grip = np.array([pel[0] - m(0.3), pel[1] - m(3.6), hd[2] + m(2.6)])
    rod(holder, kr, grip, (0.0, 0.0, 1.0), pole=(-0.6, 0.4, -0.6), left=-1.4, pole_l=(0.6, 0.4, -0.6))
    kh = sm.body(rest, pelvis=(20.0, 0.0, 0.0), spine=(16.0, 0.0, 0.0), neck=(-12.0, 0.0), head=(-10.0, 0.0, 0.0),
                 drop=0.42, feet=feet, clav=(8.0, 8.0))
    pel = kh.P["pelvis"]
    planted(holder, kh, (pel[0] - m(0.3), pel[1] - m(5.2)), axis=(0.0, 0.0, 1.0), pole=(-0.7, 0.4, -0.6), left=-1.4)
    keys = [(0.0, k0, "smooth"), (1.10, kr, "smooth"), (1.60, kr, "linear"), (RING_HIT, kh, "in"),
            (2.60, kh, "linear"), (FRAMES["ring"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["ring"])


def reel(holder, rest):
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 4.0), spine=(-12.0, 2.0, 4.0), neck=(-12.0, 6.0), head=(-20.0, 4.0, 8.0),
                 back=0.12, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.40, 0.0), -16.0, 0.0, 0.0)},
                 drop=0.12)
    sl = k1.P["upperarm_l"]
    claw(holder, k1, sl + np.array([0.70 * L, -0.20 * L, -0.30 * L]), (0.4, -0.8, 0.0), along=(0.8, -0.2, 0.3))
    sh = k1.P["upperarm_r"]
    rod(holder, k1, sh + np.array([-0.60 * L, -0.05 * L, -0.45 * L]), (-0.45, -0.15, 1.0))
    lift_rod(holder, k1, clear=0.5)
    k2 = sm.body(rest, pelvis=(12.0, 0.0, -6.0), spine=(10.0, -3.0, -4.0), neck=(12.0, -6.0), head=(14.0, 0.0, -10.0),
                 back=0.12, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.36, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.30)
    sl = k2.P["upperarm_l"]
    claw(holder, k2, sl + np.array([0.20 * L, -0.40 * L, -0.80 * L]), (0.0, -0.6, 0.0), along=(0.1, -0.4, -1.0))
    sh = k2.P["upperarm_r"]
    planted(holder, k2, (sh[0] - 0.40 * L, sh[1] - 0.36 * L), axis=(-0.08, -0.16, 1.0))
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.85, k2, "smooth"), (FRAMES["reel"] / FPS, k0, "smooth")]
    return keep_rod_up(holder, sm.keyed(holder, rest, keys, FRAMES["reel"]))


def kneel(holder, rest):
    k0 = idle0(holder, rest)
    kb = kneel_key(holder, rest, depth=0.45, lean=1.2)
    kh = kneel_key(holder, rest, depth=1.0, lean=0.9)
    ks = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    keys = [(0.0, k0, "smooth"), (0.28, kb, "in"), (KNEEL_HIT, kh, "in"), (FRAMES["kneel"] / FPS, ks, "out")]
    return sm.keyed(holder, rest, keys, FRAMES["kneel"])


def rise(holder, rest):
    k0 = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    kp = kneel_key(holder, rest, depth=0.85, lean=1.3)
    ku = kneel_key(holder, rest, depth=0.35, lean=0.9)
    keys = [(0.0, k0, "smooth"), (0.35, kp, "smooth"), (0.80, ku, "out"),
            (FRAMES["rise"] / FPS, idle0(holder, rest), "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["rise"])


def death(holder, rest):
    import clips
    from clips import X, Y, Z, rot
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 6.0), spine=(-10.0, 2.0, 4.0), neck=(-14.0, 4.0), head=(-22.0, 4.0, 6.0),
                 back=0.10, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.30, 0.0), -14.0, 0.0, 0.0)},
                 drop=0.12)
    sl = k1.P["upperarm_l"]
    claw(holder, k1, sl + np.array([0.40 * L, 0.0, -0.80 * L]), (0.6, 0.0, 0.0), along=(0.3, 0.1, -1.0))
    sh = k1.P["upperarm_r"]
    rod(holder, k1, sh + np.array([-0.45 * L, -0.10 * L, -0.55 * L]), (-0.30, -0.30, 1.0))
    lift_rod(holder, k1, clear=0.3)
    kn = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(16.0, 0.0, 0.0), neck=(12.0, 0.0), head=(16.0, 0.0, -6.0),
                 feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)}, drop=1.0)
    clips.set_arm(kn, "l", -10.0, 30.0, out_deg=30.0)
    kn.solve()
    sh = kn.P["upperarm_r"]
    rod(holder, kn, sh + np.array([-0.55 * L, -0.30 * L, -0.40 * L]), (-0.70, -0.45, 0.55))
    lift_rod(holder, kn, clear=0.2)
    down = clips.Pose(rest)
    pz = float(rest.head["pelvis"][2])
    down.offset = np.array([0.0, -0.52, -pz + 0.24])
    down.set_rel("pelvis", rot(X, 84.0) @ rot(Y, -4.0))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        down.set_rel(b, rot(X, 2.0 * k))
    down.set_rel("neck_01", rot(X, -18.0))
    down.set_rel("head", rot(X, -14.0) @ rot(Z, 40.0))
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        down.set_rel("thigh_" + s, rot(X, -76.0) @ rot(Z, 6.0 * sgn))
        down.set_rel("calf_" + s, rot(X, 10.0))
        down.set_rel("foot_" + s, rot(X, -30.0))
    down.solve()
    clips.set_arm(down, "l", -60.0, 20.0, out_deg=70.0)
    down.solve()
    # the right arm flung out ahead and to his right on the ground, the rod lying flat along the ground beside him
    sh = down.P["upperarm_r"]
    R = _sc().ROD["radius_m"] / _sc().F
    g = np.array([sh[0] - 0.55 * L, sh[1] - 0.55 * L, R + m(0.25)])
    rod(holder, down, g, (-0.25, -0.97, 0.0), pole=(-0.4, 0.2, 0.9))
    keys = [(0.0, k0, "smooth"), (0.45, k1, "out"), (1.40, kn, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- all of them

CLIP_FUNCS = {"wake": wake, "slam": slam, "sweep": sweep, "gust": gust, "call": call, "stamp": stamp, "roar2": roar2,
              "chain": chain, "ring": ring, "reel": reel, "kneel": kneel, "rise": rise, "death": death}


def make_poses(person, pieces, holder):
    """Every clip's solved frames: {name: [pose, ...]}, the gaits, and the checks (his crown's height in the stances
    and the gaits; the rod's lowest point over the ground in the stances and where its head is at each blow; the
    kneel's bones; each plate's place in the idle)."""
    import clips
    sc = _sc()
    rest = person.rest
    gaits = {"walk": clips.Gait(rest, "stormcaller_walk", 32), "run": clips.Gait(rest, "stormcaller_run", 32)}
    poses = {"idle": [idle_pose(holder, rest, f, 60) for f in range(61)],
             "walk": [gait_pose(holder, gaits["walk"], 2.0 * math.pi * f / 32) for f in range(33)],
             "run": [gait_pose(holder, gaits["run"], 2.0 * math.pi * f / 32, run=True) for f in range(33)],
             "dormant": [dormant_pose(holder, rest, f, FRAMES["dormant"]) for f in range(FRAMES["dormant"] + 1)]}
    for name in FRAMES:
        if name in poses:
            continue
        poses[name] = CLIP_FUNCS[name](holder, rest)
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]

    def crown(p):
        return float((p.P["head"] + p.D["head"] @ local)[2]) * sc.F
    checks = {"crown_m": {c: [br6(min(crown(p) for p in poses[c])), br6(max(crown(p) for p in poses[c]))]
                          for c in ("idle", "dormant", "walk", "run", "wake", "roar2", "call")}}
    checks["rod_low_m"] = {c: br6(min(rod_low(holder, p) for p in poses[c]) * sc.F)
                           for c in ("idle", "walk", "run", "dormant", "gust", "call", "stamp", "kneel", "reel")}

    def head_at(clip, t):
        p = poses[clip][min(len(poses[clip]) - 1, int(round(t * FPS)))]
        hd, _bt = rod_ends(holder, p)
        a = sm_actor(hd) * sc.F
        return [br6(a[0]), br6(a[1]), br6(a[2])]

    def butt_at(clip, t):
        p = poses[clip][min(len(poses[clip]) - 1, int(round(t * FPS)))]
        _hd, bt = rod_ends(holder, p)
        a = sm_actor(bt) * sc.F
        return [br6(a[0]), br6(a[1]), br6(a[2])]
    checks["rod_head_at_blow_m"] = {"slam": head_at("slam", SLAM_HIT), "sweep": head_at("sweep", SWEEP_HIT),
                                    "chain": head_at("chain", CHAIN_HIT), "call": head_at("call", 2.0)}
    checks["rod_butt_at_blow_m"] = {"ring": butt_at("ring", RING_HIT), "slam": butt_at("slam", SLAM_HIT)}
    checks["kneel"] = kneel_frames(person, poses)
    checks["idle_pieces"] = idle_pieces(person, poses, pieces)
    return poses, gaits, checks


def br6(x):
    import brute as br
    return br.r6(x)


def sm_actor(p):
    import stoneback as sb
    return sb.TO_ACTOR @ np.asarray(p)


def idle_pieces(person, poses, pieces):
    """Each plate's centre and extent, posed by the idle's first key, in his actor's space (real m: +X his right,
    -Z his front): tools/builders/titans.gd sets his hurtboxes and lock anchors over them."""
    import stoneback as sb
    sc = _sc()
    rest = person.rest
    p = poses["idle"][0]
    out = {}
    for name in sc.PLATE_ORDER + sc.GEAR:
        piece = pieces[name]
        V = np.asarray(piece.V, np.float64)
        W = np.stack([np.asarray(piece.groups.get(b, np.zeros(len(V)))) for b in sc.pr.BONES], axis=1)
        dom = np.argmax(W, axis=1)
        posed = np.zeros_like(V)
        for i, b in enumerate(sc.pr.BONES):
            sel = dom == i
            if sel.any():
                posed[sel] = p.P[b] + (V[sel] - rest.head[b]) @ p.D[b].T
        A = (sb.TO_ACTOR @ posed.T).T * sc.F
        lo, hi = A.min(axis=0), A.max(axis=0)
        if name == "crown":
            # (the box is the band's and the tines' lower half: the tines stand far over the head)
            lo, hi = np.percentile(A, 2, axis=0), np.percentile(A, 75, axis=0)
        out[name] = {"centre": [br6(x) for x in 0.5 * (lo + hi)], "size": [br6(x) for x in hi - lo],
                     "top": br6(float(A[:, 1].max()))}
    return out


KNEEL_BONES = fm.KNEEL_BONES


def kneel_frames(person, poses):
    import stoneback as sb
    sc = _sc()
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = sb.TO_ACTOR @ p.D[b] @ sb.TO_ACTOR.T
            d[key] = {"head": [br6(x) for x in sb.TO_ACTOR @ p.P[b] * sc.F], "basis": [br6(x) for x in R.ravel()]}
    out["pelvis_m"] = br6(float(poses["kneel"][-1].P["pelvis"][2]) * sc.F)
    return out
