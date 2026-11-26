extends RefCounted
## Element kind "settlement" (C4, decision C4-6): what a settlement's development builds, at a man's scale and of what
## the place has - dry-stone laid in courses, turf, split timber, hides, the old kings' cut stone the giant carried -
## weathered (snow on what faces up, lichen and grime: the frost stone material where the land is in the frost band).
## Most of it is flagged (visible_when_flag / hidden_when_flag: a tier's work shows once raised, its life once the
## giant is away) - each element one mesh in its chunk's props, so a tier's buildings are grouped into a few elements.
## Nothing is solid: the folk's paths are as their navmesh was baked at every tier (the giant steps over them).
## Styles (`size` per style; the frame's -z is its front):
##   hall        a dry-stone longhall (`size` [length, width]) - `state` "shell": walls tumbled at one end, no roof, its
##               fallen roof-timbers inside, a hide awning over the other end; "roofed": crucks of whole timbers, the
##               great ridge-tree, a turf roof with its smoke-hole, gable boards, the door's posts and the warm
##               glow of the fire within
##   hut         a round dry-stone hut with a conical turf roof and a hide door (`size` [diameter, height])
##   ring        a curtain of dry-stone and turf round an arc (`radius`, `arc` [from, to] degrees from local +x toward
##               +z), its gate at `gate` degrees `gap` m wide - a trilithon of three king-stones - and firing steps
##               behind it at `steps` (degrees)
##   pile        one hauled load set down at a site (`load` "timber" | "kingstone" | "block" | "heartwood" | "ashlar")
##   windfall    the old kings' frost-killed pines where they fell (`count`, `radius`): the timber's source
##   beacon      a tower of stacked king-stone drums (`height`) with a whole pine for its mast and an iron basket
##   stall       an awning on poles over crates, sacks, hides and a rack of dried fish (a trader's)
##   banners     tall poles with long banners (`points` [[x, z]...] in the frame, `color`)
##   stack       a mason's or a carpenter's stack of worked stone or timber (`size` [w, h, d]) - the older settlements'
##   frame       a timber frame raised for a building (`size` [w, h, d]): posts, beams, braces - the older settlements'

const L := preload("res://tools/world/layout.gd")
const HEARTH := preload("res://tools/world/kinds/hearth.gd")

const STONE := Color(0.5, 0.49, 0.46)
const STONE_DARK := Color(0.39, 0.38, 0.36)
const STONE_WARM := Color(0.55, 0.51, 0.45)
const KINGSTONE := Color(0.53, 0.51, 0.47)
const KINGSTONE_DARK := Color(0.42, 0.41, 0.38)
const TURF := Color(0.31, 0.3, 0.21)
const TURF_DARK := Color(0.24, 0.23, 0.17)
const THATCH := Color(0.45, 0.38, 0.25)
const WOOD := Color(0.42, 0.32, 0.22)
const WOOD_DARK := Color(0.29, 0.22, 0.16)
const WOOD_GREY := Color(0.48, 0.44, 0.38)
const BARK := Color(0.31, 0.25, 0.19)
const HIDE := Color(0.5, 0.4, 0.3)
const HIDE_PALE := Color(0.64, 0.56, 0.44)
const GLOW := Color(1.0, 0.62, 0.24)
const GLOW_DEEP := Color(0.78, 0.33, 0.1)
const SOOT := Color(0.1, 0.09, 0.08)
const IRON := Color(0.24, 0.23, 0.23)


static func _p(shape: String, pos: Vector3, size: Vector3, color: Variant, yaw := 0.0, tilt := Vector3.ZERO, extra := {}) -> Dictionary:
	var p := L.part(shape, pos, size, color, yaw, tilt)
	p["weather"] = 0.5
	p.merge(extra, true)
	return p


static func _rng(el: Dictionary) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + int(el.get("seed", 0)) + absi(str(el.get("id", el.get("style", ""))).hash()) % 10000
	return rng


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var rng := _rng(el)
	match str(el.get("style", "hut")):
		"hall":
			return _hall(el, rng)
		"hut":
			return _hut(el, rng, Vector3.ZERO)
		"tent":
			# C1b's hide tent (the hearth kind's), for a flagged group
			var t := el.duplicate()
			t["style"] = "hide_tent"
			return HEARTH.parts(t, _ctx)
		"ring":
			return _ring(el, rng)
		"pile":
			return _pile(str(el.get("load", "kingstone")), rng, Vector3.ZERO, 0.0)
		"windfall":
			return _windfall(el, rng)
		"beacon":
			return _beacon(el, rng)
		"stall":
			return _stall(rng, Vector3.ZERO)
		"banners":
			return _banners(el, rng)
		"stack":
			return _stack(el, rng)
		"frame":
			return _frame(el, rng)
		"group":
			# several of the styles above in one mesh (one draw call): `items` [{"style", "at": [x, z], "yaw", ...}]
			var out: Array = []
			for it: Dictionary in el.get("items", []):
				var sub := it.duplicate()
				sub["seed"] = int(it.get("seed", out.size()))
				var at: Array = it.get("at", [0, 0])
				var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(float(it.get("yaw", 0.0)))),
					Vector3(float(at[0]), float(it.get("y", 0.0)), float(at[1])))
				for p: Dictionary in parts(sub, _ctx):
					p["xform"] = xf * L.group_of(p)
					out.append(p)
			return out
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Settlement", parts(el, ctx))


