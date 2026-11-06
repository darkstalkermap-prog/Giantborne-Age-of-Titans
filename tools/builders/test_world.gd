extends RefCounted
## Builder: P24a's generated streaming test world (plan M6-M9 §3.6, §2.16; decision 12). 4 x 4 chunks
## of 256 m at 4 m spacing around the origin (x and z from -512 to 512), proving streaming, seams,
## hysteresis, the skyline and a settlement-sized chunk before the real world exists (P25):
##   * rolling noise (FastNoiseLite, SEED) at BASE_M; a 30-degree ramp crossing the x = 256 seam and
##     a 35-degree one crossing the z = 256 seam (planes, noise-free in their cores), each up to a
##     plateau that runs to the rim; a settlement pad flattened at PAD_Y in c2_2; a pond in c0_2; an
##     impassable rim beyond 448 m (and invisible walls at the world's edge, layer 6);
##   * the border rule: HeightField.relax_borders keeps every walkable face within 8 m of a chunk
##     border at 35 degrees or less (the build fails, naming the place, if it cannot);
##   * per chunk up to 120 trees (Poisson disk, 9 m apart: a trunk solid plus trunk and crown
##     instances), 60 saplings without collision and 16 rocks, kept off the route, the ramps, the
##     town and the pond;
##   * a Brannock-sized walled town in c2_2: 22 merged houses (two MultiMeshes) with their solids,
##     walls, two open gateways on the street, two fortified gates, 8 breakable houses, fences and
##     crates - the scripted props split into sub-scenes of at most 150 nodes;
##   * two landmarks (a watchtower on the 30-degree plateau, a monolith on the 35-degree one) as
##     props and as skyline silhouettes; a beacon on the watchtower lit by test_world.beacon.lit;
##   * the skyline (the coarse terrain, 32 m), the world index (start checkpoint, route markers, the
##     region grid: region.test_west for x < 0, region.test_east east of it), and the root scene
##     scenes/test/test_world.tscn (WorldRoot with Environment, Sun, Streamer, Skyline, Chunks,
##     Navigation, Bounds, Markers, Spawns, Spawned, Player, EncounterDirector, DebrisPool).
## Outputs: assets/test_world/{chunks/c<x>_<z>.res, shared/*, skyline.res, skyline_landmarks.res,
## index.res}, scenes/test/test_world.tscn and scenes/test/test_world/ (the house prop and the props
## parts). P24b adds the navmeshes (assets/test_world/nav/).

const LEVEL_ID := "level.test_world"
const SCENE_PATH := "res://scenes/test/test_world.tscn"
const PART_DIR := "res://scenes/test/test_world/"
const HOUSE_SCENE := "res://scenes/test/test_world/house_breakable.tscn"
const CHUNK_DIR := "res://assets/test_world/chunks/"
const SHARED_DIR := "res://assets/test_world/shared/"
const INDEX_PATH := "res://assets/test_world/index.res"
const SKYLINE_PATH := "res://assets/test_world/skyline.res"
const LANDMARKS_PATH := "res://assets/test_world/skyline_landmarks.res"

const GRID := Vector2i(4, 4)
const CHUNK_M := 256.0
const SPACING := 4.0
const ORIGIN := Vector3(-512.0, 0.0, -512.0)
const SEED := 2414
const BASE_M := 12.0
const NOISE_AMP_M := 6.0
const NOISE_FREQ := 1.0 / 280.0
## The rim: beyond RIM_FROM_M (|x| or |z|) the ground rises RIM_RISE_M over RIM_RUN_M (not walkable).
const RIM_FROM_M := 448.0
const RIM_RISE_M := 90.0
const RIM_RUN_M := 64.0
## The two ramps: the rise starts at u0 along `axis` and climbs `deg` over `run` metres (crossing a
## seam at u0 + run / 2), then the plateau holds to the rim; across, the core [v.x, v.y] is full
## height and the sides fall off over `fall` metres.
const RAMPS := [
	{"name": "ramp30", "axis": "x", "u0": 236.0, "run": 40.0, "deg": 30.0, "v": Vector2(-176.0, -80.0), "fall": 100.0},
	{"name": "ramp35", "axis": "z", "u0": 236.0, "run": 40.0, "deg": 35.0, "v": Vector2(-176.0, -80.0), "fall": 100.0},
]
## The settlement pad (x, z centre and size), its height and blend.
const PAD_CENTER := Vector2(128.0, 128.0)
const PAD_SIZE := Vector2(180.0, 150.0)
const PAD_Y := 14.0
const PAD_BLEND_M := 30.0
## The pond: centre, radius, the basin's depth at the centre, the water surface.
const POND_CENTER := Vector2(-380.0, 120.0)
const POND_R := 50.0
const POND_DEPTH_M := 7.0
const WATER_Y := 10.0
## Scenery per chunk.
const TREES_PER_CHUNK := 120
const TREE_SPACING_M := 9.0
const SAPLINGS_PER_CHUNK := 60
const ROCKS_PER_CHUNK := 16
const ROUTE_CLEAR_M := 16.0
## The town: walls inset from the pad, the street along z = PAD_CENTER.y, gateways west and east.
const WALL_INSET_M := 5.0
const WALL_H := 7.0
const WALL_T := 2.0
const STREET_HALF_M := 10.0
const GATEWAY_M := 16.0
const FORTIFIED_GAP_M := 18.0
const HOUSE_SIZE := Vector3(10.0, 6.0, 8.0)
const ROOF_H := 3.0
## The route the world walk follows by default (Markers/Route, test_world.route.NN): a loop with four
## seam crossings round (-256, -256), then through the town's gateways, round the east, over the
## 35-degree plateau and back past the pond. The seams test walks its first five points.
const ROUTE := [
	Vector2(-300, -300), Vector2(-196, -300), Vector2(-196, -196), Vector2(-300, -196), Vector2(-300, -300),
	Vector2(-150, -40), Vector2(20, 128), Vector2(128, 128), Vector2(232, 128), Vector2(350, 200),
	Vector2(350, 380), Vector2(100, 400), Vector2(-60, 350), Vector2(-360, 380), Vector2(-300, 40),
	Vector2(-300, -300),
]
const REGION_IDS := ["region.test_west", "region.test_east"]
const REGION_TINTS := [Color(0.27, 0.36, 0.24), Color(0.36, 0.35, 0.24)]
const LANDMARKS := [
	{"id": "test_world.landmark.watchtower", "chunk": Vector2i(3, 1), "pos": Vector2(380.0, -128.0), "shape": "tower"},
	{"id": "test_world.landmark.monolith", "chunk": Vector2i(1, 3), "pos": Vector2(-128.0, 380.0), "shape": "monolith"},
]
const BEACON_FLAG := "test_world.beacon.lit"
const START_CHECKPOINT := "test_world.cp.start"
const SKY := Color(0.56, 0.64, 0.74)

