extends TestSuite
## P11b's pure parts (plan §2.8.3, §3.13): the `npc` record type (the plan's elder example and the
## shipped records validate; bad values are refused), the enemy schema's training block, the
## faction rules of FactionState (flag ids, standing precedence, the 30 s offence rule, the HUD
## lines), CivilianBrain's triggers and choices, and the SparringBrain's cadence.

const S := EnemyBrain.AIState
const CS := CombatController.State


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


## The plan's elder example (§2.8.3).
func _elder() -> Dictionary:
	return {"schema_version": 1, "id": "npc.elder", "type": "npc", "role": "talker", "display_name": "Elder Maren",
		"scene": "res://scenes/npcs/elder.tscn", "height_m": 1.7, "capsule_radius_m": 0.3, "health": 60, "armor": 0,
		"walk_speed_mps": 1.2, "run_speed_mps": 2.8, "flee_trigger_radius_m": 0, "protected": true,
		"dialogue": "dialogue.elder", "lockable": false, "grants_fury": false, "threat": 0.0, "nav_layers": 1,
		"grab_attach": "none"}


func test_the_npc_record_type() -> void:
	assert_true(DataValidator.RECORD_TYPES.has("npc"), "npc is a record type")
	var r := _validate(_elder())
	assert_eq(r.errors.size(), 0, "the plan's elder example validates: %s" % "\n".join(r.errors))
	assert_eq(r.warnings.size(), 0, "without warnings")
	for id in ["npc.villager", "npc.elder"]:
		assert_eq(str(GameData.get_record(id).get("type", "")), "npc", "%s ships" % id)
	var bad := _elder()
	bad["role"] = "merchant"
	assert_true(_errors(bad).contains("role: unknown value 'merchant'"), "roles are civilian or talker")
	bad = _elder()
	bad["run_speed_mps"] = 1.0
	assert_true(_errors(bad).contains("run_speed_mps must be >= walk_speed_mps"), "runs no slower than it walks")
	bad = _elder()
	bad["dialogue"] = "Elder Talk"
	assert_true(_errors(bad).contains("must be lowercase dotted form"), "the dialogue is an id")
	bad = _elder()
	bad["scene"] = "res://scenes/npcs/nobody.tscn"
	assert_true(_errors(bad).contains("does not exist"), "the scene must exist")
	bad = _elder()
	bad.erase("health")
	assert_true(_errors(bad).contains("missing required key 'health'"), "health is required")
	bad = _elder()
	bad["faction"] = "village"
	assert_true(_errors(bad).contains("unknown key 'faction'"), "the faction comes from the spawn, not the record")
	var quiet := _elder()
	quiet.erase("dialogue")
	assert_true("\n".join(_validate(quiet).warnings).contains("a talker without a dialogue"), "a silent talker warns")


func test_the_enemy_training_block() -> void:
	var post: Dictionary = (GameData.get_record("enemy.sparring_post") as Dictionary).duplicate(true)
	assert_eq(_errors(post), "", "the shipped sparring post validates")
	post.erase("training")
	assert_true(_errors(post).contains("archetype 'training' needs a 'training' block"), "training needs its block")
	var soldier: Dictionary = (GameData.get_record("enemy.soldier") as Dictionary).duplicate(true)
	assert_eq(str(soldier.tactics.get("hold_attack")), "ability.soldier_brace", "the soldier braces in formation")
	assert_near(float(soldier.tactics.get("awe_ratio")), 4.0, 1e-6, "awe at 4x its height")
	assert_near(float(soldier.tactics.get("awe_morale_loss")), 35.0, 1e-6, "costing 35 morale")
	for id in ["enemy.archer", "enemy.mage"]:
		var t: Dictionary = GameData.get_record(id).get("tactics", {})
		assert_true(float(t.get("awe_ratio", 0.0)) == 4.0 and float(t.get("awe_morale_loss", 0.0)) == 35.0,
			"%s is awed too" % id)
	(soldier.tactics as Dictionary).erase("awe_morale_loss")
	assert_true("\n".join(_validate(soldier).warnings).contains("awe costs nothing"), "awe without a loss warns")
	var brace := GameData.get_action("ability.soldier_brace")
	assert_true(brace != null, "the brace exists")
	if brace != null:
		assert_eq(brace.power, 30.0, "P30")
		assert_eq([brace.windup_ticks, brace.active_ticks, brace.recovery_ticks], [48, 9, 42], "0.8 / 0.15 / 0.7 s")
		assert_eq(brace.poise_damage, 30.0, "poise 30")
		assert_near(float(brace.param("ai_max_range_m")), 3.0, 1e-6, "3.0 m (+ the target's radius)")
		assert_eq(str((brace.param("telegraph") as Dictionary).get("shape")), "line", "a line telegraph")


