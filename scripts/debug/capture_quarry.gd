class_name CaptureQuarry
extends CaptureTitan
## A3: the quarry capture tour - --scenario=capture_quarry in the real world films Stoneback at his quarry beside
## Millford and saves a still at each moment the beats name (a3_NN_<moment>.png under user://captures or
## --capture-dir=): his height beside the giant at stages 3, 5 and 6 (orthographic side views: the heights as they
## are), the quarry from beyond Millford, his walk out of the quarry after the giant (his AI and his territory),
## each attack on the quarry's floor, the charge broken on a standing stone, a cracked plate, a broken one, his
## death with the trunk falling from his fist, and the reopened quarry and Millford after:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/a3_world.avi] -- --no-user-settings --mode=world --start=world.cp.millford \
##     --scenario=capture_quarry --skin --capture-dir=<out>
##
## As CaptureTitan's tour (whose staging, strikes and camera it shares): his AI is off but in the walk-out, each
## beat forces his attack, the giant is healed every tick, the plates break under synthetic heavy blows through the
## ordinary resolution. The HUD and the damage numbers are hidden. AUTOPILOT_RESULT's "capture_quarry" lists the shots
## and the notes (a moment a beat missed).

const SHOT_PREFIX_A3 := "a3"
const STONEBACK_ID := "world.crownmarch.stoneback"
## The quarry pit's floor (10.5 m), its centre and the standing stone the charge is baited into.
const FLOOR_Y := 10.5
const CENTRE := Vector3(-600, FLOOR_Y, 452)
const STONE := Vector3(-622, FLOOR_Y, 440)
## The giant's place before the tour (the Woodway, out of his sight) and where he sights it.
const WAIT_AT := Vector3(-452, 8.3, 520)
const SIGHTED_AT := Vector3(-525, 11.0, 486)
## The fight's cameras on the quarry's floor: from its open side (north-east, east and north: the mouth, where no
## stone or cut face stands between) and behind him at the mouth; each over its own ground by 4-20 m.
const CAM_NE := {"at": Vector3(-562, 24, 488), "look": Vector3(-596, 17, 452), "fov": 52.0}
const CAM_N := {"at": Vector3(-592, 20, 492), "look": Vector3(-596, 15, 452), "fov": 52.0}
const CAM_NE_HIGH := {"at": Vector3(-560, 36, 492), "look": Vector3(-598, 10, 452), "fov": 52.0}
const CAM_E := {"at": Vector3(-546, 23, 452), "look": Vector3(-595, 15, 455), "fov": 52.0}
const CAM_N_WIDE := {"at": Vector3(-588, 26, 498), "look": Vector3(-596, 12, 442), "fov": 62.0}
const CAM_BACK := {"at": Vector3(-600, 27, 482), "look": Vector3(-600, 22, 452), "fov": 45.0}

var _waited := 0.0
var _ready_done := false
var _world: WorldRoot = null


func _init(autopilot: Node) -> void:
	super(autopilot)


func step(player: GiantPlayer, dt: float) -> bool:
	if done:
		return true
	if not _ready_done:
		_p = player
		_p.router.use_injection = true
		if _world == null:
			_world = player.get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot
			if _world == null:
				notes.append("no world (run it with --mode=world --start=world.cp.millford)")
				done = true
				return true
			_go(WAIT_AT)
		_keep_alive()
		_waited += dt
		var d := player.get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector
		_t = d.spawned(STONEBACK_ID) as TitanEnemy if d != null else null
		if _t == null:
			if _waited > 30.0:
				notes.append("Stoneback never came (his encounter: encounter.crownmarch_stoneback)")
				done = true
				return true
			return false
		_setup()
		_ready_done = true
		titan_found = true
	return super(player, dt)


func _setup() -> void:
	TitanDuel.prepare(_p, 5)
	Settings.set_value("damage_numbers", false, false)   # (the stills show the fight, not its numbers)
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = false
	_t.ai_enabled = false
	_t.brain.target_id = _p.entity.entity_id


## The giant moved to `at` on the ground, the streaming ring around it loaded (a fast travel).
func _go(at: Vector3) -> void:
	if _world == null:
		return
	var guard := 0
	while not _world.streamer.ring_ready(at) and guard < 400:
		_world.streamer.load_ring_slice(at)
		guard += 1
	var y := _world.height_at(at)
	_p.global_position = Vector3(at.x, (y if not is_nan(y) else at.y) + 0.05, at.z)
	_p.velocity = Vector3.ZERO


func _grow(stage: int) -> void:
	TitanDuel.prepare(_p, stage)


