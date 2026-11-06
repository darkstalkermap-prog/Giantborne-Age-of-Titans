extends TestSuite
## The M7-M9 pre-declarations (P20; plan M6-M9 §1.5, §2.4, §2.12, §2.14, §2.15): every signal of
## §2.4 exists with its arguments and names its emitter in a comment above it; every enum value the
## later packages use exists; every registry entry P20 added sits where the plan puts it, under the
## folder the plan names, and a missing file is skipped silently; the six new schema modules load,
## accept the plan's example records and reject bad ones; the tutorial and Quests listen to the new
## tutorial events; LevelRoot.RUNTIME_NODES makes only what exists. (The anchors of §1.5 are
## test_anchors' job: tests/support/anchors_expected.gd lists them.)

## Signal -> its argument names, as plan §2.4 declares them.
const EVENTS := {
	"travel_requested": ["level_id", "checkpoint_id", "reason"],
	"level_leaving": ["tick", "from_level", "to_level", "reason"],
	"level_entered": ["tick", "level_id", "reason"],
	"world_chunk_loaded": ["chunk_id"],
	"world_chunk_unloading": ["chunk_id"],
	"world_chunk_unloaded": ["chunk_id"],
	"region_changed": ["tick", "region_id", "previous_id"],
	"poi_discovered": ["tick", "poi_id"],
	"quest_tracked": ["quest_id"],
	"size_gate_blocked": ["tick", "gate_id", "min_stage", "message"],
	"trampled": ["tick", "world_id", "entity_id"],
	"formation_changed": ["tick", "formation_id", "state"],
	"siege_engine_fired": ["tick", "engine_id", "action_id", "target_id"],
	"siege_engine_crewed": ["tick", "engine_id", "crewed"],
	"ability_evolved": ["tick", "from_id", "to_id", "slot_key"],
	"talent_learned": ["tick", "talent_id"],
	"ancestry_chosen": ["tick", "ancestry_id"],
	"boss_yielded": ["tick", "boss_id"],
	"boss_disengaged": ["tick", "boss_id", "reason"],
	"wander_spawned": ["tick", "template_id", "encounter_id"],
	"world_event_started": ["tick", "event_id"],
	"world_event_ended": ["tick", "event_id", "outcome"],
}

## DataValidator constant -> the values plan §2.12 / §2.15 adds (each must exist).
const ENUM_VALUES := {
	"HIT_SHAPES": ["line_pulse", "band_pulse"],
	"ARCHETYPES": ["troll", "rival_giant", "cavalry"],
	"SOLDIER_ROLES": ["line", "pike", "shield", "banner", "crew"],
	"SIZE_POLICIES": ["fixed"],
	"INTERACTION_PERMISSIONS": ["heave", "trample"],
	"STATUS_MODIFIERS": ["heal_received_mult", "stamina_cost_mult", "essence_cost_mult", "cooldown_mult",
		"poise_threshold_add", "poise_damage_taken_mult", "grab_reach_add", "fury_on_kill_add",
		"move_speed_mult", "elemental_resist_add", "health_add", "stamina_add", "essence_add",
		"heavy_damage_mult", "throw_damage_mult", "magic_damage_mult"],
	"STATUS_TAGS": ["Burning", "Regeneration"],
	"PROJECTILE_VISUALS": ["ballista_bolt", "catapult_stone", "rune_lance", "storm_bolt", "engine"],
	"OUTMATCHED_BEHAVIORS": ["crew", "charge"],
	"CONDITION_TYPES": ["count", "quest_done", "level_is", "discovered", "region_entered", "ancestry_is",
		"ancestry_chosen", "event_done", "near"],
	"BOT_ACTIONS": ["travel", "fast_travel", "discover", "breach", "protect", "duel", "choose_ancestry",
		"heave", "burn"],
	"TUTORIAL_EVENTS": ["poi_discovered", "region_changed", "formation_changed", "size_gate_blocked",
		"level_entered", "ability_evolved"],
	"POI_KINDS": ["settlement", "shrine", "waystone", "ruin", "landmark", "camp", "lair", "boss", "forge",
		"gate", "vista", "exit", "secret"],
	"FACTION_INITIAL": ["neutral", "hostile"],
	"FORGE_TIERS": ["iron", "titan"],
}

## The record types P20 adds to SCHEMA_PATHS, in order, right after tutorial_prompt (§1.6).
const NEW_TYPES := ["region", "poi", "faction", "talent", "wander_table", "world_event"]
const FACTION_SCHEMA := preload("res://scripts/core/schemas/faction_schema.gd")


func _consts(path: String) -> Dictionary:
	return (load(path) as GDScript).get_script_constant_map()


