"""The Old Kingdom's score (P28; plan M6-M9 decision 5, sections 4.2, 4.3 and 4.5): the five regions'
zone sets in the Valley's zone frame, the three world bosses' sets in their own frames, and the
world's stingers.

The zone sets share P23's zone frame, `zone_96` (D dorian, 96 BPM, 4/4, twelve bars = 30.0 s) and its
chords (gen_music.ZONE_CHORDS: Dm Dm C Dm | G G Am C | F C G Asus-A), so they share the Valley's
danger and combat stems (`pulse`, `combat_drums`, `combat_brass`) and a region crossing - or a walk
from the Kings' Door into the Crownmarch - lands on a bar with the harmony carried on. Each region
has its own drone and three melody variants written from one motif (synth/music.py's phrase
writer), in four-bar phrases that start after a segment's downbeat and end before its last half
beat (the melody scheduler switches variants or rests at any segment):

    crownmarch     "D-E-F-A, G-F" - a lilting dance turn, on a bowed fiddle over open fifths
                   (strings and a soft organ-like pad following the chords' roots)
    greywood       "A, G-F-E" - a slow fall through the dorian scale, on a double reed (a nasal
                   shawm) over a dark choir in the low register
    drowned_steps  "D, A, F" - a falling triad on struck bells, ringing over a glassy pad
    aldmere        "D-D-F-A-D" - a trumpet call on the chord, over a soft brass pad; Aldmere's
                   combat adds a field-drum `snare` stem to the shared drums and brass
    stonehold      "A, D" - a rising fourth on an enormous low horn, over a wide choir

The bosses' sets have their own tempo, metre and mode and share no stem:

    music.boss_regiment   the Iron Regiment: a march at 112 BPM in D minor (12 bars, 25.71 s):
                          march drums (bass drum, snare, rolls, cymbals) and a brass theme;
                          phase 2 adds fifes and high trumpets
    music.boss_matriarch  the Troll Matriarch: a heavy 6/8 at 84 dotted-quarter beats a minute
                          (16 bars, 22.86 s; two beats of three eighths a bar): wild drums and a
                          growl drone grinding a semitone over D; phase 2 adds a howling wail
    music.boss_harrok     Harrok: a half-time 72 BPM in D phrygian (8 bars, 26.67 s): giant drums
                          and a chanting male choir; phase 2 adds giant horns

Stingers (one-shots on the Music bus): discovery, world_reveal (the vistas), yield, ancestry,
crowned (the throne), rout; the five regions' combat intros (two bars at 96 BPM, on a beat) and the
three bosses' one-bar intros in their own tempo.

Every file is mono at 22.05 kHz; loops are exactly bars x beats x 60 / bpm seconds (the build checks
the frame count) and seamless (tails folded onto the head, circular reverb). Balanced by K-weighted
loudness like P23's stems (drones -24 LUFS, melodies -19, the snare -21, boss stems -16 to -19,
stingers -16). Every sound is original and synthesized here. Seeds 280001-280199.
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx, music as M
from synth import instruments as ins

import gen_music as Z   # the zone frame's harmony (P23): the world's sets share its chords

FAMILY = "world_music"
RATE = core.DEFAULT_RATE
_P = "res://assets/audio/music/world/"

ZONE_BPM = Z.ZONE_BPM
ZONE_BEATS = Z.ZONE_BEATS
ZONE_FRAME = Z.ZONE_FRAME
SEGMENT_BEATS = Z.SEGMENT_BEATS
SEGMENT_FADE_BEATS = Z.SEGMENT_FADE_BEATS
TWO_PI = 2.0 * math.pi

REGIMENT_BPM = 112.0
REGIMENT_BEATS = 48            # 12 bars of 4/4
REGIMENT_FRAME = "boss_112"
MATRIARCH_BPM = 84.0           # dotted-quarter beats: 6/8, two beats of three eighths a bar
MATRIARCH_BEATS_PER_BAR = 2
MATRIARCH_BEATS = 32           # 16 bars
MATRIARCH_FRAME = "boss_84_68"
HARROK_BPM = 72.0
HARROK_BEATS = 32              # 8 bars of 4/4 (half time)
HARROK_FRAME = "boss_72"
PHRYGIAN = (0, 1, 3, 5, 7, 8, 10)   # D Eb F G A Bb C

REGIONS = ("crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold")


# --------------------------------------------------------------------------- instruments


FIDDLE_BODY = ((290.0, 170.0), (510.0, 240.0), (1050.0, 600.0), (2850.0, 1500.0))


def fiddle(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
           vib_cents: float = 17.0, bow: float = 0.06, bright: float = 1.0) -> np.ndarray:
    """A bowed fiddle: a sawtooth-like source (harmonics falling 1/k^0.7) under a wooden body
    (four resonances, the bridge hill near 3 kHz), a little scoop into the note, a vibrato that
    grows in, the bow's hiss and the scrape of its attack, a short release."""
    attack = 0.045 + 0.05 * (1.0 - vel)
    release = 0.13
    n = M.frames(dur_s + release + 0.03, rate)
    t = fx.t_axis(n, rate)
    freq = f0 * (1.0 - 0.012 * np.exp(-t / 0.03)) * M.vibrato(n, rate, rng, 5.7, vib_cents, 0.2, 0.3)
    env = M.env_note(n, rate, attack, dur_s, release, curve=0.8)
    count = int(min(32, (rate * 0.45) // max(f0, 60.0)))
    body = M.formant_weights(f0, count, [b[0] for b in FIDDLE_BODY], [b[1] for b in FIDDLE_BODY], tilt=-0.5)
    k = np.arange(1, count + 1, dtype=np.float64)
    amps = (0.35 + body / body.max()) * k ** (-0.7 / bright)
    # the bow presses harder into a swelling note: the upper harmonics follow the envelope more
    powers = 1.0 + (k - 1.0) * 0.06
    tone = M.additive(freq, amps[:, None] * env[None, :] ** powers[:, None], rate, rng)
    tone /= max(core.peak(tone), 1e-9)
    hiss = fx.noise(n, rng, 2200.0, min(7500.0, rate * 0.45), rate) * bow * (0.35 + 0.65 * env)
    scrape = fx.noise(n, rng, 700.0, 4500.0, rate) * fx.env_ad(n, rate, 0.002, 0.028) * 0.22
    return (tone * env + hiss + scrape) * vel


REED_BODY = ((1180.0, 420.0), (2650.0, 800.0), (640.0, 380.0))


def reed(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
         vib_cents: float = 13.0, breath: float = 0.05) -> np.ndarray:
    """A double reed (a shawm, nasal and old): many harmonics under two strong formants (about 1.2
    and 2.7 kHz), the odd ones a little louder, brightening as the note swells; a buzzy attack, a
    breath of air and a slow vibrato."""
    attack = 0.035 + 0.04 * (1.0 - vel)
    release = 0.11
    n = M.frames(dur_s + release + 0.03, rate)
    t = fx.t_axis(n, rate)
    freq = f0 * (1.0 - 0.018 * np.exp(-t / 0.025)) * M.vibrato(n, rate, rng, 4.9, vib_cents, 0.3, 0.5)
    env = M.env_note(n, rate, attack, dur_s, release, curve=0.85)
    count = int(min(36, (rate * 0.45) // max(f0, 60.0)))
    w = M.formant_weights(f0, count, [b[0] for b in REED_BODY], [b[1] for b in REED_BODY], tilt=-1.0)
    k = np.arange(1, count + 1, dtype=np.float64)
    amps = (0.15 + w / w.max()) * np.where(k % 2 == 1, 1.0, 0.72)
    powers = 1.0 + (k - 1.0) * 0.16
    tone = M.additive(freq, amps[:, None] * env[None, :] ** powers[:, None], rate, rng)
    tone /= max(core.peak(tone), 1e-9)
    buzz = fx.noise(n, rng, 900.0, 5000.0, rate) * fx.env_ad(n, rate, 0.002, 0.04) * 0.3
    air = fx.noise(n, rng, f0 * 1.5, min(f0 * 9.0, rate * 0.45), rate) * breath * env
    return (tone * env + buzz + air) * vel


def trumpet(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
            **kw) -> np.ndarray:
    """A natural trumpet's call: synth/music.py's brass with a bright, forward body and a crisp
    attack."""
    kw.setdefault("bright", 1.35)
    kw.setdefault("attack_s", 0.028)
    kw.setdefault("release_s", 0.12)
    kw.setdefault("vib_cents", 5.0)
    kw.setdefault("scoop", 0.015)
    kw.setdefault("body", ((620.0, 420.0), (1450.0, 900.0), (2900.0, 1700.0)))
    return M.brass(rng, f0, dur_s, vel, rate=rate, **kw)


def giant_horn(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
               breath: float = 0.12) -> np.ndarray:
    """An enormous low horn (a giant's lur): a dark horn with a slow swell and a wide scoop into
    the pitch, the octave below doubled softly, and a lot of breath in the bore."""
    hi = M.horn(rng, f0, dur_s, vel, rate=rate, bright=0.55, attack_s=0.22, release_s=0.5, vib_cents=4.0,
                scoop=0.035, body=((300.0, 260.0), (720.0, 600.0), (1750.0, 1200.0)))
    lo = M.horn(rng, f0 * 0.5, dur_s, vel * 0.7, rate=rate, bright=0.45, attack_s=0.3, release_s=0.5,
                vib_cents=3.0, scoop=0.03, body=((260.0, 240.0), (600.0, 500.0), (1500.0, 1100.0)))
    n = max(hi.shape[0], lo.shape[0])
    out = np.zeros(n)
    out[:hi.shape[0]] += hi
    out[:lo.shape[0]] += 0.45 * lo
    env = M.env_note(n, rate, 0.25, dur_s, 0.5, curve=0.7)
    air = fx.noise(n, rng, f0 * 1.2, min(f0 * 10.0, 4000.0), rate, "pink") * breath * env
    return out / max(core.peak(out), 1e-9) * vel + air


def bell(rng: np.random.Generator, f0: float, dur_s: float, vel: float = 1.0, rate: int = RATE,
         decay_s: float | None = None) -> np.ndarray:
    """A struck bell of the drowned towers (synth/music.py's bell_tone): low bells ring longer."""
    d = decay_s if decay_s is not None else float(np.clip(3.2 * (440.0 / max(f0, 60.0)) ** 0.45, 1.2, 4.5))
    return M.bell_tone(rng, f0, max(dur_s, 0.3), vel, decay_s=d, rate=rate)


def snare(rng: np.random.Generator, vel: float = 1.0, rate: int = RATE, tone_hz: float = 196.0,
          wires: float = 1.0, length_s: float = 0.22) -> np.ndarray:
    """A field drum: the stick's crack, the shell's tone dropping a little, and the wires' rattle
    (band-passed noise with a slower decay)."""
    n = M.frames(length_s, rate)
    t = fx.t_axis(n, rate)
    shell = (np.sin(TWO_PI * np.cumsum(tone_hz * (1.0 + 0.25 * np.exp(-t / 0.01))) / rate)
             + 0.4 * np.sin(TWO_PI * np.cumsum(tone_hz * 1.62 * np.ones(n)) / rate)) * np.exp(-t / 0.035)
    crack = fx.noise(n, rng, 1500.0, 8000.0, rate) * fx.env_ad(n, rate, 0.0004, 0.006)
    rattle = fx.noise(n, rng, 2500.0, 9000.0, rate) * fx.env_ad(n, rate, 0.002, 0.07) * wires
    return (0.6 * shell + 0.8 * crack + 0.7 * rattle) * vel


def roll(rng: np.random.Generator, beats: float, bpm: float, vel0: float, vel1: float, rate: int = RATE,
         tone_hz: float = 196.0) -> np.ndarray:
    """A snare roll: strokes every 32nd note, crescendo (or diminuendo) from vel0 to vel1."""
    bs = M.beat_s(bpm)
    strokes = max(1, int(round(beats * 8)))
    out = np.zeros(M.frames(beats * bs + 0.3, rate))
    for i in range(strokes):
        v = vel0 + (vel1 - vel0) * i / max(1, strokes - 1)
        M.place(out, i * bs / 8.0 + rng.uniform(-0.002, 0.002),
                snare(rng, v * rng.uniform(0.85, 1.0), rate, tone_hz, 0.8, 0.12), 0.8)
    return out


def bass_drum(rng: np.random.Generator, vel: float = 1.0, rate: int = RATE, f0: float = 62.0) -> np.ndarray:
    """A marching bass drum: synth/music.py's taiko a little higher and drier."""
    return M.taiko(rng, vel, f0=f0, rate=rate)


# --------------------------------------------------------------------------- the melodies
# Degrees count from D4 (0) in D dorian, as in gen_music.py: D4 0, E4 1, F4 2, G4 3, A4 4, B4 5,
# C5 6, D5 7, E5 8, F5 9, G5 10, A5 11, B5 12, C6 13, D6 14; below: C4 -1, B3 -2, A3 -3, G3 -4,
# F3 -5, E3 -6, D3 -7. A bar is ("m", anchor[, {opts}]) - the motif on an anchor degree - or
# ("n", [(beat, length, degree[, accidental]), ...]) written out. The chords by bar: Dm Dm C Dm |
# G G Am C | F C G Asus-A; phrases start at least half a beat into bars 1, 5 and 9 and end by beat
# 3.5 of bars 4, 8 and 12.

CROWN_MOTIF = [(0.5, 0.5, 0), (1.0, 0.5, 1), (1.5, 0.5, 2), (2.0, 0.75, 4), (2.75, 0.25, 3), (3.0, 1.0, 2)]
CROWN = {
    "a": [   # the tune: the turn sequenced on the chords, answered by arpeggios
        ("m", 0),
        ("n", [(0, 1.5, 4), (1.5, 0.5, 2), (2, 0.5, 4), (2.5, 0.5, 7), (3, 1, 4)]),
        ("m", -1),
        ("n", [(0, 1, 4), (1, 0.5, 2), (1.5, 0.5, 1), (2, 1.5, 0)]),
        ("m", 3),
        ("n", [(0, 1.5, 7), (1.5, 0.5, 5), (2, 0.5, 7), (2.5, 0.5, 10), (3, 1, 7)]),
        ("m", 4),
        ("n", [(0, 1, 8), (1, 0.5, 6), (1.5, 0.5, 5), (2, 1.5, 3)]),
        ("m", 2),
        ("n", [(0, 1.5, 6), (1.5, 0.5, 4), (2, 0.5, 3), (2.5, 0.5, 1), (3, 1, 3)]),
        ("n", [(0, 0.5, 5), (0.5, 0.5, 7), (1, 1, 10), (2, 1, 7), (3, 0.5, 5), (3.5, 0.5, 4)]),
        ("n", [(0, 1, 7), (1, 1, 8), (2, 1.5, 6, 1)]),                  # D E C#
    ],
    "b": [   # the reel: running eighths an octave up, turning back on themselves
        ("n", [(0.5, 0.5, 7), (1, 0.5, 9), (1.5, 0.5, 11), (2, 0.5, 9), (2.5, 0.5, 7), (3, 0.5, 8), (3.5, 0.5, 9)]),
        ("n", [(0, 1, 11), (1, 0.5, 9), (1.5, 0.5, 8), (2, 1, 7), (3, 1, 4)]),
        ("n", [(0, 0.5, 6), (0.5, 0.5, 8), (1, 0.5, 10), (1.5, 0.5, 8), (2, 0.5, 6), (2.5, 0.5, 7), (3, 1, 8)]),
        ("n", [(0, 1, 9), (1, 0.5, 8), (1.5, 0.5, 7), (2, 1.5, 4)]),
        ("n", [(0.5, 0.5, 10), (1, 0.5, 12), (1.5, 0.5, 14), (2, 0.5, 12), (2.5, 0.5, 10), (3, 0.5, 11), (3.5, 0.5, 12)]),
        ("n", [(0, 1, 14), (1, 0.5, 12), (1.5, 0.5, 11), (2, 1, 10), (3, 1, 7)]),
        ("n", [(0, 0.5, 8), (0.5, 0.5, 11), (1, 0.5, 13), (1.5, 0.5, 11), (2, 0.5, 8), (2.5, 0.5, 10), (3, 1, 11)]),
        ("n", [(0, 1, 10), (1, 0.5, 8), (1.5, 0.5, 6), (2, 1.5, 8)]),
        ("n", [(0.5, 0.5, 9), (1, 0.5, 11), (1.5, 0.5, 13), (2, 0.5, 11), (2.5, 0.5, 9), (3, 0.5, 10), (3.5, 0.5, 11)]),
        ("n", [(0, 1, 10), (1, 0.5, 8), (1.5, 0.5, 6), (2, 1, 8), (3, 1, 10)]),
        ("n", [(0, 0.5, 12), (0.5, 0.5, 11), (1, 0.5, 10), (1.5, 0.5, 9), (2, 1, 7), (3, 0.5, 5), (3.5, 0.5, 7)]),
        ("n", [(0, 1, 8), (1, 1, 7), (2, 1.5, 6, 1)]),
    ],
    "c": [   # the air: long bowed notes
        ("n", [(1, 2, 4), (3, 1, 2)]),
        ("n", [(0, 3, 7)]),
        ("n", [(1, 2, 3), (3, 1, 1)]),
        ("n", [(0, 3.5, 0)]),
        ("n", [(1, 2, 5), (3, 1, 7)]),
        ("n", [(0, 3, 10)]),
        ("n", [(1, 2, 8), (3, 1, 6)]),
        ("n", [(0, 3.5, 3)]),
        ("n", [(1, 2, 9), (3, 1, 11)]),
        ("n", [(0, 2, 10), (2, 2, 8)]),
        ("n", [(1, 2, 7), (3, 1, 5)]),
        ("n", [(0, 1.5, 7), (1.5, 2, 6, 1)]),
    ],
}

GREY_MOTIF = [(0.5, 1.5, 0), (2.0, 0.5, -1), (2.5, 0.5, -2), (3.0, 1.0, -3)]   # A~ G F E on anchor A4
GREY = {
    "a": [   # the fall through the dorian scale, on each chord
        ("m", 4),
        ("n", [(0, 2, 2), (2, 1, 1), (3, 1, 0)]),
        ("m", 3),
        ("n", [(0, 1, 1), (1, 2.5, 0)]),
        ("m", 7),
        ("n", [(0, 1.5, 5), (1.5, 0.5, 4), (2, 2, 3)]),
        ("m", 8),
        ("n", [(0, 1, 6), (1, 2.5, 3)]),
        ("m", 6),
        ("n", [(0, 1.5, 4), (1.5, 0.5, 3), (2, 2, 1)]),
        ("n", [(0, 1, 3), (1, 1, 5), (2, 2, 7)]),
        ("n", [(0, 1.5, 4), (1.5, 2, 6, 1)]),
    ],
    "b": [   # low and turning: the reed's dark register
        ("n", [(0.5, 1, 0), (1.5, 0.5, 1), (2, 1.5, 2), (3.5, 0.5, 1)]),
        ("n", [(0, 1, 0), (1, 0.5, -1), (1.5, 0.5, -2), (2, 2, -3)]),
        ("n", [(0, 1, -1), (1, 0.5, 0), (1.5, 0.5, 1), (2, 1.5, 3), (3.5, 0.5, 1)]),
        ("n", [(0, 1, 2), (1, 2.5, 0)]),
        ("n", [(0.5, 1, 3), (1.5, 0.5, 4), (2, 1.5, 5), (3.5, 0.5, 4)]),
        ("n", [(0, 1, 3), (1, 1, 0), (2, 2, -2)]),
        ("n", [(0, 1, -3), (1, 0.5, -2), (1.5, 0.5, -1), (2, 1.5, 1), (3.5, 0.5, 0)]),
        ("n", [(0, 1, -1), (1, 2.5, -4)]),
        ("n", [(0.5, 1, -5), (1.5, 0.5, -4), (2, 1.5, -3), (3.5, 0.5, -2)]),
        ("n", [(0, 2, -1), (2, 2, 1)]),
        ("n", [(0, 1, 0), (1, 1, -2), (2, 2, -4)]),
        ("n", [(0, 1.5, -3), (1.5, 2, -1, 1)]),
    ],
    "c": [   # long, ghostly tones high above
        ("n", [(1, 3, 7)]),
        ("n", [(0, 2, 9), (2, 2, 8)]),
        ("n", [(1, 3, 10)]),
        ("n", [(0, 3.5, 7)]),
        ("n", [(1, 3, 12)]),
        ("n", [(0, 2, 10), (2, 2, 7)]),
        ("n", [(1, 3, 11)]),
        ("n", [(0, 3.5, 10)]),
        ("n", [(1, 3, 13)]),
        ("n", [(0, 2, 10), (2, 2, 8)]),
        ("n", [(1, 3, 7)]),
        ("n", [(0, 1.5, 8), (1.5, 2, 6, 1)]),
    ],
}

BELL_MOTIF = [(0.5, 1.0, 0), (1.5, 1.0, -3), (2.5, 1.5, -5)]        # D5 A4 F4 on anchor D5
BELLS = {
    "a": [   # the falling triad on every chord
        ("m", 7),
        ("n", [(0.5, 1, 9), (1.5, 2, 11)]),
        ("m", 6),
        ("n", [(0, 1, 3), (1, 2.5, 0)]),
        ("m", 10),
        ("n", [(0.5, 1, 7), (1.5, 2, 3)]),
        ("m", 11),
        ("n", [(0, 1, 8), (1, 2.5, 6)]),
        ("m", 9),
        ("n", [(0.5, 1, 6), (1.5, 2, 3)]),
        ("n", [(0.5, 1, 7), (1.5, 1, 5), (2.5, 1.5, 3)]),
        ("n", [(0, 1, 4), (1, 2.5, 8)]),
    ],
    "b": [   # pairs of quick strokes high up, like water lapping at the steps
        ("n", [(0.5, 0.5, 11), (1, 0.5, 9), (2, 0.5, 11), (2.5, 0.5, 9), (3, 1, 7)]),
        ("n", [(0, 0.5, 9), (0.5, 0.5, 7), (1.5, 2, 4)]),
        ("n", [(0, 0.5, 10), (0.5, 0.5, 8), (2, 0.5, 10), (2.5, 0.5, 8), (3, 1, 6)]),
        ("n", [(0, 0.5, 8), (0.5, 0.5, 7), (1.5, 2, 4)]),
        ("n", [(0.5, 0.5, 12), (1, 0.5, 10), (2, 0.5, 12), (2.5, 0.5, 10), (3, 1, 7)]),
        ("n", [(0, 0.5, 10), (0.5, 0.5, 7), (1.5, 2, 5)]),
        ("n", [(0, 0.5, 13), (0.5, 0.5, 11), (2, 0.5, 13), (2.5, 0.5, 11), (3, 1, 8)]),
        ("n", [(0, 0.5, 10), (0.5, 0.5, 8), (1.5, 2, 6)]),
        ("n", [(0.5, 0.5, 13), (1, 0.5, 11), (2, 0.5, 13), (2.5, 0.5, 11), (3, 1, 9)]),
        ("n", [(0, 0.5, 10), (0.5, 0.5, 8), (1.5, 2, 6)]),
        ("n", [(0, 0.5, 12), (0.5, 0.5, 10), (1.5, 1, 7), (2.5, 1, 5)]),
        ("n", [(0, 0.5, 11), (0.5, 0.5, 8), (1.5, 2, 6, 1)]),
    ],
    "c": [   # deep bells, one a bar, far under the water
        ("n", [(1, 3, 0)]),
        ("n", [(1, 3, -3)]),
        ("n", [(1, 3, -1)]),
        ("n", [(0.5, 3, 0)]),
        ("n", [(1, 3, -4)]),
        ("n", [(1, 3, 0)]),
        ("n", [(1, 3, -3)]),
        ("n", [(0.5, 3, -4)]),
        ("n", [(1, 3, -5)]),
        ("n", [(1, 3, -1)]),
        ("n", [(1, 3, -2)]),
        ("n", [(0.5, 3, -3)]),
    ],
}

FANFARE_MOTIF = [(0.5, 0.25, 0), (0.75, 0.25, 0), (1.0, 0.5, 2), (1.5, 0.5, 4), (2.0, 1.5, 7)]   # D D F A D5~
FANFARE = {
    "a": [   # the call on every chord
        ("m", 0),
        ("n", [(0, 0.5, 4), (0.5, 0.5, 2), (1, 1, 4), (2, 2, 0)]),
        ("m", -1),
        ("n", [(0, 1, 3), (1, 0.5, 1), (1.5, 2, 0)]),
        ("m", 3),
        ("n", [(0, 0.5, 7), (0.5, 0.5, 5), (1, 1, 7), (2, 2, 3)]),
        ("m", 4),
        ("n", [(0, 0.5, 8), (0.5, 0.5, 6), (1, 0.5, 8), (1.5, 2, 3)]),
        ("m", 2),
        ("n", [(0, 0.5, 6), (0.5, 0.5, 3), (1, 1, 6), (2, 2, 8)]),
        ("n", [(0, 0.25, 7), (0.25, 0.25, 7), (0.5, 0.5, 5), (1, 0.5, 7), (1.5, 0.5, 10), (2, 2, 7)]),
        ("n", [(0, 0.5, 4), (0.5, 0.5, 7), (1, 1, 8), (2, 1.5, 6, 1)]),
    ],
    "b": [   # the answer: lower, dotted
        ("n", [(0.5, 0.75, 4), (1.25, 0.25, 4), (1.5, 0.5, 2), (2, 1.5, 0)]),
        ("n", [(0, 0.75, 2), (0.75, 0.25, 4), (1, 1, 7), (2, 0.75, 4), (2.75, 0.25, 2), (3, 1, 4)]),
        ("n", [(0, 0.75, 3), (0.75, 0.25, 3), (1, 0.5, 1), (1.5, 2, -1)]),
        ("n", [(0, 0.75, 2), (0.75, 0.25, 1), (1, 2.5, 0)]),
        ("n", [(0.5, 0.75, 7), (1.25, 0.25, 7), (1.5, 0.5, 5), (2, 1.5, 3)]),
        ("n", [(0, 0.75, 5), (0.75, 0.25, 7), (1, 1, 10), (2, 2, 7)]),
        ("n", [(0, 0.75, 8), (0.75, 0.25, 8), (1, 0.5, 6), (1.5, 2, 4)]),
        ("n", [(0, 0.75, 3), (0.75, 0.25, 6), (1, 2.5, 8)]),
        ("n", [(0.5, 0.75, 6), (1.25, 0.25, 6), (1.5, 0.5, 4), (2, 1.5, 2)]),
        ("n", [(0, 0.75, 3), (0.75, 0.25, 6), (1, 1, 8), (2, 2, 6)]),
        ("n", [(0, 0.75, 7), (0.75, 0.25, 5), (1, 1, 3), (2, 2, 5)]),
        ("n", [(0, 1, 7), (1, 0.5, 8), (1.5, 2, 4)]),
    ],
    "c": [   # a long noble line
        ("n", [(1, 2, 7), (3, 1, 9)]),
        ("n", [(0, 2, 11), (2, 2, 9)]),
        ("n", [(0, 1.5, 10), (1.5, 0.5, 8), (2, 2, 6)]),
        ("n", [(0, 3.5, 7)]),
        ("n", [(1, 2, 10), (3, 1, 12)]),
        ("n", [(0, 2, 14), (2, 2, 12)]),
        ("n", [(0, 1.5, 11), (1.5, 0.5, 13), (2, 2, 11)]),
        ("n", [(0, 3.5, 10)]),
        ("n", [(1, 2, 9), (3, 1, 11)]),
        ("n", [(0, 2, 13), (2, 2, 10)]),
        ("n", [(0, 1.5, 12), (1.5, 0.5, 11), (2, 2, 10)]),
        ("n", [(0, 1.5, 11), (1.5, 2, 13, 1)]),
    ],
}

HORN_MOTIF = [(0.5, 2.0, 0), (2.5, 1.5, 3)]                           # A3~ D4 (a rising fourth) on anchor A3
HORN = {
    "a": [   # the giants' call
        ("m", -3),
        ("n", [(0, 1, 2), (1, 1, 0), (2, 2, -3)]),
        ("m", -4),
        ("n", [(0, 1.5, 1), (1.5, 2, 0)]),
        ("m", 0),
        ("n", [(0, 1, 5), (1, 1, 3), (2, 2, 0)]),
        ("m", 1),
        ("n", [(0, 1.5, 3), (1.5, 2, -1)]),
        ("m", -1),
        ("n", [(0, 1, 3), (1, 1, 1), (2, 2, -1)]),
        ("n", [(0, 2, 0), (2, 2, 3)]),
        ("n", [(0, 1.5, 4), (1.5, 2, 1)]),
    ],
    "b": [   # the call and its echo, an octave down
        ("n", [(0.5, 1.5, 4), (2, 2, 0)]),
        ("n", [(0, 1.5, -3), (1.5, 0.5, -1), (2, 2, -7)]),
        ("n", [(0, 1.5, 3), (1.5, 2.5, -1)]),
        ("n", [(0, 1.5, -3), (1.5, 2, -7)]),
        ("n", [(0.5, 1.5, 7), (2, 2, 3)]),
        ("n", [(0, 1.5, 0), (1.5, 2.5, -4)]),
        ("n", [(0, 1.5, 4), (1.5, 2.5, 1)]),
        ("n", [(0, 1.5, -1), (1.5, 2, -4)]),
        ("n", [(0.5, 1.5, 6), (2, 2, 2)]),
        ("n", [(0, 1.5, 3), (1.5, 2.5, -1)]),
        ("n", [(0, 1.5, 0), (1.5, 2.5, -4)]),
        ("n", [(0, 1.5, 1), (1.5, 2, -3)]),
    ],
    "c": [   # very long tones in the horn's high voice
        ("n", [(1, 3, 4)]),
        ("n", [(0, 2, 2), (2, 2, 0)]),
        ("n", [(1, 3, 3)]),
        ("n", [(0, 3.5, 0)]),
        ("n", [(1, 3, 5)]),
        ("n", [(0, 2, 7), (2, 2, 3)]),
        ("n", [(1, 3, 4)]),
        ("n", [(0, 3.5, 3)]),
        ("n", [(1, 3, 6)]),
        ("n", [(0, 2, 3), (2, 2, 1)]),
        ("n", [(1, 3, 0)]),
        ("n", [(0, 1.5, 1), (1.5, 2, 4)]),
    ],
}

MELODIES = {"crownmarch": (CROWN_MOTIF, CROWN), "greywood": (GREY_MOTIF, GREY),
            "drowned_steps": (BELL_MOTIF, BELLS), "aldmere": (FANFARE_MOTIF, FANFARE),
            "stonehold": (HORN_MOTIF, HORN)}
# The melody stems' names by region (plan section 4.3).
MELODY_STEMS = {"crownmarch": "fiddle", "greywood": "reed", "drowned_steps": "bells", "aldmere": "fanfare",
                "stonehold": "horn"}
DRONE_STEMS = {"crownmarch": "march", "greywood": "deepwood", "drowned_steps": "water", "aldmere": "martial",
               "stonehold": "high"}


def melody_notes(region: str, variant: str) -> list:
    motif, plans = MELODIES[region]
    return M.plan_notes(plans[variant], motif)


MELODY_STYLE = {
    "crownmarch": {"instrument": fiddle, "kw": {}, "orn": {"a": 0.15, "b": 0.1, "c": 0.35}, "orn_style": "grace",
                   "vel": (0.7, 0.18), "rt60": 1.8, "wet": 0.24, "lp": 7000.0},
    "greywood": {"instrument": reed, "kw": {}, "orn": {"a": 0.3, "b": 0.35, "c": 0.3}, "orn_style": "turn",
                 "vel": (0.66, 0.2), "rt60": 3.0, "wet": 0.34, "lp": 5200.0},
    "drowned_steps": {"instrument": bell, "kw": {}, "orn": {"a": 0.0, "b": 0.0, "c": 0.0}, "orn_style": "grace",
                      "vel": (0.62, 0.22), "rt60": 3.6, "wet": 0.42, "lp": 7000.0},
    "aldmere": {"instrument": trumpet, "kw": {}, "orn": {"a": 0.08, "b": 0.12, "c": 0.15}, "orn_style": "grace",
                "vel": (0.72, 0.18), "rt60": 2.2, "wet": 0.26, "lp": 6500.0},
    "stonehold": {"instrument": giant_horn, "kw": {}, "orn": {"a": 0.0, "b": 0.06, "c": 0.0}, "orn_style": "grace",
                  "vel": (0.72, 0.15), "rt60": 4.2, "wet": 0.42, "lp": 3800.0},
}


def _phrase_vel(base: float, swing: float):
    """A velocity arc over each four-bar segment (rising to the third bar, easing at the cadence),
    a little accent on the bar's first and third beats (P23's)."""
    def vel(b, d, deg, i):
        pos = (b % SEGMENT_BEATS) / SEGMENT_BEATS
        arc = np.sin(np.pi * min(pos * 1.25, 1.0))
        accent = 0.05 if (b % 4.0) in (0.0, 2.0) else 0.0
        return base + swing * arc + accent + (0.04 if d >= 1.0 else 0.0)
    return vel


def melody(rng: np.random.Generator, region: str, variant: str) -> np.ndarray:
    """One melody variant of a region's set: the plan realised by the phrase writer, played on the
    region's instrument with its room. Each four-bar segment is rendered on its own (its notes, its
    reverb) and faded out over its last half beat, so the stem is silent at every segment boundary
    and the scheduler can switch variants or rest there (as P23's melodies)."""
    style = MELODY_STYLE[region]
    notes = melody_notes(region, variant)
    problems = M.check_phrases(notes, SEGMENT_BEATS)
    if problems:
        raise ValueError("%s/%s: %s" % (region, variant, "; ".join(problems)))
    notes = M.ornament(notes, rng, prob=style["orn"][variant], style=style["orn_style"])
    bs = M.beat_s(ZONE_BPM)
    period = M.frames(ZONE_BEATS * bs)
    seg_n = M.frames(SEGMENT_BEATS * bs)
    out = np.zeros(period)
    ir = M.reverb_ir(rng, seconds=min(4.0, style["rt60"] * 1.2), rt60=style["rt60"], damp_hz=3200.0)
    fade_n = M.frames(SEGMENT_FADE_BEATS * bs)
    fade = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fade_n))
    vel_fn = _phrase_vel(*style["vel"])
    for seg in range(ZONE_BEATS // SEGMENT_BEATS):
        lo = seg * SEGMENT_BEATS
        part = [(b - lo,) + tuple(rest) for b, *rest in notes if lo <= b < lo + SEGMENT_BEATS]
        buf = np.zeros(seg_n + M.frames(5.0))
        M.render_voice(rng, part, ZONE_BPM, style["instrument"], buf=buf,
                       vel_fn=lambda b, d, deg, i, lo=lo: vel_fn(b + lo, d, deg, i), **style["kw"])
        wet = M.reverb_tail(buf, ir, style["wet"])[:seg_n]
        wet[-fade_n:] *= fade
        out[seg * seg_n:(seg + 1) * seg_n] += wet
    return M.dc_loop(M.circular_band(out, 0.0, style["lp"], 2))


# --------------------------------------------------------------------------- drones


def _spans():
    return Z.zone_chord_spans()


def _loop_s() -> float:
    return ZONE_BEATS * M.beat_s(ZONE_BPM)


def _bass(rng, buf, spans, gain, octave=0):
    bs = M.beat_s(ZONE_BPM)
    for b, d, _notes, bass in spans:
        M.place(buf, b * bs, M.sub(rng, M.hz(bass + 12 * octave), (d + 0.3) * bs, 0.9), gain)


def drone_march(rng: np.random.Generator) -> np.ndarray:
    """The Crownmarch's open fifths: a soft string section and an organ-like triangle pad on each
    chord's root, fifth and octave (no third: open and rustic, like a hurdy-gurdy's drone), a sine
    bass, and the bow's breath; a bright, airy room."""
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(_loop_s(), 6.0)
    for b, d, _notes, bass in _spans():
        root = bass + 12
        for midi, g in ((root, 0.5), (root + 7, 0.42), (root + 12, 0.28)):
            s = M.strings(rng, M.hz(midi), (d + 0.5) * bs, 0.8, voices=3, attack_s=0.9, release_s=1.3)
            M.place(buf, b * bs, s, g * 0.6)
            p = M.pad(rng, M.hz(midi), (d + 0.5) * bs, 0.8, voices=2, detune_cents=4.0, attack_s=0.8,
                      release_s=1.3, wave="triangle")
            M.place(buf, b * bs, p, g * 0.55)
    _bass(rng, buf, _spans(), 0.45)
    x = M.fold(buf, period)
    x = M.circular_band(x, 30.0, 2600.0, 2)
    bow = core.fft_filter(core.pink(period, rng), RATE, core.band_response(1500.0, 6000.0, 2))
    x = x / max(core.rms(x), 1e-9) + 0.05 * bow / max(core.rms(bow), 1e-9)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.4, 2.0, 3000.0), 0.24)
    return M.dc_loop(x)


def drone_deepwood(rng: np.random.Generator) -> np.ndarray:
    """The Greywood's dark choir: an "oo" choir low on each chord's root and third, a deep sub,
    and a slow low wind through the pines (band-passed noise whose centre wanders); a long, dark
    room."""
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(_loop_s(), 8.0)
    for b, d, notes, bass in _spans():
        root = bass
        low = notes[0] - 12   # the voicing's lowest note, an octave down: in the root's octave
        for midi, vowel, g in ((root, "u", 0.55), (low, "o", 0.4), (root + 12, "u", 0.3)):
            sig = M.choir(rng, M.hz(midi), (d + 0.7) * bs, 0.8, vowel=vowel, voices=4, attack_s=1.4,
                          release_s=2.0, detune_cents=11.0, breath=0.05)
            M.place(buf, b * bs, sig, g)
    _bass(rng, buf, _spans(), 0.4, octave=-1)
    x = M.fold(buf, period)
    x = M.circular_band(x, 25.0, 1400.0, 2)
    wind = core.pink(period, rng)
    loop_s = _loop_s()

    def wind_gains(f, t):
        swell = 0.3 + 0.7 * (0.5 - 0.5 * np.cos(2.0 * np.pi * t / (loop_s / 3.0))) ** 2
        centre = 320.0 * 2.0 ** (0.7 * np.sin(2.0 * np.pi * t / loop_s * 2.0) + 0.25 * np.sin(2.0 * np.pi * t / loop_s * 5.0))
        dd = np.log2(np.maximum(f[None, :], 1.0) / centre[:, None]) / 1.0
        return swell[:, None] * np.exp(-0.5 * dd * dd)
    wind = M.tile_shape(wind, wind_gains)
    x = x / max(core.rms(x), 1e-9) + 0.4 * wind / max(core.rms(wind), 1e-9)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.5, 4.2, 1500.0, predelay_s=0.05), 0.42)
    return M.dc_loop(x)


