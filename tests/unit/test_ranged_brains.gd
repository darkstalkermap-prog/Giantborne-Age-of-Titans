extends TestSuite
## P09 pure checks: the archer and mage records (plan §4.4) and their actions, the targets_ally
## schema rules, the untelegraphed-enemy-attack error (decision 25), and ArcherBrain / MageBrain
## driven with hand-made perception snapshots: the band (x1.3 and a 10 m spread while
## outmatched), ring points, retreat, the kick under 2.5 m, shot gating (sight, band, settled,
## facing, ranged token, launch slot), the ranged token held until the shot's recovery is over,
## the mage's barrier target and kiting, and states other packages own left to the base rules.

const TMP_DATA := "user://test_tmp_ranged_brains"
const LOCO := CombatController.State.LOCOMOTION
const ATTACKING := CombatController.State.ATTACKING

var _loaded_tmp := false


func after_each() -> void:
	_rm_tree(TMP_DATA)
	if _loaded_tmp:
		_loaded_tmp = false
		GameData.load_all(GameData.DATA_ROOT)


# --------------------------------------------------------------------------- helpers

func _archer(id := "test.archer") -> ArcherBrain:
	return ArcherBrain.new(id, GameData.get_record("enemy.archer"), 7)


func _mage(id := "test.mage") -> MageBrain:
	return MageBrain.new(id, GameData.get_record("enemy.mage"), 7)


## A snapshot of a target at `target_pos` seen from `my_pos` (flat distance), facing the unit.
static func _snap(my_pos: Vector3, target_pos: Vector3, visible := true, height := 3.6576,
		facing_deg := 0.0, radius := 0.85) -> Dictionary:
	return {"exists": true, "target_id": "player", "alive": true, "position": target_pos,
		"distance": Vector2(my_pos.x - target_pos.x, my_pos.z - target_pos.z).length(), "visible": visible,
		"facing_deg": facing_deg, "target_radius": radius, "target_forward": Vector3.FORWARD,
		"target_height": height, "target_stage": 1, "target_state": 0, "self_health_frac": 1.0,
		"has_leader": true}


## Puts `b` into the engaged APPROACH state at `tick`, aware of its target.
static func _engage(b: EnemyBrain, tick: int, snap: Dictionary) -> void:
	b.perceive(tick, snap)
	b.state = EnemyBrain.AIState.APPROACH
	b.state_tick = tick
	b.aware = true


## Helpers that count calls: {"req": n, "rel": n, "slot": n, "ranged": n, "ranged_rel": n}.
static func _wire(b: EnemyBrain, counts: Dictionary, token_ok := true, ranged_ok := true, slot_ok := true) -> Array:
	for k: String in ["req", "rel", "slot", "ranged", "ranged_rel"]:
		counts[k] = 0
	b.ranged_token_request = func() -> bool:
		counts.ranged += 1
		return ranged_ok
	b.ranged_token_release = func() -> void: counts.ranged_rel += 1
	b.launch_slot_request = func(_id: String) -> bool:
		counts.slot += 1
		return slot_ok
	var req := func() -> bool:
		counts.req += 1
		return token_ok
	var rel := func() -> void: counts.rel += 1
	return [req, rel]


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# --------------------------------------------------------------------------- data (plan §4.4)

