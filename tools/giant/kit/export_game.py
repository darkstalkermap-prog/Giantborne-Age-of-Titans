"""The giant's meshes as one skinned glTF for Godot 4.6 (the steps --body, --garments, --hair).

Builds the kit's giant at the stage-1 height (3.6576 m; the game scales Visual/Body by
k = height / 3.6576) on the MPFB2 "game_engine" skeleton (53 bones) with its CC0 weights, no
subdivision, and writes into one glTF binary, every mesh on the one armature:

  Body_Head, Body_Torso, Body_Limbs   the hm08 body split at the neck, shoulders and hips (split.py),
                                      every cut capped on both sides, the joined body's normals kept,
                                      the 16 region ids in COLOR_0.r
  Eyes                                both eyes (low-poly spheres, the pole looks along the gaze)
  Hair_long_back, Hair_crop,          cards grown on the unsubdivided surface (giant_hair.py)
  Beard_full, Beard_short
  Garment_<id>[_core|_limbs]          the seven garments (giant_garment.py); the braies and the tunic
                                      split at the body's boundary with their cut loops capped; the
                                      boots decimated toward 2,500 triangles

and ``export_info.json`` beside it: per mesh its node, category, render layer, dye slot, detail map,
triangles, the regions it covers, its cut loops and caps; the landmarks (the skeleton's joints at
stage 1 in the game frame: +X the giant's right, +Y up, -Z his front) and the body's hash.

Usage (the shared venv): python export_game.py <out dir>
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils.bvhtree import BVHTree  # noqa: E402

import giant_body as gb  # noqa: E402
import giant_garment as gg  # noqa: E402
import giant_hair as gh  # noqa: E402
import mh_data as mh  # noqa: E402
import split  # noqa: E402

H = gb.STAGE1_HEIGHT_M
GLB_NAME = "giant.glb"
INFO_NAME = "export_info.json"
EYE_SEGMENTS, EYE_RINGS = 20, 14
GARMENT_CAP_LIFT_M = 0.02          # human scale: a garment's cap sits this far outside the skin's
COVER_SHARE = 0.97                 # a region a garment covers this much of sinks under it (covers)
COVER_RAY_M = 0.12                 # human scale: the longest skin-to-garment ray that still covers
SPLIT_GARMENTS = ("braies", "tunic")
WHOLE_PART = {"belt": "torso", "jerkin": "torso", "furs": "torso", "bracers": "limbs", "boots": "limbs"}
LIMB_ROOTS = ("upperarm_l", "upperarm_r", "thigh_l", "thigh_r")
TORSO_ROOTS = ("clavicle_l", "clavicle_r", "pelvis")


def log(*a):
    print("[export]", *a, flush=True)


def r6(x):
    return float(round(float(x), 6))


# --------------------------------------------------------------------------------------
# mesh arrays <-> Blender objects
# --------------------------------------------------------------------------------------
def mesh_arrays(ob):
    """{"V", "faces" (list of tuples), "corner_uv" (list of lists of (u, v)), "groups" {bone: (n,)},
    "vnormal" (n, 3)} of an object's mesh (no modifiers applied)."""
    me = ob.data
    n = len(me.vertices)
    V = np.empty(n * 3)
    me.vertices.foreach_get("co", V)
    V = V.reshape(-1, 3)
    nrm = np.empty(n * 3)
    me.vertex_normals.foreach_get("vector", nrm)
    loop_v = np.empty(len(me.loops), np.int64)
    me.loops.foreach_get("vertex_index", loop_v)
    uvl = me.uv_layers.get("UVMap") or (me.uv_layers[0] if len(me.uv_layers) else None)
    uv = np.zeros(len(me.loops) * 2)
    if uvl is not None:
        uvl.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    faces, corner_uv = [], []
    for p in me.polygons:
        ls = range(p.loop_start, p.loop_start + p.loop_total)
        faces.append(tuple(int(loop_v[i]) for i in ls))
        corner_uv.append([(float(uv[i, 0]), float(uv[i, 1])) for i in ls])
    groups = {}
    names = [g.name for g in ob.vertex_groups]
    for v in me.vertices:
        for g in v.groups:
            nm = names[g.group]
            if nm not in groups:
                groups[nm] = np.zeros(n)
            groups[nm][v.index] = g.weight
    return {"V": V, "faces": faces, "corner_uv": corner_uv, "groups": groups,
            "vnormal": nrm.reshape(-1, 3)}


