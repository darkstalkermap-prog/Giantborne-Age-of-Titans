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
##     open water no longer rimes a giant and it never freezes again. D2: the thaw comes in place - set while the sheet
##     is loaded (Events.flag_changed), the ice breaks up over THAW_S, cell by cell from the middle out (each cell's turn
##     a little hashed), into the thawed tarn's open water and floes; loaded after it, the sheet is thawed at once.
## Deterministic: its state changes only on simulation events and is read lazily by tick (state_at), so a seeded duel
## repeats. Its look (a disc of ice drawn by ice_sheet.gdshader from a small texture of the cells' states, a dark
## water plane under it) follows in _process.

const GROUP := "ice_sheets"
const WHOLE := 2
const CRACKED := 1
const OPEN := 0
const NOT_ICE := -1
const SHADER := "res://assets/shaders/ice_sheet.gdshader"
const WATER_SHADER := "res://assets/shaders/storm_water_shore.gdshader"
## Dgate: the open water's depth in the tarn's middle (the look) and the share of its radius its shore rises over.
const WATER_DEPTH_M := 0.9
const SHORE_BAND := 0.14

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
## D2: how long the in-place thaw takes (s) and the share of it a cell's own hash may move its turn.
const THAW_S := 8.0
const THAW_JITTER := 0.25

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
var _water_mat: ShaderMaterial = null
## D2: the tick the in-place thaw began (-1: none running); the cells it has turned.
var thaw_started := -1
var thaw_turned := 0


func _ready() -> void:
	add_to_group(GROUP)
	n = maxi(1, int(ceil(radius_m * 2.0 / cell_m)))
	cells.resize(n * n)
	open_until.resize(n * n)
	reset()
	if not Events.area_pulse.is_connected(_on_area_pulse):
		Events.area_pulse.connect(_on_area_pulse)
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	_build_look()


func _exit_tree() -> void:
	if Events.area_pulse.is_connected(_on_area_pulse):
		Events.area_pulse.disconnect(_on_area_pulse)
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)


## D2: the thaw flag set while the sheet is loaded: the ice breaks up in place (thaw_step).
func _on_flag_changed(_tick: int, flag_id: String, value: Variant) -> void:
	if thaw_flag == "" or flag_id != thaw_flag or not bool(value) or thaw_started >= 0:
		return
	thaw_started = Sim.tick
	thaw_turned = 0
	_bank_look()


## The thawed tarn's state of cell k (open water, a hashed few floes: reset's pattern).
func _thawed_state(k: int) -> int:
	return CRACKED if hash(k * 31 + 7) % 10 < 3 else OPEN


## D2: the in-place thaw's step: every cell whose turn has come (its distance from the middle over the radius, moved a
## little by its hash, times THAW_S after the thaw began) takes the thawed tarn's state. True once every cell has.
func thaw_step() -> bool:
	if thaw_started < 0:
		return false
	var t := float(Sim.tick - thaw_started) / float(Sim.TICK_RATE)
	var done := true
	for k in cells.size():
		if int(cells[k]) == 255:
			continue
		var want := _thawed_state(k)
		if int(cells[k]) == want and open_until[k] < 0:
			continue
		var c := cell_centre_local(k)
		var share := clampf(Vector2(c.x, c.z).length() / maxf(radius_m, 1.0), 0.0, 1.0)
		var jitter := float(hash(k * 131 + 17) % 1000) / 1000.0 * THAW_JITTER
		var turn := clampf(share * (1.0 - THAW_JITTER) + jitter, 0.0, 1.0) * THAW_S
		if t < turn:
			done = false
			continue
		cells[k] = want
		open_until[k] = -1
		thaw_turned += 1
		_dirty = true
		Events.ice_changed.emit(Sim.tick, sheet_id, k, want, "")
	if done:
		thaw_started = -1
	return done


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
	mat.render_priority = 2   # (Dgate: over its water - both blend at their shores)
	_ice.position = Vector3(0.0, ice_lift_m, 0.0)
	_ice.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ice)
	_water = MeshInstance3D.new()
	_water.name = "Water"
	# Dgate: the water drawn to a shore (StormWater.shore_mesh, storm_water_shore.gdshader) - deeper in the middle, the
	# bed's colour in its shallows and a bank that fades into the hollow's ground - not a flat disc with a hard rim.
	# The tarn's hollow is flat under it: its shore is drawn over that flat floor (WATER_DEPTH_M deep inside, rising
	# out of the water over the last SHORE_BAND of its radius), the bank's fade hiding where the mesh ends.
	var surface := ice_lift_m - water_drop_m
	var r_w := radius_m - 1.0
	var ground := func(x: float, z: float) -> float:
		var u := Vector2(x, z).length() / (r_w * shore_lobe(atan2(z, x)))
		return surface - WATER_DEPTH_M + (WATER_DEPTH_M + 0.4) * smoothstep(1.0 - SHORE_BAND, 1.0, u)
	_water.mesh = StormWater.shore_mesh([0.0, 0.0, r_w, r_w, surface], ground, 1.12, 18, 64, 0.0)
	# (deep cold water, grey-green; darker read as holes in the world. D2: it moves - the storm water's slow ripples, no
	# rain. Dgate: frozen, its bank is the snow at the ice's edge; thawed, wet stone)
	var wm := ShaderMaterial.new()
	wm.shader = load(WATER_SHADER)
	wm.set_shader_parameter(&"deep", Color(0.13, 0.23, 0.28))
	wm.set_shader_parameter(&"shallow", Color(0.33, 0.38, 0.39))
	wm.set_shader_parameter(&"sky", Color(0.66, 0.74, 0.82))
	wm.set_shader_parameter(&"mirror", 0.3)
	wm.set_shader_parameter(&"clear_m", 0.9)
	wm.set_shader_parameter(&"rim_fade", Vector2(1.04, 1.12))
	wm.set_shader_parameter(&"rain", 0.0)
	wm.set_shader_parameter(&"ripple", 0.8)
	wm.render_priority = 1
	_water.material_override = wm
	_water_mat = wm
	_water.position = Vector3.ZERO
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_bank_look()


## Dgate: the tarn's shoreline is no circle: its radius at `angle` (radians, from +x toward +z) is radius_m times this
## (0.88-1.0: a few broad lobes). ice_sheet.gdshader draws the ice's edge by the same rule. The cells keep their disc:
## an edge cell up to 8 m beyond the drawn ice is still ice to the rules (the look only).
static func shore_lobe(angle: float) -> float:
	var f := 0.55 * sin(3.0 * angle + 0.7) + 0.3 * sin(5.0 * angle + 2.1) + 0.15 * sin(9.0 * angle + 4.0)
	return 0.94 + 0.06 * f


## Dgate: the water's bank - snow lying to the ice's edge while the tarn is frozen, wet stone once it has thawed.
func _bank_look() -> void:
	if _water_mat != null:
		var thawed_now := thawed()
		_water_mat.set_shader_parameter(&"bank_wet", Color(0.22, 0.23, 0.22) if thawed_now else Color(0.60, 0.62, 0.64))
		_water_mat.set_shader_parameter(&"bank_m", 0.6 if thawed_now else 0.3)
		_water_mat.set_shader_parameter(&"bank_alpha", 0.55 if thawed_now else 0.3)


func _process(_delta: float) -> void:
	thaw_step()
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
