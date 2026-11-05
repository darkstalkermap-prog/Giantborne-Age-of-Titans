extends RefCounted
## Builder (P11b; plan §2.12): Thornwick's people, the sparring post and the village test level.
##   scenes/npcs/villager.tscn        Civilian (npc.villager): a villager in a tunic
##   scenes/npcs/elder.tscn           Civilian (npc.elder) in a robe and hood, with an NpcTalker (P13)
##   scenes/enemies/sparring_post.tscn  SparringPost (enemy.sparring_post): a post with padded arms
##   scenes/test/village_test.tscn    a small walled village (LevelRoot level.village_test, no level
##                                    record and no director: everything is placed) for the civilian
##                                    and faction tests, playable with --level
## Runs after the player, soldier and world-prop builders (tools/build_scenes.gd BUILDERS order):
## the test level instances the giant and the soldier.

const S_CIVILIAN := "res://scripts/actors/civilian.gd"
const S_POST := "res://scripts/actors/sparring_post.gd"
const S_TALKER := "res://scripts/world/npc_talker.gd"
const S_LEVEL := "res://scripts/world/level_root.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const VILLAGER_PATH := "res://scenes/npcs/villager.tscn"
const ELDER_PATH := "res://scenes/npcs/elder.tscn"
const POST_PATH := "res://scenes/enemies/sparring_post.tscn"
const VILLAGE_TEST_PATH := "res://scenes/test/village_test.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const SOLDIER := "res://scenes/enemies/soldier.tscn"
const BUILDER_DIRECTOR := "res://tools/builders/test_director.gd"

## Palette additions (name -> [albedo, roughness]).
const MATERIALS := {
	"villager_tunic": [Color(0.42, 0.50, 0.30), 0.9],
	"villager_trousers": [Color(0.36, 0.30, 0.22), 0.9],
	"villager_skin": [Color(0.86, 0.68, 0.53), 0.8],
	"villager_hair": [Color(0.32, 0.22, 0.13), 0.9],
	"elder_robe": [Color(0.40, 0.35, 0.52), 0.9],
	"elder_hood": [Color(0.30, 0.26, 0.40), 0.9],
	"elder_hair": [Color(0.86, 0.85, 0.82), 0.9],
	"post_wood": [Color(0.58, 0.42, 0.26), 0.85],
	"post_pad": [Color(0.78, 0.70, 0.50), 0.95],
	"village_plaster": [Color(0.86, 0.82, 0.72), 0.95],
	"village_roof": [Color(0.55, 0.40, 0.22), 0.95],
}

# --------------------------------------------------------------------------- village test level

const LEVEL_ID := "level.village_test"
const FLOOR_SIZE := 80.0
const START := Vector3(0, 0.05, 30)
## The human navigation layer (plan §2.2), as the director test level bakes it.
const NAV_HUMAN := {"layers": 1, "radius": 0.6, "height": 2.0, "cell": 0.3, "cell_height": 0.25,
	"climb": 0.25, "slope": 35.0}
