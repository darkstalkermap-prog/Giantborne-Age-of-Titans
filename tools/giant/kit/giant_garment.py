"""The giant's seven garments as separate skinned meshes on the body's skeleton.

* ``braies`` (loose linen short trousers) cut from MakeHuman's fitted "tights" helper, loosened and
  folded, and ``belt``, a leather band round the waist - the kit's garment (giant_garment.py of the
  research run's frozen kit snapshot);
* ``tunic``, ``jerkin``, ``bracers``, ``boots`` and ``furs``: shells cut from the body surface by
  bone-weight regions and pushed out along the normals, with the body's UVs and the body's weights
  copied per vertex, so they skin exactly like the skin under them (the research's export script).

Every garment keeps, per vertex, the hm08 body vertex it sits on (``body_vertex``), so the export
can split it at the body's head / torso / limbs boundary and cap its cut loops. Materials are
placeholders: the game draws garments with its own cloth shader.
"""
from __future__ import annotations

import math

import bpy
import numpy as np

import giant_body as gb
import mh_data as mh
from split import bone_sums

BRAIES = dict(
    top_z=1.535,          # human-scale cut heights (m, the 2.45 m body)
    knee_offset=0.13,     # bottom hem this far above the knee joint
    looseness=0.03,       # m pushed out from the skin (thighs), human scale
    fold_depth=0.013,
    belt_height=0.065,
    belt_thickness=0.006,
    thickness=0.004,
)
BOOTS_TRIANGLES = 2500    # the research boots had 4,688 triangles (dense toes): decimated toward this
# The garments' detail maps (the cloth shader's detail_tex) and dye slots (plan §2.5 index).
DETAIL = {"braies": "weave", "tunic": "weave", "belt": "leather", "jerkin": "leather",
          "bracers": "leather", "boots": "leather", "furs": "fur"}
DYE = {"braies": "primary", "tunic": "primary", "belt": "secondary", "jerkin": "secondary",
       "bracers": "secondary", "boots": "secondary", "furs": "none"}
ORDER = ("braies", "belt", "tunic", "jerkin", "bracers", "boots", "furs")


def vnormals(verts, faces):
    fn = np.cross(verts[faces[:, 2]] - verts[faces[:, 0]], verts[faces[:, 3]] - verts[faces[:, 1]])
    vn = np.zeros_like(verts)
    for c in range(4):
        np.add.at(vn, faces[:, c], fn)
    return vn / (np.linalg.norm(vn, axis=1, keepdims=True) + 1e-12)


def smooth_field(values, faces, n, it=4):
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.bincount(e[:, 0], minlength=n).astype(float)
    v = values.astype(float).copy()
    for _ in range(it):
        acc = np.bincount(e[:, 0], weights=v[e[:, 1]], minlength=n)
        v = 0.5 * v + 0.5 * acc / np.maximum(deg, 1)
    return v


def _placeholder(name):
    return bpy.data.materials.get(name) or bpy.data.materials.new(name)


def _skin_from_body(ob, weights, body_ids):
    """Vertex groups copied from the hm08 body vertices ``body_ids`` (one per local vertex)."""
    inv = {}
    for bone, lst in weights.items():
        for vi, w in lst:
            if vi < mh.N_BODY_VERTS:
                inv.setdefault(vi, []).append((bone, w))
    for li, vi in enumerate(body_ids):
        for bone, w in inv.get(int(vi), []):
            if w > 1e-4:
                vg = ob.vertex_groups.get(bone) or ob.vertex_groups.new(name=bone)
                vg.add([li], float(w), "REPLACE")


def shell(name, coll, rig, body_V, body_N, faces, fuv, uvs, keep_vert, offset, weights, S, mat_name,
          seed=0, hem_noise=0.0):
    """A garment: the body faces whose 4 vertices pass `keep_vert`, pushed out along the
    normals by `offset` (per body vertex, human-scale metres), body UVs and body weights."""
    keep = np.all(keep_vert[faces], axis=1)
    F = faces[keep]
    FU = fuv[keep]
    used = np.unique(F.ravel())
    remap = -np.ones(len(body_V), np.int64)
    remap[used] = np.arange(len(used))
    V = body_V[used] + body_N[used] * offset[used][:, None]
    if hem_noise > 0:
        # ragged hem: boundary vertices pulled along the surface by noise
        E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 3]], F[:, [3, 0]]])
        E.sort(axis=1)
        u, c = np.unique(E, axis=0, return_counts=True)
        bv = np.unique(u[c == 1].ravel())
        rng = np.random.default_rng(seed)
        V[remap[bv], 2] -= hem_noise * rng.random(len(bv))
    ob = gb.new_mesh_object(name, V * S, remap[F], coll, uvs, FU)
    m = {int(v): i for i, v in enumerate(used)}
    gb.add_vertex_groups(ob, weights, m)
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(_placeholder(mat_name))
    return ob, used


