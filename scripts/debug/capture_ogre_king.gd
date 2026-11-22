class_name CaptureOgreKing
extends CaptureTitan
## B2: the Ogre King's capture tour - --scenario=capture_ogre_king on the boss arena test level (P11a's Kingsfall
## arena at the origin) films his fight against a stage-2 giant (the Valley fight's size), beat by beat, with
## CaptureTitan's camera and machinery, and saves a still at each moment (b2_NN_<moment>.png): the face-off, the
## two-blow combo, the slam, the bell cracking, splintering and broken (the weak point struck), the charge into a
## pillar and his reel, a wheel torn off, the keg bursting and his fall to a knee, the crown within reach and
## broken, his death. With --write-movie the same run is the fight's movie:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/ogre_king_fight.avi] -- --no-user-settings \
##     --level=res://scenes/test/boss_arena_test.tscn --scenario=capture_ogre_king --skin --capture-dir=<out>
##
## As CaptureTitan: his AI off, each beat forces his attack (his brain's target the giant), the trophies break under
## synthetic heavy blows through the ordinary resolution (the region set, as a swing's hurtbox sets it), the giant
## healed every tick.

const KING_STAGE := 2


func _shot_name(n: int, moment: String) -> String:
	return "b2_%02d_%s.png" % [n, moment]


func _setup() -> void:
	TitanDuel.prepare(_p, KING_STAGE)
	var main := _auto.get_parent() if _auto != null else null
	var layer: Variant = main.get("_layer") if main != null and "_layer" in main else null
	if layer is CanvasLayer:
		(layer as CanvasLayer).visible = false
	_t.ai_enabled = false
	_t.brain.target_id = _p.entity.entity_id
	var arena := _p.get_tree().get_first_node_in_group(BossArena.GROUP) as BossArena
	if arena != null:
		arena.engage()


## A blow of raw `power` on the King's region (CaptureTitan._blow, its hit point at his chest's height).
func _hit(region: String, power: float) -> void:
	_blow(region, power)


