"""Instruments of the sound-effect families (P21; plan M6-M9 section 4.2): the physical-ish models
the generators (gen_combat, gen_abilities, gen_steps, gen_world, gen_ui, gen_threat) build their
cues from. Everything is vectorised (synth.fx) and draws its randomness from the cue's generator.

* thump: a sine whose pitch drops fast (the low body of every hit and footfall)
* impacts by material: wood (inharmonic bar partials 180-900 Hz, fast decay), iron (1.5-6 kHz
  plate partials, long ring; rendered at 32 kHz), stone (gritty low-mid noise, short stone
  modes, crumbs), flesh (a 60-120 Hz thump with a pitch drop under muffled noise and a slap),
  and armour (flesh with a short plate ring)
* whoosh: pink noise through a band-pass swept up to the swing's apex and back, with an
  asymmetric swell; blade rings, tree leaves
* footfalls: a sub thump scaled by the body's height, a surface layer (soft: granular crunch;
  hard: clicks and grit; wet: a squelch with bubbles; wade: a low slosh) and, for big giants, a
  debris tail of pebbles and earth (left out of the cruise variants)
* rumble, debris, splinters, creaks (stick-slip pulses through wood modes and a slowly swept
  resonance), stone grinding, crackle
* bells (inharmonic additive partials), FM tones, plucked strings, interface blips and buzzes
"""

from __future__ import annotations

import math

import numpy as np

from synth import core, fx

RATE = core.DEFAULT_RATE
METAL_RATE = 32000
TWO_PI = 2.0 * math.pi
SFX_ROOT = "res://assets/audio/sfx/"


def variant_cues(family: str, name: str, func, seed: int, count: int, params: dict | None = None,
                 rate: int = RATE, **extra) -> list:
    """count cue declarations of one sound (build_audio.py's CUES entries): <name>_<k>.wav under
    assets/audio/sfx/<family>/, seeds seed .. seed + count - 1. The render function gets the
    rate and the variant index (0-based) besides params, so variants can differ on purpose as
    well as by their seed."""
    out = []
    for i in range(count):
        p = dict(params or {})
        p["rate"] = rate
        p["variant"] = i
        out.append({"name": "%s_%d" % (name, i + 1), "path": "%s%s/%s_%d.wav" % (SFX_ROOT, family, name, i + 1),
                    "seed": seed + i, "func": func, "params": p, "kind": "sfx", "rate": rate, **extra})
    return out


# --------------------------------------------------------------------------- bodies


def thump(n: int, rate: int, f_start: float, f_end: float, drop_tau: float, amp_tau: float,
          attack_s: float = 0.002, harmonic: float = 0.15, overtones: float = 0.0) -> np.ndarray:
    """A sine (plus a little second harmonic) gliding from f_start to f_end with an exponential
    decay: the low body of a hit or a footfall. overtones (0..1) adds the third and fourth
    harmonics with a faster decay, so the weight still reads on small speakers that cannot play
    the fundamental."""
    f = fx.glide(n, rate, f_start, f_end, drop_tau)
    out = (core.sine(f, n, rate) + harmonic * core.sine(2.0 * f, n, rate)) * fx.env_ad(n, rate, attack_s, amp_tau)
    if overtones > 0.0:
        upper = 0.5 * core.sine(3.0 * f, n, rate) + 0.3 * core.sine(4.0 * f, n, rate)
        out = out + overtones * upper * fx.env_ad(n, rate, attack_s, amp_tau * 0.45)
    return out


def burst(rng: np.random.Generator, n: int, rate: int, lo: float, hi: float, attack_s: float,
          tau_s: float, color: str = "white") -> np.ndarray:
    """Band-limited noise under an attack-decay envelope."""
    return fx.noise(n, rng, lo, hi, rate, color) * fx.env_ad(n, rate, attack_s, tau_s)


def click(n: int, rate: int, at_s: float = 0.0, width_s: float = 0.0004) -> np.ndarray:
    """A very short raised-cosine pulse (the instant of contact)."""
    out = np.zeros(n)
    w = max(2, fx.frames(width_s, rate))
    start = fx.frames(at_s, rate) if at_s > 0 else 0
    pulse = np.hanning(w + 2)[1:-1]
    core.mix_into(out, start, pulse - float(np.mean(pulse)))
    return out


def rumble(rng: np.random.Generator, n: int, rate: int, cutoff: float, attack_s: float, tau_s: float,
           wobble_hz: float = 7.0, wobble: float = 0.35) -> np.ndarray:
    """Low-passed brown noise with a slow swell and a rolling amplitude wobble (earth, thunder)."""
    x = fx.noise(n, rng, 0.0, cutoff, rate, "brown")
    t = fx.t_axis(n, rate)
    roll = 1.0 - wobble * 0.5 * (1.0 + np.sin(TWO_PI * wobble_hz * t + rng.uniform(0, TWO_PI))
                                 * (0.6 + 0.4 * np.sin(TWO_PI * wobble_hz * 0.37 * t)))
    return x * fx.env_ad(n, rate, attack_s, tau_s, curve=0.7) * roll


