"""A person built from the giant's CC0 MakeHuman data (plan M11 §2.8, P59), and the people's clips.

``build_person`` makes a human from the same hm08 base mesh, macro targets and detail targets as the giant
(``giant_body.BodyData``), with MakeHuman's own natural proportions (the giant's reshape, ``PROPORTIONS``, is his:
it undid the strongman's build), on the game_engine rig, with the hands posed half closed. Everything is built at
the giant's stage-1 height first (``people_roles.DESIGN_HEIGHT_M``), so the giant's garment shells and his clip
generator apply in the units they were written in, and the export scales it to 1.8 m (``EXPORT_SCALE``).

Every person's skeleton is the 23 bones of ``people_roles.BONES`` (the fingers' weights folded into the hands).
So that one set of clips poses every variant exactly, each variant's pelvis stands where the reference man's does
(its scale is set by the pelvis's height, not the crown's: a person's height varies by a few centimetres with the
build) and its bones take the reference's rest orientations at their own joints; the Root bone is the reference's.

``python people_body.py <out dir> <work dir>`` writes ``people_clips.glb``: the clips of
``people_roles.CLIP_FRAMES`` computed by ``clips.py`` (with its proportions parameter: the soldier's 0.9 m step at
1.8 m) on the reference man's 53-bone rig and keyed on the 23 bones.
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

import clips  # noqa: E402
import giant_body as gb  # noqa: E402
import mh_data as mh  # noqa: E402
import people_roles as pr  # noqa: E402

DESIGN = pr.DESIGN_HEIGHT_M
F = pr.EXPORT_SCALE
N = mh.N_BODY_VERTS
REF_MACRO = pr._m(1, 30)           # the reference man: the clips' skeleton (not shipped as a variant)
CLIPS_GLB = "people_clips.glb"
LIE_LOWEST_M = 0.34                # design m: the lowest joint of the body lying on its back (the flesh under it)
CLIPS_INFO = "people_clips_info.json"
# P59b: the clips whose forearms turn by FOREARM_TWIST_DEG and wrists bend by WRIST_BEND_DEG (make_poses)
TWISTED = ("idle", "walk", "run", "flee", "brace", "held", "tumble", "death", "seated")
FOREARM_TWIST_DEG = 12.0
WRIST_BEND_DEG = 30.0


def log(*a):
    print("[people_body]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


# --------------------------------------------------------------------------------------
# a person
# --------------------------------------------------------------------------------------
class Person:
    """A built person: ``bd`` (BodyData, human scale), ``S`` (human -> design scale), ``rig`` (the 53-bone armature
    at design scale), ``body`` (its skinned hm08 body), ``weights`` (the hm08 weights), ``rest`` (clips.Rest)."""

    def __init__(self, name, bd, S, objs):
        self.name, self.bd, self.S = name, bd, S
        self.rig, self.body, self.weights = objs["rig"], objs["body"], objs["weights"]
        self.coll = objs["collection"]
        self.rest = clips.Rest(self.rig)
        self.pelvis = self.rest.head["pelvis"].copy()

    def body_V(self):
        """The body's vertices at design scale (after the hands' pose)."""
        return self.bd.verts[:N] * self.S

    def groups53(self):
        """{bone: (N,) weight} of the body's vertices (the game_engine's 53 bones)."""
        out = {}
        for b, lst in self.weights.items():
            w = np.zeros(N)
            for vi, wt in lst:
                if vi < N:
                    w[vi] = wt
            out[b] = w
        return out


def _pelvis_point(bd):
    rig = mh.load_rig()
    p = mh.bone_point(rig["pelvis"]["head"], bd.verts_mh, bd.joints_mh)
    return mh.mh_to_blender(p) + bd.offset


def build_person(macro, modifiers, name, ref=None):
    """A person at design scale: the reference man when ``ref`` is None (his crown at DESIGN), else scaled and moved
    so that the pelvis's head is the reference's."""
    bd = gb.BodyData(macro, modifiers, proportions=False)
    p = _pelvis_point(bd)
    if ref is None:
        S = DESIGN / bd.height
    else:
        S = float(ref.pelvis[2] / p[2])
        dy = float(ref.pelvis[1] / S - p[1])
        shift = np.array([0.0, dy, 0.0])
        bd.offset = bd.offset + shift
        bd.verts = bd.verts + shift
        bd.joints = {k: v + shift for k, v in bd.joints.items()}
    objs = gb.build_giant({"height_m": bd.height * S, "name": name, "collection": gb._collection(name)}, bd=bd)
    person = Person(name, bd, objs["info"]["scale"], objs)
    pose_hands(person)
    return person


def lbs_pose(V, groups, pose, rest):
    """Linear-blend skinning of design-scale points by a solved clips.Pose (armature space)."""
    out = np.zeros_like(V)
    total = np.zeros(len(V))
    for b, w in groups.items():
        if b not in pose.D:
            continue
        sel = w > 0
        if not sel.any():
            continue
        M = pose.P[b] + (V[sel] - rest.head[b]) @ pose.D[b].T
        out[sel] += w[sel, None] * M
        total[sel] += w[sel]
    rest_part = np.clip(1.0 - total, 0.0, 1.0)
    return out + rest_part[:, None] * V


def hand_rest_spec(rest, side):
    """The relaxed rest hand (people_roles.HAND_CURLS): each finger's three joints toward the palm, graded from the
    index to the little finger; the thumb turned in along the index's side, not onto its tip."""
    n, across = clips.hand_frame(rest, side)
    s = "_" + side
    spec = {}
    for f in clips.FINGERS:
        c = pr.HAND_CURLS[f]
        spec[f"{f}_01{s}"] = [("toward", tuple(n), 78.0 * c)]
        spec[f"{f}_02{s}"] = [("toward", tuple(n), 100.0 * c)]
        spec[f"{f}_03{s}"] = [("toward", tuple(n), 62.0 * c)]
    t = pr.HAND_CURLS["thumb"]
    tdir = clips.unit(n * 0.55 + across * 0.35)
    spec[f"thumb_01{s}"] = [("toward", tuple(tdir), 34.0 * t)]
    spec[f"thumb_02{s}"] = [("toward", tuple(n), 22.0 * t)]
    spec[f"thumb_03{s}"] = [("toward", tuple(n), 26.0 * t)]
    return spec


