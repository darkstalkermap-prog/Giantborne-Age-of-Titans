class_name WorldItems
extends RefCounted
## The world's guaranteed items for the equipment budget tests (P29; plan M6-M9 §5.8, decision 32):
## bags of item id -> count, built from the shipped records only - world_start's inventory, a loot
## table's guaranteed entries, a quest stage's items, a dialogue choice's give_items minus its
## take_items (found by the outcome it writes), a prop's guaranteed loot - and a refit's cost. P35
## and P36 add their oaths' rows with the same helpers.

const IRON := "item.iron_ingot"
const TITAN_IRON := "item.titan_iron"


## A bag from an items array ([{item, count}]).
static func bag(items: Variant) -> Dictionary:
	var out := {}
	if typeof(items) != TYPE_ARRAY:
		return out
	for it: Variant in items:
		if typeof(it) == TYPE_DICTIONARY and str(it.get("item", "")) != "":
			out[str(it.item)] = int(out.get(str(it.item), 0)) + int(it.get("count", 1))
	return out


## a + b (or a - b with sign -1): a new bag.
static func plus(a: Dictionary, b: Dictionary, sign := 1) -> Dictionary:
	var out := a.duplicate()
	for k: Variant in b:
		out[k] = int(out.get(k, 0)) + sign * int(b[k])
	return out


static func count(b: Dictionary, item: String) -> int:
	return int(b.get(item, 0))


## world_start's inventory.
static func world_start() -> Dictionary:
	return bag((Progression.record().get("world_start", {}) as Dictionary).get("inventory", []))


## A loot table's guaranteed entries (what it always pays).
static func loot(table_id: String) -> Dictionary:
	return bag(GameData.get_record(table_id).get("guaranteed", []))


## The items of stage `stage_id` of `quest_id` (the last stage when stage_id is "").
static func stage_items(quest_id: String, stage_id := "") -> Dictionary:
	var stages: Array = GameData.get_record(quest_id).get("stages", [])
	for s: Dictionary in stages:
		if str(s.get("id", "")) == stage_id or (stage_id == "" and s == stages.back()):
			return bag(s.get("items", []))
	return {}


## The net items of the dialogue choice whose outcome is `outcome` in `dialogue_id` (give_items minus
## take_items); the least iron of them when several choices have that outcome.
static func choice_items(dialogue_id: String, outcome: String) -> Dictionary:
	var found := false
	var worst := {}
	for n: Dictionary in GameData.get_record(dialogue_id).get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			var e: Dictionary = c.get("effects", {}) if typeof(c.get("effects")) == TYPE_DICTIONARY else {}
			if str(e.get("outcome", "")) != outcome:
				continue
			var net := plus(bag(e.get("give_items", [])), bag(e.get("take_items", [])), -1)
			if not found or count(net, IRON) < count(worst, IRON):
				worst = net
			found = true
	return worst


## A prop's guaranteed loot when it breaks (its record's loot, and its loot_table's guaranteed
## entries if it names one).
static func prop_loot(prop_id: String) -> Dictionary:
	var rec := GameData.get_record(prop_id)
	var out := bag(rec.get("loot", []))
	var table := str(rec.get("loot_table", ""))
	return plus(out, loot(table)) if table != "" else out


## The cost of a weapon's refit (its record's upgrade: reinforcing).
static func refit_cost(weapon_id: String) -> Dictionary:
	var up: Variant = GameData.get_record(weapon_id).get("upgrade")
	return bag((up as Dictionary).get("cost", [])) if typeof(up) == TYPE_DICTIONARY else {}


## True when no count in the bag is negative.
static func affordable(b: Dictionary) -> bool:
	for k: Variant in b:
		if int(b[k]) < 0:
			return false
	return true


## "iron/titan iron" for a bag (test messages).
static func label(b: Dictionary) -> String:
	return "%d iron / %d titan iron" % [count(b, IRON), count(b, TITAN_IRON)]
