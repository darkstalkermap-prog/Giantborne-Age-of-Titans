class_name AttackRunner
extends RefCounted
## Runs the hit queries of an actor's current action, one handler per hit shape (plan §2.7.2).
## Shared by the player and every enemy, so a new shape is one registered handler instead of
## another copy of the sweep code.
##
## The actor provides (duck typed):
##   weapon_segment_global(action, f) -> PackedVector3Array   shoulder/hand -> weapon tip
##   attack_origin_global() -> Vector3                         occlusion origin of the sweep
##   current_weapon() -> Dictionary                            weapon record (damage multiplier)
##   current_growth_stage() -> int                             HitEvent.attacker_growth_stage
##   weapon_hit_radius() -> float                              capsule radius of the weapon sweep
##
## Shapes: P02 `weapon_arc` and `cylinder_pulse`; P03 `sector_pulse`, `projectile`, and the
## `self_statuses` of any action (applied when it enters ACTIVE: Stone Skin, Mend, Titan Surge
## use hit_shape `none`). Later packages register theirs below their anchor in _init (P09 enemy
## ranged aim; P11a body_sweep on its own runner) or with register_shape() from their own code
## (P07 grab). Telegraphs are emitted by EnemyActor (P04), not here.
##
## Pulses (P03): the radius follows radius_from "melee_reach" (the actor's profile reach), else
## radius_by_stage_m[stage - 1], else radius_m; every cylinder pulse, sector pulse and
## projectile splash is an area effect (the player's skip neutral bystanders). Handlers emit
## Events.ability_effect: "sector", "roar" (a pulse with morale damage), "self_buff", "cast".

var actor: Node3D
var entity: CombatEntity
var controller: CombatController
## The player reports a "clank" when a swing first meets world geometry; enemies do not, so the
## clank counts tests and feedback see stay the player's.
var emit_clank := false
var prev_segment := PackedVector3Array()
## P03: set by an enemy actor at its aim-lock tick; used and cleared by the projectile handler
## for aim "target". INF = none.
var aim_point := Vector3.INF
## P03: Callable(a: ActionDef, spec: Dictionary) -> {"origin": Vector3, "aim": Vector3} that
## says where a projectile starts and what it flies at. PlayerAttack sets it (launch offset x k,
## lock-or-camera aim); without one, default_launch() is used (enemies).
var launch_resolver := Callable()

var _handlers: Dictionary = {}   ## hit_shape -> Callable(a: ActionDef, tick: int)
var _clanked_instance := -1


func _init(p_actor: Node3D, p_entity: CombatEntity, p_controller: CombatController) -> void:
	actor = p_actor
	entity = p_entity
	controller = p_controller
	register_shape("weapon_arc", _run_weapon_arc)
	register_shape("cylinder_pulse", _run_cylinder_pulse)
	## @anchor P03
	register_shape("sector_pulse", _run_sector_pulse)
	register_shape("projectile", _run_projectile)
	if controller != null:
		controller.phase_entered.connect(_on_phase_entered)
	## @anchor P07
	## @anchor P09
	## @anchor P11a


## handler(a: ActionDef, tick: int) runs every ACTIVE tick of an action with this hit_shape.
## Registering a shape again replaces its handler.
func register_shape(shape: String, handler: Callable) -> void:
	_handlers[shape] = handler


func has_shape(shape: String) -> bool:
	return _handlers.has(shape)


## Called once per tick by the actor, after movement. Outside an action's ACTIVE phase it only
## forgets the previous weapon segment, so the next sweep starts fresh.
func run(tick: int) -> void:
	var a := controller.action
	if a == null or controller.phase() != ActionDef.Phase.ACTIVE:
		prev_segment = PackedVector3Array()
		return
	var handler: Callable = _handlers.get(a.hit_shape, Callable())
	if handler.is_valid():
		handler.call(a, tick)


## The attack context for the action running now.
func context() -> AttackContext:
	var ctx := AttackContext.new()
	ctx.entity = entity
	ctx.instance_id = controller.instance_id
	ctx.weapon = actor.current_weapon()
	ctx.growth_stage = actor.current_growth_stage()
	ctx.attacker_position = actor.global_position
	ctx.registry = controller.hit_registry
	return ctx


