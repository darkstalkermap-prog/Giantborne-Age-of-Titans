extends IntegrationSuite
## Moved from tests/integration/test_weapons.gd by P49 (plan M11 §1.7 rule 2: headroom in the default
## tier; 0.9 s of simulation), unchanged: in first person at stage 3 the sword, the hammer and the tree
## never cover the crosshair for more than 30 ticks in a row during a light chain. The default tier keeps
## the weapons' fit, length and reach (test_weapons), the crosshair's rule while holding and in vertical
## aim (test_vertical_aim) and the first-person arms (test_skinned_rig).

const MAX_OBSCURED_TICKS := 30


## A giant standing on the floor (growth and equipping need LOCOMOTION on the ground).
func _grounded_player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _equip(p: GiantPlayer, id: String) -> Dictionary:
	return p.equipment.grant_weapon(id, true)


func _grow(p: GiantPlayer, stage: int) -> void:
	if p.growth_stage != stage:
		var r: Dictionary = p.growth.debug_set_stage(stage)
		assert_true(r.ok, "grew to stage %d (%s)" % [stage, r.reason])
	await step_ticks(2)


## First person at stage 3 with the sword, the hammer and the tree in turn (and the full-size
## reforged sword and maul), through a light chain entered with the router, looking ahead and
## 25 degrees down: the crosshair probe never reports more than 30 consecutive ticks in which the
## giant's own meshes (its weapon included) are the first thing the centre ray meets. P43: with the
## skinned layers on, so the realistic arms and the weapon in the fist are where the player sees them (the
## probe measures the skinned meshes by their posed bones).
func test_first_person_light_chains_keep_the_crosshair_clear_at_stage_3() -> void:
	SkinnedRig.enable_for_tests()   # off again after the test (ResetHooks)
	var p := await _grounded_player()
	p.entity.combatant.unkillable = true
	await _grow(p, 3)
	p.router.inject_edge(&"camera_toggle")
	await step_ticks(2)
	assert_true(p.camera_rig.is_first_person(), "first person")
	for id: String in ["weapon.sword", "weapon.hammer", "weapon.tree_oak", "weapon.sword_reinforced", "weapon.hammer_reinforced"]:
		assert_true(_equip(p, id).ok, "%s equipped" % id)
		await step_ticks(2)
		var probe := CrosshairProbe.new(p.camera_rig.camera, [p])
		var chain := 3 if id.begins_with("weapon.sword") else 2
		for pitch_deg: float in [0.0, -25.0]:
			p.camera_rig.pitch = deg_to_rad(pitch_deg)
			for i in chain:
				p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
				p.router.inject_light_attack()
				for t in 30:
					await step_ticks(1)
					probe.sample()
			await TestWait.until(self, func() -> bool:
				probe.sample()
				return p.controller.state == CombatController.State.LOCOMOTION, 120)
		assert_true(probe.samples > 100, "%s: sampled the chains (%d ticks)" % [id, probe.samples])
		assert_true(probe.max_consecutive <= MAX_OBSCURED_TICKS,
			"%s: never more than %d obscured ticks in a row (worst %d by %s; %d of %d obscured)" % [id,
			MAX_OBSCURED_TICKS, probe.max_consecutive, probe.worst_blocker, probe.obscured_ticks, probe.samples])
