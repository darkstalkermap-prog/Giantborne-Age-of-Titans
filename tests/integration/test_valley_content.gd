extends TestSuite
## The Valley's content, checked from the data and the built scene (P15, plan §3.17 tests; the
## Valley is instanced once, never added to the tree, and indexed: markers, areas, props,
## shrines, waystones, dummies and patrol routes with their level-space positions):
##   * integrity: every marker, area, world id, entity id, patrol, encounter, item, dialogue and
##     flag that quests, dialogue, encounters, tutorials, NPC records or the scene refer to exists
##     (flags: something writes them), and every id is unique;
##   * quest-critical objects: every prop a mandatory `destroyed` stage needs is not protected and
##     takes an attack the giant has by then (the cairn: Boulder Hurl's projectile at stage 2; the
##     practice gate: melee; the Deadfall: the tree's TreeWeapon at stage 3; and the barricade for
##     force: melee at stage 2);
##   * growth-shrine safety: no spawn or patrol point within 35 m of a growth pad, no leash circle
##     over one;
##   * checkpoint placement: the roads pass within the activation radius of every shrine and
##     waystone on the critical path;
##   * introductions: the first critical-path encounter with a mage has no archer, the first
##     soldiers are the forest hunters, met at stage 1;
##   * the tutorial prompts and the village choice (decision 11).
## The world's quests, dialogue and prompts (P27, P29 on) name the world's places and flags: a
## reference resolves in the Valley's scene or in the world (WorldContent: the world's index, its
## encounters' spawns and the flags its encounters, factions, beacons and breakable sites write).

const VALLEY := "res://scenes/world/valley.tscn"
const LAYOUT := "res://tools/data/valley_layout.json"
const LEVEL := "level.valley"
const SAFE_GROWTH_M := 35.0   # sight 25 m + 10 m (plan §3.17)
## Encounters in the order the quest line meets them, and those off the critical path.
const CRITICAL_PATH := ["encounter.forest_wolves_a", "encounter.forest_hunters", "encounter.forest_ogre",
	"encounter.road_patrol", "encounter.ruins_gate", "encounter.ruins_courtyard", "encounter.kingsfall_boss",
	"encounter.return_patrol", "encounter.village_ambush", "encounter.barrow_wardens"]
const OFF_PATH := ["encounter.hollow_sparring", "encounter.village_guards", "encounter.village_folk",
	"encounter.quarry_raiders", "encounter.field_ogre"]
const PROMPTS := ["tutorial.camera", "tutorial.light", "tutorial.heavy", "tutorial.footfall", "tutorial.lock",
	"tutorial.block", "tutorial.dodge", "tutorial.shrine", "tutorial.soldier_guard", "tutorial.grab",
	"tutorial.hurl", "tutorial.attributes", "tutorial.boss_charge"]
## The world's prompts (P27, plan M6-M9 §3.10: data/tutorial/{map,compass,fast_travel,discovery,size_gate,
## sealed_place}.json; P29, §3.12: {world_arrival,stage4_humans,formations}.json): each waits for
## progress.world_entered, so none shows in a first Valley run.
const WORLD_PROMPTS := ["tutorial.map", "tutorial.compass", "tutorial.fast_travel", "tutorial.discovery",
	"tutorial.size_gate", "tutorial.sealed_place", "tutorial.world_arrival", "tutorial.stage4_humans",
	"tutorial.formations"]
const QUESTS := ["quest.main", "quest.tutorial", "quest.village", "quest.village_cache", "quest.village_ogre"]

static var _index: Dictionary = {}


# --------------------------------------------------------------------------- the scene index

## The Valley scene's ids and positions (level space), built once per run.
func _scene() -> Dictionary:
	if not _index.is_empty():
		return _index
	var idx := {"markers": {}, "areas": {}, "props": {}, "shrines": {}, "waystones": {}, "dummies": {},
		"patrols": {}, "arena": {}, "exits": {}, "duplicates": []}
	var root := (load(VALLEY) as PackedScene).instantiate()
	_walk(root, Transform3D.IDENTITY, idx)
	root.free()
	_index = idx
	return idx


func _put(idx: Dictionary, kind: String, id: String, value: Variant) -> void:
	if (idx[kind] as Dictionary).has(id):
		(idx.duplicates as Array).append("%s %s" % [kind, id])
	idx[kind][id] = value


