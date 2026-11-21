"""The body pipeline II (P48, plan M11 §2.2): what the export adds to the M10 giant without moving a
vertex of his body or a bone of his 53.

* ``add_leaf_bones``   18 leaf bones on the game_engine rig: under ``head`` three chains for the hair
                       (``hair_01``-``03`` down the back, ``hair_l_01``-``02`` and ``hair_r_01``-``02``
                       beside the ears) and one for the beard (``beard_01``-``02``); under ``spine_03``
                       three chains of three for the cape (``cape_c``, ``cape_l``, ``cape_r``). No body
                       vertex is weighted to them.
* ``card_weights``     the hair and beard cards' skin: every card's root stays on ``head``; along the
                       card the weight passes to the chain it hangs beside, joint by joint.
* ``chain_weights``    the same hat functions for the free cape.
* ``build_weights``    the build sliders' two signed weights per body vertex (brawn, girth): the
                       MakeHuman muscle target's and weight target's displacement projected on the
                       vertex normal, as a share of the largest (``build_max_m``, metres at stage 1).
* ``shadow_proxy``     the whole body decimated to about 2,500 triangles with its skin weights, a little
                       inside the skin: the one mesh the giant casts his shadow with.
* ``hand_landmarks``   the grips, their axes, the knuckles and the toes.

Blender axes throughout (+X the giant's left, -Y his front, +Z up), metres at stage 1 unless a name
says human scale.
"""
from __future__ import annotations

import bpy
import numpy as np
from mathutils import Vector

import mh_data as mh

# ---- the chains (human-scale metres from their roots; a chain hangs along its direction) ----------
# name: (parent bone, bone names, each bone's length, the direction it hangs along)
HAIR_BONE_M = 0.10
SIDE_BONE_M = 0.13
BEARD_BONE_M = 0.09
CHAINS = {
    "hair": ("head", ("hair_01", "hair_02", "hair_03"), HAIR_BONE_M, (0.0, 0.10, -1.0)),
    "hair_l": ("head", ("hair_l_01", "hair_l_02"), SIDE_BONE_M, (0.06, -0.30, -1.0)),
    "hair_r": ("head", ("hair_r_01", "hair_r_02"), SIDE_BONE_M, (-0.06, -0.30, -1.0)),
    "beard": ("head", ("beard_01", "beard_02"), BEARD_BONE_M, (0.0, -0.16, -1.0)),
    "cape_c": ("spine_03", ("cape_c_01", "cape_c_02", "cape_c_03"), None, (0.0, 0.05, -1.0)),
    "cape_l": ("spine_03", ("cape_l_01", "cape_l_02", "cape_l_03"), None, (0.04, 0.05, -1.0)),
    "cape_r": ("spine_03", ("cape_r_01", "cape_r_02", "cape_r_03"), None, (-0.04, 0.05, -1.0)),
}
CHAIN_ORDER = ("hair", "hair_l", "hair_r", "beard", "cape_c", "cape_l", "cape_r")
LEAF_BONES = tuple(b for c in CHAIN_ORDER for b in CHAINS[c][1])
# The secondary motion's starting values per chain kind (plan §2.3: P50 reads them from the index).
CHAIN_PHYSICS = {
    "hair": {"stiffness": 1.6, "drag": 0.45, "gravity": 0.6, "max_deg": 38.0},
    "beard": {"stiffness": 3.0, "drag": 0.6, "gravity": 0.4, "max_deg": 22.0},
    "cape": {"stiffness": 0.9, "drag": 0.35, "gravity": 1.0, "max_deg": 55.0},
}
# How far along a card from its root (human-scale metres) the head still holds it whole, and from where
# the chain may have all of it: the first centimetres of a lock are stiff, and a short card (the crop, the
# short beard) never leaves the head.
ARC_HOLD, ARC_FREE = 0.03, 0.14
# Azimuth about the head (degrees, 0 the face, 180 the back of the head) between which a card passes from
# the side chains to the back chain.
SIDE_PHI = (95.0, 135.0)
CHAIN_LEAST = 0.5                # a chain is a style's when some vertex hangs on it by at least this
MAX_INFLUENCES = 4
SHADOW_TRIANGLES = 2500
SHADOW_INSET_M = 0.012          # stage 1: the proxy sits this far inside the skin, so it never shades it
BUILD_SMOOTH = 2                # Laplacian passes over the build weights (creases would speckle)


