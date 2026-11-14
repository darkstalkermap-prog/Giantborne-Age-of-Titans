class_name GiantLook
extends RefCounted
## The one interface between the look's rules and every renderer of the realistic giant (P42; plan M10
## §2.4, §2.5, §2.8; decisions 11, 12, 17): the player's rig (P43), the creator's preview and the character
## sheets (P44). It reads the giant index's format (plan §2.5: the model root's exported `index`), never the
## GiantModel class, so it works on any root that carries the index's mesh nodes - the real model, or a
## test's synthetic one. Presentation only; nothing in the simulation reads it.
##
##   build_materials(root, index, tier)  every index mesh gets its own ShaderMaterial (two instances never
##                                       share one) of its category's shader - body: giant_skin, eyes:
##                                       giant_eye, hair and beard: giant_hair, garment: giant_cloth - with
##                                       the textures of the tier; then the stored look is applied.
##   apply(root, index, look)            shows the look's hair, beard and garment meshes and hides the other
##                                       hair, beard and garment meshes; stores the look on the root; when
##                                       the materials exist, sets every uniform (the region arrays always
##                                       filled, 0 = none). Without materials (headless, the skinned layers
##                                       off) it only sets visibility and stores the look.
##   validate(root, index, look)         the problems: ids the index does not know (meshes, garments,
##                                       designs), index meshes without their node, and every uniform name
##                                       GiantLook sets that the shader does not declare
##                                       (get_shader_uniform_list(): a headless material stores a misspelled
##                                       name without complaint). [] = clean. Never an engine error.
##   materials(root)                     the root's ShaderMaterials (RigPaint's tint and flash path, P43).
##
## Tiers (decision 17): "web" draws every map from the index's tiers.web folder (512 px), "hi" the normal
## and ORM maps from tiers.hi (1024 px) - each one falling back to the web folder when its file is missing
## (a Web export without tex_hi/) - and "auto" picks "hi" when tex_hi/normal.png exists, unless
## --giant-tier=web forces the web tier (--giant-tier=hi forces hi). Textures are held in a static cache
## for the whole process (a cache miss costs about 20-30 ms).
##
## File names the asset (P41) and this file agree on: <tier folder>/albedo.png, normal.png, orm.png (R AO,
## G roughness, B thickness), masks.png (R stubble, G scalp, B brows, A lips). The other maps are named by
## the index (texture_path): the real index (P41) gives a hair mesh's "atlas" and a garment's "detail" as
## names ("hair_atlas"; "weave", "leather", "fur") that its `textures` table maps to paths (`hair_atlas`,
## `detail_<kind>`, `designs` for the design array); a synthetic index may give paths instead; without
## either, DEFAULT_TEXTURES. A garment's detail kind is its entry's "detail" name, else GARMENT_DETAIL of
## its garment. A sampler whose texture does not load is a problem validate() reports.

const SKIN_SHADER := preload("res://assets/shaders/giant_skin.gdshader")
const HAIR_SHADER := preload("res://assets/shaders/giant_hair.gdshader")
const EYE_SHADER := preload("res://assets/shaders/giant_eye.gdshader")
const CLOTH_SHADER := preload("res://assets/shaders/giant_cloth.gdshader")

## The Wanderer (plan M10 §2.4), so the model draws before and without the data; Appearance.to_look of the
## default record equals it within 1/255 per colour channel (hex-parsed colours differ in the last bit).
const DEFAULT_LOOK := {
	"skin_tone": Color(0.690196, 0.478431, 0.384314),       # #b07a62 skin.ruddy
	"eye_color": Color(0.298039, 0.450980, 0.380392),       # #4c7361 eyes.grey_green
	"eye_glow": 0.0,
	"hair_mesh": "Hair_long_back",
	"beard_mesh": "Beard_full",
	"hair_color": Color(0.290196, 0.172549, 0.101961),      # #4a2c1a haircolor.chestnut
	"hair_tip": Color(0.431373, 0.290196, 0.188235),        # #6e4a30
	"hair_grey": 0.12,
	"beard_color": Color(0.290196, 0.172549, 0.101961),     # the hair's (beard.color "")
	"beard_tip": Color(0.431373, 0.290196, 0.188235),
	"beard_grey": 0.2,
	"scalp_tint": 1.0,
	"stubble": 0.8,
	"beard_tint": 1.0,
	"tattoos": [],
	"paint": {},
	"mark": {},
	"scars": [],
	"garments": ["braies", "belt"],
	"dye_primary": Color(0.450980, 0.380392, 0.290196),     # #73614a dye.undyed
	"dye_secondary": Color(0.164706, 0.149020, 0.133333),   # #2a2622 dye.dark_leather
}

