"""Voices (P21; plan M6-M9 section 4.1 family E, section 4.2): calls, never words, synthesized by
source and filter (synth.voices: a Rosenberg glottal pulse train with jitter, shimmer and
aspiration through moving formants). bank_voices.json: sfx.voice.<voice>.<call> and the giant's
own sfx.player.*.

* human (soldiers, archers, mages, villagers; f0 120-260 Hz): alert, attack, hurt, stagger,
  death, awe, flee and greet; the elder (an older woman, tract x 1.12) greets with her own call
  and borrows the human calls a little higher (in the bank)
* wolf: snarls, barks, yelps, a whine; jaws snapping
* ogre (f0 60-90, tract x 0.72) and the Ogre King (f0 45-60, tract x 0.6, a subharmonic and a
  growl): bellows, effort grunts, pain, a long death; the King's roar
* the giant (f0 55-70, tract x 0.62): pain, a heavy pain, a dazed groan, its death, and the
  growling intimidation of the village
* crowds: a gasp, a murmur and a cheer of six or seven mixed voices

Every sound is original and synthesized here. Seeds 213001-213199.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins
from synth import voices as vo

FAMILY = "voices"


def _out(x, rate, echo=None):
    if echo is not None:
        x = echo(x)
    return fx.finish(x, rate, fade_in_s=0.004)


# --------------------------------------------------------------------------- people

HUMAN_ALERT = [  # (f0 path, vowel path)
    ([(0.0, 150.0), (0.08, 235.0), (0.3, 215.0), (0.45, 160.0)], [(0.0, "e"), (0.12, "e"), (0.32, "i")]),
    ([(0.0, 135.0), (0.07, 205.0), (0.25, 225.0), (0.45, 150.0)], [(0.0, "ae"), (0.18, "a"), (0.4, "uh")]),
]
HUMAN_ATTACK = [
    ([(0.0, 190.0), (0.05, 230.0), (0.3, 170.0)], [(0.0, "a"), (0.3, "uh")]),
    ([(0.0, 200.0), (0.04, 215.0), (0.3, 160.0)], [(0.0, "uh"), (0.3, "a")]),
    ([(0.0, 170.0), (0.06, 245.0), (0.3, 190.0)], [(0.0, "i"), (0.09, "a"), (0.3, "a")]),
]
HUMAN_HURT = [
    ([(0.0, 215.0), (0.06, 225.0), (0.3, 140.0)], [(0.0, "uh"), (0.3, "u")]),
    ([(0.0, 230.0), (0.05, 245.0), (0.3, 150.0)], [(0.0, "a"), (0.3, "uh")]),
    ([(0.0, 190.0), (0.05, 200.0), (0.3, 130.0)], [(0.0, "ae"), (0.15, "uh"), (0.3, "uh")]),
]


def human(rng, rate, variant, call):
    """A man's call (soldiers, archers, mages, villagers)."""
    if call == "alert":
        f0, vowels = HUMAN_ALERT[variant]
        x = vo.call(rng, 0.45, f0, vowels, [(0.0, 0.0), (0.03, 1.0), (0.3, 0.85), (0.45, 0.0)], rate,
                    rng.uniform(0.97, 1.03), breath_points=[(0.0, 0.7), (0.05, 0.06), (0.4, 0.15)], tilt_db=1.5)
    elif call == "attack":
        f0, vowels = HUMAN_ATTACK[variant]
        x = vo.call(rng, 0.3, f0, vowels, [(0.0, 0.0), (0.015, 1.0), (0.12, 0.8), (0.3, 0.0)], rate,
                    rng.uniform(0.96, 1.04), breath_points=[(0.0, 0.5), (0.03, 0.08), (0.3, 0.3)], shimmer=0.1,
                    drive=1.4, tilt_db=1.0)
    elif call == "hurt":
        f0, vowels = HUMAN_HURT[variant]
        x = vo.call(rng, 0.3, f0, vowels, [(0.0, 0.0), (0.01, 1.0), (0.1, 0.7), (0.3, 0.0)], rate,
                    rng.uniform(0.96, 1.04), breath_points=[(0.0, 0.2), (0.2, 0.3), (0.3, 0.6)], jitter=0.025,
                    shimmer=0.12, drive=1.3)
    elif call == "stagger":
        x = vo.call(rng, 0.4, [(0.0, 150.0), (0.1, 158.0), (0.4, 108.0)], [(0.0, "uh"), (0.25, "o"), (0.4, "u")],
                    [(0.0, 0.0), (0.03, 0.9), (0.2, 0.7), (0.4, 0.0)], rate, 1.0,
                    breath_points=[(0.0, 0.3), (0.4, 0.5)], jitter=0.03, shimmer=0.12)
    elif call == "death":
        top = (215.0, 195.0)[variant]
        x = vo.call(rng, 0.66, [(0.0, top * 0.9), (0.06, top), (0.32, top * 0.75), (0.66, top * 0.48)],
                    [(0.0, "a"), (0.28, "a"), (0.5, "o"), (0.66, "u")],
                    [(0.0, 0.0), (0.02, 1.0), (0.28, 0.8), (0.66, 0.0)], rate, rng.uniform(0.97, 1.03),
                    breath_points=[(0.0, 0.15), (0.36, 0.3), (0.66, 0.8)], jitter=0.035, shimmer=0.14, drive=1.2)
    elif call == "awe":
        x = vo.call(rng, 0.5, [(0.0, 135.0), (0.2, 190.0), (0.5, 150.0)], [(0.0, "u"), (0.12, "o"), (0.5, "o")],
                    [(0.0, 0.0), (0.06, 0.8), (0.25, 1.0), (0.5, 0.0)], rate, 1.0,
                    breath_points=[(0.0, 0.8), (0.1, 0.25), (0.5, 0.5)], jitter=0.02)
    elif call == "flee":
        x = vo.call(rng, 0.55, [(0.0, 230.0), (0.08, 285.0), (0.55, 240.0)], [(0.0, "a"), (0.35, "ae"), (0.55, "e")],
                    [(0.0, 0.0), (0.02, 1.0), (0.4, 0.8), (0.55, 0.0)], rate, 1.02,
                    breath_points=[(0.0, 0.3), (0.55, 0.4)], vibrato_hz=9.0, vibrato=0.035, shimmer=0.15, drive=1.2)
    else:   # greet: a friendly rising "mm-hm?"
        x = np.zeros(fx.frames(0.5, rate))
        a = vo.call(rng, 0.18, [(0.0, 125.0), (0.18, 135.0)], [(0.0, "m"), (0.18, "m")],
                    [(0.0, 0.0), (0.03, 0.7), (0.15, 0.6), (0.18, 0.0)], rate, 1.0, breath=0.05)
        b = vo.call(rng, 0.3, [(0.0, 135.0), (0.3, 175.0)], [(0.0, "m"), (0.07, "a"), (0.3, "a")],
                    [(0.0, 0.0), (0.04, 0.9), (0.22, 0.8), (0.3, 0.0)], rate, 1.0, breath=0.06)
        core.mix_into(x, 0, a)
        core.mix_into(x, fx.frames(0.2, rate), b)
    return _out(x, rate)


