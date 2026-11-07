extends RefCounted
## Builder: the real world (P25; plan M6-M9 §3.8, §5; decisions 12-14): the 2 x 2 km Old Kingdom
## of tools/data/world/*.json as 8 x 8 streamed chunks of 256 m.
##
##   1. heights: tools/world/features.gd's recipe (base, regions, features, the rim, water, roads),
##      HeightField.relax_borders (no walkable face over 35 degrees within 8 m of a chunk border;
##      the build fails naming the place), quantised to 16 bits;
##   2. per chunk: its ChunkData (heights with the apron, 16 m surface and 64 m region cells, the
##      water rectangles), its scenery (MultiMesh buffers of the shared meshes: species per region by
##      Poisson disk, trunks 9 m apart in the Greywood so a stage-6 capsule slides through, saplings,
##      bushes, reeds and heather without collision), the static layout elements merged into one
##      vertex-coloured structures mesh (drawn as far as the terrain) with their solids, and the
##      scripted places (shrines, waystones, checkpoints, exits, size gates, seals, caches, cairns,
##      great pines, markers, areas, flag-shown elements) in props sub-scenes of at most 150 nodes;
##   3. navigation: NavBake per chunk and layer (human, large, titan; titan gate regions from
##      WorldFeatures.gate_at: the Wend's bed 32, the Mere's channel 64, the Giant's Stair and the
##      Moot's gate 128, their rectangles drawn in by GATE_GRAZE_M) with its own and its eight
##      neighbours' obstacles; size gates are never obstacles (the gate regions carry them); the
##      rim has none;
##   4. the skyline (the coarse terrain coloured by the regions' skyline tints, the merged
##      silhouettes of the skyline landmarks, the beacon columns), the world index
##      (tools/world/index_writer.gd), the map picture (tools/world/map_render.gd) and the root scene
##      scenes/world/world.tscn (M7 polish: with Markers/Route, the world walk's default route).
##
## --chunks=c2_6,c3_6 (after "--" on the command line; tools/check.sh --build-args=...) rebuilds those
## chunks and their eight neighbours (their navmeshes see each other's obstacles and share border
## heights) and writes only theirs; the skyline, the index, the map and the root scene are always
## written. The build is deterministic: a second build writes the same bytes.

const LEVEL_ID := "level.world"
const SCENE_PATH := "res://scenes/world/world.tscn"
const PART_DIR := "res://scenes/world/chunks/"
const CHUNK_DIR := "res://assets/world/chunks/"
const NAV_DIR := "res://assets/world/nav"
const SHARED_DIR := "res://assets/world/shared/"
const STRUCTURES_DIR := "res://assets/world/structures/"
const INDEX_PATH := "res://assets/world/index_world.res"
const MAP_PATH := "res://assets/world/map_world.png"
const SKYLINE_PATH := "res://assets/world/skyline.res"
const LANDMARKS_PATH := "res://assets/world/skyline_landmarks.res"
const VERTEX_MATERIAL := "res://assets/world/shared/mat_vertex.tres"

const S_WORLD := "res://scripts/world/world_root.gd"
const S_STREAMER := "res://scripts/world/chunk_streamer.gd"
const S_SKYLINE := "res://scripts/world/skyline.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const S_WAYSTONE := "res://scripts/world/waystone.gd"
const S_EXIT := "res://scripts/world/level_exit.gd"
const S_SIZE_GATE := "res://scripts/world/size_gate.gd"
const S_TRIGGER := "res://scripts/world/area_trigger.gd"
const S_FLAG := "res://scripts/world/flag_visibility.gd"
const GIANT := "res://scenes/player/giant.tscn"
const SHRINE := "res://scenes/world/shrine.tscn"
const PINE := "res://scenes/world/great_pine.tscn"
const SEALS := {"rockfall": "res://scenes/world/rockfall.tscn", "toppled_statue": "res://scenes/world/toppled_statue.tscn",
	"titan_tree": "res://scenes/world/titan_tree.tscn"}
## LevelMarker.Kind by name, and the Markers/<folder> each goes in.
const MARKER_KINDS := {"objective": [0, "Objective"], "cover": [1, "Cover"], "elevation": [2, "Elevation"],
	"formation": [3, "Formation"], "safe": [4, "Safe"], "patrol": [5, "Patrol"], "bot_route": [6, "BotRoute"]}
## Per-layer link half lengths through a seal (beyond its block and the layer's agent radius, onto
## each layer's navmesh; the titan's reaches 4 m into a vault behind its rockfall). After the bake
## snap_links moves each end on outward to its layer's navmesh, at most LINK_SEARCH_M.
const SEAL_LINK_HALF_M := {1: 5.0, 2: 6.5, 16: 12.0}
const LINK_SEARCH_M := 10.0
const ADDED_META := &"world_added"
## The map's marks of scripted places: section -> [radius (m), palette colour].
const MAP_MARKS := {"shrines": [7.0, "rune"], "waystones": [3.5, "stone_light"], "checkpoints": [3.5, "stone_light"],
	"cairns": [3.0, "stone_dark"], "secrets": [6.0, "stone_dark"], "pines": [9.0, "pine"]}
const SKY := Color(0.58, 0.66, 0.76)
## Scenery keeps this far from roads (beyond their half width) and from the rides.
const ROAD_CLEAR_M := 8.0
## The no-scenery and road grids' cell (metres).
const GRID_M := 8.0
## Carved roads must be at least this wide (quest routes; Brannock's gateways 16 m).
const MIN_ROAD_M := 12.0
## River size-gate walls: one box per piece of this length along each bank.
const GATE_PIECE_M := 16.0
## A size gate's rectangle gates the titan navmesh's polygons that reach more than this far into it
## (NavBake gates every polygon gate_at marks anywhere). Recast's long lowland triangles that only
## graze a rectangle's edge stay open - at the Giant's Stair's foot, slivers under 5 m deep had
## gated 3,700 m2 of open ground and the stair's cache with it - while every polygon of the gated
## ground itself (the stair's ramp, the Moot's gateway) reaches much deeper. A stage-4 path can end
## at most this far past a gate's line, behind its wall, and never cross it.
const GATE_GRAZE_M := 6.0
## A narrow size gate keeps at least this much of its rectangle across when drawn in, so it still
## gates the polygons through its middle.
const GATE_CORE_M := 4.0

static var _report: Dictionary = {}


static func build_all(kit: SceneKit) -> void:
	var report := build(kit, parse_args(OS.get_cmdline_user_args()))
	if not bool(report.get("ok", false)):
		push_error("world: %s" % report.get("message", "the build failed"))
		return
	print("world: %s" % JSON.stringify(report.get("summary", {})))


## {"chunks": PackedStringArray of the requested chunk ids} from --chunks=a,b.
static func parse_args(args: PackedStringArray) -> Dictionary:
	var chunks := PackedStringArray()
	for a in args:
		if a.begins_with("--chunks="):
			for c in a.trim_prefix("--chunks=").split(",", false):
				chunks.append(c.strip_edges())
	return {"chunks": chunks}


## The chunks a --chunks= list rebuilds: each named chunk and its eight neighbours (in the grid),
## sorted. Empty = every chunk.
static func expand_chunks(named: PackedStringArray, grid: Vector2i) -> PackedStringArray:
	var set := {}
	for id in named:
		var c := ChunkData.coords_for(id)
		if c.x < 0:
			continue
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var n := c + Vector2i(dx, dz)
				if n.x >= 0 and n.y >= 0 and n.x < grid.x and n.y < grid.y:
					set[ChunkData.id_for(n)] = true
	var out := PackedStringArray(set.keys())
	out.sort()
	return out


# --------------------------------------------------------------------------- the build

