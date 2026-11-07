extends RefCounted
## Element kind "breakable_site" (P29; plan M6-M9 §2.7, §2.12, §5.4, §5.5, decision 31): a breakable or
## structural prop built here in code - a BreakableProp (scripts/world/breakable_prop.gd) with its
## CombatEntity (team NEUTRAL) on Anchors/Center, Block* shapes on the breakables layer (navigation
## obstacles while they stand), Hurtboxes/Body, its Intact and Broken visuals (one vertex-coloured mesh
## each) and, for a gate, one closed NavigationLink3D per world nav layer through it, opened when it
## breaks. Styles (`size` [w, h, d]):
##   house     a town or hamlet house (record prop.house_town: a faction house, trampled from stage 5);
##             the element's `faction` (a faction's short name) and `prop_tags` (default ["house"]) are
##             the node's metas, so FactionState counts damage to it as an offence against the town and
##             P37's raiders can target it; `roof` "thatch" | "slate" | "red", `wall` a palette colour
##   gatehouse Brannock's south gatehouse (record prop.gatehouse_brannock): two towers flanking a
##             `gap` m wide gateway that stays open - only the towers are solid, so the King's Road runs
##             through it whole or broken; smashing it is the march oath's force path
##   gate      a timber gate closing a palisade's `gap` (record prop.gate_toll: the toll fort's): doors
##             and posts are solid until it is breached at stage 4
##   dam       boulders damming the Millrace (record prop.millrace_dam: smashed aside at stage 4)
## `record` overrides the style's record. The element's id is the prop's world id; its chunk's props
## sub-scene holds it, and the index lists it as a prop (quest targets: the gates and the dam).

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
## The style's default record and size.
const STYLES := {
	"house": ["prop.house_town", Vector3(10, 6, 8)],
	"gatehouse": ["prop.gatehouse_brannock", Vector3(5, 13, 5)],
	"gate": ["prop.gate_toll", Vector3(18, 7, 1.2)],
	"dam": ["prop.millrace_dam", Vector3(14, 6, 5)],
}
const ROOFS := {"thatch": "thatch", "slate": "roof_slate", "red": "roof_red"}
## Half lengths of a gate's links per world nav layer (onto each layer's navmesh beyond the gate).
const LINK_HALF_M := {1: 4.0, 2: 5.0, 16: 8.0}
## Marks nodes the world builder must make the part own (none here: everything is built in code and
## owned by the part as usual).


static func style_of(el: Dictionary) -> String:
	var s := str(el.get("style", "house"))
	return s if STYLES.has(s) else "house"


static func record_of(el: Dictionary) -> String:
	return str(el.get("record", (STYLES[style_of(el)] as Array)[0]))


static func size_of(el: Dictionary) -> Vector3:
	return L.size3(el, (STYLES[style_of(el)] as Array)[1])


