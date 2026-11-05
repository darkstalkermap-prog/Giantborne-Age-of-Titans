extends IntegrationSuite
## The Valley of Broken Kings (P10b, plan §3.11 tests; slow, runs with --slow): the scene built by
## tools/builders/valley.gd from tools/data/valley_layout.json.
##   * It loads in under 3 s headless (node count reported) and performs no navigation bake: its
##     four regions carry the offline-baked navmeshes of assets/nav (at most 100 KB each), on nav
##     layers 1/2/4/8, at distinct heights so every layer's link connects that layer.
##   * The scene layout of plan §2.12 (Districts, Navigation, Props, Shrines, Waystones, Markers,
##     Triggers, Kingsfall/{ArenaGate,Pillars}, ...) and every layout id resolves through LevelRoot.
##   * Paths: small giant (8) from the spawn to the Grove Shrine; giant (4) from the Grove to every
##     shrine, waystone and objective marker once the barricade, practice-gate and Deadfall links
##     are open, and not past them while they are closed; each link carries each layer.
##   * The river: the human path crosses it only over the bridge, and only once the barricade's
##     link is open; a stage-3 capsule pushed east at three points of the west bank stays west of
##     x = 100.
##   * Every shrine pad, waystone and checkpoint marker has stage-3 clearance.

const MAX_LOAD_MS := 3000.0
const MAX_NAV_BYTES := 100 * 1024
const NAV_FILES := ["res://assets/nav/valley_human.res", "res://assets/nav/valley_large.res",
	"res://assets/nav/valley_giant.res", "res://assets/nav/valley_small_giant.res"]
## The stage-3 giant (data/growth/growth_03.json).
const STAGE3_RADIUS := 1.65
const STAGE3_HEIGHT := 7.92
## Objective markers that are not places to walk to (the cairn sits on its ledge: a hurl target).
const NOT_WALKABLE_MARKERS := ["valley.marker.cairn"]
## Targets behind the barricade (the bridge and everything east of the river) or the Deadfall.
const BEHIND_BARRICADE := ["valley.marker.bridge", "valley.marker.practice_gate", "valley.marker.ruins_courtyard",
	"valley.marker.causeway", "valley.marker.kingsfall_shrine", "valley.marker.arena_center",
	"valley.marker.kingsfall_oak", "valley.cp.ruins_gate", "valley.shrine.kingsfall"]
const BEHIND_DEADFALL := ["valley.marker.crown", "valley.cp.barrow_gap"]

var level: LevelRoot
var bakes := 0


func before_each() -> void:
	await super()
	bakes = 0
	level = null


func _add_valley(no_director := true) -> LevelRoot:
	level = ValleyProbe.instance(no_director)
	world.add_child(level)
	return level


func _on_bake_finished() -> void:
	bakes += 1


# --------------------------------------------------------------------------- load and structure

