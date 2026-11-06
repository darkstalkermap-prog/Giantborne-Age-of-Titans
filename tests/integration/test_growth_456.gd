extends IntegrationSuite
## Growth stages 4-6 (P26, plan M6-M9 §2.9, §5.14): a giant grown 1 -> 6 (debug grow) has every
## field of the stage's profile - capsule, floor snap, camera and zoom fraction, lock range, weapon
## geometry (a club fitting stage 6), hurtboxes and the lock anchor scaled by k, resources keeping
## their fractions - and the stage's size-gate mask in its body mask and titan bits in its
## navigation query mask; Heavy Footfall's and Thunder Roar's radius and Boulder Hurl's range follow
## the stage; a shrine with growth_requires_conditions refuses growth until they hold; first person
## at stages 4-6 puts the eye in the merged rig's head and hides the head; lights 1-2 and the heavy
## reach a soldier and a wolf from contact to 0.9 x reach (the swept geometry the swings use).

const SHRINE := "res://scenes/world/shrine.tscn"
const ATTACKS := ["ability.light_1", "ability.light_2", "ability.heavy_1"]
## Expected per stage 1..6 (data/abilities: heavy_footfall, thunder_roar, boulder_hurl).
const FOOTFALL_M := [3.0, 4.0, 5.0, 6.5, 8.0, 9.5]
const ROAR_M := [6.0, 6.0, 6.0, 9.0, 11.0, 13.0]
const HURL_M := [25.0, 25.0, 25.0, 32.0, 38.0, 44.0]
## The mask bits of each stage: its size gates (layers 7-9) and the titan navigation bits.
const SIZE_MASK := [448, 448, 448, 384, 256, 0]
const NAV_QUERY := [16, 16, 16, 48, 112, 240]

var blocked_events: Array[Array] = []


func before_each() -> void:
	await super()
	blocked_events.clear()
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 6})
	Events.growth_blocked.connect(_on_blocked)


func after_each() -> void:
	if Events.growth_blocked.is_connected(_on_blocked):
		Events.growth_blocked.disconnect(_on_blocked)
	await super()


func _on_blocked(_t: int, id: String, reason: String, message: String) -> void:
	blocked_events.append([id, reason, message])


func _profile(stage: int) -> Dictionary:
	return PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), stage)


