extends IntegrationSuite
## The wolf (plan §3.4, §4.4): data floors, the scene, the lunge (committed motion: at most 5 m,
## stops at a wall), its telegraph, the shared two-token pool with soldiers, flanking, pack
## target switching, and harassing from behind when outmatched.

const WOLF := "res://scenes/enemies/wolf.tscn"


func _wolf(pos: Vector3, id: String, ai := false, yaw := 0.0) -> WolfEnemy:
	return TestSpawn.enemy(world, WOLF, pos, id, ai, yaw) as WolfEnemy


## Facing angle of `actor` around `p` relative to the giant's facing (0 = in front).
func _angle_around(p: GiantPlayer, actor: Node3D) -> float:
	return WolfBrain.angle_from_facing(-p.global_transform.basis.z, actor.global_position - p.global_position)


func test_wolf_data_floors() -> void:
	var wolf: Dictionary = GameData.get_record("enemy.wolf")
	assert_eq(str(wolf.get("archetype")), "wolf", "archetype")
	assert_near(float(wolf.height_m), 0.9, 1e-6, "0.9 m tall")
	assert_near(float(wolf.threat), 0.4, 1e-6, "threat 0.4")
	assert_true(bool(wolf.grants_fury), "grants fury")
	assert_eq(int(wolf.nav_layers), 1, "human nav layer")
	assert_eq(str(wolf.scene), WOLF, "spawns from the wolf scene")
	assert_eq(str((wolf.tactics as Dictionary).outmatched_behavior), "harass", "outmatched -> harass")
	for id: String in wolf.attacks:
		var a := GameData.get_action(id)
		assert_true(a.windup_ticks >= ActionDef.seconds_to_ticks(0.45), "%s windup >= 0.45 s" % id)
	var lunge := GameData.get_action("ability.wolf_lunge")
	assert_true(lunge.recovery_ticks >= ActionDef.seconds_to_ticks(0.8), "lunge recovery >= 0.8 s (the punish window)")
	var motion: Dictionary = lunge.param("motion")
	assert_eq(str(motion.phase), "active", "the dash runs in the active phase")
	assert_near(float(motion.speed_mps), 9.0, 1e-6, "dash 9 m/s")
	assert_true(float(motion.max_distance_m) <= 5.0, "at most 5 m")
	assert_eq(str((lunge.param("telegraph") as Dictionary).shape), "line", "line telegraph")
	assert_eq(str(GameData.get_action("ability.soldier_chop").param("telegraph").shape), "line", "the soldier chop is telegraphed")
	assert_near(float(GameData.get_action("ability.soldier_chop").param("telegraph").length_m), 2.5, 1e-6, "a 2.5 m line")
	assert_eq(GameData.call("_untelegraphed_enemy_attacks"), PackedStringArray(),
		"every shipped enemy attack with a windup >= 0.8 s has a telegraph (decision 25)")


func test_wolf_scene_and_classes() -> void:
	var w := _wolf(Vector3(0, 0.05, -5), "test.wolf_a")
	await step_ticks(2)
	assert_true(w is WolfEnemy and w is EnemyActor, "WolfEnemy extends EnemyActor")
	assert_true(w.brain is WolfBrain, "with a WolfBrain")
	assert_true(w.quad is QuadrupedRig, "and a QuadrupedRig")
	assert_eq(w.entity_id, "test.wolf_a", "entity id")
	assert_eq(w.collision_mask, SceneKit.ACTOR_MASK, "collides with the blockers layer")
	assert_eq(w.agent.navigation_layers, 1, "nav layer from the record")
	assert_eq(w.entity.team, CombatEntity.Team.ENEMY, "hostile")
	for key in ["state", "action", "phase", "phase_fraction", "speed", "dead", "staggered", "dodging",
			"guarding", "lunging"]:
		assert_true(w.get_rig_state().has(key), "rig state has '%s'" % key)
	assert_false(w.is_guarding(), "wolves never guard")


