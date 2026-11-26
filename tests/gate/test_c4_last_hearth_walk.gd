extends IntegrationSuite
## C4's gate walk (decisions C4-1..C4-6): Last Hearth taken from tier 0 to tier 3 in the real open world
## (scenes/world/world.tscn, deterministic streaming) by a scripted run that does the work as a player does - the
## giant carries every load from its source to its site (HaulSource and PlayerHaul's E), heaves the rockfall off the
## Hearth path, kills the trolls on the crags and the dire pack on the pilgrims' track, gives what each project wants
## from his pack, beats the Rimward's raid back with the garrison loosing beside him, and raises each project at its
## site (SettlementSite's E). At every tier: the tier's work shown (its FlagVisibility elements), its life once he is
## away, the folk's paths valid (a human-layer path from the gate to the bonfire and the hall), its unlocks open (the
## hall's rest, the trades, the Hearth's forge, the Colossus Steps waystone, the garrison, the Colossus Anvil that
## rimforges), and at the end the state written into a checkpoint document and read back whole.

const SCENE := "res://scenes/world/world.tscn"
const LH := "settlement.last_hearth"
const GATE := Vector2(-150.0, -1276.0)
const BONFIRE := Vector2(-206.0, -1262.0)
const HALL := Vector2(-236.0, -1258.0)
const WINDFALL := Vector2(-326.0, -1252.0)
const PIER := Vector2(-40.0, -1420.0)
const ROCKFALL := Vector2(-118.0, -1281.0)
const CRAGS := Vector2(-345.0, -1395.0)
const DIRE := Vector2(-190.0, -1395.0)
const AWAY := Vector2(150.0, -1250.0)

var _w: WorldRoot


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2, stage := 7) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.last_hearth")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.set_flag("act.two.begun", true)
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	GameSession.on_level_ready(w, p)
	await _place(w, xz)
	TitanDuel.prepare(p, stage)
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 220.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 180.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	await step_ticks(3)