## Forget sweep state (a new action started, or the actor was reset).
func reset() -> void:
	prev_segment = PackedVector3Array()
	aim_point = Vector3.INF


# --------------------------------------------------------------------------- shapes

## Swept weapon capsule from the previous tick's segment to this tick's, so fast swings never
## tunnel. The first world contact of an instance may report a clank (player only).
func _run_weapon_arc(a: ActionDef, tick: int) -> void:
	var space := actor.get_world_3d().direct_space_state
	var origin: Vector3 = actor.attack_origin_global()
	var cur: PackedVector3Array = actor.weapon_segment_global(a, controller.active_fraction())
	var prev := prev_segment
	if prev.size() != 2:
		prev = actor.weapon_segment_global(a, controller.active_fraction_prev())
	var cands := HitQueryAdapter.sweep_capsule(space, entity, origin, prev[0], prev[1],
		cur[0], cur[1], float(actor.weapon_hit_radius()))
	prev_segment = cur
	HitFactory.queue(context(), a, cands, 0, tick)
	if emit_clank and _clanked_instance != controller.instance_id:
		var wall := HitQueryAdapter.first_world_hit(space, origin, cur[1], [])
		if not wall.is_empty():
			_clanked_instance = controller.instance_id
			Events.attack_clanked.emit(tick, entity.entity_id, controller.instance_id, wall.position)


## Vertical cylinder around the actor on the first active tick (Heavy Footfall, Thunder Roar):
## pulse_radius(), height_m, occlusion from 0.8 m above the feet, pulse id 1, an area effect.
## A pulse with morale damage is a roar (ability_effect "roar").
func _run_cylinder_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var space := actor.get_world_3d().direct_space_state
	var feet := actor.global_position
	var radius := pulse_radius(a)
	var center := feet + Vector3.UP * (a.height_m * 0.5)
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, radius, a.height_m,
		feet + Vector3.UP * 0.8)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, feet, radius)
	if float(a.param("morale_damage", 0.0)) > 0.0:
		Events.ability_effect.emit(tick, entity.entity_id, a.id, "roar", feet, radius, facing_yaw(), 360.0)


# --------------------------------------------------------------------------- P03 shapes

## The pulse radius of `a` for this actor now: the profile's melee_reach_m for radius_from
## "melee_reach", else radius_by_stage_m[growth stage - 1] (the last entry beyond the list),
## else radius_m.
func pulse_radius(a: ActionDef) -> float:
	if str(a.param("radius_from", "fixed")) == "melee_reach":
		var reach := _melee_reach()
		if reach > 0.0:
			return reach
	var by_stage: Variant = a.param("radius_by_stage_m")
	if typeof(by_stage) == TYPE_ARRAY and not (by_stage as Array).is_empty():
		var list: Array = by_stage
		var i := clampi(int(actor.current_growth_stage()) - 1, 0, list.size() - 1)
		return float(list[i])
	return a.radius_m


## The actor's melee reach: its growth profile's melee_reach_m (the giant), otherwise its arm
## plus weapon length (enemies); 0 when unknown.
func _melee_reach() -> float:
	var profile: Variant = actor.get("profile")
	if typeof(profile) == TYPE_DICTIONARY and (profile as Dictionary).has("melee_reach_m"):
		return float(profile.melee_reach_m)
	var arm: Variant = actor.get("arm_length")
	var weapon_len: Variant = actor.get("weapon_length")
	if typeof(arm) == TYPE_FLOAT and typeof(weapon_len) == TYPE_FLOAT:
		return float(arm) + float(weapon_len)
	return 0.0


## The actor's facing (yaw, radians; 0 faces -Z).
func facing_yaw() -> float:
	var fwd := -actor.global_transform.basis.z
	return TargetingRules.yaw_of(fwd) if Vector2(fwd.x, fwd.z).length_squared() > 1e-8 else 0.0


