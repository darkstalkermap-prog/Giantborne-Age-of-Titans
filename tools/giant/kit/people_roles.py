"""The people's roles, variants, budgets and skeleton (plan M11 §2.8; numpy only, no bpy).

Every person is generated from the giant's CC0 MakeHuman data (``mh_data``) by ``people_body`` and dressed by
``people_outfit`` with the giant's garment shells (``giant_garment``). This module is the table those modules and
``build_people.py`` read, and the list of CC0 files the people need beyond the giant's (``fetch_mpfb2.py``'s
audit). A variant differs in build (the macro targets), face (the detail targets), hair or headgear and small gear;
the palette (skin, hair, cloth, faction colour) is not a variant: the third map's B channel holds the band of each
texel and the game's shader multiplies the albedo by that band's colour (``BANDS``).

P59 took plan §3.12's split point and left the ``notable`` and ``rider`` roles; P59b builds them: the named
characters of §3.15 (Edda, Reeve Tamsin, Sedge, the ferrywoman, the herald, the toll captain, the deserter and
Corvane; five of them women, as their names and records call for) and the cavalry's riders, who sit the tacked horse
(assets/creatures/horse_tacked) in the ``seated`` clip.
"""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mh_data as mh  # noqa: E402

HEIGHT_M = 1.8                    # every person is built this tall; the game's body_spec scales it (P60)
DESIGN_HEIGHT_M = 3.6576          # ... at the giant's stage-1 height first, so the giant's garment code and clips
                                  # (written in stage-1 metres) apply unchanged; the export scales by HEIGHT_M / this
EXPORT_SCALE = HEIGHT_M / DESIGN_HEIGHT_M
STEP_M = 0.9                      # the soldier's rig: ActorRig.stride_length_m (tools/builders/soldier.gd)
# P59b: the gaits' own steps at 1.8 m. P59 fitted the walk to the rig's 0.9 m step, long for a walk at 1.8 m: the
# pelvis dropped 13.6 cm a step and the knees bent deep. The walk now takes a natural 0.75 m step (PersonRig plays it
# at the brain's walk phase times 2 STEP_M / WALK_CYCLE_M, so no foot slides), the run and the flee 1.3 m (PersonRig's
# own phase at RUN_CYCLE_M).
GAIT_STEP_M = {"walk": 0.7, "run": 1.1, "flee": 1.15}

# ---- the skeleton: the game_engine rig's 53 bones less the fingers (23) ------------------------------------------
BONES = ("Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
         "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l",
         "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r")
FINGERS = ("thumb", "index", "middle", "ring", "pinky")
HAND_CURL = 0.5                   # P59's hands: half closed (clips.hand_spec's curl; the thumb 0.8 of it)
# P59b: the rest hands relaxed, each finger a little more curled than the one before it (a hand hanging at rest),
# the thumb lying along the index's side instead of closing on its tip (P59's pinch); a handle passes through the
# curl of the four fingers (people_body.grip_landmark: the manifest's grip_local_<side>)
HAND_CURLS = {"index": 0.5, "middle": 0.6, "ring": 0.66, "pinky": 0.72, "thumb": 0.55}


def fold_bone(name: str) -> str:
    """The kept bone a game_engine bone's weight folds into: a finger's into its hand, every kept bone its own."""
    if name in BONES:
        return name
    for f in FINGERS:
        if name.startswith(f + "_"):
            return "hand_" + name[-1]
    raise KeyError("no kept bone for %s" % name)


def fold_weights(groups: dict) -> dict:
    """{bone: (n,) weights} of the 53 bones -> the same of the 23 (summed)."""
    out = {}
    for b, w in groups.items():
        k = fold_bone(b)
        out[k] = out[k] + w if k in out else w.copy()
    return out


