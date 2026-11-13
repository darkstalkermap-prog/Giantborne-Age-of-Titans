extends IntegrationSuite
## M9 gate (lane review; FOLLOWUPS "From the M8 screenshot pass", the riders' row): a leash return never ends
## early outside the leash. W23 (P39f) ended a return where the member stood when a body stood on its post (or
## after six path failures), so its AI resumed - but when that happened outside the leash the director sent it
## home again at its next update, and each early end healed it to full: on the director test level a soldier
## whose post a stage-6 giant stood on, 37 m out of its 40 m leash, was leashed 14 times and healed 9 times in
## 40 s, pressed against him (the review's probe). On the director test level, the real soldier AI:
##   * its post taken outside the leash: one leash, one heal (LEASH_HEAL_S into the return), it backs off his
##     body and waits there facing him, still returning; once he leaves it rides home and its return ends
##     there with no second heal;
##   * its post taken LEASH_END_MARGIN_M or more inside the leash: the return ends where it stands, unhealed,
##     and its AI resumes - the director does not send it home again;
##   * its way lost outside the leash (a wall the navmesh does not know of between it and its post): it holds
##     still LEASH_RETRY_S at a time and tries again, never ending its return out there; once the wall is
##     gone it rides home.
## Fix-up 1 (the lane's verifier): waiting off its taken post the member was a target that never answered - it
## stood in its return while the giant on its post beat it, for as long as he stayed (a Brannock guard from 220
## to 20 health in 30 s). Now:
##   * struck while it waits for its post: its return ends there, unhealed, its AI resumes knowing who struck it,
##     and the director leaves it off the leash while he holds its post (no second leash, no second heal); once
##     he leaves, the leash holds it again.
## The real world's case (the war camp's picket rider) is the gate tier's tests/gate/test_war_camp_leash.gd.

const LEVEL_SCENE := "res://scenes/test/director_test.tscn"
const SOLDIERS := "encounter.director_test_soldiers"
const MEMBER := "test.director.soldier_3"

var level: LevelRoot
var director: EncounterDirector
var player: GiantPlayer
var leashed := 0
var heals := 0


func before_each() -> void:
	await super()
	leashed = 0
	heals = 0
	Events.encounter_leashed.connect(_on_leashed)
	Events.healed.connect(_on_healed)


func after_each() -> void:
	if Events.encounter_leashed.is_connected(_on_leashed):
		Events.encounter_leashed.disconnect(_on_leashed)
	if Events.healed.is_connected(_on_healed):
		Events.healed.disconnect(_on_healed)
	level = null
	director = null
	player = null
	await super()


func _on_leashed(_t: int, _enc: String, id: String) -> void:
	if id == MEMBER:
		leashed += 1


func _on_healed(_t: int, id: String, _amount: float, source: String) -> void:
	if id == MEMBER and source == "leash":
		heals += 1