## The static kinds' interface: everything of this kind is in its props part.
static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The visuals and shapes of a style: {"intact": parts, "broken": parts, "blocks": [[size, center]],
## "hurt": [size, center], "center": Vector3, "links": bool}.
static func design(el: Dictionary) -> Dictionary:
	var s := size_of(el)
	match style_of(el):
		"gatehouse":
			var gap := float(el.get("gap", 18.0))
			var x := gap * 0.5 + s.x * 0.5
			var intact: Array = []
			var broken: Array = []
			var blocks: Array = []
			for side: float in [-1.0, 1.0]:
				intact.append(L.part("box", Vector3(x * side, -1.0, 0), Vector3(s.x, s.y + 1.0, s.z), "stone_light"))
				intact.append(L.part("pyramid", Vector3(x * side, s.y, 0), Vector3(s.x + 1.2, 3.0, s.z + 1.2), "roof_slate"))
				intact.append(L.part("box", Vector3((x - s.x * 0.5 - 0.3) * side, 0.0, s.z * 0.5 - 0.3), Vector3(0.6, 7.0, 3.6), "timber_dark", 0.0))
				intact.append(L.part("box", Vector3(x * side, s.y * 0.55, -s.z * 0.5 - 0.05), Vector3(1.6, 3.2, 0.12), "banner_blue"))
				broken.append(L.part("box", Vector3(x * side, -1.0, 0), Vector3(s.x + 0.6, s.y * 0.3, s.z + 0.6), "stone_dark", 11.0 * side))
				for k in 3:
					broken.append(L.part("box", Vector3((x + (k - 1) * 2.2) * side, -0.4, s.z * 0.9 + k * 0.8), Vector3(1.8, 1.1, 1.5), "stone", 23.0 * k))
				blocks.append([Vector3(s.x, s.y, s.z), Vector3(x * side, s.y * 0.5, 0)])
			return {"intact": intact, "broken": broken, "blocks": blocks, "hurt": [Vector3(gap + s.x * 2.0, s.y, s.z + 0.6),
				Vector3(0, s.y * 0.5, 0)], "center": Vector3(0, s.y * 0.5, 0), "links": false}
		"gate":
			var intact: Array = []
			var broken: Array = []
			for side: float in [-1.0, 1.0]:
				intact.append(L.part("box", Vector3(s.x * 0.25 * side, -0.5, 0), Vector3(s.x * 0.5 - 0.2, s.y + 0.5, s.z), "timber"))
				for b in 3:
					intact.append(L.part("box", Vector3(s.x * 0.25 * side, 1.0 + b * 2.2, -s.z * 0.5 - 0.05), Vector3(s.x * 0.5 - 0.6, 0.35, 0.15), "iron"))
				intact.append(L.part("box", Vector3((s.x * 0.5 + 0.6) * side, -0.5, 0), Vector3(1.2, s.y + 2.5, 1.4), "timber_dark"))
				broken.append(L.part("box", Vector3((s.x * 0.5 + 0.6) * side, -0.5, 0), Vector3(1.2, s.y * 0.6, 1.4), "timber_dark"))
			for k in 5:
				broken.append(L.part("box", Vector3(-s.x * 0.4 + k * s.x * 0.2, -0.2, 1.5 + (k % 2) * 1.4), Vector3(3.0, 0.5, 1.2), "timber", 17.0 * k))
			var blocks: Array = [[Vector3(s.x, s.y, s.z), Vector3(0, s.y * 0.5, 0)]]
			for side: float in [-1.0, 1.0]:
				blocks.append([Vector3(1.2, s.y + 2.0, 1.4), Vector3((s.x * 0.5 + 0.6) * side, (s.y + 2.0) * 0.5, 0)])
			return {"intact": intact, "broken": broken, "blocks": blocks, "hurt": [Vector3(s.x, s.y, s.z + 0.8), Vector3(0, s.y * 0.5, 0)],
				"center": Vector3(0, s.y * 0.5, 0), "links": true}
		"dam":
			var intact: Array = []
			var rocks := [[-4.8, 0.0, 0.2, 3.4], [-1.4, 0.0, -0.3, 3.8], [2.2, 0.0, 0.3, 3.5], [5.2, 0.0, -0.2, 3.0],
				[-3.0, 2.6, 0.0, 2.8], [0.6, 2.9, 0.2, 3.0], [3.8, 2.4, -0.1, 2.5], [-0.9, 4.6, 0.0, 2.0]]
			for i in rocks.size():
				var r: Array = rocks[i]
				intact.append(L.part("sphere", Vector3(float(r[0]), float(r[1]) - 0.6, float(r[2])), Vector3(float(r[3]), float(r[3]) * 0.8, float(r[3])),
					"rock" if i % 2 == 0 else "stone_dark", 31.0 * i))
			var broken: Array = []
			for i in 6:
				var side := -1.0 if i % 2 == 0 else 1.0
				broken.append(L.part("sphere", Vector3(side * (s.x * 0.5 + 2.0 + 1.6 * (i / 2)), -0.5, -1.5 + 1.5 * (i / 2)),
					Vector3(2.4, 1.8, 2.4), "rock" if i % 3 == 0 else "stone_dark", 47.0 * i))
			return {"intact": intact, "broken": broken, "blocks": [[Vector3(s.x, s.y, s.z), Vector3(0, s.y * 0.5 - 0.5, 0)]],
				"hurt": [Vector3(s.x, s.y, s.z + 0.6), Vector3(0, s.y * 0.5 - 0.5, 0)], "center": Vector3(0, s.y * 0.5, 0), "links": false}
	# a house
	var wall := str(el.get("wall", "plaster"))
	var roof := str(ROOFS.get(str(el.get("roof", "thatch")), "thatch"))
	var intact: Array = [
		L.part("box", Vector3(0, -0.5, 0), Vector3(s.x, s.y + 0.5, s.z), wall),
		L.part("roof", Vector3(0, s.y, 0), Vector3(s.x + 0.8, s.y * 0.6, s.z + 0.8), roof),
		L.part("box", Vector3(0, 0, s.z * 0.5 + 0.05), Vector3(1.4, 2.4, 0.2), "timber_dark"),
		L.part("box", Vector3(s.x * 0.28, s.y * 0.45, s.z * 0.5 + 0.05), Vector3(1.2, 1.0, 0.15), "timber_dark"),
		L.part("box", Vector3(-s.x * 0.3, s.y + s.y * 0.2, 0), Vector3(0.9, s.y * 0.55, 0.9), "stone_dark"),
	]
	var broken: Array = [
		L.part("box", Vector3(0, -0.5, 0), Vector3(s.x, s.y * 0.35 + 0.5, s.z), "stone_dark"),
		L.part("box", Vector3(s.x * 0.3, 0.0, s.z * 0.2), Vector3(1.0, s.y * 0.6, 1.0), "black"),
		L.part("box", Vector3(-s.x * 0.25, s.y * 0.35, -s.z * 0.1), Vector3(s.x * 0.4, 0.6, s.z * 0.5), "timber_dark", 9.0),
	]
	return {"intact": intact, "broken": broken, "blocks": [[Vector3(s.x, s.y + 0.5, s.z), Vector3(0, (s.y + 0.5) * 0.5 - 0.5, 0)]],
		"hurt": [Vector3(s.x + 0.4, s.y + 0.5, s.z + 0.4), Vector3(0, (s.y + 0.5) * 0.5 - 0.5, 0)],
		"center": Vector3(0, s.y * 0.5, 0), "links": false}


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var id := str(el.get("id", ""))
	var d := design(el)
	var root := StaticBody3D.new()
	root.name = id.validate_node_name()
	kit.scripted(root, S_BREAKABLE, {"world_id": id})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	if str(el.get("faction", "")) != "":
		root.set_meta(&"faction", str(el.faction))
	var tags: Variant = el.get("prop_tags", ["house"] if style_of(el) == "house" else [])
	if typeof(tags) == TYPE_ARRAY and not (tags as Array).is_empty():
		root.set_meta(&"prop_tags", PackedStringArray(tags))
	root.add_child(kit.combat_entity(id, record_of(el), 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", d.center))
	root.add_child(anchors)
	var k := 0
	for b: Array in d.blocks:
		var cs := CollisionShape3D.new()
		cs.name = "Block%d" % k
		cs.shape = kit.box_shape(b[0])
		cs.position = b[1]
		root.add_child(cs)
		k += 1
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(d.hurt[0]), d.hurt[1]))
	root.add_child(hb)
	var mat: Material = ctx.get("mat")
	var intact := kit.n3("Intact")
	intact.add_child(L.parts_node("Mesh", d.intact, mat))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(L.parts_node("Mesh", d.broken, mat))
	broken.visible = false
	root.add_child(broken)
	if bool(d.links):
		for spec: Dictionary in NavBake.LAYERS:
			var layer := int(spec.layer)
			var half := float(LINK_HALF_M.get(layer, 4.0))
			var link := NavigationLink3D.new()
			link.name = "NavLink" + str(spec.name).capitalize()
			link.start_position = Vector3(0.0, float(spec.above_m) + 0.2, half)
			link.end_position = Vector3(0.0, float(spec.above_m) + 0.2, -half)
			link.bidirectional = true
			link.navigation_layers = layer
			link.enabled = false
			root.add_child(link)
	return root