func _validate(rec: Dictionary) -> Dictionary:
	return DataValidator.validate_record(rec, "test.json")


func _errors(rec: Dictionary) -> String:
	return "\n".join(_validate(rec).errors)


# --------------------------------------------------------------------------- events

func test_every_campaign_and_world_signal_exists_with_its_arguments() -> void:
	var declared := {}
	for s: Dictionary in Events.get_signal_list():
		var names: Array = []
		for a: Dictionary in s.args:
			names.append(str(a.name))
		declared[str(s.name)] = names
	for sig: String in EVENTS:
		assert_true(Events.has_signal(sig), "Events.%s is declared" % sig)
		assert_eq(declared.get(sig, []), EVENTS[sig], "Events.%s has the plan's arguments" % sig)


func test_every_new_signal_names_its_emitter_above_the_package_anchors() -> void:
	var lines := FileAccess.get_file_as_string("res://scripts/core/events.gd").split("\n")
	var first_anchor := -1
	var signal_line := {}
	for i in lines.size():
		var line := lines[i].strip_edges()
		if first_anchor < 0 and line.begins_with("## @anchor "):
			first_anchor = i
		if line.begins_with("signal "):
			signal_line[line.substr(7).get_slice("(", 0).strip_edges()] = i
	assert_true(first_anchor > 0, "events.gd has its package anchors")
	assert_true(FileAccess.get_file_as_string("res://scripts/core/events.gd").contains("campaign and world (M7-M9)"),
		"the block is titled as the plan says")
	for sig: String in EVENTS:
		assert_true(signal_line.has(sig), "%s is declared in events.gd" % sig)
		if not signal_line.has(sig):
			continue
		var at: int = signal_line[sig]
		assert_true(at < first_anchor, "%s sits in the block above the package anchors" % sig)
		# The comment lines directly above the signal name its emitter.
		var comment := ""
		var j := at - 1
		while j >= 0 and lines[j].strip_edges().begins_with("##"):
			comment = lines[j] + "\n" + comment
			j -= 1
		assert_true(comment.contains("Emitter:"), "%s names its emitter in its comment: %s" % [sig, comment])


# --------------------------------------------------------------------------- enums

func test_every_pre_declared_enum_value_exists() -> void:
	var consts := _consts("res://scripts/core/data_validator.gd")
	for enum_name: String in ENUM_VALUES:
		assert_true(consts.has(enum_name), "DataValidator.%s exists" % enum_name)
		var values: Array = consts.get(enum_name, [])
		for v: String in ENUM_VALUES[enum_name]:
			assert_true(values.has(v), "DataValidator.%s has '%s'" % [enum_name, v])
	# The old values stay (nothing was renamed): a sample of each list.
	assert_true((consts.HIT_SHAPES as Array).has("cylinder_pulse"), "HIT_SHAPES keeps cylinder_pulse")
	assert_true((consts.ARCHETYPES as Array).has("ogre"), "ARCHETYPES keeps ogre")
	assert_true((consts.CONDITION_TYPES as Array).has("flag"), "CONDITION_TYPES keeps flag")
	assert_true((consts.BOT_ACTIONS as Array).has("talk"), "BOT_ACTIONS keeps talk")


func test_the_new_tutorial_events_are_events_the_tutorial_and_quests_hear() -> void:
	for e: String in ENUM_VALUES.TUTORIAL_EVENTS:
		assert_true(Events.has_signal(e), "tutorial event %s is an Events signal" % e)
		var heard := false
		for c: Dictionary in Events.get_signal_connection_list(e):
			if (c.callable as Callable).get_object() == Quests:
				heard = true
		assert_true(heard, "Quests listens to %s (the tutorial's dismiss and trigger events)" % e)


# --------------------------------------------------------------------------- registries

func test_schema_paths_gain_the_six_types_after_tutorial_prompt() -> void:
	var keys: Array = DataValidator.SCHEMA_PATHS.keys()
	var at := keys.find("tutorial_prompt")
	assert_true(at >= 0, "tutorial_prompt is registered")
	for i in NEW_TYPES.size():
		var t: String = NEW_TYPES[i]
		assert_eq(keys.find(t), at + 1 + i, "%s comes %d after tutorial_prompt (plan §1.6)" % [t, i + 1])
		assert_eq(str(DataValidator.SCHEMA_PATHS.get(t, "")), "res://scripts/core/schemas/%s_schema.gd" % t,
			"%s's module path" % t)
		assert_true(DataValidator.SCHEMAS.has(t), "the %s module is loaded" % t)
		assert_true(DataValidator.RECORD_TYPES.has(t), "%s records can be validated" % t)
	var missing := DataValidator.build_registry({"no_such_type": "res://scripts/core/schemas/no_such_type_schema.gd"})
	assert_true(missing.is_empty(), "a declared module whose file is missing is skipped silently")