## The pit's floor at (x, z).
func _floor(x: float, z: float) -> Vector3:
	var y := _world.height_at(Vector3(x, 0, z)) if _world != null else FLOOR_Y
	return Vector3(x, (y if not is_nan(y) else FLOOR_Y) + 0.05, z)


## The titan and the giant side by side on the pit's floor, facing each other along x, for the orthographic view.
func _side_by_side() -> void:
	_stage(_floor(-596, 458), _floor(-582, 458), _floor(-582, 458))
	_p.global_position = _floor(-582, 458)


# --------------------------------------------------------------------------- the camera

## view (CaptureTitan's) or {"at": Vector3, "look": Vector3, "fov"} (a fixed camera) or {"ortho": size, "at", "look"}.
func _place_camera(view: Dictionary) -> void:
	if not view.has("at") and not is_instance_valid(_t):
		return   # (his body freed after his death: the views round him are over)
	if not view.has("at"):
		if _cam != null and is_instance_valid(_cam):
			_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			_cam.fov = 55.0
		super(_clear_view(view))
		return
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.name = "CaptureQuarryCamera"
		_cam.far = 3000.0
		_p.get_tree().root.add_child(_cam)
	if view.has("ortho"):
		_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		_cam.size = float(view.ortho)
	else:
		_cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		_cam.fov = float(view.get("fov", 55.0))
	_cam.global_position = view.at as Vector3
	_cam.look_at(view.look as Vector3, Vector3.UP)
	_cam.make_current()


## The view turned round the titan (25, 50, ... degrees either way) until nothing of the world stands between the
## camera and what it looks at - a standing stone or a cut face (CaptureTitan's camera would come in front of it,
## against the stone).
func _clear_view(view: Dictionary) -> Dictionary:
	if not is_instance_valid(_t) or _p == null:
		return view
	var on := str(view.get("on", "titan"))
	var centre := _t.global_position
	if on == "mid":
		centre = (_t.global_position + _p.global_position) * 0.5
	elif on == "player":
		centre = _p.global_position
	var look := centre + Vector3.UP * float(view.get("look", 9.0))
	var space := _p.get_world_3d().direct_space_state
	for k in [0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6, -6, 7]:
		var az := float(view.get("az", 30.0)) + 25.0 * float(k)
		var yaw := _t.facing_yaw + deg_to_rad(-az)
		var want := centre + Vector3(-sin(yaw), 0.0, -cos(yaw)) * float(view.get("dist", 50.0)) \
			+ Vector3.UP * float(view.get("h", 8.0))
		var q := PhysicsRayQueryParameters3D.create(look, want, HitQueryAdapter.LAYER_WORLD)
		if space.intersect_ray(q).is_empty():
			var out := view.duplicate()
			out["az"] = az
			return out
	return view


# --------------------------------------------------------------------------- the beats

