extends TestSuite
## P01: ResourcePool rescale / restore / snapshot, PoiseMeter's new fields, Combatant derived
## values, the two CombatEntity poise rules (recovery punish, stagger vs a much larger attacker),
## and TargetingRules.player_may_target.

var _nodes: Array[Node] = []
var _restore: Array = []   # [id, previous] pairs for GameData.restore_record


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	_restore.reverse()
	for pair: Array in _restore:
		GameData.restore_record(pair[0], pair[1])
	_restore.clear()
	await get_tree().process_frame


func _pool() -> ResourcePool:
	var p := ResourcePool.new()
	p.configure({"health": 500, "stamina": 100, "essence": 100, "fury_max": 100},
		{"stamina_per_s": 15, "stamina_delay_s": 1.0, "essence_per_s": 4, "essence_delay_s": 2.0,
		"fury_decay_per_s": 5, "fury_decay_delay_s": 10})
	return p


## A bare actor (Node3D) with a CombatEntity child, added to the tree (registers with Sim).
func _bare(id: String, definition: String, team := CombatEntity.Team.ENEMY, actor_script: GDScript = null) -> CombatEntity:
	var actor := Node3D.new()
	if actor_script != null:
		actor.set_script(actor_script)
	var ce := CombatEntity.new()
	ce.name = "CombatEntity"
	ce.entity_id = id
	ce.definition_id = definition
	ce.team = team
	actor.add_child(ce)
	add_child(actor)
	_nodes.append(actor)
	return ce


func _override(id: String, patch: Dictionary) -> void:
	_restore.append([id, GameData.override_record(id, patch)])


func _enemy(id: String, poise: Dictionary) -> void:
	var rec: Dictionary = (GameData.get_record("enemy.soldier") as Dictionary).duplicate(true)
	rec["id"] = id
	rec["poise"] = poise
	_override(id, rec)


func _hit(poise: float, attacker_height: float) -> HitEvent:
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "test.attacker"
	h.power = 10.0
	h.attacker_stat = 10.0
	h.attacker_height_m = attacker_height
	h.damage_split = {"physical": 1.0}
	h.poise_damage = poise
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = Vector3(0, 0, -3)
	return h


# --------------------------------------------------------------------------- ResourcePool

func test_rescale_keeps_ratios() -> void:
	var p := _pool()
	p.damage_health(250.0)
	p.spend_stamina(25.0)
	p.spend_essence(40.0)
	p.add_fury(30.0)
	p.rescale({"health": 650, "stamina": 110, "essence": 100, "fury_max": 100})
	assert_near(p.health, 325.0, 1e-9, "50% health stays 50% of the new maximum")
	assert_near(p.stamina, 82.5, 1e-9, "75% stamina stays 75%")
	assert_near(p.essence, 60.0, 1e-9, "essence ratio kept")
	assert_near(p.fury, 30.0, 1e-9, "fury is absolute")
	assert_near(p.health_max, 650.0, 1e-9, "new maximum")
	p.rescale({"health": 500})
	assert_near(p.health, 250.0, 1e-9, "shrinking keeps the ratio too (nothing heals by switching)")
	assert_near(p.stamina_max, 110.0, 1e-9, "missing keys keep their maximum")
	p.add_fury(70.0)
	p.rescale({"fury_max": 50})
	assert_near(p.fury, 50.0, 1e-9, "fury clamps to a smaller maximum")
	var e := ResourcePool.new()
	e.configure({"health": 100, "stamina": 40, "essence": 0, "fury_max": 100}, {})
	e.rescale({"essence": 50})
	assert_near(e.essence, 50.0, 1e-9, "a pool with no previous maximum starts full")
	p.damage_health(10000.0)
	p.rescale({"health": 800})
	assert_near(p.health, 0.0, 1e-9, "zero health stays zero")