func test_builders_are_declared_in_the_plan_order() -> void:
	var b: Array = _consts("res://tools/build_scenes.gd").BUILDERS
	var at := func(builder: String) -> int: return b.find("res://tools/builders/%s.gd" % builder)
	assert_eq(at.call("world_props2"), at.call("world_props") + 1, "world_props2 (P26) right after world_props")
	assert_eq(at.call("formations"), at.call("npcs") + 1, "formations (P30) after npcs")
	assert_eq(at.call("siege"), at.call("npcs") + 2, "then siege (P32)")
	assert_eq(at.call("big"), at.call("npcs") + 3, "then big (P34)")
	assert_eq(at.call("test_world"), at.call("stress") + 1, "test_world (P24a) after stress")
	assert_eq(at.call("world"), at.call("main") - 1, "world (P25) right before main")
	assert_true(at.call("valley") >= 0 and at.call("valley") < at.call("world"), "the Valley builds before the world")
	for path: String in b:
		assert_true(path.begins_with("res://tools/builders/") and path.ends_with(".gd"),
			"%s is a builder script under tools/builders/" % path)


func test_screens_hotkeys_widgets_tabs_and_runtime_nodes() -> void:
	var screens := {"map": "res://ui/screens/map_screen.gd", "journal": "res://ui/screens/journal_screen.gd",
		"ancestry": "res://ui/screens/ancestry_screen.gd", "yield": "res://ui/screens/yield_prompt.gd"}
	for s: String in screens:
		assert_eq(str(ScreenStack.SCREENS.get(s, "")), screens[s], "ScreenStack.SCREENS[%s]" % s)
	assert_eq(str(ScreenStack.HOTKEYS.get("map", "")), "map", "the map hotkey opens the map")
	assert_eq(str(ScreenStack.HOTKEYS.get("journal", "")), "journal", "the journal hotkey opens the journal")
	assert_eq(str(ScreenStack.HOTKEYS.get("inventory", "")), "inventory", "the inventory hotkey stays")
	var stack := ScreenStack.new()
	add_child(stack)
	for s: String in screens:
		if not ResourceLoader.exists(str(screens[s])):
			assert_true(stack.open(s) == null, "%s is skipped silently while its script is missing" % s)
	assert_false(stack.any_open(), "nothing opened")
	stack.free()
	var widgets: Array = HudWidgets.WIDGETS
	var marker := widgets.find("res://ui/hud/objective_marker.gd")
	for w: String in ["compass", "region_banner", "discovery_toast"]:
		var i := widgets.find("res://ui/hud/%s.gd" % w)
		assert_true(i >= 0 and i < marker, "HudWidgets.WIDGETS has %s below the edge overlays" % w)
	var tabs := {}
	for t: Array in ShrineScreen.TABS:
		tabs[str(t[0])] = str(t[1])
	assert_eq(str(tabs.get("Talents", "")), "res://ui/screens/shrine/talents_tab.gd", "the Talents tab (P33)")
	assert_eq(str(tabs.get("Ancestry", "")), "res://ui/screens/shrine/ancestry_tab.gd", "the Ancestry tab (P33)")
	var runtime := {}
	for e: Array in LevelRoot.RUNTIME_NODES:
		runtime[str(e[0])] = e
	assert_eq(str((runtime.get("Discovery", ["", ""]) as Array)[1]), "res://scripts/world/discovery.gd", "Discovery (P27)")
	assert_eq((runtime.get("Discovery", ["", "", []]) as Array)[2], ["level.valley", "level.world"],
		"Discovery serves both campaign levels")
	assert_eq(str((runtime.get("WanderDirector", ["", ""]) as Array)[1]), "res://scripts/world/wander_director.gd",
		"WanderDirector (P37)")
	assert_eq((runtime.get("WanderDirector", ["", "", []]) as Array)[2], ["level.world"], "the world only")
	var last: Array = ResetHooks.AFTER_EACH.back()
	assert_eq(last, ["script", "res://scripts/world/world_index.gd", "clear_cache"],
		"ResetHooks.AFTER_EACH ends with the world index cache (plan §2.15)")