## Cottages (8 x 6 m, 4 m walls) round a small square at the origin, a walled yard north of them
## whose safe marker no path reaches, and the level's walls: [name, size, centre, walkable top].
const BOXES := [
	["Floor", Vector3(FLOOR_SIZE, 1, FLOOR_SIZE), Vector3(0, -0.5, 0), true],
	["WallNorth", Vector3(84, 4, 2), Vector3(0, 2, -41), false],
	["WallSouth", Vector3(84, 4, 2), Vector3(0, 2, 41), false],
	["WallEast", Vector3(2, 4, 84), Vector3(41, 2, 0), false],
	["WallWest", Vector3(2, 4, 84), Vector3(-41, 2, 0), false],
	["CottageNW", Vector3(8, 4, 6), Vector3(-10, 2, -8), false],
	["CottageNE", Vector3(8, 4, 6), Vector3(10, 2, -8), false],
	["CottageSW", Vector3(8, 4, 6), Vector3(-10, 2, 8), false],
	["CottageSE", Vector3(8, 4, 6), Vector3(10, 2, 8), false],
	["YardNorth", Vector3(6.2, 3, 0.6), Vector3(0, 1.5, -25.3), false],
	["YardSouth", Vector3(6.2, 3, 0.6), Vector3(0, 1.5, -18.7), false],
	["YardEast", Vector3(0.6, 3, 6.2), Vector3(3.3, 1.5, -22), false],
	["YardWest", Vector3(0.6, 3, 6.2), Vector3(-3.3, 1.5, -22), false],
]
## [kind folder, LevelMarker.Kind, marker_id, position, faction]: the cottage doors (safe), the
## yard's unreachable shelter (safe), the guards' posts (formation, faction village).
const MARKERS := [
	["Safe", 4, "test.village.safe_nw", Vector3(-5, 0, -8), ""],
	["Safe", 4, "test.village.safe_ne", Vector3(5, 0, -8), ""],
	["Safe", 4, "test.village.safe_sw", Vector3(-5, 0, 8), ""],
	["Safe", 4, "test.village.safe_se", Vector3(5, 0, 8), ""],
	["Safe", 4, "test.village.safe_yard", Vector3(0, 0, -22), ""],
	["Formation", 3, "test.village.guard_post_1", Vector3(-6, 0, 18), "village"],
	["Formation", 3, "test.village.guard_post_2", Vector3(6, 0, 18), "village"],
	["Objective", 0, "test.village.elder", Vector3(0, 0, -4), ""],
]
## [node name, entity id, position, yaw degrees]
const VILLAGERS := [
	["Villager1", "test.village.villager_1", Vector3(-2, 0.05, -3), 30.0],
	["Villager2", "test.village.villager_2", Vector3(2, 0.05, -3), -30.0],
	["Villager3", "test.village.villager_3", Vector3(-1.5, 0.05, 3.5), 160.0],
	["Villager4", "test.village.villager_4", Vector3(0, 0.05, -16.5), 0.0],
]
const ELDER := ["Elder", "test.village.elder", Vector3(0, 0.05, -6), 180.0]
const GUARDS := [
	["Guard1", "test.village.guard_1", Vector3(-6, 0.05, 18), 180.0],
	["Guard2", "test.village.guard_2", Vector3(6, 0.05, 18), 180.0],
]


static func build_all(kit: SceneKit) -> void:
	for mat_name: String in MATERIALS:
		var spec: Array = MATERIALS[mat_name]
		kit.add_material(mat_name, spec[0], spec[1])
	kit.save(build_villager(kit), VILLAGER_PATH)
	kit.save(build_elder(kit), ELDER_PATH)
	kit.save(build_sparring_post(kit), POST_PATH)
	var level := build_village_test(kit)
	if level != null:
		kit.save(level, VILLAGE_TEST_PATH)


# --------------------------------------------------------------------------- people

## A villager: a 1.7 m person (capsule r 0.3) on the human nav layer, team NEUTRAL.
static func build_villager(kit: SceneKit) -> Node:
	return _person(kit, "Villager", "villager_01", "npc.villager",
		{"tunic": "villager_tunic", "legs": "villager_trousers", "skin": "villager_skin", "hair": "villager_hair"},
		false)


## The elder: a villager's body in a robe and hood, with an NpcTalker (npc id = the actor's
## entity id, dialogue = its record's "dialogue").
static func build_elder(kit: SceneKit) -> Node:
	var root := _person(kit, "Elder", "elder_01", "npc.elder",
		{"tunic": "elder_robe", "legs": "elder_robe", "skin": "villager_skin", "hair": "elder_hair"}, true)
	var talker := Node3D.new()
	talker.name = "Talker"
	kit.scripted(talker, S_TALKER, {"radius_m": 4.0, "priority": 40})
	talker.position = Vector3(0, 1.0, 0)
	root.add_child(talker)
	return root


