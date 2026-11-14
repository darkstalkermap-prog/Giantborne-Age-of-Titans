"""The giant's computed-keyframe clips (P43; plan M10 §2.5 the step --clips, §2.9, design item 3).

No hand animation: every key is computed here, like the audio generators compute every sample. The
clips drive the skeleton of giant.glb (the MPFB2 "game_engine" rig, 53 bones) and are written into
assets/giant/giant_clips.glb, which Godot imports with the animation_library importer as an
AnimationLibrary (loops are set in code; imported clips have loop off). The rig is built exactly as
export_game.py builds it (giant_body.build_giant at the stage-1 height), so every bone's rest is the
model's.

  idle       2 s loop: breathing (spine and clavicles), the arms hanging relaxed, the feet planted
  walk       one two-step cycle, 32 keys; the game seeks it from the pose brain's walk phase
  run        the same cycle as a run: flight phases, a forward lean, bent pumping arms, high knees
  airborne   the legs gathered (a jump, a fall)
  death      1 s: the knees buckle and the torso slumps (the game seeks it by the body's fall)
  grip_r, grip_l, open_r, open_l    one-frame finger poses, blended per hand with a bone filter

The walk and the run are computed from the feet, not from joint angles: each foot plants on the ground
at its heel strike and moves backward relative to the hips at exactly the body's speed while it is
planted (heel rocker, flat foot, forefoot rocker: the point on the ground never slides), then swings
forward along a Hermite curve; a two-bone solve (the knee toward a forward pole) places the thigh and
the calf; the pelvis drops just enough that both legs always reach (the knee never locks), sways over
the stance leg and turns with the swing leg; the spine counter-turns. Clip phase phi in [0, 2 pi):
the LEFT heel strikes at pi/2 and the right at 3 pi/2, so with the game's mapping
t = fposmod(walk_phase + pi/2, 2 pi) / 2 pi x length the heel strikes fall on the brain's footfalls
(walk_phase = 0, pi). One cycle is two steps of STEP_M (the brain's stride_length_m, 1.6 m at k = 1),
so the stride is 3.2 m per cycle by construction; the script measures it on the posed skeleton and
writes it into clips_info.json (the manifest's "clips").

Poses are written as armature-space rotations of each bone relative to its rest ("deltas"), as the
research kit's giant_pose.py writes its character-space operations (ported: local_quat's conjugation
by the rest rotation and mirror_ops), then turned into each pose bone's local quaternion:
B = R0^-1 (D_parent^-1 D) R0. Character (armature) space: +X the giant's left, -Y his front, +Z up,
metres at stage 1.

Usage (the shared venv; build_giant.py --clips runs it): python clips.py <assets dir> [<work dir>]
"""
from __future__ import annotations

import json
import math
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import giant_body as gb  # noqa: E402

H = gb.STAGE1_HEIGHT_M
GLB_NAME = "giant_clips.glb"
INFO_NAME = "clips_info.json"
FPS = 30
STEP_M = 1.6                      # ActorRig.stride_length_m: one footfall per STEP_M at k = 1
CYCLE_M = 2.0 * STEP_M            # a two-step cycle
LEFT_STRIKE = 0.5 * math.pi       # clip phase of the left heel strike (the brain's footfall at walk phase 0)
RIGHT_STRIKE = 1.5 * math.pi
REACH_USE = 0.985                 # the legs reach at most this share of their length (never a locked knee)
MAX_SWING = 0.3                   # the most a gait's pelvis may rise and fall over a step (m, stage 1)
FINGERS = ("index", "middle", "ring", "pinky")
LEG_BONES = ("thigh", "calf", "foot", "ball")

# The clips and their key counts (frames + 1 keys; the last key of a loop equals its first).
CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "airborne": 1, "death": 30,
               "grip_r": 1, "grip_l": 1, "open_r": 1, "open_l": 1}
LOOPS = ("idle", "walk", "run")

# The gaits (metres and degrees at stage 1). duty: the share of the cycle a foot is planted.
GAITS = {
    "walk": {"duty": 0.55, "foot_x": 0.27, "lift": 0.20, "lift_peak": 0.45, "strike_deg": -16.0, "toe_off_deg": 34.0,
             "heel_rocker": 0.12, "heel_off": 0.62, "bias": 0.0, "top_drop": 0.03, "min_drop": 0.03,
             "sway": 0.035, "yaw_deg": 5.0, "roll_deg": 2.5, "pelvis_pitch_deg": 2.0, "lean_deg": 3.0,
             "arm_swing_deg": 16.0, "elbow_deg": 18.0, "elbow_swing_deg": 8.0, "shoulder_counter": 1.6},
    "run": {"duty": 0.36, "foot_x": 0.22, "lift": 0.62, "lift_peak": 0.38, "strike_deg": -8.0, "toe_off_deg": 40.0,
            "heel_rocker": 0.10, "heel_off": 0.45, "bias": 0.04, "top_drop": 0.10, "min_drop": 0.15,
            "sway": 0.02, "yaw_deg": 7.0, "roll_deg": 3.0, "pelvis_pitch_deg": 7.0, "lean_deg": 10.0,
            "arm_swing_deg": 34.0, "elbow_deg": 78.0, "elbow_swing_deg": 14.0, "shoulder_counter": 1.4},
}


