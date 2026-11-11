extends TestSuite
## M8 gate (F27; plan M6-M9 §5.2: at most 40 static draw calls a view at `low`): the merge pass, read
## from the built scenes without a renderer (tests/slow/test_world_build.gd renders the seventeen
## views under Xvfb). The M8 places drew up to 59 calls a view: a rack's weapon on display drawn in six
## or seven parts from 500 m away, every siege engine in four (one per material), every framed prop
## (the bells, the troll den's wall) in two, and the waystones, the cairns and the ledge chests at any
## distance.
##   * a siege engine's Intact and Broken are one vertex-coloured mesh each (one surface);
##   * a framed breakable draws its frame in its Intact and in its Broken mesh: the Frame body keeps its
##     solids and no mesh;
##   * the waystones' stones and glows, the cairns' stones and the ledge chests are in group "scenery"
##     (TerrainChunk and LevelRoot give them the preset's scenery distance, 220 m at low);
##   * a rack's weapon on display fades with its frame.
## Scenes only (the default tier).

const ENGINES := ["res://scenes/world/siege_ballista.tscn", "res://scenes/world/siege_catapult.tscn"]
const RACK := "res://scenes/world/weapon_rack.tscn"
## Chunk props parts with framed bells and the den's wall, cairns, waystones and a ledge chest.
const CHUNKS := ["res://scenes/world/chunks/c4_4_0.tscn", "res://scenes/world/chunks/c0_2_0.tscn",
	"res://scenes/world/chunks/c4_2_0.tscn"]
const SCENERY := "scenery"


static func _meshes(n: Node) -> Array:
	return n.find_children("*", "MeshInstance3D", true, false) if n != null else []


func test_a_siege_engine_is_one_mesh_a_state() -> void:
	for path: String in ENGINES:
		var e := (load(path) as PackedScene).instantiate()
		for group: String in ["Intact", "Broken"]:
			var meshes := _meshes(e.get_node_or_null(group))
			assert_eq(meshes.size(), 1, "%s/%s: one mesh (%d)" % [path.get_file(), group, meshes.size()])
			if meshes.size() == 1:
				var mi := meshes[0] as MeshInstance3D
				assert_eq(mi.mesh.get_surface_count(), 1, "%s/%s: one surface, one draw call" % [path.get_file(), group])
				assert_true(mi.material_override != null, "%s/%s: the vertex-coloured material" % [path.get_file(), group])
		e.free()


func test_framed_props_scenery_and_ledge_chests_in_the_chunks() -> void:
	var framed := 0
	var stones := 0
	var waystones := 0
	var chests := 0
	for path: String in CHUNKS:
		var part := (load(path) as PackedScene).instantiate()
		for n in part.find_children("*", "", true, false):
			var frame := n.get_node_or_null("Frame") as StaticBody3D
			if n is BreakableProp and frame != null:
				framed += 1
				assert_eq(_meshes(frame).size(), 0, "%s: its Frame keeps no mesh of its own" % n.name)
				assert_true(frame.get_child_count() > 0, "%s: and keeps its solids" % n.name)
				for group: String in ["Intact", "Broken"]:
					assert_eq(_meshes(n.get_node_or_null(group)).size(), 1, "%s/%s: one mesh, the frame in it" % [n.name, group])
			if n is Inscription:
				var st := n.get_node_or_null("Base/Stones")
				assert_true(st != null and st.is_in_group(SCENERY), "%s: the cairn's stones fade with the scenery" % n.name)
				stones += 1
			if n is Waystone:
				for child: String in ["Stone/Mesh", "Glow"]:
					var mesh := n.get_node_or_null(child)
					assert_true(mesh != null and mesh.is_in_group(SCENERY), "%s/%s fades with the scenery" % [n.name, child])
				waystones += 1
			if n is ItemPickup and n.get_node_or_null("Visual/Chest") != null:
				assert_true(n.get_node("Visual/Chest").is_in_group(SCENERY), "%s: the ledge chest fades with the scenery" % n.name)
				chests += 1
		part.free()
	assert_true(framed >= 3, "the bells and the den's wall were read (%d)" % framed)
	assert_true(stones >= 1 and waystones >= 1 and chests >= 1, "a cairn, a waystone and a ledge chest were read (%d, %d, %d)" % [
		stones, waystones, chests])


func test_a_racks_weapon_fades_with_its_frame() -> void:
	var rack := (load(RACK) as PackedScene).instantiate() as WeaponRack
	rack.world_id = "test.f27.rack"
	rack.weapon_id = "weapon.axe"
	for n in rack.get_node("Frame").find_children("*", "GeometryInstance3D", true, false):
		(n as GeometryInstance3D).visibility_range_end = 123.0   # as a chunk's scenery fade sets it
	add_child(rack)
	var parts := rack.display_weapon.find_children("*", "GeometryInstance3D", true, false) if rack.display_weapon != null else []
	assert_true(parts.size() >= 3, "the axe on display has its parts (%d)" % parts.size())
	for g: GeometryInstance3D in parts:
		assert_true(g.is_in_group(SCENERY), "%s fades with the scenery" % g.name)
		assert_near(g.visibility_range_end, 123.0, 0.001, "%s: at its frame's distance" % g.name)
	rack.queue_free()
	await get_tree().process_frame
