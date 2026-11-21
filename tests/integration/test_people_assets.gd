extends TestSuite
## P59 (plan M11 §3.12, tests): the generated people as Godot imports them, with nothing in the game using them yet.
## Reads the committed sources (the glTFs, the maps, the manifest), never .godot/imported (plan §2.13):
##   * every role's scene loads: one skinned mesh a variant with one surface, at most 5,000 triangles, on a
##     skeleton of the 23 bones by name; the five crowd-pose meshes (at most 600) and the far mesh (at most 150)
##     static; the importer's LODs on the variants;
##   * a soldier's model loads and the people's clips (an AnimationLibrary) drive its skeleton's bones by name;
##   * the three maps of every role load; the gear's pieces;
##   * the import settings (the LODs, named skins, the exported tangents; the ORM map lossless so the palette band
##     decodes exactly).
## That nothing in the game names assets/people yet is tools/giant/test_people_tools.py's (a text scan).

const DIR := "res://assets/people/"
const MANIFEST := "res://assets/people/manifest.json"
const BONES := ["Root", "pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "head",
	"clavicle_l", "upperarm_l", "lowerarm_l", "hand_l", "thigh_l", "calf_l", "foot_l", "ball_l",
	"clavicle_r", "upperarm_r", "lowerarm_r", "hand_r", "thigh_r", "calf_r", "foot_r", "ball_r"]
const ROLES := ["soldier", "archer", "mage", "crew", "villager", "elder", "notable", "rider"]
const CLIPS := ["idle", "walk", "run", "flee", "brace", "cower", "seated", "held", "tumble", "death", "grip_r", "grip_l"]


func _index() -> Dictionary:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert_true(doc is Dictionary, "the people's manifest parses")
	return (doc as Dictionary).get("index", {}) if doc is Dictionary else {}


func _meshes(n: Node, out: Dictionary) -> void:
	_meshes_of(n, out)


static func _meshes_of(n: Node, out: Dictionary) -> void:
	if n is MeshInstance3D:
		out[str(n.name)] = n
	for c in n.get_children():
		_meshes_of(c, out)


static func _tris_of(mesh: Mesh) -> int:
	var arr := mesh.surface_get_arrays(0)
	var idx: Variant = arr[Mesh.ARRAY_INDEX]
	return (idx as PackedInt32Array).size() / 3 if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3


func test_the_index_and_the_soldier_with_its_variants_poses_and_far_mesh() -> void:
	var index := _index()
	assert_eq(index.get("role_order", []), ROLES, "P59's six roles and P59b's notable and rider")
	assert_eq(index.get("bones", []), BONES, "the 23 bones")
	for role: String in ROLES:
		assert_true(ResourceLoader.exists(str(index.roles[role].scene)), "%s's scene" % role)
	check_roles(self, index, ["soldier"])


## Every check of a role's scene (tests/slow/test_people_roles.gd runs it on every role).
static func check_roles(t: TestSuite, index: Dictionary, roles: Array) -> void:
	for role: String in roles:
		var entry: Dictionary = index.roles[role]
		t.assert_eq(str(entry.scene), DIR + role + ".glb", "%s's scene" % role)
		var inst := (load(entry.scene) as PackedScene).instantiate()
		t.add_child(inst)
		var ms := {}
		_meshes_of(inst, ms)
		for v: String in entry.variants:
			t.assert_true(ms.has(v), "%s: the variant %s" % [role, v])
			if not ms.has(v):
				continue
			var mi: MeshInstance3D = ms[v]
			t.assert_eq(mi.mesh.get_surface_count(), 1, "%s: one surface" % v)
			t.assert_true(_tris_of(mi.mesh) <= 5000, "%s: at most 5,000 triangles" % v)
			t.assert_true(mi.skin != null, "%s is skinned" % v)
			var sk := mi.get_node_or_null(mi.skeleton) as Skeleton3D
			t.assert_true(sk != null, "%s: its skeleton" % v)
			if sk != null:
				var names: Array = []
				for b in sk.get_bone_count():
					names.append(sk.get_bone_name(b))
				names.sort()
				var want := BONES.duplicate()
				want.sort()
				t.assert_eq(names, want, "%s: the 23 bones by name" % v)
			t.assert_true(mi.mesh is ArrayMesh and (mi.mesh as ArrayMesh).surface_get_format(0) & Mesh.ARRAY_FORMAT_TANGENT,
				"%s carries tangents" % v)
		for pose: String in entry.poses:
			var node := str(entry.poses[pose])
			t.assert_true(ms.has(node), "%s: the %s crowd pose" % [role, pose])
			if ms.has(node):
				var pm: MeshInstance3D = ms[node]
				t.assert_true(pm.skin == null, "%s is static" % node)
				t.assert_true(_tris_of(pm.mesh) <= 600, "%s: at most 600 triangles" % node)
		t.assert_true(ms.has(str(entry.far)) and _tris_of((ms[str(entry.far)] as MeshInstance3D).mesh) <= 150,
			"%s: the far mesh, at most 150 triangles" % role)
		for k: String in ["albedo", "normal", "orm"]:
			t.assert_true(load(str(entry[k])) is Texture2D, "%s's %s map" % [role, k])
		inst.queue_free()


