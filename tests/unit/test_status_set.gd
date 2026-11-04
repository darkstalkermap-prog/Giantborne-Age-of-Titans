extends TestSuite
## P01: StatusSet stacking policies, heal-over-time timing, immunity, expiry, the HUD list, and
## statuses in combat (Stone Skin armor, Titan Surge damage/poise/fury, damage_taken_mult).

const T0 := 1000


func _def(d: Dictionary) -> StatusDef:
	var base := {"schema_version": 1, "type": "status_effect", "stacking": "refresh_no_stack", "duration_s": 3.0}
	base.merge(d, true)
	return StatusDef.from_dict(base)


func _stone_skin() -> StatusDef:
	return _def({"id": "status.stone_skin", "hud_label": "SKIN", "duration_s": 6.0,
		"modifiers": {"armor_flat": 30}, "tags": ["Buff"]})


func _slow() -> StatusDef:
	return _def({"id": "status.slow", "hud_label": "SLOW", "stacking": "strongest_wins", "duration_s": 3.0,
		"magnitude_key": "slow_fraction", "default_magnitude": 0.3, "modifiers": {"slow_fraction": 0.3},
		"tags": ["Debuff", "Slow"]})


func _mend() -> StatusDef:
	return _def({"id": "status.mend", "hud_label": "MEND", "duration_s": 4.0, "tick_s": 0.5,
		"modifiers": {"heal_per_tick": 12.5}, "tags": ["Buff", "Heal"]})


func _surge() -> StatusDef:
	return _def({"id": "status.titan_surge", "hud_label": "SURGE", "duration_s": 6.0,
		"modifiers": {"outgoing_damage_mult": 1.25, "outgoing_poise_mult": 1.25, "fury_gain_mult": 0.0},
		"tags": ["Buff", "Ultimate"]})


func _hidden_assist() -> StatusDef:
	return _def({"id": "status.bot_assist", "duration_s": 600.0, "modifiers": {"damage_taken_mult": 0.25},
		"tags": ["Buff"], "hidden": true})


func _none() -> PackedStringArray:
	return PackedStringArray()


# --------------------------------------------------------------------------- StatusSet

func test_status_def_reads_record() -> void:
	var s := _mend()
	assert_eq([s.duration_ticks, s.tick_ticks], [240, 30], "4 s and 0.5 s in ticks")
	assert_eq(s.hud_label, "MEND", "hud label")
	assert_true(s.has_tag("Heal") and not s.is_debuff(), "tags")
	var slow := _slow()
	assert_near(slow.default_magnitude, 0.3, 1e-9, "default magnitude")
	var implicit := _def({"id": "status.x", "magnitude_key": "armor_flat", "modifiers": {"armor_flat": 7}})
	assert_near(implicit.default_magnitude, 7.0, 1e-9, "default magnitude falls back to the modifier value")


func test_refresh_does_not_stack_stone_skin() -> void:
	var c := Combatant.from_record("def", {"id": "test.def", "health": 500, "armor": 25})
	var set := c.statuses
	assert_true(set.apply(_stone_skin(), NAN, -1.0, "player", T0, _none()), "applied")
	assert_true(set.apply(_stone_skin(), NAN, -1.0, "player", T0 + 60, _none()), "re-applied")
	assert_eq(set.count(), 1, "one instance: refresh, no stack")
	assert_near(set.modifier_sum("armor_flat"), 30.0, 1e-9, "+30 armor, not +60")
	assert_near(c.armor_total(), 55.0, 1e-9, "armor_total = 25 + 30")
	assert_near(set.remaining_s("status.stone_skin", T0 + 60), 6.0, 1e-9, "duration refreshed from the re-cast")
	var other := _def({"id": "status.stone_skin", "duration_s": 6.0, "modifiers": {"armor_flat": 30},
		"magnitude_key": "armor_flat"})
	set.apply(other, 50.0, -1.0, "player", T0 + 61, _none())
	assert_near(set.modifier_sum("armor_flat"), 30.0, 1e-9, "refresh_no_stack keeps the first magnitude")


