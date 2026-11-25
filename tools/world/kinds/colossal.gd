extends RefCounted
## Element kind "colossal" (C1; its look C1b): the old giant kings' works beyond the rim, built at the colossi's scale
## (a 24-29 m giant beside them reads as a man beside a cathedral's ruin), `scale` x their default size, by style:
##   "fallen_king"   the Fallen King - a giant-king's statue that stood about 90 m, thrown down: his feet still on
##                   their stepped plinth with the broken shins; the rest of him on his back along local +z (about
##                   120 m to the crown's place) - the legs broken off at the shins, hips and belt, the chest in its
##                   mantle, one arm along his side, the other flung out with the hand open; the crowned head broken
##                   off at the neck and rolled aside (brow, eyes, nose, beard), the crown lying apart; rubble round
##   "chain_anchor"  a chain anchor of the Worldbreaker's binding: a battered stone drum as tall as a tower in iron
##                   bands (one burst), its rune band, a ring on its crown and a chain of real links each taller than
##                   a house running from it along local -z, down into a heap of broken rock
##   "pier"          a pier of the Kings' Causeway: two pillars of stacked drums and their capitals, a cracked lintel,
##                   frost-heaved paving; `state` "standing" (default), "lintel_fallen" or "toppled" (one pillar
##                   thrown down in its drums)
##   "breach_jaws"   the Breach's mouth: fractured slabs of the split rim leaning on both sides, their rubble, and a
##                   snapped chain lying across (the size gate's wall stands behind them in the layout)
##   "breach_wall"   (C1b) the Breach's walls dressed: walking from `pos` to `to` it finds each wall's foot and face on
##                   the ground and lays talus at the foot, fallen slabs, jutting strata ledges up the face and split
##                   pillars leaning on it - all outside the walkable floor (`half_m` from the axis) and none solid
##   "rimstone"      the Rimstone: one standing stone about 64 m tall, its top weathered, carved bands and a panel of
##                   runes on both faces, six lesser stones round it (one fallen and broken)
##   "split_cairn"   a heap of giant-cut blocks
## Structures mesh (one draw with the chunk's other works); every piece is weathered (WorldLayout.add_parts' "weather":
## the frost stone material's snow, lichen, grime and cracks) and built of the layout's seeded shapes ("block",
## "drum", "boulder", "ellipsoid"). The standing pieces are solids (C1b keeps C1's solids where the works stand).

const L := preload("res://tools/world/layout.gd")

const PALE := Color(0.47, 0.46, 0.44)
const STONE := Color(0.41, 0.405, 0.39)
const DARK := Color(0.32, 0.315, 0.31)
const ROCK := Color(0.37, 0.355, 0.34)
const HOLLOW := Color(0.2, 0.19, 0.19)
const STATUE := Color(0.44, 0.43, 0.41)
const BRONZE := Color(0.55, 0.5, 0.33)
const IRON := Color(0.29, 0.28, 0.28)
const RUST := Color(0.4, 0.3, 0.23)
const RUNE := Color(0.5, 0.72, 0.8)


static func _k(el: Dictionary) -> float:
	return float(el.get("scale", 1.0))


## A weathered part: shape, position and size (unscaled), its colour, yaw and tilt, more keys in `extra`.
static func _p(shape: String, pos: Vector3, size: Vector3, color: Variant, yaw := 0.0, tilt := Vector3.ZERO,
		extra := {}) -> Dictionary:
	var p := L.part(shape, pos, size, color, yaw, tilt)
	p["weather"] = 1.0
	p.merge(extra, true)
	return p


## A worked block ("block" with `seed`, `rough`, `bevel`).
static func _blk(pos: Vector3, size: Vector3, color: Variant, seed: int, yaw := 0.0, tilt := Vector3.ZERO,
		rough := 0.05, bevel := 0.12) -> Dictionary:
	return _p("block", pos, size, color, yaw, tilt, {"seed": seed, "rough": rough, "bevel": bevel})


## A drum lying along its group's +z from `pos` (yaw turns it), `len` long and `d` across, its far end `top` x.
static func _limb(pos: Vector3, d: float, length: float, color: Variant, yaw: float, seed: int, top := 0.85,
		smooth := true) -> Dictionary:
	return _p("drum", pos, Vector3(d, length, 0.0), color, yaw, Vector3(90, 0, 0),
		{"seed": seed, "sides": 10, "rough": 0.03, "top": top, "smooth": smooth})


static func _ell(pos: Vector3, size: Vector3, color: Variant, yaw := 0.0, tilt := Vector3.ZERO) -> Dictionary:
	return _p("ellipsoid", pos, size, color, yaw, tilt, {"smooth": true})


static func _stone(pos: Vector3, size: Vector3, color: Variant, seed: int, detail := 0, yaw := 0.0) -> Dictionary:
	return _p("boulder", pos, size, color, yaw, Vector3.ZERO, {"seed": seed, "detail": detail})


