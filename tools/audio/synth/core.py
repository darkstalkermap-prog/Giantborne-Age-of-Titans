"""Core synthesis library for Giantborn's generated audio (numpy, float64, single-threaded).

Every sound in the game is original: the generators in tools/audio/ (gen_<family>.py) render it
through these functions, and tools/audio/build_audio.py writes, checks, encodes and records the
results (plan M6-M9, decision 4). This module holds the building blocks:

* sample counts and time axes; a seeded random generator per cue (cue_rng)
* oscillators (sine, band-limited saw and square, triangle) with fixed or per-sample frequency
* noise (white, pink, brown)
* envelopes (piecewise-linear points, ADSR, exponential decay, fades)
* filters: RBJ biquads, a topology-preserving state-variable filter with a per-sample cutoff,
  zero-phase FFT filtering (circular, so loops stay seamless), FFT convolution
* loops: wrapping a render's tail onto its head (exact for mixed events), circular cross-fades
* levels: peak and RMS measurement and normalisation, equal-power panning
* checks: clipping, DC, silence, loop seams, length (check_signal)
* writers: 16-bit PCM WAV bytes (the SFX masters), 32-bit float WAV bytes (the encoder's input
  and the music and ambience masters' hash), FLAC export through ffmpeg

Nothing here reads the clock, the environment or the global random state: the same seed and the
same parameters give the same samples on the reference toolchain (the Python, numpy, ffmpeg and
libvorbis versions recorded in assets/audio/manifest.json). Signals are float64 numpy arrays,
shape (n,) for mono and (n, 2) for stereo, nominally in [-1, 1].
"""

from __future__ import annotations

import hashlib
import math
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path

import numpy as np

DEFAULT_RATE = 22050
TWO_PI = 2.0 * math.pi

# --------------------------------------------------------------------------- time and randomness


def n_frames(seconds: float, rate: int = DEFAULT_RATE) -> int:
    """The number of frames of `seconds` at `rate`, rounded to the nearest frame."""
    return int(round(float(seconds) * rate))


def time_axis(n: int, rate: int = DEFAULT_RATE) -> np.ndarray:
    """Sample times in seconds: 0, 1/rate, ..."""
    return np.arange(n, dtype=np.float64) / float(rate)


def cue_rng(seed: int) -> np.random.Generator:
    """The random generator of one cue (PCG64 with the cue's seed). Each cue owns its own, so
    adding or reordering cues never changes another cue's samples."""
    return np.random.Generator(np.random.PCG64(int(seed)))


def midi_hz(note: float) -> float:
    """The frequency of a MIDI note number (69 = A4 = 440 Hz)."""
    return 440.0 * 2.0 ** ((float(note) - 69.0) / 12.0)


def db_to_gain(db: float) -> float:
    return 10.0 ** (float(db) / 20.0)


def gain_to_db(gain: float) -> float:
    return 20.0 * math.log10(max(abs(float(gain)), 1e-12))


# --------------------------------------------------------------------------- oscillators


def _phase(freq, n: int, rate: int, phase: float = 0.0) -> np.ndarray:
    """Phase in cycles (not wrapped) for a fixed or per-sample frequency; the first sample has
    exactly `phase`."""
    if np.isscalar(freq):
        return phase + float(freq) * np.arange(n, dtype=np.float64) / rate
    f = np.asarray(freq, dtype=np.float64)
    if f.shape[0] != n:
        raise ValueError("per-sample frequency must have n entries")
    acc = np.cumsum(f) / rate
    return phase + np.concatenate(([0.0], acc[:-1]))


def sine(freq, n: int, rate: int = DEFAULT_RATE, phase: float = 0.0) -> np.ndarray:
    """A sine wave (phase in cycles)."""
    return np.sin(TWO_PI * _phase(freq, n, rate, phase))


def _poly_blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """The polyBLEP residual for phase fractions t in [0, 1) and increments dt."""
    out = np.zeros_like(t)
    dt = np.maximum(dt, 1e-12)
    a = t < dt
    x = t[a] / dt[a]
    out[a] = x + x - x * x - 1.0
    b = t > 1.0 - dt
    y = (t[b] - 1.0) / dt[b]
    out[b] = y * y + y + y + 1.0
    return out


