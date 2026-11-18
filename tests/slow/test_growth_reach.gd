extends IntegrationSuite
## Moved from tests/integration/test_growth.gd by P49 (plan M11 §1.7 rule 2: headroom in the default
## tier; 1.3 s of simulation), unchanged: every light and the heavy reach a soldier and a wolf at the
## feet of a stage-2 and stage-3 giant in both camera modes (decision 5), and lights 1 and 2 and the
## heavy land on a wolf standing where its lunge stops. The default tier keeps the lunging wolf punished
## by the light chain at stages 2 and 3 (test_growth), the swing's reach per stage (test_weapons) and the
## locked soldier at the reach hit by every light (test_vertical_aim).

const WOLF := "res://scenes/enemies/wolf.tscn"
const ATTACKS := ["ability.light_1", "ability.light_2", "ability.light_3", "ability.heavy_1"]


func before_each() -> void:
	await super()
	# P08 caps weapons at their fit stage; these tests measure the full-size club at stage 3.
	TestFixtures.record_override("weapon.club", {"fit_max_stage": 3})


func _wolf(pos: Vector3, id: String, yaw := 0.0) -> WolfEnemy:
	return TestSpawn.enemy(world, WOLF, pos, id, false, yaw) as WolfEnemy


## A giant standing on the floor (growth needs it: reason "busy" while airborne).
func _grounded_player(pos: Vector3, yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _landed(target_id: String, attack_id: String) -> int:
	var n := 0
	for r in hits_on(target_id):
		if r.event.action_id == attack_id:
			n += 1
	return n


## Where a lunge stops: the wolf's approach_stop_m (0.1 m) capsule gap from the giant.
static func lunge_stop_m(p: GiantPlayer) -> float:
	return float(p.profile.capsule_radius_m) + 0.4 + 0.1


## Every light and the heavy, each started on its own facing straight ahead, at stages 2 and
## 3, in third and first person, lands on a 1.8 m soldier and on a 0.9 m wolf standing at
## 0.6 x melee reach in front (decision 5) [§15 downward attacks].
func test_lights_and_heavy_reach_soldiers_and_wolves_at_stages_2_and_3() -> void:
	var n := 0
	for stage in [2, 3]:
		for first_person in [false, true]:
			var p := await _grounded_player(Vector3(0, 0.05, 0))
			p.entity.combatant.unkillable = true
			var grown: Dictionary = p.growth.debug_set_stage(stage)
			assert_true(grown.ok, "stage %d (%s)" % [stage, grown.reason])
			if first_person:
				p.router.inject_edge(&"camera_toggle")
			await step_ticks(3)
			var d := 0.6 * float(p.profile.melee_reach_m)
			for kind in ["soldier", "wolf"]:
				for attack_id: String in ATTACKS:
					n += 1
					var id := "test.%s_reach_%d" % [kind, n]
					var pos := Vector3(0, 0.05, -d)
					var target: EnemyActor
					if kind == "soldier":
						target = spawn_soldier(pos, 0.0, id)
					else:
						target = _wolf(pos, id, 0.0)
					target.entity.combatant.unkillable = true
					p.camera_rig.yaw = 0.0
					p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
					await step_ticks(2)
					var a := GameData.get_action(attack_id)
					assert_eq(p.controller.request(&"attack", {"action_id": attack_id}), CombatController.Verdict.ACCEPT,
						"%s starts" % attack_id)
					await step_ticks(a.windup_ticks + a.active_ticks + 2)
					var landed := 0
					for r in hits_on(id):
						if r.event.action_id == attack_id:
							landed += 1
					assert_eq(landed, 1, "stage %d %s: %s lands on a %s %.2f m in front" % [stage,
						"first person" if first_person else "third person", attack_id, kind, d])
					target.queue_free()
					await TestWait.until(self, func() -> bool:
						return p.controller.state == CombatController.State.LOCOMOTION, 90)
					await step_ticks(1)
			p.queue_free()
			await step_ticks(2)


## The M2 gate's "dodge then punish" at the bigger stages: lights 1 and 2 and the heavy, each
## started alone, land on a wolf standing where its lunge stops (1.7 m from a stage-2 giant's
## centre, 2.15 m from a stage-3 one), straight ahead and 15 degrees to either side. (Light 3
## is an overhead chop down the right side: at a stage-3 giant's feet it only reaches the
## right; the chain test below shows it still connects after the first two blows.)
func test_lights_1_2_and_heavy_reach_a_wolf_at_the_feet_of_stages_2_and_3() -> void:
	var n := 0
	for stage in [2, 3]:
		var p := await _grounded_player(Vector3(0, 0.05, 0))
		p.entity.combatant.unkillable = true
		assert_true(p.growth.debug_set_stage(stage).ok, "stage %d" % stage)
		await step_ticks(2)
		var d := lunge_stop_m(p)
		for attack_id: String in ["ability.light_1", "ability.light_2", "ability.heavy_1"]:
			for bearing: float in [-15.0, 0.0, 15.0]:
				n += 1
				var id := "test.wolf_feet_%d" % n
				var t := deg_to_rad(bearing)
				var pos := Vector3(d * sin(t), 0.05, -d * cos(t))
				var w := _wolf(pos, id, yaw_towards(pos, Vector3.ZERO))
				w.entity.combatant.unkillable = true
				p.camera_rig.yaw = 0.0
				p.global_position = Vector3(0, 0.05, 0)
				p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
				await step_ticks(2)
				var a := GameData.get_action(attack_id)
				p.controller.request(&"attack", {"action_id": attack_id})
				await step_ticks(a.windup_ticks + a.active_ticks + 2)
				assert_eq(_landed(id, attack_id), 1, "stage %d: %s lands on a wolf at the giant's feet (%.2f m, %+.0f degrees)" % [
					stage, attack_id, d, bearing])
				w.queue_free()
				await TestWait.until(self, func() -> bool:
					return p.controller.state == CombatController.State.LOCOMOTION, 90)
				await step_ticks(1)
		p.queue_free()
		await step_ticks(2)
