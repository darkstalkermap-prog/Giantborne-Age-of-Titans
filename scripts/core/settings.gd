extends Node
## Player settings (autoload "Settings"): camera comfort, accessibility and input bindings.
##
## Stored in user://settings.json through SaveIO (schema-versioned, atomic replace, one
## backup). Pass "--no-user-settings" after "--" on the command line (tests, soak runs) to
## ignore and never touch the user's file.

const PATH := "user://settings.json"
const SCHEMA_VERSION := 1

const DEFAULTS := {
	"mouse_sensitivity": 0.12,        ## degrees of camera rotation per mouse pixel
	"stick_look_speed_deg_s": 180.0,
	"invert_y": false,
	"fov_deg": 75.0,
	"sprint_mode": "hold",            ## hold | toggle
	"lock_mode": "toggle",            ## toggle | hold
	"camera_shake": 1.0,              ## 0..1
	"head_bob": 0.5,                  ## 0..1 (first person)
	"hit_flash": 1.0,                 ## 0..1
	"motion_blur": false,             ## no motion blur exists in the prototype; stays off
	"vibration": 1.0,                 ## 0..1 controller rumble
	"fp_aim_assist": true,            ## gentle first-person drift toward a locked target
	"damage_numbers": true,
	"bindings": {},                   ## action -> [event dicts]; replaces that action's defaults
}
const RANGES := {
	"mouse_sensitivity": [0.02, 0.6], "stick_look_speed_deg_s": [60.0, 400.0],
	"fov_deg": [60.0, 100.0], "camera_shake": [0.0, 1.0], "head_bob": [0.0, 1.0],
	"hit_flash": [0.0, 1.0], "vibration": [0.0, 1.0],
}
const ENUMS := {"sprint_mode": ["hold", "toggle"], "lock_mode": ["toggle", "hold"]}

signal changed(key: String)

var values: Dictionary = {}
var load_message := ""
var persist := true
var _unsaved := false   ## changed with save=false (live slider drags) and not yet written
## Session-only state that survives sandbox resets but is never written to disk.
var session := {"camera_mode": 0}


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	persist = not OS.get_cmdline_user_args().has("--no-user-settings")
	if persist:
		load_settings()
	apply_bindings()


func load_settings() -> void:
	var result := SaveIO.read_json(PATH, SCHEMA_VERSION)
	load_message = result.message
	if int(result.get("future_version", 0)) > 0 and FileAccess.file_exists(PATH):
		# Keep the newer file instead of overwriting it on the next save.
		var keep := "user://settings.schema%d.rejected.json" % int(result.future_version)
		DirAccess.copy_absolute(PATH, keep)
		load_message += " It was kept as %s." % keep.get_file()
	if result.ok:
		_merge(result.data)
	if load_message != "":
		push_warning("[settings] " + load_message)


func _merge(data: Dictionary) -> void:
	for key: String in DEFAULTS:
		if not data.has(key):
			continue
		var v: Variant = data[key]
		var want: Variant = DEFAULTS[key]
		if typeof(want) == TYPE_FLOAT:
			if typeof(v) != TYPE_FLOAT and typeof(v) != TYPE_INT:
				continue
			v = float(v)
			if RANGES.has(key):
				v = clampf(v, RANGES[key][0], RANGES[key][1])
		elif typeof(v) != typeof(want):
			continue
		if ENUMS.has(key) and not ENUMS[key].has(v):
			continue
		if key == "bindings":
			v = _sanitize_bindings(v)
		values[key] = v


## Keeps an action's override only if every entry in it is valid; otherwise that action falls
## back to its default bindings (an override replaces the defaults, so a half-broken override
## could otherwise leave an action unbound). Problems are reported in load_message.
func _sanitize_bindings(raw: Dictionary) -> Dictionary:
	var clean := {}
	var dropped := PackedStringArray()
	for action_name: Variant in raw:
		if not InputBindings.ACTIONS.has(action_name) or typeof(raw[action_name]) != TYPE_ARRAY:
			dropped.append(str(action_name))
			continue
		var ok := true
		for ev: Variant in raw[action_name]:
			if InputBindings.validate_event_dict(ev) != "":
				ok = false
		if ok:
			clean[action_name] = raw[action_name]
		else:
			dropped.append(str(action_name))
	if not dropped.is_empty():
		load_message += (" " if load_message != "" else "") + \
			"Ignored invalid saved bindings for: %s (defaults used)." % ", ".join(dropped)
	return clean


func save_settings() -> Error:
	_unsaved = false
	if not persist:
		return OK
	var data := values.duplicate(true)
	data["schema_version"] = SCHEMA_VERSION
	var err := SaveIO.write_json(PATH, data)
	if err != OK:
		push_warning("[settings] could not save settings (error %d)" % err)
	return err


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, v: Variant, save := true) -> void:
	if RANGES.has(key):
		v = clampf(float(v), RANGES[key][0], RANGES[key][1])
	values[key] = v
	changed.emit(key)
	if save:
		save_settings()
	else:
		_unsaved = true


## Writes pending changes (from live slider edits) - called on quit and window close.
func flush() -> void:
	if _unsaved:
		save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush()


func apply_bindings() -> void:
	InputBindings.apply(GameData.get_record("input.default"), values.get("bindings", {}))


## Replaces the keyboard/mouse half (pad=false) or the controller half (pad=true) of an
## action's bindings. An empty dict unbinds that half.
func set_action_binding(action_name: String, pad: bool, ev: Dictionary) -> void:
	var kept: Array = []
	for d: Dictionary in InputBindings.current_events(action_name):
		if InputBindings.is_pad_event(d) != pad:
			kept.append(d)
	if not ev.is_empty():
		kept.append(ev)
	var b: Dictionary = values.get("bindings", {})
	b[action_name] = kept
	values["bindings"] = b
	apply_bindings()
	changed.emit("bindings")
	save_settings()


func reset_bindings() -> void:
	values["bindings"] = {}
	apply_bindings()
	changed.emit("bindings")
	save_settings()


## Other actions already using exactly this event (shown as a warning when rebinding).
func find_conflicts(action_name: String, ev: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for other: String in InputBindings.ACTIONS:
		if other == action_name:
			continue
		for d: Dictionary in InputBindings.current_events(other):
			if d == ev:
				out.append(InputBindings.LABELS.get(other, other))
	return out
