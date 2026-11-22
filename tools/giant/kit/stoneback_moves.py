"""Stoneback's strikes and recoveries (A2): the clips that finish A1's three wind-ups and what his fight needs besides.

Each clip is a few key poses - solved as A1's are (``clips.Pose``, the legs by their feet, the arms that hold the
trunk or the boulder by ``Holder.hold``) - and the frames between them: every bone's rotation relative to its parent
slerped between the keys on an ease (``blend``), the pelvis's offset with it. Where both hands hold the trunk over a
segment the left hand is solved onto the trunk again on every frame (a hand a fixed length up the trunk from the right
fist), so the two-handed swings never let go between keys. A clip that starts from a wind-up's peak starts from that
very pose (A1's ``overhead_pose`` / ``throw_pose`` at their last key), and every strike ends on the idle's first key,
so the game cross-fades nothing but the first frame of a strike.

  smash       (54 frames) the overhead's peak -> a dip into the knees with the trunk cocked back (SMASH_DIP, A3), the
              trunk over the head and down two-handed, the root ball striking the ground 9 m ahead at SMASH_HIT
              (0.3 s), the weight carrying on lower past the blow (A3) and rebounding, held, the left hand letting
              go, upright again
  sweep       (66) from the stance the trunk drawn back low on his right (two-handed, the torso turned away, sunk into
              the knees), swung round through his front at knee height (SWEEP_HIT 1.2 s), round to his left and on
              past it as the trunk's weight carries him (A3), checked, recovered
  charge_run  (32, a loop) the run's legs under the charge's lowered shoulder, the trunk trailing
  reel        (72) a charge into stone, a plate torn off, a poise break: the head snapped back, a stumble, hunched and
              dazed, braced on his left knee, the club hand dragging, then upright
  rip         (30) from the stance he crouches, the left hand to the ground by his left foot, closes on a boulder
              (RIP_GRIP 0.75 s) and lifts it to the throw's first key
  release     (36) the throw's peak -> the boulder slung over the shoulder and let go at RELEASE_AT (0.25 s), the arm
              following through across the body, upright again
  death       (75) struck down: a stagger back, the knees go, he kneels and falls forward on his face, the trunk
              rolling from his hand
  kneel       (24, A4) a shin plate broken: the right leg gives way (KNEEL_BUCKLE), the knee strikes the ground
              (KNEEL_HIT 0.6 s) and he settles on it, the left hand braced on the raised left knee, the trunk planted
              at his side; its last frame is held while he is down
  rise        (36, A4) from the kneel back onto his feet, pushing on the left knee, to the idle's first key

Every number below is in A1's design metres (the stage-1 giant's), Z up, -Y his front, +X his left.
"""
from __future__ import annotations

import math

import numpy as np

FRAMES = {"smash": 54, "sweep": 66, "charge_run": 32, "reel": 72, "rip": 30, "release": 36, "death": 75,
          "kneel": 24, "rise": 36}
LOOPS = ("charge_run",)
FPS = 30.0
SMASH_HIT = 0.30
SMASH_DIP = 0.10                   # A3: the anticipation's low point (the knees sunk, the trunk cocked back)
SWEEP_HIT = 1.20
RIP_GRIP = 0.75
RELEASE_AT = 0.25
KNEEL_BUCKLE = 0.30                # A4: the broken leg gives way
KNEEL_HIT = 0.60                   # A4: the knee strikes the ground (the rig's dust and shake)
# the left fist on the trunk: this far (real metres) up the trunk from the right fist (A1's overhead)
LEFT_ON_TRUNK_M = 0.62


# ----------------------------------------------------------------------------------------------- quaternions