func _grounded_player(pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	return p


## Every field the profile of `stage` sets, on the live giant.
func _check_stage(p: GiantPlayer, stage: int, health_frac: float) -> void:
	var prof := _profile(stage)
	var what := "stage %d" % stage
	var k := float(prof.height_m) / CombatRules.REFERENCE_HEIGHT_M
	assert_eq(p.growth_stage, stage, "%s: growth_stage" % what)
	var cap := p.body_shape.shape as CapsuleShape3D
	assert_near(cap.radius, float(prof.capsule_radius_m), 1e-6, "%s: capsule radius" % what)
	assert_near(cap.height, float(prof.capsule_total_height_m), 1e-6, "%s: capsule height" % what)
	assert_near(p.floor_snap_length, maxf(0.3, float(prof.step_height_m)), 1e-6, "%s: floor snap = step height" % what)
	assert_near(p.entity.combatant.height_m, float(prof.height_m), 1e-6, "%s: combatant height" % what)
	assert_near(p.lock.range_m, float(prof.lock_range_m), 1e-6, "%s: lock range" % what)
	assert_eq(p.camera_rig.profile.get("id"), prof.id, "%s: the camera follows the profile" % what)
	var g1 := _profile(1)
	var frac := (float(g1.camera_distance_m) - float(g1.camera_zoom_min_m)) / (float(g1.camera_zoom_max_m) - float(g1.camera_zoom_min_m))
	assert_near(p.camera_rig.desired_distance, lerpf(float(prof.camera_zoom_min_m), float(prof.camera_zoom_max_m), frac),
		1e-4, "%s: the zoom keeps its fraction (arm up to %.1f m)" % [what, float(prof.camera_zoom_max_m)])
	var ws := float(prof.get("weapon_scale", 1.0))
	assert_near(p.weapon_length, 1.85 * ws, 1e-4, "%s: club length x weapon_scale %.2f" % [what, ws])
	assert_near(p.weapon_radius, 0.45 * ws, 1e-4, "%s: club radius x weapon_scale" % what)
	var bonus := PlayerGrowth.resource_bonus(prof)
	var pools := p.entity.combatant.pools
	assert_near(pools.health_max, 500.0 + float(bonus.get("health", 0.0)), 1e-4, "%s: health max with the growth bonus" % what)
	assert_near(pools.health, health_frac * pools.health_max, 1e-3, "%s: health keeps its fraction" % what)
	var torso := p.get_node("Hurtboxes/Torso") as Node3D
	var torso_shape := (torso.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
	assert_true(torso_shape.size.is_equal_approx(Vector3(1.4, 1.5, 0.9) * k), "%s: torso hurtbox x k" % what)
	assert_true(torso.position.is_equal_approx(Vector3(0, 2.35, 0) * k), "%s: torso hurtbox position x k" % what)
	assert_true((p.get_node("Anchors/Torso") as Node3D).position.is_equal_approx(Vector3(0, 2.3, 0) * k),
		"%s: lock anchor x k" % what)
	assert_near(p.rig.body_scale, k, 1e-6, "%s: rig body scale k" % what)
	assert_eq(p.growth.size_gate_mask(), SIZE_MASK[stage - 1], "%s: size-gate mask" % what)
	assert_eq(p.collision_mask, PlayerGrowth.ACTOR_MASK | SIZE_MASK[stage - 1],
		"%s: the body collides with the size gates of the stages above it" % what)
	assert_eq(p.growth.nav_query_mask(), NAV_QUERY[stage - 1], "%s: titan navigation query mask" % what)
	assert_eq(p.nav_layers, int(prof.nav_layers), "%s: navigation layers (no level: the profile's)" % what)
	var footfall := GameData.get_action("ability.heavy_footfall")
	var roar := GameData.get_action("ability.thunder_roar")
	var hurl := GameData.get_action("ability.boulder_hurl")
	assert_near(p.attack.runner.pulse_radius(footfall), FOOTFALL_M[stage - 1], 1e-4, "%s: Heavy Footfall radius" % what)
	assert_near(p.attack.runner.pulse_radius(roar), ROAR_M[stage - 1], 1e-4, "%s: Thunder Roar radius" % what)
	assert_near(p.attack.stage_range(hurl, 25.0), HURL_M[stage - 1], 1e-4, "%s: Boulder Hurl range" % what)
	assert_near(float(p.attack.stage_spec(hurl).range_m), HURL_M[stage - 1], 1e-4, "%s: and its projectile's" % what)


func test_growth_1_to_6_follows_every_field() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var pools := p.entity.combatant.pools
	pools.health = 0.5 * pools.health_max
	_check_stage(p, 1, 0.5)
	for stage in range(2, 7):
		var r: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(r.ok, "debug grow to %d (%s)" % [stage, r.get("reason", "")])
		_check_stage(p, stage, 0.5)
		if stage >= 4:
			_check_reach(p, stage)
			await _check_first_person(p, stage)
		await step_ticks(2)
	assert_eq(_profile(6).display_name, "Titan (62 ft)", "stage 6 is the Titan, 18.9 m")
	var cap := p.body_shape.shape as CapsuleShape3D
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), p.global_position + Vector3.UP * (cap.height * 0.5 + 0.01))
	q.collision_mask = PlayerGrowth.CLEARANCE_MASK
	q.exclude = [p.get_rid()]
	assert_eq(p.get_world_3d().direct_space_state.intersect_shape(q, 4).size(), 0, "the stage-6 capsule overlaps nothing")
	assert_near(p.global_position.y, 0.0, 0.1, "and stands on the floor")


