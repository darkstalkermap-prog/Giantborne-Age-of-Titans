extends RefCounted
## Builder (P11a): the heavy enemies and the boss arena test level.
##   scenes/enemies/ogre.tscn          OgreEnemy (enemy.ogre): a 3.4 m brute in hide with a club;
##                                     Anchors/{Torso,KneeL,KneeR} (lock anchors) and Anchors/Grab
##                                     at the chest (two_hand, stage 3).
##   scenes/enemies/ogre_king.tscn     OgreBoss (enemy.ogre_king): the ogre's body plan at 8.5 m
##                                     with a crown, a mantle and the king's club;
##                                     Anchors/{Torso,KneeL,KneeR}; not grabbable (no Grab anchor).
##   scenes/test/boss_arena_test.tscn  the Valley's Kingsfall arena moved to the origin: a ring wall
##                                     (inner radius 40 m, 15 m high, open to the north), four
##                                     3 x 15 x 3 m pillars at 22 m, the 14 m antechamber, the
##                                     ArenaGate (open: hidden, collision off), the engage trigger
##                                     at the threshold, BossArena wired to them, the Ogre King,
##                                     the giant in the antechamber, and navigation baked here on
##                                     the giant (4) and human (1) layers.
## Both enemies share one body plan (`_ogre_body`, scaled: the king is the ogre x 2.5) with the
## ActorRig limbs, hurtboxes, NavAgent and Visual/LodProxy every enemy has. Gameplay numbers live in
## data/enemies/{ogre,ogre_king}.json; the record's weapon_pivot_m matches each shoulder here.
## Runs after the player builder (the test level instances giant.tscn).

const S_OGRE := "res://scripts/actors/ogre_enemy.gd"
const S_BOSS := "res://scripts/actors/ogre_boss.gd"
const S_ARENA := "res://scripts/world/boss_arena.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const OGRE_PATH := "res://scenes/enemies/ogre.tscn"
const KING_PATH := "res://scenes/enemies/ogre_king.tscn"
const TEST_PATH := "res://scenes/test/boss_arena_test.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const VALLEY_BUILDER := "res://tools/builders/valley.gd"

## The king is the ogre's body plan at this scale (8.5 m / 3.4 m).
const KING_SCALE := 2.5

## The boss arena test level (tests read these): the Valley arena with its centre at the origin
## (Valley (150, 135)), entrance to the north (-Z).
const INNER_RADIUS := 40.0
const WALL_RADIUS := 41.0          ## the ring's centre line (2 m thick: inner radius 40)
const WALL_T := 2.0
const WALL_H := 15.0
const WALL_SEGMENTS := 27
const ENTRANCE_HALF_WIDTH := 7.0
const PILLAR_RADIUS := 22.0
const PILLAR_SIZE := Vector3(3, 15, 3)
const PILLAR_ANGLES := [45.0, 135.0, 225.0, 315.0]
const GATE_POS := Vector3(0, 0, -40.4)
const GATE_SIZE := Vector3(14, 15, 2)
const ANTECHAMBER_Z := Vector2(-68.0, -40.4)   ## the antechamber runs between these z (x -7..7)
const ANTECHAMBER_RECT := Rect2(-7, -68, 14, 28)
const ENGAGE_POS := Vector3(0, 0, -37.2)
const ENGAGE_SIZE := Vector3(14, 16, 4)
const BOSS_POS := Vector3(0, 0.05, 15)
const BOSS_ID := "test.arena.ogre_king"
const ENGAGE_ID := "test.area.arena_engage"
const PLAYER_POS := Vector3(0, 0.05, -58)
const FLOOR_SIZE := Vector3(220, 1, 220)
const FLOOR_CENTER := Vector3(0, -0.5, -10)

## Navigation layers of the test level (plan §2.2; the Valley's agents).
const NAV := [
	{"layer": 4, "node": "Giant", "radius": 2.0, "height": 8.5, "climb": 0.75, "cell": 0.5},
	{"layer": 1, "node": "Human", "radius": 0.6, "height": 2.0, "climb": 0.25, "cell": 0.3},
]


