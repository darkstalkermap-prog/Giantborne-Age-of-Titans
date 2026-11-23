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
##       M10 gate (LD-2): "first" lists the FIRST_FRAMES intervals and "first_draw" the part of each the
##       rendering server spent drawing (frame_pre_draw to frame_post_draw: a shader compiled on first use is
##       there; the rest is the frame's scripts and physics), "median_draw_ms" the same for the steady frames.
##   UI_PROBE {"t":"skin", ...}   with a tour, SkinnedRig's counters and the monitors' texture and
##       mesh memory, draw calls and primitives when a mark's frames are done.
##   UI_PROBE {"t":"bench", "mark", "skin_ms", ...}   with --ui-probe-bench, when a mark's frames are
##       done and the player's skinned rig is in the tree: the skin's CPU a frame (§2.12: Web <= 0.35 ms,
##       native <= 0.10) - SkinnedRig._drive_tree, the AnimationTree's advance, the skeleton's update
##       and PoseBrainModifier's pass in a tight loop, the best of BENCH_BATCHES batches of BENCH_RUNS; "giants" is
##       how many skinned giants were in the tree (2 with the creator's preview open at a shrine), and
##       "modifier_runs" proves the modifier ran in the loop. "skin_springs_ms" (the W30 merge) is the same loop with
##       the skeleton advanced in manual mode, so every modifier runs - the springs and SecondaryMotion's limits too
##       (§2.12's row with secondary motion: Web <= 0.45 ms, native <= 0.15 since 0.11.0-m11, was 0.12) - and
##       "chains" the chains they ran.
##   UI_PROBE {"t":"thumbs", "key", "made", "frames", "worst_ms", "median_ms", "after_median_ms", "ratio"}   P57 (plan
##       M11 §2.7: the thumbnails' cost decides the Web's rule): once per option grid opened in the creator, when its
##       page's thumbnails are made and THUMBS_AFTER_FRAMES frames have followed - the frames while they were made
##       (one a frame) against the median of the frames after. The state's "grid" is the open grid's row ("" when
##       none) and "thumbs" how many thumbnails were made; the marks "grid" (a grid opens) and "pick" (the first
##       option put on in a grid: a piece's part loaded and drawn for the first time) are measured as the others.
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
##   --ui-probe=level      any level (--level=, --mode=): when the level's mark is done it prints the
##                         giant's own draw calls and primitives (UI_PROBE {"t":"giant_draw"}: the frame's
##                         counts with the giant's models shown and hidden, each the median of five frames
##                         of the paused level, "still" when neither moved, and the shown meshes' surfaces)
##                         and quits
##   --ui-probe=shrine     a level entered with --continue at a shrine: E (rest) -> the shrine screen:
##                         Up to the tab buttons, Right until the Appearance tab has the focus, Enter,
##                         Down to "Change your look...", Enter -> the creator -> quits
##   --ui-probe=continue   (M10 gate, LD-2) the title with a saved game (--save-dir=): Enter (Continue) -> the
##                         level -> quits: a player's way into a saved world, through the title's warm-up and
##                         the loading screen's
##   --ui-probe=intro      (A5) a New Game's first world entry (--mode=world): the intro cutscene opens; it is
##                         skipped at --ui-probe-skip= ("open": the frame it opens, before its first tick; a tick;
##                         "end": not skipped) with --ui-probe-skip-key= (enter, esc, space, pad_a, pad_b,
##                         pad_start); INTRO_SETTLE_FRAMES later one UI_PROBE {"t":"intro", ...} line says what
##                         the play looks like (the tree paused, the input context, the HUD, the camera, the giant
##                         shown and on the ground, the cutscene's nodes and Stonebacks left, a screen open, the
##                         music's state), then W is held and the giant must move; then it quits
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
const TOURS := ["", "new_game", "shrine", "level", "continue", "intro", "titan"]
## The intro tour (A5): the frames let pass after the cutscene closes before the state is read, and the frames W
## is held for after that.
const INTRO_SETTLE_FRAMES := 30
const INTRO_WALK_FRAMES := 45
## The frames after a grid's thumbnails are made that the "thumbs" line's median is taken over (P57).
const THUMBS_AFTER_FRAMES := 20
const BENCH_BATCHES := 5
const BENCH_RUNS := 200
const TOUR_STEP_LIMIT_S := 240.0
## The level tour's draw-call readings (M10 gate, LD-6): the frames let pass after the tree is paused or the
## giant hidden, and the frames each reading takes.
const DRAW_SETTLE_FRAMES := 6
const DRAW_SAMPLE_FRAMES := 5

