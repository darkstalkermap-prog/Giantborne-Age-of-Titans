"""The Valley's adaptive score (P23; plan M6-M9 decision 5, sections 4.2, 4.3 and 4.5): the zone
frame's stems (D dorian, 96 BPM, 4/4, twelve bars = 30.0 s), the title theme and the Ogre King's
set in its own frame (D aeolian, 104 BPM, twelve bars = 27.69 s).

The zone frame shares one harmony, so the danger and combat stems fit every district:

    bars  1-4  Dm  Dm  C   Dm        (home: the statement)
    bars  5-8  G   G   Am  C         (the dorian lift: B natural)
    bars  9-12 F   C   G   Asus-A    (the journey back: A pulls to Dm at the loop)

Three zone sets, each a drone and three melody variants written from one motif by the phrase
writer (synth/music.py), four-bar phrases that start after a segment's downbeat and end before
its last half beat, so the melody scheduler can switch variants or rest at any segment:

    calm    "A-D-E-F, E-D" - a rising fourth and a step to the minor third, on a plucked lute
            over a warm pad (Giant's Hollow, Thornwick and the fields, the sandbox)
    wild    "D-C-A, (B-A) G-A-F" - a falling third and a turn through the dorian B, on a low
            breathy flute over a dark pad with wind (the Old Wood, the Raider Quarry)
    ancient "D ... A, G-F-E" - a rising fifth and a slow fall, on a horn over a stone choir and
            a low bell (the Barrow, the Ruins, Kingsfall)

Shared: `pulse` (danger: a frame-drum heartbeat and a ticking shaker), `combat_drums` (taiko,
toms, rim), `combat_brass` (a low brass ostinato on the chord roots, a swell every fourth bar)
and `title_theme` (a three-horn choir playing the game's theme, which opens on the calm motif's
rising fourth). The Ogre King: `boss_drums` (double-time taiko), `boss_theme` (a chromatic low
brass ostinato and the King's call), `boss_frenzy` (phase 2: a string tremolo with semitone
clashes and a rising scream).

Every stem is mono at 22.05 kHz; loops are exactly bars x 4 x 60 / bpm seconds (the build checks
the frame count) and seamless (tails folded onto the head, circular reverb).
"""

from __future__ import annotations

import numpy as np

from synth import core, fx, music as M

FAMILY = "music"
RATE = core.DEFAULT_RATE
_P = "res://assets/audio/music/"

ZONE_BPM = 96.0
ZONE_BEATS = 48
ZONE_FRAME = "zone_96"
BOSS_BPM = 104.0
BOSS_BEATS = 48
BOSS_FRAME = "boss_104"
SEGMENT_BEATS = 16
# The last half beat of every melody segment fades to silence (melody()).
SEGMENT_FADE_BEATS = 0.5

# --------------------------------------------------------------------------- the zone harmony

# Per bar: (chord name, chord degrees (D dorian, mod 7), pad voicing (MIDI), bass root (MIDI)).
ZONE_CHORDS = [
    ("Dm", (0, 2, 4), (57, 62, 65), 38),
    ("Dm", (0, 2, 4), (57, 62, 65), 38),
    ("C", (6, 1, 3), (55, 60, 64), 36),
    ("Dm", (0, 2, 4), (57, 62, 65), 38),
    ("G", (3, 5, 0), (59, 62, 67), 43),
    ("G", (3, 5, 0), (59, 62, 67), 43),
    ("Am", (4, 6, 1), (57, 60, 64), 45),
    ("C", (6, 1, 3), (55, 60, 64), 36),
    ("F", (2, 4, 6), (57, 60, 65), 41),
    ("C", (6, 1, 3), (55, 60, 64), 36),
    ("G", (3, 5, 0), (59, 62, 67), 43),
    ("A", (4, 6, 1), (57, 61, 64), 45),
]
ASUS_VOICING = (57, 62, 64)   # the first half of bar 12


def zone_chord_spans() -> list:
    """[(start_beat, length_beats, pad MIDI notes, bass MIDI)] with repeated chords merged and
    bar 12 split into Asus4 and A."""
    spans = []
    for i, (name, _deg, voicing, bass) in enumerate(ZONE_CHORDS):
        if i == 11:
            spans.append((44.0, 2.0, ASUS_VOICING, bass))
            spans.append((46.0, 2.0, voicing, bass))
            continue
        if spans and spans[-1][2] == voicing and spans[-1][3] == bass:
            b, d, v, bs = spans[-1]
            spans[-1] = (b, d + 4.0, v, bs)
        else:
            spans.append((i * 4.0, 4.0, voicing, bass))
    return spans


# --------------------------------------------------------------------------- the melodies
# Degrees count from D4 (0): D4 0, E4 1, F4 2, G4 3, A4 4, B4 5, C5 6, D5 7, E5 8, F5 9, G5 10,
# A5 11, B5 12, C6 13, D6 14; below: C4 -1, B3 -2, A3 -3, G3 -4, F3 -5, E3 -6, D3 -7, C3 -8.
# A bar is ("m", anchor, {opts}) (the motif on an anchor degree: invert, shift, take, aug,
# octave), ("n", [(beat, length, degree[, accidental]), ...]) (written out) or ("r",).

