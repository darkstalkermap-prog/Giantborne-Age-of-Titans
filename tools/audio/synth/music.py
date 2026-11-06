"""The score's synthesis (P23; plan M6-M9 sections 4.2 and 4.3): instruments, a seeded modal phrase
writer, and rendering into sample-exact loops and one-shots (numpy, float64, single-threaded).

* pitch: modal scale degrees (D dorian for the Valley's zone frame, D aeolian for the Ogre King)
  turned into MIDI notes, with accidentals for the odd leading tone
* instruments, each rendering one note into a mono array that includes its release tail: a
  plucked lute (additive strings through a wooden body), a low flute (a breathy near-sine with
  a chiff and a growing vibrato), horns and low brass (additive harmonics that brighten with
  loudness, a scoop into the note), a vowel choir (additive voices under formant envelopes,
  detuned, with vibrato), warm and dark pads (detuned band-limited saws), a tremolo string
  ensemble, bells, and drums (frame drum, taiko, toms, rim, shaker, a metal crash)
* the phrase writer: a set's motif - a one-bar cell of (beat, length, scale step) - is stated,
  sequenced, inverted or augmented on an anchor degree bar by bar, or a bar is written out; the
  cue's seed adds ornaments (grace notes and turns before long notes), velocity arcs and a
  little timing; every variant of a set keeps its phrases inside its four-bar segments (the
  first note after the segment's downbeat, the last released before its end), so the melody
  scheduler can switch variants at any segment boundary
* rendering: events are mixed into a buffer one loop long plus their tails, the tails are
  folded onto the head (core.loop_wrap) and the reverb is a circular convolution, so every loop
  repeats sample-exactly with no seam; one-shots get a linear reverb tail and an end fade

Every random draw comes from the generator passed in (the cue's own seeded PCG64); nothing reads
the clock or the global random state.
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx, instruments

RATE = core.DEFAULT_RATE
TWO_PI = 2.0 * math.pi

# --------------------------------------------------------------------------- pitch

D4 = 62
DORIAN = (0, 2, 3, 5, 7, 9, 10)     # D E F G A B C
AEOLIAN = (0, 2, 3, 5, 7, 8, 10)    # D E F G A Bb C
NOTE_NAMES = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def degree_midi(degree: int, scale=DORIAN, tonic: int = D4, accidental: int = 0) -> int:
    """The MIDI note of a scale degree counted from the tonic (0 = the tonic, 7 = an octave up,
    -1 = the step below), plus an accidental in semitones."""
    octave, step = divmod(int(degree), 7)
    return int(tonic + 12 * octave + scale[step] + accidental)


def name_midi(name: str) -> int:
    """'D4' -> 62, 'C#5' -> 73, 'Bb2' -> 46."""
    letter = name[0].upper()
    rest = name[1:]
    acc = 0
    while rest and rest[0] in "#b":
        acc += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return 12 * (int(rest) + 1) + NOTE_NAMES[letter] + acc


def hz(midi: float) -> float:
    return core.midi_hz(midi)


# --------------------------------------------------------------------------- small helpers


def frames(seconds: float, rate: int = RATE) -> int:
    return max(0, int(round(float(seconds) * rate)))


def beat_s(bpm: float) -> float:
    return 60.0 / float(bpm)


def env_note(n: int, rate: int, attack_s: float, hold_s: float, release_s: float,
             curve: float = 1.0) -> np.ndarray:
    """A note envelope: a smooth attack (raised cosine), held at 1 until hold_s, then an
    exponential-like release over release_s (reaching zero at the end of the array or of the
    release, whichever comes first)."""
    t = fx.t_axis(n, rate)
    a = max(attack_s, 1e-4)
    att = np.where(t < a, 0.5 - 0.5 * np.cos(math.pi * np.clip(t / a, 0.0, 1.0)), 1.0)
    r = max(release_s, 1e-4)
    rel_t = np.clip((t - hold_s) / r, 0.0, 1.0)
    rel = np.where(t <= hold_s, 1.0, (1.0 - rel_t) ** (2.0 * curve))
    return att * rel


def vibrato(n: int, rate: int, rng: np.random.Generator, hz_: float, cents: float, delay_s: float,
            ramp_s: float = 0.4) -> np.ndarray:
    """A pitch ratio curve: a vibrato of `cents` that grows in after delay_s, with a slow random
    wander in its rate and depth."""
    t = fx.t_axis(n, rate)
    grow = np.clip((t - delay_s) / max(ramp_s, 1e-3), 0.0, 1.0)
    rate_wobble = 1.0 + 0.04 * np.sin(TWO_PI * 0.37 * t + rng.uniform(0, TWO_PI))
    phase = TWO_PI * np.cumsum(hz_ * rate_wobble) / rate + rng.uniform(0, TWO_PI)
    depth = cents * grow * (1.0 + 0.15 * np.sin(TWO_PI * 0.23 * t + rng.uniform(0, TWO_PI)))
    return 2.0 ** (depth * np.sin(phase) / 1200.0)


def additive(freq: np.ndarray, amps: np.ndarray, rate: int, rng: np.random.Generator,
             max_hz: float = 9000.0) -> np.ndarray:
    """A sum of harmonics k = 1..len(amps) of a per-sample fundamental `freq`; amps is
    (harmonics, n) or (harmonics,). Harmonics above max_hz (or Nyquist) are skipped."""
    n = freq.shape[0]
    base = np.cumsum(freq) / rate
    out = np.zeros(n)
    top = min(max_hz, rate * 0.46)
    fmax = float(np.max(freq))
    for k in range(1, amps.shape[0] + 1):
        if fmax * k >= top:
            break
        a = amps[k - 1]
        out += a * np.sin(TWO_PI * k * base + rng.uniform(0, TWO_PI))
    return out


def wavetable(weights, rng: np.random.Generator, size: int = 2048) -> np.ndarray:
    """One cycle of a waveform with harmonic amplitudes `weights` (random phases), size + 1
    samples (the last repeats the first, for interpolation)."""
    x = np.arange(size, dtype=np.float64) / size
    table = np.zeros(size)
    for k, w in enumerate(weights, start=1):
        if w > 0.0:
            table += w * np.sin(TWO_PI * k * x + rng.uniform(0, TWO_PI))
    return np.concatenate([table, table[:1]])


def table_osc(table: np.ndarray, freq: np.ndarray, rate: int, phase: float = 0.0) -> np.ndarray:
    """Plays a wavetable (from wavetable()) at a per-sample frequency, linearly interpolated: the
    cost does not grow with the number of harmonics (choirs, long pads)."""
    size = table.shape[0] - 1
    ph = (phase + np.cumsum(freq) / rate) % 1.0
    idx = ph * size
    i0 = np.floor(idx).astype(np.int64)
    frac = idx - i0
    return table[i0] + frac * (table[i0 + 1] - table[i0])


def formant_weights(f0: float, count: int, formants, bandwidths, tilt: float = 0.0) -> np.ndarray:
    """Amplitude weights of harmonics 1..count of f0 under a sum of resonance peaks (a vowel or
    a body), with an optional spectral tilt in dB per octave."""
    k = np.arange(1, count + 1, dtype=np.float64)
    f = k * f0
    g = np.zeros(count)
    for fc, bw in zip(formants, bandwidths):
        g += 1.0 / (1.0 + ((f - fc) / (0.5 * bw)) ** 2)
    g += 0.02
    if tilt:
        g *= 10.0 ** (tilt * np.log2(np.maximum(f, 1.0) / 500.0) / 20.0)
    return g


# --------------------------------------------------------------------------- tonal instruments

LUTE_BODY = ((210.0, 1.0, 5.0), (480.0, 0.7, 4.0), (1300.0, 0.45, 3.0), (2900.0, 0.25, 2.5))


def lute(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, ring_s: float = 1.1,
         bright: float = 0.85, rate: int = RATE) -> np.ndarray:
    """A plucked lute string: instruments.pluck through a wooden body (four resonances), a small
    finger noise at the attack, damped by the hand after dur_s (it rings for at most ring_s)."""
    total = min(dur_s + 0.35, ring_s + 0.35)
    n = frames(total + 0.05, rate)
    tau = 0.55 * ring_s * (440.0 / max(f0, 80.0)) ** 0.35
    s = instruments.pluck(rng, n, rate, f0, tau, harmonics=18, bright=bright + 0.25 * (1.0 - vel),
                          bend=0.004, inharm=0.0003)
    resp = fx.r_product(*[fx.r_peak(fc, q, g) for fc, g, q in LUTE_BODY])
    s = fx.shape(s, resp, rate, phase="min")[:n]
    noise = fx.noise(n, rng, 1500.0, 6000.0, rate) * fx.env_ad(n, rate, 0.0005, 0.006) * 0.25
    s = s / max(core.peak(s), 1e-9) + noise
    damp = env_note(n, rate, 0.002, min(dur_s, ring_s), 0.25)
    return s * damp * vel


def flute(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, breath: float = 0.22,
          vib_cents: float = 14.0, rate: int = RATE) -> np.ndarray:
    """A low wooden flute: a near-sine with weak 2nd and 3rd harmonics, breath noise around the
    first harmonics, a chiff and a small upward scoop at the attack, a vibrato that grows in on
    long notes, and a soft release."""
    attack = 0.07 + 0.05 * (1.0 - vel)
    release = 0.16
    n = frames(dur_s + release + 0.02, rate)
    t = fx.t_axis(n, rate)
    scoop = 1.0 - 0.012 * np.exp(-t / 0.035)
    ratio = scoop * vibrato(n, rate, rng, 5.1, vib_cents, delay_s=0.28, ramp_s=0.5)
    freq = f0 * ratio
    env = env_note(n, rate, attack, dur_s, release)
    swell = 1.0 + 0.08 * np.clip((t - attack) / max(dur_s, 0.1), 0.0, 1.0)
    amps = np.array([1.0, 0.16, 0.07, 0.025, 0.012])
    tone = additive(freq, amps, rate, rng)
    air = fx.noise(n, rng, f0 * 0.8, min(f0 * 4.5, rate * 0.45), rate)
    air = air * (breath * (0.6 + 0.4 * env))
    chiff = fx.noise(n, rng, f0 * 2.0, min(f0 * 8.0, rate * 0.45), rate) * fx.env_ad(n, rate, 0.004, 0.03) * 0.5
    return (tone * swell + air + chiff) * env * vel


def brass(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, bright: float = 1.0,
          attack_s: float = 0.06, release_s: float = 0.18, vib_cents: float = 9.0, scoop: float = 0.02,
          body=((480.0, 380.0), (1100.0, 900.0), (2600.0, 1800.0)), rate: int = RATE) -> np.ndarray:
    """A horn or low brass note, additive: harmonics k under a horn body (three resonances), each
    following the envelope raised to a power that grows with k, so the note brightens as it
    swells and mellows as it fades; a scoop into the pitch and a delayed vibrato."""
    n = frames(dur_s + release_s + 0.03, rate)
    t = fx.t_axis(n, rate)
    freq = f0 * (1.0 - scoop * np.exp(-t / 0.045)) * vibrato(n, rate, rng, 4.6, vib_cents, 0.35, 0.6)
    env = env_note(n, rate, attack_s, dur_s, release_s, curve=0.8)
    count = int(min(40, (rate * 0.45) // max(f0, 30.0)))
    weights = formant_weights(f0, count, [b[0] for b in body], [b[1] for b in body], tilt=-1.5)
    weights /= weights.max()
    k = np.arange(1, count + 1, dtype=np.float64)
    powers = 1.0 + (k - 1.0) * 0.22 / max(bright * vel, 0.25)
    amps = weights[:, None] * env[None, :] ** powers[:, None]
    blat = 1.0 + 0.6 * np.exp(-t / 0.05) * (k[:, None] > 3)
    return additive(freq, amps * blat, rate, rng) * vel


def horn(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
         **kw) -> np.ndarray:
    """A mellow French-horn-like voice (brass with a darker body and a slower attack)."""
    kw.setdefault("bright", 0.7)
    kw.setdefault("attack_s", 0.11)
    kw.setdefault("release_s", 0.3)
    kw.setdefault("body", ((380.0, 300.0), (850.0, 700.0), (2200.0, 1500.0)))
    return brass(rng, f0, dur_s, vel, rate=rate, **kw)


VOWEL_FORMANTS = {
    "a": ((730.0, 110.0), (1090.0, 140.0), (2440.0, 200.0)),
    "o": ((570.0, 100.0), (840.0, 120.0), (2410.0, 200.0)),
    "u": ((330.0, 90.0), (870.0, 120.0), (2240.0, 220.0)),
    "e": ((530.0, 100.0), (1840.0, 150.0), (2480.0, 200.0)),
    "m": ((280.0, 120.0), (900.0, 300.0), (2200.0, 400.0)),
}


def choir(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, vowel: str = "a",
          voices: int = 4, attack_s: float = 0.35, release_s: float = 0.6, detune_cents: float = 9.0,
          breath: float = 0.05, rate: int = RATE) -> np.ndarray:
    """A section singing one vowel: `voices` voices (one wavetable of harmonics under the vowel's
    formants), each slightly detuned, with its own vibrato and a slow amplitude drift, plus a
    little breath; a slow attack and release."""
    n = frames(dur_s + release_s + 0.05, rate)
    t = fx.t_axis(n, rate)
    forms = VOWEL_FORMANTS.get(vowel, VOWEL_FORMANTS["a"])
    count = int(min(48, (min(5500.0, rate * 0.45)) // max(f0, 40.0)))
    weights = formant_weights(f0, count, [f for f, _b in forms], [b for _f, b in forms], tilt=-3.0)
    weights /= weights.max()
    out = np.zeros(n)
    for _v in range(voices):
        cents = rng.uniform(-detune_cents, detune_cents)
        ratio = 2.0 ** (cents / 1200.0) * vibrato(n, rate, rng, rng.uniform(4.6, 5.6), rng.uniform(10.0, 18.0),
                                                  rng.uniform(0.15, 0.4), 0.5)
        drift = 1.0 + 0.12 * np.sin(TWO_PI * rng.uniform(0.15, 0.35) * t + rng.uniform(0, TWO_PI))
        table = wavetable(weights, rng)
        out += table_osc(table, f0 * ratio, rate, rng.uniform(0, 1)) * drift
    out /= math.sqrt(voices)
    air = fx.noise(n, rng, forms[0][0] * 0.8, forms[1][0] * 1.6, rate) * breath
    env = env_note(n, rate, attack_s, dur_s, release_s, curve=0.7)
    return (out + air) * env * vel


def pad(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, voices: int = 3,
        detune_cents: float = 7.0, attack_s: float = 0.9, release_s: float = 1.4, wave: str = "saw",
        rate: int = RATE) -> np.ndarray:
    """One pad note: detuned band-limited saws (or triangles) with slow drift; the stem is
    low-passed as a whole afterwards (render_* do it circularly), so this stays cheap."""
    n = frames(dur_s + release_s + 0.05, rate)
    t = fx.t_axis(n, rate)
    out = np.zeros(n)
    for v in range(voices):
        cents = detune_cents * (v - (voices - 1) / 2.0) / max((voices - 1) / 2.0, 1.0) + rng.uniform(-1.5, 1.5)
        drift = 2.0 ** ((cents + 2.0 * np.sin(TWO_PI * rng.uniform(0.07, 0.2) * t + rng.uniform(0, TWO_PI))) / 1200.0)
        if wave == "triangle":
            out += core.triangle(f0 * drift, n, rate, phase=rng.uniform(0, 1))
        else:
            out += core.saw(f0 * drift, n, rate, phase=rng.uniform(0, 1))
    out /= math.sqrt(voices)
    return out * env_note(n, rate, attack_s, dur_s, release_s, curve=0.6) * vel


def sub(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, attack_s: float = 0.6,
        release_s: float = 1.2, rate: int = RATE) -> np.ndarray:
    """A soft sine bass (with a whisper of the octave) under a pad."""
    n = frames(dur_s + release_s + 0.05, rate)
    s = core.sine(f0, n, rate, phase=rng.uniform(0, 1)) + 0.18 * core.sine(2.0 * f0, n, rate, phase=rng.uniform(0, 1))
    return s * env_note(n, rate, attack_s, dur_s, release_s, curve=0.6) * vel


def strings(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, voices: int = 4,
            tremolo_hz: float = 0.0, attack_s: float = 0.05, release_s: float = 0.25,
            rate: int = RATE) -> np.ndarray:
    """A string section on one note: detuned saws with vibrato; with tremolo_hz > 0 a measured
    bowed tremolo (each stroke a quick swell) - the Ogre King's frenzy."""
    n = frames(dur_s + release_s + 0.03, rate)
    t = fx.t_axis(n, rate)
    out = np.zeros(n)
    for _v in range(voices):
        ratio = 2.0 ** (rng.uniform(-8.0, 8.0) / 1200.0) * vibrato(n, rate, rng, rng.uniform(5.0, 6.2), 12.0, 0.1, 0.3)
        out += core.saw(f0 * ratio, n, rate, phase=rng.uniform(0, 1))
    out /= math.sqrt(voices)
    if tremolo_hz > 0:
        ph = (t * tremolo_hz + rng.uniform(0, 1)) % 1.0
        out *= 0.35 + 0.65 * np.sin(math.pi * ph) ** 0.6
    return out * env_note(n, rate, attack_s, dur_s, release_s) * vel


