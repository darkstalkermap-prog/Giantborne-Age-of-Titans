extends TestSuite
## P25 (plan M6-M9 §3.8, §5.2, §5.3): the built world. Every chunk's data loads with its heights,
## its three navmesh layers (and gate regions) and its props parts (at most 150 nodes each); the
## heights are equal across every seam (each chunk's apron holds its neighbour's border samples);
## no walkable face within 8 m of a chunk border is steeper than 35 degrees (cliffs and the rim
## excepted, the builder's rule); the world scene names the streamer, the skyline, the bounds and the
## giant at the start checkpoint; --chunks= rebuilds a chunk with its eight neighbours; and, rendered
## in a child process under Xvfb (tests/support/world_draw_probe.gd), the static world draws at most
## 40 draw calls at `low` from the Kingsgate shelf and the six settlements' greens (skipped with a
## note without xvfb-run).

const LEVEL := "level.world"
const PROBE := "res://tests/support/world_draw_probe.gd"
const PREFIX := "WORLD_DRAWS "
const MAX_STATIC_DRAWS := 40
const MAX_PART_NODES := 150
const INTERIOR := 896.0
const BAND_M := 8.0
const RULE_DEG := 35.0 + 0.05
const CLIFF_DEG := 45.0
## The walkable notches in the south rim (the Kingsgate shelf, the Broken Stair): world.json's rim.
const NOTCHES := [Rect2(-335, 892, 70, 53), Rect2(-62, 892, 44, 50)]

var _chunks := {}   # Vector2i -> ChunkData


func _world() -> Dictionary:
	return GameData.get_record(LEVEL).get("world", {})


func _load_chunks() -> void:
	if not _chunks.is_empty():
		return
	var w := _world()
	for z in int(w.grid[1]):
		for x in int(w.grid[0]):
			_chunks[Vector2i(x, z)] = load("%s/c%d_%d.res" % [w.chunk_dir, x, z]) as ChunkData


static func _walkable(x: float, z: float) -> bool:
	if absf(x) < INTERIOR and absf(z) < INTERIOR:
		return true
	for r: Rect2 in NOTCHES:
		if r.has_point(Vector2(x, z)):
			return true
	return false


func test_every_chunk_loads_with_its_navmeshes_and_parts() -> void:
	_load_chunks()
	var w := _world()
	var size := float(w.chunk_size_m)
	var parts := 0
	for c: Vector2i in _chunks:
		var d: ChunkData = _chunks[c]
		var id := "c%d_%d" % [c.x, c.y]
		assert_true(d != null, "%s loads" % id)
		if d == null:
			continue
		assert_eq(d.chunk_id, id, "%s knows its id" % id)
		assert_eq(d.origin, Vector3(float(w.origin_m[0]) + c.x * size, 0.0, float(w.origin_m[2]) + c.y * size), "%s's origin" % id)
		assert_eq(d.heights.size(), 2 * d.samples * d.samples, "%s holds 67 x 67 16-bit heights" % id)
		var walkable := Rect2(d.origin.x, d.origin.z, size, size).intersects(Rect2(-INTERIOR, -INTERIOR, 2 * INTERIOR, 2 * INTERIOR))
		if walkable:
			for layer: int in [1, 2, 16]:
				assert_true(d.nav.has(layer) and ResourceLoader.exists(str(d.nav.get(layer, ""))), "%s has its navmesh for layer %d" % [id, layer])
		for path: String in d.nav.values():
			assert_true(load(path) is NavigationMesh, "%s: %s is a navmesh" % [id, path])
		for path: String in d.props_scenes:
			var ps := load(path) as PackedScene
			assert_true(ps != null, "%s: %s loads" % [id, path])
			if ps != null:
				parts += 1
				assert_true(ps.get_state().get_node_count() <= MAX_PART_NODES, "%s holds at most 150 nodes (%d)" % [path, ps.get_state().get_node_count()])
	assert_true(parts >= 20, "the scripted places in props parts (%d)" % parts)


func test_the_heights_meet_across_every_seam() -> void:
	_load_chunks()
	var w := _world()
	var size := float(w.chunk_size_m)
	var mismatched := 0
	var worst := 0.0
	for c: Vector2i in _chunks:
		var a: ChunkData = _chunks[c]
		for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
			var b: ChunkData = _chunks.get(c + step)
			if b == null:
				continue
			for k in a.inner():
				var t := float(k) * a.spacing_m
				var ha := a.height_at_local(size, t) if step.x == 1 else a.height_at_local(t, size)
				var hb := b.height_at_local(0.0, t) if step.x == 1 else b.height_at_local(t, 0.0)
				if absf(ha - hb) > 0.0005:
					mismatched += 1
					worst = maxf(worst, absf(ha - hb))
				# the aprons hold the neighbour's next sample
				var aa := a.height_at_local(size + a.spacing_m, t) if step.x == 1 else a.height_at_local(t, size + a.spacing_m)
				var bb := b.height_at_local(b.spacing_m, t) if step.x == 1 else b.height_at_local(t, b.spacing_m)
				if absf(aa - bb) > 0.0005:
					mismatched += 1
					worst = maxf(worst, absf(aa - bb))
	assert_eq(mismatched, 0, "every seam's heights and aprons agree (worst %.4f m)" % worst)


