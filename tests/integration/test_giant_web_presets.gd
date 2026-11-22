extends TestSuite
## P45 (plan M10 §3.5 item 6; the owner's answer 1, §0.6): the realistic giant in the Web build. Parses
## only - export_presets.cfg, tools/build_web.sh, web/launcher.html, the web checks' constants and the
## saved model's index; exports nothing and starts no process.
##   * the Web presets ship the giant whole: its 1024 px maps (assets/giant/tex_hi/) stay in the pack
##     from W27 on, and only the pipeline's manifest is left out; the desktop presets leave nothing of
##     the giant out;
##   * the tier's fallback order: "auto" draws the normal and ORM maps from tex_hi/ where the pack has
##     them (the Web as the desktop) and from tex/ where it does not, map by map; the albedo and the
##     masks always come from tex/; --giant-tier= forces a tier;
##   * build_web.sh's milestone budget: 23 MB up to -m9, 26 MB from -m10 on (P49: 32 MB at -m12, 44 MB
##     at -m13, A1b: 46 MB from -m14, plan M11 §2.12; tests/integration/test_build_web_budget.gd), the giant's share the
##     budget less 18.4 MB (tests/slow/test_giant_tooling.gd runs the rule through --version=);
##   * the launcher's open-world start passes --mode=world --creator, GameSession turns those into a
##     creator start for the world, and the Chromium checks expect the same arguments.

const PRESETS := "res://export_presets.cfg"
const BUILD_WEB := "res://tools/build_web.sh"
const LAUNCHER := "res://web/launcher.html"
const MODEL := "res://scenes/player/giant_model.tscn"
const WORLD_START_CHECK := "res://tools/web/world_start_check.mjs"
const CREATOR_CHECK := "res://tools/web/creator_check.mjs"
## What the launcher hands the engine for "Start in the open world" (plan M10 §3.5).
const WORLD_START := ["--", "--mode=world", "--creator"]


## preset name -> {"platform", "exclude": PackedStringArray}.
static func _presets() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(PRESETS) != OK:
		return {}
	var out := {}
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var excl := PackedStringArray()
		for f in str(cfg.get_value(section, "exclude_filter", "")).split(",", false):
			excl.append(f.strip_edges())
		out[str(cfg.get_value(section, "name", ""))] = {"platform": str(cfg.get_value(section, "platform", "")),
			"exclude": excl}
	return out


## A JavaScript array literal of strings as the launcher and the checks write it.
static func _js_array(items: Array) -> String:
	var parts := PackedStringArray()
	for i: Variant in items:
		parts.append("'%s'" % str(i))
	return "[" + ", ".join(parts) + "]"


func test_the_web_presets_ship_the_hi_tier_and_leave_out_only_the_manifest() -> void:
	var presets := _presets()
	assert_true(presets.has("Web") and presets.has("Web (test)") and presets.has("Linux"), "the presets parse")
	for name: String in presets:
		var p: Dictionary = presets[name]
		var excl := p.exclude as PackedStringArray
		var giant := PackedStringArray()
		for f in excl:
			if f.begins_with("assets/giant") or f.begins_with("assets/shaders") or f.begins_with("scenes/player"):
				giant.append(f)
		var want := PackedStringArray(["assets/giant/manifest.json"]) if str(p.platform) == "Web" else PackedStringArray()
		assert_eq(giant, want, "%s leaves out of the giant: %s" % [name, str(want)])
	# The files the tiers name are in the project (so in every pack that does not exclude them).
	for f: String in ["tex/albedo.png", "tex/normal.png", "tex/orm.png", "tex/masks.png", "tex_hi/normal.png",
			"tex_hi/orm.png"]:
		assert_true(FileAccess.file_exists("res://assets/giant/%s.import" % f), "assets/giant/%s is imported" % f)