# --------------------------------------------------------------------------- impacts by material


def impact_wood(rng: np.random.Generator, seconds: float, weight: float = 0.0, rate: int = RATE,
                f0: float | None = None) -> np.ndarray:
    """Wood struck: a click, a short noise excitation and free-bar partials (1, 2.76, 5.40,
    8.93) around 180-300 Hz plus two body modes, decaying fast; weight 0..1 lowers, lengthens
    and thickens it."""
    n = fx.frames(seconds, rate)
    base = f0 if f0 is not None else rng.uniform(190.0, 270.0) * (1.0 - 0.25 * weight)
    ratios = [1.0, 2.76, 5.40, 8.93, 13.34]
    freqs = list(fx.partials(base, ratios, rng, 0.04)) + list(rng.uniform(420.0, 900.0, 2))
    stretch = 1.0 + 0.5 * weight
    taus = np.array([0.04, 0.026, 0.018, 0.012, 0.008, 0.02, 0.015]) * stretch
    amps = np.array([1.0, 0.7, 0.45, 0.25, 0.12, 0.4, 0.3]) * rng.uniform(0.8, 1.2, 7)
    ir = fx.modal_ir(freqs, taus, amps, n, rate, rng.uniform(0, TWO_PI, 7))
    exc_n = fx.frames(0.004, rate)
    exc = fx.noise(exc_n, rng, 200.0, 5000.0, rate) * np.hanning(exc_n)
    exc[0] += 3.0
    tone = fx.excite(exc, ir, n)
    knock = thump(n, rate, 150.0 - 40 * weight, 85.0 - 20 * weight, 0.02, 0.03 + 0.03 * weight, 0.001, 0.2, 0.6)
    crack = burst(rng, n, rate, 1500.0, 7000.0, 0.0003, 0.004 + 0.002 * weight)
    body = burst(rng, n, rate, 300.0, 2200.0, 0.0006, 0.012 + 0.01 * weight, "pink")
    y = tone / max(core.peak(tone), 1e-9) + 0.5 * knock + 0.4 * crack + 0.45 * body
    return fx.soft_clip(y, 1.4 + weight)


def impact_stone(rng: np.random.Generator, seconds: float, weight: float = 0.0, rate: int = RATE) -> np.ndarray:
    """Stone struck: gritty low-mid noise, a few short stone modes, a low thud and crumbs."""
    n = fx.frames(seconds, rate)
    grit = burst(rng, n, rate, 180.0, 2600.0, 0.0006, 0.03 + 0.03 * weight)
    modes = rng.uniform([300, 520, 800, 1150, 1700], [420, 700, 1000, 1450, 2100]) * (1.0 - 0.2 * weight)
    ir = fx.modal_ir(modes, rng.uniform(0.008, 0.022, 5) * (1 + weight), [1, 0.8, 0.6, 0.45, 0.3], n, rate)
    exc = np.zeros(8)
    exc[0] = 1.0
    stone = fx.excite(exc, ir, n)
    thud = thump(n, rate, 130.0 - 30 * weight, 75.0, 0.02, 0.045 + 0.05 * weight, 0.0015)
    bank = fx.NoiseBank(rng, 0.5, rate, (1200.0, 2400.0, 4800.0))
    times = fx.poisson_times(rng, 0.002, 0.07 + 0.2 * weight, lambda t: 260.0 * math.exp(-t / 0.035))
    crumbs = fx.scatter(n, rng, times, lambda i: bank.grain(rng.uniform(1500, 5000), rng.uniform(0.002, 0.006)),
                        rng.uniform(0.15, 0.6, len(times)), rate)
    y = 0.9 * grit + 0.5 * stone / max(core.peak(stone), 1e-9) + 0.6 * thud + 0.5 * crumbs
    return fx.soft_clip(y, 1.6)


def metal_partials(rng: np.random.Generator, lo: float = 1500.0, hi: float = 6000.0, count: int = 8) -> np.ndarray:
    """Inharmonic plate partials spread between lo and hi Hz (log-spaced, jittered)."""
    edges = np.geomspace(lo, hi, count + 1)
    return np.array([rng.uniform(edges[i], edges[i + 1]) for i in range(count)])


