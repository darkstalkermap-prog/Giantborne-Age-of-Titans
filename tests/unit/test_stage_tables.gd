extends TestSuite
## C1: the growth track's tables past the crown, without a scene - the size-gate layers and the titan gate bits for
## stages 4-10 from one table (PlayerGrowth) that the size gates, the schema, the nav bake, the level record, the
## project's layer names and the formation caps agree with; the colossi's profiles (78 and 96 ft at levels 13 and 15,
## every field rising from stage 6's, the masks of their stages); a stage's own requirement (growth_requirement) as
## a pure gate; the size multiplier's curve over the whole track (decision C1-4); the new permissions' words.


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func test_the_gate_tables_run_the_whole_track() -> void:
	var expect_gates := {1: 8128, 2: 8128, 3: 8128, 4: 8064, 5: 7936, 6: 7680, 7: 7168, 8: 6144, 9: 4096, 10: 0}
	var expect_nav := {1: 16, 2: 16, 3: 16, 4: 48, 5: 112, 6: 240, 7: 496, 8: 1008, 9: 2032, 10: 4080}
	for st: int in expect_gates:
		assert_eq(PlayerGrowth.size_gate_mask_for_stage(st), int(expect_gates[st]), "stage %d's size-gate mask" % st)
		assert_eq(PlayerGrowth.nav_query_mask_for_stage(st), int(expect_nav[st]), "stage %d's titan query mask" % st)
	assert_eq(PlayerGrowth.size_gate_mask_for_stage(1), PlayerGrowth.ALL_SIZE_GATES, "below stage 4 every gate stops a giant")
	assert_eq(PlayerGrowth.nav_query_mask_for_stage(10), PlayerGrowth.ALL_TITAN_BITS, "stage 10 crosses every gate")
	assert_eq(SizeGate.LAYERS, PlayerGrowth.SIZE_GATE_LAYERS, "the size gates use the growth's layer table")
	for st: int in PlayerGrowth.SIZE_GATE_LAYERS:
		assert_eq(SizeGate.layer_for_stage(st), int(PlayerGrowth.SIZE_GATE_LAYERS[st]), "a stage-%d gate's layer" % st)
		var layer := int(round(log(float(PlayerGrowth.SIZE_GATE_LAYERS[st])) / log(2.0))) + 1
		assert_eq(str(ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % layer, "")), "size_gate_%d" % st,
			"physics layer %d is named size_gate_%d" % [layer, st])
		assert_true(SizeGate.DEFAULT_MESSAGES.has(st), "a stage-%d gate has its default refusal" % st)
		var bit := int(PlayerGrowth.TITAN_GATE_BITS[st])
		assert_true(NavBake.GATE_NAMES.has(bit), "the nav bake names gate bit %d" % bit)
		var level_bits: Dictionary = GameData.get_record("level.world").world.gate_bits
		assert_eq(int(level_bits.get(str(st), 0)), bit, "the world's level record lists stage %d's gate bit" % st)
	assert_eq(SizeGate.layer_for_stage(12), 4096, "past stage 10 a gate is stage 10's")
	assert_eq(FormationRules.STAGES, PlayerGrowth.MAX_STAGE, "the formation caps are checked over the whole track")
	assert_eq(PlayerGrowth.MAX_STAGE, 10, "the track ends at stage 10 (level 20)")


func test_the_colossi_profiles_continue_the_curve() -> void:
	var g6 := _profile(6)
	var g7 := _profile(7)
	var g8 := _profile(8)
	assert_false(g7.is_empty() or g8.is_empty(), "stages 7 and 8 have profiles (C1)")
	var g9 := _profile(9)
	assert_false(g9.is_empty(), "D3: stage 9 has its profile")
	assert_true(_profile(10).is_empty(), "stage 10 waits for milestone E")
	assert_eq([int(g7.required_level), int(g8.required_level), int(g9.required_level)], [13, 15, 17],
		"levels 13, 15 and 17, the approved track")
	assert_eq(int(round(float(g9.height_m) * 3.28084)), 116, "116 ft")
	assert_eq([int(round(float(g7.height_m) * 3.28084)), int(round(float(g8.height_m) * 3.28084))], [78, 96], "78 and 96 ft")
	for key: String in ["capsule_radius_m", "walk_speed_mps", "melee_reach_m", "camera_distance_m", "camera_zoom_max_m",
			"lock_range_m", "step_height_m", "dodge_distance_m", "grab_reach_m", "weapon_scale", "arm_length_m"]:
		assert_true(float(g7[key]) > float(g6[key]) and float(g8[key]) > float(g7[key]) and float(g9[key]) > float(g8[key]),
			"%s rises through stages 6-9" % key)
	for key: String in ["lock_half_angle_deg", "turn_rate_deg_s", "jump_velocity_mps"]:
		assert_true(float(g7[key]) < float(g6[key]) and float(g8[key]) < float(g7[key]) and float(g9[key]) < float(g8[key]),
			"%s falls through stages 6-9" % key)
	assert_near(float(g9.weapon_scale), float(g9.height_m) / CombatRules.REFERENCE_HEIGHT_M, 1e-3, "stage 9's weapons scale with it")
	assert_near(float(g9.capsule_radius_m) / float(g9.height_m), float(g6.capsule_radius_m) / float(g6.height_m), 0.005,
		"stage 9 keeps the giant's proportions")
	assert_eq(int(g9.size_gate_mask), PlayerGrowth.size_gate_mask_for_stage(9), "stage 9's gate mask")
	assert_eq(int(g9.nav_query_mask), PlayerGrowth.nav_query_mask_for_stage(9), "stage 9's query mask")
	assert_true(float(g9.camera_zoom_max_m) <= CameraRig.MAX_ARM_M + 1e-3, "the camera's arm reaches stage 9's zoom")
	assert_eq((g9.interaction_permissions as Array), (g8.interaction_permissions as Array),
		"stage 9 keeps stage 8's permissions (what it adds is its size: decision D3-4)")
	assert_near(float(g7.weapon_scale), float(g7.height_m) / CombatRules.REFERENCE_HEIGHT_M, 1e-3, "stage 7's weapons scale with it")
	assert_near(float(g7.capsule_radius_m) / float(g7.height_m), float(g6.capsule_radius_m) / float(g6.height_m), 0.005,
		"the colossus keeps the giant's proportions")
	assert_eq(int(g7.size_gate_mask), PlayerGrowth.size_gate_mask_for_stage(7), "stage 7's gate mask")
	assert_eq(int(g8.nav_query_mask), PlayerGrowth.nav_query_mask_for_stage(8), "stage 8's query mask")
	assert_true((g7.interaction_permissions as Array).has("stride"), "stage 7 strides")
	assert_true((g8.interaction_permissions as Array).has("rout_armies"), "stage 8 routs armies")
	assert_true((g7.unlocks as Array).has("ability.colossus_stride"), "stage 7 learns Colossus Stride")
	assert_true(float(g8.camera_zoom_max_m) <= CameraRig.MAX_ARM_M + 1e-3, "the camera's arm reaches stage 8's zoom")
	assert_true(PlayerGrowth.profile_chain_errors(GameData.records_of_type("growth_profile"), {}).is_empty(),
		"the profile chain holds from 1 to 9")
	for st in [7, 8]:
		assert_true(PlayerGrowth.PERMISSION_TEXT.has("stride") and PlayerGrowth.PERMISSION_TEXT.has("rout_armies"),
			"the Grow tab has words for the new permissions")