# --------------------------------------------------------------------------- dry-stone

## A course of rough stones along the segment a -> b (local), `h` high from `y0`, each its own seeded stone.
static func _course(out: Array, rng: RandomNumberGenerator, a: Vector3, b: Vector3, y0: float, h: float, thick: float,
		color: Color, gap_from := -1.0, gap_to := -1.0) -> void:
	var d := b - a
	var ln := Vector2(d.x, d.z).length()
	if ln < 0.2:
		return
	var yaw := rad_to_deg(atan2(-d.x, -d.z))
	var n := maxi(1, int(ln / 1.5))
	for i in n:
		var t := (i + 0.5) / n
		if gap_from >= 0.0 and t >= gap_from and t <= gap_to:
			continue
		var at := a.lerp(b, t)
		var w := ln / n * rng.randf_range(1.0, 1.25)
		out.append(_p("boulder", Vector3(at.x + rng.randf_range(-0.08, 0.08), y0, at.z + rng.randf_range(-0.08, 0.08)),
			Vector3(thick * rng.randf_range(0.85, 1.05), h * rng.randf_range(0.85, 1.1), w), color if rng.randf() < 0.6 else STONE_DARK,
			yaw + rng.randf_range(-8, 8), Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "weather": 0.38, "smooth": true}))


## A dry-stone wall along a polyline (closed when `closed`), `courses` high, each course `h`; `gaps`: [t0, t1] of the
## whole length left open (a door); `low` [t0, t1, courses]: a stretch tumbled down to that many courses.
static func _wall(out: Array, rng: RandomNumberGenerator, pts: Array, courses: int, h: float, thick: float, gaps := [],
		low := []) -> void:
	var total := 0.0
	for i in pts.size() - 1:
		total += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
	var run := 0.0
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		var seg := Vector2(b.x - a.x, b.z - a.z).length()
		var n := maxi(1, int(seg / 1.5))
		for k in n:
			var t0 := (run + seg * k / n) / total
			var t1 := (run + seg * (k + 1) / n) / total
			var tm := (t0 + t1) * 0.5
			var open := false
			for g: Array in gaps:
				if tm >= float(g[0]) and tm <= float(g[1]):
					open = true
			if open:
				continue
			var nc := courses
			for lw: Array in low:
				if tm >= float(lw[0]) and tm <= float(lw[1]):
					nc = int(lw[2])
			var p0 := a.lerp(b, float(k) / n)
			var p1 := a.lerp(b, float(k + 1) / n)
			for c in nc:
				var shrink := 1.0 - c * 0.08
				_course(out, rng, p0, p1, -0.35 + c * h * 0.92, h * shrink, thick * shrink, STONE if (c + k) % 3 else STONE_WARM)
		run += seg


## The outline of a longhall (a stadium: straight sides, rounded ends) of `length` x `width`, from the door side.
static func _stadium(length: float, width: float, segs := 5) -> Array:
	var r := width * 0.5
	var half := length * 0.5 - r
	var pts: Array = []
	pts.append(Vector3(-half, 0, r))
	pts.append(Vector3(half, 0, r))
	for i in range(1, segs):
		var a := PI * 0.5 - PI * float(i) / segs
		pts.append(Vector3(half + cos(a) * r, 0, sin(a) * r))
	pts.append(Vector3(half, 0, -r))
	pts.append(Vector3(-half, 0, -r))
	for i in range(1, segs):
		var a := -PI * 0.5 - PI * float(i) / segs
		pts.append(Vector3(-half + cos(a) * r, 0, sin(a) * r))
	pts.append(Vector3(-half, 0, r))
	return pts


# --------------------------------------------------------------------------- the hall

