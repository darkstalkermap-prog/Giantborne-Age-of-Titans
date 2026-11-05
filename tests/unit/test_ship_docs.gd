extends TestSuite
## Ship gate (wave-11 review): regression tests for the documentation findings.
##
## 1. The handoff (docs/M2_M5_HANDOFF.md) counted P17a's assisted runs of the four village outcomes
##    as runs on "the same game code" (its §6.4 heading, §1) and as the M4 gate's evidence, but
##    P17b retuned the game after them: the Ogre King's slam and combo, the ogre's smash, the
##    soldiers' pause between strikes, the archer's shot, the brace counter, the swing's vertical
##    aim, the director's budget for hostile factions, the props' merged meshes. Gate evidence must
##    come from runs on the shipped game code:
##    - no row of the gate tables (§5) cites P17a;
##    - the M4 row cites §6.2, which reports a completed assisted run of every village outcome on
##      the final code;
##    - no heading or sentence that speaks of "the same game code" or "the final code" names P17a.

const HANDOFF := "res://docs/M2_M5_HANDOFF.md"
const OUTCOMES := ["help_cache", "help_ogre", "intimidate", "force"]
## Packages whose bot runs predate the shipped game code (P17b retuned the game after P17a's).
const EARLIER_BUILDS := ["P17a"]
## Phrases with which the handoff says that runs measured the shipped game.
const SHIPPED_CODE_CLAIMS := ["same game code", "final code"]


func test_the_gate_table_cites_only_runs_on_the_shipped_game_code() -> void:
	var text := _read(HANDOFF)
	var gates := _section(text, "## 5. ")
	assert_true(gates.contains("### 5.1 Milestone exit gates"), "§5 holds the gate tables")
	var cited: Array[String] = []
	for line in gates.split("\n"):
		for pkg: String in EARLIER_BUILDS:
			if line.contains(pkg):
				cited.append(line.left(140))
	assert_true(cited.is_empty(), "gate rows cite runs that predate P17b's tuning:\n  %s" % "\n  ".join(cited))
	var m4 := ""
	for line in gates.split("\n"):
		if line.begins_with("| M4 Playable Valley |"):
			m4 = line
	assert_true(m4 != "", "the M4 row is in the table")
	assert_true(m4.contains("§6.2"), "the M4 row cites the runs on the final code (§6.2): %s" % m4.left(200))
	var runs := _section(text, "### 6.2 ")
	assert_true(runs.get_slice("\n", 0).contains("final code"), "§6.2 reports runs on the final code")
	for outcome: String in OUTCOMES:
		assert_true(_completed_row(runs, outcome), "§6.2 has a completed assisted run of %s" % outcome)


func test_no_heading_or_sentence_counts_earlier_runs_as_the_shipped_code() -> void:
	var text := _read(HANDOFF)
	var clauses := _clauses(text)
	assert_true(clauses.size() > 100, "the handoff splits into clauses (%d)" % clauses.size())
	var offenders: Array[String] = []
	for clause in clauses:
		var claims := false
		for phrase: String in SHIPPED_CODE_CLAIMS:
			claims = claims or clause.contains(phrase)
		if not claims:
			continue
		for pkg: String in EARLIER_BUILDS:
			if clause.contains(pkg):
				offenders.append(clause.left(160))
	assert_true(offenders.is_empty(), "runs before P17b's tuning called the shipped code:\n  %s" % "\n  ".join(offenders))


## The text of a file under res:// (docs/ is .gdignored for imports, but read from disk as it is).
func _read(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_true(text != "", "%s reads" % path)
	return text


## The section of `text` whose heading line begins with `heading`, up to the next heading of the
## same or a higher level; its first line is the heading.
func _section(text: String, heading: String) -> String:
	var level := heading.find(" ")
	var out: Array[String] = []
	var inside := false
	for line in text.split("\n"):
		if line.begins_with("#"):
			var line_level := line.find(" ")
			if inside and line_level <= level:
				break
			if line.begins_with(heading):
				inside = true
		if inside:
			out.append(line)
	return "\n".join(out)


## True when a table row of `section` has `outcome` as its first cell and "yes" in its second.
func _completed_row(section: String, outcome: String) -> bool:
	for line in section.split("\n"):
		if not line.begins_with("|"):
			continue
		var cells := line.split("|")
		if cells.size() < 4:
			continue
		if cells[1].strip_edges().replace("`", "") == outcome and cells[2].strip_edges().begins_with("yes"):
			return true
	return false


## The handoff's headings, table rows and the clauses of its paragraphs and list items (split at
## ". " and "; "), each as one line of text.
func _clauses(text: String) -> PackedStringArray:
	var numbered_item := RegEx.create_from_string("^\\d+\\. ")
	var blocks: Array[String] = []
	var current := ""
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		var starts_item := line.begins_with("- ") or numbered_item.search(line) != null
		if line == "" or line.begins_with("#") or line.begins_with("|") or starts_item:
			if current != "":
				blocks.append(current)
			current = ""
			if line.begins_with("#") or line.begins_with("|"):
				blocks.append(line)
				continue
		if line != "":
			current = line if current == "" else current + " " + line
	if current != "":
		blocks.append(current)
	var splitter := RegEx.create_from_string("[.;](\\s+|$)")
	var out := PackedStringArray()
	for block in blocks:
		var start := 0
		for m in splitter.search_all(block):
			out.append(block.substr(start, m.get_end() - start).strip_edges())
			start = m.get_end()
		if start < block.length():
			out.append(block.substr(start).strip_edges())
	return out

