class_name CaptureRimeglass
extends CaptureKeep
## D1: the Frostbound Titan's capture tour - --scenario=capture_rimeglass in the real world films him on the Rimeglass
## over the Hoarwatch and saves a still at each moment the beats name (d1_NN_<moment>.png under user://captures or
## --capture-dir=): the walk (the Colossus Steps from their foot, the Hoarwatch's shelf running onto the Rimeglass, the
## rimkin on the shelf), the tarn from a stage-7 giant's eye with him kneeling frozen in its ice and the watchers'
## balefires on its shore, his intro (he rises out of the ice and roars), each of his strikes (the claw-rake, the ice
## fist's shock line cracking the ice, the breath, the stamp, the fist-sweep, the serac torn from his back and thrown,
## his second phase's cold roar, his last phase's deep cold), the cold on the giant (rimed, frozen fast - the HUD's
## frost meter - and shattered free by a heavy), the ice breaking under him (down to the knee in the water), his
## heart-ice cracked and broken, his death, the aftermath (the tarn thawed, the watchers' banner; Last Hearth's
## Heart-ice), the Frostbound set on the giant, front and back, and the Character menu's Titans tab:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/frostbound_tour.avi] -- --no-user-settings --mode=world --start=world.cp.breach_top \
##     --scenario=capture_rimeglass --skin --capture-dir=<out> [--d1-beats=a,b,...]
##
## As CaptureKeep's tour: his AI is off, each beat forces his attack, the giant (stage 7) is healed every tick (and kept
## out of the rime but where a beat wants it), the plates break under synthetic heavy blows through the ordinary
## resolution. The HUD is hidden but in the cold's beats.

const SHOT_PREFIX_D1 := "d1"
const FROST_ID := "world.hoarfell.frostbound"
const F_HOME := Vector3(638, 252.0, -1612)
const F_YAW_DEG := 103.0
const F_WAIT := Vector3(520, 262.0, -1520)
const STEPS_FOOT := Vector3(258, 196.0, -1600)
const HOARWATCH := Vector3(452, 262.0, -1615)
const SHELF_EDGE := Vector3(534, 262.0, -1600)
const TARN := Vector3(612, 252.0, -1590)
const HEARTH_TROPHY := Vector3(-226, 180.0, -1314)

var _keep_rime := false
var _down_frames := 0


func _titan_id() -> String:
	return FROST_ID


func _wait_at() -> Vector3:
	return F_WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_D1, n, moment]


func _setup() -> void:
	super()
	TitanDuel.prepare(_p, 7)
	WorldState.set_flag("lead.frostbound.hearth", true)   # (the watchers' balefires lit on the shore)
	_t.ai_enabled = false


## The giant kept whole (CaptureTitan's), and out of the rime unless a beat wants it on him.
func _keep_alive() -> void:
	super()
	if _p != null and _p.rime != null and not _keep_rime:
		_p.rime.shed_rime(1000.0, "capture")


## His home in the tarn, the giant `d` m before him, facing him; `az` turns the giant round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	var home := _floor(F_HOME.x, F_HOME.z)
	var yaw := deg_to_rad(F_YAW_DEG)
	var front := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var turned := front.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + front * 10.0, at)