## Builds the world; {"ok", "message" (on failure), "summary"}.
static func build(kit: SceneKit, opts: Dictionary = {}) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var layout := WorldLayout.load_all()
	if not (layout.errors as PackedStringArray).is_empty():
		return {"ok": false, "message": "layout: " + "; ".join(layout.errors as PackedStringArray)}
	var feats := WorldFeatures.new(layout.world)
	_gate_rects(feats, layout)
	var field := feats.make_field()
	var soft := feats.soften_borders(field)
	var walk := func(x: float, z: float) -> bool: return feats.border_walkable(field, x, z)
	var relax := field.relax_borders(feats.field_first(), int(feats.chunk_m / feats.spacing), feats.grid,
		HeightField.BORDER_BAND_M, HeightField.BORDER_MAX_DEG, walk)
	if not bool(relax.ok):
		return {"ok": false, "message": str(relax.message)}
	field.quantise_all()
	var seam := field.border_report(feats.field_first(), int(feats.chunk_m / feats.spacing), feats.grid,
		HeightField.BORDER_BAND_M, HeightField.BORDER_MAX_DEG, walk)
	if int(seam.cells) > 0:
		return {"ok": false, "message": "a chunk border near (%.0f, %.0f) is %.1f degrees steep after quantising" % [
			float(seam.x), float(seam.z), float(seam.deg)]}
	var checks := layout_checks(layout, feats)
	if not checks.is_empty():
		return {"ok": false, "message": "; ".join(checks)}
	var named: PackedStringArray = opts.get("chunks", PackedStringArray())
	var selected := expand_chunks(named, feats.grid)
	var mat := _vertex_material(kit)
	var meshes := _shared_meshes(kit, mat)
	var water := feats.water_world(field)
	var ctx_base := {"field": field, "feats": feats, "mat": mat, "kit": kit}
	var grids := _grids(feats, field, layout, ctx_base)
	var summary := {"chunks": 0, "rebuilt": [], "trees": 0, "scenery": 0, "solids": 0, "parts": 0, "statics": 0,
		"relax_iterations": relax.iterations, "border_deg": snappedf(float(seam.deg), 0.01),
		"softened": {"moved": soft.moved, "pushed": soft.pushed, "nudged": soft.nudged},
		"road_grade_max": feats.report.get("road_grade_max", {}), "water_rects": water.size(), "chunk_bytes": {},
		"nav_bytes": {}, "nav_polygons": {}, "structure_triangles": 0}
	# 1. every chunk's content in memory
	var chunks := {}   # coords -> {"data": ChunkData, "parts": [Node3D], "shapes": [obstacle], "struct": mesh path}
	var statics: Array = []
	var placed := _place_items(kit, layout, feats, field, mat, ctx_base, statics)
	var tree_hash := {}
	for cz in feats.grid.y:
		for cx in feats.grid.x:
			var c := Vector2i(cx, cz)
			var d := ChunkWriter.chunk_from_field(field, c, feats.chunk_m, Vector3(feats.origin.x, 0.0, feats.origin.y),
				feats.field_first())
			d.surface_cells = ChunkWriter.cells(d, ChunkData.SURFACE_CELLS, func(x: float, z: float) -> int:
				return _surface(feats, field, grids, x, z))
			d.region_cells = ChunkWriter.cells(d, ChunkData.REGION_CELLS, func(x: float, z: float) -> int:
				return feats.region_index(x, z))
			for w: Dictionary in water:
				var local := (w.rect as Rect2).intersection(Rect2(d.origin.x, d.origin.z, feats.chunk_m, feats.chunk_m))
				if local.size.x > 0.0 and local.size.y > 0.0:
					ChunkWriter.add_water(d.water, Rect2(local.position - Vector2(d.origin.x, d.origin.z), local.size),
						float(w.surface_y))
			var counts := _scenery(d, feats, field, layout, meshes, grids, tree_hash)
			summary.trees = int(summary.trees) + int(counts.trees)
			summary.scenery = int(summary.scenery) + int(counts.all)
			var struct_info := _structures(kit, d, placed.statics_by_chunk.get(d.chunk_id, []), mat, ctx_base)
			summary.structure_triangles = int(summary.structure_triangles) + int(struct_info.triangles)
			var shapes: Array = []
			var parts := _parts(kit, d, placed.props_by_chunk.get(d.chunk_id, []), shapes)
			if not bool(parts.ok):
				return {"ok": false, "message": str(parts.message)}
			shapes.append_array(NavBake.chunk_obstacles(d))
			chunks[c] = {"data": d, "roots": parts.roots, "shapes": shapes}
			summary.chunks = int(summary.chunks) + 1
			summary.solids = int(summary.solids) + d.solids.size() / ChunkData.SOLID_STRIDE
			summary.parts = int(summary.parts) + (parts.roots as Array).size()
	summary.statics = statics.size()
	# 2. the index, from every part placed at its chunk's origin
	var temp := Node3D.new()
	temp.name = "IndexScan"
	for c: Vector2i in chunks:
		var holder := Node3D.new()
		holder.name = ChunkData.id_for(c)
		holder.position = (chunks[c].data as ChunkData).origin
		for r: Node3D in chunks[c].roots:
			holder.add_child(r)
		temp.add_child(holder)
	var idx := WorldIndexWriter.build(temp, layout, feats, field, statics, MAP_PATH)
	for holder in temp.get_children():
		for r in holder.get_children():
			holder.remove_child(r)
	temp.free()
	# 3. navigation, chunk files and part scenes (the selected chunks)
	for c: Vector2i in chunks:
		var d: ChunkData = chunks[c].data
		var keep := selected.is_empty() or selected.has(d.chunk_id)
		if not keep:
			for r: Node in chunks[c].roots:
				r.free()
			continue
		(summary.rebuilt as Array).append(d.chunk_id)
		var near: Array = []
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				if chunks.has(c + Vector2i(dx, dz)):
					near.append_array(chunks[c + Vector2i(dx, dz)].shapes)
		var nms := NavBake.bake_chunk(field, d.origin, feats.chunk_m, near, water, feats.gate_at,
			func(x: float, z: float) -> bool: return feats.walkable(x, z))
		d.nav = NavBake.save_chunk(nms, NAV_DIR, d.chunk_id, kit.output_path)
		snap_links(chunks[c].roots, nms)
		var nbytes := 0
		var polys := {}
		for bit: int in d.nav:
			nbytes += FileAccess.get_file_as_bytes(kit.output_path(str(d.nav[bit]))).size()
		for bit: int in nms:
			polys[bit] = (nms[bit] as NavigationMesh).get_polygon_count()
		(summary.nav_bytes as Dictionary)[d.chunk_id] = nbytes
		(summary.nav_polygons as Dictionary)[d.chunk_id] = polys
		var roots: Array = chunks[c].roots
		for i in roots.size():
			var root: Node3D = roots[i]
			for n in root.find_children("*", "", true, false):
				if n.has_meta(ADDED_META):
					n.remove_meta(ADDED_META)
					n.owner = root
			var path := ChunkWriter.part_path(PART_DIR, d.coords, i)
			if kit.save(root, path) == "":
				return {"ok": false, "message": "could not save %s" % path}
			d.props_scenes.append(path)
		var cpath := kit.output_path(CHUNK_DIR + d.chunk_id + ".res")
		var err := ChunkWriter.save(d, cpath)
		if err != OK:
			return {"ok": false, "message": "could not save %s (error %d)" % [cpath, err]}
		(summary.chunk_bytes as Dictionary)[d.chunk_id] = FileAccess.get_file_as_bytes(cpath).size()
	# 4. the skyline, the map, the index, the root scene
	_save_skyline(kit, feats, field, layout, ctx_base, statics)
	var map := WorldMapRender.render(feats, field, _map_tints(feats), placed.footprints)
	var mpath := kit.output_path(MAP_PATH)
	if WorldMapRender.save(map, mpath) != OK:
		return {"ok": false, "message": "could not save %s" % mpath}
	summary["map_bytes"] = FileAccess.get_file_as_bytes(mpath).size()
	var ipath := kit.output_path(INDEX_PATH)
	DirAccess.make_dir_recursive_absolute(ipath.get_base_dir())
	var ierr := ResourceSaver.save(idx, ipath)
	if ierr != OK:
		return {"ok": false, "message": "could not save %s (error %d)" % [ipath, ierr]}
	summary["index"] = {"checkpoints": idx.checkpoints.size(), "pois": idx.pois.size(), "props": idx.props.size(),
		"markers": idx.markers.size(), "exits": idx.exits.size(), "encounters": idx.encounters.size(),
		"road_nodes": idx.road_nodes().size(), "road_edges": idx.road_edges().size() / 2,
		"bytes": FileAccess.get_file_as_bytes(ipath).size()}
	var root := build_root(kit, feats, field, layout)
	kit.save(root, SCENE_PATH)
	summary["seconds"] = snappedf((Time.get_ticks_msec() - t0) / 1000.0, 0.1)
	_report = summary
	return {"ok": true, "summary": summary}


