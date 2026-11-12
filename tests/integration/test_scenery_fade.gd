extends IntegrationSuite
## M8 screenshot pass (V1): trees that fade out of the giant's way (SceneryFade,
## assets/shaders/scenery_fade.gdshader).
##   * The rule (SceneryFade.fade_at, the shader's on the CPU): a tree fades out whole near the camera,
##     by CONE_FADE inside the cone from the camera to the giant (and on past him) or to the locked
##     target, with a soft edge; nothing behind the camera, beyond a cone's reach or outside it; nothing
##     in a pass whose eye is not the camera (a shadow pass: the trees' shadows stay whole) or while
##     the camera parameter is off. The dither discards that share of the pixels.
##   * The camera rig sets the parameters every frame: itself with its near radius (third person a share
##     of the arm, first person a share of the height), the giant's middle with his cone (third person
##     only), the locked target's lock point with its cone; it clears them when it leaves.
##   * The trees are drawn with the fade: the world's two tree meshes (the other shared meshes keep the
##     vertex material) and the Valley's district Scenery (trunks and crowns, in their old colours),
##     and nothing else of the Valley.
##   * M8 screenshot pass fix-up: the shader runs the rule the tests measure. Its own text, run on the
##     CPU (tests/support/shader_rule.gd), against SceneryFade: the same constants and global uniforms,
##     the same fade at points all round random views (the near sphere, the cones, their soft edges and
##     reach, behind the camera, a shadow pass), a 4 x 4 Bayer dither and the same share of its tile
##     discarded at every fade. (Nothing tied them: the shader repeated the constants and the maths by hand.)
##   * P39f: the shader's vertex() and fragment() run too (ShaderRule.run_body): the world position through
##     MODEL_MATRIX, the vertex colours' sRGB to linear (only where the output is linear), the eye from
##     INV_VIEW_MATRIX deciding the discard with the fade and the dither, and the albedo and roughness.