def ring(rng: np.random.Generator, n: int, rate: int, freqs, tau_lo: float, tau_hi: float,
         bright: float = 0.6) -> np.ndarray:
    """Metal ringing: the partials decay from tau_lo (lowest) to tau_hi (highest)."""
    f = np.asarray(freqs, dtype=np.float64)
    order = np.argsort(f)
    taus = np.empty_like(f)
    taus[order] = np.geomspace(tau_lo, tau_hi, f.shape[0])
    amps = (f / f.min()) ** (-bright) * rng.uniform(0.6, 1.0, f.shape[0])
    ir = fx.modal_ir(f, taus, amps, n, rate, rng.uniform(0, TWO_PI, f.shape[0]))
    return ir / max(core.peak(ir), 1e-9)


def impact_iron(rng: np.random.Generator, seconds: float, weight: float = 0.0, rate: int = METAL_RATE,
                ring_s: float = 0.45, low: float = 1500.0, high: float = 6000.0) -> np.ndarray:
    """Iron struck: a sharp click, a clunk of mass and plate partials in 1.5-6 kHz with a long
    ring (ring_s is the decay of the lowest partial)."""
    n = fx.frames(seconds, rate)
    f = metal_partials(rng, low * (1 - 0.15 * weight), high, 9)
    tone = ring(rng, n, rate, f, ring_s * (1 + 0.5 * weight), ring_s * 0.25, 0.5)
    exc_n = fx.frames(0.0015, rate)
    exc = fx.noise(exc_n, rng, 1500.0, 12000.0, rate) * np.hanning(exc_n)
    exc[0] += 2.0
    tone = fx.excite(exc, tone, n)
    tone /= max(core.peak(tone), 1e-9)
    clunk = thump(n, rate, 300.0 - 80 * weight, 170.0 - 40 * weight, 0.015, 0.03 + 0.04 * weight, 0.0008)
    hit = burst(rng, n, rate, 2500.0, 12000.0, 0.0002, 0.003)
    y = 0.75 * tone + (0.45 + 0.3 * weight) * clunk + 0.5 * hit
    return fx.soft_clip(y, 1.3)


def impact_flesh(rng: np.random.Generator, seconds: float, weight: float = 0.0, rate: int = RATE) -> np.ndarray:
    """A blow on a body: a 60-120 Hz thump with a fast pitch drop under low-passed noise, a
    slap on top, and for heavy blows a short crunch."""
    n = fx.frames(seconds, rate)
    f_hi = rng.uniform(105.0, 125.0) - 20.0 * weight
    f_lo = rng.uniform(55.0, 65.0) - 8.0 * weight
    body = thump(n, rate, f_hi, f_lo, 0.022, 0.05 + 0.05 * weight, 0.0012, 0.25, 0.8)
    muffle = burst(rng, n, rate, 80.0, 1100.0 - 250 * weight, 0.001, 0.035 + 0.03 * weight, "pink")
    thwack = burst(rng, n, rate, 450.0, 1900.0, 0.0006, 0.012 + 0.006 * weight, "pink")
    slap = burst(rng, n, rate, 900.0, 3600.0, 0.0004, 0.005)
    y = 0.85 * body + 0.65 * muffle + 0.5 * thwack + 0.4 * slap
    if weight > 0.3:
        bank = fx.NoiseBank(rng, 0.3, rate, (600.0, 1200.0, 2400.0))
        times = fx.poisson_times(rng, 0.004, 0.05, lambda t: 300.0)
        y += 0.35 * weight * fx.scatter(n, rng, times, lambda i: bank.grain(rng.uniform(600, 2200), 0.004),
                                        rng.uniform(0.3, 1.0, len(times)), rate)
    return fx.soft_clip(y, 2.0 + weight)


def impact_armor(rng: np.random.Generator, seconds: float, weight: float = 0.0, rate: int = METAL_RATE) -> np.ndarray:
    """A blow on an armoured body: the flesh thump with a short plate ring (iron partials that
    die within a quarter second)."""
    n = fx.frames(seconds, rate)
    flesh = impact_flesh(rng, seconds, weight * 0.8, rate)
    plate = impact_iron(rng, seconds, weight, rate, ring_s=0.09 + 0.06 * weight, low=1300.0, high=5200.0)
    return fx.soft_clip(0.8 * flesh + 0.6 * plate, 1.5)


# --------------------------------------------------------------------------- swings


def whoosh(rng: np.random.Generator, seconds: float, lo: float, hi: float, peak_at: float = 0.55,
           q: float = 1.2, rise_pow: float = 2.2, fall_tau: float | None = None, rate: int = RATE,
           color: str = "pink", end_ratio: float = 0.75) -> np.ndarray:
    """A swing passing by: noise through a band-pass whose centre sweeps lo -> hi at the apex
    (peak_at of the length) -> lo x end_ratio, under an asymmetric swell."""
    n = fx.frames(seconds, rate)
    src = fx.noise(n, rng, 0.0, 0.0, rate, color)
    apex = peak_at * seconds
    centre = [(0.0, lo), (apex * 0.6, lo + (hi - lo) * 0.45), (apex, hi), (seconds, lo * end_ratio)]
    y = fx.swept_band(src, centre, [(0.0, q), (seconds, q * 1.1)], rate, frame=512)
    env = fx.env_swell(n, rate, apex, rise_pow, fall_tau if fall_tau is not None else seconds * 0.16)
    return y * env


