extends TestSuite
## P22 (plan M6-M9 §3.4 design 7, decision 8): the web release without test content. Builds
## nothing: it reads export_presets.cfg and the launcher.
##   * the Web preset (the release) excludes scenes/test/, assets/test_world/ and data/test/;
##   * a "Web (test)" preset keeps them (the streaming checks), with the release's options, into
##     builds/web_test/; the desktop presets keep them (the stress route's owner commands);
##   * today's test-only records live in data/test/ (and nowhere else);
##   * the launcher passes ?args=a,b,c to the engine;
##   * (P23) the launcher joins a multi-part pck and resumes a suspended AudioContext on a press;
##   * (M7 release) the launcher offers an open-world start (--mode=world) that asks twice.

const PRESETS := "res://export_presets.cfg"
const LAUNCHER := "res://web/launcher.html"
const TEST_DIRS := ["scenes/test/*", "assets/test_world/*", "data/test/*"]
const MOVED := ["level_director_test", "level_stress_arena", "encounter_director_test_budget",
	"encounter_director_test_soldiers", "encounter_director_test_wolves"]


## {preset name: {"section": "preset.N", "platform", "exclude": PackedStringArray, ...}}.
static func _presets(cfg: ConfigFile) -> Dictionary:
	var out := {}
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var excl := PackedStringArray()
		for f in str(cfg.get_value(section, "exclude_filter", "")).split(",", false):
			excl.append(f.strip_edges())
		out[str(cfg.get_value(section, "name", ""))] = {"section": section,
			"platform": str(cfg.get_value(section, "platform", "")), "exclude": excl,
			"include": str(cfg.get_value(section, "include_filter", "")),
			"export_path": str(cfg.get_value(section, "export_path", "")),
			"runnable": bool(cfg.get_value(section, "runnable", false))}
	return out


static func _options(cfg: ConfigFile, section: String) -> Dictionary:
	var out := {}
	var opt := section + ".options"
	if cfg.has_section(opt):
		for key in cfg.get_section_keys(opt):
			out[key] = cfg.get_value(opt, key)
	return out


func test_the_web_release_excludes_test_content_and_web_test_keeps_it() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK, "export_presets.cfg parses")
	var presets := _presets(cfg)
	assert_true(presets.has("Web") and presets.has("Web (test)"), "Web and Web (test) presets")
	if not (presets.has("Web") and presets.has("Web (test)")):
		return
	var web: Dictionary = presets["Web"]
	var web_test: Dictionary = presets["Web (test)"]
	for d: String in TEST_DIRS:
		assert_true((web.exclude as PackedStringArray).has(d), "the Web release excludes %s" % d)
		assert_false((web_test.exclude as PackedStringArray).has(d), "Web (test) keeps %s" % d)
	assert_eq(web.export_path, "builds/web/index.html", "the release goes to builds/web")
	assert_true(web.runnable, "the release is the runnable web preset")
	assert_eq([web_test.platform, web_test.export_path, web_test.runnable], ["Web", "builds/web_test/index.html", false],
		"Web (test): a web export into builds/web_test, never the one-click run")
	assert_eq(web_test.include, web.include, "the same data include filter")
	assert_eq(_options(cfg, str(web_test.section)), _options(cfg, str(web.section)), "and the release's options")
	for name: String in presets:
		var p: Dictionary = presets[name]
		if str(p.platform) == "Web":
			continue
		for d: String in TEST_DIRS:
			assert_false((p.exclude as PackedStringArray).has(d), "%s keeps %s (desktop)" % [name, d])


func test_test_only_records_live_in_data_test() -> void:
	for f: String in MOVED:
		assert_true(FileAccess.file_exists("res://data/test/%s.json" % f), "data/test/%s.json" % f)
		assert_false(FileAccess.file_exists("res://data/world/%s.json" % f), "no longer in data/world")
	for id: String in ["level.director_test", "level.stress_arena", "encounter.director_test_wolves"]:
		assert_false(GameData.get_record(id).is_empty(), "%s still loads (tests and desktop)" % id)
	# No shipped record (outside data/test) points at a test scene or the test world.
	var offenders := PackedStringArray()
	for path in JsonIO.list_json_files("res://data"):
		if path.begins_with("res://data/test/"):
			continue
		var text := FileAccess.get_file_as_string(path)
		if text.contains("res://scenes/test/") or text.contains("res://assets/test_world/"):
			offenders.append(path)
	assert_eq(offenders, PackedStringArray(), "shipped records never name test content")


func test_the_launcher_passes_args_to_the_engine() -> void:
	var f := FileAccess.open(LAUNCHER, FileAccess.READ)
	assert_true(f != null, "web/launcher.html")
	if f == null:
		return
	var html := f.get_as_text()
	assert_true(html.contains("function launchArgs()"), "a launchArgs() helper")
	assert_true(html.contains("new URLSearchParams(window.location.search).get('args')"), "reading ?args=")
	assert_true(html.contains("raw.split(',')"), "comma-separated")
	assert_true(html.contains("args: launchArgs()"), "handed to the Engine's args")
	assert_true(html.contains("['--'].concat(list)"), "the game's own arguments by default (after --)")
	# P23: the BUILD line also carries the packed pck's part count (the multi-part pck).
	var re := RegEx.create_from_string("const BUILD = \\{ wasm: \\d+, pck: \\d+, wasmPacked: \\d+, pckPacked: \\d+, pckParts: \\d+ \\}; // set by tools/build_web.sh")
	assert_true(re.search(html) != null, "the BUILD line build_web.sh keeps in step")