def log(*a):
    print("[clips]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


# --------------------------------------------------------------------------------------
# rotations (numpy 3x3)
# --------------------------------------------------------------------------------------
def rot(axis, deg):
    a = np.asarray(axis, np.float64)
    a = a / np.linalg.norm(a)
    t = math.radians(deg)
    c, s = math.cos(t), math.sin(t)
    x, y, z = a
    return np.array([[c + x * x * (1 - c), x * y * (1 - c) - z * s, x * z * (1 - c) + y * s],
                     [y * x * (1 - c) + z * s, c + y * y * (1 - c), y * z * (1 - c) - x * s],
                     [z * x * (1 - c) - y * s, z * y * (1 - c) + x * s, c + z * z * (1 - c)]])


def unit(v):
    v = np.asarray(v, np.float64)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def between(a, b):
    """The shortest rotation taking direction a onto direction b."""
    a, b = unit(a), unit(b)
    axis = np.cross(a, b)
    s = np.linalg.norm(axis)
    c = float(np.clip(np.dot(a, b), -1.0, 1.0))
    if s < 1e-10:
        if c > 0:
            return np.eye(3)
        perp = unit(np.cross(a, [1.0, 0.0, 0.0] if abs(a[0]) < 0.9 else [0.0, 1.0, 0.0]))
        return rot(perp, 180.0)
    return rot(axis / s, math.degrees(math.atan2(s, c)))


def frame(d, f):
    """An orthonormal frame (columns d, f', d x f') with f' = f made perpendicular to d."""
    d = unit(d)
    f = unit(np.asarray(f) - d * np.dot(f, d))
    return np.column_stack([d, f, np.cross(d, f)])


X, Y, Z = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)


def smooth(t):
    t = min(1.0, max(0.0, t))
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------------------
# character-space operations (ported from the research kit's giant_pose.py)
# --------------------------------------------------------------------------------------
def mirror_dir(v):
    return (-v[0], v[1], v[2])


def mirror_ops(ops):
    """The same operations for the other side (the character's X mirrored)."""
    out = []
    for op in ops:
        if op[0] in ("toward", "aim"):
            out.append((op[0], mirror_dir(op[1]), op[2]))
        elif op[0] == "twist":
            out.append(("twist", -op[1]))
        elif op[0] == "axis":
            a = op[1]
            out.append(("axis", (a[0], -a[1], -a[2]), op[2]))   # an axial vector mirrors as (x, -y, -z)
        else:
            out.append(op)
    return out


class Rest:
    """The armature's rest: per bone its parent, head, tail, rest rotation (armature space)."""

    def __init__(self, rig):
        self.names = [b.name for b in rig.data.bones]
        self.parent = {b.name: (b.parent.name if b.parent else "") for b in rig.data.bones}
        self.head = {b.name: np.array(b.head_local[:], np.float64) for b in rig.data.bones}
        self.tail = {b.name: np.array(b.tail_local[:], np.float64) for b in rig.data.bones}
        self.R0 = {b.name: np.array([list(r) for r in b.matrix_local.to_3x3()], np.float64) for b in rig.data.bones}
        self.order = []
        seen = set()

        def visit(n):
            if n in seen:
                return
            p = self.parent[n]
            if p:
                visit(p)
            seen.add(n)
            self.order.append(n)
        for n in sorted(self.names):
            visit(n)

    def direction(self, b):
        return unit(self.tail[b] - self.head[b])

    def ops_matrix(self, b, ops):
        """The armature-space rotation of character-space ops for bone b, at rest (local_quat's Ra)."""
        d = self.direction(b)
        Ra = np.eye(3)
        for op in ops:
            kind = op[0]
            if kind == "toward":
                M = _toward(d, op[1], op[2])
            elif kind == "aim":            # all the way onto the direction, then op[2] more degrees past it
                M = between(d, op[1])
                if op[2]:
                    M = _toward(d, op[1], math.degrees(math.acos(float(np.clip(np.dot(d, unit(op[1])), -1, 1)))) + op[2])
            elif kind == "twist":
                M = rot(d, op[1])
            elif kind == "axis":
                M = rot(op[1], op[2])
            else:
                raise ValueError(op)
            Ra = M @ Ra
        return Ra


