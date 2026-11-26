extends RefCounted
## Element kind "rubble_tower" (C2): a crumbling tower of the old kings' toll-keep, the Broken Warden's walls - a square
## stone tower `size` [width, height] (default 7 x 18 m) of coursed blocks, its battlements broken, a split down one
## face. A BreakableProp (record prop.rubble_tower, tagged "rubble"): a giant's blows or his charge bring it down, and
## within his record's rubble.radius_m it falls on him (TitanEnemy.rubble_fall: a stagger, his guard open, his poise
## lower a while). Broken, it is a heap of blocks. Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const RECORD := "prop.rubble_tower"
## A flagged element is the breakable itself inside a FlagVisibility (tools/builders/world.gd).
const FLAG_WRAP := true


static func design(el: Dictionary) -> Dictionary:
	var s := L.size3(el, Vector3(7, 18, 7))
	var w := s.x
	var h := s.y
	var intact: Array = []
	var courses := 7
	var ch := h / float(courses)
	for i in courses - 2:
		# each course a little set back and turned (an old wall's lean), the colours alternating - Cgate: weathered
		# greys, not the pale stone that read as white blocks; a wider footing course
		var inset := 0.06 * float(i % 3) - (0.5 if i == 0 else 0.0)
		var yaw := 2.0 * float((i * 5) % 3 - 1)
		var col := "stone" if i % 2 == 0 else "stone_dark"
		intact.append(L.part("box", Vector3(0.12 * float(i % 2), ch * float(i), 0.0), Vector3(w - inset, ch * 0.98,
			w - inset), col, yaw))
	# Cgate: the broken crown - the top two courses only in part, stepping down to the split side (a ruin's silhouette,
	# not a flat-topped block), and the quoins at two corners standing proud
	var y5 := ch * float(courses - 2)
	intact.append(L.part("box", Vector3(-w * 0.22, y5, -w * 0.05), Vector3(w * 0.56, ch * 0.98, w - 0.1), "stone", 3.0))
	intact.append(L.part("box", Vector3(w * 0.28, y5, -w * 0.28), Vector3(w * 0.44, ch * 0.7, w * 0.44), "stone_dark", -4.0))
	intact.append(L.part("box", Vector3(-w * 0.3, y5 + ch, -w * 0.2), Vector3(w * 0.4, ch * 0.98, w * 0.6), "stone_dark", 5.0))
	intact.append(L.part("box", Vector3(-w * 0.36, y5 + ch * 2.0, -w * 0.3), Vector3(1.4, 1.5, 1.4), "stone"))
	intact.append(L.part("box", Vector3(-w * 0.05, y5 + ch * 1.6, w * 0.3), Vector3(1.3, ch * 0.5, 1.1), "stone", 20.0, Vector3(14, 0, 9)))
	for c: Array in [[-1.0, 1.0], [1.0, -1.0]]:
		intact.append(L.part("box", Vector3(float(c[0]) * (w * 0.5 - 0.05), 0.0, float(c[1]) * (w * 0.5 - 0.05)),
			Vector3(0.9, y5 * 0.96, 0.9), "stone_dark"))
	# the split down its face (a dark seam) and a slit window
	intact.append(L.part("box", Vector3(w * 0.18, h * 0.45, w * 0.5 + 0.02), Vector3(0.35, h * 0.6, 0.1), "black", 4.0))
	intact.append(L.part("box", Vector3(-w * 0.2, h * 0.7, w * 0.5 + 0.02), Vector3(0.4, 1.8, 0.1), "black"))
	var broken: Array = [
		L.part("sphere", Vector3(0, -0.6, 0), Vector3(w * 1.5, 3.4, w * 1.4), "stone_dark"),
		L.part("box", Vector3(-w * 0.3, 0.6, w * 0.2), Vector3(2.4, 1.6, 2.0), "stone", 25.0, Vector3(10, 0, 18)),
		L.part("box", Vector3(w * 0.35, 0.4, -w * 0.25), Vector3(2.2, 1.4, 1.8), "stone_light", -40.0, Vector3(-14, 0, 8)),
		L.part("box", Vector3(w * 0.05, 1.6, w * 0.4), Vector3(1.8, 1.2, 1.6), "stone", 60.0, Vector3(20, 0, -12)),
		L.part("box", Vector3(0, -0.2, 0), Vector3(w * 0.7, ch * 1.2, w * 0.7), "stone"),
	]
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(w, h, w), Vector3(0, h * 0.5, 0)]],
		"hurt": [Vector3(w + 1.0, h, w + 1.0), Vector3(0, h * 0.5, 0)], "center": Vector3(0, h * 0.35, 0)}


## The map draws the tower (a scripted kind: nothing is merged).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return design(el).intact


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func record_of(el: Dictionary) -> String:
	return str(el.get("record", RECORD))


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return K.build(kit, el, ctx, S_BREAKABLE, record_of(el), design(el))
