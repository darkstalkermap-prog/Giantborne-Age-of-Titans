extends RefCounted
## Element kind "quarry" (A3): the works of the Stoneback quarry beside Millford (tools/data/world/crownmarch.json),
## merged into its chunk's structures mesh as every static element is (or a FlagVisibility node when a flag shows
## it: the abandoned works before Stoneback falls, the reopened ones after). Styles:
##   terrace  the cut stone faces of a quarry pit's benches (features.gd's "quarry"): about `pos` (the pit's
##            centre, at the explicit `y` of the bench below the face) an arc of quarried courses from `from_deg`
##            to `to_deg` (0 along +x, 90 along +z) at `radius` (where the face begins), `height` tall (the riser)
##            and `thick` deep, in `seg_m` pieces - each two courses of dressed blocks, set a little out of line -
##            standing over the terrain's own sloped riser, only where the bench above it is cut (the ground behind
##            the face stands at its top: on the pit's open side there is none). Solids: the faces (a charge
##            meets them as a wall).
##   crane    a timber treadwheel crane `size` [h] tall: a braced mast on a timber base, a jib reaching out along
##            local -z with its rope and a hanging block, the treadwheel at its foot; `broken` lays the jib on the
##            ground beside a leaning mast (the quarry abandoned).
##   shed     an open-fronted lean-to `size` [w, h, d]: posts, a back wall, a sloping plank roof, tools racked.
##   blocks   cut blocks stacked `size` [w, h, d] (rows of dressed stone; `count` of them, set by the element's
##            id so each stack differs).
##   cart     a two-wheeled stone cart `size` [length]; `loaded` carries blocks; `overturned` lies on its side.
##   spoil    a heap of quarry spoil `size` [w, h, d] with a few loose boulders.
##   monolith one of the quarry's standing stones, `size` [w, h, d]: a weathered, leaning slab of dark stone older
##            than the quarry, a block fallen at its foot. Solid (his charge breaks on it).
## Positions are the element's own frame (layout.gd), the ground under `pos` unless `y` is given.

const L := preload("res://tools/world/layout.gd")
## The quarried stone's own tones (the palette's stone reads near white in the world's sun): a weathered face, a
## fresh-cut one, the standing stones' old dark rock.
const FACE := Color(0.36, 0.34, 0.31)
const FACE_FRESH := Color(0.47, 0.44, 0.40)
const OLD_ROCK := Color(0.29, 0.28, 0.27)


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	match str(el.get("style", "blocks")):
		"terrace":
			return _terrace(el, ctx, false)
		"crane":
			return _crane(el)
		"shed":
			return _shed(el)
		"cart":
			return _cart(el)
		"spoil":
			return _spoil(el)
		"monolith":
			return _monolith(el)
	return _blocks(el)


static func solids(el: Dictionary, ctx: Dictionary) -> Array:
	match str(el.get("style", "blocks")):
		"terrace":
			return _terrace(el, ctx, true)
		"crane":
			var h := L.size3(el, Vector3(14, 14, 14)).x
			if bool(el.get("broken", false)):
				return [L.solid("box", Vector3(0, 0.6, 0), Vector3(3.2, 1.2, 3.2))]
			return [L.solid("box", Vector3(0, h * 0.5, 0), Vector3(1.4, h, 1.4))]
		"shed":
			var s := L.size3(el, Vector3(9, 4.5, 5))
			return [L.solid("box", Vector3(0, s.y * 0.5, -s.z * 0.45), Vector3(s.x, s.y, 0.6))]
		"blocks":
			var s := L.size3(el, Vector3(6, 3, 4))
			return [L.solid("box", Vector3(0, s.y * 0.5 - 0.2, 0), Vector3(s.x, s.y + 0.4, s.z))]
		"spoil":
			var s := L.size3(el, Vector3(10, 4, 8))
			return [L.solid("box", Vector3(0, s.y * 0.3, 0), Vector3(s.x * 0.7, s.y * 0.6, s.z * 0.7))]
		"monolith":
			var s := L.size3(el, Vector3(7, 15, 7))
			return [L.solid("box", Vector3(0, s.y * 0.5 - 1.0, 0), Vector3(s.x * 0.85, s.y + 2.0, s.z * 0.85))]
	return []