def _toward(d, f, deg):
    axis = np.cross(unit(d), unit(f))
    if np.linalg.norm(axis) < 1e-9:
        return np.eye(3)
    return rot(axis, deg)


class Pose:
    """One frame: armature-space deltas (absolute, or relative to the parent's) and the pelvis offset."""

    def __init__(self, rest: Rest):
        self.rest = rest
        self.abs = {}
        self.rel = {}
        self.offset = np.zeros(3)      # the pelvis head's armature-space translation
        self.D = {}
        self.P = {}

    def set_rel(self, b, M):
        self.rel[b] = M if b not in self.rel else M @ self.rel[b]

    def ops(self, spec):
        for b, ops in spec.items():
            if b in self.rest.R0:
                self.set_rel(b, self.rest.ops_matrix(b, ops))

    def set_abs(self, b, M):
        self.abs[b] = M

    def solve(self):
        """Every bone's delta and posed head (parents first)."""
        r = self.rest
        self.D, self.P = {}, {}
        for b in r.order:
            p = r.parent[b]
            Dp = self.D[p] if p else np.eye(3)
            if b in self.abs:
                D = self.abs[b]
            elif b in self.rel:
                D = Dp @ self.rel[b]
            else:
                D = Dp
            self.D[b] = D
            if p:
                self.P[b] = self.P[p] + Dp @ (r.head[b] - r.head[p])
            else:
                self.P[b] = r.head[b].copy()
            if b == "pelvis":
                self.P[b] = self.P[b] + self.offset
        return self

    def head_of(self, b):
        """The posed head of b from the deltas solved so far (its ancestors must be set)."""
        return self.solve().P[b]

    def basis(self, b):
        """The pose bone's local rotation: R0^-1 (D_parent^-1 D) R0."""
        r = self.rest
        p = r.parent[b]
        Dp = self.D[p] if p else np.eye(3)
        M = r.R0[b].T @ (Dp.T @ self.D[b]) @ r.R0[b]
        return Matrix([list(row) for row in M]).to_quaternion()

    def pelvis_location(self):
        return Vector((self.rest.R0["pelvis"].T @ self.offset).tolist())


# --------------------------------------------------------------------------------------
# hands, arms, legs
# --------------------------------------------------------------------------------------
def hand_frame(rest, side):
    s = "_" + side
    w = rest.head["hand" + s]
    i1 = rest.head["index_01" + s]
    p1 = rest.head["pinky_01" + s]
    t3 = rest.tail["thumb_03" + s]
    across = unit(p1 - i1)
    along = unit((i1 + p1) * 0.5 - w)
    n = unit(np.cross(across, along))
    if np.dot(t3 - (w + i1 + p1) / 3.0, n) < 0:
        n = -n
    return n, across


def hand_spec(rest, side, curl, thumb, spread=0.0):
    """Finger curls (the research kit's hand_ops on the game_engine names): 0 flat ... 1 a fist."""
    n, across = hand_frame(rest, side)
    s = "_" + side
    spec = {}
    for k, f in enumerate(FINGERS):
        fan = (k - 1.5) / 1.5 * spread
        lat = across if fan > 0 else -across
        spec[f"{f}_01{s}"] = [("toward", tuple(n), 90.0 * curl * (0.98 + 0.03 * k)), ("toward", tuple(lat), abs(fan))]
        spec[f"{f}_02{s}"] = [("toward", tuple(n), 105.0 * curl)]
        spec[f"{f}_03{s}"] = [("toward", tuple(n), 68.0 * curl)]
    tdir = unit(n * 0.8 + across * 0.6)
    spec[f"thumb_01{s}"] = [("toward", tuple(tdir), 42.0 * thumb)]
    spec[f"thumb_02{s}"] = [("toward", tuple(n), 34.0 * thumb)]
    spec[f"thumb_03{s}"] = [("toward", tuple(n), 42.0 * thumb)]
    return spec


def arm_spec(side, swing_deg=0.0, elbow_deg=15.0, out_deg=8.0, forward_deg=4.0, raise_deg=0.0):
    """The arm hanging relaxed from the A-pose rest: the upper arm onto a line out_deg outward from straight
    down (forward_deg in front), swung about the giant's left-right axis by swing_deg (negative: forward)
    and raised sideways by raise_deg; the forearm bent forward by elbow_deg, turned so the palm faces the
    thigh. Written for the left side and mirrored for the right."""
    o = math.radians(out_deg)
    fw = math.radians(forward_deg)
    hang = (math.sin(o), -math.sin(fw), -math.cos(o) * math.cos(fw))
    ops_up = [("aim", hang, 0.0), ("axis", X, swing_deg)]
    if raise_deg:
        ops_up.append(("axis", (0.0, 1.0, 0.0), -raise_deg))
    ops_lo = [("axis", X, -elbow_deg)]
    spec = {"upperarm_l": ops_up, "lowerarm_l": ops_lo}
    if side == "r":
        spec = {"upperarm_r": mirror_ops(ops_up), "lowerarm_r": mirror_ops(ops_lo)}
    return spec