func test_no_walkable_border_face_is_steeper_than_35_degrees() -> void:
	_load_chunks()
	var w := _world()
	var size := float(w.chunk_size_m)
	var band := int(ceil(BAND_M / 4.0))
	var over := 0
	var worst := ""
	for c: Vector2i in _chunks:
		var d: ChunkData = _chunks[c]
		var m := d.inner() - 1   # cells per side
		for j in m:
			for i in m:
				# cells touching the band of an inner border (the rule of HeightField.border_report)
				var near_x := (c.x > 0 and i <= band) or (c.x < int(w.grid[0]) - 1 and i >= m - 1 - band)
				var near_z := (c.y > 0 and j <= band) or (c.y < int(w.grid[1]) - 1 and j >= m - 1 - band)
				if not near_x and not near_z:
					continue
				var cx := d.origin.x + (i + 0.5) * d.spacing_m
				var cz := d.origin.z + (j + 0.5) * d.spacing_m
				if not _walkable(cx, cz):
					continue
				var h00 := d.sample(i, j)
				var h10 := d.sample(i + 1, j)
				var h01 := d.sample(i, j + 1)
				var h11 := d.sample(i + 1, j + 1)
				var g := maxf(Vector2(h10 - h00, h11 - h10).length(), Vector2(h11 - h01, h01 - h00).length()) / d.spacing_m
				var deg := rad_to_deg(atan(g))
				if deg > RULE_DEG and deg <= CLIFF_DEG:
					over += 1
					worst = "%.1f degrees at (%.0f, %.0f)" % [deg, cx, cz]
	assert_eq(over, 0, "no walkable face within 8 m of a chunk border is steeper than 35 degrees (%s)" % worst)


func test_the_world_scene_and_the_chunk_rebuild() -> void:
	var ps := load(str(GameData.get_record(LEVEL).scene)) as PackedScene
	var state := ps.get_state()
	var names := {}
	for i in state.get_node_count():
		names[str(state.get_node_path(i))] = true
	for n in ["./Streamer", "./Skyline", "./Bounds", "./Player", "./EncounterDirector", "./Spawns/PlayerSpawn"]:
		assert_true(names.has(n), "world.tscn has %s" % n)
	var idx := WorldIndex.for_level(LEVEL)
	var root := ps.instantiate() as Node3D
	var player := root.get_node("Player") as Node3D
	var start := idx.position_of("world.cp.kingsgate_shelf")
	assert_true(Vector2(player.position.x, player.position.z).distance_to(Vector2(start.x, start.z)) < 1.0,
		"the giant stands at the start checkpoint")
	root.free()
	var builder := load("res://tools/builders/world.gd")
	var nine: PackedStringArray = builder.call("expand_chunks", PackedStringArray(["c2_6"]), Vector2i(8, 8))
	assert_eq(nine.size(), 9, "--chunks=c2_6 rebuilds it and its eight neighbours")
	assert_true(nine.has("c1_5") and nine.has("c3_7"), "corner neighbours included")
	var corner: PackedStringArray = builder.call("expand_chunks", PackedStringArray(["c0_0", "c7_7"]), Vector2i(8, 8))
	assert_eq(corner.size(), 8, "a corner chunk has three neighbours")
	assert_eq(builder.call("parse_args", PackedStringArray(["--chunks=c2_6,c3_6"])), {"chunks": PackedStringArray(["c2_6", "c3_6"])},
		"--chunks= after --")


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_the_static_world_draws_at_most_40_calls_at_low() -> void:
	if not _have("xvfb-run"):
		print("    test_world_build: draw calls skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["-a", "-s", "-screen 0 640x360x24", OS.get_executable_path(),
		"--path", ProjectSettings.globalize_path("res://"), "--resolution", "640x360", "--audio-driver", "Dummy",
		"-s", PROBE, "--", "--no-user-settings"])
	var output: Array = []
	var code := OS.execute("xvfb-run", args, output, true)
	var text := "\n".join(output)
	var line := ""
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY, "it reported: %s" % (line if line != "" else text.right(600)))
	if typeof(r) != TYPE_DICTIONARY:
		return
	var views: Dictionary = r.views
	assert_eq(views.size(), 7, "the shelf and the six settlements")
	for view: String in views:
		assert_true(int(views[view]) > 0 and int(views[view]) <= MAX_STATIC_DRAWS,
			"%s: %d draw calls of the static world at low (at most 40)" % [view, int(views[view])])
	print("    test_world_build: static draw calls at low %s (max %d; with the giant %s) on %s" % [JSON.stringify(views),
		int(r.max), JSON.stringify(r.get("with_giant", {})), str(r.get("adapter", "?"))])
