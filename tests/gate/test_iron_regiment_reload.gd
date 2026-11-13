extends IntegrationSuite
## M8 release (R1, the release check's blocker on the 0.8.0-m8 candidate): the Iron Regiment's battle on the real
## world (scenes/world/world.tscn, deterministic streaming) after a death, a quit and Continue, and a save written
## mid-battle - the campaign from world_start at Fort Aldmere's gate waystone, a stage-4 giant that takes no
## damage, the fort's real gate broken and the bailey entered through its engage trigger. On the candidate a
## checkpoint request deferred from before the battle (an enemy aware within 40 m) was committed mid-battle as
## soon as the Wall fell: the save held the Wall's encounter cleared with the battle not won, and after a death
## or a quit and Continue the battle engaged again behind its portcullis and waited on a Wall that never spawned.
##   * a death after the Wall fell reloads a world from before the battle: the portcullis open, the battle a
##     full attempt the giant wins (its own end checkpointed);
##   * a quit and Continue after the Wall fell, the same;
##   * the release check's own save, written mid-battle by the candidate (the Wall cleared, the battle not won):
##     Continue loads it into a full battle - the battle lifts the stale flag as it loads - which the giant wins.

const SCENE := "res://scenes/world/world.tscn"
const FORT_CP := "world.cp.fort_gate"
const GATE := "world.aldmere.fort_gate"
const WALL := "encounter.aldmere_iron_regiment_wall"
const CHARGE := "encounter.aldmere_iron_regiment_charge"
const STAND := "encounter.aldmere_iron_regiment_stand"
const CORVANE := "world.aldmere.corvane"
const GUARD := "test.reload.guard"
## A save the 0.8.0-m8 candidate wrote mid-battle (the release check's run: the Wall cleared, a death, the
## battle engaged again and its fort gate waystone's deferred checkpoint taken mid-battle).
const MID_BATTLE_SAVE := "res://tests/fixtures/saves/v2_iron_regiment_wall_cleared.json"
## Where the giant stands to fight in the bailey: 75 m from the gate's bastions, 65 m from the stables.
const IN_BAILEY := Vector2(650.0, -170.0)

var w: WorldRoot
## [tick, respawn, reason] of every checkpoint committed.
var saved: Array = []


func before_each() -> void:
	await super()
	saved.clear()
	Events.checkpoint_saved.connect(_on_saved)