## {"parts": [part], "solids": [solid]} in the element's frame, unscaled (parts() and solids() scale them).
static func _design(el: Dictionary, ctx: Dictionary) -> Dictionary:
	match str(el.get("style", "fallen_king")):
		"fallen_king":
			return _fallen_king()
		"chain_anchor":
			return _chain_anchor(el)
		"pier":
			return _pier(str(el.get("state", "standing")), int(el.get("seed", 0)))
		"breach_jaws":
			return _breach_jaws()
		"breach_wall":
			return _breach_wall(el, ctx)
		"rimstone":
			return _rimstone()
		"split_cairn":
			return _split_cairn(int(el.get("seed", 0)))
	return {"parts": [], "solids": []}


static func _box_solid(pos: Vector3, size: Vector3, yaw := 0.0) -> Dictionary:
	return L.solid("box", pos + Vector3.UP * size.y * 0.5, size, yaw)


# --------------------------------------------------------------------------- the Fallen King

static func _fallen_king() -> Dictionary:
	var parts: Array = []
	var S := STATUE
	# the stepped plinth, its moulding, a corner block thrown off
	parts.append(_blk(Vector3(0, -4, 0), Vector3(48, 6, 34), DARK, 1, 0.0, Vector3.ZERO, 0.03, 0.06))
	parts.append(_blk(Vector3(0, 1.5, 0), Vector3(41, 8, 28), STONE, 2, 0.0, Vector3.ZERO, 0.025, 0.08))
	parts.append(_blk(Vector3(0, 6.3, 0), Vector3(42.4, 1.7, 29.4), DARK, 3, 0.0, Vector3.ZERO, 0.01, 0.35))
	parts.append(_blk(Vector3(27, -1.5, -13), Vector3(9, 6, 8), STONE, 4, 31.0, Vector3(0, 0, 24), 0.08, 0.1))
	# the feet where he stood (he faced +z): each a foot, its toes, an ankle and the broken shin
	for side: float in [-1.0, 1.0]:
		var x := side * 9.0
		parts.append(_blk(Vector3(x, 9.4, 3.0), Vector3(8.6, 4.6, 15.0), S, 10 + int(side), 0.0, Vector3.ZERO, 0.03, 0.32))
		for t in 4:
			var toe := _ell(Vector3(x + (t - 1.5) * 1.95, 9.3, 10.6 - absf(t - 1.5) * 0.5), Vector3(2.0, 2.4, 3.2), S)
			toe["cols"] = 6
			toe["rows"] = 4
			parts.append(toe)
		parts.append(_ell(Vector3(x, 11.0, -1.2), Vector3(8.2, 7.6, 8.4), S))
		var shin := 21.0 if side < 0 else 12.0
		parts.append(_p("drum", Vector3(x, 14.5, -1.0), Vector3(8.4, shin, 0), S, 0.0, Vector3.ZERO,
			{"seed": 20 + int(side), "sides": 14, "rough": 0.035, "top": 1.12, "smooth": true}))
		var top := 14.5 + shin
		parts.append(_blk(Vector3(x - 1.2, top - 1.0, -1.5), Vector3(5.4, 3.6, 5.0), S, 30 + int(side), 25.0, Vector3(14, 0, 18), 0.25, 0.02))
		parts.append(_blk(Vector3(x + 1.6, top - 0.8, 0.4), Vector3(3.6, 2.4, 3.4), S, 32 + int(side), 70.0, Vector3(-10, 0, -16), 0.3, 0.02))
	# the body, thrown down on its back along +z (centre line x -4): broken legs from the shins' break to the hips
	var cx := -4.0
	for side: float in [-1.0, 1.0]:
		var lx := cx + side * 6.2
		parts.append(_blk(Vector3(lx + side * 0.6, -1.5, 17.5), Vector3(6.0, 5.0, 4.0), S, 34 + int(side), side * 20.0, Vector3(-12, 0, side * 14), 0.28, 0.02))
		parts.append(_limb(Vector3(lx, 0.5, 18.0), 8.6, 21.0, S, 0.0, 35 + int(side), 1.16))
		parts.append(_ell(Vector3(lx, -4.0, 40.0), Vector3(10.6, 9.6, 10.0), S))
		parts.append(_limb(Vector3(lx, 1.0, 41.0), 11.0, 22.0, S, 0.0, 37 + int(side), 1.14))
	# the mantle spread under him, in folds
	for f in 7:
		var fx := (f - 3.0) * 6.2
		parts.append(_blk(Vector3(cx + fx * 1.3, -2.2, 76.0 + absf(fx) * 0.3), Vector3(5.8, 3.0 - absf(f - 3.0) * 0.25, 40.0 - absf(f - 3.0) * 3.5),
			STONE, 50 + f, fx * 0.4, Vector3.ZERO, 0.04, 0.4))
	# hips and belt, chest, the shoulders, the breastplate's ridge
	parts.append(_ell(Vector3(cx, -3.0, 64.0), Vector3(25, 12, 15), S))
	parts.append(_blk(Vector3(cx, 5.0, 67.0), Vector3(25.0, 2.4, 4.4), DARK, 60, 0.0, Vector3.ZERO, 0.02, 0.4))
	parts.append(_blk(Vector3(cx, 6.4, 67.0), Vector3(4.6, 2.4, 5.2), BRONZE, 61, 0.0, Vector3.ZERO, 0.02, 0.3))
	parts.append(_ell(Vector3(cx, -4.0, 80.0), Vector3(29, 16, 28), S))
	for side: float in [-1.0, 1.0]:
		parts.append(_ell(Vector3(cx + side * 6.6, 7.2, 84.0), Vector3(11.5, 4.2, 10.5), S))
		parts.append(_ell(Vector3(cx + side * 15.0, -2.5, 90.0), Vector3(12.5, 11.5, 12.5), S))
	parts.append(_blk(Vector3(cx, 9.6, 77.5), Vector3(2.6, 2.0, 14.0), S, 62, 0.0, Vector3.ZERO, 0.02, 0.45))
	# the neck's stump, broken
	parts.append(_limb(Vector3(cx, 2.0, 93.0), 9.0, 5.5, S, 0.0, 63, 1.04))
	parts.append(_blk(Vector3(cx + 1.0, 1.0, 98.0), Vector3(5.0, 4.0, 3.0), S, 64, 15.0, Vector3(20, 0, 10), 0.3, 0.02))
	# the right arm along his side, its fist by the hip
	parts.append(_limb(Vector3(11.0, 0.0, 91.0), 8.2, 19.0, S, 180.0, 70, 0.9))
	parts.append(_ell(Vector3(11.5, -4.0, 71.0), Vector3(8.6, 8.2, 8.6), S))
	parts.append(_limb(Vector3(12.0, 0.0, 71.0), 7.4, 16.0, S, 180.0, 71, 0.8))
	parts.append(_blk(Vector3(12.5, -2.6, 50.5), Vector3(7.2, 5.8, 8.2), S, 72, 0.0, Vector3.ZERO, 0.03, 0.4))
	for t in 4:
		parts.append(_ell(Vector3(10.0 + t * 1.6, 1.3, 47.4), Vector3(1.9, 2.0, 2.4), S))
	# the left arm flung out, the hand open
	parts.append(_limb(Vector3(-19.5, 0.0, 91.0), 8.2, 16.0, S, -43.7, 73, 0.9))
	parts.append(_ell(Vector3(-30.5, -4.0, 102.5), Vector3(8.6, 8.2, 8.6), S))
	parts.append(_limb(Vector3(-30.5, 0.0, 102.5), 7.2, 10.0, S, -45.0, 74, 0.82))
	var hand := {"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(-45.0)), Vector3(-39.5, -1.5, 113.0))}
	parts.append(_p("block", Vector3(0, 0, 0), Vector3(10, 3, 9), S, 0.0, Vector3.ZERO, hand.merged({"seed": 75, "rough": 0.03, "bevel": 0.4})))
	var fingers := [[-3.6, 6.4], [-1.2, 7.4], [1.2, 7.0], [3.6, 3.2]]
	for f: Array in fingers:
		parts.append(_p("drum", Vector3(float(f[0]), 1.4, 4.0), Vector3(2.3, float(f[1]), 0), S, 0.0, Vector3(80, 0, 0),
			hand.merged({"seed": 76, "sides": 8, "rough": 0.04, "top": 0.8, "smooth": true})))
	parts.append(_p("drum", Vector3(5.2, 1.0, 0.5), Vector3(2.6, 5.0, 0), S, 55.0, Vector3(80, 0, 0),
		hand.merged({"seed": 77, "sides": 8, "rough": 0.04, "top": 0.8, "smooth": true})))
	parts.append(_p("drum", Vector3(7.0, -0.8, 11.5), Vector3(2.3, 3.6, 0), S, 20.0, Vector3(90, 0, 12),
		hand.merged({"seed": 78, "sides": 8, "rough": 0.08, "top": 0.9})))
	# the head, broken off at the neck and rolled aside: on its back, face up and turned toward +x, crown to +z
	var head := {"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(18.0)) * Basis(Vector3.BACK, deg_to_rad(-32.0)),
		Vector3(13.0, -2.5, 106.0))}
	parts.append(_p("ellipsoid", Vector3(0, -2.0, 0), Vector3(9.6, 10.0, 12.2), S, 0.0, Vector3.ZERO, head.merged({"smooth": true})))
	parts.append(_p("block", Vector3(0, 6.5, 1.4), Vector3(8.6, 2.0, 2.6), S, 0.0, Vector3.ZERO, head.merged({"seed": 80, "rough": 0.02, "bevel": 0.45})))
	for side: float in [-1.0, 1.0]:
		parts.append(_p("ellipsoid", Vector3(side * 2.1, 6.75, -0.5), Vector3(2.5, 1.1, 1.9), HOLLOW, 0.0, Vector3.ZERO, head.merged({"weather": 0.3})))
		parts.append(_p("ellipsoid", Vector3(side * 3.3, 5.6, -1.9), Vector3(3.2, 2.4, 3.2), S, 0.0, Vector3.ZERO, head.merged({"smooth": true})))
		parts.append(_p("block", Vector3(side * 1.8, 6.6, -4.2), Vector3(3.6, 1.3, 1.7), S, side * 14.0, Vector3.ZERO, head.merged({"seed": 81, "rough": 0.03, "bevel": 0.4})))
		parts.append(_p("ellipsoid", Vector3(side * 4.9, 1.6, -0.6), Vector3(1.6, 3.4, 3.0), S, 0.0, Vector3.ZERO, head.merged({"smooth": true})))
	parts.append(_p("block", Vector3(0, 6.8, -2.0), Vector3(2.0, 2.4, 4.2), S, 0.0, Vector3(-14, 0, 0), head.merged({"seed": 82, "rough": 0.02, "bevel": 0.42})))
	parts.append(_p("block", Vector3(0, 0.0, -9.6), Vector3(8.2, 6.2, 9.0), S, 0.0, Vector3(10, 0, 0), head.merged({"seed": 83, "rough": 0.04, "bevel": 0.3})))
	for b in 3:
		parts.append(_p("drum", Vector3((b - 1) * 2.5, 3.2, -12.5), Vector3(1.9, 6.0, 0), S, 180.0, Vector3(90, 0, 0),
			head.merged({"seed": 84 + b, "sides": 8, "rough": 0.05, "top": 0.55, "smooth": true})))
	# the crown, fallen off and lying on its side
	var crown := {"xform": Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)) * Basis(Vector3.RIGHT, deg_to_rad(72.0)), Vector3(30.0, 1.0, 116.0))}
	for c in 10:
		var a := TAU * c / 10.0
		parts.append(_p("block", Vector3(cos(a) * 6.8, 0, sin(a) * 6.8), Vector3(3.0, 2.8, 4.6), BRONZE, -rad_to_deg(a) + 90.0,
			Vector3.ZERO, crown.merged({"seed": 90 + c, "rough": 0.04, "bevel": 0.2, "weather": 0.8})))
		if c % 2 == 0 and c != 6:
			parts.append(_p("cone", Vector3(cos(a) * 6.8, 2.6, sin(a) * 6.8), Vector3(2.6, 4.6, 0), BRONZE, 0.0, Vector3.ZERO,
				crown.merged({"weather": 0.8})))
	# rubble: broken stone strewn round the pieces
	var rng := RandomNumberGenerator.new()
	rng.seed = 2516
	for r in 16:
		var a := TAU * r / 16.0 + rng.randf_range(-0.2, 0.2)
		var rad := rng.randf_range(20.0, 30.0)
		var at := Vector3(cos(a) * rad - 3.0, -1.2, 58.0 + sin(a) * rad * 2.0)
		var sz := rng.randf_range(2.0, 5.5)
		if r % 3 == 0:
			parts.append(_stone(at, Vector3(sz, sz * 0.6, sz * 0.8), STONE, 100 + r, 0, rng.randf_range(0, 360)))
		else:
			parts.append(_blk(at, Vector3(sz, sz * 0.55, sz * 0.8), S if r % 2 else STONE, 100 + r, rng.randf_range(0, 360),
				Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15)), 0.2, 0.03))
	# the solids where he lies: the plinth and the shins (C1's), the legs, the body, the head, the flung arm and hand
	var solids: Array = [
		_box_solid(Vector3(0, -2, 0), Vector3(44, 12, 30)),
		_box_solid(Vector3(-9, 10, 0), Vector3(10, 26, 11)),
		_box_solid(Vector3(9, 10, 1), Vector3(10, 17, 11), 4.0),
		_box_solid(Vector3(cx, -2, 40.0), Vector3(24, 10, 46)),
		_box_solid(Vector3(cx, -2, 78.0), Vector3(32, 14, 32)),
		_box_solid(Vector3(13, -2, 106), Vector3(14, 14, 16), 18.0),
		_box_solid(Vector3(-29.0, -1, 102.0), Vector3(9, 8, 30), -43.7),
		_box_solid(Vector3(-39.5, -3, 113.0), Vector3(12, 8, 12), -45.0),
	]
	return {"parts": parts, "solids": solids}


