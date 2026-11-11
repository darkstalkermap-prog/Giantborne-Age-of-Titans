extends TestSuite
## The Greywood's and the Drowned Steps' content (P35; plan M6-M9 §3.19, §5.4, §5.5, §5.7, §5.10,
## §5.13), from the records, the world's index and the layout tables (WorldContent, WorldXp) and a few
## nodes made in code:
##   * the woodfolk's oath starts at stage 4 and both its resolutions (slay, drive) are open to a
##     first oath at stage 4: Sedge's report swears it, sets oath.wood.done, its outcome and the
##     woodfolk's alliance, and pays once; the drive's flags are the den's nests' and wall's; the
##     Stormborn bargain opens the wall; the scattered brood roams once she fled; Hollowmere's lights;
##   * every stage of the seven quests can complete, reads only flags something writes, and points
##     at indexed markers and known bot targets;
##   * every placed encounter is leashed (the den's arena boss by its arena), starts inside its
##     leash, has its chunk, and every set within 150 m fields at most 12 individuals at any stage;
##     a brazier or bonfire at every troll site and beside every brood nest; the den's checkpoint
##     lies outside its arena within 80 m;
##   * the wander tables are the plan's, their templates keep nothing, stand more than 120 m from
##     every checkpoint and pay a bounded kill XP;
##   * the Needle fits stages 3-4 and refuses 5, the Hidden Grove's second key is the north ridge's
##     stage-5 rockfall, the sealed places' stages and cairns;
##   * the five bells, the Titan Forge (titan tier, lit once the scavengers are gone) and its refit to
##     titanforged, the Stoneknuckles kept for the bell-ringer;
##   * Sedge on Hollowmere's green for a giant of stage 5-6 (the director's rule).
## Records, the index and code-made nodes only: the default tier's budget.

const LEVEL := "level.world"
const WOOD := "quest.oath_wood"
const QUESTS := ["quest.oath_wood", "quest.great_pine", "quest.woodcutters", "quest.the_needle",
	"quest.drowned_bells", "quest.titan_bones", "quest.sunken_vault"]
const MAX_LEASH_M := 70.0
const CLUSTER_M := 150.0
const INDIVIDUALS := 12
const TROLLS := ["enemy.troll", "enemy.troll_whelp", "enemy.troll_matriarch"]
const DEN_CP := "world.cp.troll_den"
const DEN_ARENA := "world.greywood.den_arena"
const MATRIARCH := "world.greywood.troll_matriarch"
const NESTS := ["world.greywood.den_nest_1", "world.greywood.den_nest_2", "world.greywood.den_nest_3"]
const BELLS := ["world.drowned.bell_1", "world.drowned.bell_2", "world.drowned.bell_3", "world.drowned.bell_4",
	"world.drowned.bell_5"]
## The plan's wander tables (§5.10): entry -> [weight, min stage, max stage].
const TABLES := {"wander.greywood": {"dire_wolf_pack": [3, 4, 10], "troll_pair": [2, 4, 10], "troll_pack": [2, 5, 10],
	"hunters": [1, 0, 10]}, "wander.drowned_steps": {"ruin_robbers": [2, 3, 4], "ogre_pair": [2, 4, 10], "dire_wolves": [2, 4, 10]}}


## The layout tables read here (region -> table), once per run.
static var _tables := {}


func before_each() -> void:
	WorldState.clear()


func after_each() -> void:
	WorldState.clear()


static func _xz(a: Variant) -> Vector2:
	if a is Vector3:
		return Vector2((a as Vector3).x, (a as Vector3).z)
	return Vector2(float(a[0]), float(a[2])) if (a as Array).size() == 3 else Vector2(float(a[0]), float(a[1]))


func _element(id: String) -> Dictionary:
	for el: Dictionary in WorldContent.elements():
		if str(el.get("id", "")) == id:
			return el
	return {}


## A layout table's item of `section` (cairns, secrets...) with `id` ({} when there is none).
func _layout_item(region: String, section: String, id: String) -> Dictionary:
	if not _tables.has(region):
		_tables[region] = WorldFeatures.load_json(WorldLayout.DATA_DIR.path_join(region + ".json"))
	for it: Dictionary in (_tables[region] as Dictionary).get(section, []):
		if str(it.get("id", "")) == id:
			return it
	return {}


