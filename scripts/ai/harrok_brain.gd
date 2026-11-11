class_name HarrokBrain
extends RivalGiantBrain
## Harrok the Unbowed (plan M6-M9 §5.13 boss 3; P34). Phase 1 cycles the axe combo, the overhead chop,
## the boulder, the combo and the shoulder charge; phase 2 (at 50 % or after two poise breaks - the
## actor's P34 step) opens with the forced roar and cycles the three-hit frenzy, the chop, the charge
## and the boulder, while the Moot's stones fall: the phase's `hazard` action (moot_stones,
## arena_hazard) is this brain's. Every interval_s it keeps `count` hazards going, each a point
## distance_m from its target at least min_gap_m from the others (its own RNG, so a seeded run repeats),
## due telegraph_s after it was announced. hazard_step() returns what to announce and what to strike;
## the actor (RivalGiantEnemy) does both, so every stone is Harrok's hit. A yield, a new attempt or the
## loss of the target clears them (p34_clear_hazards).

## The hazards in the air: {"id": int, "point": Vector3, "due": tick}.
var hazards: Array = []
## Every hazard announced, in order: [tick, point] (tests, the gate's seeded runs).
var hazard_log: Array = []
var _hazard_next := -1
var _hazard_seq := 0


func _init(p_actor_id: String, record: Dictionary, seed_value: int) -> void:
	super(p_actor_id, record, seed_value)


## The current phase's arena hazard action ("" when it has none).
func phase_hazard() -> String:
	return str(phase_record().get("hazard", "")) if has_boss_phases() else ""


## One tick of the hazards: {"new": [hazards to announce], "due": [hazards to strike], "action": id}.
## target_pos INF (no living target) announces nothing new; due ones still strike.
func hazard_step(tick: int, target_pos: Vector3) -> Dictionary:
	var out := {"new": [], "due": [], "action": phase_hazard()}
	for h: Dictionary in hazards.duplicate():
		if tick >= int(h.due):
			hazards.erase(h)
			out.due.append(h)
	var id := phase_hazard()
	if id == "" or state == AIState.DEAD or target_pos == Vector3.INF:
		return out
	var spec: Dictionary = GameData.get_record(id).get("arena_hazard", {})
	if _hazard_next < 0:
		_hazard_next = tick + _ticks(float(spec.get("telegraph_s", 1.5)))   # after the phase roar begins
		return out
	if tick < _hazard_next:
		return out
	_hazard_next = tick + _ticks(float(spec.get("interval_s", 4.0)))
	while hazards.size() < int(spec.get("count", 1)):
		_hazard_seq += 1
		var h := {"id": _hazard_seq, "point": _pick_point(target_pos, spec),
			"due": tick + _ticks(float(spec.get("telegraph_s", 1.5)))}
		hazards.append(h)
		hazard_log.append([tick, h.point])
		out.new.append(h)
	return out


## A point distance_m from the target, at least min_gap_m from the hazards in the air (eight tries).
func _pick_point(target_pos: Vector3, spec: Dictionary) -> Vector3:
	var band: Array = spec.get("distance_m", [4.0, 20.0])
	var gap := float(spec.get("min_gap_m", 0.0))
	var p := target_pos
	for _i in 8:
		var ang := rng.randf() * TAU
		var r := rng.randf_range(float(band[0]), float(band[1]))
		p = target_pos + Vector3(sin(ang), 0.0, cos(ang)) * r
		var clear := true
		for h: Dictionary in hazards:
			if Vector2(p.x - (h.point as Vector3).x, p.z - (h.point as Vector3).z).length() < gap:
				clear = false
				break
		if clear:
			return p
	return p


## No hazard in the air, none scheduled (a yield, a new attempt, a dead giant).
func p34_clear_hazards() -> void:
	hazards.clear()
	_hazard_next = -1