func test_strongest_slow_wins_and_refreshes() -> void:
	var set := StatusSet.new()
	set.apply(_slow(), NAN, -1.0, "a", T0, _none())
	assert_near(set.magnitude("status.slow"), 0.3, 1e-9, "default magnitude 0.3")
	set.apply(_slow(), 0.2, -1.0, "b", T0 + 30, _none())
	assert_eq(set.count(), 1, "one slow instance")
	assert_near(set.magnitude("status.slow"), 0.3, 1e-9, "a weaker slow does not replace a stronger one")
	assert_near(set.remaining_s("status.slow", T0 + 30), 3.0, 1e-9, "but it refreshes the duration")
	set.apply(_slow(), 0.5, -1.0, "c", T0 + 40, _none())
	assert_near(set.magnitude("status.slow"), 0.5, 1e-9, "a stronger slow wins")
	assert_near(set.modifier_max("slow_fraction"), 0.5, 1e-9, "the modifier follows the magnitude")
	assert_near(set.remaining_s("status.slow", T0 + 40), 3.0, 1e-9, "and refreshes")
	var c := Combatant.from_record("def", {"id": "test.def", "health": 100})
	assert_near(c.move_mult(), 1.0, 1e-9, "no slow -> full speed")
	c.statuses.apply(_slow(), 0.95, -1.0, "x", T0, _none())
	assert_near(c.move_mult(), 0.1, 1e-9, "slows clamp at 90%")


func test_independent_instances_stack() -> void:
	var set := StatusSet.new()
	var d := _def({"id": "status.indep", "stacking": "independent", "modifiers": {"armor_flat": 5}})
	set.apply(d, NAN, -1.0, "a", T0, _none())
	set.apply(d, NAN, 1.0, "b", T0 + 10, _none())
	assert_eq(set.count(), 2, "independent applications are separate instances")
	assert_near(set.modifier_sum("armor_flat"), 10.0, 1e-9, "and add up")
	var expired := 0
	for t in range(T0 + 1, T0 + 200):
		for ev: Dictionary in set.tick(t):
			if ev.type == "expired":
				expired += 1
	assert_eq(expired, 2, "each instance expires on its own")


func test_hot_heals_exactly_100_over_240_ticks_and_caps() -> void:
	var set := StatusSet.new()
	set.apply(_mend(), NAN, -1.0, "player", T0, _none())
	var total := 0.0
	var heal_ticks: Array[int] = []
	var expired_at := -1
	for t in range(T0 + 1, T0 + 300):
		for ev: Dictionary in set.tick(t):
			if ev.type == "heal":
				total += float(ev.amount)
				heal_ticks.append(t - T0)
				assert_eq(ev.source, "player", "heals carry the caster")
			elif ev.type == "expired":
				expired_at = t - T0
	assert_near(total, 100.0, 1e-9, "8 x 12.5 = 100")
	assert_eq(heal_ticks, [30, 60, 90, 120, 150, 180, 210, 240] as Array[int], "every 0.5 s, the last on the expiry tick")
	assert_eq(expired_at, 240, "expires 4 s after application")
	var pools := ResourcePool.new()
	pools.configure({"health": 500, "stamina": 100, "essence": 100, "fury_max": 100}, {})
	pools.health = 450.0
	set.apply(_mend(), NAN, -1.0, "player", T0, _none())
	for t in range(T0 + 1, T0 + 241):
		for ev: Dictionary in set.tick(t):
			if ev.type == "heal":
				pools.heal(float(ev.amount))
	assert_near(pools.health, 500.0, 1e-9, "healing caps at maximum health")


func test_refresh_restarts_the_heal_schedule() -> void:
	var set := StatusSet.new()
	set.apply(_mend(), NAN, -1.0, "p", T0, _none())
	for t in range(T0 + 1, T0 + 100):
		set.tick(t)
	set.apply(_mend(), NAN, -1.0, "p", T0 + 100, _none())
	var heals := 0
	for t in range(T0 + 100, T0 + 400):
		for ev: Dictionary in set.tick(t):
			if ev.type == "heal":
				heals += 1
	assert_eq(heals, 8, "a refreshed Mend heals 8 more times")


