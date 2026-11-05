extends IntegrationSuite
## P17b: the swing's vertical aim (PlayerAttack, the balance pass). P17a measured that the light
## chain landed well short of melee_reach_m against a soldier (about 3.3 / 4.0 / 3.5 m by stage):
## each stage tilts its arcs down to reach the giant's feet, and a fixed tilt cannot also reach a
## man standing farther off, so stages 2 and 3 did not feel their reach and a stage-2 giant could
## not strike a holding soldier from beyond its brace. A swing at a target (the lock, else the soft
## target) now takes the smallest lift from the stage's tilt that reaches it:
##   * a locked soldier at about the §4.8 reach is hit by every light: 3.5 m at stage 1, 5 m at
##     stage 2 (beyond the brace counter's 4.2 m; the overhead third blow 4.6 m), 6.5 m at stage 3
##     with a reforged club;
##   * a soft target (no lock) in front at 5 m at stage 2 is hit too;
##   * a wolf at a stage-2 giant's feet takes the default tilt (nothing changes up close);
##   * the rig draws the swing's aimed tilt, and the tilt goes back to the default after the swing;
##   * no target, no aim: the default tilt.

const WOLF := "res://scenes/enemies/wolf.tscn"


func _grounded_player(stage: int, weapon := "") -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	p.entity.combatant.unkillable = true
	if weapon != "":
		assert_true(bool(p.equipment.grant_weapon(weapon, true).ok), "equipped %s" % weapon)
	if stage > 1:
		var r: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(r.ok, "grew to stage %d (%s)" % [stage, r.reason])
	await step_ticks(2)
	return p


func _soldier(d: float, id: String) -> SoldierEnemy:
	var s := spawn_soldier(Vector3(0, 0.05, -d), 0.0, id)
	s.entity.combatant.unkillable = true
	return s


func _lock(p: GiantPlayer, target_id: String) -> void:
	p.camera_rig.yaw = 0.0
	p.router.inject_edge(&"lock_press")
	await TestWait.until(self, func() -> bool: return p.lock.target_id == target_id, 30)
	assert_eq(p.lock.target_id, target_id, "locked on %s" % target_id)


## Starts `attack_id` and returns [hits it landed on target_id, the tilt the rig drew mid-swing].
func _swing(p: GiantPlayer, attack_id: String, target_id: String) -> Array:
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	var a := GameData.get_action(attack_id)
	assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT,
		"%s starts" % attack_id)
	await step_ticks(a.windup_ticks + 2)
	var drawn := float(p.get_rig_state().get("arc_pitch_offset_deg", NAN))
	await step_ticks(a.active_ticks + 1)
	var n := 0
	for r in hits_on(target_id):
		if r.event.action_id == attack_id:
			n += 1
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	await step_ticks(1)
	return [n, drawn]


## [stage, weapon, distance for lights 1 and 2, for light 3] (light 3 is an overhead chop down the
## right side: at stage 2 it reaches about 4.7 m).
const REACH_CASES := [[1, "", 3.5, 3.5], [2, "", 5.0, 4.6], [3, "weapon.club_reinforced", 6.5, 6.5]]


func test_a_locked_soldier_at_the_reach_is_hit_by_every_light() -> void:
	var n := 0
	for c: Array in REACH_CASES:
		var stage: int = c[0]
		var p := await _grounded_player(stage, str(c[1]))
		for attack_id: String in ["ability.light_1", "ability.light_2", "ability.light_3"]:
			var d: float = c[3] if attack_id == "ability.light_3" else c[2]
			n += 1
			var id := "test.aim_soldier_%d" % n
			var s := _soldier(d, id)
			await step_ticks(2)
			await _lock(p, id)
			var default := PlayerAttack.offset_for(p.profile, attack_id)
			var got: Array = await _swing(p, attack_id, id)
			assert_eq(got[0], 1, "stage %d: %s lands on a locked soldier %.1f m away" % [stage, attack_id, d])
			assert_true(float(got[1]) > default, "stage %d: %s tilted up for it (%.0f, default %.0f)" % [
				stage, attack_id, got[1], default])
			assert_true(float(got[1]) <= PlayerAttack.AIM_MAX_OFFSET_DEG + 1e-4, "within the aim's limit")
			assert_near(p.attack.arc_pitch_offset_for(GameData.get_action(attack_id)), default, 1e-6,
				"stage %d: the default tilt again after the swing" % stage)
			p.router.inject_edge(&"lock_press")   # release
			s.queue_free()
			await step_ticks(2)
		p.queue_free()
		await step_ticks(2)


func test_a_soft_target_in_front_is_aimed_at_without_a_lock() -> void:
	var p := await _grounded_player(2)
	var s := _soldier(5.0, "test.aim_soft")
	await step_ticks(2)
	assert_true(p.lock.target_id == "", "nothing locked")
	var got: Array = await _swing(p, "ability.light_1", "test.aim_soft")
	assert_eq(got[0], 1, "the light lands on a soldier 5 m in front (soft target)")
	assert_true(float(got[1]) > PlayerAttack.offset_for(p.profile, "ability.light_1"), "tilted up (%.0f)" % got[1])
	s.queue_free()


func test_a_wolf_at_the_feet_keeps_the_default_tilt() -> void:
	var p := await _grounded_player(2)
	var d := float(p.profile.capsule_radius_m) + 0.4 + 0.1
	var w := TestSpawn.enemy(world, WOLF, Vector3(0, 0.05, -d), "test.aim_wolf", false, PI) as WolfEnemy
	w.entity.combatant.unkillable = true
	await step_ticks(2)
	await _lock(p, "test.aim_wolf")
	for attack_id: String in ["ability.light_1", "ability.light_2", "ability.heavy_1"]:
		var got: Array = await _swing(p, attack_id, "test.aim_wolf")
		assert_eq(got[0], 1, "%s lands on a wolf at the feet (%.2f m)" % [attack_id, d])
		assert_near(float(got[1]), PlayerAttack.offset_for(p.profile, attack_id), 1e-6,
			"%s keeps the stage's tilt: it already reaches the feet" % attack_id)


func test_no_target_no_aim() -> void:
	var p := await _grounded_player(2)
	var got: Array = await _swing(p, "ability.light_1", "test.nobody")
	assert_eq(got[0], 0, "nothing to hit")
	assert_near(float(got[1]), PlayerAttack.offset_for(p.profile, "ability.light_1"), 1e-6,
		"the default tilt without a target")
	var a := GameData.get_action("ability.light_1")
	var r := p.attack.aim_offset_range(a)
	assert_near(r.x, -8.0, 1e-6, "stage 2: the aim starts at the stage's tilt")
	assert_near(r.y, PlayerAttack.AIM_MAX_OFFSET_DEG, 1e-6, "and rises at most to the limit")
	assert_true(p.attack.sweep_reaches(a, r.y, 5.0, 0.0, 0.35, 1.8), "the highest tilt reaches 5 m")
	assert_false(p.attack.sweep_reaches(a, r.x, 5.0, 0.0, 0.35, 1.8), "the stage's own tilt does not")
	assert_false(p.attack.sweep_reaches(a, r.y, 8.0, 0.0, 0.35, 1.8), "nothing reaches 8 m")
	assert_near(p.attack.aimed_offset(a, 8.0, 0.0, 0.35, 1.8), r.x, 1e-6, "out of reach: the default")