## P35's placed encounters (templates apart).
func _encounters() -> Array:
	return WorldContent.encounters().filter(func(r: Dictionary) -> bool:
		var id := str(r.id)
		return (id.begins_with("encounter.greywood_") or id.begins_with("encounter.drowned_")) and not bool(r.get("template", false)))


## Every choice of `dialogue` that writes `flag` = `value`: [choice, node id].
func _writers(dialogue: String, flag: String, value: Variant) -> Array:
	var out: Array = []
	for n: Dictionary in GameData.get_record(dialogue).get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			var flags: Dictionary = (c.get("effects", {}) as Dictionary).get("set_flags", {})
			if flags.has(flag) and QuestConditions.same_value(flags[flag], value):
				out.append([c, str(n.id)])
	return out


# --------------------------------------------------------------------------- the oath of the wood

func test_the_woods_oath_starts_at_stage_4_and_both_ways_win_it_first() -> void:
	var rec := GameData.get_record(WOOD)
	var ctx := QuestConditions.empty_context()
	ctx.stage = 3
	assert_false(QuestConditions.all_hold(rec.start_conditions, ctx), "the wood's oath waits for stage 4")
	ctx.stage = 4
	assert_true(QuestConditions.all_hold(rec.start_conditions, ctx), "and starts at stage 4")
	assert_eq(OathRules.first_oath_resolutions(WOOD, GameData.records), PackedStringArray(["drive", "slay"]),
		"slay and drive are both open to a first oath at stage 4")
	assert_eq(OathRules.first_oath_errors(GameData.records), PackedStringArray(), "every oath can be won first")
	assert_eq(OathRules.lead_errors(GameData.records), PackedStringArray(), "the oath leads end with their oaths")
	var stages: Array = rec.stages
	assert_eq(stages.map(func(s: Dictionary) -> String: return str(s.id)), ["meet", "den", "swear"], "meet, the den, swear")
	assert_eq(str(stages[0].marker), "world.marker.hollowmere_green", "Sedge is met at Hollowmere (the oaths stage's lead)")
	assert_eq(int(stages[0].xp), 50, "the meeting pays 50")
	assert_eq(int(stages[2].get("xp_floor_level", 0)), 9, "the oath lifts the XP to level 9")
	assert_eq(WorldItems.stage_items(WOOD), WorldItems.loot("loot.oath_reward"), "the last stage pays the oath's reward")
	# Each resolution: Sedge's report swears it once the Matriarch is gone - slain or fled.
	var expect := {"slay": ["slain", 750, 2], "drive": ["fled", 600, 0]}
	for outcome: String in expect:
		var ws := _writers("dialogue.sedge", "oath.wood.outcome", outcome)
		assert_eq(ws.size(), 1, "one choice of Sedge's swears the oath by %s" % outcome)
		if ws.size() != 1:
			continue
		var c: Dictionary = ws[0][0]
		var e: Dictionary = c.effects
		assert_eq(c.get("conditions", []), [{"type": "flag", "flag": "boss.matriarch.outcome", "equals": expect[outcome][0]}],
			"%s: once the Matriarch's outcome is %s" % [outcome, expect[outcome][0]])
		assert_true(bool(e.set_flags.get("oath.wood.done", false)), "%s: the oath is done" % outcome)
		assert_true(bool(e.set_flags.get("faction.woodfolk.allied", false)), "%s: the woodfolk become allies" % outcome)
		assert_eq(int(e.get("xp", 0)), int(expect[outcome][1]), "%s pays %d" % [outcome, expect[outcome][1]])
		assert_eq(int(e.get("attribute_points", 0)), int(expect[outcome][2]), "%s: the feast's attribute points" % outcome)
		assert_true(str(e.get("once_flag", "")) != "", "%s pays once" % outcome)
	# The drive: the nests and the wall are the Matriarch's drive-out flags, and the den writes them.
	var drive: Dictionary = GameData.get_record("enemy.troll_matriarch").drive_out
	var written := WorldContent.written_flags()
	for f: Variant in drive.requires_flags:
		assert_true(written.has(str(f)), "the den writes the drive-out flag %s" % f)
	var exit := WorldXp.position_of(str(drive.exit_marker))
	var wall := WorldXp.position_of("world.greywood.troll_den_wall")
	assert_true(exit.is_finite() and _xz(exit).distance_to(_xz(wall)) <= 12.0, "her way out is through the den's back wall")
	var wall_el := _element("world.greywood.troll_den_wall")
	var wall_rec := GameData.get_record(str(load("res://tools/world/kinds/den_wall.gd").call("record_of", wall_el)))
	assert_eq(str(wall_rec.get("requires_permission", "")), "heave", "a stage-5 giant heaves the wall")
	assert_eq(str(wall_rec.get("open_when_flag", "")), "world.troll_den.wall_open", "and the woodfolk's flag opens it")
	# Stormborn's bargain opens it at once (DenWall's bargain flag).
	var bargain := _writers("dialogue.sedge", "world.troll_den.bargain", true)
	assert_true(bargain.size() >= 1, "Sedge offers the druids' bargain")
	for b: Array in bargain:
		assert_true((b[0] as Dictionary).conditions.has({"type": "ancestry_is", "ancestry": "ancestry.stormborn"}),
			"only to a Stormborn giant (%s)" % b[1])
	var dw := DenWall.new()
	assert_eq(dw.bargain_flag, "world.troll_den.bargain", "the wall answers the bargain")
	dw.free()
	# Consequences: the scattered brood roams once she fled; Hollowmere's lanterns burn either way.
	var pack: Array = (GameData.get_record("wander.greywood").entries as Array).filter(
		func(e: Dictionary) -> bool: return str(e.id) == "troll_pack")
	assert_eq(pack.size(), 1, "the troll pack's wander entry")
	if pack.size() == 1:
		assert_eq(pack[0].get("conditions", []), [{"type": "flag", "flag": "boss.matriarch.outcome", "equals": "fled"}],
			"it roams once the Matriarch fled")
	assert_eq(str(_element("world.greywood.hollowmere_lights").get("visible_when_flag", "")), "oath.wood.done",
		"Hollowmere's lanterns are lit by the oath")


