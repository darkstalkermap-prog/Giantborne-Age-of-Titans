extends IntegrationSuite
## M7 polish, lane B, on the real world (scenes/world/world.tscn, deterministic streaming; the default
## half is tests/integration/test_m7_polish_ai.gd):
##   * the path-query budget (plan §2.8, §5.2: nav_query.queries_per_tick 8) holds when a town's folk
##     flee at once: Brannock turns hostile with the giant at its south gate, its eight villagers look
##     for shelter in the same moment as its guards and archers turn on the giant, and no tick spends
##     more than the eight queries NavQuery counts - each villager's safe-point search tries one marker
##     a tick within the budget and resumes at the next tick, and its agent's path waits for the budget
##     too - while every villager still reaches a safe point (they used to search every marker at once,
##     outside the budget);
##   * a defied toll fort's tower archers hold the gate tower and loose arrows at a stage-4 giant on the
##     King's Road before the gate (they came down from the old watchtower at the fort's back - 54-70 m
##     from the road, beyond their sight and their arrows - and stood behind the closed gate, aware and
##     never firing): the tower stands on the palisade west of the gate, and an archer spawned on a
##     tower top its navmesh does not reach holds it as its post, without a path query;
##   * every chunk's navmeshes of every layer (the real world's and the test world's), loaded through
##     NavMaps as the streamer loads them, merge on their layer maps without one edge error - each
##     region on its own and all of a world's regions of a layer together, every seam with its
##     neighbours (the human meshes of c4_1, c4_2, c5_2 and c6_6 had four each on every sync: the human
##     map keyed its edges in 0.25 m cells; NavMaps now keys every map at its cell x 0.1).

const SCENE := "res://scenes/world/world.tscn"
const BRANNOCK := "encounter.crownmarch_brannock"
const FOLK := ["world.crownmarch.brannock_folk_1", "world.crownmarch.brannock_folk_2", "world.crownmarch.brannock_folk_3",
	"world.crownmarch.brannock_folk_4", "world.crownmarch.brannock_folk_5", "world.crownmarch.brannock_folk_6",
	"world.crownmarch.brannock_folk_7", "world.crownmarch.brannock_folk_8"]
## How long the villagers may take to reach shelter (the farthest runs about 60 m at 3 m/s).
const SHELTER_TICKS := 60 * 40

var _tick_queries: Array[int] = []
var _tick_agents: Array[int] = []
var _budget_level: Node = null
var _folk: Array[Civilian] = []
var _agent_goals := {}
var _phase_us: Array[int] = []
var _phase_t0 := 0


func after_each() -> void:
	Sim.remove_hooks(self)
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	await super()


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


## A stage-4 giant (its profile set directly: the growth path is P05's and P26's), invulnerable.
func _stage_4(p: GiantPlayer) -> void:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	assert_eq(int(p.current_growth_stage()), 4, "a stage-4 giant")
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")


func _phase_begin(_t: int) -> void:
	_phase_t0 = Time.get_ticks_usec()


func _phase_end(_t: int) -> void:
	_phase_us.append(Time.get_ticks_usec() - _phase_t0)


func _tick_end(_t: int) -> void:
	_tick_queries.append(NavQuery.used_this_tick(_budget_level))
	var set := 0
	for c in _folk:
		if not is_instance_valid(c):
			continue
		var goal: Variant = c.get("_nav_target")
		if goal != _agent_goals.get(c.entity_id, Vector3.INF) and goal != Vector3.INF:
			set += 1
		_agent_goals[c.entity_id] = goal
	_tick_agents.append(set)


# --------------------------------------------------------------------------- B4: a town's folk flee within the budget