def _quat(M):
    """A unit quaternion (w, x, y, z) of a rotation matrix."""
    m = np.asarray(M, np.float64)
    t = m[0, 0] + m[1, 1] + m[2, 2]
    if t > 0.0:
        s = math.sqrt(t + 1.0) * 2.0
        q = np.array([0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s])
    elif m[0, 0] > m[1, 1] and m[0, 0] > m[2, 2]:
        s = math.sqrt(1.0 + m[0, 0] - m[1, 1] - m[2, 2]) * 2.0
        q = np.array([(m[2, 1] - m[1, 2]) / s, 0.25 * s, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s])
    elif m[1, 1] > m[2, 2]:
        s = math.sqrt(1.0 + m[1, 1] - m[0, 0] - m[2, 2]) * 2.0
        q = np.array([(m[0, 2] - m[2, 0]) / s, (m[0, 1] + m[1, 0]) / s, 0.25 * s, (m[1, 2] + m[2, 1]) / s])
    else:
        s = math.sqrt(1.0 + m[2, 2] - m[0, 0] - m[1, 1]) * 2.0
        q = np.array([(m[1, 0] - m[0, 1]) / s, (m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, 0.25 * s])
    return q / np.linalg.norm(q)


def _mat(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def _slerp(a, b, t):
    d = float(np.dot(a, b))
    if d < 0.0:
        b = -b
        d = -d
    if d > 0.9995:
        q = a + (b - a) * t
        return q / np.linalg.norm(q)
    th = math.acos(d)
    s = math.sin(th)
    return (math.sin((1.0 - t) * th) * a + math.sin(t * th) * b) / s


# ----------------------------------------------------------------------------------------------- blending

def local_of(pose):
    """{bone: its rotation relative to its parent (armature space)} and the pelvis offset of a solved pose."""
    r = pose.rest
    out = {}
    for b in r.order:
        p = r.parent[b]
        Dp = pose.D[p] if p else np.eye(3)
        out[b] = _quat(Dp.T @ pose.D[b])
    return out, pose.offset.copy()


def from_local(rest, loc, offset):
    import clips
    pose = clips.Pose(rest)
    for b, q in loc.items():
        pose.set_rel(b, _mat(q))
    pose.offset = np.asarray(offset, np.float64).copy()
    return pose.solve()


def blend(rest, a, b, t):
    """The pose between solved poses a and b at t (0..1): every bone's local rotation slerped, the offset lerped."""
    la, oa = local_of(a)
    lb, ob = local_of(b)
    loc = {k: _slerp(la[k], lb[k], t) for k in la}
    return from_local(rest, loc, oa * (1.0 - t) + ob * t)


def ease(t, kind="smooth"):
    t = min(1.0, max(0.0, t))
    if kind == "in":          # accelerating (a blow coming down)
        return t * t
    if kind == "out":         # decelerating (settling)
        return 1.0 - (1.0 - t) * (1.0 - t)
    if kind == "linear":
        return t
    return t * t * (3.0 - 2.0 * t)


def keyed(holder, rest, keys, frames, two_hand=None):
    """The clip's frames from keys [(time s, solved pose, ease into it)]: frame f at f / FPS. `two_hand(time)` gives
    the left hand's weight on the trunk (0 free .. 1 on it), solved onto the trunk after the blend."""
    out = []
    for f in range(frames + 1):
        t = f / FPS
        i = 0
        while i < len(keys) - 2 and t > keys[i + 1][0]:
            i += 1
        t0, p0, _e0 = keys[i]
        t1, p1, e1 = keys[i + 1]
        u = 0.0 if t1 <= t0 else ease((t - t0) / (t1 - t0), e1)
        pose = blend(rest, p0, p1, u)
        if two_hand is not None:
            w = two_hand(t)
            if w > 1e-3:
                left_on_trunk(holder, pose, w)
        out.append(pose.solve())
    return out


def left_on_trunk(holder, pose, w):
    """The left fist on the trunk LEFT_ON_TRUNK_M up from the right fist, weighted in by w (its own pose at 0)."""
    import stoneback as sb
    g, a = holder.grip_posed(pose.solve(), "r")
    gl = g + a * (LEFT_ON_TRUNK_M / sb.F)
    if w < 0.999:
        here, _ = holder.grip_posed(pose, "l")
        gl = here * (1.0 - w) + gl * w
    holder.hold(pose, "l", gl, a, pole=(0.7, 0.2, -0.4))
    pose.solve()


# ----------------------------------------------------------------------------------------------- key builders

def body(rest, pelvis=(0.0, 0.0, 0.0), spine=(0.0, 0.0, 0.0), neck=(0.0, 0.0), head=(0.0, 0.0, 0.0),
         lift=0.0, back=0.0, side=0.0, feet=None, drop=0.03, clav=(0.0, 0.0)):
    """A body key: the pelvis turned (X pitch: + forward, Y roll, Z yaw: + toward his left), the three spine bones
    by `spine` (degrees each, the same split as A1's: 0.8, 1, 1), the neck and head, the pelvis raised by `lift`,
    moved back by `back` (+Y) and to his left by `side`, the feet {side: (offset from the rest ankle, yaw, pitch,
    toe)}, `drop` the knees' bend. The arms are the caller's."""
    import clips
    from clips import X, Y, Z, rot
    pose = clips.Pose(rest)
    pose.offset = np.array([side, back, lift])
    pose.set_rel("pelvis", rot(X, pelvis[0]) @ rot(Y, pelvis[1]) @ rot(Z, pelvis[2]))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        pose.set_rel(b, rot(X, spine[0] * k) @ rot(Y, spine[1] * k) @ rot(Z, spine[2] * k))
    pose.set_rel("clavicle_l", rot(Y, -clav[0]))
    pose.set_rel("clavicle_r", rot(Y, clav[1]))
    pose.set_rel("neck_01", rot(X, neck[0]) @ rot(Z, neck[1]))
    pose.set_rel("head", rot(X, head[0]) @ rot(Y, head[1]) @ rot(Z, head[2]))
    feet = feet or {}
    spec = {}
    for s in ("l", "r"):
        off, yaw, pitch, toe = feet.get(s, ((0.0, 0.0, 0.0), 0.0, 0.0, 0.0))
        spec[s] = (clips.rest_ankle(rest, s) + np.asarray(off, np.float64), yaw, pitch, toe)
    clips.set_legs(pose, spec, drop=drop)
    pose.solve()
    return pose


def hold_trunk(holder, pose, grip, axis, two=True, pole_r=(-0.6, 0.15, -0.3), pole_l=(0.7, 0.2, -0.4)):
    """The right fist's grip at `grip` with the trunk along `axis` (toward the root ball), and the left fist on the
    trunk when `two`."""
    import stoneback as sb
    axis = sb.unit(np.asarray(axis, np.float64))
    holder.hold(pose, "r", np.asarray(grip, np.float64), axis, pole=pole_r)
    if two:
        holder.hold(pose, "l", np.asarray(grip, np.float64) + axis * (LEFT_ON_TRUNK_M / sb.F), axis, pole=pole_l)
    return pose.solve()


def free_left(pose, swing=-4.0, elbow=22.0, out=None):
    import brute as br
    import clips
    clips.set_arm(pose, "l", swing, elbow, out_deg=br.ARM_OUT_DEG if out is None else out)
    return pose.solve()


def club_low(rest):
    """The club's length to the root ball's centre (design m) and the root ball's radius: for keys that strike
    or rest the ball on the ground."""
    import stoneback as sb
    return (sb.CLUB["length_m"] - 0.45 * sb.CLUB["root_r"]) / sb.F, sb.CLUB["root_r"] / sb.F


def ground_axis(grip, forward_y, rest, sideways=0.0):
    """The trunk's line from `grip` that puts the root ball's underside on the ground `forward_y` ahead (its yaw
    tilted `sideways` toward his left): solved for the downward tilt."""
    L, R = club_low(rest)
    g = np.asarray(grip, np.float64)
    z = (0.85 * R - g[2]) / L
    z = max(-0.98, min(0.3, z))
    h = math.sqrt(max(1e-6, 1.0 - z * z))
    d = np.array([sideways, forward_y, 0.0])
    d = d / max(np.linalg.norm(d), 1e-6) * h
    return np.array([d[0], d[1], z])


def idle0(holder, rest):
    import stoneback as sb
    return sb.idle_pose(holder, rest, 0, sb.CLIP_FRAMES["idle"]).solve()


# ----------------------------------------------------------------------------------------------- the clips

def smash(holder, rest):
    import stoneback as sb
    k0 = sb.overhead_pose(holder, rest, sb.CLIP_FRAMES["overhead"], sb.CLIP_FRAMES["overhead"]).solve()
    stance = {"l": ((0.06, -0.34, 0.0), 8.0, 0.0, 0.0), "r": ((-0.08, 0.30, 0.0), -22.0, 0.0, 0.0)}
    # over the top: the trunk upright above his head, the arms high and forward, the body coming forward
    # A3, the anticipation: he sinks into his knees and cocks the trunk further back over his shoulders, gathering
    kd = body(rest, pelvis=(-7.0, 0.0, 4.0), spine=(-9.0, 0.0, 3.0), neck=(5.0, 0.0), head=(7.0, 0.0, 0.0),
              back=0.03, feet=stance, drop=0.20, clav=(-14.0, 14.0))
    head = kd.P["head"]
    hold_trunk(holder, kd, head + np.array([-0.06, 0.16, 0.30]), (-0.20, 0.62, -0.76), pole_r=(-0.6, 0.15, -0.3))
    k1 = body(rest, pelvis=(2.0, 0.0, 2.0), spine=(2.0, 0.0, 1.0), neck=(-4.0, 0.0), head=(-6.0, 0.0, 0.0),
              feet=stance, drop=0.12, clav=(-12.0, 12.0))
    head = k1.P["head"]
    hold_trunk(holder, k1, head + np.array([-0.04, -0.38, 0.42]), (0.0, -0.42, 0.91), pole_r=(-0.6, 0.0, -0.4))
    # the blow: bent hard over the front knee, the fists low before him, the root ball on the ground ahead
    k2 = body(rest, pelvis=(16.0, 0.0, 3.0), spine=(9.0, 0.0, 1.0), neck=(-10.0, 0.0), head=(-16.0, 0.0, 0.0),
              lift=0.0, back=0.04, feet=stance, drop=0.42, clav=(6.0, -6.0))
    sh = 0.5 * (k2.P["upperarm_l"] + k2.P["upperarm_r"])
    g2 = np.array([-0.04, sh[1] - 0.86, sh[2] - 1.08])
    hold_trunk(holder, k2, g2, ground_axis(g2, -1.0, rest), pole_r=(-0.7, 0.2, 0.3), pole_l=(0.7, 0.2, 0.3))
    # A3, the overshoot: the weight carries on past the blow - lower over the knee, the head down, the fists
    # pressed after the root ball
    ko = body(rest, pelvis=(21.0, 0.0, 3.0), spine=(12.0, 0.0, 1.0), neck=(-12.0, 0.0), head=(-19.0, 0.0, 0.0),
              back=0.04, feet=stance, drop=0.50, clav=(8.0, -8.0))
    # the root ball stays where it struck: the fists follow the body down the trunk's line to it
    L, _R = club_low(rest)
    ball = g2 + ground_axis(g2, -1.0, rest) * L
    sh = 0.5 * (ko.P["upperarm_l"] + ko.P["upperarm_r"])
    toward = ball - (sh + np.array([-0.04, -0.62, -1.02]))
    axis_o = toward / np.linalg.norm(toward)
    hold_trunk(holder, ko, ball - axis_o * L, axis_o, pole_r=(-0.7, 0.2, 0.3), pole_l=(0.7, 0.2, 0.3))
    # the rebound: a little up off the blow, the trunk still on the ground
    k3 = body(rest, pelvis=(13.0, 0.0, 3.0), spine=(7.0, 0.0, 1.0), neck=(-6.0, 0.0), head=(-10.0, 0.0, 0.0),
              back=0.03, feet=stance, drop=0.36, clav=(4.0, -4.0))
    sh = 0.5 * (k3.P["upperarm_l"] + k3.P["upperarm_r"])
    g3 = np.array([-0.06, sh[1] - 0.82, sh[2] - 1.04])
    hold_trunk(holder, k3, g3, ground_axis(g3, -1.0, rest, 0.05), pole_r=(-0.7, 0.2, 0.3), pole_l=(0.7, 0.2, 0.3))
    # standing up: the trunk dragged back toward his side in the right hand, the left hand let go
    k4 = body(rest, pelvis=(5.0, 0.0, -2.0), spine=(3.0, 0.0, -1.0), neck=(-2.0, 0.0), head=(-2.0, 0.0, 0.0),
              feet={"l": ((0.03, -0.16, 0.0), 4.0, 0.0, 0.0), "r": ((-0.04, 0.14, 0.0), -10.0, 0.0, 0.0)},
              drop=0.12)
    sh = k4.P["upperarm_r"]
    g4 = sh + np.array([-0.18, -0.55, -0.95])
    holder.hold(k4, "r", g4, ground_axis(g4, -0.7, rest, -0.45), pole=(-0.7, 0.4, 0.2))
    free_left(k4, -10.0, 26.0)
    k5 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (SMASH_DIP, kd, "out"), (0.19, k1, "in"), (SMASH_HIT, k2, "in"), (0.42, ko, "out"),
            (0.72, k3, "smooth"), (1.25, k4, "smooth"), (FRAMES["smash"] / FPS, k5, "smooth")]

    def two(t):
        return 1.0 if t <= 0.6 else max(0.0, 1.0 - (t - 0.6) / 0.35)
    return keyed(holder, rest, keys, FRAMES["smash"], two)


def sweep(holder, rest):
    k0 = idle0(holder, rest)
    wide = {"l": ((0.14, -0.22, 0.0), 14.0, 0.0, 0.0), "r": ((-0.18, 0.18, 0.0), -24.0, 0.0, 0.0)}
    # wound: turned away to his right, the trunk low behind his right hip, both hands on it
    # (A3: the body wound further, 31 -> 42 degrees, and sunk lower into the knees: the gathering before the swing)
    k1 = body(rest, pelvis=(6.0, 0.0, -22.0), spine=(5.0, 3.0, -20.0), neck=(0.0, 22.0), head=(-4.0, 0.0, 16.0),
              feet=wide, drop=0.32, side=0.05)
    hip = k1.P["thigh_r"]
    g1 = hip + np.array([-0.28, 0.20, 0.42])
    hold_trunk(holder, k1, g1, (-0.55, 0.78, -0.30), pole_r=(-0.5, 0.6, -0.4), pole_l=(0.3, 0.6, -0.4))
    # the blow: square to his front, the trunk swung across before him at the knees
    k2 = body(rest, pelvis=(8.0, 0.0, 6.0), spine=(6.0, -2.0, 8.0), neck=(0.0, -4.0), head=(-6.0, 0.0, -4.0),
              feet=wide, drop=0.30)
    sh = 0.5 * (k2.P["upperarm_l"] + k2.P["upperarm_r"])
    g2 = np.array([0.08, sh[1] - 0.80, sh[2] - 1.12])
    hold_trunk(holder, k2, g2, (0.20, -0.90, -0.38), pole_r=(-0.7, 0.0, -0.5), pole_l=(0.7, 0.0, -0.5))
    # past: round to his left, the trunk out at his left side
    k3 = body(rest, pelvis=(6.0, 0.0, 28.0), spine=(4.0, -4.0, 22.0), neck=(0.0, -14.0), head=(-4.0, 0.0, -12.0),
              feet=wide, drop=0.26, side=-0.03)
    hipl = k3.P["thigh_l"]
    g3 = hipl + np.array([0.30, -0.42, 0.55])
    hold_trunk(holder, k3, g3, (0.88, -0.25, -0.40), pole_r=(-0.4, -0.4, -0.5), pole_l=(0.6, 0.3, -0.5))
    # A3, the overshoot: the trunk's weight carries him on round past his left side before he checks it
    kx = body(rest, pelvis=(8.0, 0.0, 36.0), spine=(5.0, -5.0, 28.0), neck=(0.0, -16.0), head=(-5.0, 0.0, -12.0),
              feet=wide, drop=0.30, side=-0.05)
    gx = kx.P["thigh_l"] + np.array([0.42, -0.10, 0.50])
    hold_trunk(holder, kx, gx, (0.78, 0.18, -0.48), pole_r=(-0.4, -0.5, -0.5), pole_l=(0.6, 0.3, -0.5))
    # following through: the trunk coming down by his left foot, the left hand letting go
    k4 = body(rest, pelvis=(10.0, 0.0, 14.0), spine=(6.0, -2.0, 10.0), neck=(-2.0, -6.0), head=(-6.0, 0.0, -4.0),
              feet=wide, drop=0.24)
    g4 = k4.P["thigh_l"] + np.array([0.05, -0.55, 0.38])
    holder.hold(k4, "r", g4, ground_axis(g4, -0.6, rest, 0.6), pole=(-0.6, 0.0, -0.4))
    free_left(k4, -14.0, 30.0, 18.0)
    k5 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.9, k1, "out"), (SWEEP_HIT, k2, "in"), (1.45, k3, "linear"), (1.62, kx, "out"),
            (1.9, k4, "smooth"), (FRAMES["sweep"] / FPS, k5, "smooth")]

    def two(t):
        if t < 0.25:
            return 0.0
        if t < 0.6:
            return (t - 0.25) / 0.35
        if t <= 1.62:
            return 1.0
        return max(0.0, 1.0 - (t - 1.62) / 0.25)
    return keyed(holder, rest, keys, FRAMES["sweep"], two)


