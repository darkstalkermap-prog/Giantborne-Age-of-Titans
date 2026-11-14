extends IntegrationSuite
## P21 (plan M6-M9 §3.3 threat-cue tests, decision 7, §4.1 family F): threats are audible and
## directional, played by the effect banks (audio enabled):
##   * a soldier's chop from behind logs its windup and the sting, both at the soldier
##   * the same chop in view and near logs the windup alone; one in view but far still stings
##   * a chip attack (expected damage under 3 % of the giant's maximum health) logs no sting
##   * an archer's shot logs the aim lock once, at its tracking_fraction of the draw
##   * the sting (priority 100) takes a voice from a pool full of footfalls; lower requests drop

const ARCHER := "res://scenes/enemies/archer.tscn"
const SHOT := "ability.archer_shot"
const CHOP := "ability.soldier_chop"


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


func _logged(cue_id: String) -> Array:
	var out: Array = []
	for e: Dictionary in Audio.cue_log():
		if str(e.cue) == cue_id:
			out.append(e)
	return out


func _telegraph(attacker: EnemyActor, action_id: String, target_id: String, shape := "line") -> void:
	Audio.clock_s += 1.0   # clear of the retrigger guards
	Audio.clear_log()
	Events.telegraph_started.emit(Sim.tick, attacker.entity.entity_id, action_id, target_id, shape,
		attacker.global_position, 0.0, 0.3, 2.5, 0.85)
	await get_tree().process_frame


static func _chest(a: EnemyActor) -> Vector3:
	return a.global_position + Vector3.UP * a.entity.combatant.height_m * 0.6


func test_a_chop_from_behind_logs_the_windup_and_the_sting_at_the_soldier() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	var behind := spawn_soldier(Vector3(0, 0, 12), 0.0, "t.threat_behind")
	await step_ticks(3)
	await _telegraph(behind, CHOP, p.entity.entity_id)
	var windup := _logged("sfx.threat.windup.line")
	var sting := _logged("sfx.threat.sting")
	assert_eq(windup.size(), 1, "the windup plays: %s" % [Audio.logged_cues()])
	assert_eq(sting.size(), 1, "and the sting: the soldier is behind the camera")
	for e: Dictionary in windup + sting:
		assert_true((e.pos as Vector3).distance_to(_chest(behind)) < 0.5, "%s at the soldier (%s)" % [e.cue, e.pos])
		assert_eq(str(Audio.resolve(str(e.cue)).bank), "audio_bank.threat", "%s from the threat bank" % e.cue)
		assert_eq(str(e.bus), "SFX", "%s on the SFX bus" % e.cue)
	if sting.size() == 1:
		assert_eq(int(sting[0].priority), 100, "the sting at priority 100")
		var node := Audio.pool.voice_node(int(sting[0].voice))
		assert_true(node is AudioStreamPlayer3D, "a positional voice (directional)")
		if node is AudioStreamPlayer3D:
			# M6 gate: the sting is a threat alert - the alert class (scaled like far_m, a level floor)
			var d := Audio.class_distances("alert")
			assert_near((node as AudioStreamPlayer3D).unit_size, float(d.unit), 1e-4, "the alert class's unit size")
			assert_near((node as AudioStreamPlayer3D).max_distance, float(d.max), 1e-4, "and its range")
	if windup.size() == 1:
		assert_eq(int(windup[0].priority), 80, "a windup within 15 m takes priority 80")


func test_a_chop_in_view_and_near_has_no_sting_but_a_far_one_has() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	var front := spawn_soldier(Vector3(0, 0, -10), PI, "t.threat_front")
	var far_front := spawn_soldier(Vector3(0, 0, -26), PI, "t.threat_far")
	await step_ticks(3)
	await _telegraph(front, CHOP, p.entity.entity_id)
	assert_eq(_logged("sfx.threat.windup.line").size(), 1, "the windup in view")
	assert_eq(_logged("sfx.threat.sting").size(), 0, "no sting for a threat in view and near")
	await _telegraph(far_front, CHOP, p.entity.entity_id)
	assert_eq(_logged("sfx.threat.windup.line").size(), 1, "the far windup")
	assert_eq(_logged("sfx.threat.sting").size(), 1, "a threat beyond 20 m stings even in view")
	if _logged("sfx.threat.windup.line").size() == 1:
		assert_eq(int(_logged("sfx.threat.windup.line")[0].priority), 70, "beyond 15 m the windup takes priority 70")
	await _telegraph(front, CHOP, "someone_else")
	assert_eq(_logged("sfx.threat.windup.line").size() + _logged("sfx.threat.sting").size(), 0,
		"a telegraph aimed at someone else is no threat to the giant")