func test_runtime_nodes_are_made_once_and_only_when_their_script_exists() -> void:
	var root := LevelRoot.new()
	root.level_id = "level.test_p20_runtime"
	add_child(root)
	assert_true(root.create_runtime_nodes().is_empty(), "the real registry serves no test level")
	var entries := [
		["RuntimeProbe", "res://scripts/world/level_marker.gd", ["level.test_p20_runtime"]],
		["MissingProbe", "res://scripts/world/no_such_runtime_node.gd", ["level.test_p20_runtime"]],
		["OtherLevelProbe", "res://scripts/world/level_marker.gd", ["level.other"]],
	]
	var made := root.create_runtime_nodes(entries)
	assert_eq(made.size(), 1, "only the entry whose script exists and that serves this level")
	assert_true(root.get_node_or_null("RuntimeProbe") is LevelMarker, "made as a child of the root, by name")
	assert_true(root.get_node_or_null("MissingProbe") == null, "a missing script is skipped silently")
	assert_true(root.get_node_or_null("OtherLevelProbe") == null, "another level's node is not made")
	assert_true(root.create_runtime_nodes(entries).is_empty(), "a second call keeps the node it made")
	root.free()


# --------------------------------------------------------------------------- the new schema modules

func _region() -> Dictionary:
	return {"schema_version": 1, "id": "region.greywood", "type": "region", "display_name": "The Greywood",
		"level": "level.world", "tier": 2, "recommended_stage": [4, 5],
		"bounds_m": [[-896, -440], [-320, 300]], "surface": "soft", "discover_xp": 40,
		"faction": "faction.woodfolk", "map_tint": [0.33, 0.47, 0.33], "fog_color": [0.52, 0.6, 0.55],
		"skyline_tint": [0.22, 0.33, 0.24], "wander_table": "wander.greywood",
		"m7_note": "The woodfolk and their troubles come with the next build."}


func _poi() -> Dictionary:
	return {"schema_version": 1, "id": "poi.hollowmere", "type": "poi", "display_name": "Hollowmere",
		"level": "level.world", "region": "region.greywood", "kind": "settlement",
		"position_m": [-640, 22, -40], "radius_m": 70, "xp": 40, "map_icon": "settlement",
		"compass": true, "landmark": "world.greywood.hollowmere_hall", "skyline": true, "min_stage": 0,
		"reveals_m": 0, "max_inner_stage": 4, "green_m": [-610, 20, 20],
		"note": "The woodfolk's stilt village on the black pond."}


func _faction() -> Dictionary:
	return {"schema_version": 1, "id": "faction.brannock", "type": "faction", "display_name": "Brannock",
		"flag_prefix": "faction.brannock", "initial": "neutral", "offences_to_hostile": 2, "offence_window_s": 30,
		"civilians_give_way": true, "give_way_m": 3.0,
		"reconcile": {"talker": "world.crownmarch.edda", "cost": [{"item": "item.iron_ingot", "count": 2}],
			"text": "Pay for the gate you broke (2 iron)"},
		"warn_text": "Brannock's folk scatter from your feet. Strike again and the town will fight you.",
		"hostile_text": "Brannock's bells ring: the town takes up arms.",
		"stood_down_text": "Brannock's guards lower their pikes.",
		"reconciled_text": "Brannock forgives the gate, if not the fright."}


func _talent() -> Dictionary:
	return {"schema_version": 1, "id": "talent.destroyer_shoulder_charge", "type": "talent",
		"display_name": "Shoulder Charge", "tree": "destroyer", "tier": 2, "cost": 1,
		"requires": ["talent.destroyer_heavy_hands"], "requires_level": 8,
		"effects": {"modifiers": {"heavy_damage_mult": 1.1}, "grants": ["ability.shoulder_charge"], "replaces": {}}}


func _wander() -> Dictionary:
	return {"schema_version": 1, "id": "wander.aldmere", "type": "wander_table", "region": "region.aldmere",
		"max_active": 2, "interval_s": [60, 120], "min_distance_m": 120, "max_distance_m": 220,
		"anchors": "roads", "xp_full_spawns": 3,
		"entries": [{"id": "patrol_line", "weight": 3, "min_stage": 3, "max_stage": 3, "template": "encounter.tpl_aldmere_patrol"},
			{"id": "pike_column", "weight": 3, "min_stage": 4, "max_stage": 6, "template": "encounter.tpl_pike_column",
				"path": "world.patrol.kings_road", "requires_flags": [], "forbids_flags": ["oath.crown.outcome"]}]}


