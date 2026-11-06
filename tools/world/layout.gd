class_name WorldLayout
extends RefCounted
## The world's layout tables (P25; plan M6-M9 §2.7, §5.4): tools/data/world/world.json (the frame,
## terrain, water, roads) and one table per region (crownmarch, greywood, drowned_steps, aldmere,
## stonehold) holding its `elements` and the scripted places: `shrines`, `waystones`, `checkpoints`,
## `exits`, `size_gates`, `secrets` (the seals of sealed places), `caches`, `cairns`, `markers` (safe
## markers included), `areas`, `greens` and `scenery` rules. load_all() merges them and checks ids;
## the world builder places them.
##
## Elements are built by kinds: tools/world/kinds/<kind>.gd, each with
##   static func parts(el, ctx) -> Array            visual parts in the element's frame (see below)
##   static func solids(el, ctx) -> Array           collision and navigation obstacles, same frame
##   static func build(kit, el, ctx) -> Node3D      a node of the element (scripted kinds: their scene)
## and `const SCRIPTED := true` for kinds whose build() is a scripted node that goes into the chunk's
## props sub-scene (caches, cairns, gates); the static kinds' parts are merged into one
## vertex-coloured mesh per chunk (one draw call, drawn to the terrain's distance). A region package
## adds a kind by adding its file.
##
## An element: {"kind", "id" (a world id when it is persistent or a landmark), "pos": [x, z],
## "yaw" (degrees; 0 faces -Z), "y_off", "size": [...], "style", "poi", "landmark", "skyline",
## "quest_critical", "indestructible", "visible_when_flag", "hidden_when_flag", ...kind fields}.
## Its frame: the origin on the ground at pos (or y_off above it), turned by yaw.
##
## A part: {"shape": "box" | "cyl" | "cone" | "frustum" | "roof" | "pyramid" | "sphere",
## "pos": Vector3 (the base centre), "size": Vector3, "yaw" (degrees), "tilt": Vector3 (degrees,
## x and z), "color": a PALETTE key or a Color}. A solid: {"shape": "box" | "cyl", "center": Vector3,
## "size": Vector3 (cyl: diameter, height, -), "yaw" (degrees)}.

const DATA_DIR := "res://tools/data/world/"
const WORLD_FILE := "world.json"
const REGION_FILES := ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]
const KINDS_DIR := "res://tools/world/kinds/"
## The id pattern of world ids, checkpoint ids, exits, markers, areas (plan §2.3).
const ID_REGEX := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"
const SECTIONS := ["elements", "shrines", "waystones", "checkpoints", "exits", "size_gates", "secrets", "caches",
	"cairns", "markers", "areas", "greens", "pines", "signs"]

## The vertex colours of the structures (sRGB).
const PALETTE := {
	"stone": Color(0.56, 0.55, 0.53), "stone_dark": Color(0.4, 0.39, 0.38), "stone_light": Color(0.7, 0.68, 0.63),
	"plaster": Color(0.8, 0.74, 0.62), "timber": Color(0.45, 0.33, 0.2), "timber_dark": Color(0.3, 0.22, 0.14),
	"thatch": Color(0.66, 0.56, 0.32), "roof_red": Color(0.5, 0.25, 0.18), "roof_slate": Color(0.32, 0.33, 0.37),
	"bone": Color(0.86, 0.83, 0.74), "bone_dark": Color(0.64, 0.6, 0.52), "canvas": Color(0.78, 0.73, 0.6),
	"canvas_red": Color(0.62, 0.22, 0.18), "iron": Color(0.3, 0.3, 0.32), "moss": Color(0.33, 0.4, 0.27),
	"grass": Color(0.42, 0.52, 0.28), "crop": Color(0.74, 0.66, 0.34), "crop_green": Color(0.45, 0.58, 0.3),
	"soil": Color(0.42, 0.32, 0.22), "rune": Color(0.5, 0.72, 0.8), "gold": Color(0.85, 0.66, 0.24),
	"fire": Color(0.95, 0.55, 0.2), "dark": Color(0.06, 0.06, 0.07), "water": Color(0.3, 0.45, 0.55),
	"banner_blue": Color(0.2, 0.3, 0.55), "banner_green": Color(0.2, 0.4, 0.25), "pine": Color(0.24, 0.33, 0.27),
	"leaves": Color(0.28, 0.42, 0.22), "bark": Color(0.33, 0.25, 0.18), "rock": Color(0.5, 0.49, 0.46),
	"heather": Color(0.45, 0.33, 0.45), "reed": Color(0.55, 0.58, 0.36), "black": Color(0.12, 0.12, 0.13),
}

