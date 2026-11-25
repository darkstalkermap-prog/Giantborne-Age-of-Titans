"""The Broken Warden's clips (C2): key poses solved as Stoneback's and the Rootwarden's (``clips.Pose``, the legs by
their feet, a hand placed by ``stoneback.Holder.hold``) and slerped between on eases (``stoneback_moves.keyed``).

The left hand holds the wall-shield by its grip-bar (the shield is the hand's: ``shield_hold`` sets the hand so the
shield's face looks where a key wants it); the right holds the gate's bar by its butt end. Once the shield is gone
(his second phase) the bar is two-handed (the left fist on it LEFT_ON_BAR_M up from the right).

  dormant   (90, a loop) bound into his wall: upright, the shield before him, the bar planted at his right like a
            staff, the head bowed, a slow breath
  idle, walk, run
            the shield carried before his left side, its face to his front; the bar hanging at his right, its tip
            near the ground
  idle2, walk2, run2
            the shield gone: the bar across his body in both hands (the walk and the run his own gait)
  roar      (60) the wake: the shield raised high, the bar thrown up, the head back
  bash      (54) the shield drawn in against him, the weight back; then a lunge, the shield driven out before him
            (BASH_HIT), held, recovered
  hammer    (78) the bar swung up over his right shoulder, the shield up; brought down over the shield's rim to strike
            the ground ahead and to his right (HAMMER_HIT), the bar's tip on the ground, his guard down a while;
            recovered
  sweep     (66) the bar drawn back low on his right, swung round through his front to his left (SWEEP_HIT)
  charge    (36) the charge's wind-up: the shield brought round before him, the shoulder into it, crouched; its last
            frame is held until the run
  charge_run (32, a loop) the run's legs behind the braced shield
  stomp     (40) the right knee raised high behind the shield, the foot driven down (STOMP_HIT)
  reel      (60) staggered: a step back, the head snapped back, the shield arm dropping
  guardbreak (66) his guard broken: the shield struck out wide to his left, the arm flung after it, the trunk
            twisted to his right, a stumble; the shield dragged back before him
  rearm     (72) his second phase: the shield gone, he lets the empty hand drop, grips the bar in both hands and roars
  smash2    (60) the bar raised in both hands over his head, brought down ahead (SMASH2_HIT): its tip strikes the ground
  sweep2    (60) the bar drawn back two-handed to his right and swept round low to his left (SWEEP2_HIT)
  kneel, rise (24, 36) a greave broken: down on the right knee behind the shield planted before him; up again
  death     (96) struck down: he sags to his knees, the shield drops, he falls forward onto his face

Every number below is in design metres (the stage-1 giant's), Z up, -Y his front, +X his left.
"""
from __future__ import annotations

import math

import numpy as np

import stoneback_moves as sm

FPS = sm.FPS
FRAMES = {"dormant": 90, "roar": 60, "bash": 54, "hammer": 78, "sweep": 66, "charge": 36, "charge_run": 32,
          "stomp": 40, "reel": 60, "guardbreak": 66, "rearm": 72, "smash2": 60, "sweep2": 60, "kneel": 24,
          "rise": 36, "death": 96}
LOOPS = ("idle", "walk", "run", "idle2", "walk2", "run2", "dormant", "charge_run")
BASH_HIT = 1.00
HAMMER_HIT = 1.55
SWEEP_HIT = 1.25
STOMP_HIT = 0.75
SMASH2_HIT = 1.30
SWEEP2_HIT = 1.15
KNEEL_HIT = 0.55
REARM_GRIP = 1.10
# the rig's keys of each strike: [start, wound (the end of the draw), hit (the first active tick), past (the end of the
# active phase), end] (scripts/presentation/bastion_rig.gd reads them from the manifest)
KEYS = {"bash": [0.0, 0.70, BASH_HIT, 1.25, FRAMES["bash"] / FPS],
        "hammer": [0.0, 1.15, HAMMER_HIT, 1.80, FRAMES["hammer"] / FPS],
        "sweep": [0.0, 0.85, SWEEP_HIT, 1.60, FRAMES["sweep"] / FPS],
        "stomp": [0.0, 0.50, STOMP_HIT, 0.95, FRAMES["stomp"] / FPS],
        "smash2": [0.0, 0.95, SMASH2_HIT, 1.55, FRAMES["smash2"] / FPS],
        "sweep2": [0.0, 0.75, SWEEP2_HIT, 1.50, FRAMES["sweep2"] / FPS],
        "kneel_hit": KNEEL_HIT, "rearm_grip": REARM_GRIP, "hammer_hit": HAMMER_HIT, "smash2_hit": SMASH2_HIT}
# the bar's points (rest, design; set by the build): the ground checks
BAR_V = None
LEFT_ON_BAR_M = 1.6                # real metres up the bar from the right fist to the left (two-handed)
UP = np.array([0.0, 0.0, 1.0])


def _bs():
    import bastion as bs
    return bs


def unit(v):
    v = np.asarray(v, np.float64)
    return v / max(float(np.linalg.norm(v)), 1e-12)


def yawed(deg):
    """His front (-Y) turned ``deg`` toward his left (+X)."""
    a = math.radians(deg)
    return np.array([math.sin(a), -math.cos(a), 0.0])


# ----------------------------------------------------------------------------------------------- the hands

def shield_hold(holder, pose, at, out, lean=0.0, pole=(1.0, 0.45, -0.25)):
    """The left fist on the shield's grip-bar at ``at`` with the shield's face toward ``out`` (its top tipped ``lean``
    degrees toward ``out``): the grip's line across the face, the palm toward the shield's back."""
    out = unit(out)
    up = unit(UP - out * float(UP @ out))
    if lean:
        a = math.radians(lean)
        up, out = unit(up * math.cos(a) + out * math.sin(a)), unit(out * math.cos(a) - up * math.sin(a))
    across = unit(np.cross(up, out))
    holder.hold(pose, "l", np.asarray(at, np.float64), across, pole=pole, palm=-out)
    return pose.solve()


