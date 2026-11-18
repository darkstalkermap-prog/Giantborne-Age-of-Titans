"""The body's three-way split, its 16 regions, the cut loops and their caps (numpy only).

The game draws the body as three meshes (plan §2.6): ``Body_Head`` (scalp, face, neck; render
layer 3), ``Body_Torso`` (chest, belly, back, pelvis; layer 2) and ``Body_Limbs`` (arms, hands,
legs, feet; layer 1). Every face of the hm08 body goes to one part by its vertices' skinning
weights (head + neck, the spine, clavicles and pelvis, or a limb), the boundary is cleaned of
spikes and islands, and every cut between two parts must be a simple closed loop: the neck, two
shoulders and two hips. Each loop is capped on both sides with a fan of triangles (region 15),
so a part seen from inside is closed.

Regions are stored per vertex in the mesh's colour as ``(id + 0.5) / 16`` and decoded in the
shader as ``int(COLOR.r * 16.0)``. Pure numpy, so ``test_giant_tools.py`` checks it without Blender.
"""
from __future__ import annotations

import numpy as np

import mh_data as mh

PARTS = ("head", "torso", "limbs")
PART_MESH = {"head": "Body_Head", "torso": "Body_Torso", "limbs": "Body_Limbs"}
PART_LAYER = {"head": 3, "torso": 2, "limbs": 1}
REGIONS = ("scalp", "face", "neck", "chest", "belly", "upper_back", "lower_back", "pelvis",
           "upper_arm", "forearm", "hand", "thigh", "knee", "shin", "foot", "cap")
REGION_ID = {name: i for i, name in enumerate(REGIONS)}
CAP_REGION = 15
PART_REGIONS = {"head": (0, 1, 2), "torso": (3, 4, 5, 6, 7), "limbs": (8, 9, 10, 11, 12, 13, 14)}
# The design regions of the appearance record (plan §2.3, §2.6): which body regions each covers.
DESIGN_REGIONS = {"face": (1,), "chest": (3, 4), "back": (5, 6), "arms": (8, 9)}
KNEE_BAND = 0.12          # human-scale metres either side of the knee joint
EXPECTED_LOOPS = {("head", "torso"): 1, ("limbs", "torso"): 4}


def encode_region(ids):
    """The colour channel value of region ids: (id + 0.5) / 16."""
    return (np.asarray(ids, np.float64) + 0.5) / 16.0


def decode_region(values):
    """The shader's decoding: int(value * 16) (truncation, never rounding)."""
    return np.floor(np.asarray(values, np.float64) * 16.0).astype(np.int64)


# --------------------------------------------------------------------------------------
# topology helpers
# --------------------------------------------------------------------------------------
def face_edges(faces):
    """Directed edges of polygon faces (F, k): (F*k, 2) and the face of each edge."""
    faces = np.asarray(faces)
    k = faces.shape[1]
    e = np.stack([faces, np.roll(faces, -1, axis=1)], axis=2).reshape(-1, 2)
    return e, np.repeat(np.arange(len(faces)), k)


def edge_faces(faces):
    """{undirected edge (a, b) with a < b: [face indices]}."""
    e, fi = face_edges(faces)
    out = {}
    for (a, b), f in zip(e.tolist(), fi.tolist()):
        key = (a, b) if a < b else (b, a)
        out.setdefault(key, []).append(f)
    return out


def face_neighbours(faces):
    """For every face, the faces sharing an edge with it (list of lists)."""
    nb = [[] for _ in range(len(faces))]
    for fs in edge_faces(faces).values():
        if len(fs) == 2:
            a, b = fs
            nb[a].append(b)
            nb[b].append(a)
    return nb


def boundary_edges(faces, weld=None):
    """Undirected edges used by exactly one face (after mapping vertex ids through ``weld``)."""
    faces = np.asarray(faces)
    if weld is not None:
        faces = np.asarray(weld)[faces]
    e, _ = face_edges(faces)
    e = np.sort(e, axis=1)
    e = e[e[:, 0] != e[:, 1]]
    u, c = np.unique(e, axis=0, return_counts=True)
    return u[c == 1]


