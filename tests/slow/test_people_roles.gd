extends TestSuite
## P59 (plan M11 §3.12): every role's scene as Godot imports it - the default tier's test_people_assets checks the
## soldier's; this checks the archer's, the mage's, the crew's, the villager's and the elder's the same way (each
## variant one skinned surface of at most 5,000 triangles on the 23 bones, the crowd poses at most 600, the far mesh
## at most 150, the three maps).

const ASSETS_TEST := preload("res://tests/integration/test_people_assets.gd")


func test_every_other_role_loads_as_the_soldier_does() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSETS_TEST.MANIFEST))
	assert_true(doc is Dictionary, "the people's manifest parses")
	var index: Dictionary = (doc as Dictionary).index
	var others: Array = ASSETS_TEST.ROLES.filter(func(r: String) -> bool: return r != "soldier")
	assert_eq(others.size(), 7, "seven roles besides the soldier (P59b: the notables and the riders)")
	ASSETS_TEST.check_roles(self, index, others)