# --------------------------------------------------------------------------- the chain anchors

## One chain link (an oval of four bars, its long axis z) with its group transform `xf`.
static func _link(xf: Transform3D, length: float, width: float, bar: float, color: Color, seed: int) -> Array:
	var g := {"xform": xf, "weather": 0.7}
	var out: Array = []
	for side: float in [-1.0, 1.0]:
		out.append(_p("box", Vector3(side * (width - bar) * 0.5, -bar * 0.5, 0), Vector3(bar, bar, length), color, 0.0, Vector3.ZERO, g))
		out.append(_p("box", Vector3(0, -bar * 0.5, side * (length - bar) * 0.5), Vector3(width, bar, bar), color, 0.0, Vector3.ZERO, g))
	return out


static func _chain_anchor(el: Dictionary) -> Dictionary:
	var parts: Array = []
	parts.append(_blk(Vector3(0, -4.5, 0), Vector3(31, 5, 31), DARK, 1, 12.0, Vector3.ZERO, 0.05, 0.1))
	parts.append(_p("drum", Vector3(0, -3, 0), Vector3(26, 40, 0), DARK, 0.0, Vector3.ZERO,
		{"seed": 2, "sides": 18, "rough": 0.02, "top": 0.73, "smooth": true}))
	# the iron bands; the middle one burst, its pieces sprung and one hanging
	for b in 3:
		var y := 4.0 + b * 11.0
		var d := 25.6 - b * 2.2
		if b != 1:
			parts.append(_p("drum", Vector3(0, y, 0), Vector3(d, 2.6, 0), IRON if b == 0 else RUST, 0.0, Vector3.ZERO,
				{"seed": 3 + b, "sides": 18, "rough": 0.008, "top": 0.99, "weather": 0.7}))
			continue
		for s in 12:
			if s == 3 or s == 4 or s == 9:
				continue
			var a := TAU * s / 12.0
			var r := d * 0.5 + (0.6 if s == 5 else 0.0)
			parts.append(_p("box", Vector3(cos(a) * r, y, sin(a) * r), Vector3(1.0, 2.6, d * 0.27), RUST, -rad_to_deg(a),
				Vector3(0, 0, 8.0 if s == 5 else 0.0), {"weather": 0.7}))
	# the rune band under the cap, its marks worn
	parts.append(_p("drum", Vector3(0, 30.5, 0), Vector3(20.8, 2.2, 0), STONE, 0.0, Vector3.ZERO,
		{"seed": 7, "sides": 18, "rough": 0.01, "top": 0.98}))
	for g in 9:
		var a := TAU * g / 9.0 + 0.2
		parts.append(_p("box", Vector3(cos(a) * 10.45, 30.7, sin(a) * 10.45), Vector3(0.5, 1.6, 0.9 + (g % 3) * 0.5), RUNE,
			-rad_to_deg(a), Vector3(0, 0, (g % 2) * 30.0 - 15.0), {"weather": 0.2}))
	parts.append(_p("drum", Vector3(0, 37, 0), Vector3(19.2, 4, 0), STONE, 0.0, Vector3.ZERO,
		{"seed": 8, "sides": 18, "rough": 0.03, "top": 0.74, "smooth": true}))
	# the shackle and the ring on the crown (in the plane facing the chain)
	parts.append(_blk(Vector3(0, 40.5, 0), Vector3(6, 4.5, 7), IRON, 9, 0.0, Vector3.ZERO, 0.03, 0.3))
	for r in 14:
		var a := TAU * r / 14.0
		parts.append(_p("box", Vector3(0, 52 + sin(a) * 8.6, cos(a) * 8.6), Vector3(3.2, 3.4, 4.6), IRON if r % 3 else RUST,
			0.0, Vector3(-rad_to_deg(a) + 90.0, 0, 0), {"weather": 0.7}))
	# the chain: links alternately flat and on edge, descending along -z into the ground
	var n := int(el.get("links", 9))
	var drop := float(el.get("drop_m", 60.0))
	for c in n:
		var t := float(c) / float(maxi(1, n - 1))
		var z := -(12.0 + c * 8.2)
		var y := 44.0 - t * (44.0 + drop * 0.25) - t * t * drop * 0.6
		var slope := atan2(44.0 + drop, 8.2 * n) * (0.6 + 0.8 * t)
		var basis := Basis(Vector3.RIGHT, -slope)
		if c % 2 == 1:
			basis = basis * Basis(Vector3.BACK, PI * 0.5)
		parts.append_array(_link(Transform3D(basis, Vector3(0, y, z)), 11.0, 6.6, 2.0, IRON if c % 3 else RUST, 50 + c))
	# where the chain goes under: a heap of broken rock
	var under := -(12.0 + n * 8.2)
	for h in 5:
		var a := TAU * h / 5.0
		parts.append(_stone(Vector3(cos(a) * 6.0, -2.5, under + sin(a) * 5.0), Vector3(8 - h * 0.6, 5 - h * 0.4, 7), ROCK, 60 + h, 1, h * 47.0))
	parts.append(_blk(Vector3(2, -2, under + 2), Vector3(12, 5, 9), DARK, 66, 12.0, Vector3(0, 0, 6), 0.15, 0.04))
	return {"parts": parts, "solids": [L.solid("cyl", Vector3(0, -3, 0) + Vector3.UP * 20.0, Vector3(26, 40, 0))]}