def charge_run(holder, rest, gaits):
    """The run's legs and pelvis (the gait), the charge's upper body over them (A1's charge peak: the trunk
    pitched, the left shoulder leading, the left arm braced across the chest, the trunk trailing low)."""
    import brute as br
    import stoneback as sb
    from clips import X, Y, Z, rot
    frames = FRAMES["charge_run"]
    out = []
    for f in range(frames + 1):
        phi = 2.0 * math.pi * f / frames
        pose = br.brute_gait_pose(gaits["run"], phi)
        bob = math.sin(2.0 * phi)
        for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
            pose.set_rel(b, rot(X, (9.0 + 1.0 * bob) * k) @ rot(Z, -11.0 * k) @ rot(Y, 3.0 * k))
        pose.set_rel("clavicle_l", rot(Z, -6.0) @ rot(Y, 6.0))
        pose.set_rel("neck_01", rot(X, -12.0) @ rot(Z, 12.0))
        pose.set_rel("head", rot(X, -14.0) @ rot(Z, 8.0))
        pose.solve()
        shl, shr = pose.P["upperarm_l"], pose.P["upperarm_r"]
        chest = 0.5 * (shl + shr) + np.array([0.0, -0.30, -0.30])
        holder.hold(pose, "l", chest, sb.unit(np.array([-1.0, -0.15, 0.25])), pole=(0.8, -0.2, -0.5),
                    palm=(0.0, 1.0, 0.0))
        pose.solve()
        hip = pose.P["thigh_r"]
        sway = 0.06 * math.sin(phi)
        holder.hold(pose, "r", hip + np.array([-0.30, 0.42 + sway, -0.05]), sb.unit(np.array([-0.30, 0.62, -0.72])),
                    pole=(-0.6, 0.3, -0.4))
        out.append(pose.solve())
    return out


