class_name CaptureTitan
extends RefCounted
## A2: the titan capture tour - --scenario=capture_titan on the quarry test arena films Stoneback's fight against a
## stage-5 giant, beat by beat, with a camera of its own, and saves a still at each moment the beats name
## (a2_NN_<moment>.png under user://captures or --capture-dir=): each telegraph and each strike, a plate breaking,
## the exposed weak point struck, the charge's reel against a rock, his rage (phase 2) and his fall. With
## --write-movie the same run is the fight's movie (the camera cuts at each beat):
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/a2_fight.avi] -- --no-user-settings --level=res://scenes/test/quarry_test.tscn \
##     --scenario=capture_titan --skin --capture-dir=<out>
##
## The tour drives the fight as a director would: Stoneback's AI is off and each beat forces his attack on the giant
## (CombatController.force_action, his brain's target the giant); the giant walks, dodges and swings through his
## input router; the plates break under synthetic heavy blows through the ordinary resolution (a region set, as a
## swing's hurtbox sets it), so every reaction - the stone, the stagger, the phase - is the game's own. The giant
## is healed every tick (his blows land and show their numbers, but never kill it). Headless the tour still runs every beat (no frame is drawn):
## AUTOPILOT_RESULT's "capture_titan" lists the shots, the notes (a beat the game refused) and what happened.

const STAGE := 5
const SHOT_PREFIX := "a2"

var _auto: Node = null
var _p: GiantPlayer = null
var _t: TitanEnemy = null
var _cam: Camera3D = null
var _beats: Array = []
var _i := -1
var _bt := 0.0
var _pending: Array = []      # the running beat's moments still to come: [time s or Callable, name, view]
var _view: Dictionary = {}
var _shot_n := 0
var shots: Array[String] = []
var notes := PackedStringArray()
## What the tour saw happen (tests, the report): breaks, phases, reels, the death, the loot.
var seen := {"plates": [], "phases": [], "reels": 0, "died": false, "loot": [], "strikes": []}
var done := false


func _init(autopilot: Node) -> void:
	_auto = autopilot
	_beats = _make_beats()
	Events.plate_broken.connect(_on_plate_broken)
	Events.boss_phase_changed.connect(_on_phase)
	Events.entity_died.connect(_on_died)
	Events.loot_awarded.connect(_on_loot)
	Events.ability_started.connect(_on_started)


func dispose() -> void:
	_beats.clear()
	_pending.clear()
	for pair: Array in [[Events.plate_broken, _on_plate_broken], [Events.boss_phase_changed, _on_phase],
			[Events.entity_died, _on_died], [Events.loot_awarded, _on_loot], [Events.ability_started, _on_started]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	if _cam != null and is_instance_valid(_cam):
		_cam.queue_free()
	_cam = null


func beat_names() -> PackedStringArray:
	var out := PackedStringArray()
	for b: Array in _beats:
		out.append(str(b[0]))
	return out


## One physics tick of the tour; true once it has ended.
func step(player: GiantPlayer, dt: float) -> bool:
	if done:
		return true
	_p = player
	_p.router.use_injection = true
	if _t == null:
		_t = player.get_tree().get_first_node_in_group(OgreBoss.GROUP) as TitanEnemy
		if _t == null:
			notes.append("no titan in the level (run it on scenes/test/quarry_test.tscn)")
			done = true
			return true
		_setup()
	_keep_alive()
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED   # (no "click the game" hint)
	if _i < 0 or _bt >= float(_beats[_i][1]):
		for m: Array in _pending:
			notes.append("%s: %s never came" % [str(_beats[_i][0]), str(m[1])])   # (A3: a moment the beat missed)
		_i += 1
		_bt = 0.0
		if _i >= _beats.size():
			done = true
			dispose()
			return true
		_release_inputs()
		_view = _beats[_i][3]
		_pending = (_beats[_i][4] as Array).duplicate()
		(_beats[_i][2] as Callable).call()
	_bt += dt
	var tick: Variant = _beats[_i][5] if (_beats[_i] as Array).size() > 5 else null
	if tick is Callable:
		(tick as Callable).call(_bt)
	_place_camera(_view)
	if not _pending.is_empty():
		var m: Array = _pending[0]
		var due: bool = (m[0] as Callable).call() if m[0] is Callable else _bt >= float(m[0])
		if due:
			_pending.pop_front()
			if (m as Array).size() > 2 and m[2] is Dictionary:
				_view = m[2]
				_place_camera(_view)
			_shot_n += 1
			var name := _shot_name(_shot_n, str(m[1]))
			if _auto != null and _auto.has_method("_shot"):
				_auto.call("_shot", name)
			shots.append(name)
	return false


## A shot's file name: a2_NN_<moment>.png (A3's tour names its own).
func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX, n, moment]