def weld_positions(P, tol=1e-5):
    """A welding map: vertex -> id of the first vertex at the same (quantized) position."""
    q = np.round(np.asarray(P, np.float64) / tol).astype(np.int64)
    _, first, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
    return first[inv.ravel()]


def walk_loops(edges):
    """Edges (E, 2) -> (closed loops as vertex lists, open chains, pinch vertices). A loop is
    closed when every vertex on it has exactly two of the edges."""
    adj = {}
    for a, b in np.asarray(edges).tolist():
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    pinches = sorted(v for v, n in adj.items() if len(n) > 2)
    seen_e = set()
    loops, chains = [], []
    for start in sorted(adj):
        for nxt in sorted(adj[start]):
            if (start, nxt) in seen_e:
                continue
            path = [start]
            prev, cur = start, nxt
            seen_e.add((start, nxt))
            seen_e.add((nxt, start))
            closed = False
            while True:
                path.append(cur)
                if cur == start:
                    closed = True
                    path.pop()
                    break
                cands = [w for w in sorted(adj[cur]) if (cur, w) not in seen_e]
                if len(adj[cur]) != 2 or not cands:
                    break
                w = cands[0]
                seen_e.add((cur, w))
                seen_e.add((w, cur))
                prev, cur = cur, w
            (loops if closed else chains).append(path)
    return loops, chains, pinches


def orient_loop(loop, faces):
    """The loop ordered so that every directed edge (loop[i], loop[i+1]) occurs in ``faces``'
    winding (the side whose faces these are); the cap then runs each edge the other way."""
    dirs = set(map(tuple, face_edges(faces)[0].tolist()))
    a, b = loop[0], loop[1]
    if (a, b) in dirs:
        return list(loop)
    if (b, a) in dirs:
        return list(reversed(loop))
    raise ValueError("orient_loop: the loop's first edge is in none of the faces")


# --------------------------------------------------------------------------------------
# parts
# --------------------------------------------------------------------------------------
BONE_FAMILIES = {
    "head": ("head",), "neck": ("neck_01",), "spine3": ("spine_03",), "spine2": ("spine_02",),
    "spine1": ("spine_01",), "clav": ("clavicle_",), "pelvis": ("pelvis", "Root"),
    "upperarm": ("upperarm_",), "lowerarm": ("lowerarm_",),
    "hand": ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"),
    "thigh": ("thigh_",), "calf": ("calf_",), "foot": ("foot_", "ball_"),
}


def bone_sums(weights, n=mh.N_BODY_VERTS):
    """Per-vertex weight sums of the game_engine bone families above."""
    return mh.family_sums(weights, n, BONE_FAMILIES)


def part_weights(B):
    """(n, 3) weights of head, torso and limbs from the bone-family sums of bone_sums()."""
    head = B["head"] + B["neck"]
    torso = B["spine3"] + B["spine2"] + B["spine1"] + B["clav"] + B["pelvis"]
    limbs = B["upperarm"] + B["lowerarm"] + B["hand"] + B["thigh"] + B["calf"] + B["foot"]
    return np.stack([head, torso, limbs], axis=1)


