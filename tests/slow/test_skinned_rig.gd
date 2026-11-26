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
##   * the crosshair probe meets the skinned body where it is and only there;
##   * skin_stats() and SkinnedRig.run_stats() count what ran;
##   * P50: the tree holds every source of plan M11 §2.3 and the flinches, every family has its grip, and the fist's
##     landmarks in the hand bone's space put the fist where the index's stage-1 grip_r is;
##   * Gate A (lens 6): the sources' balanced, gated tree gives every leaf the chain's weight (source_weights()) and
##     opens the gate over every leaf that weighs; the hair's sway (P46) reaches the card hair and beard; the eyes
##     look along the camera's facing and toward the lock target, within the shader's quarter of the iris.

const LAYER_OF := {"body": 0, "eyes": 3, "hair": 3, "beard": 3, "bead": 3}   # P56: the beads ride the head's layer


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
	for clip in ["idle", "walk", "run", "airborne", "death", "grip_r", "grip_l", "open_r", "open_l",
			# P50 wires P48's clips II (plan M11 §2.3)
			"sprint", "turn_l", "turn_r", "stomp_r", "land", "brace", "roar", "flinch_f", "flinch_b", "flinch_l", "flinch_r",
			"grip_club", "grip_sword", "grip_hammer", "grip_axe", "grip_fist", "grip_tree", "carry_two_hand", "fp_rest"]:
		assert_true(names.has(clip), "the %s clip" % clip)
	for clip in ["idle", "walk", "run", "sprint"]:
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
			want = 2 if str(e.get("part", "")) == "torso" else (3 if str(e.get("part", "")) == "head" else 1)   # P54: head
		elif cat == "accessory" or cat == "armour":
			want = int(e.get("layer", 2))   # P54: on its bone's layer (the arm ring's 1, the neck's and the belt's 2); B1 too
		assert_eq(model.mesh(id).layers, 1 << (want - 1), "%s (%s) on layer %d" % [id, cat, want])
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
	var mask := p.camera_rig.camera.cull_mask
	assert_eq(mask & 0b110, 0, "first person culls layers 2 and 3")
	assert_true((mask & 1) != 0, "and draws layer 1")
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)


## The crosshair probe (tests/support/crosshair_probe.gd) measures the skinned giant by its parts' triangles:
## a ray at the chest (the spine_03 bone) from 3 m in front meets Body_Torso on the chest's surface, one from
## behind on the back, one 2 m to the side misses; a camera 3 m in front looking at the chest is obscured by
## the giant, one 3 m to the side is not (the positive control for the routes' and first person's probes).
func test_the_crosshair_probe_measures_the_skinned_body() -> void:
	var p := await _grounded()
	var torso := _rig(p).model().mesh("Body_Torso")
	var sk := torso.get_node(torso.skeleton) as Skeleton3D
	var chest := sk.global_transform * sk.get_bone_global_pose(sk.find_bone("spine_03")).origin
	var fwd := -p.global_transform.basis.z
	var side := p.global_transform.basis.x
	var front := CrosshairProbe.skinned_distance(torso, chest + fwd * 3.0, -fwd)
	var back := CrosshairProbe.skinned_distance(torso, chest - fwd * 3.0, fwd)
	assert_true(front > 2.0 and front < 2.95, "the ray from the front meets the chest's surface (%.3f m of 3)" % front)
	assert_true(back > 2.5 and back < 3.0, "the ray from behind meets the back (%.3f m of 3)" % back)
	assert_eq(CrosshairProbe.skinned_distance(torso, chest + fwd * 3.0 + side * 2.0, -fwd), INF, "a ray 2 m to the side misses")
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.global_position = chest + fwd * 3.0
	cam.look_at(chest)
	var probe := CrosshairProbe.new(cam, [p])
	assert_true(probe.sample(), "a camera in front looking at the chest is obscured (%s at %.3f m)" % [probe.last_blocker, probe.last_distance])
	assert_true(probe.last_blocker.begins_with("Visual/Body/Model/"), "by the model (%s)" % probe.last_blocker)
	cam.global_position = chest + fwd * 3.0 + side * 3.0
	cam.look_at(chest + side * 3.0)
	assert_false(CrosshairProbe.new(cam, [p]).sample(), "one 3 m to the side is not")
	cam.queue_free()


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


