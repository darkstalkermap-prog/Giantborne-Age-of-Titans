"""MakeHuman / MPFB2 data layer of the giant kit (numpy only, no bpy).

Reads the vendored CC0 MPFB2 subset in ``tools/giant/mpfb2`` (see ``mpfb2/SOURCE.md``):
  * the hm08 base mesh (``3dobjs/base.obj``) with its helper geometry and joint cubes,
  * morph targets (``targets/**/*.target.gz``: "index dx dy dz" lines, decimetres, Y up),
  * the macro-target rules (MakeHuman's weighting of gender/age/muscle/weight/height/
    proportions/race, written here from MakeHuman's documented rules),
  * regional modifiers (``targets/target.json``: opposite pairs, left/right),
  * the "game_engine" skeleton (``rigs/standard/rig.game_engine.json``) and its skinning weights.

Everything is returned in MakeHuman units first (decimetres, Y up, face towards +Z) and
converted to Blender metres (Z up, face towards -Y) with :func:`mh_to_blender`.

Ported from the M10 research run's frozen kit snapshot. Changes: the data folder is the vendored
subset (``GIANT_MPFB2_DIR`` overrides it, for the audit), the base mesh is parsed on every run
(no file-time cache), and :func:`region_masks` reads the game_engine bone names, so the default
rig and its weights are no longer needed.
"""
from __future__ import annotations

import gzip
import json
import os
from dataclasses import dataclass, field

import numpy as np

KIT_DIR = os.path.dirname(os.path.abspath(__file__))
GIANT_TOOLS_DIR = os.path.dirname(KIT_DIR)
MPFB_DIR = os.environ.get("GIANT_MPFB2_DIR") or os.path.join(GIANT_TOOLS_DIR, "mpfb2")
RIG = "game_engine"

N_BODY_VERTS = 13380          # hm08: vertices 0..13379 are the skin
GROUP_RANGES = {              # from mesh_metadata/hm08_config.json (inclusive)
    "body": (0, 13379),
    "helper-tongue": (13380, 13605),
    "helper-l-eye": (14598, 14669),
    "helper-r-eye": (14670, 14741),
    "helper-l-eyelashes": (14742, 14866),
    "helper-r-eyelashes": (14867, 14991),
    "helper-lower-teeth": (14992, 15059),
    "helper-upper-teeth": (15060, 15127),
    "helper-genital": (15128, 15327),
    "helper-tights": (15328, 18001),
    "helper-skirt": (18002, 18721),
    "helper-hair": (18722, 19149),
}

# The files of the subset the kit reads besides the targets (see fetch_mpfb2.py).
DATA_FILES = (
    "3dobjs/base.obj",
    "targets/target.json",
    "rigs/standard/rig.game_engine.json",
    "rigs/standard/weights.game_engine.json",
    "textures/mpfb_ears.jpg",
    "textures/mpfb_eyelids.jpg",
    "textures/mpfb_fingernails.jpg",
    "textures/mpfb_inside-mouth.jpg",
    "textures/mpfb_lips.jpg",
    "textures/mpfb_toenails.jpg",
    "LICENSE.md",
)


def set_data_dir(path):
    """Read the MPFB2 data from ``path`` (the audit points it at a copy extracted from the wheel)."""
    global MPFB_DIR, _TARGET_META
    MPFB_DIR = path
    _TARGET_META = None
    _TARGET_CACHE.clear()


# --------------------------------------------------------------------------------------
# Base mesh
# --------------------------------------------------------------------------------------
@dataclass
class BaseMesh:
    verts: np.ndarray            # (19158, 3) MH units
    uvs: np.ndarray              # (21334, 2)
    faces: np.ndarray            # (18486, 4) vertex indices (all quads)
    face_uvs: np.ndarray         # (18486, 4) uv indices
    face_group: np.ndarray       # (18486,) index into group_names
    group_names: list = field(default_factory=list)

    def group_faces(self, name):
        # a group can be split over several "g" chunks in the OBJ (eyelashes, tights)
        gis = [i for i, n in enumerate(self.group_names) if n == name]
        return np.nonzero(np.isin(self.face_group, gis))[0]

    def group_vertex_indices(self, name):
        return np.unique(self.faces[self.group_faces(name)].ravel())


