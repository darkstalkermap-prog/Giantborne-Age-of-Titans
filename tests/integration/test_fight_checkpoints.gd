extends IntegrationSuite
## M8 release (R1, the class of the Iron Regiment's soft-lock in every boss fight): no checkpoint is committed
## while a BossArena is engaged - a request made before or during the fight, ordinary or a completion one,
## waits (GameSession's fight blocker) until the fight ends; the fight's own end (the M8 gate's boss-end and
## drive-out checkpoints, F38) is still taken; the arena's gate stands open whenever the fight is not engaged.
## The boss test arenas with their AI off (nothing aware: on the old rule a request went through at once
## mid-fight): the Ogre King's (a gate, the kill), the troll den's (the drive-out) and the Moot's (Spare).

const ARENAS := {
	"ogre_king": "res://scenes/test/boss_arena_test.tscn",
	"den": "res://scenes/test/troll_den_test.tscn",
	"moot": "res://scenes/test/moot_test.tscn",
}

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
	level = null
	player = null
	await super()


func _on_saved(tick: int, respawn: String, _ok: bool, _message: String) -> void:
	saved.append([tick, respawn, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", ""))])


## The arena's test level with checkpoints on (a test level's, kept in memory), the giant in the arena.
func _arena(key: String) -> BossArena:
	level = (load(str(ARENAS[key])) as PackedScene).instantiate() as Node3D
	TestSpawn.disable_all_ai(level)
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	GameSession.test_checkpoints = true
	GameSession.on_level_ready(level, player)
	player.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	var arena := level.get_node("BossArena") as BossArena
	player.global_position = arena.global_position + Vector3(0, 0.05, 8)
	player.velocity = Vector3.ZERO
	await step_ticks(1)
	return arena


## Engages, then checks that requests made before and during the fight wait for its end.
func _held(arena: BossArena, label: String) -> void:
	saved.clear()
	assert_false(arena.is_gate_closed(), "%s: the gate stands open before the fight" % label)
	arena.engage()
	await step_ticks(2)
	assert_true(arena.is_engaged(), "%s: engaged" % label)
	if arena.gate != null:
		assert_true(arena.is_gate_closed(), "%s: the gate closes behind the giant" % label)
	GameSession.request_checkpoint("quest_stage")
	await step_ticks(10)
	assert_eq(saved, [], "%s: no checkpoint while the fight is engaged (%s)" % [label, saved])
	var code := "fight:" + arena.boss_id
	assert_true(GameSession.checkpoint_blockers().has(code), "%s: held by the fight (%s)" % [label, GameSession.checkpoint_blockers()])
	GameSession.request_checkpoint("oath_won", "", true)
	await step_ticks(5)
	assert_eq(saved, [], "%s: a completion request waits too" % label)
	assert_eq(str(GameSession.pending_checkpoint().get("reason", "")), "oath_won", "%s: the request waits" % label)


## After the fight's end: its own checkpoint is taken at once, with what waited folded into it.
func _taken_at_the_end(arena: BossArena, reason: String, label: String) -> void:
	await step_ticks(3)
	assert_false(arena.is_engaged(), "%s: the fight is over" % label)
	assert_false(arena.is_gate_closed(), "%s: the gate stands open" % label)
	assert_eq(saved.size(), 1, "%s: one checkpoint at the fight's end (%s)" % [label, saved])
	if not saved.is_empty():
		assert_eq(str(saved[0][2]), reason, "%s: the fight's own end" % label)
	assert_true(GameSession.pending_checkpoint().is_empty(), "%s: nothing waits" % label)


func test_the_ogre_kings_fight_holds_checkpoints_until_he_falls() -> void:
	var arena := await _arena("ogre_king")
	await _held(arena, "the Ogre King")
	var king := arena.boss_entity()
	assert_true(king != null and king.is_alive(), "the king fights")
	if king == null:
		return
	queue_hit(player.entity.entity_id, arena.boss_id, (king.actor as Node3D).global_position + Vector3(0, 0, 6), 1.0e6,
		PackedStringArray(["Melee", "Unblockable", "Unparryable"]), 11.0)
	await _taken_at_the_end(arena, "boss_defeated", "the Ogre King")


func test_the_dens_fight_holds_checkpoints_until_the_matriarch_is_driven_out() -> void:
	var arena := await _arena("den")
	await _held(arena, "the den")
	Events.boss_disengaged.emit(Sim.tick, arena.boss_id, "fled")
	await _taken_at_the_end(arena, "boss_fled", "the den")


func test_the_moots_duel_holds_checkpoints_until_harrok_is_spared() -> void:
	var arena := await _arena("moot")
	await _held(arena, "the Moot")
	arena.p34_on_yield_decided(arena.boss_id, "spare")
	await _taken_at_the_end(arena, "boss_defeated", "the Moot")


## Harrok's talk ending chosen while the duel is engaged (the giant stepped into the ring, then walked out to
## the challenge stone - the fight's ground - and bid him kneel) ends the duel as won: the arena is not left
## engaged with nothing to fight, so the held request (and later the throne's) is taken. The test Moot's arena
## made a MootArena (its settled flag boss.harrok.outcome).
func test_the_talk_ending_ends_an_engaged_duel() -> void:
	level = (load(str(ARENAS["moot"])) as PackedScene).instantiate() as Node3D
	var old := level.get_node("BossArena") as Node3D
	var moot := MootArena.new()
	moot.name = "BossArena"
	moot.boss_id = "test.moot.harrok"
	moot.encounter_id = ""
	moot.engage_area_id = "test.area.moot_engage"
	moot.gate_path = NodePath("")
	moot.pillars_path = NodePath("")
	moot.inner_radius_m = 60.0
	moot.defeated_flag = "test.moot.defeated"
	moot.transform = old.transform
	level.remove_child(old)
	old.free()
	level.add_child(moot)
	TestSpawn.disable_all_ai(level)
	world.add_child(level)
	player = level.get_node("Player") as GiantPlayer
	player.router.use_injection = true
	GameSession.test_checkpoints = true
	GameSession.on_level_ready(level, player)
	player.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	player.global_position = moot.global_position + Vector3(0, 0.05, 8)
	await step_ticks(1)
	await _held(moot, "the Moot")
	var defeated: Array = []
	var on_defeated := func(_t: int, id: String) -> void: defeated.append(id)
	Events.boss_defeated.connect(on_defeated)
	WorldState.set_flag("boss.harrok.outcome", "yielded_talk")   # Harrok's dialogue: the talk ending
	await step_ticks(1)
	Events.boss_defeated.disconnect(on_defeated)
	assert_eq(defeated, ["test.moot.harrok"], "the duel is won without blood (boss_defeated: the bar and the music end)")
	await _taken_at_the_end(moot, "boss_defeated", "the Moot's talk ending")
	assert_true(QuestConditions.truthy(WorldState.get_flag("test.moot.defeated")), "the duel's defeated flag")


## A fight the giant walks away from (the disengage rule) lets a held request through at once.
func test_a_fight_left_lets_a_held_checkpoint_through() -> void:
	var arena := await _arena("ogre_king")
	await _held(arena, "the Ogre King")
	arena.disengage()
	await step_ticks(3)
	assert_eq(arena.state_name(), "waiting", "the fight reset")
	assert_false(arena.is_gate_closed(), "the gate stands open")
	assert_eq(saved.size(), 1, "the request is taken once the fight is left (%s)" % [saved])
	if not saved.is_empty():
		assert_eq(str(saved[0][2]), "oath_won", "the request's own")
