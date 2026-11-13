extends TestSuite
## The Crownmarch's content (P29; plan M6-M9 §3.12, §5.4, §5.7, §5.9, §5.10), from the records, the
## world's index and layout tables (WorldContent, WorldXp) and a few nodes made in code:
##   * every Crownmarch quest stage completes: each condition it waits for can hold (a witness
##     context makes it hold) and every flag it reads is written by something - a record, the
##     world's encounters, factions, beacons or breakable sites;
##   * the main thread's oaths stage names the three powers' meeting places, all in the world's
##     index, and while Brannock's oath is tracked they are the compass's three leads; the march
##     oath starts at stage 4 (not 3);
##   * every encounter has a leash (at most 70 m) holding its spawns, and its chunk; every set of
##     encounters within 150 m of each other fields at most 12 individual combatants at any stage
##     (a settlement's guards included, as when the town is hostile; formation members apart), and
##     the formation caps hold on both platforms; the two formation fights (the toll fort's pikes,
##     the Raiders' Hollow's shield wall) form at stage 4; the M7 content rule's encounters;
##   * the near condition, the main quest following the world, a beacon fire, a town forge, the
##     shrines' growth conditions.
## Records and code-made nodes only: the default tier's budget.

const LEVEL := "level.world"
const QUESTS := ["quest.world_main", "quest.oath_march", "quest.sealed_citadel", "quest.kingsroad_toll",
	"quest.barrow_fields", "quest.millrace", "quest.watch_beacon"]
const LEADS := ["world.marker.brannock_green", "world.marker.hollowmere_green", "world.marker.war_camp_edge"]
const MAX_LEASH_M := 70.0
const CLUSTER_M := 150.0
const INDIVIDUALS := 12
## The formation fights a stage-4 giant meets (encounter -> formation).
const FORMATION_FIGHTS := {"encounter.crownmarch_toll_fort": "pikes", "encounter.crownmarch_raiders": "shields"}


func before_each() -> void:
	WorldState.clear()


func after_each() -> void:
	WorldState.clear()
	GameSession.mode = GameSession.Mode.SANDBOX
	GameSession.level_id = ""


func _crownmarch_encounters() -> Array:
	return WorldContent.encounters().filter(func(r: Dictionary) -> bool: return str(r.id).begins_with("encounter.crownmarch_"))


static func _xz(a: Variant) -> Vector2:
	return Vector2(float(a[0]), float(a[2]))


# --------------------------------------------------------------------------- quests

## Changes `ctx` so that the condition `c` holds (a witness): flags written, stage raised, the level,
## a destruction, an item, the giant beside a near target. "not" is left as it is.
func _witness(c: Variant, ctx: Dictionary) -> void:
	if typeof(c) != TYPE_DICTIONARY:
		return
	var d: Dictionary = c
	var flags: Dictionary = ctx.flags
	match str(d.get("type", "")):
		"flag":
			flags[str(d.flag)] = d.get("equals", true)
		"stage_at_least":
			ctx.stage = maxi(int(ctx.stage), int(d.stage))
		"level_at_least":
			ctx.level = maxi(int(ctx.level), int(d.level))
		"level_is":
			ctx.level_id = str(d.level)
		"encounter_cleared":
			flags[QuestConditions.encounter_flag(str(d.encounter))] = true
		"destroyed":
			(ctx.destroyed as Dictionary)[str(d.world_id)] = true
		"has_item":
			(ctx.inventory as Dictionary)[str(d.item)] = int(d.get("count", 1))
		"dialogue_outcome":
			flags[QuestConditions.outcome_flag(str(d.dialogue), str(d.outcome))] = true
		"quest_done":
			flags[str(d.quest) + ".done"] = true
		"discovered":
			flags["discovered." + QuestConditions.short_of(str(d.poi))] = true
		"entered":
			(ctx.entered as Dictionary)[str(d.area)] = true
		"near":
			var at := WorldXp.position_of(str(d.target))
			(ctx.positions as Dictionary)[str(d.target)] = at
			ctx.position = at
		"all":
			for sub: Variant in d.get("of", []):
				_witness(sub, ctx)
		"any":
			_witness((d.get("of", []) as Array).front(), ctx)
		"count":
			var of: Array = d.get("of", [])
			for i in mini(int(d.get("n", 1)), of.size()):
				_witness(of[i], ctx)


