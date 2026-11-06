extends SceneTree
## The draw calls of the formation stress case (P30, plan M6-M9 §3.13 slow tests: "rendered draw
## calls for 40 members <= 120"): two pike regiments of nineteen pikemen and a banner each, placed
## as data/test/encounter_formation_test_stress.json places them, each drawn by its CrowdRenderer,
## seen from a stage-4 giant's third-person view 9 m in front of them, the `low` look (a sun
## without shadows). tests/slow/test_formation_perf.gd runs this in a child process under Xvfb (the
## headless runner renders nothing):
##
##   xvfb-run -a -s "-screen 0 640x360x24" godot --path . --resolution 640x360 --audio-driver Dummy \
##     -s res://tests/support/formation_draw_probe.gd
##
## It measures the view alone (camera, sun, floor and the giant), then with the formations "near"
## (the giant 9 m away: at stage 4 every member is within the promotion radius, so each formation
## promotes its six nearest to their own rigs) and "far" (the giant 400 m away: nobody promoted),
## and prints one line and quits:
##   FORMATION_DRAWS {"empty", "near", "far", "members", "promoted_near", "crowd_near", "rigs_each",
##                    "adapter"}
## where rigs_each is the draw calls of the 40 drawn as rigs (crowd renderers released), for scale.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const GIANT := "res://scenes/player/giant.tscn"
const ENCOUNTER := "encounter.formation_test_stress"
## Loaded at run time, untyped: a -s script compiles before the autoloads are registered, so it must
## not name the game's classes (they use the autoloads); the scenes and these load once they exist.
const S_FORMATION := "res://scripts/ai/formation.gd"
const S_CROWD := "res://scripts/presentation/crowd_renderer.gd"
const BANNER_SLOT := -1
const SETTLE_FRAMES := 8

var _root3d: Node3D
var _giant: Node3D
var _cam: Camera3D
var _frame := 0
var _phase := "empty"
var _out := {}
var _renderers: Array = []   # CrowdRenderer
var _formations: Array = []  # Formation
var _members := 0


func _initialize() -> void:
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = false
	_root3d.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(240, 240)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(160, 0, 0)
	_root3d.add_child(floor_mesh)
	_giant = (load(GIANT) as PackedScene).instantiate() as Node3D
	_giant.position = Vector3(160, 0.05, 9)
	_root3d.add_child(_giant)
	for rec: Dictionary in _data().call("records_of_type", "growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			_giant.call("set_profile", rec)
	_cam = Camera3D.new()
	_cam.far = 300.0
	_root3d.add_child(_cam)
	_cam.look_at_from_position(Vector3(160, 14, 30), Vector3(160, 1.0, 0))
	_cam.current = true
	process_frame.connect(_on_frame)


## The GameData autoload (a -s script compiles before the autoload names exist).
func _data() -> Node:
	return get_root().get_node("GameData")


static func _calls() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _on_frame() -> void:
	_cam.current = true
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	_frame = 0
	match _phase:
		"empty":
			_out["empty"] = _calls()
			_spawn()
			_phase = "near"
		"near":
			_out["near"] = _calls()
			var promoted := 0
			var crowd := 0
			for r: Node in _renderers:
				promoted += (r.get("promoted") as Dictionary).size()
				crowd += int(r.call("instance_count"))
			_out["promoted_near"] = promoted
			_out["crowd_near"] = crowd
			_giant.position = Vector3(160, 0.05, 400)
			_phase = "far"
		"far":
			_out["far"] = _calls()
			for r: Node in _renderers:
				r.set_process(false)
				r.call("release_all")
				for c in r.get_children():
					(c as Node3D).visible = false
			_giant.position = Vector3(160, 0.05, 9)
			_phase = "rigs"
		"rigs":
			_out["rigs_each"] = _calls()
			_out["members"] = _members
			_out["adapter"] = RenderingServer.get_video_adapter_name()
			print("FORMATION_DRAWS " + JSON.stringify(_out))
			for f: Object in _formations:
				f.call("dissolve")
			quit(0)


## The two regiments as the stress encounter places them (its spawns' positions and slots).
func _spawn() -> void:
	var formation_script: GDScript = load(S_FORMATION)
	var crowd_script: GDScript = load(S_CROWD)
	var enc: Dictionary = _data().call("get_record", ENCOUNTER)
	for rec: Dictionary in enc.get("formations", []):
		var f: Object = formation_script.call("from_record", ENCOUNTER, rec)
		var yaw := float(f.get("home_yaw"))
		var pivot := Vector3.ZERO
		var n := 0
		var members: Array = []
		for s: Dictionary in enc.get("spawns", []):
			if str(s.get("formation", "")) != str(rec.id):
				continue
			var p: Array = s.position_m
			var at := Vector3(float(p[0]), 0.05, float(p[2]))
			var slot := int(s.slot)
			var e: Node3D = (load(BANNERMAN if slot == BANNER_SLOT else PIKEMAN) as PackedScene).instantiate()
			e.set("entity_id", str(s.entity_id))
			e.set("ai_enabled", false)
			e.position = at
			e.rotation.y = deg_to_rad(float(s.get("yaw_deg", 0.0)))
			_root3d.add_child(e)
			members.append([e, slot])
			_members += 1
			if slot != BANNER_SLOT:
				pivot += at - Basis(Vector3.UP, yaw) * (f.call("slot_local", slot) as Vector3)
				n += 1
		f.call("place", pivot / float(maxi(1, n)), yaw)
		for pair: Array in members:
			f.call("add_member", pair[0], int(pair[1]))
		var r: Node = crowd_script.new()
		r.set("formation", f)
		_root3d.add_child(r)
		_renderers.append(r)
		_formations.append(f)