func test_archer_record() -> void:
	var r: Dictionary = GameData.get_record("enemy.archer")
	assert_eq(str(r.archetype), "archer", "archetype")
	assert_eq(str(r.scene), "res://scenes/enemies/archer.tscn", "its scene")
	assert_eq([r.height_m, r.capsule_radius_m], [1.8, 0.35], "1.8 m, radius 0.35")
	assert_eq([r.health, r.armor, r.poise.threshold], [140.0, 5.0, 30.0], "140 / 5 / poise 30")
	assert_eq([r.walk_speed_mps, r.run_speed_mps, r.turn_rate_deg_s], [1.8, 3.8, 300.0], "1.8 / 3.8 m/s, 300 deg/s")
	assert_eq(float(r.ai.sight_range_m), 32.0, "sight 32 m (a role override: sees the top of its outmatched band)")
	assert_eq([r.morale, r.ai.flee_morale, r.ai.regroup_morale], [60.0, 25.0, 45.0], "morale 60 / 25 / 45")
	var t: Dictionary = r.tactics
	assert_eq([t.preferred_min_m, t.preferred_max_m, t.spread_m, t.launch_gap_s], [12.0, 20.0, 6.0, 1.0],
		"band 12-20 m, spread 6 m, launch gap 1.0 s")
	assert_eq(str(t.outmatched_behavior), "spread", "outmatched -> spread")
	assert_true(float(t.outmatched_ratio) > 0.0 and 5.4864 / 1.8 >= float(t.outmatched_ratio)
		and 3.6576 / 1.8 < float(t.outmatched_ratio), "outmatched by a stage-2 giant, not by stage 1")
	assert_near(float(r.threat), 0.7, 1e-6, "threat 0.7")
	assert_true(bool(r.grants_fury), "grants fury")
	assert_eq(str(r.grab_attach), "torso_fist", "grabbed by the torso")
	assert_eq(int(r.nav_layers), 1, "human nav layer")
	var shot := GameData.get_action("ability.archer_shot")
	assert_eq([shot.power, shot.windup_ticks, shot.active_ticks, shot.recovery_ticks], [22.0, 54, 3, 36],
		"shot 22 (0.90 / 0.05 / 0.60 s)")
	assert_eq(shot.hit_shape, "projectile", "a projectile")
	assert_near(shot.tracking_fraction, 0.6, 1e-6, "aim lock at 60 %")
	var spec := Projectile.spec_for(shot)
	assert_eq([spec.speed_mps, spec.gravity_mps2, spec.range_m], [32.0, 4.0, 30.0], "32 m/s, gravity 4, range 30")
	assert_eq([str(spec.aim), str(spec.visual)], ["target", "arrow"], "aimed at the target, an arrow")
	assert_true(bool(spec.arc_to_target), "the arc passes through the stored aim point")
	assert_eq(str((shot.param("telegraph") as Dictionary).shape), "line", "the draw shows a line (the aim line)")
	assert_false(shot.has_tag("Melee"), "an arrow is not parryable (no Melee tag)")
	var kick := GameData.get_action("ability.archer_kick")
	assert_eq([kick.power, kick.windup_ticks, kick.active_ticks, kick.recovery_ticks], [15.0, 27, 6, 30],
		"kick 15 (0.45 / 0.10 / 0.50 s)")
	assert_near(0.85 + float(kick.param("ai_max_range_m")), 2.35, 0.2,
		"the kick's band reaches about 2.5 m from a stage-1 giant's centre")


