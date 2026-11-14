"""The Cycles bakes of the giant's skin (the step --bake): selected-to-active from the kit's
procedural skin on the subdivided body (level 2) onto the unsubdivided body's hm08 UVs, 1024 px,
2 threads, seed 0.

The cheap passes (about 2.5 minutes at 2 threads):
  albedo.png     base colour at the neutral tone (sRGB); no stubble shadow, no scalp tint: the shader
                 tints them from masks.png
  rough.png      roughness
  normal.png     tangent-space normal (subdivision smoothing + wrinkles, veins, knuckles, pores)
  masks_rgb.png  R stubble/beard area, G scalp, B brows   } packed as masks.png RGBA
  masks2_rgb.png R lips (G moustache, B chest hair)       }
  regions.png    the body region of every texel, (id + 0.5) / 16 (designs.py restricts every design
                 to its regions' texels)
  restpos.npy    rest position per texel (human-scale metres, float32, row 0 = the image's top)
  restnrm.npy    rest normal per texel (object space, stored as (n + 1) / 2)
The expensive passes (about 11 minutes at 2 threads):
  ao.png         ambient occlusion (24 samples)
  thick.png      local thickness: inside AO (1 = thin: ears, nose, fingers)

Ported from the M10 research run's bake script; its scars pass is gone (the scars are designs,
drawn by designs.py) and the regions pass is new.

Usage: python bake.py <out dir> <passes, comma-separated, or "cheap", "expensive", "all">
"""
from __future__ import annotations

import json
import os
import sys
import time

KIT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, KIT)
import bpy  # noqa: E402
import numpy as np  # noqa: E402

import giant_body as gb  # noqa: E402
import mh_data as mh  # noqa: E402
import skin_textures  # noqa: E402
import split  # noqa: E402

SETTINGS = {
    "size": 1024,
    "samples": 4,             # the EMIT and NORMAL passes
    "ao_samples": 24,
    "seed": 0,
    "cage_extrusion": 0.006,
    "max_ray_distance": 0.015,
    "margin": 8,
    "ao_distance_human_m": 0.25,
    "thick_distance_human_m": 0.06,
    "thick_node_samples": 16,
    "subdiv": 2,
}
CHEAP = ("albedo", "rough", "normal", "masks", "regions", "rest")
EXPENSIVE = ("ao", "thick")
# the files each pass writes
FILES = {
    "albedo": ("albedo.png",), "rough": ("rough.png",), "normal": ("normal.png",),
    "masks": ("masks_rgb.png", "masks2_rgb.png"), "regions": ("regions.png",),
    "rest": ("restpos.npy", "restnrm.npy"), "ao": ("ao.png",), "thick": ("thick.png",),
}
# the kit modules whose code reaches the baked pixels (the cache key and the expensive-input hash)
SOURCES = ("mh_data.py", "giant_body.py", "giant_skin.py", "node_util.py", "skin_textures.py",
           "split.py", "bake.py")


def log(*a):
    print("[bake]", *a, flush=True)


def threads():
    return int(os.environ.get("BAKE_THREADS", "2"))


def setup_cycles():
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.render.threads_mode = "FIXED"
    sc.render.threads = threads()
    sc.cycles.use_denoising = False
    sc.cycles.seed = SETTINGS["seed"]
    b = sc.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = SETTINGS["cage_extrusion"]
    b.max_ray_distance = SETTINGS["max_ray_distance"]
    b.margin = SETTINGS["margin"]
    b.margin_type = "EXTEND"
    b.use_clear = True
    return sc


def new_image(name, float_buffer=False, non_color=True):
    s = SETTINGS["size"]
    im = bpy.data.images.new(name, s, s, alpha=False, float_buffer=float_buffer)
    im.colorspace_settings.name = "Non-Color" if non_color else "sRGB"
    return im


def target_node(low, image):
    mat = low.data.materials[0]
    nt = mat.node_tree
    n = nt.nodes.get("BAKE_TARGET") or nt.nodes.new("ShaderNodeTexImage")
    n.name = "BAKE_TARGET"
    n.image = image
    for x in nt.nodes:
        x.select = False
    n.select = True
    nt.nodes.active = n