func test_faction_rules() -> void:
	WorldState.clear()
	assert_eq(FactionState.flag_id("village", "hostile"), "faction.village.hostile", "flag ids")
	assert_eq(FactionState.standing(""), "", "no faction: no standing")
	assert_eq(FactionState.standing("village"), "neutral", "neutral by default")
	WorldState.set_flag("faction.village.warned", true)
	assert_eq(FactionState.standing("village"), "warned", "warned")
	WorldState.set_flag("faction.village.stood_down", true)
	assert_eq(FactionState.standing("village"), "stood_down", "standing down outranks a warning")
	WorldState.set_flag("faction.village.hostile", true)
	assert_eq(FactionState.standing("village"), "hostile", "hostility outranks standing down")
	WorldState.clear()
	var w := 30 * 60
	assert_eq(FactionState.offence_result(false, FactionState.NO_TICK, 100, w), "warned", "a first offence warns")
	assert_eq(FactionState.offence_result(true, 100, 100 + w, w), "hostile", "a second within 30 s: hostile")
	assert_eq(FactionState.offence_result(true, 100, 101 + w, w), "warned", "older than 30 s: forgotten")
	assert_eq(FactionState.offence_result(false, 100, 160, w), "warned", "no warning on record (a new game): warns")
	assert_eq(FactionState.text_for("village", "warned"),
		"Thornwick's people cower. Strike again and they will fight you.", "the plan's warning")
	assert_true(FactionState.text_for("other", "hostile") != "", "any faction gets a line")
	assert_true(FactionState.truthy("x") and not FactionState.truthy("") and not FactionState.truthy(null)
		and not FactionState.truthy(0) and FactionState.truthy(true), "truthy flags")


func _civilian(patch := {}) -> CivilianBrain:
	var rec: Dictionary = (GameData.get_record("npc.villager") as Dictionary).duplicate(true)
	TestFixtures.deep_merge(rec, patch)
	return CivilianBrain.new("test.civ", rec)


func _giant(distance: float, speed: float, hostile := false, stood_down := false) -> Dictionary:
	return {"exists": true, "position": Vector3(0, 0, -distance), "distance": distance, "speed": speed,
		"hostile": hostile, "stood_down": stood_down}


func test_civilian_triggers() -> void:
	var b := _civilian()
	assert_near(b.flee_trigger_radius_m, 8.0, 1e-6, "the villager's trigger radius (data)")
	b.perceive(10, _giant(5.0, 2.5))
	assert_eq(b.state, CivilianBrain.State.IDLE, "a giant ambling past (2.5 m/s) scares nobody")
	b.perceive(20, _giant(12.0, 6.0))
	assert_eq(b.state, CivilianBrain.State.IDLE, "nor one rushing by 12 m away")
	b.perceive(30, _giant(6.0, 5.0))
	assert_eq(b.state, CivilianBrain.State.FLEE, "a giant rushing within 8 m does")
	assert_eq(b.flee_reason, "giant", "reason giant")
	b = _civilian()
	b.on_noise(5, 25.0)
	assert_eq(b.state, CivilianBrain.State.IDLE, "combat 25 m away is no reason")
	b.on_noise(6, 18.0)
	assert_eq([b.state, b.flee_reason], [CivilianBrain.State.FLEE, "noise"], "combat within 20 m is")
	b = _civilian()
	b.perceive(1, _giant(50.0, 0.0, true))
	assert_eq(b.flee_reason, "hostile", "the village turned hostile")
	b = _civilian()
	b.on_faction(1, "stood_down")
	assert_eq(b.flee_reason, "stood_down", "the guards stood down")
	b = _civilian()
	b.on_faction(1, "warned")
	assert_eq(b.state, CivilianBrain.State.IDLE, "a warning alone sends nobody home")
	var t := _civilian({"role": "talker"})
	t.perceive(1, _giant(3.0, 8.0, true, true))
	t.on_noise(2, 1.0)
	t.on_faction(3, "hostile")
	assert_eq(t.state, CivilianBrain.State.IDLE, "a talker never flees")
	t.decide(4, Vector3.ZERO, true)
	assert_true(t.face_point != Vector3.INF, "and turns to a giant nearby")


