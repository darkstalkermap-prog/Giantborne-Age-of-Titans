extends TestSuite
## GiantLook on a synthetic model (P42; plan M10 §2.4, §2.5, §2.8): a few MeshInstance3D nodes named like
## the giant index's meshes, under a root, with a small index of the plan's format. Every look key sets its
## uniforms and the visibility; validate() flags a misspelled uniform name and unknown ids and is clean
## otherwise; two instances never share a material; the tier falls back to tex/ when a tex_hi/ file is
## missing; the region arrays are always filled (0 = none); headless, apply() alone builds no materials; the
## index's texture names resolve through its `textures` table, and a texture that does not load is reported;
## a duplicated model gets its own nodes and materials.
## (tests/integration/test_giant_look_real.gd runs the same over the real model once P41 has merged.)

const INDEX := {
	"meshes": {
		"Body_Head": {"node": "Body_Head", "category": "body", "layer": 1, "dye": "none", "covers": [], "tris": 10},
		"Body_Torso": {"node": "Body_Torso", "category": "body", "layer": 1, "dye": "none", "covers": [], "tris": 10},
		"Eyes": {"node": "Eyes", "category": "eyes", "layer": 3, "dye": "none", "covers": [], "tris": 10},
		"Hair_long_back": {"node": "Hair_long_back", "category": "hair", "layer": 3, "dye": "none", "covers": [], "tris": 10},
		"Hair_crop": {"node": "Hair_crop", "category": "hair", "layer": 3, "dye": "none", "covers": [], "tris": 10},
		"Beard_full": {"node": "Beard_full", "category": "beard", "layer": 3, "dye": "none", "covers": [], "tris": 10},
		"Beard_short": {"node": "Beard_short", "category": "beard", "layer": 3, "dye": "none", "covers": [], "tris": 10},
		"Garment_braies": {"node": "Garment_braies", "category": "garment", "layer": 1, "dye": "primary",
			"covers": [11, 12], "tris": 10},
		"Garment_belt": {"node": "Garment_belt", "category": "garment", "layer": 1, "dye": "secondary", "covers": [],
			"tris": 10},
		"Garment_tunic_core": {"node": "Garment_tunic_core", "category": "garment", "layer": 1, "dye": "primary",
			"covers": [3, 4, 5, 6], "tris": 10},
		"Garment_tunic_limbs": {"node": "Garment_tunic_limbs", "category": "garment", "layer": 2, "dye": "primary",
			"covers": [8], "tris": 10},
		"Garment_furs": {"node": "Garment_furs", "category": "garment", "layer": 1, "dye": "none", "covers": [7],
			"tris": 10},
	},
	"garments": {"braies": ["Garment_braies"], "belt": ["Garment_belt"],
		"tunic": ["Garment_tunic_core", "Garment_tunic_limbs"], "furs": ["Garment_furs"]},
	"designs": {
		"tat_arm_bands": {"layer": 0, "channel": 0, "kind": "tattoo", "regions": [8, 9]},
		"tat_chest_knot": {"layer": 0, "channel": 3, "kind": "tattoo", "regions": [3, 4]},
		"paint_face_stripes": {"layer": 1, "channel": 2, "kind": "paint", "regions": [1]},
		"mark_granite_veins": {"layer": 2, "channel": 1, "kind": "mark", "regions": [3, 4, 5, 6]},
		"scar_brow": {"layer": 3, "channel": 0, "kind": "scar", "regions": [1]},
		"scar_knuckles": {"layer": 3, "channel": 2, "kind": "scar", "regions": [9]},
		"scar_far": {"layer": 4, "channel": 0, "kind": "scar", "regions": [2]},
	},
	"regions": [{"id": 0, "name": "scalp"}, {"id": 1, "name": "face"}],
	# The web tier is the real one (every sampler must load: validate() reports one that does not); the hi
	# folder does not exist, so "auto" is "web" here.
	"tiers": {"web": "res://assets/giant/tex/", "hi": "res://tests/fixtures/giant/tex_hi/"},
}

