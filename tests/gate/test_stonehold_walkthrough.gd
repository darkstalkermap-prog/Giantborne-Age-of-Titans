extends IntegrationSuite
## The Stonehold walkthrough (P36; plan M6-M9 §3.20, §5.7, §5.9, §5.10, §5.13 boss 3):
##   * the siege of Skarn on the real world (scenes/world/world.tscn, deterministic streaming, the living
##     world on): Ulfra's plea to a stage-5 giant starts it - its five engines appear with it, their crews
##     take them; the line holds its fire while the giant is more than 200 m from Skarn's longhouses (no
##     longhouse loses health) and bombards them when it comes back - its shots strike them and they lose
##     health (M8 gate, F12); breaking the engines breaks the line (its soldiers rout) and Skarn is saved -
##     300 XP, the titan iron, Skarn's support and its forge;
##   * Skarn burned in play (M8 gate, F12): a giant that stands by Skarn out of the engines' reach and breaks
##     nothing watches the line's fire bring down two longhouses - the siege ends burned, its quest is lost
##     and the rebuilding errand begins;
##   * Skarn burned instead: two longhouses fall, the siege quest is lost and the rebuilding errand begins -
##     a stage-6 giant lifts the beams of two burned halls, Skarn stands with it again and its forge opens;
##   * the Moot battery's engines at stage 6: refused to a stage-5 giant, seized by a stage-6 one and thrown;
##   * the Giant's Stair and the Moot's gate admit only stage 6 and say so (M8 gate F29: "Grow to stage 6", the
##     Stair's message the Ironway too), the Stair's head reveals 600 m, entering
##     the Moot completes its stage, and the champion's three outcomes - spared (his clan reconciled, the
##     clans watch the crowning), slain (the Moot empties, his clan stays hostile) and the talk ending (no
##     fight: the ring stays quiet) - each lets the giant take the Stone Throne;
##   * M8 gate fix-up 1 (N4.6): Harrok's challenge stone stands beyond the Moot's disengage line (95.8 m from
##     the ring's centre, the line at 80 m), and a stage-6 giant answering it - within its reach on the ring's
##     side - stands on the fight's ground (BossArena.at_boss_talker): no leaving warning, no reset.

const START_CP := "world.cp.kingsgate_shelf"
const MAIN := "quest.world_main"
const SCENE := "res://scenes/world/world.tscn"
const SIEGE := "event.siege_of_skarn"
const LONGHOUSES := ["world.stonehold.skarn_longhouse_1", "world.stonehold.skarn_longhouse_2",
	"world.stonehold.skarn_longhouse_3"]
const SKARN_PART := "res://scenes/world/chunks/c5_1_0.tscn"
const BATTERY_PART := "res://scenes/world/chunks/c3_1_0.tscn"
const STAIR_PART := "res://scenes/world/chunks/c4_2_0.tscn"
const MOOT_PARTS := ["res://scenes/world/chunks/c4_1_0.tscn", "res://scenes/world/chunks/c4_0_0.tscn"]
const HARROK := "world.stonehold.harrok"


var _engine_hits: Array = []   ## [target id, health damage] of the siege line's hits on a longhouse


func before_each() -> void:
	await super()
	_engine_hits.clear()
	Events.hit_resolved.connect(_on_hit_resolved)


func _on_hit_resolved(_tick: int, result: HitResult) -> void:
	if result == null or result.event == null:
		return
	var hit := result.event
	if hit.attacker_id.begins_with("world.stonehold.siege_") and LONGHOUSES.has(hit.target_id) and result.health_damage > 0:
		_engine_hits.append([hit.target_id, result.health_damage])


func after_each() -> void:
	if Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.disconnect(_on_hit_resolved)
	Quests.end_dialogue()
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _settle() -> void:
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)


func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


func _find(root: Node, world_id: String) -> Node:
	for n in root.find_children("*", "", true, false):
		if "world_id" in n and str(n.get("world_id")) == world_id:
			return n
	return null