# --------------------------------------------------------------------------- the Kings' Causeway

static func _pillar(side: float, top_y: float, seed: int) -> Array:
	var out: Array = []
	var x := side * 14.0
	out.append(_blk(Vector3(x, -2.5, 0), Vector3(9.4, 3.2, 9.4), DARK, seed, 0.0, Vector3.ZERO, 0.04, 0.1))
	var y := 0.4
	var k := 0
	while y < top_y - 1.0:
		var h := minf(7.6, top_y - y)
		out.append(_blk(Vector3(x + sin(k * 2.1 + seed) * 0.25, y, cos(k * 1.7 + seed) * 0.25), Vector3(7.0, h, 7.0), PALE if k % 2 else STONE,
			seed * 10 + k, sin(k * 3.3 + seed) * 3.0, Vector3.ZERO, 0.05, 0.14))
		y += h
		k += 1
	return out


static func _pier(state: String, seed: int) -> Dictionary:
	var parts: Array = []
	var solids: Array = []
	# the paving, frost-heaved
	var rng := RandomNumberGenerator.new()
	rng.seed = 4231 + seed
	for i in 4:
		for j in 2:
			parts.append(_blk(Vector3(-13.5 + i * 9.0 + rng.randf_range(-0.4, 0.4), -1.0, -3.4 + j * 6.8), Vector3(8.6, 1.4, 6.5), DARK if (i + j) % 2 else STONE,
				seed * 100 + i * 2 + j, rng.randf_range(-3, 3), Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)), 0.04, 0.08))
	var fallen := state == "toppled"
	for side: float in [-1.0, 1.0]:
		var down := fallen and side < 0.0
		parts.append_array(_pillar(side, 10.0 if down else 31.0, seed + int(side) + 3))
		if down:
			# its broken top, and its drums and capital lying in a line
			parts.append(_blk(Vector3(side * 14.0 + 0.6, 9.2, 0.2), Vector3(5.0, 3.0, 4.6), PALE, seed + 40, 30.0, Vector3(14, 0, 16), 0.3, 0.02))
			for d in 3:
				parts.append(_blk(Vector3(side * 14.0 - 2.0 - d * 1.2, 1.2, 9.0 + d * 8.2), Vector3(7.0, 7.4, 7.0), PALE if d % 2 else STONE,
					seed + 41 + d, 8.0 + d * 9.0, Vector3(90, 0, d * 4.0), 0.06, 0.14))
			parts.append(_blk(Vector3(side * 14.0 - 6.0, -1.0, 34.0), Vector3(9.4, 3.0, 9.4), STONE, seed + 45, 25.0, Vector3(0, 0, 18), 0.06, 0.1))
			solids.append(_box_solid(Vector3(side * 14.0, -2, 0), Vector3(7, 12, 7)))
			continue
		parts.append(_blk(Vector3(side * 14.0, 30.5, 0), Vector3(9.6, 3.0, 9.6), STONE, seed + 50 + int(side), 0.0, Vector3.ZERO, 0.03, 0.12))
		parts.append(_blk(Vector3(side * 14.0, 29.6, 0), Vector3(8.2, 1.0, 8.2), DARK, seed + 52 + int(side), 0.0, Vector3.ZERO, 0.01, 0.3))
		solids.append(_box_solid(Vector3(side * 14.0, -2, 0), Vector3(7, 34, 7)))
	match state:
		"standing":
			parts.append(_blk(Vector3(-6, 33.5, 0), Vector3(20, 5, 8), PALE, seed + 60, 0.0, Vector3(0, 0, -3), 0.04, 0.1))
			parts.append(_blk(Vector3(-6, 33.4, 4.05), Vector3(19, 1.0, 0.4), DARK, seed + 61, 0.0, Vector3(0, 0, -3), 0.0, 0.2))
			parts.append(_blk(Vector3(12, 33.2, 0), Vector3(9, 5, 8), STONE, seed + 62, 0.0, Vector3(0, 0, 14), 0.06, 0.08))
		_:
			# the lintel down: broken in two across the paving, one end propped on the rubble
			parts.append(_blk(Vector3(-2, 0.0, 8.0), Vector3(17, 5, 8), PALE, seed + 63, 9.0, Vector3(0, 0, 7), 0.05, 0.08))
			parts.append(_blk(Vector3(13, -0.6, 10.5), Vector3(11, 5, 8), STONE, seed + 64, -14.0, Vector3(-6, 0, -12), 0.06, 0.06))
			for r in 4:
				parts.append(_stone(Vector3(-8.0 + r * 6.0, -0.8, 13.0 + (r % 2) * 2.0), Vector3(3.0, 2.0, 2.6), PALE, seed + 70 + r, 0, r * 70.0))
	return {"parts": parts, "solids": solids}


