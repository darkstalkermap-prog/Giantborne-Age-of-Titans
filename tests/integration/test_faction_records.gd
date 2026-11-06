extends IntegrationSuite
## P22 (plan M6-M9 §2.12 and §3.4 design 6, decision 31): factions by record. FactionState reads
## each faction's record (data/world/faction_village.json; the test-only data/test/faction_test_town
## and faction_test_riders): its offence count and window, its initial disposition, its flag
## prefix, its texts and whether its civilians give way to a giant at peace with them. Reconciled
## wins over hostile until the next offence; the giant's damage to a faction's house (or engine)
## is an offence; a give-way civilian steps out of the giant's path and does not flee.

const TOWN := "test_town"       # neutral, 3 offences within 10 s, civilians give way 3 m
const RIDERS := "test_riders"   # hostile from the start, 1 offence, flags under test.riders

var faction_events: Array = []
var messages: Array = []


func before_each() -> void:
	await super()
	FactionState.reset_for_tests()
	faction_events.clear()
	messages.clear()
	Events.faction_changed.connect(_on_faction_changed)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for pair: Array in [[Events.faction_changed, _on_faction_changed], [Events.hud_message, _on_message]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	await super()


func _on_faction_changed(tick: int, faction: String, state: String) -> void:
	faction_events.append([tick, faction, state])


func _on_message(text: String, kind: String) -> void:
	messages.append([text, kind])


func _events(faction: String, state: String) -> Array:
	return faction_events.filter(func(e: Array) -> bool: return e[1] == faction and e[2] == state)


## A direct blow of the giant (team PLAYER) on `target_id`, through the real resolution path.
func _blow(target_id: String, from: Vector3) -> void:
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = "player"
	e.target_id = target_id
	e.action_id = "ability.light_1"
	e.power = 5.0
	e.attacker_stat = 10.0
	e.attacker_height_m = 3.6576
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee", "Light", "BasicAttack"])
	e.attacker_position = from
	Sim.queue_hit(e)


func test_each_faction_reads_its_record() -> void:
	var known := FactionState.known_factions()
	for f: String in ["village", TOWN, RIDERS]:
		assert_true(known.has(f), "%s has a record" % f)
	# Thornwick: M5's numbers and texts, now in its record.
	assert_eq([FactionState.offences_to_hostile("village"), FactionState.offence_window_s("village"),
		FactionState.initial("village"), FactionState.give_way_m("village")], [2, 30.0, "neutral", 0.0],
		"village: 2 offences in 30 s, neutral, its villagers flee")
	assert_eq(FactionState.flag_id("village", "hostile"), "faction.village.hostile", "village flags")
	assert_eq(FactionState.text_for("village", "warned"), str(GameData.get_record("faction.village").warn_text),
		"village: its own warning")
	assert_eq([FactionState.offences_to_hostile(TOWN), FactionState.offence_window_s(TOWN),
		FactionState.initial(TOWN), FactionState.give_way_m(TOWN)], [3, 10.0, "neutral", 3.0],
		"town: 3 offences in 10 s, its civilians give way 3 m")
	assert_eq(FactionState.flag_id(RIDERS, "hostile"), "test.riders.hostile", "riders: their own prefix")
	assert_eq(FactionState.faction_of_prefix("test.riders"), RIDERS, "and the prefix names them")
	assert_eq(FactionState.initial(RIDERS), "hostile", "riders: hostile from the start")
	# A faction without a record keeps the M5 rules and the generic texts.
	assert_eq([FactionState.offences_to_hostile("nobody"), FactionState.offence_window_s("nobody"),
		FactionState.initial("nobody"), FactionState.give_way_m("nobody"), FactionState.flag_id("nobody", "warned")],
		[2, 30.0, "neutral", 0.0, "faction.nobody.warned"], "no record: the M5 defaults")
	assert_eq(FactionState.text_for("nobody", "hostile"), FactionState.FALLBACK_TEXTS.hostile, "and the generic line")
	# Three in a row within the window (pure).
	var w := 600
	assert_eq(FactionState.offence_result_n(true, [100, 400], 700, w, 3), "hostile", "3 in a row: hostile")
	assert_eq(FactionState.offence_result_n(true, [100, 400], 1100, w, 3), "warned", "a gap breaks the chain")
	assert_eq(FactionState.offence_result_n(false, [], 100, w, 1), "hostile", "1 needed: hostile at once")


func test_reconciled_wins_over_hostile_until_the_next_offence() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	var guard: SoldierEnemy = (load(SOLDIER) as PackedScene).instantiate()
	guard.entity_id = "test.rider"
	guard.ai_enabled = false
	guard.faction = RIDERS
	guard.position = Vector3(0, 0.05, -6)
	world.add_child(guard)
	await step_ticks(2)
	assert_eq(FactionState.standing(RIDERS), "hostile", "the riders' initial disposition: hostile")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "a rider spawns as an enemy")
	FactionState.reconcile(RIDERS)
	await step_ticks(1)
	assert_eq(WorldState.get_flag("test.riders.reconciled"), true, "reconciled under their prefix")
	assert_eq(FactionState.standing(RIDERS), "reconciled", "reconciled wins over the initial hostility")
	assert_false(FactionState.is_hostile(RIDERS), "not hostile")
	assert_eq(_events(RIDERS, "reconciled").size(), 1, "announced once")
	assert_true(messages.has(["The riders let you pass.", "good"]), "with the record's line")
	assert_eq(guard.entity.team, CombatEntity.Team.NEUTRAL, "the rider stands at peace")
	assert_true(guard.member_at_peace(), "a member at peace")
	# The village too: a hostile flag, then reconciled.
	WorldState.set_flag("faction.village.hostile", true)
	assert_eq(FactionState.standing("village"), "hostile", "village hostile")
	FactionState.reconcile("village")
	assert_eq(FactionState.standing("village"), "reconciled", "reconciled wins over the hostile flag")
	# One offence turns the riders hostile again (offences_to_hostile 1): reconciled is cleared.
	_blow("test.rider", Vector3(0, 0, 0))
	await step_ticks(2)
	assert_eq(FactionState.standing(RIDERS), "hostile", "an offence undoes the reconciliation")
	assert_eq(WorldState.get_flag("test.riders.reconciled"), false, "the flag is cleared")
	assert_eq(_events(RIDERS, "hostile").size(), 1, "hostile announced")
	assert_true(messages.has(["The riders draw steel.", "bad"]), "with the record's line")
	assert_eq(guard.entity.team, CombatEntity.Team.ENEMY, "the rider fights again")