_BASE_CACHE: dict = {}


def load_base_mesh(path=None) -> BaseMesh:
    path = path or os.path.join(MPFB_DIR, "3dobjs", "base.obj")
    if path in _BASE_CACHE:
        return _BASE_CACHE[path]
    verts, uvs, faces, fuvs, fgroup, groups = [], [], [], [], [], []
    cur = -1
    with open(path, "r") as fh:
        for line in fh:
            if line.startswith("v "):
                verts.append([float(x) for x in line.split()[1:4]])
            elif line.startswith("vt "):
                uvs.append([float(x) for x in line.split()[1:3]])
            elif line.startswith("f "):
                parts = line.split()[1:]
                faces.append([int(p.split("/")[0]) - 1 for p in parts])
                fuvs.append([int(p.split("/")[1]) - 1 for p in parts])
                fgroup.append(cur)
            elif line.startswith("g "):
                groups.append(line.split(None, 1)[1].strip())
                cur = len(groups) - 1
    bm = BaseMesh(np.asarray(verts, np.float64), np.asarray(uvs, np.float64),
                  np.asarray(faces, np.int64), np.asarray(fuvs, np.int64),
                  np.asarray(fgroup, np.int64), groups)
    _BASE_CACHE[path] = bm
    return bm


def mh_to_blender(co):
    """MakeHuman (dm, Y up, face +Z) -> Blender (m, Z up, face -Y)."""
    co = np.asarray(co, np.float64)
    out = np.empty_like(co)
    out[..., 0] = co[..., 0] * 0.1
    out[..., 1] = -co[..., 2] * 0.1
    out[..., 2] = co[..., 1] * 0.1
    return out


# --------------------------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------------------------
_TARGET_CACHE: dict = {}


def target_rel(rel):
    """The data-relative path of a target ("targets/<rel>.target.gz")."""
    rel = rel if rel.endswith(".target.gz") else rel + ".target.gz"
    return "targets/" + rel


def target_path(rel):
    return os.path.join(MPFB_DIR, target_rel(rel))


def load_target(rel):
    """Return (indices, deltas) of a target, deltas in MH units."""
    p = target_path(rel)
    if p in _TARGET_CACHE:
        return _TARGET_CACHE[p]
    with gzip.open(p, "rt") as fh:
        txt = "\n".join(l for l in fh.read().splitlines() if l.strip() and not l.startswith("#"))
    arr = np.array(txt.split(), dtype=np.float64).reshape(-1, 4)
    res = (arr[:, 0].astype(np.int64), arr[:, 1:4])
    _TARGET_CACHE[p] = res
    return res


def target_exists(rel):
    return os.path.exists(target_path(rel))


# --------------------------------------------------------------------------------------
# Macro rules (MakeHuman / MPFB macro.json)
# --------------------------------------------------------------------------------------
def age_years_to_value(years):
    """MakeHuman age slider: 0 -> 1 y, 0.1875 -> 11 y, 0.5 -> 25 y, 1 -> 90 y."""
    if years < 25.0:
        return max(0.0, (years - 1.0) / (2.0 * 24.0))
    return min(1.0, 0.5 + (years - 25.0) / (2.0 * 65.0))


def _age_weights(a):
    if a < 0.5:
        young = max(0.0, (a - 0.1875) * 3.2)
        return {"baby": max(0.0, 1.0 - a * 5.333), "child": max(0.0, min(1.0, 5.333 * a) - young),
                "young": young, "old": 0.0}
    old = max(0.0, a * 2.0 - 1.0)
    return {"baby": 0.0, "child": 0.0, "young": 1.0 - old, "old": old}


def _three(v, lo, mid, hi):
    if v < 0.5:
        w = max(0.0, 1.0 - 2.0 * v)
        return {lo: w, mid: 1.0 - w, hi: 0.0}
    w = max(0.0, 2.0 * (v - 0.5))
    return {lo: 0.0, mid: 1.0 - w, hi: w}


