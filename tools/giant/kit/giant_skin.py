"""The giant's procedural skin (the bake's source) and the scar segments of the designs.

* :func:`make_skin_material` - a procedural realistic skin (Principled BSDF, colour mix, coat,
  pore bump) with the body's region masks and procedural detail laid out on the rest pose at
  human scale: pores, fine lines, forehead/eye/neck wrinkles, knuckle creases, forearm and hand
  veins, sun-weathered tone variation, freckles/sun spots, redness and grime. The bake reads its
  base colour, roughness and relief; subsurface scattering is not baked (the game's skin shader
  uses wrap lighting and a thickness back-light instead).
* :func:`scar_segments` - the kit's four scars as segments on the rest surface, which
  ``designs.py`` draws into the design array.

Ported from the M10 research run's frozen kit snapshot, with its switches ``beard_shadow`` and
``scalp_tint`` (the bake sets both to 0: the shader tints the stubble and the scalp). Not ported:
the scar shading of the render (scars are designs now), MPFB's enhanced skin, the Cycles eyes and
the mouth materials; the SSS strength map (``sss.png``) is gone with the subsurface weight.
"""
from __future__ import annotations

import math
import os

import bpy
import numpy as np
from mathutils import Vector

import mh_data as mh
from node_util import NB

TEX = os.path.join(mh.MPFB_DIR, "textures")


def srgb_to_linear(c):
    c = np.asarray(c, np.float64)
    return tuple(np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4))


DEFAULT_SKIN = dict(
    tone=(0.69, 0.53, 0.44),       # sRGB base skin colour (light-medium, weathered): the bake tone
    tan=0.6,                       # sun-weathering of exposed skin (0..1)
    redness=0.5,                   # flush on cheeks, nose, ears, knuckles
    freckles=0.55,                 # sun spots on exposed skin
    roughness=0.44,
    coat=0.08,
    sheen=0.10,                    # peach-fuzz rim
    pores=1.0,
    wrinkles=1.0,
    veins=1.0,
    dirt=0.35,
    beard_shadow=1.0,              # the stubble shadow in the albedo (the bake: 0, the shader's mask)
    scalp_tint=1.0,                # the scalp tint in the albedo (the bake: 0, the shader's mask)
    bump_distance_m=0.00045,       # human-scale bump height (m); multiplied by the giant scale
    detail="high",                 # "high" (close-ups), "medium" (no pores), "low" (no relief)
    micro_path=None,               # the micro-relief tile (skin_textures.make_micro); required
)


# --------------------------------------------------------------------------------------
# scars, placed from landmarks (rest space, human scale)
# --------------------------------------------------------------------------------------
def _nearest_surface(V, target, pred=None):
    d = np.linalg.norm(V - target, axis=1)
    if pred is not None:
        d = np.where(pred, d, np.inf)
    return V[int(np.argmin(d))]


def scar_segments(bd):
    """{"brow", "cheek", "forearm_slash", "chest_claws", "knuckles"}: [(A, B, width)] in rest
    space (human-scale metres). The kit's five scars; the floor draws four (the cheek is P46's)."""
    V = bd.verts[: mh.N_BODY_VERTS]
    J = bd.joints
    L = bd.landmarks or {}
    hs = L.get("hs", 1.0)
    eyeL, eyeR = J["joint-l-eye"], J["joint-r-eye"]
    front_face = V[:, 1] < (J["joint-head"][1] - 0.06)
    out = {}
    # an old cut through the left eyebrow, down onto the upper lid's edge
    a = _nearest_surface(V, eyeL + np.array([0.004, -0.06, 0.042]) * hs, front_face)
    b = _nearest_surface(V, eyeL + np.array([0.013, -0.06, 0.016]) * hs, front_face)
    out["brow"] = [(a, b, 0.0022 * hs)]
    # a diagonal slash on the right cheek into the beard line
    a = _nearest_surface(V, eyeR + np.array([-0.022, -0.05, -0.030]) * hs, front_face)
    b = _nearest_surface(V, eyeR + np.array([-0.002, -0.07, -0.085]) * hs, front_face)
    out["cheek"] = [(a, b, 0.0026 * hs)]
    # a long slash on the right forearm (back of the arm)
    el, wr = J["joint-r-elbow"], J["joint-r-hand"]
    pred = np.linalg.norm(V - 0.5 * (el + wr), axis=1) < 0.25
    a = _nearest_surface(V, el + 0.25 * (wr - el) + np.array([0.0, 0.06, 0.0]), pred)
    b = _nearest_surface(V, el + 0.72 * (wr - el) + np.array([0.0, 0.06, 0.02]), pred)
    out["forearm_slash"] = [(a, b, 0.0035)]
    # three claw marks across the left pectoral / shoulder
    sh = J["joint-l-shoulder"]
    chest = (V[:, 1] < sh[1] - 0.02) & (V[:, 2] > sh[2] - 0.35) & (V[:, 0] > 0.0)
    claws = []
    for k in range(3):
        o = np.array([0.0, 0.0, -0.032 * k])
        a = _nearest_surface(V, sh + np.array([-0.02, -0.15, -0.03]) + o, chest)
        b = _nearest_surface(V, sh + np.array([-0.16, -0.18, -0.14]) + o, chest)
        claws.append((a, b, 0.0032))
    out["chest_claws"] = claws
    # a small nick on the left knuckles
    k2 = J["joint-l-finger-2-2"]
    pred = np.linalg.norm(V - k2, axis=1) < 0.06
    a = _nearest_surface(V, k2 + np.array([0.0, 0.03, 0.01]), pred)
    b = _nearest_surface(V, k2 + np.array([0.01, 0.03, -0.02]), pred)
    out["knuckles"] = [(a, b, 0.0015)]
    return {k: [(np.asarray(a, float), np.asarray(b, float), float(w)) for a, b, w in v] for k, v in out.items()}