## Only the member under test thinks; the others stand (they would walk up to the giant).
func _on_member_spawned(_enc: String, entity_id: String, node: Node3D) -> void:
	if entity_id != MEMBER and "ai_enabled" in node:
		node.set("ai_enabled", false)


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## The level with a stage-6 giant that takes no damage; returns the member under test.
func _setup() -> EnemyActor:
	level = (load(LEVEL_SCENE) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	director = level.director()
	director.member_spawned.connect(_on_member_spawned)
	player = level.player()
	player.router.use_injection = true
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 6:
			player.set_profile(rec)
	player.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(1)
	director.force_activate(SOLDIERS)
	await step_ticks(2)
	return director.spawned(MEMBER) as EnemyActor


func _centre() -> Vector3:
	var c: Array = GameData.get_record(SOLDIERS).get("center_m", [0, 0, 0])
	return Vector3(float(c[0]), 0.0, float(c[2]))


func _leash_m() -> float:
	return float(GameData.get_record(SOLDIERS).get("leash_radius_m", 0.0))


func _put_giant(pos: Vector3) -> void:
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.move_velocity = Vector3.ZERO


## The gap between the member's capsule and the giant's (negative: pressed into him).
func _gap(s: EnemyActor) -> float:
	return _flat(s.global_position, player.global_position) - float(player.profile.get("capsule_radius_m", 3.7)) \
		- float(s.record.get("capsule_radius_m", 0.35))


func test_a_member_whose_post_is_taken_outside_its_leash_waits_off_the_body() -> void:
	var s := await _setup()
	var centre := _centre()
	var leash := _leash_m()
	var giant_r := float(player.profile.get("capsule_radius_m", 3.7))
	var my_r := float(s.record.get("capsule_radius_m", 0.35))
	var post := centre + Vector3(0, 0.05, leash - 3.0)   # 37 m out of a 40 m leash
	assert_true(leash - 3.0 + giant_r + my_r > leash, "with the giant on its post, his edge on its side lies outside the leash")
	s.home_position = post
	_put_giant(post)
	var hp_max := s.entity.combatant.pools.health_max
	queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, 2), 60.0)
	await step_ticks(1)
	assert_true(s.entity.combatant.pools.health < hp_max, "hurt before the lure")
	s.global_position = centre + Vector3(0.3, 0.05, leash + 20.0)   # lured out behind him
	director.update_now()
	assert_true(s.is_returning(), "the leash sends it home")
	var pinned_late := 0.0
	var ended_out := false
	var wait_tick := -1
	for i in 60 * 24:
		await step_ticks(1)
		if not s.is_returning():
			ended_out = true
			break
		if wait_tick < 0 and s.leash_waiting == "post":
			wait_tick = Sim.tick
		if wait_tick >= 0 and Sim.tick - wait_tick >= 60 and _gap(s) < 0.5:
			pinned_late += 1.0 / 60.0   # still against him a second after it began to wait
	var waited := wait_tick >= 0
	print("    post taken outside the leash, 24 s: %d leash(es), %d heal(s), waiting %s, %.1f m off his body, %.1f m from the centre (leash %.0f)" % [
		leashed, heals, s.leash_waiting, _gap(s), _flat(s.global_position, centre), leash])
	assert_false(ended_out, "its return never ends out there (it ended at %s, %.1f m from the centre)" % [
		s.global_position.snappedf(0.1), _flat(s.global_position, centre)])
	assert_true(waited, "it waits for its post")
	assert_eq(leashed, 1, "the director leashed it once")
	assert_eq(heals, 1, "the leash healed it once, %.0f s into the return" % EnemyActor.LEASH_HEAL_S)
	assert_true(pinned_late < 0.01, "not pinned against him once it waits (%.1f s within 0.5 m of his body)" % pinned_late)
	assert_true(_gap(s) >= EnemyActor.LEASH_DETOUR_CLEAR_M - EnemyActor.LEASH_ARRIVE_M,
		"it stands off his body (%.1f m)" % _gap(s))
	# He leaves: it rides home, and its return ends there without a second heal.
	queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, 2), 40.0)
	_put_giant(centre + Vector3(-30, 0.05, leash + 30.0))
	var home: bool = await TestWait.until(self, func() -> bool: return not s.is_returning(), 60 * 15)
	assert_true(home, "with its post free it rides home")
	assert_true(_flat(s.global_position, post) <= EnemyActor.LEASH_ARRIVE_M + 0.3,
		"its return ends at its post (%.1f m from it)" % _flat(s.global_position, post))
	assert_eq(heals, 1, "no second heal on arrival")
	assert_true(s.entity.combatant.pools.health < hp_max, "the blow after its heal still shows")
	assert_eq(leashed, 1, "still leashed once")


