extends IntegrationSuite
## Growth-dependent soldier tactics (P11b, plan §3.13 designs 4-5, decision 26) with real soldiers
## and the real giant:
##   * awe: a soldier that first sees a stage-3 giant (7.92 m, 4.4 x its height) drops from 70 to
##     35 morale ("awe", once per life) and flees after one Thunder Roar (-20 x 1.5 = -30); a
##     stage-2 giant (3.05 x) awes nobody;
##   * the brace counter: an outmatched soldier holding formation braces when the stage-2 giant comes
##     within 3.0 m + its radius - a line telegraph, then 35 damage - while a light swing from
##     4.5 m (the giant's own reach) never sets it off.

const BRACE := "ability.soldier_brace"

var morale_events: Array = []
var telegraphs: Array = []


func before_each() -> void:
	await super()
	morale_events.clear()
	telegraphs.clear()
	Events.morale_changed.connect(_on_morale)
	Events.telegraph_started.connect(_on_telegraph)


func after_each() -> void:
	for pair: Array in [[Events.morale_changed, _on_morale], [Events.telegraph_started, _on_telegraph]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_morale(_t: int, id: String, value: float, delta: float, reason: String) -> void:
	morale_events.append([id, value, delta, reason])


func _on_telegraph(tick: int, actor_id: String, action_id: String, target_id: String, shape: String,
		_origin: Vector3, _yaw: float, radius: float, length: float, _duration_s: float) -> void:
	telegraphs.append({"tick": tick, "actor": actor_id, "action": action_id, "target": target_id,
		"shape": shape, "radius": radius, "length": length})


func _grow(p: GiantPlayer, profile_id: String) -> void:
	var prof: Dictionary = GameData.get_record(profile_id)
	p.set_profile(prof)
	p.entity.combatant.set_height(float(prof.height_m))


## A Thunder Roar hit as P03 builds it (morale_damage 20, no damage).
func _roar_hit(target_id: String, from: Vector3) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.thunder_roar"
	e.power = 1.0
	e.attacker_height_m = 7.9248
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Ability", "AoE", "Unblockable"])
	e.attacker_position = from
	e.morale_damage = 20.0
	Sim.queue_hit(e)


func _awe_events(id: String) -> Array:
	return morale_events.filter(func(e: Array) -> bool: return e[0] == id and e[3] == "awe")


## A soldier 10 m north of a giant grown to `profile_id`, both facing each other, AI on.
func _soldier_sees(profile_id: String, id: String) -> SoldierEnemy:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_grow(p, profile_id)
	var s := spawn_soldier(Vector3(0, 0.05, -10), PI, id, true)
	await TestWait.until(self, func() -> bool: return s.brain.aware, 60)
	return s


func test_a_stage_3_giant_awes_a_soldier_and_one_roar_breaks_it() -> void:
	var s: SoldierEnemy = await _soldier_sees("growth.03", "test.awed")
	assert_true(s.brain.aware, "the soldier saw the giant")
	assert_true(s.brain.awed, "awe")
	assert_near(s.brain.morale, 35.0, 1e-6, "70 - 35 on first sight of a 7.92 m giant (4.4 x its height)")
	var awe := _awe_events("test.awed")
	assert_eq(awe.size(), 1, "one awe report")
	if awe.size() == 1:
		assert_near(float(awe[0][2]), -35.0, 1e-6, "awe is applied as given (never x1.5)")
	await step_ticks(36)
	assert_eq(_awe_events("test.awed").size(), 1, "once per life, however often it looks")
	assert_false(s.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED], "35 is above flee_morale 25")
	_roar_hit("test.awed", Vector3(0, 0, 0))
	var fled: bool = await TestWait.until(self, func() -> bool: return s.brain.state == EnemyBrain.AIState.FLEE, 30)
	assert_near(s.brain.morale, 5.0, 1e-6, "one Roar: -20 x 1.5 (outmatched) = -30")
	assert_true(fled, "and it flees")


func test_a_stage_2_giant_awes_nobody() -> void:
	var s: SoldierEnemy = await _soldier_sees("growth.02", "test.steady")
	assert_true(s.brain.aware, "the soldier saw the giant")
	assert_true(s.brain.is_outmatched(), "outmatched (3.05 x >= 2.5)")
	await step_ticks(24)
	assert_false(s.brain.awed, "no awe at 3.05 x")
	assert_near(s.brain.morale, 70.0, 1e-6, "morale untouched")
	assert_eq(_awe_events("test.steady").size(), 0, "no awe report")


