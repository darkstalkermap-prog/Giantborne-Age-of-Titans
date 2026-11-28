extends RefCounted
## Element kind "oath_pillar" (E3): an oath-stone of the Kingsward - a standing stone of the old giant kings `size`
## [width, height] (8 x 28 m), its faces cut with the oath's marks, an iron collar near its head where one of the
## Hollow King's oath-chains is made fast (the chain itself is drawn by HollowRig, from the collar to him). A
## BreakableProp (record prop.oath_pillar, tagged "oath_pillar"): a giant's blows bring it down - snapped at half its
## height, its head lying beside the stump - and its chain with it (HollowEnemy: while one stands his torn plates are
## drawn back onto him; brought down, he reels). Every stone is one scene (scenes/world/oath_pillar.tscn, made by
## tools/builders/e3_titans.gd from scene_root()) placed with its own world id: the chunk's props part holds an
## instance, not the stone's meshes. `size` is not read (every stone is the scene's 28 m).

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const RECORD := "prop.oath_pillar"
const FLAG_WRAP := true
## The collar's height as a share of the stone's (HollowRig fastens the chain there).
const COLLAR_SHARE := 0.82


static func design(el: Dictionary) -> Dictionary:
	var s := L.size3(el, Vector3(8, 28, 8))
	var w := s.x
	var h := s.y
	var intact: Array = [
		# a rough footing, the shaft in two tapering courses, a leaning cap
		L.part("frustum", Vector3(0, -1.0, 0), Vector3(w * 1.5, 3.0, w * 1.35), "stone_dark", 8.0),
		L.part("frustum", Vector3(0, 1.6, 0), Vector3(w, h * 0.5, w * 0.82), "stone_dark", 3.0),
		L.part("frustum", Vector3(0.1, 1.6 + h * 0.5, 0.05), Vector3(w * 0.86, h * 0.42, w * 0.7), "stone_dark", -4.0, Vector3(1.5, 0, 0)),
		L.part("pyramid", Vector3(0.15, 1.6 + h * 0.92, 0.05), Vector3(w * 0.74, h * 0.09, w * 0.62), "stone_dark", 10.0, Vector3(3, 0, 2)),
		# the oath's marks: cut grooves down two faces
		L.part("box", Vector3(0, h * 0.28, w * 0.41 + 0.02), Vector3(0.5, h * 0.36, 0.12), "black"),
		L.part("box", Vector3(-w * 0.2, h * 0.56, w * 0.36 + 0.02), Vector3(0.4, h * 0.2, 0.12), "black", 0.0, Vector3(0, 0, 12)),
		L.part("box", Vector3(w * 0.44 + 0.02, h * 0.4, 0), Vector3(0.12, h * 0.3, 0.45), "black"),
		# the iron collar and its ring
		L.part("cyl", Vector3(0, h * COLLAR_SHARE - 0.8, 0), Vector3(w * 0.86, 1.6, w * 0.74), "iron"),
		L.part("cyl", Vector3(0, h * COLLAR_SHARE - 2.6, -w * 0.48), Vector3(2.6, 0.7, 2.6), "iron", 0.0, Vector3(90, 0, 0)),
		# lichen on the weather side
		L.part("box", Vector3(-w * 0.35, h * 0.15, -w * 0.3), Vector3(w * 0.4, h * 0.25, 0.25), "moss", 20.0),
	]
	var broken: Array = [
		L.part("frustum", Vector3(0, -1.0, 0), Vector3(w * 1.5, 3.0, w * 1.35), "stone_dark", 8.0),
		L.part("frustum", Vector3(0, 1.6, 0), Vector3(w, h * 0.34, w * 0.86), "stone_dark", 3.0),
		L.part("pyramid", Vector3(0.2, 1.6 + h * 0.34, 0.0), Vector3(w * 0.9, 2.4, w * 0.8), "rock", 30.0, Vector3(12, 0, -8)),
		# the head lying beside the stump, its collar with it
		L.part("frustum", Vector3(w * 0.4, w * 0.4, h * 0.38), Vector3(w * 0.85, h * 0.6, w * 0.72), "rock", 10.0, Vector3(86, 0, 6)),
		L.part("cyl", Vector3(w * 0.4, w * 0.45, h * 0.62), Vector3(w * 0.9, 1.6, w * 0.8), "iron", 10.0, Vector3(86, 0, 6)),
		L.part("sphere", Vector3(-w * 0.6, -0.5, w * 0.5), Vector3(w * 1.2, 2.0, w), "stone_dark"),
		L.part("box", Vector3(w * 0.9, 0.2, -w * 0.4), Vector3(2.2, 1.4, 1.8), "stone", 35.0, Vector3(12, 0, 20)),
	]
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(w, h, w), Vector3(0, h * 0.5, 0)]],
		"hurt": [Vector3(w + 1.5, h, w + 1.5), Vector3(0, h * 0.5, 0)], "center": Vector3(0, h * 0.4, 0)}


static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return design(el).intact


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func record_of(el: Dictionary) -> String:
	return str(el.get("record", RECORD))


const SCENE := "res://scenes/world/oath_pillar.tscn"
const SCENE_ID := "world.kingsward.oath_stone"


## The stone's scene root (tools/builders/e3_titans.gd saves it as SCENE): its BreakableProp and meshes.
static func scene_root(kit: SceneKit, ctx: Dictionary) -> Node3D:
	var el := {"id": SCENE_ID}
	var n := K.build(kit, el, ctx, S_BREAKABLE, RECORD, design(el))
	n.set_meta(&"collar_m", snappedf(28.0 * COLLAR_SHARE, 0.01))
	return n


## An oath-stone placed: the scene, its world id the element's.
static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := kit.instance(SCENE) as Node3D
	if n == null:
		push_error("oath_pillar: build scenes/world/oath_pillar.tscn first (tools/builders/e3_titans.gd)")
		return Node3D.new()
	var id := str(el.get("id", ""))
	n.name = id.validate_node_name()
	n.set("world_id", id)
	return n
