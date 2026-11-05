extends RefCounted
## Builder (P14): the stress arena, scenes/test/stress_arena.tscn (plan §3.16 item 1, §5.3; spec §16:
## "12 combatants, 20 breakables, 40 debris"). A walled 160 x 160 m floor with:
##   * a LevelRoot root (level_id level.stress_arena: data/world/level_stress_arena.json carries the
##     render presets, so --graphics=low applies here as in the Valley);
##   * Route/1..8: the eight stops of a rectangular route (corners and edge midpoints, 40 x 28 m round
##     the centre), in route order;
##   * Breakables/<world id>: 20 breakables in clusters at six of the stops (8 fences, 6 pines, 4
##     crates, 2 practice gates; see the *_SET tables), every one within 3.3 m of its stop (one
##     stage-2 Footfall, 4 m, reaches the whole cluster), outside the route except the fence across
##     from each gate; meta "stop" (the stop index) and "order" (the lap order);
##   * Spawns/Combatants/<slot>: the 12 combatant spawn points round the route (4 soldiers, 3 wolves,
##     2 archers, 1 mage, 2 ogres; meta "scene" and "definition"). StressScenario spawns them at load
##     and respawns each 5 s after it dies or routs, so 12 stay active;
##   * Navigation/Human (layer 1) and Navigation/Large (layer 2, the ogres), baked here, offline, from
##     the floor, the walls and the breakables' footprints (obstacles: the debris-free outline the
##     enemies path round);
##   * Scenery: two MultiMeshes of trees along the walls (group "scenery": the preset's visibility
##     range), Spawns/PlayerSpawn, Checkpoints/CpStart, Spawned, the Player, DebrisPool, Signs and the
##     StressScenario node (the respawns, and the bot that --scenario=stress starts).
## Runs after the player, enemy and prop builders (tools/build_scenes.gd BUILDERS order).

const PATH := "res://scenes/test/stress_arena.tscn"
const LEVEL_ID := "level.stress_arena"
const S_LEVEL := "res://scripts/world/level_root.gd"
const S_SCENARIO := "res://scripts/debug/stress_scenario.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const GIANT := "res://scenes/player/giant.tscn"
const VALLEY_BUILDER := "res://tools/builders/valley.gd"

const ARENA_SIZE := 160.0
const WALL_H := 4.0
const WALL_T := 2.0
## Half extents (x, z) of the route rectangle round the centre.
const ROUTE_HALF := Vector2(20.0, 14.0)
## Where the giant starts: on the west edge, facing south toward the first stop.
const START := Vector3(-20.0, 0.05, 7.0)
const START_YAW_DEG := 180.0
const CHECKPOINT_ID := "test.stress.cp_start"

## The prop kinds: scene, the collision solid the nav bake treats as an obstacle (box size or
## cylinder diameter x height) and its centre height.
const PROPS := {
	"fence": {"scene": "res://scenes/world/fence_wood.tscn", "shape": "box", "size": Vector3(8.0, 1.6, 0.3), "y": 0.8},
	"tree": {"scene": "res://scenes/world/tree_small.tscn", "shape": "cyl", "size": Vector3(0.8, 7.0, 0.8), "y": 3.5},
	"crate": {"scene": "res://scenes/world/crate.tscn", "shape": "box", "size": Vector3(1.4, 1.2, 1.0), "y": 0.6},
	"gate": {"scene": "res://scenes/world/gate_practice.tscn", "shape": "box", "size": Vector3(11.8, 6.8, 0.9), "y": 3.4},
}

