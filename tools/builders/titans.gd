extends RefCounted
## Builder (A2): the signature titans and their test arenas (the open-world expansion, 0.14).
##   scenes/enemies/stoneback.tscn   TitanEnemy (enemy.stoneback): the 17.7 m quarry titan's gameplay body - his
##                                   capsule, the CombatEntity, the lock anchors (the torso, both knees and one a
##                                   breakable plate: PlateShoulderL/R, PlateBack, PlateBrow), a hurtbox a plate region
##                                   (brow, shoulder_l/_r, back, forearm_l/_r, shin_l/_r) and the unplated torso and
##                                   legs - and a TitanRig Visual that loads A1's model (StonebackRig) where the people
##                                   are drawn, a one-box LodProxy elsewhere.
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
const QUARRY_TEST := "res://scenes/test/quarry_test.tscn"
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
	var level := build_quarry_test(kit)
	if level != null:
		kit.save(level, QUARRY_TEST)


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
	var anchors := kit.n3("Anchors")
	for a: Array in ANCHORS:
		anchors.add_child(kit.marker(str(a[0]), a[1]))
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
		hb.add_child(kit.hurtbox(str(h[0]), str(h[1]), shape, h[3]))
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
