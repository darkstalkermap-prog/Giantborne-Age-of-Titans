extends TestSuite
## Gate B (the M12 review's finding 1): GiantLook.apply's skip-unchanged cache. A piece hidden while the build or
## the layering changed is shown again with the values of the last look, as a fresh model given that look has
## them (tests/support/giant_look_cache_check.gd; random sequences in tests/slow/test_giant_look_cache_random.gd, where
## seed 1000's ten looks left the braies and the furs with an old build before the fix).

const Check := preload("res://tests/support/giant_look_cache_check.gd")


func test_a_garment_shown_again_after_a_build_change_has_the_new_build() -> void:
	assert_eq(Check.run(self, [
		Check.record({"legs": "garment.braies", "armour": "garment.jerkin"}),
		Check.record({"legs": "garment.braies"}, Vector2(1.0, 1.0)),
		Check.record({"legs": "garment.braies", "armour": "garment.jerkin"}, Vector2(1.0, 1.0)),
	]), "", "the jerkin put on again after the build moved")


func test_an_outer_garment_shown_again_after_the_inner_one_went_has_no_push() -> void:
	assert_eq(Check.run(self, [
		Check.record({"legs": "garment.braies", "chest": "garment.tunic", "armour": "garment.mail_hauberk"}),
		Check.record({"legs": "garment.braies", "chest": "garment.tunic"}),
		Check.record({"legs": "garment.braies"}),
		Check.record({"legs": "garment.braies", "armour": "garment.mail_hauberk"}),
	]), "", "the hauberk put on again over no tunic")


func test_beads_shown_again_after_a_build_change_have_the_new_build() -> void:
	var beads := {"hair": {"style": "hair.braids_crown", "color": "haircolor.chestnut", "grey": 0.1,
		"beads": "bead.bronze_rings"}}
	var none := {"hair": {"style": "hair.braids_crown", "color": "haircolor.chestnut", "grey": 0.1, "beads": "bead.none"}}
	assert_eq(Check.run(self, [
		Check.record({"legs": "garment.braies"}, Vector2.ZERO, beads),
		Check.record({"legs": "garment.braies"}, Vector2(-1.0, 1.0), none),
		Check.record({"legs": "garment.braies"}, Vector2(-1.0, 1.0), beads),
	]), "", "the beads put on again after the build moved")

