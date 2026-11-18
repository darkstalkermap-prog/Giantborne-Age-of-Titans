extends TestSuite
## The M10 gate's LC-6 (docs/systems/P46.md, "The M10 gate"): the hair and beard cards as Godot imports them.
## Read from the meshes of scenes/player/giant_model.tscn, a card being a connected piece of a mesh:
##   * the four long styles carry the hairline's fringe: short three-point cards far narrower than any other
##     card of theirs (giant_hair.FRINGE; the hairline was a row of wide card ends with a bare notch);
##   * no card of the full and the forked beard is wider at its root than BEARD_ASPECT of its own length, and
##     each narrows to a point (the cheeks' cards were squares: steps along the beard's sides); the short and
##     the braided beard's cards stay as they were (as narrow locks they showed gaps);
##   * the manifest counts the cards.

const MODEL := "res://scenes/player/giant_model.tscn"
const MANIFEST := "res://assets/giant/manifest.json"
## Style -> the fringe's cards (giant_hair.STYLES' "fringe" n).
const FRINGE := {"Hair_long_back": 110, "Hair_long_braided": 90, "Hair_warrior_tail": 90, "Hair_wild_mane": 50}
## A fringe card's root is at most this wide (m at stage 1; the fringe's cards measure 0.016 to 0.024 m, the
## narrowest card of the crop and a braid's lobes 0.031 m, the long layers' cards 0.039 m and more).
const FRINGE_MAX_WIDTH_M := 0.026
const BEARDS := ["Beard_full", "Beard_forked"]
const BEARD_ASPECT := 0.5
const BEARD_TIP_SHARE := 0.2


## The cards of a mesh: [{verts, root_w, tip_w, length}], a card being a connected set of triangles.
func _cards(mi: MeshInstance3D) -> Array:
	var arrays := mi.mesh.surface_get_arrays(0)
	var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var parent := PackedInt32Array()
	parent.resize(pos.size())
	for i in pos.size():
		parent[i] = i
	for t in range(0, idx.size(), 3):
		for k in [1, 2]:
			var a := idx[t]
			var b := idx[t + k]
			while parent[a] != a:
				parent[a] = parent[parent[a]]
				a = parent[a]
			while parent[b] != b:
				parent[b] = parent[parent[b]]
				b = parent[b]
			if a != b:
				parent[b] = a
	var groups := {}
	for i in pos.size():
		var r := i
		while parent[r] != r:
			r = parent[r]
		if not groups.has(r):
			groups[r] = []
		(groups[r] as Array).append(i)
	var out: Array = []
	for r: int in groups:
		var vs: Array = groups[r]
		vs.sort_custom(func(a: int, b: int) -> bool: return uv[a].y < uv[b].y)   # root (v 0) to tip (v 1), in pairs
		var length := 0.0
		for j in range(2, vs.size() - 1, 2):
			length += ((pos[vs[j]] + pos[vs[j + 1]]) * 0.5).distance_to((pos[vs[j - 2]] + pos[vs[j - 1]]) * 0.5)
		out.append({"verts": vs.size(), "root_w": pos[vs[0]].distance_to(pos[vs[1]]),
			"tip_w": pos[vs[vs.size() - 1]].distance_to(pos[vs[vs.size() - 2]]), "length": length})
	return out


func test_the_long_styles_carry_the_fringe_and_the_beards_cards_are_locks() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(m)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	for id: String in FRINGE:
		var mi := m.ensure_part(id)
		assert_true(mi != null, "%s is a mesh of the model" % id)
		if mi == null:
			continue
		var cards := _cards(mi)
		assert_eq(cards.size(), int(manifest.export.meshes[id].cards), "%s: the manifest counts its cards" % id)
		var fringe := cards.filter(func(c: Dictionary) -> bool: return int(c.verts) == 6 and float(c.root_w) <= FRINGE_MAX_WIDTH_M)
		assert_eq(fringe.size(), int(FRINGE[id]), "%s: the hairline's fringe of narrow three-point cards" % id)
		var others := cards.filter(func(c: Dictionary) -> bool: return int(c.verts) > 6 and float(c.root_w) <= FRINGE_MAX_WIDTH_M)
		assert_true(others.size() * 20 <= cards.size(), "%s: hardly another card is that narrow (%d of %d)" % [id, others.size(), cards.size()])
	assert_true(m.ensure_part("Hair_crop") != null and _cards(m.ensure_part("Hair_crop")).filter(
		func(c: Dictionary) -> bool: return float(c.root_w) <= FRINGE_MAX_WIDTH_M).is_empty(), "the crop has no fringe")
	for id: String in BEARDS:
		var mi := m.ensure_part(id)
		assert_true(mi != null, "%s is a mesh of the model" % id)
		if mi == null:
			continue
		var wide := 0
		var blunt := 0
		var cards := _cards(mi)
		for c: Dictionary in cards:
			if float(c.root_w) > BEARD_ASPECT * float(c.length) * 1.05 + 0.002:
				wide += 1
			if float(c.tip_w) > BEARD_TIP_SHARE * float(c.root_w) + 0.001:
				blunt += 1
		assert_eq(wide, 0, "%s: no card wider than half its length (%d cards)" % [id, cards.size()])
		assert_eq(blunt, 0, "%s: every card narrows to a point" % id)
	m.free()