def top4(groups: dict, n: int):
    """(n, 4) bone indices (into BONES) and (n, 4) weights: each vertex's four largest, normalized to 1."""
    import numpy as np
    W = np.zeros((n, len(BONES)))
    for b, w in groups.items():
        W[:, BONES.index(b)] += w
    idx = np.argsort(-W, axis=1, kind="stable")[:, :4]
    w4 = np.take_along_axis(W, idx, axis=1)
    s = w4.sum(axis=1, keepdims=True)
    w4 = np.where(s > 0, w4 / np.maximum(s, 1e-12), np.array([1.0, 0.0, 0.0, 0.0]))
    idx = np.where(s > 0, idx, BONES.index("pelvis"))
    return idx, w4


# ---- budgets (plan §2.8) -----------------------------------------------------------------------------------------
TRIS_MAX = 5000                   # a variant: one mesh, one surface
POSE_TRIS_MAX = 600               # a crowd-pose mesh
FAR_TRIS_MAX = 150                # the far mesh
ALBEDO_PX = 512
NORMAL_PX = 256
ORM_PX = 256                      # R ambient occlusion, G roughness, B the palette band
POSES = ("hold", "brace", "advance", "flee", "corpse")
POSE_CLIP = {"hold": ("idle", 0), "brace": ("brace", 0), "advance": ("walk", 8), "flee": ("flee", 8),
             "corpse": ("death", -1)}     # each crowd pose is its clip's key (-1: the last)
# a role whose crowd poses are other keys: the riders sit their horses in every pose but the corpse
ROLE_POSE_CLIP = {"rider": {"hold": ("seated", 0), "brace": ("seated", 0), "advance": ("seated", 0),
                            "flee": ("seated", 0)}}


def pose_clip(role, pose):
    """The (clip, key) a role's crowd pose is skinned in."""
    return ROLE_POSE_CLIP.get(role, {}).get(pose, POSE_CLIP[pose])


# The riding seat (the seated clip, P59b), read from the tacked horse's manifest (assets/creatures: its saddle seat
# 1.608 m over the ground, the stirrup irons' treads about 0.915 m, their leathers 0.23 m either side of the spine
# and 0.04 m before the seat): in the clip the rider's seat (between the sitting bones) is the model's origin, so a
# rider placed at the saddle's seat landmark sits it; the feet stand in the irons, the hands before the pommel.
SEAT_DROP_M = 0.09                # the seat under the hip joints' middle
STIRRUP_M = (0.255, -0.04, -0.693)    # a stirrup's tread from the seat: out, forward (-: before), down
RIDER_ANKLE_OVER_TREAD_M = 0.075  # the ankle over the tread, ...
RIDER_ANKLE_BEHIND_M = 0.07       # ... and behind it (the ball of the foot on the tread)
POSE_JOINT_TOL_M = 0.01

# ---- the palette bands (the third map's B channel) ---------------------------------------------------------------
# "none" keeps the albedo's own colour (leather, metal, wood, the eyes); the others are multiplied by the band's colour.
BANDS = ("none", "skin", "hair", "cloth", "faction")


def band_value(band: str) -> float:
    """The B channel's value of a band: (index + 0.5) / 5, decoded with int(B * 5.0) (never rounded)."""
    return (BANDS.index(band) + 0.5) / len(BANDS)


def band_byte(band: str) -> int:
    return int(round(band_value(band) * 255.0))


def decode_band(byte: int) -> str:
    return BANDS[min(len(BANDS) - 1, int(byte / 255.0 * len(BANDS)))]