func test_civilian_choices_once_and_after_a_failure() -> void:
	var b := _civilian()
	var calls: Array = []
	var answers := [Vector3(10, 0, 0), Vector3(0, 0, 12)]
	b.safe_resolver = func(_from: Vector3, skip_failed: bool) -> Vector3:
		calls.append(skip_failed)
		return answers[mini(calls.size() - 1, answers.size() - 1)]
	b.start_fleeing("noise")
	b.decide(6, Vector3.ZERO, true)
	assert_eq(b.destination, Vector3(10, 0, 0), "the nearest reachable shelter")
	assert_eq(b.move_target, Vector3(10, 0, 0), "it runs there")
	assert_true(b.move_speed < 0.0, "running")
	for i in 5:
		b.decide(12 + 6 * i, Vector3(i, 0, 0), true)
	assert_eq(calls, [false], "chosen once: no re-path without a failure")
	b.on_path_failed(Vector3(4, 0, 0))
	assert_eq(calls, [false, true], "a path failure picks again, skipping the failed one")
	assert_eq(b.destination, Vector3(0, 0, 12), "the next one")
	b.decide(60, Vector3(0, 0, 11.5), true)
	assert_eq(b.state, CivilianBrain.State.SAFE, "within 1 m: safe")
	var lost := _civilian()
	var tries := [0]
	lost.safe_resolver = func(_from: Vector3, _skip: bool) -> Vector3:
		tries[0] += 1
		return Vector3.INF
	lost.start_fleeing("hostile")
	lost.decide(6, Vector3.ZERO, true)
	lost.decide(12, Vector3.ZERO, true)
	assert_eq(tries[0], 1, "nowhere to run: it waits")
	assert_eq(lost.move_target, Vector3.INF, "standing")
	lost.decide(6 + 120, Vector3.ZERO, true)
	assert_eq(tries[0], 2, "and asks again 2 s later")
	lost.decide(200, Vector3.ZERO, false)
	assert_eq(lost.state, CivilianBrain.State.DEAD, "dead")


func test_sparring_brain_cadence() -> void:
	var b := SparringBrain.new("test.post", GameData.get_record("enemy.sparring_post"), 3)
	assert_eq(b.swing_interval_ticks, 180, "3 s")
	assert_near(b.trigger_radius_m, 4.0, 1e-6, "within 4 m")
	var near := {"exists": true, "alive": true, "visible": true, "target_id": "player", "position": Vector3(0, 0, 3),
		"distance": 3.0}
	var far := near.duplicate()
	far["distance"] = 6.0
	var swings: Array = []
	for tick in range(0, 600, 6):
		b.perceive(tick, near if tick < 420 else far)
		b.decide(tick, CS.LOCOMOTION, Vector3.ZERO, Callable(), Callable())
		if b.attack_request != "":
			swings.append(tick)
		assert_false(b.aware, "never aware (tick %d)" % tick)
		assert_eq(b.move_target, Vector3.INF, "never moves (tick %d)" % tick)
	assert_eq(swings, [0, 180, 360], "every 3 s while the giant is within 4 m, then none")
	b.on_noise(700, Vector3.ZERO, "player", true)
	assert_false(b.aware, "a blow wakes nothing")
	b.decide(706, CS.DEAD, Vector3.ZERO, Callable(), Callable())
	assert_eq(b.state, S.DEAD, "DEAD follows the controller")