func test_restore_clamps_and_snapshot_round_trips() -> void:
	var p := _pool()
	p.spend_stamina(10.0)
	p.restore({"health": 9999.0, "stamina": -5.0, "essence": 42.0, "fury": 30.0})
	assert_near(p.health, 500.0, 1e-9, "health clamps to its maximum")
	assert_near(p.stamina, 0.0, 1e-9, "stamina clamps at zero")
	assert_near(p.essence, 42.0, 1e-9, "essence")
	assert_near(p.fury, 30.0, 1e-9, "fury")
	assert_eq([p.since_stamina_spend, p.since_essence_spend, p.since_combat], [999.0, 999.0, 999.0],
		"regen timers as if idle")
	var snap := p.snapshot()
	assert_eq(snap, {"health": 500.0, "stamina": 0.0, "essence": 42.0, "fury": 30.0}, "snapshot")
	var q := _pool()
	q.restore(snap)
	assert_eq(q.snapshot(), snap, "restore(snapshot()) round-trips")
	q.restore({"essence": 10.0})
	assert_near(q.health, 500.0, 1e-9, "missing keys are kept")
	assert_near(q.essence, 10.0, 1e-9, "given keys are restored")
	p.fury_gain_mult = 0.5
	p.add_fury(10.0)
	assert_near(p.fury, 35.0, 1e-9, "add_fury scales by fury_gain_mult")


# --------------------------------------------------------------------------- PoiseMeter

func test_poise_meter_new_fields_and_reconfigure() -> void:
	var m := PoiseMeter.new()
	m.configure({"threshold": 120, "stagger_s": 1.0, "recovery_mult": 3.5, "stagger_vs_larger_s": 1.5})
	assert_near(m.recovery_mult, 3.5, 1e-9, "recovery_mult read")
	assert_near(m.stagger_duration(true), 1.5, 1e-9, "a much larger attacker staggers longer")
	assert_near(m.stagger_duration(false), 1.0, 1e-9, "others use stagger_s")
	var plain := PoiseMeter.new()
	plain.configure({"threshold": 40, "stagger_s": 1.0})
	assert_near(plain.recovery_mult, 1.0, 1e-9, "default recovery_mult 1")
	assert_near(plain.stagger_duration(true), 1.0, 1e-9, "unset stagger_vs_larger_s falls back to stagger_s")
	m.add(50.0)
	m.reconfigure({"threshold": 120, "stagger_s": 1.0}, 14.0)
	assert_near(m.threshold, 132.0, 1e-9, "Constitution 14 adds 12")
	assert_near(m.value, 50.0, 1e-9, "the accumulated value is kept")
	m.reconfigure({"threshold": 120}, 10.0, false)
	assert_near(m.value, 0.0, 1e-9, "unless keep_value is false")


# --------------------------------------------------------------------------- Combatant

func _base_giant() -> Dictionary:
	return {"id": "test.giant", "attributes": {"strength": 10, "endurance": 10, "dexterity": 10,
		"intellect": 10, "willpower": 10, "constitution": 10},
		"resources": {"health": 500, "stamina": 100, "essence": 100, "fury_max": 100},
		"poise": {"threshold": 100, "stagger_s": 1.0}}


