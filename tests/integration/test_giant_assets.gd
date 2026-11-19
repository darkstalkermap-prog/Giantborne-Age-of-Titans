extends TestSuite
## P41 (plan M10 §3.1, tests): the generated giant as Godot imports it. Reads the committed sources
## (the glTF, the design array's PNG, the manifest) and the saved scenes/player/giant_model.tscn, never
## .godot/imported (plan §2.13):
##   * the model loads and instances; the contract's 53 bones (§2.6) and P48's 18 leaf bones (M11 §2.2);
##   * every index mesh exists with its render layer and category, under its triangle cap (a part is
##     loaded for the check: P48, a glTF a part);
##   * the saved scene, reloaded from disk, shows the layers and the default meshes after _ready (edits
##     inside an instance are never saved, so GiantModel applies them from the index);
##   * the index, the glTFs (giant.glb and the parts) and the design array agree;
##   * the landmarks of P48 (the grips, their axes, the knuckles, the toes) and each design's side;
##   * the landmarks lie within 2 cm of the animation brief's (the shoulder at (0.414, 3.015, -0.033),
##     a reach of 1.385 m at stage 1);
##   * the import settings of §2.5; no .import file under tools/ (the vendored CC0 data is not imported);
##   * the fullest look shows at most 13 meshes (§2.12: draw calls at the low preset) and at most 55,000
##     triangles at full detail (M10's outfits); P54: the fullest slot look at most 24 meshes and 70,000 triangles;
##     a helm hides or cuts each hair style as its index entry says; every outfit valid;
##   * hand_transform() follows the hand bone.

const MODEL := "res://scenes/player/giant_model.tscn"
const GLB := "res://assets/giant/giant.glb"
const DESIGNS := "res://assets/giant/designs.png"
const MANIFEST := "res://assets/giant/manifest.json"
const BONES := ["Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head"]
const SIDE_BONES := ["clavicle", "upperarm", "lowerarm", "hand", "thumb_01", "thumb_02", "thumb_03",
	"index_01", "index_02", "index_03", "middle_01", "middle_02", "middle_03", "ring_01", "ring_02", "ring_03",
	"pinky_01", "pinky_02", "pinky_03", "thigh", "calf", "foot", "ball"]
## Triangles a mesh may have, by category (the boots are decimated toward 2,500).
const TRI_CAP := {"body": 16000, "eyes": 1200, "hair": 6000, "beard": 4000, "garment": 5000, "accessory": 400}
## P48 (plan M11 §2.2): the leaf chains under head and spine_03.
const LEAF_BONES := ["hair_01", "hair_02", "hair_03", "hair_l_01", "hair_l_02", "hair_r_01", "hair_r_02", "beard_01",
	"beard_02", "cape_c_01", "cape_c_02", "cape_c_03", "cape_l_01", "cape_l_02", "cape_l_03", "cape_r_01", "cape_r_02",
	"cape_r_03"]
const CORE_MESHES := ["Body_Head", "Body_Limbs", "Body_Torso", "Eyes", "ShadowProxy"]
const LAYER_OF := {"Body_Head": 3, "Body_Torso": 2, "Body_Limbs": 1, "Eyes": 3}
## The animation brief's landmarks at stage 1 (game frame).
const BRIEF_SHOULDER_R := Vector3(0.414, 3.015, -0.033)
const BRIEF_REACH := 1.385
## The floor's fullest looks (plan §2.3): the warrior and the chieftain, long hair and the full beard.
const FULLEST := [["tunic", "jerkin", "belt", "bracers", "boots"], ["braies", "belt", "furs", "jerkin", "boots"],
	["braies", "belt", "pauldron", "bracers", "leg_wraps"], ["braies", "belt", "cape", "leg_wraps", "boots"]]   # P46's two
const MAX_MESHES := 13
const MAX_TRIANGLES := 55000


func _model() -> GiantModel:
	var m := (load(MODEL) as PackedScene).instantiate() as GiantModel
	add_child(m)
	return m


