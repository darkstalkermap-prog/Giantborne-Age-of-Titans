extends IntegrationSuite
## The wolf's three long simulations (moved here from tests/integration/test_wolf.gd by P53, plan M11 §1.7 rule 2:
## about 1.1 s of the default tier; unchanged): three wolves and two soldiers share the two attack tokens over 10 s,
## an outmatched wolf harasses only from behind for 12 s, and a lunging wolf is punished by the stage-1 light chain
## from three bearings. The default tier keeps the token
## limit (test_world_and_flow_integration.test_attack_tokens_limit_attackers, test_archer's ranged pool) and the
## light chain punishing a lunging wolf at stages 2 and 3 (test_growth).

const WOLF := "res://scenes/enemies/wolf.tscn"


func _wolf(pos: Vector3, id: String, ai := false, yaw := 0.0) -> WolfEnemy:
	return TestSpawn.enemy(world, WOLF, pos, id, ai, yaw) as WolfEnemy


## Facing angle of `actor` around `p` relative to the giant's facing (0 = in front).
func _angle_around(p: GiantPlayer, actor: Node3D) -> float:
	return WolfBrain.angle_from_facing(-p.global_transform.basis.z, actor.global_position - p.global_position)


func test_outmatched_wolf_harasses_from_behind() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	p.set_profile(GameData.get_record("growth.02"))
	p.entity.combatant.set_height(float(GameData.get_record("growth.02").height_m))
	var w := _wolf(Vector3(0.5, 0.05, -9), "test.wolf_harass", true, PI)
	var attack_angles: Array[float] = []
	var retreated := false
	var was_attacking := false
	for i in 720:
		await step_ticks(1)
		var attacking := w.controller.state == CombatController.State.ATTACKING
		if attacking and not was_attacking:
			attack_angles.append(_angle_around(p, w))
		was_attacking = attacking
		if not attack_angles.is_empty() and w.global_position.distance_to(p.global_position) > 8.0:
			retreated = true
	assert_true(w.brain.is_outmatched(), "a stage-2 giant outmatches a wolf (6.1 >= 6.0)")
	assert_true(attack_angles.size() >= 1, "it attacks within 12 s")
	for a in attack_angles:
		assert_true(absf(a) > 100.0, "only from behind (attacked at %.0f degrees)" % a)
	assert_true(retreated, "and backs off about 8 m after an attack")

func test_three_wolves_and_two_soldiers_share_two_tokens() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	var actors: Array[EnemyActor] = []
	for spec: Array in [[Vector3(-6, 0.05, -6), "test.wolf_1"], [Vector3(6, 0.05, -6), "test.wolf_2"],
			[Vector3(0, 0.05, 8), "test.wolf_3"]]:
		actors.append(_wolf(spec[0], spec[1], true, yaw_towards(spec[0], Vector3.ZERO)))
	for spec: Array in [[Vector3(-7, 0.05, 3), "test.soldier_1"], [Vector3(7, 0.05, 3), "test.soldier_2"]]:
		actors.append(spawn_soldier(spec[0], yaw_towards(spec[0], Vector3.ZERO), spec[1], true))
	var most := 0
	var holders_seen := {}
	for i in 600:
		await step_ticks(1)
		var holders := Sim.token_holders("player")
		most = maxi(most, holders.size())
		for h: String in holders:
			holders_seen[h] = true
	assert_true(most <= 2, "never more than two attackers at once (spec 10; most %d)" % most)
	assert_eq(most, 2, "and the pool is used")
	assert_true(holders_seen.size() >= 3, "the tokens change hands (%s)" % ", ".join(PackedStringArray(holders_seen.keys())))
	var wolf_attacks := 0
	for s: String in started:
		if s.begins_with("test.wolf_"):
			wolf_attacks += 1
	assert_true(wolf_attacks >= 2, "the wolves attack (%d)" % wolf_attacks)


# --------------------------------------------------------------------------- M2 gate: punishing a wolf

## Where a lunge that reaches a stage-1 giant stops (its approach_stop_m capsule gap): about
## 1.3 m from the giant's centre.
const LUNGE_STOP_M := 1.3
## Straight ahead and 15 degrees to either side of the giant's facing (+ = right).
const BEARINGS_DEG := [-15.0, 0.0, 15.0]


func _bearing_point(bearing_deg: float, d: float) -> Vector3:
	var t := deg_to_rad(bearing_deg)
	return Vector3(d * sin(t), 0.05, -d * cos(t))


func _side(bearing_deg: float) -> String:
	if is_zero_approx(bearing_deg):
		return "straight ahead"
	return "%.0f degrees to the %s" % [absf(bearing_deg), "right" if bearing_deg > 0.0 else "left"]


## "Dodge then punish", without the dodge: a wolf that lunges at a stage-1 giant stops at its
## feet. The light chain started in the wolf's 0.9 s recovery lands its first two blows inside
## that window and all three connect, whether the wolf came from straight ahead or 15 degrees to
## either side.
func test_a_wolf_that_lunged_is_punished_by_the_light_chain() -> void:
	var lunge := GameData.get_action("ability.wolf_lunge")
	var n := 0
	for bearing: float in BEARINGS_DEG:
		n += 1
		var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
		p.entity.combatant.unkillable = true
		var pos := _bearing_point(bearing, 4.0)
		var id := "test.wolf_punished_%d" % n
		var w := _wolf(pos, id, false, yaw_towards(pos, Vector3.ZERO))
		w.entity.combatant.unkillable = true
		await step_ticks(3)
		w.brain.target_id = "player"
		w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
		var recovering: bool = await TestWait.until(self, func() -> bool:
			return w.controller.phase() == ActionDef.Phase.RECOVERY, lunge.windup_ticks + lunge.active_ticks + 5)
		assert_true(recovering, "the lunge from %s ends in its recovery" % _side(bearing))
		var stop := Vector2(w.global_position.x - p.global_position.x, w.global_position.z - p.global_position.z).length()
		assert_true(stop < LUNGE_STOP_M + 0.15, "it stopped at the giant's feet (%.2f m)" % stop)
		var window_end := Sim.tick + lunge.recovery_ticks
		for i in 3:
			var light_id := "ability.light_%d" % (i + 1)
			p.router.inject_light_attack()
			var swung: bool = await TestWait.until(self, func() -> bool:
				return p.controller.action != null and p.controller.action.id == light_id \
					and p.controller.phase() == ActionDef.Phase.RECOVERY, 60)
			assert_true(swung, "%s ran (wolf from %s)" % [light_id, _side(bearing)])
		var hit_tick := {}
		for r in hits_on(id):
			hit_tick[r.event.action_id] = r.event.tick
		for light_id: String in ["ability.light_1", "ability.light_2"]:
			assert_true(hit_tick.has(light_id) and int(hit_tick[light_id]) <= window_end,
				"%s lands in the recovery window (wolf from %s; hits %s)" % [light_id, _side(bearing), hit_tick])
		assert_true(hit_tick.has("ability.light_3"), "and the combo's third blow connects (wolf from %s)" % _side(bearing))
		p.queue_free()
		w.queue_free()
		await step_ticks(2)