def reel(holder, rest):
    k0 = idle0(holder, rest)
    # struck: the head snapped back, the chest up, a step back on the right foot, the arms thrown out
    k1 = body(rest, pelvis=(-8.0, 0.0, 4.0), spine=(-9.0, 2.0, 3.0), neck=(-10.0, 6.0), head=(-18.0, 4.0, 8.0),
              back=0.10, feet={"l": ((0.04, -0.06, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.40, 0.0), -16.0, 0.0, 0.0)},
              drop=0.10)
    g1 = k1.P["upperarm_r"] + np.array([-0.85, -0.05, -0.75])
    holder.hold(k1, "r", g1, ground_axis(g1, 0.2, rest, -0.9), pole=(-0.4, 0.6, 0.3))
    free_left(k1, -6.0, 30.0, 20.0)
    # stumbling, hunched: bent over the knees, the head hanging, the left hand to the brow, the trunk dragging
    k2 = body(rest, pelvis=(20.0, 0.0, -6.0), spine=(10.0, -3.0, -4.0), neck=(14.0, -6.0), head=(16.0, 0.0, -10.0),
              back=0.12, feet={"l": ((0.10, -0.18, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.36, 0.0), -18.0, 0.0, 0.0)},
              drop=0.40)
    g2 = k2.P["thigh_r"] + np.array([-0.40, -0.40, -0.30])
    holder.hold(k2, "r", g2, ground_axis(g2, -0.5, rest, -0.6), pole=(-0.6, 0.3, -0.2))
    k2.solve()
    # (A3: the left hand braced on the left thigh above the knee, not raised to the brow: between the keys the arm
    # swung up past the head on its way there)
    brace = k2.P["calf_l"] + np.array([0.04, -0.20, 0.30])
    holder.hold(k2, "l", brace, np.array([-0.3, -0.5, -0.8]), pole=(0.9, 0.3, -0.1), palm=(0.0, 0.0, -1.0))
    # still dazed, swaying the other way
    k3 = body(rest, pelvis=(17.0, 0.0, 5.0), spine=(9.0, 3.0, 4.0), neck=(10.0, 8.0), head=(12.0, 0.0, 8.0),
              back=0.10, feet={"l": ((0.10, -0.18, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.36, 0.0), -18.0, 0.0, 0.0)},
              drop=0.34)
    g3 = k3.P["thigh_r"] + np.array([-0.38, -0.45, -0.28])
    holder.hold(k3, "r", g3, ground_axis(g3, -0.5, rest, -0.6), pole=(-0.6, 0.3, -0.2))
    free_left(k3, -18.0, 46.0, 16.0)
    k4 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.22, k1, "out"), (0.8, k2, "smooth"), (1.55, k3, "smooth"),
            (FRAMES["reel"] / FPS, k4, "smooth")]
    return keyed(holder, rest, keys, FRAMES["reel"])


