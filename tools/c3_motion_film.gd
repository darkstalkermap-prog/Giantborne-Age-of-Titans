extends SceneTree
## C3: the giant's motion on film - the same scripted inputs on any build (it drives the giant through its InputRouter
## only, as a player's hands would): a walk forward, a turn to the right and back left, a stop, then the camera swung
## 120 degrees round and a three-swing combo pressed at once (light, light, light, a press every 0.2 s), then a heavy.
## Run it with --write-movie for a video (the sandbox at the stage given):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --resolution 1280x720 --audio-driver Dummy \
##     --rendering-driver opengl3 --fixed-fps 30 --write-movie <file.avi> -s res://tools/c3_motion_film.gd -- \
##     --no-user-settings --mode=sandbox [--film-stage=N]
##
## Prints C3_FILM {"stage", "ticks", "swings"} and quits when the film is done.

const MAIN_SCENE := "res://scenes/main.tscn"

var _stage := 1
var _t := 0.0
var _player: Node = null
var _swings := 0


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--film-stage="):
			_stage = int(a.substr(13))
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


func _move(v: Vector2, seconds: float) -> void:
	var r: Object = _p().get("router")
	r.call("set_injected_move", v)
	await _frames(int(seconds * 30.0))


func _run() -> void:
	for i in 600:
		await process_frame
		if _p() != null and bool(_p().call("is_on_floor")):
			break
	await _frames(20)
	var p := _p()
	if p == null:
		print("C3_FILM {\"error\": \"no giant\"}")
		quit(1)
		return
	var r: Object = p.get("router")
	r.set("use_injection", true)
	if _stage > 1:
		var duel: Script = load("res://scripts/debug/titan_duel.gd")
		duel.call("prepare", p, _stage)
		await _frames(40)
	var rig: Object = p.get("camera_rig")
	rig.set("yaw", 0.0)
	rig.set("pitch", deg_to_rad(-14.0))
	await _frames(20)
	await _move(Vector2(0, 1), 1.6)     # forward
	await _move(Vector2(1, 0), 1.2)     # a turn to the right
	await _move(Vector2(-1, 0.3), 1.2)  # and back to the left
	await _move(Vector2.ZERO, 0.8)      # a stop
	rig.set("yaw", deg_to_rad(120.0))   # the camera swung round: the swings turn to it
	await _frames(6)
	for k in 3:
		r.call("inject_edge", &"light")
		_swings += 1
		await _frames(6)
	await _frames(40)
	r.call("inject_edge", &"heavy")
	_swings += 1
	await _frames(70)
	print("C3_FILM " + JSON.stringify({"stage": _stage, "swings": _swings}))
	quit(0)
