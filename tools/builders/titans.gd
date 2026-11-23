extends RefCounted
## Builder (A2): the signature titans and their test arenas (the open-world expansion, 0.14).
##   scenes/enemies/stoneback.tscn   TitanEnemy (enemy.stoneback): the 17.7 m quarry titan's gameplay body - his
##                                   capsule, the CombatEntity, the lock anchors (the torso, both knees and one a
##                                   breakable plate: PlateShoulderL/R, PlateBack, PlateBrow), a hurtbox a plate region
##                                   (brow, shoulder_l/_r, back, forearm_l/_r, shin_l/_r) and the unplated torso and
##                                   legs - and a TitanRig Visual that loads A1's model (StonebackRig) where the people
##                                   are drawn, a one-box LodProxy elsewhere.
##   scenes/enemies/ogre_king.tscn   B2: TitanEnemy (enemy.ogre_king): the Valley's 8.5 m boss as a signature titan -
##                                   P11a's capsule, anchors (the torso, the knees) and head, torso and legs hurtboxes
##                                   kept (his fight's reach is as it was), with a hurtbox and a lock anchor for each
##                                   trophy (the crown on his head, the bell on his belly, the wheels on his shoulders,
##                                   the keg on his back), each following his kneel; an OgreKingRig Visual (the King's
##                                   model where the people are drawn, a one-box LodProxy elsewhere).
##   scenes/enemies/rootwarden.tscn  B3: TitanEnemy (enemy.rootwarden): the Greywood's 21.3 m warden - his capsule, the
##                                   CombatEntity, a hurtbox a region (head, shoulder_l/_r, back, forearm_r, knot,
##                                   arm_l, torso, legs, shin_l/_r) set over his bark plates as the idle's first key
##                                   poses them (the creatures' manifest, checks.idle_pieces), lock anchors on the
##                                   breakable plates, each following his kneel; a RootwardenRig Visual.
##   scenes/test/grove_test.tscn     B3: the grove test arena (TitanArenaTest; --titan-stage=N): a clearing 80 m
##                                   across inside a ring of trunks, the Rootwarden asleep at its north, four
##                                   braziers round him (fire for his wounds), dead trees as scenery, the giant to
##                                   the south, a BossArena without a gate, a DebrisPool, the titan navmesh.
##   scenes/test/quarry_test.tscn    the quarry test arena (TitanArenaTest; --titan-stage=N): a bowl 70 m across
##                                   inside quarry walls (three terraces, the entrance to the south), four great rocks
##                                   and a cut face to bait his charge into, two timber scaffolds and a palisade his
##                                   charge tramples, Stoneback to the north, the giant at the entrance, a BossArena
##                                   without a gate, a DebrisPool, the titan navmesh.
## Positions in his actor's space (facing -Z, his left at -X) from A1's joints (assets/creatures/manifest.json); the
## hurtboxes do not follow the clips (as every boss's). Gameplay numbers live in the records.

const S_TITAN := "res://scripts/actors/titan_enemy.gd"
const S_RIG := "res://scripts/presentation/titan_rig.gd"
const S_ARENA := "res://scripts/world/boss_arena.gd"
const S_LEVEL := "res://scripts/world/titan_arena_test.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const BB := preload("res://tools/builders/big.gd")
const HB := preload("res://tools/builders/heavy.gd")
const GIANT := "res://scenes/player/giant.tscn"
const STONEBACK := "res://scenes/enemies/stoneback.tscn"
const OGRE_KING := "res://scenes/enemies/ogre_king.tscn"
const S_KING_RIG := "res://scripts/presentation/ogre_king_rig.gd"
const QUARRY_TEST := "res://scenes/test/quarry_test.tscn"
const ROOTWARDEN := "res://scenes/enemies/rootwarden.tscn"
const GROVE_TEST := "res://scenes/test/grove_test.tscn"
const S_WARDEN_RIG := "res://scripts/presentation/rootwarden_rig.gd"
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const KIT_BREAKABLE := preload("res://tools/world/kinds/_breakable_kit.gd")
const KIND_BRAZIER := preload("res://tools/world/kinds/brazier.gd")
const PALISADE := "res://scenes/world/palisade_trample.tscn"
const STONE_ALBEDO := "res://assets/creatures/stoneback_stone_albedo.png"
const STONE_NORMAL := "res://assets/creatures/stoneback_stone_normal.png"

