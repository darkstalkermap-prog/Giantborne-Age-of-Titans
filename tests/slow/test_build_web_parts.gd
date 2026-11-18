extends TestSuite
## P49 (plan M11 §2.12, §3.2 item 2: "the report of parts for three and four; a four-part pack judged"):
## tools/build_web.sh --check-size on packs made here, nothing exported.
##   * a small stand-in (seeded noise): the PCK_PARTS line for one part and for --parts=3 and --parts=4;
##     the report's order - PCK_SIZE, PCK_PARTS, the budget, GIANT_SHARE, PEOPLE_SHARE; a people's cap
##     only from -m13 or when asked for; the usage errors;
##   * a pack at the last budget: 34.4 MB of noise ships as 45.9 MB - over three parts of 15,000,000
##     bytes, so it is judged in four, within 44 MB at -m13, over the budget at -m12 and at -m11;
##   * a real Godot pack written here (PCKPacker) with files under assets/people/, assets/creatures/,
##     scenes/people/ and the people's shaders: the PEOPLE_SHARE line counts exactly those, the giant's
##     line the giant's, and the build fails over a people's cap after printing the line.

const SCRIPT := "res://tools/build_web.sh"
const DIR := "user://test_build_web_parts"
const SMALL_BYTES := 300000
## 34.4 MB of noise: gzip cannot shrink it, base64 makes it 45.9 MB - between three parts' 45,000,000
## bytes and the 44 MiB budget's 46,137,344.
const BIG_BYTES := 34400000


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func _tools() -> bool:
	for tool: String in ["bash", "gzip", "awk", "python3", "head"]:
		if not _have(tool):
			print("    test_build_web_parts: skipped - %s is not installed" % tool)
			return false
	return true


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


func after_each() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		for f in d.get_files():
			d.remove(f)
	DirAccess.remove_absolute(DIR)


func _noise(bytes: int) -> void:
	# The system's noise: as incompressible as seeded noise and written in a fraction of the time.
	var out: Array = []
	var path := ProjectSettings.globalize_path(DIR.path_join("index.pck"))
	assert_eq(OS.execute("sh", ["-c", "head -c %d /dev/urandom > '%s'" % [bytes, path]], out, true), 0, "the stand-in pack is written")


func _run(args: Array) -> Dictionary:
	var out: Array = []
	var argv := PackedStringArray([ProjectSettings.globalize_path(SCRIPT), "--check-size=" + ProjectSettings.globalize_path(DIR)])
	for a: Variant in args:
		argv.append(str(a))
	var code := OS.execute("bash", argv, out, true)
	var text := "\n".join(out)
	return {"code": code, "out": text, "lines": text.split("\n", false)}


static func _line_of(lines: PackedStringArray, needle: String) -> int:
	for i in lines.size():
		if lines[i].contains(needle):
			return i
	return -1


static func _field(text: String, key: String) -> int:
	return int(text.get_slice(key + "=", 1).get_slice(" ", 0).get_slice("\n", 0))


func test_the_parts_report_and_the_order_of_the_lines() -> void:
	if not _tools():
		return
	_noise(SMALL_BYTES)
	var one := _run(["--version=0.13.0-m13"])
	assert_eq(int(one.code), 0, "the stand-in fits (%s)" % one.out)
	var shipped := _field(one.out, "shipped")
	assert_true(shipped > SMALL_BYTES and shipped % 4 == 0, "the shipped size is base64's (%d)" % shipped)
	assert_true(str(one.out).contains("PCK_PARTS parts=1 part_bytes=%d last_part_bytes=%d part_max=15000000" % [shipped, shipped]),
		"one part: %s" % one.out)
	var order: Array = []
	for needle: String in ["PCK_SIZE ", "PCK_PARTS ", "within the milestone's budget of 44 MB", "GIANT_SHARE", "PEOPLE_SHARE"]:
		order.append(_line_of(one.lines, needle))
	var sorted := order.duplicate()
	sorted.sort()
	assert_true(order == sorted and int(order[0]) >= 0, "PCK_SIZE, PCK_PARTS, the budget, the giant's share, the people's: %s" % one.out)
	for n: int in [3, 4]:
		var r := _run(["--parts=%d" % n])
		var per := int(ceil(shipped / float(n)))
		var last := shipped - per * (n - 1)
		assert_eq(int(r.code), 0, "--parts=%d is judged (%s)" % [n, r.out])
		assert_eq(_field(str(r.lines[_line_of(r.lines, "PCK_SIZE ")]), "parts"), n, "PCK_SIZE names %d parts" % n)
		assert_true(str(r.out).contains("PCK_PARTS parts=%d part_bytes=%d last_part_bytes=%d part_max=15000000" % [n, per, last]),
			"%d parts of %d bytes, the last %d: %s" % [n, per, last, r.out])
		assert_true(last > 0 and last <= per, "the last part is the remainder")
	# --budget-mb keeps the rule "the giant's cap is the budget less 18.4" (and from -m13 less the people's).
	var forced := _run(["--version=0.13.0-m13", "--budget-mb=40", "--people-share-mb=10", "--print-caps"])
	assert_eq(str(forced.out).strip_edges(), "CAPS budget_mb=40 giant_share_mb=11.6 people_share_mb=10", "a forced budget and people's share")
	forced = _run(["--version=0.11.0-m11", "--budget-mb=30", "--print-caps"])
	assert_eq(str(forced.out).strip_edges(), "CAPS budget_mb=30 giant_share_mb=11.6 people_share_mb=none", "a forced budget before -m13")
	assert_eq(int(_run(["--people-share-mb=many"]).code), 2, "a people's share that is not a number is a usage error")
	assert_eq(int(_run(["--parts=0"]).code), 2, "no parts is a usage error")


