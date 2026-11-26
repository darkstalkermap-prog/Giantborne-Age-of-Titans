"""The Frostbound Titan's clips (D1): key poses solved as the other titans' (``clips.Pose``, the legs by their feet,
a hand placed by ``stoneback.Holder.hold``) and slerped between on eases (``stoneback_moves.keyed``).

He fights with his body: the left hand an open claw (the rake, the tearing of a shard from his back and its throw),
the right fist inside its mass of ice (the hammer-blow, the sweep), his breath, his feet. He is old and long: every
strike is drawn slowly and lands with his whole weight; between them he stands stooped, the ice fist hanging.

  dormant   (90, a loop) frozen kneeling in the ice: down on his right knee, the left forearm across the raised left
            knee, the ice fist planted on the ground, the head bowed onto his chest, a breath too slow to see
  wake      (120) his intro: the head lifts, he pushes up off the fist and stands, straightens, throws his arms wide
            and roars (WAKE_ROAR), and settles into his stance
  idle, walk, run
            stooped, the neck thrust forward, the long arms hanging: the claw loose before his left thigh, the ice
            fist hanging heavy at his right
  rake      (54) the claw drawn across to his right shoulder, raked out and down across his front to his left
  fist      (78) the ice fist raised over his right shoulder and brought down onto the ground ahead, the left hand
            braced on his knee (FIST_HIT)
  breath    (96) the chest filled, the head drawn back; the breath driven out over the ground ahead, the head low and
            turning a little across (BREATH_HIT to BREATH_END)
  stamp     (42) the right knee raised high, the foot driven down beside him (STAMP_HIT)
  sweep     (66) the ice fist drawn back low behind his right hip and swung round across his front to his left
  roar2     (78) his second phase: he crouches, then rises with the arms thrown wide and roars into the cold
  hurl      (90) the claw reaches over his right shoulder to the crest, tears a shard free (HURL_GRIP), draws it back
            high and throws it overhand (HURL_RELEASE)
  nova      (96) his last phase's strike: he gathers, both fists drawn to his chest, rises onto his toes and drives
            both down onto the ice either side of him (NOVA_HIT)
  reel      (60) staggered: a step back, the head snapped back, the arms thrown out
  kneel, rise (24, 36) a greave broken or the ice gone under him: down on the right knee, the ice fist on the ground;
            up again
  death     (110) he sags to both knees, the fist drops, he falls forward onto his face

Every number below is in design metres (the stage-1 giant's), Z up, -Y his front, +X his left.
"""
from __future__ import annotations

import math

import numpy as np

import stoneback_moves as sm

FPS = sm.FPS
FRAMES = {"dormant": 90, "wake": 120, "rake": 54, "fist": 78, "breath": 96, "stamp": 42, "sweep": 66, "roar2": 78,
          "hurl": 90, "nova": 96, "reel": 60, "kneel": 24, "rise": 36, "death": 110}
LOOPS = ("idle", "walk", "run", "dormant")
RAKE_HIT = 1.05
FIST_HIT = 1.55
BREATH_HIT = 1.45
BREATH_END = 2.75
STAMP_HIT = 0.78
SWEEP_HIT = 1.20
HURL_GRIP = 0.95
HURL_RELEASE = 1.90
NOVA_HIT = 2.20
KNEEL_HIT = 0.55
WAKE_ROAR = 2.70
ROAR2_PEAK = 1.45
# the rig's keys of each strike: [start, wound (the end of the draw), hit (the first active tick), past (the end of the
# active phase), end] (scripts/presentation/frostbound_rig.gd reads them from the manifest)
KEYS = {"rake": [0.0, 0.62, RAKE_HIT, 1.35, FRAMES["rake"] / FPS],
        "fist": [0.0, 1.15, FIST_HIT, 1.95, FRAMES["fist"] / FPS],
        "breath": [0.0, 1.25, BREATH_HIT, BREATH_END, FRAMES["breath"] / FPS],
        "stamp": [0.0, 0.50, STAMP_HIT, 0.98, FRAMES["stamp"] / FPS],
        "sweep": [0.0, 0.85, SWEEP_HIT, 1.60, FRAMES["sweep"] / FPS],
        "hurl": [0.0, 1.45, HURL_RELEASE, 2.20, FRAMES["hurl"] / FPS],
        "nova": [0.0, 1.70, NOVA_HIT, 2.60, FRAMES["nova"] / FPS],
        "kneel_hit": KNEEL_HIT, "hurl_grip": HURL_GRIP, "hurl_release": HURL_RELEASE, "wake_roar": WAKE_ROAR,
        "roar2_peak": ROAR2_PEAK, "breath_hit": BREATH_HIT, "breath_end": BREATH_END}
# the gauntlet's mass's centre (rest, design; set by the build): the ground checks
GAUNTLET_C = None
UP = np.array([0.0, 0.0, 1.0])


def _fb():
    import frostbound as fb
    return fb


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


def arm_len(holder, s):
    return holder.l1[s] + holder.l2[s]


# ----------------------------------------------------------------------------------------------- the hands

