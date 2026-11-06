"""The Old Kingdom's sound effects (P28; plan M6-M9 section 4.1's M7-M9 rows, section 4.2's world
column, section 4.4): the giant's footfalls at stages 4-6 and wading, hooves, the voices of the new
creatures and peoples, the formation wall and the incoming whistle, the gates' answers, water,
trampling, bells and horns, formations, siege engines, the new abilities' own layers and the travel
cue. bank_world_*.json name them (many cues there alias these files, or P21's, at another pitch).

* steps (family C): the giant at stages 4-6 on soft, hard and wet ground (two soft variants, one
  each for the others), their cruise steps (no debris tail), and wading at stages 3-6 (a low slosh
  instead of the ground layer); a heavy body wading and on wet ground; hooves (two strikes, front and
  back, with the ground's surface); a paw on wet ground. Synth/instruments.py's giant_step (P21
  already sized stages 4-6 for it: lower, longer thumps and a bigger debris tail), shortened to keep
  the registered seconds inside the budget.
* voices (family E): calls, never words, by source and filter (synth/voices.py): the troll (f0 70-95
  Hz, a 0.68 tract, a growl), the dire wolf (a bigger, rougher wolf), the Troll Matriarch (deeper, a
  screech over the growl), the rival giants (f0 50-68 Hz, a 0.6 tract; a bellow distinct from the
  player's own roar), the horse (whinnies and snorts) and two crowds (a fleeing rout, an engine crew
  abandoning its engine); far versions for the big ones.
* threat (family F): the formation's wall (a low ratcheting rumble under the family's rising sweep:
  one per brace cycle) and the incoming whistle (a rising whistle that swells to the landing, played
  at the landing circle).
* objects (family G): the size gates' answers (water heaving, stone, timber), splashes, a trample,
  the town bell, the war horn of an alarm, stepping through an exit, reading an inscription; the
  formation's brace, its broken horn and the banner's fall; the ballista's and the catapult's
  release; the cavalry's gallop swell; burning and a troll's regrowth.
* abilities (family D): the new abilities' own layers - the earthquake's crack, the shoulder
  charge's rush, a stone ward, the regrowth, a lightning strike - and the ballista bolt's whirr.
* ui (family H): fast travel.

Mono 16-bit WAVs at 22.05 kHz, normalised to -6 dBFS peak (P21's convention; the banks balance
them), each at most 2.0 s. Every sound is original and synthesized here. Seeds 282001-282999.
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx
from synth import instruments as ins
from synth import voices as vo

FAMILY = "world_sfx"
TWO_PI = 2.0 * math.pi


def _norm(x):
    return np.asarray(x) / max(core.peak(x), 1e-9)


def _at(n, rate, at_s, sig):
    out = np.zeros(n)
    core.mix_into(out, fx.frames(at_s, rate), sig)
    return out


# --------------------------------------------------------------------------- C footfalls


def giant(rng, rate, variant, size, surface, cruise=False, seconds=None):
    """The giant's footfall of a size class on a surface (wade: the low slosh), shortened."""
    x = ins.giant_step(rng, size, surface, cruise, rate, seconds)
    x = fx.reflections(x, rng, rate, 5, 0.05, 0.12, 1800.0)
    return fx.finish(x, rate, floor_db=-50.0, max_s=seconds + 0.12 if seconds else 1.98)


def hoof(rng, rate, variant, surface):
    """A horse's hooves: two strikes (front and back) 50-80 ms apart - a hard knock of horn on the
    ground and the surface under it."""
    n = fx.frames(0.26, rate)
    out = np.zeros(n)
    gap = rng.uniform(0.05, 0.08)
    for at, g in ((0.0, 1.0), (gap, rng.uniform(0.6, 0.8))):
        m = n - fx.frames(at, rate)
        thud = ins.thump(m, rate, rng.uniform(150.0, 175.0), rng.uniform(95.0, 115.0), 0.008, 0.022, 0.0005, 0.25)
        f = rng.uniform(950.0, 1350.0)
        knock = fx.modal_ir([f, f * 2.2, f * 3.1], [0.007, 0.004, 0.002], [1.0, 0.5, 0.25], m, rate)
        knock_g = 0.8 if surface == "hard" else (0.25 if surface == "wet" else 0.45)
        surf = ins.step_surface(rng, m, rate, surface, 0.5)
        core.mix_into(out, fx.frames(at, rate), thud + knock_g * _norm(knock) + 0.6 * surf, g)
    return fx.finish(fx.soft_clip(out, 1.4), rate, floor_db=-50.0)


def paw_wet(rng, rate, variant):
    """A wolf's paw pair on wet ground."""
    return fx.finish(ins.paw_step(rng, "wet", rate), rate, floor_db=-50.0)


# --------------------------------------------------------------------------- E voices

BIG = {
    #           f0 base, tract, sub, growl hz, growl, drive
    "troll": (82.0, 0.68, 0.3, 32.0, 0.4, 2.2),
    "matriarch": (68.0, 0.6, 0.45, 29.0, 0.55, 2.6),
    "giant": (60.0, 0.6, 0.3, 34.0, 0.3, 2.2),
}


