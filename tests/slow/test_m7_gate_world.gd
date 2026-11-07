extends IntegrationSuite
## M7 gate review fixes on the real world (scenes/world/world.tscn, deterministic streaming; plan
## M6-M9 §0.2's M7 row: "two formation fights that threaten a stage-4 giant"):
##   * a defied toll fort brings its pikes down the road to a stage-4 giant standing 16 m before their
##     home rank (8 m before the rank once it has advanced) and damages it with the brace: no pike or
##     banner is leashed (the encounter's leash holds the formation's reach, and an intact formation's
##     members are left to their formation) and the advance ends inside the brace distance (it used to
##     stop half a metre outside it and stand "formed");
##   * the Raiders' Hollow's shield wall does the same to a stage-4 giant 16 m before its front rank;
##   * the path-query budget (plan §2.8, §5.2: nav_query.queries_per_tick 8): the Hollow's archers and
##     mage, kept aware of a stage-4 giant standing 170-220 m away, never take a tick over the level's
##     budget nor more than one search candidate's share (3 queries) each, and their ticks stay short
##     (each spent 32-34 queries in one tick, 17-27 ms, every 1-3 s: the target was out of reach and every
##     candidate of the front-arc and ring searches was tried, then tried again at the next decision);
##     and a firing-point search with nothing to find spreads its candidates over ticks, one a tick,
##     waits while the level's budget is spent, and ends - through a ranged unit's own chain too (the
##     front arc, then the ring), and a routed member's flight resumes after its rout point failed.

const SCENE := "res://scenes/world/world.tscn"
const FORT := "encounter.crownmarch_toll_fort"
const RAIDERS := "encounter.crownmarch_raiders"
## How long a fight may take to draw blood (the pikes walk ~9 m at 1.4 m/s, then a 0.8 s windup).
const FIGHT_TICKS := 60 * 30
## The Raiders' Hollow's ranged members.
const RANGED := ["world.crownmarch.raider_archer_1", "world.crownmarch.raider_archer_2", "world.crownmarch.raider_mage"]
## A spot on open ground 170-220 m from them (and outside Brannock's activation radius).
const FAR_SPOT := Vector2(70.0, 600.0)

var _leashed: Array[String] = []


func before_each() -> void:
	await super()
	_leashed.clear()
	Events.encounter_leashed.connect(_on_leashed)


func after_each() -> void:
	if Events.encounter_leashed.is_connected(_on_leashed):
		Events.encounter_leashed.disconnect(_on_leashed)
	for f in Formation.live():
		f.dissolve()
	await super()


func _on_leashed(_t: int, _enc: String, id: String) -> void:
	_leashed.append(id)


## The real world with the giant held still above (x, z) until the ring around it has streamed in.
func _world(xz: Vector2) -> WorldRoot:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	w.player().router.use_injection = true
	await _go(w, xz)
	return w


## Puts the giant on the ground at (x, z) once the ring around it is ready.
func _go(w: WorldRoot, xz: Vector2) -> void:
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


## A stage-4 giant (its profile set directly: the growth path is P05's and P26's).
func _stage_4(p: GiantPlayer) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	assert_eq(int(p.current_growth_stage()), 4, "a stage-4 giant")


## Waits until `enc`'s formation `local` has drawn blood from the giant (or FIGHT_TICKS passed);
## returns [the formation, the damage its members dealt, their hits].
func _fight(w: WorldRoot, enc: String, local: String) -> Array:
	var d := w.director()
	var p := w.player()
	var fid := Formation.formation_id(enc, local)
	var damage := 0.0
	var landed := 0
	var f: Formation = null
	for i in FIGHT_TICKS / 30:
		await step_ticks(30)
		f = d.formation(fid)
		if f == null:
			continue
		var ids := {}
		for m in f.all_members():
			ids[m.entity_id] = true
		damage = 0.0
		landed = 0
		for r in hits_on(p.entity.entity_id):
			if ids.has(r.event.attacker_id) and r.health_damage > 0.0:
				damage += r.health_damage
				landed += 1
		if landed >= 2:
			break
	return [f, damage, landed]


