extends RefCounted
## Builder (E3; after e2_titans.gd in build_scenes' BUILDERS): the Hollow Titan.
##   scenes/enemies/hollow.tscn   HollowEnemy (enemy.hollow): the Hollow Titan, 39.6 m - the Stormcaller's hurtboxes, lock
##                                anchors and kneel (titans.gd's, from the creatures' manifest) carried up by K, his
##                                breastplate's box over his whole breast, the oath-knot's box inside it (out of the world
##                                until the breastplate is off: HollowEnemy), his capsule; his rig (HollowRig).
##   scenes/test/hollow_test.tscn the Kingsward test arena (TitanArenaTest; --titan-stage=N): a frost-bitten ring of
##                                ground 112 m round under a broken rock wall, three oath-stones at its edge (prop
##                                oath_pillar: his chains), a ruined ring of the old kings' wall, the titan north, the giant
##                                south, the BossArena and the titan navmesh.

const BB := preload("res://tools/builders/big.gd")
const T := preload("res://tools/builders/titans.gd")
const KIND_PILLAR := preload("res://tools/world/kinds/oath_pillar.gd")

const S_HOLLOW := "res://scripts/actors/hollow_enemy.gd"
const S_HOLLOW_RIG := "res://scripts/presentation/hollow_rig.gd"
const HOLLOW := "res://scenes/enemies/hollow.tscn"
const HOLLOW_TEST := "res://scenes/test/hollow_test.tscn"
const OATH_STAKE := "res://scenes/world/oath_stake.tscn"
const WP2 := preload("res://tools/builders/world_props2.gd")
const S_STAKE_LOOK := "res://scripts/world/oath_stake_look.gd"

const COLORS := {"e3_frost": Color(0.5, 0.52, 0.5), "e3_rock": Color(0.36, 0.36, 0.37), "e3_turf": Color(0.33, 0.36, 0.3)}

## His size over the Stormcaller's (whose skeleton carries his armour).
const K := 39.6 / 34.0
const RADIUS := 6.0
const HEIGHT := 39.6
## The plates' hurtboxes: [node, region, the Stormcaller's piece the box is taken from, anchor, the share of the piece's
## extent] (his breastplate's box his own: BREAST_BOX).
const PLATES := [["Head", "head", "crown", "PlateCrown", 0.85],
	["ShoulderL", "shoulder_l", "pauldron_l", "PlateShoulderL", 0.95],
	["ShoulderR", "shoulder_r", "pauldron_r", "PlateShoulderR", 0.95],
	["BracerR", "forearm_r", "bracer", "PlateBracer", 1.0],
	["ShinL", "shin_l", "greave_l", "PlateShinL", 1.0], ["ShinR", "shin_r", "greave_r", "PlateShinR", 1.0]]
## His breastplate: [centre, size] in the Stormcaller's actor space (his front -Z), and its anchor on its face; the
## oath-knot inside it (a little back and down) and its anchor at the knot's middle (a swing aimed at it lands on the
## knot's box, the nearest to the aim: HitFactory.pick_titan_regions).
const BREAST_BOX := [Vector3(0.0, 24.6, -2.2), Vector3(6.8, 7.0, 3.6)]
const BREAST_ANCHOR := Vector3(0.0, 25.0, -4.0)
const KNOT_BOX := [Vector3(0.0, 24.4, -1.4), Vector3(3.4, 3.6, 3.0)]
const KNOT_ANCHOR := Vector3(0.0, 24.4, -1.4)
## His back (no plate: the backplate is hide) in the Stormcaller's actor space.
const BACK_BOX := [Vector3(0.0, 24.0, 2.4), Vector3(6.4, 8.0, 3.0)]
const KNEEL_FOLLOW := {
	"Head": "head", "PlateCrown": "head", "ShoulderL": "upperarm_l", "PlateShoulderL": "upperarm_l",
	"ShoulderR": "upperarm_r", "PlateShoulderR": "upperarm_r", "Back": "spine_03",
	"Chest": "spine_03", "PlateChest": "spine_03", "Knot": "spine_03", "PlateKnot": "spine_03", "BracerR": "lowerarm_r",
	"PlateBracer": "lowerarm_r", "ArmL": "upperarm_l", "Torso": "spine_02", "Legs": "pelvis", "ShinL": "calf_l",
	"ShinR": "calf_r", "PlateShinL": "calf_l", "PlateShinR": "calf_r", "KneeL": "calf_l", "KneeR": "calf_r",
}