var tour := ""
var shots_dir := ""
## The intro tour's skip point ("open", a tick, "end") and key.
var skip_at := "open"
var skip_key := "enter"
var _intro := {}
## B4: the titan tour's titan ("ogre_king", "rootwarden"), the giant's stage for it (0: as it is), whether the giant
## then dies in the fight (and what the retry looks like). Kept across the death's reload (static).
static var titan := "ogre_king"
static var titan_stage := 0
static var titan_die := false
static var _titan_out := {}
var bench := false
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
var _giant_draw := {}
## The rendering server's draw time: when the frame's draw began, and the last finished draw (ms).
## P57: the open grid's thumbnails: {"key", "made_before", "during": [ms], "after": [ms], "done": bool} or {}.
var _thumbs := {}
var _picked_in_grid := false
var _pre_draw_usec := 0
var _last_draw_ms := 0.0


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
		for arg in args:
			if arg.begins_with("--ui-probe-skip="):
				probe.skip_at = arg.substr(16)
			elif arg.begins_with("--ui-probe-skip-key="):
				probe.skip_key = arg.substr(20)
			elif arg.begins_with("--ui-probe-titan="):
				titan = arg.substr(17)
			elif arg.begins_with("--ui-probe-stage="):
				titan_stage = int(arg.substr(17))
		titan_die = args.has("--ui-probe-die")
		probe.shots_dir = shots
		probe.bench = args.has("--ui-probe-bench")
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
	RenderingServer.frame_pre_draw.connect(_on_pre_draw)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _exit_tree() -> void:
	if RenderingServer.frame_pre_draw.is_connected(_on_pre_draw):
		RenderingServer.frame_pre_draw.disconnect(_on_pre_draw)
	if RenderingServer.frame_post_draw.is_connected(_on_post_draw):
		RenderingServer.frame_post_draw.disconnect(_on_post_draw)


func _on_pre_draw() -> void:
	_pre_draw_usec = Time.get_ticks_usec()


func _on_post_draw() -> void:
	_last_draw_ms = float(Time.get_ticks_usec() - _pre_draw_usec) / 1000.0


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
		s["grid"] = c.grid_row().key if c.grid_open() and c.grid_row() != null else ""
		s["thumbs"] = c.thumbnails.made if c.thumbnails != null else 0
		s["thumbs_busy"] = c.thumbnails != null and c.thumbnails.busy()
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
	_account_thumbs(ms, s)
	if _open.is_empty():
		return
	if (_open.first as Array).size() < FIRST_FRAMES:
		(_open.first as Array).append(ms)
		(_open.first_draw as Array).append(_last_draw_ms)
	else:
		(_open.steady as Array).append(ms)
		(_open.steady_draw as Array).append(_last_draw_ms)
		if (_open.steady as Array).size() >= STEADY_FRAMES:
			_close_mark()


