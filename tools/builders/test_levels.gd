extends RefCounted
## Builder: the session flow test level (scenes/test/flow_test_level.tscn; plan §3.6). A flat
## 80 x 80 m floor with:
##   * the checkpoint markers test.cp_a (also the start checkpoint, where the Player stands) and
##     test.cp_b;
##   * the waystone test.cp_way (requires the flag test.way_open; radius 6 m), its stone 4 m
##     behind the marker so a respawn there has room;
##   * the fence test.flow_fence (a real BreakableProp: loot once, persistent);
##   * a stub-enemy spawn point (Spawns/StubEnemy) for the deferral tests;
##   * the Player (the giant scene) and a debris pool.
## Its root (FlowTestLevel) sets GameSession.test_checkpoints while it is in the tree. Runs after
## the player and props builders (tools/build_scenes.gd BUILDERS order).

const PATH := "res://scenes/test/flow_test_level.tscn"
const S_LEVEL := "res://scripts/world/flow_test_level.gd"
const S_MARKER := "res://scripts/world/checkpoint_marker.gd"
const S_WAYSTONE := "res://scripts/world/waystone.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const GIANT := "res://scenes/player/giant.tscn"
const FENCE := "res://scenes/world/fence_wood.tscn"

const CP_A := Vector3(0, 0.05, 20)
const CP_B := Vector3(24, 0.05, -4)
const WAYSTONE := Vector3(-24, 0.05, -4)
const WAYSTONE_RADIUS_M := 6.0
const FENCE_POS := Vector3(8, 0, 12)
const STUB_SPAWN := Vector3(0, 0.05, -24)


static func build_all(kit: SceneKit) -> void:
	var root := build_flow_level(kit)
	if root != null:
		kit.save(root, PATH)


static func build_flow_level(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	var fence: Node3D = kit.instance(FENCE)
	if player == null or fence == null:
		push_error("test_levels: build the player and props scenes first")
		for n: Node in [player, fence]:
			if n != null:
				n.free()
		return null
	kit.add_material("waystone_glow", Color(0.45, 0.85, 1.0), 0.3)
	var root := Node3D.new()
	root.name = "FlowTestLevel"
	kit.scripted(root, S_LEVEL, {"level_id": "test.flow", "start_checkpoint": "test.cp_a"})
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
	sun.directional_shadow_max_distance = 80.0
	root.add_child(sun)

	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = SceneKit.L_WORLD
	ground.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.name = "Shape"
	gcs.shape = kit.box_shape(Vector3(80, 1, 80))
	gcs.position = Vector3(0, -0.5, 0)
	ground.add_child(gcs)
	var gmesh := MeshInstance3D.new()
	gmesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	gmesh.mesh = plane
	gmesh.material_override = kit.mats["ground"]
	ground.add_child(gmesh)
	root.add_child(ground)

	var checkpoints := kit.n3("Checkpoints")
	checkpoints.add_child(_marker(kit, "CpA", "test.cp_a", CP_A, 0.0))
	checkpoints.add_child(_marker(kit, "CpB", "test.cp_b", CP_B, 90.0))
	root.add_child(checkpoints)

	var waystones := kit.n3("Waystones")
	var way := kit.scripted(kit.marker("CpWay", WAYSTONE), S_WAYSTONE, {"checkpoint_id": "test.cp_way",
		"radius_m": WAYSTONE_RADIUS_M, "requires_flags": PackedStringArray(["test.way_open"])}) as Node3D
	# The stone stands 4 m behind the marker (+Z is behind a marker that faces -Z).
	way.add_child(kit.static_box("Stone", Vector3(1.2, 4.0, 1.2), Vector3(0, 2.0, 4.0), "stone_dark"))
	var glow := kit.box("Glow", Vector3(0.6, 0.6, 0.6), Vector3(0, 4.4, 4.0), "waystone_glow")
	glow.visible = false
	way.add_child(glow)
	waystones.add_child(way)
	root.add_child(waystones)

	fence.name = "Fence"
	fence.position = FENCE_POS
	fence.rotation_degrees = Vector3(0, 90, 0)
	fence.set("world_id", "test.flow_fence")
	root.add_child(fence)

	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", CP_A))
	spawns.add_child(kit.marker("StubEnemy", STUB_SPAWN))
	root.add_child(spawns)

	player.name = "Player"
	player.position = CP_A
	root.add_child(player)

	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)

	var signs := kit.n3("Signs")
	for spec: Array in [["SignCpA", "CHECKPOINT test.cp_a (start)", CP_A + Vector3(0, 4.2, -3)],
			["SignCpB", "CHECKPOINT test.cp_b", CP_B + Vector3(0, 4.2, 0)],
			["SignWaystone", "WAYSTONE test.cp_way (needs test.way_open)", WAYSTONE + Vector3(0, 6.0, 4)],
			["SignFence", "FENCE test.flow_fence", FENCE_POS + Vector3(0, 2.6, 0)],
			["SignStub", "STUB ENEMY SPAWN", STUB_SPAWN + Vector3(0, 3.0, 0)]]:
		var sign := kit.sign(spec[1], spec[2])
		sign.name = spec[0]
		signs.add_child(sign)
	root.add_child(signs)
	return root


static func _marker(kit: SceneKit, node_name: String, checkpoint_id: String, pos: Vector3, yaw_deg: float) -> Node3D:
	var m := kit.scripted(kit.marker(node_name, pos), S_MARKER, {"checkpoint_id": checkpoint_id}) as Node3D
	m.rotation_degrees = Vector3(0, yaw_deg, 0)
	return m
