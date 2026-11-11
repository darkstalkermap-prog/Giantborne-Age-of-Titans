extends IntegrationSuite
## P32 (plan M6-M9 §2.10, §3.16 tests, decision 21): the size override. An action's
## attacker_height_override_m is the attacker's height of its hits (HitFactory): a crewed ballista's
## bolt - flown by the real engine at a stage-4 giant - strikes as an 8 m attacker and staggers it
## (its poise ratio taken from the override), while an archer's arrow (1.8 m: the 0.25 floor) does not;
## the override never touches damage (siege actions keep size_policy "none", which the action schema
## requires with an override); the cavalry's charge strikes as a 4 m attacker.

const BALLISTA := "res://scenes/world/siege_ballista.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const ARCHER := "res://scenes/enemies/archer.tscn"
const BOLT := "ability.ballista_bolt"


## A giant of `stage` at `pos` facing -Z (its profile set directly: the growth path is P05's).
func _giant(stage: int, pos: Vector3) -> GiantPlayer:
	var p := spawn_player(pos, 0.0)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			p.set_profile(rec)
	return p


## The hit `attacker` would make on `target` with `action_id` now, built by HitFactory as a projectile's.
static func _built(attacker: CombatEntity, action_id: String, target: CombatEntity) -> HitEvent:
	var ctx := AttackContext.new()
	ctx.entity = attacker
	ctx.instance_id = Sim.new_instance_id()
	ctx.attacker_position = attacker.actor.global_position
	ctx.registry = HitRegistry.new()
	ctx.from_projectile = true
	return HitFactory.build(ctx, GameData.get_action(action_id), {"entity": target, "hurtbox": null,
		"point": target.anchor_position(), "substep": 0, "distance": 10.0, "weak_point": false}, 1, Sim.tick)


func test_a_bolt_staggers_a_stage_4_giant_while_an_arrow_does_not() -> void:
	TestFixtures.record_override("prop.siege_ballista", {"engine": {"reload_s": 0.2}})
	TestFixtures.record_override(BOLT, {"windup_s": 0.2})
	var p := _giant(4, Vector3(0, 0.05, 0))
	var archer := TestSpawn.enemy(world, ARCHER, Vector3(6, 0.05, -18), "test.p32_archer", false, 0.0)
	var engine := (load(BALLISTA) as PackedScene).instantiate() as SiegeEngine
	engine.world_id = "test.p32_ballista"
	engine.position = Vector3(0, 0, -26)
	engine.rotation.y = PI   # its front (-Z) toward the giant
	world.add_child(engine)
	await step_ticks(2)
	assert_eq(p.current_growth_stage(), 4, "a stage-4 giant")
	var threshold := p.entity.combatant.poise.threshold
	# The arrow first: an archer is 1.8 m, so its poise ratio sits at the 0.25 floor.
	var arrow := _built(archer.entity, "ability.archer_shot", p.entity)
	assert_near(arrow.attacker_height_m, 1.8, 1e-4, "an arrow strikes from the archer's own height")
	Sim.queue_hit(arrow)
	await step_ticks(1)
	var arrow_hits := hits_on(p.entity.entity_id)
	assert_eq(arrow_hits.size(), 1, "the arrow lands")
	if arrow_hits.size() == 1:
		assert_near(arrow_hits[0].poise_damage, 12.0 * CombatRules.POISE_SCALE_MIN, 1e-3, "its poise at the floor ratio")
		assert_false(arrow_hits[0].poise_broken, "the arrow does not stagger the giant")
	assert_false(p.controller.state == CombatController.State.STAGGERED, "the giant stands")
	p.entity.combatant.poise.value = 0.0
	# The ballista, crewed, shoots at the giant: its bolt strikes as an 8 m attacker.
	var crew := TestSpawn.enemy(world, CREW, engine.global_position + Vector3(0, 0.05, -2.0), "test.p32_crew", false, PI)
	engine.add_crew(crew)
	var struck: bool = await TestWait.until(self, func() -> bool:
		for r in hits_on(p.entity.entity_id):
			if r.event.action_id == BOLT:
				return true
		return false, 120)
	assert_true(struck, "the crewed ballista's bolt strikes the giant (%d shots)" % engine.shots)
	if not struck:
		return
	var bolt: HitResult = null
	for r in hits_on(p.entity.entity_id):
		if r.event.action_id == BOLT:
			bolt = r
	assert_near(bolt.event.attacker_height_m, 8.0, 1e-4, "the bolt's attacker height is the override (8 m)")
	var ratio := CombatRules.poise_scale(8.0, p.entity.combatant.height_m)
	assert_near(bolt.poise_damage, GameData.get_action(BOLT).poise_damage * ratio, 1e-3,
		"its poise: the bolt's poise x the 8 m ratio (%.3f)" % ratio)
	assert_true(bolt.poise_damage >= threshold, "enough for the stage-4 giant's threshold (%.1f of %.1f)" % [
		bolt.poise_damage, threshold])
	assert_true(bolt.poise_broken, "the bolt breaks the giant's poise")
	var staggered: bool = await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.STAGGERED, 3)
	assert_true(staggered or p.controller.state == CombatController.State.STAGGERED, "and staggers it")
	# The override changes poise, never damage: the same bolt from the engine's own height deals the same.
	var plain := _built(engine.entity, BOLT, p.entity)
	plain.attacker_height_m = engine.entity.combatant.height_m
	var big := _built(engine.entity, BOLT, p.entity)
	assert_near(big.attacker_height_m, 8.0, 1e-4, "built through HitFactory with the override")
	var mine := DamageResolver.mitigate(big, p.entity.combatant)
	var theirs := DamageResolver.mitigate(plain, p.entity.combatant)
	assert_near(float(mine.total), float(theirs.total), 1e-4, "size_policy none: the damage does not grow with the override")
	crew.queue_free()
	archer.queue_free()


func test_the_cavalry_charge_strikes_as_a_4_m_attacker_and_the_schema_keeps_damage_out() -> void:
	var p := _giant(4, Vector3(0, 0.05, 0))
	var archer := TestSpawn.enemy(world, ARCHER, Vector3(4, 0.05, -10), "test.p32_rider_stand_in", false, 0.0)
	await step_ticks(1)
	var charge := _built(archer.entity, "ability.cavalry_charge", p.entity)
	assert_near(charge.attacker_height_m, 4.0, 1e-4, "the charge strikes as a 4 m attacker")
	assert_eq(charge.size_policy, "none", "with size_policy none")
	var lance := _built(archer.entity, "ability.cavalry_lance", p.entity)
	assert_near(lance.attacker_height_m, archer.entity.combatant.height_m, 1e-4, "the lance has no override")
	# The schema: an override with the default size policy (attacker_growth) is refused.
	var rec: Dictionary = GameData.get_record("ability.cavalry_charge").duplicate(true)
	rec.erase("size_policy")
	var r := DataValidator.validate_record(rec, "test.json")
	var refused := false
	for e: Variant in r.get("errors", []):
		if str(e).contains("attacker_height_override_m"):
			refused = true
	assert_true(refused, "an override needs size_policy none (%s)" % [r.get("errors", [])])
	archer.queue_free()