const SHARED := "res://assets/world/shared/"
const DISTRICTS := ["forest", "hills", "hollow", "kingsfall", "village"]
const ShaderRule := preload("res://tests/support/shader_rule.gd")
## The 4 x 4 ordered dither's thresholds in sixteenths (the shader's tile may be this one turned or flipped).
const BAYER_4 := [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


func test_the_fade_rule() -> void:
	var cam := Vector4(0, 10, 0, 4.0)
	var eye := Vector3(0, 10, 0)
	var foc := Vector4(0, 10, -20, 7.0)
	var none := Vector4.ZERO
	var near := SceneryFade.fade_at(Vector3(1, 10, 0), eye, cam, none, none)
	assert_near(near, 1.0, 0.001, "within the near core a tree fades out whole")
	var edge := SceneryFade.fade_at(Vector3(3.5, 10, 0), eye, cam, none, none)
	assert_true(edge > 0.0 and edge < 1.0, "softly towards the near radius (%.2f)" % edge)
	assert_eq(SceneryFade.fade_at(Vector3(5, 10, 0), eye, cam, none, none), 0.0, "and not beyond it")
	# the giant's cone: 0.5 m wide at the camera, 7 m at him (20 m off), on past him for 1.4 radii
	assert_near(SceneryFade.fade_at(Vector3(0, 10, -10), eye, cam, foc, none), SceneryFade.CONE_FADE, 0.001,
		"on the axis halfway: CONE_FADE")
	assert_near(SceneryFade.fade_at(Vector3(3.9, 10, -10), eye, cam, foc, none), SceneryFade.CONE_FADE, 0.001,
		"inside the radius there (0.5 + 3.5 m)")
	var soft := SceneryFade.fade_at(Vector3(4.8, 10, -10), eye, cam, foc, none)
	assert_true(soft > 0.0 and soft < SceneryFade.CONE_FADE, "a soft edge outside it (%.2f)" % soft)
	assert_eq(SceneryFade.fade_at(Vector3(6.5, 10, -10), eye, cam, foc, none), 0.0, "nothing beyond the edge")
	assert_eq(SceneryFade.fade_at(Vector3(0, 10, 8), eye, cam, foc, none), 0.0, "nothing behind the camera")
	assert_near(SceneryFade.fade_at(Vector3(6, 10, -21), eye, cam, foc, none), SceneryFade.CONE_FADE, 0.001,
		"beside the giant, at his radius")
	assert_near(SceneryFade.fade_at(Vector3(0, 10, -24), eye, cam, foc, none), SceneryFade.CONE_FADE, 0.001,
		"past him, where what he fights stands")
	assert_eq(SceneryFade.fade_at(Vector3(0, 10, -31), eye, cam, foc, none), 0.0, "but not beyond the reach")
	# the locked target's cone, reaching only half a radius past its lock point
	var tgt := Vector4(10, 10, -30, 3.0)
	var on_target_line := Vector3(5, 10, -15)
	assert_near(SceneryFade.fade_at(on_target_line, eye, cam, none, tgt), SceneryFade.CONE_FADE, 0.001,
		"on the way to the locked target")
	assert_eq(SceneryFade.fade_at(on_target_line, eye, cam, none, none), 0.0, "which only its cone clears")
	assert_eq(SceneryFade.fade_at(Vector3(10, 10, -30) + Vector3(1, 0, -3).normalized() * 4.0, eye, cam, none, tgt), 0.0,
		"nor far past the target")
	# another pass (a shadow map's eye) and no camera: nothing fades
	assert_eq(SceneryFade.fade_at(Vector3(1, 10, 0), Vector3(50, 80, 0), cam, foc, tgt), 0.0, "a shadow pass fades nothing")
	assert_eq(SceneryFade.fade_at(Vector3(0, 10, -10), eye, Vector4(0, 10, 0, 0), foc, tgt), 0.0,
		"nor anything while the camera parameter is off")
	assert_eq(SceneryFade.discarded_share(0.0), 0.0, "the dither keeps a surface that does not fade")
	assert_eq(SceneryFade.discarded_share(SceneryFade.CONE_FADE), 13.0 / 16.0, "CONE_FADE drops 13 of 16 pixels")
	assert_eq(SceneryFade.discarded_share(1.0), 1.0, "a whole fade drops them all")


func test_the_camera_sets_the_view_and_clears_it() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var s := spawn_soldier(Vector3(0, 0.05, -9), 0.0, "test.fade_soldier")
	await step_ticks(120)
	var rig := p.camera_rig
	var h := float(p.profile.height_m)
	var eye := rig.camera.global_position
	assert_true(Vector3(SceneryFade.camera.x, SceneryFade.camera.y, SceneryFade.camera.z).is_equal_approx(eye),
		"the camera's position (%s, the camera at %s)" % [SceneryFade.camera, eye])
	assert_near(SceneryFade.camera.w, maxf(SceneryFade.NEAR_MIN_M, SceneryFade.NEAR_ARM * rig.current_distance), 0.001,
		"the near radius: a share of the arm")
	var mid := p.global_position + Vector3.UP * h * SceneryFade.FOCUS_HEIGHT
	assert_true(Vector3(SceneryFade.focus.x, SceneryFade.focus.y, SceneryFade.focus.z).is_equal_approx(mid), "the giant's middle")
	assert_near(SceneryFade.focus.w, SceneryFade.FOCUS_RADII * h, 0.001, "his cone's radius: a share of his height")
	assert_eq(SceneryFade.target.w, 0.0, "no lock, no target cone")
	assert_eq(rig.scenery_fade_view().camera, SceneryFade.camera, "scenery_fade_view() is what the rig set")
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "test.fade_soldier", "the soldier is locked")
	await step_ticks(2)
	var anchor := rig.lock_focus_point()
	assert_true(Vector3(SceneryFade.target.x, SceneryFade.target.y, SceneryFade.target.z).is_equal_approx(anchor),
		"the target cone ends at the lock point the camera frames")
	assert_near(SceneryFade.target.w, maxf(SceneryFade.TARGET_MIN_M, SceneryFade.TARGET_RADII * s.entity.combatant.height_m), 0.001,
		"its radius: a share of the target's height, at least TARGET_MIN_M")
	rig.toggle_mode()
	await step_ticks(2)
	assert_true(rig.is_first_person(), "first person")
	assert_eq(SceneryFade.focus.w, 0.0, "first person: no cone to the giant (the camera is in his head)")
	assert_near(SceneryFade.camera.w, SceneryFade.FP_NEAR_RADII * h, 0.001, "the near radius a share of his height")
	assert_true(SceneryFade.target.w > 0.0, "the locked target's cone stays")
	assert_true(Vector3(SceneryFade.camera.x, SceneryFade.camera.y, SceneryFade.camera.z).is_equal_approx(rig.camera.global_position),
		"at the first-person eye")
	rig.toggle_mode()
	p.targeting.release_lock("test")
	await step_ticks(2)
	assert_eq(SceneryFade.target.w, 0.0, "released: no target cone")
	assert_true(SceneryFade.focus.w > 0.0, "third person again: the giant's cone")
	p.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq([SceneryFade.camera, SceneryFade.focus, SceneryFade.target], [Vector4.ZERO, Vector4.ZERO, Vector4.ZERO],
		"the rig left: nothing fades")


