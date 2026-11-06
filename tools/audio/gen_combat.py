"""Combat sounds (P21; plan M6-M9 section 4.1 families A and B, section 4.2): impacts on bodies,
armour, wood and stone, the critical accent, blocks, parries, guard breaks, clanks and falling
bodies (bank_combat.json: sfx.hit.*, sfx.block.*, sfx.parry, sfx.guard_break, sfx.clank.*,
sfx.body.fall.*), and the swings and movement of the giant and its enemies (sfx.swing.*,
sfx.dodge.*, sfx.block.raise, sfx.jump).

Every sound is original and synthesized here (no recordings, no samples). Metal (armour hits,
guards, parries, guard breaks) renders at 32 kHz so its 1.5-6 kHz partials keep their sparkle;
everything else at 22.05 kHz. Heavy variants are about 1.4 x longer and 0.8 x lower than light
ones (section 4.2). Seeds 210001-210199.
"""

from __future__ import annotations

import numpy as np

from synth import core, fx
from synth import instruments as ins

FAMILY = "combat"
RATE = ins.RATE
METAL = ins.METAL_RATE


# --------------------------------------------------------------------------- impacts (A)


def hit_flesh(rng, rate, variant, weight, seconds):
    """A blow on flesh: thump, muffled body, thwack and slap; heavy adds a crunch."""
    x = ins.impact_flesh(rng, seconds, weight, rate)
    x = fx.reflections(x, rng, rate, 4, 0.03, 0.12, 2500.0)
    return fx.finish(x, rate)


def hit_armor(rng, rate, variant, weight, seconds):
    """A blow on an armoured body: the flesh thump and a short plate ring."""
    return fx.finish(ins.impact_armor(rng, seconds, weight, rate), rate)


def hit_wood(rng, rate, variant, seconds):
    """Wood struck (dummies, fences, crates, gates, trees)."""
    x = ins.impact_wood(rng, seconds, 0.35 + 0.3 * variant, rate)
    return fx.finish(fx.reflections(x, rng, rate, 4, 0.025, 0.1, 3000.0), rate)


def hit_stone(rng, rate, variant, seconds):
    """Stone struck (cairns, fortified gates): grit, stone modes, a thud and crumbs."""
    return fx.finish(ins.impact_stone(rng, seconds, 0.4 + 0.3 * variant, rate), rate)


def crit(rng, rate, variant, seconds):
    """The critical accent laid over a hit: a bright crack, a biting upward chirp and a sub drop."""
    n = fx.frames(seconds, rate)
    crack = ins.burst(rng, n, rate, 2200.0, 9000.0, 0.0002, 0.006)
    chirp_f = np.linspace(1700.0, 3600.0, n)
    chirp = core.sine(chirp_f, n, rate) * fx.env_ad(n, rate, 0.002, 0.03)
    chirp += 0.5 * core.sine(chirp_f * 1.5, n, rate) * fx.env_ad(n, rate, 0.002, 0.02)
    drop = ins.thump(n, rate, 95.0, 34.0, 0.03, 0.11, 0.002, 0.2, 0.7)
    x = 0.8 * crack + 0.35 * chirp + 0.9 * drop
    return fx.finish(fx.soft_clip(x, 1.8), rate)


def immune(rng, rate, variant, seconds):
    """A blow that does nothing: a dead, damped 'tunk' and a faint tick (no body, no ring)."""
    n = fx.frames(seconds, rate)
    dead = fx.modal_ir([rng.uniform(190, 230), rng.uniform(540, 620), 1130.0], [0.012, 0.007, 0.004],
                       [1.0, 0.5, 0.25], n, rate)
    tick = core.sine(2300.0, n, rate) * fx.env_ad(n, rate, 0.001, 0.025)
    thud = ins.thump(n, rate, 140.0, 95.0, 0.01, 0.02, 0.001, 0.1, 0.5)
    x = dead / max(core.peak(dead), 1e-9) + 0.12 * tick + 0.6 * thud
    return fx.finish(x, rate)


