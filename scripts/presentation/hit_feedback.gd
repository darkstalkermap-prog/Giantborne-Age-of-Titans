class_name HitFeedback
extends Node3D
## Presentation-only reactions to combat events: floating damage and heal numbers, hit
## flashes, camera shake, wall-clank sparks, the Heavy Footfall shock ring, and the M2 ability
## effects (P03): the Sweeping Blow sector, the Thunder Roar ring, a rising ring for self buffs,
## sparks for casts and projectile impacts, and status tints on actor rigs (Stone Skin, slow,
## Mend, Titan Surge). Listens to Events; never changes gameplay state. Every effect respects
## the comfort settings. Projectile meshes themselves belong to the ProjectileSystem.

const NUMBER_POOL := 24
const NUMBER_LIFETIME := 0.9
const SECTOR_LIFETIME := 0.35
const ROAR_LIFETIME := 0.55
const BUFF_LIFETIME := 0.6
## Status id -> rig tint (alpha = strength), in priority order: the first active one shows.
const STATUS_TINTS := [
	["status.titan_surge", Color(1.0, 0.55, 0.2, 0.40)],
	["status.stone_skin", Color(0.62, 0.58, 0.50, 0.45)],
	["status.slow", Color(0.45, 0.70, 1.0, 0.35)],
	["status.mend", Color(0.45, 1.0, 0.50, 0.30)],
]

var _labels: Array[Label3D] = []
var _ages: Array[float] = []
var _velocity: Array[Vector3] = []
var _next := 0
var _sparks: Array[MeshInstance3D] = []
var _spark_ages: Array[float] = []
var _ring: MeshInstance3D
var _ring_age := 99.0
var _ring_radius := 3.0
var _sector: MeshInstance3D
var _sector_age := 99.0
var _fan_meshes: Dictionary = {}   ## rounded arc degrees -> ArrayMesh (unit radius)
var _roar: MeshInstance3D
var _roar_age := 99.0
var _roar_radius := 6.0
var _buff: MeshInstance3D
var _buff_age := 99.0
var _buff_origin := Vector3.ZERO
var _buff_height := 3.66


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
	_sector = MeshInstance3D.new()
	_sector.material_override = _effect_material(Color(1.0, 0.88, 0.55, 0.55))
	_sector.visible = false
	add_child(_sector)
	_roar = _make_ring(Color(0.70, 0.85, 1.0, 0.85), 0.92)
	_buff = _make_ring(Color(1.0, 0.85, 0.40, 0.85), 0.85)
	Events.hit_resolved.connect(_on_hit_resolved)
	Events.attack_clanked.connect(_on_clank)
	Events.area_pulse.connect(_on_area_pulse)
	Events.ability_effect.connect(_on_ability_effect)
	Events.projectile_impact.connect(_on_projectile_impact)
	Events.healed.connect(_on_healed)
	Events.status_applied.connect(_on_status_applied)
	Events.status_expired.connect(_on_status_expired)


func _effect_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _make_ring(color: Color, inner: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = inner
	torus.outer_radius = 1.0
	mi.mesh = torus
	mi.material_override = _effect_material(color)
	mi.visible = false
	add_child(mi)
	return mi


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
			if r.health_damage == 0 and r.event.power <= 0.0:
				text = ""   # a pure status / morale hit (Thunder Roar): the tint shows it
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
		_rumble(0.35, 0.6, 0.18)
	elif r.event.attacker_id == "player" and r.health_damage > 0:
		rig.add_shake(0.35 if r.event.has_tag("Heavy") else 0.15)
		_rumble(0.2, 0.45 if r.event.has_tag("Heavy") else 0.15, 0.1)
	elif r.outcome == HitResult.Outcome.PARRIED and target.team == CombatEntity.Team.PLAYER:
		_rumble(0.5, 0.2, 0.12)


## Controller rumble, scaled by the vibration setting (0 disables it).
func _rumble(weak: float, strong: float, seconds: float) -> void:
	var scale := float(Settings.get_value("vibration"))
	if scale <= 0.0:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak * scale, 0.0, 1.0), clampf(strong * scale, 0.0, 1.0), seconds)


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
	_spark(point)


func _on_area_pulse(_tick: int, _actor_id: String, action_id: String, center: Vector3, radius: float) -> void:
	var a := GameData.get_action(action_id)
	if a != null and float(a.param("morale_damage", 0.0)) > 0.0:
		return   # a roar: its own ring (ability_effect "roar")
	_ring.global_position = center + Vector3.UP * 0.1
	_ring_radius = radius
	_ring_age = 0.0
	_ring.visible = true
	var rig := _player_rig()
	if rig != null:
		rig.add_shake(0.55)


# --------------------------------------------------------------------------- M2 ability effects (P03)

