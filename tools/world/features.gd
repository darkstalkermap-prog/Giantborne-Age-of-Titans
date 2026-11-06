class_name WorldFeatures
extends RefCounted
## The terrain recipe of the real world (P25; plan M6-M9 §5.3, decision 12): turns the frame,
## regions and features of tools/data/world/world.json into one HeightField, in the table's order,
## and answers the questions the rest of the builder asks about the ground it made: where water is
## (and its surface), which gate bit the titan navmesh carries at a point, what is walkable, the
## region and surface of a cell, where the roads run and how steep they are.
##
## The recipe:
##   1. base: each region's base height plus seeded simplex noise (FastNoiseLite, frequency
##      1/520, its own amplitude), regions of one zone blended over base_blend_m (120 m) with a
##      smoothstep; the lowland zone and the Stonehold's highland zone meet at the highland wall
##      (cliff_band: a 16 m cliff face inside the band z -470..-430); the floor_m clamp keeps dry
##      land above the water;
##   2. the features in order: tilt, hill, mounds, ridge, bowl, ring_ridge, trench, rim (with its
##      notches: the Kingsgate shelf, the Broken Stair, the Wend's gap), ramp, flatten, terraces,
##      basin, channel, river, roads (flattened to their smoothed profile; water never filled);
##   3. HeightField.relax_borders (the builder's step) keeps every walkable border face <= 35 deg.
## Tools only (tools/ is never exported).

const SURFACE_SOFT := 0
const SURFACE_HARD := 1
const SURFACE_WET := 2
const SURFACE_IDS := {"soft": 0, "hard": 1, "wet": 2}
## Water is rasterised on this grid (metres) into the chunks' water rectangles.
const WATER_CELL_M := 8.0
## A cell is water when the ground at one of its corners lies this far under the surface.
const WATER_MIN_DEPTH_M := 0.05
## Slopes steeper than this are hard ground (rock).
const HARD_SLOPE_DEG := 32.0
## Ground this steep is no giant's floor (the body's 46 degree floor angle): relax_borders leaves it.
const CLIFF_DEG := 45.0

var spec: Dictionary = {}
var level_id := "level.world"
var spacing := 4.0
var grid := Vector2i(8, 8)
var chunk_m := 256.0
## World x, z of the grid's min corner.
var origin := Vector2(-1024.0, -1024.0)
var interior := 896.0
var water_level := 4.0
var floor_m := 5.0
var noise: FastNoiseLite = null
var rim_noise: FastNoiseLite = null
## [{"id", "rect": Rect2, "base", "amp", "zone", "surface"}] in the table's order.
var regions: Array = []
var region_ids := PackedStringArray()
var blend_m := 120.0
var cliff: Dictionary = {}
var rim: Dictionary = {}
## [{"id", "rect": Rect2, "floor", "wall", "walkable"}]
var notches: Array = []
var features: Array = []
## [{"id", "name", "width", "points": PackedVector2Array, "carve", "min_stage", "max_stage"}]
var roads: Array = []
var road_rules: Dictionary = {}

## What applying the features left behind (filled by make_field):
## water bodies: [{"id", "kind": "ellipse" | "river", "surface", ...}]
var water_bodies: Array = []
## The river (the Wend): {"points", "cum" (arc length at each point), params...}
var river: Dictionary = {}
## Gate regions besides the river and the channel (the builder adds the Giant's Stair and the
## Moot's gate): [{"rect": Rect2, "bit"}].
var gate_rects: Array = []
## [{"center": Vector2, "r0", "r1", "bit", "ellipse": [cx, cz, rx, rz]}]
var gate_rings: Array = []
## Road id -> {"s": PackedFloat32Array, "y": PackedFloat32Array, "grade_max", "length"}.
var road_profiles: Dictionary = {}
## Field samples that are water (lakes, rivers, ponds): roads never fill them.
var water_mask := PackedByteArray()
## Areas flattened as settlement or site pads ("hard" ground): [{"rect": Rect2} | {"circle": Vector3}].
var pads: Array = []
var report: Dictionary = {}

var _field: HeightField = null


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _init(p_spec: Dictionary = {}) -> void:
	if not p_spec.is_empty():
		configure(p_spec)


## Reads the world table (world.json).
func configure(p_spec: Dictionary) -> void:
	spec = p_spec
	var f: Dictionary = spec.get("frame", {})
	level_id = str(f.get("level_id", "level.world"))
	spacing = float(f.get("spacing_m", 4.0))
	var g: Array = f.get("grid", [8, 8])
	grid = Vector2i(int(g[0]), int(g[1]))
	chunk_m = float(f.get("chunk_m", 256.0))
	var o: Array = f.get("origin_m", [-1024, -1024])
	origin = Vector2(float(o[0]), float(o[1]))
	interior = float(f.get("interior_m", 896.0))
	water_level = float(f.get("water_level_m", 4.0))
	floor_m = float(f.get("floor_m", 5.0))
	var nz: Dictionary = spec.get("noise", {})
	noise = FastNoiseLite.new()
	noise.seed = int(f.get("seed", 2516))
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = float(nz.get("frequency", 1.0 / 520.0))
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = int(nz.get("octaves", 4))
	noise.fractal_gain = float(nz.get("gain", 0.5))
	noise.fractal_lacunarity = float(nz.get("lacunarity", 2.0))
	rim_noise = FastNoiseLite.new()
	rim_noise.seed = noise.seed + 7
	rim_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	rim_noise.frequency = 1.0 / 140.0
	rim_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	rim_noise.fractal_octaves = 3
	blend_m = float(spec.get("base_blend_m", 120.0))
	regions.clear()
	region_ids = PackedStringArray()
	for r: Dictionary in spec.get("regions", []):
		var rect := rect_of(r.rect)
		regions.append({"id": str(r.id), "rect": rect, "base": float(r.base_m), "amp": float(r.noise_m),
			"zone": str(r.get("zone", "low")), "surface": str(r.get("surface", "soft")),
			"skyline_tint": r.get("skyline_tint", [0.35, 0.38, 0.3])})
		region_ids.append(str(r.id))
	cliff = spec.get("cliff_band", {})
	rim = spec.get("rim", {})
	notches.clear()
	for n: Dictionary in rim.get("notches", []):
		notches.append({"id": str(n.id), "rect": rect_of(n.rect), "floor": float(n.floor_m),
			"wall": float(n.get("wall_m", 5.0)), "walkable": bool(n.get("walkable", false))})
	features = spec.get("features", [])
	road_rules = spec.get("road_rules", {})
	roads.clear()
	for r: Dictionary in spec.get("roads", []):
		var pts := PackedVector2Array()
		for p: Array in r.points:
			pts.append(Vector2(float(p[0]), float(p[1])))
		roads.append({"id": str(r.id), "name": str(r.get("name", r.id)), "width": float(r.get("width_m", 14.0)),
			"points": pts, "carve": bool(r.get("carve", true)), "min_stage": int(r.get("min_stage", 0)),
			"max_stage": int(r.get("max_stage", 10)), "direct": bool(r.get("direct", false)),
			"ride": bool(r.get("ride", false))})


# --------------------------------------------------------------------------- small helpers

## [[min_x, min_z], [max_x, max_z]] -> Rect2 (x, z).
static func rect_of(a: Variant) -> Rect2:
	var lo := Vector2(float(a[0][0]), float(a[0][1]))
	var hi := Vector2(float(a[1][0]), float(a[1][1]))
	return Rect2(lo, hi - lo)