# --------------------------------------------------------------------------- the Breach

static func _breach_jaws() -> Dictionary:
	var parts: Array = []
	var solids: Array = []
	for side: float in [-1.0, 1.0]:
		for s in 4:
			var pos := Vector3(side * (34 + s * 7), -4, -8 + s * 9)
			var size := Vector3(12, 38 + s * 9, 10)
			var yaw := side * (8.0 + s * 5.0)
			parts.append(_blk(pos, size, ROCK if s % 2 else DARK, 200 + s * 2 + int(side), yaw,
				Vector3(-6 + s * 4, 0, -side * (10 + s * 3)), 0.09, 0.04))
			if s < 2:
				solids.append(_box_solid(pos, size, yaw))
		# their spalls and rubble at the feet
		for r in 5:
			var at := Vector3(side * (36 + r * 5.5), -2.0, -14 + r * 7.5)
			parts.append(_stone(at, Vector3(6.0 + (r % 3) * 2.0, 3.6 + (r % 2) * 2.0, 5.0 + (r % 2)), ROCK, 220 + r * 2 + int(side), 1, r * 61.0))
		parts.append(_blk(Vector3(side * 44, -2.0, 18.0), Vector3(16, 4, 9), DARK, 230 + int(side), side * 22.0, Vector3(0, 0, side * 9.0), 0.1, 0.03))
	# the snapped chain across the mouth, its broken ends apart
	for c in 7:
		if c == 3:
			continue
		var x := -28.0 + c * 8.5
		var basis := Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.BACK, deg_to_rad((c - 3) * 3.0))
		if c % 2 == 1:
			basis = basis * Basis(Vector3.BACK, PI * 0.5)
		parts.append_array(_link(Transform3D(basis, Vector3(x, 0.6 if c % 2 == 0 else 2.6, 4.0)), 10.0, 6.0, 1.8, IRON if c % 3 else RUST, 240 + c))
	return {"parts": parts, "solids": solids}


