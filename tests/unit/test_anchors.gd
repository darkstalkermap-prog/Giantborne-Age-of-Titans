extends TestSuite
## Package anchors (plan §1.5): every "## @anchor <package>" line listed in
## tests/support/anchors_expected.gd exists in its file, so a later package never has to invent
## one. Rows of a creator package that has not landed on this branch yet are skipped.


func _read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	return f.get_as_text()


func test_every_expected_anchor_exists() -> void:
	var checked := 0
	for row: Array in AnchorsExpected.TABLE:
		var path: String = row[0]
		var creator: String = row[1]
		if not AnchorsExpected.creator_landed(creator):
			continue
		assert_true(FileAccess.file_exists(path), "%s exists (created by %s)" % [path, creator])
		var found := AnchorsExpected.anchors_in(_read(path))
		for id: String in row[2]:
			assert_true(found.has(id), "%s has the line '## @anchor %s'" % [path.get_file(), id])
			checked += 1
	assert_true(checked >= 22, "at least this package's own 22 anchors were checked (%d)" % checked)


func test_own_rows_are_always_checked() -> void:
	assert_true(AnchorsExpected.creator_landed("P02"), "P02 rows need no sentinel")
	assert_false(AnchorsExpected.creator_landed("P99"), "an unknown creator is never assumed landed")
	var own := 0
	for row: Array in AnchorsExpected.TABLE:
		if row[1] == "P02":
			own += 1
	assert_eq(own, 6, "six files carry P02's anchors")


func test_anchor_parsing() -> void:
	var text := "\n".join(PackedStringArray([
		"## @anchor P04", "	## @anchor P10a", "# @anchor P11b: guards", "## @anchor P07, grab",
		"var x := 1  ## @anchor P99 (not a comment line)", "## anchor P05", "##@anchor P12"]))
	var found := AnchorsExpected.anchors_in(text)
	assert_eq(found, PackedStringArray(["P04", "P10a", "P11b", "P07", "P12"]),
		"comment lines only; the id is the first word; P1 never matches P10a")
	assert_false(found.has("P1"), "no prefix matches")