def rip(holder, rest):
    import stoneback as sb
    k0 = idle0(holder, rest)
    crouch_feet = {"l": ((0.10, -0.24, 0.0), 12.0, 0.0, 0.0), "r": ((-0.10, 0.22, 0.0), -16.0, 0.0, 0.0)}
    # down: a deep crouch over the left knee, the left hand on the ground outside the left foot
    k1 = body(rest, pelvis=(30.0, -4.0, 14.0), spine=(14.0, -6.0, 6.0), neck=(-12.0, 6.0), head=(-14.0, 0.0, 8.0),
              back=0.10, feet=crouch_feet, drop=0.66)
    ankle = rest.head["foot_l"] + np.array([0.10, -0.24, 0.0])
    gl = ankle + np.array([0.22, -0.38, 0.16])
    holder.hold(k1, "l", gl, np.array([0.0, 0.0, -1.0]), pole=(0.9, 0.3, -0.2), palm=(0.0, 0.0, -1.0))
    g1 = k1.P["upperarm_r"] + np.array([-0.55, 0.50, -0.85])
    holder.hold(k1, "r", g1, ground_axis(g1, 0.6, rest, -0.6), pole=(-0.6, 0.5, -0.2))
    # gripped: the fist closed on the stone, the back straining, the hand just off the ground
    k2 = body(rest, pelvis=(26.0, -4.0, 12.0), spine=(10.0, -6.0, 6.0), neck=(-14.0, 6.0), head=(-12.0, 0.0, 8.0),
              back=0.10, feet=crouch_feet, drop=0.58)
    holder.hold(k2, "l", gl + np.array([0.0, 0.02, 0.14]), np.array([0.0, 0.1, -1.0]), pole=(0.9, 0.3, -0.2),
                palm=(0.0, 0.0, -1.0))
    g2 = k2.P["upperarm_r"] + np.array([-0.55, 0.48, -0.85])
    holder.hold(k2, "r", g2, ground_axis(g2, 0.6, rest, -0.6), pole=(-0.6, 0.5, -0.2))
    k3 = sb.throw_pose(holder, rest, 0, sb.CLIP_FRAMES["throw"]).solve()
    keys = [(0.0, k0, "smooth"), (0.45, k1, "out"), (RIP_GRIP, k2, "smooth"), (FRAMES["rip"] / FPS, k3, "smooth")]
    return keyed(holder, rest, keys, FRAMES["rip"])


