class_name CavalryEnemy
extends EnemyActor
## A lancer on a warhorse (enemy.cavalry, archetype cavalry; P32, plan M6-M9 §2.10, §5.11): the
## shared EnemyActor glue with a CavalryBrain (charge, wheel away, re-charge) on a QuadrupedRig (the
## horse, its rider and lance merged into its body; hoof footfalls). 2.6 m tall, radius 0.9, on the
## large nav layer (2).
##
## The charge (an action tagged Charge, ability.cavalry_charge) runs on the base's scripted `motion`
## (a straight run behind its line telegraph); while it runs the horse ignores other actors - it rides
## through the giant's legs and through its own side's ranks, and walls, breakables and blockers still
## stop it - and its hit is the body_sweep registered on its own runner: the horse's capsule (+
## BODY_SWEEP_MARGIN_M) swept from the previous tick's position to this one, one hit per target per
## charge (max_hits_per_target), each coming from beside the target off the charge line so the
## knockback shoves it aside. The hit strikes as a 4 m attacker (the action's
## attacker_height_override_m: HitFactory).
##
## The wheel point (CavalryBrain.wheel_resolver): `distance` m from the target along the charge line,
## else WHEEL_STEP_DEG steps either side of it, made reachable on the horse's nav layer - each candidate
## a closest point and up to two paths, within the tick's path-query budget like the flee and firing
## searches (EnemyActor's P24b section: _search_affords; a search that stops for the budget resumes at
## its candidate at the next decision). Without a navmesh (tests, test levels) a candidate needs a clear
## line from the rider.
##
## A stage-4 giant can seize a staggered horse with both hands (mass medium, grab_attach two_hand; the
## grab point on its back, Anchors/Grab).

const BODY_SWEEP_MARGIN_M := 0.25
## How far beside the charge line a body-sweep hit's knockback origin sits (it shoves sideways).
const SHOVE_SIDE_M := 1.0
## Wheel candidates: straight on, then this many steps of WHEEL_STEP_DEG either side.
const WHEEL_STEP_DEG := 30.0
const WHEEL_STEPS := 2
const SEARCH_KEY := "wheel"

@onready var quad: QuadrupedRig = get_node_or_null("Visual") as QuadrupedRig

## Charges started (the action began; tests, debug).
var charges_started := 0
var _sweep_instance := -1
var _sweep_prev := Vector3.ZERO
var _base_collision_mask := -1


func _ready() -> void:
	super()
	_base_collision_mask = collision_mask
	runner.register_shape("body_sweep", _run_body_sweep)
	controller.action_started.connect(_on_cavalry_action_started)


func _make_brain() -> EnemyBrain:
	var b := CavalryBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))
	b.wheel_resolver = _resolve_wheel_point
	return b


func cavalry_brain() -> CavalryBrain:
	return brain as CavalryBrain


## True while a charge (an action tagged Charge) runs in `phase` (ActionDef.Phase).
func is_charging(phase: int = ActionDef.Phase.ACTIVE) -> bool:
	var a := controller.action if controller != null else null
	return a != null and a.has_tag(CavalryBrain.CHARGE_TAG) and controller.phase() == phase


func _on_cavalry_action_started(action: ActionDef, _instance_id: int) -> void:
	if action != null and action.has_tag(CavalryBrain.CHARGE_TAG):
		charges_started += 1


## While a charge runs the horse ignores other actors (see the class notes); then the base motion runs.
func _custom_movement(dt: float) -> bool:
	if _base_collision_mask >= 0:
		var want := _base_collision_mask & ~HitQueryAdapter.LAYER_ACTORS if is_charging() else _base_collision_mask
		if collision_mask != want:
			collision_mask = want
	var moved: bool = super(dt)
	return moved and not is_returning()


# --------------------------------------------------------------------------- the charge's hit

