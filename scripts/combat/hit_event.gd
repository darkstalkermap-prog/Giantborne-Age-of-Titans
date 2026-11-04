class_name HitEvent
extends RefCounted
## One attack instance touching one target, produced by a sweep or pulse and resolved later
## in stable order by Sim. Plain data: the DamageResolver turns it into a HitResult.

var tick := 0
var instance_id := 0          ## unique per accepted action (dedup key with target_id)
var pulse_id := 0             ## explicit multi-hit pulses get distinct ids
var attacker_id := ""
var target_id := ""
var action_id := ""
var power := 0.0
var ability_multiplier := 1.0
var weapon_multiplier := 1.0
var attacker_stat := 10.0     ## Strength for physical attacks, Intellect for magic
var attacker_height_m := CombatRules.REFERENCE_HEIGHT_M
var size_policy := "attacker_growth"
var damage_split: Dictionary = {"physical": 1.0}
var poise_damage := 0.0
var tags := PackedStringArray()
var crit := false
var crit_multiplier := 1.5
var weak_point := false
var flat_penetration := 0.0
var outgoing_damage_mult := 1.0   ## reserved for buffs such as Titan Surge
var outgoing_poise_mult := 1.0
var knockback_impulse := 0.0
var knockback_max_speed := 0.0
var attacker_position := Vector3.ZERO
var hit_point := Vector3.ZERO
var substep := 0
var distance := 0.0
var category := "melee"
var attacker_growth_stage := 1
## Statuses this hit applies: [{"status": id, "magnitude": float, "duration_s": float,
## "on_blocked": bool}] - on HIT, and on BLOCKED for entries with on_blocked (CombatEntity).
var on_hit_statuses: Array = []
## Morale the defender loses on HIT or BLOCKED (actor.on_morale_delta, when it has one).
var morale_damage := 0.0
## Projectile hits still land after their shooter died on an earlier tick (decision 8).
var from_projectile := false
var projectile_id := 0
## Set for cylinder and sector pulses and projectile splash (player area effects skip neutrals).
var area_effect := false


func has_tag(tag: String) -> bool:
	return tags.has(tag)


## Deterministic resolution order: attacker, attack instance, pulse, sweep substep,
## distance from the attack origin, then target id.
static func compare_stable(a: HitEvent, b: HitEvent) -> bool:
	if a.attacker_id != b.attacker_id:
		return a.attacker_id < b.attacker_id
	if a.instance_id != b.instance_id:
		return a.instance_id < b.instance_id
	if a.pulse_id != b.pulse_id:
		return a.pulse_id < b.pulse_id
	if a.substep != b.substep:
		return a.substep < b.substep
	if not is_equal_approx(a.distance, b.distance):
		return a.distance < b.distance
	return a.target_id < b.target_id
