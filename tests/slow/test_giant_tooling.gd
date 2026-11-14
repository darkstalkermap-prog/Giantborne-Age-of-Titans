extends TestSuite
## P41 (plan M10 §2.12, §1.1, §1.7, §3.1 items 7 and 9): the giant's hooks in the project's tools.
##   * The giant's share of the Web pack. tools/pck_files.py --giant-share counts the giant's files in a
##     pack - everything under assets/giant/ with the imported files its remaps point at, the giant's
##     shaders (assets/shaders/giant_*) and its model scene - and their share of the shipped pack
##     (gzip -9, then base64, as build_web.sh ships it). build_web.sh prints the GIANT_SHARE line after
##     the budget and fails (exit 1) over the share's cap: 4.6 MB at the 23 MB budget, the budget less
##     18.4 MB otherwise (the owner's 26 MB: 7.6 MB), --giant-share-mb=N to override it. Exports
##     nothing: a stand-in pack (Godot's pack format 3) of seeded noise, which gzip cannot shrink,
##     judged with --check-size.
##   * tools/check.sh knows --giant, --giant-full, --require and --strict-times (its help says what
##     each does) and still refuses an unknown option.
## In the slow tier: python3 and six runs of the scripts (about half a second).

const SCRIPT := "res://tools/build_web.sh"
const PCK_FILES := "res://tools/pck_files.py"
const DIR := "user://test_giant_tooling"
const CHECK := "res://tools/check.sh"


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func after_each() -> void:
	DirAccess.remove_absolute(DIR.path_join("index.pck"))
	DirAccess.remove_absolute(DIR)


static func _noise(n: int, seed_value: int) -> PackedByteArray:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var b := PackedByteArray()
	b.resize(n)
	for i in n:
		b[i] = rng.randi() & 0xff
	return b


