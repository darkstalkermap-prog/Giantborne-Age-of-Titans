extends RefCounted
## Element kind "longhouse" (P36; plan M6-M9 §5.4, §5.7, §5.9, §5.10): a giants' longhouse of Skarn that
## a siege can burn and a giant can raise again - a BreakableProp built here in code (the breakable_site
## contract: its CombatEntity, team NEUTRAL, on Anchors/Center, Block* shapes on the breakables layer,
## Hurtboxes, Intact and Broken visuals) of record `record` (prop.longhouse_skarn), `size` [w, h, d],
## owned by its `faction` (a short name: damage the giant deals to it is an offence) and tagged
## `prop_tags` (["house"]: the siege line's engines bombard it, P37's protect objective counts it).
## Burned, it shows its charred frame; `rebuilt_flag` (world.skarn.longhouse_<n>.rebuilt) shows it raised
## again (a FlagVisibility child with its own solid body) - set by its RebuildPoint (the errand of
## quest.skarn_rebuild: "Lift the roof beams back", stage 6, while `waiting_flag` holds). Its chunk's
## props sub-scene holds it; the index lists it as a prop (Skarn's landmark among them).

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const S_BREAKABLE := "res://scripts/world/breakable_prop.gd"
const S_FLAG := "res://scripts/world/flag_visibility.gd"
const S_REBUILD := "res://scripts/world/rebuild_point.gd"
const DEFAULT_SIZE := Vector3(40, 15, 14)


## The standing house's parts: the builder draws them on the map and, with `skyline`, in the skyline's
## silhouettes (a scripted kind's own mesh is its node's, never the chunk's structures mesh).
static func parts(el: Dictionary, _ctx: Dictionary) -> Array:
	return intact_parts(L.size3(el, DEFAULT_SIZE))


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


## The standing house: timber walls, a turf roof, the smoke holes (hall.gd's longhouse).
static func intact_parts(s: Vector3) -> Array:
	var out: Array = []
	out.append(L.part("box", Vector3(0, -1, 0), Vector3(s.x, s.y * 0.45 + 1, s.z), "timber_dark"))
	out.append(L.part("roof", Vector3(0, s.y * 0.45, 0), Vector3(s.x + 2.0, s.y * 0.55, s.z + 3.0), "moss"))
	for k in 3:
		out.append(L.part("box", Vector3(-s.x * 0.5 + 2.0 + k * (s.x - 4.0) * 0.5, s.y * 0.85, 0), Vector3(1.6, s.y * 0.3, 1.6), "stone_dark"))
	out.append(L.part("box", Vector3(0, -0.5, s.z * 0.5 + 0.1), Vector3(5.0, 6.0, 0.4), "timber"))
	return out


## The burned house: charred stumps of its walls, a fallen ridge beam, ash.
static func burned_parts(s: Vector3) -> Array:
	var out: Array = []
	out.append(L.part("box", Vector3(0, -0.8, 0), Vector3(s.x, 0.9, s.z), "black"))
	for side: float in [-1.0, 1.0]:
		out.append(L.part("box", Vector3(0, -0.5, side * (s.z * 0.5 - 0.6)), Vector3(s.x, s.y * 0.18, 1.2), "timber_dark"))
		out.append(L.part("box", Vector3(side * (s.x * 0.5 - 0.6), -0.5, 0), Vector3(1.2, s.y * 0.25, s.z), "timber_dark"))
	out.append(L.part("box", Vector3(2.0, 0.4, 0.8), Vector3(s.x * 0.8, 1.0, 1.0), "timber_dark", 7.0, Vector3(0, 0, 8)))
	for k in 3:
		out.append(L.part("box", Vector3(-s.x * 0.5 + 2.0 + k * (s.x - 4.0) * 0.5, -0.5, 0), Vector3(1.6, s.y * 0.5, 1.6), "stone_dark"))
	return out


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var id := str(el.get("id", ""))
	var s := L.size3(el, DEFAULT_SIZE)
	var body_h := s.y * 0.6
	var root := StaticBody3D.new()
	root.name = id.validate_node_name()
	kit.scripted(root, S_BREAKABLE, {"world_id": id})
	root.collision_layer = SceneKit.L_BREAKABLE
	root.collision_mask = 0
	if str(el.get("faction", "")) != "":
		root.set_meta(&"faction", str(el.faction))
	root.set_meta(&"prop_tags", PackedStringArray(el.get("prop_tags", ["house"])))
	root.add_child(kit.combat_entity(id, str(el.get("record", "prop.longhouse_skarn")), 0, "../Anchors/Center"))
	var anchors := kit.n3("Anchors")
	anchors.add_child(kit.marker("Center", Vector3(0, body_h * 0.5, 0)))
	root.add_child(anchors)
	var cs := CollisionShape3D.new()
	cs.name = "Block0"
	cs.shape = kit.box_shape(Vector3(s.x, body_h + 1.0, s.z))
	cs.position = Vector3(0, (body_h + 1.0) * 0.5 - 1.0, 0)
	root.add_child(cs)
	var hb := kit.n3("Hurtboxes")
	hb.add_child(kit.hurtbox("Body", "body", kit.box_shape(Vector3(s.x + 0.6, s.y, s.z + 0.6)), Vector3(0, s.y * 0.5 - 1.0, 0)))
	root.add_child(hb)
	var mat: Material = ctx.get("mat")
	var intact := kit.n3("Intact")
	intact.add_child(_scenery(L.parts_node("Mesh", intact_parts(s), mat)))
	root.add_child(intact)
	var broken := kit.n3("Broken")
	broken.add_child(_scenery(L.parts_node("Mesh", burned_parts(s), mat)))
	broken.visible = false
	root.add_child(broken)
	var rebuilt_flag := str(el.get("rebuilt_flag", ""))
	if rebuilt_flag != "":
		var rebuilt := Node3D.new()
		rebuilt.name = "Rebuilt"
		kit.scripted(rebuilt, S_FLAG, {"visible_when_flag": rebuilt_flag})
		rebuilt.add_child(_scenery(L.parts_node("Mesh", intact_parts(s), mat)))
		var rb := StaticBody3D.new()
		rb.name = "Body"
		rb.collision_layer = SceneKit.L_WORLD
		rb.collision_mask = 0
		var rcs := CollisionShape3D.new()
		rcs.name = "Shape"
		rcs.shape = kit.box_shape(Vector3(s.x, body_h + 1.0, s.z))
		rcs.position = Vector3(0, (body_h + 1.0) * 0.5 - 1.0, 0)
		rb.add_child(rcs)
		rebuilt.add_child(rb)
		root.add_child(rebuilt)
		var rp := Node3D.new()
		rp.name = "RebuildPoint"
		kit.scripted(rp, S_REBUILD, {"prop_world_id": id, "rebuilt_flag": rebuilt_flag,
			"waiting_flag": str(el.get("waiting_flag", "")), "radius_m": float(el.get("rebuild_radius", 10.0)),
			"priority": 40})
		rp.position = Vector3(0, 0, s.z * 0.5 + 4.0)
		root.add_child(rp)
	return root


## A visual in the scenery group (it fades with its chunk's other props).
static func _scenery(n: Node3D) -> Node3D:
	n.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	return n
