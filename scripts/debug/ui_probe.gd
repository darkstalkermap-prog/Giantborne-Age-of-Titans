class_name UiProbe
extends Node
## P45 (plan M10 §3.5 items 2, 4 and 5; §2.12 "Shader stalls"): a passive probe of the menus and of
## the frames around them, for the Chromium checks (tools/web/creator_check.mjs) and for the native
## runs under Xvfb. main.gd makes one with --ui-probe (or --ui-probe=<tour>); without the argument
## nothing of it exists. It never changes the game: it reads the screen stack, the focus and the
## clock, and prints lines a check can follow.
##
##   UI_PROBE {"t":"state", ...}   whenever what a player would see changes: the mode ("title",
##       "valley" - the campaign, the Valley and the world alike - or "sandbox"), the "level" ("level.valley",
##       "level.world"), "loading", the top screen ("title", "creator", "shrine", ...),
##       the title's "warming", the shrine's "tab", the creator's "context", "category", "changed" and
##       "history", the focused control's text ("focus"; "focus_tab" when it is one of the shrine's tab
##       buttons, whose words a tab's own buttons may share), the interact prompt ("prompt"), whether the
##       mouse is captured, and the texture tiers the giants in the tree were built with ("tiers").
##   UI_PROBE {"t":"stall", "mark", "first_ms", "median_ms", "ratio", "frames", ...}   once per mark,
##       STEADY_FRAMES frames after it (or when the next mark cuts it short): the longest of the
##       FIRST_FRAMES frame intervals that follow the mark against the median of the frames after
##       them. The marks: "title" (first_ms is the worst frame from the start until New Game enables,
##       the median the title's frames after that), "creator" (the creator opens from the title),
##       "level" (the loading screen lets go of a level; "load_worst_ms" is the longest frame behind
##       it, reported apart: a load is not a stall), "shrine_creator" ("Change your look..." at a
##       shrine).
##   UI_PROBE {"t":"skin", ...}   with a tour, SkinnedRig's counters and the monitors' texture and
##       mesh memory, draw calls and primitives when a mark's frames are done.
##   UI_PROBE {"t":"done", "tour", "ok", "why"}   a tour's end (it then quits).
##
## Frame intervals are wall-clock time between two _process calls (the probe runs first in the frame,
## PROCESS_MODE_ALWAYS), so a frame that compiled shaders while drawing shows in the next interval.
## Under software rendering every figure is indicative; the ratio is judged against the run's own
## median (stall_ratio_ok).
##
## Tours (native runs, where no browser presses the keys; the keys go through
## Input.parse_input_event, as a keyboard's would):
##   --ui-probe=new_game   the title -> Enter (New Game) -> the creator: PageDown, R (randomize the
##                         category), Ctrl+Z (undo), R, Ctrl+Enter (Begin) -> the level -> quits
##   --ui-probe=shrine     a level entered with --continue at a shrine: E (rest) -> the shrine screen:
##                         Up to the tab buttons, Right until the Appearance tab has the focus, Enter,
##                         Down to "Change your look...", Enter -> the creator -> quits
## --ui-probe-shots=<dir> saves a PNG of the window at each mark's end (tours only).

const TAG := "UI_PROBE"
## The frames after a mark whose longest is the mark's "first frame" (the frame that drew the new
## view, and the two after it: a shader compiled on first use lands in one of them).
const FIRST_FRAMES := 3
## The frames after those whose median the first is judged against.
const STEADY_FRAMES := 40
## §2.12: a first frame may take this many median frames.
const STALL_RATIO := 3.0
## A stall under this many milliseconds is none, whatever the ratio (a 2 ms median makes 7 ms "3.5x").
const STALL_FLOOR_MS := 25.0
## ui/screens/shrine/appearance_tab.gd's TITLE and CHANGE (the tab has no class name).
const APPEARANCE_TAB := "Appearance"
const CHANGE_LOOK := "Change your look..."
const TOURS := ["", "new_game", "shrine"]
const TOUR_STEP_LIMIT_S := 240.0

var tour := ""
var shots_dir := ""
var _last_usec := 0
var _state := {}
var _frame := 0
## The open measurement: {"mark", "first": [ms], "steady": [ms], "extra": {}} or {}.
var _open := {}
var _title_worst_ms := 0.0
var _title_done := false
var _load_worst_ms := 0.0
var _was_loading := false
## Kept across scene loads (Begin and Continue reload the main scene, and the probe with it).
static var _had_creator := false
static var _results: Array = []
static var _step := 0
var _step_started_ms := 0
var _wait_frames := 0
var _keys: Array = []


