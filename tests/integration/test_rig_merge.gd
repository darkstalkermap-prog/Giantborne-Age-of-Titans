extends IntegrationSuite
## P22 (plan M6-M9 §3.4 designs 1 and 3, decision 9): merged rigs. Every humanoid and quadruped rig
## is one vertex-coloured mesh per animated pivot plus the weapon, all sharing one material (the
## scene's), which the rig copies once per actor: a hit flash sets its emission and a status tint
## multiplies its albedo. The giant keeps its chest, belt and head (render layer 2, culled in first
## person) as meshes of their own and a Hand marker where each hand box was. QuadrupedRig emits
## `footfall` once per paw pair landing.

## [scene, meshes under Visual/Body (the plan's estimate in the system doc), weapon mesh name,
## whether it has a Visual/LodProxy (the giant never leaves the camera's near range: none)]
const RIGS := [
	["res://scenes/enemies/soldier.tscn", 6, "ShoulderR/Weapon", true],
	["res://scenes/enemies/wolf.tscn", 7, "", true],
	["res://scenes/enemies/archer.tscn", 6, "ShoulderR/Weapon", true],
	["res://scenes/enemies/mage.tscn", 7, "ShoulderR/Weapon", true],
	["res://scenes/enemies/ogre.tscn", 6, "ShoulderR/Weapon", true],
	["res://scenes/enemies/ogre_king.tscn", 6, "ShoulderR/Weapon", true],
	["res://scenes/npcs/villager.tscn", 5, "", true],
	["res://scenes/npcs/elder.tscn", 5, "", true],
	["res://scenes/player/giant.tscn", 8, "ShoulderR/Club", false],
]
const WOLF := "res://scenes/enemies/wolf.tscn"


static func _meshes(node: Node, out: Array[MeshInstance3D] = []) -> Array[MeshInstance3D]:
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c as MeshInstance3D)
		_meshes(c, out)
	return out


func test_each_rig_is_one_vertex_coloured_mesh_per_pivot() -> void:
	for spec: Array in RIGS:
		var root := (load(spec[0]) as PackedScene).instantiate()
		var body := root.get_node("Visual/Body")
		var meshes := _meshes(body)
		var what := str(spec[0]).get_file()
		assert_eq(meshes.size(), int(spec[1]), "%s: %d meshes under Visual/Body" % [what, int(spec[1])])
		var mat: Material = null
		for mi in meshes:
			assert_eq(mi.mesh.get_surface_count(), 1, "%s/%s: one surface" % [what, mi.name])
			var arrays := mi.mesh.surface_get_arrays(0)
			assert_true(arrays[Mesh.ARRAY_COLOR] is PackedColorArray \
				and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
				"%s/%s: a colour per vertex" % [what, mi.name])
			var m := mi.material_override as StandardMaterial3D
			assert_true(m != null and m.vertex_color_use_as_albedo and m.emission_enabled,
				"%s/%s: the rig material (vertex colours, emission on)" % [what, mi.name])
			if mat == null:
				mat = m
			assert_true(m == mat, "%s/%s: one material for the whole rig" % [what, mi.name])
		var proxy := root.get_node_or_null("Visual/LodProxy") as MeshInstance3D
		if bool(spec[3]):
			assert_true(proxy != null and proxy.material_override == mat, "%s: the LodProxy shares it" % what)
		else:
			assert_true(proxy == null, "%s: no LodProxy" % what)
		if str(spec[2]) != "":
			assert_true(body.get_node_or_null(NodePath(spec[2])) is MeshInstance3D, "%s: %s is its own mesh" % [what, spec[2]])
		root.free()


func test_the_giant_keeps_its_first_person_parts_apart() -> void:
	var root := (load(GIANT) as PackedScene).instantiate()
	for part in ["Chest", "Belt", "Head"]:
		var mi := root.get_node("Visual/Body/Torso/" + part) as MeshInstance3D
		assert_eq(mi.layers, SceneKit.FP_HIDDEN, "%s on render layer 2 (first person culls it)" % part)
	for path in ["Visual/Body/ShoulderL/Mesh", "Visual/Body/ShoulderR/Mesh", "Visual/Body/HipL/Mesh"]:
		assert_eq((root.get_node(path) as MeshInstance3D).layers, 1, "%s on render layer 1" % path)
	for side in ["ShoulderL", "ShoulderR"]:
		var hand := root.get_node("Visual/Body/%s/Hand" % side) as Marker3D
		assert_true(hand != null and hand.position.is_equal_approx(Vector3(0, 0, -1.5)), "%s/Hand marks the hand" % side)
	root.free()


