extends RefCounted
## Builder (P09): the ranged enemies and their playground.
##   scenes/enemies/archer.tscn  ArcherEnemy (enemy.archer): leather and a hood, a bow in the
##                               weapon hand, a quiver; Anchors/Grab at the chest (torso_fist).
##   scenes/enemies/mage.tscn    MageEnemy (enemy.mage): a robe and a hood, a staff with a glowing
##                               head in the weapon hand; Anchors/Grab at the chest.
##   scenes/test/ranged_test.tscn  a 120 x 120 m test level: a raised platform with a ramp and an
##                               elevation marker on top, two cover walls with cover markers, a
##                               sight-blocking wall, a navmesh baked here (human layer), the giant,
##                               two archers, a mage and a soldier for its barrier.
## Both enemies share the soldier's body plan (1.8 m, capsule radius 0.35, the same hurtboxes),
## with Visual/LodProxy for AI LOD tier 2. Gameplay numbers live in data/enemies/{archer,mage}.json.
## Runs after the player and soldier builders (it instances giant.tscn and soldier.tscn).

const S_ARCHER := "res://scripts/actors/archer_enemy.gd"
const S_MAGE := "res://scripts/actors/mage_enemy.gd"
const ARCHER_PATH := "res://scenes/enemies/archer.tscn"
const MAGE_PATH := "res://scenes/enemies/mage.tscn"
const TEST_PATH := "res://scenes/test/ranged_test.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const SOLDIER := "res://scenes/enemies/soldier.tscn"

## The ranged test level's layout (also read by tests).
const PLAYER_POS := Vector3(0, 0.05, 14)
const PLATFORM_CENTER := Vector3(-16, 1.0, -22)
const PLATFORM_SIZE := Vector3(6, 2, 6)
const RAMP_LOW_Z := -9.0                      ## the ramp runs from here (ground) to the platform's edge
const ELEVATION_POINT := Vector3(-16, 2.0, -22)
const COVER_WALLS := [Vector3(10, 0.8, -10), Vector3(20, 0.8, -2)]
const COVER_POINTS := [Vector3(10, 0.05, -11.2), Vector3(20, 0.05, -3.2)]
const SIGHT_WALL := Vector3(-2, 2.5, -4)
const SIGHT_WALL_SIZE := Vector3(8, 5, 0.8)
const ARCHER_SPAWNS := [Vector3(-8, 0.05, -16), Vector3(12, 0.05, -18)]
const MAGE_SPAWN := Vector3(2, 0.05, -20)
const SOLDIER_SPAWN := Vector3(4, 0.05, -15)


static func build_all(kit: SceneKit) -> void:
	kit.add_material("archer_leather", Color(0.42, 0.33, 0.22), 0.9)
	kit.add_material("archer_hood", Color(0.20, 0.32, 0.18), 0.95)
	kit.add_material("bow_wood", Color(0.50, 0.32, 0.16), 0.8)
	kit.add_material("mage_robe", Color(0.22, 0.20, 0.45), 0.9)
	kit.add_material("mage_trim", Color(0.78, 0.62, 0.25), 0.5, 0.3)
	kit.add_material("staff_gem", Color(0.45, 0.95, 1.0), 0.2)
	kit.save(build_archer(kit), ARCHER_PATH)
	kit.save(build_mage(kit), MAGE_PATH)
	var level := build_test_level(kit)
	if level != null:
		kit.save(level, TEST_PATH)


## The shared body plan: root CharacterBody3D (script, entity id, actor mask), BodyShape,
## CombatEntity, Anchors (Torso, Grab), Hurtboxes, NavAgent and an ActorRig Visual with Body,
## hips and legs, shoulders and LodProxy. `dress` adds the archetype's meshes.
static func _humanoid(kit: SceneKit, node_name: String, script_path: String, entity_id: String,
		definition_id: String, cloth: String, trim: String) -> Dictionary:
	var root := CharacterBody3D.new()
	root.name = node_name
	kit.scripted(root, script_path, {"entity_id": entity_id})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.35
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity(entity_id, definition_id, 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.15, 0)))
	# P07: where a giant's fist closes around it (attachment profile torso_fist).
	anchors.add_child(kit.marker("Grab", Vector3(0, 1.2, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.17
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 1.63, 0)))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(0.55, 0.65, 0.32)), Vector3(0, 1.15, 0)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.45, 0.85, 0.3)), Vector3(0, 0.42, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 0.9, "leg_swing_rad": 0.6,
		"idle_arm_pose": Vector2(15, -70), "block_pose": Vector2(-30, 10)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0))
		hip.add_child(kit.box("Leg", Vector3(0.2, 0.82, 0.24), Vector3(0, -0.41, 0), cloth))
		hip.add_child(kit.box("Boot", Vector3(0.22, 0.12, 0.32), Vector3(0, -0.8, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 0.85, 0))
	torso.add_child(kit.box("Tunic", Vector3(0.5, 0.64, 0.3), Vector3(0, 0.31, 0), cloth))
	torso.add_child(kit.box("Belt", Vector3(0.52, 0.08, 0.32), Vector3(0, 0.04, 0), trim))
	torso.add_child(kit.box("Head", Vector3(0.24, 0.26, 0.26), Vector3(0, 0.78, 0), "soldier_skin"))
	body.add_child(torso)
	var shoulders: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		shoulder.basis = SceneKit.arm_basis(15.0 * side, -70.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.13, 0.13, 0.3), Vector3(0, 0, -0.15), cloth))
		shoulder.add_child(kit.box("Forearm", Vector3(0.12, 0.12, 0.25), Vector3(0, 0, -0.42), "soldier_skin"))
		body.add_child(shoulder)
		shoulders.append(shoulder)
	# AI LOD tier 2 shows this single box instead of the rig (EnemyActor.set_lod_tier).
	visual.add_child(kit.lod_proxy(Vector3(0.5, 1.8, 0.35), Vector3(0, 0.9, 0), cloth))
	root.add_child(visual)
	return {"root": root, "torso": torso, "left": shoulders[0], "right": shoulders[1], "body": body}


