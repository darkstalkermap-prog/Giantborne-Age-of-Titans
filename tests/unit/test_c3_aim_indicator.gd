extends TestSuite
## C3: the aim indicator's words - a titan's plate by its region ("shoulder_l" -> "left shoulder") - and its read
## API with nothing aimed at (the plan it draws is tested in tests/gate/test_c3_aim.gd).

const Indicator := preload("res://ui/hud/aim_indicator.gd")


func test_region_labels() -> void:
	assert_eq(Indicator.region_label("shoulder_l"), "left shoulder", "left")
	assert_eq(Indicator.region_label("greave_r"), "right greave", "right")
	assert_eq(Indicator.region_label("back"), "back", "one word")
	assert_eq(Indicator.region_label("flank_r"), "right flank", "the mend's flank")
	assert_eq(Indicator.region_label("forearm_r"), "right forearm", "a forearm")


func test_nothing_aimed_reads_empty() -> void:
	var w = Indicator.new()
	var r: Dictionary = w.indicated()
	assert_eq(str(r.entity_id), "", "no entity")
	assert_false(bool(r.reaches), "reaches nothing")
	assert_eq(str(r.source), "none", "no source")
	w.free()