func _setup() -> void:
	var level := _p.get_parent()
	if level is TitanArenaTest:
		(level as TitanArenaTest).stage = 0   # (the tour readies the giant itself)
	TitanDuel.prepare(_p, STAGE)
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = false   # the stills show the fight, not the bars (main's HUD layer)
	_t.ai_enabled = false
	_t.brain.target_id = _p.entity.entity_id
	var arena := _p.get_tree().get_first_node_in_group(BossArena.GROUP) as BossArena
	if arena != null:
		arena.engage()


func _keep_alive() -> void:
	var pools := _p.entity.combatant.pools
	pools.health = pools.health_max
	pools.stamina = pools.stamina_max


func _release_inputs() -> void:
	_p.router.set_injected_move(Vector2.ZERO)
	for key: StringName in [&"block", &"sprint", &"heavy_modifier"]:
		_p.router.set_injected_hold(key, false)


# --------------------------------------------------------------------------- staging

## The titan at `at` facing `face_to`; the giant at `p_at` facing the titan.
func _stage(at: Vector3, face_to: Vector3, p_at: Vector3) -> void:
	_t.brain.face_point = face_to
	if _t.controller.action != null:
		_t.controller.call("_finish_action", true)
	_t.global_position = at
	_t.velocity = Vector3.ZERO
	_face(_t, face_to)
	_p.global_position = p_at
	_p.velocity = Vector3.ZERO
	_face(_p, at)
	_p.camera_rig.yaw = _p.facing_yaw


func _face(n: Node3D, to: Vector3) -> void:
	var d := to - n.global_position
	d.y = 0.0
	if d.length_squared() < 1e-4:
		return
	var yaw := atan2(-d.x, -d.z)
	n.rotation.y = yaw
	if "facing_yaw" in n:
		n.set("facing_yaw", yaw)


## A point `dist` m from the titan at `az` degrees from his facing (0 in front of him, + toward his right).
func _round_titan(az: float, dist: float) -> Vector3:
	var yaw := _t.facing_yaw + deg_to_rad(-az)
	return _t.global_position + Vector3(-sin(yaw), 0.0, -cos(yaw)) * dist


func _attack(id: String) -> void:
	var a := GameData.get_action(id)
	if a == null:
		notes.append("%s: no such action" % id)
		return
	_t.brain.target_id = _p.entity.entity_id
	_t.brain.face_point = _p.global_position   # (his AI is off: his turn follows the brain's last face point)
	_face(_t, _p.global_position)
	_t.controller.force_action(a)
	if _t.controller.action_id() != id:
		notes.append("%s was not started" % id)


## A heavy blow of the giant's that strikes `region` for `power` (the ordinary resolution: armour, the plate).
func _blow(region: String, power: float) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = _p.entity.entity_id
	e.target_id = _t.entity_id
	e.action_id = "capture.blow"
	e.power = power
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.attacker_height_m = _p.entity.combatant.height_m
	e.poise_damage = 40.0
	e.tags = PackedStringArray(["Melee", "Heavy"])
	e.region = region
	e.attacker_position = _p.global_position
	e.hit_point = _t.global_position + Vector3.UP * 12.0
	Sim.queue_hit(e)


func _swing() -> void:
	_p.entity.combatant.pools.stamina = _p.entity.combatant.pools.stamina_max
	_p.router.inject_edge(&"heavy")


func _dodge(dir: Vector2) -> void:
	_p.router.set_injected_move(dir)
	_p.router.inject_edge(&"dodge")


func _walk(dir: Vector2) -> void:
	_p.router.set_injected_move(dir)


func _running(id: String, phase: int, at: float) -> Callable:
	return func() -> bool:
		return _t.controller.action_id() == id and _t.controller.phase() == phase and _t.controller.phase_fraction() >= at


# --------------------------------------------------------------------------- the camera

