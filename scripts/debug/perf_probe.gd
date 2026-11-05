class_name PerfProbe
extends Node
## Performance capture for the tool runs (P14; plan §3.16 item 3, §5.3, §5.4). The Autopilot adds
## one for --scenario=stress, --scenario=valley_walk and --perf; once in the tree it samples every
## simulation tick and every rendered frame until finish(). result() is the report and
## print_result() prints it as one "PERF_RESULT {json}" line: per metric p50 / p95 / p99
## (nearest rank), min, max and mean, plus the budget verdicts of §5.4.
##
## Per simulation tick (after warmup_ticks, so start-up spawning and the first navigation map sync
## are left out):
##   cpu_tick_ms        the physics tick measured from inside: this node's _physics_process runs
##                      first (priority PHYSICS_PRIORITY_FIRST, before Sim's -1000) and the tick ends
##                      at the next one of it or at the start of the frame's idle step, so the span
##                      holds Sim.step, every other _physics_process (move_and_slide, the debris
##                      pool, the autopilot) and the physics server step (Jolt: debris bodies).
##   sim_ms             Sim.step alone (actors, hooks, hit resolution, statuses): a helper at physics
##                      priority PHYSICS_PRIORITY_AFTER_SIM closes it.
##   active_combatants  the EncounterDirector's active_combatant_count(), or without a director the
##                      living, non-routed members of group "enemies".
##   debris             the debris pool's active pieces.
## Per rendered frame:
##   idle_ms            the frame's _process callbacks (HUD, camera, presentation), from this node
##                      (PROCESS_PRIORITY_FIRST) to a helper at PROCESS_PRIORITY_LAST.
##   frame_ms           the real process delta; "N/A" under --fixed-fps, where it is constant
##                      (the engine keeps --fixed-fps out of OS.get_cmdline_args(), so a run whose
##                      every delta is the same counts as fixed).
##   gpu_render_ms, cpu_render_ms   RenderingServer.viewport_get_measured_render_time_gpu / _cpu
##                      of the root viewport (measurement switched on here); "N/A" headless or when
##                      the renderer reports none.
##   draw_calls, render_objects, primitives   the frame's totals (RenderingServer rendering info,
##                      shadow passes included); "N/A" headless (the dummy renderer draws nothing).
##   nodes, objects, orphan_nodes, memory_static_mb   Performance monitors (static memory is
##                      "N/A" in release builds, which do not track it).
##
## Performance.TIME_PHYSICS_PROCESS and TIME_PROCESS are not sampled per tick: Godot 4.6 refreshes
## them once per second of wall time with the largest value of that second (verified in the
## container: 600 headless frames, one refresh), so per-tick percentiles of them would only repeat
## those maxima. The largest values seen are reported as engine_physics_max_ms and
## engine_process_max_ms.
##
## `section` (set by the scenario; valley_walk sets the district) also files cpu_tick_ms,
## frame_ms, draw_calls and active_combatants per section ("sections" in the result).
## hits_resolved is counted from Events.hit_resolved; a scenario may add its own `counters` and
## `context` keys.

const WARMUP_TICKS := 60
## This node's physics callback runs before Sim (-1000); the helper right after Sim.step.
const PHYSICS_PRIORITY_FIRST := -2000
const PHYSICS_PRIORITY_AFTER_SIM := -999
const PROCESS_PRIORITY_FIRST := -2000
const PROCESS_PRIORITY_LAST := 2000000
## Budgets (plan §5.4): Sim CPU per tick (container indicative, reference PC), frame times at 1080p
## low on the reference PC, draw calls in any Valley view.
const BUDGET_TICK_P95_MS := 8.0
const BUDGET_FRAME_P95_MS := 16.7
const BUDGET_FRAME_P99_MS := 33.3
const BUDGET_DRAW_CALLS := 250.0
## Samples kept per metric (a 40-minute run at 60 Hz).
const MAX_SAMPLES := 150000
const NA := "N/A"
const TICK_METRICS := ["cpu_tick_ms", "sim_ms", "active_combatants", "debris"]
const FRAME_METRICS := ["idle_ms", "frame_ms", "gpu_render_ms", "cpu_render_ms", "draw_calls",
	"render_objects", "primitives", "nodes", "objects", "orphan_nodes", "memory_static_mb"]
