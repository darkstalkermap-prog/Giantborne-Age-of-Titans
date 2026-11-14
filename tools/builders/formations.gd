extends RefCounted
## Builder: the formation soldiers and their test level (P30, plan M6-M9 §2.10, decision 19).
##
##   * scenes/enemies/pikeman.tscn, shieldman.tscn, bannerman.tscn: the soldier's body (P04's
##     proportions, P22's merged rig: one vertex-coloured mesh per pivot, one material) with a
##     role's gear - a 4.2 m pike lying along the weapon arm, a tower shield on the off arm, or a
##     7 m banner pole on the back with a 2.5 x 1.8 m flag on Visual/Body/FlagPivot/Flag (the crowd
##     renderer sways the pivot and paints the flag in the formation's colour; render layer 1);
##   * Visual/CrowdPoses/{hold,brace,advance,flee} on the pikeman and the shieldman: the whole
##     body merged into one mesh per pose (hidden: the CrowdRenderer draws them as MultiMesh
##     instances, one draw call per pose for a formation's rank and file). The meshes carry the rig
##     material on their surface (no material_override), so ActorRig never copies them. The brace
##     arms are EnemyActor.BRACE_POSES, the ones a promoted member's rig takes;
##   * scenes/test/formation_test.tscn: a walled 440 x 160 m floor (level.formation_test, records in
##     data/test/) with a wall at z = -40 with a 6 m gate in its middle, three flee markers north of
##     it, the human navmesh baked offline (TestDirector.bake_navmesh), the checkpoint, the player,
##     the EncounterDirector and a StressScenario (the --stress-formations bot). Its encounters
##     (pikes and a shield wall in the west, the rout at the gate, the 40-member stress case in the
##     east) wait for a flag nobody sets: tests and the stress scenario activate them.
## Runs after the player builder (BUILDERS order in tools/build_scenes.gd).

const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const SHIELDMAN := "res://scenes/enemies/shieldman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const TEST_LEVEL := "res://scenes/test/formation_test.tscn"
const TEST_DIRECTOR := "res://tools/builders/test_director.gd"

const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const S_STRESS := "res://scripts/debug/stress_scenario.gd"
const GIANT := "res://scenes/player/giant.tscn"

const POSES := ["hold", "brace", "advance", "flee"]

## Colours of the gear (only baked into vertex colours: no material file is written for them).
const COLORS := {
	"p30_pike_tabard": Color(0.18, 0.30, 0.62),
	"p30_shield_tabard": Color(0.62, 0.48, 0.14),
	"p30_banner_tabard": Color(0.45, 0.12, 0.40),
	"p30_shaft": Color(0.46, 0.32, 0.18),
	"p30_shield_face": Color(0.52, 0.36, 0.20),
	"p30_shield_rim": Color(0.40, 0.40, 0.44),
	"p30_flag": Color(0.62, 0.12, 0.10),
}

## Per role: tabard colour, the rig's arm poses (yaw, pitch degrees) and the crowd poses: the
## weapon and off arms, the hips' swing (radians, + = leg forward), the torso's lean (- = forward)
## and the body's drop.
const ROLES := {
	"pike": {"name": "Pikeman", "entity": "pikeman_01", "definition": "enemy.pikeman", "tabard": "p30_pike_tabard",
		"idle": Vector2(12.0, 62.0), "off_idle": Vector2(-20.0, 25.0),
		"block": Vector2(0.0, -6.0), "off_block": Vector2(-14.0, -18.0)},
	"shield": {"name": "Shieldman", "entity": "shieldman_01", "definition": "enemy.shieldman", "tabard": "p30_shield_tabard",
		"idle": Vector2(15.0, -70.0), "off_idle": Vector2(-18.0, -12.0),
		"block": Vector2(20.0, -40.0), "off_block": Vector2(4.0, 6.0)},
	"banner": {"name": "Bannerman", "entity": "bannerman_01", "definition": "enemy.bannerman", "tabard": "p30_banner_tabard",
		"idle": Vector2(15.0, -70.0), "off_idle": Vector2(-10.0, -80.0),
		"block": Vector2(-30.0, 10.0), "off_block": Vector2(30.0, 8.0)},
}