## The charge's hit (hit_shape body_sweep): the horse's capsule swept from where it stood last tick to
## where it stands now; HitFactory dedupes per target and instance (one hit per charge).
func _run_body_sweep(a: ActionDef, tick: int) -> void:
	var cur := global_position
	if _sweep_instance != controller.instance_id:
		_sweep_instance = controller.instance_id
		_sweep_prev = cur
	var prev := _sweep_prev
	_sweep_prev = cur
	var r := float(record.get("capsule_radius_m", 0.9)) + BODY_SWEEP_MARGIN_M
	var h := maxf(float(record.get("height_m", 2.6)), 2.0 * r)
	var lo := Vector3.UP * r
	var hi := Vector3.UP * (h - r)
	var cands := HitQueryAdapter.sweep_capsule(get_world_3d().direct_space_state, entity,
		attack_origin_global(), prev + lo, prev + hi, cur + lo, cur + hi, r)
	for c: Dictionary in cands:
		var t: CombatEntity = c.entity
		var ctx := runner.context()
		ctx.attacker_position = shove_origin(t.actor.global_position)
		HitFactory.queue(ctx, a, [c], 0, tick)


## The point a body-sweep hit on a target at `target_pos` comes "from": SHOVE_SIDE_M beside the target,
## on the charge line's side, so the knockback pushes it off the line.
func shove_origin(target_pos: Vector3) -> Vector3:
	var dir := Vector3(-sin(facing_yaw), 0.0, -cos(facing_yaw))
	var to := target_pos - global_position
	to.y = 0.0
	var side := to - dir * to.dot(dir)
	if side.length() < 0.3:
		side = Vector3(-dir.z, 0.0, dir.x)
	var from := target_pos - side.normalized() * SHOVE_SIDE_M
	from.y = target_pos.y
	return from


# --------------------------------------------------------------------------- the wheel

## CavalryBrain.wheel_resolver (see the class notes).
func _resolve_wheel_point(from: Vector3, threat: Vector3, dir: Vector3, distance: float) -> Vector3:
	var flat_dir := Vector3(dir.x, 0.0, dir.z)
	flat_dir = flat_dir.normalized() if flat_dir.length_squared() > 1e-6 else Vector3.FORWARD
	var level := nav_level()
	var layers := int(agent.navigation_layers)
	var use_nav := NavQuery.has_navigation(level, layers)
	var space := get_world_3d().direct_space_state
	for i in range(_search_start(SEARCH_KEY) if use_nav else 0, WHEEL_STEPS * 2 + 1):
		var k := ((i + 1) >> 1) * (1 if i % 2 == 1 else -1)   # 0, 1, -1, 2, -2
		var desired := threat + flat_dir.rotated(Vector3.UP, deg_to_rad(WHEEL_STEP_DEG * k)) * distance
		desired.y = from.y
		if use_nav:
			if not _search_affords():
				_search_stop(SEARCH_KEY, i)
				return Vector3.INF
			var q0 := NavQuery.queries_total
			var p := _reachable_point(level, from, NavQuery.closest_point(level, desired, layers), layers)
			_search_spend(q0)
			if p == Vector3.INF or _flat_len(p - threat) < distance * 0.5:
				continue   # unreachable, or snapped back close to the target
			_search_done(SEARCH_KEY)
			return p
		var lift := Vector3.UP * 1.0
		if HitQueryAdapter.line_clear(space, from + lift, desired + lift, SIGHT_MASK | LAYER_BLOCKER,
				entity.occlusion_rids):
			return desired
	_search_done(SEARCH_KEY)
	return Vector3.INF


# --------------------------------------------------------------------------- presentation

func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	if quad != null:
		quad.flash(strength, color)


## The rig keys; "lunging" while the charge runs (the horse stretched low at the gallop).
func get_rig_state() -> Dictionary:
	var s := super()
	s["lunging"] = is_charging()
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	var b := cavalry_brain()
	if b != null:
		d["cycle"] = "%s (%d charges, %d wheels)" % [b.cycle, b.charges, b.wheels]
	return d