def drone_water(rng: np.random.Generator) -> np.ndarray:
    """The Drowned Steps' glassy pad: sines and triangles high on the chords (an octave up) with a
    slow shimmer, like wet glass rims; a soft sine bass; a long, bright room."""
    bs = M.beat_s(ZONE_BPM)
    loop_s = _loop_s()
    buf, period = M.loop_buffer(loop_s, 7.0)
    for b, d, notes, bass in _spans():
        for midi in notes:
            p = M.pad(rng, M.hz(midi + 12), (d + 0.6) * bs, 0.8, voices=3, detune_cents=6.0, attack_s=1.5,
                      release_s=2.2, wave="triangle")
            M.place(buf, b * bs, p, 0.35)
        n = M.frames((d + 2.5) * bs)
        t = fx.t_axis(n)
        glass = core.sine(M.hz(notes[0] + 24), n) * M.env_note(n, RATE, 1.2, d * bs, 1.6)
        M.place(buf, b * bs, glass, 0.12)
    _bass(rng, buf, _spans(), 0.4)
    x = M.fold(buf, period)
    t = np.arange(period) / RATE
    shimmer = 1.0 + 0.12 * np.sin(2.0 * np.pi * t * (6.0 / loop_s)) * np.sin(2.0 * np.pi * t * (17.0 / loop_s))
    x = M.circular_band(x * shimmer, 30.0, 6000.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.5, 4.0, 4200.0, predelay_s=0.03), 0.45)
    return M.dc_loop(x)


