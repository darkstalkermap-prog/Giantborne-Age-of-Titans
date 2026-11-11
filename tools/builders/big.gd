extends RefCounted
## Builder (P34, plan M6-M9 §3.18): the larger creatures, the rival giants, Corvane and the three
## boss test levels.
##   scenes/enemies/troll.tscn            TrollEnemy (enemy.troll): the ogre's body plan (heavy.gd) at
##                                        5.5 m, mossy and long-armed; Anchors/Grab for two hands.
##   scenes/enemies/troll_whelp.tscn      TrollEnemy (enemy.troll_whelp) at 3.5 m; Anchors/Grab.
##   scenes/enemies/troll_matriarch.tscn  TrollEnemy (enemy.troll_matriarch) at 9 m with a bone crown
##                                        and a hide mantle; no Grab anchor (never grabbable).
##   scenes/enemies/dire_wolf.tscn        WolfEnemy (enemy.dire_wolf): the wolf's body plan at twice
##                                        its size (1.8 m), darker, with a scruff anchor.
##   scenes/enemies/rival_giant.tscn      RivalGiantEnemy (enemy.rival_giant): a 10 m giant in hides
##                                        with a 4.5 m axe; shoulders at (0.135, 0.73) x its height.
##   scenes/enemies/harrok.tscn           RivalGiantEnemy (enemy.harrok): the same body at 15 m, braided,
##                                        with a bronze-bound axe.
##   scenes/enemies/corvane.tscn          SoldierEnemy (enemy.corvane): the soldier's body at 2.0 m in a
##                                        warlord's cloak with a longsword.
##   scenes/test/troll_den_test.tscn      the den: a 30 m ring wall with a south entrance and the back
##                                        wall's 12 m opening to the north (the drive-out exit marker
##                                        world.marker.troll_den_exit beyond it), the fire pit (group
##                                        fire_pits, r 4 m) at the centre, the Matriarch and two whelps,
##                                        a BossArena without a gate, titan (16) and large (2) navmeshes.
##   scenes/test/moot_test.tscn           the Moot's ring: a 60 m wall of stones with a south entrance,
##                                        Harrok, two clan watchers outside the ring (rival giants of the
##                                        neutral faction.test_moot_clans, AI off: they only watch), a
##                                        BossArena without a gate,
##                                        the titan navmesh.
##   scenes/test/bailey_test.tscn         a LevelRoot (level.bailey_test): a 120 x 90 m bailey with its
##                                        gate to the south, the BattleBoss of battle.iron_regiment over
##                                        three test encounters (the wall, the charge, the last stand),
##                                        the director, human (1) and large (2) navmeshes.
## Every enemy body has the BodyShape, CombatEntity, Anchors (Torso and two knee lock anchors on the
## big ones), Hurtboxes, NavAgent and an ActorRig (QuadrupedRig for the wolf) Visual with its parts
## merged per pivot (P22) and Visual/LodProxy. Gameplay numbers live in the records; each record's
## weapon_pivot_m matches the weapon shoulder built here. Colours are this builder's own (in the scenes,
## not in the shared palette).

const HB := preload("res://tools/builders/heavy.gd")
const FB := preload("res://tools/builders/formations.gd")
const TD := preload("res://tools/builders/test_director.gd")

const S_TROLL := "res://scripts/actors/troll_enemy.gd"
const S_GIANT := "res://scripts/actors/rival_giant_enemy.gd"
const S_WOLF := "res://scripts/actors/wolf_enemy.gd"
const S_QUAD_RIG := "res://scripts/presentation/quadruped_rig.gd"
const S_SOLDIER := "res://scripts/actors/soldier_enemy.gd"
const S_ARENA := "res://scripts/world/boss_arena.gd"
const S_BATTLE := "res://scripts/world/battle_boss.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_LEVEL := "res://scripts/world/level_root.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const GIANT := "res://scenes/player/giant.tscn"

const TROLL := "res://scenes/enemies/troll.tscn"
const WHELP := "res://scenes/enemies/troll_whelp.tscn"
const MATRIARCH := "res://scenes/enemies/troll_matriarch.tscn"
const DIRE_WOLF := "res://scenes/enemies/dire_wolf.tscn"
const RIVAL := "res://scenes/enemies/rival_giant.tscn"
const HARROK := "res://scenes/enemies/harrok.tscn"
const CORVANE := "res://scenes/enemies/corvane.tscn"
const DEN_TEST := "res://scenes/test/troll_den_test.tscn"
const MOOT_TEST := "res://scenes/test/moot_test.tscn"
const BAILEY_TEST := "res://scenes/test/bailey_test.tscn"