def leaves(rng: np.random.Generator, n: int, rate: int, env: np.ndarray, density: float = 900.0) -> np.ndarray:
    """Leaf rustle: dense tiny high grains whose density follows env (0..1)."""
    bank = fx.NoiseBank(rng, 0.6, rate, (2400.0, 4800.0, 8000.0))
    dur = n / rate
    e = np.asarray(env)
    times = fx.poisson_times(rng, 0.0, dur, lambda t: density * float(e[min(int(t * rate), n - 1)]) + 1.0, 1200)
    return fx.scatter(n, rng, times, lambda i: bank.grain(rng.uniform(2500, 8000), rng.uniform(0.002, 0.008)),
                      rng.uniform(0.2, 1.0, len(times)), rate)


# --------------------------------------------------------------------------- grains: debris, crunch, splinters


def crunch(rng: np.random.Generator, n: int, rate: int, start_s: float, span_s: float, density: float,
           lo: float, hi: float, grain_s=(0.003, 0.012)) -> np.ndarray:
    """Granular crunch (soil, gravel, grass): grains between lo and hi Hz with a density that
    falls over span_s."""
    bank = fx.NoiseBank(rng, 0.5, rate, tuple(c for c in (300.0, 600.0, 1200.0, 2400.0, 4800.0) if lo * 0.7 <= c <= hi * 1.4)
                        or (lo,))
    times = fx.poisson_times(rng, start_s, start_s + span_s,
                             lambda t: density * math.exp(-(t - start_s) / max(span_s * 0.4, 1e-3)))
    return fx.scatter(n, rng, times, lambda i: bank.grain(math.exp(rng.uniform(math.log(lo), math.log(hi))),
                                                          rng.uniform(*grain_s)),
                      rng.lognormal(0.0, 0.5, len(times)) * 0.5, rate)


def debris(rng: np.random.Generator, n: int, rate: int, start_s: float, span_s: float, count: int,
           kind: str = "stone", size: float = 1.0) -> np.ndarray:
    """Falling bits after a break or a giant's step: stone (clicks and small knocks), dirt
    (soft low pats), wood (short dry pings)."""
    times = sorted(start_s + span_s * rng.uniform(0.0, 1.0, count) ** 1.6)   # more of them early
    bank = fx.NoiseBank(rng, 0.4, rate, (400.0, 800.0, 1600.0, 3200.0, 6000.0))

    def grain(i: int) -> np.ndarray:
        m = fx.frames(rng.uniform(0.006, 0.02) * size, rate)
        if kind == "wood":
            f = rng.uniform(700.0, 2600.0) / size ** 0.3
            ir = fx.modal_ir([f, f * 2.7], [0.012, 0.006], [1.0, 0.4], m, rate)
            return ir * rng.uniform(0.5, 1.0)
        if kind == "dirt":
            return bank.grain(rng.uniform(300.0, 1200.0), m / rate, 0.001, m / rate * 0.4)
        g = bank.grain(rng.uniform(1500.0, 6000.0), 0.004, 0.0002, 0.0012)
        knock = fx.modal_ir([rng.uniform(500.0, 1500.0) / size ** 0.4], [0.006], [1.0], m, rate)
        return fx.fit(g, m) + 0.6 * knock
    gains = [rng.uniform(0.25, 1.0) * (1.0 - 0.6 * (t - start_s) / max(span_s, 1e-6)) for t in times]
    return fx.scatter(n, rng, times, grain, gains, rate)


def splinter(rng: np.random.Generator, n: int, rate: int, start_s: float, span_s: float, density: float,
             size: float = 1.0) -> np.ndarray:
    """Wood splintering: a dense cloud of short wood pings and dry crackle, thinning out."""
    times = fx.poisson_times(rng, start_s, start_s + span_s,
                             lambda t: density * math.exp(-(t - start_s) / max(span_s * 0.35, 1e-3)), 600)
    bank = fx.NoiseBank(rng, 0.4, rate, (1200.0, 2400.0, 4800.0))

    def grain(i: int) -> np.ndarray:
        m = fx.frames(rng.uniform(0.004, 0.014), rate)
        f = rng.uniform(600.0, 3000.0) / size ** 0.25
        ping = fx.modal_ir([f, f * 2.3], [rng.uniform(0.003, 0.01), 0.003], [1.0, 0.5], m, rate)
        return ping + 0.6 * fx.fit(bank.grain(rng.uniform(1500, 6000), 0.003, 0.0002, 0.001), m)
    return fx.scatter(n, rng, times, grain, rng.uniform(0.2, 1.0, len(times)), rate)


