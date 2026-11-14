extends IntegrationSuite
## M8 gate (F12; plan M6-M9 §5.10, the siege of Skarn): a siege line's engine (team ENEMY) bombarding the
## NEUTRAL prop of its prop_targets strikes that prop - and only it. A crewed catapult whose stand-in giant
## (a soldier on the giant's team, inside the engine's minimum range: out of its reach) cannot be shot at
## lobs its stones at the fence it bombards; a second fence and a villager stand within the stone's 6 m
## splash (the fences take siege blows here, as Skarn's longhouses do). The bombarded fence loses health;
## the other fence and the villager take no hit (the team rule holds for everything but the shot's own
## prop: ProjectileSystem lifts that one for the shot's sweep and splash, SiegeEngine.p36_shot_target
## names it). Reloads and windups are cut short (TestFixtures).

const CATAPULT := "res://scenes/world/siege_catapult.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const VILLAGER := "res://scenes/npcs/villager.tscn"
const STONE := "ability.catapult_stone"
const TARGET := "test.m8_bombarded"
const OTHER := "test.m8_neighbour"


func test_a_bombarding_engines_stone_strikes_its_prop_and_nothing_else_neutral() -> void:
	TestFixtures.record_override("prop.siege_catapult", {"engine": {"reload_s": 0.4}})
	TestFixtures.record_override(STONE, {"windup_s": 0.1, "recovery_s": 0.05})
	# the fences take siege blows (as Skarn's longhouses do), so only the team rule can spare the other one
	TestFixtures.record_override("prop.fence_wood", {"accepted_attack_categories": ["melee", "ability", "siege"]})
	var target := spawn_fence(Vector3(0, 0, 0), TARGET)
	var other := spawn_fence(Vector3(3.0, 0, 1.5), OTHER, PI * 0.5)
	var villager := (load(VILLAGER) as PackedScene).instantiate() as Civilian
	villager.entity_id = "test.m8_villager"
	villager.ai_enabled = false
	villager.position = Vector3(-2.5, 0.05, 2.0)
	world.add_child(villager)
	# the stand-in giant: inside the catapult's 40 m minimum range, out of its reach
	var giant := spawn_soldier(Vector3(8.0, 0.05, -50.0), 0.0, "test.m8_giant", false)
	giant.entity.team = CombatEntity.Team.PLAYER
	giant.entity.combatant.unkillable = true
	var e := (load(CATAPULT) as PackedScene).instantiate() as SiegeEngine
	e.world_id = "test.m8_catapult"
	e.position = Vector3(0, 0, -50.0)
	e.rotation.y = TargetingRules.yaw_of(Vector3(0, 0, 1))
	e.prop_targets = PackedStringArray([TARGET])
	world.add_child(e)
	var crew := TestSpawn.enemy(world, CREW, e.global_position + Vector3(0, 0.05, 0), "test.m8_crew", false, e.rotation.y)
	e.add_crew(crew)
	crew.global_position = e.crew_slot(crew) + Vector3(0, 0.05, 0)
	await step_ticks(SiegeEngine.CREW_CHECK_TICKS + 2)
	var t := Sim.get_entity(TARGET)
	assert_true(t != null and t.team == CombatEntity.Team.NEUTRAL, "the bombarded fence is a neutral prop")
	assert_false(e.can_reach(giant.entity), "the stand-in giant is out of the engine's reach")
	assert_eq(e.p36_bombard_target(giant.entity), t, "so the engine bombards its prop")
	var before := t.combatant.pools.health if t != null else 0.0
	var struck: bool = await TestWait.until(self, func() -> bool: return not hits_on(TARGET).is_empty(), 60 * 12)
	assert_true(struck, "the engine's stone strikes the prop it bombards (M8 gate, F12)")
	if t != null:
		assert_true(t.combatant.pools.health < before, "and the prop loses health (%.0f -> %.0f)" % [before, t.combatant.pools.health])
	await step_ticks(30)
	assert_true(e.shots >= 1, "the catapult fired (%d shots)" % e.shots)
	assert_eq(hits_on(OTHER).size(), 0, "the other neutral fence in the splash takes no hit")
	assert_eq(hits_on("test.m8_villager").size(), 0, "nor the villager in the splash")
	assert_eq(t.team if t != null else -1, CombatEntity.Team.NEUTRAL, "the bombarded prop is neutral again after the shot")
	assert_true(other.entity.team == CombatEntity.Team.NEUTRAL and villager.entity.team == CombatEntity.Team.NEUTRAL,
		"nothing else changed side")
	e.queue_free()
