class_name CaptureMoot
extends CaptureKeep
## E1: Orrik the Fetterer's capture tour - --scenario=capture_moot in the real world films the challenge for the Stone
## Throne at the Moot and saves a still at each moment the beats name (e1_NN_<moment>.png under user://captures or
## --capture-dir=): the Moot from its foot with the winches staked in the ring and Orrik before the throne, Orrik beside
## a stage-8 and a stage-9 giant, each of his attacks with its warning (the sweep, the cleaving chop, the charge, the
## stamp), a fetter-winch's aim line and its harpoon biting, the chain on the giant's leg and the HUD's chain meter, the
## Throne-breaker raised over a chained giant, the chain torn by a heave and the step out of the axe's line, his hook
## thrown, biting and the haul, the hook torn and Orrik yanked off his feet, a winch trodden into the ground, his helm and
## his chain-coil broken off him, the war-horn bringing the reserve winches, the warband's fire-pots, his fall, the
## Moot after (his banners struck; the sworn clans, or Harrok holding it), the Fetterer's set on the giant, front and
## back. --e1-branch=spared runs the ally branch: Harrok comes in by the gate, cuts a chain off the giant, strikes at
## Orrik's legs, and holds the Moot after.
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/e1_tour.avi] -- --no-user-settings --mode=world --start=world.cp.moot_foot \
##     --scenario=capture_moot --skin --capture-dir=<out> [--e1-branch=spared] [--e1-beats=a,b,...] [--capture-stage=9]
##
## As CaptureKeep's tour: his AI is off, each beat forces his attack (or a winch's shot), the giant is healed every tick,
## the plates break under synthetic heavy blows through the ordinary resolution; the chains are the game's own (a
## harpoon that strikes binds through PlayerFetter).

const SHOT_PREFIX_E1 := "e1"
const ORRIK_ID := "world.stonehold.orrik"
const M_HOME := Vector3(0, 95.0, -764)
const M_CENTRE := Vector3(0, 95.0, -745)
const M_FOOT := Vector3(-70, 95.0, -650)
const M_WAIT := Vector3(-40, 95.0, -700)
const M_THRONE := Vector3(0, 95.0, -800)

var _flags_set := false
var _branch := "slain"


func _titan_id() -> String:
	return ORRIK_ID


func _wait_at() -> Vector3:
	return M_WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_E1, n, moment]


func step(player: GiantPlayer, dt: float) -> bool:
	if not _flags_set:
		_flags_set = true
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--e1-branch="):
				_branch = arg.substr(12)
		for f: String in ["act.two.begun", "boss.frostbound.defeated", "boss.stormcaller.defeated", "lead.harrok.hearth",
				"boss.harrok.defeated"]:
			WorldState.set_flag(f, true)
		WorldState.flags["campaign.completed"] = true
		WorldState.set_flag("boss.harrok.outcome", _branch)
		if _branch == "slain":
			WorldState.set_flag("world.moot.empty", true)
		GameSession.expansion["act"] = 2
	return super(player, dt)


func _setup() -> void:
	super()
	TitanDuel.prepare(_p, CaptureKeep.capture_stage(8))
	_t.ai_enabled = false
	Settings.set_value("damage_numbers", false, false)


## His post before the throne, the giant `d` m before him (toward the gate), `az` round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	var home := _floor(M_HOME.x, M_HOME.z)
	var to_gate := (Vector3(-38, 0, -698) - home)
	to_gate.y = 0.0
	var front := to_gate.normalized()
	var turned := front.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + front * 10.0, at)


func _heir() -> HeirEnemy:
	return _t as HeirEnemy


func _arena() -> ThroneChallenge:
	for n in _p.get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is ThroneChallenge:
			return n
	return null


func _winch(i: int) -> FetterWinch:
	for n in _p.get_tree().get_nodes_in_group("fetter_winches"):
		var w := n as FetterWinch
		if w != null and w.world_id == "world.stonehold.fetter_winch_%d" % i:
			return w
	return null