## [flag, where] of every flag test in `c`.
func _flags_read(c: Variant, out: Array) -> void:
	if typeof(c) == TYPE_ARRAY:
		for x: Variant in c:
			_flags_read(x, out)
	elif typeof(c) == TYPE_DICTIONARY:
		if str(c.get("type", "")) == "flag":
			out.append(str(c.flag))
		_flags_read(c.get("of"), out)


func test_every_crownmarch_quest_stage_can_complete_and_reads_written_flags() -> void:
	var written := OathRules.flag_writers(GameData.records)
	written.merge(WorldContent.written_flags())
	for q: Dictionary in GameData.records_of_type("quest"):
		written.merge(q.get("on_complete_flags", {}) as Dictionary)   # slice.completed: quest.main's
	var later := {}   # the oaths M8 adds (P35, P36): their done flags have no writer yet
	for qid: String in QUESTS:
		var rec := GameData.get_record(qid)
		assert_eq(str(rec.get("type", "")), "quest", "%s ships" % qid)
		var start := QuestConditions.empty_context()
		start["positions"] = {}
		for c: Variant in rec.get("start_conditions", []):
			_witness(c, start)
		assert_true(QuestConditions.all_hold(rec.get("start_conditions", []), start), "%s can start" % qid)
		for s: Dictionary in rec.get("stages", []):
			var where := "%s.%s" % [qid, s.id]
			var ctx := QuestConditions.empty_context()
			ctx["positions"] = {}
			_witness(s.complete_when, ctx)
			assert_true(QuestConditions.holds(s.complete_when, ctx), "%s can complete" % where)
			var read: Array = []
			_flags_read(s.complete_when, read)
			_flags_read(rec.get("start_conditions", []), read)
			for f: String in read:
				var engine := f.begins_with("quest.") or f.begins_with("discovered.") or f.begins_with("region.")
				var key := f.get_slice(".", 1) if f.begins_with("oath.") else ""
				if key != "" and not GameData.has_record("quest.oath_" + key):
					later[f] = where
					continue
				assert_true(written.has(f) or engine, "%s reads %s, which something writes" % [where, f])
			for m: String in Quests.stage_markers(s):
				var idx := WorldIndex.for_level("level.valley" if m.begins_with("valley.") else LEVEL)
				assert_true(idx != null and idx.position_of(m).is_finite(), "%s: marker %s is in its level's index" % [where, m])
	# M7: only Brannock's oath ships, so the oaths stage (two of three) waits for P35's and P36's; M8:
	# the wood's (P35) and the crown's (P36) are read before they ship only while their records are
	# missing - once both have merged (W21), no oath is read before it ships.
	var unshipped := ["wood", "crown"].filter(func(k: String) -> bool: return not GameData.has_record("quest.oath_" + k))
	assert_eq(later.keys().map(func(f: String) -> String: return f.get_slice(".", 1)), unshipped,
		"only the oaths not shipped yet are read before they ship (%s)" % [later])


func test_the_oaths_stage_leads_to_the_three_powers_and_the_march_opens_at_stage_4() -> void:
	var oaths := WorldXp.stage("quest.world_main", "oaths")
	assert_eq(Array(Quests.stage_markers(oaths)), LEADS, "the oaths stage names the three powers' meeting places")
	for m: String in LEADS:
		assert_true(WorldXp.position_of(m).is_finite(), "%s is in the world's index" % m)
	var starts: Array = GameData.get_record("quest.oath_march").get("start_conditions", [])
	var ctx := QuestConditions.empty_context()
	ctx.stage = 3
	assert_false(QuestConditions.all_hold(starts, ctx), "Brannock's oath waits for stage 4")
	ctx.stage = 4
	assert_true(QuestConditions.all_hold(starts, ctx), "and starts at stage 4")
	# The compass: the main quest at its oaths stage, Brannock's oath tracked -> three leads.
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = LEVEL
	Quests.test_active = true
	Quests.scope = PackedStringArray(["quest.world_main", "quest.oath_march"])
	Quests.main_quest_id = "quest.world_main"
	WorldState.set_flag(Quests.stage_flag("quest.world_main"), "oaths")
	WorldState.set_flag(Quests.stage_flag("quest.oath_march"), "meet")
	assert_true(Quests.track("quest.oath_march"), "Brannock's oath can be tracked")
	var leads: Array = Quests.leads()
	assert_eq(leads.map(func(l: Dictionary) -> String: return str(l.marker_id)), LEADS, "the compass's three leads")
	var objective: Dictionary = Quests.objective_for("quest.world_main")
	assert_eq((objective.get("markers", []) as PackedStringArray).size(), 3, "the map's three oath markers")


