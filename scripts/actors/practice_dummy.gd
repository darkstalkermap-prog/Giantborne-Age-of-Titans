class_name PracticeDummy
extends StaticBody3D
## Training target: armor 25 (so hits show the worked-example numbers: light 37, heavy 66),
## never dies, and refills its health a few seconds after the last hit.

## Stable id of this placed dummy (unique per level).
@export var entity_id := "dummy_01"

@onready var entity: CombatEntity = $CombatEntity
@onready var visual: Node3D = $Visual

var reset_after_s := 3.0
var since_hit := 999.0
var damage_taken_streak := 0
var hits_taken := 0
var last_hit_damage := 0
var _wobble := 0.0
var _wobble_axis := Vector3.RIGHT
var _time := 0.0
var _materials: Array[StandardMaterial3D] = []
var _base_colors: Array[Color] = []
var _flash := 0.0


func _ready() -> void:
	add_to_group("dummies")
	reset_after_s = float(GameData.get_record(entity.definition_id).get("reset_after_s", 3.0))
	entity.hit_taken.connect(_on_hit_taken)
	_collect_materials(visual)
	Sim.register_actor(entity.entity_id, self)


func _exit_tree() -> void:
	Sim.unregister_actor(entity.entity_id, self)


func sim_step(_tick: int, dt: float) -> void:
	since_hit += dt
	var pools := entity.combatant.pools
	if since_hit >= reset_after_s and (pools.health < pools.health_max or damage_taken_streak > 0):
		pools.health = pools.health_max
		damage_taken_streak = 0


func _on_hit_taken(result: HitResult) -> void:
	since_hit = 0.0
	hits_taken += 1
	last_hit_damage = result.health_damage
	damage_taken_streak += result.health_damage
	var away := global_position - result.event.attacker_position
	away.y = 0.0
	if away.length_squared() > 1e-4:
		_wobble_axis = Vector3.UP.cross(away.normalized())
	_wobble = clampf(0.4 + result.health_damage / 80.0, 0.4, 1.0)


func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	_flash = maxf(_flash, strength * float(Settings.get_value("hit_flash")))
	for i in _materials.size():
		_materials[i].albedo_color = _base_colors[i].lerp(color, _flash * 0.85)


func _collect_materials(node: Node) -> void:
	for child in node.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).material_override is StandardMaterial3D:
			var copy := (child as MeshInstance3D).material_override.duplicate() as StandardMaterial3D
			(child as MeshInstance3D).material_override = copy
			_materials.append(copy)
			_base_colors.append(copy.albedo_color)
		_collect_materials(child)


func _process(delta: float) -> void:
	_time += delta
	_wobble = maxf(0.0, _wobble - delta * 1.5)
	var angle := sin(_time * 14.0) * _wobble * 0.25
	visual.basis = Basis(_wobble_axis, angle) if _wobble > 0.0 else Basis.IDENTITY
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 6.0)
		for i in _materials.size():
			_materials[i].albedo_color = _base_colors[i].lerp(Color(1, 0.95, 0.85), _flash * 0.85)