static func build_all(kit: SceneKit) -> void:
	kit.add_material("ogre_skin", Color(0.46, 0.53, 0.33), 0.85)
	kit.add_material("ogre_hide", Color(0.42, 0.31, 0.20), 0.95)
	kit.add_material("ogre_tusk", Color(0.92, 0.88, 0.74), 0.6)
	kit.add_material("king_skin", Color(0.36, 0.44, 0.30), 0.85)
	kit.add_material("king_mantle", Color(0.46, 0.10, 0.13), 0.9)
	kit.add_material("king_gold", Color(0.86, 0.68, 0.22), 0.35, 0.6)
	kit.add_material("arena_iron", Color(0.22, 0.22, 0.25), 0.5, 0.5)
	kit.save(build_ogre(kit), OGRE_PATH)
	kit.save(build_king(kit), KING_PATH)
	var level := build_arena_test(kit)
	if level != null:
		kit.save(level, TEST_PATH)


# --------------------------------------------------------------------------- the body plan

## The shared ogre body at scale `s` (1 = the 3.4 m ogre): root CharacterBody3D (script, entity id,
## actor mask), BodyShape, CombatEntity, Anchors (Torso, KneeL, KneeR; Grab when `grab`), Hurtboxes,
## NavAgent and an ActorRig Visual with hips and legs, a belly and chest, a tusked head, shoulders
## with arms, a club in the weapon hand and Visual/LodProxy. Returns the parts by name.
static func _ogre_body(kit: SceneKit, node_name: String, script_path: String, entity_id: String,
		definition_id: String, s: float, radius: float, skin: String, hide_mat: String, grab: bool) -> Dictionary:
	var height := 3.4 * s
	var root := CharacterBody3D.new()
	root.name = node_name
	kit.scripted(root, script_path, {"entity_id": entity_id})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	cs.shape = cap
	cs.position = Vector3(0, height * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity(entity_id, definition_id, 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 2.2, 0) * s))
	anchors.add_child(kit.marker("KneeL", Vector3(-0.35, 0.9, -0.08) * s))
	anchors.add_child(kit.marker("KneeR", Vector3(0.35, 0.9, -0.08) * s))
	if grab:
		# P07: where both hands close round the chest (attachment profile two_hand).
		anchors.add_child(kit.marker("Grab", Vector3(0, 2.3, 0) * s))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.36 * s
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 3.08, -0.05) * s))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(1.55, 1.45, 1.1) * s), Vector3(0, 2.15, 0) * s))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(1.2, 1.4, 0.8) * s), Vector3(0, 0.7, 0) * s))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 1.5 * s, "leg_swing_rad": 0.45,
		"idle_arm_pose": Vector2(14, -74), "off_idle_pose": Vector2(-14, -76),
		"block_pose": Vector2(-30, 10)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.36 * side, 1.3, 0) * s)
		hip.add_child(kit.box("Leg", Vector3(0.5, 1.22, 0.55) * s, Vector3(0, -0.6, 0) * s, skin))
		hip.add_child(kit.box("Wrap", Vector3(0.56, 0.3, 0.6) * s, Vector3(0, -0.15, 0) * s, hide_mat))
		hip.add_child(kit.box("Foot", Vector3(0.58, 0.16, 0.8) * s, Vector3(0, -1.22, -0.12) * s, hide_mat))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 1.3, 0) * s)
	torso.add_child(kit.box("Belly", Vector3(1.5, 1.05, 1.15) * s, Vector3(0, 0.5, -0.04) * s, skin))
	torso.add_child(kit.box("Loincloth", Vector3(1.56, 0.45, 1.2) * s, Vector3(0, 0.12, 0) * s, hide_mat))
	torso.add_child(kit.box("Chest", Vector3(1.62, 0.62, 1.02) * s, Vector3(0, 1.28, 0.02) * s, skin))
	torso.add_child(kit.box("Head", Vector3(0.62, 0.56, 0.62) * s, Vector3(0, 1.8, -0.1) * s, skin))
	torso.add_child(kit.box("Brow", Vector3(0.66, 0.12, 0.2) * s, Vector3(0, 1.93, -0.36) * s, skin))
	torso.add_child(kit.box("EyeL", Vector3(0.08, 0.07, 0.04) * s, Vector3(-0.15, 1.86, -0.42) * s, "eyes"))
	torso.add_child(kit.box("EyeR", Vector3(0.08, 0.07, 0.04) * s, Vector3(0.15, 1.86, -0.42) * s, "eyes"))
	torso.add_child(kit.box("TuskL", Vector3(0.07, 0.2, 0.07) * s, Vector3(-0.18, 1.68, -0.42) * s, "ogre_tusk"))
	torso.add_child(kit.box("TuskR", Vector3(0.07, 0.2, 0.07) * s, Vector3(0.18, 1.68, -0.42) * s, "ogre_tusk"))
	body.add_child(torso)
	var shoulders: Array[Node3D] = []
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(0.88 * side, 2.62, 0) * s)
		shoulder.basis = SceneKit.arm_basis(14.0 * side, -74.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.36, 0.36, 0.58) * s, Vector3(0, 0, -0.29) * s, skin))
		shoulder.add_child(kit.box("Forearm", Vector3(0.34, 0.34, 0.52) * s, Vector3(0, 0, -0.82) * s, skin))
		shoulder.add_child(kit.box("Hand", Vector3(0.4, 0.4, 0.4) * s, Vector3(0, 0, -1.12) * s, skin))
		if side > 0:
			var club := kit.cyl("Club", 0.3 * s, 0.13 * s, 1.6 * s, Vector3(0, 0, -1.12 - 0.8) * s, "club")
			club.rotation_degrees = Vector3(-90, 0, 0)
			shoulder.add_child(club)
		body.add_child(shoulder)
		shoulders.append(shoulder)
	# AI LOD tier 2 shows this single box instead of the rig (EnemyActor.set_lod_tier).
	visual.add_child(kit.lod_proxy(Vector3(1.5, 3.4, 1.1) * s, Vector3(0, 1.7, 0) * s, skin))
	root.add_child(visual)
	return {"root": root, "torso": torso, "body": body, "left": shoulders[0], "right": shoulders[1]}


