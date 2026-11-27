class_name StormWater
extends Node3D
## D2 (decision D2-3): the water the Stormcaller's lightning runs through - the flooded pools of the Stormstair, the top
## of the Drowned Steps, where he stands calling the storm.
##
## A set of pools (`pools`: [centre x, centre z, radius x, radius z, surface y] in the node's space - ellipses): the
## water stands at its surface over whatever ground is under it, so how deep a body stands in it is the surface less
## the body's feet (depth_at). The world builder carves the pools' beds (basins) and lays this node over them; the
## test arena's floor is flat, so its pools are water standing that deep over the floor and drawn here (draw).
##
## What the pools are for (TitanEnemy's `storm`, PlayerStorm): a bolt of his that strikes water sends the shock out
## through it - every body standing in water within its reach takes it, by how much of the body is under water (a
## bigger giant stands higher out of the same pool); a titan standing deep in it is grounded by it (down on a knee).
## A pure lookup: nothing here steps. After his fall (calm_flag) the storm has gone out of the water: no shock runs.

const GROUP := "storm_water"
const SHADER := "res://assets/shaders/storm_water.gdshader"

@export var water_id := "storm_water"
## [cx, cz, rx, rz, surface_y] ellipses in the node's space.
@export var pools: Array = []
## Once this world flag is set (the Stormcaller fallen) the water is only water.
@export var calm_flag := ""
## Draw the pools' water (the test arena's flat floor); the world's chunks draw their own water.
@export var draw := false
## The rain on the drawn water (0..1) and the wind's direction over it (the look).
@export var rain := 1.0


func _ready() -> void:
	add_to_group(GROUP)
	if draw:
		_build_look()


func calm() -> bool:
	return calm_flag != "" and bool(WorldState.get_flag(calm_flag, false))


## The depth of this node's water at world point `p` (its feet): 0 outside every pool or above the water.
func depth_here(p: Vector3) -> float:
	var l := to_local(p)
	var best := 0.0
	for pool: Variant in pools:
		var a := pool as Array
		if a == null or a.size() < 5:
			continue
		var dx := (l.x - float(a[0])) / maxf(0.01, float(a[2]))
		var dz := (l.z - float(a[1])) / maxf(0.01, float(a[3]))
		if dx * dx + dz * dz > 1.0:
			continue
		best = maxf(best, float(a[4]) - l.y)
	return maxf(0.0, best)


## The surface's height (world) of the pool over `p`, NAN where there is none.
func surface_here(p: Vector3) -> float:
	var l := to_local(p)
	var out := NAN
	for pool: Variant in pools:
		var a := pool as Array
		if a == null or a.size() < 5:
			continue
		var dx := (l.x - float(a[0])) / maxf(0.01, float(a[2]))
		var dz := (l.z - float(a[1])) / maxf(0.01, float(a[3]))
		if dx * dx + dz * dz <= 1.0:
			var y := to_global(Vector3(l.x, float(a[4]), l.z)).y
			out = y if is_nan(out) else maxf(out, y)
	return out


## How deep the storm's water stands at world point `p` (the deepest of every live StormWater over it): 0 when dry.
static func depth_at(tree: SceneTree, p: Vector3) -> float:
	if tree == null:
		return 0.0
	var best := 0.0
	for node in tree.get_nodes_in_group(GROUP):
		var w := node as StormWater
		if w == null or not w.is_inside_tree() or w.calm():
			continue
		best = maxf(best, w.depth_here(p))
	return best


## The share of a body `height_m` tall standing at `p` that is under the storm's water (0..1).
static func wet_share(tree: SceneTree, p: Vector3, height_m: float) -> float:
	if height_m <= 0.0:
		return 0.0
	return clampf(depth_at(tree, p) / height_m, 0.0, 1.0)


# --------------------------------------------------------------------------- the look (the test arena)

func _build_look() -> void:
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--skin"):
		return
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter(&"rain", rain)
	var i := 0
	for pool: Variant in pools:
		var a := pool as Array
		var mi := MeshInstance3D.new()
		mi.name = "Pool%d" % i
		var w := CylinderMesh.new()
		w.top_radius = 1.0
		w.bottom_radius = 1.0
		w.height = 0.02
		w.radial_segments = 48
		w.rings = 1
		w.cap_bottom = false
		mi.mesh = w
		mi.material_override = mat
		mi.scale = Vector3(float(a[2]), 1.0, float(a[3]))
		mi.position = Vector3(float(a[0]), float(a[4]), float(a[1]))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		i += 1
