"""Threat cues (P21; plan M6-M9 decision 7, section 4.1 family F, section 4.2): bank_threat.json:
sfx.threat.windup.<line|circle|cone>, sfx.threat.sting, sfx.threat.aim_lock.

Built for localisation and kept apart from everything else: broadband (energy from 2 to 8 kHz,
where level differences between the ears are largest), a short tick at the start, a band-pass
sweep that RISES (2 -> 8 kHz) so the cue swells towards its end - impacts do the opposite,
peaking at once and decaying - and 0.2-0.6 s long. A test compares their spectral centroids and
onset times with the impact family's.

* windup.line: a rushing sweep (a charge or a thrust along a line)
* windup.circle: a swelling rumble under the rising sweep (a slam or a stomp around the attacker)
* windup.cone: a swish (a sweeping blow over an arc)
* sting: the short off-camera alert: a broadband transient, then a fast rising sweep and a bright
  glissando - played at the attacker when it is outside the camera's view or far away
* aim_lock: a two-tone tick (a ranged attacker has committed its aim)

The formation wall and the incoming whistle are world cues (P28). Every sound is original and
synthesized here. Seeds 214001-214099.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins

FAMILY = "threat"


def _norm(x):
    return np.asarray(x) / max(core.peak(x), 1e-9)


def _tick(rng, n, rate, level=0.35):
    """The short broadband tick that opens every threat cue (a sharp localisable edge)."""
    t = ins.burst(rng, n, rate, 2000.0, 9500.0, 0.0002, 0.0025, "white")
    return level * _norm(t)


def _rise(rng, n, rate, seconds, lo, hi, q, peak_at, rise_pow):
    """A band-pass sweep rising from lo to hi Hz under a swell that peaks at peak_at x seconds."""
    src = fx.noise(n, rng, 0.0, 0.0, rate, "white")
    y = fx.swept_band(src, [(0.0, lo), (seconds * peak_at, hi), (seconds, hi * 1.08)],
                      [(0.0, q), (seconds, q * 1.3)], rate, 512, 0.02)
    return _norm(y) * fx.env_swell(n, rate, seconds * peak_at, rise_pow, seconds * 0.08)


def windup(rng, rate, variant, seconds, shape):
    """A windup aimed at the giant, by the telegraph's shape."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    if shape == "line":
        rise = _rise(rng, n, rate, seconds, 1600.0, 7200.0, 2.2, 0.82, 2.4)
        glide = core.sine(900.0 * (2.6 ** np.clip(t / seconds, 0.0, 1.0)), n, rate) * fx.env_swell(n, rate, seconds * 0.82, 2.4, 0.03)
        x = rise + 0.2 * glide
    elif shape == "circle":
        rise = _rise(rng, n, rate, seconds, 2000.0, 6500.0, 2.0, 0.85, 2.0)
        swell = fx.noise(n, rng, 50.0, 260.0, rate, "brown") * fx.env_swell(n, rate, seconds * 0.85, 1.6, 0.05)
        x = 0.8 * rise + 0.7 * _norm(swell)
    else:   # cone: a swish across the arc
        rise = _rise(rng, n, rate, seconds, 1200.0, 5600.0, 1.6, 0.75, 1.8)
        swish = ins.whoosh(rng, seconds, 1500.0, 6000.0, 0.75, 1.4, 1.8, color="white")
        x = 0.75 * rise + 0.5 * _norm(swish)
    x = x + _tick(rng, n, rate)
    return fx.finish(x, rate, fade_in_s=0.0)


def sting(rng, rate, variant, seconds):
    """The off-camera threat sting: a broadband hit of noise, a fast rising sweep and a bright
    rising glissando (a 'shing' that says: something is coming from there)."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    hit = ins.burst(rng, n, rate, 1000.0, 9500.0, 0.0003, 0.014, "white")
    rise = _rise(rng, n, rate, seconds, 2000.0, 8200.0, 3.0, 0.6, 1.6)
    f = (1600.0, 1800.0)[variant] * (2.5 ** np.clip(t / (seconds * 0.6), 0.0, 1.0))
    gliss = (core.sine(f, n, rate) + 0.4 * core.sine(f * 1.5, n, rate)) * fx.env_swell(n, rate, seconds * 0.6, 1.4, 0.04)
    x = 0.55 * _norm(hit) + rise + 0.3 * _norm(gliss)
    return fx.finish(x, rate, fade_in_s=0.0)


def aim_lock(rng, rate, variant, seconds):
    """A ranged attacker's aim committed: a two-tone mechanical tick (the second higher, louder
    and ringing a little longer: the lock), with a faint ratchet between them."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    for at, f, g, tau in ((0.0, 2600.0, 0.6, 0.018), (0.07, 3900.0, 1.0, 0.03)):
        m = n - fx.frames(at, rate)
        tone = (core.sine(f, m, rate) + 0.3 * core.sine(f * 2.01, m, rate)) * fx.env_ad(m, rate, 0.0008, tau)
        clk = ins.burst(rng, m, rate, 2500.0, 9500.0, 0.0001, 0.0015, "white")
        core.mix_into(x, fx.frames(at, rate), tone + 0.6 * _norm(clk) * 0.5, g)
    ratchet = ins.crackle(rng, n, rate, 0.012, 0.05, 300.0, 3000.0, 8000.0)
    x = x + 0.12 * _norm(ratchet)
    return fx.finish(x, rate, fade_in_s=0.0)


V = ins.variant_cues
CUES = (
    V(FAMILY, "windup_line", windup, 214001, 2, {"seconds": 0.4, "shape": "line"})
    + V(FAMILY, "windup_circle", windup, 214011, 2, {"seconds": 0.45, "shape": "circle"})
    + V(FAMILY, "windup_cone", windup, 214021, 2, {"seconds": 0.34, "shape": "cone"})
    + V(FAMILY, "sting", sting, 214031, 2, {"seconds": 0.3})
    + V(FAMILY, "aim_lock", aim_lock, 214041, 1, {"seconds": 0.26})
)