def fist(holder, pose, at, knuckles, pole=(-0.8, 0.3, -0.3)):
    """The right fist (in its ice) with its grip landmark at ``at`` and its knuckles toward ``knuckles``: the grip's
    line across the fist, square to the knuckles' direction."""
    k = unit(knuckles)
    across = np.cross(k, UP) if abs(k[2]) < 0.9 else np.cross(k, np.array([0.0, 1.0, 0.0]))
    holder.hold(holder_pose(pose), "r", np.asarray(at, np.float64), unit(across), pole=pole)
    return pose.solve()


def holder_pose(pose):
    return pose


def claw(holder, pose, at, palm, along=None, pole=(0.8, 0.3, -0.3)):
    """The left hand open at ``at``, its palm toward ``palm`` and its fingers along ``along`` (default: down and
    forward)."""
    along = unit(along if along is not None else np.array([0.0, -0.4, -1.0]))
    palm = unit(np.asarray(palm) - along * float(np.asarray(palm) @ along))
    holder.hold(pose, "l", np.asarray(at, np.float64), along, pole=pole, palm=palm)
    return pose.solve()


def mass_low(holder, pose):
    """The gauntlet's mass's lowest point (design z) in ``pose``: its centre less its radius (a sphere's)."""
    fb = _fb()
    if GAUNTLET_C is None:
        return 1.0
    r = holder.rest
    c = pose.P["hand_r"] + pose.D["hand_r"] @ (GAUNTLET_C - r.head["hand_r"])
    return float(c[2]) - fb.GAUNTLET["radius_m"] / fb.F * 0.92


def mass_centre(holder, pose):
    r = holder.rest
    if GAUNTLET_C is None:
        return pose.P["hand_r"]
    return pose.P["hand_r"] + pose.D["hand_r"] @ (GAUNTLET_C - r.head["hand_r"])


def lift_fist(holder, pose, clear_m=0.4, knuckles=(0.0, -0.3, -1.0), pole=(-0.8, 0.3, -0.3)):
    """The hanging fist raised (if need be) until its mass clears the ground by ``clear_m`` (real m)."""
    fb = _fb()
    for _ in range(8):
        low = mass_low(holder, pose) * fb.F
        if low >= clear_m:
            break
        g, _a = holder.grip_posed(pose, "r")
        fist(holder, pose, g + UP * ((clear_m - low) / fb.F + 0.01), knuckles, pole)
    return pose


# ----------------------------------------------------------------------------------------------- stances

def idle_pose(holder, rest, f, frames):
    """Stooped, the knees a little bent, the head forward and up; the claw loose before his left thigh, the ice fist
    hanging at his right, a slow breath that lifts the shoulders."""
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    pose = sm.body(rest, pelvis=(5.0, 0.0, 3.0), spine=(5.0 + 1.0 * b, 0.0, 2.0), neck=(-4.0, -2.0),
                   head=(-6.0 - 0.6 * b, 0.0, -3.0), drop=0.08 + 0.004 * b, clav=(-2.0 - 2.0 * b, -2.0 - 2.0 * b),
                   feet={"l": ((0.05, -0.10, 0.0), 10.0, 0.0, 0.0), "r": ((-0.06, 0.08, 0.0), -12.0, 0.0, 0.0)})
    sh = pose.P["upperarm_l"]
    L = arm_len(holder, "l")
    claw(holder, pose, sh + np.array([0.10 * L, -0.26 * L, -0.86 * L + 0.006 * b]), (-0.6, 0.2, 0.0),
         along=(0.1, -0.35, -1.0))
    sh = pose.P["upperarm_r"]
    L = arm_len(holder, "r")
    fist(holder, pose, sh + np.array([-0.14 * L, -0.18 * L, -0.90 * L + 0.006 * b]), (-0.1, -0.35, -1.0))
    return lift_fist(holder, pose)


def idle0(holder, rest):
    return idle_pose(holder, rest, 0, 60)


def gait_pose(holder, gait, phi, run=False):
    import brute as br
    import clips
    pose = br.brute_gait_pose(gait, phi)
    pose.set_rel("neck_01", clips.rot(clips.X, -6.0))
    pose.set_rel("head", clips.rot(clips.X, -6.0))
    pose.solve()
    sw = gait.g["arm_swing_deg"] * (1.5 if run else 1.0) * math.sin(phi)
    k = math.radians(sw)
    sh = pose.P["upperarm_l"]
    L = arm_len(holder, "l")
    claw(holder, pose, sh + np.array([0.10 * L, -0.22 * L - 0.40 * L * math.sin(k), -0.85 * L]),
         (-0.6, 0.2, 0.0), along=(0.1, -0.4, -1.0))
    sh = pose.P["upperarm_r"]
    L = arm_len(holder, "r")
    fist(holder, pose, sh + np.array([-0.16 * L, -0.20 * L + 0.24 * L * math.sin(k), -0.86 * L]),
         (-0.1, -0.4, -1.0))
    return lift_fist(holder, pose)


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0, bow=0.0):
    """Down on his right knee (Stoneback's kneel's legs), the left foot forward; the left hand on the raised left
    knee, the ice fist planted on the ground before his right knee; ``bow`` (0..1) bows the head and the trunk
    (his sleep in the ice)."""
    l1, l2 = sm._leg_lengths(rest, "r")
    pel = (9.0 * lean + 8.0 * bow, 0.0, -4.0)
    spine = (12.0 * lean + 18.0 * bow, 0.0, -2.0)
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
    k = sm.body(rest, pelvis=pel, spine=spine, neck=(10.0 * lean + 22.0 * bow, -4.0),
                head=(12.0 * lean + 18.0 * bow, 0.0, -6.0), feet=feet, drop=drop, clav=(4.0, 6.0))
    # the left hand on the left knee (the knee's top: the thigh's end)
    kn = k.P["calf_l"]
    claw(holder, k, kn + np.array([-0.02, -0.06, 0.10]), (0.0, 0.0, -1.0), along=(-0.2, -1.0, -0.2))
    # the ice fist on the ground before the right knee (its mass resting on the ground)
    sh = k.P["upperarm_r"]
    fb = _fb()
    R = fb.GAUNTLET["radius_m"] / fb.F
    g = np.array([sh[0] - 0.12, sh[1] - 0.40, R * 0.65 + 0.35 * (1.0 - depth)])
    fist(holder, k, g, (0.0, -0.3, -1.0), pole=(-0.8, 0.3, 0.0))
    low = mass_low(holder, k)
    if low < 0.0:
        g2, _a = holder.grip_posed(k, "r")
        fist(holder, k, g2 + UP * (-low + 0.005), (0.0, -0.3, -1.0), pole=(-0.8, 0.3, 0.0))
    return k.solve()


