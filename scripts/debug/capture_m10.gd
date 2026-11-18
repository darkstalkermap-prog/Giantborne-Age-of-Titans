class_name CaptureM10
extends RefCounted
## The M10 capture tour (P43; plan M10 §3.3 item 7): --scenario=capture_m10 shows the realistic giant in
## every state the plan lists, one beat after another, and saves a frame of each (m10_NN_<beat>.png under
## user://captures or --capture-dir=). Run it with a display and the skinned layers, and --write-movie for
## the owner's video:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     --write-movie <out>/m10_tour.avi -- --no-user-settings --scenario=capture_m10 --skin
##
## The beats: idle, walk, run, sprint, a jump; the light and the heavy of the club, the sword, the hammer
## and the axe (stage 1), the tree's light (stage 3), the fists (stage 4, their required stage) and the
## pine's heavy (stage 5); a block; a roll and a
## sidestep; Shoulder Charge; a grab, hold and throw of the arena's soldier; Heavy Footfall (the stomp);
## Thunder Roar; Stone Skin (a self buff); a stagger; a knockback; stages 1 to 6 with Earthquake at 6; first
## person looking down and ahead; the death fall. A beat that the game refuses (a weapon a stage cannot
## carry, an ability on cooldown) is noted in `notes` and the tour goes on. The tour drives the giant
## through its input router, its debug growth and, for the stagger, the knockback and the death, the
## same synthetic hits and calls the tests use: it is a capture tool, never part of a soak.
##
## M10 gate (LC-7): the tour holds the mouse captured, as a player's is while they play (tools/valley_tour.gd
## does the same): the HUD otherwise lays "Click the game to control the camera" across the giant in every
## third-person frame and through the whole video. `mouse_mode_asked` is the mode the last step asked for.

const CAST_SLOT := "slot_3"

var _auto: Node = null
var _p: GiantPlayer = null
var _beats: Array = []
var _names := PackedStringArray()
var _i := -1
var _t := 0.0
var _shot_done := false
var shots: Array[String] = []
var notes := PackedStringArray()
var done := false
## The mouse mode the last step asked for (-1 before the first step): Input.MOUSE_MODE_CAPTURED.
var mouse_mode_asked := -1
## The ability the running beat cast and the controller has not started yet ("" once it ran).
var _expect := ""


func _init(autopilot: Node) -> void:
	_auto = autopilot
	_beats = _make_beats()
	for b: Array in _beats:
		_names.append(str(b[0]))


## Lets go of the beats: their lambdas hold this object, so it is freed only once they are gone (the tour
## clears them when it ends; the autopilot calls this when the run ends before the tour does).
func dispose() -> void:
	_beats.clear()


## One physics tick of the tour; true once it has ended.
func step(player: GiantPlayer, dt: float) -> bool:
	if done:
		return true
	_p = player
	_p.router.use_injection = true
	_hold_mouse()
	if _i < 0 or _t >= float(_beats[_i][1]):
		_i += 1
		_t = 0.0
		_shot_done = false
		if _i >= _beats.size():
			done = true
			dispose()
			return true
		_release_inputs()
		_expect = ""
		var start: Callable = _beats[_i][2]
		start.call()
	_t += dt
	var at := float(_beats[_i][3])
	if _expect != "" and _p.controller.action != null and _p.controller.action.id == _expect:
		_expect = ""   # the beat's cast ran
	if not _shot_done and at >= 0.0 and _t >= at * float(_beats[_i][1]):
		_shot_done = true
		if _expect != "":
			# M10 gate (LC-7's aside): a cast the game refused leaves the beat's frame without its ability; say so.
			notes.append("%s: %s was not cast by the shot" % [str(_beats[_i][0]), _expect])
			_expect = ""
		var name := "m10_%02d_%s.png" % [_i + 1, str(_beats[_i][0])]
		if _auto != null and _auto.has_method("_shot"):
			_auto.call("_shot", name)
		shots.append(name)
	return false


## A player's mouse is captured while they play; the autopilot never captures it, so the tour does, every
## tick (a lost focus or a screen that freed it would bring the HUD's click hint back into the frames).
func _hold_mouse() -> void:
	mouse_mode_asked = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## The labels of the beats in order (docs, tests).
