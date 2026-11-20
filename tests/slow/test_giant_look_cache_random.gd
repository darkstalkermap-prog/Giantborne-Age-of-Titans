extends TestSuite
## Gate B (the M12 review's finding 1), slow tier: random sequences of looks applied to one model end as a fresh
## model given the last look (tests/support/giant_look_cache_check.gd; the named sequences are in the default tier's
## tests/integration/test_giant_look_cache.gd). Before the fix 7 of the first 12 seeds differed.

const Check := preload("res://tests/support/giant_look_cache_check.gd")
const SEQUENCES := 24
const STEPS := 10


func test_random_sequences_of_looks_end_as_a_fresh_model() -> void:
	var fails := PackedStringArray()
	for trial in SEQUENCES:
		var d := Check.run(self, Check.random_sequence(1000 + trial, STEPS))
		if d != "":
			fails.append("seed %d:\n%s" % [1000 + trial, d])
	assert_eq("\n".join(fails), "", "random sequences that differ from a fresh model")
