class_name InputRouter
extends Node
## Engine adapter: turns raw input events into gameplay intents, consumed once per sim tick.
##
## Input contexts: GAMEPLAY (intents flow), MENU (pause/settings: gameplay input is
## suppressed), TEXT (reserved for typing). Modifier combos consume their inputs:
##   * keyboard: Shift + light attack = ONE heavy attack (never also a light attack);
##   * controller: the controller bindings of ability_1..8 and ultimate are COMBO buttons that
##     only fire while the "ability_modifier" (LT by default) is held. Defaults: LT + A/B/X/Y =
##     slots 1-4, LT + D-pad Up/Right/Down/Left = slots 5-8, LT + RT = ultimate. While the
##     modifier is held those buttons do nothing else (LT+B never dodges, LT+Up never switches
##     camera, LT+RT never heavy attacks). All of it is remappable like any other binding.
## Tests and the autopilot drive the same path through the inject_* methods.

enum Context { GAMEPLAY, MENU, TEXT }

## Global context shared by every router (one player in the prototype).
static var context: int = Context.GAMEPLAY

const FLICK_ON := 0.75
const FLICK_OFF := 0.35

var _edges: Array[StringName] = []
var _look_delta := Vector2.ZERO
var _axis_pressed: Dictionary = {}
var _flick_armed := true

var use_injection := false
var injected_move := Vector2.ZERO
var injected_holds: Dictionary = {}   ## &"block", &"sprint", &"heavy_modifier", &"lock" -> bool


static func set_context(new_context: int) -> void:
	context = new_context


func _unhandled_input(event: InputEvent) -> void:
	if context != Context.GAMEPLAY:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_look_delta += (event as InputEventMouseMotion).relative
		return
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	var pad := event is InputEventJoypadButton or event is InputEventJoypadMotion
	if pad and _pad_modifier_held():
		for i in range(1, 9):
			if _edge(event, "ability_%d" % i) == 1:
				_edges.append(StringName("slot_%d" % i))
				_consume_combo(event)
				return
		if _edge(event, "ultimate") == 1:
			_edges.append(&"ultimate")
			_consume_combo(event)
			return
		if _is_combo_input(event):
			_consume_combo(event)  # held/released combo button while the modifier is down
			return
	_route(event, pad)


## True when the event belongs to a combo binding (ability_N / ultimate controller bindings).
func _is_combo_input(event: InputEvent) -> bool:
	for action_name: String in InputBindings.COMBO_ACTIONS:
		if InputMap.has_action(action_name) and event.is_action(action_name):
			return true
	return false


## Swallows a combo input. Axis states of the actions it would otherwise trigger are synced,
## so releasing the modifier before the trigger cannot produce a phantom press later.
func _consume_combo(event: InputEvent) -> void:
	if event is InputEventJoypadMotion:
		for action_name: String in InputBindings.ACTIONS:
			if InputMap.has_action(action_name) and event.is_action(action_name):
				_axis_pressed[action_name] = event.get_action_strength(action_name) >= 0.5
	get_viewport().set_input_as_handled()


func _route(event: InputEvent, pad: bool) -> void:
	var handled := false
	if _edge(event, "attack_light") == 1:
		_edges.append(&"heavy" if _modifier_held() else &"light")
		handled = true
	if _edge(event, "attack_heavy") == 1:
		_edges.append(&"heavy")
		handled = true
	match _edge(event, "block"):
		1:
			_edges.append(&"block_press")
			handled = true
		-1:
			_edges.append(&"block_release")
			handled = true
	match _edge(event, "lock_target"):
		1:
			_edges.append(&"lock_press")
			handled = true
		-1:
			_edges.append(&"lock_release")
			handled = true
	var simple := {"dodge": &"dodge", "jump": &"jump", "interact": &"interact",
		"sprint": &"sprint_press", "target_prev": &"target_left", "target_next": &"target_right",
		"camera_toggle": &"camera_toggle"}
	for action_name: String in simple:
		if _edge(event, action_name) == 1:
			_edges.append(simple[action_name])
			handled = true
	# Controller bindings of abilities and the ultimate are combos (handled above, only with the
	# modifier held); here only keyboard/mouse bindings fire them directly.
	if not pad:
		for i in range(1, 9):
			if _edge(event, "ability_%d" % i) == 1:
				_edges.append(StringName("slot_%d" % i))
				handled = true
		if _edge(event, "ultimate") == 1:
			_edges.append(&"ultimate")
			handled = true
	if handled:
		get_viewport().set_input_as_handled()


## +1 on press, -1 on release, 0 otherwise. Joypad axes get hysteresis-free edge tracking.
func _edge(event: InputEvent, action_name: String) -> int:
	if not InputMap.has_action(action_name) or not event.is_action(action_name):
		return 0
	if event is InputEventJoypadMotion:
		var strength := event.get_action_strength(action_name)
		var was: bool = _axis_pressed.get(action_name, false)
		var now := strength >= 0.5
		_axis_pressed[action_name] = now
		if now and not was:
			return 1
		if was and not now:
			return -1
		return 0
	if event.is_pressed() and not event.is_echo():
		return 1
	if event.is_released():
		return -1
	return 0


func _pad_modifier_held() -> bool:
	return InputMap.has_action("ability_modifier") and Input.get_action_strength("ability_modifier") >= 0.5


func _modifier_held() -> bool:
	if use_injection:
		return bool(injected_holds.get(&"heavy_modifier", false))
	return InputMap.has_action("heavy_modifier") and Input.is_action_pressed("heavy_modifier")


func _held(action_name: String, key: StringName) -> bool:
	if use_injection:
		return bool(injected_holds.get(key, false))
	return context == Context.GAMEPLAY and InputMap.has_action(action_name) and Input.is_action_pressed(action_name)


## Called once per simulation tick by the owning actor.
func consume() -> Dictionary:
	var move := Vector2.ZERO
	if use_injection:
		move = injected_move.limit_length(1.0)
	elif context == Context.GAMEPLAY:
		move = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if context == Context.GAMEPLAY and not use_injection:
		var rx := Input.get_action_strength("look_right") - Input.get_action_strength("look_left")
		if absf(rx) >= FLICK_ON and _flick_armed:
			_flick_armed = false
			_edges.append(&"stick_flick_right" if rx > 0.0 else &"stick_flick_left")
		elif absf(rx) <= FLICK_OFF:
			_flick_armed = true
	var out := {
		"edges": _edges.duplicate(),
		"move": move,
		"block_held": _held("block", &"block"),
		"sprint_held": _held("sprint", &"sprint"),
		"lock_held": _held("lock_target", &"lock"),
	}
	_edges.clear()
	if context != Context.GAMEPLAY:
		out.edges = []
	return out


## Mouse look accumulated since the last call (camera reads it every rendered frame).
func take_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d if context == Context.GAMEPLAY else Vector2.ZERO


func clear() -> void:
	_edges.clear()
	_look_delta = Vector2.ZERO
	_axis_pressed.clear()


# --------------------------------------------------------------------------- injection

func inject_edge(edge: StringName) -> void:
	_edges.append(edge)


func inject_light_attack() -> void:
	_edges.append(&"heavy" if _modifier_held() else &"light")


func set_injected_hold(key: StringName, held: bool) -> void:
	use_injection = true
	injected_holds[key] = held


func set_injected_move(v: Vector2) -> void:
	use_injection = true
	injected_move = v
