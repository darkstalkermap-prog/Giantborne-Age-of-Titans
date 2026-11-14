extends IntegrationSuite
## Regressions from the camera/targeting review: arm collapse at a doorway, first-person body
## occlusion, guard facing, stick flicks, and switching with the target behind the camera. P43: the
## first-person occlusion test checks the realistic giant's render layers and the camera's masks.


func test_follow_arm_stays_long_through_a_doorway() -> void:
	# Two wall blocks leave a 2.6 m wide, 5 m tall doorway at z = -6 (like the sandbox).
	add_box(Vector3(10, 7, 1), Vector3(-6.3, 3.5, -6))
	add_box(Vector3(10, 7, 1), Vector3(6.3, 3.5, -6))
	add_box(Vector3(2.6, 2, 1), Vector3(0, 6, -6))
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(10)
	var min_arm := INF
	p.router.set_injected_move(Vector2(0, 1))
	for i in 150:
		await step_ticks(1)
		p.camera_rig.yaw = 0.0
		if p.global_position.z < -3.0 and p.global_position.z > -9.0:
			min_arm = minf(min_arm, p.camera_rig.current_distance)
	assert_true(p.global_position.z < -9.0, "walked through the doorway (z=%.1f)" % p.global_position.z)
	assert_true(min_arm > 3.0, "arm never collapses while passing the doorway (min %.2f m)" % min_arm)


## P43 (plan M10 decision 8): the realistic giant's render layers and the camera's masks. The head, hair,
## beard and eyes are on layer 3, the torso and the garments' core parts on layer 2, the limbs and the
## garments' limb parts on layer 1 (the index says which, and these lists pin it); first person culls
## layers 2 and 3 and draws the limbs and the weapon; third person draws everything.
const HEAD_MESHES := ["Body_Head", "Eyes", "Hair_crop", "Hair_long_back", "Beard_full", "Beard_short"]
const TORSO_MESHES := ["Body_Torso", "Garment_tunic_core", "Garment_braies_core", "Garment_jerkin", "Garment_furs",
	"Garment_belt"]
const LIMB_MESHES := ["Body_Limbs", "Garment_tunic_limbs", "Garment_braies_limbs", "Garment_boots", "Garment_bracers"]


func test_first_person_hides_the_giants_torso() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(2)
	var model := p.get_node("Visual/Body/Model") as GiantModel
	var third := p.camera_rig.camera.cull_mask
	assert_eq(third, CameraRig.CULL_ALL, "third person draws every layer")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	var mask := p.camera_rig.camera.cull_mask
	assert_eq(mask, CameraRig.CULL_FIRST_PERSON, "first person's mask")
	assert_eq(mask & (1 << (CameraRig.HEAD_LAYER - 1)), 0, "first person culls layer 3")
	assert_eq(mask & (1 << (CameraRig.TORSO_LAYER - 1)), 0, "and layer 2")
	assert_true((mask & 1) != 0, "and draws layer 1")
	var listed := {}
	for group: Array in [[HEAD_MESHES, CameraRig.HEAD_LAYER], [TORSO_MESHES, CameraRig.TORSO_LAYER], [LIMB_MESHES, 1]]:
		for id: String in group[0]:
			listed[id] = true
			var mi := model.mesh(id)
			assert_true(mi != null, "%s is in the model" % id)
			if mi == null:
				continue
			assert_eq(mi.layers, 1 << (int(group[1]) - 1), "%s on render layer %d" % [id, group[1]])
			assert_eq((mi.layers & mask) != 0, int(group[1]) == 1, "%s %s in first person" % [id,
				"drawn" if int(group[1]) == 1 else "not drawn"])
			assert_true((mi.layers & third) != 0, "%s drawn in third person" % id)
	for id: String in model.index.meshes:
		assert_true(listed.has(id), "%s is one of the listed meshes" % id)
	var weapon := p.equipment.visual as Node3D
	assert_true(weapon != null and weapon.get_parent() == p.get_node("Visual/Body/WeaponSocket"), "the weapon hangs at the socket")
	for mi: MeshInstance3D in weapon.find_children("*", "MeshInstance3D", true, false):
		assert_true((mi.layers & mask) != 0, "the weapon's %s stays visible" % mi.name)


func test_block_guards_the_aim_while_backing_off() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await step_ticks(8)
	p.router.set_injected_hold(&"block", true)
	p.router.inject_edge(&"block_press")
	p.router.set_injected_move(Vector2(0, -1))   # back off while blocking
	await step_ticks(25)
	assert_eq(p.controller.state, CombatController.State.BLOCKING, "blocking")
	assert_true(absf(angle_difference(p.rotation.y, p.camera_rig.yaw)) < 0.05, "guard keeps facing the aim")
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, -3), 40.0)
	await step_ticks(1)
	assert_eq(hits[-1].outcome, HitResult.Outcome.BLOCKED, "a hit from where the player looks is blocked")


func test_only_fast_stick_flicks_switch_targets() -> void:
	var router := InputRouter.new()
	world.add_child(router)
	await get_tree().process_frame
	router.consume()
	var flicked := false
	for i in 20:   # slow push to full deflection over 20 ticks: ordinary looking
		Input.action_press("look_right", float(i + 1) / 20.0)
		await get_tree().process_frame
		if router.consume().edges.has(&"stick_flick_right"):
			flicked = true
	assert_false(flicked, "a slow push is camera look, not a flick")
	Input.action_release("look_right")
	await get_tree().process_frame
	router.consume()
	Input.action_press("look_right", 1.0)   # snap from centre to full deflection
	await get_tree().process_frame
	assert_true(router.consume().edges.has(&"stick_flick_right"), "a fast flick switches (third-person lock)")
	var tapped := false
	for i in 30:   # ... but holding it afterwards is looking: no first-person tap
		await get_tree().process_frame
		if router.consume().edges.has(&"stick_tap_right"):
			tapped = true
	Input.action_release("look_right")
	await get_tree().process_frame
	if router.consume().edges.has(&"stick_tap_right"):
		tapped = true
	assert_false(tapped, "fast push then hold is first-person look, not a tap")
	Input.action_press("look_right", 1.0)   # flick and release quickly
	await get_tree().process_frame
	router.consume()
	for i in 4:
		await get_tree().process_frame
		router.consume()
	Input.action_release("look_right")
	await get_tree().process_frame
	assert_true(router.consume().edges.has(&"stick_tap_right"), "a quick flick-and-release is a first-person tap")


func test_switch_target_when_current_is_behind_camera() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	spawn_soldier(Vector3(0, 0.05, -8), PI, "soldier_a")
	spawn_soldier(Vector3(-3, 0.05, 9), 0.0, "soldier_b")
	spawn_soldier(Vector3(3, 0.05, 9), 0.0, "soldier_c")
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "soldier_a", "locked ahead")
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(1)
	p.camera_rig.yaw = PI   # first person: look back; the lock does not force the view
	await step_ticks(2)
	p.router.inject_edge(&"target_right")
	await step_ticks(1)
	assert_true(p.lock.target_id in ["soldier_b", "soldier_c"], "switches to a visible target on screen (got '%s')" % p.lock.target_id)
