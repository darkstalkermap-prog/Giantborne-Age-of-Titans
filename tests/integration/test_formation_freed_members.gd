extends IntegrationSuite
## M8 gate (F23, F25; plan M6-M9 §2.10, §2.8): a formation's members come and go without its readers
## tripping over the gone.
##   * A member whose node is freed (the director frees a corpse corpse_free_s after the death) stays in
##     no reader's way in the window before the formation's next update prunes it: the lock line's count,
##     the group lock the giant holds (alive, its focus member, its label - it holds while members stand),
##     the march's living count (AmbienceDirector), the crowd renderer's frame, the brace striker's and
##     the focus member's choice, cohesion, the free slots and joining - no script error, and the living
##     counted as living.
##   * EncounterDirector takes a corpse it frees out of its formation (Formation.remove_member): the
##     update that frees it leaves the formation no entry of it.
##   * One re-path of a formation costs one path query of the tick's budget (F25: NavQuery.path counts its
##     own, and the formation's advance spent a second one for it).

const PIKEMAN := "res://scenes/enemies/pikeman.tscn"
const BANNERMAN := "res://scenes/enemies/bannerman.tscn"
const FORMATION_TEST := "res://scenes/test/formation_test.tscn"

var f: Formation


func after_each() -> void:
	if f != null:
		f.dissolve()
	f = null
	for x in Formation.live():
		x.dissolve()
	await super()


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _kill(id: String, attacker: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = attacker
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


func test_every_reader_skips_a_freed_member_before_the_prune() -> void:
	var p := spawn_player(Vector3(0, 0.05, 24), 0.0)
	p.set_profile(_profile(4))
	f = Formation.new()
	f.id = "test.freed"
	f.kind = "pike"
	f.display_name = "Pike Regiment"
	f.ranks = 1
	f.files = 5
	f.rank_spacing_m = 1.6
	f.file_spacing_m = 1.4
	f.brace_m = 7.0
	f.brace_action = "ability.formation_brace_pike"
	f.place(Vector3.ZERO, PI * 0.5)
	Formation.register(f)
	var pikes: Array[EnemyActor] = []
	for i in 5:
		var e := TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.freed_%d" % i, false, PI * 0.5)
		pikes.append(e)
		f.add_member(e, i)
	f.set_banner(TestSpawn.enemy(world, BANNERMAN, f.slot_position(Formation.BANNER_SLOT), "test.freed_banner", false, PI * 0.5))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 40)
	p.camera_rig.yaw = 0.0
	await step_ticks(1)
	p.targeting.try_lock()
	assert_eq(p.lock.target_id, "formation:test.freed", "the giant locks the formation as a group")
	assert_eq(f.living_count(), 5, "five living")
	var renderer := CrowdRenderer.new()
	renderer.formation = f
	world.add_child(renderer)
	# The member nearest the giant's attack origin (the group's focus) goes as the director frees a corpse:
	# its node leaves the tree and is freed at the frame's end; the formation still lists it.
	var gone := f.focus_member(p.global_position + Vector3.UP * p.attack_origin.y)
	assert_true(gone != null, "a focus member")
	var gone_id := gone.entity_id
	gone.get_parent().remove_child(gone)
	gone.queue_free()
	await get_tree().process_frame
	var listed := 0
	for m in f.members:
		if not is_instance_valid(m):
			listed += 1
	assert_eq(listed, 1, "the freed member is still listed (the window before the prune)")
	# Every reader, as each frame and each tick would read it.
	assert_eq(f.living_count(), 4, "the lock line's count skips the freed member")
	assert_eq(f.lock_label(), "Pike Regiment (4)", "the lock line")
	assert_eq(f.member_count(), 5, "four rank-and-file and the banner")
	var focus := f.focus_member(p.global_position)
	assert_true(focus != null and is_instance_valid(focus) and focus.entity_id != gone_id, "a living focus member")
	var near := f.nearest_living(p.global_position)
	assert_true(near != null and is_instance_valid(near) and near.entity_id != gone_id, "a living nearest member")
	assert_near(f.cohesion(), 4.0 / 5.0, 1e-6, "cohesion counts the living")
	assert_true(f.free_slots().size() == 1, "the freed member's slot is free (%s)" % [f.free_slots()])
	assert_eq(f.all_members().size(), 5, "every member that is still a node")
	var march_count := -1
	for x: Formation in Formation.live():
		if x == f:
			march_count = x.living_count()   # AmbienceDirector._update_marches' reader
	assert_eq(march_count, 4, "the march reads the living")
	renderer.refresh()
	assert_true(renderer.promoted.size() + renderer.crowded.size() <= 5, "the crowd renderer draws the members still there")
	# The group lock: alive while members stand, on a living focus member, its line.
	p.targeting.call("_p30_maintain", 1.0 / 60.0)
	assert_eq(p.lock.target_id, "formation:test.freed", "the lock holds (members stand)")
	var locked := p.targeting.locked_entity()
	assert_true(locked != null and locked.entity_id != gone_id and locked.is_alive(), "the lock resolves to a living member")
	assert_eq(p.targeting.lock_label(), "Pike Regiment (4)", "the HUD's lock line")
	p.targeting.call("_p30_on_any_entity_died", gone_id)
	assert_true(p.lock.is_locked(), "a gone member does not release the group lock")
	# A soldier of the faction joins the freed slot.
	var joiner := TestSpawn.enemy(world, PIKEMAN, f.slot_position(0) + Vector3(0, 0, 6), "test.freed_joiner", false, PI * 0.5)
	await step_ticks(1)
	assert_true(f.try_join(joiner), "the freed slot takes a joiner")
	assert_eq(f.living_count(), 5, "five living again")
	# The banner goes the same way: the banner's readers.
	var banner := f.banner
	banner.get_parent().remove_child(banner)
	banner.queue_free()
	await get_tree().process_frame
	assert_false(f.banner_alive(), "no banner")
	assert_true(f.focus_member(p.global_position, true) != null, "the focus falls back to a member")
	f.update(Sim.tick, p)
	assert_eq(f.living_count(), 5, "the update prunes and counts the living")
	renderer.queue_free()


