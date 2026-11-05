extends RefCounted
## Builder: the 120 x 120 m combat sandbox (scenes/world/sandbox_arena.tscn). Instances the
## giant, soldier, wolf, fence and dummy scenes saved earlier in the run, so it runs after
## their builders (tools/build_scenes.gd BUILDERS order).

const S_ARENA := "res://scripts/world/sandbox_arena.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const PATH := "res://scenes/world/sandbox_arena.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const SOLDIER := "res://scenes/enemies/soldier.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"
const FENCE := "res://scenes/world/fence_wood.tscn"
const DUMMY := "res://scenes/world/practice_dummy.tscn"
const SHRINE := "res://scenes/world/shrine.tscn"
## The sandbox shrine (P05): grows to stage 3 with no other requirement. It faces the player's
## spawn (east), so its growth pad is at (-33.5, 0, 40); its 14 m activation radius stays
## clear of the obstacle route and the soak's targets.
const SHRINE_POS := Vector3(-40, 0, 40)

## The wolf pack in the north-west corner, more than 40 m from every feature of the obstacle
## route (tests/slow/test_obstacle_route.gd), the dummies and the soldier's patrol.
const WOLF_SPAWNS := [Vector3(-46, 0.05, -40), Vector3(-41, 0.05, -46), Vector3(-50, 0.05, -47)]
const WOLF_PATROL := [Vector3(-45, 0, -36), Vector3(-34, 0, -48), Vector3(-48, 0, -54),
	Vector3(-54, 0, -44)]

## P08's world props. The practice gate (sandbox.gate_01, structural: cracks at 50 %) stands in
## the open east of the fence, across the soak's way from the fence toward the arena's east side;
## it comes after the fence in the tree, so the soak still breaks the fence first. Two weapon
## racks behind the spawn, an ancient oak near the shrine (uproot at stage 3) and two bushes.
const GATE_SCENE := "res://scenes/world/gate_practice.tscn"
const RACK_SCENE := "res://scenes/world/weapon_rack.tscn"
const OAK_SCENE := "res://scenes/world/ancient_oak.tscn"
const BUSH_SCENE := "res://scenes/world/bush.tscn"
const GATE_POS := Vector3(44, 0, 40)
const SWORD_RACK_POS := Vector3(-6, 0, 52)
const HAMMER_RACK_POS := Vector3(6, 0, 52)
const OAK_POS := Vector3(-50, 0, 52)
const BUSH_POSITIONS := [Vector3(-12, 0, 48), Vector3(12, 0, 48)]
## P11b: the sparring post (block, parry and dodge practice) west of the test wall, near the
## wall dummy and on the way to the shrine: more than 9 m from every leg of the obstacle route
## (tests/slow/test_obstacle_route.gd) and 20 m from the soak's paths. It is not in the
## "enemies" group, so the soak never takes it for an enemy to kill.
const POST_SCENE := "res://scenes/enemies/sparring_post.tscn"
const POST_POS := Vector3(-22, 0.05, 40)


static func build_all(kit: SceneKit) -> void:
	var root := build_arena(kit)
	if root != null:
		kit.save(root, PATH)


