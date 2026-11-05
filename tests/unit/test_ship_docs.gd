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
## 2. Names of AI products and models: no file of the repository names one, with one recorded
##    exception, the owner's spec (docs/GIANTBORN_SPEC_V2.md), which is kept verbatim (DECISIONS.md
##    §3, the Ship gate). The hosting platform's own names stay allowed (the play link's domain,
##    the launcher's meta-tag namespace and runtime object, the integration branch). Each exception
##    must still be needed, so the list stays exact.

const HANDOFF := "res://docs/M2_M5_HANDOFF.md"
const OUTCOMES := ["help_cache", "help_ogre", "intimidate", "force"]
## Packages whose bot runs predate the shipped game code (P17b retuned the game after P17a's).
const EARLIER_BUILDS := ["P17a"]
## Phrases with which the handoff says that runs measured the shipped game.
const SHIPPED_CODE_CLAIMS := ["same game code", "final code"]

## The files that may name AI products or models, and why.
const NAME_EXCEPTIONS := {
	"res://docs/GIANTBORN_SPEC_V2.md": "the owner's spec, kept verbatim (DECISIONS.md §3)",
}
## Folders that are not part of the repository: the exports. Hidden folders (.git, .godot,
## .userdata) are never listed.
const SKIP_DIRS := ["res://builds"]
## Authored text. Generated scenes and resources (.tscn, .tres) come from the scanned builders and
## carry random ids, so they are left out.
const TEXT_EXTENSIONS := ["md", "gd", "json", "cfg", "godot", "html", "sh", "py", "gdshader", "svg", "txt"]
## The hosting platform's names, which name no product or model: the play link's domain, the
## launcher's meta-tag namespace and runtime object, the integration branch.
const PLATFORM_NAMES := "(?i)\\bclaude\\.ai\\b|\\bwindow\\.claude\\b|\\bclaude:(?=[a-z])|\\bclaude/(?=[a-z0-9])"
## AI products, their vendors and their models (a model family with a version number). Bounded by
## letters, not \b, so a name inside an identifier (snake_case, a file name) counts too.
const AI_NAMES := "(?i)(?<![a-z])(claude|anthropic|chat\\s?gpt|openai|gemini|copilot)(?![a-z])|(?<![a-z])gpt-?\\d|(?<![a-z])(opus|sonnet|haiku)[ -]?\\d"


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


func test_no_file_names_an_ai_product_or_model_except_the_owners_spec() -> void:
	var platform := RegEx.create_from_string(PLATFORM_NAMES)
	var names := RegEx.create_from_string(AI_NAMES)
	var own_path := (get_script() as Script).resource_path
	var files := _text_files("res://")
	assert_true(files.size() > 300, "the scan reads the repository's text files (%d)" % files.size())
	for must_scan: String in ["res://README.md", HANDOFF, "res://web/launcher.html", "res://project.godot"]:
		assert_true(files.has(must_scan), "the scan covers %s" % must_scan)
	var offenders: Array[String] = []
	var excepted_hits := {}
	for path in files:
		if path == own_path:
			continue  # this suite spells the names it looks for
		var text := platform.sub(FileAccess.get_file_as_string(path), "", true)
		for m in names.search_all(text):
			if NAME_EXCEPTIONS.has(path):
				excepted_hits[path] = int(excepted_hits.get(path, 0)) + 1
			else:
				var line := text.substr(0, m.get_start()).count("\n") + 1
				offenders.append("%s:%d: %s" % [path.trim_prefix("res://"), line, m.get_string()])
	assert_true(offenders.is_empty(), "AI product or model names outside the recorded exceptions:\n  %s" % "\n  ".join(offenders))
	for path: String in NAME_EXCEPTIONS:
		assert_true(int(excepted_hits.get(path, 0)) > 0,
			"%s (%s) still names them; if not, drop its exception" % [path, NAME_EXCEPTIONS[path]])


func test_the_platform_names_stay_allowed_and_product_names_do_not() -> void:
	var platform := RegEx.create_from_string(PLATFORM_NAMES)
	var names := RegEx.create_from_string(AI_NAMES)
	var allowed := ["<https://claude.ai/artifact/2UYupKVL1xE6pttiZ6NLqe>", "a claude.ai Artifact page",
		"const hot = window.claude && window.claude.hot;", "<meta name=\"claude:viewport-fit-sides\">",
		"`claude/hopeful-gauss-0f323t`", "Stone Skin and Heavy Footfall", "the opus of the Broken Kings"]
	for s: String in allowed:
		assert_true(names.search(platform.sub(s, "", true)) == null, "allowed: %s" % s)
	var named := ["Give Claude this document", "Claude's handoff", "the referenced ChatGPT conversation",
		"an OpenAI model", "GPT-4", "gpt5", "Anthropic", "Opus 4.1", "sonnet-4", "Haiku 3", "Gemini",
		"Copilot", "claude-opus-4", "claude.com", "Giantborn_Claude_Build_Prompt.pdf"]
	for s: String in named:
		assert_true(names.search(platform.sub(s, "", true)) != null, "a name: %s" % s)


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


## Every authored text file under `dir_path` (recursive): hidden folders and SKIP_DIRS left out.
func _text_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.include_hidden = false
	for f in dir.get_files():
		if TEXT_EXTENSIONS.has(f.get_extension().to_lower()):
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		var sub := dir_path.path_join(d)
		if not SKIP_DIRS.has(sub):
			out.append_array(_text_files(sub))
	return out
