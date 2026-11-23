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
##   apply(root, index, look)            shows the look's hair, beard, garment, accessory and bead meshes and
##                                       hides the others of those categories; stores the look on the root;
##                                       sets the face's blend shapes where a shown mesh has them; when the
##                                       materials exist, sets every uniform (the region arrays always filled,
##                                       0 = none). Without materials (headless, the skinned layers off) it only
##                                       sets visibility and stores the look.
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
##
## The look by slot (P53; plan M11 §2.5): `garments` is an Array of {"mesh": an index garment (its meshes in
## index.garments) or a garment mesh, "dye": Color, "kind": "cloth" | "leather" | "fur" | "metal"}, each garment
## drawn in its own dye (a metal one with the cloth shader's metal response); `build` (Vector2: brawn, girth,
## each -1 to 1) pushes the skin and the garments along their normals by the meshes' build weights (COLOR.g,
## .b) times the index's build_max_m, and the model's shadow proxy with them (GiantModel.apply_build); `face`
## (the face sliders) sets the blend shapes of those names on every shown mesh that has them (none before
## P56: then ignored); `accessories` and `hair_beads` / `beard_beads` are index mesh ids shown (none before P54
## and P56); `paint` is an Array of at most two {"design", "color"}. M10's shape - garments as index garment
## ids with `dye_primary` / `dye_secondary` by each mesh's index "dye", and `paint` as one dictionary - is still
## drawn as it was (the tests' and the sheets' hand-made looks).

const SKIN_SHADER := preload("res://assets/shaders/giant_skin.gdshader")
const HAIR_SHADER := preload("res://assets/shaders/giant_hair.gdshader")
const EYE_SHADER := preload("res://assets/shaders/giant_eye.gdshader")
const CLOTH_SHADER := preload("res://assets/shaders/giant_cloth.gdshader")
const SHELL_SHADER := preload("res://assets/shaders/giant_shell.gdshader")

## The Wanderer (plan M10 §2.4), so the model draws before and without the data; Appearance.to_look of the
## default record equals it within 1/255 per colour channel (hex-parsed colours differ in the last bit).
## P53 restated it in the look v2's shape (plan M11 §2.5) with the Wanderer's values unchanged.
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
	"hair_length": 1.0,                                      # P46: the share of the cards' length drawn
	"beard_length": 1.0,
	"scalp_tint": 1.0,
	"stubble": 0.8,
	"beard_tint": 1.0,
	"build": Vector2.ZERO,                                   # P53: brawn, girth
	"face": {"jaw": 0.0, "chin": 0.0, "nose": 0.0, "brow": 0.0, "cheeks": 0.0, "age": 0.0},
	"hair_beads": "",
	"beard_beads": "",
	"tattoos": [],
	"paint": [],
	"mark": {},
	"scars": [],
	"garments": [
		{"mesh": "belt", "dye": Color(0.164706, 0.149020, 0.133333), "kind": "leather"},   # #2a2622 dye.dark_leather
		{"mesh": "braies", "dye": Color(0.450980, 0.380392, 0.290196), "kind": "cloth"},   # #73614a dye.undyed
	],
	"accessories": [],
}
## The dyes of an M10-shaped look's garments without dye_primary / dye_secondary (the Wanderer's).
const LEGACY_PRIMARY := Color(0.450980, 0.380392, 0.290196)
const LEGACY_SECONDARY := Color(0.164706, 0.149020, 0.133333)

## The tone the skin's albedo is drawn at as it was baked: the shader scales the albedo by tone / bake tone. It
## is the default tone's colour (#b07a62, skin.ruddy; DEFAULT_LOOK.skin_tone), so the default look draws the
## albedo exactly as the kit baked it - the skin of the approved renders - and every other tone is that albedo
## scaled by its swatch against the default's. Until the M10 gate (OR-1) it was the kit's own parameter
## (0.69, 0.53, 0.44; plan M10 §2.8), which made the default look the bake times (1, 0.80, 0.74) in linear
## light: a saturated orange-red in the world's light (docs/systems/P46.md, "The M10 gate").
const BAKE_TONE := Color(0.690196, 0.478431, 0.384314)
## The share of a long beard's card over which its strands end one by one (the hair shader's tip_thin; the
## M10 gate, LC-6: the full beard's lower edge was stepped blocks). Hair keeps its tips as the atlas draws them.
const BEARD_TIP_THIN := 0.45
## The second look lane: every other beard's (its short cards ended square at the cheeks); the hair shader also narrows
## a card towards its tip where tip_thin is set.
const BEARD_SHORT_TIP_THIN := 0.18
## The beard meshes whose cards are long locks (giant_hair's styles without "locks": False): only their tips
## thin out. The short and the braided beard's cards are too short for it (they showed gaps on the cheeks).
const LOCK_BEARDS := ["Beard_full", "Beard_forked", "Beard_long_forked"]   # P56: the long forked beard's locks too
## How far a card's shading turns from its own facing towards the style's head-centred normal (P51; the hair
## shader's volume_normal; braids and beads take their tube's normal whatever it is).
const VOLUME_NORMAL := 0.75
## How far (model metres, stage 1) a region under clothing sinks inside.
const HIDE_SHRINK_M := 0.03
const REGIONS := 16
const TIERS := ["auto", "web", "hi"]
const TEX_WEB := "res://assets/giant/tex/"
const TEX_HI := "res://assets/giant/tex_hi/"
const DESIGN_ARRAY := "res://assets/giant/designs.png"
## The skin's maps: uniform -> file name in a tier folder; the hi tier holds only HI_MAPS.
const SKIN_MAPS := {"albedo_tex": "albedo.png", "normal_tex": "normal.png", "orm_tex": "orm.png",
	"mask_tex": "masks.png", "curvature_tex": "curvature.png"}
const HI_MAPS := ["normal_tex", "orm_tex"]
const HAIR_ATLAS := "res://assets/giant/hair_atlas.png"
const CLOTH_DETAIL := {"weave": "res://assets/giant/cloth_weave.png", "leather": "res://assets/giant/cloth_leather.png",
	"fur": "res://assets/giant/cloth_fur.png", "metal": "res://assets/giant/cloth_metal.png",
	"mail": "res://assets/giant/cloth_mail.png", "scale": "res://assets/giant/cloth_scale.png",
	"bone": "res://assets/giant/cloth_leather.png", "stone": "res://assets/giant/cloth_metal.png"}
## The skin's pre-integrated subsurface lookup (P51; the index's textures.skin_lut).
const SKIN_LUT := "res://assets/giant/tex/skin_lut.png"
## The paths of the index's texture names when the index has no `textures` table (a synthetic index).
const DEFAULT_TEXTURES := {"hair_atlas": HAIR_ATLAS, "designs": DESIGN_ARRAY, "detail_weave": CLOTH_DETAIL.weave,
	"detail_leather": CLOTH_DETAIL.leather, "detail_fur": CLOTH_DETAIL.fur, "detail_metal": CLOTH_DETAIL.metal,
	"detail_mail": CLOTH_DETAIL.mail, "detail_scale": CLOTH_DETAIL.scale, "detail_bone": CLOTH_DETAIL.bone,
	"detail_stone": CLOTH_DETAIL.stone, "skin_lut": SKIN_LUT, "shell_strands": SHELL_STRANDS}