def big_voice(rng, rate, variant, who, call):
    """A big body's call: the troll's grunts, the Matriarch's bellows with a screech riding them,
    a rival giant's voice (lower and rougher than the player's own)."""
    f, tract, sub, ghz, growl, drive = BIG[who]
    f *= (1.0, 0.94, 1.06)[variant % 3]
    tract *= rng.uniform(0.97, 1.03)
    kw = {"sub": sub, "growl_hz": ghz, "jitter": 0.03, "shimmer": 0.15}
    if call == "alert":
        s = 0.75 if who != "matriarch" else 0.95
        x = vo.call(rng, s, [(0.0, f * 0.85), (0.12, f * 1.18), (s, f * 0.8)], [(0.0, "uh"), (0.12, "a"), (s, "o")],
                    [(0.0, 0.0), (0.05, 1.0), (s * 0.7, 0.8), (s, 0.0)], rate, tract, breath=0.15, growl=growl,
                    drive=drive, **kw)
    elif call == "attack":
        s = 0.5
        x = vo.call(rng, s, [(0.0, f * 0.95), (0.05, f * 1.15), (s, f * 0.8)], [(0.0, "uh"), (s * 0.5, "a"), (s, "uh")],
                    [(0.0, 0.0), (0.02, 1.0), (s * 0.4, 0.75), (s, 0.0)], rate, tract, breath=0.2, growl=growl,
                    drive=drive + 0.3, **kw)
    elif call == "hurt":
        s = 0.42
        x = vo.call(rng, s, [(0.0, f * 1.1), (0.05, f * 1.2), (s, f * 0.72)], [(0.0, "a"), (0.15, "uh"), (s, "u")],
                    [(0.0, 0.0), (0.012, 1.0), (0.15, 0.7), (s, 0.0)], rate, tract, breath=0.22, growl=growl * 0.8,
                    drive=drive, **kw)
    elif call == "stagger":
        s = 0.55
        x = vo.call(rng, s, [(0.0, f * 0.95), (0.15, f), (s, f * 0.7)], [(0.0, "uh"), (0.3, "o"), (s, "u")],
                    [(0.0, 0.0), (0.04, 0.9), (0.3, 0.7), (s, 0.0)], rate, tract,
                    breath_points=[(0.0, 0.25), (s, 0.6)], growl=growl * 0.6, **kw)
    elif call == "death":
        s = 1.2 if who != "matriarch" else 1.45
        x = vo.call(rng, s, [(0.0, f * 1.0), (0.1, f * 1.15), (s * 0.5, f * 0.85), (s, f * 0.5)],
                    [(0.0, "a"), (s * 0.4, "a"), (s * 0.7, "o"), (s, "u")],
                    [(0.0, 0.0), (0.05, 1.0), (s * 0.5, 0.75), (s, 0.0)], rate, tract,
                    breath_points=[(0.0, 0.12), (s * 0.6, 0.3), (s, 0.85)], growl=growl, drive=drive * 0.9, **kw)
        x = fx.valley_echo(x, rng, rate, 0.34, 0.2, 800.0, 2)
    elif call == "greet":
        s = 0.62
        a = vo.call(rng, 0.24, [(0.0, f * 1.05), (0.24, f * 1.15)], [(0.0, "m"), (0.24, "m")],
                    [(0.0, 0.0), (0.04, 0.7), (0.2, 0.6), (0.24, 0.0)], rate, tract, breath=0.08, sub=0.2)
        b = vo.call(rng, 0.36, [(0.0, f * 1.15), (0.36, f * 1.4)], [(0.0, "m"), (0.08, "o"), (0.36, "a")],
                    [(0.0, 0.0), (0.04, 0.9), (0.28, 0.8), (0.36, 0.0)], rate, tract, breath=0.08, sub=0.2)
        x = np.zeros(fx.frames(s, rate))
        core.mix_into(x, 0, a)
        core.mix_into(x, fx.frames(0.24, rate), b)
    else:   # roar (troll, Matriarch) and bellow (a rival giant's: not the player's roar)
        s = 1.3 if who != "matriarch" else 1.5
        x = vo.call(rng, s, [(0.0, f * 0.85), (0.2, f * 1.08), (0.9, f), (s, f * 0.72)],
                    [(0.0, "uh"), (0.15, "a"), (0.9, "o"), (s, "u")],
                    [(0.0, 0.0), (0.12, 1.0), (0.9, 0.85), (s, 0.0)], rate, tract, breath=0.24, growl=growl + 0.1,
                    drive=drive + 0.5, tilt_db=1.0, **kw)
        rattle = vo.growl_tail(rng, fx.frames(s, rate), rate, f * 0.6, tract, [(0.0, 0.0), (0.3, 0.6), (1.0, 0.5), (s, 0.0)])
        x = _norm(x) + 0.35 * _norm(rattle)
        if who == "matriarch":   # a shriek riding the bellow
            n = x.shape[0]
            t = fx.t_axis(n, rate)
            shriek = vo.call(rng, s, [(0.0, 420.0), (0.3, 560.0), (s, 380.0)], [(0.0, "ae"), (s, "a")],
                             [(0.0, 0.0), (0.3, 0.6), (1.0, 0.5), (s, 0.0)], rate, 0.85, breath=0.4, jitter=0.06,
                             shimmer=0.35, drive=2.0)
            x = x + 0.22 * fx.fit(_norm(shriek), n) * (0.6 + 0.4 * np.sin(TWO_PI * 5.0 * t))
        x = fx.valley_echo(x, rng, rate, 0.32, 0.25, 700.0, 2)
    return fx.finish(x, rate, fade_in_s=0.004)


def big_far(rng, rate, variant, who):
    """A big body's roar from far off (the boss and giant classes' far versions)."""
    x = big_voice(rng, rate, 0, who, "roar")
    return fx.finish(fx.distant(x, rng, rate, 650.0, 0.05, 0.2), rate)


def dire_wolf(rng, rate, variant, call):
    """A dire wolf: a bigger, rougher wolf - lower snarls and barks, a heavier snap."""
    if call == "alert":
        n = fx.frames(0.62, rate)
        x = np.zeros(n)
        core.mix_into(x, 0, vo.snarl(rng, 0.34, rate, rng.uniform(88.0, 102.0), 1.3), 0.8)
        core.mix_into(x, fx.frames(0.3, rate), vo.bark(rng, 0.26, rate, rng.uniform(280.0, 320.0), 1.25), 1.0)
    elif call == "attack":
        n = fx.frames(0.36, rate)
        x = fx.fit(vo.snarl(rng, 0.3, rate, rng.uniform(95.0, 115.0), 1.28, 1.0), n)
        x = _norm(x) + 0.9 * vo.snap(rng, n, rate, rng.uniform(0.2, 0.25))
    elif call == "hurt":
        x = vo.yelp(rng, 0.3, rate, rng.uniform(620.0, 700.0), rng.uniform(330.0, 380.0), 1.25)
    elif call == "death":
        n = fx.frames(0.85, rate)
        x = np.zeros(n)
        core.mix_into(x, 0, vo.yelp(rng, 0.24, rate, 700.0, 430.0, 1.25), 1.0)
        core.mix_into(x, fx.frames(0.22, rate), vo.yelp(rng, 0.6, rate, 480.0, 230.0, 1.3, whine=True), 0.6)
    else:   # flee
        x = vo.yelp(rng, 0.5, rate, rng.uniform(760.0, 820.0), 540.0, 1.45, True)
    return fx.finish(x, rate, fade_in_s=0.004)


