"""The Rootwarden's clips (B3): key poses solved as Stoneback's and the Ogre King's (``clips.Pose``, the legs by their
feet, a hand placed by ``stoneback.Holder.hold``) and slerped between on eases (``stoneback_moves.keyed``). The left
arm is his root-arm (the roots hang from it); the right hand tears up the dead trees he throws.

  dormant   (90, a loop) rooted and asleep: the head bowed, the shoulders slumped, the root-arm hanging straight down
            (its roots run into the ground), a slow breath
  idle, walk, run
            awake; the walk and run his own long, careful gait (the brutes' at his stride, carried tall)
  roar      (60) the wake and the rage: the arms flung wide, the root-arm high, the head thrown back
  uproot    (72) phase 2: crouched with the root-arm down in the soil, he wrenches it up across his chest, stamps,
            straightens into the roar's pose
  lash      (54) the root-lash: the root-arm drawn across him to his right, swept out wide to his left at shoulder
            height (LASH_HIT), carried on round
  erupt     (60) the root-arm raised, driven down into the ground before him (ERUPT_HIT), held, pulled up: the roots
            erupt along a line toward the giant
  snare     (48) the root-arm drawn back low, thrust forward and down, the fingers spread (SNARE_HIT), the fist closed
            and pulled up: the roots bind the ground under the giant
  rip       (36) crouched to his right, the right hand closes on a dead tree (RIP_GRIP) and tears it out of the ground
  hurl      (40) from the rip's end the tree drawn back over his right shoulder and hurled (HURL_RELEASE)
  stomp     (40) the right knee raised high, the foot driven down (STOMP_HIT)
  reel      (60) staggered: the head snapped back, a step back, the right hand to his brow
  kneel, rise (24, 36) a shin broken: down on the right knee, the left hand on the left knee, the right fist on the
            ground; up again
  death     (96) struck down: he sags to his knees and falls forward onto his face like a felled tree

Every number below is in design metres (the stage-1 giant's), Z up, -Y his front, +X his left.
"""
from __future__ import annotations

import math

import numpy as np

import stoneback_moves as sm

FPS = sm.FPS
FRAMES = {"dormant": 90, "roar": 60, "uproot": 72, "lash": 54, "erupt": 60, "snare": 48, "rip": 36, "hurl": 40,
          "stomp": 40, "reel": 60, "kneel": 24, "rise": 36, "death": 96}
LOOPS = ("idle", "walk", "run", "dormant")
LASH_HIT = 1.00
ERUPT_HIT = 1.05
SNARE_HIT = 0.80
RIP_GRIP = 0.70
HURL_RELEASE = 0.80
STOMP_HIT = 0.75
KNEEL_HIT = 0.55
UPROOT_TEAR = 1.10
# the rig's keys of each strike: [start, wound (the end of the draw), hit (the first active tick), past (the end of the
# active phase), end] (scripts/presentation/rootwarden_rig.gd reads them from the manifest)
KEYS = {"lash": [0.0, 0.70, LASH_HIT, 1.30, FRAMES["lash"] / FPS],
        "erupt": [0.0, 0.75, ERUPT_HIT, 1.40, FRAMES["erupt"] / FPS],
        "snare": [0.0, 0.55, SNARE_HIT, 1.10, FRAMES["snare"] / FPS],
        "hurl": [0.0, 0.55, HURL_RELEASE, 1.00, FRAMES["hurl"] / FPS],
        "stomp": [0.0, 0.50, STOMP_HIT, 0.95, FRAMES["stomp"] / FPS],
        "kneel_hit": KNEEL_HIT, "rip_grip": RIP_GRIP, "hurl_release": HURL_RELEASE, "uproot_tear": UPROOT_TEAR}


def _rw():
    import rootwarden as rw
    return rw


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


def arms(pose, l=(-4.0, 18.0, 16.0), r=(-4.0, 18.0, 16.0)):
    """Both arms hanging (clips.set_arm: swing, elbow, out)."""
    import clips
    clips.set_arm(pose, "l", l[0], l[1], out_deg=l[2])
    clips.set_arm(pose, "r", r[0], r[1], out_deg=r[2])
    return pose.solve()