## The skin's bake was made at this tone (plan M10 §2.8): the shader scales the albedo by tone / bake tone.
const BAKE_TONE := Color(0.69, 0.53, 0.44)
## How far (model metres, stage 1) a region under clothing sinks inside.
const HIDE_SHRINK_M := 0.03
const REGIONS := 16
const TIERS := ["auto", "web", "hi"]
const TEX_WEB := "res://assets/giant/tex/"
const TEX_HI := "res://assets/giant/tex_hi/"
const DESIGN_ARRAY := "res://assets/giant/designs.png"
## The skin's maps: uniform -> file name in a tier folder; the hi tier holds only HI_MAPS.
const SKIN_MAPS := {"albedo_tex": "albedo.png", "normal_tex": "normal.png", "orm_tex": "orm.png",
	"mask_tex": "masks.png"}
const HI_MAPS := ["normal_tex", "orm_tex"]
const HAIR_ATLAS := "res://assets/giant/hair_atlas.png"
const CLOTH_DETAIL := {"weave": "res://assets/giant/cloth_weave.png", "leather": "res://assets/giant/cloth_leather.png",
	"fur": "res://assets/giant/cloth_fur.png"}
## The paths of the index's texture names when the index has no `textures` table (a synthetic index).
const DEFAULT_TEXTURES := {"hair_atlas": HAIR_ATLAS, "designs": DESIGN_ARRAY, "detail_weave": CLOTH_DETAIL.weave,
	"detail_leather": CLOTH_DETAIL.leather, "detail_fur": CLOTH_DETAIL.fur}
## The detail kind of each floor garment when its index entry names none (a garment not listed is cloth).
const GARMENT_DETAIL := {"braies": "weave", "tunic": "weave", "jerkin": "leather", "belt": "leather",
	"bracers": "leather", "boots": "leather", "furs": "fur"}
## A garment whose index entry has no dye slot ("none": the furs) keeps this colour.
const NATURAL_DYE := Color(0.36, 0.30, 0.24)
## The detail map's strength per kind.
const DETAIL_STRENGTH := {"weave": 0.35, "leather": 0.25, "fur": 0.45}

## The uniforms GiantLook sets, per shader kind (validate() checks them against the shaders), and the two
## every giant shader declares for RigPaint.
const UNIFORMS := {
	"skin": ["albedo_tex", "normal_tex", "orm_tex", "mask_tex", "design_tex", "skin_tone", "bake_tone", "hair_color",
		"beard_color", "stubble", "scalp_tint", "beard_tint", "brows", "region_tattoo", "region_paint", "region_mark",
		"tattoo_ink", "paint_color", "mark_color", "mark_glow", "scar_layer", "scar_on", "hidden_regions", "hide_shrink"],
	"hair": ["hair_atlas", "hair_color", "tip_color", "grey"],
	"eye": ["iris_color", "iris_glow"],
	"cloth": ["detail_tex", "dye_color", "detail_strength", "fade"],
}
const PAINT_UNIFORMS := ["tint", "flash"]
const KIND_OF_CATEGORY := {"body": "skin", "eyes": "eye", "hair": "hair", "beard": "hair", "garment": "cloth"}

const META_LOOK := "giant_look"
const META_MATERIALS := "giant_look_materials"
const META_TIER := "giant_look_tier"
const META_NAMES := "giant_look_names"
## On a material: uniform -> the texture path GiantLook asked for (validate() names it when it did not load).
const META_TEX := "giant_look_textures"
## On a root: the instance id of the root its materials and node cache were made for. Node.duplicate() copies
## a node's metadata, so a copy carries its original's; GiantLook ignores them there (and rebuilds the copy's
## own materials on its first apply).
const META_OWNER := "giant_look_owner"
const META_NODES := "giant_look_nodes"