static func _hall(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var s := L.size3(el, Vector3(18, 9, 0))
	var length := s.x
	var width := s.y
	var roofed := str(el.get("state", "roofed")) == "roofed"
	var pts := _stadium(length, width)
	# the door in the middle of the front side (the first stretch runs along +z): its share of the outline
	var total := 0.0
	for i in pts.size() - 1:
		total += Vector2(pts[i + 1].x - pts[i].x, pts[i + 1].z - pts[i].z).length()
	var side := length - width
	var door := [(side * 0.5 - 1.3) / total, (side * 0.5 + 1.3) / total]
	if roofed:
		_wall(out, rng, pts, 3, 0.78, 1.05, [door])
	else:
		# the west end tumbled to a course or two, its stones fallen out round it
		_wall(out, rng, pts, 3, 0.78, 1.05, [door], [[0.62, 0.98, 1], [0.7, 0.86, 0]])
		for k in 9:
			var a := rng.randf_range(PI * 0.6, PI * 1.4)
			out.append(_p("boulder", Vector3(-length * 0.5 + cos(a) * rng.randf_range(0.5, 3.5) + 1.5, -0.3,
				sin(a) * rng.randf_range(0.5, 3.5)), Vector3(rng.randf_range(0.8, 1.4), rng.randf_range(0.5, 0.8), rng.randf_range(0.7, 1.2)),
				STONE, rng.randf_range(0, 360), Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "weather": 0.85, "smooth": true}))
	var top := 2.25
	var ridge_h := 8.2
	var z0 := width * 0.5 - 0.4
	if roofed:
		# crucks: pairs of whole timbers from the wall-heads to the ridge
		for x: float in [-length * 0.32, -length * 0.1, length * 0.12, length * 0.33]:
			for sgn: float in [1.0, -1.0]:
				var a := atan2(z0, ridge_h - 0.4)
				var ln := sqrt(z0 * z0 + (ridge_h - 0.4) * (ridge_h - 0.4)) + 0.6
				out.append(_p("drum", Vector3(x, 0.0, sgn * z0), Vector3(0.62, ln, 0), BARK if sgn > 0 else WOOD_DARK, 0.0,
					Vector3(-rad_to_deg(a) * sgn, 0, 0), {"seed": rng.randi_range(0, 9999), "sides": 7, "rough": 0.06, "top": 0.82, "weather": 0.3}))
		# the ridge-tree: the great timber the giant carried, its ends standing proud of the gables
		out.append(_p("drum", Vector3(length * 0.5 + 1.6, ridge_h - 0.25, 0), Vector3(1.15, length + 3.2, 0), BARK, 0.0,
			Vector3(0, 0, 90), {"seed": 31, "sides": 9, "rough": 0.07, "top": 0.86, "weather": 0.45}))
		# purlins and rafters' ends at the eaves
		for sgn: float in [1.0, -1.0]:
			out.append(_p("drum", Vector3(length * 0.5 - 0.6, top + 0.3, sgn * (width * 0.5 + 0.2)), Vector3(0.36, length - 1.2, 0), WOOD_DARK,
				0.0, Vector3(0, 0, 90), {"seed": 40 + int(sgn), "sides": 6, "weather": 0.3}))
			for k in 9:
				var x := -length * 0.42 + k * length * 0.105
				out.append(_p("drum", Vector3(x, top + 0.2, sgn * (width * 0.5 + 1.0)), Vector3(0.2, 1.4, 0), WOOD_DARK, 0.0,
					Vector3(sgn * -55.0, 0, 0), {"sides": 4, "weather": 0.2}))
		# the turf roof over its thatch skirt: two layers, the turf ragged at the eaves, snow on it
		_slopes(out, length + 0.6, top - 0.15, ridge_h - 0.1, width * 0.5 + 1.3, 0.35, THATCH, 0.25)
		_slopes(out, length - 0.4, top + 0.2, ridge_h + 0.05, width * 0.5 + 0.8, 0.45, TURF, 0.5)
		for k in 10:
			var x := rng.randf_range(-length * 0.45, length * 0.45)
			var sgn := 1.0 if k % 2 == 0 else -1.0
			var zf := rng.randf_range(0.25, 0.8)
			out.append(_p("boulder", Vector3(x, top + 0.35 + (ridge_h - top) * (1.0 - zf) * 0.9, sgn * zf * (width * 0.5 + 0.7)),
				Vector3(rng.randf_range(1.2, 2.4), 0.35, rng.randf_range(0.8, 1.4)), TURF_DARK, rng.randf_range(0, 360),
				Vector3(sgn * 38.0, 0, 0), {"seed": rng.randi_range(0, 9999), "weather": 0.8, "smooth": true, "rough": 0.3}))
		# the smoke-hole, sooty, at the ridge's middle, and a weight-stone rope over the ridge
		out.append(_p("box", Vector3(0.0, ridge_h - 0.65, 0), Vector3(2.0, 0.5, 1.6), SOOT, 0.0, Vector3.ZERO, {"weather": 0.0}))
		for x: float in [-length * 0.25, length * 0.25]:
			for sgn: float in [1.0, -1.0]:
				out.append(_p("boulder", Vector3(x, top + 0.2, sgn * (width * 0.5 + 1.15)), Vector3(0.7, 0.6, 0.6), STONE, 0.0, Vector3.ZERO,
					{"seed": int(x * 3 + sgn * 7), "weather": 0.6, "smooth": true}))
		# the gables' boards, under the roof's ends
		for sgn: float in [1.0, -1.0]:
			for k in 5:
				var hz := (ridge_h - top) * (1.0 - absf(k - 2.0) / 2.5)
				out.append(_p("box", Vector3(sgn * (length * 0.5 - 0.3), top + 0.1, (k - 2) * width * 0.16), Vector3(0.12, hz * 0.95, width * 0.15),
					WOOD_GREY if k % 2 else WOOD, 0.0, Vector3.ZERO, {"weather": 0.35}))
		# the door: posts, a lintel, the hide pulled aside and the fire's glow within
		var dz := width * 0.5 + 0.1
		for x: float in [-1.35, 1.35]:
			out.append(_p("drum", Vector3(x, -0.2, dz), Vector3(0.5, 2.9, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 6, "weather": 0.2}))
		out.append(_p("drum", Vector3(1.9, 2.55, dz), Vector3(0.45, 3.8, 0), WOOD_DARK, 0.0, Vector3(0, 0, 90), {"sides": 6, "weather": 0.4}))
		out.append(_p("box", Vector3(0.0, -0.2, width * 0.5 - 0.6), Vector3(2.4, 2.45, 0.2), GLOW_DEEP, 0.0, Vector3.ZERO, {"weather": 0.0}))
		out.append(_p("box", Vector3(0.1, -0.2, width * 0.5 - 0.75), Vector3(1.4, 1.6, 0.15), GLOW, 0.0, Vector3.ZERO, {"weather": 0.0}))
		out.append(_p("box", Vector3(-1.75, -0.1, dz + 0.25), Vector3(1.0, 2.4, 0.1), HIDE, 25.0, Vector3(0, 0, 3), {"weather": 0.15}))
		# a woodpile against the front wall and a quern stone by the door
		for k in 6:
			out.append(_p("drum", Vector3(3.5 + (k % 3) * 0.75, 0.35 + int(k / 3) * 0.62, width * 0.5 + 0.9), Vector3(0.62, 2.4, 0), WOOD if k % 2 else WOOD_DARK,
				0.0, Vector3(90, 0, 0), {"seed": 70 + k, "sides": 6, "weather": 0.55}))
		out.append(_p("drum", Vector3(-3.2, -0.1, width * 0.5 + 1.2), Vector3(1.1, 0.45, 0), STONE_DARK, 0.0, Vector3.ZERO, {"sides": 10, "weather": 0.5}))
	else:
		# the old roof's timbers fallen in, charred at their ends; a hide awning on poles over the east end
		out.append(_p("drum", Vector3(-length * 0.3, 0.2, -width * 0.2), Vector3(0.55, length * 0.55, 0), WOOD_DARK, 20.0,
			Vector3(0, 0, 78), {"seed": 3, "sides": 6, "weather": 0.75}))
		out.append(_p("drum", Vector3(-1.0, 0.1, width * 0.25), Vector3(0.5, length * 0.42, 0), SOOT, -15.0, Vector3(0, 0, -82),
			{"seed": 4, "sides": 6, "weather": 0.7}))
		for x: float in [length * 0.18, length * 0.42]:
			for sgn: float in [1.0, -1.0]:
				out.append(_p("drum", Vector3(x, -0.2, sgn * (width * 0.35)), Vector3(0.24, 3.6, 0), WOOD_DARK, 0.0, Vector3(sgn * -6.0, 0, 0),
					{"sides": 5, "weather": 0.2}))
		out.append(_p("box", Vector3(length * 0.3, 3.15, 0.0), Vector3(length * 0.32, 0.1, width * 0.82), HIDE, 0.0, Vector3(4, 0, 0),
			{"weather": 0.55}))
		out.append(_p("box", Vector3(length * 0.3, 3.12, -width * 0.42), Vector3(length * 0.3, 1.4, 0.08), HIDE_PALE, 0.0, Vector3(-12, 0, 0),
			{"weather": 0.3}))
	return out


