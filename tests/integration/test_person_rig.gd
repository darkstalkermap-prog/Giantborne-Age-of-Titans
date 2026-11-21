extends IntegrationSuite
## P60 (plan M11 §2.9, §3.13 tests): PersonRig, PersonModel and the people's levels, headless with the people
## switched on (PersonRig.enable_for_tests; ResetHooks turns them off after every test):
##   * headless without the switch nothing is made or instanced: no model, no crowd, no far mesh;
##   * a soldier is skinned near the giant: a pooled PersonModel with its record's variant and palette, the
##     brain's walk on the walk clip at the walk phase's time, a change of clip cross-faded over FADE_S and
##     landing on the clip's time; its gear (the sword) in the fist; a flash and a tint on its materials;
##   * the iron guard's record names its variant and its height; two ids give two looks, one id always the same;
## (The cap, the held soldier and the pool: tests/slow/test_people_render.gd.)
## The giant is a stand-in (a node of group "player" at stage 1's distance scale): this is presentation.

const SHIELDMAN := "res://scenes/enemies/shieldman.tscn"

var player: Node3D


func before_each() -> void:
	await super()
	player = Node3D.new()
	player.name = "GiantStandIn"
	player.position = Vector3(0, 0.05, 6)
	world.add_child(player)
	player.add_to_group("player")


func test_headless_nothing_is_made_or_instanced() -> void:
	assert_false(PersonRig.layers_enabled(), "the people are off headless (ResetHooks)")
	var s := spawn_soldier(Vector3(0, 0.05, 0))
	await step_ticks(2)
	var rig := s.rig as PersonRig
	assert_true(rig != null, "the soldier's Visual is a PersonRig")
	assert_eq(rig.level, PersonRig.Level.NONE, "no level")
	assert_true(rig.model() == null and rig.body.get_node_or_null(PersonRig.MODEL_NAME) == null, "no skinned model")
	assert_true((rig.get_node("LodProxy") as MultiMeshInstance3D).multimesh == null, "no far mesh")
	assert_true(rig.body.has_node("ShoulderR") and rig.body.has_node("HipL") and rig.body.has_node("Torso"),
		"the brain's pivots stay")
	assert_eq(rig.body.find_children("*", "MeshInstance3D", true, false).size(), 0, "and carry no mesh")