def macro_variable_weights(gender=1.0, age=0.5, muscle=0.5, weight=0.5, height=0.5,
                           proportions=0.5, african=1 / 3, asian=1 / 3, caucasian=1 / 3,
                           cupsize=0.5, firmness=0.5):
    g = {"male": float(np.clip(gender, 0, 1)), "female": 1.0 - float(np.clip(gender, 0, 1))}
    a = _age_weights(float(np.clip(age, 0, 1)))
    m = _three(float(np.clip(muscle, 0, 1)), "minmuscle", "averagemuscle", "maxmuscle")
    w = _three(float(np.clip(weight, 0, 1)), "minweight", "averageweight", "maxweight")
    h = float(np.clip(height, 0, 1))
    hgt = {"minheight": max(0.0, 1.0 - 2.0 * h) if h < 0.5 else 0.0,
           "maxheight": max(0.0, 2.0 * (h - 0.5)) if h > 0.5 else 0.0}
    p = float(np.clip(proportions, 0, 1))
    prop = {"uncommonproportions": max(0.0, 1.0 - 2.0 * p) if p < 0.5 else 0.0,
            "idealproportions": max(0.0, 2.0 * (p - 0.5)) if p > 0.5 else 0.0}
    tot = african + asian + caucasian
    race = ({"african": african / tot, "asian": asian / tot, "caucasian": caucasian / tot}
            if tot > 0 else {"african": 1 / 3, "asian": 1 / 3, "caucasian": 1 / 3})
    cup = _three(float(cupsize), "mincup", "averagecup", "maxcup")
    firm = _three(float(firmness), "minfirmness", "averagefirmness", "maxfirmness")
    return dict(gender=g, age=a, muscle=m, weight=w, height=hgt, proportions=prop, race=race,
                cupsize=cup, firmness=firm)


def macro_target_weights(eps=1e-5, **macro):
    """Weights of every macro target file (relative paths) for the given macro sliders.

    Combinations as in MPFB's macro rules: racegenderage, genderagemuscleweight (universal),
    +height, +proportions, +cupsize/firmness (breast, female only).
    """
    v = macro_variable_weights(**macro)
    out = {}

    def put(rel, wt):
        if wt > eps:
            out[rel] = out.get(rel, 0.0) + wt

    for race, wr in v["race"].items():
        for gen, wg in v["gender"].items():
            for age, wa in v["age"].items():
                put(f"macrodetails/{race}-{gen}-{age}", wr * wg * wa)
    for gen, wg in v["gender"].items():
        for age, wa in v["age"].items():
            for mus, wm in v["muscle"].items():
                for wei, ww in v["weight"].items():
                    base = wg * wa * wm * ww
                    put(f"macrodetails/universal-{gen}-{age}-{mus}-{wei}", base)
                    for hk, wh in v["height"].items():
                        put(f"macrodetails/height/{gen}-{age}-{mus}-{wei}-{hk}", base * wh)
                    if age not in ("baby",):
                        for pk, wp in v["proportions"].items():
                            put(f"macrodetails/proportions/{gen}-{age}-{mus}-{wei}-{pk}", base * wp)
                    if gen == "female":
                        for ck, wc in v["cupsize"].items():
                            for fk, wf in v["firmness"].items():
                                put(f"breast/female-{age}-{mus}-{wei}-{ck}-{fk}", base * wc * wf)
    return {k: w for k, w in out.items() if target_exists(k)}


# --------------------------------------------------------------------------------------
# Regional modifiers (target.json)
# --------------------------------------------------------------------------------------
_TARGET_META = None


def target_meta():
    global _TARGET_META
    if _TARGET_META is None:
        with open(os.path.join(MPFB_DIR, "targets", "target.json")) as fh:
            _TARGET_META = json.load(fh)
    return _TARGET_META