class Leg:
    def __init__(self, rest, side):
        s = "_" + side
        self.side = side
        self.thigh, self.calf, self.foot, self.ball = ("thigh" + s, "calf" + s, "foot" + s, "ball" + s)
        h = rest.head
        self.l1 = float(np.linalg.norm(h[self.calf] - h[self.thigh]))
        self.l2 = float(np.linalg.norm(h[self.foot] - h[self.calf]))
        self.ankle0 = h[self.foot].copy()
        self.ball0 = h[self.ball].copy()
        fwd = abs(self.ball0[1] - self.ankle0[1])
        self.heel_back = 0.32 * fwd
        # ground contacts at rest: under the heel, under the ball
        self.heel_c0 = np.array([self.ankle0[0], self.ankle0[1] + self.heel_back, 0.0])
        self.ball_c0 = np.array([self.ball0[0], self.ball0[1], 0.0])
        out = 1.0 if side == "l" else -1.0
        self.pole = unit((0.12 * out, -1.0, 0.0))
        self.d0_thigh = unit(h[self.calf] - h[self.thigh])
        self.d0_calf = unit(h[self.foot] - h[self.calf])

    def reach(self):
        return REACH_USE * (self.l1 + self.l2)

    def place(self, pose, hip, ankle, pitch_deg, toe_deg, pole_rot=None):
        """Thigh and calf by the two-bone solve (hip -> ankle, the knee toward the pole), the foot pitched
        by pitch_deg about the giant's left-right axis (positive: toes down), the toes by toe_deg in the
        world (0: flat on the ground). Sets absolute deltas on `pose`. Returns the knee."""
        pole = self.pole if pole_rot is None else pole_rot @ self.pole
        d = ankle - hip
        dist = float(np.clip(np.linalg.norm(d), abs(self.l1 - self.l2) + 1e-4, (self.l1 + self.l2) * 0.9995))
        dn = unit(d)
        pv = unit(pole - dn * np.dot(pole, dn))
        a = (self.l1 * self.l1 + dist * dist - self.l2 * self.l2) / (2.0 * dist)
        hgt = math.sqrt(max(0.0, self.l1 * self.l1 - a * a))
        knee = hip + dn * a + pv * hgt
        end = hip + dn * dist
        D_thigh = frame(knee - hip, pole) @ frame(self.d0_thigh, self.pole).T
        D_calf = frame(end - knee, pole) @ frame(self.d0_calf, self.pole).T
        D_foot = rot(X, pitch_deg)
        pose.set_abs(self.thigh, D_thigh)
        pose.set_abs(self.calf, D_calf)
        pose.set_abs(self.foot, D_foot)
        pose.set_abs(self.ball, rot(X, toe_deg))
        return knee


# --------------------------------------------------------------------------------------
# the gaits
# --------------------------------------------------------------------------------------
def hermite(p0, p1, m0, m1, t):
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * p0 + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * p1 + (t3 - t2) * m1


def foot_at(leg: Leg, g: dict, u: float, y_strike: float):
    """The foot of a gait at its own phase u in [0, 1) (0 = its heel strike): (ankle, pitch_deg, toe_deg,
    planted, contact, on_ball). The ground under a planted foot moves backward (+Y) by CYCLE_M per cycle
    relative to the hips; y_strike is the heel contact's y at the strike. pitch_deg turns the foot about the
    giant's left-right axis (positive: toes down), toe_deg the toes in the world (0: flat on the ground);
    contact is the ground point the foot turns about (the heel, then the ball), on_ball which one."""
    duty = g["duty"]
    x = g["foot_x"] if leg.side == "l" else -g["foot_x"]
    heel = np.array([x, y_strike, 0.0])
    ball_off = leg.ball_c0 - leg.heel_c0
    ball_off[0] = 0.0
    a_heel = leg.ankle0 - leg.heel_c0      # the ankle from the heel contact
    a_ball = leg.ankle0 - leg.ball_c0      # the ankle from the ball contact
    a_heel[0] = a_ball[0] = 0.0

    def stance(uu):
        w = np.array([0.0, uu * CYCLE_M, 0.0])
        hr, ho = g["heel_rocker"] * duty, g["heel_off"] * duty
        if uu < hr:                                   # heel rocker: about the heel
            th = g["strike_deg"] * (1.0 - smooth(uu / hr))
            c = heel + w
            return c + rot(X, th) @ a_heel, th, th, c, False
        if uu < ho:                                   # flat
            c = heel + w
            return c + a_heel, 0.0, 0.0, c, False
        th = g["toe_off_deg"] * smooth((uu - ho) / max(1e-6, duty - ho))   # forefoot rocker: about the ball
        c = heel + ball_off + w
        return c + rot(X, th) @ a_ball, th, 0.0, c, True

    if u < duty:
        ankle, th, toe, c, on_ball = stance(u)
        return ankle, th, toe, True, c, on_ball
    v = (u - duty) / (1.0 - duty)
    a0, th0, _t0, _c0, _b0 = stance(duty - 1e-9)
    a1, th1, _t1, _c1, _b1 = stance(0.0)
    m = CYCLE_M * (1.0 - duty)                       # a planted foot's speed (backward), per unit of v
    y = hermite(a0[1], a1[1], m, m, v)
    peak = g["lift_peak"]
    lift = g["lift"] * (math.sin(math.pi * min(1.0, v / (2.0 * peak))) if v < peak else
                        math.sin(math.pi * (0.5 + 0.5 * (v - peak) / (1.0 - peak))))
    z = a0[2] + (a1[2] - a0[2]) * smooth(v) + lift
    xx = a0[0] + (a1[0] - a0[0]) * smooth(v)
    th = th0 + (th1 - th0) * smooth(v)
    toe = th * smooth(v / 0.3)                       # the toes leave the ground flat and straighten
    return np.array([xx, y, z]), th, toe, False, None, False


