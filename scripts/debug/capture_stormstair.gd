class_name CaptureStormstair
extends CaptureKeep
## D2: the Stormcaller's capture tour - --scenario=capture_stormstair in the real world films him on the Stormstair at
## the top of the Drowned Steps and saves a still at each moment the beats name (d2_NN_<moment>.png under
## user://captures or --capture-dir=): the approach from the warning post, the Bellmere from a stage-8 giant's eye with
## him asleep on its north shore, his wake, each of his strikes (the rod's slam, its sweep, the gust, the called bolts
## and their water ringing, the stamp, his second phase's roar and its chain of bolts, his last phase's ring), the
## storm's rule on the giant (the HUD's water meter and its warning, the shock through the water) and its counterplay
## (lured deep into his own water, his own bolt grounds him: the heavy into him while he kneels), his plates broken
## (the bell on his back, the crown, the lodestone, a greave - he goes down), his death, the storm clearing over the
## Steps, Last Hearth's lodestone, the Stormcaller set on the giant, front and back, and the Character menu's Titans
## tab:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/stormcaller_tour.avi] -- --no-user-settings --mode=world --start=world.cp.bell_tower \
##     --scenario=capture_stormstair --skin --capture-dir=<out> [--d2-beats=a,b,...]
##
## As CaptureKeep's tour: his AI is off, each beat forces his attack, the giant (stage 8) is healed every tick, the
## plates break under synthetic heavy blows through the ordinary resolution. His AI being off, the tour strikes his
## called bolts itself when they fall due (as his hazard step would: the bolt's pulse, then the storm's strike through
## the water). The HUD is hidden but in the water's beats.

const SHOT_PREFIX_D2 := "d2"
const STORM_ID := "world.drowned.stormcaller"
const S_HOME := Vector3(-96, 27.1, -428)
const S_YAW_DEG := 180.0
const S_WAIT := Vector3(-104, 16.0, -262)
const WARNING := Vector3(-104, 16.0, -272)
const BELLMERE := Vector3(-100, 18.2, -392)
const STEPMERE := Vector3(-48, 14.0, -308)
const HEARTH_TROPHY := Vector3(-240, 180.0, -1302)
## Where the giant shows the set: the lower terrace between the pools.
const SET_AT := Vector3(-104, 0.0, -348)

## His called bolts the tour strikes itself: [due tick, point, action id].
var _bolts: Array = []
var _flags_set := false


func _titan_id() -> String:
	return STORM_ID


func _wait_at() -> Vector3:
	return S_WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_D2, n, moment]


func step(player: GiantPlayer, dt: float) -> bool:
	if not _flags_set:
		_flags_set = true
		# (act two: he stands on the Stormstair from it; act one written over quietly, as C1's tour does)
		WorldState.set_flag("act.two.begun", true)
		WorldState.flags["campaign.completed"] = true
		GameSession.expansion["act"] = 2
	if _ready_done:
		_strike_due()
	return super(player, dt)


func _setup() -> void:
	super()
	TitanDuel.prepare(_p, CaptureKeep.capture_stage(8))   # (D3: --capture-stage=9 films him against a stage-9 giant)
	_t.ai_enabled = false
	if not Events.telegraph_started.is_connected(_on_bolt_called):
		Events.telegraph_started.connect(_on_bolt_called)


func dispose() -> void:
	if Events.telegraph_started.is_connected(_on_bolt_called):
		Events.telegraph_started.disconnect(_on_bolt_called)
	super()


## A bolt of his called (its telegraph): the tour strikes it when it falls due.
func _on_bolt_called(tick: int, _key: String, action_id: String, _target: String, _shape: String, origin: Vector3,
		_yaw: float, _radius: float, _length: float, duration_s: float) -> void:
	var a := GameData.get_action(action_id)
	if a == null or not bool(a.param("storm_bolt", false)):
		return
	_bolts.append([tick + int(duration_s * Sim.TICK_RATE), origin, action_id])


func _strike_due() -> void:
	if not is_instance_valid(_t) or not _t.entity.is_alive():
		_bolts.clear()
		return
	for b: Array in _bolts.duplicate():
		if Sim.tick >= int(b[0]):
			_bolts.erase(b)
			var a := GameData.get_action(str(b[2]))
			_t.runner.p34_hazard_pulse(a, b[1] as Vector3, Sim.tick)
			_t.storm_strike(b[1] as Vector3, Sim.tick)


## His home on the Bellmere's north shore, the giant `d` m before him (toward the pools), facing him; `az` turns the
## giant round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	_face_off_at(_floor(S_HOME.x, S_HOME.z), d, az)


