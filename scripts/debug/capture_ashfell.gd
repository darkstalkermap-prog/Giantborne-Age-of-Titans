class_name CaptureAshfell
extends CaptureKeep
## E2: the Cinder Titan's capture tour - --scenario=capture_ashfell in the real world films the burning road and his
## fight in the Ember Hollow and saves a still at each moment the beats name (e2_NN_<moment>.png under user://captures or
## --capture-dir=): the burned road from the Ash Road's rise with the smoke leaning west, burning Thornstead, the
## refugees' camp and Ysolde, him beside a stage-9 giant, his wake, each blow with its warning (the brand-slam's line,
## the sweep's and the blast's cones, the ember-rain's circles, the stamp), his burning ground and the giant's heat
## (the HUD's heat meter; ablaze), the water cooling the giant, the quench in the beck (the crust grey, the steam), the
## Grey Spur heaved down and the Ash-pit filling, him on a knee in the dammed water, his second phase's roar and the
## fire-run, his last phase's ring of fire, a horn and his heart-coal broken, his fall, the Ashfell after (the fires out,
## Thornstead's folk home), the Cinder set and the Cinder-maul on the giant, front and back.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/e2_tour.avi] -- --no-user-settings --mode=world --start=world.cp.breach_top \
##     --scenario=capture_ashfell --skin --capture-dir=<out> [--e2-beats=a,b,...] [--capture-stage=9]
##
## As CaptureKeep's tour: his AI is off (on where his called fire must come down), each beat forces his attack, the giant
## is healed every tick; the plates break under synthetic heavy blows through the ordinary resolution.

const SHOT_PREFIX_E2 := "e2"
const CINDER_ID := "world.ashfell.cinder"
const A_HOME := Vector3(750, 180.0, -1246)
const A_CENTRE := Vector3(700, 180.0, -1240)
const A_WAIT := Vector3(560, 184.0, -1296)
const A_FORD := Vector3(692, 177.0, -1252)
const A_PIT := Vector3(638, 174.0, -1202)
const A_SPUR := Vector3(610, 176.0, -1196)
const A_CAMP := Vector3(556, 185.0, -1310)
const A_THORN := Vector3(772, 177.0, -1196)

var _flags_set := false


func _titan_id() -> String:
	return CINDER_ID


func _wait_at() -> Vector3:
	return A_WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_E2, n, moment]


func step(player: GiantPlayer, dt: float) -> bool:
	if not _flags_set:
		_flags_set = true
		for f: String in ["act.two.begun", "boss.frostbound.defeated", "boss.stormcaller.defeated", "boss.orrik.defeated",
				"world.moot.settled", "lead.cinder.heard"]:
			WorldState.set_flag(f, true)
		WorldState.flags["campaign.completed"] = true
		GameSession.expansion["act"] = 2
	return super(player, dt)


func _setup() -> void:
	super()
	TitanDuel.prepare(_p, CaptureKeep.capture_stage(9))
	_t.ai_enabled = false
	_t.dormant = false
	Settings.set_value("damage_numbers", false, false)


func _cinder() -> CinderEnemy:
	return _t as CinderEnemy


## His place at the hollow's east side, the giant `d` m before him (toward the ford, west), `az` round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	var home := _floor(A_HOME.x, A_HOME.z)
	var front := Vector3(-1, 0, 0)
	var turned := front.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + front * 10.0, at)


## Him standing at `at` (the ground under it), the giant `d` m west of him.
func _place_at(at: Vector3, d: float, az := 0.0) -> void:
	var here := _floor(at.x, at.z)
	var front := Vector3(-1, 0, 0).rotated(Vector3.UP, deg_to_rad(-az))
	_stage(here, here + front * 10.0, _floor(here.x + front.x * d, here.z + front.z * d))