def drone_martial(rng: np.random.Generator) -> np.ndarray:
    """Aldmere's brass pad: a soft horn section holding each chord low (its voicing an octave down)
    with a slow swell, a sine bass, a firm, short room."""
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(_loop_s(), 5.0)
    for b, d, notes, bass in _spans():
        for k, midi in enumerate(notes):
            s = M.horn(rng, M.hz(midi - 12), (d + 0.2) * bs, 0.7, bright=0.6, attack_s=0.7, release_s=0.8,
                       vib_cents=3.0)
            M.place(buf, b * bs + 0.02 * k, s, 0.45)
    _bass(rng, buf, _spans(), 0.5)
    x = M.fold(buf, period)
    x = M.circular_band(x, 30.0, 3200.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.6, 2.2, 2600.0), 0.26)
    return M.dc_loop(x)


def drone_high(rng: np.random.Generator) -> np.ndarray:
    """The Stonehold's wide choir: an open "ah" choir on each chord's root, fifth, octave and
    ninth, high and wide, over a deep sub, with the high wind moving through it; a vast room."""
    bs = M.beat_s(ZONE_BPM)
    loop_s = _loop_s()
    buf, period = M.loop_buffer(loop_s, 8.0)
    for b, d, _notes, bass in _spans():
        root = bass + 12
        for midi, vowel, g in ((root, "o", 0.5), (root + 7, "a", 0.45), (root + 12, "a", 0.35), (root + 14, "a", 0.2)):
            sig = M.choir(rng, M.hz(midi), (d + 0.7) * bs, 0.8, vowel=vowel, voices=5, attack_s=1.3,
                          release_s=2.0, detune_cents=12.0, breath=0.06)
            M.place(buf, b * bs, sig, g)
    _bass(rng, buf, _spans(), 0.35, octave=-1)
    x = M.fold(buf, period)
    x = M.circular_band(x, 25.0, 4500.0, 2)
    wind = core.pink(period, rng)

    def wind_gains(f, t):
        swell = 0.35 + 0.65 * (0.5 - 0.5 * np.cos(2.0 * np.pi * t / (loop_s / 2.0))) ** 2
        centre = 900.0 * 2.0 ** (0.6 * np.sin(2.0 * np.pi * t / loop_s * 3.0))
        dd = np.log2(np.maximum(f[None, :], 1.0) / centre[:, None]) / 0.8
        return swell[:, None] * np.exp(-0.5 * dd * dd)
    wind = M.tile_shape(wind, wind_gains)
    x = x / max(core.rms(x), 1e-9) + 0.3 * wind / max(core.rms(wind), 1e-9)
    x = M.reverb_loop(x, M.reverb_ir(rng, 5.0, 4.6, 2400.0, predelay_s=0.06), 0.45)
    return M.dc_loop(x)


