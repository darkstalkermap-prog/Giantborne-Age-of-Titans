extends SceneTree
## The draw calls of the stress arena's twelve combatants (4 soldiers, 3 wolves, 2 archers, a mage,
## 2 ogres: tools/builders/stress.gd COMBATANTS), all in view at full detail, as the rendered
## draw-call check of P22 measures them (tests/slow/test_rig_draw_calls.gd runs this in a child
## process under Xvfb; the headless test runner renders nothing). It needs a renderer:
##
##   xvfb-run -a -s "-screen 0 640x360x24" godot --path . --resolution 640x360 --audio-driver Dummy \
##     -s res://tests/support/rig_draw_probe.gd
##
## The `low` preset's look: a sun without shadows. Prints one line
##   RIG_DRAWS {"empty": <the camera, sun and floor alone>, "with": <and the twelve>, "actors": 12,
##              "per_actor": <(with - empty) / 12>, "renderer": ..., "kinds": {kind: count}}
## and quits. The actors stand still (processing off): their rigs, weapons and proxies as built.

const COMPOSITION := [["soldier", 4], ["wolf", 3], ["archer", 2], ["mage", 1], ["ogre", 2]]
const SCENES := {
	"soldier": "res://scenes/enemies/soldier.tscn",
	"wolf": "res://scenes/enemies/wolf.tscn",
	"archer": "res://scenes/enemies/archer.tscn",
	"mage": "res://scenes/enemies/mage.tscn",
	"ogre": "res://scenes/enemies/ogre.tscn",
}
const SETTLE_FRAMES := 8

var _root3d: Node3D
var _frame := 0
var _empty := -1
var _spawned := false
var _count := 0


func _initialize() -> void:
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var cam := Camera3D.new()
	cam.far = 200.0
	_root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 9, 24), Vector3(0, 1.5, 0))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = false
	_root3d.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	floor_mesh.mesh = plane
	_root3d.add_child(floor_mesh)
	process_frame.connect(_on_frame)


static func _calls() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _on_frame() -> void:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	if _empty < 0:
		_empty = _calls()
		_spawn()
		_frame = 0
		return
	var with := _calls()
	var kinds := {}
	for k: Array in COMPOSITION:
		kinds[k[0]] = k[1]
	var out := {"empty": _empty, "with": with, "actors": _count,
		"per_actor": float(with - _empty) / maxf(1.0, float(_count)),
		"renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
		"adapter": RenderingServer.get_video_adapter_name(), "kinds": kinds}
	print("RIG_DRAWS " + JSON.stringify(out))
	quit(0)


func _spawn() -> void:
	var i := 0
	for k: Array in COMPOSITION:
		var ps := load(str(SCENES[k[0]])) as PackedScene
		for n in int(k[1]):
			var a := ps.instantiate() as Node3D
			a.process_mode = Node.PROCESS_MODE_DISABLED
			if "ai_enabled" in a:
				a.set("ai_enabled", false)
			if "entity_id" in a:
				a.set("entity_id", "probe.%s_%d" % [k[0], n])
			# Two rows across the view, 10-16 m from the camera.
			var row := i / 6
			var col := i % 6
			a.position = Vector3(-12.5 + 5.0 * col, 0.0, -2.0 - 6.0 * row)
			_root3d.add_child(a)
			i += 1
	_count = i