# --------------------------------------------------------------------------------------
# skin
# --------------------------------------------------------------------------------------
def make_skin_material(name, scale, params=None, bd=None):
    """Procedural realistic skin. ``scale`` = giant height / MakeHuman body height."""
    p = dict(DEFAULT_SKIN)
    p.update(params or {})
    if not p["micro_path"]:
        raise ValueError("make_skin_material: skin_params['micro_path'] is required")
    detail = p["detail"]
    mat = bpy.data.materials.new(name)
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    nb = NB(nt)
    out = nb.new("ShaderNodeOutputMaterial")
    bsdf = nb.new("ShaderNodeBsdfPrincipled", label="Skin BSDF")
    nb.link(bsdf.outputs[0], out.inputs["Surface"])
    mat["giant_scale"] = scale
    mat["skin_detail"] = detail
    L = (bd.landmarks if bd is not None else None) or {}
    hs = L.get("hs", 1.0)

    R = nb.attr("rest_co", "Vector")
    uv = nb.texcoord("UV")
    m = {k: nb.attr(k) for k in ("m_exposure", "m_hand", "m_forearm", "m_head", "m_neck", "m_foot",
                                  "m_beard", "m_scalp", "m_forehead", "m_crow", "m_undereye", "m_nose",
                                  "m_cheek", "m_neckfront", "m_knuckles", "m_veins", "m_brow")}
    lips = nb.bw(nb.image(os.path.join(TEX, "mpfb_lips.jpg"), uv).outputs["Color"])
    ears = nb.bw(nb.image(os.path.join(TEX, "mpfb_ears.jpg"), uv).outputs["Color"])
    lids = nb.bw(nb.image(os.path.join(TEX, "mpfb_eyelids.jpg"), uv).outputs["Color"])
    nails = nb.math("MAXIMUM", nb.bw(nb.image(os.path.join(TEX, "mpfb_fingernails.jpg"), uv).outputs["Color"]),
                    nb.bw(nb.image(os.path.join(TEX, "mpfb_toenails.jpg"), uv).outputs["Color"]))
    mouth_in = nb.bw(nb.image(os.path.join(TEX, "mpfb_inside-mouth.jpg"), uv).outputs["Color"])
    # micro relief (pores + furrows): one box-projected tile on the rest pose
    import skin_textures
    micro_img = nb.image(p["micro_path"], nb.vmath("SCALE", R, scale=1.0 / skin_textures.MICRO_TILE_M))
    micro_img.projection = "BOX"
    micro_img.projection_blend = 0.3
    micro = nb.bw(micro_img.outputs["Color"])

    # ---------------- colour --------------------------------------------------------
    base = nb.rgb(*srgb_to_linear(p["tone"]))
    n_lo = nb.noise(R, 3.0, detail=2.0, rough=0.55)
    n_mid = nb.noise(R, 16.0, detail=3.0, rough=0.6, distortion=0.2)
    n_hi = nb.noise(R, 90.0, detail=2.0, rough=0.6)
    col = nb.mixc(nb.mul(nb.maprange(n_lo, 0.35, 0.65, 0.0, 1.0), 0.45), base,
                  nb.rgb(*srgb_to_linear((0.74, 0.52, 0.40))))
    col = nb.mixc(nb.mul(nb.maprange(n_mid, 0.4, 0.75, 0.0, 1.0), 0.35), col,
                  nb.rgb(*srgb_to_linear((0.62, 0.42, 0.33))))
    col = nb.mixc(nb.mul(nb.maprange(n_mid, 0.6, 0.3, 0.0, 1.0), 0.2), col,
                  nb.rgb(*srgb_to_linear((0.74, 0.58, 0.45))))
    # sun-weathering of exposed skin: darker, browner
    tanf = nb.mul(m["m_exposure"], p["tan"])
    col = nb.mixc(tanf, col, nb.mixc(0.55, col, nb.rgb(*srgb_to_linear((0.62, 0.44, 0.31))), "MULTIPLY"))
    # redness: cheeks, nose, ears, knuckles - broken up by noise
    red_mask = nb.add(nb.add(nb.mul(m["m_cheek"], 0.7), nb.mul(m["m_nose"], 0.85)),
                      nb.add(nb.mul(ears, 0.55), nb.mul(m["m_knuckles"], 0.8)))
    red_mask = nb.add(red_mask, nb.mul(m["m_hand"], 0.2))
    red_mask = nb.mul(nb.mul(red_mask, nb.maprange(n_mid, 0.3, 0.7, 0.35, 1.0)), p["redness"], clamp=True)
    col = nb.mixc(red_mask, col, nb.rgb(*srgb_to_linear((0.70, 0.40, 0.34))))
    # broken capillaries on nose/cheeks
    cap = nb.ridged(R, 70.0, 0.025, detail=1.0, distortion=0.4)
    cap = nb.mul(cap, nb.mul(nb.add(m["m_nose"], nb.mul(m["m_cheek"], 0.7)), 0.3 * p["redness"]), clamp=True)
    col = nb.mixc(cap, col, nb.rgb(0.40, 0.10, 0.08))
    # freckles / lentigines on exposed skin
    vf = nb.voronoi(R, 140.0)
    rnd = nb.bw(vf.outputs["Color"])
    spot = nb.mul(nb.maprange(vf.outputs["Distance"], 0.12, 0.38, 1.0, 0.0, "SMOOTHSTEP"),
                  nb.maprange(rnd, 0.80, 0.86, 0.0, 1.0))
    vf2 = nb.voronoi(R, 45.0)
    spot2 = nb.mul(nb.maprange(vf2.outputs["Distance"], 0.08, 0.3, 1.0, 0.0, "SMOOTHSTEP"),
                   nb.maprange(nb.bw(vf2.outputs["Color"]), 0.93, 0.96, 0.0, 1.0))
    spots = nb.mul(nb.add(nb.mul(spot, 0.55), nb.mul(spot2, 0.45)),
                   nb.mul(nb.math("POWER", m["m_exposure"], 1.5), p["freckles"]), clamp=True)
    col = nb.mixc(spots, col, nb.rgb(*srgb_to_linear((0.48, 0.31, 0.21))))
    # pores read slightly darker
    col = nb.mixc(nb.mul(nb.maprange(micro, 0.45, 0.15, 0.0, 1.0), 0.25), col,
                  nb.mixc(1.0, col, nb.rgb(0.7, 0.62, 0.6), "MULTIPLY"))
    # under-eye shadow, eyelids, caruncle
    col = nb.mixc(nb.mul(m["m_undereye"], 0.35), col, nb.rgb(*srgb_to_linear((0.52, 0.38, 0.38))))
    col = nb.mixc(nb.mul(lids, 0.45), col, nb.rgb(*srgb_to_linear((0.62, 0.40, 0.38))))
    # beard shadow (stubble under the hair), scalp
    col = nb.mixc(nb.mul(m["m_beard"], 0.5 * p["beard_shadow"]), col, nb.rgb(*srgb_to_linear((0.46, 0.39, 0.37))))
    col = nb.mixc(nb.mul(m["m_scalp"], 0.4 * p["scalp_tint"]), col, nb.rgb(*srgb_to_linear((0.66, 0.52, 0.45))))
    # lips
    lip_col = nb.mixc(nb.mul(n_hi, 0.3), nb.rgb(*srgb_to_linear((0.60, 0.37, 0.33))),
                      nb.rgb(*srgb_to_linear((0.52, 0.31, 0.28))))
    lipf = nb.smooth(lips, 0.15, 0.85)
    col = nb.mixc(lipf, col, lip_col)
    # veins (shared with the bump below)
    vmask = nb.mul(m["m_veins"], p["veins"])
    v1 = nb.ridged(R, 7.0, 0.022, detail=1.0, distortion=0.25)
    v2 = nb.ridged(nb.vmath("ADD", R, (3.1, 1.7, 0.4)), 13.0, 0.016, detail=0.0, distortion=0.3)
    vbreak = nb.maprange(nb.noise(R, 5.0, detail=0.0), 0.42, 0.6, 0.0, 1.0)
    veins = nb.mul(nb.math("MAXIMUM", v1, nb.mul(v2, 0.7)), nb.mul(vbreak, vmask), clamp=True)
    col = nb.mixc(nb.mul(veins, 0.22), col, nb.rgb(*srgb_to_linear((0.50, 0.50, 0.58))), "MULTIPLY")
    # nails
    nailf = nb.smooth(nails, 0.2, 0.7)
    nail_col = nb.mixc(nb.mul(n_hi, 0.4), nb.rgb(*srgb_to_linear((0.78, 0.66, 0.60))),
                       nb.rgb(*srgb_to_linear((0.70, 0.60, 0.52))))
    col = nb.mixc(nailf, col, nail_col)
    # grime: soles, hands
    dirt_mask = nb.add(nb.mul(m["m_foot"], nb.maprange(nb.separate(R)[2], 0.0, 0.05, 1.0, 0.25)),
                       nb.mul(m["m_hand"], 0.25))
    dirt_mask = nb.mul(nb.mul(dirt_mask, nb.maprange(n_mid, 0.35, 0.7, 0.0, 1.0)), p["dirt"], clamp=True)
    col = nb.mixc(dirt_mask, col, nb.rgb(0.10, 0.075, 0.05))
    # inside of the mouth
    col = nb.mixc(nb.smooth(mouth_in, 0.3, 0.7), col, nb.rgb(0.25, 0.06, 0.06))
    nb.link(col, bsdf.inputs["Base Color"])

    # ---------------- roughness / coat / sheen --------------------------------------------
    rough = nb.add(p["roughness"], nb.mul(nb.sub(n_hi, 0.5), 0.12))
    rough = nb.add(rough, nb.mul(nb.sub(n_mid, 0.5), 0.22))                    # dry and oily patches
    rough = nb.add(rough, nb.mul(nb.sub(1.0, m["m_head"]), 0.05))               # body drier than face
    rough = nb.add(rough, nb.mul(nb.sub(0.5, micro), 0.25))                      # pores are rougher
    rough = nb.sub(rough, nb.mul(nb.add(m["m_nose"], nb.mul(m["m_forehead"], 0.5)), 0.05))  # oily T-zone
    rough = nb.mixf(lipf, rough, 0.36)
    rough = nb.mixf(nailf, rough, 0.24)
    rough = nb.mixf(nb.smooth(mouth_in, 0.3, 0.7), rough, 0.18)
    rough = nb.mixf(dirt_mask, rough, 0.7)
    nb.link(rough, bsdf.inputs["Roughness"])
    bsdf.inputs["IOR"].default_value = 1.4
    bsdf.inputs["Specular IOR Level"].default_value = 0.5
    coat = nb.add(p["coat"], nb.mul(nb.add(m["m_nose"], m["m_forehead"]), 0.03))
    coat = nb.mixf(lipf, coat, 0.25)
    nb.link(coat, bsdf.inputs["Coat Weight"])
    bsdf.inputs["Coat Roughness"].default_value = 0.32
    bsdf.inputs["Coat IOR"].default_value = 1.45
    nb.link(nb.mul(p["sheen"], nb.sub(1.0, nailf)), bsdf.inputs["Sheen Weight"])
    bsdf.inputs["Sheen Roughness"].default_value = 0.45
    bsdf.inputs["Sheen Tint"].default_value = (1.0, 0.92, 0.86, 1.0)

    if detail == "low":
        return mat
    # ---------------- relief: one bump on the summed height field -------------------------
    sep = nb.separate(R)
    rx, ry, rz = sep[0], sep[1], sep[2]
    h = None

    def acc(term, w):
        nonlocal h
        t = nb.mul(term, w)
        h = t if h is None else nb.add(h, t)

    if detail == "high":
        face_pores = nb.add(0.55, nb.mul(nb.add(nb.add(m["m_nose"], m["m_cheek"]), nb.mul(m["m_forehead"], 0.6)), 0.9))
        acc(nb.mul(nb.sub(micro, 0.5), face_pores), 0.55 * p["pores"])
    # forehead: a few soft horizontal creases, broken up along their length
    warp = nb.mul(nb.noise(R, 18.0, detail=1.0), 2.4)
    fh = nb.math("SINE", nb.add(nb.mul(rz, math.pi / (0.0165 * hs)), warp))
    fh = nb.maprange(nb.math("ABSOLUTE", fh), 0.0, 0.42, 1.0, 0.0, "SMOOTHSTEP")
    fh_amp = nb.maprange(nb.noise(nb.vmath("MULTIPLY", R, (1.0, 1.0, 0.2)), 22.0, detail=1.0), 0.3, 0.7, 0.0, 1.0)
    acc(nb.mul(nb.mul(fh, fh_amp), m["m_forehead"]), -1.6 * p["wrinkles"])
    # crow's feet: lines fanning out from each outer eye corner
    for side, sgn in (("L", 1.0), ("R", -1.0)):
        if f"canthus_{side}" not in L:
            continue
        c = Vector(L[f"canthus_{side}"])
        dx = nb.mul(nb.sub(rx, c.x), sgn)
        dy = nb.sub(ry, c.y)
        dz = nb.sub(rz, c.z)
        hh = nb.add(nb.mul(dx, 0.75), nb.mul(dy, 0.66))          # outward along the temple
        rr = nb.math("SQRT", nb.add(nb.mul(hh, hh), nb.mul(dz, dz)))
        ang = nb.math("ARCTAN2", dz, hh)
        lines = nb.math("SINE", nb.add(nb.mul(ang, 7.0), nb.mul(nb.noise(R, 40.0, detail=0.0), 1.2)))
        lines = nb.maprange(nb.math("ABSOLUTE", lines), 0.0, 0.3, 1.0, 0.0, "SMOOTHSTEP")
        win = nb.mul(nb.maprange(rr, 0.003 * hs, 0.008 * hs, 0.0, 1.0, "SMOOTHSTEP"),
                     nb.maprange(rr, 0.018 * hs, 0.032 * hs, 1.0, 0.0, "SMOOTHSTEP"))
        win = nb.mul(win, nb.maprange(nb.math("ABSOLUTE", ang), 0.9, 1.3, 1.0, 0.0, "SMOOTHSTEP"))
        win = nb.mul(win, nb.maprange(hh, 0.0, 0.004 * hs, 0.0, 1.0))
        acc(nb.mul(lines, win), -1.3 * p["wrinkles"])
        # under-eye arcs
        e = Vector(L[f"eye_{side}"])
        ex = nb.sub(rx, e.x)
        ez = nb.sub(rz, e.z)
        rho = nb.math("SQRT", nb.add(nb.mul(ex, ex), nb.mul(ez, ez)))
        r0 = 0.0215 * hs
        arcs = nb.add(nb.maprange(nb.math("ABSOLUTE", nb.sub(rho, r0 + 0.004 * hs)), 0.0, 0.0012 * hs, 1.0, 0.0, "SMOOTHSTEP"),
                      nb.mul(nb.maprange(nb.math("ABSOLUTE", nb.sub(rho, r0 + 0.0095 * hs)), 0.0, 0.0016 * hs, 1.0, 0.0, "SMOOTHSTEP"), 0.7))
        low = nb.maprange(ez, -0.004 * hs, -0.012 * hs, 0.0, 1.0)
        acc(nb.mul(nb.mul(arcs, low), m["m_undereye"]), -1.2 * p["wrinkles"])
    # neck rings
    nk = nb.math("SINE", nb.add(nb.mul(rz, math.pi / (0.024 * hs)), nb.mul(nb.noise(R, 10.0, detail=0.0), 2.0)))
    nk = nb.mul(nb.maprange(nb.math("ABSOLUTE", nk), 0.0, 0.3, 1.0, 0.0, "SMOOTHSTEP"), m["m_neckfront"])
    acc(nk, -1.0 * p["wrinkles"])
    # knuckles
    kn = nb.ridged(nb.vmath("MULTIPLY", R, (1.0, 1.0, 6.0)), 140.0, 0.08, detail=0.0, distortion=0.4)
    acc(nb.mul(kn, m["m_knuckles"]), -1.0 * p["wrinkles"])
    # veins (raised)
    acc(veins, 1.6)
    bump = nb.new("ShaderNodeBump", label="skin relief")
    nb.put(bump.inputs["Strength"], 1.0)
    nb.put(bump.inputs["Distance"], p["bump_distance_m"] * scale)
    nb.put(bump.inputs["Height"], h)
    nb.link(bump.outputs["Normal"], bsdf.inputs["Normal"])
    nb.link(bump.outputs["Normal"], bsdf.inputs["Coat Normal"])
    return mat
