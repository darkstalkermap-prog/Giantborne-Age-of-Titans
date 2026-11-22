class_name DustBurst
extends CPUParticles3D
## A3: a one-shot cloud of ground dust (presentation only; nothing in the simulation reads it): a titan's blow on
## the ground, his footfalls, a plate breaking, the trunk falling from his fist. Soft lit billboards in a dust colour
## that rise, spread and fade; the node frees itself when the cloud has settled. CPU particles, so the Web's
## compatibility renderer draws them as the desktop does.

const DUST := Color(0.58, 0.53, 0.45)
const LIFETIME_S := 2.4

static var _mesh: QuadMesh = null


## A cloud at `at` (the ground under it) of `count` puffs about `size` metres across at their largest, thrown out
## about `speed` m/s. Returns the node (added under `parent`, top level), or null without a parent in the tree.
static func puff(parent: Node, at: Vector3, size := 4.0, count := 18, speed := 6.0, color := DUST) -> DustBurst:
	if parent == null or not parent.is_inside_tree():
		return null
	var d := DustBurst.new()
	d.name = "DustBurst"
	d.top_level = true
	d.setup(size, count, speed, color)
	parent.add_child(d)
	d.global_position = at
	d.emitting = true
	return d


func setup(size: float, count: int, speed: float, color: Color) -> void:
	one_shot = true
	explosiveness = 0.92
	amount = maxi(count, 1)
	lifetime = LIFETIME_S
	local_coords = false
	mesh = _quad()
	emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	emission_sphere_radius = size * 0.25
	direction = Vector3.UP
	spread = 80.0
	flatness = 0.55
	initial_velocity_min = speed * 0.45
	initial_velocity_max = speed
	gravity = Vector3(0.0, -1.2, 0.0)
	damping_min = speed * 0.5
	damping_max = speed * 0.8
	angle_min = 0.0
	angle_max = 360.0
	scale_amount_min = size * 0.35
	scale_amount_max = size * 0.6
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.45))
	grow.add_point(Vector2(0.4, 0.9))
	grow.add_point(Vector2(1.0, 1.0))
	scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.55))
	ramp.set_color(1, Color(color, 0.0))
	ramp.add_point(0.35, Color(color, 0.4))
	color_ramp = ramp
	finished.connect(queue_free)


static func _quad() -> QuadMesh:
	if _mesh != null:
		return _mesh
	_mesh = QuadMesh.new()
	_mesh.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_disc()
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.disable_receive_shadows = true
	_mesh.material = m
	return _mesh


## A soft round puff: a radial fall-off with a little lumpy noise (made once, 32 px).
static func _soft_disc() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var lump := 0.12 * sin(5.0 * atan2(v, u) + 1.3) * r
			var a := clampf(1.0 - smoothstep(0.35, 1.0, r + lump), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
