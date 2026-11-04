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


## True when `target` must not receive this attack at all. P02: never (no filtering). P03:
## the player's area effects skip entities the player may not target (neutral bystanders).
static func skip_candidate(_attacker: CombatEntity, _target: CombatEntity, _area_effect: bool) -> bool:
	return false


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