def release(holder, rest):
    import stoneback as sb
    k0 = sb.throw_pose(holder, rest, sb.CLIP_FRAMES["throw"], sb.CLIP_FRAMES["throw"]).solve()
    stride = {"l": ((0.10, 0.30, 0.0), 24.0, 0.0, 0.0), "r": ((-0.06, -0.36, 0.0), -6.0, 0.0, 0.0)}
    # let go: the weight over the front (right) foot, the torso turned to the front, the arm high and ahead
    k1 = body(rest, pelvis=(10.0, 0.0, -10.0), spine=(8.0, 0.0, -8.0), neck=(-6.0, 6.0), head=(-8.0, 0.0, 4.0),
              back=-0.06, feet=stride, drop=0.14)
    sh = k1.P["upperarm_l"]
    holder.hold(k1, "l", sh + np.array([-0.10, -0.95, 0.35]), sb.unit(np.array([0.0, -0.6, 0.8])),
                pole=(1.0, 0.2, -0.5), palm=(0.0, -0.6, -0.8))
    import clips
    clips.set_arm(k1, "r", 10.0, 24.0, out_deg=26.0)
    k1.solve()
    holder.orient_hand(k1, "r", sb.unit(np.array([-0.5, 0.5, -0.7])))
    # following through: the left arm swung down across to the right knee, bent forward over the front leg
    k2 = body(rest, pelvis=(18.0, 0.0, -16.0), spine=(10.0, 0.0, -10.0), neck=(-8.0, 8.0), head=(-10.0, 0.0, 6.0),
              back=-0.08, feet=stride, drop=0.26)
    knee = k2.P["calf_r"]
    holder.hold(k2, "l", knee + np.array([0.30, -0.30, 0.25]), sb.unit(np.array([-0.6, -0.3, -0.7])),
                pole=(1.0, 0.0, -0.3), palm=(0.0, 0.0, -1.0))
    clips.set_arm(k2, "r", 18.0, 28.0, out_deg=24.0)
    k2.solve()
    holder.orient_hand(k2, "r", sb.unit(np.array([-0.4, 0.6, -0.7])))
    k3 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (RELEASE_AT, k1, "in"), (0.6, k2, "out"), (FRAMES["release"] / FPS, k3, "smooth")]
    return keyed(holder, rest, keys, FRAMES["release"])