func test_the_director_takes_a_freed_corpse_out_of_its_formation() -> void:
	var lv := (load(FORMATION_TEST) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	p.global_position = Vector3(-155, 0.05, 40)
	var d := lv.director()
	d.corpse_free_s = 0.05
	d.force_activate("encounter.formation_test_shields")
	d.update_now()
	d.check_ticks = 100000   # only this test's update_now() frees the corpse
	d.update_now()
	await step_ticks(2)
	var fs := d.formations()
	assert_eq(fs.size(), 1, "the shield wall stands")
	if fs.is_empty():
		return
	f = fs[0]
	var victim: EnemyActor = f.members[0]
	var vid := victim.entity_id
	var before := f.members.size()
	_kill(vid, p.entity.entity_id)
	await step_ticks(int(ceil(0.05 * 60.0)) + 2)
	assert_eq(d.member_status(vid), EncounterDirector.DEAD, "the member died")
	d.update_now()   # frees the corpse (corpse_free_s)
	assert_true(d.spawned(vid) == null, "its corpse is freed")
	assert_false(f.members.has(victim), "the formation no longer lists it")
	assert_eq(f.members.size(), before - 1, "one member fewer")
	assert_false(f.slot_of.has(vid), "nor its slot")
	await get_tree().process_frame
	assert_eq(f.living_count(), before - 1, "the living counted after the free")


func test_one_formation_repath_costs_one_query() -> void:
	var lv := (load(FORMATION_TEST) as PackedScene).instantiate() as LevelRoot
	world.add_child(lv)
	await step_ticks(2)
	var p := lv.player()
	p.global_position = Vector3(-155, 0.05, 40)
	var d := lv.director()
	d.force_activate("encounter.formation_test_shields")
	d.update_now()
	await step_ticks(30)
	var fs := d.formations()
	assert_eq(fs.size(), 1, "the shield wall stands")
	if fs.is_empty():
		return
	f = fs[0]
	assert_true(NavQuery.has_navigation(lv, 1), "the level has its human-layer navigation")
	f.advance_mps = 1.0
	f.advance_m = 100.0
	f.threat_pos = f.pivot + Formation.forward_of(f.facing_yaw) * 40.0
	f.set("_path", PackedVector3Array())
	var before_total := NavQuery.queries_total
	var before_tick := NavQuery.used_this_tick(lv)
	f.call("_advance", Sim.tick, 0.1)
	assert_false((f.get("_path") as PackedVector3Array).is_empty(), "the formation asked one path")
	assert_eq(NavQuery.queries_total - before_total, 1, "one path query")
	assert_eq(NavQuery.used_this_tick(lv) - before_tick, 1, "it costs one of the tick's budget")


## The crowd renderer draws far members as a crowd (their rigs hidden): one the director frees (taken out
## of its formation first) and one freed while still listed are let go of, and release_all() skips them.
func test_the_crowd_renderer_lets_go_of_freed_members_it_drew() -> void:
	var stand_in := Node3D.new()
	stand_in.name = "GiantStandIn"
	stand_in.position = Vector3(0, 0.05, 120)   # far: every member is drawn in the crowd
	world.add_child(stand_in)
	stand_in.add_to_group("player")
	f = Formation.new()
	f.id = "test.freed_crowd"
	f.kind = "pike"
	f.ranks = 2
	f.files = 3
	f.place(Vector3(0, 0, -20), PI)
	var pikes: Array[EnemyActor] = []
	for i in 6:
		var e := TestSpawn.enemy(world, PIKEMAN, f.slot_position(i), "test.freed_crowd_%d" % i, false, PI)
		pikes.append(e)
		f.add_member(e, i)
	var r := CrowdRenderer.new()
	r.formation = f
	world.add_child(r)
	r.set_process(false)   # only these refreshes: a member freed between two frames (a deferred despawn)
	await step_ticks(1)
	r.refresh()
	assert_eq(r.crowded.size(), 6, "six members in the crowd, their rigs hidden")
	# One the director frees: out of the formation first (Formation.remove_member), then freed.
	var a := pikes[0]
	f.remove_member(a)
	a.get_parent().remove_child(a)
	a.queue_free()
	# One freed while the formation still lists it (before its prune).
	var b := pikes[1]
	b.get_parent().remove_child(b)
	b.queue_free()
	await get_tree().process_frame
	r.refresh()
	assert_eq(r.crowded.size(), 4, "the four left in the crowd")
	var c := pikes[2]
	c.get_parent().remove_child(c)
	c.queue_free()
	await get_tree().process_frame
	r.release_all()
	assert_eq(r.crowded.size(), 0, "every rig given back, the freed skipped")
	r.queue_free()
