extends RefCounted
## Builder (E2; after e1_titans.gd in build_scenes' BUILDERS): the Cinder Titan.
##   scenes/enemies/cinder.tscn   CinderEnemy (enemy.cinder): the Cinder Titan, 41.0 m - the Stormcaller's hurtboxes,
##                                lock anchors and kneel (titans.gd's, from the creatures' manifest) carried up by
##                                CinderModel.SCALE, his capsule; his rig (CinderRig: CinderModel, his fire).
##   scenes/test/cinder_test.tscn the burnt hollow test arena (TitanArenaTest; --titan-stage=N): a ring of scorched
##                                ground 110 m round with charred stones at its edge, the stream (the Ashbeck: water 3 m
##                                deep in a winding channel across the middle - it cools a giant and quenches him) and
##                                the dammed water west of it (6.5 m deep; there only with test.cinder.dammed set), the
##                                titan north of the stream, the giant south, the BossArena and the titan navmesh.

const BB := preload("res://tools/builders/big.gd")
const T := preload("res://tools/builders/titans.gd")

const S_CINDER := "res://scripts/actors/cinder_enemy.gd"
const S_CINDER_RIG := "res://scripts/presentation/cinder_rig.gd"
const CINDER := "res://scenes/enemies/cinder.tscn"
const CINDER_TEST := "res://scenes/test/cinder_test.tscn"

const COLORS := {"e2_char": Color(0.17, 0.155, 0.145), "e2_ash": Color(0.33, 0.315, 0.3), "e2_rock": Color(0.27, 0.25, 0.235)}

## His size over the Stormcaller's (whose body he is).
const K := 41.0 / 34.0
const RADIUS := 6.3
const HEIGHT := 41.0
## The plates' hurtboxes: [node, region, the Stormcaller's piece the box is taken from, anchor, the share of the
## piece's extent] (the Stormcaller's, the lodestone his heart-coal).
const PLATES := [["Head", "head", "crown", "PlateCrown", 0.8],
	["ShoulderL", "shoulder_l", "pauldron_l", "PlateShoulderL", 0.85],
	["ShoulderR", "shoulder_r", "pauldron_r", "PlateShoulderR", 0.85],
	["Chest", "chest", "lodestone", "PlateHeart", 0.9],
	["BracerR", "forearm_r", "bracer", "PlateBracer", 0.95],
	["ShinL", "shin_l", "greave_l", "PlateShinL", 0.95], ["ShinR", "shin_r", "greave_r", "PlateShinR", 0.95]]
## His back (no plate: the slag spines; armour only) in the Stormcaller's actor space.
const BACK_BOX := [Vector3(0.0, 24.0, 2.6), Vector3(6.4, 8.0, 3.0)]
const KNEEL_FOLLOW := {
	"Head": "head", "PlateCrown": "head", "ShoulderL": "upperarm_l", "PlateShoulderL": "upperarm_l",
	"ShoulderR": "upperarm_r", "PlateShoulderR": "upperarm_r", "Back": "spine_03",
	"Chest": "spine_03", "PlateHeart": "spine_03", "BracerR": "lowerarm_r", "PlateBracer": "lowerarm_r",
	"ArmL": "upperarm_l", "Torso": "spine_02", "Legs": "pelvis", "ShinL": "calf_l", "ShinR": "calf_r",
	"PlateShinL": "calf_l", "PlateShinR": "calf_r", "KneeL": "calf_l", "KneeR": "calf_r",
}

## The burnt hollow test arena.
const CINDER_ID := "test.hollow.cinder"
const ENGAGE_ID := "test.area.hollow_engage"
const ARENA_RADIUS := 110.0
const PLAYER_AT := Vector3(0, 0.05, 70)
const TITAN_AT := Vector3(0, 0.05, -40)
## The Ashbeck: [cx, cz, rx, rz, depth] ellipses along a winding channel west to east, south of the titan; the dammed
## water west of it (shown with DAMMED_FLAG).
const STREAM := [[-96.0, 8.0, 20.0, 10.0, 3.0], [-66.0, 2.0, 20.0, 11.0, 3.0], [-36.0, 6.0, 20.0, 11.0, 3.2],
	[-6.0, 14.0, 20.0, 11.0, 3.0], [24.0, 16.0, 20.0, 11.0, 3.0], [54.0, 10.0, 20.0, 11.0, 3.2],
	[84.0, 4.0, 22.0, 11.0, 3.0]]
const DAM_POOL := [[-62.0, -46.0, 30.0, 24.0, 6.5]]
const DAMMED_FLAG := "test.cinder.dammed"
const STONES := [
	["StoneNorth", Vector3(9, 20, 7), Vector3(-26, 0, -98), 20.0],
	["StoneWest", Vector3(8, 15, 8), Vector3(-100, 0, -34), -15.0],
	["StoneEast", Vector3(9, 18, 7), Vector3(98, 0, -30), 35.0],
	["StoneSouth", Vector3(8, 12, 8), Vector3(74, 0, 74), 10.0],
]


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.95
			kit.mats[c] = m
	kit.save(build_cinder(kit), CINDER)
	var level := build_cinder_test(kit)
	if level != null:
		kit.save(level, CINDER_TEST)


static func _k(v: Vector3) -> Vector3:
	return T._snapv(v * K)


## A node's kneeling position at his size (the Stormcaller's kneel, carried up by K).
static func _follow(n: Node3D, bones: Dictionary) -> void:
	var bone := str(KNEEL_FOLLOW.get(str(n.name), ""))
	if bone == "" or not bones.has(bone):
		return
	var p := T.kneel_position(n.position / K, bones[bone]) * K
	n.set_meta("kneel_position", Vector3(snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)))


