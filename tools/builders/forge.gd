extends RefCounted
## Builder: the forge of P12 (plan §2.12, §3.14 design 6): scenes/world/forge.tscn, an anvil and a
## hearth of boxes sized for a giant, with the Forge interactable on the root.
##   Forge (Node3D, Forge)        world_id / display_name / requires_flags / requires_flag_values
##                                are set per placed instance (the Valley: valley.village.forge
##                                with the help outcomes, valley.ruins.giantforge open)
##     Hearth (StaticBody3D, WORLD)  a stone hearth with a chimney, 3 m behind the root
##       Fire                         the glowing coals (visual only)
##     Anvil (StaticBody3D, WORLD)   an iron anvil on a stone block, 2 m in front of the hearth
## The root is where the giant interacts from (radius_m 4.5 from its capsule edge); the forge faces
## -Z (the anvil side).

const S_FORGE := "res://scripts/world/forge.gd"
const PATH := "res://scenes/world/forge.tscn"
## C3 (decision C3-6): the looks every forge and every waystone wears (their scripts put them on at run time, over the
## old boxes, wherever they stand: the Valley, the world's chunks, the test levels).
const SMITHY_PATH := "res://scenes/world/smithy.tscn"
const MONUMENT_PATH := "res://scenes/world/waystone_monument.tscn"
const S_FORGE_LOOK := "res://scripts/presentation/forge_look.gd"
const S_WAYSTONE_LOOK := "res://scripts/presentation/waystone_look.gd"
const LANDMARK_SHADER := "res://assets/shaders/landmark.gdshader"
const BEAM_SHADER := "res://assets/shaders/landmark_beam.gdshader"
const SMOKE := preload("res://tools/world/kinds/smoke.gd")
## C3b (decision C3b-5): how far a lit forge's smoke column draws, and how far a waystone's beam (known: bright; open,
## not yet reached: a faint grey column) draws.
const SMOKE_FAR_M := 900.0
const BEAM_FAR_M := 2400.0
const LM := preload("res://tools/landmark_mesh.gd")


static func build_all(kit: SceneKit) -> void:
	_materials(kit)
	# P17b (draw calls): the hearth, the fire and the anvil as one mesh per material
	# (SceneKit.merge_meshes); the collision shapes stay on their static bodies.
	var forge := build_forge(kit)
	kit.merge_meshes(forge as Node3D, PackedStringArray(), PackedStringArray(["scenery"]))
	kit.save(forge, PATH)
	kit.save(build_smithy(), SMITHY_PATH)
	kit.save(build_monument(), MONUMENT_PATH)


static func _materials(kit: SceneKit) -> void:
	kit.add_material("forge_stone", Color(0.30, 0.29, 0.28), 0.95)
	kit.add_material("forge_iron", Color(0.20, 0.21, 0.23), 0.45, 0.6)
	var fire := kit.add_material("forge_fire", Color(1.0, 0.45, 0.12), 0.4)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.42, 0.10)
	fire.emission_energy_multiplier = 2.0
	if kit.out_root == "":
		ResourceSaver.save(fire, "%s/forge_fire.tres" % SceneKit.MAT_DIR, ResourceSaver.FLAG_CHANGE_PATH)


