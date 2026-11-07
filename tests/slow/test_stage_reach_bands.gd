extends IntegrationSuite
## Stage 4-6 reach bands (P31, plan M6-M9 §3.15, §5.12; the M7 gate's weapon check): every weapon a
## stage 4-6 giant can carry - the reinforced club, sword and hammer, the axe, the great pine and
## every titanforged form - lands each blow of its stage moveset (lights 1-3, the hammer's and the
## pine's lights 1-2, and the heavy) on a soldier and on a wolf standing straight ahead, from contact
## + 0.3 m to 0.9 x the stage's melee reach, at stages 4, 5 and 6. Real swings on the integration
## floor, third person, no lock (the swing's own vertical aim picks the soft target ahead); the
## targets are reused and put back in place before every swing, and the giant's recovery is cut short
## (controller.recovery_scale) so the 400-odd swings fit the slow tier's budget.

const WOLF := "res://scenes/enemies/wolf.tscn"
const WEAPONS := ["weapon.club_reinforced", "weapon.sword_reinforced", "weapon.hammer_reinforced", "weapon.axe",
	"weapon.tree_pine", "weapon.club_titan", "weapon.sword_titan", "weapon.hammer_titan", "weapon.axe_titan"]
const STAGES := [4, 5, 6]
## The giant's recovery while it swings here (the hits all land in the windup and the active phase).
const FAST_RECOVERY := 0.05
## Where the target not being swung at waits (behind the giant, out of reach).
const PARKED := Vector3(0, 0.05, 40)


## The blows of `weapon_id`'s moveset at `stage`: the light chain followed through chain_next, then
## the heavy.
static func attacks_of(weapon_id: String, stage: int) -> Array:
	var m := PlayerEquipment.moveset_for(GameData.get_record(weapon_id), stage)
	var out: Array = []
	var id := str(m.light_chain)
	while id != "" and not out.has(id) and out.size() < 4:
		out.append(id)
		var a := GameData.get_action(id)
		id = str(a.param("chain_next", "")) if a != null else ""
	out.append(str(m.heavy))
	return out


## One swing of `attack_id` straight ahead with `target` put back `d` metres in front of the giant:
## how many of its hits landed on it.
func _swing(p: GiantPlayer, attack_id: String, target: EnemyActor, d: float) -> int:
	# The band is about reach, not about a target still reeling from the blow before: wait out its
	# stagger and clear its poise damage.
	await TestWait.until(self, func() -> bool: return target.controller.state != CombatController.State.STAGGERED, 180)
	target.entity.combatant.poise.value = 0.0
	target.global_position = Vector3(0, 0.05, -d)
	target.velocity = Vector3.ZERO
	target.knockback_velocity = Vector3.ZERO
	target.move_velocity = Vector3.ZERO
	target.rotation.y = 0.0
	p.global_position = Vector3(0, p.global_position.y, 0)
	p.velocity = Vector3.ZERO
	p.move_velocity = Vector3.ZERO
	p.camera_rig.yaw = 0.0
	p.facing_yaw = 0.0
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.controller.recovery_scale = FAST_RECOVERY
	await step_ticks(2)
	var before := _landed(target.entity.entity_id, attack_id)
	var a := GameData.get_action(attack_id)
	if p.controller.request(&"attack", {"action_id": attack_id}) != CombatController.Verdict.ACCEPT:
		return -1
	await step_ticks(a.windup_ticks + a.active_ticks + 2)
	var landed := _landed(target.entity.entity_id, attack_id) - before
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 90)
	return landed


func _landed(target_id: String, attack_id: String) -> int:
	var n := 0
	for r in hits_on(target_id):
		if r.event.action_id == attack_id:
			n += 1
	return n


func test_every_stage_4_to_6_weapon_lands_its_moveset_from_contact_to_0_9_reach() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	p.entity.combatant.unkillable = true
	var soldier := spawn_soldier(PARKED + Vector3(6, 0, 0), 0.0, "test.p31_soldier")
	var wolf := TestSpawn.enemy(world, WOLF, PARKED - Vector3(6, 0, 0), "test.p31_wolf", false, 0.0)
	for t: EnemyActor in [soldier, wolf]:
		t.entity.combatant.unkillable = true
	var swings := 0
	var misses: Array = []
	for stage: int in STAGES:
		assert_true(bool(p.growth.debug_set_stage(stage).ok), "stage %d" % stage)
		await step_ticks(2)
		var reach := float(p.profile.melee_reach_m)
		for weapon_id: String in WEAPONS:
			var r: Dictionary = p.equipment.grant_weapon(weapon_id, true)
			assert_true(bool(r.get("ok", false)), "stage %d: %s equipped (%s)" % [stage, weapon_id, r.get("message", "")])
			await step_ticks(1)
			var attacks := attacks_of(weapon_id, stage)
			assert_eq(attacks.size(), 3 if GameData.get_record(weapon_id).family in ["hammer", "tree"] else 4,
				"stage %d %s: lights and the heavy %s" % [stage, weapon_id, attacks])
			for target: EnemyActor in [soldier, wolf]:
				var other: EnemyActor = wolf if target == soldier else soldier
				other.global_position = PARKED   # behind the giant: never the swing's soft target
				var rec: Dictionary = target.record
				var contact := float(p.profile.capsule_radius_m) + float(rec.get("capsule_radius_m", 0.4))
				for d: float in [contact + 0.3, 0.9 * reach]:
					for attack_id: String in attacks:
						swings += 1
						var landed := await _swing(p, attack_id, target, d)
						if landed != 1:
							misses.append("stage %d %s %s on the %s at %.2f m: %d" % [stage, weapon_id, attack_id,
								rec.get("archetype", "?"), d, landed])
	assert_eq(swings, 396, "every blow of every weapon, at both distances, on both targets, at three stages")
	assert_eq(misses, [], "every blow lands once (%d of %d missed)" % [misses.size(), swings])
	soldier.queue_free()
	wolf.queue_free()
