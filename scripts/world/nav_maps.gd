class_name NavMaps
extends RefCounted
## The navigation maps of a streamed world level (P24b; plan M6-M9 §2.2, §2.8, decision 13;
## open_world_tech.md §5.2): one NavigationServer3D map per nav layer of the level's world block
## (human 1, large 2, titan 16), each with edge connections off, its cell size and height those of
## its navmeshes; the titan gate regions (bits 32 / 64 / 128) join the titan map. The ChunkStreamer
## owns one (ChunkStreamer.nav_maps): it adds a chunk's regions one a frame, puts the chunk's
## NavigationLink3Ds on their layer's map, and removes both when the chunk unloads.
##
## Readiness (ChunkStreamer.is_ready): a chunk is ready once every map it changed has an iteration
## id past the one it had at the chunk's last change (a region added, a link assigned). With
## `deterministic` (headless runs and tests) every map and every streamed region syncs with async
## iterations off, so a region added in one frame is in the map at the next physics step: the chunk
## is ready one tick later, every run. Interactive desktop play keeps the engine's asynchronous
## iterations (the project setting) for smoother frames; readiness then follows the worker thread.
##
## Regions are server RIDs (no nodes): a chunk's are freed when it unloads (remove_chunk) and every
## map and region when the level goes (free_all).

## The map a query on layer 0 uses (the human map).
const DEFAULT_LAYER := 1

## The level's nav layers (single bits, as the world block lists them).
var layers := PackedInt32Array()
## The gate bits whose regions join the titan map.
var gate_bits := PackedInt32Array()
## The layer gate regions join (titan).
var gate_layer := 16
var deterministic := false
## Counters (stats, tests).
var regions_added := 0
var regions_removed := 0
var links_assigned := 0

var _maps := {}       # layer bit -> map RID
var _cells := {}      # layer bit -> Vector2(cell size, cell height) once set from a navmesh
var _chunks := {}     # chunk id -> {"regions": [{"bit", "rid", "layer"}], "marks": {layer: iteration at its last change}}


## Makes one map per layer (`p_layers`: single bits; gate regions of `p_gate_bits` join
## `p_gate_layer`'s map). Safe to call once; free_all() undoes it.
func setup(p_layers: Array, p_gate_bits: Array, p_gate_layer := 16, p_deterministic := false) -> void:
	free_all()
	layers = PackedInt32Array()
	for b: Variant in p_layers:
		var bit := int(b)
		if bit > 0 and (bit & (bit - 1)) == 0 and not layers.has(bit):
			layers.append(bit)
	gate_bits = PackedInt32Array()
	for b: Variant in p_gate_bits:
		var bit := int(b)
		if bit > 0 and not gate_bits.has(bit):
			gate_bits.append(bit)
	gate_layer = p_gate_layer
	deterministic = p_deterministic
	for bit in layers:
		var m := NavigationServer3D.map_create()
		NavigationServer3D.map_set_up(m, Vector3.UP)
		NavigationServer3D.map_set_use_edge_connections(m, false)
		if deterministic:
			NavigationServer3D.map_set_use_async_iterations(m, false)
		NavigationServer3D.map_set_active(m, true)
		_maps[bit] = m


## True when the level has maps (a world block with nav layers).
func has_maps() -> bool:
	return not _maps.is_empty()


## The layer whose map holds bit `bit`: the bit itself for a level layer, the gate layer for a gate
## bit, DEFAULT_LAYER for 0; -1 for anything else.
func layer_of(bit: int) -> int:
	if bit == 0:
		return DEFAULT_LAYER if _maps.has(DEFAULT_LAYER) else (layers[0] if not layers.is_empty() else -1)
	if _maps.has(bit):
		return bit
	if gate_bits.has(bit) and _maps.has(gate_layer):
		return gate_layer
	return -1


## The map of layer (or gate bit) `bit`; 0 = the human map. Invalid for a layer the level lacks.
func map_for(bit: int) -> RID:
	var layer := layer_of(bit)
	return _maps.get(layer, RID()) if layer > 0 else RID()


## The map serving a query mask: the lowest of its bits the level has a map for (a titan mask with
## gate bits: the titan map). Invalid when none.
func map_for_mask(mask: int) -> RID:
	var bit := 1
	while bit <= mask and bit > 0:
		if (mask & bit) != 0:
			var m := map_for(bit)
			if m.is_valid():
				return m
		bit <<= 1
	return RID()


## Every map ({layer: RID}).
func maps() -> Dictionary:
	return _maps.duplicate()


## Turns deterministic syncing on for every map and every region added so far (and later ones);
## off leaves them as they are (the project setting decides for new ones).
func set_deterministic(on: bool) -> void:
	deterministic = on
	if not on:
		return
	for bit: int in _maps:
		NavigationServer3D.map_set_use_async_iterations(_maps[bit], false)
	for id: String in _chunks:
		for r: Dictionary in (_chunks[id] as Dictionary).regions:
			NavigationServer3D.region_set_use_async_iterations(r.rid, false)


