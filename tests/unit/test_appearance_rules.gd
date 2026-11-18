extends TestSuite
## The look's code rules (P42; plan M10 §2.7, decisions 5 and 14): the look never touches the simulation.
##   * Nothing under scripts/combat/, scripts/ai/, scripts/world/, scripts/quests/, scripts/core/sim.gd or the
##     player components other than PlayerAppearance names `appearance` (P42's rule of §2.7; P43 owns the
##     skeleton and skin words of the same rule).
##   * The look's own code (Appearance, PlayerAppearance, GiantLook, TipMatching) never draws a random number
##     from the simulation (Sim.rng, a Sim stream) or the global generator: Randomize takes the creator's own
##     generator.
##   * PlayerAppearance has no simulation hook: no edge, no pre-action, no movement, no action callbacks.

const RULE_DIRS := ["res://scripts/combat/", "res://scripts/ai/", "res://scripts/world/", "res://scripts/quests/"]
const RULE_FILES := ["res://scripts/core/sim.gd"]
const COMPONENTS_DIR := "res://scripts/actors/player/"
const OWN := "player_appearance.gd"
const LOOK_CODE := ["res://scripts/progression/appearance.gd", "res://scripts/actors/player/player_appearance.gd",
	"res://scripts/presentation/giant_look.gd", "res://scripts/presentation/tip_matching.gd"]
const SIM_HOOKS := ["handle_edge", "edge_priority", "pre_actions", "post_movement", "on_action_started",
	"on_action_ended", "interact_candidate", "on_profile_changed", "on_weapon_changed"]


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


func test_no_simulation_code_names_appearance() -> void:
	var files := PackedStringArray(RULE_FILES)
	for dir: String in RULE_DIRS:
		gd_files(dir, files)
	for f in gd_files(COMPONENTS_DIR, PackedStringArray()):
		if f.get_file() != OWN:
			files.append(f)
	assert_true(files.size() > 50, "the rule reads the simulation's scripts (%d)" % files.size())
	var re := RegEx.create_from_string("(?i)appearance")
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		var m := re.search(text)
		if m != null:
			var line := text.substr(0, m.get_start()).count("\n") + 1
			fail("%s:%d names 'appearance' (plan M10 §2.7: the simulation never reads the look)" % [f, line])
	checks += 1


func test_the_look_draws_no_random_number_from_the_simulation() -> void:
	var sim := RegEx.create_from_string("Sim\\.(rng|stream|_streams)|\\bseed_stream\\b")
	var global := RegEx.create_from_string("(?<![\\w.])(randf|randi|randi_range|randf_range|randfn|randomize)\\(")
	for f: String in LOOK_CODE:
		var code := _code_only(FileAccess.get_file_as_string(f))
		assert_true(code.length() > 0, "%s is read" % f)
		assert_true(sim.search(code) == null, "%s never draws from Sim's generators" % f.get_file())
		assert_true(global.search(code) == null, "%s never draws from the global generator" % f.get_file())
	var pa := _code_only(FileAccess.get_file_as_string(LOOK_CODE[1]))
	var sim_uses := RegEx.create_from_string("Sim\\.(\\w+)").search_all(pa)
	for m in sim_uses:
		assert_eq(m.get_string(1), "tick", "PlayerAppearance reads only Sim.tick (the event's tick)")


func test_player_appearance_has_no_simulation_hook() -> void:
	var own: Dictionary = {}
	for m: Dictionary in (load(LOOK_CODE[1]) as GDScript).get_script_method_list():
		own[str(m.name)] = true
	var text := _code_only(FileAccess.get_file_as_string(LOOK_CODE[1]))
	for hook: String in SIM_HOOKS:
		assert_false(text.contains("func %s(" % hook), "PlayerAppearance does not override %s" % hook)
	assert_true(own.has("apply_state") and own.has("capture_state"), "it moves the saved key")


## The text without comments (a `#` that starts a comment, outside strings) and without string literals'
## contents, so the rules read code only.
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