func test_struck_while_it_waits_for_its_post_it_answers_and_is_held_off_the_leash_while_he_stays() -> void:
	var s := await _setup()
	var centre := _centre()
	var leash := _leash_m()
	var post := centre + Vector3(0, 0.05, leash - 3.0)   # 37 m out of a 40 m leash
	s.home_position = post
	_put_giant(post)
	s.global_position = centre + Vector3(0.3, 0.05, leash + 20.0)   # lured out behind him
	director.update_now()
	assert_true(s.is_returning(), "the leash sends it home")
	var waiting: bool = await TestWait.until(self, func() -> bool: return s.leash_waiting == "post", 60 * 12)
	assert_true(waiting, "it waits for its post")
	for i in 60 * 2:
		await step_ticks(1)   # still waiting, its LEASH_HEAL_S heal behind it or not
	var heals_before := heals
	var hp_max := s.entity.combatant.pools.health_max
	queue_hit("player", s.entity_id, player.global_position, 40.0)   # his blow from his post
	var blow_tick := Sim.tick
	var answered: bool = await TestWait.until(self, func() -> bool: return not s.is_returning(), 3)
	var hp_after := s.entity.combatant.pools.health
	print("    struck while it waits: answered %s %d tick(s) after the blow, %.1f m from the centre (leash %.0f), health %.0f / %.0f, state %s, target '%s'" % [
		answered, Sim.tick - blow_tick, _flat(s.global_position, centre), leash, hp_after, hp_max, s.brain.state_name(), s.brain.target_id])
	assert_true(answered, "struck while it waits, its return ends (it answers)")
	assert_eq(s.leash_answers, 1, "one answer")
	assert_true(_flat(s.global_position, centre) > leash, "out there, outside the leash")
	assert_eq(heals, heals_before, "unhealed: the answer is an early end")
	assert_true(hp_after < hp_max, "the blow shows (%.0f / %.0f)" % [hp_after, hp_max])
	assert_true(s.ai_enabled, "its AI resumes")
	assert_true(s.brain.target_id == "player" and s.brain.aware, "it knows who struck it (%s)" % s.brain.target_id)
	assert_true(s.leash_held_off(), "the giant on its post holds it off the leash")
	var states := {}
	var outside_held := 0
	var outside_free := 0
	for i in 60 * 8:
		await step_ticks(1)
		if i % 30 == 29:
			director.update_now()
		if not s.entity.is_alive():
			break
		states[s.brain.state_name()] = true
		if _flat(s.global_position, centre) > leash and s.brain.state != EnemyBrain.AIState.RETURN:
			if s.leash_held_off():
				outside_held += 1
			else:
				outside_free += 1
	print("    while he stays (8 s): states %s, %d leash(es), %d heal(s), %.1f s outside the leash held off, %.1f s not" % [
		states.keys(), leashed, heals, outside_held / 60.0, outside_free / 60.0])
	assert_false(states.has("Return"), "it answers him rather than go home")
	assert_eq(leashed, 1, "the director does not send it home while he holds its post")
	assert_eq(heals, heals_before, "nor heals it")
	assert_eq(outside_free, 0, "outside the leash it is held off it while he stays")
	# He leaves: it is no longer held off, and outside the leash the director sends it home.
	_put_giant(centre + Vector3(-30, 0.05, leash + 30.0))
	await step_ticks(1)
	assert_false(s.leash_held_off(), "with its post free nothing holds it off the leash")
	if s.entity.is_alive() and not (s.brain.state in [EnemyBrain.AIState.FLEE, EnemyBrain.AIState.ROUTED]):
		var inside: bool = await TestWait.until(self, func() -> bool:
			return _flat(s.global_position, centre) <= leash, 60 * 15)
		assert_true(inside, "the leash holds it again: it comes back inside (%.1f m from the centre, %d leash(es))" % [
			_flat(s.global_position, centre), leashed])