CALM_MOTIF = [(0.5, 0.5, 0), (1.0, 0.5, 3), (1.5, 0.5, 4), (2.0, 1.0, 5), (3.0, 0.5, 4), (3.5, 0.5, 3)]
CALM = {
    "a": [
        ("m", 4),                                                       # Dm: A D E F~ E D
        ("n", [(0, 1.5, 9), (1.5, 0.5, 8), (2, 0.5, 7), (2.5, 0.5, 6), (3, 1, 4)]),
        ("m", 3),                                                       # C: G C D E~ D C
        ("n", [(0, 2.5, 7), (2.5, 1, 4)]),
        ("m", 7),                                                       # G: D G A B~ A G
        ("n", [(0, 1.5, 12), (1.5, 0.5, 11), (2, 0.5, 10), (2.5, 0.5, 8), (3, 1, 7)]),
        ("m", 8),                                                       # Am: E A B C~ B A
        ("n", [(0, 2.5, 10), (2.5, 1, 8)]),
        ("m", 6),                                                       # F: C F G A~ G F
        ("n", [(0, 1.5, 8), (1.5, 0.5, 7), (2, 1, 6), (3, 1, 3)]),
        ("n", [(0.5, 0.5, 5), (1, 0.5, 7), (1.5, 1.5, 10), (3, 0.5, 9), (3.5, 0.5, 8)]),
        ("n", [(0, 2, 8), (2, 1, 4)]),
    ],
    "b": [   # the answer: from above, dotted, falling to the chord and turning up
        ("n", [(0.5, 0.5, 11), (1, 0.75, 9), (1.75, 0.25, 8), (2, 1, 7), (3, 0.5, 8), (3.5, 0.5, 9)]),
        ("n", [(0, 1.5, 11), (1.5, 0.5, 10), (2, 0.5, 9), (2.5, 0.5, 8), (3, 1, 7)]),
        ("n", [(0.5, 0.5, 10), (1, 0.75, 8), (1.75, 0.25, 7), (2, 1, 6), (3, 0.5, 7), (3.5, 0.5, 8)]),
        ("n", [(0, 1, 9), (1, 0.5, 8), (1.5, 2, 7)]),
        ("n", [(0.5, 0.5, 10), (1, 0.75, 12), (1.75, 0.25, 11), (2, 1, 10), (3, 0.5, 11), (3.5, 0.5, 12)]),
        ("n", [(0, 1.5, 14), (1.5, 0.5, 13), (2, 0.5, 12), (2.5, 0.5, 11), (3, 1, 10)]),
        ("n", [(0.5, 0.5, 11), (1, 0.75, 13), (1.75, 0.25, 12), (2, 1, 11), (3, 0.5, 10), (3.5, 0.5, 8)]),
        ("n", [(0, 1, 10), (1, 0.5, 9), (1.5, 2, 8)]),
        ("n", [(0.5, 0.5, 9), (1, 0.75, 11), (1.75, 0.25, 10), (2, 1, 9), (3, 0.5, 8), (3.5, 0.5, 9)]),
        ("n", [(0, 1.5, 10), (1.5, 0.5, 8), (2, 1, 6), (3, 0.5, 7), (3.5, 0.5, 8)]),
        ("n", [(0, 1, 7), (1, 0.5, 5), (1.5, 0.5, 7), (2, 1.5, 10), (3.5, 0.5, 9)]),
        ("n", [(0, 1.5, 8), (1.5, 0.5, 7), (2, 1, 6, 1)]),              # E D C#
    ],
    "c": [   # high and sparse: the motif's skeleton in long notes, plucked in octaves
        ("n", [(1, 2, 7), (3, 1, 9)]),
        ("n", [(0, 2, 8), (2, 1.5, 4)]),
        ("n", [(1, 2, 10), (3, 1, 8)]),
        ("n", [(0, 3.5, 7)]),
        ("n", [(1, 2, 12), (3, 1, 11)]),
        ("n", [(0, 1, 10), (1, 1, 7), (2, 1.5, 10)]),
        ("n", [(1, 2, 13), (3, 1, 12)]),
        ("n", [(0, 3.5, 10)]),
        ("n", [(1, 1, 11), (2, 1, 13), (3, 1, 11)]),
        ("n", [(0, 2, 10), (2, 1, 8), (3, 1, 6)]),
        ("n", [(1, 1, 5), (2, 2, 7)]),
        ("n", [(0, 3, 8)]),
    ],
}

WILD_MOTIF = [(0.5, 1.0, 0), (1.5, 0.5, -1), (2.0, 2.0, -3)]       # D C A~ on anchor D5
WILD = {
    "a": [
        ("m", 7),
        ("n", [(0, 0.25, 5), (0.25, 0.25, 4), (0.5, 0.5, 3), (1, 1.5, 4), (2.5, 1, 2)]),
        ("n", [(0.5, 1, 6), (1.5, 0.5, 5), (2, 2, 3)]),                 # C: C B G~
        ("n", [(0, 0.25, 4), (0.25, 0.25, 3), (0.5, 0.5, 2), (1, 1, 3), (2, 1.5, 4)]),
        ("n", [(0.5, 1, 7), (1.5, 0.5, 6), (2, 2, 5)]),                 # G: D C B~
        ("n", [(0, 0.25, 6), (0.25, 0.25, 5), (0.5, 0.5, 4), (1, 1.5, 5), (2.5, 1, 3)]),
        ("n", [(0.5, 1, 8), (1.5, 0.5, 7), (2, 2, 6)]),                 # Am: E D C~
        ("n", [(0, 0.25, 7), (0.25, 0.25, 6), (0.5, 0.5, 5), (1, 1, 6), (2, 1.5, 3)]),
        ("n", [(0.5, 1, 4), (1.5, 0.5, 6), (2, 1.5, 9), (3.5, 0.5, 8)]),
        ("n", [(0, 1, 8), (1, 0.5, 7), (1.5, 0.5, 6), (2, 2, 3)]),
        ("n", [(0.5, 0.5, 5), (1, 1, 7), (2, 1, 10), (3, 0.5, 9), (3.5, 0.5, 8)]),
        ("n", [(0, 1.5, 8), (1.5, 0.5, 6, 1), (2, 1, 4)]),              # E C# A
    ],
    "b": [   # lower and turning: the motif inverted, answered by scale turns
        ("n", [(0.5, 0.5, 4), (1, 1, 7), (2, 1, 9), (3, 0.5, 8), (3.5, 0.5, 7)]),
        ("n", [(0, 1, 6), (1, 1, 4), (2, 0.5, 5), (2.5, 0.5, 4), (3, 0.5, 3), (3.5, 0.5, 4)]),
        ("n", [(0.5, 0.5, 3), (1, 1, 6), (2, 1, 8), (3, 0.5, 7), (3.5, 0.5, 6)]),
        ("n", [(0, 1, 5), (1, 2.5, 4)]),
        ("n", [(0.5, 0.5, 5), (1, 1, 7), (2, 1, 10), (3, 0.5, 9), (3.5, 0.5, 8)]),
        ("n", [(0, 1, 7), (1, 1, 5), (2, 0.5, 6), (2.5, 0.5, 5), (3, 0.5, 4), (3.5, 0.5, 3)]),
        ("n", [(0.5, 1, 4), (1.5, 0.5, 5), (2, 2, 6)]),                 # Am: A B C~ (the motif upside down)
        ("n", [(0, 1, 7), (1, 2.5, 8)]),
        ("n", [(0.5, 0.5, 2), (1, 1, 4), (2, 1, 6), (3, 0.5, 5), (3.5, 0.5, 4)]),
        ("n", [(0, 1.5, 3), (1.5, 0.5, 1), (2, 1, 3), (3, 1, 6)]),
        ("n", [(0, 1, 5), (1, 1, 7), (2, 2, 3)]),
        ("n", [(0, 1, 4), (1, 1, 1), (2, 1, 4)]),
    ],
    "c": [   # long breaths high above: the motif augmented
        ("n", [(1, 2, 9), (3, 1, 8)]),
        ("n", [(0, 3, 7)]),
        ("n", [(1, 2, 8), (3, 1, 7)]),
        ("n", [(0, 3.5, 4)]),
        ("n", [(1, 2, 10), (3, 1, 9)]),
        ("n", [(0, 3, 7)]),
        ("n", [(1, 2, 11), (3, 1, 10)]),
        ("n", [(0, 3.5, 8)]),
        ("n", [(1, 1.5, 9), (2.5, 1.5, 11)]),
        ("n", [(0, 2, 10), (2, 2, 8)]),
        ("n", [(0, 1.5, 7), (1.5, 0.5, 5), (2, 2, 7)]),
        ("n", [(0, 1.5, 8), (1.5, 1.5, 4)]),
    ],
}