const S_WORLD := "res://scripts/world/world_root.gd"
const S_STREAMER := "res://scripts/world/chunk_streamer.gd"
const S_SKYLINE := "res://scripts/world/skyline.gd"
const S_DIRECTOR := "res://scripts/world/encounter_director.gd"
const S_DEBRIS := "res://scripts/world/debris_pool.gd"
const S_MARKER := "res://scripts/world/level_marker.gd"
const S_CHECKPOINT := "res://scripts/world/checkpoint_marker.gd"
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const GIANT := "res://scenes/player/giant.tscn"
const GATE_FORTIFIED := "res://scenes/world/gate_fortified.tscn"
const FENCE := "res://scenes/world/fence_wood.tscn"
const CRATE := "res://scenes/world/crate.tscn"
## The breakable houses' record: a timber breakable without flags or a loot table. (A record of
## their own would need a material in audio_mix.default, the audio package's file this wave; the
## real world's house records come with P29.)
const HOUSE_RECORD := "prop.fence_wood"

const MATERIALS := {
	"bark": Color(0.33, 0.24, 0.16), "leaves": Color(0.2, 0.37, 0.18), "sapling": Color(0.3, 0.45, 0.2),
	"rock": Color(0.47, 0.46, 0.43), "plaster": Color(0.78, 0.72, 0.6), "roof": Color(0.45, 0.24, 0.16),
	"wall": Color(0.55, 0.53, 0.5), "tower": Color(0.5, 0.48, 0.46), "monolith": Color(0.34, 0.33, 0.36),
	"rubble": Color(0.5, 0.45, 0.38),
}

static var _noise: FastNoiseLite = null


static func build_all(kit: SceneKit) -> void:
	var report := build(kit)
	if not bool(report.get("ok", false)):
		push_error("test_world: %s" % report.get("message", "the build failed"))
		return
	print("test_world: %s" % JSON.stringify(report.get("summary", {})))


## Builds everything; {"ok", "message" (on failure), "summary"}.
static func build(kit: SceneKit) -> Dictionary:
	var mats := _materials(kit)
	var meshes := _shared_meshes(kit, mats)
	var field := make_field()
	var first := field_first()
	var relax := field.relax_borders(first, int(CHUNK_M / SPACING), GRID, HeightField.BORDER_BAND_M,
		HeightField.BORDER_MAX_DEG, walkable)
	if not bool(relax.ok):
		return {"ok": false, "message": str(relax.message)}
	field.quantise_all()
	var house_scene := _save_house_scene(kit, mats)
	if house_scene == "":
		return {"ok": false, "message": "the breakable house scene was not saved"}
	var trees := {}   # spatial hash: Vector2i(16 m cell) -> [Vector2]
	var summary := {"chunks": 0, "trees": 0, "saplings": 0, "rocks": 0, "solids": 0, "parts": 0,
		"relax_iterations": relax.iterations, "border_deg": snappedf(float(relax.deg), 0.01), "chunk_bytes": {}}
	for cz in GRID.y:
		for cx in GRID.x:
			var c := Vector2i(cx, cz)
			var d := ChunkWriter.chunk_from_field(field, c, CHUNK_M, ORIGIN, first)
			d.surface_cells = ChunkWriter.cells(d, ChunkData.SURFACE_CELLS, func(x: float, z: float) -> int:
				return surface_kind(field, x, z))
			d.region_cells = ChunkWriter.cells(d, ChunkData.REGION_CELLS, func(x: float, _z: float) -> int:
				return region_index(x))
			var counts := _scenery(d, field, meshes, trees)
			_town(kit, d, field, meshes, mats)
			var parts := _props(kit, d, field, mats, house_scene)
			if not bool(parts.ok):
				return {"ok": false, "message": str(parts.message)}
			if d.chunk_id == "c0_2":
				var local := Rect2(POND_CENTER.x - POND_R - d.origin.x, POND_CENTER.y - POND_R - d.origin.z,
					2.0 * POND_R, 2.0 * POND_R)
				ChunkWriter.add_water(d.water, local, WATER_Y)
			var path := kit.output_path(CHUNK_DIR + d.chunk_id + ".res")
			var err := ChunkWriter.save(d, path)
			if err != OK:
				return {"ok": false, "message": "could not save %s (error %d)" % [path, err]}
			summary.chunks = int(summary.chunks) + 1
			summary.trees = int(summary.trees) + int(counts.trees)
			summary.saplings = int(summary.saplings) + int(counts.saplings)
			summary.rocks = int(summary.rocks) + int(counts.rocks)
			summary.solids = int(summary.solids) + d.solids.size() / ChunkData.SOLID_STRIDE
			summary.parts = int(summary.parts) + d.props_scenes.size()
			(summary.chunk_bytes as Dictionary)[d.chunk_id] = FileAccess.get_file_as_bytes(path).size()
	_save_skyline(kit, field)
	var root := build_root(kit, field)
	var idx := build_index(root, field)
	var ipath := kit.output_path(INDEX_PATH)
	DirAccess.make_dir_recursive_absolute(ipath.get_base_dir())
	var ierr := ResourceSaver.save(idx, ipath)
	if ierr != OK:
		root.free()
		return {"ok": false, "message": "could not save %s (error %d)" % [ipath, ierr]}
	kit.save(root, SCENE_PATH)
	return {"ok": true, "summary": summary}


