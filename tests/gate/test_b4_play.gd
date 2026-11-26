extends IntegrationSuite
## B4 (the milestone B gate; docs/systems/B4.md): milestone B through the game's own paths, from saves the shipped
## 0.14.0-m14 build wrote (tests/fixtures/saves/v3_m14_*.json: test_b4_saves says how they were made).
##   * Armour end to end in the Valley: the 0.14 mid-Valley save (its reserved empty equipment block) Continued
##     through the title's path; a piece made at the Giantforge (the materials paid once; made again, or short of
##     materials, refused with nothing spent); worn through the Character menu's rule, its passives counted once
##     however often they are rebuilt; a growth, a new look from the creator (the record never holds the armour, the
##     look keeps it; a cutscene's giant wears it too) and a checkpoint, then Continued again: the same numbers, the
##     same pieces, the same look.
##   * The Ogre King's fall from that save: his arena engaged, his death - his record slain once, his parts in the
##     pack once, Thornwick's trophy stand shown, the Kingsfall helm made at the Giantforge - and after a checkpoint
##     and a Continue nothing given or shown twice.

const FIXTURE_DIR := "res://tests/fixtures/saves/"
const VALLEY_FIXTURE := "v3_m14_valley"
const GIANTFORGE := Vector3(175.0, 0.05, -100.0)

var level: Node3D = null


func after_each() -> void:
	Quests.end_dialogue()
	if level != null and is_instance_valid(level):
		level.queue_free()
	level = null
	await get_tree().process_frame
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	SaveSlots.delete_slot(true)
	GameSession.persist = false
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## The session's save Continued as the title does, its level loaded as main.gd loads it.
func _continue() -> GiantPlayer:
	if level != null and is_instance_valid(level):
		level.queue_free()
		level = null
		await get_tree().process_frame
		await get_tree().process_frame
	var r := GameSession.continue_valley()
	assert_true(r.ok, "Continue (%s)" % r.message)
	WanderDirector.view_probe = func(_p: Vector3) -> bool: return false
	level = (load(GameSession.scene_for_level(GameSession.level_id)) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer if level.has_node("Player") else \
		get_tree().get_first_node_in_group("player") as GiantPlayer
	p.router.use_injection = true
	GameSession.on_level_ready(level, p)
	await step_ticks(30)
	return p


func _put_fixture(edit: Callable) -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE_DIR + VALLEY_FIXTURE + ".json"))
	edit.call(doc)
	GameSession.persist = true
	_write_text(SaveSlots.path(), JSON.stringify(doc))


func _forge(id: String) -> Forge:
	for n in get_tree().get_nodes_in_group("forges"):
		if n is Forge and str((n as Forge).world_id) == id:
			return n
	for n in level.find_children("*", "Forge", true, false):
		if str((n as Forge).world_id) == id:
			return n
	return null


func _checkpoint(p: GiantPlayer) -> void:
	GameSession.request_checkpoint("b4_play")
	var taken: bool = await TestWait.until(self, func() -> bool: return GameSession.pending_checkpoint().is_empty(), 240)
	assert_true(taken, "a checkpoint is written (%s)" % [GameSession.checkpoint_blockers()])
	assert_true(p.entity.is_alive(), "(the giant alive)")


func _armour_now(p: GiantPlayer) -> float:
	return p.entity.combatant.modifier("armor_flat")