def build_braies(bd, rig, coll, weights, S, p=None):
    """The kit's braies and belt (no subdivision, no solidify on the braies; the belt solidified)."""
    from scipy.spatial import cKDTree
    p = dict(BRAIES, **(p or {}))
    J = bd.joints
    knee_z = 0.5 * (J["joint-l-knee"][2] + J["joint-r-knee"][2])
    z_lo, z_hi = knee_z + p["knee_offset"], p["top_z"]
    # the tights helper is a full body suit: keep the hips and thighs, not the sleeves
    arm = np.zeros(len(bd.verts))
    for bone, lst in weights.items():
        if bone.startswith(("upperarm", "lowerarm", "wrist", "finger", "metacarpal", "shoulder", "clavicle")):
            for vi, w in lst:
                arm[vi] += w
    tights_ids = np.arange(mh.GROUP_RANGES["helper-tights"][0], mh.GROUP_RANGES["helper-tights"][1] + 1)
    vmask = np.zeros(len(bd.verts), bool)
    vmask[tights_ids] = arm[tights_ids] < 0.05
    verts, faces, uvs, fuv, vids = bd.submesh(
        "helper-tights", lambda F: np.all((F[:, :, 2] > z_lo) & (F[:, :, 2] < z_hi)
                                          & (np.abs(F[:, :, 0]) < 0.32), axis=1))
    keep = np.all(vmask[vids][faces], axis=1)
    faces, fuv = faces[keep], fuv[keep]
    used = np.unique(faces.ravel())
    remap_local = -np.ones(len(verts), np.int64)
    remap_local[used] = np.arange(len(used))
    verts, faces, vids = verts[used], remap_local[faces], vids[used]
    vn = vnormals(verts, faces)
    # looseness: cinched at the waist, loose on the thighs, a little flare at the hem
    t = np.clip((verts[:, 2] - z_lo) / (z_hi - z_lo), 0, 1)
    loose = p["looseness"] * (0.35 + 0.65 * np.sin(np.pi * np.clip(t * 1.15, 0, 1)) ** 0.7)
    loose = np.where(t > 0.88, p["looseness"] * 0.25, loose)
    # vertical folds: sum of sines around each leg / the hips
    ang = np.arctan2(verts[:, 1], np.abs(verts[:, 0]) - 0.1)
    rng = np.random.default_rng(3)
    folds = np.zeros(len(verts))
    for k, a in ((5, 1.0), (9, 0.5), (14, 0.3)):
        ph = rng.random() * 6.28
        folds += a * np.sin(k * ang + ph + 6.0 * verts[:, 2])
    folds *= p["fold_depth"] * (1.0 - 0.8 * (t > 0.85)) * (0.4 + 0.6 * (1 - t))
    out_v = verts + vn * (loose + np.maximum(folds, -loose * 0.6))[:, None]
    # straighten the stair-stepped cut: snap boundary vertices to the waist / hem heights
    E = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
    E.sort(axis=1)
    u, c = np.unique(E, axis=0, return_counts=True)
    bverts = np.unique(u[c == 1].ravel())
    zb = out_v[bverts, 2]
    mid = 0.5 * (z_lo + z_hi)
    top = bverts[zb > mid]
    bot = bverts[zb <= mid]
    out_v[top, 2] = z_hi - 0.004
    hem = z_lo + 0.012 + 0.004 * np.sin(np.arctan2(out_v[bot, 1], np.abs(out_v[bot, 0]) - 0.1) * 7.0)
    out_v[bot, 2] = hem
    ob = gb.new_mesh_object("Garment_braies", out_v * S, faces, coll, uvs, fuv)
    remap = {int(v): i for i, v in enumerate(vids)}
    gb.add_vertex_groups(ob, weights, remap)
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(_placeholder("giant_cloth"))
    body_v = bd.verts[: mh.N_BODY_VERTS]
    kd = cKDTree(body_v)
    _, braies_body = kd.query(out_v)
    # ---- belt: a band around the waist, offset from the cloth -------------------------
    band_h = p["belt_height"]
    zc = z_hi - band_h * 0.42
    n_seg = 96
    centre = np.array([0.0, J["joint-pelvis"][1] + 0.02, zc])
    band = out_v[np.abs(out_v[:, 2] - zc) < band_h * 0.6]
    rel = band[:, :2] - centre[:2]
    ang_c = np.arctan2(rel[:, 0], -rel[:, 1])
    rad_c = np.linalg.norm(rel, axis=1)
    ring = []
    for i in range(n_seg):
        a = 2 * math.pi * i / n_seg
        d = np.array([math.sin(a), -math.cos(a), 0.0])
        dang = np.abs((ang_c - a + math.pi) % (2 * math.pi) - math.pi)
        sel = dang < 0.12
        r = rad_c[sel].max() if sel.any() else 0.2
        ring.append(centre + d * (r + p["thickness"] + 0.003))
    ring = np.array(ring)
    for _ in range(3):
        ring = 0.5 * ring + 0.25 * (np.roll(ring, 1, axis=0) + np.roll(ring, -1, axis=0))
    bv = np.concatenate([ring + [0, 0, -band_h / 2], ring + [0, 0, band_h / 2]])
    bf = [(i, (i + 1) % n_seg, n_seg + (i + 1) % n_seg, n_seg + i) for i in range(n_seg)]
    belt = gb.new_mesh_object("Garment_belt", bv * S, np.array(bf), coll)
    _, belt_body = kd.query(bv)
    _skin_from_body(belt, weights, belt_body)
    gb.parent_keep(belt, rig)
    sol = belt.modifiers.new("Solidify", "SOLIDIFY")
    sol.thickness = p["belt_thickness"] * S
    sol.offset = 1.0
    gb.armature_modifier(belt, rig)
    belt.data.materials.append(_placeholder("giant_leather"))
    return {"braies": (ob, braies_body), "belt": (belt, belt_body)}