## P57: the frames of an open grid while its thumbnails are made, then THUMBS_AFTER_FRAMES after; one "thumbs" line.
func _account_thumbs(ms: float, s: Dictionary) -> void:
	if _thumbs.is_empty():
		return
	if str(s.get("grid", "")) != str(_thumbs.key) and not bool(_thumbs.done):
		_thumbs = {}   # the grid closed before its page was done
		return
	if not bool(_thumbs.done):
		(_thumbs.during as Array).append(ms)
		if not bool(s.get("thumbs_busy", false)) and (_thumbs.during as Array).size() > 1:
			_thumbs.done = true
		return
	(_thumbs.after as Array).append(ms)
	if (_thumbs.after as Array).size() < THUMBS_AFTER_FRAMES:
		return
	var during: Array = _thumbs.during
	var worst: float = during.max()
	var after_med := median(_thumbs.after)
	var cache := _thumb_cache()
	var parts := GiantModel.part_stats()
	_say({"t": "thumbs", "key": _thumbs.key, "made": int(s.get("thumbs", 0)) - int(_thumbs.made_before),
		"pictures": cache != null and cache.enabled,
		"work_max_ms": snappedf(float((cache.work_ms as Array).max()), 0.1) if cache != null and not cache.work_ms.is_empty() else 0.0,
		"readback_max_ms": snappedf(float((cache.readback_ms as Array).max()), 0.1) if cache != null and not cache.readback_ms.is_empty() else 0.0,
		"part_loads": int(parts.loads), "part_load_max_ms": parts.load_max_ms, "part_load_ms": parts.load_ms,
		"frames": during.size(), "worst_ms": snappedf(worst, 0.1), "median_ms": snappedf(median(during), 0.1),
		"after_median_ms": snappedf(after_med, 0.1), "ratio": snappedf(worst / after_med, 0.01) if after_med > 0.0 else 0.0,
		"ok": stall_ratio_ok(worst, after_med)})
	_thumbs = {}


## The creator's thumbnail cache (null when no creator is on top).
func _thumb_cache() -> ThumbnailCache:
	var main := get_parent()
	var stack: ScreenStack = main.get("screen_stack") as ScreenStack if main != null else null
	var top: UiScreen = stack.top() if stack != null and is_instance_valid(stack) else null
	return (top as CreatorScreen).thumbnails if top is CreatorScreen else null


func _begin_mark(mark: String, extra: Dictionary = {}, first: Array = []) -> void:
	if not _open.is_empty():
		_close_mark()
	_open = {"mark": mark, "first": first.duplicate(), "steady": [], "extra": extra, "first_draw": [], "steady_draw": []}


func _close_mark() -> void:
	var r := stall_result(str(_open.mark), _open.first, _open.steady)
	r.merge(_open.extra as Dictionary)
	r["first"] = (_open.first as Array).map(func(v: float) -> float: return snappedf(v, 0.1))
	r["first_draw"] = (_open.first_draw as Array).map(func(v: float) -> float: return snappedf(v, 0.1))
	r["median_draw_ms"] = snappedf(median(_open.steady_draw), 0.1)
	_open = {}
	_results.append(r)
	_say(r)
	if tour != "":
		_say_skin(str(r.mark))
		_shot(str(r.mark))
	if bench:
		var b := skin_bench()
		if not b.is_empty():
			b["t"] = "bench"
			b["mark"] = r.mark
			_say(b)