def gait_phase(phi, strike):
    return ((phi - strike) / (2.0 * math.pi)) % 1.0


class Gait:
    """A walk or a run: the pelvis's height curve fitted so both legs reach at every key."""

    def __init__(self, rest: Rest, name: str, frames: int):
        self.rest = rest
        self.name = name
        self.g = GAITS[name]
        self.frames = frames
        self.legs = {"l": Leg(rest, "l"), "r": Leg(rest, "r")}
        hip_y = rest.head["thigh_l"][1]
        # the heel contact at the strike: the stance sweep (duty x cycle) centred under the hip, a bias forward
        self.y_strike = hip_y - 0.5 * self.g["duty"] * CYCLE_M + self.legs["l"].heel_back - self.g["bias"]
        self.top = -self.g["top_drop"]
        self.amp = self.g["min_drop"]
        self._fit()

    def lowness(self, phi):
        """0..1: where the pelvis is lowest (the walk: each heel strike; the run: each mid-stance)."""
        ref = LEFT_STRIKE if self.name == "walk" else LEFT_STRIKE + self.g["duty"] * math.pi
        return math.cos(phi - ref) ** 2

    def pelvis(self, phi):
        g = self.g
        mid_l = LEFT_STRIKE + g["duty"] * math.pi           # the left foot's mid-stance
        sway = g["sway"] * math.cos(phi - mid_l)
        dz = self.top - self.amp * self.lowness(phi)
        yaw = -g["yaw_deg"] * math.sin(phi)                  # the left hip forward at the left strike
        roll = g["roll_deg"] * math.cos(phi - mid_l)         # the swing side's hip drops a little
        D = rot(Z, yaw) @ rot(Y, -roll) @ rot(X, g["pelvis_pitch_deg"])
        return np.array([sway, 0.0, dz]), D, yaw

    def feet(self, phi):
        out = {}
        for side, strike in (("l", LEFT_STRIKE), ("r", RIGHT_STRIKE)):
            out[side] = foot_at(self.legs[side], self.g, gait_phase(phi, strike), self.y_strike)
        return out

    def hips(self, phi):
        off, D, _yaw = self.pelvis(phi)
        r = self.rest
        p = r.head["pelvis"] + off
        return {s: p + D @ (r.head["thigh_" + s] - r.head["pelvis"]) for s in ("l", "r")}

    def _fit(self):
        """The least pelvis drop with which both legs reach every key: the smallest constant drop (in steps
        of 5 mm from the gait's own) for which some swing of the drop (bisected, at most MAX_SWING) fits."""
        def ok(top, amp):
            self.top, self.amp = top, amp
            for f in range(self.frames):
                phi = 2.0 * math.pi * f / self.frames
                hips = self.hips(phi)
                for s, (ankle, _th, _toe, _pl, _c, _ob) in self.feet(phi).items():
                    if np.linalg.norm(ankle - hips[s]) > self.legs[s].reach():
                        return False
            return True
        top = -self.g["top_drop"]
        for _step in range(120):
            lo, hi = self.g["min_drop"], MAX_SWING
            if ok(top, hi):
                if not ok(top, lo):
                    for _i in range(40):
                        mid = 0.5 * (lo + hi)
                        if ok(top, mid):
                            hi = mid
                        else:
                            lo = mid
                    lo = hi + 0.004
                self.top, self.amp = top, lo
                return
            top -= 0.005
        raise SystemExit("clips: the %s cannot reach its feet" % self.name)

    def pose(self, phi) -> Pose:
        g = self.g
        r = self.rest
        pose = Pose(r)
        off, D_pelvis, yaw = self.pelvis(phi)
        pose.offset = off
        pose.set_rel("pelvis", D_pelvis)
        pose.solve()
        feet = self.feet(phi)
        for s in ("l", "r"):
            ankle, th, toe, _planted, _c, _ob = feet[s]
            self.legs[s].place(pose, pose.P["thigh_" + s], ankle, th, toe, rot(Z, yaw))
        # the spine counter-turns (the shoulders against the hips) and leans
        shoulder_yaw = -yaw * g["shoulder_counter"]
        lean = g["lean_deg"] - g["pelvis_pitch_deg"]
        for b in ("spine_01", "spine_02", "spine_03"):
            pose.set_rel(b, rot(Z, (shoulder_yaw - yaw) / 3.0) @ rot(X, lean / 3.0))
        pose.set_rel("neck_01", rot(Z, -shoulder_yaw * 0.5) @ rot(X, -g["lean_deg"] * 0.4))
        pose.set_rel("head", rot(Z, -shoulder_yaw * 0.4) @ rot(X, -g["lean_deg"] * 0.3))
        # arms against the legs: the left arm forward with the right leg (the right strike, 3 pi / 2)
        sw = g["arm_swing_deg"] * math.sin(phi)
        el = g["elbow_swing_deg"]
        pose.ops(arm_spec("l", sw, g["elbow_deg"] + el * max(0.0, -math.sin(phi))))
        pose.ops(arm_spec("r", -sw, g["elbow_deg"] + el * max(0.0, math.sin(phi))))
        relaxed_hands(pose, 0.32)
        return pose