def build_shells(bd, rig, coll, weights, S):
    """tunic, jerkin, bracers, boots, furs: {name: (object, body vertex per local vertex)}."""
    n = mh.N_BODY_VERTS
    _, faces, fuv = bd.group("body")
    V = bd.verts[:n]
    N = vnormals(V, faces)
    B = bone_sums(weights, n)
    J = bd.joints
    z = V[:, 2]
    knee = 0.5 * (J["joint-l-knee"][2] + J["joint-r-knee"][2])
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    ankle = 0.5 * (J["joint-l-ankle"][2] + J["joint-r-ankle"][2])
    shoulder = 0.5 * (J["joint-l-shoulder"][2] + J["joint-r-shoulder"][2])
    neck_z = J["joint-neck"][2]
    elbow = J["joint-l-elbow"]
    wrist = J["joint-l-hand"]
    torso = B["spine3"] + B["spine2"] + B["spine1"] + B["clav"]
    out = {}
    # tunic: torso, short sleeves, a skirt to mid-thigh
    mid_thigh = knee + 0.55 * (hip - knee)
    sleeve = B["upperarm"] * (np.abs(V[:, 0]) < abs(J["joint-l-shoulder"][0]) + 0.6 * abs(elbow[0] - J["joint-l-shoulder"][0]))
    keep = ((torso + B["pelvis"] + sleeve + B["thigh"] * (z > mid_thigh)) > 0.55) & (B["neck"] < 0.35) \
        & (B["head"] < 0.05) & (B["lowerarm"] < 0.3) & (B["hand"] < 0.05) & (z > mid_thigh)
    off = 0.022 + 0.018 * np.clip((hip - z) / (hip - mid_thigh), 0, 1)
    out["tunic"] = shell("Garment_tunic", coll, rig, V, N, faces, fuv, bd.bm.uvs, keep, off, weights, S, "giant_cloth")
    # jerkin: a sleeveless leather vest over the tunic
    keep = (torso + B["pelvis"] * (z > hip + 0.06) > 0.6) & (B["upperarm"] < 0.25) & (B["neck"] < 0.3) \
        & (z > hip + 0.05) & (B["head"] < 0.02)
    out["jerkin"] = shell("Garment_jerkin", coll, rig, V, N, faces, fuv, bd.bm.uvs, keep,
                          np.full(n, 0.045), weights, S, "giant_leather")
    # bracers on both forearms
    Vm = np.abs(V) * [1, 0, 0] + V * [0, 1, 1]          # mirror the right arm onto the left
    seg = wrist - elbow
    t_arm = np.einsum("ij,j->i", Vm - elbow, seg) / np.dot(seg, seg)
    keep = (B["lowerarm"] > 0.5) & (t_arm > 0.3) & (t_arm < 0.9)
    out["bracers"] = shell("Garment_bracers", coll, rig, V, N, faces, fuv, bd.bm.uvs, keep,
                           np.full(n, 0.012), weights, S, "giant_leather")
    # boots: feet and the lower shins
    keep = ((B["foot"] > 0.3) | ((B["calf"] > 0.5) & (z < ankle + 0.5 * (knee - ankle)))) & (z < ankle + 0.5 * (knee - ankle))
    out["boots"] = shell("Garment_boots", coll, rig, V, N, faces, fuv, bd.bm.uvs, keep,
                         np.full(n, 0.014), weights, S, "giant_leather")
    # furs: a mantle over the shoulders, upper back and upper chest
    keep = ((B["spine3"] + B["clav"] + B["upperarm"] * (z > shoulder - 0.06) + B["neck"] * 0.6) > 0.45) \
        & (z > shoulder - 0.16) & (B["head"] < 0.02) & (z < neck_z + 0.02) & (B["lowerarm"] < 0.05)
    rng = np.random.default_rng(5)
    fur_off = 0.05 + 0.02 * smooth_field(rng.random(n), faces, n, 2)
    out["furs"] = shell("Garment_furs", coll, rig, V, N, faces, fuv, bd.bm.uvs, keep, fur_off, weights, S,
                        "giant_fur", seed=7, hem_noise=0.03)
    return out
