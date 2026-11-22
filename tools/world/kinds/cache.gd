extends RefCounted
## Element kind "cache" (P25; plan M6-M9 decision 33): something to find - style "crate" (P08's
## breakable supply crate with this cache's loot table, `loot`: data/loot/cache_<name>.json; one
## award per world id, so it pays once), or "ledge" (an ItemPickup of `item` x `count` with
## `requires_stage`: a chest on a high ledge that only a big enough giant reaches - the Titan's
## shoulder and the ridge eyrie: "Out of reach. Grow to stage 6."). Its chunk's props sub-scene
## holds it. The region package that brings a place's content may remove its cache.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const CRATE := "res://scenes/world/crate.tscn"
const S_PICKUP := "res://scripts/world/item_pickup.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	if str(el.get("style", "crate")) == "ledge":
		return _ledge(kit, el, ctx)
	if str(el.get("style", "crate")) == "pile":
		return _pile(kit, el, ctx)
	var c := kit.instance(CRATE) as Node3D
	if c == null:
		return null
	c.name = str(el.id).validate_node_name()
	c.set("world_id", str(el.id))
	c.set("loot_table", str(el.get("loot", "")))
	return c


## A pickup at the foot of a ledge: the chest stands `ledge_m` up on a rock spire (Visual, hidden
## once taken), the interaction on the ground below it.
static func _ledge(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var stage := int(el.get("requires_stage", 6))
	kit.scripted(n, S_PICKUP, {"world_id": str(el.id), "item_id": str(el.get("item", "item.iron_ingot")),
		"count": int(el.get("count", 1)), "requires_stage": stage, "radius_m": 6.0, "priority": 45,
		"stage_message": str(el.get("stage_message", "Out of reach. Grow to stage %d." % stage))})
	var up := float(el.get("ledge_m", 15.0))
	var visual := Node3D.new()
	visual.name = "Visual"
	var parts: Array = [
		L.part("box", Vector3(0, up, -1.5), Vector3(2.4, 1.4, 1.6), "timber_dark"),
		L.part("box", Vector3(0, up + 1.4, -1.5), Vector3(2.5, 0.4, 1.7), "gold"),
	]
	# M8 gate (F27): the chest fades with the preset's scenery distance (220 m at low) as the other props
	# do; before, it cost a draw call a view at any distance (plan §5.2: at most 40 a view at low).
	var chest := L.parts_node("Chest", parts, ctx.get("mat"))
	chest.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	visual.add_child(chest)
	n.add_child(visual)
	return n


## B1: a pile of a titan's stone or iron to take (an ItemPickup of `item` x `count`) that is there only once
## `requires_flag` holds - the reopened quarry's slabs and shackle iron (world.quarry.reopened): a few dressed blocks,
## or bound iron bars, at the giant's scale (Visual, hidden until then and once taken).
static func _pile(kit: SceneKit, el: Dictionary, ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var props := {"world_id": str(el.id), "item_id": str(el.get("item", "item.stoneback_slab")),
		"count": int(el.get("count", 1)), "radius_m": float(el.get("radius", 7.0)), "priority": 45}
	if str(el.get("requires_flag", "")) != "":
		props["requires_flag"] = str(el.requires_flag)
	kit.scripted(n, S_PICKUP, props)
	var visual := Node3D.new()
	visual.name = "Visual"
	var iron := str(el.get("item", "")).contains("iron")
	var parts: Array = []
	if iron:
		for i in 4:
			parts.append(L.part("box", Vector3(-1.2 + 0.8 * i, 0.25, 0.1 * (i % 2)), Vector3(0.5, 0.5, 3.6), "iron"))
		parts.append(L.part("box", Vector3(0, 0.75, 0), Vector3(3.2, 0.3, 0.5), "timber_dark"))
	else:
		parts.append(L.part("box", Vector3(0, 0.6, 0), Vector3(4.2, 1.2, 2.6), "stone"))
		parts.append(L.part("box", Vector3(0.4, 1.75, -0.2), Vector3(3.4, 1.1, 2.2), "stone_dark"))
		parts.append(L.part("box", Vector3(-0.3, 2.75, 0.1), Vector3(2.6, 0.9, 1.8), "stone"))
		parts.append(L.part("box", Vector3(0, 1.2, 1.32), Vector3(4.3, 0.3, 0.12), "iron"))
	var pile := L.parts_node("Pile", parts, ctx.get("mat"))
	pile.add_to_group(TerrainChunk.SCENERY_GROUP, true)
	visual.add_child(pile)
	n.add_child(visual)
	return n