func _walk(n: Node, parent: Transform3D, idx: Dictionary) -> void:
	var xf := parent * (n as Node3D).transform if n is Node3D else parent
	if n is Shrine:
		var pad := n.get_node_or_null("GrowthPad") as Node3D
		_put(idx, "shrines", (n as Shrine).world_id, {"pos": xf.origin, "record": (n as Shrine).shrine_id,
			"pad": (xf * pad.transform).origin if pad != null else xf.origin})
	elif n is Waystone:
		var w := n as Waystone
		_put(idx, "waystones", w.checkpoint_id, {"pos": xf.origin, "radius": w.radius_m, "requires": Array(w.requires_flags)})
	elif n is LevelMarker:
		var m := n as LevelMarker
		_put(idx, "markers", m.marker_id, {"pos": xf.origin, "kind": m.kind, "faction": m.faction})
	elif n is AreaTrigger:
		_put(idx, "areas", (n as AreaTrigger).area_id, {"pos": xf.origin})
	elif n is LevelExit:
		_put(idx, "exits", (n as LevelExit).exit_id, {"pos": xf.origin})
	elif n is PracticeDummy:
		_put(idx, "dummies", str(n.get("entity_id")), {"pos": xf.origin})
	elif n is BossArena:
		var a := n as BossArena
		idx.arena = {"boss": a.boss_id, "encounter": a.encounter_id, "area": a.engage_area_id, "flag": a.defeated_flag}
	elif "world_id" in n and str(n.get("world_id")) != "" and n.get_parent() != null and n.get_parent().name == "Props":
		var entity := n.get_node_or_null("CombatEntity") as CombatEntity
		var info := {"pos": xf.origin, "kind": n.get_script().get_global_name() if n.get_script() != null else "",
			"record": entity.definition_id if entity != null else ""}
		for key: String in ["item_id", "set_flag", "weapon_id", "prop_id", "requires_flags", "requires_flag_values"]:
			if key in n:
				info[key] = n.get(key)
		_put(idx, "props", str(n.get("world_id")), info)
	if n.has_meta("route_id"):
		var pts: Array = []
		for c in n.get_children():
			if c is Node3D:
				pts.append((xf * (c as Node3D).transform).origin)
		_put(idx, "patrols", str(n.get_meta("route_id")), pts)
	for c in n.get_children():
		_walk(c, xf, idx)


# --------------------------------------------------------------------------- data helpers

func _records(type: String) -> Array:
	return GameData.records_of_type(type)


func _valley_encounters() -> Array:
	return _records("encounter").filter(func(r: Dictionary) -> bool: return str(r.get("level", "")) == LEVEL)


## entity id -> {"encounter", "definition", "pos"} of every spawn of the Valley's encounters.
func _spawns() -> Dictionary:
	var out := {}
	for rec: Dictionary in _valley_encounters():
		for sp: Dictionary in rec.get("spawns", []):
			out[str(sp.entity_id)] = {"encounter": str(rec.id), "definition": str(sp.definition),
				"pos": _v3(sp.position_m), "patrol": str(sp.get("patrol", "")), "commander": bool(sp.get("commander", false))}
	return out


static func _v3(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## Every condition dictionary inside `c` (all / any / not unpacked), in order.
static func _conditions(c: Variant, out: Array) -> Array:
	if typeof(c) == TYPE_ARRAY:
		for x: Variant in c:
			_conditions(x, out)
	elif typeof(c) == TYPE_DICTIONARY:
		var d: Dictionary = c
		if str(d.get("type", "")) in ["all", "any", "not"]:
			_conditions(d.get("of"), out)
		else:
			out.append(d)
	return out


## Every flag something in the shipped content can write.
func _written_flags() -> Dictionary:
	var w := {}
	for rec: Dictionary in _records("quest"):
		var id := str(rec.id)
		w[Quests.stage_flag(id)] = true
		w[Quests.done_flag(id)] = true
		for f: Variant in (rec.get("on_complete_flags", {}) as Dictionary):
			w[str(f)] = true
		for s: Dictionary in rec.get("stages", []):
			w[Quests.reward_flag(id, str(s.id))] = true
			for f: Variant in (s.get("set_flags", {}) as Dictionary):
				w[str(f)] = true
	for rec: Dictionary in _records("dialogue"):
		for n: Dictionary in rec.get("nodes", []):
			for c: Dictionary in n.get("choices", []):
				var e: Dictionary = c.get("effects", {})
				for f: Variant in (e.get("set_flags", {}) as Dictionary):
					w[str(f)] = true
				if str(e.get("once_flag", "")) != "":
					w[str(e.once_flag)] = true
				if str(e.get("outcome", "")) != "":
					w[QuestConditions.outcome_flag(str(rec.id), str(e.outcome))] = true
	for rec: Dictionary in _records("tutorial_prompt"):
		w[TutorialDirector.seen_flag(str(rec.id))] = true
		if str(rec.get("sets_flag", "")) != "":
			w[str(rec.sets_flag)] = true
	for rec: Dictionary in _valley_encounters():
		w[EncounterDirector.cleared_flag(str(rec.id))] = true
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.get("faction", "")) != "":
				w[FactionState.flag_id(str(sp.faction), "warned")] = true
				w[FactionState.flag_id(str(sp.faction), "hostile")] = true
	var scene := _scene()
	for id: String in scene.props:
		var p: Dictionary = scene.props[id]
		for f: Variant in (GameData.get_record(str(p.get("record", ""))).get("on_destroyed_flags", {}) as Dictionary):
			w[str(f)] = true
		if str(p.get("set_flag", "")) != "":
			w[str(p.set_flag)] = true
	if not (scene.arena as Dictionary).is_empty():
		w[str(scene.arena.flag)] = true
	w[UprootTree.TAKEN_FLAG] = true
	# Flags code writes for the world's prompts: GameSession (P20) on entering the world, Discovery and
	# the map screen (P27).
	w["progress.world_entered"] = true
	w[Discovery.SEALED_COUNT_FLAG] = true
	w[Discovery.MAP_OPENED_FLAG] = true
	# The world's writers besides the records (P29): its encounters, factions, beacons and breakable sites.
	w.merge(WorldContent.written_flags())
	return w