static func build_forge(kit: SceneKit) -> Node:
	var root := kit.n3("Forge")
	kit.scripted(root, S_FORGE, {"world_id": "valley.ruins.giantforge", "display_name": "Giantforge",
		"prompt": "Reforge", "radius_m": 4.5, "priority": 45})
	var hearth := StaticBody3D.new()
	hearth.name = "Hearth"
	hearth.position = Vector3(0, 0, 3.0)
	hearth.collision_layer = SceneKit.L_WORLD
	hearth.collision_mask = 0
	hearth.add_child(_shape("Base", Vector3(4.2, 1.6, 3.0), Vector3(0, 0.8, 0)))
	hearth.add_child(_shape("Chimney", Vector3(1.8, 4.8, 1.8), Vector3(0, 4.0, 0.5)))
	hearth.add_child(kit.box("BaseMesh", Vector3(4.2, 1.6, 3.0), Vector3(0, 0.8, 0), "forge_stone"))
	hearth.add_child(kit.box("Lip", Vector3(4.4, 0.25, 3.2), Vector3(0, 1.72, 0), "forge_stone"))
	hearth.add_child(kit.box("ChimneyMesh", Vector3(1.8, 4.8, 1.8), Vector3(0, 4.0, 0.5), "forge_stone"))
	var fire := kit.n3("Fire", Vector3(0, 1.9, -0.3))
	fire.add_child(kit.box("Coals", Vector3(2.6, 0.3, 1.6), Vector3.ZERO, "forge_fire"))
	fire.add_child(kit.box("Flame", Vector3(1.2, 0.8, 0.6), Vector3(0, 0.5, 0.1), "forge_fire"))
	hearth.add_child(fire)
	root.add_child(hearth)
	var anvil := StaticBody3D.new()
	anvil.name = "Anvil"
	anvil.position = Vector3(0, 0, 0.8)
	anvil.collision_layer = SceneKit.L_WORLD
	anvil.collision_mask = 0
	anvil.add_child(_shape("Block", Vector3(1.4, 1.1, 1.0), Vector3(0, 0.55, 0)))
	anvil.add_child(_shape("Top", Vector3(2.4, 0.5, 0.9), Vector3(0, 1.35, 0)))
	anvil.add_child(kit.box("BlockMesh", Vector3(1.4, 1.1, 1.0), Vector3(0, 0.55, 0), "forge_stone"))
	anvil.add_child(kit.box("Waist", Vector3(0.9, 0.3, 0.7), Vector3(0, 1.0, 0), "forge_iron"))
	anvil.add_child(kit.box("TopMesh", Vector3(2.4, 0.5, 0.9), Vector3(0, 1.35, 0), "forge_iron"))
	var horn := kit.cyl("Horn", 0.05, 0.42, 1.1, Vector3(1.65, 1.35, 0), "forge_iron")
	horn.rotation_degrees = Vector3(0, 0, 90)
	anvil.add_child(horn)
	root.add_child(anvil)
	return root


