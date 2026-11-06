"""Abilities, projectiles, statuses and grabs (P21; plan M6-M9 section 4.1 family D, section 4.2):
bank_abilities.json: sfx.ability.<short id>.<cast|impact|sweep|roar|on>, sfx.impact.<stomp|visual>,
sfx.projectile.<visual>.launch, sfx.status.*, sfx.grab.*.

Designed layers (section 4.2): the stomp boom (a sub drop, a crack, granular rumble, a rain of
debris and an echo off the slopes), stone grinding (granular), arcane FM with a ring modulator
and shimmer (Runic Bolt, the mage), Mend's inharmonic bell chord, the roar (the giant's formant
voice) with its thunder, Titan Surge (a roar, a drum hit and a rising swell), the bow's plucked
string, the boulder ripped from the ground, whooshes for everything that flies. Every sound is
original and synthesized here. Seeds 211001-211199.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins
from synth import voices as vo

FAMILY = "abilities"


def _norm(x):
    return np.asarray(x) / max(core.peak(x), 1e-9)


# --------------------------------------------------------------------------- the stomp and the ground


def stomp(rng, rate, variant, seconds):
    """A giant's stomp: a sub drop, a crack, the earth's granular rumble, debris raining back
    and a slap off the valley's slopes (Heavy Footfall, ogre smashes and the King's slam, lowered
    by size pitch)."""
    n = fx.frames(seconds, rate)
    boom = ins.thump(n, rate, 64.0 * rng.uniform(0.95, 1.05), 27.0, 0.05, 0.24, 0.004, 0.25, 0.9)
    punch = ins.thump(n, rate, 150.0, 80.0, 0.02, 0.06, 0.002, 0.1)
    crack = ins.burst(rng, n, rate, 700.0, 6500.0, 0.0004, 0.016)
    body = ins.burst(rng, n, rate, 180.0, 900.0, 0.002, 0.07, "pink")
    rum = ins.rumble(rng, n, rate, 320.0, 0.02, 0.28, 8.0, 0.4)
    grit = ins.crunch(rng, n, rate, 0.0, 0.22, 2200.0, 300.0, 3000.0)
    rain = ins.debris(rng, n, rate, 0.12, seconds * 0.62, 34, "stone" if variant else "dirt", 1.6)
    x = (boom + 0.6 * punch + 0.6 * crack + fx.match_rms(body, boom, -6.0, 0.1, rate) + fx.match_rms(rum, boom, -9.0, 0.2, rate)
         + fx.match_rms(grit, boom, -10.0, 0.1, rate) + fx.match_rms(rain, boom, -14.0, 0.3, rate))
    x = fx.soft_clip(x, 1.8)
    x = fx.fit(fx.valley_echo(x, rng, rate, 0.29, 0.26, 650.0, 2), n)
    return fx.finish(x, rate)


def stomp_far(rng, rate, variant, seconds):
    """The stomp heard from far off: its boom and rumble, the crack and debris gone."""
    x = stomp(rng, rate, variant, seconds)
    return fx.finish(fx.distant(x, rng, rate, 450.0, 0.03, 0.2), rate)


def footfall_cast(rng, rate, variant, seconds):
    """Heavy Footfall's wind-up: the leg raised, a swelling rush and the ground's first rumble."""
    n = fx.frames(seconds, rate)
    rush = ins.whoosh(rng, seconds, 90.0, 420.0, 0.85, 0.9, 1.8, color="brown")
    rum = ins.rumble(rng, n, rate, 120.0, seconds * 0.8, 0.1, 6.0, 0.3)
    x = _norm(rush) + 0.5 * _norm(rum) * fx.env_swell(n, rate, seconds * 0.9, 2.0, 0.05)
    return fx.finish(x, rate, fade_in_s=0.02)


# --------------------------------------------------------------------------- sweeps and casts


def sweep(rng, rate, variant, seconds):
    """Sweeping Blow: a huge low swing round the giant with soil kicked up along its arc."""
    n = fx.frames(seconds, rate)
    w = ins.whoosh(rng, seconds, 70.0, 380.0, 0.5, 0.75, 1.8)
    push = ins.whoosh(rng, seconds, 40.0, 120.0, 0.5, 0.7, 1.8, color="brown")
    dirt = ins.crunch(rng, n, rate, seconds * 0.35, seconds * 0.4, 900.0, 400.0, 3500.0)
    x = _norm(w) + 0.5 * _norm(push) + 0.25 * _norm(dirt)
    return fx.finish(x, rate, fade_in_s=0.01)


def windup(rng, rate, variant, seconds, lo, hi):
    """A short wind-up: the body twisting, a whoosh drawn back."""
    w = ins.whoosh(rng, seconds, lo, hi, 0.8, 1.0, 1.6)
    return fx.finish(w, rate, fade_in_s=0.01)


def stone_skin(rng, rate, variant, seconds, part):
    """Stone Skin: grinding stone building up (cast), the shell crackling into place (on), the
    shell crumbling away (off)."""
    n = fx.frames(seconds, rate)
    if part == "cast":
        env = fx.env_swell(n, rate, seconds * 0.8, 1.5, 0.06)
        x = _norm(ins.grind(rng, n, rate, env, 520.0, 220.0, 2600.0)) + 0.5 * _norm(ins.rumble(rng, n, rate, 140.0, seconds * 0.7, 0.1))
    elif part == "on":
        crk = ins.crackle(rng, n, rate, 0.0, seconds * 0.6, 600.0, 1500.0, 6000.0)
        clack = ins.impact_stone(rng, seconds, 0.6, rate)
        x = 0.7 * _norm(crk) * fx.env_ad(n, rate, 0.01, seconds * 0.3) + 0.8 * clack
    else:
        crumbs = ins.debris(rng, n, rate, 0.02, seconds * 0.7, 26, "stone", 0.8)
        crack = ins.impact_stone(rng, seconds, 0.2, rate)
        x = 0.6 * _norm(crumbs) + 0.6 * crack
    return fx.finish(x, rate)


def grip_cast(rng, rate, variant, seconds):
    """A grab: a quick reaching whoosh and the hand's leather and knuckles tightening."""
    n = fx.frames(seconds, rate)
    w = ins.whoosh(rng, seconds, 200.0, 900.0, 0.45, 1.0, 1.6)
    creak = ins.creak(rng, seconds, [(0.0, 50.0), (seconds, 90.0)], rate, body=(480.0, 820.0, 1300.0, 2100.0, 2900.0),
                      grip_points=[(0.0, 0.0), (seconds * 0.4, 0.9), (seconds, 0.4)])
    return fx.finish(_norm(w) + 0.3 * _norm(creak), rate, fade_in_s=0.005)