## The probe the command line asks for (null without --ui-probe).
static func from_args(args: PackedStringArray) -> UiProbe:
	var probe: UiProbe = null
	var shots := ""
	for arg in args:
		if arg == "--ui-probe" or arg.begins_with("--ui-probe="):
			probe = UiProbe.new()
			probe.name = "UiProbe"
			var t := arg.get_slice("=", 1) if arg.contains("=") else ""
			probe.tour = t if t in TOURS else ""
		elif arg.begins_with("--ui-probe-shots="):
			shots = arg.substr(17)
	if probe != null:
		probe.shots_dir = shots
	return probe


## The median of `values` (0 for none).
static func median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var v := values.duplicate()
	v.sort()
	var n := v.size()
	return float(v[n / 2]) if n % 2 == 1 else (float(v[n / 2 - 1]) + float(v[n / 2])) * 0.5


## A mark's result from its first and steady frame intervals (ms).
static func stall_result(mark: String, first: Array, steady: Array) -> Dictionary:
	var worst := 0.0
	for f: float in first:
		worst = maxf(worst, f)
	var med := median(steady)
	var ratio := worst / med if med > 0.0 else 0.0
	return {"t": "stall", "mark": mark, "first_ms": snappedf(worst, 0.01), "median_ms": snappedf(med, 0.01),
		"ratio": snappedf(ratio, 0.01), "frames": steady.size(), "ok": stall_ratio_ok(worst, med)}


## §2.12: the first frame is no stall when it is within STALL_RATIO median frames (or under the floor).
static func stall_ratio_ok(first_ms: float, median_ms: float) -> bool:
	return first_ms <= STALL_FLOOR_MS or (median_ms > 0.0 and first_ms <= STALL_RATIO * median_ms)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -1000
	_last_usec = Time.get_ticks_usec()
	_step_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0
	_last_usec = now
	_frame += 1
	var s := read_state()
	if _frame > 1:
		_account(ms, s)
	if s != _state:
		_note_marks(_state, s)
		_state = s
		var line := s.duplicate()
		line["t"] = "state"
		line["frame"] = _frame
		_say(line)
	if tour != "":
		_run_tour(s)


## What a player would see now (see the header).
func read_state() -> Dictionary:
	var main := get_parent()
	var stack: ScreenStack = main.get("screen_stack") as ScreenStack if main != null else null
	var top: UiScreen = stack.top() if stack != null and is_instance_valid(stack) else null
	var s := {"mode": GameSession.mode_name(), "level": GameSession.current_level_id() if GameSession.mode != GameSession.Mode.TITLE else "",
		"loading": main != null and main.has_method("is_loading") and bool(main.call("is_loading")),
		"top": top.screen_name if top != null else "", "warming": false, "tab": "", "context": "", "category": "",
		"changed": false, "history": 0, "focus": "", "focus_tab": false, "prompt": "", "captured": Input.mouse_mode == Input.MOUSE_MODE_CAPTURED,
		"tiers": []}
	if top is TitleScreen:
		s.warming = (top as TitleScreen).warming()
	elif top is ShrineScreen:
		var tab := (top as ShrineScreen).current_tab()
		s.tab = tab.tab_title() if tab != null else ""
	elif top is CreatorScreen:
		var c := top as CreatorScreen
		s.context = c.context
		s.category = c.current_category()
		s.changed = c.is_changed()
		s.history = c.history.size()
	var focus := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	if focus != null:
		s.focus = str(focus.get("text")) if focus.get("text") != null else str(focus.name)
		s.focus_tab = top is ShrineScreen and (top as ShrineScreen).tab_buttons().has(focus)
	var player := get_tree().get_first_node_in_group("player") as GiantPlayer
	if player != null and player.interact != null:
		s.prompt = player.interact.current_prompt()
	var tiers := {}
	for m in get_tree().get_nodes_in_group(GiantModel.GROUP):
		var t := GiantLook.built_tier(m)
		if t != "":
			tiers[t] = true
	s.tiers = tiers.keys()
	s.tiers.sort()
	return s


# --------------------------------------------------------------------------- frames and marks

func _account(ms: float, s: Dictionary) -> void:
	if not _title_done and str(s.mode) == "title":
		_title_worst_ms = maxf(_title_worst_ms, ms)
	if bool(s.loading) or bool(_state.get("loading", false)):
		_load_worst_ms = maxf(_load_worst_ms, ms)
	if _open.is_empty():
		return
	if (_open.first as Array).size() < FIRST_FRAMES:
		(_open.first as Array).append(ms)
	else:
		(_open.steady as Array).append(ms)
		if (_open.steady as Array).size() >= STEADY_FRAMES:
			_close_mark()


func _begin_mark(mark: String, extra: Dictionary = {}, first: Array = []) -> void:
	if not _open.is_empty():
		_close_mark()
	_open = {"mark": mark, "first": first.duplicate(), "steady": [], "extra": extra}


func _close_mark() -> void:
	var r := stall_result(str(_open.mark), _open.first, _open.steady)
	r.merge(_open.extra as Dictionary)
	_open = {}
	_results.append(r)
	_say(r)
	if tour != "":
		_say_skin(str(r.mark))
		_shot(str(r.mark))