func _make_beats() -> Array:
	var wide := {"az": 24.0, "dist": 24.0, "h": 4.5, "look": 4.5, "on": "mid"}
	var side := {"az": -65.0, "dist": 20.0, "h": 3.5, "look": 4.6, "on": "mid"}
	var chest := {"az": 18.0, "dist": 12.0, "h": 5.0, "look": 5.2, "on": "titan"}
	return [
		["face_off", 3.0, func() -> void:
			_stage(Vector3(0, 0.05, 8), Vector3(0, 0, -8), Vector3(0, 0.05, -6))
			_walk(Vector2(0, -0.3)),
			wide, [[2.2, "face_off", {"az": 10.0, "dist": 18.0, "h": 3.0, "look": 5.5, "on": "player"}]]],
		["combo", 3.6, func() -> void:
			_stage(Vector3(0, 0.05, 8), Vector3(0, 0, 0), Vector3(0, 0.05, 3))
			_attack("ability.boss_combo_1"),
			side, [[_running("ability.boss_combo_1", ActionDef.Phase.WINDUP, 0.7), "combo_telegraph"],
				[_running("ability.boss_combo_1", ActionDef.Phase.ACTIVE, 0.4), "combo_first_blow"],
				[_running("ability.boss_combo_2", ActionDef.Phase.ACTIVE, 0.4), "combo_second_blow"]]],
		["slam", 4.2, func() -> void:
			_stage(Vector3(0, 0.05, 8), Vector3(0, 0, 0), Vector3(-5, 0.05, 1))
			_attack("ability.boss_slam"),
			{"az": -40.0, "dist": 22.0, "h": 4.0, "look": 5.0, "on": "titan"},
			[[_running("ability.boss_slam", ActionDef.Phase.WINDUP, 0.8), "slam_raised"],
				[_running("ability.boss_slam", ActionDef.Phase.ACTIVE, 0.6), "slam_impact"],
				[_running("ability.boss_slam", ActionDef.Phase.RECOVERY, 0.35), "slam_recover"]],
			func(t: float) -> void:
				if t > 0.6 and t < 0.65:
					_dodge(Vector2(-1, 0))],
		["bell", 4.6, func() -> void:
			_stage(Vector3(0, 0.05, 8), Vector3(0, 0, 0), Vector3(0, 0.05, 2)),
			chest, [[0.7, "bell_cracked"], [1.5, "bell_badly_cracked"], [2.35, "bell_splinters"],
				[3.9, "bell_weak_point", {"az": 30.0, "dist": 14.0, "h": 3.5, "look": 4.6, "on": "titan"}]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_hit("belly", 90.0)
				if t > 1.0 and t < 1.03:
					_hit("belly", 45.0)
				if t > 2.2 and t < 2.23:
					_hit("belly", 400.0)
				if t > 3.2 and t < 3.23:
					_swing()],
		["charge", 6.5, func() -> void:
			_stage(Vector3(-12, 0.05, 0), Vector3(30, 0, 0), Vector3(12, 0.05, 0))
			_attack("ability.boss_charge"),
			{"az": 75.0, "dist": 26.0, "h": 4.0, "look": 4.5, "on": "mid"},
			[[_running("ability.boss_charge", ActionDef.Phase.WINDUP, 0.85), "charge_telegraph"],
				[_running("ability.boss_charge", ActionDef.Phase.ACTIVE, 0.06), "charge_run",
					{"az": 95.0, "dist": 22.0, "h": 3.5, "look": 4.5, "on": "titan"}],
				[func() -> bool: return _t.controller.action_id() == "ability.boss_wall_recover" \
						and _t.controller.elapsed > 30, "charge_reel", {"az": 150.0, "dist": 18.0, "h": 5.0, "look": 5.0, "on": "titan"}]],
			func(t: float) -> void:
				if t < 0.85:
					_p.global_position = Vector3(12, 0.05, 0)
				if t > 0.9 and t < 0.95:
					_dodge(Vector2(0, 1))],
		["wheel", 3.0, func() -> void:
			_stage(_t.global_position, _p.global_position, _round_titan(40.0, 12.0)),
			{"az": 70.0, "dist": 13.0, "h": 7.5, "look": 6.8, "on": "titan"},
			[[0.5, "wheel_splinters"], [2.2, "wheel_gone"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_hit("shoulder_r", 400.0)],
		["keg", 6.0, func() -> void:
			_stage(Vector3(0, 0.05, 4), Vector3(0, 0, -10), Vector3(0, 0.05, 11)),
			{"az": 160.0, "dist": 15.0, "h": 4.5, "look": 4.5, "on": "titan"},
			[[0.55, "keg_bursts"], [1.4, "king_kneels", {"az": 25.0, "dist": 15.0, "h": 3.0, "look": 4.0, "on": "titan"}],
				[2.4, "crown_in_reach", {"az": -20.0, "dist": 10.0, "h": 5.5, "look": 4.8, "on": "titan"}],
				[3.3, "crown_breaks"]],
			func(t: float) -> void:
				if t > 0.25 and t < 0.28:
					_hit("back", 400.0)
				if t > 1.2 and t < 1.23:
					_p.global_position = _round_titan(0.0, 7.0)
					_face(_p, _t.global_position)
				if t > 3.0 and t < 3.03:
					_hit("head", 500.0)],
		["death", 6.5, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_t.entity.combatant.pools.health = 30.0
			_swing(),
			{"az": 60.0, "dist": 22.0, "h": 4.0, "look": 3.5, "on": "titan"},
			[[1.4, "death_fall"], [5.6, "fallen", {"az": 35.0, "dist": 22.0, "h": 8.0, "look": 1.0, "on": "titan"}]],
			func(t: float) -> void:
				if t > 0.4 and t < 0.43 and _t.entity.is_alive():
					_hit("belly", 900.0)],
	]
