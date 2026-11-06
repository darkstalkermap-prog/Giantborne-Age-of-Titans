class_name ChunkData
extends Resource
## One chunk of a streamed world level (P24a; plan M6-M9 §2.7, decision 12), written offline by
## tools/world/chunk_writer.gd and loaded by ChunkStreamer: the heights, the scenery instances, the
## collision solids, the water, the navmeshes (P24b), the props sub-scenes and the region and
## surface cells of one square of the world.
##
## Coordinates: everything is chunk-local - x and z run from 0 to size_m from the chunk's min
## corner (`origin`, y 0), y is absolute. A chunk id is "c<x>_<z>" (x west -> east, z north ->
## south; id_for, coords_for).
##
## Heights: a regular grid of `samples` x `samples` 16-bit little-endian values (row-major, z rows):
## the chunk's (samples - 2)^2 inner samples at spacing_m (65 x 65 for 256 m at 4 m) plus a
## one-sample apron on every side, so neighbouring chunks share their border samples (identical
## heights at every seam) and border normals come out identical on both sides. A value v means
## height_min + v * height_step metres (0.004 m steps: a round trip is exact to 2 mm). There is no
## float copy in the resource: decode_heights() makes one at load.
##
## Scenery: mesh key (the res:// path of a shared Mesh, loaded once per level) -> its MultiMesh
## buffer, 12 floats per instance (Transform3D rows: basis.x.x, basis.y.x, basis.z.x, origin.x,
## then the y and z rows); far_scenery names the keys drawn to the terrain's distance. Solids: [kind, x, y, z, sx, sy, sz, yaw] per solid (kind 0 a box of size
## sx x sy x sz, kind 1 a cylinder of diameter sx and height sy), centred at (x, y, z), turned by
## yaw (radians) about y. Water: [min_x, min_z, max_x, max_z, surface_y] per rectangle. Cells:
## region_cells is a 4 x 4 grid of 64 m cells (0 = no region, k = the level's region list[k - 1]),
## surface_cells a 16 x 16 grid of 16 m cells (SURFACE_SOFT, SURFACE_HARD, SURFACE_WET).

const SURFACE_SOFT := 0
const SURFACE_HARD := 1
const SURFACE_WET := 2
const SURFACE_NAMES := ["soft", "hard", "wet"]
const REGION_CELLS := 4
const SURFACE_CELLS := 16
const SOLID_STRIDE := 8
const WATER_STRIDE := 5
const SCENERY_STRIDE := 12
const SOLID_BOX := 0
const SOLID_CYLINDER := 1

@export var chunk_id := ""
@export var coords := Vector2i()
## World position of the chunk's min corner (y 0).
@export var origin := Vector3()
@export var size_m := 256.0
@export var spacing_m := 4.0
## Samples per side, apron included (65 inner + 2).
@export var samples := 67
## 16-bit little-endian heights, samples x samples (no float copy).
@export var heights := PackedByteArray()
## Metres at value 0.
@export var height_min := 0.0
## Metres per unit.
@export var height_step := 0.004
## Mesh key (res:// path of a shared Mesh) -> PackedFloat32Array (12 floats per instance).
@export var scenery := {}
## The scenery keys drawn as far as the terrain (the preset's terrain_visibility_end_m) instead of
## the scenery's distance: a settlement's merged buildings and walls, seen from afar.
@export var far_scenery := PackedStringArray()
## [kind, x, y, z, sx, sy, sz, yaw] x n (kind 0 box, 1 cylinder).
@export var solids := PackedFloat32Array()
## [min_x, min_z, max_x, max_z, surface_y] x n.
@export var water := PackedFloat32Array()
## Nav layer bit (int) -> res:// path of its NavigationMesh (gate regions: their bit). P24b.
@export var nav := {}
## res:// paths of the chunk's props sub-scenes, each of at most 150 nodes.
@export var props_scenes := PackedStringArray()
## 4 x 4 indices into the level's region list (64 m cells; 0 = none).
@export var region_cells := PackedByteArray()
## 16 x 16 surface ids (0 soft, 1 hard, 2 wet; 16 m cells).
@export var surface_cells := PackedByteArray()


# --------------------------------------------------------------------------- ids

## "c<x>_<z>" for chunk coordinates.
static func id_for(c: Vector2i) -> String:
	return "c%d_%d" % [c.x, c.y]


## The coordinates of a chunk id ("c2_7" -> (2, 7)); (-1, -1) for anything else.
static func coords_for(id: String) -> Vector2i:
	if not id.begins_with("c"):
		return Vector2i(-1, -1)
	var parts := id.substr(1).split("_")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i(-1, -1)
	return Vector2i(int(parts[0]), int(parts[1]))


# --------------------------------------------------------------------------- heights

## Inner samples per side (65 for 256 m at 4 m).
func inner() -> int:
	return samples - 2


## The byte-pair index of grid sample (i, j), i and j in [-1, inner()] (the apron included).
func index_of(i: int, j: int) -> int:
	return (j + 1) * samples + (i + 1)


## The height of grid sample (i, j) in metres (i, j in [-1, inner()]).
func sample(i: int, j: int) -> float:
	return height_min + heights.decode_u16(2 * index_of(i, j)) * height_step


