"""The Valley's ambience (P23; plan M6-M9 sections 4.2, 4.3 and 4.5): four beds, the spots that
punctuate them, the flush of birds a giant's step sets off, and two positioned emitter loops.

Beds (20 s, stereo, seamless; synth/ambience.py):
    meadow   Giant's Hollow and the sandbox: a soft wind breathing in gusts, crickets in the grass
    forest   the Old Wood: leaves rustling in waves over a low wind in the canopy
    village  Thornwick and its fields: the murmur of people far off, hens scratching, a light wind
    stone    the Barrow, the quarry, the ruins and Kingsfall: cold wind whistling through stone,
             drips in a hollow, a deep rumble

Spots (mono one-shots, at most 1.5 s): a lark, a cricket burst, a gust (the Hollow); a
woodpecker, an owl, a crow, two tree creaks, a far howl (the Wood); a dog, a smith's hammer, a far
call, a cart (Thornwick); two pebble falls, a wind whistle, a far clank (the stone districts; the
crow too); and birds taking flight (the flush reaction).

Emitters (10 s mono loops): the river under the King's Bridge and the Giantforge's fire.
"""

from __future__ import annotations

import numpy as np

from synth import ambience as A
from synth import core, fx, music as M

FAMILY = "ambience"
RATE = core.DEFAULT_RATE
_P = "res://assets/audio/ambience/"
BED_S = 20.0
EMITTER_S = 10.0


def _mix(*layers) -> np.ndarray:
    """Sums (layer, gain) pairs of stereo layers, each first brought to unit RMS."""
    out = None
    for layer, gain in layers:
        x = layer / max(core.rms(layer), 1e-9) * gain
        out = x if out is None else out + x
    return out


def bed_meadow(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=650.0, gust_hz=0.07, depth=0.5)
    insects = A.insects_layer(n, rng, count=5)
    grass = A.leaves_layer(n, rng)
    return A.finish_loop(_mix((wind, 1.0), (insects, 0.32), (grass, 0.12)), drive=1.6)


def bed_forest(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    leaves = A.leaves_layer(n, rng)
    wind = A.wind_layer(n, rng, base_hz=380.0, gust_hz=0.05, depth=0.6)
    insects = A.insects_layer(n, rng, count=2)
    return A.finish_loop(_mix((leaves, 0.55), (wind, 1.0), (insects, 0.08)), drive=1.6)


def bed_village(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    murmur = A.murmur_layer(n, rng, count=80)
    hens = A.hens_layer(n, rng)
    wind = A.wind_layer(n, rng, base_hz=550.0, gust_hz=0.06, depth=0.4)
    return A.finish_loop(_mix((murmur, 0.7), (hens, 0.3), (wind, 0.6)), drive=1.6)


def bed_stone(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=480.0, gust_hz=0.05, depth=0.7)
    whistle = A.whistle_layer(n, rng)
    drips = A.drips_layer(n, rng)
    rumble = np.stack([A.loop_noise(n, rng, 25.0, 140.0, "brown"), A.loop_noise(n, rng, 25.0, 140.0, "brown")], axis=1)
    return A.finish_loop(_mix((wind, 1.0), (whistle, 0.28), (drips, 0.3), (rumble, 0.35)), drive=1.6)


def emitter_river(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(EMITTER_S)
    return A.finish_loop(A.water_layer(n, rng, bubbles_per_s=22.0))


def emitter_forge(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(EMITTER_S)
    return A.finish_loop(A.fire_layer(n, rng))


def spot(rng: np.random.Generator, kind: str) -> np.ndarray:
    """One spot by kind (see the module's list), finished: DC out, the silent tail trimmed, at most
    1.5 s, faded to zero at both ends."""
    makers = {
        "lark": A.lark, "cricket": A.cricket_burst, "gust": A.gust, "woodpecker": A.woodpecker, "owl": A.owl,
        "crow": A.crow, "creak_a": lambda r: A.tree_creak(r, 1.4, 1.0), "creak_b": lambda r: A.tree_creak(r, 1.2, 0.7),
        "howl": A.howl, "dog": A.dog, "hammer": A.hammer, "voice": A.far_voice, "cart": A.cart,
        "pebbles_a": lambda r: A.pebbles(r, 14), "pebbles_b": lambda r: A.pebbles(r, 8), "whistle": A.wind_whistle,
        "clank": A.clank, "birds_flush": A.birds_flush,
    }
    x = makers[kind](rng)
    return fx.finish(x, RATE, fade_in_s=0.004, fade_out_s=0.05, floor_db=-55.0, max_s=1.5)


SPOTS = ["lark", "cricket", "gust", "woodpecker", "owl", "crow", "creak_a", "creak_b", "howl", "dog", "hammer",
         "voice", "cart", "pebbles_a", "pebbles_b", "whistle", "clank", "birds_flush"]

# The build's pre-encoding budget estimate per cue (build_audio.estimate_bytes: KB of Ogg per second
# besides the 3.7 KB of headers), calibrated on the encoded files (rounded up to 0.01): with the
# measured import factor x1.11 the estimate stays within a few KB of the imported size.
EST_KBPS = {
    'bed_forest': 5.14, 'bed_meadow': 4.96, 'bed_stone': 4.13, 'bed_village': 3.81, 'forge_fire': 3.11,
    'river_loop': 3.87, 'spot_birds_flush': 3.38, 'spot_cart': 2.28, 'spot_clank': 1.57,
    'spot_creak_a': 1.69, 'spot_creak_b': 1.21, 'spot_cricket': 0.87, 'spot_crow': 1.16,
    'spot_dog': 1.79, 'spot_gust': 3.52, 'spot_hammer': 1.57, 'spot_howl': 1.2, 'spot_lark': 2.21,
    'spot_owl': 1.77, 'spot_pebbles_a': 3.79, 'spot_pebbles_b': 3.34, 'spot_voice': 1.34,
    'spot_whistle': 2.53, 'spot_woodpecker': 3.7,
}

CUES = []
for _i, (_name, _func) in enumerate((("bed_meadow", bed_meadow), ("bed_forest", bed_forest),
                                      ("bed_village", bed_village), ("bed_stone", bed_stone))):
    CUES.append({"name": _name, "path": _P + _name + ".ogg", "seed": 232001 + _i, "func": _func, "params": {},
                 "kind": "loop", "quality": 0, "rate": RATE, "norm": {"lufs": -18.0, "max_peak_db": -3.0},
                 "est_kbps": EST_KBPS.get(_name, 5.5)})
for _i, (_name, _func) in enumerate((("river_loop", emitter_river), ("forge_fire", emitter_forge))):
    CUES.append({"name": _name, "path": _P + _name + ".ogg", "seed": 232011 + _i, "func": _func, "params": {},
                 "kind": "loop", "quality": 0, "rate": RATE, "norm": {"lufs": -18.0, "max_peak_db": -3.0},
                 "est_kbps": EST_KBPS.get(_name, 3.5)})
for _i, _kind in enumerate(SPOTS):
    CUES.append({"name": "spot_" + _kind, "path": _P + "spot_" + _kind + ".ogg", "seed": 232101 + _i, "func": spot,
                 "params": {"kind": _kind}, "kind": "oneshot", "quality": 0, "rate": RATE,
                 "norm": {"peak_db": -3.0}, "est_kbps": EST_KBPS.get("spot_" + _kind, 3.5)})