func test_a_stage_requirement_is_a_pure_gate() -> void:
	var g7 := _profile(7)
	var g8 := _profile(8)
	var g9 := _profile(9)
	var req7: Dictionary = g7.growth_requirement
	# D3: the placeholders are gone - stage 8 asks the Frostbound slain, stage 9 the Stormcaller
	for g: Dictionary in [g7, g8, g9]:
		assert_false((g.growth_requirement as Dictionary).has("placeholder"), "stage %d's requirement is real" % int(g.stage))
	var ctx := {"flags": {}, "stage": 6, "level": 15}
	var r := PlayerGrowth.requirement_gate(g7, ctx)
	assert_eq([r.ok, r.reason], [false, "requirement"], "act one not done: stage 7 refused")
	assert_eq(str(r.message), str(req7.texts[0]), "with the first unmet condition's words")
	ctx.flags = {"act.two.begun": true}
	r = PlayerGrowth.requirement_gate(g7, ctx)
	assert_eq(str(r.message), str(req7.texts[1]), "act two begun, the Rimstone not reached")
	ctx.flags = {"act.two.begun": true, "visited.world.shrine.rimstone": true}
	assert_true(bool(PlayerGrowth.requirement_gate(g7, ctx).ok), "act two and the Rimstone: stage 7 grows")
	r = PlayerGrowth.requirement_gate(g8, ctx)
	assert_eq([r.ok, r.reason], [false, "requirement"], "stage 8 waits for the Frostbound")
	assert_true(str(r.message).contains("Frostbound"), "and says so: %s" % r.message)
	ctx.flags["boss.frostbound.defeated"] = true
	assert_true(bool(PlayerGrowth.requirement_gate(g8, ctx).ok), "the Frostbound slain: stage 8 grows")
	r = PlayerGrowth.requirement_gate(g9, ctx)
	assert_eq([r.ok, r.reason], [false, "requirement"], "stage 9 waits for the Stormcaller")
	assert_true(str(r.message).contains("Stormcaller"), "and says so: %s" % r.message)
	ctx.flags["boss.stormcaller.defeated"] = true
	assert_true(bool(PlayerGrowth.requirement_gate(g9, ctx).ok), "the Stormcaller slain: stage 9 grows")
	assert_true(bool(PlayerGrowth.requirement_gate(_profile(6), ctx).ok), "stage 6 has no requirement of its own")
	assert_true(str(g7.growth_requirement.track_text) != "" and not str(g7.growth_requirement.track_text).contains("Frostbound"),
		"the growth track's words name no titan of the later milestones")
	for g: Dictionary in [g8, g9]:
		var track := str(g.growth_requirement.track_text)
		assert_true(track != "" and not track.contains("Frostbound") and not track.contains("Stormcaller"),
			"stage %d's track says where without naming the titan: %s" % [int(g.stage), track])


func test_the_size_multiplier_curve_runs_the_track() -> void:
	var last := 0.0
	for st in range(1, 10):
		var m := CombatRules.size_multiplier(float(_profile(st).height_m))
		assert_true(m > last, "stage %d strikes harder than stage %d (x%.2f)" % [st, st - 1, m])
		assert_true(m <= CombatRules.SIZE_MULT_MAX, "under the cap")
		last = m
	assert_near(CombatRules.size_multiplier(18.8976), pow(18.8976 / 3.6576, 0.45), 1e-9, "stage 6 unchanged (C1-4)")