def shield_at(pose, holder, fwd=0.30, out=0.10, low=0.80, side=0.0):
    """The idle's grip point (before his left hip, the arm hanging a little forward): from the left shoulder down
    ``low`` of the arm's reach, ``fwd`` forward and ``out`` out (design m)."""
    sh = pose.P["upperarm_l"]
    L = holder.l1["l"] + holder.l2["l"]
    return np.array([sh[0] + out + side, sh[1] - fwd, sh[2] - low * L])


def bar_tip(holder, pose):
    """The bar's tip and lowest point (design) in ``pose``."""
    h0 = holder.rest.head["hand_r"]
    P = (BAR_V - h0) @ pose.D["hand_r"].T + pose.P["hand_r"]
    return P[np.argmax(P @ (pose.D["hand_r"] @ holder.grip["r"][1]))], float(P[:, 2].min())


def bar_rest(holder, pose, steep=(-0.10, -0.20, -0.97), flat=(-0.20, -0.85, -0.48), clear_m=0.25):
    """The bar hand turned (between ``steep`` and ``flat``) so the bar's lowest point lies ``clear_m`` (real m) over
    the ground: its tip near the ground before his right foot."""
    bs = _bs()
    steep, flat = np.asarray(steep), np.asarray(flat)
    if BAR_V is None:
        holder.orient_hand(pose, "r", unit(steep * 0.6 + flat * 0.4))
        return pose.solve()
    a, b = 0.0, 1.0
    for _ in range(14):
        m_ = 0.5 * (a + b)
        holder.orient_hand(pose, "r", unit(steep * (1.0 - m_) + flat * m_))
        pose.solve()
        if bar_tip(holder, pose)[1] * bs.F < clear_m:
            a = m_
        else:
            b = m_
    holder.orient_hand(pose, "r", unit(steep * (1.0 - b) + flat * b))
    return pose.solve()


def ground_strike(pose, holder, side, arm_dir, reach, heading):
    """(grip, axis) of a blow that ends on the ground: the fist ``0.95`` of the arm's reach from the shoulder along
    ``arm_dir``, the bar from it down to the ground along ``heading`` (x, y: his left, his front) - its tip ``reach``
    (design m) from the fist touches the ground."""
    bs = _bs()
    sh = pose.P["upperarm_" + side]
    L = holder.l1[side] + holder.l2[side]
    grip = sh + unit(arm_dir) * (0.95 * L)
    drop = max(0.05, float(grip[2]) - 0.15 / bs.F)
    flat = math.sqrt(max(0.04, reach * reach - drop * drop)) if reach > drop else 0.2
    h = unit(np.array([heading[0], heading[1], 0.0]))
    return grip, unit(h * flat - UP * drop)


def bar_hold(holder, pose, at, axis, pole=(-0.8, 0.3, -0.3)):
    """The right fist at ``at`` with the bar along ``axis`` (toward its tip)."""
    holder.hold(pose, "r", np.asarray(at, np.float64), unit(axis), pole=pole)
    return pose.solve()


def left_on_bar(holder, pose, w=1.0, pole=(0.8, 0.2, -0.5)):
    """The left fist on the bar LEFT_ON_BAR_M up from the right, weighted in by ``w`` (its own pose at 0)."""
    bs = _bs()
    g, a = holder.grip_posed(pose.solve(), "r")
    gl = g + a * (LEFT_ON_BAR_M / bs.F)
    if w < 0.999:
        here, _ = holder.grip_posed(pose, "l")
        gl = here * (1.0 - w) + gl * w
    holder.hold(pose, "l", gl, a, pole=pole)
    return pose.solve()


def free_left(pose, swing=-4.0, elbow=20.0, out=14.0):
    import clips
    clips.set_arm(pose, "l", swing, elbow, out_deg=out)
    return pose.solve()


def keyed2(holder, rest, keys, frames, both=None):
    """sm.keyed with the left fist solved back onto the bar each frame where ``both(t)`` > 0 (the two-handed clips)."""
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
        if both is not None:
            w = both(t)
            if w > 1e-3:
                left_on_bar(holder, pose, w)
        out.append(pose.solve())
    return out


# ----------------------------------------------------------------------------------------------- stances

IDLE_YAW = 30.0                    # the shield's face turned this far to his left in the stance (bastion.SHIELD)


def idle_pose(holder, rest, f, frames):
    """The guard: the knees a little bent, the weight even, the shield carried low on the hanging left arm before his
    left side (its foot a couple of metres off the ground, its face turned to his front-left), the bar hanging at his
    right with its tip by his right foot; a slow breath."""
    import brute as br
    import clips
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    pose = sm.body(rest, pelvis=(3.0, 0.0, 4.0), spine=(1.5 + 0.8 * b, 0.0, 2.0), neck=(3.0, -2.0), head=(2.0, 0.0, -3.0),
                   drop=0.075 + 0.004 * b, clav=(-3.0, 0.0),
                   feet={"l": ((0.04, -0.12, 0.0), 12.0, 0.0, 0.0), "r": ((-0.04, 0.08, 0.0), -12.0, 0.0, 0.0)})
    shield_hold(holder, pose, shield_at(pose, holder, fwd=0.16, out=0.18, low=0.96) + np.array([0.0, 0.0, 0.006 * b]),
                yawed(IDLE_YAW))
    clips.set_arm(pose, "r", -5.0 - 1.5 * b, 16.0, out_deg=br.ARM_OUT_DEG + 2.0)
    pose.solve()
    return bar_rest(holder, pose)


def idle0(holder, rest):
    return idle_pose(holder, rest, 0, 60)