const STONEBACK_ID := "test.quarry.stoneback"
const QUARRY_ENGAGE_ID := "test.area.quarry_engage"
const QUARRY_RADIUS := 70.0
const QUARRY_PLAYER := Vector3(0, 0.05, 58)
const QUARRY_STONEBACK := Vector3(0, 0.05, -22)
## The rocks his charge stops on: [name, size, centre on the floor, yaw degrees].
const QUARRY_ROCKS := [
	["RockWest", Vector3(11, 13, 10), Vector3(-38, 0, 8), 18.0],
	["RockEast", Vector3(12, 11, 11), Vector3(40, 0, -6), -24.0],
	["RockSouthWest", Vector3(9, 9, 9), Vector3(-22, 0, 40), 40.0],
	["RockNorthEast", Vector3(10, 14, 9), Vector3(24, 0, -44), 8.0],
]
## The cut face: a block of the quarry wall standing proud into the bowl to the north-west.
const QUARRY_FACE := ["CutFace", Vector3(26, 22, 8), Vector3(-30, 0, -50), 30.0]
## The props he tramples: [world id, position, yaw degrees].
const QUARRY_PALISADES := [
	["test.quarry.palisade_1", Vector3(14, 0.05, 22), 90.0],
	["test.quarry.palisade_2", Vector3(-12, 0.05, 24), 70.0],
	["test.quarry.palisade_3", Vector3(0, 0.05, 10), 0.0],
]
const COLORS := {
	"a2_quarry_floor": Color(0.40, 0.37, 0.32),
	"a2_quarry_wall": Color(0.50, 0.47, 0.42),
	"a2_quarry_dust": Color(0.50, 0.46, 0.40),
	"a2_timber": Color(0.40, 0.29, 0.18),
}
## The hurtboxes: [name, region, shape ("sphere" radius | "box" size), centre]. The plates' regions match
## enemy.stoneback's plates; torso and legs carry none (the body's own armour).
## A3: his height 16.8 -> 17.7 m and the straighter stance: the table measured again from the idle's first key
## (each plate's posed centre). The shoulders are boxes over the two slabs and the deltoid they cover (11.4-16.2 m:
## the spheres of A2 left the slabs' lower edges, over the upper arm, out of every stage-5 swing).
const HURTBOXES := [
	["Brow", "brow", 1.5, Vector3(0, 16.6, -1.1)],
	["ShoulderL", "shoulder_l", Vector3(3.4, 4.8, 3.4), Vector3(-2.8, 13.8, -0.3)],
	["ShoulderR", "shoulder_r", Vector3(3.4, 4.8, 3.4), Vector3(2.8, 13.8, -0.3)],
	["Back", "back", Vector3(5.4, 4.6, 1.9), Vector3(0, 13.2, 1.5)],
	["Torso", "torso", Vector3(3.8, 3.4, 2.3), Vector3(0, 10.8, -0.6)],
	["ForearmL", "forearm_l", 0.95, Vector3(-3.9, 10.8, -1.5)],
	["ForearmR", "forearm_r", 0.95, Vector3(3.4, 10.7, -1.7)],
	["Legs", "legs", Vector3(4.8, 5.3, 2.5), Vector3(0, 6.6, -0.2)],
	["ShinL", "shin_l", Vector3(1.9, 4.8, 2.0), Vector3(-1.9, 2.7, -0.45)],
	["ShinR", "shin_r", Vector3(1.9, 4.8, 2.0), Vector3(1.9, 2.7, -0.45)],
]
## The lock anchors: the torso and the knees (CombatEntity.LOCK_ANCHOR_NAMES), one a breakable plate.
const ANCHORS := [
	["Torso", Vector3(0, 11.6, 0)],
	["KneeL", Vector3(-1.7, 5.4, -0.8)],
	["KneeR", Vector3(1.7, 5.4, -0.8)],
	["PlateShoulderL", Vector3(-2.8, 14.8, -0.4)],
	["PlateShoulderR", Vector3(2.8, 14.8, -0.4)],
	["PlateBack", Vector3(0, 13.7, 2.0)],
	["PlateBrow", Vector3(0, 16.9, -1.5)],
	["PlateShinL", Vector3(-1.9, 3.1, -1.25)],
	["PlateShinR", Vector3(1.9, 3.1, -1.25)],
]
## A4: the bone each hurtbox and lock anchor follows down onto his knee (TitanEnemy poses them by the kneel's weight):
## its kneeling position is its standing one carried by the bone's motion from the idle's first key to the kneel's
## last frame (the creatures' manifest, checks.kneel: kit/stoneback.py kneel_frames).
const KNEEL_FOLLOW := {
	"Brow": "head", "ShoulderL": "upperarm_l", "ShoulderR": "upperarm_r", "Back": "spine_03", "Torso": "spine_02",
	"ForearmL": "lowerarm_l", "ForearmR": "lowerarm_r", "Legs": "pelvis", "ShinL": "calf_l", "ShinR": "calf_r",
	"KneeL": "calf_l", "KneeR": "calf_r", "PlateShoulderL": "upperarm_l", "PlateShoulderR": "upperarm_r",
	"PlateBack": "spine_03", "PlateBrow": "head", "PlateShinL": "calf_l", "PlateShinR": "calf_r",
}
const CREATURES_MANIFEST := "res://assets/creatures/manifest.json"
## B2: the Ogre King's gameplay body (actor space: his front -Z, his left -X; measured on the idle's first key of
## tools/giant/kit/ogre_king.py's asset). P11a's capsule (radius 2, 8.5 m), its Torso / KneeL / KneeR anchors and its
## Head, Torso and Legs hurtboxes are kept where they were (the Valley fight's reach is unchanged); each trophy adds
## its own hurtbox over the piece (the plate's region) and a lock anchor on its face.
const KING_CAPSULE := [2.0, 8.5]
const KING_HURTBOXES := [
	["Head", "head", 0.95, Vector3(0, 7.95, -0.75)],
	["Belly", "belly", Vector3(2.9, 1.7, 1.2), Vector3(0, 5.1, -1.45)],
	["Back", "back", Vector3(2.4, 1.3, 1.3), Vector3(0, 5.1, 1.5)],
	["ShoulderL", "shoulder_l", Vector3(2.2, 1.7, 2.4), Vector3(-1.55, 7.25, -0.1)],
	["ShoulderR", "shoulder_r", Vector3(2.2, 1.7, 2.4), Vector3(1.4, 7.25, -0.15)],
	["Torso", "torso", Vector3(3.875, 3.625, 2.75), Vector3(0, 5.375, 0)],
	["Legs", "legs", Vector3(3.0, 3.5, 2.0), Vector3(0, 1.75, 0)],
]
const KING_ANCHORS := [
	["Torso", Vector3(0, 5.5, 0)],
	["KneeL", Vector3(-0.875, 2.25, -0.2)],
	["KneeR", Vector3(0.875, 2.25, -0.2)],
	["PlateCrown", Vector3(0, 8.55, -1.25)],
	["PlateBell", Vector3(0, 5.0, -2.0)],
	["PlateKeg", Vector3(0, 5.1, 2.0)],
	["PlateWheelL", Vector3(-1.6, 7.5, -0.1)],
	["PlateWheelR", Vector3(1.45, 7.5, -0.15)],
]
const KING_KNEEL_FOLLOW := {
	"Head": "head", "Belly": "spine_01", "Back": "spine_01", "ShoulderL": "upperarm_l", "ShoulderR": "upperarm_r",
	"Torso": "spine_02", "Legs": "pelvis", "KneeL": "calf_l", "KneeR": "calf_r", "PlateCrown": "head",
	"PlateBell": "spine_01", "PlateKeg": "spine_01", "PlateWheelL": "upperarm_l", "PlateWheelR": "upperarm_r",
}
## B3: the Rootwarden's gameplay body (actor space: his front -Z, his left -X). The plates' hurtboxes and anchors
## stand over the bark as the idle's first key poses it (the creatures' manifest, rootwarden.checks.idle_pieces:
## each plate's centre and extent); the head, the root-arm, the torso and the legs are set here.
const WARDEN_CAPSULE := [3.4, 21.3]
const WARDEN_PLATES := {"ShoulderL": ["shoulder_l", "bark_shoulder_l", "PlateShoulderL"],
	"ShoulderR": ["shoulder_r", "bark_shoulder_r", "PlateShoulderR"], "Back": ["back", "bark_back", "PlateBack"],
	"ForearmR": ["forearm_r", "bark_forearm_r", "PlateForearmR"], "Knot": ["knot", "bark_knot", "PlateKnot"],
	"ShinL": ["shin_l", "bark_shin_l", "PlateShinL"], "ShinR": ["shin_r", "bark_shin_r", "PlateShinR"]}