def horse(rng, rate, variant, call):
    """A cavalry horse: a whinny, a snorting effort, a squeal of pain, a fall, a frightened neigh."""
    def neigh(s, f_pts, vib=0.06, tract=0.85):
        return vo.call(rng, s, f_pts, [(0.0, "i"), (s * 0.3, "ae"), (s, "a")],
                       [(0.0, 0.0), (0.04, 1.0), (s * 0.6, 0.7), (s, 0.0)], rate, tract, jitter=0.02, shimmer=0.25,
                       vibrato_hz=18.0, vibrato=vib, breath=0.2)

    def snort(s):
        n = fx.frames(s, rate)
        t = fx.t_axis(n, rate)
        return fx.noise(n, rng, 300.0, 2200.0, rate) * fx.env_ad(n, rate, 0.008, s * 0.3) * (1.0 + 0.6 * np.sin(TWO_PI * 36.0 * t))
    if call == "alert":
        x = neigh(0.9, [(0.0, 430.0), (0.15, 760.0), (0.55, 600.0), (0.9, 340.0)])
    elif call == "attack":
        n = fx.frames(0.5, rate)
        x = _norm(fx.fit(snort(0.3), n)) * 0.8 + 0.6 * _at(n, rate, 0.18, _norm(neigh(0.3, [(0.0, 520.0), (0.3, 420.0)], 0.03)))
    elif call == "hurt":
        x = neigh(0.42, [(0.0, 700.0), (0.06, 820.0), (0.42, 520.0)], 0.08, 0.8)
    elif call == "death":
        n = fx.frames(1.0, rate)
        x = _norm(fx.fit(neigh(0.6, [(0.0, 760.0), (0.6, 380.0)], 0.1), n)) \
            + 0.7 * _at(n, rate, 0.55, _norm(ins.impact_flesh(rng, 0.4, 1.0, rate)))
    else:   # flee
        x = neigh(0.8, [(0.0, 500.0), (0.12, 820.0), (0.8, 560.0)], 0.09)
    return fx.finish(fx.reflections(x, rng, rate, 5, 0.05, 0.15, 3000.0), rate, fade_in_s=0.004)


def crowd(rng, rate, variant, call):
    """A crowd: soldiers routing (shouts breaking up as they run, armour and feet), or an engine's
    crew abandoning it (shouts, a dropped tool, running)."""
    def speaker(r, i):
        return vo.voice_params(r, "man" if i % 4 else "woman")
    if call == "flee":
        def one(r, i):
            p = speaker(r, i)
            top = p["f0"] * r.uniform(1.5, 1.9)
            return vo.call(r, 0.8, [(0.0, p["f0"] * 1.2), (0.08, top), (0.8, top * 0.8)],
                           [(0.0, "a"), (0.3, "ae"), (0.8, "e")], [(0.0, 0.0), (0.04, 1.0), (0.5, 0.7), (0.8, 0.0)],
                           rate, p["tract"], breath=0.3, vibrato_hz=8.0, vibrato=0.04, drive=1.3)
        x = vo.crowd(rng, 1.2, one, 6, 0.4, rate, 4500.0)
        n = x.shape[0]
        feet = np.zeros(n)
        for k in range(10):
            core.mix_into(feet, fx.frames(0.08 * k + rng.uniform(0.0, 0.05), rate), ins.human_step(rng, "soft", rate), rng.uniform(0.3, 0.6))
        clank = ins.crackle(rng, n, rate, 0.05, 0.9, 40.0, 1500.0, 5000.0)
        x = _norm(x) + 0.35 * _norm(feet) + 0.15 * _norm(clank)
    else:   # abandon
        def one(r, i):
            p = speaker(r, i)
            return vo.call(r, 0.45, [(0.0, p["f0"] * 1.1), (0.05, p["f0"] * 1.4), (0.45, p["f0"])],
                           [(0.0, "o"), (0.45, "a")], [(0.0, 0.0), (0.02, 1.0), (0.3, 0.7), (0.45, 0.0)],
                           rate, p["tract"], breath=0.2, drive=1.5)
        x = vo.crowd(rng, 0.9, one, 3, 0.3, rate, 5000.0)
        n = x.shape[0]
        drop = _at(n, rate, 0.12, _norm(ins.impact_wood(rng, 0.3, 0.5, rate)))
        feet = np.zeros(n)
        for k in range(6):
            core.mix_into(feet, fx.frames(0.3 + 0.09 * k, rate), ins.human_step(rng, "hard", rate), 0.5)
        x = _norm(x) + 0.5 * drop + 0.35 * _norm(feet)
    return fx.finish(fx.soft_clip(x, 1.3), rate, fade_in_s=0.004)


# --------------------------------------------------------------------------- F threat


def _tick(rng, n, rate, level=0.35):
    return level * _norm(ins.burst(rng, n, rate, 2000.0, 9500.0, 0.0002, 0.0025, "white"))


def _rise(rng, n, rate, seconds, lo, hi, q, peak_at, rise_pow):
    """P21's rising band-pass sweep under a swell (the threat family's signature)."""
    src = fx.noise(n, rng, 0.0, 0.0, rate, "white")
    y = fx.swept_band(src, [(0.0, lo), (seconds * peak_at, hi), (seconds, hi * 1.08)], [(0.0, q), (seconds, q * 1.3)],
                      rate, 512, 0.02)
    return _norm(y) * fx.env_swell(n, rate, seconds * peak_at, rise_pow, seconds * 0.08)


def wall(rng, rate, variant, seconds):
    """A formation's brace (one per brace cycle): a low ratcheting rumble - a dozen pikes and
    shields setting at once - under the threat family's rising sweep and tick."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    rise = _rise(rng, n, rate, seconds, 1800.0, 7000.0, 2.0, 0.8, 2.2)
    rate_hz = 18.0 + 22.0 * np.clip(t / seconds, 0.0, 1.0)
    ratchet = np.clip(np.sin(TWO_PI * np.cumsum(rate_hz) / rate), 0.0, 1.0) ** 8
    clicks = fx.noise(n, rng, 600.0, 4500.0, rate) * ratchet
    rumble = fx.noise(n, rng, 45.0, 220.0, rate, "brown") * fx.env_swell(n, rate, seconds * 0.8, 1.5, 0.05)
    x = 0.8 * rise + 0.5 * _norm(clicks) * fx.env_swell(n, rate, seconds * 0.8, 1.2, 0.05) + 0.6 * _norm(rumble)
    return fx.finish(x + _tick(rng, n, rate), rate, fade_in_s=0.0)


def incoming(rng, rate, variant, seconds):
    """A catapult's stone coming down (played at its landing circle): a whistle rising from 900 Hz
    to 2.6 kHz over the threat family's sweep, swelling to the landing, where it stops."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    k = np.clip(t / seconds, 0.0, 1.0)
    f = (900.0, 960.0)[variant] * (2.9 ** (k ** 1.4))
    whistle = (core.sine(f, n, rate) + 0.25 * core.sine(f * 2.0, n, rate)) * (1.0 + 0.08 * np.sin(TWO_PI * 11.0 * t))
    air = fx.swept_band(fx.noise(n, rng, 0.0, 0.0, rate, "white"), [(0.0, 900.0), (seconds, 2800.0)],
                        [(0.0, 6.0), (seconds, 6.0)], rate)
    rise = _rise(rng, n, rate, seconds, 2000.0, 7500.0, 2.4, 0.92, 2.6)
    env = fx.env_swell(n, rate, seconds * 0.94, 2.4, seconds * 0.03)
    x = (0.7 * whistle + 0.35 * _norm(air)) * env + 0.5 * rise
    return fx.finish(x, rate, fade_in_s=0.01)


