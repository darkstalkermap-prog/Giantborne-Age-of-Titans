extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 20): the target provider. An enemy record's `targets`
## lets it fight NPCs of the listed factions and props with the listed prop tags besides the giant:
## a raider (the soldier with targets {factions: village, prop_tags: house, aggro_player_m 12})
## attacks a house (a breakable prop tagged "house") and lands its hits on it although the M1 team
## rule lets an enemy hit only the player; with no house left it takes the nearest villager; and
## the giant comes first once it is seen within aggro_player_m. Without `targets` nothing changes:
## a plain soldier ignores the house and the villager.

const VILLAGER := "res://scenes/npcs/villager.tscn"


func _villager(pos: Vector3, id: String) -> Civilian:
	var v := (load(VILLAGER) as PackedScene).instantiate() as Civilian
	v.entity_id = id
	v.ai_enabled = false
	v.position = pos
	world.add_child(v)
	return v


func test_raiders_attack_a_house_and_a_villager_then_the_giant_when_it_comes() -> void:
	var plain := spawn_soldier(Vector3(-8, 0.05, -2), PI, "test.plain_soldier", false)
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"prop_tags": ["house"], "aggro_player_m": 12.0}})
	var house := spawn_fence(Vector3(0, 0, -5), "test.house")
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", true)   # facing the house
	var villager := _villager(Vector3(4, 0.05, -9), "test.villager")   # in the raider's view, beyond the house
	var p := spawn_player(Vector3(0, 0.05, 40), PI)
	await step_ticks(2)
	assert_eq(raider._target(), house.entity, "the giant far away: the raider takes the house")
	assert_true(plain._target() == null or plain._target() == p.entity, "a soldier without targets never takes it")
	var struck: bool = await TestWait.until(self, func() -> bool: return not hits_on("test.house").is_empty(), 150)
	assert_true(struck, "the raider's blows land on the house")
	if struck:
		assert_eq(hits_on("test.house")[0].event.attacker_id, "test.raider", "its own")
	# the house is gone: the nearest villager
	house.queue_free()
	await step_ticks(2)
	assert_eq(raider._target(), villager.entity, "with no house left it takes the villager")
	var follows: bool = await TestWait.until(self, func() -> bool: return raider.brain.target_id == "test.villager", 30)
	assert_true(follows, "and its brain follows (%s)" % raider.brain.target_id)
	# the giant comes within aggro_player_m, in sight (in front of the raider)
	var fwd := -raider.global_transform.basis.z
	fwd.y = 0.0
	p.global_position = raider.global_position + fwd.normalized() * 8.0 + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	assert_eq(raider._target(), p.entity, "the giant within 12 m comes first")
	p.global_position = Vector3(0, 0.05, 30)
	await step_ticks(2)
	assert_eq(raider._target(), villager.entity, "beyond 12 m the villager again (aggro_player_m)")
	assert_eq(villager.entity.team, CombatEntity.Team.NEUTRAL, "the villager stays neutral: only the raider may hit it")
	plain.queue_free()


## W23 (P39f; FOLLOWUPS "From P37"): with nothing of its targets in sight a raider keeps no target - it no
## longer falls back to the giant it does not see - so once its house is gone a stage-4 giant 60 m off does
## not rout it (the outmatched rule measured it against him); within aggro_player_m and in sight the giant
## comes first again.
func test_with_nothing_in_sight_a_raider_keeps_no_target_and_does_not_rout_from_a_far_giant() -> void:
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"prop_tags": ["house"], "aggro_player_m": 20.0}})
	var house := spawn_fence(Vector3(0, 0, -5), "test.house")
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", true)   # facing the house
	var p := spawn_player(Vector3(0, 0.05, 60), PI)
	p.set_profile(GameData.get_record("growth.04"))
	await step_ticks(2)
	assert_eq(raider._target(), house.entity, "the raider takes the house")
	var aware: bool = await TestWait.until(self, func() -> bool:
		return raider.brain.aware and raider.brain.target_id == "test.house", 60)
	assert_true(aware, "and is aware of it")
	house.queue_free()   # burned
	await step_ticks(2)
	assert_eq(raider._target(), null, "nothing of its targets in sight: no target (not the stage-4 giant 60 m off)")
	var routed := false
	for i in 120:
		await step_ticks(1)
		routed = routed or raider.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]
	assert_false(routed, "it does not flee or rout from a giant it does not see (state %s)" % EnemyBrain.AIState.keys()[raider.brain.state])
	assert_true(raider.entity.is_alive() and not raider.brain.state == EnemyBrain.AIState.ROUTED, "it stays in the raid")
	var fwd := -raider.global_transform.basis.z
	fwd.y = 0.0
	p.global_position = raider.global_position + fwd.normalized() * 14.0 + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	assert_eq(raider._target(), p.entity, "the giant within aggro_player_m and in sight comes first")


