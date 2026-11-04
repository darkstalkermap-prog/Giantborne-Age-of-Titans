class_name SandboxArena
extends Node3D
## The 120 x 120 m combat sandbox. Bakes its navigation mesh at load (sandbox-sized, a few
## hundred milliseconds at most) and rebuilds it in the background when a breakable that
## blocked paths is destroyed. Larger worlds will use authored alternate paths instead.

@onready var nav_region: NavigationRegion3D = $Navigation

var bake_count := 0


func _ready() -> void:
	add_to_group("sandbox")
	# The NavigationMesh is a sub-resource shared by every instance of this scene. Give each
	# instance its own copy so a background rebake in a scene being reset can never collide
	# with the fresh scene's bake.
	nav_region.navigation_mesh = nav_region.navigation_mesh.duplicate()
	nav_region.bake_finished.connect(_on_bake_finished)
	nav_region.bake_navigation_mesh(false)
	Events.object_destroyed.connect(_on_object_destroyed)


func _on_bake_finished() -> void:
	bake_count += 1


func _on_object_destroyed(_tick: int, _world_id: String, _by: String) -> void:
	# Wait one frame so the destroyed object's blocking shape is gone before parsing.
	await get_tree().process_frame
	if is_inside_tree() and not nav_region.is_baking():
		nav_region.bake_navigation_mesh(true)


func player_spawn() -> Transform3D:
	var m := get_node_or_null("Spawns/PlayerSpawn") as Node3D
	return m.global_transform if m != null else Transform3D.IDENTITY
