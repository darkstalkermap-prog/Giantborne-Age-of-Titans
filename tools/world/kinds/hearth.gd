extends RefCounted
## Element kind "hearth" (C1b): the dressing of a hold-outs' camp in the cold (Last Hearth), at a man's scale - so a
## colossus over it reads as one. Merged into the chunk's structures mesh, lightly weathered (snow on what faces up);
## nothing is solid (the camp's people and their paths are as C1 baked them). Styles:
##   windbreak    a dry-stone wall about 2 m high round an arc (`radius`, `arc` [from, to] degrees from local +x
##                toward +z), its courses of rough stones, hides stretched on posts along its top
##   hide_tent    a conical tent of hides on poles (`size` [diameter, height]), the poles' ends crossed above it
##   woodpile     split logs stacked under a lean-to roof, a chopping block and an axe's log
##   stores       the camp's stores: crates, barrels, sacks, under a hide tarp weighted with stones
##   drying_rack  two A-frames and a pole hung with hides and fish
##   firepit      a ring of stones round a fire's logs and embers (its smoke is the "smoke" kind)
##   lookout      a watch post: a tall post, a platform with a rail, a ladder, a tattered banner (`color`)

const L := preload("res://tools/world/layout.gd")

const HIDE := Color(0.5, 0.4, 0.3)
const HIDE_DARK := Color(0.38, 0.3, 0.23)
const HIDE_PALE := Color(0.64, 0.56, 0.44)
const WOOD := Color(0.42, 0.32, 0.22)
const WOOD_DARK := Color(0.29, 0.22, 0.16)
const STONE := Color(0.5, 0.49, 0.46)
const STONE_DARK := Color(0.4, 0.39, 0.37)
const EMBER := Color(0.85, 0.36, 0.12)
const CHAR := Color(0.12, 0.11, 0.1)


