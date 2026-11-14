extends RefCounted
## Element kind "stilt_hut" (P35; plan M6-M9 §5.4): the woodfolk's houses at Hollowmere - a plank
## hut of `size` [w, h, d] on six stilts over the pond's edge, with a steep bark roof, a porch and a
## ladder. Merged into its chunk's structures mesh; its body (the stilts' footprint) is a solid. Style
## "lights": no hut, but the lanterns of Hollowmere - a lantern post at each of `points` ([[x, z]],
## world positions) - for an element shown by a flag (visible_when_flag oath.wood.done: Hollowmere's
## lights burn for the giant who freed the wood; the builder makes it a FlagVisibility node).

const L := preload("res://tools/world/layout.gd")


static func _lights(el: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var pts: Array = el.get("points", [])
	for p: Array in pts:
		var local := L.local_point(ctx, float(p[0]), float(p[1]))
		out.append(L.part("box", local + Vector3(0, -0.5, 0), Vector3(0.35, 5.0, 0.35), "timber_dark"))
		out.append(L.part("box", local + Vector3(0.6, 4.2, 0), Vector3(1.4, 0.25, 0.25), "timber_dark"))
		out.append(L.part("box", local + Vector3(1.2, 3.2, 0), Vector3(0.8, 0.9, 0.8), "fire"))
		out.append(L.part("pyramid", local + Vector3(1.2, 4.1, 0), Vector3(1.1, 0.6, 1.1), "black"))
	return out


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	if str(el.get("style", "")) == "lights":
		return _lights(el, ctx)
	var s := L.size3(el, Vector3(7, 4, 6))
	var base := float(el.get("stilt_m", 2.8))
	var out: Array = []
	for sx: float in [-0.42, 0.0, 0.42]:
		for sz: float in [-0.42, 0.42]:
			out.append(L.part("box", Vector3(s.x * sx, -1.5, s.z * sz), Vector3(0.5, base + 1.5, 0.5), "timber_dark"))
	out.append(L.part("box", Vector3(0, base - 0.35, 0.6), Vector3(s.x + 1.4, 0.35, s.z + 2.6), "timber"))
	out.append(L.part("box", Vector3(0, base, 0), Vector3(s.x, s.y, s.z), "bark"))
	out.append(L.part("roof", Vector3(0, base + s.y, 0), Vector3(s.x + 1.2, s.y * 0.9, s.z + 1.0), "moss"))
	out.append(L.part("box", Vector3(0, base, s.z * 0.5 + 0.05), Vector3(1.2, 2.2, 0.15), "black"))
	out.append(L.part("box", Vector3(s.x * 0.3, base + s.y * 0.45, s.z * 0.5 + 0.05), Vector3(0.9, 0.7, 0.12), "timber_dark"))
	# the ladder down from the porch
	out.append(L.part("box", Vector3(-0.5, -0.3, s.z * 0.5 + 1.8), Vector3(0.18, base + 0.3, 0.18), "timber_dark", 0.0, Vector3(-18, 0, 0)))
	out.append(L.part("box", Vector3(0.5, -0.3, s.z * 0.5 + 1.8), Vector3(0.18, base + 0.3, 0.18), "timber_dark", 0.0, Vector3(-18, 0, 0)))
	return out


static func solids(el: Dictionary, _ctx: Dictionary) -> Array:
	if str(el.get("style", "")) == "lights":
		return []
	var s := L.size3(el, Vector3(7, 4, 6))
	var base := float(el.get("stilt_m", 2.8))
	return [L.solid("box", Vector3(0, (base + s.y) * 0.5 - 0.5, 0), Vector3(s.x, base + s.y + 1.0, s.z))]


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("StiltHut", parts(el, ctx))
