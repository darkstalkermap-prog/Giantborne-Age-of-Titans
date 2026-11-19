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
const TOURS := ["", "new_game", "shrine", "level", "continue"]
const BENCH_BATCHES := 5
const BENCH_RUNS := 200
const TOUR_STEP_LIMIT_S := 240.0
## The level tour's draw-call readings (M10 gate, LD-6): the frames let pass after the tree is paused or the
## giant hidden, and the frames each reading takes.
const DRAW_SETTLE_FRAMES := 6
const DRAW_SAMPLE_FRAMES := 5

var tour := ""
var shots_dir := ""
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
		(_open.first_draw as Array).append(_last_draw_ms)
	else:
		(_open.steady as Array).append(ms)
		(_open.steady_draw as Array).append(_last_draw_ms)
		if (_open.steady as Array).size() >= STEADY_FRAMES:
			_close_mark()


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
