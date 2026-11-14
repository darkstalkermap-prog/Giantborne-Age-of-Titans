class_name EndScreen
extends UiScreen
## The end of the prologue (plan §2.10.2, §3.15 design 6; P13; P26: plan M6-M9 §5.6, decision 10):
## ScreenStack SCREENS["end"], requested by Quests on Events.slice_completed (the Crown of the First
## King is claimed). It pauses the game and shows "Prologue complete - the Valley of Broken Kings":
## the time played, deaths, level and growth stage, and how Thornwick's story ended (the village
## outcome, decision 11), with prototype pacing (§6 risk 17). "Continue" (focused) closes it - play
## goes on, the Kings' Door behind the altar now open, and a HUD line points at it; "Quit to title"
## asks GameSession for the title.
## args (Quests.end_summary()): {"time_s", "deaths", "level", "stage", "outcome"}; a missing key is
## read live (GameSession.stats, the player, the flag quest.village.outcome).
## P36 (plan M6-M9 §5.7, §5.9): the campaign's end - args {"campaign": true, ...} from the Stone Throne
## (StoneThrone, once quest.world_main completes: campaign.completed). The screen reads "The Giant King":
## the time, deaths, level and stage, how each power's oath was won (or that it was not), Skarn's fate,
## and the champion's outcome last; its outcome keys ("march", "wood", "crown", "corvane", "skarn",
## "champion": campaign_summary()) are read live where missing. "Continue" leaves the giant free to
## roam the world (a HUD line says so); "Quit to title" as before.

const TITLE := "Prologue complete"
const SUBTITLE := "The Valley of Broken Kings - prototype pacing"
## The HUD line Continue leaves behind (the way on: the world's first stage names it too).
const CONTINUE_HINT := "Behind the crown's altar, the Kings' Door stands open."
const OUTCOME_LINES := {
	"help_cache": "Thornwick: you returned their stolen cache",
	"help_ogre": "Thornwick: you drove off the ogre",
	"intimidate": "Thornwick: they opened the bridge in fear",
	"force": "Thornwick: you smashed your way through",
}
const NO_OUTCOME_LINE := "Thornwick: their fate was never settled"
## P36: the campaign's end (see the header).
const CAMPAIGN_TITLE := "The Giant King"
const CAMPAIGN_SUBTITLE := "The Old Kingdom - prototype pacing"
const CAMPAIGN_CONTINUE_HINT := "The Old Kingdom is yours to roam: every road is open to its Giant King."
const MARCH_LINES := {"help": "Brannock: you freed the March's roads", "intimidate": "Brannock: the town paid you tribute",
	"force": "Brannock: you took its oath by fear"}
const WOOD_LINES := {"slay": "The Greywood: you slew the Troll Matriarch", "slain": "The Greywood: you slew the Troll Matriarch",
	"drive": "The Greywood: you drove the Troll Matriarch out", "fled": "The Greywood: you drove the Troll Matriarch out"}
const CROWN_LINES := {"parley": "Aldmere: you made peace with the crown", "sabotage": "Aldmere: you burned the kingdom's war engines",
	"breach": "Aldmere: you broke the Iron Regiment"}
const CORVANE_LINES := {"spared": " and spared Corvane", "slain": " and struck Corvane down"}
const SKARN_LINES := {"saved": "Skarn: you broke the siege and saved the steading", "rebuilt": "Skarn: you raised its burned halls again",
	"burned": "Skarn: its halls burned", "": "Skarn: you never came to its aid"}
const CHAMPION_LINES := {"yielded_talk": "Harrok knelt without a blow: the clans crowned you",
	"spared": "You broke Harrok and spared him: the clans crowned you",
	"slain": "You slew Harrok: you sit the throne of an empty Moot"}
const NO_OATH_LINES := {"march": "Brannock swore you no oath", "wood": "The Greywood swore you no oath",
	"crown": "Aldmere swore you no oath"}

var continue_button: Button
var quit_button: Button
var _lines: VBoxContainer
var _shown: PackedStringArray = []
var _title: Label
var _sub: Label


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
	_title = UiKit.label(TITLE, 28, Color(1.0, 0.86, 0.45))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_sub = UiKit.label(SUBTITLE, 15, UiKit.MUTED)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_sub)
	_lines = VBoxContainer.new()
	_lines.add_theme_constant_override("separation", 4)
	v.add_child(_lines)
	continue_button = UiKit.button("Continue", 20)
	continue_button.pressed.connect(press_continue)
	v.add_child(continue_button)
	quit_button = UiKit.button("Quit to title", 18)
	quit_button.pressed.connect(press_quit)
	v.add_child(quit_button)