func test_the_model_loads_with_its_skeleton_and_every_index_mesh() -> void:
	assert_true(ResourceLoader.exists(MODEL), "scenes/player/giant_model.tscn exists (tools/builders/giant_model.gd)")
	if not ResourceLoader.exists(MODEL):
		return
	var m := _model()
	var sk := m.skeleton()
	assert_true(sk != null, "one Skeleton3D")
	if sk == null:
		m.free()
		return
	assert_eq(sk.get_bone_count(), 53 + LEAF_BONES.size(), "the game_engine rig's 53 bones and the 18 leaf bones (P48)")
	for b: String in LEAF_BONES:
		var bi := sk.find_bone(b)
		assert_true(bi >= 0, "the leaf bone %s" % b)
		if bi >= 0:
			var root := bi
			while sk.get_bone_parent(root) >= 0 and LEAF_BONES.has(sk.get_bone_name(sk.get_bone_parent(root))):
				root = sk.get_bone_parent(root)
			assert_eq(sk.get_bone_name(sk.get_bone_parent(root)), "spine_03" if b.begins_with("cape") else "head",
				"%s hangs under %s" % [b, "spine_03" if b.begins_with("cape") else "head"])
	var expected: Array[String] = []
	for b: String in BONES:
		expected.append(b)
	for b: String in SIDE_BONES:
		expected.append(b + "_l")
		expected.append(b + "_r")
	var missing := expected.filter(func(b: String) -> bool: return sk.find_bone(b) < 0)
	assert_eq(missing, [], "every bone of the contract (§2.6)")
	assert_true(m.is_in_group(GiantModel.GROUP), "joins giant_models")
	var idx: Dictionary = m.index
	assert_true(idx.has("meshes") and idx.has("designs") and idx.has("landmarks") and idx.has("manifest_sha256"),
		"the scene carries the index")
	for id: String in idx.meshes:
		var e: Dictionary = idx.meshes[id]
		var mi := m.mesh(id)
		assert_true(mi != null, "%s is a mesh of the model" % id)
		if mi == null:
			continue
		if m.is_part(id):
			assert_true(m.ensure_part(id) == mi and mi.mesh != null, "%s: its part loads on the model's node" % id)
			if mi.mesh == null:
				continue
		var cat := str(e.category)
		assert_true(TRI_CAP.has(cat), "%s: a known category (%s)" % [id, cat])
		assert_true(int(e.tris) <= int(TRI_CAP.get(cat, 0)), "%s: %d triangles, under the %s cap" % [id, int(e.tris), cat])
		assert_eq(int(mi.mesh.surface_get_array_index_len(0)) / 3, int(e.tris), "%s: the index counts its triangles" % id)
		assert_true(mi.skin != null and mi.skeleton != NodePath(""), "%s is skinned to the skeleton" % id)
		if LAYER_OF.has(id):
			assert_eq(int(e.layer), int(LAYER_OF[id]), "%s on render layer %d (decision 8)" % [id, int(LAYER_OF[id])])
		if cat in ["hair", "beard", "eyes"]:
			assert_eq(int(e.layer), 3, "%s on the head's layer" % id)
		if cat == "garment":
			# P54: a head garment is drawn with the head (layer 3: first person culls it)
			var want_layer: int = int({"limbs": 1, "head": 3}.get(str(e.get("part", "")), 2))
			assert_eq(int(e.layer), int(want_layer), "%s: limbs on 1, cores on 2, the head's on 3" % id)
		if cat == "accessory":
			assert_eq(int(e.layer), 1 if str(e.get("bone", "")).begins_with("upperarm") else 2, "%s: on its bone's layer" % id)
	assert_eq(m.meshes("body").size(), 3, "the body in three parts")
	assert_eq(m.meshes("hair").size() + m.meshes("beard").size(), 9,
		"the catalogue's five hair and four beard meshes (the floor's four and the look pass's five, P46)")
	m.free()


