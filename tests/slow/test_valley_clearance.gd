extends IntegrationSuite
## Stage-3 clearance of the return leg (P15, plan §3.17, §4.2 clearance rules; slow, runs with
## --slow): with the barricade, the practice gate and the Deadfall out of the way (as they are on
## the return leg), the giant navigation layer (4) has a path for every stage-3 leg - Kingsfall ->
## causeway -> courtyard -> bridge -> village -> Grove -> Deadfall -> Barrow - and along each
## path, sampled every 2 m:
##   * a stage-3 capsule (r 1.65 m, h 7.92 m, lifted like the growth check) overlaps no world,
##     breakable or blocker shape (no roof, nothing in the giant's way);
##   * the corridor is at least 8 m wide: horizontal rays at right angles to the path, at the
##     knee and at the shoulder, reach at least 8 m between the walls on the two sides (the
##     plan's "required corridors are >= 8 m wide").
## Also: every spawn point of the shipped encounters stands on its definition's navigation layer.

const STAGE3_RADIUS := 1.65
const STAGE3_HEIGHT := 7.92
const MIN_WIDTH_M := 8.0
## A ray that hits nothing within this distance counts as open on that side.
const RAY_M := 12.0
const SAMPLE_M := 2.0
const WALL_MASK := HitQueryAdapter.LAYER_WORLD | 32

var level: LevelRoot


func before_each() -> void:
	await super()
	level = null


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


## The return leg's waypoints, Kingsfall to the Barrow (plan §4.2 item 8).
func _legs(lv: LevelRoot) -> Array:
	var kingsfall := ValleyProbe.shrine(lv, "valley.shrine.kingsfall").growth_pad_position()
	var grove := ValleyProbe.shrine(lv, "valley.shrine.grove").growth_pad_position()
	return [
		["Kingsfall", kingsfall],
		["the causeway", lv.marker("valley.marker.causeway").global_position],
		["the courtyard", lv.marker("valley.marker.ruins_courtyard").global_position],
		["the bridge", lv.marker("valley.marker.bridge").global_position],
		["the village square", Vector3(45, 0, -20)],
		["the Grove", grove],
		["the Deadfall", lv.marker("valley.marker.deadfall").global_position],
		["the Barrow", Vector3(-55, 0, -160)],
	]


func test_the_return_leg_fits_a_stage_3_giant() -> void:
	level = ValleyProbe.instance(true)
	world.add_child(level)
	var lv := level
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	# The return leg: every road-blocking prop is out of the way.
	for id: String in ValleyProbe.LINK_PROPS:
		var bp := ValleyProbe.prop(lv, id) as BreakableProp
		assert_true(bp != null and bp.force_open("test"), "%s is out of the way" % id)
	await ValleyProbe.wait_for_map_update(self, lv)
	await step_ticks(2)
	var space := lv.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = STAGE3_RADIUS
	cap.height = STAGE3_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = PlayerGrowth.CLEARANCE_MASK
	q.collide_with_areas = false
	var legs := _legs(lv)
	var total_m := 0.0
	var samples := 0
	for i in legs.size() - 1:
		var from: Vector3 = legs[i][1]
		var to: Vector3 = legs[i + 1][1]
		var what := "%s -> %s" % [legs[i][0], legs[i + 1][0]]
		var ok: bool = await ValleyProbe.settle(self, lv, from, to, ValleyProbe.GIANT, true)
		assert_true(ok, "%s: a giant path" % what)
		var path := ValleyProbe.path(lv, from, to, ValleyProbe.GIANT)
		var blocked := PackedStringArray()
		var narrow := PackedStringArray()
		for s: Array in _samples(path):
			var at: Vector3 = s[0]
			var dir: Vector3 = s[1]
			samples += 1
			q.transform = Transform3D(Basis(), Vector3(at.x, at.y, at.z) + Vector3.UP * (STAGE3_HEIGHT * 0.5 + PlayerGrowth.CLEARANCE_LIFT_M))
			var hits := space.intersect_shape(q, 1)
			if not hits.is_empty():
				blocked.append("%s (%s)" % [_fmt(at), (hits[0].collider as Node).name if hits[0].collider is Node else "?"])
			var width := _width(space, at, dir)
			if width < MIN_WIDTH_M:
				narrow.append("%s %.1f m" % [_fmt(at), width])
		total_m += _length(path)
		assert_eq(blocked, PackedStringArray(), "%s: a stage-3 body fits all along (blocked at %s)" % [what, blocked])
		assert_eq(narrow, PackedStringArray(), "%s: the corridor is at least 8 m wide (narrow at %s)" % [what, narrow])
	print("    valley: the stage-3 return leg: %.0f m of giant paths, %d samples" % [total_m, samples])
	assert_true(total_m > 300.0, "a return leg of several hundred metres (%.0f m)" % total_m)


## Every spawn point of the shipped encounters (not only the plan's: P10b's smoke test checks
## those) stands on its definition's navigation layer - the village captain beside the barricade's
## road and the ambush's archer on the watchtower included.
func test_every_encounter_spawn_stands_on_its_navigation_layer() -> void:
	level = ValleyProbe.instance(true)
	world.add_child(level)
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "navigation ready")
	var checked := 0
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.get("level", "")) != "level.valley":
			continue
		for sp: Dictionary in rec.get("spawns", []):
			var layers := int(GameData.get_record(str(sp.definition)).get("nav_layers", 1))
			var layer := layers & -layers
			var at := ValleyProbe.v3(sp.position_m)
			var on := NavigationServer3D.region_get_closest_point(level.nav_region(layer), at)
			assert_true(ValleyProbe.flat(on, at) < 0.3 and absf(on.y - at.y) < 1.0,
				"%s (%s) stands on nav layer %d (closest %s)" % [sp.entity_id, rec.id, layer, on])
			checked += 1
	assert_true(checked >= 50, "every spawn of the Valley's encounters (%d)" % checked)


## Points every SAMPLE_M along `path` with the path's direction there: [[point, dir], ...].
static func _samples(path: PackedVector3Array) -> Array:
	var out: Array = []
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var seg := Vector3(b.x - a.x, 0.0, b.z - a.z)
		var length := seg.length()
		if length < 1e-3:
			continue
		var dir := seg / length
		var n := maxi(1, int(ceil(length / SAMPLE_M)))
		for k in n:
			out.append([a.lerp(b, float(k) / n), dir])
	return out


## The corridor's width at `at` across `dir`: the open distance to the left plus to the right
## (each at most RAY_M), the smaller of the knee (1 m) and shoulder (6 m) heights.
func _width(space: PhysicsDirectSpaceState3D, at: Vector3, dir: Vector3) -> float:
	var side := Vector3(-dir.z, 0.0, dir.x)
	var best := INF
	for h: float in [1.0, 6.0]:
		var o := at + Vector3.UP * h
		var sum := 0.0
		for s: float in [1.0, -1.0]:
			var ray := PhysicsRayQueryParameters3D.create(o, o + side * s * RAY_M, WALL_MASK)
			ray.collide_with_areas = false
			var hit := space.intersect_ray(ray)
			sum += RAY_M if hit.is_empty() else o.distance_to(hit.position)
		best = minf(best, sum)
	return best


static func _length(path: PackedVector3Array) -> float:
	var m := 0.0
	for i in path.size() - 1:
		m += ValleyProbe.flat(path[i], path[i + 1])
	return m


static func _fmt(v: Vector3) -> String:
	return "(%.0f, %.0f)" % [v.x, v.z]