## Writes a Godot pack (format 3: the header, the files, then the directory) holding `files`
## ({path without "res://": PackedByteArray}) in order.
static func _write_pck(path: String, files: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	for v: int in [0x43504447, 3, 4, 6, 3, 0]:  # "GDPC", format 3, Godot 4.6.3, no flags
		f.store_32(v)
	var base := 6 * 4 + 8 + 8 + 16 * 4
	var data_size := 0
	for k: String in files:
		data_size += (files[k] as PackedByteArray).size()
	f.store_64(base)  # the files' base
	f.store_64(base + data_size)  # the directory's offset
	for _i in 16:
		f.store_32(0)
	for k: String in files:
		f.store_buffer(files[k])
	f.store_32(files.size())
	var offset := 0
	for k: String in files:
		var name := ("res://" + k).to_utf8_buffer()
		name.resize(name.size() + (4 - name.size() % 4) % 4)
		f.store_32(name.size())
		f.store_buffer(name)
		f.store_64(offset)
		f.store_64((files[k] as PackedByteArray).size())
		var md5 := PackedByteArray()
		md5.resize(16)
		f.store_buffer(md5)
		f.store_32(0)
		offset += (files[k] as PackedByteArray).size()
	f.close()


## Runs build_web.sh --check-size on DIR with `args` (stderr into the output): {"code", "out"}.
func _run(args: Array) -> Dictionary:
	var out: Array = []
	var argv := PackedStringArray([ProjectSettings.globalize_path(SCRIPT),
		"--check-size=" + ProjectSettings.globalize_path(DIR)])
	for a: Variant in args:
		argv.append(str(a))
	var code := OS.execute("bash", argv, out, true)
	return {"code": code, "out": "\n".join(out)}


func test_the_giant_share_is_measured_and_capped() -> void:
	for tool: String in ["bash", "gzip", "base64", "awk", "python3"]:
		if not _have(tool):
			print("    test_giant_tooling: skipped - %s is not installed" % tool)
			return
	DirAccess.make_dir_recursive_absolute(DIR)
	# 20 KB of the game's other files and 30 KB of the giant's (with their remaps).
	var giant_targets := {
		".godot/imported/giant.glb-0123.scn": _noise(20000, 3),
		".godot/imported/albedo.png-4567.s3tc.ctex": _noise(6000, 4),
		".godot/exported/1/export-89ab-giant_model.scn": _noise(3600, 6),
	}
	var files := {
		"scenes/enemies/soldier.tscn.remap": "[remap]\n\npath=\"res://.godot/exported/1/export-cdef-soldier.scn\"\n".to_utf8_buffer(),
		".godot/exported/1/export-cdef-soldier.scn": _noise(12000, 1),
		"assets/audio/music/a.ogg.import": "[remap]\npath=\"res://.godot/imported/a.ogg-1.oggvorbisstr\"\n".to_utf8_buffer(),
		".godot/imported/a.ogg-1.oggvorbisstr": _noise(8000, 2),
		"assets/giant/giant.glb.import":
			"[remap]\nimporter=\"scene\"\npath=\"res://.godot/imported/giant.glb-0123.scn\"\n".to_utf8_buffer(),
		"assets/giant/tex/albedo.png.import":
			"[remap]\nimporter=\"texture\"\npath.s3tc=\"res://.godot/imported/albedo.png-4567.s3tc.ctex\"\n".to_utf8_buffer(),
		"assets/shaders/giant_skin.gdshader": _noise(400, 5),
		"scenes/player/giant_model.tscn.remap":
			"[remap]\n\npath=\"res://.godot/exported/1/export-89ab-giant_model.scn\"\n".to_utf8_buffer(),
	}
	files.merge(giant_targets)
	_write_pck(DIR.path_join("index.pck"), files)
	var giant_bytes := 0
	for k: String in files:
		if k.begins_with("assets/giant/") or k.begins_with("assets/shaders/giant_") \
				or k.begins_with("scenes/player/giant_model.") or giant_targets.has(k):
			giant_bytes += (files[k] as PackedByteArray).size()
	# pck_files.py --giant-share: the giant's files and their shipped share
	var out: Array = []
	var code := OS.execute("python3", [ProjectSettings.globalize_path(PCK_FILES), "--giant-share",
		ProjectSettings.globalize_path(DIR.path_join("index.pck")), "--verbose"], out, true)
	var text := "\n".join(out)
	assert_eq(code, 0, "pck_files.py --giant-share runs: %s" % text)
	var m := RegEx.create_from_string(
		"GIANT_SHARE giant_bytes=(\\d+) shipped=(\\d+) shipped_mib=([0-9.]+) files=(\\d+)").search(text)
	assert_true(m != null, "one GIANT_SHARE line: %s" % text)
	if m == null:
		return
	assert_eq(int(m.get_string(1)), giant_bytes, "the giant's files: its remaps and what they point at, shaders, model")
	assert_eq(int(m.get_string(4)), 7, "seven of the eleven packed files")
	var shipped := int(m.get_string(2))
	assert_true(shipped > giant_bytes * 1.3 and shipped < giant_bytes * 1.4,
		"noise ships at about 4/3 of its size (gzip, then base64): %d for %d" % [shipped, giant_bytes])
	assert_true(text.contains("assets/giant/giant.glb.import") and text.contains("giant.glb-0123.scn"),
		"--verbose lists the giant's files")
	assert_false(text.contains("soldier") or text.contains("a.ogg"), "and only the giant's")
	# build_web.sh judges the share after the budget
	var over := _run(["--budget-mb=23", "--giant-share-mb=0.03"])
	assert_eq(int(over.code), 1, "over its share the build fails: %s" % over.out)
	var line_at := str(over.out).find("GIANT_SHARE giant_bytes=%d " % giant_bytes)
	assert_true(line_at >= 0 and str(over.out).contains("cap_mb=0.03"), "after printing the line: %s" % over.out)
	assert_true(str(over.out).find("over its share of 0.03 MB") > line_at, "and then saying why")
	var ok := _run(["--budget-mb=23"])
	assert_eq(int(ok.code), 0, "within the default share it passes: %s" % ok.out)
	assert_true(str(ok.out).contains("cap_mb=4.6"), "the default share at the 23 MB budget is 4.6 MB")
	var bigger := _run(["--budget-mb=26"])
	assert_true(int(bigger.code) == 0 and str(bigger.out).contains("cap_mb=7.6"),
		"and grows with the budget (the owner's 26 MB: 7.6 MB): %s" % bigger.out)
	var bad := _run(["--giant-share-mb=lots"])
	assert_eq(int(bad.code), 2, "a share that is not a number is a usage error")
	# a file that is no Godot pack is not measured (and does not fail the build)
	var f := FileAccess.open(DIR.path_join("index.pck"), FileAccess.WRITE)
	f.store_buffer(_noise(4000, 9))
	f.close()
	var noise := _run(["--budget-mb=23"])
	assert_eq(int(noise.code), 0, "a stand-in that is no pack passes")
	assert_true(str(noise.out).contains("GIANT_SHARE: not measured"), "with a note: %s" % noise.out)


func test_check_sh_knows_the_giant_options() -> void:
	if not _have("bash"):
		print("    test_giant_tooling: skipped - bash is not installed")
		return
	var text := FileAccess.get_file_as_string(CHECK)
	for opt: String in ["--giant", "--giant-full", "--require", "--strict-times"]:
		assert_true(text.contains("\t\t%s) " % opt), "check.sh parses %s" % opt)
	var out: Array = []
	var code := OS.execute("bash", [ProjectSettings.globalize_path(CHECK), "--help"], out, true)
	var help := "\n".join(out)
	assert_eq(code, 0, "check.sh --help")
	for opt: String in ["--giant ", "--giant-full ", "--require ", "--strict-times "]:
		assert_true(help.contains("#   %s" % opt), "the help explains %s" % opt.strip_edges())
	assert_true(help.strip_edges().ends_with("last run are kept in .userdata/check/."), "the whole header and no more")
	out.clear()
	code = OS.execute("bash", ["-n", ProjectSettings.globalize_path(CHECK)], out, true)
	assert_eq(code, 0, "check.sh parses (bash -n): %s" % "\n".join(out))
	out.clear()
	code = OS.execute("bash", [ProjectSettings.globalize_path(CHECK), "--giant-fulll"], out, true)
	assert_eq(code, 2, "an unknown option is a usage error, before anything runs")
	# --giant after --giant-full keeps the full regeneration
	assert_true(text.contains('--giant) [ "$GIANT" = "full" ] || GIANT=1 ;;'), "--giant never downgrades --giant-full")
	# --require turns every skip note into a failure
	assert_true(text.contains('if [ "$REQUIRE" = "1" ]; then\n\t\tfail "a required check was skipped (--require)'),
		"a skipped check fails under --require")
	assert_true(text.contains('grep -E "skipped - " "$LOGS/tests.log"'), "and so does a suite's skip note")