## The test level (see the class notes).
const LEVEL_ID := "level.formation_test"
const FLOOR := Vector2(440.0, 160.0)
const START := Vector3(0.0, 0.05, 50.0)
const GATE_Z := -40.0
const GATE_HALF_M := 3.0
const GATE_WALL_HALF_M := 60.0
const BOXES := [
	["Floor", Vector3(440, 1, 160), Vector3(0, -0.5, 0), true],
	["WallNorth", Vector3(444, 4, 2), Vector3(0, 2, -81), false],
	["WallSouth", Vector3(444, 4, 2), Vector3(0, 2, 81), false],
	["WallEast", Vector3(2, 4, 164), Vector3(221, 2, 0), false],
	["WallWest", Vector3(2, 4, 164), Vector3(-221, 2, 0), false],
	# the gate wall: 57 m either side of a 6 m gap at x = 0
	["GateWallWest", Vector3(57, 5, 2), Vector3(-31.5, 2.5, -40), false],
	["GateWallEast", Vector3(57, 5, 2), Vector3(31.5, 2.5, -40), false],
]
## [marker id, position]: where routed members of the gate formation run (LevelMarker SAFE).
const FLEE_MARKERS := [
	["test.formation.flee_1", Vector3(-8, 0, -66)],
	["test.formation.flee_2", Vector3(0, 0, -72)],
	["test.formation.flee_3", Vector3(8, 0, -66)],
]
const NAV_HUMAN := {"layers": 1, "radius": 0.6, "height": 2.0, "cell": 0.3, "cell_height": 0.25,
	"climb": 0.25, "slope": 35.0}


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			kit.mats[c] = m
	kit.save(build_member(kit, "pike"), PIKEMAN)
	kit.save(build_member(kit, "shield"), SHIELDMAN)
	kit.save(build_member(kit, "banner"), BANNERMAN)
	var level := build_test_level(kit)
	if level != null:
		kit.save(level, TEST_LEVEL)


# --------------------------------------------------------------------------- members

## One formation soldier of `role` (pike, shield, banner): the soldier's body and collision with the
## role's gear, its merged rig, the LOD proxy and (pike, shield) the crowd poses.
static func build_member(kit: SceneKit, role: String) -> Node:
	var spec: Dictionary = ROLES[role]
	var root := CharacterBody3D.new()
	root.name = str(spec.name)
	kit.scripted(root, S_SOLDIER, {"entity_id": spec.entity})
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
	root.add_child(kit.combat_entity(str(spec.entity), str(spec.definition), 2))
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
		"idle_arm_pose": spec.idle, "off_idle_pose": spec.off_idle, "block_pose": spec.block,
		"off_block_pose": spec.off_block})
	var body := kit.n3("Body")
	visual.add_child(body)
	_add_body(kit, body, str(spec.tabard))
	var groups := {}
	match role:
		"pike":
			_add_pike(kit, body.get_node("ShoulderR") as Node3D)
			groups = {"ShoulderR": [["Weapon", ["PikeShaft", "PikeHead", "PikeGrip"]]]}
		"shield":
			_add_sword(kit, body.get_node("ShoulderR") as Node3D)
			_add_shield(kit, body.get_node("ShoulderL") as Node3D)
			groups = {"ShoulderR": [["Weapon", ["Grip", "Guard", "Blade"]]],
				"ShoulderL": [["Shield", ["ShieldFace", "ShieldRim", "ShieldBoss"]]]}
		"banner":
			_add_sword(kit, body.get_node("ShoulderR") as Node3D)
			_add_banner_pole(kit, body)
			groups = {"ShoulderR": [["Weapon", ["Grip", "Guard", "Blade"]]], "FlagPivot": [["Flag", ["Flag"]]]}
	if role != "banner":
		visual.add_child(crowd_poses(kit, body, role))
	kit.merge_rig(body, groups)
	visual.add_child(kit.lod_proxy(Vector3(0.5, 1.8, 0.35), Vector3(0, 0.9, 0), str(spec.tabard)))
	root.add_child(visual)
	return root


## The soldier's body (P04's soldier: legs, mailed torso with a tabard, helmeted head, two arms)
## under `body`, unmerged.
static func _add_body(kit: SceneKit, body: Node3D, tabard: String) -> void:
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.12 * side, 0.85, 0))
		hip.add_child(kit.box("Leg", Vector3(0.2, 0.82, 0.24), Vector3(0, -0.41, 0), "soldier_mail"))
		hip.add_child(kit.box("Boot", Vector3(0.22, 0.12, 0.32), Vector3(0, -0.8, -0.04), "giant_belt"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 0.85, 0))
	torso.add_child(kit.box("Mail", Vector3(0.5, 0.62, 0.3), Vector3(0, 0.31, 0), "soldier_mail"))
	torso.add_child(kit.box("Tabard", Vector3(0.52, 0.66, 0.32), Vector3(0, 0.28, 0), tabard))
	torso.add_child(kit.box("Head", Vector3(0.24, 0.26, 0.26), Vector3(0, 0.78, 0), "soldier_skin"))
	torso.add_child(kit.box("Helmet", Vector3(0.3, 0.16, 0.32), Vector3(0, 0.92, 0), "steel"))
	torso.add_child(kit.box("Nasal", Vector3(0.04, 0.16, 0.04), Vector3(0, 0.8, -0.15), "steel"))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.25 * side, 1.42, 0))
		shoulder.basis = SceneKit.arm_basis(15.0 * side, -70.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.13, 0.13, 0.3), Vector3(0, 0, -0.15), "soldier_mail"))
		shoulder.add_child(kit.box("Forearm", Vector3(0.12, 0.12, 0.25), Vector3(0, 0, -0.42), "soldier_skin"))
		body.add_child(shoulder)


