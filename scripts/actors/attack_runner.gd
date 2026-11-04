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
## Shapes: P02 `weapon_arc` and `cylinder_pulse`. Later packages register theirs below their
## anchor in _init (P03 sector_pulse, projectile, none + self statuses; P09 enemy ranged aim;
## P11a body_sweep on its own runner) or with register_shape() from their own code (P07 grab).
## Telegraphs are emitted by EnemyActor (P04), not here.

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

var _handlers: Dictionary = {}   ## hit_shape -> Callable(a: ActionDef, tick: int)
var _clanked_instance := -1


func _init(p_actor: Node3D, p_entity: CombatEntity, p_controller: CombatController) -> void:
	actor = p_actor
	entity = p_entity
	controller = p_controller
	register_shape("weapon_arc", _run_weapon_arc)
	register_shape("cylinder_pulse", _run_cylinder_pulse)
	## @anchor P03
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


## Vertical cylinder around the actor on the first active tick (Heavy Footfall): radius_m,
## height_m, occlusion from 0.8 m above the feet, pulse id 1.
func _run_cylinder_pulse(a: ActionDef, tick: int) -> void:
	if not controller.is_first_active_tick():
		return
	var space := actor.get_world_3d().direct_space_state
	var feet := actor.global_position
	var center := feet + Vector3.UP * (a.height_m * 0.5)
	var cands := HitQueryAdapter.cylinder_pulse(space, entity, center, a.radius_m, a.height_m,
		feet + Vector3.UP * 0.8)
	var ctx := context()
	ctx.area_effect = true
	HitFactory.queue(ctx, a, cands, 1, tick)
	Events.area_pulse.emit(tick, entity.entity_id, a.id, feet, a.radius_m)
