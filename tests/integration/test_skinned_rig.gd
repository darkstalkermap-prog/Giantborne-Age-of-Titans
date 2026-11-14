extends IntegrationSuite
## The skinned rig (P43; plan M10 §2.9, decisions 2-8): the realistic giant on the pose brain. This default
## suite keeps to the cheap checks; the motion checks (a 5 s walk and its footfalls, the stance through a
## dodge, a stagger and a knockback, Shoulder Charge's run, the airborne pose, the death clip, the heavy at
## stage 4, the hold through a release and a death) are tests/slow/test_skinned_rig_motion.gd, and the
## rendered frames tests/slow/test_skinned_rig_render.gd (docs/systems/P43.md: the default tier's 0.6 s).
##   * the node contract on the scene read from disk: the brain's pivots and hand markers without meshes,
##     the model, the socket; the run-time nodes (AnimationPlayer with the "giant" library, AnimationTree,
##     PoseBrainModifier) made by the rig with the layers on and never saved;
##   * every track of every clip resolves to a bone of the skeleton (0 unresolved), the loops loop;
##   * the headless default: no run-time nodes, the skeleton at rest, WeaponSocket at the brain's hand;
##   * a stage-1 heavy measured in `posed`: the visible weapon's outer half inside the tested capsule, at
##     most 15 degrees off it, the fist within 0.01 m of its target;
##   * flash() and set_status_tint() reach every giant surface's shader and the weapon;
##   * apply_look on the live giant, growth to stage 4 scaling Body by 3 with the look kept;
##   * the render layers per mesh kind and the first-person mask;
##   * skin_stats() and SkinnedRig.run_stats() count what ran.

const LAYER_OF := {"body": 0, "eyes": 3, "hair": 3, "beard": 3}


func _rig(p: GiantPlayer) -> SkinnedRig:
	return p.get_node("Visual") as SkinnedRig


func _grounded(stage := 1) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	if stage != 1:
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
	await step_ticks(2)
	return p