def block_player(rng, rate, variant, seconds):
    """The giant takes a blow on its guard: a heavy wooden thud on flesh and a short scrape."""
    n = fx.frames(seconds, rate)
    wood = ins.impact_wood(rng, seconds, 0.8, rate, rng.uniform(140.0, 170.0))
    body = ins.impact_flesh(rng, seconds, 0.7, rate)
    scrape = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.02, 1.0), (0.12, 0.0)], n, rate), 500.0, 400.0, 3000.0)
    x = 0.8 * wood + 0.7 * body + 0.35 * scrape / max(core.peak(scrape), 1e-9)
    return fx.finish(fx.soft_clip(x, 1.6), rate)


def block_guard(rng, rate, variant, seconds):
    """An enemy's guard takes the blow: a wooden shield thud and a short metal clank."""
    metal = ins.impact_iron(rng, seconds, 0.3, rate, ring_s=0.12, low=1400.0, high=5500.0)
    wood = ins.impact_wood(rng, seconds, 0.5, rate)
    x = 0.7 * metal + 0.75 * wood
    return fx.finish(fx.soft_clip(x, 1.4), rate)


def parry(rng, rate, variant, seconds):
    """A parry: a clean bright ring with a deflecting upward glide and a crisp click."""
    n = fx.frames(seconds, rate)
    metal = ins.impact_iron(rng, seconds, 0.0, rate, ring_s=0.32, low=1700.0, high=6500.0)
    f_lo = rng.uniform(2000.0, 2400.0)
    glide = np.linspace(f_lo, f_lo * 1.55, n)
    glide = np.where(np.arange(n) < fx.frames(0.09, rate), glide, f_lo * 1.55)
    shing = core.sine(glide, n, rate) * fx.env_ad(n, rate, 0.003, 0.09)
    x = 0.85 * metal + 0.3 * shing + 0.5 * ins.click(n, rate)
    return fx.finish(x, rate)


def guard_break(rng, rate, variant, seconds):
    """A guard broken: a metal crash, a wooden crack, a low boom and clattering bits."""
    n = fx.frames(seconds, rate)
    metal = ins.impact_iron(rng, seconds, 1.0, rate, ring_s=0.2, low=1200.0, high=5500.0)
    wood = ins.splinter(rng, n, rate, 0.0, 0.08, 900.0, 1.3)
    boom = ins.thump(n, rate, 85.0, 38.0, 0.03, 0.14, 0.002, 0.25, 0.8)
    times = sorted(rng.uniform(0.05, 0.3, 7))
    clatter = fx.scatter(n, rng, times, lambda i: ins.ring(rng, fx.frames(0.06, rate), rate,
                                                           ins.metal_partials(rng, 1800.0, 6000.0, 4), 0.03, 0.01),
                         rng.uniform(0.15, 0.45, 7), rate)
    x = 0.75 * metal + 0.45 * wood / max(core.peak(wood), 1e-9) + 0.9 * boom + 0.35 * clatter
    return fx.finish(fx.soft_clip(x, 1.8), rate)


def clank_stone(rng, rate, variant, seconds):
    """A weapon glancing off a wall: stone grit, a short metal tick and a scrape."""
    n = fx.frames(seconds, rate)
    stone = ins.impact_stone(rng, seconds, 0.3, rate)
    tick = ins.ring(rng, n, rate, ins.metal_partials(rng, 1600.0, 5000.0, 5), 0.05, 0.015)
    scrape = ins.grind(rng, n, rate, fx.env_points([(0.0, 0.0), (0.01, 1.0), (0.09, 0.0)], n, rate), 700.0, 900.0, 4500.0)
    x = 0.85 * stone + 0.3 * tick + 0.3 * scrape / max(core.peak(scrape), 1e-9)
    return fx.finish(x, rate)


