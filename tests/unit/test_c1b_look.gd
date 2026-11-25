extends TestSuite
## C1b: the land beyond the rim's look pass (docs/systems/C1b.md) - its pure parts. The seeded natural shapes (the layout's
## convex hulls: closed, outward in the other shapes' winding, the same for the same seed, the old shapes untouched);
## a part's weather in its vertex alpha; the merged scatter's pieces; the frost band read from a level's world block
## and the terrain's material it picks (the plain material without one, as before); the hills' crags leaving every
## height under their line alone; the finale's rockfalls (a pure function of the tick); the smoke's and the dust's
## puffs drawn at their size by a renderer that leaves a particle's scale out.

const L := preload("res://tools/world/layout.gd")
const SCATTER := preload("res://tools/world/scatter.gd")
const SMOKE := preload("res://tools/world/kinds/smoke.gd")
const COLOSSAL := preload("res://tools/world/kinds/colossal.gd")


## Every face of `faces` points away from `centre` (Godot's winding: cross(b - a, c - a) points in), and every edge
## is shared by exactly two faces (a closed surface).
func _closed_and_outward(faces: PackedVector3Array, centre: Vector3) -> Array:
	var bad := 0
	var edges := {}
	for t in faces.size() / 3:
		var a := faces[t * 3]
		var b := faces[t * 3 + 1]
		var c := faces[t * 3 + 2]
		var inward := (b - a).cross(c - a)
		if inward.dot((a + b + c) / 3.0 - centre) > 0.0:
			bad += 1
		for e: Array in [[a, b], [b, c], [c, a]]:
			var k := "%s|%s" % [(e[0] as Vector3).snappedf(0.0001), (e[1] as Vector3).snappedf(0.0001)]
			edges[k] = int(edges.get(k, 0)) + 1
	var open := 0
	for k: String in edges:
		var parts := k.split("|")
		var back := "%s|%s" % [parts[1], parts[0]]
		if int(edges.get(back, 0)) != int(edges[k]):
			open += 1
	return [bad, open]


func test_the_seeded_shapes_are_closed_outward_and_repeatable() -> void:
	for shape: String in ["boulder", "block", "drum", "ellipsoid"]:
		var p := L.part(shape, Vector3.ZERO, Vector3(6, 4, 5), "rock")
		p["seed"] = 42
		var faces := L.part_faces(p)
		assert_true(faces.size() >= 36 and faces.size() % 3 == 0, "%s has triangles (%d vertices)" % [shape, faces.size()])
		var lo := INF
		var hi := -INF
		var centre := Vector3.ZERO
		for v in faces:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
			centre += v
		centre /= float(faces.size())
		assert_near(lo, 0.0, 0.001, "%s stands on its base (y 0)" % shape)
		assert_true(hi > 2.0 and hi <= 4.0 * 1.25, "%s about its height (%.2f)" % [shape, hi])
		var check := _closed_and_outward(faces, centre)
		assert_eq(check[0], 0, "%s: every face outward in the other shapes' winding" % shape)
		assert_eq(check[1], 0, "%s: a closed surface" % shape)
		assert_eq(L.part_faces(p), faces, "%s: the same seed, the same triangles" % shape)
		var q := p.duplicate()
		q["seed"] = 43
		if shape != "ellipsoid":
			assert_false(L.part_faces(q) == faces, "%s: another seed, another stone" % shape)


func test_the_old_shapes_are_untouched_and_a_box_is_still_a_box() -> void:
	var box := L.part("box", Vector3.ZERO, Vector3(2, 3, 4), "stone")
	assert_eq(L.part_faces(box), L.shape_faces("box", Vector3(2, 3, 4)), "a box's triangles as before")
	assert_eq(L.part_faces(L.part("sphere", Vector3.ZERO, Vector3(2, 2, 2), "stone")), L.shape_faces("sphere", Vector3(2, 2, 2)),
		"a sphere's as before")


func test_weather_goes_into_the_vertex_alpha() -> void:
	var plain := L.part("box", Vector3.ZERO, Vector3.ONE, "stone")
	var worn := L.part("box", Vector3(3, 0, 0), Vector3.ONE, "stone")
	worn["weather"] = 0.75
	var mesh := L.parts_mesh([plain, worn], Transform3D.IDENTITY, null)
	var cols: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var alphas := {}
	for c in cols:
		alphas[snappedf(c.a, 0.01)] = true
	assert_eq(alphas.keys().size(), 2, "two alphas: the plain part's and the weathered one's")
	assert_true(alphas.has(1.0), "a part without weather keeps an alpha of 1 (drawn as the plain material)")
	assert_true(alphas.has(0.25), "a weather of 0.75 is an alpha of 0.25")


func test_the_scatter_pieces() -> void:
	for key: String in SCATTER.KEYS:
		var a: Array = SCATTER.parts(key, 7)
		assert_true(not a.is_empty(), "%s has parts" % key)
		assert_eq(SCATTER.parts(key, 7), a, "%s: the same seed, the same piece" % key)
		for p: Dictionary in a:
			assert_true(p.has("weather"), "%s's parts are weathered" % key)
		var tris := L.parts_mesh(a, Transform3D.IDENTITY, null).surface_get_array_len(0)
		assert_true(tris < 6000, "%s stays a few hundred triangles (%d vertices)" % [key, tris])
	assert_false(SCATTER.has_key("rock"), "the MultiMesh keys are not scatter keys")