static var _kinds: Dictionary = {}


# --------------------------------------------------------------------------- loading

## The merged layout: {"world": world.json, "regions": {region short: table}, "items": [every
## element and place with "_region" and "_section"], "errors": PackedStringArray}.
static func load_all(dir := DATA_DIR) -> Dictionary:
	var out := {"world": WorldFeatures.load_json(dir.path_join(WORLD_FILE)), "regions": {}, "items": [],
		"errors": PackedStringArray()}
	var seen := {}
	for r: String in REGION_FILES:
		var path := dir.path_join(r + ".json")
		var t := WorldFeatures.load_json(path)
		if t.is_empty():
			(out.errors as PackedStringArray).append("%s is missing or not a JSON object" % path)
			continue
		out.regions[r] = t
		for section: String in SECTIONS:
			for item: Dictionary in t.get(section, []):
				item["_region"] = r
				item["_section"] = section
				(out.items as Array).append(item)
				var id := str(item.get("id", ""))
				if id == "":
					continue
				if seen.has(id):
					(out.errors as PackedStringArray).append("duplicate id '%s' (%s and %s)" % [id, seen[id], r])
				seen[id] = r
				if RegEx.create_from_string(ID_REGEX).search(id) == null:
					(out.errors as PackedStringArray).append("%s: '%s' is not an id (a.b.c)" % [r, id])
	for item: Dictionary in out.items:
		if str(item._section) == "elements" and not has_kind(str(item.get("kind", ""))):
			(out.errors as PackedStringArray).append("%s: unknown element kind '%s' (no %s%s.gd)" % [item.get("id", item._region),
				item.get("kind", ""), KINDS_DIR, item.get("kind", "")])
	return out


## The kind script for `kind` (cached); null when it does not exist.
static func kind_script(kind: String) -> GDScript:
	if kind == "" or kind.begins_with("_"):
		return null
	if not _kinds.has(kind):
		var path := KINDS_DIR + kind + ".gd"
		_kinds[kind] = load(path) as GDScript if ResourceLoader.exists(path) else null
	return _kinds[kind]


static func has_kind(kind: String) -> bool:
	return kind_script(kind) != null


## True when the kind's build() is a scripted node for the props sub-scene.
static func is_scripted(kind: String) -> bool:
	var s := kind_script(kind)
	if s == null:
		return false
	return bool(s.get_script_constant_map().get("SCRIPTED", false))


static func kind_parts(el: Dictionary, ctx: Dictionary) -> Array:
	var s := kind_script(str(el.get("kind", "")))
	return s.call("parts", el, ctx) if s != null and s.has_method("parts") else []


static func kind_solids(el: Dictionary, ctx: Dictionary) -> Array:
	var s := kind_script(str(el.get("kind", "")))
	return s.call("solids", el, ctx) if s != null and s.has_method("solids") else []


static func kind_build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var s := kind_script(str(el.get("kind", "")))
	return s.call("build", kit, el, ctx) as Node3D if s != null else null


# --------------------------------------------------------------------------- element frames

static func pos2(el: Dictionary) -> Vector2:
	var p: Array = el.get("pos", [0, 0])
	return Vector2(float(p[0]), float(p[1]))


static func yaw_rad(el: Dictionary) -> float:
	return deg_to_rad(float(el.get("yaw", 0.0)))


## The element's frame in world space: its origin on the ground (ctx.field) plus y_off, turned by yaw.
static func frame(el: Dictionary, ctx: Dictionary) -> Transform3D:
	var p := pos2(el)
	var f: HeightField = ctx.field
	var y := f.sample(p.x, p.y) + float(el.get("y_off", 0.0))
	if el.has("y"):
		y = float(el.y)
	return Transform3D(Basis(Vector3.UP, yaw_rad(el)), Vector3(p.x, y, p.y))