func test_lunge_is_capped_at_5m() -> void:
	# A longer active phase would dash 9 m: the motion stops at max_distance_m.
	TestFixtures.record_override("ability.wolf_lunge", {"active_s": 1.0})
	var w := _wolf(Vector3(0, 0.05, 10), "test.wolf_cap")
	await step_ticks(3)
	var start := w.global_position
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	var max_moved := 0.0
	for i in 140:
		await step_ticks(1)
		var d := Vector2(w.global_position.x - start.x, w.global_position.z - start.z)
		max_moved = maxf(max_moved, d.length())
		assert_true(absf(d.x) < 0.05, "the dash keeps the committed direction")
	assert_true(max_moved > 4.6, "the dash covers most of its 5 m (%.2f m)" % max_moved)
	assert_true(max_moved <= 5.05, "never more than 5 m (%.2f m)" % max_moved)
	assert_eq(w.motion_end_reason, "distance", "it ended on its distance cap")
	assert_true(w.global_position.z < start.z - 4.6, "forward along its facing (-Z)")


func test_shipped_lunge_dashes_forward_then_recovers() -> void:
	var w := _wolf(Vector3(0, 0.05, 10), "test.wolf_dash")
	await step_ticks(3)
	var start := w.global_position
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	var lunge := GameData.get_action("ability.wolf_lunge")
	await step_ticks(lunge.windup_ticks - 2)
	assert_true(w.global_position.distance_to(start) < 0.05, "no movement during the windup (the dodge window)")
	await step_ticks(lunge.active_ticks + 4)
	var moved := Vector2(w.global_position.x - start.x, w.global_position.z - start.z).length()
	assert_true(moved > 3.0 and moved <= 5.0, "the dash moved %.2f m (9 m/s for the active phase)" % moved)
	var after_dash := w.global_position
	await step_ticks(20)
	assert_true(w.global_position.distance_to(after_dash) < 0.2, "it stands still in its recovery")
	assert_eq(w.controller.phase(), ActionDef.Phase.RECOVERY, "still recovering: the punish window")


func test_lunge_stops_at_a_wall() -> void:
	add_box(Vector3(6, 3, 0.6), Vector3(0, 1.5, 7.5))   # a wall 2.5 m ahead of the wolf
	var w := _wolf(Vector3(0, 0.05, 10), "test.wolf_wall")
	await step_ticks(3)
	var start := w.global_position
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	var ok: bool = await TestWait.until(self, func() -> bool: return w.motion_end_reason != "", 120)
	assert_true(ok, "the dash ended")
	assert_eq(w.motion_end_reason, "wall", "it ended against the wall")
	var moved := start.z - w.global_position.z
	assert_true(moved < 2.5 and moved > 0.8, "it stopped at the wall (moved %.2f m)" % moved)
	await step_ticks(10)
	assert_true(w.global_position.z > 7.8, "and stays on its side of the wall (z=%.2f)" % w.global_position.z)


func test_lunge_announces_a_line_telegraph() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	var w := _wolf(Vector3(0, 0.05, -6), "test.wolf_tele", false, PI)
	var got: Array = []
	var cb := func(t: int, actor: String, action_id: String, target: String, shape: String, origin: Vector3,
			yaw: float, radius: float, length: float, duration: float) -> void:
		got.append([t, actor, action_id, target, shape, origin, yaw, radius, length, duration])
	Events.telegraph_started.connect(cb)
	await step_ticks(2)
	w.brain.target_id = "player"
	w.controller.request(&"attack", {"action_id": "ability.wolf_lunge"})
	await step_ticks(2)
	w.controller.request(&"attack", {"action_id": "ability.wolf_bite"})   # busy: never starts
	Events.telegraph_started.disconnect(cb)
	assert_eq(got.size(), 1, "one telegraph, on the windup")
	if got.size() == 1:
		var e: Array = got[0]
		assert_eq(e[1], "test.wolf_tele", "from the wolf")
		assert_eq(e[2], "ability.wolf_lunge", "for the lunge")
		assert_eq(e[3], "player", "aimed at the brain's target")
		assert_eq(e[4], "line", "a line")
		assert_true((e[5] as Vector3).distance_to(w.global_position) < 0.1, "from the wolf's feet")
		assert_near(float(e[7]), 0.5, 1e-6, "half the 1 m width")
		assert_near(float(e[8]), 5.0, 1e-6, "as long as the dash can reach")
		assert_near(float(e[9]), 0.6, 1e-6, "lasting the 0.6 s windup")
	assert_true(p != null, "player present")


