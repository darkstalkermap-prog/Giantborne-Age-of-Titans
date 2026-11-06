"""The score's stingers (P23; plan M6-M9 sections 4.2 and 4.3): short arranged phrases on the score's
instruments, one-shot Ogg streams on the Music bus that duck the stems while they play.

    growth          6 s  a timpani roll and brass climbing D-A-D to an F# - the giant's change -
                         and a choir opening on D major
    level_up        3 s  a quick lute arpeggio up D major, bells and a warm horn chord
    victory         6 s  a brass fanfare (D-D-D-A, then the high D) over timpani, the choir in D major
    quest           2.5 s a horn call on the calm motif's rising fourth, A-D-E, over a soft Dsus2
    quest_complete  4 s  plucked G - A - D (IV-V-I in D major) and the horns holding the D chord
    death           4 s  a low bell and a choir falling D-C-Bb-A into the dark
    prologue_end    8 s  the title theme's opening on the horn choir, turned to D major (F#), timpani
    combat_calm     5 s  two bars at 96 BPM: a drum break, lute strums and low brass hits
    combat_wild     5 s  a flute run up the dorian scale to a trill, a tom roll, a low horn
    combat_ancient  5 s  a horn blast on open fifths, taiko and a choir swelling on D minor
    boss_ogre_king  2.3 s one bar at 104 BPM: a taiko and crash, a low brass cluster swelling on
                         D-Eb-A, a sixteenth tom roll into the King's loop

Combat intros and the boss intro are in the tempo of the music they introduce (they start on a
beat). Mono, 22.05 kHz, libvorbis q2.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx, music as M

FAMILY = "stingers"
RATE = core.DEFAULT_RATE
_P = "res://assets/audio/music/stinger_"


def _buf(length_s: float, tail_s: float = 3.0) -> np.ndarray:
    return np.zeros(M.frames(length_s + tail_s))


def _note(rng, buf, at_s, instrument, name_or_midi, dur_s, vel=0.85, gain=1.0, **kw):
    midi = M.name_midi(name_or_midi) if isinstance(name_or_midi, str) else name_or_midi
    M.place(buf, at_s, instrument(rng, M.hz(midi), dur_s, vel, **kw), gain)


def _hit(rng, buf, at_s, fn, vel=1.0, gain=1.0, **kw):
    M.place(buf, at_s, fn(rng, vel, **kw), gain)


def _finish(rng, buf, length_s, rt60=2.6, wet=0.3, fade_s=0.6, lp=6000.0, drive=1.0) -> np.ndarray:
    """The room, then the stinger cut to its length with a smooth fade over its last fade_s; with
    drive > 1 a gentle tanh saturation takes the drums' transients down so the phrase is heard
    at its loudness without passing its peak."""
    x = M.reverb_tail(buf, M.reverb_ir(rng, min(3.5, rt60 * 1.15), rt60, 2800.0), wet)
    x = fx.lowpass(x, lp, 2.0)
    if drive > 1.0:
        x = fx.soft_clip(x, drive)
    n = M.frames(length_s)
    x = x[:n] if x.shape[0] >= n else np.concatenate([x, np.zeros(n - x.shape[0])])
    f = M.frames(fade_s)
    x[-f:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, f))
    return M.finish_oneshot(x, floor_db=-70.0, fade_s=0.02)


def growth(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(6.0)
    times = np.cumsum(np.linspace(0.24, 0.07, 18))
    for i, t in enumerate(times[times < 2.75]):
        _hit(rng, buf, float(t) - times[0], M.timpani, 0.25 + 0.6 * i / 17.0, f0=73.4)
    for name, at, dur in (("D3", 0.0, 1.0), ("A3", 0.9, 1.0), ("D4", 1.8, 1.0), ("F#4", 2.6, 2.6)):
        _note(rng, buf, at, M.brass, name, dur, 0.75 if name != "F#4" else 0.95, 0.8, bright=1.0, attack_s=0.25)
    for name in ("D4", "F#4", "A4", "D5"):
        _note(rng, buf, 2.5, M.choir, name, 2.6, 0.8, 0.55, vowel="a", attack_s=0.4, release_s=1.2)
    _note(rng, buf, 2.75, M.horn, "A4", 2.4, 0.85, 0.6)
    _hit(rng, buf, 2.78, M.taiko, 1.0, 0.9)
    _hit(rng, buf, 2.78, M.crash, 0.6, 0.35, decay_s=2.5)
    _note(rng, buf, 0.0, M.sub, "D2", 4.5, 0.9, 0.6, attack_s=2.5, release_s=1.0)
    return _finish(rng, buf, 6.0, rt60=3.0, wet=0.32, fade_s=1.2, drive=1.8)


def level_up(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(3.0)
    for i, name in enumerate(("D5", "F#5", "A5", "D6")):
        _note(rng, buf, 0.11 * i, M.lute, name, 0.9, 0.8 + 0.05 * i, 1.0, ring_s=1.3)
    for name in ("D6", "A6"):
        _note(rng, buf, 0.33, M.bell_tone, name, 1.5, 0.5, 0.45, decay_s=1.8)
    for name in ("D4", "F#4", "A4"):
        _note(rng, buf, 0.3, M.horn, name, 1.6, 0.7, 0.45, attack_s=0.35)
    return _finish(rng, buf, 3.0, rt60=2.2, wet=0.28, fade_s=0.7)


def victory(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(6.0)
    for at, name, dur, vel in ((0.0, "D4", 0.2, 0.8), (0.27, "D4", 0.2, 0.75), (0.54, "D4", 0.2, 0.8),
                               (0.8, "A4", 0.5, 0.9), (1.4, "D5", 2.6, 1.0)):
        _note(rng, buf, at, M.brass, name, dur, vel, 1.0, bright=1.1, attack_s=0.03)
    for at, name, dur in ((0.8, "F#4", 0.5), (1.4, "A4", 2.6), (1.4, "F#4", 2.6), (1.4, "D4", 2.6)):
        _note(rng, buf, at, M.horn, name, dur, 0.75, 0.55)
    for name in ("D4", "F#4", "A4", "D5"):
        _note(rng, buf, 1.4, M.choir, name, 3.0, 0.8, 0.4, vowel="a", attack_s=0.5)
    for at, vel in ((0.0, 0.8), (0.8, 0.7)):
        _hit(rng, buf, at, M.timpani, vel, 0.9, f0=73.4)
    for k in range(8):
        _hit(rng, buf, 1.4 + 0.075 * k, M.timpani, 0.5 + 0.06 * k, 0.7, f0=73.4)
    _hit(rng, buf, 1.4, M.crash, 0.7, 0.4, decay_s=3.0)
    _hit(rng, buf, 1.4, M.taiko, 0.9, 0.7)
    return _finish(rng, buf, 6.0, rt60=3.2, wet=0.32, fade_s=1.3)


def quest(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(2.5)
    for at, name, dur, vel in ((0.0, "A4", 0.33, 0.75), (0.35, "D5", 0.48, 0.85), (0.85, "E5", 1.15, 0.9)):
        _note(rng, buf, at, M.horn, name, dur, vel, 1.0)
    for name in ("D4", "E4", "A4"):
        _note(rng, buf, 0.2, M.pad, name, 1.7, 0.6, 0.18, attack_s=0.5, release_s=0.6, wave="triangle")
    _note(rng, buf, 0.86, M.bell_tone, "E6", 1.2, 0.35, 0.3, decay_s=1.4)
    return _finish(rng, buf, 2.5, rt60=2.4, wet=0.3, fade_s=0.6)


def quest_complete(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(4.0)
    chords = ((0.0, ("G3", "B3", "D4", "G4")), (0.45, ("A3", "C#4", "E4", "A4")), (0.9, ("D4", "F#4", "A4", "D5")))
    for at, names in chords:
        for k, name in enumerate(names):
            _note(rng, buf, at + 0.018 * k, M.lute, name, 0.9 if at < 0.9 else 2.0, 0.85, 0.8, ring_s=1.5)
    for name in ("D4", "F#4", "A4"):
        _note(rng, buf, 0.9, M.horn, name, 2.2, 0.8, 0.5)
    _note(rng, buf, 0.92, M.bell_tone, "D6", 2.0, 0.4, 0.3, decay_s=2.0)
    _hit(rng, buf, 0.9, M.timpani, 0.75, 0.7, f0=73.4)
    return _finish(rng, buf, 4.0, rt60=2.6, wet=0.3, fade_s=1.0)


def death(rng: np.random.Generator) -> np.ndarray:
    buf = _buf(4.0)
    _note(rng, buf, 0.0, M.bell_tone, "D3", 4.0, 0.7, 0.6, decay_s=4.0)
    for at, name, dur in ((0.0, "D4", 0.9), (0.8, "C4", 0.9), (1.6, "Bb3", 0.9), (2.4, "A3", 1.3)):
        _note(rng, buf, at, M.choir, name, dur, 0.75, 0.8, vowel="u", attack_s=0.25, release_s=0.6)
    _note(rng, buf, 0.0, M.choir, "D3", 3.2, 0.6, 0.45, vowel="o", attack_s=0.4, release_s=0.8)
    _note(rng, buf, 0.0, M.sub, "D2", 3.0, 0.8, 0.5, attack_s=0.1, release_s=1.0)
    return _finish(rng, buf, 4.0, rt60=3.5, wet=0.38, fade_s=1.2, lp=4000.0, drive=1.5)


def prologue_end(rng: np.random.Generator) -> np.ndarray:
    bs = M.beat_s(96.0)
    buf = _buf(8.0)
    tune = (("A4", 0, 1.5), ("D5", 1.5, 0.5), ("D5", 2, 1), ("E5", 3, 1), ("F#5", 4, 2), ("E5", 6, 1), ("D5", 7, 4.5))
    harmony = (("F4", 0, 1.5), ("A4", 1.5, 2.5), ("D5", 4, 2), ("C#5", 6, 1), ("A4", 7, 4.5))
    bass = (("D3", 0, 2), ("A3", 2, 2), ("D3", 4, 2), ("A2", 6, 1), ("D3", 7, 4.5))
    for notes, g, v in ((tune, 1.0, 0.9), (harmony, 0.6, 0.75), (bass, 0.55, 0.7)):
        for name, b, d in notes:
            _note(rng, buf, b * bs, M.horn, name, d * bs, v, g)
    for name in ("D4", "F#4", "A4", "D5"):
        _note(rng, buf, 7 * bs, M.choir, name, 4.5 * bs, 0.75, 0.4, vowel="a", attack_s=0.6)
    for k in range(10):
        _hit(rng, buf, 3.0 * bs + 0.1 * k, M.timpani, 0.3 + 0.05 * k, 0.6, f0=73.4)
    _hit(rng, buf, 4 * bs, M.timpani, 0.85, 0.8, f0=73.4)
    _hit(rng, buf, 7 * bs, M.timpani, 0.9, 0.8, f0=73.4)
    _hit(rng, buf, 7 * bs, M.crash, 0.45, 0.3, decay_s=3.0)
    return _finish(rng, buf, 8.0, rt60=3.6, wet=0.36, fade_s=1.6, drive=1.4)


def combat_calm(rng: np.random.Generator) -> np.ndarray:
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    hits = [(0, M.taiko, 1.0, {}), (0.5, M.tom, 0.6, {"f0": 132.0}), (1.0, M.taiko, 0.8, {}),
            (1.5, M.tom, 0.55, {"f0": 150.0}), (1.75, M.tom, 0.6, {"f0": 140.0}), (2.0, M.taiko, 0.9, {}),
            (3.0, M.rim, 0.7, {}), (3.5, M.taiko, 0.7, {}), (4.0, M.taiko, 1.0, {}), (4.0, M.crash, 0.6, {"decay_s": 2.0})]
    for k in range(8):
        hits.append((6.0 + 0.25 * k, M.tom, 0.5 + 0.06 * k, {"f0": 170.0 - 7.0 * k}))
    for b, fn, v, kw in hits:
        _hit(rng, buf, b * bs, fn, v, 0.9, **kw)
    for at in (0.0, 2.0):
        for k, name in enumerate(("D3", "A3", "D4", "F4", "A4")):
            _note(rng, buf, at * bs + 0.015 * k, M.lute, name, 1.2, 0.85, 0.5, ring_s=1.2)
    for b, d in ((4.0, 0.7), (6.0, 0.2), (6.5, 0.2), (7.0, 0.2), (7.5, 0.35)):
        for name, g in (("D3", 1.0), ("A3", 0.6)):
            _note(rng, buf, b * bs, M.brass, name, d * bs, 0.9, 0.55 * g, bright=1.2, attack_s=0.02)
    return _finish(rng, buf, 5.0, rt60=1.8, wet=0.22, fade_s=0.45, drive=2.6)


def combat_wild(rng: np.random.Generator) -> np.ndarray:
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    run = ("D4", "E4", "F4", "G4", "A4", "B4", "C5", "D5")
    for k, name in enumerate(run):
        _note(rng, buf, 0.25 * k * bs, M.flute, name, 0.24 * bs, 0.7 + 0.03 * k, 0.9)
    for k in range(12):
        _note(rng, buf, (2.0 + 0.125 * k) * bs, M.flute, "A5" if k % 2 == 0 else "B5", 0.12 * bs, 0.85, 0.8)
    _note(rng, buf, 3.5 * bs, M.flute, "A5", 0.45 * bs, 0.9, 0.8)
    n = M.frames(2.2)
    wind = fx.noise(n, rng, 400.0, 3000.0) * fx.env_points([(0.0, 0.0), (1.6, 0.5), (2.2, 0.0)], n)
    M.place(buf, 0.0, wind, 0.25)
    for k in range(16):
        _hit(rng, buf, (4.0 + 0.25 * k) * bs, M.tom, 0.35 + 0.035 * k, 0.85, f0=150.0 - 3.0 * (k % 4))
    _note(rng, buf, 4.0 * bs, M.horn, "D3", 1.6 * bs, 0.95, 0.8)
    _hit(rng, buf, 4.0 * bs, M.taiko, 1.0, 0.9)
    _hit(rng, buf, 6.0 * bs, M.taiko, 0.85, 0.8)
    _hit(rng, buf, 7.0 * bs, M.taiko, 0.9, 0.8)
    return _finish(rng, buf, 5.0, rt60=2.4, wet=0.26, fade_s=0.45, drive=1.8)


def combat_ancient(rng: np.random.Generator) -> np.ndarray:
    bs = M.beat_s(96.0)
    buf = _buf(5.0)
    for name, g in (("D3", 1.0), ("A3", 0.8), ("D4", 0.6)):
        _note(rng, buf, 0.0, M.brass, name, 1.6 * bs, 1.0, g, bright=1.25, attack_s=0.04)
    for name in ("D4", "F4", "A4"):
        _note(rng, buf, 1.0 * bs, M.choir, name, 5.0 * bs, 0.8, 0.5, vowel="a", attack_s=0.9)
    for b, v in ((0.0, 1.0), (2.0, 0.8), (4.0, 1.0), (6.0, 0.7), (6.5, 0.75), (7.0, 0.85), (7.5, 0.95)):
        _hit(rng, buf, b * bs, M.taiko, v, 0.9)
    _hit(rng, buf, 4.0 * bs, M.crash, 0.55, 0.4, decay_s=2.2)
    _note(rng, buf, 4.0 * bs, M.bell_tone, "D3", 2.5, 0.6, 0.4, decay_s=3.0)
    _note(rng, buf, 4.0 * bs, M.horn, "A3", 2.0 * bs, 0.85, 0.6)
    return _finish(rng, buf, 5.0, rt60=3.0, wet=0.3, fade_s=0.45, drive=1.8)


BOSS_INTRO_S = 4.0 * M.beat_s(104.0)


def boss_ogre_king(rng: np.random.Generator) -> np.ndarray:
    bs = M.beat_s(104.0)
    buf = _buf(BOSS_INTRO_S)
    _hit(rng, buf, 0.0, M.taiko, 1.0, 1.0, f0=50.0)
    _hit(rng, buf, 0.0, M.crash, 0.8, 0.5, decay_s=2.0)
    for name, g in (("D2", 1.0), ("Eb2", 0.7), ("A2", 0.6), ("D3", 0.5)):
        _note(rng, buf, 0.0, M.brass, name, 3.7 * bs, 1.0, g, bright=1.3, attack_s=0.03, vib_cents=0.0)
    for k in range(8):
        _hit(rng, buf, (2.0 + 0.25 * k) * bs, M.tom, 0.45 + 0.07 * k, 0.9, f0=140.0 - 4.0 * k)
    n = M.frames(1.5)
    t = fx.t_axis(n)
    gliss = core.saw(M.hz(62) * 2.0 ** (t / 1.5 * 1.0), n) * np.clip(t / 1.2, 0.0, 1.0) ** 2
    M.place(buf, 0.8, gliss * M.env_note(n, RATE, 0.05, 1.35, 0.15), 0.25)
    return _finish(rng, buf, BOSS_INTRO_S + 0.12, rt60=1.6, wet=0.18, fade_s=0.25)


def _stinger(name, func, seed, seconds, lufs=-16.0):
    return {"name": name, "path": _P + name + ".ogg", "seed": seed, "func": func, "params": {},
            "kind": "oneshot", "quality": 2, "rate": RATE, "norm": {"lufs": lufs, "max_peak_db": -3.0},
            "est_kbps": 4.6, "seconds_target": seconds}


CUES = [
    _stinger("growth", growth, 231001, 6.0),
    _stinger("level_up", level_up, 231002, 3.0),
    _stinger("victory", victory, 231003, 6.0),
    _stinger("quest", quest, 231004, 2.5, lufs=-17.0),
    _stinger("quest_complete", quest_complete, 231005, 4.0),
    _stinger("death", death, 231006, 4.0),
    _stinger("prologue_end", prologue_end, 231007, 8.0),
    _stinger("combat_calm", combat_calm, 231011, 5.0),
    _stinger("combat_wild", combat_wild, 231012, 5.0),
    _stinger("combat_ancient", combat_ancient, 231013, 5.0),
    _stinger("boss_ogre_king", boss_ogre_king, 231021, BOSS_INTRO_S),
]