def idle_pose(rest, f, frames):
    import brute as br
    import clips
    pose = br.brute_idle(rest, f, frames)
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    arms(pose, l=(-2.0 + 1.5 * b, 10.0, 12.0), r=(-4.0 - 1.5 * b, 20.0, 15.0))
    pose.set_rel("neck_01", clips.rot(clips.X, 4.0))
    return pose.solve()


def dormant_pose(rest, f, frames):
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    k = sm.body(rest, pelvis=(4.0, 0.0, 0.0), spine=(7.0 + 1.5 * b, 0.0, 0.0), neck=(16.0, 0.0),
                head=(20.0 + 1.0 * b, 0.0, -4.0), drop=0.07 + 0.006 * b, clav=(4.0, 4.0),
                feet={"l": ((0.03, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.03, 0.05, 0.0), -8.0, 0.0, 0.0)})
    return arms(k, l=(-2.0, 4.0, 6.0), r=(-6.0, 22.0, 13.0))


def gait_pose(gait, phi, run=False):
    import brute as br
    import clips
    pose = br.brute_gait_pose(gait, phi)
    swing = gait.g["arm_swing_deg"] * (1.5 if run else 1.0) * math.sin(phi)
    clips.set_arm(pose, "l", -3.0 + 0.6 * swing, 12.0, out_deg=12.0)
    clips.set_arm(pose, "r", -4.0 - swing, 26.0 if run else 20.0, out_deg=15.0)
    pose.set_rel("neck_01", clips.rot(clips.X, 5.0))
    return pose.solve()


def idle0(rest):
    return idle_pose(rest, 0, 60)


def hand_at(holder, pose, side, at, axis, pole, palm=None):
    holder.hold(pose, side, np.asarray(at, np.float64), unit(axis), pole=pole, palm=palm)
    return pose.solve()


# ----------------------------------------------------------------------------------------------- the clips

def _roar_key(holder, rest, lean=1.0):
    k = sm.body(rest, pelvis=(-4.0 * lean, 0.0, 0.0), spine=(-10.0 * lean, 0.0, 0.0), neck=(-10.0 * lean, 0.0),
                head=(-22.0 * lean, 0.0, 0.0), drop=0.10, clav=(-14.0, -14.0),
                feet={"l": ((0.08, -0.12, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.10, 0.0), -10.0, 0.0, 0.0)})
    hd = k.P["head"]
    hand_at(holder, k, "l", hd + np.array([0.62, -0.10, 0.34]), (0.6, 0.0, 0.8), (0.4, 0.8, -0.3))
    hand_at(holder, k, "r", hd + np.array([-0.60, -0.16, 0.06]), (-0.8, -0.1, 0.4), (-0.4, 0.8, -0.4))
    return k