const COLORS := {
	"p34_troll_skin": Color(0.36, 0.45, 0.34),
	"p34_troll_hide": Color(0.33, 0.27, 0.19),
	"p34_troll_moss": Color(0.24, 0.36, 0.16),
	"p34_matriarch_skin": Color(0.30, 0.38, 0.30),
	"p34_bone": Color(0.86, 0.82, 0.70),
	"p34_dire_fur": Color(0.27, 0.26, 0.25),
	"p34_dire_dark": Color(0.12, 0.11, 0.11),
	"p34_dire_eye": Color(0.95, 0.40, 0.18),
	"p34_rival_skin": Color(0.66, 0.50, 0.40),
	"p34_rival_hide": Color(0.42, 0.33, 0.24),
	"p34_rival_hair": Color(0.30, 0.20, 0.12),
	"p34_axe_haft": Color(0.38, 0.27, 0.16),
	"p34_axe_head": Color(0.56, 0.58, 0.62),
	"p34_harrok_skin": Color(0.60, 0.46, 0.36),
	"p34_harrok_bronze": Color(0.70, 0.50, 0.22),
	"p34_harrok_hair": Color(0.62, 0.60, 0.56),
	"p34_corvane_cloak": Color(0.36, 0.06, 0.08),
	"p34_iron": Color(0.30, 0.31, 0.34),
	"p34_fire": Color(1.0, 0.45, 0.10),
	"p34_ash": Color(0.16, 0.14, 0.13),
}

## The ogre body's height (heavy.gd: s = 1 is 3.4 m).
const OGRE_H := 3.4
## Navigation agents (tools/world/nav_bake.gd's layers).
const NAV_TITAN := {"layer": 16, "node": "Titan", "radius": 4.0, "height": 19.0, "climb": 2.0, "cell": 1.0}
const NAV_LARGE := {"layer": 2, "node": "Large", "radius": 1.5, "height": 6.0, "climb": 0.5, "cell": 0.5}
const NAV_HUMAN := {"layers": 1, "radius": 0.6, "height": 2.0, "cell": 0.3, "cell_height": 0.25,
	"climb": 0.25, "slope": 35.0}

## The den (troll_den_test).
const DEN_ID := "test.den.matriarch"
const DEN_ENGAGE_ID := "test.area.den_engage"
const DEN_RADIUS := 30.0
const DEN_EXIT := Vector3(0, 0, -42)
const DEN_PIT := Vector3(0, 0, 6)
const DEN_PLAYER := Vector3(0, 0.05, 44)
const DEN_MATRIARCH := Vector3(0, 0.05, -14)
const DEN_WHELPS := [["test.den.whelp_1", Vector3(-9, 0.05, -6)], ["test.den.whelp_2", Vector3(9, 0.05, -6)]]
## The Moot (moot_test).
const MOOT_ID := "test.moot.harrok"
const MOOT_ENGAGE_ID := "test.area.moot_engage"
const MOOT_RADIUS := 60.0
const MOOT_PLAYER := Vector3(0, 0.05, 80)
const MOOT_HARROK := Vector3(0, 0.05, -24)
const MOOT_WATCHERS := [["test.moot.watcher_1", Vector3(-80, 0.05, -20)], ["test.moot.watcher_2", Vector3(80, 0.05, -20)]]
## The bailey (bailey_test, a LevelRoot).
const BAILEY_LEVEL := "level.bailey_test"
const BAILEY_ID := "battle.iron_regiment"
const BAILEY_ENGAGE_ID := "test.area.bailey_engage"
const BAILEY_PLAYER := Vector3(0, 0.05, 70)
const BAILEY_BOXES := [
	["Floor", Vector3(200, 1, 200), Vector3(0, -0.5, 0), true],
	["WallNorth", Vector3(124, 12, 2), Vector3(0, 6, -46), false],
	["WallEast", Vector3(2, 12, 94), Vector3(61, 6, 0), false],
	["WallWest", Vector3(2, 12, 94), Vector3(-61, 6, 0), false],
	["WallSouthWest", Vector3(52, 12, 2), Vector3(-35, 6, 46), false],
	["WallSouthEast", Vector3(52, 12, 2), Vector3(35, 6, 46), false],
]


static func build_all(kit: SceneKit) -> void:
	for c: String in COLORS:
		if not kit.mats.has(c):
			var m := StandardMaterial3D.new()
			m.albedo_color = COLORS[c]
			m.roughness = 0.9
			kit.mats[c] = m
	if not kit.mats.has("ogre_tusk"):   # heavy.gd's (the ogre body's tusks) when only this builder runs
		var tusk := StandardMaterial3D.new()
		tusk.albedo_color = Color(0.92, 0.88, 0.74)
		kit.mats["ogre_tusk"] = tusk
	kit.save(build_troll(kit, "Troll", "troll_01", "enemy.troll", 5.5, 1.4, true), TROLL)
	kit.save(build_troll(kit, "TrollWhelp", "troll_whelp_01", "enemy.troll_whelp", 3.5, 0.9, true), WHELP)
	kit.save(build_troll(kit, "TrollMatriarch", "troll_matriarch_01", "enemy.troll_matriarch", 9.0, 2.4, false), MATRIARCH)
	kit.save(build_dire_wolf(kit), DIRE_WOLF)
	kit.save(build_giant(kit, "RivalGiant", "rival_giant_01", "enemy.rival_giant", 10.0, 2.2, false), RIVAL)
	kit.save(build_giant(kit, "Harrok", "harrok_01", "enemy.harrok", 15.0, 3.2, true), HARROK)
	kit.save(build_corvane(kit), CORVANE)
	for spec: Array in [[DEN_TEST, build_den_test], [MOOT_TEST, build_moot_test], [BAILEY_TEST, build_bailey_test]]:
		var level: Node = (spec[1] as Callable).call(kit)
		if level != null:
			kit.save(level, spec[0])