## Every flag the shipped content reads: [flag, where].
func _read_flags() -> Array:
	var out: Array = []
	for rec: Dictionary in _records("quest"):
		var conds: Array = []
		_conditions(rec.get("start_conditions", []), conds)
		_conditions(rec.get("abandon_when"), conds)
		for s: Dictionary in rec.get("stages", []):
			_conditions(s.get("complete_when"), conds)
		for c: Dictionary in conds:
			if str(c.get("type", "")) == "flag":
				out.append([str(c.flag), str(rec.id)])
	for rec: Dictionary in _records("dialogue"):
		var conds: Array = []
		for e: Dictionary in rec.get("entries", []):
			_conditions(e.get("conditions", []), conds)
		for n: Dictionary in rec.get("nodes", []):
			for c: Dictionary in n.get("choices", []):
				_conditions(c.get("conditions", []), conds)
		for c: Dictionary in conds:
			if str(c.get("type", "")) == "flag":
				out.append([str(c.flag), str(rec.id)])
	for rec: Dictionary in _records("tutorial_prompt"):
		for f: Variant in rec.get("requires_flags", []):
			out.append([str(f), str(rec.id)])
		for key: String in ["trigger", "dismiss"]:
			var t: Dictionary = rec.get(key, {})
			if str(t.get("type", "")) == "flag":
				out.append([str(t.flag), "%s.%s" % [rec.id, key]])
	for rec: Dictionary in _valley_encounters():
		for key: String in ["requires_flags", "forbids_flags"]:
			for f: Variant in rec.get(key, []):
				out.append([str(f), str(rec.id)])
	for rec: Dictionary in _records("shrine"):
		# the world's shrines (shrine.world_*, P25) are level.world's content: the world's packages
		# write their flags (P29 the Kingsgate beacon's world.kingsgate.lit; test_world_data)
		if str(rec.id).begins_with("shrine.world_"):
			continue
		for f: Variant in rec.get("growth_requires_flags", []):
			out.append([str(f), str(rec.id)])
	var scene := _scene()
	for id: String in scene.waystones:
		for f: Variant in scene.waystones[id].requires:
			out.append([str(f), id])
	for id: String in scene.props:
		var p: Dictionary = scene.props[id]
		for f: Variant in p.get("requires_flags", []):
			out.append([str(f), id])
		for f: Variant in (p.get("requires_flag_values", {}) as Dictionary):
			out.append([str(f), id])
		var open := str(GameData.get_record(str(p.get("record", ""))).get("open_when_flag", ""))
		if open != "":
			out.append([open, id])
	return out


# --------------------------------------------------------------------------- integrity

func test_every_id_in_the_scene_is_unique_and_the_content_is_shipped() -> void:
	var scene := _scene()
	assert_eq(scene.duplicates, [], "no id appears twice in the Valley scene")
	for id: String in QUESTS:
		assert_eq(str(GameData.get_record(id).get("type", "")), "quest", "%s ships" % id)
	assert_eq(str(GameData.get_record("dialogue.elder").get("type", "")), "dialogue", "dialogue.elder ships")
	var prompt_ids: Array = []
	for rec: Dictionary in _records("tutorial_prompt"):
		prompt_ids.append(str(rec.id))
	prompt_ids.sort()
	var expected := PROMPTS.duplicate()
	expected.append_array(WORLD_PROMPTS)
	expected.sort()
	assert_eq(prompt_ids, expected, "the 13 tutorial prompts of plan §4.5 and the world's nine (P27, P29)")
	for id: String in WORLD_PROMPTS:
		assert_true((GameData.get_record(id).get("requires_flags", []) as Array).has("progress.world_entered"),
			"%s waits for the world" % id)
	var ids := {}
	for rec: Dictionary in _valley_encounters():
		for sp: Dictionary in rec.get("spawns", []):
			assert_false(ids.has(str(sp.entity_id)), "spawn %s is unique" % sp.entity_id)
			ids[str(sp.entity_id)] = true
			assert_false((scene.dummies as Dictionary).has(str(sp.entity_id)), "%s is not a dummy's id too" % sp.entity_id)
	assert_true(GameData.errors.is_empty(), "the data validates (%s)" % [GameData.errors])
	var warnings := Array(GameData.warnings).filter(func(w: String) -> bool:
		return w.contains("quest.") or w.contains("dialogue.") or w.contains("tutorial.") or w.contains("encounter."))
	assert_eq(warnings, [], "no warnings on the quest line, dialogue, prompts or encounters")


