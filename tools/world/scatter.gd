class_name WorldScatter
extends RefCounted
## C1b: the merged scatter of a region - small things strewn by a region's scenery rule with "merge": true, built
## into its chunk's structures mesh (one draw with the chunk's works, as a settlement's merged buildings) instead
## of a MultiMesh of one shared shape: every piece its own seeded shape, so no two boulders are the same lump. The
## pieces are weathered (WorldLayout.add_parts' "weather": the frost stone material's snow, lichen and grime).
## Keys (each a few dozen triangles to a couple of hundred, base at y 0, about its natural size at scale 1):
##   boulder      one frost-split stone, 2-4 m (its seed picks the shape, the split face and the stone's colour)
##   scree        a spill of three to six stones fallen together
##   dead_tree    a stunted, wind-killed tree: a twisted trunk and a few bare limbs, about 7 m
##   ice          a cluster of ice shards forced up through the ground, 2-5 m
##   cairn        a waymark of stacked stones, about 3 m
##   giant_bones  the half-buried ribs, spine and skull of one of the old giants, about 30 m long
## Tools only (tools/ is never exported).

const L := preload("res://tools/world/layout.gd")
const KEYS := ["boulder", "scree", "dead_tree", "ice", "cairn", "giant_bones"]
const STONES := [Color(0.42, 0.41, 0.39), Color(0.36, 0.355, 0.34), Color(0.46, 0.45, 0.42), Color(0.39, 0.37, 0.34)]
const BARK := Color(0.34, 0.31, 0.28)
const BONE := Color(0.8, 0.77, 0.69)
const ICE := Color(0.68, 0.8, 0.88)


static func has_key(key: String) -> bool:
	return KEYS.has(key)