ANCIENT_MOTIF = [(0.5, 1.5, 0), (2.0, 2.0, 4)]                         # D~ A~ (a rising fifth)
ANCIENT = {
    "a": [
        ("m", 0),                                                       # D4 A4
        ("n", [(0, 1, 3), (1, 1, 2), (2, 2, 1)]),                       # G F E
        ("m", -1),                                                      # C: C4 G4
        ("n", [(0, 1, 2), (1, 1, 1), (2, 1.5, 0)]),                     # F E D
        ("m", 3),                                                       # G: G4 D5
        ("n", [(0, 1, 6), (1, 1, 5), (2, 2, 4)]),                       # C B A
        ("m", 4),                                                       # Am: A4 E5
        ("n", [(0, 1, 7), (1, 1, 6), (2, 1.5, 3)]),                     # D C G
        ("m", 2),                                                       # F: F4 C5
        ("n", [(0, 1, 8), (1, 1, 7), (2, 2, 6)]),                       # E D C
        ("n", [(0.5, 1.5, 5), (2, 1, 7), (3, 1, 3)]),                   # B D G
        ("n", [(0, 1.5, 4), (1.5, 1.5, 1)]),                            # A E
    ],
    "b": [   # an octave of weight below: the fifth answered by the fourth
        ("n", [(0.5, 1.5, -3), (2, 1, 0), (3, 1, 2)]),                  # A3 D4 F4
        ("n", [(0, 1.5, 1), (1.5, 0.5, 0), (2, 2, -3)]),                # E D A3
        ("n", [(0.5, 1.5, -4), (2, 1, -1), (3, 1, 1)]),                 # G3 C4 E4
        ("n", [(0, 1, 0), (1, 1, 2), (2, 1.5, 0)]),
        ("n", [(0.5, 1.5, 0), (2, 1, 3), (3, 1, 5)]),                   # D G B
        ("n", [(0, 1.5, 4), (1.5, 0.5, 3), (2, 2, 0)]),
        ("n", [(0.5, 1.5, 1), (2, 1, 4), (3, 1, 6)]),                   # E A C
        ("n", [(0, 1, 5), (1, 1, 4), (2, 1.5, 3)]),
        ("n", [(0.5, 1.5, -1), (2, 1, 2), (3, 1, 4)]),                  # C F A
        ("n", [(0, 2, 3), (2, 2, 1)]),
        ("n", [(0, 1, 0), (1, 1, 3), (2, 2, 5)]),
        ("n", [(0, 3, 4)]),
    ],
    "c": [   # a chorale of long tones high in the horn's voice
        ("n", [(1, 3, 4)]),
        ("n", [(0, 2, 7), (2, 2, 4)]),
        ("n", [(1, 3, 3)]),
        ("n", [(0, 3.5, 4)]),
        ("n", [(1, 3, 5)]),
        ("n", [(0, 2, 7), (2, 2, 5)]),
        ("n", [(1, 3, 6)]),
        ("n", [(0, 3.5, 3)]),
        ("n", [(1, 3, 4)]),
        ("n", [(0, 2, 6), (2, 2, 3)]),
        ("n", [(1, 3, 7)]),
        ("n", [(0, 1.5, 8), (1.5, 1.5, 6, 1)]),                         # E5 C#5
    ],
}

MELODIES = {"calm": (CALM_MOTIF, CALM), "wild": (WILD_MOTIF, WILD), "ancient": (ANCIENT_MOTIF, ANCIENT)}


def melody_notes(set_name: str, variant: str) -> list:
    motif, plans = MELODIES[set_name]
    return M.plan_notes(plans[variant], motif)


def _phrase_vel(base: float, swing: float):
    """A velocity arc over each four-bar segment: rising to the third bar, easing at the cadence,
    a little accent on the bar's first and third beats."""
    def vel(b, d, deg, i):
        pos = (b % SEGMENT_BEATS) / SEGMENT_BEATS
        arc = np.sin(np.pi * min(pos * 1.25, 1.0))
        accent = 0.05 if (b % 4.0) in (0.0, 2.0) else 0.0
        return base + swing * arc + accent + (0.04 if d >= 1.0 else 0.0)
    return vel