def unit(v):
    v = np.asarray(v, np.float64)
    return v / (np.linalg.norm(v) + 1e-12)


def sstep(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# --------------------------------------------------------------------------------------
# leaf bones
# --------------------------------------------------------------------------------------
def chain_layout(bd, S, heads):
    """{chain: {"parent", "bones", "root" (3,), "dir" (3,), "joints" [distance of each bone's head from
    the root, then the chain's end]}} at stage 1, from the body's landmarks and the rig's bone heads."""
    L = bd.landmarks
    hs = L["hs"]
    cy = L["head_cy"] * S
    ear_lo = L["ear_z"][0] * S
    V = bd.verts[: mh.N_BODY_VERTS] * S
    scalp = bd.masks["m_scalp"] > 0.5
    back_y = float(V[scalp, 1].max())
    half_x = float(np.abs(V[scalp, 0]).max())
    chin = np.array([0.0, L["face_y"] * S + 0.02 * hs * S, L["chin"] * S])
    sh = heads["upperarm_l"]
    hip_z = float(heads["thigh_l"][2])
    torso = bd.masks["m_torso"] > 0.5
    band = torso & (np.abs(V[:, 2] - (sh[2] - 0.10 * S)) < 0.05 * S)
    cape_y = float(V[band, 1].max()) + 0.05 * S
    cape_z = float(sh[2] - 0.06 * S)
    cape_len = (cape_z - hip_z) / 3.0
    roots = {
        "hair": np.array([0.0, back_y - 0.01 * S, ear_lo]),
        "hair_l": np.array([half_x, cy, ear_lo]),
        "hair_r": np.array([-half_x, cy, ear_lo]),
        "beard": chin,
        "cape_c": np.array([0.0, cape_y, cape_z]),
        "cape_l": np.array([0.62 * float(sh[0]), cape_y - 0.02 * S, cape_z]),
        "cape_r": np.array([-0.62 * float(sh[0]), cape_y - 0.02 * S, cape_z]),
    }
    out = {}
    for name in CHAIN_ORDER:
        parent, bones, length, d = CHAINS[name]
        seg = cape_len if length is None else length * S
        out[name] = {"parent": parent, "bones": list(bones), "root": roots[name], "dir": unit(d),
                     "joints": [seg * k for k in range(len(bones) + 1)]}
    return out


def add_leaf_bones(rig, layout):
    """The 18 leaf bones as edit bones (each chain connected, its first bone loose under its parent)."""
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for name in CHAIN_ORDER:
        c = layout[name]
        prev = eb[c["parent"]]
        for k, bone in enumerate(c["bones"]):
            b = eb.new(bone)
            b.head = Vector((c["root"] + c["dir"] * c["joints"][k]).tolist())
            b.tail = Vector((c["root"] + c["dir"] * c["joints"][k + 1]).tolist())
            b.roll = 0.0
            b.parent = prev
            b.use_connect = k > 0
            b.use_deform = True
            prev = b
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    vl.update()


def hat_weights(P, chain):
    """{bone or the chain's parent: (n,)}: a point's weights along a chain. Above the root the parent has
    it; between two joints it passes linearly from the bone above to the bone below (a bone turns about
    its own head, so a point at the next joint is all its own); past the end the last bone keeps it."""
    s = (np.asarray(P, np.float64) - chain["root"]) @ chain["dir"]
    nodes = chain["joints"]
    names = [chain["parent"]] + list(chain["bones"])
    out = {n: np.zeros(len(P)) for n in names}
    for k in range(len(nodes)):
        lo = nodes[k - 1] if k > 0 else None
        hi = nodes[k + 1] if k + 1 < len(nodes) else None
        w = np.ones(len(P))
        if lo is not None:
            w = np.minimum(w, np.clip((s - lo) / (nodes[k] - lo), 0.0, 1.0))
        else:
            w = np.where(s <= nodes[0], 1.0, w)
        if hi is not None:
            w = np.minimum(w, np.clip((hi - s) / (hi - nodes[k]), 0.0, 1.0))
        # node k is joint k: its weight belongs to the bone above it (the parent at the root)
        out[names[k]] += w if k < len(names) else 0.0
    return out


def prune(groups, n, keep=MAX_INFLUENCES):
    """At most ``keep`` influences a vertex (the largest), renormalized: {bone: (n,)}."""
    names = sorted(groups)
    W = np.stack([np.asarray(groups[b], np.float64) for b in names], axis=1)
    if W.shape[1] > keep:
        cut = np.sort(W, axis=1)[:, -keep][:, None]
        W = np.where(W >= cut, W, 0.0)
    W = np.where(W < 1e-4, 0.0, W)
    total = W.sum(axis=1, keepdims=True)
    W = W / np.maximum(total, 1e-12)
    return {b: W[:, i] for i, b in enumerate(names) if W[:, i].max() > 0.0}


def card_weights(V, arc, kind, layout, head_centre_y, S, free=None):
    """The skin of hair or beard cards: V (n, 3), arc (n,) each vertex's distance from its card's root
    along the card (m, stage 1; 0 at the root), kind "hair" | "beard"; ``free`` (n,) bool marks braid
    vertices, which hang whole from where they leave the head (a braid's lobes are short cards of their
    own: their roots are not on the scalp). Returns {bone: (n,)} with at most four influences a vertex."""
    n = len(V)
    hold = sstep(arc, ARC_HOLD * S, ARC_FREE * S)
    if free is not None:
        hold = np.where(free, 1.0, hold)
    groups = {"head": np.zeros(n)}
    if kind == "beard":
        shares = {"beard": np.ones(n)}
    else:
        phi = np.degrees(np.arctan2(np.abs(V[:, 0]), -(V[:, 1] - head_centre_y)))
        side = 1.0 - sstep(phi, SIDE_PHI[0], SIDE_PHI[1])
        left = sstep(V[:, 0], -0.03, 0.03)
        shares = {"hair": 1.0 - side, "hair_l": side * left, "hair_r": side * (1.0 - left)}
    for cname, share in shares.items():
        chain = layout[cname]
        hw = hat_weights(V, chain)
        for bone, w in hw.items():
            if bone == chain["parent"]:
                groups["head"] += share * (w * hold + (1.0 - hold))
            else:
                groups[bone] = groups.get(bone, np.zeros(n)) + share * w * hold
    return prune(groups, n)


def chain_weights(V, body_groups, layout, names=("cape_l", "cape_c", "cape_r"), blend=0.06, let_go_z=None):
    """A free cloth's skin: above the chains' roots the body's own weights (``body_groups``, the shell's);
    below, the three chains by where the vertex is across the back, joint by joint. ``blend``: the height
    (m) over which the body lets go; ``let_go_z`` (stage-1 m, P54): where it begins to, when lower than the roots
    (a cloak lies on the back down to there, so the shoulders' garments lie over it in every pose)."""
    n = len(V)
    xs = np.array([layout[c]["root"][0] for c in names])
    order = np.argsort(xs)
    xs, names = xs[order], [names[i] for i in order]
    root_z = float(np.mean([layout[c]["root"][2] for c in names]))
    if let_go_z is not None:
        root_z = min(root_z, float(let_go_z))
    let_go = sstep(root_z + blend - V[:, 2], 0.0, 2.0 * blend)       # 0 above the roots, 1 below
    across = np.stack([np.clip(1.0 - np.abs(V[:, 0] - x) / (xs[1] - xs[0]), 0.0, 1.0) for x in xs], axis=1)
    across[:, 0] = np.where(V[:, 0] <= xs[0], 1.0, across[:, 0])
    across[:, -1] = np.where(V[:, 0] >= xs[-1], 1.0, across[:, -1])
    across /= across.sum(axis=1, keepdims=True)
    groups = {b: np.asarray(w, np.float64) * (1.0 - let_go) for b, w in body_groups.items()}
    body_total = sum(np.asarray(w, np.float64) for w in body_groups.values())
    for k, cname in enumerate(names):
        chain = layout[cname]
        for bone, w in hat_weights(V, chain).items():
            if bone == chain["parent"]:
                # the part of a chain's hat that is its parent's stays with the body's own skin there
                for b, bw in body_groups.items():
                    groups[b] = groups[b] + across[:, k] * w * let_go * np.asarray(bw) / np.maximum(body_total, 1e-9)
            else:
                groups[bone] = groups.get(bone, np.zeros(n)) + across[:, k] * w * let_go
    return prune(groups, n)


def chains_of(groups):
    """The chains a mesh is weighted to (index: meshes[id].chains), in CHAIN_ORDER."""
    return [c for c in CHAIN_ORDER if any(b in groups and float(np.max(groups[b])) > 0.0 for b in CHAINS[c][1])]


def fold_weak_chains(groups, parent="head", least=CHAIN_LEAST):
    """A chain no vertex hangs on by at least ``least`` gives its weights back to its parent: a short
    style (the crop, the short beard) stays wholly on the head and needs no secondary motion."""
    out = {b: np.asarray(w, np.float64).copy() for b, w in groups.items()}
    for c in CHAIN_ORDER:
        bones = [b for b in CHAINS[c][1] if b in out]
        if bones and max(float(out[b].max()) for b in bones) < least:
            for b in bones:
                out[parent] = out.get(parent, 0.0) + out.pop(b)
    return out


def chain_index(layout, godot):
    """The index's ``chains``: per chain its parent, bones, kind, rest root (game frame) and length, and
    the secondary motion's starting values."""
    out = {}
    for name in CHAIN_ORDER:
        c = layout[name]
        kind = "cape" if name.startswith("cape") else ("beard" if name == "beard" else "hair")
        e = {"parent": c["parent"], "bones": list(c["bones"]), "kind": kind, "root": godot(c["root"]),
             "length_m": float(round(c["joints"][-1], 6))}
        e.update(CHAIN_PHYSICS[kind])
        out[name] = e
    return out


# --------------------------------------------------------------------------------------
# build weights
# --------------------------------------------------------------------------------------
def _smooth(values, faces, n, passes):
    faces = np.asarray(faces)
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(np.float64)
    v = np.asarray(values, np.float64).copy()
    for _ in range(passes):
        acc = np.bincount(e[:, 0], weights=v[e[:, 1]], minlength=n)
        v = 0.5 * v + 0.5 * acc / np.maximum(deg, 1)
    return v


def _mirror_mean(values, V):
    """The mean of each vertex's value and its mirror twin's (x -> -x), so left and right agree exactly."""
    from scipy.spatial import cKDTree
    M = np.asarray(V, np.float64) * [-1.0, 1.0, 1.0]
    d, twin = cKDTree(V).query(M)
    out = np.asarray(values, np.float64).copy()
    ok = d < 1e-5
    out[ok] = 0.5 * (out[ok] + np.asarray(values, np.float64)[twin[ok]])
    return out


BUILD_CALF_EASE = 0.5      # ... and off the calves (the body's proportions, 2026-11-20)
BUILD_SHOULDER_EASE = 0.85  # the share of the build sliders' push taken off the shoulders and the upper arms


def build_weights(bd, normals, faces, S):
    """((n, 2) signed weights in -1..1: brawn, girth; build_max_m; {"brawn_max_m", "girth_max_m"}).
    The head keeps its shape (the face has sliders of its own, and the eyes, the hair and the beard
    stand on it): the weights fade with the head's own skin weight."""
    n = mh.N_BODY_VERTS
    disp = mh.build_displacements(n)
    V = bd.verts[:n]
    keep = 1.0 - np.clip(bd.masks["m_head"], 0.0, 1.0)
    # the body's proportions (2026-11-20): the shoulders and the upper arms widen less, so the build sliders' ends keep
    # a strong man's shoulders (at +1 they reached 3.7 head widths)
    J = bd.joints
    shz = 0.5 * (J["joint-l-shoulder"][2] + J["joint-r-shoulder"][2])
    sh_x = abs(J["joint-l-shoulder"][0])
    ease = sstep(np.abs(V[:, 0]), sh_x - 0.08, sh_x) * sstep(V[:, 2], shz - 0.45, shz - 0.2)
    # (and the trapezius beside the neck, which at +1 rose round it and buried it)
    ease = np.maximum(ease, sstep(np.abs(V[:, 0]), 0.04, 0.09) * sstep(V[:, 2], shz - 0.12, shz - 0.02))
    keep = keep * (1.0 - BUILD_SHOULDER_EASE * ease)
    # (and the calves, which at +1 bulged like a bodybuilder's past the knee)
    kz = 0.5 * (J["joint-l-knee"][2] + J["joint-r-knee"][2])
    az = 0.5 * (J["joint-l-ankle"][2] + J["joint-r-ankle"][2])
    calf = sstep(V[:, 2], az + 0.02, az + 0.12) * (1.0 - sstep(V[:, 2], kz - 0.02, kz + 0.08))
    keep = keep * (1.0 - BUILD_CALF_EASE * calf)
    proj = {}
    for key in ("brawn", "girth"):
        d = mh.mh_to_blender(disp[key]) * S
        p = np.einsum("ij,ij->i", d, np.asarray(normals, np.float64))
        p = _smooth(p, faces, n, BUILD_SMOOTH) * keep
        proj[key] = _mirror_mean(p, V)
    largest = {k: float(np.abs(v).max()) for k, v in proj.items()}
    build_max = max(largest.values())
    W = np.stack([proj["brawn"], proj["girth"]], axis=1) / build_max
    return np.clip(W, -1.0, 1.0), build_max, {"brawn_max_m": largest["brawn"], "girth_max_m": largest["girth"]}


def encode_build(w):
    """The colour channel value of a signed build weight: 0.5 + 0.5 w."""
    return 0.5 + 0.5 * np.clip(np.asarray(w, np.float64), -1.0, 1.0)


# --------------------------------------------------------------------------------------
# the shadow proxy
# --------------------------------------------------------------------------------------
def shadow_proxy(body, rig, coll, S, triangles=SHADOW_TRIANGLES, name="ShadowProxy", body_V=None, vbuild=None):
    """A copy of the whole body decimated toward ``triangles`` (its vertex groups interpolated by the
    modifier), moved a little inside the skin along its normals, with the build weights (``vbuild`` per
    vertex of ``body_V``, stage-1 metres) of the skin nearest each vertex. Returns the object."""
    ob = body.copy()
    ob.data = body.data.copy()
    ob.name = name
    ob.data.name = name
    coll.objects.link(ob)
    for m in list(ob.modifiers):
        ob.modifiers.remove(m)
    for a in [a.name for a in ob.data.attributes if a.name.startswith("m_") or a.name == "rest_co"]:
        ob.data.attributes.remove(ob.data.attributes[a])
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dec = ob.modifiers.new("Decimate", "DECIMATE")
    dec.decimate_type = "COLLAPSE"
    dec.ratio = triangles / float(tris)
    dec.use_collapse_triangulate = True
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    bpy.context.view_layer.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.modifier_apply(modifier=dec.name)
    me = ob.data
    nv = len(me.vertices)
    co = np.empty(nv * 3)
    me.vertices.foreach_get("co", co)
    nrm = np.empty(nv * 3)
    me.vertex_normals.foreach_get("vector", nrm)
    co = co.reshape(-1, 3) - nrm.reshape(-1, 3) * SHADOW_INSET_M
    me.vertices.foreach_set("co", co.ravel())
    me.update()
    while len(me.uv_layers):
        me.uv_layers.remove(me.uv_layers[0])
    me.materials.clear()
    me.materials.append(bpy.data.materials.get("giant_shadow") or bpy.data.materials.new("giant_shadow"))
    if vbuild is not None:
        # the build weights of the nearest skin: the shadow follows the build sliders, and a slimmer body
        # never leaves its own shadow caster outside it
        from scipy.spatial import cKDTree
        _, near = cKDTree(np.asarray(body_V, np.float64)).query(co + nrm.reshape(-1, 3) * SHADOW_INSET_M)
        col = me.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        rgba = np.zeros((nv, 4), np.float32)
        rgba[:, 0] = 0.5 / 16.0
        rgba[:, 1:3] = encode_build(np.asarray(vbuild)[near])
        rgba[:, 3] = 1.0
        col.data.foreach_set("color", rgba.ravel())
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    return ob


# --------------------------------------------------------------------------------------
# landmarks
# --------------------------------------------------------------------------------------
def hand_landmarks(rig):
    """{"grip_s", "knuckle_s", "toe_s": armature-space points; "grip_local_s": the grip in the hand
    bone's space; "grip_axis_s": the handle's direction through the fist in the hand bone's space
    (unit, from the little finger's side to the forefinger's)} for s in r, l."""
    bones = rig.data.bones

    def head(b):
        return np.asarray(bones[b].head_local, np.float64)

    def tail(b):
        return np.asarray(bones[b].tail_local, np.float64)

    out = {}
    for s in ("r", "l"):
        wrist = head(f"hand_{s}")
        knuckles = [head(f"{f}_01_{s}") for f in ("index", "middle", "ring", "pinky")]
        centre = np.mean(knuckles, axis=0)
        across = unit(knuckles[0] - knuckles[3])                       # little finger -> forefinger
        along = unit(centre - wrist)
        normal = unit(np.cross(across, along))
        if np.dot(tail(f"thumb_03_{s}") - centre, normal) < 0.0:       # toward the palm's side
            normal = -normal
        proximal = float(np.linalg.norm(head(f"middle_02_{s}") - head(f"middle_01_{s}")))
        middle = float(np.linalg.norm(head(f"middle_03_{s}") - head(f"middle_02_{s}")))
        # the closed fist: the first phalanges stand off the palm, the second fold back over the handle
        grip = centre + normal * 0.5 * proximal - along * 0.5 * middle
        M = np.array([list(r) for r in bones[f"hand_{s}"].matrix_local.to_3x3()], np.float64)
        out[f"grip_{s}"] = grip
        out[f"grip_local_{s}"] = M.T @ (grip - wrist)
        out[f"grip_axis_{s}"] = unit(M.T @ across)
        out[f"knuckle_{s}"] = 0.5 * (knuckles[0] + knuckles[1])
        out[f"toe_{s}"] = tail(f"ball_{s}")
    # the two fists' grips mirrored exactly (the body's proportions, 2026-11-20: its reshape left them a micrometre
    # apart, which the six-place index rounded differently)
    m = np.array([-1.0, 1.0, 1.0])
    gl = 0.5 * (out["grip_local_l"] + out["grip_local_r"] * m)
    out["grip_local_l"], out["grip_local_r"] = gl, gl * m
    return out
