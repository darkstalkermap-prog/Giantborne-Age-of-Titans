extends RefCounted
## Builder (E1; after titans.gd in build_scenes' BUILDERS): Harrok's return.
##   scenes/enemies/orrik.tscn          HeirEnemy (enemy.orrik): Orrik the Fetterer, 31.5 m - the player's realistic giant
##                                      (big.gd's giant_visual: SkinnedRig on giant_model.tscn at k = 31.5 / 3.6576) in his
##                                      record's look (appearance_preset.npc_orrik), his capsule, the plates' hurtboxes and
##                                      lock anchors (actor space: his front -Z) and the body's.
##   scenes/enemies/skarn_winchman.tscn SoldierEnemy (enemy.skarn_winchman): a 10 m Skarn giant who serves a fetter-winch.
##   scenes/world/fetter_winch.tscn     FetterWinch (prop.fetter_winch): the giant's harpoon engine - a staked timber sled,
##                                      the post and the turning stock with its loaded harpoon, the great bow and its
##                                      strings, the drum of chain behind; its wreck; one vertex-coloured mesh each.
##   scenes/actors/harrok_ally.tscn     HarrokAlly: Harrok the Unbowed (15 m) as the giant's ally - the rival giants' body
##                                      in his look (appearance_preset.npc_harrok) with his axe; no combat entity.
##   scenes/test/throne_test.tscn       the Moot test arena (a LevelRoot, level.throne_test): a 60 m ring of standing stones
##                                      and a low wall with a south gate, the Stone Throne at its north edge, five
##                                      fetter-winches staked inside the ring (two from the engagement, three from his
##                                      second phase), Orrik before the throne, the ThroneChallenge arena (its warband the
##                                      winches' crews: encounter.throne_test_warband), the director and the titan navmesh.

const BB := preload("res://tools/builders/big.gd")
const HB := preload("res://tools/builders/heavy.gd")

const S_HEIR := "res://scripts/actors/heir_enemy.gd"
const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const S_WINCH := "res://scripts/world/fetter_winch.gd"
const S_ALLY := "res://scripts/actors/harrok_ally.gd"
const S_CHALLENGE := "res://scripts/world/throne_challenge.gd"
const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const GIANT := "res://scenes/player/giant.tscn"

const ORRIK := "res://scenes/enemies/orrik.tscn"
const WINCHMAN := "res://scenes/enemies/skarn_winchman.tscn"
const WINCH := "res://scenes/world/fetter_winch.tscn"
const ALLY := "res://scenes/actors/harrok_ally.tscn"
const THRONE_TEST := "res://scenes/test/throne_test.tscn"

const COLORS := {
	"e1_moot_stone": Color(0.42, 0.41, 0.38),
	"e1_moot_dark": Color(0.30, 0.29, 0.27),
	"e1_moot_turf": Color(0.33, 0.37, 0.24),
	"e1_chain": Color(0.16, 0.15, 0.14),
	"e1_timber": Color(0.33, 0.24, 0.16),
	"e1_timber_dark": Color(0.22, 0.16, 0.11),
	"e1_hide": Color(0.45, 0.36, 0.26),
	"e1_iron": Color(0.25, 0.25, 0.27),
	"e1_rope": Color(0.55, 0.47, 0.33),
	"e1_split": Color(0.47, 0.37, 0.26),
}

const ORRIK_H := 31.5
const ORRIK_RADIUS := 5.9
## His body in units of a tenth of his height (the rival giants' proportions): [node, region, shape, size or
## radius, centre].
const ORRIK_BOXES := [
	["Head", "head", "sphere", 0.85, Vector3(0, 9.05, -0.1)],
	["ShoulderL", "shoulder_l", "box", Vector3(1.3, 1.1, 1.5), Vector3(-1.3, 7.75, 0)],
	["ShoulderR", "shoulder_r", "box", Vector3(1.3, 1.1, 1.5), Vector3(1.3, 7.75, 0)],
	["ForearmL", "forearm_l", "box", Vector3(1.0, 1.6, 1.4), Vector3(-1.75, 5.2, -0.4)],
	["ArmR", "arm_r", "box", Vector3(1.0, 2.2, 1.3), Vector3(1.75, 5.6, -0.3)],
	["Torso", "torso", "box", Vector3(2.6, 3.0, 1.9), Vector3(0, 6.0, 0)],
	["Legs", "legs", "box", Vector3(2.6, 4.6, 1.6), Vector3(0, 2.3, 0)],
]
## The plates' lock anchors (the same units): on each piece's face, toward the giant.
const ORRIK_ANCHORS := [
	["Torso", Vector3(0, 6.2, 0)],
	["PlateHelm", Vector3(0, 9.05, -0.9)],
	["PlateSpaulderL", Vector3(-1.4, 7.9, -0.6)],
	["PlateSpaulderR", Vector3(1.4, 7.9, -0.6)],
	["PlateCoil", Vector3(-1.75, 5.2, -1.1)],
	["PlateGreaves", Vector3(0, 1.6, -0.8)],
	["KneeL", Vector3(-0.8, 2.4, -0.2)],
	["KneeR", Vector3(0.8, 2.4, -0.2)],
]

