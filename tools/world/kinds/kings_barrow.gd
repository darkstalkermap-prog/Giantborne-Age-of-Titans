extends RefCounted
## Element kind "kings_barrow" (E3): the Hollow King laid to rest - once his shell has fallen apart, the herders heap a long
## barrow of field stones over his armour where he knelt (along local z, `size` [length, width], default 30 x 12 m), his
## helm with its crown set on a standing stone at its head and the Kingsword driven into the barrow's crest beside it.
## Shown after his fall (visible_when_flag). Structures mesh (one draw call with the chunk's); the barrow and the stone
## are solids.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(30, 12, 0))
	var length := s.x
	var w := s.y
	var out: Array = []
	# the heap: overlapping stones, higher along the middle
	for k in 9:
		var z := lerpf(-length * 0.45, length * 0.45, float(k) / 8.0)
		var hump := 1.0 - absf(z) / (length * 0.55)
		out.append(L.part("sphere", Vector3(0.6 * sin(k * 1.3), -1.2, z), Vector3(w * (0.8 + 0.2 * hump), 3.6 + 3.0 * hump,
			length * 0.2), "rock" if k % 2 == 0 else "stone_dark", 17.0 * k))
	for k in 14:
		var z := lerpf(-length * 0.5, length * 0.5, fposmod(k * 0.37, 1.0))
		var x := (w * 0.5 + 0.6) * (1.0 if k % 2 == 0 else -1.0)
		out.append(L.part("box", Vector3(x * (0.8 + 0.2 * sin(k)), -0.3, z), Vector3(2.0 + 0.4 * (k % 3), 1.4, 1.8), "stone",
			29.0 * k, Vector3(6 * sin(k), 0, 8 * cos(k))))
	# the head stone and the helm on it: a dark iron barrel helm, its gilt crown
	var hz := -length * 0.5 - 3.5
	out.append(L.part("box", Vector3(0, -0.5, hz), Vector3(5.0, 7.5, 3.0), "stone_light", 4.0, Vector3(2, 0, 0)))
	out.append(L.part("cyl", Vector3(0, 7.0, hz), Vector3(4.6, 4.8, 0), "black"))
	out.append(L.part("box", Vector3(0, 8.9, hz + 2.2), Vector3(3.4, 0.4, 0.3), "dark"))
	out.append(L.part("cyl", Vector3(0, 11.0, hz), Vector3(4.8, 0.9, 0), "gold"))
	for k in 7:
		var a := TAU * k / 7.0
		out.append(L.part("cone", Vector3(cos(a) * 2.2, 11.8, hz + sin(a) * 2.2), Vector3(0.7, 2.0 if k == 0 else 1.2, 0), "gold"))
	# the Kingsword driven point-down into the crest, its guard and grip standing
	out.append(L.part("box", Vector3(3.4, 2.0, -length * 0.36), Vector3(1.7, 14.0, 0.4), "iron", 8.0, Vector3(0, 0, 4)))
	out.append(L.part("box", Vector3(3.4, 16.0, -length * 0.36), Vector3(5.2, 0.6, 0.7), "gold", 8.0, Vector3(0, 0, 4)))
	out.append(L.part("cyl", Vector3(3.5, 16.6, -length * 0.36), Vector3(0.9, 3.2, 0), "timber_dark"))
	out.append(L.part("sphere", Vector3(3.55, 19.8, -length * 0.36), Vector3(1.4, 1.4, 1.4), "gold"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(30, 12, 0))
	return [L.solid("box", Vector3(0, 2.0, 0), Vector3(s.y, 4.0, s.x)),
		L.solid("box", Vector3(0, 3.0, -s.x * 0.5 - 3.5), Vector3(5.0, 6.0, 3.0))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("KingsBarrow", parts(el, ctx))