## Adds the navmesh `nm` of chunk `chunk_id` as a region for bit `bit` (a layer, or a gate bit:
## the titan map) at `xform` (the chunk's origin). The map takes the navmesh's cell size and height
## before its first region. Returns the region (invalid when the level has no map for the bit).
func add_region(chunk_id: String, bit: int, nm: NavigationMesh, xform: Transform3D) -> RID:
	var layer := layer_of(bit)
	if layer <= 0 or nm == null:
		return RID()
	var m: RID = _maps[layer]
	var cells := Vector2(nm.cell_size, nm.cell_height)
	if _cells.get(layer, Vector2.ZERO) != cells:
		NavigationServer3D.map_set_cell_size(m, nm.cell_size)
		NavigationServer3D.map_set_cell_height(m, nm.cell_height)
		_cells[layer] = cells
	var rid := NavigationServer3D.region_create()
	if deterministic:
		NavigationServer3D.region_set_use_async_iterations(rid, false)
	NavigationServer3D.region_set_use_edge_connections(rid, false)
	NavigationServer3D.region_set_navigation_layers(rid, bit)
	NavigationServer3D.region_set_transform(rid, xform)
	NavigationServer3D.region_set_navigation_mesh(rid, nm)
	NavigationServer3D.region_set_map(rid, m)
	var entry := _entry(chunk_id)
	(entry.regions as Array).append({"bit": bit, "rid": rid, "layer": layer})
	_mark(entry, layer)
	regions_added += 1
	return rid


## Puts a chunk's NavigationLink3D on the map of its layer (the lowest of its layers the level has a
## map for: a Valley-style link on layers 1-8 joins the human map). False when there is none.
func assign_link(chunk_id: String, link: NavigationLink3D) -> bool:
	var mask := int(link.navigation_layers)
	var bit := 1
	while bit <= mask and bit > 0:
		if (mask & bit) != 0 and layer_of(bit) > 0:
			var layer := layer_of(bit)
			link.set_navigation_map(_maps[layer])
			_mark(_entry(chunk_id), layer)
			links_assigned += 1
			return true
		bit <<= 1
	return false


## Frees every region of a chunk (its unload). Returns how many.
func remove_chunk(chunk_id: String) -> int:
	var entry: Dictionary = _chunks.get(chunk_id, {})
	_chunks.erase(chunk_id)
	var n := 0
	for r: Dictionary in entry.get("regions", []):
		if (r.rid as RID).is_valid():
			NavigationServer3D.free_rid(r.rid)
			n += 1
	regions_removed += n
	return n


## Frees every chunk's regions (the maps stay).
func remove_all_chunks() -> void:
	for id: String in _chunks.keys():
		remove_chunk(id)
	_chunks.clear()


## True once every map the chunk changed has synced past its last change (a chunk without
## navigation is ready at once).
func chunk_ready(chunk_id: String) -> bool:
	var entry: Dictionary = _chunks.get(chunk_id, {})
	var marks: Dictionary = entry.get("marks", {})
	for layer: int in marks:
		var m: RID = _maps.get(layer, RID())
		if m.is_valid() and NavigationServer3D.map_get_iteration_id(m) <= int(marks[layer]):
			return false
	return true


## The regions of a chunk: [{"bit", "rid", "layer"}].
func chunk_regions(chunk_id: String) -> Array:
	var entry: Dictionary = _chunks.get(chunk_id, {})
	return (entry.get("regions", []) as Array).duplicate()


## How many regions each map holds now ({layer: n}; gate regions count on the titan map).
func region_counts() -> Dictionary:
	var out := {}
	for bit: int in _maps:
		out[bit] = 0
	for id: String in _chunks:
		for r: Dictionary in (_chunks[id] as Dictionary).regions:
			out[int(r.layer)] = int(out.get(int(r.layer), 0)) + 1
	return out


## The regions per bit ({bit: n}: gate regions apart from the titan layer's own).
func bit_counts() -> Dictionary:
	var out := {}
	for id: String in _chunks:
		for r: Dictionary in (_chunks[id] as Dictionary).regions:
			out[int(r.bit)] = int(out.get(int(r.bit), 0)) + 1
	return out


## Counters and region counts for stats().
func stats() -> Dictionary:
	return {"maps": _maps.size(), "regions": region_counts(), "regions_added": regions_added,
		"regions_removed": regions_removed, "links_assigned": links_assigned}


## Frees every region and every map (the level leaving; setup() again starts afresh).
func free_all() -> void:
	remove_all_chunks()
	for bit: int in _maps:
		var m: RID = _maps[bit]
		if m.is_valid():
			NavigationServer3D.free_rid(m)
	_maps.clear()
	_cells.clear()


func _entry(chunk_id: String) -> Dictionary:
	if not _chunks.has(chunk_id):
		_chunks[chunk_id] = {"regions": [], "marks": {}}
	return _chunks[chunk_id]


func _mark(entry: Dictionary, layer: int) -> void:
	var m: RID = _maps.get(layer, RID())
	if m.is_valid():
		(entry.marks as Dictionary)[layer] = NavigationServer3D.map_get_iteration_id(m)