## The texture tier the command line forces (--giant-tier=web | hi; "" = none). Tests set it directly.
static var forced_tier := _cli_tier()
static var _tex_cache := {}
static var _declared_cache := {}
static var _sampler_cache := {}


static func _cli_tier() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--giant-tier="):
			var t := arg.substr(13).strip_edges().to_lower()
			if t in ["web", "hi"]:
				return t
	return ""


# --------------------------------------------------------------------------- the index

## The shader kind ("skin", "eye", "hair", "cloth") of an index mesh category ("" for an unknown one).
static func shader_kind(category: String) -> String:
	return str(KIND_OF_CATEGORY.get(category, ""))


static func shader_for(kind: String) -> Shader:
	match kind:
		"skin":
			return SKIN_SHADER
		"hair":
			return HAIR_SHADER
		"eye":
			return EYE_SHADER
		"cloth":
			return CLOTH_SHADER
	return null


static func _meshes(index: Dictionary) -> Dictionary:
	return index.get("meshes", {}) if typeof(index.get("meshes")) == TYPE_DICTIONARY else {}


static func _garments(index: Dictionary) -> Dictionary:
	return index.get("garments", {}) if typeof(index.get("garments")) == TYPE_DICTIONARY else {}


static func _designs(index: Dictionary) -> Dictionary:
	return index.get("designs", {}) if typeof(index.get("designs")) == TYPE_DICTIONARY else {}


## The MeshInstance3D of an index mesh under `root` (its entry's "node", else the id), or null.
static func mesh_node(root: Node, index: Dictionary, mesh_id: String) -> MeshInstance3D:
	if root == null:
		return null
	var entry: Variant = _meshes(index).get(mesh_id)
	var node_name := str((entry as Dictionary).get("node", mesh_id)) if typeof(entry) == TYPE_DICTIONARY else mesh_id
	var cache := _node_cache(root)
	var hit: Variant = cache.get(node_name)
	if is_instance_valid(hit) and hit is MeshInstance3D and root.is_ancestor_of(hit):
		return hit
	var found := root.find_child(node_name, true, false) as MeshInstance3D
	if found != null:
		cache[node_name] = found
	return found


## The root's own node cache (node name -> MeshInstance3D): a fresh one on a copy that carries its
## original's (Node.duplicate() copies metadata, the cached nodes and the Dictionary itself included).
static func _node_cache(root: Node) -> Dictionary:
	var meta: Variant = root.get_meta(META_NODES, {})
	if typeof(meta) == TYPE_DICTIONARY and int((meta as Dictionary).get("owner", 0)) == root.get_instance_id():
		return meta.nodes
	var fresh := {"owner": root.get_instance_id(), "nodes": {}}
	root.set_meta(META_NODES, fresh)
	return fresh.nodes


## The root's own materials (mesh id -> ShaderMaterial; {} before build_materials, and on a copy whose
## metadata came from its original).
static func _own_materials(root: Node) -> Dictionary:
	if root == null or int(root.get_meta(META_OWNER, 0)) != root.get_instance_id():
		return {}
	var mats: Variant = root.get_meta(META_MATERIALS, {})
	return mats if typeof(mats) == TYPE_DICTIONARY else {}


## True when the root carries materials made for another root (a duplicate()'s copy of its original's).
static func _inherited_materials(root: Node) -> bool:
	return root != null and root.has_meta(META_MATERIALS) and int(root.get_meta(META_OWNER, 0)) != root.get_instance_id()


## The index meshes of `category` ("hair", "beard", ...), sorted.
static func meshes_of(index: Dictionary, category: String) -> PackedStringArray:
	var out := PackedStringArray()
	var meshes := _meshes(index)
	for id: Variant in meshes:
		if typeof(meshes[id]) == TYPE_DICTIONARY and str((meshes[id] as Dictionary).get("category", "")) == category:
			out.append(str(id))
	out.sort()
	return out