## A small deterministic value 0..1 for the n-th piece of an element (its id's hash).
static func _rand(el: Dictionary, n: int) -> float:
	return float(hash(str(el.get("id", el.get("pos", ""))) + ":" + str(n)) % 1000) / 999.0


# --------------------------------------------------------------------------- the terrace faces

static func _terrace(el: Dictionary, ctx: Dictionary, as_solids: bool) -> Array:
	var out: Array = []
	var f: HeightField = ctx.get("field")
	var xf: Transform3D = ctx.get("frame", Transform3D.IDENTITY)
	var r := float(el.get("radius", 34.0))
	var h := float(el.get("height", 7.0))
	var thick := float(el.get("thick", 3.6))
	var seg := float(el.get("seg_m", 7.0))
	var a0 := deg_to_rad(float(el.get("from_deg", 0.0)))
	var a1 := deg_to_rad(float(el.get("to_deg", 360.0)))
	# the face stands a metre in front of the riser's foot and reaches past its top (the terrain's riser, sampled every
	# 4 m, zigzags across the cut: the courses cover it)
	var rc := r - 1.0 + thick * 0.5
	var n := maxi(1, int(ceil(absf(a1 - a0) * rc / seg)))
	var base := xf.origin.y
	for k in n:
		var a := lerpf(a0, a1, (float(k) + 0.5) / float(n))
		var dir := Vector2(cos(a), sin(a))
		# the bench above this face: cut only where the ground behind the face stands at the face's top
		var behind := Vector2(xf.origin.x, xf.origin.z) + dir * (r + thick + 1.5)
		if f != null and f.sample(behind.x, behind.y) < base + h - 1.0:
			continue
		var at := Vector3(dir.x * rc, 0.0, dir.y * rc)
		var yaw := -rad_to_deg(a) - 90.0   # the course's length along the arc
		var length := absf(a1 - a0) * rc / float(n) + 0.6
		var jog := (_rand(el, k) - 0.5) * 0.7
		if as_solids:
			out.append(L.solid("box", at + Vector3(0, h * 0.5 - 0.5, 0), Vector3(length, h + 1.0, thick), yaw))
			continue
		var lower := h * (0.45 + 0.15 * _rand(el, k + 100))
		out.append(L.part("box", at + Vector3(0, -1.0, 0), Vector3(length, lower + 1.0, thick),
			FACE if k % 2 == 0 else FACE_FRESH, yaw))
		out.append(L.part("box", at + Vector3(dir.x * jog, lower, dir.y * jog), Vector3(length - 0.4,
			h - lower + 0.8, thick - 0.3), FACE_FRESH if k % 2 == 0 else FACE, yaw))
		# a dressed block left standing on the course's top now and then
		if _rand(el, k + 200) > 0.6:
			out.append(L.part("box", at + Vector3(0, h + 0.8, -0.3), Vector3(2.2, 1.3, 1.6), FACE_FRESH,
				yaw + 8.0 * (_rand(el, k + 300) - 0.5)))
	return out


# --------------------------------------------------------------------------- the works

