extends Node
## Player settings (autoload "Settings"): camera comfort, accessibility, input bindings, the
## graphics preset and (P19) the audio volumes and focus mute.
##
## Stored in user://settings.json through SaveIO (schema-versioned, atomic replace, one
## backup). Pass "--no-user-settings" after "--" on the command line (tests, soak runs) to
## ignore and never touch the user's file.
##
## Graphics preset (P14, plan §3.16): the setting "graphics_quality" is "low" or "medium" (the
## desktop default). LevelRoot applies the level record's `render` preset for the quality in
## effect, `graphics_quality` (Sun shadow distance, scenery visibility range, viewport MSAA). The
## web build always runs "low", and the command-line flag --graphics=low|medium (after "--")
## fixes the preset for one run without saving it (the reference-PC measurement uses
## --graphics=low).
##
## Button prompts (P16): "prompt_device" is "auto" (prompts name the buttons of the device used
## last), "keyboard" or "pad"; apply_bindings() and set_value() hand it to
## InputBindings.set_prompt_mode.

const PATH := "user://settings.json"
const SCHEMA_VERSION := 1
## The graphics presets (the keys of a level record's `render`; plan §2.8.3).
const GRAPHICS_QUALITIES := ["low", "medium"]
const GRAPHICS_DEFAULT := "medium"
## The web build (single-threaded: the play link) always runs this preset.
const GRAPHICS_WEB := "low"
const GRAPHICS_ARG := "--graphics="

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
	"graphics_quality": GRAPHICS_DEFAULT,   ## low | medium (P14); the web build always runs low
	"prompt_device": "auto",          ## auto | keyboard | pad: the buttons prompts name (P16)
	"bindings": {},                   ## action -> [event dicts]; replaces that action's defaults
	# Audio (P19, plan M6-M9 §2.5): 0..1 on top of the mix's bus levels (0 mutes), applied by the
	# Audio autoload with AudioServer bus volumes; Master ramps to -80 dB while the window is
	# unfocused (or the browser tab hidden) when mute_when_unfocused is on.
	"volume_master": 1.0,
	"volume_music": 0.8,
	"volume_ambience": 0.8,
	"volume_sfx": 1.0,
	"volume_ui": 0.8,
	"mute_when_unfocused": true,
}
const RANGES := {
	"mouse_sensitivity": [0.02, 0.6], "stick_look_speed_deg_s": [60.0, 400.0],
	"fov_deg": [60.0, 100.0], "camera_shake": [0.0, 1.0], "head_bob": [0.0, 1.0],
	"hit_flash": [0.0, 1.0], "vibration": [0.0, 1.0],
	"volume_master": [0.0, 1.0], "volume_music": [0.0, 1.0], "volume_ambience": [0.0, 1.0],
	"volume_sfx": [0.0, 1.0], "volume_ui": [0.0, 1.0],
}
## The "Button prompts" choices (P16; InputBindings.PROMPT_MODES).
const PROMPT_DEVICES := ["auto", "keyboard", "pad"]
const ENUMS := {"sprint_mode": ["hold", "toggle"], "lock_mode": ["toggle", "hold"],
	"graphics_quality": GRAPHICS_QUALITIES, "prompt_device": PROMPT_DEVICES}

signal changed(key: String)

var values: Dictionary = {}
var load_message := ""
var persist := true
var _unsaved := false   ## changed with save=false (live slider drags) and not yet written
## Session-only state that survives sandbox resets but is never written to disk.
var session := {"camera_mode": 0}
## The preset of --graphics=low|medium for this run ("" = none; never saved).
var graphics_override := ""
## The graphics preset in effect (read-only): "low" on the web, else the --graphics flag, else
## the saved setting (resolve_graphics_quality).
var graphics_quality: String:
	get:
		return resolve_graphics_quality(str(get_value("graphics_quality")), graphics_override,
			OS.has_feature("web"))


func _ready() -> void:
	values = DEFAULTS.duplicate(true)
	var args := OS.get_cmdline_user_args()
	persist = not args.has("--no-user-settings")
	var graphics := parse_graphics_arg(args)
	graphics_override = str(graphics.value)
	if str(graphics.error) != "":
		push_warning("[settings] " + str(graphics.error))
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
	if key == "prompt_device":
		InputBindings.set_prompt_mode(str(v))
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


## Rebuilds the input map from the default bindings and the saved overrides, and (P16) sets the
## prompt mode of the "Button prompts" setting.
func apply_bindings() -> void:
	InputBindings.apply(GameData.get_record("input.default"), values.get("bindings", {}))
	InputBindings.set_prompt_mode(str(get_value("prompt_device")))


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


# --------------------------------------------------------------------------- graphics preset (P14)

## The preset in effect for a saved value, a --graphics override ("" = none) and the platform:
## the web build always runs GRAPHICS_WEB; a valid override wins over the saved value; an unknown
## value falls back to GRAPHICS_DEFAULT.
static func resolve_graphics_quality(saved: String, override: String, web: bool) -> String:
	if web:
		return GRAPHICS_WEB
	if GRAPHICS_QUALITIES.has(override):
		return override
	if GRAPHICS_QUALITIES.has(saved):
		return saved
	return GRAPHICS_DEFAULT


## The --graphics=low|medium option of the user args: {"value": "" | quality, "error": ""}. An
## unknown value is an error message (the caller warns) and no override.
static func parse_graphics_arg(args: PackedStringArray) -> Dictionary:
	var out := {"value": "", "error": ""}
	for arg in args:
		if not arg.begins_with(GRAPHICS_ARG):
			continue
		var v := arg.substr(GRAPHICS_ARG.length()).strip_edges().to_lower()
		if GRAPHICS_QUALITIES.has(v):
			out.value = v
			out.error = ""
		else:
			out.value = ""
			out.error = "unknown %s%s (allowed: %s); the saved preset is used" % [GRAPHICS_ARG, v,
				", ".join(PackedStringArray(GRAPHICS_QUALITIES))]
	return out


## Why the saved graphics setting does not decide the preset now ("" when it does): the web
## build, or a --graphics flag. The settings page shows the row disabled with this text.
func graphics_lock_reason() -> String:
	if OS.has_feature("web"):
		return "The web build always uses the Low preset."
	if graphics_override != "":
		return "Set to %s for this run by %s%s." % [graphics_override.capitalize(), GRAPHICS_ARG,
			graphics_override]
	return ""
