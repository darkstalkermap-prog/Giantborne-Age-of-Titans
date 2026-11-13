extends IntegrationSuite
## M9 gate (final round; docs/systems/P39.md, "M9 gate (final)"): the slow-tier tests of the final audit's fixes.
##   * F2: the clans' giants watching the Moot (encounter.stonehold_moot_clans, faction skarn, AI off) stand 6 m
##     outside the ring's 60 m wall, within a stage-6 giant's 13.6 m reach while it fights Harrok near the ring's
##     stones: its light swings at Harrok struck a watcher, P11b counted each such blow an offence, and two within
##     30 s turned Skarn hostile for good (the gate's conqueror expert struck one for the throne stage's 306 s). The
##     watchers are spectators now (the spawns' `spectator`, FactionState.offended_faction): the blows that strike
##     them offend no faction; any other Skarn giant (its steading's) still takes offence as before.

const RIVAL := "res://scenes/enemies/rival_giant.tscn"
const CLANS := "encounter.stonehold_moot_clans"


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _rival(pos: Vector3, id: String, faction: String, spectator: bool, yaw := 0.0) -> EnemyActor:
	var e := (load(RIVAL) as PackedScene).instantiate() as EnemyActor
	e.entity_id = id
	e.ai_enabled = false
	e.faction = faction
	e.spectator = spectator
	e.position = pos
	e.rotation.y = yaw
	world.add_child(e)
	return e


## A stage-6 giant with the Titanforged Club swinging six light blows at a hostile rival giant 9 m before it, with
## Skarn giants standing 11.7 m from it at 40 and 60 degrees off its aim (the distance the gate's conqueror expert
## stood from world.stonehold.moot_watcher_4 while fighting Harrok): [hits on the Skarn giants, Skarn warned, hostile].
func _swing_case(spectators: bool) -> Array:
	FactionState.reset_for_tests()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(6))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	var eq: Variant = p.get("equipment")
	if eq != null:
		eq.call("grant_weapon", "weapon.club_titan", true)
	await step_ticks(2)
	var tag := "spec" if spectators else "ord"
	var foe_id := "test.m9f_foe_" + tag
	_rival(Vector3(0, 0.05, -9.0), foe_id, "", false)
	var watchers: Array[EnemyActor] = []
	for deg: float in [40.0, 60.0]:
		var r := deg_to_rad(deg)
		watchers.append(_rival(Vector3(11.7 * sin(r), 0.05, -11.7 * cos(r)), "test.m9f_skarn_%s_%d" % [tag, int(deg)], "skarn",
			spectators, PI))
	await step_ticks(10)
	p.camera_rig.yaw = 0.0
	for i in 6:
		p.router.inject_edge(&"light")
		await step_ticks(71)
	await step_ticks(30)
	var hits := 0
	for wa: EnemyActor in watchers:
		hits += hits_on(wa.entity.entity_id).size()
	var out := [hits, QuestConditions.truthy(WorldState.get_flag("faction.skarn.warned")),
		QuestConditions.truthy(WorldState.get_flag("faction.skarn.hostile")), hits_on(foe_id).size()]
	print("    m9 final (F2): %s Skarn giants - %d of the giant's blows struck them (the foe %d); Skarn warned %s, hostile %s" % [
		"spectator" if spectators else "ordinary", out[0], out[3], out[1], out[2]])
	p.queue_free()
	for wa: EnemyActor in watchers:
		wa.queue_free()
	var foe := Sim.get_entity(foe_id)
	if foe != null and is_instance_valid(foe.actor):
		foe.actor.queue_free()
	await step_ticks(3)
	return out


func test_the_moot_watchers_are_spectators_whose_blows_offend_no_one() -> void:
	# The data: the six watchers are spectators, every other Skarn member is not.
	var watchers := 0
	for enc: Dictionary in GameData.records_of_type("encounter"):
		for s: Variant in enc.get("spawns", []):
			if typeof(s) != TYPE_DICTIONARY:
				continue
			if str(enc.get("id", "")) == CLANS:
				watchers += 1
				assert_true(bool(s.get("spectator", false)), "%s watches the Moot: a spectator" % s.get("entity_id"))
			elif str(s.get("faction", "")) == "skarn":
				assert_false(bool(s.get("spectator", false)), "%s (%s) takes offence as before" % [s.get("entity_id"), enc.get("id")])
	assert_eq(watchers, 6, "six giants watch the Moot")
	# The swings: the blows reach the watchers either way; only an ordinary Skarn giant takes offence.
	var spectator: Array = await _swing_case(true)
	assert_true(int(spectator[3]) >= 4, "the giant's light blows land on the foe (%d)" % int(spectator[3]))
	assert_true(int(spectator[0]) >= 2, "the swings at the foe strike the watchers beside it (%d blows)" % int(spectator[0]))
	assert_false(bool(spectator[1]), "no warning from Skarn for the watchers struck")
	assert_false(bool(spectator[2]), "Skarn does not turn hostile")
	var ordinary: Array = await _swing_case(false)
	assert_true(int(ordinary[0]) >= 2, "the same swings strike ordinary Skarn giants (%d blows)" % int(ordinary[0]))
	assert_true(bool(ordinary[1]) or bool(ordinary[2]), "and an ordinary Skarn giant struck takes offence (P11b kept)")