## The breakables of a stop: [kind, bearing (degrees from the stop's outward direction, the one
## pointing away from the route's centre, turning toward its tangent), distance (m), orientation:
## "tangent" lays a fence's or gate's length across the bearing, "radial" along it]. Every item
## comes within 3.3 m of its stop (one stage-2 Footfall, 4 m, reaches the whole cluster) and stays
## clear of the giant's walking lines along the route.
## Dense corners: two crates, two pines and two radial fences in a fan facing out of the corner;
## broken together they fill the debris pool (6 + 6 + 6 + 6 + 8 + 8 = 40 pieces).
const DENSE_SET := [["crate", -16.0, 2.9, "tangent"], ["crate", 16.0, 2.9, "tangent"],
	["tree", -40.0, 3.0, "tangent"], ["tree", 40.0, 3.0, "tangent"],
	["fence", -62.0, 7.0, "radial"], ["fence", 62.0, 7.0, "radial"]]
## Plain corners: a fence across the corner and a pine.
const CORNER_SET := [["fence", 0.0, 3.3, "tangent"], ["tree", 45.0, 3.25, "tangent"]]
## Gate stops: a practice gate beside the route and a fence across it (inside the route).
const GATE_SET := [["gate", 0.0, 3.0, "tangent"], ["fence", 180.0, 3.3, "tangent"]]

## The enemies: kind -> [scene, enemy record].
const ENEMIES := {
	"soldier": ["res://scenes/enemies/soldier.tscn", "enemy.soldier"],
	"wolf": ["res://scenes/enemies/wolf.tscn", "enemy.wolf"],
	"archer": ["res://scenes/enemies/archer.tscn", "enemy.archer"],
	"mage": ["res://scenes/enemies/mage.tscn", "enemy.mage"],
	"ogre": ["res://scenes/enemies/ogre.tscn", "enemy.ogre"],
}
## [slot, kind, spawn position]: 10-16 m outside the route, every side covered. They face the centre.
const COMBATANTS := [
	["soldier_1", "soldier", Vector3(-8, 0, 28)],
	["soldier_2", "soldier", Vector3(8, 0, 28)],
	["soldier_3", "soldier", Vector3(8, 0, -28)],
	["soldier_4", "soldier", Vector3(-8, 0, -28)],
	["wolf_1", "wolf", Vector3(-34, 0, 8)],
	["wolf_2", "wolf", Vector3(34, 0, -8)],
	["wolf_3", "wolf", Vector3(-34, 0, -8)],
	["archer_1", "archer", Vector3(36, 0, 26)],
	["archer_2", "archer", Vector3(-36, 0, -26)],
	["mage_1", "mage", Vector3(36, 0, -26)],
	["ogre_1", "ogre", Vector3(34, 0, 10)],
	["ogre_2", "ogre", Vector3(-36, 0, 26)],
]

## Navigation layers (plan §2.2): humans, wolves, archers and the mage on 1; ogres on 2.
const NAV := [
	{"layer": 1, "node": "Human", "radius": 0.6, "height": 2.0, "climb": 0.25, "cell": 0.3},
	{"layer": 2, "node": "Large", "radius": 1.5, "height": 4.0, "climb": 0.5, "cell": 0.5},
]
## Decorative trees (no collision) along the walls.
const SCENERY_RING_M := 68.0
const SCENERY_TREES := 48


static func build_all(kit: SceneKit) -> void:
	kit.add_material("stress_route", Color(0.62, 0.55, 0.40), 0.95)
	kit.add_material("stress_leaves", Color(0.20, 0.38, 0.20), 0.9)
	kit.add_material("stress_trunk", Color(0.33, 0.24, 0.16), 0.9)
	var root := build_arena(kit)
	if root != null:
		kit.save(root, PATH)


## The route's eight stops, in route order: the south-west corner, then east along the south edge,
## north along the east edge, west along the north edge and south along the west edge (+Z is south).
static func stops() -> Array[Vector3]:
	var hx := ROUTE_HALF.x
	var hz := ROUTE_HALF.y
	return [Vector3(-hx, 0, hz), Vector3(0, 0, hz), Vector3(hx, 0, hz), Vector3(hx, 0, 0),
		Vector3(hx, 0, -hz), Vector3(0, 0, -hz), Vector3(-hx, 0, -hz), Vector3(-hx, 0, 0)]


