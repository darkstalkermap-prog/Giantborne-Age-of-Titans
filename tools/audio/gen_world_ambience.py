"""The Old Kingdom's ambience (P28; plan M6-M9 sections 4.2, 4.3 and 4.5): a bed for each region, a
bed for each of the main places, the spots that punctuate them, and positioned loops (the formation
march, the pond, the shore, the falls, the town well).

Region beds (20 s, stereo, seamless; synth/ambience.py's layers and a few of this module's):
    farmland   the Crownmarch: a light wind over the fields, crickets, the crops rustling
    deepwood   the Greywood: a low wind in the pines, the needles' hiss, a deep forest hum
    lake       the Drowned Steps: small waves lapping at stone, a wind over open water
    grassland  Aldmere: wind in long grass, crickets, war drums far off
    highland   the Stonehold: a high wind gusting and whistling through stone, a far rumble

Place beds (15 s, mono, for a place's audio region):
    town       Brannock and Millford: the murmur of a market, carts, a smithy's hammer
    camp       the war camp (and the toll-riders' camps): drums at practice, canvas, hammers
    hearth     Skarn (and Harrok's Hall): a great hearth fire and the deep voices of giants
    cave       the Troll Den: drips in the dark and a slow breath
    bones      the Titan's Bones: wind through the ribs, a low hum
    moot       the Moot: wind over the ring and a choir humming in the stones

Spots (mono one-shots, at most 1.5 s): cattle, a far bell, a troll's far grunt, a branch cracking,
wind in the pines, water birds, a gull, a horse, orders shouted, a flag snapping, an eagle, a giant's
horn far off, the stones' hum, a hawker, shutters, a saw, a giant's laugh, a log split, a whelp's
mewl and a bone rattle. (The banks alias some of them, and some of P23's, at another pitch.)

Loops (10 s, mono): the march of a formation (stomps in step, a field drum, armour), Hollowmere's
black pond (frogs, plops), the shore lapping, the Highland Falls, the town well.

Every sound is original and synthesized here. Seeds 281001-281299.
"""

from __future__ import annotations

import math

import numpy as np

from synth import ambience as A
from synth import core, fx
from synth import instruments as ins
from synth import music as M
from synth import voices as vo

FAMILY = "world_ambience"
RATE = core.DEFAULT_RATE
_P = "res://assets/audio/ambience/world/"
BED_S = 20.0
PLACE_BED_S = 15.0
LOOP_S = 10.0
TWO_PI = 2.0 * math.pi


def _mix(*layers) -> np.ndarray:
    """Sums (layer, gain) pairs, each first brought to unit RMS (P23's)."""
    out = None
    for layer, gain in layers:
        x = layer / max(core.rms(layer), 1e-9) * gain
        out = x if out is None else out + x
    return out


def _mono(x: np.ndarray) -> np.ndarray:
    return x.mean(axis=1) if x.ndim == 2 else x


# --------------------------------------------------------------------------- bed layers


def lapping_layer(n: int, rng: np.random.Generator, rate: int = RATE, spacing=(1.4, 3.2)) -> np.ndarray:
    """Small waves lapping at a stone edge: each a soft swell of low-passed noise, a slap and the
    trickle back, every few seconds, here and there (stereo, folded into one period)."""
    loop_s = n / rate
    events = []
    t = rng.uniform(0.2, 1.0)
    while t < loop_s:
        m = M.frames(rng.uniform(0.9, 1.6), rate)
        tt = fx.t_axis(m, rate)
        dur = m / rate
        swell = fx.noise(m, rng, 120.0, 1400.0, rate, "pink") * np.exp(-0.5 * ((tt - dur * 0.3) / (dur * 0.16)) ** 2)
        slap = fx.noise(m, rng, 600.0, 4000.0, rate) * fx.env_ad(m, rate, 0.004, 0.05)
        slap = np.roll(slap, M.frames(dur * 0.32, rate))
        trickle = fx.noise(m, rng, 1500.0, 6000.0, rate) * np.clip((tt - dur * 0.35) / (dur * 0.1), 0.0, 1.0) \
            * np.exp(-np.maximum(tt - dur * 0.4, 0.0) / (dur * 0.25))
        sig = swell / max(core.rms(swell), 1e-9) + 0.5 * slap / max(core.peak(slap), 1e-9) \
            + 0.25 * trickle / max(core.rms(trickle), 1e-9)
        events.append((t, fx.seal(sig, rate, 0.05), rng.uniform(-0.8, 0.8), rng.uniform(0.5, 1.0)))
        t += rng.uniform(*spacing)
    return A.events_loop(n, events, rate)


def far_drums_layer(n: int, rng: np.random.Generator, rate: int = RATE, bpm: float = 96.0,
                    cutoff: float = 320.0, steady: bool = False) -> np.ndarray:
    """War drums far off: taiko and frame-drum groups (DUM . DUM-DUM . DUM) low-passed by the
    distance, with gaps; `steady` for a camp's drummers practising a regular pattern."""
    loop_s = n / rate
    bs = 60.0 / bpm
    buf = np.zeros((n + M.frames(2.0, rate), 2))
    t = rng.uniform(0.0, 1.5)
    pan = rng.uniform(-0.4, 0.4)
    while t < loop_s:
        pattern = (0.0, 1.0, 1.5, 3.0) if steady else ((0.0, 1.0, 1.5, 3.0) if rng.random() < 0.6 else (0.0, 0.5, 2.0))
        for b in pattern:
            hit = M.taiko(rng, rng.uniform(0.6, 1.0), f0=rng.uniform(52.0, 62.0), rate=rate)
            core.mix_into(buf, M.frames(t + b * bs, rate), core.pan(hit, pan), 1.0)
        t += 4.0 * bs if steady else 4.0 * bs + rng.uniform(0.5, 3.0)
    out = core.loop_wrap(buf, n)
    return core.fft_filter(out, rate, core.band_response(35.0, cutoff, 2))


