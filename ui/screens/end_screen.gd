class_name EndScreen
extends UiScreen
## The end of the slice (plan §2.10.2, §3.15 design 6; P13): ScreenStack SCREENS["end"], requested
## by Quests on Events.slice_completed (the Crown of the First King is claimed). It pauses the game
## and shows the time played, deaths, level and growth stage, and how Thornwick's story ended (the
## village outcome, decision 11), labelled as a vertical slice with prototype pacing (§6 risk 17).
## "Continue exploring" closes it (play goes on); "Quit to title" asks GameSession for the title.
## args (Quests.end_summary()): {"time_s", "deaths", "level", "stage", "outcome"}; a missing key is
## read live (GameSession.stats, the player, the flag quest.village.outcome).

const TITLE := "The Crown of the First King is yours"
const SUBTITLE := "Giantborn - vertical slice, prototype pacing"
const OUTCOME_LINES := {
	"help_cache": "Thornwick: you returned their stolen cache",
	"help_ogre": "Thornwick: you drove off the ogre",
	"intimidate": "Thornwick: they opened the bridge in fear",
	"force": "Thornwick: you smashed your way through",
}
const NO_OUTCOME_LINE := "Thornwick: their fate was never settled"

var continue_button: Button
var quit_button: Button
var _lines: VBoxContainer
var _shown: PackedStringArray = []


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var frame := UiKit.panel(Color(0.06, 0.06, 0.08, 0.97))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -340
	frame.offset_right = 340
	frame.offset_top = -230
	frame.offset_bottom = 230
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	frame.add_child(v)
	var title := UiKit.label(TITLE, 28, Color(1.0, 0.86, 0.45))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := UiKit.label(SUBTITLE, 15, UiKit.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	v.add_child(_lines)
	continue_button = UiKit.button("Continue exploring", 20)
	continue_button.pressed.connect(press_continue)
	v.add_child(continue_button)
	quit_button = UiKit.button("Quit to title", 18)
	quit_button.pressed.connect(press_quit)
	v.add_child(quit_button)


func on_open() -> void:
	_shown = lines_for(_summary())
	for c in _lines.get_children():
		c.queue_free()
	for i in _shown.size():
		var l := UiKit.label(_shown[i], 20 if i == _shown.size() - 1 else 18,
			Color(1.0, 0.86, 0.45) if i == _shown.size() - 1 else UiKit.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_lines.add_child(l)


func first_focus() -> Control:
	return continue_button


## Continue exploring, then Quit to title, wrapping (P16).
func focus_rows() -> Array:
	return [[continue_button], [quit_button]]


## The village outcome line ("Thornwick: you drove off the ogre").
static func outcome_line(outcome: String) -> String:
	return str(OUTCOME_LINES.get(outcome, NO_OUTCOME_LINE))


## "24:13" (minutes:seconds), "1:02:03" past an hour.
static func format_time(seconds: float) -> String:
	var s := maxi(0, int(seconds))
	var minutes := floori(s / 60.0)
	if s >= 3600:
		return "%d:%02d:%02d" % [floori(s / 3600.0), minutes % 60, s % 60]
	return "%d:%02d" % [minutes, s % 60]


## The lines the screen shows for a summary: time, deaths, level and stage, the outcome line last.
static func lines_for(summary: Dictionary) -> PackedStringArray:
	var deaths := int(summary.get("deaths", 0))
	return PackedStringArray([
		"Time: %s" % format_time(float(summary.get("time_s", 0.0))),
		"Deaths: %d" % deaths,
		"Level %d, growth stage %d" % [int(summary.get("level", 1)), int(summary.get("stage", 1))],
		outcome_line(str(summary.get("outcome", ""))),
	])


## The summary from args, completed live where a key is missing.
func _summary() -> Dictionary:
	var live := Quests.end_summary()
	var out := args.duplicate()
	for k: String in live:
		if not out.has(k):
			out[k] = live[k]
	return out


## The lines shown now.
func visible_lines() -> PackedStringArray:
	return _shown


## "Continue exploring": back to the Valley.
func press_continue() -> void:
	close({"continue": true})


## "Quit to title" (GameSession reloads into the title screen).
func press_quit() -> void:
	close({"quit": true})
	Events.mode_change_requested.emit("title", {})


## Esc / pad B is "Continue exploring".
func cancel() -> void:
	press_continue()