func after_each() -> void:
	if Events.checkpoint_saved.is_connected(_on_saved):
		Events.checkpoint_saved.disconnect(_on_saved)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	if w != null and is_instance_valid(w):
		w.queue_free()
	w = null
	await get_tree().process_frame
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _on_saved(tick: int, respawn: String, _ok: bool, _message: String) -> void:
	saved.append([tick, respawn, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", ""))])


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## A load of the world as main.gd makes it: the level enters the tree, then the session restores the giant at
## its respawn, and the ring around it streams in before it is set down there.
func _load() -> void:
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await _move(Vector2(p.global_position.x, p.global_position.z))
	await step_ticks(5)


func _unload() -> void:
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	if w != null:
		w.queue_free()
	w = null
	await get_tree().process_frame
	await get_tree().process_frame
	await step_ticks(1)


## Puts the giant on the ground at `xz` once the ring around it is loaded.
func _move(xz: Vector2) -> void:
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


## The campaign's New Game at the fort gate's waystone (world_start), saving on, the giant grown to stage 4.
func _new_game() -> void:
	GameSession.persist = true
	GameSession.start_world_for_tests(FORT_CP)
	GameSession.level_id = "level.world"
	await _load()
	var p := w.player()
	var grown := false
	for i in 240:
		if p.current_growth_stage() == 4 or bool(p.growth.debug_set_stage(4).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage 4")
	await step_ticks(5)
	# The growth at a shrine is checkpointed: what a death or a Continue reloads holds the stage-4 giant.
	GameSession.request_checkpoint("growth")
	var taken: bool = await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 120)
	assert_true(taken, "the grown giant's checkpoint (%s)" % [GameSession.checkpoint_blockers()])
	assert_eq(int(GameSession.checkpoint_doc.character.get("growth_stage", 0)), 4, "it holds the stage-4 giant")


func _battle() -> FortBattle:
	if w == null:
		return null
	for n in w.get_tree().get_nodes_in_group(BattleBoss.BATTLE_GROUP):
		if n is FortBattle and w.is_ancestor_of(n):
			return n
	return null


## Strikes a prop as the stage-4 giant until it is destroyed (at most 80 blows).
func _break(world_id: String) -> bool:
	var p := w.player()
	for i in 80:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = world_id
		h.power = 900.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = p.current_growth_stage()
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	return WorldState.is_destroyed(world_id)


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or e.actor == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = w.player().entity.entity_id
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)


func _kill_encounter(enc: String) -> void:
	for id in w.director().members_of(enc):
		_kill(id)
	await step_ticks(3)


## The planned units of `enc` alive in the world.
func _up(b: BattleBoss, enc: String) -> Array:
	var planned := b.planned()
	return Array(w.director().members_of(enc)).filter(func(id: String) -> bool:
		var e := Sim.get_entity(id)
		return planned.has(id) and e != null and e.is_alive())


## The fort's gate broken (again, when a load gave it back), the giant through it and into the bailey.
func _enter_bailey(b: FortBattle) -> void:
	if not WorldState.is_destroyed(GATE):
		await _move(Vector2(650.0, -75.0))
		await step_ticks(5)
		assert_true(await _break(GATE), "the fort's gate breaks")
		await step_ticks(10)
	await _move(Vector2(650.0, -112.0))
	await step_ticks(6)
	await _move(Vector2(650.0, -128.0))
	await step_ticks(6)
	assert_eq(b.state_name(), "engaged", "walking in engages the battle")
	assert_true(b.is_gate_closed(), "the portcullis drops behind the giant")


## A request deferred by an enemy aware beside the giant, the battle engaged, the Wall fallen - and with it
## the last enemy aware within 40 m (the stub stands for the Wall's own aware units).
func _the_wall_falls_with_a_request_waiting() -> void:
	var b := _battle()
	assert_true(b != null, "the battle is loaded")
	if b == null:
		return
	await _move(Vector2(650.0, -75.0))
	var g_at := Vector3(660.0, w.height_at(Vector3(660.0, 0.0, -75.0)) + 0.1, -75.0)
	var guard := TestSpawn.stub_enemy(w, g_at, GUARD)
	await step_ticks(2)
	guard.brain.aware = true
	saved.clear()
	GameSession.request_checkpoint("quest_started")
	await step_ticks(2)
	assert_eq(saved, [], "the request waits for the aware enemy")
	await _enter_bailey(b)
	await _move(IN_BAILEY)
	guard.global_position = Vector3(IN_BAILEY.x + 10.0, w.height_at(Vector3(IN_BAILEY.x + 10.0, 0.0, IN_BAILEY.y)) + 0.1, IN_BAILEY.y)
	guard.velocity = Vector3.ZERO
	await step_ticks(3)
	var guard_text := Array(GameSession.checkpoint_blockers()).filter(func(x: String) -> bool: return x == "aware:" + GUARD)
	assert_eq(guard_text.size(), 1, "the aware enemy stands beside the giant in the bailey")
	await _kill_encounter(WALL)
	await _kill_encounter(WALL)
	guard.brain.aware = false
	guard.queue_free()
	await step_ticks(30)
	assert_true(b.phase_log.has(2), "the Wall falls: The Charge (%s)" % [b.phase_log])
	var aware_near := Array(GameSession.checkpoint_blockers()).filter(func(x: String) -> bool: return x.begins_with("aware:"))
	print("    iron regiment reload: the Wall fallen, blockers %s, checkpoints since %s" % [GameSession.checkpoint_blockers(), saved])
	assert_eq(aware_near, [], "no enemy is aware within 40 m (the riders come from the stables)")
	# M9 gate (lane ironreg; a deliberate change): the gate's fall starts the crown's road, a completion request
	# (GameSession.settles_an_oath), so the request deferred from before the battle is taken with the breach - before
	# the battle engages, with the gate broken and the battle waiting. None is committed while it is engaged.
	var during := saved.filter(func(s: Array) -> bool: return int(s[0]) >= b.engaged_tick)
	assert_eq(during, [], "no checkpoint is committed while the battle is engaged (%s; engaged at %d)" % [saved, b.engaged_tick])
	assert_false(QuestConditions.truthy(GameSession.checkpoint_doc.world.flags.get(EncounterDirector.cleared_flag(WALL), false)),
		"the last checkpoint does not hold the Wall's fall")


## After a load: the portcullis open, the battle waiting; then a full attempt the giant wins.
func _a_full_battle_after(label: String) -> void:
	var b := _battle()
	assert_true(b != null, "%s: the battle is loaded" % label)
	if b == null:
		return
	assert_eq(b.state_name(), "waiting", "%s: the battle waits" % label)
	assert_false(b.is_gate_closed(), "%s: the portcullis stands open: the giant is not shut in" % label)
	assert_false(QuestConditions.truthy(WorldState.get_flag(EncounterDirector.cleared_flag(WALL), false)), "%s: the Wall is not cleared" % label)
	await _enter_bailey(b)
	await _move(IN_BAILEY)
	await step_ticks(30)
	var d := w.director()
	var wall_planned := Array(d.members_of(WALL)).filter(func(id: String) -> bool: return b.planned().has(id))
	print("    iron regiment reload (%s): the Wall %d of %d planned up; the bar '%s'" % [label, _up(b, WALL).size(),
		wall_planned.size(), b.debug_lines()[0]])
	assert_true(wall_planned.size() >= 20, "%s: the Wall is planned whole (%d)" % [label, wall_planned.size()])
	assert_eq(_up(b, WALL).size(), wall_planned.size(), "%s: the Wall musters whole (statuses %s)" % [label,
		wall_planned.map(func(id: String) -> String: return d.member_status(id))])
	await _kill_encounter(WALL)
	await _kill_encounter(WALL)
	await step_ticks(10)
	assert_true(b.phase_log.has(2), "%s: the Wall falls, The Charge (%s)" % [label, b.phase_log])
	var riders := 0
	for i in 40:
		riders = maxi(riders, _up(b, CHARGE).size())
		await _kill_encounter(CHARGE)
		if b.phase_log.has(3):
			break
	assert_true(riders > 0, "%s: the riders came (%d)" % [label, riders])
	assert_true(b.phase_log.has(3), "%s: the riders fall, The Last Stand (%s)" % [label, b.phase_log])
	var yielded := false
	for i in 40:
		for id in d.members_of(STAND):
			if id != CORVANE:
				_kill(id)
		await step_ticks(3)
		var c := Sim.get_entity(CORVANE)
		if c != null and c.actor != null and bool(c.actor.get("yielded")):
			yielded = true
			break
	assert_true(yielded, "%s: his guard broken, Corvane yields" % label)
	if not yielded:
		return
	saved.clear()
	assert_true((Sim.get_entity(CORVANE).actor as EnemyActor).p34_decide("spare"), "%s: Spare" % label)
	await step_ticks(10)
	assert_true(b.is_defeated(), "%s: the battle is won" % label)
	assert_false(b.is_gate_closed(), "%s: the portcullis lifts" % label)
	# The battle's end (boss_defeated) is taken at once - with the oath it wins, whose request folds into it.
	assert_eq(saved.size(), 1, "%s: the battle's end takes one checkpoint (%s)" % [label, saved])
	assert_eq(str(GameSession.checkpoint_doc.world.flags.get("boss.corvane.outcome", "")), "spared",
		"%s: it saves the battle won" % label)
	assert_true(GameSession.pending_checkpoint().is_empty(), "%s: nothing waits" % label)


func test_a_death_after_the_wall_fell_reloads_a_battle_that_can_be_won() -> void:
	await _new_game()
	await _the_wall_falls_with_a_request_waiting()
	# The giant dies in the Charge: the death screen's confirm reloads the last checkpoint.
	GameSession.reload_checkpoint("death")
	await _unload()
	await _load()
	await _a_full_battle_after("after a death")


func test_a_quit_and_continue_after_the_wall_fell_loads_a_battle_that_can_be_won() -> void:
	await _new_game()
	await _the_wall_falls_with_a_request_waiting()
	GameSession.go_to_title()
	await _unload()
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads the save (%s)" % r.message)
	await _load()
	await _a_full_battle_after("after a quit and Continue")


func test_a_save_written_mid_battle_loads_a_battle_that_can_be_won() -> void:
	var doc: Dictionary = SaveSlots.migrate(JsonIO.read_file(MID_BATTLE_SAVE).data)
	var flags: Dictionary = doc.world.flags
	assert_eq([flags.get(EncounterDirector.cleared_flag(WALL)), str(flags.get("quest.iron_regiment.stage", "")),
		flags.has("boss.corvane.outcome")], [true, "battle", false], "the save holds the Wall cleared, the battle not won")
	GameSession.persist = true
	assert_true(bool(SaveSlots.write(doc).ok), "the save is in the slot")
	var r := GameSession.continue_valley()
	assert_true(bool(r.ok), "Continue loads it (%s)" % r.message)
	await _load()
	var b := _battle()
	assert_true(b != null and Array(b.get("repaired") if b.get("repaired") != null else []).has(WALL),
		"the battle lifts the Wall's stale cleared flag as it loads")
	await _a_full_battle_after("a save written mid-battle")