func _members_leashed(f: Formation) -> Array:
	var out: Array = []
	for m in f.all_members():
		if m.leash_count > 0 or _leashed.has(m.entity_id):
			out.append(m.entity_id)
	return out


func test_a_defied_toll_fort_brings_its_pikes_to_a_stage_4_giant_on_the_road() -> void:
	var w: WorldRoot = await _world(Vector2(460.0, 560.0))
	var p := w.player()
	_stage_4(p)
	WorldState.set_flag("world.toll_fort.defied", true)   # "I pay no toll.": the stand-down ends
	var home_front := 366.1
	await _go(w, Vector2(460.0, home_front + 16.0))
	var hp0 := p.entity.combatant.pools.health
	var out: Array = await _fight(w, FORT, "pikes")
	var f: Formation = out[0]
	assert_true(f != null, "the pikes formed for the stage-4 giant")
	if f == null:
		return
	print("    toll fort: %d brace(s), %d hit(s) for %.0f damage; the giant %.0f -> %.0f; the rank %.1f m from it" % [
		f.brace_count, out[2], out[1], hp0, p.entity.combatant.pools.health, f.front_gap(p.global_position)])
	assert_eq(_members_leashed(f), [], "no pike or banner was leashed")
	assert_true(f.brace_count >= 1, "the pikes braced (%d)" % f.brace_count)
	assert_true(int(out[2]) >= 1 and float(out[1]) > 0.0, "their brace damaged the giant (%d hits, %.0f)" % [out[2], out[1]])
	assert_true(p.entity.combatant.pools.health < hp0, "the giant lost health")
	assert_true(f.front_gap(p.global_position) <= f.brace_m + 0.05, "the rank advanced inside its brace distance")
	var enc := GameData.get_record(FORT)
	for rec: Dictionary in enc.formations:
		assert_true(FormationRules.reach_m(enc, rec) <= float(enc.leash_radius_m), "the leash holds the pikes' reach")


func test_the_raiders_shield_wall_closes_on_a_stage_4_giant_and_braces() -> void:
	var w: WorldRoot = await _world(Vector2(60.0, 640.0))
	var p := w.player()
	_stage_4(p)
	await _go(w, Vector2(-84.9 + 16.0, 568.0))   # 16 m before the wall's front rank, facing east
	var hp0 := p.entity.combatant.pools.health
	var out: Array = await _fight(w, RAIDERS, "shields")
	var f: Formation = out[0]
	assert_true(f != null, "the shield wall formed for the stage-4 giant")
	if f == null:
		return
	print("    raiders: %d brace(s), %d hit(s) for %.0f damage; the giant %.0f -> %.0f" % [
		f.brace_count, out[2], out[1], hp0, p.entity.combatant.pools.health])
	assert_eq(_members_leashed(f), [], "no shieldman or banner was leashed")
	assert_true(f.brace_count >= 1, "the wall braced (%d)" % f.brace_count)
	assert_true(int(out[2]) >= 1 and float(out[1]) > 0.0, "its brace damaged the giant (%d hits, %.0f)" % [out[2], out[1]])


# --------------------------------------------------------------------------- the path-query budget

var _tick_queries: Array[int] = []
var _phase_us: Array[int] = []
var _phase_t0 := 0
var _budget_level: Node = null


func _phase_begin(_t: int) -> void:
	_phase_t0 = Time.get_ticks_usec()


func _phase_end(_t: int) -> void:
	_phase_us.append(Time.get_ticks_usec() - _phase_t0)


func _tick_end(_t: int) -> void:
	_tick_queries.append(NavQuery.used_this_tick(_budget_level))


## The Raiders' Hollow's ranged members, once spawned (empty until then).
func _ranged(d: EncounterDirector) -> Array[EnemyActor]:
	var out: Array[EnemyActor] = []
	for id: String in RANGED:
		var n := d.spawned(id) as EnemyActor
		if n != null and n.entity.is_alive():
			out.append(n)
	return out