# The materials of the bake: the band each takes and its look (albedo sRGB before the band colour, roughness).
MATERIALS = {
    "skin": dict(band="skin", albedo=(0.93, 0.90, 0.88), rough=0.55),
    "lips": dict(band="skin", albedo=(0.80, 0.57, 0.60), rough=0.45),       # (P65c: rosier, 0.62 green)
    "cloth": dict(band="cloth", albedo=(0.86, 0.86, 0.86), rough=0.85),
    "faction": dict(band="faction", albedo=(0.88, 0.88, 0.88), rough=0.8),
    "leather": dict(band="none", albedo=(0.36, 0.25, 0.16), rough=0.6),
    "dark_leather": dict(band="none", albedo=(0.22, 0.16, 0.11), rough=0.55),
    "metal": dict(band="none", albedo=(0.58, 0.59, 0.62), rough=0.30),        # (under 0.35: the shader's metal)
    "mail": dict(band="none", albedo=(0.50, 0.51, 0.54), rough=0.45),
    "fur": dict(band="none", albedo=(0.42, 0.33, 0.24), rough=0.9),
    "hair": dict(band="hair", albedo=(0.90, 0.90, 0.90), rough=0.6),
    "eye": dict(band="none", albedo=(0.86, 0.84, 0.81), rough=0.4),   # (not under 0.35: the shader's metal)
}
# the giant's garment materials -> the bake's (giant_garment.GARMENTS[...]["material"] and its detail map)
GARMENT_MATERIAL = {"weave": "cloth", "leather": "leather", "fur": "fur", "metal": "metal", "mail": "mail",
                    "scale": "metal", "bone": "leather"}

# P59's square for a shared mesh's islands (u0, v0, u1, v1): people_outfit.unwrap's, which the horse's unwrap reads
# back (kit/quadruped.py); the people's atlas is laid out by ATLAS_REGIONS since P59b.
MAIN_UV = (0.0, 0.25, 0.75, 1.0)
# P59b: the role atlas's layout (u right, v up). The shared mesh's islands are packed by region: the head's skin
# (face, ears, scalp) apart, a quarter of the atlas (the face at FACE_ZOOM times the scalp's density), so the face's normals and features read; the
# side rect holds the mail (at the fixed density MAIL_UV_PER_M, upright: the person shader draws its rings from the
# mail tile there) or, for a role without mail, its garments below the crotch; the main rect the rest. A row of 64 px
# tiles along the bottom holds the variants' own pieces' patterns (hair, headgear, a tabard, a skirt, the eyes) and
# the mail's ring cell.
ATLAS_REGIONS = (("main", (0.0, 0.125, 0.5, 1.0)), ("head", (0.5, 0.5, 1.0, 1.0)),
                 ("side", (0.5, 0.125, 1.0, 0.5)))
TILES = {"hair": (0.0, 0.0), "metal": (0.125, 0.0), "faction": (0.25, 0.0), "cloth": (0.375, 0.0),
         "leather": (0.5, 0.0), "eye": (0.625, 0.0), "fur": (0.75, 0.0), "mail": (0.875, 0.0)}
TILE_SIZE = 0.125
TILE_MATERIAL = {"hair": "hair", "metal": "metal", "faction": "faction", "cloth": "cloth", "leather": "leather",
                 "eye": "eye", "fur": "fur", "mail": "mail"}
# The mail's rings (assets/shaders/person.gdshader reads the same numbers): the side rect's mail is laid out at
# MAIL_UV_PER_M (UV units a metre of the 1.8 m person) so a ring of MAIL_RING_M is MAIL_RINGS_PER_UV of a UV unit;
# the mail tile holds MAIL_TILE_RINGS x MAIL_TILE_RINGS rings.
MAIL_RING_M = 0.0125
MAIL_UV_PER_M = 0.15
MAIL_RINGS_PER_UV = 1.0 / (MAIL_UV_PER_M * MAIL_RING_M)
MAIL_TILE_RINGS = 4

# The footwear the people's own code builds (people_parts.boots) in place of the giant's shells: (P59b) the boots
# a shaft to half the calf with a turned-down cuff, the shoes cut at the ankle.
FOOTWEAR = {"boots": dict(shaft=0.5, cuff=True), "shoes": dict(shaft=0.12, cuff=False)}