# --------------------------------------------------------------------------- the terrain

static func noise() -> FastNoiseLite:
	if _noise == null:
		var n := FastNoiseLite.new()
		n.seed = SEED
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.frequency = NOISE_FREQ
		n.fractal_type = FastNoiseLite.FRACTAL_FBM
		n.fractal_octaves = 3
		n.fractal_gain = 0.45
		_noise = n
	return _noise


## The field's first sample is one spacing before the world (the outer chunks' aprons).
static func make_field() -> HeightField:
	var cells := int(CHUNK_M / SPACING)
	var size := Vector2i(GRID.x * cells + 3, GRID.y * cells + 3)
	var f := HeightField.make(Vector2(ORIGIN.x - SPACING, ORIGIN.z - SPACING), SPACING, size)
	f.fill(height)
	return f


## The field index of world sample (ORIGIN.x, ORIGIN.z).
static func field_first() -> Vector2i:
	return Vector2i(1, 1)


static func _smooth(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


## A ramp's (u, v) for a point.
static func _uv(r: Dictionary, x: float, z: float) -> Vector2:
	return Vector2(x, z) if str(r.axis) == "x" else Vector2(z, x)


## 1 inside the ramp's core across, falling to 0 over `fall` metres outside it.
static func _across(r: Dictionary, v: float) -> float:
	var core: Vector2 = r.v
	var out := maxf(core.x - v, v - core.y)
	return 1.0 if out <= 0.0 else 1.0 - _smooth(0.0, float(r.fall), out)


## The ramp's height above the base at (x, z).
static func ramp_offset(r: Dictionary, x: float, z: float) -> float:
	var uv := _uv(r, x, z)
	var run := float(r.run)
	var h := run * tan(deg_to_rad(float(r.deg)))
	return clampf((uv.x - float(r.u0)) / run, 0.0, 1.0) * h * _across(r, uv.y)


## Where the noise fades out for a ramp (its core strip from 20 m before the rise on).
static func _ramp_mask(r: Dictionary, x: float, z: float) -> float:
	var uv := _uv(r, x, z)
	return _across(r, uv.y) * _smooth(float(r.u0) - 60.0, float(r.u0) - 20.0, uv.x)


static func pad_weight(x: float, z: float) -> float:
	var dx := maxf(absf(x - PAD_CENTER.x) - PAD_SIZE.x * 0.5, 0.0)
	var dz := maxf(absf(z - PAD_CENTER.y) - PAD_SIZE.y * 0.5, 0.0)
	return 1.0 - _smooth(0.0, PAD_BLEND_M, Vector2(dx, dz).length())


static func _pond_d(x: float, z: float) -> float:
	return Vector2(x - POND_CENTER.x, z - POND_CENTER.y).length()


static func rim(x: float, z: float) -> float:
	var d := maxf(absf(x), absf(z)) - RIM_FROM_M
	return 0.0 if d <= 0.0 else RIM_RISE_M * _smooth(0.0, RIM_RUN_M, d)


## The test world's height at world (x, z), before the border relaxation.
static func height(x: float, z: float) -> float:
	var keep := 1.0
	for r: Dictionary in RAMPS:
		keep *= 1.0 - _ramp_mask(r, x, z)
	var pad := pad_weight(x, z)
	keep *= 1.0 - pad
	var pd := _pond_d(x, z)
	keep *= _smooth(POND_R + 10.0, POND_R + 30.0, pd)
	var y := BASE_M + noise().get_noise_2d(x, z) * NOISE_AMP_M * keep
	for r: Dictionary in RAMPS:
		y += ramp_offset(r, x, z)
	y = lerpf(y, PAD_Y, pad)
	y -= POND_DEPTH_M * (1.0 - _smooth(POND_R * 0.35, POND_R, pd))
	return y + rim(x, z)


## The border rule applies to walkable ground: everything inside the rim.
static func walkable(x: float, z: float) -> bool:
	return maxf(absf(x), absf(z)) < RIM_FROM_M - 4.0


## The steepest face of the field's cell holding (x, z), in degrees.
static func slope_at(field: HeightField, x: float, z: float) -> float:
	var i := int(floor((x - field.origin.x) / field.spacing))
	var j := int(floor((z - field.origin.y) / field.spacing))
	return field.cell_slope_deg(clampi(i, 0, field.size.x - 2), clampi(j, 0, field.size.y - 2))


## Surface cells: wet by the pond, hard in the town, on the rim and on steep ground, soft elsewhere.
static func surface_kind(field: HeightField, x: float, z: float) -> int:
	if _pond_d(x, z) < POND_R + 6.0:
		return ChunkData.SURFACE_WET
	if pad_weight(x, z) > 0.99 or not walkable(x, z) or slope_at(field, x, z) > 24.0:
		return ChunkData.SURFACE_HARD
	return ChunkData.SURFACE_SOFT


## The region list index (1-based) at world x: region.test_west west of the origin, east of it
## region.test_east.
static func region_index(x: float) -> int:
	return 1 if x < 0.0 else 2


# --------------------------------------------------------------------------- shared meshes, materials

static func _materials(kit: SceneKit) -> Dictionary:
	var out := {}
	DirAccess.make_dir_recursive_absolute(kit.output_path(SHARED_DIR))
	for key: String in MATERIALS:
		var m := StandardMaterial3D.new()
		m.albedo_color = MATERIALS[key]
		m.roughness = 0.95
		var path := kit.output_path(SHARED_DIR + "mat_%s.tres" % key)
		ResourceSaver.save(m, path, ResourceSaver.FLAG_CHANGE_PATH)
		out[key] = m
		kit.mats["tw_" + key] = m
	return out


## Unit meshes (base at y 0): trunk (cylinder r 0.5, h 1), crown and sapling (cones), rock, house
## body and wall (boxes), roof (a gable along x). Saved under SHARED_DIR; the chunks name them by path.
static func _shared_meshes(kit: SceneKit, mats: Dictionary) -> Dictionary:
	var specs := {
		"tree_trunk": [_cylinder_st(6, 0.5, 0.5), "bark"],
		"tree_crown": [_cylinder_st(7, 0.5, 0.0), "leaves"],
		"sapling": [_cylinder_st(5, 0.5, 0.0), "sapling"],
		"rock": [_box_st(), "rock"],
		"house_body": [_box_st(), "plaster"],
		"house_roof": [_roof_st(), "roof"],
		"wall": [_box_st(), "wall"],
	}
	var out := {}
	for key: String in specs:
		var st: SurfaceTool = specs[key][0]
		st.generate_normals()
		var mesh := st.commit()
		mesh.surface_set_material(0, mats[specs[key][1]])
		var path := SHARED_DIR + key + ".res"
		ResourceSaver.save(mesh, kit.output_path(path), ResourceSaver.FLAG_CHANGE_PATH | ResourceSaver.FLAG_COMPRESS)
		out[key] = path
	return out


static func _box_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c: Array[Vector3] = []
	for p: Vector3 in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5),
			Vector3(-0.5, 1, -0.5), Vector3(0.5, 1, -0.5), Vector3(0.5, 1, 0.5), Vector3(-0.5, 1, 0.5)]:
		c.append(p)
	for q: Array in [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for k: int in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			st.add_vertex(c[k])
	return st


static func _roof_st() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(-0.5, 1, 0)
	var r1 := Vector3(0.5, 1, 0)
	for v: Vector3 in [a, r0, r1, a, r1, b, d, c, r1, d, r1, r0, a, d, r0, b, r1, c]:
		st.add_vertex(v)
	return st


static func _cylinder_st(sides: int, r0: float, r1: float) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in sides:
		var a := TAU * float(k) / sides
		var b := TAU * float(k + 1) / sides
		var p0 := Vector3(cos(a) * r0, 0, sin(a) * r0)
		var p1 := Vector3(cos(b) * r0, 0, sin(b) * r0)
		var q0 := Vector3(cos(a) * r1, 1, sin(a) * r1)
		var q1 := Vector3(cos(b) * r1, 1, sin(b) * r1)
		if r1 <= 0.0:
			for v: Vector3 in [p0, p1, q1]:
				st.add_vertex(v)
			continue
		for v: Vector3 in [p0, p1, q1, p0, q1, q0, Vector3(0, 1, 0), q0, q1]:
			st.add_vertex(v)
	return st


# --------------------------------------------------------------------------- scenery

## Distance from (x, z) to the route polyline.
static func route_distance(x: float, z: float) -> float:
	var p := Vector2(x, z)
	var best := INF
	for i in ROUTE.size() - 1:
		var a: Vector2 = ROUTE[i]
		var b: Vector2 = ROUTE[i + 1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
		best = minf(best, p.distance_to(a + ab * t))
	return best


## Ground that scenery keeps off: the town (pad and blend), the pond, the rim, the ramps' strips,
## the route corridor, the landmarks and steep ground.
static func scenery_free(field: HeightField, x: float, z: float, route_m: float) -> bool:
	if pad_weight(x, z) > 0.0 or _pond_d(x, z) < POND_R + 8.0 or maxf(absf(x), absf(z)) > RIM_FROM_M - 8.0:
		return false
	for r: Dictionary in RAMPS:
		var uv := _uv(r, x, z)
		var core: Vector2 = r.v
		if uv.y > core.x - 12.0 and uv.y < core.y + 12.0 and uv.x > float(r.u0) - 30.0 \
				and uv.x < float(r.u0) + float(r.run) + 30.0:
			return false
	for lm: Dictionary in LANDMARKS:
		if Vector2(x, z).distance_to(lm.pos) < 24.0:
			return false
	if route_m > 0.0 and route_distance(x, z) < route_m:
		return false
	return slope_at(field, x, z) < 25.0


static func _hash_cell(p: Vector2) -> Vector2i:
	return Vector2i(int(floor(p.x / 16.0)), int(floor(p.y / 16.0)))


static func _spaced(trees: Dictionary, p: Vector2) -> bool:
	var c := _hash_cell(p)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2 in trees.get(c + Vector2i(dx, dz), []):
				if q.distance_to(p) < TREE_SPACING_M:
					return false
	return true


## Trees (a trunk solid, trunk and crown instances), saplings and rocks of one chunk.
static func _scenery(d: ChunkData, field: HeightField, meshes: Dictionary, trees: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED * 7919 + d.coords.x * 104729 + d.coords.y * 1299709
	var trunks: Array = []
	var crowns: Array = []
	var placed := 0
	var tries := 0
	while placed < TREES_PER_CHUNK and tries < 6000:
		tries += 1
		var lx := rng.randf_range(2.0, CHUNK_M - 2.0)
		var lz := rng.randf_range(2.0, CHUNK_M - 2.0)
		var x := d.origin.x + lx
		var z := d.origin.z + lz
		var p := Vector2(x, z)
		if not scenery_free(field, x, z, ROUTE_CLEAR_M) or not _spaced(trees, p):
			continue
		var c := _hash_cell(p)
		if not trees.has(c):
			trees[c] = []
		(trees[c] as Array).append(p)
		var y := field.sample(x, z)
		var r := rng.randf_range(0.45, 0.75)
		var th := rng.randf_range(7.0, 12.0)
		var cr := rng.randf_range(2.6, 4.0)
		var ch := rng.randf_range(7.0, 11.0)
		trunks.append(Transform3D(Basis.from_scale(Vector3(2.0 * r, th, 2.0 * r)), Vector3(lx, y - 0.3, lz)))
		crowns.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-PI, PI)) * Basis.from_scale(Vector3(2.0 * cr, ch, 2.0 * cr)),
			Vector3(lx, y + th * 0.55, lz)))
		ChunkWriter.add_solid(d.solids, true, Vector3(lx, y - 0.3 + (th + 0.6) * 0.5, lz), Vector3(2.0 * r, th + 0.6, 0.0))
		placed += 1
	var saplings: Array = []
	tries = 0
	while saplings.size() < SAPLINGS_PER_CHUNK and tries < 2000:
		tries += 1
		var lx := rng.randf_range(1.0, CHUNK_M - 1.0)
		var lz := rng.randf_range(1.0, CHUNK_M - 1.0)
		var x := d.origin.x + lx
		var z := d.origin.z + lz
		if not scenery_free(field, x, z, 0.0):
			continue
		var s := rng.randf_range(0.6, 1.1)
		saplings.append(Transform3D(Basis.from_scale(Vector3(1.6 * s, 2.6 * s, 1.6 * s)), Vector3(lx, field.sample(x, z) - 0.1, lz)))
	var rocks: Array = []
	tries = 0
	while rocks.size() < ROCKS_PER_CHUNK and tries < 2000:
		tries += 1
		var lx := rng.randf_range(4.0, CHUNK_M - 4.0)
		var lz := rng.randf_range(4.0, CHUNK_M - 4.0)
		var x := d.origin.x + lx
		var z := d.origin.z + lz
		if not scenery_free(field, x, z, ROUTE_CLEAR_M):
			continue
		var size := Vector3(rng.randf_range(2.0, 5.0), rng.randf_range(1.2, 3.0), rng.randf_range(2.0, 5.0))
		var yaw := rng.randf_range(-PI, PI)
		var y := field.sample(x, z) - 0.4
		rocks.append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), Vector3(lx, y, lz)))
		ChunkWriter.add_solid(d.solids, false, Vector3(lx, y + size.y * 0.5, lz), size, yaw)
	if not trunks.is_empty():
		d.scenery[meshes.tree_trunk] = ChunkWriter.xform_buffer(trunks)
		d.scenery[meshes.tree_crown] = ChunkWriter.xform_buffer(crowns)
	if not saplings.is_empty():
		d.scenery[meshes.sapling] = ChunkWriter.xform_buffer(saplings)
	if not rocks.is_empty():
		d.scenery[meshes.rock] = ChunkWriter.xform_buffer(rocks)
	return {"trees": placed, "saplings": saplings.size(), "rocks": rocks.size()}


