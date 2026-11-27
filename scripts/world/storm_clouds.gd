class_name StormClouds
extends MeshInstance3D
## D2: a storm's clouds in the world block (world.json "storms" with flags: the storm over the Drowned Steps) - shown
## only while `active_flag` is set (the storm came with act two) and never once `calm_flag` is; the calm flag set while
## it stands, the clouds thin away over CLEAR_S (storm_veil.gdshader's `density` to nothing) and are gone - the storm
## clearing over the Steps after the Stormcaller's fall. Presentation only.

const CLEAR_S := 16.0

@export var active_flag := ""
@export var calm_flag := ""

var _density := 1.25
var _clearing := -1.0


func _ready() -> void:
	var m := material_override if material_override != null else (mesh.surface_get_material(0) if mesh != null else null)
	if m is ShaderMaterial:
		_density = float((m as ShaderMaterial).get_shader_parameter(&"density"))
	set_process(false)
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	refresh()


func _exit_tree() -> void:
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)


func should_show() -> bool:
	if active_flag != "" and not QuestConditions.truthy(WorldState.get_flag(active_flag)):
		return false
	return not (calm_flag != "" and QuestConditions.truthy(WorldState.get_flag(calm_flag)))


func refresh() -> void:
	visible = should_show()
	_set_density(_density)


func _on_flag_changed(_tick: int, flag_id: String, value: Variant) -> void:
	if flag_id == calm_flag and QuestConditions.truthy(value) and visible:
		_clearing = 0.0
		set_process(true)
	elif flag_id == active_flag or flag_id == calm_flag:
		refresh()


func _process(delta: float) -> void:
	if _clearing < 0.0:
		set_process(false)
		return
	_clearing += delta / CLEAR_S
	_set_density(_density * (1.0 - smoothstep(0.0, 1.0, _clearing)))
	if _clearing >= 1.0:
		_clearing = -1.0
		visible = false
		_set_density(_density)
		set_process(false)


func _set_density(d: float) -> void:
	var m := material_override if material_override != null else (mesh.surface_get_material(0) if mesh != null else null)
	if m is ShaderMaterial:
		(m as ShaderMaterial).set_shader_parameter(&"density", d)
