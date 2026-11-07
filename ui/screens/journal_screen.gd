class_name JournalScreen
extends UiScreen
## The journal (P27; plan M6-M9 §2.14, §3.10 design 4): ScreenStack SCREENS["journal"], opened with
## J / D-pad Right (ScreenStack.HOTKEYS), pausing the game. One scrolling page:
##   * Quests: every active quest - its title, its step ("Step 2 of 5"), the current stage's
##     objective and the region (or the Valley's district) it points to - with "Track"
##     (Quests.track: the compass, the objective marker and the tracker follow it; "Tracked" on the
##     tracked one);
##   * Waiting: active quests whose stage waits on something (its waiting_text, e.g. "Waiting:
##     stage 5"), each with "Track" too;
##   * Completed quests;
##   * Oaths: the outcome of every oath settled (oath.<march|wood|crown>.outcome);
##   * Sealed places: those seen (sealed.<poi>.seen) whose seal is still shut, with the stage they
##     need;
##   * Regions: each region's M7 note while one exists ("The woodfolk and their troubles come with
##     the next build.").
## Pad and keyboard: the Track buttons top to bottom, then Close (wrapping; the page scrolls with the
## focus). J or Esc / B closes it.
## Read API for tests: sections() (pure but for the autoloads it reads), track_button(id),
## lines(), press_track(id).

const OATHS := [["march", "Brannock's oath"], ["wood", "The Greywood's oath"], ["crown", "The crown's oath"]]
const GOLD := Color(1.0, 0.86, 0.45)

var close_button: Button
## Track buttons by quest id.
var track_buttons: Dictionary = {}