def emit_from(mat, socket_or_value):
    """Rewire the high material: Emission(<source>) -> output. Returns a restore function."""
    nt = mat.node_tree
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    old = out.inputs["Surface"].links[0].from_socket if out.inputs["Surface"].links else None
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 1.0
    if hasattr(socket_or_value, "is_output"):
        nt.links.new(socket_or_value, em.inputs["Color"])
    else:
        em.inputs["Color"].default_value = socket_or_value
    nt.links.new(em.outputs[0], out.inputs["Surface"])

    def restore():
        if old is not None:
            nt.links.new(old, out.inputs["Surface"])
        nt.nodes.remove(em)
    return restore


def source_of(mat, bsdf_input):
    nt = mat.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    inp = bsdf.inputs[bsdf_input]
    return inp.links[0].from_socket if inp.links else inp.default_value


def attr_node(mat, name, vector=False):
    nt = mat.node_tree
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = name
    return a.outputs["Vector" if vector else "Fac"]


def combine(mat, socks):
    nt = mat.node_tree
    c = nt.nodes.new("ShaderNodeCombineColor")
    for i, s in enumerate(socks):
        if s is None:
            continue
        if hasattr(s, "is_output"):
            nt.links.new(s, c.inputs[i])
        else:
            c.inputs[i].default_value = s
    return c.outputs[0]


def bake(kind, image, path, samples, **kw):
    t = time.time()
    sc = bpy.context.scene
    sc.cycles.samples = samples
    bpy.ops.object.bake(type=kind, **kw)
    if path.endswith(".npy"):
        s = SETTINGS["size"]
        px = np.empty(s * s * 4, np.float32)
        image.pixels.foreach_get(px)
        np.save(path, px.reshape(s, s, 4)[::-1, :, :3].copy())
    else:
        image.filepath_raw = path
        image.file_format = "PNG"
        sc.render.image_settings.color_depth = "8"
        image.save()
    log(f"{os.path.basename(path)} {kind} {samples} spp in {time.time() - t:.1f}s")
    return time.time() - t


