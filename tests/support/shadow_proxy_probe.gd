extends SceneTree
## The giant's shadow draws with and without the shadow proxy (P49; plan M11 §2.2, §2.12 "shadows one
## draw call a cascade", §3.2 item 4). tests/slow/test_giant_shadow_proxy.gd runs this in a child process
## under Xvfb (the headless runner draws nothing):
##
##   xvfb-run -a -s "-screen 0 640x360x24" godot --path . --rendering-driver opengl3 --resolution 320x240 \
##     --audio-driver Dummy -s res://tests/support/shadow_proxy_probe.gd [-- --splits=1,4]
##
## A camera, a sun that casts shadows (--splits: 1 = one orthogonal shadow map, 2 and 4 = the cascades
## the levels use; several, comma-separated, are measured one after the other in the one process), a floor that casts none, and the giant's model (scenes/player/giant_model.tscn, its
## default look) under a bare ActorRig - the rig's own _ready is the path under test
## (RigPaint.use_shadow_proxy). The frame's draw calls (the rendering server's count, which includes
## every shadow pass) are read in a still scene in these states:
##   empty      the camera, the sun and the floor;
##   all        the model with every shown mesh casting its own shadow and no proxy (0.10.0-m10);
##   proxy      the model as ActorRig leaves it when it has a ShadowProxy;
##   late       a mesh that joins the skeleton afterwards (a part loaded on demand): one more colour
##              draw, no more shadow draws;
##   cape       a mesh named Garment_cape* joining: it keeps its own shadow;
##   unlit      the proxy state with the sun's shadows off (the colour pass alone).
## When the model has no ShadowProxy yet (before P48's model is merged) the probe adds a stand-in - a
## copy of the torso's mesh under the same skeleton, named ShadowProxy - and says so ("stand_in": true);
## the rig's path is the same either way. Prints one line for each --splits value
##   SHADOW_PROXY {"splits", "stand_in", "shown", "shown_surfaces", "proxy_surfaces", "empty", "all",
##                 "proxy", "late", "cape", "unlit", "casting": [names], "adapter"}
## and quits.

const MODEL := "res://scenes/player/giant_model.tscn"
## The rig's scripts are loaded at run time: a script run with -s compiles before the autoloads exist,
## and ActorRig names one (Settings).
const ACTOR_RIG := "res://scripts/presentation/actor_rig.gd"
const RIG_PAINT := "res://scripts/presentation/rig_paint.gd"
const PROXY_NAME := "ShadowProxy"   # RigPaint.SHADOW_PROXY
const SETTLE_FRAMES := 4
const STATES := ["empty", "all", "proxy", "late", "cape", "unlit"]

var _root3d: Node3D
var _sun: DirectionalLight3D
var _rig: Node3D
var _model: Node3D
var _holder: Node
var _frame := 0
var _state := 0
var _out := {}
var _splits := 1
var _todo: Array[int] = []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--splits="):
			for part in a.substr(9).split(",", false):
				_todo.append(int(part))
	if _todo.is_empty():
		_todo.append(1)
	_splits = _todo.pop_front()
	_root3d = Node3D.new()
	get_root().add_child(_root3d)
	var cam := Camera3D.new()
	cam.far = 200.0
	_root3d.add_child(cam)
	cam.look_at_from_position(Vector3(3.5, 3.0, 7.5), Vector3(0, 1.8, 0))
	cam.current = true
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-50, -30, 0)
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 60.0
	_root3d.add_child(_sun)
	_set_splits()
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	floor_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root3d.add_child(floor_mesh)
	_out = {"splits": _splits, "adapter": RenderingServer.get_video_adapter_name()}
	process_frame.connect(_on_frame)


func _set_splits() -> void:
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = (DirectionalLight3D.SHADOW_ORTHOGONAL if _splits <= 1
		else (DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if _splits == 2 else DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS))


static func _calls() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)


func _meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for n in _holder.get_children():
		if n is MeshInstance3D:
			out.append(n as MeshInstance3D)
	return out


func _on_frame() -> void:
	_frame += 1
	if _frame < SETTLE_FRAMES:
		return
	_frame = 0
	_out[STATES[_state]] = _calls()
	_state += 1
	match _state:
		1:
			_spawn()
		2:
			# The path under test, again now that every mesh casts (and with the stand-in when needed).
			_rig.set("shadow_proxy", (load(RIG_PAINT) as GDScript).call("use_shadow_proxy", _rig))
			_note_casting()
		3:
			_join("Hair_late")
		4:
			_join("Garment_cape_late")
		5:
			_sun.shadow_enabled = false
		_:
			print("SHADOW_PROXY " + JSON.stringify(_out))
			if _todo.is_empty():
				quit(0)
				return
			# The next --splits value: an empty scene again, under the next shadow mode.
			_root3d.remove_child(_rig)
			_rig.free()
			_splits = _todo.pop_front()
			_set_splits()
			_out = {"splits": _splits, "adapter": _out.adapter}
			_state = 0


## The model under a bare rig. State "all": every shown mesh casts and no proxy draws, as in 0.10.0-m10.
func _spawn() -> void:
	_rig = (load(ACTOR_RIG) as GDScript).new() as Node3D
	_rig.name = "Visual"
	_rig.process_mode = Node.PROCESS_MODE_DISABLED
	_model = (load(MODEL) as PackedScene).instantiate() as Node3D
	_rig.add_child(_model)
	_root3d.add_child(_rig)   # ActorRig._ready: RigPaint.use_shadow_proxy(self)
	var sk := _model.find_children("*", "Skeleton3D", true, false)
	_holder = sk[0] if not sk.is_empty() else _model
	_out["stand_in"] = _rig.get("shadow_proxy") == null
	_out["rig_found_proxy_at_ready"] = _rig.get("shadow_proxy") != null
	var proxy := _holder.get_node_or_null(PROXY_NAME) as MeshInstance3D
	if proxy == null:
		var torso := _holder.get_node_or_null("Body_Torso") as MeshInstance3D
		proxy = torso.duplicate() as MeshInstance3D
		proxy.name = PROXY_NAME
		proxy.visible = false
		_holder.add_child(proxy)
	var shown := 0
	var surfaces := 0
	for mi in _meshes():
		if mi == proxy:
			mi.visible = false
			continue
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		if mi.visible and mi.mesh != null:
			shown += 1
			surfaces += mi.mesh.get_surface_count()
	_out["shown"] = shown
	_out["shown_surfaces"] = surfaces
	_out["proxy_surfaces"] = proxy.mesh.get_surface_count() if proxy.mesh != null else 0


func _note_casting() -> void:
	var names: Array = []
	for mi in _meshes():
		if mi.visible and mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			names.append(str(mi.name))
	names.sort()
	_out["casting"] = names
	var found := _rig.get("shadow_proxy") as MeshInstance3D
	_out["proxy_shadows_only"] = found != null and found.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY


## A copy of a small shown mesh joining the skeleton under `mesh_name`, as a part loaded on demand does.
func _join(mesh_name: String) -> void:
	var src := _holder.get_node_or_null("Eyes") as MeshInstance3D
	if src == null:
		src = _holder.get_node_or_null("Body_Head") as MeshInstance3D
	var mi := src.duplicate() as MeshInstance3D
	mi.name = mesh_name
	mi.visible = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_holder.add_child(mi)
	_out["join_surfaces"] = mi.mesh.get_surface_count()
