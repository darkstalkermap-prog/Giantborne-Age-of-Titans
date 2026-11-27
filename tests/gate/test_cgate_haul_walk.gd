extends IntegrationSuite
## The milestone C gate (docs/systems/Cgate.md, "The hauling"): Last Hearth's tier 1 -> 3 loop walked end to end in the
## real open world by a scripted player - every load taken up at its source and walked (the world bot's route planner,
## BotRoute: the road graph and the titan map's legs; the stick through the input router, sprint held, the carry's
## pace) to its site and set down, the walks back empty, the walks to the rockfall, the crags, the pilgrims' track and
## the raid (their fights ended at once: the raid's own measure is test_cgate_raid), each project raised. Each leg is
## timed; no loaded leg may take more than LEG_LIMIT_S of walking at stage 6, and the giant never has to be put back on
## his way (no stuck leg). The legs' times print as HAUL lines (the gate's report).

const SCENE := "res://scenes/world/world.tscn"
const LH := "settlement.last_hearth"
const BONFIRE := Vector2(-206.0, -1262.0)
const HALL_SITE := Vector2(-228.0, -1262.0)
const RING_SITE := Vector2(-162.0, -1276.0)
const FORGE_SITE := Vector2(-196.0, -1248.0)
const BEACON_SITE := Vector2(-231.1, -1319.0)
const ANVIL_SITE := Vector2(-146.0, -1296.0)
const ROCKFALL := Vector2(-118.0, -1281.0)
const CRAGS := Vector2(-345.0, -1395.0)
const DIRE := Vector2(-190.0, -1395.0)
## The owner's bar for a single haul leg (walking with the load, at the stage that does it).
const LEG_LIMIT_S := 60.0
const LEG_GIVE_UP_S := 240.0
const STUCK_S := 6.0