# ---- the variants --------------------------------------------------------------------------------------------------
def _m(gender, age, muscle=0.5, weight=0.5, african=0.15, asian=0.15, caucasian=0.7):
    """MakeHuman macro sliders: natural proportions (proportions 0.8: MakeHuman's ideal-proportions target in part),
    average height (every person is scaled to HEIGHT_M)."""
    return dict(gender=float(gender), age=mh.age_years_to_value(age), muscle=muscle, weight=weight, height=0.5,
                proportions=0.8, african=african, asian=asian, caucasian=caucasian, cupsize=0.5, firmness=0.5)


# P65b: the women's macro muscle at most 0.5 and weight at least 0.5: the female min-weight and max-muscle targets
# are not in the vendored CC0 subset (the people's added targets stay within plan §2.12's 4 MB), and missing targets
# were skipped, so Edda's 0.55 / 0.45, the ferrywoman's 0.48 and the herald's 0.42 drew as 0.5 already.
# Faces: regional modifiers (MakeHuman's detail targets), each small so faces stay ordinary.
FACES = {
    "broad": {"nose/nose-scale-horiz-decr-incr": 0.3, "chin/chin-width-decr-incr": 0.35, "head/head-square": 0.3,
              "cheek/cheek-bones-decr-incr": 0.25, "eyebrows/eyebrows-trans-down-up": -0.2},
    "narrow": {"nose/nose-scale-horiz-decr-incr": -0.25, "chin/chin-width-decr-incr": -0.3,
               "head/head-scale-horiz-decr-incr": -0.08, "nose/nose-hump-decr-incr": 0.35,
               "mouth/mouth-scale-horiz-decr-incr": -0.15},
    "round": {"cheek/cheek-volume-decr-incr": 0.35, "head/head-fat-decr-incr": 0.3, "nose/nose-volume-decr-incr": 0.25,
              "chin/chin-prominent-decr-incr": -0.2},
    "lean": {"cheek/cheek-volume-decr-incr": -0.3, "cheek/cheek-bones-decr-incr": 0.4, "chin/chin-bones-decr-incr": 0.35,
             "eyes/eye-bag-decr-incr": 0.25, "nose/nose-point-width-decr-incr": -0.2},
    "soft": {"chin/chin-prominent-decr-incr": -0.15, "nose/nose-scale-vert-decr-incr": -0.2,
             "mouth/mouth-lowerlip-volume-decr-incr": 0.2, "eyes/eye-scale-decr-incr": 0.1},
    # P65b: the women's faces softer and plainly a woman's at the size they are seen (they still read severe and
    # boyish): the brows raised and arched, a smaller and narrower jaw and chin, an oval head, fuller lips with a
    # cupid's bow, a smaller nose, larger eyes, rounder cheeks, a slimmer neck; "fair" is P65a's name, now this
    # P65c: the younger women still read plain and somewhat boyish at 3 m: the jaw and chin smaller again, the eyes
    # larger, the nose smaller, the lips fuller, the head younger (vendored targets reweighted; none added; a narrower
    # head and a higher forehead were tried: the shared mesh, decimated on Edda, took a crease down the nose)
    "fair": {"eyebrows/eyebrows-trans-down-up": 0.45, "eyebrows/eyebrows-angle-down-up": 0.4,
             "chin/chin-width-decr-incr": -0.5, "chin/chin-height-decr-incr": -0.25,
             "chin/chin-prominent-decr-incr": -0.3, "chin/chin-jaw-drop-decr-incr": -0.4, "head/head-oval": 0.6,
             "mouth/mouth-upperlip-volume-decr-incr": 0.4, "mouth/mouth-lowerlip-volume-decr-incr": 0.4,
             "mouth/mouth-cupidsbow-decr-incr": 0.45, "nose/nose-scale-horiz-decr-incr": -0.35,
             "nose/nose-scale-vert-decr-incr": -0.3, "nose/nose-point-width-decr-incr": -0.35,
             "eyes/eye-scale-decr-incr": 0.3, "cheek/cheek-volume-decr-incr": 0.3, "cheek/cheek-inner-decr-incr": -0.2,
             "neck/neck-scale-horiz-decr-incr": -0.35, "head/head-age-decr-incr": -0.45},
    "fair_lean": {"eyebrows/eyebrows-trans-down-up": 0.4, "eyebrows/eyebrows-angle-down-up": 0.4,
                  "chin/chin-width-decr-incr": -0.45, "chin/chin-jaw-drop-decr-incr": -0.4, "head/head-oval": 0.55,
                  "chin/chin-prominent-decr-incr": -0.25,
                  "cheek/cheek-bones-decr-incr": 0.2, "mouth/mouth-upperlip-volume-decr-incr": 0.35,
                  "mouth/mouth-lowerlip-volume-decr-incr": 0.35, "mouth/mouth-cupidsbow-decr-incr": 0.4,
                  "nose/nose-scale-horiz-decr-incr": -0.25,
                  "nose/nose-scale-vert-decr-incr": -0.25, "nose/nose-point-width-decr-incr": -0.35,
                  "eyes/eye-scale-decr-incr": 0.25, "cheek/cheek-volume-decr-incr": 0.15,
                  "neck/neck-scale-horiz-decr-incr": -0.35, "head/head-age-decr-incr": -0.35},
    "fair_round": {"eyebrows/eyebrows-trans-down-up": 0.4, "eyebrows/eyebrows-angle-down-up": 0.3,
                   "chin/chin-width-decr-incr": -0.4, "chin/chin-jaw-drop-decr-incr": -0.35, "head/head-round": 0.4,
                   "chin/chin-prominent-decr-incr": -0.2,
                   "mouth/mouth-upperlip-volume-decr-incr": 0.35, "mouth/mouth-lowerlip-volume-decr-incr": 0.35,
                   "mouth/mouth-cupidsbow-decr-incr": 0.35, "nose/nose-scale-horiz-decr-incr": -0.3,
                   "nose/nose-point-width-decr-incr": -0.3, "eyes/eye-scale-decr-incr": 0.25,
                   "cheek/cheek-volume-decr-incr": 0.45, "head/head-fat-decr-incr": 0.2,
                   "neck/neck-scale-horiz-decr-incr": -0.3, "head/head-age-decr-incr": -0.2},
    # an old woman's (Sedge, Elder Maren): her age in the face's shape (the brow and the cheeks fallen, the eyes'
    # bags, the laugh lines, the corners of the mouth down) and the elders' atlas (people_bake: AGE_LINES) over the
    # women's softer features
    "aged_fair": {"head/head-age-decr-incr": 0.5, "eyes/eye-bag-decr-incr": 0.45, "mouth/mouth-laugh-lines-in-out": 0.55,
                  "cheek/cheek-volume-decr-incr": -0.1, "mouth/mouth-angles-down-up": -0.25,
                  "eyebrows/eyebrows-trans-down-up": 0.25, "eyebrows/eyebrows-angle-down-up": 0.2,
                  "chin/chin-width-decr-incr": -0.3, "chin/chin-jaw-drop-decr-incr": -0.2, "head/head-oval": 0.4,
                  "nose/nose-scale-horiz-decr-incr": -0.15, "nose/nose-point-width-decr-incr": -0.2,
                  "mouth/mouth-upperlip-volume-decr-incr": 0.1, "mouth/mouth-lowerlip-volume-decr-incr": 0.15,
                  "neck/neck-scale-horiz-decr-incr": -0.2, "neck/neck-double-decr-incr": 0.2},
    "aged": {"head/head-age-decr-incr": 0.6, "eyes/eye-bag-decr-incr": 0.5, "mouth/mouth-laugh-lines-in-out": 0.6,
             "cheek/cheek-volume-decr-incr": -0.25, "mouth/mouth-angles-down-up": -0.25},
}


