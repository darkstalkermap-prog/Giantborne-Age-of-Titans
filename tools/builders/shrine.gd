extends RefCounted
## Builder: the shrine (scenes/world/shrine.tscn, P05). A standing stone on a low dais, with a
## rune that glows once the shrine is activated, a SpawnPoint (CheckpointMarker; the Shrine
## sets its checkpoint_id to its world_id) and a GrowthPad (Marker3D) 6.5 m in front of the
## stone, where a stage-3 giant (radius 1.65 m, 7.92 m tall) has room. Only the stone collides
## (WORLD); the dais is visual, so the giant walks over it.
##
## The shrine faces -Z: the pad is at local (0, 0, -6.5) and the SpawnPoint faces away from
## the stone. A level places it with world_id and shrine_id set on the instance.

const S_SHRINE := "res://scripts/world/shrine.gd"
const S_MARKER := "res://scripts/world/checkpoint_marker.gd"
const PATH := "res://scenes/world/shrine.tscn"
const PAD_Z := -6.5


static func build_all(kit: SceneKit) -> void:
	kit.save(build_shrine(kit), PATH)


static func _materials(kit: SceneKit) -> void:
	kit.add_material("shrine_stone", Color(0.46, 0.48, 0.52), 0.85)
	kit.add_material("shrine_moss", Color(0.30, 0.42, 0.26), 0.95)
	var rune := kit.add_material("shrine_rune", Color(0.20, 0.30, 0.36), 0.6)
	_set_emission(kit, rune, "shrine_rune", Color(0.10, 0.25, 0.32), 0.6)
	var glow := kit.add_material("shrine_glow", Color(0.55, 0.92, 1.0), 0.3)
	_set_emission(kit, glow, "shrine_glow", Color(0.45, 0.85, 1.0), 2.2)


static func _set_emission(kit: SceneKit, m: StandardMaterial3D, mat_name: String, color: Color,
		energy: float) -> void:
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if kit.out_root == "":
		ResourceSaver.save(m, "%s/%s.tres" % [SceneKit.MAT_DIR, mat_name], ResourceSaver.FLAG_CHANGE_PATH)


static func build_shrine(kit: SceneKit) -> Node:
	_materials(kit)
	var root := Node3D.new()
	root.name = "Shrine"
	kit.scripted(root, S_SHRINE, {"shrine_id": "shrine.sandbox", "prompt": "Rest", "radius_m": 4.0,
		"priority": 40})
	var stone := kit.static_box("Stone", Vector3(1.4, 4.2, 1.0), Vector3(0, 2.1, 0), "shrine_stone")
	root.add_child(stone)
	var visual := kit.n3("Visual")
	visual.add_child(kit.cyl("Dais", 3.2, 3.4, 0.12, Vector3(0, 0.06, 0), "shrine_stone"))
	visual.add_child(kit.cyl("DaisMoss", 2.4, 2.6, 0.14, Vector3(0, 0.07, 0), "shrine_moss"))
	visual.add_child(kit.box("Cap", Vector3(1.8, 0.35, 1.3), Vector3(0, 4.35, 0), "shrine_stone"))
	visual.add_child(kit.box("Rune", Vector3(0.5, 1.8, 0.06), Vector3(0, 2.5, -0.52), "shrine_rune"))
	var glow := kit.box("Glow", Vector3(0.56, 1.9, 0.08), Vector3(0, 2.5, -0.53), "shrine_glow")
	glow.visible = false
	visual.add_child(glow)
	var name_label := kit.sign("SHRINE", Vector3(0, 5.3, 0))
	name_label.name = "Name"
	visual.add_child(name_label)
	root.add_child(visual)
	var pad := kit.marker("GrowthPad", Vector3(0, 0, PAD_Z))
	root.add_child(pad)
	var spawn := Marker3D.new()
	spawn.name = "SpawnPoint"
	kit.scripted(spawn, S_MARKER)
	spawn.position = Vector3(0, 0.05, PAD_Z)
	root.add_child(spawn)
	return root