def hurl_cast(rng, rate, variant, seconds):
    """Boulder Hurl's start: a boulder torn from the ground - rock cracking free, grinding, earth
    falling off it - under the giant's heave."""
    n = fx.frames(seconds, rate)
    crack = np.zeros(n)
    core.mix_into(crack, fx.frames(0.08, rate), ins.impact_stone(rng, 0.3, 0.8, rate))
    grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.1, 1.0), (0.35, 0.6), (seconds, 0.0)], n, rate),
                      600.0, 200.0, 2200.0)
    dirt = ins.debris(rng, n, rate, 0.15, seconds * 0.6, 22, "dirt", 1.2)
    lift = ins.whoosh(rng, seconds, 70.0, 260.0, 0.75, 0.8, 1.6, color="brown")
    x = 0.8 * crack + 0.6 * _norm(grind) + 0.4 * _norm(dirt) + 0.5 * _norm(lift)
    return fx.finish(fx.soft_clip(x, 1.5), rate)


def boulder_impact(rng, rate, variant, seconds):
    """The boulder lands: a stone crash, a boom, rubble and an echo."""
    n = fx.frames(seconds, rate)
    crash = ins.impact_stone(rng, seconds, 1.0, rate)
    boom = ins.thump(n, rate, 75.0, 33.0, 0.035, 0.16, 0.003, 0.25, 0.8)
    rubble = ins.debris(rng, n, rate, 0.05, seconds * 0.6, 30, "stone", 1.3)
    x = 0.9 * crash + 0.9 * boom + 0.4 * _norm(rubble)
    x = fx.fit(fx.valley_echo(fx.soft_clip(x, 1.6), rng, rate, 0.27, 0.2, 800.0, 1), n)
    return fx.finish(x, rate)


