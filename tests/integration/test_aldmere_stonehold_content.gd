extends TestSuite
## The Aldmere March's and the Stonehold's content (P36; plan M6-M9 §3.20, §5.4, §5.7, §5.9, §5.10,
## §5.13), from the shipped records, the layout tables and the world's index only (the default tier's
## budget): the encounters within the rules (a leash of at most 70 m or an arena, every spawn inside
## it, at most twelve individual combatants at any stage, the formation caps on both platforms), the
## engines their crews serve placed in the layout, Fort Aldmere's real gate, the battle's composition
## (its aggregate on both platforms), the crown's three roads as first oaths at stage 4 and the
## herald's four parley tokens, the factions, the siege of Skarn, the wander tables, the main thread's
## end and the checkpoints outside the two arenas within 80 m.

const LEVEL := "level.world"
const CROWN := "quest.oath_crown"
const MAIN := "quest.world_main"
const MAX_LEASH_M := 70.0
const BUDGET := 12
const CHECKPOINT_M := 80.0
## The battle's encounters and engines (the arena element world.aldmere.iron_regiment_arena).
const BATTLE := ["encounter.aldmere_iron_regiment_wall", "encounter.aldmere_iron_regiment_charge",
	"encounter.aldmere_iron_regiment_stand"]
const LONGHOUSES := ["world.stonehold.skarn_longhouse_1", "world.stonehold.skarn_longhouse_2",
	"world.stonehold.skarn_longhouse_3"]


func _p36_encounters() -> Array:
	return GameData.records_of_type("encounter").filter(func(r: Dictionary) -> bool:
		var id := str(r.id)
		return id.begins_with("encounter.aldmere_") or id.begins_with("encounter.stonehold_") \
			or id.begins_with("encounter.tpl_aldmere_") or id.begins_with("encounter.tpl_stonehold_"))


static func _xz(a: Variant) -> Vector2:
	if a is Vector3:
		return Vector2((a as Vector3).x, (a as Vector3).z)
	var arr: Array = a
	return Vector2(float(arr[0]), float(arr[2]))


func _element(id: String) -> Dictionary:
	for el: Dictionary in WorldContent.elements():
		if str(el.get("id", "")) == id:
			return el
	return {}


## world id -> true for every engine of the layout (placed outright or as a ConditionSpawn).
func _engines() -> Dictionary:
	var out := {}
	for el: Dictionary in WorldContent.elements_of("engine"):
		out[str(el.id)] = el
	return out


