extends IntegrationSuite
## The M2 gate's wolf reach check (moved here from tests/integration/test_wolf.gd by P42, plan M10 §1.7
## rule 4: 24 giants spawned, about 0.7 s of the default tier; test_growth's reach tests and
## tests/slow/test_stage_reach_bands.gd sweep reach too): every stage-1 light and the heavy, each started on
## its own from the same stance, lands on a 0.9 m wolf standing where a lunge stops and at 0.6 x the stage-1
## melee reach, on both sides of the giant's facing.

const WOLF := "res://scenes/enemies/wolf.tscn"
## Where a lunge that reaches a stage-1 giant stops (its approach_stop_m capsule gap): about
## 1.3 m from the giant's centre.
const LUNGE_STOP_M := 1.3
## Straight ahead and 15 degrees to either side of the giant's facing (+ = right).
const BEARINGS_DEG := [-15.0, 0.0, 15.0]


func _wolf(pos: Vector3, id: String, ai := false, yaw := 0.0) -> WolfEnemy:
	return TestSpawn.enemy(world, WOLF, pos, id, ai, yaw) as WolfEnemy


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
