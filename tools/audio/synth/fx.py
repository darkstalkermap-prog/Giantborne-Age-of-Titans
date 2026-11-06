"""Signal processing for the sound-effect families (P21; plan M6-M9 section 4.2): vectorised numpy,
float64, deterministic, with no per-sample Python loop, so the whole SFX library renders in a few
seconds on one core (build_audio.py --verify renders it twice per check).

* lengths: frames, padding, mixing at an offset
* static filters for one-shots: FFT shaping with zero padding (nothing wraps), zero or minimum
  phase (minimum phase keeps transients sharp: no pre-ringing), with band, shelf and tilt
  responses
* time-varying filters: an STFT (Hann, hop frame / 4) whose frames are multiplied by a gain per
  frame and frequency, then overlap-added (swept band-passes for swings and threat sweeps, moving
  formants for voices, closing low-passes)
* modal synthesis: impulse responses of damped sinusoids (closed form), excited by convolution
* grains: short windowed bursts scattered in time (debris, crunch, splinters, grit)
* dynamics: soft clipping, an envelope follower-free transient shaper, fades
* space: a short synthetic outdoor reflection pattern and a valley echo for the big sounds
* finishing: DC removal, trailing-silence trim and the end fade every effect gets

Every random draw comes from the generator passed in (the cue's own seeded PCG64).
"""

from __future__ import annotations

import math

import numpy as np

from synth import core

RATE = core.DEFAULT_RATE
TWO_PI = 2.0 * math.pi


# --------------------------------------------------------------------------- lengths


def frames(seconds: float, rate: int = RATE) -> int:
    return max(1, core.n_frames(seconds, rate))


def fit(x: np.ndarray, n: int) -> np.ndarray:
    """x cut or zero-padded to exactly n frames."""
    a = np.asarray(x, dtype=np.float64)
    if a.shape[0] >= n:
        return np.array(a[:n], copy=True)
    return np.concatenate([a, np.zeros(n - a.shape[0])])


def place(buf: np.ndarray, at_s: float, sig: np.ndarray, gain: float = 1.0, rate: int = RATE) -> None:
    """Adds sig into buf starting at at_s seconds (clipped at the end)."""
    core.mix_into(buf, int(round(at_s * rate)), sig, gain)


def seal(x: np.ndarray, rate: int = RATE, seconds: float = 0.012) -> np.ndarray:
    """A copy whose last `seconds` fade to zero (a raised-cosine): cut a still-sounding render
    without a click before it goes through further processing."""
    y = np.array(x, dtype=np.float64, copy=True)
    m = min(y.shape[0], frames(seconds, rate))
    if m > 1:
        y[-m:] *= 0.5 * (1.0 + np.cos(np.linspace(0.0, math.pi, m)))
    return y


def match_rms(sig: np.ndarray, ref: np.ndarray, rel_db: float, window_s: float = 0.1, rate: int = RATE) -> np.ndarray:
    """sig scaled so that its RMS over its loudest window_s is rel_db relative to ref's (layers
    balanced by energy, not by their peaks: a click and a long thump peak alike)."""
    def loud(x):
        a = np.asarray(x, dtype=np.float64)
        w = min(a.shape[0], frames(window_s, rate))
        c = np.concatenate([[0.0], np.cumsum(a * a)])
        return math.sqrt(max(float(np.max(c[w:] - c[:-w])) / max(w, 1), 0.0))
    s_l = loud(sig)
    if s_l <= 0.0:
        return np.asarray(sig, dtype=np.float64)
    return np.asarray(sig, dtype=np.float64) * (loud(ref) * 10.0 ** (rel_db / 20.0) / s_l)


def mix(n: int, *parts) -> np.ndarray:
    """Sums (signal, gain) pairs or signals into n frames."""
    out = np.zeros(n)
    for p in parts:
        sig, gain = (p if isinstance(p, tuple) else (p, 1.0))
        core.mix_into(out, 0, sig, gain)
    return out


def t_axis(n: int, rate: int = RATE) -> np.ndarray:
    return np.arange(n, dtype=np.float64) / float(rate)


# --------------------------------------------------------------------------- envelopes