# --------------------------------------------------------------------------- the town (c2_2)

static func _town_chunk() -> Vector2i:
	return Vector2i(int(floor((PAD_CENTER.x - ORIGIN.x) / CHUNK_M)), int(floor((PAD_CENTER.y - ORIGIN.z) / CHUNK_M)))


## The walls' rectangle (world x, z).
static func wall_rect() -> Rect2:
	var half := PAD_SIZE * 0.5 - Vector2(WALL_INSET_M, WALL_INSET_M)
	return Rect2(PAD_CENTER - half, half * 2.0)


## Every house slot of the town: two rows each side of the street, eight a row (world x, z).
static func house_slots() -> Array:
	var out: Array = []
	for zrow: float in [-45.0, -23.0, 23.0, 45.0]:
		for k in 8:
			out.append(Vector2(PAD_CENTER.x - 66.0 + 16.0 * k, PAD_CENTER.y + zrow))
	return out


## The square: where house slots 30 and 31 would be (world x, z).
static func square_center() -> Vector2:
	var slots := house_slots()
	return ((slots[30] as Vector2) + (slots[31] as Vector2)) * 0.5


## Which slots hold breakable houses (two a row; the rest of the first 30 are merged; the last two
## are the square).
static func breakable_slots() -> PackedInt32Array:
	return PackedInt32Array([1, 6, 9, 14, 17, 22, 25, 28])


