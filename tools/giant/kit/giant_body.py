"""The giant's body built in Blender (bpy 5.3) from the vendored CC0 MakeHuman/MPFB2 data.

``build_giant({"height_m": 3.6576})`` makes the rig (the MPFB2 "game_engine" skeleton, 53 bones,
built from the morphed body's joint cubes) and the skinned hm08 body at the given height (object
scales stay 1), with the procedural skin material when asked (the bake). Units: metres, Blender
axes (Z up, the giant faces -Y). The rest-pose coordinates at human scale are kept in the point
attribute ``rest_co`` so procedural detail never swims, and the body's derived masks (scalp,
beard, brows, lips, exposure, ...) are point attributes ``m_*``.

Ported from the M10 research run's frozen kit snapshot. Trimmed to what the game pipeline uses:
no teeth, no Cycles eyes, no strand hair, no poses (the pipeline never poses); the region masks
read the game_engine weights (mh_data.region_masks).
"""
from __future__ import annotations

import os
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mh_data as mh  # noqa: E402

STAGE1_HEIGHT_M = 3.6576   # 12 ft: the game's stage-1 giant; Visual/Body scales it by k per stage

DEFAULT_PARAMS = dict(
    height_m=STAGE1_HEIGHT_M,
    name="Giant",
    macro=None,                # MakeHuman macro sliders (None = mh_data.GIANT_MACRO)
    modifiers=None,            # regional modifiers {"group/category": value} (None = GIANT_MODIFIERS)
    subdiv_render=0,           # Catmull-Clark levels (the bake's high body uses 2)
    subdiv_viewport=0,
    corrective_smooth=False,
    skin=False,                # the procedural skin material (the bake)
    skin_params=None,          # see giant_skin.DEFAULT_SKIN
    collection=None,
)


def log(*a):
    print("[giant_body]", *a, flush=True)


# --------------------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------------------
def _collection(name, parent=None):
    coll = bpy.data.collections.get(name)
    if coll is None:
        coll = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(coll)
    return coll


def new_mesh_object(name, verts, faces, coll, uvs=None, face_uvs=None, smooth=True):
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.asarray(verts, np.float64).tolist(), [], np.asarray(faces).tolist())
    me.update()
    if uvs is not None:
        uvl = me.uv_layers.new(name="UVMap")
        uvl.data.foreach_set("uv", np.asarray(uvs)[np.asarray(face_uvs)].ravel().astype(np.float32))
    if smooth:
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    return ob


def set_point_attr(me, name, values, kind="FLOAT"):
    if name in me.attributes:
        me.attributes.remove(me.attributes[name])
    a = me.attributes.new(name, kind, "POINT")
    vals = np.asarray(values, np.float32)
    a.data.foreach_set("vector" if kind == "FLOAT_VECTOR" else ("color" if kind == "FLOAT_COLOR" else "value"),
                       vals.ravel())
    return a


def add_vertex_groups(ob, weights, index_map=None):
    """weights: {bone: [[vi, w], ...]} in hm08 indices; index_map: hm08 index -> local index."""
    for bone, lst in weights.items():
        vg = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
        for vi, w in lst:
            if index_map is None:
                li = vi
            else:
                li = index_map.get(vi, -1)
            if li >= 0 and w > 1e-4:
                vg.add([int(li)], float(w), "REPLACE")


def armature_modifier(ob, rig, preserve_volume=False):
    m = ob.modifiers.new("Armature", "ARMATURE")
    m.object = rig
    m.use_deform_preserve_volume = preserve_volume
    m.use_vertex_groups = True
    return m


def parent_keep(ob, rig):
    ob.parent = rig
    ob.matrix_parent_inverse = rig.matrix_world.inverted()


