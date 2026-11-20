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

**Only as far as what is worn under it (the W33 look lane).** That full place is not the mesh any more: each garment
is built a second time over nothing (its base: the slot's own offset), the base is the mesh, and each vertex carries
its push to the full place (``Wardrobe._push_field``; the export writes it in the vertex colour's alpha over the mesh's
``push_m``). The layering table (``Wardrobe._layering``) gives, for every outer garment and each inner garment it
stands over, the least share of its push that keeps it ``LAYER_GAP_M`` clear of that inner garment at each of
``PUSH_SAMPLES`` shares of the inner one's own push; GiantLook takes the greatest over the worn inner garments and the
cloth shader pushes the vertices by it. Worn alone a garment draws at its base. The shells span the hollows of the skin
(``bridge``), a band's ring bridges the small of the back, and a cloak hangs from its shoulders as one sheet.

Every garment keeps, per vertex, the hm08 body vertex it sits on (``body_vertex``), so the export
can split it at the body's head / torso / limbs boundary and cap its cut loops. Materials are
placeholders: the game draws garments with its own cloth shader.
"""
from __future__ import annotations

import math
import os

import bpy
import numpy as np
from mathutils.bvhtree import BVHTree

import giant_body as gb
import mh_data as mh
from split import bone_sums

BRAIES = dict(
    top_z=1.535,          # human-scale cut heights (m, the 2.45 m body)
    knee_offset=0.13,     # bottom hem this far above the knee joint
    looseness=0.018,      # m pushed out from the skin (thighs), human scale (W33: 0.03 read as puffed; the third look
    #                       lane: an even ease, the seat and the fall give the volume)
    fold_depth=0.012,
    # the third look lane (drape_breeches): fold lines (angle round the leg from his side, rad; their drift toward the
    # hip; their depth's share), their half-width, and how fast the back and the sides narrow toward the knee
    fold_lines=((-1.25, 0.35, 1.0), (-2.2, -0.25, 0.7), (0.35, 0.2, 0.6), (1.55, -0.3, 0.9), (2.45, 0.25, 0.6)),
    fold_width=0.30,
    back_taper=0.10,
    side_taper=0.16,
    waist_cinch=0.006,    # W33: the most the waist stands off the skin (human m)
    belt_height=0.065,
    belt_thickness=0.006,
    thickness=0.004,
)
SKIRT_UV_PER_M = 0.347      # the third look lane: a skirt's own UVs at the body's density (UV a human metre)
SKIRT_UV_SEAM = 0.0         # ... their seam round it at this angle (rad from his left side: under the arm)
HAUBERK_SEAT_M = 0.014       # stage 1 (the third look lane): a hauberk's skirt stands this much more off the seat
SKIRT_THIGH_FOLLOW = 1.0     # the third look lane: a skirt's hem follows the thigh on its side this much (the rows ease to it)
KILT_PLEATS = 9              # the third look lane: the kilt skirt's pleats (about three columns each)
KILT_CUT_BELOW_HIP = 0.05   # the third look lane: a skirt's shell ends this far under the hip joints (above the crotch)
LOINCLOTH_FLAP_HALF_M = 0.14   # ... and the loincloth's flaps are this wide either side of the middle (human m)
BRAIES_CROTCH_BELOW_HIP = 0.31  # the third look lane: the braies' seat spans the legs down to this under the hip joints
BRAIES_SEAT_TOP = -0.02     # the third look lane: the braies' seat spans the hips' back up to this over the hip joints
BRAIES_CLEFT_OVER = 0.07    # ... and over the cleft this much higher (under a shirt's hem)
BRAIES_UV_SCALE = 11.0    # the third look lane: the body's UV density over the tights helper's (0.347 / 0.031 a metre)
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
RAMP_SLOPE = 1.6           # (W33: 0.8 flared an armour over a belt far up the belly) how fast that clearance eases off beyond the inner garment's edge (m a m)
ENV_REACH_M = 0.30         # stage 1: the longest skin-to-garment ray of a ray-cast envelope
MAPPED_MARGIN_M = 0.005    # stage 1: added to an envelope measured over the nearest skin vertex (not a shell's own)
HANG_MARGIN_M = 0.050      # stage 1: a cloak's hanging cloth keeps this much more over what lies under it (it hangs
#                            from the chains, the back under it moves with the spine and the hips)
DECIMATE_MARGIN_M = 0.004  # stage 1: a decimated shell's allowance (the collapse pulls its surface in a little)
# The W33 look lane: a garment is built twice - over nothing (its "base": the slot's own offset, as it sits when it is
# the only layer) and over the envelope of every inner slot's loosest garment (its "full" place, P54's layering). The
# mesh is the base; each vertex carries the push to its full place (stage-1 m along the skin's normal: the vertex
# colour's alpha times the index's push_m), and the cloth shader pushes it by a share s of that (its uniform push_m =
# s x the mesh's push_m). The index's layering table gives, per outer garment and worn inner garment, the least s that
# keeps it LAYER_GAP_M clear of that inner garment at PUSH_SAMPLES shares of the inner one's own push: so a garment
# stands off only as far as what is worn under it needs (GiantLook.garment_pushes).
PUSH_SAMPLES = 5           # the inner garment's share of its own push, 0, 0.25, ... 1
BAND_SECTOR = 0.28         # rad: a band's ring spans the skin's highest within this either side (it bridges the
#                            small of the back and the cleft of the buttocks; P54's 0.12 dipped into them)
BRIDGE_ITERS = 12          # a shell spans the hollows of the skin under it this many neighbour averages wide
SKIRT_BRIDGE_ITERS = 40    # a mail or scale coat spans the cleft of the buttocks and the fold under them
CLOAK_BRIDGE_ITERS = 0     # a cloak lies looser: it spans the spine's groove and the shoulder blades' hollows
SMOOTH_PUSH_DIR = ("tunic",)   # the third look lane: garments pushed and shaded along smoothed skin normals
CLOAK_ARM_MARGIN_M = 0.003   # stage 1 (the third look lane): a cloak's cloth over the shoulders' sides keeps this more
CLOAK_NORMAL_SMOOTH = 12   # the third look lane: a cloak's normals on the back, smoothed this many neighbour passes
CLOAK_PUSH_COLUMN = 0.10   # human m: a cloak's hanging cloth keeps the greatest push above it this far either side
PUSH_RAMP = 0.35           # a band's or a cloak's push changes by at most this much a metre along its cloth
_DEBUG = bool(__import__("os").environ.get("GIANT_LAYER_DEBUG"))   # prints where a pair's full push falls short
# the push's knots (human m): off the hip joints, the hip joints, the waist, off the waist, off the shoulders twice
PUSH_KNOT_MARKS = (("hip", -0.14), ("hip", 0.0), ("waist", 0.0), ("waist", 0.13), ("shoulder", -0.22), ("shoulder", 0.04))
PUSH_FILL_RINGS = 3        # a band's push per skin vertex reaches its solidified outer layer's nearest vertices


def _co(ob):
    """An object's own vertex positions (its mesh's, no modifier)."""
    P = np.empty(len(ob.data.vertices) * 3)
    ob.data.vertices.foreach_get("co", P)
    return P.reshape(-1, 3)


def _ramp_limit(ob, P, d, slope, passes=60):
    """A per-vertex push raised where a neighbour's is higher by more than ``slope`` per metre of the edge between
    them (the object's own edges), so the push has no steps: a share of it then draws no shelf in the cloth."""
    me = ob.data
    e = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    if len(e) == 0:
        return d
    a, b = e[:, 0], e[:, 1]
    ln = np.linalg.norm(P[a] - P[b], axis=1) * slope
    d = np.asarray(d, np.float64).copy()
    for _ in range(passes):
        nxt = d.copy()
        np.maximum.at(nxt, a, d[b] - ln)
        np.maximum.at(nxt, b, d[a] - ln)
        if np.array_equal(nxt, d):
            break
        d = nxt
    return d


def _smooth_dirs(me, N, passes):
    """Unit directions per vertex of the mesh ``me`` averaged with their neighbours' (its edges) ``passes`` times."""
    e = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    e = np.concatenate([e, e[:, ::-1]])
    n = len(N)
    deg = np.maximum(np.bincount(e[:, 0], minlength=n), 1).astype(float)[:, None]
    N = np.asarray(N, np.float64).copy()
    for _ in range(passes):
        acc = np.stack([np.bincount(e[:, 0], weights=N[e[:, 1], c], minlength=n) for c in range(3)], axis=1)
        N = 0.5 * N + 0.5 * acc / deg
        N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    return N


def _remove_object(ob):
    me = ob.data
    bpy.data.objects.remove(ob, do_unlink=True)
    if me is not None and me.users == 0:
        bpy.data.meshes.remove(me)


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
RING_SLOTS = ("chest", "armour")   # the W33 look lane: the slots a torc or an arm ring sits over (not the collars and
#                                  the shoulders' garments: it stood off as far as a mantle's fur and read as a bar)
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


def hip_z(bd):
    """The hip joints' mean height (human m)."""
    J = bd.joints
    return 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])


def _hull_reach(Q, D, eq):
    """Per point of ``Q`` (k, 2) the distance along its unit direction ``D`` (k, 2) to the boundary of the convex hull
    whose facets are ``eq`` (a x + b y + c <= 0 inside); inf where it never meets one ahead."""
    den = D @ eq[:, :2].T
    num = -(Q @ eq[:, :2].T + eq[:, 2])
    t = np.where(den > 1e-9, num / np.where(den > 1e-9, den, 1.0), np.inf)
    return t.min(axis=1)


