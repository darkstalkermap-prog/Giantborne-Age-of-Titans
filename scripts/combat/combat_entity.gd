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
##   on_morale_delta(delta: float, source_id: String)   morale damage from hits (enemies)
## and may expose the properties entity_id / world_id (stable id) and faction (String).
##
## Statuses: apply_status() / heal() change state and then emit status_applied / healed; the
## Sim status pass calls tick_statuses() for every entity in id order after hit resolution.
##
## Lock anchors (P11a): lock_anchors() lists Anchors/{Torso,KneeL,KneeR} where the actor has
## them; lock_anchor_position(viewer_height) is what lock framing, lock line of sight and the
## HUD's lock marker aim at (a knee of a target much taller than the viewer, else the torso).

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
## Faction of a NEUTRAL actor ("village"); read from the actor's `faction` property in _ready.
## "" for dummies, props and the player. TargetingRules.player_may_target uses it.
var faction := ""
## Sim tick of the death (-1 while alive). A dead shooter's projectiles still land unless it
## died on the tick they resolve (Sim._resolve_hits).
var died_tick := -1
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
	var f: Variant = actor.get("faction")
	if typeof(f) == TYPE_STRING:
		faction = f
	var rec := GameData.get_record(definition_id)
	if rec.is_empty():
		push_error("CombatEntity %s: unknown definition '%s'" % [entity_id, definition_id])
	var height := height_override_m
	if height <= 0.0 and rec.has("growth_profile"):
		# The player's height comes from its current growth profile, not the base record.
		height = float(GameData.get_record(str(rec.growth_profile)).get("height_m", -1.0))
	combatant = Combatant.from_record(entity_id, rec, height)
	combatant.derived_changed.connect(_on_derived_changed)
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


# --------------------------------------------------------------------------- lock anchors (P11a)

## The Anchors/<name> nodes lock-on may frame (plan §3.12 design 3, spec 5): the torso, then the
## knees of a large target (the ogre, the Ogre King). Every one belongs to this one entity, so
## whichever is framed, the hits land on the one health pool.
const LOCK_ANCHOR_NAMES := ["Torso", "KneeL", "KneeR"]
## A target at least this many times the viewer's height is framed at its lowest lock anchor.
const LOW_ANCHOR_HEIGHT_RATIO := 1.3

var _lock_anchors: Array[Node3D] = []


## This entity's lock anchors: its anchor (the torso) first, then those Anchors/<name> of
## LOCK_ANCHOR_NAMES the actor has. Empty only for an entity without any anchor.
func lock_anchors() -> Array[Node3D]:
	for a in _lock_anchors:
		if not is_instance_valid(a):
			_lock_anchors.clear()
			break
	if _lock_anchors.is_empty() and actor != null:
		if anchor != null:
			_lock_anchors.append(anchor)
		for anchor_name: String in LOCK_ANCHOR_NAMES:
			var n := actor.get_node_or_null(NodePath("Anchors/" + anchor_name)) as Node3D
			if n != null and not _lock_anchors.has(n):
				_lock_anchors.append(n)
	return _lock_anchors


## The point lock framing, the lock's line of sight and the HUD's lock marker use for a viewer
## `viewer_height` metres tall: the lowest lock anchor (a knee) when this entity is at least
## LOW_ANCHOR_HEIGHT_RATIO times as tall as the viewer - so the camera never looks steeply up
## at the 8.5 m Ogre King - otherwise anchor_position() (the torso).
func lock_anchor_position(viewer_height: float) -> Vector3:
	if viewer_height > 0.0 and combatant != null \
			and combatant.height_m >= LOW_ANCHOR_HEIGHT_RATIO * viewer_height - 1e-6:
		var low: Node3D = null
		for a in lock_anchors():
			if low == null or a.global_position.y < low.global_position.y - 1e-4:
				low = a
		if low != null:
			return low.global_position
	return anchor_position()


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
			# The parrier's outgoing poise buffs (Titan Surge +25 %) apply to the poise its parry
			# deals, as they do to its blows; the result reports what was applied (P11a, M2 gate
			# follow-up).
			result.attacker_poise_damage *= combatant.outgoing_poise_mult()
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
		died_tick = Sim.tick
		result.killed = true
		if controller != null:
			controller.kill()
	if not result.killed:
		if result.outcome == HitResult.Outcome.GUARD_BROKEN:
			stagger(result.stagger_s, "guard_broken")
		elif result.outcome == HitResult.Outcome.HIT and result.poise_damage > 0.0:
			# The recovery punish: poise damage taken in the own attack's RECOVERY phase is
			# multiplied (ogre and boss 3.5). result.poise_damage reports what was applied.
			result.poise_damage *= _poise_taken_mult()
			if combatant.poise.add(result.poise_damage):
				result.poise_broken = true
				stagger(_poise_break_stagger_s(hit), "poise_broken")
	result.defender_health_after = pools.health
	if result.knockback_speed > 0.0 and not result.killed and actor.has_method("apply_knockback"):
		var dir := actor.global_position - hit.attacker_position
		dir.y = 0.0
		actor.apply_knockback(dir.normalized() if dir.length_squared() > 1e-6 else Vector3.ZERO,
			result.knockback_speed)
	_apply_on_hit_effects(result, attacker)
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