## The Moot test arena: the ring (radius, wall height, the gate's half width at +Z), its stones, the throne, Orrik,
## the giant, the winches ([world id, x, z, join phase]).
const MOOT_RADIUS := 60.0
const MOOT_WALL_H := 9.0
const MOOT_GATE_HALF := 14.0
const MOOT_STONES := 16
const ORRIK_ID := "test.throne.orrik"
const ENGAGE_ID := "test.area.throne_engage"
const THRONE_AT := Vector3(0, 0, -52)
const ORRIK_AT := Vector3(0, 0.05, -30)
const PLAYER_AT := Vector3(0, 0.05, 78)
const WINCHES := [
	["test.throne.winch_1", -36.0, -26.0, 1], ["test.throne.winch_2", 36.0, -26.0, 1],
	["test.throne.winch_3", -46.0, 6.0, 2], ["test.throne.winch_4", 46.0, 6.0, 2],
	["test.throne.winch_5", -24.0, 40.0, 2],
]
const ALLY_AT := Vector3(10, 0.05, 54)


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.92
			kit.mats[c] = m
	kit.save(build_orrik(kit), ORRIK)
	kit.save(build_winchman(kit), WINCHMAN)
	kit.save(build_winch(kit), WINCH)
	kit.save(build_ally(kit), ALLY)
	var level := build_throne_test(kit)
	if level != null:
		kit.save(level, THRONE_TEST)


static func _capsule(kit: SceneKit, root: Node3D, radius: float, h: float) -> void:
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = h
	cs.shape = cap
	cs.position = Vector3(0, h * 0.5, 0)
	root.add_child(cs)