DRONES = {"crownmarch": drone_march, "greywood": drone_deepwood, "drowned_steps": drone_water,
          "aldmere": drone_martial, "stonehold": drone_high}


def snare_martial(rng: np.random.Generator) -> np.ndarray:
    """Aldmere's combat adds a field drum to the shared drums and brass: a march cadence on the
    zone frame (accents on two and four, a ruff before each bar, a roll into every fourth bar)."""
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(_loop_s(), 1.5)
    for bar in range(12):
        o = bar * 4.0
        pattern = [(0.0, 0.55), (0.5, 0.35), (0.75, 0.3), (1.0, 0.95), (1.5, 0.35), (2.0, 0.55), (2.5, 0.35),
                   (2.75, 0.3), (3.0, 0.95), (3.5, 0.4)]
        if bar % 4 == 3:
            pattern = pattern[:6]
            M.place(buf, (o + 2.0) * bs, roll(rng, 2.0, ZONE_BPM, 0.25, 0.9), 0.8)
        for b, v in pattern:
            M.place(buf, (o + b) * bs + rng.uniform(-0.003, 0.003), snare(rng, v), 0.9)
        for g in (0.125, 0.0625):   # the ruff before the downbeat
            M.place(buf, (o - g) * bs if o > 0 else (48.0 - g) * bs, snare(rng, 0.25), 0.6)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 1.6, 1.2, 4500.0), 0.16)
    return M.dc_loop(fx.soft_clip(x, 2.0))


