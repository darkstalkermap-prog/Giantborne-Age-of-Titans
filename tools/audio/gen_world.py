"""World objects (P21; plan M6-M9 section 4.1 family G, section 4.2): bank_world.json:
sfx.crack.<material>, sfx.break.<material>.<small|large>, sfx.world.open.<material>,
sfx.world.<shrine_wake|shrine_rest|waystone|growth|forge_upgrade|gate_iron|alarm_bell>,
sfx.world.interact.<kind>.

Impacts and creaks combined: wood splinters (clouds of small modal grains) and timber crashes,
stone cracks and collapses with tumbling rubble, gate creaks (stick-slip pulses and a slowly swept
resonance), stone grinding, shrine chimes (additive inharmonic bells over a low hum), forge strikes
and a quench, the iron gate of the Ogre King's arena, Thornwick's alarm bell, and the giant's
growth (creaking like old timber, under a rising rumble). Every sound is original and synthesized
here. Seeds 215001-215199.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins

FAMILY = "world"


def _norm(x):
    return np.asarray(x) / max(core.peak(x), 1e-9)


# --------------------------------------------------------------------------- cracks and breaks


def crack(rng, rate, variant, seconds, material):
    """A structure cracking (a damage stage): wood splits with a groan; stone cracks and grinds."""
    n = fx.frames(seconds, rate)
    if material == "wood":
        snap = ins.burst(rng, n, rate, 800.0, 7000.0, 0.0003, 0.006)
        spl = ins.splinter(rng, n, rate, 0.0, 0.12, 1400.0, 1.4)
        groan = ins.creak(rng, seconds, [(0.0, 35.0), (seconds, 22.0)], rate, grip_points=[(0.0, 1.0), (seconds * 0.6, 0.5), (seconds, 0.0)])
        thud = ins.thump(n, rate, 140.0, 90.0, 0.02, 0.06, 0.002, 0.2, 0.6)
        x = 0.6 * snap + 0.7 * _norm(spl) + 0.35 * _norm(groan) * fx.env_ad(n, rate, 0.02, seconds * 0.35) + 0.5 * thud
    else:
        snap = ins.impact_stone(rng, seconds, 0.7, rate)
        grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.03, 1.0), (0.25, 0.3), (seconds, 0.0)], n, rate),
                          600.0, 250.0, 2500.0)
        crumbs = ins.debris(rng, n, rate, 0.05, seconds * 0.6, 16, "stone", 0.8)
        x = 0.9 * snap + 0.5 * _norm(grind) + 0.4 * _norm(crumbs)
    return fx.finish(fx.soft_clip(x, 1.4), rate)


def break_(rng, rate, variant, seconds, material, size):
    """Something destroyed: a fence or a crate smashed (wood, small); a gate, a barricade, a tree
    or the deadfall crashing down (wood, large); a cairn or a fortified gate collapsing (stone)."""
    n = fx.frames(seconds, rate)
    big = size == "large"
    if material == "wood":
        hit = ins.impact_wood(rng, min(seconds, 0.5), 1.0 if big else 0.6, rate, rng.uniform(110.0, 140.0) if big else None)
        spl = ins.splinter(rng, n, rate, 0.0, 0.25 if big else 0.14, 1600.0 if big else 1200.0, 1.6 if big else 1.0)
        bits = ins.debris(rng, n, rate, 0.08, seconds * 0.7, 30 if big else 14, "wood", 1.4 if big else 1.0)
        x = 0.9 * fx.fit(hit, n) + 0.8 * _norm(spl) + 0.45 * _norm(bits)
        if big:
            fall = np.zeros(n)
            core.mix_into(fall, fx.frames(0.35, rate), ins.thump(n, rate, 72.0, 36.0, 0.04, 0.2, 0.004, 0.25, 0.8))
            groan = ins.creak(rng, 0.4, [(0.0, 30.0), (0.4, 18.0)], rate, grip_points=[(0.0, 1.0), (0.4, 0.2)])
            core.mix_into(fall, fx.frames(0.05, rate), 0.4 * _norm(groan))
            x = x + 0.9 * fall
    else:
        hit = ins.impact_stone(rng, min(seconds, 0.5), 1.0, rate)
        boom = ins.thump(n, rate, 70.0, 32.0, 0.04, 0.22, 0.004, 0.25, 0.8)
        rubble = ins.debris(rng, n, rate, 0.06, seconds * 0.75, 40, "stone", 1.6)
        rum = ins.rumble(rng, n, rate, 260.0, 0.02, seconds * 0.3, 7.0, 0.4)
        x = 0.9 * fx.fit(hit, n) + 0.9 * boom + 0.55 * _norm(rubble) + 0.45 * _norm(rum)
    x = fx.soft_clip(x, 1.6)
    if big:
        x = fx.fit(fx.valley_echo(x, rng, rate, 0.31, 0.2, 750.0, 2), n)
    return fx.finish(x, rate)


def crash_far(rng, rate, variant, seconds):
    """A big crash heard from far off (a gate, a tree, a cairn or the arena's iron gate): the
    boom and the rumble of the fall, its splinters and ring lost on the way."""
    x = break_(rng, rate, 0, seconds, "wood", "large")
    return fx.finish(fx.distant(x, rng, rate, 520.0, 0.03, 0.2), rate)


def open_(rng, rate, variant, seconds, material):
    """A gate or a door opening: a wooden gate's latch, long creak and bump; a stone door's heavy
    grinding and its thud."""
    n = fx.frames(seconds, rate)
    if material == "wood":
        latch = ins.impact_wood(rng, 0.2, 0.2, rate, rng.uniform(380.0, 450.0))
        creak = ins.creak(rng, seconds, [(0.0, 38.0), (seconds * 0.5, 55.0), (seconds, 30.0)], rate,
                          sweep_points=[(0.0, 520.0), (seconds * 0.6, 780.0), (seconds, 600.0)], sweep_q=7.0,
                          noise_level=0.4, grip_points=[(0.0, 0.3), (0.1, 0.95), (seconds * 0.8, 0.7), (seconds, 0.1)])
        bump = np.zeros(n)
        core.mix_into(bump, fx.frames(seconds - 0.18, rate), ins.thump(n, rate, 130.0, 90.0, 0.02, 0.04, 0.002, 0.2, 0.6))
        x = 0.7 * fx.fit(latch, n) + 0.6 * _norm(creak) * fx.env_points([(0.0, 0.0), (0.08, 1.0), (seconds * 0.85, 0.8), (seconds, 0.0)], n, rate) + 0.6 * bump
    else:
        env = fx.env_points([(0.0, 0.0), (0.1, 1.0), (seconds * 0.8, 0.8), (seconds, 0.0)], n, rate)
        grind = ins.grind(rng, n, rate, env, 700.0, 150.0, 1800.0)
        rum = ins.rumble(rng, n, rate, 140.0, 0.1, seconds * 0.6, 4.0, 0.3)
        thud = np.zeros(n)
        core.mix_into(thud, fx.frames(seconds - 0.25, rate), ins.thump(n, rate, 90.0, 45.0, 0.03, 0.12, 0.003, 0.25, 0.8))
        x = 0.7 * _norm(grind) + 0.5 * _norm(rum) * env + 0.8 * thud
    return fx.finish(x, rate, fade_in_s=0.003)


# --------------------------------------------------------------------------- shrines, waystones, growth


def shrine(rng, rate, variant, seconds, part):
    """A shrine awakening (a rising shimmer, an ancient bell chord, a low hum swelling) or a rest
    (a soft warm chord breathing out)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    if part == "wake":
        hum = (core.sine(110.0, n, rate) + 0.6 * core.sine(165.0, n, rate) + 0.3 * core.sine(220.5, n, rate))
        hum *= fx.env_points([(0.0, 0.0), (0.3, 0.8), (seconds * 0.7, 0.6), (seconds, 0.0)], n, rate)
        chord = np.zeros(n)
        for k, f in enumerate((293.7, 440.0, 587.3)):   # D, A, D: an open fifth
            core.mix_into(chord, fx.frames(0.12 + 0.11 * k, rate), _norm(ins.bell(rng, n, rate, f * 1.78, 0.9, strike=0.2)), (1.0, 0.75, 0.6)[k])
        shimmer = ins.whoosh(rng, seconds * 0.6, 1500.0, 7000.0, 0.9, 2.5, 2.0, color="white")
        x = 0.35 * hum + 0.8 * _norm(chord) + 0.3 * fx.fit(_norm(shimmer), n)
    else:
        chord = np.zeros(n)
        for k, f in enumerate((220.0, 277.2, 329.6)):
            core.mix_into(chord, fx.frames(0.05 * k, rate), _norm(ins.bell(rng, n, rate, f * 1.78, 0.8, strike=0.05)), 1.0)
        air = ins.whoosh(rng, seconds, 600.0, 200.0, 0.2, 1.0, 1.0)
        x = 0.8 * _norm(chord) * fx.env_ad(n, rate, 0.05, seconds * 0.45) + 0.25 * _norm(air)
    return fx.finish(x, rate, fade_in_s=0.01)


def waystone(rng, rate, variant, seconds):
    """A waystone recognising the giant: a deep stone hum, a bright bell tick, a soft shimmer."""
    n = fx.frames(seconds, rate)
    hum = (core.sine(98.0, n, rate) + 0.5 * core.sine(147.0, n, rate) + 0.25 * core.sine(196.0, n, rate))
    hum = fx.tremolo(hum, 3.0, 0.25, rate) * fx.env_points([(0.0, 0.0), (0.15, 1.0), (seconds * 0.6, 0.7), (seconds, 0.0)], n, rate)
    tick = ins.bell(rng, n, rate, 1320.0, 0.35, strike=0.3)
    stone = ins.impact_stone(rng, 0.25, 0.3, rate)
    x = 0.55 * hum + 0.5 * _norm(tick) + 0.35 * fx.fit(stone, n)
    return fx.finish(x, rate, fade_in_s=0.003)


def growth(rng, rate, variant, seconds):
    """The giant growing: bones and sinews creaking like old timber, a rising rumble and a deep
    swell of breath and earth."""
    n = fx.frames(seconds, rate)
    creaks = np.zeros(n)
    for k in range(4):
        dur = rng.uniform(0.25, 0.45)
        c = ins.creak(rng, dur, [(0.0, rng.uniform(18.0, 26.0)), (dur, rng.uniform(28.0, 40.0))], rate,
                      body=(160.0, 290.0, 470.0, 720.0, 1100.0), grip_points=[(0.0, 0.4), (dur * 0.5, 1.0), (dur, 0.2)])
        core.mix_into(creaks, fx.frames(0.1 + k * rng.uniform(0.28, 0.36), rate), _norm(c) * np.hanning(c.shape[0]), rng.uniform(0.6, 1.0))
    rum = ins.rumble(rng, n, rate, 180.0, seconds * 0.6, seconds * 0.3, 5.0, 0.3)
    swell = fx.noise(n, rng, 40.0, 400.0, rate, "brown") * fx.env_swell(n, rate, seconds * 0.75, 2.0, 0.15)
    thump = np.zeros(n)
    core.mix_into(thump, fx.frames(seconds * 0.75, rate), ins.thump(n, rate, 70.0, 34.0, 0.04, 0.18, 0.004, 0.25, 0.8))
    x = 0.9 * _norm(creaks) + 0.45 * _norm(rum) + 0.35 * _norm(swell) + 0.7 * thump
    return fx.finish(fx.soft_clip(x, 1.4), rate, fade_in_s=0.02)


# --------------------------------------------------------------------------- iron and bells


def anvil(rng, rate, n, at, weight=0.5):
    """One hammer blow on an anvil (iron ring and a solid clunk), placed at `at` seconds."""
    out = np.zeros(n)
    m = n - fx.frames(at, rate)
    if m > 8:
        core.mix_into(out, fx.frames(at, rate), ins.impact_iron(rng, m / rate, weight, rate, ring_s=0.35, low=1400.0, high=5000.0))
    return out


def forge(rng, rate, variant, seconds, part):
    """The forge: a strike on the anvil over the fire's breath (interacting), or three strikes and
    a hissing quench (an upgrade)."""
    n = fx.frames(seconds, rate)
    fire = fx.noise(n, rng, 80.0, 900.0, rate, "pink")
    fire = fx.tremolo(fire, 7.0, 0.5, rate) * fx.env_points([(0.0, 0.0), (0.1, 0.6), (seconds, 0.0)], n, rate)
    if part == "interact":
        x = _norm(anvil(rng, rate, n, 0.0, 0.4)) + 0.4 * _norm(fire)
    else:
        strikes = anvil(rng, rate, n, 0.0, 0.5) + 0.8 * anvil(rng, rate, n, 0.26, 0.5) + 1.1 * anvil(rng, rate, n, 0.5, 0.8)
        hiss = fx.noise(n, rng, 2500.0, 9000.0, rate) * fx.env_points([(0.0, 0.0), (0.72, 0.0), (0.78, 1.0), (seconds, 0.0)], n, rate)
        x = _norm(strikes) + 0.35 * _norm(hiss) + 0.25 * _norm(fire)
    return fx.finish(x, rate)


def gate_iron(rng, rate, variant, seconds):
    """The arena's iron gate: a portcullis slamming down, chains rattling, a boom and its echo."""
    n = fx.frames(seconds, rate)
    slam = ins.impact_iron(rng, seconds, 1.0, rate, ring_s=0.4, low=600.0, high=3500.0)
    boom = ins.thump(n, rate, 75.0, 34.0, 0.04, 0.2, 0.003, 0.25, 0.8)
    times = sorted(rng.uniform(0.0, 0.35, 14))
    chain = fx.scatter(n, rng, times, lambda i: ins.ring(rng, fx.frames(0.05, rate), rate,
                                                         ins.metal_partials(rng, 1500.0, 5000.0, 3), 0.025, 0.01),
                       rng.uniform(0.2, 0.7, 14), rate)
    grind = ins.grind(rng, n, rate, fx.env_points([(0.0, 1.0), (0.12, 0.0), (seconds, 0.0)], n, rate), 500.0, 300.0, 2500.0)
    x = 0.9 * _norm(slam) + 0.9 * boom + 0.3 * _norm(chain) + 0.3 * _norm(grind)
    x = fx.fit(fx.valley_echo(fx.soft_clip(x, 1.5), rng, rate, 0.28, 0.25, 900.0, 2), n)
    return fx.finish(x, rate)


def alarm_bell(rng, rate, variant, seconds):
    """Thornwick's alarm bell rung hard, three quick strokes."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    for k, at in enumerate((0.0, 0.38, 0.76)):
        b = ins.bell(rng, n, rate, 640.0 * rng.uniform(0.995, 1.005), 1.4, strike=0.5)
        core.mix_into(x, fx.frames(at, rate), _norm(b), (1.0, 0.9, 0.95)[k])
    return fx.finish(x, rate)


# --------------------------------------------------------------------------- interactions


def interact(rng, rate, variant, seconds, kind):
    """Using things: picking something up, taking a weapon from a rack, uprooting a tree, turning
    to talk (the forge has its own)."""
    n = fx.frames(seconds, rate)
    if kind == "pickup":
        rustle = ins.crunch(rng, n, rate, 0.0, 0.08, 900.0, 1200.0, 6000.0, (0.002, 0.006))
        clink = ins.ring(rng, n, rate, ins.metal_partials(rng, 2200.0, 5000.0, 3), 0.06, 0.02)
        x = 0.6 * _norm(rustle) + 0.25 * clink * fx.env_ad(n, rate, 0.04, 0.05)
    elif kind == "weapon":
        clatter = sum(fx.fit(np.concatenate([np.zeros(fx.frames(at, rate)), ins.impact_wood(rng, 0.2, 0.3, rate)]), n)
                      for at in (0.0, 0.09, 0.2))
        scrape = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.05, 1.0), (0.3, 0.0)], n, rate), 700.0, 600.0, 3500.0)
        x = 0.8 * _norm(clatter) + 0.35 * _norm(scrape)
    elif kind == "uproot":
        tear = np.zeros(n)
        for k in range(5):
            core.mix_into(tear, fx.frames(0.05 + 0.16 * k + rng.uniform(-0.03, 0.03), rate),
                          ins.splinter(rng, fx.frames(0.25, rate), rate, 0.0, 0.08, 900.0, 1.8), rng.uniform(0.5, 1.0))
        roots = ins.creak(rng, seconds, [(0.0, 20.0), (seconds, 34.0)], rate, body=(110.0, 210.0, 340.0, 520.0, 800.0),
                          grip_points=[(0.0, 1.0), (seconds * 0.8, 0.6), (seconds, 0.0)])
        earth = ins.debris(rng, n, rate, 0.2, seconds * 0.7, 30, "dirt", 1.6)
        rum = ins.rumble(rng, n, rate, 200.0, 0.2, seconds * 0.4)
        x = 0.7 * _norm(tear) + 0.45 * _norm(roots) + 0.45 * _norm(earth) + 0.5 * _norm(rum)
    else:   # talk: the giant turning and settling down to listen
        x = ins.whoosh(rng, seconds, 300.0, 900.0, 0.4, 1.0, 1.4) + 0.3 * ins.crunch(rng, n, rate, 0.05, 0.1, 500.0, 400.0, 2000.0)
    return fx.finish(fx.soft_clip(x, 1.3), rate, fade_in_s=0.003)


V = ins.variant_cues
CUES = (
    V(FAMILY, "crack_wood", crack, 215001, 1, {"seconds": 0.55, "material": "wood"})
    + V(FAMILY, "crack_stone", crack, 215003, 1, {"seconds": 0.6, "material": "stone"})
    + V(FAMILY, "break_wood_small", break_, 215011, 2, {"seconds": 0.7, "material": "wood", "size": "small"})
    + V(FAMILY, "break_wood_large", break_, 215021, 1, {"seconds": 1.2, "material": "wood", "size": "large"})
    + V(FAMILY, "break_stone_large", break_, 215031, 1, {"seconds": 1.2, "material": "stone", "size": "large"})
    + V(FAMILY, "crash_far", crash_far, 215033, 1, {"seconds": 0.9})
    + V(FAMILY, "open_wood", open_, 215041, 1, {"seconds": 1.0, "material": "wood"})
    + V(FAMILY, "open_stone", open_, 215043, 1, {"seconds": 1.1, "material": "stone"})
    + V(FAMILY, "shrine_wake", shrine, 215051, 1, {"seconds": 1.3, "part": "wake"})
    + V(FAMILY, "shrine_rest", shrine, 215053, 1, {"seconds": 1.1, "part": "rest"})
    + V(FAMILY, "waystone", waystone, 215061, 1, {"seconds": 1.1})
    + V(FAMILY, "growth", growth, 215071, 1, {"seconds": 1.5})
    + V(FAMILY, "forge_strike", forge, 215081, 1, {"seconds": 0.6, "part": "interact"})
    + V(FAMILY, "forge_upgrade", forge, 215083, 1, {"seconds": 1.2, "part": "upgrade"})
    + V(FAMILY, "gate_iron", gate_iron, 215091, 1, {"seconds": 1.3})
    + V(FAMILY, "alarm_bell", alarm_bell, 215101, 1, {"seconds": 1.5})
    + V(FAMILY, "interact_pickup", interact, 215111, 1, {"seconds": 0.25, "kind": "pickup"})
    + V(FAMILY, "interact_weapon", interact, 215113, 1, {"seconds": 0.45, "kind": "weapon"})
    + V(FAMILY, "interact_uproot", interact, 215115, 1, {"seconds": 1.0, "kind": "uproot"})
    + V(FAMILY, "interact_talk", interact, 215117, 1, {"seconds": 0.2, "kind": "talk"})
)