const SECTION_METRICS := ["cpu_tick_ms", "frame_ms", "draw_calls", "active_combatants"]

## A name for the run ("stress", "valley_walk", "soak").
var label := ""
var warmup_ticks := WARMUP_TICKS
## True under --fixed-fps: every frame delta so far was the same (frame_ms is then N/A).
var fixed_fps := false
## True with the headless display server (no rendering: render times and draw calls are N/A).
var headless := false
## The breakdown key of the samples taken now ("" = none).
var section := ""
## Event counts of the run (hits_resolved here; scenarios add theirs).
var counters := {"hits_resolved": 0}
## Extra keys copied into the result (scenario, level, ...).
var context := {}
var ticks_seen := 0
var frames_seen := 0
var finished := false

var _series := {}       # metric -> PackedFloat64Array
var _sections := {}     # section -> {metric -> PackedFloat64Array}
var _tick_open := false
var _t_tick := 0
var _sim_us := -1
var _t_idle := -1
var _vp_rid := RID()
var _engine_physics_max_ms := 0.0
var _engine_process_max_ms := 0.0
var _delta_min := INF
var _delta_max := -INF


## Closes a measurement span at its priority: Sim.step's end (physics) or the idle step's end.
class _Edge extends Node:
	var probe: PerfProbe
	var physics := true

	func _init(p_probe: PerfProbe, p_physics: bool) -> void:
		probe = p_probe
		physics = p_physics
		name = "AfterSim" if physics else "IdleEnd"

	func _ready() -> void:
		# Both callbacks exist, so READY switched both on: keep only this edge's own.
		set_physics_process(physics)
		set_process(not physics)

	func _physics_process(_delta: float) -> void:
		if physics:
			probe.note_sim_end(Time.get_ticks_usec())

	func _process(_delta: float) -> void:
		if not physics:
			probe.note_idle_end(Time.get_ticks_usec())


func _ready() -> void:
	process_physics_priority = PHYSICS_PRIORITY_FIRST
	process_priority = PROCESS_PRIORITY_FIRST
	headless = DisplayServer.get_name() == "headless"
	_vp_rid = get_viewport().get_viewport_rid()
	if not headless:
		RenderingServer.viewport_set_measure_render_time(_vp_rid, true)
	var after_sim := _Edge.new(self, true)
	after_sim.process_physics_priority = PHYSICS_PRIORITY_AFTER_SIM
	add_child(after_sim)
	var idle_end := _Edge.new(self, false)
	idle_end.process_priority = PROCESS_PRIORITY_LAST
	add_child(idle_end)
	Events.hit_resolved.connect(_on_hit_resolved)