def dormant_pose(holder, rest, f, frames):
    """Bound into his wall: straight, the weight even, the shield squared before him, the bar planted upright at his
    right (its tip on the ground), the head bowed, a slow breath."""
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    k = sm.body(rest, pelvis=(1.0, 0.0, 0.0), spine=(2.0 + 0.8 * b, 0.0, 0.0), neck=(14.0, 0.0),
                head=(16.0 + 1.0 * b, 0.0, 0.0), drop=0.03 + 0.004 * b,
                feet={"l": ((0.03, -0.02, 0.0), 6.0, 0.0, 0.0), "r": ((-0.03, 0.02, 0.0), -6.0, 0.0, 0.0)})
    shield_hold(holder, k, shield_at(k, holder, fwd=0.30, out=0.04, low=0.98), yawed(6.0))
    sh = k.P["upperarm_r"]
    L = holder.l1["r"] + holder.l2["r"]
    bar_hold(holder, k, np.array([sh[0] - 0.10, sh[1] - 0.26, sh[2] - 0.66 * L]), (-0.02, -0.06, -1.0),
             pole=(-0.9, 0.3, -0.2))
    return k


def gait_pose(holder, gait, phi, run=False):
    import brute as br
    import clips
    pose = br.brute_gait_pose(gait, phi)
    pose.set_rel("neck_01", clips.rot(clips.X, 4.0))
    pose.solve()
    sway = 0.012 * math.sin(phi) * (1.6 if run else 1.0)
    shield_hold(holder, pose, shield_at(pose, holder, fwd=0.28 if run else 0.20, out=0.16, low=0.90)
                + np.array([0.0, 0.0, sway]), yawed(22.0 if run else IDLE_YAW), lean=6.0 if run else 0.0)
    swing = gait.g["arm_swing_deg"] * (1.4 if run else 1.0) * math.sin(phi)
    clips.set_arm(pose, "r", -6.0 - swing, 24.0 if run else 18.0, out_deg=br.ARM_OUT_DEG + 2.0)
    pose.solve()
    holder.orient_hand(pose, "r", unit((-0.16, -0.42, -0.89) if run else (-0.15, -0.52, -0.84)))
    return pose.solve()


def ready2(holder, rest, f=0, frames=60, lean=1.0):
    """The two-handed stance: the bar held across him, the tip up and forward to his left, the right fist at his right
    hip, the left above it."""
    b = math.sin(2.0 * math.pi * f / max(frames, 1))
    k = sm.body(rest, pelvis=(4.0 * lean, 0.0, -8.0), spine=(4.0 * lean + 1.0 * b, 0.0, -6.0), neck=(2.0, 6.0),
                head=(2.0, 0.0, 8.0), drop=0.08 + 0.004 * b,
                feet={"l": ((0.06, -0.14, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.10, 0.0), -16.0, 0.0, 0.0)})
    pel = k.P["pelvis"]
    bar_hold(holder, k, pel + np.array([-0.32, -0.36, 0.20 + 0.004 * b]), (0.45, -0.55, 0.70))
    return left_on_bar(holder, k)


def gait2_pose(holder, gait, phi, run=False):
    """The gait with the bar two-handed across him (the arms carried, the bar bobbing with the step)."""
    import brute as br
    pose = br.brute_gait_pose(gait, phi)
    pose.solve()
    pel = pose.P["pelvis"]
    bob = 0.01 * math.sin(2.0 * phi)
    bar_hold(holder, pose, pel + np.array([-0.30, -0.38 if run else -0.34, 0.22 + bob]),
             (0.42, -0.62 if run else -0.55, 0.66 if run else 0.70))
    return left_on_bar(holder, pose)


# ----------------------------------------------------------------------------------------------- strikes

def _roar_key(holder, rest, lean=1.0):
    k = sm.body(rest, pelvis=(-4.0 * lean, 0.0, 0.0), spine=(-9.0 * lean, 0.0, 0.0), neck=(-10.0 * lean, 0.0),
                head=(-20.0 * lean, 0.0, 0.0), drop=0.10, clav=(-10.0, -14.0),
                feet={"l": ((0.08, -0.12, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.10, 0.0), -10.0, 0.0, 0.0)})
    sh = k.P["upperarm_l"]
    shield_hold(holder, k, sh + np.array([0.30, -0.42, -0.10]), yawed(30.0), lean=-12.0)
    hd = k.P["head"]
    bar_hold(holder, k, hd + np.array([-0.62, -0.10, 0.10]), (-0.15, 0.10, 1.0), pole=(-0.6, 0.6, -0.4))
    return k


