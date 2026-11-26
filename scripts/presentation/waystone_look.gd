class_name WaystoneLook
extends Node3D
## C3 (decision C3-6): a waystone's monument (scenes/world/waystone_monument.tscn, tools/builders/forge.gd
## build_monument) - presentation only. Waystone.attach_look() puts one on every waystone over its old stone, at
## the stone's foot; set_state() follows the stone:
##   * shut (its flags not yet met): the runes dark, no ring, no beam;
##   * open, not yet reached: the runes a faint slow pulse - a waystone to find - no ring; C3b: its beam a faint grey
##     column (unlit), so it is seen from far off;
##   * known (reached once: the visited flag, or reached in this visit): the runes bright, the ring of rune stones
##     turning over the crown and the beam of light standing 90 m into the sky, faded in over FADE_S.
## Each monument has its own copy of the stone's material (its glow is its own); the beam's strength and the ring's
## turn run in _process.

enum State { SHUT, OPEN, KNOWN }

const FADE_S := 1.5
const RING_DEG_S := 18.0
const GLOW := {State.SHUT: 0.0, State.OPEN: 0.3, State.KNOWN: 1.3}
const PULSE := {State.SHUT: 0.0, State.OPEN: 1.0, State.KNOWN: 0.25}
## C3b (decision C3b-5): the beam's strength by state - an open stone not yet reached stands as a faint grey column
## (the shader's `unlit`), seen from far off as a waystone to find; a known one burns blue; a shut one has none.
const BEAM := {State.SHUT: 0.0, State.OPEN: 0.32, State.KNOWN: 1.0}
const UNLIT_COLOR := Color(0.72, 0.74, 0.78)
## How far an unreached stone's grey column draws (a known one's beam: its scene's 2.4 km). Within the static world's
## 40 draw calls a view at low (a new game's stones are all unreached: at 2.4 km the woodcutters' camp saw four more);
## beyond it the HUD's far mark carries the stone (HudPlaceMarker).
const UNLIT_FAR_M := 300.0
const UNLIT_NEAR_M := 150.0
const LIT_COLOR := Color(0.55, 0.85, 1.0)

var state := State.SHUT
var _beam := 0.0
var _mat: ShaderMaterial
var _beam_mat: ShaderMaterial
var _ring: Node3D
var _beam_node: GeometryInstance3D
var _beam_far := -1.0


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
	if _beam_node != null:
		if _beam_far < 0.0:
			_beam_far = _beam_node.visibility_range_end
		_beam_node.visibility_range_end = _beam_far if state == State.KNOWN else minf(_beam_far, UNLIT_FAR_M)
		# (the unreached stone's column only where the stone itself is small: nearer, the monument says it)
		_beam_node.visibility_range_begin = 0.0 if state == State.KNOWN else UNLIT_NEAR_M
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("unlit", 0.0 if state == State.KNOWN else 1.0)
		_beam_mat.set_shader_parameter("beam_color", LIT_COLOR if state == State.KNOWN else UNLIT_COLOR)
	if instant:
		_beam = float(BEAM[state])
	_show_beam()


func _show_beam() -> void:
	if _beam_node != null:
		_beam_node.visible = _beam > 0.001
	if _beam_mat != null:
		_beam_mat.set_shader_parameter("strength", _beam)


func _process(delta: float) -> void:
	var want := float(BEAM[state])
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
