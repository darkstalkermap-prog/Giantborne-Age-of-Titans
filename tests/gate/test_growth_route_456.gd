extends IntegrationSuite
## The 3-size route at stages 4-6 (P26, plan M6-M9 §2.9, §5.14; spec §15 camera/growth): on P24a's
## generated test world (scenes/test/test_world.tscn, streamed terrain) the giant at stages 4, 5 and
## 6, in third and in first person, walks a loop round (-256, -256) that crosses the x = -256 and
## z = -256 chunk seams twice each, at 95 % of its walk speed or more, never with its feet under the
## ground, its capsule never inside the terrain, its camera never inside the world, and the crosshair
## never on its own body for more than 30 consecutive ticks; at stage 6 it climbs the 30-degree ramp
## across the x = 256 seam to its plateau. On the integration floor, real swings: lights 1-2 and the
## heavy land on a soldier and a wolf from contact to 0.9 x reach at stages 4-6 (third person), and a
## downward light and heavy hit a soldier at the giant's feet in first person.

const SCENE := "res://scenes/test/test_world.tscn"
const LOOP := [Vector2(-280, -280), Vector2(-232, -280), Vector2(-232, -232), Vector2(-280, -232), Vector2(-280, -280)]
const RAMP := [Vector2(212, -128), Vector2(300, -128)]
## P24a's 97 % at stages 1-3 was over 104 m sides; this loop's sides are 48 m, so the start and the
## three corners weigh twice as much (a stage-6 giant turns 3.7 m of capsule at 8.1 m/s).
const MIN_SPEED_RATIO := 0.95
const WAYPOINT_M := 2.5
const MAX_SINK_M := 0.1
const MAX_OBSCURED_TICKS := 30
const ATTACKS := ["ability.light_1", "ability.light_2", "ability.heavy_1"]
const WOLF := "res://scenes/enemies/wolf.tscn"


func before_each() -> void:
	await super()
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 6})


func _load_world() -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	w.player().router.use_injection = true
	await _ring(w, w.player().global_position)
	return w


func _ring(w: WorldRoot, at: Vector3) -> void:
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 200:
		w.streamer.load_ring_slice(at)
		guard += 1
	await step_ticks(3)


func _place(w: WorldRoot, p: Vector2, toward: Vector2) -> void:
	await _ring(w, Vector3(p.x, 0.0, p.y))
	var y := w.height_at(Vector3(p.x, 0.0, p.y))
	GameSession.place_player(w.player(), Transform3D(Basis(Vector3.UP,
		TargetingRules.yaw_of(Vector3(toward.x - p.x, 0, toward.y - p.y))), Vector3(p.x, y + 0.3, p.y)))
	await step_ticks(20)