## The Breach's walls dressed (C1b): from `pos` along to `to`, every `step_m`, on each side the wall's foot (the ground
## `foot_m` over the floor at the axis) and its face at a few heights, read off the height field.
static func _breach_wall(el: Dictionary, ctx: Dictionary) -> Dictionary:
	var parts: Array = []
	if not ctx.has("field") or not ctx.has("frame"):
		return {"parts": parts, "solids": []}
	var f: HeightField = ctx.field
	var xf: Transform3D = ctx.frame
	var inv := xf.affine_inverse()
	var a := L.pos2(el)
	var b := WorldFeatures.v2(el.get("to", [a.x, a.y - 100.0]))
	var half := float(el.get("half_m", 35.0))
	var step := float(el.get("step_m", 24.0))
	var dir := (b - a).normalized()
	var across := Vector2(-dir.y, dir.x)
	var n := maxi(1, int(a.distance_to(b) / step))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9001 + int(el.get("seed", 0))
	var along_yaw := rad_to_deg(atan2(dir.x, dir.y)) - rad_to_deg(xf.basis.get_euler().y)
	for i in n + 1:
		var c := a + dir * (i * step + rng.randf_range(-4.0, 4.0))
		var floor_y := f.sample(c.x, c.y)
		for side: float in [-1.0, 1.0]:
			var face := {}
			var d := half
			while d < half + 160.0:
				var p := c + across * side * d
				var rise := f.sample(p.x, p.y) - floor_y
				for h: float in [14.0, 40.0, 75.0, 115.0, 160.0]:
					if rise >= h and not face.has(h):
						face[h] = d
				d += 2.0
			if not face.has(14.0):
				continue
			var foot: float = maxf(float(face[14.0]) - 6.0, half + 1.0)
			# talus at the foot
			for t in rng.randi_range(2, 3):
				var p := c + across * side * (foot + rng.randf_range(0.0, 10.0)) + dir * rng.randf_range(-9.0, 9.0)
				var s := rng.randf_range(5.0, 12.0)
				parts.append(_stone(inv * Vector3(p.x, f.sample(p.x, p.y) - s * 0.22, p.y), Vector3(s, s * rng.randf_range(0.5, 0.75), s * 0.85),
					ROCK if t % 2 else DARK, rng.randi_range(0, 99999), 1, rng.randf_range(0, 360)))
			# a slab fallen from the face
			if rng.randf() < 0.45:
				var p := c + across * side * (foot + 4.0) + dir * rng.randf_range(-6.0, 6.0)
				parts.append(_blk(inv * Vector3(p.x, f.sample(p.x, p.y) - 2.0, p.y), Vector3(rng.randf_range(14, 22), rng.randf_range(3, 5), rng.randf_range(8, 12)),
					DARK, rng.randi_range(0, 99999), along_yaw + rng.randf_range(-25, 25), Vector3(rng.randf_range(-6, 6), 0, side * rng.randf_range(6, 16)), 0.1, 0.03))
			# strata ledges jutting from the face
			for h: float in [40.0, 75.0, 115.0, 160.0]:
				if not face.has(h) or rng.randf() < 0.3:
					continue
				var p := c + across * side * (float(face[h]) + 3.0) + dir * rng.randf_range(-6.0, 6.0)
				var size := Vector3(rng.randf_range(8, 11), rng.randf_range(3, 6), rng.randf_range(16, 30))
				parts.append(_blk(inv * Vector3(p.x, floor_y + h - size.y * 0.7, p.y), size, ROCK if rng.randf() < 0.5 else DARK,
					rng.randi_range(0, 99999), along_yaw, Vector3(rng.randf_range(-3, 3), 0, side * rng.randf_range(-8, 2)), 0.08, 0.05))
			# a split pillar leaning on the face
			if face.has(40.0) and rng.randf() < 0.35:
				var p := c + across * side * (float(face[14.0]) + 2.0) + dir * rng.randf_range(-5.0, 5.0)
				var hh := rng.randf_range(34, 58)
				parts.append(_blk(inv * Vector3(p.x, f.sample(p.x, p.y) - 4.0, p.y), Vector3(rng.randf_range(8, 12), hh, rng.randf_range(7, 10)),
					ROCK, rng.randi_range(0, 99999), along_yaw + rng.randf_range(-12, 12), Vector3(0, 0, side * -rng.randf_range(6, 12)), 0.07, 0.04))
	return {"parts": parts, "solids": []}


