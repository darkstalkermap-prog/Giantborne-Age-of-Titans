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
		"scar_farther": {"layer": 5, "channel": 1, "kind": "scar", "regions": [2]},
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
	l.hair_length = 0.6
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
	assert_true(_near(hair.get_shader_parameter("length"), 0.6), "the hair's cut (P46: hair_length)")
	var beard := _mat(root, "Beard_short")
	assert_true(beard.shader == GiantLook.HAIR_SHADER, "the beard draws with giant_hair")
	assert_true(_near(beard.get_shader_parameter("hair_color"), l.beard_color), "the beard's colour")
	assert_true(_near(beard.get_shader_parameter("tip_color"), l.beard_tip), "the beard's tips")
	assert_true(_near(beard.get_shader_parameter("grey"), l.beard_grey), "the beard's grey")
	assert_true(_near(beard.get_shader_parameter("length"), 1.0), "the beard's full length when the look names none")
	# the M10 gate (LC-6): a beard's tips thin strand by strand; P51: a beard no longer fades out seen from behind
	# (its under-jaw cards are closed), and every style shades as a volume
	var full := _mat(root, "Beard_full")
	assert_true(_near(full.get_shader_parameter("tip_thin"), GiantLook.BEARD_TIP_THIN), "a long beard's tips thin out")
	# the second look lane: a short-card beard's tips thin a little too (and its cards narrow to points: they ended
	# square at the cheeks)
	assert_true(_near(beard.get_shader_parameter("tip_thin"), GiantLook.BEARD_SHORT_TIP_THIN), "a short beard's a little")
	assert_true(_near(beard.get_shader_parameter("back_fade"), 0.0) and _near(full.get_shader_parameter("back_fade"), 0.0),
		"a beard is there from behind the head (P51)")
	for m: ShaderMaterial in [hair, beard, full]:
		assert_true(_near(m.get_shader_parameter("volume_normal"), GiantLook.VOLUME_NORMAL), "the style shades as a volume")
	assert_true(_near(hair.get_shader_parameter("tip_thin"), 0.0), "the hair keeps the atlas's own tips")
	assert_true(_near(hair.get_shader_parameter("back_fade"), 0.0), "the hair shows from behind")
	var eye := _mat(root, "Eyes")
	assert_true(eye.shader == GiantLook.EYE_SHADER, "the eyes draw with giant_eye")
	assert_true(_near(eye.get_shader_parameter("iris_color"), l.eye_color), "the iris colour")
	assert_true(_near(eye.get_shader_parameter("iris_glow"), l.eye_glow), "the iris glow")
	assert_true((eye.get_meta(GiantLook.META_NAMES, {}) as Dictionary).has("look")
		and eye.get_shader_parameter("look") == Vector2.ZERO, "the eyes look ahead until the rig turns them (P51)")
	var tunic := _mat(root, "Garment_tunic_core")
	assert_true(_near(tunic.get_shader_parameter("kind"), 0) and _near(tunic.get_shader_parameter("rim"), 0.0),
		"wool is cloth with no rim light (Gate A: the rim ignores N.L and lit the braies' folds edge-on)")
	assert_true(float(_mat(root, "Garment_furs").get_shader_parameter("rim")) > 0.0, "fur keeps its soft edge light (P51)")
	var head := _mat(root, "Body_Head")
	assert_true(head.get_shader_parameter("skin_lut") is Texture2D and head.get_shader_parameter("curvature_tex") is Texture2D,
		"the skin has its subsurface lookup and its curvature (P51)")
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