static func v2(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## The distance from p to the rectangle (0 inside).
static func rect_distance(r: Rect2, p: Vector2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return Vector2(dx, dz).length()


## The signed distance from p to the rectangle (negative inside).
static func rect_signed(r: Rect2, p: Vector2) -> float:
	var dx := maxf(r.position.x - p.x, p.x - r.end.x)
	var dz := maxf(r.position.y - p.y, p.y - r.end.y)
	if dx <= 0.0 and dz <= 0.0:
		return maxf(dx, dz)
	return Vector2(maxf(dx, 0.0), maxf(dz, 0.0)).length()


## Distance from p to segment a-b and the parameter (0..1) of the nearest point.
static func segment_distance(p: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-9), 0.0, 1.0)
	return Vector2(p.distance_to(a + ab * t), t)


## Distance from p to a polyline and the arc length of the nearest point: Vector2(d, s).
static func polyline_distance(p: Vector2, pts: PackedVector2Array) -> Vector2:
	var best := INF
	var best_s := 0.0
	var s := 0.0
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var r := segment_distance(p, a, b)
		if r.x < best:
			best = r.x
			best_s = s + r.y * a.distance_to(b)
		s += a.distance_to(b)
	return Vector2(best, best_s)


## Cumulative arc length at each point of a polyline.
static func cumulative(pts: PackedVector2Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(pts.size())
	var s := 0.0
	for i in pts.size():
		if i > 0:
			s += pts[i - 1].distance_to(pts[i])
		out[i] = s
	return out


## The point at arc length s along a polyline (clamped to its ends).
static func point_at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	if pts.size() == 1:
		return pts[0]
	for i in pts.size() - 1:
		if s <= cum[i + 1] or i == pts.size() - 2:
			var seg := maxf(cum[i + 1] - cum[i], 1e-6)
			return pts[i].lerp(pts[i + 1], clampf((s - cum[i]) / seg, 0.0, 1.0))
	return pts[pts.size() - 1]


## The unit direction of a polyline at arc length s.
static func direction_at(pts: PackedVector2Array, cum: PackedFloat32Array, s: float) -> Vector2:
	for i in pts.size() - 1:
		if s <= cum[i + 1] or i == pts.size() - 2:
			return (pts[i + 1] - pts[i]).normalized()
	return Vector2.RIGHT


## Linear interpolation in a sorted table [[x, y], ...] (clamped to its ends).
static func table_at(table: Array, x: float) -> float:
	if table.is_empty():
		return 0.0
	if x <= float(table[0][0]):
		return float(table[0][1])
	for i in table.size() - 1:
		var a: Array = table[i]
		var b: Array = table[i + 1]
		if x <= float(b[0]):
			var t := (x - float(a[0])) / maxf(float(b[0]) - float(a[0]), 1e-6)
			return lerpf(float(a[1]), float(b[1]), t)
	return float(table[table.size() - 1][1])


## The samples of `f` within the world rectangle r: Rect2i of field indices (inclusive start,
## exclusive end).
func _span(f: HeightField, r: Rect2) -> Rect2i:
	var i0 := clampi(int(floor((r.position.x - f.origin.x) / f.spacing)), 0, f.size.x)
	var j0 := clampi(int(floor((r.position.y - f.origin.y) / f.spacing)), 0, f.size.y)
	var i1 := clampi(int(ceil((r.end.x - f.origin.x) / f.spacing)) + 1, 0, f.size.x)
	var j1 := clampi(int(ceil((r.end.y - f.origin.y) / f.spacing)) + 1, 0, f.size.y)
	return Rect2i(i0, j0, i1 - i0, j1 - j0)


func world_rect() -> Rect2:
	return Rect2(origin, Vector2(grid.x, grid.y) * chunk_m)


# --------------------------------------------------------------------------- the field

## The world's field: the frame one spacing beyond the world on every side (the outer chunks'
## aprons), the base, then every feature in order. Keeps the field for later questions.
func make_field() -> HeightField:
	var cells := int(roundf(chunk_m / spacing))
	var size := Vector2i(grid.x * cells + 3, grid.y * cells + 3)
	var f := HeightField.make(origin - Vector2(spacing, spacing), spacing, size)
	_field = f
	water_mask = PackedByteArray()
	water_mask.resize(size.x * size.y)
	water_bodies.clear()
	gate_rings.clear()
	pads.clear()
	road_profiles.clear()
	river = {}
	report = {}
	for j in size.y:
		var z := f.world_z(j)
		for i in size.x:
			f.h[j * size.x + i] = base_height(f.world_x(i), z)
	for feat: Dictionary in features:
		apply_feature(f, feat)
	return f


## The field index of world sample (origin.x, origin.y).
func field_first() -> Vector2i:
	return Vector2i(1, 1)


func field() -> HeightField:
	return _field


## The base height: the regions of the point's zone blended, plus noise, the highland wall.
func base_height(x: float, z: float) -> float:
	var cx := clampf(x, -interior, interior)
	var cz := clampf(z, -interior, interior)
	var n := noise.get_noise_2d(x, z)
	var wall_z: Vector2 = Vector2(cliff.face[0], cliff.face[1]) if cliff.has("face") else Vector2(-458, -442)
	var band: Array = cliff.get("z", [-470, -430])
	var low := _zone_blend(cx, maxf(cz, float(band[1])), "low")
	var high := _zone_blend(cx, minf(cz, float(band[0])), "high")
	var hl := low.x + n * low.y
	var hh := high.x + n * high.y
	var y := hl
	if high.x > -1e8:
		# 0 south of the face, 1 north of it (face = [north edge, south edge] of the cliff face).
		var t := smoothstep(wall_z.y, wall_z.x, cz)
		y = lerpf(hl, hh, t)
	return maxf(y, floor_m)


## Vector2(height, noise amplitude) of the zone's regions blended at (x, z).
func _zone_blend(x: float, z: float, zone: String) -> Vector2:
	var wsum := 0.0
	var h := 0.0
	var a := 0.0
	var p := Vector2(x, z)
	var half := blend_m * 0.5
	for r: Dictionary in regions:
		if str(r.zone) != zone:
			continue
		var sd := rect_signed(r.rect, p)
		var w := smoothstep(half, -half, sd)
		if w <= 0.0:
			continue
		wsum += w
		h += w * float(r.base)
		a += w * float(r.amp)
	if wsum <= 0.0:
		# Outside every region of the zone: the nearest one's values.
		var best := INF
		var out := Vector2(-1e9, 0.0)
		for r: Dictionary in regions:
			if str(r.zone) != zone:
				continue
			var d := rect_distance(r.rect, p)
			if d < best:
				best = d
				out = Vector2(float(r.base), float(r.amp))
		return out
	return Vector2(h / wsum, a / wsum)


## Applies one feature of the table to the field.
func apply_feature(f: HeightField, feat: Dictionary) -> void:
	match str(feat.get("type", "")):
		"tilt":
			_tilt(f, feat)
		"hill":
			_hill(f, feat)
		"mounds":
			_mounds(f, feat)
		"ridge":
			_ridge(f, feat)
		"bowl":
			_bowl(f, feat)
		"ring_ridge":
			_ring_ridge(f, feat)
		"trench":
			_trench(f, feat)
		"rim":
			_rim(f)
		"ramp":
			_ramp(f, feat)
		"flatten":
			_flatten(f, feat)
		"terraces":
			_terraces(f, feat)
		"basin":
			_basin(f, feat)
		"channel":
			_channel(f, feat)
		"river":
			_river(f, feat)
		"roads":
			_roads(f)
		_:
			push_error("WorldFeatures: unknown feature type '%s' (%s)" % [feat.get("type"), feat.get("id", "?")])


# --------------------------------------------------------------------------- features

func _tilt(f: HeightField, feat: Dictionary) -> void:
	var r := rect_of(feat.rect)
	var z0 := float(feat.from_z)
	var z1 := float(feat.to_z)
	var add := float(feat.add_m)
	var half := blend_m * 0.5
	var span := _span(f, r.grow(half))
	# "zone": "low" - the lowland only: the tilt fades out across the highland wall's face (as the
	# base hands over to the high zone), so the plateau beyond is never raised
	var low_only := str(feat.get("zone", "")) == "low"
	var face: Array = cliff.get("face", [-458, -442])
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		var t := clampf((z - z0) / (z1 - z0), 0.0, 1.0)
		if low_only:
			t *= 1.0 - smoothstep(float(face[1]), float(face[0]), z)
		if t <= 0.0:
			continue
		for i in range(span.position.x, span.end.x):
			var p := Vector2(f.world_x(i), z)
			# the rectangle's sides blend like the regions do (only across x: the tilt runs along z)
			var w := smoothstep(half, -half, maxf(r.position.x - p.x, p.x - r.end.x))
			if w > 0.0:
				f.h[j * f.size.x + i] += add * t * w


## A shape's distance (0 inside): {"rect": [[..],[..]]} or {"circle": [x, z, r]}.
static func shape_distance(feat: Dictionary, p: Vector2) -> float:
	if feat.has("circle"):
		var c: Array = feat.circle
		return maxf(p.distance_to(Vector2(float(c[0]), float(c[1]))) - float(c[2]), 0.0)
	return rect_distance(rect_of(feat.rect), p)


## A shape's bounding rectangle.
static func shape_rect(feat: Dictionary) -> Rect2:
	if feat.has("circle"):
		var c: Array = feat.circle
		var r := float(c[2])
		return Rect2(float(c[0]) - r, float(c[1]) - r, 2.0 * r, 2.0 * r)
	return rect_of(feat.rect)


func _hill(f: HeightField, feat: Dictionary) -> void:
	var apron := maxf(float(feat.get("apron_m", 60.0)), 0.001)
	var linear := str(feat.get("profile", "smooth")) == "linear"
	var span := _span(f, shape_rect(feat).grow(apron))
	var has_top := feat.has("top_m")
	var top := float(feat.get("top_m", 0.0))
	var rise := float(feat.get("rise_m", 0.0))
	var keep_higher := str(feat.get("mode", "")) == "max"
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var d := shape_distance(feat, Vector2(f.world_x(i), z))
			if d >= apron:
				continue
			var u := d / apron
			var w := 1.0 - (u if linear else smoothstep(0.0, 1.0, u))
			var k := j * f.size.x + i
			var y: float = lerpf(f.h[k], top, w) if has_top else f.h[k] + rise * w
			f.h[k] = maxf(f.h[k], y) if keep_higher else y


func _mounds(f: HeightField, feat: Dictionary) -> void:
	var r := float(feat.get("radius_m", 16.0))
	var rise := float(feat.get("rise_m", 5.0))
	for p: Array in feat.points:
		var c := v2(p)
		var span := _span(f, Rect2(c - Vector2(r, r), Vector2(2 * r, 2 * r)))
		for j in range(span.position.y, span.end.y):
			for i in range(span.position.x, span.end.x):
				var d := Vector2(f.world_x(i), f.world_z(j)).distance_to(c)
				if d < r:
					f.h[j * f.size.x + i] += rise * (0.5 + 0.5 * cos(PI * d / r))


func _ridge(f: HeightField, feat: Dictionary) -> void:
	var pts := _points(feat.points)
	var half := float(feat.get("half_m", 20.0))
	var fall := float(feat.get("fall_m", 40.0))
	var rise := float(feat.get("rise_m", 20.0))
	var bounds := _bounds(pts).grow(half + fall)
	var span := _span(f, bounds)
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var d := polyline_distance(Vector2(f.world_x(i), z), pts).x
			if d >= half + fall:
				continue
			var w := 1.0 if d <= half else 1.0 - smoothstep(half, half + fall, d)
			f.h[j * f.size.x + i] += rise * w


func _bowl(f: HeightField, feat: Dictionary) -> void:
	var c: Array = feat.circle
	var centre := Vector2(float(c[0]), float(c[1]))
	var r := float(c[2])
	var wall := float(feat.get("wall_m", 12.0))
	var floor_y := float(feat.floor_m)
	var span := _span(f, Rect2(centre - Vector2(r + wall, r + wall), Vector2(2 * (r + wall), 2 * (r + wall))))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var d := Vector2(f.world_x(i), z).distance_to(centre)
			if d >= r + wall:
				continue
			var k := j * f.size.x + i
			f.h[k] = floor_y if d <= r else lerpf(floor_y, f.h[k], smoothstep(r, r + wall, d))
	if feat.has("mouth"):
		# the bowl's open side: a ramp from its floor out to the ground at the mouth
		_ramp(f, {"from": [centre.x, centre.y], "to": feat.mouth, "from_y": floor_y, "to_y": "auto",
			"half_m": float(feat.get("mouth_half_m", 20.0)), "side_m": 18.0})


func _ring_ridge(f: HeightField, feat: Dictionary) -> void:
	var centre := v2(feat.center)
	var r_floor := float(feat.floor_r)
	var r_in := float(feat.inner_r)
	var r_out := float(feat.outer_r)
	var wall := float(feat.get("outer_wall_m", 14.0))
	var top := float(feat.top_m)
	var floor_y := float(feat.floor_m)
	var reach := r_out + wall + 24.0
	var cuts: Array = []
	for cut: Dictionary in feat.get("cuts", []):
		var to := v2(cut.to)
		cuts.append({"dir": (to - centre).normalized(), "half": float(cut.get("half_m", 8.0))})
	var span := _span(f, Rect2(centre - Vector2(reach, reach), Vector2(2 * reach, 2 * reach)))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var p := Vector2(f.world_x(i), z)
			var d := p.distance_to(centre)
			if d >= reach:
				continue
			var k := j * f.size.x + i
			var ground: float = f.h[k]
			var y := ground
			if d <= r_floor:
				y = floor_y
			elif d <= r_in:
				y = lerpf(floor_y, top, smoothstep(r_floor, r_in, d))
			elif d <= r_out:
				y = top
			elif d <= r_out + wall:
				y = lerpf(top, ground, smoothstep(r_out, r_out + wall, d))
			# the cuts: trenches at the floor's height through the ring, blending into the ground outside
			for cut: Dictionary in cuts:
				var dir: Vector2 = cut.dir
				var a := (p - centre).dot(dir)
				if a < 0.0:
					continue
				var q := absf((p - centre).cross(dir))
				var half := float(cut.half)
				if q >= half + 4.0:
					continue
				var cut_y := floor_y if a <= r_out else lerpf(floor_y, ground, smoothstep(r_out, reach, a))
				var w := 1.0 - smoothstep(half, half + 4.0, q)
				y = lerpf(y, minf(y, cut_y), w)
			f.h[k] = y


func _trench(f: HeightField, feat: Dictionary) -> void:
	var pts := _points(feat.points)
	var half := float(feat.get("half_m", 20.0))
	var wall := float(feat.get("wall_m", 20.0))
	var depth := float(feat.depth_m)
	var span := _span(f, _bounds(pts).grow(half + wall))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var d := polyline_distance(Vector2(f.world_x(i), z), pts).x
			if d >= half + wall:
				continue
			var w := 1.0 if d <= half else 1.0 - smoothstep(half, half + wall, d)
			f.h[j * f.size.x + i] -= depth * w


## The mountain rim beyond the interior: the ground rises to top_m (with its own noise) over
## run_m; notches keep their floor (the shelf, the Broken Stair, the Wend's gap) and their walls
## come from the rim around them.
func _rim(f: HeightField) -> void:
	var run := float(rim.get("run_m", 128.0))
	var top := float(rim.get("top_m", 160.0))
	var amp := float(rim.get("noise_m", 12.0))
	for j in f.size.y:
		var z := f.world_z(j)
		for i in f.size.x:
			var x := f.world_x(i)
			var d := maxf(absf(x), absf(z)) - interior
			var p := Vector2(x, z)
			var notch_w := 0.0
			var notch_floor := 0.0
			for n: Dictionary in notches:
				var q := rect_distance(n.rect, p)
				var w := 1.0 - smoothstep(0.0, float(n.wall), q)
				if w > notch_w:
					notch_w = w
					notch_floor = float(n.floor)
			if d <= 0.0 and notch_w <= 0.0:
				continue
			var k := j * f.size.x + i
			var y: float = f.h[k]
			if d > 0.0:
				var w := smoothstep(0.0, run, d)
				y = lerpf(y, top + rim_noise.get_noise_2d(x, z) * amp, w)
			if notch_w > 0.0:
				y = lerpf(y, notch_floor, notch_w)
			f.h[k] = y


func _ramp(f: HeightField, feat: Dictionary) -> void:
	var a := v2(feat.from)
	var b := v2(feat.to)
	var ya := f.sample(a.x, a.y) if str(feat.get("from_y", "auto")) == "auto" else float(feat.from_y)
	var yb := f.sample(b.x, b.y) if str(feat.get("to_y", "auto")) == "auto" else float(feat.to_y)
	var half := float(feat.get("half_m", 10.0))
	var side := float(feat.get("side_m", 10.0))
	feat["_y"] = [ya, yb]
	var bounds := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (a - b).abs()).grow(half + side)
	var span := _span(f, bounds)
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var r := segment_distance(Vector2(f.world_x(i), z), a, b)
			if r.x >= half + side:
				continue
			var w := 1.0 if r.x <= half else 1.0 - smoothstep(half, half + side, r.x)
			var k := j * f.size.x + i
			f.h[k] = lerpf(f.h[k], lerpf(ya, yb, r.y), w)


func _flatten(f: HeightField, feat: Dictionary) -> void:
	var blend := float(feat.get("blend_m", 20.0))
	var bounds := shape_rect(feat)
	var y := 0.0
	if str(feat.get("y", "auto")) == "auto":
		var span0 := _span(f, bounds)
		var total := 0.0
		var n := 0
		for j in range(span0.position.y, span0.end.y):
			for i in range(span0.position.x, span0.end.x):
				if shape_distance(feat, Vector2(f.world_x(i), f.world_z(j))) <= 0.0:
					total += f.h[j * f.size.x + i]
					n += 1
		y = total / maxf(1.0, float(n))
	else:
		y = float(feat.y)
	feat["_y"] = y
	pads.append(feat)
	var span := _span(f, bounds.grow(blend))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var d := shape_distance(feat, Vector2(f.world_x(i), z))
			if d > blend:
				continue
			var w := 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, blend, d)
			var k := j * f.size.x + i
			f.h[k] = lerpf(f.h[k], y, w)


