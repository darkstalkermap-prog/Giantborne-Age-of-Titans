class_name StubEnemy
extends EnemyActor
## Minimal non-soldier enemy for tests of the EnemyActor seams (TestSpawn.stub_enemy): the
## base melee EnemyBrain, no guard, and a record of the virtual hooks it received. Later
## packages may extend it (e.g. to record on_morale_delta calls).

var calls: Array[String] = []
var sense_count := 0


func _make_brain() -> EnemyBrain:
	calls.append("make_brain")
	return super()


func _sense_extra(snapshot: Dictionary) -> void:
	sense_count += 1
	snapshot["stub"] = true
