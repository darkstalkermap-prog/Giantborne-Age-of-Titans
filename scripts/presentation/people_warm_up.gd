class_name PeopleWarmUp
extends Node3D
## The people's and the creatures' shader variants made behind the loading screen (P64; plan M11 §3.17 design 3,
## §2.12 "Shader stalls": the first formation in view, the first wolf). Main.hold_until_drawn draws the finished level
## a few frames from the player's camera before the loading screen lets go; the first time in a process this node
## stands in that view, a few metres before the camera, under the level's own lights, fog and shadows, holding one of
## each way the people and the creatures draw:
##   * a skinned person (a pooled PersonModel: person.gdshader on a skinned mesh, and its shadow),
##   * a wolf (P63's glTF: the coat, skinned, in person.gdshader with its strands cut) with its fur shell
##     (fur_shell.gdshader) where the graphics preset draws one,
##   * a far mesh (person.gdshader, not skinned) and a crowd instance (person_crowd.gdshader in a MultiMesh).
## Nothing else: the tree is paused, no tick passes, and the node is freed before the first frame of play. Never
## made without a display (the loading screen's warm-up runs only there) or without the people's files.

const AHEAD_M := 5.0
static var warmed := false


## The warm-up placed before `camera` under `level` (null when it is not wanted: done already, no camera or level).
static func place(camera: Camera3D, level: Node) -> PeopleWarmUp:
	if warmed or camera == null or level == null or not PersonRig.layers_enabled():
		return null
	var w := PeopleWarmUp.new()
	w.name = "PeopleWarmUp"
	level.add_child(w)
	var fwd := -camera.global_transform.basis.z
	w.global_transform = Transform3D(Basis(Vector3.UP, atan2(fwd.x, fwd.z)), camera.global_position + fwd * AHEAD_M
		+ Vector3.DOWN * 1.2)
	w._fill()
	return w


## Frees the warm-up (its model back to the pool) and marks the process warmed.
static func remove(w: PeopleWarmUp) -> void:
	if w == null or not is_instance_valid(w):
		return
	warmed = true
	if w._person != null:
		PersonModel.release(w._person)
		w._person = null
	w.queue_free()


var _person: PersonModel = null


func _fill() -> void:
	_person = PersonModel.acquire("soldier", "")
	if _person != null:
		add_child(_person)
		_person.position = Vector3(-0.8, 0.0, 0.0)
		_person.mesh_instance().cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var r := PersonModel.role_data("soldier")
		var far := MeshInstance3D.new()
		far.mesh = r.get("far")
		far.material_override = _person.material
		far.position = Vector3(0.8, 0.0, 0.0)
		add_child(far)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = (r.get("poses", {}) as Dictionary).get("hold")
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis(), Vector3(1.6, 0.0, 0.0)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = PersonModel.crowd_material("person_role.soldier")
		add_child(mmi)
	var w: Dictionary = SkinnedQuadrupedRig.creature_index().get("wolf", {})
	if w.is_empty() or not ResourceLoader.exists(str(w.get("scene", ""))):
		return
	var wolf := (load(str(w.scene)) as PackedScene).instantiate() as Node3D
	add_child(wolf)
	wolf.position = Vector3(0.0, 0.0, 1.0)
	var mat := SkinnedQuadrupedRig.horse_material(w)
	for n in wolf.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		mi.material_override = mat
		if str(mi.name) == str((w.get("meshes", {}) as Dictionary).get("shell", "wolf_shell")):
			var layers := SkinnedWolfRig.fur_layers()
			if layers <= 0:
				mi.visible = false
				continue
			mi.mesh = SkinnedWolfRig.fur_mesh(mi.mesh, layers)
			var fur := ShaderMaterial.new()
			fur.shader = load(SkinnedWolfRig.FUR_SHADER)
			mi.material_override = fur
