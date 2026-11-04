extends IntegrationSuite
## P03, decision 17: lock-on, soft targeting and the player's area effects consider only
## entities the player may target (TargetingRules.player_may_target: team ENEMY, or NEUTRAL
## with no faction). A NEUTRAL villager stub with faction "village" is never locked or
## soft-targeted, and Footfall, Sweeping Blow and Thunder Roar beside it never queue a hit on
## it; a direct light swing or a direct projectile still hits it (P11b makes that an offence).
## The practice dummy (NEUTRAL, no faction) stays lockable.

const STUB_SCRIPT := "res://tests/support/stub_enemy.gd"


func before_each() -> void:
	await super()
	world.add_to_group("level_root")   # projectile systems are freed with the test world


## A NEUTRAL village member on the soldier body (StubEnemy: no guard, no AI).
func _spawn_villager(pos: Vector3, yaw := 0.0, id := "village.stub") -> EnemyActor:
	var node: Node = (load(SOLDIER) as PackedScene).instantiate()
	node.set_script(load(STUB_SCRIPT))
	var v := node as EnemyActor
	v.name = "Villager"
	v.entity_id = id
	v.ai_enabled = false
	v.faction = "village"
	(v.get_node("CombatEntity") as CombatEntity).team = CombatEntity.Team.NEUTRAL
	v.position = pos
	v.rotation.y = yaw
	world.add_child(v)
	return v


## The position at `dist` metres and yaw `yaw_deg` (TargetingRules convention) from the origin.
static func _at(yaw_deg: float, dist: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	return Vector3(-sin(y) * dist, 0.05, -cos(y) * dist)


func test_rules_and_skip_candidate() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var v := _spawn_villager(_at(0.0, 6.0), PI)
	var s := spawn_soldier(_at(40.0, 6.0), PI)
	var d := spawn_dummy(_at(-40.0, 6.0))
	await step_ticks(2)
	assert_eq(v.entity.faction, "village", "the stub carries its faction into its CombatEntity")
	assert_false(TargetingRules.player_may_target(v.entity), "a village member is off limits")
	assert_true(TargetingRules.player_may_target(s.entity), "an enemy may be targeted")
	assert_true(TargetingRules.player_may_target(d.entity), "a faction-less dummy may be targeted")
	assert_true(HitFactory.skip_candidate(p.entity, v.entity, true), "the player's area effects skip it")
	assert_false(HitFactory.skip_candidate(p.entity, v.entity, false), "direct blows are never filtered")
	assert_false(HitFactory.skip_candidate(p.entity, s.entity, true), "area effects still hit enemies")
	assert_false(HitFactory.skip_candidate(p.entity, d.entity, true), "and the dummy")
	assert_false(HitFactory.skip_candidate(s.entity, v.entity, true), "only the player's area effects filter")
	assert_false(p.targeting.may_target(v.entity), "PlayerTargeting.may_target uses the same rule")
	var ids: Array = []
	for c: Dictionary in p.targeting.gather_candidates(false):
		ids.append(c.id)
	assert_false(ids.has("village.stub"), "not a lock candidate")
	assert_true(ids.has("soldier_01") and ids.has("dummy_01"), "the others are")


func test_lock_selects_nothing_with_only_a_village_member_in_front() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_spawn_villager(_at(0.0, 6.0), PI)
	await step_ticks(2)
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "", "Tab selects nothing")
	p.router.inject_edge(&"target_right")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "", "and switching finds nothing either")


func test_soft_targeting_never_turns_toward_a_village_member() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var v := _spawn_villager(_at(25.0, 3.0), deg_to_rad(25.0) + PI)
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(11)
	assert_eq(p.controller.phase(), ActionDef.Phase.WINDUP, "still winding up")
	assert_near(p.facing_yaw, 0.0, 1e-4, "no soft-target turn toward the villager")
	await step_ticks(60)
	# Control: a soldier on the same spot pulls the swing toward it.
	v.queue_free()
	await step_ticks(2)
	spawn_soldier(_at(25.0, 3.0), deg_to_rad(25.0) + PI)
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(11)
	assert_true(p.facing_yaw > deg_to_rad(5.0), "a hostile target is soft-targeted (%.1f deg)" % rad_to_deg(p.facing_yaw))


func test_area_effects_beside_a_village_member_queue_no_hit_on_it() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var v := _spawn_villager(_at(-40.0, 2.2), 0.0)
	spawn_dummy(_at(40.0, 2.2))
	await step_ticks(2)
	for spec: Array in [[&"slot_1", "ability.heavy_footfall"], [&"slot_2", "ability.sweeping_blow"],
			[&"slot_8", "ability.thunder_roar"]]:
		var before := hits_on("dummy_01").size()
		assert_eq(p.controller.loadout[String(spec[0])], spec[1], "%s is in %s" % [spec[1], spec[0]])
		p.router.inject_edge(spec[0])
		await step_ticks(70)
		assert_eq(hits_on("dummy_01").size(), before + 1, "%s fired and hit the dummy beside it" % spec[1])
		assert_eq(hits_on("village.stub").size(), 0, "%s queued no hit on the villager" % spec[1])
	assert_false(v.entity.combatant.statuses.has("status.slow"), "the roar never slowed it")


func test_direct_blows_still_hit_a_village_member() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_spawn_villager(_at(0.0, 2.6), PI)
	await step_ticks(2)
	p.router.inject_light_attack()
	await step_ticks(45)
	assert_eq(hits_on("village.stub").size(), 1, "a deliberate light swing still lands")
	var sys := ProjectileSystem.instance(get_tree())
	sys.spawn(p.entity, action("ability.runic_bolt"), Vector3(0, 1.2, -0.9), Vector3(0, 0, -35),
		p.attack.runner.context())
	await step_ticks(5)
	assert_eq(hits_on("village.stub").size(), 2, "and so does a direct projectile")


func test_practice_dummy_stays_lockable() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_spawn_villager(_at(0.0, 5.0), PI)
	spawn_dummy(_at(8.0, 7.0))
	await step_ticks(2)
	p.router.inject_edge(&"lock_press")
	await step_ticks(2)
	assert_eq(p.lock.target_id, "dummy_01", "the dummy is locked, the villager in front is skipped")