# --------------------------------------------------------------------------- the bosses


def _hits(rng, buf, hits, bpm):
    M.render_hits(rng, hits, bpm, buf)


# The Iron Regiment: D aeolian, 112 BPM, the bars' roots and thirds (MIDI, octave 2).
REGIMENT_BARS = [(38, 3), (38, 3), (34, 4), (36, 4), (38, 3), (38, 3), (31, 3), (33, 4), (34, 4), (36, 4), (38, 3), (33, 4)]
REGIMENT_TUNE = [
    [("D4", 0, 0.75), ("D4", 0.75, 0.25), ("A4", 1, 1), ("F4", 2, 0.75), ("E4", 2.75, 0.25), ("D4", 3, 1)],
    [("A4", 0, 1.5), ("G4", 1.5, 0.5), ("F4", 2, 1), ("E4", 3, 1)],
    [("F4", 0, 0.75), ("F4", 0.75, 0.25), ("Bb4", 1, 1), ("A4", 2, 1), ("F4", 3, 1)],
    [("G4", 0, 1.5), ("E4", 1.5, 0.5), ("C4", 2, 2)],
    [("D4", 0, 0.75), ("D4", 0.75, 0.25), ("A4", 1, 1), ("D5", 2, 1.5), ("C5", 3.5, 0.5)],
    [("Bb4", 0, 1), ("A4", 1, 1), ("F4", 2, 2)],
    [("G4", 0, 0.75), ("G4", 0.75, 0.25), ("Bb4", 1, 1), ("D5", 2, 1), ("Bb4", 3, 1)],
    [("C#5", 0, 1.5), ("A4", 1.5, 0.5), ("E4", 2, 2)],
    [("F4", 0, 0.75), ("F4", 0.75, 0.25), ("Bb4", 1, 1), ("D5", 2, 1), ("F5", 3, 1)],
    [("E5", 0, 1), ("C5", 1, 1), ("G4", 2, 2)],
    [("A4", 0, 0.75), ("A4", 0.75, 0.25), ("D5", 1, 1), ("F5", 2, 1), ("E5", 3, 1)],
    [("C#5", 0, 1), ("E5", 1, 1), ("A4", 2, 2)],
]
REGIMENT_FIFE = [
    [], [], [], [],
    [("A5", 0, 0.5), ("D6", 0.5, 0.5), ("C6", 1, 0.5), ("A5", 1.5, 0.5), ("D6", 2, 1), ("F6", 3, 1)],
    [("E6", 0, 0.5), ("D6", 0.5, 0.5), ("C6", 1, 1), ("A5", 2, 2)],
    [("Bb5", 0, 0.5), ("D6", 0.5, 0.5), ("G6", 1, 1), ("F6", 2, 0.5), ("D6", 2.5, 0.5), ("Bb5", 3, 1)],
    [("A5", 0, 0.5), ("C#6", 0.5, 0.5), ("E6", 1, 1), ("A6", 2, 2)],
    [("F6", 0, 0.5), ("D6", 0.5, 0.5), ("Bb5", 1, 1), ("D6", 2, 1), ("F6", 3, 1)],
    [("G6", 0, 0.5), ("E6", 0.5, 0.5), ("C6", 1, 1), ("G5", 2, 2)],
    [("A5", 0, 0.5), ("D6", 0.5, 0.5), ("F6", 1, 1), ("E6", 2, 1), ("D6", 3, 1)],
    [("C#6", 0, 0.5), ("E6", 0.5, 0.5), ("A6", 1, 1.5), ("E6", 2.5, 0.5), ("C#6", 3, 1)],
]


def _named(bars) -> list:
    out = []
    for i, bar in enumerate(bars):
        for name, b, d in bar:
            out.append((i * 4.0 + b, d, M.name_midi(name)))
    return out


def _play(rng, buf, notes, bpm, instrument, gain, vel=0.85, offset_beats=0.0, **kw):
    bs = M.beat_s(bpm)
    for b, d, midi in notes:
        v = vel * (1.0 + rng.uniform(-0.05, 0.05))
        M.place(buf, max(0.0, (b + offset_beats) * bs + rng.uniform(-0.005, 0.005)),
                instrument(rng, M.hz(midi), d * bs, v, **kw), gain)


def regiment_drums(rng: np.random.Generator) -> np.ndarray:
    """The Iron Regiment's march drums: bass drums on one and three, snares on two and four with
    ruffs, rolls into every fourth bar, cymbal crashes at bars 1 and 9, and the toms of the
    following ranks."""
    bs = M.beat_s(REGIMENT_BPM)
    buf, period = M.loop_buffer(REGIMENT_BEATS * bs, 2.5)
    hits = [(0.0, M.crash, 0.7, {"decay_s": 1.8}), (32.0, M.crash, 0.65, {"decay_s": 1.8})]
    for bar in range(12):
        o = bar * 4.0
        hits += [(o + 0.0, bass_drum, 1.0, {}), (o + 2.0, bass_drum, 0.9, {}), (o + 3.5, bass_drum, 0.5, {}),
                 (o + 1.5, M.tom, 0.4, {"f0": 125.0}), (o + 3.0, M.tom, 0.35, {"f0": 110.0})]
        for b, v in ((1.0, 0.95), (3.0, 0.95), (0.5, 0.3), (1.75, 0.35), (2.5, 0.3), (3.75, 0.35)):
            hits.append((o + b, snare, v, {}))
        if bar % 4 == 3:
            M.place(buf, (o + 2.0) * bs, roll(rng, 2.0, REGIMENT_BPM, 0.3, 1.0), 0.75)
    _hits(rng, buf, hits, REGIMENT_BPM)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.0, 1.5, 3600.0), 0.2)
    return M.dc_loop(fx.soft_clip(x, 3.0), hz_=28.0)


def regiment_brass(rng: np.random.Generator) -> np.ndarray:
    """The Iron Regiment's theme: a D-minor march on horns over a low brass ostinato on each bar's
    root (DAH. da-DAH DAH), the trombones' chords on the off-beats."""
    bs = M.beat_s(REGIMENT_BPM)
    buf, period = M.loop_buffer(REGIMENT_BEATS * bs, 3.0)
    for bar, (root, third) in enumerate(REGIMENT_BARS):
        o = bar * 4.0
        for b, d, v in ((0.0, 0.7, 1.0), (1.5, 0.3, 0.6), (2.0, 0.7, 0.9), (3.0, 0.6, 0.75)):
            for midi, g in ((root + 12, 1.0), (root + 19, 0.5)):
                s = M.brass(rng, M.hz(midi), d * bs, v, bright=1.1, attack_s=0.02, release_s=0.1, vib_cents=0.0)
                M.place(buf, (o + b) * bs + rng.uniform(-0.003, 0.003), s, g * 0.6)
        for b in (1.0, 3.0):
            for midi in (root + 24, root + 24 + third, root + 31):
                s = M.brass(rng, M.hz(midi), 0.4 * bs, 0.7, bright=0.9, attack_s=0.02, release_s=0.08, vib_cents=0.0)
                M.place(buf, (o + b) * bs, s, 0.22)
    _play(rng, buf, _named(REGIMENT_TUNE), REGIMENT_BPM, M.horn, 0.95, vel=0.9, bright=1.0)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.6, 2.0, 2800.0), 0.24)
    return M.dc_loop(M.circular_band(x, 0.0, 5500.0, 2))


def regiment_fifes(rng: np.random.Generator) -> np.ndarray:
    """Phase 2 of the Iron Regiment: fifes shrilling a counter-line an octave and more above the
    horns (from bar 5), high trumpets on the off-beats and crashes at every fourth bar."""
    bs = M.beat_s(REGIMENT_BPM)
    buf, period = M.loop_buffer(REGIMENT_BEATS * bs, 2.5)
    _play(rng, buf, _named(REGIMENT_FIFE), REGIMENT_BPM, M.flute, 0.8, vel=0.85, breath=0.12, vib_cents=8.0)
    for bar, (root, third) in enumerate(REGIMENT_BARS):
        o = bar * 4.0
        for b in (0.5, 1.5, 2.5, 3.5):
            for midi in (root + 24 + third, root + 31):
                s = trumpet(rng, M.hz(midi), 0.22 * bs, 0.8)
                M.place(buf, (o + b) * bs, s, 0.18)
    hits = [(o * 4.0, M.crash, 0.55, {"decay_s": 1.4}) for o in (3, 7, 11)]
    _hits(rng, buf, hits, REGIMENT_BPM)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.2, 1.7, 3800.0), 0.22)
    return M.dc_loop(M.circular_band(x, 200.0, 7500.0, 2))


def matriarch_drums(rng: np.random.Generator) -> np.ndarray:
    """The Troll Matriarch's wild drums in 6/8: a deep boom on each bar's first beat, frame drums
    and toms rolling on the eighths (DUM-ta-ta dum-ta-TA), shakers, and a tumbling fill every
    fourth bar."""
    bs = M.beat_s(MATRIARCH_BPM)
    e = bs / 3.0
    buf, period = M.loop_buffer(MATRIARCH_BEATS * bs, 2.5)
    for bar in range(16):
        o = bar * 2 * bs
        hits = [(0, M.taiko, 1.0, {"f0": 48.0}), (3, M.taiko, 0.7, {"f0": 52.0}),
                (1, M.frame_drum, 0.45, {"f0": 82.0}), (2, M.frame_drum, 0.5, {"f0": 92.0}),
                (4, M.frame_drum, 0.45, {"f0": 82.0}), (5, M.tom, 0.75, {"f0": 118.0})]
        if bar % 4 == 3:
            hits = [(0, M.taiko, 1.0, {"f0": 48.0})] + [(k, M.tom, 0.45 + 0.08 * k, {"f0": 150.0 - 9.0 * k}) for k in range(1, 6)]
        for k, fn, v, kw in hits:
            M.place(buf, o + k * e + rng.uniform(-0.006, 0.006), fn(rng, v * rng.uniform(0.9, 1.0), **kw), 1.0)
        for k in range(6):
            M.place(buf, o + k * e + rng.uniform(-0.004, 0.004), M.shaker(rng, 0.3 if k % 3 == 0 else 0.18, length_s=0.07), 1.0)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.6, 2.2, 2400.0), 0.26)
    return M.dc_loop(fx.soft_clip(x, 3.2), hz_=26.0)