def saw(freq, n: int, rate: int = DEFAULT_RATE, phase: float = 0.0) -> np.ndarray:
    """A band-limited (polyBLEP) rising sawtooth in [-1, 1]."""
    ph = _phase(freq, n, rate, phase)
    t = ph - np.floor(ph)
    dt = np.abs(np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)) / rate
    return 2.0 * t - 1.0 - _poly_blep(t, dt)


def square(freq, n: int, rate: int = DEFAULT_RATE, duty: float = 0.5, phase: float = 0.0) -> np.ndarray:
    """A band-limited (polyBLEP) pulse wave in [-1, 1] with the given duty cycle."""
    ph = _phase(freq, n, rate, phase)
    t = ph - np.floor(ph)
    dt = np.abs(np.full(n, float(freq)) if np.isscalar(freq) else np.asarray(freq)) / rate
    out = np.where(t < duty, 1.0, -1.0)
    out += _poly_blep(t, dt)
    t2 = t - duty
    t2 = t2 - np.floor(t2)
    out -= _poly_blep(t2, dt)
    return out


def triangle(freq, n: int, rate: int = DEFAULT_RATE, phase: float = 0.0) -> np.ndarray:
    """A triangle wave in [-1, 1] (from the phase; its harmonics fall as 1/k^2)."""
    ph = _phase(freq, n, rate, phase)
    t = ph - np.floor(ph)
    return 1.0 - 4.0 * np.abs(t - 0.5)


# --------------------------------------------------------------------------- noise


def white(n: int, rng: np.random.Generator) -> np.ndarray:
    """Gaussian white noise with unit variance."""
    return rng.standard_normal(n)


def _shaped_noise(n: int, rng: np.random.Generator, exponent: float) -> np.ndarray:
    """White noise shaped by 1 / f^exponent in the frequency domain (circular, so it loops),
    normalised to unit RMS."""
    if n < 2:
        return np.zeros(n)
    spec = np.fft.rfft(rng.standard_normal(n))
    k = np.arange(spec.shape[0], dtype=np.float64)
    k[0] = 1.0
    spec = spec / (k ** exponent)
    spec[0] = 0.0
    out = np.fft.irfft(spec, n)
    rms = math.sqrt(float(np.mean(out * out)))
    return out / rms if rms > 0.0 else out


def pink(n: int, rng: np.random.Generator) -> np.ndarray:
    """Pink noise (-3 dB per octave), unit RMS, circular."""
    return _shaped_noise(n, rng, 0.5)


def brown(n: int, rng: np.random.Generator) -> np.ndarray:
    """Brown noise (-6 dB per octave), unit RMS, circular."""
    return _shaped_noise(n, rng, 1.0)


# --------------------------------------------------------------------------- envelopes


def envelope(points, n: int, rate: int = DEFAULT_RATE) -> np.ndarray:
    """A piecewise-linear envelope through (time_s, level) points; held flat outside them."""
    pts = sorted((float(t), float(v)) for t, v in points)
    ts = np.array([p[0] for p in pts]) * rate
    vs = np.array([p[1] for p in pts])
    return np.interp(np.arange(n, dtype=np.float64), ts, vs)


