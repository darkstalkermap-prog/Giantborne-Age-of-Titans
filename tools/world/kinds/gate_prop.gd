extends RefCounted
## Element kind "gate_prop" (P25): a scripted gate in a wall's gap - style "fortified" (P08's
## gate_fortified scene: 12 m doors between two towers, 18 m in all, breached at stage 4) with the
## element's world id and `indestructible` (Fort Aldmere's gate stays shut until P36 makes it the
## real gate). One closed NavigationLink3D per world nav layer runs through it (opened when the gate
## breaks; the streamer joins each to its layer's map). It goes into its chunk's props sub-scene.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const SCENES := {"fortified": "res://scenes/world/gate_fortified.tscn"}
## Half lengths of the per-layer links (they must reach each layer's navmesh beyond the gate).
const LINK_HALF_M := {1: 3.5, 2: 4.5, 16: 7.0}
## Marks nodes added under an instanced scene (the builder makes the part own them when saving).
const ADDED_META := &"world_added"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var path := str(SCENES.get(str(el.get("style", "fortified")), SCENES.fortified))
	var g := kit.instance(path) as Node3D
	if g == null:
		return null
	g.name = str(el.id).validate_node_name()
	g.set("world_id", str(el.id))
	if bool(el.get("indestructible", false)) and "indestructible" in g:
		g.set("indestructible", true)
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
		link.set_meta(ADDED_META, true)
		g.add_child(link)
	return g