## The skin's CPU a frame for the player's rig (see the header); {} when no skinned rig is in the tree.
func skin_bench() -> Dictionary:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return {}
	var rig: SkinnedRig = null
	for n in player.find_children("*", "", true, false):
		if n is SkinnedRig and (n as SkinnedRig).layers_on():
			rig = n as SkinnedRig
			break
	if rig == null or rig.animation_tree() == null or rig.skeleton() == null:
		return {}
	var tree := rig.animation_tree()
	var sk := rig.skeleton()
	var mod := rig.modifier()
	var runs_before := mod.runs if mod != null else 0
	var best := INF
	var dt := 1.0 / 60.0
	for _b in BENCH_BATCHES:
		var t0 := Time.get_ticks_usec()
		for _i in BENCH_RUNS:
			rig._drive_tree(dt)
			tree.advance(dt)
			sk.force_update_all_bone_transforms()
			if mod != null:
				mod._process_modification_with_delta(dt)   # the engine runs it inside the skeleton's deferred update
		best = minf(best, float(Time.get_ticks_usec() - t0) / float(BENCH_RUNS))
	# The same with every modifier the skeleton runs, the springs and their limits included (P50's SecondaryMotion;
	# the W30 merge): the skeleton in manual mode, advanced by hand and updated at once (its deferred update, which
	# runs every modifier and emits skeleton_updated as a frame does; plan M11 §2.12's row with secondary motion).
	var with_springs := INF
	var mode := sk.modifier_callback_mode_process
	sk.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	for _b in BENCH_BATCHES:
		var t0 := Time.get_ticks_usec()
		for _i in BENCH_RUNS:
			rig._drive_tree(dt)
			tree.advance(dt)
			sk.advance(dt)   # queues the modifiers' pass with this delta; the notification runs it now
			sk.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)
		with_springs = minf(with_springs, float(Time.get_ticks_usec() - t0) / float(BENCH_RUNS))
	sk.modifier_callback_mode_process = mode
	var sm := rig.secondary()
	var giants := 0
	for m in get_tree().get_nodes_in_group(GiantModel.GROUP):
		if (m as Node).is_inside_tree():
			giants += 1
	return {"skin_ms": snappedf(best / 1000.0, 0.0001), "skin_springs_ms": snappedf(with_springs / 1000.0, 0.0001),
		"chains": Array(sm.chains) if sm != null else [], "batches": BENCH_BATCHES, "runs": BENCH_RUNS, "giants": giants,
		"modifier_runs": (mod.runs if mod != null else 0) - runs_before, "paused": get_tree().paused}


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
	# P57: an option grid opens, and the first option put on in it
	var grid := str(s.get("grid", ""))
	if creator and grid != "" and str(was.get("grid", "")) != grid:
		_begin_mark("grid", {"key": grid})
		_thumbs = {"key": grid, "made_before": int(s.get("thumbs", 0)), "during": [], "after": [], "done": false}
		_picked_in_grid = false
	elif creator and grid != "" and not _picked_in_grid and int(s.history) > int(was.get("history", 0)):
		_picked_in_grid = true
		var parts := GiantModel.part_stats()
		_begin_mark("pick", {"key": grid, "part_loads": int(parts.loads), "part_load_max_ms": parts.load_max_ms})
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
	elif tour == "level":
		_tour_level()
	elif tour == "continue":
		_tour_continue(s)
	elif tour == "intro":
		_tour_intro(s)
	elif tour == "titan":
		_tour_titan(s)
	else:
		_tour_shrine(s)


## The level tour: once the level's mark is done, the giant's own draw calls - the frame's count with the
## giant's models shown, then hidden (§2.12: at most 13 with the fullest look, low). M10 gate (LD-6): both
## counts are read in a still scene - the tree paused, DRAW_SETTLE_FRAMES frames let pass after each change,
## then DRAW_SAMPLE_FRAMES frames read and their median taken - because in a running level the scene's own
## count moved by about 4 between the two readings (the HUD's lines, actors' LOD tiers, effects) and the
## difference read 15 calls for 11 meshes in one run and 5 for 9 in another. "still" says that neither
## reading moved while it was sampled; "giant_surfaces" is the shown meshes' own surface count, which the
## difference must equal in a level whose preset draws the giant once (no shadow pass: low).
func _tour_level() -> void:
	match _step:
		0:
			if _has_result("level"):
				_giant_draw = {"was_paused": get_tree().paused, "with": [], "without": [], "p_with": [], "p_without": []}
				get_tree().paused = true
				_next(DRAW_SETTLE_FRAMES)
		1:
			if _sample_draw("with"):
				for m in get_tree().get_nodes_in_group(GiantModel.GROUP):
					(m as Node3D).visible = false
				_next(DRAW_SETTLE_FRAMES)
		2:
			if _sample_draw("without"):
				for m in get_tree().get_nodes_in_group(GiantModel.GROUP):
					(m as Node3D).visible = true
				get_tree().paused = bool(_giant_draw.was_paused)
				var stats := SkinnedRig.run_stats()
				_say(giant_draw_result(_giant_draw["with"], _giant_draw.without, _giant_draw.p_with, _giant_draw.p_without,
					str(stats.look), stats.shown_meshes, _shown_surfaces()))
				_end_tour(true, "")


## One frame's counts into the reading `key`; true once DRAW_SAMPLE_FRAMES are in.
func _sample_draw(key: String) -> bool:
	(_giant_draw[key] as Array).append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	(_giant_draw["p_" + key] as Array).append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
	return (_giant_draw[key] as Array).size() >= DRAW_SAMPLE_FRAMES


