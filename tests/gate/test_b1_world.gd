extends IntegrationSuite
## B1 in the real open world (scenes/world/world.tscn, deterministic streaming), beside Stoneback's quarry:
##   * Millford's quarry forge works titan stone (the layout's `works`): shut while he keeps the quarry, then it makes
##     the Quarry set from his slabs - the aftermath's hook, by data (world.quarry.reopened);
##   * the reopened quarry's piles of slabs and shackle iron are there only after it reopens, and give their stone;
##   * the warning posts stand on the quarry road's mouth and on the Woodway from the north with their areas;
##   * his sight is blocked by the ground: from his quarry he sees a giant on the quarry road and in the pit's open
##     side, not one behind the hill round his pit at the same distance.

const SCENE := "res://scenes/world/world.tscn"
const CENTRE := Vector2(-600.0, 452.0)


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _world(xz: Vector2) -> WorldRoot:
	GameSession.start_world_for_tests("world.cp.millford")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	await _place(w, xz)
	TitanDuel.prepare(p, 4)
	await step_ticks(2)
	return w


func _place(w: WorldRoot, xz: Vector2) -> void:
	var p := w.player()
	var at := Vector3(xz.x, 200.0, xz.y)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	var y := w.height_at(at)
	p.global_position = Vector3(xz.x, (y if not is_nan(y) else 20.0) + 0.3, xz.y)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT


func _node_by_id(group: String, id: String) -> Node:
	for n in get_tree().get_nodes_in_group(group):
		if str(n.get("world_id")) == id:
			return n
	return null


func test_millfords_forge_and_the_reopened_quarry() -> void:
	var w := await _world(Vector2(-372.0, 600.0))
	var p := w.player()
	var forge := _node_by_id("forges", "world.crownmarch.millford_forge") as Forge
	assert_true(forge != null, "Millford's quarry forge is placed")
	if forge == null:
		return
	assert_true(forge.does_work("titan_stone"), "it works titan stone")
	assert_false(forge.is_open(), "shut while he keeps the quarry")
	WorldState.add_item("item.stoneback_slab", 6, "test")
	WorldState.add_item("item.quarry_iron", 4, "test")
	assert_eq(str(forge.can_craft(p, "recipe.quarry_pauldrons").reason), "closed", "so nothing is made")
	WorldState.try_set_flag("world.quarry.reopened", true)
	assert_true(forge.is_open(), "lit when the quarry reopens")
	var made := forge.craft(p, "recipe.quarry_pauldrons")
	assert_true(made.ok, "the Quarry Pauldrons from his slabs: %s" % made.message)
	# the quarry's piles appear with the reopening
	await _place(w, Vector2(-565.0, 452.0))
	await step_ticks(2)
	var slab := _node_by_id("interactables", "world.crownmarch.quarry_slab_pile") as ItemPickup
	var iron := _node_by_id("interactables", "world.crownmarch.quarry_iron_pile") as ItemPickup
	assert_true(slab != null and iron != null, "both piles are placed in the pit")
	if slab == null or iron == null:
		return
	assert_true(slab.enabled and slab.can_interact(p), "the slabs can be taken now")
	var before := WorldState.count_of("item.stoneback_slab")
	slab.interact(p)
	assert_eq(WorldState.count_of("item.stoneback_slab"), before + 4, "four slabs")
	iron.interact(p)
	assert_true(WorldState.count_of("item.quarry_iron") >= 2, "and his shackles' iron")


func test_the_piles_are_not_there_before_the_quarry_reopens() -> void:
	var w := await _world(Vector2(-565.0, 452.0))
	var p := w.player()
	var slab := _node_by_id("interactables", "world.crownmarch.quarry_slab_pile") as ItemPickup
	assert_true(slab != null, "placed")
	if slab != null:
		assert_false(slab.enabled, "disabled while he lives (no prompt)")
		assert_false(slab.can_interact(p), "and nothing to take")


func test_the_warning_posts_and_his_sight() -> void:
	var w := await _world(Vector2(-447.0, 515.0))
	var places := WorldContent.places()
	for id: String in ["world.area.stoneback_warning_south", "world.area.stoneback_warning_north"]:
		assert_true(places.has(id), "%s is in the world's index" % id)
	var t: TitanTerritory = null
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is TitanTerritory:
			t = n
	assert_true(t != null, "his territory is loaded")
	if t == null:
		return
	assert_true(t.line_of_sight, "his sight is by line of sight")
	# the posts stand outside his sight
	for xz: Vector2 in [Vector2(-447.0, 515.0), Vector2(-466.0, 352.0)]:
		assert_true(Vector2(xz.x, xz.y).distance_to(CENTRE) > t.territory_m + 30.0, "the post at %s is well outside it" % xz)
	# within 110 m: seen on the quarry road (the pit's open side), not everywhere behind the hill round it
	await _place(w, Vector2(-505.0, 494.0))
	var p := w.player()
	assert_true(t.sees(p.global_position), "on the quarry road, 104 m out: seen")
	var hidden := 0
	var seen := 0
	for k in 24:
		var a := TAU * float(k) / 24.0
		var xz := CENTRE + Vector2(cos(a), sin(a)) * 100.0
		var y := w.height_at(Vector3(xz.x, 0.0, xz.y))
		if is_nan(y):
			continue
		if t.sees(Vector3(xz.x, y, xz.y)):
			seen += 1
		else:
			hidden += 1
	assert_true(seen >= 3, "seen from his pit on its open side (%d of 24 points at 100 m)" % seen)
	assert_true(hidden >= 3, "hidden behind the hill round it (%d of 24)" % hidden)
	print("    test_b1_world: at 100 m from his quarry %d of 24 points seen, %d hidden by the ground" % [seen, hidden])