# --------------------------------------------------------------------------- the quests

## Changes `ctx` so that the condition `c` holds (a witness).
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
		"encounter_cleared":
			flags[QuestConditions.encounter_flag(str(d.encounter))] = true
		"destroyed":
			(ctx.destroyed as Dictionary)[str(d.world_id)] = true
		"dialogue_outcome":
			flags[QuestConditions.outcome_flag(str(d.dialogue), str(d.outcome))] = true
		"discovered":
			flags["discovered." + QuestConditions.short_of(str(d.poi))] = true
		"entered":
			(ctx.entered as Dictionary)[str(d.area)] = true
		"weapon_equipped":
			ctx.weapon = str(d.weapon)
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


func _flags_read(c: Variant, out: Array) -> void:
	if typeof(c) == TYPE_ARRAY:
		for x: Variant in c:
			_flags_read(x, out)
	elif typeof(c) == TYPE_DICTIONARY:
		if str(c.get("type", "")) == "flag":
			out.append(str(c.flag))
		_flags_read(c.get("of"), out)


func test_every_quest_stage_can_complete_reads_written_flags_and_points_at_known_places() -> void:
	var written := OathRules.flag_writers(GameData.records)
	written.merge(WorldContent.written_flags())
	var places := WorldContent.places()
	var idx := WorldContent.index()
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
				var engine := f.begins_with("quest.") or f.begins_with("discovered.")
				assert_true(written.has(f) or engine, "%s reads %s, which something writes" % [where, f])
			for m: String in Quests.stage_markers(s):
				assert_true(idx != null and idx.position_of(m).is_finite(), "%s: marker %s is in the world's index" % [where, m])
			var bot: Dictionary = s.get("bot", {})
			var targets: Array = []
			for key: String in ["target", "interact", "heave"]:
				if str(bot.get(key, "")) != "":
					targets.append(str(bot[key]))
			for key: String in ["burn", "targets"]:
				targets.append_array(bot.get(key, []))
			for t: Variant in targets:
				var known := places.has(str(t)) or GameData.has_record(str(t))
				assert_true(known, "%s: the bot's target %s is a known place" % [where, t])
	var tut := GameData.get_record("tutorial.troll_fire")
	assert_true(idx.areas.has(str(tut.trigger.area)), "the fire lesson's area is in the index")


# --------------------------------------------------------------------------- encounters

