extends RefCounted
## Builder: the props of growth stages 4-6 and the Valley's exits (P26, plan M6-M9 §2.9, §2.15, §5.5,
## §5.6), one scene each under scenes/world/:
##   kings_door        the First King's door in the Barrow's north cliff: structural, indestructible,
##                     opened by slice.completed (Closed / Open), with the tunnel's darkness behind it
##   rockfall          boulders across a passage: structural, requires_permission heave (stage 5);
##                     Intact / Heaved, a HeavePoint ("Heave the rockfall aside"), NavLinkThrough
##   titan_tree        a fallen titan of the old forest across the way: the same heave rules
##   toppled_statue    a giant-king's statue on its face over a hidden place: the same heave rules
##   palisade_trample  a 10 m stake fence a stage-4 giant walks through (trample_stage 4)
##   great_pine        a 50 m pine of the Greywood (Trunk on WORLD + Visual, the UprootTree layout; the
##                     Greywood's package makes it uprootable once the pine weapon exists)
##   citadel_hoard     the Hoard of the Broken Kings' heap (a SceneryProp with a world_id; gold, chests,
##                     the annals' lectern on a low WORLD body): the Citadel hall's dressing, whose
##                     pickups are placed apart
##   old_kings_cairn   an Old Kings' cairn (NpcTalker: its dialogue gives one attribute point once)
##   size_gate_water, size_gate_stone, size_gate_timber
##                     a SizeGate wall (12 x 8 x 1 m) with the look of its kind: deep water, a step
##                     taller than a house, a beam barrier. size_gate() builds one of any size for the
##                     world builder.
## Breakables follow world_props.gd's BreakableProp contract (Block* shapes on the breakables layer,
## CombatEntity on Anchors/Center, Hurtboxes/*, stage visuals, NavLink*). Props face -Z; walls of
## them span local X, and their nav link crosses them along Z. Instances set world_id.

const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const S_HEAVE := "res://scripts/world/heave_point.gd"
const S_SIZE_GATE := "res://scripts/world/size_gate.gd"
const S_TALKER := "res://scripts/world/npc_talker.gd"
const S_SCENERY := "res://scripts/world/scenery_prop.gd"
const DIR := "res://scenes/world/"
## Every nav layer of the Valley (human 1, large 2, giant 4, small giant 8) and the world's titan (16).
const ALL_NAV_LAYERS := 31
## The prop meshes join LevelRoot's scenery group (the graphics preset fades them far off).
const PROP_GROUPS := ["scenery"]
## The Kings' Door: its opening, its leaves' height and the tunnel's depth behind it.
const DOOR_WIDTH_M := 14.0
const DOOR_HEIGHT_M := 16.0
const TUNNEL_DEPTH_M := 14.0
## The sample size gates' wall.
const GATE_SIZE := Vector3(12.0, 8.0, 1.0)


static func build_all(kit: SceneKit) -> void:
	_materials(kit)
	kit.save(batched(kit, build_kings_door(kit)), DIR + "kings_door.tscn")
	kit.save(batched(kit, build_rockfall(kit)), DIR + "rockfall.tscn")
	kit.save(batched(kit, build_titan_tree(kit)), DIR + "titan_tree.tscn")
	kit.save(batched(kit, build_toppled_statue(kit)), DIR + "toppled_statue.tscn")
	kit.save(batched(kit, build_palisade(kit)), DIR + "palisade_trample.tscn")
	kit.save(batched(kit, build_great_pine(kit)), DIR + "great_pine.tscn")
	kit.save(batched(kit, build_citadel_hoard(kit)), DIR + "citadel_hoard.tscn")
	kit.save(batched(kit, build_old_kings_cairn(kit)), DIR + "old_kings_cairn.tscn")
	for spec: Array in [["water", 4, "sfx.gate.water"], ["stone", 6, "sfx.gate.stone"], ["timber", 4, "sfx.gate.timber"]]:
		var gate := size_gate(kit, "test.gate.%s" % spec[0], int(spec[1]), GATE_SIZE, str(spec[2]))
		kit.save(batched(kit, gate), DIR + "size_gate_%s.tscn" % spec[0])


