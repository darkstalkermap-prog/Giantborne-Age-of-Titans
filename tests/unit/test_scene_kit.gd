extends TestSuite
## SceneKit and the builder runner (plan §2.12, §3.4): the layer constants, --only selection,
## builders writing into a redirected folder, every node of a generated scene carrying its stable
## unique_id (P49: made from the scene's and the node's path, so an export's conversion is the
## same in every checkout; up to 0.10.0-m10 the ids were stripped), and byte-identical regeneration.

const BUILD_SCENES := "res://tools/build_scenes.gd"
const OUT := "user://test_scene_kit"


func _runner() -> GDScript:
	return load(BUILD_SCENES) as GDScript


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_as_text() if f != null else ""


func _rm_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_rm_tree(path.path_join(sub))
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


func after_each() -> void:
	_rm_tree(OUT)


func test_layer_constants() -> void:
	assert_eq(SceneKit.L_WORLD, 1, "world")
	assert_eq(SceneKit.L_ACTORS, 2, "actors")
	assert_eq(SceneKit.L_HURTBOX, 4, "hurtboxes")
	assert_eq(SceneKit.L_DEBRIS, 8, "debris")
	assert_eq(SceneKit.L_BREAKABLE, 16, "breakables")
	assert_eq(SceneKit.L_BLOCKER, 32, "blockers (physics layer 6)")
	assert_eq(SceneKit.ACTOR_MASK, 51, "ACTOR_MASK = world | actors | breakables | blockers")
	assert_eq(SceneKit.FP_HIDDEN, 2, "first-person hidden render layer")
	assert_eq(SceneKit.L_BLOCKER, EnemyActor.LAYER_BLOCKER, "the enemy code agrees on the blocker layer")
	assert_eq(HitQueryAdapter.OCCLUDER_MASK & SceneKit.L_BLOCKER, 0, "attack occluders ignore blockers")
	assert_eq(EnemyActor.SIGHT_MASK, SceneKit.L_WORLD | SceneKit.L_BREAKABLE, "enemy sight: world and breakables")


func test_only_selection() -> void:
	var r := _runner()
	var builders: Array = r.get("BUILDERS")
	assert_eq(r.call("parse_only", PackedStringArray(["--only=wolf"])), PackedStringArray(["wolf"]), "one name")
	assert_eq(r.call("parse_only", PackedStringArray(["--slow", "--only=wolf, sandbox,wolf.gd"])),
		PackedStringArray(["wolf", "sandbox"]), "a list; spaces, .gd and repeats are tolerated")
	assert_eq(r.call("parse_only", PackedStringArray([])), PackedStringArray(), "absent")
	var all: Dictionary = r.call("select", builders, PackedStringArray())
	assert_true(all.ok and (all.paths as Array).size() == builders.size(), "no --only: every builder")
	var one: Dictionary = r.call("select", builders, PackedStringArray(["wolf"]))
	assert_eq(one.paths, ["res://tools/builders/wolf.gd"], "--only=wolf runs the wolf builder only")
	var two: Dictionary = r.call("select", builders, PackedStringArray(["main", "player"]))
	assert_eq(two.paths, ["res://tools/builders/player.gd", "res://tools/builders/main.gd"],
		"selected builders keep the BUILDERS order")
	var bad: Dictionary = r.call("select", builders, PackedStringArray(["wolf", "nope"]))
	assert_false(bad.ok, "an unknown builder is an error")
	assert_true(str(bad.error).contains("nope"), "naming it")


func test_builders_list_covers_every_builder_file() -> void:
	var builders: Array = _runner().get("BUILDERS")
	var names := PackedStringArray()
	for path: String in builders:
		names.append(_runner().call("builder_name", path))
	for expected in ["player", "soldier", "wolf", "props", "shrine", "growth_course", "test_levels",
			"world_props", "ranged", "test_director", "forge", "heavy", "npcs", "sandbox", "valley",
			"stress", "main"]:
		assert_true(names.has(expected), "BUILDERS declares %s" % expected)
	assert_true(names.find("player") < names.find("sandbox") and names.find("wolf") < names.find("sandbox")
		and names.find("props") < names.find("sandbox") and names.find("sandbox") < names.find("main"),
		"builders run before the scenes that instance their output")
	var d := DirAccess.open("res://tools/builders")
	for f in d.get_files():
		if f.ends_with(".gd"):
			assert_true(builders.has("res://tools/builders/" + f), "%s is in BUILDERS" % f)


