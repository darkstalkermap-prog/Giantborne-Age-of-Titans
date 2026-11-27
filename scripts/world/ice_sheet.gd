class_name IceSheet
extends Node3D
## D1 (decision D1-3): a frozen tarn's ice - the Rimeglass under the Hoarcrown, where the Frostbound Titan came down.
## The ice is a grid of cells (cell_m square) inside radius_m of the node: each WHOLE, CRACKED or OPEN.
##
##   * A heavy blow on it cracks it: an area pulse (Events.area_pulse: a stomp, a shock line, a thrown serac, the
##     Frostbound's nova; the giant's own stamps and Heavy Footfall) of at least crack_min_radius_m cracks every cell
##     whose middle lies within its radius by one step (an action's `ice_crack` parameter: by that many), so whole ice
##     cracks and cracked ice breaks open. Men's blows never crack it.
##   * Open water freezes over again after refreeze_s - thin, cracked ice: the place stays weak.
##   * Weight: the Frostbound Titan (the heaviest thing on it) breaks through cracked or open ice where he steps and
##     goes down to the knee in the water (TitanEnemy, his record's `ice`: a down of his topple's kneel, rise and
##     ice.down_s); a giant wading in open water is slowed and the cold water rimes him (PlayerRime).
##   * His new attempt makes the ice whole again (reset); once he has fallen (thaw_flag) the cold is gone from it:
##     open water no longer rimes a giant and it never freezes again.
## Deterministic: its state changes only on simulation events and is read lazily by tick (state_at), so a seeded duel
## repeats. Its look (a disc of ice drawn by ice_sheet.gdshader from a small texture of the cells' states, a dark
## water plane under it) follows in _process.

const GROUP := "ice_sheets"
const WHOLE := 2
const CRACKED := 1
const OPEN := 0
const NOT_ICE := -1
const SHADER := "res://assets/shaders/ice_sheet.gdshader"

@export var sheet_id := "ice"
@export var radius_m := 70.0
@export var cell_m := 9.0
@export var refreeze_s := 45.0
@export var crack_min_radius_m := 3.5
## Once this world flag is set the tarn's cold is gone (the Frostbound fallen): open water rimes no one, no refreeze.
@export var thaw_flag := ""
## The look: the ice's surface over the node's origin (m), the water's under it.
@export var ice_lift_m := 0.10
@export var water_drop_m := 0.30

var n := 0
var cells := PackedByteArray()
var open_until := PackedInt32Array()
## Tallies (tests, the duel report): cells cracked and broken open, by whom ({entity id: count}).
var cracks := 0
var breaks := 0
var by := {}
var _dirty := true
var _image: Image = null
var _texture: ImageTexture = null
var _ice: MeshInstance3D = null
var _water: MeshInstance3D = null


func _ready() -> void:
	add_to_group(GROUP)
	n = maxi(1, int(ceil(radius_m * 2.0 / cell_m)))
	cells.resize(n * n)
	open_until.resize(n * n)
	reset()
	if not Events.area_pulse.is_connected(_on_area_pulse):
		Events.area_pulse.connect(_on_area_pulse)
	_build_look()


func _exit_tree() -> void:
	if Events.area_pulse.is_connected(_on_area_pulse):
		Events.area_pulse.disconnect(_on_area_pulse)


## Every cell whole again (a new attempt; the level loading). Thawed (thaw_flag set: he has fallen), the tarn is
## open water with floes instead: most cells open, a hashed few cracked floes, and it stays so.
func reset() -> void:
	var melt := thawed()
	for i in cells.size():
		if not _inside(i):
			cells[i] = 255
		elif melt:
			cells[i] = CRACKED if hash(i * 31 + 7) % 10 < 3 else OPEN   # (a scattered hash: no rows)
		else:
			cells[i] = WHOLE
		open_until[i] = -1
	_dirty = true


func thawed() -> bool:
	return thaw_flag != "" and bool(WorldState.get_flag(thaw_flag, false))


## The cell index at world point `p` (-1 outside the ice).
func cell_of(p: Vector3) -> int:
	var l := to_local(p)
	var i := int(floor((l.x + radius_m) / cell_m))
	var j := int(floor((l.z + radius_m) / cell_m))
	if i < 0 or j < 0 or i >= n or j >= n:
		return -1
	var k := j * n + i
	return k if _inside(k) else -1


func _inside(k: int) -> bool:
	var c := cell_centre_local(k)
	return Vector2(c.x, c.z).length() <= radius_m - cell_m * 0.25


func cell_centre_local(k: int) -> Vector3:
	var i := k % n
	var j := k / n
	return Vector3(-radius_m + (float(i) + 0.5) * cell_m, 0.0, -radius_m + (float(j) + 0.5) * cell_m)


func cell_centre(k: int) -> Vector3:
	return to_global(cell_centre_local(k))


## The state of cell k now (lazily refrozen).
func state(k: int) -> int:
	if k < 0 or k >= cells.size():
		return NOT_ICE
	var s := int(cells[k])
	if s == 255:
		return NOT_ICE
	if s == OPEN and open_until[k] >= 0 and Sim.tick >= open_until[k] and not thawed():
		cells[k] = CRACKED
		open_until[k] = -1
		_dirty = true
		Events.ice_changed.emit(Sim.tick, sheet_id, k, CRACKED, "")
		return CRACKED
	return s