## The oath each of the oaths stage's leads belongs to (M7 polish).
const LEAD_OATHS := {"world.marker.brannock_green": "oath.march.done", "world.marker.hollowmere_green": "oath.wood.done",
	"world.marker.war_camp_edge": "oath.crown.done"}


func test_a_won_oath_drops_its_lead_in_every_order() -> void:
	# The M7 gate review: once Brannock's oath was won (oath.march.done) the oaths stage still pointed
	# at Brannock's green - objective_for took the nearest of all three markers, so a giant at
	# world.cp.brannock got (60, 10.2, 568) - and the compass kept its lead.
	var oaths := WorldXp.stage("quest.world_main", "oaths")
	var done_when: Dictionary = oaths.get("markers_done_when", {})
	for m: String in LEAD_OATHS:
		assert_eq(done_when.get(m, {}), {"type": "flag", "flag": LEAD_OATHS[m]}, "%s is done with %s" % [m, LEAD_OATHS[m]])
	GameSession.mode = GameSession.Mode.VALLEY
	GameSession.level_id = LEVEL
	Quests.test_active = true
	Quests.scope = PackedStringArray(["quest.world_main", "quest.oath_march"])
	Quests.main_quest_id = "quest.world_main"
	for won: String in LEAD_OATHS.values():
		WorldState.clear()
		WorldState.set_flag(Quests.stage_flag("quest.world_main"), "oaths")
		WorldState.set_flag(Quests.stage_flag("quest.oath_march"), "meet")
		WorldState.set_flag(won, true)
		var open: Array = LEADS.filter(func(m: String) -> bool: return LEAD_OATHS[m] != won)
		var objective: Dictionary = Quests.objective_for("quest.world_main")
		assert_eq(Array(objective.get("markers", PackedStringArray())), open, "%s: the other two leads stay" % won)
		assert_eq((objective.get("positions", []) as Array).size(), 2, "%s: two diamonds on the compass and the map" % won)
		var gone := WorldXp.position_of(LEADS.filter(func(m: String) -> bool: return LEAD_OATHS[m] == won)[0])
		assert_false((objective.position as Vector3).is_equal_approx(gone), "%s: the objective no longer points at its lead" % won)
		for p: Vector3 in objective.get("positions", []):
			assert_false(p.is_equal_approx(gone), "%s: no diamond at its lead" % won)
		assert_true(Quests.track("quest.oath_march"), "%s: another quest tracked" % won)
		assert_eq(Quests.leads().map(func(l: Dictionary) -> String: return str(l.marker_id)), open,
			"%s: the compass's leads are the two oaths still open" % won)
		Quests.tracked_quest_id = ""
	# Every stage that counts the oaths' done flags drops each lead with its own oath (OathRules, run
	# by GameData's post-pass): the shipped records pass; a lead without its condition fails.
	assert_eq(OathRules.lead_errors(GameData.records), PackedStringArray(), "the shipped oaths stage keeps its leads right")
	var records := GameData.records.duplicate()
	var main: Dictionary = (records["quest.world_main"] as Dictionary).duplicate(true)
	for s: Dictionary in main.stages:
		if str(s.id) == "oaths":
			(s.markers_done_when as Dictionary).erase("world.marker.war_camp_edge")
	records["quest.world_main"] = main
	var errors := OathRules.lead_errors(records)
	assert_eq(errors.size(), 1, "a lead that outlives its oath is an error: %s" % [errors])
	assert_true(errors.size() == 1 and errors[0].contains("world.marker.war_camp_edge") and errors[0].contains("oath.crown.done"),
		"naming the lead and the oath it belongs to: %s" % [errors])