def bell_tone(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, decay_s: float = 2.2,
              rate: int = RATE) -> np.ndarray:
    """A small struck bell (instruments.bell) that rings past the note."""
    n = frames(max(dur_s, decay_s) + 0.2, rate)
    b = instruments.bell(rng, n, rate, f0, decay_s, strike=0.15)
    return fx.seal(b / max(core.peak(b), 1e-9), rate, 0.02) * vel


# --------------------------------------------------------------------------- drums


def _membrane(rng, n, rate, f0, drop, drop_tau, tau, modes=((1.0, 1.0), (1.59, 0.35), (2.14, 0.18))):
    t = fx.t_axis(n, rate)
    bend = 1.0 + drop * np.exp(-t / drop_tau)
    out = np.zeros(n)
    for ratio, amp in modes:
        out += amp * np.sin(TWO_PI * np.cumsum(f0 * ratio * bend) / rate + rng.uniform(0, 0.4)) \
            * np.exp(-t / (tau / (0.6 + 0.4 * ratio)))
    return out


def frame_drum(rng: np.random.Generator, vel: float = 1.0, f0: float = 82.0, rate: int = RATE) -> np.ndarray:
    """A hand frame drum: a low membrane thump with a fast pitch drop and the skin's slap."""
    n = frames(0.6, rate)
    body = _membrane(rng, n, rate, f0 * rng.uniform(0.98, 1.02), 0.45, 0.03, 0.18)
    slap = fx.noise(n, rng, 300.0, 2600.0, rate) * fx.env_ad(n, rate, 0.0008, 0.025) * 0.45
    return fx.seal((body + slap) * vel, rate, 0.02)


