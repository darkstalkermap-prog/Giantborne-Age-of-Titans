class_name DamageResolver
extends RefCounted
## Pure hit resolution (spec sections 6 and 7).
##
## Order: dead target -> dodge invulnerability -> raw damage -> critical (x1.5 when eligible)
## -> weak point (x1.25) -> typed mitigation (armor for physical, resistance for elemental;
## armor never reduces elemental damage) -> parry / block / guard break -> round once.
## Nothing here mutates state; CombatEntity applies the returned HitResult.

const EPSILON := 1e-6


## Typed damage before blocking. Returns {"raw", "physical", "elemental", "total", "immune"}.
static func mitigate(hit: HitEvent, defender: Combatant) -> Dictionary:
	var size_mult := 1.0
	if hit.size_policy == "attacker_growth":
		size_mult = CombatRules.size_multiplier(hit.attacker_height_m)
	var raw := CombatRules.raw_damage(hit.power, hit.attacker_stat, hit.ability_multiplier,
		hit.weapon_multiplier, size_mult) * hit.outgoing_damage_mult
	if hit.crit:
		raw *= hit.crit_multiplier
	if hit.weak_point:
		raw *= CombatRules.WEAK_POINT_MULTIPLIER
	var physical := 0.0
	var elemental := 0.0
	var had_portion := false
	var all_immune := true
	var types := hit.damage_split.keys()
	types.sort()
	for t: String in types:
		var portion := raw * float(hit.damage_split[t])
		if portion <= 0.0:
			continue
		had_portion = true
		if defender.is_immune_to(t):
			continue
		all_immune = false
		if t == "physical":
			var armor := CombatRules.effective_armor(defender.armor, hit.flat_penetration)
			physical += CombatRules.physical_after_armor(portion, armor)
		else:
			elemental += CombatRules.elemental_after_resistance(portion, defender.resistance(t))
	var tag_immune := false
	for tag in hit.tags:
		if defender.is_immune_to(tag):
			tag_immune = true
	return {"raw": raw, "physical": physical, "elemental": elemental,
		"total": physical + elemental, "immune": tag_immune or (had_portion and all_immune)}


static func resolve(hit: HitEvent, defender: Combatant, defense: DefenseState) -> HitResult:
	var r := HitResult.new()
	r.event = hit
	r.crit = hit.crit
	if defense.is_dead or defender.dead:
		r.outcome = HitResult.Outcome.IGNORED
		r.notes = "target_dead"
		return r
	if defense.invulnerable and not hit.has_tag("Unavoidable"):
		r.outcome = HitResult.Outcome.EVADED
		r.notes = "invulnerable"
		return r
	var m := mitigate(hit, defender)
	r.raw_damage = m.raw
	r.mitigated_damage = m.total
	if m.immune:
		r.outcome = HitResult.Outcome.IMMUNE
		r.notes = "immune"
		return r
	var size_ratio := hit.attacker_height_m / maxf(defense.height_m, 0.01)
	var knock := CombatRules.knockback_speed(hit.knockback_impulse, size_ratio, defense.stability,
		hit.knockback_max_speed)
	# Unblockable and Unparryable are independent flags (spec 6): an Unblockable attack can still
	# be parried inside the window; an Unparryable one can still be blocked.
	var guarding := defense.blocking and CombatRules.block_covers(defense.position, defense.forward,
		hit.attacker_position, defense.coverage_deg)
	var parryable := hit.has_tag("Melee") and hit.has_tag("Parryable") and not hit.has_tag("Unparryable")
	if guarding and parryable and defense.parry_available and defense.in_parry_window() \
			and defense.stamina + EPSILON >= defense.parry_extra_stamina:
		r.outcome = HitResult.Outcome.PARRIED
		r.stamina_damage = defense.parry_extra_stamina
		r.attacker_poise_damage = defense.parry_poise_damage
		r.notes = "parry"
		return r
	if guarding and not hit.has_tag("Unblockable"):
		var impact := CombatRules.impact_stamina_cost(m.total, defense.impact_stamina_factor)
		if defense.stamina + EPSILON >= float(impact):
			r.outcome = HitResult.Outcome.BLOCKED
			r.health_damage = CombatRules.round_damage(
				m.physical * (1.0 - defense.physical_reduction)
				+ m.elemental * (1.0 - defense.elemental_reduction))
			r.stamina_damage = float(impact)
			r.knockback_speed = knock * 0.5
			r.notes = "failed_parry" if (parryable and defense.in_parry_window()) else "block"
			return r
		r.outcome = HitResult.Outcome.GUARD_BROKEN
		r.stamina_damage = maxf(defense.stamina, 0.0)
		r.health_damage = CombatRules.round_damage(m.total * defense.guard_break_damage_fraction)
		r.stagger_s = defense.guard_break_stagger_s
		r.knockback_speed = knock
		r.notes = "guard_broken"
		return r
	r.outcome = HitResult.Outcome.HIT
	r.health_damage = CombatRules.round_damage(m.total)
	r.poise_damage = hit.poise_damage * hit.outgoing_poise_mult \
		* CombatRules.poise_scale(hit.attacker_height_m, defense.height_m)
	r.knockback_speed = knock
	return r