## The last build's summary (tests, tools).
static func last_report() -> Dictionary:
	return _report


# --------------------------------------------------------------------------- checks

## The layout's own rules: carved roads at least MIN_ROAD_M wide; every gap in a wall or palisade
## a quest route passes is at least 16 m; every element, place and item inside the world; (M7
## polish) the walk route's points on walkable ground inside it.
static func layout_checks(layout: Dictionary, feats: WorldFeatures) -> PackedStringArray:
	var out := PackedStringArray()
	var walk: Variant = (layout.world.get("walk_route", {}) as Dictionary).get("points", [])
	if typeof(walk) == TYPE_ARRAY:
		for w: Variant in walk:
			var wp := WorldFeatures.v2(w)
			if not feats.walkable(wp.x, wp.y):
				out.append("walk_route point %s is not on walkable ground" % wp)
	for road: Dictionary in feats.roads:
		if bool(road.carve) and float(road.width) < MIN_ROAD_M:
			out.append("road %s is %.0f m wide (at least %.0f)" % [road.id, road.width, MIN_ROAD_M])
	var world := feats.world_rect()
	for it: Dictionary in layout.items:
		if not it.has("pos"):
			continue
		var p := WorldLayout.pos2(it)
		if not world.has_point(p):
			out.append("%s at %s is outside the world" % [it.get("id", it._section), p])
		for g: Array in it.get("gaps", []):
			if float(g[2]) < 16.0:
				out.append("%s: a gateway of %.0f m (at least 16 m)" % [it.get("id", ""), float(g[2])])
	return out


## The size gates' titan gate rectangles (the Giant's Stair, the Moot's gate) into the features,
## each drawn in by GATE_GRAZE_M (keeping GATE_CORE_M of a narrow one).
static func _gate_rects(feats: WorldFeatures, layout: Dictionary) -> void:
	feats.gate_rects.clear()
	for it: Dictionary in layout.items:
		if str(it._section) != "size_gates" or not it.has("gate_rect"):
			continue
		var bit := {4: 32, 5: 64, 6: 128}.get(int(it.min_stage), 128) as int
		feats.gate_rects.append({"rect": drawn_in(WorldFeatures.rect_of(it.gate_rect)), "bit": bit, "id": str(it.id)})


## A size gate's rectangle drawn in by GATE_GRAZE_M on every side, keeping at least GATE_CORE_M
## across in each direction.
static func drawn_in(r: Rect2) -> Rect2:
	var gx := clampf((r.size.x - GATE_CORE_M) * 0.5, 0.0, GATE_GRAZE_M)
	var gz := clampf((r.size.y - GATE_CORE_M) * 0.5, 0.0, GATE_GRAZE_M)
	return r.grow_individual(-gx, -gz, -gx, -gz)


# --------------------------------------------------------------------------- shared meshes

static func _vertex_material(kit: SceneKit) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.95
	DirAccess.make_dir_recursive_absolute(kit.output_path(SHARED_DIR))
	ResourceSaver.save(m, kit.output_path(VERTEX_MATERIAL), ResourceSaver.FLAG_CHANGE_PATH)
	m.take_over_path(VERTEX_MATERIAL)
	return m