def arcane(rng, rate, variant, seconds, f_lo, f_hi, ratio=1.41, shimmer=0.35):
    """Runic magic: an FM tone whose carrier rises (f_lo -> f_hi) with a growing index, ring
    modulated, under a detuned high shimmer."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    carrier = f_lo * (f_hi / f_lo) ** np.clip(t / seconds, 0.0, 1.0)
    idx = 1.5 + 3.0 * np.clip(t / seconds, 0.0, 1.0)
    tone = ins.fm(n, rate, carrier, ratio, idx)
    tone = fx.ring_mod(tone, rng.uniform(70.0, 110.0), rate, 0.45)
    shim = sum(core.sine(f_hi * k * rng.uniform(0.995, 1.005), n, rate) for k in (2.0, 2.51, 3.02)) / 3.0
    shim = fx.tremolo(shim, rng.uniform(11.0, 15.0), 0.7, rate)
    env = fx.env_points([(0.0, 0.0), (seconds * 0.15, 0.6), (seconds * 0.85, 1.0), (seconds, 0.0)], n, rate)
    x = (tone + shimmer * shim) * env
    return fx.finish(x, rate, fade_in_s=0.01)


def mend(rng, rate, variant, seconds, part):
    """Ancestral Mend: a soft rising breath and chime (cast), a warm inharmonic bell chord (on),
    the chord's last shimmer falling away (off)."""
    n = fx.frames(seconds, rate)
    if part == "cast":
        air = ins.whoosh(rng, seconds, 300.0, 1400.0, 0.85, 1.4, 1.5)
        chime = ins.bell(rng, n, rate, 660.0, 0.25, strike=0.0) * fx.env_swell(n, rate, seconds * 0.85, 2.0, 0.05)
        x = 0.6 * _norm(air) + 0.35 * _norm(chime)
    elif part == "on":
        x = np.zeros(n)
        for k, f in enumerate((220.0, 277.2, 330.0)):   # a soft A major chord of inharmonic bells
            b = ins.bell(rng, n, rate, f * 1.78, seconds * 0.55, strike=0.15)
            core.mix_into(x, fx.frames(0.03 * k, rate), _norm(b), (1.0, 0.8, 0.7)[k])
        x = x * fx.env_ad(n, rate, 0.04, seconds * 0.5)
    else:
        b = ins.bell(rng, n, rate, 523.0, seconds * 0.35, strike=0.0)
        x = _norm(b) * fx.env_points([(0.0, 0.0), (0.02, 0.6), (seconds, 0.0)], n, rate)
    return fx.finish(x, rate, fade_in_s=0.005)


def roar_cast(rng, rate, variant, seconds):
    """Thunder Roar's start: the giant draws a deep breath while the air begins to rumble."""
    n = fx.frames(seconds, rate)
    breath = vo.breath(rng, seconds, [(0.0, "o"), (seconds, "a")], [(0.0, 0.0), (seconds * 0.7, 1.0), (seconds, 0.3)],
                       rate, 0.62, 200.0)
    rum = ins.rumble(rng, n, rate, 110.0, seconds * 0.9, 0.08, 5.0, 0.3)
    return fx.finish(0.7 * _norm(breath) + 0.6 * _norm(rum), rate, fade_in_s=0.02)


def giant_roar(rng, rate, variant, seconds):
    """The giant's roar (Thunder Roar's voice, and sfx.voice.giant.roar)."""
    x = vo.call(rng, seconds, [(0.0, 58.0), (0.15, 74.0), (0.7, 70.0), (seconds, 50.0)],
                [(0.0, "uh"), (0.12, "a"), (0.8, "a"), (seconds, "o")],
                [(0.0, 0.0), (0.08, 1.0), (0.85, 0.85), (seconds, 0.0)], rate, 0.62, breath=0.22,
                jitter=0.03, shimmer=0.14, sub=0.35, growl_hz=33.0, growl=0.45, drive=2.8, tilt_db=1.5)
    x = fx.valley_echo(x, rng, rate, 0.33, 0.24, 750.0, 2)
    return fx.finish(x, rate)


