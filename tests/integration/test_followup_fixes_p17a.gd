extends IntegrationSuite
## P17a: regression tests for the follow-ups docs/plans/FOLLOWUPS.md gives the Valley bot package.
##   * The test runner stalled when a suite did not compile (it called new() on the broken script);
##     such a suite is now a failure of its own (TestRunner.instantiate_suite).
##   * The encounter spawn hitch: the scenes a level's encounters spawn load with the level (a cache
##     shared by every director), and the Sim hook spawns at most SPAWNS_PER_TICK members per tick
##     (forced activations and update_now() still spawn at once).
##   * The slice's completion checkpoint waited for aware enemies, so Quit to title on the end screen
##     lost it; it is now taken with enemies aware, and a quit to the title commits it if anything
##     else still holds it back.
##   * Pad A on the death screen confirmed at once, so a player mashing jump (or LT+A, Heavy
##     Footfall) skipped the death screen; the confirm now waits a second after the death.
## And one bug the Valley bot found: an encounter member the director had taken out of the tree
## (freed at the end of the frame) read its global position when a giant's ability started in the
## same tick (an engine error); EnemyActor's global-bus handlers now return out of the tree.

const FLOW := "res://scenes/test/flow_test_level.tscn"
const DIRECTOR_LEVEL := "res://scenes/test/director_test.tscn"
const WOLVES := "encounter.director_test_wolves"
const SOLDIERS := "encounter.director_test_soldiers"
const PROBE_DIR := "user://p17a_runner_probe"
const MainScript := preload("res://scripts/main.gd")
const Fx := preload("res://tests/support/quest_fixtures.gd")

var level: Node3D
var spawn_ticks: Array = []        ## [tick, entity id] from member_spawned
var resets: Array[String] = []
var reloads: Array[String] = []


func before_each() -> void:
	await super()
	level = null
	spawn_ticks.clear()
	resets.clear()
	reloads.clear()
	Events.sandbox_reset_requested.connect(_on_reset)
	Events.reload_checkpoint_requested.connect(_on_reload)


func after_each() -> void:
	for sig: Signal in [Events.sandbox_reset_requested, Events.reload_checkpoint_requested]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if level != null and is_instance_valid(level):
		level.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	level = null
	await super()


func _on_reset(reason: String) -> void:
	resets.append(reason)


func _on_reload(reason: String) -> void:
	reloads.append(reason)


func _on_member_spawned(_encounter_id: String, entity_id: String, node: Node3D) -> void:
	spawn_ticks.append([Sim.tick, entity_id])
	if "ai_enabled" in node:
		node.set("ai_enabled", false)


static func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# --------------------------------------------------------------------------- the test runner

## FOLLOWUPS (wave 6): a suite with a parse error stalled the runner until check.sh's time limit.
## instantiate_suite reports it (the runner counts it as a failure and goes on); a good suite still
## instantiates, and a script that is not a suite is refused.
func test_a_suite_that_does_not_compile_is_a_failure_not_a_stall() -> void:
	var broken := PROBE_DIR.path_join("test_broken_suite.gd")
	var good := PROBE_DIR.path_join("test_good_suite.gd")
	var other := PROBE_DIR.path_join("test_not_a_suite.gd")
	_write(broken, "extends TestSuite\n\nfunc test_oops() -> void:\n\tvar x := = 3\n")
	_write(good, "extends TestSuite\n\nfunc test_fine() -> void:\n\tassert_true(true, \"fine\")\n")
	_write(other, "extends RefCounted\n\nvar x := 1\n")
	var bad := TestRunner.instantiate_suite(broken)
	TestRunner.take_logged_errors()   # the parse error the engine reports while loading it
	assert_true(bad.suite == null, "a suite that does not compile is not instantiated")
	assert_true(str(bad.error).contains("does not compile"), "it is reported (%s)" % bad.error)
	assert_true(str(bad.error).begins_with(broken), "with its path")
	var made := TestRunner.instantiate_suite(good)
	assert_true(made.suite is TestSuite and str(made.error) == "", "a good suite instantiates (%s)" % made.error)
	if made.suite is Node:
		(made.suite as Node).free()
	var refused := TestRunner.instantiate_suite(other)
	assert_true(refused.suite == null and str(refused.error).contains("is not a TestSuite"),
		"a script that is not a suite is refused (%s)" % refused.error)
	var missing := TestRunner.instantiate_suite(PROBE_DIR.path_join("test_missing.gd"))
	TestRunner.take_logged_errors()
	assert_true(missing.suite == null and str(missing.error).contains("failed to load"), "a missing file too")
	assert_eq(TestRunner.list_suites(PROBE_DIR), PackedStringArray([broken, good, other]),
		"the runner lists all three (sorted) and reports the broken one in its place")
	for path in [broken, good, other]:
		DirAccess.remove_absolute(path)


# --------------------------------------------------------------------------- the spawn hitch