## The detail kind of each floor garment when its index entry names none (a garment not listed is cloth).
const GARMENT_DETAIL := {"braies": "weave", "tunic": "weave", "jerkin": "leather", "belt": "leather",
	"bracers": "leather", "boots": "leather", "furs": "fur"}
## A garment whose index entry has no dye slot ("none": the furs) keeps this colour.
const NATURAL_DYE := Color(0.36, 0.30, 0.24)
## The detail map's strength per kind.
const DETAIL_STRENGTH := {"weave": 0.28, "leather": 0.5, "fur": 0.45, "metal": 0.35, "mail": 0.85, "scale": 0.8,
	"bone": 0.18, "stone": 0.55}
## The W33 look lane: the detail map's tiles over the body's UVs (the shader's 96 otherwise) and its normal's
## strength (0.4 otherwise) per kind: the mail's rings and the scales larger and deeper, so they read at the game's
## camera (at 96 a ring was about a centimetre on the giant and the hauberk drew as flat grey plate).
const DETAIL_SCALE := {"mail": 56.0, "scale": 40.0, "stone": 30.0}
const NORMAL_STRENGTH := {"mail": 1.1, "scale": 1.0, "stone": 0.9}
## The cloth shader's soft edge light per detail kind (P51: wool and fur catch the light at their edges).
## Gate A: weave and leather take no rim. The renderer's rim light does not look at N.L, so a sliver of a fold seen
## edge-on against the sun (the braies' crotch in the world's light) was lit as if it faced it: small bright patches.
## Fur keeps its fuzz (its folds are soft and it reads right in the world's light).
const CLOTH_RIM := {"weave": 0.0, "leather": 0.0, "fur": 0.45, "metal": 0.0, "mail": 0.0, "scale": 0.0, "bone": 0.0,
	"stone": 0.0}
## The cloth shader's `kind` per detail map (P54): cloth, leather and fur 0; plate, mail and scale 1 (the metal
## response); bone 2 (its own pale colour, a soft sheen: bone spaulders, the bone accessories); the second look lane:
## leather 4 (a warm waxed hide in stitched panels: the jerkin and the cuirass read as near-black slabs).
## B1: stone 5 (the Quarry set: cut stone, its iron bands where UV2.y is 1; the hammered map read as chisel marks).
const DETAIL_KIND := {"metal": 1, "mail": 1, "scale": 1, "bone": 2, "fur": 3, "leather": 4, "stone": 5}
## A head garment's index entry "hides_hair" (P54, plan M11 §2.6): "all" hides every hair style; "top" draws a style
## cut to the share of its length its "hair_cut" gives (0: not drawn).
const HIDES_ALL := "all"

## The uniforms GiantLook sets, per shader kind (validate() checks them against the shaders), and the two
## every giant shader declares for RigPaint.
const UNIFORMS := {
	"skin": ["albedo_tex", "normal_tex", "orm_tex", "mask_tex", "design_tex", "skin_tone", "bake_tone", "hair_color",
		"beard_color", "stubble", "scalp_tint", "beard_tint", "brows", "region_tattoo", "region_paint", "region_mark",
		"tattoo_ink", "paint_color", "mark_color", "mark_glow", "scar_layer", "scar_on", "scar_layer_b", "scar_on_b",
		"scar_regions", "scar_regions_b",
		"hidden_regions", "hide_shrink", "build", "build_max_m"],
	"hair": ["hair_atlas", "hair_color", "tip_color", "grey", "length", "tip_thin", "back_fade", "volume_normal"],
	"eye": ["iris_color", "iris_glow", "look"],
	"cloth": ["detail_tex", "dye_color", "detail_strength", "fade", "kind", "rim", "build", "build_max_m", "bead_mask",
		"push_m", "pushed", "push_knots", "push_y_norm", "detail_scale", "normal_strength", "push_tangent"],
	"shell": ["strand_tex", "mask_tex", "mask_channel", "shell_count", "shell_height_m", "comb", "hair_color", "tip_color",
		"grey", "length"],
}
## The shell styles (P51; the index entry's "shell": {mask, height_m}): the layers on the desktop and on the Web
## (probe 6: twelve read as a dense crop; six on the Web, where they cost a third more of a frame), the skin
## mask's channel each reads (the skin's masks map: R the beard, G the scalp) and the tips' lean in the mesh's
## own space (+Z his front: the crop combed back and down, the short beard down).
const SHELL_LAYERS := 12
const SHELL_LAYERS_WEB := 6
const SHELL_MASKS := {"scalp": Vector4(0, 1, 0, 0), "beard": Vector4(1, 0, 0, 0)}
const SHELL_COMB := {"scalp": Vector3(0.0, -0.3, -0.45), "beard": Vector3(0.0, -0.8, 0.15)}
const SHELL_STRANDS := "res://assets/giant/shell_strands.png"
## The share of the beard's tint the skin keeps under a shell beard.
const SHELL_SKIN_TINT := 0.7
## The skin shader's tone_scaled defaults (tone_shoulder, tone_chroma, tone_resat, TONE_RESAT_MAX), mirrored for
## drawn_tone.
const TONE_SHOULDER := 0.4
const TONE_CHROMA := 1.0
const TONE_RESAT := 1.0
const TONE_RESAT_MAX := 1.25
const META_SHELL_STACK := "giant_shell_stack"
## The default tone's lit chest in the creator's light (measured by tests/gate/test_skin_tone_render.gd): drawn_tone
## scales it by a tone over the bake tone. P51 graded the albedo to the approved studio render's (198, 170, 157)
## (199, 170, 157 drawn); Gate A eased the grade so the skin holds its colour in the world's light, and the chest
## now draws (220, 160, 131), 26/255 off the studio render (docs/systems/P51.md, "Gate A").
const DRAWN_DEFAULT := Color(0.862745, 0.627451, 0.513725)   # (220, 160, 131)
const PAINT_UNIFORMS := ["tint", "flash"]
## P53 pre-declares Part B's categories: accessories (P54) and beads (P56) draw with the cloth shader (metal and
## bone take its metal response or not by their entry's detail).
const KIND_OF_CATEGORY := {"body": "skin", "eyes": "eye", "hair": "hair", "beard": "hair", "garment": "cloth",
	"accessory": "cloth", "bead": "cloth", "armour": "cloth"}   # B1: the functional armour's modelled pieces

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
const META_SWAY := "giant_look_sway"
## On a root: a face slider was set on one of its meshes (P53: a look with no face then skips the meshes).
const META_FACE := "giant_look_face"
## On a root: apply()'s walk over its meshes (P57; _plan()).
const META_PLAN := "giant_look_plan"
const R_ID := 0
const R_CATEGORY := 1
const R_NODE := 2
const R_STYLES := 3
const R_ENTRY := 4
const R_SHADER := 5
const R_OWN_COLOR := 6
const R_DYE_SLOT := 7
## On a material: the look uniforms (name -> value) apply() last set there (P57: an unchanged material is skipped).
const META_LAST := "giant_look_last"
## The cloth shader's knots of the layering's push (its uniform arrays' length).
const PUSH_KNOTS := 6
const ZERO_PUSH: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
## The hair's sway (P46; the hair shader's head_motion): the tips lag the head's motion by SWAY_LAG_S seconds
## of it, eased at SWAY_EASE a second, at most SWAY_MAX_M at the tips (stage-1 metres, the mesh's own space).
const SWAY_LAG_S := 0.035
const SWAY_EASE := 10.0
const SWAY_MAX_M := 0.09
const SWAY_BONE := "head"