def make_object(name, A, coll, rig, material, vregion=None):
    """A skinned mesh object from arrays: V, faces, corner_uv, groups, corner_normal (list per face),
    and the region per vertex in a "Color" attribute when ``vregion`` is given."""
    me = bpy.data.meshes.new(name)
    me.from_pydata(np.asarray(A["V"], np.float64).tolist(), [], [list(f) for f in A["faces"]])
    me.update()
    uvl = me.uv_layers.new(name="UVMap")
    uvl.data.foreach_set("uv", np.asarray([c for f in A["corner_uv"] for c in f], np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    me.normals_split_custom_set([tuple(c) for f in A["corner_normal"] for c in f])
    if vregion is not None:
        col = me.color_attributes.new("Color", "BYTE_COLOR", "POINT")
        rgba = np.zeros((len(A["V"]), 4), np.float32)
        rgba[:, 0] = split.encode_region(vregion)
        rgba[:, 3] = 1.0
        col.data.foreach_set("color", rgba.ravel())
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    for bone in sorted(A["groups"]):
        w = A["groups"][bone]
        idx = np.nonzero(w > 1e-4)[0]
        if len(idx) == 0:
            continue
        vg = ob.vertex_groups.new(name=bone)
        for i in idx.tolist():
            vg.add([i], float(w[i]), "REPLACE")
    gb.parent_keep(ob, rig)
    gb.armature_modifier(ob, rig)
    ob.data.materials.append(bpy.data.materials.get(material) or bpy.data.materials.new(material))
    return ob


def triangles(A):
    return int(sum(len(f) - 2 for f in A["faces"]))


# --------------------------------------------------------------------------------------
# split and cap
# --------------------------------------------------------------------------------------
def split_part(A, face_part, part, vregion, root_bone, lift=0.0, cap_uv_of=None):
    """The arrays of one part of a mesh (its faces, their vertices) with every closed cut loop
    capped: rim copies of the loop's vertices (their skin weights, region 15, the cap's normal)
    and a centre vertex weighted 100 % to ``root_bone(part, centre, other part)``.
    Returns (arrays, regions per local vertex, {"loops", "capped", "open_chains"})."""
    faces = A["faces"]
    sel = [i for i, p in enumerate(face_part) if p == part]
    vids = sorted({v for i in sel for v in faces[i]})
    local = {v: k for k, v in enumerate(vids)}
    V = [A["V"][v] for v in vids]
    out_faces = [tuple(local[v] for v in faces[i]) for i in sel]
    out_uv = [list(A["corner_uv"][i]) for i in sel]
    out_nrm = [[tuple(A["vnormal"][v]) for v in faces[i]] for i in sel]
    groups = {b: [w[v] for v in vids] for b, w in A["groups"].items()}
    reg = [int(vregion[v]) for v in vids]
    # the cut: edges between a face of this part and a face of another
    ef = {}
    for i, f in enumerate(faces):
        for k in range(len(f)):
            a, b = f[k], f[(k + 1) % len(f)]
            ef.setdefault((min(a, b), max(a, b)), []).append(i)
    cut, other_of = [], {}
    for (a, b), fs in ef.items():
        if len(fs) == 2 and (face_part[fs[0]] == part) != (face_part[fs[1]] == part):
            cut.append((a, b))
            other_of[(a, b)] = face_part[fs[1]] if face_part[fs[0]] == part else face_part[fs[0]]
    loops, chains, pinches = split.walk_loops(np.asarray(cut, np.int64).reshape(-1, 2))
    stats = {"loops": len(loops), "capped": 0, "open_chains": len(chains), "pinches": len(pinches)}
    part_faces = np.asarray([faces[i] for i in sel], dtype=object)
    # every corner UV of a vertex inside this part (the cap's UV is one of the loop's own)
    corner_uvs = {}
    for i in sel:
        for v, uv in zip(faces[i], A["corner_uv"][i]):
            corner_uvs.setdefault(v, uv)
    for loop in sorted(loops, key=lambda l: (len(l), min(l))):
        oriented = split.orient_loop(loop, [faces[i] for i in sel])
        P = np.asarray(A["V"], np.float64)
        centre, tris, nrm = split.fan_cap(oriented, P, lift)
        a0, b0 = sorted((oriented[0], oriented[1]))
        other = other_of[(a0, b0)]
        bone = root_bone(part, centre, other)
        uvs = np.asarray([corner_uvs[v] for v in oriented])
        cap_uv = tuple(uvs[int(np.argmin(np.linalg.norm(uvs - uvs.mean(axis=0), axis=1)))])
        if cap_uv_of is not None:
            cap_uv = cap_uv_of(cap_uv)
        rim = {}
        for v in oriented:
            rim[v] = len(V)
            V.append(A["V"][v])
            for b in groups:
                groups[b].append(A["groups"][b][v])
            reg.append(split.CAP_REGION)
        c = len(V)
        V.append(centre)
        for b in groups:
            groups[b].append(1.0 if b == bone else 0.0)
        if bone not in groups:
            groups[bone] = [0.0] * len(V)
            groups[bone][c] = 1.0
        reg.append(split.CAP_REGION)
        for (b, a, _c) in tris:
            out_faces.append((rim[b], rim[a], c))
            out_uv.append([cap_uv, cap_uv, cap_uv])
            out_nrm.append([tuple(nrm)] * 3)
        stats["capped"] += 1
    del part_faces
    arrays = {"V": np.asarray(V, np.float64), "faces": out_faces, "corner_uv": out_uv,
              "corner_normal": out_nrm, "groups": {b: np.asarray(w) for b, w in groups.items()}}
    return arrays, np.asarray(reg, np.int64), stats


def boundary_count(A):
    """Open boundary edges of a mesh's arrays, vertices welded by position."""
    weld = split.weld_positions(A["V"], 1e-6)
    tri = []
    for f in A["faces"]:
        for k in range(1, len(f) - 1):
            tri.append((f[0], f[k], f[k + 1]))
    return int(len(split.boundary_edges(np.asarray(tri, np.int64), weld)))


# --------------------------------------------------------------------------------------
# eyes
# --------------------------------------------------------------------------------------
def eye_arrays(frames):
    """Both eyes in one mesh: UV spheres whose pole looks along the gaze; uv.y = 1 - polar angle / pi
    (Blender's v: the pupil at the top of the texture space, uv.y = 0 in Godot)."""
    V, F, UVs, N = [], [], [], []
    for side in ("L", "R"):
        c, r, g = frames[side]
        base = len(V)
        verts, uvs_v = [], []
        for ri in range(EYE_RINGS + 1):
            th = np.pi * ri / EYE_RINGS
            for s in range(EYE_SEGMENTS + 1):
                ph = 2 * np.pi * s / EYE_SEGMENTS
                verts.append((np.sin(th) * np.cos(ph), np.sin(th) * np.sin(ph), np.cos(th)))
                uvs_v.append((s / EYE_SEGMENTS, 1.0 - ri / EYE_RINGS))
        z = np.asarray(g, float) / np.linalg.norm(g)
        x = np.cross([0.0, 0.0, 1.0], z)
        x /= np.linalg.norm(x)
        y = np.cross(z, x)
        R = np.stack([x, y, z], axis=1)
        unit = np.asarray(verts) @ R.T
        V.extend((unit * (r * 1.02) + np.asarray(c)).tolist())
        N.extend(unit.tolist())
        UVs.extend(uvs_v)
        for ri in range(EYE_RINGS):
            for s in range(EYE_SEGMENTS):
                a = base + ri * (EYE_SEGMENTS + 1) + s
                F.append((a, a + EYE_SEGMENTS + 1, a + EYE_SEGMENTS + 2, a + 1))
    V = np.asarray(V)
    return {"V": V, "faces": F, "corner_uv": [[UVs[v] for v in f] for f in F],
            "corner_normal": [[tuple(N[v]) for v in f] for f in F], "groups": {"head": np.ones(len(V))}}


# --------------------------------------------------------------------------------------
# landmarks, hash, coverage
# --------------------------------------------------------------------------------------
def godot(v):
    """Blender (+X the giant's left, -Y his front, +Z up) -> the game's actor frame after the
    180 degree turn GiantModel applies (+X right, +Y up, -Z front)."""
    return [r6(-v[0]), r6(v[2]), r6(v[1])]


def landmarks(rig, eye_centres):
    bones = rig.data.bones

    def head(b):
        return np.asarray(bones[b].head_local, np.float64)

    out = {}
    for s in ("r", "l"):
        sh, el, wr = head(f"upperarm_{s}"), head(f"lowerarm_{s}"), head(f"hand_{s}")
        palm = (head(f"index_01_{s}") + head(f"middle_01_{s}") + head(f"ring_01_{s}")) / 3.0
        out[f"shoulder_{s}"] = godot(sh)
        out[f"elbow_{s}"] = godot(el)
        out[f"wrist_{s}"] = godot(wr)
        out[f"palm_{s}"] = godot(palm)
        out[f"hip_{s}"] = godot(head(f"thigh_{s}"))
        out[f"knee_{s}"] = godot(head(f"calf_{s}"))
        out[f"ankle_{s}"] = godot(head(f"foot_{s}"))
        out[f"reach_{s}"] = r6(np.linalg.norm(el - sh) + np.linalg.norm(wr - el) + np.linalg.norm(palm - wr))
    out["eye_mid"] = godot((np.asarray(eye_centres["L"]) + np.asarray(eye_centres["R"])) / 2.0)
    out["head"] = godot(head("head"))
    out["neck"] = godot(head("neck_01"))
    out["pelvis"] = godot(head("pelvis"))
    return out


def body_hash(V, faces, fuv, uvs, weights, part, face_region, rig):
    """sha256 of what decision 9 freezes after W25: the body's positions, faces, UVs, weights,
    parts and regions, and the skeleton's rest bones."""
    h = hashlib.sha256()
    h.update(np.round(np.asarray(V, np.float64), 6).astype(np.float32).tobytes())
    h.update(np.asarray(faces, np.int64).tobytes())
    h.update(np.round(np.asarray(uvs)[np.asarray(fuv)], 6).astype(np.float32).tobytes())
    for b in sorted(weights):
        h.update(b.encode())
        h.update(np.asarray(sorted(map(tuple, weights[b])), np.float64).round(6).tobytes())
    h.update(np.asarray(part, np.int64).tobytes())
    h.update(np.asarray(face_region, np.int64).tobytes())
    for bone in sorted(rig.data.bones, key=lambda x: x.name):
        h.update(bone.name.encode())
        h.update(np.round(np.asarray([*bone.head_local, *bone.tail_local]), 6).astype(np.float32).tobytes())
    return h.hexdigest()


def coverage(garment_obs, body_V, body_N, region_of_vertex, S):
    """{region id: share of its body vertices whose outward ray meets one of the objects within
    COVER_RAY_M} (human-scale reach, scene units)."""
    dg = bpy.context.evaluated_depsgraph_get()
    trees = [BVHTree.FromObject(ob, dg) for ob in garment_obs]
    hit = np.zeros(len(body_V), bool)
    for i, (p, n) in enumerate(zip(body_V, body_N)):
        o = p * S + n * 0.001
        for t in trees:
            loc, _nrm, _idx, dist = t.ray_cast(o.tolist(), n.tolist(), COVER_RAY_M * S)
            if loc is not None:
                hit[i] = True
                break
    out = {}
    for r in np.unique(region_of_vertex):
        if r < 0:
            continue
        sel = region_of_vertex == r
        out[int(r)] = r6(hit[sel].mean())
    return out


# --------------------------------------------------------------------------------------
# main
# --------------------------------------------------------------------------------------
def run(out_dir):
    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    objs = gb.build_giant({"height_m": H, "name": "Giant"})
    rig, body, bd, weights = objs["rig"], objs["body"], objs["bd"], objs["weights"]
    coll = objs["collection"]
    S = objs["info"]["scale"]
    n = mh.N_BODY_VERTS
    _, faces, fuv = bd.group("body")
    V = bd.verts[:n]
    sp = split.body_split(V, faces, weights, bd.masks, bd.joints)
    fp = sp["face_part"]
    heads = {b.name: np.asarray(b.head_local) for b in rig.data.bones}

    def root_bone(part, centre, other):
        if part == 0 or (part == 1 and other == 0):
            return "neck_01"
        if part == 2:
            return split.nearest_bone(centre, heads, LIMB_ROOTS)
        return split.nearest_bone(centre, heads, TORSO_ROOTS)

    info = {"meshes": {}, "garments": {}, "scale": r6(S), "height_m": H}
    # ---- hair: grown on the whole, unsubdivided body (its masks are point attributes) -----------
    hair = gh.build_styles(body, rig, coll, bd, S)
    # ---- the body: three parts, every cut capped ------------------------------------------------
    A = mesh_arrays(body)
    region_any = np.full(n, -1, np.int64)
    for pi, part in enumerate(split.PARTS):
        arrays, reg, st = split_part(A, fp, pi, sp["vregion"][part], root_bone)
        name = split.PART_MESH[part]
        make_object(name, arrays, coll, rig, "giant_skin", reg)
        info["meshes"][name] = {"category": "body", "layer": split.PART_LAYER[part], "dye": "none",
                                "tris": triangles(arrays), "verts": len(arrays["V"]), "cut_loops": st["loops"],
                                "caps": st["capped"], "open_chains": st["open_chains"],
                                "boundary_edges": boundary_count(arrays),
                                "regions": sorted({int(r) for r in reg})}
        region_any = np.where(sp["vregion"][part] >= 0, np.where(region_any >= 0, region_any, sp["vregion"][part]),
                              region_any)
    body_N = A["vnormal"].copy()
    # ---- eyes -----------------------------------------------------------------------------------
    frames = gb.eye_frames(bd, S)
    eyes = eye_arrays(frames)
    make_object("Eyes", eyes, coll, rig, "giant_eye")
    info["meshes"]["Eyes"] = {"category": "eyes", "layer": 3, "dye": "none", "tris": triangles(eyes),
                              "verts": len(eyes["V"])}
    for mesh_id, (ob, cards) in hair.items():
        cat = "hair" if mesh_id.startswith("Hair_") else "beard"
        info["meshes"][mesh_id] = {"category": cat, "layer": 3, "dye": "none", "cards": cards,
                                   "tris": int(sum(len(p.vertices) - 2 for p in ob.data.polygons)),
                                   "verts": len(ob.data.vertices), "atlas": "hair_atlas"}
    # ---- garments ---------------------------------------------------------------------------------
    built = gg.build_braies(bd, rig, coll, weights, S)
    built.update(gg.build_shells(bd, rig, coll, weights, S))
    from scipy.spatial import cKDTree
    kd = cKDTree(V)
    body_face_of = {frozenset(f.tolist()): i for i, f in enumerate(faces)}
    vregion_flat = region_any
    for gid in gg.ORDER:
        ob, body_ids = built[gid]
        for m in list(ob.modifiers):
            if m.type == "SOLIDIFY":
                bpy.context.view_layer.objects.active = ob
                bpy.ops.object.modifier_apply(modifier=m.name)
        if gid == "boots":
            tris_now = sum(len(p.vertices) - 2 for p in ob.data.polygons)
            dec = ob.modifiers.new("Decimate", "DECIMATE")
            dec.decimate_type = "COLLAPSE"
            dec.ratio = gg.BOOTS_TRIANGLES / float(tris_now)
            bpy.ops.object.select_all(action="DESELECT")
            bpy.context.view_layer.objects.active = ob
            ob.modifiers.move(len(ob.modifiers) - 1, 0)
            bpy.ops.object.modifier_apply(modifier=dec.name)
        ob.name = "_source_" + gid
        ob.data.name = "_source_" + gid
        G = mesh_arrays(ob)
        if gid in ("tunic",) and len(body_ids) == len(G["V"]):
            gbody = np.asarray(body_ids)
            face_part = []
            for f in G["faces"]:
                bf = body_face_of.get(frozenset(int(gbody[v]) for v in f))
                face_part.append(int(fp[bf]) if bf is not None else 1)
            face_part = np.asarray(face_part)
        elif gid in SPLIT_GARMENTS:
            _, gbody = kd.query(G["V"] / S)
            quads = np.asarray([f for f in G["faces"]])
            face_part = split.assign_parts(quads, sp["part_w"][gbody], min_island=12)
        else:
            _, gbody = kd.query(G["V"] / S)
            face_part = np.full(len(G["faces"]), split.PARTS.index(WHOLE_PART[gid]))
        if gid not in ("tunic",) or len(body_ids) != len(G["V"]):
            _, gbody = kd.query(G["V"] / S)
        greg = vregion_flat[np.asarray(gbody)]
        parts = sorted(set(int(p) for p in face_part))
        made = []
        for pi in parts:
            suffix = "" if len(parts) == 1 else ("_core" if pi != 2 else "_limbs")
            name = f"Garment_{gid}{suffix}"
            arrays, reg, st = split_part(G, face_part, pi, greg, root_bone, lift=GARMENT_CAP_LIFT_M * S)
            mat = ob.data.materials[0].name if len(ob.data.materials) else "giant_cloth"
            gob = make_object(name, arrays, coll, rig, mat, reg)
            made.append(gob)
            info["meshes"][name] = {"category": "garment", "layer": 1 if pi == 2 else 2, "dye": gg.DYE[gid],
                                    "detail": gg.DETAIL[gid], "tris": triangles(arrays), "verts": len(arrays["V"]),
                                    "cut_loops": st["loops"], "caps": st["capped"], "open_chains": st["open_chains"],
                                    "boundary_edges": boundary_count(arrays), "part": split.PARTS[pi]}
        info["garments"][gid] = [o.name for o in made]
        bpy.data.objects.remove(ob, do_unlink=True)
        # the regions this garment covers (its parts together), assigned to the part they belong to
        cov = coverage(made, V, body_N, region_any, S)
        covered = [r for r, share in sorted(cov.items()) if share >= COVER_SHARE and r != split.CAP_REGION]
        for o in made:
            e = info["meshes"][o.name]
            e["coverage"] = {str(r): s for r, s in sorted(cov.items()) if s > 0}
            part_regions = set(split.PART_REGIONS["limbs"]) if e["part"] == "limbs" else \
                set(split.PART_REGIONS["torso"]) | set(split.PART_REGIONS["head"])
            e["covers"] = [r for r in covered if r in part_regions]
    # ---- landmarks, hash ----------------------------------------------------------------------------
    eye_c = {k: np.asarray(v[0]) for k, v in frames.items()}
    info["landmarks"] = landmarks(rig, eye_c)
    info["body_hash"] = body_hash(V, faces, fuv, bd.bm.uvs, weights, fp, sp["face_region"], rig)
    info["bones"] = sorted(b.name for b in rig.data.bones)
    info["body_vertices"] = n
    info["cut_loop_lengths"] = {"%s|%s" % k: sorted(len(l) for l in v) for k, v in sp["loops"].items()}
    info["region_names"] = list(split.REGIONS)
    bpy.data.objects.remove(body, do_unlink=True)
    # ---- export --------------------------------------------------------------------------------------
    for o in bpy.data.objects:
        o.select_set(False)
    sel = [rig] + sorted((o for o in coll.objects if o.type == "MESH"), key=lambda o: o.name)
    for o in sel:
        o.select_set(True)
        if o.type == "MESH":
            o.data.name = o.name
    bpy.context.view_layer.objects.active = rig
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, GLB_NAME)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_apply=True,
                              export_skins=True, export_influence_nb=4, export_all_influences=False,
                              export_animations=False, export_morph=False,
                              export_materials="PLACEHOLDER", export_vertex_color="NAME",
                              export_vertex_color_name="Color", export_all_vertex_colors=False,
                              export_yup=True, export_tangents=False, export_extras=False,
                              export_def_bones=False, export_leaf_bone=False,
                              export_rest_position_armature=True)
    info["glb_bytes"] = os.path.getsize(path)
    info["seconds"] = round(time.time() - t0, 1)
    with open(os.path.join(out_dir, INFO_NAME), "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=1, sort_keys=True)
    log(f"wrote {path} ({info['glb_bytes']} bytes) in {info['seconds']} s")
    return info


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.getcwd(), "giant_out"))