def env_ad(n: int, rate: int, attack_s: float, tau_s: float, curve: float = 1.0) -> np.ndarray:
    """A linear (curve 1) or curved attack over attack_s, then an exponential decay of time
    constant tau_s."""
    t = t_axis(n, rate)
    a = max(attack_s, 1e-5)
    rise = np.clip(t / a, 0.0, 1.0) ** curve
    fall = np.exp(-np.maximum(t - a, 0.0) / max(tau_s, 1e-6))
    return rise * fall


def env_swell(n: int, rate: int, peak_s: float, rise_pow: float = 2.0, fall_tau_s: float = 0.05) -> np.ndarray:
    """A swell: (t / peak)^rise_pow up to the peak, then an exponential fall."""
    t = t_axis(n, rate)
    p = max(peak_s, 1e-4)
    up = np.clip(t / p, 0.0, 1.0) ** rise_pow
    down = np.exp(-np.maximum(t - p, 0.0) / max(fall_tau_s, 1e-6))
    return up * down


def env_points(points, n: int, rate: int = RATE) -> np.ndarray:
    return core.envelope(points, n, rate)


def glide(n: int, rate: int, start: float, end: float, tau_s: float) -> np.ndarray:
    """A value gliding exponentially from start to end (time constant tau_s): pitch drops."""
    return end + (start - end) * np.exp(-t_axis(n, rate) / max(tau_s, 1e-6))


# --------------------------------------------------------------------------- spectral responses


def _f(f: np.ndarray) -> np.ndarray:
    return np.maximum(f, 1e-3)


def r_lowpass(fc: float, order: float = 2.0):
    return lambda f: 1.0 / np.sqrt(1.0 + (_f(f) / fc) ** (2 * order))


def r_highpass(fc: float, order: float = 2.0):
    return lambda f: 1.0 / np.sqrt(1.0 + (fc / _f(f)) ** (2 * order))


def r_band(lo: float, hi: float, order: float = 2.0):
    lp = r_lowpass(hi, order) if hi > 0 else (lambda f: np.ones_like(f))
    hp = r_highpass(lo, order) if lo > 0 else (lambda f: np.ones_like(f))
    return lambda f: lp(f) * hp(f)


def r_peak(fc: float, q: float, gain_db: float):
    """A bell boost or cut of gain_db at fc (log-frequency Gaussian of width ~ 1 / q octaves)."""
    g = 10.0 ** (gain_db / 20.0)
    width = 1.0 / max(q, 0.1)

    def resp(f):
        d = np.log2(_f(f) / fc) / width
        return 1.0 + (g - 1.0) * np.exp(-0.5 * (d * 2.0) ** 2)
    return resp


def r_tilt(pivot: float, db_per_octave: float):
    return lambda f: (_f(f) / pivot) ** (db_per_octave / 6.0206)


def r_resonance(fc: float, bw: float):
    """The magnitude of a two-pole resonator at fc (Hz) with bandwidth bw, 1 at DC."""
    b = bw * 0.5

    def resp(f):
        num = fc * fc + b * b
        den = np.sqrt(((f - fc) ** 2 + b * b) * ((f + fc) ** 2 + b * b))
        return num / np.maximum(den, 1e-9)
    return resp


def r_product(*responses):
    def resp(f):
        g = np.ones_like(f)
        for r in responses:
            g = g * r(f)
        return g
    return resp


# --------------------------------------------------------------------------- static filtering


def _size_for(n: int) -> int:
    return 1 << max(10, (int(n) - 1).bit_length())