static func size3(el: Dictionary, default := Vector3(10, 6, 10)) -> Vector3:
	var s: Variant = el.get("size")
	if typeof(s) != TYPE_ARRAY:
		return default
	var a: Array = s
	return Vector3(float(a[0]), float(a[1]) if a.size() > 1 else default.y, float(a[2]) if a.size() > 2 else default.z)


static func color_of(c: Variant) -> Color:
	if c is Color:
		return c
	return PALETTE.get(str(c), Color(0.5, 0.5, 0.5))


## A part spec.
static func part(shape: String, pos: Vector3, size: Vector3, color: Variant, yaw := 0.0, tilt := Vector3.ZERO) -> Dictionary:
	return {"shape": shape, "pos": pos, "size": size, "color": color, "yaw": yaw, "tilt": tilt}


## A solid spec (center, size, yaw in degrees).
static func solid(shape: String, center: Vector3, size: Vector3, yaw := 0.0) -> Dictionary:
	return {"shape": shape, "center": center, "size": size, "yaw": yaw}


# --------------------------------------------------------------------------- geometry

## Appends the triangles of `parts` (in the frame `xf`) to `st` with their vertex colours.
static func add_parts(st: SurfaceTool, parts: Array, xf: Transform3D) -> int:
	var tris := 0
	for p: Dictionary in parts:
		var size: Vector3 = p.size
		var tilt: Vector3 = p.get("tilt", Vector3.ZERO)
		var basis := Basis(Vector3.UP, deg_to_rad(float(p.get("yaw", 0.0)))) * Basis.from_euler(
			Vector3(deg_to_rad(tilt.x), 0.0, deg_to_rad(tilt.z)))
		var t := xf * Transform3D(basis, p.pos)
		st.set_color(color_of(p.color))
		var faces := shape_faces(str(p.shape), size)
		for k in faces.size():
			st.add_vertex(t * faces[k])
		tris += faces.size() / 3
	return tris


## The plan footprints of `parts` in the frame `xf`: the convex hull of each part's vertices on the
## ground plane, its colour shaded for the map, lowest top first (the map draws them in order):
## [{"poly": PackedVector2Array (x, z), "color": Color, "top": float (above the frame's origin)}].
static func plan_footprints(parts: Array, xf: Transform3D, shade := 0.82) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		var tilt: Vector3 = p.get("tilt", Vector3.ZERO)
		var basis := Basis(Vector3.UP, deg_to_rad(float(p.get("yaw", 0.0)))) * Basis.from_euler(
			Vector3(deg_to_rad(tilt.x), 0.0, deg_to_rad(tilt.z)))
		var t := xf * Transform3D(basis, p.pos)
		var pts := PackedVector2Array()
		var top := -INF
		for v in shape_faces(str(p.shape), p.size):
			var w := t * v
			pts.append(Vector2(w.x, w.z))
			top = maxf(top, w.y)
		var hull := Geometry2D.convex_hull(pts)
		if hull.size() < 3:
			continue
		var c := color_of(p.color)
		out.append({"poly": hull, "color": Color(c.r * shade, c.g * shade, c.b * shade), "top": top - xf.origin.y})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.top) < float(b.top))
	return out


## The triangles of a shape in its own frame (base centred at the origin, Godot's clockwise front
## faces), non-indexed (flat shading comes from generate_normals on separate vertices).
static func shape_faces(shape: String, s: Vector3) -> PackedVector3Array:
	match shape:
		"box":
			return _box(s, 1.0)
		"frustum":
			return _cone(s.x * 0.5, s.z * 0.5, s.y, 8)
		"cyl":
			return _cone(s.x * 0.5, s.x * 0.5, s.y, 8)
		"cone":
			return _cone(s.x * 0.5, 0.0, s.y, 8)
		"roof":
			return _roof(s)
		"pyramid":
			return _pyramid(s)
		"sphere":
			return _sphere(s)
		"wedge":
			return _wedge(s)
	return _box(s, 1.0)