BODY_SIZES = {
    # thump (start, end Hz), decay, second-impact delay, debris count, echo
    "small": ((105.0, 58.0), 0.06, 0.09, 0, False),
    "large": ((80.0, 40.0), 0.12, 0.13, 10, False),
    "huge": ((58.0, 27.0), 0.26, 0.2, 26, True),
}


def body_fall(rng, rate, variant, size, seconds):
    """A body hitting the ground: a thud, a second smaller one (limbs, gear), the gear's rattle,
    dirt and, for big bodies, debris, rumble and (the King) an echo off the slopes."""
    n = fx.frames(seconds, rate)
    (f_hi, f_lo), tau, gap, bits, echo = BODY_SIZES[size]
    first = ins.thump(n, rate, f_hi * rng.uniform(0.95, 1.05), f_lo, 0.03, tau, 0.003, 0.2, 0.8)
    second = np.zeros(n)
    core.mix_into(second, fx.frames(gap * rng.uniform(0.8, 1.2), rate),
                  ins.thump(n, rate, f_hi * 1.2, f_lo * 1.3, 0.02, tau * 0.6, 0.002, 0.2, 0.6))
    dirt = ins.crunch(rng, n, rate, 0.0, 0.08 + tau, 600.0, 300.0, 2500.0)
    gear = ins.crackle(rng, n, rate, 0.005, 0.06, 140.0, 1800.0, 5000.0)
    x = 1.0 * first + 0.55 * second + 0.4 * dirt / max(core.peak(dirt), 1e-9) + 0.15 * gear
    if bits:
        x += 0.4 * ins.debris(rng, n, rate, 0.05, seconds * 0.6, bits, "dirt", 1.0 + tau * 4)
        x += 0.35 * ins.rumble(rng, n, rate, 150.0, 0.02, tau * 0.8)
    x = fx.soft_clip(x, 1.6)
    if echo:
        x = fx.fit(fx.valley_echo(x, rng, rate, 0.3, 0.25, 700.0, 2), n)
    return fx.finish(x, rate)


# --------------------------------------------------------------------------- swings and movement (B)


SWINGS = {
    # family: (lo Hz, hi Hz, q) of the light swing; heavy = x 0.8 in pitch, x 1.4 in length
    "blunt": (115.0, 540.0, 0.85),
    "blade": (520.0, 2600.0, 2.4),
    "tree": (70.0, 330.0, 0.75),
}


def swing(rng, rate, variant, family, weight, seconds):
    """A weapon swung by the giant (or an enemy): a whoosh swept to its apex; blades ring
    faintly, trees drag their leaves."""
    lo, hi, q = SWINGS[family]
    k = 0.8 if weight == "heavy" else 1.0
    jit = rng.uniform(0.93, 1.07)
    n = fx.frames(seconds, rate)
    x = ins.whoosh(rng, seconds, lo * k * jit, hi * k * jit, rng.uniform(0.52, 0.64), q, 2.2)
    x /= max(core.peak(x), 1e-9)
    if family == "blunt":
        # the air pushed by a huge club: a low swell under the whoosh
        push = ins.whoosh(rng, seconds, 45.0 * k, 140.0 * k, 0.6, 0.7, 2.0, color="brown")
        x = x + 0.45 * push / max(core.peak(push), 1e-9)
    elif family == "blade":
        apex = fx.frames(seconds * 0.55, rate)
        ring_part = ins.ring(rng, n - apex, rate, ins.metal_partials(rng, 2600.0, 5200.0, 4), 0.09, 0.03)
        r = np.zeros(n)
        core.mix_into(r, apex, ring_part * fx.env_ad(n - apex, rate, 0.01, 0.07))
        x = x + 0.12 * r
    else:
        env = fx.env_swell(n, rate, seconds * 0.6, 1.6, seconds * 0.2)
        leaf = ins.leaves(rng, n, rate, env, 1100.0)
        creak = ins.creak(rng, seconds, [(0.0, 25.0), (seconds, 45.0)], rate, grip_points=[(0.0, 0.2), (seconds * 0.5, 0.8), (seconds, 0.3)])
        x = x + 0.35 * leaf / max(core.peak(leaf), 1e-9) + 0.12 * creak * fx.env_swell(n, rate, seconds * 0.5, 1.0, 0.1)
    return fx.finish(x, rate, fade_in_s=0.01)


