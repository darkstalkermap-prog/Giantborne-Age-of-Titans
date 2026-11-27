class_name CaptureKeep
extends CaptureQuarry
## C2: the Broken Warden's capture tour - --scenario=capture_keep in the real world films him at the old toll-keep
## above the toll fort and saves a still at each moment the beats name (c2_NN_<moment>.png under user://captures or
## --capture-dir=): the keep from the toll fort's tower and from the King's Road with him asleep in its breach, the yard
## inside, his wake, each attack (the shield bash, the gate-bar's blow and its shock line, the bar sweep, the wall
## charge reeling on his own wall, the stomp at a giant hugging his legs), his guard (a blow on the shield chipping
## stone; the guard broken open, a heavy into the gap), a crumbling tower brought down on him, his back's portcullis
## and the iron of his broken side broken, a greave broken - he goes down on a knee - the shield broken off his arm
## (disarm: it falls; his second phase, the bar in both hands), the two-handed smash and sweep, his death, the keep
## opened after (the masons' crane in his breach), the Bastion set on the giant, front and back, and the Character
## menu's Titans tab:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/bastion_tour.avi] -- --no-user-settings --mode=world --start=world.cp.aldmere_road \
##     --scenario=capture_keep --skin --capture-dir=<out>
##
## As CaptureQuarry's tour: his AI is off, each beat forces his attack, the giant (stage 5) is healed every tick, the
## plates break under synthetic heavy blows through the ordinary resolution (struck from where the giant stands: from
## before his shield they land on it). The HUD and the damage numbers are hidden.

const SHOT_PREFIX_C2 := "c2"
const WARDEN_ID := "world.aldmere.bastion"
## His post in the breach of the keep's north curtain; the giant's places: on the King's Road below, in the yard.
const HOME := Vector3(706, 24.6, 189)
const WAIT := Vector3(560, 24.0, 262)
const ROAD := Vector3(600, 24.0, 254)
const YARD := Vector3(705, 24.6, 230)
const FORT_TOWER := Vector3(475, 0, 357)
const TOWER_W := "world.aldmere.warden_tower_w"

var _ui_layer: CanvasLayer = null


func _titan_id() -> String:
	return WARDEN_ID


func _wait_at() -> Vector3:
	return WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_C2, n, moment]


func _setup() -> void:
	super()
	_t.ai_enabled = false
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		_ui_layer = layer as CanvasLayer


## His post, the giant `d` m before him (toward the yard), facing him; `az` turns the giant round him (+: his right).
func _face_off(d: float, az := 0.0) -> void:
	var home := _floor(HOME.x, HOME.z)
	var yaw := deg_to_rad(156.0)   # (his post's facing: into the yard)
	var front := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var turned := front.rotated(Vector3.UP, deg_to_rad(-az))
	var at := _floor(home.x + turned.x * d, home.z + turned.z * d)
	_stage(home, home + front * 10.0, at)


func _wake() -> void:
	if _t.dormant:
		_t.wake("struck")
	_t.ai_enabled = false


## His health back to at least `frac` of its whole (the tour's blows would end him before his death's beat).
func _hale(frac := 0.8) -> void:
	var pools := _t.entity.combatant.pools
	pools.health = maxf(pools.health, pools.health_max * frac)


func _halt() -> void:
	if _t.controller.action != null:
		_t.controller.call("_finish_action", true)


func _tower() -> BreakableProp:
	for b in _p.get_tree().get_nodes_in_group("breakables"):
		if str(b.get("world_id")) == TOWER_W:
			return b as BreakableProp
	return null


## A heavy of the giant's into the crumbling tower (the ordinary resolution: it falls).
func _smash_tower() -> void:
	var tw := _tower()
	if tw == null:
		notes.append("no crumbling tower %s" % TOWER_W)
		return
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = _p.entity.entity_id
	e.target_id = tw.entity.entity_id
	e.power = 5000.0
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.poise_damage = 40.0
	e.tags = PackedStringArray(["Melee", "Heavy"])
	e.attacker_position = _p.global_position
	e.hit_point = tw.global_position + Vector3.UP * 4.0
	Sim.queue_hit(e)