func test_combatant_derived_values() -> void:
	var c := Combatant.from_record("player", _base_giant(), 3.6576)
	assert_near(c.pools.health_max, 500.0, 1e-9, "base health")
	c.pools.damage_health(250.0)
	c.growth_bonus = {"health": 150, "stamina": 10}
	c.recompute_derived()
	assert_near(c.pools.health_max, 650.0, 1e-9, "growth adds body (+150 health)")
	assert_near(c.pools.health, 325.0, 1e-9, "the health fraction is preserved")
	assert_near(c.pools.stamina_max, 110.0, 1e-9, "+10 stamina")
	var changes: Array[int] = [0]
	c.derived_changed.connect(func() -> void: changes[0] += 1)
	c.set_attributes({"endurance": 14, "dexterity": 30, "constitution": 14, "nonsense": 99})
	assert_eq(changes[0], 1, "derived_changed emitted")
	assert_near(c.pools.health_max, 650.0 + 60.0, 1e-9, "Endurance 14 adds 60 health")
	assert_near(c.pools.health, 355.0, 1e-9, "still half")
	assert_near(c.pools.stamina_max, 118.0, 1e-9, "and 8 stamina")
	assert_near(c.poise.threshold, 112.0, 1e-9, "Constitution 14 adds 12 poise threshold")
	assert_near(c.recovery_scale(), 0.9, 1e-9, "Dexterity 30 -> 10% faster recovery")
	assert_near(c.attribute("strength"), 10.0, 1e-9, "unlisted attributes are kept")
	var shipped := Combatant.from_record("player", GameData.get_record("player.giant"), 3.6576)
	var before := shipped.pools.health_max
	shipped.growth_bonus = {"health": 150}
	shipped.recompute_derived()
	assert_near(shipped.pools.health_max, before + 150.0, 1e-9, "the shipped giant grows by its bonus")
	c.set_height(5.4864)
	assert_near(c.height_m, 5.4864, 1e-9, "set_height")


func test_combatant_reads_new_record_fields() -> void:
	var mage := Combatant.from_record("mage", {"id": "test.mage", "health": 120, "essence": 80,
		"regen": {"essence_per_s": 6.0}, "mass_class": "medium", "xp_reward": 15,
		"status_immunities": ["Fear"]})
	assert_near(mage.pools.essence_max, 80.0, 1e-9, "enemies without a resources block read essence")
	assert_near(mage.pools.essence, 80.0, 1e-9, "and start full")
	assert_near(mage.pools.essence_regen_per_s, 6.0, 1e-9, "and regen")
	assert_eq(mage.mass_class, "medium", "mass_class")
	assert_eq(mage.xp_reward, 15, "xp_reward")
	assert_eq(mage.status_immunities, PackedStringArray(["Fear"]), "status_immunities")
	assert_eq(str(mage.base_record.id), "test.mage", "base_record")
	var grunt := Combatant.from_record("s", {"id": "test.grunt", "health": 220, "stamina": 40})
	assert_near(grunt.pools.essence_max, 0.0, 1e-9, "no essence field -> 0 (unchanged)")
	assert_eq(grunt.mass_class, "small", "default mass class")
	assert_eq(grunt.xp_reward, 0, "default xp_reward")


func test_recovery_scale_pushed_to_controller() -> void:
	var ce := _bare("test.dex", "player.giant", CombatEntity.Team.PLAYER)
	var ctl := CombatController.new(ce.entity_id, ce.combatant)
	ce.controller = ctl
	assert_near(ctl.recovery_scale, ce.combatant.recovery_scale(), 1e-9, "starts from the combatant")
	ce.combatant.set_attributes({"dexterity": 30})
	assert_near(ctl.recovery_scale, CombatRules.recovery_scale(30.0), 1e-9, "CombatEntity pushes the new recovery_scale")


# --------------------------------------------------------------------------- poise rules

func test_recovery_punish_only_in_recovery() -> void:
	_enemy("enemy.test_ogre", {"threshold": 1000, "stagger_s": 1.0, "recovery_mult": 3.5})
	var ce := _bare("test.ogre_1", "enemy.test_ogre")
	assert_near(ce.combatant.poise.recovery_mult, 3.5, 1e-9, "read from the record")
	var ctl := CombatController.new(ce.entity_id, ce.combatant)
	ctl.add_action(GameData.get_action("ability.soldier_slash"))
	ce.controller = ctl
	var t := 500
	ctl.begin_tick(t)
	var r := ce.receive_hit(_hit(10.0, 1.8), null)
	assert_near(r.poise_damage, 10.0, 1e-9, "idle: x1")
	ctl.request(&"attack", {"action_id": "ability.soldier_slash"})
	assert_eq(ctl.phase(), ActionDef.Phase.WINDUP, "windup")
	r = ce.receive_hit(_hit(10.0, 1.8), null)
	assert_near(r.poise_damage, 10.0, 1e-9, "windup: x1")
	while ctl.phase() != ActionDef.Phase.ACTIVE:
		t += 1
		ctl.begin_tick(t)
	r = ce.receive_hit(_hit(10.0, 1.8), null)
	assert_near(r.poise_damage, 10.0, 1e-9, "active: x1")
	while ctl.phase() != ActionDef.Phase.RECOVERY:
		t += 1
		ctl.begin_tick(t)
	r = ce.receive_hit(_hit(10.0, 1.8), null)
	assert_near(r.poise_damage, 35.0, 1e-9, "own RECOVERY phase: x3.5")
	assert_near(ce.combatant.poise.value, 65.0, 1e-9, "the meter received the multiplied amount")