def _octave_doubled_lute(rng, f0, dur_s, vel, rate=RATE, **kw):
    """Variant C's texture: each long note plucked with its lower octave, a little after."""
    hi = M.lute(rng, f0, dur_s, vel, rate=rate, **kw)
    lo = M.lute(rng, f0 * 0.5, dur_s, vel * 0.55, rate=rate, bright=1.1)
    lag = M.frames(0.018, rate)
    out = np.zeros(max(hi.shape[0], lo.shape[0] + lag))
    out[:hi.shape[0]] += hi
    out[lag:lag + lo.shape[0]] += lo
    return out


MELODY_STYLE = {
    "calm": {"instrument": M.lute, "kw": {"ring_s": 1.0}, "orn": {"a": 0.12, "b": 0.18, "c": 0.35},
             "orn_style": "grace", "vel": (0.72, 0.16), "rt60": 1.6, "wet": 0.22, "lp": 6500.0},
    "wild": {"instrument": M.flute, "kw": {}, "orn": {"a": 0.25, "b": 0.3, "c": 0.4}, "orn_style": "turn",
             "vel": (0.7, 0.18), "rt60": 2.6, "wet": 0.32, "lp": 5200.0},
    "ancient": {"instrument": M.horn, "kw": {}, "orn": {"a": 0.1, "b": 0.12, "c": 0.15}, "orn_style": "grace",
                "vel": (0.7, 0.2), "rt60": 3.2, "wet": 0.36, "lp": 4200.0},
}


