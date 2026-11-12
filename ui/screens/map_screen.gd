class_name MapScreen
extends UiScreen
## The map (P27; plan M6-M9 §2.14, §3.10 design 2): ScreenStack SCREENS["map"], opened with M / D-pad
## Down (ScreenStack.HOTKEYS) and pausing the game. It shows a campaign level from its world index:
##   * the picture (WorldIndex.map_image over map_bounds: the world's 1,024 px map), or for a level
##     without one (the Valley) a vector map of its districts and roads;
##   * fog over every chunk not seen (map.seen.<chunk>; a level without chunks has none);
##   * the regions' names and "Recommended stage 4-5" (in the warning colour below it);
##   * the POIs found (bright) and revealed by a vista (dim), sealed places once seen (a lock and
##     "Stage N" until their seal opens), shrines and waystones (bright once visited), exits, the
##     pin, the player and its facing, and the tracked quest's objective (every marker of a
##     multi-marker stage).
## Pan (right stick, W A S D, dragging), three zoom levels (LB / RB, the wheel, - / =), and focus that
## moves between the places (D-pad, left stick, arrows: Godot's geometric focus over the icons; the
## map follows the focus). The panel names the place in focus: "Travel" for a visited waystone or
## shrine whose flags hold - on any campaign level, through the level tabs at the top - emits
## Events.travel_requested(level, id, "fast_travel"), and GameSession's refusal shows on the panel
## (an aware enemy within 40 m, dead, grabbed, holding, not visited, a max_stage below the giant's
## stage). "Pin here" (P / Y: the place in focus, else the map's centre; a right click pins the
## clicked point) and "Clear pin" write the flag map.pin ([x, z, level]). Esc / B or M closes it.
## The first opening sets map.opened (the map tutorial's dismissal).
## args: {"level": a level id to show first} (default: the campaign level being played).
## Read API for tests: entries(), entry(id), selected_id(), select(id), travel_refusal_for(id),
## travel_selected(), pin_here(), clear_pin(), set_zoom(), zoom_level(), show_level(), shown_level(),
## panel_text(), icon(id), to_screen(), map_center(); entries_for() and map_bounds_for() are pure.

const ZOOMS := [1.0, 2.0, 4.0]
const ICON_PX := 22.0
const PAN_PX_PER_S := 520.0
const STICK_DEADZONE := 0.25
const DRAG_START_PX := 6.0
## A selected place outside this share of the view (from its centre) re-centres the map.
const FOLLOW_SHARE := 0.6
const PANEL_W := 300.0
const MARGIN := 24.0
const TOP_BAR := 52.0

const BG := Color(0.035, 0.04, 0.05, 0.985)
const FOG := Color(0.03, 0.035, 0.05, 0.84)
const DIM := Color(0.62, 0.64, 0.68)
const OBJECTIVE := Color(1.0, 0.82, 0.30)
const PIN := Color(1.0, 0.36, 0.32)
const CHECKPOINT := Color(0.55, 0.85, 1.0)
const SEALED := Color(0.78, 0.68, 1.0)
const DISTRICT_COLORS := [Color(0.22, 0.30, 0.22), Color(0.26, 0.28, 0.20), Color(0.24, 0.24, 0.28),
	Color(0.28, 0.25, 0.20), Color(0.22, 0.26, 0.30), Color(0.30, 0.24, 0.24), Color(0.25, 0.27, 0.25)]
const KIND_LABELS := {"settlement": "Settlement", "shrine": "Shrine", "waystone": "Waystone", "ruin": "Ruin",
	"landmark": "Landmark", "camp": "Camp", "lair": "Lair", "boss": "Arena", "forge": "Forge", "gate": "Pass",
	"vista": "Vista", "exit": "Way out", "secret": "Sealed place", "checkpoint": "Checkpoint"}

var view: Control
var travel_button: Button
var pin_button: Button
var clear_pin_button: Button
var close_button: Button
var level_buttons: Dictionary = {}   ## level id -> Button (the tabs)

var _level := ""
var _index: WorldIndex
var _entries: Array = []
var _by_id: Dictionary = {}
var _selected := ""
var _zoom := 0
var _center := Vector2.ZERO
var _bounds := Rect2(-100, -100, 200, 200)
var _image: Texture2D
var _grid: Dictionary = {}
var _regions: Array = []
var _icons: Control
var _icon_nodes: Dictionary = {}
var _title: Label
var _detail: Label
var _result: Label
var _tabs: HBoxContainer
var _press_pos := Vector2.INF
var _dragging := false
var _hint: Label
var _hint_serial := -1


func _ready() -> void:
	var shade := ColorRect.new()
	shade.color = BG
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	_tabs = HBoxContainer.new()
	_tabs.add_theme_constant_override("separation", 8)
	_tabs.position = Vector2(MARGIN, 10)
	add_child(_tabs)
	view = Control.new()
	view.name = "MapView"
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.anchor_right = 1.0
	view.anchor_bottom = 1.0
	view.offset_left = MARGIN
	view.offset_top = TOP_BAR
	view.offset_right = -(PANEL_W + 2.0 * MARGIN)
	view.offset_bottom = -MARGIN - 20.0
	view.draw.connect(_draw_map)
	view.gui_input.connect(_on_view_input)
	view.resized.connect(_relayout)
	add_child(view)
	_icons = Control.new()
	_icons.name = "Icons"
	_icons.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_icons)
	var panel := UiKit.panel(Color(0.07, 0.08, 0.10, 0.97))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -(PANEL_W + MARGIN)
	panel.offset_right = -MARGIN
	panel.offset_top = TOP_BAR
	panel.offset_bottom = -MARGIN - 20.0
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	_title = UiKit.label("", 20, Color(1.0, 0.88, 0.55))
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_title)
	_detail = UiKit.label("", 14, UiKit.TEXT)
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_detail)
	_result = UiKit.label("", 14, UiKit.WARN)
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_result)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)
	# The controls, for the device in use, above the buttons (the stack's footer hint owns the
	# bottom line).
	_hint = UiKit.label(_hint_text(InputBindings.last_device_is_pad()), 12, UiKit.MUTED)
	_hint.name = "Hint"
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_serial = InputBindings.device_serial
	v.add_child(_hint)
	travel_button = UiKit.button("Travel", 18)
	travel_button.pressed.connect(_on_travel_pressed)
	v.add_child(travel_button)
	pin_button = UiKit.button("Pin here", 16)
	pin_button.pressed.connect(pin_here)
	v.add_child(pin_button)
	clear_pin_button = UiKit.button("Clear pin", 16)
	clear_pin_button.pressed.connect(clear_pin)
	v.add_child(clear_pin_button)
	close_button = UiKit.button("Close", 16)
	close_button.pressed.connect(cancel)
	v.add_child(close_button)
	var first := str(args.get("level", ""))
	show_level(first if first != "" else GameSession.current_level_id())


