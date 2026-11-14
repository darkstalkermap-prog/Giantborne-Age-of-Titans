extends IntegrationSuite
## W23 (P39f; FOLLOWUPS "From the M8 gate review": placed fights with members inside solids). The M8 gate's
## spawn probe found members of placed fights standing in the world's solids - the woodcutters' second troll
## in the Greywood's merged solids, the war camp's fifth shield and its banner in the camp's - where
## tests/gate/test_wander_anchors.gd checks only the WanderDirector's places. This is the same probe over every
## member of every placed encounter of the real world (scenes/world/world.tscn, deterministic streaming; the
## templates are the wander test's): its body - a cylinder of its record's radius and height standing on the
## ground, or on its spawn point where that holds a post over the ground (a tower's top, a wall walk) - touches
## no static or prop geometry (world, breakables, blockers; the terrain is the ground). A siege crew stands in
## its engine's body by design (its crew slot): engines are not counted against their crews.

const SCENE := "res://scenes/world/world.tscn"
const LEVEL := "level.world"
const BODY_MASK := 1 | 16 | 32
const LIFT_M := 0.35
## A spawn point this far over the ground is a post on a structure: the body stands there.
const POST_M := 1.0

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


## The ring of chunks around `pos` loaded (the giant held there).
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


static func _in_engine(n: Node) -> bool:
	while n != null:
		if n.is_in_group(SiegeEngine.GROUP):
			return true
		n = n.get_parent()
	return false


## The bodies other than the terrain (and, for a crew, its engines) a cylinder of `radius` and `height`
## standing at `base` touches.
func _inside(base: Vector3, radius: float, height: float, crew: bool) -> PackedStringArray:
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
		if crew and _in_engine(n):
			continue
		out.append(str(n.get_parent().name) + "/" + str(n.name) if n != null and n.get_parent() != null else "?")
	return out


func test_every_placed_member_stands_clear_of_the_world() -> void:
	w = _world()
	TestSpawn.disable_all_ai(w)
	await get_tree().process_frame
	var by_chunk := {}   # chunk id -> [[encounter id, spawn, definition record, crew]]
	var encounters := 0
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.get("level", "")) != LEVEL or bool(rec.get("template", false)):
			continue
		encounters += 1
		var crews := {}
		for e: Dictionary in rec.get("engines", []):
			for c: Variant in e.get("crew", []):
				crews[str(c)] = true
		for sp: Dictionary in rec.get("spawns", []):
			var def := GameData.get_record(str(sp.get("definition", "")))
			if not str(def.get("type", "")) in ["enemy", "npc"]:
				continue
			var at := Vector3(float(sp.position_m[0]), float(sp.position_m[1]), float(sp.position_m[2]))
			var c := w.streamer.chunk_at(at)
			if not by_chunk.has(c):
				by_chunk[c] = []
			(by_chunk[c] as Array).append([str(rec.id), sp, def, crews.has(str(sp.entity_id)), at])
	assert_true(encounters >= 30, "the world's placed encounters (%d)" % encounters)
	var checked := 0
	var posts := 0
	var bad: Array = []
	var ids := by_chunk.keys()
	ids.sort()
	for c: String in ids:
		var co := ChunkData.coords_for(c)
		var origin := Vector3(-1024 + co.x * 256 + 128, 0, -1024 + co.y * 256 + 128)
		var ready: bool = await _ring(origin)
		assert_true(ready, "the ring around %s loads" % c)
		for item: Array in by_chunk[c]:
			var sp: Dictionary = item[1]
			var def: Dictionary = item[2]
			var at: Vector3 = item[4]
			var h := w.height_at(at)
			if is_nan(h):
				bad.append("%s %s: ground not loaded" % [item[0], sp.entity_id])
				continue
			var base := Vector3(at.x, h, at.z)
			if at.y > h + POST_M:
				base.y = at.y
				posts += 1
			checked += 1
			var inside := _inside(base, float(def.get("capsule_radius_m", 0.5)), float(def.get("height_m", 1.8)), bool(item[3]))
			if not inside.is_empty():
				var core := _inside(base, 0.1, float(def.get("height_m", 1.8)), bool(item[3]))
				bad.append("%s %s (%s) at (%.1f, %.1f, %.1f): inside%s %s" % [item[0], sp.entity_id, sp.definition, base.x, base.y,
					base.z, " (its core)" if not core.is_empty() else "", ", ".join(inside)])
	print("PLACED_SPAWNS checked %d members of %d encounters in %d chunks (%d on posts over the ground); %d bad" % [checked,
		encounters, ids.size(), posts, bad.size()])
	for line: String in bad:
		print("PLACED_SPAWNS bad: ", line)
	assert_true(checked > 200, "the probe checked the placed members (%d)" % checked)
	assert_eq(bad.size(), 0, "no member of a placed fight stands in the world's solids")
	w.queue_free()
	await get_tree().process_frame