func test_the_node_contract_on_the_scene_from_disk() -> void:
	var packed := ResourceLoader.load(GIANT, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var state := packed.get_state()
	var saved := {}
	for i in state.get_node_count():
		saved[str(state.get_node_path(i)).trim_prefix("./")] = str(state.get_node_type(i))
	for path: String in ["Visual", "Visual/Body", "Visual/Body/HipL", "Visual/Body/HipR", "Visual/Body/Torso",
			"Visual/Body/ShoulderL", "Visual/Body/ShoulderR", "Visual/Body/ShoulderL/Hand", "Visual/Body/ShoulderR/Hand",
			"Visual/Body/Model", "Visual/Body/WeaponSocket", "CameraRig/Camera3D"]:
		assert_true(saved.has(path), "%s is saved" % path)
	for path: String in saved:
		for runtime in ["AnimationPlayer", "AnimationTree", "PoseBrainModifier"]:
			assert_false(path.contains(runtime), "%s is never saved (%s)" % [runtime, path])
	assert_eq(saved.size(), state.get_node_count(), "every saved node read")
	var root := packed.instantiate() as GiantPlayer
	assert_true(root.get_node("Visual") is SkinnedRig, "Visual is the SkinnedRig")
	assert_true(root.get_node("Visual/Body/Model") is GiantModel, "Visual/Body/Model is the GiantModel")
	assert_eq(root.get_node("Visual/Body/Model").scene_file_path, "res://scenes/player/giant_model.tscn",
		"an instance of the model's scene")
	root.free()
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var model := rig.model()
	assert_true(rig.layers_on(), "the layers run")
	var player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	var tree := model.get_node_or_null("AnimationTree") as AnimationTree
	var mod := rig.skeleton().get_node_or_null("PoseBrainModifier") as PoseBrainModifier
	assert_true(player != null and player.has_animation_library(SkinnedRig.LIBRARY), "the AnimationPlayer with the giant library")
	assert_true(tree != null and tree == rig.animation_tree() and tree.active, "the AnimationTree")
	assert_true(mod != null and mod == rig.modifier(), "the PoseBrainModifier under the skeleton")
	for n: Node in [player, tree, mod]:
		if n != null:
			assert_true(n.owner == null, "%s belongs to no scene (never saved)" % n.name)


func test_every_clip_track_resolves_to_a_bone() -> void:
	var lib := SkinnedRig.clip_library()
	assert_true(lib != null, "the clip library loads")
	if lib == null:
		return
	var names := lib.get_animation_list()
	for clip in ["idle", "walk", "run", "airborne", "death", "grip_r", "grip_l", "open_r", "open_l"]:
		assert_true(names.has(clip), "the %s clip" % clip)
	for clip in ["idle", "walk", "run"]:
		assert_eq(lib.get_animation(clip).loop_mode, Animation.LOOP_LINEAR, "%s loops" % clip)
	var root := (load(GIANT) as PackedScene).instantiate()
	world.add_child(root)
	var model := root.get_node("Visual/Body/Model") as GiantModel
	var sk := model.skeleton()
	var gltf := sk.get_parent().get_parent()
	var tracks := 0
	var unresolved: Array = []
	for clip: StringName in names:
		var anim := lib.get_animation(clip)
		for t in anim.get_track_count():
			tracks += 1
			var path := anim.track_get_path(t)
			var node := gltf.get_node_or_null(NodePath(path.get_concatenated_names()))
			if not (node is Skeleton3D and (node as Skeleton3D).find_bone(path.get_concatenated_subnames()) >= 0):
				unresolved.append("%s:%s" % [clip, path])
	assert_true(tracks > 200, "the clips have their tracks (%d)" % tracks)
	assert_eq(unresolved, [], "every track resolves to a bone")
	root.queue_free()
	await step_ticks(1)


func test_the_headless_default() -> void:
	var p := await _grounded()
	var rig := _rig(p)
	assert_false(SkinnedRig.layers_enabled(), "headless: the layers are off")
	assert_false(rig.layers_on(), "the rig made none")
	var model := rig.model()
	for n in ["AnimationPlayer", "AnimationTree"]:
		assert_true(model.get_node_or_null(n) == null, "no %s" % n)
	assert_true(rig.skeleton().get_node_or_null("PoseBrainModifier") == null, "no PoseBrainModifier")
	var sk := rig.skeleton()
	var moved := 0
	for i in sk.get_bone_count():
		if not sk.get_bone_pose(i).is_equal_approx(sk.get_bone_rest(i)):
			moved += 1
	assert_eq(moved, 0, "the skeleton rests")
	var hand := p.get_node("Visual/Body/ShoulderR/Hand") as Node3D
	assert_true(rig.weapon_socket().global_position.is_equal_approx(hand.global_position), "WeaponSocket at the brain's hand")
	var stats := rig.skin_stats()
	assert_eq([stats.layers, stats.posed_frames, stats.modifier_runs], [false, 0, 0], "skin_stats says nothing ran")


func test_a_stage_1_heavy_is_tip_matched_in_posed() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var a := GameData.get_action("ability.heavy_1")
	var samples: Array = []
	var on_posed := func() -> void:
		if p.controller.action == a and p.controller.phase() == ActionDef.Phase.ACTIVE:
			var seg := p.weapon_segment_global(a, p.controller.active_fraction())
			var vis := rig.visible_weapon_segment()
			samples.append([seg, vis, float(rig.modifier().stats.get("fist_error_m", 1.0)), float(rig.modifier().stats.get("arc", 0.0))])
	rig.posed.connect(on_posed)
	p.controller.request(&"attack", {"action_id": "ability.heavy_1"})
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 150)
	rig.posed.disconnect(on_posed)
	assert_true(samples.size() >= a.active_ticks - 1, "the ACTIVE frames were measured (%d)" % samples.size())
	var worst_out := 0.0
	var worst_deg := 0.0
	var worst_fist := 0.0
	for smp: Array in samples:
		if float(smp[3]) < 0.999:
			continue   # the arm still blending into the arc
		var seg: PackedVector3Array = smp[0]
		var vis: Array = smp[1]
		for i in TipMatching.OUTER_HALF_SAMPLES:
			var t := 0.5 + 0.5 * float(i) / float(TipMatching.OUTER_HALF_SAMPLES - 1)
			var pt: Vector3 = (vis[0] as Vector3).lerp(vis[1], t)
			worst_out = maxf(worst_out, pt.distance_to(Geometry3D.get_closest_point_to_segment(pt, seg[0], seg[1])) - p.weapon_radius)
		worst_deg = maxf(worst_deg, rad_to_deg(((vis[1] as Vector3) - (vis[0] as Vector3)).angle_to(seg[1] - seg[0])))
		worst_fist = maxf(worst_fist, float(smp[2]))
	assert_true(worst_out <= 1e-3, "the visible weapon's outer half stays inside the tested capsule (worst %.3f m out)" % worst_out)
	assert_true(worst_deg <= TipMatching.MAX_ANGLE_DEG, "at most %d degrees off the tested direction (worst %.1f)" % [
		TipMatching.MAX_ANGLE_DEG, worst_deg])
	assert_true(worst_fist <= TipMatching.FIST_TOLERANCE_M, "the fist within 0.01 m of its target (worst %.4f m)" % worst_fist)


