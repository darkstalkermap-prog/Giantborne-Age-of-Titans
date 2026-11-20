@tool
extends EditorScenePostImport
## The giant's parts on import (the W33 look lane; plan M11 §2.12's share): a part's glTF is exported on the
## model's whole 71-bone armature (export_game.py), so its imported scene carried a Skeleton3D of 71 bones with
## its rest poses - about 7.7 KB a part, 69 parts - that GiantModel never uses: `GiantModel.load_part` takes the
## part's mesh and its skin (the binds, by name, the model's own) and draws it on the model's skeleton. This
## script keeps of a part only a root and its one skinned MeshInstance3D (mesh, skin, name), so the Web pack
## ships the skeleton once (in giant.glb). build_giant.py writes this script into every part's .import
## (IMPORT_SETTINGS "parts/*.glb"); the importer runs it in the editor and the Web build's import, never in play.


func _post_import(scene: Node) -> Object:
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
	keep.mesh = found.mesh
	keep.skin = found.skin
	keep.cast_shadow = found.cast_shadow
	root.add_child(keep)
	keep.owner = root
	scene.free()
	return root