def dormant_pose(holder, rest, f, frames):
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    k = kneel_key(holder, rest, depth=1.0, lean=0.6, settle=0.015, bow=1.0 + 0.04 * b)
    return k


# ----------------------------------------------------------------------------------------------- strikes

def _roar_key(holder, rest, wide=1.0, crouch=0.0):
    """Arms thrown wide and up, the head back, the chest out (the wake's roar, his second phase's)."""
    k = sm.body(rest, pelvis=(-3.0 + 10.0 * crouch, 0.0, 0.0), spine=(-10.0 * wide + 16.0 * crouch, 0.0, 0.0),
                neck=(-14.0 * wide, 0.0), head=(-22.0 * wide, 0.0, 0.0), drop=0.12 + 0.20 * crouch,
                clav=(-12.0 * wide, -12.0 * wide),
                feet={"l": ((0.12, -0.16, 0.0), 14.0, 0.0, 0.0), "r": ((-0.12, 0.12, 0.0), -14.0, 0.0, 0.0)})
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        sh = k.P["upperarm_" + s]
        L = arm_len(holder, s)
        at = sh + np.array([sgn * 0.80 * L, -0.25 * L, 0.30 * L * wide - 0.4 * L * crouch])
        if s == "l":
            claw(holder, k, at, (0.0, -1.0, 0.3), along=(sgn * 0.8, -0.2, 0.5))
        else:
            fist(holder, k, at, (sgn * 0.8, -0.2, 0.5), pole=(-0.4, 0.6, -0.6))
    return k.solve()


