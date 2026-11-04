class_name CombatRules
extends RefCounted
## Pure combat formulas (spec section 7). No engine state, no side effects: every function
## takes plain values and returns plain values, so the rules can be unit-tested and ported.

## Height of the stage-1 giant in metres (12 ft). Size multipliers are relative to it.
const REFERENCE_HEIGHT_M := 3.6576
const STRENGTH_SCALE := 0.015
const RESISTANCE_MIN := -0.5
const RESISTANCE_MAX := 0.75
const WEAK_POINT_MULTIPLIER := 1.25
const POISE_SCALE_MIN := 0.25
const POISE_SCALE_MAX := 2.0
const EPSILON := 1e-9


## M_size = clamp((attacker_height / 3.6576)^0.45, 1, 2.5). Depends on the attacker only.
static func size_multiplier(attacker_height_m: float) -> float:
	if attacker_height_m <= 0.0:
		return 1.0
	return clampf(pow(attacker_height_m / REFERENCE_HEIGHT_M, 0.45), 1.0, 2.5)


## D_raw = P * (1 + 0.015 * stat) * M_ability * M_weapon * M_size.
static func raw_damage(power: float, stat: float, ability_mult: float, weapon_mult: float,
		size_mult: float) -> float:
	return power * (1.0 + STRENGTH_SCALE * stat) * ability_mult * weapon_mult * size_mult


static func effective_armor(armor: float, flat_penetration: float) -> float:
	return maxf(0.0, armor - flat_penetration)


## Physical damage after armor = D * 100 / (100 + A_eff).
static func physical_after_armor(damage: float, armor_effective: float) -> float:
	return damage * 100.0 / (100.0 + maxf(0.0, armor_effective))


static func clamp_resistance(resistance: float) -> float:
	return clampf(resistance, RESISTANCE_MIN, RESISTANCE_MAX)


## Elemental damage = D * (1 - resistance), resistance clamped to -0.5..0.75.
static func elemental_after_resistance(damage: float, resistance: float) -> float:
	return damage * (1.0 - clamp_resistance(resistance))


## Damage is rounded exactly once, at the very end (half away from zero).
static func round_damage(value: float) -> int:
	return int(roundf(value))


## Poise scale = clamp(attacker_height / defender_height, 0.25, 2).
static func poise_scale(attacker_height_m: float, defender_height_m: float) -> float:
	if defender_height_m <= 0.0:
		return 1.0
	return clampf(attacker_height_m / defender_height_m, POISE_SCALE_MIN, POISE_SCALE_MAX)


## Knockback speed = clamp(base_impulse * size_ratio / stability, 0, max_speed).
static func knockback_speed(base_impulse: float, size_ratio: float, stability: float,
		max_speed: float) -> float:
	var s := maxf(stability, 0.001)
	return clampf(base_impulse * size_ratio / s, 0.0, maxf(0.0, max_speed))


## Impact stamina = ceil(factor * pre-block mitigated damage).
static func impact_stamina_cost(pre_block_mitigated: float, factor: float) -> int:
	return int(ceilf(factor * pre_block_mitigated - EPSILON))


## True when the attacker lies inside the defender's frontal block arc (default 120 degrees).
static func block_covers(defender_pos: Vector3, defender_forward: Vector3, attacker_pos: Vector3,
		coverage_deg: float) -> bool:
	var to_attacker := attacker_pos - defender_pos
	to_attacker.y = 0.0
	var fwd := defender_forward
	fwd.y = 0.0
	if to_attacker.length_squared() < 1e-6 or fwd.length_squared() < 1e-6:
		return true
	var angle := rad_to_deg(fwd.normalized().angle_to(to_attacker.normalized()))
	return angle <= coverage_deg * 0.5 + 1e-4


## Dexterity reduces attack recovery by 0.5% per point above 10, capped at 15%.
static func recovery_scale(dexterity: float) -> float:
	return 1.0 - clampf(0.005 * (dexterity - 10.0), 0.0, 0.15)


## Willpower adds 0.5 percentage points of elemental resistance per point above 10 (max 20).
static func willpower_resistance_bonus(willpower: float) -> float:
	return clampf(0.005 * (willpower - 10.0), 0.0, 0.20)


## Next-level XP requirement: 100 + 50 * (L - 1) for L = 1..19; level 20 is the cap.
static func xp_to_next_level(level: int) -> int:
	if level < 1 or level >= 20:
		return 0
	return 100 + 50 * (level - 1)