## The scenery meshes (one vertex-coloured surface each, the one material): their res:// paths.
static func _shared_meshes(kit: SceneKit, mat: Material) -> Dictionary:
	var L := WorldLayout
	var specs := {
		"tree_broadleaf": [L.part("cyl", Vector3.ZERO, Vector3(1.1, 6.0, 0), "bark"),
			L.part("sphere", Vector3(0, 4.6, 0), Vector3(8.0, 7.0, 8.0), "leaves"),
			L.part("sphere", Vector3(1.4, 6.4, 0.8), Vector3(5.0, 4.5, 5.0), "leaves")],
		"tree_pine": [L.part("cyl", Vector3.ZERO, Vector3(1.0, 9.0, 0), "bark"),
			L.part("cone", Vector3(0, 4.0, 0), Vector3(7.0, 7.0, 0), "pine"),
			L.part("cone", Vector3(0, 8.0, 0), Vector3(5.6, 6.5, 0), "pine"),
			L.part("cone", Vector3(0, 12.0, 0), Vector3(3.8, 6.0, 0), "pine")],
		"sapling": [L.part("cone", Vector3.ZERO, Vector3(1.6, 3.2, 0), "pine")],
		"bush": [L.part("sphere", Vector3(0, -0.4, 0), Vector3(3.2, 2.2, 2.8), "leaves")],
		"rock": [L.part("frustum", Vector3(0, -0.5, 0), Vector3(1.0, 1.0, 0.6), "rock")],
		"reed": [L.part("cone", Vector3(-0.4, 0, 0), Vector3(0.4, 2.2, 0), "reed"),
			L.part("cone", Vector3(0.3, 0, 0.2), Vector3(0.4, 2.6, 0), "reed"),
			L.part("cone", Vector3(0, 0, -0.4), Vector3(0.4, 1.9, 0), "reed")],
		"heather": [L.part("sphere", Vector3(0, -0.3, 0), Vector3(2.4, 1.0, 2.0), "heather")],
		"log": [L.part("cyl", Vector3(0, 0.5, 0), Vector3(1.0, 8.0, 0), "bark", 0.0, Vector3(0, 0, 90))],
	}
	var out := {}
	DirAccess.make_dir_recursive_absolute(kit.output_path(SHARED_DIR))
	for key: String in specs:
		var mesh := L.parts_mesh(specs[key], Transform3D.IDENTITY, mat)
		var path := SHARED_DIR + key + ".res"
		ResourceSaver.save(mesh, kit.output_path(path), ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
		out[key] = path
	return out


# --------------------------------------------------------------------------- grids (roads, no-scenery)

## The road and no-scenery grids (GRID_M cells over the world): "road" (1 on a carved road), "clear"
## (1 where no scenery stands: roads and rides with ROAD_CLEAR_M, pads, structures, places, water,
## the rim).
static func _grids(feats: WorldFeatures, field: HeightField, layout: Dictionary, ctx_base: Dictionary) -> Dictionary:
	var world := feats.world_rect()
	var n := Vector2i(int(world.size.x / GRID_M), int(world.size.y / GRID_M))
	var road := PackedByteArray()
	road.resize(n.x * n.y)
	var clear := PackedByteArray()
	clear.resize(n.x * n.y)
	var g := {"n": n, "origin": world.position, "road": road, "clear": clear}
	for r: Dictionary in feats.roads:
		var half := float(r.width) * 0.5
		_mark_polyline(g, "clear", r.points, half + ROAD_CLEAR_M)
		if bool(r.carve):
			_mark_polyline(g, "road", r.points, half)
	for pad: Dictionary in feats.pads:
		if pad.has("circle"):
			var c: Array = pad.circle
			_mark_circle(g, "clear", Vector2(float(c[0]), float(c[1])), float(c[2]) + 6.0)
		else:
			_mark_rect(g, "clear", WorldFeatures.rect_of(pad.rect).grow(6.0))
	for it: Dictionary in layout.items:
		if not it.has("pos"):
			continue
		var p := WorldLayout.pos2(it)
		var r := 12.0
		match str(it._section):
			"elements":
				var ctx := ctx_base.duplicate()
				ctx["frame"] = WorldLayout.frame(it, ctx)
				r = WorldLayout.clearance(it, WorldLayout.kind_parts(it, ctx), 8.0)
				if it.has("points"):
					for pt in WorldLayout.points_of(it):
						_mark_circle(g, "clear", pt, 10.0)
					var pts := WorldLayout.points_of(it)
					_mark_polyline(g, "clear", pts, float(it.get("thick", 2.0)) + 8.0)
					continue
			"shrines":
				r = 22.0
			"pines":
				r = 14.0
			"secrets":
				r = 16.0
			"markers", "areas":
				r = 4.0
		_mark_circle(g, "clear", p, r)
	# water, the rim and steep ground
	for j in n.y:
		for i in n.x:
			var x := world.position.x + (i + 0.5) * GRID_M
			var z := world.position.y + (j + 0.5) * GRID_M
			if not feats.walkable(x, z) or not is_nan(feats.water_surface_at(field, x, z)):
				clear[j * n.x + i] = 1
	return g


static func _cell_of(g: Dictionary, p: Vector2) -> Vector2i:
	var o: Vector2 = g.origin
	return Vector2i(int(floor((p.x - o.x) / GRID_M)), int(floor((p.y - o.y) / GRID_M)))


static func _set_cell(g: Dictionary, key: String, c: Vector2i) -> void:
	var n: Vector2i = g.n
	if c.x >= 0 and c.y >= 0 and c.x < n.x and c.y < n.y:
		(g[key] as PackedByteArray)[c.y * n.x + c.x] = 1


static func cell_set(g: Dictionary, key: String, p: Vector2) -> bool:
	var n: Vector2i = g.n
	var c := _cell_of(g, p)
	if c.x < 0 or c.y < 0 or c.x >= n.x or c.y >= n.y:
		return true
	return (g[key] as PackedByteArray)[c.y * n.x + c.x] != 0


static func _mark_circle(g: Dictionary, key: String, c: Vector2, r: float) -> void:
	var lo := _cell_of(g, c - Vector2(r, r))
	var hi := _cell_of(g, c + Vector2(r, r))
	var o: Vector2 = g.origin
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			var cc := o + Vector2((i + 0.5) * GRID_M, (j + 0.5) * GRID_M)
			if cc.distance_to(c) <= r + GRID_M * 0.5:
				_set_cell(g, key, Vector2i(i, j))


static func _mark_rect(g: Dictionary, key: String, r: Rect2) -> void:
	var lo := _cell_of(g, r.position)
	var hi := _cell_of(g, r.end)
	for j in range(lo.y, hi.y + 1):
		for i in range(lo.x, hi.x + 1):
			_set_cell(g, key, Vector2i(i, j))


static func _mark_polyline(g: Dictionary, key: String, pts: PackedVector2Array, half: float) -> void:
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var steps := maxi(1, int(ceil(a.distance_to(b) / (GRID_M * 0.5))))
		for s in steps + 1:
			_mark_circle(g, key, a.lerp(b, float(s) / steps), half)


## The surface id of the 16 m cell at (x, z): wet by water, hard on roads, pads, steep ground and
## the rim, else the region's.
static func _surface(feats: WorldFeatures, field: HeightField, grids: Dictionary, x: float, z: float) -> int:
	if not is_nan(feats.water_surface_at(field, x, z)):
		return ChunkData.SURFACE_WET
	if not feats.walkable(x, z) or cell_set(grids, "road", Vector2(x, z)):
		return ChunkData.SURFACE_HARD
	if WorldFeatures.slope_deg(field, x, z) > WorldFeatures.HARD_SLOPE_DEG:
		return ChunkData.SURFACE_HARD
	var k := feats.region_index(x, z)
	var surf := str(feats.regions[k - 1].surface) if k > 0 else "soft"
	return int(WorldFeatures.SURFACE_IDS.get(surf, 0))


# --------------------------------------------------------------------------- scenery

## Scenery of one chunk by its regions' rules: trees (with trunk solids) by Poisson disk across
## chunk borders (`tree_hash`: 16 m cells -> [Vector3(x, z, min spacing)]), the rest by their own
## spacing; nothing on the no-scenery grid or steeper than 28 degrees; reeds only near water.
static func _scenery(d: ChunkData, feats: WorldFeatures, field: HeightField, layout: Dictionary, meshes: Dictionary,
		grids: Dictionary, tree_hash: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(feats.spec.frame.get("seed", 2516)) * 7919 + d.coords.x * 104729 + d.coords.y * 1299709
	var by_mesh := {}   # mesh key -> [Transform3D]
	var trees := 0
	var all := 0
	var area := feats.chunk_m * feats.chunk_m
	for region_short: String in WorldLayout.REGION_FILES:
		var table: Dictionary = layout.regions.get(region_short, {})
		var rid := str(table.get("region", ""))
		var rk := feats.region_ids.find(rid) + 1
		for rule: Dictionary in table.get("scenery", []):
			var key := str(rule.mesh)
			if not meshes.has(key):
				continue
			var target := int(float(rule.density) * area)
			var spacing := float(rule.get("spacing_m", 8.0))
			var solid := bool(rule.get("solid", false))
			var scale: Array = rule.get("scale", [1.0, 1.0])
			var near_water := float(rule.get("near_water_m", 0.0))
			var own := {}
			var placed := 0
			for attempt in target * 5:
				if placed >= target:
					break
				var lx := rng.randf_range(1.0, feats.chunk_m - 1.0)
				var lz := rng.randf_range(1.0, feats.chunk_m - 1.0)
				var x := d.origin.x + lx
				var z := d.origin.z + lz
				var sc := rng.randf_range(float(scale[0]), float(scale[1]))
				var yaw := rng.randf_range(-PI, PI)
				if feats.region_index(x, z) != rk:
					continue
				var p := Vector2(x, z)
				if near_water > 0.0:
					if not _near_water(feats, field, p, near_water) or not is_nan(feats.water_surface_at(field, x, z)) \
							and feats.water_surface_at(field, x, z) - field.sample(x, z) > 0.6:
						continue
				elif cell_set(grids, "clear", p):
					continue
				if WorldFeatures.slope_deg(field, x, z) > 28.0:
					continue
				var hash := tree_hash if solid else own
				if not _spaced(hash, p, spacing):
					continue
				var hc := Vector2i(int(floor(x / 16.0)), int(floor(z / 16.0)))
				if not hash.has(hc):
					hash[hc] = []
				(hash[hc] as Array).append(Vector3(x, z, spacing))
				var y := field.sample(x, z)
				if not by_mesh.has(key):
					by_mesh[key] = []
				var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sc, sc * rng.randf_range(0.9, 1.15), sc))
				if key == "rock":
					basis = Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(sc * 3.2, sc * rng.randf_range(1.4, 2.6), sc * 2.6))
				(by_mesh[key] as Array).append(Transform3D(basis, Vector3(lx, y - 0.3, lz)))
				placed += 1
				all += 1
				if solid:
					var bs := basis.get_scale()
					if key == "rock":
						ChunkWriter.add_solid(d.solids, false, Vector3(lx, y - 0.3 + bs.y * 0.5, lz), Vector3(bs.x * 0.8, bs.y, bs.z * 0.8), yaw)
					else:
						# trunks: a fixed 1.0 m (pine) / 1.2 m (broadleaf) solid, so trees 9 m apart leave
						# a stage-6 capsule (7.4 m) room to pass
						var trunk_d := 1.0 if key == "tree_pine" else 1.2
						var th := 9.0 if key == "tree_pine" else 6.0
						ChunkWriter.add_solid(d.solids, true, Vector3(lx, y - 0.3 + th * bs.y * 0.5, lz), Vector3(trunk_d, th * bs.y, 0.0))
						trees += 1
	var keys := by_mesh.keys()
	keys.sort()
	for key: String in keys:
		d.scenery[meshes[key]] = ChunkWriter.xform_buffer(by_mesh[key])
	return {"trees": trees, "all": all}


static func _spaced(hash: Dictionary, p: Vector2, spacing: float) -> bool:
	var c := Vector2i(int(floor(p.x / 16.0)), int(floor(p.y / 16.0)))
	var reach := int(ceil(spacing / 16.0))
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for q: Vector3 in hash.get(c + Vector2i(dx, dz), []):
				if Vector2(q.x, q.y).distance_to(p) < maxf(spacing, q.z):
					return false
	return true