var _w: WorldRoot
var _route: BotRoute
var legs: Array = []
var stuck := 0
var fights_met := 0


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _place(xz: Vector2) -> void:
	var p := _w.player()
	var at := Vector3(xz.x, 220.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not _w.streamer.ring_ready(at) and guard < 900:
		_w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := _w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 180.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(3)


## Walks the giant to `to` (horizontally within `arrive_m`) as a player does: returns the seconds it took.
func walk(to: Vector2, label: String, arrive_m := 8.0) -> float:
	var p := _w.player()
	var goal := Vector3(to.x, _w.height_at(Vector3(to.x, 0.0, to.y)), to.y)
	_route = BotRoute.new(_w.index(), _w)
	_route.stage = p.current_growth_stage()
	_route.layers = BotDiagnosis.layers_for(p, _w)
	_route.plan(p.global_position, goal)
	var t0 := Sim.tick
	var last_pos := p.global_position
	var last_move := Sim.tick
	var dist := 0.0
	var was_stuck := false
	while Vector2(p.global_position.x, p.global_position.z).distance_to(to) > arrive_m:
		if Sim.tick - t0 > int(LEG_GIVE_UP_S * Sim.TICK_RATE):
			break
		var aim := _route.steer(p.global_position, Sim.tick, _w)
		var dir := Vector3(aim.x - p.global_position.x, 0.0, aim.z - p.global_position.z)
		if dir.length() < 0.5:
			dir = Vector3(goal.x - p.global_position.x, 0.0, goal.z - p.global_position.z)
		_steer(p, dir)
		await step_ticks(1)
		var moved := Vector2(p.global_position.x - last_pos.x, p.global_position.z - last_pos.z).length()
		if moved > 0.5:
			dist += moved
			last_pos = p.global_position
			last_move = Sim.tick
		elif Sim.tick - last_move > int(STUCK_S * Sim.TICK_RATE):
			was_stuck = true
			stuck += 1
			print("    HAUL_STUCK %s at (%.0f, %.0f)" % [label, p.global_position.x, p.global_position.z])
			await _place(Vector2(aim.x, aim.z) if Vector2(aim.x, aim.z).distance_to(to) > 1.0 else to)
			last_pos = p.global_position
			last_move = Sim.tick
	p.router.set_injected_move(Vector2.ZERO)
	p.router.set_injected_hold(&"sprint", false)
	var s := float(Sim.tick - t0) / Sim.TICK_RATE
	var carrying: bool = p.haul.is_carrying()
	var row := {"leg": label, "s": snappedf(s, 0.1), "m": snappedf(dist, 1.0), "carrying": carrying, "stuck": was_stuck}
	legs.append(row)
	print("    HAUL %s" % JSON.stringify(row))
	await step_ticks(2)
	return s


func _steer(p: GiantPlayer, dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 1e-6:
		p.router.set_injected_move(Vector2.ZERO)
		return
	p.camera_rig.yaw = lerp_angle(p.camera_rig.yaw, TargetingRules.yaw_of(flat), 0.25)
	var local := flat.normalized().rotated(Vector3.UP, -p.camera_rig.yaw)
	p.router.set_injected_move(Vector2(local.x, -local.z).limit_length(1.0))
	p.router.set_injected_hold(&"sprint", _sprint())


func _node(group: String, id: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id:
			return n
	return null


func _use(node: Interactable) -> void:
	var p := _w.player()
	p.interact.use_candidate({"node": node, "id": node.interact_id, "prompt": node.prompt_text(p), "priority": 0, "distance": 0.0})
	await step_ticks(3)


## The nearest source of `load_id` to the giant (sources stand along their pile).
func _source(load_id: String) -> HaulSource:
	var p := _w.player()
	var best: HaulSource = null
	var best_d := INF
	for n in get_tree().get_nodes_in_group("interactables"):
		var h := n as HaulSource
		if h != null and h.load_id == load_id and h.is_inside_tree():
			var d := h.global_position.distance_to(p.global_position)
			if d < best_d:
				best = h
				best_d = d
	return best


func _source_xz(load_id: String, fallback: Vector2) -> Vector2:
	var s := _source(load_id)
	return Vector2(s.global_position.x, s.global_position.z) if s != null else fallback


## One load: walk to its pile, take it up, carry it to the site, set it down.
func haul(load_id: String, pile: Vector2, site: Vector2, label: String) -> void:
	var p := _w.player()
	await walk(_source_xz(load_id, pile), "to the %s pile (%s)" % [load_id, label], 10.0)
	var src := _source(load_id)
	assert_true(src != null and src.can_interact(p), "%s: the pile offers a load (%s)" % [label, src.blocked_reason(p) if src else "none"])
	if src == null:
		return
	await _use(src)
	assert_true(p.haul.is_carrying(), "%s: taken up" % label)
	await walk(site, "carry %s" % label, 6.0)
	# (D1: a fight met on the carry - a wolf's or a rimkin's blow staggers the giant and the load goes back to its pile,
	# as PlayerHaul rules - is ended as the raising's are, and the load taken up again once; the full gate run met five
	# fights on this walk where the suite alone met one, and lost the anvil's king-stone on its carry)
	if not p.haul.is_carrying():
		fights_met += 1
		print("    HAUL_DROPPED %s at (%.0f, %.0f)" % [label, p.global_position.x, p.global_position.z])
		await _kill_near(Vector2(p.global_position.x, p.global_position.z), 200.0)
		await step_ticks(120)
		await walk(_source_xz(load_id, pile), "back to the %s pile (%s)" % [load_id, label], 10.0)
		src = _source(load_id)
		if src != null and src.can_interact(p):
			await _use(src)
		assert_true(p.haul.is_carrying(), "%s: taken up again" % label)
		await walk(site, "carry %s again" % label, 6.0)
	p.interact.refresh()
	var cand := p.interact.current_candidate()
	if not str(cand.get("prompt", "")).begins_with("Set the"):
		await walk(site, "carry %s (closer)" % label, 2.0)
		p.interact.refresh()
		cand = p.interact.current_candidate()
	assert_true(str(cand.get("prompt", "")).begins_with("Set the"), "%s at its site: %s" % [label, str(cand.get("prompt", ""))])
	p.interact.use_candidate(cand)
	await step_ticks(3)
	assert_false(p.haul.is_carrying(), "%s: set down" % label)


func _raise(site_id: String, site_at: Vector2) -> void:
	await walk(site_at, "to raise %s" % site_id, 6.0)
	for n in get_tree().get_nodes_in_group(SettlementSite.GROUP):
		var s := n as SettlementSite
		if s.world_id == site_id:
			# (a fight met on the way - wolves, a rimkin scout - holds the raising back: ended as the others are)
			var tries := 0
			while not s.can_interact(_w.player()) and tries < 4:
				var p := _w.player()
				fights_met += 1
				await _kill_near(Vector2(p.global_position.x, p.global_position.z), 200.0)
				await step_ticks(180)
				tries += 1
			assert_true(s.can_interact(_w.player()), "%s ready: %s" % [site_id, s.blocked_reason(_w.player())])
			await _use(s)
			return
	assert_true(false, "the site %s" % site_id)


func _kill_near(xz: Vector2, r: float) -> void:
	var p := _w.player()
	for e: CombatEntity in Sim.entities():
		if e == null or not e.is_alive() or e.team != CombatEntity.Team.ENEMY or not is_instance_valid(e.actor):
			continue
		var at := (e.actor as Node3D).global_position
		if Vector2(at.x, at.z).distance_to(xz) > r:
			continue
		var h := HitEvent.new()
		h.tick = Sim.tick
		h.instance_id = Sim.new_instance_id()
		h.attacker_id = p.entity.entity_id
		h.target_id = e.entity_id
		h.power = 1.0e6
		h.attacker_stat = 10.0
		h.size_policy = "none"
		h.damage_split = {"physical": 1.0}
		h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
		h.attacker_position = p.global_position
		Sim.queue_hit(h)
	await step_ticks(3)


func _sprint() -> bool:
	return not OS.get_cmdline_user_args().has("--haul-walk")


## The fight there ended at once, again until its encounter counts as cleared.
func _clear(xz: Vector2, flag: String) -> void:
	for k in 6:
		await step_ticks(120)
		await _kill_near(xz, 140.0)
		var p := _w.player()
		await _kill_near(Vector2(p.global_position.x, p.global_position.z), 60.0)
		await step_ticks(120)
		if QuestConditions.truthy(WorldState.get_flag(flag)):
			break
	assert_true(QuestConditions.truthy(WorldState.get_flag(flag)), flag)


func _stage() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--haul-stage="):
			return int(a.get_slice("=", 1))
	return 6


func test_last_hearths_loop_walked_end_to_end() -> void:
	var stage := _stage()
	GameSession.start_world_for_tests("world.cp.last_hearth")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.set_flag("act.two.begun", true)
	WorldState.set_flag("event.hearth_raid.runs", 0)
	_w = (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(_w)
	_w.streamer.deterministic = true
	var p := _w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	GameSession.on_level_ready(_w, p)
	await _place(BONFIRE)
	TitanDuel.prepare(p, stage)
	await step_ticks(60)
	var rec := SettlementRules.record(LH)
	var t_start := Sim.tick
	# ---- tier 1
	var windfall := Vector2(-326.0, -1252.0)
	var pier := Vector2(-40.0, -1420.0)
	for k in 2:
		await haul("timber", windfall, HALL_SITE, "timber %d to the hall" % (k + 1))
	WorldState.add_item("item.hide", 3, "test")
	SettlementWork.give(rec, "hall_roof", "item.hide")
	await walk(ROCKFALL + Vector2(10, 0), "to the rockfall", 6.0)
	var rock := get_tree().root.find_child("world_hoarfell_hearth_rockfall", true, false)
	if rock != null:
		var heave := rock.find_children("*", "HeavePoint", true, false)
		if not heave.is_empty():
			await _use(heave[0] as Interactable)
	assert_true(WorldState.is_destroyed("world.hoarfell.hearth_rockfall"), "the rockfall heaved")
	await _raise("world.hoarfell.hearth_site_hall", HALL_SITE)
	var t1 := Sim.tick
	# ---- tier 2
	for k in 3:
		await haul("kingstone", pier, RING_SITE, "king-stone %d to the ring" % (k + 1))
	await walk(CRAGS, "to the crags", 25.0)
	await _clear(CRAGS, "encounter.hoarfell_frost_trolls.cleared")
	await _raise("world.hoarfell.hearth_site_ring", RING_SITE)
	await haul("kingstone", pier, FORGE_SITE, "king-stone to the forge")
	WorldState.add_item("item.iron_ingot", 3, "test")
	SettlementWork.give(rec, "forge", "item.iron_ingot")
	await _raise("world.hoarfell.hearth_site_forge", FORGE_SITE)
	var t2 := Sim.tick
	# ---- tier 3 (the raid: its outcome set as the raid's own measure leaves it)
	WorldState.set_flag("world.last_hearth.raid_defended", true)
	await walk(DIRE, "to the pilgrims' track", 25.0)
	await _clear(DIRE, "encounter.hoarfell_dire_pack.cleared")
	await haul("kingstone", pier, BEACON_SITE, "king-stone to the beacon")
	await haul("timber", windfall, BEACON_SITE, "timber to the beacon")
	await _raise("world.hoarfell.hearth_site_beacon", BEACON_SITE)
	await haul("kingstone", pier, ANVIL_SITE, "king-stone to the anvil")
	WorldState.add_item("item.titan_iron", 1, "test")
	WorldState.add_item("item.iron_ingot", 2, "test")
	SettlementWork.give(rec, "anvil", "item.titan_iron")
	SettlementWork.give(rec, "anvil", "item.iron_ingot")
	await _raise("world.hoarfell.hearth_site_anvil", ANVIL_SITE)
	var t3 := Sim.tick
	assert_eq(SettlementRules.tier_of(SettlementWork.state(rec)), 3, "tier 3 reached by walking")
	var worst := 0.0
	var carried := 0.0
	for row: Dictionary in legs:
		if bool(row.carrying):
			worst = maxf(worst, float(row.s))
			carried += float(row.s)
	print("    HAUL_TOTAL %s" % JSON.stringify({"stage": stage, "tier1_s": snappedf(float(t1 - t_start) / 60.0, 0.1),
		"tier2_s": snappedf(float(t2 - t1) / 60.0, 0.1), "tier3_s": snappedf(float(t3 - t2) / 60.0, 0.1),
		"carrying_s": snappedf(carried, 0.1), "worst_carry_s": snappedf(worst, 0.1), "stuck": stuck, "fights_met": fights_met}))
	assert_eq(stuck, 0, "no leg stuck (the giant never put back on his way)")
	assert_true(worst <= LEG_LIMIT_S, "no loaded leg over %.0f s at stage %d (worst %.1f s)" % [LEG_LIMIT_S, stage, worst])