func test_the_regions_encounters_keep_the_rules() -> void:
	var encs := _p36_encounters()
	assert_true(encs.size() >= 20, "both regions' encounters and templates ship (%d)" % encs.size())
	for old: String in ["encounter.aldmere_road_wolves", "encounter.aldmere_ridge_bandits", "encounter.stonehold_ironway_wolves",
			"encounter.stonehold_cairn_ogres"]:
		assert_false(GameData.has_record(old), "P25's light encounter %s is replaced" % old)
	var engines := _engines()
	for enc: Dictionary in encs:
		var id := str(enc.id)
		var arena := bool(enc.get("arena", false))
		var leash := float(enc.get("leash_radius_m", 0.0))
		assert_true(arena or (leash > 0.0 and leash <= MAX_LEASH_M), "%s has a leash of at most 70 m or is an arena (%s)" % [id, leash])
		var c := _xz(enc.center_m)
		var formation_ids := {}
		for f: Dictionary in enc.get("formations", []):
			formation_ids[str(f.id)] = true
		for stage in range(3, 7):
			var individuals := 0
			for sp: Dictionary in enc.spawns:
				if str(sp.get("formation", "")) == "" and FormationRules.stage_allows(sp, stage) \
						and str(GameData.get_record(str(sp.definition)).get("type", "")) == "enemy" \
						and bool(enc.get("counts_toward_budget", true)):
					individuals += 1
			assert_true(individuals <= BUDGET, "%s: at most %d individual combatants at stage %d (%d)" % [id, BUDGET, stage, individuals])
			var counts := FormationRules.member_counts(enc, stage)
			assert_true(int(counts[0]) <= 40 and int(counts[1]) <= 20, "%s fits the formation caps at stage %d (%s)" % [id, stage, counts])
		for sp: Dictionary in enc.spawns:
			assert_true(str(sp.entity_id).begins_with("world."), "%s's spawn ids are world ids" % id)
			if not arena:
				assert_true(_xz(sp.position_m).distance_to(c) <= leash + 0.01, "%s's %s starts inside its leash" % [id, sp.entity_id])
			assert_true(GameData.has_record(str(sp.definition)), "%s: %s exists" % [id, sp.definition])
			if str(sp.get("formation", "")) != "":
				assert_true(formation_ids.has(str(sp.formation)), "%s: %s's formation is the encounter's" % [id, sp.entity_id])
		for e: Dictionary in enc.get("engines", []):
			assert_true(engines.has(str(e.engine)), "%s: its engine %s is placed in the layout" % [id, e.engine])
			for crew: Variant in e.crew:
				var sp: Dictionary = {}
				for s: Dictionary in enc.spawns:
					if str(s.entity_id) == str(crew):
						sp = s
				var el: Dictionary = engines.get(str(e.engine), {})
				var at := Vector2(float((el.get("pos", [0, 0]) as Array)[0]), float((el.get("pos", [0, 0]) as Array)[1]))
				assert_true(not sp.is_empty() and _xz(sp.position_m).distance_to(at) <= 4.0,
					"%s: the crew %s starts within 4 m of its engine" % [id, crew])
		if not bool(enc.get("template", false)):
			assert_true(str(WorldContent.index().encounters.get(id, {}).get("chunk", "")) != "", "%s has its chunk in the index" % id)


func test_fort_aldmere_has_its_real_gate_and_garrison() -> void:
	var gate := GameData.get_record("prop.gate_fort_aldmere")
	assert_eq([int(gate.get("health", 0)), int(gate.get("armor", 0)), int(gate.get("min_growth_stage", 0))], [3000, 50, 4],
		"the gate: health 3,000, armour 50, breached at stage 4 (plan §5.4)")
	assert_eq(str(gate.get("open_when_flag", "")), "world.aldmere.fort_open", "a parley or a spared Corvane opens it")
	var el := _element("world.aldmere.fort_gate")
	assert_eq(str(el.get("record", "")), "prop.gate_fort_aldmere", "the layout's gate is the real one")
	assert_false(bool(el.get("indestructible", false)), "no longer indestructible (P25's M7 gate)")
	var garrison := GameData.get_record("encounter.aldmere_fort_gate")
	var stand_down: Dictionary = garrison.get("stand_down_when", {})
	var ctx := QuestConditions.empty_context()
	ctx.flags = {"oath.crown.parley_accepted": true}
	assert_true(QuestConditions.holds(stand_down, ctx), "the garrison stands down once the herald accepted a parley")
	ctx.destroyed = {"world.aldmere.fort_gate": true}
	assert_false(QuestConditions.holds(stand_down, ctx), "...but not once the gate is breached")
	var archers := 0
	for sp: Dictionary in garrison.spawns:
		if str(sp.definition) == "enemy.archer":
			archers += 1
			var post := false
			for m: Dictionary in _markers("elevation"):
				if Vector2(float(m.pos[0]), float(m.pos[1])).distance_to(_xz(sp.position_m)) < 0.5:
					post = true
			assert_true(post, "%s stands on a bastion's elevation marker" % sp.entity_id)
	assert_eq(archers, 4, "four wall archers on the gate's bastions")