def elder(rng, rate, variant):
    """Elder Maren's greeting: an older woman's warm, slightly breathy 'mm? ah...'."""
    x = np.zeros(fx.frames(0.62, rate))
    a = vo.call(rng, 0.22, [(0.0, 185.0), (0.22, 205.0)], [(0.0, "m"), (0.22, "m")],
                [(0.0, 0.0), (0.04, 0.7), (0.18, 0.6), (0.22, 0.0)], rate, 1.12, breath=0.12, jitter=0.03, shimmer=0.1)
    b = vo.call(rng, 0.36, [(0.0, 215.0), (0.12, 228.0), (0.36, 170.0)], [(0.0, "a"), (0.2, "a"), (0.36, "uh")],
                [(0.0, 0.0), (0.03, 0.9), (0.2, 0.75), (0.36, 0.0)], rate, 1.12, breath=0.14, jitter=0.03, shimmer=0.1)
    core.mix_into(x, 0, a)
    core.mix_into(x, fx.frames(0.24, rate), b)
    return _out(x, rate)


# --------------------------------------------------------------------------- wolves


def wolf(rng, rate, variant, call):
    """A wolf: snarls, barks, yelps and whines (shaped noise and a small resonant voice)."""
    if call == "alert":
        n = fx.frames(0.55, rate)
        x = np.zeros(n)
        core.mix_into(x, 0, vo.snarl(rng, 0.3, rate, rng.uniform(110.0, 130.0)), 0.7)
        core.mix_into(x, fx.frames(0.28, rate), vo.bark(rng, 0.22, rate, rng.uniform(360.0, 420.0)), 1.0)
    elif call == "attack":
        n = fx.frames(0.32, rate)
        x = fx.fit(vo.snarl(rng, 0.26, rate, rng.uniform(120.0, 150.0), 1.5, 1.0), n)
        x = x / max(core.peak(x), 1e-9) + 0.8 * vo.snap(rng, n, rate, rng.uniform(0.17, 0.22))
    elif call == "hurt":
        x = vo.yelp(rng, 0.25, rate, rng.uniform(780.0, 900.0), rng.uniform(430.0, 520.0))
    elif call == "death":
        n = fx.frames(0.75, rate)
        x = np.zeros(n)
        core.mix_into(x, 0, vo.yelp(rng, 0.2, rate, 880.0, 560.0), 1.0)
        core.mix_into(x, fx.frames(0.18, rate), vo.yelp(rng, 0.55, rate, 620.0, 300.0, whine=True), 0.6)
    else:   # flee: a whimper
        x = vo.yelp(rng, 0.5, rate, rng.uniform(950.0, 1050.0), 700.0, 1.65, True)
    return _out(x, rate)