func test_brannocks_folk_flee_at_once_within_the_path_query_budget_and_reach_shelter() -> void:
	var w: WorldRoot = await _world(Vector2(60.0, 480.0))   # on Brannock's street, inside its south gate
	var p := w.player()
	_stage_4(p)
	var d := w.director()
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
	assert_eq(folk.size(), FOLK.size(), "Brannock's eight villagers are in the world")
	if folk.size() != FOLK.size():
		return
	await step_ticks(30)
	var cap := int(NavQuery.settings(w).get("queries_per_tick", 0))
	assert_eq(cap, 8, "the world's budget is 8 path queries a tick")
	_budget_level = w
	_tick_queries.clear()
	_tick_agents.clear()
	_agent_goals.clear()
	_phase_us.clear()
	_folk = folk
	for c in folk:
		c.set("_phase_offset", 0)   # the worst their phases allow: all eight decide in the same tick
	Sim.add_hook(Sim.Hook.PRE_ACTORS, self, _phase_begin, 1 << 20)
	Sim.add_hook(Sim.Hook.POST_ACTORS, self, _phase_end, -(1 << 20))
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _tick_end, 1 << 20)
	var q0 := NavQuery.queries_total
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)   # the town sworn by force
	var t0 := Sim.tick
	var sheltered_at := {}
	while Sim.tick - t0 < SHELTER_TICKS and sheltered_at.size() < folk.size():
		await step_ticks(6)
		for c in folk:
			if c.sheltered and not sheltered_at.has(c.entity_id):
				sheltered_at[c.entity_id] = float(Sim.tick - t0) / Sim.TICK_RATE
	Sim.remove_hooks(self)
	var worst := 0
	var over := 0
	var first := _tick_queries.slice(0, mini(_tick_queries.size(), 120))
	for q in _tick_queries:
		worst = maxi(worst, q)
		if q > cap:
			over += 1
	var first_worst := 0
	for q in first:
		first_worst = maxi(first_worst, q)
	var agents_worst := 0
	for n in _tick_agents:
		agents_worst = maxi(agents_worst, n)
	var phase_max := 0
	for us in _phase_us:
		phase_max = maxi(phase_max, us)
	var lines := PackedStringArray()
	var last := 0.0
	var peak := 0
	for c in folk:
		var s := "%s %s" % [c.entity_id.get_slice(".", 2), c.brain.state_name()]
		if sheltered_at.has(c.entity_id):
			s += " %.1f s" % float(sheltered_at[c.entity_id])
			last = maxf(last, float(sheltered_at[c.entity_id]))
		peak = maxi(peak, c.search_queries_peak)
		lines.append(s)
	print("    Brannock hostile, all eight villagers deciding in one tick: %d ticks, at most %d path queries a tick (%d in the first 2 s; the villagers' agent paths counted), %d ticks over %d; %d queries in all; at most %d agent paths set in one tick; the actors' phase at most %.1f ms; the last villager in shelter after %.1f s; a villager's searches at most %d queries a tick; %s" % [
		_tick_queries.size(), worst, first_worst, over, cap, NavQuery.queries_total - q0, agents_worst, phase_max / 1000.0, last, peak, ", ".join(lines)])
	for c in folk:
		assert_eq(c.brain.flee_reason, "hostile", "%s fled because the town turned hostile" % c.entity_id)
		assert_true(c.sheltered, "%s reached a safe point (%s)" % [c.entity_id, c.brain.state_name()])
		assert_true(c.safe_marker != null and str(c.safe_marker.get("marker_id")).begins_with("world.marker.brannock_"),
			"%s ran to one of Brannock's shelters (%s)" % [c.entity_id, c.safe_marker.get("marker_id") if c.safe_marker != null else "none"])
		assert_eq(c.brain.picks, 1, "%s chose its shelter once" % c.entity_id)
	assert_true(worst <= cap, "no tick spends more than the budget's %d queries (at most %d, %d ticks over)" % [cap, worst, over])
	assert_true(peak <= Civilian.SEARCH_QUERIES_PER_TICK, "a villager's search tries one marker a tick (%d queries at most)" % peak)


# --------------------------------------------------------------------------- B3: the toll fort's tower archers

