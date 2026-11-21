extends TestSuite
## P61 (plan M11 §3.14, tests): the generated horse as Godot imports it, with nothing in the game using it yet (P62's
## SkinnedQuadrupedRig is the first). Reads the committed sources (the glTFs, the maps, the manifest), never
## .godot/imported (plan §2.13):
##   * horse.glb loads: the bare horse and the tacked horse, each one skinned mesh with one surface of at most 6,000
##     triangles, on one skeleton of the 25 bones by name, with tangents;
##   * horse_poses.glb is an AnimationLibrary of the gait's extremes, each turning the legs' bones;
##   * the three maps load (the albedo with the strands' alpha); the import settings (the ORM map lossless so the
##     palette band decodes exactly, the named skins, the exported tangents).
## The mesh's closedness, its weights and the poses' volumes are tools/giant/test_people_tools.py's (TestHorse).

const DIR := "res://assets/creatures/"
const MANIFEST := "res://assets/creatures/manifest.json"
const BONES := ["Root", "pelvis", "spine_01", "spine_02", "neck", "head", "jaw", "tail_01", "tail_02",
	"fore_upper_l", "fore_lower_l", "fore_cannon_l", "fore_foot_l", "fore_upper_r", "fore_lower_r", "fore_cannon_r",
	"fore_foot_r", "hind_upper_l", "hind_lower_l", "hind_cannon_l", "hind_foot_l", "hind_upper_r", "hind_lower_r",
	"hind_cannon_r", "hind_foot_r"]
const POSES := ["stand", "trot_reach_left", "trot_reach_right", "gallop_extended", "gallop_gathered"]


func _index() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(doc is Dictionary, "the creatures' manifest parses")
	return (doc as Dictionary).get("index", {}) if doc is Dictionary else {}