func _note_marks(was: Dictionary, s: Dictionary) -> void:
	if was.is_empty():
		_was_loading = bool(s.loading)
	# The title: the worst frame from the start until New Game and Continue enable.
	if not _title_done and str(s.top) == "title" and not bool(s.warming):
		_title_done = true
		_begin_mark("title", {"warmed": bool(was.get("warming", false))},
			[_title_worst_ms, _title_worst_ms, _title_worst_ms])
	var creator := str(s.top) == "creator"
	if creator and str(was.get("top", "")) != "creator":
		_begin_mark("shrine_creator" if str(s.context) == "shrine" else "creator",
			{"again": _had_creator, "tiers": s.tiers})
		_had_creator = true
	if _was_loading and not bool(s.loading) and str(s.mode) != "title":
		_begin_mark("level", {"load_worst_ms": snappedf(_load_worst_ms, 0.01), "level": s.level, "tiers": s.tiers})
	_was_loading = bool(s.loading)


func _say(line: Dictionary) -> void:
	print("%s %s" % [TAG, JSON.stringify(line)])


func _say_skin(mark: String) -> void:
	var totals: Dictionary = SkinnedRig.totals.duplicate()
	_say({"t": "skin", "mark": mark, "totals": totals,
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.01),
		"buffer_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.01),
		"draw_calls": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"primitives": int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		"objects": int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))})


func _shot(mark: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(shots_dir.path_join("%s_%s.png" % [tour, mark]))


# --------------------------------------------------------------------------- tours

## True once `mark`'s stall line was printed.
func _has_result(mark: String) -> bool:
	for r: Dictionary in _results:
		if str(r.mark) == mark:
			return true
	return false


func _key(keycode: Key, ctrl := false) -> void:
	for pressed: bool in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.ctrl_pressed = ctrl
		ev.pressed = pressed
		_keys.append(ev)


func _next(wait_frames := 20) -> void:
	_step += 1
	_step_started_ms = Time.get_ticks_msec()
	_wait_frames = wait_frames


func _end_tour(ok: bool, why: String) -> void:
	if not _open.is_empty():
		_close_mark()
	_say({"t": "done", "tour": tour, "ok": ok, "why": why, "step": _step})
	tour = ""
	get_tree().quit(0 if ok else 1)


func _run_tour(s: Dictionary) -> void:
	if not _keys.is_empty():
		Input.parse_input_event(_keys.pop_front())   # one event a frame: press, then release
		return
	if _wait_frames > 0:
		_wait_frames -= 1
		return
	if float(Time.get_ticks_msec() - _step_started_ms) / 1000.0 > TOUR_STEP_LIMIT_S:
		_end_tour(false, "step %d timed out with %s" % [_step, JSON.stringify(s)])
		return
	if tour == "new_game":
		_tour_new_game(s)
	else:
		_tour_shrine(s)


func _tour_new_game(s: Dictionary) -> void:
	match _step:
		0:
			if _has_result("title") and str(s.top) == "title" and str(s.focus).begins_with("New Game"):
				_key(KEY_ENTER)
				_next()
		1:
			if _has_result("creator") and str(s.top) == "creator":
				_key(KEY_PAGEDOWN)
				_next()
		2:
			_key(KEY_R)
			_next()
		3:
			if not bool(s.changed):
				_end_tour(false, "R did not change the look")
				return
			_key(KEY_Z, true)
			_next()
		4:
			if bool(s.changed):
				_end_tour(false, "Ctrl+Z did not undo the change")
				return
			_key(KEY_R)
			_next()
		5:
			_key(KEY_ENTER, true)
			_next()
		6:
			if _has_result("level"):
				_end_tour(true, "")


func _tour_shrine(s: Dictionary) -> void:
	match _step:
		0:
			if _has_result("level") and str(s.top) == "":
				if str(s.prompt).begins_with("Rest"):
					_key(KEY_E)
					_next()
				else:
					# Not facing the shrine: a short step back, which turns the giant about.
					_key(KEY_S)
					_wait_frames = 30
		1:
			if str(s.top) == "shrine":
				if not bool(s.focus_tab):
					_key(KEY_UP)   # from the open tab's rows up to the row of tab buttons
					_wait_frames = 6
				elif str(s.focus).begins_with(APPEARANCE_TAB):
					_key(KEY_ENTER)
					_next()
				else:
					_key(KEY_RIGHT)
					_wait_frames = 6
		2:
			if str(s.tab) != APPEARANCE_TAB:
				_end_tour(false, "Enter on the Appearance tab's button opened %s" % s.tab)
			elif str(s.focus) == CHANGE_LOOK:
				_key(KEY_ENTER)
				_next()
			else:
				_key(KEY_DOWN)
				_wait_frames = 6
		3:
			if _has_result("shrine_creator"):
				_end_tour(true, "")