## A gable roof of two tilted slabs (boxes: the frost material culls back faces, which the plain `roof` shape's
## slopes are wound as), the ridge along local x at `y1`, the eaves `eave` m either side at `y0`, `thick` deep.
static func _slopes(out: Array, length: float, y0: float, y1: float, eave: float, thick: float, color: Color, weather: float) -> void:
	var h := y1 - y0
	var ln := sqrt(eave * eave + h * h)
	var ang := rad_to_deg(atan2(h, eave))
	for sgn: float in [1.0, -1.0]:
		out.append(_p("box", Vector3(0, y0 + h * 0.5 - thick * 0.5, sgn * eave * 0.5), Vector3(length, thick, ln + 0.3), color, 0.0,
			Vector3(ang * sgn, 0, 0), {"weather": weather}))


# --------------------------------------------------------------------------- huts, the ring, the beacon

static func _hut(el: Dictionary, rng: RandomNumberGenerator, at: Vector3) -> Array:
	var out: Array = []
	var s := L.size3(el, Vector3(6.0, 5.0, 0))
	var r := s.x * 0.5
	var pts: Array = []
	for i in 11:
		var a := TAU * i / 10.0
		pts.append(at + Vector3(cos(a) * r, 0, sin(a) * r))
	_wall(out, rng, pts, 2, 0.75, 0.9, [[0.2, 0.28]])
	out.append(_p("cone", at + Vector3(0, 1.25, 0), Vector3(s.x + 1.4, s.y - 1.1, 0), TURF, rng.randf_range(0, 360), Vector3.ZERO,
		{"weather": 0.45}))
	for k in 5:
		var a := rng.randf_range(0, TAU)
		var hr := rng.randf_range(0.25, 0.7)
		out.append(_p("boulder", at + Vector3(cos(a) * (s.x * 0.5 + 0.4) * (1.0 - hr * 0.8), 1.2 + (s.y - 1.1) * hr * 0.85,
			sin(a) * (s.x * 0.5 + 0.4) * (1.0 - hr * 0.8)), Vector3(1.4, 0.3, 1.0), TURF_DARK, -rad_to_deg(a) + 90.0, Vector3(30, 0, 0),
			{"seed": rng.randi_range(0, 9999), "weather": 0.5, "smooth": true, "rough": 0.3}))
	out.append(_p("cone", at + Vector3(0, 1.05, 0), Vector3(s.x + 1.9, 0.9, 0), THATCH, 0.0, Vector3.ZERO, {"weather": 0.3}))
	out.append(_p("drum", at + Vector3(0, s.y - 0.25, 0), Vector3(0.6, 0.6, 0), SOOT, 0.0, Vector3.ZERO, {"sides": 6, "weather": 0.0}))
	var door := TAU * 0.24
	out.append(_p("box", at + Vector3(cos(door) * (r + 0.2), -0.2, sin(door) * (r + 0.2)), Vector3(1.2, 1.9, 0.1), HIDE,
		-rad_to_deg(door) + 90.0, Vector3.ZERO, {"weather": 0.15}))
	return out