def adsr(n: int, rate: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    """Attack, decay to `sustain`, hold, and a release that ends at the last sample."""
    total = max(n - 1, 1) / rate
    rel_start = max(attack + decay, total - release)
    return envelope([(0.0, 0.0), (attack, 1.0), (attack + decay, sustain), (rel_start, sustain),
                     (total, 0.0)], n, rate)


def exp_decay(n: int, rate: int, tau: float) -> np.ndarray:
    """exp(-t / tau)."""
    return np.exp(-time_axis(n, rate) / max(float(tau), 1e-9))


def fade(x: np.ndarray, rate: int, fade_in: float = 0.0, fade_out: float = 0.0) -> np.ndarray:
    """Linear fades at the ends (copies)."""
    out = np.array(x, dtype=np.float64, copy=True)
    n = out.shape[0]
    fi = min(n, n_frames(fade_in, rate))
    fo = min(n, n_frames(fade_out, rate))
    if fi > 0:
        ramp = np.linspace(0.0, 1.0, fi, endpoint=False)
        out[:fi] = (out[:fi].T * ramp).T
    if fo > 0:
        ramp = np.linspace(1.0, 0.0, fo)
        out[n - fo:] = (out[n - fo:].T * ramp).T
    return out


# --------------------------------------------------------------------------- filters


def biquad_coeffs(kind: str, freq: float, q: float, rate: int = DEFAULT_RATE,
                  gain_db: float = 0.0) -> tuple:
    """RBJ cookbook biquad coefficients (b0, b1, b2, a1, a2), normalised by a0.
    kind: lowpass | highpass | bandpass (0 dB peak) | notch | peak | lowshelf | highshelf."""
    f = min(max(float(freq), 1.0), rate * 0.49)
    w0 = TWO_PI * f / rate
    cw = math.cos(w0)
    sw = math.sin(w0)
    alpha = sw / (2.0 * max(float(q), 1e-6))
    a_gain = 10.0 ** (gain_db / 40.0)
    if kind == "lowpass":
        b = ((1 - cw) / 2, 1 - cw, (1 - cw) / 2)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    elif kind == "highpass":
        b = ((1 + cw) / 2, -(1 + cw), (1 + cw) / 2)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    elif kind == "bandpass":
        b = (alpha, 0.0, -alpha)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    elif kind == "notch":
        b = (1.0, -2 * cw, 1.0)
        a = (1 + alpha, -2 * cw, 1 - alpha)
    elif kind == "peak":
        b = (1 + alpha * a_gain, -2 * cw, 1 - alpha * a_gain)
        a = (1 + alpha / a_gain, -2 * cw, 1 - alpha / a_gain)
    elif kind in ("lowshelf", "highshelf"):
        sq = 2.0 * math.sqrt(a_gain) * alpha
        if kind == "lowshelf":
            b = (a_gain * ((a_gain + 1) - (a_gain - 1) * cw + sq),
                 2 * a_gain * ((a_gain - 1) - (a_gain + 1) * cw),
                 a_gain * ((a_gain + 1) - (a_gain - 1) * cw - sq))
            a = ((a_gain + 1) + (a_gain - 1) * cw + sq,
                 -2 * ((a_gain - 1) + (a_gain + 1) * cw),
                 (a_gain + 1) + (a_gain - 1) * cw - sq)
        else:
            b = (a_gain * ((a_gain + 1) + (a_gain - 1) * cw + sq),
                 -2 * a_gain * ((a_gain - 1) + (a_gain + 1) * cw),
                 a_gain * ((a_gain + 1) + (a_gain - 1) * cw - sq))
            a = ((a_gain + 1) - (a_gain - 1) * cw + sq,
                 2 * ((a_gain - 1) - (a_gain + 1) * cw),
                 (a_gain + 1) - (a_gain - 1) * cw - sq)
    else:
        raise ValueError("unknown biquad kind '%s'" % kind)
    a0 = a[0]
    return (b[0] / a0, b[1] / a0, b[2] / a0, a[1] / a0, a[2] / a0)


def biquad(x: np.ndarray, coeffs: tuple) -> np.ndarray:
    """Filters x (mono or stereo) through one biquad (transposed direct form II)."""
    arr = np.asarray(x, dtype=np.float64)
    if arr.ndim == 2:
        return np.stack([biquad(arr[:, c], coeffs) for c in range(arr.shape[1])], axis=1)
    b0, b1, b2, a1, a2 = (float(c) for c in coeffs)
    out = []
    append = out.append
    z1 = 0.0
    z2 = 0.0
    for s in arr.tolist():
        y = b0 * s + z1
        z1 = b1 * s - a1 * y + z2
        z2 = b2 * s - a2 * y
        append(y)
    return np.array(out, dtype=np.float64)


def filter_chain(x: np.ndarray, stages) -> np.ndarray:
    """Applies several biquads: stages = [(kind, freq, q[, gain_db]), ...]; uses the default rate
    unless a stage gives "rate" as a fifth element."""
    out = np.asarray(x, dtype=np.float64)
    for st in stages:
        kind, freq, q = st[0], st[1], st[2]
        gain = st[3] if len(st) > 3 else 0.0
        rate = st[4] if len(st) > 4 else DEFAULT_RATE
        out = biquad(out, biquad_coeffs(kind, freq, q, rate, gain))
    return out


def svf(x: np.ndarray, cutoff, q: float, rate: int = DEFAULT_RATE, mode: str = "lowpass") -> np.ndarray:
    """A topology-preserving (trapezoidal) state-variable filter with a fixed or per-sample
    cutoff in Hz. mode: lowpass | bandpass | highpass. Mono input."""
    arr = np.asarray(x, dtype=np.float64)
    n = arr.shape[0]
    fc = np.full(n, float(cutoff)) if np.isscalar(cutoff) else np.asarray(cutoff, dtype=np.float64)
    if fc.shape[0] != n:
        raise ValueError("per-sample cutoff must have n entries")
    g = np.tan(math.pi * np.clip(fc, 1.0, rate * 0.49) / rate).tolist()
    k = 1.0 / max(float(q), 1e-6)
    ic1 = 0.0
    ic2 = 0.0
    out = []
    append = out.append
    want = {"lowpass": 0, "bandpass": 1, "highpass": 2}.get(mode)
    if want is None:
        raise ValueError("unknown svf mode '%s'" % mode)
    for s, gi in zip(arr.tolist(), g):
        a1 = 1.0 / (1.0 + gi * (gi + k))
        a2 = gi * a1
        a3 = gi * a2
        v3 = s - ic2
        v1 = a1 * ic1 + a2 * v3
        v2 = ic2 + a2 * ic1 + a3 * v3
        ic1 = 2.0 * v1 - ic1
        ic2 = 2.0 * v2 - ic2
        if want == 0:
            append(v2)
        elif want == 1:
            append(v1)
        else:
            append(s - k * v1 - v2)
    return np.array(out, dtype=np.float64)


def fft_filter(x: np.ndarray, rate: int, response) -> np.ndarray:
    """Zero-phase circular filtering: multiplies the spectrum by response(freqs_hz) (a real gain
    per frequency). Circular, so a loop filtered this way stays seamless."""
    arr = np.asarray(x, dtype=np.float64)
    if arr.ndim == 2:
        return np.stack([fft_filter(arr[:, c], rate, response) for c in range(arr.shape[1])], axis=1)
    n = arr.shape[0]
    if n < 2:
        return arr.copy()
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    gain = np.asarray(response(freqs), dtype=np.float64)
    return np.fft.irfft(np.fft.rfft(arr) * gain, n)


def band_response(lo: float, hi: float, order: int = 2):
    """A Butterworth-like magnitude response between lo and hi Hz (lo 0 = low-pass only, hi 0 =
    high-pass only), for fft_filter."""
    def resp(f: np.ndarray) -> np.ndarray:
        g = np.ones_like(f)
        if hi > 0:
            g = g / np.sqrt(1.0 + (f / hi) ** (2 * order))
        if lo > 0:
            g = g / np.sqrt(1.0 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
        return g
    return resp


def fft_convolve(x: np.ndarray, ir: np.ndarray) -> np.ndarray:
    """Linear convolution of mono x with mono ir through the FFT (length len(x) + len(ir) - 1)."""
    a = np.asarray(x, dtype=np.float64)
    b = np.asarray(ir, dtype=np.float64)
    n = a.shape[0] + b.shape[0] - 1
    size = 1 << max(0, (n - 1).bit_length())
    out = np.fft.irfft(np.fft.rfft(a, size) * np.fft.rfft(b, size), size)
    return out[:n]


# --------------------------------------------------------------------------- loops


def loop_wrap(buf: np.ndarray, period: int) -> np.ndarray:
    """Folds everything past `period` frames back onto the start (circularly, as often as needed)
    and returns exactly `period` frames: events that ring past the loop point continue at its
    start, so the loop repeats without a seam (exact for mixed events)."""
    arr = np.asarray(buf, dtype=np.float64)
    if period <= 0:
        raise ValueError("period must be positive")
    out = np.array(arr[:period], copy=True)
    if out.shape[0] < period:
        pad = np.zeros((period - out.shape[0],) + arr.shape[1:])
        out = np.concatenate([out, pad])
    start = period
    while start < arr.shape[0]:
        chunk = arr[start:start + period]
        out[:chunk.shape[0]] += chunk
        start += period
    return out


def crossfade_loop(x: np.ndarray, fade_frames: int) -> np.ndarray:
    """Makes a continuous texture loop seamlessly: the last `fade_frames` are cross-faded
    (equal power) into the first ones; the result is len(x) - fade_frames long."""
    arr = np.asarray(x, dtype=np.float64)
    n = arr.shape[0]
    if fade_frames <= 0 or fade_frames >= n:
        raise ValueError("fade must be inside the signal")
    body = np.array(arr[:n - fade_frames], copy=True)
    tail = arr[n - fade_frames:]
    t = np.linspace(0.0, 1.0, fade_frames, endpoint=False)
    fin = np.sin(0.5 * math.pi * t)
    fout = np.cos(0.5 * math.pi * t)
    head = body[:fade_frames]
    body[:fade_frames] = (head.T * fin).T + (tail.T * fout).T
    return body


# --------------------------------------------------------------------------- levels


def peak(x: np.ndarray) -> float:
    a = np.asarray(x)
    return float(np.max(np.abs(a))) if a.size else 0.0


def peak_db(x: np.ndarray) -> float:
    return gain_to_db(peak(x))


def rms(x: np.ndarray) -> float:
    a = np.asarray(x, dtype=np.float64)
    return math.sqrt(float(np.mean(a * a))) if a.size else 0.0


def rms_db(x: np.ndarray) -> float:
    return gain_to_db(rms(x))


def normalize_peak(x: np.ndarray, target_db: float) -> np.ndarray:
    """Scales x so its peak is target_db dBFS (silence stays silence)."""
    p = peak(x)
    return np.asarray(x, dtype=np.float64) * (db_to_gain(target_db) / p) if p > 0.0 else np.asarray(x, dtype=np.float64)


def normalize_rms(x: np.ndarray, target_db: float, max_peak_db: float = -1.0) -> np.ndarray:
    """Scales x so its RMS is target_db dBFS, but never past max_peak_db dBFS at the peak."""
    r = rms(x)
    if r <= 0.0:
        return np.asarray(x, dtype=np.float64)
    out = np.asarray(x, dtype=np.float64) * (db_to_gain(target_db) / r)
    if peak(out) > db_to_gain(max_peak_db):
        out = normalize_peak(out, max_peak_db)
    return out


# ITU-R BS.1770's K-weighting as the standard gives it at 48 kHz: the +4 dB high shelf (stage 1)
# and the RLB high-pass (stage 2).
_K_RATE = 48000.0
_K_SHELF = ((1.53512485958697, -2.69169618940638, 1.19839281085285), (1.0, -1.69065929318241, 0.73248077421585))
_K_HIGH_PASS = ((1.0, -2.0, 1.0), (1.0, -1.99004745483398, 0.99007225036621))


def k_weighting(f: np.ndarray) -> np.ndarray:
    """The magnitude of ITU-R BS.1770's K-weighting at frequencies f (Hz): the standard's two
    48 kHz biquads (the high shelf and the RLB high-pass) evaluated at f, which is exact for every
    f below 24 kHz, so for every rate the generators use (P23: music and ambience are balanced by
    it; +0.69 dB at 997 Hz, so a full-scale 997 Hz sine in one channel reads -3.01 LUFS)."""
    f = np.clip(np.asarray(f, dtype=np.float64), 0.0, _K_RATE / 2.0)
    z1 = np.exp(-2j * np.pi * f / _K_RATE)
    gain = np.ones(f.shape, dtype=np.complex128)
    for b, a in (_K_SHELF, _K_HIGH_PASS):
        gain *= (b[0] + b[1] * z1 + b[2] * z1 * z1) / (a[0] + a[1] * z1 + a[2] * z1 * z1)
    return np.abs(gain)


def loudness_lufs(x: np.ndarray, rate: int, block_s: float = 0.4) -> float:
    """Integrated loudness in the manner of ITU-R BS.1770 (LUFS): K-weighting, 400 ms blocks with
    75 % overlap, an absolute gate at -70 and a relative gate 10 LU under the gated mean; channel
    powers summed. Silent input gives -120. Used to balance music stems and ambience by what is
    heard while they sound (a sparse melody is measured by its notes, not its rests)."""
    arr = np.asarray(x, dtype=np.float64)
    chans = [arr] if arr.ndim == 1 else [arr[:, c] for c in range(arr.shape[1])]
    power = None
    for ch in chans:
        k = fft_filter(ch, rate, k_weighting)
        power = k * k if power is None else power + k * k
    n = power.shape[0]
    blk = max(1, min(n, n_frames(block_s, rate)))
    hop = max(1, blk // 4)
    c = np.concatenate([[0.0], np.cumsum(power)])
    starts = np.arange(0, n - blk + 1, hop)
    z = (c[starts + blk] - c[starts]) / blk
    lk = -0.691 + 10.0 * np.log10(np.maximum(z, 1e-30))
    keep = z[lk > -70.0]
    if keep.size == 0:
        return -120.0
    rel = -0.691 + 10.0 * math.log10(float(np.mean(keep))) - 10.0
    keep = z[(lk > -70.0) & (lk > rel)]
    if keep.size == 0:
        return -120.0
    return -0.691 + 10.0 * math.log10(float(np.mean(keep)))


def normalize_lufs(x: np.ndarray, rate: int, target: float, max_peak_db: float = -1.0) -> np.ndarray:
    """Scales x so its loudness_lufs is `target`, but never past max_peak_db dBFS at the peak."""
    current = loudness_lufs(x, rate)
    if current <= -119.0:
        return np.asarray(x, dtype=np.float64)
    out = np.asarray(x, dtype=np.float64) * db_to_gain(target - current)
    if peak(out) > db_to_gain(max_peak_db):
        out = normalize_peak(out, max_peak_db)
    return out


def pan(mono: np.ndarray, position: float) -> np.ndarray:
    """Equal-power pan of a mono signal to stereo: position -1 (left) .. 1 (right)."""
    a = (max(-1.0, min(1.0, float(position))) + 1.0) * math.pi / 4.0
    m = np.asarray(mono, dtype=np.float64)
    return np.stack([m * math.cos(a), m * math.sin(a)], axis=1)


def mix_into(buf: np.ndarray, start: int, sig: np.ndarray, gain: float = 1.0) -> None:
    """Adds sig into buf at frame `start` (clipped at buf's end; a negative start drops the head)."""
    s = np.asarray(sig, dtype=np.float64)
    if start < 0:
        s = s[-start:]
        start = 0
    end = min(buf.shape[0], start + s.shape[0])
    if end > start:
        buf[start:end] += gain * s[:end - start]


# --------------------------------------------------------------------------- checks

SILENT_DB = -60.0
SEAM_FLOOR_DB = -50.0
SFX_MAX_S = 2.0


def check_signal(x: np.ndarray, rate: int, kind: str, loop: bool) -> list:
    """The problems of a rendered cue, or []: clipping (a peak at or above full scale), DC (the
    mean over 1 % of the peak), silence (a peak under -60 dBFS), an SFX longer than 2.0 s, and for
    loops a seam step larger than every other step and above -50 dBFS (a click at the loop
    point)."""
    problems = []
    arr = np.asarray(x, dtype=np.float64)
    if not np.all(np.isfinite(arr)):
        return ["not finite (NaN or infinite samples)"]
    p = peak(arr)
    if p >= 1.0:
        problems.append("clipping (peak %.3f)" % p)
    if p < db_to_gain(SILENT_DB):
        problems.append("silent (peak %.1f dBFS)" % gain_to_db(p))
    if p > 0.0:
        mean = np.abs(np.mean(arr, axis=0))
        if float(np.max(mean)) > 0.01 * p:
            problems.append("DC offset (mean %.4f)" % float(np.max(mean)))
    if kind == "sfx" and arr.shape[0] > SFX_MAX_S * rate + 0.5:
        problems.append("longer than %.1f s (%.3f s)" % (SFX_MAX_S, arr.shape[0] / rate))
    if loop and arr.shape[0] > 2:
        seam = np.max(np.abs(arr[0] - arr[-1]))
        inner = np.max(np.abs(np.diff(arr, axis=0)))
        if seam > inner + 1e-12 and seam > db_to_gain(SEAM_FLOOR_DB):
            problems.append("loop seam step %.1f dB above every other step" % gain_to_db(seam / max(inner, 1e-12)))
    return problems


# --------------------------------------------------------------------------- writers


def _as_frames(x: np.ndarray) -> np.ndarray:
    arr = np.asarray(x, dtype=np.float64)
    return arr[:, None] if arr.ndim == 1 else arr


def to_pcm16(x: np.ndarray) -> np.ndarray:
    """Rounds to 16-bit integers (no dither: deterministic), clipped to the range."""
    return np.clip(np.round(_as_frames(x) * 32767.0), -32768, 32767).astype("<i2")


def _riff(fmt_chunk: bytes, data: bytes) -> bytes:
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt_chunk)) + fmt_chunk
    body += b"data" + struct.pack("<I", len(data)) + data
    if len(data) % 2:
        body += b"\x00"
    return b"RIFF" + struct.pack("<I", len(body)) + body


def wav_bytes_pcm16(x: np.ndarray, rate: int) -> bytes:
    """A 16-bit PCM WAV file (fmt and data chunks only) as bytes."""
    pcm = to_pcm16(x)
    ch = pcm.shape[1]
    fmt = struct.pack("<HHIIHH", 1, ch, int(rate), int(rate) * ch * 2, ch * 2, 16)
    return _riff(fmt, pcm.tobytes())


def wav_bytes_f32(x: np.ndarray, rate: int) -> bytes:
    """A 32-bit IEEE float WAV file as bytes (the encoder's input; its hash is the master hash of
    music and ambience)."""
    fr = _as_frames(x).astype("<f4")
    ch = fr.shape[1]
    fmt = struct.pack("<HHIIHH", 3, ch, int(rate), int(rate) * ch * 4, ch * 4, 32)
    return _riff(fmt, fr.tobytes())


def read_wav_pcm16(data: bytes) -> tuple:
    """(frames as float64 (n, channels), rate) of a 16-bit PCM WAV made by wav_bytes_pcm16."""
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a WAV file")
    pos = 12
    rate = 0
    ch = 1
    while pos + 8 <= len(data):
        cid = data[pos:pos + 4]
        size = struct.unpack("<I", data[pos + 4:pos + 8])[0]
        body = data[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            fmt_tag, ch, rate = struct.unpack("<HHI", body[:8])
            if fmt_tag != 1:
                raise ValueError("not 16-bit PCM")
        elif cid == b"data":
            pcm = np.frombuffer(body, dtype="<i2").astype(np.float64) / 32767.0
            return pcm.reshape(-1, ch), rate
        pos += 8 + size + (size % 2)
    raise ValueError("no data chunk")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def export_flac(x: np.ndarray, rate: int, path: Path) -> None:
    """Writes a lossless FLAC master through ffmpeg (bit-exact flags)."""
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        raise RuntimeError("ffmpeg is needed to export FLAC masters")
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        src = Path(tmp) / "master.wav"
        src.write_bytes(wav_bytes_f32(x, rate))
        subprocess.run([ffmpeg, "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
                        "-fflags", "+bitexact", "-i", str(src), "-map_metadata", "-1",
                        "-c:a", "flac", "-sample_fmt", "s32", "-flags:a", "+bitexact",
                        "-fflags", "+bitexact", str(path)], check=True)
