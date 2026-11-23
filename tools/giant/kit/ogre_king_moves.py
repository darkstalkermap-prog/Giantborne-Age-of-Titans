"""The Ogre King's clips (B2): key poses solved as Stoneback's (``clips.Pose``, the legs by their feet, the arms that
hold the ram by ``stoneback.Holder.hold``) and slerped between on eases (``stoneback_moves.keyed``), so each blow has
its anticipation (a draw back, a dip into the knees), its swing and its follow-through (the ram's weight carrying the
body on past the blow, checked, recovered). The ram rides on his right shoulder at rest, held near its foot in the
right fist; both fists take it for the blows.

  idle, walk, run  the ram on his right shoulder, the left arm hanging (the walk and run: the brutes' heavy gaits at his
                   own stride, carried taller)
  roar             (45 frames) the phase roar: he fills his chest, throws his head back and lifts the ram high in his
                   right fist, the left fist out
  combo_a          (42) the first blow: the ram heaved off the shoulder and cocked back over it (the torso wound to his
                   right, the weight on the back foot), swung down across his front to his left (COMBO_A_HIT), carried
                   on low past his left knee and held there
  combo_b          (60) the second: from there drawn up across to his left shoulder, swung back flat across his front
                   to his right (COMBO_B_HIT), carried round, and heaved back onto the shoulder
  slam             (99) both fists raise the ram upright over his head, he rocks back on his heels and arches, then
                   brings it down head-first onto the ground before him (SLAM_HIT), bent over it, levers it up and puts
                   it back on the shoulder
  charge           (27) the charge's wind-up: the ram brought down level under his right arm as a ram is carried,
                   both fists on it, his head down
  charge_run       (32, a loop) the run's legs under the charge's levelled ram
  reel             (75) a charge into stone, a trophy torn off: the head snapped back, a stumble, the left hand to his
                   brow, the ram's head dragging on the ground, then the ram back on the shoulder
  kneel            (24) the keg burst under his feet: the right foot slides, he goes down on the right knee
                   (KNEEL_HIT), the left hand on the left knee, the ram planted head-down at his side; held while down
  rise             (36) up again, the ram back to the shoulder
  death            (96) struck down: rocked back, the ram falls from his fist (the rig drops it), he sinks to his
                   knees and topples back onto the ground, his belly up

Every number below is in design metres (the stage-1 giant's), Z up, -Y his front, +X his left.
"""
from __future__ import annotations

import math

import numpy as np

import stoneback_moves as sm

FPS = sm.FPS
FRAMES = {"roar": 45, "combo_a": 42, "combo_b": 60, "slam": 99, "charge": 27, "charge_run": 32, "reel": 75,
          "kneel": 24, "rise": 36, "death": 96}
LOOPS = ("idle", "walk", "run", "charge_run")
COMBO_A_HIT = 0.80
COMBO_B_HIT = 0.80
SLAM_HIT = 1.50
KNEEL_HIT = 0.55
DEATH_DROP = 0.50
# the rig's keys of each strike: [start, wound (the end of the draw), hit (the first active tick), past (the end of the
# active phase), end] (scripts/presentation/ogre_king_rig.gd reads them from the manifest)
KEYS = {"combo_a": [0.0, 0.50, COMBO_A_HIT, 1.00, FRAMES["combo_a"] / FPS],
        "combo_b": [0.0, 0.50, COMBO_B_HIT, 1.00, FRAMES["combo_b"] / FPS],
        "slam": [0.0, 1.20, SLAM_HIT, 1.65, FRAMES["slam"] / FPS],
        "kneel_hit": KNEEL_HIT, "death_drop": DEATH_DROP}
LEFT_ON_M = 0.55                   # the left fist this far (real m) up the ram from the right


def _ok():
    import ogre_king as ok
    return ok


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


def hold_ram(holder, pose, grip, axis, two=True, pole_r=(-0.6, 0.15, -0.5), pole_l=(0.7, 0.2, -0.5), left_m=None):
    """The right fist's grip at ``grip`` with the ram along ``axis`` (toward its head), the left fist on it ``left_m``
    (real m) farther up when ``two``."""
    ok = _ok()
    axis = unit(axis)
    holder.hold(pose, "r", np.asarray(grip, np.float64), axis, pole=pole_r)
    if two:
        lm = (LEFT_ON_M if left_m is None else left_m) / ok.F
        holder.hold(pose, "l", np.asarray(grip, np.float64) + axis * lm, axis, pole=pole_l)
    return pose.solve()