func test_a_member_whose_post_is_taken_inside_its_leash_ends_its_return_unhealed() -> void:
	var s := await _setup()
	var centre := _centre()
	var leash := _leash_m()
	var giant_r := float(player.profile.get("capsule_radius_m", 3.7))
	var my_r := float(s.record.get("capsule_radius_m", 0.35))
	var post_m := leash - giant_r - my_r - EnemyActor.LEASH_END_MARGIN_M - 1.0   # his edge on its side 1 m inside the margin
	var post := centre + Vector3(0, 0.05, post_m)
	s.home_position = post
	_put_giant(post)
	var hp_max := s.entity.combatant.pools.health_max
	queue_hit("player", s.entity_id, s.global_position + Vector3(0, 0, 2), 60.0)
	await step_ticks(1)
	s.global_position = centre + Vector3(0.3, 0.05, leash + 0.5)   # just outside
	director.update_now()
	assert_true(s.is_returning(), "the leash sends it home")
	var t0 := Sim.tick
	var ended: bool = await TestWait.until(self, func() -> bool: return not s.is_returning(), 60 * 6)
	var after_s := (Sim.tick - t0) / 60.0
	print("    post taken inside the leash: the return ended after %.1f s, %.1f m from the centre, health %.0f / %.0f, %d heal(s)" % [
		after_s, _flat(s.global_position, centre), s.entity.combatant.pools.health, hp_max, heals])
	assert_true(ended and after_s < EnemyActor.LEASH_HEAL_S, "its return ends where it meets him, before the heal is due (%.1f s)" % after_s)
	assert_true(_flat(s.global_position, centre) <= leash - EnemyActor.LEASH_END_MARGIN_M, "inside its leash")
	assert_eq(heals, 0, "an early end does not heal")
	assert_true(s.entity.combatant.pools.health < hp_max, "still hurt (%.0f / %.0f)" % [s.entity.combatant.pools.health, hp_max])
	assert_true(s.ai_enabled, "its AI resumes")
	for i in 60 * 6:
		await step_ticks(1)
	assert_eq(leashed, 1, "the director does not send it home again")


func test_a_member_whose_way_is_lost_outside_its_leash_holds_and_tries_again() -> void:
	var s := await _setup()
	var centre := _centre()
	var leash := _leash_m()
	var post := centre + Vector3(0, 0.05, leash - 10.0)
	s.home_position = post
	_put_giant(centre + Vector3(25, 0.05, leash + 25.0))   # out of its way
	var lure := centre + Vector3(0.3, 0.05, leash + 4.0)
	s.global_position = lure
	# A wall the navmesh does not know of, between it and its post: the path runs through it.
	var wall := add_box(Vector3(30, 4, 1), centre + Vector3(0, 2, leash + 2.0))
	await step_ticks(1)
	director.update_now()
	assert_true(s.is_returning(), "the leash sends it home")
	var ended_out := false
	var way_waits := 0
	var held_still := 0.0
	var last := s.global_position
	for i in 60 * 30:
		await step_ticks(1)
		if not s.is_returning():
			ended_out = true
			break
		if s.leash_waiting == "way":
			if _flat(s.global_position, last) < 0.01:
				held_still += 1.0 / 60.0
		last = s.global_position
		way_waits = s.leash_waits
	print("    way lost outside the leash, 30 s: %d leash(es), %d wait(s), %.1f s held still, %.1f m from the centre" % [
		leashed, way_waits, held_still, _flat(s.global_position, centre)])
	assert_false(ended_out, "its return never ends outside the leash (it ended %.1f m from the centre)" % _flat(s.global_position, centre))
	assert_true(way_waits >= 1, "its way lost, it waits (%d)" % way_waits)
	assert_true(held_still >= EnemyActor.LEASH_RETRY_S - 0.5, "holding still (%.1f s) instead of pressing on the wall" % held_still)
	assert_eq(leashed, 1, "the director leashed it once")
	assert_true(heals <= 1, "healed once at most (%d)" % heals)
	wall.queue_free()
	var home: bool = await TestWait.until(self, func() -> bool: return not s.is_returning(), 60 * 20)
	assert_true(home and _flat(s.global_position, post) <= EnemyActor.LEASH_ARRIVE_M + 0.3,
		"the wall gone, it rides home (%.1f m from its post)" % _flat(s.global_position, post))
	assert_eq(leashed, 1, "still leashed once")
