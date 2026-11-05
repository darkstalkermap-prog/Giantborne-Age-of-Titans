extends TestSuite
## PerfProbe (P14, plan §3.16): the percentile math (nearest rank), summaries, the §5.4 budget
## verdicts, and a short live capture (ticks measured from inside, Sim.step within the tick, the
## headless and --fixed-fps "N/A" reasons, warmup, sections, hits counted).


func _values(a: Array) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	for v: Variant in a:
		out.append(float(v))
	return out


func test_percentiles_by_nearest_rank() -> void:
	var hundred := PackedFloat64Array()
	for i in range(1, 101):
		hundred.append(float(i))
	assert_eq(PerfProbe.percentile(hundred, 50.0), 50.0, "p50 of 1..100")
	assert_eq(PerfProbe.percentile(hundred, 95.0), 95.0, "p95 of 1..100")
	assert_eq(PerfProbe.percentile(hundred, 99.0), 99.0, "p99 of 1..100")
	assert_eq(PerfProbe.percentile(hundred, 100.0), 100.0, "p100 is the maximum")
	assert_eq(PerfProbe.percentile(hundred, 0.0), 1.0, "p0 is the minimum (rank clamped to 1)")
	var four := _values([10, 20, 30, 40])
	assert_eq(PerfProbe.percentile(four, 50.0), 20.0, "p50 of four: rank ceil(2.0) = 2")
	assert_eq(PerfProbe.percentile(four, 51.0), 30.0, "just above half: rank 3")
	assert_eq(PerfProbe.percentile(four, 75.0), 30.0, "p75: rank 3")
	assert_eq(PerfProbe.percentile(four, 95.0), 40.0, "p95 of four: rank ceil(3.8) = 4")
	assert_eq(PerfProbe.percentile(_values([7]), 99.0), 7.0, "one sample is every percentile")
	assert_true(is_nan(PerfProbe.percentile(PackedFloat64Array(), 50.0)), "no samples: NAN")
	# 1000 ticks with 2% spikes: p95 stays on the floor, p99 and the maximum see the spikes.
	var ticks := PackedFloat64Array()
	for i in 1000:
		ticks.append(12.0 if i % 50 == 0 else 2.0)
	ticks.sort()
	assert_eq(PerfProbe.percentile(ticks, 95.0), 2.0, "2% spikes do not move p95")
	assert_eq(PerfProbe.percentile(ticks, 99.0), 12.0, "but p99 sees them")


func test_summaries() -> void:
	var s := PerfProbe.summarize(_values([3.0, 1.0, 2.0, 4.0, 5.0]))
	assert_eq(int(s.n), 5, "n")
	assert_eq(float(s.p50), 3.0, "p50 of unsorted input")
	assert_eq(float(s.min), 1.0, "min")
	assert_eq(float(s.max), 5.0, "max")
	assert_eq(float(s.mean), 3.0, "mean")
	assert_eq(float(s.p95), 5.0, "p95")
	var odd := PerfProbe.summarize(_values([0.12345, 0.12355]))
	assert_eq(float(odd.max), 0.124, "rounded to 0.001")
	assert_eq(PerfProbe.summarize(PackedFloat64Array()), {"n": 0}, "no samples")
	var input := _values([3, 1, 2])
	PerfProbe.summarize(input)
	assert_eq(input[0], 3.0, "the input is not sorted in place")


