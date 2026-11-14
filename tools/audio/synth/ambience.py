"""The Valley's ambience synthesis (P23; plan M6-M9 sections 4.2 and 4.3): beds, spots and emitter
loops (numpy, float64, single-threaded, every random draw from the cue's own generator).

Beds are stereo loops made seamless by construction: their noise is shaped in the frequency
domain over exactly one period (circular), their slow motions are periodic curves (circularly
low-passed noise, or sines with a whole number of cycles per loop), and their events (cricket
chirps, drips, clucks, far voices) are placed in a buffer with room for tails and folded onto the
head (core.loop_wrap). The two channels share the motion and differ in their noise and in where
their events sit (equal-power panning), so the bed is wide without phasing.

* wind: brown and pink noise through a low-pass whose corner and level breathe in slow gusts
* insects: trains of narrow-band chirps (a carrier gated by a fast pulse train), several insects
  at their own pitch, rate and place
* leaves: high-passed noise whose level rustles in waves
* murmur: many far vocal grains (synth.voices) under a low-pass, never words
* water: filtered noise and bubbling grains (short rising sine chirps)
* drips and stone: sparse plinks with a falling pitch and their echo, cold whistling resonances

Spots are mono one-shots of at most 1.5 s (birds, an owl, a crow, creaks, a far howl, a dog, a
hammer, a far call, a cart, pebbles, a whistle, a clank, birds taking flight); emitters are mono
10 s loops (the river by the King's Bridge, the Giantforge's fire).
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx, instruments, voices
from synth import music as M

RATE = core.DEFAULT_RATE
TWO_PI = 2.0 * math.pi


# --------------------------------------------------------------------------- loop helpers


def periodic_curve(n: int, rng: np.random.Generator, hz: float, rate: int = RATE) -> np.ndarray:
    """A smooth random curve that is exactly periodic over n frames (white noise low-passed
    circularly near `hz`), unit RMS, zero mean."""
    w = core.fft_filter(rng.standard_normal(n), rate, core.band_response(0.0, hz, 2))
    w -= w.mean()
    r = core.rms(w)
    return w / r if r > 0 else w


def loop_noise(n: int, rng: np.random.Generator, lo: float, hi: float, color: str = "white",
               rate: int = RATE) -> np.ndarray:
    """Circular band-limited noise of exactly n frames, unit RMS."""
    if color == "pink":
        x = core.pink(n, rng)
    elif color == "brown":
        x = core.brown(n, rng)
    else:
        x = core.white(n, rng)
    x = core.fft_filter(x, rate, core.band_response(lo, hi, 2))
    r = core.rms(x)
    return x / r if r > 0 else x


def moving_band(x: np.ndarray, centre_fn, width_oct: float, rate: int = RATE) -> np.ndarray:
    """A loop through a band-pass whose centre follows centre_fn(times) (Hz), circularly (the
    STFT runs on the loop tiled three times)."""
    def gains(f, t):
        c = centre_fn(t)
        d = np.log2(np.maximum(f[None, :], 1.0) / c[:, None]) / max(width_oct, 1e-3)
        return np.exp(-0.5 * d * d)
    return M.tile_shape(x, gains, rate)


def moving_lowpass(x: np.ndarray, cutoff_fn, rate: int = RATE, order: float = 2.0) -> np.ndarray:
    def gains(f, t):
        c = cutoff_fn(t)
        return 1.0 / np.sqrt(1.0 + (f[None, :] / c[:, None]) ** (2.0 * order))
    return M.tile_shape(x, gains, rate)


def events_loop(n: int, events, rate: int = RATE, tail_s: float = 3.0) -> np.ndarray:
    """Stereo (n, 2): events = [(time_s, mono signal, pan, gain)], folded into one period."""
    buf = np.zeros((n + M.frames(tail_s, rate), 2))
    for at, sig, pan, gain in events:
        st = core.pan(sig, pan) * gain
        core.mix_into(buf, M.frames(at % (n / rate), rate), st)
    return core.loop_wrap(buf, n)


def decorrelated(n: int, rng: np.random.Generator, make) -> np.ndarray:
    """Two channels of the same texture with independent noise: make(rng) -> mono (n,)."""
    return np.stack([make(rng), make(rng)], axis=1)


def stereo_curve(curve: np.ndarray) -> np.ndarray:
    return np.stack([curve, curve], axis=1)


# --------------------------------------------------------------------------- bed layers


def wind_layer(n: int, rng: np.random.Generator, base_hz: float = 700.0, gust_hz: float = 0.08,
               depth: float = 0.55, rate: int = RATE) -> np.ndarray:
    """Stereo wind: brown and pink noise through a low-pass that opens in the gusts, its level
    following the same slow periodic curve."""
    t = np.arange(n) / rate
    gust = periodic_curve(n, rng, gust_hz, rate)
    level = np.clip(1.0 + depth * gust, 0.2, 2.2)

    def chan(r):
        return 0.8 * loop_noise(n, r, 30.0, 0.0, "brown", rate) + 0.35 * loop_noise(n, r, 60.0, 0.0, "pink", rate)
    st = decorrelated(n, rng, chan)
    loop_s = n / rate
    curve_t = np.interp(t, t, gust)

    def cutoff(times):
        return base_hz * 2.0 ** (0.9 * np.interp(np.mod(times, loop_s), t, curve_t))
    out = np.stack([moving_lowpass(st[:, c], cutoff, rate) for c in range(2)], axis=1)
    return out * stereo_curve(level)


def chirp_train(rng: np.random.Generator, carrier: float, pulses: int, pulse_hz: float, rate: int = RATE,
                bright: float = 0.3) -> np.ndarray:
    """One insect chirp: a narrow-band carrier gated by `pulses` fast pulses."""
    dur = pulses / pulse_hz + 0.02
    n = M.frames(dur, rate)
    t = fx.t_axis(n, rate)
    gate = np.clip(np.sin(math.pi * (t * pulse_hz % 1.0)) ** 2, 0.0, 1.0) * (t < pulses / pulse_hz)
    tone = core.sine(carrier * (1.0 + 0.01 * np.sin(TWO_PI * 7.0 * t)), n, rate) + bright * core.sine(carrier * 2.0, n, rate)
    return fx.seal(tone * gate, rate, 0.005)


def insects_layer(n: int, rng: np.random.Generator, count: int = 4, rate: int = RATE) -> np.ndarray:
    """Several crickets, each with its own pitch (3.6-5.2 kHz), chirp rhythm and place; each
    one pauses now and then (a periodic on/off curve) so the bed never drones."""
    loop_s = n / rate
    events = []
    for _k in range(count):
        carrier = rng.uniform(3600.0, 5200.0)
        period = rng.uniform(0.45, 1.1)
        pulses = int(rng.integers(2, 5))
        pulse_hz = rng.uniform(22.0, 34.0)
        pan = rng.uniform(-0.8, 0.8)
        gain = rng.uniform(0.25, 0.55)
        on_curve = periodic_curve(n, rng, 0.1, rate)
        t = rng.uniform(0.0, period)
        while t < loop_s:
            idx = min(n - 1, int(t * rate))
            if on_curve[idx] > -0.35:
                sig = chirp_train(rng, carrier * rng.uniform(0.995, 1.005), pulses, pulse_hz, rate)
                events.append((t, sig, pan, gain * rng.uniform(0.8, 1.0)))
            t += period * rng.uniform(0.92, 1.08)
    return events_loop(n, events, rate)


def leaves_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Leaves rustling: high-passed noise whose level moves in waves of a few seconds, the two
    sides a little out of step."""
    def chan(r):
        x = loop_noise(n, r, 1800.0, 8500.0, "pink", rate)
        lvl = np.clip(0.55 + 0.45 * periodic_curve(n, r, 0.35, rate), 0.05, 1.6) ** 1.5
        return x * lvl
    return decorrelated(n, rng, chan)