func on_open() -> void:
	WorldState.try_set_flag(Discovery.MAP_OPENED_FLAG, true)
	_relayout()


func first_focus() -> Control:
	var start := _player_anchor_id()
	if start != "" and _icon_nodes.has(start) and (_icon_nodes[start] as Control).visible:
		return _icon_nodes[start]
	for e: Dictionary in _entries:
		var n: Control = _icon_nodes.get(str(e.id))
		if n != null and n.visible:
			return n
	return close_button


## The controls line of the panel (the pad's or the keyboard and mouse's).
static func _hint_text(pad: bool) -> String:
	if pad:
		return "D-pad / left stick: places\nRight stick: pan   LB / RB: zoom\nA: choose   Y: pin   B: close"
	return "Arrows: places   Enter: choose\nW A S D or drag: pan\nWheel or - / =: zoom\nP or right click: pin   Esc / M: close"


## The controls the panel shows now (tests).
func hint_text() -> String:
	return _hint.text if _hint != null else ""


# --------------------------------------------------------------------------- levels and entries

## The campaign levels the map can show: the one being played first, then every other level visited
## (progress.levels_visited) that has a world index.
static func campaign_levels() -> PackedStringArray:
	var out := PackedStringArray()
	var here := GameSession.current_level_id()
	if here != "" and WorldIndex.for_level(here) != null:
		out.append(here)
	var visited: Array = GameSession.progress.get("levels_visited", []) if typeof(GameSession.progress) == TYPE_DICTIONARY else []
	for lv: Variant in visited:
		var id := str(lv)
		if id != "" and not out.has(id) and WorldIndex.for_level(id) != null:
			out.append(id)
	return out


## Shows a level's map (its index, picture, fog and places); false when it has no index.
func show_level(p_level_id: String) -> bool:
	var idx := WorldIndex.for_level(p_level_id)
	if idx == null:
		_level = p_level_id
		_index = null
		_entries = []
		_by_id = {}
		_title.text = "No map of this place"
		_detail.text = ""
		_build_icons()
		_build_tabs()
		return false
	_level = p_level_id
	_index = idx
	_grid = Discovery.chunk_grid(p_level_id)
	_bounds = map_bounds_for(idx)
	_image = null
	if idx.map_image != "" and ResourceLoader.exists(idx.map_image):
		_image = load(idx.map_image) as Texture2D
	_regions = regions_for(p_level_id)
	_entries = entries_for(p_level_id, idx, WorldState.flags)
	_by_id = {}
	for e: Dictionary in _entries:
		_by_id[str(e.id)] = e
	_zoom = 0
	_center = _bounds.get_center()
	var me := player_map_point()
	if me.is_finite():
		_center = me
	_selected = ""
	_build_tabs()
	_build_icons()
	_relayout()
	_update_panel()
	return true


func shown_level() -> String:
	return _level


## Every place on the shown map: [{"id", "type" (poi | checkpoint | exit), "kind", "name", "pos"
## (Vector2 x, z), "found", "revealed", "sealed", "stage", "visited", "fast_travel"}].
func entries() -> Array:
	return _entries


func entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


## The map rectangle of an index: its map_bounds, else the box of its districts (the Valley), else
## of its checkpoints, grown by a margin; never empty.
static func map_bounds_for(idx: WorldIndex) -> Rect2:
	if idx.map_bounds.size.x > 0.0 and idx.map_bounds.size.y > 0.0:
		return idx.map_bounds
	var r := Rect2()
	var first := true
	for d: Variant in idx.districts:
		if typeof(d) != TYPE_DICTIONARY or typeof(d.get("min")) != TYPE_VECTOR2:
			continue
		var dr := Rect2(d.min, (d.max as Vector2) - (d.min as Vector2))
		r = dr if first else r.merge(dr)
		first = false
	for id: Variant in idx.checkpoints:
		var p: Variant = (idx.checkpoints[id] as Dictionary).get("position")
		if typeof(p) == TYPE_VECTOR3:
			var pr := Rect2(Vector2(p.x, p.z), Vector2.ZERO)
			r = pr if first else r.merge(pr)
			first = false
	if first:
		return Rect2(-100, -100, 200, 200)
	return r.grow(maxf(10.0, maxf(r.size.x, r.size.y) * 0.04))


## The region labels of a level: [{"id", "name", "pos" (Vector2), "stages" ([lo, hi] or []), "bounds" (Rect2 of
## map points; P39f: its label stays inside it)}].
static func regions_for(p_level_id: String) -> Array:
	var out: Array = []
	for rec: Dictionary in GameData.records_of_type("region"):
		if str(rec.get("level", "")) != p_level_id or typeof(rec.get("bounds_m")) != TYPE_ARRAY:
			continue
		var b: Array = rec.bounds_m
		var c := Vector2((float(b[0][0]) + float(b[1][0])) * 0.5, (float(b[0][1]) + float(b[1][1])) * 0.5)
		var rs: Variant = rec.get("recommended_stage", [])
		var lo := Vector2(minf(float(b[0][0]), float(b[1][0])), minf(float(b[0][1]), float(b[1][1])))
		var hi := Vector2(maxf(float(b[0][0]), float(b[1][0])), maxf(float(b[0][1]), float(b[1][1])))
		out.append({"id": str(rec.id), "name": str(rec.get("display_name", rec.id)), "pos": c,
			"stages": rs if typeof(rs) == TYPE_ARRAY else [], "bounds": Rect2(lo, hi - lo)})
	return out