## view: {"az": degrees round the titan from his facing (0 = before him), "dist", "h" (the camera's height), "look"
## (the height it looks at), "on": "titan" | "mid" (between the two) | "player"}.
func _place_camera(view: Dictionary) -> void:
	if _cam == null or not is_instance_valid(_cam):
		_cam = Camera3D.new()
		_cam.name = "CaptureTitanCamera"
		_cam.fov = 55.0
		_cam.far = 3000.0
		_p.get_tree().root.add_child(_cam)
	var on := str(view.get("on", "titan"))
	var centre := _t.global_position
	if on == "mid":
		centre = (_t.global_position + _p.global_position) * 0.5
	elif on == "player":
		centre = _p.global_position
	var yaw := _t.facing_yaw + deg_to_rad(-float(view.get("az", 30.0)))
	var dir := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var want := centre + dir * float(view.get("dist", 50.0)) + Vector3.UP * float(view.get("h", 8.0))
	var look := centre + Vector3.UP * float(view.get("look", 9.0))
	# a rock or the quarry wall between: the camera comes in front of it, as a spring arm does
	var q := PhysicsRayQueryParameters3D.create(look, want, HitQueryAdapter.LAYER_WORLD)
	var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		want = (hit.position as Vector3) + (look - want).normalized() * 1.0
	_cam.global_position = want
	_cam.look_at(look, Vector3.UP)
	_cam.make_current()


# --------------------------------------------------------------------------- the beats

