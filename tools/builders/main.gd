extends RefCounted
## Builder: the entry scene (scenes/main.tscn).

const S_MAIN := "res://scripts/main.gd"
const PATH := "res://scenes/main.tscn"


static func build_all(kit: SceneKit) -> void:
	var root := Node.new()
	root.name = "Main"
	kit.scripted(root, S_MAIN)
	kit.save(root, PATH)
