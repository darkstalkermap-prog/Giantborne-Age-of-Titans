extends TestSuite
## P60 (plan M11 §2.9, §3.13 design 6, §0.3 "nothing that plays changes"): the people are presentation only. Each
## run is its own child Godot process (this project, this user:// folder), with 0 errors, 0 warnings and nothing left
## behind at exit:
##   * the seeded 120 s sandbox soak with the people off (--no-skin) and on (--skin --skin-stats) prints
##     byte-identical AUTOPILOT_RESULT lines, and the soak's numbers are the recorded baseline's (41 attacks, 33
##     hits resolved, 4 enemy kills, 2 fence breaks, 7,201 frames, 0 errors);
##   * the formation stress case (two regiments of 40, a stage-4 giant walking their front, --stress-formations)
##     with the people off and on prints the same result but for what draws (the PerfProbe's timings, the
##     crowd's peaks, the engine's node samples);
##   * positive controls, PEOPLE_STATS with the people on: skinned frames and promotions above 0, at least two
##     body variants drawn, crowd instances above 0 (the stress case), and never more skinned than the cap.
## The Valley's seeded bot twin with --skin and --no-skin (test_giant_determinism) runs the people too: --skin
## is the people's switch as well (PersonRig.layers_enabled). The plan's comparison with 0.10.0-m10 is not made
## here: 0.12.0-m12 changed one rule of play (a guard walking home waits when pressed against the giant), so the
## people's own on/off twins and the recorded soak are the controls (docs/systems/P60.md).
## P62 (plan M11 §3.15): the townsfolk, the riders and the rival giants too:
##   * a world walk through every town (the giant carried at 40 m/s by the six settlements' greens - Millford,
##     Brannock, Fort Aldmere, Skarn, Harrok's Hall, Hollowmere - on a new game) with the people off and on prints
##     the same result but for the streamer's wall-clock timings, with the townsfolk's and the riders' variants drawn;
##   * the Moot test level (Harrok's fight, the clans' watchers: the giants' realistic model) soaked for 40 s with
##     the people off and on prints the same AUTOPILOT_RESULT, Harrok's and the watchers' rigs posed.
## P64 (plan M11 §3.17): the brutes, the bosses and the wolves too: the Ogre King's arena, the Troll Matriarch's den
## (her whelps) and the stress arena (its wolf pack and brutes), each soaked for 40 s with the people (and so the creatures)
## on and off: the same AUTOPILOT_RESULT, and PEOPLE_STATS' "others" shows them skinned, never more than the cap.
## Gate tier: tools/check.sh --gate.

const GIANT_DET := preload("res://tests/gate/test_giant_determinism.gd")
const SOAK_S := 120
const STRESS_S := 40
const PEOPLE_PREFIX := "PEOPLE_STATS "
const BASELINE := {"attacks": 41, "hits_resolved": 33, "enemy_kills": 4, "fence_breaks": 2, "frames": 7201, "errors": 0}
const STRESS_ARGS := ["--level=res://scenes/test/formation_test.tscn", "--scenario=stress", "--stress-formations"]
## P62: the world walk through the six settlements' greens (world_draw_probe.gd's viewpoints) and the Moot's soak.
const TOWNS_ROUTE := "-380:618;60:565;650:-62;440:-640;-560:-690;-610:22"
const WALK_ARGS := ["--mode=world", "--new-game", "--scenario=world_walk", "--route=" + TOWNS_ROUTE, "--walk-speed=40",
	"--autoplay=400"]
const MOOT_ARGS := ["--level=res://scenes/test/moot_test.tscn", "--autoplay=40"]
## Variants the walk must draw skinned: villagers and named characters in their towns, the cavalry's riders.
const WALK_VARIANTS := ["edda", "reeve_tamsin", "elder_d", "rider_a", "villager_a"]   # (P65b: Sedge is the elders' elder_d)
## P64: the creatures' soaks (the King's arena, the Matriarch's den, the stress arena's wolves and brutes).
const CREATURE_LEVELS := ["res://scenes/test/boss_arena_test.tscn", "res://scenes/test/troll_den_test.tscn",
	"res://scenes/test/stress_arena.tscn"]
const CREATURE_SOAK_S := 40


## One child run with its PEOPLE_STATS line parsed ({} without one).
static func run(args: PackedStringArray) -> Dictionary:
	var r: Dictionary = GIANT_DET.run_child(args)
	r["people"] = {}
	for line in str(r.output).split("\n"):
		if line.begins_with(PEOPLE_PREFIX):
			var p: Variant = JSON.parse_string(line.substr(PEOPLE_PREFIX.length()).strip_edges())
			r["people"] = p if typeof(p) == TYPE_DICTIONARY else {}
	return r


