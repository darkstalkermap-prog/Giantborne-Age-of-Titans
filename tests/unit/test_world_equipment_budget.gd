extends TestSuite
## The world's equipment budget (P29; plan M6-M9 §5.8, decision 32), from the shipped data only
## (tests/support/world_items.gd): the iron and titan iron a path guarantees - world_start's
## inventory, the beacon's cache, the oath's reward on every resolution, the resolution's own items
## (Edda's tribute or banner and iron) and the toll gate's loot when the path breaks it - minus what a
## declared path pays (the toll: 1 iron), for every march resolution and every toll path:
##   * the beacon pays the reinforcement (the start weapon's refit, 2 iron) at the Kingsgate anvil, an
##     iron-tier forge beside the Kingsgate shrine on the main path;
##   * after the reinforcement, the first oath and the toll, every path still holds the first
##     titanforging's 2 titan iron and 2 iron (plan §5.8's row; the titan forges and their checks are
##     P35's and P36's - in M7 the reinforcement is the refit this test pays);
##   * every oath quest's last stage pays exactly loot.oath_reward (1 titan iron, 2 iron).

const MARCH := "quest.oath_march"
const EDDA := "dialogue.edda"
const CAPTAIN := "dialogue.toll_captain"
const BEACON_CACHE := "loot.beacon_cache"
const OATH_REWARD := "loot.oath_reward"
const ANVIL := "world.crownmarch.kingsgate_anvil"
const SHRINE_POI := "poi.kingsgate_shrine"
## The toll paths: the captain's outcome, and whether the path breaks the fort's gate (its loot).
const TOLL_PATHS := {"pay": ["paid", false], "cow": ["cowed", false], "breach": ["", true]}
## The march's resolutions: Edda's outcome, and whether the path breaks the toll fort's gate (help).
const MARCH_PATHS := {"help": ["help", true], "intimidate": ["intimidate", false], "force": ["force", false]}
const TOLL_GATE := "prop.gate_toll"
## The first titanforging (plan §5.8): 2 titan iron and 2 iron.
const TITANFORGE := {"item.titan_iron": 2, "item.iron_ingot": 2}


func _start_weapon() -> String:
	return str((Progression.record().get("world_start", {}) as Dictionary).get("weapon", ""))


## The bag after the beacon and the reinforcement.
func _after_reinforcement() -> Dictionary:
	var b := WorldItems.plus(WorldItems.world_start(), WorldItems.loot(BEACON_CACHE))
	return WorldItems.plus(b, WorldItems.refit_cost(_start_weapon()), -1)


func test_the_beacon_pays_the_reinforcement_at_the_kingsgate_anvil() -> void:
	var start := WorldItems.world_start()
	assert_eq(WorldItems.count(start, WorldItems.IRON), 1, "world_start carries 1 iron")
	var cache := WorldItems.loot(BEACON_CACHE)
	assert_eq([WorldItems.count(cache, WorldItems.IRON), WorldItems.count(cache, WorldItems.TITAN_IRON)], [2, 1],
		"the beacon's cache: 2 iron and 1 titan iron")
	var cost := WorldItems.refit_cost(_start_weapon())
	assert_eq(WorldItems.count(cost, WorldItems.IRON), 2, "reinforcing the start weapon costs 2 iron")
	var after := _after_reinforcement()
	print("    world items: after the beacon and the reinforcement %s" % WorldItems.label(after))
	assert_true(WorldItems.affordable(after), "the beacon pays the reinforcement (%s)" % WorldItems.label(after))
	# The anvil: an iron-tier forge of the layout, inside the Kingsgate shrine's place.
	var anvil: Dictionary = {}
	for el: Dictionary in WorldContent.elements_of("forge_site"):
		if str(el.get("id", "")) == ANVIL:
			anvil = el
	assert_false(anvil.is_empty(), "the Kingsgate anvil is a forge of the layout")
	assert_eq(str(anvil.get("tier", "iron")), "iron", "the anvil is an iron-tier forge")
	assert_true(str(anvil.get("style", "")) != "town" and str(anvil.get("faction", "")) == "",
		"the anvil is no town's forge: it never shuts")
	var poi := GameData.get_record(SHRINE_POI)
	var at := WorldXp.position_of(ANVIL)
	var c: Array = poi.position_m
	assert_true(at.is_finite() and Vector2(at.x - float(c[0]), at.z - float(c[2])).length() <= float(poi.radius_m),
		"the anvil stands by the Kingsgate shrine, on the main path (%s)" % at)