def modifier_targets(name, value, side="both"):
    """Map a regional modifier "group/category" with a slider value to {target: weight}.

    ``value`` in [-1, 1] for opposite pairs (negative -> decr/down/in target, positive ->
    incr/up/out target), in [0, 1] for single targets. ``side`` is 'both', 'l' or 'r' for
    left/right categories. Raw target paths ("asym/asym-nose-1-l",
    "expression/units/caucasian/mouth-compression") are passed through with weight=value.
    """
    if "/" in name:
        grp, cat = name.split("/", 1)
    else:
        grp, cat = None, name
    meta = target_meta()
    if grp in meta:
        for c in meta[grp]["categories"]:
            if c["name"] != cat:
                continue
            out = {}
            if "opposites" in c:
                op = c["opposites"]
                sign = "positive" if value > 0 else "negative"
                if c.get("has_left_and_right"):
                    sides = {"both": ("left", "right"), "l": ("left",), "r": ("right",)}[side]
                else:
                    sides = ("unsided",)
                for s in sides:
                    t = op.get(f"{sign}-{s}", "")
                    if t:
                        out[f"{grp}/{t}"] = abs(value)
            else:
                for t in c["targets"]:
                    out[f"{grp}/{t}"] = value
            return out
    if target_exists(name):
        return {name: value}
    raise KeyError(f"unknown modifier or target: {name}")


# --------------------------------------------------------------------------------------
# Morph composition
# --------------------------------------------------------------------------------------
def compose(base_verts, weighted_targets):
    v = np.array(base_verts, np.float64, copy=True)
    for rel, w in weighted_targets.items():
        if abs(w) < 1e-6:
            continue
        idx, d = load_target(rel)
        np.add.at(v, idx, w * d)
    return v


def merge_weights(*dicts):
    out = {}
    for d in dicts:
        for k, w in d.items():
            out[k] = out.get(k, 0.0) + w
    return out


# --------------------------------------------------------------------------------------
# Joints, skeleton, weights
# --------------------------------------------------------------------------------------
def joint_positions(bm: BaseMesh, verts):
    """Centre of every joint cube ('joint-*' group) for the morphed vertices."""
    out = {}
    for name in sorted(set(bm.group_names)):
        if name.startswith("joint-"):
            vi = np.unique(bm.faces[bm.group_faces(name)].ravel())
            out[name] = verts[vi].mean(axis=0)
    return out


def load_rig(name=RIG):
    with open(os.path.join(MPFB_DIR, "rigs", "standard", f"rig.{name}.json")) as fh:
        d = json.load(fh)
    return d.get("bones", d)


def bone_point(spec, verts, joints):
    s = spec["strategy"]
    if s == "CUBE":
        return joints[spec["cube_name"]]
    if s == "VERTEX":
        return verts[spec["vertex_index"]]
    if s == "MEAN":
        return verts[np.asarray(spec["vertex_indices"])].mean(axis=0)
    raise ValueError(s)


def load_weights(name=RIG):
    with open(os.path.join(MPFB_DIR, "rigs", "standard", f"weights.{name}.json")) as fh:
        return json.load(fh)["weights"]


def bone_order(rig):
    """Bones parents-first."""
    order, seen = [], set()

    def visit(b):
        if b in seen:
            return
        p = rig[b].get("parent", "")
        if p:
            visit(p)
        seen.add(b)
        order.append(b)

    for b in sorted(rig):
        visit(b)
    return order


# The game_engine bone families (prefixes) of the region masks below.
BONE_FAMILIES = {
    "hand": ("hand_", "thumb_", "index_", "middle_", "ring_", "pinky_"),
    "forearm": ("lowerarm_",),
    "upperarm": ("upperarm_",),
    "head": ("head",),
    "neck": ("neck_",),
    "torso": ("spine_", "clavicle_"),
    "pelvis": ("pelvis", "Root"),
    "upperleg": ("thigh_",),
    "lowerleg": ("calf_",),
    "foot": ("foot_", "ball_"),
}