func test_the_trees_are_drawn_with_the_fade() -> void:
	for key: String in ["tree_pine", "tree_broadleaf"]:
		var mesh := load(SHARED + key + ".res") as Mesh
		var sm := mesh.surface_get_material(0) as ShaderMaterial
		assert_true(sm != null and sm.shader != null and sm.shader.resource_path == TreeSight.FADE_SHADER,
			"the world's %s is drawn with the scenery fade" % key)
		if sm != null:
			assert_eq(sm.get_shader_parameter("vertex_color_albedo"), true, "%s: its vertex colours as the albedo" % key)
			assert_near(float(sm.get_shader_parameter("roughness")), 0.95, 0.001, "%s: the vertex material's roughness" % key)
	for key: String in ["sapling", "bush", "rock", "reed", "heather", "log"]:
		var mesh := load(SHARED + key + ".res") as Mesh
		assert_true(mesh.surface_get_material(0) is StandardMaterial3D, "%s keeps the vertex material" % key)
	var scenery := 0
	for d: String in DISTRICTS:
		var root := (load("res://scenes/world/valley/%s.tscn" % d) as PackedScene).instantiate()
		for mmi: MultiMeshInstance3D in root.find_children("*", "MultiMeshInstance3D", true, false):
			var sm := mmi.material_override as ShaderMaterial
			var fades := sm != null and sm.shader != null and sm.shader.resource_path == TreeSight.FADE_SHADER
			if mmi.get_parent().name == "Scenery":
				scenery += 1
				assert_true(fades, "%s/%s (scenery) fades" % [d, mmi.name])
				if fades:
					var base := load("res://assets/materials/valley_%s.tres" % _mat_of(str(mmi.name))) as StandardMaterial3D
					assert_true(base != null and (sm.get_shader_parameter("albedo") as Color).is_equal_approx(base.albedo_color),
						"%s/%s keeps its colour" % [d, mmi.name])
			else:
				assert_false(fades, "%s/%s (not scenery) does not fade" % [d, mmi.name])
		root.free()
	assert_true(scenery >= 10, "the districts' tree MultiMeshes (%d)" % scenery)


## The Valley material of a Scenery MultiMesh named "<Mat>_<Kind>" ("LeavesDark_Cone" -> leaves_dark).
static func _mat_of(node_name: String) -> String:
	return node_name.split("_")[0].to_snake_case()


# --------------------------------------------------------------------------- the shader is the rule