# --------------------------------------------------------------------------- ogres and the King

OGRE = {"tract": 0.72, "sub": 0.25, "growl_hz": 33.0}
KING = {"tract": 0.6, "sub": 0.45, "growl_hz": 31.0}


def big(rng, rate, variant, who, call):
    """An ogre's or the Ogre King's call: bellows, effort grunts, pain, death and the King's roar."""
    p = OGRE if who == "ogre" else KING
    low = 1.0 if who == "ogre" else 0.72
    tract = p["tract"] * rng.uniform(0.97, 1.03)
    kw = {"sub": p["sub"], "growl_hz": p["growl_hz"], "jitter": 0.03, "shimmer": 0.14}
    echo = None
    if call == "alert":
        x = vo.call(rng, 0.62, [(0.0, 70 * low), (0.12, 96 * low), (0.62, 66 * low)], [(0.0, "uh"), (0.1, "a"), (0.62, "o")],
                    [(0.0, 0.0), (0.05, 1.0), (0.45, 0.8), (0.62, 0.0)], rate, tract, breath=0.12, growl=0.3, drive=2.2, **kw)
    elif call == "attack":
        top = (88.0, 80.0)[variant] * low
        dur = 0.45 if who == "ogre" else 0.52
        x = vo.call(rng, dur, [(0.0, top * 0.85), (0.05, top), (dur, top * 0.75)], [(0.0, "uh"), (dur * 0.5, "a"), (dur, "uh")],
                    [(0.0, 0.0), (0.02, 1.0), (dur * 0.4, 0.75), (dur, 0.0)], rate, tract, breath=0.18, growl=0.35,
                    drive=2.4, **kw)
    elif call == "hurt":
        top = (92.0, 84.0)[variant] * low
        x = vo.call(rng, 0.4, [(0.0, top), (0.05, top * 1.06), (0.4, top * 0.65)], [(0.0, "a"), (0.15, "uh"), (0.4, "u")],
                    [(0.0, 0.0), (0.012, 1.0), (0.15, 0.7), (0.4, 0.0)], rate, tract, breath=0.2, growl=0.25,
                    drive=2.0, **kw)
    elif call == "death":
        dur = 0.9 if who == "ogre" else 1.25
        x = vo.call(rng, dur, [(0.0, 82 * low), (0.1, 95 * low), (dur * 0.5, 70 * low), (dur, 42 * low)],
                    [(0.0, "a"), (dur * 0.4, "a"), (dur * 0.7, "o"), (dur, "u")],
                    [(0.0, 0.0), (0.05, 1.0), (dur * 0.5, 0.75), (dur, 0.0)], rate, tract,
                    breath_points=[(0.0, 0.12), (dur * 0.6, 0.3), (dur, 0.85)], growl=0.35, drive=2.0, **kw)
        if who != "ogre":
            echo = lambda s: fx.valley_echo(s, rng, rate, 0.34, 0.22, 800.0, 2)
    else:   # roar (the King's phase roar; the ogre borrows its alert in the bank)
        dur = 1.2
        x = vo.call(rng, dur, [(0.0, 52.0), (0.2, 64.0), (0.8, 60.0), (dur, 44.0)],
                    [(0.0, "uh"), (0.15, "a"), (0.85, "o"), (dur, "u")],
                    [(0.0, 0.0), (0.12, 1.0), (0.9, 0.85), (dur, 0.0)], rate, tract, breath=0.22, growl=0.5,
                    drive=2.8, tilt_db=1.0, **kw)
        rattle = vo.growl_tail(rng, fx.frames(dur, rate), rate, 40.0, tract,
                               [(0.0, 0.0), (0.3, 0.6), (1.0, 0.5), (dur, 0.0)])
        x = x / max(core.peak(x), 1e-9) + 0.35 * rattle / max(core.peak(rattle), 1e-9)
        echo = lambda s: fx.valley_echo(s, rng, rate, 0.32, 0.25, 700.0, 2)
    return _out(x, rate, echo)