def seat_hull(P, vn, z_lo, z_hi, yc, crotch, most=0.05, slice_h=0.02, window=0.03, top=None):
    """Points (human m) of a garment round the hips and legs raised, along their normal's horizontal part, to the
    convex hull of their 2 cm slice (the third look lane; the hull of the points ``window`` m about it): cloth spans the cleft of the buttocks and every hollow
    between the muscles. Above the crotch (a slice with points on the middle line) the hips' hull and only behind the
    hips' middle (the groin's front stays), straight back; below ``crotch`` (human m) each leg's own hull; easing off
    over 6 cm under ``top`` but over the cleft (the belt lies over the braies' waist), all round. At most ``most`` m."""
    from scipy.spatial import ConvexHull
    P = P.copy()
    h = vn[:, :2]
    ln = np.linalg.norm(h, axis=1)
    D = h / np.maximum(ln, 1e-9)[:, None]
    z = P[:, 2]
    for z0 in np.arange(z_lo - slice_h, z_hi, slice_h):
        sl = np.nonzero((z >= z0) & (z < z0 + slice_h))[0]
        # the hull of a deeper window round the slice (the mesh's rows are 3-7 cm apart and uneven)
        win = np.nonzero((z >= z0 - window) & (z < z0 + slice_h + window))[0]
        if len(sl) == 0 or len(win) < 6:
            continue
        joined = bool(np.any(np.abs(P[sl, 0]) < 0.025)) and z0 > crotch
        groups = [(sl, win)] if joined else [(sl[P[sl, 0] > 0.0], win[P[win, 0] > 0.0]),
                                            (sl[P[sl, 0] <= 0.0], win[P[win, 0] <= 0.0])]
        for g, gw in groups:
            if len(g) == 0 or len(gw) < 4:
                continue
            try:
                eq = ConvexHull(P[gw, :2]).equations
            except Exception:
                continue
            mv = g[(P[g, 1] > yc) | ((np.abs(P[g, 0]) < 0.07) & (P[g, 1] > yc - 0.05))] if joined else g[ln[g] > 0.2]
            if len(mv) == 0:
                continue
            # across the seat straight back (the cleft's walls face each other: along their normals they crossed)
            Dm = np.tile([0.0, 1.0], (len(mv), 1)) if joined else D[mv]
            reach = _hull_reach(P[mv, :2], Dm, eq)
            ok = np.isfinite(reach) & (reach > 0.0)
            # (the cleft itself, the middle 8 cm either side, BRAIES_CLEFT_OVER higher)
            ease = np.where(np.abs(P[mv[ok], 0]) < 0.08, sstep(top + BRAIES_CLEFT_OVER - P[mv[ok], 2], 0.0, 0.04),
                            sstep(top - P[mv[ok], 2], 0.0, 0.06)) if top is not None else 1.0
            P[mv[ok], :2] += Dm[ok] * (np.minimum(reach[ok], most * (4.0 if joined else 1.0)) * ease)[:, None]
    return P


def drape_breeches(P, vn, faces, J, z_lo, z_hi, p):
    """Loose breeches' drape over the tights helper's points ``P`` (human m, already eased off the skin along ``vn``)
    (the third look lane): the seat and the legs spanned (``seat_hull``); below the seat's fullest the back falls
    straight to the knee and below the hips' widest the sides do, each narrowing only by ``taper`` a metre (the cloth
    hung on the buttocks' and the thighs' round); the drape smoothed; a few narrow fold lines down each leg, deepest
    toward the knee."""
    P0 = P.copy()
    n = len(P)
    yc = J["joint-pelvis"][1]
    hip = 0.5 * (J["joint-l-upper-leg"][2] + J["joint-r-upper-leg"][2])
    P = seat_hull(P, vn, z_lo, z_hi, yc, hip - BRAIES_CROTCH_BELOW_HIP, top=hip + BRAIES_SEAT_TOP)
    side = np.sign(P[:, 0])

    def fall(axis, sel, top, taper, most, sign_axis):
        cand = np.nonzero(sel & (P[:, 2] < top + 0.06))[0]
        other = 1 - axis
        for v in sorted(np.nonzero(sel & (P[:, 2] < top))[0].tolist(), key=lambda i: -P[i, 2]):
            near = cand[(np.abs(P[cand, other] - P[v, other]) < 0.035) & (P[cand, 2] > P[v, 2] + 1e-6)
                        & ((side[cand] == side[v]) | (np.abs(P[cand, 0]) < 0.03))]
            if len(near) == 0:
                continue
            if sign_axis:
                cur = P[v, axis] * side[v]
                want = float(np.max(P[near, axis] * side[near] - taper * (P[near, 2] - P[v, 2])))
                if want > cur:
                    P[v, axis] = side[v] * (cur + min(want - cur, most))
            else:
                want = float(np.max(P[near, axis] - taper * (P[near, 2] - P[v, 2])))
                if want > P[v, axis]:
                    P[v, axis] += min(want - P[v, axis], most)

    back = (vn[:, 1] > 0.25) & (P0[:, 1] > yc - 0.04)
    fall(1, back, hip + 0.03, p["back_taper"], 0.06, False)
    outer = vn[:, 0] * np.sign(P0[:, 0]) > 0.5
    fall(0, outer, hip - 0.02, p["side_taper"], 0.03, True)
    # the drape smoothed (the hull's and the fall's edges), then spanned again (smoothing sinks the middle of a span)
    d = P - P0
    for c in range(3):
        d[:, c] = smooth_field(d[:, c], faces, n, 3)
    P = seat_hull(P0 + d, vn, z_lo, z_hi, yc, hip - BRAIES_CROTCH_BELOW_HIP, top=hip + BRAIES_SEAT_TOP)
    # the seat's middle relaxed (the cleft's walls, spanned straight back, left slivers of faces that folded over)
    mid = (np.abs(P0[:, 0]) < 0.07) & (P0[:, 1] > yc) & (P0[:, 2] > hip - 0.22) & (P0[:, 2] < z_hi - 0.03)
    for c in range(3):
        sm = smooth_field(P[:, c], faces, n, 6)
        P[:, c] = np.where(mid, sm, P[:, c])
    # over the hips' sides the drape eases off toward the waist, where the belt lies (the cleft keeps its span)
    top = hip + BRAIES_SEAT_TOP
    keepw = np.where(np.abs(P0[:, 0]) < 0.08, sstep(top + BRAIES_CLEFT_OVER - P0[:, 2], 0.0, 0.04), sstep(top - P0[:, 2], 0.0, 0.06))
    P = P0 + (P - P0) * keepw[:, None]
    # fold lines: narrow ridges round each leg at fixed angles, drifting a little with height
    t = np.clip((P0[:, 2] - z_lo) / (z_hi - z_lo), 0, 1)
    kn = J["joint-l-knee"]
    hp = J["joint-l-upper-leg"]
    a = np.clip((hp[2] - P0[:, 2]) / (hp[2] - kn[2]), 0, 1)
    cx = hp[0] + (kn[0] - hp[0]) * a
    cy = hp[1] + (kn[1] - hp[1]) * a
    ang = np.arctan2(P0[:, 1] - cy, np.abs(P0[:, 0]) - cx)
    folds = np.zeros(n)
    for th0, drift, depth in p["fold_lines"]:
        dth = np.angle(np.exp(1j * (ang - th0 - drift * (1.0 - t))))
        folds += depth * np.exp(-(dth / p["fold_width"]) ** 2)
    folds *= p["fold_depth"] * sstep(0.62 - t, 0.0, 0.35)
    P = untangle(P + vn * folds[:, None], faces, P0)
    return P, np.linalg.norm(P - P0, axis=1)


def _face_normals(P, faces):
    return np.cross(P[faces[:, 2]] - P[faces[:, 0]], P[faces[:, 3]] - P[faces[:, 1]])


