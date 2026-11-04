extends TestSuite
## HitFactory: every field of a HitEvent is set the same way for every attacker (player and
## soldier), candidates are ordered deterministically, repeats are dropped, and crits are
## rolled with Sim.rng in build order - so the worked examples (light 37, heavy 66, Footfall 44
## against the dummy's armor 25) still come out exactly.

var _nodes: Array[Node] = []


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	Sim.clear_pending()


func _entity(id: String, def_id: String, height := -1.0) -> CombatEntity:
	var e := CombatEntity.new()
	e.entity_id = id
	e.definition_id = def_id
	e.combatant = Combatant.from_record(id, GameData.get_record(def_id), height)
	_nodes.append(e)
	return e


func _ctx(entity: CombatEntity, weapon_id: String, stage: int, pos: Vector3) -> AttackContext:
	var ctx := AttackContext.new()
	ctx.entity = entity
	ctx.instance_id = 7
	ctx.weapon = GameData.get_record(weapon_id).duplicate(true)   # tests may edit their copy
	ctx.growth_stage = stage
	ctx.attacker_position = pos
	ctx.registry = HitRegistry.new()
	return ctx


func _cand(target: CombatEntity, substep := 1, distance := 2.0, weak := false) -> Dictionary:
	return {"entity": target, "hurtbox": null, "point": Vector3(0.5, 1.0, -2.0), "substep": substep,
		"distance": distance, "weak_point": weak}


func _pending() -> Array:
	return (Sim.get("_pending_hits") as Array).duplicate()


func _player() -> CombatEntity:
	var p := _entity("player", "player.giant", 3.6576)
	p.combatant.crit_chance = 0.0   # worked examples are non-crit numbers
	return p


func test_player_hit_carries_every_field() -> void:
	var player := _player()
	var dummy := _entity("dummy_01", "prop.practice_dummy")
	var a := action("ability.light_1")
	var ctx := _ctx(player, "weapon.club", 1, Vector3(1, 0, 2))
	var e := HitFactory.build(ctx, a, _cand(dummy, 3, 2.5, false), 0, 100)
	assert_eq(e.tick, 100, "tick")
	assert_eq(e.instance_id, 7, "instance id from the context")
	assert_eq(e.pulse_id, 0, "pulse id")
	assert_eq(e.attacker_id, "player", "attacker id")
	assert_eq(e.target_id, "dummy_01", "target id")
	assert_eq(e.action_id, "ability.light_1", "action id")
	assert_near(e.power, a.power, 1e-9, "power")
	assert_near(e.ability_multiplier, a.ability_multiplier, 1e-9, "ability multiplier")
	assert_near(e.weapon_multiplier, 1.0, 1e-9, "club multiplier (uses_weapon)")
	assert_near(e.attacker_stat, 10.0, 1e-9, "Strength for a melee attack")
	assert_near(e.attacker_height_m, 3.6576, 1e-9, "attacker height")
	assert_eq(e.size_policy, a.size_policy, "size policy")
	assert_true(e.damage_split == a.damage_split, "damage split")
	assert_near(e.poise_damage, a.poise_damage, 1e-9, "poise damage")
	assert_eq(e.tags, a.tags, "tags")
	assert_false(e.crit, "no crit at 0% crit chance")
	assert_near(e.crit_multiplier, 1.5, 1e-9, "crit multiplier")
	assert_false(e.weak_point, "weak point from the candidate")
	assert_near(e.flat_penetration, a.flat_penetration, 1e-9, "flat penetration")
	assert_near(e.knockback_impulse, a.knockback_impulse, 1e-9, "knockback impulse")
	assert_near(e.knockback_max_speed, a.knockback_max_speed, 1e-9, "knockback max speed")
	assert_true(e.attacker_position.is_equal_approx(Vector3(1, 0, 2)), "attacker position from the context")
	assert_true(e.hit_point.is_equal_approx(Vector3(0.5, 1.0, -2.0)), "hit point from the candidate")
	assert_eq(e.substep, 3, "sub-step from the candidate")
	assert_near(e.distance, 2.5, 1e-9, "distance from the candidate")
	assert_eq(e.category, "melee", "category")
	assert_eq(e.attacker_growth_stage, 1, "growth stage from the context")


func test_soldier_hit_uses_the_same_rules() -> void:
	var soldier := _entity("soldier_01", "enemy.soldier")
	var player := _player()
	var a := action("ability.soldier_slash")
	var ctx := _ctx(soldier, "weapon.soldier_sword", 1, Vector3.ZERO)
	var e := HitFactory.build(ctx, a, _cand(player, 2, 1.0, true), 4, 55)
	assert_eq(e.attacker_id, "soldier_01", "attacker id")
	assert_eq(e.pulse_id, 4, "pulse id passes through (M1 soldiers never set it)")
	assert_true(e.weak_point, "weak point passes through (M1 soldiers dropped it)")
	assert_eq(e.attacker_growth_stage, 1, "growth stage 1 (M1 soldiers left it unset)")
	assert_near(e.weapon_multiplier, 1.0, 1e-9, "sword multiplier")
	assert_near(e.attacker_stat, 10.0, 1e-9, "Strength")
	assert_near(e.attacker_height_m, 1.8, 1e-9, "a soldier's height")
	assert_false(e.crit, "soldier slashes are not crit eligible")
	# The same action built for the player differs only by what the attacker brings.
	var p := HitFactory.build(_ctx(player, "weapon.club", 1, Vector3.ZERO), a, _cand(soldier, 2, 1.0, true), 4, 55)
	for field in ["tick", "instance_id", "pulse_id", "action_id", "power", "ability_multiplier",
			"size_policy", "poise_damage", "tags", "weak_point", "flat_penetration", "knockback_impulse",
			"knockback_max_speed", "substep", "distance", "category", "attacker_growth_stage"]:
		assert_eq(p.get(field), e.get(field), "field %s is built the same way for both attackers" % field)