func state_at(p: Vector3) -> int:
	var k := cell_of(p)
	if k < 0:
		return NOT_ICE
	# (open water is open water a giant's height above it no longer: he walks on the shore's level)
	if absf(p.y - global_position.y) > 6.0:
		return NOT_ICE
	return state(k)


## True while open water rimes a giant wading in it.
func cold() -> bool:
	return not thawed()


## Weakens cell k by `steps` (WHOLE -> CRACKED -> OPEN): its new state.
func weaken(k: int, steps: int, by_id: String) -> int:
	var s := state(k)
	if s == NOT_ICE or s == OPEN or steps <= 0:
		return s
	var to := maxi(OPEN, s - steps)
	cells[k] = to
	if to == CRACKED:
		cracks += 1
	if to == OPEN:
		breaks += 1
		open_until[k] = Sim.tick + ActionDef.seconds_to_ticks(refreeze_s) if not thawed() else -1
	by[by_id] = int(by.get(by_id, 0)) + 1
	_dirty = true
	Events.ice_changed.emit(Sim.tick, sheet_id, k, to, by_id)
	return to


## Breaks cell k open at once (a weight through it).
func break_open(k: int, by_id: String) -> int:
	return weaken(k, 2, by_id)


## Cracks every cell within `radius` of `center` by `steps`: the cells it changed.
func crack_area(center: Vector3, radius: float, steps: int, by_id: String) -> int:
	if absf(center.y - global_position.y) > 8.0:
		return 0
	var changed := 0
	var l := to_local(center)
	var reach := radius + cell_m * 0.35
	var i0 := clampi(int(floor((l.x - reach + radius_m) / cell_m)), 0, n - 1)
	var i1 := clampi(int(floor((l.x + reach + radius_m) / cell_m)), 0, n - 1)
	var j0 := clampi(int(floor((l.z - reach + radius_m) / cell_m)), 0, n - 1)
	var j1 := clampi(int(floor((l.z + reach + radius_m) / cell_m)), 0, n - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var k := j * n + i
			var c := cell_centre_local(k)
			if Vector2(c.x - l.x, c.z - l.z).length() > reach:
				continue
			var before := state(k)
			if before == NOT_ICE or before == OPEN:
				continue
			if weaken(k, steps, by_id) != before:
				changed += 1
	return changed


func _on_area_pulse(_tick: int, actor_id: String, action_id: String, center: Vector3, radius: float) -> void:
	if radius < crack_min_radius_m or not is_inside_tree():
		return
	var steps := 1
	var a := GameData.get_action(action_id) if action_id != "" else null
	if a != null:
		steps = int(a.param("ice_crack", 1))
	crack_area(center, radius, steps, actor_id)


## The ice sheet under `pos` (null when none).
static func sheet_at(tree: SceneTree, pos: Vector3) -> IceSheet:
	if tree == null:
		return null
	for node in tree.get_nodes_in_group(GROUP):
		var s := node as IceSheet
		if s != null and s.is_inside_tree() and s.cell_of(pos) >= 0:
			return s
	return null


func counts() -> Dictionary:
	var out := {"whole": 0, "cracked": 0, "open": 0}
	for k in cells.size():
		match state(k):
			WHOLE:
				out.whole += 1
			CRACKED:
				out.cracked += 1
			OPEN:
				out.open += 1
	return out


# --------------------------------------------------------------------------- the look

func _build_look() -> void:
	if DisplayServer.get_name() == "headless" and not OS.get_cmdline_user_args().has("--skin"):
		return
	_image = Image.create(n, n, false, Image.FORMAT_R8)
	_texture = ImageTexture.create_from_image(_image)
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER)
	mat.set_shader_parameter(&"cells", _texture)
	mat.set_shader_parameter(&"cells_n", float(n))
	mat.set_shader_parameter(&"radius_m", radius_m)
	_ice = MeshInstance3D.new()
	_ice.name = "Ice"
	var q := PlaneMesh.new()
	q.size = Vector2(radius_m * 2.0, radius_m * 2.0)
	q.subdivide_width = 1
	q.subdivide_depth = 1
	_ice.mesh = q
	_ice.material_override = mat
	_ice.position = Vector3(0.0, ice_lift_m, 0.0)
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ice)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	# (a disc, not a square: the water stands over the bed, so its corners would show past the ice's ragged edge)
	var w := CylinderMesh.new()
	w.top_radius = radius_m - 2.0
	w.bottom_radius = radius_m - 2.0
	w.height = 0.02
	w.radial_segments = 48
	w.rings = 1
	w.cap_bottom = false
	_water.mesh = w
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.10, 0.17, 0.22)   # (deep cold water, grey-green; darker read as holes in the world)
	wm.roughness = 0.12
	wm.metallic_specular = 0.7
	_water.material_override = wm
	_water.position = Vector3(0.0, ice_lift_m - water_drop_m, 0.0)
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)


func _process(_delta: float) -> void:
	if _image == null:
		return
	# (refreezing is lazy: poll the open cells' clocks so the look follows)
	for k in cells.size():
		if int(cells[k]) == OPEN:
			state(k)
	if not _dirty:
		return
	_dirty = false
	for k in cells.size():
		var s := int(cells[k])
		var v := 0.0
		if s == WHOLE:
			v = 1.0
		elif s == CRACKED:
			v = 0.5
		elif s == 255:
			v = 1.0
		_image.set_pixel(k % n, k / n, Color(v, 0.0, 0.0))
	_texture.update(_image)