func test_auto_draws_the_hi_maps_where_the_pack_has_them() -> void:
	var packed := load(MODEL) as PackedScene
	assert_true(packed != null, "scenes/player/giant_model.tscn")
	if packed == null:
		return
	var model := packed.instantiate() as GiantModel
	var index: Dictionary = model.index
	model.free()
	var tiers: Dictionary = index.get("tiers", {})
	assert_eq([str(tiers.get("web", "")), str(tiers.get("hi", ""))], [GiantLook.TEX_WEB, GiantLook.TEX_HI],
		"the index names tex/ and tex_hi/")
	var before := GiantLook.forced_tier
	GiantLook.forced_tier = ""
	var web := GiantLook.TEX_WEB
	var hi := GiantLook.TEX_HI
	# A pack with tex_hi/ (every preset from W27 on) and one without (a Web build of W25 and W26).
	var with_hi := func(_p: String) -> bool: return true
	var without_hi := func(p: String) -> bool: return not p.begins_with(hi)
	var orm_only := func(p: String) -> bool: return p != hi + "normal.png"
	assert_eq(GiantLook.resolve_tier("auto", index, with_hi), "hi", "auto is hi where tex_hi/normal.png is packed")
	assert_eq(GiantLook.resolve_tier("auto", index, without_hi), "web", "and web where it is not")
	assert_eq(GiantLook.resolve_tier("auto", index), "hi", "this project has tex_hi/: auto is hi")
	var maps := GiantLook.map_paths(index, "auto", with_hi)
	assert_eq([str(maps.normal_tex), str(maps.orm_tex)], [hi + "normal.png", hi + "orm.png"],
		"hi: the normal and ORM maps from tex_hi/")
	assert_eq([str(maps.albedo_tex), str(maps.mask_tex)], [web + "albedo.png", web + "masks.png"],
		"the albedo and the masks always from tex/")
	for u: String in maps:
		assert_true(ResourceLoader.exists(str(maps[u])), "%s loads (%s)" % [u, maps[u]])
	maps = GiantLook.map_paths(index, "auto", without_hi)
	for u: String in maps:
		assert_true(str(maps[u]).begins_with(web), "without tex_hi/ every map falls back to tex/ (%s)" % u)
	maps = GiantLook.map_paths(index, "hi", orm_only)
	assert_eq([str(maps.normal_tex), str(maps.orm_tex)], [web + "normal.png", hi + "orm.png"],
		"the fallback is map by map: a missing hi normal map draws tex/'s, the ORM stays hi")
	GiantLook.forced_tier = "web"
	assert_eq(GiantLook.resolve_tier("auto", index, with_hi), "web", "--giant-tier=web forces the 512 px maps")
	GiantLook.forced_tier = before


func test_the_budget_is_26_mb_from_m10_on() -> void:
	var text := FileAccess.get_file_as_string(BUILD_WEB)
	var lines := text.split("\n")
	var rule: Array[String] = []
	for l in lines:
		var s := l.strip_edges()
		if s.contains("BUDGET_MB=") and (s.begins_with("if ") or s.begins_with("elif ") or s.begins_with("else ")):
			rule.append(s)
	# P49 (plan M11 §2.12): the staged budgets - 26 MB at M10 and M11, 32 MB at M12, 44 MB from M13 on. The
	# current milestone's is the last branch (the giant pipeline's estimate reads the last default assigned):
	# M12's since the 0.12.0-m12 release (P58), M13's since the 0.13.0-m13 release (P66), as test_predeclared_m11
	# requires of the version; -m12's branch names its milestone ("-eq 12"), which the giant pipeline reads for its
	# assets' own budget (build_giant.ASSET_MILESTONE). A1b (the expansion's 0.14.0-m14, the owner's raised cap): 46 MB
	# from M14 is the last branch, and -m13's names its milestone ("-eq 13").
	assert_eq(rule, ['if [ "$MILESTONE" -le 6 ]; then BUDGET_MB=7.5', 'elif [ "$MILESTONE" -le 7 ]; then BUDGET_MB=21',
		'elif [ "$MILESTONE" -le 9 ]; then BUDGET_MB=23', 'elif [ "$MILESTONE" -le 11 ]; then BUDGET_MB=26',
		'elif [ "$MILESTONE" -eq 12 ]; then BUDGET_MB=32', 'elif [ "$MILESTONE" -eq 13 ]; then BUDGET_MB=44',
		"else BUDGET_MB=46"] as Array[String],
		"7.5 MB to M6, 21 at M7, 23 at M8 and M9, 26 at M10 and M11, 32 at M12, 44 at M13, 46 from M14 on")
	assert_true(text.contains("OTHER_SHARE_MB=18.4") and text.contains('v = $BUDGET_MB - $OTHER_SHARE_MB - $PEOPLE_OFF;'),
		"the giant's share: the budget less 18.4 MB (7.6 at 26), and from M13 less the people's share")
	assert_true(text.contains("PART_MAX=15000000"), "still in parts of at most 15 MB")
	assert_true(text.contains('--version=*) VERSION="${arg#--version=}" ;;'), "--version= stands for config/version")


func test_the_open_world_start_passes_the_creator() -> void:
	var html := FileAccess.get_file_as_string(LAUNCHER)
	assert_true(html.contains("start(%s);" % _js_array(WORLD_START)), "the launcher: start(%s)" % _js_array(WORLD_START))
	assert_false(html.contains("start(['--', '--mode=world']);"), "and no longer the bare world start")
	# The game's own arguments are what follows "--".
	var user := PackedStringArray()
	for a: String in WORLD_START.slice(1):
		user.append(a)
	user.append("--no-user-settings")
	var o := GameSession.parse_args(user)
	assert_eq([str(o.mode), bool(o.creator), str(o.unknown_mode)], ["world", true, ""], "GameSession reads them")
	var mode_before := GameSession.mode
	var start_before := GameSession.creator_start.duplicate(true)
	var persist_before := GameSession.persist
	var preset_before := Appearance.cli_preset
	GameSession.apply_args(o)
	assert_eq(GameSession.mode, GameSession.Mode.TITLE, "--creator shows the title")
	assert_eq(str(GameSession.creator_start.get("mode", "")), "world", "with a creator start for the world")
	GameSession.creator_start = start_before
	GameSession.mode = mode_before
	GameSession.persist = persist_before
	Appearance.cli_preset = preset_before
	# The Chromium checks expect the same arguments.
	for path: String in [WORLD_START_CHECK, CREATOR_CHECK]:
		var js := FileAccess.get_file_as_string(path)
		assert_true(js.contains("const WORLD_ARGS = %s;" % _js_array(WORLD_START)), "%s expects them" % path.get_file())