func _terraces(f: HeightField, feat: Dictionary) -> void:
	var r := rect_of(feat.rect)
	var steps: Array = feat.steps
	var riser := float(feat.get("riser_m", 8.0))
	var blend := float(feat.get("blend_m", 20.0))
	var span := _span(f, r.grow(blend))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		var y := _terrace_height(steps, z, riser)
		for i in range(span.position.x, span.end.x):
			var p := Vector2(f.world_x(i), z)
			var d := rect_distance(r, p)
			if d > blend:
				continue
			var w := 1.0 if d <= 0.0 else 1.0 - smoothstep(0.0, blend, d)
			var k := j * f.size.x + i
			f.h[k] = lerpf(f.h[k], y, w)
	pads.append({"rect": feat.rect})


## The terraces' height at z: each step's height, ramped over `riser` metres between two steps.
static func _terrace_height(steps: Array, z: float, riser: float) -> float:
	# steps: [[z0, z1, y], ...] (any order)
	var best := float(steps[0][2])
	var best_d := INF
	for s: Array in steps:
		var z0 := minf(float(s[0]), float(s[1]))
		var z1 := maxf(float(s[0]), float(s[1]))
		var d := 0.0 if z >= z0 and z <= z1 else minf(absf(z - z0), absf(z - z1))
		if d < best_d:
			best_d = d
			best = float(s[2])
	# ramp across a boundary between steps
	for a: Array in steps:
		for b: Array in steps:
			if a == b:
				continue
			var shared := NAN
			if absf(float(a[1]) - float(b[0])) < 0.01:
				shared = float(a[1])
			if is_nan(shared):
				continue
			if absf(z - shared) <= riser * 0.5:
				var t := smoothstep(shared - riser * 0.5, shared + riser * 0.5, z)
				# a covers z < shared (a = [z0, shared]); b covers z > shared
				return lerpf(float(a[2]), float(b[2]), t) if float(a[0]) < shared else lerpf(float(b[2]), float(a[2]), 1.0 - t)
	return best