func test_every_reference_resolves() -> void:
	var scene := _scene()
	var spawns := _spawns()
	var known_targets := {}
	for d: Dictionary in [scene.markers, scene.props, scene.shrines, scene.waystones, scene.areas, scene.dummies,
			scene.exits, spawns]:
		for id: String in d:
			known_targets[id] = true
	for rec: Dictionary in _valley_encounters():
		known_targets[str(rec.id)] = true
	var world := WorldContent.places()
	known_targets.merge(world)
	# Quests: markers, conditions and bot hints.
	for rec: Dictionary in _records("quest"):
		var conds: Array = []
		_conditions(rec.get("start_conditions", []), conds)
		_conditions(rec.get("abandon_when"), conds)
		for s: Dictionary in rec.get("stages", []):
			var where := "%s.%s" % [rec.id, s.id]
			for m: String in Quests.stage_markers(s):
				assert_true((scene.markers as Dictionary).has(m) or world.has(m), "%s: marker %s" % [where, m])
			_conditions(s.get("complete_when"), conds)
			var bot: Dictionary = s.get("bot", {})
			if str(bot.get("target", "")) != "":
				assert_true(known_targets.has(str(bot.target)), "%s: bot target %s" % [where, bot.target])
			if str(bot.get("dialogue", "")) != "":
				assert_false(GameData.get_record(str(bot.dialogue)).is_empty(), "%s: dialogue %s" % [where, bot.dialogue])
			if str(bot.get("encounter", "")) != "":
				assert_true(known_targets.has(str(bot.encounter)), "%s: encounter %s" % [where, bot.encounter])
		for c: Dictionary in conds:
			_check_condition(c, str(rec.id), scene, spawns)
	# Dialogue conditions; the NPC records' dialogue.
	for rec: Dictionary in _records("dialogue"):
		var conds: Array = []
		for e: Dictionary in rec.get("entries", []):
			_conditions(e.get("conditions", []), conds)
		for n: Dictionary in rec.get("nodes", []):
			for c: Dictionary in n.get("choices", []):
				_conditions(c.get("conditions", []), conds)
		for c: Dictionary in conds:
			_check_condition(c, str(rec.id), scene, spawns)
	for rec: Dictionary in _records("npc"):
		if str(rec.get("dialogue", "")) != "":
			assert_eq(str(GameData.get_record(str(rec.dialogue)).get("type", "")), "dialogue",
				"%s's dialogue %s ships" % [rec.id, rec.dialogue])
	# Tutorial triggers and dismissals.
	for rec: Dictionary in _records("tutorial_prompt"):
		for key: String in ["trigger", "dismiss"]:
			var t: Dictionary = rec.get(key, {})
			match str(t.get("type", "")):
				"entered":
					assert_true((scene.areas as Dictionary).has(str(t.area)), "%s.%s: area %s" % [rec.id, key, t.area])
				"event":
					assert_true(DataValidator.TUTORIAL_EVENTS.has(str(t.event)), "%s.%s: event %s" % [rec.id, key, t.event])
				"action_id":
					assert_true(GameData.get_action(str(t.action_id)) != null, "%s.%s: action %s" % [rec.id, key, t.action_id])
				"action_kind":
					assert_true(DataValidator.ACTION_KINDS.has(str(t.action_kind)), "%s.%s: kind %s" % [rec.id, key, t.action_kind])
	# Encounters: patrol routes, definitions, the level's districts.
	var districts := {}
	for d: Dictionary in GameData.get_record(LEVEL).get("districts", []):
		districts[str(d.id)] = true
	for rec: Dictionary in _valley_encounters():
		assert_true(districts.has(str(rec.get("district", ""))), "%s: district %s" % [rec.id, rec.get("district", "")])
		for sp: Dictionary in rec.get("spawns", []):
			var patrol := str(sp.get("patrol", ""))
			if patrol != "":
				assert_true((scene.patrols as Dictionary).has(patrol), "%s: patrol %s" % [sp.entity_id, patrol])
			assert_true(str(GameData.get_record(str(sp.definition)).get("type", "")) in ["enemy", "npc"],
				"%s: definition %s" % [sp.entity_id, sp.definition])
	# The arena, the pickups, racks and forges of the scene.
	var arena: Dictionary = scene.arena
	assert_true(spawns.has(str(arena.get("boss", ""))) and str(spawns[str(arena.boss)].encounter) == str(arena.encounter),
		"the arena's boss %s is its encounter's spawn" % arena.get("boss", ""))
	assert_true((scene.areas as Dictionary).has(str(arena.get("area", ""))), "the arena's engage area")
	for id: String in scene.props:
		var p: Dictionary = scene.props[id]
		if p.has("item_id"):
			assert_false(GameData.get_record(str(p.item_id)).is_empty(), "%s: item %s" % [id, p.item_id])
		if p.has("weapon_id") and str(p.weapon_id) != "":
			assert_eq(str(GameData.get_record(str(p.weapon_id)).get("type", "")), "weapon", "%s: weapon %s" % [id, p.weapon_id])
		if str(p.get("record", "")) != "":
			assert_eq(str(GameData.get_record(str(p.record)).get("type", "")), "prop", "%s: prop record %s" % [id, p.record])
	# Flags: everything read is written by something.
	var written := _written_flags()
	for pair: Array in _read_flags():
		assert_true(written.has(str(pair[0])), "%s reads flag %s, which nothing writes" % [pair[1], pair[0]])