## W23 (P39f; FOLLOWUPS "From P37"): the provider never takes a target its blows cannot damage - a villager in
## shelter (inside: hidden, out of the world's physics; a raider stood at the mill's shelter for the rest of a
## raid) or a protected NPC (Reeve Tamsin refuses every blow) - and gives up one it has been fixed on for
## P30_GIVE_UP_S without damaging it, for P30_GIVEN_UP_S; a blow that damages it starts the count again.
func test_a_raider_skips_sheltered_and_protected_people_and_gives_up_one_it_cannot_damage() -> void:
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"aggro_player_m": 12.0}})
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", false)   # facing -z
	var sheltered := _villager(Vector3(1.5, 0.05, -7), "test.sheltered")
	spawn_player(Vector3(0, 0.05, 60), PI)
	await step_ticks(2)
	assert_eq(raider._target(), sheltered.entity, "a villager in the open is a target")
	sheltered._take_shelter()
	await step_ticks(1)
	assert_true(sheltered.sheltered and sheltered.entity.is_alive(), "the villager is in shelter, alive")
	assert_eq(raider._target(), null, "a villager in shelter is no target")
	TestFixtures.record_override("npc.villager", {"protected": true})
	var reeve := _villager(Vector3(-1.5, 0.05, -8), "test.reeve")
	await step_ticks(2)
	assert_false(reeve.accepts_hit(null), "a protected villager refuses every blow")
	assert_eq(raider._target(), null, "a protected NPC is no target")
	TestFixtures.restore_all()
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"aggro_player_m": 12.0}})
	var aloft := _villager(Vector3(-1.0, 0.05, -9), "test.aloft")
	await step_ticks(2)
	assert_eq(raider._target(), aloft.entity, "a villager it can see is a target")
	# a blow that damages it starts the give-up count again
	var keep := raider._p30_fix_tick
	raider._p30_fix_tick = Sim.tick - int(EnemyActor.P30_GIVE_UP_S * Sim.TICK_RATE) + 30
	var damaging := HitResult.new()
	damaging.event = HitEvent.new()
	damaging.event.target_id = "test.aloft"
	damaging.health_damage = 5
	raider.entity.hit_landed.emit(damaging)
	assert_eq(raider._p30_fix_tick, Sim.tick, "a damaging blow restarts the count (it was %d)" % keep)
	await step_ticks(1)
	assert_eq(raider._target(), aloft.entity, "so it keeps its target")
	# fixed on it for P30_GIVE_UP_S without damaging it: given up
	raider._p30_fix_tick = Sim.tick - int(EnemyActor.P30_GIVE_UP_S * Sim.TICK_RATE) - 1
	await step_ticks(1)
	assert_eq(raider._target(), null, "fixed on it for %.0f s without damage: given up" % EnemyActor.P30_GIVE_UP_S)
	await step_ticks(30)
	assert_eq(raider._target(), null, "and left alone for a while")
	raider._p30_given_up["test.aloft"] = Sim.tick
	await step_ticks(1)
	assert_eq(raider._target(), aloft.entity, "after P30_GIVEN_UP_S it may take it again")


## W23 fix-up (lane P39f's verifier): the give-up count runs only while the provider keeps picking the NPC or
## prop. A raider that took a house fights the giant for longer than P30_GIVE_UP_S; when he steps off it takes
## the house again with a fresh count. Before, the fight counted as time spent on the house: the raider gave
## the house up the moment it saw it again and left it alone for P30_GIVEN_UP_S (in the Millford raid, a giant
## who fought the raiders and stepped off left them idle for a minute).
func test_a_raider_that_fought_the_giant_goes_back_to_its_house() -> void:
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"prop_tags": ["house"], "aggro_player_m": 12.0}})
	var house := spawn_fence(Vector3(0, 0, -5), "test.house")
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", true)   # facing the house
	var p := spawn_player(Vector3(0, 0.05, 40), PI)
	await step_ticks(2)
	assert_eq(raider._target(), house.entity, "the giant far away: the raider takes the house")
	# the giant comes within aggro_player_m, in sight, and they fight for longer than P30_GIVE_UP_S
	var fwd := -raider.global_transform.basis.z
	fwd.y = 0.0
	p.global_position = raider.global_position + fwd.normalized() * 8.0 + Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	await step_ticks(2)
	assert_eq(raider._target(), p.entity, "the giant within 12 m comes first")
	await step_ticks(int((EnemyActor.P30_GIVE_UP_S + 1.0) * Sim.TICK_RATE))
	assert_eq(raider._target(), p.entity, "and stays its target through a fight longer than P30_GIVE_UP_S")
	p.global_position = Vector3(0, 0.05, 40)   # he steps off, beyond aggro_player_m
	p.velocity = Vector3.ZERO
	var left := Sim.tick
	await step_ticks(3)
	assert_eq(raider._target(), house.entity, "the giant gone, it takes the house again: the fight was no time spent on it")
	assert_false(raider._p30_given_up.has("test.house"), "not given up (%s)" % raider._p30_given_up)
	assert_true(raider._p30_fix_tick >= left, "its count started when it took the house again (%d, left %d)" % [raider._p30_fix_tick, left])
	var follows: bool = await TestWait.until(self, func() -> bool: return raider.brain.target_id == "test.house", 120)
	assert_true(follows, "and its brain goes back to the house (%s)" % raider.brain.target_id)