def crackle(rng: np.random.Generator, n: int, rate: int, start_s: float, span_s: float, density: float,
            lo: float = 2000.0, hi: float = 7000.0) -> np.ndarray:
    """Crisp tiny clicks (a stone shell forming, embers, a crust breaking)."""
    times = fx.poisson_times(rng, start_s, start_s + span_s, lambda t: density, 800)
    bank = fx.NoiseBank(rng, 0.3, rate, (2400.0, 4800.0, 8000.0))
    return fx.scatter(n, rng, times, lambda i: bank.grain(rng.uniform(lo, hi), rng.uniform(0.001, 0.004), 0.0001, 0.0008),
                      rng.uniform(0.2, 1.0, len(times)), rate)


def grind(rng: np.random.Generator, n: int, rate: int, env: np.ndarray, density: float = 420.0,
          lo: float = 250.0, hi: float = 2500.0) -> np.ndarray:
    """Stone on stone: dense grains of band noise with rough amplitudes, following env."""
    bank = fx.NoiseBank(rng, 0.6, rate, (300.0, 600.0, 1200.0, 2400.0))
    e = np.asarray(env)
    times = fx.poisson_times(rng, 0.0, n / rate, lambda t: density * float(e[min(int(t * rate), n - 1)]) + 1.0, 1500)
    g = fx.scatter(n, rng, times, lambda i: bank.grain(math.exp(rng.uniform(math.log(lo), math.log(hi))),
                                                       rng.uniform(0.006, 0.02), 0.002),
                   rng.lognormal(0.0, 0.6, len(times)) * 0.4, rate)
    return g


# --------------------------------------------------------------------------- creaks


WOOD_BODY = (240.0, 470.0, 760.0, 1180.0, 1850.0)


def creak(rng: np.random.Generator, seconds: float, pulse_points, rate: int = RATE,
          body=WOOD_BODY, sweep_points=None, sweep_q: float = 6.0, noise_level: float = 0.35,
          grip_points=None) -> np.ndarray:
    """A wooden creak: stick-slip pulses (their rate in Hz follows pulse_points, wandering) through
    wood body modes, plus noise through a slowly swept narrow resonance (the plan's gate creak).
    The grip (0..1 over time, grip_points) sets how often the surfaces catch: it breaks the
    pulse train into irregular runs, as real wood does, instead of a steady buzz."""
    n = fx.frames(seconds, rate)
    t = fx.t_axis(n, rate)
    drift = fx.wander(n, rng, 12.0, rate)
    pr = fx.track(pulse_points, t) * np.clip(1.0 + 0.25 * drift, 0.4, 1.8)
    phase = np.cumsum(np.maximum(pr, 1.0)) / rate
    k = np.floor(phase)
    starts = np.nonzero(np.diff(k) > 0)[0] + 1
    grip = fx.track(grip_points, t) if grip_points is not None else np.full(n, 0.85)
    # runs: a slow random gate (the wood catches and lets go) times the grip
    gate = np.clip(0.5 + 0.5 * fx.wander(n, rng, 6.0, rate), 0.0, 1.0)
    keep = rng.uniform(0.0, 1.0, starts.shape[0]) < (grip[starts] * (0.35 + 0.65 * gate[starts]))
    starts = starts[keep]
    train = np.zeros(n)
    train[starts] = rng.lognormal(0.0, 0.45, starts.shape[0])
    ir = fx.modal_ir(fx.partials(1.0, body, rng, 0.06), rng.uniform(0.006, 0.02, len(body)),
                     [1.0, 0.8, 0.6, 0.45, 0.3], fx.frames(0.06, rate), rate)
    tone = core.fft_convolve(train, ir)[:n]
    tone /= max(core.peak(tone), 1e-9)
    if sweep_points is not None:
        src = fx.noise(n, rng, 0.0, 0.0, rate, "pink")
        sw = fx.swept_band(src, sweep_points, [(0.0, sweep_q), (seconds, sweep_q)], rate, 1024)
        tone = tone + noise_level * sw / max(core.peak(sw), 1e-9)
    return tone


# --------------------------------------------------------------------------- tones


RISSET_RATIOS = (0.56, 0.563, 0.92, 0.923, 1.19, 1.7, 2.0, 2.74, 3.0, 3.76, 4.07)
RISSET_DECAYS = (1.0, 0.9, 0.65, 0.55, 0.325, 0.35, 0.25, 0.2, 0.15, 0.1, 0.075)
RISSET_AMPS = (1.0, 0.67, 1.0, 1.8, 2.67, 1.67, 1.46, 1.33, 1.33, 1.0, 1.33)