static func build_ogre(kit: SceneKit) -> Node:
	var parts := _ogre_body(kit, "Ogre", S_OGRE, "ogre_01", "enemy.ogre", 1.0, 0.9, "ogre_skin", "ogre_hide", true)
	var torso: Node3D = parts.torso
	torso.add_child(kit.box("Strap", Vector3(0.18, 1.2, 1.18), Vector3(0.3, 0.9, 0.0), "ogre_hide"))
	return parts.root


static func build_king(kit: SceneKit) -> Node:
	var s := KING_SCALE
	var parts := _ogre_body(kit, "OgreKing", S_BOSS, "ogre_king_01", "enemy.ogre_king", s, 2.0, "king_skin",
		"king_mantle", false)
	var torso: Node3D = parts.torso
	torso.add_child(kit.box("Mantle", Vector3(1.78, 0.34, 1.2) * s, Vector3(0, 1.52, 0.06) * s, "king_mantle"))
	torso.add_child(kit.box("Cape", Vector3(1.5, 1.4, 0.12) * s, Vector3(0, 0.85, 0.6) * s, "king_mantle"))
	torso.add_child(kit.box("Belt", Vector3(1.6, 0.16, 1.22) * s, Vector3(0, 0.3, 0) * s, "king_gold"))
	torso.add_child(kit.box("CrownBand", Vector3(0.7, 0.14, 0.7) * s, Vector3(0, 2.13, -0.1) * s, "king_gold"))
	for i in 4:
		var x := (-0.27 + 0.18 * i) * s
		torso.add_child(kit.box("CrownSpike%d" % (i + 1), Vector3(0.1, 0.22, 0.1) * s, Vector3(x, 2.3, -0.42) * s,
			"king_gold"))
	var hand: Node3D = parts.right
	hand.add_child(kit.box("ClubBand", Vector3(0.66, 0.66, 0.2) * s, Vector3(0, 0, -2.4) * s, "king_gold"))
	return parts.root


# --------------------------------------------------------------------------- the boss arena test level