# --------------------------------------------------------------------------- G world objects


def gate(rng, rate, variant, seconds, kind):
    """A size gate answering the giant at the contact point: deep water heaving back (water), a
    cliff or a stone gate that will not give (stone), a palisade gate's timbers groaning (timber)."""
    n = fx.frames(seconds, rate)
    if kind == "water":
        surge = fx.swept_band(fx.noise(n, rng, 0.0, 0.0, rate, "pink"), [(0.0, 180.0), (seconds * 0.3, 700.0), (seconds, 200.0)],
                              [(0.0, 1.2), (seconds, 1.6)], rate)
        surge *= fx.env_swell(n, rate, seconds * 0.3, 1.4, seconds * 0.25)
        spray = ins.crunch(rng, n, rate, seconds * 0.15, seconds * 0.5, 2200.0, 1500.0, 7000.0, (0.002, 0.008))
        thump = ins.thump(n, rate, 70.0, 40.0, 0.04, 0.15, 0.01, 0.2, 0.5)
        bub = np.zeros(n)
        for _k in range(14):
            m = fx.frames(rng.uniform(0.01, 0.03), rate)
            f0 = rng.uniform(300.0, 800.0)
            b = core.sine(np.linspace(f0, f0 * 2.4, m), m, rate) * np.hanning(m)
            core.mix_into(bub, fx.frames(rng.uniform(0.2, seconds * 0.9), rate), b, rng.uniform(0.2, 0.5))
        x = _norm(surge) + 0.35 * _norm(spray) + 0.5 * thump + 0.25 * _norm(bub)
    elif kind == "stone":
        hit = ins.impact_stone(rng, seconds, 0.9, rate)
        grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.05, 1.0), (0.35, 0.2), (seconds, 0.0)], n, rate),
                          500.0, 200.0, 2000.0)
        boom = ins.thump(n, rate, 60.0, 34.0, 0.04, 0.16, 0.004, 0.25, 0.8)
        x = 0.8 * hit + 0.45 * _norm(grind) + 0.8 * boom
    else:   # timber
        thud = ins.impact_wood(rng, seconds, 1.0, rate, rng.uniform(95.0, 120.0))
        groan = ins.creak(rng, seconds, [(0.0, 28.0), (seconds, 16.0)], rate, grip_points=[(0.0, 1.0), (seconds, 0.3)])
        boom = ins.thump(n, rate, 80.0, 45.0, 0.03, 0.12, 0.003, 0.2, 0.6)
        x = 0.8 * fx.fit(thud, n) + 0.4 * _norm(groan) * fx.env_ad(n, rate, 0.03, seconds * 0.4) + 0.6 * boom
    return fx.finish(fx.soft_clip(x, 1.5), rate)


def splash(rng, rate, variant, seconds, size):
    """A body entering water deeper than half a metre: a slap and a spray (small); a deep plunge,
    a column of spray and the drops raining back (large)."""
    n = fx.frames(seconds, rate)
    big = size == "large"
    slap = ins.burst(rng, n, rate, 400.0, 4000.0, 0.001, 0.03 if big else 0.015)
    plunge = ins.thump(n, rate, 90.0 if big else 160.0, 45.0 if big else 90.0, 0.03, 0.12 if big else 0.05, 0.004, 0.2, 0.4)
    spray = ins.crunch(rng, n, rate, 0.01, seconds * 0.45, 2600.0 if big else 1600.0, 1200.0, 7500.0, (0.002, 0.01))
    whoosh = ins.whoosh(rng, seconds * 0.6, 300.0, 1500.0, 0.2, 1.0, 1.4)
    drops = np.zeros(n)
    for _k in range(30 if big else 12):
        m = fx.frames(rng.uniform(0.008, 0.02), rate)
        f0 = rng.uniform(700.0, 2200.0)
        d = core.sine(np.linspace(f0, f0 * 1.8, m), m, rate) * np.hanning(m)
        core.mix_into(drops, fx.frames(rng.uniform(0.15, seconds * 0.85), rate), d, rng.uniform(0.15, 0.5))
    x = 0.7 * slap + 0.8 * plunge + 0.7 * _norm(spray) + 0.4 * fx.fit(_norm(whoosh), n) + 0.3 * _norm(drops)
    return fx.finish(fx.soft_clip(x, 1.6), rate)


def trample(rng, rate, variant, seconds):
    """A fence or a palisade crushed under a big foot: a crunch of splintering stakes pressed into
    the ground, the foot's thud."""
    n = fx.frames(seconds, rate)
    spl = ins.splinter(rng, n, rate, 0.0, seconds * 0.4, 1600.0, 1.4)
    crunch = ins.crunch(rng, n, rate, 0.0, seconds * 0.3, 1500.0, 300.0, 3000.0)
    thud = ins.thump(n, rate, 80.0, 40.0, 0.03, 0.1, 0.003, 0.25, 0.7)
    snap = ins.burst(rng, n, rate, 800.0, 6000.0, 0.0003, 0.006)
    x = 0.8 * _norm(spl) + 0.5 * _norm(crunch) + 0.7 * thud + 0.5 * snap
    return fx.finish(fx.soft_clip(x, 1.5), rate)