def murmur_layer(n: int, rng: np.random.Generator, count: int = 70, rate: int = RATE) -> np.ndarray:
    """A village heard from its edge: many short far vocal calls (synth.voices) scattered over the
    loop, low-passed hard (distance), never a word."""
    loop_s = n / rate
    events = []
    vowels = ("a", "o", "e", "uh", "schwa", "ae")
    for _k in range(count):
        f0 = rng.uniform(110.0, 240.0)
        seconds = rng.uniform(0.25, 0.7)
        v1, v2 = rng.choice(vowels, 2)
        f0_pts = [(0.0, f0 * rng.uniform(0.95, 1.1)), (seconds, f0 * rng.uniform(0.8, 1.0))]
        amp = [(0.0, 0.0), (0.05, 1.0), (seconds * 0.7, 0.7), (seconds, 0.0)]
        sig = voices.call(rng, seconds, f0_pts, [(0.0, str(v1)), (seconds, str(v2))], amp, rate,
                          tract=rng.uniform(0.95, 1.18))
        sig = fx.lowpass(sig, 1300.0, 2.0, rate)
        events.append((rng.uniform(0.0, loop_s), sig / max(core.peak(sig), 1e-9), rng.uniform(-0.7, 0.7),
                       rng.uniform(0.12, 0.3)))
    out = events_loop(n, events, rate)
    return np.stack([core.fft_filter(out[:, c], rate, core.band_response(120.0, 1600.0, 2)) for c in range(2)], axis=1)