def ram_length():
    ok = _ok()
    return (ok.RAM["length_m"] - 0.1) / ok.F


def shoulder_carry(holder, pose, bob=0.0):
    """The ram on the right shoulder: the fist before the chest, the log over the trapezius, its head behind him."""
    ok = _ok()
    pose.solve()
    sh = pose.P["upperarm_r"]
    nk = pose.P["neck_01"]
    c = sh + (nk - sh) * 0.10 + np.array([-0.05, 0.04, 0.08 + 0.01 * bob])   # the shoulder's top under the log
    rr = ok.RAM["r"] / ok.F
    grip = sh + np.array([-0.07, -0.68, -0.04 + 0.01 * bob])
    axis = unit(c + np.array([0.0, 0.0, rr * 1.05]) - grip)
    holder.hold(pose, "r", grip, axis, pole=(-0.7, 0.1, -0.7))
    return pose.solve()


def idle_pose(holder, rest, f, frames):
    import brute as br
    pose = br.brute_idle(rest, f, frames)
    shoulder_carry(holder, pose, math.sin(2.0 * math.pi * f / max(frames, 1)))
    sm.free_left(pose, -4.0 + 1.5 * math.sin(2.0 * math.pi * f / max(frames, 1)), 24.0, br.ARM_OUT_DEG + 4.0)
    return pose.solve()


def gait_pose(holder, gait, phi, run=False):
    import brute as br
    import clips
    pose = br.brute_gait_pose(gait, phi)
    shoulder_carry(holder, pose, math.sin(2.0 * phi))
    swing = gait.g["arm_swing_deg"] * (1.6 if run else 1.0) * math.sin(phi)
    clips.set_arm(pose, "l", -4.0 + swing, 30.0 if run else 22.0, out_deg=br.ARM_OUT_DEG + 4.0)
    return pose.solve()


def idle0(holder, rest):
    return idle_pose(holder, rest, 0, 60)


def ground_axis(grip, forward, sideways, rest, lift=0.0):
    """The ram's line from ``grip`` that puts its head on the ground ``forward`` (-Y) and ``sideways`` (+X)."""
    ok = _ok()
    L = ram_length()
    R = ok.RAM["r"] * 1.15 / ok.F
    g = np.asarray(grip, np.float64)
    z = (R + lift - g[2]) / L
    z = max(-0.98, min(0.5, z))
    h = math.sqrt(max(1e-6, 1.0 - z * z))
    d = np.array([sideways, -forward, 0.0])
    d = d / max(np.linalg.norm(d), 1e-6) * h
    return np.array([d[0], d[1], z])


# ----------------------------------------------------------------------------------------------- the clips