static func _near_water(feats: WorldFeatures, field: HeightField, p: Vector2, within: float) -> bool:
	for k in 8:
		var a := TAU * k / 8.0
		var q := p + Vector2(cos(a), sin(a)) * within
		if not is_nan(feats.water_surface_at(field, q.x, q.y)):
			return true
	return not is_nan(feats.water_surface_at(field, p.x, p.y))


# --------------------------------------------------------------------------- placing the layout

## Sorts the layout's items: static elements (parts merged into their chunk's structures mesh,
## solids into its solids) by chunk, scripted places (nodes for the props parts) by chunk, the
## map's footprints, and `statics` (the static elements with ids, for the index).
static func _place_items(kit: SceneKit, layout: Dictionary, feats: WorldFeatures, field: HeightField, mat: Material,
		ctx_base: Dictionary, statics: Array) -> Dictionary:
	var statics_by_chunk := {}
	var props_by_chunk := {}
	var footprints: Array = []
	for it: Dictionary in layout.items:
		var section := str(it._section)
		if section == "elements" and it.has("points") and not it.has("pos"):
			it["pos"] = it.points[0]
		if section in ["greens", "signs"]:
			continue
		if section == "size_gates":
			for g: Dictionary in _size_gate_nodes(kit, it, feats, field):
				_add_prop(props_by_chunk, feats, g.at, g.node, "SizeGates")
			continue
		var ctx := ctx_base.duplicate()
		ctx["frame"] = WorldLayout.frame(it, ctx)
		var xf: Transform3D = ctx.frame
		var p := WorldLayout.pos2(it)
		var chunk := feats.chunk_id_of(p.x, p.y)
		if section == "elements":
			var kind := str(it.kind)
			var flagged := str(it.get("visible_when_flag", "")) != "" or str(it.get("hidden_when_flag", "")) != ""
			if WorldLayout.is_scripted(kind) or flagged:
				var node: Node3D = _flag_node(kit, it, ctx) if flagged else WorldLayout.kind_build(kit, it, ctx)
				if node != null:
					_place(node, xf)
					_add_prop(props_by_chunk, feats, p, node, "Props")
			else:
				if not statics_by_chunk.has(chunk):
					statics_by_chunk[chunk] = []
				(statics_by_chunk[chunk] as Array).append({"el": it, "frame": xf})
				if str(it.get("id", "")) != "":
					statics.append({"el": it, "position": xf.origin})
			if not flagged:
				footprints.append_array(WorldLayout.plan_footprints(WorldLayout.kind_parts(it, ctx), xf))
			continue
		var built: Array = _place_node(kit, it, section, ctx)
		if built.is_empty():
			continue
		if MAP_MARKS.has(section):
			var mark: Array = MAP_MARKS[section]
			footprints.append({"circle": Vector3(p.x, p.y, float(mark[0])), "color": WorldLayout.color_of(mark[1])})
		var node: Node3D = built[0]
		_add_prop(props_by_chunk, feats, p, node, str(built[1]))
		if section == "pines" and str(it.get("id", "")) != "":
			statics.append({"el": it, "position": xf.origin})
	# low parts first (fields, floors), roofs and the places' marks over them
	footprints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("top", 99.0)) < float(b.get("top", 99.0)))
	return {"statics_by_chunk": statics_by_chunk, "props_by_chunk": props_by_chunk, "footprints": footprints}


static func _place(node: Node3D, xf: Transform3D) -> void:
	node.transform = xf


static func _add_prop(by_chunk: Dictionary, feats: WorldFeatures, p: Vector2, node: Node3D, container: String) -> void:
	var chunk := feats.chunk_id_of(p.x, p.y)
	if chunk == "":
		node.free()
		return
	if not by_chunk.has(chunk):
		by_chunk[chunk] = []
	(by_chunk[chunk] as Array).append({"node": node, "container": container})


## The node of a scripted place and its container: [node, container] ([] when it cannot be made).
static func _place_node(kit: SceneKit, it: Dictionary, section: String, ctx: Dictionary) -> Array:
	var xf: Transform3D = ctx.frame
	var id := str(it.get("id", ""))
	match section:
		"shrines":
			var sh := kit.instance(SHRINE) as Node3D
			if sh == null:
				return []
			sh.name = id.validate_node_name()
			sh.set("world_id", id)
			sh.set("shrine_id", str(it.record))
			sh.transform = xf
			return [sh, "Shrines"]
		"waystones":
			return [_waystone(it, xf, ctx.mat), "Waystones"]
		"checkpoints":
			var cp := Marker3D.new()
			cp.name = id.validate_node_name()
			kit.scripted(cp, S_CHECKPOINT, {"checkpoint_id": id})
			cp.transform = xf.translated_local(Vector3.UP * 0.3)
			return [cp, "Waystones"]
		"exits":
			var e := kit.scripted(kit.n3(id.validate_node_name()), S_EXIT, {
				"exit_id": id, "interact_id": id, "to_level": str(it.to_level), "to_checkpoint": str(it.to_checkpoint),
				"requires_flags": PackedStringArray(it.get("requires_flags", [])),
				"locked_message": str(it.get("locked_message", "The way is shut.")), "display_name": str(it.get("display_name", "")),
				"prompt": str(it.get("prompt", "Step through")), "radius_m": float(it.get("radius", 6.0)), "priority": 40}) as Node3D
			e.transform = xf
			return [e, "Exits"]
		"secrets":
			if str(it.seal) == "ledge":
				var ledge := {"kind": "cache", "style": "ledge"}
				ledge.merge(it)
				var n := WorldLayout.kind_build(kit, ledge, ctx)
				n.transform = xf
				return [n, "Props"]
			var scene := str(SEALS.get(str(it.seal), ""))
			var s := kit.instance(scene) as Node3D if scene != "" else null
			if s == null:
				return []
			s.name = id.validate_node_name()
			s.set("world_id", id)
			add_layer_links(s, SEAL_LINK_HALF_M)
			s.transform = xf
			ground_links(s, ctx.field)
			return [s, "Props"]
		"caches":
			var cache := {"kind": "cache", "style": "crate"}
			cache.merge(it)
			var c := WorldLayout.kind_build(kit, cache, ctx)
			if c == null:
				return []
			c.transform = xf
			return [c, "Props"]
		"cairns":
			var cairn := {"kind": "cairn"}
			cairn.merge(it)
			var n := WorldLayout.kind_build(kit, cairn, ctx)
			n.transform = xf
			return [n, "Props"]
		"pines":
			var pine := kit.instance(PINE) as Node3D
			if pine == null:
				return []
			pine.name = id.validate_node_name()
			pine.transform = xf.translated_local(Vector3.DOWN * 0.5)
			return [pine, "Landmarks"]
		"markers":
			var kind: Array = MARKER_KINDS.get(str(it.get("kind", "objective")), MARKER_KINDS.objective)
			var m := kit.scripted(kit.marker(id.validate_node_name()), S_MARKER, {"marker_id": id, "kind": int(kind[0]),
				"faction": str(it.get("faction", ""))}) as Node3D
			m.transform = xf.translated_local(Vector3.UP * 0.2)
			return [m, "Markers/" + str(kind[1])]
		"areas":
			var a := Area3D.new()
			a.name = id.validate_node_name()
			kit.scripted(a, S_TRIGGER, {"area_id": id, "once": bool(it.get("once", false))})
			a.collision_layer = 0
			a.collision_mask = SceneKit.L_ACTORS
			a.monitoring = true
			a.monitorable = false
			var cs := CollisionShape3D.new()
			cs.name = "Shape"
			var cyl := CylinderShape3D.new()
			cyl.radius = float(it.get("r", 20.0))
			cyl.height = float(it.get("h", 20.0))
			cs.shape = cyl
			cs.position = Vector3(0, cyl.height * 0.5 - 4.0, 0)
			a.add_child(cs)
			a.transform = xf
			return [a, "Triggers"]
	return []