def matriarch_growl(rng: np.random.Generator) -> np.ndarray:
    """The Troll Matriarch's growl drone: a low choir on D and A swelling with each bar, a saw
    growl a semitone above (E flat) that grinds against it every other bar, and a slow throb."""
    bs = M.beat_s(MATRIARCH_BPM)
    loop_s = MATRIARCH_BEATS * bs
    buf, period = M.loop_buffer(loop_s, 4.0)
    bar_s = 2 * bs
    for bar in range(0, 16, 2):
        o = bar * bar_s
        for midi, vowel, g in ((38, "u", 0.55), (45, "o", 0.4), (50, "u", 0.3)):
            sig = M.choir(rng, M.hz(midi), 2 * bar_s, 0.8, vowel=vowel, voices=4, attack_s=0.6, release_s=0.9,
                          detune_cents=16.0, breath=0.08)
            M.place(buf, o, sig, g)
        n = M.frames(bar_s * 1.1)
        t = fx.t_axis(n)
        grind = 39 if bar % 4 == 2 else 38
        f = M.hz(grind) * (1.0 + 0.01 * np.sin(TWO_PI * 5.5 * t))
        saw = core.saw(f, n) * M.env_note(n, RATE, 0.25, bar_s * 0.8, 0.3) * (0.6 + 0.4 * np.sin(TWO_PI * 31.0 * t) ** 2)
        M.place(buf, o + bar_s, saw, 0.35)
    x = M.fold(buf, period)
    x = M.circular_band(x, 28.0, 1800.0, 2)
    t = np.arange(period) / RATE
    x = x * (0.8 + 0.2 * np.sin(TWO_PI * t / bar_s) ** 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 3.5, 3.0, 1600.0), 0.32)
    return M.dc_loop(x, hz_=26.0)


def matriarch_howl(rng: np.random.Generator) -> np.ndarray:
    """Phase 2 of the Matriarch: a wailing reed howling up a minor sixth and sliding down every two
    bars, the brood's bone rattles on the off-eighths."""
    bs = M.beat_s(MATRIARCH_BPM)
    e = bs / 3.0
    loop_s = MATRIARCH_BEATS * bs
    buf, period = M.loop_buffer(loop_s, 3.0)
    bar_s = 2 * bs
    for bar in range(0, 16, 2):
        n = M.frames(bar_s * 1.8)
        t = fx.t_axis(n)
        top = 74 if bar % 4 == 0 else 75
        curve = np.clip(t / (bar_s * 0.6), 0.0, 1.0)
        fall = np.clip((t - bar_s * 1.1) / (bar_s * 0.6), 0.0, 1.0)
        midi = 66 + (top - 66) * curve - 7 * fall
        f = 440.0 * 2.0 ** ((midi - 69) / 12.0) * M.vibrato(n, RATE, rng, 6.5, 30.0, 0.2, 0.3)
        w = M.formant_weights(float(f[0]), 18, [1100.0, 2600.0], [500.0, 900.0], tilt=-1.0)
        tone = M.additive(f, w / w.max(), RATE, rng)
        tone = tone / max(core.peak(tone), 1e-9) * M.env_note(n, RATE, 0.3, bar_s * 1.4, 0.4)
        M.place(buf, bar * bar_s + 0.5 * bs, tone, 0.5)
    for bar in range(16):
        for k in (1, 2, 4, 5):
            m = M.frames(0.08)
            rattle = ins.crackle(rng, m, RATE, 0.0, 0.06, 900.0, 1500.0, 6000.0)
            M.place(buf, bar * bar_s + k * e, rattle / max(core.peak(rattle), 1e-9), 0.18)
    x = M.fold(buf, period)
    x = M.circular_band(x, 250.0, 6500.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 3.0, 2.6, 3000.0), 0.3)
    return M.dc_loop(x)


# Harrok: D phrygian (D Eb F G A Bb C), 72 BPM, 8 bars in half time; the bars' roots.
HARROK_ROOTS = [38, 38, 39, 38, 36, 34, 39, 38]
HARROK_CHANT = [   # (bar, beat, length, phrygian degree from D3) - the clan's chant
    (0, 0.0, 1.0, 0), (0, 1.0, 0.5, 1), (0, 1.5, 0.5, 0), (0, 2.0, 2.0, -1),
    (1, 0.0, 1.0, 0), (1, 1.0, 1.0, 2), (1, 2.0, 2.0, 1),
    (2, 0.0, 1.0, 1), (2, 1.0, 0.5, 2), (2, 1.5, 0.5, 1), (2, 2.0, 2.0, 0),
    (3, 0.0, 1.0, 0), (3, 1.0, 1.0, -1), (3, 2.0, 2.0, 0),
    (4, 0.0, 1.0, -1), (4, 1.0, 1.0, 0), (4, 2.0, 2.0, 2),
    (5, 0.0, 1.0, 3), (5, 1.0, 1.0, 2), (5, 2.0, 2.0, 1),
    (6, 0.0, 1.0, 1), (6, 1.0, 0.5, 2), (6, 1.5, 0.5, 3), (6, 2.0, 2.0, 4),
    (7, 0.0, 1.0, 3), (7, 1.0, 1.0, 1), (7, 2.0, 2.0, 0),
]


def _phrygian(degree: int, tonic: int = 50) -> int:
    return M.degree_midi(degree, PHRYGIAN, tonic)


def harrok_drums(rng: np.random.Generator) -> np.ndarray:
    """Harrok's giant drums, half time: an enormous boom on one, a cracking hit on three, the
    great toms answering in between, and a slow roll of booms into every fourth bar."""
    bs = M.beat_s(HARROK_BPM)
    buf, period = M.loop_buffer(HARROK_BEATS * bs, 3.0)
    hits = [(0.0, M.crash, 0.6, {"decay_s": 2.4})]
    for bar in range(8):
        o = bar * 4.0
        hits += [(o + 0.0, M.taiko, 1.0, {"f0": 42.0}), (o + 2.0, M.taiko, 0.95, {"f0": 50.0}),
                 (o + 2.0, M.rim, 0.7, {}), (o + 1.0, M.tom, 0.45, {"f0": 92.0}), (o + 3.0, M.tom, 0.5, {"f0": 84.0}),
                 (o + 1.5, M.taiko, 0.4, {"f0": 46.0})]
        if bar % 4 == 3:
            hits += [(o + 3.0 + 0.25 * k, M.taiko, 0.5 + 0.12 * k, {"f0": 44.0}) for k in range(4)]
    _hits(rng, buf, hits, HARROK_BPM)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 3.4, 2.8, 2200.0, predelay_s=0.04), 0.3)
    return M.dc_loop(fx.soft_clip(x, 4.2), hz_=24.0)


def harrok_choir(rng: np.random.Generator) -> np.ndarray:
    """Harrok's clan chanting: a low male choir in D phrygian (the E flat above the tonic) in
    octaves and fifths, short shouted syllables on the half-time backbeat."""
    bs = M.beat_s(HARROK_BPM)
    buf, period = M.loop_buffer(HARROK_BEATS * bs, 4.0)
    for bar, b, d, deg in HARROK_CHANT:
        midi = _phrygian(deg)
        for off, vowel, g in ((0, "a", 0.6), (-12, "o", 0.45), (7, "o", 0.25)):
            sig = M.choir(rng, M.hz(midi + off), d * bs * 0.95, 0.85, vowel=vowel, voices=5, attack_s=0.08,
                          release_s=0.35, detune_cents=14.0, breath=0.07)
            M.place(buf, (bar * 4.0 + b) * bs, sig, g)
    for bar in range(8):
        for root_off in (0, 7):
            sig = M.choir(rng, M.hz(HARROK_ROOTS[bar] + root_off), 3.8 * bs, 0.6, vowel="u", voices=4, attack_s=0.8,
                          release_s=1.2, detune_cents=12.0)
            M.place(buf, bar * 4.0 * bs, sig, 0.22)
    x = M.fold(buf, period)
    x = M.circular_band(x, 40.0, 3800.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.0, 3.4, 2200.0, predelay_s=0.05), 0.38)
    return M.dc_loop(x)


def harrok_horns(rng: np.random.Generator) -> np.ndarray:
    """Phase 2 of Harrok: giant horns calling back to the chant (the phrygian fall E flat - D), the
    second horn a fifth below, bar by bar."""
    bs = M.beat_s(HARROK_BPM)
    buf, period = M.loop_buffer(HARROK_BEATS * bs, 4.0)
    calls = [(0, 2.0, 2.0, 1), (1, 0.0, 2.0, 0), (2, 2.0, 1.0, 2), (2, 3.0, 1.0, 1), (3, 0.0, 3.0, 0),
             (4, 2.0, 2.0, 4), (5, 0.0, 2.0, 3), (6, 2.0, 1.0, 5), (6, 3.0, 1.0, 4), (7, 0.0, 3.0, 4)]
    for bar, b, d, deg in calls:
        midi = _phrygian(deg, 38)
        M.place(buf, (bar * 4.0 + b) * bs, giant_horn(rng, M.hz(midi + 12), d * bs, 0.9), 0.8)
        M.place(buf, (bar * 4.0 + b) * bs + 0.02, giant_horn(rng, M.hz(midi + 5), d * bs, 0.7), 0.45)
    x = M.fold(buf, period)
    x = M.circular_band(x, 30.0, 3500.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.2, 3.6, 1800.0, predelay_s=0.06), 0.4)
    return M.dc_loop(x)


# --------------------------------------------------------------------------- stingers


def _buf(length_s: float, tail_s: float = 3.0) -> np.ndarray:
    return np.zeros(M.frames(length_s + tail_s))


def _note(rng, buf, at_s, instrument, name_or_midi, dur_s, vel=0.85, gain=1.0, **kw):
    midi = M.name_midi(name_or_midi) if isinstance(name_or_midi, str) else name_or_midi
    M.place(buf, at_s, instrument(rng, M.hz(midi), dur_s, vel, **kw), gain)


def _hit(rng, buf, at_s, fn, vel=1.0, gain=1.0, **kw):
    M.place(buf, at_s, fn(rng, vel, **kw), gain)


def _finish(rng, buf, length_s, rt60=2.6, wet=0.3, fade_s=0.6, lp=6000.0, drive=1.0) -> np.ndarray:
    """P23's stinger finish: the room, cut to the length with a smooth fade, an optional gentle
    saturation that tames drum transients."""
    x = M.reverb_tail(buf, M.reverb_ir(rng, min(3.5, rt60 * 1.15), rt60, 2800.0), wet)
    x = fx.lowpass(x, lp, 2.0)
    if drive > 1.0:
        x = fx.soft_clip(x, drive)
    n = M.frames(length_s)
    x = x[:n] if x.shape[0] >= n else np.concatenate([x, np.zeros(n - x.shape[0])])
    f = M.frames(fade_s)
    x[-f:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, f))
    return M.finish_oneshot(x, floor_db=-70.0, fade_s=0.02)


def discovery(rng: np.random.Generator) -> np.ndarray:
    """A place found (3 s): bells ringing up D-A-D-E over a soft open fifth, a horn answering."""
    buf = _buf(3.0)
    for i, name in enumerate(("D5", "A5", "D6", "E6")):
        _note(rng, buf, 0.12 * i, bell, name, 1.5, 0.7 - 0.05 * i, 0.55, decay_s=1.6)
    for name in ("D4", "A4"):
        _note(rng, buf, 0.0, M.pad, name, 2.0, 0.6, 0.22, attack_s=0.4, release_s=0.8, wave="triangle")
    _note(rng, buf, 0.45, M.horn, "A4", 1.1, 0.75, 0.55)
    _note(rng, buf, 0.45, M.horn, "D4", 1.1, 0.65, 0.4)
    return _finish(rng, buf, 3.0, rt60=2.8, wet=0.34, fade_s=0.8)