func test_a_pack_at_the_last_budget_is_judged_in_four_parts() -> void:
	if not _tools():
		return
	_noise(BIG_BYTES)
	var r := _run(["--version=0.13.0-m13"])
	assert_eq(int(r.code), 0, "45.9 MB shipped is within 44 MiB at -m13 (%s)" % r.out)
	var shipped := _field(r.out, "shipped")
	assert_true(shipped > 3 * 15000000 and shipped <= 44 * 1048576, "over three parts, within the budget (%d)" % shipped)
	var per := int(ceil(shipped / 4.0))
	assert_true(str(r.out).contains("budget_mb=44 parts=4"), "four parts by itself: %s" % r.out)
	assert_true(str(r.out).contains("PCK_PARTS parts=4 part_bytes=%d last_part_bytes=%d part_max=15000000" % [per, shipped - 3 * per]),
		"four parts of %d bytes: %s" % [per, r.out])
	assert_true(per <= 15000000 and per > 11000000, "each under the host's cap")
	assert_true(str(r.out).contains("PEOPLE_SHARE: not measured") and str(r.out).contains("GIANT_SHARE: not measured"),
		"noise is not a Godot pack: the shares say so and do not fail")
	# The same pack is over the budget one milestone earlier (the rule alone: no second gzip of 34 MB).
	var caps: Array = []
	OS.execute("bash", PackedStringArray([ProjectSettings.globalize_path(SCRIPT), "--version=0.12.0-m12", "--print-caps"]), caps, true)
	assert_true("\n".join(caps).contains("CAPS budget_mb=32 "), "-m12 judges by 32 MB")
	assert_true(shipped > 32 * 1048576, "which this pack is over")
	# In three parts each would hold more than the cap (the script's own rule for that is a failure:
	# test_build_web_budget, "a part over 15 MB stays a failure"; a second gzip of 34 MB is not spent on it).
	assert_true(int(ceil(shipped / 3.0)) > 15000000, "three parts of it would each be over 15,000,000 bytes")


func test_the_peoples_share_counts_their_files_in_a_real_pack() -> void:
	if not _tools():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 49
	var src := DIR.path_join("src.bin")
	var files := {
		"res://assets/people/soldier.glb": 60000, "res://assets/creatures/wolf.glb": 40000,
		"res://scenes/people/soldier_model.tscn": 3000, "res://scenes/creatures/wolf_model.tscn": 3000,
		"res://assets/shaders/person.gdshader": 2000, "res://assets/shaders/person_crowd.gdshader": 2000,
		"res://assets/shaders/fur_shell.gdshader": 2000,
		"res://assets/giant/giant.glb": 50000, "res://assets/shaders/giant_skin.gdshader": 2000,
		"res://scripts/core/sim.gd": 30000, "res://assets/world/terrain.bin": 80000,
	}
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(DIR.path_join("index.pck")), OK, "the pack is started")
	var n := 0
	for path: String in files:
		var bytes := PackedByteArray()
		bytes.resize(int(files[path]))
		for i in bytes.size():
			bytes[i] = rng.randi() & 0xff
		var one := "%s.%d" % [src, n]
		n += 1
		var f := FileAccess.open(one, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		assert_eq(packer.add_file(path, one), OK, "%s added" % path)
	assert_eq(packer.flush(), OK, "the pack is written")
	var r := _run(["--version=0.13.0-m13"])
	assert_eq(int(r.code), 0, "the small pack passes at -m13 (%s)" % r.out)
	var people_line := str(r.lines[maxi(0, _line_of(r.lines, "PEOPLE_SHARE "))])
	assert_eq(_field(people_line, "files"), 7, "seven people's and creatures' files: %s" % people_line)
	assert_eq(_field(people_line, "people_bytes"), 112000, "their bytes")
	assert_true(people_line.ends_with("cap_mb=12.0"), "judged by 12.0 MB at -m13")
	var people_shipped := _field(people_line, "shipped")
	assert_true(people_shipped > 140000 and people_shipped < 160000, "noise ships as four thirds of itself (%d)" % people_shipped)
	var giant_line := str(r.lines[maxi(0, _line_of(r.lines, "GIANT_SHARE "))])
	assert_eq(_field(giant_line, "files"), 2, "the giant's two files are the giant's: %s" % giant_line)
	assert_true(giant_line.ends_with("cap_mb=13.6"), "the giant's cap at -m13 is 44 - 18.4 - 12.0")
	# Before -m13 the line is printed without a cap; a cap given by hand is enforced, after the line.
	var m11 := _run(["--version=0.11.0-m11"])
	assert_true(int(m11.code) == 0 and str(m11.out).contains("files=7 cap_mb=none"), "-m11: printed, not capped (%s)" % m11.out)
	var over := _run(["--version=0.11.0-m11", "--people-share-mb=0.1"])
	assert_eq(int(over.code), 1, "over a people's cap the build fails (%s)" % over.out)
	assert_true(_line_of(over.lines, "over their share of 0.1 MB") > _line_of(over.lines, "PEOPLE_SHARE "), "after printing the line")
	var over_giant := _run(["--version=0.13.0-m13", "--giant-share-mb=0.01"])
	assert_eq(int(over_giant.code), 1, "the giant's share still fails first")
	assert_false(str(over_giant.out).contains("PEOPLE_SHARE"), "before the people's line")
