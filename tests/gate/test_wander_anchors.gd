extends IntegrationSuite
## M8 gate (F18; plan M6-M9 §2.13, §5.10): where the WanderDirector stands wanderers on the real world
## (scenes/world/world.tscn, deterministic streaming), the regressions of the M8 gate review:
##   * the review's probe: every template of every wander table of the five regions (its moving columns
##     aside) at every road node the director may anchor it on (anchor_nodes), turned along the road
##     (road_yaw); each footprint the director accepts (footprint_problem "") is checked on its own - no
##     member's body (a cylinder of its radius and height over the ground) in static or prop geometry
##     (world, breakables, blockers; the terrain is the ground), each within its radius + 3 m of its own
##     nav layer (the map's closest point, 4 m up or down), none in water deeper than 0.6 of its height
##     unless it wades on the titan layer: 0 bad points in all five regions, and every entry of every
##     table still has places to stand;
##   * find_place, the live rule (every placed fight cleared, a stage-5 giant, nothing in view), never
##     chooses the review's six bad nodes - two seals, the Needle's 5 m slot, a toppled statue, the
##     Titan's Bones' ribs, a shrine - and from the Greywood shrine never anything in the sealed Hidden
##     Grove, on its rockfall or in the Needle.

const SCENE := "res://scenes/world/world.tscn"
const LEVEL := "level.world"
const BODY_MASK := 1 | 16 | 32
const LIFT_M := 0.35
const NAV_OFF_M := 3.0
const NAV_DY_M := 4.0
const WATER_SHARE := 0.6
const TITAN_LAYER := 16
## The review's cases: [region, table entry, player xz, the node xz never to be chosen, what is there].
const CASES := [
	["region.greywood", "troll_pair", Vector2(-640, -150), Vector2(-505, -70), "the Hidden Grove's north-ridge rockfall (a seal)"],
	["region.greywood", "dire_wolf_pack", Vector2(-560, 200), Vector2(-428, 42), "the Needle's 5 m slot"],
	["region.greywood", "dire_wolf_pack", Vector2(-560, 200), Vector2(-688, 116), "the old root's fallen titan-tree (a seal)"],
	["region.crownmarch", "dire_wolf_pack", Vector2(-470, 900), Vector2(-345, 790), "the toppled Kingsgate statue (a seal)"],
	["region.drowned_steps", "ogre_pair", Vector2(100, -180), Vector2(220, -260), "inside the Titan's Bones' ribs"],
	["region.stonehold", "troll_pack", Vector2(-180, -520), Vector2(-300, -600), "the Standing Stones' shrine"],
]
const GROVE := Vector2(-480, -10)
const GROVE_ROCKFALL := Vector2(-504.7, -70.1)
const NEEDLE := Vector2(-428.4, 41.6)
const GREYWOOD_SHRINE := Vector2(-540, 104)

var w: WorldRoot = null


func after_each() -> void:
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	NavQuery.reset_budget()
	await super()


func _world() -> WorldRoot:
	var root := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(root)
	root.streamer.deterministic = true
	root.player().router.use_injection = true
	root.player().entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	return root


func _director() -> WanderDirector:
	return w.get_node_or_null("WanderDirector") as WanderDirector


## The ring of chunks around `pos` loaded (the giant held there), and its navigation synced.
func _ring(pos: Vector3) -> bool:
	var p := w.player()
	var guard := 0
	while not w.streamer.ring_ready(pos) and guard < 3000:
		var h := w.height_at(pos)
		p.global_position = Vector3(pos.x, (h if not is_nan(h) else 200.0) + 1.0, pos.z)
		p.velocity = Vector3.ZERO
		w.streamer.load_ring_slice(pos)
		await get_tree().physics_frame
		guard += 1
	for i in 3:
		await get_tree().physics_frame
	return w.streamer.ring_ready(pos)