## M6 gate: the far sting fired where it was quietest - at 20 m (the far threshold at stage 1) the
## threat class took 21 dB off it, 22 dB under the combat layer. The alerts now carry: wherever the
## attacker stands within the alert class's range, the sting reaches the listener at its own level
## (the class's floor), still panned toward the attacker, and the windup beside it keeps the threat
## class's distance falloff.
func test_a_far_stings_level_at_the_listener_holds_at_its_floor() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	var far_m := float(((Audio.mix.get("threat", {}) as Dictionary)).get("far_m", 20.0))
	var at_threshold := spawn_soldier(Vector3(0, 0, -(far_m + 2.0)), PI, "t.threat_threshold")
	var farther := spawn_soldier(Vector3(0, 0, -3.0 * far_m), PI, "t.threat_farther")
	await step_ticks(3)
	var floor_db := Audio.class_floor_db("alert")
	assert_false(is_nan(floor_db), "the alert class has a level floor")
	var sting_volume := float(Audio.resolve("sfx.threat.sting").get("volume_db", 0.0))
	for attacker: SoldierEnemy in [at_threshold, farther]:
		await _telegraph(attacker, CHOP, p.entity.entity_id)
		var sting := _logged("sfx.threat.sting")
		assert_eq(sting.size(), 1, "a sting for the chop %.0f m away (in view, beyond far_m)" % attacker.global_position.length())
		if sting.size() != 1:
			continue
		var node := Audio.pool.voice_node(int(sting[0].voice)) as AudioStreamPlayer3D
		assert_true(node != null, "on a positional voice")
		if node == null:
			continue
		var d := Audio.listener_position().distance_to(node.global_position)
		var level := AudioMath.level_at(d, node.unit_size, node.max_distance, node.volume_db)
		var reachable := minf(sting_volume + floor_db,
			AudioMath.MAX_DB + 20.0 * log(1.0 - d / node.max_distance) / log(10.0))
		assert_true(level >= reachable - 0.05,
			"the sting %.0f m away reaches the listener at %.1f dB (its floor: %.1f dB)" % [d, level, reachable])
		var threat := Audio.class_distances("threat")
		var unfloored := AudioMath.level_at(d, float(threat.unit), float(threat.max), sting_volume)
		assert_true(level - unfloored >= 15.0,
			"%.0f dB louder than the threat class left it (%.1f dB)" % [level - unfloored, unfloored])
		var windup := _logged("sfx.threat.windup.line")
		if windup.size() == 1:
			var wnode := Audio.pool.voice_node(int(windup[0].voice)) as AudioStreamPlayer3D
			assert_near(wnode.volume_db, float(Audio.resolve("sfx.threat.windup.line").get("volume_db", 0.0)), 1e-4,
				"the windup keeps its own volume (the threat class falls off with distance)")


func test_the_aim_lock_carries_like_the_sting() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	Audio.clock_s += 1.0
	Audio.clear_log()
	var floor_db := Audio.class_floor_db("alert")
	var volume := float(Audio.resolve("sfx.threat.aim_lock").get("volume_db", 0.0))
	var src := p.global_position + Vector3(0, 1.5, -45.0)
	var v := Audio.play("sfx.threat.aim_lock", src, {"priority": 100, "reason": "aim_lock"})
	assert_true(v >= 0, "the aim lock of an archer 45 m off plays")
	var node := Audio.pool.voice_node(v) as AudioStreamPlayer3D
	assert_true(node != null, "positionally")
	if node == null:
		return
	var d := Audio.listener_position().distance_to(src)
	var level := AudioMath.level_at(d, node.unit_size, node.max_distance, node.volume_db)
	assert_true(level >= volume + floor_db - 3.0,
		"it reaches the listener at %.1f dB (its own level %.1f, floor %.1f)" % [level, volume, floor_db])