static func _person(kit: SceneKit, node_name: String, entity_id: String, definition: String,
		palette: Dictionary, elder: bool) -> Node:
	var root := CharacterBody3D.new()
	root.name = node_name
	kit.scripted(root, S_CIVILIAN, {"entity_id": entity_id, "faction": "village"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position = Vector3(0, 0.85, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity(entity_id, definition, 0))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.1, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.15
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 1.56, 0)))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(0.46, 0.6, 0.3)), Vector3(0, 1.08, 0)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.4, 0.8, 0.3)), Vector3(0, 0.4, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 0.8, "leg_swing_rad": 0.6,
		"idle_arm_pose": Vector2(8, -82), "off_idle_pose": Vector2(-8, -82)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.11 * side, 0.8, 0))
		hip.add_child(kit.box("Leg", Vector3(0.17, 0.76, 0.2), Vector3(0, -0.38, 0), palette.legs))
		hip.add_child(kit.box("Shoe", Vector3(0.19, 0.1, 0.28), Vector3(0, -0.76, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 0.8, 0))
	if elder:
		torso.add_child(kit.box("Robe", Vector3(0.5, 0.62, 0.32), Vector3(0, 0.28, 0), palette.tunic))
		torso.add_child(kit.box("Skirt", Vector3(0.46, 0.6, 0.3), Vector3(0, -0.26, 0), palette.tunic))
		torso.add_child(kit.box("Head", Vector3(0.22, 0.24, 0.24), Vector3(0, 0.74, 0), palette.skin))
		torso.add_child(kit.box("Hood", Vector3(0.3, 0.3, 0.3), Vector3(0, 0.8, 0.04), "elder_hood"))
		torso.add_child(kit.box("Beard", Vector3(0.16, 0.16, 0.06), Vector3(0, 0.62, -0.13), palette.hair))
	else:
		torso.add_child(kit.box("Tunic", Vector3(0.46, 0.6, 0.28), Vector3(0, 0.28, 0), palette.tunic))
		torso.add_child(kit.box("Belt", Vector3(0.48, 0.08, 0.3), Vector3(0, 0.04, 0), "giant_belt"))
		torso.add_child(kit.box("Head", Vector3(0.22, 0.24, 0.24), Vector3(0, 0.74, 0), palette.skin))
		torso.add_child(kit.box("Hair", Vector3(0.24, 0.08, 0.26), Vector3(0, 0.88, 0.01), palette.hair))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.27 * side, 1.34, 0))
		shoulder.basis = SceneKit.arm_basis(8.0 * side, -82.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.11, 0.11, 0.28), Vector3(0, 0, -0.14), palette.tunic))
		shoulder.add_child(kit.box("Forearm", Vector3(0.1, 0.1, 0.24), Vector3(0, 0, -0.4), palette.skin))
		if elder and side < 0:
			var staff := kit.cyl("Staff", 0.03, 0.03, 1.6, Vector3(0, 0, -0.55), "wood_dark")
			staff.rotation_degrees = Vector3(-90, 0, 0)
			shoulder.add_child(staff)
		body.add_child(shoulder)
	visual.add_child(kit.lod_proxy(Vector3(0.45, 1.7, 0.3), Vector3(0, 0.85, 0), palette.tunic))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- sparring post