func test_magic_uses_intellect_and_weaponless_actions_ignore_the_weapon() -> void:
	var player := _player()
	player.combatant.attributes["intellect"] = 17.0
	var dummy := _entity("dummy_01", "prop.practice_dummy")
	var d: Dictionary = GameData.get_record("ability.light_1").duplicate(true)
	d["id"] = "test.bolt"
	d["category"] = "magic"
	d["uses_weapon"] = false
	var bolt := ActionDef.from_dict(d)
	var ctx := _ctx(player, "weapon.club", 2, Vector3.ZERO)
	ctx.weapon = {"damage_multiplier": 1.4}
	var e := HitFactory.build(ctx, bolt, _cand(dummy), 0, 1)
	assert_near(e.attacker_stat, 17.0, 1e-9, "magic uses Intellect")
	assert_near(e.weapon_multiplier, 1.0, 1e-9, "uses_weapon false ignores the weapon")
	assert_eq(e.attacker_growth_stage, 2, "stage comes from the context")
	var swing := HitFactory.build(ctx, action("ability.light_1"), _cand(dummy), 0, 1)
	assert_near(swing.attacker_stat, 10.0, 1e-9, "a melee swing uses Strength")
	assert_near(swing.weapon_multiplier, 1.4, 1e-9, "a weapon swing uses the weapon multiplier")


func test_candidates_sort_by_substep_distance_then_id() -> void:
	var a := _entity("b_target", "prop.practice_dummy")
	var b := _entity("a_target", "prop.practice_dummy")
	var c := _entity("c_target", "prop.practice_dummy")
	var cands := [_cand(c, 2, 1.0), _cand(a, 1, 3.0), _cand(b, 1, 3.0), _cand(c, 1, 0.5)]
	HitFactory.sort_candidates(cands)
	var order: Array[String] = []
	for cand: Dictionary in cands:
		order.append("%s@%d" % [(cand.entity as CombatEntity).entity_id, cand.substep])
	assert_eq(order, ["c_target@1", "a_target@1", "b_target@1", "c_target@2"] as Array[String],
		"sub-step, then distance, then entity id")


func test_queue_dedups_skips_nothing_and_rolls_crits_in_build_order() -> void:
	var player := _entity("player", "player.giant", 3.6576)
	player.combatant.crit_chance = 0.5
	var targets: Array[CombatEntity] = []
	var cands: Array = []
	for i in 24:
		var t := _entity("t_%02d" % i, "prop.practice_dummy")
		targets.append(t)
		assert_false(HitFactory.skip_candidate(player, t, true), "P02 never skips a candidate")
	for i in range(23, -1, -1):   # reverse order: queue() must sort them first
		cands.append(_cand(targets[i], 1, float(i)))
	cands.append(_cand(targets[0], 1, 0.0))   # a repeat of t_00: dropped by the registry
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = Sim.DEFAULT_SEED
	Sim.reseed(Sim.DEFAULT_SEED)
	Sim.clear_pending()
	var ctx := _ctx(player, "weapon.club", 1, Vector3.ZERO)
	var n := HitFactory.queue(ctx, action("ability.light_1"), cands, 0, 10)
	assert_eq(n, 24, "24 distinct targets queued, the repeat dropped")
	var pending := _pending()
	assert_eq(pending.size(), 24, "Sim holds the 24 hits")
	var crits := 0
	for i in pending.size():
		var e: HitEvent = pending[i]
		assert_eq(e.target_id, "t_%02d" % i, "queued in sorted order (%d)" % i)
		var roll := expected_rng.randf() < 0.5
		assert_eq(e.crit, roll, "crit %d follows the Sim.rng sequence in build order" % i)
		crits += 1 if e.crit else 0
	assert_true(crits > 0 and crits < 24, "the sequence really mixes crits and normal hits (%d)" % crits)
	assert_eq(HitFactory.queue(ctx, action("ability.light_1"), [_cand(targets[3])], 0, 11), 0,
		"the same instance never hits a target twice")


func test_worked_examples_through_the_factory() -> void:
	var player := _player()
	var dummy := _entity("dummy_01", "prop.practice_dummy")
	var defense := DefenseState.new()
	defense.height_m = dummy.combatant.height_m
	var expected := {"ability.light_1": 37, "ability.heavy_1": 66, "ability.heavy_footfall": 44}
	for id: String in expected:
		var e := HitFactory.build(_ctx(player, "weapon.club", 1, Vector3(0, 0, 3)), action(id), _cand(dummy), 0, 1)
		var r := DamageResolver.resolve(e, dummy.combatant, defense)
		assert_eq(r.health_damage, int(expected[id]), "%s vs armor 25 = %d" % [id, expected[id]])


func test_context_snapshot_is_independent() -> void:
	var player := _player()
	var ctx := _ctx(player, "weapon.club", 2, Vector3(4, 0, 0))
	ctx.area_effect = true
	var snap := ctx.snapshot()
	ctx.instance_id = 99
	ctx.weapon["damage_multiplier"] = 9.0
	ctx.attacker_position = Vector3.ZERO
	assert_eq(snap.instance_id, 7, "instance id kept")
	assert_eq(snap.growth_stage, 2, "stage kept")
	assert_true(snap.area_effect, "area effect kept")
	assert_true(snap.attacker_position.is_equal_approx(Vector3(4, 0, 0)), "position kept")
	assert_near(float(snap.weapon.get("damage_multiplier", 0.0)), 1.0, 1e-9, "weapon copied, not shared")
	assert_true(snap.entity == player and snap.registry == ctx.registry, "entity and registry are shared")