func _world_event() -> Dictionary:
	return {"schema_version": 1, "id": "event.hollowmere_raid", "type": "world_event", "display_name": "Raid on Hollowmere",
		"level": "level.world", "region": "region.greywood", "centre_m": [-640, 22, -40], "start_radius_m": 200,
		"trigger": {"min_stage": 4, "max_stage": 6, "requires_flags": [], "forbids_flags": ["event.hollowmere_raid.done"],
			"conditions": [{"type": "quest_done", "quest": "quest.main"}], "cooldown_s": 600},
		"encounters": ["encounter.hollowmere_raiders"],
		"objective": {"kind": "protect", "targets": ["world.greywood.hollowmere_hall"], "lost_to_fail": 2},
		"fail": {"timer_s": 240, "conditions": []}, "path": "", "speed_mps": 0,
		"outcomes": {"saved": {"set_flags": {"event.hollowmere_raid.saved": true}, "xp": 80, "items": []},
			"burned": {"set_flags": {"event.hollowmere_raid.burned": true}}}}


func test_the_plan_examples_validate() -> void:
	for rec: Dictionary in [_region(), _poi(), _faction(), _talent(), _wander(), _world_event()]:
		var r := _validate(rec)
		assert_eq(r.errors.size(), 0, "%s validates: %s" % [rec.id, "\n".join(r.errors)])
	var refs: Array = _validate(_talent()).refs
	var ref_ids := []
	for ref: Dictionary in refs:
		ref_ids.append(str(ref.id))
	assert_true(ref_ids.has("talent.destroyer_heavy_hands") and ref_ids.has("ability.shoulder_charge"),
		"a talent's requires and grants are references: %s" % [ref_ids])
	assert_eq(FACTION_SCHEMA.state_flag(_faction(), "hostile"), "faction.brannock.hostile",
		"a faction state's flag is <flag_prefix>.<state>")


func test_the_new_modules_reject_bad_records() -> void:
	var r := _region()
	r.surface = "lava"
	r.bounds_m = [[0, 0], [-10, 10]]
	r.recommended_stage = [5, 4]
	r.map_tint = [1.5, 0, 0]
	var e := _errors(r)
	assert_true(e.contains("surface"), "a region's surface is soft | hard | wet: %s" % e)
	assert_true(e.contains("bounds_m"), "bounds need min < max: %s" % e)
	assert_true(e.contains("recommended_stage"), "lowest <= highest: %s" % e)
	assert_true(e.contains("map_tint"), "colours lie in 0..1: %s" % e)
	var p := _poi()
	p.kind = "castle"
	assert_true(_errors(p).contains("kind"), "a POI kind is one of POI_KINDS")
	p = _poi()
	p.kind = "secret"
	p.min_stage = 0
	e = _errors(p)
	assert_true(e.contains("min_stage >= 1") and e.contains("seal"), "a secret needs min_stage and its seal: %s" % e)
	p = _poi()
	p.erase("landmark")
	assert_true(_errors(p).contains("skyline needs a landmark"), "a skyline POI needs its landmark")
	p = _poi()
	p.erase("green_m")
	assert_true(_errors(p).contains("go together"), "green_m and max_inner_stage go together")
	var f := _faction()
	f.initial = "angry"
	assert_true(_errors(f).contains("initial"), "a faction starts neutral or hostile")
	f = _faction()
	f.id = "brannock.faction"
	assert_true(_errors(f).contains("start with 'faction.'"), "faction ids start with faction.")
	var t := _talent()
	t.tree = "berserker"
	t.effects.modifiers = {"not_a_modifier": 1.0}
	e = _errors(t)
	assert_true(e.contains("tree"), "a talent's tree is destroyer | guardian | primordial: %s" % e)
	assert_true(e.contains("not_a_modifier"), "talent modifiers use STATUS_MODIFIERS keys only: %s" % e)
	t = _talent()
	t.requires = ["talent.destroyer_shoulder_charge"]
	assert_true(_errors(t).contains("cannot require itself"), "a talent never requires itself")
	var w := _wander()
	w.entries = []
	assert_true(_errors(w).contains("at least one entry"), "a wander table has entries")
	w = _wander()
	w.interval_s = [120, 60]
	w.entries[1].min_stage = 6
	w.entries[1].max_stage = 4
	e = _errors(w)
	assert_true(e.contains("interval_s") and e.contains("min_stage must be <= max_stage"), "ranges in order: %s" % e)
	var ev := _world_event()
	ev.objective.kind = "capture"
	ev.trigger.conditions = [{"type": "count", "of": []}]
	ev.outcomes["Not A Word"] = {}
	e = _errors(ev)
	assert_true(e.contains("objective.kind"), "an event objective is protect | destroy | defeat | survive | escort: %s" % e)
	assert_true(e.contains("trigger.conditions"), "its trigger conditions are checked like any condition: %s" % e)
	assert_true(e.contains("Not A Word"), "outcome names are plain words: %s" % e)
