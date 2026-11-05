extends IntegrationSuite
## P18: regression test for the bug the ship package's rendered Valley tour showed. The HUD's
## "Destroyed: ..." message took the second part of the world id, which in the Valley is the
## district: breaking the practice gate said "Destroyed: ruins", the Deadfall "Destroyed: forest",
## the watch cairn "Destroyed: grove". It now names the prop by its record ("Practice Gate"), else
## by the last part of its world id.

const PRACTICE := "res://scenes/world/gate_practice.tscn"


func _hud() -> Hud:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	var hud := Hud.new()
	layer.add_child(hud)
	return hud


func test_a_destroyed_prop_is_named_by_its_record_not_its_district() -> void:
	spawn_player(Vector3(0, 0.05, 20))
	var hud := _hud()
	var gate := (load(PRACTICE) as PackedScene).instantiate() as BreakableProp
	gate.world_id = "valley.ruins.practice_gate"
	world.add_child(gate)
	await step_ticks(2)
	assert_eq(hud.destroyed_name("valley.ruins.practice_gate"), "Practice Gate", "a prop in the tree: its record's name")
	queue_hit("tester", "valley.ruins.practice_gate", Vector3(0, 1, 4), 1000.0)
	await step_ticks(2)
	assert_true(gate.destroyed, "the gate broke")
	assert_true(hud.message_texts().has("Destroyed: Practice Gate"), "the message names the gate: %s" % [hud.message_texts()])
	assert_false(hud.message_texts().has("Destroyed: ruins"), "not its district")
	assert_eq(hud.destroyed_name("valley.forest.fence_pen"), "fence pen", "no such prop: the last part of the id")
	assert_eq(hud.destroyed_name("sandbox.fence_01"), "fence 01", "a two-part id reads as before")