def _circle_centre(Q):
    """The centre of the circle best through points Q (k, 3) (their plane's, algebraic fit)."""
    c = Q.mean(axis=0)
    _u, _s, Vt = np.linalg.svd(Q - c)
    e1, e2 = Vt[0], Vt[1]
    x, y = (Q - c) @ e1, (Q - c) @ e2
    A = np.column_stack([x, y, np.ones(len(Q))])
    sol = np.linalg.lstsq(A, x * x + y * y, rcond=None)[0]
    return c + e1 * sol[0] / 2.0 + e2 * sol[1] / 2.0


def grip_landmark(pose, side):
    """(point, axis) armature space, design scale: where a handle passes through the rest hand's curled fingers
    (the mean of each finger's curl's centre: knuckle, the two finger joints and the tip on a circle) and along
    which line (from the little finger's curl to the index's: the side a blade leaves the fist)."""
    r = pose.rest
    s = "_" + side
    cs = []
    for f in clips.FINGERS:
        tip = pose.P[f + "_03" + s] + pose.D[f + "_03" + s] @ (r.tail[f + "_03" + s] - r.head[f + "_03" + s])
        Q = np.array([pose.P[f + "_01" + s], pose.P[f + "_02" + s], pose.P[f + "_03" + s], tip])
        cs.append(_circle_centre(Q))
    cs = np.array(cs)
    axis = clips.unit(cs[0] - cs[-1])
    return cs.mean(axis=0), axis