def melody(rng: np.random.Generator, set_name: str, variant: str) -> np.ndarray:
    """One melody variant of a zone set: the plan realised by the phrase writer (seeded
    ornaments, a velocity arc per segment), played on the set's instrument with its room.

    Each four-bar segment is rendered on its own - its notes, its reverb - and faded out over
    its last half beat, so the stem is silent at every segment boundary: the scheduler can
    switch to another variant (or rest) there without cutting a ringing tail or letting in the
    tail of a phrase that did not play."""
    style = MELODY_STYLE[set_name]
    notes = melody_notes(set_name, variant)
    problems = M.check_phrases(notes, SEGMENT_BEATS)
    if problems:
        raise ValueError("%s/%s: %s" % (set_name, variant, "; ".join(problems)))
    notes = M.ornament(notes, rng, prob=style["orn"][variant], style=style["orn_style"])
    bs = M.beat_s(ZONE_BPM)
    loop_s = ZONE_BEATS * bs
    period = M.frames(loop_s)
    seg_n = M.frames(SEGMENT_BEATS * bs)
    out = np.zeros(period)
    instrument = style["instrument"]
    if set_name == "calm" and variant == "c":
        instrument = _octave_doubled_lute
    ir = M.reverb_ir(rng, seconds=min(3.5, style["rt60"] * 1.2), rt60=style["rt60"], damp_hz=3200.0)
    fade_n = M.frames(SEGMENT_FADE_BEATS * bs)
    fade = 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, fade_n))
    vel_fn = _phrase_vel(*style["vel"])
    for seg in range(ZONE_BEATS // SEGMENT_BEATS):
        lo = seg * SEGMENT_BEATS
        part = [(b - lo,) + tuple(rest) for b, *rest in notes if lo <= b < lo + SEGMENT_BEATS]
        buf = np.zeros(seg_n + M.frames(4.0))
        M.render_voice(rng, part, ZONE_BPM, instrument, buf=buf,
                       vel_fn=lambda b, d, deg, i, lo=lo: vel_fn(b + lo, d, deg, i), **style["kw"])
        wet = M.reverb_tail(buf, ir, style["wet"])[:seg_n]
        wet[-fade_n:] *= fade
        out[seg * seg_n:(seg + 1) * seg_n] += wet
    return M.dc_loop(M.circular_band(out, 0.0, style["lp"], 2))


# --------------------------------------------------------------------------- drones


def _pad_layer(rng, buf, spans, bpm, transpose=0, voices=3, detune=7.0, attack=0.9, release=1.4,
               wave="saw", gain=1.0, overlap_beats=0.5):
    bs = M.beat_s(bpm)
    for b, d, notes, _bass in spans:
        for midi in notes:
            sig = M.pad(rng, M.hz(midi + transpose), (d + overlap_beats) * bs, 0.8, voices=voices,
                        detune_cents=detune, attack_s=attack, release_s=release, wave=wave)
            M.place(buf, b * bs, sig, gain)


def _bass_layer(rng, buf, spans, bpm, gain=1.0, octave=0):
    bs = M.beat_s(bpm)
    for b, d, _notes, bass in spans:
        M.place(buf, b * bs, M.sub(rng, M.hz(bass + 12 * octave), (d + 0.3) * bs, 0.9), gain)


def drone_calm(rng: np.random.Generator) -> np.ndarray:
    """The warm pad of the calm set: soft detuned saws on the shared chords, a sine bass, a
    gentle low-pass that opens a little in the dorian lift (bars 5-8), a small room."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 6.0)
    spans = zone_chord_spans()
    _pad_layer(rng, buf, spans, ZONE_BPM, voices=3, detune=8.0, gain=0.55)
    _pad_layer(rng, buf, spans, ZONE_BPM, transpose=12, voices=2, detune=5.0, wave="triangle", gain=0.18)
    _bass_layer(rng, buf, spans, ZONE_BPM, gain=0.55)
    x = M.fold(buf, period)

    def gains(f, t):
        lift = np.clip(np.sin(np.pi * (t - loop_s / 3.0) / (loop_s / 3.0)), 0.0, 1.0)[:, None]
        cut = 900.0 + 600.0 * lift
        return 1.0 / np.sqrt(1.0 + (f[None, :] / cut) ** 4)
    x = M.tile_shape(x, gains)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.5, 2.2, 2500.0), 0.25)
    return M.dc_loop(x)


def drone_wild(rng: np.random.Generator) -> np.ndarray:
    """The dark pad of the wild set: the chords voiced low with their sevenths, a closed
    low-pass, a sub, and wind (band-passed noise whose centre wanders and swells every two
    bars) - the Old Wood breathing."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 7.0)
    spans = []
    for b, d, notes, bass in zone_chord_spans():
        low = tuple(n - 12 for n in notes)
        seventh = (low[0] + 10,) if notes != ASUS_VOICING else ()
        spans.append((b, d, low + seventh, bass))
    _pad_layer(rng, buf, spans, ZONE_BPM, voices=3, detune=11.0, attack=1.6, release=2.0, gain=0.5)
    _bass_layer(rng, buf, zone_chord_spans(), ZONE_BPM, gain=0.6)
    x = M.fold(buf, period)
    x = M.circular_band(x, 30.0, 620.0, 2)
    n = x.shape[0]
    wind = core.pink(n, rng)

    def wind_gains(f, t):
        cycle = 2.0 * 4.0 * M.beat_s(ZONE_BPM)
        swell = 0.35 + 0.65 * (0.5 - 0.5 * np.cos(2.0 * np.pi * t / cycle)) ** 2
        centre = 520.0 * 2.0 ** (0.8 * np.sin(2.0 * np.pi * t / loop_s * 3.0) + 0.3 * np.sin(2.0 * np.pi * t / loop_s * 7.0))
        bw = 0.9
        d = np.log2(np.maximum(f[None, :], 1.0) / centre[:, None]) / bw
        return swell[:, None] * np.exp(-0.5 * d * d)
    wind = M.tile_shape(wind, wind_gains)
    x = x / max(core.rms(x), 1e-9) + 0.55 * wind / max(core.rms(wind), 1e-9)
    x = M.reverb_loop(x, M.reverb_ir(rng, 3.5, 3.0, 1800.0), 0.3)
    return M.dc_loop(x)


def drone_ancient(rng: np.random.Generator) -> np.ndarray:
    """The stone choir of the ancient set: an "oo" choir on open fifths of the chord roots (root,
    fifth, octave), a deep sub, and a low bell toll on bars 1 and 7 - the Barrow and the kings'
    ruins; a long, dark room."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 8.0)
    for b, d, _notes, bass in zone_chord_spans():
        root = bass + 12
        for midi, vowel, g in ((root, "o", 0.55), (root + 7, "u", 0.45), (root + 12, "o", 0.3)):
            sig = M.choir(rng, M.hz(midi), (d + 0.6) * bs, 0.8, vowel=vowel, voices=4, attack_s=1.2,
                          release_s=1.8, detune_cents=10.0, breath=0.04)
            M.place(buf, b * bs, sig, g)
    _bass_layer(rng, buf, zone_chord_spans(), ZONE_BPM, gain=0.35)
    for bar in (0, 6):
        toll = M.bell_tone(rng, M.hz(50 if bar == 0 else 45), 6.0, 0.5, decay_s=5.0)
        M.place(buf, bar * 4 * bs + 0.02, M.circular_band(toll, 0.0, 2200.0, 2), 0.35)
    x = M.fold(buf, period)
    x = M.circular_band(x, 28.0, 3000.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.5, 4.0, 1600.0, predelay_s=0.04), 0.45)
    return M.dc_loop(x)


# --------------------------------------------------------------------------- shared stems


def pulse(rng: np.random.Generator) -> np.ndarray:
    """The danger layer: a frame-drum heartbeat (DUM . . dum DUM . . dum) on D, a ticking
    shaker in sixteenths with its weight on the off-beats, a soft roll closing every fourth
    bar."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 2.0)
    hits = []
    for bar in range(12):
        o = bar * 4.0
        hits += [(o + 0.0, M.frame_drum, 1.0, {"f0": 73.4}), (o + 0.75, M.frame_drum, 0.5, {"f0": 73.4}),
                 (o + 2.0, M.frame_drum, 0.82, {"f0": 73.4}), (o + 2.75, M.frame_drum, 0.45, {"f0": 73.4})]
        if bar % 4 == 3:
            hits += [(o + 3.25, M.frame_drum, 0.3, {"f0": 98.0}), (o + 3.5, M.frame_drum, 0.4, {"f0": 98.0}),
                     (o + 3.75, M.frame_drum, 0.55, {"f0": 110.0})]
        for k in range(16):
            v = 0.32 if k % 4 == 2 else (0.18 if k % 2 == 1 else 0.24)
            hits.append((o + k * 0.25, M.shaker, v, {"length_s": 0.06 if k % 2 else 0.08}))
    M.render_hits(rng, hits, ZONE_BPM, buf)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 1.6, 1.2, 4000.0), 0.18)
    return M.dc_loop(fx.soft_clip(x, 2.2))