# --------------------------------------------------------------------------- trolls

## A troll of height `h` on the ogre's body plan (TrollEnemy): mossy shoulders, a long nose and
## hanging arms; the Matriarch (`grab` false) also wears a bone crown and a hide mantle.
static func build_troll(kit: SceneKit, node_name: String, entity_id: String, definition: String, h: float,
		radius: float, grab: bool) -> Node:
	var s := h / OGRE_H
	var matriarch := definition == "enemy.troll_matriarch"
	var skin := "p34_matriarch_skin" if matriarch else "p34_troll_skin"
	var parts: Dictionary = HB._ogre_body(kit, node_name, S_TROLL, entity_id, definition, s, radius, skin,
		"p34_troll_hide", grab)
	var torso: Node3D = parts.torso
	torso.add_child(kit.box("Nose", Vector3(0.16, 0.14, 0.34) * s, Vector3(0, 1.74, -0.48) * s, skin))
	torso.add_child(kit.box("Moss", Vector3(1.7, 0.18, 0.9) * s, Vector3(0, 1.6, 0.12) * s, "p34_troll_moss"))
	torso.add_child(kit.box("Hump", Vector3(1.1, 0.5, 0.5) * s, Vector3(0, 1.45, 0.5) * s, skin))
	if matriarch:
		torso.add_child(kit.box("Mantle", Vector3(1.8, 0.3, 1.25) * s, Vector3(0, 1.5, 0.05) * s, "p34_troll_hide"))
		for i in 5:
			var x := (-0.3 + 0.15 * i) * s
			torso.add_child(kit.box("Crown%d" % (i + 1), Vector3(0.08, 0.26, 0.08) * s, Vector3(x, 2.2, -0.2) * s,
				"p34_bone"))
	kit.merge_rig(parts.body, {"ShoulderR": [["Weapon", ["Club"]]]})
	return parts.root


# --------------------------------------------------------------------------- the dire wolf