func _markers(kind: String) -> Array:
	var out: Array = []
	for r: String in WorldLayout.REGION_FILES:
		var t := WorldFeatures.load_json(WorldLayout.DATA_DIR.path_join(r + ".json"))
		for m: Dictionary in t.get("markers", []):
			if str(m.get("kind", "")) == kind:
				out.append(m)
	return out


func test_the_iron_regiment_is_one_battle_on_both_platforms() -> void:
	var arena := _element("world.aldmere.iron_regiment_arena")
	assert_eq(str(arena.get("style", "")), "battle", "Fort Aldmere's bailey holds the battle (FortBattle)")
	assert_eq(str(arena.get("battle_id", "")), "battle.iron_regiment", "under P34's battle id")
	var phases: Array = arena.get("phases", [])
	assert_eq(phases.map(func(p: Dictionary) -> Array: return p.encounters), [[BATTLE[0]], [BATTLE[1]], [BATTLE[2]]],
		"the Wall, the Charge and the Last Stand")
	assert_eq(phases.map(func(p: Dictionary) -> float: return float(p.below)), [1.0, 0.6, 0.25], "at 100 %, 60 % and 25 %")
	var desktop := 0
	var web := 0
	for id: String in BATTLE:
		var enc := GameData.get_record(id)
		assert_true(bool(enc.get("arena", false)), "%s is an arena encounter" % id)
		var scale := float(enc.get("web_formation_scale", 1.0))
		var kept := {}
		for f: Dictionary in enc.get("formations", []):
			var slots: Array = []
			for sp: Dictionary in enc.spawns:
				if str(sp.get("formation", "")) == str(f.id):
					slots.append(int(sp.slot))
			for s: Variant in FormationRules.web_kept_slots(slots, scale):
				kept["%s:%d" % [f.id, int(s)]] = true
		for sp: Dictionary in enc.spawns:
			var h := int(GameData.get_record(str(sp.definition)).get("health", 0))
			desktop += h
			if str(sp.get("formation", "")) == "" or kept.has("%s:%d" % [sp.formation, int(sp.slot)]):
				web += h
			assert_false(bool(sp.get("persist_death", true)), "%s comes back for a new attempt" % sp.entity_id)
	for e: Variant in arena.get("engines", []):
		var engine := _engines().get(str(e), {}) as Dictionary
		var h := int(GameData.get_record("prop.siege_" + str(engine.get("style", "ballista"))).get("health", 0))
		desktop += h
		web += h
	print("    aldmere content: the Iron Regiment's aggregate %d on desktop, %d on the web" % [desktop, web])
	assert_true(desktop >= 13000 and desktop <= 14500, "about 13,700 on desktop (%d)" % desktop)
	assert_true(web >= 11000 and web < desktop, "less on the web composition (%d)" % web)
	var guard := GameData.get_record(BATTLE[2])
	var corvane := (guard.spawns as Array).filter(func(s: Dictionary) -> bool: return str(s.entity_id) == "world.aldmere.corvane")
	assert_eq(corvane.size(), 1, "Corvane stands with his guard")
	assert_eq(str(arena.get("commander_id", "")), "world.aldmere.corvane", "the battle's commander yields")
	# M8 gate (F8): the battle's arena is the bailey inside the curtain wall, corners and all.
	var walls := _element("world.aldmere.fort_walls")
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for pt: Variant in walls.get("points", []):
		lo = lo.min(Vector2(float(pt[0]), float(pt[1])))
		hi = hi.max(Vector2(float(pt[0]), float(pt[1])))
	var fl: Array = arena.get("floor", [])
	assert_eq(fl.size(), 2, "the arena has a floor rectangle")
	if fl.size() == 2:
		var a := Vector2(float(fl[0][0]), float(fl[0][1]))
		var b := Vector2(float(fl[1][0]), float(fl[1][1]))
		assert_true(a.min(b).is_equal_approx(lo) and a.max(b).is_equal_approx(hi),
			"its floor is the curtain wall's rectangle (%s %s, the wall %s %s)" % [a.min(b), a.max(b), lo, hi])
	# M8 gate (F9): the gate garrison outside the portcullis stands out when the battle engages.
	assert_eq(arena.get("stand_out", []), ["encounter.aldmere_fort_gate"], "the gate garrison stands out of the battle")
	# M8 gate (F16): the titan forges a deed opens shut while their settlement is hostile.
	assert_eq(str(_element("world.aldmere.fort_forge").get("faction", "")), "aldmere", "the fort forge is Aldmere's")
	assert_eq(str(_element("world.stonehold.skarn_forge").get("faction", "")), "skarn", "the hearth-forge is Skarn's")