## [name, seconds, start, view, moments [[time s | Callable, shot name, view?], ...], per-tick Callable?]
func _make_beats() -> Array:
	var wide := {"az": 25.0, "dist": 46.0, "h": 9.0, "look": 9.0, "on": "mid"}
	var side := {"az": -62.0, "dist": 36.0, "h": 6.0, "look": 9.0, "on": "mid"}
	return [
		["face_off", 3.0, func() -> void:
			_stage(Vector3(0, 0.05, -20), Vector3(0, 0, 20), Vector3(0, 0.05, 10))
			_walk(Vector2(0, -0.35)),
			wide, [[2.2, "face_off", {"az": 14.0, "dist": 44.0, "h": 5.0, "look": 10.0, "on": "player"}]]],
		["smash", 4.6, func() -> void:
			_stage(Vector3(0, 0.05, -20), Vector3(0, 0, 0), Vector3(0, 0.05, -2))
			_attack("ability.stoneback_smash"),
			side, [[_running("ability.stoneback_smash", ActionDef.Phase.WINDUP, 0.62), "smash_telegraph"],
				[_running("ability.stoneback_smash", ActionDef.Phase.ACTIVE, 0.15), "smash_strike"],
				[_running("ability.stoneback_smash", ActionDef.Phase.RECOVERY, 0.25), "smash_shock"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.05:
					_dodge(Vector2(1, 0))],
		["sweep", 4.0, func() -> void:
			_stage(Vector3(0, 0.05, -20), Vector3(0, 0, 0), Vector3(0, 0.05, -20) + Vector3(-15, 0, 4))
			_attack("ability.stoneback_sweep"),
			{"az": -35.0, "dist": 46.0, "h": 8.0, "look": 8.0, "on": "titan"},
			[[_running("ability.stoneback_sweep", ActionDef.Phase.WINDUP, 0.75), "sweep_telegraph"],
				[_running("ability.stoneback_sweep", ActionDef.Phase.ACTIVE, 0.4), "sweep_strike"]]],
		["boulder", 6.0, func() -> void:
			_stage(Vector3(0, 0.05, -30), Vector3(0, 0, 20), Vector3(0, 0.05, 20))
			_attack("ability.stoneback_boulder"),
			{"az": 40.0, "dist": 40.0, "h": 6.0, "look": 7.0, "on": "titan"},
			[[_running("ability.stoneback_boulder", ActionDef.Phase.WINDUP, 0.37), "boulder_rip"],
				[_running("ability.stoneback_boulder", ActionDef.Phase.WINDUP, 0.85), "boulder_throw",
					{"az": 70.0, "dist": 46.0, "h": 10.0, "look": 9.0, "on": "mid"}],
				[_running("ability.stoneback_boulder", ActionDef.Phase.RECOVERY, 0.35), "boulder_landing",
					{"az": 88.0, "dist": 46.0, "h": 16.0, "look": 4.0, "on": "mid"}]],
			func(t: float) -> void:
				if t > 1.4 and t < 1.45:
					_walk(Vector2(1, 0.4))],
		["charge", 7.0, func() -> void:
			_stage(Vector3(-14, 0.05, -6), Vector3(40, 0, -6), Vector3(12, 0.05, -6))
			_attack("ability.stoneback_charge"),
			{"az": 70.0, "dist": 46.0, "h": 7.0, "look": 8.0, "on": "mid"},
			[[_running("ability.stoneback_charge", ActionDef.Phase.WINDUP, 0.8), "charge_telegraph"],
				[_running("ability.stoneback_charge", ActionDef.Phase.ACTIVE, 0.12), "charge_run",
					{"az": 95.0, "dist": 44.0, "h": 6.0, "look": 8.0, "on": "titan"}],
				[func() -> bool: return _t.controller.action_id() == "ability.stoneback_reel" \
						and _t.controller.elapsed > 36, "charge_stagger",
					{"az": 150.0, "dist": 36.0, "h": 11.0, "look": 9.0, "on": "titan"}]],
			func(t: float) -> void:
				if t < 1.6:
					_p.global_position = Vector3(12, 0.05, -6)   # (he turns on the giant through his windup: hold it there)
				if t > 1.68 and t < 1.73:
					_dodge(Vector2(0, 1))],
		["plate_break", 3.4, func() -> void:
			# (in the open, whatever the charge left: he reels, his back to the giant)
			_stage(Vector3(0, 0.05, -12), Vector3(0, 0, 30), Vector3(0, 0.05, -12) + Vector3(0, 0, -14))
			_t.controller.force_action(GameData.get_action("ability.stoneback_reel")),
			{"az": 140.0, "dist": 34.0, "h": 14.0, "look": 11.0, "on": "titan"},
			[[0.7, "plate_break"], [2.3, "weak_point", {"az": 205.0, "dist": 26.0, "h": 16.0, "look": 13.0, "on": "titan"}]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23 and not _t.plates().is_broken("back"):
					_blow("back", 2600.0)
				if t > 1.55 and t < 1.58:
					_swing()
				if t > 2.15 and t < 2.18:
					_blow("back", 140.0)],
		["rage", 5.0, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_face(_t, _p.global_position)
			_blow("shoulder_l", 2600.0),
			{"az": 12.0, "dist": 38.0, "h": 3.5, "look": 12.0, "on": "titan"},
			[[func() -> bool: return _t.controller.action_id() == "ability.stoneback_roar" \
					and _t.controller.phase() == ActionDef.Phase.ACTIVE, "phase_two_roar"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					var front := _round_titan(0.0, 22.0)
					_p.global_position = Vector3(front.x, 0.05, front.z)
					_face(_p, _t.global_position)],
		["rage_chain", 5.0, func() -> void:
			_stage(_t.global_position, _p.global_position, _round_titan(-20.0, 16.0))
			_attack("ability.stoneback_smash_rage"),
			{"az": -22.0, "dist": 40.0, "h": 8.0, "look": 9.0, "on": "titan"},
			[[_running("ability.stoneback_smash_rage", ActionDef.Phase.ACTIVE, 0.2), "rage_smash"],
				[_running("ability.stoneback_sweep_rage", ActionDef.Phase.ACTIVE, 0.4), "rage_sweep"]]],
		["death", 6.0, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_stage(_t.global_position, _p.global_position, _round_titan(10.0, 18.0))
			_t.entity.combatant.pools.health = 40.0
			_swing(),
			{"az": 70.0, "dist": 46.0, "h": 6.0, "look": 7.0, "on": "titan"},
			[[1.7, "death_fall"], [4.6, "fallen", {"az": 40.0, "dist": 46.0, "h": 14.0, "look": 2.0, "on": "titan"}]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43 and _t.entity.is_alive():
					_blow("brow", 2000.0)],
	]


# --------------------------------------------------------------------------- what happened

func _on_plate_broken(_tick: int, entity_id: String, plate_id: String) -> void:
	if _t != null and entity_id == _t.entity_id:
		(seen.plates as Array).append(plate_id)


func _on_phase(_tick: int, boss_id: String, phase: int) -> void:
	if _t != null and boss_id == _t.entity_id:
		(seen.phases as Array).append(phase)


func _on_died(_tick: int, id: String, _killer: String) -> void:
	if _t != null and id == _t.entity_id:
		seen.died = true


func _on_loot(_tick: int, _world_id: String, item: String, count: int, _recipient: String) -> void:
	(seen.loot as Array).append("%s x%d" % [item, count])


func _on_started(_tick: int, actor_id: String, action_id: String, _instance: int) -> void:
	if _t != null and actor_id == _t.entity_id:
		(seen.strikes as Array).append(action_id)
		if action_id == "ability.stoneback_reel":
			seen.reels = int(seen.reels) + 1


func result() -> Dictionary:
	return {"shots": shots, "notes": notes, "complete": done, "seen": seen}