static func _crane(el: Dictionary) -> Array:
	var h := L.size3(el, Vector3(14, 14, 14)).x
	var out: Array = []
	out.append(L.part("box", Vector3(0, -0.4, 0), Vector3(4.0, 0.8, 4.0), "timber_dark"))
	if bool(el.get("broken", false)):
		# abandoned: the mast leaning on its cracked base, the jib fallen beside it, the wheel on its side
		out.append(L.part("box", Vector3(0.6, 0.2, 0), Vector3(0.8, h * 0.7, 0.8), "timber", 0.0, Vector3(0, 0, -24)))
		out.append(L.part("box", Vector3(-1.5, 0.2, -h * 0.3), Vector3(0.6, 0.6, h * 0.75), "timber", 14.0))
		out.append(L.part("cyl", Vector3(3.6, 0.0, 2.4), Vector3(4.2, 1.2, 4.2), "timber_dark"))
		out.append(L.part("box", Vector3(-3.0, 0.0, -h * 0.55), Vector3(2.4, 1.4, 1.8), "stone_light", 20.0))
		return out
	out.append(L.part("box", Vector3(0, 0, 0), Vector3(0.9, h, 0.9), "timber"))
	# two braces from the base to the mast
	out.append(L.part("box", Vector3(1.2, 0, 0), Vector3(0.4, h * 0.45, 0.4), "timber_dark", 0.0, Vector3(0, 0, 22)))
	out.append(L.part("box", Vector3(-1.2, 0, 0), Vector3(0.4, h * 0.45, 0.4), "timber_dark", 0.0, Vector3(0, 0, -22)))
	out.append(L.part("box", Vector3(0, 0, 1.2), Vector3(0.4, h * 0.45, 0.4), "timber_dark", 0.0, Vector3(-22, 0, 0)))
	# the jib: from the mast's top out along -z, tilted up
	var jib := h * 0.7
	out.append(L.part("box", Vector3(0, h - 1.2, 0), Vector3(0.6, jib, 0.6), "timber", 0.0, Vector3(-62, 0, 0)))
	var tip := Vector3(0, h - 1.2 + jib * cos(deg_to_rad(62.0)), -jib * sin(deg_to_rad(62.0)))
	# the rope and the hanging block
	var hang := clampf(tip.y - 3.0, 2.0, h)
	out.append(L.part("box", Vector3(0, tip.y - hang, tip.z), Vector3(0.12, hang, 0.12), "dark"))
	out.append(L.part("box", Vector3(0, tip.y - hang - 1.3, tip.z), Vector3(2.2, 1.3, 1.5), "stone_light"))
	# the treadwheel beside the mast (its axle across x)
	out.append(L.part("cyl", Vector3(2.4, 2.6, 0), Vector3(5.0, 1.4, 5.0), "timber_dark", 0.0, Vector3(0, 0, 90)))
	out.append(L.part("box", Vector3(2.4, 0, 0), Vector3(0.5, 2.6, 0.5), "timber"))
	return out


static func _shed(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(9, 4.5, 5))
	var out: Array = []
	for x: float in [-0.46, 0.0, 0.46]:
		out.append(L.part("box", Vector3(s.x * x, 0, s.z * 0.42), Vector3(0.4, s.y * 0.8, 0.4), "timber_dark"))
	out.append(L.part("box", Vector3(0, -0.2, -s.z * 0.45), Vector3(s.x, s.y + 0.2, 0.5), "timber"))
	out.append(L.part("box", Vector3(-s.x * 0.48, -0.2, 0), Vector3(0.4, s.y * 0.9, s.z), "timber"))
	out.append(L.part("box", Vector3(0, s.y * 0.8, 0), Vector3(s.x + 0.8, 0.3, s.z + 1.4), "roof_slate", 0.0, Vector3(-9, 0, 0)))
	# tools racked on the back wall and a stack of wedges
	for k in 4:
		out.append(L.part("box", Vector3(-s.x * 0.3 + k * 0.9, 0.2, -s.z * 0.36), Vector3(0.15, 2.2, 0.15), "timber_dark",
			0.0, Vector3(0, 0, 6.0 * (k % 2) - 3.0)))
	out.append(L.part("box", Vector3(s.x * 0.25, 0, -s.z * 0.15), Vector3(2.0, 0.9, 1.4), "iron"))
	return out


static func _blocks(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(6, 3, 4))
	var out: Array = []
	var bw := 2.2
	var bh := 1.25
	var bd := 1.6
	var cols := maxi(1, int(s.x / bw))
	var rows := maxi(1, int(s.z / bd))
	var layers := maxi(1, int(s.y / bh))
	var i := 0
	for y in layers:
		for z in rows:
			for x in cols - y:
				i += 1
				if _rand(el, i) > 0.85:
					continue
				var p := Vector3(-s.x * 0.5 + (x + 0.5 + y * 0.5) * bw, y * bh, -s.z * 0.5 + (z + 0.5) * bd)
				out.append(L.part("box", p, Vector3(bw - 0.1, bh - 0.05, bd - 0.1),
					FACE_FRESH if (x + y + z) % 3 != 0 else FACE, 6.0 * (_rand(el, i + 50) - 0.5)))
	return out


