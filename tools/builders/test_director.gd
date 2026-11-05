extends RefCounted
## Builder: the EncounterDirector test level (scenes/test/director_test.tscn; plan §3.10). A
## 120 x 120 m floor inside low walls, two pillars, and:
##   * a LevelRoot root (level_id level.director_test; its record and the three encounters are
##     in data/world/): the wolves (encounter.director_test_wolves, north-west), the soldiers
##     with a commander and a patrol (encounter.director_test_soldiers, north-east) and a
##     14-member budget test (encounter.director_test_budget, in the middle);
##   * Navigation/Human: a NavigationRegion3D on nav layer 1 (human: agent radius 0.6 m, height
##     2 m, cell 0.3 m) baked here, offline, from the same boxes as the collision (floor, walls,
##     pillars) - nothing bakes at runtime;
##   * Markers/<Kind>/<marker> (LevelMarker): an objective marker, three formation posts in
##     front of the soldiers, a cover point, a safe point and a bot route point;
##     Markers/Patrol/test_patrol_soldiers/1..3 (the route test.patrol.soldiers);
##   * Triggers: test.area.wolf_den (a box around the wolves) and test.area.camp (a cylinder
##     around the soldiers, `once`);
##   * the checkpoint test.director.cp_start, Spawns/PlayerSpawn, Spawned, the Player and the
##     EncounterDirector.
## Runs after the player, soldier and wolf builders (tools/build_scenes.gd BUILDERS order).

const PATH := "res://scenes/test/director_test.tscn"
const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const GIANT := "res://scenes/player/giant.tscn"

const LEVEL_ID := "level.director_test"
const FLOOR_SIZE := 120.0
const START := Vector3(0, 0.05, 50)
const WOLVES_CENTER := Vector3(-35, 0, -30)
const SOLDIERS_CENTER := Vector3(35, 0, -30)
const BUDGET_CENTER := Vector3(0, 0, 15)

## The human navigation layer (plan §2.2).
const NAV_HUMAN := {"layers": 1, "radius": 0.6, "height": 2.0, "cell": 0.3, "cell_height": 0.25,
	"climb": 0.25, "slope": 35.0}

## [node name, size, centre, walkable top]: every solid box of the level; collision and
## navigation both come from this one list. Walls and pillars are obstacles: no top face and a
## projected obstruction over their footprint, so the navmesh has no unreachable islands on or
## inside them (Recast rasterises surfaces: a closed box's inside would stay walkable).
const BOXES := [
	["Floor", Vector3(FLOOR_SIZE, 1, FLOOR_SIZE), Vector3(0, -0.5, 0), true],
	["WallNorth", Vector3(124, 4, 2), Vector3(0, 2, -61), false],
	["WallSouth", Vector3(124, 4, 2), Vector3(0, 2, 61), false],
	["WallEast", Vector3(2, 4, 124), Vector3(61, 2, 0), false],
	["WallWest", Vector3(2, 4, 124), Vector3(-61, 2, 0), false],
	["PillarEast", Vector3(3, 6, 3), Vector3(20, 3, 0), false],
	["PillarWest", Vector3(3, 6, 3), Vector3(-20, 3, 0), false],
]

## [kind folder, LevelMarker.Kind, marker_id, position, faction]
const MARKERS := [
	["Objective", 0, "test.marker.wolves", WOLVES_CENTER, ""],
	["Cover", 1, "test.marker.cover_1", Vector3(22.5, 0, 3.5), ""],
	["Formation", 3, "test.marker.formation_1", Vector3(30, 0, -20), ""],
	["Formation", 3, "test.marker.formation_2", Vector3(35, 0, -20), ""],
	["Formation", 3, "test.marker.formation_3", Vector3(40, 0, -20), ""],
	["Safe", 4, "test.marker.safe_1", Vector3(-50, 0, 50), ""],
	["BotRoute", 6, "test.marker.bot_1", Vector3(0, 0, 30), ""],
]

const PATROL_ID := "test.patrol.soldiers"
const PATROL_POINTS := [Vector3(30, 0, -38), Vector3(40, 0, -38), Vector3(35, 0, -24)]


static func build_all(kit: SceneKit) -> void:
	var root := build_level(kit)
	if root != null:
		kit.save(root, PATH)