def cluck(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A hen's cluck: a short, pinched nasal call."""
    seconds = rng.uniform(0.08, 0.14)
    f0 = rng.uniform(380.0, 520.0)
    sig = voices.call(rng, seconds, [(0.0, f0 * 1.25), (seconds, f0)], [(0.0, "ae"), (seconds, "e")],
                      [(0.0, 0.0), (0.01, 1.0), (seconds, 0.0)], rate, tract=0.55)
    return sig / max(core.peak(sig), 1e-9)


def hens_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Hens scratching about: little runs of clucks now and then, here and there."""
    loop_s = n / rate
    events = []
    t = rng.uniform(0.5, 2.0)
    while t < loop_s:
        pan = rng.uniform(-0.6, 0.6)
        for k in range(int(rng.integers(2, 6))):
            events.append((t + 0.17 * k + rng.uniform(-0.02, 0.02), cluck(rng, rate), pan, rng.uniform(0.25, 0.45)))
        t += rng.uniform(2.0, 5.0)
    return events_loop(n, events, rate)


def drip(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A drop falling into a pool in a stone hollow: a plink whose pitch falls, and its echo."""
    n = M.frames(0.5, rate)
    t = fx.t_axis(n, rate)
    f = rng.uniform(1300.0, 2400.0) * (1.0 + 0.6 * np.exp(-t / 0.012))
    s = core.sine(f, n, rate) * fx.env_ad(n, rate, 0.0008, 0.035)
    echo = np.zeros(n)
    lag = M.frames(rng.uniform(0.09, 0.16), rate)
    echo[lag:] = s[:n - lag] * 0.35
    return fx.seal(s + echo, rate, 0.02)


def drips_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    loop_s = n / rate
    events = []
    t = rng.uniform(0.3, 1.0)
    while t < loop_s:
        events.append((t, drip(rng, rate), rng.uniform(-0.8, 0.8), rng.uniform(0.15, 0.4)))
        t += rng.uniform(0.6, 2.4)
    return events_loop(n, events, rate)


def whistle_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Cold wind whistling through stone: narrow resonances drifting slowly, rising and fading."""
    t = np.arange(n) / rate
    loop_s = n / rate
    curve = periodic_curve(n, rng, 0.05, rate)
    level = np.clip(0.3 + 0.7 * periodic_curve(n, rng, 0.07, rate), 0.0, 2.0) ** 2

    def chan(r):
        x = loop_noise(n, r, 200.0, 3000.0, "pink", rate)
        return moving_band(x, lambda times: 720.0 * 2.0 ** (0.4 * np.interp(np.mod(times, loop_s), t, curve)), 0.12, rate)
    st = decorrelated(n, rng, chan)
    return st * stereo_curve(level)


def water_layer(n: int, rng: np.random.Generator, bubbles_per_s: float = 18.0, rate: int = RATE) -> np.ndarray:
    """Running water: filtered noise with a slow swell and bubbling grains (short rising sines)."""
    loop_s = n / rate
    base = loop_noise(n, rng, 250.0, 3500.0, "pink", rate) * np.clip(1.0 + 0.25 * periodic_curve(n, rng, 0.3, rate), 0.4, 1.6)
    buf = np.zeros(n + M.frames(1.0, rate))
    count = int(bubbles_per_s * loop_s)
    for _k in range(count):
        m = M.frames(rng.uniform(0.02, 0.06), rate)
        tt = fx.t_axis(m, rate)
        f = rng.uniform(450.0, 1700.0) * (1.0 + 2.5 * tt / tt[-1] * rng.uniform(0.2, 0.6))
        g = core.sine(f, m, rate) * np.sin(math.pi * tt / tt[-1]) ** 2
        core.mix_into(buf, M.frames(rng.uniform(0.0, loop_s), rate), g, rng.uniform(0.2, 0.7))
    bub = core.loop_wrap(buf, n)
    return 0.8 * base / max(core.rms(base), 1e-9) + 0.9 * bub / max(core.rms(bub), 1e-9)


def fire_layer(n: int, rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A big forge fire: a low roar that flickers, and crackling (sharp clicks of burning wood)."""
    loop_s = n / rate
    roar = loop_noise(n, rng, 40.0, 420.0, "brown", rate) * np.clip(1.0 + 0.35 * periodic_curve(n, rng, 1.8, rate), 0.3, 1.8)
    buf = np.zeros(n + M.frames(0.5, rate))
    t = 0.0
    while t < loop_s:
        m = M.frames(rng.uniform(0.004, 0.02), rate)
        click = fx.noise(m, rng, 1200.0, 7000.0, rate) * fx.env_ad(m, rate, 0.0003, m / rate * 0.25)
        core.mix_into(buf, M.frames(t, rate), click, rng.uniform(0.1, 1.0) ** 2)
        t += rng.exponential(0.07) if rng.random() < 0.85 else rng.uniform(0.3, 0.9)
    crackle = core.loop_wrap(buf, n)
    roar = roar / max(core.rms(roar), 1e-9)
    return fx.soft_clip(0.7 * roar + 3.0 * crackle / max(core.peak(crackle), 1e-9), 1.6)


def finish_loop(x: np.ndarray, rate: int = RATE, drive: float = 1.0) -> np.ndarray:
    """DC and sub-audio out of a loop (circular); with drive > 1 a gentle tanh saturation (a
    memoryless curve, so the loop stays seamless) takes the odd chirp or drip peak down."""
    y = fx.soft_clip(x, drive) if drive > 1.0 else x
    return core.fft_filter(y, rate, core.band_response(25.0, 0.0, 2))


# --------------------------------------------------------------------------- spots (mono one-shots)


def far(x: np.ndarray, rng: np.random.Generator, cutoff: float = 2500.0, rate: int = RATE) -> np.ndarray:
    """A sound heard from far off: low-passed, a short outdoor reflection pattern."""
    y = fx.lowpass(x, cutoff, 2.0, rate)
    return fx.reflections(y, rng, rate)


def lark(rng: np.random.Generator, seconds: float = 1.45, rate: int = RATE) -> np.ndarray:
    """A skylark's rapid warble: FM chirps of rising and falling pitch, 2.5-5.5 kHz."""
    n = M.frames(seconds, rate)
    out = np.zeros(n)
    t = 0.05
    while t < seconds - 0.12:
        m = M.frames(rng.uniform(0.04, 0.11), rate)
        tt = fx.t_axis(m, rate)
        f0 = rng.uniform(2500.0, 4800.0)
        f = f0 * (1.0 + rng.uniform(-0.25, 0.3) * tt / tt[-1])
        s = instruments.fm(m, rate, f, 1.5, rng.uniform(0.3, 1.2)) * np.clip(np.sin(math.pi * tt / tt[-1]), 0.0, 1.0) ** 1.5
        core.mix_into(out, M.frames(t, rate), s, rng.uniform(0.5, 1.0))
        t += m / rate + rng.uniform(0.0, 0.04)
    return far(out, rng, 7000.0, rate)


def cricket_burst(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    n = M.frames(1.3, rate)
    out = np.zeros(n)
    carrier = rng.uniform(4200.0, 4900.0)
    for k in range(int(rng.integers(5, 8))):
        core.mix_into(out, M.frames(0.03 + 0.18 * k, rate), chirp_train(rng, carrier, 4, 28.0, rate), 1.0 - 0.06 * k)
    return far(out, rng, 8000.0, rate)


def gust(rng: np.random.Generator, seconds: float = 1.5, rate: int = RATE) -> np.ndarray:
    """A gust of wind passing: noise swept by a band-pass that rises and falls with its swell."""
    n = M.frames(seconds, rate)
    x = fx.noise(n, rng, 0.0, 0.0, rate, "pink")
    y = fx.swept_band(x, [(0.0, 300.0), (seconds * 0.55, 1400.0), (seconds, 500.0)],
                      [(0.0, 1.2), (seconds, 1.2)], rate)
    return y * fx.env_points([(0.0, 0.0), (seconds * 0.55, 1.0), (seconds, 0.0)], n, rate)


def woodpecker(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A woodpecker drumming on a trunk: a fast roll of knocks that slows and softens."""
    n = M.frames(1.3, rate)
    out = np.zeros(n)
    t = 0.02
    gap = 0.045
    for k in range(int(rng.integers(13, 18))):
        knock = M.rim(rng, 1.0, rate)
        knock = fx.shape(knock, fx.r_peak(rng.uniform(900.0, 1300.0), 2.0, 9.0), rate)[:knock.shape[0]]
        core.mix_into(out, M.frames(t, rate), knock, 1.0 - 0.035 * k)
        t += gap
        gap *= 1.03
    return far(out, rng, 4000.0, rate)


def owl(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A tawny owl far in the wood: two soft hoots, the second longer and wavering."""
    n = M.frames(1.5, rate)
    out = np.zeros(n)
    for at, dur, f in ((0.05, 0.32, rng.uniform(360.0, 400.0)), (0.6, 0.75, rng.uniform(340.0, 380.0))):
        m = M.frames(dur, rate)
        tt = fx.t_axis(m, rate)
        freq = f * (1.0 + 0.04 * np.exp(-tt / 0.05)) * (1.0 + 0.012 * np.sin(TWO_PI * 9.0 * tt))
        s = (core.sine(freq, m, rate) + 0.08 * core.sine(freq * 2.0, m, rate)) * M.env_note(m, rate, 0.05, dur * 0.7, dur * 0.3)
        s += fx.noise(m, rng, 300.0, 1200.0, rate) * 0.04 * M.env_note(m, rate, 0.02, dur * 0.6, dur * 0.4)
        core.mix_into(out, M.frames(at, rate), s, 1.0)
    return far(out, rng, 2000.0, rate)


def crow(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A crow: two harsh caws (a rough, nasal voice)."""
    n = M.frames(1.4, rate)
    out = np.zeros(n)
    for k in range(2):
        seconds = rng.uniform(0.26, 0.34)
        f0 = rng.uniform(520.0, 640.0)
        s = voices.call(rng, seconds, [(0.0, f0 * 1.1), (seconds * 0.4, f0), (seconds, f0 * 0.85)],
                        [(0.0, "ae"), (seconds, "a")], [(0.0, 0.0), (0.02, 1.0), (seconds * 0.8, 0.8), (seconds, 0.0)],
                        rate, tract=0.5, jitter=0.06, shimmer=0.25, breath=0.35)
        core.mix_into(out, M.frames(0.05 + 0.45 * k + rng.uniform(0.0, 0.05), rate), s / max(core.peak(s), 1e-9), 1.0 - 0.15 * k)
    return far(out, rng, 3500.0, rate)


def tree_creak(rng: np.random.Generator, seconds: float = 1.4, pitch: float = 1.0, rate: int = RATE) -> np.ndarray:
    """An old tree creaking in the wind (instruments.creak: stick-slip through a swept resonance)."""
    pts = [(0.0, 9.0 * pitch), (seconds * 0.5, 14.0 * pitch), (seconds, 7.0 * pitch)]
    s = instruments.creak(rng, seconds, pts, rate)
    s = s[:M.frames(seconds, rate)]
    return far(s * fx.env_points([(0.0, 0.0), (0.15, 1.0), (seconds - 0.2, 0.8), (seconds, 0.0)], s.shape[0], rate),
               rng, 2500.0, rate)


def howl(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A wolf howling far across the valley: a long gliding "oo", rising then falling."""
    seconds = 1.45
    f0 = rng.uniform(420.0, 480.0)
    s = voices.call(rng, seconds, [(0.0, f0 * 0.8), (0.35, f0 * 1.25), (1.0, f0 * 1.15), (seconds, f0 * 0.85)],
                    [(0.0, "u"), (0.6, "o"), (seconds, "u")], [(0.0, 0.0), (0.25, 1.0), (1.1, 0.8), (seconds, 0.0)],
                    rate, tract=0.75, jitter=0.004, shimmer=0.03, breath=0.08)
    return far(s / max(core.peak(s), 1e-9), rng, 1600.0, rate)


def dog(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A farm dog barking twice over in the village."""
    n = M.frames(1.4, rate)
    out = np.zeros(n)
    t = 0.04
    for _k in range(int(rng.integers(2, 4))):
        b = voices.bark(rng, rng.uniform(0.14, 0.2), rate, f0=rng.uniform(330.0, 420.0), tract=1.3)
        core.mix_into(out, M.frames(t, rate), b / max(core.peak(b), 1e-9), rng.uniform(0.75, 1.0))
        t += rng.uniform(0.28, 0.4)
    return far(out, rng, 2800.0, rate)


def hammer(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A smith at work: three hammer strokes on an anvil, the third a little lighter."""
    n = M.frames(1.4, rate)
    out = np.zeros(n)
    parts = instruments.metal_partials(rng, 900.0, 4200.0, 7)
    for k in range(3):
        m = M.frames(0.5, rate)
        ring = instruments.ring(rng, m, rate, parts * rng.uniform(0.99, 1.01), 0.08, 0.3)
        thud = instruments.thump(m, rate, 220.0, 120.0, 0.01, 0.03)
        core.mix_into(out, M.frames(0.03 + 0.42 * k, rate), ring / max(core.peak(ring), 1e-9) + 0.4 * thud,
                      1.0 if k < 2 else 0.7)
    return far(out, rng, 4500.0, rate)


def far_voice(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Someone calling across the fields: one long call, no words."""
    seconds = rng.uniform(0.7, 1.0)
    f0 = rng.uniform(150.0, 220.0)
    s = voices.call(rng, seconds, [(0.0, f0), (seconds * 0.3, f0 * 1.3), (seconds, f0 * 0.9)],
                    [(0.0, "e"), (seconds * 0.35, "o"), (seconds, "o")],
                    [(0.0, 0.0), (0.06, 1.0), (seconds * 0.7, 0.8), (seconds, 0.0)], rate, tract=1.0)
    return far(s / max(core.peak(s), 1e-9), rng, 1800.0, rate)


def cart(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """A cart going by: a wheel squeaking once a turn over a rumble of wood on the track."""
    seconds = 1.45
    n = M.frames(seconds, rate)
    rumble = fx.noise(n, rng, 60.0, 500.0, rate, "brown") * 0.25
    out = rumble * fx.env_points([(0.0, 0.0), (0.3, 1.0), (1.1, 1.0), (seconds, 0.0)], n, rate)
    for k in range(3):
        sq = instruments.creak(rng, 0.25, [(0.0, 24.0), (0.25, 30.0)], rate)
        core.mix_into(out, M.frames(0.15 + 0.42 * k, rate), sq[:M.frames(0.25, rate)], 0.6)
    return far(out, rng, 2400.0, rate)


def pebbles(rng: np.random.Generator, count: int = 14, rate: int = RATE) -> np.ndarray:
    """Loose stones slipping down a slope: a rattle of small stone knocks that thins out."""
    n = M.frames(1.4, rate)
    out = np.zeros(n)
    t = 0.02
    for k in range(count):
        m = M.frames(0.06, rate)
        s = instruments.impact_stone(rng, 0.06, 0.0, rate)[:m]
        core.mix_into(out, M.frames(t, rate), s / max(core.peak(s), 1e-9), max(0.15, 1.0 - 0.06 * k) * rng.uniform(0.5, 1.0))
        t += rng.uniform(0.03, 0.09) * (1.0 + 0.08 * k)
        if t > 1.3:
            break
    return far(out, rng, 5000.0, rate)


def wind_whistle(rng: np.random.Generator, seconds: float = 1.5, rate: int = RATE) -> np.ndarray:
    n = M.frames(seconds, rate)
    x = fx.noise(n, rng, 0.0, 0.0, rate, "pink")
    f0 = rng.uniform(750.0, 950.0)
    y = fx.swept_band(x, [(0.0, f0), (seconds * 0.5, f0 * 1.35), (seconds, f0 * 1.05)], [(0.0, 18.0), (seconds, 18.0)], rate)
    return y * fx.env_points([(0.0, 0.0), (seconds * 0.4, 1.0), (seconds * 0.7, 0.8), (seconds, 0.0)], n, rate)


def clank(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Iron struck somewhere in the ruins, far away."""
    s = instruments.impact_iron(rng, 1.0, 0.3, rate)
    return far(s, rng, 3000.0, rate)


def birds_flush(rng: np.random.Generator, rate: int = RATE) -> np.ndarray:
    """Birds taking flight all at once: wingbeats fluttering away and a few alarm calls."""
    seconds = 1.5
    n = M.frames(seconds, rate)
    out = np.zeros(n)
    for _b in range(int(rng.integers(5, 9))):
        start = rng.uniform(0.0, 0.25)
        m = M.frames(seconds - start, rate)
        tt = fx.t_axis(m, rate)
        rate_hz = rng.uniform(12.0, 20.0)
        flaps = np.clip(np.sin(TWO_PI * rate_hz * tt + rng.uniform(0, TWO_PI)), 0.0, 1.0) ** 3
        s = fx.noise(m, rng, 400.0, 4500.0, rate) * flaps * np.exp(-tt / rng.uniform(0.35, 0.7))
        core.mix_into(out, M.frames(start, rate), s, rng.uniform(0.4, 1.0))
    for _c in range(3):
        m = M.frames(0.09, rate)
        tt = fx.t_axis(m, rate)
        chirp = instruments.fm(m, rate, rng.uniform(3000.0, 4200.0) * (1.0 - 0.3 * tt / tt[-1]), 2.0, 0.8) \
            * np.sin(math.pi * tt / tt[-1])
        core.mix_into(out, M.frames(rng.uniform(0.05, 0.6), rate), chirp, 0.5)
    return far(out, rng, 7000.0, rate)
