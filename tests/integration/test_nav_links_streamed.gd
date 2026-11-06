extends IntegrationSuite
## P24b (plan M6-M9 §2.8, decision 13): nav links in a streamed chunk join their layer's map - the
## tiny nav world's fortified gate (tests/support/nav_tiny_world.gd, c2_0) stands between a north and
## a south navmesh with one closed link per layer - and open a path once the gate breaks, as soon as
## the map has synced the change (its iteration id); an unloaded and reloaded chunk's links rejoin.


func _root() -> WorldRoot:
	NavTinyWorld.write()
	NavTinyWorld.install_record()
	var root := NavTinyWorld.make_root()
	world.add_child(root)
	root.streamer.deterministic = true
	root.streamer.process_mode = Node.PROCESS_MODE_DISABLED
	return root


func _load_ready(root: WorldRoot, at: Vector3) -> bool:
	for i in 40:
		root.streamer.load_ring_slice(at)
		if root.streamer.ring_ready(at):
			return true
		await step_ticks(1)
	return root.streamer.ring_ready(at)


func _gate(root: WorldRoot) -> BreakableProp:
	for n in get_tree().get_nodes_in_group("breakables"):
		if n is BreakableProp and root.is_ancestor_of(n) and (n as BreakableProp).world_id == NavTinyWorld.GATE_WORLD_ID:
			return n as BreakableProp
	return null


## Waits until every layer map's iteration id passed `marks` ({map: id}); true when it did.
func _wait_maps(marks: Dictionary, max_ticks := 10) -> bool:
	for i in max_ticks:
		var all := true
		for m: RID in marks:
			all = all and NavigationServer3D.map_get_iteration_id(m) > int(marks[m])
		if all:
			return true
		await step_ticks(1)
	return false


func test_a_gate_link_joins_its_layer_map_and_opens_a_path_when_the_gate_breaks() -> void:
	var root := _root()
	var at := NavTinyWorld.at(2, Vector3(32, 0, 32))
	assert_true(await _load_ready(root, at), "the gate's chunk is ready")
	var gate := _gate(root)
	assert_true(gate != null, "the gate streamed in with c2_0's props")
	var links := {}
	for link: NavigationLink3D in gate.nav_links():
		links[link.name] = link
	assert_eq(links.keys().size(), 4, "its own NavLinkThrough and one link per layer: %s" % [links.keys()])
	for pair: Array in [["NavLinkHuman", 1], ["NavLinkLarge", 2], ["NavLinkTitan", 16], ["NavLinkThrough", 1]]:
		var link := links.get(pair[0]) as NavigationLink3D
		assert_true(link != null, "%s exists" % pair[0])
		if link == null:
			continue
		assert_eq(NavigationServer3D.link_get_map(link.get_rid()), root.nav_map(int(pair[1])),
			"%s joined the map of layer %d" % pair)
		assert_false(link.enabled, "%s is closed while the gate stands" % pair[0])
	assert_eq(int(root.streamer.nav_maps.links_assigned), 4, "the streamer put the four links on their maps")
	var north := NavTinyWorld.at(2, Vector3(32, NavTinyWorld.NAV_Y, 10))
	var south := NavTinyWorld.at(2, Vector3(32, NavTinyWorld.NAV_Y, 54))
	for layer: int in [1, 2, 16]:
		var p := NavQuery.path(root, north, south, layer, NavQuery.PURPOSE_FAR)
		var end := p[p.size() - 1] if p.size() > 0 else Vector3.INF
		assert_true(end.is_finite() and end.z <= NavTinyWorld.at(2, Vector3(0, 0, NavTinyWorld.WALL.x)).z + 0.01,
			"layer %d: the closed gate stops the path at the wall (ends at %s)" % [layer, end])
	var marks := {}
	for layer: int in [1, 2, 16]:
		marks[root.nav_map(layer)] = NavigationServer3D.map_get_iteration_id(root.nav_map(layer))
	assert_true(gate.force_open("test"), "the gate breaks")
	assert_true(gate.nav_links_enabled(), "its links open")
	assert_true(await _wait_maps(marks), "every layer map synced the opened links")
	for layer: int in [1, 2, 16]:
		var p := NavQuery.path(root, north, south, layer, NavQuery.PURPOSE_FAR)
		assert_true(p.size() > 0 and p[p.size() - 1].distance_to(south) < 0.5,
			"layer %d: the path now goes through the gate" % layer)
		var through := false
		for q: Vector3 in p:
			if absf(q.z - NavTinyWorld.at(2, NavTinyWorld.GATE_LOCAL).z) < 7.0 and absf(q.x - at.x) < 1.0:
				through = true
		assert_true(through, "layer %d: by way of the link" % layer)


func test_a_reloaded_chunk_rejoins_its_links() -> void:
	NavTinyWorld.write()
	NavTinyWorld.install_record(true, {"world": {"load_ring": 0, "unload_at": 2}})
	var root := NavTinyWorld.make_root()
	world.add_child(root)
	root.streamer.deterministic = true
	root.streamer.process_mode = Node.PROCESS_MODE_DISABLED
	var gate_at := NavTinyWorld.at(2, Vector3(32, 0, 32))
	assert_true(await _load_ready(root, gate_at), "c2_0 ready")
	assert_eq(int(root.streamer.nav_maps.links_assigned), 4, "its links joined")
	assert_true(await _load_ready(root, NavTinyWorld.at(0, Vector3(32, 0, 32))), "off to c0_0 (c2_0 unloads)")
	for i in 10:
		root.streamer.update(true)
	assert_false(root.streamer.is_loaded("c2_0"), "c2_0 unloaded")
	assert_true(await _load_ready(root, gate_at), "back at the gate: c2_0 reloaded")
	var gate := _gate(root)
	assert_true(gate != null, "a new gate")
	assert_eq(int(root.streamer.nav_maps.links_assigned), 8, "its links joined again")
	for link: NavigationLink3D in gate.nav_links():
		var layer := int(link.navigation_layers) & -int(link.navigation_layers)
		assert_eq(NavigationServer3D.link_get_map(link.get_rid()), root.nav_map(layer), "%s on its map" % link.name)