## The places of a level's map for these flags. A place of a chunked level shows once its chunk was
## seen (map.seen) - checkpoints also once visited - and POIs once known (found or revealed by a
## vista); sealed places once seen (sealed.<poi>.seen) or found. A shrine or waystone POI with its
## checkpoint inside its radius is shown by the checkpoint alone.
static func entries_for(p_level_id: String, idx: WorldIndex, flags: Dictionary) -> Array:
	var out: Array = []
	var grid := Discovery.chunk_grid(p_level_id)
	var cps: Array = []
	for id: String in idx.checkpoint_ids():
		var c: Dictionary = idx.checkpoints[id]
		var kind := str(c.get("kind", ""))
		if (kind != "shrine" and kind != "waystone") or typeof(c.get("position")) != TYPE_VECTOR3:
			continue
		var p: Vector3 = c.position
		var visited := QuestConditions.truthy(flags.get(GameSession.VISITED_PREFIX + id))
		if not visited and not _seen(grid, flags, p):
			continue
		cps.append(p)
		out.append({"id": id, "type": "checkpoint", "kind": kind, "name": str(c.get("display_name", id)),
			"pos": Vector2(p.x, p.z), "visited": visited, "fast_travel": bool(c.get("fast_travel", true)),
			"stage": int(c.get("max_stage", WorldIndex.ANY_STAGE)), "found": visited, "revealed": false,
			"sealed": false})
	for id: Variant in idx.exits:
		var x: Dictionary = idx.exits[id]
		if typeof(x.get("position")) != TYPE_VECTOR3 or not _seen(grid, flags, x.position):
			continue
		out.append({"id": str(id), "type": "exit", "kind": "exit", "name": str(x.get("display_name", id)),
			"pos": Vector2(x.position.x, x.position.z), "visited": false, "fast_travel": false, "stage": 0,
			"found": true, "revealed": false, "sealed": false})
	var pois := Discovery.poi_table(p_level_id)
	var ids := PackedStringArray(pois.keys())
	ids.sort()
	for id in ids:
		var info: Dictionary = pois[id]
		var p: Vector3 = info.position
		if not p.is_finite():
			continue
		var kind := str(info.kind)
		var found := Discovery.is_found(flags, id)
		var known := Discovery.is_known(flags, id)
		var sealed := false
		if kind == "secret":
			if not found and not QuestConditions.truthy(flags.get(Discovery.sealed_seen_flag(id))):
				continue
			sealed = not Discovery.seal_open(str(info.seal))
		elif not known:
			continue
		if kind == "shrine" or kind == "waystone":
			var covered := false
			for cp: Vector3 in cps:
				if Discovery.flat_distance(cp, p) <= float(info.radius):
					covered = true
					break
			if covered:
				continue
		out.append({"id": id, "type": "poi", "kind": kind, "name": str(info.display_name),
			"pos": Vector2(p.x, p.z), "found": found, "revealed": known and not found, "sealed": sealed,
			"stage": int(info.min_stage), "visited": false, "fast_travel": false})
	return out


static func _seen(grid: Dictionary, flags: Dictionary, p: Vector3) -> bool:
	if grid.is_empty():
		return true
	var chunk := Discovery.chunk_of(grid, p)
	return chunk == "" or QuestConditions.truthy(flags.get(Discovery.seen_flag(chunk)))


# --------------------------------------------------------------------------- the player, the pin, the objective

## The player's map point on the shown level (Vector2.INF when it is not the level being played).
func player_map_point() -> Vector2:
	if _level != GameSession.current_level_id():
		return Vector2.INF
	var p := GameSession.player()
	if p == null or not p.is_inside_tree():
		return Vector2.INF
	var pos := p.global_position - _root_offset()
	return Vector2(pos.x, pos.z)


func _player_yaw() -> float:
	var p := GameSession.player()
	if p == null:
		return 0.0
	return p.camera_rig.yaw if p.camera_rig != null else p.facing_yaw


func _root_offset() -> Vector3:
	if not is_inside_tree():
		return Vector3.ZERO
	var root := get_tree().get_first_node_in_group(LevelRoot.GROUP) as Node3D
	return root.global_position if root != null and root.is_inside_tree() else Vector3.ZERO


## The pin on the shown level (Vector2.INF when there is none or it is on another level).
func pin_point() -> Vector2:
	return Discovery.pin_on(WorldState.flags, _level)


## The tracked quest's objective points on the shown level (the level being played only).
func objective_points() -> Array:
	var out: Array = []
	if _level != GameSession.current_level_id() or not Quests.is_active():
		return out
	for p: Vector3 in HudCompass.objective_positions(Quests.tracked_objective(), _root_offset()):
		out.append(Vector2(p.x, p.z))
	return out


## The checkpoint nearest the player (where the focus starts), else "".
func _player_anchor_id() -> String:
	var me := player_map_point()
	var best := ""
	var best_d := INF
	for e: Dictionary in _entries:
		var d: float = (e.pos as Vector2).distance_to(me) if me.is_finite() else 0.0
		if d < best_d:
			best_d = d
			best = str(e.id)
	return best


# --------------------------------------------------------------------------- view

func zoom_level() -> int:
	return _zoom


## The map point at the view's centre.
func map_center() -> Vector2:
	return _center


func set_zoom(level: int) -> void:
	_zoom = clampi(level, 0, ZOOMS.size() - 1)
	_clamp_center()
	_relayout()


func zoom_by(steps: int) -> void:
	set_zoom(_zoom + steps)


## Pans the map by `px` screen pixels (the selection is dropped: "here" is the centre then).
func pan_by(px: Vector2) -> void:
	_center += px / _scale()
	_clamp_center()
	if _selected != "":
		_selected = ""
		_update_panel()
	_relayout()


func _scale() -> float:
	var vs := view.size if view != null and view.size.x > 1.0 else Vector2(800, 600)
	var base := minf(vs.x / maxf(_bounds.size.x, 1.0), vs.y / maxf(_bounds.size.y, 1.0))
	return base * float(ZOOMS[_zoom])