def _v(name, macro, face, hair="crop", head=None, beard=None, extras=(), sex=None):
    return dict(name=name, macro=macro, face=face, hair=hair, head=head, beard=beard, extras=tuple(extras),
                sex=("male" if macro["gender"] >= 0.5 else "female") if sex is None else sex)


# Each role: its shared outfit (garment ids of giant_garment, built on the first variant's body and carried to the
# others), the garments in the faction band, the variants, the gear it may carry (gear.glb) and the role's default
# palette (for previews; the game's look table is P60's).
ROLES = {
    "soldier": dict(
        outfit=("trousers", "tunic", "boots", "bracers", "mail_hauberk", "belt"), faction=("tunic",),
        variants=(
            # (gate C) every soldier wears a surcoat in his side's colour over the mail, front and back to under the
            # hips: the mail and the helm were all a formation showed from the front, so its side did not read at
            # 60 m (the tunic's colour was under the hauberk, the shield's face held edge-on). The crowd poses and
            # the far mesh are soldier_a's, so they wear it too.
            _v("soldier_a", _m(1, 27, 0.62, 0.5), "broad", hair="crop", head="iron_helm", extras=("tabard",)),
            _v("soldier_b", _m(1, 34, 0.6, 0.62, african=0.75, asian=0.05, caucasian=0.2), "round", hair="crop",
               head="leather_cap", beard="short", extras=("tabard",)),
            _v("soldier_c", _m(1, 23, 0.55, 0.42, african=0.05, asian=0.6, caucasian=0.35), "narrow", hair="crop",
               head="iron_helm", extras=("tabard",)),
            # the iron guard: a heavier helm and a tabard (plan §2.8)
            _v("iron_guard", _m(1, 38, 0.72, 0.58), "lean", hair="crop", head="iron_helm_guard", beard="short",
               extras=("tabard", "pauldrons")),
        ),
        gear=("sword", "spear", "shield", "banner"), used_by=("enemy.soldier", "pikeman", "shieldman", "bannerman",
                                                               "iron_guard")),
    "archer": dict(
        outfit=("trousers", "tunic", "boots", "bracers", "jerkin", "belt"), faction=("tunic",),
        variants=(
            _v("archer_a", _m(1, 25, 0.5, 0.4), "lean", hair="crop", head="hood"),
            _v("archer_b", _m(1, 31, 0.55, 0.46, african=0.1, asian=0.45, caucasian=0.45), "narrow", hair="crop",
               head="leather_cap", beard="short"),
        ),
        gear=("bow", "quiver"), used_by=("enemy.archer",)),
    "mage": dict(
        outfit=("trousers", "tunic", "kilt", "shoes", "sash"), faction=("kilt", "sash"),
        variants=(
            _v("mage_a", _m(1, 46, 0.35, 0.55), "aged", hair="crop", head="hood", beard="full"),
            _v("mage_b", _m(1, 52, 0.3, 0.44, african=0.55, asian=0.1, caucasian=0.35), "lean", hair="long",
               beard="full"),
        ),
        gear=("staff",), used_by=("enemy.mage",)),
    "crew": dict(
        outfit=("trousers", "shirt", "boots", "sleeveless_vest", "belt"), faction=("shirt",),
        variants=(
            _v("crew_a", _m(1, 33, 0.7, 0.65), "broad", hair="crop", head="leather_cap", beard="short"),
            _v("crew_b", _m(1, 27, 0.6, 0.55, african=0.6, asian=0.1, caucasian=0.3), "round", hair="crop"),
        ),
        gear=("hammer",), used_by=("enemy.siege_crew",)),
    "villager": dict(
        outfit=("trousers", "shirt", "boots", "belt"), faction=(),
        variants=(
            _v("villager_a", _m(1, 30, 0.5, 0.5), "soft", hair="crop"),
            _v("villager_b", _m(1, 46, 0.45, 0.66, african=0.1, asian=0.1, caucasian=0.8), "round", hair="crop",
               beard="full"),
            _v("villager_c", _m(1, 20, 0.45, 0.4, african=0.5, asian=0.2, caucasian=0.3), "narrow", hair="crop"),
            # women (the owner's answer to question 6): the female macro targets of the same CC0 source
            _v("villager_d", _m(0, 28, 0.45, 0.5), "fair", hair="long", extras=("skirt",)),
            _v("villager_e", _m(0, 40, 0.4, 0.6, african=0.2, asian=0.4, caucasian=0.4), "fair_round", hair="long",
               head="hood", extras=("skirt",)),
        ),
        gear=(), used_by=("npc.villager", "npc.deserter", "npc.ferrywoman")),
    "elder": dict(
        outfit=("trousers", "tunic", "kilt", "shoes", "belt"), faction=(),
        variants=(
            _v("elder_a", _m(1, 70, 0.3, 0.45), "aged", hair="crop", beard="full"),
            _v("elder_b", _m(1, 74, 0.3, 0.56, african=0.4, asian=0.3, caucasian=0.3), "aged", hair="crop",
               head="hood", beard="full"),
            # P65b: the old women (Elder Maren, who wore villager_e; Sedge, who wore the notables' young face): grey
            # hair long, a skirt over the kilt, Sedge in her hood
            _v("elder_c", _m(0, 72, 0.3, 0.56), "aged_fair", hair="long", extras=("skirt",)),
            _v("elder_d", _m(0, 68, 0.3, 0.55, african=0.35, asian=0.25, caucasian=0.4), "aged_fair", hair="long",
               head="hood", extras=("skirt",)),
        ),
        gear=("staff",), used_by=("npc.elder", "npc.sedge")),
    # P59b: the named characters (plan §3.15), each a variant of their own; the tunic in their faction's colour
    "notable": dict(
        outfit=("trousers", "tunic", "boots", "belt"), faction=("tunic",),
        variants=(
            # Brannock's marchwarden: a rider of the March's roads, her colours over her tunic
            _v("edda", _m(0, 38, 0.5, 0.5), "fair_lean", hair="long", extras=("tabard",)),
            # Millford's reeve
            _v("reeve_tamsin", _m(0, 46, 0.4, 0.62, african=0.15, asian=0.1, caucasian=0.75), "fair_round", hair="long",
               head="hood", extras=("skirt",)),
            # the woodfolk's elder at Hollowmere
            _v("sedge", _m(0, 68, 0.3, 0.5, african=0.35, asian=0.25, caucasian=0.4), "aged", hair="long",
               head="hood", extras=("skirt",)),
            # Wenna, the last ferrywoman of the Mere
            _v("ferrywoman", _m(0, 34, 0.5, 0.5, african=0.1, asian=0.45, caucasian=0.45), "fair", hair="long",
               extras=("skirt",)),
            # Herald Maelis of Aldmere, in the crown's tabard
            _v("herald", _m(0, 30, 0.4, 0.5), "fair", hair="long", extras=("tabard",)),
            # Captain Hask of the toll-riders
            _v("toll_captain", _m(1, 42, 0.68, 0.6, african=0.2, asian=0.1, caucasian=0.7), "broad", hair="crop",
               head="leather_cap", beard="short", extras=("pauldrons",)),
            # Sergeant Wynn, the deserters' sergeant
            _v("deserter", _m(1, 36, 0.6, 0.45, african=0.6, asian=0.05, caucasian=0.35), "lean", hair="crop",
               beard="full"),
            # Warlord Corvane of the Iron Regiment (2.0 m in play: his record's height scales him)
            _v("corvane", _m(1, 50, 0.75, 0.55), "lean", hair="crop", head="iron_helm_guard", beard="short",
               extras=("tabard", "pauldrons")),
        ),
        gear=("sword", "staff", "banner"), used_by=("npc.edda", "npc.reeve_tamsin", "npc.sedge", "npc.ferrywoman",
                                                    "npc.herald", "npc.toll_captain", "npc.deserter",
                                                    "enemy.corvane")),
    # P59b: the cavalry's riders (they sit the tacked horse: the seated clip, ROLE_POSE_CLIP)
    "rider": dict(
        outfit=("trousers", "tunic", "boots", "bracers", "mail_hauberk", "belt"), faction=("tunic",),
        variants=(
            _v("rider_a", _m(1, 29, 0.62, 0.5, african=0.2, asian=0.1, caucasian=0.7), "broad", hair="crop",
               head="iron_helm"),
            _v("rider_b", _m(1, 35, 0.6, 0.55, african=0.1, asian=0.5, caucasian=0.4), "lean", hair="crop",
               head="leather_cap", beard="short"),
        ),
        gear=("spear", "sword", "shield"), used_by=("enemy.cavalry",)),
}
ROLE_ORDER = ("soldier", "archer", "mage", "crew", "villager", "elder", "notable", "rider")

