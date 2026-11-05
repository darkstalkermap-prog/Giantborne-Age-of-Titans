class_name FakeShrine
extends Node3D
## A stand-in for a P05 Shrine in the session tests (P06 never references the real class): a
## node in group "shrines" with world_id (the checkpoint id) and shrine_id (the record id), and a
## SpawnPoint CheckpointMarker child whose checkpoint_id is the world id, as plan §2.7.4 lays
## a shrine out. GameSession resolves shrine events to respawn points through exactly these.

@export var world_id := ""
@export var shrine_id := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group("shrines")


## A fake shrine at `pos` with its spawn point 3 m in front of it.
static func make(p_world_id: String, p_shrine_id: String, pos: Vector3) -> FakeShrine:
	var s := FakeShrine.new()
	s.name = "FakeShrine_" + p_world_id.replace(".", "_")
	s.world_id = p_world_id
	s.shrine_id = p_shrine_id
	s.position = pos
	var spawn := CheckpointMarker.new()
	spawn.name = "SpawnPoint"
	spawn.checkpoint_id = p_world_id
	spawn.position = Vector3(0, 0.05, -3)
	s.add_child(spawn)
	return s
