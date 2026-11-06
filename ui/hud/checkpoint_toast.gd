extends HudWidget
## Checkpoint toast (plan §2.10.1; P06): a short line top-left, (12..352, 52..86) above the
## debug panel, for every Events.checkpoint_saved and checkpoint_loaded: "Checkpoint saved",
## "Checkpoint (saving is off)", "Checkpoint (kept in memory)" (a test level in the sandbox),
## "Checkpoint NOT saved (play continues)" (a write failure, in the warning colour; GameSession
## also posts the reason as a HUD message), "Checkpoint loaded". It shows for SHOW_S and fades
## over FADE_S; the HUD is paused with the game, so it waits while a screen is open.
## P20: a checkpoint the level's world index (or its node) names is named after a colon -
## "Checkpoint saved: Grove Shrine", "Game loaded: Forest road waystone" (GameSession
## .checkpoint_display_name); one without a name keeps the plain line.

const SHOW_S := 2.6
const FADE_S := 0.5
const MAX_FRAME_S := 0.1

var _panel: PanelContainer
var _label: Label
var _left := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel = HudKit.panel(Color(0.05, 0.06, 0.08, 0.82))
	_panel.offset_left = 12
	_panel.offset_right = 352
	_panel.offset_top = 52
	_panel.offset_bottom = 86   # P16: the 15 pt line and the panel margins need 34 px (it grew past 80)
	add_child(_panel)
	_label = HudKit.label("", HudKit.TEXT, UiKit.GOOD)
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_panel.add_child(_label)
	_panel.visible = false
	Events.checkpoint_saved.connect(_on_checkpoint_saved)
	Events.checkpoint_loaded.connect(_on_checkpoint_loaded)


## The toast text for checkpoint_saved(ok, message): "" message = written. place (P20): the
## checkpoint's display name ("" = none), shown after a colon when the checkpoint was written.
static func saved_text(ok: bool, message: String, place := "") -> String:
	if not ok:
		return "Checkpoint NOT saved (play continues)"
	if message == "":
		return "Checkpoint saved: %s" % place if place != "" else "Checkpoint saved"
	return "Checkpoint (%s)" % message


## The toast text for checkpoint_loaded(source): continue | death | debug | menu | load. place
## (P20): the checkpoint's display name ("" = none).
static func loaded_text(source: String, place := "") -> String:
	var text := "Checkpoint loaded"
	match source:
		"continue":
			text = "Game loaded"
		"debug":
			text = "Checkpoint reloaded (debug)"
	return "%s: %s" % [text, place] if place != "" else text


func show_text(text: String, color: Color) -> void:
	_label.text = text
	_label.add_theme_color_override("font_color", color)
	_left = SHOW_S + FADE_S
	_panel.modulate.a = 1.0
	_panel.visible = true


## What the toast shows right now ("" when hidden).
func visible_text() -> String:
	return _label.text if _panel != null and _panel.visible else ""


func _on_checkpoint_saved(_tick: int, checkpoint_id: String, ok: bool, message: String) -> void:
	show_text(saved_text(ok, message, GameSession.checkpoint_display_name(checkpoint_id)),
		UiKit.GOOD if ok else UiKit.WARN)


func _on_checkpoint_loaded(_tick: int, checkpoint_id: String, source: String) -> void:
	show_text(loaded_text(source, GameSession.checkpoint_display_name(checkpoint_id)), UiKit.TEXT)


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	# A long frame (the level load right after a checkpoint_loaded) must not eat the display time.
	_left -= minf(delta, MAX_FRAME_S)
	if _left <= 0.0:
		_panel.visible = false
	elif _left < FADE_S:
		_panel.modulate.a = _left / FADE_S


func layout_controls() -> Dictionary:
	return {"checkpoint_toast": _panel}