## The hurtboxes he has beside his plates': [name, region, shape (radius | size), centre].
const WARDEN_BODY := [
	["Head", "head", 1.3, Vector3(0, 20.1, -0.9)],
	["ArmL", "arm_l", Vector3(1.6, 5.4, 1.8), Vector3(-2.9, 14.2, -0.6)],
	["Torso", "torso", Vector3(4.0, 4.4, 2.6), Vector3(0, 14.4, -0.4)],
	["Legs", "legs", Vector3(4.6, 6.6, 2.6), Vector3(0, 9.0, -0.2)],
]
const WARDEN_ANCHORS := [
	["Torso", Vector3(0, 14.6, 0)],
	["KneeL", Vector3(-2.0, 7.0, -0.9)],
	["KneeR", Vector3(2.0, 7.0, -0.9)],
]
const WARDEN_KNEEL_FOLLOW := {
	"Head": "head", "ShoulderL": "upperarm_l", "ShoulderR": "upperarm_r", "Back": "spine_03", "Torso": "spine_02",
	"ForearmR": "lowerarm_r", "Knot": "lowerarm_l", "ArmL": "upperarm_l", "Legs": "pelvis", "ShinL": "calf_l",
	"ShinR": "calf_r", "KneeL": "calf_l", "KneeR": "calf_r", "PlateShoulderL": "upperarm_l",
	"PlateShoulderR": "upperarm_r", "PlateBack": "spine_03", "PlateForearmR": "lowerarm_r", "PlateKnot": "lowerarm_l",
	"PlateShinL": "calf_l", "PlateShinR": "calf_r",
}
## The grove test arena.
const ROOTWARDEN_ID := "test.grove.rootwarden"
const GROVE_ENGAGE_ID := "test.area.grove_engage"
const GROVE_RADIUS := 80.0
const GROVE_PLAYER := Vector3(0, 0.05, 52)
const GROVE_WARDEN := Vector3(0, 0.05, -18)
## The braziers round his spot: [world id, position].
const GROVE_BRAZIERS := [
	["test.grove.brazier_1", Vector3(-12, 0.05, -8)],
	["test.grove.brazier_2", Vector3(13, 0.05, -10)],
	["test.grove.brazier_3", Vector3(-11, 0.05, -30)],
	["test.grove.brazier_4", Vector3(12, 0.05, -29)],
]