## One closed NavigationLink3D per world nav layer through a prop (along its local z), added under
## an instanced scene (the part owns it when it is saved), opened when the prop breaks.
static func add_layer_links(prop: Node3D, halves: Dictionary) -> void:
	for spec: Dictionary in NavBake.LAYERS:
		var layer := int(spec.layer)
		var half := float(halves.get(layer, 5.0))
		var link := NavigationLink3D.new()
		link.name = "NavLink" + str(spec.name).capitalize()
		link.start_position = Vector3(0.0, float(spec.above_m) + 0.2, half)
		link.end_position = Vector3(0.0, float(spec.above_m) + 0.2, -half)
		link.bidirectional = true
		link.navigation_layers = layer
		link.enabled = false
		link.set_meta(ADDED_META, true)
		prop.add_child(link)


## Puts the ends of a chunk's nav links (its props parts' NavigationLink3Ds: seals, gates) on their
## layer's baked navmesh (a titan link: the titan mesh or a gate region's): each end moves outward
## along the link until it stands over one of the layer's polygons (at most LINK_SEARCH_M), else back
## toward the prop, and takes its height, so the link meets the mesh beyond the prop's eroded margin
## (a rockfall on a barrow's flank, a vault's door over the Mere's deep channel).
static func snap_links(roots: Array, nms: Dictionary) -> void:
	var cache := {}   # layer -> [polygons as [PackedVector2Array, PackedVector3Array, Rect2]]
	for root: Node3D in roots:
		for link: NavigationLink3D in root.find_children("*", "NavigationLink3D", true, false):
			var layer := int(link.navigation_layers)
			if not nms.has(layer):
				continue
			if not cache.has(layer):
				# the titan map holds the gate regions too: a titan link's end may stand on one
				var polys := _mesh_polygons(nms[layer])
				if layer == NavBake.TITAN_LAYER:
					for bit: int in nms:
						if bit > NavBake.TITAN_LAYER:
							polys.append_array(_mesh_polygons(nms[bit]))
				cache[layer] = polys
			var xf := _relative(root, link)
			var a := xf * link.start_position
			var b := xf * link.end_position
			var mid := (a + b) * 0.5
			var half := a.distance_to(b) * 0.5
			for end: String in ["start_position", "end_position"]:
				var p := xf * (link.get(end) as Vector3)
				var dir := Vector3(p.x - mid.x, 0.0, p.z - mid.z).normalized()
				# outward first, then back toward the prop (no nearer than a third of the way in)
				var hit := _over_mesh(cache[layer], p, dir, LINK_SEARCH_M)
				if hit == Vector3.INF:
					hit = _over_mesh(cache[layer], p, -dir, half * 0.66)
				if hit != Vector3.INF:
					link.set(end, xf.affine_inverse() * hit)


## A navmesh's polygons: [[outline (x, z), vertices, bounds (x, z)]].
static func _mesh_polygons(nm: NavigationMesh) -> Array:
	var verts := nm.get_vertices()
	var out: Array = []
	for i in nm.get_polygon_count():
		var outline := PackedVector2Array()
		var v3 := PackedVector3Array()
		for k in nm.get_polygon(i):
			outline.append(Vector2(verts[k].x, verts[k].z))
			v3.append(verts[k])
		var r := Rect2(outline[0], Vector2.ZERO)
		for q in outline:
			r = r.expand(q)
		out.append([outline, v3, r])
	return out


## The first point at or beyond p along dir (up to max_m, 0.5 m steps) over a polygon, on its
## surface (Vector3.INF when none).
static func _over_mesh(polys: Array, p: Vector3, dir: Vector3, max_m: float) -> Vector3:
	var s := 0.0
	while s <= max_m:
		var q := Vector2(p.x + dir.x * s, p.z + dir.z * s)
		for poly: Array in polys:
			if not (poly[2] as Rect2).grow(0.01).has_point(q) or not Geometry2D.is_point_in_polygon(q, poly[0]):
				continue
			var v: PackedVector3Array = poly[1]
			for k in range(1, v.size() - 1):
				var t0 := Vector2(v[0].x, v[0].z)
				var t1 := Vector2(v[k].x, v[k].z)
				var t2 := Vector2(v[k + 1].x, v[k + 1].z)
				if Geometry2D.point_is_inside_triangle(q, t0, t1, t2):
					var w := _barycentric(q, t0, t1, t2)
					return Vector3(q.x, v[0].y * w.x + v[k].y * w.y + v[k + 1].y * w.z, q.y)
			return Vector3(q.x, v[0].y, q.y)
		s += 0.5
	return Vector3.INF


static func _barycentric(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var den := v0.x * v1.y - v1.x * v0.y
	if absf(den) < 1e-9:
		return Vector3(1, 0, 0)
	var v := (v2.x * v1.y - v1.x * v2.y) / den
	var w := (v0.x * v2.y - v2.x * v0.y) / den
	return Vector3(1.0 - v - w, v, w)


## A node's transform relative to an ancestor.
static func _relative(ancestor: Node, node: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != ancestor:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf


## Puts the ends of a placed prop's links on the ground under them (the seal stands on one level,
## a vault's floor or the shore beyond it may lie lower or higher), at each layer's height above it.
static func ground_links(prop: Node3D, field: HeightField) -> void:
	var xf := prop.transform
	for spec: Dictionary in NavBake.LAYERS:
		var link := prop.get_node_or_null("NavLink" + str(spec.name).capitalize()) as NavigationLink3D
		if link == null:
			continue
		for end: String in ["start_position", "end_position"]:
			var local: Vector3 = link.get(end)
			var world := xf * Vector3(local.x, 0.0, local.z)
			local.y = field.sample(world.x, world.z) - xf.origin.y + float(spec.above_m) + 0.2
			link.set(end, local)


## A waystone (Waystone, a Marker3D): the marker where the giant respawns and, `stone` metres off,
## its standing stone (WORLD) and cap as one vertex-coloured mesh, and the Glow shown while it is open.
static func _waystone(it: Dictionary, xf: Transform3D, mat: Material) -> Node3D:
	var m := Marker3D.new()
	m.name = str(it.id).validate_node_name()
	m.set_script(load(S_WAYSTONE))
	m.set("checkpoint_id", str(it.id))
	m.set("radius_m", float(it.get("radius", 10.0)))
	m.set("requires_flags", PackedStringArray(it.get("requires_flags", [])))
	m.set("display_name", str(it.get("display_name", "")))
	m.transform = xf.translated_local(Vector3.UP * 0.3)
	var so: Array = it.get("stone", [8, 0])
	var off := Vector3(float(so[0]), -0.3, float(so[1]))
	var body := StaticBody3D.new()
	body.name = "Stone"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	body.position = off
	var cs := CollisionShape3D.new()
	cs.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 5.0, 1.6)
	cs.shape = box
	cs.position = Vector3(0, 2.5, 0)
	body.add_child(cs)
	body.add_child(WorldLayout.parts_node("Mesh", [WorldLayout.part("box", Vector3(0, -0.6, 0), Vector3(1.6, 5.6, 1.6), "stone_dark"),
		WorldLayout.part("box", Vector3(0, 5.0, 0), Vector3(2.2, 0.5, 2.2), "stone")], mat))
	m.add_child(body)
	var glow := WorldLayout.parts_node("Glow", [WorldLayout.part("box", Vector3(0, 5.6, 0), Vector3(0.8, 0.8, 0.8), "rune")], mat)
	glow.position = off
	m.add_child(glow)
	return m


## An element shown or hidden by a flag: a FlagVisibility node holding the element's mesh and its
## solids as a WORLD body.
static func _flag_node(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_FLAG, {"visible_when_flag": str(el.get("visible_when_flag", "")),
		"hidden_when_flag": str(el.get("hidden_when_flag", ""))})
	n.add_child(WorldLayout.parts_node("Mesh", WorldLayout.kind_parts(el, ctx), ctx.mat))
	var solids := WorldLayout.kind_solids(el, ctx)
	if not solids.is_empty():
		var body := StaticBody3D.new()
		body.name = "Body"
		body.collision_layer = SceneKit.L_WORLD
		body.collision_mask = 0
		var k := 0
		for s: Dictionary in solids:
			body.add_child(_solid_shape(kit, s, "Shape%d" % k))
			k += 1
		n.add_child(body)
	return n


static func _solid_shape(kit: SceneKit, s: Dictionary, node_name: String) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	var size: Vector3 = s.size
	if str(s.shape) == "cyl":
		var cyl := CylinderShape3D.new()
		cyl.radius = size.x * 0.5
		cyl.height = size.y
		cs.shape = cyl
	else:
		cs.shape = kit.box_shape(size)
	cs.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(float(s.get("yaw", 0.0)))), s.center)
	return cs