static func _box(s: Vector3, top: float) -> PackedVector3Array:
	var c: Array[Vector3] = []
	for p: Vector3 in [Vector3(-0.5, 0, -0.5), Vector3(0.5, 0, -0.5), Vector3(0.5, 0, 0.5), Vector3(-0.5, 0, 0.5),
			Vector3(-0.5 * top, 1, -0.5 * top), Vector3(0.5 * top, 1, -0.5 * top), Vector3(0.5 * top, 1, 0.5 * top),
			Vector3(-0.5 * top, 1, 0.5 * top)]:
		c.append(p * s)
	var out := PackedVector3Array()
	for q: Array in [[4, 5, 6, 7], [3, 2, 1, 0], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]:
		for k: int in [q[0], q[1], q[2], q[0], q[2], q[3]]:
			out.append(c[k])
	return out


static func _cone(r0: float, r1: float, h: float, sides: int) -> PackedVector3Array:
	var out := PackedVector3Array()
	for k in sides:
		var a := TAU * float(k) / sides
		var b := TAU * float(k + 1) / sides
		var p0 := Vector3(cos(a) * r0, 0, sin(a) * r0)
		var p1 := Vector3(cos(b) * r0, 0, sin(b) * r0)
		var q0 := Vector3(cos(a) * r1, h, sin(a) * r1)
		var q1 := Vector3(cos(b) * r1, h, sin(b) * r1)
		if r1 <= 0.0:
			out.append_array([p0, p1, Vector3(0, h, 0)])
			continue
		out.append_array([p0, p1, q1, p0, q1, q0])
		out.append_array([Vector3(0, h, 0), q0, q1])
	return out


## A gable roof: the ridge along x at the top, eaves at y 0 (size: length x, height y, depth z).
static func _roof(s: Vector3) -> PackedVector3Array:
	var a := Vector3(-0.5, 0, -0.5) * s
	var b := Vector3(0.5, 0, -0.5) * s
	var c := Vector3(0.5, 0, 0.5) * s
	var d := Vector3(-0.5, 0, 0.5) * s
	var r0 := Vector3(-0.5, 1, 0) * s
	var r1 := Vector3(0.5, 1, 0) * s
	return PackedVector3Array([a, r0, r1, a, r1, b, d, c, r1, d, r1, r0, a, d, r0, b, r1, c])


static func _pyramid(s: Vector3) -> PackedVector3Array:
	var a := Vector3(-0.5, 0, -0.5) * s
	var b := Vector3(0.5, 0, -0.5) * s
	var c := Vector3(0.5, 0, 0.5) * s
	var d := Vector3(-0.5, 0, 0.5) * s
	var t := Vector3(0, s.y, 0)
	return PackedVector3Array([a, t, b, b, t, c, c, t, d, d, t, a])


## A wedge: a ramp rising along -z (size x width, y height, z depth).
static func _wedge(s: Vector3) -> PackedVector3Array:
	var a := Vector3(-0.5, 0, 0.5) * s
	var b := Vector3(0.5, 0, 0.5) * s
	var c := Vector3(0.5, 0, -0.5) * s
	var d := Vector3(-0.5, 0, -0.5) * s
	var e := Vector3(-0.5 * s.x, s.y, -0.5 * s.z)
	var f := Vector3(0.5 * s.x, s.y, -0.5 * s.z)
	return PackedVector3Array([a, e, f, a, f, b, d, c, f, d, f, e, a, d, e, b, f, c, a, b, c, a, c, d])


