extends IntegrationSuite
## M8 gate (F14; plan M6-M9 §5.9 "Nothing is farmable", §2.10 the disengage rule): a battle's units come
## back for every new attempt under the same entity ids (persist_death false), and their kill XP is paid
## once per spawn record, as their loot is. On scenes/test/bailey_test.tscn the wall's thirteen units,
## killed by the giant, pay their kill XP; a disengage brings them back, and killed again they pay
## nothing, nor a third time after the world is saved and loaded again (the once-marks ride in the
## world's deltas, beside "killed" and "loot_awarded"); a unit's loot drops once. A unit no spawn record
## brings back (a placed soldier) pays every time it is a new one (test_progression_player), and a copy
## of a template keeps P37's xp_scale (test_wander_director).

const BAILEY := "res://scenes/test/bailey_test.tscn"
const WALL := "encounter.bailey_test_wall"
const LOOT := "loot.raider"
const LOOT_ITEM := "item.wood_scrap"

var gone: Array = []


func before_each() -> void:
	await super()
	gone.clear()
	WorldState.clear()
	Events.boss_disengaged.connect(_on_disengaged)


func after_each() -> void:
	if Events.boss_disengaged.is_connected(_on_disengaged):
		Events.boss_disengaged.disconnect(_on_disengaged)
	Quests.end_dialogue()
	await super()


func _on_disengaged(_t: int, id: String, reason: String) -> void:
	gone.append([id, reason])


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
	h.attacker_position = e.actor.global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


## One attempt: engage, the first wall unit carries a loot table, the giant kills the whole wall.
## Returns [units killed, XP gained, loot items gained].
func _attempt(battle: BattleBoss, d: EncounterDirector, p: GiantPlayer) -> Array:
	battle.engage()
	await step_ticks(3)
	var first := d.members_of(WALL)[0]
	var actor := Sim.get_entity(first).actor if Sim.get_entity(first) != null else null
	if actor != null:
		actor.set("loot_table", LOOT)
	var xp0: int = p.progression.xp
	var loot0 := WorldState.count_of(LOOT_ITEM)
	var killed := 0
	for id in d.members_of(WALL):
		var e := Sim.get_entity(id)
		if e != null and e.is_alive():
			_kill(id, p.entity.entity_id)
			killed += 1
	await step_ticks(4)
	return [killed, p.progression.xp - xp0, WorldState.count_of(LOOT_ITEM) - loot0]


## The giant steps out beyond the arena's radius + 20 m until the disengage resets the battle, then back.
func _disengage(battle: BattleBoss, p: GiantPlayer) -> void:
	battle.disengage_s = 0.25
	var n := gone.size()
	p.global_position = Vector3(0, 0.05, 90)
	await step_ticks(20)
	assert_eq(gone.size(), n + 1, "the disengage resets the battle")
	p.global_position = Vector3(0, 0.05, 30)
	await step_ticks(2)


func test_a_battles_kill_xp_and_loot_are_paid_once_per_unit() -> void:
	var level := (load(BAILEY) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	p.global_position = Vector3(0, 0.05, 30)
	var want := 0
	for id in d.members_of(WALL):
		var sp := {}
		for s: Dictionary in GameData.get_record(WALL).spawns:
			if str(s.entity_id) == id:
				sp = s
		assert_false(bool(sp.get("persist_death", true)), "%s comes back for a new attempt" % id)
		want += int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
	assert_true(want > 0, "the wall's units carry kill XP (%d)" % want)
	var first := await _attempt(battle, d, p)
	assert_eq(int(first[0]), 13, "attempt 1: the wall's thirteen fall")
	assert_eq(int(first[1]), want, "attempt 1 pays the wall's kill XP")
	assert_true(int(first[2]) >= 1, "and the first unit's loot")
	await _disengage(battle, p)
	var second := await _attempt(battle, d, p)
	assert_eq(int(second[0]), 13, "attempt 2: the same thirteen, back and killed again")
	assert_eq(int(second[1]), 0, "attempt 2 pays no kill XP for the same units")
	assert_eq(int(second[2]), 0, "nor their loot again")
	# The marks ride in the saved world: a checkpoint's world loaded again keeps them.
	var doc := WorldState.to_save_dict()
	assert_true(WorldState.from_save_dict(doc), "the world reloads")
	await _disengage(battle, p)
	var third := await _attempt(battle, d, p)
	assert_eq(int(third[0]), 13, "attempt 3: the thirteen once more")
	assert_eq(int(third[1]), 0, "attempt 3 after the world's reload pays nothing")
	assert_eq(int(third[2]), 0, "nor any loot")
