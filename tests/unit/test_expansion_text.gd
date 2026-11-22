extends TestSuite
## A5: the expansion's player-facing words (milestone A's records: Stoneback's items, quest, dialogue, the intro's
## lines and title card) carry no package tag ("A2: ..."), no developer wording and no placeholder; and the advice
## the game gives on Stoneback names the fight A4 made - his shins.

const ITEMS := ["item.stoneback_heart_stone", "item.stoneback_slab", "item.quarry_iron"]
const DIALOGUES := ["dialogue.quarryman_bram", "dialogue.reeve_tamsin"]
## Words that belong to the developers, not the player.
const DEV_WORDS := ["no recipe yet", "todo", "tbd", "placeholder", "lorem", "for later", "(test", "fixme"]
const TAG := "^(A|P|M|W)[0-9]+[a-z]?: "


func _player_strings() -> Dictionary:
	var out := {}
	for id: String in ITEMS:
		var r := GameData.get_record(id)
		out[id + " name"] = str(r.get("display_name", ""))
		out[id + " description"] = str(r.get("description", ""))
	var q := GameData.get_record("quest.stoneback")
	out["quest name"] = str(q.get("display_name", ""))
	for s: Dictionary in q.get("stages", []):
		out["quest " + str(s.id)] = str(s.get("objective", ""))
		if str(s.get("waiting_text", "")) != "":
			out["quest " + str(s.id) + " waiting"] = str(s.waiting_text)
	for id: String in DIALOGUES:
		for n: Dictionary in GameData.get_record(id).get("nodes", []):
			out[id + " " + str(n.get("id", ""))] = str(n.get("text", ""))
			for c: Dictionary in n.get("choices", []):
				out[id + " " + str(n.get("id", "")) + " choice"] = str(c.get("text", ""))
	var cut := GameData.get_record(ExpansionState.INTRO_ID)
	for l: Dictionary in cut.get("lines", []):
		out["intro %d" % int(l.start)] = str(l.text)
	out["intro title"] = str((cut.get("title", {}) as Dictionary).get("text", ""))
	out["intro sub"] = str((cut.get("title", {}) as Dictionary).get("sub", ""))
	return out


func test_no_package_tags_developer_words_or_empty_lines() -> void:
	var tag := RegEx.create_from_string(TAG)
	var strings := _player_strings()
	assert_true(strings.size() > 30, "(the strings were read: %d)" % strings.size())
	for k: String in strings:
		var s: String = strings[k]
		assert_true(s.strip_edges() != "", "%s is not empty" % k)
		assert_true(tag.search(s) == null, "%s carries no package tag (%s)" % [k, s.left(40)])
		for w: String in DEV_WORDS:
			assert_false(s.to_lower().contains(w), "%s has no developer wording \"%s\"" % [k, w])
		assert_false(s.contains("  ") or s.contains(" ,") or s.contains(" ."), "%s has no stray spacing" % k)


func test_the_advice_on_stoneback_names_his_shins() -> void:
	var slay := ""
	for s: Dictionary in GameData.get_record("quest.stoneback").get("stages", []):
		if str(s.id) == "slay":
			slay = str(s.objective)
	assert_true(slay.to_lower().contains("shin"), "the quest's slay objective names his shins (%s)" % slay)
	var bram := ""
	for n: Dictionary in GameData.get_record("dialogue.quarryman_bram").get("nodes", []):
		bram += str(n.get("text", "")) + " "
	assert_true(bram.to_lower().contains("shins"), "Old Bram tells of his shins")
	assert_false(bram.contains("only knocking on a wall"), "and no longer says his legs are no use to strike")
