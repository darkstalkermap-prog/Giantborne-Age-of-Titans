extends TestSuite
## Randomize over 1,000 seeds in every scope (P42; plan M10 §3.2, §2.10): from the default record before a
## line is chosen, and from a Warrior's record (its tunic and jerkin hide the chest and back) of a Stoneblood
## giant with the mark hidden (250 seeds a scope). Every record is valid, never puts a design where the outfit hides it, keeps
## the outfit when asked and the mark's choice, and never touches Sim.rng
## (tests/support/appearance_random_check.gd; the default tier's test_appearance_record runs 6 seeds).

const RandomCheck := preload("res://tests/support/appearance_random_check.gd")
const SEEDS := 1000


## The second base's seeds (its rules are the same; the default's 1,000 a scope are the plan's count).
const SEEDS_WARRIOR := 250


func _run(seeds: int, base: Dictionary, line: String, label: String) -> void:
	var r := RandomCheck.run(seeds, base, line)
	assert_eq(str(r.error), "", "%s: every random record keeps the rules" % label)
	assert_eq(int(r.count), seeds * Appearance.RANDOM_SCOPES.size(), "%s: %d records" % [label, int(r.count)])


func test_a_thousand_seeds_in_every_scope_from_the_default() -> void:
	_run(SEEDS, {}, "", "the default, no line")


func test_every_scope_from_a_stoneblood_warrior() -> void:
	var r := Appearance.default_record()
	r.outfit.set = "outfit.warrior"
	r.mark = "none"
	r.skin = "skin.ashen"
	_run(SEEDS_WARRIOR, r, "ancestry.stoneblood", "a Stoneblood warrior")
