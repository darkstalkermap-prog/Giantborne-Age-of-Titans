extends RefCounted
## Builder: the siege engines, their crews, the cavalry and the siege test level (P32, plan M6-M9
## §2.10, §3.16, §5.11).
##
##   * scenes/world/siege_ballista.tscn, siege_catapult.tscn: SiegeEngine props (the BreakableProp
##     contract: a StaticBody3D on the breakables layer, a CombatEntity - team NEUTRAL until the engine
##     takes its side - on Anchors/Center, Intact / Broken visuals, Block* shapes, Hurtboxes/Body) facing
##     -Z with Anchors/Grab where a giant's hands close. The ballista (3.2 m) is a great crossbow on a
##     post and sled whose stock ends at its muzzle (the record's engine.muzzle_m); the catapult (4.0 m)
##     a frame with a throwing arm whose bucket is its muzzle. Each visual group is merged into one
##     vertex-coloured mesh (M8 gate, F27: one draw call, not one per material - four before); they are
##     not level scenery (a battery 180 m off must stay in view).
##   * scenes/enemies/siege_crew.tscn: the soldier's body in a leather jerkin with a mallet (P22's merged
##     rig; soldier_enemy.gd: the crew rules are EnemyBrain's P32 section).
##   * scenes/enemies/cavalry.tscn: a warhorse with its rider and lance on a QuadrupedRig (the horse's
##     head, tail and legs animate; the rider and lance ride in its body), 2.6 m tall, radius 0.9.
##   * scenes/test/siege_test.tscn: a walled 400 x 320 m floor (level.siege_test, records in data/test/)
##     with a battery of two catapults and two ballistae in the north (encounter.siege_test_battery: their
##     six crews and a shield wall of eight and a banner before them), a cavalry pair in the east
##     (encounter.siege_test_cavalry), the human and large navmeshes baked offline
##     (TestDirector.bake_navmesh), the checkpoint, the giant and the director. Its encounters wait for a
##     flag nobody sets: tests activate them.
## Runs after the player and formations builders (BUILDERS order in tools/build_scenes.gd).

const S_ENGINE := "res://scripts/world/siege_engine.gd"
const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const S_CAVALRY := "res://scripts/actors/cavalry_enemy.gd"
const S_QUAD_RIG := "res://scripts/presentation/quadruped_rig.gd"
const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CATAPULT := "res://scenes/world/siege_catapult.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const CAVALRY := "res://scenes/enemies/cavalry.tscn"
const TEST_LEVEL := "res://scenes/test/siege_test.tscn"
const TEST_DIRECTOR := "res://tools/builders/test_director.gd"

const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const GIANT := "res://scenes/player/giant.tscn"

## Colours (in-memory materials: baked into vertex colours for the rigs, embedded in the engine scenes).
const COLORS := {
	"p32_timber": Color(0.45, 0.31, 0.18),
	"p32_timber_dark": Color(0.30, 0.21, 0.13),
	"p32_split": Color(0.62, 0.47, 0.30),
	"p32_iron": Color(0.30, 0.31, 0.34),
	"p32_rope": Color(0.70, 0.62, 0.42),
	"p32_stone": Color(0.50, 0.49, 0.46),
	"p32_jerkin": Color(0.42, 0.30, 0.18),
	"p32_horse": Color(0.36, 0.25, 0.17),
	"p32_mane": Color(0.13, 0.10, 0.08),
	"p32_caparison": Color(0.20, 0.32, 0.55),
	"p32_lance": Color(0.62, 0.55, 0.42),
}

