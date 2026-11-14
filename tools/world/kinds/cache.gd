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
