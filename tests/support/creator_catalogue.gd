class_name CreatorCatalogue
extends RefCounted
## P55 (plan M11 §2.6, §3.8): the test-only catalogue at the target's size (tests/fixtures/appearance/
## creator_catalogue.json: 35 garments in ten slots, 8 accessories, 12 outfits, 12 hair styles, 11 beards, 28
## tattoos in five regions, 8 war paints, 10 scars, 14 dyes, beads and six face sliders - about 190 options with
## the sets it leaves as they are). install() puts its sets over the game's for one test through TestFixtures
## (ResetHooks puts them back after the test); the creator builds every row from the sets, so the same screen
## shows today's data and this. Never game data: P54 and P56 own the real sets.

const PATH := "res://tests/fixtures/appearance/creator_catalogue.json"


## The fixture's document ({} when it cannot be read).
static func document() -> Dictionary:
	var r: Variant = JsonIO.read_file(PATH)
	if typeof(r) == TYPE_DICTIONARY and typeof((r as Dictionary).get("data")) == TYPE_DICTIONARY:
		return r.data
	return {}


## Puts the fixture's sets over the game's for this test (TestFixtures.record_override: restored after it).
## Returns how many options the creator offers with it (the fixture's own count).
static func install() -> int:
	var doc := document()
	var sets: Dictionary = doc.get("sets", {})
	for category: String in sets:
		TestFixtures.record_override(Appearance.SET_PREFIX + category, {"type": "appearance_set", "category": category,
			"id": Appearance.SET_PREFIX + category, "display_name": category.capitalize(), "options": sets[category]})
	return int(doc.get("total", 0))


## The same without TestFixtures (a probe run outside the test runner: nothing to restore).
static func install_for_probe() -> int:
	var doc := document()
	var sets: Dictionary = doc.get("sets", {})
	for category: String in sets:
		GameData.override_record(Appearance.SET_PREFIX + category, {"type": "appearance_set", "category": category,
			"id": Appearance.SET_PREFIX + category, "display_name": category.capitalize(), "options": sets[category]})
	return int(doc.get("total", 0))