func test_mage_record() -> void:
	var r: Dictionary = GameData.get_record("enemy.mage")
	assert_eq(str(r.archetype), "mage", "archetype")
	assert_eq([r.health, r.armor, r.poise.threshold], [160.0, 0.0, 25.0], "160 / 0 / poise 25")
	assert_near(float(r.resistances.arcane), 0.3, 1e-6, "arcane resistance 0.3")
	assert_eq([r.essence, r.regen.essence_per_s], [100.0, 6.0], "essence 100 (+6/s) from data")
	assert_eq([r.walk_speed_mps, r.run_speed_mps], [1.6, 3.4], "1.6 / 3.4 m/s")
	assert_eq([r.tactics.preferred_min_m, r.tactics.preferred_max_m], [10.0, 16.0], "band 10-16 m")
	assert_eq(str(r.tactics.outmatched_behavior), "kite", "outmatched -> kite")
	assert_near(float(r.threat), 0.8, 1e-6, "threat 0.8")
	assert_eq(str(r.grab_attach), "torso_fist", "grabbed by the torso")
	var bolt := GameData.get_action("ability.mage_slow_bolt")
	assert_eq([bolt.power, bolt.windup_ticks, bolt.active_ticks, bolt.recovery_ticks], [20.0, 60, 3, 36],
		"slow bolt 20 (1.0 / 0.05 / 0.6 s)")
	assert_eq([bolt.kind, bolt.damage_type, bolt.category], ["ability", "arcane", "magic"],
		"an arcane cast (CASTING, Intellect)")
	assert_eq(float(Projectile.spec_for(bolt).speed_mps), 20.0, "20 m/s")
	assert_near(bolt.tracking_fraction, 0.6, 1e-6, "aim lock at 60 %")
	var slow: Array = bolt.param("on_hit_statuses")
	assert_eq([str(slow[0].status), float(slow[0].magnitude), float(slow[0].duration_s)], ["status.slow", 0.3, 3.0],
		"a 30 % slow for 3 s")
	var barrier := GameData.get_action("ability.mage_barrier")
	assert_eq([barrier.windup_ticks, barrier.essence_cost, barrier.cooldown_s], [72, 30.0, 10.0],
		"barrier: 1.2 s, 30 essence, 10 s cooldown")
	assert_true(bool(barrier.param("targets_ally")), "a cast on an ally")
	assert_eq(str((barrier.param("telegraph") as Dictionary).shape), "circle", "circle telegraph")
	var ward := GameData.get_status("status.barrier")
	assert_near(ward.modifiers.get("damage_taken_mult", 1.0), 0.5, 1e-6, "x0.5 damage taken")
	assert_eq(ward.duration_ticks, 300, "for 5 s")
	var staff := GameData.get_action("ability.mage_staff")
	assert_eq([staff.power, staff.windup_ticks, staff.active_ticks, staff.recovery_ticks], [12.0, 30, 6, 30],
		"staff 12 (0.5 / 0.1 / 0.5 s)")
	for id: String in ["ability.mage_slow_bolt", "ability.mage_barrier", "ability.mage_staff"]:
		assert_eq(GameData.get_action(id).interrupt_policy, "hard_stagger", "%s can be interrupted" % id)


## Decision 25: every action an enemy uses with a windup of 0.8 s or more has a telegraph.
func test_shipped_enemy_attacks_are_telegraphed() -> void:
	assert_eq(GameData.call("_untelegraphed_enemy_attacks"), PackedStringArray(),
		"no shipped enemy attack of 0.8 s or more lacks a telegraph")
	for id: String in ["ability.archer_shot", "ability.mage_slow_bolt", "ability.mage_barrier"]:
		assert_true(GameData.get_action(id).windup_ticks >= 48 and GameData.get_action(id).param("telegraph") != null,
			"%s: a windup of 0.8 s or more, telegraphed" % id)


## From P09 on the finding is an error, not a warning (P01 left the switch at the P09 anchor).
func test_an_untelegraphed_enemy_attack_is_a_data_error() -> void:
	var chop: Dictionary = (GameData.get_record("ability.soldier_chop") as Dictionary).duplicate(true)
	chop.erase("telegraph")
	chop["id"] = "ability.test_untelegraphed"
	_write("a.json", chop)
	_write("b.json", GameData.get_record("weapon.soldier_sword"))
	_loaded_tmp = true
	GameData.load_all(TMP_DATA, false)
	var errors := "\n".join(GameData.errors)
	assert_true(errors.contains("(ability.test_untelegraphed): enemy attack (kind enemy_attack) with windup_s 0.85"),
		"reported as an error")
	assert_false("\n".join(GameData.warnings).contains("ability.test_untelegraphed"), "and not as a warning")
	assert_false(GameData.is_valid(), "the game refuses to start on it")


func test_targets_ally_schema() -> void:
	var barrier: Dictionary = (GameData.get_record("ability.mage_barrier") as Dictionary).duplicate(true)
	assert_eq(DataValidator.validate_record(barrier, "barrier.json").errors.size(), 0, "the shipped barrier validates")
	var shot := barrier.duplicate(true)
	shot["hit_shape"] = "projectile"
	shot["projectile"] = {"speed_mps": 10, "radius_m": 0.2, "range_m": 10}
	assert_true("\n".join(DataValidator.validate_record(shot, "a.json").errors).contains("hit_shape must be 'none'"),
		"a targets_ally cast has no hit")
	var empty := barrier.duplicate(true)
	empty.erase("on_hit_statuses")
	assert_true("\n".join(DataValidator.validate_record(empty, "b.json").errors).contains("needs on_hit_statuses"),
		"and needs statuses to land")
	var bad := barrier.duplicate(true)
	bad["targets_ally"] = "yes"
	assert_true(DataValidator.validate_record(bad, "c.json").errors.size() > 0, "targets_ally is a bool")


