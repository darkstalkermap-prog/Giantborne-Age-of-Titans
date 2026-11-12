extends IntegrationSuite
## M8 release (R1, the release check's blocker on the 0.8.0-m8 candidate): the Iron Regiment's battle shut the
## giant in an empty bailey after a death or a quit-and-Continue mid-battle. A checkpoint request deferred from
## before the battle (it waits for no aware enemy within 40 m) was committed mid-battle as soon as the Wall fell,
## with the Wall's encounter cleared in its world; the battle's units come back for every attempt
## (persist_death false), so the next engagement after the load dropped the portcullis and waited on a Wall
## that never spawned. On scenes/test/bailey_test.tscn (battle.iron_regiment, with Fort Aldmere's portcullis
## added where the battle looks for it), the campaign's flow on the test level:
##   * no checkpoint is committed while the battle is engaged: a request deferred from before it, an ordinary
##     one and a completion one wait (and travel is refused) until the battle is won - its own end is still
##     checkpointed - or reset by the disengage rule;
##   * a death reload and a quit-and-Continue after the Wall fell bring back a full, winnable battle;
##   * a save written mid-battle by the old code (the Wall cleared, the battle not won) loads into a full,
##     winnable battle: the cleared flag is repaired as the battle loads, and its portcullis stands open;
##   * a phase never waits on units that will never come: units of a cleared encounter that are not up count
##     as fallen, and units of a begun phase that left the world come back.

const BAILEY := "res://scenes/test/bailey_test.tscn"
const WALL := "encounter.bailey_test_wall"
const CHARGE := "encounter.bailey_test_charge"
const STAND := "encounter.bailey_test_stand"
const BATTLE := "battle.iron_regiment"
const CORVANE := "test.bailey.corvane"
const GUARD := "test.reload.guard"

var level: Node3D
var player: GiantPlayer
## [tick, respawn, reason] of every checkpoint committed.
var saved: Array = []


func before_each() -> void:
	await super()
	saved.clear()
	WorldState.clear()
	Events.checkpoint_saved.connect(_on_saved)


func after_each() -> void:
	if Events.checkpoint_saved.is_connected(_on_saved):
		Events.checkpoint_saved.disconnect(_on_saved)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	level = null
	player = null
	await super()