def roar(holder, rest):
    import clips
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(6.0, 0.0, 0.0), spine=(6.0, 0.0, 0.0), neck=(6.0, 0.0), head=(6.0, 0.0, 0.0), drop=0.12,
                 feet={"l": ((0.05, -0.10, 0.0), 8.0, 0.0, 0.0), "r": ((-0.05, 0.08, 0.0), -8.0, 0.0, 0.0)})
    shoulder_carry(holder, k1)
    sm.free_left(k1, -10.0, 40.0, 26.0)
    k2 = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-12.0, 0.0, 0.0), neck=(-10.0, 0.0), head=(-22.0, 0.0, 0.0),
                 drop=0.08, clav=(-10.0, 16.0),
                 feet={"l": ((0.05, -0.10, 0.0), 8.0, 0.0, 0.0), "r": ((-0.05, 0.08, 0.0), -8.0, 0.0, 0.0)})
    sh = k2.P["upperarm_r"]
    holder.hold(k2, "r", sh + np.array([-0.28, -0.10, 0.62]), unit(np.array([-0.15, 0.10, 1.0])),
                pole=(-0.9, 0.2, -0.2))
    clips.set_arm(k2, "l", 40.0, 70.0, out_deg=60.0)
    k2.solve()
    keys = [(0.0, k0, "smooth"), (0.35, k1, "smooth"), (0.80, k2, "out"), (1.25, k2, "linear"),
            (FRAMES["roar"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["roar"])


def _combo_a_end(holder, rest):
    wide = {"l": ((0.16, -0.30, 0.0), 22.0, 0.0, 0.0), "r": ((-0.14, 0.16, 0.0), -10.0, 0.0, 0.0)}
    k = sm.body(rest, pelvis=(14.0, 0.0, 22.0), spine=(9.0, 0.0, 16.0), neck=(-6.0, -6.0), head=(-8.0, 0.0, -10.0),
                feet=wide, drop=0.28, clav=(4.0, -6.0))
    pel = k.P["pelvis"]
    g = pel + np.array([0.30, -0.42, 0.18])
    hold_ram(holder, k, g, ground_axis(g, 0.55, 0.85, rest, lift=0.10), pole_r=(-0.5, 0.2, 0.4),
             pole_l=(0.8, 0.2, -0.2), left_m=0.55)
    return k


def combo_a(holder, rest):
    k0 = idle0(holder, rest)
    back = {"l": ((0.08, -0.22, 0.0), 14.0, 0.0, 0.0), "r": ((-0.10, 0.20, 0.0), -24.0, 0.0, 0.0)}
    # the draw: wound to his right, the ram cocked high back over the right shoulder in both fists
    kw = sm.body(rest, pelvis=(-4.0, 0.0, -16.0), spine=(-6.0, 0.0, -18.0), neck=(2.0, 8.0), head=(4.0, 0.0, 12.0),
                 back=0.04, feet=back, drop=0.16, clav=(-12.0, 16.0))
    sh = kw.P["upperarm_r"]
    hold_ram(holder, kw, sh + np.array([-0.06, -0.20, 0.30]), (-0.40, 0.55, 0.73), pole_r=(-0.7, 0.3, -0.4),
             pole_l=(0.6, -0.3, -0.5))
    # the blow: swung down across his front, the weight thrown onto the left foot
    wide = {"l": ((0.16, -0.30, 0.0), 22.0, 0.0, 0.0), "r": ((-0.14, 0.16, 0.0), -10.0, 0.0, 0.0)}
    kh = sm.body(rest, pelvis=(8.0, 0.0, 14.0), spine=(6.0, 0.0, 12.0), neck=(-4.0, -4.0), head=(-6.0, 0.0, -8.0),
                 feet=wide, drop=0.22)
    pel = kh.P["pelvis"]
    g = pel + np.array([0.12, -0.46, 0.50])
    hold_ram(holder, kh, g, unit(np.array([0.50, -0.78, -0.30])), pole_r=(-0.4, 0.3, -0.5), pole_l=(0.8, 0.2, -0.3))
    # the follow-through: carried on low past his left knee, the head of the ram near the ground
    kf = _combo_a_end(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.50, kw, "out"), (COMBO_A_HIT, kh, "in"), (1.00, kf, "out"),
            (FRAMES["combo_a"] / FPS, kf, "linear")]

    def two(t):
        return min(1.0, max(0.0, (t - 0.12) / 0.3))   # the left fist joins the ram as it comes off the shoulder
    return _keyed_two(holder, rest, keys, FRAMES["combo_a"], two)


def combo_b(holder, rest):
    k0 = _combo_a_end(holder, rest)
    feet = {"l": ((0.10, -0.24, 0.0), 16.0, 0.0, 0.0), "r": ((-0.12, 0.18, 0.0), -14.0, 0.0, 0.0)}
    # the draw: up across to his left shoulder, wound to his left
    kw = sm.body(rest, pelvis=(0.0, 0.0, 18.0), spine=(-4.0, 0.0, 22.0), neck=(0.0, -10.0), head=(2.0, 0.0, -12.0),
                 feet=feet, drop=0.14, clav=(10.0, -8.0))
    sh = kw.P["upperarm_l"]
    hold_ram(holder, kw, sh + np.array([0.00, -0.42, -0.06]), (0.55, 0.62, 0.55), pole_r=(-0.3, -0.6, -0.5),
             pole_l=(0.8, 0.3, -0.3))
    # the blow: flat across his front to his right at his chest's height
    kh = sm.body(rest, pelvis=(4.0, 0.0, -14.0), spine=(4.0, 0.0, -18.0), neck=(-2.0, 6.0), head=(-4.0, 0.0, 10.0),
                 feet=feet, drop=0.20)
    sh = kh.P["upperarm_r"]
    hold_ram(holder, kh, sh + np.array([0.20, -0.60, -0.30]), unit(np.array([-0.55, -0.80, 0.05])),
             pole_r=(-0.8, 0.2, -0.4), pole_l=(0.4, -0.5, -0.5))
    # carried round to his right, the ram's weight pulling him on
    kf = sm.body(rest, pelvis=(6.0, 0.0, -24.0), spine=(4.0, 0.0, -24.0), neck=(-2.0, 8.0), head=(-4.0, 0.0, 12.0),
                 feet=feet, drop=0.22)
    sh = kf.P["upperarm_r"]
    hold_ram(holder, kf, sh + np.array([-0.10, -0.40, -0.40]), unit(np.array([-0.95, 0.15, -0.15])),
             pole_r=(-0.6, 0.5, -0.4), pole_l=(0.2, -0.6, -0.5))
    # heaved back up onto the shoulder
    ku = sm.body(rest, pelvis=(2.0, 0.0, -6.0), spine=(0.0, 0.0, -6.0), drop=0.10,
                 feet={"l": ((0.06, -0.12, 0.0), 8.0, 0.0, 0.0), "r": ((-0.06, 0.10, 0.0), -10.0, 0.0, 0.0)})
    shoulder_carry(holder, ku)
    sm.free_left(ku, -8.0, 30.0, 24.0)
    k5 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.50, kw, "out"), (COMBO_B_HIT, kh, "in"), (1.00, kf, "out"), (1.55, ku, "smooth"),
            (FRAMES["combo_b"] / FPS, k5, "smooth")]

    def two(t):
        return 1.0 if t <= 1.25 else max(0.0, 1.0 - (t - 1.25) / 0.3)
    return _keyed_two(holder, rest, keys, FRAMES["combo_b"], two)


