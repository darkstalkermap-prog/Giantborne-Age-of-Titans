extends IntegrationSuite
## M8 gate (F30, F44): the HUD's message line shows every refusal, size-gate text and notice the game
## ships whole at 1280 x 720 - wrapped at words onto at most Hud.MESSAGE_MAX_LINES lines - instead of
## one line trimmed with an ellipsis, which cut the guidance off most refusals (the Needle's pointer to
## the north ridge, how to burn a brood nest, what opens the fort's forge). The texts are read where
## they live, so new wording is covered as it lands: the records (props' locked_message, shrines'
## growth texts, factions' lines, world events' lines), every "message" and "*_message" field of the
## layout tables (size gates, narrow passes, forges, racks, fires, exits, beacons, stage-gated
## interactables, reward areas) and the code's own refusals and defaults. Besides: the box keeps the
## newest message whole and stays inside its region (no other region overlaps it: test_hud_layout),
## the same message is not shown twice, and a long message stays longer than a short one.

const VIEW := Vector2(1280, 720)
const LAYOUTS := ["res://tools/data/world/world.json", "res://tools/data/world/crownmarch.json",
	"res://tools/data/world/greywood.json", "res://tools/data/world/drowned_steps.json",
	"res://tools/data/world/aldmere.json", "res://tools/data/world/stonehold.json",
	"res://tools/data/valley_layout.json"]

var hud: Hud
var frame: Control


func before_each() -> void:
	await super()
	var layer := CanvasLayer.new()
	world.add_child(layer)
	frame = Control.new()
	frame.position = Vector2.ZERO
	frame.size = VIEW
	layer.add_child(frame)
	hud = Hud.new()
	frame.add_child(hud)
	await get_tree().process_frame


## Every text the game ships for the message line: label -> text.
static func shipped_texts() -> Dictionary:
	var out := {}
	for path: String in LAYOUTS:
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		_layout_texts(d, path.get_file(), out)
	for rec: Dictionary in GameData.records_of_type("prop"):
		_record_texts(rec, out)
	for rec: Dictionary in GameData.records_of_type("shrine"):
		_record_texts(rec, out)
		for t: Variant in rec.get("growth_conditions_text", []):
			out["%s.growth_conditions_text" % rec.id] = str(t)
	for rec: Dictionary in GameData.records_of_type("faction"):
		for key: String in ["warn_text", "hostile_text", "stood_down_text", "reconciled_text"]:
			if str(rec.get(key, "")) != "":
				out["%s.%s" % [rec.id, key]] = str(rec[key])
	for rec: Dictionary in GameData.records_of_type("world_event"):
		for key: String in ["start_text", "respawn_text"]:
			if str(rec.get(key, "")) != "":
				out["%s.%s" % [rec.id, key]] = str(rec[key])
	# The code's own refusals and defaults.
	for gate: int in SizeGate.DEFAULT_MESSAGES:
		out["SizeGate.DEFAULT_MESSAGES[%d]" % gate] = str(SizeGate.DEFAULT_MESSAGES[gate])
	for key: String in SiegeEngine.REFUSAL_TEXTS:
		out["SiegeEngine.REFUSAL_TEXTS.%s" % key] = str(SiegeEngine.REFUSAL_TEXTS[key])
	for key: String in FactionState.FALLBACK_TEXTS:
		out["FactionState.FALLBACK_TEXTS.%s" % key] = str(FactionState.FALLBACK_TEXTS[key])
	for pair: Array in [["Forge.DEFAULT_CLOSED_MESSAGE", Forge.DEFAULT_CLOSED_MESSAGE],
			["Forge.TIER_MESSAGE", Forge.TIER_MESSAGE], ["DenWall.OPEN_MESSAGE", DenWall.OPEN_MESSAGE],
			["DenWall.BARGAIN_MESSAGE", DenWall.BARGAIN_MESSAGE], ["BroodNest.BURNED_MESSAGE", BroodNest.BURNED_MESSAGE],
			["GreatPineTree.UPROOTED_MESSAGE", GreatPineTree.UPROOTED_MESSAGE],
			["BreakableProp.PROTECTED_MESSAGE", BreakableProp.PROTECTED_MESSAGE],
			["GameSession.NARROW_PATHS", GameSession.NARROW_PATHS], ["GameSession.NOT_VISITED", GameSession.NOT_VISITED],
			["GameSession.NOT_OPEN", GameSession.NOT_OPEN], ["GameSession.UNKNOWN_PLACE", GameSession.UNKNOWN_PLACE]]:
		out[str(pair[0])] = str(pair[1])
	return out


static func _layout_texts(v: Variant, where: String, out: Dictionary) -> void:
	if v is Dictionary:
		var d: Dictionary = v
		for key: Variant in d:
			var k := str(key)
			if typeof(d[key]) == TYPE_STRING and (k == "message" or k.ends_with("_message")):
				if str(d[key]) != "":
					out["%s %s.%s" % [where, str(d.get("id", "?")), k]] = str(d[key])
			else:
				_layout_texts(d[key], where, out)
	elif v is Array:
		for item: Variant in v:
			_layout_texts(item, where, out)


static func _record_texts(rec: Dictionary, out: Dictionary) -> void:
	for key: Variant in rec:
		if typeof(rec[key]) == TYPE_STRING and str(key).ends_with("_message") and str(rec[key]) != "":
			out["%s.%s" % [rec.id, key]] = str(rec[key])


func _box() -> VBoxContainer:
	return hud.get("_messages") as VBoxContainer


