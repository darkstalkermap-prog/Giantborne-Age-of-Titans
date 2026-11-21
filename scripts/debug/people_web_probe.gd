class_name PeopleWebProbe
extends Node
## P64 (plan M11 §3.17 design 3 and 4, §2.12): the people's and the creatures' measures in play, for
## tools/web/people_check.mjs (the Web build in Chromium) and native runs under Xvfb. main.gd makes one with
## --people-probe (beside --ui-probe, whose marks time the first frames); without the argument nothing of it exists.
## Once the level's loading screen has let go and SETTLE_FRAMES frames have passed, it plays its views and prints one
## line for each, then quits:
##
##   PEOPLE_WEB {"t":"view", "view", "draw_calls", "primitives", "texture_mem_mb", "buffer_mem_mb", "people":
##     {"skinned", "crowd", "far"}, "others": {"skinned", "far", "half_rate_skips", "camera_m"}, "people_cpu_ms",
##     "people_cpu_parts_ms", "frames"}
##       the view's medians over MEASURE_FRAMES frames; the people's CPU a frame is every PersonRig's, BruteRig's,
##       SkinnedWolfRig's and CrowdRenderer's process timed in a loop of BENCH_RUNS frames (their median; as the
##       people's probe does natively, docs/systems/P60.md); P64b: the creatures' half-rate frames over the view's frames
##       (CreatureSlots.half_rate) and their median distance from the camera;
##   PEOPLE_WEB {"t":"done", "views"}
##
## The views (--people-probe=<list>, joined by "+" or ",": the Web launcher splits its arguments at commas; default
## "level+formation+wolves"):
##   level      the level as it stands before the giant;
##   formation  forty soldiers in a block of 8 x 5 FORMATION_M before the giant, facing him (UiProbe's mark
##              "first_formation": the frames that first draw a formation);
##   wolves     a pack of five wolves and a dire wolf WOLVES_M before him (the mark "first_wolf").
## It never changes a rule of play: the AI of what it adds is off, and the run ends with it.

const TAG := "PEOPLE_WEB"
const SETTLE_FRAMES := 60
const MEASURE_FRAMES := 30
const AFTER_SPAWN_FRAMES := 60
const BENCH_RUNS := 30
const FORMATION_M := 25.0
const WOLVES_M := 12.0
const SOLDIER := "res://scenes/enemies/soldier.tscn"
const WOLF := "res://scenes/enemies/wolf.tscn"
const DIRE := "res://scenes/enemies/dire_wolf.tscn"

var views: PackedStringArray = PackedStringArray(["level", "formation", "wolves"])
var _started := false
var _done: Array = []


static func from_args(args: PackedStringArray) -> PeopleWebProbe:
	for arg in args:
		if arg == "--people-probe" or arg.begins_with("--people-probe="):
			var p := PeopleWebProbe.new()
			p.name = "PeopleWebProbe"
			if arg.contains("="):
				p.views = arg.get_slice("=", 1).replace("+", ",").split(",", false)
			return p
	return null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	if _started:
		return
	var main := get_parent()
	if main == null or main.get("level") == null or (main.has_method("is_loading") and bool(main.call("is_loading"))):
		return
	if get_tree().paused or get_tree().get_first_node_in_group("player") == null:
		return
	_started = true
	_run.call_deferred()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	await _frames(SETTLE_FRAMES)
	for v: String in views:
		match v:
			"formation":
				_mark("first_formation")
				_spawn_formation()
				await _frames(AFTER_SPAWN_FRAMES)
			"wolves":
				_mark("first_wolf")
				_spawn_wolves()
				await _frames(AFTER_SPAWN_FRAMES)
		await _measure(v)
	_say({"t": "done", "views": _done})
	await _frames(2)
	get_tree().quit(0)


## A mark of UiProbe's (its first frames against the steady ones), when it runs.
func _mark(mark: String) -> void:
	var ui := get_parent().get_node_or_null("UiProbe")
	if ui != null and ui.has_method("_begin_mark"):
		ui.call("_begin_mark", mark)


func _giant() -> Node3D:
	return get_tree().get_first_node_in_group("player") as Node3D


func _ahead(d: float, side: float) -> Vector3:
	var g := _giant()
	var f := -g.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	return g.global_position + f * d + f.cross(Vector3.UP).normalized() * side