static func build_archer(kit: SceneKit) -> Node:
	var parts := _humanoid(kit, "Archer", S_ARCHER, "archer_01", "enemy.archer", "archer_leather", "giant_belt")
	var torso: Node3D = parts.torso
	torso.add_child(kit.box("Hood", Vector3(0.3, 0.2, 0.32), Vector3(0, 0.9, 0.02), "archer_hood"))
	torso.add_child(kit.box("Cape", Vector3(0.46, 0.6, 0.06), Vector3(0, 0.36, 0.19), "archer_hood"))
	torso.add_child(kit.box("Quiver", Vector3(0.14, 0.62, 0.14), Vector3(0.12, 0.5, 0.24), "giant_belt"))
	torso.add_child(kit.box("Fletching", Vector3(0.12, 0.12, 0.12), Vector3(0.12, 0.86, 0.24), "soldier_tabard"))
	# The bow stands upright in the weapon hand; the rig points that arm at the aim point.
	var hand: Node3D = parts.right
	hand.add_child(kit.box("Grip", Vector3(0.06, 0.12, 0.06), Vector3(0, 0, -0.52), "giant_belt"))
	hand.add_child(kit.box("LimbUpper", Vector3(0.05, 0.06, 0.62), Vector3(0, 0.0, -0.52), "bow_wood"))
	var upper := hand.get_node("LimbUpper") as Node3D
	upper.basis = Basis(Vector3.RIGHT, deg_to_rad(90.0))
	upper.position = Vector3(0, 0.3, -0.56)
	hand.add_child(kit.box("LimbLower", Vector3(0.05, 0.06, 0.62), Vector3(0, -0.3, -0.56), "bow_wood"))
	(hand.get_node("LimbLower") as Node3D).basis = Basis(Vector3.RIGHT, deg_to_rad(90.0))
	hand.add_child(kit.box("String", Vector3(0.01, 1.2, 0.01), Vector3(0, 0, -0.44), "soldier_skin"))
	return parts.root


static func build_mage(kit: SceneKit) -> Node:
	var parts := _humanoid(kit, "Mage", S_MAGE, "mage_01", "enemy.mage", "mage_robe", "mage_trim")
	var torso: Node3D = parts.torso
	torso.add_child(kit.box("Hood", Vector3(0.3, 0.24, 0.32), Vector3(0, 0.9, 0.02), "mage_robe"))
	torso.add_child(kit.box("Mantle", Vector3(0.56, 0.12, 0.36), Vector3(0, 0.58, 0), "mage_trim"))
	# The robe hangs from the waist over the legs (on the body, so it does not swing with them).
	(parts.body as Node3D).add_child(kit.box("Robe", Vector3(0.5, 0.82, 0.34), Vector3(0, 0.44, 0), "mage_robe"))
	var hand: Node3D = parts.right
	hand.add_child(kit.box("Staff", Vector3(0.06, 0.06, 1.3), Vector3(0, 0, -0.5 - 0.65), "bow_wood"))
	hand.add_child(kit.sphere("Gem", 0.1, Vector3(0, 0, -1.82), "staff_gem"))
	return parts.root


# --------------------------------------------------------------------------- ranged test level