## As _face_off, he at `home` facing `yaw_deg` (his home's facing when none).
func _face_off_at(home: Vector3, d: float, az := 0.0, yaw_deg := S_YAW_DEG) -> void:
	var yaw := deg_to_rad(yaw_deg)
	var front := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var turned := front.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + front * 10.0, at)


## A fixed camera `off` from his home's ground (south of it: +z, over the pools), looking at `look_h` m over it.
func _cam_at(off: Vector3, look_h: float, fov: float) -> Dictionary:
	var g := Vector3(S_HOME.x, S_HOME.y, S_HOME.z)
	return {"at": g + off, "look": g + Vector3(0.0, look_h, 0.0), "fov": fov}


## The set's camera `side` (1 before him, -1 behind) 44 m off along z, 15 m over the ground there, at his middle.
func _set_view(side: float) -> Dictionary:
	var g := _floor(SET_AT.x, SET_AT.z)
	var c := _floor(SET_AT.x + 8.0 * side, SET_AT.z + 44.0 * side)
	return {"at": Vector3(c.x, maxf(c.y, g.y) + 15.0, c.z), "look": g + Vector3(0, 14.0, 0), "fov": 55.0}


## Up off his knee at once (a down left by the beat before: the tour's next blow wants him standing).
func _stand() -> void:
	if _t.is_down():
		_t.call("_end_down", false)


func _depth(at: Vector3) -> float:
	return StormWater.depth_at(_p.get_tree(), at)


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--d2-beats="):
			only = arg.substr(11)
	var all := _d2_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


## The HUD shown (the water's beats: the water meter) or hidden again.
func _ui_hud(on: bool) -> void:
	if _ui_layer != null:
		_ui_layer.visible = on


