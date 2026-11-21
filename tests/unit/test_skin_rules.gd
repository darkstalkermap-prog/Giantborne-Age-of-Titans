extends TestSuite
## The skin's code rules (P43; plan M10 §2.7, decisions 5 and 6, §2.13):
##   * nothing under scripts/combat/, scripts/ai/, scripts/world/, scripts/quests/, scripts/core/sim.gd or the
##     player components other than PlayerAppearance names the skeleton, the model, the look, the skinned rig,
##     its modifier, the weapon socket, the animation tree or tip matching (P42 owns the `appearance` word of
##     the same rule: tests/unit/test_appearance_rules.gd);
##   * SkinnedRig, PoseBrainModifier and SecondaryMotion (P50) are write-only: no event, no simulation call, no
##     request, no write to the actor or another actor but the held body's Visual.position (which they put back);
##     P50's words join the rule (SecondaryMotion, the springs, the flinch);
##   * HitFeedback's flinch hands the rig the hit's side and nothing else: it reads the hit, calls the rig's
##     flinch() and writes nothing (plan M11 §2.3);
##   * the skinned layers are off at the start of every test: a test that turns them on
##     (SkinnedRig.enable_for_tests) leaves them to ResetHooks (the two tests below run in this order).

const RULE_DIRS := ["res://scripts/combat/", "res://scripts/ai/", "res://scripts/world/", "res://scripts/quests/"]
const RULE_FILES := ["res://scripts/core/sim.gd"]
const COMPONENTS_DIR := "res://scripts/actors/player/"
const EXEMPT := "player_appearance.gd"
const WORDS := ["Skeleton3D", "get_bone_", "GiantModel", "GiantLook", "SkinnedRig", "PoseBrainModifier", "WeaponSocket",
	"AnimationTree", "TipMatching", "SecondaryMotion", "SpringBone", "flinch",
	"PersonRig", "PersonModel", "PersonLook", "body_spec",   # P60 (plan M11 §2.11: the people)
	"SkinnedQuadrupedRig"]   # P62 (plan M11 §2.11: the skinned horse and its rider)
const SKIN := ["res://scripts/presentation/skinned_rig.gd", "res://scripts/presentation/pose_brain_modifier.gd",
	"res://scripts/presentation/secondary_motion.gd", "res://scripts/presentation/person_rig.gd",
	"res://scripts/presentation/person_model.gd", "res://scripts/presentation/person_look.gd",
	"res://scripts/presentation/skinned_quadruped_rig.gd"]   # P62
const HIT_FEEDBACK := "res://scripts/presentation/hit_feedback.gd"
## What the skin never does (code only, comments and strings left out): the simulation's buses and calls, a
## request to a controller, a write to an actor's state or place.
const FORBIDDEN := {
	"Events\\.": "emits or reads a simulation event",
	"\\bSim\\.": "calls the simulation",
	"\\bWorldState\\b|\\bGameSession\\b|\\bQuests\\b": "touches the world's or the session's state",
	"\\.request\\(": "requests an action",
	"\\bactor\\.(?!get\\(|get_node|global_transform\\b|is_on_floor\\(|get_rig_state\\()[a-z_]+\\s*=(?!=)": "writes the actor",
	"\\bactor\\.set\\(": "writes the actor",
	"velocity|move_and_slide|apply_knockback|set_profile|set_weapon\\(": "moves or changes the actor",
	"\\bcontroller\\.[a-z_]+\\s*=(?!=)|\\bentity\\.[a-z_]+\\s*=(?!=)|\\bcombatant\\b": "writes combat state",
	"global_position\\s*=(?!=)|global_transform\\s*=(?!=)": "places a node in the world",
}


static func gd_files(dir: String, out: PackedStringArray) -> PackedStringArray:
	var d := DirAccess.open(dir)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir + f)
	for sub in d.get_directories():
		gd_files(dir + sub + "/", out)
	return out