func test_loads_fast_with_offline_navigation() -> void:
	var t0 := Time.get_ticks_usec()
	var packed := load(ValleyProbe.VALLEY) as PackedScene
	var lv := packed.instantiate() as LevelRoot
	var regions: Array[NavigationRegion3D] = []
	for name: String in ["Human", "Large", "Giant", "SmallGiant"]:
		var r := lv.get_node_or_null("Navigation/" + name) as NavigationRegion3D
		assert_true(r != null, "Navigation/%s exists" % name)
		if r == null:
			continue
		regions.append(r)
		assert_true(r.navigation_mesh != null and r.navigation_mesh.get_polygon_count() > 0,
			"%s carries a baked navmesh before it enters the tree" % name)
		r.bake_finished.connect(_on_bake_finished)
	level = lv
	world.add_child(lv)
	await get_tree().process_frame
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var nodes := _count_nodes(lv)
	print("    valley: loaded, instanced and added in %.0f ms; %d nodes" % [ms, nodes])
	assert_true(ms < MAX_LOAD_MS, "the Valley loads in under 3 s headless (%.0f ms)" % ms)
	assert_true(nodes > 100 and nodes < 4000, "a plausible node count (%d)" % nodes)
	var synced: bool = await ValleyProbe.wait_for_navigation(self, lv)
	assert_true(synced, "the navigation map answers on every layer without a bake")
	assert_eq(bakes, 0, "no region baked at runtime")
	for r in regions:
		assert_false(r.is_baking(), "%s is not baking" % r.name)
	var expected := {"Human": [1, NAV_FILES[0]], "Large": [2, NAV_FILES[1]], "Giant": [4, NAV_FILES[2]],
		"SmallGiant": [8, NAV_FILES[3]]}
	var builder: GDScript = load(ValleyProbe.BUILDER)
	var above := {}
	for spec: Dictionary in builder.get("NAV_LAYERS"):
		above[str(spec.node)] = float(spec.above)
	var heights := {}
	for r in regions:
		var e: Array = expected[str(r.name)]
		assert_eq(r.navigation_layers, int(e[0]), "%s is on nav layer %d" % [r.name, e[0]])
		assert_eq(r.navigation_mesh.resource_path, str(e[1]), "%s uses %s" % [r.name, e[1]])
		assert_false(r.use_edge_connections, "%s makes no edge connections to the other layers" % r.name)
		assert_eq(lv.nav_region(int(e[0])), r.get_rid(), "LevelRoot.nav_region(%d) is %s" % [e[0], r.name])
		heights[str(r.name)] = r.position.y + 0.5
		assert_near(r.position.y + 0.5, float(above[str(r.name)]), 0.011,
			"%s sits %.2f m above the walking surface" % [r.name, above[str(r.name)]])
	var hs := heights.values()
	hs.sort()
	for i in hs.size() - 1:
		assert_true(float(hs[i + 1]) - float(hs[i]) >= 0.09, "the four layers sit at distinct heights (%s)" % [heights])
	for path: String in NAV_FILES:
		var f := FileAccess.open(path, FileAccess.READ)
		var size := f.get_length() if f != null else -1
		print("    %s: %d bytes" % [path.get_file(), size])
		assert_true(size > 1000 and size <= MAX_NAV_BYTES, "%s is at most 100 KB (%d bytes)" % [path.get_file(), size])