## The SizeGate nodes of a size_gates item: [{"node", "at": Vector2}] - its own boxes, the river's
## banks (along: river) or the channel's outer ring (ring: <channel>), one node per chunk and bank.
static func _size_gate_nodes(kit: SceneKit, it: Dictionary, feats: WorldFeatures, field: HeightField) -> Array:
	var boxes: Array = []   # [center: Vector3 (world), size: Vector3, yaw (rad), group key]
	var h := float(it.get("height_m", 14.0))
	if str(it.get("along", "")) == "river" and not feats.river.is_empty():
		var pts: PackedVector2Array = feats.river.points
		var cum: PackedFloat32Array = feats.river.cum
		var s0 := float(feats.river.gate_from)
		var length := float(feats.river.length)
		var wall := float(feats.river.wall_d)
		for side: float in [-1.0, 1.0]:
			var s := s0
			while s < length:
				var s1 := minf(s + GATE_PIECE_M, length)
				var pa := WorldFeatures.point_at(pts, cum, s)
				var pb := WorldFeatures.point_at(pts, cum, s1)
				var na := WorldFeatures.direction_at(pts, cum, s)
				var nb := WorldFeatures.direction_at(pts, cum, s1)
				var a := pa + Vector2(-na.y, na.x) * wall * side
				var b := pb + Vector2(-nb.y, nb.x) * wall * side
				var mid := (a + b) * 0.5
				s = s1
				if feats.on_bridge(mid) or not feats.walkable(mid.x, mid.y) or a.distance_to(b) < 1.0:
					continue
				var dir := b - a
				var y := minf(field.sample(a.x, a.y), field.sample(b.x, b.y)) - 3.0
				boxes.append([Vector3(mid.x, y + h * 0.5, mid.y), Vector3(dir.length() + 1.0, h, 1.0), atan2(-dir.y, dir.x),
					"%s_%d" % ["n" if side < 0 else "s", 0]])
	elif str(it.get("ring", "")) != "":
		for g: Dictionary in feats.gate_rings:
			if str(g.id) != str(it.ring):
				continue
			var c: Vector2 = g.center
			var r := float(g.r1)
			var e: Array = g.ellipse
			var n := int(ceil(TAU * r / GATE_PIECE_M))
			for k in n:
				var a := c + Vector2(cos(TAU * k / n), sin(TAU * k / n)) * r
				var b := c + Vector2(cos(TAU * (k + 1) / n), sin(TAU * (k + 1) / n)) * r
				var mid := (a + b) * 0.5
				var rn := sqrt(pow((mid.x - float(e[0])) / float(e[2]), 2.0) + pow((mid.y - float(e[1])) / float(e[3]), 2.0))
				if rn > 1.02:
					continue
				var dir := b - a
				var y := minf(field.sample(a.x, a.y), field.sample(b.x, b.y)) - 3.0
				boxes.append([Vector3(mid.x, y + h * 0.5, mid.y), Vector3(dir.length() + 1.0, h, 1.0), atan2(-dir.y, dir.x), "ring"])
	else:
		for bx: Array in it.get("boxes", []):
			var x := float(bx[0])
			var z := float(bx[1])
			var y := field.sample(x, z) - 3.0
			boxes.append([Vector3(x, y + float(bx[3]) * 0.5, z), Vector3(float(bx[2]), float(bx[3]), float(bx[4])),
				deg_to_rad(float(bx[5])), "box"])
	# one node per chunk and group
	var groups := {}
	var order: Array = []
	for b: Array in boxes:
		var centre: Vector3 = b[0]
		var key := "%s|%s" % [feats.chunk_id_of(centre.x, centre.z), b[3]]
		if not groups.has(key):
			groups[key] = []
			order.append(key)
		(groups[key] as Array).append(b)
	var out: Array = []
	var gi := 0
	for key: String in order:
		var list: Array = groups[key]
		var first: Vector3 = (list[0] as Array)[0]
		var gate := StaticBody3D.new()
		gate.name = ("%s_%d" % [str(it.id), gi]).validate_node_name()
		gi += 1
		kit.scripted(gate, S_SIZE_GATE, {"gate_id": str(it.id), "min_stage": int(it.min_stage), "cue": str(it.get("cue", "sfx.gate.water")),
			"message": str(it.get("message", ""))})
		gate.collision_layer = SizeGate.layer_for_stage(int(it.min_stage))
		gate.collision_mask = 0
		gate.position = first
		var k := 0
		for b: Array in list:
			var cs := CollisionShape3D.new()
			cs.name = "Wall%d" % k
			k += 1
			cs.shape = kit.box_shape(b[1])
			cs.transform = Transform3D(Basis(Vector3.UP, float(b[2])), (b[0] as Vector3) - first)
			gate.add_child(cs)
		out.append({"node": gate, "at": Vector2(first.x, first.z)})
	return out


# --------------------------------------------------------------------------- per chunk

