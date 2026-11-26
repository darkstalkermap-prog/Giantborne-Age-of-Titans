extends SceneTree
## C3b: the low strike on film - the sandbox at a stage, a soldier stood at the giant's toes and another at half his
## reach (and a fence), the camera put on each in turn (its yaw and pitch, as a player's mouse would: the screen's
## centre on the body) with the aim indicator showing what the press will do, then a light (the stamp) and a heavy
## (the stomp), each seen by an onlooker's camera from his side as it lands. Drives the giant through its InputRouter
## only.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy \
##     --rendering-driver opengl3 --fixed-fps 30 --write-movie <file.avi> -s res://tools/c3b_low_film.gd -- \
##     --no-user-settings --mode=sandbox --film-stage=8 [--film-still=<dir>]
##
## --film-still=<dir> also saves 1280x720 stills (the indicator on the man, the foot coming down, the strike) there.
## Prints C3B_FILM {"stage", "strikes": [{"what", "strike", "struck"}]} and quits when the film is done.

const MAIN_SCENE := "res://scenes/main.tscn"
const SOLDIER := "res://scenes/enemies/soldier.tscn"
const FENCE := "res://scenes/world/fence_wood.tscn"
## (CameraRig's third-person pitch limits and ActionDef's phases: a -s script cannot name the project's classes)
const PITCH_MIN := -84.0
const PITCH_MAX := 40.0
const ACTIVE := 2
const WINDUP := 1

var _stage := 8
var _still_dir := ""
var _player: Node = null
var _out: Array = []
var _hits: Array = []
var _side_deg := 105.0
var _eye: Camera3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--film-stage="):
			_stage = int(a.substr(13))
		elif a.begins_with("--film-still="):
			_still_dir = a.substr(13)
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


func _still(name: String) -> void:
	if _still_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if img != null:
		DirAccess.make_dir_recursive_absolute(_still_dir)
		img.save_png(_still_dir.path_join("stage%d_%s.png" % [_stage, name]))


## The camera's yaw and pitch that put the screen's centre on `point` (a few rounds: the camera's place moves with them).
func _aim_at(point: Vector3, frames_each := 2) -> void:
	var rig: Node3D = _p().get("camera_rig")
	for i in 8:
		var from := rig.global_position
		var d := point - from
		rig.set("yaw", atan2(-d.x, -d.z))
		rig.set("pitch", clampf(atan2(d.y, Vector2(d.x, d.z).length()), deg_to_rad(PITCH_MIN), deg_to_rad(PITCH_MAX)))
		await _frames(frames_each)


func _spawn(path: String, at: Vector3, id: String, yaw: float) -> Node3D:
	var n := (load(path) as PackedScene).instantiate() as Node3D
	if "entity_id" in n:
		n.set("entity_id", id)
	if "world_id" in n:
		n.set("world_id", id)
	if "ai_enabled" in n:
		n.set("ai_enabled", false)
	n.position = at
	n.rotation.y = yaw
	(_p().get_parent() as Node).add_child(n)
	return n


func _on_hit(_tick: int, r: Object) -> void:
	var ev: Object = r.get("event")
	if ev != null and str(ev.get("attacker_id")) == "player":
		_hits.append(str(ev.get("target_id")))