def town_bell(rng, rate, variant, seconds):
    """A town bell rung for a giant at the gate: three slow strokes of a big bell."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    f0 = rng.uniform(300.0, 330.0)
    for k, at in enumerate((0.0, 0.62, 1.24)):
        b = ins.bell(rng, n, rate, f0 * rng.uniform(0.997, 1.003), 2.2, strike=0.35)
        core.mix_into(x, fx.frames(at, rate), _norm(b), (1.0, 0.85, 0.9)[k])
    return fx.finish(fx.reflections(x, rng, rate, 6, 0.08, 0.25, 2500.0), rate)


def horn_alarm(rng, rate, variant, seconds):
    """A war horn sounding an alarm: two long blasts on a low horn, the second higher and
    wavering."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)

    def blast(f0, dur, bend):
        m = fx.frames(dur, rate)
        tt = fx.t_axis(m, rate)
        freq = f0 * (1.0 - 0.04 * np.exp(-tt / 0.06)) * (1.0 + bend * np.sin(TWO_PI * 5.0 * tt))
        w = np.array([1.0, 0.8, 0.55, 0.4, 0.28, 0.18, 0.1, 0.06])
        env = np.clip(tt / 0.08, 0.0, 1.0) * np.clip((dur - tt) / 0.15, 0.0, 1.0)
        amps = w[:, None] * env[None, :] ** (1.0 + np.arange(8)[:, None] * 0.25)
        y = np.zeros(m)
        base = np.cumsum(freq) / rate
        for k in range(8):
            y += amps[k] * np.sin(TWO_PI * (k + 1) * base)
        return y + 0.08 * fx.noise(m, rng, 300.0, 2500.0, rate) * env
    x = _at(n, rate, 0.0, _norm(blast(146.8, 0.7, 0.004))) + _at(n, rate, 0.8, _norm(blast(174.6, 0.95, 0.012)))
    x = fx.valley_echo(fx.lowpass(x, 3500.0, 2.0, rate), rng, rate, 0.4, 0.25, 900.0, 2)
    return fx.finish(fx.fit(x, n), rate)


def interact_exit(rng, rate, variant, seconds):
    """Stepping through an exit: a heavy stone door's grind and a draught of air."""
    n = fx.frames(seconds, rate)
    grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.08, 1.0), (seconds * 0.6, 0.4), (seconds, 0.0)], n, rate),
                      450.0, 200.0, 2000.0)
    air = ins.whoosh(rng, seconds, 200.0, 900.0, 0.5, 1.0, 1.4)
    x = 0.7 * _norm(grind) + 0.5 * _norm(air)
    return fx.finish(x, rate, fade_in_s=0.01)


def interact_inscription(rng, rate, variant, seconds):
    """Reading an old king's inscription: a stone resonance hummed awake and a soft chime of runes."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    hum = (core.sine(98.0, n, rate) + 0.5 * core.sine(147.0, n, rate)) * fx.env_points([(0.0, 0.0), (0.2, 1.0), (seconds, 0.0)], n, rate)
    chime = np.zeros(n)
    for k, f in enumerate((587.3, 880.0, 1174.7)):
        core.mix_into(chime, fx.frames(0.1 + 0.12 * k, rate), _norm(ins.bell(rng, n, rate, f, 0.6, strike=0.1)), 0.6 - 0.12 * k)
    shimmer = fx.tremolo(fx.noise(n, rng, 3000.0, 8000.0, rate), 12.0, 0.6, rate) * fx.env_swell(n, rate, seconds * 0.5, 2.0, 0.2)
    x = 0.5 * hum + _norm(chime) + 0.08 * _norm(shimmer)
    return fx.finish(x, rate, fade_in_s=0.01)


def brace(rng, rate, variant, seconds):
    """A formation bracing: a dozen pikes levelled and grounded at once (a wooden clatter and the
    butts thudding into the ground), steel shivering, and the rank's shout."""
    n = fx.frames(seconds, rate)
    clatter = np.zeros(n)
    for _k in range(12):
        k = ins.impact_wood(rng, 0.2, 0.3, rate)
        core.mix_into(clatter, fx.frames(rng.uniform(0.0, 0.12), rate), _norm(k), rng.uniform(0.3, 0.8))
    thuds = np.zeros(n)
    for _k in range(8):
        core.mix_into(thuds, fx.frames(rng.uniform(0.1, 0.2), rate), ins.thump(fx.frames(0.2, rate), rate, 120.0, 70.0, 0.01, 0.04, 0.001, 0.2), 0.5)
    steel = ins.crackle(rng, n, rate, 0.0, 0.3, 120.0, 2500.0, 7000.0)

    def one(r, i):
        p = vo.voice_params(r, "man")
        return vo.call(r, 0.3, [(0.0, p["f0"] * 1.2), (0.05, p["f0"] * 1.45), (0.3, p["f0"] * 1.1)], [(0.0, "uh"), (0.3, "a")],
                       [(0.0, 0.0), (0.02, 1.0), (0.2, 0.7), (0.3, 0.0)], rate, p["tract"], breath=0.2, drive=1.6)
    shout = _at(n, rate, 0.08, vo.crowd(rng, 0.45, one, 6, 0.05, rate, 4000.0))
    x = 0.7 * _norm(clatter) + 0.5 * _norm(thuds) + 0.2 * _norm(steel) + 0.6 * _norm(shout)
    return fx.finish(fx.soft_clip(x, 1.4), rate)