func test_much_larger_attacker_staggers_longer() -> void:
	_enemy("enemy.test_grunt", {"threshold": 40, "stagger_s": 1.0, "immunity_s": 1.5, "stagger_vs_larger_s": 1.5})
	var cases := [["test.grunt_big", 3.6576, 90], ["test.grunt_twice", 3.6, 90], ["test.grunt_peer", 1.8, 60]]
	for c: Array in cases:
		var ce := _bare(c[0], "enemy.test_grunt")
		var ctl := CombatController.new(ce.entity_id, ce.combatant)
		ce.controller = ctl
		ctl.begin_tick(600)
		var r := ce.receive_hit(_hit(50.0, c[1]), null)
		assert_true(r.poise_broken, "%s: poise broken" % c[0])
		assert_eq(ctl.stagger_ticks_left, c[2], "%s: attacker %.2f m vs 1.8 m staggers %d ticks" % [c[0], c[1], c[2]])
	_enemy("enemy.test_plain", {"threshold": 40, "stagger_s": 1.0, "immunity_s": 1.5})
	var ce2 := _bare("test.grunt_plain", "enemy.test_plain")
	var ctl2 := CombatController.new(ce2.entity_id, ce2.combatant)
	ce2.controller = ctl2
	ctl2.begin_tick(600)
	ce2.receive_hit(_hit(50.0, 3.6576), null)
	assert_eq(ctl2.stagger_ticks_left, 60, "without stagger_vs_larger_s a larger attacker uses stagger_s")


# --------------------------------------------------------------------------- targeting

func test_player_may_target() -> void:
	var made: Array[CombatEntity] = []
	var cases := [[CombatEntity.Team.ENEMY, "", true, "enemy"],
		[CombatEntity.Team.NEUTRAL, "", true, "neutral without a faction (dummy, prop)"],
		[CombatEntity.Team.NEUTRAL, "village", false, "neutral village member"],
		[CombatEntity.Team.PLAYER, "", false, "the player"],
		[CombatEntity.Team.ENEMY, "village", true, "a hostile guard (turned ENEMY)"]]
	for c: Array in cases:
		var e := CombatEntity.new()
		e.team = c[0]
		e.faction = c[1]
		made.append(e)
		assert_eq(TargetingRules.player_may_target(e), c[2], c[3])
	assert_false(TargetingRules.player_may_target(null), "null")
	for e in made:
		e.free()


func test_faction_read_from_actor() -> void:
	var s := GDScript.new()
	s.source_code = "extends Node3D\nvar entity_id := \"valley.village.guard_1\"\nvar faction := \"village\"\n"
	s.reload()
	var guard := _bare("ignored.id", "enemy.soldier", CombatEntity.Team.NEUTRAL, s)
	assert_eq(guard.entity_id, "valley.village.guard_1", "the actor's entity_id wins")
	assert_eq(guard.faction, "village", "faction read from the actor in _ready")
	assert_false(TargetingRules.player_may_target(guard), "a neutral guard is not a target")
	var dummy := _bare("test.dummy_plain", "prop.practice_dummy", CombatEntity.Team.NEUTRAL)
	assert_eq(dummy.faction, "", "no faction property -> \"\"")
	assert_true(TargetingRules.player_may_target(dummy), "a dummy is a target")