func _on_ability_effect(_tick: int, actor_id: String, _action_id: String, kind: String,
		center: Vector3, radius: float, yaw: float, arc_deg: float) -> void:
	var rig := _player_rig()
	var by_player := actor_id == "player"
	match kind:
		"sector":
			_sector.mesh = _fan_mesh(arc_deg)
			_sector.global_position = center + Vector3.UP * 0.12
			_sector.rotation = Vector3(0.0, yaw, 0.0)
			_sector.scale = Vector3(radius, 1.0, radius)
			_sector_age = 0.0
			_sector.visible = true
			if rig != null and by_player:
				rig.add_shake(0.3)
		"roar":
			_roar.global_position = center + Vector3.UP * 0.4
			_roar_radius = radius
			_roar_age = 0.0
			_roar.visible = true
			if rig != null:
				rig.add_shake(0.4)
			_rumble(0.4, 0.2, 0.2)
		"self_buff":
			var e := Sim.get_entity(actor_id)
			_buff_height = e.combatant.height_m if e != null else 3.66
			_buff_origin = center
			_buff_age = 0.0
			_buff.visible = true
		"cast":
			_spark(center)


func _on_projectile_impact(_tick: int, _projectile_id: int, point: Vector3, _hit_entity_id: String) -> void:
	_spark(point)


func _on_healed(_tick: int, entity_id: String, amount: float, _source_id: String) -> void:
	var e := Sim.get_entity(entity_id)
	if e == null or amount <= 0.0 or not Settings.get_value("damage_numbers"):
		return
	_spawn_number(e.anchor_position() + Vector3.UP * 0.9, "+%d" % roundi(amount), Color(0.5, 1.0, 0.55))


func _on_status_applied(_tick: int, entity_id: String, _status_id: String, _source_id: String,
		_duration_s: float) -> void:
	_refresh_tint(entity_id)


func _on_status_expired(_tick: int, entity_id: String, _status_id: String) -> void:
	_refresh_tint(entity_id)


## The first STATUS_TINTS entry the entity has, on its ActorRig (actors without a rig: none).
func _refresh_tint(entity_id: String) -> void:
	var e := Sim.get_entity(entity_id)
	if e == null or e.actor == null:
		return
	var rig := e.actor.get("rig") as ActorRig
	if rig == null:
		return
	var tint := Color(0.0, 0.0, 0.0, 0.0)
	for entry: Array in STATUS_TINTS:
		if e.combatant.statuses.has(str(entry[0])):
			tint = entry[1]
			break
	rig.set_status_tint(tint)


func _spark(point: Vector3) -> void:
	for i in _sparks.size():
		if _spark_ages[i] > 0.25:
			_sparks[i].global_position = point
			_sparks[i].visible = true
			_spark_ages[i] = 0.0
			return


## A flat fan of `arc_deg` around local -Z with radius 1 (scaled by the sector radius).
func _fan_mesh(arc_deg: float) -> ArrayMesh:
	var key := int(roundf(arc_deg))
	if _fan_meshes.has(key):
		return _fan_meshes[key]
	var segments := maxi(6, int(arc_deg / 6.0))
	var half := deg_to_rad(arc_deg * 0.5)
	var verts := PackedVector3Array()
	for i in segments:
		var a0 := lerpf(-half, half, float(i) / segments)
		var a1 := lerpf(-half, half, float(i + 1) / segments)
		verts.append(Vector3.ZERO)
		verts.append(Vector3(-sin(a0), 0.0, -cos(a0)))
		verts.append(Vector3(-sin(a1), 0.0, -cos(a1)))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_fan_meshes[key] = mesh
	return mesh


func _process(delta: float) -> void:
	_process_ability_effects(delta)
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


func _process_ability_effects(delta: float) -> void:
	if _sector_age < SECTOR_LIFETIME:
		_sector_age += delta
		var t := clampf(_sector_age / SECTOR_LIFETIME, 0.0, 1.0)
		(_sector.material_override as StandardMaterial3D).albedo_color.a = 0.55 * (1.0 - t)
		if _sector_age >= SECTOR_LIFETIME:
			_sector.visible = false
	if _roar_age < ROAR_LIFETIME:
		_roar_age += delta
		var t := clampf(_roar_age / ROAR_LIFETIME, 0.0, 1.0)
		var s := lerpf(0.2, 1.0, 1.0 - (1.0 - t) * (1.0 - t)) * _roar_radius
		_roar.scale = Vector3(s, 1.0, s)
		(_roar.material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - t)
		if _roar_age >= ROAR_LIFETIME:
			_roar.visible = false
	if _buff_age < BUFF_LIFETIME:
		_buff_age += delta
		var t := clampf(_buff_age / BUFF_LIFETIME, 0.0, 1.0)
		var r := 0.4 * _buff_height
		_buff.global_position = _buff_origin + Vector3.UP * (_buff_height * t)
		_buff.scale = Vector3(r, 1.0, r)
		(_buff.material_override as StandardMaterial3D).albedo_color.a = 0.85 * (1.0 - t)
		if _buff_age >= BUFF_LIFETIME:
			_buff.visible = false