## P23 (plan M6-M9 §3.5): the launcher downloads a multi-part pck in order under one meter, resumes a
## suspended AudioContext on the first press, and says "Sound on". P49 (plan M11 §3.2 item 3): the
## parts' text is no longer joined - each piece is decoded and inflated as it arrives, through one
## stream (tools/web/test_launcher_parts.mjs runs the launcher's own lines on packs of 1-4 parts).
func test_the_launcher_joins_pck_parts_and_resumes_the_sound() -> void:
	var html := FileAccess.get_file_as_string(LAUNCHER)
	assert_true(html.contains("'index.pck': { urls: pckUrls(BUILD.pckParts)"), "the pck's parts from the BUILD line")
	assert_true(html.contains("urls.push('index.pck.gz.b64.' + i + '.txt')"), "named index.pck.gz.b64.<n>.txt")
	assert_true(html.contains("if (n === 1) return ['index.pck.gz.b64.txt'];"), "one part keeps its plain name")
	assert_true(html.contains("reader = await open(urls[part]);") and html.contains("let reader = await open(urls[0]);"),
		"downloaded in order, one part after the other")
	assert_false(html.contains("new Blob(chunks).text()"), "the parts' text is not joined (P49)")
	assert_true(html.contains("const bytes = pieces.push(step.value);") and html.contains("await writer.write(bytes);")
		and html.contains("new DecompressionStream('gzip')"), "each piece is decoded and inflated as it arrives")
	assert_true(html.contains("// <parts>") and html.contains("// </parts>"), "the block the launcher's own test runs")
	# P52: the page's own text is the note the script writes from the BUILD line (the engine and the pck as
	# shipped, in millions of bytes), so a reader without script reads the same figure (36 MB at 0.10.0-m10).
	var counts := RegEx.create_from_string("wasmPacked: (\\d+), pckPacked: (\\d+)").search(html)
	var note := "About %d MB to download." % roundi((int(counts.get_string(1)) + int(counts.get_string(2))) / 1e6) \
		if counts != null else "(no BUILD line)"
	assert_true(html.contains(note) and html.contains("Math.round(packedTotal / 1e6)"),
		"the download note is written from the build's byte counts (%s)" % note)
	assert_true(html.contains("for (const type of ['pointerdown', 'pointerup', 'mousedown', 'touchend', 'click', 'keydown']) {")
		and html.contains("window.addEventListener(type, resumeAudio, true);"), "the first press (its start or its end) resumes the sound")
	assert_true(html.contains("navigator.audioSession.type = 'playback'"), "a phone's silent switch does not mute the page")
	assert_true(html.contains("id=\"sound-test\"") and html.contains("id=\"sound-test-gate\""), "a test tone before and during the game")
	assert_true(html.contains("if (ctx.state === 'suspended') ctx.resume()"), "only suspended contexts")
	assert_true(html.contains("<b>Sound on.</b>"), "the page's notes say Sound on")
	assert_false(html.contains("there is no sound"), "and no longer that there is none")


## The M7 release (plan M6-M9 §6.6: "the world opens after the Valley"): beside Play, the launcher
## starts a new game in the open world (--mode=world, GameSession's world start) on a second press,
## since it replaces the saved game; Play and the page's ?args= are unchanged. P45 (plan M10 §3.5): the
## start passes --creator, so the world start too begins in the character creator.
func test_the_launcher_offers_the_open_world_start() -> void:
	var html := FileAccess.get_file_as_string(LAUNCHER)
	assert_true(html.contains("id=\"play-world\""), "a second start button")
	assert_true(html.contains("start(['--', '--mode=world', '--creator']);"),
		"it starts the engine with --mode=world --creator")
	assert_true(html.contains("if (startArgs) return startArgs;"), "through launchArgs(), which keeps ?args= otherwise")
	assert_true(html.contains("worldTimer = setTimeout(disarmWorld, 6000);"), "the first press only arms it")
	assert_true(html.contains("It replaces a game saved in this browser."), "the note says it replaces the saved game")
	assert_true(html.contains("play.addEventListener('click', function () { start(); });"), "Play keeps the page's arguments")
	assert_true(GameSession.CLI_MODES.has("world"), "GameSession knows --mode=world")


## P41 (plan M10 §1.6, §2.5), changed by P45 (the owner's answer 1, plan M10 §0.6): the Web presets leave
## out the giant's manifest (as the audio's) and, from W27 on, keep the 1024 px texture tier
## (assets/giant/tex_hi/: the Web draws it as the desktop does, inside the 26 MB budget); the desktop
## presets keep both. tests/integration/test_giant_web_presets.gd has the rest.
func test_the_web_presets_leave_out_the_giant_manifest_and_keep_the_hi_tier() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(PRESETS), OK, "export_presets.cfg parses")
	var presets := _presets(cfg)
	for name: String in presets:
		var p: Dictionary = presets[name]
		var web := str(p.platform) == "Web"
		assert_eq((p.exclude as PackedStringArray).has("assets/giant/manifest.json"), web,
			"%s %s the giant's manifest" % [name, "excludes" if web else "keeps"])
		assert_false((p.exclude as PackedStringArray).has("assets/giant/tex_hi/*"), "%s ships the 1024 px maps" % name)
		assert_false((p.exclude as PackedStringArray).has("assets/giant/*"), "%s ships the giant" % name)