func _clamp_center() -> void:
	var half := (view.size if view != null else Vector2(800, 600)) * 0.5 / _scale()
	var lo := _bounds.position + half
	var hi := _bounds.end - half
	_center.x = clampf(_center.x, minf(lo.x, _bounds.get_center().x), maxf(hi.x, _bounds.get_center().x))
	_center.y = clampf(_center.y, minf(lo.y, _bounds.get_center().y), maxf(hi.y, _bounds.get_center().y))


## A map point (x, z) on the view (px).
func to_screen(p: Vector2) -> Vector2:
	return view.size * 0.5 + (p - _center) * _scale()


## A view point (px) on the map (x, z).
func to_map(s: Vector2) -> Vector2:
	return _center + (s - view.size * 0.5) / _scale()


func _relayout() -> void:
	if view == null:
		return
	for id: String in _icon_nodes:
		var n: Control = _icon_nodes[id]
		var e: Dictionary = _by_id.get(id, {})
		if e.is_empty():
			continue
		var s := to_screen(e.pos)
		n.position = s - Vector2(ICON_PX, ICON_PX) * 0.5
		# before the first layout every place counts as in view (the focus may start on one)
		n.visible = view.size.x <= 1.0 or Rect2(Vector2.ZERO, view.size).has_point(s)
	view.queue_redraw()


func _build_icons() -> void:
	for c in _icons.get_children():
		_icons.remove_child(c)
		c.queue_free()
	_icon_nodes = {}
	for e: Dictionary in _entries:
		var n := Control.new()
		n.name = "Icon_" + str(e.id).validate_node_name()
		n.size = Vector2(ICON_PX, ICON_PX)
		n.focus_mode = Control.FOCUS_ALL
		n.mouse_filter = Control.MOUSE_FILTER_STOP
		n.tooltip_text = str(e.name)
		n.focus_entered.connect(_on_icon_focus.bind(str(e.id)))
		n.gui_input.connect(_on_icon_input.bind(str(e.id)))
		_icons.add_child(n)
		_icon_nodes[str(e.id)] = n


## The icon control of a place (focus and pad tests), or null.
func icon(id: String) -> Control:
	return _icon_nodes.get(id)


func _build_tabs() -> void:
	for c in _tabs.get_children():
		_tabs.remove_child(c)
		c.queue_free()
	level_buttons = {}
	var levels := campaign_levels()
	if _level != "" and not levels.has(_level) and WorldIndex.for_level(_level) != null:
		levels.insert(0, _level)
	for lv in levels:
		var rec := GameData.get_record(lv)
		var b := UiKit.button(str(rec.get("display_name", lv)), 15)
		b.toggle_mode = true
		b.button_pressed = lv == _level
		b.pressed.connect(show_level.bind(lv))
		_tabs.add_child(b)
		level_buttons[lv] = b
	_tabs.visible = levels.size() > 1


# --------------------------------------------------------------------------- selection and the panel

func selected_id() -> String:
	return _selected


## Selects a place: the panel shows it, and the map follows when it is near the view's edge. False
## for an id that is not on the shown map.
func select(id: String) -> bool:
	if not _by_id.has(id):
		return false
	_selected = id
	var s := to_screen((_by_id[id] as Dictionary).pos)
	var keep := Rect2(view.size * (1.0 - FOLLOW_SHARE) * 0.5, view.size * FOLLOW_SHARE)
	if not keep.has_point(s):
		_center = (_by_id[id] as Dictionary).pos
		_clamp_center()
	_result.text = ""
	_update_panel()
	_relayout()
	return true


func _on_icon_focus(id: String) -> void:
	if _selected != id:
		select(id)


func _on_icon_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			(_icon_nodes[id] as Control).grab_focus()
			select(id)
			if mb.double_click:
				activate(id)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			pin_at((_by_id[id] as Dictionary).pos)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		activate(id)
		accept_event()


## A or Enter on a place: a destination you can travel to puts the focus on "Travel"; otherwise the
## panel says why not.
func activate(id: String) -> void:
	select(id)
	var why := travel_refusal_for(id)
	if why == "":
		travel_button.grab_focus()
	elif (_by_id.get(id, {}) as Dictionary).get("type", "") == "checkpoint":
		_result.text = why


## Why travel to a place would be refused now ("" = it would go): not a waystone or shrine, else
## GameSession.travel_refusal(level, id, "fast_travel") (not visited, flags, max_stage, the blockers).
func travel_refusal_for(id: String) -> String:
	var e: Dictionary = _by_id.get(id, {})
	if e.is_empty() or str(e.get("type", "")) != "checkpoint" or not bool(e.get("fast_travel", true)):
		return "You can only travel to a waystone or a shrine."
	return GameSession.travel_refusal(_level, id, "fast_travel")


## Travels to the selected place (Events.travel_requested, fast_travel): {"ok", "message"} - the
## message also shows on the panel when it is refused.
func travel_selected() -> Dictionary:
	var why := travel_refusal_for(_selected)
	if why != "":
		_result.text = why
		return {"ok": false, "message": why}
	Events.travel_requested.emit(_level, _selected, "fast_travel")
	var r: Dictionary = GameSession.last_travel_result
	if r.is_empty() or not bool(r.get("ok", false)):
		_result.text = str(r.get("message", "You cannot travel now."))
		return {"ok": false, "message": _result.text}
	_result.text = ""
	return {"ok": true, "message": ""}


func _on_travel_pressed() -> void:
	travel_selected()


## Pins the place in focus, else the map's centre. Returns the point.
func pin_here() -> Vector2:
	var p: Vector2 = (_by_id[_selected] as Dictionary).pos if _by_id.has(_selected) else _center
	pin_at(p)
	return p


func pin_at(p: Vector2) -> void:
	WorldState.set_flag(Discovery.PIN_FLAG, [snappedf(p.x, 0.1), snappedf(p.y, 0.1), _level])
	_update_panel()
	view.queue_redraw()


func clear_pin() -> void:
	WorldState.set_flag(Discovery.PIN_FLAG, "")
	_update_panel()
	view.queue_redraw()


