extends IntegrationSuite
## P22 (plan M6-M9 §3.4 design 5; FOLLOWUPS, HOW_IT_PLAYS "Known issues"): the village yard pocket.
## Between cottages 3-5, the watchtower and the north palisade (x 62-72, z -50 to -35) the giant
## layer's navmesh had an island whose 3-4 m ways in a stage-2 or stage-3 giant could walk through
## but no path led out of. Two invisible fill boxes on the blockers layer (tools/data/valley_layout.json
## yard_fill_w / yard_fill_n) now fill the yard:
##   * no polygon of the giant layers (giant, small giant) lies in the yard;
##   * the fill is solid where the giant collides (the blockers layer is in its collision mask);
##   * every point of the giant layers just outside the fill has a path out to the village square,
##     and a stage-3 giant walks it.

const SQUARE := Vector3(52, 0, -20)
## The fill boxes [min x, max x, min z, max z] (the layout's segments with their thickness).
const FILL := [[62.0, 72.5, -50.0, -33.5], [72.5, 77.5, -50.0, -42.5]]
## The old pocket (FOLLOWUPS): nothing of the giant layers may remain inside.
const POCKET := [62.0, 72.0, -50.0, -35.0]
const GIANT_LAYERS := [ValleyProbe.GIANT, ValleyProbe.SMALL_GIANT]
const NAV := {ValleyProbe.GIANT: "res://assets/nav/valley_giant.res", ValleyProbe.SMALL_GIANT: "res://assets/nav/valley_small_giant.res"}

var level: LevelRoot


func after_each() -> void:
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await super()


static func _inside(p: Vector3, box: Array, margin := 0.0) -> bool:
	return p.x > float(box[0]) - margin and p.x < float(box[1]) + margin \
		and p.z > float(box[2]) - margin and p.z < float(box[3]) + margin


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func test_the_giant_layers_have_no_pocket_in_the_yard() -> void:
	for layer: int in GIANT_LAYERS:
		var nm := load(str(NAV[layer])) as NavigationMesh
		assert_true(nm != null and nm.get_polygon_count() > 100, "%s loads" % NAV[layer])
		if nm == null:
			continue
		var verts := nm.get_vertices()
		var inside := 0
		for i in nm.get_polygon_count():
			var c := Vector3.ZERO
			var poly := nm.get_polygon(i)
			for v in poly:
				c += verts[v]
			c /= float(poly.size())
			if _inside(c, POCKET):
				inside += 1
		assert_eq(inside, 0, "layer %d: no navmesh polygon in the old pocket" % layer)


func test_the_fill_is_solid_and_every_way_around_it_leads_out() -> void:
	level = ValleyProbe.instance(true)
	world.add_child(level)
	assert_true(await ValleyProbe.wait_for_navigation(self, level), "navigation ready")
	var space := level.get_world_3d().direct_space_state
	for box: Array in FILL:
		var centre := Vector3((float(box[0]) + float(box[1])) * 0.5, 2.0, (float(box[2]) + float(box[3])) * 0.5)
		var q := PhysicsPointQueryParameters3D.new()
		q.position = centre
		q.collision_mask = 32
		assert_true(space.intersect_point(q, 1).size() == 1, "the fill is solid at %s (blockers layer)" % centre)
	var p := level.player()
	assert_true(p.get_collision_mask_value(6), "the giant collides with the blockers layer")
	# Points of the giant layers 2 m outside each box's edges (every 2 m), on the navmesh: each has
	# a path to the village square.
	var map := level.nav_map()
	for layer: int in GIANT_LAYERS:
		var region := level.nav_region(layer)
		var checked := 0
		var stranded := PackedStringArray()
		for box: Array in FILL:
			var x0 := float(box[0]) - 2.0
			var x1 := float(box[1]) + 2.0
			var z0 := float(box[2]) - 2.0
			var z1 := float(box[3]) + 2.0
			var samples: Array[Vector3] = []
			var x := x0
			while x <= x1:
				samples.append(Vector3(x, 0, z0))
				samples.append(Vector3(x, 0, z1))
				x += 2.0
			var z := z0
			while z <= z1:
				samples.append(Vector3(x0, 0, z))
				samples.append(Vector3(x1, 0, z))
				z += 2.0
			for s in samples:
				var on := NavigationServer3D.region_get_closest_point(region, s)
				if ValleyProbe.flat(on, s) > 0.75 or _inside(on, FILL[0]) or _inside(on, FILL[1]):
					continue   # not on this layer's navmesh there (a wall, a cottage, the palisade)
				checked += 1
				var path := NavigationServer3D.map_get_path(map, on, SQUARE, true, layer)
				if path.is_empty() or ValleyProbe.flat(path[path.size() - 1], SQUARE) > 1.5:
					stranded.append("%s" % on)
		assert_true(checked >= 10, "layer %d: %d points around the fill on the navmesh" % [layer, checked])
		assert_eq(stranded, PackedStringArray(), "layer %d: every one leads out to the square" % layer)
	# A stage-3 giant beside the yard's old west way in (between the cottages) walks the path out.
	var start := NavigationServer3D.region_get_closest_point(level.nav_region(ValleyProbe.GIANT), Vector3(60, 0, -40))
	GameSession.place_player(p, Transform3D(Basis(), start + Vector3.UP * 0.05))
	p.router.use_injection = true
	p.set_profile(_profile(3))
	await step_ticks(2)
	var path := ValleyProbe.path(level, p.global_position, SQUARE, ValleyProbe.GIANT)
	assert_true(path.size() > 1, "a path from the yard's west side to the square")
	var walked := await ValleyProbe.walk(self, p, path)
	assert_eq(int(walked.reached), int(walked.total), "the giant walks out (%s)" % [walked])
	assert_true(ValleyProbe.flat(p.global_position, SQUARE) < 3.0, "and stands in the square")