def taiko(rng: np.random.Generator, vel: float = 1.0, f0: float = 58.0, rate: int = RATE) -> np.ndarray:
    """A big barrel drum: a deep pitch-dropping boom, the stick's crack and a short room."""
    n = frames(1.4, rate)
    body = _membrane(rng, n, rate, f0 * rng.uniform(0.98, 1.02), 0.9, 0.05, 0.42,
                     modes=((1.0, 1.0), (1.5, 0.4), (2.0, 0.22), (2.6, 0.1)))
    crack = fx.noise(n, rng, 500.0, 4500.0, rate) * fx.env_ad(n, rate, 0.0005, 0.018) * 0.6
    room = fx.noise(n, rng, 60.0, 700.0, rate) * fx.env_ad(n, rate, 0.02, 0.25) * 0.12
    return fx.seal((body + crack + room) * vel, rate, 0.03)


def tom(rng: np.random.Generator, vel: float = 1.0, f0: float = 120.0, rate: int = RATE) -> np.ndarray:
    """A mid drum: a shorter, higher membrane with a stick attack."""
    n = frames(0.5, rate)
    body = _membrane(rng, n, rate, f0 * rng.uniform(0.98, 1.02), 0.35, 0.025, 0.16)
    stick = fx.noise(n, rng, 800.0, 5000.0, rate) * fx.env_ad(n, rate, 0.0004, 0.01) * 0.5
    return fx.seal((body + stick) * vel, rate, 0.02)


