extends IntegrationSuite
## P24a (plan M6-M9 §2.8, §3.6): one chunk of the test world built step by step - the steps and
## their order, a deterministic quota, the terrain mesh, the ground body under the giant's feet (a
## ray finds the same height as ChunkData), solids in bodies of 16, the scenery MultiMeshes, and the
## town chunk's props parts (dependencies one a step, every part instanced) with its far scenery.

const CHUNK_DIR := "res://assets/test_world/chunks"


func _streamer() -> ChunkStreamer:
	var s := ChunkStreamer.new()
	s.name = "Streamer"
	world.add_child(s)
	s.configure({"chunk_size_m": 256.0, "grid": [4, 4], "origin_m": [-512.0, 0.0, -512.0], "chunk_dir": CHUNK_DIR}, world)
	s.deterministic = true
	s.process_mode = Node.PROCESS_MODE_DISABLED
	s.terrain_visibility_end_m = 700.0
	return s


## Loads one chunk with its own loader (no streamer queue); returns [chunk, step names].
func _load(s: ChunkStreamer, id: String) -> Array:
	var c := TerrainChunk.new()
	c.begin(id, s.chunk_path(id), s, s.chunks_parent)
	var names: Array = []
	var guard := 0
	while not c.done and not c.aborted and guard < 500:
		var what := c.step()
		if what != "":
			names.append(what)
		guard += 1
	return [c, names]


func test_a_chunk_loads_in_small_steps() -> void:
	var s := _streamer()
	var r := _load(s, "c1_1")
	var c: TerrainChunk = r[0]
	var names: Array = r[1]
	assert_true(c.done, "the chunk finished loading")
	assert_eq(names.slice(0, 3), ["request", "data", "decode"], "the data first, then its heights decoded")
	assert_eq(names.count("rows"), 3, "65 rows of 65 vertices in three slices of about 2,000")
	assert_true(names.find("mesh") > names.rfind("rows") and names.find("ground") == names.find("mesh") + 1,
		"the mesh after the rows, the ground body next")
	var d := c.data
	var n_solids := d.solids.size() / ChunkData.SOLID_STRIDE
	assert_eq(names.count("solids"), ceili(n_solids / float(TerrainChunk.SOLID_BATCH)), "one step per 16 solids (%d)" % n_solids)
	assert_eq(names.count("scenery"), d.scenery.size(), "one step per scenery key")
	assert_eq(c.steps_done, names.size(), "steps counted")
	assert_eq(c.total_steps(), names.size(), "and estimated exactly once the data is known")
	assert_true(c.is_inside_tree() and c.get_parent() == s.chunks_parent, "the chunk joined the Chunks node")
	assert_eq(str(c.name), "Chunk_1_1", "named after its id")
	assert_eq(c.position, Vector3(-256.0, 0.0, -256.0), "at its origin")
	# The terrain mesh
	var mesh := c.terrain.mesh as ArrayMesh
	var arrays := mesh.surface_get_arrays(0)
	assert_eq((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 65 * 65, "65 x 65 vertices at 4 m")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 64 * 64 * 6, "8,192 triangles")
	assert_near((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array)[65 * 10 + 7].y, d.sample(7, 10), 1e-4, "vertex heights are the samples")
	assert_near(c.terrain.visibility_range_end, 700.0, 0.01, "the preset's terrain distance")
	assert_true(c.terrain.is_in_group(TerrainChunk.TERRAIN_GROUP), "in the terrain group")
	# Solids in bodies of at most 16 shapes
	var bodies := c.solids_root.get_children()
	var shapes := 0
	for b in bodies:
		assert_true(b.get_child_count() <= TerrainChunk.SOLID_BATCH, "%s holds at most 16 shapes" % b.name)
		shapes += b.get_child_count()
	assert_eq(shapes, n_solids, "every solid made")
	for mmi in c.scenery_root.get_children():
		assert_true((mmi as MultiMeshInstance3D).multimesh.instance_count > 0, "%s has instances" % mmi.name)
		assert_true(mmi.is_in_group("scenery"), "%s is scenery (the preset fades it)" % mmi.name)
	# The ground under the feet: a ray down meets the same height as the data.
	await step_ticks(2)
	var space := world.get_world_3d().direct_space_state
	var worst := 0.0
	for p: Vector2 in [Vector2(10.5, 20.25), Vector2(128.0, 128.0), Vector2(250.3, 3.7), Vector2(66.6, 201.1)]:
		var top := c.position + Vector3(p.x, 300.0, p.y)
		var q := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 600.0, 1)
		q.exclude = []
		for b in bodies:
			q.exclude.append((b as StaticBody3D).get_rid())
		var hit := space.intersect_ray(q)
		assert_false(hit.is_empty(), "the ground body is under %s" % p)
		if not hit.is_empty():
			worst = maxf(worst, absf((hit.position as Vector3).y - d.ground_at_local(p.x, p.y)))
	assert_true(worst < 0.01, "the ground body is the data's triangles (worst %.4f m)" % worst)


