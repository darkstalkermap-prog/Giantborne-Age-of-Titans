extends RefCounted
## Element kind "brazier" (P35; plan M6-M9 §5.13, §3.19 "a brazier or bonfire at every troll site"):
## fire to use against trolls. A BreakableProp whose record carries prop_tags ["fire"] (P34's brazier
## rule: a troll within its regeneration's brazier_radius_m of a fire prop when it breaks starts
## Burning and stops regenerating; a brood nest within reach catches fire, BroodNest). Styles:
##   brazier   an iron fire-bowl on a stone pedestal (record prop.brazier), 3 m tall
##   bonfire   a woodcutters' log fire (record prop.bonfire): the woodcutters' camp's lesson in fire
## Broken, it is a spill of embers. Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const RECORDS := {"brazier": "prop.brazier", "bonfire": "prop.bonfire"}


static func style_of(el: Dictionary) -> String:
	var s := str(el.get("style", "brazier"))
	return s if RECORDS.has(s) else "brazier"


static func _flames(y: float, w: float) -> Array:
	return [
		L.part("cone", Vector3(0, y, 0), Vector3(w, w * 1.4, 0), "fire"),
		L.part("cone", Vector3(w * 0.25, y, w * 0.15), Vector3(w * 0.6, w * 1.1, 0), "gold", 0.0, Vector3(7, 0, -6)),
		L.part("cone", Vector3(-w * 0.22, y, -w * 0.18), Vector3(w * 0.55, w, 0), "fire", 0.0, Vector3(-6, 0, 8)),
	]


static func _embers(r: float) -> Array:
	return [
		L.part("cyl", Vector3(0, -0.1, 0), Vector3(r * 2.0, 0.3, 0), "black"),
		L.part("box", Vector3(r * 0.4, 0.0, r * 0.2), Vector3(0.7, 0.3, 0.5), "fire", 20.0),
		L.part("box", Vector3(-r * 0.3, 0.0, -r * 0.4), Vector3(0.6, 0.3, 0.6), "fire", 55.0),
		L.part("box", Vector3(-r * 0.5, 0.0, r * 0.35), Vector3(0.5, 0.25, 0.5), "gold", 80.0),
	]


static func design(el: Dictionary) -> Dictionary:
	if style_of(el) == "bonfire":
		var logs: Array = []
		for k in 6:
			var a := TAU * k / 6.0
			logs.append(L.part("box", Vector3(cos(a) * 0.9, 0.0, sin(a) * 0.9), Vector3(3.2, 0.6, 0.6), "timber_dark",
				rad_to_deg(-a), Vector3(0, 0, 18)))
		var stones: Array = []
		for k in 8:
			var a := TAU * (k + 0.5) / 8.0
			stones.append(L.part("sphere", Vector3(cos(a) * 2.4, -0.2, sin(a) * 2.4), Vector3(0.9, 0.6, 0.9), "stone_dark"))
		return {"intact": logs + stones + _flames(0.6, 2.4), "broken": stones + _embers(2.2),
			"blocks": [[Vector3(3.6, 1.6, 3.6), Vector3(0, 0.8, 0)]], "hurt": [Vector3(4.4, 3.0, 4.4), Vector3(0, 1.5, 0)],
			"center": Vector3(0, 1.0, 0)}
	var intact: Array = [
		L.part("frustum", Vector3(0, -0.4, 0), Vector3(1.8, 1.9, 1.2), "stone_dark"),
		L.part("frustum", Vector3(0, 1.5, 0), Vector3(1.2, 0.6, 2.6), "iron"),
		L.part("cyl", Vector3(0, 2.1, 0), Vector3(2.8, 0.3, 0), "iron"),
	] + _flames(2.2, 1.9)
	var broken: Array = [L.part("frustum", Vector3(0, -0.4, 0), Vector3(1.8, 1.1, 1.2), "stone_dark"),
		L.part("box", Vector3(1.4, -0.1, 0.6), Vector3(1.6, 0.5, 1.2), "iron", 30.0, Vector3(0, 0, 40))] + _embers(1.8)
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(1.8, 2.6, 1.8), Vector3(0, 1.3, 0)]],
		"hurt": [Vector3(2.8, 3.4, 2.8), Vector3(0, 1.7, 0)], "center": Vector3(0, 1.6, 0)}


## The map draws the brazier (a scripted kind: nothing is merged).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return design(el).intact


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The prop record of the element (its `record`, else its style's).
static func record_of(el: Dictionary) -> String:
	return str(el.get("record", RECORDS[style_of(el)]))


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return K.build(kit, el, ctx, S_BREAKABLE, record_of(el), design(el))