func test_the_main_quest_follows_the_world_once_the_valley_is_done() -> void:
	assert_eq(Quests.p29_main_for(Quests.ACTIVE, Quests.INACTIVE), "quest.main", "the Valley's quest while it runs")
	assert_eq(Quests.p29_main_for(Quests.ACTIVE, Quests.ACTIVE), "quest.main", "even with the world's started")
	assert_eq(Quests.p29_main_for(Quests.COMPLETED, Quests.INACTIVE), "quest.main", "until the world's starts")
	assert_eq(Quests.p29_main_for(Quests.COMPLETED, Quests.ACTIVE), "quest.world_main", "then the world's")
	assert_eq(Quests.p29_main_for(Quests.INACTIVE, Quests.ACTIVE), "quest.world_main", "and from world_start")
	var start: Array = GameData.get_record("quest.world_main").get("start_conditions", [])
	var flags := {}
	for f: String in (Progression.record().world_start as Dictionary).flags:
		flags[f] = true
	var ctx := QuestConditions.empty_context()
	ctx.flags = flags
	assert_true(QuestConditions.all_hold(start, ctx), "world_start's flags start the world's main quest")


# --------------------------------------------------------------------------- encounters

## Individual combatants of `enc` at `stage`: enemy spawns outside formations its stage admits.
func _individuals(enc: Dictionary, stage: int) -> int:
	var n := 0
	for sp: Dictionary in enc.spawns:
		if str(sp.get("formation", "")) != "" or not FormationRules.stage_allows(sp, stage):
			continue
		if str(GameData.get_record(str(sp.definition)).get("type", "")) == "enemy":
			n += 1
	return n


## Every set of encounters pairwise within CLUSTER_M of each other that contains `encs[i]` and only
## later ones (each clique found once): arrays of indices.
func _cliques(encs: Array, chosen: Array, start: int, out: Array) -> void:
	out.append(chosen.duplicate())
	for j in range(start, encs.size()):
		var ok := true
		for k: int in chosen:
			if _xz(encs[k].center_m).distance_to(_xz(encs[j].center_m)) > CLUSTER_M:
				ok = false
				break
		if ok:
			chosen.append(j)
			_cliques(encs, chosen, j + 1, out)
			chosen.pop_back()


func test_every_encounter_keeps_its_leash_chunk_and_the_budgets() -> void:
	var encs := _crownmarch_encounters()
	assert_true(encs.size() >= 9, "the Crownmarch's nine encounters (%d)" % encs.size())
	var idx := WorldContent.index()
	for enc: Dictionary in encs:
		var id := str(enc.id)
		var leash := float(enc.get("leash_radius_m", 0.0))
		assert_true(leash > 0.0 and leash <= MAX_LEASH_M, "%s has a leash of at most 70 m (%s)" % [id, leash])
		assert_true(str(idx.encounters.get(id, {}).get("chunk", "")) != "", "%s has its chunk in the index" % id)
		for sp: Dictionary in enc.spawns:
			assert_true(_xz(sp.position_m).distance_to(_xz(enc.center_m)) <= leash, "%s starts inside %s's leash" % [sp.entity_id, id])
			assert_true(str(sp.entity_id).begins_with("world.crownmarch."), "%s is a Crownmarch world id" % sp.entity_id)
			assert_false(GameData.get_record(str(sp.definition)).is_empty(), "%s's %s exists" % [sp.entity_id, sp.definition])
	var cliques: Array = []
	_cliques(encs, [], 0, cliques)
	var worst := 0
	for stage in range(1, FormationRules.STAGES + 1):
		for clique: Array in cliques:
			var n := 0
			for i: int in clique:
				n += _individuals(encs[i], stage)
			worst = maxi(worst, n)
			assert_true(n <= INDIVIDUALS, "at stage %d the encounters %s field %d individuals" % [
				stage, clique.map(func(i: int) -> String: return str(encs[i].id)), n])
	print("    crownmarch: at most %d individual combatants within %d m of each other" % [worst, int(CLUSTER_M)])
	var records := {}
	for enc: Dictionary in encs:
		records[str(enc.id)] = enc
	records[LEVEL] = GameData.get_record(LEVEL)
	for id: String in ["enemy.pikeman", "enemy.shieldman", "enemy.bannerman"]:
		records[id] = GameData.get_record(id)
	assert_eq(FormationRules.cross_record_errors(records), PackedStringArray(), "the formation caps hold on both platforms")
	for id: String in FORMATION_FIGHTS:
		var enc := GameData.get_record(id)
		var f: Array = (enc.formations as Array).filter(func(x: Dictionary) -> bool: return str(x.id) == FORMATION_FIGHTS[id])
		assert_eq(f.size(), 1, "%s fields its %s" % [id, FORMATION_FIGHTS[id]])
		assert_eq(int(f[0].get("min_stage", 0)), 4, "%s's %s form at stage 4" % [id, FORMATION_FIGHTS[id]])
		var counts: Array = FormationRules.member_counts(enc, 4)
		assert_true(int(counts[0]) >= 8 and int(counts[1]) >= 1, "%s's formation at stage 4: %s (desktop, web)" % [id, counts])
		assert_eq(FormationRules.member_counts(enc, 3), [0, 0], "and not at stage 3")