## The probe the Chromium checks follow (scripts/debug/ui_probe.gd): made only with --ui-probe, and its
## stall rule (plan M10 §2.12: a first frame within three median frames; under 25 ms never a stall).
func test_the_ui_probe_is_made_only_when_asked_and_judges_stalls() -> void:
	assert_true(UiProbe.from_args(PackedStringArray(["--mode=world", "--creator"])) == null, "no probe without --ui-probe")
	var plain := UiProbe.from_args(PackedStringArray(["--ui-probe", "--ui-probe-bench"]))
	assert_true(plain != null and plain.tour == "" and plain.bench, "--ui-probe: a passive probe; --ui-probe-bench: the skin's bench")
	var toured := UiProbe.from_args(PackedStringArray(["--ui-probe=shrine", "--ui-probe-shots=user://x"]))
	assert_true(toured != null and toured.tour == "shrine" and toured.shots_dir == "user://x" and not toured.bench, "a tour and its shots")
	var unknown := UiProbe.from_args(PackedStringArray(["--ui-probe=moon"]))
	assert_true(unknown != null and unknown.tour == "", "an unknown tour is the passive probe")
	for p: UiProbe in [plain, toured, unknown]:
		p.free()
	assert_eq([UiProbe.median([5.0, 1.0, 3.0]), UiProbe.median([4.0, 1.0, 3.0, 2.0]), UiProbe.median([])], [3.0, 2.5, 0.0], "the median")
	var r := UiProbe.stall_result("creator", [40.0, 130.0, 60.0], [50.0, 40.0, 60.0])
	assert_eq([str(r.mark), float(r.first_ms), float(r.median_ms), float(r.ratio), bool(r.ok)], ["creator", 130.0, 50.0, 2.6, true],
		"the longest of the first frames against the median of the steady ones")
	assert_false(bool(UiProbe.stall_result("level", [151.0], [50.0, 50.0]).ok), "over three median frames is a stall")
	assert_true(UiProbe.stall_ratio_ok(24.0, 2.0) and not UiProbe.stall_ratio_ok(26.0, 2.0), "under 25 ms never, whatever the ratio")
	var js := FileAccess.get_file_as_string(CREATOR_CHECK)
	assert_true(js.contains("export const STALL_RATIO = %d;" % int(UiProbe.STALL_RATIO))
		and js.contains("const STALL_FLOOR_MS = %d;" % int(UiProbe.STALL_FLOOR_MS)), "creator_check.mjs judges by the same rule")


## M10 gate (LD-6): the level tour's "giant alone" reading is the difference of two medians, each of
## DRAW_SAMPLE_FRAMES frames of the paused level, and says when a reading moved while it was sampled. Before,
## it was one live frame with the giant against one live frame four frames later without him, and the scene's
## own count moved by about 4 in between (15 calls for 11 meshes in one run, 5 for 9 in another).
func test_the_level_tours_giant_draw_reading_is_two_medians_of_a_still_scene() -> void:
	var still := UiProbe.giant_draw_result([111, 111, 111, 111, 111], [99, 99, 99, 99, 99], [120000, 120000, 120000, 120000, 120000],
		[99422, 99422, 99422, 99422, 99422], "look", ["Body", "Eyes"], 12)
	assert_eq([int(still.giant_draw_calls), int(still.draw_calls_with), int(still.draw_calls_without), int(still.giant_primitives),
		bool(still.still), int(still.samples), int(still.giant_surfaces)], [12, 111, 99, 20578, true, 5, 12], "a still scene: the giant's own count")
	# one frame of either reading off (a toast's last frame, an actor's LOD step): the median holds, "still" says it moved
	var moved := UiProbe.giant_draw_result([111, 115, 111, 111, 111], [99, 99, 103, 99, 99], [5, 5, 5, 5, 5], [1, 1, 1, 1, 1], "look", [], 12)
	assert_eq([int(moved.giant_draw_calls), bool(moved.still), int(moved.spread_with), int(moved.spread_without)], [12, false, 4, 4],
		"a moving reading is reported as one, and one odd frame does not move the figure")
	assert_true(UiProbe.DRAW_SAMPLE_FRAMES >= 5 and UiProbe.DRAW_SETTLE_FRAMES >= 4, "enough frames to settle and to sample")
	var src := FileAccess.get_file_as_string("res://scripts/debug/ui_probe.gd")
	var tour := src.substr(src.find("func _tour_level()"), 1600)
	assert_true(tour.contains("get_tree().paused = true") and tour.contains("get_tree().paused = bool(_giant_draw.was_paused)"),
		"the tour reads both counts with the tree paused and gives the pause back")