## The bitmask of body regions the given garments' meshes cover (their index "covers"): the skin's
## hidden_regions.
static func hidden_regions_mask(index: Dictionary, garments: Variant) -> int:
	var mask := 0
	for r in Appearance.covered_body_regions(garments, index):
		if r >= 0 and r < REGIONS:
			mask |= 1 << r
	return mask


## The skin's region arrays of `look`: {"tattoo", "paint", "mark"}, each REGIONS codes (layer * 4 +
## channel + 1 of the design drawn in that body region, 0 = none). Unknown designs are left out.
static func region_codes(index: Dictionary, look: Dictionary) -> Dictionary:
	var out := {"tattoo": _zeros(), "paint": _zeros(), "mark": _zeros()}
	var designs := _designs(index)
	var place := func(kind: String, design_id: String) -> void:
		var d: Variant = designs.get(design_id)
		if typeof(d) != TYPE_DICTIONARY:
			return
		var code := int((d as Dictionary).get("layer", 0)) * 4 + int((d as Dictionary).get("channel", 0)) + 1
		var arr: PackedInt32Array = out[kind]
		for r: Variant in (d as Dictionary).get("regions", []):
			if SchemaUtil.is_number(r) and int(r) >= 0 and int(r) < REGIONS:
				arr[int(r)] = code
		out[kind] = arr
	for t: Variant in look.get("tattoos", []):
		if typeof(t) == TYPE_DICTIONARY:
			place.call("tattoo", str((t as Dictionary).get("design", "")))
	if typeof(look.get("paint")) == TYPE_DICTIONARY and not (look.paint as Dictionary).is_empty():
		place.call("paint", str(look.paint.get("design", "")))
	if typeof(look.get("mark")) == TYPE_DICTIONARY and not (look.mark as Dictionary).is_empty():
		place.call("mark", str(look.mark.get("design", "")))
	return out


static func _zeros() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(REGIONS)
	a.fill(0)
	return a


## The scar uniforms of `look`: {"layer": the layer of its first known scar (0 when none), "on": a
## Vector4 with 1 in the channel of every scar on that layer}. Scars on another layer are left out
## (validate() reports them).
static func scar_uniforms(index: Dictionary, scars: Variant) -> Dictionary:
	var designs := _designs(index)
	var layer := -1
	var on := Vector4.ZERO
	for s: Variant in (scars if typeof(scars) == TYPE_ARRAY else []):
		var d: Variant = designs.get(str(s))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var l := int((d as Dictionary).get("layer", 0))
		if layer < 0:
			layer = l
		if l == layer:
			on[clampi(int((d as Dictionary).get("channel", 0)), 0, 3)] = 1.0
	if layer < 0:
		for id: Variant in designs:
			if typeof(designs[id]) == TYPE_DICTIONARY and str((designs[id] as Dictionary).get("kind", "")) == "scar":
				layer = int((designs[id] as Dictionary).get("layer", 0))
				break
	return {"layer": maxi(layer, 0), "on": on}


# --------------------------------------------------------------------------- tiers and textures

## The tier `tier` ("auto", "web", "hi") stands for here: forced_tier wins; "auto" is "hi" when the hi
## folder's normal map exists. `exists` (tests) replaces ResourceLoader.exists.
static func resolve_tier(tier: String, index: Dictionary = {}, exists: Callable = Callable()) -> String:
	if forced_tier in ["web", "hi"]:
		return forced_tier
	if tier in ["web", "hi"]:
		return tier
	var check := exists if exists.is_valid() else Callable(ResourceLoader, "exists")
	return "hi" if bool(check.call(_tier_dir(index, "hi") + str(SKIN_MAPS.normal_tex))) else "web"


static func _tier_dir(index: Dictionary, tier: String) -> String:
	var tiers: Dictionary = index.get("tiers", {}) if typeof(index.get("tiers")) == TYPE_DICTIONARY else {}
	var dir := str(tiers.get(tier, TEX_HI if tier == "hi" else TEX_WEB))
	return dir if dir.ends_with("/") else dir + "/"