def death(holder, rest):
    import clips
    from clips import X, Z, rot
    k0 = idle0(holder, rest)
    # struck: rocked back, the head thrown back
    k1 = body(rest, pelvis=(-10.0, 0.0, 6.0), spine=(-8.0, 2.0, 4.0), neck=(-12.0, 4.0), head=(-20.0, 4.0, 6.0),
              back=0.12, feet={"l": ((0.04, 0.04, 0.0), 6.0, 0.0, 0.0), "r": ((-0.06, 0.34, 0.0), -14.0, 0.0, 0.0)},
              drop=0.12)
    g1 = k1.P["upperarm_r"] + np.array([-0.90, 0.05, -0.65])
    holder.hold(k1, "r", g1, ground_axis(g1, 0.3, rest, -0.9), pole=(-0.4, 0.6, 0.3))
    free_left(k1, -26.0, 34.0, 36.0)
    # kneeling: both knees down, slumped, the arms hanging, the trunk let go (it lies on the ground by his right)
    kneel = body(rest, pelvis=(12.0, 0.0, 0.0), spine=(14.0, 0.0, 0.0), neck=(12.0, 0.0), head=(16.0, 0.0, -6.0),
                 back=0.0, feet={"l": ((0.0, 0.42, 0.0), 0.0, 60.0, 30.0), "r": ((0.0, 0.46, 0.0), 0.0, 60.0, 30.0)},
                 drop=1.05)
    g2 = kneel.P["upperarm_r"] + np.array([-0.55, -0.35, -1.05])
    holder.hold(kneel, "r", g2, ground_axis(g2, -0.3, rest, -1.0), pole=(-0.6, 0.3, 0.2))
    free_left(kneel, -12.0, 20.0, 14.0)
    # face down: pitched forward onto the ground from the knees, the arms out before him
    down = clips.Pose(rest)
    down.offset = np.array([0.0, -1.05, -1.62])
    down.set_rel("pelvis", rot(X, 78.0) @ rot(Z, -6.0))
    for b, k in (("spine_01", 0.8), ("spine_02", 1.0), ("spine_03", 1.0)):
        down.set_rel(b, rot(X, 4.0 * k))
    down.set_rel("neck_01", rot(X, -18.0))
    down.set_rel("head", rot(X, -26.0) @ rot(Z, 30.0))
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        down.set_rel("thigh_" + s, rot(X, -70.0) @ rot(Z, 4.0 * sgn))
        down.set_rel("calf_" + s, rot(X, 30.0))
        down.set_rel("foot_" + s, rot(X, 40.0))
    down.solve()
    clips.set_arm(down, "l", -150.0, 18.0, out_deg=30.0)
    clips.set_arm(down, "r", -140.0, 24.0, out_deg=34.0)
    down.solve()
    keys = [(0.0, k0, "smooth"), (0.35, k1, "out"), (1.15, kneel, "smooth"), (FRAMES["death"] / FPS, down, "in")]
    return keyed(holder, rest, keys, FRAMES["death"])


# ----------------------------------------------------------------------------------------------- A4: down on a knee

KNEE_R = 0.07                      # the kneeling knee's height over the ground at rest on it (design m)


