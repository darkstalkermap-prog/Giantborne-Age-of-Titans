"""Placeholder sounds of the audio engine (P19): four test tones, one three-variant test set, one
test bed and a one-second test stinger, about 110 KB in all. The engine's placeholder bank (data/audio/bank_placeholder.json)
points every family's default cue at them, so the Valley makes sounds before the sound packages
land; the engine's tests use them as known signals. The sound packages replace them (P21 the
effects, P23 the music and ambience) and P23 deletes them.

Every sound here is original and synthesized by these functions (no recordings, no samples).
"""

from __future__ import annotations

import numpy as np

from synth import core

FAMILY = "placeholder"
RATE = core.DEFAULT_RATE
BED_BPM = 120.0
BED_BEATS = 16
BED_BEATS_PER_BAR = 4


def _dc_safe(x: np.ndarray, fade_out_s: float = 0.01) -> np.ndarray:
    """Removes DC with a gentle high-pass and fades the tail to zero."""
    y = core.biquad(x, core.biquad_coeffs("highpass", 25.0, 0.707, RATE))
    return core.fade(y, RATE, 0.002, fade_out_s)


def thump(rng: np.random.Generator, seconds: float, f_start: float, f_end: float, noise: float) -> np.ndarray:
    """A low thump: a sine falling from f_start to f_end Hz under a little low-passed noise."""
    n = core.n_frames(seconds, RATE)
    t = core.time_axis(n, RATE)
    freq = f_end + (f_start - f_end) * np.exp(-t / 0.04)
    body = core.sine(freq, n, RATE) * core.exp_decay(n, RATE, seconds * 0.3)
    grit = core.biquad(core.white(n, rng), core.biquad_coeffs("lowpass", 900.0, 0.7, RATE))
    grit *= core.exp_decay(n, RATE, 0.03) * noise
    return _dc_safe(body + grit)


def blip(rng: np.random.Generator, seconds: float, notes: list) -> np.ndarray:
    """A short interface blip: triangle notes in sequence with fast envelopes."""
    n = core.n_frames(seconds, RATE)
    out = np.zeros(n)
    step = n // max(1, len(notes))
    for i, note in enumerate(notes):
        m = n - i * step if i == len(notes) - 1 else step
        tone = core.triangle(core.midi_hz(note), m, RATE)
        env = core.adsr(m, RATE, 0.004, 0.03, 0.4, 0.04)
        core.mix_into(out, i * step, tone * env)
    # a hint of noise so variant checks never see a perfectly periodic signal
    out += 0.002 * core.white(n, rng)
    return _dc_safe(out, 0.005)


def chirp(rng: np.random.Generator, seconds: float, f_lo: float, f_hi: float) -> np.ndarray:
    """A rising band-passed chirp with a tick at the start (a threat-like cue)."""
    n = core.n_frames(seconds, RATE)
    t = core.time_axis(n, RATE) / seconds
    centres = f_lo * (f_hi / f_lo) ** t
    sweep = core.svf(core.white(n, rng), centres, 4.0, RATE, "bandpass")
    tone = 0.5 * core.sine(centres, n, RATE)
    env = core.envelope([(0.0, 0.0), (0.02, 1.0), (seconds * 0.7, 0.8), (seconds, 0.0)], n, RATE)
    tick = core.white(n, rng) * core.exp_decay(n, RATE, 0.002)
    return _dc_safe((sweep + tone) * env + 0.6 * tick, 0.01)


def whoosh(rng: np.random.Generator, seconds: float, f_lo: float, f_hi: float) -> np.ndarray:
    """Band-passed noise whose centre swells from f_lo to f_hi and back (a swing)."""
    n = core.n_frames(seconds, RATE)
    u = core.time_axis(n, RATE) / seconds
    centres = f_lo + (f_hi - f_lo) * np.sin(np.pi * u) ** 1.5
    x = core.svf(core.white(n, rng), centres, 2.5, RATE, "bandpass")
    env = np.sin(np.pi * np.clip(u / 0.9, 0.0, 1.0)) ** 2
    return _dc_safe(x * env, 0.01)


def burst(rng: np.random.Generator, seconds: float, centre: float, q: float) -> np.ndarray:
    """A short resonant noise burst (an impact-like variant)."""
    n = core.n_frames(seconds, RATE)
    x = core.biquad(core.white(n, rng), core.biquad_coeffs("bandpass", centre, q, RATE))
    x *= core.exp_decay(n, RATE, seconds * 0.18)
    knock = core.sine(centre * 0.25, n, RATE) * core.exp_decay(n, RATE, seconds * 0.12)
    return _dc_safe(x + 0.6 * knock)