static func _shape(node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.name = node_name
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	return cs


# --------------------------------------------------------------------------- C3: the smithy and the waystone's monument

static func _landmark_material(glow_color: Color, glow: float, flicker: float, pulse: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(LANDMARK_SHADER)
	m.set_shader_parameter("glow_color", glow_color)
	m.set_shader_parameter("glow", glow)
	m.set_shader_parameter("flicker", flicker)
	m.set_shader_parameter("pulse", pulse)
	return m


static func _box_shape(node_name: String, size: Vector3, pos: Vector3) -> CollisionShape3D:
	return _shape(node_name, size, pos)


## C3: a giant's smithy, in forge.tscn's frame (the giant works it from the root, facing -Z; the hearth behind at
## +z): a drystone hearth with a fire-bed of glowing coals and flames under a hood, its coursed chimney rising 13 m
## with smoke from its crown, the bellows of boards and hide beside it, an anvil on an oak stump, a quench trough, a
## rack of hammers and tongs, a heap of charcoal and bar iron, a low wall behind and a lean-to of boards on posts over
## the anvil. One mesh of the landmark material (stone, oak, iron, hide and the fire in its vertex colours), its light
## (a fire's orange, no shadows, fading out beyond 45 m), the smoke and the embers. C3b (decision C3b-5): the smoke a
## soft pale column drawn out to SMOKE_FAR_M (a lit forge is found by it from far off; beyond, the HUD's far mark),
## and solids of its own (Body: the chimney above the old hearth, the back wall, the trough, the lean-to's posts; the old forge's
## hearth and anvil bodies stay). ForgeLook lights or quenches it.
static func build_smithy() -> Node3D:
	var root := Node3D.new()
	root.name = "Smithy"
	root.set_script(load(S_FORGE_LOOK))
	var k := LM.new(310001)
	var stone := LM.col(Color(0.46, 0.43, 0.39), LM.STONE)
	var dark_stone := LM.col(Color(0.34, 0.32, 0.29), LM.STONE)
	var course := LM.col(Color(0.42, 0.40, 0.36), LM.STONE)
	var soot := LM.col(Color(0.16, 0.15, 0.14), LM.STONE)
	var oak := LM.col(Color(0.42, 0.30, 0.18), LM.WOOD)
	var old_oak := LM.col(Color(0.33, 0.25, 0.17), LM.WOOD)
	var iron := LM.col(Color(0.22, 0.22, 0.24), LM.IRON)
	var hide := LM.col(Color(0.45, 0.31, 0.20), LM.LEATHER)
	var coal := LM.col(Color(0.10, 0.09, 0.09), LM.LEATHER)
	var water := LM.col(Color(0.10, 0.13, 0.15), LM.LEATHER)
	var fire := LM.col(Color(1.0, 0.45, 0.12), LM.GLOW)
	# the hearth: two courses of rough stones round a fire-bed
	k.block(Vector3(0, 0, 3.2), Vector3(4.8, 0.8, 3.2), dark_stone, 0.05)
	for i in 5:
		k.block(Vector3(-1.9 + i * 0.95, 0.8, 4.45), Vector3(0.92, 0.75, 0.7), stone, 0.12, 0.05 * i)
	for side: float in [-1.0, 1.0]:
		for j in 3:
			k.block(Vector3(side * 2.05, 0.8, 2.15 + j * 0.95), Vector3(0.75, 0.75, 0.9), stone, 0.12, 0.1 * j)
	k.block(Vector3(0, 0.8, 1.75), Vector3(4.6, 0.35, 0.55), stone, 0.06)
	k.block(Vector3(0, 0.8, 3.0), Vector3(3.2, 0.25, 2.0), soot, 0.04)
	# the fire-bed: coals and flames
	for i in 9:
		var x := -1.2 + 0.3 * float(i)
		k.block(Vector3(x, 1.02, 2.6 + 0.25 * sin(i * 1.7)), Vector3(0.36, 0.18, 0.5), fire, 0.3)
	for f: Array in [[-0.6, 0.9, 0.35], [0.1, 1.25, 0.42], [0.7, 0.85, 0.33], [-0.2, 0.7, 0.3], [0.45, 1.0, 0.28]]:
		k.cone(Vector3(float(f[0]), 1.15, 2.75), float(f[2]), float(f[1]), fire, 5, Vector3(0.05, 0, 0.1))
	# the hood and the chimney, course on course
	k.prism(Vector3(0, 1.55, 3.55), Vector2(2.4, 1.6), Vector2(1.2, 1.0), 1.9, stone, 4, 2, 0.06, PI * 0.25)
	var y := 3.45
	for c in 8:
		var t := float(c) / 8.0
		var r := lerpf(1.0, 0.72, t)
		k.prism(Vector3(0.02 * sin(c * 2.1), y, 3.75), Vector2(r, r * 0.9), Vector2(r * 0.97, r * 0.88), 1.2,
			stone if c % 2 == 0 else course, 6, 1, 0.07, 0.3 * c)
		y += 1.2
	k.prism(Vector3(0, y, 3.75), Vector2(0.86, 0.8), Vector2(0.82, 0.76), 0.35, soot, 6, 1, 0.05)
	# the low wall behind
	for i in 7:
		k.block(Vector3(-3.3 + i * 1.1, 0, 5.4), Vector3(1.05, 1.3 + 0.35 * sin(i * 2.3), 0.8), stone, 0.14, 0.08 * i)
	# the bellows beside the hearth: two boards, the hide between, a nozzle into the fire
	k.slab([Vector3(-3.9, 1.35, 2.2), Vector3(-2.7, 1.35, 2.2), Vector3(-2.7, 1.35, 3.6), Vector3(-3.9, 1.35, 3.6)], 0.12, oak)
	k.prism(Vector3(-3.3, 0.85, 2.9), Vector2(0.62, 0.72), Vector2(0.6, 0.7), 0.45, hide, 8, 1, 0.08)
	k.slab([Vector3(-3.9, 0.85, 2.2), Vector3(-2.7, 0.85, 2.2), Vector3(-2.7, 0.85, 3.6), Vector3(-3.9, 0.85, 3.6)], 0.12, oak)
	k.log_between(Vector3(-2.7, 1.05, 2.9), Vector3(-2.15, 1.05, 2.9), 0.1, iron, 6)
	k.log_between(Vector3(-3.3, 0.0, 2.3), Vector3(-3.3, 0.85, 2.3), 0.09, old_oak, 6)
	k.log_between(Vector3(-3.3, 0.0, 3.5), Vector3(-3.3, 0.85, 3.5), 0.09, old_oak, 6)
	k.log_between(Vector3(-3.9, 1.45, 2.9), Vector3(-4.6, 2.2, 2.9), 0.07, oak, 6)
	# the anvil on its stump
	k.log_between(Vector3(0, 0, 0.6), Vector3(0, 0.82, 0.6), 0.55, old_oak, 10, 0.08)
	k.block(Vector3(0, 0.82, 0.6), Vector3(0.75, 0.32, 0.55), iron, 0.02)
	k.block(Vector3(0, 1.14, 0.6), Vector3(0.5, 0.22, 0.38), iron, 0.02)
	k.block(Vector3(-0.1, 1.36, 0.6), Vector3(1.55, 0.3, 0.55), iron, 0.015)
	k.log_between(Vector3(0.68, 1.51, 0.6), Vector3(1.25, 1.51, 0.6), 0.13, iron, 8, 0.02)
	k.log_between(Vector3(1.25, 1.51, 0.6), Vector3(1.5, 1.53, 0.6), 0.06, iron, 6, 0.02)
	# a hammer on the anvil, a bar heating in the coals
	k.log_between(Vector3(-0.5, 1.7, 0.45), Vector3(0.2, 1.7, 0.95), 0.04, oak, 6)
	k.block(Vector3(0.2, 1.62, 0.95), Vector3(0.22, 0.16, 0.3), iron, 0.02, 0.6)
	k.log_between(Vector3(0.3, 1.2, 1.5), Vector3(0.0, 1.12, 2.5), 0.05, iron, 6)
	# the quench trough
	k.block(Vector3(2.7, 0, 1.0), Vector3(1.7, 0.7, 0.85), oak, 0.03)
	k.slab([Vector3(1.95, 0.66, 0.67), Vector3(3.45, 0.66, 0.67), Vector3(3.45, 0.66, 1.33), Vector3(1.95, 0.66, 1.33)], 0.02, water)
	# the tool rack: posts, a bar, hammers and tongs hanging
	k.log_between(Vector3(3.2, 0, 3.0), Vector3(3.2, 2.2, 3.0), 0.09, old_oak, 6)
	k.log_between(Vector3(4.3, 0, 3.0), Vector3(4.3, 2.2, 3.0), 0.09, old_oak, 6)
	k.log_between(Vector3(3.1, 2.1, 3.0), Vector3(4.4, 2.1, 3.0), 0.07, oak, 6)
	for t in 4:
		var x := 3.4 + 0.27 * t
		k.log_between(Vector3(x, 2.05, 3.0), Vector3(x + 0.03, 1.25, 3.0), 0.03, oak if t % 2 == 0 else iron, 5)
		if t % 2 == 0:
			k.block(Vector3(x + 0.03, 1.1, 3.0), Vector3(0.18, 0.15, 0.12), iron, 0.02)
	# the charcoal heap and the bar iron
	k.cone(Vector3(-2.8, 0, 4.4), 0.95, 0.75, coal, 9, Vector3.ZERO, 0.25)
	for b in 4:
		k.block(Vector3(-2.3 + 0.12 * b, 0.12 * b, -0.3 + 0.05 * b), Vector3(0.9, 0.11, 0.16), iron, 0.02, 0.2 * b)
	# the lean-to over the anvil: four posts, two beams, boards
	for p: Vector2 in [Vector2(-2.6, -1.4), Vector2(2.6, -1.4), Vector2(-2.6, 1.9), Vector2(2.6, 1.9)]:
		k.log_between(Vector3(p.x, 0, p.y), Vector3(p.x, 3.3 if p.y < 0.0 else 3.9, p.y), 0.13, old_oak, 7)
	k.log_between(Vector3(-2.9, 3.3, -1.4), Vector3(2.9, 3.3, -1.4), 0.12, oak, 7)
	k.log_between(Vector3(-2.9, 3.9, 1.9), Vector3(2.9, 3.9, 1.9), 0.12, oak, 7)
	for i in 6:
		var x0 := -3.0 + i * 1.0
		k.slab([Vector3(x0, 3.45, -1.75), Vector3(x0 + 1.02, 3.45, -1.75), Vector3(x0 + 1.02, 4.05, 2.15),
			Vector3(x0, 4.05, 2.15)], 0.08, oak if i % 2 == 0 else old_oak)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = k.commit()
	mesh.material_override = _landmark_material(Color(1.0, 0.5, 0.16), 2.6, 0.8, 0.0)
	mesh.visibility_range_end = 240.0
	root.add_child(mesh)
	var light := OmniLight3D.new()
	light.name = "Light"
	light.position = Vector3(0, 1.9, 2.2)
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 2.2
	light.omni_range = 9.0
	light.shadow_enabled = false
	# (its light only near: a lit forge far off is its smoke and its glow, not a light pass on everything round it)
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 15.0
	root.add_child(light)
	var smoke := SMOKE.build(null, {"id": "Smoke", "size": [6.0, 3.0], "wind": [0.3, 0.12], "puffs": 22,
		"lifetime_s": 16.0}, {}) as CPUParticles3D
	smoke.position = Vector3(0, y + 0.5, 3.75)
	smoke.visibility_range_end = SMOKE_FAR_M
	# (the forge's smoke lit by its own colours: the sun behind a dark puff read as soot stars from the hearth side;
	# C3b: a soft round puff, pale and thin - the lumpy grey puffs read as dark blots against the sky)
	var sm2 := ((smoke.mesh as QuadMesh).material as StandardMaterial3D)
	sm2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm2.albedo_texture = _soft_round_puff()
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.86, 0.85, 0.83, 0.0))
	ramp.set_color(1, Color(0.90, 0.91, 0.93, 0.0))
	ramp.add_point(0.06, Color(0.80, 0.78, 0.75, 0.42))
	ramp.add_point(0.35, Color(0.86, 0.86, 0.86, 0.3))
	ramp.add_point(0.7, Color(0.90, 0.91, 0.93, 0.16))
	smoke.color_ramp = ramp
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.2))
	grow.add_point(Vector2(0.3, 0.6))
	grow.add_point(Vector2(1.0, 1.6))
	smoke.scale_amount_curve = grow
	root.add_child(smoke)
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	body.add_child(_box_shape("Chimney", Vector3(1.8, 10.0, 1.8), Vector3(0, 8.4, 3.75)))
	body.add_child(_box_shape("Wall", Vector3(7.8, 1.4, 0.8), Vector3(0, 0.7, 5.4)))
	body.add_child(_box_shape("Trough", Vector3(1.7, 0.7, 0.85), Vector3(2.7, 0.35, 1.0)))
	for i in 4:
		var pp: Vector2 = [Vector2(-2.6, -1.4), Vector2(2.6, -1.4), Vector2(-2.6, 1.9), Vector2(2.6, 1.9)][i]
		body.add_child(_box_shape("Post%d" % i, Vector3(0.32, 3.6, 0.32), Vector3(pp.x, 1.8, pp.y)))
	root.add_child(body)
	var embers := CPUParticles3D.new()
	embers.name = "Embers"
	embers.position = Vector3(0, 1.4, 2.7)
	embers.amount = 18
	embers.lifetime = 1.6
	embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	embers.emission_box_extents = Vector3(1.1, 0.1, 0.5)
	embers.direction = Vector3.UP
	embers.spread = 20.0
	embers.initial_velocity_min = 1.2
	embers.initial_velocity_max = 2.6
	embers.gravity = Vector3(0.2, 0.6, 0.0)
	embers.scale_amount_min = 0.6
	embers.scale_amount_max = 1.0
	var spark := QuadMesh.new()
	spark.size = Vector2(0.07, 0.07)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.albedo_color = Color(1.0, 0.62, 0.2)
	sm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	spark.material = sm
	embers.mesh = spark
	embers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	embers.visibility_range_end = 90.0
	root.add_child(embers)
	return root