def _keyed_two(holder, rest, keys, frames, two):
    """sm.keyed with the left fist held on the ram by weight ``two(t)`` (its own blended pose at 0)."""
    ok = _ok()
    out = []
    for f in range(frames + 1):
        t = f / FPS
        i = 0
        while i < len(keys) - 2 and t > keys[i + 1][0]:
            i += 1
        t0, p0, _e0 = keys[i]
        t1, p1, e1 = keys[i + 1]
        u = 0.0 if t1 <= t0 else sm.ease((t - t0) / (t1 - t0), e1)
        pose = sm.blend(rest, p0, p1, u)
        w = two(t)
        if w > 1e-3:
            g, a = holder.grip_posed(pose.solve(), "r")
            gl = g + a * (LEFT_ON_M / ok.F)
            if w < 0.999:
                here, _ = holder.grip_posed(pose, "l")
                gl = here * (1.0 - w) + gl * w
            holder.hold(pose, "l", gl, a, pole=(0.7, 0.2, -0.5))
        out.append(pose.solve())
    return out


def slam(holder, rest):
    k0 = idle0(holder, rest)
    stance = {"l": ((0.10, -0.30, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.22, 0.0), -16.0, 0.0, 0.0)}
    # up: the ram lifted upright over his head in both fists
    ku = sm.body(rest, pelvis=(2.0, 0.0, 0.0), spine=(-2.0, 0.0, 0.0), neck=(-4.0, 0.0), head=(-10.0, 0.0, 0.0),
                 feet=stance, drop=0.08, clav=(-14.0, 14.0))
    hd = ku.P["head"]
    hold_ram(holder, ku, hd + np.array([0.0, -0.30, 0.22]), (0.0, 0.05, 1.0), pole_r=(-0.7, 0.1, -0.4),
             pole_l=(0.7, 0.1, -0.4), left_m=0.55)
    # the anticipation: rocked back on his heels, arched, the ram tipped back over his head, the knees giving
    kb = sm.body(rest, pelvis=(-10.0, 0.0, 0.0), spine=(-14.0, 0.0, 0.0), neck=(4.0, 0.0), head=(8.0, 0.0, 0.0),
                 back=0.06, feet=stance, drop=0.20, clav=(-16.0, 16.0))
    hd = kb.P["head"]
    hold_ram(holder, kb, hd + np.array([0.0, -0.14, 0.36]), unit(np.array([0.0, 0.62, 0.78])),
             pole_r=(-0.7, 0.1, -0.4), pole_l=(0.7, 0.1, -0.4), left_m=0.55)
    # the blow: bent hard over the front knee, the fists low before him, the ram's head on the ground ahead
    kh = sm.body(rest, pelvis=(20.0, 0.0, 0.0), spine=(14.0, 0.0, 0.0), neck=(-10.0, 0.0), head=(-16.0, 0.0, 0.0),
                 back=0.02, feet=stance, drop=0.46, clav=(6.0, -6.0))
    sh = 0.5 * (kh.P["upperarm_l"] + kh.P["upperarm_r"])
    g = sh + np.array([0.0, -0.36, -0.58])
    hold_ram(holder, kh, g, ground_axis(g, 1.0, 0.0, rest), pole_r=(-0.7, 0.2, 0.3), pole_l=(0.7, 0.2, 0.3),
             left_m=0.55)
    # the overshoot: lower still, the head of the ram held where it struck
    ko = sm.body(rest, pelvis=(25.0, 0.0, 0.0), spine=(17.0, 0.0, 0.0), neck=(-12.0, 0.0), head=(-19.0, 0.0, 0.0),
                 back=0.02, feet=stance, drop=0.54, clav=(8.0, -8.0))
    head = g + ground_axis(g, 1.0, 0.0, rest) * ram_length()
    sh = 0.5 * (ko.P["upperarm_l"] + ko.P["upperarm_r"])
    toward = unit(head - (sh + np.array([0.0, -0.55, -0.84])))
    hold_ram(holder, ko, head - toward * ram_length(), toward, pole_r=(-0.7, 0.2, 0.3), pole_l=(0.7, 0.2, 0.3),
             left_m=0.55)
    # levering it up: still bent, the head of the ram lifting off the ground
    kl = sm.body(rest, pelvis=(14.0, 0.0, -4.0), spine=(8.0, 0.0, -4.0), neck=(-6.0, 0.0), head=(-8.0, 0.0, 0.0),
                 back=0.02, feet=stance, drop=0.30)
    sh = kl.P["upperarm_r"]
    g = sh + np.array([0.10, -0.55, -0.60])
    hold_ram(holder, kl, g, ground_axis(g, 1.0, -0.25, rest, lift=0.5), pole_r=(-0.7, 0.2, 0.0),
             pole_l=(0.7, 0.2, 0.0))
    k5 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.55, ku, "smooth"), (1.20, kb, "out"), (SLAM_HIT, kh, "in"), (1.65, ko, "out"),
            (2.40, kl, "smooth"), (FRAMES["slam"] / FPS, k5, "smooth")]

    def two(t):
        return 1.0 if t <= 2.5 else max(0.0, 1.0 - (t - 2.5) / 0.35)
    return _keyed_two(holder, rest, keys, FRAMES["slam"], two)


