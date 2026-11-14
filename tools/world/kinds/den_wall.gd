extends RefCounted
## Element kind "den_wall" (P35; plan M6-M9 §5.5, §5.7, §5.13): the Troll Den's back wall - boulders and
## old timber heaped across the cave at the back of the den, the Matriarch's way out when she is
## driven off. A DenWall (scripts/world/den_wall.gd; record prop.den_back_wall: heaved aside at stage
## 5, opened by the woodfolk 20 s after the den's nests burn or at once on Sedge's bargain) with a
## HeavePoint ("Heave the den's back wall aside"). The cave mouth behind it (a dark arch on the rock
## face, part of the static Frame) shows through once it is open. Along local x, `size` [width, height,
## depth]; its back (local -z) faces the cave. Fields: `nests_flag`, `bargain_flag`, `wall_flag`,
## `woodfolk_s`. Its chunk's props part holds it.

const L := preload("res://tools/world/layout.gd")
const K := preload("res://tools/world/kinds/_breakable_kit.gd")
const SCRIPTED := true
const S_DEN_WALL := "res://scripts/world/den_wall.gd"
const S_HEAVE := "res://scripts/world/heave_point.gd"
const RECORD := "prop.den_back_wall"
const NESTS_FLAG := "world.troll_den.nests_burned"
const BARGAIN_FLAG := "world.troll_den.bargain"
const WALL_FLAG := "world.troll_den.wall_open"


static func design(el: Dictionary) -> Dictionary:
	var s := L.size3(el, Vector3(20, 10, 7))
	var intact: Array = []
	var rocks := [[-0.36, 0.0, 0.0, 0.42], [-0.08, 0.0, 0.1, 0.48], [0.22, 0.0, -0.1, 0.44], [0.42, 0.0, 0.05, 0.3],
		[-0.22, 0.42, 0.0, 0.34], [0.1, 0.46, 0.05, 0.36], [0.32, 0.38, -0.05, 0.28], [-0.02, 0.74, 0.0, 0.26]]
	for i in rocks.size():
		var r: Array = rocks[i]
		var d := float(r[3]) * s.x * 0.62
		intact.append(L.part("sphere", Vector3(float(r[0]) * s.x, float(r[1]) * s.y - 0.8, float(r[2]) * s.z), Vector3(d, d * 0.8, s.z * 0.9),
			"rock" if i % 2 == 0 else "stone_dark", 29.0 * i))
	for k in 3:
		intact.append(L.part("box", Vector3((k - 1) * s.x * 0.3, s.y * 0.55, s.z * 0.45), Vector3(0.8, s.y * 0.9, 0.8), "timber_dark",
			0.0, Vector3(14.0 * (k - 1), 0, 8)))
	var broken: Array = []
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		broken.append(L.part("sphere", Vector3(side * (s.x * 0.5 + 1.5 + 1.8 * (i / 2)), -0.6, s.z * 0.2 + 1.4 * (i / 2)),
			Vector3(3.4, 2.6, 3.2), "rock" if i % 3 == 0 else "stone_dark", 41.0 * i))
	broken.append(L.part("box", Vector3(s.x * 0.2, -0.2, s.z * 0.8), Vector3(5.0, 0.7, 0.8), "timber_dark", 23.0))
	# the cave mouth behind it: a dark arch on the rock face (static; shows once the wall is gone)
	var frame: Array = [
		L.part("box", Vector3(0, -1.0, -s.z * 0.9), Vector3(s.x * 0.8, s.y + 4.0, 1.2), "black"),
		L.part("box", Vector3(-s.x * 0.48, -1.0, -s.z * 0.7), Vector3(3.0, s.y + 6.0, 3.0), "rock"),
		L.part("box", Vector3(s.x * 0.48, -1.0, -s.z * 0.7), Vector3(3.0, s.y + 6.0, 3.0), "rock"),
		L.part("box", Vector3(0, s.y + 2.6, -s.z * 0.7), Vector3(s.x + 3.0, 3.0, 3.6), "stone_dark"),
	]
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(s.x, s.y, s.z), Vector3(0, s.y * 0.5, 0)]],
		"hurt": [Vector3(s.x + 0.8, s.y + 0.6, s.z + 0.8), Vector3(0, s.y * 0.5, 0)], "center": Vector3(0, s.y * 0.5, 0),
		"frame": frame, "frame_solids": [[Vector3(3.0, s.y + 6.0, 3.0), Vector3(-s.x * 0.48, (s.y + 6.0) * 0.5 - 1.0, -s.z * 0.7)],
			[Vector3(3.0, s.y + 6.0, 3.0), Vector3(s.x * 0.48, (s.y + 6.0) * 0.5 - 1.0, -s.z * 0.7)]]}


## The map draws the wall (a scripted kind: nothing is merged).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return design(el).intact


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The prop record of the element (its `record`, else prop.den_back_wall).
static func record_of(el: Dictionary) -> String:
	return str(el.get("record", RECORD))


## The flag the wall's node writes when the woodfolk open it (DenWall.wall_flag; the content tests).
static func written_flags(el: Dictionary) -> Array:
	return [str(el.get("wall_flag", WALL_FLAG))]


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var root := K.build(kit, el, ctx, S_DEN_WALL, record_of(el), design(el), {
		"nests_flag": str(el.get("nests_flag", NESTS_FLAG)),
		"bargain_flag": str(el.get("bargain_flag", BARGAIN_FLAG)),
		"wall_flag": str(el.get("wall_flag", WALL_FLAG)),
		"woodfolk_delay_s": float(el.get("woodfolk_s", 20.0))})
	var s := L.size3(el, Vector3(20, 10, 7))
	var heave := Node3D.new()
	heave.name = "HeavePoint"
	kit.scripted(heave, S_HEAVE, {"prompt": "Heave the wall aside", "radius_m": float(el.get("heave_radius", 9.0)),
		"priority": 40})
	heave.position = Vector3(0, 0.5, s.z * 0.5 + 2.0)
	root.add_child(heave)
	return root