def pose_hands(person):
    """The rest hands (hand_rest_spec; the fingers' weights fold into the hands, so this pose is the people's rest):
    the body's vertices (BodyData and the Blender body) move by the fingers' skinning; ``person.grip`` keeps each
    hand's grip landmark (grip_landmark)."""
    rest = person.rest
    pose = clips.Pose(rest)
    for s in ("l", "r"):
        pose.ops(hand_rest_spec(rest, s))
    pose.solve()
    person.grip = {s: grip_landmark(pose, s) for s in ("l", "r")}
    g = person.groups53()
    fingers = {b: w for b, w in g.items() if pr.fold_bone(b) != b}
    V = person.body_V()
    hand = np.zeros(N, bool)
    for w in fingers.values():
        hand |= w > 0
    Vp = V.copy()
    Vp[hand] = lbs_pose(V[hand], {b: w[hand] for b, w in g.items()}, pose, rest)
    person.bd.verts[:N] = Vp / person.S
    me = person.body.data
    me.vertices.foreach_set("co", Vp.astype(np.float32).ravel())
    me.update()


def folded_groups(groups53):
    return pr.fold_weights(groups53)


# --------------------------------------------------------------------------------------
# the 23-bone skeleton at export scale
# --------------------------------------------------------------------------------------
def export_rig(person, ref, name, coll):
    """The person's 23-bone armature at 1.8 m: its own joints, the reference's rest orientations, the reference's
    Root (so a clip's absolute pelvis track places every variant's pelvis as the reference's)."""
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
        R = rb.matrix_local.to_3x3()
        head = (rb.head_local if b == "Root" else sb.head_local) * F
        M = R.to_4x4()
        M.translation = head
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


def rest_matrices(arm):
    """{bone: 4x4 armature-space rest matrix} (numpy) of an armature object."""
    return {b.name: np.array([list(r) for r in b.matrix_local], np.float64) for b in arm.data.bones}


def parents_of(arm):
    return {b.name: (b.parent.name if b.parent else "") for b in arm.data.bones}


def quat_matrix(q):
    w, x, y, z = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def fk(rest, parents, basis, loc=None):
    """{bone: 4x4 posed armature-space matrix} from local basis quaternions (w, x, y, z) and the pelvis's basis
    location (bone-local, export scale): G_b = G_parent L_b T(loc_b) R(q_b), L_b = Rest_parent^-1 Rest_b."""
    out = {}
    order = []
    seen = set()

    def visit(b):
        if b in seen:
            return
        if parents[b]:
            visit(parents[b])
        seen.add(b)
        order.append(b)
    for b in sorted(rest):
        visit(b)
    for b in order:
        p = parents[b]
        L = np.linalg.inv(rest[p]) @ rest[b] if p else rest[b]
        T = np.eye(4)
        if loc is not None and b in loc:
            T[:3, 3] = loc[b]
        Rq = np.eye(4)
        if b in basis:
            Rq[:3, :3] = quat_matrix(basis[b])
        G = (out[p] if p else np.eye(4)) @ L @ T @ Rq
        out[b] = G
    return out


def skin_points(V, idx4, w4, rest, posed):
    """Linear-blend skinning of export-scale points by 23-bone indices and weights (people_roles.top4)."""
    mats = np.stack([posed[b] @ np.linalg.inv(rest[b]) for b in pr.BONES])
    Vh = np.concatenate([V, np.ones((len(V), 1))], axis=1)
    out = np.zeros((len(V), 3))
    for k in range(4):
        M = mats[idx4[:, k]]
        out += w4[:, k, None] * np.einsum("nij,nj->ni", M, Vh)[:, :3]
    return out


# --------------------------------------------------------------------------------------
# the people's clips (clips.py's machinery on the reference man)
# --------------------------------------------------------------------------------------
def _clear_arm(pose, side):
    for b in ("upperarm_" + side, "lowerarm_" + side):
        pose.rel.pop(b, None)


def flee_pose(rest, gait, phi):
    pose = gait.pose(phi)
    for s, sgn in (("l", 1.0), ("r", -1.0)):
        _clear_arm(pose, s)
        clips.set_arm(pose, s, sgn * 38.0 * math.sin(phi) - 18.0, 62.0 + 18.0 * math.sin(phi + sgn * 1.2),
                      out_deg=24.0, raise_deg=10.0)
    pose.set_rel("head", clips.rot(clips.Z, 14.0 * math.sin(0.5 * phi)) @ clips.rot(clips.X, -6.0))
    return pose