def dodge_roll(rng, rate, variant, seconds):
    """The stage-1 giant's roll: two or three soft body thuds, a ground scrape and a cloth swish."""
    n = fx.frames(seconds, rate)
    x = np.zeros(n)
    for i, at in enumerate((0.06, 0.2, 0.32)):
        core.mix_into(x, fx.frames(at * rng.uniform(0.9, 1.1), rate),
                      ins.thump(n, rate, 95.0, 55.0, 0.02, 0.05, 0.004, 0.2, 0.7), (1.0, 0.7, 0.45)[i])
    scrape_env = fx.env_points([(0.0, 0.0), (0.07, 1.0), (0.3, 0.6), (seconds, 0.0)], n, rate)
    scrape = ins.grind(rng, n, rate, scrape_env, 700.0, 350.0, 2400.0)
    swish = ins.whoosh(rng, seconds, 260.0, 1100.0, 0.35, 1.0, 1.6)
    x = x + 0.45 * scrape / max(core.peak(scrape), 1e-9) + 0.35 * swish / max(core.peak(swish), 1e-9)
    return fx.finish(fx.soft_clip(x, 1.4), rate, fade_in_s=0.005)


def dodge_sidestep(rng, rate, variant, seconds):
    """A big giant's sidestep: a body swish, a foot sliding over the ground and its landing."""
    n = fx.frames(seconds, rate)
    swish = ins.whoosh(rng, seconds, 160.0, 700.0, 0.4, 0.9, 1.8)
    slide_env = fx.env_points([(0.0, 0.0), (0.04, 0.4), (0.16, 1.0), (0.24, 0.0)], n, rate)
    slide = ins.grind(rng, n, rate, slide_env, 650.0, 300.0, 2200.0)
    land = np.zeros(n)
    core.mix_into(land, fx.frames(0.2 * rng.uniform(0.9, 1.1), rate),
                  ins.thump(n, rate, 85.0, 44.0, 0.03, 0.07, 0.004, 0.2, 0.8))
    x = 0.5 * swish / max(core.peak(swish), 1e-9) + 0.45 * slide / max(core.peak(slide), 1e-9) + 0.9 * land
    return fx.finish(fx.soft_clip(x, 1.4), rate, fade_in_s=0.005)


def block_raise(rng, rate, variant, seconds):
    """Raising the guard: leather straining and a light knock of the arm coming up."""
    n = fx.frames(seconds, rate)
    leather = ins.creak(rng, seconds, [(0.0, 60.0), (seconds, 90.0)], rate, body=(520.0, 900.0, 1500.0, 2300.0, 3100.0),
                        grip_points=[(0.0, 0.9), (0.08, 0.6), (seconds, 0.0)])
    leather *= fx.env_points([(0.0, 0.0), (0.01, 1.0), (0.09, 0.5), (seconds, 0.0)], n, rate)
    swish = ins.whoosh(rng, seconds, 300.0, 1200.0, 0.3, 1.0, 1.5)
    knock = np.zeros(n)
    core.mix_into(knock, fx.frames(0.07, rate), ins.thump(n, rate, 170.0, 120.0, 0.01, 0.02, 0.001, 0.2, 0.5))
    x = 0.4 * leather + 0.4 * swish / max(core.peak(swish), 1e-9) + 0.5 * knock
    return fx.finish(x, rate, fade_in_s=0.003)