# --------------------------------------------------------------------------------------
# skeleton
# --------------------------------------------------------------------------------------
def build_armature(name, rig_json, verts_mh, joints_mh, to_scene, coll):
    arm = bpy.data.armatures.new(name)
    rig = bpy.data.objects.new(name, arm)
    coll.objects.link(rig)
    arm.display_type = "OCTAHEDRAL"
    rig.show_in_front = True
    vl = bpy.context.view_layer
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    order = mh.bone_order(rig_json)
    for bname in order:
        spec = rig_json[bname]
        h = to_scene(mh.bone_point(spec["head"], verts_mh, joints_mh))
        t = to_scene(mh.bone_point(spec["tail"], verts_mh, joints_mh))
        if np.linalg.norm(t - h) < 1e-5:
            t = h + np.array([0.0, 0.0, 0.002])
        eb = arm.edit_bones.new(bname)
        eb.head = Vector(h)
        eb.tail = Vector(t)
        eb.roll = float(spec.get("roll", 0.0))
        p = spec.get("parent", "")
        if p:
            eb.parent = arm.edit_bones[p]
            eb.use_connect = bool(spec.get("use_connect", False))
        eb.use_inherit_rotation = bool(spec.get("use_inherit_rotation", True))
        eb.use_local_location = bool(spec.get("use_local_location", True))
        eb.inherit_scale = spec.get("inherit_scale", "FULL")
        eb.use_deform = True
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in rig.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return rig


# --------------------------------------------------------------------------------------
# body
# --------------------------------------------------------------------------------------
class BodyData:
    """Morphed hm08 data in Blender space (metres, Z up, feet on z=0), human scale."""

    def __init__(self, macro=None, modifiers=None):
        mods = dict(mh.GIANT_MODIFIERS if modifiers is None else modifiers)
        t = time.time()
        self.bm, self.verts_mh, self.target_weights = mh.build_phenotype(macro, mods)
        self.joints_mh = mh.joint_positions(self.bm, self.verts_mh)
        ground = mh.mh_to_blender(self.joints_mh["joint-ground"])
        self.offset = np.array([0.0, 0.0, -ground[2]])
        self.verts = mh.mh_to_blender(self.verts_mh) + self.offset
        self.joints = {k: mh.mh_to_blender(v) + self.offset for k, v in self.joints_mh.items()}
        body = self.verts[: mh.N_BODY_VERTS]
        self.height = float(body[:, 2].max())
        self.masks = {}
        self.landmarks = None
        log(f"phenotype: {len(self.target_weights)} targets, height {self.height:.3f} m "
            f"({time.time() - t:.1f}s)")

    def group(self, name):
        """(vertex indices (hm08), faces (hm08 indices), face uv indices) of a group."""
        if name.endswith("eyelashes"):
            names = [n for n in self.bm.group_names if n.startswith(name)]
        else:
            names = [name]
        fi = np.concatenate([self.bm.group_faces(n) for n in names])
        faces = self.bm.faces[fi]
        return np.unique(faces.ravel()), faces, self.bm.face_uvs[fi]

    def submesh(self, name, vert_filter=None):
        """Local mesh of a group: (verts, faces, uvs, face_uvs, local->hm08 indices)."""
        vids, faces, fuv = self.group(name)
        if vert_filter is not None:
            keep = vert_filter(self.verts[faces])          # (F, 4, 3) -> (F,) bool
            faces, fuv = faces[keep], fuv[keep]
            vids = np.unique(faces.ravel())
        remap = -np.ones(len(self.verts), np.int64)
        remap[vids] = np.arange(len(vids))
        return self.verts[vids], remap[faces], self.bm.uvs, fuv, vids

    def compute_masks(self, weights):
        """The region masks and the derived masks (and the landmarks) of the body."""
        masks = mh.region_masks(weights)
        masks.update(derived_masks(self, masks))
        self.masks = masks
        return masks


def build_body_object(bd: BodyData, name, coll, weights, scale=1.0):
    vids, faces, fuv = bd.group("body")
    ob = new_mesh_object(name, bd.verts[: mh.N_BODY_VERTS] * scale, faces, coll, bd.bm.uvs, fuv)
    me = ob.data
    add_vertex_groups(ob, {b: [e for e in l if e[0] < mh.N_BODY_VERTS] for b, l in weights.items()})
    # rest-pose coordinates (human scale) for procedural textures that must not swim
    set_point_attr(me, "rest_co", bd.verts[: mh.N_BODY_VERTS], "FLOAT_VECTOR")
    masks = bd.masks or bd.compute_masks(weights)
    for k in sorted(masks):
        set_point_attr(me, k, masks[k])
    return ob