def king_roar_far(rng, rate, variant):
    """The King's roar heard from far off (and the ogres' bellows at a distance)."""
    x = big(rng, rate, 0, "king", "roar")
    return fx.finish(fx.distant(x, rng, rate, 700.0, 0.05, 0.2), rate)


# --------------------------------------------------------------------------- the giant (the player)

GIANT = {"tract": 0.62, "sub": 0.3, "growl_hz": 34.0, "jitter": 0.03, "shimmer": 0.12}


def giant(rng, rate, variant, call):
    """The giant's own voice: pain, a heavy pain, a dazed groan, its death, the intimidation."""
    kw = dict(GIANT)
    tract = kw.pop("tract") * rng.uniform(0.98, 1.02)
    if call == "hurt":
        top = (72.0, 66.0, 78.0)[variant]
        vowel = ("uh", "a", "u")[variant]
        x = vo.call(rng, 0.4, [(0.0, top), (0.05, top * 1.08), (0.4, top * 0.7)], [(0.0, vowel), (0.4, "u")],
                    [(0.0, 0.0), (0.012, 1.0), (0.12, 0.7), (0.4, 0.0)], rate, tract, breath=0.2, growl=0.2,
                    drive=2.0, **kw)
    elif call == "hurt_heavy":
        x = vo.call(rng, 0.65, [(0.0, 70.0), (0.06, 84.0), (0.3, 76.0), (0.65, 50.0)], [(0.0, "a"), (0.35, "a"), (0.65, "o")],
                    [(0.0, 0.0), (0.015, 1.0), (0.3, 0.8), (0.65, 0.0)], rate, tract, breath=0.2, growl=0.35,
                    drive=2.4, **kw)
    elif call == "stagger":
        x = vo.call(rng, 0.55, [(0.0, 64.0), (0.15, 68.0), (0.55, 48.0)], [(0.0, "uh"), (0.3, "o"), (0.55, "u")],
                    [(0.0, 0.0), (0.04, 0.9), (0.3, 0.7), (0.55, 0.0)], rate, tract,
                    breath_points=[(0.0, 0.25), (0.55, 0.6)], growl=0.2, **kw)
    elif call == "death":
        dur = 1.2
        x = vo.call(rng, dur, [(0.0, 74.0), (0.1, 82.0), (0.6, 62.0), (dur, 38.0)],
                    [(0.0, "a"), (0.5, "a"), (0.9, "o"), (dur, "u")],
                    [(0.0, 0.0), (0.04, 1.0), (0.7, 0.7), (dur, 0.0)], rate, tract,
                    breath_points=[(0.0, 0.15), (0.8, 0.35), (dur, 0.9)], growl=0.3, drive=1.8, **kw)
        x = fx.valley_echo(x, rng, rate, 0.36, 0.2, 700.0, 2)
    else:   # intimidate: a long growl rising into a roar
        dur = 1.15
        growl = vo.growl_tail(rng, fx.frames(dur, rate), rate, 46.0, tract, [(0.0, 0.0), (0.1, 0.8), (0.5, 0.6), (0.7, 0.0)])
        roar = vo.call(rng, dur, [(0.0, 50.0), (0.45, 58.0), (0.75, 74.0), (dur, 56.0)],
                       [(0.0, "u"), (0.45, "o"), (0.7, "a"), (dur, "a")],
                       [(0.0, 0.0), (0.4, 0.2), (0.7, 1.0), (dur, 0.0)], rate, tract, breath=0.25, growl=0.45,
                       drive=2.6, **kw)
        x = 0.6 * growl / max(core.peak(growl), 1e-9) + roar / max(core.peak(roar), 1e-9)
        x = fx.valley_echo(x, rng, rate, 0.3, 0.2, 800.0, 1)
    return _out(x, rate)


