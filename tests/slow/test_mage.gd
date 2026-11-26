extends IntegrationSuite
## The mage (plan §3.9, §4.4) through real scenes and ticks: its scene and essence from data, the
## slowing bolt (30 % for 3 s; a second one refreshes, strongest wins), a heavy during the windup
## cancels the cast with no hit and no refund, a Runic Bolt fired 0.1 s into the slow bolt's
## windup staggers the mage before release, the barrier picked for the most hurt ally lands on it
## and halves its damage (on the mage itself when that ally died), and a target that dies
## mid-cast leaves no stale hits, tokens or errors [§15].

const MAGE := "res://scenes/enemies/mage.tscn"
const BOLT := "ability.mage_slow_bolt"
const BARRIER := "ability.mage_barrier"

var spawned: Array = []
var applied: Array = []


func before_each() -> void:
	await super()
	spawned.clear()
	applied.clear()
	Events.projectile_spawned.connect(_on_spawned)
	Events.status_applied.connect(_on_status_applied)


func after_each() -> void:
	for sig: Signal in [Events.projectile_spawned, Events.status_applied]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	for n in get_tree().get_nodes_in_group(ProjectileSystem.GROUP):
		n.queue_free()
	await super()


func _on_spawned(t: int, id: int, owner_id: String, action_id: String, _pos: Vector3, _vel: Vector3, _visual: String) -> void:
	spawned.append({"tick": t, "id": id, "owner": owner_id, "action": action_id})


func _on_status_applied(t: int, entity_id: String, status_id: String, source_id: String, duration_s: float) -> void:
	applied.append({"tick": t, "entity": entity_id, "status": status_id, "source": source_id, "duration": duration_s})


func _mage(pos: Vector3, id: String, ai := false, yaw := PI) -> MageEnemy:
	return TestSpawn.enemy(world, MAGE, pos, id, ai, yaw) as MageEnemy


func _player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	p.entity.combatant.unkillable = true
	return p


## Starts a cast of the mage's by hand (its AI off) at the player.
func _cast(m: MageEnemy, id: String) -> int:
	m.brain.target_id = "player"
	return m.controller.request(&"attack", {"action_id": id})


func _launches_by(owner_id: String) -> Array:
	return spawned.filter(func(s: Dictionary) -> bool: return s.owner == owner_id)


# --------------------------------------------------------------------------- scene

func test_mage_scene_and_essence_from_data() -> void:
	var m := _mage(Vector3(0, 0.05, -12), "test.mage_s")
	await step_ticks(2)
	assert_true(m is MageEnemy and m.brain is MageBrain, "MageEnemy with a MageBrain")
	for path in ["CombatEntity", "NavAgent", "Visual/Body", "Visual/LodProxy", "Anchors/Grab", "Hurtboxes/Torso"]:
		assert_true(m.get_node_or_null(path) != null, "has %s" % path)
	assert_true(m.is_in_group("ranged_enemies"), "a ranged enemy")
	var pools := m.entity.combatant.pools
	assert_eq([pools.essence, pools.essence_max], [100.0, 100.0], "essence 100 from its record")
	assert_near(pools.essence_regen_per_s, 6.0, 1e-6, "regenerating 6/s")
	assert_near(m.entity.combatant.resistance("arcane"), 0.3, 1e-6, "arcane resistance 0.3")
	assert_eq(_cast(m, BOLT), CombatController.Verdict.ACCEPT, "the slow bolt is cast")
	assert_eq(m.controller.state, CombatController.State.CASTING, "in CASTING (kind ability)")
	assert_near(pools.essence, 88.0, 1e-6, "for 12 essence")


# --------------------------------------------------------------------------- the slowing bolt