def rim(rng: np.random.Generator, vel: float = 1.0, rate: int = RATE) -> np.ndarray:
    """A hard wooden click (stick on the drum's rim)."""
    n = frames(0.12, rate)
    w = instruments.impact_wood(rng, 0.12, 0.0, rate)[:n]
    return fx.seal(w / max(core.peak(w), 1e-9) * vel, rate, 0.01)


def shaker(rng: np.random.Generator, vel: float = 1.0, length_s: float = 0.07, rate: int = RATE) -> np.ndarray:
    """A seed shaker stroke: high-passed noise with a quick swell and decay."""
    n = frames(length_s + 0.04, rate)
    s = fx.noise(n, rng, 3500.0, 10000.0, rate)
    env = fx.env_points([(0.0, 0.0), (length_s * 0.35, 1.0), (length_s, 0.25), (length_s + 0.04, 0.0)], n, rate)
    return s * env * vel


def crash(rng: np.random.Generator, vel: float = 1.0, decay_s: float = 1.6, rate: int = RATE) -> np.ndarray:
    """A dark metal crash (an inharmonic partial cloud over noise), band-limited for 22.05 kHz."""
    n = frames(decay_s + 0.3, rate)
    parts = rng.uniform(380.0, 7500.0, 26)
    ir = fx.modal_ir(parts, rng.uniform(0.3, 1.0, 26) * decay_s, rng.uniform(0.2, 1.0, 26), n, rate,
                     rng.uniform(0, TWO_PI, 26))
    ir /= max(core.peak(ir), 1e-9)
    hiss = fx.noise(n, rng, 2500.0, 10000.0, rate) * fx.env_ad(n, rate, 0.002, decay_s * 0.35)
    return fx.seal((0.6 * ir + 0.5 * hiss) * vel, rate, 0.05)


