extends IntegrationSuite
## P37's gate (plan M6-M9 §3.21, §5.10, decision 27): the Millford raid on the real world
## (scenes/world/world.tscn, deterministic streaming, the living world switched on as in the campaign):
##   * a stage-3 giant (the first stage the raid comes at: right after the beacon) 117 m from Millford's
##     centre (the hamlet's actors at full AI rate: the AI LOD would put those beyond 90 m to sleep) with
##     the Kingsgate beacon lit: the raid's rules hold (stage 3-5, its centre chunk loaded and ready,
##     within 200 m) and it starts - its notice on the HUD, its protect objective tracked ("Defend
##     Millford: 5 of 5 houses stand", then 4 of 5 ...), its raiders in the world;
##   * Millford's villagers run for shelter: every one of the six reaches one of the hamlet's safe
##     markers, on loaded ground, while no tick spends more than the world's path-query budget (8; the
##     FOLLOWUPS row's re-measure, printed with the folk's own peak and the time the last one took);
##   * the raiders strike the protected houses (their target provider) and, the giant standing by, three
##     of the five fall: the raid ends "fell" - event.millford_raid.done and .outcome, world.millford.burned,
##     at least two houses burned - its objective leaves the tracker, and the raiders who are left rout.
## (A stage-4 giant scares raiders off as they turn from a house they burned: P30's provider falls back
## to the giant, and an aware soldier outmatched by a stage-4 giant routs - docs/systems/P37.md.)

const SCENE := "res://scenes/world/world.tscn"
const RAID := "event.millford_raid"
## On the meadow north-east of the green: 117 m from Millford's centre (its folk are in the world, 120 m),
## 64 m from where the raiders come in (beyond their 25 m sight and 20 m aggro).
const GIANT_AT := Vector2(-280.0, 700.0)
const FOLK := ["world.crownmarch.millford_folk_1", "world.crownmarch.millford_folk_2", "world.crownmarch.millford_folk_3",
	"world.crownmarch.millford_folk_4", "world.crownmarch.millford_folk_5", "world.crownmarch.millford_folk_6"]
## The raid's cap (sim time): its houses must have fallen by then.
const RAID_TICKS := 60 * 240

var _tick_queries: Array[int] = []
var _budget_level: Node = null


func after_each() -> void:
	Sim.remove_hooks(self)
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	await super()


func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
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
	return w


func _tick_end(_t: int) -> void:
	_tick_queries.append(NavQuery.used_this_tick(_budget_level))