# --------------------------------------------------------------------------- crowds


def crowd(rng, rate, variant, call):
    """A village crowd: a shocked gasp, a relieved murmur, a cheer."""
    def speaker(r, i):
        return vo.voice_params(r, "woman" if i % 3 == 1 else ("elder" if i % 5 == 4 else "man"))

    if call == "gasp":
        def one(r, i):
            p = speaker(r, i)
            g = vo.breath(r, 0.45, [(0.0, "a"), (0.45, "o")], [(0.0, 0.0), (0.05, 1.0), (0.3, 0.6), (0.45, 0.0)], rate,
                          p["tract"])
            v = vo.call(r, 0.45, [(0.0, p["f0"] * 1.1), (0.45, p["f0"] * 1.3)], [(0.0, "a"), (0.45, "o")],
                        [(0.0, 0.0), (0.12, 0.0), (0.2, 0.5), (0.45, 0.0)], rate, p["tract"], breath=0.5)
            return g + 0.6 * v
        x = vo.crowd(rng, 0.7, one, 6, 0.15, rate, 5500.0)
    elif call == "murmur":
        def one(r, i):
            p = speaker(r, i)
            dur = 0.75
            path = [(k * dur / 5, str(r.choice(["a", "e", "o", "uh", "m", "i"]))) for k in range(6)]
            f = [(k * dur / 4, p["f0"] * r.uniform(0.85, 1.12)) for k in range(5)]
            amp = [(0.0, 0.0)] + [(k * dur / 8 + 0.05, r.uniform(0.2, 1.0)) for k in range(8)] + [(dur, 0.0)]
            return vo.call(r, dur, f, path, amp, rate, p["tract"], breath=0.12)
        x = vo.crowd(rng, 0.85, one, 7, 0.1, rate, 2800.0)
    else:   # cheer
        def one(r, i):
            p = speaker(r, i)
            top = p["f0"] * r.uniform(1.4, 1.7)
            return vo.call(r, 0.7, [(0.0, p["f0"] * 1.1), (0.1, top), (0.45, top * 0.95), (0.7, top * 0.7)],
                           [(0.0, "e"), (0.12, "e"), (0.4, "i"), (0.7, "i")] if i % 2 else [(0.0, "o"), (0.2, "a"), (0.7, "a")],
                           [(0.0, 0.0), (0.04, 1.0), (0.45, 0.8), (0.7, 0.0)], rate, p["tract"],
                           breath_points=[(0.0, 0.5), (0.05, 0.08), (0.7, 0.2)], tilt_db=1.0)
        x = vo.crowd(rng, 0.85, one, 6, 0.2, rate, 6000.0)
    return _out(x, rate)


