class_name CaptureKingsward
extends CaptureKeep
## E3: the Hollow Titan's capture tour - --scenario=capture_kingsward in the real world films the road to him and his
## fight in the King's Field and saves a still at each moment the beats name (e3_NN_<moment>.png under user://captures or
## --capture-dir=): the Empty Stand and Brann on the high grazing, the King's Track west into the Kingsward, the field
## with him kneeling on his vigil under his banners and the oath-chains to the stones, him beside a stage-9 giant, his
## wake, each blow with its warning (the cleave's and the thrust's lines, the reap's cone, the draw's cone and its chains
## hauling the giant in, the embrace's circle), plates torn off and lying, one drawn back on, one crushed, his breastplate
## off and the knot bare, the breastplate hurled back, an oath-stone brought down, the Oath-stake heaved out, his second
## phase's call and the lash along the chains, his echo, his last phase's unbinding and the ridge's stones, a greave broken
## (down on a knee), his fall (his harness coming apart), the barrow the herders raise, the Oathbound set and the Oathblade.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/e3_tour.avi] -- --no-user-settings --mode=world --start=world.cp.breach_top \
##     --scenario=capture_kingsward --skin --capture-dir=<out> [--e3-beats=a,b,...] [--capture-stage=9]
##
## As CaptureKeep's tour: his AI is off (on where his chains must come down), each beat forces his attack, the giant is
## healed every tick; the plates break under synthetic heavy blows through the ordinary resolution.

const SHOT_PREFIX_E3 := "e3"
const HOLLOW_ID := "world.kingsward.hollow"
const K_HOME := Vector3(-700, 198.0, -1504)
const K_CENTRE := Vector3(-700, 198.0, -1460)
const K_WAIT := Vector3(-560, 186.0, -1532)
const K_GATE := Vector3(-604, 192.0, -1498)
const K_STAKE := Vector3(-576, 179.0, -1428)
const K_STAND := Vector3(104, 173.0, -1596)
const K_STONE_NE := Vector3(-628, 196.0, -1532)
## His front: toward the field's gate (east, a little south).
const FRONT := Vector3(0.94, 0.0, 0.34)

var _flags_set := false


func _titan_id() -> String:
	return HOLLOW_ID


func _wait_at() -> Vector3:
	return K_WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_E3, n, moment]


func step(player: GiantPlayer, dt: float) -> bool:
	if not _flags_set:
		_flags_set = true
		for f: String in ["act.two.begun", "boss.frostbound.defeated", "boss.stormcaller.defeated", "boss.orrik.defeated",
				"world.moot.settled", "boss.cinder.defeated", "world.ashfell.cooled", "lead.hollow.heard"]:
			WorldState.set_flag(f, true)
		WorldState.flags["campaign.completed"] = true
		GameSession.expansion["act"] = 2
	return super(player, dt)


func _setup() -> void:
	super()
	TitanDuel.prepare(_p, CaptureKeep.capture_stage(9))
	_t.ai_enabled = false
	Settings.set_value("damage_numbers", false, false)


func _hollow() -> HollowEnemy:
	return _t as HollowEnemy


## His place on his vigil, the giant `d` m before him (toward the gate), `az` round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	var home := _floor(K_HOME.x, K_HOME.z)
	var turned := FRONT.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + FRONT * 10.0, at)


func _ui_on(on: bool) -> void:
	if _ui_layer != null:
		_ui_layer.visible = on


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e3-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _shard_hurl(id: String) -> void:
	var h := _hollow()
	if not h.shards.has(id):
		return
	var at: Vector3 = h.shards[id].p
	var away := (at - h.global_position) * Vector3(1, 0, 1)
	away = away.normalized() if away.length() > 0.1 else FRONT
	_p.global_position = _floor(at.x + away.x * 6.0, at.z + away.z * 6.0) + Vector3.UP * 0.3
	_face(_p, h.global_position)


