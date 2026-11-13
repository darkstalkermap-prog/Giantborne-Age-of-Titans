extends IntegrationSuite
## M9 gate (lane review; the review's major finding): a war-camp picket rider whose post a giant stands on, at
## the edge of the camp's leash. On the real world (scenes/world/world.tscn, deterministic streaming), Aldmere at
## war, a stage-6 giant that takes no damage: the middle picket's rider, lured past its post out of the camp's
## leash, is sent home by the leash while the giant steps onto its post. W23 (P39f) ended its return at his edge -
## outside the leash, since the post stands a few metres inside it and he is 3.7 m wide - the director sent it
## home again at its next update and each early end healed it to full: 12 leashes and 11 heals in 30 s, pinned
## 4.1 m from his centre (the review's probe). Now a return never ends early outside the leash: the rider backs
## off his body and waits for its post, and while he stays it is leashed once and healed once (LEASH_HEAL_S into
## the return; the blows after it stay), and it is not pinned against him. When he leaves, it rides home and its
## return ends at its post.
## The camp's centre and leash and the picket's post come from the encounter's record at run time (the shield
## wall's place may change; the riders' pickets are what this test is about).

const SCENE := "res://scenes/world/world.tscn"
const CAMP := "encounter.aldmere_war_camp"
const RIDER := "world.aldmere.camp_rider_2"

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


func test_a_rider_whose_picket_the_giant_stands_on_is_leashed_once_and_waits_off_him() -> void:
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
	var wait_tick := -1
	var pinned_waiting := 0.0
	var pinned := 0.0
	var ends_out := 0
	var was_returning := true
	var giant := p.global_position
	for i in 60 * 30:
		if i == 60 * 12 or i == 60 * 20:
			queue_hit("player", rider.entity_id, rider.global_position + Vector3(0, 0, 2), 40.0)   # his blows while it waits
		await step_ticks(1)
		if not is_instance_valid(rider) or not rider.entity.is_alive():
			break
		if was_returning and not rider.is_returning() \
				and Vector2(rider.global_position.x, rider.global_position.z).distance_to(centre) > leash:
			ends_out += 1   # a return ended outside the leash: the director sends it home again
		was_returning = rider.is_returning()
		if wait_tick < 0 and str(rider.get("leash_waiting")) == "post":
			wait_tick = Sim.tick
		var gap := _flat(rider.global_position, p.global_position) - giant_r - rider_r
		if gap < 0.5:
			pinned += 1.0 / 60.0
			if wait_tick >= 0 and Sim.tick - wait_tick >= 60:
				pinned_waiting += 1.0 / 60.0
	assert_true(is_instance_valid(rider) and rider.entity.is_alive(), "the rider lives through the 30 s")
	if not is_instance_valid(rider):
		w.queue_free()
		await step_ticks(2)
		return
	var gap_end := _flat(rider.global_position, p.global_position) - giant_r - rider_r
	print("    the giant on %s's picket for 30 s: %d leash(es), %d heal(s), %d return(s) ended outside the leash, %.1f s against him; waiting '%s' %.1f m off his body, %.1f m from the camp's centre (leash %.0f); health %.0f / %.0f" % [
		RIDER.get_slice(".", 2), leashed, heals, ends_out, pinned, str(rider.get("leash_waiting")), gap_end,
		Vector2(rider.global_position.x, rider.global_position.z).distance_to(centre), leash,
		rider.entity.combatant.pools.health, hp_max])
	assert_true(_flat(p.global_position, giant) < 1.0, "he stayed on its post (%s)" % p.global_position.snappedf(0.1))
	assert_eq(ends_out, 0, "its return never ends outside the leash")
	assert_true(rider.is_returning() and wait_tick >= 0, "it waits for its post, still on its way home")
	assert_eq(leashed, 1, "leashed once while he stays (the review's probe: 12 in 30 s)")
	assert_eq(heals, 1, "healed once while he stays (the probe: 11)")
	assert_true(rider.entity.combatant.pools.health < hp_max, "his blows after its heal stay")
	assert_true(pinned_waiting < 0.01, "not pinned against him once it waits (%.1f s within 0.5 m of his body)" % pinned_waiting)
	assert_true(gap_end >= EnemyActor.LEASH_DETOUR_CLEAR_M - EnemyActor.LEASH_ARRIVE_M,
		"it stands off his body (%.1f m; pinned, it stood at -0.5)" % gap_end)
	# He leaves, out past the pickets: it rides home and its return ends at its post, with no second heal.
	await _move(w, post + out * 40.0)
	var home := false
	for i in 60 * 15:
		await step_ticks(1)
		if not rider.is_returning():
			home = true
			break
	assert_true(home, "with its post free it rides home")
	assert_true(_flat(rider.global_position, Vector3(post.x, 0, post.y)) <= EnemyActor.LEASH_ARRIVE_M + 0.3,
		"its return ends at its post (%.1f m from it)" % _flat(rider.global_position, Vector3(post.x, 0, post.y)))
	assert_eq(heals, 1, "no second heal on arrival")
	assert_eq(leashed, 1, "still leashed once")
	w.queue_free()
	await step_ticks(2)