func _spawn(path: String, id: String, pos: Vector3) -> Node3D:
	var e := (load(path) as PackedScene).instantiate() as Node3D
	e.set("entity_id", id)
	e.set("ai_enabled", false)
	var g := _giant()
	e.position = pos
	e.rotation.y = atan2(g.global_position.x - pos.x, g.global_position.z - pos.z) + PI
	var level: Node = get_parent().get("level")
	level.add_child(e)
	return e


func _spawn_formation() -> void:
	for i in 40:
		_spawn(SOLDIER, "people_web.soldier_%d" % i, _ahead(FORMATION_M + float(i / 8) * 1.6, (float(i % 8) - 3.5) * 1.4))


func _spawn_wolves() -> void:
	for i in 5:
		_spawn(WOLF, "people_web.wolf_%d" % i, _ahead(WOLVES_M + float(i % 2) * 1.5, (float(i) - 2.0) * 1.8))
	_spawn(DIRE, "people_web.dire_wolf", _ahead(WOLVES_M + 3.0, 4.5))


func _measure(view: String) -> void:
	var calls: Array = []
	var prims: Array = []
	var skips0 := int(CreatureSlots.totals.get("half_rate_skips", 0))
	for i in MEASURE_FRAMES:
		await get_tree().process_frame
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var people := {"skinned": 0, "crowd": 0, "far": 0}
	for r: PersonRig in PersonRig.rigs():
		match r.level:
			PersonRig.Level.SKINNED:
				people.skinned += 1
			PersonRig.Level.CROWD:
				people.crowd += 1
			PersonRig.Level.FAR:
				people.far += 1
	var others := {"skinned": 0, "far": 0, "half_rate_skips": int(CreatureSlots.totals.get("half_rate_skips", 0)) - skips0,
		"camera_m": 0.0}
	var cam := get_viewport().get_camera_3d()
	var dists: Array = []
	for r: Variant in CreatureSlots.rigs():
		if bool((r as Object).call("has_slot")):
			others.skinned += 1
		elif bool((r as Object).call("slot_wanted")):
			others.far += 1
		if cam != null:
			dists.append(((r as Node3D).global_position).distance_to(cam.global_position))
	if not dists.is_empty():
		others.camera_m = snappedf(UiProbe.median(dists), 0.1)
	var cpu := _bench()
	var line := {"t": "view", "view": view, "draw_calls": int(UiProbe.median(calls)), "primitives": int(UiProbe.median(prims)),
		"texture_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.01),
		"buffer_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.01),
		"people": people, "others": others, "people_cpu_ms": cpu[0], "people_cpu_parts_ms": cpu.slice(1),
		"frames": MEASURE_FRAMES, "quality": str(Settings.graphics_quality)}
	_done.append(view)
	_say(line)


## The people's CPU a frame (ms): [all, skinned people, instanced people, creatures, renderers], each the median of
## BENCH_RUNS frames' process calls (P64b: the median, of thirty, so that a frame the shared machine took from the
## page does not move the view's number; P64 took the mean of ten).
func _bench() -> Array:
	var runs: Array = [[], [], [], [], []]
	for k in BENCH_RUNS:
		var us := [0, 0, 0, 0]
		for r: PersonRig in PersonRig.rigs():
			var t := Time.get_ticks_usec()
			r._process(1.0 / 60.0)
			us[0 if r.skinned() else 1] += Time.get_ticks_usec() - t
		for r: Variant in CreatureSlots.rigs():
			var t := Time.get_ticks_usec()
			(r as Node).call("_process", 1.0 / 60.0)
			us[2] += Time.get_ticks_usec() - t
		var t2 := Time.get_ticks_usec()
		for c in get_tree().get_nodes_in_group("crowd_renderers"):
			c.call("refresh")
		us[3] += Time.get_ticks_usec() - t2
		var total := 0
		for i in 4:
			(runs[i + 1] as Array).append(float(us[i]))
			total += int(us[i])
		(runs[0] as Array).append(float(total))
	return runs.map(func(x: Array) -> float: return snappedf(UiProbe.median(x) / 1000.0, 0.001))


func _say(line: Dictionary) -> void:
	print("%s %s" % [TAG, JSON.stringify(line)])