def jump(rng, rate, variant, seconds):
    """A giant's jump: a push-off thud, kicked dirt and an upward rush of air."""
    n = fx.frames(seconds, rate)
    push = ins.thump(n, rate, 90.0, 46.0, 0.025, 0.06, 0.003, 0.2, 0.8)
    dirt = ins.crunch(rng, n, rate, 0.0, 0.08, 700.0, 350.0, 2600.0)
    rush = ins.whoosh(rng, seconds, 180.0, 950.0, 0.55, 1.0, 1.4)
    x = 1.0 * push + 0.35 * dirt / max(core.peak(dirt), 1e-9) + 0.5 * rush / max(core.peak(rush), 1e-9)
    return fx.finish(fx.soft_clip(x, 1.4), rate)


V = ins.variant_cues
CUES = (
    V(FAMILY, "hit_flesh_light", hit_flesh, 210001, 3, {"weight": 0.0, "seconds": 0.26})
    + V(FAMILY, "hit_flesh_heavy", hit_flesh, 210011, 2, {"weight": 1.0, "seconds": 0.38})
    + V(FAMILY, "hit_armor_light", hit_armor, 210021, 2, {"weight": 0.0, "seconds": 0.32}, METAL)
    + V(FAMILY, "hit_armor_heavy", hit_armor, 210031, 2, {"weight": 1.0, "seconds": 0.45}, METAL)
    + V(FAMILY, "hit_wood", hit_wood, 210041, 2, {"seconds": 0.28})
    + V(FAMILY, "hit_stone", hit_stone, 210051, 2, {"seconds": 0.3})
    + V(FAMILY, "hit_crit", crit, 210061, 1, {"seconds": 0.3})
    + V(FAMILY, "hit_immune", immune, 210071, 1, {"seconds": 0.22})
    + V(FAMILY, "block_player", block_player, 210081, 2, {"seconds": 0.32})
    + V(FAMILY, "block_guard", block_guard, 210091, 2, {"seconds": 0.35}, METAL)
    + V(FAMILY, "parry", parry, 210101, 2, {"seconds": 0.5}, METAL)
    + V(FAMILY, "guard_break", guard_break, 210111, 1, {"seconds": 0.55}, METAL)
    + V(FAMILY, "clank_stone", clank_stone, 210121, 1, {"seconds": 0.3})
    + V(FAMILY, "body_fall_small", body_fall, 210131, 2, {"size": "small", "seconds": 0.35})
    + V(FAMILY, "body_fall_large", body_fall, 210141, 1, {"size": "large", "seconds": 0.55})
    + V(FAMILY, "body_fall_huge", body_fall, 210151, 1, {"size": "huge", "seconds": 1.0})
    + V(FAMILY, "swing_blunt_light", swing, 210161, 2, {"family": "blunt", "weight": "light", "seconds": 0.3})
    + V(FAMILY, "swing_blunt_heavy", swing, 210171, 2, {"family": "blunt", "weight": "heavy", "seconds": 0.44})
    + V(FAMILY, "swing_blade_light", swing, 210181, 2, {"family": "blade", "weight": "light", "seconds": 0.28})
    + V(FAMILY, "swing_blade_heavy", swing, 210185, 1, {"family": "blade", "weight": "heavy", "seconds": 0.4})
    + V(FAMILY, "swing_tree_light", swing, 210191, 1, {"family": "tree", "weight": "light", "seconds": 0.5})
    + V(FAMILY, "swing_tree_heavy", swing, 210193, 1, {"family": "tree", "weight": "heavy", "seconds": 0.72})
    + V(FAMILY, "dodge_roll", dodge_roll, 210195, 1, {"seconds": 0.45})
    + V(FAMILY, "dodge_sidestep", dodge_sidestep, 210196, 2, {"seconds": 0.36})
    + V(FAMILY, "block_raise", block_raise, 210198, 1, {"seconds": 0.2})
    + V(FAMILY, "jump", jump, 210199, 1, {"seconds": 0.4})
)