func _update_panel() -> void:
	if _title == null:
		return
	var e: Dictionary = _by_id.get(_selected, {})
	clear_pin_button.disabled = not Discovery.pin_of(WorldState.flags).is_finite()
	if e.is_empty():
		var c := _center
		var region := _index.region_at(Vector3(c.x, 0, c.y)) if _index != null else ""
		var rec := GameData.get_record(_level)
		_title.text = str(rec.get("display_name", "The map"))
		_detail.text = "%s\nThe pin goes to the middle of the map." % (str(GameData.get_record(region).get("display_name", ""))
			if region != "" else "Choose a place, or pan the map.")
		travel_button.disabled = true
		return
	_title.text = str(e.name)
	_detail.text = "\n".join(detail_lines(e, _stage(), _index))
	travel_button.disabled = travel_refusal_for(_selected) != ""
	travel_button.visible = str(e.type) == "checkpoint"


func _stage() -> int:
	return GameSession.current_stage()


## The panel's lines for a place: its kind, its region (with the recommended stages), and what it
## means: visited or not and its arrival limit, found or seen from a vista, sealed (the stage it needs).
static func detail_lines(e: Dictionary, stage: int, idx: WorldIndex) -> PackedStringArray:
	var out := PackedStringArray([str(KIND_LABELS.get(str(e.kind), str(e.kind).capitalize()))])
	if idx != null:
		var p: Vector2 = e.pos
		var region := idx.region_at(Vector3(p.x, 0, p.y))
		if region != "":
			var rec := GameData.get_record(region)
			var line := str(rec.get("display_name", region))
			var rs: Variant = rec.get("recommended_stage")
			if typeof(rs) == TYPE_ARRAY and (rs as Array).size() == 2:
				line += " - recommended stage %d-%d" % [int(rs[0]), int(rs[1])]
				if stage < int(rs[0]):
					line += " (you are stage %d)" % stage
			out.append(line)
	match str(e.type):
		"checkpoint":
			out.append("Visited: you can travel here." if bool(e.visited) else "Not visited yet.")
			if int(e.stage) < WorldIndex.ANY_STAGE:
				out.append("Too narrow above stage %d." % int(e.stage))
		"poi":
			if bool(e.sealed):
				out.append("Sealed. Grow to stage %d to open it." % int(e.stage))
			elif bool(e.revealed):
				out.append("Seen from afar: not yet found.")
			else:
				out.append("Found.")
		"exit":
			out.append("A way out of this land.")
	return out


## Everything the panel says now (tests).
func panel_text() -> String:
	return "\n".join([_title.text, _detail.text, _result.text]).strip_edges()


# --------------------------------------------------------------------------- input

func _process(delta: float) -> void:
	if not is_inside_tree() or stack == null or stack.top() != self:
		return
	if _hint != null and InputBindings.device_serial != _hint_serial:
		_hint_serial = InputBindings.device_serial
		_hint.text = _hint_text(InputBindings.last_device_is_pad())
	var v := Vector2(Input.get_axis("look_left", "look_right"), Input.get_axis("look_up", "look_down"))
	if v.length() < STICK_DEADZONE:
		v = Vector2.ZERO
	if v == Vector2.ZERO and not (get_viewport().gui_get_focus_owner() is LineEdit):
		v = Vector2(float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)),
			float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)))
	if v != Vector2.ZERO:
		pan_by(v * PAN_PX_PER_S * minf(delta, 0.1))


func _unhandled_input(event: InputEvent) -> void:
	if stack == null or stack.top() != self:
		return
	if event.is_action_pressed("map_pin"):
		pin_here()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("map") and not is_ui_direction(event):
		close({"closed": "map"})
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		var b := (event as InputEventJoypadButton).button_index
		if b == JOY_BUTTON_LEFT_SHOULDER or b == JOY_BUTTON_RIGHT_SHOULDER:
			zoom_by(1 if b == JOY_BUTTON_RIGHT_SHOULDER else -1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_EQUAL, KEY_KP_ADD, KEY_PAGEUP:
				zoom_by(1)
				get_viewport().set_input_as_handled()
			KEY_MINUS, KEY_KP_SUBTRACT, KEY_PAGEDOWN:
				zoom_by(-1)
				get_viewport().set_input_as_handled()


static func is_ui_direction(event: InputEvent) -> bool:
	for a: String in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action(a):
			return true
	return false


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					zoom_by(1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_press_pos = mb.position
					_dragging = false
				else:
					if not _dragging and _press_pos.is_finite():
						_center = to_map(mb.position)
						_clamp_center()
						_selected = ""
						_update_panel()
						_relayout()
					_press_pos = Vector2.INF
					_dragging = false
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					pin_at(to_map(mb.position))
		view.accept_event()
	elif event is InputEventMouseMotion and _press_pos.is_finite():
		var mm := event as InputEventMouseMotion
		if _dragging or mm.position.distance_to(_press_pos) >= DRAG_START_PX:
			_dragging = true
			pan_by(-mm.relative)
		view.accept_event()


# --------------------------------------------------------------------------- drawing

func _draw_map() -> void:
	var vs := view.size
	view.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.09, 0.10, 0.11))
	if _index == null:
		return
	var font := view.get_theme_default_font()
	var top_left := to_screen(_bounds.position)
	var bottom_right := to_screen(_bounds.end)
	if _image != null:
		view.draw_texture_rect(_image, Rect2(top_left, bottom_right - top_left), false)
	else:
		_draw_vector_map(font)
	if not _grid.is_empty():
		var n: Vector2i = _grid.grid
		for z in n.y:
			for x in n.x:
				if not QuestConditions.truthy(WorldState.flags.get(Discovery.seen_flag("c%d_%d" % [x, z]))):
					var r := Discovery.chunk_rect(_grid, Vector2i(x, z))
					var a := to_screen(r.position)
					view.draw_rect(Rect2(a, to_screen(r.end) - a), FOG)
	# P39f: every mark first, then the labels the layout placed clear of them and of each other
	for e: Dictionary in _entries:
		_draw_entry(e)
	var pin := pin_point()
	if pin.is_finite():
		var s := to_screen(pin)
		view.draw_rect(Rect2(s.x - 1.0, s.y - 2.0, 2.0, 12.0), Color(0.1, 0.05, 0.05))
		HudKit.draw_diamond(view, s + Vector2(0, -5), 7.0, PIN)
	for o: Vector2 in objective_points():
		var s := to_screen(o)
		HudKit.draw_diamond(view, s, 10.0, Color(0, 0, 0, 0.6))
		HudKit.draw_diamond(view, s, 8.0, OBJECTIVE)
	var me := player_map_point()
	if me.is_finite():
		var s := to_screen(me)
		var yaw := _player_yaw()
		var fwd := Vector2(-sin(yaw), -cos(yaw))
		HudKit.draw_pointer(view, s + fwd * 11.0, fwd, 20.0, 15.0, Color(0, 0, 0, 0.7))
		HudKit.draw_pointer(view, s + fwd * 9.0, fwd, 16.0, 11.0, Color(1, 1, 1))
	# the centre: where "Pin here" goes when no place is chosen
	var c := vs * 0.5
	view.draw_rect(Rect2(c.x - 8.0, c.y - 0.5, 16.0, 1.0), Color(1, 1, 1, 0.35))
	view.draw_rect(Rect2(c.x - 0.5, c.y - 8.0, 1.0, 16.0), Color(1, 1, 1, 0.35))
	_labels = layout_labels(font)
	for l: Dictionary in _labels:
		_draw_label(font, l)