def assign_parts(faces, vert_part_w, max_iter=40, min_island=40):
    """Face parts (0 head, 1 torso, 2 limbs): the largest summed weight over the face's vertices,
    then spikes (a face with most of its neighbours in one other part) and small islands are
    flipped, and pinch vertices of the cut resolved, until stable."""
    faces = np.asarray(faces)
    fp = np.argmax(vert_part_w[faces].sum(axis=1), axis=1)
    nb = face_neighbours(faces)
    for _ in range(max_iter):
        changed = 0
        # spikes: at least 3 of 4 neighbours in another single part (2 of 3 at a boundary)
        for f in range(len(faces)):
            ns = nb[f]
            if not ns:
                continue
            counts = np.bincount(fp[ns], minlength=3)
            other = int(np.argmax(np.where(np.arange(3) == fp[f], -1, counts)))
            if counts[other] > len(ns) / 2.0 and counts[other] > counts[fp[f]]:
                fp[f] = other
                changed += 1
        # islands: connected components of one part smaller than min_island faces
        comp = _components(fp, nb)
        for cid in np.unique(comp):
            members = np.nonzero(comp == cid)[0]
            if len(members) >= min_island:
                continue
            around = [fp[g] for f in members for g in nb[f] if comp[g] != cid]
            if around:
                fp[members] = int(np.bincount(around, minlength=3).argmax())
                changed += len(members)
        # pinches: a cut vertex with more than two cut edges
        cuts = cut_edges(faces, fp)
        _, _, pinches = walk_loops(cuts)
        for v in pinches:
            fs = np.nonzero(np.any(faces == v, axis=1))[0]
            # flip the face of the smaller part around the vertex to the larger one
            parts = fp[fs]
            counts = np.bincount(parts, minlength=3)
            minor = int(np.argmin(np.where(counts > 0, counts, 1 << 30)))
            major = int(np.argmax(counts))
            fp[fs[parts == minor][:1]] = major
            changed += 1
        if changed == 0:
            break
    return fp


def _components(fp, nb):
    comp = -np.ones(len(fp), np.int64)
    cid = 0
    for s in range(len(fp)):
        if comp[s] >= 0:
            continue
        stack = [s]
        comp[s] = cid
        while stack:
            f = stack.pop()
            for g in nb[f]:
                if comp[g] < 0 and fp[g] == fp[f]:
                    comp[g] = cid
                    stack.append(g)
        cid += 1
    return comp


def cut_edges(faces, fp):
    """Undirected edges between faces of different parts."""
    out = []
    for (a, b), fs in edge_faces(faces).items():
        if len(fs) == 2 and fp[fs[0]] != fp[fs[1]]:
            out.append((a, b))
    return np.asarray(out, np.int64).reshape(-1, 2)


def cut_loops(faces, fp):
    """{(part a, part b) sorted by name: [loops]} of the cut; raises on open chains or pinches."""
    faces = np.asarray(faces)
    out = {}
    ef = edge_faces(faces)
    pair_edges = {}
    for (a, b), fs in ef.items():
        if len(fs) == 2 and fp[fs[0]] != fp[fs[1]]:
            key = tuple(sorted((PARTS[fp[fs[0]]], PARTS[fp[fs[1]]])))
            pair_edges.setdefault(key, []).append((a, b))
    for key, edges in sorted(pair_edges.items()):
        loops, chains, pinches = walk_loops(np.asarray(edges))
        if chains or pinches:
            raise ValueError("cut %s: %d open chains, pinch vertices %s" % (key, len(chains), pinches[:6]))
        out[key] = loops
    return out


# --------------------------------------------------------------------------------------
# regions
# --------------------------------------------------------------------------------------
def vertex_regions(part, V, B, masks, joints):
    """Region id per vertex for one part (human-scale Blender coordinates: Z up, front -Y)."""
    n = len(V)
    z, y = V[:, 2], V[:, 1]
    if part == "head":
        r = np.where(B["neck"] > B["head"], REGION_ID["neck"],
                     np.where(masks["m_scalp"] > 0.5, REGION_ID["scalp"], REGION_ID["face"]))
        return r.astype(np.int64)
    if part == "torso":
        fam = np.stack([B["pelvis"], B["spine1"], B["spine2"], B["spine3"], B["clav"]], axis=1)
        pelvis = np.argmax(fam, axis=1) == 0
        sp = [joints[k] for k in ("joint-spine-4", "joint-spine-3", "joint-spine-2", "joint-spine-1", "joint-neck")]
        sz = np.array([p[2] for p in sp])
        sy = np.array([p[1] for p in sp])
        y_spine = np.interp(z, sz, sy)
        back = y > y_spine
        upper = z > joints["joint-spine-2"][2]
        r = np.where(back, np.where(upper, REGION_ID["upper_back"], REGION_ID["lower_back"]),
                     np.where(upper, REGION_ID["chest"], REGION_ID["belly"]))
        return np.where(pelvis, REGION_ID["pelvis"], r).astype(np.int64)
    knee_z = 0.5 * (joints["joint-l-knee"][2] + joints["joint-r-knee"][2])
    near_knee = np.abs(z - knee_z) <= KNEE_BAND
    fam = np.stack([B["upperarm"] + B["clav"], B["lowerarm"], B["hand"],
                    (B["thigh"] + B["pelvis"]) * (z > knee_z + KNEE_BAND),
                    (B["thigh"] + B["calf"]) * near_knee,
                    B["calf"] * (z < knee_z - KNEE_BAND), B["foot"]], axis=1)
    return np.asarray(PART_REGIONS["limbs"])[np.argmax(fam, axis=1)].astype(np.int64)