func _newest() -> Label:
	var box := _box()
	return box.get_child(box.get_child_count() - 1) as Label if box.get_child_count() > 0 else null


## True when `l` shows all of its text: a wrapped label shows every line it has, a one-line label's
## text fits its width.
static func _shown_whole(l: Label) -> bool:
	if l.autowrap_mode != TextServer.AUTOWRAP_OFF:
		return l.get_visible_line_count() >= l.get_line_count()
	var font := l.get_theme_font("font")
	return font.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x <= l.size.x + 0.5


func _region() -> Rect2:
	return hud.layout_regions(VIEW)["messages"]


func _drawn(c: Control) -> Rect2:
	return Rect2(c.get_global_rect().position - frame.get_global_rect().position, c.size)


func test_every_shipped_text_is_shown_whole_at_1280x720() -> void:
	var texts := shipped_texts()
	assert_true(texts.size() >= 60, "the texts are found (%d)" % texts.size())
	var keys: Array = texts.keys()
	keys.sort()
	var cut := PackedStringArray()
	var outside := PackedStringArray()
	var region := _region()
	assert_true(Rect2(Vector2.ZERO, VIEW).encloses(region), "the message box lies on the 1280 x 720 screen")
	for k: String in keys:
		var t: String = texts[k]
		hud.show_message(t, "warn")
		await get_tree().process_frame
		await get_tree().process_frame
		var l := _newest()
		if l == null or l.text != t:
			cut.append("%s: not shown" % k)
			continue
		if not _shown_whole(l) or l.get_line_count() > Hud.MESSAGE_MAX_LINES:
			cut.append("%s (%d lines): %s" % [k, l.get_line_count(), t])
		if not region.grow(0.5).encloses(_drawn(l)) or not region.grow(0.5).encloses(_drawn(_box())):
			outside.append("%s: line %s, box %s, region %s" % [k, _drawn(l), _drawn(_box()), region])
		if hud.message_line_count(t) != l.get_line_count():
			cut.append("%s: counted %d lines, the label has %d" % [k, hud.message_line_count(t), l.get_line_count()])
	assert_eq(cut, PackedStringArray(), "every shipped refusal, size-gate text and notice is shown whole")
	assert_eq(outside, PackedStringArray(), "and inside the message box's region")


func test_the_box_keeps_the_newest_whole_inside_its_region() -> void:
	var region := _region()
	for t: String in ["Destroyed: Practice Gate", "+2 Iron", "Equipped: Great Club"]:
		hud.show_message(t, "info")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(hud.message_texts().size(), 3, "three one-line messages")
	assert_true(region.grow(0.5).encloses(_drawn(_box())), "fit the box's region (%s in %s)" % [_drawn(_box()), region])
	var needle: String = shipped_texts().get("greywood.json world.gate.needle.message", "")
	var nest: String = GameData.get_record("prop.brood_nest").get("locked_message", "")
	assert_true(needle != "" and nest != "", "the Needle's and the nest's refusals")
	hud.show_message(needle, "warn")
	hud.show_message(nest, "warn")
	await get_tree().process_frame
	await get_tree().process_frame
	var shown := hud.message_texts()
	assert_eq(shown[shown.size() - 1], nest, "the newest message is at the bottom")
	assert_true(_shown_whole(_newest()), "and shown whole (%d lines)" % _newest().get_line_count())
	assert_true(region.grow(0.5).encloses(_drawn(_box())), "the box stays in its region (%s in %s)" % [_drawn(_box()), region])
	assert_false(shown.has("Destroyed: Practice Gate"), "the oldest gave way")
	# The same message again (after the 0.6 s repeat guard) moves down instead of showing twice.
	hud.show_message("Too small to uproot this oak (stage 3).", "warn")
	hud.show_message("+2 Iron", "good")
	hud.set("_time", float(hud.get("_time")) + 1.0)
	hud.show_message("Too small to uproot this oak (stage 3).", "warn")
	await get_tree().process_frame
	shown = hud.message_texts()
	assert_eq(shown.count("Too small to uproot this oak (stage 3)."), 1, "a repeated message is shown once")
	assert_eq(shown[shown.size() - 1], "Too small to uproot this oak (stage 3).", "at the bottom (%s)" % [shown])


func test_a_long_message_stays_longer() -> void:
	var short := "Destroyed: Practice Gate"
	var long: String = GameData.get_record("prop.brood_nest").get("locked_message", "")
	assert_eq(Hud.message_lifetime(short), Hud.MESSAGE_LIFETIME, "a short message stays %.1f s" % Hud.MESSAGE_LIFETIME)
	assert_true(Hud.message_lifetime(long) > Hud.MESSAGE_LIFETIME + 3.0,
		"a long one long enough to read (%.1f s for %d characters)" % [Hud.message_lifetime(long), long.length()])
	assert_true(Hud.message_lifetime(long.repeat(5)) <= Hud.MESSAGE_MAX_LIFETIME, "never longer than %.0f s" % Hud.MESSAGE_MAX_LIFETIME)
	hud.show_message(short, "info")
	hud.show_message(long, "warn")
	var t0 := float(hud.get("_time"))
	hud.set("_time", t0 + Hud.MESSAGE_LIFETIME + 0.1)
	hud.call("_update_messages")
	assert_eq(hud.message_texts(), PackedStringArray([long]), "after %.1f s only the long message stays" % Hud.MESSAGE_LIFETIME)
	hud.set("_time", t0 + Hud.message_lifetime(long) + 0.1)
	hud.call("_update_messages")
	assert_eq(hud.message_texts(), PackedStringArray(), "and it goes after its own lifetime")