func test_armour_end_to_end_from_a_0_14_valley_save() -> void:
	_put_fixture(func(doc: Dictionary) -> void:
		doc.world.inventory["item.iron_ingot"] = 3
		doc.world.inventory["item.hide"] = 1)
	var p := await _continue()
	var eq0 := Armour.normalized(GameSession.expansion.equipment)
	assert_true((eq0.pieces as Dictionary).is_empty(), "0.14's reserved empty block: nothing owned")
	var bare := _armour_now(p)
	var bare_health := p.entity.combatant.pools.health_max
	# made at the Giantforge (any forge makes the Iron set)
	p.global_position = GIANTFORGE
	await step_ticks(5)
	var forge := _forge("valley.ruins.giantforge")
	assert_true(forge != null, "the Giantforge is in the Valley")
	if forge == null:
		return
	var made := forge.craft(p, "recipe.iron_hauberk")
	assert_true(bool(made.ok), "the hauberk made (%s)" % made.message)
	assert_eq(WorldState.count_of("item.iron_ingot"), 0, "three ingots paid, once")
	var again := forge.craft(p, "recipe.iron_hauberk")
	assert_eq(str(again.reason), "owned", "made again: refused")
	var short := forge.craft(p, "recipe.iron_nasal_helm")
	assert_eq(str(short.reason), "missing_items", "short of ingots: refused")
	assert_eq(WorldState.count_of("item.hide"), 1, "and nothing spent")
	assert_false(Armour.owns(GameSession.expansion.equipment, "armour.iron_nasal_helm"), "nor made")
	# worn through the Character menu's rule; its passives once, however often rebuilt
	assert_true(bool(CharacterScreen.apply_option(p, "chest", "armour.iron_hauberk").ok), "put on")
	var worn := _armour_now(p)
	var want := float(Armour.modifiers(GameSession.expansion.equipment).modifiers.get("armor_flat", 0.0))
	assert_near(worn - bare, want, 1e-4, "its armour counted once (%.1f)" % want)
	for i in 3:
		p.progression.rebuild_passives()
		Armour.refresh_player(p)
	CharacterScreen.apply_option(p, "chest", "-")
	CharacterScreen.apply_option(p, "chest", "armour.iron_hauberk")
	assert_near(_armour_now(p), worn, 1e-4, "rebuilt, taken off and put on again: still once")
	assert_true(p.appearance.look().get("garments", []).size() > 0, "(a look)")
	var record_before: Dictionary = p.appearance.record()
	# a growth
	var stage := p.current_growth_stage()
	p.growth.debug_set_stage(stage + 1)
	await step_ticks(5)
	assert_eq(p.current_growth_stage(), stage + 1, "grown")
	assert_near(_armour_now(p), worn, 1e-4, "grown: the same armour")
	# a new look from the creator: the record never holds the armour, the look keeps it
	var rec := record_before.duplicate(true)
	rec.outfit.slots["armour"] = {"item": "", "dye": ""}
	p.appearance.set_record(rec)
	assert_false(JSON.stringify(p.appearance.record()).contains("iron_hauberk"), "the record holds no armour")
	assert_near(_armour_now(p), worn, 1e-4, "a new look: the same armour")
	var armour_slot := ""
	for g: Dictionary in p.appearance.look().get("garments", []):
		armour_slot += str(g.get("mesh", "")) + " "
	assert_true(armour_slot.to_lower().contains("mail") or armour_slot.to_lower().contains("hauberk"),
		"the hauberk drawn over the new look (%s)" % armour_slot)
	# the cutscenes show the giant as it is drawn: its armour too (a titan's intro, the intro replayed)
	assert_eq(CutsceneScreen.giant_look(), p.appearance.look(), "a cutscene's giant wears what the giant wears")
	# a checkpoint and a Continue: the same
	await _checkpoint(p)
	var saved := SaveSlots.read()
	assert_false(JSON.stringify(saved.data.character.get("appearance", {})).contains("hauberk"),
		"the saved look holds no armour")
	var p2 := await _continue()
	assert_true(Armour.owns(GameSession.expansion.equipment, "armour.iron_hauberk"), "still owned")
	assert_eq(str(GameSession.expansion.equipment.slots.chest), "armour.iron_hauberk", "still worn")
	assert_near(_armour_now(p2), worn, 1e-4, "Continued: the same armour, once")
	assert_eq(WorldState.count_of("item.iron_ingot"), 0, "the ingots still spent")
	assert_eq(WorldState.count_of("item.hide"), 1, "the hide still held")
	assert_eq(p2.current_growth_stage(), stage + 1, "its stage")
	assert_true(p2.entity.combatant.pools.health_max >= bare_health, "(its health)")


