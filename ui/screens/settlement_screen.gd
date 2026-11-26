class_name SettlementScreen
extends UiScreen
## C4 (decision C4-4): the settlement panel - ScreenStack SCREENS["settlement"], opened at a settlement's builder's
## board (SettlementBoard: Events.ui_screen_requested("settlement", {"settlement": id})) or from the Character menu's
## Settlements tab. It pauses the game. At its top the settlement's name and its tier track (each tier's name: stands,
## being earned, to come). Three tabs (their buttons, Enter on a focused one, the mouse, pad LB / RB):
##   * Work: the projects of the tier being earned - each a row with how many of its needs are met; the chosen one's
##     words, every need (a load to haul and where it lies, a material to bring - with a Give button that takes what is
##     still wanted from the pack -, a deed in the world) met or not, how it is raised (at its site: the giant raises
##     it himself), and what the tier unlocks once all its projects stand;
##   * Trades: what the settlement trades at its tier (each a row; Trade makes it once: SettlementWork.trade);
##   * Tiers: every tier, its words and what it gave or will give.
## Leave (or Esc / pad B) closes it. Giving and trading are refused in a fight (Armour.change_blocked), with the reason.
## args: {"settlement": record id, "player": GiantPlayer}. Focus (P16): the tab row, the list's rows, the chosen row's
## buttons (Give / Trade), Leave; every direction wraps. Read API for tests: tab_names(), show_tab(i),
## show_tab_named(name), select(i), rows_text(), detail_text(), tiers_text(), press_give(item), press_trade(id),
## result_text(); summary_lines(rec) is the static text the Character menu shows.

const TABS := ["Work", "Trades", "Tiers"]
const PANEL_SIZE := Vector2(1000, 620)
const LIFT_PX := 14.0
const GOLD := Color(1.0, 0.86, 0.45)
const LIST_W := 330.0
const DETAIL_W := 620.0
const MET := "[done]"
const NOT_MET := "[ ]"

var settlement_id := ""
var rec: Dictionary = {}
var player: GiantPlayer
var _title: Label
var _track: Label
var _tab_buttons: Array[Button] = []
var _current := 0
var _list: VBoxContainer
var _detail: VBoxContainer
var _actions: HBoxContainer
var _result: Label
var leave_button: Button
var row_buttons: Array[Button] = []
var action_buttons: Array[Button] = []
var _rows: Array = []   ## {"kind": project | trade | tier, "id"}
var _chosen := 0
var _detail_lines := PackedStringArray()


func _ready() -> void:
	settlement_id = str(args.get("settlement", ""))
	rec = SettlementRules.record(settlement_id)
	player = args.get("player") as GiantPlayer
	if player == null and is_inside_tree():
		player = get_tree().get_first_node_in_group("player") as GiantPlayer
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var frame := UiKit.panel(Color(0.08, 0.07, 0.06, 0.97))
	frame.name = "Frame"
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	frame.offset_left = -PANEL_SIZE.x * 0.5
	frame.offset_right = PANEL_SIZE.x * 0.5
	frame.offset_top = -PANEL_SIZE.y * 0.5 - LIFT_PX
	frame.offset_bottom = PANEL_SIZE.y * 0.5 - LIFT_PX
	add_child(frame)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	frame.add_child(v)
	_title = UiKit.label("", 26)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_title)
	_track = UiKit.label("", 14, UiKit.MUTED)
	_track.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_track.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_track.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 0)
	v.add_child(_track)
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(bar)
	for i in TABS.size():
		var b := UiKit.button(str(TABS[i]), 17)
		b.pressed.connect(show_tab.bind(i))
		bar.add_child(b)
		_tab_buttons.append(b)
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 14)
	v.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(LIST_W, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	row.add_child(scroll)
	_list = VBoxContainer.new()
	_list.custom_minimum_size = Vector2(LIST_W - 14, 0)
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)
	var right_scroll := ScrollContainer.new()
	right_scroll.custom_minimum_size = Vector2(DETAIL_W, 0)
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(DETAIL_W - 16, 0)
	right.add_theme_constant_override("separation", 4)
	right_scroll.add_child(right)
	_detail = VBoxContainer.new()
	_detail.add_theme_constant_override("separation", 3)
	right.add_child(_detail)
	_actions = HBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	right.add_child(_actions)
	_result = UiKit.label("", 14, UiKit.GOOD)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(PANEL_SIZE.x - 40, 0)
	v.add_child(_result)
	leave_button = UiKit.button("Leave", 18)
	leave_button.pressed.connect(cancel)
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.add_child(leave_button)
	v.add_child(bottom)
	show_tab(0)


func on_open() -> void:
	refresh()


