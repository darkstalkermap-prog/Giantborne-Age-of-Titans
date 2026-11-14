class_name WorldMapRender
extends RefCounted
## The world's map picture (P25; plan M6-M9 §3.8, decision 14): one PNG of the whole level drawn
## from the same heights the chunks hold - a hillshade lit from the north-west over the regions'
## map tints, the water, the roads, the rim's mountains and the footprints of settlements and
## landmarks - for P27's map screen (WorldIndex.map_image, map_bounds). The shading is quantised to
## a few bands so the picture stays small (the plan's 300 KB). Tools only.

## Pixels per side of the saved picture.
const SIZE := 1024
## The picture is drawn at this size and scaled up (the field holds a sample every 4 m).
const DRAW_SIZE := 512
## Hillshade bands (fewer bands: a smaller file).
const SHADE_BANDS := 9
const LIGHT := Vector3(-0.55, 0.75, -0.55)
const WATER := Color(0.27, 0.41, 0.52)
const WATER_DEEP := Color(0.2, 0.32, 0.44)
const ROAD := Color(0.62, 0.55, 0.42)
const RIDE := Color(0.5, 0.52, 0.36)
const RIM := Color(0.43, 0.41, 0.4)
const FOOTPRINT := Color(0.33, 0.27, 0.22)
const LANDMARK := Color(0.24, 0.21, 0.2)


## The picture: `tints` maps a 1-based region index to its colour (the region records' map_tint);
## `footprints` are [{"poly": PackedVector2Array (x, z)} | {"rect": Rect2 (x, z)} |
## {"circle": Vector3 (x, z, r)}, "color": Color (else by "landmark": bool)], drawn in order.
static func render(feats: WorldFeatures, field: HeightField, tints: Dictionary, footprints: Array) -> Image:
	var world := feats.world_rect()
	var n := DRAW_SIZE
	var px := world.size.x / float(n)
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var light := LIGHT.normalized()
	for j in n:
		var z := world.position.y + (j + 0.5) * px
		for i in n:
			var x := world.position.x + (i + 0.5) * px
			var h := field.sample(x, z)
			var dx := field.sample(x + 4.0, z) - field.sample(x - 4.0, z)
			var dz := field.sample(x, z + 4.0) - field.sample(x, z - 4.0)
			var nrm := Vector3(-dx, 8.0, -dz).normalized()
			var shade := clampf(nrm.dot(light), 0.0, 1.0)
			shade = roundf(shade * SHADE_BANDS) / SHADE_BANDS
			var base: Color
			if not feats.walkable(x, z):
				base = RIM
			else:
				base = tints.get(feats.region_index(x, z), Color(0.4, 0.45, 0.32))
			var c := base * (0.55 + 0.6 * shade)
			var ws := feats.water_surface_at(field, x, z)
			if not is_nan(ws):
				c = WATER_DEEP if ws - h > 4.0 else WATER
			img.set_pixel(i, j, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1)))
	for road: Dictionary in feats.roads:
		if bool(road.get("ride", false)):
			_draw_polyline(img, world, road.points, 2.0, RIDE)
		else:
			_draw_polyline(img, world, road.points, minf(float(road.width), 18.0) * 0.5, ROAD)
	for fp: Dictionary in footprints:
		_draw_footprint(img, world, fp)
	img.resize(SIZE, SIZE, Image.INTERPOLATE_NEAREST)
	return img


static func _to_px(world: Rect2, n: int, p: Vector2) -> Vector2:
	return (p - world.position) / world.size * float(n)


static func _draw_polyline(img: Image, world: Rect2, pts: PackedVector2Array, half_m: float, color: Color) -> void:
	var n := img.get_width()
	var r := maxf(0.6, half_m / world.size.x * float(n))
	for k in pts.size() - 1:
		var a := _to_px(world, n, pts[k])
		var b := _to_px(world, n, pts[k + 1])
		var steps := maxi(1, int(ceil(a.distance_to(b) / 0.5)))
		for s in steps + 1:
			_disc(img, a.lerp(b, float(s) / steps), r, color)


static func _disc(img: Image, c: Vector2, r: float, color: Color) -> void:
	var n := img.get_width()
	for j in range(int(floor(c.y - r)), int(ceil(c.y + r)) + 1):
		for i in range(int(floor(c.x - r)), int(ceil(c.x + r)) + 1):
			if i < 0 or j < 0 or i >= n or j >= n:
				continue
			if Vector2(i + 0.5, j + 0.5).distance_to(c) <= r:
				img.set_pixel(i, j, color)


static func _draw_footprint(img: Image, world: Rect2, fp: Dictionary) -> void:
	var n := img.get_width()
	var color: Color = fp.get("color", LANDMARK if bool(fp.get("landmark", false)) else FOOTPRINT)
	if fp.has("poly"):
		var poly := PackedVector2Array()
		for q: Vector2 in fp.poly:
			poly.append(_to_px(world, n, q))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in poly:
			lo = lo.min(q)
			hi = hi.max(q)
		var drawn := false
		for j in range(maxi(0, int(floor(lo.y))), mini(n, int(ceil(hi.y)) + 1)):
			for i in range(maxi(0, int(floor(lo.x))), mini(n, int(ceil(hi.x)) + 1)):
				if Geometry2D.is_point_in_polygon(Vector2(i + 0.5, j + 0.5), poly):
					img.set_pixel(i, j, color)
					drawn = true
		# a part smaller than a pixel still shows
		if not drawn:
			var c := (lo + hi) * 0.5
			if c.x >= 0 and c.y >= 0 and c.x < n and c.y < n and (hi - lo).length() > 0.35:
				img.set_pixel(int(c.x), int(c.y), color)
		return
	if fp.has("circle"):
		var c: Vector3 = fp.circle
		_disc(img, _to_px(world, n, Vector2(c.x, c.y)), maxf(0.8, c.z / world.size.x * float(n)), color)
		return
	var r: Rect2 = fp.rect
	var a := _to_px(world, n, r.position)
	var b := _to_px(world, n, r.end)
	for j in range(int(floor(a.y)), int(ceil(b.y)) + 1):
		for i in range(int(floor(a.x)), int(ceil(b.x)) + 1):
			if i >= 0 and j >= 0 and i < n and j < n:
				img.set_pixel(i, j, color)


## Saves the picture as PNG; returns the error code.
static func save(img: Image, path: String) -> int:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	return img.save_png(path)