def combat_drums(rng: np.random.Generator) -> np.ndarray:
    """The combat layer's drums: taiko on one and three with pickups, toms on the off-beats,
    rim on two and four, a tom fill into every fourth bar, a crash at the top of the loop."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 2.5)
    hits = [(0.0, M.crash, 0.55, {"decay_s": 1.8})]
    for bar in range(12):
        o = bar * 4.0
        hits += [(o + 0.0, M.taiko, 1.0, {}), (o + 1.5, M.taiko, 0.55, {}), (o + 2.0, M.taiko, 0.9, {}),
                 (o + 0.5, M.tom, 0.55, {"f0": 132.0}), (o + 1.0, M.rim, 0.55, {}),
                 (o + 2.5, M.tom, 0.5, {"f0": 118.0}), (o + 3.0, M.rim, 0.6, {})]
        if bar % 4 == 3:
            for k, f0 in enumerate((165.0, 150.0, 132.0, 118.0)):
                hits.append((o + 3.0 + 0.25 * k, M.tom, 0.55 + 0.1 * k, {"f0": f0}))
            hits.append((o + 3.75, M.taiko, 0.7, {}))
        else:
            hits += [(o + 3.5, M.taiko, 0.5, {}), (o + 3.75, M.tom, 0.4, {"f0": 132.0})]
        for k in range(1, 16, 2):
            hits.append((o + k * 0.25, M.shaker, 0.12, {"length_s": 0.05}))
    M.render_hits(rng, hits, ZONE_BPM, buf)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.0, 1.5, 3500.0), 0.2)
    return M.dc_loop(fx.soft_clip(x, 3.2), hz_=28.0)


BRASS_PATTERN = [(0.0, 0.62, 1.0), (0.75, 0.18, 0.6), (1.0, 0.4, 0.78), (1.5, 0.4, 0.72), (2.0, 0.62, 0.95),
                 (2.75, 0.18, 0.6), (3.0, 0.85, 0.85)]


def combat_brass(rng: np.random.Generator) -> np.ndarray:
    """The combat layer's low brass: an ostinato on each bar's root and fifth (DAH-da DAH DAH
    DAH-da DAAH), doubled softly an octave down, and a swelling triad on the last two beats of
    every fourth bar."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    bs = M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 2.5)
    for bar, (_name, _deg, voicing, bass) in enumerate(ZONE_CHORDS):
        o = bar * 4.0
        root = bass + 12
        pattern = BRASS_PATTERN if bar % 4 != 3 else BRASS_PATTERN[:4]
        for b, d, v in pattern:
            for midi, g in ((root, 1.0), (root + 7, 0.6), (root - 12, 0.4)):
                sig = M.brass(rng, M.hz(midi), d * bs, v, bright=1.15, attack_s=0.025, release_s=0.12, vib_cents=0.0)
                M.place(buf, (o + b) * bs + rng.uniform(-0.004, 0.004), sig, g)
        if bar % 4 == 3:
            for midi in voicing:
                sig = M.brass(rng, M.hz(midi - 12), 1.9 * bs, 0.95, bright=1.0, attack_s=0.5, release_s=0.15)
                M.place(buf, (o + 2.0) * bs, sig, 0.55)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.2, 1.8, 2800.0), 0.22)
    return M.dc_loop(M.circular_band(x, 0.0, 5000.0, 2))


# The title theme: three horns (the tune, its harmony a third or sixth below, the roots).
TITLE_TUNE = [
    [("A4", 0, 1.5), ("D5", 1.5, 0.5), ("D5", 2, 1), ("E5", 3, 1)],
    [("F5", 0, 2), ("E5", 2, 1), ("D5", 3, 1)],
    [("E5", 0, 1.5), ("C5", 1.5, 0.5), ("G4", 2, 2)],
    [("A4", 0, 3.5)],
    [("B4", 0, 1.5), ("D5", 1.5, 0.5), ("G5", 2, 1.5), ("F5", 3.5, 0.5)],
    [("E5", 0, 1), ("D5", 1, 1), ("B4", 2, 2)],
    [("C5", 0, 1.5), ("E5", 1.5, 0.5), ("A5", 2, 2)],
    [("G5", 0, 1), ("E5", 1, 1), ("C5", 2, 2)],
    [("A5", 0, 1.5), ("G5", 1.5, 0.5), ("F5", 2, 1), ("C5", 3, 1)],
    [("E5", 0, 1.5), ("D5", 1.5, 0.5), ("C5", 2, 1), ("G4", 3, 1)],
    [("B4", 0, 1), ("D5", 1, 1), ("G5", 2, 1), ("F5", 3, 1)],
    [("E5", 0, 2), ("C#5", 2, 1), ("A4", 3, 1)],
]
TITLE_HARMONY = [
    [("F4", 0, 1.5), ("A4", 1.5, 2.5)],
    [("D5", 0, 2), ("C5", 2, 1), ("A4", 3, 1)],
    [("C5", 0, 1.5), ("G4", 1.5, 0.5), ("E4", 2, 2)],
    [("F4", 0, 3.5)],
    [("G4", 0, 1.5), ("B4", 1.5, 0.5), ("D5", 2, 2)],
    [("B4", 0, 2), ("G4", 2, 2)],
    [("A4", 0, 1.5), ("C5", 1.5, 0.5), ("E5", 2, 2)],
    [("E5", 0, 1), ("C5", 1, 1), ("G4", 2, 2)],
    [("F5", 0, 1.5), ("E5", 1.5, 0.5), ("C5", 2, 1), ("A4", 3, 1)],
    [("C5", 0, 1.5), ("B4", 1.5, 0.5), ("G4", 2, 1), ("E4", 3, 1)],
    [("G4", 0, 1), ("B4", 1, 1), ("D5", 2, 2)],
    [("C#5", 0, 2), ("A4", 2, 1), ("E4", 3, 1)],
]
TITLE_BASS = [
    [("D3", 0, 2), ("A3", 2, 2)], [("D3", 0, 4)], [("C3", 0, 2), ("G3", 2, 2)], [("D3", 0, 4)],
    [("G2", 0, 2), ("D3", 2, 2)], [("G2", 0, 4)], [("A2", 0, 2), ("E3", 2, 2)], [("C3", 0, 4)],
    [("F2", 0, 2), ("C3", 2, 2)], [("C3", 0, 4)], [("G2", 0, 2), ("D3", 2, 2)], [("A2", 0, 4)],
]


def _named_notes(bars) -> list:
    out = []
    for i, bar in enumerate(bars):
        for name, b, d in bar:
            out.append((i * 4.0 + b, d, M.name_midi(name)))
    return out


def _play_midi(rng, buf, notes, bpm, instrument, gain, vel=0.85, **kw):
    bs = M.beat_s(bpm)
    for b, d, midi in notes:
        v = vel * (1.0 + rng.uniform(-0.05, 0.05))
        M.place(buf, max(0.0, b * bs + rng.uniform(-0.006, 0.006)), instrument(rng, M.hz(midi), d * bs, v, **kw), gain)


