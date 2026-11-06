extends IntegrationSuite
## P24a (plan M6-M9 §3.6, open_world_tech.md §4.4): the real giant on the generated test world's
## streamed terrain. At stages 1, 2 and 3 it walks the loop round (-248, -248) that crosses the
## x = -256 and z = -256 seams twice each (the route's first five points) at 97 % of its walk speed or
## more, never with its feet under the ground; at stage 1 it climbs the 30-degree ramp across the
## x = 256 seam and the 35-degree ramp across the z = 256 seam (the border rule's limit) to their
## plateaus. Streaming is deterministic (the step quota) and every walk starts on a ready ring.

const SCENE := "res://scenes/test/test_world.tscn"
const LOOP := [Vector2(-300, -300), Vector2(-196, -300), Vector2(-196, -196), Vector2(-300, -196), Vector2(-300, -300)]
const RAMPS := [
	["30-degree ramp", [Vector2(212, -128), Vector2(300, -128)]],
	["35-degree ramp", [Vector2(-128, 212), Vector2(-128, 300)]],
]
const MIN_SPEED_RATIO := 0.97
const WAYPOINT_M := 2.5
const MAX_SINK_M := 0.1

var _world: WorldRoot


func _load_world() -> WorldRoot:
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	p.router.use_injection = true
	await _ring(w, p.global_position)
	return w


## Loads the ring around `at` (deterministic slices) and lets the physics settle.
func _ring(w: WorldRoot, at: Vector3) -> void:
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 200:
		w.streamer.load_ring_slice(at)
		guard += 1
	await step_ticks(3)


## Puts the giant at `p` on the ground, facing `toward`, with its ring ready.
func _place(w: WorldRoot, p: Vector2, toward: Vector2) -> void:
	var giant := w.player()
	await _ring(w, Vector3(p.x, 0.0, p.y))
	var y := w.height_at(Vector3(p.x, 0.0, p.y))
	GameSession.place_player(giant, Transform3D(Basis(Vector3.UP, TargetingRules.yaw_of(Vector3(toward.x - p.x, 0, toward.y - p.y))),
		Vector3(p.x, y + 0.3, p.y)))
	await step_ticks(20)


## Walks the giant through `points` with the stick (the camera along each segment). Returns the
## metres, ticks, worst sink, seam crossings and whether every point was reached.
func _walk(w: WorldRoot, points: Array, timeout_s := 120.0) -> Dictionary:
	var p := w.player()
	var out := {"reached": 0, "metres": 0.0, "ticks": 0, "sink": 0.0, "seams": 0, "note": ""}
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
		if not ok:
			out.note = "stopped before %s at %s" % [target, p.global_position]
			break
		out.reached = int(out.reached) + 1
	p.router.set_injected_move(Vector2.ZERO)
	return out


static func _stick(to: Vector3, yaw: float) -> Vector2:
	var d := Vector3(to.x, 0.0, to.z).normalized()
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	return Vector2(d.dot(right), d.dot(forward)).normalized()


func test_the_seam_loop_at_stages_1_to_3() -> void:
	var w: WorldRoot = await _load_world()
	var p := w.player()
	for stage in [1, 2, 3]:
		if stage > 1:
			assert_true(bool(p.growth.debug_set_stage(stage).ok), "grown to stage %d" % stage)
		await _place(w, LOOP[0], LOOP[1])
		var r := await _walk(w, LOOP)
		var walk := float(p.profile.get("walk_speed_mps", 5.0))
		var speed := float(r.metres) / maxf(int(r.ticks) / 60.0, 0.01)
		assert_eq(int(r.reached), LOOP.size() - 1, "stage %d: the loop is walked (%s)" % [stage, r.note])
		assert_true(int(r.seams) >= 4, "stage %d: four seam crossings (%d)" % [stage, r.seams])
		assert_true(speed >= MIN_SPEED_RATIO * walk, "stage %d: %.2f m/s, at least 97 %% of %.1f (%.1f %%)" % [stage,
			speed, walk, 100.0 * speed / walk])
		assert_true(float(r.sink) <= MAX_SINK_M, "stage %d: never under the terrain (worst %.3f m)" % [stage, r.sink])
	assert_eq(int(w.streamer.stats().thrash), 0, "no chunk thrashed while walking the loop")


func test_the_30_and_35_degree_ramps_across_seams() -> void:
	var w: WorldRoot = await _load_world()
	for ramp: Array in RAMPS:
		var pts: Array = ramp[1]
		await _place(w, pts[0], pts[1])
		var start_y := w.player().global_position.y
		var r := await _walk(w, pts, 90.0)
		assert_eq(int(r.reached), 1, "%s: climbed at stage 1 (%s)" % [ramp[0], r.note])
		assert_true(w.player().global_position.y > start_y + 20.0, "%s: up onto the plateau (%.1f m -> %.1f m)" % [
			ramp[0], start_y, w.player().global_position.y])
		assert_true(int(r.seams) >= 1, "%s: across a chunk border" % ramp[0])
		assert_true(float(r.sink) <= MAX_SINK_M, "%s: never under the terrain (worst %.3f m)" % [ramp[0], r.sink])
