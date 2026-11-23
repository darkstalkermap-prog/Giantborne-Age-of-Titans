class_name CaptureGrove
extends CaptureQuarry
## B3: the Rootwarden's capture tour - --scenario=capture_grove in the real world films him in his grove in the deep
## Greywood and saves a still at each moment the beats name (b3_NN_<moment>.png under user://captures or
## --capture-dir=): the grove from the warden ride's end with him asleep, his wake, each attack (the root-lash, the
## roots erupting along their line, the snare's circle, a dead tree ripped up and hurled, the stomp at a giant hugging
## his legs), a shoulder's bark broken (the sapwood glowing), growing back, then a wound seared by a brazier knocked
## over beside him, the knot of his root-arm broken (his roots withering) and his uprooting (his second phase), a shin
## broken - he goes down on a knee - and a blow struck back at his lowered shoulder, his death, the grove greened after
## the giant has gone on, Hollowmere after (the heartwood stacked by Wren's benches) and the Warden set on the giant,
## front and back:
##
##   xvfb-run -a -s "-screen 0 1280x720x24" tools/gd.sh --path . --rendering-driver opengl3 --fixed-fps 30 \
##     [--write-movie <out>/rootwarden_fight.avi] -- --no-user-settings --mode=world --start=world.cp.hollowmere \
##     --scenario=capture_grove --skin --capture-dir=<out>
##
## As CaptureQuarry's tour: his AI is off, each beat forces his attack, the giant (stage 5) is healed every tick, the
## plates break under synthetic heavy blows through the ordinary resolution; a wound's clock is moved on to show its
## regrowth within the beat. The HUD and the damage numbers are hidden.

const SHOT_PREFIX_B3 := "b3"
const WARDEN_ID := "world.greywood.rootwarden"
## His spot in the hollow (its floor 17.5 m) and the giant's places: out of his grove on the ride, at the lookout.
const HOME := Vector3(-796, 17.5, 186)
const WAIT := Vector3(-688, 20.0, 116)
const LOOKOUT := Vector3(-712, 20.0, 140)
const HOLLOWMERE := Vector3(-596, 21.0, -22)


func _titan_id() -> String:
	return WARDEN_ID


func _wait_at() -> Vector3:
	return WAIT


func _shot_name(n: int, moment: String) -> String:
	return "%s_%02d_%s.png" % [SHOT_PREFIX_B3, n, moment]


func _setup() -> void:
	super()
	_t.ai_enabled = false


## His spot, the giant `d` m before him (toward the arch), facing him.
func _face_off(d: float) -> void:
	var front := _floor(HOME.x + 0.96 * d, HOME.z - 0.28 * d)
	_stage(_floor(HOME.x, HOME.z), front, front)


## Wakes him (the roar) with his AI kept off: the tour forces each attack.
func _wake() -> void:
	if _t.dormant:
		_t.wake("struck")
	_t.ai_enabled = false


## A wound's clock moved on to `s` seconds (to show its regrowth within a beat).
func _clock(plate: String, s: float) -> void:
	var ps := _t.plates()
	if ps != null and ps.wounds.has(plate):
		(ps.wounds[plate] as Dictionary).open_ticks = int(s * Sim.TICK_RATE)