## The test level (see the class notes).
const LEVEL_ID := "level.siege_test"
const FLOOR := Vector2(400.0, 320.0)
const START := Vector3(0.0, 0.05, 80.0)
const BOXES := [
	["Floor", Vector3(400, 1, 320), Vector3(0, -0.5, 0), true],
	["WallNorth", Vector3(404, 4, 2), Vector3(0, 2, -161), false],
	["WallSouth", Vector3(404, 4, 2), Vector3(0, 2, 161), false],
	["WallEast", Vector3(2, 4, 324), Vector3(201, 2, 0), false],
	["WallWest", Vector3(2, 4, 324), Vector3(-201, 2, 0), false],
]
## [node name, scene, world id, position, yaw degrees]: the battery, facing south (+Z).
const ENGINES := [
	["CatapultWest", CATAPULT, "test.siege.catapult_1", Vector3(-30, 0, -70), 180.0],
	["BallistaWest", BALLISTA, "test.siege.ballista_1", Vector3(-12, 0, -64), 180.0],
	["BallistaEast", BALLISTA, "test.siege.ballista_2", Vector3(12, 0, -64), 180.0],
	["CatapultEast", CATAPULT, "test.siege.catapult_2", Vector3(30, 0, -70), 180.0],
]
const NAV_HUMAN := {"layers": 1, "radius": 0.6, "height": 2.0, "cell": 0.3, "cell_height": 0.25,
	"climb": 0.25, "slope": 35.0}
const NAV_LARGE := {"layers": 2, "radius": 1.5, "height": 6.0, "cell": 0.5, "cell_height": 0.25,
	"climb": 0.5, "slope": 35.0}


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.9
			kit.mats[c] = m
	kit.save(build_ballista(kit), BALLISTA)
	kit.save(build_catapult(kit), CATAPULT)
	kit.save(build_crew(kit), CREW)
	kit.save(build_cavalry(kit), CAVALRY)
	var level := build_test_level(kit)
	if level != null:
		kit.save(level, TEST_LEVEL)


# --------------------------------------------------------------------------- engines

