extends IntegrationSuite
## P24a (plan M6-M9 §3.6, §5.2; open_world_tech.md §3.5): the streaming walk at 16 m/s (a stage-6
## sprint) along the test world's whole route - its seam loop, the town's chunk with its props parts,
## the east, the 35-degree plateau and the pond - carried by WorldWalk with deterministic streaming
## (the headless step quota). It must keep 200 m or more of loaded ground ahead (the margin), never
## reload a chunk within 10 s of its unload (thrash), never hold more than 25 chunks, and keep the
## streaming work at p99 6 ms or less per frame (desktop headless). The work is wall time, which
## another process on a shared machine can stretch: when the first walk's p99 is over, a second walk
## (a fresh world, the same deterministic streaming) is measured and the better p99 is judged. M9 gate (final):
## judged by the shared load rule (tests/support/budget_rule.gd) - still over on a loaded machine, it warns.

const SCENE := "res://scenes/test/test_world.tscn"
const SPEED := 16.0
const WORK_P99_MS := 6.0


## One carried walk on a fresh test world; its report (the world is freed).
func _walk_once() -> Dictionary:
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	world.add_child(w)
	w.streamer.deterministic = true
	TestSpawn.disable_all_ai(w)
	var p := w.player()
	var guard := 0
	while not w.streamer.ring_ready(p.global_position) and guard < 200:
		w.streamer.load_ring_slice(p.global_position)
		guard += 1
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	add_child(walk)
	walk.start(p, w, null, {"speed": SPEED})
	var ticks := 0
	while not walk.done and ticks < 20000:
		await step_ticks(1)
		ticks += 1
	var r := walk.result()
	r["done"] = walk.done
	r["ticks"] = ticks
	print("P24A_WORLD_WALK " + JSON.stringify(walk.summary()))
	walk.queue_free()
	w.queue_free()
	await get_tree().process_frame
	return r


func test_the_streaming_walk_at_16_metres_a_second() -> void:
	var load_start := BudgetRule.load_average()
	var r := await _walk_once()
	assert_true(bool(r.done) and bool(r.finished), "the route was carried to its end (%d ticks)" % r.ticks)
	assert_true(float(r.metres) > 2500.0, "about 2.9 km (%.0f m)" % r.metres)
	assert_true((r.chunks_visited as PackedStringArray).has("c2_2"), "through the town's chunk")
	assert_true(float(r.min_margin_m) >= WorldWalk.MARGIN_REQUIRED_M, "200 m of loaded ground ahead or more (%.1f m)" % r.min_margin_m)
	assert_eq(int(r.thrash), 0, "no chunk reloaded within 10 s of its unload")
	assert_true(int(r.max_loaded) <= 25, "at most 25 chunks loaded (%d)" % r.max_loaded)
	assert_true(int(r.loads) >= 12 and int(r.unloads) >= 8, "it streamed (%d loads, %d unloads)" % [r.loads, r.unloads])
	assert_eq((r.check_failures as PackedStringArray).size(), 0, "no check failed: %s" % [r.check_failures])
	var steps: Dictionary = (r.streaming as Dictionary).get("steps_by_kind", {})
	assert_true(steps.has("props_add") and int(steps.props_add.n) >= 3, "the town's parts streamed in")
	var p99 := float(r.work_ms_p99)
	var seen := PackedStringArray(["%.2f" % p99])
	if p99 > WORK_P99_MS:
		var again := await _walk_once()
		p99 = minf(p99, float(again.work_ms_p99))
		seen.append("%.2f" % float(again.work_ms_p99))
	BudgetRule.judge(self, p99, WORK_P99_MS, load_start, "streaming work p99 %.2f ms (at most %.0f ms; the walks measured: %s)" % [
		p99, WORK_P99_MS, ", ".join(seen)])
