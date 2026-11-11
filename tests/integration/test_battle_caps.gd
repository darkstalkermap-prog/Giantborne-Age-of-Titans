extends IntegrationSuite
## M8 gate (F9; plan M6-M9 §3.20 "every battle fits the caps on both platforms", §2.10 the bar's
## "aggregate health of what actually spawned", §5.13 "felling a banner breaks its formation's morale"):
## on scenes/test/bailey_test.tscn with a garrison of its own outside the battle (a test record like Fort
## Aldmere's gate garrison: a pike formation of ten and its banner, two archers) and the level's caps
## made tight:
##   * on the web the battle stands that garrison out when it engages (BattleBoss.stand_out): the Wall
##     musters whole within the formation cap, and the bar counts what spawned;
##   * while the battle is engaged its units still to come keep their room (EncounterDirector.p34_reserve):
##     the garrison, coming back, waits for room, and the Charge's riders spawn whole within the
##     combatants' budget;
##   * a formation short of room in the cap fields its banner before its rank and file.

const BAILEY := "res://scenes/test/bailey_test.tscn"
const WALL := "encounter.bailey_test_wall"
const CHARGE := "encounter.bailey_test_charge"
const GATE := "encounter.bailey_test_gate_garrison"


func after_each() -> void:
	LevelRoot.force_web_for_tests = false
	TestFixtures.restore_all()
	Quests.end_dialogue()
	await super()


## The test garrison: ten pikes and a banner in a formation (web scale 0.7: seven and the banner) and two
## archers, inert, near the bailey's gate; it waits for a flag no one sets (the test activates it).
static func _garrison() -> Dictionary:
	var spawns: Array = []
	for i in 10:
		spawns.append({"entity_id": "test.bailey.gate_pike_%d" % (i + 1), "definition": "enemy.pikeman",
			"position_m": [40.0 + float(i % 5) * 1.6, 0.05, 30.0 + float(i / 5) * 2.2], "yaw_deg": 0,
			"ai_enabled": false, "persist_death": true, "formation": "pikes", "slot": i})
	spawns.append({"entity_id": "test.bailey.gate_banner", "definition": "enemy.bannerman",
		"position_m": [43.2, 0.05, 34.4], "yaw_deg": 0, "ai_enabled": false, "persist_death": true,
		"formation": "pikes", "slot": -1})
	for i in 2:
		spawns.append({"entity_id": "test.bailey.gate_archer_%d" % (i + 1), "definition": "enemy.archer",
			"position_m": [34.0 - float(i) * 3.0, 0.05, 30.0], "yaw_deg": 0, "ai_enabled": false, "persist_death": true})
	return {"schema_version": 1, "id": GATE, "type": "encounter", "level": "level.bailey_test",
		"display_name": "Test bailey: a gate garrison", "center_m": [40, 0, 32], "activate_radius_m": 10,
		"deactivate_radius_m": 400, "leash_radius_m": 60, "alert_group": false,
		"requires_flags": ["test.bailey.manual"], "forbids_flags": [], "counts_toward_budget": true,
		"web_formation_scale": 0.7,
		"formations": [{"id": "pikes", "kind": "pike", "banner": "test.bailey.gate_banner", "ranks": 2, "files": 5,
			"rank_spacing_m": 2.2, "file_spacing_m": 1.6, "facing": "fixed", "yaw_deg": 0}],
		"spawns": spawns}


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "test.nobody"
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = e.actor.global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


func _spawned(d: EncounterDirector, enc: String) -> Array:
	return Array(d.members_of(enc)).filter(func(id: String) -> bool: return d.member_status(id) == EncounterDirector.SPAWNED)


func _level() -> Node3D:
	var level := (load(BAILEY) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	p.global_position = Vector3(0, 0.05, 30)
	return level


func test_the_battle_stands_the_garrison_out_and_keeps_its_room() -> void:
	LevelRoot.force_web_for_tests = true
	TestFixtures.record_override(GATE, _garrison())
	var level := await _level()
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	assert_true(d.encounter_ids().has(GATE), "the garrison is one of the level's encounters")
	d.p30_formation_room()   # loads the level's cap: the web's
	assert_eq(d.max_formation_members, 20, "the web's formation cap")
	d.max_formation_members = 12   # tight: the garrison's eight and the Wall's nine do not fit together
	d.max_active_enemies = 5   # tight: the Charge's four riders and one more
	d.force_activate(GATE)
	d.update_now()
	var garrison := _spawned(d, GATE)
	assert_eq(garrison.size(), 10, "the garrison stands: seven pikes and the banner (the web's 0.7) and two archers")
	battle.stand_out = PackedStringArray([GATE])
	battle.engage()
	await step_ticks(2)
	assert_eq(battle.stood_out.size(), 10, "the battle stands the garrison out (%s)" % [battle.stood_out])
	for id: String in garrison:
		assert_eq(d.member_status(id), EncounterDirector.DESPAWNED, "%s left (it comes back on its next activation)" % id)
	# The Wall musters whole within the cap; the bar counts what spawned.
	var planned := battle.planned()
	var wall := Array(d.members_of(WALL)).filter(func(id: String) -> bool: return planned.has(id))
	assert_eq(wall.size(), 9, "the web's Wall: eight shields and the banner")
	for id: String in wall:
		assert_eq(d.member_status(id), EncounterDirector.SPAWNED, "%s spawned" % id)
	assert_true(d.formation_member_count() <= d.max_formation_members, "within the cap (%d)" % d.formation_member_count())
	var counted := 0.0
	for id: String in planned:
		var e := Sim.get_entity(id)
		counted += e.combatant.pools.health if e != null and e.combatant != null else float(planned[id])
	assert_near(float(battle.aggregate().current), counted, 0.01, "the bar counts the units that spawned (and the phases to come)")
	# The garrison comes back meanwhile: it waits for the room the battle keeps for its units to come.
	d.force_activate(GATE)
	d.update_now()
	var back := _spawned(d, GATE)
	assert_eq(back.size(), 1, "one archer beside the four riders' room in the budget of five, no pike beside the guard's (%s)" % [back])
	assert_true(d.p34_is_reserved("test.bailey.rider_1"), "the riders' room is the battle's")
	# The Wall falls: the Charge's four riders all spawn.
	for id: String in wall:
		_kill(id)
	await step_ticks(3)
	assert_eq(battle.phase_log, [1, 2] as Array[int], "The Charge")
	assert_eq(_spawned(d, CHARGE).size(), 4, "its four riders, whole")
	assert_true(d.active_combatant_count() <= d.max_active_enemies, "within the budget")


func test_a_formation_short_of_room_fields_its_banner_first() -> void:
	var level := await _level()
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	d.p30_formation_room()
	d.max_formation_members = 5
	battle.engage()
	await step_ticks(2)
	var up := _spawned(d, WALL)
	assert_eq(up.size(), 5, "five of the Wall in the cap of five")
	assert_true(up.has("test.bailey.wall_banner"), "its banner among them (%s)" % [up])
	var f: Formation = null
	for x: Formation in d.formations():
		if x.encounter_id == WALL:
			f = x
	assert_true(f != null and f.banner_alive(), "the Wall stands behind its banner")