static func _cart(el: Dictionary) -> Array:
	var length := L.size3(el, Vector3(4.5, 1, 1)).x
	var out: Array = []
	var tilt := Vector3(0, 0, 78) if bool(el.get("overturned", false)) else Vector3.ZERO
	var lift := 0.6 if tilt == Vector3.ZERO else 1.1
	out.append(L.part("box", Vector3(0, lift + 0.5, 0), Vector3(2.2, 0.35, length), "timber", 0.0, tilt))
	out.append(L.part("box", Vector3(0, lift + 0.85, length * 0.5 - 0.1), Vector3(2.2, 0.6, 0.15), "timber_dark", 0.0, tilt))
	for sx: float in [-1.25, 1.25]:
		var w := Vector3(sx, 0.0, 0.0) if tilt == Vector3.ZERO else Vector3(sx * 0.3 - 0.6, 0.6 + sx * 0.5, 0.0)
		out.append(L.part("cyl", w + Vector3(0, 1.0, 0), Vector3(2.0, 0.3, 2.0), "timber_dark", 0.0,
			Vector3(0, 0, 90) + tilt))
	if tilt == Vector3.ZERO:
		out.append(L.part("box", Vector3(-0.5, lift + 0.6, -length * 0.5 - 1.2), Vector3(0.15, 0.15, 2.6), "timber_dark"))
		out.append(L.part("box", Vector3(0.5, lift + 0.6, -length * 0.5 - 1.2), Vector3(0.15, 0.15, 2.6), "timber_dark"))
		if bool(el.get("loaded", false)):
			out.append(L.part("box", Vector3(0, lift + 0.7, -0.4), Vector3(1.8, 1.0, 1.4), "stone_light", 5.0))
			out.append(L.part("box", Vector3(0.1, lift + 0.7, 1.1), Vector3(1.6, 0.9, 1.2), "stone", -4.0))
	else:
		out.append(L.part("box", Vector3(2.0, 0.0, 0.4), Vector3(1.6, 0.9, 1.3), "stone_light", 30.0))
	return out


static func _spoil(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(10, 4, 8))
	var out: Array = [L.part("frustum", Vector3(0, -0.5, 0), Vector3(s.x, s.y * 0.7 + 0.5, s.x * 0.35), "rock"),
		L.part("frustum", Vector3(s.x * 0.15, s.y * 0.55, -s.z * 0.05), Vector3(s.x * 0.45, s.y * 0.45, s.x * 0.1),
			"stone_dark", 20.0)]
	for k in 4:
		var a := TAU * _rand(el, k)
		var d := 0.45 + 0.2 * _rand(el, k + 10)
		out.append(L.part("box", Vector3(cos(a) * s.x * d, 0.0, sin(a) * s.z * d), Vector3(1.6, 1.1, 1.3),
			"stone" if k % 2 == 0 else "stone_light", rad_to_deg(a)))
	return out


static func _monolith(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(7, 15, 7))
	var lean := Vector3(4.0 * (_rand(el, 1) - 0.5), 0, 4.0 * (_rand(el, 2) - 0.5))
	var out: Array = []
	out.append(L.part("box", Vector3(0, -1.0, 0), Vector3(s.x, s.y * 0.55 + 1.0, s.z), OLD_ROCK, 0.0, lean))
	out.append(L.part("box", Vector3(0.2, s.y * 0.5, -0.1), Vector3(s.x * 0.82, s.y * 0.38, s.z * 0.8), FACE,
		7.0, lean))
	out.append(L.part("pyramid", Vector3(0.1, s.y * 0.86, 0), Vector3(s.x * 0.7, s.y * 0.16, s.z * 0.65), OLD_ROCK,
		12.0, lean))
	out.append(L.part("box", Vector3(s.x * 0.7, 0, s.z * 0.4), Vector3(2.0, 1.2, 1.6), "rock", 25.0))
	out.append(L.part("box", Vector3(-s.x * 0.2, s.y * 0.3, s.z * 0.5 + 0.05), Vector3(s.x * 0.5, 0.25, 0.1), "moss", 0.0, lean))
	return out