def timpani(rng: np.random.Generator, vel: float = 1.0, f0: float = 73.4, rate: int = RATE) -> np.ndarray:
    """A tuned kettle drum: a membrane with near-harmonic modes and a long, soft ring."""
    n = frames(1.8, rate)
    body = _membrane(rng, n, rate, f0, 0.04, 0.03, 0.9, modes=((1.0, 1.0), (1.5, 0.45), (1.98, 0.3), (2.44, 0.15)))
    mallet = fx.noise(n, rng, 150.0, 1500.0, rate) * fx.env_ad(n, rate, 0.001, 0.02) * 0.3
    return fx.seal((body + mallet) * vel, rate, 0.04)


# --------------------------------------------------------------------------- the phrase writer


def motif_notes(motif, anchor: int, invert: bool = False, shift: float = 0.0, take: int = 0,
                aug: float = 1.0, octave: int = 0) -> list:
    """The motif - [(beat, length, step)] - on an anchor degree: inverted (steps negated),
    shifted in time, cut to its first `take` notes, augmented (lengths and offsets x aug), moved
    by octaves. Returns [(beat, length, degree, accidental)]."""
    out = []
    cells = motif[:take] if take else motif
    for beat, length, step in cells:
        s = -step if invert else step
        out.append((beat * aug + shift, length * aug, anchor + s + 7 * octave, 0))
    return out


