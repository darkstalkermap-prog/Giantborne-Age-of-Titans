class_name Loot
extends RefCounted
## Loot tables (plan §3.14 design 3, §2.8.3): what a `loot_table` record drops, and the one-time
## award of it to the inventory.
##
## roll(table_id): the table's `guaranteed` items, then `rolls` independent weighted picks among
## its `entries` ({item, count, weight}; chance = weight / sum of weights), drawn from
## Sim.rng_for("loot") so a seeded run (tests, the bot) drops the same things every time. Drops of
## the same item are merged, in the order they first appear.
##
## award_once(id, table_id, recipient): WorldState.try_award_loot(id) first, so an enemy (entity
## id) or a prop (world id) drops its loot at most once, even across checkpoint reloads; then every
## drop goes to the inventory (WorldState.add_item(..., "loot")) and is announced with
## Events.loot_awarded(tick, id, item, count, recipient) (the HUD's "+1 Iron Ingot").
##
## Enemy loot is awarded by PlayerProgression (a kill by the player: the actor's own loot_table,
## set per spawn by the director, else its record's); props award theirs in BreakableProp.

const STREAM := "loot"


## The drops of the loot_table record `table_id` ([] for "" or an unknown table):
## [{"item": String, "count": int}].
static func roll(table_id: String, rng: RandomNumberGenerator = null) -> Array:
	if table_id == "":
		return []
	var table := GameData.get_record(table_id)
	if str(table.get("type", "")) != "loot_table":
		push_warning("Loot.roll: '%s' is not a loot table" % table_id)
		return []
	return roll_table(table, rng if rng != null else Sim.rng_for(STREAM))


## The drops of a loot_table dictionary with `rng` (pure; see roll()).
static func roll_table(table: Dictionary, rng: RandomNumberGenerator) -> Array:
	var counts := {}
	var order: Array = []
	var guaranteed: Variant = table.get("guaranteed", [])
	if typeof(guaranteed) == TYPE_ARRAY:
		for g: Variant in guaranteed:
			if typeof(g) == TYPE_DICTIONARY:
				_add(counts, order, str(g.get("item", "")), int(g.get("count", 1)))
	var entries: Array = table.entries if typeof(table.get("entries")) == TYPE_ARRAY else []
	var total := 0.0
	for e: Variant in entries:
		if typeof(e) == TYPE_DICTIONARY:
			total += maxf(0.0, float(e.get("weight", 0.0)))
	var rolls := int(table.get("rolls", 0))
	if total > 0.0:
		for i in rolls:
			var pick := pick_entry(entries, total, rng.randf())
			if not pick.is_empty():
				_add(counts, order, str(pick.get("item", "")), int(pick.get("count", 1)))
	var out: Array = []
	for item: String in order:
		out.append({"item": item, "count": int(counts[item])})
	return out


## The entry a uniform draw `u` in [0, 1) picks: each entry owns weight / total of the range, in
## list order. {} when nothing can be picked.
static func pick_entry(entries: Array, total: float, u: float) -> Dictionary:
	var at := u * total
	var last: Dictionary = {}
	for e: Variant in entries:
		if typeof(e) != TYPE_DICTIONARY:
			continue
		var w := maxf(0.0, float(e.get("weight", 0.0)))
		if w <= 0.0:
			continue
		last = e
		if at < w:
			return e
		at -= w
	return last   # rounding at the very top of the range


## Rolls `table_id` and gives it to the inventory once for `id` (an entity or world id):
## WorldState.try_award_loot(id) gates it (an id with no table is never marked). Returns the drops
## given ([] when the id was awarded before).
static func award_once(id: String, table_id: String, recipient_id: String) -> Array:
	if id == "" or table_id == "":
		return []
	if not WorldState.try_award_loot(id):
		return []
	var drops := roll(table_id)
	give(id, drops, recipient_id)
	return drops


## Adds `drops` to the inventory (source "loot") and announces each with Events.loot_awarded.
static func give(id: String, drops: Array, recipient_id: String) -> void:
	for d: Dictionary in drops:
		var item := str(d.get("item", ""))
		var count := int(d.get("count", 0))
		if item == "" or count <= 0:
			continue
		WorldState.add_item(item, count, "loot")
		Events.loot_awarded.emit(Sim.tick, id, item, count, recipient_id)


static func _add(counts: Dictionary, order: Array, item: String, count: int) -> void:
	if item == "" or count <= 0:
		return
	if not counts.has(item):
		counts[item] = 0
		order.append(item)
	counts[item] = int(counts[item]) + count