def family_sums(weights, n_verts=N_BODY_VERTS, families=None):
    """Per-vertex sums of the skinning weights of bone families {name: (prefixes, ...)}."""
    families = families or BONE_FAMILIES
    out = {k: np.zeros(n_verts) for k in families}
    for b, lst in weights.items():
        for k, pre in families.items():
            if b.startswith(pre):
                for vi, w in lst:
                    if vi < n_verts:
                        out[k][vi] += w
    return out


def region_masks(weights, n_verts=N_BODY_VERTS):
    """Soft region masks (0..1 per vertex) summed from the game_engine skinning weights."""
    s = family_sums(weights, n_verts)
    return {f"m_{k}": np.clip(v, 0, 1) for k, v in s.items()}


# --------------------------------------------------------------------------------------
# The giant's default phenotype
# --------------------------------------------------------------------------------------
GIANT_MACRO = dict(
    gender=1.0,                       # male
    age=age_years_to_value(42.0),     # a man of about 40-45
    muscle=1.0,                       # very muscular
    weight=1.0,                       # heavy-set: the strongman build (with muscle 1.0)
    height=1.0,                       # tallest proportions
    proportions=1.0,                  # ideal proportions
    african=0.12, asian=0.08, caucasian=0.80,
)

# Regional modifiers: a weathered giant's face and frame, kept within human range.
GIANT_MODIFIERS = {
    # brow, forehead, eyes
    "eyebrows/eyebrows-trans-backward-forward": 0.55,
    "eyebrows/eyebrows-trans-down-up": -0.35,
    "eyebrows/eyebrows-angle-down-up": -0.25,
    "forehead/forehead-trans-backward-forward": 0.15,
    "forehead/forehead-temple-decr-incr": 0.25,
    "forehead/forehead-scale-vert-decr-incr": 0.10,
    "eyes/eye-bag-decr-incr": 0.35,
    "eyes/eye-bag-height-decr-incr": 0.20,
    "eyes/eye-eyefold-down-up": -0.35,
    "eyes/eye-scale-decr-incr": -0.12,
    "eyes/eye-height2-decr-incr": -0.15,
    # nose: broad, a healed break
    "nose/nose-scale-horiz-decr-incr": 0.35,
    "nose/nose-scale-vert-decr-incr": 0.15,
    "nose/nose-flaring-decr-incr": 0.35,
    "nose/nose-nostrils-width-decr-incr": 0.30,
    "nose/nose-point-width-decr-incr": 0.35,
    "nose/nose-hump-decr-incr": 0.45,
    "nose/nose-volume-decr-incr": 0.25,
    "nose/nose-width1-decr-incr": 0.25,
    "nose/nose-width2-decr-incr": 0.20,
    # cheeks, jaw, chin
    "cheek/cheek-bones-decr-incr": 0.50,
    "cheek/cheek-volume-decr-incr": -0.25,
    "cheek/cheek-inner-decr-incr": -0.15,
    "chin/chin-bones-decr-incr": 0.55,
    "chin/chin-width-decr-incr": 0.45,
    "chin/chin-prominent-decr-incr": 0.35,
    "chin/chin-height-decr-incr": 0.20,
    "chin/chin-jaw-drop-decr-incr": 0.25,
    "chin/chin-cleft-decr-incr": 0.15,
    "head/head-square": 0.45,
    "head/head-age-decr-incr": 0.35,
    "head/head-fat-decr-incr": -0.10,
    "head/head-scale-horiz-decr-incr": 0.06,
    # mouth: stern, thin upper lip, laugh lines
    "mouth/mouth-upperlip-volume-decr-incr": -0.25,
    "mouth/mouth-lowerlip-volume-decr-incr": 0.05,
    "mouth/mouth-scale-horiz-decr-incr": 0.10,
    "mouth/mouth-laugh-lines-in-out": 0.55,
    "mouth/mouth-angles-down-up": -0.30,
    "mouth/mouth-philtrum-volume-decr-incr": 0.15,
    # ears
    "ears/ear-scale-decr-incr": 0.15,
    "ears/ear-lobe-decr-incr": 0.25,
    "ears/ear-flap-decr-incr": 0.10,
    # thick neck
    "neck/measure-neck-circ-decr-incr": 0.85,
    "neck/neck-scale-horiz-decr-incr": 0.40,
    "neck/neck-scale-depth-decr-incr": 0.25,
    "neck/measure-neck-height-decr-incr": -0.35,
    # torso, arms, legs: a labourer-warrior, heavy-set
    "torso/torso-muscle-pectoral-decr-incr": 0.35,
    "torso/torso-muscle-dorsi-decr-incr": 0.50,
    "torso/torso-vshape-decr-incr": 0.20,
    "torso/measure-shoulder-dist-decr-incr": 0.35,
    "torso/torso-scale-depth-decr-incr": 0.20,
    "torso/measure-waist-circ-decr-incr": 0.30,
    "torso/torso-scale-horiz-decr-incr": 0.15,
    "torso/measure-bust-circ-decr-incr": 0.25,
    "hip/hip-scale-horiz-decr-incr": 0.08,
    "stomach/stomach-pregnant-decr-incr": 0.12,
    "arms/upperarm-muscle-decr-incr": 0.45,
    "arms/upperarm-shoulder-muscle-decr-incr": 0.50,
    "arms/lowerarm-muscle-decr-incr": 0.55,
    "arms/measure-upperarm-circ-decr-incr": 0.25,
    "arms/upperarm-scale-horiz-decr-incr": 0.15,
    "arms/upperarm-scale-depth-decr-incr": 0.15,
    "arms/lowerarm-scale-horiz-decr-incr": 0.15,
    "legs/upperleg-muscle-decr-incr": 0.40,
    "legs/lowerleg-muscle-decr-incr": 0.45,
    "legs/measure-calf-circ-decr-incr": 0.45,
    "legs/measure-thigh-circ-decr-incr": 0.45,
    "legs/upperleg-scale-horiz-decr-incr": 0.25,
    "legs/upperleg-scale-depth-decr-incr": 0.20,
    "legs/lowerleg-scale-horiz-decr-incr": 0.15,
    "legs/lowerleg-scale-depth-decr-incr": 0.10,
    # big hands and feet
    "hands/hand-scale-decr-incr": 0.45,
    "hands/hand-fingers-diameter-decr-incr": 0.45,
    "hands/measure-wrist-circ-decr-incr": 0.55,
    "feet/foot-scale-decr-incr": 0.35,
    "feet/measure-ankle-circ-decr-incr": 0.40,
    # a lived-in, slightly asymmetric face; a stern set
    "asym/asym-nose-2-l": 0.35,
    "asym/asym-brown-1-r": 0.25,
    "asym/asym-jaw-1-l": 0.20,
    "asym/asym-eye-2-r": 0.20,
    "asym/asym-mouth-1-l": 0.20,
    "expression/units/caucasian/mouth-compression": 0.15,
    "expression/units/caucasian/eyebrows-left-down": 0.12,
    "expression/units/caucasian/eyebrows-right-down": 0.12,
}


def modifiers_to_targets(mods):
    out = {}
    for name, val in mods.items():
        for k, w in modifier_targets(name, val).items():
            out[k] = out.get(k, 0.0) + w
    return out


def phenotype_targets(macro=None, modifiers=None):
    """{target: weight} of the giant's phenotype (the targets the subset must vendor)."""
    macro = dict(GIANT_MACRO if macro is None else macro)
    mods = dict(GIANT_MODIFIERS if modifiers is None else modifiers)
    return merge_weights(macro_target_weights(**macro), modifiers_to_targets(mods))


def build_phenotype(macro=None, modifiers=None):
    """Return (BaseMesh, morphed vertices in MH units, target weights used)."""
    bm = load_base_mesh()
    tw = phenotype_targets(macro, modifiers)
    verts = compose(bm.verts, tw)
    return bm, verts, tw


def subset_files():
    """Data-relative paths of every file the kit reads: DATA_FILES and the phenotype's targets."""
    return sorted(set(DATA_FILES) | {target_rel(k) for k in phenotype_targets()})