func test_damage_to_a_faction_house_is_an_offence() -> void:
	spawn_player(Vector3(0, 0.05, 0))
	var houses: Array[BreakableProp] = []
	for i in 3:
		var f := spawn_fence(Vector3(-4.0 + 4.0 * i, 0.05, -4), "test.house_%d" % i)
		f.set_meta(&"faction", TOWN)
		f.set_meta(&"prop_tags", PackedStringArray(["house"]))
		houses.append(f)
	var shed := spawn_fence(Vector3(0, 0.05, 5), "test.shed")
	shed.set_meta(&"faction", TOWN)
	shed.set_meta(&"prop_tags", PackedStringArray(["fence"]))
	var wild := spawn_fence(Vector3(5, 0.05, 5), "test.wild_house")
	wild.set_meta(&"prop_tags", PackedStringArray(["house"]))
	await step_ticks(2)
	# A fence of the town and a house of no faction: no offence.
	_blow("test.shed", Vector3(0, 0, 3))
	_blow("test.wild_house", Vector3(4, 0, 3))
	await step_ticks(2)
	assert_true(hits_on("test.shed").size() == 1 and hits_on("test.wild_house").size() == 1, "both were struck")
	assert_eq(FactionState.standing(TOWN), "neutral", "a fence or a house of no one offends no one")
	# Its houses: warned, warned again, then hostile (three within 10 s).
	var expected := ["warned", "warned", "hostile"]
	for i in 3:
		_blow("test.house_%d" % i, Vector3(-4.0 + 4.0 * i, 0, -2))
		await step_ticks(2)
		assert_eq(FactionState.standing(TOWN), expected[i], "house %d: %s" % [i, expected[i]])
	assert_eq(_events(TOWN, "warned").size(), 2, "two warnings")
	assert_eq(_events(TOWN, "hostile").size(), 1, "then hostile")
	assert_true(messages.has(["The test town's folk scatter from your feet.", "warn"]), "the town's warning")
	var hub := FactionState.hub()
	assert_eq(hub.history.size(), 3, "three offences, one per blow")
	assert_eq(str(hub.history[2].target), "test.house_2", "the third was the last house")


