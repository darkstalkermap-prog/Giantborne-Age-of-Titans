extends Node3D
## C4: a settlement's fire (tools/world/kinds/settlement_fire.gd): its light flickers about base_energy and its
## flames sway a little (presentation only: nothing here reads or changes the simulation). Off headless.

@export var flicker := true
@export var base_energy := 2.2

var _t := 0.0
var _light: OmniLight3D = null
var _flames: Node3D = null
var _phase := 0.0


func _ready() -> void:
	_light = get_node_or_null("Light") as OmniLight3D
	_flames = get_node_or_null("Flames") as Node3D
	_phase = float(absi(hash(name)) % 1000) * 0.01
	set_process(DisplayServer.get_name() != "headless")


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	var w := sin(_t * 7.3 + _phase) * 0.5 + sin(_t * 13.1 + _phase * 2.0) * 0.3 + sin(_t * 3.1) * 0.2
	if _light != null and flicker:
		_light.light_energy = base_energy * (1.0 + 0.16 * w)
	if _flames != null:
		_flames.scale = Vector3(1.0, 1.0 + 0.12 * w, 1.0)
		_flames.rotation.y = 0.15 * sin(_t * 1.7 + _phase)