def untangle(P, faces, ref, passes=40):
    """Points relaxed where the drape turned a face over (its normal against the same face's on ``ref``): the
    vertices of each such face and their neighbours move half way to their neighbours' mean, until none is turned
    (the third look lane: the crotch's underside, carried onto the seat, folded)."""
    P = P.copy()
    n = len(P)
    fr = _face_normals(ref, faces)
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 3]], faces[:, [3, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    deg = np.maximum(np.bincount(e[:, 0], minlength=n), 1).astype(float)
    for _ in range(passes):
        bad = np.einsum("ij,ij->i", _face_normals(P, faces), fr) <= 0.0
        if not bad.any():
            break
        m = np.zeros(n, bool)
        m[faces[bad].ravel()] = True
        m[e[:, 1][m[e[:, 0]]]] = True
        mean = np.stack([np.bincount(e[:, 0], weights=P[e[:, 1], c], minlength=n) for c in range(3)], axis=1) / deg[:, None]
        P[m] = 0.5 * P[m] + 0.5 * mean[m]
    return P


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
    t = np.clip((verts[:, 2] - z_lo) / (z_hi - z_lo), 0, 1)
    # the third look lane: loose wool breeches, not bloomers - an even ease (a little more toward the knee, where the
    # cloth falls), the seat spanned across the cleft, the cloth hanging straight from the seat and the hips to the
    # knee, a few narrow fold lines and a plain hem (the sines' ease ballooned the hips and thighs, every hollow of the
    # tights helper showed through, and the hem pulled in like an elastic's)
    loose = p["looseness"] * (0.95 + 0.3 * sstep(0.7 - t, 0.0, 0.7)) * (1.0 - 0.5 * sstep(t, 0.7, 0.85) - 0.2 * sstep(t, 0.85, 0.9))  # (gathered into the waistband)
    out_v, lift = drape_breeches(verts + vn * loose[:, None], vn, faces, J, z_lo, z_hi, p)
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
    out_v[bot, 2] = z_lo + 0.012          # (the third look lane: a plain hem; it waved)
    body_v = bd.verts[: mh.N_BODY_VERTS]
    kd = cKDTree(body_v)
    # the W33 look lane: the waist cinched onto the skin (the tights helper spans the small of the back and stood up to
    # 4.4 cm off it there, so every garment over the braies stood off as far): within the top quarter a vertex keeps at
    # most this height over the skin vertex nearest it, easing to the looseness below
    _, near = kd.query(out_v)
    bn = vnormals(body_v, bd.group("body")[1])
    h = np.einsum("ij,ij->i", out_v - body_v[near], bn[near])
    cap = p["waist_cinch"] + (p["looseness"] + p["fold_depth"]) * 2.0 * sstep(0.95 - t, 0.0, 0.2) \
        + lift * sstep(0.86 - t, 0.0, 0.1)       # (the third look lane: the span across the cleft is kept, under the belt)
    out_v -= bn[near] * np.maximum(0.0, h - cap)[:, None]
    # the third look lane: the tights helper's UVs are about a tenth as dense as the body's (0.03 against 0.35 a metre),
    # so the weave drew ten times its size, a quilted grid of bands across the braies: scaled to the body's density
    uvs = np.asarray(uvs, np.float64) * BRAIES_UV_SCALE
    ob = gb.new_mesh_object("Garment_braies", out_v * S, faces, coll, uvs, fuv)
    # the third look lane: the skin vertex under each vertex's place before the drape (the cloth spanning the cleft
    # took the nearest of either cheek, and the torso / limbs split ran jagged down the seat)
    _, braies_body = kd.query(verts)
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
        # the W33 look lane: the base build (over nothing) and each garment's push to its full place
        self.mode = "full"
        self.C0 = np.full(n, np.nan)
        self.pushd = {}           # per body vertex, the push of the garment's vertex over it (stage-1 m, quantized)
        self.push_scale = {}      # the garment's greatest push (its index push_m: the alpha's 1)
        self.geo = {}             # the base mesh as exported: (points stage-1, body vertex, push, own, hung)
        self.layering = {}
        self.skirt_rows = {}      # the third look lane: a skirt's hanging rows (human m) and its slot, at its full place
        self.pdir = {}            # per vertex of a garment's mesh, the line of its pushes (its exported normal)
        # the push's knots (human m): a garment's push takes its own share at each, so a garment worn under the hips'
        # part of it pushes that part, not the chest (PUSH_KNOT_MARKS)
        mark = {"hip": self.hip, "waist": self.waist_z, "shoulder": self.shoulder}
        self.knots = tuple(mark[k] + dz for k, dz in PUSH_KNOT_MARKS)

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
        if self.mode == "base":
            return                 # the base build records nothing: the envelope is the full places'
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
        env = self.fill_env(env)
        ok = np.nonzero(np.isfinite(env))[0]
        self.note(gid, GARMENTS[gid]["slot"], ok, env[ok])

    def clear(self, P, extra=0.0, rounds=3, own=None, along=None):
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
            if along is None:
                P += self.N[near] * short[:, None]
            else:
                # the W33 look lane: a point with a direction of its own (a cloak's hanging cloth: back, away from the
                # body) moves along it as far as lifts it clear; pushed along the skin's normal under the buttocks it
                # was pushed down and sideways across its neighbours (folds that showed the cloth's back)
                dirs = np.asarray(along, np.float64)
                has = np.linalg.norm(dirs, axis=1) > 0.5
                cos = np.clip(np.einsum("ij,ij->i", dirs, self.N[near]), 0.3, 1.0)
                step = np.where(has[:, None], dirs * (short / cos)[:, None], self.N[near] * short[:, None])
                P += step
        return P

    def kd_scaled(self):
        from scipy.spatial import cKDTree
        if getattr(self, "_kd_s", None) is None:
            self._kd_s = cKDTree(self.V * self.S)
        return self._kd_s

    def bridge(self, off, keep, iters=BRIDGE_ITERS):
        """Offsets (stage-1 m) raised where the skin under them is hollow (the cleft of the buttocks, under the
        breast, the small of the back): the shell's points are averaged over their neighbours inside ``keep`` and a
        point that the average lies further out than it is lifted to it, ``iters`` times. Cloth spans a hollow; it
        does not follow the skin into it. A convex place keeps its offset."""
        if iters <= 0:
            return off
        keep = np.asarray(keep, bool)
        inside = keep[self.edges[:, 0]] & keep[self.edges[:, 1]]
        a, b = self.edges[inside, 0], self.edges[inside, 1]
        cnt = np.zeros(self.n)
        np.add.at(cnt, a, 1.0)
        np.add.at(cnt, b, 1.0)
        has = cnt > 0
        off = np.asarray(off, np.float64).copy()
        VS = self.V * self.S
        for _ in range(iters):
            P = VS + self.N * off[:, None]
            # each neighbour's point measured along this vertex's normal: on a convex skin it lies below this point,
            # over a hollow above it; the mean of the neighbours and their highest, half and half
            ha = np.einsum("ij,ij->i", P[b] - VS[a], self.N[a])
            hb = np.einsum("ij,ij->i", P[a] - VS[b], self.N[b])
            acc = np.zeros(self.n)
            np.add.at(acc, a, ha)
            np.add.at(acc, b, hb)
            top = np.full(self.n, -np.inf)
            np.maximum.at(top, a, ha)
            np.maximum.at(top, b, hb)
            h = 0.5 * (acc / np.maximum(cnt, 1.0) + top)
            off = np.where(keep & has, np.maximum(off, h), off)
        return off

    def hang(self, off, keep, top_z, column=0.05, most=0.05):
        """Offsets (stage-1 m) of a skirt raised so its cloth falls straight below ``top_z`` (human m) instead of
        following the skin in under the buttocks, the belly or the hips: a vertex below it facing back (front, his
        side) stands at least as far back (forward, out) as the skirt above it in its column (``column`` human m
        wide), at most ``most`` more. The inner thighs (facing the other leg) keep their offsets."""
        keep = np.asarray(keep, bool)
        V, N, S = self.V, self.N, self.S
        P = V + N * (np.asarray(off) / S)[:, None]
        z = V[:, 2]
        sk = keep & (z < top_z)
        out = np.asarray(off, np.float64).copy()
        ids = np.nonzero(keep & (z < top_z + 0.04))[0]
        for axis, sel, sign in ((1, N[:, 1] > 0.3, 1.0), (1, N[:, 1] < -0.3, -1.0),
                                (0, (N[:, 0] * np.sign(V[:, 0]) > 0.45), 0.0)):
            cand = ids[sel[ids]]
            for v in np.nonzero(sk & sel)[0].tolist():
                other = 1 - axis
                near = cand[(np.abs(P[cand, other] - P[v, other]) < column) & (P[cand, 2] >= P[v, 2])
                            & ((np.sign(V[cand, 0]) == np.sign(V[v, 0])) | (axis == 1))]
                if len(near) == 0:
                    continue
                if axis == 1:
                    want = sign * (P[near, 1] * sign).max()
                    gap = (want - P[v, 1]) * sign
                    ncomp = abs(N[v, 1])
                else:
                    want = np.abs(P[near, 0]).max()
                    gap = want - abs(P[v, 0])
                    ncomp = abs(N[v, 0])
                if gap > 0.0:
                    out[v] = max(out[v], off[v] + min(most, gap / max(ncomp, 0.3) * S))
        return out

    def hull_fill(self, off, keep, top_z, low_z, most=0.06):
        """Offsets (stage-1 m) of a coat's back raised to the convex hull of each horizontal slice of it (2 cm high)
        between ``low_z`` and ``top_z`` (human m): the cloth spans the cleft of the buttocks and the hollows beside
        them, as a skirt hangs over them, instead of drawing each cheek round. Only the back (facing back, behind the
        hips' middle) and at most ``most`` (human m) more."""
        from scipy.spatial import ConvexHull
        keep = np.asarray(keep, bool)
        V, N, S = self.V, self.N, self.S
        out = np.asarray(off, np.float64).copy()
        P = V + N * (out / S)[:, None]
        yc = self.J["joint-pelvis"][1]
        band = keep & (V[:, 2] < top_z) & (V[:, 2] > low_z)
        back = band & (N[:, 1] > 0.15) & (V[:, 1] > yc)
        for z0 in np.arange(low_z, top_z, 0.02):
            sl = np.nonzero(band & (V[:, 2] >= z0) & (V[:, 2] < z0 + 0.02))[0]
            if len(sl) < 4:
                continue
            Q = P[sl, :2]
            try:
                hull = ConvexHull(Q)
            except Exception:
                continue
            eq = hull.equations                      # a x + b y + c <= 0 inside
            for v in sl[back[sl]].tolist():
                nh = N[v, :2]
                ln = float(np.linalg.norm(nh))
                if ln < 0.2:
                    continue
                dirv = nh / ln
                # the distance along the normal's horizontal part to the hull's boundary
                den = eq[:, :2] @ dirv
                num = -(eq[:, :2] @ P[v, :2] + eq[:, 2])
                t = num[den > 1e-9] / den[den > 1e-9]
                if len(t) == 0:
                    continue
                reach = float(t.min())
                if reach > 1e-4:
                    out[v] = max(out[v], out[v] + min(most, reach / ln) * S)
        return out

    def add_shell(self, gid, keep, off_st, seed=0, hem_noise=0.0, snaps=(), mat="giant_cloth", allowance=0.0,
                  bridge=None, hang_z=None, seat_z=None):
        slot = GARMENTS[gid]["slot"]
        off = self.resolve(slot, off_st, keep)
        if hang_z is not None:
            off = self.hull_fill(off, keep, hang_z, self.hip - 0.16)
            off = self.hang(off, keep, hang_z)
        elif seat_z is not None:
            off = self.hull_fill(off, keep, seat_z, self.hip - 0.16)     # (the seat spanned; nothing hangs)
        off = self.bridge(off, keep, BRIDGE_ITERS if bridge is None else bridge) + allowance
        ob, used = shell("Garment_" + gid, self.coll, self.rig, self.V, self.N, self.faces, self.fuv, self.uvs,
                         keep, off / self.S, self.weights, self.S, mat, seed=seed, hem_noise=hem_noise, snaps=snaps)
        self.note(gid, slot, used, off[used])
        self.built[gid] = (ob, used)
        self.shells[gid] = (used, off[used])
        self.exact[gid] = np.asarray(used)
        return ob

    def add_skirt(self, gid, keep, off_st, hem_z, flare, pleats=0, pleat_depth=0.0, clear=0.03, rows=9,
                  columns=None, thigh_follow=0.5, seed=0, mat="giant_cloth", snaps=(), bridge=SKIRT_BRIDGE_ITERS):
        """A skirt (the third look lane): the shell of ``keep`` (round the hips, above the crotch: its lower edge one
        loop) and below its lower edge rows of cloth hanging to ``hem_z`` (human m): each column falls from its loop
        vertex straight down and out (``flare`` m at the hem), never nearer the legs than ``clear`` outside the convex
        hull of their slice, never tucking in under the row above, with ``pleats`` knife pleats round the hips
        ``pleat_depth`` deep. ``columns``: a function of the loop's points giving which columns hang (the rest end at the
        loop: a loincloth's flaps). The rows take their column's skin weights, eased toward the thigh on their side by
        ``thigh_follow`` at the hem. A shell between legs cannot hang: it followed the thighs and read as shorts."""
        import split as sp_mod
        slot = GARMENTS[gid]["slot"]
        off = self.resolve(slot, off_st, keep)
        off = self.hull_fill(off, keep, self.hip + 0.12, self.hip - 0.16)     # (the seat spanned, as a coat's)
        off = self.bridge(off, keep, bridge)
        top, used = shell("Garment_" + gid, self.coll, self.rig, self.V, self.N, self.faces, self.fuv, self.uvs,
                          keep, off / self.S, self.weights, self.S, mat, snaps=snaps)
        me = top.data
        P = _co(top) / self.S
        F = np.array([list(pg.vertices) for pg in me.polygons], np.int64)
        luv = np.empty(len(me.loops) * 2)
        me.uv_layers[0].data.foreach_get("uv", luv)
        UVc = luv.reshape(-1, 2)
        FU = np.arange(len(me.loops), dtype=np.int64).reshape(len(F), 4)
        _remove_object(top)
        loops, _chains, _p = sp_mod.walk_loops(_boundary(F))
        loop = np.asarray(min(loops, key=lambda lp: float(np.mean(P[lp, 2]))), np.int64)
        m = len(loop)
        c = np.array([0.0, float(np.mean(P[loop, 1]))])
        rel = P[loop, :2] - c
        th = np.arctan2(rel[:, 1], rel[:, 0])
        # the loop's own winding: walked so the angle rises (the quads then face out)
        if np.sum(np.angle(np.exp(1j * (np.roll(th, -1) - th)))) < 0.0:
            loop, rel, th = loop[::-1], rel[::-1], th[::-1]
        rho0 = np.linalg.norm(rel, axis=1)
        D = rel / np.maximum(rho0, 1e-9)[:, None]
        from scipy.spatial import ConvexHull
        # the rows hang from the loop's convex hull (a column under the cleft of the buttocks hung deeper: a groove
        # down the skirt's back)
        rho_hang = np.maximum(rho0, np.nan_to_num(_hull_reach(np.tile(c, (m, 1)), D, ConvexHull(rel + c).equations),
                                                  nan=0.0, posinf=0.0))
        hang = np.ones(m, bool) if columns is None else np.asarray(columns(P[loop]), bool)
        legs = (self.B["thigh"] + self.B["calf"] + self.B["pelvis"] > 0.5) & (self.B["hand"] < 0.01) \
            & (self.B["lowerarm"] < 0.01)
        saw = np.abs(((pleats * th / (2.0 * np.pi)) % 1.0) * 2.0 - 1.0) if pleats else np.zeros(m)
        # the loop's corner UVs (each loop vertex's first corner)
        corner = {}
        for f, fu in zip(F.tolist(), FU.tolist()):
            for v, u in zip(f, fu):
                corner.setdefault(v, u)
        # the hanging cloth's own UVs (the third look lane): round the skirt by arc length from his left side and down
        # by height, at the body's density (the body's UVs carried down drew the back's seam as a line to the hem)
        circ = float(np.sum(np.linalg.norm(np.roll(rel, -1, axis=0) - rel, axis=1)))
        u = ((th - SKIRT_UV_SEAM) % (2.0 * np.pi)) / (2.0 * np.pi) * circ * SKIRT_UV_PER_M
        wrap = int(np.argmin(u))
        u_cols = np.concatenate([u, [u[wrap] + circ * SKIRT_UV_PER_M]])     # the seam's second copy
        newP, newUV, prev_rho = [], [], rho_hang.copy()
        z0 = P[loop, 2]
        hem_z = np.asarray(hem_z(P[loop]) if callable(hem_z) else np.full(m, float(hem_z)), np.float64)
        newUV.append(np.column_stack([u_cols, np.zeros(m + 1)]))
        for r in range(1, rows + 1):
            t = r / rows
            z = z0 + (hem_z - z0) * t
            rho = rho_hang + flare * t ** 1.2 + pleat_depth * (1.0 - saw) ** 1.5 * (0.3 + 0.7 * t)
            zr = float(np.mean(z))
            sl = np.nonzero(legs & (np.abs(self.V[:, 2] - zr) < 0.03))[0]
            if len(sl) >= 4:
                # the legs, and the garments of the inner slots over them (their envelope; none in the base build)
                lift = np.where(np.isnan(self.C[sl]), 0.0, (self.C[sl] + LAYER_GAP_M) / self.S)
                pts = [self.V[sl, :2] + self.N[sl, :2] * lift[:, None]]
                if self.mode == "full":
                    # and the hanging rows of the skirts of the inner slots (no envelope over the skin holds them)
                    for g2, (Q2, slot2) in self.skirt_rows.items():
                        if LAYER_ORDER.index(slot2) < LAYER_ORDER.index(slot):
                            near = np.abs(Q2[:, 2] - zr) < 0.04
                            if near.any():
                                rr = Q2[near, :2] - c
                                rn = np.linalg.norm(rr, axis=1, keepdims=True)
                                pts.append(c + rr * (1.0 + (LAYER_GAP_M / self.S) / np.maximum(rn, 1e-6)))
                eq = ConvexHull(np.concatenate(pts)).equations
                reach = _hull_reach(np.tile(c, (m, 1)), D, eq)
                rho = np.maximum(rho, np.where(np.isfinite(reach), reach + clear, 0.0))
            rho = np.maximum(rho, prev_rho)
            prev_rho = rho
            row = np.column_stack([c[0] + D[:, 0] * rho, c[1] + D[:, 1] * rho, z])
            newP.append(row)
            zc = np.concatenate([z0 - z, [(z0 - z)[wrap]]])
            newUV.append(np.column_stack([u_cols, -SKIRT_UV_PER_M * zc]))
        base_v, base_uv = len(P), len(UVc)
        P2 = np.concatenate([P] + newP)
        UV2 = np.concatenate([UVc] + newUV)
        faces, fuvs = [F], [FU]
        prev_v = loop
        for r in range(rows):
            cur_v = base_v + r * m + np.arange(m)
            j = np.arange(m)
            k = (j + 1) % m
            kk = np.where(k == wrap, m, k)             # the quad over the seam takes the seam's second copy
            pu = base_uv + r * (m + 1)
            cu = base_uv + (r + 1) * (m + 1)
            ok = hang[j] & hang[k]
            faces.append(np.stack([prev_v[j], prev_v[k], cur_v[k], cur_v[j]], axis=1)[ok])
            fuvs.append(np.stack([pu + j, pu + kk, cu + kk, cu + j], axis=1)[ok])
            prev_v = cur_v
        F2, FU2 = np.concatenate(faces), np.concatenate(fuvs)
        # the outward facing of the first hanging quad decides the winding
        q = F2[len(F)] if len(F2) > len(F) else None
        if q is not None:
            n_q = np.cross(P2[q[2]] - P2[q[0]], P2[q[3]] - P2[q[1]])
            mid = P2[q].mean(axis=0)
            if np.dot(n_q[:2], mid[:2] - c) < 0.0:
                F2[len(F):] = F2[len(F):, ::-1]
                FU2[len(F):] = FU2[len(F):, ::-1]
        # drop the rows' vertices no face uses (the columns that do not hang)
        usedv = np.unique(F2.ravel())
        remap = -np.ones(len(P2), np.int64)
        remap[usedv] = np.arange(len(usedv))
        P2, F2 = P2[usedv], remap[F2]
        src_loop = np.concatenate([np.full(base_v, -1), np.tile(np.arange(m), rows)])[usedv]
        row_t = np.concatenate([np.zeros(base_v), np.repeat(np.arange(1, rows + 1) / rows, m)])[usedv]
        body = np.concatenate([np.asarray(used, np.int64), np.tile(np.asarray(used, np.int64)[loop], rows)])[usedv]
        ob = gb.new_mesh_object("Garment_" + gid, P2 * self.S, F2, self.coll, UV2, FU2)
        # the skin: the shell's own body vertices; a hanging row its column's, eased toward its side's thigh
        inv = {}
        for bone, lst in self.weights.items():
            for vi, w in lst:
                if vi < self.n and w > 1e-4:
                    inv.setdefault(int(vi), []).append((bone, float(w)))
        for li in range(len(P2)):
            ws = dict(inv.get(int(body[li]), []))
            if src_loop[li] >= 0:
                side = sstep(abs(P2[li, 0]), 0.02, 0.10) * thigh_follow * sstep(row_t[li], 0.0, 0.35)
                bone = "thigh_l" if P2[li, 0] > 0.0 else "thigh_r"
                ws = {b: w * (1.0 - side) for b, w in ws.items()}
                ws[bone] = ws.get(bone, 0.0) + side
            for b, w in ws.items():
                if w > 1e-4:
                    vg = ob.vertex_groups.get(b) or ob.vertex_groups.new(name=b)
                    vg.add([li], float(w), "REPLACE")
        gb.parent_keep(ob, self.rig)
        gb.armature_modifier(ob, self.rig)
        ob.data.materials.append(_placeholder(mat))
        if self.mode == "full":
            self.skirt_rows[gid] = (P2[src_loop >= 0], slot)
        exact = np.where(src_loop >= 0, -1, body)
        shell_ids = body[src_loop < 0]
        self.note(gid, slot, shell_ids, off[shell_ids])
        self.built[gid] = (ob, body)
        self.shells[gid] = (shell_ids, off[shell_ids])
        self.exact[gid] = exact
        if (src_loop >= 0).any():
            ids, _lo, hmax = heights(P2[src_loop >= 0] * self.S, self.V * self.S, self.N, self.kd_scaled())
            if len(ids):
                self.note(gid, slot, ids, hmax + MAPPED_MARGIN_M)
        return ob

    def clear_skirts(self, P, slot, gap):
        """Points (human m) moved out from the hips' middle until each stands ``gap`` (human m) outside the hanging
        rows of the inner slots' skirts near it (the third look lane: a sash's tail over a kilt; full build only)."""
        P = np.asarray(P, np.float64).copy()
        if self.mode != "full":
            return P
        c = np.array([0.0, float(self.J["joint-pelvis"][1])])
        for g2, (Q2, slot2) in self.skirt_rows.items():
            if LAYER_ORDER.index(slot2) >= LAYER_ORDER.index(slot):
                continue
            rq = Q2[:, :2] - c
            aq = np.arctan2(rq[:, 1], rq[:, 0])
            nq = np.linalg.norm(rq, axis=1)
            for i in range(len(P)):
                rp = P[i, :2] - c
                ln = float(np.linalg.norm(rp))
                if ln < 1e-6:
                    continue
                ap = math.atan2(rp[1], rp[0])
                near = (np.abs(Q2[:, 2] - P[i, 2]) < 0.05) & (np.abs(np.angle(np.exp(1j * (aq - ap)))) < 0.2)
                if near.any():
                    want = float(nq[near].max()) + gap
                    if ln < want:
                        P[i, :2] = c + rp * (want / ln)
        return P

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
        """Every garment, slot by slot, at its full place (the envelope grows by it) and then over nothing (the mesh
        kept); returns ``built``. Then the layering table (``layering``)."""
        by_slot = {}
        for gid in ORDER:
            by_slot.setdefault(GARMENTS[gid]["slot"], []).append(gid)
        for slot in LAYER_ORDER:
            for gid in by_slot.get(slot, []):
                self.mode = "full"
                getattr(self, "g_" + gid)()
                full_ob, _ = self.built[gid]
                Pf = _co(full_ob)
                _remove_object(full_ob)
                keep_C = self.C
                self.C, self.mode = self.C0, "base"
                try:
                    getattr(self, "g_" + gid)()
                finally:
                    self.C, self.mode = keep_C, "full"
                self._push_field(gid, Pf)
            self.close(slot)
        self._layering()
        return self.built

    # ---- the W33 look lane: the pushes and the layering table ----------------------------------------------------
    def _body_of(self, gid, P):
        """The skin vertex of each point of a garment's mesh as the export takes it: the garment's own body vertex
        per vertex when it has one for each (a shell, a cloak, the sash), else the nearest."""
        body = np.asarray(self.built[gid][1], np.int64)
        if len(body) == len(P):
            return body
        return self.kd.query(P / self.S)[1]

    def _push_field(self, gid, Pf):
        """Per body vertex the push (stage-1 m along the skin's normal) that takes the base mesh's vertex over it to
        its full place, quantized up to the alpha's 255 steps of the garment's greatest push; a solidified band's
        outer layer reads the nearest skin vertex's, so the field is filled a few rings out."""
        ob, _ = self.built[gid]
        Pb = _co(ob)
        if len(Pb) != len(Pf):
            raise RuntimeError("%s: the full and the base builds differ in topology (%d, %d)" % (gid, len(Pf), len(Pb)))
        b = self._body_of(gid, Pb)
        ex = self.exact.get(gid)
        own_b = np.asarray(ex, np.int64) if ex is not None and len(ex) == len(Pb) else np.full(len(Pb), -1)
        pdir = self._push_dir(gid, ob, Pb, b, own_b)
        d = np.maximum(0.0, np.einsum("ij,ij->i", Pf - Pb, pdir))
        if gid not in self.shells:
            # a band, a cloak: at least the push that clears the envelope under it (the inner slots' places at their
            # full push) at the skin vertex it stands over, with the gap (a cloak's hanging cloth HANG_MARGIN_M more)
            tb = np.where(own_b >= 0, own_b, self._standing(Pb / self.S))
            cos = np.clip(np.einsum("ij,ij->i", pdir, self.N[tb]), 0.25, 1.0)
            hb = np.einsum("ij,ij->i", Pb - self.V[tb] * self.S, self.N[tb])
            hang = self._hang_margin(gid, Pb, own_b)
            C = self.C[tb]
            need = np.where(np.isfinite(C), (C + LAYER_GAP_M + hang - hb) / cos, 0.0)
            d = np.maximum(d, need)
            if GARMENTS[gid].get("free"):
                # a cloak's hanging cloth hangs as one sheet: below a bulge it keeps the bulge's push (the push of
                # the rearmost cloth above it in its column, as the hang itself)
                hung = np.nonzero(own_b < 0)[0]
                hx, hz, hd = Pb[hung, 0], Pb[hung, 2], d[hung].copy()
                for k in range(len(hung)):
                    above = (np.abs(hx - hx[k]) < CLOAK_PUSH_COLUMN * self.S) & (hz >= hz[k])
                    d[hung[k]] = max(d[hung[k]], float(hd[above].max()))
            d = _ramp_limit(ob, Pb, d, PUSH_RAMP)
        D = np.full(self.n, np.nan)
        np.fmax.at(D, b, d)
        a, c = self.edges[:, 0], self.edges[:, 1]
        for _ in range(PUSH_FILL_RINGS):
            hole = np.isnan(D)
            if not hole.any():
                break
            nxt = D.copy()
            np.fmax.at(nxt, a, np.where(hole[a], D[c], np.nan))
            np.fmax.at(nxt, c, np.where(hole[c], D[a], np.nan))
            D = np.where(hole, nxt, D)
        D = np.nan_to_num(D, nan=0.0)
        scale = float(D.max())
        if scale > 1e-6:
            D = np.ceil(D / scale * 255.0 - 1e-6) / 255.0 * scale
        self.pushd[gid] = D
        self.push_scale[gid] = scale if scale > 1e-6 else 0.0
        # the base mesh as the export writes it (its own vertices: a band is solidified already): its points, skin
        # vertices and pushes
        Pe = Pb
        be = b
        ex = self.exact.get(gid)
        own = np.asarray(ex, np.int64) if ex is not None and len(ex) == len(Pe) else np.full(len(Pe), -1)
        hung = self._hang_margin(gid, Pe, own)
        # the skin vertex each point stands over (its own, else as ``clear`` picks it) and how much of the push along
        # its exported normal (its body vertex's) lifts it over that one
        tb = np.where(own >= 0, own, self._standing(Pe / self.S))
        cosf = np.clip(np.einsum("ij,ij->i", pdir, self.N[tb]), 0.25, 1.0)
        self.geo[gid] = (Pe, be, D[be], own, hung, tb, cosf, pdir)
        # the envelope the outer slots clear is this garment's place at its whole push (what the shader can draw)
        slot = GARMENTS[gid]["slot"]
        E = self.E.setdefault(slot, np.full(self.n, np.nan))
        for k in range(PUSH_SAMPLES):        # (a cloak's hanging cloth may stand over other skin part way)
            E = np.fmax(E, self._env_at(gid, k / (PUSH_SAMPLES - 1.0)))
        self.E[slot] = E

    def _push_dir(self, gid, ob, P, b, own):
        """Per vertex of a garment's mesh the line the cloth shader pushes it along (its exported normal): the skin
        vertex's normal, but a cloak's hanging cloth takes its own surface's, eased in as it leaves the back (with
        the skin's normal under it the hanging cloth was shaded by the muscles of the back it no longer lies on)."""
        N = self.N[b]
        if gid in SMOOTH_PUSH_DIR:
            # the third look lane: a skirt's band over the seat pushes (and shades) along the skin's normals smoothed
            # over its own mesh (with the skin's own the tunic drew the buttocks' cheeks)
            fade = sstep(self.hip + 0.15 - P[:, 2] / self.S, 0.0, 0.10)[:, None]      # (the seat only)
            N = N * (1.0 - fade) + _smooth_dirs(ob.data, N, CLOAK_NORMAL_SMOOTH) * fade
            N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
            self.pdir[gid] = N
            return N
        if not GARMENTS[gid].get("free") or "hang_z" not in ob:
            self.pdir[gid] = N
            return N
        me = ob.data
        own_n = np.empty(len(me.vertices) * 3)
        me.vertices.foreach_get("normal", own_n)
        own_n = own_n.reshape(-1, 3)
        own_n *= np.where(np.einsum("ij,ij->i", own_n, N) < 0.0, -1.0, 1.0)[:, None]
        # the third look lane: where the cloth lies on the back, the skin's normals smoothed over the cloak's own mesh
        # (with the skin's own the cloak drew the back's muscles, a painted shirt)
        # (not on the shoulders, where the shoulders' garments lie over it: their layering reads the skin's normals)
        fade = sstep(self.shoulder - 0.25 - P[:, 2] / self.S, 0.0, 0.12)[:, None]
        N = N * (1.0 - fade) + _smooth_dirs(me, N, CLOAK_NORMAL_SMOOTH) * fade
        N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
        w = np.where(own < 0, sstep(float(ob["hang_z"]) - P[:, 2] / self.S, 0.0, float(ob.get("hang_ease", 0.12))), 0.0)
        # leaning back: the hanging cloth is pushed (by the layering and the build) mostly straight back, a sheet
        hang_n = own_n + np.array([0.0, 1.5, 0.0])
        hang_n /= np.maximum(np.linalg.norm(hang_n, axis=1, keepdims=True), 1e-9)
        out = N * (1.0 - w)[:, None] + hang_n * w[:, None]
        out /= np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)
        self.pdir[gid] = out
        return out

    def _hang_margin(self, gid, P, own):
        """Per point of a cloak (stage-1 coordinates) the margin its hanging cloth keeps more over what lies under it:
        HANG_MARGIN_M eased in below where it leaves the back, as ``build_cape`` clears it; 0 elsewhere."""
        ob = self.built[gid][0]
        if not GARMENTS[gid].get("free") or "hang_z" not in ob:
            return np.zeros(len(P))
        return np.where(own < 0, HANG_MARGIN_M * sstep(float(ob["hang_z"]) - P[:, 2] / self.S, 0.0, 0.15), 0.0)

    def _standing(self, P):
        """The skin vertex each point (human m) stands over, as ``clear`` picks it."""
        _, cand = self.kd.query(P, k=6)
        rel = P[:, None, :] - self.V[cand]
        hh = np.einsum("ijk,ijk->ij", rel, self.N[cand])
        side = np.linalg.norm(rel - self.N[cand] * hh[..., None], axis=2)
        pick = np.argmin(np.where(hh > -0.01, side, np.inf), axis=1)
        return cand[np.arange(len(P)), pick]

    def _env_at(self, gid, s):
        """The garment's standoff per body vertex (stage-1 m, nan where it is not) with a share ``s`` of its push, as
        the envelope measures it (a shell over its own skin vertices; the rest by ``heights`` with MAPPED_MARGIN_M,
        two rings out)."""
        Pe, be, d, own, _hung, _tb, _cosf, pdir = self.geo[gid]
        P = Pe + (s * d)[:, None] * pdir
        env = np.full(self.n, np.nan)
        mine = own >= 0
        if mine.any():
            h = np.einsum("ij,ij->i", P[mine] - self.V[own[mine]] * self.S, self.N[own[mine]])
            np.fmax.at(env, own[mine], h)
        if (~mine).any():
            ids, _lo, hmax = heights(P[~mine], self.V * self.S, self.N, self.kd_scaled())
            env[ids] = np.fmax(env[ids], hmax + MAPPED_MARGIN_M)
        if gid not in self.shells:
            env = self.fill_env(env)
        return env

    def fill_env(self, env, rings=2):
        """A measured envelope's gaps (skin vertices no point of the garment stood over) filled ``rings`` out with
        the highest neighbour's (the W33 look lane: only the gaps; P54 raised every vertex to its neighbours' highest,
        which lifted a garment's envelope over a hollow - the cleft of the buttocks - to the cheeks' height)."""
        a, b = self.edges[:, 0], self.edges[:, 1]
        for _ in range(rings):
            hole = np.isnan(env)
            if not hole.any():
                break
            nxt = env.copy()
            np.fmax.at(nxt, a, np.where(hole[a], env[b], np.nan))
            np.fmax.at(nxt, b, np.where(hole[b], env[a], np.nan))
            env = np.where(hole, nxt, env)
        return env

    def _layering(self):
        """``layering``: {"order": the garments from the skin out, "push": {outer: {inner: [the least share of the
        outer garment's push that keeps it LAYER_GAP_M (a cloak's hanging cloth HANG_MARGIN_M more) over the inner
        one at each of PUSH_SAMPLES shares of the inner one's push]}}, "short": {outer|inner: the gap still missing
        at the outer garment's full push}} (pairs that need no push are left out)."""
        order = [g for slot in LAYER_ORDER for g in ORDER if GARMENTS[g]["slot"] == slot]
        layer = {g: LAYER_ORDER.index(GARMENTS[g]["slot"]) for g in order}
        samples = np.linspace(0.0, 1.0, PUSH_SAMPLES)
        envs = {}
        for g in order:
            # each share's envelope at least the smaller shares' (the table is read at the share at or above)
            run = np.full(self.n, np.nan)
            for k, sv in enumerate(samples):
                run = np.fmax(run, self._env_at(g, sv))
                envs[(g, k)] = run
        push, short = {}, {}
        for g in order:
            Pe, _be, d0, _own, hung, be, cosf, _pdir = self.geo[g]
            d = d0 * cosf
            hb = np.einsum("ij,ij->i", Pe - self.V[be] * self.S, self.N[be])
            margin = LAYER_GAP_M + hung
            row = {}
            for h in order:
                if layer[h] >= layer[g]:
                    continue
                vals = []
                wk = self.knot_weights(Pe[:, 2] / self.S) > 0.0      # (points, knots): the knots each point reads
                for k in range(PUSH_SAMPLES):
                    E = envs[(h, k)][be]
                    over = np.isfinite(E)
                    need = np.where(over, E + margin - hb, -np.inf)
                    s_i = np.where(need > 0.0, need / np.maximum(d, 1e-9), 0.0)
                    bad = (need > 1e-4) & (d < 1e-6)
                    s_i = np.where(bad, 1.0, s_i)
                    if (s_i > 1.0).any() or bad.any():
                        miss = float(np.max(np.where(bad | (s_i > 1.0), need - d, -np.inf)))
                        key = "%s|%s" % (h, g)
                        short[key] = max(short.get(key, 0.0), miss)
                        if _DEBUG and k == PUSH_SAMPLES - 1:
                            i = int(np.argmax(np.where(bad | (s_i > 1.0), need - d, -np.inf)))
                            print("[layering] %s s=1 short %.4f at point %d/%d body %d z %.3f: hb %.4f d %.4f (d0 %.4f "
                                  "cos %.2f) E %.4f" % (key, miss, i, len(Pe), be[i], self.V[be[i], 2], hb[i], d[i], d0[i],
                                                       cosf[i], envs[(h, k)][be[i]]), flush=True)
                    # each knot's share: the greatest any point that reads it needs (so any mix of knots is enough)
                    for j in range(len(self.knots)):
                        sj = float(s_i[wk[:, j]].max()) if wk[:, j].any() else 0.0
                        vals.append(float(min(1.0, math.ceil(max(0.0, sj) * 1000.0) / 1000.0)))
                if max(vals) > 0.0:
                    row[h] = vals
            if row:
                push[g] = row
        self.layering = {"order": order, "push": push, "short": short,
                         "knots_m": [float(k * self.S) for k in self.knots]}

    def knot_weights(self, z):
        """(points, knots) the share of each knot's push a point at rest height ``z`` (human m) takes: the lowest knot's
        below it, the highest's above, and between two knots a smoothstep from the one to the other (the cloth shader's
        push_weights, from the point's rest height in UV2.x)."""
        z = np.asarray(z, np.float64)
        K = self.knots
        W = np.zeros((len(z), len(K)))
        W[:, 0] = z <= K[0]
        W[:, -1] = z >= K[-1]
        for j in range(len(K) - 1):
            inside = (z > K[j]) & (z < K[j + 1])
            t = sstep(z, K[j], K[j + 1])
            W[:, j] = np.where(inside, 1.0 - t, W[:, j])
            W[:, j + 1] = np.where(inside, t, W[:, j + 1])
        return W

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
        # the third look lane: a pleated wrap hanging from the belt to the knee - the hips' shell above the crotch and
        # below it a skirt of its own (add_skirt) that bridges the legs (the shell followed each thigh: shorts from behind)
        hem = kn + 0.035
        keep = self._legs(w - 0.004, hp - KILT_CUT_BELOW_HIP) & (z > hp - KILT_CUT_BELOW_HIP)
        V = self.V
        th = np.arctan2(V[:, 1], V[:, 0])
        saw = np.abs(((13.0 * th / (2.0 * np.pi)) % 1.0) * 2.0 - 1.0)
        down = np.clip((hp + 0.06 - z) / 0.12, 0, 1)
        off = SLOT_SHELL_M["legs"] + 0.004 + (0.006 + 0.012 * (1.0 - saw) ** 1.5) * down * self.S
        self.add_skirt("kilt", keep, off, hem, flare=0.05, pleats=KILT_PLEATS, pleat_depth=0.03, clear=0.03, rows=9,
                       thigh_follow=SKIRT_THIGH_FOLLOW)

    def g_loincloth(self):
        z, w, hp = self.z, self.waist_z, self.hip
        # the third look lane: a band round the hips and two flaps hanging from it, the front to a hand under the
        # crotch, the back to mid-thigh over the seat (a shell's back flap followed the buttocks round and left them bare)
        keep = self._legs(w - 0.004, hp - KILT_CUT_BELOW_HIP) & (z > hp - KILT_CUT_BELOW_HIP)
        off = np.full(self.n, SLOT_SHELL_M["legs"] + 0.004 * self.S)
        yc = self.J["joint-pelvis"][1]

        def flaps(Q):
            return np.abs(Q[:, 0]) < LOINCLOTH_FLAP_HALF_M

        def hem(Q):
            return np.where(Q[:, 1] > yc, self.mid_thigh, hp - 0.23)

        self.add_skirt("loincloth", keep, off, hem, flare=0.03, clear=0.02, rows=8, columns=flaps, thigh_follow=0.35)

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
        # the third look lane: the skirt hangs from the hips to mid-thigh as cloth of its own (add_skirt; the shell
        # followed the buttocks and the thighs round: briefs on the Iron Veteran)
        keep = keep & (z > hip - KILT_CUT_BELOW_HIP)
        off = np.full(self.n, 0.022 * self.S)
        self.add_skirt("tunic", keep, off, mid_thigh, flare=0.035, clear=0.02, rows=6, thigh_follow=SKIRT_THIGH_FOLLOW,
                       snaps=[self.upsnap(cut_t)], bridge=BRIDGE_ITERS)

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
        # (the third look lane: its hem spans the cleft of the buttocks as a coat's does, over the braies' seat)
        self.add_shell("shirt", keep, off, snaps=[self.lowsnap(cuff), self.zsnap(bottom)], seat_z=self.hip + 0.04)

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
            sel_a = dang < BAND_SECTOR
            r = rad_c[sel_a].max() if sel_a.any() else 0.2
            ring.append(centre + d * (r + LAYER_GAP_M / S + 0.002))
        ring = np.array(ring)
        for _ in range(3):
            ring = 0.5 * ring + 0.25 * (np.roll(ring, 1, axis=0) + np.roll(ring, -1, axis=0))
        # the smoothing may pull a ring point inside the envelope: push it back out
        for i in range(n_seg):
            a = 2 * math.pi * i / n_seg
            dang = np.abs((ang_c - a + math.pi) % (2 * math.pi) - math.pi)
            sel_a = dang < BAND_SECTOR
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
        sol = ob.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = thickness * S
        sol.offset = 1.0
        # the W33 look lane: solidified here, and every vertex (both layers) on the skin vertex it stands over (its
        # weights, its build weights and its normal, the line the cloth shader pushes it along), not the nearest one
        # (on the waist's curve the nearest vertex's normal leaned up or down: a push along it slid the band off)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.modifier_apply(modifier=sol.name)
        body = self._standing(_co(ob) / S)
        self.exact[gid] = body
        _skin_from_body(ob, self.weights, body)
        gb.parent_keep(ob, self.rig)
        gb.armature_modifier(ob, self.rig)
        ob.data.materials.append(_placeholder(mat))
        self.built[gid] = (ob, body)
        self.ray_env(gid, ob, np.unique(np.concatenate([body, ids])), body)
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
        verts = self.clear_skirts(verts, "waist", (0.012 + HANG_MARGIN_M) / S)
        faces = []
        for r in range(rows):
            for c in range(cols):
                a = r * (cols + 1) + c
                faces.append((a, a + 1, a + cols + 2, a + cols + 1))
        tail = gb.new_mesh_object("_sash_tail", verts * S, np.array(faces), self.coll)
        # one solid strip: join the tail to the band after the band's solidify (a single mesh, one draw call)
        tail.data.materials.append(_placeholder("giant_cloth"))
        sol = tail.modifiers.new("Solidify", "SOLIDIFY")
        sol.thickness = 0.003 * S
        sol.offset = 1.0
        bpy.context.view_layer.objects.active = tail
        bpy.ops.object.modifier_apply(modifier=sol.name)
        bpy.context.view_layer.objects.active = band
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
        # the W33 look lane: the band and its tail each on the skin vertex it stands over (the tail follows the hip)
        body_all = self._standing(np.array([v.co[:] for v in band.data.vertices]) / S)
        self.exact["sash"] = body_all
        _skin_from_body(band, self.weights, body_all)
        gb.armature_modifier(band, self.rig)
        self.built["sash"] = (band, body_all)
        self.ray_env("sash", band, np.unique(body_all), body_all)

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
        # the third look lane: the skirt hangs from the hips as cloth of its own (add_skirt), over a kilt's or a tunic's
        keep = keep & (z > self.hip - KILT_CUT_BELOW_HIP)
        # (it hangs off the seat as mail over its padding does: a shirt's or braies' seat under it needs no push there)
        seat = sstep(self.V[:, 1] - self.J["joint-pelvis"][1], 0.0, 0.06) * sstep(z, self.hip - 0.18, self.hip - 0.10)
        off = SLOT_SHELL_M["armour"] + 0.008 + HAUBERK_SEAT_M * seat
        self.add_skirt("mail_hauberk", keep, off, hem, flare=0.03, clear=0.025, rows=6,
                       thigh_follow=SKIRT_THIGH_FOLLOW, mat="giant_metal", snaps=[self.upsnap(0.5)])

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
        keep = keep & (z > self.hip - KILT_CUT_BELOW_HIP)      # (the third look lane: a skirt of its own, add_skirt)
        off = np.full(self.n, SLOT_SHELL_M["armour"] + 0.011)
        self.add_skirt("scale_coat", keep, off, hem, flare=0.03, clear=0.025, rows=5, thigh_follow=SKIRT_THIGH_FOLLOW,
                       mat="giant_metal")

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
                              clear=lambda P, own, extra: w.clear(P, extra, own=own, along=np.where(
                                  (np.asarray(own) < 0)[:, None], np.array([[0.0, 1.0, 0.0]]), 0.0)),
                              bridge=lambda off, keep: w.bridge(off * w.S, keep, CLOAK_BRIDGE_ITERS) / w.S)
        # the cut part stands over its own skin vertex, unless the hang moved it; the rows below the body's cut do not
        w.exact[gid] = np.asarray(ob["exact_ids"], np.int64)
        # the W33 look lane: the hanging cloth takes the skin vertex it hangs over (its build weights, its normal: the
        # line the cloth shader pushes it along), not the hem's it was carried down from
        hung = w.exact[gid] < 0
        used = np.asarray(used, np.int64).copy()
        if hung.any():
            used[hung] = w._standing(_co(ob)[hung] / w.S)
        w.built[gid] = (ob, used)
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
        face = (V[:, 1] < L["head_cy"] - 0.02) & ((V[:, 0] / 0.072) ** 2 + ((z - zc) / rz) ** 2 < 1.0)
        # (W33: the opening narrower than P54's 0.088 wide: the ears were in it and stood out of the hood)
        # the W33 look lane: a hood, not a coif - it stands well off the crown, falls loose to a point behind the head
        # and over the nape, and its sides hang out from the cheeks (it sat tight)
        behind = sstep(V[:, 1], L["head_cy"] - 0.02, L["head_cy"] + 0.08)
        rim = self.neck_z + 0.065 - 0.02 * behind               # a little lower behind, over the nape
        keep = (hn > 0.5) & (z > rim) & ~face
        back = sstep(V[:, 1], L["head_cy"], L["head_cy"] + 0.11) * sstep(z, L["ear_z"][1], L["top"])
        point = np.exp(-((z - (L["top"] - 0.06)) / 0.07) ** 2) * sstep(V[:, 1], L["head_cy"] + 0.02, L["head_cy"] + 0.12)
        side = sstep(L["ear_z"][1] + 0.02 - z, 0, 0.10) * (1.0 - 0.6 * behind)
        off = SLOT_SHELL_M["head"] + 0.036 + 0.055 * back + 0.050 * point + 0.025 * side \
            + 0.025 * sstep(L["ear_z"][0] - z, 0, 0.08)
        self.add_shell("hood", keep, off, snaps=[(z - rim, 0.0, np.tile([0.0, 0.0, 1.0], (self.n, 1)), 0.03)],
                       bridge=SKIRT_BRIDGE_ITERS)

    def _cap(self, gid, front, back, crown, mat, ridge=0.0, band=0.0):
        """A skull cap: the scalp above ``front`` (at the brow) and ``back`` (round the ears and the nape)."""
        hn, L = self._head()
        V, z = self.V, self.z
        frontness = sstep(L["head_cy"] - V[:, 1], -0.02, 0.06)
        rim = back + (front - back) * frontness
        keep = (self.B["head"] > 0.9) & (z > rim)
        crest = ridge * np.exp(-(V[:, 0] / 0.018) ** 2) * sstep(z, rim + 0.04, rim + 0.08)
        brim = band * np.exp(-((z - rim) / 0.018) ** 2)
        # the second look lane: the rim closes in on the brow, the temples and the nape (the cap stood its whole
        # crown's height off the skin there: it sat high, with a gap under it at the brow); the dome keeps it
        rise = sstep(z, rim, rim + 0.05)
        off = np.maximum(SLOT_SHELL_M["head"] * (0.55 + 0.45 * rise) + crown * (0.3 + 0.7 * rise), CAP_RIM_LEAST_M) \
            + crest + brim
        self.add_shell(gid, keep, off, snaps=[(z - rim, 0.0, np.tile([0.0, 0.0, 1.0], (self.n, 1)), 0.03)], mat=mat)
        return keep, off

    def g_leather_cap(self):
        L = self.bd.landmarks
        self._cap("leather_cap", L["brow_z"] + 0.012, L["ear_z"][1] + 0.006, 0.024, "giant_leather", band=0.004)

    def g_iron_helm(self):
        L = self.bd.landmarks
        self._cap("iron_helm", L["brow_z"] - 0.002, L["ear_z"][1] - 0.012, 0.028, "giant_metal", ridge=0.008,
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
CAPE = dict(offset=0.05, flare=0.035, column=0.10, fold_depth=0.016, folds=9.0, hem_noise=0.035, hang_below=0.18, ease=0.12, let_go_below=0.375,
            collar_lo=0.045, collar_hi=0.012, collar_offset=0.03, extend=0.0, extend_rows=0, extend_flare=0.0,
            extend_spread=0.0, end_noise=0.0, seed=11)


def build_cape(bd, rig, coll, weights, S, layout, V, N, faces, fuv, B, z, shoulder, hip, neck_z, p=None,
               name="Garment_cape", need=None, mat="giant_cloth", clear=None, bridge=None):
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
    # the W33 look lane: the middle of the back down to the hem whatever its normals (the cleft of the buttocks left a
    # notch in the hem, and the long cloaks' rows hung from the notch folded back on themselves)
    keep = keep | ((np.abs(V[:, 0]) < 0.08) & (V[:, 1] > 0.0) & (z > hip - 0.03) & (z < shoulder - 0.1))
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
    if bridge is not None:
        off = bridge(off, keep)          # the W33 look lane: the cloth spans the spine's groove and the hollows
    shell_v = V + N * off[:, None]
    hang = keep & back & (z < hang_z)
    idx = np.nonzero(hang)[0]
    y = shell_v[:, 1].copy()
    # the W33 look lane: each hanging vertex falls from the rearmost cloth above it in its column - the shoulder
    # blades' and the shoulders' too (P54 looked at the hanging cloth only, which began under the blades and stepped
    # off the back there) - and leaves the back over ``ease`` below hang_z, not at once
    cand = np.nonzero(keep & back)[0]
    cx, cz, cy = shell_v[cand, 0], shell_v[cand, 2], shell_v[cand, 1]
    for vi in idx.tolist():
        above = (np.abs(cx - shell_v[vi, 0]) < p["column"]) & (cz >= shell_v[vi, 2])
        if above.any():
            y[vi] = cy[above].max()
    y = shell_v[:, 1] + (y - shell_v[:, 1]) * sstep(hang_z - z, 0.0, p["ease"])
    y = np.where(hang, smooth_field(y, faces, n, 3), y)
    y = np.maximum(y, shell_v[:, 1])
    rng = np.random.default_rng(p["seed"])
    ph = rng.random() * 6.28
    fold = p["fold_depth"] * down ** 1.2 * np.sin(p["folds"] * shell_v[:, 0] / 0.2 + ph)
    y = np.where(hang, y + p["flare"] * down ** 1.5 + fold, y)
    pos = shell_v.copy()
    pos[:, 1] = y
    # the W33 look lane: the hanging cloth's breadth smoothed (the walls of the buttocks' cleft overhang: flattened to
    # one depth they folded the cloth over itself, its back showing)
    xs = np.where(hang, smooth_field(shell_v[:, 0], faces, n, 10), shell_v[:, 0])
    pos[:, 0] = shell_v[:, 0] + (xs - shell_v[:, 0]) * sstep(hang_z - z, 0.0, p["ease"]) \
        * sstep(0.12 - np.abs(V[:, 0]), 0.0, 0.04)      # (the middle only: the sheet keeps its breadth)
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
        # (the third look lane: over the shoulders' sides a little more, where a raised arm stretches the skin under it)
        extra = extra + np.where(exact >= 0, CLOAK_ARM_MARGIN_M / S * sstep(np.abs(P[:, 0]), 0.16, 0.22), 0.0)
        P = clear(P, exact, extra)
    ob = gb.new_mesh_object(name, P * S, FL, coll, uvs, FUV)
    ob["exact_ids"] = exact.tolist()
    ob["hang_z"] = float(hang_z)
    ob["hang_ease"] = float(p["ease"])
    body_groups = {}
    for bone, lst in weights.items():
        w = np.zeros(n)
        for vi, wt in lst:
            if vi < n:
                w[vi] = wt
        if w[body_ids].max() > 1e-4:
            body_groups[bone] = w[body_ids]
    # the cloth stays on the body's weights down to let_go_below under the shoulders (P54's height: it hung from
    # 0.29 m), then the chains carry it (the W33 look lane: hanging from higher up, the cloth over the small of the back
    # on the chains showed the back through it when the spine bent)
    groups = gp.chain_weights(P * S, body_groups, layout, let_go_z=(shoulder - p["let_go_below"]) * S) if layout is not None \
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
    print("[garment] hem chain fallback: %d hem vertices, %d ends, %d branching" % (
        len(hs), len(ends), sum(1 for nb in adj.values() if len(nb) > 2)), flush=True)
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
def build_accessories(w, ring_slots=RING_SLOTS, only=None, bare=False):
    """{accessory id: object}: every accessory placed clear of the whole wardrobe's envelope (w.C after the last
    slot), 100 % on its bone; a ring (the neck's, the arm's) clear of ``ring_slots``' envelope (the W33 look lane: ()
    gives its place on the bare skin, the ring's mesh; ``ring_push`` its push to its place over those slots). The
    second look lane: ``bare`` places a belt's trophy on the bare skin (its mesh; ``trophy_push`` its push out)."""
    S = w.S
    out = {}
    w.ring_slots = ring_slots
    w.trophy_bare = bare
    for aid in ACCESSORY_ORDER:
        if only is not None and aid not in only:
            continue
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


def ring_push(w, base, full):
    """The W33 look lane: the rings' layering. ``base``, ``full``: {accessory id: object} on the bare skin and over
    RING_SLOTS' envelope (the same topology). Returns {accessory id: (per vertex push stage-1 m along the skin's normal,
    quantized as a garment's; its scale; {inner garment: [shares, PUSH_SAMPLES x knots]})}: a ring's push is one share,
    so every knot of a sample carries it."""
    S = w.S
    order = [g for g in ORDER if GARMENTS[g]["slot"] in RING_SLOTS]
    samples = np.linspace(0.0, 1.0, PUSH_SAMPLES)
    envs = {}
    for g in order:
        run = np.full(w.n, np.nan)
        for k, sv in enumerate(samples):
            run = np.fmax(run, w._env_at(g, sv))
            envs[(g, k)] = run
    out = {}
    for aid, ob in base.items():
        Pb, Pf = _co(ob), _co(full[aid])
        near = w.kd.query(Pb / S)[1]
        N = w.N[near]
        d = np.maximum(0.0, np.einsum("ij,ij->i", Pf - Pb, N))
        scale = float(d.max())
        if scale > 1e-6:
            d = np.ceil(d / scale * 255.0 - 1e-6) / 255.0 * scale
        hb = np.einsum("ij,ij->i", Pb - w.V[near] * S, N)
        rows = {}
        for g in order:
            vals = []
            for k in range(PUSH_SAMPLES):
                E = envs[(g, k)][near]
                need = np.where(np.isfinite(E), E + LAYER_GAP_M - hb, -np.inf)
                si = np.where(need > 0.0, need / np.maximum(d, 1e-9), 0.0)
                sv = float(min(1.0, math.ceil(max(0.0, float(si.max())) * 1000.0) / 1000.0))
                vals += [sv] * len(w.knots)
            if max(vals) > 0.0:
                rows[g] = vals
        out[aid] = (d, scale, rows)
    return out


def _ring_clear(w, centre, axis, sel, gap, push=False, slots=None, spread=True):
    """Per angle (32 sectors) round ``axis`` through ``centre``: the largest distance from the axis of the skin
    pushed out by the wardrobe's envelope (``slots``' alone when given), over the body vertices ``sel``, plus ``gap``
    (human metres)."""
    axis = np.asarray(axis, np.float64) / np.linalg.norm(axis)
    a = np.cross(axis, [0.0, 0.0, 1.0] if abs(axis[2]) < 0.9 else [1.0, 0.0, 0.0])
    a /= np.linalg.norm(a)
    b = np.cross(axis, a)
    ids = np.nonzero(sel)[0]
    C = w.C
    if slots is not None:
        C = np.full(w.n, np.nan)
        for slot in slots:
            if slot in w.E:
                C = np.fmax(C, w.E[slot])
    cover = (np.where(np.isnan(C[ids]), 0.0, C[ids]) + (w.push[ids] if push else 0.0)) / w.S
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
    if spread:
        out = np.maximum(out, np.maximum(np.roll(out, 1), np.roll(out, -1)))
    else:
        out = np.maximum(out, 0.5 * (np.roll(out, 1) + np.roll(out, -1)))   # (a slice: smoothed, not widened)
    return a, b, out + gap


def _ring_path(centre, a, b, radii, m, open_deg=0.0, start=-math.pi):
    pts = []
    span = 2 * math.pi - math.radians(open_deg)
    for i in range(m):
        th = start + math.radians(open_deg) / 2 + span * i / (m - 1 if open_deg else m)
        k = int(((th + math.pi) % (2 * math.pi)) / (2 * math.pi) * 32) % 32
        pts.append(centre + radii[k] * (math.cos(th) * a + math.sin(th) * b))
    return np.array(pts)


CAP_RIM_LEAST_M = 0.031   # the second look lane: a cap's rim stands at least this far off (stage 1): the crop's shells
#                           (their top and LAYER_GAP_M) stay under it
TORC_TILT = 0.26       # the second look lane: a torc's ring drops this much (m a m) from its back to its front, which
#                        rests on the collarbones (it went round the neck level with the chin, a bar under the beard)
TORC_GAP = 0.004       # ... and a ring's clearance over what it sits on (human m; LAYER_GAP_M's 8 mm stood it off)


def _acc_neck(w, aid):
    L = w.bd.landmarks
    J = w.J
    torc = aid != "tooth_necklace"
    zt = w.neck_z + (0.012 if torc else 0.035)
    centre = np.array([0.0, J["joint-neck"][1] + 0.005, zt])
    tube_r = {"iron_torc": 0.011, "gilded_torc": 0.012, "tooth_necklace": 0.004}[aid]
    if torc:
        # the second look lane: tilted by TORC_TILT, its front lower: the plane through the back at zt; a vertex is near
        # the ring when it lies within 2 cm of that plane (the neck's and the collarbones' skin and what is worn there)
        tilt = TORC_TILT
        plane_z = zt + (w.V[:, 1] - centre[1]) * tilt
        sel = (np.abs(w.z - plane_z) < 0.02) & ((w.B["neck"] + w.torso) > 0.5) & (w.B["head"] < 0.3) \
            & (np.abs(w.V[:, 0]) < 0.16)
        a, b, radii = _ring_clear(w, centre, [0.0, 0.0, 1.0], sel, tube_r + TORC_GAP, slots=w.ring_slots)
    else:
        # the neck's own skin and what is worn on it (a collar's rim further out is fur: a torc sits on it, P54.md)
        sel = (np.abs(w.z - zt) < 0.025) & (w.B["neck"] > 0.55) & (w.B["head"] < 0.3)
        a, b, radii = _ring_clear(w, centre, [0.0, 0.0, 1.0], sel, tube_r + LAYER_GAP_M / w.S, slots=w.ring_slots)
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
    if torc:
        path[:, 2] += (path[:, 1] - centre[1]) * tilt
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
    # the second look lane: round the biceps (at three quarters of the way to the elbow the skin there bends with the
    # forearm and the rigid ring stood off it as a hoop in the relaxed pose)
    t = {"iron_arm_ring": 0.5, "bronze_arm_spiral": 0.48, "gilded_arm_ring": 0.52}[aid]
    sh, el = w.sh, w.el
    axis = el - sh
    centre = sh + axis * t
    # the second look lane: the skin a ring closes round is its own slice of the arm (5 % of the upper arm wide: a
    # tenth stood it off by the biceps' bulge) and it clears it by TORC_GAP (it stood off like a hoop)
    sel = (np.abs(w.t_up - t) < (0.05 if aid == "bronze_arm_spiral" else 0.025)) & (w.V[:, 0] > 0.05) \
        & (w.B["upperarm"] > 0.6)
    tube_r = {"iron_arm_ring": 0.012, "bronze_arm_spiral": 0.0075, "gilded_arm_ring": 0.010}[aid]
    a, b, radii = _ring_clear(w, centre, axis, sel, tube_r + TORC_GAP, slots=w.ring_slots, spread=False)
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
    # (the third look lane: hung at the skin's widest point, out as far as the covered ring's widest - the skirts' seats
    # moved the covered ring's widest point behind the hip, and the trophy with it)
    k = int(np.argmax(w.V[ids, 0] * side))
    root = P[k].copy()
    root[0] = side * float(np.max(P[:, 0] * side))
    root = root + np.array([side, 0.0, 0.0]) * (LAYER_GAP_M / w.S + 0.012)
    if getattr(w, "trophy_bare", False):
        # the second look lane: on the bare skin the trophy hangs from the same height and depth, nearer in (along X
        # alone: trophy_push moves it back out as far as what is worn needs)
        Pb = w.V[ids] + w.N[ids] * (w.push[ids] / w.S)[:, None]
        root[0] = side * float(np.max(Pb[:, 0] * side)) + side * (LAYER_GAP_M / w.S + 0.012)
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


def _trophy_env(w):
    """The envelope a belt's trophy is placed over (stage-1 m per skin vertex): the whole wardrobe's, or none (the bare
    skin, w.trophy_bare: the trophy's mesh since the second look lane)."""
    if getattr(w, "trophy_bare", False):
        return np.zeros(w.n)
    return np.where(np.isnan(w.C), 0.0, w.C)


def trophy_push(w, base, full):
    """The second look lane: a belt's trophies' layering, as ``ring_push`` gives a ring's. ``base``, ``full``:
    {accessory id: object} on the bare skin and clear of the whole wardrobe (the same topology, moved along +-X).
    Returns {accessory id: (per vertex push stage-1 m along its side, quantized as a garment's; its scale; {inner
    garment: [shares, PUSH_SAMPLES x knots]})}: the least share of the push that keeps the trophy LAYER_GAP_M clear of
    the inner garment's envelope at each of its shares (the trophy is rigid: one share for every knot). The drinking
    horn stood a hand off the hip when only braies were worn under it (it cleared the fullest wardrobe's envelope)."""
    S = w.S
    samples = np.linspace(0.0, 1.0, PUSH_SAMPLES)
    out = {}
    for aid, ob in base.items():
        side = 1.0 if aid == "drinking_horn" else -1.0
        Pb, Pf = _co(ob) / S, _co(full[aid]) / S
        shift = float(np.max((Pf[:, 0] - Pb[:, 0]) * side))
        d = np.full(len(Pb), max(shift, 0.0) * S)
        scale = float(d.max())
        if scale > 1e-6:
            d = np.ceil(d / scale * 255.0 - 1e-6) / 255.0 * scale
        _, near = w.kd.query(Pb)
        rows = {}
        for g in ORDER:
            vals = []
            run = np.full(w.n, np.nan)
            for k, sv in enumerate(samples):
                run = np.fmax(run, w._env_at(g, sv))
                E = run[near]
                ok = np.isfinite(E)
                if not ok.any() or scale <= 1e-6:
                    vals += [0.0] * len(w.knots)
                    continue
                skin = w.V[near] + w.N[near] * ((np.where(ok, E, 0.0) + w.push[near]) / S + LAYER_GAP_M / S + 0.004)[:, None]
                need = np.where(ok, (skin[:, 0] - Pb[:, 0]) * side, -np.inf).max() * S
                sv_need = float(min(1.0, math.ceil(max(0.0, need / scale) * 1000.0) / 1000.0))
                vals += [sv_need] * len(w.knots)
            if max(vals) > 0.0:
                rows[g] = vals
        out[aid] = (d, scale, rows)
    return out


def _clear_hang(w, verts, side):
    """Moves a hanging trophy outward (along +-X) until every vertex clears the envelope under it."""
    _, near = w.kd.query(verts)
    cover = (_trophy_env(w)[near] + w.push[near]) / w.S
    skin = w.V[near] + w.N[near] * (cover + LAYER_GAP_M / w.S + 0.004)[:, None]
    push = np.max(np.maximum(0.0, (skin[:, 0] - verts[:, 0]) * side))
    return verts + np.array([side * push, 0.0, 0.0])