func _individuals(enc: Dictionary, stage: int) -> int:
	var n := 0
	for sp: Dictionary in enc.spawns:
		if not FormationRules.stage_allows(sp, stage):
			continue
		if str(GameData.get_record(str(sp.definition)).get("type", "")) == "enemy":
			n += 1
	return n


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


func test_every_encounter_is_leashed_indexed_and_within_the_budgets() -> void:
	var encs := _encounters()
	assert_eq(encs.size(), 11, "the regions' eleven placed encounters")
	var idx := WorldContent.index()
	for enc: Dictionary in encs:
		var id := str(enc.id)
		var arena := bool(enc.get("arena", false))
		var leash := float(enc.get("leash_radius_m", 0.0))
		assert_true(arena or (leash > 0.0 and leash <= MAX_LEASH_M), "%s has a leash of at most 70 m (%s)" % [id, leash])
		assert_true(str(idx.encounters.get(id, {}).get("chunk", "")) != "", "%s has its chunk in the index" % id)
		for sp: Dictionary in enc.spawns:
			assert_false(GameData.get_record(str(sp.definition)).is_empty(), "%s's %s exists" % [sp.entity_id, sp.definition])
			assert_true(str(sp.entity_id).begins_with("world.greywood.") or str(sp.entity_id).begins_with("world.drowned."),
				"%s is a region's world id" % sp.entity_id)
			if not arena:
				assert_true(_xz(sp.position_m).distance_to(_xz(enc.center_m)) <= leash, "%s starts inside %s's leash" % [sp.entity_id, id])
	var cliques: Array = []
	_cliques(encs, [], 0, cliques)
	var worst := 0
	for stage in range(1, 7):
		for clique: Array in cliques:
			var n := 0
			for i: int in clique:
				n += _individuals(encs[i], stage)
			worst = maxi(worst, n)
			assert_true(n <= INDIVIDUALS, "at stage %d the encounters %s field %d individuals" % [
				stage, clique.map(func(i: int) -> String: return str(encs[i].id)), n])
	print("    greywood and drowned steps: at most %d individual combatants within %d m of each other" % [worst, int(CLUSTER_M)])
	# A brazier or bonfire at every troll site, and beside every brood nest.
	var fires: Array = WorldContent.elements_of("brazier").map(func(el: Dictionary) -> Vector2: return _xz(el.pos))
	for enc: Dictionary in encs:
		var trolls: Array = (enc.spawns as Array).filter(func(sp: Dictionary) -> bool: return TROLLS.has(str(sp.definition)))
		if trolls.is_empty():
			continue
		var near := fires.filter(func(f: Vector2) -> bool: return f.distance_to(_xz(enc.center_m)) <= 40.0)
		assert_false(near.is_empty(), "%s's trolls have a fire within 40 m" % enc.id)
	for nest: String in NESTS:
		var el := _element(nest)
		var r := float(el.get("ignite_m", 9.0))
		assert_false(fires.filter(func(f: Vector2) -> bool: return f.distance_to(_xz(el.pos)) <= r).is_empty(),
			"%s has a brazier within its %.0f m" % [nest, r])


func test_the_troll_dens_arena_and_its_checkpoint() -> void:
	var arena := _element(DEN_ARENA)
	var den := GameData.get_record("encounter.greywood_troll_den")
	assert_true(bool(den.get("arena", false)), "the den is an arena boss's encounter")
	assert_eq(den.get("forbids_flags", []), ["boss.matriarch.outcome"], "she never comes back once slain or fled")
	assert_eq(str(arena.get("boss_id", "")), MATRIARCH, "the arena holds the Matriarch")
	assert_eq(str(arena.get("encounter", "")), str(den.id), "and her encounter")
	var bo: Dictionary = GameData.get_record("enemy.troll_matriarch").boss_outcome
	assert_eq(str(arena.get("defeated_flag", "")), str(bo.defeated_flag), "its defeated flag is hers")
	assert_true(WorldContent.index().areas.has(str(arena.get("engage_area", ""))), "its engage area is in the index")
	var r := float(arena.get("radius", 0.0))
	assert_eq(r, 45.0, "the bowl is 45 m across")
	var cp := WorldXp.position_of(DEN_CP)
	var d := _xz(cp).distance_to(_xz(arena.pos))
	assert_true(d > r and d <= 80.0, "the den's waystone lies outside the arena within 80 m (%.0f m)" % d)
	for sp: Dictionary in den.spawns:
		assert_true(_xz(sp.position_m).distance_to(_xz(arena.pos)) < r, "%s starts in the bowl" % sp.entity_id)