func test_the_millford_raid_on_the_real_world() -> void:
	WanderDirector.test_active = true
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	var w: WorldRoot = await _world(GIANT_AT)
	var p := w.player()
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 3:
			p.set_profile(rec)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var wd := w.get_node_or_null("WanderDirector") as WanderDirector
	assert_true(wd != null, "level.world makes its WanderDirector")
	if wd == null:
		return
	var d := w.director()
	# The AI LOD sends actors beyond 90 m of the giant to sleep (P10a): a raid goes on where the giant is.
	# Here the giant watches from the meadow, out of the raiders' way, and the whole hamlet runs at full rate.
	d.near_m = 130.0
	d.mid_m = 220.0
	var folk: Array[Civilian] = []
	for i in 40:
		await step_ticks(15)
		folk.clear()
		for id: String in FOLK:
			var c := d.spawned(id) as Civilian
			if c != null:
				folk.append(c)
		if folk.size() == FOLK.size():
			break
	assert_eq(folk.size(), FOLK.size(), "Millford's six villagers are in the world")
	var raid: WorldEvent = wd.events.get(RAID)
	assert_true(raid != null, "the raid is one of the world's events")
	if raid == null or folk.size() != FOLK.size():
		return
	assert_eq(raid.can_start_with(wd.event_context(raid)), "flags", "not before the Kingsgate beacon burns")
	WorldState.set_flag("world.kingsgate.lit", true)
	assert_eq(raid.can_start_with(wd.event_context(raid)), "", "then its rules hold (stage 4, Millford loaded, 117 m away)")
	var cap := int(NavQuery.settings(w).get("queries_per_tick", 0))
	_budget_level = w
	_tick_queries.clear()
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _tick_end, 1 << 20)
	var hud: Array = []
	var on_hud := func(text: String, _kind: String) -> void: hud.append(text)
	Events.hud_message.connect(on_hud)
	var q0 := NavQuery.queries_total
	var t0 := Sim.tick
	wd.check_events(Sim.tick)
	assert_eq(wd.running_event(), raid, "the raid starts")
	assert_true(hud.has(str(raid.record.start_text)), "its notice on the HUD")
	assert_eq(Quests.tracked_quest_id, RAID, "its objective tracked: compass, map and marker lead there")
	assert_eq(str(Quests.objective_for(RAID).get("text", "")), "Defend Millford: 5 of 5 houses stand", "the tracker's line")
	var houses := raid.targets()
	var raiders := {}
	var sheltered_at := {}
	var struck := {}
	var fallen_at := {}
	var line_after_first := ""
	while Sim.tick - t0 < RAID_TICKS and raid.is_running():
		await step_ticks(30)
		for id in raid.copies:
			for n: Node3D in d.p37_living(id):
				raiders[(n as EnemyActor).entity.entity_id] = true
		for c in folk:
			if is_instance_valid(c) and c.sheltered and not sheltered_at.has(c.entity_id):
				sheltered_at[c.entity_id] = float(Sim.tick - t0) / Sim.TICK_RATE
		for h in houses:
			if WorldState.is_destroyed(h) and not fallen_at.has(h):
				fallen_at[h] = float(Sim.tick - t0) / Sim.TICK_RATE
		if fallen_at.size() == 1 and line_after_first == "" and raid.is_running():
			line_after_first = str(Quests.objective_for(RAID).get("text", ""))
	Events.hud_message.disconnect(on_hud)
	Sim.remove_hooks(self)
	for r in hits:
		if raiders.has(r.event.attacker_id) and houses.has(r.event.target_id):
			struck[r.event.target_id] = int(struck.get(r.event.target_id, 0)) + 1
	var worst := 0
	var over := 0
	for q in _tick_queries:
		worst = maxi(worst, q)
		if q > cap:
			over += 1
	var last := 0.0
	var peak := 0
	var lines := PackedStringArray()
	for c in folk:
		if not is_instance_valid(c):
			continue
		peak = maxi(peak, c.search_queries_peak)
		last = maxf(last, float(sheltered_at.get(c.entity_id, 0.0)))
		lines.append("%s %s%s" % [c.entity_id.get_slice(".", 2), c.brain.state_name(),
			" %.1f s" % float(sheltered_at[c.entity_id]) if sheltered_at.has(c.entity_id) else ""])
	print("    Millford raid: %.0f s of play, %d raiders, houses struck %s, fallen %s; %d ticks, at most %d path queries a tick (%d over %d), %d in all; a villager's searches at most %d a tick; the last villager in shelter after %.1f s; %s" % [
		float(Sim.tick - t0) / Sim.TICK_RATE, raiders.size(), struck, fallen_at, _tick_queries.size(), worst, over, cap,
		NavQuery.queries_total - q0, peak, last, ", ".join(lines)])
	assert_eq(raiders.size(), 7, "six raiders and an archer came")
	for c in folk:
		if not is_instance_valid(c):
			fail("a villager left the world")
			continue
		assert_true(c.sheltered, "%s reached a safe point (%s)" % [c.entity_id, c.brain.state_name()])
		var marker := str(c.safe_marker.get("marker_id")) if c.safe_marker != null else ""
		assert_true(marker.begins_with("world.marker.millford_"), "%s ran to one of Millford's shelters (%s)" % [c.entity_id, marker])
		if c.safe_marker != null:
			assert_true(w.streamer.is_ready(w.chunk_at(c.safe_marker.global_position)), "%s's shelter is on loaded ground" % c.entity_id)
	assert_true(worst <= cap, "no tick spends more than the world's %d path queries (at most %d, %d ticks over)" % [cap, worst, over])
	assert_true(struck.size() >= 1, "the raiders struck the protected houses (%s)" % struck)
	assert_false(raid.is_running(), "the raid ended")
	assert_true(fallen_at.size() >= 3, "three of the five houses fell (%s)" % fallen_at)
	assert_eq(WorldState.get_flag("event.millford_raid.done"), true, "event.millford_raid.done")
	assert_eq(WorldState.get_flag("event.millford_raid.outcome"), "fell", "its outcome: fell")
	assert_eq(WorldState.get_flag("world.millford.burned"), true, "world.millford.burned")
	var burned := 0
	for h in houses:
		if WorldState.is_destroyed(h):
			burned += 1
	assert_true(burned >= 2, "at least two houses stay burned (%d)" % burned)
	assert_eq(line_after_first, "Defend Millford: 4 of 5 houses stand", "the tracker counts what stands")
	assert_false(Quests.active_quest_ids().has(RAID), "its objective left the tracker")
	await step_ticks(12)
	var routed := 0
	for id: String in raiders:
		var n := d.spawned(id) as EnemyActor
		if n != null and n.entity.is_alive():
			assert_eq(n.brain.state_name(), "Routed", "%s routs: the raid is over" % id)
			routed += 1
	print("    the raiders left standing rout: %d" % routed)
	assert_true(hud.has("Millford fell to the raiders: its houses burn."), "its ending on the HUD")