var _roots: Array[Node3D] = []


func after_each() -> void:
	for r in _roots:
		if is_instance_valid(r):
			r.free()
	_roots.clear()
	GiantLook.forced_tier = ""


## A synthetic model: one MeshInstance3D per index mesh under a root (garments nested one level down,
## as the glTF's nodes are).
func _model() -> Node3D:
	var root := Node3D.new()
	root.name = "SyntheticGiant"
	var clothes := Node3D.new()
	clothes.name = "Clothes"
	root.add_child(clothes)
	for id: String in INDEX.meshes:
		var mi := MeshInstance3D.new()
		mi.name = str(INDEX.meshes[id].node)
		mi.mesh = BoxMesh.new()
		(clothes if id.begins_with("Garment_") else root).add_child(mi)
	add_child(root)
	_roots.append(root)
	return root


func _mat(root: Node3D, mesh_id: String) -> ShaderMaterial:
	var mi := GiantLook.mesh_node(root, INDEX, mesh_id)
	return mi.material_override as ShaderMaterial if mi != null else null


func _look() -> Dictionary:
	var l: Dictionary = GiantLook.DEFAULT_LOOK.duplicate(true)
	l.skin_tone = Color(0.5, 0.4, 0.3)
	l.eye_color = Color(0.2, 0.3, 0.8)
	l.eye_glow = 0.35
	l.hair_mesh = "Hair_crop"
	l.beard_mesh = "Beard_short"
	l.hair_color = Color(0.1, 0.1, 0.1)
	l.hair_tip = Color(0.2, 0.2, 0.2)
	l.hair_grey = 0.4
	l.beard_color = Color(0.6, 0.3, 0.1)
	l.beard_tip = Color(0.7, 0.4, 0.2)
	l.beard_grey = 0.6
	l.scalp_tint = 0.5
	l.stubble = 0.8
	l.beard_tint = 0.5
	l.tattoos = [{"design": "tat_arm_bands", "ink": Color(0.1, 0.2, 0.5)}]
	l.paint = {"design": "paint_face_stripes", "color": Color(0.9, 0.9, 0.8)}
	l.mark = {"design": "mark_granite_veins", "color": Color(0.4, 0.4, 0.45), "glow": 0.2}
	l.scars = ["scar_brow", "scar_knuckles"]
	l.garments = ["tunic", "belt", "furs"]
	l.dye_primary = Color(0.3, 0.5, 0.2)
	l.dye_secondary = Color(0.15, 0.1, 0.05)
	return l