func _clean(label: String, r: Dictionary) -> void:
	assert_true(str(r.result) != "", "%s reports (exit %d): %s" % [label, int(r.code), str(r.output).right(400)])
	assert_true(str(r.result).contains("\"errors\":0") and str(r.result).contains("\"warnings\":0"),
		"%s: no errors or warnings (%s)" % [label, str(r.result).left(200)])
	for marker: String in GIANT_DET.EXIT_MARKERS:
		assert_false(str(r.output).contains(marker), "%s exits cleanly (no \"%s\")" % [label, marker])


## P64c (the M13 gate review): the result's hits_resolved (-1 without one): a soak that resolved no blow compares
## nothing.
static func hits_resolved(result: String) -> int:
	var parsed: Variant = JSON.parse_string(result)
	return int((parsed as Dictionary).get("hits_resolved", -1)) if typeof(parsed) == TYPE_DICTIONARY else -1


## A stress result without what draws (the probe, the crowd's peaks, the node samples).
static func comparable(result: String) -> String:
	var parsed: Variant = JSON.parse_string(result)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var strip := func(d: Variant, self_ref: Callable) -> void:
		if typeof(d) == TYPE_DICTIONARY:
			for k in ["perf", "promoted_peak", "crowd_instances_peak", "nodes", "load_nodes"]:
				(d as Dictionary).erase(k)
			for v: Variant in (d as Dictionary).values():
				self_ref.call(v, self_ref)
	strip.call(parsed, strip)
	return JSON.stringify(parsed, "", true)


func test_the_soak_is_identical_with_the_people_on_and_off_and_matches_the_baseline() -> void:
	var off := run(PackedStringArray(["--autoplay=%d" % SOAK_S, "--no-skin"]))
	_clean("the soak without the people", off)
	var on := run(PackedStringArray(["--autoplay=%d" % SOAK_S, "--skin", "--skin-stats"]))
	_clean("the soak with the people", on)
	assert_eq(str(on.result), str(off.result), "AUTOPILOT_RESULT byte-identical with the people on and off")
	var parsed: Variant = JSON.parse_string(str(off.result))
	var flat := JSON.stringify(parsed)
	for k: String in BASELINE:
		assert_true(flat.contains("\"%s\":%d" % [k, int(BASELINE[k])]), "the soak's %s is the baseline's %d" % [k, int(BASELINE[k])])
	var p: Dictionary = on.people
	assert_true(bool(p.get("layers", false)), "the people ran (PEOPLE_STATS: %s)" % str(on.people).left(300))
	assert_true(int(p.get("skinned_frames", 0)) > 100 and int(p.get("promotions", 0)) > 0,
		"skinned frames and promotions (%s, %s)" % [p.get("skinned_frames"), p.get("promotions")])
	assert_true(int(p.get("skinned_max", 99)) <= PersonRig.MAX_SKINNED, "never more skinned than the cap")
	print("    test_people_determinism: the soak, %s skinned frames, %s promotions, variants %s" % [
		p.get("skinned_frames"), p.get("promotions"), p.get("variants")])


func test_the_formation_stress_plays_the_same_with_the_people_on_and_off() -> void:
	var runs := {}
	for mode: String in ["on", "off"]:
		var args := PackedStringArray(STRESS_ARGS)
		args.append("--autoplay=%d" % STRESS_S)
		args.append_array(["--skin", "--skin-stats"] if mode == "on" else ["--no-skin"])
		runs[mode] = run(args)
		_clean("the formation stress (people %s)" % mode, runs[mode])
	var a := comparable(str(runs.on.result))
	var b := comparable(str(runs.off.result))
	assert_true(a != "" and b != "", "both results parse")
	assert_true(a == b, "the formation stress is identical with the people on and off%s" % ["" if a == b else
		(": %s" % [GIANT_DET.first_differences(JSON.parse_string(a), JSON.parse_string(b))])])
	var p: Dictionary = runs.on.people
	assert_true(int(p.get("crowd_instances", 0)) > 0, "crowd instances drawn (%s)" % p.get("crowd_instances"))
	assert_true((p.get("variants", []) as Array).size() >= 2, "at least two variants drawn skinned (%s)" % [p.get("variants")])
	assert_true(int(p.get("skinned_max", 99)) <= PersonRig.MAX_SKINNED and int(p.get("skinned_max", 0)) > 0,
		"skinned, never more than the cap (%s)" % p.get("skinned_max"))
	print("    test_people_determinism: the formation stress, %s crowd instances (largest frame %s), %s skinned frames, variants %s" % [
		p.get("crowd_instances"), p.get("crowd_instances_max"), p.get("skinned_frames"), p.get("variants")])


## A result without the wall clock's timings (the PerfProbe's, the streamer's, anything in milliseconds) and what
## draws (P62: the world walk's report keeps every count, chunk and region change).
static func without_timings(result: String) -> String:
	var parsed: Variant = JSON.parse_string(result)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var strip := func(d: Variant, self_ref: Callable) -> void:
		if typeof(d) == TYPE_DICTIONARY:
			for k: Variant in (d as Dictionary).keys():
				var key := str(k)
				if key in ["perf", "nodes", "load_nodes", "promoted_peak", "crowd_instances_peak"] or key.ends_with("_ms") \
						or key.contains("work_ms") or key == "steps_by_kind":
					(d as Dictionary).erase(k)
			for v: Variant in (d as Dictionary).values():
				self_ref.call(v, self_ref)
	strip.call(parsed, strip)
	return JSON.stringify(parsed, "", true)


