extends RefCounted
## Element kind "nest" (P35; plan M6-M9 §5.7, §5.13): a brood nest of the Troll Matriarch in the Troll
## Den - a mound of branches, hides and gnawed bones that only fire destroys (BroodNest,
## scripts/world/brood_nest.gd; record prop.brood_nest). Fields: `den_nests` (the world ids of every
## nest of the den, this one among them), `den_flag` (set once they have all burned), `ignite_m` (a
## fire prop broken this close, or a burning body landing this close, sets it alight). Broken, it is a
## charred ring. Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_NEST := "res://scripts/world/brood_nest.gd"
const RECORD := "prop.brood_nest"


static func design(el: Dictionary) -> Dictionary:
	var r := float(el.get("radius", 3.6))
	var intact: Array = [L.part("sphere", Vector3(0, -0.6, 0), Vector3(r * 2.0, 2.6, r * 2.0), "moss")]
	for k in 7:
		var a := TAU * k / 7.0
		intact.append(L.part("box", Vector3(cos(a) * r * 0.75, 0.4, sin(a) * r * 0.75), Vector3(r * 1.1, 0.45, 0.5), "bark",
			rad_to_deg(-a) + 20.0, Vector3(0, 0, 24)))
	for k in 4:
		var a := TAU * (k + 0.3) / 4.0
		intact.append(L.part("box", Vector3(cos(a) * r * 0.45, 1.3, sin(a) * r * 0.45), Vector3(1.6, 0.35, 0.35), "bone",
			rad_to_deg(-a), Vector3(0, 0, -15)))
	intact.append(L.part("sphere", Vector3(0.6, 1.2, -0.4), Vector3(1.4, 1.1, 1.2), "bone_dark"))
	var broken: Array = [L.part("cyl", Vector3(0, -0.2, 0), Vector3(r * 2.2, 0.4, 0), "black"),
		L.part("sphere", Vector3(0, -0.4, 0), Vector3(r * 1.2, 0.9, r * 1.2), "stone_dark"),
		L.part("box", Vector3(r * 0.4, 0.1, 0.3), Vector3(0.8, 0.3, 0.6), "fire", 30.0),
		L.part("box", Vector3(-r * 0.3, 0.1, -r * 0.4), Vector3(0.6, 0.3, 0.5), "fire", 70.0)]
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(r * 1.6, 2.2, r * 1.6), Vector3(0, 1.1, 0)]],
		"hurt": [Vector3(r * 2.0, 3.0, r * 2.0), Vector3(0, 1.4, 0)], "center": Vector3(0, 1.2, 0)}


## The map draws the nest (a scripted kind: nothing is merged).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return design(el).intact


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	return K.build(kit, el, ctx, S_NEST, str(el.get("record", RECORD)), design(el), {
		"den_nests": PackedStringArray(el.get("den_nests", [str(el.get("id", ""))])),
		"den_flag": str(el.get("den_flag", "world.troll_den.nests_burned")),
		"ignite_radius_m": float(el.get("ignite_m", 9.0))})