static func _ring(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	# the curtain's line: `path` [[degrees, radius], ...] from the frame's +x toward +z (or a plain `radius` and `arc`),
	# the gate at `gate` [degrees, radius] `gap` m wide, splitting it in two runs
	var path: Array = el.get("path", [])
	if path.is_empty():
		var arc: Array = el.get("arc", [-68, 120])
		var r0 := float(el.get("radius", 46.0))
		path = [[float(arc[0]), r0], [(float(arc[0]) + float(arc[1])) * 0.5, r0], [float(arc[1]), r0]]
	var gate_v: Variant = el.get("gate", [0.0, 46.0])
	var gate: Array = gate_v if typeof(gate_v) == TYPE_ARRAY else [float(gate_v), float(el.get("radius", 46.0))]
	var gap := float(el.get("gap", 12.0))
	var ga := deg_to_rad(float(gate[0]))
	var gr := float(gate[1])
	var half := rad_to_deg(gap * 0.5 / gr) + 2.0
	var before: Array = []
	var after: Array = []
	for pt: Array in path:
		if float(pt[0]) < float(gate[0]) - half:
			before.append(pt)
		elif float(pt[0]) > float(gate[0]) + half:
			after.append(pt)
	before.append([float(gate[0]) - half, gr])
	after.push_front([float(gate[0]) + half, gr])
	for run: Array in [before, after]:
		# the run's points, densified to about 5 m
		var pts: Array = []
		for i in run.size() - 1:
			var p0 := _polar(run[i])
			var p1 := _polar(run[i + 1])
			var n := maxi(1, int(p0.distance_to(p1) / 5.0))
			for k in n:
				pts.append(p0.lerp(p1, float(k) / n))
		pts.append(_polar(run[run.size() - 1]))
		_wall(out, rng, pts, 3, 0.85, 1.6)
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var d := b - a
			var yaw := rad_to_deg(atan2(-d.x, -d.z))
			var mid := (a + b) * 0.5
			var out_dir := Vector3(mid.x, 0, mid.z).normalized()
			out.append(_p("boulder", mid + Vector3(0, 2.05, 0), Vector3(1.5, 0.5, d.length() + 0.4), TURF_DARK if i % 3 else TURF, yaw,
				Vector3(rng.randf_range(-3, 3), 0, 0), {"seed": rng.randi_range(0, 99999), "weather": 0.3, "smooth": true, "rough": 0.3}))
			out.append(_p("boulder", mid + out_dir * 1.3 + Vector3(0, -0.5, 0), Vector3(1.5, 0.9, d.length() * 0.9),
				STONE_DARK, yaw, Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "weather": 0.4, "smooth": true, "rough": 0.3}))
	# the gate: a trilithon of the giant's king-stones, the timber leaves swung open inside it
	var g := Vector3(cos(ga) * gr, 0, sin(ga) * gr)
	var along := Vector3(-sin(ga), 0, cos(ga))
	var inward := -Vector3(cos(ga), 0, sin(ga))
	var gyaw := -rad_to_deg(ga)
	for sgn: float in [-1.0, 1.0]:
		var at := g + along * sgn * (gap * 0.5 + 1.3)
		out.append(_p("drum", at + Vector3(0, -0.6, 0), Vector3(2.6, 7.0, 0), KINGSTONE, gyaw + sgn * 12.0, Vector3(sgn * 2.0, 0, 0),
			{"seed": 600 + int(sgn), "sides": 11, "rough": 0.05, "top": 0.94, "weather": 0.3}))
		out.append(_p("box", g + along * sgn * (gap * 0.5 - 0.2) + inward * 2.2 + Vector3(0, -0.2, 0), Vector3(0.35, 3.4, 4.2), WOOD_DARK,
			gyaw + sgn * 32.0, Vector3.ZERO, {"weather": 0.3}))
	out.append(_p("drum", g - along * (gap * 0.5 + 3.0) + Vector3(0, 6.6, 0), Vector3(2.4, gap + 6.0, 0), KINGSTONE_DARK, gyaw,
		Vector3(90, 0, 0), {"seed": 602, "sides": 11, "rough": 0.05, "top": 0.92, "weather": 0.4}))
	# firing steps behind the curtain: a bank of rubble and turf with a few stone treads
	for d: Variant in el.get("steps", []):
		var a := float(d)
		var r := _path_radius(path, a) - 2.6
		var at := Vector3(cos(deg_to_rad(a)) * r, 0, sin(deg_to_rad(a)) * r)
		out.append(_p("boulder", at + Vector3(0, -0.6, 0), Vector3(3.2, 1.9, 4.2), STONE_DARK, -a, Vector3.ZERO,
			{"seed": rng.randi_range(0, 99999), "weather": 0.35, "smooth": true, "rough": 0.25}))
		out.append(_p("boulder", at + Vector3(0, 1.0, 0), Vector3(2.6, 0.45, 3.6), TURF, -a, Vector3.ZERO,
			{"seed": rng.randi_range(0, 99999), "weather": 0.3, "smooth": true, "rough": 0.2}))
	return out