# --------------------------------------------------------------------------- the living world

func test_the_wander_tables_and_their_templates() -> void:
	var cps: Array = []
	for id: String in WorldContent.index().checkpoint_ids():
		cps.append(_xz(WorldXp.position_of(id)))
	for table: String in TABLES:
		var rec := GameData.get_record(table)
		var entries: Dictionary = {}
		for e: Dictionary in rec.entries:
			entries[str(e.id)] = e
		assert_eq(entries.keys(), (TABLES[table] as Dictionary).keys(), "%s's entries are the plan's" % table)
		var wander_xp := 0
		for id: String in entries:
			var e: Dictionary = entries[id]
			var want: Array = TABLES[table][id]
			assert_eq([int(e.weight), int(e.get("min_stage", 0)), int(e.get("max_stage", 10))], want, "%s.%s's weight and stages" % [table, id])
			var tpl := GameData.get_record(str(e.template))
			assert_true(bool(tpl.get("template", false)), "%s.%s names a template" % [table, id])
			var c := _xz(tpl.center_m)
			for p: Vector2 in cps:
				assert_true(p.distance_to(c) > 120.0, "%s's nominal centre is more than 120 m from every checkpoint" % tpl.id)
			for sp: Dictionary in tpl.spawns:
				assert_false(bool(sp.persist_death) or str(sp.loot_table) != "", "%s keeps nothing" % sp.entity_id)
				wander_xp += int(rec.xp_full_spawns) * int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
		var placed := 0
		var prefix := "encounter.greywood_" if table == "wander.greywood" else "encounter.drowned_"
		for enc: Dictionary in _encounters():
			if str(enc.id).begins_with(prefix):
				for sp: Dictionary in enc.spawns:
					placed += int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
		print("    %s pays at most %d kill XP (placed fights: %d)" % [table, wander_xp, placed])
		assert_true(wander_xp > 0 and wander_xp <= 3 * placed, "%s's kill XP is bounded by its placed fights" % table)


# --------------------------------------------------------------------------- gates and sealed places

func test_the_needle_the_grove_and_the_sealed_places() -> void:
	var pass_ := NarrowPass.new()
	assert_eq([pass_.fits(3), pass_.fits(4), pass_.fits(5), pass_.fits(6)], [true, true, false, false],
		"the Needle fits stages 3-4 and refuses 5")
	assert_true(pass_.message.contains("outgrown"), "and says so")
	pass_.free()
	var needle := _element("world.gate.needle")
	var west := _element("world.greywood.needle_wall_west")
	var east := _element("world.greywood.needle_wall_east")
	var mid := (_xz(west.pos) + _xz(east.pos)) * 0.5
	assert_true(_xz(needle.pos).distance_to(mid) < 3.0, "the Needle's sign stands in the slot between its walls")
	var idx := WorldContent.index()
	var grove := GameData.get_record("poi.hidden_grove")
	var rockfall: Dictionary = idx.props.get("world.greywood.grove_rockfall", {})
	assert_eq(str(rockfall.get("kind", "")), "rockfall", "the Hidden Grove's second key is a rockfall")
	assert_true(_xz(rockfall.get("position", Vector3.INF)).distance_to(_xz(grove.position_m)) <= 80.0,
		"on the grove's north ridge")
	assert_eq(str(GameData.get_record("prop.rockfall").get("requires_permission", "")), "heave", "heaved at stage 5")
	assert_eq(str(GameData.get_record("quest.the_needle").stages[0].complete_when.poi), "poi.hidden_grove",
		"the Needle's quest ends in the grove, whichever way the giant came")
	assert_eq(str(idx.props.get("world.drowned.vault_rockfall", {}).get("kind", "")), "rockfall", "the causeway's rockfall seals the vault")
	assert_true(_xz(idx.areas["world.area.sunken_vault"].position).distance_to(_xz(GameData.get_record("poi.sunken_vault").position_m)) <= 30.0,
		"the vault's area lies in the vault")
	for cairn: Array in [["world.greywood.old_root_cairn", "old_root", 5, "greywood"],
			["world.drowned.vault_cairn", "sunken_vault", 0, "drowned_steps"],
			["world.drowned.shoulder_cairn", "bones_shoulder", 6, "drowned_steps"]]:
		assert_eq(str(idx.props.get(cairn[0], {}).get("kind", "")), "cairn", "%s is a cairn" % cairn[0])
		assert_eq(int(_layout_item(str(cairn[3]), "cairns", cairn[0]).get("requires_stage", 0)), int(cairn[2]), "%s's stage" % cairn[0])
		assert_eq(Inscription.gift_flag(GameData.get_record("dialogue.cairn_" + str(cairn[1]))), "reward.cairn." + str(cairn[1]),
			"%s gives its point once" % cairn[0])