func test_strip_unique_ids() -> void:
	var kit := SceneKit.new(OUT)
	var text := "[node name=\"A\" type=\"Node3D\" unique_id=1234567]\n[node name=\"B\" type=\"Node3D\" parent=\".\" unique_id=-42]\n"
	assert_eq(kit.strip_unique_ids(text), "[node name=\"A\" type=\"Node3D\"]\n[node name=\"B\" type=\"Node3D\" parent=\".\"]\n",
		"every node unique_id attribute is removed")


## P49: [node path, id] of every node line of a scene's text, read here on its own (not with the kit's
## code): the name and parent attributes give the path, unique_id the id (0 when the line has none).
static func _node_ids(text: String) -> Array:
	var out: Array = []
	var name_re := RegEx.create_from_string("^\\[node name=\"([^\"]*)\"")
	var parent_re := RegEx.create_from_string(" parent=\"([^\"]*)\"")
	var id_re := RegEx.create_from_string(" unique_id=(-?[0-9]+)")
	for line in text.split("\n"):
		var m := name_re.search(line)
		if m == null:
			continue
		var pm := parent_re.search(line)
		var node_path := "." if pm == null else (m.get_string(1) if pm.get_string(1) == "." else pm.get_string(1) + "/" + m.get_string(1))
		var im := id_re.search(line)
		out.append([node_path, int(im.get_string(1)) if im != null else 0])
	return out


## Every node of `text` has the id the kit gives the scene `scene_path`, and no two share one.
func _assert_stable_ids(text: String, scene_path: String) -> void:
	var seen := {}
	var wrong: Array = []
	var nodes := _node_ids(text)
	for n: Array in nodes:
		var id := int(n[1])
		if id <= 0 or id > 0x7fffffff or seen.has(id) or id != SceneKit.stable_node_id(scene_path, str(n[0])):
			wrong.append(n)
		seen[id] = true
	assert_true(nodes.size() > 0, "%s has nodes" % scene_path)
	assert_eq(wrong.slice(0, 5), [], "%s: each of its %d nodes carries its stable unique_id" % [scene_path, nodes.size()])


func test_stable_unique_ids() -> void:
	var kit := SceneKit.new(OUT)
	var text := "[gd_scene format=3]\n\n[node name=\"A\" type=\"Node3D\" unique_id=1234567]\n\n[node name=\"B\" type=\"Node3D\" parent=\".\"]\n" \
		+ "position = Vector3(1, 2, 3)\n\n[node name=\"C\" parent=\"B\" unique_id=-42 instance=ExtResource(\"1_abcde\")]\n\n[node name=\"D\" type=\"Node\" parent=\"B/C\" groups=[\"g\"]]\n"
	var a := SceneKit.stable_node_id("res://x.tscn", ".")
	var b := SceneKit.stable_node_id("res://x.tscn", "B")
	var c := SceneKit.stable_node_id("res://x.tscn", "B/C")
	var d := SceneKit.stable_node_id("res://x.tscn", "B/C/D")
	var out := kit.stable_unique_ids(text, "res://x.tscn")
	assert_eq(out, "[gd_scene format=3]\n\n[node name=\"A\" type=\"Node3D\" unique_id=%d]\n\n[node name=\"B\" type=\"Node3D\" parent=\".\" unique_id=%d]\n" % [a, b]
		+ "position = Vector3(1, 2, 3)\n\n[node name=\"C\" parent=\"B\" unique_id=%d instance=ExtResource(\"1_abcde\")]\n\n[node name=\"D\" type=\"Node\" parent=\"B/C\" unique_id=%d groups=[\"g\"]]\n" % [c, d],
		"every node line gets its id (a random one replaced, a missing one added), where Godot's saver writes it")
	assert_eq(kit.stable_unique_ids(out, "res://x.tscn"), out, "applying it again changes nothing")
	var ids := [a, b, c, d]
	for id: int in ids:
		assert_true(id >= 1 and id <= 0x7fffffff, "a positive 31-bit id (%d)" % id)
		assert_eq(ids.count(id), 1, "the four ids differ")
	assert_true(SceneKit.stable_node_id("res://y.tscn", ".") != a, "another scene's root has another id")
	assert_eq(SceneKit.stable_node_id("res://x.tscn", "B"), b, "the same every time")
	assert_true(SceneKit.stable_node_id("res://x.tscn", "B", 1) != b, "a clash inside one scene is salted")
	_assert_stable_ids(out, "res://x.tscn")
	# Two nodes that would share an id never do: the second is salted.
	var twins := "[node name=\"A\" type=\"Node3D\"]\n[node name=\"A\" type=\"Node3D\"]\n"
	var twin_ids := _node_ids(kit.stable_unique_ids(twins, "res://x.tscn"))
	assert_eq(int(twin_ids[0][1]), a, "the first keeps the plain id")
	assert_eq(int(twin_ids[1][1]), SceneKit.stable_node_id("res://x.tscn", ".", 1), "the second takes the salted one")