## The parts of one piece of `key`, seeded (the same seed, the same piece), in its own frame.
static func parts(key: String, seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2516 + seed * 6007 + KEYS.find(key) * 104729
	var out: Array = []
	match key:
		"boulder":
			var w := rng.randf_range(2.2, 3.6)
			out.append(_stone(Vector3.ZERO, Vector3(w, w * rng.randf_range(0.5, 0.85), w * rng.randf_range(0.7, 1.0)),
				rng, 1 if w > 3.0 else 0))
		"scree":
			var n := rng.randi_range(2, 5)
			for k in n:
				var a := rng.randf_range(0.0, TAU)
				var r := rng.randf_range(0.0, 3.5)
				var w := rng.randf_range(0.7, 1.9) * (1.4 if k == 0 else 1.0)
				out.append(_stone(Vector3(cos(a) * r, -0.15 * w, sin(a) * r), Vector3(w, w * rng.randf_range(0.45, 0.8), w * 0.85), rng, 0))
		"dead_tree":
			var h := rng.randf_range(5.5, 8.0)
			var lean := Vector3(rng.randf_range(-9, 9), 0, rng.randf_range(-9, 9))
			var segs := 4
			var at := Vector3(0, -0.3, 0)
			var d := 0.75
			for k in segs:
				var seg_h := h / segs
				var tilt := lean + Vector3(rng.randf_range(-7, 7), 0, rng.randf_range(-7, 7))
				out.append(_wood("drum", at, Vector3(d, seg_h * 1.08, 0), tilt, rng.randf_range(0, 360), 0.78, rng))
				var bend := Basis.from_euler(Vector3(deg_to_rad(tilt.x), 0, deg_to_rad(tilt.z)))
				at += bend * Vector3(0, seg_h, 0)
				d *= 0.78
				if k >= 1:
					for b in rng.randi_range(1, 2):
						var yaw := rng.randf_range(0, 360)
						var bl := rng.randf_range(1.6, 3.2) * (1.15 - k * 0.15)
						out.append(_wood("drum", at - Vector3(0, seg_h * 0.3, 0), Vector3(d * 0.55, bl, 0),
							Vector3(rng.randf_range(40, 75), 0, 0), yaw, 0.5, rng))
		"ice":
			var n := rng.randi_range(3, 5)
			for k in n:
				var a := rng.randf_range(0.0, TAU)
				var r := rng.randf_range(0.0, 1.8)
				var hh := rng.randf_range(1.6, 4.8) * (1.3 if k == 0 else 1.0)
				var p := L.part("boulder", Vector3(cos(a) * r, -0.4, sin(a) * r), Vector3(hh * 0.32, hh, hh * 0.26), ICE,
					rng.randf_range(0, 360), Vector3(rng.randf_range(-22, 22), 0, rng.randf_range(-22, 22)))
				p["seed"] = rng.randi_range(0, 9999)
				p["rough"] = 0.12
				p["weather"] = 0.25
				out.append(p)
		"cairn":
			var y := -0.2
			var w := rng.randf_range(1.7, 2.2)
			for k in rng.randi_range(4, 6):
				var hh := w * rng.randf_range(0.42, 0.55)
				out.append(_stone(Vector3(rng.randf_range(-0.15, 0.15), y, rng.randf_range(-0.15, 0.15)), Vector3(w, hh, w * 0.9), rng, 0))
				y += hh * 0.82
				w *= 0.8
		"giant_bones":
			# the spine along +z, the ribs arching up off it on both sides, half sunk; the skull at its head
			var length := rng.randf_range(24.0, 30.0)
			var verts := 7
			for k in verts:
				var z := -length * 0.5 + length * k / float(verts - 1)
				out.append(_bone("ellipsoid", Vector3(0, -0.6, z), Vector3(1.6, 1.4, 2.4), Vector3.ZERO, 0.0, rng))
			for k in 6:
				var z := -length * 0.18 + k * 2.6
				for side: float in [-1.0, 1.0]:
					if rng.randf() < 0.18:
						continue
					var r := 6.5 - absf(k - 2.5) * 0.6
					for s in 3:
						var t0 := float(s) / 3.0
						var a0 := lerpf(0.1, 2.3, t0)
						var pos := Vector3(side * sin(a0) * r * 0.9, cos(a0) * r * 0.9 - 2.6, z)
						var seg := r * 0.8
						out.append(_bone("drum", pos, Vector3(0.55, seg, 0), Vector3(0, 0, -side * rad_to_deg(a0 + PI * 0.5)), 0.0, rng))
			out.append(_bone("ellipsoid", Vector3(0.6, -1.4, length * 0.5 + 3.2), Vector3(5.2, 4.6, 6.4), Vector3(0, 0, 24), 18.0, rng))
			out.append(_bone("block", Vector3(1.4, -1.6, length * 0.5 + 6.6), Vector3(3.8, 1.6, 4.2), Vector3(-8, 0, 18), 18.0, rng))
	return out


static func _stone(pos: Vector3, size: Vector3, rng: RandomNumberGenerator, detail: int) -> Dictionary:
	var p := L.part("boulder", pos, size, STONES[rng.randi_range(0, STONES.size() - 1)], rng.randf_range(0, 360),
		Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)))
	p["seed"] = rng.randi_range(0, 99999)
	p["detail"] = detail
	p["weather"] = 0.6
	return p


static func _wood(shape: String, pos: Vector3, size: Vector3, tilt: Vector3, yaw: float, top: float,
		rng: RandomNumberGenerator) -> Dictionary:
	var p := L.part(shape, pos, size, BARK, yaw, tilt)
	p["seed"] = rng.randi_range(0, 99999)
	p["sides"] = 6
	p["top"] = top
	p["rough"] = 0.12
	p["weather"] = 0.55
	return p


static func _bone(shape: String, pos: Vector3, size: Vector3, tilt: Vector3, yaw: float, rng: RandomNumberGenerator) -> Dictionary:
	var p := L.part(shape, pos, size, BONE.darkened(rng.randf_range(0.0, 0.12)), yaw, tilt)
	p["seed"] = rng.randi_range(0, 99999)
	p["sides"] = 6
	p["cols"] = 8
	p["rows"] = 5
	p["top"] = 0.85
	p["weather"] = 0.6
	return p