func _part(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	return part


## Breaks a prop or an engine with heavy blows from `attacker` (at most 80).
func _break(world_id: String, attacker: String, stage := 6) -> bool:
	for i in 80:
		if WorldState.is_destroyed(world_id):
			return true
		var e := Sim.get_entity(world_id)
		if e == null:
			fail("%s has no entity" % world_id)
			return false
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = attacker
		h.target_id = world_id
		h.power = 1200.0
		h.attacker_stat = 40.0
		h.attacker_height_m = 20.0
		h.damage_split = {"physical": 1.0}
		h.poise_damage = 50.0
		h.tags = PackedStringArray(["Melee"])
		h.category = "siege"
		h.attacker_growth_stage = stage
		h.attacker_position = (e.actor as Node3D).global_position + Vector3(0, 0, 8) if e.actor != null else Vector3.ZERO
		Sim.queue_hit(h)
		await step_ticks(1)
	return WorldState.is_destroyed(world_id)


# --------------------------------------------------------------------------- the siege of Skarn, saved

func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _move(w, xz)
	return w


func _move(w: WorldRoot, xz: Vector2) -> void:
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


func _siege_engines(w: Node) -> Array:
	return w.get_tree().get_nodes_in_group(SiegeEngine.GROUP).filter(func(n: Node) -> bool:
		return str((n as SiegeEngine).siege_group) == "skarn_siege")


func _longhouse_health() -> Array:
	return LONGHOUSES.map(func(id: String) -> float:
		var e := Sim.get_entity(id)
		return e.combatant.pools.health if e != null else -1.0)


func test_the_siege_of_skarn_saved_on_the_real_world() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	var w: WorldRoot = await _world(Vector2(440.0, -600.0))
	var p := w.player()
	p.set_profile(_profile(5))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(5)
	var wd := w.get_node_or_null("WanderDirector") as WanderDirector
	assert_true(wd != null and wd.events.has(SIEGE), "the siege is one of the world's events")
	if wd == null or not wd.events.has(SIEGE):
		return
	var siege: WorldEvent = wd.events[SIEGE]
	assert_eq(_siege_engines(w).size(), 0, "no siege line before the siege")
	assert_true(siege.can_start_with(wd.event_context(siege)) != "", "a stage-5 giant without Ulfra's plea starts nothing")
	var s := Quests.start_dialogue("dialogue.ulfra", "world.stonehold.ulfra")
	assert_true(s != null and s.find_choice("plea") >= 0, "Ulfra pleads with a stage-5 giant")
	if s != null:
		s.choose_outcome("plea")
	Quests.end_dialogue()
	assert_eq(siege.can_start_with(wd.event_context(siege)), "", "her plea accepted, the siege's rules hold")
	wd.check_events(Sim.tick)
	assert_eq(wd.running_event(), siege, "the siege starts")
	await step_ticks(30)
	var engines := _siege_engines(w)
	assert_eq(engines.size(), 5, "its five engines appear with it")
	var crewed := 0
	for i in 40:
		await step_ticks(15)
		crewed = engines.filter(func(e: SiegeEngine) -> bool: return e.crew_count() > 0).size()
		if crewed == engines.size():
			break
	assert_eq(crewed, 5, "their crews take them")
	# away from Skarn: no longhouse within 200 m of the giant, the line holds its fire
	await _move(w, Vector2(650.0, -860.0))
	var before := _longhouse_health()
	for e: SiegeEngine in engines:
		assert_true(e.p36_bombard_target(p.entity) == null, "%s holds its fire while the giant is far" % e.world_id)
	await step_ticks(60 * 12)
	assert_eq(_longhouse_health(), before, "the siege's clock stands still beyond 200 m")
	await _move(w, Vector2(440.0, -600.0))
	var bombarding := 0
	for e: SiegeEngine in engines:
		if e.p36_bombard_target(p.entity) != null:
			bombarding += 1
	assert_true(bombarding > 0, "back at Skarn the line bombards its longhouses (%d engines)" % bombarding)
	var struck: bool = await TestWait.until(self, func() -> bool: return not _engine_hits.is_empty(), 60 * 45)
	assert_true(struck, "the engines' shots strike a longhouse (M8 gate, F12)")
	var after := _longhouse_health()
	var lost := false
	for i in after.size():
		lost = lost or float(after[i]) < float(before[i])
	assert_true(lost, "a longhouse loses health to the engines' fire (%s -> %s)" % [before, after])
	for e: SiegeEngine in engines:
		assert_true(await _break(e.world_id, p.entity.entity_id), "%s is broken" % e.world_id)
	var done: bool = await TestWait.until(self, func() -> bool: return not siege.is_running(), 60 * 20)
	assert_true(done, "the siege ends")
	assert_eq(str(WorldState.get_flag("%s.outcome" % SIEGE, "")), "saved", "Skarn is saved")
	await _settle()
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.COMPLETED, "the siege of Skarn's quest is won")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.skarn.support")), "Skarn stands with the giant")
	var forge := _find(w, "world.stonehold.skarn_forge") as ConditionForge
	assert_true(forge != null and forge.is_open(), "Skarn's hearth-forge opens")