func test_a_world_walk_through_every_town_plays_the_same_with_the_people_on_and_off() -> void:
	var runs := {}
	for mode: String in ["on", "off"]:
		var args := PackedStringArray(WALK_ARGS)
		args.append_array(["--skin", "--skin-stats"] if mode == "on" else ["--no-skin"])
		runs[mode] = run(args)
		_clean("the towns' walk (people %s)" % mode, runs[mode])
	var a := without_timings(str(runs.on.result))
	var b := without_timings(str(runs.off.result))
	assert_true(a != "" and b != "", "both results parse")
	assert_true(a == b, "the towns' walk is identical with the people on and off%s" % ["" if a == b else
		(": %s" % [GIANT_DET.first_differences(JSON.parse_string(a), JSON.parse_string(b))])])
	var ww: Variant = (JSON.parse_string(str(runs.off.result)) as Dictionary).get("world_walk", {}) \
		if JSON.parse_string(str(runs.off.result)) is Dictionary else {}
	assert_true(ww is Dictionary and bool((ww as Dictionary).get("finished", false)), "the walk finished its route")
	var p: Dictionary = runs.on.people
	for v: String in WALK_VARIANTS:
		assert_true((p.get("variants", []) as Array).has(v), "%s drawn skinned on the way (%s)" % [v, p.get("variants")])
	assert_true(int(p.get("skinned_max", 99)) <= PersonRig.MAX_SKINNED, "never more skinned than the cap")
	print("    test_people_determinism: the towns' walk, %s skinned frames, %s crowd instances, variants %s" % [
		p.get("skinned_frames"), p.get("crowd_instances"), p.get("variants")])


func test_the_moot_plays_the_same_with_the_giants_skinned_and_not() -> void:
	var runs := {}
	for mode: String in ["on", "off"]:
		var args := PackedStringArray(MOOT_ARGS)
		args.append_array(["--skin", "--skin-stats"] if mode == "on" else ["--no-skin"])
		runs[mode] = run(args)
		_clean("the Moot (giants %s)" % mode, runs[mode])
	assert_eq(str(runs.on.result), str(runs.off.result), "AUTOPILOT_RESULT byte-identical with the giants skinned and not")
	assert_true(str(runs.on.result).contains("\"attacks\":") and not str(runs.on.result).contains("\"attacks\":0,"),
		"the fight was fought (%s)" % str(runs.on.result).left(120))
	assert_true(hits_resolved(str(runs.on.result)) > 0, "P64c: blows were resolved (%d)" % hits_resolved(str(runs.on.result)))
	var skin: Variant = JSON.parse_string(str(runs.on.skin))
	assert_true(typeof(skin) == TYPE_DICTIONARY and int((skin as Dictionary).get("rigs", 0)) >= 3,
		"Harrok's and the watchers' rigs ran (SKIN_STATS rigs %s)" % [(skin as Dictionary).get("rigs") if skin is Dictionary else "?"])
	assert_eq(str((skin as Dictionary).get("look", "")) if skin is Dictionary else "", "appearance_preset.wanderer",
		"SKIN_STATS' look is the player's")



func test_the_bosses_the_den_and_a_wolf_pack_play_the_same_with_the_creatures_skinned_and_not() -> void:
	for level: String in CREATURE_LEVELS:
		var runs := {}
		for mode: String in ["on", "off"]:
			var args := PackedStringArray(["--level=" + level, "--autoplay=%d" % CREATURE_SOAK_S])
			args.append_array(["--skin", "--skin-stats"] if mode == "on" else ["--no-skin"])
			runs[mode] = run(args)
			_clean("%s (creatures %s)" % [level.get_file(), mode], runs[mode])
		assert_eq(str(runs.on.result), str(runs.off.result), "%s: AUTOPILOT_RESULT byte-identical with the creatures skinned and not" % level.get_file())
		assert_true(hits_resolved(str(runs.on.result)) > 0, "%s: P64c: blows were resolved (%d)" % [level.get_file(),
			hits_resolved(str(runs.on.result))])
		var o: Dictionary = (runs.on.people as Dictionary).get("others", {})
		assert_true(int(o.get("skinned_frames", 0)) > 100, "%s: the creatures drawn skinned (%s)" % [level.get_file(), o])
		assert_true(int(o.get("skinned_max", 99)) <= CreatureSlots.MAX_SKINNED + 2,
			"%s: never more than the cap (and the bosses) at once (%s)" % [level.get_file(), o.get("skinned_max")])
		print("    test_people_determinism: %s, the creatures' %s skinned frames, at most %s at once" % [level.get_file(),
			o.get("skinned_frames"), o.get("skinned_max")])