## The Kingsward test arena.
const HOLLOW_ID := "test.kingsward.hollow"
const ENGAGE_ID := "test.area.kingsward_engage"
const ARENA_RADIUS := 112.0
const PLAYER_AT := Vector3(0, 0.05, 70)
const TITAN_AT := Vector3(0, 0.05, -36)
## The oath-stones: [id, position on the floor, height].
const PILLARS := [["test.kingsward.oath_stone_w", Vector3(-78, 0, -40), 26.0],
	["test.kingsward.oath_stone_e", Vector3(80, 0, -30), 26.0],
	["test.kingsward.oath_stone_s", Vector3(-20, 0, 82), 24.0]]
## The old kings' ring wall, broken: [name, size, centre on the floor, yaw degrees].
const STONES := [
	["WallNorth", Vector3(30, 12, 6), Vector3(-10, 0, -104), 8.0],
	["WallNorthEast", Vector3(18, 9, 6), Vector3(62, 0, -86), -40.0],
	["WallWest", Vector3(16, 7, 6), Vector3(-100, 0, 20), 78.0],
	["Boulder", Vector3(9, 6, 8), Vector3(66, 0, 58), 25.0],
]


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.95
			kit.mats[c] = m
	kit.save(build_hollow(kit), HOLLOW)
	kit.save(build_oath_stake(kit), OATH_STAKE)
	kit.save(KIND_PILLAR.scene_root(kit, {"mat": _vertex_material()}), KIND_PILLAR.SCENE)
	var level := build_hollow_test(kit)
	if level != null:
		kit.save(level, HOLLOW_TEST)


static func _k(v: Vector3) -> Vector3:
	return T._snapv(v * K)


## A node's kneeling position at his size (the Stormcaller's kneel, carried up by K).
static func _follow(n: Node3D, bones: Dictionary) -> void:
	var bone := str(KNEEL_FOLLOW.get(str(n.name), ""))
	if bone == "" or not bones.has(bone):
		return
	var p := T.kneel_position(n.position / K, bones[bone]) * K
	n.set_meta("kneel_position", Vector3(snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)))