# --------------------------------------------------------------------------- Skarn burned in play (M8 gate, F12)

## West of the steading: within 200 m of the longhouses the engines aim at, beyond every engine's range
## (the catapults' 180 m, the ballistae's 140 m) - the whole line bombards the halls.
const OUT_OF_REACH := Vector2(330.0, -650.0)


func test_skarn_burned_by_the_siege_lines_fire_in_play() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	var w: WorldRoot = await _world(Vector2(440.0, -600.0))
	var p := w.player()
	p.set_profile(_profile(5))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(5)
	var wd := w.get_node_or_null("WanderDirector") as WanderDirector
	var siege: WorldEvent = wd.events[SIEGE]
	var s := Quests.start_dialogue("dialogue.ulfra", "world.stonehold.ulfra")
	if s != null:
		s.choose_outcome("plea")
	Quests.end_dialogue()
	wd.check_events(Sim.tick)
	assert_eq(wd.running_event(), siege, "the siege starts")
	var started := Sim.tick
	await _move(w, OUT_OF_REACH)
	var engines := _siege_engines(w)
	assert_eq(engines.size(), 5, "its five engines")
	var reach := 0
	for e: SiegeEngine in engines:
		if e.can_reach(p.entity):
			reach += 1
	assert_eq(reach, 0, "the giant stands out of every engine's reach")
	# the giant breaks nothing: the line's fire alone decides (at most 8 minutes of play)
	var done: bool = await TestWait.until(self, func() -> bool: return not siege.is_running(), 60 * 60 * 8)
	assert_true(done, "the siege ends")
	assert_eq(str(WorldState.get_flag("%s.outcome" % SIEGE, "")), "burned", "Skarn burns")
	var fallen := LONGHOUSES.filter(func(id: String) -> bool: return WorldState.is_destroyed(id))
	assert_true(fallen.size() >= 2, "two longhouses fell (%s)" % [fallen])
	var by_fire := {}
	for h: Array in _engine_hits:
		by_fire[str(h[0])] = true
	for id: String in fallen:
		assert_true(by_fire.has(id), "%s was struck by the engines' fire" % id)
	var ended_tick := int(siege.log[siege.log.size() - 1].tick) if not siege.log.is_empty() else Sim.tick
	print("    test_stonehold_walkthrough: Skarn burned by the siege line's fire in %.0f s of play (%d hits on its halls)" % [
		float(ended_tick - started) / float(Sim.TICK_RATE), _engine_hits.size()])
	await _settle()
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.ABANDONED, "the siege's quest is lost")
	assert_eq(Quests.quest_state("quest.skarn_rebuild"), Quests.ACTIVE, "the rebuilding errand begins")


# --------------------------------------------------------------------------- Skarn burned and rebuilt