func test_the_hollows_archers_and_mage_keep_the_path_query_budget_with_the_giant_200_m_away() -> void:
	var w: WorldRoot = await _world(Vector2(-110.0, 520.0))   # the camp's south side
	var p := w.player()
	_stage_4(p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var d := w.director()
	for i in 40:
		await step_ticks(30)
		if _ranged(d).size() == RANGED.size() and _ranged(d).all(func(n: EnemyActor) -> bool: return n.brain.aware):
			break
	assert_eq(_ranged(d).size(), RANGED.size(), "the Hollow's two archers and its mage are in the world")
	await _go(w, FAR_SPOT)
	var cap := int(NavQuery.settings(w).get("queries_per_tick", 0))
	assert_eq(cap, 8, "the world's budget is 8 path queries a tick")
	_budget_level = w
	_tick_queries.clear()
	_phase_us.clear()
	for n in _ranged(d):
		n.search_queries_peak = 0
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _phase_begin, 1 << 20)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, _phase_end, -(1 << 20))
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _tick_end, 1 << 20)
	var aware_samples := 0
	var samples := 0
	for i in 20:
		# kept aware of the far giant (as the alert group and its footsteps kept them on the walk)
		for n in _ranged(d):
			if not n.is_returning():
				n.brain.on_noise(Sim.tick, p.global_position, p.entity.entity_id, true)
		for k in 6:
			await step_ticks(10)
			for n in _ranged(d):
				samples += 1
				if n.brain.aware:
					aware_samples += 1
	Sim.remove_hooks(self)
	var worst := 0
	for q in _tick_queries:
		worst = maxi(worst, q)
	var slow := 0
	var phase_max := 0
	for us in _phase_us:
		phase_max = maxi(phase_max, us)
		if us > 10000:
			slow += 1
	var lines := PackedStringArray()
	var far_m := INF
	for n in _ranged(d):
		far_m = minf(far_m, Vector2(n.global_position.x - p.global_position.x, n.global_position.z - p.global_position.z).length())
		lines.append("%s %s, search peak %d" % [n.entity_id.get_slice(".", 2), n.brain.state_name(), n.search_queries_peak])
	print("    the giant %.0f m and more from them; %d ticks: at most %d queries a tick, the actors' phase at most %.1f ms (%d ticks over 10 ms); aware %d of %d samples; %s" % [
		far_m, _tick_queries.size(), worst, phase_max / 1000.0, slow, aware_samples, samples, ", ".join(lines)])
	assert_true(far_m >= 150.0 and far_m <= 250.0, "the giant stands 150-250 m from them (%.0f m)" % far_m)
	assert_true(aware_samples * 2 >= samples, "and they stay aware of it (%d of %d samples)" % [aware_samples, samples])
	assert_true(worst <= cap, "no tick spends more than the budget's %d queries (at most %d)" % [cap, worst])
	for n in _ranged(d):
		assert_true(n.search_queries_peak <= EnemyActor.SEARCH_QUERIES_PER_TICK,
			"%s's searches spend at most one candidate's queries a tick (%d)" % [n.entity_id, n.search_queries_peak])
	assert_true(slow <= 3, "the actors' phase stays under 10 ms (%d ticks over it, at most %.1f ms)" % [slow, phase_max / 1000.0])


