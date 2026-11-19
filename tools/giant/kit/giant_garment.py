"""The giant's garments and accessories as separate skinned meshes on the body's skeleton.

M10's ten garments (the floor's seven and the look pass's three) and the wardrobe of P54 (plan M11 §2.6, §3.7):
35 garments in ten slots and 8 accessories.

* ``braies`` (loose linen short trousers) cut from MakeHuman's fitted "tights" helper, loosened and
  folded, and ``belt``, a leather band round the waist - the kit's garment (giant_garment.py of the
  research run's frozen kit snapshot); the plated war belt and the sash are bands of the same kind;
* every other garment but the cloaks is a shell cut from the body surface by bone-weight regions and pushed
  out along the normals, with the body's UVs and the body's weights copied per vertex, so it skins exactly
  like the skin under it (the research's export script);
* the cape, the long cloak and the fur cloak hang free on the three cape chains (P48), the long ones
  lengthened below the body's cut;
* the accessories are rigid meshes on one bone each (a torc on ``spine_03``, an arm ring on ``upperarm_l``, a
  trophy on ``pelvis``), at most 400 triangles.

**Slots and shells (P54).** A garment belongs to one slot; a slot has a least standoff from the skin at stage 1
(``SLOT_SHELL_M``, the plan's table), and the slots are layered in ``LAYER_ORDER``, the innermost first. The
wardrobe is built slot by slot: after a slot, the cumulative envelope (per body vertex, the farthest any garment
built so far stands off the skin along its normal) grows by the slot's garments, and every garment of a later
slot keeps at least ``LAYER_GAP_M`` outside that envelope wherever it covers the same skin, the step eased into
a ramp of slope ``RAMP_SLOPE``. So two garments of different slots never share a surface, whichever two are
worn together: an outer shell clears the loosest inner one of every inner slot. A shell's vertex carries the
weights of the body vertex it stands on, so the order holds under the skin's linear blend in any pose (the
export measures it in four poses: ``shell_distances``).

Every garment keeps, per vertex, the hm08 body vertex it sits on (``body_vertex``), so the export
can split it at the body's head / torso / limbs boundary and cap its cut loops. Materials are
placeholders: the game draws garments with its own cloth shader.
"""
from __future__ import annotations

import math

import bpy
import numpy as np
from mathutils.bvhtree import BVHTree

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

# ---- slots (plan M11 §2.6) ---------------------------------------------------------------------------------
# The least standoff of a slot's shells from the skin, stage-1 metres (the plan's table). The cape hangs free.
SLOT_SHELL_M = {"legs": 0.012, "chest": 0.014, "shins": 0.020, "feet": 0.024, "arms": 0.022, "waist": 0.030,
                "armour": 0.034, "shoulders": 0.046, "head": 0.020, "cape": 0.030}
# The slots from the skin out. The plan's offsets give the order of the eight shell slots; the cape lies over the
# armour and under the shoulders (a mantle or a pauldron over a cloak's top), and the head garments over all
# (their footprint begins above the collars).
LAYER_ORDER = ("legs", "chest", "shins", "arms", "feet", "waist", "armour", "cape", "shoulders", "head")
LAYER_GAP_M = 0.012        # stage 1: an outer slot's shell over an inner slot's envelope (the test's floor: 0.004; the skin's
#                            linear blend shortens a shell's offset where two bones share it, a third at a raised shoulder)
RAMP_SLOPE = 0.8           # how fast that clearance eases off beyond the inner garment's edge (m a m)
ENV_REACH_M = 0.30         # stage 1: the longest skin-to-garment ray of a ray-cast envelope
MAPPED_MARGIN_M = 0.005    # stage 1: added to an envelope measured over the nearest skin vertex (not a shell's own)
HANG_MARGIN_M = 0.050      # stage 1: a cloak's hanging cloth keeps this much more over what lies under it (it hangs
#                            from the chains, the back under it moves with the spine and the hips)
DECIMATE_MARGIN_M = 0.004  # stage 1: a decimated shell's allowance (the collapse pulls its surface in a little)


def _g(slot, material, detail, dye, part, name, **kw):
    return dict(slot=slot, material=material, detail=detail, dye=dye, part=part, name=name, **kw)


# Every garment: its slot, its material (the record's dye family: cloth, leather, fur, metal), its detail map,
# its M10 dye slot (the legacy look's primary / secondary; "none" keeps its colour), the body part it is drawn
# with ("split": cut at the torso / limbs boundary, two meshes; "torso", "limbs", "head": one) and its name.
# A head garment's hides_hair: "all" (no hair under it), "top" (the hair is cut by length where it would show
# through: the index's hair_cut, measured by the export).
GARMENTS = {
    # legs (0.012)
    "braies": _g("legs", "cloth", "weave", "primary", "split", "Braies"),
    "trousers": _g("legs", "cloth", "weave", "primary", "split", "Trousers"),
    "kilt": _g("legs", "cloth", "weave", "primary", "split", "Kilt"),
    "loincloth": _g("legs", "cloth", "weave", "primary", "torso", "Loincloth"),
    # chest (0.014)
    "tunic": _g("chest", "cloth", "weave", "primary", "split", "Tunic"),
    "shirt": _g("chest", "cloth", "weave", "primary", "split", "Shirt"),
    "sleeveless_vest": _g("chest", "leather", "leather", "secondary", "torso", "Sleeveless vest"),
    "chest_wrap": _g("chest", "cloth", "weave", "primary", "torso", "Chest wrap"),
    # shins (0.020)
    "leg_wraps": _g("shins", "cloth", "weave", "primary", "limbs", "Leg wraps"),
    "greaves": _g("shins", "metal", "metal", "metal", "limbs", "Greaves"),
    # arms (0.022)
    "bracers": _g("arms", "leather", "leather", "secondary", "limbs", "Bracers"),
    "iron_vambraces": _g("arms", "metal", "metal", "metal", "limbs", "Iron vambraces"),
    "arm_wraps": _g("arms", "cloth", "weave", "primary", "limbs", "Arm wraps"),
    # feet (0.024)
    "boots": _g("feet", "leather", "leather", "secondary", "limbs", "Boots"),
    "wrapped_sandals": _g("feet", "leather", "leather", "secondary", "limbs", "Wrapped sandals"),
    # waist (0.030)
    "belt": _g("waist", "leather", "leather", "secondary", "torso", "Belt"),
    "war_belt": _g("waist", "metal", "metal", "metal", "torso", "Plated war belt"),
    "sash": _g("waist", "cloth", "weave", "primary", "torso", "Sash"),
    # armour (0.034)
    "jerkin": _g("armour", "leather", "leather", "secondary", "torso", "Jerkin"),
    "mail_hauberk": _g("armour", "metal", "mail", "metal", "torso", "Mail hauberk"),
    "leather_cuirass": _g("armour", "leather", "leather", "secondary", "torso", "Leather cuirass"),
    "scale_coat": _g("armour", "metal", "scale", "metal", "torso", "Scale coat"),
    "bronze_breastplate": _g("armour", "metal", "metal", "metal", "torso", "Bronze breastplate"),
    # cape (free)
    "cape": _g("cape", "cloth", "weave", "primary", "torso", "Cape", free=True),
    "long_cloak": _g("cape", "cloth", "weave", "primary", "torso", "Long cloak", free=True),
    "fur_cloak": _g("cape", "fur", "fur", "none", "torso", "Fur cloak", free=True),
    # shoulders (0.046)
    "furs": _g("shoulders", "fur", "fur", "none", "torso", "Furs"),
    "pauldron": _g("shoulders", "leather", "leather", "secondary", "torso", "Pauldron"),
    "fur_mantle": _g("shoulders", "fur", "fur", "none", "torso", "Fur mantle"),
    "iron_pauldrons": _g("shoulders", "metal", "metal", "metal", "torso", "Iron pauldrons"),
    "bone_spaulders": _g("shoulders", "fur", "bone", "none", "torso", "Bone spaulders"),
    # head (0.020)
    "hood": _g("head", "cloth", "weave", "primary", "head", "Hood", hides_hair="all"),
    "leather_cap": _g("head", "leather", "leather", "secondary", "head", "Leather cap", hides_hair="top"),
    "iron_helm": _g("head", "metal", "metal", "metal", "head", "Iron helm", hides_hair="top"),
    "horned_helm": _g("head", "metal", "metal", "metal", "head", "Horned helm", hides_hair="top"),
}
# M10's ten, in their M10 order (the creator's and the oracle's), then P54's 25 in the plan's build order (the cut
# list's reverse, plan §6.3), then the rest of the slot.
M10_ORDER = ("braies", "belt", "tunic", "jerkin", "bracers", "boots", "furs", "cape", "leg_wraps", "pauldron")
NEW_ORDER = ("loincloth", "trousers", "kilt", "hood", "mail_hauberk", "leather_cuirass", "iron_pauldrons",
             "iron_vambraces", "greaves", "long_cloak", "shirt", "sleeveless_vest", "war_belt", "fur_mantle",
             "leather_cap", "iron_helm", "fur_cloak", "arm_wraps", "chest_wrap", "sash", "wrapped_sandals",
             "bronze_breastplate", "scale_coat", "horned_helm", "bone_spaulders")
ORDER = M10_ORDER + NEW_ORDER
# The garments the plan's cut list names, last cut first (§6.3: what is cut first goes last).
CUT_LIST = ("bone_spaulders", "horned_helm", "scale_coat", "bronze_breastplate", "wrapped_sandals", "sash",
            "chest_wrap", "arm_wraps")
DETAIL = {g: s["detail"] for g, s in GARMENTS.items()}
DYE = {g: s["dye"] for g, s in GARMENTS.items()}

# ---- accessories (plan M11 §2.6: neck, arm_ring, belt) ----------------------------------------------------------
# slot, bone, detail map (metal: the cloth shader's metal response; bone: its bone kind), natural colour (sRGB).
ACCESSORIES = {
    "iron_torc": dict(slot="neck", bone="spine_03", detail="metal", color="#6b6e72", name="Iron torc"),
    "gilded_torc": dict(slot="neck", bone="spine_03", detail="metal", color="#c49a3a", name="Gilded torc"),
    "tooth_necklace": dict(slot="neck", bone="spine_03", detail="bone", color="#d8ccb0", name="Tooth necklace"),
    "iron_arm_ring": dict(slot="arm_ring", bone="upperarm_l", detail="metal", color="#6b6e72", name="Iron arm ring"),
    "bronze_arm_spiral": dict(slot="arm_ring", bone="upperarm_l", detail="metal", color="#a5713c",
                              name="Bronze arm spiral"),
    "gilded_arm_ring": dict(slot="arm_ring", bone="upperarm_l", detail="metal", color="#c49a3a",
                            name="Gilded arm ring"),
    "drinking_horn": dict(slot="belt", bone="pelvis", detail="bone", color="#cdbb94", name="Drinking horn"),
    "beast_jaw": dict(slot="belt", bone="pelvis", detail="bone", color="#d8ccb0", name="Beast's jaw"),
}
ACCESSORY_ORDER = tuple(ACCESSORIES)
ACCESSORY_TRIANGLES = 400


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


