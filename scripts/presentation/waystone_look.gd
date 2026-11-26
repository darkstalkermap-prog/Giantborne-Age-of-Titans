class_name WaystoneLook
extends Node3D
## C3 (decision C3-6): a waystone's monument (scenes/world/waystone_monument.tscn, tools/builders/forge.gd
## build_monument) - presentation only. Waystone.attach_look() puts one on every waystone over its old stone, at
## the stone's foot; set_state() follows the stone:
##   * shut (its flags not yet met): the runes dark, no ring, no beam;
##   * open, not yet reached: the runes a faint slow pulse - a waystone to find - no ring, no beam;
##   * known (reached once: the visited flag, or reached in this visit): the runes bright, the ring of rune stones
##     turning over the crown and the beam of light standing 90 m into the sky, faded in over FADE_S.
## Each monument has its own copy of the stone's material (its glow is its own); the beam's strength and the ring's
## turn run in _process.

enum State { SHUT, OPEN, KNOWN }

const FADE_S := 1.5
const RING_DEG_S := 18.0
const GLOW := {State.SHUT: 0.0, State.OPEN: 0.3, State.KNOWN: 1.3}
const PULSE := {State.SHUT: 0.0, State.OPEN: 1.0, State.KNOWN: 0.25}

var state := State.SHUT
var _beam := 0.0
var _mat: ShaderMaterial
var _beam_mat: ShaderMaterial
var _ring: Node3D
var _beam_node: GeometryInstance3D


func _ready() -> void:
	var mesh := get_node_or_null("Mesh") as GeometryInstance3D
	if mesh != null and mesh.material_override is ShaderMaterial:
		_mat = (mesh.material_override as ShaderMaterial).duplicate()
		mesh.material_override = _mat
	_ring = get_node_or_null("Ring") as Node3D
	if _ring is GeometryInstance3D and _mat != null:
		(_ring as GeometryInstance3D).material_override = _mat
	_beam_node = get_node_or_null("Beam") as GeometryInstance3D
	if _beam_node != null and _beam_node.material_override is ShaderMaterial:
		_beam_mat = (_beam_node.material_override as ShaderMaterial).duplicate()
		_beam_node.material_override = _beam_mat
	_apply(true)


## open: its flags are met; known: the giant has reached it.
func set_state(open: bool, known: bool) -> void:
	var s := State.KNOWN if open and known else (State.OPEN if open else State.SHUT)
	if s == state:
		return
	state = s
	_apply(false)


func _apply(instant: bool) -> void:
	if _mat != null:
		_mat.set_shader_parameter("glow", float(GLOW[state]))
		_mat.set_shader_parameter("pulse", float(PULSE[state]))
	if _ring != null:
		_ring.visible = state == State.KNOWN
	if instant:
		_beam = 1.0 if state == State.KNOWN else 0.0
	_show_beam()


func _show_beam() -> void:
	if _beam_node != null:
		_beam_node.visible = _beam > 0.001
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("strength", _beam)


func _process(delta: float) -> void:
	var want := 1.0 if state == State.KNOWN else 0.0
	if not is_equal_approx(_beam, want):
		_beam = move_toward(_beam, want, delta / FADE_S)
		_show_beam()
	if _ring != null and _ring.visible:
		_ring.rotate_y(deg_to_rad(RING_DEG_S) * delta)


## "shut", "open" or "known" (tests, the HUD's place marker).
func state_name() -> String:
	return ["shut", "open", "known"][state]


## The monument's crown in the world (where the HUD's place marker stands).
func crown() -> Vector3:
	return global_position + global_basis * Vector3(0.35, 10.9, 0.12)