## On HIT: the hit's on_hit_statuses (on BLOCKED only the entries with on_blocked), then its
## morale damage (HIT or BLOCKED) through actor.on_morale_delta when the actor has one.
## Nothing happens for a target this hit killed.
func _apply_on_hit_effects(result: HitResult, _attacker: CombatEntity) -> void:
	if result.killed or combatant.dead:
		return
	var blocked := result.outcome == HitResult.Outcome.BLOCKED
	if result.outcome != HitResult.Outcome.HIT and not blocked:
		return
	var hit := result.event
	for entry: Variant in hit.on_hit_statuses:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if blocked and not bool(entry.get("on_blocked", false)):
			continue
		apply_status(str(entry.get("status", "")), float(entry.get("magnitude", NAN)),
			float(entry.get("duration_s", -1.0)), hit.attacker_id)
	if hit.morale_damage > 0.0 and actor.has_method("on_morale_delta"):
		actor.on_morale_delta(-hit.morale_damage, hit.attacker_id)


## poise.recovery_mult while this entity's controller is in the RECOVERY phase of an attack.
func _poise_taken_mult() -> float:
	if controller != null and controller.action != null and controller.action.is_attack() \
			and controller.phase() == ActionDef.Phase.RECOVERY:
		return combatant.poise.recovery_mult
	return 1.0


## A poise break by an attacker at least twice this entity's height staggers for
## poise.stagger_vs_larger_s when that is set, otherwise poise.stagger_s.
func _poise_break_stagger_s(hit: HitEvent) -> float:
	var larger := hit != null and hit.attacker_height_m >= 2.0 * combatant.height_m - 1e-6
	return combatant.poise.stagger_duration(larger)


func apply_poise_damage(amount: float, reason: String) -> void:
	if combatant.dead or amount <= 0.0:
		return
	if combatant.poise.add(amount * _poise_taken_mult()):
		stagger(combatant.poise.stagger_s, reason)


# --------------------------------------------------------------------------- statuses and heals

## Applies a status record (GameData.get_status). magnitude NAN = the record's default;
## duration_s <= 0 = the record's duration. Returns false for an unknown status, a dead entity
## or a status immunity (status_immunities vs the status tags). Emits status_applied.
func apply_status(status_id: String, magnitude: float = NAN, duration_s: float = -1.0,
		source_id: String = "") -> bool:
	var def := GameData.get_status(status_id)
	if def == null:
		push_error("CombatEntity %s: unknown status '%s'" % [entity_id, status_id])
		return false
	if not is_alive():
		return false
	var duration := duration_s if duration_s > 0.0 else def.duration_s()
	if not combatant.statuses.apply(def, magnitude, duration, source_id, Sim.tick,
			combatant.status_immunities):
		return false
	Events.status_applied.emit(Sim.tick, entity_id, status_id, source_id, duration)
	return true


## Restores health (capped at the maximum; nothing once dead) and emits healed with the amount
## actually gained (no event when nothing was gained).
func heal(amount: float, source_id: String) -> void:
	if not is_alive() or amount <= 0.0:
		return
	var pools := combatant.pools
	var before := pools.health
	pools.heal(amount)
	var gained := pools.health - before
	if gained > 0.0:
		Events.healed.emit(Sim.tick, entity_id, gained, source_id)


## Called by the Sim status pass once per tick: periodic heals, then expiry (status_expired).
func tick_statuses(now: int) -> void:
	if combatant == null or combatant.statuses.is_empty():
		return
	for effect: Dictionary in combatant.statuses.tick(now):
		match str(effect.get("type", "")):
			"heal":
				heal(float(effect.amount), str(effect.get("source", "")))
			"expired":
				Events.status_expired.emit(now, entity_id, str(effect.id))


func _on_derived_changed() -> void:
	if controller != null:
		controller.recovery_scale = combatant.recovery_scale()


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