def cower_pose(rest, f, frames):
    ph = 2.0 * math.pi * f / frames
    shiver = math.sin(3.0 * ph)
    pose = clips.Pose(rest)
    pose.set_rel("pelvis", clips.rot(clips.X, 16.0))
    for b, d in (("spine_01", 10.0), ("spine_02", 12.0), ("spine_03", 10.0)):
        pose.set_rel(b, clips.rot(clips.X, d + 0.8 * shiver))
    pose.set_rel("neck_01", clips.rot(clips.X, 18.0))
    pose.set_rel("head", clips.rot(clips.X, 16.0) @ clips.rot(clips.Z, 3.0 * shiver))
    clips.stand_legs(pose, drop=0.62, back=0.20)
    clips.set_arm(pose, "l", -118.0 + 2.0 * shiver, 118.0, out_deg=10.0)
    clips.set_arm(pose, "r", -124.0 - 2.0 * shiver, 112.0, out_deg=12.0)
    return pose


def seated_pose(rest, f, frames):
    """The riding seat (P59b; P59's was a chair's): the seat between the sitting bones (people_roles.SEAT_DROP_M
    under the hip joints) at the armature's origin, the pelvis rocked back a little, the back upright; each foot in
    its stirrup (people_roles.STIRRUP_M: the ankle over the tread and behind it, the leg's two-bone solve with the
    knee forward and out round the horse's barrel); the hands low before the pommel on the reins."""
    pose = clips.Pose(rest)
    hip = 0.5 * (rest.head["thigh_l"] + rest.head["thigh_r"])
    seat = hip - np.array([0.0, 0.0, pr.SEAT_DROP_M / F])
    pose.offset = -np.array([0.0, seat[1], seat[2]])
    pose.set_rel("pelvis", clips.rot(clips.X, -6.0))
    pose.set_rel("spine_01", clips.rot(clips.X, 5.0))
    pose.set_rel("spine_02", clips.rot(clips.X, 3.0))
    pose.solve()
    sx, sy, sz = pr.STIRRUP_M
    for s, out in (("l", 1.0), ("r", -1.0)):
        leg = clips.Leg(rest, s)
        ankle = np.array([out * sx, sy + pr.RIDER_ANKLE_BEHIND_M, sz + pr.RIDER_ANKLE_OVER_TREAD_M]) / F
        leg.place(pose, pose.P["thigh_" + s], ankle, -8.0, 0.0, clips.rot(clips.Z, out * 28.0))
    clips.set_arm(pose, "l", -16.0, 78.0, out_deg=10.0)
    clips.set_arm(pose, "r", -16.0, 78.0, out_deg=10.0)
    return pose


def held_pose(rest, f, frames):
    ph = 2.0 * math.pi * f / frames
    s = math.sin(ph)
    pose = clips.Pose(rest)
    pose.set_rel("spine_02", clips.rot(clips.X, 6.0 + 2.0 * s))
    pose.set_rel("neck_01", clips.rot(clips.X, 16.0))
    pose.set_rel("head", clips.rot(clips.X, 22.0) @ clips.rot(clips.Y, 9.0 * s))
    pose.set_rel("thigh_l", clips.rot(clips.X, -10.0 - 6.0 * s))
    pose.set_rel("thigh_r", clips.rot(clips.X, -4.0 + 6.0 * s))
    pose.set_rel("calf_l", clips.rot(clips.X, 18.0 + 4.0 * s))
    pose.set_rel("calf_r", clips.rot(clips.X, 12.0 - 4.0 * s))
    pose.set_rel("foot_l", clips.rot(clips.X, 30.0))
    pose.set_rel("foot_r", clips.rot(clips.X, 26.0))
    clips.set_arm(pose, "l", 4.0 * s, 12.0, out_deg=6.0)
    clips.set_arm(pose, "r", -4.0 * s, 14.0, out_deg=6.0)
    return pose