func _draw_vector_map(_font: Font) -> void:
	var i := 0
	for d: Variant in _index.districts:
		if typeof(d) != TYPE_DICTIONARY or typeof(d.get("min")) != TYPE_VECTOR2:
			continue
		var a := to_screen(d.min)
		var b := to_screen(d.max)
		var col: Color = DISTRICT_COLORS[i % DISTRICT_COLORS.size()]
		view.draw_rect(Rect2(a, b - a), col)
		view.draw_rect(Rect2(a, b - a), Color(1, 1, 1, 0.15), false, 1.0)
		i += 1   # P39f: the district's name is a label (layout_labels)
	var nodes: PackedVector3Array = _index.road_nodes()
	var edges: PackedInt32Array = _index.road_edges()
	for k in range(edges.size() / 2):
		var a: Vector3 = nodes[edges[2 * k]]
		var b: Vector3 = nodes[edges[2 * k + 1]]
		view.draw_line(to_screen(Vector2(a.x, a.z)), to_screen(Vector2(b.x, b.z)), Color(0.75, 0.66, 0.48, 0.8), 2.0)


func _draw_entry(e: Dictionary) -> void:
	var s := to_screen(e.pos)
	if not Rect2(Vector2(-20, -20), view.size + Vector2(40, 40)).has_point(s):
		return
	match str(e.type):
		"checkpoint":
			var col := CHECKPOINT if bool(e.visited) else Color(CHECKPOINT.r, CHECKPOINT.g, CHECKPOINT.b, 0.45)
			if str(e.kind) == "shrine":
				HudKit.draw_diamond(view, s, 9.0, Color(0, 0, 0, 0.6))
				HudKit.draw_diamond(view, s, 7.0, col)
			else:
				view.draw_rect(Rect2(s.x - 5.0, s.y - 8.0, 10.0, 16.0), Color(0, 0, 0, 0.6))
				view.draw_rect(Rect2(s.x - 3.5, s.y - 6.5, 7.0, 13.0), col)
		"exit":
			view.draw_rect(Rect2(s.x - 7.0, s.y - 7.0, 14.0, 14.0), Color(0, 0, 0, 0.6))
			view.draw_rect(Rect2(s.x - 5.0, s.y - 5.0, 10.0, 10.0), Color(0.95, 0.95, 0.95))
			view.draw_rect(Rect2(s.x - 2.0, s.y - 1.0, 4.0, 6.0), Color(0.1, 0.1, 0.1))
		"poi":
			if bool(e.sealed):
				# a lock: the shackle and the body (its "Stage N" is a label: layout_labels)
				view.draw_rect(Rect2(s.x - 4.0, s.y - 9.0, 8.0, 2.0), SEALED)
				view.draw_rect(Rect2(s.x - 4.0, s.y - 9.0, 2.0, 6.0), SEALED)
				view.draw_rect(Rect2(s.x + 2.0, s.y - 9.0, 2.0, 6.0), SEALED)
				view.draw_rect(Rect2(s.x - 6.0, s.y - 3.0, 12.0, 10.0), SEALED)
			else:
				var col: Color = HudCompass.KIND_COLORS.get(str(e.kind), DIM)
				if bool(e.revealed):
					col = Color(col.r, col.g, col.b, 0.5)
				view.draw_rect(Rect2(s.x - 7.0, s.y - 7.0, 14.0, 14.0), Color(0, 0, 0, 0.6))
				view.draw_rect(Rect2(s.x - 5.0, s.y - 5.0, 10.0, 10.0), col)
	if str(e.id) == _selected:
		HudKit.draw_diamond_outline(view, s, 16.0, Color(1, 1, 1, 0.95), 2.0)


# --------------------------------------------------------------------------- P39f: the labels

## P39f (FOLLOWUPS: "the map's labels overlap"): the map's words - the regions' names with their recommended
## stages (the Valley's district names), the place in focus, the settlements, the sealed places' "Stage N" and,
## zoomed in, every found place's name - are laid out after the marks are drawn, so that no label covers
## another label or any mark (a place's icon, the pin, the objective, the giant's arrow) and none is cut by the
## view's edge: each takes the first of its candidate spots that is free (a place's: above its icon, below, to
## the right, to the left, then the four corners; a region's: its centre, then half-block steps up, down and
## aside), in
## order of importance - the place in focus, the regions, the settlements, the sealed places, the rest - and a
## label with no free spot is left out (the panel names the place in focus; zooming in makes room). The place in
## focus always shows, kept inside the view.
const NAME_PX := 13
const REGION_PX := 15
const REGION_STAGE_PX := 12
const STAGE_PX := 12
const LABEL_GAP := 3.0
const REGION_COLOR := Color(0.95, 0.92, 0.85, 0.9)
const REGION_STAGE_COLOR := Color(0.8, 0.82, 0.86, 0.85)
const NAME_COLOR := Color(0.92, 0.92, 0.9, 0.85)
const SELECTED_COLOR := Color(1, 1, 1, 0.95)