## The town's static half in its chunk's data: the merged houses (body and roof instances with their
## solids) and the walls (instances and solids), the gateways left open on the street and gaps for
## the two fortified gates.
static func _town(kit: SceneKit, d: ChunkData, _field: HeightField, meshes: Dictionary, _mats: Dictionary) -> void:
	if d.coords != _town_chunk():
		return
	var bodies: Array = []
	var roofs: Array = []
	var slots := house_slots()
	var breakable := breakable_slots()
	for k in slots.size():
		if breakable.has(k) or k >= 30:
			continue
		var p: Vector2 = slots[k]
		var local := Vector3(p.x - d.origin.x, PAD_Y, p.y - d.origin.z)
		bodies.append(Transform3D(Basis.from_scale(HOUSE_SIZE), local))
		roofs.append(Transform3D(Basis.from_scale(Vector3(HOUSE_SIZE.x + 0.6, ROOF_H, HOUSE_SIZE.z + 0.6)),
			local + Vector3.UP * HOUSE_SIZE.y))
		ChunkWriter.add_solid(d.solids, false, local + Vector3.UP * HOUSE_SIZE.y * 0.5, HOUSE_SIZE)
	d.scenery[meshes.house_body] = ChunkWriter.xform_buffer(bodies)
	d.scenery[meshes.house_roof] = ChunkWriter.xform_buffer(roofs)
	var walls: Array = []
	var r := wall_rect()
	# North and south walls (along x), each with a gap for a fortified gate at the middle.
	for zw: float in [r.position.y, r.end.y]:
		var gap := FORTIFIED_GAP_M * 0.5
		for seg: Vector2 in [Vector2(r.position.x, PAD_CENTER.x - gap), Vector2(PAD_CENTER.x + gap, r.end.x)]:
			_wall(d, walls, Vector2(seg.x, zw), Vector2(seg.y, zw))
	# West and east walls (along z), each with an open gateway on the street.
	for xw: float in [r.position.x, r.end.x]:
		var gap := GATEWAY_M * 0.5
		for seg: Vector2 in [Vector2(r.position.y, PAD_CENTER.y - gap), Vector2(PAD_CENTER.y + gap, r.end.y)]:
			_wall(d, walls, Vector2(xw, seg.x), Vector2(xw, seg.y))
	d.scenery[meshes.wall] = ChunkWriter.xform_buffer(walls)