def thunder(rng, rate, variant, seconds):
    """The roar's thunder: a crack, then a rolling low rumble that swells and fades."""
    n = fx.frames(seconds, rate)
    crack = ins.burst(rng, n, rate, 400.0, 5000.0, 0.002, 0.03, "pink")
    rum = fx.highpass(ins.rumble(rng, n, rate, 420.0, 0.12, seconds * 0.35, 6.5, 0.5), 45.0, 2.0, rate, "zero")
    crackle = ins.crunch(rng, n, rate, 0.05, seconds * 0.5, 160.0, 250.0, 1800.0, (0.02, 0.07))
    low = ins.thump(n, rate, 55.0, 30.0, 0.08, seconds * 0.3, 0.02, 0.2, 0.8)
    x = 0.5 * crack + _norm(rum) + 0.6 * low + fx.match_rms(crackle, rum, -8.0, 0.3, rate)
    x = fx.fit(fx.valley_echo(x, rng, rate, 0.4, 0.3, 500.0, 2), n)
    return fx.finish(x, rate)


def surge(rng, rate, variant, seconds, part):
    """Titan Surge: a short roar, a great drum hit and a rising swell (cast); a bright surge of
    power (on); the power draining away (off)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    if part == "cast":
        roar = vo.call(rng, 0.7, [(0.0, 60.0), (0.1, 80.0), (0.7, 66.0)], [(0.0, "uh"), (0.1, "a"), (0.7, "o")],
                       [(0.0, 0.0), (0.06, 1.0), (0.5, 0.8), (0.7, 0.0)], rate, 0.62, breath=0.2, sub=0.3,
                       growl_hz=33.0, growl=0.4, drive=2.6)
        drum = ins.thump(n, rate, 70.0, 42.0, 0.03, 0.22, 0.002, 0.2, 0.9) + 0.4 * ins.burst(rng, n, rate, 200.0, 2500.0, 0.001, 0.05, "pink")
        rise_band = ins.whoosh(rng, seconds, 200.0, 3000.0, 0.95, 2.0, 2.5)
        cluster = sum(core.sine(f * (1.0 + 0.6 * t / seconds), n, rate) for f in (220.0, 277.0, 330.0, 440.0)) / 4.0
        cluster *= fx.env_swell(n, rate, seconds * 0.95, 2.2, 0.04)
        x = np.zeros(n)
        core.mix_into(x, 0, _norm(roar), 0.9)
        core.mix_into(x, fx.frames(0.42, rate), _norm(drum), 1.0)
        x = x + 0.4 * _norm(rise_band) + 0.25 * cluster
    elif part == "on":
        shim = ins.fm(n, rate, 880.0 * (1.0 + 0.2 * t / seconds), 2.0, 2.5) * fx.env_ad(n, rate, 0.01, seconds * 0.4)
        pulse = ins.thump(n, rate, 90.0, 55.0, 0.03, 0.1, 0.002, 0.2, 0.6)
        sweep = ins.whoosh(rng, seconds, 600.0, 4000.0, 0.25, 2.0, 1.4)
        x = 0.5 * shim + 0.8 * pulse + 0.5 * _norm(sweep)
    else:
        fall = ins.fm(n, rate, 700.0 * (1.0 - 0.5 * t / seconds), 2.0, 1.5) * fx.env_ad(n, rate, 0.01, seconds * 0.35)
        sweep = ins.whoosh(rng, seconds, 2500.0, 600.0, 0.2, 2.0, 1.2)
        x = 0.6 * fall + 0.5 * _norm(sweep)
    return fx.finish(fx.soft_clip(x, 1.5), rate, fade_in_s=0.005)


def throw_cast(rng, rate, variant, seconds):
    """The heave before a throw: a deep drawn-back whoosh and cloth."""
    n = fx.frames(seconds, rate)
    w = ins.whoosh(rng, seconds, 90.0, 400.0, 0.75, 0.85, 1.8)
    cloth = ins.whoosh(rng, seconds, 900.0, 2600.0, 0.6, 2.0, 1.5)
    return fx.finish(_norm(w) + 0.25 * _norm(cloth), rate, fade_in_s=0.01)


def body_impact(rng, rate, variant, seconds):
    """A thrown body (or a held one slammed down) hitting the ground hard."""
    n = fx.frames(seconds, rate)
    flesh = ins.impact_flesh(rng, seconds, 1.0, rate)
    ground = ins.thump(n, rate, 85.0, 40.0, 0.03, 0.12, 0.002, 0.2, 0.8)
    gear = ins.crackle(rng, n, rate, 0.01, 0.12, 220.0, 1500.0, 5000.0)
    dirt = ins.crunch(rng, n, rate, 0.0, 0.15, 1200.0, 300.0, 2500.0)
    x = 0.8 * flesh + 0.8 * ground + 0.15 * _norm(gear) + 0.35 * _norm(dirt)
    return fx.finish(fx.soft_clip(x, 1.6), rate)


def bow(rng, rate, variant, seconds):
    """An archer's bow released: a plucked string twang, its slap on the bracer and the limbs."""
    n = fx.frames(seconds, rate)
    f0 = (150.0, 168.0)[variant] * rng.uniform(0.97, 1.03)
    string = ins.pluck(rng, n, rate, f0, 0.05, 20, 0.35, 0.15)
    snap = ins.burst(rng, n, rate, 1500.0, 5000.0, 0.0002, 0.004)
    slap = ins.burst(rng, n, rate, 600.0, 3000.0, 0.0003, 0.012, "pink")
    limbs = fx.modal_ir([rng.uniform(560, 680), rng.uniform(1300, 1600), rng.uniform(2400, 2900)], [0.03, 0.018, 0.01],
                        [1.0, 0.6, 0.35], n, rate)
    x = _norm(string) + 0.6 * snap + 0.45 * slap + 0.4 * _norm(limbs)
    return fx.finish(x, rate)