func test_skarn_burned_then_rebuilt_at_stage_6() -> void:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	var part := _part(SKARN_PART)
	var lh := _find(part, LONGHOUSES[0]) as Node3D
	assert_true(lh != null, "Skarn's longhouses are in its chunk")
	if lh == null:
		return
	add_box(Vector3(200, 1, 200), lh.global_position + Vector3(0, -0.5, 30))
	var p := spawn_player(lh.global_position + Vector3(0, 0.1, 30), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = lh.global_position + Vector3(0, 0.1, 30)
	p.set_profile(_profile(6))
	WorldState.set_flag("world.skarn.plea_accepted", true)
	await _settle()
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.ACTIVE, "the plea starts the siege's quest")
	for id: String in LONGHOUSES.slice(0, 2):
		assert_true(await _break(id, "world.stonehold.siege_crew_1"), "%s burns" % id)
	# the siege's fail outcome, as WorldEvent writes it
	for f: Array in [["%s.done" % SIEGE, true], ["%s.outcome" % SIEGE, "burned"], ["world.skarn.burned", true]]:
		WorldState.set_flag(str(f[0]), f[1])
	await _settle()
	assert_eq(Quests.quest_state("quest.siege_of_skarn"), Quests.ABANDONED, "Skarn burned: the siege's quest is lost")
	assert_eq(Quests.quest_state("quest.skarn_rebuild"), Quests.ACTIVE, "the rebuilding errand begins")
	var forge := _find(part, "world.stonehold.skarn_forge") as ConditionForge
	assert_true(forge != null and not forge.is_open(), "Skarn's hearth is cold")
	var raised := 0
	for rp in part.find_children("*", "", true, false):
		if rp is RebuildPoint:
			var point := rp as RebuildPoint
			if point.is_needed():
				point.rebuild()
				raised += 1
	assert_eq(raised, 2, "the beams of the two burned halls are lifted back")
	await _settle()
	assert_eq(Quests.quest_state("quest.skarn_rebuild"), Quests.COMPLETED, "Skarn is rebuilt")
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.skarn.support")), "Skarn stands with the giant again")
	assert_true(forge.is_open(), "its hearth-forge opens")


# --------------------------------------------------------------------------- the battery's engines

func test_the_moot_batterys_engines_are_seized_and_thrown_at_stage_6() -> void:
	var part := _part(BATTERY_PART)
	await step_ticks(2)
	var eng := _find(part, "world.stonehold.battery_ballista_1") as SiegeEngine
	assert_true(eng != null, "the battery's ballista is in its chunk")
	if eng == null:
		return
	var at := eng.global_position
	add_box(Vector3(80, 1, 80), at + Vector3(0, -0.5, 0))
	var p := spawn_player(at + Vector3(7.5, 0.1, 0), 90.0)
	p.set_profile(_profile(5))
	await step_ticks(2)
	assert_eq(p.grab.check_target(eng.entity), "engine_stage", "a stage-5 giant cannot seize it")
	p.set_profile(_profile(6))
	await step_ticks(2)
	assert_eq(p.grab.check_target(eng.entity), "", "a stage-6 giant seizes an uncrewed engine")
	var grabbed: bool = false
	for i in 30:
		if p.grab.try_grab() == CombatController.Verdict.ACCEPT:
			grabbed = true
			break
		await step_ticks(2)
	assert_true(grabbed, "the grab is accepted")
	var held: bool = await TestWait.until(self, func() -> bool: return p.grab.is_holding(), 60)
	assert_true(held, "the engine is held")
	if not held:
		return
	await TestWait.until(self, func() -> bool:
		return p.controller.state == CombatController.State.LOCOMOTION and p.controller.action == null, 60)
	p.router.inject_light_attack()
	var smashed: bool = await TestWait.until(self, func() -> bool: return eng.destroyed, 240)
	assert_true(smashed, "thrown, it smashes")


# --------------------------------------------------------------------------- the Stair, the Moot, the champion