## The root of an engine: StaticBody3D on the breakables layer with the SiegeEngine script, a
## CombatEntity (team NEUTRAL) on Anchors/Center, Anchors/Grab.
static func _engine_root(kit: SceneKit, node_name: String, world_id: String, definition_id: String,
		center: Vector3, grab: Vector3) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = node_name
	kit.scripted(root, S_ENGINE, {"world_id": world_id, "faction": ""})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	root.add_child(kit.combat_entity(world_id, definition_id, 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", center))
	anchors.add_child(kit.marker("Grab", grab))
	root.add_child(anchors)
	return root


static func _block(kit: SceneKit, node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	cs.shape = kit.box_shape(size)
	cs.position = pos
	return cs


## Merges each visual group (Intact, Broken) into one vertex-coloured mesh "Merged" (not level
## scenery). M8 gate (F27; plan M6-M9 §5.2: at most 40 static draw calls a view at low): one draw call
## an engine instead of one per material - the war camp's six engines in view cost 24 before, the
## ridge's and the fort's five 20.
static func _merged(kit: SceneKit, root: Node3D) -> Node3D:
	for group_name: String in ["Intact", "Broken"]:
		var g := root.get_node_or_null(group_name) as Node3D
		if g == null:
			continue
		var parts: Array[MeshInstance3D] = []
		for c in g.get_children():
			if c is MeshInstance3D:
				parts.append(c as MeshInstance3D)
		var merged := kit.merge_vertex_colored(parts)
		if merged != null:
			merged.name = "Merged"
	return root


## The ballista: a sled with a post, a turning stock carrying a bolt, the bow arms and their string
## (3.2 m at the bow tips), the muzzle at the stock's front end (0, 1.9, -1.9).
static func build_ballista(kit: SceneKit) -> Node:
	var root := _engine_root(kit, "SiegeBallista", "test.siege.ballista_01", "prop.siege_ballista",
		Vector3(0, 1.4, 0), Vector3(0, 1.9, 0.2))
	var intact := kit.n3("Intact")
	intact.add_child(kit.box("Sled", Vector3(2.2, 0.35, 3.4), Vector3(0, 0.18, 0.2), "p32_timber_dark"))
	intact.add_child(kit.box("SledRunnerL", Vector3(0.25, 0.3, 3.8), Vector3(-1.0, 0.15, 0.2), "p32_timber"))
	intact.add_child(kit.box("SledRunnerR", Vector3(0.25, 0.3, 3.8), Vector3(1.0, 0.15, 0.2), "p32_timber"))
	intact.add_child(kit.box("Post", Vector3(0.45, 1.3, 0.45), Vector3(0, 0.95, 0.3), "p32_timber"))
	intact.add_child(kit.box("Stock", Vector3(0.42, 0.32, 3.9), Vector3(0, 1.75, 0.0), "p32_timber"))
	intact.add_child(kit.box("Bolt", Vector3(0.12, 0.12, 2.6), Vector3(0, 1.97, -0.4), "p32_timber_dark"))
	intact.add_child(kit.box("BoltHead", Vector3(0.2, 0.2, 0.35), Vector3(0, 1.97, -1.8), "p32_iron"))
	intact.add_child(kit.box("Winch", Vector3(0.9, 0.3, 0.3), Vector3(0, 1.6, 1.75), "p32_iron"))
	for side in [-1.0, 1.0]:
		var arm := kit.box("Arm%s" % ("L" if side < 0 else "R"), Vector3(1.9, 0.22, 0.26),
			Vector3(0.95 * side, 2.45, -1.45), "p32_timber_dark")
		arm.rotation_degrees = Vector3(0, 0, 32.0 * side)
		intact.add_child(arm)
		var string := kit.box("String%s" % ("L" if side < 0 else "R"), Vector3(0.05, 0.05, 1.9),
			Vector3(0.85 * side, 2.15, -0.6), "p32_rope")
		string.rotation_degrees = Vector3(0, -38.0 * side, 0)
		intact.add_child(string)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(kit.box("Wreck", Vector3(2.0, 0.3, 3.2), Vector3(0, 0.15, 0.2), "p32_split"))
	var stock := kit.box("StockFallen", Vector3(0.4, 0.3, 3.4), Vector3(0.4, 0.45, -0.2), "p32_timber_dark")
	stock.rotation_degrees = Vector3(0, 25, 8)
	broken.add_child(stock)
	root.add_child(broken)
	root.add_child(_block(kit, "BlockBody", Vector3(2.4, 2.2, 3.8), Vector3(0, 1.1, 0.2)))
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(Vector3(2.6, 3.2, 4.0)), Vector3(0, 1.6, 0.1)))
	root.add_child(hb)
	return _merged(kit, root)


## The catapult: a wheeled frame with two uprights and a throwing arm cocked back over it, its
## bucket the muzzle (0, 4.2, 1.2); 4.0 m to the top of the uprights' cross beam.
static func build_catapult(kit: SceneKit) -> Node:
	var root := _engine_root(kit, "SiegeCatapult", "test.siege.catapult_01", "prop.siege_catapult",
		Vector3(0, 1.8, 0), Vector3(0, 2.4, 0.3))
	var intact := kit.n3("Intact")
	for side in [-1.0, 1.0]:
		intact.add_child(kit.box("Rail%s" % ("L" if side < 0 else "R"), Vector3(0.35, 0.4, 4.4),
			Vector3(1.2 * side, 0.6, 0), "p32_timber_dark"))
		intact.add_child(kit.box("Upright%s" % ("L" if side < 0 else "R"), Vector3(0.35, 3.4, 0.4),
			Vector3(1.2 * side, 2.3, -0.4), "p32_timber"))
		for z in [-1.6, 1.6]:
			intact.add_child(kit.cyl("Wheel%s%d" % ["L" if side < 0 else "R", int(z)], 0.55, 0.55, 0.25,
				Vector3(1.45 * side, 0.55, z), "p32_timber_dark"))
	for child in intact.get_children():
		if String(child.name).begins_with("Wheel"):
			(child as Node3D).rotation_degrees = Vector3(0, 0, 90)
	intact.add_child(kit.box("CrossBeam", Vector3(2.8, 0.35, 0.4), Vector3(0, 3.85, -0.4), "p32_timber"))
	intact.add_child(kit.box("Axle", Vector3(2.4, 0.25, 0.25), Vector3(0, 1.2, 0), "p32_iron"))
	intact.add_child(kit.box("Bed", Vector3(2.4, 0.25, 3.2), Vector3(0, 0.85, 0.2), "p32_timber"))
	var arm := kit.box("Arm", Vector3(0.3, 0.3, 4.2), Vector3(0, 2.75, 0.55), "p32_timber_dark")
	arm.rotation_degrees = Vector3(-38, 0, 0)
	intact.add_child(arm)
	intact.add_child(kit.box("Bucket", Vector3(0.9, 0.35, 0.9), Vector3(0, 4.0, 1.25), "p32_timber"))
	intact.add_child(kit.sphere("Stone", 0.38, Vector3(0, 4.3, 1.25), "p32_stone"))
	intact.add_child(kit.box("Counterweight", Vector3(1.1, 0.8, 0.9), Vector3(0, 1.45, -1.0), "p32_stone"))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(kit.box("Wreck", Vector3(2.6, 0.4, 3.8), Vector3(0, 0.2, 0), "p32_split"))
	var fallen := kit.box("ArmFallen", Vector3(0.3, 0.3, 4.0), Vector3(-0.6, 0.55, 0.3), "p32_timber_dark")
	fallen.rotation_degrees = Vector3(0, 30, 10)
	broken.add_child(fallen)
	broken.add_child(kit.box("CounterweightFallen", Vector3(1.1, 0.8, 0.9), Vector3(0.8, 0.4, -1.4), "p32_stone"))
	root.add_child(broken)
	root.add_child(_block(kit, "BlockBody", Vector3(2.8, 4.0, 4.4), Vector3(0, 2.0, 0)))
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(Vector3(3.0, 4.2, 4.6)), Vector3(0, 2.1, 0)))
	root.add_child(hb)
	return _merged(kit, root)