## The bolt slows the giant 30 % for 3 s; a second bolt refreshes it (strongest wins, no stacking).
func test_slow_bolt_slows_for_3_s_and_a_second_refreshes() -> void:
	var p := _player()
	var m := _mage(Vector3(0, 0.05, -12), "test.mage_slow")
	await step_ticks(2)
	_cast(m, BOLT)
	var hit: bool = await TestWait.until(self, func() -> bool: return hits_on("player").size() == 1, 150)
	assert_true(hit, "the bolt hit the giant")
	var statuses := p.entity.combatant.statuses
	assert_true(statuses.has("status.slow"), "slowed")
	assert_near(statuses.magnitude("status.slow"), 0.3, 1e-6, "by 30 %")
	assert_near(p.controller.move_speed_multiplier(), 0.7, 1e-6, "moving at x0.7")
	assert_near(statuses.remaining_s("status.slow", Sim.tick), 3.0, 0.05, "for 3 s")
	var first_hit_tick := Sim.tick
	await TestWait.until(self, func() -> bool: return m.controller.action == null, 90)
	_cast(m, BOLT)
	var second: bool = await TestWait.until(self, func() -> bool: return hits_on("player").size() == 2, 150)
	assert_true(second, "a second bolt hit")
	var since := float(Sim.tick - first_hit_tick) / 60.0
	assert_true(since > 1.0 and since < 3.0, "while the first slow still ran (%.2f s later)" % since)
	assert_near(statuses.remaining_s("status.slow", Sim.tick), 3.0, 0.05, "refreshed to 3 s")
	assert_near(statuses.magnitude("status.slow"), 0.3, 1e-6, "still 30 %: slows never stack")
	assert_near(p.controller.move_speed_multiplier(), 0.7, 1e-6, "still x0.7")
	await step_ticks(182)
	assert_false(statuses.has("status.slow"), "gone 3 s after the second bolt")
	assert_near(p.controller.move_speed_multiplier(), 1.0, 1e-6, "full speed again")


## A heavy landing during the windup hard-staggers the mage (poise 25): no bolt, essence not refunded.
func test_a_heavy_during_the_windup_cancels_the_cast_without_refund() -> void:
	var p := _player()
	var m := _mage(Vector3(0, 0.05, -2.8), "test.mage_h")
	await step_ticks(3)
	_cast(m, BOLT)
	var essence := m.entity.combatant.pools.essence
	assert_near(essence, 88.0, 1e-6, "12 essence spent on the cast")
	p.router.inject_edge(&"heavy")
	var staggered: bool = await TestWait.until(self, func() -> bool:
		return m.controller.state == CombatController.State.STAGGERED, 50)
	assert_true(staggered, "the heavy staggered the mage")
	assert_eq(m.controller.action, null, "its cast was interrupted")
	var on := hits_on("test.mage_h")
	assert_true(on.size() >= 1 and on[0].event.action_id == "ability.heavy_1", "by the heavy")
	assert_true(m.entity.combatant.pools.essence <= essence + 0.2, "no refund (only a tick of regen)")
	await step_ticks(70)
	assert_eq(_launches_by("test.mage_h").size(), 0, "no bolt ever left")
	assert_eq(hits_on("player").size(), 0, "and nothing hit the giant")


## Plan §3.9: a Runic Bolt fired 0.1 s after the slow bolt's windup starts reaches the mage 16 m
## away before its release (0.35 s + 16 m / 35 m/s ~ 0.81 s < 1.0 s) and staggers it (poise 15 x 2).
func test_a_runic_bolt_interrupts_the_slow_bolt_before_release() -> void:
	var p := _player()
	var m := _mage(Vector3(0, 0.05, -16), "test.mage_r")
	await step_ticks(3)
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.mage_r", "locked on the mage")
	_cast(m, BOLT)
	var started := Sim.tick
	await step_ticks(6)
	p.router.inject_edge(&"slot_6")
	await step_ticks(1)
	assert_eq(p.controller.action_id(), "ability.runic_bolt", "Runic Bolt 0.1 s into the mage's windup")
	var staggered: bool = await TestWait.until(self, func() -> bool:
		return m.controller.state == CombatController.State.STAGGERED, 60)
	assert_true(staggered, "the mage was staggered")
	assert_true(Sim.tick - started < GameData.get_action(BOLT).windup_ticks, "before its release (%d ticks)" % (Sim.tick - started))
	await step_ticks(40)
	assert_eq(_launches_by("test.mage_r").size(), 0, "the slow bolt never left")


# --------------------------------------------------------------------------- the barrier

