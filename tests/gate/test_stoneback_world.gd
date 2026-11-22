extends IntegrationSuite
## A3: Stoneback in the real world (scenes/world/world.tscn, deterministic streaming): his quarry beside Millford,
## his encounter (encounter.crownmarch_stoneback) and his territory (TitanTerritory). docs/systems/A3.md.
##   * from the start of the open world he stands at home in his quarry; within his activation radius his seat in
##     the combatant budget is reserved and his AI runs at the near tier at 300 m (lod_near_m);
##   * a giant at the Woodway lookout (163 m) is unseen; at 95 m he sights it - boss_engaged, the quarry discovered
##     - and walks out after it, past any leash (the giant 150 m from home);
##   * the giant runs to Millford (290 m, beyond his 230 m line): the hunt ends (boss_disengaged "left"), he is whole
##     and walks home;
##   * the same hunt twice (two worlds in one run) is the same tick for tick: the encounter is deterministic;
##   * fast travel away unloads his chunk: he is despawned (no death recorded) and comes back at home, whole;
##   * a stage-3 giant who walks up to his quarry dies within two minutes;
##   * his death: his outcome, the defeated flag, a checkpoint, his loot, the quest's slay stage; the quarry reopens once
##     the giant has gone beyond his line (world.quarry.reopened: the works' encounter, the flag-shown cranes and
##     carts); he never returns.

const SCENE := "res://scenes/world/world.tscn"
const STONEBACK := "world.crownmarch.stoneback"
const ENCOUNTER := "encounter.crownmarch_stoneback"
const HOME := Vector2(-606.0, 456.0)
const CENTRE := Vector2(-600.0, 452.0)
const LOOKOUT := Vector2(-452.0, 520.0)
const SIGHTED_AT := Vector2(-512.0, 488.0)
const AWAY := Vector2(-475.0, 545.0)
const MILLFORD := Vector2(-380.0, 625.0)

var _engaged: Array = []
var _disengaged: Array = []
var _defeated: Array = []
var _saved: Array = []


func before_each() -> void:
	await super()
	WorldState.clear()
	_engaged.clear()
	_disengaged.clear()
	_defeated.clear()
	_saved.clear()
	Events.boss_engaged.connect(_on_engaged)
	Events.boss_disengaged.connect(_on_disengaged)
	Events.boss_defeated.connect(_on_defeated)


