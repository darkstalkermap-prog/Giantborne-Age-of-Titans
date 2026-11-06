"""Synthesized voices for the sound effects (P21; plan M6-M9 section 4.2, family E): calls, never
words. Source-filter synthesis:

* the source is a Rosenberg glottal pulse train (its flow derivative), following an f0 contour,
  with jitter and shimmer drawn per period, aspiration noise gated by the glottal opening, and
  for big bodies a subharmonic (alternate pulses weaker) and a 30-40 Hz growl modulation
* the filter is a cascade of five formant resonators whose centres and bandwidths move between
  vowel targets; it is applied frame by frame in an STFT (hop 11.6 ms), so vowel glides are smooth
* the vocal tract scale moves every formant: humans 1.0, women and the elder about 1.15, ogres
  0.72, the Ogre King 0.6, the giant 0.62; f0: humans 120-220 Hz, ogres 60-90, the King 45-60,
  giants 40-70
* wolves are shaped noise with resonant snarls, barks and yelps; crowds are several voices layered
  with small offsets, pitches and tract sizes

All randomness comes from the cue's generator.
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx, instruments

RATE = core.DEFAULT_RATE
TWO_PI = 2.0 * math.pi

# Formant targets (Hz) of an adult male tract; bandwidths are set by BANDWIDTHS x a scale.
VOWELS = {
    "a": (730.0, 1090.0, 2440.0, 3300.0, 3750.0),
    "o": (570.0, 840.0, 2410.0, 3300.0, 3750.0),
    "u": (300.0, 870.0, 2240.0, 3300.0, 3750.0),
    "e": (530.0, 1840.0, 2480.0, 3300.0, 3750.0),
    "i": (270.0, 2290.0, 3010.0, 3500.0, 3900.0),
    "ae": (660.0, 1720.0, 2410.0, 3300.0, 3750.0),
    "uh": (640.0, 1190.0, 2390.0, 3300.0, 3750.0),
    "er": (490.0, 1350.0, 1690.0, 3300.0, 3750.0),
    "schwa": (500.0, 1500.0, 2500.0, 3300.0, 3750.0),
    "m": (280.0, 1000.0, 2200.0, 3300.0, 3750.0),     # a closed-mouth hum (wide, damped below)
}
BANDWIDTHS = (90.0, 110.0, 170.0, 250.0, 300.0)


# --------------------------------------------------------------------------- the source


def glottal(rng: np.random.Generator, f0: np.ndarray, rate: int = RATE, open_q: float = 0.6,
            skew: float = 0.68, jitter: float = 0.012, shimmer: float = 0.06, sub: float = 0.0,
            growl_hz: float = 0.0, growl: float = 0.0) -> tuple:
    """(excitation, opening) for a per-sample f0: the Rosenberg flow derivative with jitter and
    shimmer per period, a subharmonic and a growl; `opening` (0..1) gates the aspiration."""
    f0 = np.maximum(np.asarray(f0, dtype=np.float64), 20.0)
    n = f0.shape[0]
    ph0 = np.cumsum(f0) / rate
    periods = int(ph0[-1]) + 3
    jit = 1.0 + jitter * rng.standard_normal(periods)
    f = f0 * jit[np.minimum(np.floor(ph0).astype(np.int64), periods - 1)]
    ph = np.cumsum(f) / rate
    k = np.floor(ph).astype(np.int64)
    frac = ph - k
    tp = open_q * skew
    tn = open_q * (1.0 - skew)
    flow = np.where(frac < tp, 0.5 * (1.0 - np.cos(math.pi * frac / tp)),
                    np.where(frac < tp + tn, np.cos(0.5 * math.pi * (frac - tp) / tn), 0.0))
    amp = 1.0 + shimmer * rng.standard_normal(int(k[-1]) + 3)
    a = amp[np.minimum(k, amp.shape[0] - 1)]
    if sub > 0.0:
        a = a * np.where(k % 2 == 0, 1.0, 1.0 - sub)
    if growl > 0.0 and growl_hz > 0.0:
        t = fx.t_axis(n, rate)
        wob = np.sin(TWO_PI * growl_hz * t + 0.6 * np.sin(TWO_PI * growl_hz * 0.31 * t))
        a = a * (1.0 - growl * 0.5 * (1.0 + wob))
    flow = flow * np.maximum(a, 0.0)
    exc = np.diff(flow, prepend=0.0) * (rate / 200.0)
    return exc, np.clip(flow, 0.0, 1.0)


# --------------------------------------------------------------------------- the filter


def formant_gains(freqs: np.ndarray, formants: np.ndarray, bands: np.ndarray) -> np.ndarray:
    """Cascade-resonator magnitude for each frame: formants and bands are (frames, 5)."""
    f = freqs[None, :, None]
    fc = formants[:, None, :]
    b = 0.5 * bands[:, None, :]
    num = fc * fc + b * b
    den = np.sqrt(((f - fc) ** 2 + b * b) * ((f + fc) ** 2 + b * b))
    return np.prod(num / np.maximum(den, 1e-9), axis=2)


def _vowel_tracks(vowel_points, times: np.ndarray, tract: float, bw_scale: float) -> tuple:
    pts = sorted(vowel_points, key=lambda p: float(p[0]))
    ts = np.array([float(p[0]) for p in pts])
    fm = np.array([VOWELS[p[1]] for p in pts])
    form = np.stack([np.interp(times, ts, fm[:, i]) for i in range(5)], axis=1) * tract
    bands = np.tile(np.array(BANDWIDTHS) * bw_scale * math.sqrt(max(tract, 0.2)), (times.shape[0], 1))
    nasal = np.array([1.0 if p[1] == "m" else 0.0 for p in pts])
    nas = np.interp(times, ts, nasal)
    bands[:, 0] *= 1.0 + 1.5 * nas
    return form, bands, nas


def articulate(src: np.ndarray, vowel_points, rate: int = RATE, tract: float = 1.0, bw_scale: float = 1.0,
               tilt_db: float = 0.0, frame: int = 1024) -> np.ndarray:
    """Filters a source through formants moving between (time_s, vowel) points (tract scales
    every formant frequency); tilt_db per octave brightens (+) or darkens (-) above 500 Hz."""
    def gains(freqs, times):
        form, bands, nas = _vowel_tracks(vowel_points, times, tract, bw_scale)
        g = formant_gains(freqs, form, bands)
        if tilt_db != 0.0:
            g = g * fx.r_tilt(500.0, tilt_db)(freqs)[None, :]
        # a hum's mouth is closed: everything above the first formant falls away
        g = g * (1.0 - 0.8 * nas[:, None] * (freqs[None, :] > 600.0 * tract))
        return g
    return fx.stft_shape(src, gains, rate, frame)


# --------------------------------------------------------------------------- calls


def call(rng: np.random.Generator, seconds: float, f0_points, vowel_points, amp_points, rate: int = RATE,
         tract: float = 1.0, breath: float = 0.05, breath_points=None, jitter: float = 0.012,
         shimmer: float = 0.06, sub: float = 0.0, growl_hz: float = 0.0, growl: float = 0.0,
         open_q: float = 0.6, drive: float = 0.0, tilt_db: float = 0.0, bw_scale: float = 1.0,
         vibrato_hz: float = 0.0, vibrato: float = 0.0) -> np.ndarray:
    """One vocal call: an f0 contour (time_s, Hz; log-interpolated), a vowel path (time_s,
    vowel), an amplitude envelope (time_s, level), aspiration (breath, or breath_points over
    time), and the voice's quality (tract, jitter, shimmer, subharmonic, growl, drive)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    f0 = fx.log_track(f0_points, t)
    if vibrato > 0.0 and vibrato_hz > 0.0:
        f0 = f0 * (1.0 + vibrato * np.sin(TWO_PI * vibrato_hz * t + rng.uniform(0, TWO_PI)))
    f0 = f0 * (1.0 + 0.012 * fx.wander(n, rng, 6.0, rate))
    exc, opening = glottal(rng, f0, rate, open_q, 0.68, jitter, shimmer, sub, growl_hz, growl)
    exc /= max(core.rms(exc), 1e-9)
    asp = fx.noise(n, rng, 400.0, 0.0, rate, "white") * (0.25 + 0.75 * opening)
    br = fx.track(breath_points, t) if breath_points is not None else np.full(n, breath)
    voiced = 1.0 - np.clip(br, 0.0, 1.0) * 0.6
    src = exc * voiced + 2.2 * br * asp
    y = articulate(src, vowel_points, rate, tract, bw_scale, tilt_db)
    y = y * fx.env_points(amp_points, n, rate)
    if drive > 0.0:
        y = fx.soft_clip(y, drive)
    return y