func _moot(stage := 6) -> Array:
	GameSession.start_world_for_tests(START_CP)
	GameSession.level_id = "level.world"
	Quests.test_active = true
	Quests.scope = PackedStringArray()
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	GameSession.on_level_ready(world, p)
	p.global_position = Vector3(0, 0.05, 0)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	p.set_profile(_profile(stage))
	for f: String in ["world.kingsgate.lit", "oath.march.done", "oath.crown.done"]:
		WorldState.set_flag(f, true)
	await _settle()
	var part := Node3D.new()
	world.add_child(part)
	for path: String in MOOT_PARTS:
		part.add_child((load(path) as PackedScene).instantiate())
	await step_ticks(2)
	var arena: MootArena = null
	for n in part.find_children("*", "", true, false):
		if n is MootArena:
			arena = n
	return [p, part, arena]


func test_the_stair_and_the_moot_admit_only_stage_6_and_the_moot_is_entered() -> void:
	var stair := _part(STAIR_PART)
	var moot_gate := _part(BATTERY_PART)
	await step_ticks(2)
	var gates := {}
	for part: Node in [stair, moot_gate]:
		for n in part.find_children("*", "", true, false):
			if n is SizeGate:
				gates[(n as SizeGate).gate_id] = n
	for id: String in ["world.gate.giants_stair", "world.gate.moot"]:
		var g := gates.get(id) as SizeGate
		assert_true(g != null, "%s is in its chunk" % id)
		if g != null:
			assert_false(g.passes(5), "%s refuses a stage-5 giant" % id)
			assert_true(g.passes(6), "%s admits a stage-6 giant" % id)
			# M8 gate (F29): the refusal names the stage it needs (decision 18), the Stair the way round.
			assert_true(g.message_text().contains("Grow to stage 6"), "%s says to grow to stage 6 (%s)" % [id, g.message_text()])
	var stair_gate := gates.get("world.gate.giants_stair") as SizeGate
	assert_true(stair_gate != null and stair_gate.message_text().contains("the Ironway"), "the Stair names the Ironway")
	assert_eq(int(GameData.get_record("poi.stair_top").get("reveals_m", 0)), 600, "the Stair's head reveals 600 m")
	var r: Array = await _moot()
	var p: GiantPlayer = r[0]
	assert_eq(Quests.stage_of(MAIN), "moot", "a stage-6 giant with two oaths: the Moot is next")
	Events.area_entered.emit(Sim.tick, "world.area.moot", p.entity.entity_id)
	await _settle()
	assert_eq(Quests.stage_of(MAIN), "champion", "entering the Moot completes its stage")


func _claim(part: Node) -> void:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	Events.area_entered.emit(Sim.tick, "world.area.moot", p.entity.entity_id if p != null else "player")
	await _settle()
	var throne := _find(part, "world.stonehold.stone_throne") as StoneThrone
	assert_true(throne != null and throne.can_interact(null), "the champion settled, the throne can be taken")
	if throne != null:
		assert_true(throne.claim(), "the giant takes the Stone Throne")
	await _settle()
	assert_eq(Quests.quest_state(MAIN), Quests.COMPLETED, "the main thread completes")


func test_the_champion_spared() -> void:
	var r: Array = await _moot()
	var arena: MootArena = r[2]
	assert_true(arena != null, "the Moot's arena")
	var throne := _find(r[1], "world.stonehold.stone_throne") as StoneThrone
	assert_false(throne.can_interact(null), "the throne waits for the champion")
	WorldState.set_flag("boss.harrok.outcome", "spared")
	arena.p34_on_yield_decided(HARROK, "spare")
	await _settle()
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.harrok_clan.reconciled")), "his clan reconciled")
	assert_false(QuestConditions.truthy(WorldState.get_flag("world.moot.empty")), "the clans watch the crowning")
	await _claim(r[1])


func test_the_champion_slain() -> void:
	var r: Array = await _moot()
	var arena: MootArena = r[2]
	WorldState.set_flag("boss.harrok.outcome", "slain")
	arena._on_entity_died(Sim.tick, HARROK, "player")
	await _settle()
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.moot.empty")), "the Moot empties")
	assert_false(QuestConditions.truthy(WorldState.get_flag("faction.harrok_clan.reconciled")), "his clan stays hostile")
	var entry := (GameData.get_record("wander.stonehold").entries as Array).filter(func(e: Dictionary) -> bool: return str(e.id) == "clan_giants")
	var c := QuestConditions.empty_context()
	c.flags = WorldState.flags
	assert_true(QuestConditions.all_hold(entry[0].conditions, c), "his clan's giants roam the highlands")
	await _claim(r[1])