func _check_condition(c: Dictionary, where: String, scene: Dictionary, spawns: Dictionary) -> void:
	var world := WorldContent.places()
	match str(c.get("type", "")):
		"entered":
			assert_true((scene.areas as Dictionary).has(str(c.area)) or world.has(str(c.area)), "%s: area %s" % [where, c.area])
		"killed":
			for t: Variant in c.get("targets", []):
				assert_true(spawns.has(str(t)) or world.has(str(t)), "%s: kill target %s is a spawn" % [where, t])
		"hits_on":
			for t: Variant in c.get("targets", []):
				assert_true(spawns.has(str(t)) or (scene.dummies as Dictionary).has(str(t)) or world.has(str(t)),
					"%s: hits_on target %s" % [where, t])
		"near":
			var target := str(c.get("target", ""))
			assert_true((scene.markers as Dictionary).has(target) or (scene.props as Dictionary).has(target)
				or world.has(target), "%s: near target %s" % [where, target])
			if c.has("action_id"):
				assert_true(GameData.get_action(str(c.action_id)) != null, "%s: action %s" % [where, c.action_id])
		"encounter_cleared":
			assert_eq(str(GameData.get_record(str(c.encounter)).get("type", "")), "encounter", "%s: encounter %s" % [where, c.encounter])
		"destroyed":
			assert_true((scene.props as Dictionary).has(str(c.world_id)) or world.has(str(c.world_id)), "%s: prop %s" % [where, c.world_id])
		"has_item":
			assert_eq(str(GameData.get_record(str(c.item)).get("type", "")), "item", "%s: item %s" % [where, c.item])
		"weapon_equipped":
			assert_eq(str(GameData.get_record(str(c.weapon)).get("type", "")), "weapon", "%s: weapon %s" % [where, c.weapon])
		"dialogue_outcome":
			assert_eq(str(GameData.get_record(str(c.dialogue)).get("type", "")), "dialogue", "%s: dialogue %s" % [where, c.dialogue])


# --------------------------------------------------------------------------- quest-critical objects

## The attacks the giant has at `stage`: [{category, tags, stage, what}] from the start weapon's
## moveset, the library abilities a stage meets, and the tree once the quest line hands it out.
func _attacks(stage: int, tree: bool) -> Array:
	var out: Array = []
	var weapons := ["weapon.club"]
	if tree:
		weapons.append("weapon.tree_oak")
	for wid: String in weapons:
		var w := GameData.get_record(wid)
		if int(w.get("required_stage", 1)) > stage:
			continue
		for aid: String in [str(w.get("light_chain", "")), str(w.get("heavy", ""))]:
			var a := GameData.get_record(aid)
			if a.is_empty():
				continue
			var tags: Array = Array(a.get("tags", [])) + Array(w.get("tags", []))
			out.append({"category": str(a.get("category", "melee")), "tags": tags, "what": "%s %s" % [wid, aid]})
	for id: Variant in Progression.library():
		var a := GameData.get_record(str(id))
		if int(a.get("unlock_stage", 1)) <= stage:
			out.append({"category": str(a.get("category", "ability")), "tags": Array(a.get("tags", [])), "what": str(id)})
	return out


func _accepts(prop_rec: Dictionary, attack: Dictionary, stage: int) -> bool:
	if bool(prop_rec.get("protected", false)) or stage < int(prop_rec.get("min_growth_stage", 1)):
		return false
	if not (prop_rec.get("accepted_attack_categories", []) as Array).has(attack.category):
		return false
	for t: Variant in prop_rec.get("required_tags", []):
		if not (attack.tags as Array).has(str(t)):
			return false
	return true