def barrier(rng, rate, variant, seconds):
    """A mage's barrier rising round an ally: a glassy FM shimmer swelling up."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    glass = ins.fm(n, rate, 1320.0 * (1.0 + 0.15 * t / seconds), 1.5, 1.2 + 1.5 * t / seconds)
    glass = fx.tremolo(glass, 9.0, 0.5, rate)
    hum = core.sine(220.0, n, rate) + 0.5 * core.sine(330.0, n, rate)
    env = fx.env_points([(0.0, 0.0), (seconds * 0.5, 1.0), (seconds * 0.8, 0.8), (seconds, 0.0)], n, rate)
    return fx.finish((0.6 * glass + 0.4 * hum) * env, rate, fade_in_s=0.01)


# --------------------------------------------------------------------------- projectiles and their landings


def launch(rng, rate, variant, seconds, kind):
    """Something leaving a hand or a bow: an arrow's thin 'fwip', a bolt's zap, a boulder's heavy
    tumbling rush, a body's flailing whoosh."""
    n = fx.frames(seconds, rate)
    if kind == "arrow":
        x = ins.whoosh(rng, seconds, 1800.0, 6000.0, 0.25, 2.5, 1.2, fall_tau=seconds * 0.3, color="white")
    elif kind == "bolt":
        zap = ins.fm(n, rate, np.linspace(1400.0, 500.0, n), 1.5, 3.0) * fx.env_ad(n, rate, 0.002, 0.06)
        w = ins.whoosh(rng, seconds, 600.0, 2600.0, 0.3, 1.8, 1.3)
        x = 0.6 * zap + _norm(w)
    elif kind == "boulder":
        w = ins.whoosh(rng, seconds, 70.0, 380.0, 0.4, 0.8, 1.4, color="brown")
        x = fx.tremolo(_norm(w), rng.uniform(6.0, 9.0), 0.45, rate)
    else:
        w = ins.whoosh(rng, seconds, 180.0, 900.0, 0.4, 1.0, 1.4)
        x = fx.tremolo(_norm(w), rng.uniform(7.0, 10.0), 0.5, rate)
    return fx.finish(x, rate, fade_in_s=0.004)