func test_the_crowns_three_roads_and_the_parley_tokens() -> void:
	var roads := OathRules.first_oath_resolutions(CROWN, GameData.records)
	assert_eq(roads, PackedStringArray(["breach", "parley", "sabotage"]), "breach, parley and sabotage are each a first oath at stage 4")
	var herald := GameData.get_record("dialogue.herald")
	var tokens := {}
	for n: Dictionary in herald.nodes:
		for c: Dictionary in n.get("choices", []):
			var e: Dictionary = c.get("effects", {})
			if (e.get("set_flags", {}) as Dictionary).has("oath.crown.parley_accepted"):
				tokens[str((e.set_flags as Dictionary).get("oath.crown.token", ""))] = c
	assert_eq(tokens.keys().map(func(k: String) -> String: return k), ["banner", "deserters", "stoneblood", "stature"],
		"the four tokens: Brannock's banner, the deserters' word, Stoneblood blood, stage 5")
	for k: String in tokens:
		var c: Dictionary = tokens[k]
		assert_true(str(c.get("locked_text", "")) != "", "the %s token is greyed with its reason" % k)
		var ctx := QuestConditions.empty_context()
		ctx.stage = 4
		assert_false(QuestConditions.all_hold(c.get("conditions", []), ctx), "the %s token is not had for free" % k)
	var ctx4 := QuestConditions.empty_context()
	ctx4.stage = 4
	ctx4.flags = {"oath.crown.token_deserters": true}
	assert_true(QuestConditions.all_hold((tokens.deserters as Dictionary).conditions, ctx4), "the deserters' word at stage 4")
	ctx4.ancestry = "ancestry.stoneblood"
	assert_true(QuestConditions.all_hold((tokens.stoneblood as Dictionary).conditions, ctx4), "Stoneblood blood at stage 4")
	ctx4.stage = 5
	assert_true(QuestConditions.all_hold((tokens.stature as Dictionary).conditions, ctx4), "the stature of stage 5")
	# the deserters' word is open to a stage-4 giant, and sparing them gives it
	var spared := WorldItems.choice_items("dialogue.deserters", "spare")
	assert_eq(WorldItems.count(spared, WorldItems.IRON), 1, "sparing the deserters: 1 iron from their pay chest")
	assert_eq(WorldItems.count(WorldItems.choice_items("dialogue.deserters", "hand_over"), WorldItems.IRON), 2,
		"handing them over: 2 iron")
	# the crown's oath: meeting the herald, then the resolution's 750 on every road
	var oath := GameData.get_record(CROWN)
	assert_eq((oath.stages as Array).map(func(s: Dictionary) -> int: return int(s.xp)), [50, 750], "50 and 750 XP")
	assert_eq(int((oath.stages[1] as Dictionary).get("xp_floor_level", 0)), WorldXp.growth_level("growth.05"),
		"the resolution lifts the XP to stage 5's level")