func _near(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_COLOR and typeof(b) == TYPE_COLOR:
		return (a as Color).is_equal_approx(b)
	if typeof(a) in [TYPE_FLOAT, TYPE_INT] and typeof(b) in [TYPE_FLOAT, TYPE_INT]:
		return is_equal_approx(float(a), float(b))
	return a == b


func _codes(pairs: Dictionary) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(GiantLook.REGIONS)
	a.fill(0)
	for r: int in pairs:
		a[r] = pairs[r]
	return a


func test_headless_apply_sets_visibility_and_stores_the_look_without_materials() -> void:
	var root := _model()
	GiantLook.apply(root, INDEX, GiantLook.DEFAULT_LOOK)
	assert_true(GiantLook.materials(root).is_empty(), "apply() alone builds no materials (the skinned layers are off)")
	assert_eq(GiantLook.built_tier(root), "", "no tier yet")
	assert_true(GiantLook.mesh_node(root, INDEX, "Hair_long_back").visible, "the default hair shows")
	assert_false(GiantLook.mesh_node(root, INDEX, "Hair_crop").visible, "the other hair is hidden")
	assert_true(GiantLook.mesh_node(root, INDEX, "Beard_full").visible, "the default beard shows")
	assert_true(GiantLook.mesh_node(root, INDEX, "Garment_braies").visible, "the braies show")
	assert_true(GiantLook.mesh_node(root, INDEX, "Garment_belt").visible, "the belt shows")
	assert_false(GiantLook.mesh_node(root, INDEX, "Garment_tunic_core").visible, "the tunic is hidden")
	assert_true(GiantLook.mesh_node(root, INDEX, "Body_Head").visible, "the body is never hidden")
	var stored := GiantLook.applied_look(root)
	assert_eq(str(stored.hair_mesh), "Hair_long_back", "the look is stored on the root")
	var partial := {"hair_mesh": "", "garments": ["tunic"]}
	GiantLook.apply(root, INDEX, partial)
	assert_false(GiantLook.mesh_node(root, INDEX, "Hair_long_back").visible, "no hair: every hair mesh hidden")
	assert_true(GiantLook.mesh_node(root, INDEX, "Garment_tunic_limbs").visible, "a split garment shows both meshes")
	assert_eq(str(GiantLook.applied_look(root).beard_mesh), "Beard_full", "a look's missing keys take DEFAULT_LOOK's")


func test_every_look_key_sets_its_uniforms_and_visibility() -> void:
	var root := _model()
	GiantLook.build_materials(root, INDEX, "web")
	var l := _look()
	GiantLook.apply(root, INDEX, l)
	assert_eq(GiantLook.materials(root).size(), INDEX.meshes.size(), "every index mesh has its material")
	var skin := _mat(root, "Body_Head")
	assert_true(skin != null and skin.shader == GiantLook.SKIN_SHADER, "the body draws with giant_skin")
	var want_skin := {"skin_tone": l.skin_tone, "hair_color": l.hair_color, "beard_color": l.beard_color,
		"scalp_tint": l.scalp_tint, "stubble": l.stubble, "beard_tint": l.beard_tint, "tattoo_ink": l.tattoos[0].ink,
		"paint_color": l.paint.color, "mark_color": l.mark.color, "mark_glow": l.mark.glow, "scar_layer": 3,
		"scar_on": Vector4(1, 0, 1, 0), "bake_tone": GiantLook.BAKE_TONE, "hide_shrink": GiantLook.HIDE_SHRINK_M,
		"brows": 1.0}
	for u: String in want_skin:
		assert_true(_near(skin.get_shader_parameter(u), want_skin[u]),
			"skin %s = %s (got %s)" % [u, want_skin[u], skin.get_shader_parameter(u)])
	assert_eq(skin.get_shader_parameter("region_tattoo"), _codes({8: 1, 9: 1}), "the tattoo's code in the arm regions")
	assert_eq(skin.get_shader_parameter("region_paint"), _codes({1: 1 * 4 + 2 + 1}), "the paint's code on the face")
	assert_eq(skin.get_shader_parameter("region_mark"), _codes({3: 10, 4: 10, 5: 10, 6: 10}), "the mark's code")
	assert_eq(int(skin.get_shader_parameter("hidden_regions")), (1 << 3) | (1 << 4) | (1 << 5) | (1 << 6) | (1 << 8)
		| (1 << 7), "the regions the tunic and furs cover are hidden")
	var hair := _mat(root, "Hair_crop")
	assert_true(hair.shader == GiantLook.HAIR_SHADER, "hair draws with giant_hair")
	assert_true(_near(hair.get_shader_parameter("hair_color"), l.hair_color), "the hair's colour")
	assert_true(_near(hair.get_shader_parameter("tip_color"), l.hair_tip), "the hair's tips")
	assert_true(_near(hair.get_shader_parameter("grey"), l.hair_grey), "the hair's grey")
	var beard := _mat(root, "Beard_short")
	assert_true(beard.shader == GiantLook.HAIR_SHADER, "the beard draws with giant_hair")
	assert_true(_near(beard.get_shader_parameter("hair_color"), l.beard_color), "the beard's colour")
	assert_true(_near(beard.get_shader_parameter("tip_color"), l.beard_tip), "the beard's tips")
	assert_true(_near(beard.get_shader_parameter("grey"), l.beard_grey), "the beard's grey")
	var eye := _mat(root, "Eyes")
	assert_true(eye.shader == GiantLook.EYE_SHADER, "the eyes draw with giant_eye")
	assert_true(_near(eye.get_shader_parameter("iris_color"), l.eye_color), "the iris colour")
	assert_true(_near(eye.get_shader_parameter("iris_glow"), l.eye_glow), "the iris glow")
	assert_true(_mat(root, "Garment_tunic_core").shader == GiantLook.CLOTH_SHADER, "garments draw with giant_cloth")
	assert_true(_near(_mat(root, "Garment_tunic_core").get_shader_parameter("dye_color"), l.dye_primary), "primary dye")
	assert_true(_near(_mat(root, "Garment_belt").get_shader_parameter("dye_color"), l.dye_secondary), "secondary dye")
	assert_true(_near(_mat(root, "Garment_furs").get_shader_parameter("dye_color"), GiantLook.NATURAL_DYE),
		"an undyed garment keeps its natural colour")
	assert_true(_near(_mat(root, "Garment_tunic_core").get_shader_parameter("fade"), 0.0), "no fade")
	GiantLook.set_garment_fade(root, INDEX, 0.6)
	assert_true(_near(_mat(root, "Garment_tunic_core").get_shader_parameter("fade"), 0.6), "the creator's fade")
	assert_true(_near(_mat(root, "Garment_tunic_core").get_shader_parameter("detail_strength"),
		GiantLook.DETAIL_STRENGTH.weave), "the tunic is woven")
	assert_true(_near(_mat(root, "Garment_belt").get_shader_parameter("detail_strength"),
		GiantLook.DETAIL_STRENGTH.leather), "the belt is leather")
	for id: String in ["Hair_crop", "Beard_short", "Garment_tunic_core", "Garment_tunic_limbs", "Garment_belt",
			"Garment_furs"]:
		assert_true(GiantLook.mesh_node(root, INDEX, id).visible, "%s shows" % id)
	for id: String in ["Hair_long_back", "Beard_full", "Garment_braies"]:
		assert_false(GiantLook.mesh_node(root, INDEX, id).visible, "%s is hidden" % id)
	GiantLook.apply(root, INDEX, l.merged({"beard_mesh": ""}, true))
	assert_true(_near(skin.get_shader_parameter("beard_tint"), 0.0), "no beard: no beard tint on the skin")
	assert_eq(GiantLook.validate(root, INDEX, l), PackedStringArray(), "validate() is clean for the look")


func test_validate_flags_a_misspelled_uniform_and_unknown_ids() -> void:
	var root := _model()
	GiantLook.build_materials(root, INDEX, "web")
	assert_eq(GiantLook.validate(root, INDEX, GiantLook.DEFAULT_LOOK), PackedStringArray(), "clean at first")
	GiantLook.set_param(_mat(root, "Body_Head"), "skin_tome", Color.RED)
	var problems := "\n".join(GiantLook.validate(root, INDEX, GiantLook.DEFAULT_LOOK))
	assert_true(problems.contains("skin_tome"), "a misspelled uniform name is flagged: %s" % problems)
	var root2 := _model()
	GiantLook.build_materials(root2, INDEX, "web")
	var bad := _look()
	bad.hair_mesh = "Hair_mohawk"
	bad.garments = ["tunic", "cape"]
	bad.tattoos = [{"design": "tat_dragon", "ink": Color.BLUE}]
	bad.scars = ["scar_brow", "scar_far", "paint_face_stripes"]
	var p := "\n".join(GiantLook.validate(root2, INDEX, bad))
	assert_true(p.contains("Hair_mohawk"), "an unknown hair mesh")
	assert_true(p.contains("'cape'"), "an unknown garment")
	assert_true(p.contains("tat_dragon"), "an unknown design")
	assert_true(p.contains("scar_far") and p.contains("layer"), "a scar on another layer than the first")
	assert_true(p.contains("paint_face_stripes") and p.contains("is a paint"), "a design of another kind")
	var orphan := INDEX.duplicate(true)
	orphan.meshes["Garment_cape"] = {"node": "Garment_cape", "category": "garment"}
	assert_true("\n".join(GiantLook.validate(root2, orphan, GiantLook.DEFAULT_LOOK)).contains("no node for the mesh"),
		"an index mesh without its node")
	assert_true(GiantLook.undeclared_uniforms(GiantLook.SKIN_SHADER, ["skin_tone", "region_tattoo"]).is_empty(),
		"the skin shader declares its uniforms")
	for kind: String in GiantLook.UNIFORMS:
		assert_eq(GiantLook.undeclared_uniforms(GiantLook.shader_for(kind), GiantLook.UNIFORMS[kind]
			+ GiantLook.PAINT_UNIFORMS), PackedStringArray(), "giant_%s declares every uniform GiantLook sets" % kind)


func test_two_instances_never_share_a_material() -> void:
	var a := _model()
	var b := _model()
	GiantLook.build_materials(a, INDEX, "web")
	GiantLook.build_materials(b, INDEX, "web")
	var seen := {}
	for m in GiantLook.materials(a) + GiantLook.materials(b):
		assert_false(seen.has(m.get_instance_id()), "a material is used once")
		seen[m.get_instance_id()] = true
	assert_eq(seen.size(), INDEX.meshes.size() * 2, "one material per mesh per instance")
	GiantLook.apply(a, INDEX, _look())
	assert_false(_near(_mat(b, "Body_Head").get_shader_parameter("skin_tone"), _look().skin_tone),
		"a look on one instance leaves the other as it was")
	GiantLook.build_materials(a, INDEX, "web")
	assert_true(_near(_mat(a, "Body_Head").get_shader_parameter("skin_tone"), _look().skin_tone),
		"rebuilding the materials keeps the stored look")


func test_the_tier_falls_back_to_the_web_folder() -> void:
	var web := str(INDEX.tiers.web)
	var hi := str(INDEX.tiers.hi)
	var all_hi := func(path: String) -> bool: return true
	var no_orm := func(path: String) -> bool: return path != hi + "orm.png"
	var none := func(path: String) -> bool: return not path.begins_with(hi)
	assert_eq(GiantLook.resolve_tier("auto", INDEX, all_hi), "hi", "auto picks hi when tex_hi/normal.png exists")
	assert_eq(GiantLook.resolve_tier("auto", INDEX, none), "web", "auto picks web without tex_hi/")
	assert_eq(GiantLook.resolve_tier("web", INDEX, all_hi), "web", "web asked is web")
	var maps: Dictionary = GiantLook.map_paths(INDEX, "hi", no_orm)
	assert_eq(str(maps.normal_tex), hi + "normal.png", "hi: the normal map from tex_hi/")
	assert_eq(str(maps.orm_tex), web + "orm.png", "a missing tex_hi/ file falls back to tex/")
	assert_eq(str(maps.albedo_tex), web + "albedo.png", "the albedo is always the web tier's")
	assert_eq(str(maps.mask_tex), web + "masks.png", "the masks too")
	var web_maps: Dictionary = GiantLook.map_paths(INDEX, "web", all_hi)
	for u: Variant in web_maps:
		assert_true(str(web_maps[u]).begins_with(web), "web: %s from tex/" % u)
	GiantLook.forced_tier = "web"
	assert_eq(GiantLook.resolve_tier("auto", INDEX, all_hi), "web", "--giant-tier=web forces the web tier")
	assert_eq(GiantLook.resolve_tier("hi", INDEX, all_hi), "web", "even over a hi request")
	GiantLook.forced_tier = "hi"
	assert_eq(GiantLook.resolve_tier("auto", INDEX, none), "hi", "--giant-tier=hi forces hi")
	GiantLook.forced_tier = ""
	var root := _model()
	GiantLook.build_materials(root, INDEX, "auto")
	assert_eq(GiantLook.built_tier(root), "web", "the synthetic model has no tex_hi/: web")


func test_the_region_arrays_are_always_filled() -> void:
	var root := _model()
	GiantLook.build_materials(root, INDEX, "web")
	var skin := _mat(root, "Body_Head")
	for arr: String in ["region_tattoo", "region_paint", "region_mark"]:
		assert_eq(skin.get_shader_parameter(arr), _codes({}), "%s: 16 zeros for the default look" % arr)
	GiantLook.apply(root, INDEX, _look())
	GiantLook.apply(root, INDEX, GiantLook.DEFAULT_LOOK)
	for arr: String in ["region_tattoo", "region_paint", "region_mark"]:
		assert_eq(skin.get_shader_parameter(arr), _codes({}), "%s: back to zeros when the designs go" % arr)
	var codes := GiantLook.region_codes(INDEX, {"tattoos": [{"design": "tat_arm_bands"}, {"design": "tat_chest_knot"}],
		"paint": {"design": "nope"}})
	assert_eq(codes.tattoo, _codes({8: 1, 9: 1, 3: 4, 4: 4}), "two tattoos, layer * 4 + channel + 1")
	assert_eq(codes.paint, _codes({}), "an unknown design is left out")
	assert_eq(int(skin.get_shader_parameter("scar_layer")), 3, "no scar: the scars' layer all the same")
	assert_eq(skin.get_shader_parameter("scar_on"), Vector4.ZERO, "and none on")


## The real index names its maps ("atlas": "hair_atlas", "detail": "leather" | "weave" | "fur") and maps the
## names to paths in `textures` (W25 review C1: they were loaded as paths and every one came back null).
func test_the_index_names_its_textures_and_a_missing_one_is_reported() -> void:
	var named := INDEX.duplicate(true)
	named["textures"] = {"hair_atlas": GiantLook.HAIR_ATLAS, "designs": GiantLook.DESIGN_ARRAY,
		"detail_weave": GiantLook.CLOTH_DETAIL.weave, "detail_leather": GiantLook.CLOTH_DETAIL.leather,
		"detail_fur": GiantLook.CLOTH_DETAIL.fur}
	for id: String in ["Hair_long_back", "Hair_crop", "Beard_full", "Beard_short"]:
		named.meshes[id]["atlas"] = "hair_atlas"
	named.meshes["Garment_braies"]["detail"] = "weave"
	named.meshes["Garment_belt"]["detail"] = "leather"
	named.meshes["Garment_furs"]["detail"] = "fur"
	assert_eq(GiantLook.texture_path(named, "hair_atlas", "", "hair_atlas"), GiantLook.HAIR_ATLAS, "a name: the table's path")
	assert_eq(GiantLook.texture_path(named, "fur", "detail_", "detail_weave"), GiantLook.CLOTH_DETAIL.fur,
		"a detail kind: the table's detail_<kind>")
	assert_eq(GiantLook.texture_path(named, "res://x.png", "", "hair_atlas"), "res://x.png", "a path is used as it is")
	assert_eq(GiantLook.texture_path(named, "hair_braided", "", "hair_atlas"), "", "a name the table lacks: none")
	assert_eq(GiantLook.texture_path(INDEX, "", "detail_", "detail_leather"), GiantLook.CLOTH_DETAIL.leather,
		"no table: the defaults")
	var root := _model()
	GiantLook.build_materials(root, named, "web")
	for id: String in ["Hair_crop", "Beard_short"]:
		var atlas: Variant = GiantLook.mesh_node(root, named, id).material_override.get_shader_parameter("hair_atlas")
		assert_true(atlas is Texture2D and (atlas as Texture2D).resource_path == GiantLook.HAIR_ATLAS, "%s has the atlas" % id)
	var want := {"Garment_braies": "weave", "Garment_belt": "leather", "Garment_furs": "fur"}
	for id: String in want:
		var mat: ShaderMaterial = GiantLook.mesh_node(root, named, id).material_override
		var tex: Variant = mat.get_shader_parameter("detail_tex")
		assert_true(tex is Texture2D and (tex as Texture2D).resource_path == GiantLook.CLOTH_DETAIL[want[id]],
			"%s has the %s map" % [id, want[id]])
		assert_true(_near(mat.get_shader_parameter("detail_strength"), GiantLook.DETAIL_STRENGTH[want[id]]),
			"%s has the %s strength" % [id, want[id]])
	assert_eq(GiantLook.validate(root, named, GiantLook.DEFAULT_LOOK), PackedStringArray(), "every texture loads")
	var broken := named.duplicate(true)
	broken.meshes["Hair_crop"]["atlas"] = "hair_braided"
	broken.meshes["Garment_belt"]["detail"] = "silk"
	var root2 := _model()
	GiantLook.build_materials(root2, broken, "web")
	var p := "\n".join(GiantLook.validate(root2, broken, GiantLook.DEFAULT_LOOK))
	assert_true(p.contains("Hair_crop") and p.contains("hair_atlas") and p.contains("did not load"),
		"an atlas that does not load is reported: %s" % p)
	assert_true(p.contains("Garment_belt") and p.contains("detail_tex"), "so is a detail map")
	var no_tier := INDEX.duplicate(true)
	no_tier["tiers"] = {"web": "res://tests/fixtures/giant/no_such_tier/"}
	var root3 := _model()
	GiantLook.build_materials(root3, no_tier, "web")
	assert_true("\n".join(GiantLook.validate(root3, no_tier, GiantLook.DEFAULT_LOOK)).contains("albedo_tex"),
		"and a skin map that does not load")


## Node.duplicate() copies metadata: a copy must not reach into its original's meshes or share its
## materials (W25 review C4).
func test_a_duplicated_model_gets_its_own_nodes_and_materials() -> void:
	var a := _model()
	GiantLook.apply(a, INDEX, GiantLook.DEFAULT_LOOK)
	GiantLook.build_materials(a, INDEX, "web")
	var a_mat := _mat(a, "Body_Head")
	var b := a.duplicate() as Node3D
	add_child(b)
	_roots.append(b)
	assert_true(GiantLook.mesh_node(b, INDEX, "Body_Head") != GiantLook.mesh_node(a, INDEX, "Body_Head"),
		"the copy finds its own nodes")
	assert_true(b.is_ancestor_of(GiantLook.mesh_node(b, INDEX, "Garment_belt")), "under the copy")
	assert_true(GiantLook.materials(b).is_empty(), "the copy has no materials of its own yet")
	assert_eq(GiantLook.built_tier(b), "", "nor a tier")
	GiantLook.build_materials(b, INDEX, "web")
	assert_true(_mat(a, "Body_Head") == a_mat, "building the copy's leaves the original's materials")
	assert_true(_mat(b, "Body_Head") != a_mat and _mat(b, "Body_Head") != null, "the copy has its own")
	var seen := {}
	for m in GiantLook.materials(a) + GiantLook.materials(b):
		seen[m.get_instance_id()] = true
	assert_eq(seen.size(), INDEX.meshes.size() * 2, "no material shared")
	GiantLook.apply(b, INDEX, _look())
	assert_false(_near(a_mat.get_shader_parameter("skin_tone"), _look().skin_tone), "a look on the copy leaves the original")
	assert_true(GiantLook.mesh_node(a, INDEX, "Hair_long_back").visible, "and its visibility")
	var c := a.duplicate() as Node3D
	add_child(c)
	_roots.append(c)
	GiantLook.apply(c, INDEX, _look())
	assert_true(_mat(c, "Body_Head") != a_mat and _near(_mat(c, "Body_Head").get_shader_parameter("skin_tone"),
		_look().skin_tone), "a copy's first apply gives it its own materials, with the look")
	assert_true(_near(a_mat.get_shader_parameter("skin_tone"), GiantLook.DEFAULT_LOOK.skin_tone), "the original keeps its own")