func _basin(f: HeightField, feat: Dictionary) -> void:
	var e: Array = feat.ellipse
	var cx := float(e[0])
	var cz := float(e[1])
	var rx := float(e[2])
	var rz := float(e[3])
	var shore := float(feat.get("shore_m", 30.0))
	var from := float(feat.get("edge_from", 0.85))
	var base := 0.0
	if bool(feat.get("relative", false)):
		base = f.sample(cx, cz)
	var bed := base + float(feat.bed_m)
	var edge := base + float(feat.edge_y)
	var surface := base + float(feat.get("surface_m", water_level))
	var mean_r := (rx + rz) * 0.5
	var reach := 1.0 + shore / minf(rx, rz)
	var span := _span(f, Rect2(cx - rx * reach, cz - rz * reach, 2 * rx * reach, 2 * rz * reach))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var x := f.world_x(i)
			var rn := sqrt(pow((x - cx) / rx, 2.0) + pow((z - cz) / rz, 2.0))
			var k := j * f.size.x + i
			if rn <= from:
				f.h[k] = bed
			elif rn <= 1.0:
				f.h[k] = lerpf(bed, edge, smoothstep(from, 1.0, rn))
			else:
				var d := (rn - 1.0) * mean_r
				if d >= shore:
					continue
				f.h[k] = lerpf(edge, maxf(f.h[k], edge), smoothstep(0.0, shore, d))
			if rn <= 1.0:
				water_mask[k] = 1
	water_bodies.append({"id": str(feat.id), "kind": "ellipse", "ellipse": [cx, cz, rx, rz], "surface": surface})