const TOWER_ARCHERS := {"world.crownmarch.toll_archer_1": "world.marker.toll_tower_w",
	"world.crownmarch.toll_archer_2": "world.marker.toll_tower_e"}
## Where the giant stands: on the King's Road before the gate, about 22 m from the gate tower.
const ROAD_SPOT := Vector2(455.0, 376.0)
const TOWER_TICKS := 60 * 20


func test_a_defied_toll_forts_tower_archers_hold_the_tower_and_shoot_a_stage_4_giant_on_the_road() -> void:
	var w: WorldRoot = await _world(Vector2(460.0, 560.0))
	var p := w.player()
	_stage_4(p)
	WorldState.set_flag("world.toll_fort.defied", true)   # "I pay no toll.": the stand-down ends
	await _go(w, ROAD_SPOT)
	var d := w.director()
	var archers: Array[EnemyActor] = []
	for i in 40:
		await step_ticks(15)
		archers.clear()
		for id: String in TOWER_ARCHERS:
			var a := d.spawned(id) as EnemyActor
			if a != null:
				archers.append(a)
		if archers.size() == TOWER_ARCHERS.size():
			break
	assert_eq(archers.size(), TOWER_ARCHERS.size(), "the fort's two tower archers are in the world")
	if archers.size() != TOWER_ARCHERS.size():
		return
	var shots := {}
	var on_start := func(_t: int, actor: String, action: String, _i: int) -> void:
		if action == "ability.archer_shot":
			shots[actor] = int(shots.get(actor, 0)) + 1
	Events.ability_started.connect(on_start)
	var lowest := {}
	var farthest := {}
	var posts := {}
	for i in TOWER_TICKS / 6:
		await step_ticks(6)
		for a in archers:
			if not is_instance_valid(a) or not a.entity.is_alive():
				continue
			var post := a.post_marker()
			if post != null:
				posts[a.entity_id] = post
			lowest[a.entity_id] = minf(float(lowest.get(a.entity_id, INF)), a.global_position.y)
			if post != null:
				farthest[a.entity_id] = maxf(float(farthest.get(a.entity_id, 0.0)),
					Vector2(a.global_position.x - post.global_position.x, a.global_position.z - post.global_position.z).length())
	Events.ability_started.disconnect(on_start)
	var landed := {}
	for r in hits_on(p.entity.entity_id):
		if TOWER_ARCHERS.has(r.event.attacker_id) and r.event.action_id == "ability.archer_shot":
			landed[r.event.attacker_id] = int(landed.get(r.event.attacker_id, 0)) + 1
	var lines := PackedStringArray()
	for a in archers:
		var dist := Vector2(a.global_position.x - p.global_position.x, a.global_position.z - p.global_position.z).length()
		lines.append("%s %s at %s (%.1f m from the giant): %d shots, %d hits, lowest y %.2f, %.2f m off its post, searches %d" % [
			a.entity_id.get_slice(".", 2), a.brain.state_name(), a.global_position.snapped(Vector3(0.1, 0.1, 0.1)), dist,
			int(shots.get(a.entity_id, 0)), int(landed.get(a.entity_id, 0)), float(lowest.get(a.entity_id, -1.0)),
			float(farthest.get(a.entity_id, -1.0)), a.search_queries_peak])
	print("    the gate tower against a stage-4 giant on the road: %s" % "; ".join(lines))
	var hits_total := 0
	for a in archers:
		var post: Node3D = posts.get(a.entity_id)
		assert_true(post != null, "%s holds a post" % a.entity_id)
		if post == null:
			continue
		assert_eq(str(post.get("marker_id")), str(TOWER_ARCHERS[a.entity_id]), "%s holds the tower top it spawned on" % a.entity_id)
		assert_true(float(lowest.get(a.entity_id, 0.0)) > post.global_position.y - 1.0,
			"%s never left the tower (lowest y %.2f, the post at %.2f)" % [a.entity_id, lowest.get(a.entity_id, 0.0), post.global_position.y])
		assert_true(float(farthest.get(a.entity_id, 0.0)) <= 1.0, "%s stayed at its post (%.2f m off)" % [a.entity_id, farthest.get(a.entity_id, 0.0)])
		assert_true(int(shots.get(a.entity_id, 0)) >= 3, "%s loosed arrows at the giant on the road (%d)" % [a.entity_id, shots.get(a.entity_id, 0)])
		assert_eq(a.search_queries_peak, 0, "%s never searched for a firing point (no path query)" % a.entity_id)
		hits_total += int(landed.get(a.entity_id, 0))
	assert_true(hits_total >= 1, "their arrows struck the giant (%d hits)" % hits_total)