func test_scene_layout_and_lookups() -> void:
	var lv := _add_valley(false)
	await step_ticks(2)
	var layout := ValleyProbe.layout()
	for path: String in ["Environment", "Sun", "Districts", "Navigation", "Props", "Shrines", "Waystones",
			"Dummies", "Markers", "Markers/Patrol", "Triggers", "Kingsfall", "Kingsfall/ArenaGate",
			"Kingsfall/Pillars", "Signs", "Spawns/PlayerSpawn", "Spawned", "Player", "EncounterDirector",
			"DebrisPool"]:
		assert_true(lv.has_node(path), "the Valley has %s" % path)
	assert_eq(lv.level_id, "level.valley", "LevelRoot level_id")
	assert_false(lv.level_record().is_empty(), "the level record exists")
	assert_eq(str(lv.level_record().get("scene", "")), ValleyProbe.VALLEY, "and names this scene")
	assert_true(lv.director() is EncounterDirector, "LevelRoot/EncounterDirector")
	assert_true(lv.player() is GiantPlayer and lv.player() == lv.get_node("Player"), "the Player")
	var env := (lv.get_node("Environment") as WorldEnvironment).environment
	assert_true(env.fog_enabled and is_equal_approx(env.fog_depth_begin, 120.0), "depth fog from 120 m")
	for d: Dictionary in layout.districts:
		assert_true(lv.has_node("Districts/" + str(d.id)), "Districts/%s" % d.id)
	var scenery := 0
	for n in get_tree().get_nodes_in_group("valley_scenery"):
		if lv.is_ancestor_of(n):
			scenery += 1
			assert_near((n as GeometryInstance3D).visibility_range_end, 220.0, 0.01, "%s fades out at 220 m" % n.name)
	assert_true(scenery >= 3, "scenery MultiMeshes in group valley_scenery (%d)" % scenery)
	# Kingsfall: the closed-off gate (P11a drives it) and four pillars at 22 m round the arena centre.
	var gate := lv.get_node("Kingsfall/ArenaGate") as StaticBody3D
	assert_eq(gate.collision_layer, 1, "the arena gate is on WORLD")
	assert_false(gate.visible, "hidden")
	assert_true((gate.get_node("Shape") as CollisionShape3D).disabled, "with its collision off")
	var centre := Vector3(150, 0, 135)
	var pillars := lv.get_node("Kingsfall/Pillars").get_children()
	assert_eq(pillars.size(), 4, "four pillars")
	for p: Node in pillars:
		var body := p as StaticBody3D
		assert_eq(body.collision_layer, 1, "%s is on WORLD" % p.name)
		assert_near(ValleyProbe.flat(body.global_position, centre), 22.0, 0.01, "%s stands 22 m from the centre" % p.name)
		var box := (body.get_node("Shape") as CollisionShape3D).shape as BoxShape3D
		assert_eq(box.size, Vector3(3, 15, 3), "%s is 3 x 15 x 3 m" % p.name)
	assert_true(lv.area("valley.area.arena_engage") != null, "the arena_engage trigger")
	# Every id of the layout resolves through LevelRoot.
	for m: Dictionary in layout.markers:
		var node := lv.marker(str(m.id))
		assert_true(node != null, "marker %s" % m.id)
		if node != null:
			assert_true(node.global_position.distance_to(ValleyProbe.v3(m.pos)) < 0.01, "%s at its layout position" % m.id)
	for t: Dictionary in layout.triggers:
		assert_true(lv.area(str(t.id)) != null, "trigger %s" % t.id)
	for w: Dictionary in layout.waystones:
		var cp := lv.checkpoint(str(w.id))
		assert_true(cp is Waystone, "waystone %s" % w.id)
		if cp is Waystone:
			assert_eq(Array((cp as Waystone).requires_flags), Array(w.requires_flags), "%s requires %s" % [w.id, w.requires_flags])
	for s: Dictionary in layout.shrines:
		var sh := ValleyProbe.shrine(lv, str(s.world_id))
		assert_true(sh != null and sh.shrine_id == str(s.record), "shrine %s (%s)" % [s.world_id, s.record])
		assert_true(lv.checkpoint(str(s.world_id)) != null, "its spawn point is checkpoint %s" % s.world_id)
	for r: Dictionary in layout.patrols:
		var route := lv.patrol_route(str(r.id))
		assert_true(route != null and route.get_child_count() == (r.points as Array).size(),
			"patrol route %s with %d points" % [r.id, (r.points as Array).size()])
	for d: Dictionary in layout.dummies:
		var dummy := lv.get_node_or_null("Dummies/" + str(d.entity_id).validate_node_name()) as PracticeDummy
		assert_true(dummy != null and dummy.entity.entity_id == str(d.entity_id), "dummy %s" % d.entity_id)
	for p: Dictionary in layout.props:
		var node := ValleyProbe.prop(lv, str(p.world_id))
		if not ResourceLoader.exists("res://scenes/world/%s.tscn" % p.scene):
			continue   # an optional scene of a later package (the forge)
		var missing_record := false
		for rec: Variant in p.get("requires_records", []):
			missing_record = missing_record or GameData.get_record(str(rec)).is_empty()
		if missing_record:
			assert_true(node == null, "%s waits for its records" % p.world_id)
			continue
		assert_true(node != null and str(node.get("world_id")) == str(p.world_id), "prop %s" % p.world_id)
	# The district rectangles of the level record.
	for sample: Array in [["hollow", Vector3(-150, 0, 170)], ["forest", Vector3(-60, 0, -70)],
			["village", Vector3(14, 0, -26)], ["quarry", Vector3(30, 0, -155)], ["barrow", Vector3(-55, 0, -172)],
			["ruins", Vector3(158, 0, -50)], ["kingsfall", Vector3(150, 0, 55)]]:
		assert_eq(lv.district_at(sample[1]), sample[0], "%s is in district %s" % [sample[1], sample[0]])
	# The links: one per layer, at the layer's height, disabled while the prop stands.
	var builder: GDScript = load(ValleyProbe.BUILDER)
	for id: String in ValleyProbe.LINK_PROPS:
		var bp := ValleyProbe.prop(lv, id) as BreakableProp
		assert_true(bp != null, "%s is a BreakableProp" % id)
		if bp == null:
			continue
		assert_false(bp.nav_links_enabled(), "%s's links are closed while it stands" % id)
		for spec: Dictionary in builder.get("NAV_LAYERS"):
			var link := bp.get_node_or_null("NavLink" + str(spec.node)) as NavigationLink3D
			assert_true(link != null and link.navigation_layers == int(spec.layer)
				and is_equal_approx(link.start_position.y, float(spec.above)),
				"%s has NavLink%s on layer %d at %.2f m" % [id, spec.node, spec.layer, spec.above])