## M8 screenshot pass fix-up (V1): the shader and SceneryFade - the copy of its rule that TreeSight and
## test_tree_fade_world measure every sight line with - are one rule. The shader's own text runs on the CPU
## (ShaderRule) against SceneryFade.fade_at: its constants and global uniforms are SceneryFade's; its
## scenery_fade() gives SceneryFade's fade at 400 points round random views - near the camera, at the cones'
## apex just past it, inside and at the soft edge of the giant's and the target's cones, past them and
## behind the camera, for the camera's pass and a shadow pass, with parts switched off - its dither is the
## 4 x 4 Bayer matrix, and fragment()'s discard drops the share of the tile SceneryFade.discarded_share
## gives, at every fade. (Nothing tied
## them: a CONE_FADE of 0.3 or a broken cone test in the shader passed every suite while the pines in front
## of the giant stayed solid.)
func test_the_shader_runs_the_rule_the_tests_measure() -> void:
	var rule = ShaderRule.from_file(TreeSight.FADE_SHADER)
	assert_eq(rule.error, "", "the shader's rule reads")
	if rule.error != "":
		return
	var consts := {"CONE_FADE": SceneryFade.CONE_FADE, "CONE_APEX_M": SceneryFade.CONE_APEX_M,
		"CONE_EDGE": SceneryFade.CONE_EDGE, "EDGE_M": SceneryFade.EDGE_M,
		"FOCUS_REACH_RADII": SceneryFade.FOCUS_REACH_RADII, "TARGET_REACH_RADII": SceneryFade.TARGET_REACH_RADII,
		"NEAR_CORE": SceneryFade.NEAR_CORE, "SAME_CAMERA_M": SceneryFade.SAME_CAMERA_M}
	for k: String in consts:
		assert_true(rule.constants.has(k), "the shader has %s" % k)
		assert_near(float(rule.constants.get(k, NAN)), float(consts[k]), 1e-6, "the shader's %s is SceneryFade's" % k)
	for k: String in rule.constants:
		assert_true(consts.has(k), "the shader's constant %s is one of SceneryFade's" % k)
	assert_eq(Array(rule.global_uniforms), [str(SceneryFade.PARAM_CAMERA), str(SceneryFade.PARAM_FOCUS),
		str(SceneryFade.PARAM_TARGET)], "its global uniforms are the parameters the camera sets")
	for k: String in ["scenery_fade", "cone_fade", "bayer4"]:
		assert_true(rule.functions.has(k), "the shader's %s()" % k)
	assert_true(rule.fragment_body.contains("scenery_fade(world_pos, eye)"),
		"fragment() fades by scenery_fade() at the fragment's world position, seen by its pass's eye")
	# The rule at points all round random views.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	var worst := 0.0
	var worst_at := ""
	var kinds := {"whole": 0, "cone": 0, "soft": 0, "none": 0}
	for i in 400:
		var cam_pos := Vector3(rng.randf_range(-50, 50), rng.randf_range(0, 40), rng.randf_range(-50, 50))
		var near_r := rng.randf_range(1.0, 9.0) if i % 10 != 0 else 0.0
		if i % 4 == 1:
			near_r = SceneryFade.NEAR_MIN_M   # the cones' apex, just past the smallest near sphere
		var to_focus := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.6, 0.2), rng.randf_range(-1, 1)).normalized()
		var foc_pos := cam_pos + to_focus * rng.randf_range(4.0, 40.0)
		var foc := Vector4(foc_pos.x, foc_pos.y, foc_pos.z, rng.randf_range(1.0, 12.0) if i % 7 != 0 else 0.0)
		var tgt_pos := foc_pos + Vector3(rng.randf_range(-20, 20), rng.randf_range(-5, 5), rng.randf_range(-20, 20))
		var tgt := Vector4(tgt_pos.x, tgt_pos.y, tgt_pos.z, rng.randf_range(1.5, 6.0) if i % 3 == 0 else 0.0)
		var cam := Vector4(cam_pos.x, cam_pos.y, cam_pos.z, near_r)
		# A point near the camera, or about one of the cones' axes: before, beside and past its focus.
		var p := cam_pos
		var aim: Vector4 = tgt if (i % 3 == 0 and i % 2 == 0) else foc
		var aim_pos := Vector3(aim.x, aim.y, aim.z)
		if i % 4 == 0:
			p = cam_pos + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized() \
				* rng.randf_range(0.0, near_r * 1.3 + 0.5)
		else:
			var axis := (aim_pos - cam_pos).normalized()
			var side := axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized() \
				.rotated(axis, rng.randf_range(-PI, PI))
			var span := cam_pos.distance_to(aim_pos)
			var s := rng.randf_range(-3.0, span * 1.5 + 2.0) if i % 4 != 1 else rng.randf_range(-1.0, 3.0)
			var r := SceneryFade.CONE_APEX_M + maxf(aim.w, 1.0) * clampf(s / span, 0.0, 1.0)
			p = cam_pos + axis * s + side * rng.randf_range(0.0, r * 1.6 + 1.0)
		var eye := cam_pos if i % 9 != 0 else cam_pos + Vector3(rng.randf_range(-60, 60), 80, rng.randf_range(-60, 60))
		rule.globals = {"scenery_fade_camera": cam, "scenery_fade_focus": foc, "scenery_fade_target": tgt}
		var got: Variant = rule.run("scenery_fade", [p, eye])
		if rule.error != "":
			break
		var want := SceneryFade.fade_at(p, eye, cam, foc, tgt)
		var diff := absf(float(got) - want)
		if diff > worst:
			worst = diff
			worst_at = "p %s eye %s cam %s focus %s target %s: shader %.5f, SceneryFade %.5f" % [p, eye, cam, foc, tgt,
				float(got), want]
		if want >= 0.999:
			kinds.whole += 1
		elif is_equal_approx(want, SceneryFade.CONE_FADE):
			kinds.cone += 1
		elif want > 0.0:
			kinds.soft += 1
		else:
			kinds.none += 1
	assert_eq(rule.error, "", "the shader's scenery_fade() runs")
	assert_true(worst < 1e-5, "the shader fades as SceneryFade does at all 400 points (worst %.6f%s)" % [worst,
		(" at " + worst_at) if worst_at != "" else ""])
	for k: String in kinds:
		assert_true(int(kinds[k]) >= 30, "the points cover the %s fade (%s)" % [k, str(kinds)])
	print("    the shader against SceneryFade: %s, worst difference %.8f" % [str(kinds), worst])
	# The dither: a 4 x 4 ordered (Bayer) matrix of thresholds, the same in every tile...
	var levels := PackedFloat32Array()
	for y in 4:
		for x in 4:
			levels.append(float(rule.run("bayer4", [Vector2(x + 0.5 + 8.0, y + 0.5 + 4.0)])) * 16.0)
	var bayer := false
	for t in 8:
		var same := true
		for y in 4:
			for x in 4:
				var u := y if t & 4 else x
				var v := x if t & 4 else y
				u = 3 - u if t & 1 else u
				v = 3 - v if t & 2 else v
				same = same and is_equal_approx(levels[y * 4 + x], float(BAYER_4[v][u]))
		bayer = bayer or same
	assert_true(bayer, "the shader's bayer4() is the 4 x 4 Bayer matrix (sixteenths by row: %s)" % str(levels))
	# ...and the share of a tile fragment()'s discard drops at each fade is SceneryFade.discarded_share.
	assert_true(rule.discard_condition != "", "fragment() discards by a condition (%s)" % rule.discard_condition)
	var shares := PackedStringArray()
	for n in 65:
		var f := n / 64.0
		var dropped := 0
		for y in 4:
			for x in 4:
				rule.globals = {"FRAGCOORD": Vector4(x + 0.5 + 8.0, y + 0.5 + 4.0, 0.5, 1.0)}
				if bool(rule.evaluate(rule.discard_condition, {"fade": f})):
					dropped += 1
		if rule.error != "":
			break
		if not is_equal_approx(dropped / 16.0, SceneryFade.discarded_share(f)):
			shares.append("fade %.3f: the shader drops %d of 16, SceneryFade.discarded_share %.3f" % [f, dropped,
				SceneryFade.discarded_share(f)])
	assert_eq(rule.error, "", "the shader's discard condition runs")
	assert_eq(shares.size(), 0, "the shader's dither drops what discarded_share says: %s" % "; ".join(shares))


