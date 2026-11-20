@tool
extends EditorScenePostImport
## The giant's meshes on import. build_giant.py writes this script into every part's .import and giant.glb's
## (IMPORT_SETTINGS); the importer runs it in the editor and the Web build's import, never in play.
##
## - A part (the W33 look lane; plan M11 §2.12's share): a part's glTF is exported on the model's whole 71-bone
##   armature (export_game.py), so its imported scene carried a Skeleton3D of 71 bones with its rest poses - about
##   7.7 KB a part, 69 parts - that GiantModel never uses: `GiantModel.load_part` takes the part's mesh and its skin
##   (the binds, by name, the model's own) and draws it on the model's skeleton. This script keeps of a part only a
##   root and its one skinned MeshInstance3D (mesh, skin, name), so the Web pack ships the skeleton once.
## - Every mesh but the shadow proxy takes its far levels (far_lods.gd; the second look lane, plan M11 §2.12's
##   "at most 4,000 primitives beyond 120 m"); a hair style's or a beard's its own strand levels; a bead set's keeps
##   no share of its triangles (its beads are a few pixels at most).

const FarLods := preload("res://tools/giant/far_lods.gd")


func _post_import(scene: Node) -> Object:
	if get_source_file().get_file() == "giant.glb":
		for n in scene.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.name != &"ShadowProxy":
				mi.mesh = FarLods.with_far_levels(mi.mesh)
		return scene
	var found: MeshInstance3D = null
	for n in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.skin != null:
			found = mi
			break
	if found == null:
		return scene
	var root := Node3D.new()
	root.name = scene.name
	var keep := MeshInstance3D.new()
	keep.name = found.name
	keep.mesh = FarLods.with_far_levels(found.mesh, strands(str(found.name)),
		0.0 if str(found.name).begins_with("Beads_") else FarLods.FAR_LEAST_SHARE)
	keep.skin = found.skin
	keep.cast_shadow = found.cast_shadow
	root.add_child(keep)
	keep.owner = root
	scene.free()
	return root


## True for a hair style's or a beard's mesh (cards, braids' tubes and ties).
static func strands(mesh_name: String) -> bool:
	return mesh_name.begins_with("Hair_") or mesh_name.begins_with("Beard_")