## A 4.2 m pike along the weapon arm: from 0.7 m behind the shoulder to 3.5 m in front of it.
static func _add_pike(kit: SceneKit, arm: Node3D) -> void:
	arm.add_child(kit.box("PikeGrip", Vector3(0.07, 0.07, 0.16), Vector3(0, 0, -0.5), "giant_belt"))
	arm.add_child(kit.box("PikeShaft", Vector3(0.06, 0.06, 4.2), Vector3(0, 0, -1.4), "p30_shaft"))
	arm.add_child(kit.box("PikeHead", Vector3(0.09, 0.04, 0.32), Vector3(0, 0, -3.66), "steel"))


## The soldier's sword in the weapon hand.
static func _add_sword(kit: SceneKit, arm: Node3D) -> void:
	arm.add_child(kit.box("Grip", Vector3(0.05, 0.05, 0.14), Vector3(0, 0, -0.5), "giant_belt"))
	arm.add_child(kit.box("Guard", Vector3(0.22, 0.04, 0.05), Vector3(0, 0, -0.56), "steel"))
	arm.add_child(kit.box("Blade", Vector3(0.07, 0.02, 0.75), Vector3(0, 0, -0.5 - 0.375), "steel"))


## A tower shield on the off forearm, its face across the arm (it faces forward with the arm raised).
static func _add_shield(kit: SceneKit, arm: Node3D) -> void:
	arm.add_child(kit.box("ShieldFace", Vector3(0.62, 1.05, 0.06), Vector3(0.05, 0.12, -0.5), "p30_shield_face"))
	arm.add_child(kit.box("ShieldRim", Vector3(0.68, 1.11, 0.03), Vector3(0.05, 0.12, -0.47), "p30_shield_rim"))
	arm.add_child(kit.box("ShieldBoss", Vector3(0.16, 0.16, 0.06), Vector3(0.05, 0.12, -0.55), "steel"))


## The banner: a 7 m pole on the back (a mesh of Body) and the 2.5 x 1.8 m flag on its own pivot
## at the top, Body/FlagPivot/Flag (decision 19: visible, on render layer 1).
static func _add_banner_pole(kit: SceneKit, body: Node3D) -> void:
	body.add_child(kit.box("Pole", Vector3(0.08, 7.0, 0.08), Vector3(0, 3.5, 0.24), "p30_shaft"))
	body.add_child(kit.box("PoleTip", Vector3(0.14, 0.2, 0.14), Vector3(0, 7.08, 0.24), "steel"))
	var pivot := kit.n3("FlagPivot", Vector3(0, 6.9, 0.24))
	pivot.add_child(kit.box("Flag", Vector3(2.5, 1.8, 0.04), Vector3(1.29, -0.9, 0), "p30_flag"))
	body.add_child(pivot)


# --------------------------------------------------------------------------- crowd poses

## The pose table of `role` (see ROLES): pose -> {"arm", "off", "hips": [left, right], "lean",
## "drop"}. The brace arms are EnemyActor.BRACE_POSES (what a promoted, braced member shows).
static func pose_table(role: String) -> Dictionary:
	var spec: Dictionary = ROLES[role]
	var brace: Array = EnemyActor.BRACE_POSES.get(role, EnemyActor.BRACE_POSES["line"])
	return {
		"hold": {"arm": spec.idle, "off": spec.off_idle, "hips": [0.0, 0.0], "lean": 0.0, "drop": 0.0},
		"brace": {"arm": brace[0], "off": brace[1], "hips": [0.32, -0.22], "lean": -0.14, "drop": 0.07},
		"advance": {"arm": spec.block, "off": spec.off_block, "hips": [0.42, -0.42], "lean": -0.05, "drop": 0.0},
		"flee": {"arm": Vector2(35.0, -55.0), "off": Vector2(-30.0, 30.0), "hips": [0.6, -0.6], "lean": -0.35, "drop": 0.03},
	}