static func build_level(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("test_director: build the player scene first")
		return null
	var root := Node3D.new()
	root.name = "DirectorTestLevel"
	kit.scripted(root, S_LEVEL, {"level_id": LEVEL_ID})
	_add_environment(root)

	var world := kit.n3("World")
	for spec: Array in BOXES:
		var body := kit.static_box(spec[0], spec[1], spec[2], "stone_dark" if spec[0].begins_with("Pillar") else "stone")
		if spec[0] == "Floor":
			body.get_node("Mesh").free()
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var plane := PlaneMesh.new()
			plane.size = Vector2(FLOOR_SIZE, FLOOR_SIZE)
			mesh.mesh = plane
			mesh.material_override = kit.mats["ground"]
			mesh.position = Vector3(0, 0.5, 0)
			body.add_child(mesh)
		world.add_child(body)
	root.add_child(world)

	var nav := kit.n3("Navigation")
	var human := NavigationRegion3D.new()
	human.name = "Human"
	human.navigation_layers = int(NAV_HUMAN.layers)
	human.navigation_mesh = bake_navmesh(NAV_HUMAN, BOXES)
	nav.add_child(human)
	root.add_child(nav)

	var markers := kit.n3("Markers")
	for spec: Array in MARKERS:
		var folder := markers.get_node_or_null(NodePath(spec[0])) as Node3D
		if folder == null:
			folder = kit.n3(spec[0])
			markers.add_child(folder)
		var m := kit.scripted(kit.marker(str(spec[2]).validate_node_name(), spec[3]), S_MARKER,
			{"marker_id": spec[2], "kind": spec[1], "faction": spec[4]})
		folder.add_child(m)
	var patrols := kit.n3("Patrol")
	var route := kit.n3(PATROL_ID.validate_node_name())
	route.set_meta("route_id", PATROL_ID)
	for i in PATROL_POINTS.size():
		route.add_child(kit.marker(str(i + 1), PATROL_POINTS[i]))
	patrols.add_child(route)
	markers.add_child(patrols)
	root.add_child(markers)

	var triggers := kit.n3("Triggers")
	var den := _trigger(kit, "test.area.wolf_den", false, WOLVES_CENTER + Vector3(0, 4, 0))
	var box := BoxShape3D.new()
	box.size = Vector3(30, 8, 30)
	(den.get_node("Shape") as CollisionShape3D).shape = box
	triggers.add_child(den)
	var camp := _trigger(kit, "test.area.camp", true, SOLDIERS_CENTER + Vector3(0, 4, 0))
	var cyl := CylinderShape3D.new()
	cyl.radius = 12.0
	cyl.height = 8.0
	(camp.get_node("Shape") as CollisionShape3D).shape = cyl
	triggers.add_child(camp)
	root.add_child(triggers)

	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", START), S_CHECKPOINT,
		{"checkpoint_id": "test.director.cp_start"}))
	root.add_child(checkpoints)
	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", START))
	root.add_child(spawns)
	root.add_child(kit.n3("Spawned"))

	player.name = "Player"
	player.position = START
	root.add_child(player)

	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignWolves", "WOLVES: activate 25 m, leash 30 m", WOLVES_CENTER + Vector3(0, 4, 8)],
			["SignSoldiers", "SOLDIERS: commander, patrol, leash 40 m", SOLDIERS_CENTER + Vector3(0, 4, 8)],
			["SignBudget", "BUDGET: 14 members, at most 12 alive", BUDGET_CENTER + Vector3(0, 4, 4)],
			["SignStart", "DIRECTOR TEST LEVEL (F3: director state)", START + Vector3(0, 4.5, -4)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


## Bakes a navigation mesh offline (no runtime bake) from `boxes` ([name, size, centre,
## walkable top]) with the agent of `agent` (layers, radius, height, cell, cell_height, climb,
## slope).
static func bake_navmesh(agent: Dictionary, boxes: Array) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = float(agent.radius)
	nm.agent_height = float(agent.height)
	nm.agent_max_climb = float(agent.climb)
	nm.agent_max_slope = float(agent.slope)
	nm.cell_size = float(agent.cell)
	nm.cell_height = float(agent.cell_height)
	var src := NavigationMeshSourceGeometryData3D.new()
	for spec: Array in boxes:
		var size: Vector3 = spec[1]
		var centre: Vector3 = spec[2]
		var walkable_top := spec.size() < 4 or bool(spec[3])
		src.add_faces(box_faces(size, centre, walkable_top), Transform3D.IDENTITY)
		if not walkable_top:
			var h := size * 0.5
			src.add_projected_obstruction(PackedVector3Array([centre + Vector3(-h.x, 0, -h.z),
				centre + Vector3(h.x, 0, -h.z), centre + Vector3(h.x, 0, h.z), centre + Vector3(-h.x, 0, h.z)]),
				centre.y - h.y, size.y, false)
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


## The triangles of an axis-aligned box, wound clockwise seen from outside (Godot's front faces,
## as NavigationMeshSourceGeometryData3D.add_faces expects); without the top face when `top` is
## false (an obstacle nothing should stand on).
static func box_faces(size: Vector3, centre: Vector3, top := true) -> PackedVector3Array:
	var h := size * 0.5
	var c := [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z),
		Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)]
	var quads := [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	var out := PackedVector3Array()
	for i in quads.size():
		if i == 0 and not top:
			continue
		var q: Array = quads[i]
		out.append_array([centre + c[q[0]], centre + c[q[1]], centre + c[q[2]],
			centre + c[q[0]], centre + c[q[2]], centre + c[q[3]]])
	return out


static func _trigger(kit: SceneKit, area_id: String, once: bool, pos: Vector3) -> Area3D:
	var a := Area3D.new()
	a.name = area_id.validate_node_name()
	a.position = pos
	kit.scripted(a, S_TRIGGER, {"area_id": area_id, "once": once})
	a.collision_layer = 0
	a.collision_mask = SceneKit.L_ACTORS
	a.monitoring = true
	a.monitorable = false
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	a.add_child(cs)
	return a


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.55, 0.68)
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
	sun.directional_shadow_max_distance = 90.0
	root.add_child(sun)