func _channel(f: HeightField, feat: Dictionary) -> void:
	var centre := v2(feat.center)
	var profile: Array = feat.profile
	var r_last := float(profile[profile.size() - 1][0])
	var within: Dictionary = {}
	for b: Dictionary in water_bodies:
		if str(b.id) == str(feat.get("within", "")):
			within = b
	var e: Array = within.get("ellipse", [centre.x, centre.y, r_last, r_last])
	var span := _span(f, Rect2(centre - Vector2(r_last, r_last), Vector2(2 * r_last, 2 * r_last)))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var x := f.world_x(i)
			var r := Vector2(x, z).distance_to(centre)
			if r >= r_last:
				continue
			var rn := sqrt(pow((x - float(e[0])) / float(e[2]), 2.0) + pow((z - float(e[1])) / float(e[3]), 2.0))
			var w := 1.0 - smoothstep(0.9, 1.0, rn)
			if w <= 0.0:
				continue
			var k := j * f.size.x + i
			f.h[k] = lerpf(f.h[k], table_at(profile, r), w)
	var gr: Array = feat.get("gate_r", [])
	if gr.size() == 2:
		gate_rings.append({"center": centre, "r0": float(gr[0]), "r1": float(gr[1]), "bit": int(feat.get("gate_bit", 64)),
			"ellipse": e, "id": str(feat.id)})


func _river(f: HeightField, feat: Dictionary) -> void:
	var pts := _points(feat.points)
	var cum := cumulative(pts)
	var half := float(feat.get("half_bed_m", 3.0))
	var bank := float(feat.get("bank_m", 26.0))
	var bed := float(feat.get("bed_m", -2.0))
	var head_bed := float(feat.get("head_bed_m", bed))
	var head: Array = feat.get("head_m", [0, 0])
	var surface := float(feat.get("surface_m", water_level))
	var bridges: Array = []
	for b: Dictionary in feat.get("bridges", []):
		bridges.append({"id": str(b.id), "rect": rect_of(b.rect)})
	river = {"id": str(feat.id), "points": pts, "cum": cum, "half": half, "bank": bank, "surface": surface,
		"gate_from": float(feat.get("gate_from_m", 0.0)), "gate_d": float(feat.get("gate_d_m", 12.0)),
		"gate_bit": int(feat.get("gate_bit", 32)), "wall_d": float(feat.get("wall_d_m", 12.0)), "bridges": bridges,
		"length": cum[cum.size() - 1]}
	var span := _span(f, _bounds(pts).grow(bank + 2.0))
	for j in range(span.position.y, span.end.y):
		var z := f.world_z(j)
		for i in range(span.position.x, span.end.x):
			var ds := polyline_distance(Vector2(f.world_x(i), z), pts)
			if ds.x >= bank:
				continue
			var s := ds.y
			var y_bed := lerpf(head_bed, bed, smoothstep(float(head[0]), float(head[1]), s))
			var k := j * f.size.x + i
			var ground: float = maxf(f.h[k], surface + 1.0)
			var y := y_bed if ds.x <= half else lerpf(y_bed, ground, smoothstep(half, bank, ds.x))
			f.h[k] = minf(f.h[k], y)
			if f.h[k] < surface:
				water_mask[k] = 1
	water_bodies.append({"id": str(feat.id), "kind": "river", "surface": surface})


## The roads, in the table's order: each carved road is flattened to its smoothed profile (the
## ground along it averaged over smooth_m on both sides), never over water, then reported with
## its steepest grade.
func _roads(f: HeightField) -> void:
	var smooth := float(road_rules.get("smooth_m", 40.0))
	var blend := float(road_rules.get("blend_m", 12.0))
	var step := float(road_rules.get("sample_m", 4.0))
	var grades := {}
	for road: Dictionary in roads:
		var pts: PackedVector2Array = road.points
		var cum := cumulative(pts)
		var length := cum[cum.size() - 1]
		var n := maxi(2, int(ceil(length / step)) + 1)
		var raw := PackedFloat32Array()
		raw.resize(n)
		var ss := PackedFloat32Array()
		ss.resize(n)
		for k in n:
			var s := length * float(k) / float(n - 1)
			ss[k] = s
			var p := point_at(pts, cum, s)
			raw[k] = f.sample(p.x, p.y)
		var prof := PackedFloat32Array()
		prof.resize(n)
		var win := maxi(0, int(roundf(smooth / (length / float(n - 1)))))
		for k in n:
			var total := 0.0
			var cnt := 0
			for m in range(maxi(0, k - win), mini(n, k + win + 1)):
				total += raw[m]
				cnt += 1
			prof[k] = total / float(cnt)
		if bool(road.carve):
			prof = grade_limited(prof, ss, float(road_rules.get("grade_max", 0.12)))
		var gmax := 0.0
		for k in range(1, n):
			gmax = maxf(gmax, absf(prof[k] - prof[k - 1]) / maxf(ss[k] - ss[k - 1], 1e-6))
		road_profiles[str(road.id)] = {"s": ss, "y": prof, "length": length, "grade_max": gmax, "cum": cum}
		grades[str(road.id)] = snappedf(gmax, 0.001)
		if not bool(road.carve):
			continue
		var half := float(road.width) * 0.5
		var span := _span(f, _bounds(pts).grow(half + blend))
		for j in range(span.position.y, span.end.y):
			var z := f.world_z(j)
			for i in range(span.position.x, span.end.x):
				var k := j * f.size.x + i
				var p := Vector2(f.world_x(i), z)
				if water_mask[k] != 0 and not on_bridge(p):
					continue
				var ds := polyline_distance(p, pts)
				if ds.x >= half + blend:
					continue
				var t := clampf(ds.y / maxf(length, 1e-6), 0.0, 1.0) * float(n - 1)
				var k0 := clampi(int(floor(t)), 0, n - 1)
				var k1 := mini(k0 + 1, n - 1)
				var target := lerpf(prof[k0], prof[k1], t - float(k0))
				var w := 1.0 if ds.x <= half else 1.0 - smoothstep(half, half + blend, ds.x)
				f.h[k] = lerpf(f.h[k], target, w)
	report["road_grade_max"] = grades


## A profile whose grade nowhere exceeds `g`, kept centred on `y`: the mean of its cut-only
## envelope (peaks lowered until no stretch is steeper than g) and its fill-only envelope (hollows
## raised the same way). Both are g-limited, and so is their mean.
static func grade_limited(y: PackedFloat32Array, s: PackedFloat32Array, g: float) -> PackedFloat32Array:
	var n := y.size()
	var lo := y.duplicate()
	var hi := y.duplicate()
	for k in range(1, n):
		var d := g * (s[k] - s[k - 1])
		lo[k] = minf(lo[k], lo[k - 1] + d)
		hi[k] = maxf(hi[k], hi[k - 1] - d)
	for k in range(n - 2, -1, -1):
		var d := g * (s[k + 1] - s[k])
		lo[k] = minf(lo[k], lo[k + 1] + d)
		hi[k] = maxf(hi[k], hi[k + 1] - d)
	var out := PackedFloat32Array()
	out.resize(n)
	for k in n:
		out[k] = (lo[k] + hi[k]) * 0.5
	return out