func test_a_skinned_soldier_walks_on_its_clip_carries_its_gear_and_flashes() -> void:
	PersonRig.enable_for_tests()
	var s := spawn_soldier(Vector3(0, 0.05, 0), 0.0, "test.person_a")
	await step_ticks(2)
	var rig := s.rig as PersonRig
	assert_true(rig.skinned(), "near the giant the soldier is skinned")
	var m := rig.model()
	assert_true(m != null and m.get_parent() == rig.body and m.name == PersonRig.MODEL_NAME, "its model under Visual/Body")
	var spec := rig.body_spec()
	assert_eq(str(spec.person_role), "person_role.soldier", "the record's role")
	assert_true(str(spec.variant) in ["soldier_a", "soldier_b", "soldier_c"], "a variant of the role's pool (%s)" % spec.variant)
	assert_eq(m.variant, str(spec.variant), "the model shows it")
	assert_true(m.mesh_instance().mesh != null and m.mesh_instance().skin != null, "a skinned mesh")
	assert_eq(m.skeleton().get_bone_count(), 23, "on the 23 bones")
	assert_true(m.transform.basis.z.dot(Vector3.BACK) < -0.9, "turned to face -Z")
	assert_eq(rig.current_clip(), "idle", "standing: the idle")
	var gear := rig.weapon_socket().get_node_or_null("Gear_sword") as MeshInstance3D
	assert_true(gear != null and gear.mesh == PersonModel.gear_mesh("sword"), "the sword in the fist's socket")
	var seg := rig.visible_weapon_segment()
	assert_true(seg.size() == 2 and (seg[0] as Vector3).distance_to(seg[1]) > 0.9, "the visible weapon's segment")
	# P59b: the socket is the variant's grip landmark (the manifest's grip_local_r, in the hand bone's frame: the
	# handle through the curled fingers), not PersonRig's fallback
	var grip := PersonRig.grips_of(m.role, m.variant)
	assert_true((grip.grip_r as Vector3).distance_to(PersonRig.FIST_LOCAL) > 0.005, "the manifest's grip (%s)" % grip.grip_r)
	var sk := m.skeleton()
	var at := (m.global_transform * sk.get_bone_global_pose(sk.find_bone("hand_r"))) * (grip.grip_r as Vector3)
	assert_true(rig.weapon_socket().global_position.distance_to(at) < 0.01,
		"the sword's grip in the fist (%.4f m off)" % rig.weapon_socket().global_position.distance_to(at))
	# the walk: the clip's time is the brain's walk phase scaled to the clip's cycle (P59b: its 1.5 m against the
	# brain's two 0.9 m steps), the change cross-faded
	s.process_mode = Node.PROCESS_MODE_DISABLED   # (held still: the brain reads the velocity set here)
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	s.velocity = Vector3(0, 0, -1.6)
	await step_ticks(2)
	assert_eq(rig.current_clip(), "walk", "walking: the walk clip")
	var ap := m.player()
	assert_eq(String(ap.current_animation), "people/walk", "the player plays it")
	assert_true(absf(rig.walk_ratio() - 2.0 * rig.stride_length_m / float(PersonModel.index().walk_cycle_m)) < 1e-5,
		"the walk ratio: two strides over the clip's cycle (%.3f)" % rig.walk_ratio())
	var want := fposmod(rig.walk_phase() * rig.walk_ratio() + PI * 0.5, TAU) / TAU * ap.current_animation_length
	assert_true(absf(ap.current_animation_position - want) < 0.03 or absf(absf(ap.current_animation_position - want)
		- ap.current_animation_length) < 0.03, "at the walk phase's time (%.3f / %.3f)" % [ap.current_animation_position, want])
	await step_ticks(12)   # past FADE_S
	s.velocity = Vector3.ZERO
	s.process_mode = Node.PROCESS_MODE_INHERIT
	rig.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(2)
	assert_eq(rig.current_clip(), "idle", "back to the idle")
	# a flash and a status tint reach the skinned body's material and the gear's
	s.flash(1.0)
	await step_ticks(1)
	var f: Vector3 = m.material.get_shader_parameter("flash")
	assert_true(f.x > 0.3, "a flash lights the body (%s)" % f)
	var gf: Vector3 = (gear.material_override as ShaderMaterial).get_shader_parameter("flash")
	assert_true(gf.x > 0.3, "and its gear")
	rig.set_status_tint(Color(0.45, 0.70, 1.0, 0.35))
	await step_ticks(30)
	var t: Vector4 = m.material.get_shader_parameter("tint")
	assert_true(absf(t.w - 0.35) < 1e-4 and (m.material.get_shader_parameter("flash") as Vector3).x < 0.01,
		"the tint stays, the flash fades")
	assert_true(int(PersonRig.run_stats().skinned_frames) > 0 and (PersonRig.run_stats().variants as Array).has(m.variant),
		"PEOPLE_STATS counts the skinned frames and the variant drawn")


func test_looks_by_record_and_id_and_the_iron_guards_variant() -> void:
	var a := PersonLook.spec({"role": "person_role.soldier"}, "test.look_1", "", 1.8, {})
	var b := PersonLook.spec({"role": "person_role.soldier"}, "test.look_1", "", 1.8, {})
	assert_eq(a, b, "one id always gives the same look")
	var differ := 0
	for i in 8:
		var c := PersonLook.spec({"role": "person_role.soldier"}, "test.look_x%d" % (i * 7), "", 1.8, {})
		if c.variant != a.variant or c.row != a.row:
			differ += 1
	assert_true(differ >= 6, "other ids give other looks (%d of 8)" % differ)
	var guard := GameData.get_record("enemy.iron_guard")
	var g := PersonLook.spec(guard.get("body"), "test.guard", "", float(guard.height_m), {})
	assert_eq(str(g.variant), "iron_guard", "the iron guard's record names its variant")
	assert_near(float(g.height_scale), 1.9 / 1.8, 1e-4, "at its record's height")
	assert_eq(g.gear, ["sword", "shield"], "with a sword and a shield")
	var faction := PersonLook.spec({"role": "person_role.soldier"}, "test.look_1", "brannock", 1.8, {})
	assert_true((faction.palette.faction as Color) != (a.palette.faction as Color), "a faction's colour on its band")