func test_the_factions_the_siege_and_the_wander_tables() -> void:
	var skarn := GameData.get_record("faction.skarn")
	assert_eq(str(skarn.get("initial", "")), "neutral", "Skarn is at peace")
	assert_eq(WorldItems.choice_items("dialogue.ulfra", "reconcile_skarn"), {WorldItems.IRON: -2}, "Ulfra takes 2 iron for harm done")
	assert_eq(str(GameData.get_record("faction.harrok_clan").get("initial", "")), "hostile", "Harrok's clan is hostile")
	var ev := GameData.get_record("event.siege_of_skarn")
	assert_eq(str(ev.get("success_outcome", "")), "saved", "saved")
	assert_eq(str(ev.get("fail_outcome", "")), "burned", "burned")
	assert_eq((ev.objective.targets as Array).size(), 3, "three longhouses to protect")
	for t: Variant in ev.objective.targets:
		assert_true(LONGHOUSES.has(str(t)), "the siege threatens %s, a longhouse of Skarn" % t)
	assert_eq(int(ev.objective.lost_to_fail), 2, "two lost burn Skarn")
	assert_eq(int(ev.trigger.min_stage), 5, "from stage 5")
	var c5 := QuestConditions.empty_context()
	c5.stage = 5
	assert_false(QuestConditions.all_hold(ev.trigger.conditions, c5), "not at stage 5 without Ulfra's plea")
	c5.flags = {"world.skarn.plea_accepted": true}
	assert_true(QuestConditions.all_hold(ev.trigger.conditions, c5), "Ulfra's plea starts it at stage 5")
	var c6 := QuestConditions.empty_context()
	c6.stage = 6
	assert_true(QuestConditions.all_hold(ev.trigger.conditions, c6), "a stage-6 giant arriving starts it")
	var siege := 0
	for el: Dictionary in WorldContent.elements_of("engine"):
		if str(el.get("siege_group", "")) != "":
			siege += 1
			assert_eq(float(el.get("bombard_within_m", 0.0)), 200.0, "%s pauses beyond 200 m" % el.id)
			assert_eq((el.get("appears_when", {}) as Dictionary).get("flag", ""), "event.siege_of_skarn.runs",
				"%s appears with the siege" % el.id)
			for t: Variant in el.get("prop_targets", []):
				assert_true(LONGHOUSES.has(str(t)), "%s bombards Skarn's longhouses (%s)" % [el.id, t])
	assert_eq(siege, 5, "the siege line's five engines (3 catapults, 2 ballistae)")
	for id: String in LONGHOUSES:
		var lh := _element(id)
		assert_eq(str(lh.get("kind", "")), "longhouse", "%s is a longhouse that burns" % id)
		assert_true((lh.get("prop_tags", []) as Array).has("house"), "%s is tagged house" % id)
		assert_eq(str(lh.get("faction", "")), "skarn", "%s is Skarn's" % id)
		assert_eq(str(lh.get("rebuilt_flag", "")), "%s.rebuilt" % id.replace("world.stonehold.skarn_", "world.skarn."),
			"%s can be raised again" % id)
	for table: String in ["wander.aldmere", "wander.stonehold"]:
		var rec := GameData.get_record(table)
		assert_eq(int(rec.get("max_active", 0)), 2, "%s: two at once" % table)
		for e: Dictionary in rec.entries:
			var tpl := GameData.get_record(str(e.template))
			assert_true(bool(tpl.get("template", false)), "%s: %s is a template" % [table, e.template])