func test_the_crownmarch_meets_the_m7_content_rule() -> void:
	var fights := 0
	for enc: Dictionary in _crownmarch_encounters():
		if _individuals(enc, 3) > 0 and bool(enc.get("counts_toward_budget", true)):
			fights += 1
	assert_true(fights >= 2, "the Crownmarch has at least two encounters of existing archetypes (%d)" % fights)
	var factions := {}
	for enc: Dictionary in _crownmarch_encounters():
		for sp: Dictionary in enc.spawns:
			if str(sp.get("faction", "")) != "":
				factions[str(sp.faction)] = true
	for f: String in ["brannock", "millford", "toll_riders"]:
		assert_true(factions.has(f), "%s's people are in the Crownmarch's encounters" % f)
		assert_false(GameData.get_record("faction." + f).is_empty(), "faction.%s ships" % f)
	assert_false(GameData.get_record("faction.aldmere").is_empty(), "Aldmere's faction ships apart from the toll-riders")


# --------------------------------------------------------------------------- the near condition

func test_near_holds_within_its_radius_of_a_known_target() -> void:
	var ctx := QuestConditions.empty_context()
	ctx["positions"] = {"world.marker.test": Vector3(100, 40, 0)}
	var near := {"type": "near", "target": "world.marker.test", "radius_m": 50}
	assert_false(QuestConditions.holds(near, ctx), "no position: never")
	ctx.position = Vector3(140, 0, 0)
	assert_true(QuestConditions.holds(near, ctx), "40 m away (heights ignored)")
	ctx.position = Vector3(100, 0, 60)
	assert_false(QuestConditions.holds(near, ctx), "60 m away")
	assert_true(QuestConditions.holds({"type": "near", "target": "world.marker.test"}, ctx), "the default radius is 150 m")
	assert_false(QuestConditions.holds({"type": "near", "target": "world.marker.unknown"}, ctx), "an unknown target never")
	ctx.erase("positions")
	ctx.position = Vector3(110, 0, 0)
	ctx["position_of"] = func(id: String) -> Vector3: return Vector3(100, 0, 0) if id == "world.marker.test" else Vector3.INF
	assert_true(QuestConditions.holds(near, ctx), "position_of answers when positions does not")
	assert_true(Quests.condition_context().has("position_of"), "the live context gives the lookup")


# --------------------------------------------------------------------------- the beacon, the forge, the shrines