# --------------------------------------------------------------------------- archer brain

func test_attack_classes_and_bands() -> void:
	var a := _archer()
	assert_eq(a.ranged_attacks(), ["ability.archer_shot"] as Array[String], "the shot is the ranged attack")
	assert_eq(a.close_attacks(), ["ability.archer_kick"] as Array[String], "the kick answers up close")
	assert_eq(a.ally_casts().size(), 0, "no ally casts")
	assert_eq(a.ranged_band(false), Vector2(12.0, 20.0), "band 12-20 m")
	var out := a.ranged_band(true)
	assert_near(out.x, 15.6, 1e-4, "outmatched band from 15.6 m")
	assert_near(out.y, 26.0, 1e-4, "to 26 m")
	assert_near(a.ranged_spread_m(false), 6.0, 1e-6, "spread 6 m")
	assert_near(a.ranged_spread_m(true), 10.0, 1e-6, "10 m when outmatched")
	var m := _mage()
	assert_eq(m.ranged_attacks(), ["ability.mage_slow_bolt"] as Array[String], "the slow bolt is the mage's shot")
	assert_eq(m.close_attacks(), ["ability.mage_staff"] as Array[String], "the staff answers up close")
	assert_eq(m.ally_casts(), ["ability.mage_barrier"] as Array[String], "the barrier is its ally cast")
	assert_eq(m.ranged_band(false), Vector2(10.0, 16.0), "band 10-16 m")


func test_archer_takes_a_ring_point_in_the_band_then_shoots_when_settled() -> void:
	var b := _archer()
	var counts := {}
	var tok := _wire(b, counts)
	var target := Vector3.ZERO
	var far := Vector3(0, 0, -30)
	_engage(b, 100, _snap(far, target))
	b.decide(100, LOCO, far, tok[0], tok[1])
	assert_true(b.firing_point != Vector3.INF, "a firing point")
	assert_near(_flat(b.firing_point, target), 19.0, 1e-3, "on the ring, 1 m inside the band's far edge")
	assert_eq(b.move_target, b.firing_point, "it goes there")
	assert_eq(b.move_speed, -1.0, "running (far from it)")
	assert_eq(b.attack_request, "", "no shot while it is not settled")
	assert_eq(counts.ranged, 0, "and no ranged token asked for")
	var at := b.firing_point
	b.perceive(106, _snap(at, target))
	b.decide(106, LOCO, at, tok[0], tok[1])
	assert_eq(b.attack_request, "ability.archer_shot", "settled in the band with sight: it shoots")
	assert_eq(b.state, EnemyBrain.AIState.ATTACK, "ATTACK")
	assert_eq([counts.ranged, counts.slot], [1, 1], "after a ranged token and a launch slot")
	assert_true(b.holds_ranged_token, "it holds the ranged token")
	assert_eq(counts.req, 0, "a shot takes no melee token")


func test_shots_need_sight_band_facing_token_and_slot() -> void:
	var target := Vector3.ZERO
	var at := Vector3(0, 0, -16)
	var cases := [
		["no sight", {"visible": false}, true, true],
		["beyond the band", {"distance": 21.5}, true, true],
		["inside the band", {"distance": 10.5}, true, true],
		["facing away", {"facing_deg": 80.0}, true, true],
		["no ranged token", {}, false, true],
		["no launch slot", {}, true, false],
	]
	for c: Array in cases:
		var b := _archer()
		var counts := {}
		var tok := _wire(b, counts, true, c[2], c[3])
		var snap := _snap(at, target)
		snap.merge(c[1], true)
		_engage(b, 200, snap)
		b.last_seen_tick = 200
		b.firing_point = at   # settled at its point
		b.decide(200, LOCO, at, tok[0], tok[1])
		assert_eq(b.attack_request, "", "%s: no shot" % c[0])
		assert_false(b.holds_ranged_token, "%s: no ranged token kept" % c[0])
		if c[0] == "no launch slot":
			assert_eq([counts.ranged, counts.slot, counts.ranged_rel], [1, 1, 1],
				"a refused slot gives the token straight back")
		if c[0] == "no ranged token":
			assert_eq(counts.slot, 0, "no slot is asked for without a token (none is wasted)")


