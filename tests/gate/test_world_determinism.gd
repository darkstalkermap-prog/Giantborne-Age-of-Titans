extends TestSuite
## P24b (plan M6-M9 §2.8, decision 13; the risk "deterministic streaming does not make navigation
## deterministic"): two runs of the same world walk with AI on, each in its own process, play the
## same to the tick. The walk (--scenario=world_walk on the traced test world,
## tests/support/test_world_traced.tscn) sets off west of the wolf pack at x = -300, walks east through
## it - the pack chases the giant across the x = -256 seam on the human layer's per-chunk navmeshes
## until its leash turns it back and it deactivates - then on east over the x = 0 seam while the ring
## streams in the next column of chunks (their navmeshes loaded and their regions added on the layer
## maps as the giant walks, navigation readiness by the maps' iteration ids with async iterations off).
## Compared:
##   * the AUTOPILOT_RESULT lines, without the PerfProbe's block and the wall-time fields (every key
##     ending in "_ms" or holding "_ms_": the streaming work, the frame times) - byte-identical;
##   * the AI trace (world_ai_trace.gd: every half second the tick, the giant, every member's position
##     to the millimetre, state, awareness, path failures and re-paths) - every line identical.
## With async iterations on (the engine's default), the same check fails: the walks part by two ticks
## and their traces differ (tried on the branch). Gate tier: tools/check.sh --gate (about 20 s).

const RESULT_PREFIX := "AUTOPILOT_RESULT "
const SCENE := "res://tests/support/test_world_traced.tscn"
const SEAM_X := -256.0
const AUTOPLAY_S := 150


## The route: 10 m steps (the giant walks, it does not sprint: the wolves keep up) from x = -300 to
## -190, then 40 m steps on to x = 30, all at z = -200.
static func route() -> String:
	var pts := PackedStringArray()
	for x in range(-300, -189, 10):
		pts.append("%d:-200" % x)
	for x: int in [-150, -110, -70, -30, 10, 30]:
		pts.append("%d:-200" % x)
	return ";".join(pts)


## One world walk in a child Godot process: {"code", "result", "trace" (the P24B_AI lines), "output"}.
static func run_walk() -> Dictionary:
	var cmd := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--fixed-fps", "60", "--", "--no-user-settings", "--no-audio", "--level=" + SCENE,
		"--scenario=world_walk", "--autoplay=%d" % AUTOPLAY_S, "--route=" + route()])
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), cmd, output, true)
	var text := "\n".join(output)
	var result := ""
	var trace := PackedStringArray()
	for line in text.split("\n"):
		if line.begins_with(RESULT_PREFIX) and result == "":
			result = line.substr(RESULT_PREFIX.length()).strip_edges()
		elif line.begins_with(WorldAiTrace.PREFIX):
			trace.append(line.strip_edges())
	return {"code": code, "result": result, "trace": trace, "output": text}


## A result without the probe's block and the wall-time fields; "" when it does not parse.
static func comparable(result: String) -> String:
	var parsed: Variant = JSON.parse_string(result)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var r: Dictionary = parsed
	r.erase("perf")
	return JSON.stringify(_without_timings(r), "", true)


static func _without_timings(v: Variant) -> Variant:
	if typeof(v) == TYPE_DICTIONARY:
		var out := {}
		for k: Variant in v:
			var key := str(k)
			if key.ends_with("_ms") or key.contains("_ms_"):
				continue
			out[k] = _without_timings(v[k])
		return out
	if typeof(v) == TYPE_ARRAY:
		var out := []
		for e: Variant in v:
			out.append(_without_timings(e))
		return out
	return v


## The trace lines' states: [{tick, giant, members: {id: [pos, state, aware, failures, repaths] or status}}].
static func parse_trace(lines: PackedStringArray) -> Array:
	var out := []
	for line in lines:
		var v: Variant = JSON.parse_string(line.substr(WorldAiTrace.PREFIX.length()))
		if typeof(v) == TYPE_DICTIONARY:
			out.append(v)
	return out


## Wolves that chased the giant over the seam: aware and not returning on the other side of x = -256
## from where they were first seen.
static func seam_chasers(trace: Array) -> PackedStringArray:
	var first := {}
	var out := PackedStringArray()
	for t: Dictionary in trace:
		var members: Dictionary = t.get("members", {})
		for id: String in members:
			var m: Variant = members[id]
			if not id.begins_with("test_world.wolves.") or typeof(m) != TYPE_ARRAY:
				continue
			var x := float(str(m[0]).get_slice(",", 0))
			if not first.has(id):
				first[id] = x
			elif bool(m[2]) and str(m[1]) != "Return" and (float(first[id]) < SEAM_X) != (x < SEAM_X) and not out.has(id):
				out.append(id)
	return out