func _ui(screen: String, on: bool) -> void:
	if _ui_layer != null:
		_ui_layer.visible = on
	var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
	if stack == null:
		notes.append("no screen stack for %s" % screen)
		return
	if on:
		stack.open(screen, {})
	else:
		stack.close_all()


func _make_beats() -> Array:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--c2-beats="):
			only = arg.substr(11)
	var all := _tour_beats()
	if only == "":
		return all
	return all.filter(func(b: Array) -> bool: return str(b[0]) in only.split(",", false))


func _tour_beats() -> Array:
	var wide := {"az": 25.0, "dist": 46.0, "h": 12.0, "look": 12.0, "on": "mid"}
	var side := {"az": -75.0, "dist": 42.0, "h": 10.0, "look": 11.0, "on": "mid"}
	var high := {"az": 30.0, "dist": 46.0, "h": 30.0, "look": 6.0, "on": "mid"}
	var shield := {"az": -35.0, "dist": 30.0, "h": 12.0, "look": 10.0, "on": "titan"}
	var behind := {"az": 160.0, "dist": 30.0, "h": 16.0, "look": 14.0, "on": "titan"}
	return [
		["fort", 3.0, func() -> void:
			_grow(5)
			_go(ROAD)
			_face(_p, HOME),
			{"at": _floor(FORT_TOWER.x, FORT_TOWER.z) + Vector3(0, 34, 0), "look": HOME + Vector3(0, 10, 0), "fov": 30.0},
			[[2.5, "keep_from_the_toll_fort"]]],
		["road", 3.0, func() -> void:
			_go(WAIT),   # (the giant out of the frame: the view is the road's)
			{"at": ROAD + Vector3(4, 14, -2), "look": HOME + Vector3(0, 10, 0), "fov": 34.0},
			[[2.5, "keep_from_the_kings_road_dormant"]]],
		["yard", 3.0, func() -> void:
			_go(YARD + Vector3(30, 0, 40)),   # (the giant out of the frame)
			{"at": YARD + Vector3(4, 12, 18), "look": HOME + Vector3(0, 11, 0), "fov": 58.0},
			[[2.5, "yard_inside_the_keep_dormant"]]],
		["wake", 4.5, func() -> void:
			_face_off(30.0)
			_wake(),
			wide, [[2.4, "wake_roar", {"az": 15.0, "dist": 36.0, "h": 6.0, "look": 16.0, "on": "titan"}]]],
		["bash", 4.0, func() -> void:
			_face_off(11.0)
			_attack("ability.bastion_bash"),
			side, [[_running("ability.bastion_bash", ActionDef.Phase.WINDUP, 0.6), "bash_windup"],
				[_running("ability.bastion_bash", ActionDef.Phase.ACTIVE, 0.3), "bash_strike"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.04:
					_dodge(Vector2(1, 0))],
		["hammer", 5.0, func() -> void:
			_face_off(26.0)
			_attack("ability.bastion_hammer"),
			high, [[_running("ability.bastion_hammer", ActionDef.Phase.WINDUP, 0.7), "hammer_telegraph"],
				[_running("ability.bastion_hammer", ActionDef.Phase.ACTIVE, 0.6), "hammer_shock_line", side],
				[_running("ability.bastion_hammer", ActionDef.Phase.RECOVERY, 0.3), "hammer_recovery_guard_down", shield]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.24:
					_dodge(Vector2(1, 0))],
		["sweep", 4.0, func() -> void:
			_face_off(12.0, 60.0)
			_attack("ability.bastion_sweep"),
			wide, [[_running("ability.bastion_sweep", ActionDef.Phase.WINDUP, 0.6), "sweep_windup"],
				[_running("ability.bastion_sweep", ActionDef.Phase.ACTIVE, 0.4), "sweep_strike"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.04:
					_dodge(Vector2(0, 1))],
		["charge", 6.5, func() -> void:
			_face_off(1.0)
			_t.global_position = _floor(700, 236)
			_p.global_position = _floor(686, 206)   # (beyond the giant: the curtain west of his breach)
			_face(_t, _p.global_position)
			_attack("ability.bastion_charge"),
			{"az": -80.0, "dist": 50.0, "h": 14.0, "look": 10.0, "on": "titan"},
			[[_running("ability.bastion_charge", ActionDef.Phase.WINDUP, 0.6), "charge_telegraph"],
				[_running("ability.bastion_charge", ActionDef.Phase.ACTIVE, 0.3), "charge_run"],
				[func() -> bool: return _t.controller.action_id() == "ability.bastion_reel", "charge_reels_on_his_wall"]],
			func(t: float) -> void:
				if t > 1.2 and t < 1.24:
					_dodge(Vector2(1, 0))],
		["stomp", 4.0, func() -> void:
			_face_off(5.0, -20.0)
			_attack("ability.bastion_stomp"),
			{"az": 70.0, "dist": 32.0, "h": 9.0, "look": 8.0, "on": "titan"},
			[[_running("ability.bastion_stomp", ActionDef.Phase.WINDUP, 0.6), "stomp_raised"],
				[_running("ability.bastion_stomp", ActionDef.Phase.ACTIVE, 0.3), "stomp_impact"]]],
		["guard", 7.0, func() -> void:
			_halt()
			_hale()
			_face_off(14.0, -10.0),
			shield, [[0.6, "guard_blow_on_the_shield"], [3.4, "guard_broken_open"], [4.6, "heavy_into_the_open_guard"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_swing()
					_blow("torso", 400.0)
				if t > 1.4 and t < 1.43:
					_blow("torso", 400.0)
				if t > 2.9 and t < 2.93:
					_t.break_guard()
				if t > 3.8 and t < 3.83:
					_swing()
				if t > 4.3 and t < 4.33:
					_blow("shin_l", 300.0)],
		["rubble", 6.0, func() -> void:
			_halt()
			_hale()
			_t.global_position = _floor(HOME.x, HOME.z)
			_p.global_position = _floor(684, 206)
			_face(_p, _tower().global_position if _tower() != null else HOME),
			{"at": _floor(724, 236) + Vector3(0, 20, 0), "look": _floor(698, 196) + Vector3(0, 10, 0), "fov": 55.0},
			[[0.5, "rubble_tower_beside_him"], [1.6, "rubble_tower_falls_on_him"], [3.2, "rubble_dazed"]],
			func(t: float) -> void:
				if t > 0.8 and t < 0.83:
					_swing()
				if t > 1.0 and t < 1.03:
					_smash_tower()],
		["back", 6.0, func() -> void:
			_halt()
			_hale()
			_face_off(12.0, 175.0),
			behind, [[0.9, "portcullis_broken"], [4.4, "mend_broken_old_wound",
				{"az": 100.0, "dist": 22.0, "h": 15.0, "look": 14.0, "on": "titan"}]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("back", 3000.0)
				if t > 3.6 and t < 3.63:
					_p.global_position = _round_titan(95.0, 12.0)
					_face(_p, _t.global_position)
					_blow("flank_r", 2000.0)],
		["disarm", 8.0, func() -> void:
			_halt()
			_hale()
			_face_off(16.0, -15.0),
			shield, [[0.7, "shield_broken_falls"], [2.6, "shield_on_the_ground", wide],
				[_running("ability.bastion_rearm", ActionDef.Phase.ACTIVE, 0.3), "rearm_phase_2_two_handed", wide]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shield", 12000.0)
					if not _t.plates().is_broken("shield"):
						_t.break_plate("shield")
				if t > 1.2 and t < 1.23 and _t.controller.action_id() != "ability.bastion_rearm":
					_attack("ability.bastion_rearm")],
		["smash2", 5.0, func() -> void:
			_hale(0.3)
			_face_off(24.0)
			_attack("ability.bastion_smash2"),
			high, [[_running("ability.bastion_smash2", ActionDef.Phase.WINDUP, 0.7), "smash2_telegraph"],
				[_running("ability.bastion_smash2", ActionDef.Phase.ACTIVE, 0.6), "smash2_shock_line", side]],
			func(t: float) -> void:
				if t > 0.9 and t < 0.94:
					_dodge(Vector2(1, 0))],
		["sweep2", 4.0, func() -> void:
			_hale(0.3)
			_face_off(12.0, 40.0)
			_attack("ability.bastion_sweep2"),
			wide, [[_running("ability.bastion_sweep2", ActionDef.Phase.WINDUP, 0.6), "sweep2_windup"],
				[_running("ability.bastion_sweep2", ActionDef.Phase.ACTIVE, 0.4), "sweep2_strike"]],
			func(t: float) -> void:
				if t > 0.8 and t < 0.84:
					_dodge(Vector2(0, 1))],
		["topple", 6.0, func() -> void:
			_halt()
			_hale(0.3)
			_face_off(10.0, 120.0),
			{"az": 75.0, "dist": 34.0, "h": 8.0, "look": 9.0, "on": "titan"},
			[[1.6, "greave_broken_topple"], [4.0, "strike_at_his_lowered_helm", {"az": 40.0, "dist": 26.0, "h": 14.0,
				"look": 9.0, "on": "mid"}]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shin_r", 4000.0)
					if not _t.plates().is_broken("greave_r"):
						_t.break_plate("greave_r")
				if t > 2.6 and t < 2.63:
					_p.global_position = _round_titan(30.0, 9.0)
					_face(_p, (_t.get_node("Anchors/PlateHelm") as Node3D).global_position)
					_swing()
				if t > 3.4 and t < 3.43:
					_blow("head", 400.0)],
		["death", 7.5, func() -> void:
			_halt()
			_face_off(24.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 80.0, "dist": 40.0, "h": 10.0, "look": 7.0, "on": "titan"},
			[[1.6, "death_fall"], [6.8, "fallen", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 4000.0)],
		["leave", 1.0, func() -> void:
			_go(Vector3(470, 0, 60)),   # (the giant goes on beyond his territory: the keep opens behind it)
			{"at": Vector3(480, 60, 80), "look": Vector3(470, 20, 60), "fov": 55.0}, []],
		["opened", 5.0, func() -> void:
			_go(ROAD),
			{"at": HOME + Vector3(-24, 26, 64), "look": HOME + Vector3(0, 6, 10), "fov": 58.0},
			[[4.5, "keep_opened_the_masons_crane"]]],
		["bastion_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.bastion"))
			Armour.refresh_player(_p)
			_go(YARD)
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": YARD + Vector3(18, 7, 0), "look": YARD + Vector3(0, 7.5, 0), "fov": 50.0},
			[[2.0, "bastion_set_front"], [4.5, "bastion_set_back", {"at": YARD + Vector3(-18, 7, 0),
				"look": YARD + Vector3(0, 7.5, 0), "fov": 50.0}]]],
		["titans_tab", 4.0, func() -> void:
			_ui("character", true)
			var stack := _p.get_tree().get_first_node_in_group(ScreenStack.GROUP) as ScreenStack
			var cs := stack.top() as CharacterScreen if stack != null else null
			if cs != null:
				cs.show_tab(3),
			{}, [[2.0, "character_titans_tab", {}]], func(_t: float) -> void: pass],
		["end", 1.0, func() -> void: _ui("character", false), {}, [], func(_t: float) -> void: pass],
	]


## D3: the giant's stage the tour fights at - --capture-stage=<n> on the command line, else `fallback` (the tour's own).
static func capture_stage(fallback: int) -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-stage="):
			return clampi(int(arg.substr(16)), 1, 10)
	return fallback