func test_the_ranged_token_is_held_until_the_shot_recovery_is_over() -> void:
	var b := _archer()
	var counts := {}
	var tok := _wire(b, counts)
	var at := Vector3(0, 0, -16)
	_engage(b, 300, _snap(at, Vector3.ZERO))
	b.firing_point = at
	b.decide(300, LOCO, at, tok[0], tok[1])
	assert_eq(b.attack_request, "ability.archer_shot", "the shot")
	for t in [306, 336, 360, 390]:
		b.decide(t, ATTACKING, at, tok[0], tok[1])
		assert_true(b.holds_ranged_token, "held through the draw, release and recovery (tick %d)" % t)
		assert_eq(counts.ranged_rel, 0, "not released yet (tick %d)" % t)
	b.decide(396, LOCO, at, tok[0], tok[1])
	assert_eq(b.state, EnemyBrain.AIState.RECOVER, "the recovery is over: a pause")
	assert_false(b.holds_ranged_token, "the ranged token went back")
	assert_eq(counts.ranged_rel, 1, "released once")
	b.decide(402, CombatController.State.STAGGERED, at, tok[0], tok[1])
	assert_eq(counts.ranged_rel, 1, "nothing more to release")


func test_a_stagger_mid_draw_releases_the_ranged_token() -> void:
	var b := _archer()
	var counts := {}
	var tok := _wire(b, counts)
	var at := Vector3(0, 0, -16)
	_engage(b, 300, _snap(at, Vector3.ZERO))
	b.firing_point = at
	b.decide(300, LOCO, at, tok[0], tok[1])
	b.decide(306, CombatController.State.STAGGERED, at, tok[0], tok[1])
	assert_eq(b.state, EnemyBrain.AIState.STAGGERED, "staggered")
	assert_false(b.holds_ranged_token, "an interrupted shot gives the token back")
	assert_eq(counts.ranged_rel, 1, "released")


func test_archer_retreats_inside_its_band_and_kicks_under_2_5_m() -> void:
	var target := Vector3.ZERO
	var b := _archer()
	var counts := {}
	var tok := _wire(b, counts)
	var near := Vector3(0, 0, -6)
	_engage(b, 400, _snap(near, target))
	b.decide(400, LOCO, near, tok[0], tok[1])
	assert_near(_flat(b.firing_point, target), 13.0, 1e-3, "the target is closer than 12 m: back to the band")
	assert_true(b.firing_point.z < near.z, "away from it")
	assert_eq(b.move_speed, -1.0, "running")
	assert_eq(b.attack_request, "", "no shot from inside the band")
	var close := Vector3(0, 0, -2.3)   # 2.3 m from a stage-1 giant's centre
	b.perceive(406, _snap(close, target))
	b.decide(406, LOCO, close, tok[0], tok[1])
	assert_eq(b.attack_request, "ability.archer_kick", "under 2.5 m it kicks")
	assert_eq(counts.req, 1, "holding one of the two melee tokens")
	var b2 := _archer("test.archer_2")
	var tok2 := _wire(b2, {}, false)
	_engage(b2, 400, _snap(close, target))
	b2.decide(400, LOCO, close, tok2[0], tok2[1])
	assert_eq(b2.attack_request, "", "without a melee token: no kick")
	assert_eq(b2.move_speed, -1.0, "it retreats instead")
	var b3 := _archer("test.archer_3")
	var tok3 := _wire(b3, {})
	var outside := Vector3(0, 0, -2.7)
	_engage(b3, 400, _snap(outside, target))
	b3.decide(400, LOCO, outside, tok3[0], tok3[1])
	assert_eq(b3.attack_request, "", "2.7 m away is beyond the kick")


