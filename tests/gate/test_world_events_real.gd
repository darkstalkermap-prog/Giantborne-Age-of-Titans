extends IntegrationSuite
## M8 gate (F2 with F20, F19; plan M6-M9 §2.13, §5.10): the world events on the real world (scenes/world/world.tscn,
## deterministic streaming, the living world on), the regressions of the M8 gate review:
##   * F2: a Millford raid that starts as a stage-4 giant grows at the Kingsgate shrine and that the giant
##     then leaves behind (suspended, out of play) does not keep the siege of Skarn from starting for a
##     stage-6 giant on Skarn's green with Ulfra's plea accepted; the raid still runs (it waits);
##   * F20: Aldmere's army column marching the King's Road far off does not hold the siege back either;
##   * F19: the siege started, a checkpoint's world saved, a quit to the title and a continue: the siege
##     resumes (its run counted once), its line comes back, and breaking its engines saves Skarn - its quest
##     is won, not stuck.

const SCENE := "res://scenes/world/world.tscn"
const SIEGE := "event.siege_of_skarn"
const RAID := "event.millford_raid"
const COLUMN := "event.army_column"
const KINGSGATE_PAD := Vector2(-300.0, 763.5)
const SKARN_GREEN := Vector2(440.0, -640.0)
const COLUMN_SPOT := Vector2(560.0, 440.0)


func after_each() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _world() -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	w.player().entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	return w


func _go(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 300.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 60.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _stage(p: GiantPlayer, stage: int) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			p.set_profile(rec)


func _director(w: WorldRoot) -> WanderDirector:
	return w.get_node_or_null("WanderDirector") as WanderDirector


## Steps until the director's checks have run (every CHECK_TICKS) `n` times.
func _checks(n := 2) -> void:
	await step_ticks(WanderDirector.CHECK_TICKS * n + 1)


func _engines(w: Node) -> Array:
	return w.get_tree().get_nodes_in_group(SiegeEngine.GROUP).filter(func(n: Node) -> bool:
		return str((n as SiegeEngine).siege_group) == "skarn_siege")


## Breaks a prop or an engine with heavy blows from `attacker` (at most 80).
func _break(world_id: String, attacker: String) -> bool:
	for i in 80:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = attacker
		h.target_id = world_id
		h.power = 1200.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "siege"
		h.attacker_growth_stage = 6
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	return WorldState.is_destroyed(world_id)


func test_a_raid_left_behind_lets_the_siege_of_skarn_start() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	WorldState.set_flag("world.kingsgate.lit", true)
	var w := _world()
	var p := w.player()
	_stage(p, 4)
	var wd := _director(w)
	assert_true(wd != null, "the WanderDirector")
	if wd == null:
		return
	# the main thread's grow4 stage: the giant grows at the Kingsgate shrine, 152 m from Millford
	await _go(w, KINGSGATE_PAD)
	await _checks(3)
	var raid: WorldEvent = wd.events[RAID]
	assert_true(raid.is_running(), "the Millford raid starts as the stage-4 giant passes")
	# away to Skarn at stage 6, Ulfra's plea accepted
	WorldState.set_flag("world.skarn.plea_accepted", true)
	_stage(p, 6)
	await _go(w, SKARN_GREEN)
	await _checks(2)
	var siege: WorldEvent = wd.events[SIEGE]
	assert_true(raid.is_running() and not wd.in_play(raid), "the raid left behind still runs, out of play (%s)" % raid.state)
	assert_true(siege.is_running(), "the siege of Skarn starts: the raid left behind holds no slot (M8 gate, F2)")
	assert_true(wd.in_play(siege), "the siege is the event in play")
	assert_eq(wd.running_event(), siege, "running_event() names it")
	await _checks(2)
	assert_eq(_engines(w).size(), 5, "its five engines appear with it")
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	assert_eq(Quests.stage_of("quest.siege_of_skarn"), "defend", "its quest: break the siege line")
	w.queue_free()
	await get_tree().process_frame


func test_the_army_column_far_off_lets_the_siege_start() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	WorldState.set_flag("faction.aldmere.hostile", true)
	WorldState.set_flag("oath.crown.outcome", "sabotage")
	var w := _world()
	var p := w.player()
	_stage(p, 6)
	var wd := _director(w)
	await _go(w, COLUMN_SPOT)
	await _checks(2)
	var column: WorldEvent = wd.events[COLUMN]
	assert_true(column.is_running(), "Aldmere's column marches from the toll fort's east road")
	WorldState.set_flag("world.skarn.plea_accepted", true)
	await _go(w, SKARN_GREEN)
	await _checks(2)
	var siege: WorldEvent = wd.events[SIEGE]
	assert_true(column.is_running() and not wd.in_play(column), "the column marches on, far off and out of play")
	assert_true(siege.is_running(), "the siege starts while the column marches (M8 gate, F20)")
	assert_eq(wd.running_event(), siege, "the siege is the event in play")
	w.queue_free()
	await get_tree().process_frame


func test_the_siege_survives_a_save_and_a_continue() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	WorldState.set_flag("world.skarn.plea_accepted", true)
	var w := _world()
	_stage(w.player(), 5)
	await _go(w, SKARN_GREEN)
	await _checks(3)
	var wd := _director(w)
	var siege: WorldEvent = wd.events[SIEGE]
	assert_true(siege.is_running(), "the siege starts (the plea accepted, stage 5)")
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.ACTIVE, "its quest is active")
	# the giant leaves to grow at the Standing Stones: the growth's checkpoint saves the world as it is
	var saved := WorldState.to_save_dict()
	# quit to the title, then continue (main.gd frees the level on each mode change)
	Events.mode_change_requested.emit("title", {})
	w.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	WorldState.clear()
	WorldState.from_save_dict(saved)
	Events.mode_change_requested.emit("continue", {})
	assert_false(WanderDirector.is_carried("level.world", SIEGE), "the continue carries nothing")
	var w2 := _world()
	_stage(w2.player(), 6)
	var wd2 := _director(w2)
	var siege2: WorldEvent = wd2.events[SIEGE]
	assert_true(siege2.is_running(), "the saved siege is resumed on the level's load (M8 gate, F19)")
	assert_eq(int(WorldState.get_flag("%s.runs" % SIEGE, 0)), 1, "its run counted once")
	await _go(w2, SKARN_GREEN)
	await _checks(2)
	assert_eq(siege2.state, WorldEvent.RUNNING, "back at Skarn its attempt begins again")
	assert_false(siege2.copies.is_empty(), "its line comes back")
	var engines := _engines(w2)
	assert_eq(engines.size(), 5, "its five engines stand")
	for e: SiegeEngine in engines:
		assert_true(await _break(e.world_id, w2.player().entity.entity_id), "%s is broken" % e.world_id)
	var done: bool = await TestWait.until(self, func() -> bool: return not siege2.is_running(), 60 * 20)
	assert_true(done, "the siege ends")
	assert_eq(str(WorldState.get_flag("%s.outcome" % SIEGE, "")), "saved", "Skarn is saved")
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.COMPLETED, "its quest is won, not stuck")
	w2.queue_free()
	await get_tree().process_frame