func test_a_shrine_waits_for_its_growth_conditions() -> void:
	TestFixtures.record_override("shrine.sandbox", {"growth_requires_conditions": [{"type": "flag", "flag": "test.p26.oath"}],
		"growth_conditions_text": ["Swear the oath at the standing stones first."]})
	var s: Shrine = (load(SHRINE) as PackedScene).instantiate()
	s.world_id = "test.shrine"
	s.shrine_id = "shrine.sandbox"
	s.position = Vector3(0, 0, -12)
	world.add_child(s)
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var refused := s.grow(p, 2)
	assert_false(refused.ok, "no growth while the condition does not hold")
	assert_eq(refused.reason, "conditions", "reason conditions")
	assert_eq(refused.message, "Swear the oath at the standing stones first.", "the condition's own line")
	assert_eq(blocked_events, [["player", "conditions", refused.message]], "growth_blocked says so")
	assert_eq(s.growth_waiting_text(), refused.message, "the shrine shows what it waits for")
	assert_eq(p.growth_stage, 1, "still stage 1")
	WorldState.set_flag("test.p26.oath", true)
	assert_eq(s.growth_waiting_text(), "", "nothing left to wait for")
	var grown := s.grow(p, 2)
	assert_true(grown.ok, "grows once it holds (%s)" % grown.message)
	assert_eq(p.growth_stage, 2, "stage 2")


## First person at `stage`: the eye at 0.92 x the height, inside the merged rig's head, which the
## camera culls (then back to third person).
func _check_first_person(p: GiantPlayer, stage: int) -> void:
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	p.camera_rig.yaw = 0.0
	p.camera_rig.pitch = 0.0
	await get_tree().process_frame
	var prof := _profile(stage)
	var cam := p.camera_rig.camera.global_position
	var eye_y := p.global_position.y + float(prof.height_m) * float(prof.eye_height_ratio)
	assert_near(cam.y, eye_y, 0.05, "stage %d: the eye at %.2f m (0.92 x the height)" % [stage, eye_y - p.global_position.y])
	var head := p.get_node("Visual/Body/Torso/Head") as MeshInstance3D
	var box := head.global_transform * head.get_aabb()
	assert_true(cam.y >= box.position.y and cam.y <= box.end.y + 0.05,
		"stage %d: the eye is at the merged head's height (%.2f in %.2f-%.2f)" % [stage, cam.y, box.position.y, box.end.y])
	var centre := box.get_center()
	var off := Vector2(cam.x - centre.x, cam.z - centre.z).length()
	assert_true(off <= maxf(box.size.x, box.size.z), "stage %d: and at its face (%.2f m from its centre)" % [stage, off])
	assert_eq(head.layers, SceneKit.FP_HIDDEN, "stage %d: the head is on the first-person hidden layer" % stage)
	assert_eq(p.camera_rig.camera.cull_mask & SceneKit.FP_HIDDEN, 0, "stage %d: and first person culls it" % stage)
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON)


## The swept geometry of lights 1-2 and the heavy (PlayerAttack.aimed_offset / sweep_reaches, what a
## swing aims and tests with) reaches a 1.8 m soldier and a 0.9 m wolf at contact + 0.3 m, at
## mid-reach and at 0.9 x reach (the real swings: tests/slow/test_growth_route_456.gd).
func _check_reach(p: GiantPlayer, stage: int) -> void:
	var reach := float(p.profile.melee_reach_m)
	for kind: String in ["soldier", "wolf"]:
		var rec := GameData.get_record("enemy." + kind)
		var tr := float(rec.capsule_radius_m)
		var th := float(rec.height_m)
		var contact := float(p.profile.capsule_radius_m) + tr
		for d: float in [contact + 0.3, 0.5 * (contact + 0.9 * reach), 0.9 * reach]:
			for id: String in ATTACKS:
				var a := GameData.get_action(id)
				var off := p.attack.aimed_offset(a, d, 0.0, tr, th)
				assert_true(p.attack.sweep_reaches(a, off, d, 0.0, tr, th),
					"stage %d: %s reaches a %s %.2f m away (contact %.2f, reach %.1f)" % [stage, id, kind, d, contact, reach])