def bell(rng: np.random.Generator, n: int, rate: int, f0: float, decay_s: float,
         ratios=RISSET_RATIOS, decays=RISSET_DECAYS, amps=RISSET_AMPS, detune: float = 0.003,
         strike: float = 0.3) -> np.ndarray:
    """An inharmonic bell (additive, Risset-style partials) with a soft strike."""
    f = fx.partials(f0, ratios, rng, detune)
    taus = np.asarray(decays) * decay_s
    ir = fx.modal_ir(f, taus, np.asarray(amps) / max(amps), n, rate, rng.uniform(0, TWO_PI, len(f)))
    ir /= max(core.peak(ir), 1e-9)
    hit = burst(rng, n, rate, f0 * 2.0, min(f0 * 12.0, rate * 0.45), 0.0003, 0.004)
    return ir + strike * hit


def fm(n: int, rate: int, carrier, ratio: float, index, phase: float = 0.0) -> np.ndarray:
    """Two-operator FM: sin(2 pi int carrier + index sin(2 pi int carrier x ratio)); carrier and
    index may be per-sample arrays."""
    c = np.full(n, float(carrier)) if np.isscalar(carrier) else np.asarray(carrier, dtype=np.float64)
    idx = np.full(n, float(index)) if np.isscalar(index) else np.asarray(index, dtype=np.float64)
    ph_c = np.cumsum(c) / rate
    ph_m = np.cumsum(c * ratio) / rate
    return np.sin(TWO_PI * ph_c + idx * np.sin(TWO_PI * ph_m) + phase)


def pluck(rng: np.random.Generator, n: int, rate: int, f0: float, tau_s: float, harmonics: int = 14,
          bright: float = 0.9, bend: float = 0.08, inharm: float = 0.0008) -> np.ndarray:
    """A plucked string (additive): harmonic partials whose decay shortens with their number,
    a slight pitch bend down at the start, a little stiffness."""
    t = fx.t_axis(n, rate)
    bend_curve = 1.0 + bend * np.exp(-t / 0.02)
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        fk = f0 * k * math.sqrt(1.0 + inharm * k * k)
        if fk * (1.0 + bend) >= rate * 0.47:
            break
        tau = tau_s / (1.0 + 0.55 * (k - 1))
        amp = k ** (-bright) * rng.uniform(0.7, 1.0)
        out += amp * np.exp(-t / tau) * np.sin(TWO_PI * np.cumsum(fk * bend_curve) / rate + rng.uniform(0, TWO_PI))
    return out


def tone(n: int, rate: int, freq, wave: str = "sine") -> np.ndarray:
    if wave == "triangle":
        return core.triangle(freq, n, rate)
    if wave == "square":
        return core.square(freq, n, rate)
    if wave == "saw":
        return core.saw(freq, n, rate)
    return core.sine(freq, n, rate)