func first_focus() -> Control:
	if not row_buttons.is_empty():
		return row_buttons[0]
	return leave_button


func focus_rows() -> Array:
	var rows: Array = [_tab_buttons.duplicate()]
	for b in row_buttons:
		rows.append([b])
	if not action_buttons.is_empty():
		rows.append(action_buttons.duplicate())
	rows.append([leave_button])
	return rows


func nav_hint(pad: bool) -> String:
	if pad:
		return "D-pad / left stick: move     LB / RB: tabs     A: select     B: leave"
	return "Arrows / Tab: move     Enter: select     Esc: leave     (or use the mouse)"


func tab_names() -> PackedStringArray:
	return PackedStringArray(TABS)


func current_tab() -> String:
	return str(TABS[_current])


func tab_buttons() -> Array[Button]:
	return _tab_buttons.duplicate()


func show_tab(i: int) -> void:
	if i < 0 or i >= TABS.size():
		return
	_current = i
	_chosen = 0
	for k in _tab_buttons.size():
		UiKit.set_tab_open(_tab_buttons[k], k == i)
	refresh()
	if is_inside_tree():
		refresh_focus()
		if _tab_buttons[i].is_visible_in_tree():
			_tab_buttons[i].grab_focus()


func show_tab_named(tab_name: String) -> void:
	show_tab(TABS.find(tab_name))


func _unhandled_input(event: InputEvent) -> void:
	if stack == null or stack.top() != self:
		return
	var step := UiNav.page_step(event)
	if step != 0:
		show_tab((_current + step + TABS.size()) % TABS.size())
		get_viewport().set_input_as_handled()


func select(i: Variant) -> void:
	var k := int(i)
	if k < 0 or k >= _rows.size():
		return
	_chosen = k
	_refresh_detail()
	for j in row_buttons.size():
		UiKit.set_tab_open(row_buttons[j], j == k)
	if is_inside_tree():
		refresh_focus()


func refresh() -> void:
	if _title == null:
		return
	var st := SettlementWork.state(rec) if not rec.is_empty() else SettlementRules.blank()
	var tier := SettlementRules.tier_of(st)
	_title.text = "%s - %s" % [str(rec.get("display_name", "Settlement")), SettlementRules.tier_name(rec, tier)]
	_track.text = track_text(rec, st)
	_build_rows(st)
	_refresh_detail()
	if is_inside_tree():
		refresh_focus()


## "The Camp (stands) > The Roofed Hall (being earned) > The Stone Ring > The Hearth-hold"
static func track_text(r: Dictionary, st: Dictionary) -> String:
	var tier := SettlementRules.tier_of(st)
	var parts := PackedStringArray()
	for k in SettlementRules.max_tier(r) + 1:
		var nm := SettlementRules.tier_name(r, k)
		if k <= tier:
			parts.append("%s (%s)" % [nm, "stands" if k == tier else "done"])
		elif k == tier + 1:
			parts.append("%s (being earned)" % nm)
		else:
			parts.append(nm)
	return "Tier %d of %d:   %s" % [tier, SettlementRules.max_tier(r), "  >  ".join(parts)]


# --------------------------------------------------------------------------- the rows

func _build_rows(st: Dictionary) -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	row_buttons.clear()
	_rows.clear()
	var ctx := SettlementWork.context()
	match current_tab():
		"Work":
			var tier := SettlementRules.tier_of(st)
			if tier >= SettlementRules.max_tier(rec):
				_note("%s stands at its last tier. Nothing more is asked of you here." % str(rec.get("display_name", "")))
			else:
				_section("For %s" % SettlementRules.tier_name(rec, tier + 1))
				for p: Dictionary in SettlementRules.current_projects(rec, st):
					var s := SettlementRules.project_status(rec, str(p.id), st, ctx)
					var mark := "raised" if bool(s.raised) else ("ready to raise" if bool(s.ready) else "%d of %d" % [int(s.met), int(s.total)])
					_row("%s  - %s" % [str(s.name), mark], {"kind": "project", "id": str(p.id)})
		"Trades":
			var open := SettlementRules.trades_open(rec, st)
			if open.is_empty():
				_note("%s has nothing to trade yet." % str(rec.get("display_name", "")))
			for t: Dictionary in open:
				_row(SettlementRules.trade_text(t), {"kind": "trade", "id": str(t.id)})
			for t: Dictionary in rec.get("trades", []):
				if not open.has(t):
					_note("From %s: %s" % [SettlementRules.tier_name(rec, int(t.get("requires_tier", 0))), SettlementRules.trade_text(t)])
		"Tiers":
			for k in SettlementRules.max_tier(rec) + 1:
				_row("%d  %s" % [k, SettlementRules.tier_name(rec, k)], {"kind": "tier", "id": str(k)})
	_chosen = clampi(_chosen, 0, maxi(0, _rows.size() - 1))
	for k in row_buttons.size():
		UiKit.set_tab_open(row_buttons[k], k == _chosen)


