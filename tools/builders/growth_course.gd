extends RefCounted
## Builder: the growth course (scenes/test/growth_course.tscn, P05). Stage-3-sized features in
## a line toward -Z, for the 3-size route (tests/slow/test_growth_route.gd) and the growth tests:
##   - a doorway 5 m wide x 9.5 m tall in a 14 m wall (z = 0);
##   - a low passage 8 m wide x 8.6 m tall x 10 m long (z -20 .. -30);
##   - a 20 degree ramp up to a 4 m platform and down again (z -40 .. -74);
##   - a wall lane: a 12 m wall whose face is 1 m beside the path (x = 2), on the camera's
##     shoulder side, so the follow arm has to retract (z -82 .. -108);
##   - a "growth trap" alcove with a 6 m ceiling beside the start (inside: Markers/TrapPoint),
##     where a stage-2 giant fits but stage 3 does not;
##   - a shrine (shrine.sandbox, world id test.course.shrine) beside the start.
## Route/WP01.. are the route's waypoints, in order (a stage-3 giant fits along all of them).

const PATH := "res://scenes/test/growth_course.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const SHRINE := "res://scenes/world/shrine.tscn"
const START := Vector3(0, 0.05, 25)
const ROUTE := [
	Vector3(0, 0, 10), Vector3(0, 0, -8),                          # through the doorway
	Vector3(0, 0, -16), Vector3(0, 0, -25), Vector3(0, 0, -36),    # the low passage
	Vector3(0, 4, -56), Vector3(0, 4, -61), Vector3(0, 0, -78),    # up the ramp, over, down
	Vector3(1, 0, -84), Vector3(1, 0, -106),                       # the wall lane (1 m from the wall)
	Vector3(0, 0, -118),
]
const RAMP_DEG := 20.0
const PLATFORM_H := 4.0


static func build_all(kit: SceneKit) -> void:
	var root := build_course(kit)
	if root != null:
		kit.save(root, PATH)