## W23 fix-up: a raider asleep (the AI LOD's dormant tier senses nothing) for longer than P30_FIX_GAP_S starts
## its give-up count again when it wakes - here a fix that had run P30_GIVE_UP_S, which the raider would
## otherwise give up the moment it woke.
func test_a_raider_that_slept_goes_back_to_its_house() -> void:
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"prop_tags": ["house"], "aggro_player_m": 12.0}})
	var house := spawn_fence(Vector3(0, 0, -5), "test.house")
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", true)   # facing the house
	spawn_player(Vector3(0, 0.05, 40), PI)
	await step_ticks(2)
	assert_eq(raider._target(), house.entity, "the giant far away: the raider takes the house")
	raider._p30_fix_tick = Sim.tick - int(EnemyActor.P30_GIVE_UP_S * Sim.TICK_RATE)
	raider.set_lod_tier(2)
	await step_ticks(int((EnemyActor.P30_FIX_GAP_S + 0.5) * Sim.TICK_RATE))
	var woke := Sim.tick
	raider.set_lod_tier(0)
	await step_ticks(13)   # a perception
	assert_eq(raider._target(), house.entity, "awake again it takes the house again: the sleep started the count again")
	assert_false(raider._p30_given_up.has("test.house"), "not given up (%s)" % raider._p30_given_up)
	assert_true(raider._p30_fix_tick >= woke, "its count started when it woke (%d, woke %d)" % [raider._p30_fix_tick, woke])


## W23 fix-up: the give-up count runs only while the provider keeps picking the house. Nothing of its targets
## in sight for longer than P30_FIX_GAP_S starts it again, as the giant in between does however short his
## visit; a shorter blink with nothing in sight (a sight line passing a post) does not, so a target the raider
## keeps losing and finding is still given up after P30_GIVE_UP_S. Each step starts from a fix aged to just
## under or at P30_GIVE_UP_S. The raider's brain is off: the test senses for it at the brain's rate (5 Hz).
func test_the_give_up_count_runs_only_while_the_provider_keeps_picking_the_target() -> void:
	TestFixtures.record_override("enemy.soldier", {"targets": {"teams": ["player"], "factions": ["faction.village"],
		"prop_tags": ["house"], "aggro_player_m": 12.0}})
	var house := spawn_fence(Vector3(0, 0, -5), "test.house")
	house.set_meta(&"prop_tags", PackedStringArray(["house"]))
	var raider := spawn_soldier(Vector3(0, 0.05, -2.2), 0.0, "test.raider", false)
	var p := spawn_player(Vector3(0, 0.05, 60), PI)
	await step_ticks(2)
	assert_eq(raider._target(), house.entity, "the raider takes the house")
	var give_up := int(EnemyActor.P30_GIVE_UP_S * Sim.TICK_RATE)
	# the house out of sight (beyond the raider's 25 m) for longer than P30_FIX_GAP_S
	raider._p30_fix_tick = Sim.tick - give_up
	house.global_position = Vector3(0, 0, -60)
	var seen := false
	for i in int((EnemyActor.P30_FIX_GAP_S + 0.5) * Sim.TICK_RATE / 12.0):
		await step_ticks(12)
		seen = seen or raider._target() != null
	assert_false(seen, "the house away, nothing in sight")
	house.global_position = Vector3(0, 0, -5)
	var back := Sim.tick
	await step_ticks(1)
	assert_eq(raider._target(), house.entity, "back in sight it takes the house again: the spell started the count again")
	assert_false(raider._p30_given_up.has("test.house"), "not given up (%s)" % raider._p30_given_up)
	assert_true(raider._p30_fix_tick >= back, "its count started when it saw the house again")
	# the giant within aggro_player_m and in sight for half a second, then gone
	raider._p30_fix_tick = Sim.tick - give_up
	p.global_position = Vector3(0, 0.05, -2.2 - 8.0)   # 8 m in front of the raider (it faces -z)
	p.velocity = Vector3.ZERO
	await step_ticks(12)
	assert_eq(raider._target(), p.entity, "the giant comes first")
	await step_ticks(12)
	assert_eq(raider._target(), p.entity, "for half a second")
	p.global_position = Vector3(0, 0.05, 60)
	var gone := Sim.tick
	await step_ticks(1)
	assert_eq(raider._target(), house.entity, "the giant gone, it takes the house again: his visit started the count again")
	assert_false(raider._p30_given_up.has("test.house"), "not given up (%s)" % raider._p30_given_up)
	assert_true(raider._p30_fix_tick >= gone, "its count started when it took the house again")
	# half a second short of P30_GIVE_UP_S, then a blink of one second: the count runs on
	raider._p30_fix_tick = Sim.tick - give_up + 30
	house.global_position = Vector3(0, 0, -60)
	for i in 5:
		await step_ticks(12)
		seen = seen or raider._target() != null
	assert_false(seen, "out of sight for a second")
	house.global_position = Vector3(0, 0, -5)
	await step_ticks(1)
	assert_eq(raider._target(), null, "back in sight after a blink, it gives the house up: the blink did not start the count again")
	assert_true(raider._p30_given_up.has("test.house"), "given up for P30_GIVEN_UP_S")
