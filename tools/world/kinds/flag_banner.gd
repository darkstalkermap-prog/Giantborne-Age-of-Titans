extends RefCounted
## Element kind "flag_banner" (P36; plan M6-M9 §5.9): a banner on a tall pole that a choice raises or
## strikes - the crown of Aldmere's banners over the toll fort, struck after the crown's parley
## (`struck_when_flag` world.aldmere.flags_struck). A FlagVisibility node (scripts/world/flag_visibility.gd:
## `shown_when_flag` / `struck_when_flag` as its visible_when_flag / hidden_when_flag) with the banner's
## mesh in the scenery group, so it fades with the chunk's other props at the preset's scenery distance
## (the dressing kind's flag-shown banners are drawn at any distance). `size` [height, cloth width],
## `color` a palette key. Its chunk's props sub-scene holds it.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_FLAG := "res://scripts/world/flag_visibility.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The pole, its cross-bar and the cloth (the dressing kind's banner).
static func banner_parts(el: Dictionary) -> Array:
	var s := L.size3(el, Vector3(14, 4, 0))
	var out: Array = []
	out.append(L.part("cyl", Vector3(0, -0.5, 0), Vector3(0.5, s.x + 0.5, 0), "timber_dark"))
	out.append(L.part("box", Vector3(s.y * 0.5 + 0.2, s.x - s.y * 1.4, 0), Vector3(s.y, s.y * 1.3, 0.12),
		str(el.get("color", "banner_blue"))))
	out.append(L.part("box", Vector3(s.y * 0.5, s.x - 0.2, 0), Vector3(s.y + 0.6, 0.25, 0.25), "timber_dark"))
	return out


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_FLAG, {"visible_when_flag": str(el.get("shown_when_flag", "")),
		"hidden_when_flag": str(el.get("struck_when_flag", ""))})
	var mesh := L.parts_node("Mesh", banner_parts(el), ctx.get("mat"))
	mesh.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	n.add_child(mesh)
	return n