static func _p(shape: String, pos: Vector3, size: Vector3, color: Variant, yaw := 0.0, tilt := Vector3.ZERO, extra := {}) -> Dictionary:
	var p := L.part(shape, pos, size, color, yaw, tilt)
	p["weather"] = 0.45
	p.merge(extra, true)
	return p


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 777 + int(el.get("seed", 0)) + str(el.get("id", "")).hash() % 1000
	match str(el.get("style", "firepit")):
		"windbreak":
			var r := float(el.get("radius", 30.0))
			var arc: Array = el.get("arc", [0, 120])
			var a0 := deg_to_rad(float(arc[0]))
			var a1 := deg_to_rad(float(arc[1]))
			var n := maxi(2, int(absf(a1 - a0) * r / 2.1))
			for i in n:
				var a := lerpf(a0, a1, (i + 0.5) / n)
				var at := Vector3(cos(a) * r, -0.4, sin(a) * r)
				var yaw := -rad_to_deg(a) + 90.0
				for course in 2:
					var w := rng.randf_range(1.8, 2.5)
					var h := rng.randf_range(0.8, 1.05) * (1.0 - course * 0.12)
					out.append(_p("boulder", at + Vector3(rng.randf_range(-0.2, 0.2), course * 0.82, rng.randf_range(-0.2, 0.2)),
						Vector3(w, h, 1.3 - course * 0.2), STONE if (i + course) % 3 else STONE_DARK, yaw + rng.randf_range(-12, 12),
						Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "weather": 0.8}))
				if i % 4 == 0:
					out.append(_p("drum", at + Vector3(0, 1.2, 0), Vector3(0.22, 2.2, 0), WOOD_DARK, 0.0, Vector3(rng.randf_range(-6, 6), 0, 0),
						{"seed": i, "sides": 5, "top": 0.8}))
				if i % 4 == 1 and i + 2 < n:
					var b := lerpf(a0, a1, (i + 2.0) / n)
					var mid := (at + Vector3(cos(b) * r, -0.4, sin(b) * r)) * 0.5
					out.append(_p("box", mid + Vector3(0, 1.75, 0), Vector3(3.4, 1.3, 0.08), HIDE if i % 3 else HIDE_DARK, yaw,
						Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-3, 3))))
		"hide_tent":
			var s := L.size3(el, Vector3(5.5, 4.6, 0))
			out.append(_p("drum", Vector3(0, -0.2, 0), Vector3(s.x, s.y, 0), HIDE if rng.randf() < 0.5 else HIDE_PALE, rng.randf_range(0, 360),
				Vector3.ZERO, {"seed": rng.randi_range(0, 99999), "sides": 7, "top": 0.06, "rough": 0.05}))
			for k in 5:
				var a := TAU * k / 5.0 + rng.randf_range(-0.2, 0.2)
				var lean := rad_to_deg(atan2(s.x * 0.42, s.y * 1.1))
				out.append(_p("drum", Vector3(cos(a) * s.x * 0.42, -0.2, sin(a) * s.x * 0.42), Vector3(0.14, s.y * 1.32, 0), WOOD_DARK, 0.0,
					Vector3(-lean * sin(a), 0, lean * cos(a)), {"seed": k, "sides": 4, "top": 0.7}))
			out.append(_p("box", Vector3(s.x * 0.3, -0.1, s.x * 0.3), Vector3(1.4, 2.0, 0.08), HIDE_DARK, 45.0, Vector3(0, 0, 0)))
		"woodpile":
			for row in 3:
				for k in 5 - row:
					out.append(_p("drum", Vector3(-1.8 + k * 0.85 + row * 0.42, 0.35 + row * 0.62, -1.6), Vector3(0.7, 3.2, 0),
						WOOD if (k + row) % 2 else WOOD_DARK, 0.0, Vector3(90, 0, 0), {"seed": row * 7 + k, "sides": 6, "weather": 0.6}))
			out.append(_p("box", Vector3(0, 2.4, 0.1), Vector3(5.2, 0.2, 4.4), HIDE_DARK, 0.0, Vector3(-18, 0, 0)))
			for side: float in [-1.0, 1.0]:
				out.append(_p("drum", Vector3(side * 2.4, -0.3, 1.7), Vector3(0.2, 2.6, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 4}))
			out.append(_p("drum", Vector3(1.8, -0.2, 3.0), Vector3(0.9, 0.9, 0), WOOD, 0.0, Vector3.ZERO, {"sides": 8}))
		"stores":
			for k in 4:
				out.append(_p("box", Vector3(-2.0 + k * 1.3, -0.1 + (k % 2) * 0.0, rng.randf_range(-0.3, 0.3)), Vector3(1.1, 1.0, 1.1), WOOD,
					rng.randf_range(-15, 15)))
			out.append(_p("box", Vector3(-1.3, 0.9, 0.0), Vector3(1.0, 0.9, 1.0), WOOD_DARK, 20.0))
			for k in 3:
				out.append(_p("drum", Vector3(1.6 + k * 0.95, -0.1, 1.4), Vector3(0.9, 1.25, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 8}))
			for k in 5:
				out.append(_p("ellipsoid", Vector3(-1.5 + k * 0.8, -0.1, 1.6), Vector3(1.0, 0.9, 0.8), HIDE_PALE, k * 30.0, Vector3.ZERO,
					{"cols": 6, "rows": 4}))
			out.append(_p("box", Vector3(-0.6, 1.25, 0.2), Vector3(4.6, 0.12, 3.0), HIDE_DARK, 4.0, Vector3(6, 0, -10)))
			for k in 3:
				out.append(_p("boulder", Vector3(-2.6 + k * 2.4, 1.0 - k * 0.3, 1.4), Vector3(0.6, 0.45, 0.5), STONE, 0.0, Vector3.ZERO,
					{"seed": k, "weather": 0.8}))
		"drying_rack":
			for side: float in [-1.0, 1.0]:
				for leg: float in [-1.0, 1.0]:
					out.append(_p("drum", Vector3(side * 2.6, -0.2, leg * 0.8), Vector3(0.16, 3.1, 0), WOOD_DARK, 0.0, Vector3(leg * -15.0, 0, 0), {"sides": 4}))
			out.append(_p("drum", Vector3(-2.8, 2.7, 0), Vector3(0.16, 5.6, 0), WOOD_DARK, 0.0, Vector3(0, 0, -90), {"sides": 4}))
			for k in 4:
				out.append(_p("box", Vector3(-1.9 + k * 1.25, 1.6, 0), Vector3(1.0, 1.9 - (k % 2) * 0.5, 0.06), HIDE if k % 2 else HIDE_DARK,
					rng.randf_range(-8, 8), Vector3(rng.randf_range(-5, 5), 0, 0)))
		"firepit":
			for k in 9:
				var a := TAU * k / 9.0
				out.append(_p("boulder", Vector3(cos(a) * 1.5, -0.15, sin(a) * 1.5), Vector3(0.75, 0.5, 0.6), STONE_DARK, 0.0, Vector3.ZERO,
					{"seed": k + 9, "weather": 0.3}))
			for k in 4:
				out.append(_p("drum", Vector3(cos(k * 1.7) * 0.5, 0.1, sin(k * 1.7) * 0.5), Vector3(0.28, 1.7, 0), CHAR if k % 2 else WOOD_DARK,
					k * 47.0, Vector3(72, 0, 0), {"sides": 5, "weather": 0.0}))
			out.append(_p("cone", Vector3(0, 0.0, 0), Vector3(1.4, 0.5, 0), EMBER, 0.0, Vector3.ZERO, {"weather": 0.0}))
			out.append(_p("cone", Vector3(0.1, 0.1, -0.1), Vector3(0.7, 1.1, 0), Color(0.95, 0.6, 0.22), 20.0, Vector3.ZERO, {"weather": 0.0}))
		"lookout":
			var h := float(el.get("height", 9.0))
			for c in 4:
				var a := TAU * c / 4.0 + PI * 0.25
				out.append(_p("drum", Vector3(cos(a) * 1.1, -0.4, sin(a) * 1.1), Vector3(0.3, h + 0.6, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 5}))
			out.append(_p("box", Vector3(0, h - 0.2, 0), Vector3(3.2, 0.25, 3.2), WOOD))
			for side: float in [-1.0, 1.0]:
				out.append(_p("box", Vector3(side * 1.55, h + 0.6, 0), Vector3(0.12, 0.12, 3.2), WOOD_DARK))
				out.append(_p("box", Vector3(0, h + 0.6, side * 1.55), Vector3(3.2, 0.12, 0.12), WOOD_DARK))
			out.append(_p("box", Vector3(0.0, -0.2, 2.0), Vector3(0.9, h, 0.1), WOOD, 0.0, Vector3(12, 0, 0)))
			out.append(_p("drum", Vector3(1.3, h, 1.3), Vector3(0.14, 4.0, 0), WOOD_DARK, 0.0, Vector3.ZERO, {"sides": 4}))
			out.append(_p("box", Vector3(2.0, h + 2.4, 1.3), Vector3(1.3, 1.6, 0.06), str(el.get("color", "canvas_red")), 0.0,
				Vector3(0, 0, -6), {"weather": 0.0}))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Hearth", parts(el, ctx))
