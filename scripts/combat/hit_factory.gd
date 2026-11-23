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
	e.versus_size_exponent = float(a.param("versus_size_exponent", 0.0))   # A2: a titan's blow
	var hb: Variant = cand.get("hurtbox")
	if hb is Hurtbox:
		e.region = (hb as Hurtbox).region   # A2: the struck region (a titan's plates read it)
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
	# M6-M9 (P20): P32's size override (attacker_height_override_m) goes below its anchor.
	## @anchor P32
	# P32 (plan M6-M9 §2.10, decision 21): an action's attacker_height_override_m - siege engines 8.0, the
	# cavalry's charge 4.0 - is the attacker's height for this hit: the poise ratio, the knockback ratio
	# and the stagger length treat it as coming from that tall an attacker (a ballista bolt staggers a
	# big giant as an 8 m attacker would). Damage's M_size is unchanged: such actions use size_policy
	# "none" (the action schema requires it).
	var p32_override := float(a.param("attacker_height_override_m", 0.0))
	if p32_override > 0.0:
		e.attacker_height_m = p32_override
	return e


## Sorts the candidates, drops skipped ones and repeats (ctx.registry, per instance, pulse and
## entity), builds the rest and queues them with Sim. Returns how many hits were queued.
static func queue(ctx: AttackContext, a: ActionDef, cands: Array, pulse_id: int, tick: int) -> int:
	sort_candidates(cands)
	pick_titan_regions(cands, ctx.entity, ctx.instance_id if a.hit_shape == "weapon_arc" else -1, tick)
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


## A2 (decision A2-1): a titan (an entity with plates) is struck in one region per pulse. Hits stay
## de-duplicated per entity (HitRegistry); of a titan's candidates in this call only one is kept, where its first
## candidate stood, so the order of the other targets (and every non-titan hit) is unchanged. Which one: when the
## attacker holds the titan in its lock, the hurtbox the swing passed through nearest the lock's point (the plate
## the lock frames: TitanEnemy.titan_lock_point - the player aims at a plate by the lock); otherwise, and between
## equals, PlateRules.pick_before - the earliest sub-step, the deepest contact, the distance, the region's name.
## Every key is a plain value of the bodies' positions, so the same swing strikes the same plate in every run.
## Modifies `cands` in place.
static func pick_titan_regions(cands: Array, attacker: CombatEntity = null, swing_instance := -1, tick := 0) -> void:
	var best := {}      # entity id -> the kept candidate's key
	var aimed := {}     # entity id -> true when the attacker aims at a plate of it
	var plated := false
	for cand: Dictionary in cands:
		var e: CombatEntity = cand.entity
		if e == null or e.plates == null:
			continue
		plated = true
		var aim := _aim_point(attacker, e)
		if aim.is_finite():
			aimed[e.entity_id] = true
		var key := _region_key(cand, aim)
		if not best.has(e.entity_id) or _key_before(key, best[e.entity_id]):
			best[e.entity_id] = key
	if not plated:
		return
	var out: Array = []
	var placed := {}
	for cand: Dictionary in cands:
		var e: CombatEntity = cand.entity
		if e == null or e.plates == null:
			out.append(cand)
			continue
		if placed.has(e.entity_id):
			continue
		placed[e.entity_id] = true
		var key: Dictionary = best[e.entity_id]
		if swing_instance >= 0 and aimed.has(e.entity_id) and not _aim_beyond(attacker, e):
			var kept := _aimed_swing(e.entity_id, swing_instance, tick, key, aim_snap_m(e))
			if not kept.is_empty():
				out.append(kept)
			continue
		out.append(key.cand)
	cands.assign(out)


## A2: a weapon swing aimed at a titan's plate (the attacker's lock) that touches him first somewhere else - his
## forearm, his legs - is held back up to AIM_DEFER_TICKS so it can reach the plate it was swung at (within
## AIM_SNAP_M of the lock's point: it strikes that plate); after that its first contact lands as it would have.
## A swing that ends inside the delay without touching him again is a miss. Keyed by the swing's instance (ticks
## only: deterministic). Returns the candidate to land now, or {} to hold it back.
## B4 (the milestone B gate): a titan's record may set its own (aim_snap_m): AIM_SNAP_M was set for Stoneback (17.7 m),
## within which every hurtbox centre of the Ogre King (8.5 m) lies of every plate's point - his torso's too - so a swing
## aimed at his keg or bell landed on his torso wherever it first touched him.
const AIM_SNAP_M := 4.5
const AIM_DEFER_TICKS := 3
static var _deferred: Dictionary = {}   # "instance:entity" -> {"tick", "cand"}