func test_the_battery_the_moot_and_the_main_threads_end() -> void:
	var battery := GameData.get_record("encounter.stonehold_moot_battery")
	for sp: Dictionary in battery.spawns:
		assert_eq(int(sp.get("min_stage", 0)), 6, "%s musters for a stage-6 giant" % sp.entity_id)
	assert_eq((battery.engines as Array).size(), 4, "the battery's two catapults and two ballistae")
	var moot := GameData.get_record("encounter.stonehold_moot")
	assert_true(bool(moot.get("arena", false)), "Harrok's duel is an arena")
	assert_true((moot.forbids_flags as Array).has("boss.harrok.outcome"), "a settled champion never comes back")
	var main := GameData.get_record(MAIN)
	var ids := (main.stages as Array).map(func(s: Dictionary) -> String: return str(s.id))
	assert_eq(ids, ["kings_door", "beacon", "grow4", "oaths", "grow6", "moot", "champion", "throne"], "the main thread's eight stages")
	assert_eq([WorldXp.stages_xp(MAIN, ["grow6"]), WorldXp.stages_xp(MAIN, ["moot"]), WorldXp.stages_xp(MAIN, ["champion"]),
		WorldXp.stages_xp(MAIN, ["throne"])], [100, 100, 300, 200], "grow6 100, moot 100, champion 300, throne 200")
	assert_eq(main.get("on_complete_flags", {}), {"campaign.completed": true}, "the campaign's end")
	for s: Dictionary in main.stages:
		for m: String in Quests.stage_markers(s):
			if not m.begins_with("valley."):
				assert_true(WorldXp.position_of(m).is_finite(), "%s: marker %s is in the world" % [s.id, m])
	var throne := _element("world.stonehold.stone_throne")
	assert_eq(str(throne.get("kind", "")), "throne", "the Stone Throne ends the campaign")
	assert_true(WorldContent.index().props.has("world.stonehold.stone_throne"), "the throne is in the index")
	# checkpoints outside the arenas within 80 m of their edge (M8 gate, F8: an enclosure's edge is its floor
	# rectangle's, beyond the disengage rule's 20 m too, so a giant waiting at the checkpoint has left the fight)
	for pair: Array in [["world.aldmere.iron_regiment_arena", "world.cp.fort_gate"], ["world.stonehold.moot_arena", "world.cp.moot_foot"]]:
		var a := _element(str(pair[0]))
		var centre := Vector2(float(a.pos[0]), float(a.pos[1]))
		var cp := WorldXp.position_of(str(pair[1]))
		var d := Vector2(cp.x, cp.z).distance_to(centre) - float(a.inner_radius)
		var fl: Array = a.get("floor", [])
		if fl.size() == 2:
			var r := Rect2(Vector2(float(fl[0][0]), float(fl[0][1])), Vector2.ZERO).expand(Vector2(float(fl[1][0]), float(fl[1][1])))
			var dx := maxf(maxf(r.position.x - cp.x, 0.0), cp.x - r.end.x)
			var dz := maxf(maxf(r.position.y - cp.z, 0.0), cp.z - r.end.y)
			d = Vector2(dx, dz).length()
			assert_true(d > BossArena.DISENGAGE_MARGIN_M, "%s lies beyond %s's disengage line (%.1f m)" % [pair[1], pair[0], d])
		assert_true(d > 0.0 and d <= CHECKPOINT_M, "%s lies outside %s within 80 m of its edge (%.1f m)" % [pair[1], pair[0], d])
	for r: String in ["region.aldmere", "region.stonehold"]:
		assert_eq(str(GameData.get_record(r).get("m7_note", "")), "", "%s no longer waits for its package" % r)


func test_the_toll_forts_stage_5_tower_ballista() -> void:
	var el := _element("world.crownmarch.toll_ballista")
	assert_eq(str(el.get("kind", "")), "engine", "the tower ballista is placed")
	var when: Dictionary = el.get("appears_when", {})
	assert_eq([str(when.get("type", "")), int(when.get("stage", 0))], ["stage_at_least", 5], "it is mounted for a stage-5 giant")
	var fort := GameData.get_record("encounter.crownmarch_toll_fort")
	var crewed := (fort.get("engines", []) as Array).filter(func(e: Dictionary) -> bool: return str(e.engine) == "world.crownmarch.toll_ballista")
	assert_eq(crewed.size(), 1, "the toll fort's encounter crews it")
	for sp: Dictionary in fort.spawns:
		if (crewed[0].crew as Array).has(str(sp.entity_id)):
			assert_eq(int(sp.get("min_stage", 0)), 5, "its crew comes at stage 5")
