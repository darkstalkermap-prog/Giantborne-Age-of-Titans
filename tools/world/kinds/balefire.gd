extends RefCounted
## Element kind "balefire" (D1): a great fire a giant warms himself at - the Hearth's watchers' balefires on the
## Rimeglass's shore: a ring of stones round a stack of whole pines burning (settlement_fire's flames and light at
## `size`), and its warmth (scripts/world/warmth_source.gd: WarmthSource, `radius` m: it thaws a giant's rime).
## `requires_flag`: lit (seen and warming) only once that flag is set (the watchers came). FLAG_WRAP: a flagged
## balefire is built whole inside its FlagVisibility.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const FLAG_WRAP := true
const S_WARMTH := "res://scripts/world/warmth_source.gd"
const FIRE := preload("res://tools/world/kinds/settlement_fire.gd")


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var h := float(el.get("size", 4.2))
	# the ring of stones and the stacked trunks (one vertex-coloured mesh)
	var parts: Array = []
	var stones := 11
	for k in stones:
		var a := TAU * float(k) / float(stones)
		var r := h * 1.25
		parts.append(L.part("sphere", Vector3(cos(a) * r, -0.3, sin(a) * r), Vector3(1.6, 1.3, 1.4) * (0.8 + 0.25 * float(k % 3)),
			"stone_dark", rad_to_deg(a)))
	for k in 6:
		var a := PI * float(k) / 6.0
		parts.append(L.part("cyl", Vector3(0, 0.6 + 0.35 * float(k % 2), 0), Vector3(0.9, 0.9, h * 2.2), "timber_dark",
			rad_to_deg(a), Vector3(90, 0, 0)))
	n.add_child(L.parts_node("Stack", parts))
	var fire := FIRE.build(kit, {"id": str(el.id) + ".flames", "size": h, "embers_m": h * 1.15,
		"energy": float(el.get("energy", 3.2)), "range": float(el.get("range", 28.0)),
		"light_far_m": float(el.get("light_far_m", 260.0)), "far_m": float(el.get("far_m", 1600.0))}, {})
	n.add_child(fire)
	var w := Node3D.new()
	w.name = "Warmth"
	kit.scripted(w, S_WARMTH, {"radius_m": float(el.get("radius", 22.0)), "requires_flag": str(el.get("requires_flag", "")),
		"hidden_when_flag": str(el.get("hidden_when_flag", ""))})
	n.add_child(w)
	return n
