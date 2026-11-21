extends TestSuite
## GiantLook on the real model (P42; plan M10 §2.4, §2.5, §2.13): skipped with a note while
## scenes/player/giant_model.tscn does not exist (P41 builds it in the same wave; the W25 merge runs this).
## The data's mesh, design and garment ids all exist in the model's index; every index mesh has its node
## and a known category; DEFAULT_LOOK applies cleanly; and every option of every set, applied through
## Appearance.to_look and GiantLook.apply with the materials built, sets the expected visibility with
## validate() empty; every material's samplers hold the maps the index names (its `textures` table), and
## the data's covered regions agree with the index's for every outfit.

const MODEL := "res://scenes/player/giant_model.tscn"

var _root: Node3D


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null


func _model() -> Dictionary:
	if not ResourceLoader.exists(MODEL):
		print("    test_giant_look_real: skipped - %s does not exist yet (P41; the W25 merge runs it)" % MODEL)
		return {}
	_root = (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(_root)
	var index: Variant = _root.get("index")
	assert_true(typeof(index) == TYPE_DICTIONARY and not (index as Dictionary).is_empty(), "the model carries its index")
	return index if typeof(index) == TYPE_DICTIONARY else {}


## Every option id of the data with the index id it names: [option id, "mesh" | "garment" | "design", index id].
static func data_refs() -> Array:
	var out: Array = []
	for c: String in ["hair", "beard"]:
		for id: String in Appearance.option_ids(c):
			var m := str(Appearance.option(id).get("mesh", ""))
			if m != "":
				out.append([id, "mesh", m])
	for id: String in Appearance.option_ids("outfit"):
		for g: Variant in Appearance.option(id).get("garments", []):
			out.append([id, "garment", str(g)])
	# P53 (plan M11 §2.6): every garment of the slots names an index garment
	for id: String in Appearance.option_ids("garment"):
		out.append([id, "garment", str(Appearance.option(id).get("mesh", ""))])
	for c: String in ["tattoo", "paint", "scar", "mark"]:
		for id: String in Appearance.option_ids(c):
			out.append([id, "design", str(Appearance.option(id).get("design", ""))])
	return out


func test_the_datas_ids_exist_in_the_index_and_every_mesh_has_its_node() -> void:
	var index := _model()
	if index.is_empty():
		return
	var tables := {"mesh": index.get("meshes", {}), "garment": index.get("garments", {}), "design": index.get("designs", {})}
	for ref: Array in data_refs():
		assert_true((tables[ref[1]] as Dictionary).has(ref[2]), "%s: the index has the %s '%s'" % [ref[0], ref[1], ref[2]])
	for id: Variant in index.get("meshes", {}):
		assert_true(GiantLook.mesh_node(_root, index, str(id)) != null, "the index mesh %s has its node" % id)
		assert_true(GiantLook.shader_kind(str(index.meshes[id].get("category", ""))) != "", "%s has a known category" % id)
	GiantLook.apply(_root, index, GiantLook.DEFAULT_LOOK)
	assert_eq(GiantLook.validate(_root, index, GiantLook.DEFAULT_LOOK), PackedStringArray(), "DEFAULT_LOOK applies cleanly")


func test_every_option_of_the_data_applies_with_validate_empty() -> void:
	var index := _model()
	if index.is_empty():
		return
	GiantLook.build_materials(_root, index, "web")
	assert_eq(GiantLook.materials(_root).size(), (index.get("meshes", {}) as Dictionary).size(),
		"every index mesh has its own material")
	# P57 (plan M11 §1.7 rule 2): the default tier walks a sample - the first and the last option of every set; every
	# option of the data is walked in tests/slow/test_giant_look_walks.gd
	var n := OptionWalk.every_option(self, _root, index, true)
	assert_true(n >= Appearance.CATEGORIES.size(), "a sample of every set (%d)" % n)


## Every sampler of every material holds the map the index names (W25 review C1: the index gives names,
## "atlas": "hair_atlas" and "detail": "leather" | "weave" | "fur", that its `textures` table maps to paths).
func test_the_real_models_materials_get_their_textures() -> void:
	var index := _model()
	if index.is_empty():
		return
	var textures: Dictionary = index.get("textures", {})
	GiantLook.build_materials(_root, index, "web")
	var n := 0
	for id: Variant in index.meshes:
		var entry: Dictionary = index.meshes[id]
		var mat := GiantLook.mesh_node(_root, index, str(id)).material_override as ShaderMaterial
		for u: Variant in GiantLook.sampler_uniforms(mat.shader):
			assert_true(mat.get_shader_parameter(str(u)) is Texture, "%s: %s is bound" % [id, u])
			n += 1
		match str(entry.category):
			"hair", "beard":
				if entry.has("shell"):
					# P51: a shell style reads the shells' strands and the skin's masks, not the card atlas
					assert_eq((mat.get_shader_parameter("strand_tex") as Texture).resource_path, str(textures.shell_strands),
						"%s: the shells' strands" % id)
				else:
					assert_eq((mat.get_shader_parameter("hair_atlas") as Texture).resource_path, str(textures.get(entry.atlas)),
						"%s: the atlas the index names" % id)
			"garment":
				assert_eq((mat.get_shader_parameter("detail_tex") as Texture).resource_path,
					str(textures.get("detail_" + str(entry.detail))), "%s: its %s map" % [id, entry.detail])
				assert_true(is_equal_approx(float(mat.get_shader_parameter("detail_strength")),
					float(GiantLook.DETAIL_STRENGTH[str(entry.detail)])), "%s: the %s strength" % [id, entry.detail])
			"body":
				assert_eq((mat.get_shader_parameter("design_tex") as Texture).resource_path, str(textures.designs),
					"%s: the design array" % id)
	assert_true(n >= (index.meshes as Dictionary).size() - 1, "every sampler checked (%d)" % n)
	assert_eq(GiantLook.validate(_root, index, GiantLook.DEFAULT_LOOK), PackedStringArray(), "validate() is empty")


## The two sources of the covered regions agree on the real model (W25 review C2): the data's `covers`,
## which Randomize reads, and the index's coverage, which the creator's "Hidden by your clothing" reads.
func test_the_datas_covered_regions_match_the_real_index() -> void:
	var index := _model()
	if index.is_empty():
		return
	for id: String in Appearance.option_ids("outfit"):
		var r := Appearance.default_record()
		r = Appearance.with_outfit(r, id)   # P53: an outfit fills the slots
		assert_eq(Appearance.covered_regions(r, index), Appearance.covered_regions(r),
			"%s: the index's covered regions are the data's %s" % [id, Appearance.covered_regions(r)])


## P53 (plan M11 §2.5, §2.6): each garment alone hides what the index says it hides (its data's `covers` and the
## index's coverage agree), and its material is the dye its meshes took in M10 (cloth the primary, leather the
## secondary, fur none), so a migrated look dyes every mesh as M10 did.
func test_every_garments_covers_and_material_match_the_real_index() -> void:
	var index := _model()
	if index.is_empty():
		return
	var empty := Appearance.with_outfit(Appearance.default_record(), "outfit.wanderer")
	empty.outfit.slots = Appearance.empty_slots()
	var want_dye := {"cloth": "primary", "leather": "secondary", "fur": "none", "metal": "metal"}   # P54: metal
	for id: String in Appearance.option_ids("garment"):
		var g := Appearance.option(id)
		var r: Dictionary = empty.duplicate(true)
		r.outfit.slots[str(g.slot)]["item"] = id
		assert_eq(Appearance.covered_regions(r, index), Appearance.covered_regions(r),
			"%s: the index's covered regions are the data's %s" % [id, Appearance.covered_regions(r)])
		for m: Variant in index.garments.get(str(g.mesh), []):
			assert_eq(str(index.meshes[m].get("dye", "")), str(want_dye.get(str(g.material), "?")),
				"%s: %s's M10 dye slot is its material's (%s)" % [id, m, g.material])