def roar(holder, rest):
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(8.0, 0.0, 0.0), spine=(9.0, 0.0, 0.0), neck=(8.0, 0.0), head=(10.0, 0.0, 0.0),
                 drop=0.16, feet={"l": ((0.08, -0.12, 0.0), 10.0, 0.0, 0.0), "r": ((-0.08, 0.10, 0.0), -10.0, 0.0, 0.0)})
    shield_hold(holder, k1, shield_at(k1, holder, fwd=0.26, out=0.14, low=0.92), yawed(24.0))
    sh = k1.P["upperarm_r"]
    bar_hold(holder, k1, sh + np.array([-0.30, -0.40, -0.70]), (-0.3, -0.5, 0.8))
    k2 = _roar_key(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.45, k1, "smooth"), (0.95, k2, "out"), (1.55, k2, "linear"),
            (FRAMES["roar"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["roar"])


def bash(holder, rest):
    k0 = idle0(holder, rest)
    feet_w = {"l": ((0.06, -0.06, 0.0), 8.0, 0.0, 0.0), "r": ((-0.08, 0.22, 0.0), -18.0, 0.0, 0.0)}
    # the draw: the weight back on the right foot, the shield drawn in against his left side, the trunk turned right
    kw = sm.body(rest, pelvis=(-2.0, 0.0, -14.0), spine=(-2.0, 0.0, -10.0), neck=(0.0, 6.0), head=(4.0, 0.0, 10.0),
                 back=0.06, drop=0.16, feet=feet_w, clav=(10.0, 0.0))
    shield_hold(holder, kw, shield_at(kw, holder, fwd=0.10, out=0.10, low=0.86), yawed(34.0))
    sh = kw.P["upperarm_r"]
    bar_hold(holder, kw, sh + np.array([-0.20, 0.10, -0.86]), (-0.20, -0.10, -0.97))
    # the lunge: the left foot driven forward, the trunk thrown into the shield, the shield out before him
    feet_h = {"l": ((0.06, -0.62, 0.0), 6.0, 0.0, 0.0), "r": ((-0.08, 0.30, 0.0), -16.0, 0.0, 22.0)}
    kh = sm.body(rest, pelvis=(14.0, 0.0, 8.0), spine=(10.0, 0.0, 10.0), neck=(-6.0, -4.0), head=(-8.0, 0.0, -6.0),
                 back=-0.30, drop=0.22, feet=feet_h, clav=(-6.0, 0.0))
    sh_l = kh.P["upperarm_l"]
    L = holder.l1["l"] + holder.l2["l"]
    shield_hold(holder, kh, sh_l + np.array([-0.10, -0.78 * L, -0.42 * L]), yawed(4.0), lean=4.0)
    sh = kh.P["upperarm_r"]
    bar_hold(holder, kh, sh + np.array([-0.10, 0.26, -0.84]), (-0.15, 0.30, -0.94))
    kf = sm.body(rest, pelvis=(12.0, 0.0, 6.0), spine=(8.0, 0.0, 8.0), neck=(-4.0, -4.0), head=(-6.0, 0.0, -6.0),
                 back=-0.26, drop=0.20, feet=feet_h)
    sh_l = kf.P["upperarm_l"]
    shield_hold(holder, kf, sh_l + np.array([-0.08, -0.72 * L, -0.46 * L]), yawed(6.0), lean=2.0)
    sh = kf.P["upperarm_r"]
    bar_hold(holder, kf, sh + np.array([-0.10, 0.20, -0.86]), (-0.15, 0.20, -0.96))
    keys = [(0.0, k0, "smooth"), (0.70, kw, "out"), (BASH_HIT, kh, "in"), (1.25, kf, "out"),
            (FRAMES["bash"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["bash"])


def hammer(holder, rest):
    """The bar over his right shoulder and down over the shield's rim: its tip on the ground ahead and to his right."""
    bs = _bs()
    k0 = idle0(holder, rest)
    feet = {"l": ((0.08, -0.30, 0.0), 8.0, 0.0, 0.0), "r": ((-0.12, 0.20, 0.0), -16.0, 0.0, 0.0)}
    # up: the bar raised high over his right shoulder, pointing back; the shield kept up before him
    ku = sm.body(rest, pelvis=(-4.0, 0.0, -10.0), spine=(-8.0, 0.0, -14.0), neck=(-2.0, 6.0), head=(-6.0, 0.0, 10.0),
                 drop=0.12, feet=feet, clav=(0.0, -18.0))
    shield_hold(holder, ku, shield_at(ku, holder, fwd=0.40, low=0.66), yawed(18.0))
    hd = ku.P["head"]
    bar_hold(holder, ku, hd + np.array([-0.40, 0.04, 0.34]), (-0.10, 0.65, 0.75), pole=(-0.7, 0.5, -0.4))
    # the blow: bent hard over the front knee, the arm thrown down and out ahead, the bar come down over the shield's
    # rim so its tip strikes the ground ahead and to his right
    reach = (bs.BAR["length"] * (1.0 - bs.BAR["grip_share"]) - 0.6) / bs.F
    L = holder.l1["r"] + holder.l2["r"]
    kh = sm.body(rest, pelvis=(26.0, 0.0, 12.0), spine=(12.0, 0.0, 10.0), neck=(-12.0, -4.0), head=(-14.0, 0.0, -6.0),
                 drop=0.36, feet=feet, clav=(0.0, 10.0))
    shield_hold(holder, kh, shield_at(kh, holder, fwd=0.30, out=0.14, low=0.94), yawed(18.0), lean=-6.0)
    bar_hold(holder, kh, *ground_strike(kh, holder, "r", (-0.16, -0.60, -0.78), reach, (-0.30, -1.0)))
    # past: the weight carried on down past the blow, the bar on the ground; then up
    kp = sm.body(rest, pelvis=(28.0, 0.0, 14.0), spine=(14.0, 0.0, 12.0), neck=(-14.0, -4.0), head=(-16.0, 0.0, -8.0),
                 drop=0.40, feet=feet, clav=(0.0, 10.0))
    shield_hold(holder, kp, shield_at(kp, holder, fwd=0.26, out=0.16, low=0.96), yawed(14.0), lean=-10.0)
    bar_hold(holder, kp, *ground_strike(kp, holder, "r", (-0.16, -0.56, -0.81), reach, (-0.30, -1.0)))
    keys = [(0.0, k0, "smooth"), (1.15, ku, "out"), (HAMMER_HIT, kh, "in"), (1.80, kp, "out"), (2.25, kp, "linear"),
            (FRAMES["hammer"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["hammer"])


def sweep(holder, rest):
    k0 = idle0(holder, rest)
    feet = {"l": ((0.10, -0.20, 0.0), 6.0, 0.0, 0.0), "r": ((-0.14, 0.18, 0.0), -26.0, 0.0, 0.0)}
    # the draw: wound to his right, the bar back low behind his right hip, sunk into the knees
    kw = sm.body(rest, pelvis=(4.0, 0.0, -30.0), spine=(2.0, 0.0, -24.0), neck=(0.0, 12.0), head=(2.0, 0.0, 18.0),
                 drop=0.22, feet=feet, clav=(6.0, 10.0))
    shield_hold(holder, kw, shield_at(kw, holder, fwd=0.24, out=0.10, low=0.92), yawed(2.0))
    pel = kw.P["pelvis"]
    bar_hold(holder, kw, pel + np.array([-0.58, 0.14, 0.10]), (-0.55, 0.80, -0.20))
    # the blow: swung round through his front at hip height, the bar out to his front-left
    kh = sm.body(rest, pelvis=(6.0, 0.0, 16.0), spine=(4.0, 0.0, 18.0), neck=(-2.0, -8.0), head=(-4.0, 0.0, -10.0),
                 drop=0.22, feet=feet)
    shield_hold(holder, kh, shield_at(kh, holder, fwd=0.16, out=0.20, low=0.92), yawed(50.0))
    sh = kh.P["upperarm_r"]
    L = holder.l1["r"] + holder.l2["r"]
    bar_hold(holder, kh, sh + np.array([0.18, -0.80 * L, -0.40 * L]), (0.55, -0.80, -0.12))
    # on round to his left, carried by the bar's weight, checked
    kf = sm.body(rest, pelvis=(6.0, 0.0, 34.0), spine=(4.0, 0.0, 28.0), neck=(-2.0, -10.0), head=(-4.0, 0.0, -12.0),
                 drop=0.20, feet=feet)
    shield_hold(holder, kf, shield_at(kf, holder, fwd=0.10, out=0.26, low=0.92), yawed(68.0))
    sh = kf.P["upperarm_r"]
    bar_hold(holder, kf, sh + np.array([0.50, -0.58 * L, -0.46 * L]), (0.90, -0.30, -0.25))
    keys = [(0.0, k0, "smooth"), (0.85, kw, "out"), (SWEEP_HIT, kh, "in"), (1.60, kf, "out"),
            (FRAMES["sweep"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["sweep"])


def _charge_key(holder, rest, depth=1.0):
    feet = {"l": ((0.06, -0.34 * depth, 0.0), 6.0, 0.0, 0.0), "r": ((-0.08, 0.34 * depth, 0.0), -12.0, 0.0, 18.0)}
    k = sm.body(rest, pelvis=(16.0 * depth, 0.0, 12.0 * depth), spine=(12.0 * depth, 0.0, 10.0 * depth),
                neck=(-10.0 * depth, -4.0), head=(-10.0 * depth, 0.0, -8.0), back=-0.10 * depth, drop=0.10 + 0.20 * depth,
                feet=feet, clav=(-8.0, 0.0))
    sh_l = k.P["upperarm_l"]
    L = holder.l1["l"] + holder.l2["l"]
    shield_hold(holder, k, sh_l + np.array([-0.30, -0.55 * L, -0.48 * L]), yawed(-6.0), lean=8.0 * depth)
    sh = k.P["upperarm_r"]
    bar_hold(holder, k, sh + np.array([-0.16, 0.30, -0.80]), (-0.10, 0.55, -0.83))
    return k


def charge(holder, rest):
    k0 = idle0(holder, rest)
    kc = _charge_key(holder, rest, 1.0)
    keys = [(0.0, k0, "smooth"), (0.55, _charge_key(holder, rest, 0.45), "smooth"), (1.05, kc, "out"),
            (FRAMES["charge"] / FPS, kc, "linear")]
    return sm.keyed(holder, rest, keys, FRAMES["charge"])


def charge_run_pose(holder, gait, phi):
    import brute as br
    import clips
    pose = br.brute_gait_pose(gait, phi)
    pose.set_rel("spine_02", clips.rot(clips.X, 8.0))
    pose.set_rel("neck_01", clips.rot(clips.X, -6.0))
    pose.solve()
    sh_l = pose.P["upperarm_l"]
    L = holder.l1["l"] + holder.l2["l"]
    shield_hold(holder, pose, sh_l + np.array([-0.30, -0.55 * L, -0.48 * L + 0.01 * math.sin(2.0 * phi)]),
                yawed(-6.0), lean=8.0)
    sh = pose.P["upperarm_r"]
    bar_hold(holder, pose, sh + np.array([-0.16, 0.30 + 0.06 * math.sin(phi), -0.80]), (-0.10, 0.55, -0.83))
    return pose


def stomp(holder, rest):
    k0 = idle0(holder, rest)
    ku = sm.body(rest, pelvis=(-4.0, 0.0, 0.0), spine=(-6.0, 0.0, 0.0), neck=(6.0, 0.0), head=(12.0, 0.0, 0.0),
                 drop=0.10, side=0.04,
                 feet={"l": ((0.04, 0.02, 0.0), 6.0, 0.0, 0.0), "r": ((-0.04, -0.20, 0.36), -6.0, -18.0, 0.0)})
    shield_hold(holder, ku, shield_at(ku, holder, fwd=0.22, out=0.16, low=0.90), yawed(26.0))
    sh = ku.P["upperarm_r"]
    bar_hold(holder, ku, sh + np.array([-0.40, -0.10, -0.62]), (-0.30, -0.25, -0.92))
    kh = sm.body(rest, pelvis=(12.0, 0.0, 0.0), spine=(10.0, 0.0, 0.0), neck=(-6.0, 0.0), head=(-8.0, 0.0, 0.0),
                 drop=0.30, side=-0.02,
                 feet={"l": ((0.06, 0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, -0.30, 0.0), -10.0, 0.0, 0.0)})
    shield_hold(holder, kh, shield_at(kh, holder, fwd=0.24, out=0.16, low=0.96), yawed(26.0), lean=-4.0)
    sh = kh.P["upperarm_r"]
    bar_hold(holder, kh, sh + np.array([-0.42, -0.06, -0.66]), (-0.30, -0.25, -0.92))
    keys = [(0.0, k0, "smooth"), (0.50, ku, "out"), (STOMP_HIT, kh, "in"), (0.95, kh, "linear"),
            (FRAMES["stomp"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["stomp"])


def reel(holder, rest):
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(-8.0, 0.0, 4.0), spine=(-10.0, 2.0, 4.0), neck=(-10.0, 6.0), head=(-18.0, 4.0, 8.0),
                 back=0.10, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.36, 0.0), -16.0, 0.0, 0.0)},
                 drop=0.12)
    shield_hold(holder, k1, shield_at(k1, holder, fwd=0.12, out=0.24, low=0.94), yawed(40.0), lean=-14.0)
    sh = k1.P["upperarm_r"]
    bar_hold(holder, k1, sh + np.array([-0.46, 0.10, -0.64]), (-0.40, 0.10, -0.91))
    k2 = sm.body(rest, pelvis=(14.0, 0.0, -6.0), spine=(10.0, -3.0, -4.0), neck=(14.0, -6.0), head=(16.0, 0.0, -10.0),
                 back=0.12, feet={"l": ((0.10, -0.16, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.32, 0.0), -18.0, 0.0, 0.0)},
                 drop=0.30)
    shield_hold(holder, k2, shield_at(k2, holder, fwd=0.22, out=0.14, low=0.96), yawed(26.0), lean=-6.0)
    sh = k2.P["upperarm_r"]
    bar_hold(holder, k2, sh + np.array([-0.40, -0.10, -0.62]), (-0.25, -0.35, -0.90))
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.85, k2, "smooth"), (FRAMES["reel"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["reel"])


def guardbreak(holder, rest):
    """His guard broken: the shield struck out wide to his left (the arm flung after it, the face turned out), the
    trunk twisted to his right, a stumble back on the right foot; then the shield dragged back before him."""
    k0 = idle0(holder, rest)
    feet = {"l": ((0.14, 0.04, 0.0), 18.0, 0.0, 0.0), "r": ((-0.10, 0.40, 0.0), -24.0, 0.0, 0.0)}
    k1 = sm.body(rest, pelvis=(-6.0, 0.0, -18.0), spine=(-8.0, 4.0, -16.0), neck=(-6.0, 10.0), head=(-12.0, 6.0, 14.0),
                 back=0.14, drop=0.16, feet=feet, clav=(-12.0, 4.0))
    sh_l = k1.P["upperarm_l"]
    L = holder.l1["l"] + holder.l2["l"]
    shield_hold(holder, k1, sh_l + np.array([0.72 * L, -0.20 * L, -0.42 * L]), yawed(95.0), lean=-18.0,
                pole=(0.3, 0.6, -0.7))
    sh = k1.P["upperarm_r"]
    bar_hold(holder, k1, sh + np.array([-0.50, 0.20, -0.60]), (-0.45, 0.25, -0.86))
    k2 = sm.body(rest, pelvis=(10.0, 0.0, -10.0), spine=(8.0, 2.0, -8.0), neck=(6.0, 6.0), head=(8.0, 4.0, 8.0),
                 back=0.18, drop=0.28, feet=feet)
    sh_l = k2.P["upperarm_l"]
    shield_hold(holder, k2, sh_l + np.array([0.52 * L, -0.30 * L, -0.62 * L]), yawed(70.0), lean=-10.0,
                pole=(0.5, 0.6, -0.6))
    sh = k2.P["upperarm_r"]
    bar_hold(holder, k2, sh + np.array([-0.44, 0.04, -0.66]), (-0.35, -0.10, -0.93))
    keys = [(0.0, k0, "smooth"), (0.25, k1, "out"), (1.05, k2, "smooth"), (FRAMES["guardbreak"] / FPS, k0, "smooth")]
    return sm.keyed(holder, rest, keys, FRAMES["guardbreak"])


def rearm(holder, rest):
    """The shield gone: the empty left hand falls, he looks at it, grips the bar in both hands and roars, and stands
    ready, the bar across him (idle2)."""
    k0 = idle0(holder, rest)
    k1 = sm.body(rest, pelvis=(6.0, 0.0, 6.0), spine=(8.0, 0.0, 6.0), neck=(16.0, -10.0), head=(18.0, 0.0, -14.0),
                 drop=0.14, feet={"l": ((0.06, -0.10, 0.0), 8.0, 0.0, 0.0), "r": ((-0.08, 0.12, 0.0), -12.0, 0.0, 0.0)})
    free_left(k1, swing=-30.0, elbow=60.0, out=18.0)
    sh = k1.P["upperarm_r"]
    bar_hold(holder, k1, sh + np.array([-0.30, -0.30, -0.70]), (-0.20, -0.40, -0.90))
    k2 = _roar_key(holder, rest, 0.9)
    hd = k2.P["head"]
    bar_hold(holder, k2, hd + np.array([-0.30, -0.30, 0.20]), (0.55, -0.20, 0.80), pole=(-0.6, 0.6, -0.4))
    left_on_bar(holder, k2)
    k3 = ready2(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.60, k1, "smooth"), (REARM_GRIP, k1, "linear"), (1.70, k2, "out"),
            (2.05, k2, "linear"), (FRAMES["rearm"] / FPS, k3, "smooth")]
    return keyed2(holder, rest, keys, FRAMES["rearm"], both=lambda t: 0.0 if t < REARM_GRIP + 0.15 else
                  min(1.0, (t - REARM_GRIP - 0.15) / 0.30))


def smash2(holder, rest):
    """The bar raised two-handed over and behind his head, brought down ahead: its tip strikes the ground before
    him (SMASH2_HIT), the weight carried on down past the blow, up again to the two-handed stance."""
    bs = _bs()
    k0 = ready2(holder, rest)
    feet = {"l": ((0.08, -0.30, 0.0), 8.0, 0.0, 0.0), "r": ((-0.10, 0.22, 0.0), -14.0, 0.0, 0.0)}
    ku = sm.body(rest, pelvis=(-6.0, 0.0, 0.0), spine=(-12.0, 0.0, 0.0), neck=(-4.0, 0.0), head=(-10.0, 0.0, 0.0),
                 drop=0.14, feet=feet, clav=(-14.0, -14.0))
    hd = ku.P["head"]
    bar_hold(holder, ku, hd + np.array([-0.08, 0.10, 0.38]), (0.05, 0.70, 0.70), pole=(-0.6, 0.6, -0.4))
    left_on_bar(holder, ku, pole=(0.6, 0.6, -0.4))
    reach = (bs.BAR["length"] * (1.0 - bs.BAR["grip_share"]) - 0.6) / bs.F
    kh = sm.body(rest, pelvis=(28.0, 0.0, 0.0), spine=(14.0, 0.0, 0.0), neck=(-14.0, 0.0), head=(-16.0, 0.0, 0.0),
                 drop=0.40, feet=feet, clav=(8.0, 8.0))
    bar_hold(holder, kh, *ground_strike(kh, holder, "r", (0.30, -0.58, -0.76), reach, (0.0, -1.0)))
    left_on_bar(holder, kh)
    kp = sm.body(rest, pelvis=(30.0, 0.0, 0.0), spine=(16.0, 0.0, 0.0), neck=(-16.0, 0.0), head=(-18.0, 0.0, 0.0),
                 drop=0.44, feet=feet, clav=(8.0, 8.0))
    bar_hold(holder, kp, *ground_strike(kp, holder, "r", (0.30, -0.54, -0.79), reach, (0.0, -1.0)))
    left_on_bar(holder, kp)
    keys = [(0.0, k0, "smooth"), (0.95, ku, "out"), (SMASH2_HIT, kh, "in"), (1.55, kp, "out"),
            (FRAMES["smash2"] / FPS, k0, "smooth")]
    return keyed2(holder, rest, keys, FRAMES["smash2"], both=lambda t: 1.0)


def sweep2(holder, rest):
    k0 = ready2(holder, rest)
    feet = {"l": ((0.10, -0.22, 0.0), 6.0, 0.0, 0.0), "r": ((-0.14, 0.18, 0.0), -26.0, 0.0, 0.0)}
    kw = sm.body(rest, pelvis=(4.0, 0.0, -34.0), spine=(2.0, 0.0, -26.0), neck=(0.0, 12.0), head=(2.0, 0.0, 18.0),
                 drop=0.24, feet=feet, clav=(10.0, 10.0))
    pel = kw.P["pelvis"]
    bar_hold(holder, kw, pel + np.array([-0.50, 0.12, 0.16]), (-0.60, 0.78, -0.10))
    left_on_bar(holder, kw)
    kh = sm.body(rest, pelvis=(6.0, 0.0, 18.0), spine=(4.0, 0.0, 20.0), neck=(-2.0, -8.0), head=(-4.0, 0.0, -10.0),
                 drop=0.24, feet=feet)
    pel = kh.P["pelvis"]
    bar_hold(holder, kh, pel + np.array([0.10, -0.52, 0.16]), (0.62, -0.78, -0.05))
    left_on_bar(holder, kh)
    kf = sm.body(rest, pelvis=(6.0, 0.0, 36.0), spine=(4.0, 0.0, 30.0), neck=(-2.0, -10.0), head=(-4.0, 0.0, -12.0),
                 drop=0.22, feet=feet)
    pel = kf.P["pelvis"]
    bar_hold(holder, kf, pel + np.array([0.38, -0.36, 0.16]), (0.95, -0.25, -0.10))
    left_on_bar(holder, kf)
    keys = [(0.0, k0, "smooth"), (0.75, kw, "out"), (SWEEP2_HIT, kh, "in"), (1.50, kf, "out"),
            (FRAMES["sweep2"] / FPS, k0, "smooth")]
    return keyed2(holder, rest, keys, FRAMES["sweep2"], both=lambda t: 1.0)


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0):
    """Down on his right knee (Stoneback's kneel's legs) behind the shield planted on the ground before his left side;
    the bar's fist on the ground at his right."""
    bs = _bs()
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
    # the shield planted: its foot on the ground before his left side (its grip half its height up)
    sh_l = k.P["upperarm_l"]
    half = (bs.SHIELD["height"] * 0.5) / bs.F
    stand = half * depth + (shield_at(k, holder)[2]) * (1.0 - depth)
    shield_hold(holder, k, np.array([sh_l[0] + 0.12, sh_l[1] - 0.70, stand + 0.03]), yawed(10.0))
    sh = k.P["upperarm_r"]
    g = np.array([sh[0] - 0.22, sh[1] - 0.18, 0.06 + 0.4 * (1.0 - depth)])
    holder.hold(k, "r", g, np.array([0.0, -0.3, -1.0]), pole=(-0.8, 0.3, 0.0))
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
                 back=0.10, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.30, 0.0), -14.0, 0.0, 0.0)},
                 drop=0.12)
    shield_hold(holder, k1, shield_at(k1, holder, fwd=0.08, out=0.28, low=0.96), yawed(46.0), lean=-16.0)
    sh = k1.P["upperarm_r"]
    bar_hold(holder, k1, sh + np.array([-0.50, 0.20, -0.60]), (-0.45, 0.25, -0.86))
    kn = sm.body(rest, pelvis=(10.0, 0.0, 0.0), spine=(14.0, 0.0, 0.0), neck=(12.0, 0.0), head=(16.0, 0.0, -6.0),
                 feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)}, drop=1.0)
    clips.set_arm(kn, "l", -10.0, 30.0, out_deg=30.0)
    clips.set_arm(kn, "r", -8.0, 18.0, out_deg=20.0)
    kn.solve()
    holder.orient_hand(kn, "r", unit((-0.2, -0.3, -0.93)))
    kn.solve()
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
    keys = [(0.0, k0, "smooth"), (0.40, k1, "out"), (1.30, kn, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return sm.keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- all of them

def make_poses(person, pieces, holder):
    """Every clip's solved frames: {name: [pose, ...]}, the gaits, and the checks (the crown's height in the stances
    and the gaits; the shield's foot and the bar's lowest point over the ground in the idle; the hammer's and the
    smash's tip at their blows; the kneel's bones; each plate's place in the idle)."""
    import clips
    bs = _bs()
    rest = person.rest
    gaits = {"walk": clips.Gait(rest, "bastion_walk", 32), "run": clips.Gait(rest, "bastion_run", 32)}
    poses = {"idle": [idle_pose(holder, rest, f, 60) for f in range(61)],
             "walk": [gait_pose(holder, gaits["walk"], 2.0 * math.pi * f / 32) for f in range(33)],
             "run": [gait_pose(holder, gaits["run"], 2.0 * math.pi * f / 32, run=True) for f in range(33)],
             "idle2": [ready2(holder, rest, f, 60) for f in range(61)],
             "walk2": [gait2_pose(holder, gaits["walk"], 2.0 * math.pi * f / 32) for f in range(33)],
             "run2": [gait2_pose(holder, gaits["run"], 2.0 * math.pi * f / 32, run=True) for f in range(33)],
             "dormant": [dormant_pose(holder, rest, f, FRAMES["dormant"]) for f in range(FRAMES["dormant"] + 1)],
             "charge_run": [charge_run_pose(holder, gaits["run"], 2.0 * math.pi * f / 32) for f in range(33)]}
    for name in FRAMES:
        if name in poses:
            continue
        poses[name] = globals()[name](holder, rest)
    V = person.body_V()
    top = np.array([rest.head["head"][0], rest.head["head"][1], float(V[:, 2].max())])
    local = top - rest.head["head"]

    def crown(p):
        return float((p.P["head"] + p.D["head"] @ local)[2]) * bs.F
    checks = {"crown_m": {c: [br6(min(crown(p) for p in poses[c])), br6(max(crown(p) for p in poses[c]))]
                          for c in ("idle", "dormant", "walk", "run", "idle2", "walk2", "roar")}}
    sv = pieces["shield"].V
    h0 = rest.head["hand_l"]

    def shield_low(p):
        return float(((sv - h0) @ p.D["hand_l"].T + p.P["hand_l"])[:, 2].min()) * bs.F
    checks["shield_low_m"] = {c: br6(min(shield_low(p) for p in poses[c])) for c in ("idle", "walk", "run", "dormant",
                                                                                     "bash", "charge_run")}
    checks["shield_planted_m"] = br6(shield_low(poses["kneel"][-1]))
    checks["bar_low_m"] = {c: br6(min(bar_tip(holder, p)[1] for p in poses[c]) * bs.F)
                           for c in ("idle", "walk", "run", "dormant", "idle2")}

    def tip_at(clip, t):
        p = poses[clip][min(len(poses[clip]) - 1, int(round(t * FPS)))]
        tip, low = bar_tip(holder, p)
        a = sm_actor(tip) * bs.F
        return [br6(a[0]), br6(a[1]), br6(a[2])]
    checks["tip_at_blow_m"] = {"hammer": tip_at("hammer", HAMMER_HIT), "smash2": tip_at("smash2", SMASH2_HIT)}
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
    bs = _bs()
    rest = person.rest
    p = poses["idle"][0]
    out = {}
    for name in bs.PLATE_ORDER + bs.GEAR:
        piece = pieces[name]
        b = bs.PIECE_BONE[name]
        V = np.asarray(piece.V, np.float64)
        if name in ("helm", "back", "pauldron_l", "pauldron_r", "greave_l", "greave_r"):
            V = V[np.asarray(piece.rgba)[:, 3] > 0.5] if (np.asarray(piece.rgba)[:, 3] > 0.5).sum() > 8 else V
        if name == "mend":
            # (the mend's iron rides the skin: its place is its staples' and bands' by the posed skin)
            pass
        posed = p.P[b] + (V - rest.head[b]) @ p.D[b].T
        A = (sb.TO_ACTOR @ posed.T).T * bs.F
        lo, hi = A.min(axis=0), A.max(axis=0)
        out[name] = {"centre": [br6(x) for x in 0.5 * (lo + hi)], "size": [br6(x) for x in hi - lo],
                     "outer": [br6(x) for x in A[np.argmax(np.linalg.norm(A - A.mean(axis=0), axis=1))]]}
    return out


KNEEL_BONES = ("pelvis", "spine_01", "spine_02", "spine_03", "head", "upperarm_l", "upperarm_r", "lowerarm_l",
               "lowerarm_r", "hand_l", "hand_r", "thigh_l", "thigh_r", "calf_l", "calf_r")


def kneel_frames(person, poses):
    """Each KNEEL_BONES head and frame in the idle's first key and the kneel's last, in his actor's space and real
    metres (tools/builders/titans.gd moves each hurtbox and lock anchor with its bone)."""
    import stoneback as sb
    bs = _bs()
    out = {"bones": {}}
    for key, p in (("idle", poses["idle"][0]), ("kneel", poses["kneel"][-1])):
        for b in KNEEL_BONES:
            d = out["bones"].setdefault(b, {})
            R = sb.TO_ACTOR @ p.D[b] @ sb.TO_ACTOR.T
            d[key] = {"head": [br6(x) for x in sb.TO_ACTOR @ p.P[b] * bs.F], "basis": [br6(x) for x in R.ravel()]}
    out["pelvis_m"] = br6(float(poses["kneel"][-1].P["pelvis"][2]) * bs.F)
    return out