func test_wolf_builder_output_is_clean_and_deterministic() -> void:
	var kit := SceneKit.new(OUT)
	var result: Dictionary = _runner().call("run", kit, ["res://tools/builders/wolf.gd"])
	assert_true(result.ok and int(result.ran) == 1, "the wolf builder ran")
	var path := OUT.path_join("scenes/enemies/wolf.tscn")
	assert_eq(kit.saved, PackedStringArray([path]), "it wrote one scene, under the redirected folder")
	var first := _read(path)
	assert_true(first.length() > 1000, "the scene was written")
	# P49: the ids are those of the scene's own path, not of the redirected folder it was written to.
	_assert_stable_ids(first, "res://scenes/enemies/wolf.tscn")
	assert_true(first.contains("[node name=\"LodProxy\" type=\"MeshInstance3D\" parent=\"Visual\" unique_id=%d]"
		% SceneKit.stable_node_id("res://scenes/enemies/wolf.tscn", "Visual/LodProxy")), "Visual/LodProxy")
	assert_true(first.contains("collision_mask = 51"), "the wolf body uses ACTOR_MASK")
	var wolf := (load(path) as PackedScene).instantiate()
	for node_path in ["CombatEntity", "NavAgent", "BodyShape", "Visual/Body", "Visual/LodProxy",
			"Anchors/Torso", "Hurtboxes/Head", "Hurtboxes/Body", "Hurtboxes/Legs", "Visual/Body/Head",
			"Visual/Body/Tail", "Visual/Body/LegFL", "Visual/Body/LegBR"]:
		assert_true(wolf.has_node(node_path), "the wolf has %s" % node_path)
	assert_false((wolf.get_node("Visual/LodProxy") as Node3D).visible, "the proxy starts hidden")
	wolf.free()
	var kit2 := SceneKit.new(OUT)
	_runner().call("run", kit2, ["res://tools/builders/wolf.gd"])
	assert_eq(_read(path), first, "regenerating gives a byte-identical file")


## P49: up to 0.10.0-m10 this read "have no unique ids"; the committed scenes now carry the kit's stable ones.
func test_committed_scenes_have_stable_unique_ids() -> void:
	for path in ["res://scenes/player/giant.tscn", "res://scenes/enemies/soldier.tscn",
			"res://scenes/enemies/wolf.tscn", "res://scenes/world/practice_dummy.tscn",
			"res://scenes/world/fence_wood.tscn", "res://scenes/world/sandbox_arena.tscn",
			"res://scenes/main.tscn"]:
		var text := _read(path)
		assert_true(text.length() > 0, "%s exists" % path)
		_assert_stable_ids(text, path)
	var soldier := _read("res://scenes/enemies/soldier.tscn")
	assert_true(soldier.contains("[node name=\"LodProxy\" type=\"MeshInstance3D\" parent=\"Visual\" unique_id=%d]"
		% SceneKit.stable_node_id("res://scenes/enemies/soldier.tscn", "Visual/LodProxy")),
		"the soldier gained Visual/LodProxy")
	for path in ["res://scenes/player/giant.tscn", "res://scenes/enemies/soldier.tscn",
			"res://scenes/enemies/wolf.tscn"]:
		var root := (load(path) as PackedScene).instantiate() as CollisionObject3D
		assert_eq(root.collision_mask, SceneKit.ACTOR_MASK, "%s collides with the blockers layer" % path)
		root.free()