## FOLLOWUPS (wave 7, P14's measurements): an encounter's activation spawned every member in one tick
## (13-25 ms) and the first load of an archetype's scene cost 100-150 ms. The level's encounter
## scenes are cached when the level loads, and the Sim hook spreads a proximity activation over
## ticks (SPAWNS_PER_TICK per tick); update_now() and forced activations spawn at once.
func test_encounter_scenes_load_with_the_level_and_spawns_spread_over_ticks() -> void:
	level = (load(DIRECTOR_LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	var lv := level as LevelRoot
	var d := lv.director()
	d.member_spawned.connect(_on_member_spawned)
	var paths := d.scene_paths()
	assert_true(paths.has("res://scenes/enemies/wolf.tscn") and paths.has("res://scenes/enemies/soldier.tscn"),
		"the level's encounters spawn wolves and soldiers (%s)" % paths)
	for path in paths:
		assert_true(EncounterDirector.is_scene_cached(path), "%s was loaded with the level" % path.get_file())
	assert_eq(d.preload_scenes(), 0, "a second preload loads nothing (the cache is shared)")
	assert_eq(EncounterDirector.SPAWNS_PER_TICK, 2, "two members per tick")
	var p := lv.player()
	p.router.use_injection = true
	await step_ticks(2)
	GameSession.place_player(p, Transform3D(Basis.IDENTITY, Vector3(-35, 0.05, -8)))   # 22 m from the wolves
	var all_up: bool = await TestWait.until(self, func() -> bool: return spawn_ticks.size() >= 3, 40)
	assert_true(all_up, "the wolves spawned (%s)" % [spawn_ticks])
	assert_eq(d.encounter_state(WOLVES), EncounterDirector.ACTIVE, "the encounter is active")
	var by_tick := {}
	for e: Array in spawn_ticks:
		by_tick[int(e[0])] = int(by_tick.get(int(e[0]), 0)) + 1
	var ticks: Array = by_tick.keys()
	ticks.sort()
	assert_eq(ticks.size(), 2, "the three wolves spawned over two ticks (%s)" % [spawn_ticks])
	if ticks.size() == 2:
		assert_eq(int(by_tick[ticks[0]]), 2, "two on the first")
		assert_eq(int(by_tick[ticks[1]]), 1, "the third on the next")
		assert_eq(int(ticks[1]) - int(ticks[0]), 1, "on the very next tick")
	spawn_ticks.clear()
	d.force_activate(SOLDIERS)
	d.update_now()
	assert_eq(spawn_ticks.size(), 3, "a forced activation with update_now() spawns all three soldiers at once")
	for e: Array in spawn_ticks:
		assert_eq(int(e[0]), Sim.tick, "%s in this tick" % e[1])


# --------------------------------------------------------------------------- the completion save

func _start_flow_valley() -> GiantPlayer:
	GameSession.persist = true
	GameSession.level_override = FLOW
	GameSession.start_new_valley()
	Fx.install([Fx.quest("quest.test_end", [Fx.stage("crown", Fx.flag_cond("slice.crown_claimed"), 50)],
		{"on_complete_flags": {"slice.completed": true}})])
	Fx.activate(["quest.test_end"], [], "quest.test_end")
	level = (load(FLOW) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(2)
	return p


static func _saved_flags() -> Dictionary:
	var r := SaveSlots.read()
	if not bool(r.ok):
		return {}
	return ((r.data as Dictionary).get("world", {}) as Dictionary).get("flags", {})


## FOLLOWUPS (M4 review): the crown taken with an enemy aware nearby deferred the completion
## checkpoint, and Quit to title on the end screen then lost it. Now the completion is saved in the
## same tick with the enemy aware; and a completion still held back by something else (the giant
## holding a body) is committed when the player quits to the title. An ordinary pending checkpoint
## still waits for its blockers and is not written by the quit.
func test_the_completed_slice_is_saved_with_enemies_aware_and_on_quit_to_title() -> void:
	var p := await _start_flow_valley()
	var guard := TestSpawn.stub_enemy(level, p.global_position + Vector3(0, 0.05, -12), "test.p17a.warden")
	await step_ticks(1)
	guard.brain.aware = true
	assert_true(GameSession.checkpoint_blockers().has("aware:test.p17a.warden"), "an aware enemy 12 m away")
	var before := GameSession.checkpoints_taken
	WorldState.try_set_flag("slice.crown_claimed", true)
	await step_ticks(1)
	assert_true(Quests.is_complete("quest.test_end"), "the slice is complete")
	assert_eq(GameSession.checkpoints_taken, before + 1, "its checkpoint is taken in the same tick")
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")
	assert_eq(str(GameSession.checkpoint_doc.checkpoint.reason), "quest_complete", "the completion checkpoint")
	assert_eq(_saved_flags().get("slice.completed"), true, "the save on disk has the completed slice")
	ScreenStack.close_all_static()
	# An ordinary request still waits for the aware enemy, and quitting does not write it.
	GameSession.request_checkpoint("quest_stage")
	await step_ticks(2)
	assert_eq(str(GameSession.pending_checkpoint().get("reason", "")), "quest_stage", "an ordinary checkpoint waits")
	WorldState.set_flag("test.p17a.after", true)
	GameSession.go_to_title()
	assert_false(_saved_flags().has("test.p17a.after"), "quitting does not write an ordinary pending checkpoint")
	assert_true(GameSession.scene_reloads.has("title"), "the title was asked for")
	# A completion held back by a hold: the quit commits it.
	level.queue_free()
	await get_tree().process_frame
	level = null
	p = await _start_flow_valley()
	p.controller.holding_id = "test.p17a.body"
	WorldState.try_set_flag("slice.crown_claimed", true)
	await step_ticks(2)
	assert_true(Quests.is_complete("quest.test_end"), "complete again (a new game)")
	assert_true(bool(GameSession.pending_checkpoint().get("completion", false)), "the completion waits for the hold")
	assert_false(_saved_flags().has("slice.completed"), "not saved yet")
	ScreenStack.close_all_static()
	Events.mode_change_requested.emit("title", {})   # the end screen's Quit to title
	assert_eq(_saved_flags().get("slice.completed"), true, "Quit to title saved the completed slice first")
	assert_true(GameSession.pending_checkpoint().is_empty(), "and nothing waits any more")
	p.controller.holding_id = ""


# --------------------------------------------------------------------------- the death screen

static func _pad_a() -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = JOY_BUTTON_A
	e.pressed = true
	return e


static func _enter() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_ENTER
	e.pressed = true
	return e


## FOLLOWUPS (M4 review): pad A (jump, and LT+A: Heavy Footfall) confirmed the death screen at once,
## so a player mashing it skipped the screen. The confirm is now swallowed (nothing happens) for a
## second after the death; then pad A or Enter confirms, once per press. A press while a menu is open
## is not the death screen's.
func test_the_death_screen_ignores_its_confirm_for_a_second() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await step_ticks(2)
	var m: Node = MainScript.new()
	assert_false(m.handle_death_confirm(_pad_a(), p, false), "alive: pad A is a jump, not a confirm")
	queue_hit("tester", "player", p.global_position + Vector3(0, 0, -2), 50000.0,
		PackedStringArray(["Melee", "Unblockable"]))
	await step_ticks(1)
	assert_eq(p.controller.state, CombatController.State.DEAD, "the giant died")
	var died := p.entity.died_tick
	assert_true(died > 0, "at tick %d" % died)
	assert_true(m.handle_death_confirm(_pad_a(), p, false), "pad A right after the death is swallowed")
	assert_true(resets.is_empty() and reloads.is_empty(), "and does nothing")
	assert_false(MainScript.death_confirm_ready(p, Sim.tick), "the screen is not ready")
	await step_ticks(died + 58 - Sim.tick)
	assert_true(m.handle_death_confirm(_enter(), p, false), "Enter just before the second")
	assert_true(resets.is_empty(), "still nothing")
	await step_ticks(died + 60 - Sim.tick)
	assert_true(MainScript.death_confirm_ready(p, Sim.tick), "a second after the death the screen is ready")
	assert_false(m.handle_death_confirm(_pad_a(), p, true), "a press while a menu is open is the menu's")
	assert_true(resets.is_empty(), "nothing yet")
	assert_true(m.handle_death_confirm(_pad_a(), p, false), "pad A")
	assert_eq(resets, ["restart_after_death"] as Array[String], "confirms once (the sandbox restarts)")
	assert_eq(MainScript.DEATH_CONFIRM_DELAY_S, 1.0, "the delay is a second")
	m.free()


# --------------------------------------------------------------------------- found by the Valley bot

## The Valley bot (an intimidate run, on its way back to the Deadfall): the director takes a
## despawned member out of the tree and frees it at the end of the frame; the giant's ability that
## started later in the same tick reached the member's ability_started handler, which read its
## global position out of the tree (an engine error). The global-bus handlers now return out of the
## tree.
func test_a_member_out_of_the_tree_ignores_the_global_events() -> void:
	level = (load(DIRECTOR_LEVEL) as PackedScene).instantiate() as LevelRoot
	world.add_child(level)
	var lv := level as LevelRoot
	var d := lv.director()
	d.member_spawned.connect(_on_member_spawned)
	var p := lv.player()
	p.router.use_injection = true
	await step_ticks(2)
	d.force_activate(SOLDIERS)
	d.update_now()
	assert_eq(spawn_ticks.size(), 3, "three soldiers")
	if spawn_ticks.size() < 3:
		return
	var gone := d.spawned(str(spawn_ticks[0][1])) as EnemyActor
	var other := str(spawn_ticks[1][1])
	assert_true(gone != null and gone.is_inside_tree(), "a soldier")
	TestRunner.take_logged_errors()
	gone.get_parent().remove_child(gone)   # as the director's despawn does, before the free
	Events.ability_started.emit(Sim.tick, p.entity.entity_id, "ability.heavy_footfall", 4242)
	Events.entity_died.emit(Sim.tick, other, p.entity.entity_id)
	Events.faction_changed.emit(Sim.tick, "faction.test", "hostile")
	assert_eq(TestRunner.take_logged_errors(), [] as Array[String], "no engine error from the member out of the tree")
	gone.queue_free()
