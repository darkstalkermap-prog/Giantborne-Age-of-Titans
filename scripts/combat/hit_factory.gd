class_name HitFactory
extends RefCounted
## The one place that turns hit-query candidates into HitEvents (plan §2.6.5). The player,
## every enemy archetype, projectiles and throws all queue their hits through here, so the
## stat choice, weapon multiplier, crit roll and growth stage are set the same way for every
## source.
##
## Determinism: candidates are sorted by sub-step, then distance, then entity id; crits are
## rolled with Sim.rng in that build order (the worked-example tests pin the sequence).
##
## Later packages add their fields directly below their own anchor (plan §1.5): P03 the
## outgoing multipliers, on-hit statuses, morale damage, weapon tags, projectile fields,
## area_effect and the skip_candidate rule; P07 grab and throw fields.


## Stable candidate order: sub-step, then distance from the attack origin, then entity id.
static func sort_candidates(cands: Array) -> void:
	cands.sort_custom(_candidate_before)


static func _candidate_before(x: Dictionary, y: Dictionary) -> bool:
	if x.substep != y.substep:
		return x.substep < y.substep
	if not is_equal_approx(x.distance, y.distance):
		return x.distance < y.distance
	return (x.entity as CombatEntity).entity_id < (y.entity as CombatEntity).entity_id


## True when `target` must not receive this attack at all: the player's area effects (cylinder
## and sector pulses, projectile splash, Roar) skip every entity the player may not target, so
## they never touch neutral bystanders (decision 17). Direct weapon arcs and direct projectile
## hits are never filtered: a deliberate swing still lands (P11b makes that an offence).
static func skip_candidate(attacker: CombatEntity, target: CombatEntity, area_effect: bool) -> bool:
	return area_effect and attacker != null and attacker.team == CombatEntity.Team.PLAYER \
		and not TargetingRules.player_may_target(target)


## One HitEvent for one candidate ({entity, hurtbox, point, substep, distance, weak_point}).
## Rolls the crit with Sim.rng, so call it only for hits that will really be queued.
static func build(ctx: AttackContext, a: ActionDef, cand: Dictionary, pulse_id: int, tick: int) -> HitEvent:
	var c := ctx.entity.combatant
	var target: CombatEntity = cand.entity
	var e := HitEvent.new()
	e.tick = tick
	e.instance_id = ctx.instance_id
	e.pulse_id = pulse_id
	e.attacker_id = ctx.entity.entity_id
	e.target_id = target.entity_id
	e.action_id = a.id
	e.power = a.power
	e.ability_multiplier = a.ability_multiplier
	e.weapon_multiplier = float(ctx.weapon.get("damage_multiplier", 1.0)) if a.uses_weapon else 1.0
	e.attacker_stat = c.attribute("intellect") if a.category == "magic" else c.attribute("strength")
	e.attacker_height_m = c.height_m
	e.size_policy = a.size_policy
	e.damage_split = a.damage_split
	e.poise_damage = a.poise_damage
	e.tags = a.tags
	e.crit = a.crit_eligible and Sim.rng.randf() < c.crit_chance
	e.crit_multiplier = c.crit_multiplier
	e.weak_point = bool(cand.get("weak_point", false))
	e.flat_penetration = a.flat_penetration
	e.knockback_impulse = a.knockback_impulse
	e.knockback_max_speed = a.knockback_max_speed
	e.attacker_position = ctx.attacker_position
	e.hit_point = cand.get("point", ctx.attacker_position)
	e.substep = int(cand.get("substep", 0))
	e.distance = float(cand.get("distance", 0.0))
	e.category = a.category
	e.attacker_growth_stage = ctx.growth_stage
	## @anchor P03
	# Buffs (Titan Surge): live for melee and pulses, frozen at launch for projectiles.
	e.outgoing_damage_mult = c.outgoing_damage_mult() if is_nan(ctx.outgoing_damage_mult) \
		else ctx.outgoing_damage_mult
	e.outgoing_poise_mult = c.outgoing_poise_mult() if is_nan(ctx.outgoing_poise_mult) \
		else ctx.outgoing_poise_mult
	# The record's array (read-only for everyone: CombatEntity only reads it).
	var p03_statuses: Variant = a.param("on_hit_statuses", [])
	e.on_hit_statuses = p03_statuses if typeof(p03_statuses) == TYPE_ARRAY else []
	e.morale_damage = float(a.param("morale_damage", 0.0))
	if a.uses_weapon:
		# Weapon tags (TreeWeapon) ride on every weapon blow.
		var p03_weapon_tags: Variant = ctx.weapon.get("tags", [])
		if typeof(p03_weapon_tags) == TYPE_ARRAY and not (p03_weapon_tags as Array).is_empty():
			var p03_tags := PackedStringArray(a.tags)
			for p03_tag: Variant in p03_weapon_tags:
				if not p03_tags.has(str(p03_tag)):
					p03_tags.append(str(p03_tag))
			e.tags = p03_tags
	e.from_projectile = ctx.from_projectile
	e.projectile_id = ctx.projectile_id
	e.area_effect = ctx.area_effect
	## @anchor P07
	return e


## Sorts the candidates, drops skipped ones and repeats (ctx.registry, per instance, pulse and
## entity), builds the rest and queues them with Sim. Returns how many hits were queued.
static func queue(ctx: AttackContext, a: ActionDef, cands: Array, pulse_id: int, tick: int) -> int:
	sort_candidates(cands)
	var queued := 0
	for cand: Dictionary in cands:
		var target: CombatEntity = cand.entity
		if skip_candidate(ctx.entity, target, ctx.area_effect):
			continue
		if not ctx.registry.try_register(ctx.instance_id, pulse_id, target.entity_id, a.max_hits_per_target):
			continue
		Sim.queue_hit(build(ctx, a, cand, pulse_id, tick))
		queued += 1
	return queued
