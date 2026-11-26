extends TestSuite
## The long walks over the data that the default tier samples (P57; plan M11 §1.7 rule 2: moved, not deleted, as the
## wardrobe and the catalogue II grew them): every option of every set - Part B's garments by slot, metals, build and
## face sliders, accessories and beads with M10's sets - applied to the real model with validate() empty and the
## meshes shown as the look says (tests/support/option_walk.gd; test_giant_look_real walks the first and the last of
## each set), and the random greys of 400 seeds a scope (test_creator_screen draws 40).

const MODEL := "res://scenes/player/giant_model.tscn"
const CreatorScreenTests := preload("res://tests/slow/test_creator_screen.gd")

var _root: Node3D


func after_each() -> void:
	if is_instance_valid(_root):
		_root.free()
	_root = null


func test_every_option_of_every_set_applies_with_validate_empty() -> void:
	if not ResourceLoader.exists(MODEL):
		print("    test_giant_look_walks: skipped - %s does not exist" % MODEL)
		return
	_root = (load(MODEL) as PackedScene).instantiate() as Node3D
	add_child(_root)
	var index: Dictionary = _root.get("index")
	GiantLook.build_materials(_root, index, "web")
	var n := OptionWalk.every_option(self, _root, index, false)
	var all := 0
	for c: String in Appearance.ALL_CATEGORIES:
		all += Appearance.option_ids(c).size()
	assert_eq(n, all, "every option of the data (%d)" % n)
	assert_true(n >= 150, "the catalogue's options and the wardrobe's (%d)" % n)


func test_random_greys_of_400_seeds_are_slider_values() -> void:
	CreatorScreenTests.random_greys_are_slider_values(self, 400)