func test_the_sources_the_grips_and_the_fist_landmarks() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var bt := rig.animation_tree().tree_root as AnimationNodeBlendTree
	for node: String in ["idle_clip", "brace_clip", "turn_side", "gait", "sprint", "charge_gait", "stomp_r_seek", "roar_seek",
			"land_seek", "air_clip", "death_seek", "flinch_f_seek", "flinch_b_seek", "flinch_l_seek", "flinch_r_seek", "hand_r",
			"open_l", "grip_l", "fist_l", "fp"]:
		assert_true(bt.has_node(StringName(node)), "the tree's %s node" % node)
	assert_true(bt.get_node(&"flinch") is AnimationNodeAdd2, "the flinches are added on top")
	for g: String in SkinnedRig.GATE_NAMES:
		assert_true(bt.get_node(StringName(g)) is AnimationNodeTransition, "the gate %s" % g)
	for fam: String in ["club", "sword", "hammer", "axe", "fists", "tree"]:
		assert_true(SkinnedRig.clip_library().has_animation(str(SkinnedRig.GRIP_CLIPS[fam])), "%s's grip clip" % fam)
	assert_eq(rig.grip_clip(), "grip_club", "the club closes the fist with its grip")
	var sk := rig.skeleton()
	var hand := sk.get_bone_global_rest(sk.find_bone("hand_r"))
	var lm: Dictionary = rig.model().index.landmarks
	var gl: Array = lm.grip_local_r
	var at_rest := PoseBrainModifier.relative_transform(sk, rig.body) * (hand * Vector3(gl[0], gl[1], gl[2]))
	var grip: Array = lm.grip_r
	assert_true(at_rest.distance_to(Vector3(grip[0], grip[1], grip[2])) < 0.005,
		"grip_local_r in the hand bone's space is the index's grip_r at rest (%s against %s)" % [at_rest, grip])
	var tm := TipMatching.for_fist(rig.model().index)
	assert_eq(tm.source, "fist", "tip matching is built for the fist")
	assert_true(float(tm.reach.r) < 1.385 and float(tm.reach.r) > 1.2, "its reach is the fist's (%.3f)" % float(tm.reach.r))


## Gate A: SLOT_PARAMS' shares multiplied down the balanced tree are source_weights() for any weights, and every gate
## over a leaf that weighs is open (an unweighted branch may be closed: it is not evaluated).
func test_the_gated_source_tree_weighs_each_leaf_as_the_chain() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	var rng := RandomNumberGenerator.new()
	rng.seed = 30
	var worst := 0.0
	var shut := 0
	for trial in 60:
		for key: String in SkinnedRig.SOURCE_CHAIN:
			rig._w[key] = 0.0 if rng.randf() < 0.5 else (1.0 if rng.randf() < 0.2 else rng.randf())
		var eff := rig.source_weights()
		rig._send_all(eff, float(eff.move))
		var a := rig._want
		var g := func(i: int) -> float: return float(a[i])
		# SLOT_PARAMS 8.. : sources, sources_lo, stance_brace, turn_move, sources_hi, charge_pulse, stomp_roar, land_fall, air_dead
		var lo: float = 1.0 - g.call(8)
		var hi: float = g.call(8)
		var leaf := {
			"stance": lo * (1.0 - g.call(9)) * (1.0 - g.call(10)), "brace": lo * (1.0 - g.call(9)) * g.call(10),
			"turn": lo * g.call(9) * (1.0 - g.call(11)), "move": lo * g.call(9) * g.call(11),
			"charge": hi * (1.0 - g.call(12)) * (1.0 - g.call(13)), "stomp": hi * (1.0 - g.call(12)) * g.call(13) * (1.0 - g.call(14)),
			"roar": hi * (1.0 - g.call(12)) * g.call(13) * g.call(14), "land": hi * g.call(12) * (1.0 - g.call(15)),
			"air": hi * g.call(12) * g.call(15) * (1.0 - g.call(16)), "dead": hi * g.call(12) * g.call(15) * g.call(16)}
		for key: String in SkinnedRig.SOURCE_LEAVES:
			worst = maxf(worst, absf(float(leaf[key]) - float(eff[key])))
		# the gates over each leaf: GATE_NAMES 0..8
		var over := {"turn": [0, 2], "move": [1, 2], "charge": [3, 6, 8], "stomp": [4, 6, 8], "roar": [4, 6, 8], "land": [7, 8],
			"air": [5, 7, 8], "dead": [5, 7, 8]}
		for key: String in over:
			if float(eff[key]) > 0.0:
				for i: int in over[key]:
					if rig._want_gate[i] != 1:
						shut += 1
	assert_true(worst < 1e-9, "each leaf weighs what the chain gave it (worst %s)" % worst)
	assert_eq(shut, 0, "no gate is closed over a leaf that weighs")