static func build_arena_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var king: Node3D = kit.instance(KING_PATH)
	if player == null or king == null:
		push_error("heavy: build the player scene first")
		for n: Node in [player, king]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "BossArenaTest"
	_add_environment(root)

	var solids := arena_solids()
	var geometry := kit.n3("Geometry")
	for sd: Dictionary in solids:
		if str(sd.nav) == "pillar":
			continue   # Pillars/Pillar1..4 below
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
			plane.size = Vector2(FLOOR_SIZE.x, FLOOR_SIZE.z)
			mesh.mesh = plane
			mesh.position = Vector3(0, FLOOR_SIZE.y * 0.5, 0)
			mesh.material_override = kit.mats["ground"]
			body.add_child(mesh)
		else:
			body.add_child(kit.box("Mesh", sd.size, Vector3.ZERO, str(sd.mat)))
		geometry.add_child(body)
	root.add_child(geometry)

	var nav := kit.n3("Navigation")
	for spec: Dictionary in NAV:
		var region := NavigationRegion3D.new()
		region.name = str(spec.node)
		region.navigation_layers = int(spec.layer)
		region.use_edge_connections = false
		region.navigation_mesh = bake_layer(spec, solids)
		nav.add_child(region)
	root.add_child(nav)

	var gate := StaticBody3D.new()
	gate.name = "ArenaGate"
	gate.position = GATE_POS
	gate.collision_layer = SceneKit.L_WORLD
	gate.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.name = "Shape"
	gcs.shape = kit.box_shape(GATE_SIZE)
	gcs.position = Vector3(0, GATE_SIZE.y * 0.5, 0)
	gcs.disabled = true
	gate.add_child(gcs)
	var bars := kit.n3("Bars")
	for i in 8:
		var x := -GATE_SIZE.x * 0.5 + 0.6 + (GATE_SIZE.x - 1.2) * float(i) / 7.0
		bars.add_child(kit.box("Bar%d" % i, Vector3(0.35, GATE_SIZE.y, 0.35), Vector3(x, GATE_SIZE.y * 0.5, 0), "arena_iron"))
	for j in 3:
		bars.add_child(kit.box("Cross%d" % j, Vector3(GATE_SIZE.x, 0.3, 0.45), Vector3(0, 2.5 + 5.0 * j, 0), "arena_iron"))
	gate.add_child(bars)
	gate.visible = false
	root.add_child(gate)

	var pillars := kit.n3("Pillars")
	for i in PILLAR_ANGLES.size():
		var ang := deg_to_rad(float(PILLAR_ANGLES[i]))
		var pos := Vector3(cos(ang), 0, sin(ang)) * PILLAR_RADIUS
		pillars.add_child(kit.static_box("Pillar%d" % (i + 1), PILLAR_SIZE, pos + Vector3.UP * PILLAR_SIZE.y * 0.5,
			"stone"))
	root.add_child(pillars)

	var triggers := kit.n3("Triggers")
	var trig := Area3D.new()
	trig.name = ENGAGE_ID.validate_node_name()
	trig.position = ENGAGE_POS
	kit.scripted(trig, S_TRIGGER, {"area_id": ENGAGE_ID, "once": false})
	trig.collision_layer = 0
	trig.collision_mask = SceneKit.L_ACTORS
	trig.monitoring = true
	trig.monitorable = false
	var tcs := CollisionShape3D.new()
	tcs.name = "Shape"
	tcs.shape = kit.box_shape(ENGAGE_SIZE)
	tcs.position = Vector3(0, ENGAGE_SIZE.y * 0.5, 0)
	trig.add_child(tcs)
	triggers.add_child(trig)
	root.add_child(triggers)

	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_ARENA, {"boss_id": BOSS_ID, "encounter_id": "", "engage_area_id": ENGAGE_ID,
		"gate_path": NodePath("../ArenaGate"), "pillars_path": NodePath("../Pillars"),
		"inner_radius_m": INNER_RADIUS, "antechamber_rect": ANTECHAMBER_RECT})
	root.add_child(arena)

	king.name = "OgreKing"
	king.set("entity_id", BOSS_ID)
	king.position = BOSS_POS
	root.add_child(king)

	var spawns := kit.n3("Spawns")
	var spawn := kit.marker("PlayerSpawn", PLAYER_POS)
	spawn.rotation.y = PI
	spawns.add_child(spawn)
	root.add_child(spawns)
	player.name = "Player"
	player.position = PLAYER_POS
	player.rotation.y = PI
	root.add_child(player)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignArena", "BOSS ARENA TEST: walk south through the gate", PLAYER_POS + Vector3(0, 5.0, 5)],
			["SignGate", "ARENA GATE (closes behind you)", GATE_POS + Vector3(0, 16.0, -1)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		sign.visibility_range_end = 80.0
		signs.add_child(sign)
	root.add_child(signs)
	return root


## Every solid of the test arena: {name, shape "box", xform, size, mat, nav "ground"|"obstacle"}:
## the floor, the ring's wall segments, the antechamber's two walls and the four pillars (the
## pillars are also built as Pillars/Pillar1..4; here they are only navigation obstacles).
static func arena_solids() -> Array:
	var out: Array = []
	out.append({"name": "Floor", "shape": "box", "xform": Transform3D(Basis(), FLOOR_CENTER), "size": FLOOR_SIZE,
		"mat": "stone", "nav": "ground"})
	var gap := asin(ENTRANCE_HALF_WIDTH / WALL_RADIUS)
	var start := -PI * 0.5 + gap
	var span := TAU - 2.0 * gap
	for i in WALL_SEGMENTS:
		var a0 := start + span * float(i) / WALL_SEGMENTS
		var a1 := start + span * float(i + 1) / WALL_SEGMENTS
		var p0 := Vector3(cos(a0), 0, sin(a0)) * WALL_RADIUS
		var p1 := Vector3(cos(a1), 0, sin(a1)) * WALL_RADIUS
		var dir := (p1 - p0).normalized()
		p0 -= dir * WALL_T * 0.5
		p1 += dir * WALL_T * 0.5
		var basis := Basis(Vector3.UP, TargetingRules.yaw_of(p1 - p0))
		out.append({"name": "Wall%02d" % i, "shape": "box",
			"xform": Transform3D(basis, (p0 + p1) * 0.5 + Vector3.UP * WALL_H * 0.5),
			"size": Vector3(WALL_T, WALL_H, p0.distance_to(p1)), "mat": "stone_dark", "nav": "obstacle"})
	var length := ANTECHAMBER_Z.y - ANTECHAMBER_Z.x
	for side: float in [-1.0, 1.0]:
		var x := side * (ENTRANCE_HALF_WIDTH + WALL_T * 0.5)
		out.append({"name": "Antechamber%s" % ("W" if side < 0.0 else "E"), "shape": "box",
			"xform": Transform3D(Basis(), Vector3(x, WALL_H * 0.5, (ANTECHAMBER_Z.x + ANTECHAMBER_Z.y) * 0.5)),
			"size": Vector3(WALL_T, WALL_H, length), "mat": "stone_dark", "nav": "obstacle"})
	for i in PILLAR_ANGLES.size():
		var ang := deg_to_rad(float(PILLAR_ANGLES[i]))
		var pos := Vector3(cos(ang), 0, sin(ang)) * PILLAR_RADIUS
		out.append({"name": "PillarNav%d" % (i + 1), "shape": "box",
			"xform": Transform3D(Basis(), pos + Vector3.UP * PILLAR_SIZE.y * 0.5), "size": PILLAR_SIZE,
			"mat": "stone", "nav": "pillar"})
	return out


## Bakes one navigation layer offline from the arena's solids (the Valley builder's face and
## footprint helpers): the floor walkable, everything else an obstacle without a top face plus a
## projected obstruction over its footprint (no islands inside walls or on pillars).
static func bake_layer(spec: Dictionary, solids: Array) -> NavigationMesh:
	var vb: GDScript = load(VALLEY_BUILDER)
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
	NavigationServer3D.bake_from_source_geometry_data(nm, src)
	return nm


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.50, 0.56, 0.66)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.68)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	root.add_child(sun)
