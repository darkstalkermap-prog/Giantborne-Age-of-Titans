extends RefCounted
## Element kind "field" (P25): a field of `size` [w, d] in strips along local x - style "wheat",
## "barley" (golden) or "green" (young crops), alternating with darker furrows, 0.6 m tall and
## following the ground under each strip. Crops never collide (no solids): a giant walks through.

const L := preload("res://tools/world/layout.gd")


static func parts(el: Dictionary, ctx: Dictionary) -> Array:
	var s := L.size3(el, Vector3(60, 0.6, 40))
	var strips := maxi(2, int(s.z / 6.0))
	var crop := "crop_green" if str(el.get("style", "wheat")) == "green" else "crop"
	var xf: Transform3D = ctx.frame
	var f: HeightField = ctx.field
	var out: Array = []
	for k in strips:
		var z := -s.z * 0.5 + (k + 0.5) * s.z / strips
		var mid := xf * Vector3(0, 0, z)
		var y := f.sample(mid.x, mid.z) - xf.origin.y
		out.append(L.part("box", Vector3(0, y - 0.3, z), Vector3(s.x, s.y + 0.3, s.z / strips * 0.82), crop if k % 2 == 0 else "soil"))
	return out


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return L.parts_node("Field", parts(el, ctx))