def blip(rng: np.random.Generator, seconds: float, notes, rate: int = RATE, wave: str = "sine",
         step_s: float | None = None, attack_s: float = 0.003, tau_s: float = 0.05,
         detune_cents: float = 4.0, glide: float = 0.0, harmonics: float = 0.0) -> np.ndarray:
    """Interface notes: each MIDI note a short tone (two slightly detuned voices) with a fast
    attack and an exponential decay; notes follow each other every step_s."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    count = max(1, len(notes))
    step = step_s if step_s is not None else seconds / count * 0.6
    for i, note in enumerate(notes):
        start = fx.frames(i * step, rate) if i else 0
        m = n - start
        if m <= 4:
            break
        f = core.midi_hz(note)
        freq = f * (1.0 + glide * np.exp(-fx.t_axis(m, rate) / 0.03)) if glide else f
        cents = 2.0 ** (detune_cents / 1200.0)
        v = tone(m, rate, freq, wave) + 0.6 * tone(m, rate, (np.asarray(freq) * cents) if glide else f * cents, wave)
        if harmonics > 0:
            v += harmonics * core.sine(np.asarray(freq) * 2.0 if glide else f * 2.0, m, rate)
        core.mix_into(out, start, v * fx.env_ad(m, rate, attack_s, tau_s))
    return out


def buzz(n: int, rate: int, freq: float, pulses: int = 1, gap_s: float = 0.05, cutoff: float = 1600.0) -> np.ndarray:
    """A low square buzz (the refusal), in one or more pulses."""
    total = n / rate
    seg = (total - gap_s * (pulses - 1)) / pulses
    out = np.zeros(n)
    for i in range(pulses):
        m = fx.frames(seg, rate)
        f = fx.glide(m, rate, freq * 1.06, freq, 0.03)
        v = core.square(f, m, rate, 0.42) * fx.env_points([(0.0, 0.0), (0.004, 1.0), (seg * 0.7, 0.8), (seg, 0.0)], m, rate)
        core.mix_into(out, fx.frames(i * (seg + gap_s), rate) if i else 0, v)
    return fx.lowpass(out, cutoff, 2.0, rate)


# --------------------------------------------------------------------------- footfalls


# Body size classes of the footfalls: the giant's stages (height 3.66 / 5.49 / 7.92 m and, for
# P28, 10.97 / 14.63 / 18.90 m), heavy bodies (ogres, the King), humans and paws.
STEP_SIZES = {
    "giant_s1": {"f": (88.0, 46.0), "drop": 0.032, "tau": 0.07, "attack": 0.004, "body_lp": 260.0, "crunch": 1.0, "debris": 0},
    "giant_s2": {"f": (78.0, 41.0), "drop": 0.038, "tau": 0.085, "attack": 0.006, "body_lp": 220.0, "crunch": 1.25, "debris": 0},
    "giant_s3": {"f": (68.0, 36.0), "drop": 0.045, "tau": 0.1, "attack": 0.008, "body_lp": 190.0, "crunch": 1.5, "debris": 18},
    "giant_s4": {"f": (60.0, 32.0), "drop": 0.05, "tau": 0.12, "attack": 0.010, "body_lp": 170.0, "crunch": 1.8, "debris": 24},
    "giant_s5": {"f": (54.0, 29.0), "drop": 0.056, "tau": 0.14, "attack": 0.012, "body_lp": 150.0, "crunch": 2.1, "debris": 30},
    "giant_s6": {"f": (48.0, 26.0), "drop": 0.062, "tau": 0.16, "attack": 0.014, "body_lp": 135.0, "crunch": 2.4, "debris": 36},
    "heavy": {"f": (82.0, 48.0), "drop": 0.03, "tau": 0.06, "attack": 0.003, "body_lp": 300.0, "crunch": 0.8, "debris": 0},
}


def step_surface(rng: np.random.Generator, n: int, rate: int, surface: str, scale: float, start_s: float = 0.0) -> np.ndarray:
    """The surface layer of a footfall (scale ~ 0.3 for a human .. 2.4 for a stage-6 giant):
    soft = a granular crunch of soil and grass; hard = clicks and grit on stone; wet = a squelch
    (a falling resonance) with bubbles; wade = a low slosh."""
    out = np.zeros(n)
    s = max(scale, 0.2)
    if surface == "hard":
        tick = burst(rng, n, rate, 1200.0 / s ** 0.3, 6500.0, 0.0002, 0.0025 + 0.002 * s)
        core.mix_into(out, fx.frames(start_s, rate), tick, 0.55)
        out += 0.8 * crunch(rng, n, rate, start_s, 0.03 + 0.04 * s, 900.0 * s ** 0.5, 1800.0 / s ** 0.2, 7000.0,
                            (0.001, 0.004))
        knock = fx.modal_ir(rng.uniform([260, 480, 760], [360, 640, 980]) / s ** 0.35, [0.014, 0.009, 0.006],
                            [1.0, 0.6, 0.35], n, rate)
        core.mix_into(out, fx.frames(start_s, rate), fx.fit(knock, n), 0.6)
        grit = burst(rng, n, rate, 500.0, 3500.0, 0.001, 0.012 + 0.008 * s, "pink")
        core.mix_into(out, fx.frames(start_s, rate), grit, 0.5)
    elif surface == "wet":
        m = fx.frames(0.05 + 0.09 * s, rate)
        mud = fx.noise(m, rng, 60.0, 2500.0, rate, "pink")
        sq = fx.swept_band(mud, [(0.0, 900.0 / s ** 0.3), (m / rate, 150.0)], [(0.0, 2.5), (m / rate, 3.5)], rate, 256)
        sq *= fx.env_ad(m, rate, 0.004, m / rate * 0.35)
        core.mix_into(out, fx.frames(start_s, rate), sq / max(core.peak(sq), 1e-9), 0.9)
        slap = burst(rng, n, rate, 500.0, 2400.0, 0.0005, 0.006)
        core.mix_into(out, fx.frames(start_s, rate), slap, 0.35)
        for _ in range(int(rng.integers(3, 7))):
            bm = fx.frames(rng.uniform(0.008, 0.025), rate)
            f0 = rng.uniform(280.0, 650.0) / s ** 0.2
            bub = core.sine(np.linspace(f0, f0 * rng.uniform(2.0, 3.0), bm), bm, rate) * np.hanning(bm)
            core.mix_into(out, fx.frames(start_s + rng.uniform(0.03, 0.06 + 0.12 * s), rate), bub, rng.uniform(0.12, 0.3))
    elif surface == "wade":
        m = fx.frames(0.12 + 0.2 * s, rate)
        water = fx.noise(m, rng, 80.0, 1800.0, rate, "pink")
        slosh = fx.swept_band(water, [(0.0, 300.0), (m / rate * 0.3, 900.0 / s ** 0.2), (m / rate, 200.0)],
                              [(0.0, 1.2), (m / rate, 1.6)], rate, 512)
        slosh *= fx.env_swell(m, rate, m / rate * 0.25, 1.2, m / rate * 0.3)
        core.mix_into(out, fx.frames(start_s, rate), slosh / max(core.peak(slosh), 1e-9), 1.0)
    else:   # soft
        out += crunch(rng, n, rate, start_s, 0.05 + 0.05 * s, 700.0 * s ** 0.6, 350.0 / s ** 0.25, 2600.0 / s ** 0.15,
                      (0.003, 0.012))
        scuff = burst(rng, n, rate, 250.0 / s ** 0.3, 1400.0, 0.002, 0.02 + 0.015 * s, "pink")
        core.mix_into(out, fx.frames(start_s, rate), scuff, 0.45)
    return out


def giant_step(rng: np.random.Generator, size: str, surface: str, cruise: bool = False,
               rate: int = RATE, seconds: float | None = None) -> np.ndarray:
    """A giant's (or a heavy body's) footfall: the sub thump of its size, a lower body of earth,
    the surface layer and, from stage 3 on, a debris tail of pebbles (not when cruising)."""
    p = STEP_SIZES[size]
    scale = p["crunch"]
    has_debris = p["debris"] > 0 and not cruise and surface in ("soft", "hard")
    dur = seconds if seconds is not None else (0.08 + 4.0 * p["tau"] + (0.3 if has_debris else 0.0))
    n = fx.frames(dur, rate)
    f_hi, f_lo = p["f"]
    f_hi *= rng.uniform(0.95, 1.05)
    body = thump(n, rate, f_hi, f_lo, p["drop"], p["tau"], p["attack"], 0.2, 0.9)
    # the punch: the upper-bass knock that carries the weight on small speakers
    punch = thump(n, rate, f_hi * 2.1, f_lo * 2.6, p["drop"] * 0.6, p["tau"] * 0.28, p["attack"] * 0.5, 0.1)
    earth = burst(rng, n, rate, 25.0, p["body_lp"] * 1.6, p["attack"] * 0.6, p["tau"] * 0.45, "brown")
    surf = step_surface(rng, n, rate, surface, scale, 0.0)
    rel = {"soft": -7.0, "hard": -5.0, "wet": -6.0, "wade": -5.0}.get(surface, -7.0)
    surf = fx.match_rms(surf, body, rel, 0.06, rate)
    y = 1.0 * body + 0.7 * punch + 0.6 * earth + surf
    if has_debris:
        y += 0.38 * debris(rng, n, rate, 0.07, dur * 0.65, p["debris"], "stone" if surface == "hard" else "dirt", scale)
        y += 0.3 * rumble(rng, n, rate, 160.0, 0.03, 0.12, 9.0, 0.3)
    if cruise:
        y = 0.8 * body + 0.55 * punch + 0.5 * earth + 0.6 * surf
    return fx.seal(fx.soft_clip(y, 1.5 + 0.2 * scale), rate, 0.03)


def human_step(rng: np.random.Generator, surface: str, rate: int = RATE, seconds: float = 0.16) -> np.ndarray:
    """A person's step: heel then toe (two small knocks 40-70 ms apart) and a little surface."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    gap = rng.uniform(0.04, 0.07)
    for at, g in ((0.0, 1.0), (gap, rng.uniform(0.45, 0.65))):
        m = n - fx.frames(at, rate)
        heel = thump(m, rate, rng.uniform(170, 200), rng.uniform(105, 125), 0.008, 0.014, 0.0008, 0.3)
        core.mix_into(out, fx.frames(at, rate), heel, g)
        core.mix_into(out, fx.frames(at, rate), step_surface(rng, m, rate, surface, 0.3), 0.7 * g)
    return fx.soft_clip(out, 1.3)


def paw_step(rng: np.random.Generator, surface: str, rate: int = RATE, seconds: float = 0.17) -> np.ndarray:
    """A wolf's paw pair: two soft pats 35-60 ms apart with tiny claw clicks."""
    n = fx.frames(seconds, rate)
    out = np.zeros(n)
    gap = rng.uniform(0.035, 0.06)
    for at, g in ((0.0, 1.0), (gap, rng.uniform(0.6, 0.85))):
        m = n - fx.frames(at, rate)
        pat = burst(rng, m, rate, 120.0, 900.0 if surface != "hard" else 1400.0, 0.0015, 0.007, "pink")
        knock = thump(m, rate, 210.0, 140.0, 0.006, 0.01, 0.0008)
        claws = crackle(rng, m, rate, 0.0, 0.012, 260.0 if surface == "hard" else 120.0, 3000.0, 7500.0)
        core.mix_into(out, fx.frames(at, rate), pat + 0.5 * knock + (0.35 if surface == "hard" else 0.18) * claws, g)
    return out
