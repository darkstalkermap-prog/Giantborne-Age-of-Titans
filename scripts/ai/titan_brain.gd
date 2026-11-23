class_name TitanBrain
extends HarrokBrain
## A signature titan's brain (A2; TitanEnemy): the rival giants' sequences (EnemyBrain P11a through
## OgreBossBrain) with two titan rules:
##   * faster chains by phase: a phase's strike_pause_scale scales the pause between his strikes (Stoneback's
##     rage: 0.45 - the record's 1.0-1.6 s becomes 0.45-0.7 s);
##   * he punishes circling: a target that stands on his flank (between FLANK_MIN_DEG and FLANK_MAX_DEG off his
##     facing) within the sweep's band for FLANK_S is answered by the phase's sweep (the first phase attack whose
##     telegraph is a cone of at least SWEEP_MIN_ARC_DEG) before the sequence goes on. Behind him (beyond
##     FLANK_MAX_DEG) nothing answers but his slow turn: his back is the giant's opening. At most one answer every
##     FLANK_COOLDOWN_S.
##   * B3: the arena hazards of a phase (HarrokBrain's: a phase's `hazard` action - the Rootwarden's grove's dead
##     trees falling in his second phase); none for a titan whose phases name none (Stoneback, the Ogre King: their
##     RNG is never drawn for one);
##   * B3: he answers a giant at his feet (the record's `hug`: the Rootwarden's stomp): a target whose capsule's
##     edge stays within hug.within_m of his for hug.hold_s is answered by hug.action before the sequence goes on,
##     at most every hug.cooldown_s; while he walks the hug is the sequence's own business.
## Everything is decided from the brain's own clock and RNG, so a seeded fight repeats.

const FLANK_MIN_DEG := 55.0
const FLANK_MAX_DEG := 115.0
const FLANK_S := 1.0
## At most one circling answer this often (seconds): a sweep is his answer, not his whole fight.
const FLANK_COOLDOWN_S := 9.0
const SWEEP_MIN_ARC_DEG := 180.0

## Sweeps struck to answer circling (tests, debug).
var flank_answers := 0
## B3: the answers to a giant at his feet struck (tests, debug).
var hug_answers := 0
var _hug: Dictionary = {}
var _hug_since := NO_TICK
var _last_hug := NO_TICK
var _flank_since := NO_TICK
var _answer := ""
var _answer_is_hug := false
var _last_answer := NO_TICK


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)
	_hug = record.get("hug", {}) if typeof(record.get("hug")) == TYPE_DICTIONARY else {}


## The current phase's pause scale (1.0 without one).
func strike_pause_scale() -> float:
	return float(phase_record().get("strike_pause_scale", 1.0)) if has_boss_phases() else 1.0


## A wide sweep (a cone of SWEEP_MIN_ARC_DEG or more) starts with the target anywhere inside its arc, less a
## margin: it is the answer to a target on his flank. Every other entry as EnemyBrain's.
static func entry_facing_deg(action_id: String) -> float:
	var t: Variant = GameData.get_record(action_id).get("telegraph")
	if typeof(t) == TYPE_DICTIONARY and str(t.get("shape", "")) == "cone" \
			and float(t.get("arc_deg", 0.0)) >= SWEEP_MIN_ARC_DEG:
		return float(t.arc_deg) * 0.5 - 15.0
	return EnemyBrain.entry_facing_deg(action_id)


## The phase's sweep (a wide cone attack) or "".
func phase_sweep() -> String:
	for id: Variant in phase_attacks():
		var t: Variant = GameData.get_record(str(id)).get("telegraph")
		if typeof(t) == TYPE_DICTIONARY and str(t.get("shape", "")) == "cone" \
				and float(t.get("arc_deg", 0.0)) >= SWEEP_MIN_ARC_DEG:
			return str(id)
	return ""


## The sequence entry now: the circling answer while one is due, else the sequence's.
func current_sequence_entry() -> String:
	if _answer != "":
		return _answer
	return super()


func advance_sequence(performed: bool) -> void:
	if _answer != "":
		if performed:
			if _answer_is_hug:
				hug_answers += 1
				_last_hug = now
				sequence_log.append("hug:" + _answer)
			else:
				flank_answers += 1
				_last_answer = now
				sequence_log.append("flank:" + _answer)
		_answer = ""
		_answer_is_hug = false
		_entry_since = NO_TICK
		return
	super(performed)


func update_boss_phase(health_frac: float, tick: int = -1) -> int:
	var entered := super(health_frac, tick)
	if entered > 0:
		_answer = ""
		_answer_is_hug = false
		_flank_since = NO_TICK
		_hug_since = NO_TICK
	return entered


func _decide_engaged(my_position: Vector3, target_pos: Vector3, distance: float, seen: bool,
		memory_ok: bool, target_alive: bool, request_token: Callable, release_token: Callable) -> void:
	_watch_hug(distance)
	_watch_flank(distance)
	var before := state
	super(my_position, target_pos, distance, seen, memory_ok, target_alive, request_token, release_token)
	if before == AIState.ATTACK and state == AIState.RECOVER:
		var scale := strike_pause_scale()
		if scale != 1.0:
			strike_ready_tick = now + int(round(float(strike_ready_tick - now) * scale))


## B3: a target at his feet (its capsule's edge within hug.within_m of his) for hug.hold_s makes hug.action the next
## entry (at most every hug.cooldown_s).
func _watch_hug(distance: float) -> void:
	if _hug.is_empty() or _answer != "" or state == AIState.ATTACK:
		return
	if _last_hug != NO_TICK and now - _last_hug < _ticks(float(_hug.get("cooldown_s", 8.0))):
		return
	var edge := distance - float(perception.get("target_radius", 0.85)) - _own_radius_m
	if edge <= float(_hug.get("within_m", 4.0)):
		if _hug_since == NO_TICK:
			_hug_since = now
		elif now - _hug_since >= _ticks(float(_hug.get("hold_s", 1.0))):
			_answer = str(_hug.get("action", ""))
			_answer_is_hug = true
			_hug_since = NO_TICK
	else:
		_hug_since = NO_TICK


## A target on his flank inside the sweep's band for FLANK_S makes the sweep the next entry.
func _watch_flank(distance: float) -> void:
	if _answer != "" or state == AIState.ATTACK:
		return
	if _last_answer != NO_TICK and now - _last_answer < _ticks(FLANK_COOLDOWN_S):
		return
	var sweep := phase_sweep()
	if sweep == "":
		return
	var off := absf(float(perception.get("facing_deg", 0.0)))
	var band := sequence_band(sweep)
	var edge := distance - float(perception.get("target_radius", 0.85))
	if off >= FLANK_MIN_DEG and off <= FLANK_MAX_DEG and edge <= band.y and edge >= band.x:
		if _flank_since == NO_TICK:
			_flank_since = now
		elif now - _flank_since >= _ticks(FLANK_S):
			_answer = sweep
			_flank_since = NO_TICK
	else:
		_flank_since = NO_TICK
