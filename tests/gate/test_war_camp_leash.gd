extends IntegrationSuite
## M9 gate (lane review; the review's major finding): a war-camp picket rider whose post a giant stands on, at
## the edge of the camp's leash. On the real world (scenes/world/world.tscn, deterministic streaming), Aldmere at
## war, a stage-6 giant that takes no damage: the middle picket's rider, lured past its post out of the camp's
## leash, is sent home by the leash while the giant steps onto its post. W23 (P39f) ended its return at his edge -
## outside the leash, since the post stands a few metres inside it and he is 3.7 m wide - the director sent it
## home again at its next update and each early end healed it to full: 12 leashes and 11 heals in 30 s, pinned
## 4.1 m from his centre (the review's probe). Now a return never ends early outside the leash: the rider backs
## off his body and waits for its post, and while he stays it is leashed once and healed once (LEASH_HEAL_S into
## the return), and it is not pinned against him.
## The camp's centre and leash and the picket's post come from the encounter's record at run time (the shield
## wall's place may change; the riders' pickets are what this test is about).
## Fix-up 1 (the lane's verifier): waiting off its post the rider was a target that never answered - the giant on
## its post could beat it for as long as he stayed (the review's camp probe: it fell, waiting). Now his blow ends
## its wait: the return ends there, unhealed, it turns on him (charges or thrusts its lance), and while he holds
## its post the director leaves it off the leash - still one leash and one heal while he stays, and it is never
## pinned against him. Once he leaves, the leash holds it again: it is back inside the camp's leash, its return over
## (a detour's end asks for a fresh path: at AI tier 1 the rider had kept its path to the detour point and rode to
## and fro short of its post).

const SCENE := "res://scenes/world/world.tscn"
const CAMP := "encounter.aldmere_war_camp"
const RIDER := "world.aldmere.camp_rider_2"
## Fix-up 1: he leaves the waiting rider be for WAIT_S, then strikes it every BLOW_TICKS (the review's probe's 2.5 s)
## while its body is within BLOW_REACH_M of his, for BLOWS_S.
const WAIT_S := 14
const BLOWS_S := 16
const BLOW_TICKS := 150
const BLOW_REACH_M := 6.0

var leashed := 0
var heals := 0
var rider_actions: Array[String] = []


func before_each() -> void:
	await super()
	leashed = 0
	heals = 0
	rider_actions.clear()
	Events.encounter_leashed.connect(_on_leashed)
	Events.healed.connect(_on_healed)
	Events.ability_started.connect(_on_ability)


func after_each() -> void:
	if Events.encounter_leashed.is_connected(_on_leashed):
		Events.encounter_leashed.disconnect(_on_leashed)
	if Events.healed.is_connected(_on_healed):
		Events.healed.disconnect(_on_healed)
	if Events.ability_started.is_connected(_on_ability):
		Events.ability_started.disconnect(_on_ability)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _on_leashed(_t: int, _enc: String, id: String) -> void:
	if id == RIDER:
		leashed += 1


func _on_healed(_t: int, id: String, _amount: float, source: String) -> void:
	if id == RIDER and source == "leash":
		heals += 1


func _on_ability(_t: int, actor: String, action_id: String, _i: int) -> void:
	if actor == RIDER:
		rider_actions.append(action_id)


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _xz(v: Variant) -> Vector2:
	var a := v as Array
	return Vector2(float(a[0]), float(a[2])) if a != null and a.size() == 3 else Vector2.INF