def _smooth_mask(bd, values, iterations=3):
    """Laplacian-smooth a per-vertex body scalar over the quad mesh."""
    _, faces, _ = bd.group("body")
    n = mh.N_BODY_VERTS
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(np.float64)
    v = np.asarray(values, np.float64).copy()
    for _ in range(iterations):
        acc = np.bincount(e[:, 0], weights=v[e[:, 1]], minlength=n)
        v = 0.5 * v + 0.5 * acc / np.maximum(deg, 1)
    return v


def _sstep(x, a, b):
    t = np.clip((x - a) / (b - a), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def derived_masks(bd: BodyData, masks):
    """Masks for hair placement and skin detail from landmarks (joints, MPFB UV masks).

    Built in a head frame: azimuth phi (deg) around the vertical axis through the head
    joint, 0 = straight ahead, 90 = the sides, 180 = the back; lengths scale with the head.
    """
    V = bd.verts[: mh.N_BODY_VERTS]
    J = bd.joints
    x, y, z = V[:, 0], V[:, 1], V[:, 2]
    out = {}
    head = masks["m_head"]
    ears = uv_mask(bd, "mpfb_ears.jpg")
    lids = uv_mask(bd, "mpfb_eyelids.jpg")
    lips = uv_mask(bd, "mpfb_lips.jpg")
    mouth_in = uv_mask(bd, "mpfb_inside-mouth.jpg")
    out["m_lips"] = lips
    out["m_ears"] = ears
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    eye_z = 0.5 * (eyeL[2] + eyeR[2])
    cy = J["joint-head"][1]
    top = z.max()
    lipv = V[(lips > 0.5) & (np.abs(x) < 0.01)]
    lip_top, lip_bot = lipv[:, 2].max(), lipv[:, 2].min()
    jaw = J["joint-jaw"]
    facev = V[(np.abs(x) < 0.006) & (y < jaw[1] + 0.012) & (z > J["joint-neck"][2]) & (z < lip_bot)]
    chin = facev[:, 2].min()
    hs = (top - chin) / 0.297                              # head size relative to the reference
    ear_sel = (ears > 0.5)
    ear_zlo, ear_zhi = V[ear_sel, 2].min(), V[ear_sel, 2].max()
    phi = np.degrees(np.arctan2(np.abs(x), -(y - cy)))     # 0 front .. 180 back
    front = phi < 60
    # ---- scalp, natural hairline with slightly receded temples ----------------------
    brow_z = eye_z + 0.018 * hs
    hair_front = brow_z + 0.085 * hs
    tab_phi = [0, 22, 38, 52, 60, 68, 96, 104, 118, 140, 180]
    tab_z = [hair_front, hair_front + 0.008 * hs, hair_front - 0.012 * hs, hair_front - 0.045 * hs,
             ear_zhi + 0.012 * hs, ear_zhi + 0.016 * hs, ear_zhi + 0.012 * hs, ear_zlo + 0.01 * hs,
             ear_zlo - 0.02 * hs, chin + 0.045 * hs, chin + 0.04 * hs]
    zh = np.interp(phi, tab_phi, tab_z)
    scalp = _sstep(z - zh, -0.002 * hs, 0.008 * hs) * (head + masks["m_neck"] > 0.4)
    scalp *= 1.0 - _sstep(ears, 0.3, 0.6)
    out["m_scalp"] = np.clip(_smooth_mask(bd, scalp, 2), 0, 1)
    # ---- beard: mustache, cheeks below the cheek line, chin, jaw, upper throat --------
    subnasale = lip_top + 0.021 * hs
    tab_phi_b = [0, 9, 14, 30, 45, 56, 62, 68]
    tab_zb = [subnasale, subnasale, subnasale + 0.004 * hs, subnasale + 0.014 * hs,
              subnasale + 0.04 * hs, subnasale + 0.075 * hs, ear_zhi + 0.02 * hs, ear_zhi + 0.02 * hs]
    zb = np.interp(phi, tab_phi_b, tab_zb)
    upper = _sstep(zb - z, -0.002 * hs, 0.006 * hs)
    # back edge: in front of the ear above the lobe, wrapping the jaw angle below it
    back_phi = np.where(z > ear_zlo + 0.01 * hs, 66.0, 98.0)
    back = _sstep(back_phi - phi, -2.0, 4.0)
    neck_lo = np.interp(phi, [0, 40, 80, 100], [chin - 0.035 * hs, chin - 0.028 * hs,
                                                 chin + 0.02 * hs, chin + 0.04 * hs])
    lower = _sstep(z - neck_lo, -0.004 * hs, 0.01 * hs)
    beard = upper * back * lower * ((head + masks["m_neck"]) > 0.3)
    beard *= (1.0 - _sstep(lips, 0.15, 0.5)) * (1.0 - _sstep(ears, 0.2, 0.5))
    beard *= (1.0 - _sstep(mouth_in, 0.2, 0.5)) * (1.0 - _sstep(lids, 0.2, 0.5))
    out["m_beard"] = np.clip(_smooth_mask(bd, beard, 2), 0, 1)
    out["m_mustache"] = out["m_beard"] * (z > lip_bot) * _sstep(30 - phi, 0, 8)
    # ---- eyebrows: a band above each eye along the brow ridge -------------------------
    brow = np.zeros(len(V))
    for eye, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        lx = (x - eye[0]) * sgn / hs                      # + = lateral
        arc_z = eye[2] + hs * (0.021 + 0.004 * np.cos(np.clip(lx / 0.03, -1.5, 1.5))
                               - 0.004 * _sstep(lx, 0.012, 0.03))
        dz = (z - arc_z) / hs
        band = _sstep(0.0085 - np.abs(dz + 0.001 * lx / 0.03), 0.0, 0.004)
        along = _sstep(lx, -0.03, -0.019) * (1 - _sstep(lx, 0.024, 0.034))
        brow = np.maximum(brow, band * along * front)
    out["m_brow"] = np.clip(brow, 0, 1)
    # ---- skin-detail regions ------------------------------------------------------------
    fh = _sstep(z - (brow_z + 0.012 * hs), 0.0, 0.01 * hs) * (1 - out["m_scalp"]) * _sstep(48 - phi, 0, 10)
    out["m_forehead"] = np.clip(fh * (head > 0.5), 0, 1)
    face_y = V[(np.abs(x) < 0.01) & (np.abs(z - eye_z) < 0.01 * hs), 1].min()
    crow = np.zeros(len(V))
    under = np.zeros(len(V))
    cheek = np.zeros(len(V))
    for eye, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        c = np.array([eye[0] + sgn * 0.027 * hs, face_y + 0.035 * hs, eye[2] - 0.002 * hs])
        crow = np.maximum(crow, 1 - _sstep(np.linalg.norm(V - c, axis=1), 0.008 * hs, 0.022 * hs))
        c = np.array([eye[0], face_y + 0.012 * hs, eye[2] - 0.026 * hs])
        under = np.maximum(under, 1 - _sstep(np.linalg.norm((V - c) * [1.0, 1.6, 2.0], axis=1), 0.006 * hs, 0.018 * hs))
        c = np.array([eye[0] + sgn * 0.016 * hs, face_y + 0.03 * hs, eye[2] - 0.045 * hs])
        cheek = np.maximum(cheek, 1 - _sstep(np.linalg.norm(V - c, axis=1), 0.01 * hs, 0.035 * hs))
    out["m_crow"] = crow * (head > 0.5) * (1 - lids)
    out["m_undereye"] = under * (1 - lids) * front
    out["m_cheek"] = cheek * front * (1 - out["m_beard"])
    nose_c = np.array([0.0, face_y - 0.012 * hs, subnasale + 0.022 * hs])
    out["m_nose"] = (1 - _sstep(np.linalg.norm((V - nose_c) * [1.3, 0.8, 0.7], axis=1), 0.012 * hs, 0.03 * hs)) * front
    out["m_neckfront"] = masks["m_neck"] * _sstep(cy - y, -0.01, 0.03) * (1 - out["m_beard"])
    kn = np.zeros(len(V))
    for k, p in J.items():
        if "finger" in k and k[-1] in "234":
            kn = np.maximum(kn, 1 - _sstep(np.linalg.norm(V - p, axis=1), 0.004, 0.012))
    out["m_knuckles"] = kn * masks["m_hand"]
    out["m_nails"] = np.clip(uv_mask(bd, "mpfb_fingernails.jpg") + uv_mask(bd, "mpfb_toenails.jpg"), 0, 1)
    out["m_exposure"] = np.clip(
        1.0 * head + 0.9 * masks["m_neck"] + 1.0 * masks["m_hand"] + 0.85 * masks["m_forearm"]
        + 0.6 * masks["m_upperarm"] + 0.45 * masks["m_torso"] + 0.4 * masks["m_lowerleg"]
        + 0.5 * masks["m_foot"] + 0.25 * masks["m_upperleg"], 0, 1)
    temple = np.zeros(len(V))
    for eye, sgn in ((eyeL, 1.0), (eyeR, -1.0)):
        c = np.array([sgn * 0.085 * hs, eye[1] + 0.045 * hs, eye[2] + 0.03 * hs])
        temple = np.maximum(temple, 1 - _sstep(np.linalg.norm(V - c, axis=1), 0.008 * hs, 0.025 * hs))
    out["m_veins"] = np.clip(1.0 * masks["m_forearm"] + 0.9 * masks["m_hand"] + 0.55 * masks["m_upperarm"]
                             + 0.5 * masks["m_foot"] + 0.35 * masks["m_lowerleg"]
                             + 0.6 * temple * (1 - out["m_scalp"]) + 0.3 * out["m_neckfront"], 0, 1)
    out["m_mouth_inside"] = mouth_in
    # chest hair: over the pectorals and sternum, a trail down the midline to the navel
    sp1, sp2, sp4 = J["joint-spine-1"], J["joint-spine-2"], J["joint-spine-4"]
    torso_front = (y < sp2[1] - 0.06) & (masks["m_torso"] + masks["m_pelvis"] > 0.3)
    chest = _sstep(z - (sp2[2] - 0.01), 0.0, 0.05) * (1 - _sstep(z - (sp1[2] + 0.02), 0.0, 0.05))
    chest *= 1 - _sstep(np.abs(x), 0.07, 0.17)
    trail = _sstep(z - (sp4[2] - 0.07), 0.0, 0.03) * (1 - _sstep(z - sp2[2], 0.0, 0.03))
    trail *= 1 - _sstep(np.abs(x), 0.012, 0.035)
    out["m_chesthair"] = np.clip(_smooth_mask(bd, np.maximum(chest, trail) * torso_front, 3), 0, 1)
    lid_sel = lids > 0.5
    cL = V[lid_sel & (x > 0)][np.argmax(V[lid_sel & (x > 0), 0])]
    cR = V[lid_sel & (x < 0)][np.argmin(V[lid_sel & (x < 0), 0])]
    cIL = V[lid_sel & (x > 0)][np.argmin(V[lid_sel & (x > 0), 0])]
    cIR = V[lid_sel & (x < 0)][np.argmax(V[lid_sel & (x < 0), 0])]
    bd.landmarks = dict(canthus_L=cL.tolist(), canthus_R=cR.tolist(), inner_canthus_L=cIL.tolist(),
                        inner_canthus_R=cIR.tolist(), eye_L=eyeL.tolist(), eye_R=eyeR.tolist(),
                        eye_z=float(eye_z), lip_top=float(lip_top), lip_bot=float(lip_bot), chin=float(chin),
                        top=float(top), subnasale=float(subnasale), head_cy=float(cy), hs=float(hs),
                        ear_z=(float(ear_zlo), float(ear_zhi)), face_y=float(face_y), brow_z=float(brow_z))
    return out


def uv_mask(bd, tex):
    """Per-vertex value of an MPFB UV-space mask texture (textures/<tex>)."""
    from PIL import Image
    im = np.asarray(Image.open(os.path.join(mh.MPFB_DIR, "textures", tex)).convert("L"),
                    np.float32) / 255.0
    _, faces, fuv = bd.group("body")
    uv = bd.bm.uvs
    val = np.zeros(mh.N_BODY_VERTS)
    cnt = np.zeros(mh.N_BODY_VERTS)
    h, w = im.shape
    for c in range(4):
        u = uv[fuv[:, c]]
        px = np.clip((u[:, 0] * (w - 1)).astype(int), 0, w - 1)
        py = np.clip(((1 - u[:, 1]) * (h - 1)).astype(int), 0, h - 1)
        np.add.at(val, faces[:, c], im[py, px])
        np.add.at(cnt, faces[:, c], 1)
    return val / np.maximum(cnt, 1)


def add_body_modifiers(ob, rig, p):
    armature_modifier(ob, rig)
    if p["corrective_smooth"]:
        cs = ob.modifiers.new("CorrectiveSmooth", "CORRECTIVE_SMOOTH")
        cs.rest_source = "ORCO"
        cs.smooth_type = "LENGTH_WEIGHTED"
        cs.iterations = 6
        cs.factor = 0.5
        cs.use_only_smooth = False
        cs.use_pin_boundary = True
    if p["subdiv_render"] or p["subdiv_viewport"]:
        ss = ob.modifiers.new("Subdivision", "SUBSURF")
        ss.levels = p["subdiv_viewport"]
        ss.render_levels = p["subdiv_render"]
        ss.quality = 3
        ss.uv_smooth = "PRESERVE_BOUNDARIES"
        ss.boundary_smooth = "ALL"


def eye_frames(bd, scale=1.0):
    """Centre, radius and gaze direction of each eye from the helper eyes and eye joints."""
    out = {}
    for side, grp in (("L", "helper-l-eye"), ("R", "helper-r-eye")):
        vids, _, _ = bd.group(grp)
        P = bd.verts[vids]
        c = P.mean(axis=0)
        r = float(np.linalg.norm(P - c, axis=1).mean())
        j = bd.joints[f"joint-{side.lower()}-eye"]
        tgt = bd.joints[f"joint-{side.lower()}-eye-target"]
        g = tgt - j
        g /= np.linalg.norm(g)
        out[side] = (c * scale, r * scale, g)
    return out


# --------------------------------------------------------------------------------------
# main entry point
# --------------------------------------------------------------------------------------
def build_giant(params=None, bd=None, weights=None):
    """Build the giant at its final size (object scales stay 1). Returns a dict: rig (the
    armature), body, bd (the BodyData), weights, info (heights, scale factor, landmarks)."""
    p = dict(DEFAULT_PARAMS)
    p.update(params or {})
    t0 = time.time()
    name = p["name"]
    coll = p["collection"] or _collection(name)
    bd = bd or BodyData(p["macro"], p["modifiers"])
    weights = weights or mh.load_weights()
    if not bd.masks:
        bd.compute_masks(weights)
    S = p["height_m"] / bd.height
    bd.scale = S
    rig_json = mh.load_rig()
    to_scene = lambda p_mh: (mh.mh_to_blender(p_mh) + bd.offset) * S  # noqa: E731
    rig = build_armature(f"{name}_rig", rig_json, bd.verts_mh, bd.joints_mh, to_scene, coll)
    body = build_body_object(bd, f"{name}_body", coll, weights, S)
    parent_keep(body, rig)
    add_body_modifiers(body, rig, p)
    info = {"human_height_m": bd.height, "height_m": p["height_m"], "scale": S, "landmarks": bd.landmarks}
    rig["giant_height_m"] = p["height_m"]
    rig["giant_scale"] = S
    if p["skin"]:
        import giant_skin as gs
        mat = gs.make_skin_material(f"{name}_skin", S, p["skin_params"], bd)
        body.data.materials.append(mat)
        info["skin_material"] = mat.name
    bpy.context.view_layer.update()
    log(f"built {name}: {p['height_m']:.4f} m (x{S:.4f} of the {bd.height:.3f} m MakeHuman body) "
        f"in {time.time() - t0:.1f}s")
    return {"rig": rig, "body": body, "bd": bd, "weights": weights, "info": info, "collection": coll}