## The chunk's static elements merged into one structures mesh (a scenery key with one identity
## instance, drawn as far as the terrain) and their solids into the chunk's solids.
static func _structures(kit: SceneKit, d: ChunkData, list: Array, mat: Material, ctx_base: Dictionary) -> Dictionary:
	if list.is_empty():
		return {"triangles": 0}
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tris := 0
	var to_chunk := Transform3D(Basis(), -d.origin)
	for e: Dictionary in list:
		var el: Dictionary = e.el
		var ctx := ctx_base.duplicate()
		ctx["frame"] = e.frame
		var xf: Transform3D = to_chunk * (e.frame as Transform3D)
		tris += WorldLayout.add_parts(st, WorldLayout.kind_parts(el, ctx), xf)
		for s: Dictionary in WorldLayout.kind_solids(el, ctx):
			var sxf := xf * Transform3D(Basis(Vector3.UP, deg_to_rad(float(s.get("yaw", 0.0)))), s.center)
			var yaw := sxf.basis.get_euler().y
			var size: Vector3 = s.size
			ChunkWriter.add_solid(d.solids, str(s.shape) == "cyl", sxf.origin, Vector3(size.x, size.y, size.z) if str(s.shape) != "cyl" \
				else Vector3(size.x, size.y, 0.0), yaw)
	st.generate_normals()
	st.index()
	var mesh := st.commit()
	if mesh.get_surface_count() == 0:
		return {"triangles": 0}
	mesh.surface_set_material(0, mat)
	var path := STRUCTURES_DIR + d.chunk_id + ".res"
	var disk := kit.output_path(path)
	DirAccess.make_dir_recursive_absolute(disk.get_base_dir())
	ResourceSaver.save(mesh, disk, ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
	var one := Transform3D.IDENTITY
	d.scenery[path] = ChunkWriter.xform_buffer([one])
	d.far_scenery.append(path)
	return {"triangles": tris}


## The chunk's scripted places split into parts of at most 150 nodes ({"ok", "roots": [Node3D]});
## their static collision shapes (size gates excepted) are appended to `shapes` (world space).
static func _parts(_kit: SceneKit, d: ChunkData, elements: Array, shapes: Array) -> Dictionary:
	if elements.is_empty():
		return {"ok": true, "roots": []}
	var chunk_xform := Transform3D(Basis(), d.origin)
	for e: Dictionary in elements:
		var node := e.node as Node3D
		# the node's transform is world space until here: make it chunk-local
		node.transform = Transform3D(node.transform.basis, node.transform.origin - d.origin)
		if str(e.container) != "SizeGates":
			NavBake.static_shapes(node, chunk_xform * node.transform, shapes)
	var split := ChunkWriter.split_parts(elements)
	if not bool(split.ok):
		for e: Dictionary in elements:
			(e.node as Node).free()
		return {"ok": false, "message": "%s: %s" % [d.chunk_id, split.message]}
	var roots: Array = []
	var parts: Array = split.parts
	for i in parts.size():
		roots.append(ChunkWriter.part_scene(d.coords, i, parts[i]))
	return {"ok": true, "roots": roots}


# --------------------------------------------------------------------------- skyline, map, root

static func _map_tints(feats: WorldFeatures) -> Dictionary:
	var out := {}
	for k in feats.region_ids.size():
		var rec := GameData.get_record(feats.region_ids[k])
		var t: Variant = rec.get("map_tint")
		if typeof(t) == TYPE_ARRAY and (t as Array).size() == 3:
			out[k + 1] = Color(float(t[0]), float(t[1]), float(t[2]))
		else:
			out[k + 1] = feats.skyline_tint(k + 1) * 1.5
	return out


## The skyline: the coarse terrain (coloured by the regions' skyline tints) and the silhouettes of
## the skyline landmarks (their parts, merged; the great pines as a pine shape).
static func _save_skyline(kit: SceneKit, feats: WorldFeatures, field: HeightField, layout: Dictionary, ctx_base: Dictionary,
		_statics: Array) -> void:
	var rect := feats.world_rect()
	var coarse := SkylineWriter.coarse(field, rect)
	var mesh := SkylineWriter.terrain_mesh(coarse, func(x: float, z: float) -> Color:
		return feats.skyline_tint(feats.region_index(x, z)))
	ResourceSaver.save(mesh, kit.output_path(SKYLINE_PATH), ResourceSaver.FLAG_COMPRESS)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for it: Dictionary in layout.items:
		if not bool(it.get("skyline", false)):
			continue
		var ctx := ctx_base.duplicate()
		ctx["frame"] = WorldLayout.frame(it, ctx)
		var parts: Array = []
		if str(it._section) == "pines":
			parts = [WorldLayout.part("cyl", Vector3.ZERO, Vector3(4.0, 50.0, 0), "bark"),
				WorldLayout.part("cone", Vector3(0, 16.0, 0), Vector3(18.0, 36.0, 0), "pine")]
			for other: Dictionary in layout.items:
				if str(other._section) == "pines" and other != it:
					var ox := WorldLayout.pos2(other) - WorldLayout.pos2(it)
					parts.append(WorldLayout.part("cone", Vector3(ox.x, 14.0, ox.y), Vector3(16.0, 34.0, 0), "pine"))
		else:
			parts = WorldLayout.kind_parts(it, ctx)
		WorldLayout.add_parts(st, parts, ctx.frame)
	st.generate_normals()
	ResourceSaver.save(st.commit(), kit.output_path(LANDMARKS_PATH), ResourceSaver.FLAG_COMPRESS)


static func build_root(kit: SceneKit, feats: WorldFeatures, field: HeightField, layout: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "World"
	kit.scripted(root, S_WORLD, {"level_id": LEVEL_ID})
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.62
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 120.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	root.add_child(sun)
	var streamer := Node.new()
	streamer.name = "Streamer"
	kit.scripted(streamer, S_STREAMER)
	root.add_child(streamer)
	var sky := Node3D.new()
	sky.name = "Skyline"
	var positions := PackedVector3Array()
	var flags := PackedStringArray()
	for b: Dictionary in layout.world.get("beacons", []):
		var t := WorldFeatures.v2(b.top)
		positions.append(Vector3(t.x, field.sample(t.x, t.y) + float(b.above_m), t.y))
		flags.append(str(b.flag))
	kit.scripted(sky, S_SKYLINE, {"beacon_positions": positions, "beacon_flags": flags, "beacon_height_m": 500.0,
		"beacon_radius_m": 3.0})
	root.add_child(sky)
	root.add_child(kit.n3("Chunks"))
	root.add_child(kit.n3("Navigation"))
	root.add_child(_bounds(feats))
	var route := walk_route(kit, layout, field)
	if route != null:
		var markers := kit.n3("Markers")
		markers.add_child(route)
		root.add_child(markers)
	var spawns := kit.n3("Spawns")
	var start := _start_transform(layout, field)
	var spawn := kit.marker("PlayerSpawn", start.origin)
	spawn.basis = start.basis
	spawns.add_child(spawn)
	root.add_child(spawns)
	root.add_child(kit.n3("Spawned"))
	var player := kit.instance(GIANT) as Node3D
	if player != null:
		player.name = "Player"
		player.transform = start
		root.add_child(player)
	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)
	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)
	return root


## The world walk's default route (M7 polish): Markers/Route, one plain Marker3D per point of
## world.json's walk_route on the ground (WP01, WP02, ...), which WorldWalk.level_route reads when
## --scenario=world_walk has no --route= (the test world has its own). Plain markers: no LevelMarker,
## so neither the level's marker lookups nor a bot's route points ever see them. null without one.
static func walk_route(kit: SceneKit, layout: Dictionary, field: HeightField) -> Node3D:
	var points: Variant = (layout.world.get("walk_route", {}) as Dictionary).get("points", [])
	if typeof(points) != TYPE_ARRAY or (points as Array).size() < 2:
		return null
	var route := kit.n3("Route")
	for i in (points as Array).size():
		var p := WorldFeatures.v2(points[i])
		route.add_child(kit.marker("WP%02d" % (i + 1), Vector3(p.x, field.sample(p.x, p.y), p.y)))
	return route


## Where the giant stands when the scene loads: the start checkpoint (world.cp.kingsgate_shelf).
static func _start_transform(layout: Dictionary, field: HeightField) -> Transform3D:
	for it: Dictionary in layout.items:
		if str(it.get("id", "")) == "world.cp.kingsgate_shelf":
			var p := WorldLayout.pos2(it)
			return Transform3D(Basis(Vector3.UP, deg_to_rad(float(it.get("yaw", 0.0)))), Vector3(p.x, field.sample(p.x, p.y) + 0.3, p.y))
	return Transform3D(Basis(), Vector3(-300, 50, 915))


## Invisible walls (layer 6, blockers) along the walkable edge of the interior, around the shelf
## and the Broken Stair's notch: no giant climbs the rim.
static func _bounds(feats: WorldFeatures) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = SceneKit.L_BLOCKER
	body.collision_mask = 0
	var e := feats.interior + 1.0
	var walls: Array = [
		["North", Vector3(0, 120, -e), Vector3(2.0 * e + 2.0, 400, 2.0)],
		["West", Vector3(-e, 120, 0), Vector3(2.0, 400, 2.0 * e + 2.0)],
		["East", Vector3(e, 120, 0), Vector3(2.0, 400, 2.0 * e + 2.0)],
	]
	# the south edge, with the two walkable notches open (each walled round instead)
	var cuts: Array = []
	for n: Dictionary in feats.notches:
		if bool(n.walkable):
			cuts.append(n.rect)
	cuts.sort_custom(func(a: Rect2, b: Rect2) -> bool: return a.position.x < b.position.x)
	var x0 := -e - 1.0
	var k := 0
	for r: Rect2 in cuts:
		walls.append(["South%d" % k, Vector3((x0 + r.position.x) * 0.5, 120, e), Vector3(r.position.x - x0, 400, 2.0)])
		k += 1
		walls.append(["Notch%dW" % k, Vector3(r.position.x - 1.0, 120, (e + r.end.y) * 0.5), Vector3(2.0, 400, r.end.y - e + 2.0)])
		walls.append(["Notch%dE" % k, Vector3(r.end.x + 1.0, 120, (e + r.end.y) * 0.5), Vector3(2.0, 400, r.end.y - e + 2.0)])
		walls.append(["Notch%dS" % k, Vector3(r.get_center().x, 120, r.end.y + 1.0), Vector3(r.size.x + 4.0, 400, 2.0)])
		x0 = r.end.x
	walls.append(["South%d" % k, Vector3((x0 + e + 1.0) * 0.5, 120, e), Vector3(e + 1.0 - x0, 400, 2.0)])
	for w: Array in walls:
		var cs := CollisionShape3D.new()
		cs.name = str(w[0])
		var s := BoxShape3D.new()
		s.size = w[2]
		cs.shape = s
		cs.position = w[1]
		body.add_child(cs)
	return body
