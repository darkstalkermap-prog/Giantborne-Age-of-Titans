extends IntegrationSuite
## M7 polish, lane B, on the real world (scenes/world/world.tscn, deterministic streaming; the default
## half is tests/integration/test_m7_polish_ai.gd):
##   * the path-query budget (plan §2.8, §5.2: nav_query.queries_per_tick 8) holds when a town's folk
##     flee at once: Brannock turns hostile with the giant at its south gate, its eight villagers look
##     for shelter in the same moment as its guards and archers turn on the giant, and no tick spends
##     more than the eight queries NavQuery counts - each villager's safe-point search tries one marker
##     a tick within the budget and resumes at the next tick, and its agent's path waits for the budget
##     too - while every villager still reaches a safe point (they used to search every marker at once,
##     outside the budget).

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
