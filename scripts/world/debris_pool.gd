class_name DebrisPool
extends Node3D
## Pooled cosmetic debris: at most 40 active pieces, each removed after 5 s or once it has
## been off screen for a second. Debris collides with the world only; it never damages
## actors and never blocks the camera or movement.

const MAX_ACTIVE := 40
const LIFETIME_S := 5.0
const OFFSCREEN_GRACE_S := 1.0

var _bodies: Array[RigidBody3D] = []
var _age: Array[float] = []
var _offscreen: Array[float] = []
var _active: Array[bool] = []
var _cursor := 0
var spawned_total := 0


func _ready() -> void:
	add_to_group("debris_pool")
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.16, 0.16, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.38, 0.22)
	mat.roughness = 0.9
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	for i in MAX_ACTIVE:
		var body := RigidBody3D.new()
		body.name = "Debris%02d" % i
		body.collision_layer = HitQueryAdapter.LAYER_DEBRIS
		body.collision_mask = HitQueryAdapter.LAYER_WORLD
		body.mass = 2.0
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		body.add_child(mi)
		add_child(body)
		_deactivate_body(body)
		_bodies.append(body)
		_age.append(0.0)
		_offscreen.append(0.0)
		_active.append(false)


func spawn(transforms: Array[Transform3D], velocities: Array[Vector3]) -> void:
	for i in transforms.size():
		var idx := _take_slot()
		var body := _bodies[idx]
		body.global_transform = transforms[i]
		body.freeze = false
		body.visible = true
		body.process_mode = Node.PROCESS_MODE_INHERIT
		body.linear_velocity = velocities[i] if i < velocities.size() else Vector3.ZERO
		body.angular_velocity = Vector3(1.7 * (i % 3), 2.3, -1.1 * (i % 2))
		_age[idx] = 0.0
		_offscreen[idx] = 0.0
		_active[idx] = true
		spawned_total += 1


func active_count() -> int:
	var n := 0
	for a in _active:
		if a:
			n += 1
	return n


func clear_all() -> void:
	for i in _bodies.size():
		_active[i] = false
		_deactivate_body(_bodies[i])


func _take_slot() -> int:
	for i in _bodies.size():
		if not _active[i]:
			return i
	# Pool full: recycle the oldest piece instead of growing past the cap.
	var oldest := 0
	for i in _bodies.size():
		if _age[i] > _age[oldest]:
			oldest = i
	return oldest


func _deactivate_body(body: RigidBody3D) -> void:
	body.freeze = true
	body.visible = false
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_position = Vector3(0.0, -500.0, 0.0)


func _physics_process(delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	for i in _bodies.size():
		if not _active[i]:
			continue
		_age[i] += delta
		var pos := _bodies[i].global_position
		if cam != null and not cam.is_position_in_frustum(pos):
			_offscreen[i] += delta
		else:
			_offscreen[i] = 0.0
		if _age[i] >= LIFETIME_S or _offscreen[i] >= OFFSCREEN_GRACE_S or pos.y < -50.0:
			_active[i] = false
			_deactivate_body(_bodies[i])
