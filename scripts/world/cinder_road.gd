class_name CinderRoad
extends Node3D
## E2: the Cinder Titan's burned road across the Ashfell (tools/world/kinds/cinder_road.gd places it): presentation only,
## nothing in the simulation reads it.
##   * a ribbon of charred ground and ash `width_m` wide draped over the terrain along `points` (cinder_ground.gdshader:
##     the char, the ash, embers glowing in it - brighter toward the road's head, where he stands - its edges ragged);
##   * `spots` ([x, z, r]) of burnt ground round it: the villages he passed, the hollow he stands in (CinderFx discs);
##   * `fires` flames burning along it and in the spots (CinderFx: one MultiMesh) - until `cooled_flag` is set (his fall):
##     then they sink over COOL_S and the embers go dark; the char stays.
## The ground is the world's (WorldRoot.height_at): what is not loaded yet is drawn when its chunk is.

const SHADER := "res://assets/shaders/cinder_ground.gdshader"
const STEP_M := 6.0
const ACROSS := 8
const LIFT_M := 0.3
const COOL_S := 8.0
const GROUP := "cinder_road"

@export var road_id := ""
@export var points := PackedVector2Array()
@export var spots: Array = []
@export var width_m := 40.0
@export var fires := 40
@export var cooled_flag := ""
## E2: the houses he burned: [x, z, yaw degrees, width, depth] - stubs of charred stone wall, broken, a roof-beam fallen
## across them, made here (CinderGear) and drawn with his slag's shader at a dull heat (their embers go out with his fire).
@export var ruins: Array = []

var fx: CinderFx = null
var ribbon: MeshInstance3D = null
var ruin_mesh: MeshInstance3D = null
var _ruin_mat: ShaderMaterial = null
var _mat: ShaderMaterial = null
var _flames: Array = []      # [slot, world point, height]
var _discs: Array = []       # [slot, world point, radius, seed]
var _missing := true
var _cool := 0.0             # 0 burning .. 1 out
var _built_fx := false
## Tests and stats: the ribbon's quads drawn, the flames lit.
var quads := 0
var flames_lit := 0


func _ready() -> void:
	add_to_group(GROUP)
	_cool = 1.0 if cooled() else 0.0
	if not _draws():
		return
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_mat.set_shader_parameter(&"disc", false)
	_mat.render_priority = -2   # (under the telegraphs' warnings and every other see-through thing on the ground)
	fx = CinderFx.new(maxi(fires, 1), maxi(spots.size(), 1))
	fx.name = "Fire"
	add_child(fx)
	_build()
	Events.flag_changed.connect(_on_flag_changed)


func _exit_tree() -> void:
	if Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.disconnect(_on_chunk_loaded)
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)


static func _draws() -> bool:
	return DisplayServer.get_name() != "headless" or OS.get_cmdline_user_args().has("--skin")


func cooled() -> bool:
	return cooled_flag != "" and bool(WorldState.get_flag(cooled_flag, false))


func _on_flag_changed(_tick: int, flag_id: String, _value: Variant) -> void:
	if flag_id == cooled_flag:
		set_process(true)


func _on_chunk_loaded(_chunk_id: String) -> void:
	_build()


func _world() -> WorldRoot:
	return get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) as WorldRoot if is_inside_tree() else null


func _ground(p: Vector2) -> float:
	var w := _world()
	if w == null:
		return 0.0 if get_tree() != null and get_tree().get_first_node_in_group(WorldRoot.WORLD_GROUP) == null else NAN
	return w.height_at(to_global(Vector3(p.x, 0.0, p.y)))


## The ribbon (what of it stands on loaded ground), the spots' discs and the fires, once their ground is there.
func _build() -> void:
	_missing = false
	_build_ribbon()
	if not _built_fx:
		_build_fx()
	if ruin_mesh == null and not ruins.is_empty():
		_build_ruins()
	if _missing and not Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.connect(_on_chunk_loaded)
	elif not _missing and Events.world_chunk_loaded.is_connected(_on_chunk_loaded):
		Events.world_chunk_loaded.disconnect(_on_chunk_loaded)
	_show_cool()


