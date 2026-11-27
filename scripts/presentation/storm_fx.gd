class_name StormFx
extends Node3D
## D2: the storm's light, short-lived and self-freeing - a lightning bolt from the cloud to the ground (a jagged,
## branching strip of white-blue light, drawn additive and unshaded: never a dark quad), its flash (an omni light that
## blazes and dies), and the shock running out over water (a pale ring spreading on the water's surface). The
## Stormcaller's rig makes them at his strikes; the storm over the Drowned Steps (StormWeather) at its own far strikes.
## Presentation only.

const BOLT_COLOR := Color(0.78, 0.86, 1.0)
const RING_COLOR := Color(0.55, 0.78, 1.0)
const MARK_COLOR := Color(1.0, 0.24, 0.12)

var life := 0.3
var age := 0.0
var kind := "bolt"
var _mat: StandardMaterial3D = null
var _light: OmniLight3D = null
var _ring: MeshInstance3D = null
var _radius := 1.0
var _energy := 6.0


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = color
	m.vertex_color_use_as_albedo = true
	return m


## A bolt from `top` down to `ground` (world), jagged by `seed`, with a branch or two; its flash light. Added under
## `parent` (top level), gone after `life_s`.
static func bolt(parent: Node, top: Vector3, ground: Vector3, seed: int, life_s := 0.32, light_energy := 7.0,
		width := 1.4) -> StormFx:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := StormFx.new()
	fx.name = "StormBolt"
	fx.kind = "bolt"
	fx.life = life_s
	fx.top_level = true
	parent.add_child(fx)
	fx.global_position = ground
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var main := _path(top - ground, Vector3.ZERO, 14, rng, 0.16)
	_strip(st, main, width, Color(1, 1, 1, 1))
	# (its glow: a wide faint strip round the core - added light, no screen reads)
	_strip(st, main, width * 5.0, Color(0.55, 0.6, 0.9, 0.22))
	for b in 2:
		var at := main[rng.randi_range(3, 8)]
		var dir := Vector3(rng.randf_range(-1, 1), -1.2, rng.randf_range(-1, 1)).normalized()
		var end := at + dir * (top - ground).length() * rng.randf_range(0.12, 0.25)
		_strip(st, _path(at, end, 6, rng, 0.2), width * 0.55, Color(1, 1, 1, 0.8))
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	fx._mat = _material(BOLT_COLOR)
	mi.material_override = fx._mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 400.0
	fx.add_child(mi)
	if light_energy > 0.0:
		fx._light = OmniLight3D.new()
		fx._light.light_color = BOLT_COLOR
		fx._light.omni_range = 140.0
		fx._light.light_energy = light_energy
		fx._light.position = Vector3(0.0, 18.0, 0.0)
		fx._energy = light_energy
		fx.add_child(fx._light)
	return fx


## The shock running out over water from `at` to `radius` m (a ring on the surface at `at`'s height), gone after
## `life_s`.
static func shock_ring(parent: Node, at: Vector3, radius: float, life_s := 0.6) -> StormFx:
	if parent == null or not parent.is_inside_tree():
		return null
	var fx := StormFx.new()
	fx.name = "StormShock"
	fx.kind = "ring"
	fx.life = life_s
	fx.top_level = true
	parent.add_child(fx)
	fx.global_position = at + Vector3.UP * 0.12
	fx._radius = radius
	var torus := TorusMesh.new()
	torus.inner_radius = 0.93
	torus.outer_radius = 1.0
	torus.rings = 48
	torus.ring_segments = 4
	fx._ring = MeshInstance3D.new()
	fx._ring.mesh = torus
	fx._mat = _material(RING_COLOR)
	fx._ring.material_override = fx._mat
	fx._ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fx._ring.scale = Vector3(1.0, 0.05, 1.0)
	fx.add_child(fx._ring)
	return fx


## Where a called bolt will strike: a red disc of `radius` on the ground (or the water) at `at` - its rim at once, its
## fill growing from the middle until the strike `life_s` later (as the game's other telegraphs fill). Additive.
static func strike_mark(parent: Node, at: Vector3, radius: float, life_s: float) -> StormFx:
	var fx := shock_ring(parent, at, radius, life_s)
	if fx == null:
		return null
	fx.kind = "mark"
	fx.name = "StormMark"
	fx._mat.albedo_color = Color(MARK_COLOR, 0.8)
	fx._ring.scale = Vector3(radius, 0.05 * radius, radius)
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.02
	disc.radial_segments = 32
	disc.rings = 1
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.mesh = disc
	fill.material_override = _material(MARK_COLOR)
	(fill.material_override as StandardMaterial3D).albedo_color = Color(MARK_COLOR, 0.55)
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fill.scale = Vector3(0.05, 1.0, 0.05)
	fx.add_child(fill)
	return fx


## The water's warning: a pale ring of `radius` on the water at `at` that pulses for `life_s` (a bolt is coming down on
## the water - its shock will reach that far).
static func water_warning(parent: Node, at: Vector3, radius: float, life_s: float) -> StormFx:
	var fx := shock_ring(parent, at, radius, life_s)
	if fx != null:
		fx.kind = "warn"
		fx.name = "StormWarning"
	return fx


static func _path(a: Vector3, b: Vector3, n: int, rng: RandomNumberGenerator, jag: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	var d := b - a
	var L := d.length()
	for i in n + 1:
		var t := float(i) / float(n)
		var p := a + d * t
		if i > 0 and i < n:
			p += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.3, 0.3), rng.randf_range(-1, 1)) * L * jag / sqrt(n)
		out.append(p)
	return out


## Two crossed ribbons along `pts` (seen from any side), `w` wide.
static func _strip(st: SurfaceTool, pts: PackedVector3Array, w: float, c: Color) -> void:
	for side: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var wa := w * (1.0 - 0.5 * float(i) / float(pts.size()))
			var wb := w * (1.0 - 0.5 * float(i + 1) / float(pts.size()))
			var q := [a - side * wa * 0.5, a + side * wa * 0.5, b + side * wb * 0.5, b - side * wb * 0.5]
			for k: int in [0, 1, 2, 0, 2, 3]:
				st.set_color(c)
				st.add_vertex(q[k])


func _process(delta: float) -> void:
	age += delta
	var k := clampf(age / maxf(life, 0.01), 0.0, 1.0)
	if kind == "bolt":
		# (a bolt flickers: two bright pulses, then gone)
		var a := (1.0 - k) * (0.6 + 0.4 * absf(sin(age * 60.0)))
		if _mat != null:
			_mat.albedo_color = Color(BOLT_COLOR, a)
		if _light != null:
			_light.light_energy = _energy * (1.0 - k) * (1.0 - k)
	elif _ring != null and kind == "mark":
		var f := get_node_or_null("Fill") as MeshInstance3D
		if f != null:
			var r := maxf(0.05, _radius * k)
			f.scale = Vector3(r, 1.0, r)
		_mat.albedo_color = Color(MARK_COLOR, 0.55 + 0.4 * absf(sin(age * 9.0)) * k)
	elif _ring != null and kind == "warn":
		_ring.scale = Vector3(_radius, 0.05 * _radius, _radius)
		_mat.albedo_color = Color(RING_COLOR, 0.25 + 0.35 * absf(sin(age * 7.0)) * (0.4 + 0.6 * k))
	elif _ring != null:
		var r := lerpf(_radius * 0.15, _radius, sqrt(k))
		_ring.scale = Vector3(r, 0.05 * r, r)
		_mat.albedo_color = Color(RING_COLOR, (1.0 - k) * 0.9)
	if age >= life:
		queue_free()