## A low-poly sphere (8 x 4) of diameter s.x and height s.y, its base at y 0.
static func _sphere(s: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	var rx := s.x * 0.5
	var ry := s.y * 0.5
	var rz := s.z * 0.5 if s.z > 0.0 else rx
	var rows := 4
	var cols := 8
	for i in rows:
		var t0 := PI * float(i) / rows
		var t1 := PI * float(i + 1) / rows
		for k in cols:
			var a := TAU * float(k) / cols
			var b := TAU * float(k + 1) / cols
			var p00 := Vector3(sin(t0) * cos(a) * rx, ry - cos(t0) * ry + ry * 0.0, sin(t0) * sin(a) * rz)
			var p01 := Vector3(sin(t0) * cos(b) * rx, ry - cos(t0) * ry, sin(t0) * sin(b) * rz)
			var p10 := Vector3(sin(t1) * cos(a) * rx, ry - cos(t1) * ry, sin(t1) * sin(a) * rz)
			var p11 := Vector3(sin(t1) * cos(b) * rx, ry - cos(t1) * ry, sin(t1) * sin(b) * rz)
			# the sphere spans y 0..2ry with its top at t = 0
			p00.y = ry + cos(t0) * ry
			p01.y = ry + cos(t0) * ry
			p10.y = ry + cos(t1) * ry
			p11.y = ry + cos(t1) * ry
			out.append_array([p00, p01, p11, p00, p11, p10])
	return out


## One mesh of `parts` in the frame `xf` (vertex colours, flat normals, the given material).
static func parts_mesh(parts: Array, xf: Transform3D, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	add_parts(st, parts, xf)
	st.generate_normals()
	st.index()
	var mesh := st.commit()
	if mat != null and mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)
	return mesh


## A node of an element's parts (kinds' build() for static kinds, tests): a MeshInstance3D.
static func parts_node(node_name: String, parts: Array, mat: Material = null) -> Node3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = parts_mesh(parts, Transform3D.IDENTITY, mat)
	return mi


## The horizontal radius an element keeps scenery away from (its parts' extent plus a margin).
static func clearance(el: Dictionary, parts: Array, margin := 6.0) -> float:
	var r := float(el.get("clear_m", 0.0))
	if r > 0.0:
		return r
	for p: Dictionary in parts:
		var pos: Vector3 = p.pos
		var size: Vector3 = p.size
		r = maxf(r, Vector2(pos.x, pos.z).length() + maxf(size.x, size.z) * 0.6)
	return r + margin


# --------------------------------------------------------------------------- polylines (walls, palisades)

## The element's points ([[x, z], ...]) in world space.
static func points_of(el: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in el.get("points", []):
		out.append(Vector2(float(p[0]), float(p[1])))
	return out


## A world point (x, ground + dy, z) in the element's frame (ctx.frame).
static func local_point(ctx: Dictionary, x: float, z: float, dy := 0.0) -> Vector3:
	var f: HeightField = ctx.field
	var xf: Transform3D = ctx.frame
	return xf.affine_inverse() * Vector3(x, f.sample(x, z) + dy, z)


## Splits a polyline into pieces of at most `piece_m` metres: [[a: Vector2, b: Vector2], ...].
static func pieces(pts: PackedVector2Array, piece_m: float) -> Array:
	var out: Array = []
	for k in pts.size() - 1:
		var a := pts[k]
		var b := pts[k + 1]
		var n := maxi(1, int(ceil(a.distance_to(b) / piece_m)))
		for i in n:
			out.append([a.lerp(b, float(i) / n), a.lerp(b, float(i + 1) / n)])
	return out


## Parts and solids of a straight run (a wall, a palisade) from world a to b: boxes of `height`
## and `thick` per piece on the ground under each piece's middle (sunk `sink` m), in ctx.frame.
static func run_boxes(ctx: Dictionary, a: Vector2, b: Vector2, height: float, thick: float, color: Variant,
		sink := 1.0, piece_m := 16.0) -> Dictionary:
	var parts: Array = []
	var solids: Array = []
	var xf: Transform3D = ctx.frame
	var f: HeightField = ctx.field
	for pc: Array in pieces(PackedVector2Array([a, b]), piece_m):
		var p0: Vector2 = pc[0]
		var p1: Vector2 = pc[1]
		var mid := (p0 + p1) * 0.5
		var lo := minf(f.sample(p0.x, p0.y), minf(f.sample(p1.x, p1.y), f.sample(mid.x, mid.y)))
		var local := xf.affine_inverse() * Vector3(mid.x, lo - sink, mid.y)
		var dir := p1 - p0
		var yaw := rad_to_deg(atan2(-dir.y, dir.x)) - rad_to_deg(xf.basis.get_euler().y)
		var length := dir.length() + thick
		var size := Vector3(length, height + sink, thick)
		parts.append(part("box", local, size, color, yaw))
		solids.append(solid("box", local + Vector3.UP * size.y * 0.5, size, yaw))
	return {"parts": parts, "solids": solids}