func test_a_no_simulation_code_names_the_skin() -> void:
	assert_false(SkinnedRig.layers_enabled(), "the layers are off at the start of a test (headless, ResetHooks)")
	var files := PackedStringArray(RULE_FILES)
	for dir: String in RULE_DIRS:
		gd_files(dir, files)
	for f in gd_files(COMPONENTS_DIR, PackedStringArray()):
		if f.get_file() != EXEMPT:
			files.append(f)
	assert_true(files.size() > 50, "the rule reads the simulation's scripts (%d)" % files.size())
	var re := RegEx.create_from_string("|".join(WORDS))
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		var m := re.search(text)
		if m != null:
			var line := text.substr(0, m.get_start()).count("\n") + 1
			fail("%s:%d names '%s' (plan M10 §2.7: the simulation never reads the skinned body)" % [f, line, m.get_string()])
	checks += 1
	SkinnedRig.enable_for_tests()   # left on: the next test checks ResetHooks turned it off
	assert_true(SkinnedRig.layers_enabled(), "enable_for_tests turns the layers on")


func test_b_the_layers_are_off_again_and_the_skin_writes_nothing_it_does_not_own() -> void:
	assert_false(SkinnedRig.layers_enabled(), "ResetHooks turned the layers off after the previous test")
	for path: String in SKIN:
		var code := _code_only(FileAccess.get_file_as_string(path))
		assert_true(code.length() > 500, "%s is read" % path.get_file())
		for pattern: String in FORBIDDEN:
			var m := RegEx.create_from_string(pattern).search(code)
			assert_true(m == null, "%s %s (%s)" % [path.get_file(), FORBIDDEN[pattern],
				m.get_string() if m != null else ""])
	# the one write into another actor: the held body's Visual.position, put back by _restore_held; the
	# other position write is the rig's own weapon visual, set at its socket (set_weapon_visual)
	var rig := _code_only(FileAccess.get_file_as_string(SKIN[0]))
	var writes := RegEx.create_from_string("(\\w+)\\.position\\s*=(?!=)").search_all(rig)
	var targets := {}
	for m in writes:
		targets[m.get_string(1)] = true
	var keys := targets.keys()
	keys.sort()
	assert_eq(keys, ["_held_visual", "weapon"], "SkinnedRig moves only the held body's visual and its own weapon visual (and its socket's transform)")
	assert_true(rig.contains("func _restore_held") and rig.contains("_held_visual.position = _held_base"),
		"and puts it back")
	assert_true(rig.contains("func _exit_tree") and rig.contains("_restore_held()"), "also when the rig goes")
	# P50: SecondaryMotion writes only its skeleton's bones (set_bone_global_pose) and its own springs
	var sm := _code_only(FileAccess.get_file_as_string(SKIN[2]))
	var sm_writes := RegEx.create_from_string("(\\w+)\\.(set_[a-z_]+)\\(").search_all(sm)
	var sm_targets := {}
	for m in sm_writes:
		sm_targets[m.get_string(1)] = true
	var sm_keys := sm_targets.keys()
	sm_keys.sort()
	assert_eq(sm_keys, ["sk", "springs"], "SecondaryMotion sets only its skeleton's bones and its springs (%s)" % [sm_keys])
	# P50: HitFeedback's flinch: the rig's flinch() with the hit's side, nothing written
	var hf := FileAccess.get_file_as_string(HIT_FEEDBACK)
	var at := hf.find("func _flinch(")
	assert_true(at > 0, "HitFeedback has its flinch hook")
	var raw := hf.substr(at, hf.find("\nfunc ", at + 10) - at)
	var body := _code_only(raw)
	assert_true(raw.contains("call(\"flinch\", local, strength)"), "it calls the rig's flinch with the hit's side")
	for pattern: String in FORBIDDEN:
		var m := RegEx.create_from_string(pattern).search(body)
		assert_true(m == null, "HitFeedback's flinch %s (%s)" % [FORBIDDEN[pattern], m.get_string() if m != null else ""])
	assert_false(RegEx.create_from_string("\\b\\w+\\.\\w+\\s*=(?!=)").search(body) != null, "and assigns nothing")


## The text without comments and string literals' contents (the rules read code only).
static func _code_only(text: String) -> String:
	var out := PackedStringArray()
	for line in text.split("\n"):
		var keep := ""
		var in_str := false
		var quote := ""
		var i := 0
		while i < line.length():
			var ch := line[i]
			if in_str:
				if ch == "\\":
					i += 2
					continue
				if ch == quote:
					in_str = false
					keep += ch
			elif ch == "\"" or ch == "'":
				in_str = true
				quote = ch
				keep += ch
			elif ch == "#":
				break
			else:
				keep += ch
			i += 1
		out.append(keep)
	return "\n".join(out)
