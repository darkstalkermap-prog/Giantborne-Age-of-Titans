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
	_b_strings(out)
	return out


## B4 (the milestone B gate): milestone B's words as the player reads them - its materials (the inventory shows an
## item's description whole), the armour pieces (the forge shows a piece's description), the perks and the sets'
## bonuses, where a recipe is made, the Quarry Maul, the Rootwarden's quest, Wren's and Sedge's words, the two titans'
## intros and the new prompts.
func _b_strings(out: Dictionary) -> void:
	for id: String in ["item.hide", "item.ogre_hide", "item.ogre_crown_iron", "item.kings_bell_bronze", "item.warden_bark",
			"item.warden_heartwood", "item.amber_sap", "weapon.quarry_maul"]:
		var r := GameData.get_record(id)
		out[id + " name"] = str(r.get("display_name", ""))
		out[id + " description"] = str(r.get("description", ""))
	for rec: Dictionary in GameData.records_of_type("armour"):
		out[str(rec.id) + " name"] = str(rec.get("display_name", ""))
		out[str(rec.id) + " description"] = str(rec.get("description", ""))
	for rec: Dictionary in GameData.records_of_type("armour_perk"):
		out[str(rec.id) + " text"] = str(rec.get("text", ""))
	for rec: Dictionary in GameData.records_of_type("armour_set"):
		out[str(rec.id) + " name"] = str(rec.get("display_name", ""))
		for b: Dictionary in rec.get("bonuses", []):
			out[str(rec.id) + " " + str(b.get("name", ""))] = str(b.get("text", ""))
	for rec: Dictionary in GameData.records_of_type("recipe"):
		if str(rec.get("where", "")) != "":
			out[str(rec.id) + " where"] = str(rec.where)
	var q := GameData.get_record("quest.rootwarden")
	out["quest.rootwarden name"] = str(q.get("display_name", ""))
	for st: Dictionary in q.get("stages", []):
		out["quest.rootwarden " + str(st.id)] = str(st.get("objective", ""))
		if str(st.get("waiting_text", "")) != "":
			out["quest.rootwarden " + str(st.id) + " waiting"] = str(st.waiting_text)
	for id: String in ["dialogue.woodwright_wren", "dialogue.sedge"]:
		for n: Dictionary in GameData.get_record(id).get("nodes", []):
			out[id + " " + str(n.get("id", ""))] = str(n.get("text", ""))
			for c: Dictionary in n.get("choices", []):
				out[id + " " + str(n.get("id", "")) + " choice " + str(c.get("text", "")).left(12)] = str(c.get("text", ""))
	for id: String in ["cutscene.ogre_king", "cutscene.rootwarden"]:
		var c := GameData.get_record(id)
		for l: Dictionary in c.get("lines", []):
			out["%s %d" % [id, int(l.start)]] = str(l.text)
		out[id + " title"] = str((c.get("title", {}) as Dictionary).get("text", ""))
	for id: String in ["tutorial.ogre_king_trophies", "tutorial.ogre_king_down", "tutorial.rootwarden_dormant",
			"tutorial.rootwarden_regrow", "tutorial.stoneback_warning_north", "tutorial.titan_plates"]:
		out[id] = str(GameData.get_record(id).get("text", ""))


## B4: a Kingsfall piece refused at another forge says where it is made in words a giant in the world can follow (its
## forges are in the Valley; B2's "the Giantforge in the ruins" did not say which ruins, or how to get back there).
func test_the_kingsfall_set_says_its_forges_are_in_the_valley() -> void:
	for id: String in Armour.set_pieces("armour_set.kingsfall"):
		var where := ""
		for rec: Dictionary in GameData.records_of_type("recipe"):
			if str(rec.get("makes", "")) == id:
				where = str(rec.get("where", ""))
		assert_true(where.contains("Valley") and where.contains("Kings' Door"),
			"%s: made in the Valley, back through the Kings' Door (%s)" % [id, where])


func test_no_package_tags_developer_words_or_empty_lines() -> void:
	var tag := RegEx.create_from_string(TAG)
	var strings := _player_strings()
	assert_true(strings.size() > 200, "(the strings were read: %d)" % strings.size())
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