## The sparring post: 2.2 m, capsule r 0.4, team ENEMY; padded arms at 1.45 m that spin through
## a swing (SparringPost turns Visual/Body/Arms).
static func build_sparring_post(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "SparringPost"
	kit.scripted(root, S_POST, {"entity_id": "sparring_post_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.2
	cs.shape = cap
	cs.position = Vector3(0, 1.1, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("sparring_post_01", "enemy.sparring_post", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.3, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Post", "torso", kit.box_shape(Vector3(0.6, 1.4, 0.6)), Vector3(0, 1.4, 0)))
	hb.add_child(kit.hurtbox("Base", "legs", kit.box_shape(Vector3(0.6, 0.7, 0.6)), Vector3(0, 0.35, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	var body := kit.n3("Body")
	body.add_child(kit.cyl("Base", 0.55, 0.6, 0.25, Vector3(0, 0.125, 0), "wood_dark"))
	body.add_child(kit.cyl("Post", 0.2, 0.24, 2.0, Vector3(0, 1.1, 0), "post_wood"))
	body.add_child(kit.box("Cap", Vector3(0.5, 0.18, 0.5), Vector3(0, 2.12, 0), "wood_dark"))
	body.add_child(kit.box("Collar", Vector3(0.56, 0.12, 0.56), Vector3(0, 1.45, 0), "steel"))
	var arms := kit.n3("Arms", Vector3(0, 1.45, 0))
	arms.add_child(kit.box("ArmMain", Vector3(2.9, 0.14, 0.14), Vector3.ZERO, "post_wood"))
	arms.add_child(kit.box("PadA", Vector3(0.36, 0.4, 0.36), Vector3(1.45, 0, 0), "post_pad"))
	arms.add_child(kit.box("PadB", Vector3(0.36, 0.4, 0.36), Vector3(-1.45, 0, 0), "post_pad"))
	arms.add_child(kit.box("ArmLow", Vector3(0.12, 0.12, 2.2), Vector3(0, -0.45, 0), "post_wood"))
	arms.add_child(kit.box("PadC", Vector3(0.3, 0.3, 0.3), Vector3(0, -0.45, 1.1), "post_pad"))
	arms.add_child(kit.box("PadD", Vector3(0.3, 0.3, 0.3), Vector3(0, -0.45, -1.1), "post_pad"))
	body.add_child(arms)
	visual.add_child(body)
	visual.add_child(kit.lod_proxy(Vector3(0.6, 2.2, 0.6), Vector3(0, 1.1, 0), "post_wood"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- village test level

static func build_village_test(kit: SceneKit) -> Node:
	var director_builder: Variant = load(BUILDER_DIRECTOR)
	var player: Node3D = kit.instance(GIANT)
	if player == null or director_builder == null:
		push_error("npcs: build the player scene (and keep tools/builders/test_director.gd) first")
		if player != null:
			player.free()
		return null
	var root := Node3D.new()
	root.name = "VillageTestLevel"
	kit.scripted(root, S_LEVEL, {"level_id": LEVEL_ID})
	_add_environment(root)

	var world := kit.n3("World")
	for spec: Array in BOXES:
		var mat := "stone"
		if str(spec[0]).begins_with("Cottage"):
			mat = "village_plaster"
		elif str(spec[0]).begins_with("Yard"):
			mat = "wood_dark"
		var body := kit.static_box(spec[0], spec[1], spec[2], mat)
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
		elif str(spec[0]).begins_with("Cottage"):
			var size: Vector3 = spec[1]
			var roof := kit.box("Roof", Vector3(size.x + 0.6, 0.4, size.z + 0.6), Vector3(0, size.y * 0.5 + 0.2, 0), "village_roof")
			body.add_child(roof)
		world.add_child(body)
	root.add_child(world)

	var nav := kit.n3("Navigation")
	var human := NavigationRegion3D.new()
	human.name = "Human"
	human.navigation_layers = int(NAV_HUMAN.layers)
	human.navigation_mesh = director_builder.bake_navmesh(NAV_HUMAN, BOXES)
	nav.add_child(human)
	root.add_child(nav)

	var markers := kit.n3("Markers")
	for spec: Array in MARKERS:
		var folder := markers.get_node_or_null(NodePath(spec[0])) as Node3D
		if folder == null:
			folder = kit.n3(spec[0])
			markers.add_child(folder)
		folder.add_child(kit.scripted(kit.marker(str(spec[2]).validate_node_name(), spec[3]), S_MARKER,
			{"marker_id": spec[2], "kind": spec[1], "faction": spec[4]}))
	root.add_child(markers)

	var folk := kit.n3("Folk")
	for spec: Array in VILLAGERS:
		var v := kit.instance(VILLAGER_PATH) as Node3D
		if v != null:
			folk.add_child(_placed(v, spec))
	var elder := kit.instance(ELDER_PATH) as Node3D
	if elder != null:
		folk.add_child(_placed(elder, ELDER))
	root.add_child(folk)
	var guards := kit.n3("Guards")
	for spec: Array in GUARDS:
		var g := kit.instance(SOLDIER) as Node3D
		if g != null:
			g.set("faction", "village")
			guards.add_child(_placed(g, spec))
	root.add_child(guards)

	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", START), S_CHECKPOINT,
		{"checkpoint_id": "test.village.cp_start"}))
	root.add_child(checkpoints)
	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", START))
	root.add_child(spawns)
	root.add_child(kit.n3("Spawned"))
	player.name = "Player"
	player.position = START
	root.add_child(player)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignStart", "VILLAGE TEST: neutral guards, villagers, the elder", START + Vector3(0, 4.5, -4)],
			["SignYard", "WALLED YARD: a shelter no path reaches", Vector3(0, 4.0, -22)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


static func _placed(n: Node3D, spec: Array) -> Node3D:
	n.name = spec[0]
	n.set("entity_id", spec[1])
	n.position = spec[2]
	n.rotation_degrees = Vector3(0, spec[3], 0)
	return n


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