def horn_broken(rng, rate, variant, seconds):
    """A formation broken: its signal horn blown in panic, wavering, cracking and dying away."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    f = 233.1 * (1.0 - 0.18 * np.clip((t - 0.4) / 0.6, 0.0, 1.0)) * (1.0 + 0.02 * np.sin(TWO_PI * 7.0 * t))
    w = np.array([1.0, 0.7, 0.5, 0.35, 0.25, 0.15])
    base = np.cumsum(f) / rate
    env = np.clip(t / 0.05, 0.0, 1.0) * np.clip((seconds - t) / 0.4, 0.0, 1.0)
    crack = 1.0 - 0.7 * ((t > 0.55) & (t < 0.63))
    y = sum(w[k] * np.sin(TWO_PI * (k + 1) * base) * env ** (1.0 + 0.3 * k) for k in range(6)) * crack
    y = y + 0.15 * fx.noise(n, rng, 400.0, 3000.0, rate) * env
    return fx.finish(fx.reflections(y, rng, rate, 6, 0.08, 0.25, 3000.0), rate)


def banner_fall(rng, rate, variant, seconds):
    """A banner falling: the pole creaking over, the cloth's whoosh, the pole's thud and the flag's
    heavy flop."""
    n = fx.frames(seconds, rate)
    creak = ins.creak(rng, 0.35, [(0.0, 18.0), (0.35, 30.0)], rate, grip_points=[(0.0, 1.0), (0.35, 0.4)])
    cloth = ins.whoosh(rng, 0.5, 300.0, 1600.0, 0.7, 1.0, 1.6)
    thud = ins.impact_wood(rng, 0.4, 0.8, rate)
    flop = ins.burst(rng, fx.frames(0.3, rate), rate, 200.0, 1800.0, 0.004, 0.06, "pink")
    x = _at(n, rate, 0.0, 0.5 * _norm(creak)) + _at(n, rate, 0.25, 0.5 * _norm(cloth)) \
        + _at(n, rate, 0.6, 0.9 * _norm(thud)) + _at(n, rate, 0.66, 0.5 * _norm(flop))
    return fx.finish(fx.soft_clip(x, 1.3), rate)


def ballista_fire(rng, rate, variant, seconds):
    """A ballista loosing: the trigger's clack, the torsion arms slamming forward (a deep wooden
    thump and a low string twang), the frame rattling."""
    n = fx.frames(seconds, rate)
    clack = ins.impact_wood(rng, 0.15, 0.2, rate)
    slam = ins.impact_wood(rng, seconds, 1.0, rate, rng.uniform(90.0, 110.0))
    twang = ins.pluck(rng, n, rate, rng.uniform(70.0, 85.0), 0.12, 16, 0.5, 0.2)
    rattle = ins.debris(rng, n, rate, 0.05, 0.3, 16, "wood", 1.0)
    boom = ins.thump(n, rate, 90.0, 45.0, 0.02, 0.1, 0.002, 0.2, 0.6)
    x = _at(n, rate, 0.0, 0.4 * _norm(clack)) + _at(n, rate, 0.04, 0.9 * _norm(slam)) + _at(n, rate, 0.04, 0.6 * _norm(twang)) \
        + 0.3 * _norm(rattle) + _at(n, rate, 0.04, 0.6 * boom[:n - fx.frames(0.04, rate)])
    return fx.finish(fx.soft_clip(x, 1.5), rate)


def catapult_fire(rng, rate, variant, seconds):
    """A catapult's throw: the ropes creaking under the winch, the release, the arm whipping up
    and slamming into its crossbar."""
    n = fx.frames(seconds, rate)
    creak = ins.creak(rng, 0.35, [(0.0, 22.0), (0.35, 12.0)], rate, body=(160.0, 300.0, 520.0, 800.0, 1200.0),
                      grip_points=[(0.0, 1.0), (0.35, 0.7)])
    whip = ins.whoosh(rng, 0.35, 120.0, 900.0, 0.6, 0.9, 1.8)
    slam = ins.impact_wood(rng, 0.5, 1.0, rate, rng.uniform(80.0, 100.0))
    boom = ins.thump(fx.frames(0.5, rate), rate, 70.0, 36.0, 0.03, 0.14, 0.003, 0.25, 0.8)
    x = _at(n, rate, 0.0, 0.45 * _norm(creak)) + _at(n, rate, 0.3, 0.6 * _norm(whip)) \
        + _at(n, rate, 0.55, 0.9 * _norm(slam)) + _at(n, rate, 0.55, 0.8 * boom)
    return fx.finish(fx.soft_clip(x, 1.5), rate)


def cavalry_charge(rng, rate, variant, seconds):
    """A cavalry charge beginning: hooves breaking into a gallop and swelling, the riders' cry."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    t = 0.02
    gap = 0.16
    k = 0
    while t < seconds - 0.25:
        h = hoof(rng, rate, 0, "soft" if k % 3 else "hard")
        core.mix_into(out, fx.frames(t, rate), h, 0.35 + 0.65 * min(1.0, t / (seconds * 0.7)))
        t += gap * rng.uniform(0.85, 1.15)
        gap = max(0.07, gap * 0.92)
        k += 1
    rumble = ins.rumble(rng, n, rate, 220.0, seconds * 0.7, seconds * 0.3, 9.0, 0.4)

    def one(r, i):
        p = vo.voice_params(r, "man")
        return vo.call(r, 0.6, [(0.0, p["f0"] * 1.3), (0.1, p["f0"] * 1.7), (0.6, p["f0"] * 1.4)], [(0.0, "a"), (0.6, "o")],
                       [(0.0, 0.0), (0.05, 1.0), (0.4, 0.8), (0.6, 0.0)], rate, p["tract"], breath=0.2, drive=1.5)
    cry = _at(n, rate, seconds * 0.45, vo.crowd(rng, 0.7, one, 4, 0.15, rate, 5000.0))
    x = _norm(out) + 0.5 * _norm(rumble) + 0.4 * _norm(cry)
    return fx.finish(fx.soft_clip(x, 1.4), rate, fade_in_s=0.02)


def burning(rng, rate, variant, seconds):
    """Something catching fire: a whoosh of flame and a crackle settling into a burn."""
    n = fx.frames(seconds, rate)
    whoosh = ins.whoosh(rng, seconds * 0.5, 200.0, 1800.0, 0.35, 1.0, 1.6)
    roar = fx.noise(n, rng, 60.0, 700.0, rate, "brown") * fx.env_points([(0.0, 0.0), (0.12, 1.0), (seconds, 0.3)], n, rate)
    crk = ins.crackle(rng, n, rate, 0.05, seconds * 0.9, 90.0, 1500.0, 6000.0)
    x = 0.7 * fx.fit(_norm(whoosh), n) + 0.6 * _norm(roar) + 0.4 * _norm(crk)
    return fx.finish(x, rate, fade_in_s=0.01)


