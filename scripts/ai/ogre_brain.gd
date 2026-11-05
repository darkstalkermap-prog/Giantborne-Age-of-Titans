class_name OgreBrain
extends EnemyBrain
## Ogre (spec 10 "Slow heavy strikes and stagger resistance; recovery punish"; plan §3.12, §4.4).
##
## The shared melee approach - close to the target's legs, take one of its two attack tokens,
## strike, pause - with the ogre's two super-armoured strikes: the smash (a ground pulse all round
## the ogre, circle telegraph r 3.5 m) and the sweep (a 120 degree sector in front, cone
## telegraph). Both are picked by range band (ai_min_range_m / ai_max_range_m from the target's
## capsule surface) and the record's weights while the ogre faces its target; a target beside or
## behind it inside the smash's band gets the smash at once (it needs no facing), so circling the
## slow-turning ogre (90 degrees/s) is answered by the smash. The counterplay is the long recovery
## after each strike: poise taken there counts x3.5 (poise.recovery_mult), and super armour does
## not cover it, so one heavy staggers the ogre at any stage. Morale: ignored (ignores_morale).


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	if state == AIState.APPROACH and seen and memory_ok and target_alive and now >= strike_ready_tick:
		var radius := float(perception.get("target_radius", 0.85))
		var in_range := distance <= float(ai.get("attack_range_m", 2.5)) + radius
		var facing_ok := absf(float(perception.get("facing_deg", 180.0))) <= ATTACK_FACING_DEG
		if in_range and not facing_ok:
			var all_round := all_round_attack(distance - radius)
			if all_round != "":
				face_point = target_pos
				_stop_moving()
				if holds_token or request_token.call():
					holds_token = true
					attack_request = all_round
					_set_state(AIState.ATTACK)
				return
	super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)


## The first attack whose telegraph is a circle (it hits all round) and whose band holds `edge_m`;
## "" when none fits.
func all_round_attack(edge_m: float) -> String:
	for id in attacks_in_range(edge_m):
		if entry_facing_deg(id) >= 180.0:
			return id
	return ""


## By range: a weighted pick among the attacks whose band holds the target's distance; the
## all-round one when the target is not in front; the first attack when none fits.
func _choose_attack() -> String:
	var edge := float(perception.get("distance", 0.0)) - float(perception.get("target_radius", 0.85))
	if absf(float(perception.get("facing_deg", 0.0))) > ATTACK_FACING_DEG:
		var all_round := all_round_attack(edge)
		if all_round != "":
			return all_round
	var id := choose_attack_in_range(edge)
	return id if id != "" else super()