def relaxed_hands(pose, curl, thumb=None):
    t = curl * 0.8 if thumb is None else thumb
    for s in ("l", "r"):
        pose.ops(hand_spec(pose.rest, s, curl, t))


def stand_legs(pose, drop=0.025, back=0.0):
    """Both feet planted where they stand at rest, the pelvis lowered by `drop` (the knees soft) and moved
    back by `back` (the idle's and the death's legs)."""
    r = pose.rest
    pose.offset = pose.offset + np.array([0.0, back, -drop])
    pose.solve()
    for s in ("l", "r"):
        leg = Leg(r, s)
        leg.place(pose, pose.P["thigh_" + s], leg.ankle0.copy(), 0.0, 0.0)


# --------------------------------------------------------------------------------------
# the clips
# --------------------------------------------------------------------------------------
def idle_pose(rest, f, frames):
    ph = 2.0 * math.pi * f / frames
    breath = math.sin(ph)
    pose = Pose(rest)
    pose.offset = np.array([0.006 * math.sin(ph), 0.0, -0.004 * (1.0 + breath)])
    pose.set_rel("spine_02", rot(X, -1.2 * breath))
    pose.set_rel("spine_03", rot(X, -0.9 * breath))
    pose.set_rel("neck_01", rot(X, 1.2 * breath))
    pose.set_rel("clavicle_l", rot(Y, -1.0 * breath))
    pose.set_rel("clavicle_r", rot(Y, 1.0 * breath))
    stand_legs(pose)
    pose.ops(arm_spec("l", 1.5 * breath, 16.0))
    pose.ops(arm_spec("r", -1.5 * breath, 16.0))
    relaxed_hands(pose, 0.32)
    return pose


def airborne_pose(rest, f, frames):
    pose = Pose(rest)
    pose.set_rel("pelvis", rot(X, 6.0))
    pose.set_rel("spine_02", rot(X, 3.0))
    pose.set_rel("thigh_l", rot(X, -48.0))
    pose.set_rel("calf_l", rot(X, 72.0))
    pose.set_rel("foot_l", rot(X, 22.0))
    pose.set_rel("thigh_r", rot(X, -18.0))
    pose.set_rel("calf_r", rot(X, 58.0))
    pose.set_rel("foot_r", rot(X, 28.0))
    pose.ops(arm_spec("l", -12.0, 30.0, out_deg=22.0))
    pose.ops(arm_spec("r", 8.0, 30.0, out_deg=22.0))
    relaxed_hands(pose, 0.4)
    return pose