func test_immune_tag_returns_false() -> void:
	var set := StatusSet.new()
	assert_false(set.apply(_slow(), NAN, -1.0, "a", T0, PackedStringArray(["Slow"])), "Slow immunity blocks a slow")
	assert_false(set.has("status.slow"), "nothing applied")
	assert_true(set.apply(_slow(), NAN, -1.0, "a", T0, PackedStringArray(["Fear"])), "other immunities do not")
	var c := Combatant.from_record("boss", {"id": "test.boss", "health": 100, "status_immunities": ["Slow", "Fear"]})
	assert_eq(c.status_immunities, PackedStringArray(["Slow", "Fear"]), "status_immunities read from the record")
	assert_false(c.is_immune_to("Slow"), "status immunity is not a hit immunity")


func test_expiry_reported_once_and_changed_signal() -> void:
	var set := StatusSet.new()
	var changes: Array[int] = [0]
	set.changed.connect(func() -> void: changes[0] += 1)
	set.apply(_slow(), NAN, -1.0, "a", T0, _none())
	assert_eq(changes[0], 1, "apply emits changed")
	var expired := 0
	for t in range(T0 + 1, T0 + 400):
		for ev: Dictionary in set.tick(t):
			if ev.type == "expired":
				expired += 1
				assert_eq(t - T0, 180, "a 3 s slow expires on tick +180")
	assert_eq(expired, 1, "expiry is reported exactly once")
	assert_eq(changes[0], 2, "expiry emits changed")
	assert_false(set.has("status.slow"), "gone")
	set.apply(_slow(), NAN, 1.0, "a", T0, _none())
	assert_near(set.remaining_s("status.slow", T0), 1.0, 1e-9, "an explicit duration overrides the record")
	set.remove("status.slow")
	assert_false(set.has("status.slow"), "remove")
	set.apply(_stone_skin(), NAN, -1.0, "a", T0, _none())
	set.clear()
	assert_true(set.is_empty(), "clear")


func test_armor_is_never_mutated() -> void:
	var c := Combatant.from_record("def", {"id": "test.def", "health": 500, "armor": 25})
	c.statuses.apply(_stone_skin(), NAN, -1.0, "p", T0, _none())
	assert_near(c.armor, 25.0, 1e-9, "base armor untouched while Stone Skin is active")
	assert_near(c.armor_total(), 55.0, 1e-9, "armor_total includes it")
	for t in range(T0 + 1, T0 + 361):
		c.statuses.tick(t)
	assert_near(c.armor, 25.0, 1e-9, "base armor untouched after expiry")
	assert_near(c.armor_total(), 25.0, 1e-9, "armor_total back to base")


func test_hud_list_sorted_and_hidden_left_out() -> void:
	var set := StatusSet.new()
	set.apply(_stone_skin(), NAN, -1.0, "p", T0, _none())
	set.apply(_slow(), NAN, -1.0, "e", T0, _none())
	set.apply(_hidden_assist(), NAN, -1.0, "bot", T0, _none())
	var rows := set.hud_list(T0 + 60)
	assert_eq(rows.size(), 2, "hidden statuses are left out")
	assert_eq([rows[0].id, rows[1].id], ["status.slow", "status.stone_skin"], "sorted by id")
	assert_eq(rows[0].label, "SLOW", "label")
	assert_true(rows[0].debuff and not rows[1].debuff, "debuff flag from the Debuff tag")
	assert_near(float(rows[1].remaining_s), 5.0, 1e-9, "remaining seconds")
	assert_true(set.has("status.bot_assist"), "the hidden status is still active")


# --------------------------------------------------------------------------- statuses in combat

func _defender() -> Combatant:
	return Combatant.from_record("def", {"id": "test.def", "health": 500, "armor": 25,
		"height_m": 3.6576, "poise": {"threshold": 100}})


