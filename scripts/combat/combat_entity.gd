class_name CombatEntity
extends Node
## Makes its parent node a damageable combat entity with a stable id.
##
## Owns the Combatant (stats, resources, poise), finds the parent's Hurtboxes and occluding
## bodies, registers with Sim, and applies resolved hits: resource changes, stagger, death
## (exactly once), fury awards, and the HitResolved / EntityDied events.
##
## The parent may implement (all optional):
##   get_defense_state() -> DefenseState     block/parry/dodge posture
##   accepts_hit(hit: HitEvent) -> bool      category/stage permissions (breakables)
##   apply_knockback(direction: Vector3, speed: float)
##   on_entity_died(killer_id: String)

enum Team { NEUTRAL, PLAYER, ENEMY }

@export var entity_id := ""
@export var definition_id := ""
@export var team: Team = Team.NEUTRAL
@export var anchor_path: NodePath
## Height used for size ratios. <= 0 means "use the record's height_m".
@export var height_override_m := -1.0

signal hit_taken(result: HitResult)
signal hit_landed(result: HitResult)
signal died(killer_id: String)
signal staggered(duration_s: float, reason: String)

var combatant: Combatant
var controller: CombatController = null
var actor: Node3D
var anchor: Node3D
var hurtboxes: Array[Hurtbox] = []
var occlusion_rids: Array[RID] = []
var _fury_instances: Dictionary = {}


static func can_damage(attacker_team: int, target_team: int) -> bool:
	match attacker_team:
		Team.PLAYER:
			return target_team != Team.PLAYER
		Team.ENEMY:
			return target_team == Team.PLAYER
	return false


func _ready() -> void:
	actor = get_parent() as Node3D
	# Placed instances set their stable id on the actor root (entity_id, or world_id for
	# persistent props) so each instance in a level can carry its own id.
	for key in ["entity_id", "world_id"]:
		var v: Variant = actor.get(key)
		if typeof(v) == TYPE_STRING and v != "":
			entity_id = v
			break
	var rec := GameData.get_record(definition_id)
	if rec.is_empty():
		push_error("CombatEntity %s: unknown definition '%s'" % [entity_id, definition_id])
	var height := height_override_m
	if height <= 0.0 and rec.has("growth_profile"):
		# The player's height comes from its current growth profile, not the base record.
		height = float(GameData.get_record(str(rec.growth_profile)).get("height_m", -1.0))
	combatant = Combatant.from_record(entity_id, rec, height)
	anchor = get_node_or_null(anchor_path) as Node3D
	_collect(actor)
	Sim.register_entity(self)


func _exit_tree() -> void:
	Sim.unregister_entity(self)


func _collect(node: Node) -> void:
	for child in node.get_children():
		if child is Hurtbox:
			var hb := child as Hurtbox
			hb.entity = self
			hurtboxes.append(hb)
		elif child is CollisionObject3D:
			occlusion_rids.append((child as CollisionObject3D).get_rid())
		_collect(child)
	if node == actor and actor is CollisionObject3D:
		occlusion_rids.append((actor as CollisionObject3D).get_rid())


func is_alive() -> bool:
	return combatant != null and not combatant.dead


func is_lockable() -> bool:
	return is_alive() and combatant.lockable


func anchor_position() -> Vector3:
	if anchor != null:
		return anchor.global_position
	return actor.global_position + Vector3.UP * combatant.height_m * 0.6


func display_name() -> String:
	return combatant.display_name


# --------------------------------------------------------------------------- hits

func build_defense_state() -> DefenseState:
	if actor.has_method("get_defense_state"):
		return actor.get_defense_state()
	var d := DefenseState.new()
	d.position = actor.global_position
	d.forward = -actor.global_transform.basis.z
	d.height_m = combatant.height_m
	d.is_dead = combatant.dead
	d.stability = combatant.stability
	return d


func receive_hit(hit: HitEvent, attacker: CombatEntity) -> HitResult:
	var result: HitResult
	if not is_alive():
		result = HitResult.new()
		result.event = hit
		result.outcome = HitResult.Outcome.IGNORED
		result.notes = "target_dead"
	elif actor.has_method("accepts_hit") and not actor.accepts_hit(hit):
		result = HitResult.new()
		result.event = hit
		result.outcome = HitResult.Outcome.IMMUNE
		result.notes = "not_permitted"
	else:
		result = DamageResolver.resolve(hit, combatant, build_defense_state())
	_apply(result, attacker)
	return result