def bar_notes(entry) -> list:
    """One bar of a variant plan: ("m", anchor, {opts}) states the motif (see motif_notes);
    ("n", [(beat, length, degree[, accidental]), ...]) writes it out; ("r",) rests."""
    kind = entry[0]
    if kind == "r":
        return []
    if kind == "n":
        return [(b, d, deg, acc[0] if acc else 0) for b, d, deg, *acc in entry[1]]
    raise ValueError("bar entries other than 'n' and 'r' need the motif: use plan_notes")


def plan_notes(plan, motif, beats_per_bar: int = 4) -> list:
    """Every note of a variant plan (one entry per bar): [(beat_in_loop, length, degree, acc)]."""
    out = []
    for i, entry in enumerate(plan):
        if entry[0] == "m":
            opts = entry[2] if len(entry) > 2 else {}
            notes = motif_notes(motif, entry[1], **opts)
        else:
            notes = bar_notes(entry)
        for b, d, deg, acc in notes:
            out.append((i * beats_per_bar + b, d, deg, acc))
    return out


def ornament(notes, rng: np.random.Generator, scale=DORIAN, prob: float = 0.3, segment_beats: int = 16,
             min_len: float = 1.0, grace_beats: float = 0.125, style: str = "grace") -> list:
    """Seeded ornaments before long notes: a grace note a step above (or below), or a turn
    (above, the note, below) for style "turn". Never before a segment's first half beat, so a
    phrase still starts after the segment's downbeat. Returns new (beat, length, degree, acc,
    is_ornament) tuples."""
    out = []
    for b, d, deg, acc in notes:
        seg_pos = b % segment_beats
        room = seg_pos - 0.5
        if d >= min_len and rng.random() < prob and room >= grace_beats * (3 if style == "turn" else 1):
            if style == "turn":
                g = grace_beats
                out.append((b - 3 * g, g, deg + 1, 0, True))
                out.append((b - 2 * g, g, deg, acc, True))
                out.append((b - g, g, deg - 1, 0, True))
            else:
                step = 1 if rng.random() < 0.65 else -1
                out.append((b - grace_beats, grace_beats, deg + step, 0, True))
        out.append((b, d, deg, acc, False))
    return out