static func _wall(d: ChunkData, walls: Array, a: Vector2, b: Vector2) -> void:
	var mid := (a + b) * 0.5
	var length := a.distance_to(b) + WALL_T
	var along_x := absf(b.x - a.x) > absf(b.y - a.y)
	var size := Vector3(length, WALL_H, WALL_T) if along_x else Vector3(WALL_T, WALL_H, length)
	var local := Vector3(mid.x - d.origin.x, PAD_Y - 0.5, mid.y - d.origin.z)
	walls.append(Transform3D(Basis.from_scale(size), local))
	ChunkWriter.add_solid(d.solids, false, local + Vector3.UP * WALL_H * 0.5, size)


# --------------------------------------------------------------------------- the scripted props (parts)

## The breakable house scene (HOUSE_RECORD; a placed copy sets world_id): BreakableProp on
## the breakables layer, a CombatEntity, Intact (body and roof) / Broken (rubble), its block shape
## and hurtbox.
static func _save_house_scene(kit: SceneKit, _mats: Dictionary) -> String:
	var root := StaticBody3D.new()
	root.name = "HouseBreakable"
	kit.scripted(root, S_BREAKABLE, {"world_id": ""})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	root.add_child(kit.combat_entity("", HOUSE_RECORD, 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", Vector3(0, HOUSE_SIZE.y * 0.5, 0)))
	root.add_child(anchors)
	var block := CollisionShape3D.new()
	block.name = "BlockBody"
	block.shape = kit.box_shape(HOUSE_SIZE)
	block.position = Vector3.UP * HOUSE_SIZE.y * 0.5
	root.add_child(block)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(HOUSE_SIZE + Vector3(0.4, 0.4, 0.4)), Vector3.UP * HOUSE_SIZE.y * 0.5))
	root.add_child(hb)
	var intact := kit.n3("Intact")
	intact.add_child(kit.box("Walls", HOUSE_SIZE, Vector3.UP * HOUSE_SIZE.y * 0.5, "tw_plaster"))
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(HOUSE_SIZE.z + 0.6, ROOF_H, HOUSE_SIZE.x + 0.6)
	roof.mesh = roof_mesh
	roof.material_override = kit.mats["tw_roof"]
	roof.position = Vector3.UP * (HOUSE_SIZE.y + ROOF_H * 0.5)
	roof.rotation.y = PI * 0.5
	intact.add_child(roof)
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(kit.box("Rubble", Vector3(HOUSE_SIZE.x, 1.4, HOUSE_SIZE.z), Vector3.UP * 0.7, "tw_rubble"))
	broken.visible = false
	root.add_child(broken)
	return kit.save(root, HOUSE_SCENE)


## The chunk's scripted props: in the town chunk the 8 breakable houses, the two fortified gates and
## the fences and crates of the square; in a landmark's chunk the landmark (Landmarks). Split into
## parts of at most ChunkWriter.MAX_PART_NODES nodes, saved under PART_DIR and named in props_scenes.
static func _props(kit: SceneKit, d: ChunkData, field: HeightField, _mats: Dictionary, _house_scene: String) -> Dictionary:
	var elements: Array = []
	if d.coords == _town_chunk():
		var slots := house_slots()
		var n := 0
		for k: int in breakable_slots():
			n += 1
			var p: Vector2 = slots[k]
			var h := kit.instance(HOUSE_SCENE) as Node3D
			if h == null:
				return {"ok": false, "message": "the house scene did not load"}
			h.name = "House%d" % n
			h.set("world_id", "test_world.town.house_%d" % n)
			h.position = Vector3(p.x - d.origin.x, PAD_Y, p.y - d.origin.z)
			elements.append({"node": h, "container": "Props"})
		var r := wall_rect()
		for gate: Array in [["GateNorth", "test_world.town.gate_north", r.position.y, 0.0],
				["GateSouth", "test_world.town.gate_south", r.end.y, PI]]:
			var g := kit.instance(GATE_FORTIFIED) as Node3D
			if g == null:
				continue
			g.name = str(gate[0])
			g.set("world_id", str(gate[1]))
			g.position = Vector3(PAD_CENTER.x - d.origin.x, PAD_Y - 0.2, float(gate[2]) - d.origin.z)
			g.rotation.y = float(gate[3])
			elements.append({"node": g, "container": "Props"})
		# The square (the last two slots of the back row south of the street): two rows of three fences
		# (8 m each, along x) with six crates between them.
		var sq := square_center()
		for k in 6:
			var f := kit.instance(FENCE) as Node3D
			if f == null:
				break
			f.name = "Fence%d" % (k + 1)
			f.set("world_id", "test_world.town.fence_%d" % (k + 1))
			f.position = Vector3(sq.x - 8.0 + 8.0 * (k % 3) - d.origin.x, PAD_Y, sq.y + (-7.0 if k < 3 else 7.0) - d.origin.z)
			elements.append({"node": f, "container": "Props"})
		for k in 6:
			var c := kit.instance(CRATE) as Node3D
			if c == null:
				break
			c.name = "Crate%d" % (k + 1)
			c.set("world_id", "test_world.town.crate_%d" % (k + 1))
			c.position = Vector3(sq.x - 11.0 + 4.4 * k - d.origin.x, PAD_Y, sq.y - d.origin.z)
			elements.append({"node": c, "container": "Props"})
	for lm: Dictionary in LANDMARKS:
		if lm.chunk != d.coords:
			continue
		elements.append({"node": landmark_node(kit, lm, field, d.origin), "container": "Landmarks"})
	if elements.is_empty():
		return {"ok": true}
	var split := ChunkWriter.split_parts(elements)
	if not bool(split.ok):
		for e: Dictionary in elements:
			(e.node as Node).free()
		return {"ok": false, "message": "%s: %s" % [d.chunk_id, split.message]}
	var parts: Array = split.parts
	for i in parts.size():
		var root := ChunkWriter.part_scene(d.coords, i, parts[i])
		var path := ChunkWriter.part_path(PART_DIR, d.coords, i)
		if kit.save(root, path) == "":
			return {"ok": false, "message": "could not save %s" % path}
		d.props_scenes.append(path)
	return {"ok": true}