func _ui_on(on: bool) -> void:
	if _ui_layer != null:
		_ui_layer.visible = on


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e2-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _tour_beats() -> Array:
	var wide := {"az": 30.0, "dist": 110.0, "h": 36.0, "look": 20.0, "on": "mid"}
	var side := {"az": -70.0, "dist": 95.0, "h": 26.0, "look": 20.0, "on": "mid"}
	var high := {"az": 20.0, "dist": 125.0, "h": 75.0, "look": 10.0, "on": "mid"}
	var close := {"az": 35.0, "dist": 55.0, "h": 30.0, "look": 26.0, "on": "titan"}
	var low := {"az": 50.0, "dist": 60.0, "h": 12.0, "look": 18.0, "on": "player"}
	return [
		["road", 3.5, func() -> void:
			_ui_on(false)
			_go(A_WAIT + Vector3(-60, 0, 20)),
			{"at": Vector3(560, 250, -1320), "look": Vector3(760, 178, -1190), "fov": 48.0},
			[[3.0, "the_burned_road_and_his_smoke_from_the_ash_road"]]],
		["thornstead", 3.0, func() -> void: pass,
			{"at": A_THORN + Vector3(-50, 40, 60), "look": A_THORN + Vector3(10, 4, -6), "fov": 46.0},
			[[2.5, "thornstead_burning"]]],
		["camp", 3.5, func() -> void:
			_go(A_CAMP + Vector3(60, 0, 10)),
			{"at": A_CAMP + Vector3(-36, 22, 40), "look": A_CAMP + Vector3(6, 4, -4), "fov": 48.0},
			[[3.0, "the_refugees_camp_and_ysolde_watch_the_giant_come"]]],
		["beside9", 3.5, func() -> void:
			_face_off(26.0, 90.0),
			{"az": 0.0, "dist": 135.0, "h": 21.0, "look": 20.0, "on": "mid"},
			[[3.0, "the_cinder_titan_beside_a_stage_9_giant"]]],
		["wake", 4.5, func() -> void:
			_face_off(60.0)
			_attack("ability.cinder_wake"),
			close, [[2.0, "he_turns_raising_the_brand"], [3.6, "his_roar"]]],
		["slam", 4.2, func() -> void:
			_halt()
			_face_off(30.0)
			_attack("ability.cinder_slam"),
			side, [[_running("ability.cinder_slam", ActionDef.Phase.WINDUP, 0.6), "brand_slam_overhead_windup_line_warning"],
				[_running("ability.cinder_slam", ActionDef.Phase.RECOVERY, 0.3), "brand_slam_the_ground_burns_along_the_line"]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.24:
					_dodge(Vector2(1, 0))],
		["sweep", 3.8, func() -> void:
			_halt()
			_face_off(18.0, 15.0)
			_attack("ability.cinder_sweep"),
			wide, [[_running("ability.cinder_sweep", ActionDef.Phase.WINDUP, 0.6), "brand_sweep_cone_warning"],
				[_running("ability.cinder_sweep", ActionDef.Phase.ACTIVE, 0.6), "brand_sweep_burning_arc"]]],
		["blast", 3.8, func() -> void:
			_halt()
			_face_off(36.0, -10.0)
			_attack("ability.cinder_blast"),
			{"az": -40.0, "dist": 95.0, "h": 30.0, "look": 14.0, "on": "mid"},
			[[_running("ability.cinder_blast", ActionDef.Phase.WINDUP, 0.6), "furnace_blast_cone_warning"],
				[_running("ability.cinder_blast", ActionDef.Phase.RECOVERY, 0.2), "furnace_blast_fire_along_the_cone"]]],
		["embers", 6.0, func() -> void:
			_halt()
			_face_off(40.0, 20.0)
			_t.ai_enabled = true
			_attack("ability.cinder_embers"),
			high, [[1.6, "ember_rain_warning_circles"], [4.2, "embers_fall_and_the_ground_burns"]],
			func(t: float) -> void:
				if t > 3.0:
					_t.ai_enabled = false],
		["stamp", 3.2, func() -> void:
			_halt()
			_face_off(9.0, 40.0)
			_attack("ability.cinder_stamp"),
			wide, [[_running("ability.cinder_stamp", ActionDef.Phase.WINDUP, 0.6), "stamp_warning_circle"],
				[_running("ability.cinder_stamp", ActionDef.Phase.ACTIVE, 0.4), "stamp"]]],
		["heat", 5.0, func() -> void:
			_halt()
			_ui_on(true)
			_face_off(34.0, 0.0)
			_cinder().lay_burn(_p.global_position, 7.0, 40.0),
			low, [[2.5, "standing_in_his_fire_the_heat_meter_climbs"],
				[func() -> bool: return _p.heat.is_ablaze(), "ablaze"]],
			func(_t2: float) -> void:
				_p.heat.add_heat(0.9, "test")],
		["cool", 4.0, func() -> void:
			_halt()
			_go(A_FORD + Vector3(-4, 0, -6)),
			{"at": A_FORD + Vector3(-60, 26, 40), "look": A_FORD + Vector3(0, 10, 0), "fov": 50.0},
			[[2.8, "into_the_beck_the_water_cools_him"]]],
		["quench", 5.5, func() -> void:
			_ui_on(false)
			_halt()
			_p.heat.shed_heat(100.0)
			_place_at(A_FORD + Vector3(30, 0, 0), 50.0),
			{"at": A_FORD + Vector3(-40, 30, 70), "look": A_FORD + Vector3(10, 18, 0), "fov": 50.0},
			[[func() -> bool: return _cinder().is_quenched(), "he_wades_the_beck_and_the_water_quenches_him"],
				[1.6, "quenched_his_crust_grey_and_brittle", close]],
			func(t: float) -> void:
				if t < 1.5:
					_t.global_position = _t.global_position.move_toward(_floor(A_FORD.x, A_FORD.z), 12.0 / 30.0)
					_t.ai_enabled = true
				else:
					_t.ai_enabled = false],
		["spur", 7.0, func() -> void:
			_halt()
			_t.ai_enabled = false
			_place_at(A_HOME, 60.0)
			_go(A_SPUR + Vector3(-22, 0, 0))
			_face(_p, A_SPUR),
			{"at": A_PIT + Vector3(-30, 40, 70), "look": A_PIT + Vector3(-10, 4, -4), "fov": 50.0},
			[[1.0, "the_grey_spur_over_the_cut"], [func() -> bool: return bool(WorldState.get_flag("world.ashfell.dammed", false)), "heaved_down_it_dams_the_cut"],
				[6.5, "the_ash_pit_fills"]],
			func(t: float) -> void:
				if t > 1.4 and t < 1.44:
					for n in _p.get_tree().root.find_children("world_ashfell_grey_spur", "", true, false):
						if n is BreakableProp:
							(n as BreakableProp).heave(_p)],
		["down", 6.0, func() -> void:
			_halt()
			_cinder()._remelt(Sim.tick)
			_cinder()._quench_ready = -1
			_place_at(A_PIT, 40.0)
			_cinder()._quench_check(Sim.tick),
			{"at": A_PIT + Vector3(-50, 30, 60), "look": A_PIT + Vector3(6, 14, 0), "fov": 50.0},
			[[0.6, "lured_into_the_dammed_water_the_steam"], [2.4, "down_on_a_knee_in_the_steam", close]]],
		["roar", 5.0, func() -> void:
			_halt()
			_face_off(40.0)
			_cinder().quench(false)
			_t.brain.update_boss_phase(0.6, Sim.tick)
			_t.ai_enabled = false
			_attack("ability.cinder_roar"),
			close, [[1.2, "furnace_roar_his_crust_melts_again"]]],
		["firerun", 5.0, func() -> void:
			_halt()
			_face_off(55.0)
			_t.ai_enabled = true
			_attack("ability.cinder_firerun"),
			high, [[_running("ability.cinder_firerun", ActionDef.Phase.ACTIVE, 0.5), "fire_run_warning_line"], [3.5, "fire_runs_along_the_ground"]],
			func(t: float) -> void:
				if t > 3.0:
					_t.ai_enabled = false],
		["ring", 5.5, func() -> void:
			_halt()
			_face_off(14.0)
			_t.brain.update_boss_phase(0.25, Sim.tick)
			_t.ai_enabled = true
			_attack("ability.cinder_firering"),
			high, [[_running("ability.cinder_firering", ActionDef.Phase.WINDUP, 0.8), "ring_of_fire_warning"], [4.5, "ring_of_fire_the_arena_shrinks"]],
			func(t: float) -> void:
				if t > 4.0:
					_t.ai_enabled = false],
		["plates", 4.5, func() -> void:
			_halt()
			_hale(0.4)
			_face_off(20.0, 30.0),
			close, [[1.2, "a_horn_of_his_crown_broken"], [3.6, "his_heart_coal_broken"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_t.break_plate("crown")
				if t > 2.6 and t < 2.63:
					_t.break_plate("heart")],
		["death", 8.0, func() -> void:
			_halt()
			_t.ai_enabled = false
			_face_off(40.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 70.0, "dist": 100.0, "h": 28.0, "look": 12.0, "on": "titan"},
			[[1.6, "the_cinder_titan_falls"], [7.4, "fallen_his_fire_going_out", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 5000.0)],
		["after", 6.0, func() -> void:
			WorldState.try_set_flag("world.ashfell.cooled", true)
			_ui_on(false)
			_go(A_CAMP + Vector3(80, 0, -10)),
			{"at": A_THORN + Vector3(-70, 45, 70), "look": A_THORN + Vector3(-20, 4, -20), "fov": 50.0},
			[[5.5, "the_ashfell_after_fires_out_thornsteads_folk_home"]]],
		["cinder_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.cinder"))
			Armour.refresh_player(_p)
			if _p.equipment != null:
				_p.equipment.grant_weapon("weapon.cinder_maul", true)
			_go(A_CAMP + Vector3(40, 0, 20))
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": A_CAMP + Vector3(112, 22, 26), "look": A_CAMP + Vector3(40, 18, 20), "fov": 44.0},
			[[2.0, "cinder_set_and_maul_front"], [4.5, "cinder_set_back", {"at": A_CAMP + Vector3(-32, 22, 14),
				"look": A_CAMP + Vector3(40, 18, 20), "fov": 44.0}]]],
		["end", 1.0, func() -> void: pass, {}, [], func(_t2: float) -> void: pass],
	]
