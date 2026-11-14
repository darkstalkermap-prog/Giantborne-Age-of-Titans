"""Footfalls (P21; plan M6-M9 section 4.1 family C, section 4.2): the giant at stages 1-3 on soft,
hard and wet ground (and the stage-3 cruise variants without the debris tail), people, heavy
bodies (ogres and the Ogre King, lowered further by size pitch) and wolves' paws
(bank_steps.json: sfx.step.<size class>.<surface>[.cruise]).

A footfall is a sub thump (40-90 Hz with a fast pitch drop; lower and longer with every stage),
an upper-bass punch that carries the weight on small speakers, a body of earth, the surface
layer (soft: a granular crunch of soil and grass; hard: clicks and grit; wet: a squelch with
bubbles, by the Valley's river) and, from stage 3, a tail of pebbles and earth that the cruise
variants leave out (section 4.4: after 10 s of walking the giant's steps drop 5 dB and lose
their tail). Stages 4-6, wading and hooves are world sounds (P28). Every sound is original and
synthesized here. Seeds 212001-212099.
"""

from __future__ import annotations

from synth import fx
from synth import instruments as ins

FAMILY = "steps"


def giant(rng, rate, variant, size, surface, cruise=False):
    """The giant's (or a heavy body's) footfall of a size class on a surface."""
    x = ins.giant_step(rng, size, surface, cruise, rate)
    x = fx.reflections(x, rng, rate, 5, 0.05, 0.12, 1800.0)
    return fx.finish(x, rate, floor_db=-50.0)


def heavy_far(rng, rate, variant, surface):
    """A heavy body's footfall from far off (an ogre across a clearing): a dull low thud."""
    x = ins.giant_step(rng, "heavy", surface, False, rate)
    return fx.finish(fx.distant(x, rng, rate, 320.0, 0.02, 0.12), rate, floor_db=-48.0)


def human(rng, rate, variant, surface):
    """A person's step (heel and toe)."""
    return fx.finish(ins.human_step(rng, surface, rate), rate, floor_db=-50.0)


def paw(rng, rate, variant, surface):
    """A wolf's paw pair."""
    return fx.finish(ins.paw_step(rng, surface, rate), rate, floor_db=-50.0)


V = ins.variant_cues
CUES = (
    V(FAMILY, "giant_s1_soft", giant, 212001, 3, {"size": "giant_s1", "surface": "soft"})
    + V(FAMILY, "giant_s1_hard", giant, 212004, 2, {"size": "giant_s1", "surface": "hard"})
    + V(FAMILY, "giant_s1_wet", giant, 212006, 1, {"size": "giant_s1", "surface": "wet"})
    + V(FAMILY, "giant_s2_soft", giant, 212011, 3, {"size": "giant_s2", "surface": "soft"})
    + V(FAMILY, "giant_s2_hard", giant, 212014, 2, {"size": "giant_s2", "surface": "hard"})
    + V(FAMILY, "giant_s2_wet", giant, 212016, 1, {"size": "giant_s2", "surface": "wet"})
    + V(FAMILY, "giant_s3_soft", giant, 212021, 2, {"size": "giant_s3", "surface": "soft"})
    + V(FAMILY, "giant_s3_hard", giant, 212023, 2, {"size": "giant_s3", "surface": "hard"})
    + V(FAMILY, "giant_s3_wet", giant, 212025, 1, {"size": "giant_s3", "surface": "wet"})
    + V(FAMILY, "giant_s3_soft_cruise", giant, 212031, 2, {"size": "giant_s3", "surface": "soft", "cruise": True})
    + V(FAMILY, "giant_s3_hard_cruise", giant, 212033, 1, {"size": "giant_s3", "surface": "hard", "cruise": True})
    + V(FAMILY, "human_soft", human, 212041, 3, {"surface": "soft"})
    + V(FAMILY, "human_hard", human, 212044, 2, {"surface": "hard"})
    + V(FAMILY, "human_wet", human, 212046, 1, {"surface": "wet"})
    + V(FAMILY, "heavy_soft", giant, 212051, 2, {"size": "heavy", "surface": "soft"})
    + V(FAMILY, "heavy_hard", giant, 212053, 1, {"size": "heavy", "surface": "hard"})
    + V(FAMILY, "heavy_far", heavy_far, 212055, 1, {"surface": "soft"})
    + V(FAMILY, "paw_soft", paw, 212061, 2, {"surface": "soft"})
    + V(FAMILY, "paw_hard", paw, 212063, 1, {"surface": "hard"})
)