## P39f (FOLLOWUPS, "From the M8 screenshot pass": "the scenery fade's shader test does not cover the shader's
## world position, eye and vertex-colour albedo lines"): the shader's own vertex() and fragment() run on the CPU
## (ShaderRule.run_body) with the built-ins Godot hands them, and give what they must:
##   * vertex(): world_pos is the vertex through MODEL_MATRIX (a mesh's or a MultiMesh instance's transform) -
##     at 200 random transforms and vertices, Transform3D * VERTEX - and the vertex colours turn from sRGB to
##     linear exactly as Color.srgb_to_linear does, only with vertex_color_albedo on and the output not sRGB
##     (the Compatibility renderer's output is sRGB: they stay as they are there, as a StandardMaterial3D's do);
##   * fragment(): the eye is INV_VIEW_MATRIX's origin - the camera's position for the camera's pass, so the
##     fade (SceneryFade.fade_at with that eye) and its dither decide the discard; another pass's eye fades
##     nothing - and the albedo is the uniform times the vertex colour with vertex_color_albedo, else the uniform;
##     the roughness is the uniform's.
func test_the_shader_stages_feed_the_rule() -> void:
	var rule = ShaderRule.from_file(TreeSight.FADE_SHADER)
	assert_eq(rule.error, "", "the shader reads")
	if rule.error != "":
		return
	assert_true(rule.vertex_body != "" and rule.fragment_body != "", "it has a vertex() and a fragment()")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3923
	var worst := 0.0
	for i in 200:
		var basis := Basis(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(),
			rng.randf_range(-PI, PI)).scaled(Vector3(rng.randf_range(0.5, 3.0), rng.randf_range(0.5, 3.0), rng.randf_range(0.5, 3.0)))
		var xf := Transform3D(basis, Vector3(rng.randf_range(-900, 900), rng.randf_range(-20, 200), rng.randf_range(-900, 900)))
		var v := Vector3(rng.randf_range(-6, 6), rng.randf_range(0, 12), rng.randf_range(-6, 6))
		var out: Dictionary = rule.run_body("vertex", {"MODEL_MATRIX": Projection(xf), "VERTEX": v, "COLOR": Vector4(1, 1, 1, 1),
			"vertex_color_albedo": false, "OUTPUT_IS_SRGB": true, "world_pos": Vector3.ZERO})
		if rule.error != "":
			break
		worst = maxf(worst, (out.world_pos as Vector3).distance_to(xf * v))
	assert_eq(rule.error, "", "vertex() runs")
	assert_true(worst < 1e-3, "world_pos is the vertex through MODEL_MATRIX at 200 transforms (worst %.6f m)" % worst)
	var colour_worst := 0.0
	var colours: Array = [Color(0.04, 0.0405, 0.5), Color(0.0, 1.0, 0.04045), Color(0.2, 0.6, 0.9)]
	for i in 61:
		colours.append(Color(rng.randf(), rng.randf(), rng.randf()))
	for c: Color in colours:
		var col := Vector4(c.r, c.g, c.b, 1.0)
		var base := {"MODEL_MATRIX": Projection(Transform3D.IDENTITY), "VERTEX": Vector3.ZERO, "COLOR": col,
			"world_pos": Vector3.ZERO}
		var linear: Dictionary = rule.run_body("vertex", base.merged({"vertex_color_albedo": true, "OUTPUT_IS_SRGB": false}))
		var want := c.srgb_to_linear()
		var got: Vector4 = linear.get("COLOR", Vector4.ZERO)
		colour_worst = maxf(colour_worst, Vector3(got.x - want.r, got.y - want.g, got.z - want.b).length())
		assert_eq(rule.run_body("vertex", base.merged({"vertex_color_albedo": true, "OUTPUT_IS_SRGB": true})).get("COLOR"), col,
			"an sRGB output keeps the vertex colour (%s)" % c)
		assert_eq(rule.run_body("vertex", base.merged({"vertex_color_albedo": false, "OUTPUT_IS_SRGB": false})).get("COLOR"), col,
			"without vertex_color_albedo the colour is left alone (%s)" % c)
	assert_eq(rule.error, "", "the colour lines run")
	assert_true(colour_worst < 1e-5, "sRGB to linear as Color.srgb_to_linear at %d colours (worst %.7f)" % [colours.size(), colour_worst])
	# fragment(): the eye, the fade and the dither, the albedo
	var kinds := {"discarded": 0, "kept": 0, "shadow": 0}
	for i in 200:
		var cam_pos := Vector3(rng.randf_range(-50, 50), rng.randf_range(2, 40), rng.randf_range(-50, 50))
		var near_r := rng.randf_range(2.0, 9.0)
		var foc_pos := cam_pos + Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.1), rng.randf_range(-1, 1)).normalized() * 20.0
		var foc := Vector4(foc_pos.x, foc_pos.y, foc_pos.z, 7.0)
		var cam := Vector4(cam_pos.x, cam_pos.y, cam_pos.z, near_r)
		var shadow_pass := i % 5 == 0
		var eye_at := cam_pos if not shadow_pass else cam_pos + Vector3(rng.randf_range(-60, 60), 90, rng.randf_range(-60, 60))
		var view_xf := Transform3D(Basis.looking_at(foc_pos - eye_at), eye_at)
		var p := cam_pos.lerp(foc_pos, rng.randf_range(-0.2, 1.4)) + Vector3(rng.randf_range(-4, 4), rng.randf_range(-3, 3), rng.randf_range(-4, 4))
		if i % 7 == 0:
			p = cam_pos + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * near_r * 0.6
		var frag := Vector4(float(rng.randi_range(0, 1279)) + 0.5, float(rng.randi_range(0, 719)) + 0.5, 0.5, 1.0)
		var albedo := Color(rng.randf(), rng.randf(), rng.randf())
		var vcol := Vector4(rng.randf(), rng.randf(), rng.randf(), 1.0)
		var with_vc := i % 2 == 0
		rule.globals = {"scenery_fade_camera": cam, "scenery_fade_focus": foc, "scenery_fade_target": Vector4.ZERO,
			"FRAGCOORD": frag}
		var out: Dictionary = rule.run_body("fragment", {"INV_VIEW_MATRIX": Projection(view_xf), "world_pos": p, "COLOR": vcol,
			"albedo": albedo, "roughness": 0.95, "vertex_color_albedo": with_vc, "ALBEDO": Vector3.ZERO, "METALLIC": -1.0,
			"SPECULAR": -1.0, "ROUGHNESS": -1.0})
		if rule.error != "":
			break
		var fade := SceneryFade.fade_at(p, eye_at, cam, foc, Vector4.ZERO)
		var threshold := float(rule.run("bayer4", [Vector2(frag.x, frag.y)]))
		var want_discard := fade > 0.0 and fade >= threshold + 1.0 / 32.0
		assert_eq(rule.discarded, want_discard, "fragment %d: discarded when the fade (%.3f, eye %s) passes the dither (%.3f)" % [i, fade,
			"the camera" if not shadow_pass else "a shadow pass", threshold])
		if shadow_pass:
			kinds.shadow += 1
			assert_false(rule.discarded, "fragment %d: a shadow pass's eye fades nothing" % i)
		if rule.discarded:
			kinds.discarded += 1
			continue
		kinds.kept += 1
		var a := Vector3(albedo.r, albedo.g, albedo.b)
		var want_albedo := a * Vector3(vcol.x, vcol.y, vcol.z) if with_vc else a
		assert_true((out.ALBEDO as Vector3).is_equal_approx(want_albedo), "fragment %d: the albedo %s (%s)" % [i,
			"times the vertex colour" if with_vc else "is the uniform", out.ALBEDO])
		assert_near(float(out.ROUGHNESS), 0.95, 1e-6, "fragment %d: the roughness uniform" % i)
		assert_near(float(out.METALLIC), 0.0, 1e-6, "fragment %d: not metallic" % i)
	assert_eq(rule.error, "", "fragment() runs")
	for k: String in kinds:
		assert_true(int(kinds[k]) >= 20, "the fragments cover the %s case (%s)" % [k, str(kinds)])
	print("    the shader's stages: %s, colour worst %.8f, position worst %.6f m" % [str(kinds), colour_worst, worst])