def _min_phase(mag: np.ndarray, size: int) -> np.ndarray:
    """A minimum-phase spectrum (rfft layout, FFT size `size`) with the magnitude `mag`
    (homomorphic: fold the real cepstrum). The magnitude floor (-100 dB) keeps the cepstrum short;
    shape() uses an FFT at least four times the output, so the little cepstral aliasing there is
    lands beyond the frames it keeps."""
    logmag = np.log(np.maximum(mag, 1e-5))
    cep = np.fft.irfft(logmag, size)
    fold = np.zeros(size)
    fold[0] = 1.0
    fold[1:size // 2] = 2.0
    fold[size // 2] = 1.0
    return np.exp(np.fft.rfft(cep * fold))


def shape(x: np.ndarray, response, rate: int = RATE, phase: str = "min", tail_s: float = 0.0) -> np.ndarray:
    """Filters a one-shot by a magnitude response (a function of frequency in Hz), zero-padded
    so nothing wraps; phase "min" (causal, no pre-ringing) or "zero" (symmetric). The result is
    len(x) + tail_s long."""
    a = np.asarray(x, dtype=np.float64)
    n = a.shape[0] + frames(tail_s, rate) if tail_s > 0 else a.shape[0]
    size = _size_for(n + 4096) if phase == "zero" else _size_for(4 * (n + 2048))
    freqs = np.fft.rfftfreq(size, 1.0 / rate)
    mag = np.asarray(response(freqs), dtype=np.float64)
    spec = np.fft.rfft(a, size)
    if phase == "zero":
        y = np.fft.irfft(spec * mag, size)
    else:
        y = np.fft.irfft(spec * _min_phase(mag, size), size)
    return y[:n]


def lowpass(x, fc, order=2.0, rate=RATE, phase="min"):
    return shape(x, r_lowpass(fc, order), rate, phase)


def highpass(x, fc, order=2.0, rate=RATE, phase="min"):
    return shape(x, r_highpass(fc, order), rate, phase)


def bandpass(x, lo, hi, order=2.0, rate=RATE, phase="min"):
    return shape(x, r_band(lo, hi, order), rate, phase)


def wander(n: int, rng: np.random.Generator, hz: float, rate: int = RATE) -> np.ndarray:
    """A smooth random curve (low-passed noise at about hz), unit RMS: drifts, gates, wobbles."""
    w = shape(rng.standard_normal(n), r_lowpass(hz, 1.0), rate, "zero")
    r = core.rms(w)
    return w / r if r > 0 else w


def noise(n: int, rng: np.random.Generator, lo: float = 0.0, hi: float = 0.0, rate: int = RATE,
          color: str = "white") -> np.ndarray:
    """Noise (white, pink or brown) band-limited to [lo, hi] Hz (0 = open), unit RMS."""
    if color == "pink":
        x = core.pink(n, rng)
    elif color == "brown":
        x = core.brown(n, rng)
    else:
        x = core.white(n, rng)
    if lo > 0 or hi > 0:
        x = shape(x, r_band(lo, hi, 2.0), rate, phase="zero")
    r = core.rms(x)
    return x / r if r > 0 else x


# --------------------------------------------------------------------------- time-varying filtering


def stft_shape(x: np.ndarray, gains_fn, rate: int = RATE, frame: int = 512) -> np.ndarray:
    """Time-varying filtering: a Hann STFT (hop frame / 4) whose spectra are multiplied by
    gains_fn(freqs, times) -> array (frames, bins), then inverse transformed and overlap-added
    with window-sum normalisation. The output has the input's length."""
    a = np.asarray(x, dtype=np.float64)
    n = a.shape[0]
    hop = frame // 4
    padded = np.concatenate([np.zeros(frame), a, np.zeros(frame + hop)])
    count = (padded.shape[0] - frame) // hop + 1
    idx = np.arange(frame)[None, :] + hop * np.arange(count)[:, None]
    win = np.hanning(frame + 1)[:frame]
    spec = np.fft.rfft(padded[idx] * win, axis=1)
    freqs = np.fft.rfftfreq(frame, 1.0 / rate)
    times = (hop * np.arange(count) + frame * 0.5 - frame) / float(rate)
    gains = np.asarray(gains_fn(freqs, times), dtype=np.float64)
    out_frames = np.fft.irfft(spec * gains, frame, axis=1) * win
    flat = idx.ravel()
    out = np.bincount(flat, weights=out_frames.ravel(), minlength=padded.shape[0])
    wsum = np.bincount(flat, weights=np.tile(win * win, count), minlength=padded.shape[0])
    out = out / np.maximum(wsum, 1e-3)
    return out[frame:frame + n]


def track(points, times: np.ndarray) -> np.ndarray:
    """A parameter track: piecewise-linear through (time_s, value) points, sampled at times."""
    pts = sorted((float(t), float(v)) for t, v in points)
    return np.interp(times, [p[0] for p in pts], [p[1] for p in pts])


def log_track(points, times: np.ndarray) -> np.ndarray:
    """A frequency track interpolated in log space (glides sound even)."""
    pts = sorted((float(t), math.log(max(float(v), 1e-3))) for t, v in points)
    return np.exp(np.interp(times, [p[0] for p in pts], [p[1] for p in pts]))


def swept_band(x: np.ndarray, centre_points, q_points, rate: int = RATE, frame: int = 512,
               floor: float = 0.0) -> np.ndarray:
    """A band-pass whose centre (Hz, log-interpolated) and Q follow the given (time, value)
    points; floor lets some broadband signal through (0..1)."""
    def gains(freqs, times):
        c = log_track(centre_points, times)[:, None]
        q = track(q_points, times)[:, None]
        f = np.maximum(freqs[None, :], 1e-3)
        # a band of width c / q (octave-symmetric Lorentzian in log frequency)
        oct_width = np.log2(1.0 + 1.0 / np.maximum(q, 0.05))
        d = np.log2(f / c) / np.maximum(oct_width, 1e-3)
        g = 1.0 / (1.0 + d * d)
        return floor + (1.0 - floor) * g
    return stft_shape(x, gains, rate, frame)


def moving_lowpass(x: np.ndarray, cutoff_points, rate: int = RATE, order: float = 2.0, frame: int = 512) -> np.ndarray:
    """A low-pass whose cutoff (Hz, log-interpolated) follows (time, value) points."""
    def gains(freqs, times):
        c = log_track(cutoff_points, times)[:, None]
        return 1.0 / np.sqrt(1.0 + (np.maximum(freqs[None, :], 1e-3) / c) ** (2 * order))
    return stft_shape(x, gains, rate, frame)


# --------------------------------------------------------------------------- modal synthesis


def modal_ir(freqs, taus, amps, n: int, rate: int = RATE, phases=None) -> np.ndarray:
    """The impulse response of a bank of damped sinusoids: sum a_i exp(-t / tau_i)
    sin(2 pi f_i t + phi_i). Partials at or above Nyquist are dropped."""
    f = np.asarray(freqs, dtype=np.float64)
    tau = np.asarray(taus, dtype=np.float64)
    amp = np.asarray(amps, dtype=np.float64)
    ph = np.zeros_like(f) if phases is None else np.asarray(phases, dtype=np.float64)
    keep = f < rate * 0.48
    f, tau, amp, ph = f[keep], tau[keep], amp[keep], ph[keep]
    if f.size == 0:
        return np.zeros(n)
    t = t_axis(n, rate)[:, None]
    return np.sum(amp[None, :] * np.exp(-t / np.maximum(tau[None, :], 1e-5))
                  * np.sin(TWO_PI * f[None, :] * t + ph[None, :]), axis=1)


def excite(excitation: np.ndarray, ir: np.ndarray, n: int) -> np.ndarray:
    """Convolves an excitation with an impulse response, cut to n frames."""
    return fit(core.fft_convolve(excitation, ir), n)


def partials(f0: float, ratios, rng: np.random.Generator | None = None, detune: float = 0.0) -> np.ndarray:
    """f0 x ratios, each detuned by up to +-detune (relative) when a generator is given."""
    r = np.asarray(ratios, dtype=np.float64)
    if rng is not None and detune > 0:
        r = r * (1.0 + rng.uniform(-detune, detune, r.shape[0]))
    return f0 * r


# --------------------------------------------------------------------------- grains


class NoiseBank:
    """Band-limited noise in octave-ish bands, cut into grains: a grain at centre fc takes a
    window of the band nearest fc (fast: the bands are filtered once per cue)."""

    def __init__(self, rng: np.random.Generator, seconds: float = 1.0, rate: int = RATE,
                 centres=(150.0, 300.0, 600.0, 1200.0, 2400.0, 4800.0, 8000.0)):
        self.rate = rate
        self.centres = np.array([c for c in centres if c < rate * 0.45], dtype=np.float64)
        n = frames(seconds, rate)
        self.n = n
        self.bands = []
        for c in self.centres:
            self.bands.append(noise(n, rng, c / 1.5, c * 1.5, rate))
        self.rng = rng

    def grain(self, fc: float, length_s: float, attack_s: float = 0.0005, tau_s: float | None = None) -> np.ndarray:
        k = int(np.argmin(np.abs(np.log(self.centres / max(fc, 1.0)))))
        m = min(frames(length_s, self.rate), self.n - 1)
        start = int(self.rng.integers(0, self.n - m))
        g = np.array(self.bands[k][start:start + m], copy=True)
        tau = tau_s if tau_s is not None else length_s * 0.3
        return g * env_ad(m, self.rate, attack_s, tau)


def scatter(n: int, rng: np.random.Generator, times, make_grain, gains, rate: int = RATE) -> np.ndarray:
    """Places make_grain(i) at each time (s) with its gain."""
    out = np.zeros(n)
    for i, (t, g) in enumerate(zip(times, gains)):
        core.mix_into(out, int(round(float(t) * rate)), make_grain(i), float(g))
    return out


def poisson_times(rng: np.random.Generator, start_s: float, end_s: float, rate_fn, max_count: int = 400):
    """Event times of a Poisson process whose rate (events per second) is rate_fn(t) (thinned
    against its maximum over the span)."""
    ts = np.linspace(start_s, end_s, 64)
    peak = max(float(np.max([rate_fn(t) for t in ts])), 1e-6)
    out = []
    t = start_s
    while t < end_s and len(out) < max_count:
        t += float(rng.exponential(1.0 / peak))
        if t >= end_s:
            break
        if rng.uniform() * peak <= rate_fn(t):
            out.append(t)
    return out


# --------------------------------------------------------------------------- dynamics and colour


def soft_clip(x: np.ndarray, drive: float = 2.0) -> np.ndarray:
    """tanh saturation, normalised so a full-scale input stays near full scale."""
    p = core.peak(x)
    if p <= 0:
        return np.asarray(x, dtype=np.float64)
    y = np.tanh(drive * np.asarray(x) / p) / math.tanh(drive)
    return y * p


def ring_mod(x: np.ndarray, freq, rate: int = RATE, depth: float = 1.0) -> np.ndarray:
    n = np.asarray(x).shape[0]
    car = core.sine(freq, n, rate)
    return np.asarray(x) * (1.0 - depth + depth * car)


def tremolo(x: np.ndarray, freq: float, depth: float, rate: int = RATE, phase: float = 0.0) -> np.ndarray:
    n = np.asarray(x).shape[0]
    return np.asarray(x) * (1.0 - depth * 0.5 * (1.0 + np.sin(TWO_PI * freq * t_axis(n, rate) + phase)))


# --------------------------------------------------------------------------- space


def reflections(x: np.ndarray, rng: np.random.Generator, rate: int = RATE, count: int = 6,
                spread_s: float = 0.06, level: float = 0.25, damp_hz: float = 3000.0) -> np.ndarray:
    """A few early reflections (outdoor ground and nearby surfaces): delayed, damped copies."""
    a = seal(x, rate, 0.004)
    ir = np.zeros(frames(spread_s + 0.01, rate))
    ir[0] = 1.0
    for i in range(count):
        d = int(round(rng.uniform(0.008, spread_s) * rate))
        ir[min(d, ir.shape[0] - 1)] += level * rng.uniform(0.4, 1.0) * (0.8 ** i) * (1 if rng.uniform() < 0.5 else -1)
    wet = core.fft_convolve(a, ir)[:a.shape[0] + ir.shape[0]]
    return lowpass(wet, damp_hz) if damp_hz > 0 else wet


def valley_echo(x: np.ndarray, rng: np.random.Generator, rate: int = RATE, delay_s: float = 0.28,
                level: float = 0.3, damp_hz: float = 900.0, repeats: int = 2, tail_s: float = 0.0) -> np.ndarray:
    """The slap of a big sound off far slopes: low-passed, delayed copies (each repeat later and
    quieter), smeared a little so they read as a landscape rather than a delay line."""
    a = seal(x, rate, 0.004)
    n = a.shape[0] + frames(tail_s, rate)
    out = fit(a, n)
    smear_n = frames(0.03, rate)
    smear = noise(smear_n, rng) * env_ad(smear_n, rate, 0.002, 0.008)
    smear[0] += 4.0
    smear /= np.sum(np.abs(smear))
    src = lowpass(a, damp_hz)
    src = core.fft_convolve(src, smear)
    for i in range(repeats):
        d = delay_s * (1.0 + 0.55 * i) * rng.uniform(0.92, 1.08)
        core.mix_into(out, int(round(d * rate)), src, level * (0.45 ** i))
    return out


def distant(x: np.ndarray, rng: np.random.Generator, rate: int = RATE, cutoff: float = 600.0,
            soften_s: float = 0.025, tail_s: float = 0.25) -> np.ndarray:
    """A far version of a big sound (plan section 4.4: played instead when the source starts
    beyond half its class's range): low-passed (the air takes the highs), its attack softened,
    a little longer smear of reflections - the distance filter does not exist for web samples,
    so distance is baked."""
    a = seal(x, rate, 0.01)
    n = a.shape[0] + frames(tail_s, rate)
    y = lowpass(fit(a, n), cutoff, 2.0, rate)
    k = frames(soften_s, rate)
    y[:k] *= np.linspace(0.0, 1.0, k) ** 1.5
    smear_n = frames(0.12, rate)
    smear = noise(smear_n, rng) * env_ad(smear_n, rate, 0.01, 0.04)
    smear[0] += 6.0
    smear /= np.sum(np.abs(smear))
    return core.fft_convolve(y, smear)[:n]


# --------------------------------------------------------------------------- finishing


def dc_block(x: np.ndarray, rate: int = RATE, fc: float = 18.0) -> np.ndarray:
    """Removes DC and sub-audio drift: the classic one-pole DC blocker y[n] = x[n] - x[n-1] +
    R y[n-1] (R = 1 - 2 pi fc / rate), computed exactly as a convolution with its impulse
    response truncated at -120 dB (causal, no ringing, no wrap)."""
    a = np.asarray(x, dtype=np.float64)
    r = 1.0 - TWO_PI * fc / rate
    taps = int(math.ceil(math.log(1e-6) / math.log(r)))
    h = r ** np.arange(taps, dtype=np.float64)
    d = np.diff(a, prepend=0.0)
    return core.fft_convolve(d, h)[:a.shape[0]]


def trim_tail(x: np.ndarray, rate: int = RATE, floor_db: float = -54.0, min_s: float = 0.04,
              hold_s: float = 0.01) -> np.ndarray:
    """Cuts trailing frames that stay under floor_db (relative to the peak) - they cost bytes
    and add nothing - keeping hold_s after the last louder frame."""
    a = np.asarray(x, dtype=np.float64)
    p = core.peak(a)
    if p <= 0:
        return a
    thr = p * 10.0 ** (floor_db / 20.0)
    loud = np.nonzero(np.abs(a) >= thr)[0]
    if loud.size == 0:
        return a
    end = min(a.shape[0], int(loud[-1]) + frames(hold_s, rate))
    return a[:max(end, frames(min_s, rate))]


def end_level_db(x: np.ndarray, rate: int = RATE, window_s: float = 0.02) -> float:
    """The RMS level of the last window_s relative to the peak (dB)."""
    a = np.asarray(x, dtype=np.float64)
    tail = a[-frames(window_s, rate):]
    return core.gain_to_db(core.rms(tail) / max(core.peak(a), 1e-12))


def finish(x: np.ndarray, rate: int = RATE, fade_in_s: float = 0.0, fade_out_s: float = 0.012,
           floor_db: float = -50.0, max_s: float = 1.98) -> np.ndarray:
    """The last step of every effect: DC removed, the silent tail trimmed, at most max_s long,
    a short fade so it starts and ends at zero (no click). When the sound is still loud where it
    is cut (above -40 dB), the end fades over up to a fifth of its length (an exponential taper)
    instead, so a ring is never chopped."""
    y = dc_block(np.asarray(x, dtype=np.float64), rate)
    y = trim_tail(y, rate, floor_db)
    y = y[:frames(max_s, rate)]
    dur = y.shape[0] / rate
    if end_level_db(y, rate) > -40.0:
        taper_n = frames(min(0.2 * dur, 0.3), rate)
        k = np.linspace(0.0, 1.0, taper_n)
        y[-taper_n:] *= np.exp(-5.0 * k) * (1.0 - k)
    y = core.fade(y, rate, fade_in_s, min(fade_out_s, dur * 0.5))
    # the mean of a one-shot after a high-pass is tiny but not zero; take it out exactly so the
    # build's DC check (mean under 1 % of the peak) never trips on a short click
    m = float(np.mean(y))
    if abs(m) > 0.0:
        win = np.hanning(y.shape[0] + 2)[1:-1]
        y = y - m * win / max(float(np.mean(win)), 1e-9)
    return y