def world_reveal(rng: np.random.Generator) -> np.ndarray:
    """A vista (6 s): the whole kingdom in view - a timpani roll swelling under the choir opening
    on an open D (D-A-D-E-A), horns climbing A-D-E to F#, and a bell at the top."""
    buf = _buf(6.0)
    times = np.cumsum(np.linspace(0.2, 0.06, 16))
    for i, t in enumerate(times[times < 2.2]):
        _hit(rng, buf, float(t) - times[0], M.timpani, 0.2 + 0.5 * i / 15.0, 0.8, f0=73.4)
    for name, at in (("D3", 0.0), ("A3", 0.4), ("D4", 0.8), ("E4", 1.2), ("A4", 1.6)):
        _note(rng, buf, at, M.choir, name, 5.0 - at, 0.8, 0.45, vowel="a", attack_s=0.9, release_s=1.4)
    for name, at, dur in (("A3", 0.6, 0.8), ("D4", 1.3, 0.8), ("E4", 2.0, 0.6), ("F#4", 2.5, 2.8)):
        _note(rng, buf, at, M.horn, name, dur, 0.85, 0.6)
    _note(rng, buf, 2.5, M.horn, "A3", 2.8, 0.7, 0.4)
    _note(rng, buf, 2.5, bell, "D6", 2.0, 0.5, 0.25, decay_s=2.5)
    _hit(rng, buf, 2.5, M.timpani, 0.9, 0.8, f0=73.4)
    _hit(rng, buf, 2.5, M.crash, 0.4, 0.25, decay_s=3.0)
    _note(rng, buf, 0.0, M.sub, "D2", 5.0, 0.8, 0.45, attack_s=2.0, release_s=1.5)
    return _finish(rng, buf, 6.0, rt60=3.4, wet=0.36, fade_s=1.4, drive=1.4)


def yield_(rng: np.random.Generator) -> np.ndarray:
    """A foe yields (4 s): the strings settle down the scale A-G-F#-E-D over a plagal cadence (G to
    D major) on horns: relief, not triumph."""
    buf = _buf(4.0)
    for i, name in enumerate(("A4", "G4", "F#4", "E4", "D4")):
        _note(rng, buf, 0.35 * i, M.strings, name, 0.5 if i < 4 else 2.0, 0.75, 0.5, voices=4, attack_s=0.08,
              release_s=0.4)
    for name in ("G3", "B3", "D4"):
        _note(rng, buf, 0.0, M.horn, name, 1.3, 0.7, 0.4, attack_s=0.3)
    for name in ("F#3", "A3", "D4"):
        _note(rng, buf, 1.4, M.horn, name, 2.2, 0.75, 0.45, attack_s=0.3)
    _note(rng, buf, 1.4, M.sub, "D2", 2.2, 0.7, 0.4, attack_s=0.3, release_s=1.0)
    return _finish(rng, buf, 4.0, rt60=2.8, wet=0.32, fade_s=1.1)


def ancestry(rng: np.random.Generator) -> np.ndarray:
    """An ancestry chosen (4 s): a low bell, an ancient open-fifth choir (D-A-D) rising to the
    giant horn's long A."""
    buf = _buf(4.0)
    _note(rng, buf, 0.0, bell, "D3", 3.5, 0.65, 0.5, decay_s=3.5)
    for name, g in (("D3", 0.5), ("A3", 0.45), ("D4", 0.35)):
        _note(rng, buf, 0.1, M.choir, name, 3.0, 0.8, g, vowel="o", attack_s=0.7, release_s=1.0)
    _note(rng, buf, 0.9, giant_horn, "A3", 2.2, 0.85, 0.7)
    _note(rng, buf, 0.0, M.sub, "D2", 3.0, 0.8, 0.4, attack_s=0.5, release_s=1.0)
    return _finish(rng, buf, 4.0, rt60=3.4, wet=0.38, fade_s=1.0, lp=5000.0)


def crowned(rng: np.random.Generator) -> np.ndarray:
    """The throne taken (10 s): the title theme's opening on the full brass and choir in D major,
    a timpani roll to its long last chord, a bell over it."""
    bs = M.beat_s(96.0)
    buf = _buf(10.0)
    tune = (("A4", 0, 1.5), ("D5", 1.5, 0.5), ("D5", 2, 1), ("E5", 3, 1), ("F#5", 4, 2), ("E5", 6, 1),
            ("D5", 7, 1), ("A5", 8, 6.5))
    harmony = (("F#4", 0, 1.5), ("A4", 1.5, 2.5), ("D5", 4, 2), ("C#5", 6, 1), ("A4", 7, 1), ("D5", 8, 6.5))
    bass = (("D3", 0, 2), ("A3", 2, 2), ("D3", 4, 2), ("A2", 6, 2), ("D3", 8, 6.5))
    for notes, inst, g, v in ((tune, M.horn, 1.0, 0.92), (tune, trumpet, 0.35, 0.8), (harmony, M.horn, 0.6, 0.78),
                              (bass, M.horn, 0.6, 0.75)):
        for name, b, d in notes:
            _note(rng, buf, b * bs, inst, name, d * bs, v, g)
    for name in ("D3", "A3", "D4", "F#4", "A4", "D5"):
        _note(rng, buf, 4 * bs, M.choir, name, 10.5 * bs, 0.8, 0.32, vowel="a", attack_s=1.0, release_s=1.5)
    for k in range(14):
        _hit(rng, buf, 6.0 * bs + 0.12 * k, M.timpani, 0.3 + 0.045 * k, 0.6, f0=73.4)
    _hit(rng, buf, 8 * bs, M.timpani, 1.0, 0.9, f0=73.4)
    _hit(rng, buf, 8 * bs, M.crash, 0.55, 0.32, decay_s=4.0)
    _note(rng, buf, 8 * bs, bell, "D6", 4.0, 0.5, 0.25, decay_s=3.5)
    _note(rng, buf, 0.0, M.sub, "D2", 9.5, 0.8, 0.4, attack_s=3.0, release_s=2.0)
    return _finish(rng, buf, 10.0, rt60=3.6, wet=0.36, fade_s=2.0, drive=1.4)


def rout(rng: np.random.Generator) -> np.ndarray:
    """A formation routs (3 s): fleeing armies sound triumphant - a snare roll, a brass flourish up
    D major (D-F#-A-D) and a crash."""
    buf = _buf(3.0)
    M.place(buf, 0.0, roll(rng, 1.4, 96.0, 0.3, 0.9), 0.7)
    for i, name in enumerate(("D4", "F#4", "A4", "D5")):
        _note(rng, buf, 0.42 + 0.1 * i, trumpet, name, 0.18 if i < 3 else 1.4, 0.85, 0.7)
    for name in ("D3", "A3", "F#4"):
        _note(rng, buf, 0.72, M.brass, name, 1.4, 0.85, 0.45, bright=1.1, attack_s=0.03)
    _hit(rng, buf, 0.72, M.crash, 0.6, 0.35, decay_s=1.8)
    _hit(rng, buf, 0.72, M.taiko, 0.9, 0.7)
    return _finish(rng, buf, 3.0, rt60=2.2, wet=0.26, fade_s=0.8, drive=1.8)


def _combat_frame(rng, buf):
    """Two bars at 96 BPM of drums under every region's combat intro: taiko on the beats of bar 1,
    a tom run into bar 2's downbeat."""
    bs = M.beat_s(96.0)
    for b, v in ((0.0, 1.0), (1.0, 0.7), (2.0, 0.9), (3.0, 0.7), (3.5, 0.75)):
        _hit(rng, buf, b * bs, M.taiko, v, 0.85)
    for k in range(8):
        _hit(rng, buf, (6.0 + 0.25 * k) * bs, M.tom, 0.45 + 0.06 * k, 0.85, f0=165.0 - 6.0 * k)
    _hit(rng, buf, 4.0 * bs, M.crash, 0.55, 0.35, decay_s=2.0)
    _hit(rng, buf, 4.0 * bs, M.taiko, 1.0, 0.9)


def combat_crownmarch(rng: np.random.Generator) -> np.ndarray:
    """The Crownmarch's combat intro (5 s): fiddle stabs on D-A, a run up to the high D, the
    drums under it."""
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    _combat_frame(rng, buf)
    for b, name, d in ((0.0, "D5", 0.3), (0.5, "A4", 0.3), (1.0, "D5", 0.3), (2.0, "F5", 0.3), (2.5, "E5", 0.3),
                       (3.0, "D5", 0.3), (3.5, "A5", 0.4)):
        _note(rng, buf, b * bs, fiddle, name, d * bs, 0.95, 0.7)
    for k, name in enumerate(("D5", "E5", "F5", "G5", "A5", "B5", "C6", "D6")):
        _note(rng, buf, (4.0 + 0.25 * k) * bs, fiddle, name, 0.22 * bs, 0.8 + 0.02 * k, 0.6)
    _note(rng, buf, 6.0 * bs, fiddle, "D6", 1.8 * bs, 0.95, 0.65)
    return _finish(rng, buf, 5.0, rt60=1.8, wet=0.22, fade_s=0.45, drive=2.4)


def combat_greywood(rng: np.random.Generator) -> np.ndarray:
    """The Greywood's combat intro (5 s): the reed screams a falling A-G-F-E, a low choir surges,
    toms roll."""
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    _combat_frame(rng, buf)
    for b, name, d in ((0.0, "A5", 1.0), (1.0, "G5", 0.5), (1.5, "F5", 0.5), (2.0, "E5", 1.8)):
        _note(rng, buf, b * bs, reed, name, d * bs, 0.95, 0.7)
    for name in ("D3", "A3"):
        _note(rng, buf, 0.0, M.choir, name, 7.5 * bs, 0.85, 0.45, vowel="o", attack_s=0.8, release_s=0.8)
    _note(rng, buf, 4.0 * bs, reed, "D5", 3.5 * bs, 0.9, 0.6)
    return _finish(rng, buf, 5.0, rt60=2.6, wet=0.3, fade_s=0.45, drive=2.0)


def combat_drowned_steps(rng: np.random.Generator) -> np.ndarray:
    """The Drowned Steps' combat intro (5 s): bells clanging a falling D-A-F in octaves over the
    drums, a low bell tolling on bar 2."""
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    _combat_frame(rng, buf)
    for b, name in ((0.0, "D6"), (0.5, "A5"), (1.0, "F5"), (2.0, "D6"), (2.5, "A5"), (3.0, "F5"), (3.5, "E5")):
        _note(rng, buf, b * bs, bell, name, 0.5, 0.8, 0.5, decay_s=1.2)
        _note(rng, buf, b * bs, bell, M.name_midi(name) - 12, 0.5, 0.6, 0.3, decay_s=1.5)
    _note(rng, buf, 4.0 * bs, bell, "D3", 3.0, 0.8, 0.5, decay_s=3.0)
    _note(rng, buf, 4.0 * bs, M.choir, "D4", 3.0 * bs, 0.8, 0.35, vowel="a", attack_s=0.4)
    return _finish(rng, buf, 5.0, rt60=2.8, wet=0.32, fade_s=0.45, drive=1.8)