func _on_saved(tick: int, respawn: String, _ok: bool, _message: String) -> void:
	saved.append([tick, respawn, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", ""))])


## The test bailey with Fort Aldmere's portcullis where the battle looks for it (BossArena.gate_path).
static func bailey_with_portcullis() -> Node3D:
	var b := (load(BAILEY) as PackedScene).instantiate() as Node3D
	var portcullis := StaticBody3D.new()
	portcullis.name = "ArenaGate"
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(18, 13, 2)
	shape.shape = box
	portcullis.add_child(shape)
	portcullis.position = Vector3(0, 6.5, 60)
	b.add_child(portcullis)
	(b.get_node("BattleBoss") as BattleBoss).gate_path = ^"../ArenaGate"
	return b


## A load of the bailey as main.gd makes it: the level enters the tree, then the session restores the giant.
func _load() -> void:
	level = bailey_with_portcullis()
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	GameSession.on_level_ready(level, player)
	player.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)


func _unload() -> void:
	if level != null:
		world.remove_child(level)
		level.queue_free()
	level = null
	player = null
	await get_tree().process_frame
	await get_tree().process_frame
	await step_ticks(1)


## New Game on the test bailey (the campaign's flow on a test level: --mode=valley --level=...).
func _new_game(persist := false) -> void:
	GameSession.persist = persist
	GameSession.level_override = BAILEY
	GameSession.start_new_valley()
	Quests.scope = PackedStringArray(["quest.none_on_the_test_bailey"])   # no shipped quest runs here
	Quests.tutorial.scope = PackedStringArray(["tutorial.none_on_the_test_bailey"])
	await _load()


func _battle() -> BattleBoss:
	return level.get_node("BattleBoss") as BattleBoss


func _director() -> EncounterDirector:
	return level.get_node("EncounterDirector") as EncounterDirector


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive() or e.actor == null:
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = player.entity.entity_id if player != null else "player"
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


func _kill_encounter(enc: String) -> void:
	for id in _director().members_of(enc):
		_kill(id)
	await step_ticks(3)


## The planned units of `enc` that are in the world, alive.
func _up(enc: String) -> Array:
	var planned := _battle().planned()
	return Array(_director().members_of(enc)).filter(func(id: String) -> bool:
		var e := Sim.get_entity(id)
		return planned.has(id) and e != null and e.is_alive())


## The giant inside the bailey, then the engagement (the trigger's path ends in engage()).
func _engage() -> void:
	player.global_position = Vector3(0, 0.05, 30)
	player.velocity = Vector3.ZERO
	await step_ticks(1)
	_battle().engage()
	await step_ticks(3)


## An enemy aware of the giant within 40 m of where it engages the battle (and of its start): an ordinary
## checkpoint request waits for it (decision 13), as for the Wall's own aware units in the fort.
func _aware_guard() -> EnemyActor:
	var g := TestSpawn.stub_enemy(level, Vector3(14, 0.05, 50), GUARD)
	await step_ticks(2)
	g.brain.aware = true
	return g


## The rest of the battle, won: the Charge, the Last Stand, Corvane's yield and Spare.
func _win_from_the_charge() -> void:
	var b := _battle()
	for i in 3:
		await _kill_encounter(CHARGE)
	assert_eq(b.phase_log, [1, 2, 3] as Array[int], "the riders fall: The Last Stand (%s)" % [b.phase_log])
	await _kill_encounter(STAND)
	await step_ticks(2)
	var corvane := Sim.get_entity(CORVANE)
	assert_true(corvane != null and corvane.actor != null and (corvane.actor as EnemyActor).yielded,
		"his guard broken, Corvane yields")
	if corvane == null or corvane.actor == null:
		return
	assert_true((corvane.actor as EnemyActor).p34_decide("spare"), "Spare")
	await step_ticks(3)
	assert_true(b.is_defeated(), "the battle is won")
	assert_false(b.is_gate_closed(), "the portcullis lifts")


## Engages and checks that this is a full attempt: the Wall's planned units all come, the bar counts all of it.
func _a_full_attempt(label: String) -> void:
	var b := _battle()
	assert_eq(b.state_name(), "waiting", "%s: the battle waits for the giant" % label)
	assert_false(b.is_gate_closed(), "%s: its portcullis stands open" % label)
	await _engage()
	assert_eq(b.state_name(), "engaged", "%s: walking in engages it" % label)
	assert_true(b.is_gate_closed(), "%s: the portcullis drops behind the giant" % label)
	var wall := Array(_director().members_of(WALL))
	assert_eq(_up(WALL).size(), wall.size(), "%s: the Wall musters whole (%d of %d up; statuses %s)" % [label,
		_up(WALL).size(), wall.size(), wall.map(func(id: String) -> String: return _director().member_status(id))])
	assert_near(b.aggregate_fraction(), 1.0, 1e-6, "%s: the bar counts the whole battle" % label)
	await _kill_encounter(WALL)
	assert_eq(b.phase_log, [1, 2] as Array[int], "%s: the Wall falls, The Charge (%s)" % [label, b.phase_log])
	assert_true(_up(CHARGE).size() > 0, "%s: the riders come" % label)
	await _win_from_the_charge()


# --------------------------------------------------------------------------- no checkpoint mid-battle

func test_a_deferred_checkpoint_waits_until_the_battle_is_won() -> void:
	await _new_game()
	assert_eq(saved.size(), 1, "New Game's checkpoint")
	var guard := await _aware_guard()
	saved.clear()
	GameSession.request_checkpoint("quest_started")   # the gate's quest, started with its garrison aware
	await step_ticks(2)
	assert_eq(saved, [], "the request waits for the aware enemy")
	await _engage()
	var b := _battle()
	assert_eq(b.state_name(), "engaged", "the battle is engaged")
	assert_eq(saved, [], "nothing is taken as the battle engages")
	# The Wall falls; the last enemy aware within 40 m (the Wall's own, in the fort) goes with it.
	await _kill_encounter(WALL)
	guard.brain.aware = false
	guard.queue_free()
	assert_eq(b.phase_log, [1, 2] as Array[int], "the Wall falls: The Charge")
	await step_ticks(30)
	var aware_near := Array(GameSession.checkpoint_blockers()).filter(func(x: String) -> bool: return x.begins_with("aware:"))
	assert_eq(aware_near, [], "no enemy is aware within 40 m now (the riders come from 70 m off)")
	assert_eq(saved, [], "no checkpoint is committed while the battle is engaged (%s)" % [saved])
	assert_eq(str(GameSession.pending_checkpoint().get("reason", "")), "quest_started", "the deferred request still waits")
	assert_true(GameSession.checkpoint_blockers().has("fight:" + BATTLE), "held by the battle (%s)" % [GameSession.checkpoint_blockers()])
	assert_true(GameSession.checkpoint_blockers(true).has("fight:" + BATTLE), "a completion request is held too")
	GameSession.request_checkpoint("quest_stage", "", true)
	await step_ticks(3)
	assert_eq(saved, [], "a completion request waits as well")
	var travel := GameSession.travel_blockers("fast_travel")
	assert_true(travel.has("fight:" + BATTLE), "travel waits for the battle too (%s)" % [travel])
	assert_eq(GameSession.blocker_text(PackedStringArray(["fight:" + BATTLE])), "Not in the middle of a fight.",
		"and says why")
	await _win_from_the_charge()
	await step_ticks(3)
	assert_eq(saved.size(), 1, "the battle won: one checkpoint (%s)" % [saved])
	if not saved.is_empty():
		assert_eq(str(saved[0][2]), "boss_defeated", "the battle's own end")
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")


func test_a_checkpoint_held_by_the_battle_is_taken_once_it_resets() -> void:
	await _new_game()
	await _engage()
	var b := _battle()
	b.disengage_s = 0.25
	await _kill_encounter(WALL)
	saved.clear()
	GameSession.request_checkpoint("quest_stage")
	await step_ticks(20)
	assert_eq(saved, [], "held while the battle is engaged (%s)" % [saved])
	# The giant leaves the bailey for good: the disengage rule resets the battle and lets the request through.
	player.global_position = Vector3(0, 0.05, 90)
	var reset: bool = await TestWait.until(self, func() -> bool: return b.state_name() == "waiting", 120)
	assert_true(reset, "the battle resets behind the giant")
	await step_ticks(3)
	assert_eq(saved.size(), 1, "then the request is taken (%s)" % [saved])
	if not saved.is_empty():
		assert_eq(str(saved[0][2]), "quest_stage", "the request's own")
	assert_false(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)),
		"the reset brings the Wall back: its fall is not saved")