func test_the_bells_the_titan_forge_and_the_stoneknuckles() -> void:
	var idx := WorldContent.index()
	for bell: String in BELLS:
		assert_eq(str(idx.props.get(bell, {}).get("kind", "")), "bell", "%s hangs in the world" % bell)
	var circle := GameData.get_record("poi.ancestral_circle")
	assert_true(_xz(WorldXp.position_of(BELLS[4])).distance_to(_xz(circle.position_m)) <= float(circle.radius_m),
		"the fifth bell hangs on the island")
	assert_eq(str(GameData.get_record("prop.bell").get("category", "")), "breakable", "a bell rings when struck")
	var forge := _element("world.drowned.titan_forge")
	assert_eq(str(forge.get("tier", "")), "titan", "the Titan Forge is a titan-tier forge")
	assert_eq(forge.get("requires_flags", []), ["world.titan_forge.lit"], "once its fire burns")
	var fire := _element("world.drowned.titan_forge_fire")
	assert_eq(str(fire.get("flag", "")), "world.titan_forge.lit", "the fire lights it")
	assert_eq(fire.get("requires_flags", []), [EncounterDirector.cleared_flag("encounter.drowned_bones_scavengers")],
		"once the scavengers are gone: no stage and no oath (a stage-4 giant's first titanforging)")
	assert_eq(WorldItems.count(WorldItems.loot(str(fire.loot)), WorldItems.TITAN_IRON), 2, "the ribs' 2 titan iron")
	var f := Forge.new()
	f.set("tier", str(forge.tier))
	var step: Dictionary = GameData.get_record("weapon.club_reinforced").upgrade
	assert_eq(str(step.to), "weapon.club_titan", "a reinforced weapon's next step is titanforged")
	assert_true(f.does_tier(str(step.get("forge_tier", "iron"))), "the Titan Forge titanforges it")
	f.free()
	var rack := _element("world.drowned.stoneknuckles_rack")
	assert_eq(str(rack.get("weapon", "")), "weapon.fists", "the Stoneknuckles wait on the ferrywoman's landing")
	assert_eq(rack.get("requires_flags", []), ["quest.drowned_bells.done"], "for the giant who rang the five bells")


# --------------------------------------------------------------------------- Sedge on the green

func test_sedge_meets_a_big_giant_on_hollowmeres_green() -> void:
	var poi := GameData.get_record("poi.hollowmere")
	var sedge := WorldXp.position_of("world.greywood.sedge")
	assert_true(_xz(sedge).distance_to(_xz(poi.position_m)) <= float(poi.radius_m), "Sedge lives inside Hollowmere")
	assert_eq(str(GameData.get_record("npc.sedge").get("role", "")), "talker", "a talker the director moves")
	assert_eq(int(poi.max_inner_stage), 4, "a giant of stage 4 meets her among the huts")
	var green := _xz(poi.green_m)
	assert_true(green.distance_to(_xz(WorldXp.position_of("world.marker.hollowmere_green"))) <= 10.0,
		"a giant of stage 5-6 meets her on the green, where the oath's marker points")
	assert_true(_xz(sedge).distance_to(green) <= 40.0, "the green is a short walk from her huts")
	var ferry := WorldXp.position_of("world.drowned.ferrywoman")
	for p: Dictionary in GameData.records_of_type("poi"):
		if str(p.get("kind", "")) == "settlement" and str(p.get("level", "")) == LEVEL:
			assert_true(_xz(ferry).distance_to(_xz(p.position_m)) > float(p.radius_m), "Wenna keeps her landing at every stage")