## The breakable set of each stop: the south-west and north-east corners dense (6 each), the
## other two corners plain (2 each), a gate and a fence at the south and north midpoints, nothing
## at the east and west midpoints (waypoints of the rectangle): 8 fences, 6 pines, 4 crates and 2
## gates in all.
static func stop_sets() -> Array:
	return [DENSE_SET, GATE_SET, CORNER_SET, [], DENSE_SET, GATE_SET, CORNER_SET, []]


## Every breakable: {"kind", "world_id", "stop", "order", "xform"} in lap order. World ids count per
## kind: stress.fence_01..08, stress.tree_01..06, stress.crate_01..04, stress.gate_01..02.
static func breakables() -> Array:
	var out: Array = []
	var counts := {}
	var all_stops := stops()
	var sets := stop_sets()
	for i in all_stops.size():
		var stop: Vector3 = all_stops[i]
		var outward := Vector3(stop.x, 0, stop.z).normalized()
		var tangent := Vector3(-outward.z, 0, outward.x)
		for item: Array in sets[i]:
			var kind := str(item[0])
			counts[kind] = int(counts.get(kind, 0)) + 1
			var b := deg_to_rad(float(item[1]))
			var dir := outward * cos(b) + tangent * sin(b)
			var pos := stop + dir * float(item[2])
			# Local X (a fence's or gate's length) across the bearing, or along it.
			var length_axis := dir if str(item[3]) == "radial" else Vector3(-dir.z, 0, dir.x)
			var yaw := atan2(-length_axis.z, length_axis.x)
			out.append({"kind": kind, "world_id": "stress.%s_%02d" % [kind, counts[kind]], "stop": i,
				"order": out.size(), "xform": Transform3D(Basis(Vector3.UP, yaw), pos)})
	return out


