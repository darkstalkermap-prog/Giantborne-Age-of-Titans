"""Interface sounds (P21; plan M6-M9 section 4.1 family H, section 4.2): bank_ui.json: sfx.ui.*.

Short sine and triangle blips with fast envelopes and two- or three-note intervals drawn from the
score's key (D dorian: fifths and fourths, no thirds, so they sit under any music), a low square
buzz for a refusal, a paper rustle for the map, a few tactile ones (a clink for metal, a wooden
thunk, a blade's slide, leaves) for items and weapons. Quiet and short on purpose: interface cues
repeat constantly. Every sound is original and synthesized here. Seeds 216001-216099.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins

FAMILY = "ui"

# MIDI notes of the key (D dorian)
D4, E4, G4, A4, B4 = 62, 64, 67, 69, 71
D5, E5, G5, A5, B5 = 74, 76, 79, 81, 83
D6, E6, A6 = 86, 88, 93


def _norm(x):
    return np.asarray(x) / max(core.peak(x), 1e-9)


def notes(rng, rate, variant, seconds, seq, wave="sine", step=None, tau=0.05, glide=0.0, harmonics=0.0, attack=0.003):
    """A blip of one or more notes."""
    x = ins.blip(rng, seconds, seq, rate, wave, step, attack, tau, 4.0, glide, harmonics)
    return fx.finish(x, rate, fade_out_s=0.006, floor_db=-50.0)


def chime(rng, rate, variant, seconds, seq, step, decay):
    """Bell-like notes (a soft inharmonic chime per note)."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    for i, note in enumerate(seq):
        b = ins.bell(rng, n, rate, core.midi_hz(note) * 1.78, decay, strike=0.1)
        core.mix_into(x, fx.frames(i * step, rate), _norm(b), 1.0 - 0.1 * i)
    return fx.finish(x, rate, fade_out_s=0.01, floor_db=-50.0)


def denied(rng, rate, variant, seconds):
    """A refusal: a low square buzz in two short pulses."""
    n = fx.frames(seconds, rate)
    return fx.finish(ins.buzz(n, rate, 116.5, 2, 0.04, 1400.0), rate, fade_out_s=0.006)