## The wolf's body plan (wolf.gd) at twice its size, darker, its eyes ember-red (WolfEnemy).
static func build_dire_wolf(kit: SceneKit) -> Node:
	var s := 2.0
	var root := CharacterBody3D.new()
	root.name = "DireWolf"
	kit.scripted(root, S_WOLF, {"entity_id": "dire_wolf_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.6
	cap.height = 1.8
	cs.shape = cap
	cs.position = Vector3(0, 0.9, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("dire_wolf_01", "enemy.dire_wolf", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 0.55, 0) * s))
	anchors.add_child(kit.marker("Grab", Vector3(0, 0.74, -0.3) * s))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.18 * s
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 0.64, -0.55) * s))
	hb.add_child(kit.hurtbox("Body", "torso", kit.box_shape(Vector3(0.42, 0.42, 0.95) * s), Vector3(0, 0.52, 0) * s))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.38, 0.34, 0.85) * s), Vector3(0, 0.17, 0) * s))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, S_QUAD_RIG, {"body_path": NodePath("Body"), "head_path": NodePath("Body/Head"),
		"tail_path": NodePath("Body/Tail"), "leg_fl_path": NodePath("Body/LegFL"),
		"leg_fr_path": NodePath("Body/LegFR"), "leg_bl_path": NodePath("Body/LegBL"),
		"leg_br_path": NodePath("Body/LegBR")})
	var body := kit.n3("Body")
	visual.add_child(body)
	body.add_child(kit.box("Torso", Vector3(0.36, 0.34, 0.86) * s, Vector3(0, 0.55, 0.04) * s, "p34_dire_fur"))
	body.add_child(kit.box("Chest", Vector3(0.4, 0.4, 0.3) * s, Vector3(0, 0.56, -0.3) * s, "p34_dire_fur"))
	body.add_child(kit.box("Ruff", Vector3(0.44, 0.22, 0.24) * s, Vector3(0, 0.76, -0.32) * s, "p34_dire_dark"))
	body.add_child(kit.box("Spine", Vector3(0.12, 0.08, 0.7) * s, Vector3(0, 0.74, 0.08) * s, "p34_dire_dark"))
	var head := kit.n3("Head", Vector3(0, 0.64, -0.44) * s)
	head.add_child(kit.box("Skull", Vector3(0.26, 0.24, 0.26) * s, Vector3(0, 0.04, -0.1) * s, "p34_dire_fur"))
	head.add_child(kit.box("Snout", Vector3(0.14, 0.12, 0.24) * s, Vector3(0, -0.02, -0.33) * s, "p34_dire_dark"))
	head.add_child(kit.box("Jaw", Vector3(0.12, 0.05, 0.2) * s, Vector3(0, -0.09, -0.3) * s, "p34_dire_dark"))
	head.add_child(kit.box("EarL", Vector3(0.06, 0.12, 0.05) * s, Vector3(-0.08, 0.2, -0.04) * s, "p34_dire_dark"))
	head.add_child(kit.box("EarR", Vector3(0.06, 0.12, 0.05) * s, Vector3(0.08, 0.2, -0.04) * s, "p34_dire_dark"))
	head.add_child(kit.box("EyeL", Vector3(0.04, 0.04, 0.02) * s, Vector3(-0.07, 0.08, -0.23) * s, "p34_dire_eye"))
	head.add_child(kit.box("EyeR", Vector3(0.04, 0.04, 0.02) * s, Vector3(0.07, 0.08, -0.23) * s, "p34_dire_eye"))
	body.add_child(head)
	var tail := kit.n3("Tail", Vector3(0, 0.64, 0.46) * s)
	var brush := kit.box("Brush", Vector3(0.09, 0.09, 0.44) * s, Vector3(0, -0.07, 0.2) * s, "p34_dire_fur")
	brush.rotation_degrees = Vector3(20, 0, 0)
	tail.add_child(brush)
	body.add_child(tail)
	for leg_name: String in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var x := (-0.12 if leg_name.ends_with("L") else 0.12) * s
		var z := (-0.3 if leg_name.begins_with("LegF") else 0.3) * s
		var hip := kit.n3(leg_name, Vector3(x, 0.42 * s, z))
		hip.add_child(kit.box("Leg", Vector3(0.1, 0.4, 0.1) * s, Vector3(0, -0.2, 0) * s, "p34_dire_fur"))
		hip.add_child(kit.box("Paw", Vector3(0.12, 0.06, 0.15) * s, Vector3(0, -0.39, -0.03) * s, "p34_dire_dark"))
		body.add_child(hip)
	kit.merge_rig(body)
	visual.add_child(kit.lod_proxy(Vector3(0.42, 0.62, 1.0) * s, Vector3(0, 0.36, 0) * s, "p34_dire_fur"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- rival giants

## A rival giant `h` metres tall (RivalGiantEnemy): broad legs and torso, a bearded head, arms from
## shoulders at (0.135, 0.73) x h, a 4.5 m (x h / 10) axe in the weapon hand. Harrok wears braids and
## a bronze-bound axe. Lock anchors at the torso and both knees; no Grab anchor.
static func build_giant(kit: SceneKit, node_name: String, entity_id: String, definition: String, h: float,
		radius: float, harrok: bool) -> Node:
	var u := h / 10.0
	var skin := "p34_harrok_skin" if harrok else "p34_rival_skin"
	var hair := "p34_harrok_hair" if harrok else "p34_rival_hair"
	var root := CharacterBody3D.new()
	root.name = node_name
	kit.scripted(root, S_GIANT, {"entity_id": entity_id})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = h
	cs.shape = cap
	cs.position = Vector3(0, h * 0.5, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity(entity_id, definition, 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 6.2, 0) * u))
	anchors.add_child(kit.marker("KneeL", Vector3(-0.8, 2.4, -0.2) * u))
	anchors.add_child(kit.marker("KneeR", Vector3(0.8, 2.4, -0.2) * u))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.75 * u
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 9.0, -0.1) * u))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(3.2, 3.4, 2.0) * u), Vector3(0, 6.2, 0) * u))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(2.6, 4.6, 1.6) * u), Vector3(0, 2.3, 0) * u))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 3.4 * u, "leg_swing_rad": 0.5,
		"idle_arm_pose": Vector2(12, -72), "off_idle_pose": Vector2(-12, -76), "block_pose": Vector2(-30, 10)})
	var body := kit.n3("Body")
	visual.add_child(body)
	for side in [-1.0, 1.0]:
		var hip := kit.n3("HipL" if side < 0 else "HipR", Vector3(0.7 * side, 4.4, 0) * u)
		hip.add_child(kit.box("Leg", Vector3(1.1, 4.2, 1.2) * u, Vector3(0, -2.1, 0) * u, skin))
		hip.add_child(kit.box("Wrap", Vector3(1.2, 1.4, 1.3) * u, Vector3(0, -0.6, 0) * u, "p34_rival_hide"))
		hip.add_child(kit.box("Foot", Vector3(1.2, 0.35, 1.7) * u, Vector3(0, -4.2, -0.25) * u, "p34_rival_hide"))
		body.add_child(hip)
	var torso := kit.n3("Torso", Vector3(0, 4.4, 0) * u)
	torso.add_child(kit.box("Belly", Vector3(2.6, 1.6, 1.8) * u, Vector3(0, 0.7, 0) * u, "p34_rival_hide"))
	torso.add_child(kit.box("Chest", Vector3(3.0, 1.9, 1.7) * u, Vector3(0, 2.3, 0) * u, skin))
	torso.add_child(kit.box("Belt", Vector3(2.7, 0.35, 1.9) * u, Vector3(0, 0.1, 0) * u, "giant_belt"))
	torso.add_child(kit.box("Head", Vector3(1.2, 1.4, 1.2) * u, Vector3(0, 4.2, -0.1) * u, skin))
	torso.add_child(kit.box("Beard", Vector3(1.1, 0.9, 0.4) * u, Vector3(0, 3.7, -0.62) * u, hair))
	torso.add_child(kit.box("Hair", Vector3(1.3, 0.5, 1.3) * u, Vector3(0, 4.95, 0) * u, hair))
	torso.add_child(kit.box("EyeL", Vector3(0.14, 0.1, 0.06) * u, Vector3(-0.28, 4.4, -0.72) * u, "eyes"))
	torso.add_child(kit.box("EyeR", Vector3(0.14, 0.1, 0.06) * u, Vector3(0.28, 4.4, -0.72) * u, "eyes"))
	if harrok:
		torso.add_child(kit.box("BraidL", Vector3(0.25, 1.6, 0.25) * u, Vector3(-0.55, 3.6, 0.3) * u, hair))
		torso.add_child(kit.box("BraidR", Vector3(0.25, 1.6, 0.25) * u, Vector3(0.55, 3.6, 0.3) * u, hair))
		torso.add_child(kit.box("Torc", Vector3(1.3, 0.25, 1.3) * u, Vector3(0, 3.3, 0) * u, "p34_harrok_bronze"))
	body.add_child(torso)
	for side in [-1.0, 1.0]:
		var shoulder := kit.n3("ShoulderL" if side < 0 else "ShoulderR", Vector3(1.35 * side, 7.3, 0) * u)
		shoulder.basis = SceneKit.arm_basis(12.0 * side, -72.0)
		shoulder.add_child(kit.box("UpperArm", Vector3(0.8, 0.8, 1.4) * u, Vector3(0, 0, -0.7) * u, skin))
		shoulder.add_child(kit.box("Forearm", Vector3(0.75, 0.75, 1.3) * u, Vector3(0, 0, -2.0) * u, skin))
		shoulder.add_child(kit.box("Hand", Vector3(0.8, 0.8, 0.7) * u, Vector3(0, 0, -2.8) * u, skin))
		if side > 0:
			shoulder.add_child(kit.box("Haft", Vector3(0.28, 0.28, 4.5) * u, Vector3(0, 0, -2.6 - 2.25) * u, "p34_axe_haft"))
			var head_mat := "p34_harrok_bronze" if harrok else "p34_axe_head"
			shoulder.add_child(kit.box("AxeHead", Vector3(0.2, 1.6, 1.1) * u, Vector3(0, 0.55, -6.6) * u, head_mat))
		body.add_child(shoulder)
	kit.merge_rig(body, {"ShoulderR": [["Weapon", ["Haft", "AxeHead"]]]})
	visual.add_child(kit.lod_proxy(Vector3(3.0, 10.0, 1.8) * u, Vector3(0, 5.0, 0) * u, skin))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- Corvane