func _build_ribbon() -> void:
	if points.size() < 2:
		return
	# the centre line resampled every STEP_M, each with its side direction
	var line: Array = []
	var total := 0.0
	for i in points.size() - 1:
		total += points[i].distance_to(points[i + 1])
	var along := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var seg := a.distance_to(b)
		var n := maxi(1, int(ceil(seg / STEP_M)))
		var last := 1 if i == points.size() - 2 else 0
		for k in n + last:
			var t := float(k) / float(n)
			line.append([a.lerp(b, t), (b - a).normalized(), along + seg * t])
		along += seg
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows: Array = []
	for r: Array in line:
		var c: Vector2 = r[0]
		var d: Vector2 = r[1]
		var side := Vector2(-d.y, d.x)
		var row: Array = []
		for k in ACROSS + 1:
			var u := float(k) / float(ACROSS)
			# the edges wander a little (the fire spread unevenly)
			var wob := 1.0 + 0.18 * sin(float(r[2]) * 0.031 + u * 5.0) + 0.1 * sin(float(r[2]) * 0.11)
			var q := c + side * (u - 0.5) * width_m * wob
			var y := _ground(q)
			row.append([q, y, u, float(r[2]) / maxf(total, 1.0)])
			if is_nan(y):
				_missing = true
		rows.append(row)
	quads = 0
	for i in rows.size() - 1:
		for k in ACROSS:
			var v := [rows[i][k], rows[i][k + 1], rows[i + 1][k + 1], rows[i + 1][k]]
			var skip := false
			for e: Array in v:
				if is_nan(float(e[1])):
					skip = true
			if skip:
				continue
			for idx: int in [0, 2, 1, 0, 3, 2]:
				var e: Array = v[idx]
				var q: Vector2 = e[0]
				st.set_color(Color(1, 1, 1, float(e[3])))
				st.set_uv(Vector2(float(e[2]), float(e[3]) * 1000.0))
				st.add_vertex(Vector3(q.x, float(e[1]) + LIFT_M, q.y))
			quads += 1
	if quads == 0:
		return
	st.generate_normals()
	if ribbon == null:
		ribbon = MeshInstance3D.new()
		ribbon.name = "Ribbon"
		ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ribbon.material_override = _mat
		add_child(ribbon)
	ribbon.mesh = st.commit()


func _build_fx() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(road_id)
	var places: Array = []
	for s: Variant in spots:
		var a := s as Array
		places.append([Vector2(float(a[0]), float(a[1])), float(a[2])])
	for i in points.size() - 1:
		places.append([points[i].lerp(points[i + 1], 0.5), width_m * 0.4])
	# the spots' char first (it waits for no fire)
	for s: Variant in spots:
		var a := s as Array
		var c := Vector2(float(a[0]), float(a[1]))
		var y := _ground(c)
		if is_nan(y):
			return
		_discs.append([c, y, float(a[2]), rng.randf()])
	var lit: Array = []
	for f in fires:
		var pl: Array = places[f % places.size()]
		var c: Vector2 = pl[0]
		var r := float(pl[1]) * sqrt(rng.randf())
		var ang := rng.randf() * TAU
		var q := c + Vector2(cos(ang), sin(ang)) * r
		var y := _ground(q)
		if is_nan(y):
			return
		lit.append([q, y, rng.randf_range(5.0, 13.0), rng.randf()])
	_built_fx = true
	for d: Array in _discs:
		var w := to_global(Vector3((d[0] as Vector2).x, float(d[1]), (d[0] as Vector2).y))
		d.append(fx.add_disc(w, float(d[2]), float(d[3]), 1.0))
	for l: Array in lit:
		var w := to_global(Vector3((l[0] as Vector2).x, float(l[1]), (l[0] as Vector2).y))
		var slot := fx.add_flame(w, float(l[2]), float(l[2]) * 0.65, float(l[3]), 1.0, 0.5)
		_flames.append([slot, w, float(l[2])])
	flames_lit = _flames.size()