## world_props.gd's batching (P17b): each visual group merged into one mesh per material, apart, so
## the stage visuals still show and hide; the merged meshes join the scenery group.
static func batched(kit: SceneKit, root: Node) -> Node:
	for child in root.get_children():
		if child.get_script() == null and (child.get_class() == "Node3D" or child is StaticBody3D):
			kit.merge_meshes(child as Node3D, PackedStringArray(), PackedStringArray(PROP_GROUPS))
	return root


static func _materials(kit: SceneKit) -> void:
	kit.add_material("door_stone", Color(0.47, 0.45, 0.42), 0.9)
	var rune := kit.add_material("door_rune", Color(0.55, 0.78, 0.86), 0.4)
	rune.emission_enabled = true
	rune.emission = Color(0.35, 0.62, 0.75)
	rune.emission_energy_multiplier = 0.8
	if kit.out_root == "":
		ResourceSaver.save(rune, "%s/door_rune.tres" % SceneKit.MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)
	kit.add_material("tunnel_dark", Color(0.03, 0.03, 0.04), 1.0)
	kit.add_material("rock_grey", Color(0.50, 0.48, 0.45), 0.95)
	kit.add_material("rock_dark", Color(0.36, 0.35, 0.33), 0.95)
	kit.add_material("titan_bark", Color(0.30, 0.24, 0.19), 0.95)
	kit.add_material("pine_bark", Color(0.37, 0.33, 0.30), 0.95)
	kit.add_material("pine_needles", Color(0.27, 0.36, 0.30), 0.95)
	kit.add_material("statue_stone", Color(0.62, 0.60, 0.55), 0.85)
	kit.add_material("hoard_gold", Color(0.86, 0.68, 0.22), 0.35, 0.7)
	kit.add_material("hoard_chest", Color(0.40, 0.26, 0.15), 0.85)
	kit.add_material("annals_parchment", Color(0.86, 0.80, 0.64), 0.9)
	kit.add_material("palisade_wood", Color(0.46, 0.34, 0.21), 0.9)
	kit.add_material("gate_deep_water", Color(0.10, 0.20, 0.32), 0.1, 0.1)


# --------------------------------------------------------------------------- shared parts