# --------------------------------------------------------------------------- paths

func test_paths_on_every_layer() -> void:
	var lv := _add_valley()
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var spawn := (lv.get_node("Spawns/PlayerSpawn") as Node3D).global_position
	var grove := ValleyProbe.shrine(lv, "valley.shrine.grove").growth_pad_position()
	var p8 := ValleyProbe.path(lv, spawn, grove, ValleyProbe.SMALL_GIANT)
	assert_true(ValleyProbe.reaches(lv, spawn, grove, ValleyProbe.SMALL_GIANT),
		"a small-giant path from the spawn to the Grove Shrine (ends %s)" % [p8[p8.size() - 1] if p8.size() > 0 else "nowhere"])
	var length := 0.0
	for i in p8.size() - 1:
		length += ValleyProbe.flat(p8[i], p8[i + 1])
	print("    valley: spawn -> Grove on the small-giant layer: %.0f m" % length)
	assert_true(length > ValleyProbe.flat(spawn, grove) and length < 2.0 * ValleyProbe.flat(spawn, grove),
		"along the trail and the forest road (%.0f m)" % length)
	# The giant layer from the Grove: everything before the gates, nothing behind them.
	var targets := _giant_targets(lv)
	for id: String in targets:
		var behind := BEHIND_BARRICADE.has(id) or BEHIND_DEADFALL.has(id)
		var ok := ValleyProbe.reaches(lv, grove, targets[id], ValleyProbe.GIANT)
		if behind:
			assert_false(ok, "links closed: no giant path from the Grove to %s" % id)
		else:
			assert_true(ok, "a giant path from the Grove to %s" % id)
	assert_true(await ValleyProbe.set_links(self, lv, true), "the map takes the open links")
	for id: String in targets:
		var ok: bool = await ValleyProbe.settle(self, lv, grove, targets[id], ValleyProbe.GIANT, true)
		var p := ValleyProbe.path(lv, grove, targets[id], ValleyProbe.GIANT)
		assert_true(ok, "links open: a giant path from the Grove to %s (ends %s)" % [id,
			p[p.size() - 1] if p.size() > 0 else "nowhere"])
	# Each link carries each layer: closed, no layer gets past the prop; open, every layer does.
	var crossings := {"valley.village.barricade": [Vector3(86, 0, -20), Vector3(106, 0, -20)],
		"valley.ruins.practice_gate": [Vector3(118, 0, -20), Vector3(140, 0, -20)],
		"valley.forest.deadfall": [Vector3(-50, 0, -100), Vector3(-50, 0, -126)]}
	assert_true(await ValleyProbe.set_links(self, lv, false), "the map takes the closed links")
	for id: String in crossings:
		for layer: int in ValleyProbe.ALL_LAYERS:
			var ok: bool = await ValleyProbe.settle(self, lv, crossings[id][0], crossings[id][1], layer, false)
			assert_false(ok, "%s closed: layer %d does not get past it" % [id, layer])
	for id: String in crossings:
		await ValleyProbe.set_links(self, lv, true, [id])
		for layer: int in ValleyProbe.ALL_LAYERS:
			var there: bool = await ValleyProbe.settle(self, lv, crossings[id][0], crossings[id][1], layer, true)
			assert_true(there, "%s open: layer %d crosses it on its own link" % [id, layer])
			var back: bool = await ValleyProbe.settle(self, lv, crossings[id][1], crossings[id][0], layer, true)
			assert_true(back, "%s open: layer %d crosses it back" % [id, layer])
		await ValleyProbe.set_links(self, lv, false, [id])