static func build_cinder(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Cinder"
	kit.scripted(root, S_CINDER, {"entity_id": "cinder_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = RADIUS
	cap.height = HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, HEIGHT * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("cinder_01", "enemy.cinder", 2))
	var bones := T.kneel_bones("stormcaller")
	var pieces := T.idle_pieces("stormcaller")
	var anchors := kit.n3("Anchors")
	for a: Array in T.STORMCALLER_ANCHORS:
		var m: Node3D = kit.marker(str(a[0]), _k(a[1]))
		_follow(m, bones)
		anchors.add_child(m)
	var hb := kit.n3("Hurtboxes")
	for spec: Array in PLATES:
		var ip: Dictionary = pieces.get(str(spec[2]), {})
		var c := T._vec(ip.get("centre", [0, 17, 0]))
		var size := T._vec(ip.get("size", [2, 2, 2])) * float(spec[4])
		if str(spec[2]) == "crown":
			# (the horns stand off his head: the box is his head and the horns' roots)
			size = Vector3(maxf(size.x, 4.6), maxf(size.y, 4.0), maxf(size.z, 4.0))
		var box: Node3D = kit.hurtbox(str(spec[0]), str(spec[1]), kit.box_shape(_k(size)), _k(c))
		_follow(box, bones)
		hb.add_child(box)
		var out := Vector3(c.x, 0.0, c.z)
		if str(spec[1]).begins_with("shin") or str(spec[1]) == "chest":
			out = Vector3(0, 0, -1)
		out = out.normalized() if out.length() > 0.2 else Vector3.FORWARD
		var at := c + out * (minf(size.x, size.z) * 0.45)
		var m: Node3D = kit.marker(str(spec[3]), _k(at))
		_follow(m, bones)
		anchors.add_child(m)
	var back: Node3D = kit.hurtbox("Back", "back", kit.box_shape(_k(BACK_BOX[1])), _k(BACK_BOX[0]))
	_follow(back, bones)
	hb.add_child(back)
	for h: Array in T.STORMCALLER_BODY:
		var b: Node3D = kit.hurtbox(str(h[0]), str(h[1]), kit.box_shape(_k(h[2])), _k(h[3]))
		_follow(b, bones)
		hb.add_child(b)
	root.add_child(anchors)
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_CINDER_RIG, {"body_path": NodePath("Body"), "stride_length_m": 25.8 * K})
	visual.add_child(kit.n3("Body"))
	visual.add_child(kit.lod_proxy(Vector3(12.0, HEIGHT, 6.3), Vector3(0, HEIGHT * 0.5, 0), "e2_char"))
	root.add_child(visual)
	return root


## The burnt hollow: scorched ground in a ring of stone, the Ashbeck winding across it, the dammed water west.
static func build_cinder_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(T.GIANT)
	var titan: Node3D = kit.instance(CINDER)
	if player == null or titan == null:
		push_error("e2_titans: build the player scene first")
		for n: Node in [player, titan]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "HollowTest"
	kit.scripted(root, T.S_LEVEL, {})
	T._environment(root)
	var floor_size := Vector3(440, 1, 440)
	var solids := BB.ring_solids(ARENA_RADIUS, 30.0, 46, floor_size, [[90.0, 18.0]])
	for sd: Dictionary in solids:
		sd["mat"] = "e2_rock" if str(sd.name) != "Floor" else "e2_char"
	for spec: Array in STONES:
		var size: Vector3 = spec[1]
		solids.append({"name": str(spec[0]), "shape": "box",
			"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec[3]))), (spec[2] as Vector3) + Vector3.UP * size.y * 0.5),
			"size": size, "mat": "e2_rock", "nav": "obstacle"})
	BB._add_solids(kit, root, solids, floor_size)
	var floor_mesh := root.get_node_or_null("Geometry/Floor/Mesh") as MeshInstance3D
	if floor_mesh != null:
		floor_mesh.material_override = kit.mats["e2_char"]
	BB._add_nav(kit, root, solids, [BB.NAV_TITAN])
	var stream := T.storm_water(kit, "test.hollow.stream", STREAM)
	stream.name = "Stream"
	stream.set("rain", 0.0)
	root.add_child(stream)
	var dam := T.storm_water(kit, "test.hollow.damwater", DAM_POOL)
	dam.name = "Damwater"
	dam.set("rain", 0.0)
	dam.set("show_flag", DAMMED_FLAG)
	root.add_child(dam)
	root.add_child(BB._engage_trigger(kit, ENGAGE_ID, Vector3(0, 0, ARENA_RADIUS - 14.0), Vector3(36, 30, 8)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, T.S_ARENA, {"boss_id": CINDER_ID, "encounter_id": "", "engage_area_id": ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": ARENA_RADIUS,
		"defeated_flag": "test.hollow.defeated"})
	root.add_child(arena)
	root.add_child(kit.scripted(kit.n3("DebrisPool"), T.S_DEBRIS))
	titan.name = "Cinder"
	titan.set("entity_id", CINDER_ID)
	titan.position = TITAN_AT
	titan.rotation.y = PI   # facing the entrance (+Z)
	root.add_child(titan)
	BB._place_player(kit, root, player, PLAYER_AT, 0.0)
	BB._sign(kit, root, "HOLLOW TEST: the Cinder Titan (--titan-stage=N; default 9)", PLAYER_AT + Vector3(0, 12, -8))
	return root