## Gate A: the hair's sway (P46) is the rig's own step now: it finds the card hair and beard (not the shells) and
## writes their head_motion when the head moves.
func test_the_sway_reaches_the_card_hair() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	await step_ticks(2)
	var model := rig.model()
	var cards := 0
	for mi: MeshInstance3D in rig._sway_meshes:
		var id := str(mi.name)
		assert_true(mi.material_override is ShaderMaterial and (mi.material_override as ShaderMaterial).shader == GiantLook.HAIR_SHADER,
			"%s is a card mesh on the hair shader" % id)
		cards += 1
	var expect := 0
	for cat: String in ["hair", "beard"]:
		for id in GiantLook.meshes_of(model.index, cat):
			if GiantLook.mesh_kind(model.index.meshes[id]) == "hair":
				expect += 1
	assert_eq(cards, expect, "every card hair and beard mesh (%d)" % expect)
	var shown: MeshInstance3D = null
	for mi: MeshInstance3D in rig._sway_meshes:
		if mi.visible:
			shown = mi
	assert_true(shown != null, "the default look shows a card style")
	p.router.set_injected_move(Vector2(0, 1))
	await step_ticks(20)
	p.router.set_injected_move(Vector2.ZERO)
	var hm: Variant = (shown.material_override as ShaderMaterial).get_shader_parameter("head_motion")
	assert_true(hm is Vector3 and (hm as Vector3).length() > 0.0 and (hm as Vector3).length() <= GiantLook.SWAY_MAX_M + 1e-6,
		"a walk sways the shown cards (%s)" % [hm])


## Gate A: the eyes' look (P51's uniform) follows the camera's facing, level, and the lock target, within the
## shader's quarter of the iris; the giant's right is +x.
func test_the_eyes_look_along_the_camera_and_at_the_lock_target() -> void:
	SkinnedRig.enable_for_tests()
	var p := await _grounded()
	var rig := _rig(p)
	await step_ticks(20)
	var eyes := GiantLook.mesh_node(rig.model(), rig.model().index, "Eyes")
	var mat := eyes.material_override as ShaderMaterial
	assert_true(rig.eye_look().length() < 0.05, "the camera behind him: the eyes ahead (%s)" % rig.eye_look())
	p.camera_rig.yaw -= deg_to_rad(40.0)   # the camera turns to his right
	await step_ticks(30)
	assert_true(rig.eye_look().x > 0.2 and rig.eye_look().x <= SkinnedRig.EYE_LOOK_MAX, "the eyes turn right (%s)" % rig.eye_look())
	assert_true(absf(rig.eye_look().y) < 0.05, "and stay level (%s)" % rig.eye_look())
	assert_true((mat.get_shader_parameter("look") as Vector2).distance_to(rig.eye_look()) < 1e-3, "the Eyes material has it")
	p.camera_rig.yaw += deg_to_rad(40.0)
	await step_ticks(30)
	assert_true(absf(rig.eye_look().x) < 0.05, "and come back (%s)" % rig.eye_look())
	spawn_soldier(Vector3(6, 0.05, -10))
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(30)
	assert_true(p.camera_rig.lock_focus_point() != Vector3.INF, "locked on the soldier")
	assert_true(rig.eye_look().y < -0.1, "the eyes look down at the soldier's chest (%s)" % rig.eye_look())