func after_each() -> void:
	for pair: Array in [[Events.boss_engaged, _on_engaged], [Events.boss_disengaged, _on_disengaged],
			[Events.boss_defeated, _on_defeated]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	Quests.test_active = false
	await super()


func _on_engaged(t: int, id: String) -> void:
	_engaged.append([t, id])


func _on_disengaged(t: int, id: String, reason: String) -> void:
	_disengaged.append([t, id, reason])


func _on_defeated(t: int, id: String) -> void:
	_defeated.append([t, id])


func _on_saved(_t: int, _cp: String, ok: bool, _msg: String) -> void:
	if ok:
		_saved.append(str(GameSession.checkpoint_doc.get("checkpoint", {}).get("reason", "")))


func _world(xz: Vector2, stage: int) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _place(w, xz)
	var p := w.player()
	TitanDuel.prepare(p, stage)
	await step_ticks(2)
	return w


## Moves the giant to `xz` on the ground, the ring around it loaded first (a fast travel).
func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 600:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _director(w: WorldRoot) -> EncounterDirector:
	return w.get_node_or_null("EncounterDirector") as EncounterDirector if w.has_node("EncounterDirector") \
		else w.get_tree().get_first_node_in_group(EncounterDirector.GROUP) as EncounterDirector


func _territory(w: WorldRoot) -> TitanTerritory:
	for n in w.find_children("*", "", true, false):
		if n is TitanTerritory:
			return n
	return null


func _titan(w: WorldRoot) -> TitanEnemy:
	var d := _director(w)
	return d.spawned(STONEBACK) as TitanEnemy if d != null else null


func _flat(a: Vector3, b: Vector2) -> float:
	return Vector2(a.x, a.z).distance_to(b)


## Steps up to `max_ticks` until `done` holds (true) or not (false).
func _until(done: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if bool(done.call()):
			return true
		await step_ticks(1)
	return bool(done.call())


## The hunt: the giant (invulnerable) at the lookout, then sighted, then away to Millford. Returns a log of the
## titan's place every second and the events' ticks (for the determinism check).
func _hunt(w: WorldRoot, checks: bool) -> Array:
	var p := w.player()
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var d := _director(w)
	var log: Array = []
	var ok := await _until(func() -> bool: return _titan(w) != null, 600)
	if checks:
		assert_true(ok, "he stands in his quarry from the start (the encounter active at the lookout)")
	# (the same start each run: a whole second, the Sim reseeded, and he comes back at home on this tick - his
	# brain's clocks begin here, whatever the streaming took before)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	d.despawn(STONEBACK)
	d.force_activate(ENCOUNTER)
	d.update_now()
	await _until(func() -> bool: return _titan(w) != null, 120)
	var t0 := Sim.tick
	var t := _titan(w)
	if t == null:
		return log
	var terr := _territory(w)
	if checks:
		assert_true(terr != null, "his territory is in the world (the quarry chunk's props)")
		assert_true(_flat(t.global_position, HOME) < 6.0, "at home (%.1f m away)" % _flat(t.global_position, HOME))
		assert_true(d.a3_seat_reserved(ENCOUNTER), "his seat in the combatant budget is reserved")
	await step_ticks(EncounterDirector.DEFAULT_CHECK_TICKS + 1)
	if checks:
		assert_eq(int(t.get("lod_tier")), 0, "his AI at the near tier with the giant %.0f m away" % _flat(p.global_position, HOME))
	await step_ticks(120)
	if checks:
		assert_eq(terr.state_name(), "waiting", "the giant at the lookout (%.0f m) is unseen" % _flat(p.global_position, CENTRE))
		assert_true(_engaged.is_empty(), "no engagement yet")
	await _place(w, SIGHTED_AT)
	ok = await _until(func() -> bool: return terr.is_engaged(), 120)
	log.append(["engaged", Sim.tick - t0])
	if checks:
		assert_true(ok, "sighted at %.0f m: engaged" % _flat(p.global_position, CENTRE))
		assert_eq(_engaged.size(), 1, "boss_engaged once")
		assert_true(Waystone.flag_truthy(WorldState.get_flag(Discovery.discovered_flag("poi.stoneback_quarry"))),
			"Stoneback's Quarry discovered as he sights the giant")
	# he walks out after it; the giant waits beyond his home by 150 m and more
	await _place(w, AWAY)
	var farthest := 0.0
	for s in 30:
		await step_ticks(60)
		var at := t.global_position
		farthest = maxf(farthest, _flat(at, HOME))
		log.append([snappedf(at.x, 0.01), snappedf(at.z, 0.01), int(t.entity.combatant.pools.health)])
	if checks:
		assert_true(farthest > 70.0, "he walked out after the giant, %.0f m from home (an ordinary leash is 70 m)" % farthest)
		assert_true(terr.is_engaged(), "still hunting at %.0f m from home" % _flat(t.global_position, HOME))
	# the giant escapes to Millford, beyond his line
	await _place(w, MILLFORD)
	ok = await _until(func() -> bool: return not _disengaged.is_empty(), 60 * 12)
	log.append(["disengaged", _disengaged.size(), int(_disengaged.back()[0]) - t0 if ok else -1])
	if checks:
		assert_true(ok, "the giant at Millford (%.0f m) ends the hunt" % _flat(p.global_position, CENTRE))
		assert_eq(str(_disengaged.back()[2]) if ok else "", "left", "boss_disengaged left")
		assert_eq(t.entity.combatant.pools.health, t.entity.combatant.pools.health_max, "whole again")
	ok = await _until(func() -> bool: return _flat(t.global_position, HOME) < 12.0, 60 * 120)
	log.append([snappedf(t.global_position.x, 0.01), snappedf(t.global_position.z, 0.01)])
	if checks:
		assert_true(ok, "he walks home (%.0f m from it)" % _flat(t.global_position, HOME))
		assert_eq(terr.state_name(), "waiting", "his territory waits again")
	return log


func test_he_sights_hunts_and_goes_home_and_the_hunt_repeats() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(LOOKOUT, 5)
	var first := await _hunt(w, true)
	w.queue_free()
	await step_ticks(2)
	WorldState.clear()
	_engaged.clear()
	_disengaged.clear()
	var w2: WorldRoot = await _world(LOOKOUT, 5)
	var second := await _hunt(w2, false)
	assert_true(first.size() > 30, "the hunt logged (%d entries)" % first.size())
	assert_eq(second, first, "the same hunt again: the same places on the same ticks")
	w2.queue_free()
	await step_ticks(2)


func test_fast_travel_away_despawns_him_whole() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(LOOKOUT, 6)
	var d := _director(w)
	assert_true(await _until(func() -> bool: return _titan(w) != null, 600), "he is in the world")
	await _place(w, Vector2(300.0, 600.0))
	var gone := await _until(func() -> bool: return _titan(w) == null, 600)
	assert_true(gone, "his chunk unloaded: he is despawned")
	assert_false(WorldState.is_killed(STONEBACK), "no death recorded")
	assert_false(d.a3_seat_reserved(ENCOUNTER), "his seat released beyond his radius")
	await _place(w, LOOKOUT)
	assert_true(await _until(func() -> bool: return _titan(w) != null, 600), "back on the next activation")
	var t := _titan(w)
	assert_true(_flat(t.global_position, HOME) < 6.0, "at home")
	assert_eq(t.plates().broken_count(), 0, "every plate whole")
	assert_true(d.a3_seat_reserved(ENCOUNTER), "his seat reserved again")
	w.queue_free()
	await step_ticks(2)


func test_a_stage_3_giant_dies_quickly() -> void:
	WanderDirector.test_active = false
	var w: WorldRoot = await _world(LOOKOUT, 3)
	var p := w.player()
	assert_true(await _until(func() -> bool: return _titan(w) != null, 600), "he is in the world")
	await _place(w, Vector2(-540.0, 480.0))
	var terr := _territory(w)
	assert_true(await _until(func() -> bool: return terr.is_engaged(), 120), "he sights the giant in his quarry's mouth")
	var t0 := Sim.tick
	hits.clear()
	var dead := await _until(func() -> bool: return not p.entity.is_alive(), 60 * 90)
	var blows: Array = []
	for r in hits:
		if r.event.target_id == p.entity.entity_id and r.health_damage > 0:
			blows.append("%s %d" % [r.event.action_id.trim_prefix("ability.stoneback_"), r.health_damage])
	print("    stoneback_world: a stage-3 giant (%d health) standing in his quarry's mouth, 64 m from its centre: dead %.1f s after he sighted it, by %s" % [
		int(p.entity.combatant.pools.health_max), (Sim.tick - t0) / 60.0, blows])
	assert_true(dead, "a stage-3 giant in his quarry dies within 90 s of his sighting it")
	assert_true(blows.size() <= 4, "in a few of his blows (%d)" % blows.size())
	w.queue_free()
	await step_ticks(2)


func test_his_death_reopens_the_quarry_and_he_stays_dead() -> void:
	WanderDirector.test_active = false
	Quests.test_active = true
	GameSession.start_world_for_tests("world.cp.millford")
	GameSession.level_id = "level.world"
	var w: WorldRoot = await _world(LOOKOUT, 6)
	var p := w.player()
	GameSession.on_level_ready(w, p)
	Events.checkpoint_saved.connect(_on_saved)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	assert_true(await _until(func() -> bool: return _titan(w) != null, 600), "he is in the world")
	await _place(w, SIGHTED_AT)
	var terr := _territory(w)
	assert_true(await _until(func() -> bool: return terr.is_engaged(), 120), "engaged")
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	assert_eq(Quests.quest_state("quest.stoneback"), Quests.ACTIVE,
		"the quest begins as he sights the giant (the quarry discovered)")
	var t := _titan(w)
	t.entity.combatant.pools.health = 10.0
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = p.entity.entity_id
	e.target_id = STONEBACK
	e.power = 5000.0
	e.size_policy = "none"
	e.tags = PackedStringArray(["Melee"])
	e.region = "torso"
	e.attacker_position = p.global_position
	Sim.queue_hit(e)
	assert_true(await _until(func() -> bool: return not _defeated.is_empty(), 300), "boss_defeated")
	assert_eq(str(WorldState.get_flag("boss.stoneback.outcome")), "slain", "his outcome: slain")
	assert_true(Waystone.flag_truthy(WorldState.get_flag("boss.stoneback.defeated")), "the defeated flag")
	assert_true(WorldState.is_killed(STONEBACK), "his death persists")
	assert_eq(terr.state_name(), "defeated", "his territory is done")
	await step_ticks(120)
	# (the kill's request, boss_defeated, may be replaced by the quest's stage moving on the same evaluation: one
	# pending request keeps the newest reason - GameSession; either way the kill is in the checkpoint)
	assert_true(_saved.has("boss_defeated") or _saved.has("quest_stage"), "a checkpoint after the kill (%s)" % [_saved])
	assert_eq(str(GameSession.checkpoint_doc.get("world", {}).get("flags", {}).get("boss.stoneback.outcome", "")), "slain",
		"the checkpoint holds his death")
	Events.checkpoint_saved.disconnect(_on_saved)
	await step_ticks(Quests.EVALUATE_EVERY_TICKS * 2 + 1)
	for item: String in ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron"]:
		assert_true(loot.any(func(l: String) -> bool: return l.ends_with(":" + item)), "his loot: %s (%s)" % [item, loot])
	assert_eq(Quests.stage_of("quest.stoneback"), "thanks", "the quest's slay stage done: Millford's thanks next")
	var d := _director(w)
	assert_false(Waystone.flag_truthy(WorldState.get_flag("world.quarry.reopened")), "not reopened at his corpse")
	await _place(w, MILLFORD)
	await step_ticks(5)
	assert_true(Waystone.flag_truthy(WorldState.get_flag("world.quarry.reopened")),
		"the giant gone on beyond his line: the quarry reopens behind its back")
	await _place(w, Vector2(-560.0, 480.0))
	await step_ticks(EncounterDirector.DEFAULT_CHECK_TICKS * 3)
	assert_eq(d.encounter_state("encounter.crownmarch_quarry_works"), "active", "the quarry works open")
	assert_true(d.spawned("world.crownmarch.quarryman_bram_works") != null, "Old Bram runs the quarry")
	var shown := 0
	for n in w.find_children("*", "", true, false):
		if n.has_method("refresh") and str(n.name).begins_with("world_crownmarch_quarry_crane") and (n as Node3D).visible:
			shown += 1
	assert_true(shown >= 2, "the working cranes shown (%d), the broken ones hidden" % shown)
	assert_false(d.a3_seat_reserved(ENCOUNTER), "his seat released")
	w.queue_free()
	await step_ticks(2)
	var w2: WorldRoot = await _world(SIGHTED_AT, 6)
	await step_ticks(EncounterDirector.DEFAULT_CHECK_TICKS * 4)
	assert_true(_titan(w2) == null, "slain, he never comes back")
	w2.queue_free()
	await step_ticks(2)