def stinger(rng: np.random.Generator, seconds: float, notes: list) -> np.ndarray:
    """A short rising figure of filtered saw notes (a stinger-like one-shot for the music tests)."""
    n = core.n_frames(seconds, RATE)
    out = np.zeros(n)
    step = n // (len(notes) + 1)
    for i, note in enumerate(notes):
        m = n - i * step
        tone = core.saw(core.midi_hz(note), m, RATE) + 0.5 * core.saw(core.midi_hz(note) * 1.003, m, RATE)
        tone = core.biquad(tone, core.biquad_coeffs("lowpass", 1800.0, 0.8, RATE))
        core.mix_into(out, i * step, tone * core.adsr(m, RATE, 0.02, 0.15, 0.6, 0.25))
    out += 0.003 * core.white(n, rng)
    return _dc_safe(out, 0.05)


def bed(rng: np.random.Generator, bpm: float, beats: int, pulse_hz: float) -> np.ndarray:
    """A seamless test bed: slowly moving low-passed pink noise with a soft pulse on every beat,
    exactly beats x 60 / bpm seconds long (circular filtering and wrapping keep the seam clean)."""
    period = core.n_frames(beats * 60.0 / bpm, RATE)
    wind = core.fft_filter(core.pink(period, rng), RATE, core.band_response(40.0, 1200.0, 2))
    swell = 0.75 + 0.25 * np.sin(2.0 * np.pi * np.arange(period) / period * 2.0)
    buf = np.zeros(period + core.n_frames(1.0, RATE))
    beat_frames = 60.0 / bpm * RATE
    pulse_n = core.n_frames(0.35, RATE)
    pulse = core.sine(pulse_hz, pulse_n, RATE) * core.envelope([(0.0, 0.0), (0.01, 1.0), (0.35, 0.0)], pulse_n, RATE)
    for b in range(beats):
        core.mix_into(buf, int(round(b * beat_frames)), pulse, 0.6 if b % BED_BEATS_PER_BAR == 0 else 0.35)
    pulses = core.loop_wrap(buf, period)
    mix = 0.5 * wind / max(core.peak(wind), 1e-9) * swell + pulses
    return core.fft_filter(mix, RATE, core.band_response(30.0, 0.0, 1))


_P = "res://assets/audio/placeholder/"

CUES = [
    {"name": "tone_low", "path": _P + "tone_low.wav", "seed": 190101, "func": thump, "kind": "sfx",
     "params": {"seconds": 0.30, "f_start": 140.0, "f_end": 55.0, "noise": 0.25}},
    {"name": "tone_mid", "path": _P + "tone_mid.wav", "seed": 190102, "func": blip, "kind": "sfx",
     "params": {"seconds": 0.15, "notes": [76, 81]}},
    {"name": "tone_high", "path": _P + "tone_high.wav", "seed": 190103, "func": chirp, "kind": "sfx",
     "params": {"seconds": 0.25, "f_lo": 1500.0, "f_hi": 5000.0}},
    {"name": "tone_sweep", "path": _P + "tone_sweep.wav", "seed": 190104, "func": whoosh, "kind": "sfx",
     "params": {"seconds": 0.35, "f_lo": 300.0, "f_hi": 1600.0}},
    {"name": "set_a1", "path": _P + "set_a1.wav", "seed": 190111, "func": burst, "kind": "sfx",
     "params": {"seconds": 0.20, "centre": 420.0, "q": 3.0}},
    {"name": "set_a2", "path": _P + "set_a2.wav", "seed": 190112, "func": burst, "kind": "sfx",
     "params": {"seconds": 0.20, "centre": 520.0, "q": 3.0}},
    {"name": "set_a3", "path": _P + "set_a3.wav", "seed": 190113, "func": burst, "kind": "sfx",
     "params": {"seconds": 0.20, "centre": 360.0, "q": 3.0}},
    {"name": "stinger", "path": _P + "stinger.ogg", "seed": 190131, "func": stinger, "kind": "oneshot",
     "quality": 2, "params": {"seconds": 1.0, "notes": [50, 57, 62]}},
    {"name": "bed", "path": _P + "bed.ogg", "seed": 190121, "func": bed, "kind": "loop", "quality": 0,
     "params": {"bpm": BED_BPM, "beats": BED_BEATS, "pulse_hz": 82.0},
     "bpm": BED_BPM, "beats": BED_BEATS, "beats_per_bar": BED_BEATS_PER_BAR, "frame": "test_120",
     "norm": {"peak_db": -3.0}},
]
