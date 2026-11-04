class_name HitFeedback
extends Node3D
## Presentation-only reactions to combat events: floating damage numbers, hit flashes,
## camera shake, wall-clank sparks and the Heavy Footfall shock ring. Listens to Events;
## never changes gameplay state. Every effect respects the comfort settings.

const NUMBER_POOL := 24
const NUMBER_LIFETIME := 0.9

var _labels: Array[Label3D] = []
var _ages: Array[float] = []
var _velocity: Array[Vector3] = []
var _next := 0
var _sparks: Array[MeshInstance3D] = []
var _spark_ages: Array[float] = []
var _ring: MeshInstance3D
var _ring_age := 99.0
var _ring_radius := 3.0


func _ready() -> void:
	for i in NUMBER_POOL:
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.fixed_size = true
		l.pixel_size = 0.0022
		l.font_size = 30
		l.outline_size = 8
		l.visible = false
		add_child(l)
		_labels.append(l)
		_ages.append(99.0)
		_velocity.append(Vector3.ZERO)
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.18
	spark_mesh.height = 0.36
	var spark_mat := StandardMaterial3D.new()
	spark_mat.albedo_color = Color(1.0, 0.85, 0.4)
	spark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for i in 6:
		var s := MeshInstance3D.new()
		s.mesh = spark_mesh
		s.material_override = spark_mat
		s.visible = false
		add_child(s)
		_sparks.append(s)
		_spark_ages.append(99.0)
	_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.0
	_ring.mesh = torus
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = Color(0.85, 0.75, 0.55, 0.8)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = ring_mat
	_ring.visible = false
	add_child(_ring)
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.attack_clanked.connect(_on_clank)
	Events.area_pulse.connect(_on_area_pulse)


func _player_rig() -> CameraRig:
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	return p.camera_rig if p != null else null


func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	var target := Sim.get_entity(r.event.target_id)
	if target == null:
		return
	var text := ""
	var color := Color.WHITE
	match r.outcome:
		HitResult.Outcome.HIT:
			text = str(r.health_damage)
			color = Color(1.0, 0.85, 0.3) if r.crit else Color.WHITE
			if r.crit:
				text += "!"
		HitResult.Outcome.BLOCKED:
			text = "BLOCK %d" % r.health_damage
			color = Color(0.6, 0.8, 1.0)
		HitResult.Outcome.PARRIED:
			text = "PARRY"
			color = Color(1.0, 0.8, 0.2)
		HitResult.Outcome.GUARD_BROKEN:
			text = "GUARD BREAK %d" % r.health_damage
			color = Color(1.0, 0.4, 0.3)
		HitResult.Outcome.EVADED:
			text = "EVADE"
			color = Color(0.7, 0.9, 0.7)
		HitResult.Outcome.IMMUNE:
			text = "IMMUNE" if r.notes != "not_permitted" else ""
			color = Color(0.7, 0.7, 0.7)
	if r.killed:
		text += "  KO"
	if text != "" and Settings.get_value("damage_numbers"):
		_spawn_number(target.anchor_position() + Vector3.UP * 0.6, text, color)
	if r.outcome in [HitResult.Outcome.HIT, HitResult.Outcome.BLOCKED, HitResult.Outcome.GUARD_BROKEN] \
			and target.actor.has_method("flash"):
		target.actor.flash(0.9 if r.outcome == HitResult.Outcome.HIT else 0.45)
	var rig := _player_rig()
	if rig == null:
		return
	if target.team == CombatEntity.Team.PLAYER and r.health_damage > 0:
		rig.add_shake(clampf(0.25 + r.health_damage / 120.0, 0.25, 0.7))
	elif r.event.attacker_id == "player" and r.health_damage > 0:
		rig.add_shake(0.35 if r.event.has_tag("Heavy") else 0.15)


func _spawn_number(pos: Vector3, text: String, color: Color) -> void:
	var i := _next
	_next = (_next + 1) % NUMBER_POOL
	var l := _labels[i]
	l.text = text
	l.modulate = color
	l.outline_modulate = Color(0, 0, 0, 0.85)
	l.global_position = pos
	l.visible = true
	_ages[i] = 0.0
	var jitter := float((i * 37) % 11 - 5) * 0.08
	_velocity[i] = Vector3(jitter, 1.6, 0.0)


func _on_clank(_tick: int, _actor_id: String, _instance: int, point: Vector3) -> void:
	for i in _sparks.size():
		if _spark_ages[i] > 0.25:
			_sparks[i].global_position = point
			_sparks[i].visible = true
			_spark_ages[i] = 0.0
			break


func _on_area_pulse(_tick: int, _actor_id: String, _action_id: String, center: Vector3, radius: float) -> void:
	_ring.global_position = center + Vector3.UP * 0.1
	_ring_radius = radius
	_ring_age = 0.0
	_ring.visible = true
	var rig := _player_rig()
	if rig != null:
		rig.add_shake(0.55)


func _process(delta: float) -> void:
	for i in _labels.size():
		if _ages[i] >= NUMBER_LIFETIME:
			continue
		_ages[i] += delta
		var l := _labels[i]
		l.global_position += _velocity[i] * delta
		var fade := clampf(1.0 - (_ages[i] / NUMBER_LIFETIME), 0.0, 1.0)
		l.modulate.a = fade
		l.outline_modulate.a = fade * 0.85
		if _ages[i] >= NUMBER_LIFETIME:
			l.visible = false
	for i in _sparks.size():
		if _spark_ages[i] < 0.25:
			_spark_ages[i] += delta
			var k := 1.0 + _spark_ages[i] * 6.0
			_sparks[i].scale = Vector3.ONE * k
			if _spark_ages[i] >= 0.25:
				_sparks[i].visible = false
	if _ring_age < 0.45:
		_ring_age += delta
		var t := clampf(_ring_age / 0.45, 0.0, 1.0)
		var s := lerpf(0.4, 1.0, t) * _ring_radius
		_ring.scale = Vector3(s, 1.0, s)
		var mat := _ring.material_override as StandardMaterial3D
		mat.albedo_color.a = 0.8 * (1.0 - t)
		if _ring_age >= 0.45:
			_ring.visible = false