func _go(xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _stage(stage: int) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			w.player().set_profile(rec)


## The bodies other than the terrain a cylinder of `radius` and `height` standing at `base` touches.
func _inside(base: Vector3, radius: float, height: float) -> PackedStringArray:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = maxf(0.5, height - LIFT_M)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = BODY_MASK
	q.transform = Transform3D(Basis(), base + Vector3.UP * (LIFT_M + shape.height * 0.5))
	var out := PackedStringArray()
	for hit: Dictionary in w.get_world_3d().direct_space_state.intersect_shape(q, 16):
		if PhysicsServer3D.shape_get_type(PhysicsServer3D.body_get_shape(hit.rid, int(hit.shape))) == PhysicsServer3D.SHAPE_HEIGHTMAP:
			continue
		var n := hit.collider as Node
		out.append(str(n.get_parent().name) + "/" + str(n.name) if n != null and n.get_parent() != null else "?")
	return out


## The probe's own verdict on a member of record `def_id` standing at `at` ("" = fine).
func _probe(def_id: String, at: Vector3) -> String:
	var def := GameData.get_record(def_id)
	var h := w.height_at(at)
	if is_nan(h):
		return "ground not loaded"
	var base := Vector3(at.x, h, at.z)
	var r := float(def.get("capsule_radius_m", 0.5))
	var height := float(def.get("height_m", 1.8))
	var inside := _inside(base, r, height)
	if not inside.is_empty():
		var core := _inside(base, 0.1, height)
		return "inside%s %s" % [" (its core)" if not core.is_empty() else "", ", ".join(inside)]
	var layers := int(def.get("nav_layers", 1))
	var cp := NavQuery.closest_point(w, base, layers)
	if not cp.is_finite():
		return "no navigation on layers %d" % layers
	var off := Vector2(cp.x - base.x, cp.z - base.z).length()
	if off > r + NAV_OFF_M or absf(cp.y - base.y) > NAV_DY_M:
		return "%.1f m off its nav layers %d (closest %s)" % [off, layers, cp.snappedf(0.1)]
	var water := w.water_at(base)
	if not is_nan(water) and water - h > height * WATER_SHARE and (layers & TITAN_LAYER) == 0:
		return "in water %.1f m deep" % (water - h)
	return ""


func test_every_footprint_the_director_accepts_is_clear() -> void:
	w = _world()
	TestSpawn.disable_all_ai(w)
	await get_tree().process_frame
	var wd := _director()
	assert_true(wd != null, "the WanderDirector")
	if wd == null:
		return
	var idx := WorldIndex.for_level(LEVEL)
	var nodes := idx.road_nodes()
	# [region, entry id, template, node] by the chunk of the node
	var by_chunk := {}
	var accepted := {}   # "region entry" -> places accepted
	var regions := {}
	for table: Dictionary in GameData.records_of_type("wander_table"):
		var region := str(table.region)
		regions[region] = true
		assert_false(wd.anchor_nodes(region).is_empty(), "%s has road nodes to stand on" % region)
		for e: Dictionary in table.get("entries", []):
			if e.has("route") or e.has("path"):
				continue   # a moving column stands on its route
			accepted["%s %s" % [region, e.id]] = 0
			var tpl := GameData.get_record(str(e.template))
			for i: int in wd.anchor_nodes(region):
				var c := w.streamer.chunk_at(nodes[i])
				if not by_chunk.has(c):
					by_chunk[c] = []
				(by_chunk[c] as Array).append([region, str(e.id), tpl, i])
	assert_eq(regions.size(), 5, "the five regions' tables")
	var checked := 0
	var refused := {}
	var bad: Array = []
	var ids := by_chunk.keys()
	ids.sort()
	for c: String in ids:
		var co := ChunkData.coords_for(c)
		var origin := Vector3(-1024 + co.x * 256 + 128, 0, -1024 + co.y * 256 + 128)
		var ready: bool = await _ring(origin)
		assert_true(ready, "the ring around %s loads" % c)
		for item: Array in by_chunk[c]:
			var tpl: Dictionary = item[2]
			var i: int = item[3]
			var pts := WanderDirector.footprint(tpl, nodes[i], wd.road_yaw(i))
			var loaded := true
			for q: Vector3 in pts:
				loaded = loaded and w.streamer.is_ready(w.streamer.chunk_at(q))
			if not loaded:
				refused["unloaded"] = int(refused.get("unloaded", 0)) + 1
				continue
			NavQuery.reset_budget()   # (the probe is no tick's work)
			var why := wd.footprint_problem(tpl, nodes[i], pts)
			if why != "":
				var kind := why.get_slice(":", 0)
				refused[kind] = int(refused.get(kind, 0)) + 1
				continue
			var key := "%s %s" % [item[0], item[1]]
			accepted[key] = int(accepted[key]) + 1
			var spawns: Array = tpl.get("spawns", [])
			for j in pts.size():
				var def_id := WanderDirector._member_definition(spawns[j] as Dictionary)
				var kind := str(GameData.get_record(def_id).get("type", ""))
				if kind != "enemy":
					continue
				checked += 1
				var problem := _probe(def_id, pts[j])
				if problem != "":
					bad.append("%s %s node %d (%.0f, %.0f) member %s at (%.1f, %.1f): %s" % [item[0], item[1], i, nodes[i].x,
						nodes[i].z, (spawns[j] as Dictionary).get("entity_id", ""), pts[j].x, pts[j].z, problem])
	var keys := accepted.keys()
	keys.sort()
	for key: String in keys:
		print("WANDER_ANCHORS %s: %d places accepted" % [key, accepted[key]])
		assert_true(int(accepted[key]) > 0, "%s still has places to stand" % key)
	print("WANDER_ANCHORS checked %d member points; refused footprints %s; %d bad" % [checked, refused, bad.size()])
	for line: String in bad:
		print("WANDER_ANCHORS bad: ", line)
	assert_true(checked > 0, "the probe checked points")
	assert_eq(bad.size(), 0, "no member of an accepted footprint stands in a wall, off its navmesh or in deep water")
	w.queue_free()
	await get_tree().process_frame


func test_find_place_never_chooses_the_reviews_bad_nodes() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	w = _world()
	TestSpawn.disable_all_ai(w)
	var wd := _director()
	var d := w.director()
	# the placed fights are cleared (find_place keeps ENCOUNTER_GAP_M from one that is not)
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.get("level", "")) == LEVEL and not bool(rec.get("template", false)) and not bool(rec.get("arena", false)):
			WorldState.set_flag(EncounterDirector.cleared_flag(str(rec.id)), true)
	d.reload_encounters()
	for c: Array in CASES:
		var region := str(c[0])
		var table: Dictionary = wd.tables[region]
		var entry: Dictionary = {}
		for e: Dictionary in table.entries:
			if str(e.id) == str(c[1]):
				entry = e
		var tpl := GameData.get_record(str(entry.template))
		await _go(c[2])
		_stage(5)
		var never := Vector2(c[3])
		var placed := 0
		var hits := 0
		for i in 160:
			var place := wd.find_place(table, entry, tpl, w.player().global_position)
			await step_ticks(1)
			if place.is_empty():
				continue
			placed += 1
			var a: Vector3 = place.anchor
			if Vector2(a.x, a.z).distance_to(never) < 6.0:
				hits += 1
		print("WANDER_ANCHORS %s %s from %s: %d places; %s (%s) chosen %d times" % [region, entry.id, c[2], placed, never, c[4], hits])
		assert_true(placed > 0, "%s %s finds places near %s" % [region, entry.id, c[2]])
		assert_eq(hits, 0, "%s %s never stands at %s: %s" % [region, entry.id, never, c[4]])
	w.queue_free()
	await get_tree().process_frame