# --------------------------------------------------------------------------- the Rimstone, the cairns

static func _rimstone() -> Dictionary:
	var parts: Array = []
	var lean := {"xform": Transform3D(Basis(Vector3.BACK, deg_to_rad(2.0)), Vector3.ZERO)}
	parts.append(_p("block", Vector3(0, -3, 0), Vector3(13, 64, 8), Color(0.38, 0.38, 0.39), 0.0, Vector3.ZERO,
		lean.merged({"seed": 1, "rough": 0.03, "bevel": 0.16})))
	parts.append(_p("boulder", Vector3(0.6, 57.5, 0), Vector3(12.4, 7.5, 8.2), Color(0.38, 0.38, 0.39), 0.0, Vector3.ZERO,
		lean.merged({"seed": 2, "detail": 1, "rough": 0.16})))
	for y: float in [9.0, 21.0, 48.5]:
		parts.append(_p("block", Vector3(0, y, 0), Vector3(13.7, 1.5, 8.7), Color(0.48, 0.47, 0.46), 0.0, Vector3.ZERO,
			lean.merged({"seed": int(y), "rough": 0.008, "bevel": 0.35})))
	# the rune panels: worn glyphs cut in both broad faces
	var rng := RandomNumberGenerator.new()
	rng.seed = 64
	for face: float in [-1.0, 1.0]:
		for col in 3:
			for row in 5:
				var cx := (col - 1) * 2.6
				var cy := 30.0 + row * 3.4
				for s in rng.randi_range(2, 3):
					var vertical := rng.randf() < 0.55
					var size := Vector3(0.5, rng.randf_range(1.6, 2.8), 0.4) if vertical else Vector3(rng.randf_range(1.2, 2.0), 0.5, 0.4)
					parts.append(_p("box", Vector3(cx + rng.randf_range(-0.7, 0.7), cy + rng.randf_range(-0.6, 0.6), face * 4.02), size, RUNE,
						0.0, Vector3(0, 0, rng.randf_range(-35, 35) if not vertical else 0.0), lean.merged({"weather": 0.25})))
	# the lesser stones round it, the fifth fallen and broken in two
	for s in 6:
		var a := TAU * s / 6.0 + 0.3
		var at := Vector3(cos(a) * 36, -2, sin(a) * 36)
		var h := 24.0 + (s % 3) * 6.0
		if s == 4:
			parts.append(_blk(at + Vector3(0, -1, 0), Vector3(h * 0.55, 4.0, 7.0), STONE, 300 + s, -rad_to_deg(a), Vector3(0, 0, 4), 0.08, 0.1))
			parts.append(_blk(at + Vector3(cos(a) * 11.0, -1.4, sin(a) * 11.0), Vector3(h * 0.4, 4.0, 6.6), STONE, 310 + s, -rad_to_deg(a) + 12.0,
				Vector3(0, 0, -6), 0.1, 0.08))
			continue
		parts.append(_blk(at, Vector3(7, h, 4.4), PALE if s % 2 else STONE, 300 + s, -rad_to_deg(a) + 90.0, Vector3(0, 0, 8 + (s % 2) * 6), 0.07, 0.14))
		parts.append(_stone(at + Vector3(cos(a + 0.6) * 6.0, -1.0, sin(a + 0.6) * 6.0), Vector3(3.2, 2.0, 2.8), STONE, 320 + s, 0, s * 50.0))
	var solids: Array = [_box_solid(Vector3(0, -3, 0), Vector3(13, 67, 8))]
	for s in 6:
		if s == 4:
			continue
		var a := TAU * s / 6.0 + 0.3
		solids.append(_box_solid(Vector3(cos(a) * 36, -2, sin(a) * 36), Vector3(7, 24 + (s % 3) * 6, 4), -rad_to_deg(a) + 90.0))
	return {"parts": parts, "solids": solids}