## The real landmark of its chunk (a static body with its mesh): the watchtower (a 40 m round tower
## with a roof) or the monolith (a 30 m standing stone).
static func landmark_node(kit: SceneKit, lm: Dictionary, field: HeightField, chunk_origin: Vector3) -> Node3D:
	var p: Vector2 = lm.pos
	var y := field.sample(p.x, p.y) - 0.5
	var body := StaticBody3D.new()
	body.name = str(lm.id).get_slice(".", 2).to_pascal_case()
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	body.position = Vector3(p.x - chunk_origin.x, y, p.y - chunk_origin.z)
	for s: Dictionary in landmark_shapes(lm):
		var size: Vector3 = s.size
		var cs := CollisionShape3D.new()
		var mi := MeshInstance3D.new()
		match str(s.shape):
			"box":
				cs.shape = kit.box_shape(size)
				var bm := BoxMesh.new()
				bm.size = size
				mi.mesh = bm
			_:
				var cyl := CylinderShape3D.new()
				cyl.radius = size.x * 0.5
				cyl.height = size.y
				cs.shape = cyl
				var cm := CylinderMesh.new()
				cm.top_radius = 0.0 if str(s.shape) == "cone" else size.x * 0.5
				cm.bottom_radius = size.x * 0.5
				cm.height = size.y
				cm.radial_segments = 8
				mi.mesh = cm
		var center := (s.position as Vector3) + Vector3.UP * size.y * 0.5
		mi.position = center
		mi.material_override = kit.mats["tw_" + str(s.mat)]
		cs.position = center
		mi.name = "Mesh%d" % body.get_child_count()
		cs.name = "Shape%d" % body.get_child_count()
		body.add_child(cs)
		body.add_child(mi)
	return body


## A landmark's shapes relative to its base: [{"shape", "position" (base centre), "size", "mat"}].
static func landmark_shapes(lm: Dictionary) -> Array:
	if str(lm.shape) == "tower":
		return [{"shape": "cylinder", "position": Vector3.ZERO, "size": Vector3(12.0, 40.0, 0.0), "mat": "tower"},
			{"shape": "cone", "position": Vector3(0, 40.0, 0), "size": Vector3(15.0, 9.0, 0.0), "mat": "roof"}]
	return [{"shape": "box", "position": Vector3.ZERO, "size": Vector3(7.0, 30.0, 4.0), "mat": "monolith"}]


# --------------------------------------------------------------------------- the skyline

static func _save_skyline(kit: SceneKit, field: HeightField) -> void:
	var rect := Rect2(Vector2(ORIGIN.x, ORIGIN.z), Vector2(GRID.x, GRID.y) * CHUNK_M)
	var coarse := SkylineWriter.coarse(field, rect)
	var mesh := SkylineWriter.terrain_mesh(coarse, func(x: float, _z: float) -> Color:
		return REGION_TINTS[region_index(x) - 1])
	ResourceSaver.save(mesh, kit.output_path(SKYLINE_PATH), ResourceSaver.FLAG_COMPRESS)
	var shapes: Array = []
	for lm: Dictionary in LANDMARKS:
		var p: Vector2 = lm.pos
		var base := Vector3(p.x, field.sample(p.x, p.y) - 0.5, p.y)
		for s: Dictionary in landmark_shapes(lm):
			shapes.append({"shape": s.shape, "position": base + (s.position as Vector3), "size": s.size,
				"color": MATERIALS[str(s.mat)]})
	ResourceSaver.save(SkylineWriter.landmarks_mesh(shapes), kit.output_path(LANDMARKS_PATH), ResourceSaver.FLAG_COMPRESS)


## The coarse skyline grid of the built field (tests compare it with the chunks).
static func coarse_skyline(field: HeightField) -> Dictionary:
	return SkylineWriter.coarse(field, Rect2(Vector2(ORIGIN.x, ORIGIN.z), Vector2(GRID.x, GRID.y) * CHUNK_M))


# --------------------------------------------------------------------------- the root scene and the index