## The surfaces of the giant's visible meshes (every model in the tree): what one colour pass draws.
func _shown_surfaces() -> int:
	var n := 0
	for m in get_tree().get_nodes_in_group(GiantModel.GROUP):
		for c in (m as Node).find_children("*", "MeshInstance3D", true, false):
			var mi := c as MeshInstance3D
			if mi.is_visible_in_tree() and mi.mesh != null:
				n += mi.mesh.get_surface_count()
	return n


## The level tour's line from its two readings (each DRAW_SAMPLE_FRAMES frames of a paused scene): the
## medians, their difference, and whether either reading moved while it was sampled ("still").
static func giant_draw_result(with: Array, without: Array, prims_with: Array, prims_without: Array, look: String,
		shown_meshes: Variant, surfaces: int) -> Dictionary:
	var w := int(median(with))
	var wo := int(median(without))
	return {"t": "giant_draw", "draw_calls_with": w, "draw_calls_without": wo, "giant_draw_calls": w - wo,
		"giant_primitives": int(median(prims_with)) - int(median(prims_without)),
		"still": _spread(with) == 0 and _spread(without) == 0, "samples": mini(with.size(), without.size()),
		"spread_with": _spread(with), "spread_without": _spread(without),
		"look": look, "shown_meshes": shown_meshes, "giant_surfaces": surfaces}


static func _spread(values: Array) -> int:
	if values.is_empty():
		return 0
	return int(values.max()) - int(values.min())


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


## The continue tour: the title with a saved game, Enter on Continue, the level's mark.
func _tour_continue(s: Dictionary) -> void:
	match _step:
		0:
			if _has_result("title") and str(s.top) == "title":
				if not str(s.focus).begins_with("Continue"):
					_end_tour(false, "the title's focus is \"%s\", not Continue (no saved game in --save-dir?)" % s.focus)
					return
				_key(KEY_ENTER)
				_next()
		1:
			if _has_result("level"):
				_end_tour(true, "")


## The intro tour (A5; see the header).
func _tour_intro(s: Dictionary) -> void:
	var main := get_parent()
	var stack: ScreenStack = main.get("screen_stack") as ScreenStack if main != null else null
	var top: UiScreen = stack.top() if stack != null and is_instance_valid(stack) else null
	match _step:
		0:
			var cs := top as CutsceneScreen
			if cs == null:
				return
			var due := skip_at == "open" or (skip_at.is_valid_int() and cs.tick >= int(skip_at))
			if due:
				_intro = {"skipped_at_tick": cs.tick, "loading_at_skip": bool(s.loading)}
				_skip_press()
				_next(0)
			elif skip_at == "end":
				_next(0)
		1:
			if top is CutsceneScreen:
				return
			_next(INTRO_SETTLE_FRAMES)
		2:
			var player := get_tree().get_first_node_in_group("player") as GiantPlayer
			var level: Node = main.get("level") if main != null else null
			var hud: Control = main.get("hud") as Control if main != null else null
			var cam := get_viewport().get_camera_3d()
			var ground := NAN
			if level is WorldRoot and player != null:
				ground = (level as WorldRoot).height_at(player.global_position)
			var stonebacks := 0
			for n in get_tree().root.find_children("*", "StonebackRig", true, false):
				stonebacks += 1
			_intro.merge({"t": "intro", "skip": skip_at, "key": skip_key, "paused": get_tree().paused,
				"gameplay_context": InputRouter.context == InputRouter.Context.GAMEPLAY,
				"hud_shown": hud != null and hud.is_visible_in_tree(), "top": s.top,
				"camera_is_players": player != null and cam != null and player.camera_rig.is_ancestor_of(cam),
				"player_shown": player != null and player.is_visible_in_tree(),
				"player_above_ground_m": snappedf(player.global_position.y - ground, 0.01) if not is_nan(ground) else null,
				"cutscene_nodes": get_tree().root.find_children("Cutscene", "", true, false).size(),
				"stoneback_rigs": stonebacks, "titans": get_tree().root.find_children("*", "TitanEnemy", true, false).size(),
				"music": Audio.music.state_name() if Audio != null and Audio.get("music") != null else "",
				"seen": ExpansionState.seen(GameSession.expansion, ExpansionState.INTRO_ID),
				"played": GameSession.cutscenes_played.size()})
			_intro["at"] = player.global_position if player != null else Vector3.ZERO
			var w := InputEventKey.new()
			w.keycode = KEY_W
			w.physical_keycode = KEY_W
			w.pressed = true
			Input.parse_input_event(w)
			_next(INTRO_WALK_FRAMES)
		3:
			var w := InputEventKey.new()
			w.keycode = KEY_W
			w.physical_keycode = KEY_W
			w.pressed = false
			Input.parse_input_event(w)
			var player := get_tree().get_first_node_in_group("player") as GiantPlayer
			var at: Vector3 = _intro.at
			_intro.erase("at")
			_intro["walked_m"] = snappedf((player.global_position - at).length(), 0.01) if player != null else 0.0
			var ok: bool = not bool(_intro.paused) and bool(_intro.gameplay_context) and bool(_intro.hud_shown) \
				and str(_intro.top) == "" and bool(_intro.camera_is_players) and bool(_intro.player_shown) \
				and int(_intro.cutscene_nodes) == 0 and bool(_intro.seen) and int(_intro.played) == 1 \
				and float(_intro.walked_m) > 1.0
			_intro["ok"] = ok
			_say(_intro)
			_end_tour(ok, "" if ok else "the play after the intro is not right")