static func _points(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


static func _bounds(pts: PackedVector2Array) -> Rect2:
	var lo := pts[0]
	var hi := pts[0]
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


# --------------------------------------------------------------------------- questions about the ground

## True on a bridge deck (the river's bridges).
func on_bridge(p: Vector2) -> bool:
	for b: Dictionary in river.get("bridges", []):
		if (b.rect as Rect2).has_point(p):
			return true
	return false


## The river's distance and arc length at (x, z): Vector2(d, s); (INF, 0) without a river.
func river_at(x: float, z: float) -> Vector2:
	if river.is_empty():
		return Vector2(INF, 0.0)
	return polyline_distance(Vector2(x, z), river.points)


## The titan gate bit of the ground at (x, z): the Wend's deep bed (32, stage 4), the Mere's deep
## channel (64, stage 5), the gate rectangles the layout adds (the Giant's Stair, the Moot's gate:
## 128, stage 6); the highest wins; 0 elsewhere.
func gate_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	var best := 0
	for g: Dictionary in gate_rects:
		if (g.rect as Rect2).has_point(p):
			best = maxi(best, int(g.bit))
	for g: Dictionary in gate_rings:
		var r := p.distance_to(g.center)
		if r < float(g.r0) or r > float(g.r1):
			continue
		var e: Array = g.ellipse
		var rn := sqrt(pow((x - float(e[0])) / float(e[2]), 2.0) + pow((z - float(e[1])) / float(e[3]), 2.0))
		if rn <= 1.02:
			best = maxi(best, int(g.bit))
	if not river.is_empty() and best < int(river.gate_bit):
		var ds := river_at(x, z)
		if ds.x < float(river.gate_d) and ds.y >= float(river.gate_from) and not on_bridge(p):
			best = maxi(best, int(river.gate_bit))
	return best


## True where navigation is baked and the border rule applies: inside the rim, and in the
## walkable notches (the Kingsgate shelf, the Broken Stair).
func walkable(x: float, z: float) -> bool:
	if absf(x) < interior and absf(z) < interior:
		return true
	var p := Vector2(x, z)
	for n: Dictionary in notches:
		if bool(n.walkable) and (n.rect as Rect2).has_point(p):
			return true
	return false


## The 1-based index of the region at (x, z) in region_ids (the point clamped into the interior;
## the regions tile it).
func region_index(x: float, z: float) -> int:
	var p := Vector2(clampf(x, -interior + 0.01, interior - 0.01), clampf(z, -interior + 0.01, interior - 0.01))
	for k in regions.size():
		if (regions[k].rect as Rect2).has_point(p):
			return k + 1
	var best := 0
	var best_d := INF
	for k in regions.size():
		var d := rect_distance(regions[k].rect, p)
		if d < best_d:
			best_d = d
			best = k + 1
	return best


func region_id_at(x: float, z: float) -> String:
	var k := region_index(x, z)
	return region_ids[k - 1] if k > 0 else ""


## The water surface over (x, z) when the ground there lies under it, else NAN.
func water_surface_at(f: HeightField, x: float, z: float) -> float:
	var g := f.sample(x, z)
	for b: Dictionary in water_bodies:
		var s := float(b.surface)
		if g >= s - WATER_MIN_DEPTH_M:
			continue
		match str(b.kind):
			"ellipse":
				var e: Array = b.ellipse
				var rn := sqrt(pow((x - float(e[0])) / float(e[2]), 2.0) + pow((z - float(e[1])) / float(e[3]), 2.0))
				if rn <= 1.05:
					return s
			"river":
				if river_at(x, z).x < float(river.bank) and not on_bridge(Vector2(x, z)):
					return s
	return NAN


## The water of the world as rectangles (world x, z) with their surface: every WATER_CELL_M cell
## whose ground lies under a body's surface at one of its corners, merged into runs along x.
func water_world(f: HeightField) -> Array:
	var out: Array = []
	var c := WATER_CELL_M
	var r := world_rect()
	var nx := int(r.size.x / c)
	var nz := int(r.size.y / c)
	for jz in nz:
		var z := r.position.y + jz * c
		var run_start := -1
		var run_surface := NAN
		for ix in nx + 1:
			var s := NAN
			if ix < nx:
				var x := r.position.x + ix * c
				for corner: Vector2 in [Vector2(x + 1, z + 1), Vector2(x + c - 1, z + 1), Vector2(x + 1, z + c - 1),
						Vector2(x + c - 1, z + c - 1), Vector2(x + c * 0.5, z + c * 0.5)]:
					var ws := water_surface_at(f, corner.x, corner.y)
					if not is_nan(ws):
						s = ws
						break
			if run_start >= 0 and (is_nan(s) or absf(s - run_surface) > 0.01):
				out.append({"rect": Rect2(r.position.x + run_start * c, z, (ix - run_start) * c, c), "surface_y": run_surface})
				run_start = -1
			if not is_nan(s) and run_start < 0:
				run_start = ix
				run_surface = s
	return out


## The surface kind of the 16 m cell around (x, z): wet on and by the water, hard on roads, pads,
## the rim, steep and rocky ground and in the Stonehold, else the region's surface.
func surface_kind(f: HeightField, x: float, z: float) -> int:
	if not is_nan(water_surface_at(f, x, z)):
		return SURFACE_WET
	if not walkable(x, z):
		return SURFACE_HARD
	var p := Vector2(x, z)
	for road: Dictionary in roads:
		if bool(road.carve) and polyline_distance(p, road.points).x <= float(road.width) * 0.5:
			return SURFACE_HARD
	if slope_deg(f, x, z) > HARD_SLOPE_DEG:
		return SURFACE_HARD
	var k := region_index(x, z)
	var surf := str(regions[k - 1].surface) if k > 0 else "soft"
	return int(SURFACE_IDS.get(surf, SURFACE_SOFT))


## The steepest face of the field's cell holding (x, z), in degrees.
static func slope_deg(f: HeightField, x: float, z: float) -> float:
	var i := int(floor((x - f.origin.x) / f.spacing))
	var j := int(floor((z - f.origin.y) / f.spacing))
	return f.cell_slope_deg(clampi(i, 0, f.size.x - 2), clampi(j, 0, f.size.y - 2))


## The border rule's walkable test for relax_borders: navigable ground (walkable) that is no
## cliff (the giant's floor angle): cliffs and the rim are left as they are.
func border_walkable(f: HeightField, x: float, z: float) -> bool:
	return walkable(x, z) and slope_deg(f, x, z) <= CLIFF_DEG


## The border band's slope limit for soften_borders (under HeightField.BORDER_MAX_DEG, so 4 mm
## quantisation keeps it), and the limit of the transition beside the band (under CLIFF_DEG, so no
## walkable face becomes a cliff).
const SOFTEN_BAND_DEG := 34.8
const SOFTEN_TRANSITION_DEG := 44.6
const SOFTEN_TRANSITION_M := 36.0
const SOFTEN_MAX_SWEEPS := 60
const SOFTEN_ROUNDS := 4
## A band cell the pass cannot bring under the rule becomes part of a cliff when it is beside one
## or at least this steep.
const SOFTEN_PUSH_FROM_DEG := 40.0

## The border rule on a hilly world: Laplacian relaxation (HeightField.relax_borders) cannot bend a
## planar slope of 35 to 45 degrees (a hill's flank, a river bank, a cliff's shoulder) that crosses
## a chunk border. This pass limits the slope instead: every walkable cell of the border band (the
## cells HeightField.border_report checks) is brought to SOFTEN_BAND_DEG by projecting its
## triangles' gradients onto the limit, the height it loses or gains is pushed into a transition of
## SOFTEN_TRANSITION_M beside the band (held under SOFTEN_TRANSITION_DEG), and everything else stays
## put: the samples of cliffs (steeper than CLIFF_DEG before the pass), of the rim and beyond the
## transition are pinned. Deterministic (cells in index order). {"ok", "sweeps", "cells" (band cells
## still over the rule), "moved" (samples changed)}.
func soften_borders(f: HeightField) -> Dictionary:
	var first := field_first()
	var cells := int(roundf(chunk_m / spacing))
	var xs := HeightField.border_lines(first.x, cells, grid.x)
	var zs := HeightField.border_lines(first.y, cells, grid.y)
	var band := int(ceil(HeightField.BORDER_BAND_M / spacing))
	var trans := int(ceil(SOFTEN_TRANSITION_M / spacing))
	var start := f.h.duplicate()
	var band_lim := tan(deg_to_rad(SOFTEN_BAND_DEG)) * spacing
	var trans_lim := tan(deg_to_rad(SOFTEN_TRANSITION_DEG)) * spacing
	var cliff_lim := tan(deg_to_rad(CLIFF_DEG)) * spacing
	var rule_lim := tan(deg_to_rad(HeightField.BORDER_MAX_DEG + HeightField.SLOPE_EPS_DEG)) * spacing
	var nx := f.size.x
	# cell kinds: 0 outside the zone, a cliff or the rim (its samples pinned), 1 band, 2 transition
	var kinds := PackedByteArray()
	kinds.resize(f.h.size())
	kinds.fill(255)
	var ctx := {"f": f, "kinds": kinds, "start": start, "xs": xs, "zs": zs, "band": band, "trans": trans,
		"cliff": cliff_lim, "nx": nx}
	var active := {}
	for j in f.size.y - 1:
		var row_band := HeightField._near(j, zs, band)
		for i in f.size.x - 1:
			if (row_band or HeightField._near(i, xs, band)) and _soften_kind(ctx, i, j) == 1:
				if _cell_grad(f.h, nx, i, j) > band_lim:
					active[j * nx + i] = true
	var moved := {}
	var sweeps := 0
	var pushed := 0
	var left: Array = []
	var push_lim := tan(deg_to_rad(CLIFF_DEG + 0.8)) * spacing
	var push_from := tan(deg_to_rad(SOFTEN_PUSH_FROM_DEG)) * spacing
	var cliff_now := tan(deg_to_rad(CLIFF_DEG + 0.05)) * spacing
	for _r in SOFTEN_ROUNDS:
		sweeps += _soften_sweeps(ctx, active, band_lim, trans_lim, moved)
		left = _soften_left(ctx, rule_lim)
		if left.is_empty():
			break
		# a band cell still over the rule beside a cliff (it shares the cliff's steep edge) or nearly a
		# cliff itself becomes part of the cliff (steeper than CLIFF_DEG: no walkable face) and its
		# neighbours go again; the others go again as they are
		active = {}
		for key: int in left:
			var i := key % nx
			var j := key / nx
			active[key] = true
			if not _beside_pinned(ctx, i, j) and _cell_grad(f.h, nx, i, j) < push_from:
				continue
			var tris := [[[Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1)], [-1.0, 1.0, 0.0], [0.0, -1.0, 1.0]],
				[[Vector2i(i, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)], [0.0, -1.0, 1.0], [-1.0, 1.0, 0.0]]]
			# the steeper triangle is pushed
			var t: Array = tris[0] if _tri_grad(f, tris[0]) >= _tri_grad(f, tris[1]) else tris[1]
			_project_triangle(ctx, t[0], t[1], t[2], push_lim, moved, true)
			if _cell_grad(f.h, nx, i, j) > cliff_now:
				kinds[key] = 0
				pushed += 1
				for dj in range(-1, 2):
					for di in range(-1, 2):
						if _soften_kind(ctx, i + di, j + dj) > 0:
							active[(j + dj) * nx + i + di] = true
	var nudged := 0
	if not left.is_empty():
		nudged = _soften_nudge(ctx, left, rule_lim, moved)
		left = _soften_left(ctx, rule_lim)
	return {"ok": left.is_empty(), "sweeps": sweeps, "cells": left.size(), "moved": moved.size(), "pushed": pushed,
		"nudged": nudged, "first": _soften_where(f, left)}