## Sweeping Blow: a cylinder pulse (pulse_radius(), height = height_m or the actor's height)
## on the first active tick, kept to |yaw delta| <= sector_deg / 2 of the facing, with
## occlusion from the attack origin. Pulse id 1, an area effect.
func _run_sector_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var space := actor.get_world_3d().direct_space_state
	var feet := actor.global_position
	var radius := pulse_radius(a)
	var height := a.height_m if a.height_m > 0.0 else entity.combatant.height_m
	var center := feet + Vector3.UP * (height * 0.5)
	var origin: Vector3 = actor.attack_origin_global()
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, radius, height, origin)
	var yaw := facing_yaw()
	var arc_deg := float(a.param("sector_deg", 360.0))
	var half := deg_to_rad(arc_deg * 0.5)
	var inside: Array = []
	for c: Dictionary in cands:
		var to: Vector3 = (c.point as Vector3) - feet
		to.y = 0.0
		if to.length_squared() < 1e-6 \
				or absf(TargetingRules.yaw_delta(yaw, TargetingRules.yaw_of(to))) <= half + 1e-4:
			inside.append(c)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, inside, 1, tick)
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "sector", feet, radius, yaw, arc_deg)


## Projectile actions launch on their first active tick: the launch resolver (or
## default_launch) gives the origin and aim point, Projectile.launch_velocity the velocity, and
## the level's ProjectileSystem takes it from there. aim_point is cleared after every launch.
func _run_projectile(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var spec := Projectile.spec_for(a)
	var launch: Dictionary = launch_resolver.call(a, spec) if launch_resolver.is_valid() \
		else default_launch(a, spec)
	aim_point = Vector3.INF
	var origin: Vector3 = launch.get("origin", actor.attack_origin_global())
	var aim: Vector3 = launch.get("aim", origin + -actor.global_transform.basis.z * float(spec.range_m))
	var velocity := Projectile.launch_velocity(origin, aim, spec)
	var system := ProjectileSystem.instance(actor.get_tree())
	system.spawn(entity, a, origin, velocity, context())
	Events.ability_effect.emit(tick, entity.entity_id, a.id, "cast", origin, 0.0, facing_yaw(), 0.0)


## Launch point and aim for actors without a launch resolver (enemies): launch_offset_m in the
## actor's own space (or its attack origin), aimed per spec.aim - "target": aim_point when the
## actor stored one at its aim-lock tick, otherwise the anchor of its target at launch (the
## brain's target, else the nearest living entity it may damage); "forward": straight ahead at
## range. Player-only modes (lock_or_camera, camera) fall back to "target" here.
func default_launch(_a: ActionDef, spec: Dictionary) -> Dictionary:
	var offset: Vector3 = spec.get("launch_offset", Vector3.INF)
	var origin: Vector3 = actor.to_global(offset) if offset != Vector3.INF else actor.attack_origin_global()
	var forward := -actor.global_transform.basis.z
	var aim := origin + forward * float(spec.get("range_m", 25.0))
	if str(spec.get("aim", "target")) != "forward":
		if aim_point != Vector3.INF:
			aim = aim_point
		else:
			var t := _default_target()
			if t != null:
				aim = t.anchor_position()
	return {"origin": origin, "aim": aim}


## The brain's living target (enemies), else the nearest living entity this actor may damage.
func _default_target() -> CombatEntity:
	var brain: Variant = actor.get("brain")
	if brain is Object and "target_id" in brain and str(brain.get("target_id")) != "":
		var t := Sim.get_entity(str(brain.get("target_id")))
		if t != null and t.is_alive():
			return t
	var best: CombatEntity = null
	var best_d := INF
	for e in Sim.entities():
		if e == entity or not e.is_alive() or not CombatEntity.can_damage(entity.team, e.team):
			continue
		var d := actor.global_position.distance_squared_to(e.actor.global_position)
		if d < best_d:
			best = e
			best_d = d
	return best


## self_statuses are applied when an action enters ACTIVE (Stone Skin, Mend, Titan Surge),
## whatever its hit shape. Emits ability_effect "self_buff" when one was applied.
func _on_phase_entered(a: ActionDef, _instance_id: int, phase: int) -> void:
	if phase != ActionDef.Phase.ACTIVE or a == null:
		return
	var list: Variant = a.param("self_statuses")
	if typeof(list) != TYPE_ARRAY or (list as Array).is_empty():
		return
	var applied := false
	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if entity.apply_status(str(entry.get("status", "")), float(entry.get("magnitude", NAN)),
				float(entry.get("duration_s", -1.0)), entity.entity_id):
			applied = true
	if applied:
		Events.ability_effect.emit(Sim.tick, entity.entity_id, a.id, "self_buff", actor.global_position,
			0.0, facing_yaw(), 0.0)