func _strike(what: String, node: Node3D, heavy: bool, aim: Vector3) -> void:
	print("C3B_FILM_STEP %s %s" % [what, heavy])
	var p := _p()
	await _aim_at(aim)
	await _frames(24)   # the indicator shows it
	var plan: Dictionary = p.get("attack").call("next_swing_plan", heavy)
	await _still("%s_%s_aimed" % [what, "heavy" if heavy else "light"])
	_hits.clear()
	var r: Object = p.get("router")
	r.call("inject_edge", &"heavy" if heavy else &"light")
	await _frames(2)
	# the strike seen by an onlooker from his side, low, the whole of him and his target in the frame (the press's plan
	# is made; the HUD's indicator belongs to his own camera, shown in the aimed shot)
	var h := float((p.get("profile") as Dictionary).get("height_m", 3.66))
	var at: Vector3 = (p as Node3D).global_position
	var tgt := node.global_position
	var mid := at.lerp(tgt, 0.5)
	var to := (tgt - at)
	to.y = 0.0
	var fwd := to.normalized() if to.length() > 0.1 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized() * signf(_side_deg)
	_eye.global_position = mid + side * (1.95 * h) - fwd * (0.3 * h) + Vector3.UP * (0.5 * h)
	_eye.look_at(mid + Vector3.UP * (0.44 * h), Vector3.UP)
	_eye.current = true
	var c: Object = p.get("controller")
	var shots := 0
	for i in 90:
		await process_frame
		var a: Object = c.get("action")
		if a != null and shots == 0 and int(c.call("phase")) == WINDUP and float(c.call("phase_fraction")) > 0.6:
			shots += 1
			await _still("%s_%s_lift" % [what, "heavy" if heavy else "light"])
		elif a != null and shots == 1 and int(c.call("phase")) != WINDUP:
			shots += 1
			await _frames(4)
			await _still("%s_%s_strike" % [what, "heavy" if heavy else "light"])
	await _still("%s_%s_after" % [what, "heavy" if heavy else "light"])
	_side_deg = -_side_deg
	((p.get("camera_rig") as Node).get("camera") as Camera3D).current = true
	_out.append({"what": what, "strike": str(plan.get("strike", "")), "planned": str(plan.get("variant", "")),
		"reaches": bool(plan.get("reaches", false)), "struck": _hits.duplicate()})
	await _frames(30)


func _run() -> void:
	for i in 600:
		await process_frame
		if _p() != null and bool(_p().call("is_on_floor")):
			break
	await _frames(20)
	var p := _p()
	print("C3B_FILM_STEP start %s" % [p != null])
	if p == null:
		print("C3B_FILM {\"error\": \"no giant\"}")
		quit(1)
		return
	(root.get_node("Events") as Object).connect("hit_resolved", _on_hit)
	var r: Object = p.get("router")
	r.set("use_injection", true)
	var duel: Script = load("res://scripts/debug/titan_duel.gd")
	duel.call("prepare", p, _stage)
	await _frames(60)
	var prof: Dictionary = p.get("profile")
	var cap := float(prof.get("capsule_radius_m", 0.85))
	var reach := float(prof.get("melee_reach_m", 3.5))
	var at: Vector3 = (p as Node3D).global_position
	var yaw := float(p.get("facing_yaw"))
	var fwd := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var rig: Node3D = p.get("camera_rig")
	rig.set("yaw", yaw)
	rig.set("pitch", deg_to_rad(-30.0))
	await _frames(60)
	_eye = Camera3D.new()
	_eye.name = "FilmEye"
	_eye.fov = 52.0
	_eye.far = 2000.0
	(p.get_parent() as Node).add_child(_eye)
	# a soldier at his toes, a little left: the stamp
	var feet := at + fwd * (cap + 1.0) - right * (cap * 0.25)
	var man := _spawn(SOLDIER, feet, "c3b.film.man_feet", yaw + PI)
	await _frames(10)
	await _strike("man_feet", man, false, (man.get("entity") as Object).call("anchor_position"))
	# another at half his reach, a little right: the stomp
	var mid := at + fwd * maxf(cap + 1.6, reach * 0.5) + right * (cap * 0.3)
	var man2 := _spawn(SOLDIER, mid, "c3b.film.man_mid", yaw + PI)
	await _frames(10)
	await _strike("man_mid", man2, true, (man2.get("entity") as Object).call("anchor_position"))
	# a fence before him: the stamp
	var fence := _spawn(FENCE, at + fwd * (cap + 2.0) + right * (cap * 0.1), "c3b.film.fence", yaw + 0.3)
	await _frames(10)
	await _strike("fence", fence, false, fence.global_position + Vector3.UP * 0.8)
	await _frames(40)
	print("C3B_FILM " + JSON.stringify({"stage": _stage, "strikes": _out}))
	quit(0)