## Visual/CrowdPoses: one hidden MeshInstance3D per pose, the whole (unmerged) `body` posed and
## merged into one vertex-coloured mesh in the actor's space, the rig material on its surface.
static func crowd_poses(kit: SceneKit, body: Node3D, role: String) -> Node3D:
	var holder := kit.n3("CrowdPoses")
	holder.visible = false
	var table := pose_table(role)
	for pose: String in POSES:
		var mi := MeshInstance3D.new()
		mi.name = pose
		mi.mesh = pose_mesh(kit, body, table[pose])
		holder.add_child(mi)
	return holder


## One mesh of `body` in `pose` (see pose_table): every visible part of Body's pivots and of Body
## itself, each pivot posed (shoulders by arm pose, hips by swing, the torso by lean, the body by
## drop), baked into vertices with its colour.
static func pose_mesh(kit: SceneKit, body: Node3D, pose: Dictionary) -> ArrayMesh:
	var body_xf := Transform3D(Basis.IDENTITY, body.position + Vector3(0.0, -float(pose.get("drop", 0.0)), 0.0))
	var temps: Array[MeshInstance3D] = []
	for child in body.get_children():
		if child is MeshInstance3D:
			temps.append(_baked_part(child as MeshInstance3D, body_xf * (child as MeshInstance3D).transform))
		elif child.get_class() == "Node3D":
			var pivot_xf := _posed_pivot(child as Node3D, pose)
			for part in child.get_children():
				var mi := part as MeshInstance3D
				if mi != null and mi.visible:
					temps.append(_baked_part(mi, body_xf * pivot_xf * mi.transform))
	var mesh := SceneKit.vertex_colored_mesh(temps)
	mesh.surface_set_material(0, kit.rig_material())
	for t in temps:
		t.free()
	return mesh


static func _baked_part(part: MeshInstance3D, xf: Transform3D) -> MeshInstance3D:
	var t := MeshInstance3D.new()
	t.mesh = part.mesh
	t.material_override = part.material_override
	t.transform = xf
	return t


static func _posed_pivot(pivot: Node3D, pose: Dictionary) -> Transform3D:
	var hips: Array = pose.get("hips", [0.0, 0.0])
	match String(pivot.name):
		"ShoulderR":
			var a: Vector2 = pose.arm
			return Transform3D(SceneKit.arm_basis(a.x, a.y), pivot.position)
		"ShoulderL":
			var o: Vector2 = pose.off
			return Transform3D(SceneKit.arm_basis(o.x, o.y), pivot.position)
		"HipL":
			return Transform3D(Basis(Vector3.RIGHT, float(hips[0])), pivot.position)
		"HipR":
			return Transform3D(Basis(Vector3.RIGHT, float(hips[1])), pivot.position)
		"Torso":
			return Transform3D(Basis(Vector3.RIGHT, float(pose.get("lean", 0.0))), pivot.position)
	return pivot.transform


# --------------------------------------------------------------------------- the test level

static func build_test_level(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("formations: build the player scene first")
		return null
	var td: GDScript = load(TEST_DIRECTOR)
	var root := Node3D.new()
	root.name = "FormationTestLevel"
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

	var nav := kit.n3("Navigation")
	var human := NavigationRegion3D.new()
	human.name = "Human"
	human.navigation_layers = int(NAV_HUMAN.layers)
	human.navigation_mesh = td.call("bake_navmesh", NAV_HUMAN, BOXES)
	nav.add_child(human)
	root.add_child(nav)

	var markers := kit.n3("Markers")
	var safe := kit.n3("Safe")
	for spec: Array in FLEE_MARKERS:
		safe.add_child(kit.scripted(kit.marker(str(spec[0]).validate_node_name(), spec[1]), S_MARKER,
			{"marker_id": spec[0], "kind": 4, "faction": ""}))
	markers.add_child(safe)
	root.add_child(markers)

	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", START), S_CHECKPOINT,
		{"checkpoint_id": "test.formation.cp_start"}))
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
	# the formation stress case's bot (--scenario=stress --stress-formations; idle otherwise)
	var stress := Node.new()
	stress.name = "StressScenario"
	kit.scripted(stress, S_STRESS)
	root.add_child(stress)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignPikes", "PIKES and SHIELD WALL (tests activate them)", Vector3(-172, 4, 12)],
			["SignGate", "THE GATE: routs fan out beyond it", Vector3(0, 6, -36)],
			["SignStress", "STRESS: 40 members (--stress-formations)", Vector3(160, 4, 14)],
			["SignStart", "FORMATION TEST LEVEL (F3: director state)", START + Vector3(0, 4.5, -4)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


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