func _section(text: String) -> void:
	_list.add_child(UiKit.label(text, 15, GOLD))


func _note(text: String) -> void:
	var l := UiKit.label(text, 13, UiKit.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(LIST_W - 20, 0)
	_list.add_child(l)


func _row(text: String, data: Dictionary) -> void:
	var b := UiKit.button(text, 14)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(LIST_W - 20, 0)
	var i := _rows.size()
	b.pressed.connect(select.bind(i))
	b.focus_entered.connect(_on_row_focus.bind(i))
	_list.add_child(b)
	row_buttons.append(b)
	_rows.append(data)


func _on_row_focus(i: int) -> void:
	if i != _chosen:
		_chosen = i
		_refresh_detail()
		for k in row_buttons.size():
			UiKit.set_tab_open(row_buttons[k], k == i)


# --------------------------------------------------------------------------- the detail

func _refresh_detail() -> void:
	if _detail == null:
		return
	for c in _detail.get_children():
		_detail.remove_child(c)
		c.queue_free()
	for b in action_buttons:
		if is_instance_valid(b):
			b.queue_free()
	action_buttons.clear()
	_detail_lines = PackedStringArray()
	if _rows.is_empty():
		return
	var r: Dictionary = _rows[clampi(_chosen, 0, _rows.size() - 1)]
	var st := SettlementWork.state(rec)
	match str(r.kind):
		"project":
			for l: Dictionary in project_detail(rec, str(r.id), st, SettlementWork.context()):
				_dline(str(l.text), l.get("color", UiKit.TEXT), int(l.get("size", 14)))
				if str(l.get("give", "")) != "":
					_action("Give %s" % str(l.get("give_name", "")), press_give.bind(str(l.give), str(r.id)),
						not bool(l.get("can_give", false)))
		"trade":
			var t := SettlementRules.trade(rec, str(r.id))
			_dline(SettlementRules.trade_text(t), GOLD, 17)
			for g: Dictionary in t.get("give", []):
				_dline("You give %d %s (you carry %d)" % [int(g.count), _item_name(str(g.item)), WorldState.count_of(str(g.item))])
			for g: Dictionary in t.get("get", []):
				_dline("You get %d %s" % [int(g.count), _item_name(str(g.item))])
			var can := SettlementRules.can_trade(rec, st, str(r.id), WorldState.inventory)
			if not bool(can.ok):
				_dline(str(can.message), UiKit.WARN)
			_action("Trade", press_trade.bind(str(r.id)), not bool(can.ok))
		"tier":
			var k := int(r.id)
			var t := SettlementRules.tier_rec(rec, k)
			var state := "stands" if k <= SettlementRules.tier_of(st) else ("being earned" if k == SettlementRules.tier_of(st) + 1 else "to come")
			_dline("%s (%s)" % [str(t.get("name", "")), state], GOLD, 17)
			_dline(str(t.get("text", "")))
			if k <= SettlementRules.tier_of(st) and str(t.get("settled_text", "")) != "":
				_dline(str(t.settled_text), UiKit.MUTED)
			for u: Dictionary in t.get("unlocks", []):
				_dline("%s: %s" % [str(u.kind).capitalize(), str(u.text)], UiKit.GOOD if k <= SettlementRules.tier_of(st) else UiKit.TEXT, 13)
			var names := PackedStringArray()
			for p: Dictionary in t.get("projects", []):
				names.append(str(p.name))
			if not names.is_empty():
				_dline("Earned by: " + ", ".join(names), UiKit.MUTED, 13)


## The chosen project's lines: [{"text", "color", "size", "give" (an item a Give button takes), "give_name",
## "can_give"}] - its words, each need with its state, how it is raised, what its tier unlocks (static: tests).
static func project_detail(r: Dictionary, pid: String, st: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var s := SettlementRules.project_status(r, pid, st, ctx)
	if s.is_empty():
		return out
	out.append({"text": str(s.name), "color": GOLD, "size": 18})
	out.append({"text": str(s.text)})
	out.append({"text": "What it needs", "color": GOLD, "size": 15})
	for n: Dictionary in s.needs:
		var count := " (%d of %d)" % [int(n.have), int(n.want)] if int(n.want) > 1 else ""
		var line := "%s  %s%s" % [MET if bool(n.met) else NOT_MET, str(n.text), count]
		var l := {"text": line, "color": UiKit.GOOD if bool(n.met) else UiKit.TEXT}
		if str(n.kind) == "give" and not bool(n.met):
			var check := SettlementRules.can_give(r, st, pid, str(n.item), ctx.get("inventory", {}))
			l["give"] = str(n.item)
			l["give_name"] = _item_name(str(n.item))
			l["can_give"] = bool(check.ok)
			l.text = "%s   - you carry %d" % [line, int((ctx.get("inventory", {}) as Dictionary).get(str(n.item), 0))]
		out.append(l)
		if str(n.kind) == "haul" and not bool(n.met) and str(n.where) != "":
			out.append({"text": "      It lies at " + str(n.where) + ". Take it up there (E) and carry it here.",
				"color": UiKit.MUTED, "size": 13})
	if bool(s.raised):
		out.append({"text": "Raised.", "color": UiKit.GOOD})
	elif bool(s.get("auto", false)):
		out.append({"text": "The folk do this themselves once it is done - behind your back.", "color": UiKit.MUTED, "size": 13})
	elif bool(s.ready):
		out.append({"text": "Everything is ready: go to its site and %s (E)." % str(s["raise"]).to_lower(), "color": UiKit.GOOD})
	else:
		out.append({"text": "When all of it is done, you raise it yourself at its site: %s." % str(s["raise"]).to_lower(),
			"color": UiKit.MUTED, "size": 13})
	if not bool(s.stage_ok):
		out.append({"text": "It needs a giant of stage %d." % int(s.min_stage), "color": UiKit.WARN})
	var tier := int(s.tier)
	out.append({"text": "Once %s stands, it gives" % SettlementRules.tier_name(r, tier), "color": GOLD, "size": 15})
	for u: Dictionary in SettlementRules.unlocks(r, tier):
		out.append({"text": "%s: %s" % [str(u.kind).capitalize(), str(u.text)], "size": 13})
	return out


static func _item_name(id: String) -> String:
	return str(GameData.get_record(id).get("display_name", id))


func _dline(text: String, color: Variant = UiKit.TEXT, size := 14) -> void:
	var l := UiKit.label(text, size, color if color is Color else UiKit.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(DETAIL_W - 20, 0)
	_detail.add_child(l)
	_detail_lines.append(text)


func _action(text: String, callable: Callable, disabled: bool) -> void:
	var b := UiKit.button(text, 16)
	b.disabled = disabled
	b.pressed.connect(callable)
	_actions.add_child(b)
	action_buttons.append(b)


# --------------------------------------------------------------------------- actions

## Gives what is still wanted of `item` to project `pid` (the chosen one when ""): SettlementWork.give.
func press_give(item: String, pid := "") -> Dictionary:
	if pid == "" and not _rows.is_empty():
		pid = str((_rows[_chosen] as Dictionary).get("id", ""))
	var r := SettlementWork.give(rec, pid, item)
	_show_result(r)
	return r


func press_trade(tid: String) -> Dictionary:
	var r := SettlementWork.trade(rec, tid)
	_show_result(r)
	return r


func _show_result(r: Dictionary) -> void:
	_result.text = str(r.get("message", ""))
	_result.add_theme_color_override("font_color", UiKit.GOOD if bool(r.get("ok", false)) else UiKit.WARN)
	var keep := _chosen
	refresh()
	select(keep)


func result_text() -> String:
	return _result.text if _result != null else ""


func rows_text() -> PackedStringArray:
	var out := PackedStringArray()
	for b in row_buttons:
		out.append(b.text)
	return out


func detail_text() -> String:
	return "\n".join(_detail_lines)


func tiers_text() -> String:
	return _track.text if _track != null else ""


## The Character menu's Settlements tab and the journal: each settlement as lines - its tier and what is being earned,
## each current project with its needs met (static: no screen).
static func summary_lines(r: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var st := SettlementWork.state(r)
	var tier := SettlementRules.tier_of(st)
	out.append("# %s: %s (tier %d of %d)" % [str(r.display_name), SettlementRules.tier_name(r, tier), tier, SettlementRules.max_tier(r)])
	if tier >= SettlementRules.max_tier(r):
		out.append("Stands at its last tier.")
		return out
	var ctx := SettlementWork.context()
	out.append("Being earned: %s" % SettlementRules.tier_name(r, tier + 1))
	for p: Dictionary in SettlementRules.current_projects(r, st):
		var s := SettlementRules.project_status(r, str(p.id), st, ctx)
		var parts := PackedStringArray()
		for n: Dictionary in s.needs:
			parts.append("%s%s" % ["done: " if bool(n.met) else "", str(n.text)])
		out.append("  %s - %s" % [str(s.name), "ready to raise" if bool(s.ready) else "; ".join(parts)])
	return out