var _labels: Array = []


## The labels drawn now (tests): [{"kind" (selected | region | settlement | sealed | name), "id", "lines":
## [[text, size, color]], "rect" (Rect2 on the view)}], in the order they were placed.
func label_layout() -> Array:
	return _labels


## Every mark drawn on the view now, as rects on it: {"entry:<id>": Rect2, "pin", "objective_<n>", "player"}.
func mark_rects() -> Dictionary:
	var out := {}
	var near := Rect2(Vector2(-20, -20), view.size + Vector2(40, 40))
	for e: Dictionary in _entries:
		var s := to_screen(e.pos)
		if near.has_point(s):
			out["entry:" + str(e.id)] = icon_rect(e, s, str(e.id) == _selected)
	var pin := pin_point()
	if pin.is_finite():
		var s := to_screen(pin)
		out["pin"] = Rect2(s.x - 5.0, s.y - 12.0, 10.0, 22.0)
	var objectives := objective_points()
	for i in objectives.size():
		var s := to_screen(objectives[i])
		out["objective_%d" % i] = Rect2(s - Vector2(10, 10), Vector2(20, 20))
	var me := player_map_point()
	if me.is_finite():
		var s := to_screen(me)
		out["player"] = Rect2(s - Vector2(22, 22), Vector2(44, 44))
	return out


## The rect an entry's icon covers at `s` on the view (the selection's outline with it when `selected`).
static func icon_rect(e: Dictionary, s: Vector2, selected := false) -> Rect2:
	var r := Rect2(s - Vector2(7, 7), Vector2(14, 14))
	match str(e.get("type", "")):
		"checkpoint":
			r = Rect2(s - Vector2(9, 9), Vector2(18, 18)) if str(e.get("kind", "")) == "shrine" \
				else Rect2(s.x - 5.0, s.y - 8.0, 10.0, 16.0)
		"poi":
			if bool(e.get("sealed", false)):
				r = Rect2(s.x - 6.0, s.y - 9.0, 12.0, 16.0)
	if selected:
		r = r.merge(Rect2(s - Vector2(17, 17), Vector2(34, 34)))
	return r


## Lays the labels out on the view as it is now (see the notes above). Returns label_layout()'s rows.
func layout_labels(font: Font) -> Array:
	var out: Array = []
	if font == null or view == null or _index == null:
		return out
	var bounds := Rect2(Vector2.ZERO, view.size)
	var marks := mark_rects()
	var blocked: Array = marks.values()
	var placed: Array = []
	# the place in focus, always shown
	var sel: Dictionary = _by_id.get(_selected, {})
	if not sel.is_empty() and marks.has("entry:" + _selected):
		var lines := _entry_lines(sel, SELECTED_COLOR)
		var r := _place(font, lines, _entry_spots(marks["entry:" + _selected]), blocked, placed, bounds, true)
		out.append({"kind": "selected", "id": _selected, "lines": lines, "rect": r})
		placed.append(r)
	# the regions (the Valley: its districts)
	for reg: Dictionary in _region_labels():
		var lines: Array = reg.lines
		var area: Rect2 = reg.bounds
		var on_view := Rect2(to_screen(area.position), area.size * _scale()) if area.size != Vector2.ZERO else Rect2()
		on_view = on_view.intersection(bounds)
		var r := _place(font, lines, _region_spots(font, lines, to_screen(reg.pos), on_view), blocked, placed, bounds,
			false)
		if r.size != Vector2.ZERO:
			out.append({"kind": "region", "id": str(reg.id), "lines": lines, "rect": r})
			placed.append(r)
	# the places: settlements, then sealed places, then (zoomed in) every found place
	for pass_kind: String in ["settlement", "sealed", "name"]:
		for e: Dictionary in _entries:
			var id := str(e.id)
			if id == _selected or not marks.has("entry:" + id) or _label_kind(e) != pass_kind:
				continue
			var lines := _entry_lines(e, NAME_COLOR)
			var r := _place(font, lines, _entry_spots(marks["entry:" + id]), blocked, placed, bounds, false)
			if r.size != Vector2.ZERO:
				out.append({"kind": pass_kind, "id": id, "lines": lines, "rect": r})
				placed.append(r)
	return out


## Which pass labels an entry ("" = none at this zoom): settlements always, sealed places always (their stage),
## other found places when zoomed in.
func _label_kind(e: Dictionary) -> String:
	if str(e.get("kind", "")) == "settlement":
		return "settlement"
	if bool(e.get("sealed", false)):
		return "sealed"
	if _zoom > 0 and not bool(e.get("revealed", false)):
		return "name"
	return ""


## An entry's label lines: its name (zoomed in, in focus or a settlement) and a sealed place's stage.
func _entry_lines(e: Dictionary, color: Color) -> Array:
	var lines: Array = []
	var named := str(e.id) == _selected or _zoom > 0 or str(e.get("kind", "")) == "settlement"
	if named:
		lines.append([str(e.name), NAME_PX, color])
	if bool(e.get("sealed", false)):
		lines.append(["Stage %d" % int(e.stage), STAGE_PX, SEALED])
	return lines


## The region labels: [{"id", "pos" (map point), "lines"}] - the world's regions with their recommended stages,
## or the Valley's districts.
func _region_labels() -> Array:
	var out: Array = []
	var stage := _stage()
	for reg: Dictionary in _regions:
		var lines: Array = [[str(reg.name).to_upper(), REGION_PX, REGION_COLOR]]
		var st: Array = reg.stages
		if st.size() == 2:
			lines.append(["Recommended stage %d-%d" % [int(st[0]), int(st[1])], REGION_STAGE_PX,
				UiKit.WARN if stage < int(st[0]) else REGION_STAGE_COLOR])
		out.append({"id": str(reg.id), "pos": reg.pos, "lines": lines, "bounds": reg.get("bounds", Rect2())})
	if _image == null and _index != null:
		for d: Variant in _index.districts:
			if typeof(d) != TYPE_DICTIONARY or typeof(d.get("min")) != TYPE_VECTOR2 or str(d.get("display_name", "")) == "":
				continue
			var lo: Vector2 = d.min
			var hi: Vector2 = d.max
			out.append({"id": str(d.get("id", d.display_name)), "pos": (lo + hi) * 0.5, "bounds": Rect2(lo, hi - lo),
				"lines": [[str(d.display_name), NAME_PX, Color(0.9, 0.9, 0.86, 0.85)]]})
	return out