func test_two_world_walks_with_a_chase_across_a_seam_play_the_same() -> void:
	var a := run_walk()
	var b := run_walk()
	for pair: Array in [[a, "first"], [b, "second"]]:
		var r: Dictionary = pair[0]
		assert_true(str(r.result) != "", "the %s walk reports (exit %d): %s" % [pair[1], int(r.code), str(r.output).right(300)])
		assert_eq(int(r.code), 0, "the %s walk exits cleanly" % pair[1])
		assert_true(str(r.result).contains("\"errors\":0"), "the %s walk: no errors" % pair[1])
	var ca := comparable(str(a.result))
	var cb := comparable(str(b.result))
	assert_true(ca != "" and cb != "", "both results parse")
	assert_true(ca == cb, "the AUTOPILOT_RESULT lines are identical but for the timings%s" % [
		"" if ca == cb else (": %s" % [first_differences(JSON.parse_string(ca), JSON.parse_string(cb))])])
	var ta: PackedStringArray = a.trace
	var tb: PackedStringArray = b.trace
	assert_true(ta.size() >= 100, "the AI was traced every half second (%d lines)" % ta.size())
	assert_eq(ta.size(), tb.size(), "as often in both walks")
	var first_diff := -1
	for i in mini(ta.size(), tb.size()):
		if ta[i] != tb[i]:
			first_diff = i
			break
	assert_eq(first_diff, -1, "every trace line identical%s" % ("" if first_diff < 0 else
		(":\n  %s\n  %s" % [ta[first_diff].left(400), tb[first_diff].left(400)])))
	# What the walks did: the pack chased the giant over the seam without a path failure, the ring
	# streamed chunks with their navmeshes.
	var trace := parse_trace(ta)
	var chasers := seam_chasers(trace)
	assert_true(chasers.size() >= 2, "wolves chased the giant over the x = -256 seam: %s" % [chasers])
	var failures := 0
	var aware := 0
	for t: Dictionary in trace:
		var members: Dictionary = t.get("members", {})
		var n := 0
		for id: String in members:
			var m: Variant = members[id]
			if id.begins_with("test_world.wolves.") and typeof(m) == TYPE_ARRAY:
				failures = maxi(failures, int(m[3]))
				if bool(m[2]):
					n += 1
		aware = maxi(aware, n)
	assert_eq(aware, 5, "the whole pack was on the giant")
	assert_eq(failures, 0, "no wolf had a path failure")
	var ww: Dictionary = (JSON.parse_string(str(a.result)) as Dictionary).get("world_walk", {})
	assert_true(bool(ww.get("finished", false)), "the route was walked to its end")
	assert_true(int(ww.get("seam_crossings", 0)) >= 2, "over both seams (%d crossings)" % int(ww.get("seam_crossings", 0)))
	var steps: Dictionary = (ww.get("streaming", {}) as Dictionary).get("steps_by_kind", {})
	var adds := int((steps.get("nav_add", {}) as Dictionary).get("n", 0))
	assert_true(int(ww.get("loads", 0)) >= 3 and adds >= 9,
		"chunks streamed in with their navmeshes on the way (%d loads, %d region adds)" % [int(ww.get("loads", 0)), adds])
	print("    world determinism: %d trace lines and the results identical; %d loads, %d region adds; wolves over the seam %s" % [
		ta.size(), int(ww.get("loads", 0)), adds, chasers])


## The first differing key paths of two parsed results (for the failure message).
static func first_differences(a: Variant, b: Variant, path := "", out: Array = []) -> Array:
	if out.size() >= 6:
		return out
	if typeof(a) != typeof(b):
		out.append("%s: %s / %s" % [path, str(a).left(60), str(b).left(60)])
	elif typeof(a) == TYPE_DICTIONARY:
		for k: Variant in a:
			if not (b as Dictionary).has(k):
				out.append("%s/%s: missing" % [path, k])
			else:
				first_differences(a[k], b[k], "%s/%s" % [path, k], out)
	elif typeof(a) == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			out.append("%s: %d / %d entries" % [path, (a as Array).size(), (b as Array).size()])
		else:
			for i in (a as Array).size():
				first_differences(a[i], b[i], "%s[%d]" % [path, i], out)
	elif a != b:
		out.append("%s: %s / %s" % [path, str(a).left(60), str(b).left(60)])
	return out