static func build_arena(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("stress: build the player scene first")
		return null
	var root := Node3D.new()
	root.name = "StressArena"
	kit.scripted(root, S_LEVEL, {"level_id": LEVEL_ID})
	_add_environment(root)

	var solids := arena_solids()
	var geometry := kit.n3("Geometry")
	for sd: Dictionary in solids:
		if str(sd.nav) == "prop":
			continue   # the breakables carry their own collision
		var body := StaticBody3D.new()
		body.name = str(sd.name)
		body.transform = sd.xform
		body.collision_layer = SceneKit.L_WORLD
		body.collision_mask = 0
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = kit.box_shape(sd.size)
		body.add_child(cs)
		if sd.name == "Floor":
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var plane := PlaneMesh.new()
			plane.size = Vector2(ARENA_SIZE, ARENA_SIZE)
			mesh.mesh = plane
			mesh.position = Vector3(0, 0.5, 0)
			mesh.material_override = kit.mats["ground"]
			body.add_child(mesh)
		else:
			body.add_child(kit.box("Mesh", sd.size, Vector3.ZERO, "stone"))
		geometry.add_child(body)
	root.add_child(geometry)
	root.add_child(_route_visuals(kit))
	root.add_child(_scenery(kit))

	var nav := kit.n3("Navigation")
	var vb: GDScript = load(VALLEY_BUILDER)
	for spec: Dictionary in NAV:
		var region := NavigationRegion3D.new()
		region.name = str(spec.node)
		region.navigation_layers = int(spec.layer)
		region.use_edge_connections = false
		region.navigation_mesh = bake_layer(vb, spec, solids)
		nav.add_child(region)
	root.add_child(nav)

	var route := kit.n3("Route")
	var all_stops := stops()
	for i in all_stops.size():
		var m := kit.marker(str(i + 1), all_stops[i])
		m.set_meta("stop", i)
		route.add_child(m)
	root.add_child(route)

	var props := kit.n3("Breakables")
	for b: Dictionary in breakables():
		var prop: Node3D = kit.instance(str(PROPS[b.kind].scene))
		if prop == null:
			push_error("stress: the %s scene is missing (build world_props / props first)" % b.kind)
			continue
		prop.name = str(b.world_id).validate_node_name()
		prop.set("world_id", b.world_id)
		prop.transform = b.xform
		prop.set_meta("stop", b.stop)
		prop.set_meta("order", b.order)
		props.add_child(prop)
	root.add_child(props)

	var spawns := kit.n3("Spawns")
	var ps := kit.marker("PlayerSpawn", START)
	ps.rotation_degrees.y = START_YAW_DEG
	spawns.add_child(ps)
	var slots := kit.n3("Combatants")
	for c: Array in COMBATANTS:
		var pos: Vector3 = c[2]
		var m := kit.marker(str(c[0]), pos)
		m.rotation.y = TargetingRules.yaw_of(-Vector3(pos.x, 0, pos.z))
		m.set_meta("scene", str(ENEMIES[c[1]][0]))
		m.set_meta("definition", str(ENEMIES[c[1]][1]))
		slots.add_child(m)
	spawns.add_child(slots)
	root.add_child(spawns)

	var checkpoints := kit.n3("Checkpoints")
	var cp := kit.scripted(kit.marker("CpStart", START), S_CHECKPOINT, {"checkpoint_id": CHECKPOINT_ID}) as Node3D
	cp.rotation_degrees.y = START_YAW_DEG
	checkpoints.add_child(cp)
	root.add_child(checkpoints)
	root.add_child(kit.n3("Spawned"))

	player.name = "Player"
	player.position = START
	player.rotation_degrees.y = START_YAW_DEG
	root.add_child(player)

	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)

	var scenario := Node.new()
	scenario.name = "StressScenario"
	kit.scripted(scenario, S_SCENARIO)
	root.add_child(scenario)

	var signs := kit.n3("Signs")
	for i in all_stops.size():
		var stop: Vector3 = all_stops[i]
		var inward := -Vector3(stop.x, 0, stop.z).normalized()
		var s := kit.sign("STOP %d" % (i + 1), stop + inward * 2.5 + Vector3.UP * 3.0)
		s.name = "SignStop%d" % (i + 1)
		s.visibility_range_end = 60.0
		signs.add_child(s)
	var title := kit.sign("STRESS ARENA: 12 combatants, 20 breakables (--scenario=stress)", START + Vector3(4, 5, 0))
	title.name = "SignTitle"
	title.visibility_range_end = 80.0
	signs.add_child(title)
	root.add_child(signs)
	return root


## Every solid of the arena: {"name", "shape", "xform", "size", "nav"}: the floor ("ground"), the four
## walls ("obstacle") and the breakables' collision ("prop": obstacles in the bake only).
static func arena_solids() -> Array:
	var out: Array = []
	var half := ARENA_SIZE * 0.5
	out.append({"name": "Floor", "shape": "box", "xform": Transform3D(Basis(), Vector3(0, -0.5, 0)),
		"size": Vector3(ARENA_SIZE, 1, ARENA_SIZE), "nav": "ground"})
	var span := ARENA_SIZE + WALL_T * 2.0
	for w: Array in [["WallNorth", Vector3(0, WALL_H * 0.5, -half - WALL_T * 0.5), Vector3(span, WALL_H, WALL_T)],
			["WallSouth", Vector3(0, WALL_H * 0.5, half + WALL_T * 0.5), Vector3(span, WALL_H, WALL_T)],
			["WallEast", Vector3(half + WALL_T * 0.5, WALL_H * 0.5, 0), Vector3(WALL_T, WALL_H, span)],
			["WallWest", Vector3(-half - WALL_T * 0.5, WALL_H * 0.5, 0), Vector3(WALL_T, WALL_H, span)]]:
		out.append({"name": w[0], "shape": "box", "xform": Transform3D(Basis(), w[1]), "size": w[2], "nav": "obstacle"})
	for b: Dictionary in breakables():
		var spec: Dictionary = PROPS[b.kind]
		var xf: Transform3D = b.xform
		out.append({"name": b.world_id, "shape": spec.shape, "size": spec.size, "nav": "prop",
			"xform": Transform3D(xf.basis, xf.origin + Vector3.UP * float(spec.y))})
	return out


