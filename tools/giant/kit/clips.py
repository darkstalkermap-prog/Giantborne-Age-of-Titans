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

The clips II (P48, plan M11 §2.3), all computed the same way:

  sprint     the run's cycle with a shorter stance, a longer flight, a deeper lean and pumping arms (the
             stride a cycle stays the brain's 3.2 m, so the game seeks it on the same walk phase)
  turn_l, turn_r   a 90 degree turn on the spot in two steps, keyed on the yaw travelled (clip time =
             yaw / 90 degrees): the inside foot steps round first, then the outside one; a planted foot
             stays where it stands in the world while the body turns over it
  stomp_r    the right foot lifted, held and planted where it stood, the hips over it (the game seeks it
             by the action's phase fraction)
  land       0.27 s: the knees take a landing and straighten
  brace      the block's stance: the left foot forward, the knees bent, the weight low
  roar       the legs set wide, the chest out, the head back
  flinch_f, flinch_b, flinch_l, flinch_r   0.3 s, the spine, neck, head and clavicles only, as offsets
             from the rest pose that start and end at nothing (played additively); named by the side
             the giant is hit on
  grip_club, grip_sword, grip_hammer, grip_axe, grip_fist, grip_tree   one-frame finger poses per weapon
             family, both hands
  carry_two_hand   both arms and hands: the off hand on a two-handed weapon carried at rest
  fp_rest    both arms: the first-person rest, the weapon hand raised into the lower right of the view

Every clip but the full-body ones is written with the tracks of its own bones only (``clip_bones``;
``strip_tracks`` removes the others from the glTF, which Blender's exporter samples for every bone).

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


def configure(step_m=1.6):
    """The proportions parameter (P59, plan M11 §2.8): the people's clips are computed on a human body built at the
    stage-1 height, where every length here applies as it is, with the step their rig's stride makes at that height
    (the soldier's 0.9 m at 1.8 m: 1.8288 m). The giant's pipeline never calls it (his STEP_M stays 1.6)."""
    global STEP_M, CYCLE_M
    STEP_M = float(step_m)
    CYCLE_M = 2.0 * STEP_M


FINGERS = ("index", "middle", "ring", "pinky")
LEG_BONES = ("thigh", "calf", "foot", "ball")

# The clips and their key counts (frames + 1 keys; the last key of a loop equals its first).
CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "airborne": 1, "death": 30,
               "grip_r": 1, "grip_l": 1, "open_r": 1, "open_l": 1}
M10_CLIPS = tuple(CLIP_FRAMES)
# The clips II (P48): appended, so M10's nine are computed and keyed exactly as they were.
CLIP_FRAMES.update({"sprint": 32, "turn_l": 24, "turn_r": 24, "stomp_r": 30, "land": 8, "brace": 1, "roar": 24,
                    "flinch_f": 9, "flinch_b": 9, "flinch_l": 9, "flinch_r": 9,
                    "grip_club": 1, "grip_sword": 1, "grip_hammer": 1, "grip_axe": 1, "grip_fist": 1, "grip_tree": 1,
                    "carry_two_hand": 1, "fp_rest": 1})
LOOPS = ("idle", "walk", "run", "sprint")
HAND_CLIPS = ("grip_r", "grip_l", "open_r", "open_l")
# The weapon families' grips: (finger curl, thumb curl, spread in degrees). A thin handle closes the fist
# further than a thick one; a tree's trunk is held with an open hand.
GRIPS = {"grip_club": (0.80, 0.85, 0.0), "grip_sword": (0.93, 1.0, 0.0), "grip_hammer": (0.85, 0.9, 0.0),
         "grip_axe": (0.89, 0.95, 0.0), "grip_fist": (1.0, 0.72, 0.0), "grip_tree": (0.52, 0.45, 4.0)}
UPPER_BODY = ("spine_01", "spine_02", "spine_03", "neck_01", "head", "clavicle_l", "clavicle_r")
ARM_BONES = ("clavicle", "upperarm", "lowerarm", "hand")
TURN_DEG = 90.0                   # a turn clip's whole yaw
TURN_STEP = ((0.04, 0.50), (0.50, 0.96))    # the inside foot's step and the outside foot's, in clip fraction
# The stomp's beats in the action's phase fraction: the foot is up by LIFT, held to HOLD, down at PLANT.
STOMP_LIFT, STOMP_HOLD, STOMP_PLANT = 0.34, 0.58, 0.72

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
    # P48: the sprint. The cycle is the brain's (two steps of STEP_M), so "a longer stride" is a longer
    # flight: the foot is planted for less of the cycle and swings further and higher.
    "sprint": {"duty": 0.29, "foot_x": 0.20, "lift": 0.80, "lift_peak": 0.36, "strike_deg": -4.0, "toe_off_deg": 46.0,
               "heel_rocker": 0.08, "heel_off": 0.40, "bias": 0.08, "top_drop": 0.12, "min_drop": 0.16,
               "sway": 0.015, "yaw_deg": 9.0, "roll_deg": 3.5, "pelvis_pitch_deg": 10.0, "lean_deg": 17.0,
               "arm_swing_deg": 50.0, "elbow_deg": 92.0, "elbow_swing_deg": 12.0, "shoulder_counter": 1.3},
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


def set_arm(pose, side, swing_deg=0.0, elbow_deg=15.0, out_deg=8.0, forward_deg=4.0, raise_deg=0.0):
    """The arm hanging relaxed from the A-pose rest (relative to the clavicle): the upper arm onto a line
    out_deg outward from straight down (forward_deg in front), swung about the giant's left-right axis by
    swing_deg (negative: forward) and raised sideways by raise_deg; the forearm bent forward by elbow_deg
    from the upper arm's line (the rest's own 44 degree bend undone: the forearm is aimed, not added to);
    the hand straight on the forearm."""
    r = pose.rest
    s = "_" + side
    out = 1.0 if side == "l" else -1.0
    o, fw = math.radians(out_deg), math.radians(forward_deg)
    hang = np.array([out * math.sin(o), -math.sin(fw), -math.cos(o) * math.cos(fw)])
    R = rot(X, swing_deg)
    if raise_deg:
        R = R @ rot(Y, -raise_deg * out)
    d_up = r.direction("upperarm" + s)
    D_up = R @ between(d_up, hang)
    up_now = D_up @ d_up
    fore_want = R @ rot(X, -elbow_deg) @ hang         # bent forward about the left-right axis
    d_lo = r.direction("lowerarm" + s)
    D_lo = between(D_up @ d_lo, fore_want) @ D_up
    pose.set_rel("upperarm" + s, D_up)
    pose.set_rel("lowerarm" + s, D_up.T @ D_lo)
    return up_now


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
        set_arm(pose, "l", sw, g["elbow_deg"] + el * max(0.0, -math.sin(phi)))
        set_arm(pose, "r", -sw, g["elbow_deg"] + el * max(0.0, math.sin(phi)))
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
    set_arm(pose, "l", 1.5 * breath, 14.0)
    set_arm(pose, "r", -1.5 * breath, 14.0)
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
    set_arm(pose, "l", -12.0, 30.0, out_deg=22.0)
    set_arm(pose, "r", 8.0, 30.0, out_deg=22.0)
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
    set_arm(pose, "l", -10.0 * e, 14.0 + 14.0 * e, out_deg=8.0 + 6.0 * e)
    set_arm(pose, "r", -14.0 * e, 14.0 + 18.0 * e, out_deg=8.0 + 4.0 * e)
    relaxed_hands(pose, 0.32 + 0.12 * e)
    return pose


def hand_pose(rest, side, curl, thumb, spread=0.0):
    pose = Pose(rest)
    pose.ops(hand_spec(rest, side, curl, thumb, spread))
    return pose


def clip_bones(rest, name):
    """The bones a clip keys: the finger poses only their fingers, the flinches the upper body, the arm
    rests the arms; the others every bone but Root."""
    fingers = FINGERS + ("thumb",)
    if name in HAND_CLIPS:
        s = "_" + name[-1]
        return [b for b in rest.order if b.endswith(s) and b.startswith(fingers)]
    if name in GRIPS:
        return [b for b in rest.order if b.startswith(fingers)]
    if name.startswith("flinch_"):
        return [b for b in rest.order if b in UPPER_BODY]
    if name == "carry_two_hand":
        return [b for b in rest.order if b.startswith(ARM_BONES + fingers)]
    if name == "fp_rest":
        return [b for b in rest.order if b.startswith(ARM_BONES)]
    return [b for b in rest.order if b != "Root"]


def is_partial(name):
    """True for a clip written with the tracks of its own bones only."""
    return name in HAND_CLIPS or name in GRIPS or name.startswith("flinch_") or name in ("carry_two_hand", "fp_rest")


# --------------------------------------------------------------------------------------
# the clips II (P48)
# --------------------------------------------------------------------------------------
def set_legs(pose, feet, drop=0.025):
    """Both legs by their feet: {side: (ankle, yaw_deg, pitch_deg, toe_deg)} in armature space. The pelvis
    (its rotation and offset already set) is lowered by ``drop``, and further by the millimetre until both
    legs reach. Returns the drop used."""
    r = pose.rest
    base = pose.offset.copy()
    legs = {s: Leg(r, s) for s in feet}
    d = drop
    while True:
        pose.offset = base + np.array([0.0, 0.0, -d])
        pose.solve()
        if d > 1.5 or all(np.linalg.norm(np.asarray(feet[s][0]) - pose.P["thigh_" + s]) <= legs[s].reach() for s in feet):
            break
        d += 0.001
    for s, (ankle, yaw, pitch, toe) in feet.items():
        legs[s].place(pose, pose.P["thigh_" + s], np.asarray(ankle, np.float64), pitch, toe, rot(Z, 0.5 * yaw))
        if yaw:
            pose.set_abs(legs[s].foot, rot(Z, yaw) @ rot(X, pitch))
            pose.set_abs(legs[s].ball, rot(Z, yaw) @ rot(X, toe))
    return d


def rest_ankle(rest, side):
    return rest.head["foot_" + side].copy()


def turn_feet(rest, u, sign):
    """A turn's feet at clip fraction u, in the turning body's own frame: {side: (ankle, yaw_deg, lift
    fraction 0..1, planted)}; ``sign`` +1 turns to the giant's left. In the world a foot stands still until
    its step, swings round the body's axis by the whole turn, and stands again; the body has turned
    TURN_DEG x u, so in its frame a standing foot moves the other way."""
    body = TURN_DEG * u * sign
    inside, outside = ("l", "r") if sign > 0 else ("r", "l")
    out = {}
    for side, (t0, t1) in ((inside, TURN_STEP[0]), (outside, TURN_STEP[1])):
        v = min(1.0, max(0.0, (u - t0) / (t1 - t0)))
        world = TURN_DEG * sign * smooth(v)
        p = rot(Z, world) @ rest_ankle(rest, side)
        lift = math.sin(math.pi * v) if 0.0 < v < 1.0 else 0.0
        a = rot(Z, -body) @ p
        out[side] = (a, world - body, lift, not (0.0 < v < 1.0))
    return out


def turn_pose(rest, f, frames, sign):
    u = f / float(frames)
    pose = Pose(rest)
    feet = turn_feet(rest, u, sign)
    swing = math.sin(math.pi * u)
    # the weight over the standing foot: toward the outside foot in the first step, the inside in the second
    stance = [s for s in ("l", "r") if feet[s][3]]
    lean = np.zeros(3)
    if len(stance) == 1:
        a = feet[stance[0]][0]
        lean = np.array([a[0], a[1], 0.0]) * 0.16 * max(feet["l"][2], feet["r"][2])
    pose.offset = lean
    pose.set_rel("pelvis", rot(Z, -3.0 * sign * math.sin(2.0 * math.pi * u)))
    for b in ("spine_01", "spine_02", "spine_03"):
        pose.set_rel(b, rot(Z, 3.0 * sign * swing))            # the shoulders lead the hips into the turn
    pose.set_rel("neck_01", rot(Z, 4.0 * sign * swing))
    pose.set_rel("head", rot(Z, 6.0 * sign * swing))
    set_legs(pose, {s: (feet[s][0] + np.array([0.0, 0.0, 0.16 * feet[s][2]]), feet[s][1], 10.0 * feet[s][2], 0.0)
                    for s in ("l", "r")}, drop=0.025 + 0.035 * swing)
    set_arm(pose, "l", 4.0 * sign * swing, 14.0 + 6.0 * swing)
    set_arm(pose, "r", -4.0 * sign * swing, 14.0 + 6.0 * swing)
    relaxed_hands(pose, 0.32)
    return pose


def stomp_pose(rest, f, frames):
    t = f / float(frames)
    up = smooth(t / STOMP_LIFT) if t < STOMP_HOLD else 1.0 - smooth((t - STOMP_HOLD) / (STOMP_PLANT - STOMP_HOLD))
    up = max(0.0, up)
    hit = smooth((t - STOMP_HOLD) / (STOMP_PLANT - STOMP_HOLD)) if t > STOMP_HOLD else 0.0
    settle = smooth((t - STOMP_PLANT) / (1.0 - STOMP_PLANT)) if t > STOMP_PLANT else 0.0
    sink = hit * (1.0 - settle)                 # the knees take the plant, then straighten
    pose = Pose(rest)
    # over the standing (left) leg while the foot is up, over the stomping foot as it lands
    pose.offset = np.array([0.10 * up - 0.10 * sink, -0.02 * sink, 0.0])
    pose.set_rel("pelvis", rot(Y, 4.0 * up) @ rot(X, -3.0 * up + 6.0 * sink))
    for b in ("spine_01", "spine_02", "spine_03"):
        pose.set_rel(b, rot(X, -2.0 * up + 5.0 * sink) @ rot(Y, -1.5 * up))
    pose.set_rel("neck_01", rot(X, 4.0 * up - 4.0 * sink))
    pose.set_rel("head", rot(X, 6.0 * up - 6.0 * sink))
    a_r = rest_ankle(rest, "r") + np.array([0.0, -0.26 * up, 0.86 * up])
    set_legs(pose, {"l": (rest_ankle(rest, "l"), 0.0, 0.0, 0.0), "r": (a_r, 0.0, 24.0 * up, 0.0)},
             drop=0.025 + 0.02 * up + 0.16 * sink)
    set_arm(pose, "l", 6.0 * up - 8.0 * sink, 16.0 + 14.0 * up, out_deg=8.0 + 14.0 * up)
    set_arm(pose, "r", -8.0 * up + 6.0 * sink, 16.0 + 20.0 * up, out_deg=8.0 + 10.0 * up)
    relaxed_hands(pose, 0.36 + 0.3 * up)
    return pose


def land_pose(rest, f, frames):
    t = f / float(frames)
    deep = 0.45 + 0.55 * smooth(t / 0.3) if t < 0.3 else 1.0 - smooth((t - 0.3) / 0.7)
    pose = Pose(rest)
    pose.offset = np.array([0.0, 0.05 * deep, 0.0])
    pose.set_rel("pelvis", rot(X, 12.0 * deep))
    for b, deg in (("spine_01", 5.0), ("spine_02", 6.0), ("spine_03", 5.0)):
        pose.set_rel(b, rot(X, deg * deep))
    pose.set_rel("neck_01", rot(X, -6.0 * deep))
    pose.set_rel("head", rot(X, -8.0 * deep))
    set_legs(pose, {s: (rest_ankle(rest, s), 0.0, 0.0, 0.0) for s in ("l", "r")}, drop=0.025 + 0.40 * deep)
    set_arm(pose, "l", -14.0 * deep, 14.0 + 30.0 * deep, out_deg=8.0 + 16.0 * deep)
    set_arm(pose, "r", -14.0 * deep, 14.0 + 30.0 * deep, out_deg=8.0 + 16.0 * deep)
    relaxed_hands(pose, 0.32 + 0.1 * deep)
    return pose


def brace_pose(rest, f, frames):
    pose = Pose(rest)
    pose.offset = np.array([0.0, -0.02, 0.0])
    pose.set_rel("pelvis", rot(Z, -8.0) @ rot(X, 6.0))             # the left hip forward, the weight low
    for b in ("spine_01", "spine_02", "spine_03"):
        pose.set_rel(b, rot(Z, 3.0) @ rot(X, 3.0))
    pose.set_rel("neck_01", rot(Z, 4.0) @ rot(X, -4.0))
    pose.set_rel("head", rot(X, -4.0))
    a_l = rest_ankle(rest, "l") + np.array([0.02, -0.30, 0.0])
    a_r = rest_ankle(rest, "r") + np.array([-0.06, 0.26, 0.0])
    set_legs(pose, {"l": (a_l, 6.0, 0.0, 0.0), "r": (a_r, -28.0, 0.0, 0.0)}, drop=0.17)
    set_arm(pose, "l", -10.0, 40.0, out_deg=14.0)
    set_arm(pose, "r", 6.0, 30.0, out_deg=12.0)
    relaxed_hands(pose, 0.5)
    return pose


def roar_pose(rest, f, frames):
    t = f / float(frames)
    e = smooth(t / 0.3) * (1.0 - 0.5 * smooth((t - 0.82) / 0.18))
    step = math.sin(math.pi * min(1.0, t / 0.3)) if t < 0.3 else 0.0          # the feet lift as they move apart
    pose = Pose(rest)
    pose.offset = np.array([0.0, -0.03 * e, 0.0])
    pose.set_rel("pelvis", rot(X, 5.0 * e))
    for b, deg in (("spine_01", -5.0), ("spine_02", -8.0), ("spine_03", -8.0)):   # arched back: the chest out
        pose.set_rel(b, rot(X, deg * e))
    pose.set_rel("clavicle_l", rot(Z, -8.0 * e))
    pose.set_rel("clavicle_r", rot(Z, 8.0 * e))
    pose.set_rel("neck_01", rot(X, -6.0 * e))
    pose.set_rel("head", rot(X, -14.0 * e))
    feet = {}
    for s, out in (("l", 1.0), ("r", -1.0)):
        a = rest_ankle(rest, s) + np.array([out * 0.20 * e, 0.0, 0.05 * step])
        feet[s] = (a, out * 12.0 * e, 0.0, 0.0)
    set_legs(pose, feet, drop=0.025 + 0.11 * e)
    set_arm(pose, "l", 14.0 * e, 14.0 + 36.0 * e, out_deg=8.0 + 26.0 * e)
    set_arm(pose, "r", 14.0 * e, 14.0 + 36.0 * e, out_deg=8.0 + 26.0 * e)
    relaxed_hands(pose, 0.32 + 0.5 * e)
    return pose


# The flinches: the upper body's offsets at the peak (degrees about the giant's axes: X pitches the torso
# forward, Y rolls it toward his left, Z turns it to his right), per bone as a share of the whole. Each throws the
# torso away from the side it is named by (Gate A2: the side ones leaned into the hit - the game measured the head
# moving toward the attacker - so their signs are swapped; the comment had Y's and Z's senses the wrong way round).
FLINCH = {"flinch_f": (-13.0, 0.0, 0.0), "flinch_b": (15.0, 0.0, 0.0), "flinch_l": (2.0, -11.0, 5.0),
          "flinch_r": (2.0, 11.0, -5.0)}
FLINCH_SHARE = {"spine_01": 0.2, "spine_02": 0.3, "spine_03": 0.3, "neck_01": 0.35, "head": 0.5}
FLINCH_PEAK = 0.3                 # the share of the clip at which the offset is whole


def flinch_pose(rest, name, f, frames):
    t = f / float(frames)
    e = smooth(t / FLINCH_PEAK) if t < FLINCH_PEAK else 1.0 - smooth((t - FLINCH_PEAK) / (1.0 - FLINCH_PEAK))
    px, ry, tz = FLINCH[name]
    pose = Pose(rest)
    for b, share in FLINCH_SHARE.items():
        # the head lags the torso: it turns the other way first, as the torso is thrown under it
        k = share * e if b not in ("neck_01", "head") else -share * e * 0.6
        pose.set_rel(b, rot(Z, tz * k) @ rot(Y, ry * k) @ rot(X, px * k))
    shrug = 5.0 * e
    pose.set_rel("clavicle_l", rot(Y, -shrug))
    pose.set_rel("clavicle_r", rot(Y, shrug))
    return pose


def grip_pose(rest, name):
    curl, thumb, spread = GRIPS[name]
    pose = Pose(rest)
    for s in ("l", "r"):
        pose.ops(hand_spec(rest, s, curl, thumb, spread))
    return pose


def carry_pose(rest):
    """Both hands on a long handle carried across the front of the hips: the right hand low at the right
    hip, the left a hand's breadth further along it."""
    pose = Pose(rest)
    pose.set_rel("clavicle_l", rot(Z, -6.0))
    pose.set_rel("clavicle_r", rot(Z, 6.0))
    set_arm(pose, "r", -8.0, 44.0, out_deg=4.0, forward_deg=6.0)
    set_arm(pose, "l", -16.0, 62.0, out_deg=-6.0, forward_deg=12.0)
    for s in ("l", "r"):
        pose.ops(hand_spec(rest, s, 0.84, 0.9))
    return pose


def twist_forearm(pose, side, deg):
    """Turns the forearm (and the hand on it) about its own posed line by deg (positive: right-handed about the
    elbow-to-wrist direction), so what the fist holds turns about the forearm."""
    s = "_" + side
    pose.solve()
    d_up = pose.D["upperarm" + s]
    f = pose.D["lowerarm" + s] @ pose.rest.direction("lowerarm" + s)
    pose.set_rel("lowerarm" + s, d_up.T @ rot(f, deg) @ d_up)


FP_REST_R = (-24.0, 82.0, 10.0, 6.0, 75.0)


def fp_rest_pose(rest):
    """The first-person rest: the weapon arm forward of the body with the forearm raised, so the fist and
    what it holds sit in the lower right of the view; the off arm a little forward and bent."""
    pose = Pose(rest)
    sw, el, out, fw, tw = FP_REST_R
    set_arm(pose, "r", sw, el, out_deg=out, forward_deg=fw)
    if tw:
        twist_forearm(pose, "r", tw)
    set_arm(pose, "l", -10.0, 46.0, out_deg=12.0, forward_deg=4.0)
    return pose


def make_poses(rest):
    walk = Gait(rest, "walk", CLIP_FRAMES["walk"])
    run = Gait(rest, "run", CLIP_FRAMES["run"])
    sprint = Gait(rest, "sprint", CLIP_FRAMES["sprint"])
    gaits = {"walk": walk, "run": run, "sprint": sprint}
    poses = {}
    for name, frames in CLIP_FRAMES.items():
        keys = []
        for f in range(frames + 1):
            if name == "idle":
                p = idle_pose(rest, f, frames)
            elif name in gaits:
                p = gaits[name].pose(2.0 * math.pi * f / frames)
            elif name in ("turn_l", "turn_r"):
                p = turn_pose(rest, f, frames, 1.0 if name == "turn_l" else -1.0)
            elif name == "stomp_r":
                p = stomp_pose(rest, f, frames)
            elif name == "land":
                p = land_pose(rest, f, frames)
            elif name == "brace":
                p = brace_pose(rest, f, frames)
            elif name == "roar":
                p = roar_pose(rest, f, frames)
            elif name in FLINCH:
                p = flinch_pose(rest, name, f, frames)
            elif name in GRIPS:
                p = grip_pose(rest, name)
            elif name == "carry_two_hand":
                p = carry_pose(rest)
            elif name == "fp_rest":
                p = fp_rest_pose(rest)
            elif name == "airborne":
                p = airborne_pose(rest, f, frames)
            elif name == "death":
                p = death_pose(rest, f, frames)
            elif name in ("grip_r", "grip_l"):
                p = hand_pose(rest, name[-1], 0.86, 0.9)
            else:
                p = hand_pose(rest, name[-1], 0.08, 0.1, 5.0)
            keys.append(p.solve())
        poses[name] = keys
    return poses, gaits


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


def _yaw_of(D):
    """The yaw (degrees, positive to the giant's left) a delta turns his forward axis by."""
    v = np.asarray(D) @ np.array([0.0, -1.0, 0.0])
    return math.degrees(math.atan2(v[0], -v[1]))


def _angle_of(D):
    return math.degrees(math.acos(float(np.clip((np.trace(np.asarray(D)) - 1.0) / 2.0, -1.0, 1.0))))


def measure_turn(rest, name, samples=97):
    """A turn clip on its solved poses: the yaw each foot has turned by in the world at the end, the most a
    standing foot moves in the world while the body turns over it, the highest a stepping foot lifts, and
    how far the posed ankles are from where the clip puts them."""
    sign = 1.0 if name == "turn_l" else -1.0
    frames = CLIP_FRAMES[name]
    slide, lift, err = 0.0, 0.0, 0.0
    for i in range(samples):
        u = i / float(samples - 1)
        pose = turn_pose(rest, u * frames, frames, sign).solve()
        feet = turn_feet(rest, u, sign)
        body = TURN_DEG * u * sign
        for side, (t0, t1) in zip(("l", "r") if sign > 0 else ("r", "l"), TURN_STEP):
            a, _yaw, lf, planted = feet[side]
            got = pose.P["foot_" + side]
            lift = max(lift, float(got[2] - rest.head["foot_" + side][2]))
            if planted:
                err = max(err, float(np.linalg.norm(got - a)))
                want = rest_ankle(rest, side) if u <= t0 else rot(Z, TURN_DEG * sign) @ rest_ankle(rest, side)
                slide = max(slide, float(np.linalg.norm(rot(Z, body) @ got - want)))
    end = turn_pose(rest, frames, frames, sign).solve()
    start = turn_pose(rest, 0, frames, sign).solve()
    turned = [TURN_DEG * sign + _yaw_of(end.D["foot_" + s]) - _yaw_of(start.D["foot_" + s]) for s in ("l", "r")]
    loop = max(float(np.linalg.norm(end.P[b] - start.P[b])) for b in ("foot_l", "foot_r", "pelvis", "head"))
    return {"turn_deg": r6(sum(turned) / 2.0), "slide_m": r6(slide), "step_lift_m": r6(lift), "foot_error_m": r6(err),
            "end_to_start_m": r6(loop), "keys": frames + 1}


def measure_stomp(rest, samples=121):
    """The stomp on its solved poses: how high the foot lifts, how far the plant point (the ankle as the
    foot lands) is from under the hip, and how far the standing foot and the planted foot are from where
    they stood."""
    frames = CLIP_FRAMES["stomp_r"]
    lift, stand = 0.0, 0.0
    for i in range(samples):
        pose = stomp_pose(rest, frames * i / float(samples - 1), frames).solve()
        lift = max(lift, float(pose.P["foot_r"][2] - rest.head["foot_r"][2]))
        stand = max(stand, float(np.linalg.norm(pose.P["foot_l"] - rest.head["foot_l"])))
    plant = stomp_pose(rest, frames * STOMP_PLANT, frames).solve()
    off = plant.P["foot_r"][:2] - plant.P["thigh_r"][:2]
    return {"lift_m": r6(lift), "plant_from_hip_m": r6(float(np.linalg.norm(off))),
            "plant_from_rest_m": r6(float(np.linalg.norm(plant.P["foot_r"] - rest.head["foot_r"]))),
            "standing_foot_m": r6(stand), "lift_fraction": STOMP_LIFT, "hold_fraction": STOMP_HOLD,
            "plant_fraction": STOMP_PLANT, "keys": frames + 1}


def measure_stance(rest, name, fn, samples=49):
    """A standing clip (land, brace, roar): the most the pelvis drops and how far each posed ankle is from
    the ground height it stands at."""
    frames = CLIP_FRAMES[name]
    drop, off_ground, spread = 0.0, 0.0, 0.0
    for i in range(samples if frames > 1 else 1):
        pose = fn(rest, frames * i / float(max(1, samples - 1)), frames).solve()
        drop = max(drop, float(rest.head["pelvis"][2] - pose.P["pelvis"][2]))
        spread = max(spread, float(abs(pose.P["foot_l"][0] - pose.P["foot_r"][0])))
        if name != "roar":
            off_ground = max(off_ground, max(abs(float(pose.P["foot_" + s][2] - rest.head["foot_" + s][2])) for s in "lr"))
    return {"pelvis_drop_m": r6(drop), "foot_off_ground_m": r6(off_ground), "feet_apart_m": r6(spread), "keys": frames + 1}


def measure_flinch(rest, name):
    """A flinch: the chest's and the head's largest turn from rest, and what is left at its ends (nothing)."""
    frames = CLIP_FRAMES[name]
    chest, head = 0.0, 0.0
    for f in range(frames + 1):
        pose = flinch_pose(rest, name, f, frames).solve()
        chest = max(chest, _angle_of(pose.D["spine_03"]))
        head = max(head, _angle_of(pose.D["head"]))
    ends = max(_angle_of(flinch_pose(rest, name, f, frames).solve().D[b]) for f in (0, frames) for b in UPPER_BODY)
    return {"chest_deg": r6(chest), "head_deg": r6(head), "ends_deg": r6(ends), "length_s": r6(frames / float(FPS)),
            "keys": frames + 1}


def measure_clips(rest):
    out = {"turn_l": measure_turn(rest, "turn_l"), "turn_r": measure_turn(rest, "turn_r"),
           "stomp_r": measure_stomp(rest), "land": measure_stance(rest, "land", land_pose),
           "brace": measure_stance(rest, "brace", brace_pose), "roar": measure_stance(rest, "roar", roar_pose)}
    for name in sorted(FLINCH):
        out[name] = measure_flinch(rest, name)
    return out


# --------------------------------------------------------------------------------------
# the glTF's tracks: a partial clip keeps its own bones' only
# --------------------------------------------------------------------------------------
def strip_tracks(path, keep):
    """Rewrites a glTF binary without the animation channels of bones a clip does not key: ``keep`` is
    {clip: set of bone names}. Samplers, accessors and buffer views nothing uses any more leave the file;
    what stays keeps its bytes. Returns {clip: channels kept}."""
    import struct
    with open(path, "rb") as fh:
        data = fh.read()
    pos, doc, binary = 12, None, b""
    while pos < len(data):
        clen, ctype = struct.unpack_from("<I4s", data, pos)
        chunk = data[pos + 8: pos + 8 + clen]
        if ctype == b"JSON":
            doc = json.loads(chunk.decode("utf-8"))
        elif ctype == b"BIN\x00":
            binary = chunk
        pos += 8 + clen
    kept = {}
    for a in doc.get("animations", []):
        if a["name"] not in keep:
            continue
        chans = [c for c in a["channels"] if doc["nodes"][c["target"]["node"]]["name"] in keep[a["name"]]]
        used = sorted({c["sampler"] for c in chans})
        remap = {old: new for new, old in enumerate(used)}
        a["samplers"] = [a["samplers"][i] for i in used]
        a["channels"] = [dict(c, sampler=remap[c["sampler"]]) for c in chans]
        kept[a["name"]] = len(chans)
    used_acc = set()
    for m in doc.get("meshes", []):
        for prim in m["primitives"]:
            used_acc.update(prim["attributes"].values())
            if "indices" in prim:
                used_acc.add(prim["indices"])
    for sk in doc.get("skins", []):
        if "inverseBindMatrices" in sk:
            used_acc.add(sk["inverseBindMatrices"])
    for a in doc.get("animations", []):
        for sm in a["samplers"]:
            used_acc.update((sm["input"], sm["output"]))
    acc_map = {old: new for new, old in enumerate(sorted(used_acc))}
    accessors = [doc["accessors"][i] for i in sorted(used_acc)]
    used_bv = sorted({a["bufferView"] for a in accessors})
    bv_map = {old: new for new, old in enumerate(used_bv)}
    out_bin = bytearray()
    views = []
    for i in used_bv:
        bv = dict(doc["bufferViews"][i])
        start = bv.get("byteOffset", 0)
        while len(out_bin) % 4:
            out_bin.append(0)
        bv["byteOffset"] = len(out_bin)
        out_bin += binary[start: start + bv["byteLength"]]
        views.append(bv)
    while len(out_bin) % 4:
        out_bin.append(0)
    for a in accessors:
        a["bufferView"] = bv_map[a["bufferView"]]
    for m in doc.get("meshes", []):
        for prim in m["primitives"]:
            prim["attributes"] = {k: acc_map[v] for k, v in prim["attributes"].items()}
            if "indices" in prim:
                prim["indices"] = acc_map[prim["indices"]]
    for sk in doc.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = acc_map[sk["inverseBindMatrices"]]
    for a in doc.get("animations", []):
        for sm in a["samplers"]:
            sm["input"], sm["output"] = acc_map[sm["input"]], acc_map[sm["output"]]
    doc["accessors"], doc["bufferViews"] = accessors, views
    doc["buffers"] = [{"byteLength": len(out_bin)}]
    text = json.dumps(doc, separators=(",", ":"), sort_keys=True).encode("utf-8")
    text += b" " * (-len(text) % 4)
    total = 12 + 8 + len(text) + 8 + len(out_bin)
    with open(path, "wb") as fh:
        fh.write(struct.pack("<4sII", b"glTF", 2, total))
        fh.write(struct.pack("<I4s", len(text), b"JSON"))
        fh.write(text)
        fh.write(struct.pack("<I4s", len(out_bin), b"BIN\x00"))
        fh.write(bytes(out_bin))
    return kept


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
    worst = max(check_against_blender(rig, rest, poses[n][k]) for n, k in (
        ("walk", 5), ("run", 11), ("death", 30), ("idle", 13), ("sprint", 7), ("turn_l", 9), ("turn_r", 17),
        ("stomp_r", 12), ("land", 2), ("brace", 0), ("roar", 10)))
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
    # P48: a partial clip keeps the tracks of its own bones only (M10's follow-up: the hand clips carried
    # a track for every bone, which the tree evaluated every frame)
    kept = strip_tracks(path, {n: set(clip_bones(rest, n)) for n in CLIP_FRAMES if is_partial(n)})
    info = {"fps": FPS, "step_m": STEP_M, "cycle_m": CYCLE_M, "left_strike_phase": r6(LEFT_STRIKE),
            "clips": {n: {"frames": f, "length_s": r6(f / float(FPS)), "loop": n in LOOPS,
                          "bones": len(clip_bones(rest, n)), "partial": is_partial(n)} for n, f in CLIP_FRAMES.items()},
            "gaits": {n: measure_gait(g) for n, g in sorted(gaits.items())},
            "measures": measure_clips(rest),
            "conversion_error_m": r6(worst)}
    for n, count in sorted(kept.items()):
        if count != 3 * info["clips"][n]["bones"]:
            raise SystemExit("clips: %s kept %d channels, expected three a bone (%d bones)" % (n, count, info["clips"][n]["bones"]))
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