## B4: true for a titan with its own aim_snap_m (a small one) when the plate the attacker aims at lies beyond his body
## from it (his keg seen from his front, his bell from behind): such a swing is not held back for the plate - it
## lands where it first touches him, as an unaimed one does (the weapon does not pass through him to the far side).
static func _aim_beyond(attacker: CombatEntity, e: CombatEntity) -> bool:
	var rec: Variant = e.actor.get("record") if e != null and e.actor != null and is_instance_valid(e.actor) else null
	if typeof(rec) != TYPE_DICTIONARY or not (rec as Dictionary).has("aim_snap_m") or attacker == null \
			or attacker.actor == null:
		return false
	var aim := _aim_point(attacker, e)
	var from := (attacker.actor as Node3D).global_position
	var centre := (e.actor as Node3D).global_position
	return Vector2(aim.x - from.x, aim.z - from.z).length() > Vector2(centre.x - from.x, centre.z - from.z).length()


## The snap distance of titan `e` (its record's aim_snap_m, else AIM_SNAP_M).
static func aim_snap_m(e: CombatEntity) -> float:
	var rec: Variant = e.actor.get("record") if e != null and e.actor != null and is_instance_valid(e.actor) else null
	if typeof(rec) == TYPE_DICTIONARY and SchemaUtil.is_number((rec as Dictionary).get("aim_snap_m")):
		return float(rec.aim_snap_m)
	return AIM_SNAP_M


static func _aimed_swing(entity_id: String, instance: int, tick: int, key: Dictionary, snap_m := AIM_SNAP_M) -> Dictionary:
	var k := "%d:%s" % [instance, entity_id]
	if float(key.aim) <= snap_m:
		_deferred.erase(k)
		return key.cand
	if not _deferred.has(k):
		if _deferred.size() > 64:
			_deferred.clear()
		_deferred[k] = {"tick": tick, "cand": key.cand}
		return {}
	var d: Dictionary = _deferred[k]
	if tick - int(d.tick) < AIM_DEFER_TICKS:
		return {}
	_deferred.erase(k)
	return d.cand


## The point the attacker aims at on titan `e`: its lock's point when it holds `e` locked (the player), else INF.
static func _aim_point(attacker: CombatEntity, e: CombatEntity) -> Vector3:
	if attacker == null or attacker.actor == null or not ("targeting" in attacker.actor):
		return Vector3.INF
	var targeting: Variant = attacker.actor.get("targeting")
	if targeting == null or not (targeting as Object).has_method("locked_entity") \
			or (targeting as Object).call("locked_entity") != e:
		return Vector3.INF
	return e.lock_anchor_position(attacker.combatant.height_m)


static func _key_before(a: Dictionary, b: Dictionary) -> bool:
	if not is_equal_approx(float(a.aim), float(b.aim)):
		return float(a.aim) < float(b.aim)
	return PlateRules.pick_before(a, b)


static func _region_key(cand: Dictionary, aim := Vector3.INF) -> Dictionary:
	var hb: Variant = cand.get("hurtbox")
	var region := ""
	var contact := 0.0
	var to_aim := 0.0
	if hb is Hurtbox and is_instance_valid(hb):
		region = (hb as Hurtbox).region
		var point: Vector3 = cand.get("point", (hb as Hurtbox).global_position)
		contact = point.distance_to((hb as Hurtbox).global_position)
		if aim.is_finite():
			to_aim = snappedf((hb as Hurtbox).global_position.distance_to(aim), 0.001)
	return {"substep": int(cand.get("substep", 0)), "contact": contact, "distance": float(cand.get("distance", 0.0)),
		"region": region, "aim": to_aim, "cand": cand}
