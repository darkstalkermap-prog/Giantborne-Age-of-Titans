class_name ArcherBrain
extends EnemyBrain
## Archer (spec 10 "keeps 12-20 m, seeks authored cover/elevation; pressure or throw"; plan §3.9).
##
## The shared ranged rules (EnemyBrain._decide_ranged): it holds a firing point in its band of
## tactics.preferred_min_m..preferred_max_m (12-20 m) - an elevation or cover marker that sees
## the giant, kept tactics.spread_m (6 m) from the other ranged allies, else a ring point -
## retreats to the band when the giant comes closer, kicks at its shins when it stands within
## the kick's band (about 2.5 m from a stage-1 giant's centre) holding a melee token, and shoots
## only when settled in the band with line of sight, one of the giant's two ranged tokens and a
## launch slot (tactics.launch_gap_s apart). The draw is 0.9 s behind a line telegraph; the aim
## commits at 60 % (decision 24).
##
## Outmatched (the giant at least tactics.outmatched_ratio times taller: stage 2 and up) it
## spreads: the band grows x1.3 (15.6-26 m, inside its 32 m sight) and the spread to 10 m.
## States other packages own (RETURN, STAND_DOWN) go to the base rules.


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


func decide(tick: int, p_controller_state: int, my_position: Vector3, request_token: Callable,
		release_token: Callable) -> void:
	super(tick, p_controller_state, my_position, request_token, release_token)
	if state != AIState.ATTACK:
		_release_ranged()   # the ranged token goes back once the shot's recovery is over
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


## Outmatched: spread (the x1.3 band and a 10 m spread).
func _decide_spread(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> bool:
	if not is_ranged_state():
		return false
	_decide_ranged(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token,
		release_token, true, false)
	return true


func on_path_failed(my_position: Vector3) -> void:
	if not _ranged_path_failed(my_position):
		super(my_position)


## The base weighted pick is only a fallback: the ranged rules choose explicitly (the kick up
## close, otherwise the shot).
func _choose_attack() -> String:
	var edge := float(perception.get("distance", INF)) - float(perception.get("target_radius", 0.85))
	var close := _close_attack_for(edge)
	return close if close != "" else _ranged_shot()