static func build_test_level(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var soldier: Node3D = kit.instance(SOLDIER)
	var archers: Array[Node3D] = []
	for i in ARCHER_SPAWNS.size():
		archers.append(kit.instance(ARCHER_PATH))
	var mage: Node3D = kit.instance(MAGE_PATH)
	if player == null or soldier == null or mage == null or archers.has(null):
		push_error("ranged: build the player and soldier scenes first")
		for n: Node in [player, soldier, mage] + archers:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "RangedTest"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.48, 0.58, 0.70)
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
	sun.directional_shadow_max_distance = 80.0
	root.add_child(sun)

	# Everything that collides is listed once: the geometry nodes and the baked navmesh use it.
	var solids := _solids()
	var nav := NavigationRegion3D.new()
	nav.name = "Navigation"
	nav.navigation_layers = 1
	nav.navigation_mesh = _bake_navmesh(solids)
	root.add_child(nav)
	var geometry := kit.n3("Geometry")
	for s: Dictionary in solids:
		var body := StaticBody3D.new()
		body.name = s.name
		body.collision_layer = SceneKit.L_WORLD
		body.collision_mask = 0
		body.transform = s.xform
		var cs := CollisionShape3D.new()
		cs.name = "Shape"
		cs.shape = kit.box_shape(s.size)
		body.add_child(cs)
		if s.name == "Ground":
			var gmesh := MeshInstance3D.new()
			gmesh.name = "Mesh"
			var plane := PlaneMesh.new()
			plane.size = Vector2(s.size.x, s.size.z)
			gmesh.mesh = plane
			gmesh.position = Vector3(0, s.size.y * 0.5, 0)
			gmesh.material_override = kit.mats["ground"]
			body.add_child(gmesh)
		else:
			body.add_child(kit.box("Mesh", s.size, Vector3.ZERO, s.mat))
		geometry.add_child(body)
	root.add_child(geometry)

	var markers := kit.n3("Markers")
	var elevation := kit.marker("ElevationPlatform", ELEVATION_POINT)
	elevation.add_to_group("ai_elevation_points", true)
	markers.add_child(elevation)
	for i in COVER_POINTS.size():
		var cover := kit.marker("Cover%d" % (i + 1), COVER_POINTS[i])
		cover.add_to_group("ai_cover_points", true)
		markers.add_child(cover)
	root.add_child(markers)

	var enemies := kit.n3("Enemies")
	for i in archers.size():
		var a := archers[i]
		a.name = "Archer%02d" % (i + 1)
		a.set("entity_id", "ranged_test.archer_%d" % (i + 1))
		a.position = ARCHER_SPAWNS[i]
		enemies.add_child(a)
	mage.name = "Mage01"
	mage.set("entity_id", "ranged_test.mage_1")
	mage.position = MAGE_SPAWN
	enemies.add_child(mage)
	soldier.name = "Soldier01"
	soldier.set("entity_id", "ranged_test.soldier_1")
	soldier.position = SOLDIER_SPAWN
	enemies.add_child(soldier)
	root.add_child(enemies)

	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", PLAYER_POS))
	root.add_child(spawns)
	player.name = "Player"
	player.position = PLAYER_POS
	root.add_child(player)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignPlatform", "ELEVATION (archers climb the ramp)", ELEVATION_POINT + Vector3(0, 3.2, 0)],
			["SignCover", "COVER POINTS", COVER_POINTS[0] + Vector3(0, 3.0, 0)],
			["SignWall", "SIGHT WALL", SIGHT_WALL + Vector3(0, 3.4, 0)],
			["SignStart", "RANGED TEST: 2 archers, a mage and a soldier", PLAYER_POS + Vector3(0, 4.0, -4)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


## Every solid of the test level: {name, size, xform, mat}.
static func _solids() -> Array:
	var out: Array = []
	out.append({"name": "Ground", "size": Vector3(120, 1, 120), "xform": Transform3D(Basis(), Vector3(0, -0.5, 0)),
		"mat": "stone"})
	out.append({"name": "Platform", "size": PLATFORM_SIZE, "xform": Transform3D(Basis(), PLATFORM_CENTER),
		"mat": "stone_dark"})
	# The ramp: its top face runs from the ground at z = RAMP_LOW_Z up to the platform's near edge.
	var top_z := PLATFORM_CENTER.z + PLATFORM_SIZE.z * 0.5
	var rise := PLATFORM_CENTER.y + PLATFORM_SIZE.y * 0.5
	var run := RAMP_LOW_Z - top_z
	var length := sqrt(run * run + rise * rise)
	var angle := atan2(rise, run)
	var thickness := 0.4
	var basis := Basis(Vector3.RIGHT, angle)
	var mid := Vector3(PLATFORM_CENTER.x, rise * 0.5, (RAMP_LOW_Z + top_z) * 0.5)
	out.append({"name": "Ramp", "size": Vector3(4, thickness, length),
		"xform": Transform3D(basis, mid - basis.y * (thickness * 0.5)), "mat": "stone"})
	for i in COVER_WALLS.size():
		out.append({"name": "CoverWall%d" % (i + 1), "size": Vector3(4, 1.6, 0.6),
			"xform": Transform3D(Basis(), COVER_WALLS[i]), "mat": "wood_dark"})
	out.append({"name": "SightWall", "size": SIGHT_WALL_SIZE, "xform": Transform3D(Basis(), SIGHT_WALL),
		"mat": "stone_dark"})
	return out


## The human-layer navmesh (agent radius 0.5, height 2, cells 0.25: the sandbox's settings) baked
## here from the same boxes as the collision, so the level loads without a bake.
static func _bake_navmesh(solids: Array) -> NavigationMesh:
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 2.0
	nm.agent_max_climb = 0.25
	nm.agent_max_slope = 35.0
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	var source := NavigationMeshSourceGeometryData3D.new()
	for s: Dictionary in solids:
		var mesh := BoxMesh.new()
		mesh.size = s.size
		source.add_faces(mesh.get_faces(), s.xform)   # procedural faces (never parse GPU meshes)
	NavigationServer3D.bake_from_source_geometry_data(nm, source)
	return nm