## Shrine pads, waystones and the objective markers a giant walks to, by id -> position.
func _giant_targets(lv: LevelRoot) -> Dictionary:
	var out := {}
	for s in get_tree().get_nodes_in_group(Shrine.GROUP):
		if lv.is_ancestor_of(s) and (s as Shrine).world_id != "valley.shrine.grove":
			out[(s as Shrine).world_id] = (s as Shrine).growth_pad_position()
	for w in get_tree().get_nodes_in_group(Waystone.GROUP):
		if lv.is_ancestor_of(w):
			out[(w as Waystone).checkpoint_id] = (w as Node3D).global_position
	for m in get_tree().get_nodes_in_group("objective_markers"):
		var lm := m as LevelMarker
		if lm != null and lv.is_ancestor_of(lm) and not NOT_WALKABLE_MARKERS.has(lm.marker_id) \
				and lm.marker_id != "valley.marker.grove_shrine":
			out[lm.marker_id] = lm.global_position
	return out


# --------------------------------------------------------------------------- the river

func test_the_river_is_crossed_only_on_the_bridge() -> void:
	var lv := _add_valley()
	assert_true(await ValleyProbe.wait_for_navigation(self, lv), "navigation ready")
	var village := Vector3(80, 0, -20)
	var court := Vector3(118, 0, -20)
	var plaza := Vector3(130, 0, 40)
	var fields := Vector3(95, 0, 50)
	assert_false(ValleyProbe.reaches(lv, village, court, ValleyProbe.HUMAN), "no human path across before the barricade opens")
	assert_false(ValleyProbe.reaches(lv, fields, court, ValleyProbe.HUMAN), "not from the fields either")
	assert_false(ValleyProbe.reaches(lv, Vector3(95, 0, -70), court, ValleyProbe.HUMAN), "nor from north of the road")
	await ValleyProbe.set_links(self, lv, true, ["valley.village.barricade"])
	var crossed: bool = await ValleyProbe.settle(self, lv, village, court, ValleyProbe.HUMAN, true)
	assert_true(crossed, "with the barricade's link open the human path crosses")
	_assert_crosses_on_the_bridge(ValleyProbe.path(lv, village, court, ValleyProbe.HUMAN), "village -> bridgehead")
	assert_false(ValleyProbe.reaches(lv, village, plaza, ValleyProbe.HUMAN), "Kingsfall stays behind the practice gate")
	await ValleyProbe.set_links(self, lv, true)
	for from: Vector3 in [fields, Vector3(95, 0, -70), Vector3(40, 0, 90)]:
		var ok: bool = await ValleyProbe.settle(self, lv, from, plaza, ValleyProbe.HUMAN, true)
		assert_true(ok, "every link open: %s -> Kingsfall" % from)
		_assert_crosses_on_the_bridge(ValleyProbe.path(lv, from, plaza, ValleyProbe.HUMAN), "%s -> Kingsfall" % from)
	# A stage-3 body pushed east against the west bank never reaches the river.
	for z: float in [45.0, -60.0, -80.0]:
		var body := CharacterBody3D.new()
		body.collision_layer = 0
		body.collision_mask = SceneKit.ACTOR_MASK
		var cs := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = STAGE3_RADIUS
		cap.height = STAGE3_HEIGHT
		cs.shape = cap
		cs.position = Vector3(0, STAGE3_HEIGHT * 0.5, 0)
		body.add_child(cs)
		body.position = Vector3(94, 0.1, z)
		world.add_child(body)
		var max_x := body.global_position.x
		for i in 150:
			await step_ticks(1)
			body.velocity = Vector3(9.0, body.velocity.y - 9.8 / 60.0, 0)
			body.move_and_slide()
			max_x = maxf(max_x, body.global_position.x + STAGE3_RADIUS)
		assert_true(max_x < 100.0, "a stage-3 capsule pushed east at z %.0f stays west of x = 100 (reached %.2f)" % [z, max_x])
		assert_true(body.global_position.x > 96.0, "after walking up to the bank (x %.2f)" % body.global_position.x)
		body.queue_free()