# The default palette (sRGB) of the previews and the contact sheet: skin, hair, cloth, faction per variant.
SKIN_TONES = ("#e3b89a", "#8d5a3b", "#d6a77f", "#c58d68", "#f0c8ac", "#6e4630", "#b98361")
HAIR_TONES = ("#2b1f17", "#4a3424", "#15110e", "#7a5a3a", "#a7a39c", "#d0ccc4")
CLOTH_TONES = ("#6b6152", "#5d6a55", "#7a6a55", "#4f5662", "#8a7c63")
FACTION_TONES = {"soldier": "#8a2b22", "archer": "#3f5a2e", "mage": "#3b3f70", "crew": "#6a5a32",
                 "villager": "#7c6a4d", "elder": "#5b4a3a", "notable": "#2f4f6e", "rider": "#8a2b22"}


def preview_palette(role: str, k: int) -> dict:
    v = ROLES[role]["variants"][k]
    old = v["macro"]["age"] > mh.age_years_to_value(60)
    seed = sum(ord(c) for c in v["name"])
    return {"skin": SKIN_TONES[seed % len(SKIN_TONES)],
            "hair": HAIR_TONES[4 + seed % 2] if old else HAIR_TONES[seed % 4],
            "cloth": CLOTH_TONES[seed % len(CLOTH_TONES)], "faction": FACTION_TONES[role]}