def sstep(x, a, b):
    t = np.clip((np.asarray(x, np.float64) - a) / (b - a), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


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


def _boundary(F):
    E = np.concatenate([F[:, [0, 1]], F[:, [1, 2]], F[:, [2, 3]], F[:, [3, 0]]])
    E.sort(axis=1)
    u, c = np.unique(E, axis=0, return_counts=True)
    return u[c == 1]


EDGE_SMOOTH = 6           # passes of the boundary's easing (P54)


def clean_faces(faces, keep, passes=3):
    """A face mask without the cut's teeth (P54): a kept face with at most one kept neighbour is dropped, a face with
    three or four kept neighbours is filled in, a few times over."""
    key = id(faces)
    if _ADJ.get("key") != key:
        E = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
        fid = np.tile(np.arange(len(faces)), 4)
        E.sort(axis=1)
        _u, inv, cnt = np.unique(E, axis=0, return_inverse=True, return_counts=True)
        inv = inv.ravel()
        order = np.argsort(inv, kind="stable")
        si = inv[order]
        first = np.searchsorted(si, np.arange(len(cnt)))
        two = cnt == 2
        pa = fid[order[first[two]]]
        pb = fid[order[first[two] + 1]]
        _ADJ.update(key=key, a=pa, b=pb)
    a, b = _ADJ["a"], _ADJ["b"]
    k = keep.copy()
    for _ in range(passes):
        nk = np.bincount(a, weights=k[b], minlength=len(k)) + np.bincount(b, weights=k[a], minlength=len(k))
        k = (k & (nk > 1)) | (~k & (nk >= 3))
    return k


_ADJ = {}


def ease_boundary(V, F, N, passes=EDGE_SMOOTH):
    """The cut's stair steps (the body's quads) eased in place (P54): each boundary vertex of the faces ``F`` (local
    indices into V) moves toward the middle of its two neighbours along the boundary, in the tangent plane of its
    normal ``N`` (per local vertex), so it keeps its height over the skin."""
    BE = _boundary(F)
    if len(BE) == 0:
        return
    nb = {}
    for a, b in BE.tolist():
        nb.setdefault(a, []).append(b)
        nb.setdefault(b, []).append(a)
    bv = np.array(sorted(nb))
    pair = np.array([nb[v] if len(nb[v]) == 2 else [v, v] for v in bv.tolist()])
    Nb = N[bv]
    for _ in range(passes):
        mid = 0.5 * (V[pair[:, 0]] + V[pair[:, 1]])
        mv = mid - V[bv]
        mv -= Nb * np.einsum("ij,ij->i", mv, Nb)[:, None]
        V[bv] += 0.5 * mv


def shell(name, coll, rig, body_V, body_N, faces, fuv, uvs, keep_vert, offset, weights, S, mat_name,
          seed=0, hem_noise=0.0, snaps=()):
    """A garment: the body faces whose 4 vertices pass `keep_vert`, pushed out along the
    normals by `offset` (per body vertex, human-scale metres), body UVs and body weights.
    ``snaps``: (field per body vertex, cut value, the field's gradient per body vertex (n, 3), tolerance): a
    boundary vertex whose field lies within the tolerance of the cut moves along the skin onto it (a hem cut
    across the body's quads is straightened instead of stepping with them). P54: the snaps and the ragged hem
    move a vertex in the skin's tangent plane, so it keeps its standoff (the slots' layering)."""
    keep = clean_faces(faces, np.all(keep_vert[faces], axis=1))
    F = faces[keep]
    FU = fuv[keep]
    used = np.unique(F.ravel())
    remap = -np.ones(len(body_V), np.int64)
    remap[used] = np.arange(len(used))
    V = body_V[used] + body_N[used] * offset[used][:, None]
    if True:
        bv = np.unique(_boundary(F).ravel())
        Nb = body_N[bv]
        for field, cut, grad, tol in snaps:
            # along the skin (the gradient's part in the tangent plane), so the vertex keeps its height over the skin
            g = grad[bv] - Nb * np.einsum("ij,ij->i", grad[bv], Nb)[:, None]
            g2 = np.einsum("ij,ij->i", g, g)
            step = (cut - field[bv]) / np.maximum(g2, 1e-9)
            move = g * step[:, None]
            ok = (np.abs(field[bv] - cut) < tol) & (np.linalg.norm(move, axis=1) < 0.06)
            V[remap[bv[ok]]] += move[ok]
        ease_boundary(V, remap[F], body_N[used])
        if hem_noise > 0:
            # ragged hem: boundary vertices pulled down along the skin (its tangent plane) by noise
            rng = np.random.default_rng(seed)
            down = np.array([0.0, 0.0, -1.0]) - Nb * (-Nb[:, 2])[:, None]
            down /= np.maximum(np.linalg.norm(down, axis=1, keepdims=True), 0.3)
            V[remap[bv]] += down * (hem_noise * rng.random(len(bv)))[:, None]
    ob = gb.new_mesh_object(name, V * S, remap[F], coll, uvs, FU)
    m = {int(v): i for i, v in enumerate(used)}
    gb.add_vertex_groups(ob, weights, m)
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(_placeholder(mat_name))
    return ob, used


def build_braies(bd, rig, coll, weights, S, p=None):
    """The kit's braies (no subdivision, no solidify): (object, body vertex per local vertex)."""
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
    body_v = bd.verts[: mh.N_BODY_VERTS]
    kd = cKDTree(body_v)
    _, braies_body = kd.query(out_v)
    # P54: the skin of the body vertex under each vertex (it was the tights helper's own): the braies then move
    # with the skin, and every garment over them with it, in any pose
    _skin_from_body(ob, weights, braies_body)
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(_placeholder("giant_cloth"))
    return ob, braies_body


HEIGHT_LATERAL_M = 0.06    # stage 1: a garment vertex stands over the skin vertex nearest it when it lies this close
#                            to that vertex's normal line


def heights(P, BV, BN, kd, lateral=HEIGHT_LATERAL_M):
    """(body vertex ids, the least and the greatest height over each): every point of ``P`` (stage-1 m) measured
    along the normal of the skin vertex nearest it (``BV``, ``BN``; ``kd`` a KD-tree of BV), when it stands over that
    vertex (within ``lateral`` of its normal line)."""
    _, near = kd.query(P)
    rel = P - BV[near]
    h = np.einsum("ij,ij->i", rel, BN[near])
    side = np.linalg.norm(rel - BN[near] * h[:, None], axis=1)
    ok = (side < lateral) & (h > 0.0)          # a cut's cap (its centre inside the limb) stands over nothing
    near, h = near[ok], h[ok]
    if len(near) == 0:
        return np.zeros(0, np.int64), np.zeros(0), np.zeros(0)
    order = np.argsort(near, kind="stable")
    near, h = near[order], h[order]
    ids, start = np.unique(near, return_index=True)
    hmin = np.minimum.reduceat(h, start)
    hmax = np.maximum.reduceat(h, start)
    return ids, hmin, hmax


# --------------------------------------------------------------------------------------------------------------
# the wardrobe: the slots' layering
# --------------------------------------------------------------------------------------------------------------
class Wardrobe:
    """Builds every garment slot by slot (LAYER_ORDER), keeping each outer slot's shells clear of the
    envelope of every inner slot's garments. ``built``: {garment id: (object, body vertex per local vertex)};
    ``record``: {garment id: {"shell": the slot's offset, "least_m", "most_m": the shell's own standoff}}."""

    def __init__(self, bd, rig, coll, weights, S, layout):
        from scipy.spatial import cKDTree
        n = mh.N_BODY_VERTS
        self.bd, self.rig, self.coll, self.weights, self.S, self.layout = bd, rig, coll, weights, S, layout
        self.n = n
        _, faces, fuv = bd.group("body")
        self.faces, self.fuv = faces, fuv
        V = bd.verts[:n]
        self.V = V
        self.N = vnormals(V, faces)
        self.B = bone_sums(weights, n)
        self.kd = cKDTree(V)
        z = V[:, 2]
        self.z = z
        J = bd.joints
        self.J = J
        self.knee = 0.5 * (J["joint-l-knee"][2] + J["joint-r-knee"][2])
        self.hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
        self.ankle = 0.5 * (J["joint-l-ankle"][2] + J["joint-r-ankle"][2])
        self.shoulder = 0.5 * (J["joint-l-shoulder"][2] + J["joint-r-shoulder"][2])
        self.neck_z = J["joint-neck"][2]
        self.waist_z = BRAIES["top_z"]
        self.mid_thigh = self.knee + 0.55 * (self.hip - self.knee)
        B = self.B
        self.torso = B["spine3"] + B["spine2"] + B["spine1"] + B["clav"]
        self.Vm = np.abs(V) * [1, 0, 0] + V * [0, 1, 1]        # the right side mirrored onto the left
        self.side = np.where(V[:, 0] >= 0.0, 1.0, -1.0)
        sh, el, wr = J["joint-l-shoulder"], J["joint-l-elbow"], J["joint-l-hand"]
        self.sh, self.el, self.wr = sh, el, wr
        low = wr - el
        up = el - sh
        self.t_low = np.einsum("ij,j->i", self.Vm - el, low) / np.dot(low, low)
        self.t_up = np.einsum("ij,j->i", self.Vm - sh, up) / np.dot(up, up)
        self.dir_low = np.outer(self.side, [1, 0, 0]) * low + np.outer(np.ones(n), [0, 1, 1]) * low
        self.dir_up = np.outer(self.side, [1, 0, 0]) * up + np.outer(np.ones(n), [0, 1, 1]) * up
        # the angle round each limb (the lower arm's and the leg's own axes): windings and pleats
        kn = J["joint-l-knee"]
        an = J["joint-l-ankle"]
        hp = J["joint-l-upper-leg"]
        leg_axis = np.where(z[:, None] > kn[2], hp + (kn - hp) * np.clip((hp[2] - z) / (hp[2] - kn[2]), 0, 1)[:, None],
                            kn + (an - kn) * np.clip((kn[2] - z) / (kn[2] - an[2]), 0, 1)[:, None])
        rel = self.Vm - leg_axis
        self.leg_theta = np.arctan2(rel[:, 1], rel[:, 0])
        arm_axis = el + np.outer(np.clip(self.t_low, 0, 1), low)
        ra = self.Vm - arm_axis
        self.arm_theta = np.arctan2(ra[:, 1], ra[:, 2])
        e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
        e.sort(axis=1)
        e = np.unique(e, axis=0)
        self.edges = e
        self.elen = np.linalg.norm(V[e[:, 0]] - V[e[:, 1]], axis=1) * S
        self.C = np.full(n, np.nan)          # the envelope of the slots built so far (stage-1 m off the skin)
        # the build sliders' farthest push of the skin (stage-1 m, (|brawn| + |girth|) x build_max_m): the rigid
        # accessories keep clear of it (they take no push of their own); the export sets it
        self.push = np.zeros(n)
        self.E = {}
        self.built = {}
        self.record = {}
        self.shells = {}          # a shell garment: (its body vertices, its standoff there, stage-1 m)
        self.exact = {}           # per vertex of a garment's object, the skin vertex it stands over (-1: none)
        self.footprint = {}       # every garment: the body vertices it stands on (the shells' check)
        self.uvs = bd.bm.uvs

    # ---- the layering -----------------------------------------------------------------------------------------
    def need(self, keep):
        """Per body vertex the least standoff a shell of the next slot must keep: the envelope plus the gap
        where it covers an inner garment, eased off beyond that garment's edge across its own footprint
        ``keep`` (-inf elsewhere: a garment that does not cover an inner one does not bulge for it)."""
        keep = np.asarray(keep, bool)
        r = np.where(np.isnan(self.C) | ~keep, -np.inf, self.C + LAYER_GAP_M)
        inside = keep[self.edges[:, 0]] & keep[self.edges[:, 1]]
        a, b = self.edges[inside, 0], self.edges[inside, 1]
        d = RAMP_SLOPE * self.elen[inside]
        for _ in range(60):
            nxt = r.copy()
            np.maximum.at(nxt, a, r[b] - d)
            np.maximum.at(nxt, b, r[a] - d)
            if np.array_equal(nxt, r):
                break
            r = nxt
        return r

    def resolve(self, slot, off_st, keep):
        off = np.maximum(np.asarray(off_st, np.float64), SLOT_SHELL_M[slot])
        return np.maximum(off, self.need(keep))

    def note(self, gid, slot, ids, env):
        E = self.E.setdefault(slot, np.full(self.n, np.nan))
        E[ids] = np.fmax(E[ids], env)
        self.footprint.setdefault(gid, set()).update(int(i) for i in np.asarray(ids).tolist())
        rec = self.record.setdefault(gid, {"shell": SLOT_SHELL_M[slot]})
        good = env[np.isfinite(env)]
        if len(good):
            rec["least_m"] = float(np.min(good))
            rec["most_m"] = float(np.max(good))

    def close(self, slot):
        if slot in self.E:
            self.C = np.fmax(self.C, self.E[slot])

    def dilate(self, ids, rings=2):
        m = np.zeros(self.n, bool)
        m[np.asarray(ids, np.int64)] = True
        a, b = self.edges[:, 0], self.edges[:, 1]
        for _ in range(rings):
            m2 = m.copy()
            m2[a[m[b]]] = True
            m2[b[m[a]]] = True
            m = m2
        return np.nonzero(m)[0]

    def ray_env(self, gid, ob, footprint=None, exact=None):
        """A garment that is not a shell (the braies, the bands, the cloaks): its standoff per body vertex, from
        its own vertices (heights over the skin: ``heights``; ``exact``: per vertex the skin vertex it stands over,
        -1 for none), the gaps between them filled two rings out."""
        dg = bpy.context.evaluated_depsgraph_get()
        me = ob.evaluated_get(dg).to_mesh()
        P = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("co", P)
        ob.evaluated_get(dg).to_mesh_clear()
        P = P.reshape(-1, 3)
        env = np.full(self.n, np.nan)
        rest = np.ones(len(P), bool)
        if exact is not None and len(exact) == len(P):
            ex = np.asarray(exact)
            own = ex >= 0
            h = np.einsum("ij,ij->i", P[own] - self.V[ex[own]] * self.S, self.N[ex[own]])
            np.fmax.at(env, ex[own], h)
            rest = ~own
        ids, hmin, hmax = heights(P[rest], self.V * self.S, self.N, self.kd_scaled())
        env[ids] = np.fmax(env[ids], hmax + MAPPED_MARGIN_M)
        a, b = self.edges[:, 0], self.edges[:, 1]
        for _ in range(2):
            nxt = env.copy()
            np.fmax.at(nxt, a, env[b])
            np.fmax.at(nxt, b, env[a])
            env = nxt
        ok = np.nonzero(np.isfinite(env))[0]
        self.note(gid, GARMENTS[gid]["slot"], ok, env[ok])

    def clear(self, P, extra=0.0, rounds=3, own=None):
        """Points (human metres) pushed out along the skin's normal until each stands at least the envelope plus
        the gap (and ``extra``, human metres) over its skin vertex: ``own`` (-1: none) or else the nearest one that
        it stands over (a point nearer an arm's inner side than the flank it lies on is pushed from the flank)."""
        P = np.asarray(P, np.float64).copy()
        own = np.full(len(P), -1) if own is None else np.asarray(own)
        for _ in range(rounds):
            _, cand = self.kd.query(P, k=6)
            rel = P[:, None, :] - self.V[cand]
            hh = np.einsum("ijk,ijk->ij", rel, self.N[cand])
            side = np.linalg.norm(rel - self.N[cand] * hh[..., None], axis=2)
            pick = np.argmin(np.where(hh > -0.01, side, np.inf), axis=1)
            near = cand[np.arange(len(P)), pick]
            near = np.where(own >= 0, own, near)
            h = np.einsum("ij,ij->i", P - self.V[near], self.N[near])
            env = np.where(np.isnan(self.C[near]), 0.0, self.C[near]) + self.push[near]
            want = (env + LAYER_GAP_M) / self.S + extra
            short = np.maximum(0.0, want - h)
            P += self.N[near] * short[:, None]
        return P

    def kd_scaled(self):
        from scipy.spatial import cKDTree
        if getattr(self, "_kd_s", None) is None:
            self._kd_s = cKDTree(self.V * self.S)
        return self._kd_s

    def add_shell(self, gid, keep, off_st, seed=0, hem_noise=0.0, snaps=(), mat="giant_cloth", allowance=0.0):
        slot = GARMENTS[gid]["slot"]
        off = self.resolve(slot, off_st, keep) + allowance
        ob, used = shell("Garment_" + gid, self.coll, self.rig, self.V, self.N, self.faces, self.fuv, self.uvs,
                         keep, off / self.S, self.weights, self.S, mat, seed=seed, hem_noise=hem_noise, snaps=snaps)
        self.note(gid, slot, used, off[used])
        self.built[gid] = (ob, used)
        self.shells[gid] = (used, off[used])
        self.exact[gid] = np.asarray(used)
        return ob

    # ---- the helpers of the cuts -------------------------------------------------------------------------------
    def zsnap(self, cut, tol=0.03):
        return (self.z, cut, np.tile([0.0, 0.0, 1.0], (self.n, 1)), tol)

    def lowsnap(self, cut, tol=0.06):
        low = self.wr - self.el
        return (self.t_low, cut, self.dir_low / np.dot(low, low), tol)

    def upsnap(self, cut, tol=0.07):
        up = self.el - self.sh
        return (self.t_up, cut, self.dir_up / np.dot(up, up), tol)

    def build(self):
        """Every garment, slot by slot; returns ``built``."""
        by_slot = {}
        for gid in ORDER:
            by_slot.setdefault(GARMENTS[gid]["slot"], []).append(gid)
        for slot in LAYER_ORDER:
            for gid in by_slot.get(slot, []):
                getattr(self, "g_" + gid)()
            self.close(slot)
        return self.built

    # ================================================================================== legs (0.012)
    def g_braies(self):
        ob, body = build_braies(self.bd, self.rig, self.coll, self.weights, self.S)
        self.built["braies"] = (ob, body)
        self.ray_env("braies", ob, np.unique(body))

    def _legs(self, top, bottom):
        B, z = self.B, self.z
        return (((B["pelvis"] + B["thigh"] + B["calf"] + B["spine1"] * 0.5) > 0.6) & (z < top) & (z > bottom)
                & (B["foot"] < 0.15) & (B["spine2"] < 0.2) & (B["hand"] < 0.01) & (B["lowerarm"] < 0.01))

    def g_trousers(self):
        z, an, w = self.z, self.ankle, self.waist_z
        bottom = an + 0.05
        keep = self._legs(w - 0.004, bottom)
        t = np.clip((z - bottom) / (w - bottom), 0, 1)
        loose = 0.004 + 0.016 * np.sin(np.pi * np.clip((t - 0.02) / 0.9, 0, 1)) ** 0.8
        loose = np.where(t > 0.93, 0.003, loose)
        rng = np.random.default_rng(21)
        th = self.leg_theta
        folds = sum(a * np.sin(k * th + rng.random() * 6.28 + 9.0 * z) for k, a in ((4, 1.0), (7, 0.5), (11, 0.3)))
        folds = 0.004 * folds * (0.3 + 0.7 * sstep(0.35 - t, -0.3, 0.3))        # bunched toward the ankle
        cuff = 0.006 * sstep(bottom + 0.06 - z, 0.0, 0.05)                      # gathered into the wraps
        off = SLOT_SHELL_M["legs"] + loose + np.maximum(folds, -0.5 * loose) + cuff
        self.add_shell("trousers", keep, off, snaps=[self.zsnap(bottom), self.zsnap(w - 0.004)])

    def g_kilt(self):
        z, w, kn, hp = self.z, self.waist_z, self.knee, self.hip
        hem = kn + 0.09
        keep = self._legs(w - 0.004, hem) & (self.B["calf"] < 0.3)
        down = np.clip((hp + 0.06 - z) / (hp + 0.06 - hem), 0, 1)
        V = self.V
        th = np.arctan2(V[:, 1], V[:, 0])                     # round the hips: the pleats run all the way round
        pleat = 0.007 * np.abs(np.sin(11.0 * th)) * (0.3 + 0.7 * down)
        off = SLOT_SHELL_M["legs"] + 0.004 + 0.030 * down ** 1.2 + pleat
        self.add_shell("kilt", keep, off, snaps=[self.zsnap(hem), self.zsnap(w - 0.004)])

    def g_loincloth(self):
        z, w, hp = self.z, self.waist_z, self.hip
        N = self.N
        front_back = np.clip((np.abs(N[:, 1]) - 0.35) / 0.65, 0, 1)
        hem = hp - 0.07 - 0.16 * front_back                        # deep flaps before and behind, short at the sides
        keep = self._legs(w - 0.004, -1.0) & (z > hem) & (self.B["calf"] < 0.05)
        down = np.clip((hp + 0.05 - z) / 0.25, 0, 1)
        off = SLOT_SHELL_M["legs"] + 0.004 + 0.016 * down
        self.add_shell("loincloth", keep, off, seed=31, hem_noise=0.025, snaps=[self.zsnap(w - 0.004)])

    # ================================================================================== chest (0.014)
    def g_tunic(self):
        B, V, z, J = self.B, self.V, self.z, self.J
        knee, hip = self.knee, self.hip
        elbow = self.el
        mid_thigh = self.mid_thigh
        # P54: the sleeve is cut across the arm (M10 cut it at a plane of x, 0.6 of the way from the shoulder to the
        # elbow in x: about the same place), so its hem can be straightened along the arm
        cut_t = 0.6
        sleeve = B["upperarm"] * (self.t_up < cut_t)
        keep = ((self.torso + B["pelvis"] + sleeve + B["thigh"] * (z > mid_thigh)) > 0.55) & (B["neck"] < 0.35) \
            & (B["head"] < 0.05) & (B["lowerarm"] < 0.3) & (B["hand"] < 0.05) & (z > mid_thigh)
        off = 0.022 + 0.018 * np.clip((hip - z) / (hip - mid_thigh), 0, 1)
        # P54: the sleeve's and the skirt's hems straightened (P53's follow-up: the sleeve edge stepped)
        self.add_shell("tunic", keep, off * self.S, snaps=[self.upsnap(cut_t), self.zsnap(mid_thigh)])

    def g_shirt(self):
        B, z = self.B, self.z
        bottom = self.hip - 0.03
        cuff = 0.93
        keep = ((self.torso + B["pelvis"] + B["upperarm"] + B["lowerarm"] * (self.t_low < cuff)) > 0.55) \
            & (B["neck"] < 0.35) & (B["head"] < 0.05) & (B["hand"] < 0.05) & (z > bottom) & (B["thigh"] < 0.5) \
            & ~((B["lowerarm"] > 0.3) & (self.t_low > cuff))
        arm = np.clip(B["upperarm"] + B["lowerarm"], 0, 1)
        rng = np.random.default_rng(23)
        folds = 0.003 * np.sin(6.0 * self.arm_theta + 40.0 * self.t_low * 0.4 + rng.random() * 6.28) * arm
        blouse = 0.006 * sstep(self.t_low, 0.5, 0.85) * (1.0 - sstep(self.t_low, 0.88, cuff))
        off = SLOT_SHELL_M["chest"] + 0.006 + np.abs(folds) + blouse + 0.004 * sstep(self.hip + 0.12 - z, 0, 0.1)
        self.add_shell("shirt", keep, off, snaps=[self.lowsnap(cuff), self.zsnap(bottom)])

    def g_sleeveless_vest(self):
        B, V, z, N = self.B, self.V, self.z, self.N
        bottom = self.hip + 0.05
        opening = (N[:, 1] < -0.3) & (np.abs(V[:, 0]) < 0.02 + 0.07 * np.clip((z - (self.shoulder - 0.30)) / 0.30, 0, 1)) \
            & (z > bottom + 0.02)
        keep = ((self.torso + B["pelvis"] * (z > self.hip + 0.06)) > 0.6) & (B["upperarm"] < 0.22) & (B["neck"] < 0.3) \
            & (B["head"] < 0.02) & (z > bottom) & ~opening
        off = SLOT_SHELL_M["chest"] + 0.009 + 0.003 * sstep(bottom + 0.1 - z, 0, 0.1)
        self.add_shell("sleeveless_vest", keep, off, snaps=[self.zsnap(bottom)], mat="giant_leather")

    def g_chest_wrap(self):
        B, V, z = self.B, self.V, self.z
        lo, hi = self.shoulder - 0.36, self.shoulder - 0.17
        band = (z > lo) & (z < hi)
        # a strap from over the left shoulder across the chest and the back to the right flank
        a = np.array([0.15, self.shoulder + 0.05])
        b = np.array([-0.17, lo + 0.03])
        d = b - a
        p = np.stack([V[:, 0], z], axis=1) - a
        s = np.clip(p @ d / (d @ d), -0.2, 1.0)
        dist = np.linalg.norm(p - np.outer(s, d), axis=1)
        strap = (dist < 0.045) & (z > lo)
        keep = (band | strap) & ((self.torso + B["pelvis"]) > 0.6) & (B["upperarm"] < 0.3) & (B["neck"] < 0.3) \
            & (B["head"] < 0.02)
        turns = 0.0025 * np.abs(np.sin(z * 75.0))
        off = SLOT_SHELL_M["chest"] + 0.004 + turns
        self.add_shell("chest_wrap", keep, off, seed=37, hem_noise=0.006)

    # ================================================================================== shins (0.020)
    def g_leg_wraps(self):
        B, z = self.B, self.z
        ankle, knee = self.ankle, self.knee
        keep = (B["calf"] > 0.5) & (z > ankle + 0.07 * (knee - ankle)) & (z < ankle + 0.86 * (knee - ankle))
        wind = 0.004 * np.sin((z - ankle) / (knee - ankle) * 2 * math.pi * 7.0)       # the turns of the winding
        # M10's 0.012 +- 0.004 (human) lifted onto the slot: 0.020 at the turns' troughs (stage 1)
        off = SLOT_SHELL_M["shins"] + (0.004 + wind) * self.S
        self.add_shell("leg_wraps", keep, off)

    def g_greaves(self):
        B, z, N = self.B, self.z, self.N
        lo, hi = self.ankle + 0.11, self.knee + 0.05
        front = N[:, 1] < 0.3
        keep = (B["calf"] + B["thigh"] * (z < self.knee + 0.08) > 0.45) & (z > lo) & (z < hi) & front & (B["foot"] < 0.1)
        keel = 0.007 * np.clip(-N[:, 1], 0, 1) ** 6
        knee_cop = 0.010 * np.exp(-((z - self.knee) / 0.05) ** 2)
        flare = 0.005 * sstep(lo + 0.05 - z, 0, 0.05)
        off = SLOT_SHELL_M["shins"] + 0.007 + keel + knee_cop + flare
        self.add_shell("greaves", keep, off, snaps=[self.zsnap(lo), self.zsnap(hi)])

    # ================================================================================== arms (0.022)
    def g_bracers(self):
        B = self.B
        keep = (B["lowerarm"] > 0.5) & (self.t_low > 0.3) & (self.t_low < 0.9)
        self.add_shell("bracers", keep, np.full(self.n, 0.012 * self.S), snaps=[self.lowsnap(0.3), self.lowsnap(0.9)],
                       mat="giant_leather")

    def g_iron_vambraces(self):
        B, t = self.B, self.t_low
        keep = (B["lowerarm"] > 0.45) & (t > 0.22) & (t < 0.92)
        flare = 0.007 * (sstep(0.30 - t, 0, 0.08) + sstep(t - 0.84, 0, 0.08))
        ridge = 0.004 * np.clip(np.cos(self.arm_theta - 0.3), 0, 1) ** 4
        off = SLOT_SHELL_M["arms"] + 0.005 + flare + ridge
        self.add_shell("iron_vambraces", keep, off, snaps=[self.lowsnap(0.22), self.lowsnap(0.92)])

    def g_arm_wraps(self):
        B, t = self.B, self.t_low
        keep = (B["lowerarm"] + B["hand"] * (t < 1.04) > 0.4) & (t > 0.32) & (t < 1.02) & (B["hand"] < 0.6)
        wind = 0.0025 * np.sin(t * 2 * math.pi * 7.0 + self.arm_theta)
        off = SLOT_SHELL_M["arms"] + 0.004 + wind
        self.add_shell("arm_wraps", keep, off, seed=41, hem_noise=0.004, snaps=[self.lowsnap(0.32)])

    # ================================================================================== feet (0.024)
    def g_boots(self):
        B, z = self.B, self.z
        ankle, knee = self.ankle, self.knee
        keep = ((B["foot"] > 0.3) | ((B["calf"] > 0.5) & (z < ankle + 0.5 * (knee - ankle)))) & (z < ankle + 0.5 * (knee - ankle))
        self.add_shell("boots", keep, np.full(self.n, 0.014 * self.S), snaps=[self.zsnap(ankle + 0.5 * (knee - ankle))],
                       mat="giant_leather", allowance=DECIMATE_MARGIN_M)

    def g_wrapped_sandals(self):
        B, z, N, V = self.B, self.z, self.N, self.V
        an = self.ankle
        top = an + 0.24
        sole = (B["foot"] > 0.3) & (N[:, 2] < 0.35)
        th = self.leg_theta
        s = z * 9.0
        lattice = (np.mod(s + th / math.pi, 1.0) < 0.36) | (np.mod(s - th / math.pi, 1.0) < 0.36)
        straps = (B["calf"] + B["foot"] > 0.4) & (z < top) & (z > an - 0.02) & lattice
        instep = (B["foot"] > 0.3) & (N[:, 2] >= 0.35) & (np.mod(V[:, 1] * 9.0, 1.0) < 0.4)
        keep = (sole | straps | instep) & (z < top)
        off = SLOT_SHELL_M["feet"] + 0.002 + 0.002 * (N[:, 2] < -0.5)
        self.add_shell("wrapped_sandals", keep, off, mat="giant_leather")

    # ================================================================================== waist (0.030)
    def _band(self, gid, height, thickness, centre_drop, extra=None, n_seg=96, mat="giant_leather", reach=0.0):
        """A band round the waist (the M10 belt's construction): a ring at the waist whose radius at each angle
        clears every inner garment's envelope there (and the skin), solidified outward."""
        S, V, N = self.S, self.V, self.N
        J = self.J
        zc = self.waist_z - centre_drop
        centre = np.array([0.0, J["joint-pelvis"][1] + 0.02, zc])
        sel = (np.abs(self.z - zc) < height * 0.6 + reach) & ((self.torso + self.B["pelvis"] + self.B["thigh"]) > 0.5) \
            & (self.B["hand"] < 0.01) & (self.B["lowerarm"] < 0.01)
        ids = np.nonzero(sel)[0]
        cover = np.where(np.isnan(self.C[ids]), 0.0, self.C[ids]) / S
        P = V[ids] + N[ids] * cover[:, None]
        rel = P[:, :2] - centre[:2]
        ang_c = np.arctan2(rel[:, 0], -rel[:, 1])
        rad_c = np.linalg.norm(rel, axis=1)
        ring = []
        for i in range(n_seg):
            a = 2 * math.pi * i / n_seg
            d = np.array([math.sin(a), -math.cos(a), 0.0])
            dang = np.abs((ang_c - a + math.pi) % (2 * math.pi) - math.pi)
            sel_a = dang < 0.12
            r = rad_c[sel_a].max() if sel_a.any() else 0.2
            ring.append(centre + d * (r + LAYER_GAP_M / S + 0.002))
        ring = np.array(ring)
        for _ in range(3):
            ring = 0.5 * ring + 0.25 * (np.roll(ring, 1, axis=0) + np.roll(ring, -1, axis=0))
        # the smoothing may pull a ring point inside the envelope: push it back out
        for i in range(n_seg):
            a = 2 * math.pi * i / n_seg
            dang = np.abs((ang_c - a + math.pi) % (2 * math.pi) - math.pi)
            sel_a = dang < 0.12
            if sel_a.any():
                need = rad_c[sel_a].max() + LAYER_GAP_M / S + 0.001
                rel_r = ring[i, :2] - centre[:2]
                r = np.linalg.norm(rel_r)
                if r < need:
                    ring[i, :2] = centre[:2] + rel_r * (need / r)
        if extra is not None:
            ring = extra(ring, centre)
        bv = np.concatenate([ring + [0, 0, -height / 2], ring + [0, 0, height / 2]])
        # P54: each edge of the band clear of the envelope under it (a bulge below or above the band's middle)
        for _ in range(2):
            bv = self.clear(bv, 0.002)
            for r0 in (0, n_seg):
                row = bv[r0:r0 + n_seg]
                bv[r0:r0 + n_seg] = 0.5 * row + 0.25 * (np.roll(row, 1, axis=0) + np.roll(row, -1, axis=0))
        bv = self.clear(bv, 0.002)
        bf = [(i, (i + 1) % n_seg, n_seg + (i + 1) % n_seg, n_seg + i) for i in range(n_seg)]
        ob = gb.new_mesh_object("Garment_" + gid, bv * S, np.array(bf), self.coll)
        _, body = self.kd.query(bv)
        _skin_from_body(ob, self.weights, body)
        gb.parent_keep(ob, self.rig)
        sol = ob.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = thickness * S
        sol.offset = 1.0
        gb.armature_modifier(ob, self.rig)
        ob.data.materials.append(_placeholder(mat))
        self.built[gid] = (ob, body)
        self.ray_env(gid, ob, np.unique(np.concatenate([body, ids])))
        return ob

    def g_belt(self):
        p = BRAIES
        self._band("belt", p["belt_height"], p["belt_thickness"], p["belt_height"] * 0.42)

    def g_war_belt(self):
        def plates(ring, centre):
            n = len(ring)
            out = ring.copy()
            for i in range(n):
                a = 2 * math.pi * i / n
                raised = (math.fmod(a * 14 / (2 * math.pi), 1.0) < 0.78)
                if raised:
                    rel = out[i, :2] - centre[:2]
                    out[i, :2] = centre[:2] + rel * (1.0 + 0.004 / np.linalg.norm(rel))
            return out
        self._band("war_belt", 0.095, 0.009, 0.045, extra=plates, n_seg=112, mat="giant_metal", reach=0.03)

    def g_sash(self):
        def folds(ring, centre):
            n = len(ring)
            out = ring.copy()
            for i in range(n):
                a = 2 * math.pi * i / n
                rel = out[i, :2] - centre[:2]
                out[i, :2] = centre[:2] + rel * (1.0 + 0.003 * (1.0 + math.sin(a * 9.0)) / np.linalg.norm(rel))
            return out
        ob = self._band("sash", 0.085, 0.004, 0.05, extra=folds, mat="giant_cloth", reach=0.03)
        self._sash_tail(ob)

    def _sash_tail(self, band):
        """The sash's knotted end: a strip hanging from the band at the left hip, over the hip's envelope."""
        S = self.S
        me = band.data
        P = np.array([v.co[:] for v in me.vertices]) / S
        n_seg = len(P) // 2
        i0 = int(round(n_seg * 0.27))                 # the left hip, a little behind the side (the thigh swings least)
        top = P[n_seg + i0]
        rows, cols, length, width = 6, 3, 0.24, 0.07
        side = np.array([math.cos(2 * math.pi * i0 / n_seg), math.sin(2 * math.pi * i0 / n_seg), 0.0])
        out_dir = np.array([math.sin(2 * math.pi * i0 / n_seg), -math.cos(2 * math.pi * i0 / n_seg), 0.0])
        verts = []
        for r in range(rows + 1):
            zt = -length * r / rows
            for c in range(cols + 1):
                u = (c / cols - 0.5) * width * (1.0 + 0.4 * r / rows)
                p = top + side * u + np.array([0, 0, zt - 0.01])
                verts.append(p)
        verts = np.array(verts)
        # clear the envelope under each tail vertex (the hip, the inner garments) and the band's thickness
        verts = verts + out_dir * 0.01
        verts = self.clear(verts, 0.012 + HANG_MARGIN_M / S)
        faces = []
        for r in range(rows):
            for c in range(cols):
                a = r * (cols + 1) + c
                faces.append((a, a + 1, a + cols + 2, a + cols + 1))
        tail = gb.new_mesh_object("_sash_tail", verts * S, np.array(faces), self.coll)
        tail_body = np.array([self.kd.query(top)[1]] * len(verts))
        # one solid strip: join the tail to the band after the band's solidify (a single mesh, one draw call)
        tail.data.materials.append(_placeholder("giant_cloth"))
        sol = tail.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = 0.003 * S
        sol.offset = 1.0
        bpy.context.view_layer.objects.active = tail
        bpy.ops.object.modifier_apply(modifier=sol.name)
        bpy.context.view_layer.objects.active = band
        for m in list(band.modifiers):
            if m.type == "SOLIDIFY":
                bpy.ops.object.modifier_apply(modifier=m.name)
        nb = len(band.data.vertices)
        for o in bpy.data.objects:
            o.select_set(False)
        band.select_set(True)
        tail.select_set(True)
        bpy.context.view_layer.objects.active = band
        for m in list(band.modifiers):
            if m.type == "ARMATURE":
                band.modifiers.remove(m)
        bpy.ops.object.join()
        for vg in list(band.vertex_groups):
            band.vertex_groups.remove(vg)
        _, body_band = self.kd.query(np.array([v.co[:] for v in band.data.vertices])[:nb] / S)
        body_all = np.concatenate([body_band, np.full(len(band.data.vertices) - nb, tail_body[0])])
        _skin_from_body(band, self.weights, body_all)
        gb.armature_modifier(band, self.rig)
        self.built["sash"] = (band, body_all)
        self.ray_env("sash", band, np.unique(body_all))

    # ================================================================================== armour (0.034)
    def g_jerkin(self):
        B, z = self.B, self.z
        hip = self.hip
        keep = (self.torso + B["pelvis"] * (z > hip + 0.06) > 0.6) & (B["upperarm"] < 0.25) & (B["neck"] < 0.3) \
            & (z > hip + 0.05) & (B["head"] < 0.02)
        self.add_shell("jerkin", keep, np.full(self.n, 0.045 * self.S), snaps=[self.zsnap(hip + 0.05)],
                       mat="giant_leather")

    def g_mail_hauberk(self):
        B, z = self.B, self.z
        hem = self.knee + 0.45 * (self.hip - self.knee)
        sleeve = B["upperarm"] * (self.t_up < 0.5)
        keep = ((self.torso + B["pelvis"] + B["thigh"] * (z > hem) + sleeve) > 0.55) & (B["neck"] < 0.32) \
            & (B["head"] < 0.03) & (B["lowerarm"] < 0.1) & (B["hand"] < 0.02) & (z > hem)
        skirt = np.clip((self.hip + 0.12 - z) / (self.hip + 0.12 - hem), 0, 1)
        rng = np.random.default_rng(43)
        folds = 0.004 * np.sin(7.0 * self.leg_theta + rng.random() * 6.28) * skirt
        off = SLOT_SHELL_M["armour"] + 0.008 + 0.032 * skirt ** 1.5 + folds
        self.add_shell("mail_hauberk", keep, off, snaps=[self.zsnap(hem), self.upsnap(0.5)], mat="giant_metal")

    def g_leather_cuirass(self):
        B, z = self.B, self.z
        bottom = self.hip + 0.09
        keep = ((self.torso + B["pelvis"] * (z > self.hip + 0.1)) > 0.6) & (B["upperarm"] < 0.15) & (B["neck"] < 0.25) \
            & (z > bottom) & (B["head"] < 0.02)
        off = SLOT_SHELL_M["armour"] + 0.012 + 0.004 * sstep(bottom + 0.06 - z, 0, 0.06)
        self.add_shell("leather_cuirass", keep, off, snaps=[self.zsnap(bottom)], mat="giant_leather")

    def g_scale_coat(self):
        B, z = self.B, self.z
        hem = self.mid_thigh + 0.02
        keep = ((self.torso + B["pelvis"] + B["thigh"] * (z > hem)) > 0.55) & (B["upperarm"] < 0.25) & (B["neck"] < 0.3) \
            & (B["head"] < 0.02) & (z > hem)
        skirt = np.clip((self.hip + 0.12 - z) / (self.hip + 0.12 - hem), 0, 1)
        off = SLOT_SHELL_M["armour"] + 0.011 + 0.030 * skirt ** 1.5
        self.add_shell("scale_coat", keep, off, snaps=[self.zsnap(hem)], mat="giant_metal")

    def g_bronze_breastplate(self):
        B, z, V, N = self.B, self.z, self.V, self.N
        bottom = self.hip + 0.13
        keep = (self.torso > 0.65) & (B["upperarm"] < 0.12) & (B["neck"] < 0.2) & (z > bottom) & (B["pelvis"] < 0.4) \
            & (B["head"] < 0.02)
        keel = 0.008 * np.exp(-(V[:, 0] / 0.045) ** 2) * (N[:, 1] < -0.3)
        off = SLOT_SHELL_M["armour"] + 0.016 + keel + 0.004 * sstep(bottom + 0.05 - z, 0, 0.05)
        self.add_shell("bronze_breastplate", keep, off, snaps=[self.zsnap(bottom)], mat="giant_metal")

    # ================================================================================== cape (free)
    def g_cape(self):
        self._cloak("cape", dict(CAPE))

    def g_long_cloak(self):
        self._cloak("long_cloak", dict(CAPE, hem_noise=0.0, extend=0.80, extend_rows=10, extend_flare=0.20,
                                        extend_spread=0.10, end_noise=0.03, seed=13))

    def g_fur_cloak(self):
        self._cloak("fur_cloak", dict(CAPE, offset=0.06, collar_offset=0.05, collar_lo=0.06, hem_noise=0.0,
                                       extend=0.48, extend_rows=7, extend_flare=0.14, extend_spread=0.08,
                                       end_noise=0.05, seed=17), mat="giant_fur")

    def _cloak(self, gid, p, mat="giant_cloth"):
        w = self
        V, N, faces, fuv, B, z = w.V, w.N, w.faces, w.fuv, w.B, w.z
        ob, used = build_cape(w.bd, w.rig, w.coll, w.weights, w.S, w.layout, V, N, faces, fuv, B, z,
                              w.shoulder, w.hip, w.neck_z, p, name="Garment_" + gid,
                              need=lambda keep: w.need(keep) / w.S, mat=mat,
                              clear=lambda P, own, extra: w.clear(P, extra, own=own))
        w.built[gid] = (ob, used)
        # the cut part stands over its own skin vertex, unless the hang moved it; the rows below the body's cut do not
        w.exact[gid] = np.asarray(ob["exact_ids"], np.int64)
        w.ray_env(gid, ob, used, w.exact[gid])

    # ================================================================================== shoulders (0.046)
    def g_furs(self):
        B, z = self.B, self.z
        shoulder, neck_z = self.shoulder, self.neck_z
        n = self.n
        keep = ((B["spine3"] + B["clav"] + B["upperarm"] * (z > shoulder - 0.06) + B["neck"] * 0.6) > 0.45) \
            & (z > shoulder - 0.16) & (B["head"] < 0.02) & (z < neck_z + 0.02) & (B["lowerarm"] < 0.05)
        rng = np.random.default_rng(5)
        fur_off = 0.05 + 0.02 * smooth_field(rng.random(n), self.faces, n, 2)
        self.add_shell("furs", keep, fur_off * self.S, seed=7, hem_noise=0.03, mat="giant_fur")

    def g_pauldron(self):
        B, V, z, J = self.B, self.V, self.z, self.J
        sh_l = J["joint-l-shoulder"]
        d_sh = np.linalg.norm(V - (sh_l + np.array([0.02, 0.0, 0.03])), axis=1)
        keep = (V[:, 0] > 0.0) & (d_sh < 0.2) & ((B["upperarm"] + B["clav"] + B["spine3"] * 0.5) > 0.5) \
            & (z > self.shoulder - 0.15) & (B["neck"] < 0.25) & (B["lowerarm"] < 0.05)
        pad = 0.03 + 0.025 * np.clip(1.0 - d_sh / 0.2, 0.0, 1.0)
        self.add_shell("pauldron", keep, pad * self.S, mat="giant_leather")

    def g_fur_mantle(self):
        B, z = self.B, self.z
        shoulder, neck_z = self.shoulder, self.neck_z
        n = self.n
        keep = ((B["spine3"] + B["clav"] + B["upperarm"] * (z > shoulder - 0.13) + B["neck"] * 0.6
                 + B["spine2"] * (z > shoulder - 0.27)) > 0.42) \
            & (z > shoulder - 0.27) & (B["head"] < 0.02) & (z < neck_z + 0.03) & (B["lowerarm"] < 0.05) \
            & (self.t_up < 0.62)
        rng = np.random.default_rng(47)
        fluff = smooth_field(rng.random(n), self.faces, n, 2)
        off = SLOT_SHELL_M["shoulders"] + 0.030 + 0.030 * fluff + 0.012 * sstep(z, shoulder - 0.05, shoulder + 0.05)
        self.add_shell("fur_mantle", keep, off, seed=49, hem_noise=0.045, mat="giant_fur")

    def _shoulder_pieces(self, reach):
        B, z = self.B, self.z
        d = np.linalg.norm(self.Vm - (self.sh + np.array([0.03, 0.0, 0.03])), axis=1)
        keep = (d < reach) & ((B["upperarm"] + B["clav"] + B["spine3"] * 0.5) > 0.5) & (z > self.shoulder - 0.17) \
            & (B["neck"] < 0.22) & (B["lowerarm"] < 0.05) & (np.abs(self.V[:, 0]) > 0.11)
        return keep, d

    def _dsnap(self, d, cut, tol=0.03):
        """A snap onto the shoulder pieces' rim: d's gradient is the direction away from the shoulder point."""
        c = self.sh + np.array([0.03, 0.0, 0.03])
        g = (self.Vm - c) / np.maximum(d, 1e-6)[:, None]
        g[:, 0] *= self.side
        return (d, cut, g, tol)

    def g_iron_pauldrons(self):
        keep, d = self._shoulder_pieces(0.20)
        dome = 0.016 * np.clip(1.0 - d / 0.20, 0.0, 1.0) ** 0.6
        down = np.clip((self.sh[2] + 0.07 - self.z) / 0.24, 0, 1)
        steps = down * 4.0
        lame = np.floor(steps) + sstep(np.mod(steps, 1.0), 0.8, 1.0)     # soft terraces: each lame over the next
        lames = 0.005 * (3.0 - np.minimum(lame, 3.0)) / 3.0
        off = SLOT_SHELL_M["shoulders"] + 0.006 + dome + lames
        self.add_shell("iron_pauldrons", keep, off, mat="giant_metal", snaps=[self._dsnap(d, 0.20)])

    def g_bone_spaulders(self):
        keep, d = self._shoulder_pieces(0.18)
        V = self.V
        plate = np.abs(np.sin(V[:, 1] * 38.0) * np.sin(self.z * 34.0))
        off = SLOT_SHELL_M["shoulders"] + 0.010 + 0.014 * np.clip(1.0 - d / 0.18, 0, 1) ** 0.7 + 0.005 * plate
        self.add_shell("bone_spaulders", keep, off, mat="giant_bone", snaps=[self._dsnap(d, 0.18)])

    # ================================================================================== head (0.020)
    def _head(self):
        L = self.bd.landmarks
        return self.B["head"] + self.B["neck"], L

    def g_hood(self):
        hn, L = self._head()
        V, z, N = self.V, self.z, self.N
        brow, chin = L["brow_z"], L["chin"]
        zc = 0.5 * ((brow + 0.03) + (chin - 0.07))
        rz = 0.5 * ((brow + 0.03) - (chin - 0.07))
        face = (V[:, 1] < L["head_cy"] - 0.02) & ((V[:, 0] / 0.088) ** 2 + ((z - zc) / rz) ** 2 < 1.0)
        keep = (hn > 0.6) & (z > self.neck_z + 0.065) & ~face
        back = sstep(V[:, 1], L["head_cy"], L["head_cy"] + 0.11) * sstep(z, L["ear_z"][1], L["top"])
        off = SLOT_SHELL_M["head"] + 0.032 + 0.045 * back + 0.012 * sstep(L["ear_z"][0] - z, 0, 0.08)
        self.add_shell("hood", keep, off, snaps=[self.zsnap(self.neck_z + 0.065)])

    def _cap(self, gid, front, back, crown, mat, ridge=0.0, band=0.0):
        """A skull cap: the scalp above ``front`` (at the brow) and ``back`` (round the ears and the nape)."""
        hn, L = self._head()
        V, z = self.V, self.z
        frontness = sstep(L["head_cy"] - V[:, 1], -0.02, 0.06)
        rim = back + (front - back) * frontness
        keep = (self.B["head"] > 0.9) & (z > rim)
        crest = ridge * np.exp(-(V[:, 0] / 0.018) ** 2) * sstep(z, rim + 0.04, rim + 0.08)
        brim = band * np.exp(-((z - rim) / 0.018) ** 2)
        off = SLOT_SHELL_M["head"] + crown + crest + brim
        self.add_shell(gid, keep, off, snaps=[(z - rim, 0.0, np.tile([0.0, 0.0, 1.0], (self.n, 1)), 0.03)], mat=mat)
        return keep, off

    def g_leather_cap(self):
        L = self.bd.landmarks
        self._cap("leather_cap", L["brow_z"] + 0.022, L["ear_z"][1] + 0.012, 0.024, "giant_leather", band=0.004)

    def g_iron_helm(self):
        L = self.bd.landmarks
        self._cap("iron_helm", L["brow_z"] + 0.004, L["ear_z"][1] - 0.012, 0.028, "giant_metal", ridge=0.008,
                  band=0.007)

    def g_horned_helm(self):
        L = self.bd.landmarks
        self._cap("horned_helm", L["brow_z"] + 0.008, L["ear_z"][1] - 0.008, 0.028, "giant_metal", ridge=0.0,
                  band=0.008)
        ob, used = self.built["horned_helm"]
        add_horns(ob, self.bd, self.S, self.V, self.N, self.C, self.kd)


# The free cape (P48, plan M11 §2.2; human-scale metres). It is cut from the body as the M10 shell was - the
# back from the neck to the hips and over the shoulders - with a band round the base of the neck that closes
# it at the collar; below the shoulder blades it leaves the back and hangs: every vertex takes the rearmost
# place of the cloth above it in its own column, the hem flares and falls in folds. P54: it lies on the back down to
# ``hang_below`` under the shoulders (the shoulders' garments lie over it there) and hangs from there; the long cloaks
# carry on below the body's cut (``extend`` metres in ``extend_rows`` rows, flaring back and out).
CAPE = dict(offset=0.05, flare=0.07, column=0.022, fold_depth=0.016, folds=9.0, hem_noise=0.035, hang_below=0.29,
            collar_lo=0.045, collar_hi=0.012, collar_offset=0.03, extend=0.0, extend_rows=0, extend_flare=0.0,
            extend_spread=0.0, end_noise=0.0, seed=11)


def build_cape(bd, rig, coll, weights, S, layout, V, N, faces, fuv, B, z, shoulder, hip, neck_z, p=None,
               name="Garment_cape", need=None, mat="giant_cloth", clear=None):
    """(object, body vertex per local vertex): the cape as a free mesh. Its skin: the body's weights down
    to the chains' roots, then the three cape chains (giant_parts.chain_weights). ``need``: the least standoff
    (a function of the footprint: human metres per body vertex) the slots under it ask for (Wardrobe.need)."""
    import giant_parts as gp
    p = dict(CAPE, **(p or {}))
    n = len(V)
    torso = B["spine3"] + B["spine2"] + B["spine1"] + B["clav"]
    back = N[:, 1] > -0.15
    keep = (((torso + B["pelvis"] * (z > hip - 0.02) + B["upperarm"] * (z > shoulder - 0.05) + B["neck"] * 0.5) > 0.45)
            & back & (z > hip - 0.03) & (z < neck_z + 0.01) & (B["head"] < 0.02) & (B["lowerarm"] < 0.05))
    # the collar: a band round the base of the neck, front included, so the cape closes on the chest
    collar = ((torso + B["neck"]) > 0.6) & (z > neck_z - p["collar_lo"]) & (z < neck_z + p["collar_hi"]) \
        & (B["head"] < 0.02) & (B["upperarm"] < 0.2)
    keep = keep | collar
    # P54: the cloth lies on the back down to hang_z (below the shoulders' garments, which lie over it), then hangs
    hang_z = shoulder - p["hang_below"]
    down = np.clip((hang_z - z) / (hang_z - hip), 0.0, 1.0)
    off = np.where(collar & ~back, p["collar_offset"], p["offset"])
    if need is not None:
        off = np.maximum(off, need(keep))
    shell_v = V + N * off[:, None]
    hang = keep & back & (z < hang_z)
    idx = np.nonzero(hang)[0]
    y = shell_v[:, 1].copy()
    hx, hz, hy = shell_v[idx, 0], shell_v[idx, 2], shell_v[idx, 1]
    for i, vi in enumerate(idx):
        above = (np.abs(hx - hx[i]) < p["column"]) & (hz >= hz[i])
        y[vi] = hy[above].max()
    y = np.where(hang, smooth_field(y, faces, n, 3), y)
    y = np.maximum(y, shell_v[:, 1])
    rng = np.random.default_rng(p["seed"])
    ph = rng.random() * 6.28
    fold = p["fold_depth"] * down ** 1.2 * np.sin(p["folds"] * shell_v[:, 0] / 0.2 + ph)
    y = np.where(hang, y + p["flare"] * down ** 1.5 + fold, y)
    pos = shell_v.copy()
    pos[:, 1] = y
    keep_f = np.all(keep[faces], axis=1)          # (not cleaned: the collar is a band a face or two high)
    F, FU = faces[keep_f], fuv[keep_f]
    used = np.unique(F.ravel())
    remap = -np.ones(n, np.int64)
    remap[used] = np.arange(len(used))
    P = pos[used]
    ease_boundary(P, remap[F], N[used])
    E = _boundary(F)
    bv = np.unique(E.ravel())
    bv = bv[z[bv] < hip + 0.12]
    uvs = np.asarray(bd.bm.uvs, np.float64)
    bottom = bv[z[bv] < hip + 0.01]
    FL = remap[F]
    FUV = FU
    body_ids = used.copy()
    if p["extend"] > 0.0:
        P, FL, uvs, FUV, body_ids = _extend_cloak(P, FL, uvs, FUV, body_ids, remap[bottom], used, z, hip, p, rng)
    else:
        # the ragged hem (the M10 cape's): the lower boundary pulled down by noise
        P[remap[bv], 2] -= p["hem_noise"] * rng.random(len(bv))
    exact = np.where(np.arange(len(P)) < len(used), np.concatenate([used, np.zeros(len(P) - len(used), np.int64)]), -1)
    hung = np.zeros(len(P), bool)
    hung[:len(used)] = hang[used]
    exact = np.where(hung, -1, exact)
    if clear is not None:
        # the hanging cloth keeps HANG_MARGIN_M more over what lies under it, eased in below where it leaves the back
        extra = np.where(exact >= 0, 0.0, HANG_MARGIN_M / S * sstep(hang_z - P[:, 2], 0.0, 0.15))
        P = clear(P, exact, extra)
    ob = gb.new_mesh_object(name, P * S, FL, coll, uvs, FUV)
    ob["exact_ids"] = exact.tolist()
    body_groups = {}
    for bone, lst in weights.items():
        w = np.zeros(n)
        for vi, wt in lst:
            if vi < n:
                w[vi] = wt
        if w[body_ids].max() > 1e-4:
            body_groups[bone] = w[body_ids]
    groups = gp.chain_weights(P * S, body_groups, layout, let_go_z=(hang_z - 0.085) * S) if layout is not None \
        else body_groups
    for bone in sorted(groups):
        w = groups[bone]
        ids = np.nonzero(w > 1e-4)[0]
        if len(ids) == 0:
            continue
        vg = ob.vertex_groups.new(name=bone)
        for i in ids.tolist():
            vg.add([i], float(w[i]), "REPLACE")
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(_placeholder(mat))
    return ob, body_ids


def _hem_chain(P, FL, hem_local):
    """The cloak's lower edge as one chain of local vertices from his right to his left: the boundary edges
    between hem vertices, walked from the end with the smallest x (falls back to an order by x)."""
    E = _boundary(FL)
    hs = set(int(v) for v in hem_local)
    adj = {}
    for a, b in E.tolist():
        if a in hs and b in hs:
            adj.setdefault(a, []).append(b)
            adj.setdefault(b, []).append(a)
    ends = [v for v, nb in adj.items() if len(nb) == 1]
    if len(ends) == 2 and all(len(nb) <= 2 for nb in adj.values()):
        start = min(ends, key=lambda v: P[v, 0])
        chain, prev = [start], None
        while True:
            nxt = [u for u in adj[chain[-1]] if u != prev]
            if not nxt:
                break
            prev = chain[-1]
            chain.append(nxt[0])
        if len(chain) == len(adj):
            return np.asarray(chain)
    return np.asarray(sorted(hs, key=lambda v: P[v, 0]))


def _extend_cloak(P, FL, uvs, FUV, body_ids, hem_local, used, z, hip, p, rng):
    """Rows of cloth below the cut cape's hem: each row falls ``extend / extend_rows``, steps back and out
    (``extend_flare``, ``extend_spread`` at the last row) and the last row's hem is ragged (``end_noise``)."""
    chain = _hem_chain(P, FL, hem_local)
    rows = int(p["extend_rows"])
    m = len(chain)
    top = P[chain].copy()
    top[:, 2] = np.minimum(top[:, 2], np.min(top[:, 2]) + 0.015)       # an even top for the fall
    xs = top[:, 0]
    mid = 0.5 * (xs.max() + xs.min())
    newP = [P]
    ids = []
    base = len(P)
    uv_top = np.zeros((m, 2))
    # the hem vertices' own UVs: the first corner UV the faces give them
    corner = {}
    for f, fu in zip(FL.tolist(), FUV.tolist()):
        for v, u in zip(f, fu):
            corner.setdefault(v, u)
    for k, v in enumerate(chain.tolist()):
        uv_top[k] = uvs[corner[v]]
    new_uv = []
    noise = rng.random(m)
    for r in range(1, rows + 1):
        s = r / rows
        row = top.copy()
        row[:, 2] = top[:, 2] - p["extend"] * s
        row[:, 1] = top[:, 1] + p["extend_flare"] * s ** 1.3 + 0.012 * np.sin(xs * 30.0 + r) * s
        row[:, 0] = top[:, 0] + (xs - mid) * p["extend_spread"] * s / max(1e-6, (xs.max() - xs.min()) / 2)
        if r == rows:
            row[:, 2] -= p["end_noise"] * noise
        newP.append(row)
        ids.append(base + (r - 1) * m + np.arange(m))
        uvr = uv_top.copy()
        uvr[:, 1] -= 0.12 * s
        new_uv.append(uvr)
    P2 = np.concatenate(newP)
    uv2 = np.concatenate([uvs] + new_uv)
    uv_base = len(uvs)
    faces, fuvs = [FL], [FUV]
    prev_v = chain
    prev_uv = np.array([corner[v] for v in chain.tolist()])
    for r in range(rows):
        cur_v = ids[r]
        cur_uv = uv_base + r * m + np.arange(m)
        quads = np.stack([prev_v[:-1], prev_v[1:], cur_v[1:], cur_v[:-1]], axis=1)
        quv = np.stack([prev_uv[:-1], prev_uv[1:], cur_uv[1:], cur_uv[:-1]], axis=1)
        # keep the cut cape's winding (its faces face outward, away from the back)
        faces.append(quads)
        fuvs.append(quv)
        prev_v, prev_uv = cur_v, cur_uv
    F2 = np.concatenate(faces)
    FUV2 = np.concatenate(fuvs)
    body2 = np.concatenate([body_ids, np.repeat(body_ids[chain][None, :], rows, axis=0).ravel()])
    return P2, F2, uv2, FUV2, body2


def _tube(path, radius, sides, closed=False, twist=0.0):
    """Vertices and quads of a tube along ``path`` (m, 3) with a radius per point."""
    path = np.asarray(path, np.float64)
    m = len(path)
    T = np.gradient(path, axis=0)
    T /= np.linalg.norm(T, axis=1, keepdims=True) + 1e-12
    ref = np.array([0.0, 0.0, 1.0]) if abs(T[0, 2]) < 0.9 else np.array([1.0, 0.0, 0.0])
    verts = []
    for i in range(m):
        a = np.cross(T[i], ref)
        if np.linalg.norm(a) < 1e-6:
            a = np.cross(T[i], [0.0, 1.0, 0.0])
        a /= np.linalg.norm(a)
        b = np.cross(T[i], a)
        for s in range(sides):
            th = 2 * math.pi * s / sides + twist * i
            verts.append(path[i] + radius[i] * (math.cos(th) * a + math.sin(th) * b))
    faces = []
    rings = m if closed else m - 1
    for i in range(rings):
        j = (i + 1) % m
        for s in range(sides):
            t = (s + 1) % sides
            faces.append((i * sides + s, i * sides + t, j * sides + t, j * sides + s))
    return np.array(verts), faces


def _cap_end(verts, faces, ring_start, sides, tip):
    """Closes a tube's end ring with a fan to ``tip`` (triangles as degenerate-free quads: tris)."""
    c = len(verts)
    verts = np.vstack([verts, tip])
    for s in range(sides):
        t = (s + 1) % sides
        faces.append((ring_start + s, ring_start + t, c))
    return verts, faces


def add_horns(helm, bd, S, V, N, C, kd):
    """Two horns on the horned helm's sides: tapering curved tubes from the temples, up, out and forward, joined
    into the helm's mesh, 100 % on the head bone."""
    L = bd.landmarks
    me = helm.data
    HP = np.array([v.co[:] for v in me.vertices]) / S
    verts_all, faces_all = [], []
    base = len(HP)
    zc = L["ear_z"][1] + 0.05
    for side in (1.0, -1.0):
        sel = (HP[:, 2] > zc - 0.02) & (HP[:, 2] < zc + 0.02) & (HP[:, 0] * side > 0)
        root = HP[sel][np.argmax(HP[sel][:, 0] * side)] if sel.any() else np.array([side * 0.09, -0.04, zc])
        root = root - np.array([side * 0.012, 0.0, 0.0])
        m = 12
        path, radius = [], []
        for i in range(m):
            t = i / (m - 1)
            path.append(root + np.array([side * (0.02 + 0.11 * t), -0.035 * t - 0.04 * t * t, 0.03 * t + 0.10 * t * t]))
            radius.append(0.032 * (1.0 - t) ** 0.85 + 0.002)
        v, f = _tube(path, np.array(radius), 7)
        v, f = _cap_end(v, f, (m - 1) * 7, 7, np.asarray(path[-1]) + (np.asarray(path[-1]) - np.asarray(path[-2])) * 0.6)
        off = base + sum(len(x) for x in verts_all)
        verts_all.append(v)
        faces_all.extend([tuple(i + off for i in face) for face in f])
    newV = np.vstack(verts_all) * S
    old = helm.data
    names = [g.name for g in helm.vertex_groups]
    kept = [[(names[g.group], g.weight) for g in v.groups] for v in old.vertices]
    V0 = [tuple(v.co) for v in old.vertices]
    F0 = [tuple(p.vertices) for p in old.polygons]
    uv0 = old.uv_layers.active
    UV0 = [tuple(uv0.data[li].uv) for p in old.polygons for li in range(p.loop_start, p.loop_start + p.loop_total)]
    me = bpy.data.meshes.new(old.name)
    me.from_pydata(V0 + [tuple(v) for v in newV.tolist()], [], F0 + faces_all)
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    extra = []
    for face in faces_all:
        extra += [(0.05 + 0.3 * k, 0.05) for k in range(len(face))]
    uvl.data.foreach_set("uv", np.asarray(UV0 + extra, np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    for m in old.materials:
        me.materials.append(m)
    helm.data = me
    bpy.data.meshes.remove(old)
    for i, groups in enumerate(kept):
        for name, wt in groups:
            (helm.vertex_groups.get(name) or helm.vertex_groups.new(name=name)).add([i], wt, "REPLACE")
    vg = helm.vertex_groups.get("head") or helm.vertex_groups.new(name="head")
    vg.add(list(range(base, base + len(newV))), 1.0, "REPLACE")


# --------------------------------------------------------------------------------------------------------------
# accessories: rigid meshes on one bone each
# --------------------------------------------------------------------------------------------------------------
def build_accessories(w):
    """{accessory id: object}: every accessory placed clear of the whole wardrobe's envelope (w.C after the last
    slot), 100 % on its bone."""
    S = w.S
    out = {}
    for aid in ACCESSORY_ORDER:
        spec = ACCESSORIES[aid]
        verts, faces = globals()["_acc_" + spec["slot"]](w, aid)
        ob = gb.new_mesh_object("Accessory_" + aid, np.asarray(verts) * S, np.array(faces, dtype=object), w.coll)
        me = ob.data
        uvl = me.uv_layers.new(name="UVMap")
        # the detail map's UVs: each vertex's place along and round the mesh (a cylindrical projection)
        Pv = np.array([v.co[:] for v in me.vertices])
        c = Pv.mean(axis=0)
        for poly in me.polygons:
            for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
                p = Pv[me.loops[li].vertex_index] - c
                uvl.data[li].uv = (0.5 + math.atan2(p[0], p[1]) / (2 * math.pi), 0.5 + p[2] / S * 2.0)
        vg = ob.vertex_groups.new(name=spec["bone"])
        vg.add(list(range(len(me.vertices))), 1.0, "REPLACE")
        gb.parent_keep(ob, w.rig)
        gb.armature_modifier(ob, w.rig)
        ob.data.materials.append(_placeholder("giant_bone" if spec["detail"] == "bone" else "giant_metal"))
        out[aid] = ob
    return out


def _ring_clear(w, centre, axis, sel, gap, push=False):
    """Per angle (32 sectors) round ``axis`` through ``centre``: the largest distance from the axis of the skin
    pushed out by the wardrobe's envelope, over the body vertices ``sel``, plus ``gap`` (human metres)."""
    axis = np.asarray(axis, np.float64) / np.linalg.norm(axis)
    a = np.cross(axis, [0.0, 0.0, 1.0] if abs(axis[2]) < 0.9 else [1.0, 0.0, 0.0])
    a /= np.linalg.norm(a)
    b = np.cross(axis, a)
    ids = np.nonzero(sel)[0]
    cover = (np.where(np.isnan(w.C[ids]), 0.0, w.C[ids]) + (w.push[ids] if push else 0.0)) / w.S
    P = w.V[ids] + w.N[ids] * cover[:, None] - centre
    P = P - np.outer(P @ axis, axis)
    ang = np.arctan2(P @ b, P @ a)
    rad = np.linalg.norm(P, axis=1)
    out = np.zeros(32)
    for k in range(32):
        th = -math.pi + 2 * math.pi * (k + 0.5) / 32
        d = np.abs((ang - th + math.pi) % (2 * math.pi) - math.pi)
        s = d < 2 * math.pi / 32 * 1.2
        out[k] = rad[s].max() if s.any() else (rad.max() if len(rad) else 0.05)
    out = np.maximum(out, np.maximum(np.roll(out, 1), np.roll(out, -1)))
    return a, b, out + gap


def _ring_path(centre, a, b, radii, m, open_deg=0.0, start=-math.pi):
    pts = []
    span = 2 * math.pi - math.radians(open_deg)
    for i in range(m):
        th = start + math.radians(open_deg) / 2 + span * i / (m - 1 if open_deg else m)
        k = int(((th + math.pi) % (2 * math.pi)) / (2 * math.pi) * 32) % 32
        pts.append(centre + radii[k] * (math.cos(th) * a + math.sin(th) * b))
    return np.array(pts)


def _acc_neck(w, aid):
    L = w.bd.landmarks
    J = w.J
    zt = w.neck_z + 0.035
    centre = np.array([0.0, J["joint-neck"][1] + 0.005, zt])
    # the neck's own skin and what is worn on it (a collar's rim further out is fur: a torc sits on it, P54.md)
    sel = (np.abs(w.z - zt) < 0.025) & (w.B["neck"] > 0.55) & (w.B["head"] < 0.3)
    tube_r = {"iron_torc": 0.011, "gilded_torc": 0.012, "tooth_necklace": 0.004}[aid]
    a, b, radii = _ring_clear(w, centre, [0.0, 0.0, 1.0], sel, tube_r + LAYER_GAP_M / w.S)
    # the opening of a torc faces front (-Y: the angle where the ring direction is -Y)
    front = math.atan2(np.dot([0.0, -1.0, 0.0], b), np.dot([0.0, -1.0, 0.0], a))
    if aid == "tooth_necklace":
        path = _ring_path(centre, a, b, radii, 28, 0.0, front)
        path[:, 2] -= 0.012 * np.cos(np.linspace(0, 2 * math.pi, len(path), endpoint=False)) + 0.012
        verts, faces = _tube(path, np.full(len(path), tube_r), 4, closed=True)
        V = [verts]
        F = list(faces)
        base = len(verts)
        for i in range(-4, 5):
            k = (i % len(path))
            p = path[k]
            outward = p - centre
            outward[2] = 0.0
            outward /= np.linalg.norm(outward)
            tooth = [p + outward * 0.004 + np.array([0, 0, -0.004]), p + outward * 0.012 + np.array([0, 0, -0.03 - 0.006 * (4 - abs(i)) / 4]),
                     p + outward * 0.004 + np.array([0.008, 0, -0.006]), p + outward * 0.004 + np.array([-0.008, 0, -0.006])]
            V.append(np.array(tooth))
            F += [(base, base + 2, base + 1), (base, base + 1, base + 3), (base + 2, base + 3, base + 1)]
            base += 4
        return np.vstack(V), F
    m = 30
    path = _ring_path(centre, a, b, radii, m, 50.0, front)
    twist = 0.9 if aid == "gilded_torc" else 0.0
    radius = np.full(m, tube_r) * (1.0 + 0.12 * np.sin(np.arange(m) * 2.4)) if aid == "gilded_torc" else np.full(m, tube_r)
    verts, faces = _tube(path, radius, 5, twist=twist)
    faces = list(faces)
    # the terminals: a knob at each end
    for end, inward in ((0, path[0] - path[1]), (m - 1, path[-1] - path[-2])):
        inward = inward / np.linalg.norm(inward)
        knob = path[end] + inward * 0.012
        verts, faces = _cap_end(verts, faces, end * 5, 5, knob)
    return verts, faces


def _acc_arm_ring(w, aid):
    t = {"iron_arm_ring": 0.72, "bronze_arm_spiral": 0.70, "gilded_arm_ring": 0.74}[aid]
    sh, el = w.sh, w.el
    axis = el - sh
    centre = sh + axis * t
    sel = (np.abs(w.t_up - t) < 0.08) & (w.V[:, 0] > 0.05) & (w.B["upperarm"] > 0.5)
    tube_r = {"iron_arm_ring": 0.012, "bronze_arm_spiral": 0.0075, "gilded_arm_ring": 0.010}[aid]
    a, b, radii = _ring_clear(w, centre, axis, sel, tube_r + LAYER_GAP_M / w.S)
    if aid == "bronze_arm_spiral":
        m = 56
        u = axis / np.linalg.norm(axis)
        path = []
        for i in range(m):
            th = -math.pi + 2 * math.pi * 2.6 * i / (m - 1)
            k = int(((th + math.pi) % (2 * math.pi)) / (2 * math.pi) * 32) % 32
            path.append(centre + u * (-0.03 + 0.06 * i / (m - 1)) + radii[k] * (math.cos(th) * a + math.sin(th) * b))
        verts, faces = _tube(np.array(path), np.full(m, tube_r), 3)
        return verts, list(faces)
    path = _ring_path(centre, a, b, radii, 26, 0.0)
    if aid == "gilded_arm_ring":
        verts, faces = _tube(path, np.full(26, tube_r) * (1.0 + 0.25 * (np.arange(26) % 2)), 6, closed=True)
    else:
        verts, faces = _tube(path, np.full(26, tube_r), 6, closed=True)
    return verts, list(faces)


def _acc_belt(w, aid):
    """A trophy hanging from the belt at the hip, clear of the wardrobe's envelope there."""
    J = w.J
    side = 1.0 if aid == "drinking_horn" else -1.0
    zt = w.waist_z - 0.06
    anchor_sel = (np.abs(w.z - zt) < 0.04) & (w.V[:, 0] * side > 0.10) & ((w.torso + w.B["pelvis"] + w.B["thigh"]) > 0.5)
    ids = np.nonzero(anchor_sel)[0]
    cover = (np.where(np.isnan(w.C[ids]), 0.0, w.C[ids]) + w.push[ids]) / w.S
    P = w.V[ids] + w.N[ids] * cover[:, None]
    k = int(np.argmax(P[:, 0] * side))
    root = P[k] + np.array([side, 0.0, 0.0]) * (LAYER_GAP_M / w.S + 0.012)
    if aid == "drinking_horn":
        m = 10
        path, radius = [], []
        for i in range(m):
            t = i / (m - 1)
            path.append(root + np.array([side * 0.015 * t, -0.07 * math.sin(t * 2.2), -0.28 * t + 0.08 * t * t]))
            radius.append(0.045 * (1.0 - t) ** 0.8 + 0.004)
        verts, faces = _tube(path, np.array(radius), 8)
        faces = list(faces)
        verts, faces = _cap_end(verts, faces, 0, 8, path[0])
        verts, faces = _cap_end(verts, faces, (m - 1) * 8, 8, np.asarray(path[-1]) + np.array([0, -0.01, -0.01]))
        return _clear_hang(w, verts, side), faces
    # the beast's jaw: a U of bone hanging from a thong, the teeth along its upper edge
    m = 12
    path = []
    for i in range(m):
        t = -1.0 + 2.0 * i / (m - 1)
        path.append(root + np.array([side * 0.016, 0.10 * t, -0.09 - 0.08 * (1 - t * t)]))
    verts, faces = _tube(path, np.full(m, 0.016), 5)
    faces = list(faces)
    V = [verts]
    base = len(verts)
    for i in range(1, m - 1, 2):
        p = np.asarray(path[i])
        tooth = [p + np.array([0, -0.009, 0.01]), p + np.array([0, 0.009, 0.01]), p + np.array([side * 0.006, 0, 0.045])]
        V.append(np.array(tooth))
        faces += [(base, base + 1, base + 2)]
        base += 3
    thong, tf = _tube([root + np.array([0, 0, 0.02]), np.asarray(path[m // 2]) + np.array([0, 0, 0.0])], np.full(2, 0.005), 3)
    V.append(thong)
    faces += [tuple(i + base for i in f) for f in tf]
    verts = np.vstack(V)
    return _clear_hang(w, verts, side), faces


def _clear_hang(w, verts, side):
    """Moves a hanging trophy outward (along +-X) until every vertex clears the envelope under it."""
    _, near = w.kd.query(verts)
    cover = (np.where(np.isnan(w.C[near]), 0.0, w.C[near]) + w.push[near]) / w.S
    skin = w.V[near] + w.N[near] * (cover + LAYER_GAP_M / w.S + 0.004)[:, None]
    push = np.max(np.maximum(0.0, (skin[:, 0] - verts[:, 0]) * side))
    return verts + np.array([side * push, 0.0, 0.0])