static func _in_grove(a: Vector3) -> String:
	var xz := Vector2(a.x, a.z)
	if xz.distance_to(GROVE_ROCKFALL) < 6.0:
		return "on the grove's rockfall"
	if xz.distance_to(GROVE) < 48.0:
		return "in the sealed grove"
	if xz.distance_to(NEEDLE) < 40.0 and xz.distance_to(GROVE) < 82.0:
		return "in the Needle"
	return ""


func test_no_greywood_wanderer_in_the_sealed_grove() -> void:
	WanderDirector.test_active = true
	w = _world()
	await _go(GREYWOOD_SHRINE)
	_stage(5)
	w.player().camera_rig.yaw = PI   # looking south, the grove behind
	await step_ticks(30)
	var wd := _director()
	var table: Dictionary = wd.tables["region.greywood"]
	var placed := 0
	var sealed: Array = []
	for i in 120:
		for e: Dictionary in table.entries:
			if int(e.get("min_stage", 0)) > 5 or int(e.get("max_stage", 10)) < 5:
				continue
			var place := wd.find_place(table, e, GameData.get_record(str(e.template)), w.player().global_position)
			if place.is_empty():
				continue
			placed += 1
			var where := _in_grove(place.anchor)
			if where != "":
				sealed.append("%s at %s: %s" % [e.id, (place.anchor as Vector3).snappedf(0.5), where])
		await step_ticks(1)   # a fresh path-query budget
	print("WANDER_ANCHORS the Greywood from its shrine: %d places, %d in the grove %s" % [placed, sealed.size(), sealed])
	assert_true(placed > 0, "the Greywood's wanderers find places from its shrine")
	assert_eq(sealed.size(), 0, "no wanderer stands in the sealed Hidden Grove, on its rockfall or in the Needle")
	w.queue_free()
	await get_tree().process_frame