V = ins.variant_cues
CUES = (
    V(FAMILY, "human_alert", human, 213001, 2, {"call": "alert"})
    + V(FAMILY, "human_attack", human, 213011, 3, {"call": "attack"})
    + V(FAMILY, "human_hurt", human, 213021, 3, {"call": "hurt"})
    + V(FAMILY, "human_stagger", human, 213031, 1, {"call": "stagger"})
    + V(FAMILY, "human_death", human, 213041, 2, {"call": "death"})
    + V(FAMILY, "human_awe", human, 213051, 1, {"call": "awe"})
    + V(FAMILY, "human_flee", human, 213061, 1, {"call": "flee"})
    + V(FAMILY, "human_greet", human, 213071, 1, {"call": "greet"})
    + V(FAMILY, "elder_greet", elder, 213081, 1, {})
    + V(FAMILY, "wolf_alert", wolf, 213091, 1, {"call": "alert"})
    + V(FAMILY, "wolf_attack", wolf, 213101, 2, {"call": "attack"})
    + V(FAMILY, "wolf_hurt", wolf, 213111, 2, {"call": "hurt"})
    + V(FAMILY, "wolf_death", wolf, 213121, 1, {"call": "death"})
    + V(FAMILY, "wolf_flee", wolf, 213131, 1, {"call": "flee"})
    + V(FAMILY, "ogre_alert", big, 213141, 1, {"who": "ogre", "call": "alert"})
    + V(FAMILY, "ogre_attack", big, 213143, 2, {"who": "ogre", "call": "attack"})
    + V(FAMILY, "ogre_hurt", big, 213146, 2, {"who": "ogre", "call": "hurt"})
    + V(FAMILY, "ogre_death", big, 213149, 1, {"who": "ogre", "call": "death"})
    + V(FAMILY, "king_attack", big, 213151, 2, {"who": "king", "call": "attack"})
    + V(FAMILY, "king_death", big, 213154, 1, {"who": "king", "call": "death"})
    + V(FAMILY, "king_roar", big, 213156, 1, {"who": "king", "call": "roar"})
    + V(FAMILY, "king_roar_far", king_roar_far, 213158, 1, {})
    + V(FAMILY, "giant_hurt", giant, 213161, 3, {"call": "hurt"})
    + V(FAMILY, "giant_hurt_heavy", giant, 213165, 1, {"call": "hurt_heavy"})
    + V(FAMILY, "giant_stagger", giant, 213167, 1, {"call": "stagger"})
    + V(FAMILY, "giant_death", giant, 213169, 1, {"call": "death"})
    + V(FAMILY, "giant_intimidate", giant, 213171, 1, {"call": "intimidate"})
    + V(FAMILY, "crowd_gasp", crowd, 213181, 1, {"call": "gasp"})
    + V(FAMILY, "crowd_murmur", crowd, 213183, 1, {"call": "murmur"})
    + V(FAMILY, "crowd_cheer", crowd, 213185, 1, {"call": "cheer"})
)