func _node(group: String, id: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id:
			return n
	return null


func _flagged(id: String) -> FlagVisibility:
	for n in get_tree().get_nodes_in_group(FlagVisibility.GROUP):
		if str(n.name) == id.validate_node_name() or str(n.name) == (id + "_shown").validate_node_name():
			return n as FlagVisibility
	return null


func _use(node: Interactable) -> void:
	var p := _w.player()
	p.interact.use_candidate({"node": node, "id": node.interact_id, "prompt": node.prompt_text(p), "priority": 0, "distance": 0.0})
	await step_ticks(3)


## One load carried from its source to its site: taken up, walked (placed) to the site, set down with E.
func _haul(source_id: String, source_at: Vector2, site_at: Vector2) -> bool:
	var p := _w.player()
	await _place(_w, source_at)
	var src := _node("interactables", source_id) as HaulSource
	if src == null:
		for n in get_tree().get_nodes_in_group("interactables"):
			if n is HaulSource and (n as HaulSource).world_id == source_id:
				src = n
	assert_true(src != null, "the source %s is loaded" % source_id)
	if src == null:
		return false
	await _use(src)
	assert_true(p.haul.is_carrying(), "%s: a load taken up" % source_id)
	await _place(_w, site_at)
	p.interact.refresh()
	var cand := p.interact.current_candidate()
	assert_true(str(cand.get("prompt", "")).begins_with("Set the"), "at the site: %s" % str(cand.get("prompt", "")))
	p.interact.use_candidate(cand)
	await step_ticks(3)
	assert_false(p.haul.is_carrying(), "%s: set down" % source_id)
	return true


func _raise(site_id: String, site_at: Vector2) -> Dictionary:
	await _place(_w, site_at)
	var site: SettlementSite = null
	for n in get_tree().get_nodes_in_group(SettlementSite.GROUP):
		if (n as SettlementSite).world_id == site_id:
			site = n
	assert_true(site != null, "the site %s" % site_id)
	if site == null:
		return {}
	assert_true(site.can_interact(_w.player()), "%s ready: %s" % [site_id, site.blocked_reason(_w.player())])
	await _use(site)
	return site.last_result


## Kills every living enemy (team ENEMY) within `r` m of `xz` with the giant's blows (lethal hits from him).
func _kill_near(xz: Vector2, r: float) -> int:
	var p := _w.player()
	var n := 0
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
		n += 1
	await step_ticks(3)
	return n


func _away_and_back() -> void:
	var watch := _w.get_node_or_null("SettlementWatch") as SettlementWatch
	await _place(_w, AWAY)
	await step_ticks(SettlementWatch.POLL_TICKS + 2)
	if watch != null:
		watch.poll()
	await _place(_w, BONFIRE)
	await step_ticks(60)


func _path_ok(from: Vector2, to: Vector2) -> bool:
	var a := Vector3(from.x, _w.height_at(Vector3(from.x, 0, from.y)), from.y)
	var b := Vector3(to.x, _w.height_at(Vector3(to.x, 0, to.y)), to.y)
	var path := NavQuery.path(_w, a, b, 1, NavQuery.PURPOSE_FAR)
	return path.size() >= 2 and Vector2(path[path.size() - 1].x, path[path.size() - 1].z).distance_to(to) < 6.0


func test_last_hearth_from_tier_0_to_3() -> void:
	_w = await _world(BONFIRE)
	var p := _w.player()
	var rec := SettlementRules.record(LH)
	var st := SettlementWork.state(rec)
	await step_ticks(30)
	WorldState.set_flag("event.hearth_raid.runs", 0)
	# ---- tier 0: the camp as found
	assert_eq(SettlementRules.tier_of(st), 0, "tier 0")
	assert_true(_flagged("world.hoarfell.hearth_hall_shell") != null and _flagged("world.hoarfell.hearth_hall_shell").visible,
		"the hall's shell stands")
	assert_false(_flagged("world.hoarfell.hearth_hall").visible, "no roofed hall")
	assert_true(_node("interactables", "world.hoarfell.hearth_board") != null or get_tree().root.find_child("world_hoarfell_hearth_board", true, false) != null,
		"the tally-board")
	var forge := _node("forges", "world.hoarfell.hearth_forge") as Forge
	assert_true(forge != null and not forge.is_visible_in_tree(), "no forge yet (hidden)")
	assert_true(_path_ok(GATE, BONFIRE), "tier 0: the folk's path from the gate to the bonfire")
	# ---- tier 1: two timbers from the Windfall, three hides, the rockfall heaved; the roof-tree raised
	for k in 2:
		await _haul("world.hoarfell.windfall_timber", WINDFALL, HALL + Vector2(6, -4))
	assert_true(_flagged("world.hoarfell.hearth_hall_timber_2").visible, "the second timber lies by the hall")
	WorldState.add_item("item.hide", 3, "test")
	assert_true(bool(SettlementWork.give(rec, "hall_roof", "item.hide").ok), "three hides given")
	await _place(_w, ROCKFALL + Vector2(8, 0))
	var rock := get_tree().root.find_child("world_hoarfell_hearth_rockfall", true, false)
	assert_true(rock != null, "the rockfall on the Hearth path")
	if rock != null:
		var heave := rock.find_children("*", "HeavePoint", true, false)
		assert_false(heave.is_empty(), "its heave")
		if not heave.is_empty():
			await _use(heave[0] as Interactable)
	assert_true(WorldState.is_destroyed("world.hoarfell.hearth_rockfall"), "heaved aside")
	var r := await _raise("world.hoarfell.hearth_site_hall", HALL + Vector2(8, -4))
	assert_eq(int(r.get("tier_up", -1)), 1, "the roof-tree raised: tier 1")
	assert_true(_flagged("world.hoarfell.hearth_hall").visible and not _flagged("world.hoarfell.hearth_hall_shell").visible,
		"the roofed hall stands, the shell gone")
	assert_false(QuestConditions.truthy(WorldState.get_flag("settlement.last_hearth.tier_1.settled")), "its life not while he stands by")
	await _away_and_back()
	assert_true(QuestConditions.truthy(WorldState.get_flag("settlement.last_hearth.tier_1.settled")), "its life come behind his back")
	assert_true(_flagged("world.hoarfell.hearth_t1_life").visible, "the huts and the woodstack")
	assert_true(Sim.get_entity("world.hoarfell.hearth_folk_7") != null, "the newcomers in the camp")
	p.entity.combatant.pools.health = p.entity.combatant.pools.health_max * 0.5
	var rest := _node("interactables", "world.hoarfell.hearth_rest") as SettlementRest
	if rest == null:
		for n in get_tree().get_nodes_in_group("interactables"):
			if n is SettlementRest:
				rest = n
	assert_true(rest != null and rest.is_open(), "the hall's fire to rest by")
	if rest != null:
		await _place(_w, HALL + Vector2(8, -4))
		await _use(rest)
		assert_eq(p.entity.combatant.pools.health, p.entity.combatant.pools.health_max, "rested: health restored")
	assert_eq(SettlementRules.trades_open(rec, st).size(), 1, "Maera's trade open")
	assert_true(_path_ok(GATE, BONFIRE) and _path_ok(BONFIRE, HALL + Vector2(6, -3)), "tier 1: the paths")
	# ---- tier 2: three king-stones for the ring, the trolls off the crags; one for the forge and three iron
	for k in 3:
		await _haul("world.hoarfell.causeway_kingstones", PIER, GATE + Vector2(-12, 0))
	await _place(_w, CRAGS)
	await step_ticks(120)
	var killed := await _kill_near(CRAGS, 110.0)
	assert_true(killed >= 1, "the crag trolls struck down (%d)" % killed)
	await step_ticks(120)
	assert_true(QuestConditions.truthy(WorldState.get_flag("encounter.hoarfell_frost_trolls.cleared")), "the crags cleared")
	r = await _raise("world.hoarfell.hearth_site_ring", GATE + Vector2(-12, 0))
	assert_true(bool(r.get("ok", false)), "the gate-stones set")
	await _haul("world.hoarfell.causeway_kingstones", PIER, Vector2(-196, -1248))
	WorldState.add_item("item.iron_ingot", 3, "test")
	assert_true(bool(SettlementWork.give(rec, "forge", "item.iron_ingot").ok), "the forge's iron")
	r = await _raise("world.hoarfell.hearth_site_forge", Vector2(-196, -1248))
	assert_eq(int(r.get("tier_up", -1)), 2, "tier 2")
	assert_true(_flagged("world.hoarfell.hearth_ring").visible, "the stone ring stands")
	forge = _node("forges", "world.hoarfell.hearth_forge") as Forge
	assert_true(forge != null and forge.is_visible_in_tree() and forge.is_open(), "the Hearth's forge open")
	assert_true(forge != null and forge.does_work("warden_wood") and forge.does_work("titan_stone"), "it works the titans' parts")
	await _away_and_back()
	var garrison := get_tree().get_first_node_in_group("settlement_garrisons") as SettlementGarrison
	assert_true(garrison != null, "the garrison")
	await step_ticks(60)
	assert_true(garrison != null and garrison.manned_count() >= 4, "four archers on the steps (%d)" % (garrison.manned_count() if garrison else 0))
	var way := _node(Waystone.GROUP, "")
	var steps_way: Waystone = null
	for n in get_tree().get_nodes_in_group(Waystone.GROUP):
		if (n as Waystone).checkpoint_id == "world.cp.colossus_steps":
			steps_way = n
	assert_true(Forge.flags_allow(PackedStringArray(["settlement.last_hearth.tier_2.settled"]), {}, Callable(WorldState, "get_flag")),
		"the Colossus Steps waystone's flag holds")
	assert_true(steps_way == null or steps_way.global_position.x < 282.0, "its stone below the steps' stage-7 gate")
	assert_true(_path_ok(GATE, BONFIRE), "tier 2: the folk's path through the gate")
	# ---- tier 3: the raid beaten back beside the garrison, the pilgrims fetched, the beacon and the anvil raised
	var wd := _w.get_node_or_null("WanderDirector") as WanderDirector
	assert_true(wd != null and wd.events.has("event.hearth_raid"), "the raid's event")
	if wd != null and wd.events.has("event.hearth_raid"):
		await _place(_w, BONFIRE)
		var ev: WorldEvent = wd.events["event.hearth_raid"]
		wd.start_event(ev)
		await step_ticks(240)
		assert_eq(ev.state, WorldEvent.RUNNING, "the Rimward come for the Hearth")
		var shots0 := garrison.shots if garrison != null else 0
		await step_ticks(600)
		assert_true(garrison != null and garrison.shots > shots0, "the ring's archers loose at them (%d shots, %d hits)" % [
			garrison.shots if garrison else 0, garrison.hits if garrison else 0])
		for k in 6:
			await _kill_near(Vector2(-180, -1272), 160.0)
			await step_ticks(30)
		await step_ticks(120)
		assert_eq(str(WorldState.get_flag("event.hearth_raid.outcome", "")), "defended", "the raid beaten back")
	await _place(_w, DIRE)
	await step_ticks(120)
	await _kill_near(DIRE, 110.0)
	await step_ticks(120)
	assert_true(QuestConditions.truthy(WorldState.get_flag("encounter.hoarfell_dire_pack.cleared")), "the pilgrims' track clear")
	var beacon_site := Vector2(-231.1, -1319.0)
	await _haul("world.hoarfell.causeway_kingstones", PIER, beacon_site)
	await _haul("world.hoarfell.windfall_timber", WINDFALL, beacon_site)
	r = await _raise("world.hoarfell.hearth_site_beacon", beacon_site)
	assert_true(bool(r.get("ok", false)), "the beacon raised")
	await _haul("world.hoarfell.causeway_kingstones", PIER, Vector2(-146, -1296))
	WorldState.add_item("item.titan_iron", 1, "test")
	WorldState.add_item("item.iron_ingot", 2, "test")
	assert_true(bool(SettlementWork.give(rec, "anvil", "item.titan_iron").ok), "titan iron given")
	assert_true(bool(SettlementWork.give(rec, "anvil", "item.iron_ingot").ok), "iron given")
	r = await _raise("world.hoarfell.hearth_site_anvil", Vector2(-146, -1296))
	assert_eq(int(r.get("tier_up", -1)), 3, "tier 3: the Hearth-hold")
	assert_true(_flagged("world.hoarfell.hearth_beacon").visible, "the beacon tower")
	var anvil := _node("forges", "world.hoarfell.colossus_anvil") as Forge
	assert_true(anvil != null and anvil.is_open() and anvil.tier == "colossus", "the Colossus Anvil open")
	await _away_and_back()
	assert_true(_flagged("world.hoarfell.hearth_t3_life").visible, "the stall, the huts, the beacon's banners")
	assert_true(Sim.get_entity("world.hoarfell.hearth_pilgrim_1") != null, "the pilgrims home")
	assert_true(_path_ok(GATE, BONFIRE) and _path_ok(BONFIRE, HALL + Vector2(6, -3)), "tier 3: the paths")
	assert_eq(SettlementRules.current_projects(rec, st).size(), 0, "nothing more is asked")
	# ---- the save: the checkpoint document holds it whole
	var doc := GameSession.snapshot_document("test_c4")
	assert_eq(int(doc.schema_version), 3, "schema 3")
	var back := ExpansionState.from_doc(JSON.parse_string(JSON.stringify(doc)))
	assert_eq(int(back.settlements["poi.last_hearth"].level), 3, "tier 3 saved")
	assert_eq(SettlementRules.flags_owed(rec, back.settlements["poi.last_hearth"], doc.world.flags), {}, "the world's flags agree")
	print("    test_c4_last_hearth_walk: garrison %d shots, %d hits; static elements shown" % [
		garrison.shots if garrison else 0, garrison.hits if garrison else 0])
