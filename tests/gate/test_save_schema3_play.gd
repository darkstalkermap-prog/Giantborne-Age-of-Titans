extends IntegrationSuite
## A4: the real cross-version check of save schema 3 - each schema 2 fixture the pre-A4 build wrote (a Valley save,
## a mid-world save, a campaign-completed save, the mid-world save with Stoneback slain:
## tests/fixtures/saves/v2_a4_*.json) is put in the slot and Continued through the title's own path
## (GameSession.continue_valley), its level loaded as main.gd loads it (the scene, then GameSession.on_level_ready,
## the ring streamed in), and played on for two seconds: the giant stands at its respawn, alive, in its character;
## then a checkpoint writes schema 3 (the first checkpoint after the Continue - the shrine it wakes at may take one -
## keeps the schema 2 file as its backup) and a second Continue reads it back.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const FIXTURES := ["v2_a4_valley", "v2_a4_world_mid", "v2_a4_campaign_complete", "v2_a4_stoneback_slain"]

var level: Node3D = null
var saved: Array = []
## The backup file as the first checkpoint after the Continue left it (the schema 2 file).
var first_backup := ""


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
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await get_tree().process_frame
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	await super()


func _on_saved(_t: int, _cp: String, ok: bool, _msg: String) -> void:
	if ok and first_backup == "" and FileAccess.file_exists(SaveSlots.path() + ".bak"):
		first_backup = FileAccess.get_file_as_string(SaveSlots.path() + ".bak")
	saved.append(ok)


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The level of the session's save loaded as main.gd loads it, the giant restored at its respawn.
func _load_level() -> GiantPlayer:
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var scene := GameSession.scene_for_level(GameSession.level_id)
	level = (load(scene) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var w := level as WorldRoot
	if w != null:
		w.streamer.deterministic = true
	var p := level.get_node("Player") as GiantPlayer if level.has_node("Player") else \
		get_tree().get_first_node_in_group("player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	if w != null:
		var at := p.global_position
		var guard := 0
		while not w.streamer.ring_ready(at) and guard < 900:
			w.streamer.load_ring_slice(at)
			await step_ticks(1)
			guard += 1
	return p


func test_each_fixture_continues_plays_on_and_saves_schema_3() -> void:
	for f: String in FIXTURES:
		var text := FileAccess.get_file_as_string(FIXTURE_DIR + f + ".json")
		var doc: Dictionary = JSON.parse_string(text)
		GameSession.persist = true
		_write_text(SaveSlots.path(), text)
		first_backup = ""
		var r := GameSession.continue_valley()
		assert_true(r.ok, "%s: Continue (%s)" % [f, r.message])
		var p := await _load_level()
		await step_ticks(120)
		assert_true(p.entity.is_alive(), "%s: the giant plays on" % f)
		var respawn := GameSession.respawn_transform(str(doc.checkpoint.respawn))
		if respawn.origin.is_finite():
			assert_true(Vector2(p.global_position.x - respawn.origin.x, p.global_position.z - respawn.origin.z).length() < 25.0,
				"%s: at its respawn %s" % [f, doc.checkpoint.respawn])
		assert_eq(int(p.progression.level), int(doc.character.level), "%s: its level" % f)
		assert_eq(p.current_growth_stage(), int(doc.character.growth_stage), "%s: its stage" % f)
		assert_false(GameSession.intro_due, "%s: no intro on a Continue" % f)
		saved.clear()
		GameSession.request_checkpoint("a4_schema3")
		var taken: bool = await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 240)
		assert_true(taken and saved.has(true), "%s: a checkpoint is written (%s)" % [f, GameSession.checkpoint_blockers()])
		var main := JsonIO.read_file(SaveSlots.path())
		assert_eq(int((main.data as Dictionary).get("schema_version", 0)) if main.ok else 0, 3, "%s: schema 3 on disk" % f)
		assert_eq(first_backup, text, "%s: the first schema 3 checkpoint kept the schema 2 file as its backup" % f)
		var again := GameSession.continue_valley()
		assert_true(again.ok and str(again.message) == "", "%s: the schema 3 save Continues (%s)" % [f, again.message])
		assert_eq(GameSession.expansion, ExpansionState.from_doc(SaveSlots.read().data), "%s: with its fields" % f)
		if level != null and is_instance_valid(level):
			level.queue_free()
		level = null
		await get_tree().process_frame
		await get_tree().process_frame
		FactionState.reset_for_tests()
		WanderDirector.reset_for_tests()
		SaveSlots.delete_slot(true)
		WorldState.clear()