def charge_key(holder, rest, pose=None, phi=0.0):
    """The ram levelled under his right arm as a ram is carried: the right fist at his hip, the left on the log
    ahead, the head down behind it."""
    from clips import X, Y, Z, rot
    if pose is None:
        pose = sm.body(rest, pelvis=(14.0, 0.0, 0.0), spine=(10.0, 0.0, -4.0), neck=(-10.0, 0.0), head=(-16.0, 0.0, 0.0),
                       feet={"l": ((0.06, -0.28, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.22, 0.0), -8.0, 0.0, 0.0)},
                       drop=0.26)
    else:
        bob = math.sin(2.0 * phi)
        for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
            pose.set_rel(b, rot(X, (10.0 + 1.0 * bob) * k) @ rot(Z, -4.0 * k) @ rot(Y, 0.0))
        pose.set_rel("neck_01", rot(X, -10.0))
        pose.set_rel("head", rot(X, -16.0))
        pose.solve()
    hip = pose.P["thigh_r"]
    g = hip + np.array([-0.02, -0.30, 0.44])
    hold_ram(holder, pose, g, unit(np.array([0.10, -1.0, 0.06])), pole_r=(-0.6, 0.4, -0.5), pole_l=(0.6, -0.2, -0.6),
             left_m=0.55)
    return pose.solve()


def charge(holder, rest):
    k0 = idle0(holder, rest)
    k1 = charge_key(holder, rest)
    keys = [(0.0, k0, "smooth"), (FRAMES["charge"] / FPS, k1, "out")]
    return sm.keyed(holder, rest, keys, FRAMES["charge"])