func test_the_saved_scene_shows_the_layers_and_defaults_after_ready() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var packed := ResourceLoader.load(MODEL, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var m := packed.instantiate() as GiantModel
	add_child(m)
	var shown: Array = m.index.defaults.shown
	assert_true(shown.has("Body_Head") and shown.has("Hair_long_back") and shown.has("Beard_full"),
		"the Wanderer's meshes are the defaults (%s)" % str(shown))
	for id: String in m.index.meshes:
		var mi := m.mesh(id)
		if mi == null:
			continue
		assert_eq(mi.layers, 1 << (int(m.index.meshes[id].layer) - 1), "%s on its render layer after _ready" % id)
		assert_eq(mi.visible, shown.has(id), "%s %s by default" % [id, "shown" if shown.has(id) else "hidden"])
	var giant := m.get_node_or_null("Giant") as Node3D
	assert_true(giant != null and giant.scene_file_path == GLB, "the glTF is an instance in the saved scene")
	if giant != null:
		assert_true(giant.basis.z.is_equal_approx(Vector3(0, 0, -1)), "turned 180 degrees: the giant faces -Z")
	m.free()


func test_the_index_the_gltf_and_the_design_array_agree() -> void:
	var text := FileAccess.get_file_as_string(MANIFEST)
	var doc: Variant = JSON.parse_string(text)
	assert_true(typeof(doc) == TYPE_DICTIONARY, "the manifest parses")
	if typeof(doc) != TYPE_DICTIONARY or not ResourceLoader.exists(MODEL):
		return
	var m := _model()
	assert_eq(str(m.index.manifest_sha256), text.sha256_text(), "the scene's index is the committed manifest's")
	var gltf_meshes: Array[String] = []
	var gltf := (load(GLB) as PackedScene).instantiate()
	for n in gltf.find_children("*", "MeshInstance3D", true, false):
		gltf_meshes.append(n.name)
	gltf.free()
	gltf_meshes.sort()
	assert_eq(gltf_meshes, CORE_MESHES, "giant.glb holds the body, the eyes and the shadow proxy (P48)")
	# P48: every other index mesh is a part, a glTF of its own that holds that one mesh
	for id: String in m.index.meshes:
		var e: Dictionary = m.index.meshes[id]
		if not e.has(GiantModel.PART_PATH):
			assert_true(CORE_MESHES.has(id), "%s is a mesh of giant.glb" % id)
			continue
		assert_eq(str(e[GiantModel.PART_PATH]), "res://assets/giant/parts/%s.glb" % id, "%s: its part's path" % id)
		assert_true(ResourceLoader.exists(str(e[GiantModel.PART_PATH])), "%s: its part is imported" % id)
		var part := (load(str(e[GiantModel.PART_PATH])) as PackedScene).instantiate()
		var names: Array[String] = []
		for n in part.find_children("*", "MeshInstance3D", true, false):
			names.append(n.name)
		part.free()
		assert_eq(names, [id] as Array[String], "%s.glb holds its one mesh" % id)
		gltf_meshes.append(id)
	gltf_meshes.erase("ShadowProxy")
	gltf_meshes.sort()
	var ids: Array = m.index.meshes.keys()
	ids.sort()
	assert_eq(ids, gltf_meshes, "the index lists exactly the glTFs' meshes (the shadow proxy is no look's mesh)")
	assert_eq(str(m.index.shadow_proxy.node), "ShadowProxy", "the index names the shadow proxy")
	var files: Dictionary = (doc as Dictionary).files
	var on_disk := Array(DirAccess.get_files_at("res://assets/giant/parts")).filter(
		func(f: String) -> bool: return f.ends_with(".glb"))
	assert_eq(on_disk.size(), gltf_meshes.size() - 4, "a file a part under assets/giant/parts, no other")
	for f: String in on_disk:
		assert_true(files.has("assets/giant/parts/" + f), "the manifest lists parts/%s" % f)
	# P51 added four: tex/skin_lut.png, tex/curvature.png, cloth_metal.png and shell_strands.png; P54 two:
	# cloth_mail.png and cloth_scale.png
	assert_eq(files.size(), 19 + on_disk.size(), "the manifest's files: M10's 13, P51's four, P54's two and the parts")
	for g: String in m.index.garments:
		for id: String in m.index.garments[g]:
			assert_true(m.index.meshes.has(id), "garment %s's mesh %s is indexed" % [g, id])
	for id: String in m.index.defaults.shown:
		assert_true(m.index.meshes.has(id), "default %s is indexed" % id)
	var arr := load(DESIGNS) as TextureLayered
	assert_true(arr != null, "designs.png imports as a texture array (%s)" % str(arr))
	if arr != null:
		assert_eq(arr.get_layers(), int(m.index.textures.design_layers), "the array has the index's layer count")
		assert_eq([arr.get_width(), arr.get_height()], [512, 512], "512 x 512 layers")
	var kinds := {}
	for d: String in m.index.designs:
		var e: Dictionary = m.index.designs[d]
		assert_true(int(e.layer) >= 0 and int(e.layer) < int(m.index.textures.design_layers), "%s: a layer of the array" % d)
		assert_true(int(e.channel) >= 0 and int(e.channel) <= 3, "%s: a channel" % d)
		kinds[str(e.kind)] = int(kinds.get(str(e.kind), 0)) + 1
	assert_eq(kinds, {"tattoo": 16, "paint": 4, "scar": 6, "mark": 3},
		"the catalogue's 29 designs (§2.3: the floor's 17 and the look pass's 12, P46)")
	for d: String in m.index.designs:
		assert_true(str(m.index.designs[d].get("side", "")) in ["left", "right", "centre"], "%s: its side (P48)" % d)
	# P48: the chains and the build range
	assert_eq((m.index.chains as Dictionary).size(), 7, "seven leaf chains")
	var chain_bones: Array = []
	for c: String in m.index.chains:
		chain_bones.append_array(m.index.chains[c].bones)
	chain_bones.sort()
	var leaf := LEAF_BONES.duplicate()
	leaf.sort()
	assert_eq(chain_bones, leaf, "the chains name the 18 leaf bones")
	assert_true(float(m.index.build_max_m) > 0.02 and float(m.index.build_max_m) < 0.2,
		"build_max_m: the build sliders' largest push at stage 1 (%s m)" % str(m.index.build_max_m))
	assert_eq((m.index.regions as Array).size(), 16, "16 regions")
	for tier: String in ["web", "hi"]:
		for f: String in ["normal.png", "orm.png"]:
			assert_true(ResourceLoader.exists(str(m.index.tiers[tier]) + f), "%s tier: %s" % [tier, f])
	for f: String in ["albedo.png", "masks.png"]:
		assert_true(ResourceLoader.exists(str(m.index.tiers.web) + f), "web tier: %s" % f)
	m.free()


func test_the_landmarks_lie_near_the_animation_briefs() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := _model()
	var lm := m.landmarks()
	for k: String in ["shoulder_r", "elbow_r", "wrist_r", "palm_r", "shoulder_l", "elbow_l", "wrist_l", "palm_l",
			"hip_r", "knee_r", "ankle_r", "eye_mid"]:
		assert_true(lm.get(k) is Vector3, "landmark %s" % k)
	assert_true((lm.shoulder_r as Vector3).distance_to(BRIEF_SHOULDER_R) <= 0.02,
		"the right shoulder %s within 2 cm of the brief's %s" % [str(lm.shoulder_r), str(BRIEF_SHOULDER_R)])
	assert_near(float(lm.reach_r), BRIEF_REACH, 0.02, "the right arm's reach")
	assert_near(float(lm.reach_l), float(lm.reach_r), 0.001, "the arms are symmetric")
	assert_true((lm.palm_r as Vector3).z < (lm.shoulder_r as Vector3).z, "the palm is ahead of the shoulder (-Z front)")
	# the landmarks are the skeleton's joints in the model's frame
	var sk := m.skeleton()
	var at := m.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_rest(sk.find_bone("upperarm_r"))
	assert_true(at.origin.distance_to(lm.shoulder_r) < 0.001, "shoulder_r is upperarm_r's head (%s)" % str(at.origin))
	# P48 (plan M11 §2.2): the grips, their axes, the knuckles and the toes
	for side: String in ["r", "l"]:
		for k: String in ["grip_", "grip_axis_", "grip_local_", "knuckle_", "toe_"]:
			assert_true(lm.get(k + side) is Vector3, "landmark %s%s" % [k, side])
		var hand := sk.find_bone("hand_" + side)
		var hand_rest := m.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_rest(hand)
		assert_true((hand_rest * (lm["grip_local_" + side] as Vector3)).distance_to(lm["grip_" + side]) < 0.002,
			"grip_local_%s is grip_%s in the hand bone's space" % [side, side])
		assert_near((lm["grip_axis_" + side] as Vector3).length(), 1.0, 0.001, "grip_axis_%s is a unit vector" % side)
		# the handle's line runs from the little finger's side to the forefinger's
		var axis_model: Vector3 = hand_rest.basis * (lm["grip_axis_" + side] as Vector3)
		var across := (sk.get_bone_global_rest(sk.find_bone("index_01_" + side)).origin
			- sk.get_bone_global_rest(sk.find_bone("pinky_01_" + side)).origin)
		across = (m.global_transform.affine_inverse() * sk.global_transform).basis * across
		assert_true(axis_model.normalized().dot(across.normalized()) > 0.98, "grip_axis_%s follows the knuckle line" % side)
		assert_true((lm["grip_" + side] as Vector3).distance_to(lm["palm_" + side]) < 0.12, "the fist's centre is in the hand")
		assert_true((lm["toe_" + side] as Vector3).y < 0.08 and (lm["toe_" + side] as Vector3).z < (lm["ankle_" + side] as Vector3).z - 0.3,
			"toe_%s is on the ground ahead of the ankle" % side)
	m.free()


func test_the_import_settings_and_nothing_imported_under_tools() -> void:
	var glb := ConfigFile.new()
	assert_eq(glb.load(GLB + ".import"), OK, "giant.glb.import")
	assert_eq(str(glb.get_value("remap", "importer", "")), "scene", "imported as a scene")
	for key: String in ["meshes/generate_lods", "meshes/create_shadow_meshes", "meshes/ensure_tangents",
			"skins/use_named_skins"]:
		assert_eq(glb.get_value("params", key, false), true, "giant.glb: %s" % key)
	assert_eq(glb.get_value("params", "animation/import", true), false, "giant.glb: no animation import")
	# P48: a part is a scene with LODs, tangents and its named skin; its shadow is the proxy's
	for f in DirAccess.get_files_at("res://assets/giant/parts"):
		if not f.ends_with(".glb"):
			continue
		var part := ConfigFile.new()
		assert_eq(part.load("res://assets/giant/parts/%s.import" % f), OK, "parts/%s.import" % f)
		assert_eq(str(part.get_value("remap", "importer", "")), "scene", "parts/%s: imported as a scene" % f)
		for key: String in ["meshes/generate_lods", "meshes/ensure_tangents", "skins/use_named_skins"]:
			assert_eq(part.get_value("params", key, false), true, "parts/%s: %s" % [f, key])
		assert_eq(part.get_value("params", "meshes/create_shadow_meshes", true), false, "parts/%s: no shadow mesh" % f)
		assert_eq(part.get_value("params", "animation/import", true), false, "parts/%s: no animation import" % f)
	var arr := ConfigFile.new()
	assert_eq(arr.load(DESIGNS + ".import"), OK, "designs.png.import")
	assert_eq(str(arr.get_value("remap", "importer", "")), "2d_array_texture", "a 2D texture array")
	assert_eq(int(arr.get_value("params", "compress/mode", 0)), 2, "VRAM compressed")
	assert_eq(arr.get_value("params", "mipmaps/generate", false), true, "with mipmaps")
	var layers := Image.load_from_file(ProjectSettings.globalize_path(DESIGNS)).get_height() / 512
	assert_eq(int(arr.get_value("params", "slices/vertical", 0)), layers, "one slice per layer")
	for f: String in ["tex/albedo.png", "tex/normal.png", "tex/orm.png", "tex/masks.png", "tex_hi/normal.png",
			"tex_hi/orm.png", "hair_atlas.png", "cloth_weave.png", "cloth_leather.png", "cloth_fur.png"]:
		var c := ConfigFile.new()
		assert_eq(c.load("res://assets/giant/%s.import" % f), OK, "%s.import" % f)
		assert_eq(int(c.get_value("params", "compress/mode", 0)), 2, "%s: VRAM compressed" % f)
		assert_eq(c.get_value("params", "mipmaps/generate", false), true, "%s: mipmaps" % f)
		assert_eq(int(c.get_value("params", "compress/normal_map", -1)), 1 if f.ends_with("normal.png") else 0,
			"%s: a normal map only for the normal maps" % f)
	assert_eq(_imports_under("res://tools"), PackedStringArray(), "no .import file under tools/")


func _imports_under(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".import"):
			out.append(dir_path.path_join(f))
	for sub in d.get_directories():
		out.append_array(_imports_under(dir_path.path_join(sub)))
	return out


func test_the_fullest_look_shows_at_most_13_meshes() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := _model()
	var idx: Dictionary = m.index
	for outfit: Array in FULLEST:
		var shown := ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes", "Hair_long_back", "Beard_full"]
		for g: String in outfit:
			shown.append_array(idx.garments[g])
		var tris := 0
		for id: String in shown:
			tris += int(idx.meshes[id].tris)
		assert_true(shown.size() <= MAX_MESHES, "%s: %d meshes (draw calls at the low preset), at most %d" % [
			str(outfit), shown.size(), MAX_MESHES])
		assert_true(tris <= MAX_TRIANGLES, "%s: %d triangles at full detail, at most %d" % [str(outfit), tris, MAX_TRIANGLES])
	m.free()


## P54 (plan M11 §2.12, §3.7): the fullest slot look - in every slot its largest garment, the largest hair and beard,
## two bead sets (none before P56) and the largest accessory of each of the three accessory slots - draws at most 24
## meshes (draw calls at the low preset) and 70,000 triangles at full detail.
func test_the_fullest_slot_look_is_within_24_draw_calls_and_70000_primitives() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := _model()
	var idx: Dictionary = m.index
	var meshes := 4   # the body's three meshes and the eyes
	var tris := 0
	for id: String in ["Body_Head", "Body_Torso", "Body_Limbs", "Eyes"]:
		tris += int(idx.meshes[id].tris)
	var most := {}
	var count := {}
	for g: String in idx.garments:
		var slot := str(idx.meshes[(idx.garments[g] as Array)[0]].get("slot", ""))
		assert_true(slot in Appearance.SLOTS, "%s: its index entry names its slot (%s)" % [g, slot])
		var t := 0
		for mid: String in idx.garments[g]:
			t += int(idx.meshes[mid].tris)
		if t > int(most.get(slot, -1)):
			most[slot] = t
		count[slot] = maxi(int(count.get(slot, 0)), (idx.garments[g] as Array).size())
	assert_eq(most.size(), Appearance.SLOTS.size(), "a garment in each of the ten slots")
	for slot: String in most:
		tris += int(most[slot])
		meshes += int(count[slot])
	for cat: String in ["hair", "beard"]:
		var best := 0
		for id: String in idx.meshes:
			if str(idx.meshes[id].category) == cat:
				best = maxi(best, int(idx.meshes[id].tris))
		tris += best
		meshes += 1
	meshes += 2   # the bead sets' (P56)
	var acc := {}
	for id: String in idx.meshes:
		if str(idx.meshes[id].category) == "accessory":
			var slot := str(idx.meshes[id].slot)
			acc[slot] = maxi(int(acc.get(slot, 0)), int(idx.meshes[id].tris))
	assert_eq(acc.size(), 3, "an accessory in each of the three accessory slots")
	for slot: String in acc:
		tris += int(acc[slot])
		meshes += 1
	print("    the fullest slot look: %d meshes, %d triangles" % [meshes, tris])
	assert_true(meshes <= 24, "the fullest slot look: %d meshes (draw calls at low), at most 24" % meshes)
	assert_true(tris <= 70000, "the fullest slot look: %d triangles at full detail, at most 70,000" % tris)
	m.free()


## P54 (plan M11 §2.6): a head garment hides every hair style ("all") or cuts each by length as its index entry's
## hair_cut says ("top": 0 hides it); every outfit of the data is a valid record and every garment of the data has
## its index garment.
func test_a_helm_hides_or_cuts_each_hair_style_and_every_outfit_is_valid() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := _model()
	var idx: Dictionary = m.index
	var styles := GiantLook.meshes_of(idx, "hair")
	var helms := 0
	for g: String in idx.garments:
		var mid: String = (idx.garments[g] as Array)[0]
		var e: Dictionary = idx.meshes[mid]
		if str(e.get("slot", "")) != "head":
			continue
		helms += 1
		var cut := GiantLook.hair_cut(idx, [mid])
		for style: String in styles:
			var want := 0.0 if str(e.hides_hair) == "all" else float((e.get("hair_cut", {}) as Dictionary).get(style, 1.0))
			assert_true(is_equal_approx(float(cut.get(style, 1.0)), want), "%s over %s: %.2f of its length" % [g, style, want])
		# the look applied: the default long hair drawn or not under it (a look a helm, so the parts load once)
		var look := GiantLook.DEFAULT_LOOK.duplicate(true)
		look.garments = [{"mesh": g, "dye": Color.GRAY, "kind": str(e.get("material", "cloth"))}]
		GiantLook.apply(m, idx, look)
		var hair := str(look.hair_mesh)
		assert_eq(GiantLook.mesh_node(m, idx, hair).visible, float(cut.get(hair, 1.0)) > 0.0, "%s over %s: drawn or not" % [g, hair])
	assert_eq(helms, 4, "the hood, the leather cap, the iron helm and the horned helm")
	for id: String in Appearance.option_ids("outfit"):
		var r := Appearance.with_outfit(Appearance.default_record(), id)
		assert_true(Appearance.is_valid(r), "%s: a valid record" % id)
	for id: String in Appearance.option_ids("garment"):
		assert_true(idx.garments.has(str(Appearance.option(id).mesh)), "%s: its index garment" % id)
	for id: String in Appearance.option_ids("accessory"):
		assert_true(idx.meshes.has(str(Appearance.option(id).mesh)), "%s: its index mesh" % id)
	m.free()


func test_hand_transform_follows_the_hand_bone() -> void:
	if not ResourceLoader.exists(MODEL):
		fail("no giant_model.tscn")
		return
	var m := _model()
	var sk := m.skeleton()
	var hand := sk.find_bone("hand_r")
	var rest := m.hand_transform(true)
	assert_true(rest.origin.distance_to(sk.global_transform * sk.get_bone_global_rest(hand).origin) < 0.001,
		"at rest: the hand bone's head")
	assert_true(rest.origin.x > 0.5 and rest.origin.y > 1.8 and rest.origin.y < 2.6,
		"the right hand hangs at the giant's right (%s)" % str(rest.origin))
	m.pose_relaxed()
	var relaxed := m.hand_transform(true)
	assert_true(relaxed.origin.distance_to(rest.origin) > 0.15, "pose_relaxed() brings the hand in (%.2f m)" % relaxed.origin.distance_to(rest.origin))
	assert_true(relaxed.origin.x < rest.origin.x, "toward the body")
	assert_true(relaxed.origin.distance_to(sk.global_transform * sk.get_bone_global_pose(hand).origin) < 0.001,
		"hand_transform() is the posed hand bone")
	assert_true(m.hand_transform(false).origin.x < 0.0, "the left hand at the giant's left")
	m.pose_rest()
	assert_true(m.hand_transform(true).origin.distance_to(rest.origin) < 0.001, "pose_rest() puts it back")
	m.free()