func test_the_kings_fall_from_a_0_14_valley_save_gives_once() -> void:
	_put_fixture(func(_doc: Dictionary) -> void: pass)
	var p := await _continue()
	assert_false(WorldState.is_killed("valley.arena.ogre_king"), "he stands")
	var arena: BossArena = null
	for n in get_tree().get_nodes_in_group(BossArena.GROUP):
		if (n as BossArena).boss_id == "valley.arena.ogre_king":
			arena = n
	assert_true(arena != null, "his arena")
	if arena == null:
		return
	TitanDuel.prepare(p, 3)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	p.global_position = arena.global_position + Vector3(0, 0.05, -20)
	await step_ticks(10)
	arena.engage()
	await step_ticks(10)
	var king := arena.boss() as TitanEnemy
	assert_true(king != null and arena.state_name() == "engaged", "engaged")
	if king == null:
		return
	king.break_plate("crown")
	king.break_plate("bell")
	var h := HitEvent.new()
	h.attacker_id = p.entity.entity_id
	h.target_id = king.entity.entity_id
	h.power = 1000000.0
	h.attacker_stat = 10.0
	h.attacker_height_m = p.entity.combatant.height_m
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee"])
	h.attacker_position = king.global_position + Vector3(0, 0, -3)
	Sim.queue_hit(h)
	await TestWait.until(self, func() -> bool: return not king.entity.is_alive(), 120)
	await step_ticks(30)
	assert_true(QuestConditions.truthy(WorldState.get_flag("world.ogre_king.defeated")), "his defeated flag")
	var rec: Dictionary = GameSession.expansion.titans.get("titan.ogre_king", {})
	assert_eq(str(rec.get("state", "")), ExpansionState.STATE_SLAIN, "his record: slain")
	assert_eq(int(rec.get("kills", 0)), 1, "once")
	assert_eq(WorldState.count_of("item.ogre_hide"), 4, "four cuts of his hide")
	assert_eq(WorldState.count_of("item.ogre_crown_iron"), 2, "his crown's iron and the broken crown's")
	assert_eq(WorldState.count_of("item.kings_bell_bronze"), 2, "the bell's bronze and the broken bell's")
	var after := level.get_node_or_null("Aftermath") as FlagVisibility
	assert_true(after != null and after.visible, "Thornwick's trophy stand shown")
	await _checkpoint(p)
	var p2 := await _continue()
	assert_eq(WorldState.count_of("item.ogre_hide"), 4, "Continued: his hide not given again")
	assert_eq(int((GameSession.expansion.titans.get("titan.ogre_king", {}) as Dictionary).get("kills", 0)), 1,
		"his record: one kill")
	var stand := level.get_node_or_null("Aftermath") as FlagVisibility
	assert_true(stand != null and stand.visible, "the stand still shown")
	assert_eq(stand.find_children("*", "TrophyDisplay", true, false).size(), 5, "his five pieces on it, once")
	# (C4: the bell hung in Thornwick's frame is a sixth display, hidden until the village raises it)
	var frame := level.get_node_or_null("SettlementC4") as FlagVisibility
	assert_true(frame != null and not frame.visible, "the bell's frame not raised yet")
	p2.global_position = GIANTFORGE
	await step_ticks(5)
	WorldState.add_item("item.iron_ingot", 1, "test")
	var forge := _forge("valley.ruins.giantforge")
	var helm := forge.craft(p2, "recipe.kingsfall_helm") if forge != null else {}
	assert_true(bool(helm.get("ok", false)), "the Kingsfall helm made at the Giantforge (%s)" % helm.get("message", ""))
	var twice := forge.craft(p2, "recipe.kingsfall_helm") if forge != null else {}
	assert_eq(str(twice.get("reason", "")), "owned", "once")