## The size of a block of `lines` ([[text, size, color]]) in `font`.
static func block_size(font: Font, lines: Array) -> Vector2:
	var out := Vector2.ZERO
	for l: Array in lines:
		out.x = maxf(out.x, font.get_string_size(str(l[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[1])).x + 1.0)
		out.y += font.get_height(int(l[1]))
	return out


## A place's label spots round its icon `icon` - above, below, right, left, then the corners - as anchors
## (Vector2 of the block's top-left, given the block's size later): [[side, Vector2]]. _place sizes them.
static func _entry_spots(icon: Rect2) -> Array:
	return [["above", icon], ["below", icon], ["right", icon], ["left", icon], ["above_right", icon],
		["above_left", icon], ["below_right", icon], ["below_left", icon]]


## A region's spots: its centre, then steps of half the block's height up and down (up to six) and half its
## width aside; and every spot of a grid whose centre lies in the region's own rect `area` (on the view; none
## when it is empty), nearest the centre first - a crowded region's label finds the free ground left in it.
static func _region_spots(font: Font, lines: Array, centre: Vector2, area := Rect2()) -> Array:
	var size := block_size(font, lines)
	var offsets: Array = [Vector2.ZERO]
	for k in range(1, 7):
		offsets.append(Vector2(0, -k * size.y * 0.5))
		offsets.append(Vector2(0, k * size.y * 0.5))
	for k in [0, -1, 1, -2, 2, -3, 3]:
		for side in [-1, 1]:
			offsets.append(Vector2(side * size.x * 0.5, k * size.y * 0.5))
	if area.size.x > 1.0 and area.size.y > 1.0:
		var grid: Array = []
		# at most about 16 x 16 spots, however far the map is zoomed in
		var step := Vector2(maxf(maxf(size.x * 0.125, 8.0), area.size.x / 16.0),
			maxf(maxf(size.y * 0.25, 6.0), area.size.y / 16.0))
		var y := area.position.y
		while y <= area.end.y:
			var x := area.position.x
			while x <= area.end.x:
				grid.append(Vector2(x, y) - centre)
				x += step.x
			y += step.y
		grid.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.length_squared() < b.length_squared())
		offsets.append_array(grid)
	var out: Array = []
	for o: Vector2 in offsets:
		out.append(["at", Rect2(centre - size * 0.5 + o, size)])
	return out


## The first spot of `spots` where the block of `lines` covers nothing of `blocked` (marks) and `placed`
## (labels) and lies inside `bounds`; Rect2() when none does - unless `must`, then the first spot kept inside
## `bounds`.
static func _place(font: Font, lines: Array, spots: Array, blocked: Array, placed: Array, bounds: Rect2,
		must: bool) -> Rect2:
	var size := block_size(font, lines)
	var rects: Array = []
	var reach := Rect2()
	for spot: Array in spots:
		var r := _spot_rect(str(spot[0]), spot[1], size)
		rects.append(r)
		reach = r if reach.size == Vector2.ZERO else reach.merge(r)
	# only what lies within reach of a spot can be in the way
	var near: Array = []
	for b: Rect2 in blocked:
		if reach.intersects(b):
			near.append(b)
	for b: Rect2 in placed:
		if reach.intersects(b):
			near.append(b)
	var first: Rect2 = rects[0] if not rects.is_empty() else Rect2()
	for r: Rect2 in rects:
		if not bounds.encloses(r):
			continue
		var free := true
		for b: Rect2 in near:
			if r.intersects(b):
				free = false
				break
		if free:
			return r
	if not must:
		return Rect2()
	first.position = first.position.clamp(bounds.position, bounds.end - first.size)
	return first


## The block of `size` at a spot: "at" (the spot's own rect), or a side of the icon rect `icon`.
static func _spot_rect(side: String, anchor: Rect2, size: Vector2) -> Rect2:
	var c := anchor.get_center()
	match side:
		"above":
			return Rect2(c.x - size.x * 0.5, anchor.position.y - LABEL_GAP - size.y, size.x, size.y)
		"below":
			return Rect2(c.x - size.x * 0.5, anchor.end.y + LABEL_GAP, size.x, size.y)
		"right":
			return Rect2(anchor.end.x + LABEL_GAP, c.y - size.y * 0.5, size.x, size.y)
		"left":
			return Rect2(anchor.position.x - LABEL_GAP - size.x, c.y - size.y * 0.5, size.x, size.y)
		"above_right":
			return Rect2(anchor.end.x, anchor.position.y - size.y, size.x, size.y)
		"above_left":
			return Rect2(anchor.position.x - size.x, anchor.position.y - size.y, size.x, size.y)
		"below_right":
			return Rect2(anchor.end.x, anchor.end.y, size.x, size.y)
		"below_left":
			return Rect2(anchor.position.x - size.x, anchor.end.y, size.x, size.y)
	return Rect2(anchor.position, size)


## Draws a placed label: each line centred in its rect, with a shadow.
func _draw_label(font: Font, l: Dictionary) -> void:
	var r: Rect2 = l.rect
	var y := r.position.y
	for line: Array in l.lines:
		var size := int(line[1])
		var text := str(line[0])
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var p := Vector2(r.position.x + (r.size.x - w) * 0.5, y + font.get_ascent(size))
		var color: Color = line[2]
		view.draw_string(font, p + Vector2(1, 1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(0, 0, 0, 0.8 * color.a))
		view.draw_string(font, p, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
		y += font.get_height(size)