static func build_orrik(kit: SceneKit) -> Node:
	var u := ORRIK_H / 10.0
	var root := CharacterBody3D.new()
	root.name = "Orrik"
	kit.scripted(root, S_HEIR, {"entity_id": "orrik_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	_capsule(kit, root, ORRIK_RADIUS, ORRIK_H)
	root.add_child(kit.combat_entity("orrik_01", "enemy.orrik", 2))
	var anchors := kit.n3("Anchors")
	for a: Array in ORRIK_ANCHORS:
		anchors.add_child(kit.marker(str(a[0]), (a[1] as Vector3) * u))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	for b: Array in ORRIK_BOXES:
		var shape: Shape3D
		if str(b[2]) == "sphere":
			var s := SphereShape3D.new()
			s.radius = float(b[3]) * u
			shape = s
		else:
			shape = kit.box_shape((b[3] as Vector3) * u)
		hb.add_child(kit.hurtbox(str(b[0]), str(b[1]), shape, (b[4] as Vector3) * u))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	root.add_child(BB.giant_visual(kit, ORRIK_H))
	return root


static func build_winchman(kit: SceneKit) -> Node:
	var root := BB.build_giant(kit, "SkarnWinchman", "skarn_winchman_01", "enemy.skarn_winchman", 10.0, 2.1, false)
	root.set_script(null)
	kit.scripted(root, S_SOLDIER, {"entity_id": "skarn_winchman_01"})
	return root


## The fetter-winch (its front -Z): 7.5 m to the bow's tips, the muzzle at (0, 4.6, -4.8), the drum's chain at about
## 0.55 of its height behind the post.
static func build_winch(kit: SceneKit) -> Node:
	var root := StaticBody3D.new()
	root.name = "FetterWinch"
	kit.scripted(root, S_WINCH, {"world_id": "test.throne.winch", "faction": ""})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	root.add_child(kit.combat_entity("test.throne.winch", "prop.fetter_winch", 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", Vector3(0, 3.0, 0)))
	anchors.add_child(kit.marker("Grab", Vector3(0, 4.0, 0.5)))
	root.add_child(anchors)
	var intact := kit.n3("Intact")
	intact.add_child(kit.box("Sled", Vector3(5.6, 0.8, 9.6), Vector3(0, 0.4, 0.6), "e1_timber_dark"))
	for side in [-1.0, 1.0]:
		intact.add_child(kit.box("Runner%s" % ("L" if side < 0 else "R"), Vector3(0.7, 0.7, 10.6),
			Vector3(2.5 * side, 0.35, 0.6), "e1_timber"))
		for zz in [-3.6, 4.6]:
			var stake := kit.box("Stake%s%d" % ["L" if side < 0 else "R", int(zz)], Vector3(0.45, 2.6, 0.45),
				Vector3(3.3 * side, 0.6, zz), "e1_iron")
			stake.rotation_degrees = Vector3(0, 0, -24.0 * side)
			intact.add_child(stake)
	intact.add_child(kit.box("Post", Vector3(1.3, 2.8, 1.3), Vector3(0, 2.2, 0.0), "e1_timber"))
	intact.add_child(kit.box("Stock", Vector3(1.1, 0.9, 10.4), Vector3(0, 3.95, -0.4), "e1_timber"))
	intact.add_child(kit.box("Harpoon", Vector3(0.32, 0.32, 8.0), Vector3(0, 4.6, -1.4), "e1_timber_dark"))
	intact.add_child(kit.box("HarpoonHead", Vector3(0.9, 0.9, 1.4), Vector3(0, 4.6, -5.6), "e1_iron"))
	for side in [-1.0, 1.0]:
		var arm := kit.box("Arm%s" % ("L" if side < 0 else "R"), Vector3(4.6, 0.6, 0.7),
			Vector3(2.4 * side, 5.6, -4.0), "e1_timber_dark")
		arm.rotation_degrees = Vector3(0, 0, 30.0 * side)
		intact.add_child(arm)
		var string := kit.box("String%s" % ("L" if side < 0 else "R"), Vector3(0.12, 0.12, 4.9),
			Vector3(2.15 * side, 5.0, -2.3), "e1_rope")
		string.rotation_degrees = Vector3(0, -42.0 * side, 0)
		intact.add_child(string)
		intact.add_child(kit.box("DrumCheek%s" % ("L" if side < 0 else "R"), Vector3(0.6, 3.4, 2.4),
			Vector3(2.3 * side, 2.5, 3.8), "e1_timber"))
	var drum := kit.cyl("Drum", 1.25, 1.25, 4.0, Vector3(0, 3.0, 3.8), "e1_timber_dark")
	drum.rotation_degrees = Vector3(0, 0, 90)
	intact.add_child(drum)
	var coil := kit.cyl("Coil", 1.55, 1.55, 3.4, Vector3(0, 3.0, 3.8), "e1_chain")
	coil.rotation_degrees = Vector3(0, 0, 90)
	intact.add_child(coil)
	for side in [-1.0, 1.0]:
		var spoke := kit.box("Spoke%s" % ("L" if side < 0 else "R"), Vector3(0.35, 4.4, 0.35),
			Vector3(2.75 * side, 3.0, 3.8), "e1_timber")
		spoke.rotation_degrees = Vector3(35.0, 0, 0)
		intact.add_child(spoke)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(kit.box("Wreck", Vector3(5.2, 0.6, 8.8), Vector3(0.3, 0.3, 0.6), "e1_split"))
	var stock := kit.box("StockFallen", Vector3(1.0, 0.8, 9.0), Vector3(1.6, 0.9, -0.6), "e1_timber_dark")
	stock.rotation_degrees = Vector3(0, 28, 9)
	broken.add_child(stock)
	var fallen := kit.cyl("DrumFallen", 1.25, 1.25, 4.0, Vector3(-1.8, 1.25, 4.6), "e1_chain")
	fallen.rotation_degrees = Vector3(0, 30, 90)
	broken.add_child(fallen)
	root.add_child(broken)
	var block := CollisionShape3D.new()
	block.name = "BlockBody"
	block.shape = kit.box_shape(Vector3(6.2, 5.2, 10.4))
	block.position = Vector3(0, 2.6, 0.6)
	root.add_child(block)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(Vector3(7.0, 7.5, 11.0)), Vector3(0, 3.75, 0.5)))
	root.add_child(hb)
	return BBmerge(kit, root)


static func BBmerge(kit: SceneKit, root: Node3D) -> Node3D:
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


## Harrok as the giant's ally (HarrokAlly, no combat entity): the rival giants' Visual at his 15 m.
static func build_ally(kit: SceneKit) -> Node:
	var root := CharacterBody3D.new()
	root.name = "HarrokAlly"
	kit.scripted(root, S_ALLY, {})
	root.collision_layer = 0
	root.collision_mask = SceneKit.L_WORLD
	_capsule(kit, root, 3.2, 15.0)
	root.add_child(BB.giant_visual(kit, 15.0))
	return root


static func build_throne_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var orrik: Node3D = kit.instance(ORRIK)
	if player == null or orrik == null:
		push_error("e1: build the player scene first")
		for n: Node in [player, orrik]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "ThroneTest"
	kit.scripted(root, S_LEVEL, {"level_id": "level.throne_test"})
	HB._add_environment(root)
	var floor_size := Vector3(520, 1, 520)
	var gate_deg := 90.0   # (+Z)
	var solids := BB.ring_solids(MOOT_RADIUS, MOOT_WALL_H, 48, floor_size, [[gate_deg, MOOT_GATE_HALF]])
	for sd: Dictionary in solids:
		sd["mat"] = "e1_moot_dark" if str(sd.name) != "Floor" else "e1_moot_turf"
	for i in MOOT_STONES:
		var a := TAU * (float(i) + 0.5) / MOOT_STONES
		var at := Vector3(cos(a), 0, sin(a)) * (MOOT_RADIUS + 3.0)
		if absf(wrapf(a - deg_to_rad(gate_deg), -PI, PI)) < deg_to_rad(18.0):
			continue
		solids.append({"name": "Stone%02d" % i, "shape": "box",
			"xform": Transform3D(Basis(Vector3.UP, -a), at + Vector3.UP * 7.5), "size": Vector3(3, 15, 6),
			"mat": "e1_moot_stone", "nav": "obstacle"})
	solids.append({"name": "ThroneSeat", "shape": "box", "xform": Transform3D(Basis(), THRONE_AT + Vector3(0, 3, 0)),
		"size": Vector3(10, 6, 8), "mat": "e1_moot_stone", "nav": "obstacle"})
	solids.append({"name": "ThroneBack", "shape": "box", "xform": Transform3D(Basis(), THRONE_AT + Vector3(0, 10, -4.5)),
		"size": Vector3(11, 20, 2.5), "mat": "e1_moot_stone", "nav": "obstacle"})
	BB._add_solids(kit, root, solids, floor_size)
	var floor_mesh := root.get_node_or_null("Geometry/Floor/Mesh") as MeshInstance3D
	if floor_mesh != null:
		floor_mesh.material_override = kit.mats["e1_moot_turf"]
	BB._add_nav(kit, root, solids, [BB.NAV_TITAN])
	root.add_child(BB._engage_trigger(kit, ENGAGE_ID, Vector3(0, 0, MOOT_RADIUS - 10.0), Vector3(30, 30, 8)))
	var props := kit.n3("Props")
	for w: Array in WINCHES:
		var winch: Node3D = kit.instance(WINCH)
		if winch == null:
			continue
		winch.name = str(w[0]).get_slice(".", 2).capitalize().replace(" ", "")
		winch.set("world_id", str(w[0]))
		winch.set("boss_id", ORRIK_ID)
		winch.set("join_phase", int(w[3]))
		var at := Vector3(float(w[1]), 0, float(w[2]))
		winch.position = at
		winch.rotation.y = TargetingRules.yaw_of(-at)
		props.add_child(winch)
	root.add_child(props)
	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_CHALLENGE, {"boss_id": ORRIK_ID, "encounter_id": "", "engage_area_id": ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": MOOT_RADIUS + 30.0,
		"defeated_flag": "test.throne.defeated", "warband_encounter": "encounter.throne_test_warband",
		"ally_at": ALLY_AT})
	root.add_child(arena)
	root.add_child(kit.scripted(kit.n3("DebrisPool"), S_DEBRIS))
	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", PLAYER_AT), S_CHECKPOINT,
		{"checkpoint_id": "test.throne.cp_start"}))
	root.add_child(checkpoints)
	root.add_child(kit.n3("Spawned"))
	orrik.name = "Orrik"
	orrik.set("entity_id", ORRIK_ID)
	orrik.position = ORRIK_AT
	root.add_child(orrik)
	BB._place_player(kit, root, player, PLAYER_AT, 0.0)
	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)
	BB._sign(kit, root, "THE MOOT TEST: Orrik the Fetterer and the Skarn's fetter-winches", PLAYER_AT + Vector3(0, 14, -10))
	return root