def charge_run(holder, rest, gaits):
    import brute as br
    out = []
    frames = FRAMES["charge_run"]
    for f in range(frames + 1):
        phi = 2.0 * math.pi * f / frames
        pose = br.brute_gait_pose(gaits["run"], phi)
        out.append(charge_key(holder, rest, pose, phi))
    return out


def reel(holder, rest):
    import clips
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(-8.0, 0.0, 4.0), spine=(-10.0, 2.0, 4.0), neck=(-10.0, 6.0), head=(-18.0, 4.0, 8.0),
                 back=0.10, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.38, 0.0), -16.0, 0.0, 0.0)},
                 drop=0.12)
    g1 = k1.P["upperarm_r"] + np.array([-0.55, -0.10, -0.80])
    holder.hold(k1, "r", g1, ground_axis(g1, 0.2, -0.95, rest, lift=0.3), pole=(-0.4, 0.6, 0.3))
    sm.free_left(k1, -8.0, 30.0, 26.0)
    # stumbling, hunched, the left hand to his brow (the crown), the ram's head on the ground
    k2 = sm.body(rest, pelvis=(18.0, 0.0, -6.0), spine=(10.0, -3.0, -4.0), neck=(14.0, -6.0), head=(16.0, 0.0, -10.0),
                 back=0.12, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.34, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.38)
    g2 = k2.P["thigh_r"] + np.array([-0.40, -0.36, -0.22])
    holder.hold(k2, "r", g2, ground_axis(g2, 0.5, -0.6, rest), pole=(-0.6, 0.3, -0.2))
    hd = k2.P["head"]
    holder.hold(k2, "l", hd + np.array([0.12, -0.30, 0.02]), unit(np.array([-0.5, 0.2, 0.8])), pole=(0.9, -0.2, -0.3),
                palm=(0.0, 1.0, 0.0))
    k3 = sm.body(rest, pelvis=(14.0, 0.0, 5.0), spine=(8.0, 3.0, 4.0), neck=(8.0, 8.0), head=(10.0, 0.0, 8.0),
                 back=0.10, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.34, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.30)
    g3 = k3.P["thigh_r"] + np.array([-0.38, -0.40, -0.20])
    holder.hold(k3, "r", g3, ground_axis(g3, 0.5, -0.6, rest), pole=(-0.6, 0.3, -0.2))
    clips.set_arm(k3, "l", -16.0, 44.0, out_deg=18.0)
    k3.solve()
    k4 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.80, k2, "smooth"), (1.60, k3, "smooth"),
            (FRAMES["reel"] / FPS, k4, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["reel"])


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0):
    """Down on his right knee (Stoneback's kneel's legs), the left hand on the raised left knee, the ram planted
    head-down at his right side."""
    l1, l2 = sm._leg_lengths(rest, "r")
    pel = (9.0 * lean, 0.0, -6.0)
    spine = (10.0 * lean, 2.0, -4.0)
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
    k = sm.body(rest, pelvis=pel, spine=spine, neck=(10.0 * lean, -4.0), head=(12.0 * lean, 0.0, -6.0),
                feet=feet, drop=drop, clav=(4.0, 6.0))
    kl = k.P["calf_l"]
    holder.hold(k, "l", kl + np.array([0.02, -0.12, 0.10]), np.array([-0.35, -0.55, -0.75]), pole=(0.9, 0.2, -0.1),
                palm=(0.0, 0.0, -1.0))
    g = k.P["upperarm_r"] + np.array([-0.40, -0.30, -0.50])
    holder.hold(k, "r", g, ground_axis(g, 0.25, -0.35, rest), pole=(-0.6, 0.3, -0.2))
    return k.solve()


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
    k3 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.35, kp, "smooth"), (0.80, ku, "out"), (FRAMES["rise"] / FPS, k3, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["rise"])


