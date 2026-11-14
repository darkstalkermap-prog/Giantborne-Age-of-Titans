class_name MageBrain
extends EnemyBrain
## Mage (spec 10 "telegraphs slow/barrier attacks; interrupt or evade"; plan §3.9).
##
## The shared ranged rules (EnemyBrain._decide_ranged) with a 10-16 m band: the slowing bolt is
## its shot (an arcane projectile behind a 1.0 s line telegraph, aim committed at 60 %, one of the
## giant's two ranged tokens and a launch slot); the staff strike answers up close (a melee
## token). Its special is the barrier (a targets_ally cast: 1.2 s behind a circle telegraph, 30
## essence, 10 s cooldown): whenever it is ready the mage wards the most hurt ally within
## tactics.barrier_range_m (12 m) - the perception's "allies" list - or itself when no ally is
## more hurt. Every cast runs in CASTING and a hard stagger (poise 25) interrupts it with no hit
## and no refund.
##
## Outmatched it kites: the band grows x1.3 and it keeps to the band's far edge, so it falls back
## after every cast as the giant closes in. States other packages own go to the base rules.


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


func decide(tick: int, p_controller_state: int, my_position: Vector3, request_token: Callable,
		release_token: Callable) -> void:
	var held := firing_point
	super(tick, p_controller_state, my_position, request_token, release_token)
	keep_front_arc(held)   # P22: keep to the camera's side when a firing point there exists
	if state != AIState.ATTACK:
		_release_ranged()
	if state in [AIState.FLEE, AIState.ROUTED, AIState.DEAD, AIState.PATROL, AIState.IDLE]:
		if firing_point != Vector3.INF:
			_drop_firing_point()


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if not is_ranged_state():
		super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)
		return
	if _decide_outmatched(outmatched_behavior(), my_position, target_pos, distance, seen, memory_ok,
			target_alive, request_token, release_token):
		return
	_decide_ranged(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token,
		release_token, false, false)


## Outmatched: kite (the x1.3 band, held at its far edge).
func _decide_kite(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	if not is_ranged_state():
		return false
	_decide_ranged(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token,
		release_token, true, true)
	return true


func on_path_failed(my_position: Vector3) -> void:
	if not _ranged_path_failed(my_position):
		super(my_position)


## The barrier whenever it is ready (cooldown and essence), aimed at barrier_target().
func _ranged_special_attack(_my_position: Vector3, _target_pos: Vector3, _distance: float) -> String:
	for id in ally_casts():
		if _action_ready(id):
			ally_target_id = barrier_target()
			return id
	return ""


## Who the barrier is for: the most hurt ally within tactics.barrier_range_m (the perception's
## "allies": [{id, health_frac, distance}]), or this mage when nobody is more hurt than it.
func barrier_target() -> String:
	var reach := float(tactics.get("barrier_range_m", 12.0))
	var best := actor_id
	var best_frac := float(perception.get("self_health_frac", 1.0))
	for entry: Variant in perception.get("allies", []):
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		if float(entry.get("distance", INF)) > reach:
			continue
		var frac := float(entry.get("health_frac", 1.0))
		if frac < best_frac - 1e-6:
			best = str(entry.get("id", best))
			best_frac = frac
	return best


func _choose_attack() -> String:
	var edge := float(perception.get("distance", INF)) - float(perception.get("target_radius", 0.85))
	var close := _close_attack_for(edge)
	return close if close != "" else _ranged_shot()


## P22: the shot to take now, readied for where the giant's camera looks (drawn from outside its view,
## its windup lasts tactics.off_camera_aim_s: EnemyBrain.prepare_ranged_shot).
func _ranged_shot() -> String:
	var shot := super()
	prepare_ranged_shot(shot)
	return shot