## The skin's map paths for `tier` (uniform -> path): every map from the web folder, the HI_MAPS from the hi
## folder when the tier is "hi" and the file exists there. `exists` (tests) replaces ResourceLoader.exists.
static func map_paths(index: Dictionary, tier: String, exists: Callable = Callable()) -> Dictionary:
	var check := exists if exists.is_valid() else Callable(ResourceLoader, "exists")
	var t := resolve_tier(tier, index, check)
	var out := {}
	for u: String in SKIN_MAPS:
		var web := _tier_dir(index, "web") + str(SKIN_MAPS[u])
		var hi := _tier_dir(index, "hi") + str(SKIN_MAPS[u])
		out[u] = hi if t == "hi" and u in HI_MAPS and bool(check.call(hi)) else web
	return out


## The path of a texture the index names. `ref` is a mesh entry's "atlas" or "detail" (or "" for none):
## a path ("res://...", a synthetic index) is used as it is; a name is looked up in index.textures under
## `prefix` + ref ("detail_" + "leather") and then ref, else in DEFAULT_TEXTURES when the index has no
## `textures` table; "" (a texture that is not there, which validate() reports) for a name the index's
## table does not have. An empty ref stands for `default_key` ("hair_atlas", "detail_weave", "designs").
static func texture_path(index: Dictionary, ref: String, prefix: String, default_key: String) -> String:
	if ref.contains("://"):
		return ref
	var table: Variant = index.get("textures")
	var keys := [default_key] if ref == "" else [prefix + ref, ref]
	for key: String in keys:
		if typeof(table) == TYPE_DICTIONARY and typeof((table as Dictionary).get(key)) == TYPE_STRING:
			return str(table[key])
		if typeof(table) != TYPE_DICTIONARY and DEFAULT_TEXTURES.has(key):
			return str(DEFAULT_TEXTURES[key])
	return ""


## A texture by path, from the static cache (null when the file does not exist).
static func texture(path: String) -> Texture:
	if path == "":
		return null
	if _tex_cache.has(path):
		return _tex_cache[path]
	var tex: Texture = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture
	_tex_cache[path] = tex
	return tex


## Forgets the cached textures (tests that swap files).
static func clear_texture_cache() -> void:
	_tex_cache.clear()


# --------------------------------------------------------------------------- materials

## Gives every index mesh under `root` its own ShaderMaterial (material_override) of its category's shader
## with the textures of `tier`, then applies the root's stored look (DEFAULT_LOOK when none). Calling it
## again rebuilds them (a tier change).
static func build_materials(root: Node3D, index: Dictionary, tier: String) -> void:
	if root == null:
		return
	var maps := map_paths(index, tier)
	var mats := {}
	var meshes := _meshes(index)
	for id: Variant in meshes:
		var entry: Dictionary = meshes[id] if typeof(meshes[id]) == TYPE_DICTIONARY else {}
		var kind := shader_kind(str(entry.get("category", "")))
		var mi := mesh_node(root, index, str(id))
		if kind == "" or mi == null:
			continue
		var mat := ShaderMaterial.new()
		mat.shader = shader_for(kind)
		match kind:
			"skin":
				for u: String in maps:
					_set_texture(mat, u, str(maps[u]))
				_set_texture(mat, "design_tex", str(index.get("design_array", texture_path(index, "", "", "designs"))))
				set_param(mat, "bake_tone", BAKE_TONE)
				set_param(mat, "hide_shrink", HIDE_SHRINK_M)
				set_param(mat, "brows", 1.0)
			"hair":
				_set_texture(mat, "hair_atlas", texture_path(index, str(entry.get("atlas", "")), "", "hair_atlas"))
			"cloth":
				var detail := _detail_kind(str(id), entry, index)
				var ref := str(entry.get("detail", ""))
				_set_texture(mat, "detail_tex", texture_path(index, ref, "detail_", "detail_" + detail))
				set_param(mat, "detail_strength", float(DETAIL_STRENGTH.get(detail, 0.3)))
		mi.material_override = mat
		mats[str(id)] = mat
	root.set_meta(META_MATERIALS, mats)
	root.set_meta(META_OWNER, root.get_instance_id())
	root.set_meta(META_TIER, resolve_tier(tier, index))
	apply(root, index, root.get_meta(META_LOOK, DEFAULT_LOOK))