func test_a_chip_attack_from_behind_has_no_sting() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	var behind := spawn_soldier(Vector3(0, 0, 12), 0.0, "t.threat_chip")
	await step_ticks(3)
	var max_hp := float(p.entity.combatant.pools.health_max)
	var chip := ""
	for id: String in ["ability.sparring_swing", "ability.mage_staff", "ability.archer_kick", "ability.wolf_bite"]:
		var dmg := AudioMath.expected_damage(GameData.get_action(id), behind.entity.combatant, behind.weapon, p.entity.combatant)
		if dmg < 0.03 * max_hp:
			chip = id
			break
	assert_true(chip != "", "an attack worth less than 3 %% of %d health exists" % int(max_hp))
	if chip == "":
		return
	var before := int(Audio.stats.suppressed)
	await _telegraph(behind, chip, p.entity.entity_id, "circle")
	assert_eq(_logged("sfx.threat.windup.circle").size(), 1, "the chip's windup still plays")
	assert_eq(_logged("sfx.threat.sting").size(), 0, "but no sting (%s)" % chip)
	assert_eq(int(Audio.stats.suppressed), before + 1, "the sting was suppressed, not lost")
	await _telegraph(behind, CHOP, p.entity.entity_id)
	assert_eq(_logged("sfx.threat.sting").size(), 1, "a real chop from the same place stings")


func test_an_archers_shot_logs_the_aim_lock_at_its_commit() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.entity.combatant.unkillable = true
	var a := TestSpawn.enemy(world, ARCHER, Vector3(0, 0.05, -16), "t.threat_archer", false, PI) as ArcherEnemy
	await step_ticks(2)
	Audio.clock_s += 1.0
	Audio.clear_log()
	var shot := GameData.get_action(SHOT)
	var lock_tick := EnemyActor.aim_lock_tick(shot)
	a.brain.target_id = p.entity.entity_id
	a.controller.request(&"attack", {"action_id": SHOT})
	var heard_at := -1
	for i in shot.windup_ticks + 10:
		await step_ticks(1)
		if heard_at < 0 and not _logged("sfx.threat.aim_lock").is_empty():
			heard_at = a.controller.elapsed if a.controller.action != null else shot.windup_ticks
	assert_true(heard_at >= 0, "the aim lock is heard: %s" % [Audio.logged_cues()])
	assert_true(heard_at >= lock_tick and heard_at <= lock_tick + 2,
		"at the commit (%d ticks into the draw, lock at %d = tracking_fraction %.2f)" % [heard_at, lock_tick, shot.tracking_fraction])
	var locks := _logged("sfx.threat.aim_lock")
	assert_eq(locks.size(), 1, "once per shot")
	if locks.size() == 1:
		assert_true((locks[0].pos as Vector3).distance_to(_chest(a)) < 0.5, "at the archer")
		assert_eq(int(locks[0].priority), 100, "at priority 100")
	assert_true(_logged("sfx.ability.archer_shot.cast").size() + _logged("sfx.projectile.arrow.launch").size() >= 1,
		"the release twangs and the arrow flies")


func test_the_sting_steals_a_voice_from_a_pool_full_of_footfalls() -> void:
	var p := spawn_player(Vector3.ZERO, 0.0)
	await step_ticks(2)
	var pool := Audio.pool
	var near := p.global_position + Vector3(1.5, 0, 0)
	var steps := ["sfx.step.human.soft", "sfx.step.human.hard", "sfx.step.human.wet", "sfx.step.paw.soft",
		"sfx.step.paw.hard", "sfx.step.paw"]
	var started := 0
	for cue: String in steps:
		for i in 6:
			Audio.clock_s += 0.05
			pool.begin_frame()
			if Audio.play(cue, near, {"priority": 40, "reason": "test"}) >= 0:
				started += 1
	assert_eq(pool.busy_count(VoicePool.Kind.VOICE_3D), pool.size_of(VoicePool.Kind.VOICE_3D),
		"footfalls fill every 3D voice (%d started)" % started)
	pool.begin_frame()
	var stolen_before := pool.stolen
	var v := Audio.play("sfx.threat.sting", p.global_position + Vector3(0, 0, 12),
		{"priority": 100, "reason": "sting", "expected_damage": 100.0, "max_health": 500.0, "poise_ratio": 1.0})
	assert_true(v >= 0, "the sting plays")
	assert_eq(pool.stolen, stolen_before + 1, "it took a footfall's voice")
	assert_eq(pool.voice_cue(v), "sfx.threat.sting", "and plays on it")
	pool.begin_frame()
	Audio.clock_s += 0.05
	assert_eq(Audio.play("sfx.step.human.soft", near, {"priority": 30, "reason": "test"}), -1,
		"a lower-priority footfall finds no voice to take")