func _build_ruins() -> void:
	var g := CinderGear.new(hash(road_id) + 3)
	var r := g.rng()
	for ru: Variant in ruins:
		var a := ru as Array
		var c := Vector2(float(a[0]), float(a[1]))
		var base := _ground(c)
		if is_nan(base):
			return
		var yaw := deg_to_rad(float(a[2]))
		var w := float(a[3])
		var d := float(a[4])
		var xf := Transform3D(Basis(Vector3.UP, yaw), Vector3(c.x, base - 0.4, c.y))
		# four walls as rows of stones, broken: each stone a lump, the walls' tops ragged, a gap where the door was
		for side in 4:
			var along := w if side % 2 == 0 else d
			var across := d if side % 2 == 0 else w
			var n := int(ceil(along / 1.6))
			for k in n:
				if side == 0 and absi(k - n / 2) <= 0:
					continue
				var t := (float(k) + 0.5) / float(n) - 0.5
				var h := r.randf_range(0.6, 3.6) * (1.0 - 0.5 * absf(t))
				var p := Vector3(t * along, 0.0, across * 0.5)
				p = Basis(Vector3.UP, PI * 0.5 * side) * p
				var rows := maxi(1, int(h / 1.1))
				for row in rows:
					g.lump(p + Vector3(r.randf_range(-0.15, 0.15), 0.55 + 1.05 * row, r.randf_range(-0.15, 0.15)),
						Vector3(0.95, 0.6, 0.7) * r.randf_range(0.8, 1.15), Basis(Vector3.UP, PI * 0.5 * side + r.randf_range(-0.2, 0.2)),
						0.25, 4, 6, xf)
		# a roof-beam fallen across the shell, charred, and a heap of the roof's ash and stones inside
		var b0 := Vector3(-w * 0.45, 0.4, r.randf_range(-d, d) * 0.3)
		var b1 := Vector3(w * 0.45, 2.2, r.randf_range(-d, d) * 0.3)
		g.bar(xf * b0, xf * b1, 0.35, 0.3, 6, 2)
		g.lump(Vector3(0, 0.3, 0), Vector3(w * 0.3, 0.9, d * 0.3), Basis.IDENTITY, 0.35, 5, 8, xf)
	var mesh := g.mesh()
	if mesh == null:
		return
	_ruin_mat = ShaderMaterial.new()
	_ruin_mat.shader = load(CinderModel.SLAG_SHADER)
	var n := load("res://assets/creatures/stoneback_stone_normal.png")
	if n != null:
		_ruin_mat.set_shader_parameter(&"normal_tex", n)
	_ruin_mat.set_shader_parameter(&"cells", 0.7)
	_ruin_mat.set_shader_parameter(&"glow_energy", 1.2)
	_ruin_mat.set_shader_parameter(&"slag_color", Color(0.11, 0.1, 0.095))
	_ruin_mat.set_shader_parameter(&"cooled_color", Color(0.2, 0.19, 0.18))
	ruin_mesh = MeshInstance3D.new()
	ruin_mesh.name = "Ruins"
	ruin_mesh.mesh = mesh
	ruin_mesh.material_override = _ruin_mat
	add_child(ruin_mesh)


func _process(delta: float) -> void:
	var want := 1.0 if cooled() else 0.0
	if is_equal_approx(_cool, want):
		set_process(false)
		return
	_cool = move_toward(_cool, want, delta / COOL_S)
	_show_cool()


func _show_cool() -> void:
	var burn := 1.0 - _cool
	if _mat != null:
		_mat.set_shader_parameter(&"ember", burn)
	if _ruin_mat != null:
		_ruin_mat.set_shader_parameter(&"heat", 0.25 * burn)
	if fx == null:
		return
	for f: Array in _flames:
		fx.set_flame_strength(int(f[0]), burn)
	for d: Array in _discs:
		if d.size() > 4:
			fx.set_disc(int(d[4]), burn, 1.0)