## Every sample (apron included) as floats, row-major (samples x samples): what the terrain and
## the ground body are built from at load.
func decode_heights() -> PackedFloat32Array:
	var n := samples * samples
	var out := PackedFloat32Array()
	out.resize(n)
	if heights.size() < 2 * n:
		return out
	for k in n:
		out[k] = height_min + heights.decode_u16(2 * k) * height_step
	return out


## The lowest and highest inner sample (x, y) in metres.
func height_range() -> Vector2:
	var lo := INF
	var hi := -INF
	var m := inner()
	for j in m:
		var row := (j + 1) * samples + 1
		for i in m:
			var v := heights.decode_u16(2 * (row + i))
			lo = minf(lo, v)
			hi = maxf(hi, v)
	if lo == INF:
		return Vector2.ZERO
	return Vector2(height_min + lo * height_step, height_min + hi * height_step)


## The height at chunk-local (x, z), bilinear on the grid (the apron answers up to one sample
## beyond the chunk). NaN outside that.
func height_at_local(x: float, z: float) -> float:
	var fx := x / spacing_m
	var fz := z / spacing_m
	var m := inner()
	if fx < -1.0 or fz < -1.0 or fx > float(m) or fz > float(m) or heights.size() < 2 * samples * samples:
		return NAN
	var i0 := clampi(int(floor(fx)), -1, m - 1)
	var j0 := clampi(int(floor(fz)), -1, m - 1)
	var tx := fx - float(i0)
	var tz := fz - float(j0)
	var h00 := sample(i0, j0)
	var h10 := sample(i0 + 1, j0)
	var h01 := sample(i0, j0 + 1)
	var h11 := sample(i0 + 1, j0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## The height at chunk-local (x, z) on the triangles the terrain mesh and the ground body use
## (each cell split along its (i, j) - (i + 1, j + 1) diagonal). NaN outside the chunk.
func ground_at_local(x: float, z: float) -> float:
	var fx := x / spacing_m
	var fz := z / spacing_m
	var m := inner()
	if fx < 0.0 or fz < 0.0 or fx > float(m - 1) or fz > float(m - 1) or heights.size() < 2 * samples * samples:
		return NAN
	var i0 := clampi(int(floor(fx)), 0, m - 2)
	var j0 := clampi(int(floor(fz)), 0, m - 2)
	var tx := fx - float(i0)
	var tz := fz - float(j0)
	var h00 := sample(i0, j0)
	var h11 := sample(i0 + 1, j0 + 1)
	if tx >= tz:
		# triangle (i, j), (i + 1, j), (i + 1, j + 1)
		return h00 + (sample(i0 + 1, j0) - h00) * tx + (h11 - sample(i0 + 1, j0)) * tz
	# triangle (i, j), (i + 1, j + 1), (i, j + 1)
	return h00 + (sample(i0, j0 + 1) - h00) * tz + (h11 - sample(i0, j0 + 1)) * tx


func contains_local(x: float, z: float) -> bool:
	return x >= 0.0 and z >= 0.0 and x < size_m and z < size_m


# --------------------------------------------------------------------------- cells, water

## The surface id at chunk-local (x, z): SURFACE_SOFT / HARD / WET, -1 outside or without cells.
func surface_at_local(x: float, z: float) -> int:
	if not contains_local(x, z) or surface_cells.size() < SURFACE_CELLS * SURFACE_CELLS:
		return -1
	var cell := size_m / SURFACE_CELLS
	var i := clampi(int(x / cell), 0, SURFACE_CELLS - 1)
	var j := clampi(int(z / cell), 0, SURFACE_CELLS - 1)
	return int(surface_cells[j * SURFACE_CELLS + i])


## The surface name at chunk-local (x, z) ("soft", "hard", "wet"; "" outside).
func surface_name_at_local(x: float, z: float) -> String:
	var s := surface_at_local(x, z)
	return SURFACE_NAMES[s] if s >= 0 and s < SURFACE_NAMES.size() else ""


## The region list index at chunk-local (x, z): 0 = none (or outside), k = region list[k - 1].
func region_index_at_local(x: float, z: float) -> int:
	if not contains_local(x, z) or region_cells.size() < REGION_CELLS * REGION_CELLS:
		return 0
	var cell := size_m / REGION_CELLS
	var i := clampi(int(x / cell), 0, REGION_CELLS - 1)
	var j := clampi(int(z / cell), 0, REGION_CELLS - 1)
	return int(region_cells[j * REGION_CELLS + i])


## The water surface height over chunk-local (x, z), or NaN where there is no water.
func water_at_local(x: float, z: float) -> float:
	var best := NAN
	var n := water.size() / WATER_STRIDE
	for k in n:
		var o := k * WATER_STRIDE
		if x >= water[o] and z >= water[o + 1] and x <= water[o + 2] and z <= water[o + 3]:
			var y := water[o + 4]
			if is_nan(best) or y > best:
				best = y
	return best


## How many solids, scenery instances (all keys) and props scenes the chunk has.
func counts() -> Dictionary:
	var inst := 0
	for key: Variant in scenery:
		inst += (scenery[key] as PackedFloat32Array).size() / SCENERY_STRIDE
	return {"solids": solids.size() / SOLID_STRIDE, "scenery": inst, "scenery_keys": scenery.size(),
		"props_scenes": props_scenes.size(), "water": water.size() / WATER_STRIDE}