func test_the_frost_band_and_the_terrain_material() -> void:
	assert_eq(ChunkStreamer.frost_band({}), Vector2.ZERO, "no band without one")
	assert_eq(ChunkStreamer.frost_band({"frost": {"from_z": -905, "full_z": -1000}}), Vector2(-905, -1000), "the band")
	var world: Dictionary = GameData.get_record("level.world").get("world", {})
	var band := ChunkStreamer.frost_band(world)
	assert_true(band.x > -1024.0 and band.y < band.x, "the world's band starts at the rim (z %.0f) and is whole north of it" % band.x)
	var plain := ChunkStreamer.new()
	assert_true(plain.terrain_material() is StandardMaterial3D, "without a band: the plain vertex-colour material")
	plain.free()
	var frosty := ChunkStreamer.new()
	frosty.frost_z = band
	var m := frosty.terrain_material()
	assert_true(m is ShaderMaterial and (m as ShaderMaterial).shader.resource_path == ChunkStreamer.FROST_SHADER,
		"with one: the frost ground")
	assert_eq((m as ShaderMaterial).get_shader_parameter("frost_z"), band, "its band")
	frosty.free()


func test_the_crags_leave_the_ground_under_their_line() -> void:
	var feat := {"type": "hill", "circle": [0, 0, 50], "top_m": 700, "apron_m": 90}
	var crags := {"above_m": 470, "ridges": 7, "depth": 0.4, "jag": 0.16, "seed": 3}
	for y: float in [0.0, 176.0, 300.0, 469.9]:
		assert_eq(WorldFeatures._craggy(feat, crags, Vector2(60, 20), y), y, "%.0f m: under the line, untouched" % y)
	var lows := 0
	for a in 36:
		var p := Vector2(cos(TAU * a / 36.0), sin(TAU * a / 36.0)) * 90.0
		var y := WorldFeatures._craggy(feat, crags, p, 650.0)
		assert_true(y > 470.0 and y < 700.0, "above the line it stays between the line and the summit (%.0f)" % y)
		if y < 600.0:
			lows += 1
	assert_true(lows >= 4, "and gullies cut into it round the peak (%d of 36 below 600 m)" % lows)
	assert_eq(WorldFeatures._craggy(feat, crags, Vector2(90, 3), 650.0), WorldFeatures._craggy(feat, crags, Vector2(90, 3), 650.0),
		"the same everywhere it is asked")


func test_the_finales_rockfalls() -> void:
	var rec := GameData.get_record("cutscene.act_one_finale")
	var falls: Array = rec.get("rocks", [])
	assert_true(falls.size() >= 4, "the rim visibly breaks: %d rockfalls" % falls.size())
	var e: Dictionary = falls[0]
	var t0 := int(e.tick)
	assert_false(bool(CutsceneRules.rock_at(e, 0, t0 - 1).visible), "no rock before it breaks away")
	var fell := 0
	for k in int(e.get("count", 1)):
		var a := CutsceneRules.rock_at(e, k, t0 + 100)
		var b := CutsceneRules.rock_at(e, k, t0 + 160)
		assert_eq(CutsceneRules.rock_at(e, k, t0 + 100), a, "rock %d: the same at the same tick" % k)
		if bool(a.visible) and bool(b.visible) and (b.at as Vector3).y < (a.at as Vector3).y:
			fell += 1
	assert_true(fell >= int(e.get("count", 1)) / 2, "they fall (%d)" % fell)
	for f: Dictionary in falls:
		assert_true(int(f.tick) < CutsceneRules.ticks_of(rec), "each rockfall within the finale")


func test_the_puffs_are_drawn_at_their_size() -> void:
	var smoke := SMOKE.build(null, {"id": "s", "size": [9.0, 2.5]}, {}) as CPUParticles3D
	assert_true(smoke != null and smoke.mesh is QuadMesh, "a smoke column is a CPU particle system of quads")
	assert_near((smoke.mesh as QuadMesh).size.x, 9.0, 0.01, "its quad is the puff's width (a renderer that leaves the scale out)")
	assert_true(smoke.preprocess > 0.0, "already risen when its chunk streams in")
	smoke.free()
	var holder := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(holder)
	var dust := DustBurst.puff(holder, Vector3.ZERO, 20.0, 10, 6.0)
	assert_true(dust != null and (dust.mesh as QuadMesh).size.x >= 10.0, "a 20 m dust cloud's puffs are metres across, not 1 m")
	holder.queue_free()


func test_the_fallen_king_lies_whole() -> void:
	var el := {"kind": "colossal", "style": "fallen_king", "scale": 1.0}
	var parts: Array = COLOSSAL.parts(el, {})
	var far := 0.0
	for p: Dictionary in parts:
		far = maxf(far, (L.group_of(p) * (p.pos as Vector3)).z)
	assert_true(far > 100.0, "his head and crown lie over 100 m from his feet (%.0f)" % far)
	assert_true(parts.size() > 80, "built of his parts, not a few boxes (%d)" % parts.size())
	assert_eq(COLOSSAL.solids(el, {}).size(), 8, "his solids: plinth, shins, legs, body, head, arm, hand")