## Puts the giant on the ground at `xz` once the ring around it is loaded.
func _move(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 800:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 80.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func test_a_rider_whose_picket_the_giant_stands_on_is_leashed_once_waits_off_him_and_answers_his_blows() -> void:
	var rec := GameData.get_record(CAMP)
	var centre := _xz(rec.get("center_m"))
	var leash := float(rec.get("leash_radius_m", 0.0))
	var post := Vector2.INF
	for s: Dictionary in rec.get("spawns", []):
		if str(s.get("entity_id", "")) == RIDER:
			post = _xz(s.get("position_m"))
	assert_true(post != Vector2.INF and leash > 0.0, "the camp's record has its leash and the picket %s" % RIDER)
	if post == Vector2.INF or leash <= 0.0:
		return
	var giant_r := float(_profile(6).get("capsule_radius_m", 3.7))
	var rider_r := float(GameData.get_record("enemy.cavalry").get("capsule_radius_m", 0.9))
	var out := (post - centre).normalized()
	var post_m := post.distance_to(centre)
	assert_true(post_m < leash and post_m + giant_r + rider_r > leash,
		"the picket stands inside the leash (%.1f of %.0f m) and a stage-6 giant on it reaches past the leash" % [post_m, leash])
	WorldState.set_flag(FactionState.flag_id("aldmere", "hostile"), true)
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.set_profile(_profile(6))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await _move(w, post + out * 54.0)   # east of the pickets, as the review's probe stood him
	await step_ticks(60)
	var d := w.director()
	var ent := Sim.get_entity(RIDER)
	var rider: CavalryEnemy = null
	if ent != null:
		rider = ent.actor as CavalryEnemy
	assert_true(rider != null and rider.entity.is_alive(), "the picket's rider is up")
	if rider == null:
		w.queue_free()
		await step_ticks(2)
		return
	assert_true(Vector2(rider.home_position.x, rider.home_position.z).distance_to(post) < 0.5,
		"its post is the record's (%s)" % rider.home_position.snappedf(0.1))
	# Lured 12 m past its post, out of the leash; the giant steps onto its post; it is hurt.
	rider.global_position = Vector3(post.x + out.x * 12.0, rider.global_position.y, post.y + out.y * 12.0)
	await step_ticks(2)
	await _move(w, post)
	await step_ticks(2)
	var hp_max := rider.entity.combatant.pools.health_max
	queue_hit("player", rider.entity_id, rider.global_position + Vector3(out.x, 0, out.y) * 2.0, 90.0)
	await step_ticks(1)
	assert_true(rider.entity.combatant.pools.health < hp_max, "hurt before the leash")
	d.update_now()
	assert_true(rider.is_returning(), "the leash sends it home")
	var giant := p.global_position
	# He leaves it be: it backs off his body and waits for its post.
	var wait_tick := -1
	var pinned_waiting := 0.0
	var ends_out := 0
	var was_returning := true
	for i in 60 * WAIT_S:
		await step_ticks(1)
		if not rider.entity.is_alive():
			break
		if was_returning and not rider.is_returning() and _flat2(rider.global_position, centre) > leash:
			ends_out += 1   # a return ended outside the leash: the director sends it home again
		was_returning = rider.is_returning()
		if wait_tick < 0 and rider.leash_waiting == "post":
			wait_tick = Sim.tick
		if wait_tick >= 0 and Sim.tick - wait_tick >= 60 and _gap(rider, p, giant_r, rider_r) < 0.5:
			pinned_waiting += 1.0 / 60.0
	var gap_wait := _gap(rider, p, giant_r, rider_r)
	print("    the giant on %s's picket, %d s with no blow: %d leash(es), %d heal(s), %d return(s) ended outside the leash; waiting '%s' %.1f m off his body, %.1f m from the camp's centre (leash %.0f); health %.0f / %.0f" % [
		RIDER.get_slice(".", 2), WAIT_S, leashed, heals, ends_out, rider.leash_waiting, gap_wait,
		_flat2(rider.global_position, centre), leash, rider.entity.combatant.pools.health, hp_max])
	assert_true(rider.entity.is_alive(), "the rider lives")
	assert_eq(ends_out, 0, "its return never ends outside the leash on its own")
	assert_true(rider.is_returning() and rider.leash_waiting == "post", "it waits for its post, still on its way home")
	assert_eq(leashed, 1, "leashed once (the review's probe: 12 in 30 s)")
	assert_eq(heals, 1, "healed once, %.0f s into the return (the probe: 11)" % EnemyActor.LEASH_HEAL_S)
	assert_true(pinned_waiting < 0.01, "not pinned against him once it waits (%.1f s within 0.5 m of his body)" % pinned_waiting)
	assert_true(gap_wait >= EnemyActor.LEASH_DETOUR_CLEAR_M - EnemyActor.LEASH_ARRIVE_M,
		"it stands off his body (%.1f m; pinned, it stood at -0.5)" % gap_wait)
	# Fix-up 1: he strikes it whenever it is within his reach - it answers.
	var answer_tick := -1
	var first_blow := -1
	var hp_answer := 0.0
	var knew_him := false
	var actions_before := rider_actions.size()
	var blows := 0
	var next_blow := 0
	var pinned_run := 0
	var pinned_longest := 0
	var outside_held := 0
	var outside_free := 0
	for i in 60 * BLOWS_S:
		if i >= next_blow and rider.entity.is_alive() and _gap(rider, p, giant_r, rider_r) <= BLOW_REACH_M:
			queue_hit("player", rider.entity_id, p.global_position, 40.0)
			blows += 1
			next_blow = i + BLOW_TICKS
			if first_blow < 0:
				first_blow = Sim.tick
		await step_ticks(1)
		if not rider.entity.is_alive():
			break
		if answer_tick < 0 and not rider.is_returning():
			answer_tick = Sim.tick
			hp_answer = rider.entity.combatant.pools.health
		elif answer_tick >= 0 and Sim.tick == answer_tick + 1:
			knew_him = rider.brain.target_id == "player" and rider.brain.aware
		if _gap(rider, p, giant_r, rider_r) < 0.5 and not rider.is_galloping():   # a charge's run goes through his legs
			pinned_run += 1
			pinned_longest = maxi(pinned_longest, pinned_run)
		else:
			pinned_run = 0
		if answer_tick >= 0 and _flat2(rider.global_position, centre) > leash and not rider.is_returning():
			if rider.leash_held_off():
				outside_held += 1
			else:
				outside_free += 1
	var acted := rider_actions.slice(actions_before)
	print("    then his blows (%d in %d s): it answered %d tick(s) after the first, health %.0f / %.0f then; actions %s; %d leash(es), %d heal(s) while he stays; %.1f s outside the leash held off it, %.1f s not; longest against his body out of a charge %.2f s" % [
		blows, BLOWS_S, answer_tick - first_blow, hp_answer, hp_max, acted, leashed, heals, outside_held / 60.0,
		outside_free / 60.0, pinned_longest / 60.0])
	assert_true(_flat(p.global_position, giant) < 1.0, "he stayed on its post (%s)" % p.global_position.snappedf(0.1))
	assert_true(rider.entity.is_alive(), "the rider lives through his blows")
	assert_true(first_blow >= 0 and answer_tick >= 0 and answer_tick - first_blow <= 2,
		"his first blow ends its wait at once (%d tick(s))" % (answer_tick - first_blow))
	assert_eq(rider.leash_answers, 1, "it answered once")
	assert_true(hp_answer < hp_max, "unhealed: the blow shows (%.0f / %.0f)" % [hp_answer, hp_max])
	assert_true(knew_him, "it knows who struck it")
	assert_true(not acted.is_empty(), "it turns on him (%s)" % [acted])
	assert_eq(leashed, 1, "still leashed once while he stays")
	assert_eq(heals, 1, "and healed once")
	assert_eq(outside_free, 0, "outside the leash, the giant on its post holds it off the leash")
	assert_true(pinned_longest < 60, "never pinned against him (%.2f s at most within 0.5 m of his body, out of a charge)" % (pinned_longest / 60.0))
	# He leaves, out past the pickets: nothing holds it off the leash any more, and the leash brings it back.
	await _move(w, post + out * 40.0)
	await step_ticks(1)
	assert_false(rider.leash_held_off(), "with its post free nothing holds it off the leash")
	var t_left := Sim.tick
	var back: bool = await TestWait.until(self, func() -> bool:
		return not rider.is_returning() and _flat2(rider.global_position, centre) <= leash, 60 * 20)
	print("    he leaves: after %.1f s %.1f m from the camp's centre, %.1f m from its post, returning %s; %d leash(es), %d heal(s) in all" % [
		(Sim.tick - t_left) / 60.0, _flat2(rider.global_position, centre), _flat2(rider.global_position, post),
		rider.is_returning(), leashed, heals])
	assert_true(back, "the leash holds it again: back inside the camp's leash, its return over (%.1f m from the centre, returning %s; a rider sent home round its fellows on the picket line rode to and fro short of its post)" % [
		_flat2(rider.global_position, centre), rider.is_returning()])
	assert_true(leashed <= 2, "at most the one leash that sent it back (%d in all)" % leashed)
	w.queue_free()
	await step_ticks(2)


static func _flat2(a: Vector3, c: Vector2) -> float:
	return Vector2(a.x - c.x, a.z - c.y).length()


## The gap between the rider's body and the giant's (negative: pressed into him).
static func _gap(rider: Node3D, giant: Node3D, giant_r: float, rider_r: float) -> float:
	return _flat(rider.global_position, giant.global_position) - giant_r - rider_r