## C3: a waystone's monument, its foot at the origin: a plinth of two rough slabs ringed by kerb stones, and on it a
## tall leaning menhir of blue-grey stone with two rune bands and a rune eye cut in it, crowned by three small
## standing stones round a notch; over the notch a ring of six rune stones (Ring, turning while the stone is known);
## and the Beam, a column of pale light 90 m into the sky (shown once the stone is known). The runes glow by its state
## (WaystoneLook: dark while it is shut, a faint slow pulse until the giant has reached it, bright once known). One
## mesh for the stone, one for the ring, one for the beam; no solids of its own (the old stone's body stays).
static func build_monument() -> Node3D:
	var root := Node3D.new()
	root.name = "Monument"
	root.set_script(load(S_WAYSTONE_LOOK))
	var k := LM.new(320001)
	var slab := LM.col(Color(0.44, 0.43, 0.41), LM.STONE)
	var blue := LM.col(Color(0.40, 0.42, 0.44), LM.STONE)
	var kerb := LM.col(Color(0.40, 0.39, 0.36), LM.STONE)
	var rune := LM.col(Color(0.55, 0.85, 1.0), LM.GLOW)
	k.prism(Vector3(0, 0, 0), Vector2(3.0, 2.8), Vector2(2.8, 2.6), 0.6, slab, 7, 1, 0.07)
	k.prism(Vector3(0, 0.6, 0), Vector2(2.2, 2.0), Vector2(2.0, 1.85), 0.55, slab, 6, 1, 0.06, 0.4)
	for i in 8:
		var a := TAU * float(i) / 8.0 + 0.2
		k.prism(Vector3(cos(a) * 3.6, 0, sin(a) * 3.6), Vector2(0.38, 0.3), Vector2(0.24, 0.2), 0.7 + 0.25 * sin(i * 1.9),
			kerb, 5, 1, 0.15, a)
	var lean := Vector3(0.35, 0, 0.12)
	var h := 8.6
	k.prism(Vector3(0, 1.15, 0), Vector2(0.98, 0.76), Vector2(0.58, 0.44), h, blue, 5, 6, 0.06, 0.15, lean, 0.06)
	# the rune bands and the eye: thin glowing rings just proud of the stone
	for band: Array in [[0.32, 0.22], [0.58, 0.18]]:
		var t := float(band[0])
		var r := Vector2(0.98, 0.76).lerp(Vector2(0.58, 0.44), t) * 1.045
		k.prism(Vector3(0, 1.15 + h * t, 0) + lean * t, r, r * 0.985, float(band[1]), rune, 5, 1, 0.0, 0.15)
	var eye_t := 0.78
	var er := Vector2(0.98, 0.76).lerp(Vector2(0.58, 0.44), eye_t)
	k.block(Vector3(0, 1.15 + h * eye_t, -er.y * 0.98) + lean * eye_t, Vector3(0.34, 0.5, 0.12), rune, 0.05)
	k.block(Vector3(0, 1.15 + h * eye_t, er.y * 0.98) + lean * eye_t, Vector3(0.34, 0.5, 0.12), rune, 0.05)
	# the crown: three small standing stones round the notch
	var top := Vector3(0, 1.15 + h, 0) + lean
	for i in 3:
		var a := TAU * float(i) / 3.0 + 0.5
		k.prism(top + Vector3(cos(a) * 0.36, -0.05, sin(a) * 0.3), Vector2(0.2, 0.16), Vector2(0.1, 0.08), 1.05, blue, 4, 1,
			0.1, a, Vector3(cos(a), 0, sin(a)) * 0.22)
	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = k.commit()
	mesh.material_override = _landmark_material(Color(0.55, 0.85, 1.0), 1.6, 0.0, 0.0)
	mesh.visibility_range_end = 240.0
	root.add_child(mesh)
	var rk := LM.new(320101)
	for i in 6:
		var a := TAU * float(i) / 6.0
		var c := Vector3(cos(a) * 1.5, 0, sin(a) * 1.5)
		rk.prism(c - Vector3(0, 0.3, 0), Vector2(0.2, 0.17), Vector2(0.13, 0.11), 0.6, blue, 5, 1, 0.12, a)
		rk.block(c - Vector3(0, 0.05, 0), Vector3(0.12, 0.18, 0.12), rune, 0.02, a)
	var ring := MeshInstance3D.new()
	ring.name = "Ring"
	ring.mesh = rk.commit()
	ring.position = top + Vector3(0, 1.6, 0)
	ring.material_override = mesh.material_override
	ring.visibility_range_end = 300.0
	root.add_child(ring)
	var beam := MeshInstance3D.new()
	beam.name = "Beam"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.6
	cyl.bottom_radius = 2.4
	cyl.height = 90.0
	cyl.radial_segments = 12
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	beam.mesh = cyl
	var bm := ShaderMaterial.new()
	bm.shader = load(BEAM_SHADER)
	beam.material_override = bm
	beam.position = top + Vector3(0, 45.5, 0)
	beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam.visibility_range_end = BEAM_FAR_M
	root.add_child(beam)
	# C3b: the plinth's solid - its two slabs as an eight-sided step narrowing to the menhir's foot (the menhir is the
	# old stone's body, which stays): a giant no longer wades through the plinth
	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = SceneKit.L_WORLD
	body.collision_mask = 0
	var plinth := CollisionShape3D.new()
	plinth.name = "Plinth"
	var pts := PackedVector3Array()
	for tier: Array in [[Vector2(1.45, 1.35), 0.0], [Vector2(1.4, 1.3), 0.6], [Vector2(1.0, 0.92), 1.15]]:
		var r: Vector2 = tier[0]
		for i in 8:
			var a := TAU * float(i) / 8.0 + PI / 8.0
			pts.append(Vector3(cos(a) * r.x, float(tier[1]), sin(a) * r.y))
	var cps := ConvexPolygonShape3D.new()
	cps.points = pts
	plinth.shape = cps
	body.add_child(plinth)
	root.add_child(body)
	return root


## C3b: a soft round puff (32 px, a smooth radial falloff): the smithy's smoke and its fire's glow.
static func _soft_round_puff() -> ImageTexture:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var a := clampf(1.0 - sqrt(u * u + v * v), 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, a * a * (3.0 - 2.0 * a)))
	return ImageTexture.create_from_image(img)