## Warlord Corvane (SoldierEnemy, enemy.corvane): the soldier's body (formations.gd) at 2.0 m - the
## Visual scaled by 2.0 / 1.8 - with a cloak, a crested helm and a longsword.
static func build_corvane(kit: SceneKit) -> Node:
	var k := 2.0 / 1.8
	var root := CharacterBody3D.new()
	root.name = "Corvane"
	kit.scripted(root, S_SOLDIER, {"entity_id": "corvane_01"})
	root.collision_layer = SceneKit.L_ACTORS
	root.collision_mask = SceneKit.ACTOR_MASK
	var cs := CollisionShape3D.new()
	cs.name = "BodyShape"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 2.0
	cs.shape = cap
	cs.position = Vector3(0, 1.0, 0)
	root.add_child(cs)
	root.add_child(kit.combat_entity("corvane_01", "enemy.corvane", 2))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Torso", Vector3(0, 1.28, 0)))
	anchors.add_child(kit.marker("Grab", Vector3(0, 1.33, 0)))
	root.add_child(anchors)
	var hb := kit.n3("Hurtboxes")
	var head_shape := SphereShape3D.new()
	head_shape.radius = 0.19
	hb.add_child(kit.hurtbox("Head", "head", head_shape, Vector3(0, 1.81, 0)))
	hb.add_child(kit.hurtbox("Torso", "torso", kit.box_shape(Vector3(0.6, 0.72, 0.36)), Vector3(0, 1.28, 0)))
	hb.add_child(kit.hurtbox("Legs", "legs", kit.box_shape(Vector3(0.5, 0.94, 0.34)), Vector3(0, 0.47, 0)))
	root.add_child(hb)
	var agent := NavigationAgent3D.new()
	agent.name = "NavAgent"
	root.add_child(agent)
	var visual := kit.n3("Visual")
	visual.scale = Vector3(k, k, k)
	kit.scripted(visual, SceneKit.S_RIG, {"weapon_arm_path": NodePath("Body/ShoulderR"),
		"off_arm_path": NodePath("Body/ShoulderL"), "leg_left_path": NodePath("Body/HipL"),
		"leg_right_path": NodePath("Body/HipR"), "torso_path": NodePath("Body/Torso"),
		"body_path": NodePath("Body"), "stride_length_m": 0.9, "leg_swing_rad": 0.6,
		"idle_arm_pose": Vector2(15.0, -70.0), "off_idle_pose": Vector2(-18.0, -60.0), "block_pose": Vector2(-30.0, 10.0)})
	var body := kit.n3("Body")
	visual.add_child(body)
	FB._add_body(kit, body, "p34_corvane_cloak")
	var torso := body.get_node("Torso") as Node3D
	torso.add_child(kit.box("Cloak", Vector3(0.56, 0.9, 0.06), Vector3(0, 0.2, 0.2), "p34_corvane_cloak"))
	torso.add_child(kit.box("Crest", Vector3(0.05, 0.16, 0.34), Vector3(0, 1.05, 0.02), "p34_corvane_cloak"))
	var arm := body.get_node("ShoulderR") as Node3D
	arm.add_child(kit.box("Grip", Vector3(0.05, 0.05, 0.2), Vector3(0, 0, -0.5), "giant_belt"))
	arm.add_child(kit.box("Guard", Vector3(0.26, 0.04, 0.05), Vector3(0, 0, -0.6), "steel"))
	arm.add_child(kit.box("Blade", Vector3(0.07, 0.02, 0.95), Vector3(0, 0, -0.6 - 0.475), "steel"))
	kit.merge_rig(body, {"ShoulderR": [["Weapon", ["Grip", "Guard", "Blade"]]]})
	visual.add_child(kit.lod_proxy(Vector3(0.5, 1.8, 0.35), Vector3(0, 0.9, 0), "p34_corvane_cloak"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- shared level parts

## Solids of a ring arena of inner radius `r` (heavy.gd's solid dictionaries): the floor and the wall
## in `segments` pieces leaving `gaps` ([centre angle in degrees, half width m]) open.
static func ring_solids(r: float, height: float, segments: int, floor_size: Vector3, gaps: Array) -> Array:
	var out: Array = []
	out.append({"name": "Floor", "shape": "box", "xform": Transform3D(Basis(), Vector3(0, -0.5, 0)), "size": floor_size,
		"mat": "stone", "nav": "ground"})
	var t := 2.0
	var wall_r := r + t * 0.5
	for i in segments:
		var a0 := TAU * float(i) / segments
		var a1 := TAU * float(i + 1) / segments
		var mid := (a0 + a1) * 0.5
		var open := false
		for g: Array in gaps:
			var half := asin(clampf(float(g[1]) / wall_r, 0.0, 1.0))
			if absf(wrapf(mid - deg_to_rad(float(g[0])), -PI, PI)) <= half + (a1 - a0) * 0.5:
				open = true
		if open:
			continue
		var p0 := Vector3(cos(a0), 0, sin(a0)) * wall_r
		var p1 := Vector3(cos(a1), 0, sin(a1)) * wall_r
		var dir := (p1 - p0).normalized()
		p0 -= dir * t * 0.5
		p1 += dir * t * 0.5
		out.append({"name": "Wall%02d" % i, "shape": "box",
			"xform": Transform3D(Basis(Vector3.UP, TargetingRules.yaw_of(p1 - p0)), (p0 + p1) * 0.5 + Vector3.UP * height * 0.5),
			"size": Vector3(t, height, p0.distance_to(p1)), "mat": "stone_dark", "nav": "obstacle"})
	return out


static func _add_solids(kit: SceneKit, root: Node3D, solids: Array, floor_size: Vector3) -> void:
	var geometry := kit.n3("Geometry")
	for sd: Dictionary in solids:
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
			plane.size = Vector2(floor_size.x, floor_size.z)
			mesh.mesh = plane
			mesh.position = Vector3(0, floor_size.y * 0.5, 0)
			mesh.material_override = kit.mats["ground"]
			body.add_child(mesh)
		else:
			body.add_child(kit.box("Mesh", sd.size, Vector3.ZERO, str(sd.mat)))
		geometry.add_child(body)
	root.add_child(geometry)


static func _add_nav(kit: SceneKit, root: Node3D, solids: Array, specs: Array) -> void:
	var nav := kit.n3("Navigation")
	for spec: Dictionary in specs:
		var region := NavigationRegion3D.new()
		region.name = str(spec.node)
		region.navigation_layers = int(spec.layer)
		region.use_edge_connections = false
		region.navigation_mesh = HB.bake_layer(spec, solids)
		nav.add_child(region)
	root.add_child(nav)


static func _engage_trigger(kit: SceneKit, area_id: String, pos: Vector3, size: Vector3) -> Node3D:
	var triggers := kit.n3("Triggers")
	var trig := Area3D.new()
	trig.name = area_id.validate_node_name()
	trig.position = pos
	kit.scripted(trig, S_TRIGGER, {"area_id": area_id, "once": false})
	trig.collision_layer = 0
	trig.collision_mask = SceneKit.L_ACTORS
	trig.monitoring = true
	trig.monitorable = false
	var tcs := CollisionShape3D.new()
	tcs.name = "Shape"
	tcs.shape = kit.box_shape(size)
	tcs.position = Vector3(0, size.y * 0.5, 0)
	trig.add_child(tcs)
	triggers.add_child(trig)
	return triggers


static func _place_player(kit: SceneKit, root: Node3D, player: Node3D, pos: Vector3, yaw: float) -> void:
	var spawns := kit.n3("Spawns")
	var spawn := kit.marker("PlayerSpawn", pos)
	spawn.rotation.y = yaw
	spawns.add_child(spawn)
	root.add_child(spawns)
	player.name = "Player"
	player.position = pos
	player.rotation.y = yaw
	root.add_child(player)


static func _sign(kit: SceneKit, root: Node3D, text: String, pos: Vector3) -> void:
	var signs := root.get_node_or_null("Signs") as Node3D
	if signs == null:
		signs = kit.n3("Signs")
		root.add_child(signs)
	var s := kit.sign(text, pos)
	s.name = "Sign%d" % signs.get_child_count()
	s.visibility_range_end = 120.0
	signs.add_child(s)


# --------------------------------------------------------------------------- the den

static func build_den_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var matriarch: Node3D = kit.instance(MATRIARCH)
	if player == null or matriarch == null:
		push_error("big: build the player scene first")
		for n: Node in [player, matriarch]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "TrollDenTest"
	HB._add_environment(root)
	var floor_size := Vector3(160, 1, 160)
	var solids := ring_solids(DEN_RADIUS, 10.0, 28, floor_size, [[90.0, 6.0], [-90.0, 6.0]])
	_add_solids(kit, root, solids, floor_size)
	_add_nav(kit, root, solids, [NAV_TITAN, NAV_LARGE])
	root.add_child(_engage_trigger(kit, DEN_ENGAGE_ID, Vector3(0, 0, DEN_RADIUS - 6.0), Vector3(12, 8, 6)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_ARENA, {"boss_id": DEN_ID, "encounter_id": "", "engage_area_id": DEN_ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": DEN_RADIUS,
		"defeated_flag": "test.den.defeated"})
	root.add_child(arena)
	var pit := kit.n3("FirePit", DEN_PIT)
	pit.add_to_group("fire_pits", true)
	pit.set_meta("radius_m", 4.0)
	pit.add_child(kit.cyl("Ash", 4.0, 4.0, 0.12, Vector3(0, 0.06, 0), "p34_ash"))
	pit.add_child(kit.cyl("Embers", 2.6, 3.2, 0.4, Vector3(0, 0.2, 0), "p34_fire"))
	root.add_child(pit)
	var markers := kit.n3("Markers")
	markers.add_child(kit.scripted(kit.marker("DenExit", DEN_EXIT), S_MARKER,
		{"marker_id": "world.marker.troll_den_exit", "kind": 0, "faction": ""}))
	root.add_child(markers)
	matriarch.name = "TrollMatriarch"
	matriarch.set("entity_id", DEN_ID)
	matriarch.position = DEN_MATRIARCH
	root.add_child(matriarch)
	for spec: Array in DEN_WHELPS:
		var w: Node3D = kit.instance(WHELP)
		w.name = str(spec[0]).validate_node_name()
		w.set("entity_id", spec[0])
		w.position = spec[1]
		root.add_child(w)
	_place_player(kit, root, player, DEN_PLAYER, 0.0)
	_sign(kit, root, "TROLL DEN TEST: the Matriarch, two whelps, the fire pit", DEN_PLAYER + Vector3(0, 6, -6))
	_sign(kit, root, "THE BACK WALL (the drive-out exit)", DEN_EXIT + Vector3(0, 8, 2))
	return root


# --------------------------------------------------------------------------- the Moot

static func build_moot_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var harrok: Node3D = kit.instance(HARROK)
	if player == null or harrok == null:
		push_error("big: build the player scene first")
		for n: Node in [player, harrok]:
			if n != null:
				n.free()
		return null
	var root := Node3D.new()
	root.name = "MootTest"
	HB._add_environment(root)
	var floor_size := Vector3(240, 1, 240)
	var solids := ring_solids(MOOT_RADIUS, 14.0, 40, floor_size, [[90.0, 9.0]])
	_add_solids(kit, root, solids, floor_size)
	_add_nav(kit, root, solids, [NAV_TITAN])
	root.add_child(_engage_trigger(kit, MOOT_ENGAGE_ID, Vector3(0, 0, MOOT_RADIUS - 8.0), Vector3(18, 16, 6)))
	var arena := kit.n3("BossArena")
	kit.scripted(arena, S_ARENA, {"boss_id": MOOT_ID, "encounter_id": "", "engage_area_id": MOOT_ENGAGE_ID,
		"gate_path": NodePath(""), "pillars_path": NodePath(""), "inner_radius_m": MOOT_RADIUS,
		"defeated_flag": "test.moot.defeated"})
	root.add_child(arena)
	harrok.name = "Harrok"
	harrok.set("entity_id", MOOT_ID)
	harrok.position = MOOT_HARROK
	root.add_child(harrok)
	var watchers := kit.n3("Watchers")
	for spec: Array in MOOT_WATCHERS:
		var w: Node3D = kit.instance(RIVAL)
		w.name = str(spec[0]).validate_node_name()
		w.set("entity_id", spec[0])
		w.set("ai_enabled", false)
		w.position = spec[1]
		w.rotation.y = PI * 0.5 if (spec[1] as Vector3).x > 0.0 else -PI * 0.5
		w.set("faction", "faction.test_moot_clans")   # neutral: the clans watch the duel and never strike
		watchers.add_child(w)
	root.add_child(watchers)
	_place_player(kit, root, player, MOOT_PLAYER, 0.0)
	_sign(kit, root, "THE MOOT TEST: Harrok the Unbowed (the clans watch from outside the ring)",
		MOOT_PLAYER + Vector3(0, 8, -6))
	return root


# --------------------------------------------------------------------------- the bailey

static func build_bailey_test(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("big: build the player scene first")
		return null
	var root := Node3D.new()
	root.name = "BaileyTest"
	kit.scripted(root, S_LEVEL, {"level_id": BAILEY_LEVEL})
	HB._add_environment(root)
	var world := kit.n3("World")
	for spec: Array in BAILEY_BOXES:
		var body := kit.static_box(spec[0], spec[1], spec[2], "stone")
		if spec[0] == "Floor":
			body.get_node("Mesh").free()
			var mesh := MeshInstance3D.new()
			mesh.name = "Mesh"
			var plane := PlaneMesh.new()
			plane.size = Vector2((spec[1] as Vector3).x, (spec[1] as Vector3).z)
			mesh.mesh = plane
			mesh.material_override = kit.mats["ground"]
			mesh.position = Vector3(0, 0.5, 0)
			body.add_child(mesh)
		world.add_child(body)
	root.add_child(world)
	var nav := kit.n3("Navigation")
	var human := NavigationRegion3D.new()
	human.name = "Human"
	human.navigation_layers = 1
	human.navigation_mesh = TD.bake_navmesh(NAV_HUMAN, BAILEY_BOXES)
	nav.add_child(human)
	var large := NavigationRegion3D.new()
	large.name = "Large"
	large.navigation_layers = 2
	large.navigation_mesh = TD.bake_navmesh({"radius": 1.5, "height": 6.0, "cell": 0.5, "cell_height": 0.25,
		"climb": 0.5, "slope": 35.0}, BAILEY_BOXES)
	nav.add_child(large)
	root.add_child(nav)
	root.add_child(_engage_trigger(kit, BAILEY_ENGAGE_ID, Vector3(0, 0, 40), Vector3(20, 8, 6)))
	var battle := kit.n3("BattleBoss")
	kit.scripted(battle, S_BATTLE, {"battle_id": BAILEY_ID, "battle_name": "The Iron Regiment",
		"engage_area_id": BAILEY_ENGAGE_ID, "gate_path": NodePath(""), "pillars_path": NodePath(""),
		"inner_radius_m": 50.0, "defeated_flag": "test.bailey.defeated", "commander_id": "test.bailey.corvane",
		"guard_formation": "guard",
		"phases": [{"id": "wall", "name": "The Wall", "below": 1.0, "encounters": ["encounter.bailey_test_wall"]},
			{"id": "charge", "name": "The Charge", "below": 0.6, "encounters": ["encounter.bailey_test_charge"]},
			{"id": "last_stand", "name": "The Last Stand", "below": 0.25, "encounters": ["encounter.bailey_test_stand"]}]})
	root.add_child(battle)
	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(kit.scripted(kit.marker("CpStart", BAILEY_PLAYER), S_CHECKPOINT,
		{"checkpoint_id": "test.bailey.cp_start"}))
	root.add_child(checkpoints)
	root.add_child(kit.n3("Spawned"))
	_place_player(kit, root, player, BAILEY_PLAYER, 0.0)
	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)
	_sign(kit, root, "BAILEY TEST: the Iron Regiment (walk north through the gate)", BAILEY_PLAYER + Vector3(0, 5, -6))
	return root