func test_quest_critical_props_take_an_attack_the_giant_has_by_then() -> void:
	var scene := _scene()
	var stage := 1
	var tree := false
	var checked := []
	for s: Dictionary in GameData.get_record("quest.main").get("stages", []):
		var conds: Array = _conditions(s.get("complete_when"), [])
		for c: Dictionary in conds:
			if str(c.type) != "destroyed":
				continue
			var id := str(c.world_id)
			if checked.has(id):
				continue   # also an alternative of an earlier stage (bridge: the gate broken)
			var p: Dictionary = scene.props.get(id, {})
			var rec := GameData.get_record(str(p.get("record", "")))
			assert_false(rec.is_empty(), "%s: %s has a prop record" % [s.id, id])
			assert_false(bool(rec.get("protected", false)), "%s: %s is not protected" % [s.id, id])
			var ok := _attacks(stage, tree).filter(func(a: Dictionary) -> bool: return _accepts(rec, a, stage))
			assert_true(not ok.is_empty(), "%s: at stage %d the giant can break %s" % [s.id, stage, id])
			checked.append(id)
		# The state the stage leaves behind.
		for c: Dictionary in conds:
			if str(c.type) == "stage_at_least":
				stage = maxi(stage, int(c.stage))
			if str(c.type) == "flag" and str(c.flag) == UprootTree.TAKEN_FLAG:
				tree = true
	assert_eq(checked, ["valley.grove.cairn", "valley.ruins.practice_gate", "valley.forest.deadfall"],
		"the three props the quest line must break")
	# Each one takes what it teaches, and only that.
	var cairn := GameData.get_record(str(scene.props["valley.grove.cairn"].record))
	assert_eq(cairn.get("accepted_attack_categories", []), ["projectile"], "the cairn takes projectiles only")
	assert_eq(str(GameData.get_record("ability.boulder_hurl").get("category", "")), "projectile", "Boulder Hurl is a projectile")
	assert_eq(int(GameData.get_record("ability.boulder_hurl").get("unlock_stage", 0)), 2, "learned at stage 2 (the Grove)")
	assert_true(_attacks(1, false).filter(func(a: Dictionary) -> bool: return _accepts(cairn, a, 1)).is_empty(),
		"nothing a stage-1 giant has topples the cairn")
	var deadfall := GameData.get_record(str(scene.props["valley.forest.deadfall"].record))
	assert_true(_attacks(3, false).filter(func(a: Dictionary) -> bool: return _accepts(deadfall, a, 3)).is_empty(),
		"without the tree nothing breaks the Deadfall")
	assert_true((GameData.get_record("weapon.tree_oak").get("tags", []) as Array).has("TreeWeapon"), "the tree carries TreeWeapon")
	for oak: String in ["valley.kingsfall.oak", "valley.forest.oak_barrow"]:
		assert_eq(str(scene.props.get(oak, {}).get("kind", "")), "UprootTree", "%s can be uprooted" % oak)
	# Force: the barricade breaks to a stage-2 blow, never a stage-1 one.
	var barricade := GameData.get_record(str(scene.props["valley.village.barricade"].record))
	assert_true(not _attacks(2, false).filter(func(a: Dictionary) -> bool: return _accepts(barricade, a, 2)).is_empty(),
		"a stage-2 giant can smash the barricade")
	assert_true(_attacks(1, false).filter(func(a: Dictionary) -> bool: return _accepts(barricade, a, 1)).is_empty(),
		"a stage-1 giant cannot")


# --------------------------------------------------------------------------- placement

func test_growth_shrines_are_out_of_every_encounters_reach() -> void:
	var scene := _scene()
	var pads := 0
	for id: String in scene.shrines:
		var rec := GameData.get_record(str(scene.shrines[id].record))
		if not bool(rec.get("allows_growth", false)):
			continue
		pads += 1
		var pad: Vector3 = scene.shrines[id].pad
		for enc: Dictionary in _valley_encounters():
			var leash := float(enc.get("leash_radius_m", 0.0))
			var centre := _v3(enc.center_m)
			if leash > 0.0:
				assert_true(_flat(centre, pad) > leash, "%s's leash (%.0f m) stays off %s's pad (%.1f m)" % [enc.id, leash, id,
					_flat(centre, pad)])
			for sp: Dictionary in enc.get("spawns", []):
				var at := _v3(sp.position_m)
				assert_true(_flat(at, pad) >= SAFE_GROWTH_M, "%s spawns %.1f m from %s's pad" % [sp.entity_id, _flat(at, pad), id])
				var patrol := str(sp.get("patrol", ""))
				for pt: Vector3 in scene.patrols.get(patrol, []):
					assert_true(_flat(pt, pad) >= SAFE_GROWTH_M, "%s's patrol point %s is %.1f m from %s's pad" % [
						sp.entity_id, pt, _flat(pt, pad), id])
	assert_eq(pads, 2, "two growth shrines (the Grove and Kingsfall)")