def canvas_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Tent canvas flapping in the wind: bursts of mid noise fluttering at 9-16 Hz now and then."""
    loop_s = n / rate
    events = []
    t = rng.uniform(0.3, 1.5)
    while t < loop_s:
        m = M.frames(rng.uniform(0.3, 0.8), rate)
        tt = fx.t_axis(m, rate)
        flutter = np.clip(np.sin(TWO_PI * rng.uniform(9.0, 16.0) * tt), 0.0, 1.0) ** 2
        sig = fx.noise(m, rng, 400.0, 3500.0, rate) * flutter * np.sin(np.pi * tt / tt[-1])
        events.append((t, sig, rng.uniform(-0.8, 0.8), rng.uniform(0.3, 0.8)))
        t += rng.uniform(0.8, 2.5)
    return A.events_loop(n, events, rate)


def hammers_layer(n: int, rng: np.random.Generator, rate: int = RATE, smiths: int = 2) -> np.ndarray:
    """Hammers on anvils and timbers about a camp: each smith striking at its own steady rate."""
    loop_s = n / rate
    events = []
    for _s in range(smiths):
        parts = ins.metal_partials(rng, rng.uniform(800.0, 1100.0), 4200.0, 6)
        pan = rng.uniform(-0.7, 0.7)
        period = rng.uniform(0.55, 0.85)
        t = rng.uniform(0.0, period)
        while t < loop_s:
            m = M.frames(0.4, rate)
            ring = ins.ring(rng, m, rate, parts * rng.uniform(0.99, 1.01), 0.06, 0.22)
            thud = ins.thump(m, rate, 210.0, 120.0, 0.01, 0.03)
            sig = A.far(ring / max(core.peak(ring), 1e-9) + 0.4 * thud, rng, 3500.0, rate)
            events.append((t, sig, pan, rng.uniform(0.2, 0.45)))
            t += period * (3.0 if rng.random() < 0.2 else 1.0)
    return A.events_loop(n, events, rate)


def giant_murmur_layer(n: int, rng: np.random.Generator, count: int = 26, rate: int = RATE) -> np.ndarray:
    """Giants talking low by the hearth: few, long, deep vocal grains (f0 60-110 Hz, a giant's
    tract), never a word."""
    loop_s = n / rate
    events = []
    for _k in range(count):
        f0 = rng.uniform(62.0, 105.0)
        seconds = rng.uniform(0.5, 1.2)
        v1, v2 = rng.choice(("a", "o", "uh", "u", "schwa"), 2)
        sig = vo.call(rng, seconds, [(0.0, f0 * rng.uniform(0.95, 1.12)), (seconds, f0 * rng.uniform(0.82, 1.0))],
                      [(0.0, str(v1)), (seconds, str(v2))], [(0.0, 0.0), (0.08, 1.0), (seconds * 0.7, 0.7), (seconds, 0.0)],
                      rate, tract=rng.uniform(0.6, 0.7), sub=0.2, growl_hz=32.0, growl=0.15)
        sig = fx.lowpass(sig, 1100.0, 2.0, rate)
        events.append((rng.uniform(0.0, loop_s), sig / max(core.peak(sig), 1e-9), rng.uniform(-0.6, 0.6),
                       rng.uniform(0.2, 0.45)))
    return A.events_loop(n, events, rate)


def breath_layer(n: int, rng: np.random.Generator, rate: int = RATE, period_s: float = 5.0) -> np.ndarray:
    """A slow breath in the dark (something large asleep): band-passed noise swelling in and out,
    a whole number of breaths per loop (seamless)."""
    loop_s = n / rate
    breaths = max(1, int(round(loop_s / period_s)))
    t = np.arange(n) / rate
    phase = (t * breaths / loop_s) % 1.0
    level = np.where(phase < 0.45, np.sin(np.pi * phase / 0.45) ** 2, 0.55 * np.sin(np.pi * (phase - 0.45) / 0.55) ** 2)
    x = A.loop_noise(n, rng, 70.0, 420.0, "pink", rate) * level
    return np.stack([x, x * 0.92], axis=1)


def hum_layer(n: int, rng: np.random.Generator, rate: int = RATE, f0: float = 55.0) -> np.ndarray:
    """A low hum (old bone, the stones): a few harmonics of f0 beating slowly, a whole number of
    beats per loop."""
    loop_s = n / rate
    t = np.arange(n) / rate
    out = np.zeros(n)
    for k, a in ((1, 1.0), (2, 0.5), (3, 0.3), (5, 0.12)):
        beat = round(rng.uniform(1.0, 4.0)) / loop_s
        out += a * np.sin(TWO_PI * (round(f0 * k * loop_s) / loop_s) * t) * (0.7 + 0.3 * np.sin(TWO_PI * beat * t))
    return np.stack([out, out], axis=1)


def choir_hum_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A choir humming within the Moot's stones: "mm" on D and A, swelling slowly (folded loop)."""
    loop_s = n / rate
    buf = np.zeros((n + M.frames(4.0, rate), 2))
    for start, midi, pan in ((0.0, 50, -0.3), (loop_s * 0.5, 57, 0.3), (loop_s * 0.25, 45, 0.0)):
        sig = M.choir(rng, M.hz(midi), loop_s * 0.7, 0.8, vowel="m", voices=5, attack_s=3.0, release_s=3.0,
                      detune_cents=10.0, breath=0.03, rate=rate)
        core.mix_into(buf, M.frames(start, rate), core.pan(sig, pan), 1.0)
    return core.loop_wrap(buf, n)