## The intro tour's skip: the key or button of --ui-probe-skip-key=, pressed and released.
func _skip_press() -> void:
	var pads := {"pad_a": JOY_BUTTON_A, "pad_b": JOY_BUTTON_B, "pad_start": JOY_BUTTON_START}
	if pads.has(skip_key):
		for pressed: bool in [true, false]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = pads[skip_key]
			ev.pressed = pressed
			_keys.append(ev)
		return
	var keys := {"enter": KEY_ENTER, "esc": KEY_ESCAPE, "space": KEY_SPACE}
	_key(keys.get(skip_key, KEY_ENTER))


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


# --------------------------------------------------------------------------- B4: the titan tour

## B4 (the milestone B gate): a titan's fight entered as a player enters it, in a running game (--mode=valley
## --new-game --start=valley.shrine.kingsfall for the Ogre King; --mode=world --new-game --start=world.cp.hollowmere
## for the Rootwarden, the woodfolk's call set): the giant (readied for --ui-probe-stage=N when given) is put into
## the arena's engage trigger and then past the gate (the King), or into the hollow (the Rootwarden); his intro must
## open; it is skipped as the intro tour's (--ui-probe-skip=, --ui-probe-skip-key=); then one UI_PROBE {"t":"titan"}
## line says what the play looks like (paused, the input context, the HUD, the camera, the giant shown on the ground,
## the titan shown, awake and fighting, the arena engaged, the cutscene's nodes gone, the intro seen and played once).
## With --ui-probe-die the fight is then lost: two of his plates broken (the King's crown and keg: unbalanced and
## down; the Rootwarden's knot and a shoulder), the giant brought to one point of health and left to his blows; the
## death screen's confirm reloads the checkpoint, and UI_PROBE {"t":"titan_retry"} says what the retry looks like
## (his plates whole, no unbalance, standing, the intro not played again, then entered again: engaged, no intro).
const TITAN_POINTS := {"ogre_king": [Vector3(150.0, 0.3, 97.8), Vector3(150.0, 0.3, 107.0)],
	"rootwarden": [Vector3(-770.0, 0.0, 208.0), Vector3(-770.0, 0.0, 208.0)]}
const TITAN_ENEMIES := {"ogre_king": "enemy.ogre_king", "rootwarden": "enemy.rootwarden"}
const TITAN_INTRO_IDS := {"ogre_king": "cutscene.ogre_king", "rootwarden": "cutscene.rootwarden"}
const TITAN_BREAKS := {"ogre_king": ["crown", "keg"], "rootwarden": ["knot", "shoulder_l"]}
const TITAN_NO_INTRO_FRAMES := 240
var _titan_wait := 0
static var _titan_levels := 0