func test_a_give_way_civilian_steps_aside_and_does_not_flee() -> void:
	var rec := GameData.get_record("npc.villager")
	var b := CivilianBrain.new("test.townsfolk", rec)
	b.faction = TOWN
	var me := Vector3(1.0, 0, -8)
	var giant := 3.6576
	# The giant 8 m away walks toward it at 5 m/s (two perceptions, 10 ticks apart).
	b.perceive(100, {"exists": true, "position": Vector3.ZERO, "distance": 8.06, "speed": 0.0, "height": giant})
	b.perceive(110, {"exists": true, "position": Vector3(0, 0, -0.83), "distance": 7.24, "speed": 5.0, "height": giant})
	assert_eq(b.state, CivilianBrain.State.GIVE_WAY, "it gives way instead of fleeing")
	b.decide(110, me, true)
	var clearance := 3.0 + giant
	assert_near(b.give_way_clearance(), clearance, 1e-3, "give_way_m plus the giant's height")
	assert_true(b.move_target != Vector3.INF, "it steps somewhere")
	if b.move_target != Vector3.INF:
		assert_near(b.move_target.x, clearance + CivilianBrain.GIVE_WAY_MARGIN_M, 1e-3,
			"to the side of the giant's line, on its own side, just clear (%.2f m)" % b.move_target.x)
		assert_near(b.move_target.z, me.z, 1e-3, "straight sideways")
	# Arrived: it stands and watches; the giant passing by never sends it running.
	var aside := Vector3(clearance + CivilianBrain.GIVE_WAY_MARGIN_M, 0, me.z)
	b.decide(115, aside, true)
	assert_eq(b.state, CivilianBrain.State.IDLE, "it stands")
	for t in range(120, 240, 10):
		var gz := -0.83 - 5.0 * float(t - 110) / 60.0
		b.perceive(t, {"exists": true, "position": Vector3(0, 0, gz), "distance": Vector2(aside.x, aside.z - gz).length(),
			"speed": 5.0, "height": giant})
		b.decide(t, aside, true)
		assert_true(b.state != CivilianBrain.State.FLEE, "tick %d: no flight (%s)" % [t, b.state_name()])
	assert_eq(b.picks, 0, "it never looked for shelter")
	assert_eq(b.flee_reason, "", "no reason to flee")
	# Warned, the town's civilians flee as Thornwick's always do.
	WorldState.set_flag("faction.test_town.warned", true)
	var c := CivilianBrain.new("test.townsfolk_2", rec)
	c.faction = TOWN
	c.perceive(100, {"exists": true, "position": Vector3.ZERO, "distance": 8.06, "speed": 0.0, "height": giant})
	c.perceive(110, {"exists": true, "position": Vector3(0, 0, -0.83), "distance": 7.24, "speed": 5.0, "height": giant})
	assert_eq(c.state, CivilianBrain.State.FLEE, "a warned town's civilian flees")
	var v := CivilianBrain.new("test.villager", rec)
	v.faction = "village"
	v.perceive(100, {"exists": true, "position": Vector3.ZERO, "distance": 8.06, "speed": 0.0, "height": giant})
	v.perceive(110, {"exists": true, "position": Vector3(0, 0, -0.83), "distance": 7.24, "speed": 5.0, "height": giant})
	assert_eq(v.state, CivilianBrain.State.FLEE, "Thornwick's villagers still flee (the Valley is unchanged)")