def title_theme(rng: np.random.Generator) -> np.ndarray:
    """The game's theme on a horn choir: the tune opens on the calm motif's rising fourth (A-D),
    lifts through the dorian B and ends on the C#-A that pulls back to D; the harmony horn moves
    in thirds and sixths below, the low horn holds the roots."""
    loop_s = ZONE_BEATS * M.beat_s(ZONE_BPM)
    buf, period = M.loop_buffer(loop_s, 5.0)
    _play_midi(rng, buf, _named_notes(TITLE_TUNE), ZONE_BPM, M.horn, 1.0, vel=0.9)
    _play_midi(rng, buf, _named_notes(TITLE_HARMONY), ZONE_BPM, M.horn, 0.62, vel=0.75)
    _play_midi(rng, buf, _named_notes(TITLE_BASS), ZONE_BPM, M.horn, 0.55, vel=0.7, bright=0.55)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 4.0, 3.4, 2600.0, predelay_s=0.03), 0.38)
    return M.dc_loop(M.circular_band(x, 0.0, 5000.0, 2))


# --------------------------------------------------------------------------- the Ogre King (D aeolian, 104 BPM)

# Per bar: (root MIDI (octave 2), third in semitones).
BOSS_BARS = [(38, 3), (38, 3), (34, 4), (33, 4), (38, 3), (38, 3), (31, 3), (33, 4), (34, 4), (36, 4), (38, 3), (33, 4)]
BOSS_RIFF = [(0, 1.0), (0, 0.6), ("third", 0.8), (0, 0.6), (1, 0.85), (0, 0.6), (-1, 0.8), (0, 0.65)]
KING_CALL = [
    [], [], [], [],
    [("D4", 0, 1.5), ("A3", 1.5, 0.5), ("D4", 2, 1), ("F4", 3, 1)],
    [("E4", 0, 1), ("D4", 1, 1), ("C#4", 2, 1), ("A3", 3, 1)],
    [("Bb3", 0, 1.5), ("G3", 1.5, 0.5), ("Bb3", 2, 1), ("D4", 3, 1)],
    [("C#4", 0, 2), ("E4", 2, 1), ("A3", 3, 1)],
    [("D4", 0, 1.5), ("F4", 1.5, 0.5), ("Bb4", 2, 2)],
    [("A4", 0, 1), ("G4", 1, 1), ("E4", 2, 2)],
    [("F4", 0, 1), ("E4", 1, 1), ("D4", 2, 2)],
    [("C#4", 0, 1), ("E4", 1, 1), ("A4", 2, 2)],
]


def boss_theme(rng: np.random.Generator) -> np.ndarray:
    """The Ogre King's brass: a chromatic eighth-note ostinato on each bar's root (root, root,
    third, root, the semitone above, root, the leading tone, root), doubled an octave up, swelling
    pedals under bars 1-4 and from bar 5 the King's call on horns."""
    loop_s = BOSS_BEATS * M.beat_s(BOSS_BPM)
    bs = M.beat_s(BOSS_BPM)
    buf, period = M.loop_buffer(loop_s, 2.5)
    for bar, (root, third) in enumerate(BOSS_BARS):
        o = bar * 4.0
        for k, (step, v) in enumerate(BOSS_RIFF):
            semis = third if step == "third" else step
            for octave, g in ((12, 1.0), (24, 0.45)):
                sig = M.brass(rng, M.hz(root + octave + semis), 0.42 * bs, v, bright=1.2, attack_s=0.02,
                              release_s=0.08, vib_cents=0.0, scoop=0.01)
                M.place(buf, (o + 0.5 * k) * bs + rng.uniform(-0.003, 0.003), sig, g)
    for start, length, midi in ((0.0, 8.0, 50), (8.0, 4.0, 46), (12.0, 4.0, 45)):
        sig = M.brass(rng, M.hz(midi), length * bs, 0.8, bright=0.8, attack_s=1.2, release_s=0.3)
        M.place(buf, start * bs, sig, 0.5)
    _play_midi(rng, buf, _named_notes(KING_CALL), BOSS_BPM, M.horn, 0.9, vel=0.95, bright=0.95)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.6, 2.0, 2600.0), 0.24)
    return M.dc_loop(M.circular_band(x, 0.0, 5500.0, 2), hz_=28.0)


def boss_drums(rng: np.random.Generator) -> np.ndarray:
    """Double-time taiko for the King: booms on the beat and off-sixteenths, toms filling the
    gaps, rim on two and four, crashes at bars 1 and 9, a sixteenth roll through bar 12."""
    loop_s = BOSS_BEATS * M.beat_s(BOSS_BPM)
    buf, period = M.loop_buffer(loop_s, 2.5)
    hits = [(0.0, M.crash, 0.7, {"decay_s": 2.0}), (32.0, M.crash, 0.6, {"decay_s": 1.8})]
    for bar in range(12):
        o = bar * 4.0
        if bar == 11:
            for k in range(16):
                hits.append((o + 0.25 * k, M.tom if k % 4 else M.taiko, 0.45 + 0.035 * k,
                             {"f0": 150.0 - 2.0 * k} if k % 4 else {"f0": 52.0}))
            continue
        hits += [(o + 0.0, M.taiko, 1.0, {"f0": 52.0}), (o + 0.75, M.taiko, 0.55, {"f0": 52.0}),
                 (o + 1.5, M.taiko, 0.7, {"f0": 56.0}), (o + 2.0, M.taiko, 0.95, {"f0": 52.0}),
                 (o + 2.75, M.taiko, 0.55, {"f0": 52.0}), (o + 3.5, M.taiko, 0.7, {"f0": 56.0}),
                 (o + 1.0, M.rim, 0.65, {}), (o + 3.0, M.rim, 0.7, {})]
        for k in (1, 3, 5, 9, 11, 13):
            hits.append((o + 0.25 * k, M.tom, 0.32, {"f0": 140.0}))
    M.render_hits(rng, hits, BOSS_BPM, buf)
    x = M.fold(buf, period)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.0, 1.6, 3200.0), 0.2)
    return M.dc_loop(fx.soft_clip(x, 3.2), hz_=28.0)