static func _polar(pt: Array) -> Vector3:
	var a := deg_to_rad(float(pt[0]))
	return Vector3(cos(a) * float(pt[1]), 0, sin(a) * float(pt[1]))


static func _path_radius(path: Array, deg: float) -> float:
	for i in path.size() - 1:
		var a0 := float(path[i][0])
		var a1 := float(path[i + 1][0])
		if deg >= a0 and deg <= a1:
			return lerpf(float(path[i][1]), float(path[i + 1][1]), (deg - a0) / maxf(a1 - a0, 1e-4))
	return float(path[0][1]) if not path.is_empty() else 46.0


static func _beacon(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var h := float(el.get("height", 14.0))
	var drums := 4
	var y := -0.5
	for k in drums:
		var dh := (h - 1.0) / drums
		var d := lerpf(5.2, 3.6, float(k) / drums)
		out.append(_p("drum", Vector3(rng.randf_range(-0.12, 0.12), y, rng.randf_range(-0.12, 0.12)), Vector3(d, dh + 0.05, 0),
			KINGSTONE if k % 2 == 0 else KINGSTONE_DARK, rng.randf_range(0, 360), Vector3.ZERO,
			{"seed": 700 + k, "sides": 12, "rough": 0.05, "top": 0.97, "weather": 0.6}))
		y += dh
	# its foot heaped round with stones, a ladder of lashed poles up its side
	for k in 10:
		var a := TAU * k / 10.0 + rng.randf_range(-0.2, 0.2)
		out.append(_p("boulder", Vector3(cos(a) * 3.2, -0.5, sin(a) * 3.2), Vector3(1.6, 1.0, 1.3), STONE, rng.randf_range(0, 360),
			Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "weather": 0.8, "smooth": true}))
	for sgn: float in [-1.0, 1.0]:
		out.append(_p("drum", Vector3(sgn * 0.45, -0.3, 2.7), Vector3(0.18, h + 0.4, 0), WOOD_DARK, 0.0, Vector3(-7.0, 0, 0), {"sides": 4, "weather": 0.2}))
	for k in int(h / 1.2):
		out.append(_p("box", Vector3(0, 0.6 + k * 1.2, 2.72 - k * 0.15), Vector3(1.1, 0.12, 0.12), WOOD, 0.0, Vector3.ZERO, {"weather": 0.3}))
	# the mast: a whole pine standing from the top, the iron basket on it and its stays
	out.append(_p("drum", Vector3(0, h - 1.0, 0), Vector3(0.9, 7.0, 0), BARK, 0.0, Vector3.ZERO, {"seed": 750, "sides": 8, "top": 0.8, "weather": 0.4}))
	out.append(_p("frustum", Vector3(0, h + 5.2, 0), Vector3(2.0, 1.4, 3.0), IRON, 0.0, Vector3.ZERO, {"weather": 0.2}))
	for k in 6:
		var a := TAU * k / 6.0
		out.append(_p("drum", Vector3(cos(a) * 1.0, h + 5.4, sin(a) * 1.0), Vector3(0.22, 1.7, 0), WOOD_DARK, 0.0,
			Vector3(cos(a) * 20.0, 0, -sin(a) * 20.0), {"sides": 4, "weather": 0.1}))
	return out