func test_the_town_chunk_streams_its_parts() -> void:
	var s := _streamer()
	s.scenery_visibility_end_m = 220.0
	var r := _load(s, "c2_2")
	var c: TerrainChunk = r[0]
	var names: Array = r[1]
	assert_true(c.done, "the town chunk finished loading")
	var parts := c.data.props_scenes.size()
	assert_true(parts >= 2, "the town is split into parts (%d)" % parts)
	assert_eq(names.count("props_load"), parts, "each part loaded in its own step")
	assert_eq(names.count("props_add"), parts, "and instanced in its own step")
	assert_eq(c.props_root.get_child_count(), parts, "every part under Props")
	for part in c.props_root.get_children():
		assert_true(ChunkWriter.node_count(part) <= ChunkWriter.MAX_PART_NODES, "%s: at most 150 nodes" % part.name)
		assert_true(part.has_node("Props") and part.has_node("Landmarks"), "%s has its containers" % part.name)
	var breakables := 0
	for b in get_tree().get_nodes_in_group("breakables"):
		if c.is_ancestor_of(b):
			breakables += 1
	assert_true(breakables >= 8 + 2 + 8, "the houses, gates, fences and crates are breakables (%d)" % breakables)
	assert_true(c.props_root.find_child("House1", true, false) != null, "a breakable house")
	# The merged houses and the walls are seen as far as the terrain; the trees and the props'
	# merged meshes (group "scenery") fade at the scenery's distance.
	var far_names: Array = []
	for mmi in c.scenery_root.get_children():
		var g := mmi as GeometryInstance3D
		if g.is_in_group(TerrainChunk.TERRAIN_GROUP):
			far_names.append(str(g.name))
			assert_near(g.visibility_range_end, 700.0, 0.01, "%s is drawn as far as the terrain" % g.name)
		else:
			assert_near(g.visibility_range_end, 220.0, 0.01, "%s fades with the scenery" % g.name)
	far_names.sort()
	assert_eq(far_names, ["House", "Wall"], "the far scenery: the merged houses and the walls")
	var in_group := 0
	var faded := 0
	for n in c.props_root.find_children("*", "GeometryInstance3D", true, false):
		if n.is_in_group("scenery"):
			in_group += 1
			if is_equal_approx((n as GeometryInstance3D).visibility_range_end, 220.0):
				faded += 1
	assert_true(in_group > 0 and faded == in_group, "the props' scenery meshes fade too (%d of %d)" % [faded, in_group])
	var deps := names.count("props_dep")
	assert_true(deps <= 6, "dependencies one a step, only those not cached yet (%d)" % deps)
	# A second load of the same chunk finds every dependency kept by the streamer.
	c.queue_free()
	await get_tree().process_frame
	var again := _load(s, "c2_2")
	assert_eq((again[1] as Array).count("props_dep"), 0, "nothing left to fetch the second time")
	(again[0] as Node).queue_free()


func test_unloading_frees_props_first() -> void:
	var s := _streamer()
	var c: TerrainChunk = _load(s, "c3_1")[0]
	assert_true(c.props_root != null and c.props_root.get_child_count() == 1, "the watchtower's part is loaded")
	var props := c.props_root
	c.free_props()
	assert_true(props.is_queued_for_deletion(), "free_props() takes the props")
	assert_true(c.terrain != null and is_instance_valid(c.terrain) and not c.terrain.is_queued_for_deletion(),
		"and leaves the terrain for the next step")
	await get_tree().process_frame
	assert_false(is_instance_valid(props), "the props are gone after the frame")