func test_outmatched_archer_spreads_with_the_wider_band() -> void:
	var b := _archer()
	var tok := _wire(b, {})
	var at := Vector3(0, 0, -14)
	_engage(b, 500, _snap(at, Vector3.ZERO, true, 5.4864))
	assert_true(b.is_outmatched(), "a stage-2 giant outmatches it")
	assert_eq(b.outmatched_behavior(), "spread", "spread")
	b.decide(500, LOCO, at, tok[0], tok[1])
	assert_near(_flat(b.firing_point, Vector3.ZERO), 16.6, 1e-3, "14 m is inside 15.6-26 m: back to 16.6 m")
	var resolved: Array = []
	var b2 := _archer("test.archer_2")
	var tok2 := _wire(b2, {})
	b2.firing_point_resolver = func(p: Vector3, t: Vector3, band: Vector2, spread: float, far: bool) -> Vector3:
		resolved.append([band, spread, far])
		return Vector3(0, 0, -20)
	_engage(b2, 500, _snap(at, Vector3.ZERO, true, 5.4864))
	b2.decide(500, LOCO, at, tok2[0], tok2[1])
	assert_eq(resolved.size(), 1, "the actor's resolver picks the point")
	if resolved.size() == 1:
		assert_near((resolved[0][0] as Vector2).y, 26.0, 1e-4, "with the outmatched band")
		assert_near(float(resolved[0][1]), 10.0, 1e-6, "and a 10 m spread")
		assert_false(bool(resolved[0][2]), "archers do not kite")
	assert_eq(b2.firing_point, Vector3(0, 0, -20), "and it holds that point")


func test_a_path_failure_picks_another_firing_point() -> void:
	var b := _archer()
	var tok := _wire(b, {})
	var picks: Array = []
	b.firing_point_resolver = func(p: Vector3, _t: Vector3, _band: Vector2, _s: float, _f: bool) -> Vector3:
		picks.append(p)
		return Vector3(0, 0, -15 - picks.size())
	var at := Vector3(0, 0, -30)
	_engage(b, 600, _snap(at, Vector3.ZERO))
	b.decide(600, LOCO, at, tok[0], tok[1])
	b.decide(606, LOCO, at, tok[0], tok[1])
	assert_eq(picks.size(), 1, "the point is kept while it stays valid")
	b.on_path_failed(at)
	assert_eq(b.state, EnemyBrain.AIState.APPROACH, "still positioning (no REPOSITION detour)")
	b.decide(612, LOCO, at, tok[0], tok[1])
	assert_eq(picks.size(), 2, "a path failure asks for another point")
	assert_eq(b.firing_point, Vector3(0, 0, -17), "the new one")


func test_states_other_packages_own_are_left_to_the_base_rules() -> void:
	for s: int in [EnemyBrain.AIState.RETURN, EnemyBrain.AIState.STAND_DOWN]:
		var b := _archer()
		var tok := _wire(b, {})
		var at := Vector3(0, 0, -16)
		_engage(b, 700, _snap(at, Vector3.ZERO))
		b.state = s
		b.decide(700, LOCO, at, tok[0], tok[1])
		assert_eq(b.state, s, "%s: unchanged by the ranged rules" % b.state_name())
		assert_eq(b.attack_request, "", "%s: no shot" % b.state_name())
		assert_eq(b.firing_point, Vector3.INF, "%s: no firing point" % b.state_name())


# --------------------------------------------------------------------------- mage brain

func test_barrier_goes_to_the_most_hurt_ally_in_range_or_the_mage() -> void:
	var m := _mage()
	var snap := _snap(Vector3(0, 0, -14), Vector3.ZERO)
	m.perceive(10, snap)
	assert_eq(m.barrier_target(), "test.mage", "nobody hurt: itself")
	snap["allies"] = [{"id": "a", "health_frac": 0.6, "distance": 5.0}, {"id": "b", "health_frac": 0.3, "distance": 13.0},
		{"id": "c", "health_frac": 0.8, "distance": 2.0}]
	m.perceive(12, snap)
	assert_eq(m.barrier_target(), "a", "the most hurt ally within 12 m (b is 13 m away)")
	snap["self_health_frac"] = 0.5
	m.perceive(14, snap)
	assert_eq(m.barrier_target(), "test.mage", "itself when it is more hurt than any ally")


