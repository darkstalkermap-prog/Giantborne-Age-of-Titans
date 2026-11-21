extends TestSuite
## The giant's far levels (the second W33 look lane; plan M11 §2.12: "at most 4,000 primitives beyond 120 m"), as the
## import made them (tools/giant/part_import.gd, tools/giant/far_lods.gd):
##   * every mesh the look draws (the body's, the parts') has a level the renderer takes at FAR_KEY - its far level -
##     and a hair style's or a beard's cards and braids keep a middle level and a far one of their own;
##   * the far levels keep the mesh's vertices (index lists only) and never more triangles than the level before;
##   * the worst slot look - in every slot the garment with the most far triangles, the hair and the beard with the
##     most, two bead sets and the heaviest accessory of each accessory slot - draws at most FAR_BUDGET triangles at
##     its far levels: the rendered count beyond 120 m (tests/gate/test_giant_far_render.gd) of any look stays under
##     §2.12's 4,000.

const MODEL := "res://scenes/player/giant_model.tscn"
const FarLods := preload("res://tools/giant/far_lods.gd")
const BODY := ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes"]
## The worst slot look's far triangles: §2.12's 4,000 less a margin for what the count adds (the shadow proxy draws
## no main pass; the alpha-scissored cards' depth pre-pass is not counted as primitives).
const FAR_BUDGET := 3800


func _model() -> GiantModel:
	var m := (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(m)
	return m


## The triangles the renderer draws of `mesh` at the far switch: its coarsest level whose key is at most FAR_KEY.
static func far_triangles(mesh: Mesh) -> int:
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var tris: int = mesh.surface_get_array_index_len(0) / 3
	var best_key := -1.0
	var wide: bool = (d.get("index_data", PackedByteArray()) as PackedByteArray).size() >= 4 * mesh.surface_get_array_index_len(0)
	for lod: Dictionary in d.get("lods", []):
		var key := float(lod.edge_length)
		if key <= FarLods.FAR_KEY * 1.0001 and key > best_key:
			best_key = key
			tris = (lod.index_data as PackedByteArray).size() / (4 if wide else 2) / 3
	return tris


## {key: triangles} of every level of `mesh`.
static func levels(mesh: Mesh) -> Array:
	var d: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), 0)
	var wide: bool = (d.get("index_data", PackedByteArray()) as PackedByteArray).size() >= 4 * mesh.surface_get_array_index_len(0)
	var out := []
	for lod: Dictionary in d.get("lods", []):
		out.append([float(lod.edge_length), (lod.index_data as PackedByteArray).size() / (4 if wide else 2) / 3])
	out.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	return out


func _far_of_every_mesh(m: GiantModel) -> Dictionary:
	var out := {}
	for id: String in m.index.meshes:
		var mi := m.mesh(id)
		if mi == null:
			continue
		if m.is_part(id):
			mi = m.ensure_part(id)
		if mi == null or mi.mesh == null:
			continue
		out[id] = far_triangles(mi.mesh)
	return out


func test_every_drawn_mesh_has_a_far_level_and_the_strands_their_own() -> void:
	var m := _model()
	for id: String in m.index.meshes:
		var mi := m.mesh(id)
		if mi == null:
			continue
		if m.is_part(id):
			mi = m.ensure_part(id)
		var mesh: Mesh = mi.mesh
		var full: int = mesh.surface_get_array_index_len(0) / 3
		var lv := levels(mesh)
		var prev := full
		for l: Array in lv:
			assert_true(int(l[1]) <= prev, "%s: each level no finer than the one before (%s)" % [id, str(lv)])
			prev = int(l[1])
		var far := far_triangles(mesh)
		assert_true(far < full or full <= FarLods.FAR_LEAST_TRIS, "%s: a far level (%d of %d triangles)" % [id, far, full])
		var strands := id.begins_with("Hair_") or id.begins_with("Beard_")
		if strands and id not in ["Hair_crop", "Beard_short"]:
			assert_true(lv.size() == 2 and is_equal_approx(float(lv[0][0]), FarLods.STRAND_MID_KEY)
				and is_equal_approx(float(lv[1][0]), FarLods.FAR_KEY), "%s: the strands' middle and far levels (%s)" % [id, str(lv)])
			assert_true(far <= FarLods.FAR_STRAND_TRIS + 100, "%s: its far level %d triangles" % [id, far])
			assert_true(int(lv[0][1]) < full, "%s: its middle level is coarser than the whole (%d of %d)" % [id, int(lv[0][1]), full])
	m.free()


func test_the_worst_slot_look_at_its_far_levels_is_within_the_budget() -> void:
	var m := _model()
	var idx: Dictionary = m.index
	var far := _far_of_every_mesh(m)
	var total := 0
	var parts := PackedStringArray()
	for id: String in BODY:
		total += int(far[id])
	var most := {}
	var which := {}
	for g: String in idx.garments:
		var slot := str(idx.meshes[(idx.garments[g] as Array)[0]].get("slot", ""))
		var t := 0
		for mid: String in idx.garments[g]:
			t += int(far[mid])
		if t > int(most.get(slot, -1)):
			most[slot] = t
			which[slot] = g
	assert_eq(most.size(), Appearance.SLOTS.size(), "a garment in each of the ten slots")
	for slot: String in most:
		total += int(most[slot])
		parts.append("%s %d" % [which[slot], int(most[slot])])
	var cats := {"hair": [], "beard": [], "bead": [], "accessory": []}
	var acc := {}
	for id: String in idx.meshes:
		var cat := str(idx.meshes[id].category)
		if cat == "accessory":
			var slot := str(idx.meshes[id].slot)
			acc[slot] = maxi(int(acc.get(slot, 0)), int(far[id]))
		elif cats.has(cat):
			(cats[cat] as Array).append(int(far[id]))
	for cat: String in ["hair", "beard", "bead"]:
		var vals: Array = cats[cat]
		vals.sort()
		vals.reverse()
		var n := 2 if cat == "bead" else 1
		for i in mini(n, vals.size()):
			total += int(vals[i])
		parts.append("%s %s" % [cat, str(vals.slice(0, n))])
	for slot: String in acc:
		total += int(acc[slot])
	parts.append("accessories %s" % str(acc))
	print("    the worst slot look's far levels: %d triangles (%s)" % [total, ", ".join(parts)])
	assert_true(total <= FAR_BUDGET, "the worst slot look at its far levels: %d triangles, at most %d" % [total, FAR_BUDGET])
	m.free()