def carts_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Carts on a cobbled street now and then (P23's cart spot, quieter and farther)."""
    loop_s = n / rate
    events = []
    t = rng.uniform(1.0, 4.0)
    while t < loop_s:
        events.append((t, A.cart(rng, rate), rng.uniform(-0.7, 0.7), rng.uniform(0.3, 0.6)))
        t += rng.uniform(4.0, 8.0)
    return A.events_loop(n, events, rate)


# --------------------------------------------------------------------------- the beds


def bed_farmland(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=720.0, gust_hz=0.06, depth=0.45)
    insects = A.insects_layer(n, rng, count=3)
    crops = A.leaves_layer(n, rng)
    return A.finish_loop(_mix((wind, 1.0), (insects, 0.28), (crops, 0.16)), drive=1.6)


def bed_deepwood(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=300.0, gust_hz=0.04, depth=0.65)
    needles = np.stack([A.loop_noise(n, rng, 3000.0, 9000.0, "pink") * np.clip(0.6 + 0.4 * A.periodic_curve(n, rng, 0.2), 0.1, 1.5)
                        for _c in range(2)], axis=1)
    hum = np.stack([A.loop_noise(n, rng, 25.0, 90.0, "brown"), A.loop_noise(n, rng, 25.0, 90.0, "brown")], axis=1)
    drips = A.drips_layer(n, rng)
    return A.finish_loop(_mix((wind, 1.0), (needles, 0.12), (hum, 0.35), (drips, 0.08)), drive=1.6)


def bed_lake(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    lap = lapping_layer(n, rng)
    wind = A.wind_layer(n, rng, base_hz=620.0, gust_hz=0.05, depth=0.4)
    water = np.stack([A.loop_noise(n, rng, 200.0, 1800.0, "pink"), A.loop_noise(n, rng, 200.0, 1800.0, "pink")], axis=1)
    return A.finish_loop(_mix((lap, 0.9), (wind, 0.8), (water, 0.18)), drive=1.6)


def bed_grassland(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=820.0, gust_hz=0.07, depth=0.55)
    grass = A.leaves_layer(n, rng)
    drums = far_drums_layer(n, rng, cutoff=300.0)
    insects = A.insects_layer(n, rng, count=2)
    return A.finish_loop(_mix((wind, 1.0), (grass, 0.3), (drums, 0.3), (insects, 0.12)), drive=1.6)


def bed_highland(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(BED_S)
    wind = A.wind_layer(n, rng, base_hz=900.0, gust_hz=0.09, depth=0.8)
    whistle = A.whistle_layer(n, rng)
    rumble = np.stack([A.loop_noise(n, rng, 25.0, 120.0, "brown"), A.loop_noise(n, rng, 25.0, 120.0, "brown")], axis=1)
    return A.finish_loop(_mix((wind, 1.0), (whistle, 0.32), (rumble, 0.25)), drive=1.6)


def bed_town(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    murmur = A.murmur_layer(n, rng, count=60)
    carts = carts_layer(n, rng)
    smithy = hammers_layer(n, rng, smiths=1)
    wind = A.wind_layer(n, rng, base_hz=600.0, gust_hz=0.06, depth=0.3)
    return A.finish_loop(_mono(_mix((murmur, 0.8), (carts, 0.25), (smithy, 0.3), (wind, 0.4))), drive=1.6)


def bed_camp(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    drums = far_drums_layer(n, rng, bpm=100.0, cutoff=900.0, steady=True)
    canvas = canvas_layer(n, rng)
    hammers = hammers_layer(n, rng, smiths=2)
    murmur = A.murmur_layer(n, rng, count=30)
    return A.finish_loop(_mono(_mix((drums, 0.6), (canvas, 0.35), (hammers, 0.45), (murmur, 0.45))), drive=1.8)


def bed_hearth(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    fire = A.fire_layer(n, rng)
    voices = giant_murmur_layer(n, rng)
    wind = A.wind_layer(n, rng, base_hz=500.0, gust_hz=0.05, depth=0.4)
    return A.finish_loop(_mono(_mix((np.stack([fire, fire], axis=1), 0.9), (voices, 0.7), (wind, 0.35))), drive=1.6)


def bed_cave(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    drips = A.drips_layer(n, rng)
    breath = breath_layer(n, rng)
    air = np.stack([A.loop_noise(n, rng, 40.0, 300.0, "brown"), A.loop_noise(n, rng, 40.0, 300.0, "brown")], axis=1)
    return A.finish_loop(_mono(_mix((drips, 0.6), (breath, 0.7), (air, 0.4))), drive=1.6)


def bed_bones(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    wind = A.wind_layer(n, rng, base_hz=520.0, gust_hz=0.06, depth=0.6)
    ribs = A.whistle_layer(n, rng)
    hum = hum_layer(n, rng, f0=49.0)
    return A.finish_loop(_mono(_mix((wind, 0.9), (ribs, 0.5), (hum, 0.3))), drive=1.6)


def bed_moot(rng: np.random.Generator) -> np.ndarray:
    n = M.frames(PLACE_BED_S)
    wind = A.wind_layer(n, rng, base_hz=760.0, gust_hz=0.07, depth=0.6)
    choir = choir_hum_layer(n, rng)
    return A.finish_loop(_mono(_mix((wind, 1.0), (choir, 0.38))), drive=1.6)


# --------------------------------------------------------------------------- loops (emitters)


def march_loop(rng: np.random.Generator) -> np.ndarray:
    """A formation on the march, heard from beside it: a dozen boots coming down together on every
    beat (120 steps a minute, left and right), a field drum tapping the step and rolling every
    eighth, armour and pikes rattling - twenty steps in exactly ten seconds, so it loops."""
    n = M.frames(LOOP_S)
    buf = np.zeros(n + M.frames(1.0))
    step_s = LOOP_S / 20.0
    for k in range(20):
        at = k * step_s
        for _m in range(12):
            st = ins.human_step(rng, "hard" if rng.random() < 0.3 else "soft")
            M.place(buf, at + rng.uniform(-0.018, 0.018), st, rng.uniform(0.5, 1.0) * (1.0 if k % 2 == 0 else 0.85))
        thud = ins.thump(M.frames(0.2), RATE, 95.0, 60.0, 0.02, 0.05)
        M.place(buf, at, thud, 0.8)
        if k % 2 == 0:
            M.place(buf, at + step_s * 0.5, _drum_tap(rng, 0.5), 0.7)
        M.place(buf, at, _drum_tap(rng, 0.9 if k % 8 == 0 else 0.65), 0.8)
        for _c in range(3):
            m = M.frames(0.1)
            clink = ins.ring(rng, m, RATE, ins.metal_partials(rng, 2000.0, 6000.0, 4), 0.01, 0.04)
            M.place(buf, at + rng.uniform(0.02, 0.25), clink / max(core.peak(clink), 1e-9), rng.uniform(0.05, 0.15))
    x = core.loop_wrap(buf, n)
    x = core.fft_filter(x, RATE, core.band_response(40.0, 7000.0, 2))
    return A.finish_loop(fx.soft_clip(x / max(core.peak(x), 1e-9), 1.4))


def _drum_tap(rng: np.random.Generator, vel: float) -> np.ndarray:
    m = M.frames(0.18)
    t = fx.t_axis(m)
    shell = np.sin(TWO_PI * np.cumsum(190.0 * (1.0 + 0.2 * np.exp(-t / 0.01)) * np.ones(m)) / RATE) * np.exp(-t / 0.03)
    rattle = fx.noise(m, rng, 2500.0, 8000.0) * fx.env_ad(m, RATE, 0.002, 0.05)
    return (0.6 * shell + 0.7 * rattle) * vel


def pond_loop(rng: np.random.Generator) -> np.ndarray:
    """Hollowmere's black pond: still water with a few plops, and frogs croaking in turn (short
    pulsed croaks, each frog at its own pitch and pace)."""
    n = M.frames(LOOP_S)
    buf = np.zeros(n + M.frames(1.0))
    for _f in range(3):
        f0 = rng.uniform(180.0, 320.0)
        period = rng.uniform(1.6, 3.2)
        t = rng.uniform(0.0, period)
        while t < LOOP_S:
            pulses = int(rng.integers(3, 7))
            m = M.frames(pulses / 22.0 + 0.05)
            tt = fx.t_axis(m)
            gate = np.clip(np.sin(np.pi * (tt * 22.0 % 1.0)), 0.0, 1.0) ** 3 * (tt < pulses / 22.0)
            croak = vo.call(rng, m / RATE, [(0.0, f0), (m / RATE, f0 * 0.9)], [(0.0, "o"), (m / RATE, "u")],
                            [(0.0, 0.0), (0.01, 1.0), (m / RATE, 0.0)], RATE, tract=0.55, jitter=0.03, shimmer=0.2)
            M.place(buf, t, croak * gate / max(core.peak(croak), 1e-9), rng.uniform(0.3, 0.7))
            t += period * rng.uniform(0.8, 1.2)
    t = rng.uniform(0.0, 1.0)
    while t < LOOP_S:
        m = M.frames(0.12)
        tt = fx.t_axis(m)
        plop = core.sine(rng.uniform(500.0, 900.0) * (1.0 + 1.5 * tt / tt[-1]), m) * np.sin(np.pi * tt / tt[-1]) ** 2
        M.place(buf, t, plop, rng.uniform(0.15, 0.35))
        t += rng.uniform(0.8, 2.5)
    still = A.loop_noise(n, rng, 150.0, 900.0, "pink") * 0.05
    x = core.loop_wrap(buf, n) + still
    return A.finish_loop(x)


def shore_loop(rng: np.random.Generator) -> np.ndarray:
    """Waves lapping at the Mere's stone shore (lapping_layer, a little bigger), mono."""
    n = M.frames(LOOP_S)
    x = _mono(lapping_layer(n, rng, spacing=(1.2, 2.4)))
    return A.finish_loop(x)


def falls_loop(rng: np.random.Generator) -> np.ndarray:
    """The Highland Falls: a deep roar of falling water, the spray's hiss and a churn of grains."""
    n = M.frames(LOOP_S)
    roar = A.loop_noise(n, rng, 40.0, 900.0, "brown") * np.clip(1.0 + 0.12 * A.periodic_curve(n, rng, 0.5), 0.6, 1.4)
    spray = A.loop_noise(n, rng, 1500.0, 8000.0, "pink") * np.clip(1.0 + 0.2 * A.periodic_curve(n, rng, 1.2), 0.4, 1.6)
    churn = A.water_layer(n, rng, bubbles_per_s=40.0)
    return A.finish_loop(_mix((roar, 1.0), (spray, 0.45), (churn, 0.4)), drive=1.4)


def well_loop(rng: np.random.Generator) -> np.ndarray:
    """The town well: drops falling into the shaft with its echo, the bucket's chain clinking now
    and then, a soft creak of the windlass."""
    n = M.frames(LOOP_S)
    buf = np.zeros(n + M.frames(2.0))
    t = rng.uniform(0.1, 0.6)
    while t < LOOP_S:
        d = A.drip(rng)
        echo = np.zeros(d.shape[0] + M.frames(0.6))
        echo[:d.shape[0]] += d
        for k, g in ((0.11, 0.4), (0.23, 0.2), (0.37, 0.1)):
            core.mix_into(echo, M.frames(k), d, g)
        M.place(buf, t, echo, rng.uniform(0.4, 0.8))
        t += rng.uniform(0.5, 1.6)
    for at in (rng.uniform(1.0, 3.0), rng.uniform(5.5, 8.0)):
        for k in range(int(rng.integers(3, 6))):
            m = M.frames(0.12)
            clink = ins.ring(rng, m, RATE, ins.metal_partials(rng, 1500.0, 5000.0, 4), 0.012, 0.05)
            M.place(buf, at + 0.09 * k + rng.uniform(0.0, 0.03), clink / max(core.peak(clink), 1e-9), 0.25)
    creak = ins.creak(rng, 1.4, [(0.0, 7.0), (0.7, 11.0), (1.4, 6.0)])
    M.place(buf, rng.uniform(3.0, 5.0), creak[:M.frames(1.4)] / max(core.peak(creak), 1e-9), 0.18)
    x = core.loop_wrap(buf, n) + A.loop_noise(n, rng, 100.0, 600.0, "brown") * 0.02
    return A.finish_loop(x)


# --------------------------------------------------------------------------- spots


def cattle(rng):
    """A cow lowing across the fields."""
    s = 1.25
    f0 = rng.uniform(105.0, 125.0)
    x = vo.call(rng, s, [(0.0, f0 * 0.9), (0.25, f0 * 1.1), (s, f0 * 0.82)], [(0.0, "m"), (0.2, "u"), (0.8, "o"), (s, "u")],
                [(0.0, 0.0), (0.2, 1.0), (0.9, 0.8), (s, 0.0)], RATE, tract=0.78, breath=0.15, sub=0.1, jitter=0.02)
    return A.far(x / max(core.peak(x), 1e-9), rng, 1800.0)


def far_bell(rng):
    """A bell rung twice from a tower far off (no church: a village's alarm and hour bell)."""
    n = M.frames(1.5)
    out = np.zeros(n)
    f0 = rng.uniform(400.0, 460.0)
    for at in (0.02, 0.72):
        b = ins.bell(rng, n, RATE, f0, 1.4, strike=0.2)
        core.mix_into(out, M.frames(at), b / max(core.peak(b), 1e-9), 1.0 if at < 0.1 else 0.85)
    return A.far(out, rng, 2600.0)


def troll_far(rng):
    """A troll's grunt from deep in the wood."""
    s = 1.1
    x = vo.call(rng, s, [(0.0, 72.0), (0.2, 84.0), (s, 56.0)], [(0.0, "uh"), (0.3, "o"), (s, "u")],
                [(0.0, 0.0), (0.08, 1.0), (0.6, 0.7), (s, 0.0)], RATE, tract=0.66, breath=0.2, sub=0.35,
                growl_hz=33.0, growl=0.45, drive=2.0)
    return A.far(x / max(core.peak(x), 1e-9), rng, 1100.0)


def branch_crack(rng):
    """A dead branch cracking and falling through the trees."""
    n = M.frames(1.3)
    crack = ins.impact_wood(rng, 0.3, 0.6)
    out = np.zeros(n)
    core.mix_into(out, 0, crack / max(core.peak(crack), 1e-9))
    out += 0.6 * ins.splinter(rng, n, RATE, 0.0, 0.25, 260.0) / 1.0
    rustle = A.leaves_layer(n, rng)[:, 0] * fx.env_points([(0.0, 0.0), (0.2, 1.0), (1.2, 0.0)], n)
    out += 0.15 * rustle / max(core.peak(rustle), 1e-9)
    for k, at in enumerate((0.6, 0.85, 1.0)):
        thud = ins.impact_wood(rng, 0.15, 0.2)
        core.mix_into(out, M.frames(at), thud / max(core.peak(thud), 1e-9), 0.4 - 0.1 * k)
    return A.far(out, rng, 3500.0)


def pine_wind(rng):
    """A gust in the pines: a hiss through the needles over a low whoosh."""
    s = 1.5
    n = M.frames(s)
    hiss = fx.swept_band(fx.noise(n, rng, 0.0, 0.0, RATE, "pink"), [(0.0, 2500.0), (s * 0.5, 5500.0), (s, 3000.0)],
                         [(0.0, 1.0), (s, 1.0)], RATE)
    low = fx.swept_band(fx.noise(n, rng, 0.0, 0.0, RATE, "pink"), [(0.0, 250.0), (s * 0.5, 700.0), (s, 300.0)],
                        [(0.0, 1.2), (s, 1.2)], RATE)
    env = fx.env_points([(0.0, 0.0), (s * 0.5, 1.0), (s, 0.0)], n)
    return (0.6 * hiss / max(core.peak(hiss), 1e-9) + low / max(core.peak(low), 1e-9)) * env


def water_birds(rng):
    """Water birds on the Mere: a few nasal calls, near and far."""
    n = M.frames(1.4)
    out = np.zeros(n)
    t = 0.03
    for _k in range(int(rng.integers(3, 6))):
        s = rng.uniform(0.09, 0.16)
        f0 = rng.uniform(550.0, 820.0)
        q = vo.call(rng, s, [(0.0, f0 * 1.1), (s, f0 * 0.85)], [(0.0, "ae"), (s, "a")], [(0.0, 0.0), (0.01, 1.0), (s, 0.0)],
                    RATE, tract=0.45, jitter=0.05, shimmer=0.3, breath=0.25)
        core.mix_into(out, M.frames(t), q / max(core.peak(q), 1e-9), rng.uniform(0.5, 1.0))
        t += rng.uniform(0.12, 0.3)
        if t > 1.2:
            break
    return A.far(out, rng, 4500.0)


def gull(rng):
    """A gull's cry over the lake: a falling "kee-ow", twice."""
    n = M.frames(1.5)
    out = np.zeros(n)
    for k, at in enumerate((0.03, 0.62)):
        s = 0.45
        q = vo.call(rng, s, [(0.0, 1300.0), (0.08, 1650.0), (s, 900.0)], [(0.0, "i"), (0.1, "ae"), (s, "e")],
                    [(0.0, 0.0), (0.03, 1.0), (0.3, 0.8), (s, 0.0)], RATE, tract=0.4, jitter=0.03, shimmer=0.15,
                    breath=0.15)
        core.mix_into(out, M.frames(at), q / max(core.peak(q), 1e-9), 1.0 - 0.25 * k)
    return A.far(out, rng, 6000.0)


def horse(rng):
    """A horse snorting and whinnying at its picket."""
    n = M.frames(1.5)
    out = np.zeros(n)
    m = M.frames(0.35)
    snort = fx.noise(m, rng, 300.0, 2200.0) * fx.env_ad(m, RATE, 0.01, 0.08) * (1.0 + 0.5 * np.sin(TWO_PI * 38.0 * fx.t_axis(m)))
    core.mix_into(out, 0, snort / max(core.peak(snort), 1e-9), 0.6)
    s = 1.0
    neigh = vo.call(rng, s, [(0.0, 420.0), (0.15, 720.0), (0.6, 560.0), (s, 330.0)], [(0.0, "i"), (0.3, "ae"), (s, "a")],
                    [(0.0, 0.0), (0.05, 1.0), (0.6, 0.7), (s, 0.0)], RATE, tract=0.85, jitter=0.02, shimmer=0.25,
                    vibrato_hz=18.0, vibrato=0.06, breath=0.2)
    core.mix_into(out, M.frames(0.4), neigh / max(core.peak(neigh), 1e-9), 1.0)
    return A.far(out, rng, 3500.0)


def orders(rng):
    """An order shouted across a camp: two barked syllables."""
    n = M.frames(1.2)
    out = np.zeros(n)
    for k, (at, s, f0, v) in enumerate(((0.03, 0.22, 175.0, "a"), (0.32, 0.5, 205.0, "o"))):
        q = vo.call(rng, s, [(0.0, f0), (0.05, f0 * 1.15), (s, f0 * 0.9)], [(0.0, v), (s, v)],
                    [(0.0, 0.0), (0.02, 1.0), (s * 0.7, 0.8), (s, 0.0)], RATE, tract=1.0, drive=1.6, breath=0.1)
        core.mix_into(out, M.frames(at), q / max(core.peak(q), 1e-9), 1.0)
    return A.far(out, rng, 2200.0)


def flag_snap(rng):
    """A banner snapping in the wind: three or four sharp cloth cracks and their flutter."""
    n = M.frames(1.3)
    out = np.zeros(n)
    t = 0.02
    for _k in range(int(rng.integers(3, 5))):
        m = M.frames(rng.uniform(0.12, 0.25))
        tt = fx.t_axis(m)
        crack = fx.noise(m, rng, 600.0, 6000.0) * fx.env_ad(m, RATE, 0.001, 0.02)
        flutter = fx.noise(m, rng, 300.0, 3000.0) * np.clip(np.sin(TWO_PI * 24.0 * tt), 0.0, 1.0) ** 2 * np.exp(-tt / 0.08)
        core.mix_into(out, M.frames(t), crack + 0.5 * flutter, rng.uniform(0.6, 1.0))
        t += rng.uniform(0.18, 0.35)
    return A.far(out, rng, 6000.0)


def eagle(rng):
    """An eagle screaming high over the highlands."""
    s = 1.0
    x = vo.call(rng, s, [(0.0, 2100.0), (0.1, 2600.0), (0.7, 2200.0), (s, 1700.0)], [(0.0, "i"), (0.4, "e"), (s, "ae")],
                [(0.0, 0.0), (0.04, 1.0), (0.6, 0.8), (s, 0.0)], RATE, tract=0.35, jitter=0.04, shimmer=0.3,
                vibrato_hz=24.0, vibrato=0.03, breath=0.2)
    return A.far(x / max(core.peak(x), 1e-9), rng, 7000.0)


def giant_horn_far(rng):
    """A giant's horn blown far across the highlands: a long low call rising a fourth."""
    n = M.frames(1.5)
    out = np.zeros(n)
    a = M.horn(rng, M.hz(45), 0.55, 0.9, bright=0.5, attack_s=0.18, release_s=0.3, scoop=0.04)
    b = M.horn(rng, M.hz(50), 0.6, 0.9, bright=0.5, attack_s=0.15, release_s=0.35, scoop=0.03)
    core.mix_into(out, 0, a / max(core.peak(a), 1e-9))
    core.mix_into(out, M.frames(0.6), b / max(core.peak(b), 1e-9))
    out += fx.noise(n, rng, 150.0, 1200.0, RATE, "pink") * 0.06 * fx.env_points([(0.0, 0.0), (0.2, 1.0), (1.2, 1.0), (1.5, 0.0)], n)
    return A.far(fx.valley_echo(out, rng, RATE, 0.45, 0.3, 700.0, 2)[:n], rng, 1200.0)


def stone_hum(rng):
    """The standing stones humming: a low chord swelling up and dying away."""
    s = 1.5
    n = M.frames(s)
    t = fx.t_axis(n)
    f0 = rng.uniform(52.0, 58.0)
    x = np.zeros(n)
    for k, a in ((1, 1.0), (2, 0.6), (3, 0.35), (4.02, 0.2), (6.03, 0.1)):
        x += a * np.sin(TWO_PI * f0 * k * t + rng.uniform(0, TWO_PI)) * (1.0 + 0.2 * np.sin(TWO_PI * rng.uniform(0.8, 2.0) * t))
    x += fx.noise(n, rng, 100.0, 600.0) * 0.15
    return x * fx.env_points([(0.0, 0.0), (0.6, 1.0), (1.0, 0.8), (s, 0.0)], n)


def hawker(rng):
    """A market hawker's sing-song cry (no words)."""
    s = 1.2
    f0 = rng.uniform(180.0, 215.0)
    x = vo.call(rng, s, [(0.0, f0), (0.3, f0 * 1.33), (0.6, f0 * 1.33), (0.75, f0 * 1.12), (s, f0 * 0.9)],
                [(0.0, "e"), (0.3, "o"), (0.6, "a"), (0.8, "o"), (s, "o")],
                [(0.0, 0.0), (0.05, 1.0), (0.55, 0.9), (0.62, 0.4), (0.7, 0.9), (s, 0.0)], RATE, tract=1.02,
                breath=0.08)
    return A.far(x / max(core.peak(x), 1e-9), rng, 2600.0)


def shutters(rng):
    """Wooden shutters swinging to: two knocks and a creak."""
    n = M.frames(1.2)
    out = np.zeros(n)
    cr = ins.creak(rng, 0.5, [(0.0, 14.0), (0.5, 22.0)])
    core.mix_into(out, 0, cr[:M.frames(0.5)] / max(core.peak(cr), 1e-9), 0.4)
    for at, g in ((0.5, 1.0), (0.68, 0.6)):
        k = ins.impact_wood(rng, 0.25, 0.3)
        core.mix_into(out, M.frames(at), k / max(core.peak(k), 1e-9), g)
    return A.far(out, rng, 4000.0)


def saw(rng):
    """A two-man saw in a log: four strokes back and forth."""
    n = M.frames(1.45)
    out = np.zeros(n)
    stroke_s = 0.34
    for k in range(4):
        m = M.frames(stroke_s)
        f = fx.noise(m, rng, 0.0, 0.0, RATE, "white")
        c0, c1 = (1800.0, 2600.0) if k % 2 == 0 else (2600.0, 1900.0)
        y = fx.swept_band(f, [(0.0, c0), (stroke_s, c1)], [(0.0, 5.0), (stroke_s, 5.0)], RATE)
        teeth = 1.0 + 0.6 * np.sin(TWO_PI * 70.0 * fx.t_axis(m)) ** 2
        y = y * teeth * np.sin(np.pi * fx.t_axis(m) / stroke_s) ** 0.7
        core.mix_into(out, M.frames(0.02 + k * stroke_s), y / max(core.peak(y), 1e-9))
    return A.far(out, rng, 6000.0)


def giant_laugh(rng):
    """A giant laughing by the fire: three deep "ho"s."""
    n = M.frames(1.4)
    out = np.zeros(n)
    for k in range(3):
        s = 0.28
        f0 = 82.0 - 4.0 * k
        h = vo.call(rng, s, [(0.0, f0 * 1.1), (s, f0 * 0.9)], [(0.0, "o"), (s, "uh")],
                    [(0.0, 0.0), (0.03, 1.0), (s * 0.6, 0.6), (s, 0.0)], RATE, tract=0.64, breath=0.25, sub=0.25,
                    growl_hz=31.0, growl=0.2)
        core.mix_into(out, M.frames(0.03 + 0.33 * k), h / max(core.peak(h), 1e-9), 1.0 - 0.15 * k)
    return fx.reflections(out, rng, RATE, 6, 0.08, 0.3, 2500.0)[:n]


def log_split(rng):
    """An axe splitting a log: a deep thunk and the wood cracking apart."""
    n = M.frames(1.0)
    out = np.zeros(n)
    t = ins.impact_wood(rng, 0.4, 1.0)
    core.mix_into(out, 0, t / max(core.peak(t), 1e-9))
    core.mix_into(out, M.frames(0.06), ins.splinter(rng, M.frames(0.5), RATE, 0.0, 0.2, 300.0), 0.5)
    for at in (0.25, 0.4):
        k = ins.impact_wood(rng, 0.15, 0.1)
        core.mix_into(out, M.frames(at), k / max(core.peak(k), 1e-9), 0.35)
    return fx.reflections(out, rng, RATE, 5, 0.06, 0.25, 3000.0)[:n]


def whelp(rng):
    """A troll whelp mewling in the den: a squealing, rough little cry."""
    s = 0.9
    x = vo.call(rng, s, [(0.0, 300.0), (0.25, 520.0), (s, 380.0)], [(0.0, "ae"), (0.4, "i"), (s, "e")],
                [(0.0, 0.0), (0.05, 1.0), (0.6, 0.7), (s, 0.0)], RATE, tract=0.8, jitter=0.05, shimmer=0.3,
                breath=0.2, vibrato_hz=9.0, vibrato=0.05)
    return fx.reflections(x / max(core.peak(x), 1e-9), rng, RATE, 8, 0.12, 0.4, 2000.0)


def bone_rattle(rng):
    """Old bones knocking together: hollow dry clicks in a tumbling cluster."""
    n = M.frames(1.0)
    out = np.zeros(n)
    t = 0.02
    for k in range(int(rng.integers(8, 14))):
        m = M.frames(0.05)
        f = rng.uniform(600.0, 1500.0)
        click = fx.modal_ir([f, f * 2.4, f * 3.7], [0.008, 0.004, 0.002], [1.0, 0.5, 0.25], m, RATE)
        core.mix_into(out, M.frames(t), click / max(core.peak(click), 1e-9), rng.uniform(0.3, 1.0) * (1.0 - 0.04 * k))
        t += rng.uniform(0.02, 0.09)
    return fx.reflections(out, rng, RATE, 8, 0.1, 0.35, 3000.0)[:n]


SPOT_MAKERS = {"cattle": cattle, "far_bell": far_bell, "troll_far": troll_far, "branch_crack": branch_crack,
               "pine_wind": pine_wind, "water_birds": water_birds, "gull": gull, "horse": horse, "orders": orders,
               "flag_snap": flag_snap, "eagle": eagle, "giant_horn_far": giant_horn_far, "stone_hum": stone_hum,
               "hawker": hawker, "shutters": shutters, "saw": saw, "giant_laugh": giant_laugh, "log_split": log_split,
               "whelp": whelp, "bone_rattle": bone_rattle}
SPOTS = list(SPOT_MAKERS)


def spot(rng: np.random.Generator, kind: str) -> np.ndarray:
    """One spot by kind, finished like P23's: DC out, the silent tail trimmed, at most 1.5 s,
    faded to zero at both ends."""
    x = SPOT_MAKERS[kind](rng)
    return fx.finish(x, RATE, fade_in_s=0.004, fade_out_s=0.05, floor_db=-55.0, max_s=1.5)


# --------------------------------------------------------------------------- the build list

EST_KBPS = {}

CUES = []
for _i, (_name, _func) in enumerate((("bed_farmland", bed_farmland), ("bed_deepwood", bed_deepwood),
                                      ("bed_lake", bed_lake), ("bed_grassland", bed_grassland),
                                      ("bed_highland", bed_highland))):
    CUES.append({"name": _name, "path": _P + _name + ".ogg", "seed": 281001 + _i, "func": _func, "params": {},
                 "kind": "loop", "scope": "world", "quality": 0, "rate": RATE,
                 "norm": {"lufs": -18.0, "max_peak_db": -3.0}, "est_kbps": EST_KBPS.get(_name, 5.5)})
for _i, (_name, _func) in enumerate((("bed_town", bed_town), ("bed_camp", bed_camp), ("bed_hearth", bed_hearth),
                                      ("bed_cave", bed_cave), ("bed_bones", bed_bones), ("bed_moot", bed_moot))):
    CUES.append({"name": _name, "path": _P + _name + ".ogg", "seed": 281011 + _i, "func": _func, "params": {},
                 "kind": "loop", "scope": "world", "quality": 0, "rate": RATE,
                 "norm": {"lufs": -18.0, "max_peak_db": -3.0}, "est_kbps": EST_KBPS.get(_name, 3.2)})
for _i, (_name, _func) in enumerate((("march_loop", march_loop), ("pond_loop", pond_loop), ("shore_loop", shore_loop),
                                      ("falls_loop", falls_loop), ("well_loop", well_loop))):
    CUES.append({"name": _name, "path": _P + _name + ".ogg", "seed": 281021 + _i, "func": _func, "params": {},
                 "kind": "loop", "scope": "world", "quality": 0, "rate": RATE,
                 "norm": {"lufs": -18.0, "max_peak_db": -3.0}, "est_kbps": EST_KBPS.get(_name, 3.5)})
for _i, _kind in enumerate(SPOTS):
    CUES.append({"name": "spot_" + _kind, "path": _P + "spot_" + _kind + ".ogg", "seed": 281101 + _i, "func": spot,
                 "params": {"kind": _kind}, "kind": "oneshot", "scope": "world", "quality": 0, "rate": RATE,
                 "norm": {"peak_db": -3.0}, "est_kbps": EST_KBPS.get("spot_" + _kind, 3.5)})