## Its brain picks the most hurt ally within 12 m; the barrier lands on it when the cast enters ACTIVE
## and halves the damage it takes.
func test_barrier_lands_on_the_most_hurt_ally_and_halves_its_damage() -> void:
	var p := _player()
	var hurt := spawn_soldier(Vector3(3, 0.05, -13), PI, "test.ally_hurt")
	var fine := spawn_soldier(Vector3(-3, 0.05, -13), PI, "test.ally_fine")
	var twin := spawn_soldier(Vector3(30, 0.05, -30), PI, "test.ally_twin")   # out of range, for the comparison
	var m := _mage(Vector3(0, 0.05, -15), "test.mage_b", true)
	await step_ticks(2)
	hurt.entity.combatant.pools.health = 100.0
	twin.entity.combatant.pools.health = 100.0
	var warded: bool = await TestWait.until(self, func() -> bool:
		return hurt.entity.combatant.statuses.has("status.barrier"), 240)
	assert_true(warded, "the hurt soldier got the barrier")
	assert_eq(m.brain.ally_target_id, "test.ally_hurt", "the mage picked it")
	assert_false(fine.entity.combatant.statuses.has("status.barrier"), "not the unhurt one")
	assert_false(m.entity.combatant.statuses.has("status.barrier"), "nor the mage")
	var ward: Array = applied.filter(func(a: Dictionary) -> bool: return a.status == "status.barrier")
	assert_eq(ward.size(), 1, "one barrier")
	if ward.size() == 1:
		assert_eq(ward[0].source, "test.mage_b", "from the mage")
		assert_near(float(ward[0].duration), 5.0, 1e-6, "for 5 s")
	assert_near(hurt.entity.combatant.damage_taken_mult(), 0.5, 1e-6, "x0.5 damage taken")
	queue_hit("tester", "test.ally_hurt", hurt.global_position + Vector3(0, 0, 2), 200.0, PackedStringArray())
	queue_hit("tester", "test.ally_twin", twin.global_position + Vector3(0, 0, 2), 200.0, PackedStringArray())
	await step_ticks(1)
	var a := hits_on("test.ally_hurt")
	var b := hits_on("test.ally_twin")
	assert_true(a.size() == 1 and b.size() == 1, "both hit")
	if a.size() == 1 and b.size() == 1:
		assert_true(absi(a[0].health_damage * 2 - b[0].health_damage) <= 1,
			"the barrier halves the damage (%d vs %d)" % [a[0].health_damage, b[0].health_damage])
	assert_true(p != null, "player present")


## An ally that dies during the cast: the barrier goes to the mage itself.
func test_barrier_falls_back_to_the_mage_when_its_ally_died() -> void:
	var p := _player(Vector3(0, 0.05, 0))
	var ally := spawn_soldier(Vector3(3, 0.05, -14), PI, "test.ally_doomed")
	var m := _mage(Vector3(0, 0.05, -15), "test.mage_f")
	await step_ticks(2)
	m.brain.ally_target_id = "test.ally_doomed"
	assert_eq(_cast(m, BARRIER), CombatController.Verdict.ACCEPT, "the barrier is cast")
	assert_near(m.entity.combatant.pools.essence, 70.0, 1e-6, "for 30 essence")
	await step_ticks(20)
	queue_hit("tester", "test.ally_doomed", ally.global_position + Vector3(0, 0, 2), 9999.0, PackedStringArray())
	await step_ticks(2)
	assert_false(ally.entity.is_alive(), "the ally died mid-cast")
	var done: bool = await TestWait.until(self, func() -> bool:
		return m.entity.combatant.statuses.has("status.barrier"), 80)
	assert_true(done, "the barrier landed on the mage instead")
	assert_eq(m.controller.cooldowns.is_ready(BARRIER, Sim.tick), false, "and went on its 10 s cooldown")
	assert_true(p != null, "player present")


## [§15] The target dies during the cast: the bolt still flies (decision 8) but hits no corpse,
## the mage gives up its target and its ranged token, and nothing errors.
func test_target_death_mid_cast_is_handled() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var m := _mage(Vector3(0, 0.05, -12), "test.mage_d", true)
	var engaged: bool = await TestWait.until(self, func() -> bool:
		return m.controller.action != null and m.controller.action.id == BOLT, 300)
	assert_true(engaged, "the mage began a slow bolt at the giant")
	assert_true(m.brain.holds_ranged_token, "holding a ranged token")
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, -2), 99999.0, PackedStringArray())
	await step_ticks(2)
	assert_false(p.entity.is_alive(), "the giant died mid-cast")
	var hits_before := hits_on("player").size()
	await step_ticks(150)
	assert_eq(hits_on("player").size(), hits_before, "no hit lands on the corpse")
	assert_eq(Sim.token_holders(EnemyActor.ranged_token_key("player")).size(), 0, "no ranged token left held")
	assert_false(m.brain.holds_ranged_token, "the brain let it go")
	assert_eq(m.controller.state, CombatController.State.LOCOMOTION, "the mage is free again")
	assert_true(m.brain.state in [EnemyBrain.AIState.PATROL, EnemyBrain.AIState.IDLE], "and stops fighting (%s)" % m.brain.state_name())