func test_flash_and_tint_reach_every_surface_and_the_weapon() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var mats := GiantLook.materials(rig.model())
	assert_true(mats.size() >= 10, "the giant's shader materials (%d)" % mats.size())
	var weapon_mats: Array = rig.get("_materials")
	var weapon_base: Array = rig.get("_base_colors")
	assert_true(weapon_mats.size() > 0 and weapon_base.size() == weapon_mats.size(), "the weapon's flat materials")
	rig.flash(1.0)
	await step_ticks(1)
	for m: ShaderMaterial in mats:
		var f: Variant = m.get_shader_parameter("flash")
		assert_true(f is Vector3 and (f as Vector3).length() > 0.1, "%s flashes (%s)" % [m.shader.resource_path.get_file(), f])
	for m: StandardMaterial3D in weapon_mats:
		assert_true(m.emission.r > 0.1, "the weapon flashes")
	await step_ticks(40)
	for m: ShaderMaterial in mats:
		assert_true((m.get_shader_parameter("flash") as Vector3).length() < 1e-3, "and fades")
	var tint := Color(0.45, 0.70, 1.0, 0.35)
	rig.set_status_tint(tint)
	await step_ticks(1)
	for m: ShaderMaterial in mats:
		var t: Variant = m.get_shader_parameter("tint")
		assert_true(t is Vector4 and (t as Vector4).is_equal_approx(Vector4(tint.r, tint.g, tint.b, tint.a)),
			"%s takes the status tint (%s)" % [m.shader.resource_path.get_file(), t])
	for i in weapon_mats.size():
		var m := weapon_mats[i] as StandardMaterial3D
		assert_true(m.albedo_color.is_equal_approx((weapon_base[i] as Color) * RigPaint.tint_multiplier(tint)), "the weapon too")
	rig.set_status_tint(Color(0, 0, 0, 0))
	await step_ticks(1)
	for m: ShaderMaterial in mats:
		assert_true(is_zero_approx((m.get_shader_parameter("tint") as Vector4).w), "and lets it go")


func test_apply_look_on_the_live_giant_and_growth_keeps_it() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var before := rig.shown_meshes()
	var rec := Appearance.preset_record("appearance_preset.ash_raider")
	assert_false(rec.is_empty(), "the preset exists")
	p.appearance.set_record(rec)
	await step_ticks(1)
	var shown := rig.shown_meshes()
	assert_true(shown != before, "the look changes the meshes shown (%s -> %s)" % [before, shown])
	assert_eq(rig.look_name(), "appearance_preset.ash_raider", "the rig names the look")
	assert_true(p.growth.debug_set_stage(4).ok, "stage 4")
	await step_ticks(2)
	var k := float(p.profile.height_m) / CombatRules.REFERENCE_HEIGHT_M
	assert_near(k, 3.0, 1e-3, "stage 4 is three times stage 1")
	assert_true(rig.body.scale.is_equal_approx(Vector3.ONE * k), "Body scales by k (%s)" % rig.body.scale)
	assert_eq(rig.shown_meshes(), shown, "the look is kept")
	assert_eq(rig.look_name(), "appearance_preset.ash_raider", "and named")


func test_render_layers_by_mesh_kind_and_the_first_person_mask() -> void:
	var p := await _grounded()
	var model := _rig(p).model()
	for id: String in model.index.meshes:
		var e: Dictionary = model.index.meshes[id]
		var cat := str(e.get("category", ""))
		var want := int(LAYER_OF.get(cat, 0))
		if cat == "body":
			want = {"Body_Head": 3, "Body_Torso": 2, "Body_Limbs": 1}.get(id, 0)
		elif cat == "garment":
			want = 2 if str(e.get("part", "")) == "torso" else 1
		assert_eq(model.mesh(id).layers, 1 << (want - 1), "%s (%s) on layer %d" % [id, cat, want])
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
	var mask := p.camera_rig.camera.cull_mask
	assert_eq(mask & 0b110, 0, "first person culls layers 2 and 3")
	assert_true((mask & 1) != 0, "and draws layer 1")
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)


func test_skin_stats_count_what_ran() -> void:
	SkinnedRig.enable_for_tests()
	var before: Dictionary = SkinnedRig.run_stats()
	var p := await _grounded()
	var rig := _rig(p)
	await step_ticks(10)
	var stats := rig.skin_stats()
	assert_true(stats.layers, "layers on")
	assert_true(int(stats.posed_frames) >= 10 and int(stats.modifier_runs) >= 10,
		"posed frames and modifier runs counted (%d, %d)" % [stats.posed_frames, stats.modifier_runs])
	assert_eq(stats.look, rig.look_name(), "the look's name")
	assert_eq(stats.shown_meshes, rig.shown_meshes(), "the meshes shown")
	var run := SkinnedRig.run_stats()
	assert_true(int(run.posed_frames) - int(before.posed_frames) >= 10, "the run's totals grow")
	assert_true(int(run.rigs) > int(before.rigs), "and count the rig")
	for key in ["look", "layers", "posed_frames", "modifier_runs", "held_visual_writes", "shown_meshes", "rig_footfalls", "rigs"]:
		assert_true(run.has(key), "SKIN_STATS has %s" % key)