def regrow(rng, rate, variant, seconds):
    """A troll's wounds closing: wet, squelching regrowth - bubbling flesh and a slow stretch."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    for _k in range(26):
        m = fx.frames(rng.uniform(0.02, 0.06), rate)
        f0 = rng.uniform(120.0, 420.0)
        sq = fx.swept_band(fx.noise(m, rng, 0.0, 0.0, rate, "pink"), [(0.0, f0 * 3.0), (m / rate, f0)],
                           [(0.0, 3.0), (m / rate, 3.0)], rate, 256)
        core.mix_into(out, fx.frames(rng.uniform(0.0, seconds * 0.85), rate), _norm(sq) * np.hanning(m), rng.uniform(0.3, 0.9))
    stretch = ins.creak(rng, seconds, [(0.0, 9.0), (seconds, 15.0)], rate, body=(140.0, 260.0, 400.0, 600.0, 900.0),
                        grip_points=[(0.0, 0.3), (seconds * 0.5, 0.8), (seconds, 0.2)])
    x = _norm(out) + 0.25 * _norm(stretch)
    return fx.finish(fx.lowpass(x, 3000.0, 2.0, rate), rate, fade_in_s=0.01)


# --------------------------------------------------------------------------- D abilities


def quake(rng, rate, variant, seconds):
    """The earthquake's pulse: the ground cracking open (a sub drop and a long tearing crack),
    rubble jumping and a rumble rolling away."""
    n = fx.frames(seconds, rate)
    boom = ins.thump(n, rate, 55.0, 24.0, 0.06, 0.28, 0.004, 0.25, 0.9)
    tear = ins.crackle(rng, n, rate, 0.0, seconds * 0.35, 900.0, 300.0, 3500.0)
    grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 1.0), (seconds * 0.4, 0.3), (seconds, 0.0)], n, rate), 700.0, 150.0, 1800.0)
    rubble = ins.debris(rng, n, rate, 0.05, seconds * 0.6, 30, "stone", 1.4)
    rum = ins.rumble(rng, n, rate, 260.0, 0.04, seconds * 0.4, 6.0, 0.45)
    x = boom + 0.5 * _norm(tear) + 0.45 * _norm(grind) + 0.35 * _norm(rubble) + 0.5 * _norm(rum)
    x = fx.fit(fx.valley_echo(fx.soft_clip(x, 1.8), rng, rate, 0.3, 0.22, 600.0, 2), n)
    return fx.finish(x, rate)


def charge_rush(rng, rate, variant, seconds):
    """A shoulder charge: the giant lunging - three pounding strides under a heavy rush of air."""
    n = fx.frames(seconds, rate)
    rush = ins.whoosh(rng, seconds, 80.0, 500.0, 0.7, 0.8, 1.6, color="brown")
    cloth = ins.whoosh(rng, seconds, 700.0, 2500.0, 0.65, 1.6, 1.4)
    strides = np.zeros(n)
    for k, at in enumerate((0.0, 0.18, 0.33)):
        st = ins.giant_step(rng, "giant_s4", "soft", True, rate, 0.3)
        core.mix_into(strides, fx.frames(at, rate), _norm(st), 0.6 + 0.2 * k)
    x = _norm(rush) + 0.3 * _norm(cloth) + 0.7 * strides
    return fx.finish(fx.soft_clip(x, 1.4), rate, fade_in_s=0.01)


def ward_on(rng, rate, variant, seconds):
    """A stone ward closing round the giant (Bulwark, Stonewall Stance, Bedrock Ward; the banks
    pitch it): grinding stone rising into a deep hum, then plates clacking into place."""
    n = fx.frames(seconds, rate)
    env = fx.env_swell(n, rate, seconds * 0.6, 1.6, 0.08)
    grind = ins.grind(rng, n, rate, env, 480.0, 180.0, 2200.0)
    hum = (core.sine(73.4, n, rate) + 0.5 * core.sine(110.0, n, rate) + 0.3 * core.sine(146.8, n, rate)) * env
    clack = _at(n, rate, seconds * 0.6, _norm(ins.impact_stone(rng, 0.3, 0.7, rate)))
    x = 0.6 * _norm(grind) + 0.45 * hum + 0.8 * clack
    return fx.finish(x, rate, fade_in_s=0.01)


def regrowth(rng, rate, variant, seconds):
    """Primal Regrowth taking hold: green things growing - a soft creaking stretch, leaves rustling
    open and a warm rising chime."""
    n = fx.frames(seconds, rate)
    stretch = ins.creak(rng, seconds, [(0.0, 10.0), (seconds, 24.0)], rate, body=(300.0, 520.0, 800.0, 1200.0, 1800.0),
                        grip_points=[(0.0, 0.2), (seconds * 0.5, 0.7), (seconds, 0.1)])
    leaves = ins.leaves(rng, n, rate, fx.env_swell(n, rate, seconds * 0.6, 1.5, 0.2), 700.0)
    chime = np.zeros(n)
    for k, f in enumerate((440.0, 554.4, 659.3)):
        core.mix_into(chime, fx.frames(0.15 + 0.15 * k, rate), _norm(ins.bell(rng, n, rate, f * 1.78, 0.6, strike=0.0)), 0.5)
    x = 0.35 * _norm(stretch) + 0.4 * _norm(leaves) + 0.6 * _norm(chime) * fx.env_swell(n, rate, seconds * 0.7, 1.5, 0.15)
    return fx.finish(x, rate, fade_in_s=0.01)


def lightning(rng, rate, variant, seconds):
    """A lightning strike: an instant broadband crack and sizzle, then thunder rolling away."""
    n = fx.frames(seconds, rate)
    crack = ins.burst(rng, n, rate, 300.0, 9000.0, 0.0002, 0.012)
    sizzle = ins.crackle(rng, n, rate, 0.0, 0.18, 1500.0, 2000.0, 8000.0)
    thunder = fx.highpass(ins.rumble(rng, n, rate, 380.0, 0.05, seconds * 0.4, 6.5, 0.5), 40.0, 2.0, rate, "zero")
    low = ins.thump(n, rate, 60.0, 30.0, 0.05, seconds * 0.25, 0.01, 0.2, 0.8)
    x = 0.9 * _norm(crack) + 0.4 * _norm(sizzle) + _norm(thunder) * 0.8 + 0.6 * low
    x = fx.fit(fx.valley_echo(x, rng, rate, 0.45, 0.28, 600.0, 2), n)
    return fx.finish(x, rate)


def ballista_whirr(rng, rate, variant, seconds):
    """A ballista bolt in flight: a heavy shaft whirring away (a low rush with a tonal flutter)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    w = ins.whoosh(rng, seconds, 250.0, 1400.0, 0.2, 1.4, 1.2, fall_tau=seconds * 0.4)
    whirr = ins.fm(n, rate, 320.0 * (1.0 - 0.2 * t / seconds), 0.5, 1.5) * fx.env_ad(n, rate, 0.01, seconds * 0.4)
    x = _norm(w) * (1.0 + 0.3 * np.sin(TWO_PI * 26.0 * t)) + 0.3 * whirr
    return fx.finish(x, rate, fade_in_s=0.003)


# --------------------------------------------------------------------------- H interface


def travel(rng, rate, variant, seconds):
    """Fast travel: a soft rising rush and a two-note chime (D-A) in the score's key."""
    n = fx.frames(seconds, rate)
    rush = ins.whoosh(rng, seconds, 400.0, 3000.0, 0.7, 1.2, 1.6)
    chime = ins.blip(rng, seconds, [74, 81], rate, "sine", 0.12, 0.004, 0.12, 4.0, 0.0, 0.3)   # D5, A5
    x = 0.4 * _norm(rush) + fx.fit(_norm(chime), n)
    return fx.finish(x, rate, fade_in_s=0.005)


