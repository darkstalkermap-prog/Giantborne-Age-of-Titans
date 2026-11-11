extends TestSuite
## M7 polish (the M7 gate review; plan M6-M9 §6.6: tools/build_web.sh "fails over the milestone's
## budget and if any part exceeds 15 MB"): the script judged the shipped index.pck against the
## milestone's budget but only printed a WARNING and exited 0. It now fails (exit 1) after the
## PCK_SIZE line and the reason, before web/launcher.html is touched; --budget-mb=N still overrides
## the budget and a part over 15 MB still fails. Exports nothing: --check-size=DIR packs a small
## stand-in index.pck in memory and judges it as a build would (a fraction of a second).

const SCRIPT := "res://tools/build_web.sh"
const DIR := "user://test_build_web_budget"
## The stand-in pck: seeded noise gzip cannot shrink, about 0.38 MB as shipped (gzip + base64).
const PCK_BYTES := 300000


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var bytes := PackedByteArray()
	bytes.resize(PCK_BYTES)
	for i in PCK_BYTES:
		bytes[i] = rng.randi() & 0xff
	var f := FileAccess.open(DIR.path_join("index.pck"), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func after_each() -> void:
	DirAccess.remove_absolute(DIR.path_join("index.pck"))
	DirAccess.remove_absolute(DIR)


## Runs build_web.sh with `args` (stderr into the output): {"code", "out", "lines"}.
func _run(args: Array) -> Dictionary:
	var out: Array = []
	var argv := PackedStringArray([ProjectSettings.globalize_path(SCRIPT)])
	for a: Variant in args:
		argv.append(str(a))
	var code := OS.execute("bash", argv, out, true)
	var text := "\n".join(out)
	return {"code": code, "out": text, "lines": text.split("\n", false)}


func _check(budget := "") -> Array:
	var args: Array = ["--check-size=" + ProjectSettings.globalize_path(DIR)]
	if budget != "":
		args.append("--budget-mb=" + budget)
	return [_run(args), args]


## The index of the first line holding `needle` (-1 when none).
static func _line_of(lines: PackedStringArray, needle: String) -> int:
	for i in lines.size():
		if lines[i].contains(needle):
			return i
	return -1


func test_the_build_fails_over_the_budget_after_saying_why() -> void:
	for tool: String in ["bash", "gzip", "base64", "awk"]:
		if not _have(tool):
			print("    test_build_web_budget: skipped - %s is not installed" % tool)
			return
	var over: Dictionary = _check("0.1")[0]
	assert_eq(int(over.code), 1, "over the budget the script fails (exit 1): %s" % over.out)
	var size_at := _line_of(over.lines, "PCK_SIZE ")
	var why_at := _line_of(over.lines, "over the milestone's budget of 0.1 MB")
	assert_true(size_at >= 0 and over.out.contains("budget_mb=0.1"), "it prints the PCK_SIZE line: %s" % over.out)
	assert_true(why_at > size_at, "then the reason: %s" % over.out)
	assert_false(over.out.contains("WARNING"), "a failure, not a warning")
	var within: Dictionary = _check("1")[0]
	assert_eq(int(within.code), 0, "--budget-mb=1 overrides the budget: it passes (%s)" % within.out)
	assert_true(within.out.contains("within the milestone's budget of 1 MB"), "and says so")
	# Without --budget-mb the milestone's budget comes from config/version (decision 8).
	var version := str(ProjectSettings.get_setting("application/config/version", ""))
	var milestone := int(version.get_slice("-m", 1)) if version.contains("-m") else 6
	var expected := "7.5" if milestone <= 6 else ("21" if milestone <= 7 else "23")
	var default_run: Dictionary = _check()[0]
	assert_true(default_run.out.contains("budget_mb=%s " % expected), "%s: the budget is %s MB (%s)" % [version, expected,
		default_run.out])
	assert_eq(int(default_run.code), 0, "and the stand-in fits it")
	var bad: Dictionary = _check("lots")[0]
	assert_eq(int(bad.code), 2, "a budget that is not a number is a usage error")


func test_a_part_over_15_mb_stays_a_failure() -> void:
	# The part cap needs a 15 MB part to trip; the script's own lines keep it a failure (exit 1).
	var text := FileAccess.get_file_as_string(SCRIPT)
	assert_true(text.contains("PART_MAX=15000000"), "parts of at most 15 MB")
	var lines := text.split("\n")
	for needle: String in ["holds $part bytes (1 to $PART_MAX wanted)", "would hold $per bytes (at most $PART_MAX)"]:
		var at := _line_of(lines, needle)
		assert_true(at >= 0 and at + 1 < lines.size() and lines[at + 1].strip_edges() == "exit 1",
			"'%s' is followed by exit 1" % needle)
	# And the budget's failure comes before the release touches web/launcher.html.
	var budget_at := _line_of(lines, "check_budget \"$pck_packed\"")
	var launcher_at := _line_of(lines, "cp \"$OUT/launcher.tmp\" web/launcher.html")
	assert_true(budget_at >= 0 and launcher_at > budget_at, "the budget is judged before the launcher is rewritten")