var _list: VBoxContainer
var _scroll: ScrollContainer
var _order: Array[Button] = []
var _lines: PackedStringArray = []


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.07, 0.08, 0.10, 0.97))
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -400
	frame.offset_right = 400
	frame.offset_top = -310
	frame.offset_bottom = 310
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	frame.add_child(v)
	var title := UiKit.label("Journal", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	v.add_child(_scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	_scroll.add_child(_list)
	close_button = UiKit.button("Close", 18)
	close_button.pressed.connect(cancel)
	v.add_child(close_button)
	rebuild()


func on_open() -> void:
	rebuild()


func first_focus() -> Control:
	return _order[0] if not _order.is_empty() else close_button


## The Track buttons top to bottom, then Close (P16 rows, wrapping).
func focus_rows() -> Array:
	var rows: Array = []
	for b: Button in _order:
		rows.append([b])
	rows.append([close_button])
	return rows


func _unhandled_input(event: InputEvent) -> void:
	if stack == null or stack.top() != self:
		return
	if event.is_action_pressed("journal") and not MapScreen.is_ui_direction(event):
		close({"closed": "journal"})
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------------- content

## What the journal lists now: {"active": [{"id", "title", "text", "step", "steps", "region",
## "tracked"}], "waiting": [the same and "waiting"], "completed": [{"id", "title"}], "oaths":
## [{"oath", "name", "outcome"}], "sealed": [{"id", "name", "stage", "region"}], "regions": [{"id",
## "name", "note"}]}.
static func sections() -> Dictionary:
	var out := {"active": [], "waiting": [], "completed": [], "oaths": [], "sealed": [], "regions": []}
	var tracked := Quests.tracked_id()
	var idx := Quests.level_index()
	for id in Quests.active_quest_ids():
		var o := Quests.objective_for(id)
		if o.is_empty():
			continue
		# M7 polish: an objective on another level names the door it leads through, not the door's region.
		var via := str(o.get("via_text", ""))
		var row := {"id": id, "title": str(o.get("title", id)), "text": str(o.get("text", "")),
			"step": int(o.get("stage_index", 0)) + 1, "steps": int(o.get("stage_count", 1)),
			"region": via if via != "" else place_name(o.get("position", Vector3.INF), idx), "tracked": id == tracked}
		var waiting := str(o.get("waiting_text", ""))
		if waiting != "":
			row["waiting"] = waiting
			(out.waiting as Array).append(row)
		else:
			(out.active as Array).append(row)
	for rec: Dictionary in Quests.quest_records():
		var id := str(rec.get("id", ""))
		if Quests.quest_state(id) == Quests.COMPLETED:
			(out.completed as Array).append({"id": id, "title": str(rec.get("display_name", id))})
	for oath: Array in OATHS:
		var outcome: Variant = WorldState.get_flag("oath.%s.outcome" % oath[0], "")
		if QuestConditions.truthy(outcome):
			(out.oaths as Array).append({"oath": str(oath[0]), "name": str(oath[1]), "outcome": str(outcome)})
	for rec: Dictionary in GameData.records_of_type("poi"):
		if str(rec.get("kind", "")) != "secret":
			continue
		var id := str(rec.get("id", ""))
		if not QuestConditions.truthy(WorldState.get_flag(Discovery.sealed_seen_flag(id))) \
				or Discovery.seal_open(str(rec.get("seal", ""))):
			continue
		(out.sealed as Array).append({"id": id, "name": str(rec.get("display_name", id)),
			"stage": int(rec.get("min_stage", 0)),
			"region": str(GameData.get_record(str(rec.get("region", ""))).get("display_name", ""))})
	for rec: Dictionary in GameData.records_of_type("region"):
		var note := str(rec.get("m7_note", ""))
		if note != "":
			(out.regions as Array).append({"id": str(rec.id), "name": str(rec.get("display_name", rec.id)), "note": note})
	return out


## The name of the region (the world) or district (the Valley) holding a position ("" when none).
static func place_name(pos: Variant, idx: WorldIndex) -> String:
	if idx == null or typeof(pos) != TYPE_VECTOR3 or not (pos as Vector3).is_finite():
		return ""
	var region := idx.region_at(pos)
	if region != "":
		return str(GameData.get_record(region).get("display_name", region))
	var district := idx.district_at(pos)
	return idx.display_name(district) if district != "" else ""


## Rebuilds the page from sections() (after a Track, and when it opens).
func rebuild() -> void:
	var focused_id := ""
	for id: String in track_buttons:
		if is_instance_valid(track_buttons[id]) and (track_buttons[id] as Button).has_focus():
			focused_id = id
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	track_buttons = {}
	_order = []
	_lines = []
	var s := sections()
	var stage := GameSession.current_stage()
	_header("Quests")
	if (s.active as Array).is_empty():
		_line("No quest in hand.", UiKit.MUTED)
	for q: Dictionary in s.active:
		_quest_row(q, _step_text(q))
	if not (s.waiting as Array).is_empty():
		_header("Waiting")
		for q: Dictionary in s.waiting:
			_quest_row(q, "%s  -  %s" % [_step_text(q), str(q.waiting)])
	if not (s.completed as Array).is_empty():
		_header("Completed")
		for q: Dictionary in s.completed:
			_line(str(q.title), UiKit.MUTED)
	if not (s.oaths as Array).is_empty():
		_header("Oaths")
		for o: Dictionary in s.oaths:
			_line("%s: %s" % [str(o.name), str(o.outcome).capitalize()], UiKit.TEXT)
	if not (s.sealed as Array).is_empty():
		_header("Sealed places")
		for p: Dictionary in s.sealed:
			var needs := "Grow to stage %d" % int(p.stage)
			if stage >= int(p.stage):
				needs = "You are big enough now (stage %d)" % int(p.stage)
			_line("%s%s  -  %s" % [str(p.name), " (%s)" % str(p.region) if str(p.region) != "" else "", needs],
				UiKit.WARN if stage < int(p.stage) else UiKit.GOOD)
	if not (s.regions as Array).is_empty():
		_header("Regions")
		for r: Dictionary in s.regions:
			_line("%s: %s" % [str(r.name), str(r.note)], UiKit.MUTED)
	refresh_focus()
	if focused_id != "" and track_buttons.has(focused_id):
		(track_buttons[focused_id] as Button).grab_focus()


## "Step 2 of 5: <objective>" ("Step 2 of 5" alone for a stage without objective text).
static func _step_text(q: Dictionary) -> String:
	var step := "Step %d of %d" % [int(q.step), maxi(int(q.steps), int(q.step))]
	return "%s: %s" % [step, str(q.text)] if str(q.text) != "" else step


func _header(text: String) -> void:
	var l := UiKit.label(text, 18, GOLD)
	_list.add_child(l)
	_lines.append("# " + text)


func _line(text: String, color: Color) -> void:
	var l := UiKit.label(text, 14, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(720, 0)
	_list.add_child(l)
	_lines.append(text)


func _quest_row(q: Dictionary, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var b := UiKit.button("Tracked" if bool(q.tracked) else "Track", 14)
	b.custom_minimum_size = Vector2(110, 0)
	b.pressed.connect(press_track.bind(str(q.id)))
	row.add_child(b)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UiKit.label(str(q.title) + ("   (%s)" % str(q.region) if str(q.region) != "" else ""), 16,
		GOLD if bool(q.tracked) else UiKit.TEXT)
	v.add_child(title)
	var body := UiKit.label(text, 14, UiKit.TEXT)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(580, 0)
	v.add_child(body)
	row.add_child(v)
	_list.add_child(row)
	track_buttons[str(q.id)] = b
	_order.append(b)
	_lines.append("%s%s: %s" % ["* " if bool(q.tracked) else "", str(q.title), text])


## Tracks a quest (Quests.track) and rebuilds the page. False when it is not active.
func press_track(quest_id: String) -> bool:
	var ok := Quests.track(quest_id)
	rebuild()
	if track_buttons.has(quest_id):
		(track_buttons[quest_id] as Button).grab_focus()
	return ok


func track_button(quest_id: String) -> Button:
	return track_buttons.get(quest_id)


## The page as text lines ("# Section", "* " before the tracked quest; tests).
func lines() -> PackedStringArray:
	return _lines