func test_a_soldier_loads_and_the_clips_drive_its_bones() -> void:
	var lib := load(DIR + "people_clips.glb") as AnimationLibrary
	assert_true(lib != null, "people_clips.glb is an AnimationLibrary")
	if lib == null:
		return
	var names: Array = []
	for n in lib.get_animation_list():
		names.append(str(n))
	names.sort()
	var want := CLIPS.duplicate()
	want.sort()
	assert_eq(names, want, "the people's clips")
	var soldier := (load(DIR + "soldier.glb") as PackedScene).instantiate()
	add_child(soldier)
	var ms := {}
	_meshes(soldier, ms)
	var sk := (ms["soldier_a"] as MeshInstance3D).get_node((ms["soldier_a"] as MeshInstance3D).skeleton) as Skeleton3D
	var walk := lib.get_animation("walk")
	var bones := {}
	for t in walk.get_track_count():
		var path := str(walk.track_get_path(t))
		bones[path.get_slice(":", 1)] = true
	for b: String in BONES:
		if b != "Root":       # (never moves: the importer drops an immutable track)
			assert_true(bones.has(b), "the walk keys %s" % b)
		assert_true(sk.find_bone(b) >= 0, "the soldier's skeleton has %s" % b)
	# a grip keys its hand only in the glTF (test_people_tools.py); the importer adds a one-key track for the other
	# bones, as it does for the giant's grips
	var grip := lib.get_animation("grip_r")
	var hand := -1
	for t in grip.get_track_count():
		if str(grip.track_get_path(t)).get_slice(":", 1) == "hand_r" and grip.track_get_type(t) == Animation.TYPE_ROTATION_3D:
			hand = t
	assert_true(hand >= 0, "grip_r turns the right hand")
	assert_true(grip.length < 0.05, "a one-frame grip")
	soldier.queue_free()


func test_the_gear() -> void:
	var gear := (load(DIR + "gear.glb") as PackedScene).instantiate()
	add_child(gear)
	var ms := {}
	_meshes(gear, ms)
	for g: String in ["sword", "spear", "shield", "banner", "bow", "quiver", "staff", "hammer"]:
		assert_true(ms.has("gear_" + g), "gear.glb has the %s" % g)
	gear.queue_free()


func test_the_import_settings() -> void:
	for role: String in ROLES:
		var text := FileAccess.get_file_as_string(DIR + role + ".glb.import")
		for kv: String in ["meshes/generate_lods=true", "meshes/create_shadow_meshes=true", "skins/use_named_skins=true",
				"meshes/ensure_tangents=false", "animation/import=false"]:
			assert_true(text.contains(kv + "\n"), "%s.glb: %s" % [role, kv])
		var orm := FileAccess.get_file_as_string(DIR + role + "_orm.png.import")
		assert_true(orm.contains("compress/mode=0\n"), "%s's ORM map is lossless (the band decodes exactly)" % role)
		var nrm := FileAccess.get_file_as_string(DIR + role + "_normal.png.import")
		assert_true(nrm.contains("compress/normal_map=1\n"), "%s's normal map is imported as one" % role)
	var clips := FileAccess.get_file_as_string(DIR + "people_clips.glb.import")
	assert_true(clips.contains('importer="animation_library"'), "the clips import as an AnimationLibrary")