func test_a_beacon_fire_lights_once_after_its_hill_is_cleared() -> void:
	var fire := BeaconFire.new()
	fire.world_id = "world.test.beacon_fire"
	fire.lit_flag = "test.p29.beacon_lit"
	fire.requires_flags = PackedStringArray(["test.p29.hill_cleared"])
	fire.loot_table = "loot.beacon_cache"
	fire.scene_dialogue = "dialogue.kingsgate_beacon"
	var flames := Node3D.new()
	flames.name = "Fire"
	fire.add_child(flames)
	var dialogues: Array = []
	var on_dialogue := func(speaker: String, dialogue: String) -> void: dialogues.append([speaker, dialogue])
	Events.dialogue_requested.connect(on_dialogue)
	add_child(fire)
	assert_false(flames.visible, "no flames before it is lit")
	assert_false(fire.can_interact(null), "the hill is not yet cleared")
	assert_eq(fire.blocked_reason(null), fire.locked_message, "and E says so")
	assert_false(fire.light(), "it cannot be lit yet")
	WorldState.set_flag("test.p29.hill_cleared", true)
	assert_true(fire.can_interact(null), "cleared: it can be lit")
	assert_true(fire.light(), "lit")
	assert_true(flames.visible and fire.is_lit(), "the flames show")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.TITAN_IRON), 1, "its cache pays titan iron")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), 2, "and iron")
	assert_eq(dialogues, [["world.test.beacon_fire", "dialogue.kingsgate_beacon"]], "its short scene plays")
	assert_false(fire.light(), "once")
	assert_false(fire.can_interact(null), "a lit beacon offers nothing")
	WorldState.set_flag("test.p29.beacon_lit", false)
	assert_false(flames.visible, "the flames follow the flag from any writer")
	assert_true(fire.light(), "relit")
	assert_eq(WorldItems.count(WorldState.inventory, WorldItems.IRON), 2, "but the cache pays once")
	Events.dialogue_requested.disconnect(on_dialogue)
	fire.queue_free()
	assert_eq(fire.is_in_group(BeaconFire.GROUP), true, "beacons are grouped")


func test_a_town_forge_shuts_while_its_town_is_hostile() -> void:
	var forge := TownForge.new()
	forge.faction = "brannock"
	assert_true(forge.is_open(), "open while Brannock is at peace")
	WorldState.set_flag(FactionState.flag_id("brannock", "hostile"), true)
	assert_false(forge.is_open(), "shut while it is hostile")
	assert_eq(forge.blocked_reason(null), forge.hostile_message, "and says why")
	WorldState.set_flag(FactionState.flag_id("brannock", "reconciled"), true)
	assert_true(forge.is_open(), "open again once reconciled")
	forge.requires_flags = PackedStringArray(["test.p29.never"])
	assert_false(forge.is_open(), "and still a Forge: its own flags")
	forge.free()
	var forges := WorldContent.elements_of("forge_site").filter(func(el: Dictionary) -> bool: return str(el.get("style", "")) == "town")
	assert_eq(forges.map(func(el: Dictionary) -> String: return str(el.faction)), ["brannock"], "Brannock's smithy is the town forge")


func test_the_shrines_wait_for_the_beacon_and_the_oaths() -> void:
	var expect := {"shrine.world_kingsgate": ["flag", 0], "shrine.world_greywood": ["count", 1],
		"shrine.world_steps": ["count", 1], "shrine.world_aldmere": ["count", 1], "shrine.world_stones": ["count", 2]}
	for id: String in expect:
		var conds: Array = GameData.get_record(id).get("growth_requires_conditions", [])
		assert_eq(conds.size(), 1, "%s has its growth condition" % id)
		if conds.is_empty():
			continue
		var c: Dictionary = conds[0]
		assert_eq(str(c.type), str(expect[id][0]), "%s: %s" % [id, c])
		if str(c.type) == "count":
			assert_eq(int(c.n), int(expect[id][1]), "%s needs %d oaths" % [id, expect[id][1]])
			var of: Array = c.of
			assert_eq(of.map(func(x: Dictionary) -> String: return str(x.flag)),
				["oath.march.done", "oath.wood.done", "oath.crown.done"], "%s counts the three oaths" % id)
		else:
			assert_eq(str(c.flag), "world.kingsgate.lit", "Kingsgate waits for its beacon")
		assert_false((GameData.get_record(id).get("growth_conditions_text", []) as Array).is_empty(), "%s says what it waits for" % id)