## A sampler uniform from a path (the texture cache), the path remembered for validate().
static func _set_texture(mat: ShaderMaterial, uniform: String, path: String) -> void:
	set_param(mat, uniform, texture(path))
	var paths: Dictionary = mat.get_meta(META_TEX, {})
	paths[uniform] = path
	mat.set_meta(META_TEX, paths)


## The detail kind ("weave" | "leather" | "fur") of a garment mesh: its entry's "detail" when that is a
## name of DETAIL_STRENGTH (the real index), else its "detail_kind", else GARMENT_DETAIL of its garment.
static func _detail_kind(mesh_id: String, entry: Dictionary, index: Dictionary) -> String:
	if DETAIL_STRENGTH.has(str(entry.get("detail", ""))):
		return str(entry.detail)
	if entry.has("detail_kind"):
		return str(entry.detail_kind)
	var garments := _garments(index)
	for g: Variant in garments:
		if (garments[g] as Array).has(mesh_id) if typeof(garments[g]) == TYPE_ARRAY else false:
			return str(GARMENT_DETAIL.get(str(g), "weave"))
	return "weave"


## The root's ShaderMaterials (built by build_materials; [] before), in index order.
static func materials(root: Node) -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	if root == null:
		return out
	var mats := _own_materials(root)
	for id: Variant in mats:
		if mats[id] is ShaderMaterial:
			out.append(mats[id])
	return out


## The tier the root's materials were built with ("" before build_materials, and on a copy that has not
## built its own).
static func built_tier(root: Node) -> String:
	return str(root.get_meta(META_TIER, "")) if root != null and not _own_materials(root).is_empty() else ""


## The look last applied to the root (DEFAULT_LOOK before any).
static func applied_look(root: Node) -> Dictionary:
	return (root.get_meta(META_LOOK, DEFAULT_LOOK) as Dictionary).duplicate(true) if root != null else DEFAULT_LOOK.duplicate(true)


## Sets a uniform and remembers its name on the material (validate() checks every name set).
static func set_param(mat: ShaderMaterial, uniform: String, value: Variant) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(uniform, value)
	var names: Dictionary = mat.get_meta(META_NAMES, {})
	names[uniform] = true
	mat.set_meta(META_NAMES, names)


# --------------------------------------------------------------------------- apply

