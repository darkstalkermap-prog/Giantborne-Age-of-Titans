extends IntegrationSuite
## Size gates (P26, plan M6-M9 §2.9, §5.5, decision 18): a SizeGate wall stops a giant below its
## min_stage - only the giant's body collides with the gate layers 7-9, and only below their stage -
## and says why once per 4 s (Events.size_gate_blocked with the gate's id, stage and message, a HUD
## warning, the contact point for the gate's cue); a giant of the stage walks through it; an
## interaction with requires_stage refuses a smaller giant the same way. The camera, attack
## occluders, enemies and the growth clearance never see the walls.

const WATER := "res://scenes/world/size_gate_water.tscn"
const STONE := "res://scenes/world/size_gate_stone.tscn"

var blocked: Array[Array] = []
var warnings: Array[String] = []


func before_each() -> void:
	await super()
	blocked.clear()
	warnings.clear()
	Events.size_gate_blocked.connect(_on_blocked)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for pair: Array in [[Events.size_gate_blocked, _on_blocked], [Events.hud_message, _on_message]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_blocked(_tick: int, gate_id: String, min_stage: int, message: String) -> void:
	blocked.append([gate_id, min_stage, message])


func _on_message(text: String, kind: String) -> void:
	if kind == "warn":
		warnings.append(text)


func _gate(path: String, pos: Vector3) -> SizeGate:
	var g := (load(path) as PackedScene).instantiate() as SizeGate
	g.position = pos
	world.add_child(g)
	return g


func test_a_stage_3_giant_is_stopped_and_a_stage_4_giant_walks_through() -> void:
	var gate := _gate(WATER, Vector3(0, 0, -6))   # the wall: x -6..6, z -6.5..-5.5, 8 m tall
	assert_eq([gate.min_stage, gate.collision_layer, gate.collision_mask], [4, 64, 0], "a stage-4 gate on layer 7")
	var p := spawn_player(Vector3(0, 0.05, -2.5))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	assert_true((p.growth.debug_set_stage(3) as Dictionary).ok, "stage 3")
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, 1))
	var told: bool = await TestWait.until(self, func() -> bool: return not blocked.is_empty(), 90)
	await step_ticks(6)
	var r3 := float(p.profile.capsule_radius_m)
	assert_true(told, "the gate says why")
	assert_true(p.global_position.z > -5.5 + r3 - 0.15, "stopped at the wall (z %.2f)" % p.global_position.z)
	var text := "Too deep to wade. Grow to stage 4."
	assert_eq(blocked, [["test.gate.water", 4, text]], "size_gate_blocked once, with the gate's id, stage and message")
	assert_eq(warnings.count(text), 1, "a HUD warning")
	assert_eq(gate.blocked_count, 1, "counted once (at most every 4 s)")
	assert_near(gate.last_contact.z, -5.5, 0.05, "the contact point is on the wall's face, where the cue plays")
	assert_true(absf(gate.last_contact.x - p.global_position.x) < 0.1, "in front of the giant")
	assert_eq([gate.cue, gate.material, gate.world_id], ["sfx.gate.water", "water", "test.gate.water"],
		"the gate's cue and the material the audio router reads")
	p.router.set_injected_move(Vector2.ZERO)
	assert_true((p.growth.debug_set_stage(4) as Dictionary).ok, "grows to 4 against the wall: its own gate is not in the way")
	await step_ticks(1)
	p.router.set_injected_move(Vector2(0, 1))
	var through: bool = await TestWait.until(self, func() -> bool: return p.global_position.z < -7.0, 150)
	p.router.set_injected_move(Vector2.ZERO)
	assert_true(through, "a stage-4 giant walks through (z %.2f)" % p.global_position.z)
	assert_eq(blocked.size(), 1, "and is never refused")
	# A stage-gated interaction (a ledge only a stage-6 giant reaches): E refuses with its reason.
	var ledge := Interactable.new()
	ledge.interact_id = "test.ledge"
	ledge.requires_stage = 6
	world.add_child(ledge)
	p.interact.use_candidate({"node": ledge, "id": "test.ledge"})
	var out_of_reach := "Out of reach. Grow to stage 6."
	assert_eq(blocked.back(), ["test.ledge", 6, out_of_reach], "a stage-4 giant is told to grow to 6")
	assert_true(warnings.has(out_of_reach), "on the HUD")
	assert_eq(ledge.stage_reason(6), "", "a stage-6 giant reaches it")


func test_gate_layers_and_who_collides_with_them() -> void:
	assert_eq([SizeGate.layer_for_stage(4), SizeGate.layer_for_stage(5), SizeGate.layer_for_stage(6)], [64, 128, 256],
		"layers 7-9")
	for stage in range(1, 7):
		var prof := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)
		var mask := PlayerGrowth.collision_mask_for(prof)
		for gate_stage in [4, 5, 6]:
			assert_eq((mask & SizeGate.layer_for_stage(gate_stage)) != 0, stage < gate_stage,
				"a stage-%d giant %s a stage-%d gate" % [stage, "is stopped by" if stage < gate_stage else "passes", gate_stage])
	assert_eq(HitQueryAdapter.OCCLUDER_MASK & PlayerGrowth.ALL_SIZE_GATES, 0, "the camera's sweep and attack occluders never see them")
	assert_eq(PlayerGrowth.ACTOR_MASK & PlayerGrowth.ALL_SIZE_GATES, 0, "nor do enemies and NPCs (ACTOR_MASK)")
	assert_eq(PlayerGrowth.CLEARANCE_MASK & PlayerGrowth.ALL_SIZE_GATES, 0, "growth clearance adds only the stage's own gates")
	var stone := _gate(STONE, Vector3(30, 0, 0))
	assert_eq([stone.min_stage, stone.collision_layer], [6, 256], "the stone gate: stage 6, layer 9")
	assert_eq(stone.message_text(), "Only a giant of the old height can pass here. Grow to stage 6.", "its default message")
	assert_true(stone.sense_area() != null and stone.sense_area().get_child_count() == 1, "one sensing shape per wall shape")
	var grown := stone.sense_area().get_child(0) as CollisionShape3D
	assert_true((grown.shape as BoxShape3D).size.is_equal_approx(Vector3(13, 9, 2)), "grown 0.5 m on every side")
	assert_true(stone.passes(6) and not stone.passes(5), "passes(6), not passes(5)")