## One material copy per actor; a flash is emission, a tint multiplies the albedo; both go away.
func test_flashes_and_tints_read_on_the_one_material() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4))
	var w := (load(WOLF) as PackedScene).instantiate() as WolfEnemy
	w.entity_id = "test.wolf"
	w.ai_enabled = false
	w.position = Vector3(3, 0.05, -4)
	world.add_child(w)
	await step_ticks(2)
	for rig: Node3D in [s.rig, w.quad]:
		var mats: Array = rig.get("_materials")
		assert_eq(mats.size(), 1, "%s: one material copy for the actor" % rig.get_parent().name)
		var m := mats[0] as StandardMaterial3D
		for mi in _meshes(rig.get_node("Body")):
			assert_true(mi.material_override == m, "%s/%s uses the actor's copy" % [rig.get_parent().name, mi.name])
		assert_true(m.emission.is_equal_approx(Color.BLACK), "no glow at rest")
		rig.call("flash", 1.0)
		await step_ticks(1)
		assert_true(m.emission.r > 0.3 and m.emission.g > 0.3, "a flash lights the emission (%s)" % m.emission)
		assert_true(m.albedo_color.is_equal_approx(Color.WHITE), "the flash leaves the albedo alone")
		rig.call("set_status_tint", Color(0.45, 0.70, 1.0, 0.35))
		await step_ticks(30)
		assert_true(m.emission.is_equal_approx(Color.BLACK), "the flash fades")
		var tint := RigPaint.tint_multiplier(Color(0.45, 0.70, 1.0, 0.35))
		assert_true(m.albedo_color.is_equal_approx(tint), "a tint multiplies the albedo (%s)" % m.albedo_color)
		rig.call("set_status_tint", Color(0, 0, 0, 0))
		await step_ticks(1)
		assert_true(m.albedo_color.is_equal_approx(Color.WHITE), "and goes")


## The giant's weapon visual brings its own flat materials; the rig copies them (emission on) and
## forgets them when the weapon changes.
func test_the_giants_weapon_materials_join_and_leave_the_flash_list() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	var mats: Array = p.rig.get("_materials")
	p.rig.set_weapon_visual(null)   # the equipped weapon's own visual leaves first
	var before := mats.size()
	assert_eq(before, 1, "bare-handed, the rig's one material")
	var club := WeaponVisuals.build({"id": "weapon.test", "visual_shape": "sword", "length_m": 1.6})
	p.rig.set_weapon_visual(club)
	assert_true(mats.size() > before, "the weapon's materials join the list")
	for mi in _meshes(club):
		var m := mi.material_override as StandardMaterial3D
		assert_true(mats.has(m) and m.emission_enabled, "%s: a copy with emission" % mi.name)
	p.rig.set_weapon_visual(null)
	assert_eq(mats.size(), before, "and leave it with the weapon")
	await step_ticks(1)


## QuadrupedRig.footfall (the audio router's paw steps): once per half gait cycle while moving.
func test_a_trotting_wolf_rig_emits_a_footfall_per_paw_pair() -> void:
	var src := GDScript.new()
	src.source_code = "extends Node3D\nvar speed := 4.0\nfunc get_rig_state() -> Dictionary:\n\treturn {\"state\": %d, \"speed\": speed}\n" % CombatController.State.LOCOMOTION
	src.reload()
	var holder := Node3D.new()
	holder.set_script(src)
	var wolf := (load(WOLF) as PackedScene).instantiate()
	var rig := wolf.get_node("Visual") as QuadrupedRig
	wolf.remove_child(rig)
	wolf.free()
	holder.add_child(rig)
	world.add_child(holder)
	var heard := [0]
	rig.footfall.connect(func() -> void: heard[0] += 1)
	await step_ticks(60)
	var expected := 4.0 / rig.stride_length_m   # gait rate / pi: footfalls per second
	assert_true(absf(float(heard[0]) - expected) <= 1.0, "%d footfalls in 1 s at 4 m/s (expected about %.1f)" % [heard[0], expected])
	assert_eq(rig.footfalls, heard[0], "counted as emitted")
	holder.set("speed", 0.0)
	var still: int = heard[0]
	await step_ticks(30)
	assert_eq(heard[0], still, "none while standing")