## Walks the giant through `points`; every tick: the feet against the terrain, the capsule and the
## camera against the world, the crosshair against the giant's own body.
func _walk(w: WorldRoot, points: Array, timeout_s := 90.0) -> Dictionary:
	var p := w.player()
	var out := {"reached": 0, "metres": 0.0, "ticks": 0, "sink": 0.0, "seams": 0, "inside": 0, "capsule": 0, "note": ""}
	var space := p.get_world_3d().direct_space_state
	var cam_q := PhysicsPointQueryParameters3D.new()
	cam_q.collision_mask = HitQueryAdapter.OCCLUDER_MASK
	var cap := (p.body_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	cap.radius -= 0.05   # the body touches the ground: test the capsule a hair inside its surface
	cap.height -= 0.1
	var cap_q := PhysicsShapeQueryParameters3D.new()
	cap_q.shape = cap
	cap_q.collision_mask = HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE
	var probe := CrosshairProbe.new(p.camera_rig.camera, [p])
	var prev := p.global_position
	var last_chunk := w.chunk_at(prev)
	for k in range(1, points.size()):
		var target: Vector2 = points[k]
		var seg: Vector2 = target - (points[k - 1] as Vector2)
		var ok := false
		for i in int(timeout_s * 60.0):
			var to := Vector3(target.x - p.global_position.x, 0.0, target.y - p.global_position.z)
			if to.length() < WAYPOINT_M:
				ok = true
				break
			var yaw := TargetingRules.yaw_of(Vector3(seg.x, 0.0, seg.y))
			p.camera_rig.yaw = yaw
			if p.camera_rig.is_first_person():
				p.camera_rig.pitch = deg_to_rad(-20.0)
			p.router.set_injected_move(_stick(to, yaw))
			await step_ticks(1)
			out.ticks = int(out.ticks) + 1
			var pos := p.global_position
			out.metres = float(out.metres) + Vector2(pos.x - prev.x, pos.z - prev.z).length()
			prev = pos
			var chunk := w.chunk_at(pos)
			if chunk != last_chunk:
				out.seams = int(out.seams) + 1
				last_chunk = chunk
			var ground := w.height_at(pos)
			if not is_nan(ground):
				out.sink = maxf(float(out.sink), ground - pos.y)
			cam_q.position = p.camera_rig.camera.global_position
			if not space.intersect_point(cam_q, 1).is_empty():
				out.inside = int(out.inside) + 1
				out.note = "camera inside the world at %s" % cam_q.position
			if int(out.ticks) % 4 == 0:
				cap_q.transform = Transform3D(Basis(), pos + Vector3.UP * (p.body_shape.position.y))
				if not space.intersect_shape(cap_q, 1).is_empty():
					out.capsule = int(out.capsule) + 1
			probe.sample()
		if not ok:
			out.note = "stopped before %s at %s" % [target, p.global_position]
			break
		out.reached = int(out.reached) + 1
	p.router.set_injected_move(Vector2.ZERO)
	out["max_obscured"] = probe.max_consecutive
	out["blocker"] = probe.worst_blocker
	return out


static func _stick(to: Vector3, yaw: float) -> Vector2:
	var d := Vector3(to.x, 0.0, to.z).normalized()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Vector2(d.dot(right), d.dot(forward)).normalized()


func test_the_seam_loop_at_stages_4_to_6_in_both_camera_modes() -> void:
	var w: WorldRoot = await _load_world()
	var p := w.player()
	for stage in [4, 5, 6]:
		await _place(w, LOOP[0], LOOP[1])
		var grown: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(grown.ok, "grown to stage %d (%s)" % [stage, grown.get("reason", "")])
		for first_person in [false, true]:
			var mode := "first person" if first_person else "third person"
			p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON if first_person else CameraRig.Mode.THIRD_PERSON)
			await _place(w, LOOP[0], LOOP[1])
			var r := await _walk(w, LOOP)
			var walk := float(p.profile.get("walk_speed_mps", 5.0))
			var speed := float(r.metres) / maxf(int(r.ticks) / 60.0, 0.01)
			var what := "stage %d, %s" % [stage, mode]
			assert_eq(int(r.reached), LOOP.size() - 1, "%s: the loop is walked (%s)" % [what, r.note])
			assert_true(int(r.seams) >= 4, "%s: four seam crossings (%d)" % [what, r.seams])
			assert_true(speed >= MIN_SPEED_RATIO * walk, "%s: %.2f m/s, at least 95 %% of %.1f (%.1f %%)" % [what, speed, walk,
				100.0 * speed / walk])
			assert_true(float(r.sink) <= MAX_SINK_M, "%s: never under the terrain (worst %.3f m)" % [what, r.sink])
			assert_eq(int(r.capsule), 0, "%s: the capsule is never inside the terrain" % what)
			assert_eq(int(r.inside), 0, "%s: the camera is never inside the world (%s)" % [what, r.note])
			assert_true(int(r.max_obscured) <= MAX_OBSCURED_TICKS, "%s: the crosshair is off the giant's own body (worst %d ticks, %s)" % [
				what, r.max_obscured, r.blocker])
			print("    route 456: %s: %.0f m at %.2f m/s (%.1f %%), %d seams, sink %.3f m, obscured %d" % [what, r.metres,
				speed, 100.0 * speed / walk, r.seams, r.sink, r.max_obscured])
	p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON)
	assert_eq(int(w.streamer.stats().thrash), 0, "no chunk thrashed")