# --------------------------------------------------------------------------- the build list


def _v(sub, name, func, seed, count, params, **extra):
    return ins.variant_cues("world/" + sub, name, func, seed, count, params, scope="world", **extra)


CUES = []
_seed = 282001
for _stage, _size in ((4, "giant_s4"), (5, "giant_s5"), (6, "giant_s6")):
    base = 282001 + (_stage - 4) * 20
    CUES += (_v("steps", "giant_s%d_soft" % _stage, giant, base, 2, {"size": _size, "surface": "soft", "seconds": 0.5})
             + _v("steps", "giant_s%d_hard" % _stage, giant, base + 2, 1, {"size": _size, "surface": "hard", "seconds": 0.5})
             + _v("steps", "giant_s%d_wet" % _stage, giant, base + 3, 1, {"size": _size, "surface": "wet", "seconds": 0.38})
             + _v("steps", "giant_s%d_soft_cruise" % _stage, giant, base + 4, 1,
                  {"size": _size, "surface": "soft", "cruise": True, "seconds": 0.38})
             + _v("steps", "giant_s%d_hard_cruise" % _stage, giant, base + 5, 1,
                  {"size": _size, "surface": "hard", "cruise": True, "seconds": 0.38})
             + _v("steps", "giant_s%d_wade" % _stage, giant, base + 6, 1, {"size": _size, "surface": "wade", "seconds": 0.45}))
CUES += (_v("steps", "giant_s3_wade", giant, 282071, 1, {"size": "giant_s3", "surface": "wade", "seconds": 0.42})
         + _v("steps", "heavy_wade", giant, 282073, 1, {"size": "heavy", "surface": "wade", "seconds": 0.4})
         + _v("steps", "heavy_wet", giant, 282075, 1, {"size": "heavy", "surface": "wet", "seconds": 0.32})
         + _v("steps", "hoof_soft", hoof, 282081, 2, {"surface": "soft"})
         + _v("steps", "hoof_hard", hoof, 282083, 1, {"surface": "hard"})
         + _v("steps", "hoof_wet", hoof, 282085, 1, {"surface": "wet"})
         + _v("steps", "paw_wet", paw_wet, 282087, 1, {}))

for _i, (_who, _calls) in enumerate((("troll", ("alert", "attack", "hurt", "stagger", "death", "roar")),
                                      ("matriarch", ("alert", "attack", "hurt", "death", "roar")),
                                      ("giant", ("alert", "attack", "hurt", "stagger", "death", "bellow", "greet")))):
    for _j, _call in enumerate(_calls):
        CUES += _v("voices", "%s_%s" % (_who, _call), big_voice, 282101 + 40 * _i + 3 * _j, 2 if _call == "attack" else 1,
                   {"who": _who, "call": "roar" if _call == "bellow" else _call})
CUES += (_v("voices", "troll_far", big_far, 282221, 1, {"who": "troll"})
         + _v("voices", "matriarch_far", big_far, 282223, 1, {"who": "matriarch"})
         + _v("voices", "giant_far", big_far, 282225, 1, {"who": "giant"}))
for _j, _call in enumerate(("alert", "attack", "hurt", "death", "flee")):
    CUES += _v("voices", "dire_wolf_%s" % _call, dire_wolf, 282231 + 3 * _j, 1, {"call": _call})
for _j, _call in enumerate(("alert", "attack", "hurt", "death", "flee")):
    CUES += _v("voices", "horse_%s" % _call, horse, 282251 + 3 * _j, 1, {"call": _call})
CUES += (_v("voices", "crowd_flee", crowd, 282271, 1, {"call": "flee"})
         + _v("voices", "crowd_abandon", crowd, 282273, 1, {"call": "abandon"}))

CUES += (_v("threat", "windup_wall", wall, 282301, 2, {"seconds": 0.5})
         + _v("threat", "incoming", incoming, 282311, 2, {"seconds": 1.5}))

CUES += (_v("objects", "gate_water", gate, 282401, 1, {"seconds": 0.8, "kind": "water"})
         + _v("objects", "gate_stone", gate, 282403, 1, {"seconds": 0.6, "kind": "stone"})
         + _v("objects", "gate_timber", gate, 282405, 1, {"seconds": 0.6, "kind": "timber"})
         + _v("objects", "splash_small", splash, 282411, 1, {"seconds": 0.55, "size": "small"})
         + _v("objects", "splash_large", splash, 282413, 2, {"seconds": 0.85, "size": "large"})
         + _v("objects", "trample", trample, 282421, 2, {"seconds": 0.5})
         + _v("objects", "town_bell", town_bell, 282431, 1, {"seconds": 1.9})
         + _v("objects", "horn_alarm", horn_alarm, 282433, 1, {"seconds": 1.9})
         + _v("objects", "interact_exit", interact_exit, 282441, 1, {"seconds": 0.6})
         + _v("objects", "interact_inscription", interact_inscription, 282443, 1, {"seconds": 0.9})
         + _v("objects", "formation_brace", brace, 282451, 1, {"seconds": 0.75})
         + _v("objects", "formation_horn_broken", horn_broken, 282453, 1, {"seconds": 1.2})
         + _v("objects", "formation_banner_fall", banner_fall, 282455, 1, {"seconds": 1.0})
         + _v("objects", "siege_ballista_fire", ballista_fire, 282461, 2, {"seconds": 0.6})
         + _v("objects", "siege_catapult_fire", catapult_fire, 282465, 2, {"seconds": 0.95})
         + _v("objects", "cavalry_charge", cavalry_charge, 282471, 1, {"seconds": 1.3})
         + _v("objects", "status_burning", burning, 282481, 1, {"seconds": 0.9})
         + _v("objects", "troll_regrow", regrow, 282483, 1, {"seconds": 0.9}))

CUES += (_v("abilities", "earthquake_impact", quake, 282501, 1, {"seconds": 0.85})
         + _v("abilities", "shoulder_charge", charge_rush, 282503, 1, {"seconds": 0.7})
         + _v("abilities", "ward_on", ward_on, 282505, 1, {"seconds": 0.7})
         + _v("abilities", "regrowth", regrowth, 282507, 1, {"seconds": 0.85})
         + _v("abilities", "lightning", lightning, 282509, 1, {"seconds": 1.2})
         + _v("abilities", "ballista_bolt_launch", ballista_whirr, 282511, 1, {"seconds": 0.6}))

CUES += _v("ui", "travel", travel, 282601, 1, {"seconds": 0.5})