def check_phrases(notes, segment_beats: int = 16, start_after: float = 0.5, end_before: float = 0.5) -> list:
    """Problems of a melody variant against the scheduler's segments: a note starting before
    start_after beats into a segment, or one still sounding (by its written length) within
    end_before beats of the segment's end."""
    problems = []
    for b, d, *_rest in notes:
        seg = int(b // segment_beats)
        pos = b - seg * segment_beats
        if pos < start_after - 1e-9:
            problems.append("a note at beat %.3f starts %.3f beats into its segment" % (b, pos))
        if pos + d > segment_beats - end_before + 1e-9:
            problems.append("a note at beat %.3f (%.2f beats) rings into the next segment" % (b, d))
    return problems


# --------------------------------------------------------------------------- rendering


def place(buf: np.ndarray, at_s: float, sig: np.ndarray, gain: float = 1.0, rate: int = RATE) -> None:
    """Adds sig into buf at at_s seconds (beyond the end it is dropped: use a buffer with room
    for the tails and fold it with core.loop_wrap)."""
    core.mix_into(buf, frames(at_s, rate), sig, gain)


def loop_buffer(loop_s: float, tail_s: float = 6.0, rate: int = RATE) -> tuple:
    """(buffer, period): a buffer one loop long plus room for tails."""
    period = frames(loop_s, rate)
    return np.zeros(period + frames(tail_s, rate)), period


def render_voice(rng: np.random.Generator, notes, bpm: float, instrument, rate: int = RATE,
                 scale=DORIAN, tonic: int = D4, transpose: int = 0, buf=None, gain: float = 1.0,
                 humanize_s: float = 0.006, vel_fn=None, **kw) -> np.ndarray:
    """Plays (beat, length, degree, accidental[, ornament]) notes on an instrument
    (instrument(rng, f0, dur_s, vel, **kw)) into buf (or a new buffer sized to the notes)."""
    bs = beat_s(bpm)
    if buf is None:
        end = max((b + d) for b, d, *_r in notes) if notes else 0.0
        buf = np.zeros(frames(end * bs + 4.0, rate))
    for i, note in enumerate(notes):
        b, d, deg, acc = note[:4]
        is_orn = bool(note[4]) if len(note) > 4 else False
        midi = degree_midi(deg, scale, tonic, acc) + transpose
        vel = vel_fn(b, d, deg, i) if vel_fn else 0.85
        if is_orn:
            vel *= 0.6
        vel *= 1.0 + rng.uniform(-0.05, 0.05)
        at = max(0.0, b * bs + rng.uniform(-humanize_s, humanize_s))
        sig = instrument(rng, hz(midi), d * bs, vel, rate=rate, **kw)
        place(buf, at, sig, gain, rate)
    return buf


def render_hits(rng: np.random.Generator, hits, bpm: float, buf: np.ndarray, rate: int = RATE,
                humanize_s: float = 0.004) -> np.ndarray:
    """Plays percussion: hits = [(beat, fn, vel, kwargs)] with fn(rng, vel, rate=..., **kwargs)."""
    bs = beat_s(bpm)
    for b, fn, vel, kw in hits:
        sig = fn(rng, vel * (1.0 + rng.uniform(-0.04, 0.04)), rate=rate, **kw)
        place(buf, max(0.0, b * bs + rng.uniform(-humanize_s, humanize_s)), sig, 1.0, rate)
    return buf


def fold(buf: np.ndarray, period: int) -> np.ndarray:
    """Folds the tails onto the head: exactly one seamless loop."""
    return core.loop_wrap(buf, period)


def reverb_ir(rng: np.random.Generator, seconds: float = 2.4, rt60: float = 1.8, damp_hz: float = 3500.0,
              predelay_s: float = 0.02, early: int = 7, rate: int = RATE) -> np.ndarray:
    """A synthetic hall: a few early reflections, then exponentially decaying noise whose highs die
    faster (the tail is split in two bands with different decays), unit energy."""
    n = frames(seconds, rate)
    t = fx.t_axis(n, rate)
    tau = rt60 / 6.91
    lows = fx.noise(n, rng, 0.0, damp_hz, rate) * np.exp(-t / tau)
    highs = fx.noise(n, rng, damp_hz, 0.0, rate) * np.exp(-t / (tau * 0.45))
    tail = lows + 0.5 * highs
    tail *= np.clip(t / 0.03, 0.0, 1.0)
    ir = np.zeros(n)
    pre = frames(predelay_s, rate)
    ir[pre:] += tail[:n - pre]
    for _i in range(early):
        at = frames(predelay_s + rng.uniform(0.004, 0.06), rate)
        if at < n:
            ir[at] += rng.uniform(-1.0, 1.0) * 6.0
    return ir / math.sqrt(float(np.sum(ir * ir)))


def reverb_loop(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0) -> np.ndarray:
    """A circular convolution (the loop's tail rings into its own head: seamless)."""
    n = x.shape[0]
    size = n if ir.shape[0] <= n else ir.shape[0]
    wet_sig = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)
    return dry * x + wet * fold(wet_sig, n)