def variants(role):
    return ROLES[role]["variants"]


def all_variants():
    return [(r, k, v) for r in ROLE_ORDER for k, v in enumerate(ROLES[r]["variants"])]


# ---- the clips (people_clips.glb) ------------------------------------------------------------------------------------
CLIP_FRAMES = {"idle": 60, "walk": 32, "run": 32, "flee": 32, "brace": 1, "cower": 30, "seated": 1, "held": 30,
               "tumble": 24, "death": 30, "grip_r": 1, "grip_l": 1}
CLIP_LOOPS = ("idle", "walk", "run", "flee", "cower", "held", "tumble")
PARTIAL_CLIPS = {"grip_r": ("hand_r",), "grip_l": ("hand_l",)}


# ---- the CC0 data the people read ------------------------------------------------------------------------------------
def variant_targets(v) -> dict:
    """{target: weight} of a variant's phenotype: its macro targets and its face's detail targets."""
    return mh.merge_weights(mh.macro_target_weights(**v["macro"]), mh.modifiers_to_targets(FACES[v["face"]]))


def subset_files() -> list:
    """Data-relative paths of every file the people read (the giant's subset, mh_data.subset_files, and more)."""
    out = set(mh.subset_files())
    for _r, _k, v in all_variants():
        out |= {mh.target_rel(t) for t in variant_targets(v)}
    return sorted(out)


def people_only_files() -> list:
    """The files the people read that the giant does not (mpfb2/PEOPLE.sha256)."""
    return sorted(set(subset_files()) - set(mh.subset_files()))