static func build_course(kit: SceneKit) -> Node:
	var player: Node3D = kit.instance(GIANT)
	if player == null:
		push_error("growth_course: build the player scene first")
		return null
	var root := Node3D.new()
	root.name = "GrowthCourse"
	_environment(root)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = SceneKit.L_WORLD
	ground.collision_mask = 0
	var gcs := CollisionShape3D.new()
	gcs.name = "Shape"
	gcs.shape = kit.box_shape(Vector3(90, 1, 200))
	gcs.position = Vector3(0, -0.5, -45)
	ground.add_child(gcs)
	var gmesh := MeshInstance3D.new()
	gmesh.name = "Mesh"
	var plane := PlaneMesh.new()
	plane.size = Vector2(90, 200)
	gmesh.mesh = plane
	gmesh.position = Vector3(0, 0, -45)
	gmesh.material_override = kit.mats["ground"]
	ground.add_child(gmesh)
	root.add_child(ground)

	var features := kit.n3("Features")
	# Doorway: 5 m wide, 9.5 m tall, in a 14 m tall wall 1 m thick at z = 0.
	features.add_child(kit.static_box("DoorwayLeft", Vector3(17.5, 14, 1), Vector3(-11.25, 7, 0), "stone"))
	features.add_child(kit.static_box("DoorwayRight", Vector3(17.5, 14, 1), Vector3(11.25, 7, 0), "stone"))
	features.add_child(kit.static_box("DoorwayLintel", Vector3(5, 4.5, 1), Vector3(0, 11.75, 0), "stone"))
	# Low passage: inner 8 m wide, ceiling at 8.6 m, 10 m long (z -20 .. -30).
	features.add_child(kit.static_box("PassageWallW", Vector3(1, 9.6, 10), Vector3(-4.5, 4.8, -25), "stone_dark"))
	features.add_child(kit.static_box("PassageWallE", Vector3(1, 9.6, 10), Vector3(4.5, 4.8, -25), "stone_dark"))
	features.add_child(kit.static_box("PassageRoof", Vector3(10, 1, 10), Vector3(0, 9.1, -25), "stone_dark"))
	# Ramp up (z -40 .. -51), a 4 m platform (z -51 .. -63) and a ramp down (z -63 .. -74).
	features.add_child(_ramp(kit, "RampUp", -40.0, true))
	features.add_child(kit.static_box("Platform", Vector3(10, PLATFORM_H, 12), Vector3(0, PLATFORM_H * 0.5, -57), "stone"))
	features.add_child(_ramp(kit, "RampDown", -63.0, false))
	# Wall lane: the wall's face at x = 2, 1 m beside waypoints at x = 1 (the shoulder side).
	features.add_child(kit.static_box("LaneWall", Vector3(1, 12, 26), Vector3(2.5, 6, -95), "stone"))
	# Growth trap: an alcove open to -X; inside 8 x 8 m, ceiling at 6 m.
	features.add_child(kit.static_box("TrapBack", Vector3(1, 6.6, 10), Vector3(25.5, 3.3, 25), "stone_dark"))
	features.add_child(kit.static_box("TrapSideN", Vector3(10, 6.6, 1), Vector3(21, 3.3, 20.5), "stone_dark"))
	features.add_child(kit.static_box("TrapSideS", Vector3(10, 6.6, 1), Vector3(21, 3.3, 29.5), "stone_dark"))
	features.add_child(kit.static_box("TrapRoof", Vector3(10, 0.6, 10), Vector3(21, 6.3, 25), "stone_dark"))
	root.add_child(features)

	var markers := kit.n3("Markers")
	markers.add_child(kit.marker("TrapPoint", Vector3(21, 0, 25)))
	markers.add_child(kit.marker("OpenPoint", Vector3(0, 0, 25)))
	markers.add_child(kit.marker("PassagePoint", Vector3(0, 0, -25)))
	markers.add_child(kit.marker("WallLanePoint", Vector3(1, 0, -95)))
	root.add_child(markers)
	var route := kit.n3("Route")
	for i in ROUTE.size():
		route.add_child(kit.marker("WP%02d" % (i + 1), ROUTE[i]))
	root.add_child(route)

	var shrine: Node3D = kit.instance(SHRINE)
	if shrine != null:
		shrine.name = "Shrine"
		shrine.position = Vector3(-16, 0, 25)
		shrine.rotation_degrees = Vector3(0, -90, 0)   # faces +X: its pad is at (-9.5, 0, 25)
		shrine.set("world_id", "test.course.shrine")
		shrine.set("shrine_id", "shrine.sandbox")
		root.add_child(shrine)

	var spawns := kit.n3("Spawns")
	spawns.add_child(kit.marker("PlayerSpawn", START))
	root.add_child(spawns)
	player.name = "Player"
	player.position = START
	root.add_child(player)

	var signs := kit.n3("Signs")
	signs.add_child(kit.sign("DOORWAY 5 x 9.5 m", Vector3(0, 15, 1)))
	signs.add_child(kit.sign("LOW PASSAGE 8.6 m", Vector3(0, 10.5, -19.4)))
	signs.add_child(kit.sign("RAMP 20 deg / 4 m", Vector3(-6.5, 6, -46)))
	signs.add_child(kit.sign("WALL LANE", Vector3(2, 13, -82)))
	signs.add_child(kit.sign("GROWTH TRAP 6 m", Vector3(16, 7.5, 25)))
	root.add_child(signs)
	return root


## A 20 degree ramp 10 m wide whose top surface starts on the floor at z = `z0` and rises
## toward -Z to the platform (up), or starts on the platform at `z0` and falls toward -Z (down).
static func _ramp(kit: SceneKit, ramp_name: String, z0: float, up: bool) -> StaticBody3D:
	var a := deg_to_rad(RAMP_DEG)
	var length := PLATFORM_H / sin(a)
	var run := PLATFORM_H / tan(a)
	var t := 0.4
	var top_center := Vector3(0, PLATFORM_H * 0.5, z0 - run * 0.5)
	var sign_a := 1.0 if up else -1.0
	# The box's local +Y after the rotation about X by sign_a * a.
	var normal := Vector3(0, cos(a), sin(a) * sign_a)
	var ramp := kit.static_box(ramp_name, Vector3(10, t, length), top_center - normal * (t * 0.5), "stone")
	ramp.rotation_degrees = Vector3(RAMP_DEG * sign_a, 0, 0)
	return ramp


static func _environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = Color(0.33, 0.50, 0.78)
	psm.sky_horizon_color = Color(0.72, 0.78, 0.86)
	psm.ground_bottom_color = Color(0.22, 0.22, 0.2)
	psm.ground_horizon_color = Color(0.62, 0.64, 0.62)
	sky.sky_material = psm
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.68)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
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