func test_a_firing_point_search_with_nothing_to_find_spreads_over_ticks_and_ends() -> void:
	var w: WorldRoot = await _world(Vector2(-110.0, 520.0))
	var p := w.player()
	_stage_4(p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var d := w.director()
	for i in 20:
		await step_ticks(30)
		if d.spawned(RANGED[1]) != null:
			break
	var a := d.spawned(RANGED[1]) as EnemyActor
	assert_true(a != null, "the Hollow's second archer is in the world")
	if a == null:
		return
	a.ai_enabled = false   # the test asks it directly
	var target := Vector3(-120.0, 2.8, 560.0)   # the camp's centre: in reach of its leash
	var band := Vector2(0.0, 0.5)               # a band no snapped ring point lies in: every candidate fails
	assert_false(a.target_out_of_reach(a.global_position, target, band), "the target is in reach")
	# the level's budget all but spent this tick: the search waits without a query
	await step_ticks(1)
	NavQuery.spend(w, NavQuery.budget_left(w) - 2)
	var q0 := NavQuery.queries_total
	a.brain.nav_search_pending = false
	assert_eq(a.call("_resolve_firing_point", a.global_position, target, band, 0.0, false), Vector3.INF, "nothing yet")
	assert_true(a.brain.nav_search_pending, "the search waits for the budget")
	assert_eq(NavQuery.queries_total - q0, 0, "and spent no query")
	# then one candidate a tick until every one was tried
	var calls := 0
	var finished := false
	for i in 30:
		await step_ticks(1)
		q0 = NavQuery.queries_total
		a.brain.nav_search_pending = false
		var r: Vector3 = a.call("_resolve_firing_point", a.global_position, target, band, 0.0, false)
		calls += 1
		var spent := NavQuery.queries_total - q0
		assert_true(spent <= EnemyActor.SEARCH_QUERIES_PER_TICK, "call %d spent %d queries" % [calls, spent])
		assert_true(NavQuery.used_this_tick(w) <= 8, "within the level's budget")
		if not a.brain.nav_search_pending:
			assert_eq(r, Vector3.INF, "nothing walkable in the band: no firing point (it holds, and waits FIRING_REPICK_S)")
			finished = true
			break
	assert_true(finished and calls > 1, "the search resumed over %d ticks and ended" % calls)
	assert_true(calls <= EnemyActor.RING_STEPS * 2 + 1, "one candidate a tick: at most %d ticks (%d)" % [EnemyActor.RING_STEPS * 2 + 1, calls])


## The archer's own resolver chain (brain.firing_point_resolver: P22's front arc, then P09's markers
## and ring): a front arc that ends with nothing hands over to the ring, which resumes over the next
## ticks - the arc is not searched again meanwhile (it used to start anew at every call and overwrite
## the ring's place, so the ring never ran and the search never ended).
func test_a_ranged_units_chain_of_searches_goes_on_from_the_front_arc_to_the_ring_and_ends() -> void:
	var w: WorldRoot = await _world(Vector2(-110.0, 520.0))
	var p := w.player()
	_stage_4(p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	var d := w.director()
	for i in 20:
		await step_ticks(30)
		if d.spawned(RANGED[1]) != null:
			break
	var a := d.spawned(RANGED[1]) as EnemyActor
	assert_true(a != null, "the Hollow's second archer is in the world")
	if a == null:
		return
	a.ai_enabled = false   # the test asks it directly
	var target := Vector3(-120.0, 2.8, 560.0)   # the camp's centre: in reach of its leash
	var band := Vector2(0.0, 0.5)               # no snapped candidate lies in it: every one fails
	# the giant's camera looks from the target toward the archer: the arc's candidates lie in front of it
	p.camera_rig.yaw = TargetingRules.yaw_of(Vector3(a.global_position.x - target.x, 0.0, a.global_position.z - target.z))
	await step_ticks(2)
	assert_false(a.camera_view().is_empty(), "the giant's camera is there: the front arc searches first")
	var resolver: Callable = a.brain.firing_point_resolver
	var stages := {}
	var calls := 0
	var finished := false
	var r := Vector3.ZERO
	for i in 120:
		await step_ticks(1)
		if NavQuery.budget_left(w) < EnemyActor.SEARCH_CANDIDATE_QUERIES:
			continue   # the camp's other members spent this tick's budget: the search would only wait
		var q0 := NavQuery.queries_total
		a.brain.nav_search_pending = false
		r = resolver.call(a.global_position, target, band, 0.0, false)
		calls += 1
		var spent := NavQuery.queries_total - q0
		assert_true(spent <= EnemyActor.SEARCH_QUERIES_PER_TICK, "call %d spent %d queries" % [calls, spent])
		var key := String(a.get("_search_key"))
		if key != "":
			stages[key] = int(stages.get(key, 0)) + 1
		if not a.brain.nav_search_pending or calls >= 60:
			finished = not a.brain.nav_search_pending
			break
	print("    the chain ended after %d calls (%s): %s" % [calls, str(stages), str(r)])
	assert_true(stages.has("firing_arc"), "the front arc searched over several ticks (%s)" % str(stages))
	assert_true(stages.has("firing_ring"), "then the ring did (%s)" % str(stages))
	assert_true(finished, "and the search ended (%d calls)" % calls)
	assert_eq(r, Vector3.INF, "with nothing in the band: no firing point (it holds, and waits FIRING_REPICK_S)")
	var arc_steps := int(floor(float((a.call("_tactics") as Dictionary).get("front_arc_deg", 0.0)) / EnemyActor.RING_STEP_DEG))
	assert_true(calls <= arc_steps * 2 + 1 + EnemyActor.RING_STEPS * 2 + 1,
		"one candidate a tick: at most every arc and ring candidate once (%d calls)" % calls)


## P30's flee resolver chains the formation's rout point and P04's flight: once the rout point found
## nowhere reachable and the flight it fell back to stopped for the budget, the flight resumes where it
## stopped - the rout point is not asked again meanwhile (it would spend the tick's share first, every
## time, and the flight would never go on). A real navmesh always gives the rout point a reachable
## point (a partial path's end), so the test marks its failure (_p30_rout_failed) itself.
func test_a_routed_members_flight_resumes_after_its_rout_point_failed() -> void:
	var w: WorldRoot = await _world(Vector2(60.0, 640.0))
	var p := w.player()
	_stage_4(p)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await _go(w, Vector2(-84.9 + 16.0, 568.0))   # before the shield wall's front rank
	var d := w.director()
	var f: Formation = null
	for i in 30:
		await step_ticks(30)
		f = d.formation(Formation.formation_id(RAIDERS, "shields"))
		if f != null and not f.all_members().is_empty():
			break
	assert_true(f != null and not f.all_members().is_empty(), "the Raiders' shield wall formed")
	if f == null or f.all_members().is_empty():
		return
	var m := f.all_members()[0] as EnemyActor
	m.ai_enabled = false   # the test asks it directly
	m.brain.call("_rout")
	assert_eq(m.brain.state, EnemyBrain.AIState.ROUTED, "the member routed")
	var threat := p.global_position
	var dist := float(m.brain.ai.get("flee_distance_m", 12.0))
	# its flight stops at its first candidate: the level's budget all but spent this tick
	await step_ticks(1)
	NavQuery.spend(w, NavQuery.budget_left(w) - 2)
	m.brain.nav_search_pending = false
	assert_eq(m.call("_resolve_flee_point", m.global_position, threat, dist), Vector3.INF, "no flight point yet")
	assert_true(m.brain.nav_search_pending and m.search_resuming("flee"), "the flight waits for the budget")
	m.set("_p30_rout_failed", true)   # the rout point it fell back from found nowhere reachable
	var calls := 0
	var finished := false
	var keys := {}
	for i in 60:
		await step_ticks(1)
		if NavQuery.budget_left(w) < EnemyActor.SEARCH_CANDIDATE_QUERIES:
			continue   # the fight spent this tick's budget: the flight would only wait
		var q0 := NavQuery.queries_total
		m.brain.nav_search_pending = false
		var r: Vector3 = m.brain.flee_resolver.call(m.global_position, threat, dist)
		calls += 1
		assert_true(NavQuery.queries_total - q0 <= EnemyActor.SEARCH_QUERIES_PER_TICK, "call %d spent %d queries" % [calls, NavQuery.queries_total - q0])
		var key := String(m.get("_search_key"))
		keys[key] = true
		if calls == 1:
			assert_true(key != "flee" or int(m.get("_search_next")) > 0, "the flight went on from where it stopped (%s at %d)" % [key, int(m.get("_search_next"))])
		if not m.brain.nav_search_pending:
			finished = true
			print("    the routed member's flight ended after %d call(s): %s" % [calls, str(r)])
			break
		if calls >= 30:
			break
	assert_false(keys.has("rout"), "the rout point was not asked again while the flight resumed (%s)" % str(keys))
	assert_true(finished and calls <= EnemyActor.FLEE_MAX_STEPS * 2 + 1, "and the flight ended within its candidates (%d calls)" % calls)