# --------------------------------------------------------------------------- B2: every chunk merges on its maps

## The navmesh files of chunk `id` in `dir`: [bit, path] for every layer and gate bit that has one.
static func _chunk_navmeshes(dir: String, id: String, bits: Array) -> Array:
	var out: Array = []
	for bit: int in bits:
		var path := NavBake.nav_path(dir, id, bit)
		if ResourceLoader.exists(path):
			out.append([bit, path])
	return out


## Adds `ids`' navmeshes to a fresh NavMaps set up as the streamer's (deterministic) and waits for
## them to sync; returns [the edge errors the syncs warned about, the regions added].
func _merge(w: Dictionary, ids: Array) -> Array:
	var size := float(w.chunk_size_m)
	var origin := Vector3(float(w.origin_m[0]), 0.0, float(w.origin_m[2]))
	var gates: Array = (w.get("gate_bits", {}) as Dictionary).values()
	var bits: Array = (w.nav_layers as Array) + gates
	var log := NavEdgeLog.new()
	OS.add_logger(log)
	var maps := NavMaps.new()
	maps.setup(w.nav_layers, gates, NavBake.TITAN_LAYER, true)
	var added := 0
	for id: String in ids:
		var c := ChunkData.coords_for(id)
		var at := origin + Vector3(c.x * size, 0.0, c.y * size)
		for entry: Array in _chunk_navmeshes(str(w.nav_dir), id, bits):
			maps.add_region(id, int(entry[0]), load(str(entry[1])) as NavigationMesh, Transform3D(Basis(), at))
			added += 1
	var ready := false
	for i in 12:
		await step_ticks(1)
		ready = ids.all(func(id: String) -> bool: return maps.chunk_ready(id))
		if ready:
			break
	await step_ticks(1)
	OS.remove_logger(log)
	assert_true(ready, "%d chunk(s) synced" % ids.size())
	maps.free_all()
	return [log.edge_errors(), added]


func test_every_chunks_navmeshes_merge_on_their_layer_maps_without_edge_errors() -> void:
	for level_id: String in ["level.world", "level.test_world"]:
		var w: Dictionary = GameData.get_record(level_id).get("world", {})
		assert_false(w.is_empty(), "%s has a world block" % level_id)
		if w.is_empty():
			continue
		var ids: Array = []
		for z in int(w.grid[1]):
			for x in int(w.grid[0]):
				ids.append(ChunkData.id_for(Vector2i(x, z)))
		var all: Array = await _merge(w, ids)
		print("    %s: %d regions of %d chunks on their %d layer maps, %d edge errors" % [level_id, all[1], ids.size(),
			(w.nav_layers as Array).size(), all[0]])
		assert_true(int(all[1]) > ids.size(), "%s's navmeshes loaded (%d regions)" % [level_id, all[1]])
		if int(all[0]) == 0:
			assert_eq(int(all[0]), 0, "%s: every region and seam merges without an edge error" % level_id)
			continue
		# name the chunks: each alone
		var bad := PackedStringArray()
		for id: String in ids:
			var alone: Array = await _merge(w, [id])
			if int(alone[0]) > 0:
				bad.append("%s (%d)" % [id, alone[0]])
		fail("%s: %d edge errors on its layer maps; alone: %s (the rest are between neighbours)" % [level_id, all[0],
			", ".join(bad) if not bad.is_empty() else "none"])