## One navigation layer baked offline: the floor walkable; walls and breakables obstacles (side
## faces plus a projected obstruction over the footprint, so no island forms on or in them).
static func bake_layer(vb: GDScript, spec: Dictionary, solids: Array) -> NavigationMesh:
	var src := NavigationMeshSourceGeometryData3D.new()
	for sd: Dictionary in solids:
		if str(sd.nav) == "ground":
			src.add_faces(vb.solid_faces(sd, true), Transform3D.IDENTITY)
			continue
		src.add_faces(vb.solid_faces(sd, false), Transform3D.IDENTITY)
		var xf: Transform3D = sd.xform
		var size: Vector3 = sd.size
		src.add_projected_obstruction(vb.footprint(sd), xf.origin.y - size.y * 0.5 - 0.25, size.y + 0.25, false)
	var nm := NavigationMesh.new()
	nm.agent_radius = float(spec.radius)
	nm.agent_height = float(spec.height)
	nm.agent_max_climb = float(spec.climb)
	nm.agent_max_slope = 35.0
	nm.cell_size = float(spec.cell)
	nm.cell_height = 0.25
	nm.region_min_size = 8.0
	nm.edge_max_error = 2.0
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


## The route drawn on the floor: a 3 m strip along each edge of the rectangle.
static func _route_visuals(kit: SceneKit) -> Node3D:
	var n := kit.n3("RouteStrip")
	var all_stops := stops()
	for i in all_stops.size():
		var a: Vector3 = all_stops[i]
		var b: Vector3 = all_stops[(i + 1) % all_stops.size()]
		var mid := (a + b) * 0.5
		var length := a.distance_to(b) + 3.0
		var along_x := absf(b.x - a.x) > absf(b.z - a.z)
		var size := Vector3(length, 0.04, 3.0) if along_x else Vector3(3.0, 0.04, length)
		n.add_child(kit.box("Strip%d" % (i + 1), size, mid + Vector3.UP * 0.02, "stress_route"))
	return n


## Decorative trees (trunk and crown MultiMeshes, no collision) on a ring along the walls; group
## "scenery", so the graphics preset's scenery range applies.
static func _scenery(kit: SceneKit) -> Node3D:
	var vb: GDScript = load(VALLEY_BUILDER)
	var n := kit.n3("Scenery")
	var trunks: Array = []
	var crowns: Array = []
	for i in SCENERY_TREES:
		var a := TAU * float(i) / float(SCENERY_TREES)
		var r := SCENERY_RING_M + 4.0 * sin(float(i) * 2.3)
		var p := Vector3(cos(a) * r, 0, sin(a) * r)
		var s := 0.85 + 0.3 * (0.5 + 0.5 * sin(float(i) * 1.7))
		trunks.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3.UP * 2.0 * s))
		crowns.append(Transform3D(Basis().scaled(Vector3(s, s, s)), p + Vector3.UP * 6.0 * s))
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.3
	trunk_mesh.bottom_radius = 0.4
	trunk_mesh.height = 4.0
	trunk_mesh.radial_segments = 6
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.05
	crown_mesh.bottom_radius = 2.4
	crown_mesh.height = 6.0
	crown_mesh.radial_segments = 7
	for spec: Array in [["Trunks", trunk_mesh, trunks, "stress_trunk"], ["Crowns", crown_mesh, crowns, "stress_leaves"]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = spec[1]
		mm.instance_count = (spec[2] as Array).size()
		mm.buffer = vb.multimesh_buffer(spec[2])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = spec[0]
		mmi.multimesh = mm
		mmi.material_override = kit.mats[spec[3]]
		mmi.visibility_range_end = 220.0
		mmi.add_to_group("scenery", true)
		n.add_child(mmi)
	return n


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.58, 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.68)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	root.add_child(sun)