def wake(holder, rest):
    k0 = dormant_pose(holder, rest, 0, FRAMES["dormant"])
    k1 = kneel_key(holder, rest, depth=1.0, lean=0.4, settle=0.015, bow=0.15)
    kp = kneel_key(holder, rest, depth=0.80, lean=1.4)
    ku = kneel_key(holder, rest, depth=0.30, lean=1.0)
    kr = _roar_key(holder, rest, 1.0)
    keys = [(0.0, k0, "smooth"), (0.75, k1, "smooth"), (1.35, kp, "smooth"), (1.90, ku, "out"),
            (WAKE_ROAR, kr, "out"), (3.35, kr, "linear"), (FRAMES["wake"] / FPS, idle0(holder, rest), "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["wake"])


def roar2(holder, rest):
    k0 = idle0(holder, rest)
    kc = _roar_key(holder, rest, 0.1, crouch=1.0)
    kr = _roar_key(holder, rest, 1.15)
    keys = [(0.0, k0, "smooth"), (0.70, kc, "smooth"), (ROAR2_PEAK, kr, "out"), (2.15, kr, "linear"),
            (FRAMES["roar2"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["roar2"])


def rake(holder, rest):
    """The claw drawn high across to his right shoulder, then raked out and down across his front to his left."""
    k0 = idle0(holder, rest)
    feet = {"l": ((0.10, -0.24, 0.0), 10.0, 0.0, 0.0), "r": ((-0.10, 0.18, 0.0), -16.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(4.0, 0.0, -18.0), spine=(4.0, 0.0, -22.0), neck=(-6.0, 10.0), head=(-6.0, 0.0, 14.0),
                 drop=0.14, feet=feet, clav=(14.0, 0.0))
    sh_r = kw.P["upperarm_r"]
    L = arm_len(holder, "l")
    claw(holder, kw, sh_r + np.array([-0.10 * L, -0.30 * L, 0.18 * L]), (-1.0, -0.2, 0.0), along=(-0.3, -0.3, 1.0),
         pole=(0.2, 0.6, -0.8))
    sh = kw.P["upperarm_r"]
    fist(holder, kw, sh + np.array([-0.20 * L, 0.05 * L, -0.85 * L]), (-0.2, 0.1, -1.0))
    lift_fist(holder, kw)
    kh = sm.body(rest, pelvis=(14.0, 0.0, 16.0), spine=(12.0, 0.0, 18.0), neck=(-12.0, -8.0), head=(-8.0, 0.0, -12.0),
                 drop=0.26, feet=feet, clav=(-8.0, 0.0))
    sh_l = kh.P["upperarm_l"]
    claw(holder, kh, sh_l + np.array([0.20 * L, -0.85 * L, -0.42 * L]), (0.85, -0.3, -0.2), along=(0.2, -0.8, -0.6))
    sh = kh.P["upperarm_r"]
    fist(holder, kh, sh + np.array([-0.18 * L, 0.20 * L, -0.82 * L]), (-0.2, 0.3, -1.0))
    lift_fist(holder, kh)
    kf = sm.body(rest, pelvis=(14.0, 0.0, 30.0), spine=(12.0, 0.0, 28.0), neck=(-10.0, -10.0), head=(-6.0, 0.0, -14.0),
                 drop=0.24, feet=feet, clav=(-6.0, 0.0))
    sh_l = kf.P["upperarm_l"]
    claw(holder, kf, sh_l + np.array([0.70 * L, -0.40 * L, -0.62 * L]), (0.9, 0.2, -0.2), along=(0.6, -0.4, -0.7))
    sh = kf.P["upperarm_r"]
    fist(holder, kf, sh + np.array([-0.10 * L, 0.24 * L, -0.82 * L]), (-0.2, 0.3, -1.0))
    lift_fist(holder, kf)
    keys = [(0.0, k0, "smooth"), (0.62, kw, "out"), (RAKE_HIT, kh, "in"), (1.35, kf, "out"),
            (FRAMES["rake"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["rake"])


def _fist_down(holder, k, reach_share, side_x=-0.10):
    """The fist driven onto the ground ahead: its mass resting on the ground ``reach_share`` of the arm's reach out."""
    fb = _fb()
    sh = k.P["upperarm_r"]
    L = arm_len(holder, "r")
    R = fb.GAUNTLET["radius_m"] / fb.F
    g = np.array([sh[0] + side_x, sh[1] - reach_share * L, R * 0.7])
    fist(holder, k, g, (0.0, -0.6, -1.0), pole=(-0.8, 0.4, 0.2))
    for _ in range(6):
        low = mass_low(holder, k)
        if abs(low) < 0.004:
            break
        g2, _a = holder.grip_posed(k, "r")
        fist(holder, k, g2 - UP * low, (0.0, -0.6, -1.0), pole=(-0.8, 0.4, 0.2))
    return k


def fist_(holder, rest):
    k0 = idle0(holder, rest)
    feet = {"l": ((0.10, -0.34, 0.0), 8.0, 0.0, 0.0), "r": ((-0.12, 0.22, 0.0), -16.0, 0.0, 0.0)}
    ku = sm.body(rest, pelvis=(-4.0, 0.0, -12.0), spine=(-10.0, 0.0, -16.0), neck=(-4.0, 8.0), head=(-8.0, 0.0, 10.0),
                 drop=0.12, feet=feet, clav=(-4.0, -22.0))
    hd = ku.P["head"]
    fist(holder, ku, hd + np.array([-0.42, 0.18, 0.46]), (-0.2, 0.5, 0.9), pole=(-0.6, 0.6, -0.4))
    sh_l = ku.P["upperarm_l"]
    L = arm_len(holder, "l")
    claw(holder, ku, sh_l + np.array([0.30 * L, -0.55 * L, -0.40 * L]), (0.0, -1.0, 0.0), along=(0.2, -0.8, -0.4))
    kh = sm.body(rest, pelvis=(30.0, 0.0, 10.0), spine=(16.0, 0.0, 10.0), neck=(-16.0, -4.0), head=(-14.0, 0.0, -6.0),
                 drop=0.38, feet=feet, clav=(0.0, 12.0))
    _fist_down(holder, kh, 0.98)
    kn = kh.P["calf_l"]
    claw(holder, kh, kn + np.array([0.04, -0.10, 0.16]), (0.0, 0.0, -1.0), along=(-0.2, -1.0, -0.3))
    kp = sm.body(rest, pelvis=(32.0, 0.0, 12.0), spine=(18.0, 0.0, 12.0), neck=(-18.0, -4.0), head=(-16.0, 0.0, -8.0),
                 drop=0.42, feet=feet, clav=(0.0, 12.0))
    _fist_down(holder, kp, 0.96)
    kn = kp.P["calf_l"]
    claw(holder, kp, kn + np.array([0.04, -0.10, 0.14]), (0.0, 0.0, -1.0), along=(-0.2, -1.0, -0.3))
    keys = [(0.0, k0, "smooth"), (1.15, ku, "out"), (FIST_HIT, kh, "in"), (1.95, kp, "out"), (2.25, kp, "linear"),
            (FRAMES["fist"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["fist"])


def breath(holder, rest):
    """The chest filled, the head drawn back; then the breath driven out over the ground ahead, the head low and
    sweeping a little from his right to his left."""
    k0 = idle0(holder, rest)
    feet = {"l": ((0.10, -0.26, 0.0), 10.0, 0.0, 0.0), "r": ((-0.10, 0.22, 0.0), -14.0, 0.0, 0.0)}
    kd = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-14.0, 0.0, 0.0), neck=(-14.0, 0.0), head=(-24.0, 0.0, 0.0),
                 drop=0.12, feet=feet, clav=(-14.0, -14.0))
    L = arm_len(holder, "l")
    sh = kd.P["upperarm_l"]
    claw(holder, kd, sh + np.array([0.45 * L, 0.30 * L, -0.70 * L]), (0.6, 0.6, 0.0), along=(0.3, 0.3, -1.0))
    sh = kd.P["upperarm_r"]
    fist(holder, kd, sh + np.array([-0.40 * L, 0.30 * L, -0.74 * L]), (-0.3, 0.4, -1.0))
    lift_fist(holder, kd)

    def out_key(turn):
        k = sm.body(rest, pelvis=(16.0, 0.0, turn * 0.5), spine=(18.0, 0.0, turn), neck=(-6.0, turn * 0.5),
                    head=(14.0, 0.0, turn * 0.6), drop=0.24, feet=feet, clav=(6.0, 6.0))
        sh_ = k.P["upperarm_l"]
        claw(holder, k, sh_ + np.array([0.30 * L, -0.45 * L, -0.62 * L]), (0.4, -0.6, 0.0), along=(0.2, -0.6, -0.8))
        sh_ = k.P["upperarm_r"]
        fist(holder, k, sh_ + np.array([-0.30 * L, -0.30 * L, -0.80 * L]), (-0.2, -0.3, -1.0))
        lift_fist(holder, k)
        return k
    ka = out_key(-14.0)
    kb = out_key(12.0)
    keys = [(0.0, k0, "smooth"), (1.25, kd, "out"), (BREATH_HIT, ka, "in"), (BREATH_END, kb, "smooth"),
            (FRAMES["breath"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["breath"])


def stamp(holder, rest):
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    ku = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-4.0, 0.0, 0.0), neck=(4.0, 0.0), head=(10.0, 0.0, 0.0),
                 drop=0.10, side=0.05,
                 feet={"l": ((0.04, 0.02, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, -0.22, 0.40), -6.0, -18.0, 0.0)})
    sh = ku.P["upperarm_l"]
    claw(holder, ku, sh + np.array([0.55 * L, -0.25 * L, -0.55 * L]), (0.6, -0.4, 0.0), along=(0.6, -0.3, -0.7))
    sh = ku.P["upperarm_r"]
    fist(holder, ku, sh + np.array([-0.40 * L, 0.05 * L, -0.80 * L]), (-0.3, 0.1, -1.0))
    lift_fist(holder, ku)
    kh = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(10.0, 0.0, 0.0), neck=(-6.0, 0.0), head=(-8.0, 0.0, 0.0),
                 drop=0.30, side=-0.02,
                 feet={"l": ((0.06, 0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.08, -0.32, 0.0), -10.0, 0.0, 0.0)})
    sh = kh.P["upperarm_l"]
    claw(holder, kh, sh + np.array([0.45 * L, -0.30 * L, -0.65 * L]), (0.6, -0.4, 0.0), along=(0.5, -0.3, -0.8))
    sh = kh.P["upperarm_r"]
    fist(holder, kh, sh + np.array([-0.36 * L, -0.05 * L, -0.84 * L]), (-0.3, -0.1, -1.0))
    lift_fist(holder, kh)
    keys = [(0.0, k0, "smooth"), (0.50, ku, "out"), (STAMP_HIT, kh, "in"), (0.98, kh, "linear"),
            (FRAMES["stamp"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["stamp"])


def sweep(holder, rest):
    k0 = idle0(holder, rest)
    L = arm_len(holder, "r")
    feet = {"l": ((0.12, -0.22, 0.0), 6.0, 0.0, 0.0), "r": ((-0.16, 0.20, 0.0), -26.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(6.0, 0.0, -32.0), spine=(4.0, 0.0, -26.0), neck=(0.0, 12.0), head=(2.0, 0.0, 18.0),
                 drop=0.24, feet=feet, clav=(8.0, 10.0))
    pel = kw.P["pelvis"]
    fist(holder, kw, pel + np.array([-0.62, 0.30, -0.02]), (-0.5, 0.8, -0.2))
    lift_fist(holder, kw, knuckles=(-0.5, 0.8, -0.2))
    sh = kw.P["upperarm_l"]
    claw(holder, kw, sh + np.array([0.40 * L, -0.40 * L, -0.55 * L]), (0.6, -0.5, 0.0), along=(0.4, -0.5, -0.7))
    kh = sm.body(rest, pelvis=(10.0, 0.0, 16.0), spine=(8.0, 0.0, 20.0), neck=(-4.0, -8.0), head=(-4.0, 0.0, -10.0),
                 drop=0.26, feet=feet)
    sh = kh.P["upperarm_r"]
    fist(holder, kh, sh + np.array([0.22 * L, -0.84 * L, -0.48 * L]), (0.6, -0.8, -0.1))
    lift_fist(holder, kh, knuckles=(0.6, -0.8, -0.1))
    sh = kh.P["upperarm_l"]
    claw(holder, kh, sh + np.array([0.55 * L, 0.10 * L, -0.55 * L]), (0.6, 0.5, 0.0), along=(0.5, 0.3, -0.8))
    kf = sm.body(rest, pelvis=(10.0, 0.0, 34.0), spine=(8.0, 0.0, 30.0), neck=(-4.0, -10.0), head=(-4.0, 0.0, -12.0),
                 drop=0.22, feet=feet)
    sh = kf.P["upperarm_r"]
    fist(holder, kf, sh + np.array([0.62 * L, -0.52 * L, -0.52 * L]), (0.9, -0.3, -0.2))
    lift_fist(holder, kf, knuckles=(0.9, -0.3, -0.2))
    sh = kf.P["upperarm_l"]
    claw(holder, kf, sh + np.array([0.45 * L, 0.25 * L, -0.60 * L]), (0.6, 0.6, 0.0), along=(0.4, 0.4, -0.8))
    keys = [(0.0, k0, "smooth"), (0.85, kw, "out"), (SWEEP_HIT, kh, "in"), (1.60, kf, "out"),
            (FRAMES["sweep"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["sweep"])


def hurl(holder, rest):
    """The claw over his right shoulder to the crest (the shard torn free), drawn back high, thrown overhand ahead."""
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    feet = {"l": ((0.10, -0.36, 0.0), 8.0, 0.0, 0.0), "r": ((-0.12, 0.26, 0.0), -18.0, 0.0, 0.0)}
    kg = sm.body(rest, pelvis=(2.0, 0.0, -14.0), spine=(6.0, 0.0, -18.0), neck=(8.0, 10.0), head=(10.0, 0.0, 16.0),
                 drop=0.14, feet=feet, clav=(16.0, 0.0))
    nk = kg.P["neck_01"]
    claw(holder, kg, nk + np.array([-0.12, 0.22, 0.06]), (0.0, 1.0, 0.0), along=(-0.2, 0.6, 0.7), pole=(0.6, 0.0, 0.8))
    sh = kg.P["upperarm_r"]
    fist(holder, kg, sh + np.array([-0.20 * L, 0.0, -0.86 * L]), (-0.2, 0.0, -1.0))
    lift_fist(holder, kg)
    kb = sm.body(rest, pelvis=(-4.0, 0.0, -16.0), spine=(-10.0, 0.0, -20.0), neck=(-6.0, 10.0), head=(-8.0, 0.0, 14.0),
                 drop=0.14, feet=feet, clav=(-16.0, 0.0))
    sh = kb.P["upperarm_l"]
    claw(holder, kb, sh + np.array([0.20 * L, 0.45 * L, 0.55 * L]), (0.0, -1.0, 0.0), along=(0.0, 0.2, 1.0),
         pole=(0.6, 0.6, -0.4))
    sh = kb.P["upperarm_r"]
    fist(holder, kb, sh + np.array([-0.40 * L, -0.45 * L, -0.55 * L]), (-0.3, -0.6, -0.6))
    lift_fist(holder, kb)
    kr = sm.body(rest, pelvis=(16.0, 0.0, 14.0), spine=(16.0, 0.0, 16.0), neck=(-10.0, -6.0), head=(-10.0, 0.0, -8.0),
                 drop=0.26, feet=feet, clav=(-6.0, 0.0))
    sh = kr.P["upperarm_l"]
    claw(holder, kr, sh + np.array([0.0, -0.85 * L, 0.35 * L]), (0.0, -0.3, 1.0), along=(0.0, -1.0, 0.1),
         pole=(0.6, 0.4, -0.6))
    sh = kr.P["upperarm_r"]
    fist(holder, kr, sh + np.array([-0.30 * L, 0.20 * L, -0.80 * L]), (-0.2, 0.3, -1.0))
    lift_fist(holder, kr)
    kf = sm.body(rest, pelvis=(22.0, 0.0, 22.0), spine=(18.0, 0.0, 22.0), neck=(-14.0, -8.0), head=(-12.0, 0.0, -10.0),
                 drop=0.30, feet=feet)
    sh = kf.P["upperarm_l"]
    claw(holder, kf, sh + np.array([-0.10 * L, -0.70 * L, -0.60 * L]), (0.0, -0.3, -1.0), along=(-0.2, -0.7, -0.7))
    sh = kf.P["upperarm_r"]
    fist(holder, kf, sh + np.array([-0.30 * L, 0.24 * L, -0.80 * L]), (-0.2, 0.3, -1.0))
    lift_fist(holder, kf)
    keys = [(0.0, k0, "smooth"), (HURL_GRIP, kg, "out"), (1.45, kb, "smooth"), (HURL_RELEASE, kr, "in"),
            (2.20, kf, "out"), (FRAMES["hurl"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["hurl"])


def nova(holder, rest):
    """He gathers (the fists to his chest), rises onto his toes, and drives both arms down onto the ice either side."""
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    fb = _fb()
    feet = {"l": ((0.16, -0.10, 0.0), 14.0, 0.0, 0.0), "r": ((-0.16, 0.10, 0.0), -14.0, 0.0, 0.0)}
    kg = sm.body(rest, pelvis=(18.0, 0.0, 0.0), spine=(22.0, 0.0, 0.0), neck=(6.0, 0.0), head=(6.0, 0.0, 0.0),
                 drop=0.30, feet=feet, clav=(10.0, 10.0))
    sp = kg.P["spine_03"]
    claw(holder, kg, sp + np.array([0.16, -0.30, -0.02]), (-0.6, 0.6, 0.0), along=(-0.6, -0.2, 0.6))
    fist(holder, kg, sp + np.array([-0.18, -0.34, -0.06]), (0.6, -0.2, 0.6), pole=(-0.6, 0.0, -0.8))
    kr = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-14.0, 0.0, 0.0), neck=(-12.0, 0.0), head=(-18.0, 0.0, 0.0),
                 drop=0.02, lift=0.04, feet={"l": ((0.16, -0.10, 0.0), 14.0, 0.0, 28.0),
                                             "r": ((-0.16, 0.10, 0.0), -14.0, 0.0, 28.0)}, clav=(-18.0, -18.0))
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        sh = kr.P["upperarm_" + s]
        at = sh + np.array([sgn * 0.55 * L, -0.10 * L, 0.70 * L])
        if s == "l":
            claw(holder, kr, at, (0.0, -1.0, 0.0), along=(sgn * 0.4, 0.0, 1.0))
        else:
            fist(holder, kr, at, (sgn * 0.4, 0.0, 1.0), pole=(-0.4, 0.6, -0.6))
    kh = sm.body(rest, pelvis=(26.0, 0.0, 0.0), spine=(20.0, 0.0, 0.0), neck=(-14.0, 0.0), head=(-12.0, 0.0, 0.0),
                 drop=0.50, feet={"l": ((0.24, -0.18, 0.0), 18.0, 0.0, 0.0), "r": ((-0.24, 0.12, 0.0), -18.0, 0.0, 0.0)},
                 clav=(10.0, 10.0))
    R = fb.GAUNTLET["radius_m"] / fb.F
    sh = kh.P["upperarm_l"]
    claw(holder, kh, np.array([sh[0] + 0.55 * L, sh[1] - 0.45 * L, 0.06]), (0.0, 0.0, -1.0), along=(0.5, -0.8, -0.2))
    sh = kh.P["upperarm_r"]
    fist(holder, kh, np.array([sh[0] - 0.50 * L, sh[1] - 0.45 * L, R * 0.75]), (-0.5, -0.4, -1.0),
         pole=(-0.8, 0.4, 0.2))
    low = mass_low(holder, kh)
    if low < 0.0:
        g2, _a = holder.grip_posed(kh, "r")
        fist(holder, kh, g2 - UP * low, (-0.5, -0.4, -1.0), pole=(-0.8, 0.4, 0.2))
    keys = [(0.0, k0, "smooth"), (1.10, kg, "smooth"), (1.70, kr, "out"), (NOVA_HIT, kh, "in"), (2.60, kh, "linear"),
            (FRAMES["nova"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["nova"])


def reel(holder, rest):
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 4.0), spine=(-12.0, 2.0, 4.0), neck=(-12.0, 6.0), head=(-20.0, 4.0, 8.0),
                 back=0.12, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.40, 0.0), -16.0, 0.0, 0.0)},
                 drop=0.12)
    sh = k1.P["upperarm_l"]
    claw(holder, k1, sh + np.array([0.70 * L, -0.20 * L, -0.30 * L]), (0.4, -0.8, 0.0), along=(0.8, -0.2, 0.3))
    sh = k1.P["upperarm_r"]
    fist(holder, k1, sh + np.array([-0.60 * L, -0.10 * L, -0.55 * L]), (-0.8, -0.2, -0.4))
    lift_fist(holder, k1)
    k2 = sm.body(rest, pelvis=(16.0, 0.0, -6.0), spine=(12.0, -3.0, -4.0), neck=(14.0, -6.0), head=(16.0, 0.0, -10.0),
                 back=0.12, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.36, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.30)
    sh = k2.P["upperarm_l"]
    claw(holder, k2, sh + np.array([0.20 * L, -0.40 * L, -0.80 * L]), (0.0, -0.6, 0.0), along=(0.1, -0.4, -1.0))
    sh = k2.P["upperarm_r"]
    fist(holder, k2, sh + np.array([-0.20 * L, -0.25 * L, -0.86 * L]), (-0.2, -0.4, -1.0))
    lift_fist(holder, k2)
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.85, k2, "smooth"), (FRAMES["reel"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["reel"])


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
    keys = [(0.0, k0, "smooth"), (0.35, kp, "smooth"), (0.80, ku, "out"), (FRAMES["rise"] / FPS, idle0(holder, rest),
                                                                          "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["rise"])


def death(holder, rest):
    import clips
    from clips import X, Y, Z, rot
    k0 = idle0(holder, rest)
    L = arm_len(holder, "l")
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 6.0), spine=(-10.0, 2.0, 4.0), neck=(-14.0, 4.0), head=(-22.0, 4.0, 6.0),
                 back=0.10, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.30, 0.0), -14.0, 0.0, 0.0)},
                 drop=0.12)
    sh = k1.P["upperarm_l"]
    claw(holder, k1, sh + np.array([0.40 * L, 0.0, -0.80 * L]), (0.6, 0.0, 0.0), along=(0.3, 0.1, -1.0))
    sh = k1.P["upperarm_r"]
    fist(holder, k1, sh + np.array([-0.35 * L, 0.10 * L, -0.85 * L]), (-0.3, 0.1, -1.0))
    lift_fist(holder, k1)
    kn = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(16.0, 0.0, 0.0), neck=(12.0, 0.0), head=(16.0, 0.0, -6.0),
                 feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)}, drop=1.0)
    clips.set_arm(kn, "l", -10.0, 30.0, out_deg=30.0)
    clips.set_arm(kn, "r", -8.0, 18.0, out_deg=24.0)
    kn.solve()
    lift_fist(holder, kn, clear_m=0.0)
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
    clips.set_arm(down, "r", -120.0, 30.0, out_deg=50.0)
    down.solve()
    keys = [(0.0, k0, "smooth"), (0.45, k1, "out"), (1.40, kn, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- all of them

CLIP_FUNCS = {"wake": wake, "rake": rake, "fist": fist_, "breath": breath, "stamp": stamp, "sweep": sweep,
              "roar2": roar2, "hurl": hurl, "nova": nova, "reel": reel, "kneel": kneel, "rise": rise, "death": death}


def make_poses(person, pieces, holder):
    """Every clip's solved frames: {name: [pose, ...]}, the gaits, and the checks (his crown's height in the stances
    and the gaits; the ice fist's lowest point over the ground in the stances and at its blows; the kneel's bones;
    each plate's place in the idle)."""
    import clips
    fb = _fb()
    rest = person.rest
    gaits = {"walk": clips.Gait(rest, "frostbound_walk", 32), "run": clips.Gait(rest, "frostbound_run", 32)}
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
        return float((p.P["head"] + p.D["head"] @ local)[2]) * fb.F
    checks = {"crown_m": {c: [br6(min(crown(p) for p in poses[c])), br6(max(crown(p) for p in poses[c]))]
                          for c in ("idle", "dormant", "walk", "run", "wake", "roar2")}}
    checks["fist_low_m"] = {c: br6(min(mass_low(holder, p) for p in poses[c]) * fb.F)
                            for c in ("idle", "walk", "run", "dormant", "rake", "sweep", "breath", "hurl")}

    def mass_at(clip, t):
        p = poses[clip][min(len(poses[clip]) - 1, int(round(t * FPS)))]
        a = sm_actor(mass_centre(holder, p)) * fb.F
        return [br6(a[0]), br6(a[1]), br6(a[2])]
    checks["fist_at_blow_m"] = {"fist": mass_at("fist", FIST_HIT), "nova": mass_at("nova", NOVA_HIT),
                                "sweep": mass_at("sweep", SWEEP_HIT)}
    checks["mouth_at_breath_m"] = mouth_at(person, poses["breath"][int(round(BREATH_HIT * FPS))])
    checks["kneel"] = kneel_frames(person, poses)
    checks["idle_pieces"] = idle_pieces(person, poses, pieces)
    return poses, gaits, checks


def br6(x):
    import brute as br
    return br.r6(x)


def sm_actor(p):
    import stoneback as sb
    return sb.TO_ACTOR @ np.asarray(p)


def mouth_at(person, p):
    """His mouth's place and the head's forward line in a pose (actor space, real m): the breath's origin."""
    import stoneback as sb
    fb = _fb()
    J = person.bd.joints
    S = person.S
    jaw = J["joint-jaw"] * S if "joint-jaw" in J else person.rest.head["head"]
    loc = jaw - person.rest.head["head"]
    m = p.P["head"] + p.D["head"] @ loc
    fwd = p.D["head"] @ np.array([0.0, -1.0, 0.0])
    return {"at": [br6(x) for x in sb.TO_ACTOR @ m * fb.F], "forward": [br6(x) for x in sb.TO_ACTOR @ fwd]}


def idle_pieces(person, poses, pieces):
    """Each plate's centre and extent, posed by the idle's first key, in his actor's space (real m: +X his right,
    -Z his front): tools/builders/titans.gd sets his hurtboxes and lock anchors over them."""
    import stoneback as sb
    fb = _fb()
    rest = person.rest
    p = poses["idle"][0]
    out = {}
    for name in fb.PLATE_ORDER + fb.GEAR:
        piece = pieces[name]
        V = np.asarray(piece.V, np.float64)
        W = np.stack([np.asarray(piece.groups.get(b, np.zeros(len(V)))) for b in fb.pr.BONES], axis=1)
        dom = np.argmax(W, axis=1)
        posed = np.zeros_like(V)
        for i, b in enumerate(fb.pr.BONES):
            sel = dom == i
            if sel.any():
                posed[sel] = p.P[b] + (V[sel] - rest.head[b]) @ p.D[b].T
        A = (sb.TO_ACTOR @ posed.T).T * fb.F
        lo, hi = A.min(axis=0), A.max(axis=0)
        if name == "serac":
            # (the box is the slab's, not the crest's: the crest stands far above the back)
            core = A[np.asarray(piece.rgba)[:, 3] > 0.5]
            body_part = A[: getattr(piece, "n_slab", len(A))]
            lo, hi = np.percentile(body_part, 5, axis=0), np.percentile(body_part, 70, axis=0)
            del core
        out[name] = {"centre": [br6(x) for x in 0.5 * (lo + hi)], "size": [br6(x) for x in hi - lo],
                     "top": br6(float(A[:, 1].max()))}
    return out


KNEEL_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
               "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r")


def kneel_frames(person, poses):
    import stoneback as sb
    fb = _fb()
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = sb.TO_ACTOR @ p.D[b] @ sb.TO_ACTOR.T
            d[key] = {"head": [br6(x) for x in sb.TO_ACTOR @ p.P[b] * fb.F], "basis": [br6(x) for x in R.ravel()]}
    out["pelvis_m"] = br6(float(poses["kneel"][-1].P["pelvis"][2]) * fb.F)
    return out
