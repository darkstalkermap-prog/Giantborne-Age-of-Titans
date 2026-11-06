extends IntegrationSuite
## P30 (plan M6-M9 §2.10, §3.13 tests, decision 19): formations are lock groups at stages 4-6
## (profile target_rules.formation_lock). With a stage-4 giant: one candidate per formation
## ("formation:<id>", none for its members) plus its banner (flagged), the lone soldier as itself;
## the lock resolves to the focus member nearest the attack origin and the camera frames the
## formation's anchor; lock_label() reads "Pike Regiment (5)" and the banner's flag line; switching
## moves from the group to the banner and back; the lock releases (target_died) once no member is
## alive and not routed. At stage 3 the members are candidates of their own. The banner stays a
## target through the rank in front of it, and a heavy kills it.

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"

var f: Formation
var p: GiantPlayer


func after_each() -> void:
	if f != null:
		f.dissolve()
	await super()


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## A stage-`stage` giant at `pos` facing -Z and a formation of five pikemen in one rank facing -X
## at `pivot` (its files along Z, its banner 1.6 m behind at +X), AI off.
func _setup(stage: int, pos: Vector3, pivot: Vector3, ranks := 1) -> void:
	p = spawn_player(pos, 0.0)
	p.set_profile(_profile(stage))
	f = Formation.new()
	f.id = "test.lock"
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.banner_name = "Banner of the Test Pikes"
	f.ranks = ranks
	f.files = 5
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.place(pivot, PI * 0.5)
	Formation.register(f)
	for i in 5 * ranks:
		f.add_member(TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.lock_%d" % i, false, PI * 0.5), i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "test.lock_banner", false, PI * 0.5))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	p.camera_rig.yaw = 0.0
	await step_ticks(1)


func test_a_formation_is_one_candidate_with_its_banner_and_resolves_to_its_nearest_member() -> void:
	await _setup(4, Vector3(0, 0.05, 24), Vector3(0, 0, 0))
	var lone := spawn_soldier(Vector3(12, 0.05, 0), PI * 0.5, "test.lock_lone")
	await step_ticks(1)
	# below stage 4 the members are candidates of their own
	p.set_profile(_profile(3))
	var at3 := {}
	for c: Dictionary in p.targeting.gather_candidates(false):
		at3[str(c.id)] = true
	assert_false(at3.has("formation:test.lock"), "no group below stage 4")
	for m in f.members:
		assert_true(at3.has(m.entity_id), "at stage 3 %s is a candidate" % m.entity_id)
	p.set_profile(_profile(4))
	var ids := {}
	for c: Dictionary in p.targeting.gather_candidates(false):
		ids[str(c.id)] = c
	assert_true(ids.has("formation:test.lock"), "one candidate for the formation (%s)" % [ids.keys()])
	assert_true(bool((ids.get("formation:test.lock", {}) as Dictionary).get("group", false)), "flagged as a group")
	assert_true(ids.has("test.lock_banner") and bool(ids["test.lock_banner"].get("banner", false)),
		"its banner is a candidate of its own, flagged")
	assert_true(ids.has("test.lock_lone"), "the lone soldier is itself")
	for m in f.members:
		assert_false(ids.has(m.entity_id), "%s is folded into the group" % m.entity_id)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "formation:test.lock", "the giant locks the formation")
	assert_true(p.targeting.is_group_locked(), "a group lock")
	var nearest: EnemyActor = null
	for m in f.members:
		if nearest == null or m.global_position.distance_to(p.global_position) < nearest.global_position.distance_to(p.global_position):
			nearest = m
	assert_eq(p.targeting.locked_entity(), nearest.entity, "it resolves to the member nearest the attack origin")
	assert_eq(p.camera_rig.lock_target, nearest.entity, "the camera's target is that member")
	assert_true(p.camera_rig.lock_focus_point().is_equal_approx(f.anchor()), "framing the formation's anchor")
	assert_eq(p.targeting.lock_label(), "Pike Regiment (5)", "the lock line")
	p.targeting.switch_target(1)
	assert_eq(p.lock.target_id, "test.lock_banner", "switching moves to the banner")
	assert_eq(p.targeting.lock_label(), "⚑ Banner of the Test Pikes", "with its flag line")
	await step_ticks(12)   # the switch debounce (0.2 s)
	p.targeting.switch_target(-1)
	assert_eq(p.lock.target_id, "formation:test.lock", "and back to the formation")
	# two rout, three die: no member alive and not routed - the lock lets go
	(f.members[0] as EnemyActor).p30_force_rout()
	(f.members[1] as EnemyActor).p30_force_rout()
	await step_ticks(1)
	assert_eq(p.lock.target_id, "formation:test.lock", "routed members do not end the lock while others stand")
	assert_eq(p.targeting.lock_label(), "Pike Regiment (3)", "the count drops")
	for i in [2, 3, 4]:
		queue_hit("player", (f.members[i] as EnemyActor).entity_id, p.global_position, 100000.0)
	await step_ticks(2)
	assert_eq(p.lock.target_id, "", "the lock releases when none is left")
	assert_eq(str(lock_events[-1][3]) if not lock_events.is_empty() else "", "target_died", "as target_died")
	lone.queue_free()


## The banner stays a target through its rank: locked from in front of the formation it is in
## sight (soldiers never block the lock), the lock resolves to the banner itself (not the group's
## focus), it holds over time, and a heavy kills it. (The hit is the stage-4 heavy's event through
## the real resolution; a club heavy at stage 4 lands about 3 m in front of the giant, so landing a
## swing on human-sized targets beyond that is P31's stage movesets.)
func test_a_heavy_kills_the_locked_banner_through_one_rank() -> void:
	# the formation faces -X, toward the giant; its banner stands 1.6 m behind the rank, at x = 0
	await _setup(4, Vector3(-9.5, 0.05, 0), Vector3(-1.6, 0, 0))
	p.rotation.y = -PI * 0.5      # the giant faces +X
	p.camera_rig.yaw = -PI * 0.5
	await step_ticks(2)
	var b := f.banner
	p.targeting.try_lock()
	if p.lock.target_id != b.entity_id:
		p.targeting.switch_target(1)
	if p.lock.target_id != b.entity_id:
		await step_ticks(12)
		p.targeting.switch_target(-1)
	assert_eq(p.lock.target_id, b.entity_id, "the banner is locked through its rank")
	assert_true(p.targeting.is_visible(b.entity), "in sight: the rank in front does not hide it")
	assert_eq(p.targeting.locked_entity(), b.entity, "the lock resolves to the banner, not a focus member")
	await step_ticks(10)
	assert_eq(p.lock.target_id, b.entity_id, "and holds")
	var heavy := GameData.get_action("ability.heavy_1")
	queue_hit(p.entity.entity_id, b.entity_id, p.global_position, heavy.power * 10.0,
		PackedStringArray(heavy.tags) + PackedStringArray(["Heavy"]), float(p.profile.height_m))
	await step_ticks(1)
	assert_false(b.entity.is_alive(), "a heavy kills the banner")
	assert_eq(p.lock.target_id, "", "its lock ends with it")
	assert_false(f.banner_alive(), "the formation has lost its banner")
