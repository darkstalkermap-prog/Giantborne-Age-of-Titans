extends RefCounted
## Element kind "settlement_board" (C4): a settlement's builder's board (scripts/world/settlement_board.gd: E opens
## the settlement panel) wearing scenes/world/settlement_board.tscn (built by tools/builders/forge.gd: a timber
## tally-post with its board, the steward's tallies and hides, a lamp) - `settlement`, `radius`. Its chunk's props
## sub-scene holds it.

const SCRIPTED := true
const S_BOARD := "res://scripts/world/settlement_board.gd"
const LOOK := "res://scenes/world/settlement_board.tscn"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_BOARD, {"world_id": str(el.id), "settlement_id": str(el.get("settlement", "")),
		"radius_m": float(el.get("radius", 12.0))})
	var look := kit.instance(LOOK) as Node3D
	if look != null:
		look.name = "Look"
		var s := float(el.get("scale", 1.0))
		look.scale = Vector3(s, s, s)
		n.add_child(look)
	return n