func on_open() -> void:
	var campaign := is_campaign()
	_title.text = CAMPAIGN_TITLE if campaign else TITLE
	_sub.text = CAMPAIGN_SUBTITLE if campaign else SUBTITLE
	_shown = campaign_lines(_campaign_summary()) if campaign else lines_for(_summary())
	for c in _lines.get_children():
		c.queue_free()
	for i in _shown.size():
		var l := UiKit.label(_shown[i], 20 if i == _shown.size() - 1 else (16 if campaign else 18),
			Color(1.0, 0.86, 0.45) if i == _shown.size() - 1 else UiKit.TEXT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_lines.add_child(l)


## P36: true for the campaign's end (args "campaign").
func is_campaign() -> bool:
	return bool(args.get("campaign", false))


func first_focus() -> Control:
	return continue_button


## Continue, then Quit to title, wrapping (P16).
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


## "Continue": back to the Valley, its exit open (a HUD line points at the Kings' Door) - P36: after the
## campaign's end, back to the world to roam it.
func press_continue() -> void:
	var hint := CAMPAIGN_CONTINUE_HINT if is_campaign() else CONTINUE_HINT
	close({"continue": true})
	Events.hud_message.emit(hint, "info")


## "Quit to title" (GameSession reloads into the title screen).
func press_quit() -> void:
	close({"quit": true})
	Events.mode_change_requested.emit("title", {})


## Esc / pad B is "Continue".
func cancel() -> void:
	press_continue()


# --------------------------------------------------------------------------- P36: the campaign's end

## The outcome keys of the campaign's end from the world's flags: "march", "wood", "crown" (each oath's
## outcome, "" when it was not won), "corvane" and "champion" (boss.<x>.outcome) and "skarn" (saved,
## rebuilt, burned or "").
static func campaign_summary(flags: Dictionary) -> Dictionary:
	var skarn := ""
	if QuestConditions.truthy(flags.get("world.skarn.saved")):
		skarn = "saved"
	elif QuestConditions.truthy(flags.get("world.skarn.rebuilt")):
		skarn = "rebuilt"
	elif QuestConditions.truthy(flags.get("world.skarn.burned")):
		skarn = "burned"
	var out := {"skarn": skarn, "corvane": str(flags.get("boss.corvane.outcome", "")),
		"champion": str(flags.get("boss.harrok.outcome", ""))}
	for key: String in ["march", "wood", "crown"]:
		var done := QuestConditions.truthy(flags.get("oath.%s.done" % key))
		out[key] = str(flags.get("oath.%s.outcome" % key, "")) if done else ""
	return out


## The oath line of one power ("" outcome: it swore no oath).
static func oath_line(key: String, outcome: String, corvane := "") -> String:
	if outcome == "":
		return str(NO_OATH_LINES.get(key, ""))
	match key:
		"march":
			return str(MARCH_LINES.get(outcome, "Brannock: its oath is yours"))
		"wood":
			return str(WOOD_LINES.get(outcome, "The Greywood: its oath is yours"))
		"crown":
			var line := str(CROWN_LINES.get(outcome, "Aldmere: its oath is yours"))
			if outcome == "breach":
				line += str(CORVANE_LINES.get(corvane, ""))
			return line
	return ""


## The lines the campaign's end shows: time, deaths, level and stage, the three oaths, Skarn, and the
## champion's outcome last.
static func campaign_lines(summary: Dictionary) -> PackedStringArray:
	var out := PackedStringArray([
		"Time: %s" % format_time(float(summary.get("time_s", 0.0))),
		"Deaths: %d" % int(summary.get("deaths", 0)),
		"Level %d, growth stage %d" % [int(summary.get("level", 1)), int(summary.get("stage", 1))]])
	for key: String in ["march", "wood", "crown"]:
		out.append(oath_line(key, str(summary.get(key, "")), str(summary.get("corvane", ""))))
	out.append(str(SKARN_LINES.get(str(summary.get("skarn", "")), SKARN_LINES[""])))
	out.append(str(CHAMPION_LINES.get(str(summary.get("champion", "")), "The clans crowned you at the Moot")))
	return out


## The campaign's summary from args, completed live where a key is missing.
func _campaign_summary() -> Dictionary:
	var out := _summary()
	var live := campaign_summary(WorldState.flags)
	for k: String in live:
		if not out.has(k):
			out[k] = live[k]
	return out