func test_mage_casts_its_barrier_when_ready_otherwise_the_slow_bolt() -> void:
	var m := _mage()
	var counts := {}
	var tok := _wire(m, counts)
	var ready := {"ability.mage_barrier": true, "ability.mage_slow_bolt": true, "ability.mage_staff": true}
	m.action_ready = func(id: String) -> bool: return bool(ready.get(id, false))
	var at := Vector3(0, 0, -13)
	var snap := _snap(at, Vector3.ZERO)
	snap["allies"] = [{"id": "test.soldier", "health_frac": 0.4, "distance": 6.0}]
	_engage(m, 800, snap)
	m.firing_point = at
	m.decide(800, LOCO, at, tok[0], tok[1])
	assert_eq(m.attack_request, "ability.mage_barrier", "the barrier first while it is ready")
	assert_eq(m.ally_target_id, "test.soldier", "for the hurt soldier")
	assert_eq([counts.ranged, counts.slot], [0, 0], "a barrier takes no ranged token or launch slot")
	var m2 := _mage("test.mage_2")
	var counts2 := {}
	var tok2 := _wire(m2, counts2)
	ready["ability.mage_barrier"] = false
	m2.action_ready = func(id: String) -> bool: return bool(ready.get(id, false))
	_engage(m2, 800, snap)
	m2.firing_point = at
	m2.decide(800, LOCO, at, tok2[0], tok2[1])
	assert_eq(m2.attack_request, "ability.mage_slow_bolt", "on cooldown: the slow bolt")
	assert_eq([counts2.ranged, counts2.slot], [1, 1], "with a ranged token and a launch slot")
	var m3 := _mage("test.mage_3")
	var tok3 := _wire(m3, {})
	ready["ability.mage_slow_bolt"] = false
	m3.action_ready = func(id: String) -> bool: return bool(ready.get(id, false))
	_engage(m3, 800, snap)
	m3.firing_point = at
	m3.decide(800, LOCO, at, tok3[0], tok3[1])
	assert_eq(m3.attack_request, "", "without essence for the bolt: nothing")
	var m4 := _mage("test.mage_4")
	var tok4 := _wire(m4, {})
	m4.action_ready = func(id: String) -> bool: return bool(ready.get(id, false))
	var close := Vector3(0, 0, -1.9)
	_engage(m4, 800, _snap(close, Vector3.ZERO))
	m4.decide(800, LOCO, close, tok4[0], tok4[1])
	assert_eq(m4.attack_request, "ability.mage_staff", "up close: the staff strike")


func test_outmatched_mage_kites_at_the_far_edge() -> void:
	var m := _mage()
	var tok := _wire(m, {})
	m.action_ready = func(_id: String) -> bool: return false
	var at := Vector3(0, 0, -15)
	_engage(m, 900, _snap(at, Vector3.ZERO, true, 5.4864))
	assert_eq(m.outmatched_behavior(), "kite", "a stage-2 giant: kite")
	m.decide(900, LOCO, at, tok[0], tok[1])
	assert_near(_flat(m.firing_point, Vector3.ZERO), 19.8, 1e-3, "the far edge of the x1.3 band (20.8 - 1)")
	m.firing_point = Vector3(0, 0, -19.8)
	var at2 := Vector3(0, 0, -19.8)
	var closer := Vector3(0, 0, -6)   # the giant closed in: the held point is now in the band's near half
	m.perceive(906, _snap(at2, closer, true, 5.4864))
	m.decide(906, LOCO, at2, tok[0], tok[1])
	assert_near(_flat(m.firing_point, closer), 19.8, 1e-3, "it falls back to the far edge again")
	assert_true(m.firing_point.z < -19.8, "farther away")


# --------------------------------------------------------------------------- files

func _write(file_name: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(TMP_DATA)
	var f := FileAccess.open(TMP_DATA.path_join(file_name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


func _rm_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)
	for d in dir.get_directories():
		_rm_tree(path.path_join(d))
	DirAccess.remove_absolute(path)