func test_soldier_chop_announces_its_telegraph() -> void:
	var s := spawn_soldier(Vector3(0, 0.05, -4), PI)
	var got: Array = []
	var cb := func(_t: int, _actor: String, action_id: String, _target: String, shape: String, _origin: Vector3,
			_yaw: float, _radius: float, length: float, duration: float) -> void:
		got.append([action_id, shape, length, duration])
	Events.telegraph_started.connect(cb)
	await step_ticks(2)
	s.controller.request(&"attack", {"action_id": "ability.soldier_slash"})
	await step_ticks(90)
	s.controller.request(&"attack", {"action_id": "ability.soldier_chop"})
	await step_ticks(2)
	Events.telegraph_started.disconnect(cb)
	assert_eq(got.size(), 1, "only the 0.85 s chop is telegraphed (the 0.55 s slash is not)")
	if got.size() == 1:
		assert_eq(got[0], ["ability.soldier_chop", "line", 2.5, 51.0 / 60.0], "a 2.5 m line over the windup")


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


func test_wolf_flanks_beyond_60_degrees_within_6_s() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)   # faces -Z
	p.entity.combatant.unkillable = true
	var w := _wolf(Vector3(0.5, 0.05, -9), "test.wolf_flank", true, PI)   # faces the giant
	var reached_at := -1
	var start := Sim.tick
	for i in 360:
		await step_ticks(1)
		if absf(_angle_around(p, w)) > 60.0:
			reached_at = Sim.tick - start
			break
	assert_true(reached_at >= 0, "the wolf works round to more than 60 degrees off the giant's facing (%.0f)" % _angle_around(p, w))
	assert_true(reached_at <= 360, "within 6 s (%d ticks)" % reached_at)


func test_pack_target_switching_debounce_and_walls() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_wolf(Vector3(-4, 0.05, -9), "test.wolf_l")
	_wolf(Vector3(0, 0.05, -10), "test.wolf_c")
	_wolf(Vector3(4, 0.05, -9), "test.wolf_r")
	_wolf(Vector3(10, 0.05, -9), "test.wolf_hidden")
	add_box(Vector3(0.8, 6, 10), Vector3(7.5, 3, -8))   # hides the far-right wolf from the giant's eye
	await step_ticks(3)
	assert_false(p.targeting.is_visible(Sim.get_entity("test.wolf_hidden")), "the far-right wolf is behind the wall")
	p.router.inject_edge(&"lock_press")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_c", "locks the wolf straight ahead")
	p.router.inject_edge(&"target_right")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_r", "switches right")
	p.router.inject_edge(&"target_left")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_r", "a second switch inside 0.20 s is ignored (debounce)")
	await step_ticks(12)
	p.router.inject_edge(&"target_right")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_r", "never switches to the wolf hidden behind the wall")
	await step_ticks(12)
	p.router.inject_edge(&"target_left")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_c", "after the debounce: back to the middle")
	await step_ticks(12)
	p.router.inject_edge(&"target_left")
	await step_ticks(1)
	assert_eq(p.lock.target_id, "test.wolf_l", "and on to the left wolf")
	var switched := 0
	for e: Array in lock_events:
		if e[3] == "switched":
			switched += 1
	assert_eq(switched, 3, "exactly three switches happened")


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


## Every stage-1 light and the heavy, each started on its own from the same stance, lands on a
## 0.9 m wolf standing where a lunge stops and at 0.6 x the stage-1 melee reach (2.1 m), on both
## sides of the giant's facing. (The M1 arcs swept over a wolf there: light 2 never landed.)
func test_stage_1_attacks_reach_a_wolf_on_both_sides() -> void:
	var reach := float(GameData.get_record("growth.01").melee_reach_m)
	var n := 0
	for attack_id: String in ["ability.light_1", "ability.light_2", "ability.light_3", "ability.heavy_1"]:
		var a := GameData.get_action(attack_id)
		for d: float in [LUNGE_STOP_M, 0.6 * reach]:
			for bearing: float in BEARINGS_DEG:
				n += 1
				var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
				var pos := _bearing_point(bearing, d)
				var id := "test.wolf_reach_%d" % n
				var w := _wolf(pos, id, false, yaw_towards(pos, Vector3.ZERO))
				w.entity.combatant.unkillable = true
				await step_ticks(3)
				assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT,
					"%s starts" % attack_id)
				await step_ticks(a.windup_ticks + a.active_ticks + 2)
				var landed := 0
				for r in hits_on(id):
					if r.event.action_id == attack_id:
						landed += 1
				assert_eq(landed, 1, "%s lands on a wolf %.1f m away, %s" % [attack_id, d, _side(bearing)])
				p.queue_free()
				w.queue_free()
				await step_ticks(2)


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