def face_regions(faces, vregion):
    """The region of every face: the most common region of its vertices (ties: the lowest id)."""
    r = vregion[np.asarray(faces)]
    out = np.empty(len(r), np.int64)
    for i, row in enumerate(r):
        out[i] = np.bincount(row, minlength=16).argmax()
    return out


# --------------------------------------------------------------------------------------
# caps
# --------------------------------------------------------------------------------------
def fan_cap(loop, P, lift=0.0):
    """A fan over an oriented loop: (centre position, triangles as (b, a, -1) with -1 the centre,
    the cap's unit normal). ``lift`` moves the centre along the normal (garment caps sit just
    outside the skin's)."""
    loop = list(loop)
    pts = P[loop]
    c = pts.mean(axis=0)
    tris = []
    nsum = np.zeros(3)
    for i in range(len(loop)):
        a, b = loop[i], loop[(i + 1) % len(loop)]
        tris.append((b, a, -1))
        nsum += np.cross(P[a] - c, P[b] - c)
    # the skin's faces run a->b; the cap runs b->a, so its normal is minus the loop's winding normal
    nrm = -nsum / (np.linalg.norm(nsum) + 1e-12)
    return c + nrm * lift, tris, nrm


def nearest_bone(point, heads, names):
    """The name among ``names`` whose bone head is nearest ``point``."""
    best = min(names, key=lambda b: float(np.linalg.norm(np.asarray(heads[b]) - point)))
    return best


# --------------------------------------------------------------------------------------
# the body
# --------------------------------------------------------------------------------------
def body_split(V, faces, weights, masks, joints):
    """The hm08 body's split (human-scale vertices V of the body group, its quads):
    {"B": bone sums, "part_w": (n, 3), "face_part": (F,), "loops": {pair: [loops]},
     "vregion": {part: (n,) region id, -1 outside the part}, "face_region": (F,)}."""
    faces = np.asarray(faces)
    n = len(V)
    B = bone_sums(weights, n)
    pw = part_weights(B)
    fp = assign_parts(faces, pw)
    loops = cut_loops(faces, fp)
    counts = {k: len(v) for k, v in loops.items()}
    if counts != EXPECTED_LOOPS:
        raise ValueError("body_split: cut loops %s, expected %s" % (counts, EXPECTED_LOOPS))
    vregion = {}
    face_region = np.empty(len(faces), np.int64)
    for pi, part in enumerate(PARTS):
        sel = fp == pi
        vids = np.unique(faces[sel].ravel())
        r = -np.ones(n, np.int64)
        r[vids] = vertex_regions(part, V[vids], {k: v[vids] for k, v in B.items()},
                                 {k: v[vids] for k, v in masks.items()}, joints)
        vregion[part] = r
        face_region[sel] = face_regions(faces[sel], r)
    return {"B": B, "part_w": pw, "face_part": fp, "loops": loops, "vregion": vregion,
            "face_region": face_region}