func test_a_stage_6_giant_climbs_the_30_degree_ramp_across_a_seam() -> void:
	var w: WorldRoot = await _load_world()
	var p := w.player()
	await _place(w, RAMP[0], RAMP[1])
	var grown: Dictionary = p.growth.debug_set_stage(6)
	assert_true(grown.ok, "stage 6 (%s)" % grown.get("reason", ""))
	await _place(w, RAMP[0], RAMP[1])
	var start_y := p.global_position.y
	var r := await _walk(w, RAMP, 60.0)
	assert_eq(int(r.reached), 1, "climbed at stage 6 (%s)" % r.note)
	assert_true(p.global_position.y > start_y + 20.0, "up onto the plateau (%.1f m -> %.1f m)" % [start_y, p.global_position.y])
	assert_true(int(r.seams) >= 1, "across a chunk border")
	assert_true(float(r.sink) <= MAX_SINK_M, "never under the terrain (worst %.3f m)" % r.sink)
	assert_eq(int(r.inside), 0, "the camera never inside the world (%s)" % r.note)


## One swing of `attack_id`, straight ahead, on the target `id`: how many of its hits landed.
func _swing(p: GiantPlayer, attack_id: String, id: String) -> int:
	p.camera_rig.yaw = 0.0
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	await step_ticks(2)
	var a := GameData.get_action(attack_id)
	if p.controller.request(&"attack", {"action_id": attack_id}) != CombatController.Verdict.ACCEPT:
		return -1
	await step_ticks(a.windup_ticks + a.active_ticks + 2)
	var landed := 0
	for r in hits_on(id):
		if r.event.action_id == attack_id:
			landed += 1
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	return landed


func test_swings_land_from_contact_to_0_9_reach_at_stages_4_to_6() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.entity.combatant.unkillable = true
	var n := 0
	for stage in [4, 5, 6]:
		assert_true(bool(p.growth.debug_set_stage(stage).ok), "stage %d" % stage)
		await step_ticks(2)
		var reach := float(p.profile.melee_reach_m)
		for kind in ["soldier", "wolf"]:
			var rec := GameData.get_record("enemy." + kind)
			var contact := float(p.profile.capsule_radius_m) + float(rec.capsule_radius_m)
			for d: float in [contact + 0.3, 0.9 * reach]:
				for attack_id: String in ATTACKS:
					n += 1
					var id := "test.p26_%s_%d" % [kind, n]
					var target: EnemyActor = spawn_soldier(Vector3(0, 0.05, -d), 0.0, id) if kind == "soldier" \
						else TestSpawn.enemy(world, WOLF, Vector3(0, 0.05, -d), id, false, 0.0)
					target.entity.combatant.unkillable = true
					var landed := await _swing(p, attack_id, id)
					assert_eq(landed, 1, "stage %d: %s lands on a %s %.2f m away (contact %.2f, reach %.1f)" % [stage,
						attack_id, kind, d, contact, reach])
					target.queue_free()
					await step_ticks(1)


func test_first_person_downward_light_and_heavy_hit_a_soldier_at_the_feet() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.entity.combatant.unkillable = true
	p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
	var n := 0
	for stage in [4, 5, 6]:
		assert_true(bool(p.growth.debug_set_stage(stage).ok), "stage %d" % stage)
		await step_ticks(2)
		var d := float(p.profile.capsule_radius_m) + 0.35 + 0.3
		for attack_id: String in ["ability.light_1", "ability.heavy_1"]:
			n += 1
			var id := "test.p26_fp_%d" % n
			var s := spawn_soldier(Vector3(0, 0.05, -d), 0.0, id)
			s.entity.combatant.unkillable = true
			p.camera_rig.pitch = deg_to_rad(-60.0)   # looking down at the feet
			var landed := await _swing(p, attack_id, id)
			assert_eq(landed, 1, "stage %d, first person: %s hits a soldier %.2f m away, at the feet" % [stage, attack_id, d])
			s.queue_free()
			await step_ticks(1)