def death_pose(rest, f, frames):
    t = f / float(frames)
    e = smooth(t)
    knees = smooth(min(1.0, t * 1.4))       # the knees go first, the torso follows
    pose = Pose(rest)
    pose.set_rel("pelvis", rot(X, 14.0 * e))
    for b, deg in (("spine_01", 10.0), ("spine_02", 12.0), ("spine_03", 12.0)):
        pose.set_rel(b, rot(X, deg * e))
    pose.set_rel("neck_01", rot(X, 14.0 * e))
    pose.set_rel("head", rot(X, 18.0 * e) @ rot(Y, 6.0 * e))
    stand_legs(pose, drop=0.025 + 0.72 * knees, back=0.16 * knees)
    pose.ops(arm_spec("l", -10.0 * e, 16.0 + 14.0 * e, out_deg=8.0 + 6.0 * e))
    pose.ops(arm_spec("r", -14.0 * e, 16.0 + 18.0 * e, out_deg=8.0 + 4.0 * e))
    relaxed_hands(pose, 0.32 + 0.12 * e)
    return pose


def hand_pose(rest, side, curl, thumb, spread=0.0):
    pose = Pose(rest)
    pose.ops(hand_spec(rest, side, curl, thumb, spread))
    return pose


def clip_bones(rest, name):
    """The bones a clip keys: the finger poses only their hand's fingers; the others every bone but Root."""
    if name in ("grip_r", "grip_l", "open_r", "open_l"):
        s = "_" + name[-1]
        return [b for b in rest.order if b.endswith(s) and b.startswith(FINGERS + ("thumb",))]
    return [b for b in rest.order if b != "Root"]


def make_poses(rest):
    walk = Gait(rest, "walk", CLIP_FRAMES["walk"])
    run = Gait(rest, "run", CLIP_FRAMES["run"])
    poses = {}
    for name, frames in CLIP_FRAMES.items():
        keys = []
        for f in range(frames + 1):
            if name == "idle":
                p = idle_pose(rest, f, frames)
            elif name in ("walk", "run"):
                p = (walk if name == "walk" else run).pose(2.0 * math.pi * f / frames)
            elif name == "airborne":
                p = airborne_pose(rest, f, frames)
            elif name == "death":
                p = death_pose(rest, f, frames)
            elif name.startswith("grip_"):
                p = hand_pose(rest, name[-1], 0.86, 0.9)
            else:
                p = hand_pose(rest, name[-1], 0.08, 0.1, 5.0)
            keys.append(p.solve())
        poses[name] = keys
    return poses, {"walk": walk, "run": run}


# --------------------------------------------------------------------------------------
# measuring the gaits on the posed skeleton
# --------------------------------------------------------------------------------------
def measure_gait(gait: Gait, samples=256):
    """The stride per cycle, the largest slide and lift of a planted foot's ground point, and the pelvis drop,
    measured on the solved poses (the same deltas the keys hold): the left foot over its stance. The ground
    point is the posed heel (the ball in the forefoot rocker, moved back by the foot's heel-to-ball offset
    so the two read as one point); planted, it must move backward relative to the hips along a straight
    line, CYCLE_M per cycle."""
    leg = gait.legs["l"]
    ball_off = leg.ball_c0 - leg.heel_c0
    ball_off[0] = 0.0
    us, ys, zs, err = [], [], [], 0.0
    for i in range(samples):
        phi = 2.0 * math.pi * i / samples
        u = gait_phase(phi, LEFT_STRIKE)
        _a, _th, _toe, planted, c, on_ball = foot_at(leg, gait.g, u, gait.y_strike)
        if not planted:
            continue
        pose = gait.pose(phi).solve()
        ref = (leg.ball_c0 if on_ball else leg.heel_c0) - leg.ankle0
        ref[0] = 0.0
        ground = pose.P[leg.foot] + pose.D[leg.foot] @ ref
        err = max(err, float(np.linalg.norm(ground - c)))
        heel = ground - (ball_off if on_ball else 0.0)
        us.append(u)
        ys.append(heel[1])
        zs.append(ground[2])
    k = np.polyfit(np.array(us), np.array(ys), 1)
    stride = float(k[0])
    slide = float(np.max(np.abs(np.array(ys) - np.polyval(k, np.array(us)))))
    return {"stride_m": r6(stride), "stride_error": r6(stride / CYCLE_M - 1.0), "slide_m": r6(slide),
            "contact_error_m": r6(err), "ground_lift_m": r6(float(np.max(np.abs(zs)))),
            "pelvis_drop_m": r6(gait.amp - gait.top), "duty": gait.g["duty"], "keys": gait.frames + 1}