def tumble_pose(rest, f, frames):
    ph = 2.0 * math.pi * f / frames
    s, c = math.sin(ph), math.cos(ph)
    pose = clips.Pose(rest)
    pose.set_rel("spine_02", clips.rot(clips.Z, 12.0 * s) @ clips.rot(clips.X, -8.0 * c))
    pose.set_rel("head", clips.rot(clips.X, -18.0 * c))
    pose.set_rel("thigh_l", clips.rot(clips.Y, 18.0) @ clips.rot(clips.X, -30.0 * s - 20.0))
    pose.set_rel("thigh_r", clips.rot(clips.Y, -18.0) @ clips.rot(clips.X, 30.0 * s - 20.0))
    pose.set_rel("calf_l", clips.rot(clips.X, 40.0 + 25.0 * c))
    pose.set_rel("calf_r", clips.rot(clips.X, 40.0 - 25.0 * c))
    clips.set_arm(pose, "l", -30.0 * s, 35.0, out_deg=20.0, raise_deg=65.0 + 20.0 * c)
    clips.set_arm(pose, "r", 30.0 * s, 35.0, out_deg=20.0, raise_deg=65.0 - 20.0 * c)
    return pose


def _lowest(pose):
    pose.solve()
    return min(float(p[2]) for b, p in pose.P.items() if b != "Root")


def death_pose(rest, f, frames):
    """The knees go, then the body falls backward and lies on its back (its last key is the corpse)."""
    t = f / float(frames)
    bend = clips.smooth(t / 0.4)
    fall = clips.smooth((t - 0.3) / 0.7)
    pose = clips.Pose(rest)
    pose.set_rel("pelvis", clips.rot(clips.X, 10.0 * bend * (1.0 - fall) - 84.0 * fall))
    for b, deg in (("spine_01", 6.0), ("spine_02", 5.0), ("spine_03", 4.0)):
        pose.set_rel(b, clips.rot(clips.X, deg * bend * (1.0 - fall) - 2.0 * fall))
    pose.set_rel("neck_01", clips.rot(clips.X, 12.0 * bend - 4.0 * fall))
    pose.set_rel("head", clips.rot(clips.X, 10.0 * bend) @ clips.rot(clips.Y, 18.0 * fall))
    for s, k in (("l", 1.0), ("r", 0.8)):
        pose.set_rel("thigh_" + s, clips.rot(clips.X, -40.0 * k * bend * (1.0 - fall) - 8.0 * fall))
        pose.set_rel("calf_" + s, clips.rot(clips.X, 80.0 * k * bend * (1.0 - fall) + 14.0 * fall))
        pose.set_rel("foot_" + s, clips.rot(clips.X, 12.0 * fall))
    clips.set_arm(pose, "l", -12.0 * bend + 20.0 * fall, 16.0 + 10.0 * fall, out_deg=8.0 + 30.0 * fall)
    clips.set_arm(pose, "r", -16.0 * bend + 10.0 * fall, 18.0 + 22.0 * fall, out_deg=8.0 + 42.0 * fall)
    # the pelvis falls back and down: the lowest joint from the rest's (the balls on the ground) to a hand over it
    base = _lowest(clips.Pose(rest))
    target = base + (LIE_LOWEST_M - base) * fall
    pose.offset = np.array([0.0, 0.34 * fall, 0.0])
    low = _lowest(pose)
    pose.offset = pose.offset + np.array([0.0, 0.0, target - low])
    return pose


def grip_pose(rest, side):
    pose = clips.Pose(rest)
    pose.set_rel("hand_" + side, clips.rot(clips.X, -12.0))
    return pose


# P59b: the people's own changes to clips.py's gaits (design metres): the run planted longer and lifted less, so its
# pelvis need not fall as far to reach the feet (it dropped 25 cm at the people's stride)
GAIT_CHANGES = {"walk": {"top_drop": 0.02, "min_drop": 0.02, "lift": 0.16},
                "run": {"duty": 0.42, "top_drop": 0.05, "min_drop": 0.05, "lift": 0.42, "heel_off": 0.5}}


