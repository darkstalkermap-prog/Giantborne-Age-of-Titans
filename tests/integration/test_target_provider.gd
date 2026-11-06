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