## Every segment of `p` that spans the river (x 100..112) runs over the bridge (z -26..-14).
func _assert_crosses_on_the_bridge(p: PackedVector3Array, what: String) -> void:
	var crossed := false
	var off := 0
	for i in p.size() - 1:
		var a := p[i]
		var b := p[i + 1]
		if maxf(a.x, b.x) <= 100.0 or minf(a.x, b.x) >= 112.0:
			continue
		crossed = true
		for x: float in [maxf(minf(a.x, b.x), 100.0), minf(maxf(a.x, b.x), 112.0)]:
			var f := 0.0 if is_equal_approx(a.x, b.x) else (x - a.x) / (b.x - a.x)
			var z := lerpf(a.z, b.z, clampf(f, 0.0, 1.0))
			if z < -26.0 or z > -14.0:
				off += 1
	assert_true(crossed, "%s crosses the river" % what)
	assert_eq(off, 0, "%s crosses it on the bridge only" % what)


# --------------------------------------------------------------------------- clearance

func test_checkpoints_have_stage_3_clearance() -> void:
	var lv := _add_valley()
	await step_ticks(3)
	var space := lv.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = STAGE3_RADIUS
	cap.height = STAGE3_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.collision_mask = PlayerGrowth.CLEARANCE_MASK
	q.collide_with_areas = false
	var points := {}
	for s in get_tree().get_nodes_in_group(Shrine.GROUP):
		if lv.is_ancestor_of(s):
			points["%s pad" % (s as Shrine).world_id] = (s as Shrine).growth_pad_position()
	for c in get_tree().get_nodes_in_group("checkpoints"):
		if lv.is_ancestor_of(c):
			points["checkpoint %s" % (c as CheckpointMarker).checkpoint_id] = (c as Node3D).global_position
	var waystones := 0
	for w in get_tree().get_nodes_in_group(Waystone.GROUP):
		if lv.is_ancestor_of(w):
			waystones += 1
	assert_eq(waystones, 3, "three waystones")
	assert_true(points.size() >= 11, "four pads, four shrine spawn points and three waystones (%d)" % points.size())
	for what: String in points:
		var at: Vector3 = points[what]
		q.transform = Transform3D(Basis(), Vector3(at.x, 0.0, at.z) + Vector3.UP * (STAGE3_HEIGHT * 0.5 + PlayerGrowth.CLEARANCE_LIFT_M))
		var hits := space.intersect_shape(q, 4)
		var names := PackedStringArray()
		for h: Dictionary in hits:
			names.append(str((h.collider as Node).name) if h.collider is Node else "?")
		assert_true(hits.is_empty(), "%s has stage-3 clearance (blocked by %s)" % [what, ", ".join(names)])


static func _count_nodes(n: Node) -> int:
	var c := 1
	for child in n.get_children():
		c += _count_nodes(child)
	return c