func _apply(result: HitResult, attacker: CombatEntity) -> void:
	var pools := combatant.pools
	var hit := result.event
	match result.outcome:
		HitResult.Outcome.IGNORED:
			return  # a dead target generates nothing, not even feedback events
		HitResult.Outcome.PARRIED:
			pools.spend_stamina(result.stamina_damage)
			pools.add_fury(float(combatant.fury_gain.get("parry", 0.0)))
			if attacker != null:
				attacker.apply_poise_damage(result.attacker_poise_damage, "parried")
		HitResult.Outcome.BLOCKED:
			pools.consume_stamina_up_to(result.stamina_damage)
			if controller != null:
				controller.on_block_impact(result.notes == "failed_parry")
		HitResult.Outcome.GUARD_BROKEN:
			pools.consume_stamina_up_to(result.stamina_damage)
	if result.health_damage > 0:
		pools.damage_health(result.health_damage)
		if combatant.unkillable and pools.health < 1.0:
			pools.health = 1.0
	# Every resolved exchange counts as combat for both sides - including evaded (dodged) and
	# immune hits - so fury never decays while a fight is actually going on.
	if result.outcome != HitResult.Outcome.IGNORED:
		pools.mark_combat()
		if attacker != null:
			attacker.combatant.pools.mark_combat()
	if pools.health <= 0.0 and not combatant.dead and not combatant.unkillable:
		combatant.dead = true
		result.killed = true
		if controller != null:
			controller.kill()
	if not result.killed:
		if result.outcome == HitResult.Outcome.GUARD_BROKEN:
			stagger(result.stagger_s, "guard_broken")
		elif result.outcome == HitResult.Outcome.HIT and result.poise_damage > 0.0:
			if combatant.poise.add(result.poise_damage):
				result.poise_broken = true
				stagger(combatant.poise.stagger_s, "poise_broken")
	result.defender_health_after = pools.health
	if result.knockback_speed > 0.0 and not result.killed and actor.has_method("apply_knockback"):
		var dir := actor.global_position - hit.attacker_position
		dir.y = 0.0
		actor.apply_knockback(dir.normalized() if dir.length_squared() > 1e-6 else Vector3.ZERO,
			result.knockback_speed)
	Events.hit_resolved.emit(Sim.tick, result)
	hit_taken.emit(result)
	if attacker != null:
		attacker._on_hit_landed(result, self)
	if result.killed:
		died.emit(hit.attacker_id)
		if actor.has_method("on_entity_died"):
			actor.on_entity_died(hit.attacker_id)
		Events.entity_died.emit(Sim.tick, entity_id, hit.attacker_id)


func _on_hit_landed(result: HitResult, target: CombatEntity) -> void:
	if combatant.dead:
		return
	var hit := result.event
	if hit.has_tag("BasicAttack") and result.dealt_damage() and target.combatant.grants_fury \
			and not _fury_instances.has(hit.instance_id):
		_fury_instances[hit.instance_id] = true
		combatant.pools.add_fury(float(combatant.fury_gain.get("basic_attack", 0.0)))
		if _fury_instances.size() > 64:
			_fury_instances.erase(_fury_instances.keys()[0])
	if result.killed and target.combatant.grants_fury:
		combatant.pools.add_fury(float(combatant.fury_gain.get("kill", 0.0)))
	hit_landed.emit(result)


func apply_poise_damage(amount: float, reason: String) -> void:
	if combatant.dead or amount <= 0.0:
		return
	if combatant.poise.add(amount):
		stagger(combatant.poise.stagger_s, reason)


func stagger(seconds: float, reason: String) -> void:
	if combatant.dead:
		return
	if controller != null:
		if not controller.apply_stagger(seconds, reason):
			return
	else:
		combatant.poise.begin_stagger()
		combatant.poise.end_stagger()
	staggered.emit(seconds, reason)
	Events.staggered.emit(Sim.tick, entity_id, seconds, reason)