func test_the_roads_pass_every_checkpoint_on_the_critical_path() -> void:
	var scene := _scene()
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var roads: Array = layout.get("roads", [])
	var points := {}
	for id: String in scene.shrines:
		points[id] = [scene.shrines[id].pos, float(GameData.get_record(str(scene.shrines[id].record)).get("activation_radius_m", 14.0))]
	for id: String in scene.waystones:
		points[id] = [scene.waystones[id].pos, float(scene.waystones[id].radius)]
	# P26 (plan M6-M9 §5.6): the Kings' Door's and the Citadel stair's waystones join the M5 three.
	assert_eq(points.size(), 9, "four shrines and five waystones")
	for id: String in points:
		var best := INF
		for road: Dictionary in roads:
			var pts: Array = road.points
			for i in pts.size() - 1:
				var a := Vector2(float(pts[i][0]), float(pts[i][1]))
				var b := Vector2(float(pts[i + 1][0]), float(pts[i + 1][1]))
				var p := Vector2((points[id][0] as Vector3).x, (points[id][0] as Vector3).z)
				best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
		assert_true(best <= float(points[id][1]), "%s lies %.1f m off a road, within its %.0f m" % [id, best, points[id][1]])


func test_introductions_on_the_critical_path() -> void:
	var listed := CRITICAL_PATH + OFF_PATH
	for rec: Dictionary in _valley_encounters():
		assert_true(listed.has(str(rec.id)), "%s is placed on or off the critical path in this test" % rec.id)
	var first_mage := ""
	var first_soldiers := ""
	var first_archer := ""
	for id: String in CRITICAL_PATH:
		var defs := (GameData.get_record(id).get("spawns", []) as Array).map(func(sp: Dictionary) -> String: return str(sp.definition))
		if first_mage == "" and defs.has("enemy.mage"):
			first_mage = id
			assert_false(defs.has("enemy.archer"), "%s, the first mage, comes without an archer" % id)
		if first_archer == "" and defs.has("enemy.archer"):
			first_archer = id
		if first_soldiers == "" and defs.has("enemy.soldier"):
			first_soldiers = id
	assert_eq(first_soldiers, "encounter.forest_hunters", "the first soldiers are the forest hunters")
	assert_eq(GameData.get_record(first_soldiers).get("requires_flags", []), [], "met before any growth (stage 1)")
	assert_eq(first_mage, "encounter.road_patrol", "the first mage walks with the road patrol")
	assert_eq(GameData.get_record(first_mage).get("requires_flags", []), ["reward.main.grove"], "after the Grove's growth")
	assert_eq(first_archer, "encounter.ruins_gate", "the first archer guards the practice gate")
	# The stage-3 return leg's encounters wait for the king.
	for id: String in ["encounter.return_patrol", "encounter.village_ambush", "encounter.barrow_wardens"]:
		assert_true((GameData.get_record(id).get("requires_flags", []) as Array).has("world.ogre_king.defeated"),
			"%s waits for the Ogre King's defeat" % id)
	assert_true((GameData.get_record("encounter.village_ambush").get("requires_flags", []) as Array).has("faction.village.hostile"),
		"the ambush only waits for a hostile giant")
	assert_eq(GameData.get_record("encounter.kingsfall_boss").get("forbids_flags", []), ["world.ogre_king.defeated"],
		"the king never comes back")
	var commanders := _spawns().keys().filter(func(id: String) -> bool: return bool(_spawns()[id].commander))
	for id: String in ["valley.quarry.raider_captain", "valley.ruins.sergeant", "valley.ruins.patrol_captain"]:
		assert_true(commanders.has(id), "%s leads its encounter" % id)


# --------------------------------------------------------------------------- tutorial and village

func test_the_hollow_teaches_with_two_dummies_and_the_sparring_post() -> void:
	var scene := _scene()
	var hollow := (GameData.get_record(LEVEL).get("districts", []) as Array).filter(
		func(d: Dictionary) -> bool: return str(d.id) == "hollow")
	assert_eq(hollow.size(), 1, "the level has Giant's Hollow")
	var in_hollow := func(p: Vector3) -> bool:
		var d: Dictionary = hollow[0]
		return p.x >= float(d.min_m[0]) and p.x <= float(d.max_m[0]) and p.z >= float(d.min_m[2]) and p.z <= float(d.max_m[2])
	var dummies := (scene.dummies as Dictionary).keys().filter(func(id: String) -> bool: return in_hollow.call(scene.dummies[id].pos))
	assert_eq(dummies.size(), 2, "two practice dummies in the Hollow")
	var train: Dictionary = (GameData.get_record("quest.tutorial").get("stages", []) as Array)[1]
	for c: Dictionary in _conditions(train.complete_when, []):
		var targets: Array = c.get("targets", [])
		targets.sort()
		dummies.sort()
		assert_eq(targets, dummies, "the train stage counts blows on both dummies")
	var posts := _spawns().keys().filter(func(id: String) -> bool: return str(_spawns()[id].definition) == "enemy.sparring_post")
	assert_eq(posts.size(), 1, "one sparring post")
	if posts.size() == 1:
		assert_true(in_hollow.call(_spawns()[posts[0]].pos), "in the Hollow")
	assert_eq(str(GameData.get_record("tutorial.block").get("sets_flag", "")), "tutorial.block.done", "block teaches the spar stage")
	assert_eq(str(GameData.get_record("tutorial.dodge").get("sets_flag", "")), "tutorial.dodge.done", "and so does the dodge")
	assert_eq(str(GameData.get_record("tutorial.camera").get("sets_flag", "")), "tutorial.camera.done", "the camera the awaken stage")