def _leg_lengths(rest, s):
    h = rest.head
    return (float(np.linalg.norm(h["calf_" + s] - h["thigh_" + s])),
            float(np.linalg.norm(h["foot_" + s] - h["calf_" + s])))


def kneel_key(holder, rest, depth=1.0, lean=1.0, settle=0.0):
    """A4: down on his right knee - the right thigh near upright over the knee on the ground, the shin laid back
    along it with the toes dug in; the left foot planted ahead, its knee up, the left hand braced on it; the trunk
    planted by his right side, its root ball on the ground; the trunk pitched forward over the knee, the head
    hanging a little (he is hurt). `depth` (0..1) how far down the pelvis has gone, `lean` the forward pitch's
    share, `settle` a little rebound up off the ground (design m)."""
    l1, l2 = _leg_lengths(rest, "r")
    pel = (9.0 * lean, 0.0, -6.0)
    spine = (11.0 * lean, 2.0, -4.0)
    # first the hip's height at the pose's rotation (a small drop), then the drop that sets the knee on the ground
    probe = body(rest, pelvis=pel, spine=spine, drop=0.03)
    hip = probe.P["thigh_r"].copy()
    want_z = l1 * 0.985 + KNEE_R + settle
    full = max(0.03, float(hip[2]) + 0.03 - want_z)
    drop = 0.03 + (full - 0.03) * depth
    hip_z = float(hip[2]) + 0.03 - drop
    knee = np.array([hip[0] - 0.02, hip[1] - 0.04, hip_z - l1 * 0.985])
    back = math.sqrt(max(1e-6, l2 * l2 * 0.97 - max(0.0, knee[2] - 0.15) ** 2))
    ankle_r = np.array([knee[0] + 0.02, knee[1] + back * depth + 0.08 * (1.0 - depth), 0.15])
    ankle_r[2] = max(ankle_r[2], float(rest.head["foot_r"][2]))
    feet = {"l": ((0.08, -0.72 * min(1.0, depth * 1.4), 0.0), 10.0, 0.0, 0.0),
            "r": (tuple(ankle_r - rest.head["foot_r"]), -8.0, 58.0 * depth, 34.0 * depth)}
    k = body(rest, pelvis=pel, spine=spine, neck=(10.0 * lean, -4.0), head=(12.0 * lean, 0.0, -6.0),
             feet=feet, drop=drop, clav=(4.0, 6.0))
    # the left hand braced on the raised knee, the palm down on it
    kl = k.P["calf_l"]
    holder.hold(k, "l", kl + np.array([0.02, -0.12, 0.10]), np.array([-0.35, -0.55, -0.75]), pole=(0.9, 0.2, -0.1),
                palm=(0.0, 0.0, -1.0))
    # the trunk planted at his right side, the root ball on the ground ahead and out
    g = k.P["upperarm_r"] + np.array([-0.42, -0.42, -0.72])
    holder.hold(k, "r", g, ground_axis(g, -0.55, rest, -0.75), pole=(-0.6, 0.3, -0.2))
    return k.solve()


def kneel(holder, rest):
    """A4 (24 frames): a shin plate broken, his right leg gives way - the knee buckles (KNEEL_BUCKLE), he lurches
    forward and the knee strikes the ground (KNEEL_HIT), a little rebound and he settles there (the last frame, held
    while he is down)."""
    k0 = idle0(holder, rest)
    kb = kneel_key(holder, rest, depth=0.45, lean=1.2)
    kh = kneel_key(holder, rest, depth=1.0, lean=0.9)
    ks = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    keys = [(0.0, k0, "smooth"), (KNEEL_BUCKLE, kb, "in"), (KNEEL_HIT, kh, "in"), (FRAMES["kneel"] / FPS, ks, "out")]
    return keyed(holder, rest, keys, FRAMES["kneel"])


def rise(holder, rest):
    """A4 (36 frames): from the kneel, the weight pushed onto the left hand on the knee, the right foot brought
    under him, up onto both feet and back to the stance (the idle's first key)."""
    k0 = kneel_key(holder, rest, depth=1.0, lean=0.5, settle=0.015)
    kp = kneel_key(holder, rest, depth=0.85, lean=1.3)
    ku = kneel_key(holder, rest, depth=0.35, lean=0.9)
    k3 = idle0(holder, rest)
    keys = [(0.0, k0, "smooth"), (0.35, kp, "smooth"), (0.8, ku, "out"), (FRAMES["rise"] / FPS, k3, "smooth")]
    return keyed(holder, rest, keys, FRAMES["rise"])


def make(holder, rest, gaits):
    """Every A2 clip's solved frames (and A4's kneel and rise): {name: [pose, ...]} in FRAMES's order."""
    out = {}
    for name in FRAMES:
        if name == "charge_run":
            out[name] = charge_run(holder, rest, gaits)
        else:
            out[name] = globals()[name](holder, rest)
    return out