# --------------------------------------------------------------------------- loads, the windfall, the dressing

static func _pile(load_id: String, rng: RandomNumberGenerator, at: Vector3, yaw: float) -> Array:
	var out: Array = []
	match load_id:
		"timber", "heartwood":
			var ln := 15.0 if load_id == "timber" else 10.0
			out.append(_p("drum", at + Vector3(ln * 0.5, 0.7, 0), Vector3(1.45, ln, 0), BARK if load_id == "timber" else Color(0.45, 0.33, 0.2),
				yaw, Vector3(0, 0, 90), {"seed": rng.randi_range(0, 9999), "sides": 9, "rough": 0.07, "top": 0.78, "weather": 0.55}))
			for k in 3:
				out.append(_p("drum", at + Vector3(-ln * 0.3 + k * ln * 0.3, 1.2, 0.4), Vector3(0.3, 1.4, 0), WOOD_DARK, yaw + k * 70.0,
					Vector3(50, 0, 0), {"sides": 4, "weather": 0.3}))
		"kingstone":
			out.append(_p("drum", at + Vector3(2.9, 1.5, 0), Vector3(3.0, 5.6, 0), KINGSTONE, yaw, Vector3(0, 0, 90),
				{"seed": rng.randi_range(0, 9999), "sides": 12, "rough": 0.05, "top": 0.96, "weather": 0.6}))
			out.append(_p("boulder", at + Vector3(-0.8, -0.4, 1.4), Vector3(1.1, 0.6, 0.9), STONE_DARK, 0.0, Vector3.ZERO,
				{"seed": rng.randi_range(0, 9999), "weather": 0.8, "smooth": true}))
		"block", "ashlar":
			out.append(_p("block", at + Vector3(0, -0.3, 0), Vector3(4.6, 2.4, 3.0), STONE_WARM if load_id == "block" else STONE, yaw,
				Vector3.ZERO, {"seed": rng.randi_range(0, 9999), "weather": 0.4}))
	return out


static func _windfall(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var n := int(el.get("count", 6))
	var r := float(el.get("radius", 16.0))
	for k in n:
		var a := rng.randf_range(0, TAU)
		var at := Vector3(cos(a) * rng.randf_range(0, r), -0.3, sin(a) * rng.randf_range(0, r))
		var ln := rng.randf_range(18.0, 27.0)
		var yaw := rng.randf_range(0, 360)
		var d := rng.randf_range(1.3, 2.0)
		# the trunk lying along local x from its root plate, a stub of a branch or two, its top snapped off
		var xf := Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
		var trunk := _p("drum", Vector3(ln, d * 0.45, 0), Vector3(d, ln, 0), BARK if k % 2 else WOOD_GREY, 0.0, Vector3(0, 0, 90),
			{"seed": rng.randi_range(0, 9999), "sides": 9, "rough": 0.08, "top": 0.55, "weather": 0.65})
		trunk["xform"] = xf
		out.append(trunk)
		var root := _p("boulder", Vector3(-0.6, -0.2, 0), Vector3(1.8, d * 2.2, d * 2.4), Color(0.36, 0.29, 0.2), 0.0, Vector3.ZERO,
			{"seed": rng.randi_range(0, 9999), "rough": 0.35, "weather": 0.5, "smooth": true})
		root["xform"] = xf
		out.append(root)
		for b in 3:
			var stub := _p("drum", Vector3(ln * rng.randf_range(0.3, 0.85), d * 0.6, 0), Vector3(0.35, rng.randf_range(2.0, 4.5), 0), WOOD_GREY,
				rng.randf_range(0, 360), Vector3(rng.randf_range(30, 70), 0, 0), {"sides": 4, "top": 0.4, "weather": 0.5})
			stub["xform"] = xf
			out.append(stub)
	return out


static func _stall(rng: RandomNumberGenerator, at: Vector3) -> Array:
	var out: Array = []
	for x: float in [-2.4, 2.4]:
		for z: float in [-1.4, 1.4]:
			out.append(_p("drum", at + Vector3(x, -0.2, z), Vector3(0.18, 3.0 if z < 0 else 2.4, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 4, "weather": 0.2}))
	out.append(_p("box", at + Vector3(0, 2.75, 0), Vector3(5.6, 0.08, 3.4), HIDE_PALE, 0.0, Vector3(-9, 0, 0), {"weather": 0.5}))
	for k in 4:
		out.append(_p("box", at + Vector3(-1.8 + k * 1.2, -0.1, 0.6), Vector3(1.0, 0.8, 0.9), WOOD, rng.randf_range(-10, 10), Vector3.ZERO, {"weather": 0.3}))
	for k in 3:
		out.append(_p("ellipsoid", at + Vector3(-1.2 + k * 1.1, 0.7, 0.4), Vector3(0.9, 0.7, 0.7), HIDE, k * 40.0, Vector3.ZERO,
			{"cols": 6, "rows": 4, "weather": 0.3}))
	out.append(_p("drum", at + Vector3(-2.6, 1.9, -1.2), Vector3(0.1, 5.0, 0), WOOD_DARK, 0.0, Vector3(0, 0, 90), {"sides": 4, "weather": 0.2}))
	for k in 5:
		out.append(_p("box", at + Vector3(-2.2 + k * 1.0, 1.25, -1.2), Vector3(0.3, 1.1, 0.06), Color(0.62, 0.58, 0.5), 0.0, Vector3.ZERO, {"weather": 0.1}))
	return out


static func _banners(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var color: Variant = el.get("color", "banner_blue")
	for pt: Array in el.get("points", [[0, 0]]):
		var at := Vector3(float(pt[0]), 0, float(pt[1]))
		var h := float(el.get("height", 9.0))
		out.append(_p("drum", at + Vector3(0, -0.4, 0), Vector3(0.28, h + 0.4, 0), WOOD_DARK, 0.0, Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2)),
			{"sides": 5, "weather": 0.25}))
		out.append(_p("drum", at + Vector3(0, h - 0.3, 0), Vector3(0.14, 2.6, 0), WOOD_DARK, 0.0, Vector3(0, 0, 90), {"sides": 4, "weather": 0.2}))
		out.append(_p("box", at + Vector3(-1.2, h - 4.6, 0.05), Vector3(2.2, 4.3, 0.06), color, 0.0, Vector3(rng.randf_range(-4, 4), 0, 0),
			{"weather": 0.08}))
		out.append(_p("box", at + Vector3(-1.2, h - 5.4, 0.06), Vector3(2.2, 0.8, 0.06), STONE_WARM, 0.0, Vector3.ZERO, {"weather": 0.05}))
	return out


