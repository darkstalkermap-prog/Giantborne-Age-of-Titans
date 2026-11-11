extends IntegrationSuite
## M8 gate (F38): the troll den's two endings and their checkpoints (decision 13: a checkpoint never
## loses a boss's end). The campaign from world_start in level.world (the Greywood walkthrough's
## harness), the shipped den props parts (its BossArena, braziers, nests and back wall) and the shipped
## Matriarch scene, at stage 4:
##   * slain: her death ends the arena (boss_defeated) and a checkpoint is taken;
##   * driven out: the three braziers burn the nests, the woodfolk open the wall, below 60 % she runs
##     for the exit and flees (boss_disengaged "fled", the arena DEFEATED) - and a checkpoint is taken
##     the same way, with no boss_defeated (no victory cue); a death right after reloads the drive-out:
##     her outcome, the burned nests and the open wall stay.

const START_CP := "world.cp.hollowmere"
const DEN_PARTS := ["res://scenes/world/chunks/c0_2_0.tscn", "res://scenes/world/chunks/c1_2_0.tscn"]
const MATRIARCH := "world.greywood.troll_matriarch"
const BRAZIERS := ["world.greywood.den_brazier_1", "world.greywood.den_brazier_2", "world.greywood.den_brazier_3"]

var _saved: Array = []
var _defeated: Array = []


func before_each() -> void:
	await super()
	WorldState.clear()
	_saved.clear()
	_defeated.clear()
	Events.checkpoint_saved.connect(_on_saved)
	Events.boss_defeated.connect(_on_defeated)


func after_each() -> void:
	if Events.checkpoint_saved.is_connected(_on_saved):
		Events.checkpoint_saved.disconnect(_on_saved)
	if Events.boss_defeated.is_connected(_on_defeated):
		Events.boss_defeated.disconnect(_on_defeated)
	await super()


func _on_saved(t: int, cp: String, ok: bool, msg: String) -> void:
	_saved.append([t, cp, ok, msg, str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", ""))])


func _on_defeated(_t: int, id: String) -> void:
	_defeated.append(id)


func _start(stage: int) -> GiantPlayer:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.velocity = Vector3.ZERO
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	var grown := int(p.get("growth_stage")) == stage
	for i in 240:
		if grown or bool(p.growth.debug_set_stage(stage).get("ok", false)):
			grown = true
			break
		await step_ticks(1)
	assert_true(grown, "the giant grows to stage %d" % stage)
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	return p


func _den() -> void:
	for path: String in DEN_PARTS:
		world.add_child((load(path) as PackedScene).instantiate())


func _arena() -> BossArena:
	for n in world.find_children("*", "", true, false):
		if n is BossArena and (n as BossArena).boss_id == MATRIARCH:
			return n
	return null


func _strike(p: GiantPlayer, world_id: String) -> bool:
	for i in 40:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			break
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = world_id
		h.power = 600.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.tags = PackedStringArray(["Melee"])
		h.category = "melee"
		h.attacker_growth_stage = int(p.get("growth_stage"))
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	await step_ticks(2)
	return WorldState.is_destroyed(world_id)


func _matriarch() -> TrollEnemy:
	var rec := GameData.get_record("enemy.troll_matriarch")
	var m := (load(str(rec.scene)) as PackedScene).instantiate() as TrollEnemy
	m.set("entity_id", MATRIARCH)
	m.position = Vector3(0, 0.05, 40)
	world.add_child(m)
	await step_ticks(2)
	return m


## The checkpoints recorded (since the last clear) whose document gives `reason`.
func _taken(reason: String) -> Array:
	return _saved.filter(func(s: Array) -> bool: return str(s[4]) == reason)


func test_the_slay_takes_a_checkpoint() -> void:
	var p := await _start(4)
	_den()
	await step_ticks(2)
	var arena := _arena()
	assert_true(arena != null, "the den's arena is in its props part")
	var m := await _matriarch()
	await step_ticks(5)
	_saved.clear()
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = p.entity.entity_id
	h.target_id = MATRIARCH
	h.power = 99999.0
	h.attacker_stat = 40.0
	h.attacker_height_m = 11.0
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.category = "melee"
	h.attacker_growth_stage = 4
	h.attacker_position = m.global_position + Vector3(0, 0, 6)
	Sim.queue_hit(h)
	await step_ticks(3)
	assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "slain", "slain")
	assert_true(arena.is_defeated(), "the arena is won")
	await step_ticks(10)
	assert_eq(_taken("boss_defeated").size(), 1, "the slay takes a checkpoint (%s)" % [_saved])
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")


func test_the_drive_out_takes_a_checkpoint_that_a_death_reloads() -> void:
	var p := await _start(4)
	_den()
	await step_ticks(2)
	var arena := _arena()
	assert_true(arena != null, "the den's arena is in its props part")
	for b: String in BRAZIERS:
		assert_true(await _strike(p, b), "%s smashed" % b)
		await step_ticks(3)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.nests_burned")), "the nests burned")
	await step_ticks(ActionDef.seconds_to_ticks(20.5))
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.wall_open")), "the woodfolk opened the wall")
	var m := await _matriarch()
	await step_ticks(5)
	_saved.clear()
	_defeated.clear()
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.55
	await step_ticks(2)
	assert_true(m.is_fleeing(), "below 60 % she runs")
	m.global_position = m.exit_point() + Vector3(0, 0.05, 1.0)
	await step_ticks(3)
	assert_eq(WorldState.get_flag("boss.matriarch.outcome"), "fled", "fled")
	assert_true(arena.is_defeated(), "the arena is won (DEFEATED)")
	await step_ticks(10)
	assert_eq(_taken("boss_fled").size(), 1, "the drive-out takes a checkpoint as the slay does (%s)" % [_saved])
	assert_true(GameSession.pending_checkpoint().is_empty(), "nothing waits")
	assert_eq(_defeated, [], "and no boss_defeated (no victory cue for a flight)")
	# A death before any later checkpoint reloads the drive-out, not the fight.
	GameSession.reload_checkpoint("death")
	assert_eq(str(WorldState.get_flag("boss.matriarch.outcome")), "fled", "after a death her outcome stays fled")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.nests_burned")), "the nests stay burned")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.troll_den.wall_open")), "the wall stays open")
