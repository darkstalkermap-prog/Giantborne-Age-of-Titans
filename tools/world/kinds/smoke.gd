extends RefCounted
## Element kind "smoke" (C1b): a column of smoke rising from a fire and leaning off downwind - a camp's fires seen
## from afar (Last Hearth). A CPUParticles3D (no script: soft lit puffs, as DustBurst draws its dust, so the Web's
## compatibility renderer draws them as the desktop does) in its chunk's props sub-scene, a few seconds risen when the
## chunk streams in (preprocess 3 s). `size` [the puffs' greatest width, the column's rise speed m/s], `wind` [x, z] m/s².
## Not in the scenery group: it shows as long as its chunk is loaded. Presentation only.

const SCRIPTED := true


static func parts(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func solids(_el: Dictionary, _ctx: Dictionary) -> Array:
	return []


static func build(_kit: SceneKit, el: Dictionary, _ctx: Dictionary) -> Node3D:
	var s: Array = el.get("size", [9.0, 2.6])
	var wind: Array = el.get("wind", [0.5, 0.2])
	var width := float(s[0])
	var rise := float(s[1])
	var p := CPUParticles3D.new()
	p.name = str(el.get("id", "smoke")).validate_node_name()
	p.amount = int(el.get("puffs", 16))
	p.lifetime = float(el.get("lifetime_s", 10.0))
	# (a few seconds risen when its chunk streams in: a whole lifetime's preprocess cost a chunk's props step 35 ms on
	# the Web)
	p.preprocess = minf(3.0, p.lifetime)
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.6
	p.direction = Vector3.UP
	p.spread = 6.0
	p.initial_velocity_min = rise * 0.8
	p.initial_velocity_max = rise * 1.2
	p.gravity = Vector3(float(wind[0]), 0.05, float(wind[1]))
	p.damping_min = 0.08
	p.damping_max = 0.16
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.angular_velocity_min = -8.0
	p.angular_velocity_max = 8.0
	# (the quad is the puff's full width: the compatibility renderer leaves a CPU particle's scale out, DustBurst)
	p.scale_amount_min = 0.75
	p.scale_amount_max = 1.0
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.18))
	grow.add_point(Vector2(0.35, 0.55))
	grow.add_point(Vector2(1.0, 1.0))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.6, 0.59, 0.58, 0.0))
	ramp.set_color(1, Color(0.82, 0.83, 0.86, 0.0))
	ramp.add_point(0.08, Color(0.58, 0.57, 0.56, 0.55))
	ramp.add_point(0.5, Color(0.74, 0.75, 0.78, 0.36))
	p.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * width
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_puff()
	m.roughness = 1.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.disable_receive_shadows = true
	quad.material = m
	p.mesh = quad
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


## A soft, lumpy puff (32 px; DustBurst's disc with more lumps).
static func _soft_puff() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var r := sqrt(u * u + v * v)
			var lump := 0.14 * sin(4.0 * atan2(v, u) + 0.7) * r + 0.08 * sin(9.0 * atan2(v, u) + 2.1) * r
			var a := clampf(1.0 - smoothstep(0.25, 1.0, r + lump), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a))
	return ImageTexture.create_from_image(img)
