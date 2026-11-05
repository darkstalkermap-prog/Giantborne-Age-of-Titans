class_name FlowTestLevel
extends Node3D
## Root of the session flow test level (scenes/test/flow_test_level.tscn, built by
## tools/builders/test_levels.gd; plan §3.6): a floor, the checkpoint markers test.cp_a and
## test.cp_b, the waystone test.cp_way (needs the flag test.way_open), the fence
## test.flow_fence, a stub-enemy spawn point (Spawns/StubEnemy) and the Player.
##
## While it is in the tree it opts in to checkpoints outside the Valley
## (GameSession.test_checkpoints), so the checkpoint, death and reload flow can be tested (and
## played with --level=res://scenes/test/flow_test_level.tscn) without the Valley.

## Written into save documents and used for the start checkpoint (GameSession).
@export var level_id := "test.flow"
## Where a New Game's later reloads respawn before any other checkpoint was reached.
@export var start_checkpoint := "test.cp_a"


func _enter_tree() -> void:
	GameSession.test_checkpoints = true


func _exit_tree() -> void:
	GameSession.test_checkpoints = false


## Where tests put a stub enemy (Spawns/StubEnemy), or the origin.
func stub_spawn_position() -> Vector3:
	var m := get_node_or_null("Spawns/StubEnemy") as Node3D
	return m.global_position if m != null else global_position
