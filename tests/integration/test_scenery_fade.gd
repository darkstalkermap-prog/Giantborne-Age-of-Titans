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

const SHARED := "res://assets/world/shared/"
const DISTRICTS := ["forest", "hills", "hollow", "kingsfall", "village"]


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
