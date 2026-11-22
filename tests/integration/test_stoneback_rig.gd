extends TestSuite
## A1: Stoneback, the quarry titan, as the asset pipeline made him (tools/giant/kit/stoneback.py) and StonebackRig
## shows him (no actor, no fight yet). Reads the committed glTFs and maps and the creatures' manifest:
##   * the index entry and the files load; the body, eight stone plates (each its own MeshInstance3D), the shackles,
##     the club and the boulder are skinned on the one 23-bone skeleton; he is 16.8 m (55 ft) within 2 %;
##   * each plate hides alone (the weak points' four among them) and the body stays; all hide and show again;
##   * the clips: idle, walk, run, roar and the three wind-ups; a wind-up moves the hands; the throw shows the boulder;
##   * the plates and the boulder take the stone shader, the club the same shader on the bark;
##   * sheet D's pages are described (ids, sections, the line-up, the plates' states and the walk's two phases, A1b),
##     without rendering.

const DIR := "res://assets/creatures/"
const PLATES := ["plate_shoulder_l", "plate_shoulder_r", "plate_back", "plate_brow", "plate_forearm_l",
	"plate_forearm_r", "plate_shin_l", "plate_shin_r"]
const CLIPS := ["idle", "walk", "run", "roar", "overhead", "charge", "throw"]


func _rig() -> StonebackRig:
	var rig := StonebackRig.new()
	add_child(rig)
	return rig


func test_the_asset_is_in_the_index_and_loads() -> void:
	var e := StonebackRig.entry()
	assert_false(e.is_empty(), "the creatures' index has stoneback")
	for key: String in ["scene", "clips", "albedo", "normal", "orm", "stone_albedo", "stone_normal", "bark_albedo",
			"bark_normal"]:
		assert_true(ResourceLoader.exists(str(e.get(key, ""))), "%s: %s loads" % [key, e.get(key, "")])
	assert_eq(Array(e.get("plates", [])), PLATES, "the eight plates in order")
	assert_eq((e.get("weak_points", {}) as Dictionary).keys().size(), 4, "four weak points under plates")


func test_every_plate_is_its_own_mesh_and_hides_alone() -> void:
	var rig := _rig()
	assert_true(rig.body != null and rig.skeleton != null, "the body on its skeleton")
	assert_eq(rig.skeleton.get_bone_count(), 23, "the people's 23 bones")
	var names := Array(rig.plate_names())
	names.sort()
	var want := PLATES.duplicate()
	want.sort()
	assert_eq(names, want, "the plates found as nodes")
	var meshes := {}
	for n: String in PLATES:
		var mi := rig.piece(n)
		assert_true(mi != null and mi.skin != null and mi.get_node_or_null(mi.skeleton) == rig.skeleton,
			"%s: skinned on the skeleton" % n)
		meshes[mi] = true
	assert_eq(meshes.size(), PLATES.size(), "eight distinct meshes")
	for n: String in PLATES:
		rig.set_plates(true)
		rig.set_plate_visible(n, false)
		for m: String in PLATES:
			assert_eq(rig.plate_visible(m), m != n, "%s hidden: %s shown is %s" % [n, m, m != n])
		assert_true(rig.body.visible, "the body stays with %s hidden" % n)
	rig.set_plates(false)
	for m: String in PLATES:
		assert_false(rig.plate_visible(m), "all off: %s" % m)
	rig.set_plates(true)
	for m: String in PLATES:
		assert_true(rig.plate_visible(m), "all on: %s" % m)
	for n: String in ["shackles", "club", "boulder"]:
		assert_true(rig.piece(n) != null, "the %s" % n)
	rig.queue_free()


func test_he_is_55_feet_tall() -> void:
	var rig := _rig()
	var aabb := rig.body.mesh.get_aabb()
	var h := aabb.end.y - minf(0.0, aabb.position.y)
	assert_true(absf(h - 16.8) <= 16.8 * 0.02, "the body is %.2f m (16.8 m within 2 %%)" % h)
	var head := rig.bone_position("head")
	assert_true(head.y > 13.5 and head.y < 16.8, "the head's joint at %.2f m" % head.y)
	rig.queue_free()


func test_the_clips_and_the_wind_ups() -> void:
	var rig := _rig()
	var have := Array(rig.clips())
	for c: String in CLIPS:
		assert_true(c in have, "the %s clip" % c)
	rig.pose("idle", 0.0)
	var idle_r := rig.bone_position("hand_r")
	var idle_l := rig.bone_position("hand_l")
	var head := rig.bone_position("head")
	assert_false(rig.piece("boulder").visible, "no boulder in the idle")
	rig.pose_windup("overhead")
	assert_true(rig.bone_position("hand_r").y > head.y and rig.bone_position("hand_l").y > head.y,
		"the overhead: both fists over the head")
	assert_true(rig.bone_position("hand_r").distance_to(rig.bone_position("hand_l")) < 3.0, "both hands on the trunk")
	rig.pose_windup("throw")
	assert_true(rig.piece("boulder").visible, "the throw shows the boulder")
	assert_true(rig.bone_position("hand_l").y > idle_l.y + 5.0, "the boulder's hand drawn up")
	rig.pose_windup("charge")
	assert_true(rig.bone_position("head").y < head.y - 0.5, "the charge leans in")
	rig.pose("idle", 0.0)
	assert_true(rig.bone_position("hand_r").distance_to(idle_r) < 0.01, "back to the idle")
	rig.queue_free()


func test_the_materials() -> void:
	var rig := _rig()
	for n: String in PLATES + ["boulder", "club"]:
		var m := rig.piece(n).material_override as ShaderMaterial
		assert_true(m != null and m.shader.resource_path == StonebackRig.STONE_SHADER, "%s: the stone shader" % n)
	assert_true(rig.piece("club").material_override == rig.bark_material, "the club on the bark")
	assert_true(rig.body.material_override == rig.body_material and rig.piece("shackles").material_override == rig.body_material,
		"the body and the shackles on his atlas")
	rig.queue_free()


func test_sheet_d_is_described() -> void:
	var sheet: Node = load("res://tools/character_sheet.gd").new()
	sheet.set("sheet", "d")
	var pages: Array = sheet.call("pages")
	PersonRig.reset_for_tests()
	var ids := pages.map(func(p: Dictionary) -> String: return str(p.id))
	assert_eq(ids, ["d1", "d2", "d3", "d4"], "the four pages (A2: d4, his strikes)")
	var tiles := 0
	var lineup := false
	var hidden := {}
	var walk_phases := {}
	for p: Dictionary in pages:
		for s: Dictionary in p.sections:
			for t: Dictionary in s.tiles:
				tiles += 1
				assert_true(t.has("titan"), "every tile is Stoneback's")
				lineup = lineup or bool(t.get("lineup", false))
				hidden[str(t.get("hidden", []))] = true
				if str(t.get("clip", "")) == "walk":
					walk_phases[float(t.get("phase", -1.0))] = str(t.view)
	assert_true(tiles >= 30, "%d tiles" % tiles)
	assert_true(lineup, "the line-up")
	assert_true(hidden.size() >= 5, "the plates' five states")
	assert_eq(walk_phases.size(), 2, "A1b: the walk at two phases")
	assert_true(walk_phases.values().all(func(v: String) -> bool: return v == "side"), "the walk from the side")
	sheet.free()