## The root of a breakable or structural prop: StaticBody3D on the breakables layer with the
## BreakableProp script and `world_id`, a CombatEntity (team NEUTRAL) on Anchors/Center.
static func _breakable_root(kit: SceneKit, node_name: String, world_id: String, definition_id: String,
		center: Vector3) -> StaticBody3D:
	var root := StaticBody3D.new()
	root.name = node_name
	kit.scripted(root, S_BREAKABLE, {"world_id": world_id})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	root.add_child(kit.combat_entity(world_id, definition_id, 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", center))
	root.add_child(anchors)
	return root


static func _block(kit: SceneKit, node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	cs.shape = kit.box_shape(size)
	cs.position = pos
	return cs


static func _hurtboxes(kit: SceneKit, size: Vector3, pos: Vector3) -> Node3D:
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(size), pos))
	return hb


## A disabled link across the prop along Z (from +half_depth to -half_depth), for every layer.
static func _nav_link(half_depth: float) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.name = "NavLinkThrough"
	link.start_position = Vector3(0, 0, half_depth)
	link.end_position = Vector3(0, 0, -half_depth)
	link.bidirectional = true
	link.navigation_layers = ALL_NAV_LAYERS
	link.enabled = false
	return link


## The heave interaction of a heave prop (HeavePoint), reachable from either side of it.
static func _heave_point(kit: SceneKit, radius_m: float) -> Node3D:
	var hp := kit.n3("HeavePoint")
	kit.scripted(hp, S_HEAVE, {"prompt": "Heave", "radius_m": radius_m, "priority": 40})
	return hp


## A rough boulder: a stretched sphere.
static func _boulder(kit: SceneKit, node_name: String, r: float, pos: Vector3, mat: String, squash := 0.75,
		yaw_deg := 0.0) -> MeshInstance3D:
	var b := kit.sphere(node_name, r, pos, mat)
	b.scale = Vector3(1.15, squash, 0.95)
	b.rotation_degrees = Vector3(0, yaw_deg, 0)
	return b


# --------------------------------------------------------------------------- the Kings' Door

## The First King's door: two carved stone leaves, 14 m wide and 16 m tall, between posts under a
## lintel, with the dark of the tunnel behind them. Indestructible; slice.completed opens it (the
## Open stage swings the leaves into the tunnel and removes the collision). Faces -Z: the tunnel
## runs toward -Z behind it.
static func build_kings_door(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "KingsDoor", "valley.barrow.kings_door", "prop.kings_door",
		Vector3(0, DOOR_HEIGHT_M * 0.5, 0))
	root.add_child(_block(kit, "BlockDoor", Vector3(DOOR_WIDTH_M, DOOR_HEIGHT_M, 2.0), Vector3(0, DOOR_HEIGHT_M * 0.5, 0)))
	root.add_child(_hurtboxes(kit, Vector3(DOOR_WIDTH_M, DOOR_HEIGHT_M, 2.4), Vector3(0, DOOR_HEIGHT_M * 0.5, 0)))
	var frame := kit.n3("Frame")
	for side in [-1.0, 1.0]:
		frame.add_child(kit.box("Post%s" % ("L" if side < 0 else "R"), Vector3(1.6, DOOR_HEIGHT_M + 2.0, 2.6),
			Vector3((DOOR_WIDTH_M * 0.5 + 0.4) * side, (DOOR_HEIGHT_M + 2.0) * 0.5, 0.4), "door_stone"))
		for r in 3:
			frame.add_child(kit.box("Rune%s%d" % ["L" if side < 0 else "R", r], Vector3(0.5, 1.6, 0.2),
				Vector3((DOOR_WIDTH_M * 0.5 + 0.4) * side, 4.0 + 4.5 * r, 1.75), "door_rune"))
	frame.add_child(kit.box("Lintel", Vector3(DOOR_WIDTH_M + 4.0, 2.4, 3.0), Vector3(0, DOOR_HEIGHT_M + 1.2, 0.5), "door_stone"))
	frame.add_child(kit.box("Crown", Vector3(3.0, 1.0, 0.3), Vector3(0, DOOR_HEIGHT_M + 1.2, 2.1), "door_rune"))
	# The tunnel's darkness: what the open door shows (the tunnel leads out of the Valley).
	frame.add_child(kit.box("Darkness", Vector3(DOOR_WIDTH_M - 0.4, DOOR_HEIGHT_M - 0.2, 0.4),
		Vector3(0, (DOOR_HEIGHT_M - 0.2) * 0.5, -TUNNEL_DEPTH_M + 0.6), "tunnel_dark"))
	root.add_child(frame)
	var closed := kit.n3("Closed")
	for leaf in 2:
		var side := -1.0 if leaf == 0 else 1.0
		closed.add_child(_door_leaf(kit, "Leaf%d" % leaf, Vector3(side * DOOR_WIDTH_M * 0.25, 0, 0)))
	root.add_child(closed)
	var opened := kit.n3("Open")
	for leaf in 2:
		var side := -1.0 if leaf == 0 else 1.0
		var l := _door_leaf(kit, "Leaf%d" % leaf, Vector3(side * (DOOR_WIDTH_M * 0.5 - 0.7), 0, -DOOR_WIDTH_M * 0.25 - 0.4))
		l.rotation_degrees = Vector3(0, -84.0 * side, 0)
		opened.add_child(l)
	opened.visible = false
	root.add_child(opened)
	return root


## One leaf of the door, centred on `pos`: a slab with three carved bands and a rune.
static func _door_leaf(kit: SceneKit, node_name: String, pos: Vector3) -> Node3D:
	var leaf := kit.n3(node_name, pos)
	var w := DOOR_WIDTH_M * 0.5 - 0.1
	leaf.add_child(kit.box("Slab", Vector3(w, DOOR_HEIGHT_M, 1.4), Vector3(0, DOOR_HEIGHT_M * 0.5, 0), "door_stone"))
	for b in 3:
		leaf.add_child(kit.box("Band%d" % b, Vector3(w + 0.1, 0.5, 1.6), Vector3(0, 2.5 + 5.5 * b, 0), "rock_dark"))
	leaf.add_child(kit.box("Rune", Vector3(1.2, 1.2, 0.2), Vector3(0, DOOR_HEIGHT_M * 0.6, 0.8), "door_rune"))
	return leaf


# --------------------------------------------------------------------------- heave props

## A rockfall across a passage: a 16 m wide, 8 m tall heap of boulders (heave, stage 5). Heaved, the
## boulders lie rolled to both sides.
static func build_rockfall(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "Rockfall", "valley.barrow.vault_rockfall", "prop.rockfall", Vector3(0, 3.5, 0))
	root.add_child(_block(kit, "BlockRocks", Vector3(16.0, 8.0, 5.0), Vector3(0, 4.0, 0)))
	root.add_child(_hurtboxes(kit, Vector3(16.0, 8.0, 5.6), Vector3(0, 4.0, 0)))
	var intact := kit.n3("Intact")
	var rocks := [[-5.5, 2.2, 0.2, 3.0], [-1.5, 2.4, -0.3, 3.2], [2.8, 2.2, 0.3, 3.0], [6.4, 1.9, -0.2, 2.6],
		[-3.6, 5.6, 0.0, 2.5], [0.8, 5.9, 0.2, 2.6], [4.6, 5.2, -0.1, 2.3], [-0.9, 7.6, 0.0, 1.6]]
	for i in rocks.size():
		var r: Array = rocks[i]
		intact.add_child(_boulder(kit, "Boulder%d" % i, float(r[3]), Vector3(r[0], r[1], r[2]),
			"rock_grey" if i % 2 == 0 else "rock_dark", 0.8, 31.0 * i))
	root.add_child(intact)
	var heaved := kit.n3("Heaved")
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		heaved.add_child(_boulder(kit, "Rolled%d" % i, 2.2 - 0.25 * (i % 3), Vector3(side * (9.5 + 1.5 * (i / 2)), 1.4,
			-1.5 + 1.5 * (i / 2)), "rock_grey" if i % 3 == 0 else "rock_dark", 0.7, 47.0 * i))
	heaved.visible = false
	root.add_child(heaved)
	root.add_child(_heave_point(kit, 6.0))
	root.add_child(_nav_link(6.0))
	return root


## A fallen titan-tree: a 24 m trunk of 2.5 m radius lying across the way, its root plate at one end
## (heave, stage 5). Heaved, it lies rolled aside.
static func build_titan_tree(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "TitanTree", "world.test.titan_tree", "prop.titan_tree", Vector3(0, 2.5, 0))
	root.add_child(_block(kit, "BlockTrunk", Vector3(24.0, 5.0, 5.0), Vector3(0, 2.5, 0)))
	root.add_child(_hurtboxes(kit, Vector3(24.0, 5.0, 5.6), Vector3(0, 2.5, 0)))
	var intact := kit.n3("Intact")
	intact.add_child(_trunk(kit, "Trunk", Vector3(0, 2.5, 0), 0.0))
	var roots := kit.cyl("RootPlate", 4.5, 4.5, 1.2, Vector3(-12.6, 3.6, 0), "titan_bark")
	roots.rotation_degrees = Vector3(0, 0, 90)
	intact.add_child(roots)
	for b in 3:
		var branch := kit.box("Branch%d" % b, Vector3(0.9, 6.0, 0.9), Vector3(4.0 + 3.5 * b, 5.5, 0.6 * (b - 1)), "titan_bark")
		branch.rotation_degrees = Vector3(0, 0, -40.0 + 25.0 * b)
		intact.add_child(branch)
	root.add_child(intact)
	var heaved := kit.n3("Heaved")
	heaved.add_child(_trunk(kit, "Trunk", Vector3(-2.0, 2.5, 7.5), 14.0))
	heaved.visible = false
	root.add_child(heaved)
	root.add_child(_heave_point(kit, 6.0))
	root.add_child(_nav_link(6.0))
	return root


## A trunk lying along local X (rotated by yaw_deg).
static func _trunk(kit: SceneKit, node_name: String, pos: Vector3, yaw_deg: float) -> MeshInstance3D:
	var mi := kit.cyl(node_name, 2.3, 2.6, 24.0, pos, "titan_bark")
	mi.rotation_degrees = Vector3(0, yaw_deg, 90)
	return mi


## A toppled king's statue lying on its face: a 12 m body with its crowned head (heave, stage 5).
## Heaved, it lies on its back beside the dark of what it hid.
static func build_toppled_statue(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "ToppledStatue", "world.test.toppled_statue", "prop.toppled_statue",
		Vector3(0, 2.0, 0))
	root.add_child(_block(kit, "BlockStatue", Vector3(12.0, 4.0, 5.0), Vector3(0, 2.0, 0)))
	root.add_child(_hurtboxes(kit, Vector3(12.0, 4.0, 5.6), Vector3(0, 2.0, 0)))
	var intact := kit.n3("Intact")
	_statue(kit, intact, Vector3.ZERO, 0.0)
	root.add_child(intact)
	var heaved := kit.n3("Heaved")
	_statue(kit, heaved, Vector3(1.0, 0, 7.0), 180.0)
	heaved.add_child(kit.box("Hollow", Vector3(6.0, 0.1, 3.5), Vector3(0, 0.03, 0), "tunnel_dark"))
	heaved.visible = false
	root.add_child(heaved)
	root.add_child(_heave_point(kit, 6.0))
	root.add_child(_nav_link(5.0))
	return root


static func _statue(kit: SceneKit, parent: Node3D, offset: Vector3, yaw_deg: float) -> void:
	var s := kit.n3("Statue", offset)
	s.rotation_degrees = Vector3(0, yaw_deg, 0)
	s.add_child(kit.box("Body", Vector3(9.0, 3.2, 4.2), Vector3(-1.0, 1.6, 0), "statue_stone"))
	s.add_child(kit.box("Shoulders", Vector3(1.6, 3.4, 5.2), Vector3(3.2, 1.7, 0), "statue_stone"))
	s.add_child(kit.sphere("Head", 1.5, Vector3(5.0, 1.6, 0), "statue_stone"))
	s.add_child(kit.box("Crown", Vector3(0.8, 2.4, 2.4), Vector3(6.3, 1.6, 0), "hoard_gold"))
	s.add_child(kit.box("Plinth", Vector3(2.0, 3.0, 4.6), Vector3(-5.8, 1.5, 0), "rock_dark"))
	parent.add_child(s)


# --------------------------------------------------------------------------- trample

## A palisade section a stage-4 giant walks through: 13 stakes 3.5 m tall on two rails, 10 m wide.
static func build_palisade(kit: SceneKit) -> Node:
	var root := _breakable_root(kit, "PalisadeTrample", "world.test.palisade", "prop.palisade_trample",
		Vector3(0, 1.75, 0))
	root.add_child(_block(kit, "BlockStakes", Vector3(10.0, 3.5, 0.6), Vector3(0, 1.75, 0)))
	root.add_child(_hurtboxes(kit, Vector3(10.0, 3.5, 1.0), Vector3(0, 1.75, 0)))
	var intact := kit.n3("Intact")
	for i in 13:
		var x := -4.8 + 0.8 * i
		intact.add_child(kit.box("Stake%d" % i, Vector3(0.32, 3.5 - 0.2 * (i % 2), 0.32), Vector3(x, 1.75 - 0.1 * (i % 2), 0),
			"palisade_wood"))
	for r in 2:
		intact.add_child(kit.box("Rail%d" % r, Vector3(10.0, 0.22, 0.2), Vector3(0, 0.9 + 1.5 * r, 0.25), "wood_dark"))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	for i in 6:
		var stake := kit.box("Snapped%d" % i, Vector3(0.32, 0.7 + 0.2 * (i % 3), 0.32), Vector3(-4.0 + 1.6 * i, 0.4, 0),
			"palisade_wood")
		stake.rotation_degrees = Vector3(0, 0, 12.0 * ((i % 3) - 1))
		broken.add_child(stake)
	for i in 3:
		var fallen := kit.box("Fallen%d" % i, Vector3(3.2, 0.3, 0.3), Vector3(-3.0 + 3.0 * i, 0.15, -1.2 + 0.8 * i), "palisade_wood")
		fallen.rotation_degrees = Vector3(0, 25.0 * i - 20.0, 0)
		broken.add_child(fallen)
	broken.visible = false
	root.add_child(broken)
	root.add_child(_nav_link(2.0))
	return root


# --------------------------------------------------------------------------- the great pine

## A great pine of the Greywood: a 50 m trunk (Trunk: a WORLD cylinder, the obstacle) and five tiers
## of grey needles (Visual). The same children as an UprootTree, so the Greywood's package can make
## it uprootable by giving it that script.
static func build_great_pine(kit: SceneKit) -> Node:
	var root := kit.n3("GreatPine")
	var trunk := StaticBody3D.new()
	trunk.name = "Trunk"
	trunk.collision_layer = SceneKit.L_WORLD
	trunk.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.2
	cyl.height = 50.0
	cs.shape = cyl
	cs.position = Vector3(0, 25.0, 0)
	trunk.add_child(cs)
	root.add_child(trunk)
	var visual := kit.n3("Visual")
	visual.add_child(kit.cyl("Bole", 1.2, 2.4, 50.0, Vector3(0, 25.0, 0), "pine_bark"))
	for r in 4:
		var rt := kit.box("Root%d" % r, Vector3(1.2, 1.0, 5.0), Vector3(0, 0.5, 0), "pine_bark")
		rt.position = Vector3(cos(PI * 0.5 * r) * 2.8, 0.5, sin(PI * 0.5 * r) * 2.8)
		rt.rotation_degrees = Vector3(0, -90.0 * r, 0)
		visual.add_child(rt)
	for t in 5:
		visual.add_child(kit.cyl("Needles%d" % t, 0.4, 9.0 - 1.4 * t, 9.0, Vector3(0, 18.0 + 7.0 * t, 0), "pine_needles"))
	root.add_child(visual)
	return root


# --------------------------------------------------------------------------- the Citadel's hoard

## The Hoard of the Broken Kings: heaps of gold, iron-bound chests and the annals on their lectern,
## on a low WORLD body (7 x 1.6 x 4 m). Dressing only: the hall's pickups carry the rewards.
static func build_citadel_hoard(kit: SceneKit) -> Node:
	var root := kit.n3("CitadelHoard")
	kit.scripted(root, S_SCENERY, {"world_id": "valley.citadel.hoard"})
	var body := StaticBody3D.new()
	body.name = "Pile"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	body.add_child(_block(kit, "Shape", Vector3(7.0, 1.6, 4.0), Vector3(0, 0.8, 0)))
	for i in 5:
		body.add_child(_boulder(kit, "Gold%d" % i, 1.1 - 0.12 * i, Vector3(-2.6 + 1.3 * i, 0.4 + 0.1 * (i % 2), 0.5 * ((i % 3) - 1)),
			"hoard_gold", 0.45, 30.0 * i))
	for c in 2:
		body.add_child(kit.box("Chest%d" % c, Vector3(1.6, 1.1, 1.0), Vector3(-2.2 + 4.4 * c, 1.05, -1.3), "hoard_chest"))
		body.add_child(kit.box("Lid%d" % c, Vector3(1.7, 0.3, 1.1), Vector3(-2.2 + 4.4 * c, 1.75, -1.3), "hoard_gold"))
	body.add_child(kit.box("Lectern", Vector3(1.0, 2.2, 0.8), Vector3(0, 1.1, 1.5), "rock_dark"))
	body.add_child(kit.box("Annals", Vector3(1.4, 0.25, 1.0), Vector3(0, 2.3, 1.5), "annals_parchment"))
	root.add_child(body)
	return root


# --------------------------------------------------------------------------- the Old Kings' cairn

## An Old Kings' cairn (plan M6-M9 decision 33): stones stacked on a base (WORLD) with the First
## King's rune; an NpcTalker whose dialogue gives one attribute point once. The instance sets
## npc_id and dialogue_id.
static func build_old_kings_cairn(kit: SceneKit) -> Node:
	var root := kit.n3("OldKingsCairn")
	kit.scripted(root, S_TALKER, {"npc_id": "valley.barrow.vault_cairn", "dialogue_id": "dialogue.cairn_valley_vault",
		"prompt": "Read the cairn", "radius_m": 4.0, "priority": 45})
	var base := StaticBody3D.new()
	base.name = "Base"
	base.collision_layer = SceneKit.L_WORLD
	base.collision_mask = 0
	base.add_child(_block(kit, "Shape", Vector3(2.6, 3.2, 2.6), Vector3(0, 1.6, 0)))
	var sizes := [Vector3(2.6, 0.9, 2.5), Vector3(2.1, 0.8, 2.0), Vector3(1.6, 0.7, 1.6), Vector3(1.1, 0.6, 1.0)]
	var y := 0.0
	for i in sizes.size():
		var s: Vector3 = sizes[i]
		var stone := kit.box("Stone%d" % i, s, Vector3(0.06 * (i % 2), y + s.y * 0.5, -0.05 * (i % 3)), "rock_grey")
		stone.rotation_degrees = Vector3(0, 23.0 * i, 0)
		base.add_child(stone)
		y += s.y
	base.add_child(kit.box("Rune", Vector3(0.7, 0.5, 0.12), Vector3(0, 1.6, 1.32), "door_rune"))
	root.add_child(base)
	return root


# --------------------------------------------------------------------------- size gates

## A SizeGate (scripts/world/size_gate.gd) of `size` (a box standing on the ground, spanning local
## X) for `min_stage`, with its kind's look from `cue`: water - a dark deep-water strip on both
## sides; stone - a step taller than a house; timber - a heavy beam barrier. The wall itself stays
## invisible (it is a size gate, not a wall: what stops a small giant is the water or the height).
static func size_gate(kit: SceneKit, gate_id: String, min_stage: int, size: Vector3, cue: String,
		message := "") -> StaticBody3D:
	var gate := StaticBody3D.new()
	gate.name = "SizeGate"
	kit.scripted(gate, S_SIZE_GATE, {"gate_id": gate_id, "min_stage": min_stage, "cue": cue, "message": message})
	gate.collision_layer = SizeGate.layer_for_stage(min_stage)
	gate.collision_mask = 0
	gate.add_child(_block(kit, "Wall", size, Vector3(0, size.y * 0.5, 0)))
	var visual := kit.n3("Visual")
	match cue.get_slice(".", 2):
		"water":
			visual.add_child(kit.box("DeepWater", Vector3(size.x, 0.05, maxf(size.z, 1.0) * 4.0), Vector3(0, 0.06, 0),
				"gate_deep_water"))
		"stone":
			visual.add_child(kit.box("Step", Vector3(size.x, minf(size.y, 6.0), maxf(size.z, 2.0)),
				Vector3(0, minf(size.y, 6.0) * 0.5, -maxf(size.z, 2.0) * 0.5), "rock_dark"))
		_:
			for b in 2:
				visual.add_child(kit.box("Beam%d" % b, Vector3(size.x, 0.6, 0.6), Vector3(0, 2.0 + 2.5 * b, 0), "palisade_wood"))
	gate.add_child(visual)
	return gate
