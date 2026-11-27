class_name HeirBrain
extends TitanBrain
## E1: Orrik the Fetterer's brain (HeirEnemy). The titans' brain (TitanBrain: the sequences, the circling answer, the
## answer to a giant at his feet, a phase's arena hazards - the warband's fire-pots in his last phase) with the
## fetters' rules:
##   * **The Throne-breaker comes for a bound giant**: a target held by at least an action's `pinned_only` chains
##     (HeirEnemy tells the brain how many: `fettered`) makes that action (the record's `heir.breaker`) the next entry -
##     he walks in to its band and swings - at most every heir.breaker_cooldown_s. The chains are what open the giant to
##     it: his warning (the circle at the giant's feet, the long windup) is the time to tear free.
##   * **The haul follows the hook**: his chain-hook bit (`hook_bit`: HeirEnemy, from Events.fetter_bound) makes the
##     haul (heir.haul) the next entry at once.
##   * **No hook without its chain**: once the chain-coil on his arm is broken (`hook_lost`), or while the target is
##     already on his hook or within heir.hook_min_m, a sequence entry of his hook (heir.hook) is skipped.
## Every rule reads the brain's own clock and the actor's plain values: a seeded fight repeats.

var heir: Dictionary = {}
## How many chains hold the target now (HeirEnemy sets it every tick).
var fettered := 0
## The hook bit and its haul is due; the hook is gone for this attempt (the coil broken); the target is on the hook.
var hook_bit := false
var hook_lost := false
var target_hooked := false
## Throne-breakers and hauls answered (tests, debug).
var breaker_answers := 0
var haul_answers := 0
var _last_breaker := NO_TICK
var _answer_kind := ""


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	heir = record.get("heir", {}) if typeof(record.get("heir")) == TYPE_DICTIONARY else {}


func breaker_id() -> String:
	return str(heir.get("breaker", ""))


func hook_id() -> String:
	return str(heir.get("hook", ""))


func haul_id() -> String:
	return str(heir.get("haul", ""))


## The chains the Throne-breaker asks of the target (its action's pinned_only).
func breaker_needs() -> int:
	var a := GameData.get_action(breaker_id())
	return int(a.param("pinned_only", 2)) if a != null else 99


func current_sequence_entry() -> String:
	if _answer != "":
		return _answer
	var id := super()
	var guard := 0
	while id != "" and id == hook_id() and _hook_unwanted() and guard < 8:
		super.advance_sequence(false)
		id = super()
		guard += 1
	return id


func _hook_unwanted() -> bool:
	if hook_lost or target_hooked:
		return true
	var edge := float(perception.get("distance", 0.0))
	return edge > 0.0 and edge < float(heir.get("hook_min_m", 18.0))


func advance_sequence(performed: bool) -> void:
	if _answer != "" and _answer_kind != "":
		if performed:
			if _answer_kind == "breaker":
				breaker_answers += 1
				_last_breaker = now
				sequence_log.append("pin:" + _answer)
			else:
				haul_answers += 1
				sequence_log.append("haul:" + _answer)
		elif _answer_kind == "breaker":
			_last_breaker = now   # (skipped: he could not reach the bound giant in time; not again at once)
		_answer = ""
		_answer_kind = ""
		_answer_is_hug = false
		_entry_since = NO_TICK
		return
	super(performed)


func update_boss_phase(health_frac: float, tick: int = -1) -> int:
	var kind := _answer_kind
	var keep := _answer
	var entered := super(health_frac, tick)
	if entered > 0 and kind == "haul":
		_answer = keep   # (a phase's roar does not let go of a giant on his hook)
		_answer_kind = kind
	elif entered > 0:
		_answer_kind = ""
	return entered


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	_watch_heir()
	super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)


func _watch_heir() -> void:
	if state == AIState.ATTACK:
		return
	if hook_bit:
		hook_bit = false
		if haul_id() != "" and target_hooked:
			_answer = haul_id()
			_answer_kind = "haul"
			_answer_is_hug = false
			_entry_since = NO_TICK
			return
	if _answer_kind == "haul" and not target_hooked:
		_answer = ""   # (the giant tore the hook before the haul began)
		_answer_kind = ""
	if _answer != "":
		if _answer_kind == "breaker" and fettered < breaker_needs():
			_answer = ""   # (he tore free before the swing began: the Throne-breaker is not swung at a free giant)
			_answer_kind = ""
			_last_breaker = now
		return
	if breaker_id() == "" or fettered < breaker_needs():
		return
	if _last_breaker != NO_TICK and now - _last_breaker < _ticks(float(heir.get("breaker_cooldown_s", 10.0))):
		return
	_answer = breaker_id()
	_answer_kind = "breaker"
	_answer_is_hug = false
	_entry_since = NO_TICK