func beat_names() -> PackedStringArray:
	return _names


func _release_inputs() -> void:
	_p.router.set_injected_move(Vector2.ZERO)
	for key: StringName in [&"block", &"sprint", &"heavy_modifier"]:
		_p.router.set_injected_hold(key, false)


func _equip(id: String) -> void:
	var r: Dictionary = _p.equipment.grant_weapon(id, true)
	if not bool(r.get("ok", false)):
		notes.append("%s refused (%s)" % [id, r.get("reason", "?")])


func _cast(id: String) -> void:
	_expect = id
	_p.set_loadout_slot(CAST_SLOT, id)
	var pools := _p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	_p.controller.cooldowns.clear()
	_p.router.inject_edge(StringName(CAST_SLOT))


## The throw of what the hand holds, as a light or a heavy while holding makes it (PlayerGrab.try_throw).
## M10 gate (LC-7's aside): the beat cast ability.throw_held through a loadout slot, which the game refuses,
## so the giant kept the soldier in his hand and the stomp, the roar and Stone Skin after it were refused
## too: the frames 20 to 23 of the merge's tour showed him standing with "[E] Put down".
func _throw() -> void:
	var pools := _p.entity.combatant.pools
	pools.stamina = pools.stamina_max
	_expect = _p.grab.throw_id()
	if _p.grab.try_throw() != CombatController.Verdict.ACCEPT:
		notes.append("throw refused (%s)" % str(_p.controller.last_reject_reason))


func _light() -> void:
	_p.entity.combatant.pools.stamina = _p.entity.combatant.pools.stamina_max
	_p.router.inject_light_attack()


func _heavy() -> void:
	_p.entity.combatant.pools.stamina = _p.entity.combatant.pools.stamina_max
	_p.router.inject_edge(&"heavy")


func _stage(n: int) -> void:
	var r: Variant = _p.growth.debug_set_stage(n)
	if typeof(r) == TYPE_DICTIONARY and not bool((r as Dictionary).get("ok", false)):
		notes.append("stage %d refused (%s: %s)" % [n, (r as Dictionary).get("reason", "?"), (r as Dictionary).get("message", "")])


func _view(yaw_deg: float, pitch_deg: float) -> void:
	_p.camera_rig.yaw = _p.rotation.y + deg_to_rad(yaw_deg)
	_p.camera_rig.pitch = deg_to_rad(pitch_deg)


func _soldier() -> EnemyActor:
	var best: EnemyActor = null
	for n in _p.get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyActor
		if e != null and is_instance_valid(e) and e.entity != null and e.entity.is_alive() \
				and (best == null or e.global_position.distance_to(_p.global_position) < best.global_position.distance_to(_p.global_position)):
			best = e
	return best


func _hit_self(power: float) -> void:
	_hit(_p.entity.entity_id, power)


## The arena's soldiers fall (a synthetic hit each): the one the giant threw gets up and walks back to him,
## and an actor beside the giant refuses every growth after it ("Soldier is in the way").
func _clear_soldiers() -> void:
	for n in _p.get_tree().get_nodes_in_group("enemies"):
		var e := n as EnemyActor
		if e != null and is_instance_valid(e) and e.entity != null and e.entity.is_alive():
			_hit(e.entity.entity_id, 50000.0)


func _hit(target_id: String, power: float) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "capture"
	e.target_id = target_id
	e.power = power
	e.attacker_stat = 10.0
	e.attacker_height_m = 1.8
	e.damage_split = {"physical": 1.0}
	e.poise_damage = 5.0
	e.tags = PackedStringArray(["Melee", "Unblockable"])
	e.attacker_position = _p.global_position - _p.global_transform.basis.z * 2.0
	Sim.queue_hit(e)