func _titan_node() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t != null and t.entity != null and t.entity.definition_id == str(TITAN_ENEMIES.get(titan, "")):
			return t
	return null


func _titan_arena(t: TitanEnemy) -> BossArena:
	return t.territory() if t != null else null


func _level_results() -> int:
	var n := 0
	for r: Dictionary in _results:
		if str(r.mark) == "level":
			n += 1
	return n


## Puts the giant at `at` (the ground's height under it in the world, once its ring is in).
func _titan_place(at: Vector3) -> bool:
	var main := get_parent()
	var level: Node = main.get("level") if main != null else null
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	if p == null:
		return false
	var y := at.y
	if level is WorldRoot:
		var w := level as WorldRoot
		if not w.streamer.ring_ready(at):
			p.process_mode = Node.PROCESS_MODE_DISABLED
			p.global_position = at + Vector3.UP * 200.0
			w.streamer.load_ring_slice(at)
			return false
		var h := w.height_at(at)
		y = (h if not is_nan(h) else 20.0) + 0.3
	p.global_position = Vector3(at.x, y, at.z)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	return true


func _titan_read(s: Dictionary, t: TitanEnemy) -> Dictionary:
	var main := get_parent()
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	var level: Node = main.get("level") if main != null else null
	var hud: Control = main.get("hud") as Control if main != null else null
	var cam := get_viewport().get_camera_3d()
	var ground := NAN
	if level is WorldRoot and p != null:
		ground = (level as WorldRoot).height_at(p.global_position)
	elif p != null and p.is_on_floor():
		ground = p.global_position.y
	var arena := _titan_arena(t)
	return {"paused": get_tree().paused, "gameplay_context": InputRouter.context == InputRouter.Context.GAMEPLAY,
		"hud_shown": hud != null and hud.is_visible_in_tree(), "top": s.top,
		"camera_is_players": p != null and cam != null and p.camera_rig.is_ancestor_of(cam),
		"player_shown": p != null and p.is_visible_in_tree(),
		"player_alive": p != null and p.entity != null and p.entity.is_alive(),
		"player_above_ground_m": snappedf(p.global_position.y - ground, 0.01) if p != null and not is_nan(ground) else null,
		"titan_shown": t != null and t.is_visible_in_tree(), "titan_ai": t != null and t.ai_enabled,
		"titan_dormant": t != null and t.dormant, "titan_alive": t != null and t.entity.is_alive(),
		"plates_broken": t.entity.plates.broken_count() if t != null and t.entity.plates != null else -1,
		"unbalance": t.entity.plates.poise_taken_mult if t != null and t.entity.plates != null else -1.0,
		"down": t != null and t.is_down(), "arena": arena.state_name() if arena != null else "",
		"gate_closed": arena != null and arena.is_gate_closed(),
		"cutscene_nodes": get_tree().root.find_children("Cutscene", "", true, false).size(),
		"music": Audio.music.state_name() if Audio != null and Audio.get("music") != null else "",
		"seen": ExpansionState.seen(GameSession.expansion, str(TITAN_INTRO_IDS.get(titan, ""))),
		"played": GameSession.cutscenes_played.count(str(TITAN_INTRO_IDS.get(titan, "")))}