func test_every_march_and_toll_path_keeps_the_first_titanforging() -> void:
	var worst_iron := 1 << 20
	var rows := PackedStringArray()
	for march: String in MARCH_PATHS:
		for toll: String in TOLL_PATHS:
			var b := _after_reinforcement()
			b = WorldItems.plus(b, WorldItems.stage_items(MARCH))
			b = WorldItems.plus(b, WorldItems.choice_items(EDDA, str(MARCH_PATHS[march][0])))
			var toll_outcome := str(TOLL_PATHS[toll][0])
			if toll_outcome != "":
				b = WorldItems.plus(b, WorldItems.choice_items(CAPTAIN, toll_outcome))
			if bool(TOLL_PATHS[toll][1]) or bool(MARCH_PATHS[march][1]):
				b = WorldItems.plus(b, WorldItems.prop_loot(TOLL_GATE))
			rows.append("%s+%s: %s" % [march, toll, WorldItems.label(b)])
			assert_true(WorldItems.affordable(b), "%s with the toll %s never runs short (%s)" % [march, toll, WorldItems.label(b)])
			var left := WorldItems.plus(b, TITANFORGE, -1)
			assert_true(WorldItems.affordable(left), "%s with the toll %s keeps a titanforging (%s)" % [
				march, toll, WorldItems.label(b)])
			worst_iron = mini(worst_iron, WorldItems.count(b, WorldItems.IRON))
	print("    world items after the first oath: " + ", ".join(rows))
	assert_eq(worst_iron, 2, "the worst path (force, toll paid) keeps exactly 2 iron (plan §5.8)")


func test_every_oath_resolution_pays_the_oath_reward() -> void:
	var reward := WorldItems.loot(OATH_REWARD)
	assert_eq([WorldItems.count(reward, WorldItems.IRON), WorldItems.count(reward, WorldItems.TITAN_IRON)], [2, 1],
		"an oath's reward: 2 iron and 1 titan iron")
	var oaths := 0
	for id: String in GameData.ids_of_type("quest"):
		if OathRules.oath_key(id) == "":
			continue
		oaths += 1
		assert_eq(WorldItems.stage_items(id), reward, "%s's last stage pays loot.oath_reward on every resolution" % id)
	assert_true(oaths >= 1, "the march oath ships")


func test_the_toll_and_the_reconciliations_cost_what_the_records_say() -> void:
	assert_eq(WorldItems.count(WorldItems.choice_items(CAPTAIN, "paid"), WorldItems.IRON), -1, "the toll costs 1 iron")
	assert_eq(WorldItems.choice_items(CAPTAIN, "cowed"), {}, "cowing the captain costs nothing")
	for short: String in ["brannock", "millford"]:
		var rec := GameData.get_record("faction." + short)
		var cost := WorldItems.bag((rec.get("reconcile", {}) as Dictionary).get("cost", []))
		var npc := "npc.edda" if short == "brannock" else "npc.reeve_tamsin"
		var talker := str(GameData.get_record(npc).get("dialogue", ""))
		assert_eq(WorldItems.choice_items(talker, "reconcile_" + short), WorldItems.plus({}, cost, -1),
			"%s's reconciliation at its talker takes its cost (%s)" % [short, WorldItems.label(cost)])