## W23 (P39f; plan §5.10, FOLLOWUPS "From P37"): after the raid on Millford the reeve's words change - its
## outcome flags (event.millford_raid's `fell` and `defended`) open her own greeting, a burned Millford first
## (two houses stay burned), and both lead on to her troubles; hostile, she still sends the giant away.
func test_the_reeve_speaks_of_the_raid() -> void:
	var rec := GameData.get_record("dialogue.reeve_tamsin")
	var raid := GameData.get_record("event.millford_raid")
	var outcome_flags := {}
	for outcome: String in ["fell", "defended"]:
		for f: String in (((raid.get("outcomes", {}) as Dictionary).get(outcome, {}) as Dictionary).get("set_flags", {}) as Dictionary):
			outcome_flags[outcome] = f
	assert_eq(outcome_flags, {"fell": "world.millford.burned", "defended": "world.millford.defended"},
		"the raid's outcomes write the flags her greeting reads")
	var start := func(flags: Dictionary) -> String:
		var ctx := QuestConditions.empty_context()
		ctx.flags = flags
		return DialogueSession.start_node(rec, ctx)
	assert_eq(start.call({}), "greet", "before any raid: her greeting")
	assert_eq(start.call({"world.millford.burned": true}), "burned", "the raid fell: the houses lost")
	assert_eq(start.call({"world.millford.defended": true}), "defended", "the raid was beaten off: her thanks")
	assert_eq(start.call({"world.millford.defended": true, "world.millford.burned": true}), "burned",
		"defended once and burned the second time: the burned houses come first")
	assert_eq(start.call({"world.millford.defended": true, "quest.millrace.done": true}), "defended",
		"the raid is newer news than the mill")
	assert_eq(start.call({"world.millford.burned": true, "faction.millford.hostile": true}), "hostile",
		"hostile, she still sends the giant away")
	assert_eq(start.call({"world.millford.burned": true, "faction.millford.hostile": true, "faction.millford.reconciled": true}),
		"burned", "reconciled, the raid again")
	# M9 gate (lane review): the raid is defended while fewer than lost_to_fail of its houses fall, and a fallen
	# house stays burned (a destroyed prop, saved) - her thanks said every house still had its roof over the ashes.
	# With a house of the raid's objective destroyed she speaks of the losses; the houses she counts are the raid's.
	var objective: Dictionary = raid.get("objective", {})
	var houses: Array = objective.get("targets", [])
	assert_true(int(objective.get("lost_to_fail", 0)) >= 2 and houses.size() >= 3,
		"a defended raid may lose up to %d of its %d houses" % [int(objective.get("lost_to_fail", 0)) - 1, houses.size()])
	var counted: Array = []
	for entry: Dictionary in rec.get("entries", []):
		if str(entry.get("node", "")) == "defended_losses":
			counted = _destroyed_ids(entry.get("conditions", []))
	counted.sort()
	var expected := houses.duplicate()
	expected.sort()
	assert_eq(counted, expected, "the losses she counts are the raid's protected houses")
	var after := func(flags: Dictionary, burned: Array) -> String:
		var ctx := QuestConditions.empty_context()
		ctx.flags = flags
		var deltas := {}
		for h: Variant in burned:
			deltas[str(h)] = {"destroyed": true, "damage_stage": 1}
		ctx.deltas = deltas
		return DialogueSession.start_node(rec, ctx)
	var defended := {"world.millford.defended": true}
	for h: Variant in houses:
		assert_eq(after.call(defended, [h]), "defended_losses", "defended, %s burned: she speaks of the losses" % h)
	assert_eq(after.call(defended, houses.slice(0, int(objective.get("lost_to_fail", 0)) - 1)), "defended_losses",
		"defended with the most houses a defence may lose")
	assert_eq(after.call(defended, []), "defended", "defended with every house standing: every roof stands")
	assert_eq(after.call({"world.millford.defended": true, "world.millford.burned": true}, houses), "burned",
		"defended, then burned: the burned houses come first")
	assert_eq(after.call({"world.millford.defended": true, "faction.millford.hostile": true}, [houses[0]]), "hostile",
		"hostile, she still sends the giant away")
	assert_false(str(DialogueSession.node_record(rec, "defended_losses").get("text", "")).to_lower().contains("every house"),
		"the losses' words do not say every house stands")
	for id: String in ["burned", "defended", "defended_losses"]:
		var node := DialogueSession.node_record(rec, id)
		assert_true(str(node.get("text", "")).length() > 40, "%s has its words" % id)
		var nexts: Array = (node.get("choices", []) as Array).map(func(c: Dictionary) -> String: return str(c.get("next", "")))
		assert_true(nexts.has("troubles") and nexts.has(""), "%s leads on to her troubles and lets the giant go (%s)" % [id, nexts])