func test_budget_verdicts() -> void:
	var at := PerfProbe.budgets({"cpu_tick_ms": {"p95": 8.0}, "frame_ms": {"p95": 16.7, "p99": 33.3},
		"draw_calls": {"max": 250.0}})
	assert_eq(at.cpu_tick_p95_ms, {"limit": 8.0, "value": 8.0, "ok": true}, "p95 8 ms is within the 8 ms budget")
	assert_true(bool(at.frame_p95_ms.ok), "frame p95 16.7 ms is within <= 16.7")
	assert_false(bool(at.frame_p99_ms.ok), "frame p99 must stay strictly below 33.3 ms")
	assert_true(bool(at.draw_calls_max.ok), "250 draw calls is within the budget")
	var over := PerfProbe.budgets({"cpu_tick_ms": {"p95": 8.01}, "frame_ms": {"p95": 17.0, "p99": 20.0},
		"draw_calls": {"max": 251.0}})
	assert_false(bool(over.cpu_tick_p95_ms.ok), "8.01 ms is over")
	assert_false(bool(over.frame_p95_ms.ok), "17 ms frames are over")
	assert_true(bool(over.frame_p99_ms.ok), "p99 20 ms is under 33.3")
	assert_false(bool(over.draw_calls_max.ok), "251 draw calls are over")
	var na := PerfProbe.budgets({"cpu_tick_ms": {"p95": 1.0}, "frame_ms": "N/A (--fixed-fps: constant frame delta)",
		"draw_calls": "N/A (headless: nothing is rendered)"})
	assert_eq(str(na.frame_p95_ms), "N/A (--fixed-fps: constant frame delta)", "an unmeasured metric stays N/A")
	assert_eq(str(na.draw_calls_max), "N/A (headless: nothing is rendered)", "draw calls N/A headless")
	assert_eq(str(PerfProbe.budgets({}).cpu_tick_p95_ms), "N/A (no samples)", "nothing measured")


func test_live_capture() -> void:
	var probe := PerfProbe.new()
	probe.label = "unit"
	probe.warmup_ticks = 5
	add_child(probe)
	probe.section = "first"
	await step_ticks(20)
	probe.section = "second"
	await step_ticks(20)
	var hit := HitResult.new()
	Events.hit_resolved.emit(Sim.tick, hit)
	Events.hit_resolved.emit(Sim.tick, hit)
	await step_ticks(1)
	probe.finish()
	var r := probe.result()
	await step_ticks(3)
	assert_eq(probe.result().ticks, r.ticks, "nothing is sampled after finish()")
	assert_true(int(r.ticks) >= 30 and int(r.ticks) <= 37, "about 41 ticks minus 5 warmup (%d)" % r.ticks)
	var tick: Dictionary = r.cpu_tick_ms
	var sim: Dictionary = r.sim_ms
	assert_eq(int(tick.n), int(r.ticks), "one cpu_tick_ms sample per tick")
	assert_true(float(tick.min) > 0.0, "a tick takes time (%s)" % tick)
	assert_true(float(sim.max) <= float(tick.max) + 0.001, "Sim.step is part of the tick (%s / %s)" % [sim, tick])
	assert_true(r.idle_ms is Dictionary and int(r.idle_ms.n) > 0, "idle time measured")
	assert_eq(r.fixed_fps, true, "the suite runs with --fixed-fps: every frame delta is the same")
	assert_true(str(r.frame_ms).begins_with("N/A"), "frame_ms is N/A under --fixed-fps (%s)" % [r.frame_ms])
	assert_true(str(r.draw_calls).begins_with("N/A (headless"), "draw calls are N/A headless")
	assert_true(str(r.gpu_render_ms).begins_with("N/A (headless"), "GPU time is N/A headless")
	assert_true(r.nodes is Dictionary and float(r.nodes.max) > 0.0, "node count sampled")
	assert_eq(int(r.counters.hits_resolved), 2, "hits resolved counted")
	assert_eq(str(r.label), "unit", "label")
	assert_true(r.sections.has("first") and r.sections.has("second"), "per-section summaries (%s)" % [r.sections.keys()])
	assert_true(int(r.sections.first.cpu_tick_ms.n) + int(r.sections.second.cpu_tick_ms.n) == int(tick.n),
		"every tick filed under its section")
	assert_true(r.budgets.cpu_tick_p95_ms is Dictionary, "the tick budget is judged")
	assert_true(str(r.budgets.draw_calls_max).begins_with("N/A"), "the draw-call budget is N/A headless")
	assert_true(JSON.stringify(r).length() > 100, "the result serialises")
	assert_eq(PerfProbe.active_combatants(get_tree()), 0, "no enemies here")
	assert_eq(PerfProbe.debris_count(get_tree()), 0, "no debris pool here")
	probe.queue_free()
	await step_ticks(1)
