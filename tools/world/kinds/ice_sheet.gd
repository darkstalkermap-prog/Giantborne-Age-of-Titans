extends RefCounted
## Element kind "ice_sheet" (D1): a frozen tarn's ice (scripts/world/ice_sheet.gd: IceSheet) - `radius` (m), `cell_m`,
## `refreeze_s`, `thaw_flag` (once set the cold is gone from it: the Frostbound fallen), its surface `lift` metres over
## the ground at `pos` (the tarn's flattened bed). Its look is its own (a disc drawn from its cells' states over a dark
## water plane); no solids (the giant walks the tarn's bed under the ice's surface: the ice is a skin of a few
## decimetres).

const SCRIPTED := true
const S_ICE := "res://scripts/world/ice_sheet.gd"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	kit.scripted(n, S_ICE, {"sheet_id": str(el.id), "radius_m": float(el.get("radius", 60.0)),
		"cell_m": float(el.get("cell_m", 9.0)), "refreeze_s": float(el.get("refreeze_s", 45.0)),
		"thaw_flag": str(el.get("thaw_flag", "")), "ice_lift_m": float(el.get("lift", 0.12))})
	return n