## The M10 gate's OR-1: the default skin read orange-red in the world's light. The default look multiplied the
## baked albedo (the approved renders' skin) by ruddy / (0.69, 0.53, 0.44) - green down a fifth, blue a quarter,
## in linear light - and the light's wrap was tinted (0.42, 0.20, 0.13). The default tone now draws the albedo
## as baked, the other tones scale it by their swatch against the default's, and the wrap's tint is eased.
func test_the_default_tone_draws_the_albedo_as_baked() -> void:
	assert_true(_near(GiantLook.BAKE_TONE, GiantLook.DEFAULT_LOOK.skin_tone), "the bake tone is the default look's skin tone")
	var look := Appearance.to_look(Appearance.default_record(), "")
	var tone: Color = look.skin_tone
	assert_true(_near(tone, GiantLook.BAKE_TONE), "and the default record's (%s against %s)" % [tone, GiantLook.BAKE_TONE])
	var lin := tone.srgb_to_linear()
	var bake := GiantLook.BAKE_TONE.srgb_to_linear()
	for ch in 3:
		assert_near(lin[ch] / bake[ch], 1.0, 1e-4, "the default look scales channel %d of the albedo by 1" % ch)
	# a paler tone lifts green and blue more than red (less red, not more), a deeper one darkens every channel
	var pale := Color("#c9a08a").srgb_to_linear()
	assert_true(pale.g / bake.g > pale.r / bake.r and pale.b / bake.b > pale.g / bake.g, "pale is paler and less red than the default")
	var deep := Color("#4e3426").srgb_to_linear()
	assert_true(deep.r / bake.r < 0.5 and deep.g / bake.g < 0.5 and deep.b / bake.b < 0.5, "deep darkens every channel")
	# the shader's own defaults: the same bake tone, and a wrap whose red reaches less than twice as far as its blue
	var code := GiantLook.SKIN_SHADER.code
	var re := RegEx.new()
	re.compile("uniform vec3 bake_tone[^=]*= vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	var m := re.search(code)
	assert_true(m != null, "the skin shader declares bake_tone with a default")
	if m != null:
		assert_true(_near(Color(float(m.get_string(1)), float(m.get_string(2)), float(m.get_string(3))), GiantLook.BAKE_TONE),
			"the shader's default bake tone is GiantLook.BAKE_TONE")
	re.compile("uniform vec3 wrap = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\)")
	m = re.search(code)
	assert_true(m != null, "the skin shader declares wrap with a default")
	if m != null:
		var r := float(m.get_string(1))
		var b := float(m.get_string(3))
		assert_true(r >= b and r <= 2.0 * b, "the wrap is warm but not red (%.2f against %.2f; 0.42 against 0.13 before)" % [r, b])


## The M10 gate's LC-6: the hair shader feathers every card's root strand by strand, thins a beard's tips and
## can hide a beard from behind (its cards showed as loose squares beside the neck at the creator's Hair framing;
## since P51 GiantLook no longer asks it to: the beard's under-jaw cards are closed).
func test_the_hair_shader_feathers_roots_and_hides_a_beard_from_behind() -> void:
	var code := GiantLook.HAIR_SHADER.code
	for u: String in ["root_feather", "tip_thin", "back_fade"]:
		assert_true(code.contains("uniform float " + u), "giant_hair declares %s" % u)
	var re := RegEx.new()
	re.compile("uniform float root_feather = ([0-9.]+)")
	var m := re.search(code)
	assert_true(m != null and float(m.get_string(1)) >= 0.08 and float(m.get_string(1)) <= 0.25,
		"the root fades in over a tenth to a quarter of a card")
	re.compile("const float BACK_FADE_FROM = (-?[0-9.]+);\\s*const float BACK_FADE_TO = (-?[0-9.]+);")
	m = re.search(code)
	assert_true(m != null, "the beard's fade is between two camera directions")
	if m != null:
		var from := float(m.get_string(1))
		var to := float(m.get_string(2))
		# 0 is the camera beside the giant, -1 behind him; the creator's Hair framing stands at 140 degrees
		assert_true(from < -0.2 and from > to, "a beard is whole from the side and a little behind it (%.2f)" % from)
		assert_true(to >= cos(deg_to_rad(float(GiantPreview.FRAMINGS.hair.yaw))) + 0.03,
			"and gone at the creator's Hair framing (%.2f against %.2f)" % [to, cos(deg_to_rad(float(GiantPreview.FRAMINGS.hair.yaw)))])
	assert_true(code.contains("smoothstep(BACK_FADE_TO, BACK_FADE_FROM, v_behind), back_fade"), "the fade is applied to the alpha")
	assert_true(code.contains("UV.y + sid * root_feather") and code.contains("UV.y + sid * tip_thin"),
		"root and tip are offset by the strand's id")
	assert_true(GiantLook.BEARD_TIP_THIN >= 0.3 and GiantLook.BEARD_TIP_THIN <= 0.6, "a beard's strands end over a third to a half of a card")


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
	bad.scars = ["scar_brow", "scar_far", "scar_farther", "paint_face_stripes"]
	var p := "\n".join(GiantLook.validate(root2, INDEX, bad))
	assert_true(p.contains("Hair_mohawk"), "an unknown hair mesh")
	assert_true(p.contains("'cape'"), "an unknown garment")
	assert_true(p.contains("tat_dragon"), "an unknown design")
	assert_true(p.contains("'scar_farther' is on layer 5"), "a scar on a third layer (P46: the scars fill two layers of four)")
	assert_false(p.contains("'scar_far' is on layer"), "a scar on the second layer is drawn (scar_layer_b)")
	var two := GiantLook.scar_uniforms(INDEX, ["scar_knuckles", "scar_far", "scar_farther"])
	assert_eq([two.layer, two.on, two.layer_b, two.on_b], [3, Vector4(0, 0, 1, 0), 4, Vector4(1, 0, 0, 0)],
		"the first layer's scars and the second layer's, the third layer's left out")
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
	assert_eq(int(skin.get_shader_parameter("scar_layer_b")), 4, "and the second scar layer (P46)")
	assert_eq(skin.get_shader_parameter("scar_on_b"), Vector4.ZERO, "none on there either")


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


## P46: the hair's sway. One step is a pure easing towards the head's motion times the lag; the sway on a model
## writes the hair shader's head_motion on the shown hair and beard, in the mesh's own space, and stays within
## its bound however fast the head moves.
func test_the_hairs_sway_eases_towards_the_heads_motion_and_is_bounded() -> void:
	var rest := GiantLook.sway_step(Vector3.ZERO, Vector3.ZERO, 1.0 / 60.0)
	assert_eq(rest, Vector3.ZERO, "a still head: no sway")
	var one := GiantLook.sway_step(Vector3.ZERO, Vector3(2, 0, 0), 1.0 / 60.0)
	var target := Vector3(2, 0, 0) * GiantLook.SWAY_LAG_S
	assert_true(one.x > 0.0 and one.x < target.x, "one frame moves part of the way (%.4f of %.4f)" % [one.x, target.x])
	var v := Vector3.ZERO
	for i in 120:
		v = GiantLook.sway_step(v, Vector3(2, 0, 0), 1.0 / 60.0)
	assert_true(v.distance_to(target) < 1e-4, "and settles on the head's motion times the lag")
	for i in 120:
		v = GiantLook.sway_step(v, Vector3.ZERO, 1.0 / 60.0)
	assert_true(v.length() < 1e-4, "and comes back to rest when the head stops")
	assert_true(GiantLook.undeclared_uniforms(GiantLook.HAIR_SHADER, ["head_motion", "length"]).is_empty(),
		"the hair shader declares head_motion and length")
	assert_eq(GiantLook.sway(null, INDEX, null), Vector3.ZERO, "no model, no skeleton: nothing, and no error")


## The W27 merge's fix: the skeleton can update while the giant is out of the tree (the sandbox's reset
## re-parents the player for a frame), where a world transform is an engine error - three of them in the skinned
## 120 s soak, which the determinism gate counts. The sway then does nothing, forgets its last frame, and starts
## afresh in the tree. (The runner fails this test on any logged error.)
func test_the_sway_waits_while_the_giant_is_out_of_the_tree() -> void:
	var root := _model()
	GiantLook.build_materials(root, INDEX, "web")
	var skeleton := Skeleton3D.new()
	skeleton.add_bone(GiantLook.SWAY_BONE)
	root.add_child(skeleton)
	var hair := _mat(root, "Hair_long_back")
	GiantLook.sway(root, INDEX, skeleton)
	root.position = Vector3(0.5, 0, 0)
	assert_true(GiantLook.sway(root, INDEX, skeleton).x > 0.0, "in the tree the head's move sways the hair")
	assert_true((hair.get_shader_parameter("head_motion") as Vector3).x > 0.0, "and the hair's material has it")
	remove_child(root)
	assert_eq(GiantLook.sway(root, INDEX, skeleton), Vector3.ZERO, "out of the tree: no sway, and no engine error")
	assert_true(not root.has_meta(GiantLook.META_SWAY), "and the last frame is forgotten")
	add_child(root)
	assert_eq(GiantLook.sway(root, INDEX, skeleton), Vector3.ZERO, "back in the tree the sway starts afresh")
	assert_true(root.has_meta(GiantLook.META_SWAY), "from this frame's place")



# --------------------------------------------------------------------------- P51: the look pass II

## A model that loads its parts on demand: it records what GiantLook asks of it (GiantModel's two calls).
class PartsRoot extends Node3D:
	var ensured: Array = []
	var released: Array = []

	func ensure_part(id: String) -> MeshInstance3D:
		ensured.append(id)
		return null

	func release_unused(shown: Array) -> void:
		released = shown.duplicate()


## One triangle, skinned to bone 0, as a part's imported surface.
static func _triangle() -> ArrayMesh:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	a[Mesh.ARRAY_BONES] = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])
	a[Mesh.ARRAY_WEIGHTS] = PackedFloat32Array([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
	a[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
	return m


func test_apply_loads_the_parts_a_look_shows_and_lets_go_of_the_rest() -> void:
	var root := PartsRoot.new()
	for id: String in INDEX.meshes:
		var mi := MeshInstance3D.new()
		mi.name = id
		root.add_child(mi)
	add_child(root)
	_roots.append(root)
	var l := _look()
	GiantLook.apply(root, INDEX, l)
	for id: String in ["Hair_crop", "Beard_short", "Garment_tunic_core", "Garment_tunic_limbs", "Garment_belt", "Garment_furs"]:
		assert_true(root.ensured.has(id), "%s is loaded before it is shown" % id)
	assert_false(root.ensured.has("Hair_long_back"), "a style the look does not show is not loaded")
	assert_true(root.released.has("Hair_crop") and not root.released.has("Hair_long_back"),
		"release_unused hears what the look shows: %s" % [root.released])


func test_a_shell_style_draws_its_layers_in_one_surface_and_casts_no_shadow() -> void:
	var index: Dictionary = INDEX.duplicate(true)
	index.meshes["Hair_crop"]["shell"] = {"mask": "scalp", "height_m": 0.018}
	var root := _model()
	var crop := GiantLook.mesh_node(root, index, "Hair_crop")
	var src := _triangle()
	crop.mesh = src
	GiantLook.build_materials(root, index, "web")
	var l := _look()
	GiantLook.apply(root, index, l)
	var mat := crop.material_override as ShaderMaterial
	assert_true(mat != null and mat.shader == GiantLook.SHELL_SHADER, "a shell style draws with giant_shell")
	assert_eq(GiantLook.mesh_kind(index.meshes.Hair_crop), "shell", "a mesh with a shell entry is a shell style")
	assert_eq(int(mat.get_shader_parameter("shell_count")), GiantLook.shell_layers(), "the build's layers")
	assert_eq(GiantLook.shell_layers(), GiantLook.SHELL_LAYERS, "twelve off the Web (probe 6)")
	assert_true(_near(mat.get_shader_parameter("hair_color"), l.hair_color), "the hair's colour")
	assert_true(_near(mat.get_shader_parameter("mask_channel"), GiantLook.SHELL_MASKS.scalp), "the scalp's mask")
	assert_eq(crop.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "shells never cast a shadow")
	var stack := crop.mesh as ArrayMesh
	assert_true(stack != src and stack.has_meta(GiantLook.META_SHELL_STACK), "the loaded skin was stacked")
	assert_eq(stack.get_surface_count(), 1, "one surface: one draw call a style")
	var a := stack.surface_get_arrays(0)
	var layers := GiantLook.shell_layers()
	assert_eq((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 3 * layers, "a copy of the skin a layer")
	var uv2: PackedVector2Array = a[Mesh.ARRAY_TEX_UV2]
	assert_true(is_equal_approx(uv2[0].x, 0.0) and is_equal_approx(uv2[uv2.size() - 1].x, float(layers - 1)),
		"each copy carries its layer in UV2.x")
	assert_eq((a[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 3 * layers, "every layer drawn at LOD 0")
	assert_true(GiantLook.shell_stack(src, layers) == stack, "a stack is built once for a skin")
	GiantLook.apply(root, index, l)
	assert_true(crop.mesh == stack, "and not stacked again")
	assert_eq(GiantLook.validate(root, index, l), PackedStringArray(), "the shell's uniforms are declared")
	index.meshes["Beard_short"]["shell"] = {"mask": "beard", "height_m": 0.015}
	l.beard_mesh = "Beard_short"
	GiantLook.apply(root, index, l)
	var skin := _mat(root, "Body_Head")
	assert_true(float(skin.get_shader_parameter("stubble")) < float(l.stubble),
		"under a shell beard the skin keeps a shade of its stubble only")


func test_the_swatch_shows_the_tone_the_skin_draws() -> void:
	var d := GiantLook.drawn_tone(GiantLook.BAKE_TONE)
	assert_true(_near(d, GiantLook.DRAWN_DEFAULT) or d.is_equal_approx(GiantLook.DRAWN_DEFAULT),
		"the default tone draws as the measured chest")
	var approved := Color8(198, 170, 157)
	for ch in 3:
		assert_true(absf(GiantLook.DRAWN_DEFAULT[ch] - approved[ch]) <= 30.0 / 255.0,
			"within 30/255 of the approved render (Gate A: the world's light first; P51 had 12)")
	var pale := GiantLook.drawn_tone({"color": "#c9a08a"})
	var deep := GiantLook.drawn_tone({"color": "#4e3426"})
	assert_true(pale.get_luminance() > d.get_luminance() and deep.get_luminance() < d.get_luminance(),
		"tones keep their order")
	var rows := OptionRows.choices({"key": "skin", "kind": "swatch", "set": "skin"}, "")
	assert_true(rows.size() >= 9, "the skin row lists its tones")
	for c: Dictionary in rows:
		var o := Appearance.option(str(c.id))
		assert_true((c.color as Color).is_equal_approx(GiantLook.drawn_tone(o)), "%s's swatch is its drawn tone" % c.id)


# --------------------------------------------------------------------------- the look by slot (P53)

## P53 (plan M11 §2.5): the look v2's garments - each {mesh, dye, kind} - show their index garment's meshes in
## their own dye (a split garment both meshes), a metal one with the cloth shader's metal response; M10's shape
## (index garment ids with dye_primary / dye_secondary) still draws as it did; the build and its maximum reach the
## skin and every garment; two war paints place both; the accessories and beads show only what the look names.
func test_the_look_by_slot_dyes_each_garment_and_pushes_the_build() -> void:
	var index: Dictionary = INDEX.duplicate(true)
	index["build_max_m"] = 0.099254
	index.meshes["Acc_torc"] = {"node": "Acc_torc", "category": "accessory", "layer": 2, "dye": "none", "covers": []}
	index.meshes["Bead_bone"] = {"node": "Bead_bone", "category": "bead", "layer": 3, "dye": "none", "covers": []}
	var root := _model()
	for id: String in ["Acc_torc", "Bead_bone"]:
		var mi := MeshInstance3D.new()
		mi.name = id
		mi.mesh = BoxMesh.new()
		root.add_child(mi)
	GiantLook.build_materials(root, index, "web")
	var l: Dictionary = GiantLook.DEFAULT_LOOK.duplicate(true)
	var red := Color(0.5, 0.1, 0.1)
	var brown := Color(0.3, 0.2, 0.1)
	var grey := Color(0.5, 0.5, 0.55)
	l.garments = [{"mesh": "tunic", "dye": red, "kind": "cloth"}, {"mesh": "belt", "dye": brown, "kind": "leather"},
		{"mesh": "furs", "dye": grey, "kind": "metal"}]
	l.build = Vector2(0.5, -0.25)
	l.paint = [{"design": "paint_face_stripes", "color": Color(0.9, 0.9, 0.8)},
		{"design": "tat_chest_knot", "color": Color(0.9, 0.9, 0.8)}]
	l.accessories = ["Acc_torc"]
	GiantLook.apply(root, index, l)
	for id: String in ["Garment_tunic_core", "Garment_tunic_limbs"]:
		assert_true(GiantLook.mesh_node(root, index, id).visible, "%s shows" % id)
		assert_true(_near(_mat(root, id).get_shader_parameter("dye_color"), red), "%s in the tunic's own dye" % id)
	assert_true(_near(_mat(root, "Garment_belt").get_shader_parameter("dye_color"), brown), "the belt in its dye")
	assert_false(GiantLook.mesh_node(root, index, "Garment_braies").visible, "the braies are not worn")
	assert_eq(int(_mat(root, "Garment_furs").get_shader_parameter("kind")), 1, "a metal garment takes the metal response")
	# the second look lane: leather takes its own response (4: warm, waxed, in stitched panels), not the metal's
	assert_eq(int(_mat(root, "Garment_belt").get_shader_parameter("kind")), 4, "leather takes the leather response")
	for id: String in ["Body_Torso", "Garment_belt", "Garment_tunic_limbs"]:
		assert_eq(_mat(root, id).get_shader_parameter("build"), Vector2(0.5, -0.25), "%s: the build" % id)
		assert_true(_near(_mat(root, id).get_shader_parameter("build_max_m"), 0.099254), "%s: the index's build_max_m" % id)
	var paint: PackedInt32Array = _mat(root, "Body_Torso").get_shader_parameter("region_paint")
	assert_true(paint[1] != 0 and paint[3] != 0, "both war paints are placed: %s" % [paint])
	assert_true(GiantLook.mesh_node(root, index, "Acc_torc").visible, "the accessory the look names shows")
	assert_false(GiantLook.mesh_node(root, index, "Bead_bone").visible, "beads it does not name are hidden")
	l.paint = [l.paint[0]]   # (the second was a tattoo's design, to place a second region)
	l.hair_beads = "Bead_bone"
	l.accessories = []
	GiantLook.apply(root, index, l)
	assert_true(GiantLook.mesh_node(root, index, "Bead_bone").visible, "the hair's beads show")
	assert_false(GiantLook.mesh_node(root, index, "Acc_torc").visible, "and the accessory taken off hides")
	assert_eq(GiantLook.validate(root, index, l), PackedStringArray(), "validate() is clean (the new uniforms are declared)")
	l.accessories = ["Acc_none"]
	l.garments = [{"mesh": "kilt", "dye": red, "kind": "cloth"}]
	var problems := "\n".join(GiantLook.validate(root, index, l))
	assert_true(problems.contains("'kilt'") and problems.contains("'Acc_none'"), "unknown garments and accessories: %s" % problems)
	# M10's shape still draws as it did
	var old: Dictionary = _look()
	GiantLook.apply(root, index, old)
	assert_true(_near(_mat(root, "Garment_tunic_core").get_shader_parameter("dye_color"), old.dye_primary), "M10's primary dye")
	assert_true(_near(_mat(root, "Garment_belt").get_shader_parameter("dye_color"), old.dye_secondary), "M10's secondary dye")
	assert_true(_near(_mat(root, "Garment_furs").get_shader_parameter("dye_color"), GiantLook.NATURAL_DYE), "the furs' own")
	assert_eq(_mat(root, "Body_Torso").get_shader_parameter("build"), Vector2.ZERO, "a look without a build: none")


## P53: DEFAULT_LOOK in the v2 shape shows the Wanderer's braies and belt in undyed and dark leather, as M10's did.
func test_the_default_look_v2_is_the_wanderers() -> void:
	var root := _model()
	GiantLook.build_materials(root, INDEX, "web")
	GiantLook.apply(root, INDEX, GiantLook.DEFAULT_LOOK)
	assert_true(GiantLook.mesh_node(root, INDEX, "Garment_braies").visible and GiantLook.mesh_node(root, INDEX, "Garment_belt").visible,
		"the braies and the belt")
	assert_true(_near(_mat(root, "Garment_braies").get_shader_parameter("dye_color"), GiantLook.LEGACY_PRIMARY), "undyed braies")
	assert_true(_near(_mat(root, "Garment_belt").get_shader_parameter("dye_color"), GiantLook.LEGACY_SECONDARY), "a dark belt")
	assert_eq(GiantLook.hidden_regions_mask(INDEX, GiantLook.DEFAULT_LOOK.garments), (1 << 11) | (1 << 12),
		"the mask reads the v2 entries")
	assert_eq(GiantLook.validate(root, INDEX, GiantLook.DEFAULT_LOOK), PackedStringArray(), "validate() is clean")


## P53 (plan M11 §2.5): `face` sets the blend shapes of those names on a shown mesh that has them and leaves a mesh
## without them alone (every mesh before P56's face keys).
func test_the_face_sliders_set_blend_shapes_where_a_mesh_has_them() -> void:
	var root := _model()
	var head := GiantLook.mesh_node(root, INDEX, "Body_Head")
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var shape := []
	shape.resize(Mesh.ARRAY_MAX)
	shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, -0.1, 0), Vector3.RIGHT, Vector3.UP])
	shape[Mesh.ARRAY_NORMAL] = a[Mesh.ARRAY_NORMAL]
	var m := ArrayMesh.new()
	m.add_blend_shape("jaw")
	m.add_blend_shape("brow")
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a, [shape.slice(0, Mesh.ARRAY_MAX), shape.slice(0, Mesh.ARRAY_MAX)])
	head.mesh = m
	var l: Dictionary = GiantLook.DEFAULT_LOOK.duplicate(true)
	l.face = {"jaw": 0.6, "brow": -3.0, "nose": 0.5}
	GiantLook.apply(root, INDEX, l)
	assert_true(_near(head.get_blend_shape_value(head.find_blend_shape_by_name("jaw")), 0.6), "the jaw key takes its slider")
	assert_true(_near(head.get_blend_shape_value(head.find_blend_shape_by_name("brow")), -1.0), "clamped to -1")
	GiantLook.apply(root, INDEX, GiantLook.DEFAULT_LOOK)
	assert_true(_near(head.get_blend_shape_value(head.find_blend_shape_by_name("jaw")), 0.0), "the default face is 0")
	assert_eq(GiantLook.mesh_node(root, INDEX, "Body_Torso").get_blend_shape_count(), 0, "a mesh without keys is left alone")


## P56 (plan M11 §2.5): a bead set with style codes shows its beads only on the shown styles that have anchors - the
## look's hair style when its hair beads are the set (and the style is drawn whole), its beard likewise - by the cloth
## shader's bead_mask (a bit a style code); a style without anchors wears none; a set without codes (the floor's
## shape) shows when named. The scars' channels are gated by the worn scars' regions.
func test_beads_by_style_code_and_scars_by_region() -> void:
	var entry := {"category": "bead", "styles": {"Hair_twin": 1, "Beard_chin": 2}}
	var l: Dictionary = GiantLook.DEFAULT_LOOK.duplicate(true)
	l.hair_mesh = "Hair_twin"
	l.beard_mesh = "Beard_chin"
	l.hair_beads = "Beads_bone"
	assert_eq(GiantLook.bead_mask(entry, "Beads_bone", l), 1 << 1, "the hair's code")
	l.beard_beads = "Beads_bone"
	assert_eq(GiantLook.bead_mask(entry, "Beads_bone", l), (1 << 1) | (1 << 2), "both the hair's and the beard's")
	assert_eq(GiantLook.bead_mask(entry, "Beads_silver", l), 0, "another set shows nothing")
	assert_eq(GiantLook.bead_mask(entry, "Beads_bone", l, {"Hair_twin": 0.3}), 1 << 2, "a helm's cut takes the hair's off")
	l.hair_mesh = "Hair_crop"
	l.beard_mesh = "Beard_full"
	assert_eq(GiantLook.bead_mask(entry, "Beads_bone", l), 0, "styles without anchors wear none")
	var index := {"designs": {"scar_a": {"kind": "scar", "layer": 0, "channel": 0, "regions": [1]},
		"scar_b": {"kind": "scar", "layer": 0, "channel": 0, "regions": [11]},
		"scar_c": {"kind": "scar", "layer": 1, "channel": 3, "regions": [5, 6]}}}
	var u := GiantLook.scar_uniforms(index, ["scar_b", "scar_c"])
	assert_eq(u.on, Vector4(1, 0, 0, 0), "scar_b's channel on")
	assert_eq(u.regions, Vector4i(1 << 11, 0, 0, 0), "only in its own region (scar_a shares the channel)")
	assert_eq(u.regions_b, Vector4i(0, 0, 0, (1 << 5) | (1 << 6)), "the second layer's scar in its regions")



## The W33 look lane: a garment stands off only as far as what is worn under it needs. The index's layering table
## gives, per outer garment and worn inner garment, the least share of its push at each share (0, 0.25 ... 1) of the
## inner one's own push; a garment takes the greatest over the garments worn under it, read at the step at or above
## the inner garment's share; the mesh's push_m scales it.
func test_the_layering_pushes_a_garment_only_as_far_as_what_is_worn_under_it() -> void:
	var index := {"garments": {"braies": ["Garment_braies"], "tunic": ["Garment_tunic_core", "Garment_tunic_limbs"],
			"belt": ["Garment_belt"]},
		"meshes": {"Garment_braies": {"category": "garment"}, "Garment_tunic_core": {"category": "garment", "push_m": 0.05},
			"Garment_tunic_limbs": {"category": "garment", "push_m": 0.05}, "Garment_belt": {"category": "garment", "push_m": 0.1}},
		"layering": {"order": ["braies", "tunic", "belt"], "samples": 5,
			"push": {"tunic": {"braies": [0.4, 0.4, 0.4, 0.4, 0.4]},
				"belt": {"braies": [0.2, 0.2, 0.2, 0.2, 0.2], "tunic": [0.1, 0.3, 0.5, 0.7, 0.9]}}}}
	var one := func(x: float) -> PackedFloat32Array: return PackedFloat32Array([x, x, x, x, x, x])
	assert_eq(GiantLook.garment_pushes(index, ["belt"]), {"belt": one.call(0.0)}, "worn alone: none")
	assert_false(GiantLook.garment_push_m(index, {"Garment_belt": {}}).has("Garment_belt"), "and no push_m set")
	assert_eq(GiantLook.garment_pushes(index, ["belt", "braies"]), {"braies": one.call(0.0), "belt": one.call(0.2)},
		"over the braies")
	var s := GiantLook.garment_pushes(index, ["belt", "tunic", "braies"])
	assert_eq(s.tunic, one.call(0.4), "the tunic over the braies")
	assert_eq(s.belt, one.call(0.5), "the belt over the tunic at 0.4 reads the step at or above it (0.5): more than the braies' 0.2")
	assert_eq(GiantLook.garment_pushes(index, ["belt", "tunic"]).belt, one.call(0.1), "over the tunic at no push")
	var m := GiantLook.garment_push_m(index, {"Garment_braies": {}, "Garment_tunic_core": {}, "Garment_tunic_limbs": {},
		"Garment_belt": {}})
	assert_true(absf((m.Garment_tunic_limbs as PackedFloat32Array)[3] - 0.02) < 1e-6, "a mesh's push_m times its garment's share")
	assert_true(absf((m.Garment_belt as PackedFloat32Array)[0] - 0.05) < 1e-6, "the belt's")
	assert_false(m.has("Garment_braies"), "a mesh without push_m takes none")
	assert_eq(GiantLook.garment_pushes({"garments": {}}, ["belt"]), {}, "an index without the table: none")
	# three knots (the hips, the waist, the chest): a garment under the hips' part pushes that part only
	index.layering["knots_m"] = [2.0, 2.3, 2.7]
	index.layering.push = {"tunic": {"braies": [0.6, 0.1, 0.0, 0.6, 0.1, 0.0, 0.6, 0.1, 0.0, 0.6, 0.1, 0.0, 0.7, 0.2, 0.0]}}
	index["manifest_sha256"] = ""
	assert_eq(GiantLook.garment_pushes(index, ["tunic", "braies"]).tunic, PackedFloat32Array([0.6, 0.1, 0.0, 0.0, 0.0, 0.0]),
		"by knot (the table's last knot repeated)")