## The texture tier the command line forces (--giant-tier=web | hi; "" = none). Tests set it directly.
static var forced_tier := _cli_tier()
static var _tex_cache := {}
static var _declared_cache := {}
static var _sampler_cache := {}
## The shell stacks built so far: "<source mesh id>:<layers>" -> WeakRef of the stacked ArrayMesh.
static var _shell_stacks := {}


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


## The shader kind of an index mesh entry: "shell" for a shell style (P51), else its category's.
static func mesh_kind(entry: Dictionary) -> String:
	if typeof(entry.get("shell")) == TYPE_DICTIONARY:
		return "shell"
	return shader_kind(str(entry.get("category", "")))


static func shader_for(kind: String) -> Shader:
	match kind:
		"shell":
			return SHELL_SHADER
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
	# P57: cached by mesh id, so a hit costs one lookup (apply() asks for every mesh of the index on every look)
	var cache := _node_cache(root)
	var hit: Variant = cache.get(mesh_id)
	if hit != null and is_instance_valid(hit) and root.is_ancestor_of(hit):
		return hit
	var entry: Variant = _meshes(index).get(mesh_id)
	var node_name := str((entry as Dictionary).get("node", mesh_id)) if typeof(entry) == TYPE_DICTIONARY else mesh_id
	var found := root.find_child(node_name, true, false) as MeshInstance3D
	if found != null:
		cache[mesh_id] = found
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
	for p: Dictionary in paints(look):
		place.call("paint", str(p.get("design", "")))
	if typeof(look.get("mark")) == TYPE_DICTIONARY and not (look.mark as Dictionary).is_empty():
		place.call("mark", str(look.mark.get("design", "")))
	return out