def boss_frenzy(rng: np.random.Generator) -> np.ndarray:
    """Phase 2 (the King below half health): a high string tremolo on each bar's chord with a
    semitone grinding above its root, off-beat stabs, and a scream rising through bars 11-12."""
    loop_s = BOSS_BEATS * M.beat_s(BOSS_BPM)
    bs = M.beat_s(BOSS_BPM)
    buf, period = M.loop_buffer(loop_s, 2.0)
    trem = BOSS_BPM / 60.0 * 8.0
    for bar, (root, third) in enumerate(BOSS_BARS):
        o = bar * 4.0
        top = root + 36
        for midi, g in ((top, 0.6), (top + 1, 0.4), (top + third, 0.45), (top + 7, 0.5)):
            sig = M.strings(rng, M.hz(midi), 4.0 * bs, 0.8, voices=3, tremolo_hz=trem, attack_s=0.08, release_s=0.15)
            M.place(buf, o * bs, sig, g)
        for b in (0.5, 2.5):
            sig = M.strings(rng, M.hz(root + 24), 0.22 * bs, 1.0, voices=4, attack_s=0.008, release_s=0.08)
            M.place(buf, (o + b) * bs, sig, 0.5)
    n = M.frames(8.0 * bs)
    t = fx.t_axis(n)
    gliss = M.hz(74) * 2.0 ** (t / (8.0 * bs) * 1.0)
    scream = core.saw(gliss, n) * np.clip(t / (6.0 * bs), 0.0, 1.0) ** 2 * M.env_note(n, RATE, 0.05, 7.6 * bs, 0.3 * bs)
    M.place(buf, 40.0 * bs, scream, 0.35)
    x = M.fold(buf, period)
    x = M.circular_band(x, 180.0, 4800.0, 2)
    x = M.reverb_loop(x, M.reverb_ir(rng, 2.0, 1.6, 3000.0), 0.22)
    return M.dc_loop(x)


# --------------------------------------------------------------------------- the build list


# The build's pre-encoding budget estimate per cue (build_audio.estimate_bytes: KB of Ogg per second
# besides the 3.7 KB of headers), calibrated on the encoded files (rounded up to 0.01): with the
# measured import factor x1.11 the estimate stays within a few KB of the imported size.
EST_KBPS = {
    'boss_drums': 4.07, 'boss_frenzy': 4.37, 'boss_theme': 4.08, 'combat_brass': 4.09,
    'combat_drums': 4.26, 'drone_ancient': 2.42, 'drone_calm': 3.07, 'drone_wild': 2.91,
    'melody_ancient_a': 2.78, 'melody_ancient_b': 2.97, 'melody_ancient_c': 2.53,
    'melody_calm_a': 2.46, 'melody_calm_b': 2.44, 'melody_calm_c': 2.22, 'melody_wild_a': 3.52,
    'melody_wild_b': 3.53, 'melody_wild_c': 3.42, 'pulse': 4.36, 'title_theme': 3.87,
}


def _loop(name, func, seed, params, frame=ZONE_FRAME, bpm=ZONE_BPM, beats=ZONE_BEATS, quality=0, lufs=-20.0,
          est=3.2):
    """A music loop of the build: Ogg at 22.05 kHz mono, balanced by its K-weighted loudness
    (core.loudness_lufs) with its peak at most -3 dBFS."""
    return {"name": name, "path": _P + name + ".ogg", "seed": seed, "func": func, "params": params,
            "kind": "loop", "bpm": bpm, "beats": beats, "beats_per_bar": 4, "frame": frame, "quality": quality,
            "rate": RATE, "norm": {"lufs": lufs, "max_peak_db": -3.0}, "est_kbps": EST_KBPS.get(name, est)}


# Loudness of each stem (LUFS) before the layer volumes of its set and the Music bus: the explore
# mix (drone 0, melody -2) is about -19, danger about -20.5, combat about -15, the King about -13.5
# (and -13 in phase 2): see docs/systems/P23.md "The mix".
DRONE_LUFS = -24.0
MELODY_LUFS = -19.0
CUES = [
    _loop("drone_calm", drone_calm, 230001, {}, lufs=DRONE_LUFS),
    _loop("drone_wild", drone_wild, 230002, {}, lufs=DRONE_LUFS),
    _loop("drone_ancient", drone_ancient, 230003, {}, lufs=DRONE_LUFS),
]
for _i, (_set, _v) in enumerate([(s, v) for s in ("calm", "wild", "ancient") for v in ("a", "b", "c")]):
    CUES.append(_loop("melody_%s_%s" % (_set, _v), melody, 230010 + _i, {"set_name": _set, "variant": _v},
                      lufs=MELODY_LUFS, est=3.0))
CUES += [
    _loop("pulse", pulse, 230020, {}, quality=1, lufs=-21.0, est=4.0),
    _loop("combat_drums", combat_drums, 230021, {}, quality=1, lufs=-17.0, est=4.0),
    _loop("combat_brass", combat_brass, 230022, {}, quality=1, lufs=-18.0, est=4.0),
    _loop("title_theme", title_theme, 230023, {}, quality=1, lufs=-18.0, est=4.0),
    _loop("boss_drums", boss_drums, 230030, {}, frame=BOSS_FRAME, bpm=BOSS_BPM, beats=BOSS_BEATS, quality=1,
          lufs=-16.0, est=4.0),
    _loop("boss_theme", boss_theme, 230031, {}, frame=BOSS_FRAME, bpm=BOSS_BPM, beats=BOSS_BEATS, quality=1,
          lufs=-17.0, est=4.0),
    _loop("boss_frenzy", boss_frenzy, 230032, {}, frame=BOSS_FRAME, bpm=BOSS_BPM, beats=BOSS_BEATS, quality=1,
          lufs=-19.0, est=4.0),
]
