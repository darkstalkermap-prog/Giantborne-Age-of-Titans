extends IntegrationSuite
## C3b (decision C3b-5): the landmarks at every size. A waystone open but not yet reached stands as a faint grey
## column (its beam unlit) and burns blue once reached; a lit forge's soft pale smoke draws far, a cold one's
## not at all (and beyond them the HUD's far marks); the plinth, the chimney, the back wall, the trough and the lean-to's posts are solid (a giant walking
## into them stops); the HUD's place marks reach far at a big stage, keep their words clear of the HUD's top messages
## and of each other.

const FORGE_SCENE := "res://scenes/world/forge.tscn"
const Marker := preload("res://ui/hud/place_marker.gd")


func _waystone(id: String, flags: PackedStringArray, at: Vector3) -> Waystone:
	var m := Marker3D.new()
	m.name = id.validate_node_name()
	m.set_script(load("res://scripts/world/waystone.gd"))
	m.set("checkpoint_id", id)
	m.set("radius_m", 6.0)
	m.set("requires_flags", flags)
	m.set("display_name", "Test waystone")
	m.position = at
	var body := StaticBody3D.new()
	body.name = "Stone"
	body.position = Vector3(0, 0, 4)
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 5.0, 1.6)
	cs.shape = box
	cs.position = Vector3(0, 2.5, 0)
	body.add_child(cs)
	m.add_child(body)
	world.add_child(m)
	return m as Waystone


func test_an_unreached_waystone_stands_unlit_and_burns_once_reached() -> void:
	var w := _waystone("c3b.way", PackedStringArray(["c3b.way_open"]), Vector3(30, 0, 0))
	await step_ticks(2)
	var beam := w.look.get_node("Beam") as GeometryInstance3D
	var mat := beam.material_override as ShaderMaterial
	assert_false(beam.visible, "shut: no column")
	WorldState.set_flag("c3b.way_open", true)
	await step_ticks(2)
	await get_tree().create_timer(WaystoneLook.FADE_S * 0.5).timeout
	assert_true(beam.visible, "open, not yet reached: a column")
	assert_eq(float(mat.get_shader_parameter("unlit")), 1.0, "unlit")
	assert_near(float(mat.get_shader_parameter("strength")), WaystoneLook.BEAM[WaystoneLook.State.OPEN], 1e-4, "faint")
	assert_near(beam.visibility_range_end, WaystoneLook.UNLIT_FAR_M, 0.01, "drawn past the monument's own reach")
	assert_near(beam.visibility_range_begin, WaystoneLook.UNLIT_NEAR_M, 0.01, "where the stone is small")
	WorldState.set_flag(GameSession.VISITED_PREFIX + "c3b.way", true)
	await step_ticks(2)
	await get_tree().create_timer(WaystoneLook.FADE_S + 0.1).timeout
	assert_eq(float(mat.get_shader_parameter("unlit")), 0.0, "reached: lit")
	assert_near(float(mat.get_shader_parameter("strength")), 1.0, 1e-3, "at full strength")
	assert_true(beam.visibility_range_end >= 2000.0 and beam.visibility_range_begin == 0.0, "seen from far off (%.0f m)" % beam.visibility_range_end)
	assert_true(w.look.get_node_or_null("Body") is StaticBody3D, "the plinth is solid")


func test_a_lit_forge_is_found_from_far_off() -> void:
	var f := (load(FORGE_SCENE) as PackedScene).instantiate() as Forge
	f.world_id = "c3b.forge"
	f.requires_flags = PackedStringArray(["c3b.forge_open"])
	f.position = Vector3(0, 0, -30)
	world.add_child(f)
	await step_ticks(2)
	var smoke := f.look.get_node("Smoke") as CPUParticles3D
	assert_false(smoke.emitting, "cold: no smoke")
	assert_true(smoke.visibility_range_end >= 800.0, "its smoke drawn far (%.0f m)" % smoke.visibility_range_end)
	var ramp := smoke.color_ramp
	for i in ramp.get_point_count():
		var c := ramp.get_color(i)
		assert_true(c.v >= 0.7, "the smoke is pale (%s)" % c)
		assert_true(c.a <= 0.45, "and thin (%s)" % c)
	WorldState.set_flag("c3b.forge_open", true)
	await get_tree().create_timer(Forge.LOOK_POLL_S + 0.2).timeout
	assert_true(smoke.emitting, "lit: its smoke column")
	assert_true(f.look.get_node_or_null("Body") is StaticBody3D, "the smithy has solids of its own")


func test_a_giant_does_not_walk_through_a_smithy() -> void:
	var f := (load(FORGE_SCENE) as PackedScene).instantiate() as Forge
	f.world_id = "c3b.forge_walk"
	f.position = Vector3(0, 0, -12)
	world.add_child(f)
	await step_ticks(2)
	var p := spawn_player(Vector3(0, 0.05, 2), 0.0)   # behind the smithy's back wall (its +z side), facing it (-z)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.camera_rig.yaw = 0.0
	p.router.set_injected_move(Vector2(0, 1))
	await step_ticks(240)
	p.router.set_injected_move(Vector2.ZERO)
	var wall_z := f.global_position.z + 5.4 + 0.4
	print("    the giant walked from z 2 toward the smithy's back wall (its face at z %.1f): stopped at z %.2f" % [wall_z, p.global_position.z])
	assert_true(p.global_position.z > wall_z, "stopped at the back wall (%.2f > %.2f)" % [p.global_position.z, wall_z])


func test_the_marks_keep_clear_of_the_hud_and_each_other() -> void:
	var reserved := [Rect2(320, 206, 640, 46)]   # the region banner's place
	var marks := [
		{"screen": Vector2(640, 200), "far": false},   # under the banner: moved down past it
		{"screen": Vector2(650, 205), "far": false},   # on top of the first: moved down past it
		{"screen": Vector2(660, 210), "far": true},
	]
	Marker._layout(marks, reserved)
	var rects: Array = []
	for m: Dictionary in marks:
		var r: Rect2 = m.get("rect", Rect2())
		if r.size == Vector2.ZERO:
			continue
		assert_false(r.intersects(reserved[0]), "clear of the banner (%s)" % r)
		for o: Rect2 in rects:
			assert_false(r.intersects(o), "clear of the others (%s, %s)" % [r, o])
		rects.append(r)
	assert_true(rects.size() >= 2, "the near marks keep their words")
	assert_true(Marker.FAR_M + Marker.FAR_HEIGHTS * 29.26 > 1500.0, "a stage-8 giant sees the marks from 1.5 km and more")