## A look's war paints (P53: an Array of at most two {"design", "color"}; M10's one dictionary read as one).
static func paints(look: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var p: Variant = look.get("paint")
	if typeof(p) == TYPE_DICTIONARY and not (p as Dictionary).is_empty():
		out.append(p)
	elif typeof(p) == TYPE_ARRAY:
		for e: Variant in p:
			if typeof(e) == TYPE_DICTIONARY and not (e as Dictionary).is_empty():
				out.append(e)
	return out


## The garment meshes a look shows: mesh id -> {"dye": Color, "kind": String ("" for an M10-shaped entry)}. An
## entry names an index garment (its meshes) or a garment mesh; an M10-shaped entry (an index garment id) takes
## dye_primary, dye_secondary or the natural colour by each mesh's index "dye".
static func garment_meshes(index: Dictionary, look: Dictionary) -> Dictionary:
	var out := {}
	var garments := _garments(index)
	var meshes := _meshes(index)
	var g_list: Variant = look.get("garments", [])
	for g: Variant in (g_list if typeof(g_list) == TYPE_ARRAY else []):
		var id := Appearance.garment_id(g)
		var ids: Array = garments.get(id, []) if typeof(garments.get(id)) == TYPE_ARRAY else ([id] if meshes.has(id) else [])
		for m: Variant in ids:
			var entry: Dictionary = meshes.get(str(m), {}) if typeof(meshes.get(str(m))) == TYPE_DICTIONARY else {}
			if typeof(g) == TYPE_DICTIONARY:
				var dye: Variant = (g as Dictionary).get("dye", LEGACY_PRIMARY)
				out[str(m)] = {"dye": dye if dye is Color else (Color.html(str(dye)) if Color.html_is_valid(str(dye)) else NATURAL_DYE),
					"kind": str((g as Dictionary).get("kind", ""))}
			else:
				out[str(m)] = {"dye": _legacy_dye(look, str(entry.get("dye", "primary"))), "kind": ""}
	return out


## The W33 look lane: how far each worn garment stands off the skin. A garment's mesh sits where it would over nothing,
## and each vertex carries its push to its place over the loosest garment of every inner slot (the cloth shader's
## `push_m` times the vertex colour's alpha); the index's `layering` gives, per outer garment and worn inner garment,
## the least share of that push which keeps it clear of the inner one at each share of the inner one's own push
## (`samples` steps of 0-1, read at the step at or above the inner garment's greatest share), one share for each of the
## table's `knots_m` (rest heights from the thighs to the shoulders: the cloth shader eases between them), so a garment
## worn under the hips' part of a coat pushes that part and not its chest. Returns {garment id: PackedFloat32Array of
## PUSH_KNOTS shares 0-1} for `garment_ids` (the worn garments, index ids); a table with fewer knots repeats its last;
## an index without the table gives {} (every garment at its mesh: an index from before).
static func garment_pushes(index: Dictionary, garment_ids: Array, prepared: Dictionary = {}) -> Dictionary:
	var out := {}
	var t := prepared if not prepared.is_empty() else _layering_table(index)
	if t.is_empty():
		return out
	var push: Dictionary = t.push
	var rank: Dictionary = t.rank
	var by_rank: Array = t.by_rank
	var last := int(t.last)
	var ranks: Array[int] = []
	for g: Variant in garment_ids:
		var r: Variant = rank.get(str(g))
		if r != null and not ranks.has(r):
			ranks.append(r)
	ranks.sort()
	var worn: Array[String] = []
	for r: int in ranks:
		worn.append(by_rank[r])
	var knots := int(t.knots)
	var most := {}   # each worn garment's greatest share (its row's sample is read at or above it)
	for i in worn.size():
		var id: String = worn[i]
		var row: Variant = push.get(id)
		var share := PackedFloat32Array()
		share.resize(PUSH_KNOTS)
		share.fill(0.0)
		var top := 0.0
		if typeof(row) == TYPE_DICTIONARY:
			for j in i:
				var h: String = worn[j]
				var r: Variant = (row as Dictionary).get(h)
				if typeof(r) == TYPE_ARRAY and (r as Array).size() >= (last + 1) * knots:
					var k := clampi(ceili(float(most[h]) * last - 0.000001), 0, last) * knots
					for c in PUSH_KNOTS:
						var v := float(r[k + mini(c, knots - 1)])
						if v > share[c]:
							share[c] = v
							top = maxf(top, v)
		out[id] = share
		most[id] = top
	return out


## The cloth shader's push_m of every garment mesh in `shown` (garment_meshes: the look's shown garment meshes): the
## shares garment_pushes gives its garment times the mesh's index push_m, {mesh id: PackedFloat32Array of metres at the
## knots} (a mesh that stays at its place is left out). The index's table is
## prepared once per index (its manifest_sha256; a synthetic index without one every time).
static func garment_push_m(index: Dictionary, shown: Dictionary) -> Dictionary:
	var out := {}
	if shown.is_empty():
		return out
	var t := _layering_table(index)
	if t.is_empty():
		return out
	var g_of: Dictionary = t.g_of
	var worn: Array = []
	for m: Variant in shown:
		var g: Variant = g_of.get(m)
		if g != null:
			worn.append(g)
	var shares := garment_pushes(index, worn, t)
	var push_m: Dictionary = t.push_m
	for m: Variant in shown:
		if push_m.has(m):
			var sh: PackedFloat32Array = shares.get(g_of[m], PackedFloat32Array())
			if sh.is_empty():
				continue
			var pm := PackedFloat32Array(sh)
			var scale := float(push_m[m])
			var any := false
			for c in pm.size():
				pm[c] *= scale
				any = any or pm[c] > 0.0
			if any:
				out[m] = pm
	return out


static var _layering_tables := {}


static func _layering_table(index: Dictionary) -> Dictionary:
	var key := str(index.get("manifest_sha256", ""))
	if key != "" and _layering_tables.has(key):
		return _layering_tables[key]
	var lay: Variant = index.get("layering")
	if typeof(lay) != TYPE_DICTIONARY or typeof((lay as Dictionary).get("order")) != TYPE_ARRAY:
		return {}
	var g_of := {}
	var push_m := {}
	var garments := _garments(index)
	var meshes := _meshes(index)
	for g: Variant in garments:
		for m: Variant in (garments[g] if typeof(garments[g]) == TYPE_ARRAY else []):
			g_of[str(m)] = str(g)
			var e: Variant = meshes.get(str(m))
			if typeof(e) == TYPE_DICTIONARY and SchemaUtil.is_number((e as Dictionary).get("push_m")):
				push_m[str(m)] = float((e as Dictionary).push_m)
	var rank := {}
	for i in ((lay as Dictionary).order as Array).size():
		var id := str((lay as Dictionary).order[i])
		rank[id] = i
		if not garments.has(id) and typeof(meshes.get(id)) == TYPE_DICTIONARY:
			# a ring accessory: its own mesh in the table (after every garment)
			g_of[id] = id
			if SchemaUtil.is_number((meshes[id] as Dictionary).get("push_m")):
				push_m[id] = float((meshes[id] as Dictionary).push_m)
	for m: String in g_of:
		if not rank.has(g_of[m]):
			rank[g_of[m]] = rank.size()
	var by_rank: Array = []
	by_rank.resize(rank.size())
	for g: String in rank:
		by_rank[int(rank[g])] = g
	var t := {"g_of": g_of, "rank": rank, "by_rank": by_rank, "push_m": push_m,
		"push": (lay as Dictionary).get("push", {}) if typeof((lay as Dictionary).get("push")) == TYPE_DICTIONARY else {},
		"last": maxi(1, int((lay as Dictionary).get("samples", 5)) - 1),
		"knots": clampi(((lay as Dictionary).get("knots_m", [0]) as Array).size(), 1, PUSH_KNOTS)}
	if key != "":
		_layering_tables[key] = t
	return t


## `shown` with the ids of `more` as keys too (a copy).
static func _with(shown: Dictionary, more: Variant) -> Dictionary:
	var out := shown.duplicate()
	for m: Variant in (more if typeof(more) == TYPE_ARRAY else []):
		out[str(m)] = {}
	return out


## The hair styles a look's head garments cut (P54, plan M11 §2.6): hair mesh id -> the share of its length drawn
## (0: not drawn; a style not named is drawn whole). `garment_ids` are the garment meshes shown.
static func hair_cut(index: Dictionary, garment_ids: Array) -> Dictionary:
	var out := {}
	var meshes := _meshes(index)
	for g: Variant in garment_ids:
		var e: Variant = meshes.get(str(g))
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var hides := str((e as Dictionary).get("hides_hair", ""))
		if hides == HIDES_ALL:
			for id in meshes_of(index, "hair"):
				out[id] = 0.0
		elif hides == "top" and typeof((e as Dictionary).get("hair_cut")) == TYPE_DICTIONARY:
			var c: Dictionary = (e as Dictionary).hair_cut
			for id: Variant in c:
				out[str(id)] = minf(float(out.get(str(id), 1.0)), float(c[id]))
	return out


## An M10-shaped look's dye for a mesh's index "dye" slot.
static func _legacy_dye(look: Dictionary, slot: String) -> Color:
	match slot:
		"primary":
			return look.get("dye_primary", LEGACY_PRIMARY)
		"secondary":
			return look.get("dye_secondary", LEGACY_SECONDARY)
	return NATURAL_DYE


static func _zeros() -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(REGIONS)
	a.fill(0)
	return a


## The scar uniforms of `look`: {"layer", "on", "layer_b", "on_b"}: the layer of its first known scar and a
## Vector4 with 1 in the channel of every scar on that layer, and the same for the scars of a second layer
## (P46: four scars a layer, the fifth and sixth on the second). With no scar the layers are the index's scar
## layers and nothing is on. Scars on a third layer are left out (validate() reports them).
static func scar_uniforms(index: Dictionary, scars: Variant) -> Dictionary:
	var designs := _designs(index)
	var layers: Array[int] = []
	var on: Array[Vector4] = [Vector4.ZERO, Vector4.ZERO]
	# P56: a scar channel may hold scars of several regions; it is on only in the worn scars' regions
	var regions: Array[Vector4i] = [Vector4i.ZERO, Vector4i.ZERO]
	for s: Variant in (scars if typeof(scars) == TYPE_ARRAY else []):
		var d: Variant = designs.get(str(s))
		if typeof(d) != TYPE_DICTIONARY:
			continue
		var l := int((d as Dictionary).get("layer", 0))
		if not layers.has(l) and layers.size() < 2:
			layers.append(l)
		var slot := layers.find(l)
		if slot >= 0:
			var ch := clampi(int((d as Dictionary).get("channel", 0)), 0, 3)
			on[slot][ch] = 1.0
			for r: Variant in (d as Dictionary).get("regions", []):
				if SchemaUtil.is_number(r) and int(r) >= 0 and int(r) < REGIONS:
					regions[slot][ch] |= 1 << int(r)
	var known := _scar_layers(designs)
	for l in known:
		if layers.size() < 2 and not layers.has(l):
			layers.append(l)
	while layers.size() < 2:
		layers.append(layers[0] if not layers.is_empty() else 0)
	return {"layer": maxi(layers[0], 0), "on": on[0], "layer_b": maxi(layers[1], 0), "on_b": on[1],
		"regions": regions[0], "regions_b": regions[1]}


static var _scar_layers_of: Dictionary = {}
static var _scar_layers_size := -1
static var _scar_layers_known: Array[int] = []


## The index's scar layers, sorted (P57: worked out once per designs Dictionary).
static func _scar_layers(designs: Dictionary) -> Array[int]:
	if is_same(designs, _scar_layers_of) and designs.size() == _scar_layers_size:
		return _scar_layers_known
	var known: Array[int] = []
	for id: Variant in designs:
		if typeof(designs[id]) == TYPE_DICTIONARY and str((designs[id] as Dictionary).get("kind", "")) == "scar":
			var l := int((designs[id] as Dictionary).get("layer", 0))
			if not known.has(l):
				known.append(l)
	known.sort()
	_scar_layers_of = designs
	_scar_layers_size = designs.size()
	_scar_layers_known = known
	return known


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
		var kind := mesh_kind(entry)
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
				var lut := texture_path(index, "", "", "skin_lut")
				_set_texture(mat, "skin_lut", lut if lut != "" else SKIN_LUT)   # an index from before P51 names none
				set_param(mat, "bake_tone", BAKE_TONE)
				set_param(mat, "hide_shrink", HIDE_SHRINK_M)
				set_param(mat, "brows", 1.0)
			"hair":
				_set_texture(mat, "hair_atlas", texture_path(index, str(entry.get("atlas", "")), "", "hair_atlas"))
				# the M10 gate (LC-6): a beard's tips thin strand by strand. P51: a beard no longer fades out seen
				# from behind (its under-jaw cards are closed); the hair shades as a volume
				var is_beard := str(entry.get("category", "")) == "beard"
				set_param(mat, "tip_thin", (BEARD_TIP_THIN if str(id) in LOCK_BEARDS else BEARD_SHORT_TIP_THIN) if is_beard else 0.0)
				set_param(mat, "back_fade", 0.0)
				set_param(mat, "volume_normal", VOLUME_NORMAL)
			"eye":
				set_param(mat, "look", Vector2.ZERO)   # P51: ahead; SkinnedRig and the creator turn it later
			"shell":
				var sh: Dictionary = entry.shell
				var channel := str(sh.get("mask", "scalp"))
				var strands := texture_path(index, "", "", "shell_strands")
				_set_texture(mat, "strand_tex", strands if strands != "" else SHELL_STRANDS)
				_set_texture(mat, "mask_tex", str(maps.mask_tex))
				set_param(mat, "mask_channel", SHELL_MASKS.get(channel, SHELL_MASKS.scalp))
				set_param(mat, "comb", SHELL_COMB.get(channel, SHELL_COMB.scalp))
				set_param(mat, "shell_count", shell_layers())
				set_param(mat, "shell_height_m", float(sh.get("height_m", 0.018)))
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			"cloth":
				var detail := _detail_kind(str(id), entry, index)
				var ref := str(entry.get("detail", ""))
				_set_texture(mat, "detail_tex", texture_path(index, ref, "detail_", "detail_" + detail))
				set_param(mat, "detail_strength", float(DETAIL_STRENGTH.get(detail, 0.3)))
				set_param(mat, "kind", int(DETAIL_KIND.get(detail, 0)))
				set_param(mat, "band_mask", bool(entry.get("band", false)))   # B2: a modelled piece's iron
				set_param(mat, "rim", float(CLOTH_RIM.get(detail, 0.2)))
				if str(entry.get("category", "")) in ["garment", "accessory", "armour"]:
					set_param(mat, "push_m", ZERO_PUSH)   # W33: apply sets it as the worn garments need
					set_param(mat, "pushed", false)
					var lay: Variant = index.get("layering")
					if typeof(lay) == TYPE_DICTIONARY and ((lay as Dictionary).get("knots_m", []) as Array).size() == PUSH_KNOTS:
						set_param(mat, "push_knots", PackedFloat32Array((lay as Dictionary).knots_m))
						set_param(mat, "push_y_norm", float((lay as Dictionary).get("y_norm_m", 4.0)))
				if bool(entry.get("push_tangent", false)):
					set_param(mat, "push_tangent", true)   # W33: a ring's push rides in its tangents
				if DETAIL_SCALE.has(detail):
					set_param(mat, "detail_scale", float(DETAIL_SCALE[detail]))
					set_param(mat, "normal_strength", float(NORMAL_STRENGTH[detail]))
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


## The hair's and the beard's sway for this frame (P46): call it once a drawn frame with the model and its
## skeleton, after the pose is final (SkinnedRig, in skeleton_updated). It reads the head bone's place, eases
## its motion and writes the hair shader's head_motion on the hair and beard materials. Presentation only.
static func sway(root: Node3D, index: Dictionary, skeleton: Skeleton3D) -> Vector3:
	if root == null or skeleton == null:
		return Vector3.ZERO
	if not root.is_inside_tree() or not skeleton.is_inside_tree():
		# a pose can update while the giant is out of the tree (a level reset re-parents the player): there is
		# no world transform to read, and the next frame in the tree starts the sway afresh
		root.remove_meta(META_SWAY)
		return Vector3.ZERO
	var bone := skeleton.find_bone(SWAY_BONE)
	if bone < 0:
		return Vector3.ZERO
	var now := Time.get_ticks_usec()
	var pos: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin
	var st: Dictionary = root.get_meta(META_SWAY, {})
	var motion := Vector3.ZERO
	if st.has("pos"):
		var dt := clampf(float(now - int(st.t)) / 1.0e6, 1.0 / 240.0, 0.1)
		motion = sway_step(st.motion, (pos - (st.pos as Vector3)) / dt, dt)
	root.set_meta(META_SWAY, {"pos": pos, "t": now, "motion": motion})
	var mats := _own_materials(root)
	for category: String in ["hair", "beard"]:
		for id in meshes_of(index, category):
			var mi := mesh_node(root, index, id)
			var mat: Variant = mats.get(id)
			if mi == null or not mi.visible or not mi.is_inside_tree() or not mat is ShaderMaterial:
				continue
			# into the mesh's own space: its scale (the growth stage) divides out, so the sway is in stage-1 metres
			(mat as ShaderMaterial).set_shader_parameter("head_motion",
				(mi.global_transform.basis.inverse() * motion).limit_length(SWAY_MAX_M))
	return motion


## One eased step of the sway (pure): the motion kept from the last frame towards `head_speed` (m/s, world).
static func sway_step(previous: Vector3, head_speed: Vector3, dt: float) -> Vector3:
	return previous.lerp(head_speed * SWAY_LAG_S, 1.0 - exp(-SWAY_EASE * dt))


## Sets a uniform and remembers its name on the material (validate() checks every name set).
static func set_param(mat: ShaderMaterial, uniform: String, value: Variant) -> void:
	if mat == null:
		return
	mat.set_shader_parameter(uniform, value)
	if mat.has_meta(META_LAST):
		mat.remove_meta(META_LAST)   # P57: apply() sets this material's look again next time
	# P57: the names' Dictionary is stored once and then filled in place (a set_meta on every uniform was most of
	# a look's cost in the creator's every pick)
	if not mat.has_meta(META_NAMES):
		mat.set_meta(META_NAMES, {uniform: true})
		return
	var names: Dictionary = mat.get_meta(META_NAMES)
	if not names.has(uniform):
		names[uniform] = true


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
	var shown := garment_meshes(index, l)
	var pushes := garment_push_m(index, shown if l.accessories.is_empty() else _with(shown, l.accessories))   # W33
	var extras := {}   # P53: the accessories and the beads shown (Part B's meshes; none before P54 and P56)
	for m: Variant in l.accessories:
		extras[str(m)] = true
	for key: String in ["hair_beads", "beard_beads"]:
		if str(l[key]) != "":
			extras[str(l[key])] = true
	var meshes := _meshes(index)
	var cut := hair_cut(index, shown.keys())
	# P51 (plan M11 §2.2): a model that loads its parts on demand (GiantModel) loads what the look shows and lets
	# go of the rest; a synthetic root just shows and hides its nodes
	var parts := root.has_method("ensure_part") and root.has_method("release_unused")
	var shown_ids: Array = []
	var rows := _plan(root, index)
	for r: Array in rows:
		var mi: MeshInstance3D = r[R_NODE]
		var id: String = r[R_ID]
		match r[R_CATEGORY]:
			"hair":
				mi.visible = id == str(l.hair_mesh) and float(cut.get(id, 1.0)) > 0.0
			"beard":
				mi.visible = id == str(l.beard_mesh)
			"garment":
				mi.visible = shown.has(id)
			"accessory", "armour":
				mi.visible = extras.has(id)   # B1: a modelled armour piece as an accessory (Armour.look_of)
			"bead":
				# P56: a bead set with style codes shows only on the shown styles that have anchors
				mi.visible = extras.has(id) and (not r[R_STYLES] or bead_mask(r[R_ENTRY], id, l, cut) != 0)
		if mi.visible:
			shown_ids.append(id)
			if parts:
				root.call("ensure_part", id)
	if parts:
		root.call("release_unused", shown_ids)
	_apply_face(root, index, shown_ids, l.face)
	var build: Vector2 = l.build if l.build is Vector2 else Vector2.ZERO
	var build_max := float(index.get("build_max_m", 0.0)) if SchemaUtil.is_number(index.get("build_max_m")) else 0.0
	if root.has_method("apply_build"):
		root.call("apply_build", build, build_max)
	var mats := _own_materials(root)
	if mats.is_empty():
		return
	var stacked := false
	for id: String in shown_ids:
		var entry: Dictionary = meshes.get(id, {}) if typeof(meshes.get(id)) == TYPE_DICTIONARY else {}
		if mesh_kind(entry) == "shell":
			var mi := mesh_node(root, index, id)
			var before: Mesh = mi.mesh if mi != null else null
			_stack_shells(mi)
			stacked = stacked or (mi != null and mi.mesh != before)
	if stacked:
		_apply_face(root, index, shown_ids, l.face, true)   # P56: a fresh stack starts with its face keys at 0
	var hidden := hidden_regions_mask(index, l.garments)
	var codes := region_codes(index, l)
	var scars := scar_uniforms(index, l.scars)
	var painted := paints(l)
	var paint: Dictionary = painted[0] if not painted.is_empty() else {}
	var mark: Dictionary = l.mark if typeof(l.mark) == TYPE_DICTIONARY else {}
	var ink: Color = (l.tattoos[0] as Dictionary).get("ink", Color(0.1, 0.18, 0.4)) if not (l.tattoos as Array).is_empty() \
		else Color(0.1, 0.18, 0.4)
	# P57: each kind's uniforms are worked out once per look, and a material whose last look set the same values is
	# skipped (the creator applies the whole look on every pick; 73 materials with the catalogue II). set_param
	# (and so set_garment_fade) forgets a material's last values, so only a raw set_shader_parameter outside
	# GiantLook could be missed; GiantLook.forget_applied(root) makes the next look set everything again.
	# Gate B: the build and a garment's push are part of each material's own compared values (a root-wide "last
	# build" left a piece hidden while the build or the layering changed with its old values when shown again).
	var shell_beard := _shell_beard(meshes, l)
	var skin := {"skin_tone": l.skin_tone, "hair_color": l.hair_color, "beard_color": l.beard_color,
		"scalp_tint": float(l.scalp_tint), "stubble": float(l.stubble) * (SHELL_SKIN_TINT if shell_beard else 1.0),
		# P51: under a shell beard the skin keeps only a shade of the beard's colour (the shells are the beard; the
		# skin's hard-edged beard area showed through as a line on the cheeks)
		"beard_tint": (float(l.beard_tint) * (SHELL_SKIN_TINT if shell_beard else 1.0)) if str(l.beard_mesh) != "" else 0.0,
		"region_tattoo": codes.tattoo, "region_paint": codes.paint, "region_mark": codes.mark, "tattoo_ink": ink,
		"paint_color": paint.get("color", Color(0.86, 0.84, 0.78)), "mark_color": mark.get("color", Color(0.44, 0.49, 0.55)),
		"mark_glow": float(mark.get("glow", 0.0)), "scar_layer": int(scars.layer), "scar_on": scars.on,
		"scar_layer_b": int(scars.layer_b), "scar_on_b": scars.on_b, "scar_regions": scars.regions,
		"scar_regions_b": scars.regions_b, "hidden_regions": hidden, "build": build, "build_max_m": build_max}
	var hair := {"hair_color": l.hair_color, "tip_color": l.hair_tip, "grey": float(l.hair_grey),
		"length": clampf(float(l.hair_length), 0.0, 1.0)}
	var beard := {"hair_color": l.beard_color, "tip_color": l.beard_tip, "grey": float(l.beard_grey),
		"length": clampf(float(l.beard_length), 0.0, 1.0)}
	var eye := {"iris_color": l.eye_color, "iris_glow": float(l.eye_glow)}
	for r: Array in rows:
		var mat: ShaderMaterial = mats.get(r[R_ID])
		if mat == null:
			continue
		if not (r[R_NODE] as MeshInstance3D).visible and r[R_SHADER] != "skin" and mat.has_meta(META_LAST):
			continue   # P57: a hidden piece keeps the values of the last look that showed it until it is shown again
		var id: String = r[R_ID]
		var category: String = r[R_CATEGORY]
		match r[R_SHADER]:
			"skin":
				_put(mat, skin)
			"hair":
				if category == "beard":
					_put(mat, beard)
				elif cut.has(id):
					var h := hair.duplicate()
					h.length = clampf(minf(float(l.hair_length), float(cut[id])), 0.0, 1.0)   # P54: under a helm
					_put(mat, h)
				else:
					_put(mat, hair)
			"eye":
				_put(mat, eye)
			"cloth":
				var g: Dictionary = shown.get(id, {})
				var dye: Variant = g.get("dye")
				if dye == null:   # P54: an accessory in its own colour
					dye = r[R_OWN_COLOR] if r[R_OWN_COLOR] != null else _legacy_dye(l, r[R_DYE_SLOT])
				var c := {"dye_color": dye, "fade": 0.0, "build": build, "build_max_m": build_max}
				if category == "bead" and r[R_STYLES]:
					c["bead_mask"] = bead_mask(r[R_ENTRY], id, l, cut)
				if str(g.get("kind", "")) == "metal":
					c["kind"] = 1   # a metal garment's response whatever its detail map
				if category == "garment" or category == "accessory" or category == "armour":
					# W33: `pushed` skips the shader's knots for a garment that stands at its mesh
					c["push_m"] = pushes.get(id, ZERO_PUSH)
					c["pushed"] = pushes.has(id)
				_put(mat, c)


## P57: the root's meshes as apply() walks them, worked out once per root and index: one Array a mesh of the index
## that has a node, [id, category, node, has style codes, entry, shader kind, own colour or null, dye slot]. Made
## again when the index or a node changes (a copy of the root, a node freed).
static func _plan(root: Node, index: Dictionary) -> Array:
	var meshes := _meshes(index)
	if root.has_meta(META_PLAN):
		var plan: Dictionary = root.get_meta(META_PLAN)
		if int(plan.owner) == root.get_instance_id() and is_same(plan.meshes, meshes) and int(plan.size) == meshes.size():
			var valid := true
			for r: Array in plan.rows:
				if not is_instance_valid(r[R_NODE]):
					valid = false
					break
			if valid:
				return plan.rows
	var rows := []
	for id: Variant in meshes:
		var entry: Dictionary = meshes[id] if typeof(meshes[id]) == TYPE_DICTIONARY else {}
		var mi := mesh_node(root, index, str(id))
		if mi == null:
			continue
		var category := str(entry.get("category", ""))
		var own := str(entry.get("color", ""))
		rows.append([str(id), category, mi, entry.has("styles"), entry, shader_kind(category),
			Color.html(own) if Color.html_is_valid(own) else null, str(entry.get("dye", "primary"))])
	root.set_meta(META_PLAN, {"owner": root.get_instance_id(), "meshes": meshes, "size": meshes.size(), "rows": rows})
	return rows


## P57: `values` (uniform -> value) on `mat`, unless the last look put exactly these values there; the names are
## remembered for validate() as set_param does.
static func _put(mat: ShaderMaterial, values: Dictionary) -> void:
	var last: Variant = mat.get_meta(META_LAST) if mat.has_meta(META_LAST) else null
	if last is Dictionary and last == values:
		return
	if not mat.has_meta(META_NAMES):
		mat.set_meta(META_NAMES, {})
	var names: Dictionary = mat.get_meta(META_NAMES)
	for u: String in values:
		mat.set_shader_parameter(u, values[u])
		names[u] = true
	mat.set_meta(META_LAST, values)


## P57: the next look sets every uniform of the root's materials again (after a uniform was set outside GiantLook).
static func forget_applied(root: Node) -> void:
	for mat: Variant in _own_materials(root).values():
		(mat as ShaderMaterial).remove_meta(META_LAST)


## The bead set `id`'s mask of style codes shown with look `l` (P56; plan M11 §2.5: beads only on styles whose index
## entry has bead anchors): bit `code` for the hair style when the look's hair beads are this set and the style is
## drawn whole (a helm's cut leaves its braids' beads off), and for the beard likewise. `entry.styles` maps a style
## mesh to its code (the bead mesh's UV2.x); the cloth shader drops the beads of every other code.
static func bead_mask(entry: Dictionary, id: String, l: Dictionary, cut: Dictionary = {}) -> int:
	var styles: Dictionary = entry.get("styles", {}) if typeof(entry.get("styles")) == TYPE_DICTIONARY else {}
	var mask := 0
	if str(l.get("hair_beads", "")) == id and styles.has(str(l.get("hair_mesh", ""))) \
			and float(cut.get(str(l.hair_mesh), 1.0)) >= 1.0:
		mask |= 1 << int(styles[str(l.hair_mesh)])
	if str(l.get("beard_beads", "")) == id and styles.has(str(l.get("beard_mesh", ""))):
		mask |= 1 << int(styles[str(l.beard_mesh)])
	return mask


## The creator's "Hidden by your clothing" fade (0-1) on the garments' materials (none before
## build_materials).
static func set_garment_fade(root: Node, index: Dictionary, fade: float) -> void:
	var mats := _own_materials(root)
	var meshes := _meshes(index)
	for id: Variant in mats:
		if typeof(meshes.get(id)) == TYPE_DICTIONARY and str((meshes[id] as Dictionary).get("category", "")) == "garment":
			set_param(mats[id], "fade", clampf(fade, 0.0, 1.0))


## The shader warm-ups (P51; GiantPreview.WarmUp): shows every shell style's node beside the look's own, so the
## shell shader's variants compile behind the title or the loading screen and not in the creator's first frame.
## Returns the shell styles shown. Only for a hidden warm-up model: the next apply() hides them again.
static func warm_shells(root: Node3D, index: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var meshes := _meshes(index)
	for id: Variant in meshes:
		if typeof(meshes[id]) != TYPE_DICTIONARY or mesh_kind(meshes[id]) != "shell":
			continue
		var mi := mesh_node(root, index, str(id))
		if mi == null:
			continue
		mi.visible = true
		if root.has_method("ensure_part"):
			root.call("ensure_part", str(id))
		if not _own_materials(root).is_empty():
			_stack_shells(mi)
		out.append(str(id))
	return out


## True when the look's beard is a shell style.
static func _shell_beard(meshes: Dictionary, l: Dictionary) -> bool:
	var e: Variant = meshes.get(str(l.beard_mesh))
	return typeof(e) == TYPE_DICTIONARY and mesh_kind(e) == "shell"


## The shell layers of this build (P51): SHELL_LAYERS, SHELL_LAYERS_WEB on the Web.
static func shell_layers() -> int:
	return SHELL_LAYERS_WEB if OS.has_feature("web") else SHELL_LAYERS


## Stacks the shells of mesh `id` when it is a shell style shown with its skin loaded (a caller that shows a
## style's node itself, not through apply(): the parts probe). False for any other mesh.
static func stack_shells_of(root: Node3D, index: Dictionary, id: String) -> bool:
	var e: Variant = _meshes(index).get(id)
	if typeof(e) != TYPE_DICTIONARY or mesh_kind(e) != "shell" or _own_materials(root).is_empty():
		return false
	_stack_shells(mesh_node(root, index, id))
	return true


## Puts the stacked shells on a shell style's node in place of its loaded skin (once a load; the stack is shared
## by every model that shows the style).
static func _stack_shells(mi: MeshInstance3D) -> void:
	if mi == null or mi.mesh == null or mi.mesh.has_meta(META_SHELL_STACK):
		return
	mi.mesh = shell_stack(mi.mesh, shell_layers())
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## `layers` copies of `src`'s first surface in one surface (P51; plan M11 §2.4): copy i carries i in UV2.x (the
## shell shader lifts it), its indices offset by i copies; LODs keep a third of the layers, then the base alone.
## Built once for a source mesh and a layer count while some model holds it.
static func shell_stack(src: Mesh, layers: int) -> ArrayMesh:
	var key := "%d:%d" % [src.get_instance_id(), layers]
	var hit: Variant = _shell_stacks.get(key)
	if hit is WeakRef and (hit as WeakRef).get_ref() != null:
		return (hit as WeakRef).get_ref()
	var arrays := src.surface_get_arrays(0)
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		for i in n:
			idx.append(i)
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for t in Mesh.ARRAY_MAX:
		if t == Mesh.ARRAY_INDEX or t == Mesh.ARRAY_TEX_UV2 or arrays[t] == null:
			continue
		var a: Variant = arrays[t].duplicate()
		for i in range(1, layers):
			a.append_array(arrays[t])
		out[t] = a
	var uv2 := PackedVector2Array()
	uv2.resize(n * layers)
	var index := PackedInt32Array()
	for i in layers:
		for v in n:
			uv2[i * n + v] = Vector2(float(i), 0.0)
		for k in idx:
			index.append(k + i * n)
	out[Mesh.ARRAY_TEX_UV2] = uv2
	out[Mesh.ARRAY_INDEX] = index
	var lod1 := index.slice(0, idx.size() * maxi(1, layers / 3))
	var lod2 := index.slice(0, idx.size())
	var flags := 0
	if src is ArrayMesh:
		flags = (src as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
	var mesh := ArrayMesh.new()
	# P56: the face keys of a shell (the skin under the short beard or the crop) go with every layer
	var shapes := []
	if src is ArrayMesh and (src as ArrayMesh).get_blend_shape_count() > 0:
		var am := src as ArrayMesh
		mesh.blend_shape_mode = am.blend_shape_mode
		for b in am.get_blend_shape_count():
			mesh.add_blend_shape(am.get_blend_shape_name(b))
		for shape: Array in am.surface_get_blend_shape_arrays(0):
			var sa := []
			sa.resize(Mesh.ARRAY_MAX)
			for t in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT]:
				if t < shape.size() and shape[t] != null:
					var a: Variant = shape[t].duplicate()
					for i in range(1, layers):
						a.append_array(shape[t])
					sa[t] = a
			shapes.append(sa)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out, shapes, {0.04: lod1, 0.12: lod2}, flags)
	mesh.set_meta(META_SHELL_STACK, layers)
	mesh.resource_name = src.resource_name + "_shells"
	_shell_stacks[key] = weakref(mesh)
	return mesh


## The colour a skin tone draws at (P51; plan M11 §2.4): the creator's swatch shows it instead of the record's
## colour. The shader draws the baked albedo times tone / bake tone in linear light; the default tone's lit chest
## in the creator's light is DRAWN_DEFAULT, so a tone draws DRAWN_DEFAULT times the same ratio. `option` is a skin
## option (its "color") or a Color.
static func drawn_tone(option: Variant) -> Color:
	var tone := BAKE_TONE
	if option is Color:
		tone = option
	elif typeof(option) == TYPE_DICTIONARY and Color.html_is_valid(str((option as Dictionary).get("color", ""))):
		tone = Color.html(str(option.color))
	var a := DRAWN_DEFAULT.srgb_to_linear()
	var t := tone.srgb_to_linear()
	var b := BAKE_TONE.srgb_to_linear()
	var r := Vector3(t.r / maxf(b.r, 0.01), t.g / maxf(b.g, 0.01), t.b / maxf(b.b, 0.01))
	var out := tone_scaled(Vector3(a.r, a.g, a.b), r)
	return Color(clampf(out.x, 0.0, 1.0), clampf(out.y, 0.0, 1.0), clampf(out.z, 0.0, 1.0)).linear_to_srgb()


## The skin shader's tone_scaled (P51) with its defaults: a tone's ratio to the bake tone on a linear albedo.
static func tone_scaled(albedo: Vector3, ratio: Vector3) -> Vector3:
	var w := Vector3(0.2126, 0.7152, 0.0722)
	var lr := maxf(ratio.dot(w), 1e-4)
	var hue := Vector3.ONE.lerp(ratio / lr, TONE_CHROMA)
	var lr2 := 1.0 + (lr - 1.0) * TONE_SHOULDER if lr > 1.0 else lr
	var la := albedo.dot(w)
	var sat := lerpf(1.0, TONE_RESAT_MAX, clampf(absf(1.0 - lr) * 2.0, 0.0, 1.0) * TONE_RESAT)
	var a := (Vector3.ONE * la + (albedo - Vector3.ONE * la) * sat).max(Vector3.ZERO)
	return a * lr2 * hue


## `look` with every key DEFAULT_LOOK has (its own values kept), a copy.
static func complete(look: Dictionary) -> Dictionary:
	var l := DEFAULT_LOOK.duplicate(true)
	for k: Variant in look:
		l[k] = look[k]
	for key: String in ["tattoos", "scars", "garments", "accessories"]:
		if typeof(l[key]) != TYPE_ARRAY:
			l[key] = []
	if typeof(l.mark) != TYPE_DICTIONARY:
		l["mark"] = {}
	if typeof(l.paint) != TYPE_DICTIONARY and typeof(l.paint) != TYPE_ARRAY:
		l["paint"] = []
	if typeof(l.face) != TYPE_DICTIONARY:
		l["face"] = {}
	if not l.build is Vector2:
		l["build"] = Vector2.ZERO
	return l


## The face sliders (P53; plan M11 §2.5): every shown mesh with a blend shape named like a face key takes the
## key's value (0 when the look has none). A mesh without the shapes (every mesh before P56's face keys) is left
## alone.
static func _apply_face(root: Node3D, index: Dictionary, shown_ids: Array, face: Variant, again := false) -> void:
	var values: Dictionary = face if typeof(face) == TYPE_DICTIONARY else {}
	var any := false
	for k: Variant in values:
		if SchemaUtil.is_number(values[k]) and float(values[k]) != 0.0:
			any = true
			break
	if not any and (again or not root.has_meta(META_FACE)):
		return   # no face slider set, now or before: nothing to put back
	if any:
		root.set_meta(META_FACE, true)
	else:
		root.remove_meta(META_FACE)
	for id: Variant in shown_ids:
		var mi := mesh_node(root, index, str(id))
		if mi == null or mi.mesh == null or mi.get_blend_shape_count() == 0:
			continue
		for k: String in Appearance.FACE_KEYS:
			var at := mi.find_blend_shape_by_name(k)
			if at >= 0:
				var v: Variant = values.get(k, 0.0)
				mi.set_blend_shape_value(at, clampf(float(v), -1.0, 1.0) if SchemaUtil.is_number(v) else 0.0)


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
		var gid := Appearance.garment_id(g)
		var as_mesh: Variant = meshes.get(gid)
		var garment_mesh := typeof(as_mesh) == TYPE_DICTIONARY and str((as_mesh as Dictionary).get("category", "")) == "garment"
		if not garments.has(gid) and not garment_mesh:
			out.append("garments: the index has no garment '%s'" % gid)
	for m: Variant in l.accessories:
		if not meshes.has(str(m)):
			out.append("accessories: the index has no mesh '%s'" % m)
	for key: String in ["hair_beads", "beard_beads"]:
		if str(l[key]) != "" and not meshes.has(str(l[key])):
			out.append("%s: the index has no mesh '%s'" % [key, l[key]])
	var wanted := []   # [design id, kind]
	for t: Variant in l.tattoos:
		wanted.append([str((t as Dictionary).get("design", "")) if typeof(t) == TYPE_DICTIONARY else str(t), "tattoo"])
	for p: Dictionary in paints(l):
		wanted.append([str(p.get("design", "")), "paint"])
	if not (l.mark as Dictionary).is_empty():
		wanted.append([str(l.mark.get("design", "")), "mark"])
	for s: Variant in l.scars:
		wanted.append([str(s), "scar"])
	var scar_layers: Array[int] = []
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
			if not scar_layers.has(layer) and scar_layers.size() < 2:
				scar_layers.append(layer)
			elif not scar_layers.has(layer):
				out.append("scar: '%s' is on layer %d, not one of the scars' two layers %s (four scars a layer)" % [w[0], layer, scar_layers])
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