func _tour_titan(s: Dictionary) -> void:
	var main := get_parent()
	var stack: ScreenStack = main.get("screen_stack") as ScreenStack if main != null else null
	var top: UiScreen = stack.top() if stack != null and is_instance_valid(stack) else null
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	var pts: Array = TITAN_POINTS.get(titan, [])
	match _step:
		0:
			if not _has_result("level") or str(s.top) != "" or bool(s.loading) or p == null:
				return
			if titan_stage > 0:
				TitanDuel.prepare(p, titan_stage)
			if titan == "rootwarden":
				WorldState.try_set_flag("world.rootwarden.called", true)
				WorldState.try_set_flag("world.rootwarden.resin_laid", true)
			_titan_out = {"t": "titan", "titan": titan, "stage": p.growth_stage, "skip": skip_at, "key": skip_key}
			_next(0)
		1:
			if _titan_place(pts[0]):
				_next(10)
		2:
			_titan_place(pts[1])
			_titan_wait = 0
			_next(0)
		3:
			var cs := top as CutsceneScreen
			if cs == null:
				_titan_wait += 1
				if _titan_wait > TITAN_NO_INTRO_FRAMES * 4:
					_titan_out["why"] = "no intro opened"
					_titan_out.merge(_titan_read(s, _titan_node()))
					_say(_titan_out)
					_end_tour(false, "his intro did not open")
				return
			_titan_out["intro"] = cs.cutscene_id
			var due := skip_at == "open" or (skip_at.is_valid_int() and cs.tick >= int(skip_at))
			if due:
				_titan_out["skipped_at_tick"] = cs.tick
				_skip_press()
				_next(0)
			elif skip_at == "end":
				_next(0)
		4:
			if top is CutsceneScreen:
				return
			_next(INTRO_SETTLE_FRAMES)
		5:
			var t := _titan_node()
			_titan_out.merge(_titan_read(s, t))
			var o := _titan_out
			var ok: bool = not bool(o.paused) and bool(o.gameplay_context) and bool(o.hud_shown) and str(o.top) == "" \
				and bool(o.camera_is_players) and bool(o.player_shown) and bool(o.titan_shown) and bool(o.titan_ai) \
				and not bool(o.titan_dormant) and str(o.arena) == "engaged" and int(o.cutscene_nodes) == 0 \
				and bool(o.seen) and int(o.played) == 1 and o.player_above_ground_m != null \
				and absf(float(o.player_above_ground_m)) < 1.0
			_titan_out["ok"] = ok
			_say(_titan_out)
			if not ok:
				_end_tour(false, "the play after his intro is not right")
				return
			if not titan_die:
				_end_tour(true, "")
				return
			for id: String in TITAN_BREAKS.get(titan, []):
				t.break_plate(id)
			_titan_out = {"t": "titan_retry", "titan": titan, "before_death": {
				"plates_broken": t.entity.plates.broken_count(), "unbalance": t.entity.plates.poise_taken_mult,
				"down": t.is_down(), "regrow_wounds": t.entity.plates.wounds.size()}}
			p.entity.combatant.pools.health = 1.0
			_titan_levels = _level_results()
			_next(0)
		6:
			if p == null or not get_parent().call("is_dead", p):
				return
			if get_parent().call("death_confirm_ready", p, Sim.tick):
				get_parent().call("_confirm_death")
				_next(0)
		7:
			if _level_results() <= _titan_levels or str(s.top) != "" or bool(s.loading) or p == null:
				return
			_next(INTRO_SETTLE_FRAMES)
		8:
			var t := _titan_node()
			_titan_out["after_reload"] = _titan_read(s, t)
			if titan_stage > 0:
				TitanDuel.prepare(p, titan_stage)
			_next(0)
		9:
			if _titan_place(pts[0]):
				_next(10)
		10:
			_titan_place(pts[1])
			_titan_wait = 0
			_next(0)
		11:
			_titan_wait += 1
			if top is CutsceneScreen:
				_titan_out["intro_again"] = true
			if _titan_wait < TITAN_NO_INTRO_FRAMES and not (top is CutsceneScreen):
				return
			var t := _titan_node()
			var again := _titan_read(s, t)
			_titan_out["entered_again"] = again
			# (after the reload he may not be spawned yet - his encounter waits for the giant to come near)
			var a: Dictionary = _titan_out.after_reload
			var ok: bool = bool(a.player_alive) and str(a.arena) != "engaged" and not bool(a.gate_closed) \
				and bool(again.titan_alive) and int(again.plates_broken) == 0 and float(again.unbalance) == 1.0 \
				and not bool(again.down) and not bool(_titan_out.get("intro_again", false)) \
				and str(again.arena) == "engaged" and int(again.played) <= 1
			_titan_out["ok"] = ok
			_say(_titan_out)
			_end_tour(ok, "" if ok else "the retry is not right")
