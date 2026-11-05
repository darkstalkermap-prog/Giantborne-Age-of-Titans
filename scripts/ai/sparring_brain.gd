class_name SparringBrain
extends EnemyBrain
## The sparring post's "AI" (plan §3.13 design 6, §4.4): it swings its padded arms (the record's
## first attack, ability.sparring_swing) every training.swing_interval_s (3 s) while a target
## stands within training.trigger_radius_m (4 m, centre to centre); otherwise it waits. The first
## swing starts as soon as someone steps in; the cadence is kept when they step out and back.
##
## It never moves, never turns, never takes an attack token, never flees and is never aware of
## anyone (so it never defers a checkpoint or wakes an encounter): perceive() only remembers the
## target. States: IDLE (nobody near), ATTACK (swinging), RECOVER (waiting for the next swing),
## STAGGERED, DEAD (it cannot die; kept for completeness).

## Swing period and trigger distance (the record's training block).
var swing_interval_ticks := 180
var trigger_radius_m := 4.0
## The tick the next swing may start (-1: at once).
var next_swing_tick := -1
## Swings started so far (tests, debug).
var swings := 0


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	var training: Variant = record.get("training", {})
	if typeof(training) == TYPE_DICTIONARY:
		swing_interval_ticks = maxi(1, int(roundf(float(training.get("swing_interval_s", 3.0)) * TICK_RATE)))
		trigger_radius_m = float(training.get("trigger_radius_m", 4.0))


## Remembers the target (for the telegraph's target and the distance); never becomes aware.
func perceive(tick: int, snapshot: Dictionary) -> void:
	now = tick
	perception = snapshot
	aware = false
	if snapshot.get("exists", false):
		target_id = str(snapshot.get("target_id", ""))
		last_known = snapshot.get("position", last_known)


## Noises and blows change nothing: a training post does not hunt.
func on_noise(tick: int, _position: Vector3, _source_id: String, _certain: bool) -> void:
	now = tick
	aware = false


func on_ally_died(_tick: int = -1) -> void:
	pass


func decide(tick: int, p_controller_state: int, _my_position: Vector3, _request_token: Callable,
		_release_token: Callable) -> void:
	now = tick
	controller_state = p_controller_state
	attack_request = ""
	aware = false
	_stop()
	match controller_state:
		CombatController.State.DEAD:
			_set_state(AIState.DEAD)
			return
		CombatController.State.STAGGERED:
			_set_state(AIState.STAGGERED)
			return
		CombatController.State.ATTACKING, CombatController.State.CASTING:
			_set_state(AIState.ATTACK)
			return
	if not target_in_range():
		_set_state(AIState.IDLE)
		return
	if next_swing_tick >= 0 and now < next_swing_tick:
		_set_state(AIState.RECOVER)
		return
	attack_request = _choose_attack()
	if attack_request == "":
		return
	next_swing_tick = now + swing_interval_ticks
	swings += 1
	_set_state(AIState.ATTACK)


## True while a living target stands within trigger_radius_m (as last perceived).
func target_in_range() -> bool:
	return bool(perception.get("exists", false)) and bool(perception.get("alive", false)) \
		and float(perception.get("distance", INF)) <= trigger_radius_m


func _choose_attack() -> String:
	return str(attacks[0]) if not attacks.is_empty() else ""