func _d2_beats() -> Array:
	var wide := {"az": 30.0, "dist": 78.0, "h": 22.0, "look": 16.0, "on": "mid"}
	var side := {"az": -80.0, "dist": 70.0, "h": 16.0, "look": 16.0, "on": "mid"}
	var high := {"az": 35.0, "dist": 74.0, "h": 46.0, "look": 8.0, "on": "mid"}
	var close := {"az": 20.0, "dist": 44.0, "h": 22.0, "look": 24.0, "on": "titan"}
	var behind := {"az": 165.0, "dist": 46.0, "h": 26.0, "look": 22.0, "on": "titan"}
	var giant_eye := func(back := 8.0) -> Dictionary:
		var to := (_t.global_position - _p.global_position)
		to.y = 0.0
		to = to.normalized() if to.length() > 0.1 else Vector3.FORWARD
		var h := _p.entity.combatant.height_m
		return {"at": _p.global_position - to * back + Vector3.UP * (h * 0.95),
			"look": _t.global_position + Vector3.UP * 18.0, "fov": 62.0}
	return [
		["approach", 3.5, func() -> void:
			_go(WARNING + Vector3(0, 0, 14))
			_face(_p, BELLMERE),
			{"at": WARNING + Vector3(-34, 42, 52), "look": BELLMERE + Vector3(0, 18, 40), "fov": 58.0},
			[[3.0, "approach_the_stormstair_from_the_warning_post"]]],
		["pools", 4.0, func() -> void:
			_go(Vector3(-96, 0, -332))
			_face(_p, S_HOME),
			{"at": Vector3(-30, 70, -300), "look": Vector3(-96, 22, -400), "fov": 60.0},
			[[1.2, "the_stormstair_wide"], [3.5, "the_bellmere_from_a_giants_eye", {}]],
			func(t: float) -> void:
				if t > 3.0 and t < 3.04:
					_view = giant_eye.call()],
		["wake", 6.0, func() -> void:
			_face_off(52.0)
			if _t.dormant:
				_t.wake("struck")
			_t.ai_enabled = false,
			close, [[1.4, "wake_rising_rod_in_hand"], [3.4, "wake_roar_the_storm_answers", wide],
				[5.6, "wake_giants_eye"]],
			func(t: float) -> void:
				if t > 5.3 and t < 5.34:
					_view = giant_eye.call()],
		["slam", 4.5, func() -> void:
			_face_off(22.0)
			_attack("ability.stormcaller_slam"),
			side, [[_running("ability.stormcaller_slam", ActionDef.Phase.WINDUP, 0.6), "slam_rod_raised_telegraph"],
				[_running("ability.stormcaller_slam", ActionDef.Phase.ACTIVE, 0.4), "slam_strike"]],
			func(t: float) -> void:
				if t > 1.1 and t < 1.14:
					_dodge(Vector2(1, 0))],
		["sweep", 4.0, func() -> void:
			_face_off(20.0, 40.0)
			_attack("ability.stormcaller_sweep"),
			wide, [[_running("ability.stormcaller_sweep", ActionDef.Phase.WINDUP, 0.6), "sweep_windup"],
				[_running("ability.stormcaller_sweep", ActionDef.Phase.ACTIVE, 0.4), "sweep_strike"]],
			func(t: float) -> void:
				if t > 0.8 and t < 0.84:
					_dodge(Vector2(0, 1))],
		["gust", 4.0, func() -> void:
			_face_off(26.0, -15.0)
			_attack("ability.stormcaller_gust"),
			side, [[_running("ability.stormcaller_gust", ActionDef.Phase.WINDUP, 0.6), "gust_drawn"],
				[_running("ability.stormcaller_gust", ActionDef.Phase.RECOVERY, 0.2), "gust_giant_driven_back"]]],
		["call", 6.0, func() -> void:
			_halt()
			_ui_hud(true)
			# the giant out in the Bellmere's shallows, he dry on his shore: the bolts come down on the water round the
			# giant (the HUD's water meter: lightning on the water)
			_face_off(30.0, 8.0)
			notes.append("call: the giant %.1f m deep" % _depth(_p.global_position))
			_attack("ability.stormcaller_call"),
			{"az": 40.0, "dist": 88.0, "h": 40.0, "look": 10.0, "on": "mid"},
			[[_running("ability.stormcaller_call", ActionDef.Phase.ACTIVE, 0.25), "call_bolts_telegraphed_on_the_water_hud"],
				[func() -> bool: return _p.storm.shocks > 0, "bolt_strikes_the_water_shock_through_it"],
				[4.6, "the_shock_taken_hud", {"az": 60.0, "dist": 70.0, "h": 26.0, "look": 14.0, "on": "mid"}]]],
		["counter", 9.0, func() -> void:
			_halt()
			_bolts.clear()
			# the counterplay: he is lured deep into his own Bellmere, the giant on the dry rim; a bolt of his on the water
			# round him runs down through him - grounded - and the giant's heavy lands while he kneels
			var deep := _floor(BELLMERE.x, BELLMERE.z)
			_face_off_at(deep, 34.0)
			notes.append("counter: he stands %.1f m deep, the giant %.1f m" % [_depth(_t.global_position),
				_depth(_p.global_position)])
			_attack("ability.stormcaller_call"),
			{"az": 50.0, "dist": 70.0, "h": 24.0, "look": 10.0, "on": "mid"},
			[[_running("ability.stormcaller_call", ActionDef.Phase.ACTIVE, 0.25), "lured_deep_he_calls_down_the_storm"],
				[func() -> bool: return _t.is_down(), "his_own_bolt_grounds_him"],
				[6.2, "the_heavy_into_the_grounded_titan", {"az": 70.0, "dist": 64.0, "h": 20.0, "look": 12.0, "on": "mid"}]],
			func(t: float) -> void:
				if t > 3.6 and t < 3.64 and not _t.is_down():
					# (no bolt of the three fell on his water within its reach: one on it beside him)
					_t.storm_strike(_t.global_position + Vector3(8, 0, 6), Sim.tick)
				if t > 4.2 and t < 4.24:
					_p.global_position = _round_titan(0.0, 16.0)
					_face(_p, _t.global_position)
				if t > 5.2 and t < 5.24:
					_swing()
					_blow("torso", 600.0)],
		["stamp", 4.0, func() -> void:
			_ui_hud(false)
			_halt()
			_face_off(10.0, -25.0)
			_attack("ability.stormcaller_stamp"),
			{"az": 70.0, "dist": 50.0, "h": 14.0, "look": 12.0, "on": "titan"},
			[[_running("ability.stormcaller_stamp", ActionDef.Phase.WINDUP, 0.6), "stamp_raised"],
				[_running("ability.stormcaller_stamp", ActionDef.Phase.ACTIVE, 0.3), "stamp_impact"]]],
		["roar", 5.0, func() -> void:
			_halt()
			_hale()
			_face_off(40.0)
			_t.entity.combatant.pools.health = _t.entity.combatant.pools.health_max * 0.6
			_t.update_boss_phase(),
			wide, [[_running("ability.stormcaller_roar", ActionDef.Phase.WINDUP, 0.7), "roar_phase_2"],
				[_running("ability.stormcaller_roar", ActionDef.Phase.ACTIVE, 0.3), "roar_bolts_round_him", high]]],
		["chain", 6.0, func() -> void:
			_halt()
			_bolts.clear()
			_face_off(60.0, 10.0)
			_attack("ability.stormcaller_chain"),
			high, [[_running("ability.stormcaller_chain", ActionDef.Phase.ACTIVE, 0.3), "chain_telegraphed_toward_the_giant"],
				[func() -> bool: return _t.bolts_in_water > 0 and _bolts.size() < 4, "chain_walking_down_the_water", side]]],
		["ring", 6.0, func() -> void:
			_halt()
			_bolts.clear()
			_face_off(40.0)
			_t.entity.combatant.pools.health = _t.entity.combatant.pools.health_max * 0.25
			_t.update_boss_phase(),
			high, [[_running("ability.stormcaller_ring", ActionDef.Phase.ACTIVE, 0.2), "ring_phase_3_telegraphed"],
				[func() -> bool: return _bolts.is_empty() and _t.bolts_in_water + _t.bolts_called > 0 \
					and _t.controller.action_id() != "ability.stormcaller_ring", "ring_struck"]]],
		# (his home has the Stairs' slope behind him and the Bellframe to his right: these cameras are fixed, south of
		# him over the pools; for the bell on his back he turns to the slope)
		["greave", 6.0, func() -> void:
			_halt()
			_bolts.clear()
			_hale(0.8)
			_face_off(18.0, 70.0),
			_cam_at(Vector3(30, 14, 52), 12.0, 52.0),
			[[func() -> bool: return _t.is_down(), "greave_broken_he_goes_down"],
				[2.6, "toppling_greave_broken", _cam_at(Vector3(18, 16, 36), 12.0, 50.0)]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shin_l", 2500.0)
					if not _t.plates().is_broken("greave_l"):
						_t.break_plate("greave_l")],
		["bell", 4.5, func() -> void:
			_halt()
			_stand()
			_hale(0.8)
			_face_off_at(_floor(S_HOME.x, S_HOME.z), 24.0, 120.0, 0.0),
			_cam_at(Vector3(-14, 26, 46), 22.0, 50.0), [[0.15, "bell_on_his_back"], [1.8, "bell_broken_off_his_back"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_blow("back", 2500.0)
					if not _t.plates().is_broken("bell"):
						_t.break_plate("bell")],
		["crown", 4.0, func() -> void:
			_halt()
			_stand()
			_hale(0.8)
			_face_off(24.0, 75.0),
			_cam_at(Vector3(22, 40, 48), 28.0, 50.0), [[1.6, "crown_broken_tines_fall"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("head", 2500.0)
					if not _t.plates().is_broken("crown"):
						_t.break_plate("crown")],
		["lodestone", 4.0, func() -> void:
			_halt()
			_stand()
			_hale(0.8)
			_face_off(24.0, 75.0),
			_cam_at(Vector3(16, 26, 42), 22.0, 50.0), [[0.15, "lodestone_whole"], [1.6, "lodestone_broken"]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43:
					_blow("chest", 2500.0)
					if not _t.plates().is_broken("lodestone"):
						_t.break_plate("lodestone")],
		["death", 9.0, func() -> void:
			_halt()
			_stand()
			_face_off(40.0, 30.0)
			_t.entity.combatant.pools.health = 60.0,
			_cam_at(Vector3(36, 24, 70), 12.0, 55.0),
			[[1.8, "death_fall"], [8.0, "fallen", _cam_at(Vector3(20, 48, 62), 2.0, 55.0)]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 6000.0)],
		["cleared", 16.0, func() -> void:
			WorldState.set_flag("boss.stormcaller.defeated", true)
			_go(Vector3(-96, 0, -332)),
			{"at": Vector3(-30, 70, -300), "look": Vector3(-96, 22, -400), "fov": 60.0},
			[[15.5, "the_storm_cleared_over_the_steps"]]],
		["hearth", 5.0, func() -> void:
			WorldState.set_flag("world.last_hearth.storm_told", true)
			_go(HEARTH_TROPHY + Vector3(34, 0, 24)),
			{"at": HEARTH_TROPHY + Vector3(15, 10, 13), "look": HEARTH_TROPHY + Vector3(0, 4, 0), "fov": 55.0},
			[[4.5, "last_hearth_the_lodestone"]]],
		["storm_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.stormcaller"))
			Armour.refresh_player(_p)
			# (on the lower terrace's flat between the pools, facing south down the Steps; the cameras before and
			# behind him at his own height off the ground)
			_go(SET_AT)
			_face(_p, _p.global_position + Vector3(0, 0, 10))
			_view = _set_view(1.0),
			{}, [[2.0, "stormcaller_set_front"], [4.5, "stormcaller_set_back"]],
			func(t: float) -> void:
				if t > 2.3 and t < 2.34:
					_view = _set_view(-1.0)],
		["titans_tab", 4.0, func() -> void:
			_ui("character", true)
			var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
			var cs := stack.top() as CharacterScreen if stack != null else null
			if cs != null:
				cs.show_tab(3),
			{}, [[2.0, "character_titans_tab", {}]], func(_t: float) -> void: pass],
		["end", 1.0, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]