func test_the_champion_kneels_to_the_talk() -> void:
	var r: Array = await _moot()
	var arena: MootArena = r[2]
	# all three oaths (the wood's flag stands in for P35's oath on this branch) and Skarn's support
	for f: String in ["oath.wood.done", "world.skarn.support"]:
		WorldState.set_flag(f, true)
	var s := Quests.start_dialogue("dialogue.harrok", HARROK)
	assert_eq(str(s.node().get("id", "")) if s != null else "", "talk", "Harrok hears the talk")
	if s != null:
		assert_true(s.find_choice("yielded_talk") >= 0, "the talk ending is offered")
		s.choose_outcome("yielded_talk")
	Quests.end_dialogue()
	await _settle()
	assert_eq(str(WorldState.get_flag("boss.harrok.outcome", "")), "yielded_talk", "he kneels without a fight")
	assert_eq(arena.state, BossArena.State.DEFEATED, "the ring stays quiet")
	assert_true(QuestConditions.truthy(WorldState.get_flag("faction.harrok_clan.reconciled")), "his clan reconciled")
	await _claim(r[1])


## M8 gate fix-up 1 (N4.6): the shipped Moot (c4_1) and the challenge stone (c3_1) at their chunks' places
## in the world (256 m chunks: c3_1 at (-256, -768), c4_1 at (0, -768)).
func test_answering_harroks_challenge_stone_is_no_leaving_the_moot() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(6))
	var battery := _part(BATTERY_PART)
	battery.position = Vector3(-256, 0, -768)
	var moot := _part(MOOT_PARTS[0])
	moot.position = Vector3(0, 0, -768)
	await step_ticks(2)
	var arena: MootArena = null
	for n in moot.find_children("*", "", true, false):
		if n is MootArena:
			arena = n
	var stone: NpcTalker = null
	for n in battery.find_children("*", "", true, false):
		if n is NpcTalker and (n as NpcTalker).prompt == "Answer Harrok's challenge":
			stone = n
	assert_true(arena != null and stone != null, "the Moot's arena and Harrok's challenge stone")
	if arena == null or stone == null:
		return
	assert_eq(stone.resolved_npc_id(), arena.boss_id, "the stone speaks for the arena's boss")
	var centre := arena.global_position
	var to_ring := Vector3(centre.x - stone.global_position.x, 0.0, centre.z - stone.global_position.z)
	assert_true(arena.outside_m(stone.global_position) > arena.disengage_margin_m,
		"the stone stands beyond the disengage line (%.1f m out)" % arena.outside_m(stone.global_position))
	var reach := stone.radius_m + float(p.profile.get("capsule_radius_m", 0.0))
	var nearest := stone.global_position + to_ring.normalized() * (reach - 1.0)
	assert_true(arena.outside_m(nearest) > arena.disengage_margin_m,
		"even its reach on the ring's side lies beyond the line (%.1f m out): answering it meant leaving" % arena.outside_m(nearest))
	# The giant answers from the ring's side of the stone, from its far side and beside it: all within reach.
	for d: Vector3 in [to_ring.normalized() * (reach - 1.0), -to_ring.normalized() * 2.0,
			to_ring.normalized().cross(Vector3.UP) * (reach - 1.0)]:
		p.global_position = Vector3(stone.global_position.x + d.x, 0.05, stone.global_position.z + d.z)
		assert_true(arena.at_boss_talker(p), "within the stone's reach the giant has not left the fight (%s)" % d)
	p.global_position = stone.global_position - to_ring.normalized() * (reach + 10.0)
	assert_false(arena.at_boss_talker(p), "past the stone's reach it has")

