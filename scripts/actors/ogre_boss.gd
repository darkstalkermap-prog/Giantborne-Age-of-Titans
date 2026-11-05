class_name OgreBoss
extends EnemyActor
## The Ogre King (enemy.ogre_king, archetype boss; spec 10, decision 27, plan §3.12 design 2): an
## 8.5 m ogre on the giant nav layer (4) with an OgreBossBrain. Group "bosses".
##
## Phases (EnemyActor's and EnemyBrain's P11a sections): every tick, before its step, the actor
## feeds the brain its health fraction; the first time it is at or below 50 % the brain enters
## phase 2, the actor announces it once (Events.boss_phase_changed) and forces the 1.5 s phase
## roar (super armour, a circle telegraph, no damage). Its two-hit combo chains combo 1 into
## combo 2 (queue_chain_next after each step).
##
## The charge (phase 2): during its 0.9 s windup the king turns toward its target at 90 degrees/s
## (its walk turn rate is 80); then the action's `motion` (EnemyActor P04) runs it straight ahead at
## 15 m/s with no steering for up to 6 s, ending against WORLD geometry - the arena wall or a
## pillar - in a forced boss_wall_recover (2.5 s, the punish window), or on its cap in its own
## 1.4 s recovery. While it runs, the king's body ignores other actors (it never stops on the
## giant), and its hit is the body_sweep shape registered on its own runner: the king's capsule
## swept from the previous tick's position to this one, one hit per target per charge, the giant
## knocked aside off the charge line. Unblockable and unparryable, like the slam.
##
## Never grabbable (Grab immunity in data, can_be_grabbed() false), ignores morale and Fear.

const GROUP := "bosses"
## The charge's windup turns this fast (degrees/s) toward the target (plan §3.12).
const CHARGE_TURN_DEG_S := 90.0
## The body sweep's capsule is this much wider than the king's own.
const BODY_SWEEP_MARGIN_M := 0.25
## How far beside the charge line the body sweep's knockback origin sits (it shoves sideways).
const SHOVE_SIDE_M := 1.0

## How many charges ended against stone (forced boss_wall_recover) / on their cap (tests, debug).
var wall_stops := 0
var cap_stops := 0
var _sweep_instance := -1
var _sweep_prev := Vector3.ZERO
var _base_collision_mask := -1
var _charge_counted := -1


func _ready() -> void:
	add_to_group(GROUP)
	super()
	_base_collision_mask = collision_mask
	runner.register_shape("body_sweep", _run_body_sweep)
	install_boss_hooks()


func _make_brain() -> EnemyBrain:
	return OgreBossBrain.new(entity.entity_id, record, Sim.DEFAULT_SEED ^ hash(entity.entity_id))


func sim_step(tick: int, dt: float) -> void:
	update_boss_phase()
	super(tick, dt)
	queue_chain_next()
	_count_charge_end()


## The current phase (1-based) and how many there are (the boss bar's pips).
func boss_phase() -> int:
	return brain.boss_phase() if brain != null else 0


func phase_count() -> int:
	return brain.boss_phase_count() if brain != null else 0


## True while a charge (an action tagged Charge) runs in `phase` (ActionDef.Phase).
func is_charging(phase: int = ActionDef.Phase.ACTIVE) -> bool:
	var a := controller.action if controller != null else null
	return a != null and a.has_tag("Charge") and controller.phase() == phase


func can_be_grabbed() -> bool:
	return false


func _turn_rate_deg_s() -> float:
	if is_charging(ActionDef.Phase.WINDUP):
		return CHARGE_TURN_DEG_S
	return super()


## While a charge runs its body ignores other actors (WORLD, breakables and blockers still stop
## it), so it ends against stone, never on the giant; then the base motion runs. Never true while
## the king walks home on a leash (the base steering moves it then; its encounter has no leash).
func _custom_movement(dt: float) -> bool:
	if _base_collision_mask >= 0:
		var want := _base_collision_mask & ~HitQueryAdapter.LAYER_ACTORS if is_charging() else _base_collision_mask
		if collision_mask != want:
			collision_mask = want
	var moved: bool = super(dt)
	return moved and not is_returning()


## Counts how the last charge ended (wall_stops: its motion ended against a wall; cap_stops: its
## active phase ran out).
func _count_charge_end() -> void:
	if motion_end_reason == "" or _motion_instance < 0 or _charge_counted == _motion_instance:
		return
	var a := GameData.get_action(controller.action_id()) if controller != null else null
	if motion_end_reason == "wall":
		_charge_counted = _motion_instance
		wall_stops += 1
	elif motion_end_reason == "phase" and a != null and a.has_tag("Charge"):
		_charge_counted = _motion_instance
		cap_stops += 1


# --------------------------------------------------------------------------- body sweep

## The charge's hit (hit_shape body_sweep): the king's capsule (radius + BODY_SWEEP_MARGIN_M, its
## height) swept from where it stood last tick to where it stands now; HitFactory dedupes per
## target and instance. Each hit's attacker position lies beside the target off the charge line,
## so the knockback shoves the giant aside.
func _run_body_sweep(a: ActionDef, tick: int) -> void:
	var cur := global_position
	if _sweep_instance != controller.instance_id:
		_sweep_instance = controller.instance_id
		_sweep_prev = cur
	var prev := _sweep_prev
	_sweep_prev = cur
	var r := float(record.get("capsule_radius_m", 2.0)) + BODY_SWEEP_MARGIN_M
	var h := maxf(float(record.get("height_m", 8.5)), 2.0 * r)
	var lo := Vector3.UP * r
	var hi := Vector3.UP * (h - r)
	var cands := HitQueryAdapter.sweep_capsule(get_world_3d().direct_space_state, entity,
		attack_origin_global(), prev + lo, prev + hi, cur + lo, cur + hi, r)
	for c: Dictionary in cands:
		var t: CombatEntity = c.entity
		var ctx := runner.context()
		ctx.attacker_position = shove_origin(t.actor.global_position)
		HitFactory.queue(ctx, a, [c], 0, tick)


## The point a body-sweep hit on a target at `target_pos` comes "from": SHOVE_SIDE_M beside the
## target, on the charge line's side, so the knockback pushes it off the line (to the king's
## right when it stands right on the line).
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


# --------------------------------------------------------------------------- presentation

## The ActorRig keys: the charge leans in with both arms low and forward; the wall recovery
## reels (shown like a stagger).
func get_rig_state() -> Dictionary:
	var s := super()
	var a := controller.action
	if a != null and a.has_tag("Charge"):
		var phase := controller.phase()
		if phase == ActionDef.Phase.WINDUP:
			s["pose_override"] = {"arm": Vector2(35.0, -20.0), "off": Vector2(-35.0, -20.0), "exact": false}
		elif phase == ActionDef.Phase.ACTIVE:
			s["pose_override"] = {"arm": Vector2(8.0, -5.0), "off": Vector2(-8.0, -5.0), "exact": false}
	elif a != null and a.id == "ability.boss_wall_recover":
		s["staggered"] = true
	return s


func get_debug_info() -> Dictionary:
	var d := super()
	d["phase"] = "%d/%d" % [boss_phase(), phase_count()]
	d["next"] = brain.current_sequence_entry() if brain != null else ""
	d["charges"] = "%d wall, %d cap" % [wall_stops, cap_stops]
	return d