def land(rng, rate, variant, seconds, kind):
    """A projectile landing on the ground: an arrow's woody thock, a bolt's fizzling zap, a
    boulder's spray of soil and rolling rubble."""
    n = fx.frames(seconds, rate)
    if kind == "arrow":
        thock = fx.modal_ir([rng.uniform(800, 1000), rng.uniform(1900, 2300)], [0.012, 0.006], [1.0, 0.5], n, rate)
        dirt = ins.crunch(rng, n, rate, 0.0, 0.04, 900.0, 600.0, 3500.0)
        quiver = core.sine(rng.uniform(150.0, 190.0), n, rate) * fx.env_ad(n, rate, 0.003, 0.05) * fx.tremolo(np.ones(n), 25.0, 0.8, rate)
        x = _norm(thock) + 0.4 * _norm(dirt) + 0.25 * quiver
    elif kind == "bolt":
        zap = ins.fm(n, rate, np.linspace(900.0, 200.0, n), 2.1, 4.0) * fx.env_ad(n, rate, 0.002, 0.08)
        crk = ins.crackle(rng, n, rate, 0.0, seconds * 0.6, 500.0, 2000.0, 7000.0)
        x = 0.7 * zap + 0.4 * _norm(crk) * fx.env_ad(n, rate, 0.002, seconds * 0.3)
    else:
        spray = ins.crunch(rng, n, rate, 0.0, 0.2, 1500.0, 250.0, 3000.0)
        rubble = ins.debris(rng, n, rate, 0.06, seconds * 0.7, 18, "stone", 1.2)
        x = 0.8 * _norm(spray) + 0.5 * _norm(rubble)
    return fx.finish(x, rate)


# --------------------------------------------------------------------------- statuses and grabs


