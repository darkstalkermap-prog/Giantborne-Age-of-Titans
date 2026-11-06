class_name WorldAiTrace
extends Node
## P24b: the AI trace of the world determinism gate (tests/gate/test_world_determinism.gd). A child of
## the traced test world (tests/support/test_world_traced.tscn: the test world with this node), it
## prints one "P24B_AI {json}" line every TRACE_TICKS physics ticks - the tick, the giant's position,
## the hits resolved so far, every encounter's state and every member's position, brain state,
## awareness, path failures and re-paths (positions to the millimetre) - so two runs of the same
## world walk can be compared line by line, the AI's every half second with them.

const PREFIX := "P24B_AI "
const TRACE_TICKS := 30

var _ticks := 0
var _hits := 0


func _ready() -> void:
	Events.hit_resolved.connect(_on_hit_resolved)


func _exit_tree() -> void:
	if Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.disconnect(_on_hit_resolved)


func _on_hit_resolved(_tick: int, _r: HitResult) -> void:
	_hits += 1


func _physics_process(_delta: float) -> void:
	_ticks += 1
	if _ticks % TRACE_TICKS == 0:
		print(PREFIX + JSON.stringify(snapshot()))


## The trace's state now (see the header).
func snapshot() -> Dictionary:
	var level := get_parent() as LevelRoot
	var out := {"tick": Sim.tick, "hits": _hits}
	if level == null:
		return out
	var p := level.player()
	if p != null:
		out["giant"] = _v(p.global_position)
	var d := level.director()
	if d == null:
		return out
	var encounters := {}
	var members := {}
	for enc: String in d.encounter_ids():
		encounters[enc] = d.encounter_state(enc)
		for id: String in d.members_of(enc):
			var n := d.spawned(id) as EnemyActor
			if n == null:
				members[id] = d.member_status(id)
				continue
			members[id] = [_v(n.global_position), n.brain.state_name(), n.brain.aware, n.path_failures, n.repath_count]
	out["encounters"] = encounters
	out["members"] = members
	return out


static func _v(v: Vector3) -> String:
	return "%.3f,%.3f,%.3f" % [v.x, v.y, v.z]