func test_the_village_choice() -> void:
	var by_outcome := {}
	for n: Dictionary in GameData.get_record("dialogue.elder").get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			var e: Dictionary = c.get("effects", {})
			if str(e.get("outcome", "")) != "":
				by_outcome[str(e.outcome)] = e
	for o: String in ["offer_cache", "offer_ogre", "intimidate", "help_cache", "help_ogre"]:
		assert_true(by_outcome.has(o), "the elder's conversation reaches %s" % o)
	for o: String in ["help_cache", "help_ogre"]:
		var e: Dictionary = by_outcome.get(o, {})
		assert_eq(str(e.get("once_flag", "")), "reward.village.help", "%s: once-flag reward.village.help" % o)
		assert_eq(e.get("give_items", []), [{"item": "item.iron_ingot", "count": 2.0}], "%s: 2 iron" % o)
		assert_eq(e.get("learn_abilities", []), ["ability.ancestral_mend"], "%s: Ancestral Mend" % o)
		assert_eq(int(e.get("xp", 0)), 120, "%s: 120 XP" % o)
		assert_eq(str((e.get("set_flags", {}) as Dictionary).get("quest.village.outcome", "")), o, "%s sets its outcome" % o)
		assert_eq((e.get("set_flags", {}) as Dictionary).get("faction.village.gate_open"), true, "%s opens the bridge" % o)
	var cache: Dictionary = by_outcome.get("help_cache", {})
	assert_eq(cache.get("take_items", []), [{"item": "item.supply_cache", "count": 1.0}], "the cache is handed over")
	var im: Dictionary = by_outcome.get("intimidate", {})
	assert_eq(str(im.get("once_flag", "")), "reward.village.intimidate", "intimidate: once-flag reward.village.intimidate")
	assert_eq(im.get("learn_abilities", []), ["ability.thunder_roar"], "intimidate: Thunder Roar")
	assert_eq(int(im.get("xp", 0)), 40, "intimidate: 40 XP")
	assert_false(im.has("give_items"), "intimidate: no iron")
	assert_eq((im.get("set_flags", {}) as Dictionary).get("faction.village.stood_down"), true, "the guards stand down")
	assert_eq((im.get("set_flags", {}) as Dictionary).get("faction.village.gate_open"), true, "and open the bridge")
	# Every intimidation choice needs stage 2.
	for n: Dictionary in GameData.get_record("dialogue.elder").get("nodes", []):
		for c: Dictionary in n.get("choices", []):
			if str((c.get("effects", {}) as Dictionary).get("outcome", "")) == "intimidate":
				assert_eq(c.get("conditions", []), [{"type": "stage_at_least", "stage": 2.0}], "%s: intimidation needs stage 2" % n.id)
	# Force: only the smashed barricade sets it (and the village's hostility); nothing in the
	# conversation does, and the barricade opens for every other outcome.
	assert_false(by_outcome.has("force"), "no dialogue choice sets force")
	var barricade := GameData.get_record("prop.cart_barricade")
	assert_eq(barricade.get("on_destroyed_flags", {}), {"quest.village.outcome": "force", "faction.village.hostile": true},
		"the smashed barricade sets force and hostility")
	assert_eq(str(barricade.get("open_when_flag", "")), "faction.village.gate_open", "and opens for the other outcomes")
	assert_eq(int(barricade.get("min_growth_stage", 0)), 2, "it takes a stage-2 giant to smash it")
	assert_eq(int(barricade.get("xp_reward", 0)), 30, "for 30 XP")
	# The village smithy serves helpers only; the Giantforge everyone.
	var scene := _scene()
	assert_eq(scene.props["valley.village.forge"].get("requires_flag_values", {}),
		{"quest.village.outcome": ["help_cache", "help_ogre"]}, "the village forge serves helpers")
	assert_eq(scene.props["valley.ruins.giantforge"].get("requires_flag_values", {}), {}, "the Giantforge everyone")