static func _stack(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var s := L.size3(el, Vector3(6, 2.5, 4))
	var wood := str(el.get("material", "stone")) == "timber"
	var rows := maxi(1, int(s.y / 1.0))
	for row in rows:
		var n := maxi(1, int(s.x / 1.6) - row)
		for k in n:
			var at := Vector3(-s.x * 0.5 + 0.8 + k * 1.6 + row * 0.8, -0.2 + row * 1.0, rng.randf_range(-0.2, 0.2))
			if wood:
				out.append(_p("drum", at + Vector3(0, 0.45, s.z * 0.5), Vector3(0.9, s.z, 0), WOOD if (k + row) % 2 else WOOD_DARK, 0.0,
					Vector3(90, 0, 0), {"seed": rng.randi_range(0, 9999), "sides": 7, "weather": 0.4}))
			else:
				out.append(_p("block", at, Vector3(1.5, 0.95, s.z), STONE_WARM if (k + row) % 2 else STONE, rng.randf_range(-4, 4), Vector3.ZERO,
					{"seed": rng.randi_range(0, 9999), "weather": 0.35, "bevel": 0.06}))
	return out


static func _frame(el: Dictionary, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var s := L.size3(el, Vector3(8, 6, 6))
	for x: float in [-s.x * 0.5, 0.0, s.x * 0.5]:
		for z: float in [-s.z * 0.5, s.z * 0.5]:
			out.append(_p("drum", Vector3(x, -0.3, z), Vector3(0.45, s.y + 0.3, 0), WOOD, 0.0, Vector3.ZERO, {"sides": 6, "weather": 0.25}))
		out.append(_p("drum", Vector3(x, s.y - 0.2, s.z * 0.5 + 0.2), Vector3(0.4, s.z + 0.4, 0), WOOD_DARK, 0.0, Vector3(90, 0, 0), {"sides": 6, "weather": 0.3}))
	for z: float in [-s.z * 0.5, s.z * 0.5]:
		out.append(_p("drum", Vector3(s.x * 0.5 + 0.2, s.y - 0.4, z), Vector3(0.4, s.x + 0.4, 0), WOOD_DARK, 0.0, Vector3(0, 0, 90), {"sides": 6, "weather": 0.3}))
		out.append(_p("drum", Vector3(-s.x * 0.5, 0.4, z), Vector3(0.25, sqrt(s.x * s.x * 0.25 + s.y * s.y * 0.5), 0), WOOD, 0.0,
			Vector3(0, 0, -rad_to_deg(atan2(s.x * 0.5, s.y * 0.7))), {"sides": 5, "weather": 0.25}))
	_slopes(out, s.x + 1.0, s.y, s.y * 1.45, s.z * 0.5 + 0.8, 0.25, THATCH, 0.3)
	return out