def people_gait(rest, name, kind):
    """clips.Gait of ``kind`` with GAIT_CHANGES, fitted again (at the step clips.configure set)."""
    g = clips.Gait(rest, kind, pr.CLIP_FRAMES[name])
    g.g = dict(g.g, **GAIT_CHANGES.get(name, {}))
    hip_y = rest.head["thigh_l"][1]
    g.y_strike = hip_y - 0.5 * g.g["duty"] * clips.CYCLE_M + g.legs["l"].heel_back - g.g["bias"]
    g.top = -g.g["top_drop"]
    g.amp = g.g["min_drop"]
    g._fit()
    return g


def make_poses(rest):
    """{clip: [solved clips.Pose, one a key]} of people_roles.CLIP_FRAMES on a 53-bone rest (design scale)."""
    gaits = {}
    for name, kind in (("walk", "walk"), ("run", "run"), ("flee", "sprint")):
        clips.configure(step_m=pr.GAIT_STEP_M[name] / F)
        gaits[name] = people_gait(rest, name, kind)
    poses = {}
    for name, frames in pr.CLIP_FRAMES.items():
        # (clips.py's gait reads its step at every pose: each gait's own)
        clips.configure(step_m=pr.GAIT_STEP_M.get(name, pr.GAIT_STEP_M["walk"]) / F)
        keys = []
        for f in range(frames + 1):
            phi = 2.0 * math.pi * f / frames
            if name == "idle":
                p = clips.idle_pose(rest, f, frames)
            elif name in ("walk", "run"):
                p = gaits[name].pose(phi)
            elif name == "flee":
                p = flee_pose(rest, gaits["flee"], phi)
            elif name == "brace":
                p = clips.brace_pose(rest, f, frames)
            elif name == "cower":
                p = cower_pose(rest, f, frames)
            elif name == "seated":
                p = seated_pose(rest, f, frames)
            elif name == "held":
                p = held_pose(rest, f, frames)
            elif name == "tumble":
                p = tumble_pose(rest, f, frames)
            elif name == "death":
                p = death_pose(rest, f, frames)
            else:
                p = grip_pose(rest, name[-1])
            if name in TWISTED:
                # the hanging hands' knuckles run forward (the forearm turned a little) and the wrists bend down a
                # little toward the little finger: what a fist holds (the grip landmark's line) points forward and
                # down, as P60 carried a sword
                for side, sg in (("l", -1.0), ("r", 1.0)):
                    clips.twist_forearm(p, side, sg * FOREARM_TWIST_DEG)
                    n, _across = clips.hand_frame(rest, side)
                    p.ops({"hand_" + side: [("axis", tuple(n), sg * WRIST_BEND_DEG)]})
            keys.append(p.solve())
        poses[name] = keys
    return poses, gaits


def clip_bones(name):
    return pr.PARTIAL_CLIPS.get(name, pr.BONES)


def tracks(poses, rest53, ref_rest_export):
    """{clip: [{"basis": {bone: (w, x, y, z)}, "loc": {"pelvis": (3,) export scale}}, one a key]}: each key's local
    rotations of the 23 bones (clips.Pose.basis on the reference's 53-bone rest: its bones' rest orientations are the
    export rig's) and the pelvis's location in its own rest frame at 1.8 m."""
    out = {}
    R_pelvis = ref_rest_export["pelvis"][:3, :3]
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


def pose_key(trk, clip, key):
    seq = trk[clip]
    return seq[key if key >= 0 else len(seq) + key]


def reference():
    return build_person(REF_MACRO, {}, "Reference")


# --------------------------------------------------------------------------------------
# people_clips.glb
# --------------------------------------------------------------------------------------
def key_actions(arm, trk):
    for name in pr.CLIP_FRAMES:
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


def anchor_mesh(arm, coll):
    verts, faces = [], []
    rest = rest_matrices(arm)
    for i, b in enumerate(pr.BONES):
        h = rest[b][:3, 3]
        verts += [tuple(h), tuple(h + np.array([0.002, 0.0, 0.0])), tuple(h + np.array([0.0, 0.0, 0.002]))]
        faces.append((3 * i, 3 * i + 1, 3 * i + 2))
    me = bpy.data.meshes.new("ClipsAnchor")
    me.from_pydata(verts, [], faces)
    me.update()
    ob = bpy.data.objects.new("ClipsAnchor", me)
    coll.objects.link(ob)
    for i, b in enumerate(pr.BONES):
        vg = ob.vertex_groups.new(name=b)
        vg.add([3 * i, 3 * i + 1, 3 * i + 2], 1.0, "REPLACE")
    gb.parent_keep(ob, arm)
    gb.armature_modifier(ob, arm)
    return ob


