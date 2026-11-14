extends RefCounted
## P41 (plan M10 §2.5, §3.1 design 8): scenes/player/giant_model.tscn - a GiantModel root holding the
## instanced glTF (assets/giant/giant.glb, turned 180 degrees about Y so the giant faces -Z) and the
## giant index, read from assets/giant/manifest.json (tools/giant/build_giant.py writes both) with the
## manifest's own sha256 added. Runs before player.gd (tools/build_scenes.gd BUILDERS), whose scene P43
## builds on it. Skipped with a note while the manifest or the glTF is missing.

const MANIFEST := "res://assets/giant/manifest.json"
const GLB := "res://assets/giant/giant.glb"
const OUT := "res://scenes/player/giant_model.tscn"
const SCRIPT := "res://scripts/presentation/giant_model.gd"
## Index fields that hold whole numbers (JSON gives every number back as a float).
const INT_FIELDS := ["layer", "tris", "channel", "id", "design_layers", "scar_layer"]
const INT_LIST_FIELDS := ["covers", "regions", "face", "chest", "back", "arms"]


static func build_all(kit: SceneKit) -> void:
	if not FileAccess.file_exists(MANIFEST) or not ResourceLoader.exists(GLB):
		print("giant_model: skipped (%s or %s is missing: run tools/giant/build_giant.py)" % [MANIFEST, GLB])
		return
	var text := FileAccess.get_file_as_string(MANIFEST)
	var doc: Variant = JSON.parse_string(text)
	if typeof(doc) != TYPE_DICTIONARY or not (doc as Dictionary).has("index"):
		push_error("giant_model: %s has no index" % MANIFEST)
		return
	var root := Node3D.new()
	root.name = "GiantModel"
	root.set_script(load(SCRIPT))
	root.set("index", index_from(doc as Dictionary, text))
	var inst := (load(GLB) as PackedScene).instantiate() as Node3D
	inst.name = "Giant"
	inst.rotation = Vector3(0.0, PI, 0.0)
	root.add_child(inst)
	kit.save(root, OUT)


## The giant index of a parsed manifest: its "index" with whole numbers as ints and the manifest's sha256.
static func index_from(doc: Dictionary, manifest_text: String) -> Dictionary:
	var index: Dictionary = _ints(doc.index.duplicate(true), "")
	index["manifest_sha256"] = manifest_text.sha256_text()
	return index


static func _ints(v: Variant, key: String) -> Variant:
	if v is Dictionary:
		var out := {}
		for k: Variant in v:
			out[k] = _ints(v[k], str(k))
		return out
	if v is Array:
		var arr: Array = []
		for x: Variant in v:
			arr.append(int(x) if INT_LIST_FIELDS.has(key) and (x is float or x is int) else _ints(x, ""))
		return arr
	if v is float and INT_FIELDS.has(key):
		return int(v)
	return v