def breath(rng: np.random.Generator, seconds: float, vowel_points, amp_points, rate: int = RATE,
           tract: float = 1.0, lo: float = 300.0) -> np.ndarray:
    """An unvoiced breath through the vowel path (gasps, exhales, hisses)."""
    n = fx.frames(seconds, rate)
    src = fx.noise(n, rng, lo, 0.0, rate, "white")
    y = articulate(src, vowel_points, rate, tract, 1.6, 0.0)
    return y * fx.env_points(amp_points, n, rate)


def growl_tail(rng: np.random.Generator, n: int, rate: int, f0: float, tract: float, amp_points,
               rough_hz: float = 34.0) -> np.ndarray:
    """A rough low rattle (the back of a big throat): noise and a low pulse train through dark
    formants, amplitude-modulated at rough_hz."""
    sec = n / rate
    v = call(rng, sec, [(0.0, f0), (sec, f0 * 0.9)], [(0.0, "o"), (sec, "u")], amp_points, rate, tract,
             breath=0.35, jitter=0.04, shimmer=0.25, sub=0.5, growl_hz=rough_hz, growl=0.8, drive=2.0, tilt_db=-2.0)
    return v


# --------------------------------------------------------------------------- animals


def snarl(rng: np.random.Generator, seconds: float, rate: int = RATE, f0: float = 120.0, tract: float = 1.55,
          intensity: float = 1.0) -> np.ndarray:
    """A wolf's snarl: a rough low voice with bared-teeth hiss, growl-modulated."""
    n = fx.frames(seconds, rate)
    voice = call(rng, seconds, [(0.0, f0 * 0.9), (seconds * 0.4, f0 * 1.15), (seconds, f0 * 0.85)],
                 [(0.0, "u"), (seconds * 0.35, "a"), (seconds, "e")],
                 [(0.0, 0.0), (0.03, 0.8), (seconds * 0.5, 1.0), (seconds, 0.0)], rate, tract,
                 breath=0.3, jitter=0.05, shimmer=0.3, sub=0.3, growl_hz=rng.uniform(28.0, 40.0), growl=0.85,
                 drive=2.2, tilt_db=1.0)
    hiss = fx.noise(n, rng, 2500.0, 9000.0, rate) * fx.env_points([(0.0, 0.0), (0.05, 0.6), (seconds * 0.6, 0.8),
                                                                    (seconds, 0.0)], n, rate)
    hiss = fx.tremolo(hiss, rng.uniform(25.0, 35.0), 0.7, rate)
    return voice / max(core.peak(voice), 1e-9) * intensity + 0.18 * hiss