def measure_walk(gaits):
    out = {}
    for n, g in sorted(gaits.items()):
        clips.configure(step_m=pr.GAIT_STEP_M[n] / F)
        m = clips.measure_gait(g)
        out[n] = {k: (r6(v * F) if k.endswith("_m") else v) for k, v in m.items()}
    return out


def clips_main(out_dir, work_dir):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = clips.FPS
    ref = reference()
    coll = gb._collection("Clips")
    arm = export_rig(ref, ref, "People", coll)
    rest_e = rest_matrices(arm)
    poses, gaits = make_poses(ref.rest)
    trk = tracks(poses, ref.rest, rest_e)
    # the keyed rotations reproduce the solved poses' joints (at 1.8 m)
    worst = 0.0
    for name in ("walk", "death", "cower", "idle", "flee", "held"):
        for k in (0, len(poses[name]) // 2, len(poses[name]) - 1):
            G = fk(rest_e, parents_of(arm), pose_key(trk, name, k)["basis"], pose_key(trk, name, k)["loc"])
            for b in ("foot_l", "hand_r", "head", "calf_r", "pelvis"):
                worst = max(worst, float(np.linalg.norm(G[b][:3, 3] - poses[name][k].P[b] * F)))
    if worst > 1e-4:
        raise SystemExit("people clips: the keys do not reproduce the solved poses (%.6f m off)" % worst)
    for o in list(bpy.data.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    anchor = anchor_mesh(arm, coll)
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
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, CLIPS_GLB)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=False,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS",
                              export_force_sampling=True, export_frame_step=1,
                              export_optimize_animation_size=False, export_reset_pose_bones=True,
                              export_morph=False, export_materials="NONE", export_yup=True,
                              export_def_bones=False, export_leaf_bone=False, export_extras=False,
                              export_cameras=False, export_lights=False, export_rest_position_armature=True)
    keep = {n: set(clip_bones(n)) for n in pr.CLIP_FRAMES if n in pr.PARTIAL_CLIPS}
    kept = clips.strip_tracks(path, keep)
    for n, count in sorted(kept.items()):
        if count != 3 * len(clip_bones(n)) and count != len(clip_bones(n)):
            raise SystemExit("people clips: %s kept %d channels for %d bones" % (n, count, len(clip_bones(n))))
    info = {"fps": clips.FPS, "step_m": pr.GAIT_STEP_M["walk"], "cycle_m": r6(2.0 * pr.GAIT_STEP_M["walk"]),
            "run_cycle_m": r6(2.0 * pr.GAIT_STEP_M["run"]), "bones": list(pr.BONES),
            "clips": {n: {"frames": f, "length_s": r6(f / float(clips.FPS)), "loop": n in pr.CLIP_LOOPS,
                          "bones": len(clip_bones(n)), "partial": n in pr.PARTIAL_CLIPS}
                      for n, f in pr.CLIP_FRAMES.items()},
            "gaits": measure_walk(gaits), "conversion_error_m": r6(worst),
            "reference": {"pelvis_m": [r6(x * F) for x in ref.pelvis], "height_m": r6(ref.bd.height * ref.S * F)}}
    if work_dir:
        os.makedirs(work_dir, exist_ok=True)
        with open(os.path.join(work_dir, CLIPS_INFO), "w", encoding="utf-8") as fh:
            json.dump(info, fh, indent=1, sort_keys=True)
    log("wrote %s (%d bytes) in %.1f s; walk stride %.4f m a cycle" % (
        path, os.path.getsize(path), time.time() - t0, info["gaits"]["walk"]["stride_m"]))
    return info


if __name__ == "__main__":
    clips_main(sys.argv[1] if len(sys.argv) > 1 else os.getcwd(), sys.argv[2] if len(sys.argv) > 2 else "")