static func build_arena(kit: SceneKit) -> Node:
	var root := Node3D.new()
	root.name = "SandboxArena"
	kit.scripted(root, S_ARENA)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.33, 0.50, 0.78)
	psm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	psm.ground_bottom_color = Color(0.22, 0.22, 0.2)
	psm.ground_horizon_color = Color(0.62, 0.64, 0.62)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-52, -32, 0)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	root.add_child(sun)

	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 35.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = SceneKit.L_WORLD | SceneKit.L_ACTORS | SceneKit.L_BREAKABLE
	nav.navigation_mesh = nm
	root.add_child(nav)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = SceneKit.L_WORLD
	ground.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.name = "Shape"
	gcs.shape = kit.box_shape(Vector3(130, 1, 130))
	gcs.position = Vector3(0, -0.5, 0)
	ground.add_child(gcs)
	var gmesh := MeshInstance3D.new()
	gmesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(130, 130)
	gmesh.mesh = plane
	gmesh.material_override = kit.mats["ground"]
	ground.add_child(gmesh)
	nav.add_child(ground)

	var walls := kit.n3("Walls")
	walls.add_child(kit.static_box("North", Vector3(124, 8, 2), Vector3(0, 4, -61), "stone"))
	walls.add_child(kit.static_box("South", Vector3(124, 8, 2), Vector3(0, 4, 61), "stone"))
	walls.add_child(kit.static_box("East", Vector3(2, 8, 124), Vector3(61, 4, 0), "stone"))
	walls.add_child(kit.static_box("West", Vector3(2, 8, 124), Vector3(-61, 4, 0), "stone"))
	nav.add_child(walls)

	var pillars := kit.n3("Pillars")
	var pillar_positions := [Vector3(-22, 4, -4), Vector3(22, 4, -40), Vector3(-9, 4, -34),
		Vector3(9, 4, -36), Vector3(-34, 4, 22), Vector3(36, 4, 20)]
	for i in pillar_positions.size():
		pillars.add_child(kit.static_box("Pillar%d" % i, Vector3(3, 8, 3), pillar_positions[i], "stone_dark"))
	nav.add_child(pillars)

	var tests := kit.n3("TestFeatures")
	# Wall lane: a dummy stands behind a solid wall; swings must not pass through it.
	tests.add_child(kit.static_box("TestWall", Vector3(0.8, 6, 12), Vector3(-14, 3, 36), "stone"))
	# Doorway: 2.6 m wide, 5 m tall opening for camera/clearance checks.
	tests.add_child(kit.static_box("DoorwayLeft", Vector3(17.7, 7, 1), Vector3(-35.15, 3.5, 10), "stone"))
	tests.add_child(kit.static_box("DoorwayRight", Vector3(11.7, 7, 1), Vector3(-17.85, 3.5, 10), "stone"))
	tests.add_child(kit.static_box("DoorwayLintel", Vector3(2.6, 2, 1), Vector3(-25, 6, 10), "stone"))
	# Low arch: 6 m wide tunnel with a 4.2 m ceiling (giant is 3.66 m).
	tests.add_child(kit.static_box("ArchWallWest", Vector3(1, 4.2, 8), Vector3(21.5, 2.1, 6), "stone_dark"))
	tests.add_child(kit.static_box("ArchWallEast", Vector3(1, 4.2, 8), Vector3(28.5, 2.1, 6), "stone_dark"))
	tests.add_child(kit.static_box("ArchRoof", Vector3(8, 0.8, 8), Vector3(25, 4.6, 6), "stone_dark"))
	# Ramp (20 degrees) up to a 3 m platform.
	tests.add_child(kit.static_box("Platform", Vector3(10, 3, 10), Vector3(36, 1.5, -24), "stone"))
	var ramp_len := 3.0 / sin(deg_to_rad(20.0))
	var ramp := kit.static_box("Ramp", Vector3(5, 0.4, ramp_len), Vector3(36, 1.5 - 0.19, -19 + 3.0 / tan(deg_to_rad(20.0)) * 0.5), "stone")
	ramp.rotation_degrees = Vector3(20, 0, 0)
	tests.add_child(ramp)
	nav.add_child(tests)

	var fence: Node3D = kit.instance(FENCE)
	var dummy: Node3D = kit.instance(DUMMY)
	var wall_dummy: Node3D = kit.instance(DUMMY)
	var player: Node3D = kit.instance(GIANT)
	var soldier: Node3D = kit.instance(SOLDIER)
	if fence == null or dummy == null or player == null or soldier == null:
		push_error("sandbox: build the player, soldier and props scenes first")
		for n: Node in [root, fence, dummy, wall_dummy, player, soldier]:
			if n != null:
				n.free()
		return null
	fence.name = "Fence01"
	fence.position = Vector3(12, 0, 34)
	fence.rotation_degrees = Vector3(0, 90, 0)
	fence.set("world_id", "sandbox.fence_01")
	nav.add_child(fence)
	dummy.name = "PracticeDummy"
	dummy.position = Vector3(0, 0, 32)
	dummy.set("entity_id", "dummy_01")
	nav.add_child(dummy)
	wall_dummy.name = "WallDummy"
	wall_dummy.position = Vector3(-16.5, 0, 36)
	wall_dummy.set("entity_id", "dummy_behind_wall")
	nav.add_child(wall_dummy)

	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", Vector3(0, 0.05, 40)))
	root.add_child(spawns)
	var route := kit.n3("PatrolRoute")
	for i in 3:
		route.add_child(kit.marker("P%d" % (i + 1), [Vector3(0, 0, -12), Vector3(14, 0, -22), Vector3(-14, 0, -22)][i]))
	root.add_child(route)
	player.name = "Player"
	player.position = Vector3(0, 0.05, 40)
	root.add_child(player)
	soldier.name = "Soldier01"
	soldier.position = Vector3(0, 0.05, -12)
	soldier.set("entity_id", "soldier_01")
	soldier.set("patrol_route", NodePath("../PatrolRoute"))
	root.add_child(soldier)
	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)

	var signs := kit.n3("Signs")
	signs.add_child(kit.sign("PRACTICE DUMMY (armor 25)", Vector3(0, 3.3, 32)))
	signs.add_child(kit.sign("BREAKABLE FENCE", Vector3(12, 2.6, 34)))
	signs.add_child(kit.sign("WALL TEST: hits must not pass", Vector3(-12.5, 6.8, 36)))
	signs.add_child(kit.sign("DOORWAY 2.6 x 5 m", Vector3(-25, 7.8, 10)))
	signs.add_child(kit.sign("LOW ARCH 4.2 m", Vector3(25, 5.8, 6)))
	signs.add_child(kit.sign("RAMP 20 deg", Vector3(36, 5.0, -14)))
	signs.add_child(kit.sign("SOLDIER PATROL", Vector3(0, 4.0, -18)))
	root.add_child(signs)
	_add_wolves(kit, root, signs)
	_add_shrine(kit, nav, signs)
	_add_world_props(kit, nav, root, signs)
	_add_sparring_post(kit, root, signs)
	return root