## [label, seconds, start, shot at this share of the beat (-1: none)]
func _make_beats() -> Array:
	var b: Array = []
	b.append(["idle", 2.5, func() -> void: _view(35.0, -12.0), 0.7])
	b.append(["walk", 2.5, func() -> void:
		_view(0.0, -12.0)
		_p.router.set_injected_move(Vector2(0.0, 0.55)), 0.7])
	b.append(["run", 2.5, func() -> void: _p.router.set_injected_move(Vector2(0.0, 1.0)), 0.7])
	b.append(["sprint", 2.5, func() -> void:
		_p.router.set_injected_move(Vector2(0.0, 1.0))
		_p.router.set_injected_hold(&"sprint", true), 0.7])
	b.append(["jump", 1.6, func() -> void: _p.router.inject_edge(&"jump"), 0.25])
	for w: Array in [["club", "weapon.club"], ["sword", "weapon.sword"], ["hammer", "weapon.hammer"],
			["axe", "weapon.axe"]]:
		var id: String = w[1]
		b.append(["%s_light" % w[0], 1.4, func() -> void:
			_equip(id)
			_view(50.0, -10.0)
			_light(), 0.35])
		b.append(["%s_heavy" % w[0], 2.2, func() -> void: _heavy(), 0.45])
	b.append(["block", 1.5, func() -> void:
		_equip("weapon.club")
		_p.router.set_injected_hold(&"block", true)
		_p.router.inject_edge(&"block_press"), 0.6])
	b.append(["dodge_roll", 1.4, func() -> void:
		_p.router.inject_edge(&"block_release")
		_p.router.set_injected_move(Vector2(1.0, 0.0))
		_p.router.inject_edge(&"dodge"), 0.3])
	b.append(["dodge_sidestep", 1.4, func() -> void:
		_p.router.set_injected_move(Vector2(-1.0, 0.0))
		_p.router.inject_edge(&"dodge"), 0.3])
	b.append(["shoulder_charge", 2.2, func() -> void:
		_view(70.0, -10.0)
		_cast("ability.shoulder_charge"), 0.3])
	b.append(["grab", 2.5, func() -> void:
		var s := _soldier()
		if s == null:
			notes.append("grab: no soldier")
			return
		_p.global_position = s.global_position + (s.global_transform.basis.z * 2.4)
		_p.look_at(s.global_position, Vector3.UP)
		s.entity.stagger(3.0, "capture")
		_p.grab.hold_timeout_s = 30.0
		if _p.grab.try_grab() != CombatController.Verdict.ACCEPT:
			notes.append("grab refused"), 0.8])
	b.append(["hold", 2.0, func() -> void: _view(40.0, -8.0), 0.5])
	b.append(["throw", 2.0, func() -> void: _throw(), 0.3])
	b.append(["stomp", 2.0, func() -> void: _cast("ability.heavy_footfall"), 0.35])
	b.append(["roar", 2.2, func() -> void: _cast("ability.thunder_roar"), 0.4])
	b.append(["self_buff", 2.0, func() -> void: _cast("ability.stone_skin"), 0.4])
	b.append(["stagger", 1.6, func() -> void:
		_clear_soldiers()
		_p.entity.stagger(1.0, "capture"), 0.3])
	b.append(["knockback", 1.6, func() -> void: _p.apply_knockback(_p.global_transform.basis.z, 9.0), 0.25])
	for n in [2, 3, 4, 5, 6]:
		var stage: int = n
		b.append(["stage_%d" % stage, 2.4, func() -> void:
			_stage(stage)
			_view(35.0, -14.0), 0.8])
		if stage == 3:
			b.append(["tree_light", 1.6, func() -> void:
				_equip("weapon.tree_oak")
				_light(), 0.4])
		if stage == 4:
			b.append(["fists_light", 1.4, func() -> void:
				_equip("weapon.fists")
				_light(), 0.35])
			b.append(["fists_heavy", 2.2, func() -> void: _heavy(), 0.45])
		if stage == 5:
			b.append(["pine_heavy", 2.4, func() -> void:
				_equip("weapon.tree_pine")
				_heavy(), 0.45])
		if stage == 6:
			b.append(["earthquake", 2.6, func() -> void: _cast("ability.earthquake"), 0.45])
	b.append(["first_person_ahead", 1.6, func() -> void:
		_stage(1)
		_equip("weapon.club")
		_p.camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON, false)
		_view(0.0, 0.0), 0.7])
	b.append(["first_person_down", 1.6, func() -> void:
		_view(0.0, -70.0)
		_light(), 0.5])
	b.append(["death", 3.0, func() -> void:
		_p.camera_rig.set_mode(CameraRig.Mode.THIRD_PERSON, false)
		_view(60.0, -12.0)
		_hit_self(50000.0), 0.85])
	return b