## Winch `i` frees its fire (the others hold theirs): its next shot is at the giant.
func _loose(i: int) -> void:
	for n in _p.get_tree().get_nodes_in_group("fetter_winches"):
		var w := n as FetterWinch
		if w != null:
			w.set_fire_held(w != _winch(i))
			if w == _winch(i):
				w.reload_left = 0.0


func _hold_all() -> void:
	for n in _p.get_tree().get_nodes_in_group("fetter_winches"):
		(n as FetterWinch).set_fire_held(true)


func _winch_aiming(i: int) -> Callable:
	return func() -> bool:
		var w := _winch(i)
		return w != null and w.controller.action != null and w.controller.phase() == ActionDef.Phase.WINDUP and w.aim_locked()


func _chained() -> Callable:
	return func() -> bool: return _p.fetter.count() > 0


func _free() -> Callable:
	return func() -> bool: return _p.fetter.count() == 0


func _heave() -> void:
	_p.entity.combatant.pools.stamina = _p.entity.combatant.pools.stamina_max
	_p.router.inject_edge(&"heavy")


func _ally() -> HarrokAlly:
	var a := _arena()
	return a.ally as HarrokAlly if a != null and a.ally != null and is_instance_valid(a.ally) else null


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--e1-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _tour_beats() -> Array:
	var wide := {"az": 30.0, "dist": 95.0, "h": 34.0, "look": 18.0, "on": "mid"}
	var side := {"az": -70.0, "dist": 80.0, "h": 24.0, "look": 18.0, "on": "mid"}
	var high := {"az": 20.0, "dist": 110.0, "h": 70.0, "look": 10.0, "on": "mid"}
	var close := {"az": 35.0, "dist": 48.0, "h": 26.0, "look": 22.0, "on": "titan"}
	var legs := {"az": 60.0, "dist": 40.0, "h": 10.0, "look": 4.0, "on": "player"}
	return [
		["foot", 3.0, func() -> void:
			_go(M_FOOT + Vector3(-30, 0, 30))
			_hold_all(),
			{"at": M_FOOT + Vector3(0, 40, 0), "look": M_CENTRE + Vector3(0, 12, 0), "fov": 42.0},
			[[2.5, "the_moot_from_its_foot_winches_staked_orrik_waiting"]]],
		["beside8", 3.0, func() -> void:
			_face_off(24.0, 90.0),
			{"az": 0.0, "dist": 120.0, "h": 18.0, "look": 17.0, "on": "mid"},
			[[2.5, "orrik_beside_a_stage_8_giant"]]],
		["beside9", 3.5, func() -> void:
			_grow(9)
			_face_off(26.0, 90.0),
			{"az": 0.0, "dist": 130.0, "h": 19.0, "look": 18.0, "on": "mid"},
			[[3.0, "orrik_beside_a_stage_9_giant"]]],
		["engage", 3.0, func() -> void:
			_grow(CaptureKeep.capture_stage(8))
			_face_off(40.0)
			var a := _arena()
			if a != null:
				a.engage()
			_t.ai_enabled = false
			_hold_all(),
			wide, [[2.6, "the_challenge_engaged"]]],
		["sweep", 3.6, func() -> void:
			_face_off(14.0, 10.0)
			_attack("ability.orrik_combo_1"),
			side, [[_running("ability.orrik_combo_1", ActionDef.Phase.WINDUP, 0.55), "axe_sweep_warning"],
				[_running("ability.orrik_combo_2", ActionDef.Phase.ACTIVE, 0.4), "axe_back_stroke"]]],
		["chop", 4.0, func() -> void:
			_halt()
			_face_off(22.0)
			_attack("ability.orrik_chop"),
			high, [[_running("ability.orrik_chop", ActionDef.Phase.WINDUP, 0.6), "cleaving_chop_warning_line"],
				[_running("ability.orrik_chop", ActionDef.Phase.ACTIVE, 0.5), "cleaving_chop_splits_the_ground", side]],
			func(t: float) -> void:
				if t > 1.05 and t < 1.09:
					_dodge(Vector2(1, 0))],
		["charge", 5.0, func() -> void:
			_halt()
			_face_off(50.0)
			_attack("ability.orrik_charge"),
			{"az": -80.0, "dist": 100.0, "h": 26.0, "look": 14.0, "on": "mid"},
			[[_running("ability.orrik_charge", ActionDef.Phase.WINDUP, 0.6), "charge_warning_line"],
				[_running("ability.orrik_charge", ActionDef.Phase.ACTIVE, 0.25), "charge_runs"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.04:
					_dodge(Vector2(1, 0))],
		["harpoon", 7.0, func() -> void:
			_halt()
			_face_off(30.0, -30.0)
			_loose(1),
			{"at": M_CENTRE + Vector3(70, 46, 50), "look": M_CENTRE + Vector3(0, 6, -20), "fov": 50.0},
			[[_winch_aiming(1), "winch_aim_line_on_the_giant"], [_chained(), "harpoon_bites_the_chain_holds"],
				[0.8, "chain_on_the_leg_and_the_chain_meter", legs]],
			func(_t2: float) -> void:
				if _ui_layer != null:
					_ui_layer.visible = _p.fetter.count() > 0],   # (the HUD's chain meter in this beat's last shot)
		["breaker", 6.5, func() -> void:
			if _ui_layer != null:
				_ui_layer.visible = false
			_hold_all()
			_t.global_position = _floor(_p.global_position.x + 0, _p.global_position.z - 16.0)
			_face(_t, _p.global_position)
			_attack("ability.orrik_throne_breaker"),
			side, [[_running("ability.orrik_throne_breaker", ActionDef.Phase.WINDUP, 0.35), "throne_breaker_raised_over_a_chained_giant"],
				[_free(), "chain_torn_by_a_heave", close],
				[_running("ability.orrik_throne_breaker", ActionDef.Phase.ACTIVE, 0.6), "out_of_the_axes_line", wide]],
			func(t: float) -> void:
				if t > 0.9 and t < 0.94:
					_heave()
				if t > 2.0 and t < 2.04:
					_dodge(Vector2(1, 0))],
		["hook", 7.5, func() -> void:
			_halt()
			_p.fetter.release_all("cut")
			_face_off(48.0, 20.0)
			_attack("ability.orrik_hook"),
			{"az": -55.0, "dist": 90.0, "h": 30.0, "look": 14.0, "on": "mid"},
			[[_running("ability.orrik_hook", ActionDef.Phase.WINDUP, 0.5), "chain_hook_swung_aim_line"],
				[_chained(), "hook_bites"], [func() -> bool: return _heir().hauls > 0 and _t.controller.phase() == ActionDef.Phase.ACTIVE, "the_haul_drags_the_giant_in"],
				[func() -> bool: return _heir().yanks > 0, "hook_torn_orrik_yanked_off_his_feet", close]],
			func(t: float) -> void:
				if _heir().hooks_bit > 0 and _heir().hauls == 0 and _t.controller.action == null:
					_attack("ability.orrik_haul")
				if t > 4.4 and t < 4.44:
					_heave()],
		["trample", 6.0, func() -> void:
			_halt()
			var w := _winch(2)
			if w != null:
				_go(w.global_position + (w.global_position - M_CENTRE).normalized() * -40.0)
				_face(_p, w.global_position),
			{"at": M_CENTRE + Vector3(80, 40, -30), "look": M_CENTRE + Vector3(30, 4, -30), "fov": 48.0},
			[[4.5, "a_winch_trodden_into_the_ground"]],
			func(_t2: float) -> void:
				var w := _winch(2)
				if w != null and not w.destroyed:
					var to := w.global_position - _p.global_position
					to.y = 0.0
					_p.camera_rig.yaw = TargetingRules.yaw_of(to)
					_walk(Vector2(0, 1))
				else:
					_walk(Vector2.ZERO)],
		["helm", 4.0, func() -> void:
			_halt()
			_hale(0.7)
			_face_off(16.0, 30.0),
			close, [[1.5, "helm_broken_off_him"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_t.break_plate("helm")],
		["coil", 4.0, func() -> void:
			_halt()
			_face_off(16.0, -40.0),
			{"az": -50.0, "dist": 44.0, "h": 20.0, "look": 16.0, "on": "titan"},
			[[1.5, "chain_coil_broken_no_more_hook"]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33:
					_t.break_plate("chain_coil")],
		["horn", 5.0, func() -> void:
			_halt()
			_face_off(36.0)
			_t.brain.update_boss_phase(0.6, Sim.tick)
			_t.ai_enabled = false,
			high, [[1.2, "war_horn_the_reserve_winches_join"]]],
		["stamp", 3.5, func() -> void:
			_halt()
			_face_off(6.0, 40.0)
			_attack("ability.orrik_stamp"),
			wide, [[_running("ability.orrik_stamp", ActionDef.Phase.WINDUP, 0.6), "stamp_warning"],
				[_running("ability.orrik_stamp", ActionDef.Phase.ACTIVE, 0.3), "stamp"]]],
		["fire", 7.0, func() -> void:
			_halt()
			_hold_all()
			_face_off(34.0)
			_t.brain.update_boss_phase(0.25, Sim.tick)
			_t.ai_enabled = true,
			high, [[3.0, "fire_pots_warning_circles"], [5.0, "fire_pots_burst"]],
			func(_t2: float) -> void:
				_hold_all()],
		["ally", 9.0, func() -> void:
			if _ui_layer != null:
				_ui_layer.visible = false
			_halt()
			_t.ai_enabled = false
			_face_off(28.0, 30.0)
			_loose(5),
			{"at": M_CENTRE + Vector3(-80, 40, 60), "look": M_CENTRE + Vector3(-20, 8, 10), "fov": 52.0},
			[[2.0, "harrok_beside_the_giant"], [func() -> bool: return _ally() != null and _ally().chains_cut > 0, "harrok_cuts_the_chain"],
				[func() -> bool: return _ally() != null and _ally().heir_blows > 0, "harrok_at_orriks_legs", wide]]],
		["death", 7.0, func() -> void:
			_halt()
			_hold_all()
			_t.ai_enabled = false
			_face_off(30.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 70.0, "dist": 90.0, "h": 26.0, "look": 10.0, "on": "titan"},
			[[1.8, "orrik_falls"], [6.4, "fallen_before_the_throne", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 5000.0)],
		["after", 6.0, func() -> void:
			if _branch == "slain":
				WorldState.try_set_flag("world.moot.clan_knelt", true)
			WorldState.try_set_flag("world.moot.settled", true)
			if _ui_layer != null:
				_ui_layer.visible = false
			_go(M_CENTRE + Vector3(-150, 0, 40)),   # (the giant behind the camera, near enough for the Moot's people to come)
			{"at": M_CENTRE + Vector3(-70, 50, 70), "look": M_CENTRE + Vector3(0, 10, -20), "fov": 50.0},
			[[5.5, "the_moot_after_banners_struck_and_who_holds_it"]]],
		["fetterer_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.fetterer"))
			Armour.refresh_player(_p)
			_p.fetter.release_all("cut")
			_go(M_CENTRE + Vector3(0, 0, 10))
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": M_CENTRE + Vector3(44, 17, 10), "look": M_CENTRE + Vector3(0, 15, 10), "fov": 48.0},
			[[2.0, "fetterer_set_front"], [4.5, "fetterer_set_back", {"at": M_CENTRE + Vector3(-44, 17, 10),
				"look": M_CENTRE + Vector3(0, 15, 10), "fov": 48.0}]]],
		["end", 1.0, func() -> void: pass, {}, [], func(_t2: float) -> void: pass],
	]