## The world ids of every destroyed condition in `conds` (any depth of all / any / not / count).
static func _destroyed_ids(conds: Variant) -> Array:
	var out: Array = []
	if typeof(conds) == TYPE_ARRAY:
		for c: Variant in conds:
			out.append_array(_destroyed_ids(c))
	elif typeof(conds) == TYPE_DICTIONARY:
		var d: Dictionary = conds
		if str(d.get("type", "")) == "destroyed":
			out.append(str(d.get("world_id", "")))
		out.append_array(_destroyed_ids(d.get("of", [])))
	return out


## W23 (P39f; FOLLOWUPS "From P36"): the toll fort's watchtower shows its archers. Its top is an open lookout -
## a deck whose top is the footing solid's, where the archers' posts stand, a railing at most 1 m high round its
## edge and the roof on corner posts - so no part of the tower covers either archer above the railing (the old
## closed cabin, 1.4 m tall on a deck 0.6 m over the footing, hid them to the shoulders).
func test_the_toll_watchtower_shows_its_archers() -> void:
	var tower_kind := load("res://tools/world/kinds/tower.gd")
	var table := WorldFeatures.load_json(WorldLayout.DATA_DIR.path_join("crownmarch.json"))
	var tower: Dictionary = {}
	for el: Dictionary in table.get("elements", []):
		if str(el.get("id", "")) == "world.crownmarch.toll_watchtower":
			tower = el
	assert_eq(str(tower.get("style", "")), "watch", "the toll fort's watchtower")
	if tower.is_empty():
		return
	var at := WorldLayout.pos2(tower)
	var h := float((tower.size as Array)[1])
	var solids: Array = tower_kind.call("solids", tower, {})
	var top := -INF
	for sd: Dictionary in solids:
		top = maxf(top, (sd.center as Vector3).y + (sd.size as Vector3).y * 0.5)
	assert_near(top, h, 0.01, "its footing solid's top is the deck (%.2f m)" % top)
	var archer := GameData.get_record("enemy.archer")
	var body_h := float(archer.get("height_m", 1.8))
	var body_r := float(archer.get("capsule_radius_m", 0.35))
	var posts: Array = []
	for m: Dictionary in table.get("markers", []):
		if str(m.get("id", "")).begins_with("world.marker.toll_tower_"):
			posts.append(m)
	assert_eq(posts.size(), 2, "its two archers' posts")
	var parts: Array = tower_kind.call("parts", tower, {})
	var deck_top := -INF
	for p: Dictionary in parts:
		var pos: Vector3 = p.pos
		var size: Vector3 = p.size
		if str(p.shape) == "box" and size.x > 4.0 and size.z > 4.0 and pos.y + size.y <= h + 0.01:
			deck_top = maxf(deck_top, pos.y + size.y)
	assert_near(deck_top, h, 0.01, "the deck's top is where the archers stand, not above their feet (%.2f m)" % deck_top)
	for m: Dictionary in posts:
		var local := WorldLayout.pos2(m) - at
		var feet := float(m.get("y_off", 0.0))
		assert_near(feet, h, 0.1, "%s stands on the deck" % m.id)
		var rail: Variant = tower_kind.get("WATCH_RAIL_TOP")
		var shown_from := feet + (float(rail) if rail != null else 1.0)
		var hidden: Array = []
		for p: Dictionary in parts:
			var pos: Vector3 = p.pos
			var size: Vector3 = p.size
			var lo := Vector3(pos.x - size.x * 0.5, pos.y, pos.z - size.z * 0.5)
			var hi := Vector3(pos.x + size.x * 0.5, pos.y + size.y, pos.z + size.z * 0.5)
			var across := local.x + body_r > lo.x and local.x - body_r < hi.x and local.y + body_r > lo.z and local.y - body_r < hi.z
			if across and hi.y > shown_from + 0.01 and lo.y < feet + body_h:
				hidden.append("%s %s from %.2f to %.2f m" % [p.shape, size, lo.y, hi.y])
		assert_eq(hidden, [], "no part of the tower covers %s above its railing (%.2f m)" % [m.id, shown_from])