def roar(holder, rest):
    k0 = idle0(rest)
    k1 = sm.body(rest, pelvis=(8.0, 0.0, 0.0), spine=(10.0, 0.0, 0.0), neck=(8.0, 0.0), head=(10.0, 0.0, 0.0),
                 drop=0.16, feet={"l": ((0.08, -0.12, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.10, 0.0), -10.0, 0.0, 0.0)})
    arms(k1, l=(-10.0, 50.0, 30.0), r=(-10.0, 50.0, 30.0))
    k2 = _roar_key(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.45, k1, "smooth"), (0.95, k2, "out"), (1.55, k2, "linear"),
            (FRAMES["roar"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["roar"])


def _rooted_crouch(holder, rest, depth=1.0):
    """Crouched over the root-arm driven into the soil at his left-front."""
    k = sm.body(rest, pelvis=(18.0 * depth, 0.0, 8.0), spine=(16.0 * depth, -4.0, 8.0), neck=(-4.0, 0.0),
                head=(-8.0, 0.0, 0.0), drop=0.18 + 0.20 * depth, clav=(10.0, 0.0),
                feet={"l": ((0.10, -0.24, 0.0), 14.0, 0.0, 0.0), "r": ((-0.10, 0.18, 0.0), -12.0, 0.0, 0.0)})
    pel = k.P["pelvis"]
    hand_at(holder, k, "l", np.array([pel[0] + 0.34, pel[1] - 0.48, 0.08]), (0.15, -0.25, -1.0), (0.8, 0.4, 0.2))
    arms_r = k.solve()
    import clips
    clips.set_arm(arms_r, "r", -24.0, 40.0, out_deg=26.0)
    return k.solve()


def uproot(holder, rest):
    k0 = dormant_pose(rest, 0, FRAMES["dormant"])
    k1 = _rooted_crouch(holder, rest, 1.0)
    # the wrench: the root-arm torn up across his chest, the trunk twisted to his right, the knees still bent
    k2 = sm.body(rest, pelvis=(6.0, 0.0, -14.0), spine=(-4.0, 4.0, -22.0), neck=(-6.0, 8.0), head=(-12.0, 0.0, 10.0),
                 drop=0.20, feet={"l": ((0.12, -0.26, 0.0), 14.0, 0.0, 0.0), "r": ((-0.12, 0.20, 0.0), -14.0, 0.0, 0.0)})
    sh = k2.P["upperarm_r"]
    hand_at(holder, k2, "l", sh + np.array([0.10, -0.40, 0.22]), (-0.7, -0.3, 0.6), (0.6, -0.2, -0.8))
    import clips
    clips.set_arm(k2, "r", 10.0, 40.0, out_deg=34.0)
    k2.solve()
    k3 = _roar_key(holder, rest, 0.8)
    k4 = idle0(rest)
    keys = [(0.0, k0, "smooth"), (0.55, k1, "smooth"), (UPROOT_TEAR, k2, "in"), (1.65, k3, "out"),
            (2.0, k3, "linear"), (FRAMES["uproot"] / FPS, k4, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["uproot"])


def _lash_end(holder, rest):
    k = sm.body(rest, pelvis=(4.0, 0.0, 30.0), spine=(4.0, 0.0, 26.0), neck=(-2.0, -8.0), head=(-4.0, 0.0, -10.0),
                drop=0.16, feet={"l": ((0.14, -0.10, 0.0), 30.0, 0.0, 0.0), "r": ((-0.12, 0.20, 0.0), -6.0, 0.0, 0.0)})
    sh = k.P["upperarm_l"]
    hand_at(holder, k, "l", sh + np.array([0.80, 0.30, -0.18]), (0.9, 0.4, -0.2), (0.2, 0.3, -0.9))
    import clips
    clips.set_arm(k, "r", -14.0, 34.0, out_deg=20.0)
    return k.solve()


def lash(holder, rest):
    import clips
    k0 = idle0(rest)
    feet = {"l": ((0.10, -0.20, 0.0), 6.0, 0.0, 0.0), "r": ((-0.12, 0.16, 0.0), -24.0, 0.0, 0.0)}
    # the draw: wound to his right, the root-arm across his chest, its hand by his right shoulder
    kw = sm.body(rest, pelvis=(2.0, 0.0, -20.0), spine=(-2.0, 0.0, -24.0), neck=(0.0, 10.0), head=(2.0, 0.0, 16.0),
                 drop=0.14, feet=feet, clav=(12.0, -6.0))
    sh = kw.P["upperarm_r"]
    hand_at(holder, kw, "l", sh + np.array([-0.10, -0.38, -0.04]), (-0.8, 0.2, -0.4), (0.4, -0.5, -0.7))
    clips.set_arm(kw, "r", 16.0, 30.0, out_deg=26.0)
    kw.solve()
    # the sweep: the arm flung straight out to his left-front at shoulder height
    kh = sm.body(rest, pelvis=(4.0, 0.0, 18.0), spine=(2.0, 0.0, 18.0), neck=(-2.0, -6.0), head=(-4.0, 0.0, -8.0),
                 drop=0.18, feet=feet)
    sh = kh.P["upperarm_l"]
    hand_at(holder, kh, "l", sh + np.array([0.55, -0.62, -0.06]), (0.6, -0.8, -0.05), (0.0, 0.3, -1.0))
    clips.set_arm(kh, "r", -10.0, 34.0, out_deg=22.0)
    kh.solve()
    kf = _lash_end(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.70, kw, "out"), (LASH_HIT, kh, "in"), (1.30, kf, "out"),
            (FRAMES["lash"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["lash"])


def erupt(holder, rest):
    import clips
    k0 = idle0(rest)
    feet = {"l": ((0.12, -0.30, 0.0), 10.0, 0.0, 0.0), "r": ((-0.10, 0.22, 0.0), -16.0, 0.0, 0.0)}
    # up: the root-arm raised high over him, the trunk arched back
    ku = sm.body(rest, pelvis=(-6.0, 0.0, 6.0), spine=(-10.0, 0.0, 6.0), neck=(-4.0, 0.0), head=(-10.0, 0.0, 0.0),
                 drop=0.12, feet=feet, clav=(-16.0, 0.0))
    hd = ku.P["head"]
    hand_at(holder, ku, "l", hd + np.array([0.24, 0.10, 0.52]), (0.1, 0.2, 1.0), (0.8, 0.0, -0.4))
    clips.set_arm(ku, "r", -14.0, 36.0, out_deg=30.0)
    ku.solve()
    # down: bent hard over the front knee, the root-arm's fist driven into the ground before him
    kh = sm.body(rest, pelvis=(24.0, 0.0, 6.0), spine=(20.0, 0.0, 4.0), neck=(-12.0, 0.0), head=(-14.0, 0.0, 0.0),
                 drop=0.42, feet=feet, clav=(10.0, -4.0))
    pel = kh.P["pelvis"]
    hand_at(holder, kh, "l", np.array([pel[0] + 0.16, pel[1] - 0.62, 0.05]), (0.05, -0.30, -1.0), (0.8, 0.4, 0.1))
    clips.set_arm(kh, "r", -30.0, 40.0, out_deg=34.0)
    kh.solve()
    ko = sm.body(rest, pelvis=(27.0, 0.0, 6.0), spine=(22.0, 0.0, 4.0), neck=(-14.0, 0.0), head=(-16.0, 0.0, 0.0),
                 drop=0.46, feet=feet, clav=(10.0, -4.0))
    pel = ko.P["pelvis"]
    hand_at(holder, ko, "l", np.array([pel[0] + 0.16, pel[1] - 0.60, 0.02]), (0.05, -0.30, -1.0), (0.8, 0.4, 0.1))
    clips.set_arm(ko, "r", -30.0, 40.0, out_deg=34.0)
    ko.solve()
    keys = [(0.0, k0, "smooth"), (0.75, ku, "out"), (ERUPT_HIT, kh, "in"), (1.40, ko, "out"),
            (FRAMES["erupt"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["erupt"])


def snare(holder, rest):
    import clips
    k0 = idle0(rest)
    feet = {"l": ((0.10, -0.26, 0.0), 8.0, 0.0, 0.0), "r": ((-0.10, 0.18, 0.0), -14.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(-2.0, 0.0, 14.0), spine=(-4.0, 0.0, 16.0), neck=(0.0, -6.0), head=(0.0, 0.0, -8.0),
                 drop=0.14, feet=feet)
    pel = kw.P["pelvis"]
    hand_at(holder, kw, "l", pel + np.array([0.36, 0.30, -0.02]), (0.2, 0.6, -0.8), (0.6, -0.6, -0.4))
    clips.set_arm(kw, "r", -8.0, 30.0, out_deg=20.0)
    kw.solve()
    kh = sm.body(rest, pelvis=(14.0, 0.0, -6.0), spine=(12.0, 0.0, -8.0), neck=(-8.0, 4.0), head=(-10.0, 0.0, 6.0),
                 drop=0.26, feet=feet)
    sh = kh.P["upperarm_l"]
    hand_at(holder, kh, "l", sh + np.array([0.0, -0.80, -0.42]), (0.0, -0.8, -0.6), (0.6, 0.2, -0.8),
            palm=(0.0, 0.0, -1.0))
    clips.set_arm(kh, "r", -24.0, 36.0, out_deg=24.0)
    kh.solve()
    kp = sm.body(rest, pelvis=(4.0, 0.0, -4.0), spine=(-2.0, 0.0, -6.0), neck=(-4.0, 2.0), head=(-8.0, 0.0, 4.0),
                 drop=0.16, feet=feet)
    sh = kp.P["upperarm_l"]
    hand_at(holder, kp, "l", sh + np.array([0.0, -0.58, 0.10]), (0.0, -0.4, 0.9), (0.8, 0.2, -0.6))
    clips.set_arm(kp, "r", -12.0, 32.0, out_deg=22.0)
    kp.solve()
    keys = [(0.0, k0, "smooth"), (0.55, kw, "out"), (SNARE_HIT, kh, "in"), (1.10, kp, "out"),
            (FRAMES["snare"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["snare"])


def rip_key(holder, rest, depth):
    """Crouched to his right, the right fist on the dead tree (upright), ``depth`` 1 at the ground, 0 risen."""
    import clips
    k = sm.body(rest, pelvis=(20.0 * depth, 0.0, -16.0 * depth), spine=(16.0 * depth, 0.0, -12.0 * depth),
                neck=(-8.0 * depth, 6.0), head=(-8.0 * depth, 0.0, 6.0), drop=0.08 + 0.40 * depth,
                feet={"l": ((0.08, -0.16, 0.0), 8.0, 0.0, 0.0), "r": ((-0.16, 0.06, 0.0), -24.0, 0.0, 0.0)})
    pel = k.P["pelvis"]
    grip = np.array([pel[0] - 0.40, pel[1] - 0.28, 0.12 + (pel[2] - 0.12) * (0.75 - 0.75 * depth) + 0.12])
    hand_at(holder, k, "r", grip, (0.0, 0.0, 1.0), (-0.8, 0.4, 0.2))
    clips.set_arm(k, "l", -6.0, 14.0, out_deg=16.0)
    return k.solve()


def rip(holder, rest):
    k0 = idle0(rest)
    kd = rip_key(holder, rest, 1.0)
    ku = rip_key(holder, rest, 0.0)
    keys = [(0.0, k0, "smooth"), (RIP_GRIP, kd, "out"), (FRAMES["rip"] / FPS, ku, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["rip"])


def hurl(holder, rest):
    import clips
    k0 = rip_key(holder, rest, 0.0)
    feet = {"l": ((0.12, -0.30, 0.0), 10.0, 0.0, 0.0), "r": ((-0.12, 0.22, 0.0), -22.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(-6.0, 0.0, -24.0), spine=(-10.0, 0.0, -26.0), neck=(2.0, 10.0), head=(2.0, 0.0, 14.0),
                 back=0.04, drop=0.16, feet=feet, clav=(0.0, -16.0))
    sh = kw.P["upperarm_r"]
    hand_at(holder, kw, "r", sh + np.array([-0.06, 0.10, 0.36]), (0.05, 0.60, 0.8), (-0.6, 0.3, -0.6))
    clips.set_arm(kw, "l", -30.0, 40.0, out_deg=34.0)
    kw.solve()
    kh = sm.body(rest, pelvis=(12.0, 0.0, 18.0), spine=(14.0, 0.0, 20.0), neck=(-8.0, -6.0), head=(-10.0, 0.0, -8.0),
                 drop=0.22, feet=feet)
    sh = kh.P["upperarm_r"]
    hand_at(holder, kh, "r", sh + np.array([0.18, -0.62, 0.24]), (0.10, -0.95, 0.25), (-0.6, 0.4, -0.6))
    clips.set_arm(kh, "l", 10.0, 30.0, out_deg=26.0)
    kh.solve()
    kf = sm.body(rest, pelvis=(16.0, 0.0, 26.0), spine=(16.0, 0.0, 24.0), neck=(-8.0, -8.0), head=(-10.0, 0.0, -10.0),
                 drop=0.24, feet=feet)
    clips.set_arm(kf, "r", -40.0, 18.0, out_deg=8.0)
    clips.set_arm(kf, "l", 16.0, 30.0, out_deg=28.0)
    kf.solve()
    k5 = idle0(rest)
    keys = [(0.0, k0, "smooth"), (0.55, kw, "out"), (HURL_RELEASE, kh, "in"), (1.00, kf, "out"),
            (FRAMES["hurl"] / FPS, k5, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["hurl"])


def stomp(holder, rest):
    k0 = idle0(rest)
    ku = sm.body(rest, pelvis=(-4.0, 0.0, 0.0), spine=(-6.0, 0.0, 0.0), neck=(6.0, 0.0), head=(14.0, 0.0, 0.0),
                 drop=0.10, side=0.04,
                 feet={"l": ((0.04, 0.02, 0.0), 6.0, 0.0, 0.0), "r": ((-0.04, -0.20, 0.36), -6.0, -18.0, 0.0)})
    arms(ku, l=(-14.0, 30.0, 34.0), r=(-14.0, 30.0, 36.0))
    kh = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(12.0, 0.0, 0.0), neck=(-6.0, 0.0), head=(-8.0, 0.0, 0.0),
                 drop=0.30, side=-0.02,
                 feet={"l": ((0.06, 0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, -0.30, 0.0), -10.0, 0.0, 0.0)})
    arms(kh, l=(-24.0, 40.0, 30.0), r=(-24.0, 40.0, 30.0))
    keys = [(0.0, k0, "smooth"), (0.50, ku, "out"), (STOMP_HIT, kh, "in"), (0.95, kh, "linear"),
            (FRAMES["stomp"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["stomp"])


def reel(holder, rest):
    import clips
    k0 = idle0(rest)
    k1 = sm.body(rest, pelvis=(-8.0, 0.0, 4.0), spine=(-10.0, 2.0, 4.0), neck=(-10.0, 6.0), head=(-18.0, 4.0, 8.0),
                 back=0.10, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.36, 0.0), -16.0, 0.0, 0.0)},
                 drop=0.12)
    arms(k1, l=(16.0, 26.0, 40.0), r=(10.0, 30.0, 36.0))
    k2 = sm.body(rest, pelvis=(16.0, 0.0, -6.0), spine=(10.0, -3.0, -4.0), neck=(14.0, -6.0), head=(16.0, 0.0, -10.0),
                 back=0.12, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.32, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.30)
    hd = k2.P["head"]
    hand_at(holder, k2, "r", hd + np.array([-0.10, -0.30, 0.02]), (0.5, 0.2, 0.8), (-0.9, -0.2, -0.3),
            palm=(0.0, 1.0, 0.0))
    clips.set_arm(k2, "l", -10.0, 20.0, out_deg=24.0)
    k2.solve()
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.85, k2, "smooth"), (FRAMES["reel"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["reel"])


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0):
    """Down on his right knee (Stoneback's kneel's legs), the left hand on the raised left knee, the right fist on the
    ground at his right side."""
    l1, l2 = sm._leg_lengths(rest, "r")
    pel = (9.0 * lean, 0.0, -6.0)
    spine = (12.0 * lean, 2.0, -4.0)
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
    sh = k.P["upperarm_r"]
    g = np.array([sh[0] - 0.22, sh[1] - 0.18, 0.06 + 0.4 * (1.0 - depth)])
    holder.hold(k, "r", g, np.array([0.0, -0.3, -1.0]), pole=(-0.8, 0.3, 0.0))
    return k.solve()


def kneel(holder, rest):
    k0 = idle0(rest)
    kb = kneel_key(holder, rest, depth=0.45, lean=1.2)
    kh = kneel_key(holder, rest, depth=1.0, lean=0.9)
    ks = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    keys = [(0.0, k0, "smooth"), (0.28, kb, "in"), (KNEEL_HIT, kh, "in"), (FRAMES["kneel"] / FPS, ks, "out")]
    return sm.keyed(holder, rest, keys, FRAMES["kneel"])


def rise(holder, rest):
    k0 = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    kp = kneel_key(holder, rest, depth=0.85, lean=1.3)
    ku = kneel_key(holder, rest, depth=0.35, lean=0.9)
    k3 = idle0(rest)
    keys = [(0.0, k0, "smooth"), (0.35, kp, "smooth"), (0.80, ku, "out"), (FRAMES["rise"] / FPS, k3, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["rise"])


def death(holder, rest):
    import clips
    from clips import X, Y, Z, rot
    k0 = idle0(rest)
    k1 = sm.body(rest, pelvis=(-10.0, 0.0, 6.0), spine=(-8.0, 2.0, 4.0), neck=(-12.0, 4.0), head=(-20.0, 4.0, 6.0),
                 back=0.10, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.30, 0.0), -14.0, 0.0, 0.0)},
                 drop=0.12)
    arms(k1, l=(20.0, 30.0, 44.0), r=(16.0, 30.0, 40.0))
    # on his knees, sagging forward, the arms hanging
    kn = sm.body(rest, pelvis=(10.0, 0.0, 0.0), spine=(14.0, 0.0, 0.0), neck=(12.0, 0.0), head=(16.0, 0.0, -6.0),
                 feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)}, drop=1.0)
    arms(kn, l=(-6.0, 16.0, 18.0), r=(-8.0, 18.0, 20.0))
    # on his face: toppled forward from the knees like a felled tree, the arms flung out ahead
    down = clips.Pose(rest)
    pz = float(rest.head["pelvis"][2])
    down.offset = np.array([0.0, -0.52, -pz + 0.24])
    down.set_rel("pelvis", rot(X, 84.0) @ rot(Y, -4.0))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        down.set_rel(b, rot(X, 2.0 * k))
    down.set_rel("neck_01", rot(X, -18.0))
    down.set_rel("head", rot(X, -14.0) @ rot(Z, -40.0))
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        down.set_rel("thigh_" + s, rot(X, -76.0) @ rot(Z, 6.0 * sgn))
        down.set_rel("calf_" + s, rot(X, 10.0))
        down.set_rel("foot_" + s, rot(X, -30.0))
    down.solve()
    clips.set_arm(down, "l", -150.0, 20.0, out_deg=40.0)
    clips.set_arm(down, "r", -120.0, 30.0, out_deg=50.0)
    down.solve()
    keys = [(0.0, k0, "smooth"), (0.40, k1, "out"), (1.30, kn, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- all of them

def make_poses(person, pieces):
    """Every clip's solved frames: {name: [pose, ...]}, the gaits, and the checks (the crown's height in the idle,
    the dormant stance, the walk and the run; the root-arm's hand over the ground at rest; the kneel's bones)."""
    import brute as br
    import clips
    import stoneback as sb
    rw = _rw()
    rest = person.rest
    holder = sb.Holder(person)
    gaits = {"walk": clips.Gait(rest, "warden_walk", 32), "run": clips.Gait(rest, "warden_run", 32)}
    poses = {"idle": [idle_pose(rest, f, 60) for f in range(61)],
             "walk": [gait_pose(gaits["walk"], 2.0 * math.pi * f / 32) for f in range(33)],
             "run": [gait_pose(gaits["run"], 2.0 * math.pi * f / 32, run=True) for f in range(33)],
             "dormant": [dormant_pose(rest, f, FRAMES["dormant"]) for f in range(FRAMES["dormant"] + 1)]}
    for name in FRAMES:
        if name == "dormant":
            continue
        poses[name] = globals()[name](holder, rest)
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]

    def crown(p):
        return float((p.P["head"] + p.D["head"] @ local)[2]) * rw.F
    checks = {"crown_m": {c: [br.r6(min(crown(p) for p in poses[c])), br.r6(max(crown(p) for p in poses[c]))]
                          for c in ("idle", "dormant", "walk", "run", "roar")}}
    checks["hand_l_m"] = {c: br.r6(float(poses[c][0].P["hand_l"][2]) * rw.F) for c in ("idle", "dormant")}
    checks["kneel"] = kneel_frames(person, poses)
    checks["idle_pieces"] = idle_pieces(person, poses, pieces)
    return poses, gaits, checks


def idle_pieces(person, poses, pieces):
    """Each plate's centre and extent, posed by the idle's first key, in his actor's space (real m: +X his right,
    -Z his front): tools/builders/titans.gd sets his hurtboxes and lock anchors over them. The extent is the
    piece's half-size along its bone's frame's axes carried into the actor's frame (an AABB)."""
    import brute as br
    import stoneback as sb
    rw = _rw()
    rest = person.rest
    p = poses["idle"][0]
    out = {}
    for name in rw.PLATE_ORDER:
        piece = pieces[name]
        b = rw.PIECE_BONE[name]
        V = np.asarray(piece.V, np.float64)
        posed = p.P[b] + (V - rest.head[b]) @ p.D[b].T
        A = (sb.TO_ACTOR @ posed.T).T * rw.F
        lo, hi = A.min(axis=0), A.max(axis=0)
        out[name] = {"centre": [br.r6(x) for x in 0.5 * (lo + hi)], "size": [br.r6(x) for x in hi - lo],
                     "outer": [br.r6(x) for x in A[np.argmax(np.linalg.norm(A - A.mean(axis=0), axis=1))]]}
    return out


KNEEL_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
               "lowerarm_r", "thigh_l", "thigh_r", "calf_l", "calf_r")


def kneel_frames(person, poses):
    """Each KNEEL_BONES head and frame in the idle's first key and the kneel's last, in his actor's space and real
    metres (tools/builders/titans.gd moves each hurtbox and lock anchor with its bone, as Stoneback's)."""
    import brute as br
    import stoneback as sb
    rw = _rw()
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = sb.TO_ACTOR @ p.D[b] @ sb.TO_ACTOR.T
            d[key] = {"head": [br.r6(x) for x in sb.TO_ACTOR @ p.P[b] * rw.F], "basis": [br.r6(x) for x in R.ravel()]}
    out["pelvis_m"] = br.r6(float(poses["kneel"][-1].P["pelvis"][2]) * rw.F)
    return out