func _physics_process(_delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	if _tick_open:
		_close_tick(now)   # a second tick in the same frame: the previous one ended here
	_t_tick = now
	_tick_open = true
	_sim_us = -1


func _process(delta: float) -> void:
	if finished:
		return
	var now := Time.get_ticks_usec()
	if _tick_open:
		_close_tick(now)
	_t_idle = now
	_sample_frame(delta)


## The helper after Sim.step (physics priority PHYSICS_PRIORITY_AFTER_SIM).
func note_sim_end(now_usec: int) -> void:
	if _tick_open and _sim_us < 0:
		_sim_us = now_usec - _t_tick


## The helper at the end of the idle step (process priority PROCESS_PRIORITY_LAST).
func note_idle_end(now_usec: int) -> void:
	if finished or _t_idle < 0:
		return
	if ticks_seen > warmup_ticks:
		add_sample("idle_ms", float(now_usec - _t_idle) / 1000.0)
	_t_idle = -1


## Stops sampling (the result keeps what was taken).
func finish() -> void:
	finished = true
	set_physics_process(false)
	set_process(false)


func _on_hit_resolved(_tick: int, _r: HitResult) -> void:
	if not finished:
		counters["hits_resolved"] = int(counters.get("hits_resolved", 0)) + 1


func _close_tick(now_usec: int) -> void:
	_tick_open = false
	ticks_seen += 1
	if ticks_seen <= warmup_ticks:
		return
	add_sample("cpu_tick_ms", float(now_usec - _t_tick) / 1000.0)
	if _sim_us >= 0:
		add_sample("sim_ms", float(_sim_us) / 1000.0)
	if is_inside_tree():
		add_sample("active_combatants", float(active_combatants(get_tree())))
		add_sample("debris", float(debris_count(get_tree())))


func _sample_frame(delta: float) -> void:
	frames_seen += 1
	_delta_min = minf(_delta_min, delta)
	_delta_max = maxf(_delta_max, delta)
	fixed_fps = frames_seen > 1 and _delta_max - _delta_min < 1e-9
	_engine_physics_max_ms = maxf(_engine_physics_max_ms,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	_engine_process_max_ms = maxf(_engine_process_max_ms,
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if ticks_seen <= warmup_ticks:
		return
	add_sample("frame_ms", delta * 1000.0)
	if not headless:
		add_sample("gpu_render_ms", RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid))
		add_sample("cpu_render_ms", RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid))
		add_sample("draw_calls", float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
		add_sample("render_objects", float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)))
		add_sample("primitives", float(RenderingServer.get_rendering_info(
			RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	add_sample("nodes", Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	add_sample("objects", Performance.get_monitor(Performance.OBJECT_COUNT))
	add_sample("orphan_nodes", Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	add_sample("memory_static_mb", Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0)


## Adds one sample of `metric` (also to the current section for SECTION_METRICS).
func add_sample(metric: String, value: float) -> void:
	var arr: PackedFloat64Array = _series.get(metric, PackedFloat64Array())
	if arr.size() < MAX_SAMPLES:
		arr.append(value)
		_series[metric] = arr
	if section != "" and SECTION_METRICS.has(metric):
		var per: Dictionary = _sections.get(section, {})
		var s: PackedFloat64Array = per.get(metric, PackedFloat64Array())
		if s.size() < MAX_SAMPLES:
			s.append(value)
			per[metric] = s
			_sections[section] = per


## The samples of `metric` taken so far (a copy).
func samples(metric: String) -> PackedFloat64Array:
	return (_series.get(metric, PackedFloat64Array()) as PackedFloat64Array).duplicate()


# --------------------------------------------------------------------------- the report

## The report: run facts, a summary (or an "N/A (...)" reason) per metric, the counters, the
## engine's per-second maxima, the per-section summaries and the budget verdicts.
func result() -> Dictionary:
	var size := get_viewport().get_visible_rect().size if is_inside_tree() else Vector2.ZERO
	var out := {
		"label": label,
		"ticks": maxi(0, ticks_seen - warmup_ticks),
		"frames": frames_seen,
		"warmup_ticks": warmup_ticks,
		"fixed_fps": fixed_fps,
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"resolution": "%dx%d" % [int(size.x), int(size.y)],
		"quality": _quality(),
		"debug_build": OS.is_debug_build(),
	}
	for k: Variant in context:
		out[k] = context[k]
	for metric: String in TICK_METRICS + FRAME_METRICS:
		out[metric] = metric_summary(metric)
	out["counters"] = counters.duplicate()
	out["engine_physics_max_ms"] = snappedf(_engine_physics_max_ms, 0.001)
	out["engine_process_max_ms"] = snappedf(_engine_process_max_ms, 0.001)
	var secs := {}
	var keys := _sections.keys()
	keys.sort()
	for sec: Variant in keys:
		var per: Dictionary = _sections[sec]
		var entry := {}
		for metric: String in SECTION_METRICS:
			if per.has(metric):
				entry[metric] = summarize(per[metric])
		secs[sec] = entry
	out["sections"] = secs
	out["budgets"] = budgets(out)
	return out


## The summary of one metric, or "N/A (<why>)" when it cannot be measured in this run.
func metric_summary(metric: String) -> Variant:
	var why := na_reason(metric)
	if why != "":
		return "%s (%s)" % [NA, why]
	var arr: PackedFloat64Array = _series.get(metric, PackedFloat64Array())
	if arr.is_empty():
		return "%s (no samples)" % NA
	return summarize(arr)


## Why `metric` is not measured in this run ("" when it is).
func na_reason(metric: String) -> String:
	match metric:
		"frame_ms":
			if fixed_fps:
				return "--fixed-fps: constant frame delta"
		"gpu_render_ms", "cpu_render_ms", "draw_calls", "render_objects", "primitives":
			if headless:
				return "headless: nothing is rendered"
			if metric.ends_with("render_ms") and _all_zero(metric):
				return "not reported by this renderer"
		"memory_static_mb":
			if _all_zero(metric):
				return "not tracked in release builds"
	return ""


func print_result() -> void:
	print("PERF_RESULT " + JSON.stringify(result()))


func _all_zero(metric: String) -> bool:
	var arr: PackedFloat64Array = _series.get(metric, PackedFloat64Array())
	for v in arr:
		if v != 0.0:
			return false
	return true


func _quality() -> String:
	if is_inside_tree():
		var lv := get_tree().get_first_node_in_group(LevelRoot.GROUP) as LevelRoot
		if lv != null and lv.applied_graphics.has("quality"):
			return str(lv.applied_graphics.quality)
	return Settings.graphics_quality


# --------------------------------------------------------------------------- statistics

## The p-th percentile (0-100) of ascending `sorted` values by the nearest-rank method: the
## smallest value with at least p% of the samples at or below it. NAN when there are none.
static func percentile(sorted: PackedFloat64Array, p: float) -> float:
	var n := sorted.size()
	if n == 0:
		return NAN
	var rank := clampi(ceili(clampf(p, 0.0, 100.0) / 100.0 * float(n)), 1, n)
	return sorted[rank - 1]


## {"n", "p50", "p95", "p99", "min", "max", "mean"} of `values` (any order; rounded to 0.001).
## An empty input gives {"n": 0}.
static func summarize(values: PackedFloat64Array) -> Dictionary:
	var n := values.size()
	if n == 0:
		return {"n": 0}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in sorted:
		total += v
	return {"n": n, "p50": snappedf(percentile(sorted, 50.0), 0.001),
		"p95": snappedf(percentile(sorted, 95.0), 0.001), "p99": snappedf(percentile(sorted, 99.0), 0.001),
		"min": snappedf(sorted[0], 0.001), "max": snappedf(sorted[n - 1], 0.001),
		"mean": snappedf(total / float(n), 0.001)}


## The plan §5.4 budgets judged on a result: Sim CPU per tick p95 <= 8 ms, frame p95 <= 16.7 ms and
## p99 < 33.3 ms (real frames only), draw calls <= 250 (rendered runs only). Each entry is
## {"limit", "value", "ok"} or "N/A (...)" when the run cannot measure it.
static func budgets(r: Dictionary) -> Dictionary:
	return {
		"cpu_tick_p95_ms": _budget(r.get("cpu_tick_ms"), "p95", BUDGET_TICK_P95_MS, false),
		"frame_p95_ms": _budget(r.get("frame_ms"), "p95", BUDGET_FRAME_P95_MS, false),
		"frame_p99_ms": _budget(r.get("frame_ms"), "p99", BUDGET_FRAME_P99_MS, true),
		"draw_calls_max": _budget(r.get("draw_calls"), "max", BUDGET_DRAW_CALLS, false),
	}


static func _budget(summary: Variant, key: String, limit: float, strict: bool) -> Variant:
	if typeof(summary) != TYPE_DICTIONARY or not (summary as Dictionary).has(key):
		return summary if typeof(summary) == TYPE_STRING else "%s (no samples)" % NA
	var value := float(summary[key])
	return {"limit": limit, "value": value, "ok": value < limit if strict else value <= limit}


# --------------------------------------------------------------------------- what is on the field

## Active combatants: the level's EncounterDirector count when it has one, else the living,
## non-routed members of group "enemies" (the stress arena has no director).
static func active_combatants(tree: SceneTree) -> int:
	var d := tree.get_first_node_in_group("encounter_director")
	if d != null and d.has_method("active_combatant_count"):
		return int(d.call("active_combatant_count"))
	var n := 0
	for e in tree.get_nodes_in_group("enemies"):
		var ent: Variant = e.get("entity")
		if not (ent is CombatEntity) or not (ent as CombatEntity).is_alive():
			continue
		if e.has_method("is_routed") and bool(e.call("is_routed")):
			continue
		n += 1
	return n


## The debris pool's active pieces (0 without a pool).
static func debris_count(tree: SceneTree) -> int:
	var pool := tree.get_first_node_in_group("debris_pool") as DebrisPool
	return pool.active_count() if pool != null else 0