func _make_beats() -> Array:
	var wide := {"az": 20.0, "dist": 36.0, "h": 12.0, "look": 12.0, "on": "mid"}
	var side := {"az": -70.0, "dist": 34.0, "h": 10.0, "look": 11.0, "on": "mid"}
	var high := {"az": 35.0, "dist": 38.0, "h": 26.0, "look": 6.0, "on": "mid"}
	var shoulder := {"az": 60.0, "dist": 24.0, "h": 19.0, "look": 17.0, "on": "titan"}
	return [
		["dormant", 3.0, func() -> void:
			_grow(5)
			_go(LOOKOUT)
			_face(_p, HOME),
			{"at": LOOKOUT + Vector3(10, 22, -12), "look": HOME + Vector3(0, 12, 0), "fov": 46.0},
			[[2.5, "grove_from_path_dormant"]]],
		["wake", 4.5, func() -> void:
			_go(_floor(HOME.x + 26, HOME.z - 8))
			_face_off(26.0)
			_wake(),
			wide, [[2.2, "wake_roar", {"az": 15.0, "dist": 34.0, "h": 6.0, "look": 15.0, "on": "titan"}]]],
		["lash", 4.0, func() -> void:
			_face_off(18.0)
			_attack("ability.rootwarden_lash"),
			side, [[_running("ability.rootwarden_lash", ActionDef.Phase.WINDUP, 0.6), "lash_windup"],
				[_running("ability.rootwarden_lash", ActionDef.Phase.ACTIVE, 0.4), "lash_strike"]],
			func(t: float) -> void:
				if t > 1.3 and t < 1.35:
					_dodge(Vector2(0, 1))],
		["erupt", 4.5, func() -> void:
			_face_off(26.0)
			_attack("ability.rootwarden_erupt"),
			high, [[_running("ability.rootwarden_erupt", ActionDef.Phase.WINDUP, 0.7), "erupt_telegraph"],
				[_running("ability.rootwarden_erupt", ActionDef.Phase.ACTIVE, 0.5), "erupt_roots"]],
			func(t: float) -> void:
				if t > 1.0 and t < 1.05:
					_dodge(Vector2(1, 0))],
		["snare", 4.0, func() -> void:
			_face_off(22.0)
			_attack("ability.rootwarden_snare"),
			wide, [[_running("ability.rootwarden_snare", ActionDef.Phase.WINDUP, 0.6), "snare_circle"],
				[_running("ability.rootwarden_snare", ActionDef.Phase.ACTIVE, 0.6), "snare_bind",
					{"az": 40.0, "dist": 22.0, "h": 6.0, "look": 3.0, "on": "player"}]]],
		["hurl", 5.5, func() -> void:
			_face_off(40.0)
			_attack("ability.rootwarden_hurl"),
			side, [[_running("ability.rootwarden_hurl", ActionDef.Phase.WINDUP, 0.35), "hurl_rip_tree"],
				[_running("ability.rootwarden_hurl", ActionDef.Phase.ACTIVE, 0.3), "hurl_throw"],
				[_running("ability.rootwarden_hurl", ActionDef.Phase.RECOVERY, 0.5), "hurl_landing", high]],
			func(t: float) -> void:
				if t > 1.6 and t < 1.65:
					_dodge(Vector2(1, 0))],
		["stomp", 4.0, func() -> void:
			_face_off(5.0)
			_attack("ability.rootwarden_stomp"),
			{"az": 70.0, "dist": 30.0, "h": 9.0, "look": 8.0, "on": "titan"},
			[[_running("ability.rootwarden_stomp", ActionDef.Phase.WINDUP, 0.6), "stomp_raised"],
				[_running("ability.rootwarden_stomp", ActionDef.Phase.ACTIVE, 0.3), "stomp_impact"]]],
		["plate", 9.0, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_face_off(12.0),
			shoulder, [[0.9, "plate_broken_sapwood"], [4.2, "plate_regrowing"], [8.2, "plate_regrown"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shoulder_l", 3000.0)
				if t > 2.5 and t < 2.53:
					_clock("shoulder_l", float((_t.plates().plate("shoulder_l").regrow as Dictionary).after_s) + 1.0)
				if t > 5.0 and t < 5.03:
					_clock("shoulder_l", float((_t.plates().plate("shoulder_l").regrow as Dictionary).after_s)
						+ float((_t.plates().plate("shoulder_l").regrow as Dictionary).over_s) - 0.2)],
		["sear", 5.0, func() -> void:
			_face_off(12.0),
			shoulder, [[0.9, "plate_broken_again"], [3.6, "wound_seared"]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shoulder_l", 3000.0)
				if t > 1.5 and t < 1.53:
					_t.p34_ignite(8.0, _p.entity.entity_id)],
		["knot", 7.0, func() -> void:
			_face_off(12.0),
			{"az": -55.0, "dist": 22.0, "h": 12.0, "look": 9.0, "on": "titan"},
			[[0.8, "knot_broken"], [2.0, "roots_withered"],
				[_running("ability.rootwarden_uproot", ActionDef.Phase.ACTIVE, 0.2), "uprooted_phase_2", wide]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("knot", 3000.0)
				if t > 0.5 and t < 0.53:
					if not _t.plates().is_broken("knot"):
						_t.break_plate("knot")
				if t > 2.2 and t < 2.23 and _t.controller.action_id() != "ability.rootwarden_uproot":
					_attack("ability.rootwarden_uproot")],
		["topple", 6.5, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_face_off(10.0),
			{"az": 75.0, "dist": 32.0, "h": 8.0, "look": 9.0, "on": "titan"},
			[[1.6, "shin_broken_topple"], [4.2, "strike_back", {"az": 40.0, "dist": 26.0, "h": 13.0, "look": 9.0,
				"on": "mid"}]],
			func(t: float) -> void:
				if t > 0.2 and t < 0.23:
					_blow("shin_l", 4000.0)
					if not _t.plates().is_broken("shin_l"):
						_t.break_plate("shin_l")
				if t > 2.6 and t < 2.63:
					_p.global_position = _round_titan(-25.0, 9.0)
					_face(_p, (_t.get_node("Anchors/PlateShoulderL") as Node3D).global_position)
					_swing()
				if t > 3.6 and t < 3.63:
					_blow("shoulder_r", 600.0)],
		["death", 7.0, func() -> void:
			if _t.controller.action != null:
				_t.controller.call("_finish_action", true)
			_face_off(22.0)
			_t.entity.combatant.pools.health = 60.0,
			{"az": 80.0, "dist": 36.0, "h": 10.0, "look": 7.0, "on": "titan"},
			[[1.6, "death_fall"], [6.2, "fallen", high]],
			func(t: float) -> void:
				if t > 0.3 and t < 0.33 and _t.entity.is_alive():
					_blow("torso", 4000.0)],
		["leave", 1.0, func() -> void:
			_go(_floor(-600, 60)),   # (the giant goes on beyond his line: the grove greens behind it)
			{"at": Vector3(-590, 40, 40), "look": Vector3(-600, 20, 60), "fov": 55.0}, []],
		["greened", 5.0, func() -> void:
			_go(LOOKOUT),
			{"at": HOME + Vector3(34, 30, -14), "look": HOME + Vector3(-4, 2, 6), "fov": 58.0},
			[[4.5, "grove_greened"]]],
		["warden_set", 5.0, func() -> void:
			GameSession.expansion.equipment = Armour.equipment_with(Armour.set_pieces("armour_set.warden"))
			Armour.refresh_player(_p)
			_go(_floor(HOME.x + 14, HOME.z + 8))
			_face(_p, _p.global_position + Vector3(10, 0, 0)),
			{"at": HOME + Vector3(32, 9, 8), "look": HOME + Vector3(14, 7.5, 8), "fov": 50.0},
			[[2.0, "warden_set_front"], [4.5, "warden_set_back", {"at": HOME + Vector3(-4, 9, 8),
				"look": HOME + Vector3(14, 7.5, 8), "fov": 50.0}]]],
		["hollowmere", 4.0, func() -> void:
			_go(HOLLOWMERE),
			{"at": HOLLOWMERE + Vector3(26, 22, 10), "look": HOLLOWMERE + Vector3(4, 2, -6), "fov": 56.0},
			[[3.5, "hollowmere_after"]]],
	]
