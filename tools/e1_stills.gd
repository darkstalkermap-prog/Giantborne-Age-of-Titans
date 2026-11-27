extends Node
## E1: stills of Orrik the Fetterer and the fetter-winch as the game draws them (the Moot test arena, scenes/test/
## throne_test.tscn: his real scene - the player's giant body in his look - and the real winches and their crews), one
## PNG a shot at 1280 x 720: his turnaround (front, back, three-quarter, close on his head and his trophies), the scale
## line-up (a man, a house, stage-8 and stage-9 giants beside him: an orthographic camera, so the heights are honest),
## a winch and its Skarn giant, the winch beside a stage-8 giant's foot, a chain on the giant's leg. The evidence for
## docs/systems/E1.md and the look's own check.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --resolution 1280x720 \
##     --audio-driver Dummy res://tools/e1_stills.tscn -- --out=<dir> [--shots=a,b,...]
##
## Prints E1_STILLS {"shots": [paths]} and quits (a watchdog quits it after WATCHDOG_S).

const SIZE := Vector2i(1280, 720)
const WATCHDOG_S := 600.0
const PREFIX := "E1_STILLS "
const ARENA := "res://scenes/test/throne_test.tscn"
const MAN_H := 1.8
const HOUSE := Vector3(9.0, 4.5, 7.0)

var out_dir := ""
var only: PackedStringArray = []
var _level: Node3D
var _cam: Camera3D
var _written := PackedStringArray()


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(func() -> void:
		print(PREFIX + JSON.stringify({"error": "timed out", "shots": Array(_written)}))
		get_tree().quit(3))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.substr(6)
		elif arg.begins_with("--shots="):
			only = arg.substr(8).split(",", false)
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("user://e1_stills")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_window().size = SIZE
	_level = (load(ARENA) as PackedScene).instantiate() as Node3D
	add_child(_level)
	_cam = Camera3D.new()
	_cam.far = 2000.0
	add_child(_cam)
	_cam.make_current()
	_run.call_deferred()


func _orrik() -> HeirEnemy:
	return _level.get_node("Orrik") as HeirEnemy


func _player() -> GiantPlayer:
	return _level.get_node("Player") as GiantPlayer


func _winch() -> FetterWinch:
	return _level.get_node("Props").get_child(0) as FetterWinch


## Faces `n` (an actor: its rig follows its facing) toward yaw `y`.
func _turn(n: Node3D, y: float) -> void:
	n.rotation.y = y
	if "facing_yaw" in n:
		n.set("facing_yaw", y)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	var o := _orrik()
	o.ai_enabled = false
	var p := _player()
	p.router.use_injection = true
	await _frames(20)
	TitanDuel.prepare(p, 8)
	await _frames(30)
	o.global_position = Vector3(0, 0.05, 0)
	_turn(o, PI)
	p.global_position = Vector3(46, 0.05, 0)
	_turn(p, PI)
	if p.camera_rig != null:
		p.camera_rig.set_process(false)
	await _frames(90)
	var h := 31.5
	await _shot("orrik_front", Vector3(0, h * 0.55, h * 1.6), Vector3(0, h * 0.5, 0), 44.0)
	await _shot("orrik_back", Vector3(0, h * 0.55, -h * 1.6), Vector3(0, h * 0.5, 0), 44.0)
	await _shot("orrik_three_quarter", Vector3(-h * 1.1, h * 0.45, h * 1.2), Vector3(0, h * 0.5, 0), 44.0)
	await _shot("orrik_close", Vector3(-4.0, h * 0.9, h * 0.55), Vector3(0, h * 0.86, 0), 40.0)
	await _shot("orrik_trophies", Vector3(-h * 0.5, h * 0.75, h * 0.6), Vector3(-h * 0.1, h * 0.72, 0), 40.0)
	# the line-up: a man, a house, stage 8 (the player), Orrik, stage 9
	await _lineup()
	# a winch and its crew from a colossus's eye
	var w := _winch()
	await _shot("winch", w.global_position + Vector3(-22, 14, 18), w.global_position + Vector3(0, 4, 0), 45.0)
	print(PREFIX + JSON.stringify({"shots": Array(_written)}))
	get_tree().quit(0)


## The line-up (orthographic, the heights honest): a man, a house, the giant (stage 8, then stage 9) and Orrik.
func _lineup() -> void:
	var o := _orrik()
	var p := _player()
	var z := 150.0
	var house := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = HOUSE
	house.mesh = bm
	_level.add_child(house)
	house.position = Vector3(-44, HOUSE.y * 0.5, z)
	var man := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.height = MAN_H
	cm.radius = 0.3
	man.mesh = cm
	_level.add_child(man)
	man.position = Vector3(-36, MAN_H * 0.5, z)
	for stage: int in [8, 9]:
		TitanDuel.prepare(p, stage)
		await _frames(40)
		o.global_position = Vector3(10, 0.05, z)
		_turn(o, PI)
		p.global_position = Vector3(-14, 0.05, z)
		_turn(p, PI)
		await _frames(20)
		_cam.make_current()
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = 48.0
		_cam.global_position = Vector3(-8, 20, z + 200)
		_cam.look_at(Vector3(-8, 20, z), Vector3.UP)
		await _frames(6)
		await _save("lineup_stage_%d" % stage)
	_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	TitanDuel.prepare(p, 8)
	house.queue_free()
	man.queue_free()


func _shot(name: String, from: Vector3, at: Vector3, fov: float) -> void:
	if not only.is_empty() and not only.has(name):
		return
	_cam.fov = fov
	_cam.make_current()
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)
	await _frames(6)
	await _save(name)


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%02d_%s.png" % [out_dir, _written.size() + 1, name]
	img.save_png(path)
	_written.append(path)