func _make_beats() -> Array:
	# the side views: on the pit's level floor, the camera 26 m to the north of the pair (nothing between), level
	# with 11.5 m over the floor, orthographic (no perspective: the heights as they are; the frame's foot at the
	# floor); the standing stones and the cut faces behind them
	var side_at := Vector3(-589, FLOOR_Y + 11.5, 484)
	var side_look := Vector3(-589, FLOOR_Y + 11.5, 458)
	var side := {"at": side_at, "look": side_look, "ortho": 24.0}
	var wide := {"az": 25.0, "dist": 50.0, "h": 9.0, "look": 9.0, "on": "mid"}
	return [
		["height_3", 3.0, func() -> void:
			_grow(3)
			_side_by_side(),
			side, [[2.6, "height_stage3"]], func(_t: float) -> void: _side_by_side()],
		["height_5", 3.0, func() -> void:
			_grow(5)
			_side_by_side(),
			side, [[2.6, "height_stage5"]], func(_t: float) -> void: _side_by_side()],
		["height_6", 3.0, func() -> void:
			_grow(6)
			_side_by_side(),
			side, [[2.6, "height_stage6"]], func(_t: float) -> void: _side_by_side()],
		["afar", 2.5, func() -> void:
			_grow(5)
			_stage(_floor(-606, 456), _floor(-560, 476), _floor(-380, 625)),
			{"at": Vector3(-300, 64, 735), "look": Vector3(-560, 14, 470), "fov": 50.0}, [[2.0, "quarry_from_millford"]]],
		["walk_out", 11.0, func() -> void:
			_stage(_floor(-606, 456), _floor(-560, 476), SIGHTED_AT)
			_go(SIGHTED_AT)
			_t.ai_enabled = true
			_t.brain.on_noise(Sim.tick, _p.global_position, _p.entity.entity_id, true),
			{"at": Vector3(-548, 34, 418), "look": Vector3(-585, 14, 472), "fov": 50.0},
			[[6.5, "walks_out", {"az": 60.0, "dist": 55.0, "h": 10.0, "look": 9.0, "on": "titan"}]],
			func(t: float) -> void:
				_p.global_position = SIGHTED_AT if t < 9.0 else _p.global_position],
		["smash", 4.6, func() -> void:
			_t.ai_enabled = false
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-586, 452))
			_attack("ability.stoneback_smash"),
			CAM_NE, [[_running("ability.stoneback_smash", ActionDef.Phase.WINDUP, 0.5), "smash_telegraph"],
				[_running("ability.stoneback_smash", ActionDef.Phase.ACTIVE, 0.15), "smash_strike", CAM_N]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.05:
					_dodge(Vector2(1, 0))],
		["sweep", 4.0, func() -> void:
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-598, 465))
			_attack("ability.stoneback_sweep"),
			CAM_NE, [[_running("ability.stoneback_sweep", ActionDef.Phase.ACTIVE, 0.3), "sweep_strike"]]],
		["boulder", 6.0, func() -> void:
			_stage(_floor(-608, 448), _floor(-575, 468), _floor(-572, 470))
			_attack("ability.stoneback_boulder"),
			CAM_E, [[_running("ability.stoneback_boulder", ActionDef.Phase.WINDUP, 0.37), "boulder_rip"],
				[_running("ability.stoneback_boulder", ActionDef.Phase.RECOVERY, 0.3), "boulder_landing", CAM_NE_HIGH]],
			func(t: float) -> void:
				if t > 1.4 and t < 1.45:
					_walk(Vector2(1, 0.4))],
		["charge", 7.5, func() -> void:
			# he faces west across the pit, the giant between him and the standing stone (-622, 440)
			_stage(_floor(-568, 452), _floor(-622, 440), _floor(-600, 445))
			_t.brain.on_noise(Sim.tick, _p.global_position, _p.entity.entity_id, true)
			_attack("ability.stoneback_charge"),
			CAM_N_WIDE, [[_running("ability.stoneback_charge", ActionDef.Phase.WINDUP, 0.8), "charge_telegraph"],
				[_running("ability.stoneback_charge", ActionDef.Phase.ACTIVE, 0.06), "charge_run"],
				[func() -> bool: return _t.controller.action_id() == "ability.stoneback_reel" \
						and _t.controller.elapsed > 30, "charge_reel_on_stone"]],
			func(t: float) -> void:
				if t < 1.38:
					_p.global_position = _floor(-600, 445)
				if t > 1.45 and t < 1.5:
					_dodge(Vector2(1, 0))
				elif t > 1.8 and t < 3.0:
					_walk(Vector2(1, 0))],
		["crack", 3.0, func() -> void:
			# his back to the camera at the quarry's mouth
			_stage(_floor(-600, 452), _floor(-600, 420), _floor(-600, 432))
			_t.controller.force_action(GameData.get_action("ability.stoneback_reel")),
			CAM_BACK, [[1.6, "plate_cracked"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("back", 340.0)],
		["break", 3.2, func() -> void:
			_blow("back", 2600.0),
			CAM_BACK, [[0.5, "plate_breaking"], [2.6, "plate_broken"]]],
		["death", 6.0, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_stage(_floor(-604, 452), _floor(-584, 452), _floor(-586, 456))
			_t.entity.combatant.pools.health = 40.0,
			CAM_NE, [[1.25, "death_trunk_falling"], [4.4, "fallen", CAM_NE_HIGH]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("brow", 2000.0)],
		["leave", 1.0, func() -> void:
			_go(Vector3(-380, 8.1, 625)),   # (the giant goes on beyond his line: the quarry reopens behind it)
			{"at": Vector3(-330, 30, 545), "look": Vector3(-375, 10, 610), "fov": 55.0}, []],
		["reopened", 6.0, func() -> void:
			_go(Vector3(-538, 11, 482)),
			{"at": Vector3(-545, 40, 515), "look": Vector3(-605, 14, 452), "fov": 55.0},
			[[5.5, "quarry_reopened"]]],
		["millford_after", 4.0, func() -> void:
			_go(Vector3(-372, 8.1, 600)),
			{"at": Vector3(-352, 44, 566), "look": Vector3(-374, 8, 606), "fov": 58.0},
			[[3.5, "millford_after"]]],
	]


func beat_names() -> PackedStringArray:
	return super()


## The shots' names: a3_NN_<moment>.png.
func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_A3, n, moment]