## The last resort of soften_borders for band cells it could not settle (a walkable sliver inside a
## cliff, every sample pinned): greedy nudges of their samples (pins ignored, the rim and beyond the
## zone excepted) by up to 2 m, each kept only when the band cells around the sample end farther
## from the rule (a face over 35 and under 45 degrees counts by how far it is from either). The
## number of nudges made.
func _soften_nudge(ctx: Dictionary, left: Array, rule_lim: float, moved: Dictionary) -> int:
	var f: HeightField = ctx.f
	var nx := int(ctx.nx)
	var nudges := 0
	var steps := [0.25, -0.25, 0.5, -0.5, 1.0, -1.0, 2.0, -2.0]
	for _pass in 6:
		var any := false
		for key: int in left:
			var i := key % nx
			var j := key / nx
			for v: Vector2i in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
				if not _soften_movable(ctx, v):
					continue
				var h0 := f.at(v.x, v.y)
				var best := _vertex_penalty(ctx, v)
				if best <= 0.0:
					continue
				var best_h := h0
				for d: float in steps:
					f.set_at(v.x, v.y, h0 + d)
					var p := _vertex_penalty(ctx, v)
					if p < best - 1e-4:
						best = p
						best_h = h0 + d
				f.set_at(v.x, v.y, best_h)
				if best_h != h0:
					moved[v.y * nx + v.x] = true
					nudges += 1
					any = true
		if not any:
			break
	return nudges


## A sample the nudges may move: the four cells around it inside the zone and walkable ground.
func _soften_movable(ctx: Dictionary, v: Vector2i) -> bool:
	var f: HeightField = ctx.f
	for c: Vector2i in [Vector2i(v.x - 1, v.y - 1), Vector2i(v.x, v.y - 1), Vector2i(v.x - 1, v.y), Vector2i(v.x, v.y)]:
		if c.x < 0 or c.y < 0 or c.x >= f.size.x - 1 or c.y >= f.size.y - 1:
			return false
		var band := int(ctx.band)
		var outer := band + int(ctx.trans)
		if not (HeightField._near(c.x, ctx.xs, outer) or HeightField._near(c.y, ctx.zs, outer)):
			return false
		if not walkable(f.world_x(c.x) + spacing * 0.5, f.world_z(c.y) + spacing * 0.5):
			return false
	return true


## How far the band cells around sample v are from the border rule (0 when none breaks it).
func _vertex_penalty(ctx: Dictionary, v: Vector2i) -> float:
	var f: HeightField = ctx.f
	var nx := int(ctx.nx)
	var band := int(ctx.band)
	var total := 0.0
	for c: Vector2i in [Vector2i(v.x - 1, v.y - 1), Vector2i(v.x, v.y - 1), Vector2i(v.x - 1, v.y), Vector2i(v.x, v.y)]:
		if not (HeightField._near(c.x, ctx.xs, band) or HeightField._near(c.y, ctx.zs, band)):
			continue
		var deg := rad_to_deg(atan(_cell_grad(f.h, nx, c.x, c.y) / spacing))
		if deg > SOFTEN_BAND_DEG and deg <= CLIFF_DEG + 0.3:
			total += 1.0 + minf(deg - SOFTEN_BAND_DEG, CLIFF_DEG + 0.3 - deg)
	return total