static func build_hollow(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Hollow"
	kit.scripted(root, S_HOLLOW, {"entity_id": "hollow_01"})
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
	root.add_child(kit.combat_entity("hollow_01", "enemy.hollow", 2))
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
			# (his helm is the whole head and the crown on it)
			size = Vector3(maxf(size.x, 4.4), maxf(size.y, 4.6), maxf(size.z, 4.2))
			c.y -= 0.6
		var box: Node3D = kit.hurtbox(str(spec[0]), str(spec[1]), kit.box_shape(_k(size)), _k(c))
		_follow(box, bones)
		hb.add_child(box)
		var out := Vector3(c.x, 0.0, c.z)
		if str(spec[1]).begins_with("shin"):
			out = Vector3(0, 0, -1)
		out = out.normalized() if out.length() > 0.2 else Vector3.FORWARD
		var at := c + out * (minf(size.x, size.z) * 0.45)
		var m: Node3D = kit.marker(str(spec[3]), _k(at))
		_follow(m, bones)
		anchors.add_child(m)
	var chest: Node3D = kit.hurtbox("Chest", "chest", kit.box_shape(_k(BREAST_BOX[1])), _k(BREAST_BOX[0]))
	_follow(chest, bones)
	hb.add_child(chest)
	var pc: Node3D = kit.marker("PlateChest", _k(BREAST_ANCHOR))
	_follow(pc, bones)
	anchors.add_child(pc)
	var knot: Node3D = kit.hurtbox("Knot", "knot", kit.box_shape(_k(KNOT_BOX[1])), _k(KNOT_BOX[0]))
	_follow(knot, bones)
	hb.add_child(knot)
	var pk: Node3D = kit.marker("PlateKnot", _k(KNOT_ANCHOR))
	_follow(pk, bones)
	anchors.add_child(pk)
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
	kit.scripted(visual, S_HOLLOW_RIG, {"body_path": NodePath("Body"), "stride_length_m": 25.8 * K})
	visual.add_child(kit.n3("Body"))
	visual.add_child(kit.lod_proxy(Vector3(12.0, HEIGHT, 6.0), Vector3(0, HEIGHT * 0.5, 0), "e3_rock"))
	root.add_child(visual)
	return root


## The vertex-coloured material of the world's props (the oath-stones' scene).
static func _vertex_material() -> Material:
	if ResourceLoader.exists("res://assets/world/shared/mat_vertex.tres"):
		return load("res://assets/world/shared/mat_vertex.tres")
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	return mat


## E3: the Oath-stake (prop.oath_stake; a world seal): an iron stake as tall as a tower driven into a boulder on the
## Kingsward's edge - heave it out (stage 9) and the Hollow Titan's oath-chains go slack (on_destroyed_flags:
## world.kingsward.stake_pulled). Its iron is made at load (OathStakeLook); its block and hurtbox the stake's and rock's.
static func build_oath_stake(kit: SceneKit) -> Node:
	var root := WP2._breakable_root(kit, "OathStake", "world.kingsward.oath_stake", "prop.oath_stake", Vector3(0, 14.0, 0))
	root.add_child(WP2._block(kit, "BlockStake", Vector3(14.0, 34.0, 13.0), Vector3(1.5, 17.0, 1.0)))
	root.add_child(WP2._hurtboxes(kit, Vector3(16.0, 34.0, 15.0), Vector3(1.5, 17.0, 1.0)))
	var intact := kit.n3("Intact")
	intact.add_child(kit.scripted(kit.n3("Stake"), S_STAKE_LOOK, {"lying": false}))
	root.add_child(intact)
	var heaved := kit.n3("Heaved")
	heaved.add_child(kit.scripted(kit.n3("Pulled"), S_STAKE_LOOK, {"lying": true}))
	heaved.visible = false
	root.add_child(heaved)
	root.add_child(WP2._heave_point(kit, 26.0))
	return root


## The Kingsward test arena: frost-bitten turf in a ring of rock, the old wall broken round it, three oath-stones.
static func build_hollow_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(T.GIANT)
	var titan: Node3D = kit.instance(HOLLOW)
	if player == null or titan == null:
		push_error("e3_titans: build the player scene first")
		for n: Node in [player, titan]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "KingswardTest"
	kit.scripted(root, T.S_LEVEL, {})
	T._environment(root)
	var floor_size := Vector3(440, 1, 440)
	var solids := BB.ring_solids(ARENA_RADIUS, 30.0, 46, floor_size, [[90.0, 18.0]])
	for sd: Dictionary in solids:
		sd["mat"] = "e3_rock" if str(sd.name) != "Floor" else "e3_turf"
	for spec: Array in STONES:
		var size: Vector3 = spec[1]
		solids.append({"name": str(spec[0]), "shape": "box",
			"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec[3]))), (spec[2] as Vector3) + Vector3.UP * size.y * 0.5),
			"size": size, "mat": "e3_rock", "nav": "obstacle"})
	BB._add_solids(kit, root, solids, floor_size)
	var floor_mesh := root.get_node_or_null("Geometry/Floor/Mesh") as MeshInstance3D
	if floor_mesh != null:
		floor_mesh.material_override = kit.mats["e3_turf"]
	BB._add_nav(kit, root, solids, [BB.NAV_TITAN])
	var props := kit.n3("Props")
	for spec: Array in PILLARS:
		var p := KIND_PILLAR.build(kit, {"id": str(spec[0])}, {})
		p.position = spec[1]
		props.add_child(p)
	root.add_child(props)
	root.add_child(BB._engage_trigger(kit, ENGAGE_ID, Vector3(0, 0, ARENA_RADIUS - 14.0), Vector3(36, 30, 8)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, T.S_ARENA, {"boss_id": HOLLOW_ID, "encounter_id": "", "engage_area_id": ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": ARENA_RADIUS,
		"defeated_flag": "test.kingsward.defeated"})
	root.add_child(arena)
	root.add_child(kit.scripted(kit.n3("DebrisPool"), T.S_DEBRIS))
	titan.name = "Hollow"
	titan.set("entity_id", HOLLOW_ID)
	titan.position = TITAN_AT
	titan.rotation.y = PI   # facing the entrance (+Z)
	root.add_child(titan)
	BB._place_player(kit, root, player, PLAYER_AT, 0.0)
	BB._sign(kit, root, "KINGSWARD TEST: the Hollow Titan (--titan-stage=N; default 9)", PLAYER_AT + Vector3(0, 12, -8))
	return root