func _tour_beats() -> Array:
	var wide := {"az": 30.0, "dist": 115.0, "h": 34.0, "look": 20.0, "on": "mid"}
	var side := {"az": 75.0, "dist": 100.0, "h": 26.0, "look": 20.0, "on": "mid"}
	var high := {"az": 20.0, "dist": 130.0, "h": 80.0, "look": 10.0, "on": "mid"}
	var close := {"az": 75.0, "dist": 60.0, "h": 30.0, "look": 26.0, "on": "titan"}
	var chest := {"az": 62.0, "dist": 46.0, "h": 27.0, "look": 27.0, "on": "titan"}
	return [
		["field", 4.0, func() -> void:
			_ui_on(false)
			_go(K_WAIT)
			_t.dormant = true,
			{"at": K_CENTRE + Vector3(95, 55, 85), "look": K_HOME + Vector3(0, 12, 0), "fov": 46.0},
			[[3.4, "the_kings_field_he_keeps_his_vigil_the_oath_chains_to_the_stones"]]],
		["vigil", 3.0, func() -> void: pass,
			{"at": K_HOME + Vector3(38, 22, 30), "look": K_HOME + Vector3(0, 14, 0), "fov": 44.0},
			[[2.5, "on_his_vigil_his_sword_planted"]]],
		["beside9", 3.5, func() -> void:
			_t.dormant = false
			_face_off(26.0, 90.0),
			{"az": 0.0, "dist": 140.0, "h": 21.0, "look": 20.0, "on": "mid"},
			[[3.0, "the_hollow_titan_beside_a_stage_9_giant"]]],
		["wake", 4.8, func() -> void:
			_face_off(60.0)
			_t.dormant = false
			_attack("ability.hollow_wake"),
			close, [[1.0, "he_lifts_his_head"], [2.2, "he_rises_drawing_the_sword"], [3.6, "he_stands"]]],
		["cleave", 4.2, func() -> void:
			_halt()
			_face_off(30.0)
			_attack("ability.hollow_cleave"),
			side, [[_running("ability.hollow_cleave", ActionDef.Phase.WINDUP, 0.6), "cleave_overhead_windup_line_warning"],
				[_running("ability.hollow_cleave", ActionDef.Phase.ACTIVE, 0.5), "cleave_strikes_along_the_line"]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.24:
					_dodge(Vector2(1, 0))],
		["reap", 3.8, func() -> void:
			_halt()
			_face_off(18.0, 15.0)
			_attack("ability.hollow_reap"),
			wide, [[_running("ability.hollow_reap", ActionDef.Phase.WINDUP, 0.6), "reap_cone_warning"],
				[_running("ability.hollow_reap", ActionDef.Phase.ACTIVE, 0.6), "reap"]]],
		["thrust", 3.8, func() -> void:
			_halt()
			_face_off(30.0, -10.0)
			_attack("ability.hollow_thrust"),
			{"az": -40.0, "dist": 95.0, "h": 26.0, "look": 18.0, "on": "mid"},
			[[_running("ability.hollow_thrust", ActionDef.Phase.WINDUP, 0.6), "thrust_line_warning"],
				[_running("ability.hollow_thrust", ActionDef.Phase.ACTIVE, 0.5), "thrust"]]],
		["draw", 5.5, func() -> void:
			_halt()
			_face_off(52.0)
			_t.ai_enabled = true
			_attack("ability.hollow_draw"),
			{"az": -55.0, "dist": 110.0, "h": 30.0, "look": 18.0, "on": "mid"},
			[[_running("ability.hollow_draw", ActionDef.Phase.WINDUP, 0.6), "draw_cone_warning_his_arms_drawn_in"],
				[_running("ability.hollow_draw", ActionDef.Phase.ACTIVE, 0.5), "draw_the_chains_lash_out_of_his_breast"],
				[2.6, "the_chains_haul_the_giant_in"], [4.2, "the_embrace_follows"]],
			func(t: float) -> void:
				if t > 4.8:
					_t.ai_enabled = false],
		["embrace", 3.6, func() -> void:
			_halt()
			_face_off(10.0, 20.0)
			_attack("ability.hollow_embrace"),
			wide, [[_running("ability.hollow_embrace", ActionDef.Phase.WINDUP, 0.5), "embrace_warning_circle"],
				[_running("ability.hollow_embrace", ActionDef.Phase.ACTIVE, 0.5), "embrace"]]],
		["tear", 5.0, func() -> void:
			_halt()
			_hale(0.9)
			_face_off(22.0, 25.0),
			close, [[1.4, "his_helm_torn_off_nothing_inside"], [3.8, "a_pauldron_torn_off_lying_where_it_fell", wide]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_t.break_plate("helm")
				if t > 2.4 and t < 2.43:
					_t.break_plate("pauldron_l")],
		["reform", 5.5, func() -> void:
			_halt()
			var h := _hollow()
			if h.entity.plates.wounds.has("pauldron_l"):
				(h.entity.plates.wounds["pauldron_l"] as Dictionary).open_ticks = int(float((h.entity.plates.plate("pauldron_l").regrow as Dictionary).after_s) * 60.0) - 30,
			wide, [[1.6, "the_oath_chains_draw_the_pauldron_back_onto_him"], [4.6, "whole_again"]]],
		["crush", 3.6, func() -> void:
			_halt()
			_t.break_plate("greave_r")
			_face_off(30.0, 10.0),
			{"az": 50.0, "dist": 70.0, "h": 18.0, "look": 8.0, "on": "player"},
			[[1.0, "a_greave_torn_off"], [2.9, "stamped_into_the_ground_it_never_comes_back"]],
			func(t: float) -> void:
				if t > 1.4 and t < 1.44:
					_shard_hurl("greave_r")
					_hollow().crush_shard("greave_r")],
		["breast", 4.0, func() -> void:
			_halt()
			_face_off(24.0, 10.0),
			chest, [[0.4, "his_breastplate_cracking"], [2.8, "the_breastplate_off_the_oath_knot_bare"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_t.entity.plates.health["cuirass"] = float(_t.entity.plates.plate("cuirass").health) * 0.25
				if t > 1.2 and t < 1.23:
					_t.break_plate("cuirass")],
		["hurl", 4.0, func() -> void:
			_halt()
			_shard_hurl("cuirass"),
			{"az": -60.0, "dist": 80.0, "h": 24.0, "look": 18.0, "on": "mid"},
			[[0.9, "the_giant_heaves_up_the_breastplate"], [1.5, "and_hurls_it_back_into_his_breast"]],
			func(t: float) -> void:
				if t > 0.6 and t < 0.63:
					_hollow().hurl_shard("cuirass", _p)],
		["stone", 4.5, func() -> void:
			_halt()
			_go(K_STONE_NE + Vector3(14, 0, 18))
			_face(_p, K_STONE_NE),
			{"at": K_STONE_NE + Vector3(60, 34, 70), "look": K_STONE_NE.lerp(K_HOME, 0.4) + Vector3(0, 12, 0), "fov": 52.0},
			[[1.0, "an_oath_stone_and_its_chain_into_him"], [2.6, "brought_down_its_chain_snaps_and_he_reels"]],
			func(t: float) -> void:
				if t > 1.4 and t < 1.43:
					for n in _p.get_tree().root.find_children("world_kingsward_oath_stone_ne", "", true, false):
						if n is BreakableProp:
							(n as BreakableProp).on_entity_died(_p.entity.entity_id)],
		["stake", 5.0, func() -> void:
			_halt()
			_go(K_STAKE + Vector3(20, 0, 8))
			_face(_p, K_STAKE),
			{"at": K_STAKE + Vector3(60, 30, 60), "look": K_STAKE + Vector3(0, 14, 0), "fov": 50.0},
			[[1.0, "the_oath_stake_in_its_rock"], [func() -> bool: return bool(WorldState.get_flag("world.kingsward.stake_pulled", false)), "heaved_out_the_chains_go_slack"]],
			func(t: float) -> void:
				if t > 1.6 and t < 1.64:
					for n in _p.get_tree().root.find_children("world_kingsward_oath_stake", "", true, false):
						if n is BreakableProp:
							(n as BreakableProp).heave(_p)],
		["call", 4.5, func() -> void:
			_halt()
			_face_off(40.0)
			_t.brain.update_boss_phase(0.55, Sim.tick)
			_t.ai_enabled = false
			_attack("ability.hollow_call"),
			close, [[1.2, "the_hollow_call_his_second_phase"]]],
		["lash", 5.0, func() -> void:
			_halt()
			_face_off(45.0, 30.0)
			_t.ai_enabled = true
			_attack("ability.hollow_lash"),
			high, [[_running("ability.hollow_lash", ActionDef.Phase.ACTIVE, 0.4), "lash_circles_along_the_oath_chains"], [3.6, "the_chains_whip_down"]],
			func(t: float) -> void:
				if t > 4.2:
					_t.ai_enabled = false],
		["echo", 4.5, func() -> void:
			_halt()
			_face_off(20.0, 20.0)
			_hollow().resonance = float(_hollow().hollow.get("resonance_full", 12.0))
			_attack("ability.hollow_echo"),
			wide, [[_running("ability.hollow_echo", ActionDef.Phase.WINDUP, 0.5), "echo_his_shell_rings_full_warning_ring"],
				[_running("ability.hollow_echo", ActionDef.Phase.ACTIVE, 0.5), "the_echo_given_back"]]],
		["unbinding", 6.0, func() -> void:
			_halt()
			_face_off(40.0)
			_t.brain.update_boss_phase(0.2, Sim.tick)
			_t.ai_enabled = true
			_attack("ability.hollow_unbinding"),
			high, [[1.6, "the_unbinding_nothing_comes_back_now"], [4.6, "stones_fall_from_the_ridge"]],
			func(t: float) -> void:
				if t > 5.5:
					_t.ai_enabled = false],
		["topple", 5.0, func() -> void:
			_halt()
			_hale(0.4)
			_face_off(20.0, 30.0),
			close, [[1.0, "his_greave_broken"], [3.0, "down_on_a_knee_the_knot_within_reach"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_t.break_plate("greave_l")],
		["death", 9.0, func() -> void:
			_halt()
			_t.ai_enabled = false
			_face_off(40.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 70.0, "dist": 100.0, "h": 28.0, "look": 12.0, "on": "titan"},
			[[1.6, "the_knot_breaks_his_knees_go"], [4.0, "his_harness_comes_apart"], [8.4, "fallen_nothing_inside", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("knot", 5000.0)],
		["after", 5.0, func() -> void:
			WorldState.try_set_flag("world.kingsward.at_rest", true)
			_ui_on(false)
			_go(K_WAIT + Vector3(10, 0, 20)),
			{"at": K_HOME + Vector3(70, 30, 55), "look": K_HOME + Vector3(0, 6, 0), "fov": 50.0},
			[[4.5, "the_barrow_the_herders_raised_over_him"]]],
		["oath_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.hollow"))
			Armour.refresh_player(_p)
			if _p.equipment != null:
				_p.equipment.grant_weapon("weapon.oathblade", true)
			_go(K_GATE + Vector3(30, 0, 30))
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": K_GATE + Vector3(102, 22, 36), "look": K_GATE + Vector3(30, 18, 30), "fov": 44.0},
			[[2.0, "the_oathbound_set_and_the_oathblade_front"], [4.5, "oathbound_set_back", {"at": K_GATE + Vector3(-42, 22, 24),
				"look": K_GATE + Vector3(30, 18, 30), "fov": 44.0}]]],
		["stand", 3.5, func() -> void:
			_ui_on(false)
			_go(K_STAND + Vector3(70, 0, 30)),
			{"at": K_STAND + Vector3(34, 16, 34), "look": K_STAND + Vector3(-22, 2, -4), "fov": 44.0},
			[[3.0, "the_empty_stand_brann_and_the_empty_kings_tracks"]]],
		["track", 3.5, func() -> void:
			_go(K_GATE + Vector3(60, 0, -20)),
			{"at": K_GATE + Vector3(110, 40, -30), "look": K_CENTRE + Vector3(-10, 14, -20), "fov": 50.0},
			[[3.0, "the_kings_track_up_into_the_kingsward"]]],
		["end", 1.0, func() -> void: pass, {}, [], func(_t2: float) -> void: pass],
	]
