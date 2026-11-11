extends RefCounted
## Shared builder of the P35 kinds' code-built props (not a kind: WorldLayout skips names that start
## with "_"): a BreakableProp-family node - its script (BreakableProp or a subclass) with `props`, its
## CombatEntity (team NEUTRAL) on Anchors/Center, Block* shapes on the breakables layer (navigation
## obstacles while they stand), Hurtboxes/Body, the Intact and Broken visuals (one vertex-coloured
## mesh each, in the scenery group so they fade with the preset like the other props), and an
## optional static Frame (a WORLD body with its own mesh that stays when the prop breaks: a bell's
## posts). The bell, brazier, nest and den_wall kinds describe their props as designs:
##   {"intact": parts, "broken": parts, "blocks": [[size, center]], "hurt": [size, center],
##    "center": Vector3, "frame": parts, "frame_solids": [[size, center]]}

const L := preload("res://tools/world/layout.gd")


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary, script_path: String, record_id: String,
		design: Dictionary, props := {}) -> StaticBody3D:
	var id := str(el.get("id", ""))
	var root := StaticBody3D.new()
	root.name = id.validate_node_name()
	var p := {"world_id": id}
	p.merge(props)
	kit.scripted(root, script_path, p)
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	if str(el.get("faction", "")) != "":
		root.set_meta(&"faction", str(el.faction))
	root.add_child(kit.combat_entity(id, record_id, 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", design.get("center", Vector3(0, 2, 0))))
	root.add_child(anchors)
	var k := 0
	for b: Array in design.get("blocks", []):
		var cs := CollisionShape3D.new()
		cs.name = "Block%d" % k
		cs.shape = kit.box_shape(b[0])
		cs.position = b[1]
		root.add_child(cs)
		k += 1
	var hurt: Array = design.get("hurt", [Vector3(2, 2, 2), Vector3(0, 1, 0)])
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(hurt[0]), hurt[1]))
	root.add_child(hb)
	var mat: Material = ctx.get("mat")
	var intact := kit.n3("Intact")
	intact.add_child(scenery(L.parts_node("Mesh", design.get("intact", []), mat)))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(scenery(L.parts_node("Mesh", design.get("broken", []), mat)))
	broken.visible = false
	root.add_child(broken)
	var frame: Array = design.get("frame", [])
	if not frame.is_empty():
		var body := StaticBody3D.new()
		body.name = "Frame"
		body.collision_layer = SceneKit.L_WORLD
		body.collision_mask = 0
		var j := 0
		for s: Array in design.get("frame_solids", []):
			var fcs := CollisionShape3D.new()
			fcs.name = "Shape%d" % j
			fcs.shape = kit.box_shape(s[0])
			fcs.position = s[1]
			body.add_child(fcs)
			j += 1
		body.add_child(scenery(L.parts_node("Mesh", frame, mat)))
		root.add_child(body)
	return root


## A visual in the scenery group (saved with the scene): it fades out beyond the preset's scenery
## distance like the other props of its chunk (TerrainChunk, LevelRoot; 220 m at low).
static func scenery(n: Node3D) -> Node3D:
	n.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	return n


## The element's ground height (its frame's origin) and the water surface over it (NAN on land).
static func water_over(el: Dictionary, ctx: Dictionary) -> float:
	var feats: WorldFeatures = ctx.get("feats")
	var field: HeightField = ctx.get("field")
	if feats == null or field == null:
		return NAN
	var p := L.pos2(el)
	return feats.water_surface_at(field, p.x, p.y)