def horn(rng, rate, variant, seconds, seq, step):
    """A soft horn-like call (filtered saws): a new quest."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    for i, note in enumerate(seq):
        m = n - fx.frames(i * step, rate)
        f = core.midi_hz(note)
        v = core.saw(f, m, rate) + 0.5 * core.saw(f * 1.004, m, rate)
        v = fx.lowpass(v, 1300.0, 2.0, rate, "zero") * core.adsr(m, rate, 0.02, 0.08, 0.6, min(0.15, m / rate * 0.5))
        core.mix_into(x, fx.frames(i * step, rate), v)
    return fx.finish(x, rate, fade_in_s=0.004, floor_db=-50.0)


def tactile(rng, rate, variant, seconds, kind):
    """Item and equipment sounds: a metal clink, a wooden thunk, a blade's slide, a leafy thump,
    a soft pop, a camera click, a paper rustle."""
    n = fx.frames(seconds, rate)
    if kind == "metal":
        x = ins.ring(rng, n, rate, ins.metal_partials(rng, 2400.0, 6000.0, 5), 0.12, 0.04) + 0.3 * ins.click(n, rate)
    elif kind == "wood":
        x = ins.impact_wood(rng, seconds, 0.2, rate, rng.uniform(300.0, 360.0)) + 0.3 * ins.blip(rng, seconds, [D5], rate, "triangle", tau_s=0.05)
    elif kind == "blade":
        slide = ins.whoosh(rng, seconds, 2500.0, 6000.0, 0.6, 3.0, 1.5, color="white")
        x = 0.6 * _norm(slide) + 0.5 * ins.ring(rng, n, rate, ins.metal_partials(rng, 2800.0, 5500.0, 4), 0.1, 0.04) * fx.env_ad(n, rate, 0.15, 0.1)
    elif kind == "leaves":
        env = fx.env_ad(n, rate, 0.01, seconds * 0.4)
        x = 0.6 * _norm(ins.leaves(rng, n, rate, env, 1400.0)) + 0.6 * ins.thump(n, rate, 140.0, 95.0, 0.02, 0.05, 0.002, 0.2, 0.6)
    elif kind == "pop":
        x = core.sine(fx.glide(n, rate, 900.0, 520.0, 0.02), n, rate) * fx.env_ad(n, rate, 0.002, 0.04)
    elif kind == "camera":
        x = 0.7 * ins.burst(rng, n, rate, 1500.0, 7000.0, 0.0002, 0.003) + 0.4 * ins.blip(rng, seconds, [A4], rate, "triangle", tau_s=0.025)
    else:   # paper: the map unfolding
        rustle = ins.crunch(rng, n, rate, 0.0, seconds * 0.8, 900.0, 1500.0, 7000.0, (0.003, 0.012))
        slide = ins.whoosh(rng, seconds, 1200.0, 4500.0, 0.4, 1.5, 1.4, color="white")
        x = 0.7 * _norm(rustle) + 0.4 * _norm(slide)
    return fx.finish(x, rate, fade_out_s=0.006, floor_db=-50.0)


V = ins.variant_cues
CUES = (
    V(FAMILY, "denied", denied, 216001, 1, {"seconds": 0.22})
    + V(FAMILY, "saved", chime, 216002, 1, {"seconds": 0.42, "seq": [D5, A5], "step": 0.09, "decay": 0.3})
    + V(FAMILY, "loot", notes, 216003, 1, {"seconds": 0.34, "seq": [A5, D6, E6], "step": 0.055, "tau": 0.08, "harmonics": 0.15})
    + V(FAMILY, "item", tactile, 216004, 1, {"seconds": 0.12, "kind": "pop"})
    + V(FAMILY, "item_metal", tactile, 216005, 1, {"seconds": 0.25, "kind": "metal"})
    + V(FAMILY, "item_quest", chime, 216006, 1, {"seconds": 0.55, "seq": [D5, A5, D6], "step": 0.1, "decay": 0.35})
    + V(FAMILY, "equip", tactile, 216007, 1, {"seconds": 0.24, "kind": "wood"})
    + V(FAMILY, "equip_sword", tactile, 216008, 1, {"seconds": 0.3, "kind": "blade"})
    + V(FAMILY, "equip_tree", tactile, 216009, 1, {"seconds": 0.3, "kind": "leaves"})
    + V(FAMILY, "ability_learned", notes, 216010, 1, {"seconds": 0.62, "seq": [D5, A5, D6, E6], "step": 0.075, "tau": 0.12, "harmonics": 0.2})
    + V(FAMILY, "select", notes, 216011, 1, {"seconds": 0.07, "seq": [A5], "wave": "triangle", "tau": 0.02})
    + V(FAMILY, "quest_new", horn, 216012, 1, {"seconds": 0.5, "seq": [D4, A4], "step": 0.16})
    + V(FAMILY, "tip", chime, 216013, 1, {"seconds": 0.28, "seq": [E6], "step": 0.0, "decay": 0.22})
    + V(FAMILY, "lock_on", notes, 216014, 1, {"seconds": 0.09, "seq": [E6, A6], "step": 0.035, "tau": 0.02})
    + V(FAMILY, "lock_off", notes, 216015, 1, {"seconds": 0.09, "seq": [E6, A5], "step": 0.035, "tau": 0.02})
    + V(FAMILY, "camera", tactile, 216016, 1, {"seconds": 0.07, "kind": "camera"})
    + V(FAMILY, "warn", notes, 216017, 1, {"seconds": 0.28, "seq": [B4, B4], "wave": "triangle", "step": 0.12, "tau": 0.04})
    + V(FAMILY, "open", notes, 216018, 1, {"seconds": 0.14, "seq": [E5, B5], "step": 0.05, "tau": 0.035})
    + V(FAMILY, "close", notes, 216019, 1, {"seconds": 0.12, "seq": [B5, E5], "step": 0.045, "tau": 0.03})
    + V(FAMILY, "move", notes, 216020, 1, {"seconds": 0.045, "seq": [D6], "wave": "triangle", "tau": 0.01})
    + V(FAMILY, "back", notes, 216021, 1, {"seconds": 0.1, "seq": [A5, E5], "step": 0.04, "tau": 0.025})
    + V(FAMILY, "map_open", tactile, 216022, 1, {"seconds": 0.35, "kind": "paper"})
)