def reverb_tail(x: np.ndarray, ir: np.ndarray, wet: float, dry: float = 1.0) -> np.ndarray:
    """A linear convolution with the IR's tail appended (one-shots)."""
    full = core.fft_convolve(x, ir)
    out = np.zeros(full.shape[0])
    out[:x.shape[0]] += dry * x
    return out + wet * full


def circular_band(x: np.ndarray, lo: float, hi: float, order: int = 2, rate: int = RATE) -> np.ndarray:
    """A zero-phase circular band filter (loops stay seamless)."""
    return core.fft_filter(x, rate, core.band_response(lo, hi, order))


def tile_shape(x: np.ndarray, gains_fn, rate: int = RATE) -> np.ndarray:
    """A time-varying (STFT) filter applied to a loop as if it repeated forever: the loop is
    tiled three times, filtered, and the middle copy kept."""
    n = x.shape[0]
    tiled = np.concatenate([x, x, x])
    y = fx.stft_shape(tiled, lambda f, t: gains_fn(f, np.mod(t - n / rate, n / rate)), rate)
    return y[n:2 * n]


def finish_oneshot(x: np.ndarray, rate: int = RATE, floor_db: float = -60.0, fade_s: float = 0.25,
                   max_s: float = 30.0) -> np.ndarray:
    """A stinger's or a spot's end (fx.finish with a long limit): DC out, the silent tail trimmed
    under floor_db, a fade to zero, the mean taken out exactly."""
    return fx.finish(x, rate, fade_in_s=0.003, fade_out_s=fade_s, floor_db=floor_db, max_s=max_s)


def dc_loop(x: np.ndarray, rate: int = RATE, hz_: float = 22.0) -> np.ndarray:
    """A circular high-pass that takes DC and subsonic drift out of a loop."""
    return core.fft_filter(x, rate, core.band_response(hz_, 0.0, 2))


# --------------------------------------------------------------------------- analysis (checks, docs)


def a_weight_db(f: np.ndarray) -> np.ndarray:
    f2 = np.maximum(f, 1e-3) ** 2
    ra = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) * (f2 + 12194.0 ** 2))
    return 20.0 * np.log10(np.maximum(ra, 1e-12)) + 2.0


def measure(x: np.ndarray, rate: int = RATE) -> dict:
    """Objective numbers for a rendered piece: peak and RMS (dBFS), A-weighted RMS (dBFS), the
    loudest 3 s window (A-weighted), spectral centroid (Hz), the share of energy under 250 Hz,
    the crest factor (dB) and the length."""
    mono = x.mean(axis=1) if x.ndim == 2 else x
    n = mono.shape[0]
    spec = np.fft.rfft(mono)
    freqs = np.fft.rfftfreq(n, 1.0 / rate)
    power = np.abs(spec) ** 2
    total = float(power.sum()) or 1e-12
    weighted = power * 10.0 ** (a_weight_db(freqs) / 10.0)
    a_rms = math.sqrt(float(weighted.sum()) / total) * core.rms(mono)
    win = frames(3.0, rate)
    loud = -200.0
    if n > win:
        a_sig = core.fft_filter(mono, rate, lambda f: 10.0 ** (a_weight_db(f) / 20.0))
        c = np.concatenate([[0.0], np.cumsum(a_sig * a_sig)])
        loud = core.gain_to_db(math.sqrt(max(float(np.max(c[win:] - c[:-win])) / win, 0.0)))
    return {"seconds": round(n / rate, 3), "peak_db": round(core.peak_db(x), 2), "rms_db": round(core.rms_db(x), 2),
            "lufs": round(core.loudness_lufs(x, rate), 2),
            "a_rms_db": round(core.gain_to_db(a_rms), 2), "loudest3s_a_db": round(loud, 2),
            "centroid_hz": round(float((freqs * power).sum() / total), 1),
            "low_share": round(float(power[freqs < 250.0].sum() / total), 3),
            "crest_db": round(core.peak_db(x) - core.rms_db(x), 2)}