# --------------------------------------------------------------------------- loads after the Wall fell

## A deferred request, the battle engaged and the Wall fallen: what a death or a quit then reloads.
func _wall_falls_with_a_request_waiting() -> void:
	var guard := await _aware_guard()
	GameSession.request_checkpoint("quest_started")
	await step_ticks(2)
	await _engage()
	await _kill_encounter(WALL)
	guard.brain.aware = false   # the last enemy aware within 40 m falls with the Wall
	guard.queue_free()
	await step_ticks(30)
	assert_eq(_battle().phase_log, [1, 2] as Array[int], "the Wall fell: The Charge")


func test_a_death_after_the_wall_fell_reloads_a_full_battle() -> void:
	await _new_game()
	await _wall_falls_with_a_request_waiting()
	assert_false(QuestConditions.truthy(GameSession.checkpoint_doc.world.flags.get(EncounterDirector.cleared_flag(WALL), false)),
		"the last checkpoint does not hold the Wall's fall")
	# The giant dies in the Charge: the death screen's confirm reloads the last checkpoint.
	GameSession.reload_checkpoint("death")
	await _unload()
	await _load()
	assert_false(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)),
		"after the death the Wall is not cleared")
	await _a_full_attempt("after a death")


func test_a_quit_and_continue_after_the_wall_fell_loads_a_full_battle() -> void:
	await _new_game(true)
	await _wall_falls_with_a_request_waiting()
	await _unload()
	GameSession.go_to_title()
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	await _load()
	assert_false(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)),
		"after Continue the Wall is not cleared")
	await _a_full_attempt("after a quit and Continue")


## M8 release (R1): a save the old code wrote mid-battle - the Wall's encounter cleared, the battle not won.
func test_a_save_written_mid_battle_loads_a_full_battle() -> void:
	await _new_game(true)
	var doc := GameSession.checkpoint_doc.duplicate(true)
	var flags: Dictionary = doc.world.flags
	flags[EncounterDirector.cleared_flag(WALL)] = true
	var deltas: Dictionary = doc.world.deltas
	for id in _director().members_of(WALL):
		deltas[id] = {"kill_xp_paid": true}   # the fallen Wall's XP marks (F14) ride with it
	assert_true(bool(SaveSlots.write(doc).ok), "the old save is written")
	await _unload()
	GameSession.go_to_title()
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads it (%s)" % r.message)
	assert_true(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)),
		"the save holds the Wall cleared")
	await _load()
	assert_false(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)),
		"the battle repairs it as it loads: a battle not won has no fallen phase")
	assert_eq(_director().encounter_state(WALL), EncounterDirector.DORMANT, "the Wall waits for the battle")
	await _a_full_attempt("a save written mid-battle")


# --------------------------------------------------------------------------- the phases never wait on nobody

func test_a_phase_never_waits_on_units_that_will_never_come() -> void:
	level = bailey_with_portcullis()
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	player.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	var b := _battle()
	var d := _director()
	await _engage()
	assert_eq(b.phase_log, [1] as Array[int], "The Wall")
	# Units of a begun phase that leave the world (despawned) come back: the phase does not wait on them.
	var gone := [d.members_of(WALL)[0], d.members_of(WALL)[1]]
	for id: String in gone:
		d.despawn(id)
	await step_ticks(4)
	for id: String in gone:
		assert_eq(d.member_status(id), EncounterDirector.SPAWNED, "%s came back to its place in the battle" % id)
	# The Wall's encounter cleared with its units not up (the old save's state): they are not to come.
	WorldState.set_flag(EncounterDirector.cleared_flag(WALL), true)
	d.reload_encounters()
	await step_ticks(3)
	assert_eq(d.encounter_state(WALL), EncounterDirector.CLEARED, "the Wall's encounter reads cleared")
	assert_eq(b.phase_log, [1, 2] as Array[int], "The Charge begins: a cleared Wall's units are not waited on (%s)" % [b.phase_log])
	assert_true(_up(CHARGE).size() > 0, "the riders come")
	var a := b.aggregate()
	assert_true(float(a.current) < float(a.total) * 0.6, "the bar does not count units that will never come (%d / %d)" % [
		int(a.current), int(a.total)])