# --------------------------------------------------------------------------- the crew

## The siege crew: the soldier's body (P04's proportions) in a leather jerkin with a mallet, on the
## soldier's script, its merged rig and the LOD proxy.
static func build_crew(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "SiegeCrew"
	kit.scripted(root, S_SOLDIER, {"entity_id": "siege_crew_01"})
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
	root.add_child(kit.combat_entity("siege_crew_01", "enemy.siege_crew", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.15, 0)))
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
		"idle_arm_pose": Vector2(10, -55), "block_pose": Vector2(-30, 10)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0))
		hip.add_child(kit.box("Leg", Vector3(0.2, 0.82, 0.24), Vector3(0, -0.41, 0), "p32_jerkin"))
		hip.add_child(kit.box("Boot", Vector3(0.22, 0.12, 0.32), Vector3(0, -0.8, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 0.85, 0))
	torso.add_child(kit.box("Jerkin", Vector3(0.52, 0.64, 0.32), Vector3(0, 0.3, 0), "p32_jerkin"))
	torso.add_child(kit.box("Apron", Vector3(0.46, 0.4, 0.06), Vector3(0, 0.12, -0.17), "giant_belt"))
	torso.add_child(kit.box("Head", Vector3(0.24, 0.26, 0.26), Vector3(0, 0.78, 0), "soldier_skin"))
	torso.add_child(kit.box("Cap", Vector3(0.28, 0.1, 0.3), Vector3(0, 0.94, 0), "p32_jerkin"))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		shoulder.basis = SceneKit.arm_basis(10.0 * side, -55.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.13, 0.13, 0.3), Vector3(0, 0, -0.15), "p32_jerkin"))
		shoulder.add_child(kit.box("Forearm", Vector3(0.12, 0.12, 0.25), Vector3(0, 0, -0.42), "soldier_skin"))
		if side > 0:
			shoulder.add_child(kit.box("Haft", Vector3(0.05, 0.05, 0.7), Vector3(0, 0, -0.75), "p32_timber"))
			shoulder.add_child(kit.box("MalletHead", Vector3(0.2, 0.2, 0.3), Vector3(0, 0, -1.12), "p32_timber_dark"))
		body.add_child(shoulder)
	kit.merge_rig(body, {"ShoulderR": [["Weapon", ["Haft", "MalletHead"]]]})
	visual.add_child(kit.lod_proxy(Vector3(0.5, 1.8, 0.35), Vector3(0, 0.9, 0), "p32_jerkin"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- the cavalry

## The cavalry: a warhorse (body, neck and head, tail, four legs) with its rider and lance in the body.
static func build_cavalry(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Cavalry"
	kit.scripted(root, S_CAVALRY, {"entity_id": "cavalry_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.9
	cap.height = 2.6
	cs.shape = cap
	cs.position = Vector3(0, 1.3, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("cavalry_01", "enemy.cavalry", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.6, 0)))
	anchors.add_child(kit.marker("Grab", Vector3(0, 1.5, 0.1)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.3
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 2.0, -1.25)))
	hb.add_child(kit.hurtbox("Body", "torso", kit.box_shape(Vector3(0.9, 1.0, 2.3)), Vector3(0, 1.35, 0)))
	hb.add_child(kit.hurtbox("Rider", "torso", kit.box_shape(Vector3(0.55, 0.8, 0.45)), Vector3(0, 2.2, 0.1)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.8, 0.9, 1.9)), Vector3(0, 0.45, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_QUAD_RIG, {"body_path": NodePath("Body"), "head_path": NodePath("Body/Head"),
		"tail_path": NodePath("Body/Tail"), "leg_fl_path": NodePath("Body/LegFL"),
		"leg_fr_path": NodePath("Body/LegFR"), "leg_bl_path": NodePath("Body/LegBL"),
		"leg_br_path": NodePath("Body/LegBR"), "stride_length_m": 2.4, "leg_swing_rad": 0.55})
	var body := kit.n3("Body")
	visual.add_child(body)
	body.add_child(kit.box("Barrel", Vector3(0.8, 0.85, 2.1), Vector3(0, 1.35, 0.05), "p32_horse"))
	body.add_child(kit.box("Caparison", Vector3(0.86, 0.5, 1.6), Vector3(0, 1.2, 0.1), "p32_caparison"))
	body.add_child(kit.box("Saddle", Vector3(0.6, 0.18, 0.6), Vector3(0, 1.84, 0.1), "giant_belt"))
	# the rider and the lance, in the body (they ride with it)
	body.add_child(kit.box("RiderLegs", Vector3(0.95, 0.25, 0.3), Vector3(0, 1.85, 0.1), "soldier_mail"))
	body.add_child(kit.box("RiderTorso", Vector3(0.5, 0.65, 0.34), Vector3(0, 2.22, 0.12), "soldier_mail"))
	body.add_child(kit.box("RiderTabard", Vector3(0.52, 0.5, 0.36), Vector3(0, 2.15, 0.12), "p32_caparison"))
	body.add_child(kit.box("RiderHead", Vector3(0.24, 0.26, 0.26), Vector3(0, 2.66, 0.12), "soldier_skin"))
	body.add_child(kit.box("RiderHelm", Vector3(0.3, 0.16, 0.32), Vector3(0, 2.78, 0.12), "steel"))
	body.add_child(kit.box("Lance", Vector3(0.08, 0.08, 4.2), Vector3(0.38, 2.05, -1.0), "p32_lance"))
	body.add_child(kit.box("LanceTip", Vector3(0.12, 0.12, 0.4), Vector3(0.38, 2.05, -3.2), "steel"))
	body.add_child(kit.box("Shield", Vector3(0.08, 0.6, 0.45), Vector3(-0.36, 2.15, 0.15), "p32_caparison"))
	var head := kit.n3("Head", Vector3(0, 1.7, -0.95))
	var neck := kit.box("Neck", Vector3(0.4, 0.9, 0.45), Vector3(0, 0.3, -0.15), "p32_horse")
	neck.rotation_degrees = Vector3(-35, 0, 0)
	head.add_child(neck)
	head.add_child(kit.box("Skull", Vector3(0.32, 0.36, 0.7), Vector3(0, 0.62, -0.5), "p32_horse"))
	head.add_child(kit.box("Mane", Vector3(0.1, 0.7, 0.3), Vector3(0, 0.55, 0.05), "p32_mane"))
	head.add_child(kit.box("EarL", Vector3(0.06, 0.16, 0.06), Vector3(-0.1, 0.86, -0.32), "p32_mane"))
	head.add_child(kit.box("EarR", Vector3(0.06, 0.16, 0.06), Vector3(0.1, 0.86, -0.32), "p32_mane"))
	body.add_child(head)
	var tail := kit.n3("Tail", Vector3(0, 1.6, 1.1))
	var brush := kit.box("Brush", Vector3(0.14, 0.14, 0.7), Vector3(0, -0.2, 0.3), "p32_mane")
	brush.rotation_degrees = Vector3(40, 0, 0)
	tail.add_child(brush)
	body.add_child(tail)
	for leg_name: String in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var x := -0.26 if leg_name.ends_with("L") else 0.26
		var z := -0.75 if leg_name.begins_with("LegF") else 0.75
		var hip := kit.n3(leg_name, Vector3(x, 1.0, z))
		hip.add_child(kit.box("Leg", Vector3(0.18, 0.92, 0.2), Vector3(0, -0.46, 0), "p32_horse"))
		hip.add_child(kit.box("Hoof", Vector3(0.2, 0.1, 0.24), Vector3(0, -0.95, -0.02), "p32_mane"))
		body.add_child(hip)
	kit.merge_rig(body)
	visual.add_child(kit.lod_proxy(Vector3(0.9, 2.6, 2.4), Vector3(0, 1.3, 0), "p32_horse"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- the test level

static func build_test_level(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("siege: build the player scene first")
		return null
	var td: GDScript = load(TEST_DIRECTOR)
	var root := Node3D.new()
	root.name = "SiegeTestLevel"
	kit.scripted(root, S_LEVEL, {"level_id": LEVEL_ID})
	_add_environment(root)

	var world := kit.n3("World")
	for spec: Array in BOXES:
		var body := kit.static_box(spec[0], spec[1], spec[2], "stone")
		if spec[0] == "Floor":
			body.get_node("Mesh").free()
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var plane := PlaneMesh.new()
			plane.size = FLOOR
			mesh.mesh = plane
			mesh.material_override = kit.mats["ground"]
			mesh.position = Vector3(0, 0.5, 0)
			body.add_child(mesh)
		world.add_child(body)
	root.add_child(world)

	# Both navmeshes keep a 0.25 m cell height (as the heavy builder's): the waypoints lie about 0.5 m over
	# the floor, inside EnemyActor's path_desired_distance (0.6). A 0.5 m cell height put the large one
	# 1 m up, and a rider's agent never reached its first waypoint (it rocked on the spot): this level
	# has no nav_query settings, so NavQuery.level_waypoint does not level them.
	var nav := kit.n3("Navigation")
	for spec: Array in [["Human", NAV_HUMAN], ["Large", NAV_LARGE]]:
		var region := NavigationRegion3D.new()
		region.name = spec[0]
		region.navigation_layers = int((spec[1] as Dictionary).layers)
		region.navigation_mesh = td.call("bake_navmesh", spec[1], BOXES)
		nav.add_child(region)
	root.add_child(nav)

	var props := kit.n3("Props")
	for spec: Array in ENGINES:
		var engine: Node3D = kit.instance(str(spec[1]))
		if engine == null:
			continue
		engine.name = str(spec[0])
		engine.set("world_id", spec[2])
		engine.position = spec[3]
		engine.rotation_degrees = Vector3(0, float(spec[4]), 0)
		props.add_child(engine)
	root.add_child(props)

	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", START), S_CHECKPOINT,
		{"checkpoint_id": "test.siege.cp_start"}))
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
	for spec: Array in [["SignBattery", "BATTERY: 2 catapults, 2 ballistae, a shield wall (tests activate it)", Vector3(0, 6, -50)],
			["SignCavalry", "CAVALRY: a pair (tests activate it)", Vector3(110, 4, 0)],
			["SignStart", "SIEGE TEST LEVEL (F3: director state)", START + Vector3(0, 4.5, -4)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.47, 0.55, 0.66)
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