## Sweeps of soften_borders over the active cells until none moves (or SOFTEN_MAX_SWEEPS); the count.
func _soften_sweeps(ctx: Dictionary, active: Dictionary, band_lim: float, trans_lim: float, moved: Dictionary) -> int:
	var nx := int(ctx.nx)
	var sweeps := 0
	while not active.is_empty() and sweeps < SOFTEN_MAX_SWEEPS:
		sweeps += 1
		var keys := active.keys()
		keys.sort()
		active.clear()
		for key: int in keys:
			var i := key % nx
			var j := key / nx
			var k := _soften_kind(ctx, i, j)
			if k == 0:
				continue
			var lim := (band_lim if k == 1 else trans_lim) * 0.998
			# triangle A (00, 10, 11): gx = h10 - h00, gz = h11 - h10; B (00, 01, 11): gx = h11 - h01, gz = h01 - h00
			var a := _project_triangle(ctx, [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1)],
				[-1.0, 1.0, 0.0], [0.0, -1.0, 1.0], lim, moved)
			var b := _project_triangle(ctx, [Vector2i(i, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)],
				[0.0, -1.0, 1.0], [-1.0, 1.0, 0.0], lim, moved)
			if a or b:
				for dj in range(-1, 2):
					for di in range(-1, 2):
						if _soften_kind(ctx, i + di, j + dj) > 0:
							active[(j + dj) * nx + i + di] = true
	return sweeps


## The band cells of soften_borders still over the rule (cell keys, in order).
func _soften_left(ctx: Dictionary, rule_lim: float) -> Array:
	var f: HeightField = ctx.f
	var nx := int(ctx.nx)
	var band := int(ctx.band)
	var cliff_lim := float(ctx.cliff)
	var out: Array = []
	for j in f.size.y - 1:
		var row_band := HeightField._near(j, ctx.zs, band)
		for i in f.size.x - 1:
			if not (row_band or HeightField._near(i, ctx.xs, band)):
				continue
			# HeightField.border_report's test with border_walkable: walkable ground, no cliff
			var g := _cell_grad(f.h, nx, i, j)
			if g > rule_lim and g <= cliff_lim and walkable(f.world_x(i) + spacing * 0.5, f.world_z(j) + spacing * 0.5):
				out.append(j * nx + i)
	return out


## True when one of the eight cells around (i, j) is pinned (a cliff, the rim).
func _beside_pinned(ctx: Dictionary, i: int, j: int) -> bool:
	for dj in range(-1, 2):
		for di in range(-1, 2):
			if (di != 0 or dj != 0) and _soften_kind(ctx, i + di, j + dj) == 0:
				return true
	return false


## The world position of the first cell key in `keys` (Vector2.INF when none).
static func _soften_where(f: HeightField, keys: Array) -> Vector2:
	if keys.is_empty():
		return Vector2.INF
	var key: int = keys[0]
	return Vector2(f.world_x(key % f.size.x) + f.spacing * 0.5, f.world_z(key / f.size.x) + f.spacing * 0.5)


## A triangle's gradient length ([vertices, gx coefficients, gz coefficients]).
static func _tri_grad(f: HeightField, t: Array) -> float:
	var gx := 0.0
	var gz := 0.0
	for k in 3:
		var hv := f.at(t[0][k].x, t[0][k].y)
		gx += float(t[1][k]) * hv
		gz += float(t[2][k]) * hv
	return Vector2(gx, gz).length()


## The kind of cell (i, j) for soften_borders, from the heights before the pass (memoised).
func _soften_kind(ctx: Dictionary, i: int, j: int) -> int:
	var f: HeightField = ctx.f
	if i < 0 or j < 0 or i >= f.size.x - 1 or j >= f.size.y - 1:
		return 0
	var kinds: PackedByteArray = ctx.kinds
	var nx := int(ctx.nx)
	var key := j * nx + i
	if kinds[key] != 255:
		return kinds[key]
	var k := 0
	var band := int(ctx.band)
	var outer := band + int(ctx.trans)
	if HeightField._near(i, ctx.xs, band) or HeightField._near(j, ctx.zs, band):
		k = 1
	elif HeightField._near(i, ctx.xs, outer) or HeightField._near(j, ctx.zs, outer):
		k = 2
	if k > 0:
		var cx := f.world_x(i) + spacing * 0.5
		var cz := f.world_z(j) + spacing * 0.5
		if not walkable(cx, cz) or _cell_grad(ctx.start, nx, i, j) > float(ctx.cliff):
			k = 0
	kinds[key] = k
	return k


## A sample moves only when the four cells around it are in the zone and none is a cliff.
func _soften_free(ctx: Dictionary, v: Vector2i) -> bool:
	return _soften_kind(ctx, v.x - 1, v.y - 1) > 0 and _soften_kind(ctx, v.x, v.y - 1) > 0 \
		and _soften_kind(ctx, v.x - 1, v.y) > 0 and _soften_kind(ctx, v.x, v.y) > 0


## The steeper triangle gradient of cell (i, j) of heights `h` (row length nx), as a height
## difference over one sample spacing.
static func _cell_grad(h: PackedFloat32Array, nx: int, i: int, j: int) -> float:
	var h00 := h[j * nx + i]
	var h10 := h[j * nx + i + 1]
	var h01 := h[(j + 1) * nx + i]
	var h11 := h[(j + 1) * nx + i + 1]
	return maxf(Vector2(h10 - h00, h11 - h10).length(), Vector2(h11 - h01, h01 - h00).length())


## Brings one triangle's gradient (gx = m1 . heights, gz = m2 . heights) down to `lim` (up to it
## with `up`) with the least change of its free samples; true when a sample moved.
func _project_triangle(ctx: Dictionary, vs: Array, m1: Array, m2: Array, lim: float, moved: Dictionary,
		up := false) -> bool:
	var f: HeightField = ctx.f
	var gx := 0.0
	var gz := 0.0
	for k in 3:
		var hv := f.at(vs[k].x, vs[k].y)
		gx += float(m1[k]) * hv
		gz += float(m2[k]) * hv
	var g := Vector2(gx, gz).length()
	if (g >= lim) if up else (g <= lim):
		return false
	if g < 1e-6:
		return false
	var d := Vector2(gx, gz) * (lim / g - 1.0)
	var a11 := 0.0
	var a12 := 0.0
	var a22 := 0.0
	var fr := [false, false, false]
	for k in 3:
		if _soften_free(ctx, vs[k]):
			fr[k] = true
			a11 += float(m1[k]) * float(m1[k])
			a12 += float(m1[k]) * float(m2[k])
			a22 += float(m2[k]) * float(m2[k])
	var det := a11 * a22 - a12 * a12
	var y := Vector2.ZERO
	if det > 1e-6:
		y = Vector2((a22 * d.x - a12 * d.y) / det, (a11 * d.y - a12 * d.x) / det)
	elif a11 + a22 > 1e-6:
		y = d / (a11 + a22)
	else:
		return false
	var any := false
	for k in 3:
		if not fr[k]:
			continue
		var dh := float(m1[k]) * y.x + float(m2[k]) * y.y
		if absf(dh) < 1e-6:
			continue
		var v: Vector2i = vs[k]
		f.set_at(v.x, v.y, f.at(v.x, v.y) + dh)
		moved[v.y * f.size.x + v.x] = true
		any = true
	return any


## The chunk cell holding (x, z).
func chunk_of_point(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor((x - origin.x) / chunk_m)), int(floor((z - origin.y) / chunk_m)))


func chunk_id_of(x: float, z: float) -> String:
	var c := chunk_of_point(x, z)
	if c.x < 0 or c.y < 0 or c.x >= grid.x or c.y >= grid.y:
		return ""
	return ChunkData.id_for(c)


## The skyline tint of a region (by 1-based index).
func skyline_tint(k: int) -> Color:
	if k <= 0 or k > regions.size():
		return Color(0.35, 0.38, 0.3)
	var t: Array = regions[k - 1].skyline_tint
	return Color(float(t[0]), float(t[1]), float(t[2]))
