extends RefCounted
## Gate B (the M12 review's finding 1): GiantLook.apply's skip-unchanged cache checked against a fresh model. A
## sequence of looks applied to ONE model must leave every shown mesh's look uniforms (and its blend shapes) as a
## fresh model given only the last look has them. Shared by tests/integration/test_giant_look_cache.gd (the
## named sequences) and tests/slow/test_giant_look_cache_random.gd (random sequences).

const MODEL := "res://scenes/player/giant_model.tscn"
const PARAMS := ["dye_color", "fade", "kind", "build", "build_max_m", "bead_mask", "push_m", "pushed",
	"skin_tone", "hair_color", "beard_color", "stubble", "scalp_tint", "beard_tint", "region_tattoo", "region_paint",
	"region_mark", "tattoo_ink", "paint_color", "mark_color", "mark_glow", "scar_layer", "scar_on", "scar_layer_b",
	"scar_on_b", "scar_regions", "scar_regions_b", "hidden_regions", "tip_color", "grey", "length", "iris_color",
	"iris_glow"]


## A model with its materials built, a child of `parent` (the caller frees it).
static func model(parent: Node) -> Node3D:
	var root := (load(MODEL) as PackedScene).instantiate() as Node3D
	parent.add_child(root)
	GiantLook.build_materials(root, root.get("index"), "auto")
	return root


## A sanitized record wearing `slots` (slot -> garment id) with the build (brawn, girth) and `extra` keys.
static func record(slots: Dictionary, build := Vector2.ZERO, extra := {}) -> Dictionary:
	var r := Appearance.default_record()
	for s: String in Appearance.SLOTS:
		r.outfit.slots[s] = {"item": str(slots.get(s, "")), "dye": ""}
	r.build = {"brawn": build.x, "girth": build.y}
	for k: String in extra:
		r[k] = extra[k]
	return Appearance.sanitize(r).record


## {mesh id: {uniform or "bs<n>": value as text}} of the root's shown meshes.
static func state(root: Node3D) -> Dictionary:
	var index: Dictionary = root.get("index")
	var out := {}
	var mats := GiantLook._own_materials(root)
	for id: String in mats:
		var mi := GiantLook.mesh_node(root, index, id)
		if mi == null or not mi.visible:
			continue
		var vals := {}
		for p: String in PARAMS:
			var v: Variant = (mats[id] as ShaderMaterial).get_shader_parameter(p)
			if v != null:
				vals[p] = var_to_str(v)
		if mi.mesh != null:
			for b in mi.get_blend_shape_count():
				vals["bs%d" % b] = snappedf(mi.get_blend_shape_value(b), 0.0001)
		out[id] = vals
	return out


## The differences between the incremental and the fresh state ("" when none).
static func diff(inc: Dictionary, fresh: Dictionary) -> String:
	var out := PackedStringArray()
	for id: String in fresh:
		if not inc.has(id):
			out.append("%s: not shown incrementally" % id)
			continue
		for p: String in fresh[id]:
			if str(inc[id].get(p)) != str(fresh[id][p]):
				out.append("%s.%s: incremental %s, fresh %s" % [id, p, inc[id].get(p), fresh[id][p]])
	for id: String in inc:
		if not fresh.has(id):
			out.append("%s: shown incrementally only" % id)
	return "\n".join(out)


## `records` applied in turn to one model against a fresh model given the last: the differences ("" when none).
static func run(parent: Node, records: Array) -> String:
	var inc := model(parent)
	var index: Dictionary = inc.get("index")
	for rec: Dictionary in records:
		GiantLook.apply(inc, index, Appearance.to_look(rec))
	var fresh := model(parent)
	GiantLook.apply(fresh, index, Appearance.to_look(records[-1]))
	var d := diff(state(inc), state(fresh))
	inc.free()
	fresh.free()
	return d


## A random sequence of `steps` records from seed `seed`: each a random scope's draw on the last, and a random
## garment (or none) in a random slot.
static func random_sequence(seed: int, steps: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var seq: Array = []
	var r := Appearance.default_record()
	var scopes := ["outfit", "build", "hair", "beard", "all", "tattoos", "scars"]
	for step in steps:
		r = Appearance.random_record(rng, scopes[rng.randi_range(0, scopes.size() - 1)], false, "", r)
		var slot: String = Appearance.SLOTS[rng.randi_range(0, Appearance.SLOTS.size() - 1)]
		var opts: Array = [""]
		for id: String in Appearance.option_ids("garment"):
			if str(Appearance.option(id).slot) == slot:
				opts.append(id)
		r.outfit.slots[slot] = {"item": opts[rng.randi_range(0, opts.size() - 1)], "dye": ""}
		r = Appearance.sanitize(r).record
		seq.append(r.duplicate(true))
	return seq