def run(out_dir, passes, micro_dir=None):
    """Bake ``passes`` (names of CHEAP and EXPENSIVE) into ``out_dir``; returns {pass: seconds}."""
    t0 = time.time()
    os.makedirs(out_dir, exist_ok=True)
    micro = skin_textures.make_micro(os.path.join(micro_dir or out_dir, "skin_micro.png"))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = setup_cycles()
    objs = gb.build_giant({"height_m": gb.STAGE1_HEIGHT_M, "subdiv_render": SETTINGS["subdiv"],
                           "subdiv_viewport": SETTINGS["subdiv"], "skin": True,
                           "skin_params": {"beard_shadow": 0.0, "scalp_tint": 0.0, "micro_path": micro}})
    high, bd, weights = objs["body"], objs["bd"], objs["weights"]
    S = objs["info"]["scale"]
    # the region of every face, as a face attribute of the high body (subdivision keeps it per face)
    _, faces, _ = bd.group("body")
    sp = split.body_split(bd.verts[: mh.N_BODY_VERTS], faces, weights, bd.masks, bd.joints)
    ra = high.data.attributes.new("region", "FLOAT", "FACE")
    ra.data.foreach_set("value", split.encode_region(sp["face_region"]).astype(np.float32))
    # the low body: the same mesh without modifiers (rest pose)
    low = high.copy()
    low.data = high.data.copy()
    low.name = "Giant_low"
    for m in list(low.modifiers):
        low.modifiers.remove(m)
    low.parent = None
    low.matrix_world = high.matrix_world.copy()
    high.users_collection[0].objects.link(low)
    low.data.materials.clear()
    low.data.materials.append(bpy.data.materials.new("bake_target"))
    skin = high.data.materials[0]
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    high.select_set(True)
    low.select_set(True)
    bpy.context.view_layer.objects.active = low
    spp = SETTINGS["samples"]
    times = {}
    p = os.path.join
    if "albedo" in passes:
        im = new_image("albedo", non_color=False)
        target_node(low, im)
        r = emit_from(skin, source_of(skin, "Base Color"))
        times["albedo"] = bake("EMIT", im, p(out_dir, "albedo.png"), spp)
        r()
    if "rough" in passes:
        im = new_image("rough")
        target_node(low, im)
        r = emit_from(skin, source_of(skin, "Roughness"))
        times["rough"] = bake("EMIT", im, p(out_dir, "rough.png"), spp)
        r()
    if "normal" in passes:
        im = new_image("normal")
        target_node(low, im)
        times["normal"] = bake("NORMAL", im, p(out_dir, "normal.png"), spp, normal_space="TANGENT")
    if "masks" in passes:
        im = new_image("masks")
        target_node(low, im)
        c = combine(skin, [attr_node(skin, "m_beard"), attr_node(skin, "m_scalp"), attr_node(skin, "m_brow")])
        r = emit_from(skin, c)
        t1 = bake("EMIT", im, p(out_dir, "masks_rgb.png"), spp)
        r()
        im2 = new_image("masks_a")
        target_node(low, im2)
        c = combine(skin, [attr_node(skin, "m_lips"), attr_node(skin, "m_mustache"), attr_node(skin, "m_chesthair")])
        r = emit_from(skin, c)
        times["masks"] = t1 + bake("EMIT", im2, p(out_dir, "masks2_rgb.png"), spp)
        r()
    if "regions" in passes:
        im = new_image("regions")
        target_node(low, im)
        nt = skin.node_tree
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_type = "GEOMETRY"
        a.attribute_name = "region"
        r = emit_from(skin, a.outputs["Fac"])
        times["regions"] = bake("EMIT", im, p(out_dir, "regions.png"), 1)
        r()
    if "rest" in passes:
        im = new_image("restpos", float_buffer=True)
        target_node(low, im)
        r = emit_from(skin, attr_node(skin, "rest_co", vector=True))
        t1 = bake("EMIT", im, p(out_dir, "restpos.npy"), 1)
        r()
        im = new_image("restnrm", float_buffer=True)
        target_node(low, im)
        times["rest"] = t1 + bake("NORMAL", im, p(out_dir, "restnrm.npy"), 1, normal_space="OBJECT")
    if "ao" in passes:
        im = new_image("ao")
        target_node(low, im)
        sc.world = sc.world or bpy.data.worlds.new("w")
        sc.world.light_settings.distance = SETTINGS["ao_distance_human_m"] * S
        times["ao"] = bake("AO", im, p(out_dir, "ao.png"), SETTINGS["ao_samples"])
    if "thick" in passes:
        im = new_image("thick")
        target_node(low, im)
        nt = skin.node_tree
        ao = nt.nodes.new("ShaderNodeAmbientOcclusion")
        ao.inside = True
        ao.only_local = True
        ao.samples = SETTINGS["thick_node_samples"]
        ao.inputs["Distance"].default_value = SETTINGS["thick_distance_human_m"] * S
        r = emit_from(skin, ao.outputs["AO"])
        times["thick"] = bake("EMIT", im, p(out_dir, "thick.png"), SETTINGS["ao_samples"])
        r()
    log(f"done in {time.time() - t0:.1f}s; scale {S:.4f}")
    return times


def parse_passes(text):
    out = []
    for item in text.split(","):
        item = item.strip()
        if item == "cheap":
            out.extend(CHEAP)
        elif item == "expensive":
            out.extend(EXPENSIVE)
        elif item == "all":
            out.extend(CHEAP + EXPENSIVE)
        elif item:
            if item not in FILES:
                raise SystemExit("bake.py: unknown pass %r (%s)" % (item, ", ".join(FILES)))
            out.append(item)
    return out


if __name__ == "__main__":
    out = sys.argv[1]
    passes = parse_passes(sys.argv[2] if len(sys.argv) > 2 else "cheap")
    t = run(out, passes, sys.argv[3] if len(sys.argv) > 3 else None)
    with open(os.path.join(out, "bake_times.json"), "w") as fh:
        json.dump({k: round(v, 1) for k, v in t.items()}, fh, indent=1, sort_keys=True)