func _hit(power := 40.0) -> HitEvent:
	var h := HitEvent.new()
	h.power = power
	h.attacker_stat = 10.0
	h.attacker_height_m = 3.6576
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Parryable"])
	h.poise_damage = 12.0
	h.attacker_position = Vector3(0, 0, -3)
	return h


func _defense(blocking := false) -> DefenseState:
	var d := DefenseState.new()
	d.forward = Vector3(0, 0, -1)
	d.height_m = 3.6576
	d.blocking = blocking
	d.block_elapsed_ticks = 30
	d.stamina = 100.0
	d.apply_block_def(GameData.get_action("action.block"))
	return d


func test_stone_skin_drops_the_worked_example_to_30() -> void:
	var c := _defender()
	assert_eq(DamageResolver.resolve(_hit(), c, _defense()).health_damage, 37, "37 without Stone Skin")
	c.statuses.apply(_stone_skin(), NAN, -1.0, "def", T0, _none())
	assert_eq(DamageResolver.resolve(_hit(), c, _defense()).health_damage, int(roundf(46.0 * 100.0 / 155.0)),
		"round(46 * 100 / 155) = 30 with +30 armor")
	assert_eq(DamageResolver.resolve(_hit(), c, _defense()).health_damage, 30, "= 30")
	var fire := _hit()
	fire.damage_split = {"fire": 1.0}
	assert_eq(DamageResolver.resolve(fire, c, _defense()).health_damage, 46, "armor never reduces elemental damage")


func test_titan_surge_damage_poise_and_no_fury() -> void:
	var attacker := Combatant.from_record("player", GameData.get_record("player.giant"), 3.6576)
	attacker.statuses.apply(_surge(), NAN, -1.0, "player", T0, _none())
	assert_near(attacker.outgoing_damage_mult(), 1.25, 1e-9, "x1.25 damage")
	assert_near(attacker.outgoing_poise_mult(), 1.25, 1e-9, "x1.25 poise")
	var h := _hit()
	h.outgoing_damage_mult = attacker.outgoing_damage_mult()
	h.outgoing_poise_mult = attacker.outgoing_poise_mult()
	var r := DamageResolver.resolve(h, _defender(), _defense())
	assert_eq(r.health_damage, 46, "46 x 1.25 = 57.5 raw -> x 100/125 = 46")
	assert_near(r.poise_damage, 15.0, 1e-9, "12 x 1.25 = 15 poise")
	attacker.pools.add_fury(4.0)
	attacker.pools.add_fury(8.0)
	assert_near(attacker.pools.fury, 0.0, 1e-9, "no fury gain while Titan Surge is active")
	attacker.statuses.remove("status.titan_surge")
	attacker.pools.add_fury(4.0)
	assert_near(attacker.pools.fury, 4.0, 1e-9, "fury gain returns when it ends")
	assert_near(attacker.outgoing_damage_mult(), 1.0, 1e-9, "multipliers back to 1")


func test_damage_taken_mult_zero_takes_nothing() -> void:
	var c := _defender()
	c.statuses.apply(_def({"id": "status.debug_invulnerable", "duration_s": 60.0,
		"modifiers": {"damage_taken_mult": 0.0}, "hidden": true}), NAN, -1.0, "debug", T0, _none())
	var hit := DamageResolver.resolve(_hit(), c, _defense())
	assert_eq(hit.outcome, HitResult.Outcome.HIT, "still a hit")
	assert_eq(hit.health_damage, 0, "0 health damage")
	var blocked := DamageResolver.resolve(_hit(), c, _defense(true))
	assert_eq(blocked.outcome, HitResult.Outcome.BLOCKED, "blocked")
	assert_eq(blocked.health_damage, 0, "0 health damage through a block")
	assert_near(blocked.stamina_damage, 0.0, 1e-9, "0 impact stamina")
	var assist := _defender()
	assist.statuses.apply(_hidden_assist(), NAN, -1.0, "bot", T0, _none())
	assert_eq(DamageResolver.resolve(_hit(), assist, _defense()).health_damage, int(roundf(36.8 * 0.25)),
		"bot assist x0.25: 36.8 -> 9.2 -> 9")
