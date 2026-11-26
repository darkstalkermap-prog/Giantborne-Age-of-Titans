extends SceneTree
## C3b: the Valley's landmarks at a stage-1 giant (the world's new game starts at stage 3), near and far - the village
## forge cold (its help outcome not reached), the ruins' Giantforge lit with its smoke, the ruins gate waystone not yet
## reached (its grey column from a few hundred metres) and then reached (its blue beam). Stills only (1280x720).
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy \
##     -s res://tools/c3b_valley_landmarks.gd -- --no-user-settings --mode=valley --new-game --stills=<dir>
##
## Prints C3B_STILLS {"shots": [...]} and quits.

const MAIN_SCENE := "res://scenes/main.tscn"
## The places (the Valley's layout, scenes/world/valley.tscn): [name, the giant's spot (x, z), what he looks at
## (x, y, z), the camera's pitch (degrees), the visited flag to set first ("" for none)].
const SHOTS := [
	["s1_near_forge_cold", Vector2(58.0, -10.0), Vector3(40.0, 3.0, 2.0), -6.0, ""],
	["s1_near_forge_lit", Vector2(160.0, -80.0), Vector3(175.0, 4.0, -104.0), -6.0, ""],
	["s1_near_waystone_unreached", Vector2(112.0, -4.0), Vector3(134.0, 5.0, -18.0), -6.0, ""],
	["s1_far_waystone_unreached", Vector2(-60.0, 60.0), Vector3(134.0, 20.0, -18.0), 2.0, ""],
	["s1_far_forge_lit", Vector2(-20.0, 120.0), Vector3(175.0, 14.0, -104.0), 3.0, ""],
	["s1_near_waystone_reached", Vector2(112.0, -4.0), Vector3(134.0, 5.0, -18.0), -6.0, "visited.valley.cp.ruins_gate"],
	["s1_far_waystone_reached", Vector2(-60.0, 60.0), Vector3(134.0, 20.0, -18.0), 6.0, ""],
]

var _dir := ""
var _player: Node = null
var _out: Array = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--stills="):
			_dir = a.substr(9)
	change_scene_to_file(MAIN_SCENE)
	_run.call_deferred()


func _p() -> Node:
	if _player == null or not is_instance_valid(_player):
		var list := get_nodes_in_group("player")
		_player = list[0] if not list.is_empty() else null
	return _player


func _frames(n: int) -> void:
	for i in n:
		await process_frame


## The ground's height at (x, z) (a ray down from high up; the giant's own body left out).
func _ground(p: Node3D, x: float, z: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, 400.0, z), Vector3(x, -100.0, z), 1, [(p as CollisionObject3D).get_rid()])
	var hit := p.get_world_3d().direct_space_state.intersect_ray(q)
	return float(hit.position.y) if not hit.is_empty() else 0.0


func _run() -> void:
	for i in 900:
		await process_frame
		if _p() != null and bool(_p().call("is_on_floor")):
			break
	await _frames(60)
	var p := _p() as Node3D
	if p == null:
		print("C3B_STILLS {\"error\": \"no giant\"}")
		quit(1)
		return
	var rig: Node3D = p.get("camera_rig")
	var ws: Object = root.get_node("WorldState")
	for s: Array in SHOTS:
		if str(s[4]) != "":
			ws.call("set_flag", str(s[4]), true)
		var at: Vector2 = s[1]
		var look: Vector3 = s[2]
		p.global_position = Vector3(at.x, _ground(p, at.x, at.y) + 0.3, at.y)
		var d := look - p.global_position
		var yaw := atan2(-d.x, -d.z)
		p.set("facing_yaw", yaw)
		p.rotation.y = yaw
		rig.set("yaw", yaw + deg_to_rad(8.0))
		rig.set("pitch", deg_to_rad(float(s[3])))
		await _frames(90)
		await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		if img != null and _dir != "":
			DirAccess.make_dir_recursive_absolute(_dir)
			img.save_png(_dir.path_join("%s.png" % str(s[0])))
		_out.append(str(s[0]))
	print("C3B_STILLS " + JSON.stringify({"shots": _out}))
	quit(0)
