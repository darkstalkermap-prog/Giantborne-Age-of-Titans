class_name ForgeLook
extends Node3D
## C3 (decision C3-6): a forge's smithy (scenes/world/smithy.tscn, tools/builders/forge.gd build_smithy) -
## presentation only. Forge.attach_look() puts one on every forge over its old boxes (in its frame: the giant works
## it facing -Z, the hearth behind), scaled to the forge (forge.tscn's at 1, a titan-tier forge's larger);
## set_lit() follows the forge: lit (open: the coals and flames glowing and flickering, the fire's light, the smoke
## from the chimney's crown, the embers) or cold (shut: dark ashes, no light, no smoke).

const GLOW_LIT := 2.6

var lit := true
var _mat: ShaderMaterial
var _light: OmniLight3D
var _smoke: CPUParticles3D
var _embers: CPUParticles3D
var _t := 0.0


func _ready() -> void:
	var mesh := get_node_or_null("Mesh") as GeometryInstance3D
	if mesh != null and mesh.material_override is ShaderMaterial:
		_mat = (mesh.material_override as ShaderMaterial).duplicate()
		mesh.material_override = _mat
	_light = get_node_or_null("Light") as OmniLight3D
	_smoke = get_node_or_null("Smoke") as CPUParticles3D
	_embers = get_node_or_null("Embers") as CPUParticles3D
	_apply()


func set_lit(on: bool) -> void:
	if on == lit:
		return
	lit = on
	_apply()


func _apply() -> void:
	if _mat != null:
		_mat.set_shader_parameter("glow", GLOW_LIT if lit else 0.05)
		_mat.set_shader_parameter("flicker", 0.8 if lit else 0.0)
	if _light != null:
		_light.visible = lit
	for p: CPUParticles3D in [_smoke, _embers]:
		if p != null:
			p.emitting = lit
			p.visible = lit


func _process(delta: float) -> void:
	if not lit or _light == null:
		return
	_t += delta
	_light.light_energy = 2.0 + 0.45 * sin(_t * 11.0) * sin(_t * 3.7 + 1.0) + 0.25 * sin(_t * 23.0)


## The chimney's crown in the world (where the HUD's place marker stands).
func crown() -> Vector3:
	return global_position + global_basis * Vector3(0, 13.4, 3.75)