static func _meshes_of(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D:
		out[str(n.name)] = n
	for c in n.get_children():
		_meshes_of(c, out)


static func _tris_of(mesh: Mesh) -> int:
	var arr := mesh.surface_get_arrays(0)
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	return (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func test_the_horse_bare_and_tacked_on_its_25_bones() -> void:
	var index := _index()
	var horse: Dictionary = index.get("horse", {})
	assert_eq(horse.get("bones", []), BONES, "the 25 bones in the index")
	assert_eq(str(horse.get("scene", "")), DIR + "horse.glb", "the horse's scene")
	var inst := (load(DIR + "horse.glb") as PackedScene).instantiate()
	add_child(inst)
	var ms := {}
	_meshes_of(inst, ms)
	var skeletons := {}
	for key: String in ["bare", "tacked"]:
		var name := str(horse.meshes[key])
		assert_true(ms.has(name), "the %s horse's mesh %s" % [key, name])
		if not ms.has(name):
			continue
		var mi: MeshInstance3D = ms[name]
		assert_eq(mi.mesh.get_surface_count(), 1, "%s: one surface (one draw call)" % name)
		var tris := _tris_of(mi.mesh)
		assert_true(tris <= 6000 and tris > 4000, "%s: %d triangles, at most 6,000" % [name, tris])
		assert_true(mi.skin != null, "%s is skinned" % name)
		assert_true((mi.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TANGENT, "%s carries tangents" % name)
		var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		assert_true(sk != null, "%s: its skeleton" % name)
		if sk == null:
			continue
		skeletons[sk] = true
		var names: Array = []
		for b in sk.get_bone_count():
			names.append(sk.get_bone_name(b))
		names.sort()
		var want := BONES.duplicate()
		want.sort()
		assert_eq(names, want, "%s: the 25 bones by name" % name)
		# the hooves stand on the ground, the withers about 1.6 m up (the glTF faces +Z, y up)
		var aabb := mi.get_aabb()
		assert_true(absf(aabb.position.y) < 0.01, "%s stands on the ground (%.3f)" % [name, aabb.position.y])
		assert_true(aabb.size.z > 2.2 and aabb.size.z < 2.8, "%s: %.2f m nose to tail" % [name, aabb.size.z])
	assert_eq(skeletons.size(), 1, "both meshes on one skeleton")
	var seat: Dictionary = horse.landmarks.saddle_seat
	assert_eq(str(seat.bone), "spine_01", "the saddle's seat rides the back")
	assert_true(float(seat.position[1]) > 1.5 and float(seat.position[1]) < 1.75, "the seat about 1.6 m up")
	inst.queue_free()


func test_the_gaits_extremes_and_the_maps() -> void:
	var lib := load(DIR + "horse_poses.glb") as AnimationLibrary
	assert_true(lib != null, "horse_poses.glb is an AnimationLibrary")
	if lib == null:
		return
	var names: Array = []
	for n in lib.get_animation_list():
		names.append(str(n))
	names.sort()
	var want := POSES.duplicate()
	want.sort()
	assert_eq(names, want, "the gait's extremes")
	var trot := lib.get_animation("trot_reach_left")
	var keyed := {}
	for t in trot.get_track_count():
		keyed[str(trot.track_get_path(t)).get_slice(":", 1)] = true
	for b: String in ["fore_upper_l", "fore_cannon_r", "hind_upper_r", "hind_cannon_l"]:
		assert_true(keyed.has(b), "the trot's extreme turns %s" % b)
	var albedo := load(DIR + "horse_albedo.png") as Texture2D
	assert_true(albedo != null and albedo.get_width() == 512, "the albedo, 512 px")
	assert_true(albedo != null and albedo.get_image().detect_alpha() != Image.ALPHA_NONE,
		"the albedo carries the strands' alpha (the mane and the tail)")
	for k: String in ["normal", "orm"]:
		var tex := load(DIR + "horse_%s.png" % k) as Texture2D
		assert_true(tex != null and tex.get_width() == 256, "the %s map, 256 px" % k)


func test_the_import_settings() -> void:
	var text := FileAccess.get_file_as_string(DIR + "horse.glb.import")
	for kv: String in ["meshes/generate_lods=true", "meshes/create_shadow_meshes=true", "skins/use_named_skins=true",
			"meshes/ensure_tangents=false", "animation/import=false"]:
		assert_true(text.contains(kv + "\n"), "horse.glb: %s" % kv)
	assert_true(FileAccess.get_file_as_string(DIR + "horse_orm.png.import").contains("compress/mode=0\n"),
		"the ORM map is lossless (the band decodes exactly)")
	assert_true(FileAccess.get_file_as_string(DIR + "horse_normal.png.import").contains("compress/normal_map=1\n"),
		"the normal map is imported as one")
	assert_true(FileAccess.get_file_as_string(DIR + "horse_poses.glb.import").contains('importer="animation_library"'),
		"the poses import as an AnimationLibrary")


## P61 (plan §3.14 tests): the rival giants' looks are valid, name the giant's new parts, and are hidden from the
## creator (the preset list, the option rows, Randomize's pool); option() and preset_record() still find them.
func test_the_rival_giants_looks_are_valid_and_hidden_from_the_creator() -> void:
	var npc := ["appearance_preset.npc_rival_giant", "appearance_preset.npc_harrok"]
	for pid: String in npc:
		var rec := GameData.get_record(pid)
		assert_true(Appearance.is_npc(rec), "%s is an npc look" % pid)
		assert_false(Appearance.preset_ids().has(pid), "%s is not offered" % pid)
		var look := Appearance.preset_record(pid)
		assert_true(Appearance.is_valid(look), "%s is a valid record" % pid)
		var s := Appearance.sanitize(look, "")
		assert_eq((s.dropped as PackedStringArray).size(), 0, "%s: nothing dropped" % pid)
		assert_eq(str(look.outfit.slots.shoulders.item), "garment.hide_mantle", "%s wears the hide mantle" % pid)
		assert_eq(str(look.outfit.slots.armour.item), "garment.war_harness", "%s wears the war harness" % pid)
		assert_eq(str(look.beard.beads), "bead.iron_rings", "%s's beard is ringed in iron" % pid)
	for id: String in ["garment.hide_mantle", "garment.war_harness", "bead.iron_rings"]:
		var cat := id.get_slice(".", 0)
		assert_false(Appearance.option(id).is_empty(), "%s is found by id" % id)
		assert_false(Appearance.option_ids(cat).has(id), "%s is not among the creator's ids" % id)
		var shown := false
		for o: Dictionary in Appearance.options(cat, ""):
			shown = shown or str(o.id) == id
		assert_false(shown, "%s is not in the creator's rows" % id)
		assert_false(Appearance._unlocked(cat, "").has(id), "%s is not in Randomize's pool" % id)
	var idx: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/giant/manifest.json"))
	var meshes: Dictionary = (idx as Dictionary).index.meshes
	for m: String in ["Garment_hide_mantle", "Garment_war_harness", "Beads_iron"]:
		assert_true(meshes.has(m), "the giant's index has %s" % m)
		assert_true(ResourceLoader.exists(str(meshes[m].get("part_path", "res://assets/giant/parts/%s.glb" % m))), "%s's part" % m)


## P63 (plan §3.16 tests): the brutes and the wolf as Godot imports them. Each brute's scene: its variants (the ogre;
## the troll and the whelp) skinned on the people's 23 bones, the bosses' gear on the same skeleton, a far mesh each;
## its clips an AnimationLibrary; the wolf on the 25 bones with its shell's mesh, its far mesh, its poses and its fur
## map. The reach bands, the bands and the weights are tools/giant/test_people_tools.py's (TestBrutes, TestWolf).
const PEOPLE_BONES := ["Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r"]
const BRUTES := {"ogre": ["ogre", "ogre_far", "ogre_king_gear"], "troll": ["troll", "whelp", "troll_far", "whelp_far",
	"troll_matriarch_gear"]}
const BRUTE_CLIPS := ["brace", "death", "grip_l", "grip_r", "idle", "roar", "run", "slam", "walk"]


static func _bone_names(sk: Skeleton3D) -> Array:
	var names: Array = []
	for b in sk.get_bone_count():
		names.append(sk.get_bone_name(b))
	names.sort()
	return names


func test_the_brutes_and_the_wolf() -> void:
	var index := _index()
	var pb := PEOPLE_BONES.duplicate()
	pb.sort()
	for kind: String in BRUTES:
		assert_true(index.has(kind), "the index has the %s" % kind)
		var inst := (load(DIR + kind + ".glb") as PackedScene).instantiate()
		add_child(inst)
		var ms := {}
		_meshes_of(inst, ms)
		for name: String in BRUTES[kind]:
			assert_true(ms.has(name), "%s.glb has %s" % [kind, name])
			if not ms.has(name):
				continue
			var mi: MeshInstance3D = ms[name]
			assert_eq(mi.mesh.get_surface_count(), 1, "%s: one surface" % name)
			if name.ends_with("_far"):
				assert_true(_tris_of(mi.mesh) <= 300, "%s: a far mesh" % name)
				continue
			assert_true(mi.skin != null, "%s is skinned" % name)
			var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			assert_true(sk != null and _bone_names(sk) == pb, "%s: the 23 bones" % name)
		inst.queue_free()
		var lib := load(DIR + kind + "_clips.glb") as AnimationLibrary
		assert_true(lib != null, "%s_clips.glb is an AnimationLibrary" % kind)
		if lib != null:
			var names: Array = []
			for n in lib.get_animation_list():
				names.append(str(n))
			names.sort()
			assert_eq(names, BRUTE_CLIPS, "the %s's clips" % kind)
		assert_true(FileAccess.get_file_as_string(DIR + kind + "_orm.png.import").contains("compress/mode=0\n"),
			"%s: the ORM map is lossless" % kind)
	var wolf := (load(DIR + "wolf.glb") as PackedScene).instantiate()
	add_child(wolf)
	var wm := {}
	_meshes_of(wolf, wm)
	var hb := BONES.duplicate()
	hb.sort()
	for name: String in ["wolf", "wolf_shell"]:
		assert_true(wm.has(name), "wolf.glb has %s" % name)
		if wm.has(name):
			var mi: MeshInstance3D = wm[name]
			assert_true(_tris_of(mi.mesh) <= 6000, "%s within 6,000 triangles" % name)
			var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			assert_true(sk != null and _bone_names(sk) == hb, "%s: the 25 bones" % name)
	assert_true(wm.has("wolf_far"), "wolf.glb has its far mesh")
	wolf.queue_free()
	assert_true(load(DIR + "wolf_poses.glb") is AnimationLibrary, "the wolf's poses")
	var fur := load(DIR + "wolf_fur.png") as Texture2D
	assert_true(fur != null and fur.get_width() == 256, "the fur shell's map, 256 px")
