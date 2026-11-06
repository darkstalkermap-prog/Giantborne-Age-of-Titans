extends TestSuite
## M6 gate (the Valley matrix's expert intimidate runs lost the crown stage to its 240 s watchdog):
## the Barrow's wardens against a stage-3 giant. Their wolves, broken by its roar or its blows, rout
## instead of coming back to harass (tactics.outmatched_rout), and the bot takes the crown once the
## wardens left are out of its reach - the stall's wait now lasts while the giant stays within
## ValleyBot.STALL_KEEP_M of the encounter, where a dodge from a wolf biting from behind restarted it
## every few seconds. From the pre-crown save (a stage-3 giant at the Barrow's waystone) the expert
## intimidate bot claims the crown inside the watchdog, with no breach, on seeds 1 and 2: before the
## bot's fix both ran out the 240 s with one unbroken wolf harassing the giant at the crown.
## Gate tier: tools/check.sh --gate (under a minute: two Continue runs of about 90 s of play each).

const DETERMINISM := preload("res://tests/gate/test_valley_audio_determinism.gd")
const FIXTURE := "res://tests/fixtures/saves/v1_pre_crown.json"
const SAVE_ROOT := "user://gate_barrow_crown"
const RUN_S := 300


func test_the_expert_bot_claims_the_crown_inside_the_watchdog() -> void:
	var fixture := FileAccess.get_file_as_string(FIXTURE)
	assert_true(fixture != "", "the pre-crown save fixture reads")
	for seed in [1, 2]:
		var dir := "%s/seed_%d" % [SAVE_ROOT, seed]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		for f: String in ["valley_1.json", "valley_1.json.bak"]:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join(f)))
		var file := FileAccess.open(dir.path_join("valley_1.json"), FileAccess.WRITE)
		file.store_string(fixture)
		file.close()
		var r := DETERMINISM.run_valley(false, PackedStringArray(["--save-dir=" + dir, "--mode=valley", "--continue",
			"--autoplay=%d" % RUN_S, "--bot-village=intimidate", "--bot-skill=expert", "--bot-seed=%d" % seed]))
		var parsed: Variant = JSON.parse_string(str(r.result))
		assert_true(typeof(parsed) == TYPE_DICTIONARY, "seed %d reports (exit %d): %s" % [seed, int(r.code),
			str(r.output).right(300)])
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var vb: Dictionary = (parsed as Dictionary).get("valley_bot", {})
		var crown := -1.0
		for o: Dictionary in vb.get("objectives", []):
			if str(o.get("id", "")) == "quest.main:crown":
				crown = float(o.get("seconds", -1.0))
		print("    seed %d: the crown stage took %.1f s, completed %s, breaches %s" % [seed, crown,
			vb.get("completed"), vb.get("breaches")])
		assert_eq(int((parsed as Dictionary).get("errors", -1)), 0, "seed %d: no errors" % seed)
		assert_true(bool(vb.get("completed", false)), "seed %d: the crown is claimed" % seed)
		assert_true((vb.get("breaches", []) as Array).is_empty(), "seed %d: no watchdog breach (%s)" % [seed, vb.get("breaches")])
		assert_true(crown > 0.0 and crown < ValleyBot.OBJECTIVE_TIMEOUT_S,
			"seed %d: inside the crown stage's %.0f s watchdog (%.1f s)" % [seed, ValleyBot.OBJECTIVE_TIMEOUT_S, crown])
