extends TestSuite
## GiantLook on the real model (P42; plan M10 §2.4, §2.5, §2.13): skipped with a note while
## scenes/player/giant_model.tscn does not exist (P41 builds it in the same wave; the W25 merge runs this).
## The data's mesh, design and garment ids all exist in the model's index; every index mesh has its node
## and a known category; DEFAULT_LOOK applies cleanly; and every option of every set, applied through
## Appearance.to_look and GiantLook.apply with the materials built, sets the expected visibility with
## validate() empty.

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
	var n := 0
	for c: String in Appearance.CATEGORIES:
		for id: String in Appearance.option_ids(c):
			var o := Appearance.option(id)
			var line := Appearance.required_ancestry(o)
			var r := Appearance.default_record()
			match c:
				"skin", "eyes":
					r[c] = id
				"hair":
					r.hair.style = id
				"haircolor":
					r.hair.color = id
				"beard":
					r.beard.style = id
				"tattoo":
					r.tattoos[str(o.region)] = id
				"ink":
					r.tattoos.arms = "tattoo.arm_bands"
					r.tattoos.ink = id
				"paint":
					r.paint.design = id
				"paintcolor":
					r.paint.design = "paint.face_stripes"
					r.paint.color = id
				"scar":
					r.scars = [id]
				"outfit":
					r.outfit.set = id
				"dye":
					r.outfit.primary = id
			var look := Appearance.to_look(r, line if line != "" else "ancestry.stoneblood")
			GiantLook.apply(_root, index, look)
			assert_eq(GiantLook.validate(_root, index, look), PackedStringArray(), "%s: validate() is empty" % id)
			for m: String in GiantLook.meshes_of(index, "hair"):
				assert_eq(GiantLook.mesh_node(_root, index, m).visible, m == str(look.hair_mesh), "%s: %s's visibility" % [id, m])
			for m: String in GiantLook.meshes_of(index, "beard"):
				assert_eq(GiantLook.mesh_node(_root, index, m).visible, m == str(look.beard_mesh), "%s: %s's visibility" % [id, m])
			var shown := {}
			for g: Variant in look.garments:
				for m: Variant in index.garments.get(str(g), []):
					shown[str(m)] = true
			for m: String in GiantLook.meshes_of(index, "garment"):
				assert_eq(GiantLook.mesh_node(_root, index, m).visible, shown.has(m), "%s: %s's visibility" % [id, m])
			n += 1
	assert_true(n >= 70, "every option of the data (%d)" % n)