# --------------------------------------------------------------------------------------
# Blender: keys, the anchor mesh, the export
# --------------------------------------------------------------------------------------
def anchor_mesh(rig, rest, coll):
    """A tiny triangle at every bone's head, 100 % on that bone: a skin, so the importer builds a
    Skeleton3D and the tracks address its bones (the animation library keeps the clips only)."""
    verts, faces = [], []
    names = [b for b in rest.order]
    for i, b in enumerate(names):
        h = rest.head[b]
        verts += [tuple(h), tuple(h + np.array([0.004, 0.0, 0.0])), tuple(h + np.array([0.0, 0.0, 0.004]))]
        faces.append((3 * i, 3 * i + 1, 3 * i + 2))
    me = bpy.data.meshes.new("ClipsAnchor")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("ClipsAnchor", me)
    coll.objects.link(ob)
    for i, b in enumerate(names):
        vg = ob.vertex_groups.new(name=b)
        vg.add([3 * i, 3 * i + 1, 3 * i + 2], 1.0, "REPLACE")
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    return ob


def key_clip(rig, rest, name, keys):
    act = bpy.data.actions.new(name)
    rig.animation_data_create()
    rig.animation_data.action = act
    bones = clip_bones(rest, name)
    for f, pose in enumerate(keys):
        for pb in rig.pose.bones:
            pb.rotation_quaternion = Quaternion()
            pb.location = (0.0, 0.0, 0.0)
        for b in bones:
            pb = rig.pose.bones[b]
            pb.rotation_quaternion = pose.basis(b)
            pb.keyframe_insert("rotation_quaternion", frame=f)
            if b == "pelvis":
                pb.location = pose.pelvis_location()
                pb.keyframe_insert("location", frame=f)
    act.use_fake_user = True
    track = rig.animation_data.nla_tracks.new()
    track.name = name
    track.strips.new(name, 0, act)
    rig.animation_data.action = None
    return act


def check_against_blender(rig, rest, pose, bones=("foot_l", "hand_r", "head", "calf_r")):
    """The heads Blender computes from the keyed quaternions equal the solved ones (the conversion is right)."""
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)
    for b in rest.order:
        if b == "Root":
            continue
        rig.pose.bones[b].rotation_quaternion = pose.basis(b)
    rig.pose.bones["pelvis"].location = pose.pelvis_location()
    bpy.context.view_layer.update()
    worst = 0.0
    for b in bones:
        got = np.array(rig.pose.bones[b].head[:])
        worst = max(worst, float(np.linalg.norm(got - pose.P[b])))
    return worst


def run(out_dir, work_dir):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.fps = FPS
    objs = gb.build_giant({"height_m": H, "name": "Giant"})
    rig, coll = objs["rig"], objs["collection"]
    bpy.data.objects.remove(objs["body"], do_unlink=True)
    rest = Rest(rig)
    poses, gaits = make_poses(rest)
    worst = max(check_against_blender(rig, rest, poses[n][k]) for n, k in (("walk", 5), ("run", 11), ("death", 30),
                                                                             ("idle", 13)))
    if worst > 1e-4:
        raise SystemExit("clips: the keyed rotations do not reproduce the solved pose (%.6f m off)" % worst)
    anchor = anchor_mesh(rig, rest, coll)
    for name in CLIP_FRAMES:
        key_clip(rig, rest, name, poses[name])
    for pb in rig.pose.bones:
        pb.rotation_quaternion = Quaternion()
        pb.location = (0.0, 0.0, 0.0)
    bpy.context.view_layer.update()
    for o in bpy.data.objects:
        o.select_set(False)
    rig.select_set(True)
    anchor.select_set(True)
    bpy.context.view_layer.objects.active = rig
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, GLB_NAME)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False, export_reset_pose_bones=True,
                              export_morph=False, export_materials="NONE", export_yup=True,
                              export_def_bones=False, export_leaf_bone=False, export_extras=False,
                              export_cameras=False, export_lights=False, export_rest_position_armature=True)
    info = {"fps": FPS, "step_m": STEP_M, "cycle_m": CYCLE_M, "left_strike_phase": r6(LEFT_STRIKE),
            "clips": {n: {"frames": f, "length_s": r6(f / float(FPS)), "loop": n in LOOPS,
                          "bones": len(clip_bones(rest, n))} for n, f in CLIP_FRAMES.items()},
            "gaits": {n: measure_gait(g) for n, g in sorted(gaits.items())},
            "conversion_error_m": r6(worst)}
    for n, m in info["gaits"].items():
        log("%s: stride %.4f m per cycle (%+.2f %%), slide %.4f m, pelvis drop %.3f m" % (
            n, m["stride_m"], 100.0 * m["stride_error"], m["slide_m"], m["pelvis_drop_m"]))
    if work_dir:
        os.makedirs(work_dir, exist_ok=True)
        with open(os.path.join(work_dir, INFO_NAME), "w", encoding="utf-8") as fh:
            json.dump(info, fh, indent=1, sort_keys=True)
    log("wrote %s (%d bytes) in %.1f s" % (path, os.path.getsize(path), time.time() - t0))
    return info


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else os.getcwd(), sys.argv[2] if len(sys.argv) > 2 else "")