## A3: his capsule (17.7 m).
const CAPSULE_RADIUS := 3.6
const CAPSULE_HEIGHT := 17.7


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.95
			kit.mats[c] = m
	kit.mats["a2_rock"] = rock_material()
	kit.save(build_stoneback(kit), STONEBACK)
	kit.save(build_ogre_king(kit), OGRE_KING)
	kit.save(build_rootwarden(kit), ROOTWARDEN)
	var level := build_quarry_test(kit)
	if level != null:
		kit.save(level, QUARRY_TEST)
	var grove := build_grove_test(kit)
	if grove != null:
		kit.save(grove, GROVE_TEST)


## The quarry's rock: A1's tileable stone in world space (triplanar), a little darker than his plates.
static func rock_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.86, 0.83, 0.78)
	if ResourceLoader.exists(STONE_ALBEDO):
		m.albedo_texture = load(STONE_ALBEDO)
	if ResourceLoader.exists(STONE_NORMAL):
		m.normal_enabled = true
		m.normal_texture = load(STONE_NORMAL)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / 6.0
	m.roughness = 0.95
	return m


# --------------------------------------------------------------------------- Stoneback

static func build_stoneback(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Stoneback"
	kit.scripted(root, S_TITAN, {"entity_id": "stoneback_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = CAPSULE_RADIUS
	cap.height = CAPSULE_HEIGHT
	cs.shape = cap
	cs.position = Vector3(0, CAPSULE_HEIGHT * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("stoneback_01", "enemy.stoneback", 2))
	var bones := kneel_bones()
	var anchors := kit.n3("Anchors")
	for a: Array in ANCHORS:
		var m: Node3D = kit.marker(str(a[0]), a[1])
		_follow_kneel(m, bones)
		anchors.add_child(m)
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	for h: Array in HURTBOXES:
		var shape: Shape3D
		if h[2] is Vector3:
			shape = kit.box_shape(h[2])
		else:
			var sp := SphereShape3D.new()
			sp.radius = float(h[2])
			shape = sp
		var box: Node3D = kit.hurtbox(str(h[0]), str(h[1]), shape, h[3])
		_follow_kneel(box, bones)
		hb.add_child(box)
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_RIG, {"body_path": NodePath("Body"), "stride_length_m": 7.4})
	visual.add_child(kit.n3("Body"))
	visual.add_child(kit.lod_proxy(Vector3(5.2, 16.8, 3.4), Vector3(0, 8.4, 0), "a2_quarry_wall"))
	root.add_child(visual)
	return root


## B2: the Ogre King (enemy.ogre_king) as a signature titan: TitanEnemy, his trophies' hurtboxes and anchors.
static func build_ogre_king(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "OgreKing"
	kit.scripted(root, S_TITAN, {"entity_id": "ogre_king_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = float(KING_CAPSULE[0])
	cap.height = float(KING_CAPSULE[1])
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("ogre_king_01", "enemy.ogre_king", 2))
	var bones := kneel_bones("ogre_king")
	var anchors := kit.n3("Anchors")
	for a: Array in KING_ANCHORS:
		var m: Node3D = kit.marker(str(a[0]), a[1])
		_follow_kneel(m, bones, KING_KNEEL_FOLLOW)
		anchors.add_child(m)
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	for h: Array in KING_HURTBOXES:
		var shape: Shape3D
		if h[2] is Vector3:
			shape = kit.box_shape(h[2])
		else:
			var sp := SphereShape3D.new()
			sp.radius = float(h[2])
			shape = sp
		var box: Node3D = kit.hurtbox(str(h[0]), str(h[1]), shape, h[3])
		_follow_kneel(box, bones, KING_KNEEL_FOLLOW)
		hb.add_child(box)
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_KING_RIG, {"body_path": NodePath("Body"), "stride_length_m": 3.06})
	visual.add_child(kit.n3("Body"))
	visual.add_child(kit.lod_proxy(Vector3(3.75, 8.5, 2.75), Vector3(0, 4.25, 0), "king_skin"))
	root.add_child(visual)
	return root


## B3: the Rootwarden (enemy.rootwarden) as a signature titan: TitanEnemy, his plates' hurtboxes and anchors over his
## bark as the idle poses it, every one following his kneel.
static func build_rootwarden(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "Rootwarden"
	kit.scripted(root, S_TITAN, {"entity_id": "rootwarden_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = float(WARDEN_CAPSULE[0])
	cap.height = float(WARDEN_CAPSULE[1])
	cs.shape = cap
	cs.position = Vector3(0, cap.height * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("rootwarden_01", "enemy.rootwarden", 2))
	var bones := kneel_bones("rootwarden")
	var pieces := idle_pieces("rootwarden")
	var anchors := kit.n3("Anchors")
	for a: Array in WARDEN_ANCHORS:
		var m: Node3D = kit.marker(str(a[0]), a[1])
		_follow_kneel(m, bones, WARDEN_KNEEL_FOLLOW)
		anchors.add_child(m)
	var hb := kit.n3("Hurtboxes")
	for name: String in WARDEN_PLATES:
		var spec: Array = WARDEN_PLATES[name]
		var ip: Dictionary = pieces.get(str(spec[1]), {})
		var c := _vec(ip.get("centre", [0, 12, 0]))
		var size := _vec(ip.get("size", [2, 2, 2])) * 0.9
		var box: Node3D = kit.hurtbox(name, str(spec[0]), kit.box_shape(_snapv(size)), _snapv(c))
		_follow_kneel(box, bones, WARDEN_KNEEL_FOLLOW)
		hb.add_child(box)
		# the plate's lock anchor: on its face, out from his body's axis (and forward for the shins)
		var out := Vector3(c.x, 0.0, c.z)
		out = out.normalized() if out.length() > 0.2 else Vector3.FORWARD
		var at := c + out * (minf(size.x, size.z) * 0.45)
		var m: Node3D = kit.marker(str(spec[2]), _snapv(at))
		_follow_kneel(m, bones, WARDEN_KNEEL_FOLLOW)
		anchors.add_child(m)
	for h: Array in WARDEN_BODY:
		var shape: Shape3D
		if h[2] is Vector3:
			shape = kit.box_shape(h[2])
		else:
			var sp := SphereShape3D.new()
			sp.radius = float(h[2])
			shape = sp
		var b: Node3D = kit.hurtbox(str(h[0]), str(h[1]), shape, h[3])
		_follow_kneel(b, bones, WARDEN_KNEEL_FOLLOW)
		hb.add_child(b)
	root.add_child(anchors)
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_WARDEN_RIG, {"body_path": NodePath("Body"), "stride_length_m": 12.4})
	visual.add_child(kit.n3("Body"))
	visual.add_child(kit.lod_proxy(Vector3(5.6, 21.3, 3.2), Vector3(0, 10.65, 0), "a2_timber"))
	root.add_child(visual)
	return root


## B3: the plates' centres and extents in the idle (the creatures' manifest, <creature>.checks.idle_pieces).
static func idle_pieces(creature: String) -> Dictionary:
	if not FileAccess.file_exists(CREATURES_MANIFEST):
		return {}
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREATURES_MANIFEST))
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	var ip: Variant = ((doc.get(creature, {}) as Dictionary).get("checks", {}) as Dictionary).get("idle_pieces", {})
	return ip if typeof(ip) == TYPE_DICTIONARY else {}


static func _vec(a: Variant) -> Vector3:
	var l: Array = a if typeof(a) == TYPE_ARRAY else [0, 0, 0]
	return Vector3(float(l[0]), float(l[1]), float(l[2]))


static func _snapv(v: Vector3) -> Vector3:
	return Vector3(snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01))


## A4: the kneel's bones (the creatures' manifest, <creature>.checks.kneel.bones: {bone: {idle, kneel: {head,
## basis}}} in his actor's space); {} while the manifest is missing. B2: of any titan (the Ogre King's too).
static func kneel_bones(creature := "stoneback") -> Dictionary:
	if not FileAccess.file_exists(CREATURES_MANIFEST):
		return {}
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(CREATURES_MANIFEST))
	if typeof(doc) != TYPE_DICTIONARY:
		return {}
	var k: Variant = ((doc.get(creature, {}) as Dictionary).get("checks", {}) as Dictionary).get("kneel", {})
	return (k as Dictionary).get("bones", {}) if typeof(k) == TYPE_DICTIONARY else {}


## A4: a node's kneeling position: its standing one carried by its bone's rigid motion from the idle to the kneel.
static func kneel_position(at: Vector3, bone: Dictionary) -> Vector3:
	var i: Dictionary = bone.get("idle", {})
	var k: Dictionary = bone.get("kneel", {})
	if i.is_empty() or k.is_empty():
		return at
	var bi := _basis_of(i.basis as Array)
	var bk := _basis_of(k.basis as Array)
	var hi := Vector3(float(i.head[0]), float(i.head[1]), float(i.head[2]))
	var hk := Vector3(float(k.head[0]), float(k.head[1]), float(k.head[2]))
	return hk + bk * (bi.inverse() * (at - hi))


static func _basis_of(m: Array) -> Basis:
	# (row-major 3x3 in the manifest; a Basis holds columns)
	return Basis(Vector3(float(m[0]), float(m[3]), float(m[6])), Vector3(float(m[1]), float(m[4]), float(m[7])),
		Vector3(float(m[2]), float(m[5]), float(m[8])))


static func _follow_kneel(n: Node3D, bones: Dictionary, follow: Dictionary = KNEEL_FOLLOW) -> void:
	var bone := str(follow.get(str(n.name), ""))
	if bone == "" or not bones.has(bone):
		return
	var at := n.position
	var p := kneel_position(at, bones[bone])
	n.set_meta("kneel_position", Vector3(snappedf(p.x, 0.001), snappedf(p.y, 0.001), snappedf(p.z, 0.001)))


# --------------------------------------------------------------------------- the quarry

static func build_quarry_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var titan: Node3D = kit.instance(STONEBACK)
	if player == null or titan == null:
		push_error("titans: build the player scene first")
		for n: Node in [player, titan]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "QuarryTest"
	kit.scripted(root, S_LEVEL, {})
	_environment(root)
	var floor_size := Vector3(300, 1, 300)
	var solids := BB.ring_solids(QUARRY_RADIUS, 24.0, 36, floor_size, [[90.0, 11.0]])
	for sd: Dictionary in solids:
		sd["mat"] = "a2_rock" if str(sd.name) != "Floor" else "a2_quarry_floor"
	# the terraces above the wall: two rings stepped back and up (scenery: outside the navmesh's reach)
	for tier in 2:
		var r := QUARRY_RADIUS + 9.0 + 9.0 * tier
		for sd: Dictionary in BB.ring_solids(r, 30.0 + 8.0 * tier, 36, floor_size, [[90.0, 11.0 + 4.0 * tier]]):
			if str(sd.name) == "Floor":
				continue
			sd["name"] = "Terrace%d_%s" % [tier + 1, str(sd.name)]
			sd["size"] = (sd.size as Vector3) * Vector3(4.0, 1.0, 1.0)
			sd["mat"] = "a2_rock"
			solids.append(sd)
	for spec: Array in QUARRY_ROCKS + [QUARRY_FACE]:
		var size: Vector3 = spec[1]
		solids.append({"name": str(spec[0]), "shape": "box",
			"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(float(spec[3]))), (spec[2] as Vector3) + Vector3.UP * size.y * 0.5),
			"size": size, "mat": "a2_rock", "nav": "obstacle"})
	BB._add_solids(kit, root, solids, floor_size)
	var floor_mesh := root.get_node_or_null("Geometry/Floor/Mesh") as MeshInstance3D
	if floor_mesh != null:
		floor_mesh.material_override = kit.mats["a2_quarry_floor"]
	BB._add_nav(kit, root, solids, [BB.NAV_TITAN])
	_dressing(kit, root)
	root.add_child(BB._engage_trigger(kit, QUARRY_ENGAGE_ID, Vector3(0, 0, QUARRY_RADIUS - 10.0), Vector3(22, 20, 8)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_ARENA, {"boss_id": STONEBACK_ID, "encounter_id": "", "engage_area_id": QUARRY_ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": QUARRY_RADIUS,
		"defeated_flag": "test.quarry.defeated"})
	root.add_child(arena)
	var props := kit.n3("Props")
	for spec: Array in QUARRY_PALISADES:
		var p: Node3D = kit.instance(PALISADE)
		if p == null:
			continue
		p.name = str(spec[0]).get_slice(".", 2).capitalize().replace(" ", "")
		p.set("world_id", spec[0])
		p.position = spec[1]
		p.rotation.y = deg_to_rad(float(spec[2]))
		props.add_child(p)
	root.add_child(props)
	root.add_child(kit.scripted(kit.n3("DebrisPool"), S_DEBRIS))   # the plates' stone, the palisades' planks
	titan.name = "Stoneback"
	titan.set("entity_id", STONEBACK_ID)
	titan.position = QUARRY_STONEBACK
	titan.rotation.y = PI   # facing the entrance (+Z) and the giant coming in
	root.add_child(titan)
	BB._place_player(kit, root, player, QUARRY_PLAYER, 0.0)
	BB._sign(kit, root, "QUARRY TEST: Stoneback (--titan-stage=N; default 5)", QUARRY_PLAYER + Vector3(0, 10, -8))
	return root


## A clear sky colour, a sun from the south-west with long shadows (the box levels' own light).
static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.52, 0.62, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-42, -35, 0)
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.light_energy = 1.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 220.0
	root.add_child(sun)


## Scenery: quarried blocks stacked by the walls, spoil heaps, dust on the floor (no collision: never in the way).
static func _dressing(kit: SceneKit, root: Node3D) -> void:
	var d := kit.n3("Dressing")
	var blocks := [[Vector3(60, 0, 26), 25.0], [Vector3(-63, 0, -18), -10.0], [Vector3(50, 0, -40), 60.0],
		[Vector3(-54, 0, 38), 15.0], [Vector3(8, 0, -64), 0.0]]
	var i := 0
	for b: Array in blocks:
		var at: Vector3 = b[0]
		for k in 3:
			var size := Vector3(5.0 - k, 2.6, 3.4 - 0.6 * k)
			var m := kit.box("Block%d_%d" % [i, k], size, at + Vector3(0.6 * k, 1.3 + 2.6 * k, -0.4 * k), "a2_rock")
			m.rotation.y = deg_to_rad(float(b[1]) + 9.0 * k)
			d.add_child(m)
		i += 1
	for s: Array in [[Vector3(-58, 0, -36), 9.0], [Vector3(62, 0, 8), 7.0], [Vector3(36, 0, 56), 6.0]]:
		d.add_child(kit.cyl("Spoil%d" % i, 1.0, float(s[1]), float(s[1]) * 0.55,
			(s[0] as Vector3) + Vector3.UP * float(s[1]) * 0.275, "a2_quarry_dust"))
		i += 1
	root.add_child(d)


# --------------------------------------------------------------------------- B3: the grove

static func build_grove_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var titan: Node3D = kit.instance(ROOTWARDEN)
	if player == null or titan == null:
		push_error("titans: build the player scene first")
		for n: Node in [player, titan]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "GroveTest"
	kit.scripted(root, S_LEVEL, {})
	_environment(root)
	var floor_size := Vector3(320, 1, 320)
	var solids := BB.ring_solids(GROVE_RADIUS, 30.0, 40, floor_size, [[90.0, 14.0]])
	for sd: Dictionary in solids:
		sd["mat"] = "a2_timber" if str(sd.name) != "Floor" else "a2_quarry_floor"
	BB._add_solids(kit, root, solids, floor_size)
	BB._add_nav(kit, root, solids, [BB.NAV_TITAN])
	# dead trees standing round the clearing (scenery, no collision): grey trunks with a few broken limbs
	var d := kit.n3("Dressing")
	var i := 0
	for a_deg: float in [20.0, 70.0, 130.0, 200.0, 250.0, 300.0, 340.0]:
		var a := deg_to_rad(a_deg)
		var at := Vector3(cos(a), 0.0, sin(a)) * (GROVE_RADIUS - 14.0)
		d.add_child(kit.cyl("DeadTree%d" % i, 0.5, 1.3, 16.0, at + Vector3.UP * 8.0, "a2_timber"))
		i += 1
	root.add_child(d)
	root.add_child(BB._engage_trigger(kit, GROVE_ENGAGE_ID, Vector3(0, 0, GROVE_RADIUS - 12.0), Vector3(26, 22, 8)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_ARENA, {"boss_id": ROOTWARDEN_ID, "encounter_id": "", "engage_area_id": GROVE_ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": GROVE_RADIUS,
		"defeated_flag": "test.grove.defeated"})
	root.add_child(arena)
	var props := kit.n3("Props")
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	for spec: Array in GROVE_BRAZIERS:
		var b := KIT_BREAKABLE.build(kit, {"id": str(spec[0])}, {"mat": mat}, S_BREAKABLE, "prop.brazier",
			KIND_BRAZIER.design({}))
		b.position = spec[1]
		props.add_child(b)
	root.add_child(props)
	root.add_child(kit.scripted(kit.n3("DebrisPool"), S_DEBRIS))
	titan.name = "Rootwarden"
	titan.set("entity_id", ROOTWARDEN_ID)
	titan.position = GROVE_WARDEN
	titan.rotation.y = PI   # facing the entrance (+Z)
	root.add_child(titan)
	BB._place_player(kit, root, player, GROVE_PLAYER, 0.0)
	BB._sign(kit, root, "GROVE TEST: the Rootwarden (--titan-stage=N; default 5)", GROVE_PLAYER + Vector3(0, 10, -8))
	return root
