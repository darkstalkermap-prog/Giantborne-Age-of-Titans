extends RefCounted
## Element kind "settlement_fire" (C4): a fire's light where folk keep one - a hall's hearth seen through its door, a
## brazier at a gate, a beacon's basket: an emissive bed of embers and tongues of flame (one mesh, the shared fire
## material) and, with `light`, an OmniLight3D of `range` metres that flickers (scripts/presentation/settlement_fire.gd)
## and fades out beyond `light_far_m` (the Web's draw calls: a light adds a pass to what it touches). `size` the
## flames' height, `embers_m` the bed's width, `glow` [w, h] a doorway's firelight behind them. FLAG_WRAP: a flagged fire (lit once a tier's life has come) is built
## whole inside its FlagVisibility, so hidden it neither shows nor lights.

const L := preload("res://tools/world/layout.gd")
const SCRIPTED := true
const FLAG_WRAP := true
const S_FIRE := "res://scripts/presentation/settlement_fire.gd"
const FIRE_MAT := "res://assets/materials/settlement_fire.tres"


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.name = str(el.id).validate_node_name()
	var h := float(el.get("size", 1.6))
	var w := float(el.get("embers_m", h * 0.9))
	var light := bool(el.get("light", true))
	kit.scripted(n, S_FIRE, {"flicker": light, "base_energy": float(el.get("energy", 2.2))})
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242 + str(el.id).hash() % 1000
	# the bed of embers: a low ring of lumps
	for k in 7:
		var a := TAU * k / 7.0 + rng.randf_range(-0.2, 0.2)
		var r := w * 0.32 * rng.randf_range(0.6, 1.0)
		_lump(st, Vector3(cos(a) * r, 0.08, sin(a) * r), w * 0.16, w * 0.09, Color(0.85, 0.32, 0.08), rng)
	# tongues of flame: crossed tapering blades
	for k in 4:
		var a := PI * k / 4.0 + rng.randf_range(-0.15, 0.15)
		var fh := h * rng.randf_range(0.65, 1.0)
		_blade(st, a, w * 0.42, fh, Color(1.0, 0.55, 0.16) if k % 2 == 0 else Color(1.0, 0.72, 0.3))
	# a doorway's firelight: a warm panel behind the flames (`glow` [w, h], facing local +z), brighter at its foot
	var g: Variant = el.get("glow")
	if typeof(g) == TYPE_ARRAY and (g as Array).size() == 2:
		var gw := float(g[0]) * 0.5
		var gh := float(g[1])
		var lo := Color(1.0, 0.55, 0.18)
		var hi := Color(0.55, 0.22, 0.07)
		var z := -0.4
		for tri: Array in [[Vector3(-gw, 0, z), lo, Vector3(gw, 0, z), lo, Vector3(gw, gh, z), hi],
				[Vector3(-gw, 0, z), lo, Vector3(gw, gh, z), hi, Vector3(-gw, gh, z), hi]]:
			for k in 3:
				st.set_color(tri[k * 2 + 1])
				st.add_vertex(tri[k * 2])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Flames"
	mi.mesh = st.commit()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if ResourceLoader.exists(FIRE_MAT):
		mi.material_override = load(FIRE_MAT)
	mi.visibility_range_end = float(el.get("far_m", 700.0))
	n.add_child(mi)
	if light:
		var l := OmniLight3D.new()
		l.name = "Light"
		l.position = Vector3(0, h * 0.6, 0)
		l.light_color = Color(1.0, 0.62, 0.32)
		l.light_energy = float(el.get("energy", 2.2))
		l.omni_range = float(el.get("range", 14.0))
		l.omni_attenuation = 1.4
		l.shadow_enabled = false
		l.distance_fade_enabled = true
		l.distance_fade_begin = float(el.get("light_far_m", 160.0))
		l.distance_fade_length = 40.0
		n.add_child(l)
	return n


static func _lump(st: SurfaceTool, c: Vector3, r: float, h: float, col: Color, rng: RandomNumberGenerator) -> void:
	var ring: Array = []
	for i in 5:
		var a := TAU * i / 5.0
		ring.append(c + Vector3(cos(a) * r * rng.randf_range(0.7, 1.1), 0.0, sin(a) * r * rng.randf_range(0.7, 1.1)))
	var top := c + Vector3(0, h, 0)
	for i in 5:
		st.set_color(col)
		st.add_vertex(ring[i])
		st.set_color(col.lightened(0.2))
		st.add_vertex(top)
		st.set_color(col)
		st.add_vertex(ring[(i + 1) % 5])


static func _blade(st: SurfaceTool, a: float, half_w: float, h: float, col: Color) -> void:
	var d := Vector3(cos(a), 0, sin(a)) * half_w
	var p0 := -d
	var p1 := d
	var mid := Vector3(0, h * 0.45, 0)
	var top := Vector3(0, h, 0)
	for pair: Array in [[p0, p1, mid], [p1, p0, mid]]:
		st.set_color(col)
		st.add_vertex(pair[0])
		st.set_color(col)
		st.add_vertex(pair[1])
		st.set_color(col.lightened(0.25))
		st.add_vertex(pair[2])
	for pair: Array in [[p0 * 0.5 + mid * 0.6, mid, top], [mid, p1 * 0.5 + mid * 0.6, top], [mid, p0 * 0.5 + mid * 0.6, top],
			[p1 * 0.5 + mid * 0.6, mid, top]]:
		st.set_color(col.lightened(0.15))
		st.add_vertex(pair[0])
		st.set_color(col.lightened(0.15))
		st.add_vertex(pair[1])
		st.set_color(Color(1.0, 0.9, 0.6))
		st.add_vertex(pair[2])