## The look on one model instance; see the class notes. A look's missing keys take DEFAULT_LOOK's.
static func apply(root: Node3D, index: Dictionary, look: Dictionary) -> void:
	if root == null:
		return
	var l := complete(look)
	root.set_meta(META_LOOK, l.duplicate(true))
	if _inherited_materials(root):
		# A copy of a model whose materials were built: its meshes still draw with its original's. Give it
		# its own (build_materials applies the look just stored).
		build_materials(root, index, str(root.get_meta(META_TIER, "auto")))
		return
	var shown := {}
	var garments := _garments(index)
	for g: Variant in l.garments:
		for m: Variant in (garments.get(str(g), []) if typeof(garments.get(str(g))) == TYPE_ARRAY else []):
			shown[str(m)] = true
	var meshes := _meshes(index)
	for id: Variant in meshes:
		var entry: Dictionary = meshes[id] if typeof(meshes[id]) == TYPE_DICTIONARY else {}
		var mi := mesh_node(root, index, str(id))
		if mi == null:
			continue
		match str(entry.get("category", "")):
			"hair":
				mi.visible = str(id) == str(l.hair_mesh)
			"beard":
				mi.visible = str(id) == str(l.beard_mesh)
			"garment":
				mi.visible = shown.has(str(id))
	var mats := _own_materials(root)
	if mats.is_empty():
		return
	var hidden := hidden_regions_mask(index, l.garments)
	var codes := region_codes(index, l)
	var scars := scar_uniforms(index, l.scars)
	var paint: Dictionary = l.paint if typeof(l.paint) == TYPE_DICTIONARY else {}
	var mark: Dictionary = l.mark if typeof(l.mark) == TYPE_DICTIONARY else {}
	var ink: Color = (l.tattoos[0] as Dictionary).get("ink", Color(0.1, 0.18, 0.4)) if not (l.tattoos as Array).is_empty() \
		else Color(0.1, 0.18, 0.4)
	for id: Variant in mats:
		var mat: ShaderMaterial = mats[id]
		var entry: Dictionary = meshes.get(id, {}) if typeof(meshes.get(id)) == TYPE_DICTIONARY else {}
		var category := str(entry.get("category", ""))
		match shader_kind(category):
			"skin":
				set_param(mat, "skin_tone", l.skin_tone)
				set_param(mat, "hair_color", l.hair_color)
				set_param(mat, "beard_color", l.beard_color)
				set_param(mat, "scalp_tint", float(l.scalp_tint))
				set_param(mat, "stubble", float(l.stubble))
				set_param(mat, "beard_tint", float(l.beard_tint) if str(l.beard_mesh) != "" else 0.0)
				set_param(mat, "region_tattoo", codes.tattoo)
				set_param(mat, "region_paint", codes.paint)
				set_param(mat, "region_mark", codes.mark)
				set_param(mat, "tattoo_ink", ink)
				set_param(mat, "paint_color", paint.get("color", Color(0.86, 0.84, 0.78)))
				set_param(mat, "mark_color", mark.get("color", Color(0.44, 0.49, 0.55)))
				set_param(mat, "mark_glow", float(mark.get("glow", 0.0)))
				set_param(mat, "scar_layer", int(scars.layer))
				set_param(mat, "scar_on", scars.on)
				set_param(mat, "hidden_regions", hidden)
			"hair":
				var beard := category == "beard"
				set_param(mat, "hair_color", l.beard_color if beard else l.hair_color)
				set_param(mat, "tip_color", l.beard_tip if beard else l.hair_tip)
				set_param(mat, "grey", float(l.beard_grey if beard else l.hair_grey))
			"eye":
				set_param(mat, "iris_color", l.eye_color)
				set_param(mat, "iris_glow", float(l.eye_glow))
			"cloth":
				match str(entry.get("dye", "primary")):
					"primary":
						set_param(mat, "dye_color", l.dye_primary)
					"secondary":
						set_param(mat, "dye_color", l.dye_secondary)
					_:
						set_param(mat, "dye_color", NATURAL_DYE)
				set_param(mat, "fade", 0.0)


## The creator's "Hidden by your clothing" fade (0-1) on the garments' materials (none before
## build_materials).
static func set_garment_fade(root: Node, index: Dictionary, fade: float) -> void:
	var mats := _own_materials(root)
	var meshes := _meshes(index)
	for id: Variant in mats:
		if typeof(meshes.get(id)) == TYPE_DICTIONARY and str((meshes[id] as Dictionary).get("category", "")) == "garment":
			set_param(mats[id], "fade", clampf(fade, 0.0, 1.0))


## `look` with every key DEFAULT_LOOK has (its own values kept), a copy.
static func complete(look: Dictionary) -> Dictionary:
	var l := DEFAULT_LOOK.duplicate(true)
	for k: Variant in look:
		l[k] = look[k]
	for key: String in ["tattoos", "scars", "garments"]:
		if typeof(l[key]) != TYPE_ARRAY:
			l[key] = []
	for key: String in ["paint", "mark"]:
		if typeof(l[key]) != TYPE_DICTIONARY:
			l[key] = {}
	return l


# --------------------------------------------------------------------------- validate