static func build_root(kit: SceneKit, field: HeightField) -> Node3D:
	var root := Node3D.new()
	root.name = "TestWorld"
	kit.scripted(root, S_WORLD, {"level_id": LEVEL_ID})
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.7)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50, -35, 0)
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
	var tower: Dictionary = LANDMARKS[0]
	var tp: Vector2 = tower.pos
	kit.scripted(sky, S_SKYLINE, {"beacon_positions": PackedVector3Array([Vector3(tp.x, field.sample(tp.x, tp.y) + 49.0, tp.y)]),
		"beacon_flags": PackedStringArray([BEACON_FLAG]), "beacon_height_m": 400.0, "beacon_radius_m": 3.0})
	root.add_child(sky)
	root.add_child(kit.n3("Chunks"))
	root.add_child(kit.n3("Navigation"))
	root.add_child(_bounds())
	var markers := kit.n3("Markers")
	var route := kit.n3("Route")
	for i in ROUTE.size():
		var p: Vector2 = ROUTE[i]
		var id := "test_world.route.%02d" % (i + 1)
		route.add_child(kit.scripted(kit.marker("WP%02d" % (i + 1), Vector3(p.x, field.sample(p.x, p.y), p.y)), S_MARKER,
			{"marker_id": id, "kind": 6}))
	markers.add_child(route)
	root.add_child(markers)
	var start: Vector2 = ROUTE[0]
	var start_pos := Vector3(start.x, field.sample(start.x, start.y) + 0.3, start.y)
	var yaw := TargetingRules.yaw_of(Vector3(ROUTE[1].x - start.x, 0.0, ROUTE[1].y - start.y))
	var spawns := kit.n3("Spawns")
	var cp := kit.scripted(kit.marker("StartCheckpoint", start_pos), S_CHECKPOINT, {"checkpoint_id": START_CHECKPOINT}) as Node3D
	cp.rotation.y = yaw
	spawns.add_child(cp)
	root.add_child(spawns)
	root.add_child(kit.n3("Spawned"))
	var player := kit.instance(GIANT) as Node3D
	if player != null:
		player.name = "Player"
		player.position = start_pos
		player.rotation.y = yaw
		root.add_child(player)
	var director := Node.new()
	director.name = "EncounterDirector"
	kit.scripted(director, S_DIRECTOR)
	root.add_child(director)
	var debris := kit.n3("DebrisPool")
	kit.scripted(debris, S_DEBRIS)
	root.add_child(debris)
	return root


## Invisible walls (layer 6) along the world's edge.
static func _bounds() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Bounds"
	body.collision_layer = SceneKit.L_BLOCKER
	body.collision_mask = 0
	var half := Vector2(GRID.x, GRID.y) * CHUNK_M * 0.5
	var c := Vector2(ORIGIN.x, ORIGIN.z) + half
	var walls := [
		["North", Vector3(c.x, 100.0, c.y - half.y - 1.0), Vector3(half.x * 2.0, 400.0, 2.0)],
		["South", Vector3(c.x, 100.0, c.y + half.y + 1.0), Vector3(half.x * 2.0, 400.0, 2.0)],
		["West", Vector3(c.x - half.x - 1.0, 100.0, c.y), Vector3(2.0, 400.0, half.y * 2.0)],
		["East", Vector3(c.x + half.x + 1.0, 100.0, c.y), Vector3(2.0, 400.0, half.y * 2.0)],
	]
	for w: Array in walls:
		var cs := CollisionShape3D.new()
		cs.name = str(w[0])
		var s := BoxShape3D.new()
		s.size = w[2]
		cs.shape = s
		cs.position = w[1]
		body.add_child(cs)
	return body


## The world index: the root's checkpoints and markers (each with its chunk), the landmarks and the
## town's props by world id, the region grid (64 m cells), the route as a road, the map bounds.
static func build_index(root: Node3D, field: HeightField) -> WorldIndex:
	var idx := WorldIndex.build_from_scene(root, LEVEL_ID)
	for table: String in ["checkpoints", "markers"]:
		var t: Dictionary = idx.get(table)
		for id: String in t:
			var e: Dictionary = t[id]
			e["chunk"] = chunk_of(e.position)
			if table == "checkpoints":
				e["region"] = REGION_IDS[region_index((e.position as Vector3).x) - 1]
				e["display_name"] = "Test world start"
	for lm: Dictionary in LANDMARKS:
		var p: Vector2 = lm.pos
		var pos := Vector3(p.x, field.sample(p.x, p.y), p.y)
		idx.props[str(lm.id)] = {"position": pos, "chunk": chunk_of(pos)}
	idx.region_ids = PackedStringArray(REGION_IDS)
	idx.cell_m = 64.0
	idx.grid_origin = Vector2(ORIGIN.x, ORIGIN.z)
	idx.grid_size = Vector2i(int(GRID.x * CHUNK_M / 64.0), int(GRID.y * CHUNK_M / 64.0))
	var grid := PackedByteArray()
	grid.resize(idx.grid_size.x * idx.grid_size.y)
	for j in idx.grid_size.y:
		for i in idx.grid_size.x:
			grid[j * idx.grid_size.x + i] = region_index(ORIGIN.x + (i + 0.5) * 64.0)
	idx.region_grid = grid
	for i in ROUTE.size() - 1:
		var a: Vector2 = ROUTE[i]
		var b: Vector2 = ROUTE[i + 1]
		idx.add_road(Vector3(a.x, field.sample(a.x, a.y), a.y), Vector3(b.x, field.sample(b.x, b.y), b.y), 16.0)
	idx.map_bounds = Rect2(Vector2(ORIGIN.x, ORIGIN.z), Vector2(GRID.x, GRID.y) * CHUNK_M)
	return idx


## The chunk id holding a world position ("" outside the grid).
static func chunk_of(pos: Vector3) -> String:
	var c := Vector2i(int(floor((pos.x - ORIGIN.x) / CHUNK_M)), int(floor((pos.z - ORIGIN.z) / CHUNK_M)))
	if c.x < 0 or c.y < 0 or c.x >= GRID.x or c.y >= GRID.y:
		return ""
	return ChunkData.id_for(c)