## A stage-2 giant at (0, 0) facing north and a soldier `gap` m north of it holding formation.
func _holding_soldier(gap: float) -> Array:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	_grow(p, "growth.02")
	var s := spawn_soldier(Vector3(0, 0.05, -gap), PI, "test.brace", true)
	var held: bool = await TestWait.until(self, func() -> bool:
		return s.brain.state == EnemyBrain.AIState.HOLD and s.brain.in_formation(), 90)
	assert_true(held, "the outmatched soldier holds formation")
	return [p, s]


func test_a_holding_soldier_braces_against_a_giant_stepping_into_reach() -> void:
	var pair: Array = await _holding_soldier(9.0)
	var p: GiantPlayer = pair[0]
	var s: SoldierEnemy = pair[1]
	var radius := float(p.profile.get("capsule_radius_m", 1.2))
	assert_near(s.brain.hold_reach(), 3.0 + radius, 1e-4, "brace reach: 3.0 m + the giant's radius")
	await step_ticks(30)
	assert_true(telegraphs.filter(func(t: Dictionary) -> bool: return t.actor == "test.brace").is_empty(),
		"no brace while the giant stands 9 m off")
	# The giant steps into the spears: 3.9 m, inside 3.0 + 1.2.
	p.global_position = Vector3(0, 0.05, -9.0 + 3.9)
	var braced: bool = await TestWait.until(self, func() -> bool:
		return telegraphs.any(func(t: Dictionary) -> bool: return t.actor == "test.brace" and t.action == BRACE), 60)
	assert_true(braced, "the soldier braces")
	var tele: Array = telegraphs.filter(func(t: Dictionary) -> bool: return t.action == BRACE)
	if not tele.is_empty():
		assert_eq(tele[0].shape, "line", "behind a line telegraph")
		assert_near(float(tele[0].length), 4.0, 1e-6, "4 m long")
		assert_eq(tele[0].target, "player", "at the giant")
	var landed: bool = await TestWait.until(self, func() -> bool:
		return hits_on("player").any(func(r: HitResult) -> bool: return r.event.action_id == BRACE), 90)
	assert_true(landed, "the brace lands")
	for r in hits_on("player"):
		if r.event.action_id == BRACE:
			assert_eq(r.outcome, HitResult.Outcome.HIT, "a hit")
			assert_eq(r.health_damage, 35, "35 damage (30 x 1.15 = 34.5, armour 0)")


func test_a_light_swing_from_the_edge_of_reach_does_not_trigger_the_brace() -> void:
	var pair: Array = await _holding_soldier(4.5)
	var p: GiantPlayer = pair[0]
	var s: SoldierEnemy = pair[1]
	assert_true(4.5 > s.brain.hold_reach(), "4.5 m is beyond the brace reach (%.2f m)" % s.brain.hold_reach())
	p.camera_rig.yaw = 0.0
	p.router.inject_light_attack()
	await TestWait.until(self, func() -> bool: return started.has("player:ability.light_1"), 10)
	assert_true(started.has("player:ability.light_1"), "the giant swings a light from 4.5 m")
	await step_ticks(70)
	assert_true(telegraphs.filter(func(t: Dictionary) -> bool: return t.action == BRACE).is_empty(),
		"no brace: the giant stayed outside its reach")
	# The heavy reaches farther than the lights at stage 2 (about 5 m from the giant's centre against
	# a soldier, the lights about 4.1 m): from the edge of its own reach it lands, unpunished.
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 60)
	assert_eq(p.controller.request(&"attack", {"action_id": "ability.heavy_1"}), CombatController.Verdict.ACCEPT,
		"a heavy from 4.5 m")
	var landed: bool = await TestWait.until(self, func() -> bool: return hits_on("test.brace").size() > 0, 90)
	assert_true(landed, "the heavy reaches the soldier 4.5 m away")
	await step_ticks(40)
	assert_true(telegraphs.filter(func(t: Dictionary) -> bool: return t.action == BRACE).is_empty(),
		"still no brace: a strike from the edge of the giant's reach is not punished")
	assert_false(hits_on("player").any(func(r: HitResult) -> bool: return r.event.action_id == BRACE),
		"and no brace damage")