def slow(rng, rate, variant, seconds):
    """The giant slowed: a sinking, viscous drag (a falling tone with a heavy wobble)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    sink = ins.fm(n, rate, 420.0 * (0.4 ** (t / seconds)), 0.5, 2.0) * fx.env_ad(n, rate, 0.01, seconds * 0.45)
    goo = ins.burst(rng, n, rate, 150.0, 900.0, 0.01, seconds * 0.4, "pink")
    x = fx.tremolo(0.7 * sink + 0.4 * goo, 6.0, 0.5, rate)
    return fx.finish(x, rate)


def grab(rng, rate, variant, seconds, part):
    """Grabs: seizing (a quick whoosh and a firm thud on a body), throwing (a release whoosh),
    dropping (a release and a light thud), crushing (a muffled squeeze and crunching)."""
    n = fx.frames(seconds, rate)
    if part == "seize":
        w = ins.whoosh(rng, seconds, 250.0, 1100.0, 0.35, 1.0, 1.5)
        hold = np.zeros(n)
        core.mix_into(hold, fx.frames(seconds * 0.4, rate), ins.impact_flesh(rng, seconds * 0.6, 0.4, rate))
        x = 0.6 * _norm(w) + 0.9 * hold
    elif part == "throw":
        x = _norm(ins.whoosh(rng, seconds, 150.0, 1000.0, 0.3, 0.9, 1.3))
    elif part == "drop":
        rel = ins.whoosh(rng, seconds, 300.0, 900.0, 0.2, 1.0, 1.2)
        thud = np.zeros(n)
        core.mix_into(thud, fx.frames(seconds * 0.45, rate), ins.thump(n, rate, 110.0, 70.0, 0.015, 0.04, 0.002, 0.2, 0.7))
        x = 0.5 * _norm(rel) + 0.9 * thud
    else:
        squeeze = ins.impact_flesh(rng, seconds, 0.8, rate) * fx.env_swell(n, rate, 0.05, 1.0, seconds * 0.3)
        crunch = ins.crunch(rng, n, rate, 0.04, seconds * 0.5, 900.0, 500.0, 2500.0, (0.004, 0.015))
        x = 0.8 * _norm(squeeze) + 0.6 * _norm(crunch)
    return fx.finish(fx.soft_clip(x, 1.4), rate)


V = ins.variant_cues
CUES = (
    V(FAMILY, "stomp", stomp, 211001, 2, {"seconds": 0.92})
    + V(FAMILY, "stomp_far", stomp_far, 211005, 1, {"seconds": 0.7})
    + V(FAMILY, "footfall_cast", footfall_cast, 211003, 1, {"seconds": 0.35})
    + V(FAMILY, "sweep", sweep, 211011, 1, {"seconds": 0.6})
    + V(FAMILY, "sweep_cast", windup, 211012, 1, {"seconds": 0.3, "lo": 120.0, "hi": 500.0})
    + V(FAMILY, "stone_skin_cast", stone_skin, 211021, 1, {"seconds": 0.5, "part": "cast"})
    + V(FAMILY, "stone_skin_on", stone_skin, 211022, 1, {"seconds": 0.4, "part": "on"})
    + V(FAMILY, "stone_skin_off", stone_skin, 211023, 1, {"seconds": 0.4, "part": "off"})
    + V(FAMILY, "grip_cast", grip_cast, 211031, 1, {"seconds": 0.35})
    + V(FAMILY, "hurl_cast", hurl_cast, 211041, 1, {"seconds": 0.6})
    + V(FAMILY, "hurl_impact", boulder_impact, 211042, 1, {"seconds": 0.8})
    + V(FAMILY, "runic_cast", arcane, 211051, 1, {"seconds": 0.45, "f_lo": 220.0, "f_hi": 660.0})
    + V(FAMILY, "mend_cast", mend, 211061, 1, {"seconds": 0.35, "part": "cast"})
    + V(FAMILY, "mend_on", mend, 211062, 1, {"seconds": 0.8, "part": "on"})
    + V(FAMILY, "mend_off", mend, 211063, 1, {"seconds": 0.35, "part": "off"})
    + V(FAMILY, "roar_cast", roar_cast, 211071, 1, {"seconds": 0.35})
    + V(FAMILY, "roar", giant_roar, 211072, 1, {"seconds": 1.15})
    + V(FAMILY, "roar_thunder", thunder, 211073, 1, {"seconds": 1.1})
    + V(FAMILY, "surge_cast", surge, 211081, 1, {"seconds": 1.15, "part": "cast"})
    + V(FAMILY, "surge_on", surge, 211082, 1, {"seconds": 0.7, "part": "on"})
    + V(FAMILY, "surge_off", surge, 211083, 1, {"seconds": 0.5, "part": "off"})
    + V(FAMILY, "throw_cast", throw_cast, 211091, 1, {"seconds": 0.4})
    + V(FAMILY, "throw_impact", body_impact, 211092, 1, {"seconds": 0.55})
    + V(FAMILY, "bow", bow, 211101, 2, {"seconds": 0.32})
    + V(FAMILY, "barrier_on", barrier, 211111, 1, {"seconds": 0.55})
    + V(FAMILY, "launch_arrow", launch, 211121, 1, {"seconds": 0.25, "kind": "arrow"})
    + V(FAMILY, "launch_bolt", launch, 211122, 1, {"seconds": 0.35, "kind": "bolt"})
    + V(FAMILY, "launch_boulder", launch, 211123, 1, {"seconds": 0.5, "kind": "boulder"})
    + V(FAMILY, "launch_body", launch, 211124, 1, {"seconds": 0.45, "kind": "body"})
    + V(FAMILY, "land_arrow", land, 211131, 2, {"seconds": 0.2, "kind": "arrow"})
    + V(FAMILY, "land_bolt", land, 211133, 1, {"seconds": 0.35, "kind": "bolt"})
    + V(FAMILY, "land_boulder", land, 211134, 1, {"seconds": 0.45, "kind": "boulder"})
    + V(FAMILY, "slow", slow, 211141, 1, {"seconds": 0.45})
    + V(FAMILY, "grab_seize", grab, 211151, 1, {"seconds": 0.35, "part": "seize"})
    + V(FAMILY, "grab_throw", grab, 211152, 1, {"seconds": 0.4, "part": "throw"})
    + V(FAMILY, "grab_drop", grab, 211153, 1, {"seconds": 0.35, "part": "drop"})
    + V(FAMILY, "grab_crush", grab, 211154, 1, {"seconds": 0.5, "part": "crush"})
)