## The names in `names` that `shader` does not declare as uniforms (get_shader_uniform_list).
static func undeclared_uniforms(shader: Shader, names: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if shader == null:
		return out
	var declared: Dictionary = _declared_cache.get(shader.resource_path, {})
	if declared.is_empty():
		for u: Dictionary in shader.get_shader_uniform_list():
			declared[str(u.name)] = true
		if shader.resource_path != "":
			_declared_cache[shader.resource_path] = declared
	for n: Variant in names:
		if not declared.has(str(n)):
			out.append(str(n))
	return out


## The sampler uniforms `shader` declares (get_shader_uniform_list: the Object-typed ones).
static func sampler_uniforms(shader: Shader) -> Dictionary:
	if shader == null:
		return {}
	var out: Dictionary = _sampler_cache.get(shader.resource_path, {})
	if out.is_empty():
		for u: Dictionary in shader.get_shader_uniform_list():
			if int(u.get("type", 0)) == TYPE_OBJECT:
				out[str(u.name)] = true
		if shader.resource_path != "":
			_sampler_cache[shader.resource_path] = out
	return out


## The problems of drawing `look` on `root` (see the class notes); [] = clean.
static func validate(root: Node, index: Dictionary, look: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var l := complete(look)
	var meshes := _meshes(index)
	var designs := _designs(index)
	var garments := _garments(index)
	for key: String in ["hair_mesh", "beard_mesh"]:
		var m := str(l[key])
		if m != "" and not meshes.has(m):
			out.append("%s: the index has no mesh '%s'" % [key, m])
	for g: Variant in l.garments:
		if not garments.has(str(g)):
			out.append("garments: the index has no garment '%s'" % g)
	var wanted := []   # [design id, kind]
	for t: Variant in l.tattoos:
		wanted.append([str((t as Dictionary).get("design", "")) if typeof(t) == TYPE_DICTIONARY else str(t), "tattoo"])
	if not (l.paint as Dictionary).is_empty():
		wanted.append([str(l.paint.get("design", "")), "paint"])
	if not (l.mark as Dictionary).is_empty():
		wanted.append([str(l.mark.get("design", "")), "mark"])
	for s: Variant in l.scars:
		wanted.append([str(s), "scar"])
	var scar_layer := -1
	for w: Array in wanted:
		var d: Variant = designs.get(w[0])
		if typeof(d) != TYPE_DICTIONARY:
			out.append("%s: the index has no design '%s'" % [w[1], w[0]])
			continue
		var kind := str((d as Dictionary).get("kind", w[1]))
		if kind != w[1]:
			out.append("%s: the design '%s' is a %s" % [w[1], w[0], kind])
		if w[1] == "scar":
			var layer := int((d as Dictionary).get("layer", 0))
			if scar_layer < 0:
				scar_layer = layer
			elif layer != scar_layer:
				out.append("scar: '%s' is on layer %d, not the scars' layer %d (one layer of four scars)" % [w[0], layer, scar_layer])
	for id: Variant in meshes:
		if typeof(meshes[id]) != TYPE_DICTIONARY:
			out.append("index: the mesh entry '%s' is not an object" % id)
			continue
		if shader_kind(str((meshes[id] as Dictionary).get("category", ""))) == "":
			out.append("index: the mesh '%s' has an unknown category '%s'" % [id, (meshes[id] as Dictionary).get("category", "")])
		if root != null and mesh_node(root, index, str(id)) == null:
			out.append("index: no node for the mesh '%s'" % id)
	for kind: String in UNIFORMS:
		for n in undeclared_uniforms(shader_for(kind), UNIFORMS[kind] + PAINT_UNIFORMS):
			out.append("giant_%s.gdshader does not declare the uniform '%s'" % [kind, n])
	var mats := _own_materials(root)
	for id: Variant in mats:
		var mat: ShaderMaterial = mats[id]
		var names: Dictionary = mat.get_meta(META_NAMES, {})
		for n in undeclared_uniforms(mat.shader, names.keys()):
			out.append("%s: its shader does not declare the uniform '%s'" % [id, n])
		var samplers := sampler_uniforms(mat.shader)
		var paths: Dictionary = mat.get_meta(META_TEX, {})
		for n: Variant in names:
			if samplers.has(n) and mat.get_shader_parameter(str(n)) == null:
				out.append("%s: the texture of '%s' did not load ('%s')" % [id, n, paths.get(n, "")])
		if mat.shader == SKIN_SHADER:
			for arr: String in ["region_tattoo", "region_paint", "region_mark"]:
				var v: Variant = mat.get_shader_parameter(arr)
				if not (v is PackedInt32Array) or (v as PackedInt32Array).size() != REGIONS:
					out.append("%s: %s is not filled (%d codes, 0 = none)" % [id, arr, REGIONS])
	return out
