extends IntegrationSuite
## M9 gate (final round; docs/systems/P39.md, "M9 gate (final)"): the slow-tier tests of the final audit's fixes.
##   * F2: the clans' giants watching the Moot (encounter.stonehold_moot_clans, faction skarn, AI off) stand 6 m
##     outside the ring's 60 m wall, within a stage-6 giant's 13.6 m reach while it fights Harrok near the ring's
##     stones: its light swings at Harrok struck a watcher, P11b counted each such blow an offence, and two within
##     30 s turned Skarn hostile for good (the gate's conqueror expert struck one for the throne stage's 306 s). The
##     watchers are spectators now (the spawns' `spectator`, FactionState.offended_faction): the blows that strike
##     them offend no faction; any other Skarn giant (its steading's) still takes offence as before.
##   * F4/F12: a crewed siege engine's shot that lands on the giant raises combat music (its crew's hit; decision
##     6: crews count). The engine's projectile belongs to the engine's prop entity, which CueRouter left out with
##     every other prop, and since the M9 gate's combat cap (40 m from a stage-4+ giant) a barrage from a battery
##     50-60 m off stayed at danger. Through the real router into Audio.music: danger before a stone lands, combat
##     within 5 s after it; a lone soldier's blow still raises danger only, a blow on a crate notes nothing.

const RIVAL := "res://scenes/enemies/rival_giant.tscn"
const CLANS := "encounter.stonehold_moot_clans"
const CATAPULT := "res://scenes/world/siege_catapult.tscn"
const CREW := "res://scenes/enemies/siege_crew.tscn"
const CRATE := "res://scenes/world/crate.tscn"


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


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


## The music's intensity target now, from the director's own snapshot of the live actors and its hit ages.
func _target() -> String:
	return AudioMath.intensity_target(Audio.music.intensity_snapshot(), Audio.mix.get("intensity", {}) as Dictionary)


func test_an_engines_shot_raises_combat_music_as_its_crews_hit() -> void:
	Audio.enable_for_tests()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(6))
	p.entity.combatant.unkillable = true
	await step_ticks(5)
	var e := (load(CATAPULT) as PackedScene).instantiate() as SiegeEngine
	e.world_id = "test.m9f_catapult"
	e.position = Vector3(0, 0, -55.0)
	e.rotation.y = TargetingRules.yaw_of(Vector3(0, 0, 55.0))
	world.add_child(e)
	var crew := TestSpawn.enemy(world, CREW, e.global_position + Vector3(0, 0.05, 0), "test.m9f_crew", true, e.rotation.y)
	e.add_crew(crew)
	crew.global_position = e.crew_slot(crew) + Vector3(0, 0.05, 0)
	await step_ticks(10)
	var before := ""
	var landed := -1
	var after: Array = []
	for i in 40 * 4:
		if crew.brain != null and not crew.brain.aware:
			crew.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)   # the director's alert group
		await step_ticks(15)
		var hits := hits_on(p.entity.entity_id).filter(func(r: HitResult) -> bool:
			return r.event.attacker_id == e.entity.entity_id and r.outcome != HitResult.Outcome.IGNORED)
		if hits.is_empty():
			before = _target()   # the last sample before the first stone lands
		elif landed < 0:
			landed = Sim.tick
		if landed >= 0:
			after.append(_target())
			if Sim.tick - landed >= 5 * 60 - 15:
				break
	var age := float(Audio.music.intensity_snapshot().get("combat_hit_age_s", INF))
	print("    m9 final (F4/F12): catapult 55 m off a stage-6 giant, crew aware %s: before the first stone %s, the 5 s after it %s (combat hit age %.2f s)" % [
		crew.brain.aware if crew.brain != null else false, before, after, age])
	assert_true(landed >= 0, "a stone lands on the giant")
	assert_eq(before, AudioMath.DANGER, "before any stone lands the battery 55 m off raises danger (the combat cap)")
	assert_true(after.size() >= 2 and after.all(func(t: String) -> bool: return t == AudioMath.COMBAT),
		"within 5 s after the stone lands the music is in combat (%s)" % [after])
	e.queue_free()
	crew.queue_free()
	await step_ticks(3)
	# The controls: a lone soldier's blow raises danger only, the giant's blow on a crate notes nothing.
	await step_ticks(int(6.0 * 60))
	var soldier := TestSpawn.enemy(world, SOLDIER, Vector3(0, 0.05, -60.0), "test.m9f_soldier", true, 0.0)
	await step_ticks(2)
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = soldier.entity.entity_id
	h.target_id = p.entity.entity_id
	h.power = 10.0
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.category = "melee"
	h.attacker_position = p.global_position + Vector3(0, 0, -3)
	Sim.queue_hit(h)
	await step_ticks(3)
	var snap: Dictionary = Audio.music.intensity_snapshot()
	print("    m9 final (F4/F12): a lone soldier's blow - combat hit age %.2f s, lesser hit age %.2f s" % [
		float(snap.get("combat_hit_age_s", INF)), float(snap.get("lesser_hit_age_s", INF))])
	assert_true(float(snap.get("lesser_hit_age_s", INF)) <= 1.0, "a lone soldier's blow is noted as a lesser hit")
	assert_true(float(snap.get("combat_hit_age_s", INF)) > 5.0, "...not as combat's")
	soldier.queue_free()
	await step_ticks(2)
	var crate := (load(CRATE) as PackedScene).instantiate() as Node3D
	crate.set("world_id", "test.m9f_crate")
	crate.position = Vector3(0, 0.05, -12.0)
	world.add_child(crate)
	await step_ticks(2)
	var age0 := float(Audio.music.intensity_snapshot().get("combat_hit_age_s", INF))
	var ce := crate.get("entity") as CombatEntity
	assert_true(ce != null, "the crate stands")
	if ce != null:
		var hc := HitEvent.new()
		hc.tick = Sim.tick
		hc.instance_id = Sim.new_instance_id()
		hc.attacker_id = p.entity.entity_id
		hc.target_id = ce.entity_id
		hc.power = 50.0
		hc.damage_split = {"physical": 1.0}
		hc.tags = PackedStringArray(["Melee"])
		hc.category = "melee"
		hc.attacker_position = crate.global_position + Vector3(0, 0, 6)
		Sim.queue_hit(hc)
		await step_ticks(3)
		assert_true(hits_on(ce.entity_id).size() >= 1, "the giant's blow reaches the crate")
		assert_true(float(Audio.music.intensity_snapshot().get("combat_hit_age_s", INF)) >= age0,
			"the giant's blow on a crate notes no hit")
	crate.queue_free()
	p.queue_free()
	await step_ticks(3)
