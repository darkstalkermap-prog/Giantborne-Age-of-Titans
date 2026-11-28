extends RefCounted
## Element kind "cinder_road" (E2): the Cinder Titan's burned road (scripts/world/cinder_road.gd: CinderRoad) - a ribbon
## of charred ground and ash `width` m wide draped over the terrain along `points` ([[x, z], ...] world metres) from where
## he came over the eastern mountains to where he stands, and `spots` ([[x, z, r], ...]) of burnt ground round it (the
## villages he passed, the hollow he stands in), with fires burning along it until `cooled_flag` is set (his fall: the
## fires go out, the char stays). The node stands at `pos` at height 0 (`y` 0), its points kept in world metres. No
## parts, no solids. `ruins` ([[x, z, yaw, w, d], ...]): the houses he burned, their charred shells made at load.

const SCRIPTED := true
const S_ROAD := "res://scripts/world/cinder_road.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var at := WorldLayout.pos2(el)
	var pts := PackedVector2Array()
	for p: Variant in el.get("points", []):
		pts.append(Vector2(float((p as Array)[0]) - at.x, float((p as Array)[1]) - at.y))
	var spots: Array = []
	for s: Variant in el.get("spots", []):
		var a := s as Array
		spots.append([float(a[0]) - at.x, float(a[1]) - at.y, float(a[2])])
	var ruins: Array = []
	for rv: Variant in el.get("ruins", []):
		var a := rv as Array
		ruins.append([float(a[0]) - at.x, float(a[1]) - at.y, float(a[2]), float(a[3]), float(a[4])])
	kit.scripted(n, S_ROAD, {"road_id": str(el.id), "points": pts, "spots": spots, "width_m": float(el.get("width", 40.0)),
		"fires": int(el.get("fires", 40)), "cooled_flag": str(el.get("cooled_flag", "")), "ruins": ruins})
	return n