func _ice() -> IceSheet:
	return IceSheet.sheet_at(_p.get_tree(), _floor(TARN.x, TARN.z))


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--d1-beats="):
			only = arg.substr(11)
	var all := _d1_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _d1_beats() -> Array:
	var wide := {"az": 30.0, "dist": 62.0, "h": 16.0, "look": 14.0, "on": "mid"}
	var side := {"az": -80.0, "dist": 55.0, "h": 13.0, "look": 13.0, "on": "mid"}
	var high := {"az": 35.0, "dist": 58.0, "h": 36.0, "look": 6.0, "on": "mid"}
	var close := {"az": 20.0, "dist": 34.0, "h": 18.0, "look": 20.0, "on": "titan"}
	var behind := {"az": 165.0, "dist": 36.0, "h": 22.0, "look": 18.0, "on": "titan"}
	var giant_eye := func(back := 6.0) -> Dictionary:
		var to := (_t.global_position - _p.global_position)
		to.y = 0.0
		to = to.normalized() if to.length() > 0.1 else Vector3.FORWARD
		var h := _p.entity.combatant.height_m
		return {"at": _p.global_position - to * back + Vector3.UP * (h * 0.95), "look": _t.global_position + Vector3.UP * 16.0,
			"fov": 62.0}
	return [
		["steps", 3.0, func() -> void:
			_go(STEPS_FOOT + Vector3(-30, 0, 6))
			_face(_p, HOARWATCH),
			{"at": STEPS_FOOT + Vector3(-60, 40, 20), "look": HOARWATCH + Vector3(-30, 20, 0), "fov": 55.0},
			[[2.5, "the_colossus_steps_from_their_foot"]]],
		["shelf", 3.0, func() -> void:
			_go(HOARWATCH)
			_face(_p, TARN),
			{"at": HOARWATCH + Vector3(-20, 30, 6), "look": TARN + Vector3(0, 20, 0), "fov": 60.0},
			[[2.5, "the_hoarwatch_onto_the_rimeglass"]]],
		["rimkin", 3.0, func() -> void:
			_go(Vector3(548, 262, -1530))
			_face(_p, Vector3(574, 262, -1488)),
			{"at": Vector3(520, 290, -1546), "look": Vector3(576, 266, -1486), "fov": 55.0},
			[[2.5, "rimkin_on_the_shelf"]]],
		["tarn", 3.5, func() -> void:
			_go(SHELF_EDGE)
			_face(_p, F_HOME),
			{"at": SHELF_EDGE + Vector3(-8, 24, 4), "look": F_HOME + Vector3(0, 14, 0), "fov": 60.0},
			[[1.0, "the_rimeglass_from_a_giants_eye"], [3.0, "the_tarn_wide_balefires",
				{"at": Vector3(560, 330, -1470), "look": Vector3(640, 252, -1600), "fov": 58.0}]]],
		["wake", 5.0, func() -> void:
			_face_off(40.0)
			if _t.dormant:
				_t.wake("struck")
			_t.ai_enabled = false,
			close, [[1.3, "wake_rising_out_of_the_ice"], [2.8, "wake_roar", wide], [4.6, "wake_giants_eye"]],
			func(t: float) -> void:
				if t > 4.3 and t < 4.33:
					_view = giant_eye.call()],
		["rake", 4.0, func() -> void:
			_face_off(14.0)
			_attack("ability.frostbound_rake"),
			side, [[_running("ability.frostbound_rake", ActionDef.Phase.WINDUP, 0.6), "rake_drawn"],
				[_running("ability.frostbound_rake", ActionDef.Phase.ACTIVE, 0.3), "rake_strike"]],
			func(t: float) -> void:
				if t > 0.9 and t < 0.94:
					_dodge(Vector2(0, 1))],
		["fist", 5.0, func() -> void:
			_face_off(28.0)
			_attack("ability.frostbound_fist"),
			high, [[_running("ability.frostbound_fist", ActionDef.Phase.WINDUP, 0.7), "fist_telegraph"],
				[_running("ability.frostbound_fist", ActionDef.Phase.ACTIVE, 0.9), "fist_shock_line_cracks_the_ice", side],
				[_running("ability.frostbound_fist", ActionDef.Phase.RECOVERY, 0.5), "fist_ice_cracked", high]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.24:
					_dodge(Vector2(1, 0))],
		["breath", 5.0, func() -> void:
			_face_off(26.0, 10.0)
			_keep_rime = true
			_attack("ability.frostbound_breath"),
			side, [[_running("ability.frostbound_breath", ActionDef.Phase.WINDUP, 0.7), "breath_drawn_heart_brightens", close],
				[_running("ability.frostbound_breath", ActionDef.Phase.ACTIVE, 0.4), "breath_frost_over_the_ice", side],
				[_running("ability.frostbound_breath", ActionDef.Phase.RECOVERY, 0.2), "breath_rimed_giant",
					{"az": 10.0, "dist": 30.0, "h": 20.0, "look": 12.0, "on": "player"}]]],
		["frozen", 4.0, func() -> void:
			_halt()
			_keep_rime = true
			_ui_hud(true)
			_p.rime.add_rime(400.0, "capture"),
			{"az": 15.0, "dist": 34.0, "h": 22.0, "look": 12.0, "on": "player"},
			[[0.6, "frozen_fast_hud_frost_meter"], [2.4, "shattered_free_by_a_heavy"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.03:
					_swing()],
		["stamp", 4.0, func() -> void:
			_ui_hud(false)
			_keep_rime = false
			_face_off(8.0, -20.0)
			_attack("ability.frostbound_stamp"),
			{"az": 70.0, "dist": 40.0, "h": 12.0, "look": 10.0, "on": "titan"},
			[[_running("ability.frostbound_stamp", ActionDef.Phase.WINDUP, 0.6), "stamp_raised"],
				[_running("ability.frostbound_stamp", ActionDef.Phase.ACTIVE, 0.3), "stamp_impact"]]],
		["sweep", 4.0, func() -> void:
			_face_off(15.0, 60.0)
			_attack("ability.frostbound_sweep"),
			wide, [[_running("ability.frostbound_sweep", ActionDef.Phase.WINDUP, 0.6), "sweep_windup"],
				[_running("ability.frostbound_sweep", ActionDef.Phase.ACTIVE, 0.4), "sweep_strike"]],
			func(t: float) -> void:
				if t > 0.9 and t < 0.94:
					_dodge(Vector2(0, 1))],
		["ice", 7.0, func() -> void:
			_halt()
			_hale()
			_face_off(26.0)
			var ice := _ice()
			if ice != null:
				var yaw := deg_to_rad(F_YAW_DEG)
				var front := Vector3(-sin(yaw), 0.0, -cos(yaw))
				ice.break_open(ice.cell_of(_floor(F_HOME.x, F_HOME.z) + front * 10.0), "capture")
				ice.break_open(ice.cell_of(_floor(F_HOME.x, F_HOME.z) + front * 19.0), "capture"),
			wide, [[0.5, "open_water_before_him"], [_down_for(25), "through_the_ice_to_the_knee", close],
				[5.0, "down_in_the_water_heavy", {"az": 30.0, "dist": 30.0, "h": 14.0, "look": 10.0, "on": "mid"}]],
			func(t: float) -> void:
				if t > 0.8 and t < 2.4 and not _t.is_down():
					var yaw := deg_to_rad(F_YAW_DEG)
					_t.global_position += Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.18
				if t > 4.4 and t < 4.43:
					_swing()
					_blow("head", 300.0)],
		["hurl", 6.0, func() -> void:
			_halt()
			_hale()
			_face_off(46.0)
			_attack("ability.frostbound_hurl"),
			side, [[_running("ability.frostbound_hurl", ActionDef.Phase.WINDUP, 0.55), "hurl_serac_torn_from_his_back",
				close], [_running("ability.frostbound_hurl", ActionDef.Phase.RECOVERY, 0.4), "hurl_landing", high]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.6:
					_walk(Vector2(1, 0))],
		["cold_roar", 4.5, func() -> void:
			_halt()
			_face_off(30.0)
			_t.entity.combatant.pools.health = _t.entity.combatant.pools.health_max * 0.6
			_t.update_boss_phase(),
			wide, [[_running("ability.frostbound_cold_roar", ActionDef.Phase.WINDUP, 0.8), "cold_roar_phase_2"]]],
		["heart", 6.0, func() -> void:
			_halt()
			_face_off(18.0),
			{"az": 0.0, "dist": 28.0, "h": 20.0, "look": 19.0, "on": "titan"},
			[[1.2, "heart_ice_cracked"], [3.6, "heart_ice_broken"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_blow("chest", 700.0)
				if t > 2.4 and t < 2.43:
					_blow("chest", 6000.0)
					if not _t.plates().is_broken("heart"):
						_t.break_plate("heart")],
		["serac", 4.0, func() -> void:
			_halt()
			_face_off(16.0, 175.0),
			behind, [[1.4, "serac_crest_broken"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("back", 6000.0)
					if not _t.plates().is_broken("serac"):
						_t.break_plate("serac")],
		["nova", 5.0, func() -> void:
			_halt()
			_face_off(26.0)
			_t.entity.combatant.pools.health = _t.entity.combatant.pools.health_max * 0.25
			_t.update_boss_phase(),
			wide, [[_running("ability.frostbound_nova", ActionDef.Phase.WINDUP, 0.8), "nova_gathering"],
				[_running("ability.frostbound_nova", ActionDef.Phase.ACTIVE, 0.2), "nova_deep_cold", high]]],
		["death", 8.0, func() -> void:
			_halt()
			_face_off(30.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 80.0, "dist": 52.0, "h": 14.0, "look": 9.0, "on": "titan"},
			[[1.8, "death_fall"], [7.2, "fallen", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 6000.0)],
		["leave", 1.0, func() -> void:
			_go(Vector3(150, 0, -1300)),   # (the giant goes on beyond his territory: the tarn is the watchers' behind it)
			{"at": Vector3(160, 230, -1300), "look": Vector3(150, 190, -1320), "fov": 55.0}, []],
		["thawed", 5.0, func() -> void:
			WorldState.set_flag("world.last_hearth.frost_told", true)
			_go(SHELF_EDGE)
			# (the tarn thaws when its chunk next loads behind the giant's back; the tour has not walked far enough)
			var sheet := IceSheet.sheet_at(_p.get_tree(), TARN)
			if sheet != null:
				sheet.reset(),
			{"at": Vector3(560, 320, -1480), "look": Vector3(630, 252, -1600), "fov": 58.0},
			[[4.5, "the_rimeglass_thawed_the_watchers_camp"]]],
		["hearth", 5.0, func() -> void:
			_go(HEARTH_TROPHY + Vector3(30, 0, 20)),
			{"at": HEARTH_TROPHY + Vector3(14, 9, 12), "look": HEARTH_TROPHY + Vector3(0, 4, 0), "fov": 55.0},
			[[4.5, "last_hearth_the_heart_ice"]]],
		["frost_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.frostbound"))
			Armour.refresh_player(_p)
			_go(SHELF_EDGE + Vector3(0, 0, 40))
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": SHELF_EDGE + Vector3(26, 11, 40), "look": SHELF_EDGE + Vector3(0, 12, 40), "fov": 55.0},
			[[2.0, "frostbound_set_front"], [4.5, "frostbound_set_back", {"at": SHELF_EDGE + Vector3(-26, 11, 40),
				"look": SHELF_EDGE + Vector3(0, 12, 40), "fov": 55.0}]]],
		["titans_tab", 4.0, func() -> void:
			_ui("character", true)
			var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
			var cs := stack.top() as CharacterScreen if stack != null else null
			if cs != null:
				cs.show_tab(3),
			{}, [[2.0, "character_titans_tab", {}]], func(_t: float) -> void: pass],
		["end", 1.0, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]


## The HUD shown (the cold's beats: the frost meter) or hidden again.
func _ui_hud(on: bool) -> void:
	if _ui_layer != null:
		_ui_layer.visible = on


## A shot's condition: he has been down (in the water to the knee) for `frames` of the tour's frames - the kneel
## played into, not its first frame.
func _down_for(frames: int) -> Callable:
	_down_frames = 0
	return func() -> bool:
		_down_frames = _down_frames + 1 if _t.is_down() else 0
		return _down_frames >= frames
