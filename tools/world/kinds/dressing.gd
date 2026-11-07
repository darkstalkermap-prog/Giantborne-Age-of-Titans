extends RefCounted
## Element kind "dressing" (P29; plan M6-M9 §2.7, §5.9): small static dressing of the Crownmarch's
## places, merged into its chunk's structures mesh - or, with `visible_when_flag` /
## `hidden_when_flag`, a flag-shown element of its own that shows what a choice changed on site.
## Styles:
##   banner    a tall pole with a cloth (`color`, a palette key): the giant's banner on Brannock's
##             gates once the town is allied (`size` [height, cloth width])
##   tribute   Brannock's tribute heaped by its gate once the town pays (sacks, crates, a chest)
##   toll_bar  the toll-riders' bar across the King's Road, lifted on two posts at the road's edges
##             (`size` [span, height]); the posts are solids, the bar stands clear above the road
##   stall     a market stall (an awning on four posts)
## Only the posts and the heaps are solids.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	var out: Array = []
	match str(el.get("style", "banner")):
		"banner":
			var s := L.size3(el, Vector3(14, 4, 0))
			out.append(L.part("cyl", Vector3(0, -0.5, 0), Vector3(0.5, s.x + 0.5, 0), "timber_dark"))
			out.append(L.part("box", Vector3(s.y * 0.5 + 0.2, s.x - s.y * 1.4, 0), Vector3(s.y, s.y * 1.3, 0.12),
				str(el.get("color", "banner_green"))))
			out.append(L.part("box", Vector3(s.y * 0.5, s.x - 0.2, 0), Vector3(s.y + 0.6, 0.25, 0.25), "timber_dark"))
		"tribute":
			for k in 5:
				out.append(L.part("sphere", Vector3(-3.0 + k * 1.5, -0.2, (k % 2) * 1.2), Vector3(1.4, 1.2, 1.2), "canvas", 13.0 * k))
			out.append(L.part("box", Vector3(-1.5, -0.1, -1.6), Vector3(2.0, 1.4, 1.4), "timber"))
			out.append(L.part("box", Vector3(1.4, -0.1, -1.8), Vector3(1.8, 1.2, 1.2), "timber_dark"))
			out.append(L.part("box", Vector3(0.0, 1.2, -1.7), Vector3(1.6, 0.9, 1.0), "gold"))
			out.append(L.part("box", Vector3(3.2, -0.1, 0.2), Vector3(1.6, 1.0, 1.6), "timber"))
		"toll_bar":
			var s := L.size3(el, Vector3(20, 6, 0))
			for side: float in [-1.0, 1.0]:
				out.append(L.part("box", Vector3(s.x * 0.5 * side, -0.5, 0), Vector3(0.8, s.y + 0.5, 0.8), "timber_dark"))
			out.append(L.part("box", Vector3(0, s.y - 0.4, 0), Vector3(s.x + 1.0, 0.5, 0.5), "canvas_red"))
			out.append(L.part("box", Vector3(-s.x * 0.25, s.y - 0.4, 0), Vector3(s.x * 0.2, 0.52, 0.52), "plaster"))
			out.append(L.part("box", Vector3(s.x * 0.25, s.y - 0.4, 0), Vector3(s.x * 0.2, 0.52, 0.52), "plaster"))
		"stall":
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					out.append(L.part("box", Vector3(1.6 * sx, -0.3, 1.1 * sz), Vector3(0.2, 2.6, 0.2), "timber_dark"))
			out.append(L.part("roof", Vector3(0, 2.2, 0), Vector3(3.8, 0.9, 2.8), str(el.get("color", "canvas_red"))))
			out.append(L.part("box", Vector3(0, 0.0, 0.4), Vector3(3.0, 1.0, 1.0), "timber"))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	match str(el.get("style", "banner")):
		"banner":
			var s := L.size3(el, Vector3(14, 4, 0))
			return [L.solid("cyl", Vector3(0, s.x * 0.5, 0), Vector3(0.5, s.x, 0.5))]
		"tribute":
			return [L.solid("box", Vector3(0, 0.6, -0.4), Vector3(7.0, 1.4, 3.6))]
		"toll_bar":
			var s := L.size3(el, Vector3(20, 6, 0))
			return [L.solid("box", Vector3(-s.x * 0.5, s.y * 0.5, 0), Vector3(0.8, s.y, 0.8)),
				L.solid("box", Vector3(s.x * 0.5, s.y * 0.5, 0), Vector3(0.8, s.y, 0.8))]
		"stall":
			return [L.solid("box", Vector3(0, 0.5, 0.4), Vector3(3.0, 1.0, 1.0))]
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Dressing", parts(el, ctx))