def death(holder, rest):
    import clips
    from clips import X, Y, Z, rot
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 6.0), spine=(-8.0, 2.0, 4.0), neck=(-12.0, 4.0), head=(-20.0, 4.0, 6.0),
                 back=0.10, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.32, 0.0), -14.0, 0.0, 0.0)},
                 drop=0.12)
    clips.set_arm(k1, "r", 20.0, 30.0, out_deg=44.0)
    sm.free_left(k1, -26.0, 34.0, 36.0)
    # on his knees, sagging back, the arms hanging
    kn = sm.body(rest, pelvis=(-4.0, 0.0, 0.0), spine=(-6.0, 0.0, 0.0), neck=(-8.0, 0.0), head=(-14.0, 0.0, -6.0),
                 feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)}, drop=1.0)
    clips.set_arm(kn, "r", -14.0, 18.0, out_deg=22.0)
    clips.set_arm(kn, "l", -12.0, 20.0, out_deg=20.0)
    kn.solve()
    # on his back: toppled from the knees backward, the knees up, the arms flung out, the head turned
    down = clips.Pose(rest)
    pz = float(rest.head["pelvis"][2])
    down.offset = np.array([0.0, 0.62, -pz + 0.30])
    down.set_rel("pelvis", rot(X, -82.0) @ rot(Y, 6.0))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        down.set_rel(b, rot(X, -3.0 * k))
    down.set_rel("neck_01", rot(X, 14.0))
    down.set_rel("head", rot(X, 10.0) @ rot(Z, 34.0))
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        down.set_rel("thigh_" + s, rot(X, 48.0) @ rot(Z, 8.0 * sgn))
        down.set_rel("calf_" + s, rot(X, -70.0))
        down.set_rel("foot_" + s, rot(X, 20.0))
    down.solve()
    clips.set_arm(down, "l", 20.0, 30.0, out_deg=70.0)
    clips.set_arm(down, "r", 30.0, 26.0, out_deg=76.0)
    down.solve()
    keys = [(0.0, k0, "smooth"), (0.40, k1, "out"), (1.30, kn, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- all of them

def make_poses(person, ram):
    """Every clip's solved frames: {name: [pose, ...]}, the gaits, and the checks (the crown's height in the idle and
    the walk, the left fist's distance from the ram in the two-handed keys)."""
    import brute as br
    import clips
    import stoneback as sb
    ok = _ok()
    rest = person.rest
    holder = sb.Holder(person)
    gaits = {"walk": clips.Gait(rest, "king_walk", 32), "run": clips.Gait(rest, "king_run", 32)}
    poses = {"idle": [idle_pose(holder, rest, f, 60) for f in range(61)],
             "walk": [gait_pose(holder, gaits["walk"], 2.0 * math.pi * f / 32) for f in range(33)],
             "run": [gait_pose(holder, gaits["run"], 2.0 * math.pi * f / 32, run=True) for f in range(33)]}
    for name in FRAMES:
        if name == "charge_run":
            poses[name] = charge_run(holder, rest, gaits)
        else:
            poses[name] = globals()[name](holder, rest)
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]

    def crown(p):
        return float((p.P["head"] + p.D["head"] @ local)[2]) * ok.F
    checks = {"crown_m": {c: [br.r6(min(crown(p) for p in poses[c])), br.r6(max(crown(p) for p in poses[c]))]
                          for c in ("idle", "walk", "run", "roar")}}
    off = {}
    for c, f in (("slam", int(SLAM_HIT * FPS)), ("combo_a", int(COMBO_A_HIT * FPS)), ("charge", FRAMES["charge"])):
        p = poses[c][f]
        gr, ar = holder.grip_posed(p, "r")
        gl, _ = holder.grip_posed(p, "l")
        q = gl - gr
        off[c] = br.r6(float(np.linalg.norm(q - ar * float(q @ ar))) * ok.F)
    checks["left_off_ram_m"] = off
    checks["kneel"] = sb_kneel_frames(person, poses)
    return poses, gaits, checks


KNEEL_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
               "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r")


def sb_kneel_frames(person, poses):
    """Each KNEEL_BONES head and frame in the idle's first key and the kneel's last, in his actor's space and real
    metres (tools/builders/titans.gd moves each hurtbox and lock anchor with its bone, as Stoneback's)."""
    import brute as br
    import stoneback as sb
    ok = _ok()
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = sb.TO_ACTOR @ p.D[b] @ sb.TO_ACTOR.T
            d[key] = {"head": [br.r6(x) for x in sb.TO_ACTOR @ p.P[b] * ok.F], "basis": [br.r6(x) for x in R.ravel()]}
    out["pelvis_m"] = br.r6(float(poses["kneel"][-1].P["pelvis"][2]) * ok.F)
    return out