def combat_aldmere(rng: np.random.Generator) -> np.ndarray:
    """Aldmere's combat intro (5 s): a trumpet fanfare (D D F A D) over a snare roll, the brass
    hitting the downbeat of bar 2."""
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    _combat_frame(rng, buf)
    M.place(buf, 0.0, roll(rng, 4.0, 96.0, 0.25, 0.85), 0.55)
    for b, name, d in ((0.5, "D5", 0.2), (0.75, "D5", 0.2), (1.0, "F5", 0.45), (1.5, "A5", 0.45), (2.0, "D6", 1.8)):
        _note(rng, buf, b * bs, trumpet, name, d * bs, 0.95, 0.7)
    for name, g in (("D3", 1.0), ("A3", 0.7), ("D4", 0.5)):
        _note(rng, buf, 4.0 * bs, M.brass, name, 1.2 * bs, 1.0, 0.55 * g, bright=1.25, attack_s=0.02)
    return _finish(rng, buf, 5.0, rt60=2.0, wet=0.24, fade_s=0.45, drive=2.2)


def combat_stonehold(rng: np.random.Generator) -> np.ndarray:
    """The Stonehold's combat intro (5 s): the giant horn's blast on A then D, a wide choir on D
    minor, the great drums."""
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    _combat_frame(rng, buf)
    _note(rng, buf, 0.0, giant_horn, "A2", 1.8 * bs, 1.0, 0.85)
    _note(rng, buf, 2.0 * bs, giant_horn, "D3", 4.0 * bs, 1.0, 0.85)
    for name in ("D3", "A3", "D4", "F4"):
        _note(rng, buf, 2.0 * bs, M.choir, name, 5.5 * bs, 0.8, 0.35, vowel="a", attack_s=0.6)
    return _finish(rng, buf, 5.0, rt60=3.2, wet=0.34, fade_s=0.45, drive=1.8)


REGIMENT_INTRO_S = 4.0 * M.beat_s(REGIMENT_BPM)
MATRIARCH_INTRO_S = 2.0 * M.beat_s(MATRIARCH_BPM)
HARROK_INTRO_S = 4.0 * M.beat_s(HARROK_BPM)


def boss_regiment(rng: np.random.Generator) -> np.ndarray:
    """The Iron Regiment's one-bar intro at 112 BPM: a snare roll swelling into a brass stab on D
    minor, the bass drums on the last two beats."""
    bs = M.beat_s(REGIMENT_BPM)
    buf = _buf(REGIMENT_INTRO_S)
    M.place(buf, 0.0, roll(rng, 3.0, REGIMENT_BPM, 0.2, 1.0), 0.75)
    for name, g in (("D3", 1.0), ("A3", 0.7), ("D4", 0.55), ("F4", 0.45)):
        _note(rng, buf, 0.0, M.brass, name, 3.6 * bs, 1.0, g * 0.55, bright=1.2, attack_s=0.9)
    _hit(rng, buf, 2.0 * bs, bass_drum, 0.9, 0.8)
    _hit(rng, buf, 3.0 * bs, bass_drum, 1.0, 0.9)
    _hit(rng, buf, 3.0 * bs, M.crash, 0.55, 0.3, decay_s=1.2)
    return _finish(rng, buf, REGIMENT_INTRO_S + 0.1, rt60=1.6, wet=0.18, fade_s=0.2)


def boss_matriarch(rng: np.random.Generator) -> np.ndarray:
    """The Matriarch's one-bar intro (6/8 at 84): the growl swelling on D, a boom, and the toms
    tumbling down the last beat."""
    bs = M.beat_s(MATRIARCH_BPM)
    e = bs / 3.0
    buf = _buf(MATRIARCH_INTRO_S)
    _hit(rng, buf, 0.0, M.taiko, 1.0, 1.0, f0=46.0)
    for name, g in (("D2", 0.6), ("A2", 0.4), ("Eb3", 0.3)):
        _note(rng, buf, 0.0, M.choir, name, 1.9 * bs, 0.9, g, vowel="u", attack_s=0.4)
    n = M.frames(1.7 * bs)
    t = fx.t_axis(n)
    growl = core.saw(M.hz(38) * (1.0 + 0.02 * np.sin(TWO_PI * 6.0 * t)), n) * np.clip(t / (1.2 * bs), 0.0, 1.0) ** 2
    M.place(buf, 0.1, growl * (0.6 + 0.4 * np.sin(TWO_PI * 29.0 * t) ** 2), 0.25)
    for k in range(3):
        _hit(rng, buf, bs + (k + 0.0) * e, M.tom, 0.6 + 0.15 * k, 0.85, f0=140.0 - 18.0 * k)
    return _finish(rng, buf, MATRIARCH_INTRO_S + 0.12, rt60=2.0, wet=0.22, fade_s=0.2, lp=4500.0)


def boss_harrok(rng: np.random.Generator) -> np.ndarray:
    """Harrok's one-bar intro (72 BPM): an enormous drum boom, the clan's shout on D and E flat, the
    giant horn sliding down to D."""
    bs = M.beat_s(HARROK_BPM)
    buf = _buf(HARROK_INTRO_S)
    _hit(rng, buf, 0.0, M.taiko, 1.0, 1.0, f0=40.0)
    _hit(rng, buf, 2.0 * bs, M.taiko, 0.95, 0.9, f0=48.0)
    _hit(rng, buf, 2.0 * bs, M.crash, 0.5, 0.25, decay_s=1.6)
    for name, g in (("D3", 0.6), ("Eb3", 0.35), ("A3", 0.35)):
        _note(rng, buf, 0.0, M.choir, name, 1.6 * bs, 0.95, g, vowel="a", attack_s=0.06, release_s=0.3)
    _note(rng, buf, 2.0 * bs, giant_horn, "D3", 1.9 * bs, 1.0, 0.8)
    return _finish(rng, buf, HARROK_INTRO_S + 0.12, rt60=2.6, wet=0.26, fade_s=0.25, lp=4500.0)


# --------------------------------------------------------------------------- the build list

# The build's pre-encoding budget estimate per cue (KB of Ogg per second besides the headers), the
# P23 rates by kind until the encoded files calibrate them.
EST_KBPS = {}


def _loop(name, func, seed, params, frame=ZONE_FRAME, bpm=ZONE_BPM, beats=ZONE_BEATS, beats_per_bar=4, quality=0,
          lufs=-20.0, est=3.2):
    return {"name": name, "path": _P + name + ".ogg", "seed": seed, "func": func, "params": params,
            "kind": "loop", "scope": "world", "bpm": bpm, "beats": beats, "beats_per_bar": beats_per_bar,
            "frame": frame, "quality": quality, "rate": RATE, "norm": {"lufs": lufs, "max_peak_db": -3.0},
            "est_kbps": EST_KBPS.get(name, est)}


def _stinger(name, func, seed, lufs=-16.0, quality=2):
    return {"name": "stinger_" + name, "path": _P + "stinger_" + name + ".ogg", "seed": seed, "func": func,
            "params": {}, "kind": "oneshot", "scope": "world", "quality": quality, "rate": RATE,
            "norm": {"lufs": lufs, "max_peak_db": -3.0}, "est_kbps": EST_KBPS.get("stinger_" + name, 4.6)}


DRONE_LUFS = Z.DRONE_LUFS
MELODY_LUFS = Z.MELODY_LUFS
CUES = []
for _i, _region in enumerate(REGIONS):
    CUES.append(_loop("drone_" + DRONE_STEMS[_region], DRONES[_region], 280001 + _i, {}, lufs=DRONE_LUFS))
for _i, (_region, _v) in enumerate([(r, v) for r in REGIONS for v in ("a", "b", "c")]):
    CUES.append(_loop("melody_%s_%s" % (MELODY_STEMS[_region], _v), melody, 280010 + _i,
                      {"region": _region, "variant": _v}, lufs=MELODY_LUFS, est=3.0))
CUES += [
    _loop("snare_martial", snare_martial, 280030, {}, quality=1, lufs=-21.0, est=4.0),
    _loop("regiment_drums", regiment_drums, 280040, {}, frame=REGIMENT_FRAME, bpm=REGIMENT_BPM, beats=REGIMENT_BEATS,
          quality=1, lufs=-16.0, est=4.0),
    _loop("regiment_brass", regiment_brass, 280041, {}, frame=REGIMENT_FRAME, bpm=REGIMENT_BPM, beats=REGIMENT_BEATS,
          quality=1, lufs=-17.0, est=4.0),
    _loop("regiment_fifes", regiment_fifes, 280042, {}, frame=REGIMENT_FRAME, bpm=REGIMENT_BPM, beats=REGIMENT_BEATS,
          quality=1, lufs=-19.0, est=4.0),
    _loop("matriarch_drums", matriarch_drums, 280050, {}, frame=MATRIARCH_FRAME, bpm=MATRIARCH_BPM,
          beats=MATRIARCH_BEATS, beats_per_bar=MATRIARCH_BEATS_PER_BAR, quality=1, lufs=-16.0, est=4.0),
    _loop("matriarch_growl", matriarch_growl, 280051, {}, frame=MATRIARCH_FRAME, bpm=MATRIARCH_BPM,
          beats=MATRIARCH_BEATS, beats_per_bar=MATRIARCH_BEATS_PER_BAR, quality=1, lufs=-17.0, est=4.0),
    _loop("matriarch_howl", matriarch_howl, 280052, {}, frame=MATRIARCH_FRAME, bpm=MATRIARCH_BPM,
          beats=MATRIARCH_BEATS, beats_per_bar=MATRIARCH_BEATS_PER_BAR, quality=1, lufs=-19.0, est=4.0),
    _loop("harrok_drums", harrok_drums, 280060, {}, frame=HARROK_FRAME, bpm=HARROK_BPM, beats=HARROK_BEATS,
          quality=1, lufs=-16.0, est=4.0),
    _loop("harrok_choir", harrok_choir, 280061, {}, frame=HARROK_FRAME, bpm=HARROK_BPM, beats=HARROK_BEATS,
          quality=1, lufs=-17.0, est=4.0),
    _loop("harrok_horns", harrok_horns, 280062, {}, frame=HARROK_FRAME, bpm=HARROK_BPM, beats=HARROK_BEATS,
          quality=1, lufs=-19.0, est=4.0),
    _stinger("discovery", discovery, 280101),
    _stinger("world_reveal", world_reveal, 280102),
    _stinger("yield", yield_, 280103),
    _stinger("ancestry", ancestry, 280104),
    _stinger("crowned", crowned, 280105),
    _stinger("rout", rout, 280106),
    _stinger("combat_crownmarch", combat_crownmarch, 280111),
    _stinger("combat_greywood", combat_greywood, 280112),
    _stinger("combat_drowned_steps", combat_drowned_steps, 280113),
    _stinger("combat_aldmere", combat_aldmere, 280114),
    _stinger("combat_stonehold", combat_stonehold, 280115),
    _stinger("boss_regiment", boss_regiment, 280121),
    _stinger("boss_matriarch", boss_matriarch, 280122),
    _stinger("boss_harrok", boss_harrok, 280123),
]