static func _split_cairn(seed: int) -> Dictionary:
	var parts: Array = []
	var solids: Array = []
	for s in 7:
		var a := TAU * s / 7.0
		var pos := Vector3(cos(a) * 7, -1 + (s % 3) * 4, sin(a) * 7)
		var size := Vector3(9, 7, 8)
		parts.append(_blk(pos, size, PALE if s % 2 else STONE, 400 + seed * 10 + s, s * 31.0, Vector3((s % 2) * 8.0, 0, 0), 0.08, 0.12))
		if s < 4:
			solids.append(_box_solid(pos, size, s * 31.0))
	for r in 4:
		var a := TAU * r / 4.0 + 0.4
		parts.append(_stone(Vector3(cos(a) * 14, -1, sin(a) * 14), Vector3(4.0, 2.6, 3.4), STONE, 420 + seed * 10 + r, 0, r * 80.0))
	return {"parts": parts, "solids": solids}


# --------------------------------------------------------------------------- the kind's interface

static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var k := _k(el)
	var out: Array = []
	for p: Dictionary in _design(el, ctx).parts:
		var q := p.duplicate()
		q.pos = (p.pos as Vector3) * k
		q.size = (p.size as Vector3) * k
		if p.has("xform"):
			var g: Transform3D = p.xform
			q.xform = Transform3D(g.basis, g.origin * k)
		out.append(q)
	return out


## The standing pieces as solids (C1's, where the works stand).
static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	if bool(el.get("no_solids", false)):
		return []
	var k := _k(el)
	var out: Array = []
	for s: Dictionary in _design(el, ctx).solids:
		var q := s.duplicate()
		q.center = (s.center as Vector3) * k
		q.size = (s.size as Vector3) * k
		out.append(q)
	return out


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Colossal", parts(el, ctx))