## The sparring post (sandbox.sparring_post, P11b) beside the dummies; it swings every 3 s while
## the giant stands within 4 m.
static func _add_sparring_post(kit: SceneKit, root: Node3D, signs: Node3D) -> void:
	if not ResourceLoader.exists(kit.output_path(POST_SCENE)):
		print("sandbox: skipped the sparring post (%s not built yet)" % POST_SCENE)
		return
	var post: Node3D = kit.instance(POST_SCENE)
	post.name = "SparringPost"
	post.position = POST_POS
	post.set("entity_id", "sandbox.sparring_post")
	root.add_child(post)
	signs.add_child(kit.sign("SPARRING POST: block, parry, dodge", POST_POS + Vector3(0, 3.2, 0)))


## The practice gate, the sword and hammer racks, the ancient oak and two bushes (P08). Obstacles
## go under Navigation (baked; the gate's break re-bakes the sandbox), the bushes under the root.
static func _add_world_props(kit: SceneKit, nav: Node3D, root: Node3D, signs: Node3D) -> void:
	for path: String in [GATE_SCENE, RACK_SCENE, OAK_SCENE, BUSH_SCENE]:
		if not ResourceLoader.exists(kit.output_path(path)):
			print("sandbox: skipped the world props (%s not built yet)" % path)
			return
	var gate: Node3D = kit.instance(GATE_SCENE)
	gate.name = "PracticeGate"
	gate.position = GATE_POS
	gate.rotation_degrees = Vector3(0, 90, 0)
	gate.set("world_id", "sandbox.gate_01")
	nav.add_child(gate)
	signs.add_child(kit.sign("PRACTICE GATE: cracks, then breaks", GATE_POS + Vector3(0, 7.6, 0)))
	for spec: Array in [["SwordRack", "sandbox.sword_rack", "weapon.sword", SWORD_RACK_POS],
			["HammerRack", "sandbox.hammer_rack", "weapon.hammer", HAMMER_RACK_POS]]:
		var rack: Node3D = kit.instance(RACK_SCENE)
		rack.name = spec[0]
		rack.position = spec[3]
		rack.set("world_id", spec[1])
		rack.set("weapon_id", spec[2])
		nav.add_child(rack)
	signs.add_child(kit.sign("WEAPON RACKS: sword, hammer (E)", Vector3(0, 3.4, 52)))
	var oak: Node3D = kit.instance(OAK_SCENE)
	oak.name = "AncientOak"
	oak.position = OAK_POS
	oak.set("world_id", "sandbox.oak_01")
	nav.add_child(oak)
	signs.add_child(kit.sign("ANCIENT OAK: uproot it at stage 3 (E)", OAK_POS + Vector3(0, 4.0, -2.0)))
	for i in BUSH_POSITIONS.size():
		var bush: Node3D = kit.instance(BUSH_SCENE)
		bush.name = "Bush%02d" % (i + 1)
		bush.position = BUSH_POSITIONS[i]
		root.add_child(bush)


## One shrine (sandbox.shrine, record shrine.sandbox) west of the spawn (P05).
static func _add_shrine(kit: SceneKit, parent: Node3D, signs: Node3D) -> void:
	if not ResourceLoader.exists(kit.output_path(SHRINE)):
		print("sandbox: skipped the shrine (%s not built yet)" % SHRINE)
		return
	var shrine: Node3D = kit.instance(SHRINE)
	shrine.name = "Shrine"
	shrine.position = SHRINE_POS
	shrine.rotation_degrees = Vector3(0, -90, 0)
	shrine.set("world_id", "sandbox.shrine")
	shrine.set("shrine_id", "shrine.sandbox")
	parent.add_child(shrine)
	signs.add_child(kit.sign("SHRINE: rest and grow (stages 1-3)", SHRINE_POS + Vector3(0, 6.2, 0)))


## Three wolves (sandbox.wolf_1..3) on one patrol in the north-west corner (P04).
static func _add_wolves(kit: SceneKit, root: Node3D, signs: Node3D) -> void:
	if not ResourceLoader.exists(kit.output_path(WOLF)):
		print("sandbox: skipped the wolves (%s not built yet)" % WOLF)
		return
	var patrol := kit.n3("WolfPatrol")
	for i in WOLF_PATROL.size():
		patrol.add_child(kit.marker("P%d" % (i + 1), WOLF_PATROL[i]))
	root.add_child(patrol)
	for i in WOLF_SPAWNS.size():
		var wolf: Node3D = kit.instance(WOLF)
		wolf.name = "Wolf%02d" % (i + 1)
		wolf.position = WOLF_SPAWNS[i]
		wolf.rotation_degrees = Vector3(0, 45, 0)
		wolf.set("entity_id", "sandbox.wolf_%d" % (i + 1))
		wolf.set("patrol_route", NodePath("../WolfPatrol"))
		root.add_child(wolf)
	signs.add_child(kit.sign("WOLF PACK", Vector3(-45, 3.0, -45)))