def snap(rng: np.random.Generator, n: int, rate: int, at_s: float) -> np.ndarray:
    """Jaws snapping shut: a sharp clack and a soft thud."""
    out = np.zeros(n)
    m = n - fx.frames(at_s, rate)
    if m <= 8:
        return out
    clack = instruments.burst(rng, m, rate, 1800.0, 7000.0, 0.0002, 0.002)
    tooth = fx.modal_ir([rng.uniform(2200, 3200), rng.uniform(4000, 5200)], [0.004, 0.002], [1.0, 0.5], m, rate)
    thud = instruments.thump(m, rate, 260.0, 160.0, 0.006, 0.012, 0.0005)
    core.mix_into(out, fx.frames(at_s, rate), clack + 0.5 * tooth + 0.4 * thud)
    return out


def bark(rng: np.random.Generator, seconds: float, rate: int = RATE, f0: float = 380.0, tract: float = 1.45) -> np.ndarray:
    """A short sharp bark."""
    v = call(rng, seconds, [(0.0, f0 * 0.85), (0.025, f0 * 1.1), (seconds, f0 * 0.75)],
             [(0.0, "a"), (seconds * 0.5, "a"), (seconds, "uh")],
             [(0.0, 0.0), (0.008, 1.0), (seconds * 0.4, 0.7), (seconds, 0.0)], rate, tract,
             breath=0.2, jitter=0.03, shimmer=0.15, sub=0.15, drive=1.8, tilt_db=1.5)
    return v


def yelp(rng: np.random.Generator, seconds: float, rate: int = RATE, f_start: float = 820.0, f_end: float = 480.0,
         tract: float = 1.4, whine: bool = False) -> np.ndarray:
    """A yelp (pain) or a whine (whimper): a high, bright, rough voice falling fast (or
    wavering), with the nasal breath of a dog."""
    pts = [(0.0, f_start * 0.9), (0.02, f_start), (seconds, f_end)]
    v = call(rng, seconds, pts, [(0.0, "ae"), (seconds * 0.5, "a"), (seconds, "uh")],
             [(0.0, 0.0), (0.012, 1.0), (seconds * 0.55, 0.65 if not whine else 0.85), (seconds, 0.0)], rate, tract,
             breath=0.3 if whine else 0.18, jitter=0.03, shimmer=0.2, open_q=0.42,
             vibrato_hz=7.0 if whine else 0.0, vibrato=0.035 if whine else 0.0, tilt_db=3.0, bw_scale=1.6)
    n = v.shape[0]
    nose = fx.noise(n, rng, 1500.0, 6000.0, rate) * fx.env_points([(0.0, 0.0), (0.01, 0.5), (seconds, 0.0)], n, rate)
    return v / max(core.peak(v), 1e-9) + 0.12 * nose


# --------------------------------------------------------------------------- crowds


def crowd(rng: np.random.Generator, seconds: float, make_voice, count: int = 6, spread_s: float = 0.25,
          rate: int = RATE, distance_hz: float = 0.0) -> np.ndarray:
    """count voices from make_voice(rng, index) layered with offsets up to spread_s, then (with
    distance_hz) low-passed as if heard across a square."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    for i in range(count):
        v = make_voice(rng, i)
        v = v / max(core.peak(v), 1e-9)
        core.mix_into(out, fx.frames(rng.uniform(0.0, spread_s), rate), v, rng.uniform(0.5, 1.0))
    if distance_hz > 0.0:
        out = fx.lowpass(out, distance_hz, 1.5, rate)
    return out


def voice_params(rng: np.random.Generator, kind: str) -> dict:
    """A random speaker of a kind: "man", "woman", "elder" (an older woman)."""
    if kind == "woman":
        return {"f0": rng.uniform(180.0, 240.0), "tract": rng.uniform(1.12, 1.2)}
    if kind == "elder":
        return {"f0": rng.uniform(165.0, 195.0), "tract": rng.uniform(1.1, 1.16)}
    return {"f0": rng.uniform(110.0, 160.0), "tract": rng.uniform(0.95, 1.05)}
