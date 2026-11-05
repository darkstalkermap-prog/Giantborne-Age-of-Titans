extends IntegrationSuite
## Inventory, the forge upgrade and loot (plan §3.14): the forge consumes 2 iron once, equips the
## reinforced club, and a light on the dummy rises from 37 to round(46 x 1.15 x 100 / 125) = 42; the
## reinforced club is not "too small" at stage 3; a second upgrade is refused; the village forge
## refuses without a help outcome; the forge screen through the real E key; crates roll their loot
## table (and a placed crate's own table) once per world id; a soldier spawned with loot.raider
## drops from it, once per entity id even after a reload; the inventory screen's items, weapons
## (Equip, "(too small)"), loadout and talent points, and its refusal in combat (the I hotkey).

const FORGE := "res://scenes/world/forge.tscn"
const CRATE := "res://scenes/world/crate.tscn"
const VILLAGE_VALUES := {"quest.village.outcome": ["help_cache", "help_ogre"]}

var upgrades: Array = []
var messages: Array[String] = []
var stack: ScreenStack


func before_each() -> void:
	await super()
	upgrades.clear()
	messages.clear()
	stack = null
	Events.upgrade_applied.connect(_on_upgrade)
	Events.hud_message.connect(_on_message)


func after_each() -> void:
	for sig: Signal in [Events.upgrade_applied, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	if stack != null and is_instance_valid(stack):
		stack.close_all()
	stack = null
	await super()


func _on_upgrade(_tick: int, from_weapon: String, to_weapon: String) -> void:
	upgrades.append([from_weapon, to_weapon])


func _on_message(text: String, _kind: String) -> void:
	messages.append(text)


## A forge whose front (the anvil side, -Z) faces `pos` + (0, 0, 1): the giant at the origin stands
## in front of a forge placed at (0, 0, -5).
func _forge(pos: Vector3, world_id := "test.forge", values := {}, flags := PackedStringArray()) -> Forge:
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = world_id
	f.requires_flag_values = values
	f.requires_flags = flags
	f.position = pos
	f.rotation.y = PI
	world.add_child(f)
	return f


func _crate(pos: Vector3, world_id: String, table := "") -> BreakableProp:
	var c := (load(CRATE) as PackedScene).instantiate() as BreakableProp
	c.world_id = world_id
	c.loot_table = table
	c.position = pos
	world.add_child(c)
	return c


func _grounded_player(pos := Vector3(0, 0.05, 0), yaw := 0.0) -> GiantPlayer:
	var p := spawn_player(pos, yaw)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _stack() -> ScreenStack:
	var layer := CanvasLayer.new()
	world.add_child(layer)
	stack = ScreenStack.new()
	layer.add_child(stack)
	return stack


## One light swing at the dummy 2.6 m ahead; its damage (crits off: the worked example's numbers).
func _light_damage(p: GiantPlayer, dummy_id: String) -> int:
	var before := hits_on(dummy_id).size()
	p.router.inject_light_attack()
	await step_ticks(45)
	var on := hits_on(dummy_id)
	assert_eq(on.size(), before + 1, "the light lands once on %s" % dummy_id)
	return on.back().health_damage if on.size() > before else -1


# --------------------------------------------------------------------------- the forge

func test_the_forge_reforges_the_club_once_and_damage_rises_15_percent() -> void:
	var p := await _grounded_player()
	p.entity.combatant.crit_chance = 0.0
	spawn_dummy(Vector3(0, 0, -2.6), "test.dummy_forge")
	var f := _forge(Vector3(10, 0, 0))
	await step_ticks(2)
	assert_eq(await _light_damage(p, "test.dummy_forge"), 37, "the Oak Club's light on the dummy: 37")
	var no_iron := f.can_upgrade(p)
	assert_false(no_iron.ok, "no iron yet")
	assert_eq(str(no_iron.reason), "missing_items", "missing items")
	assert_eq([str(no_iron.from), str(no_iron.to)], ["weapon.club", "weapon.club_reinforced"], "the offer")
	assert_true(str(no_iron.message).contains("2 Iron Ingot (you have 0)"), "the message names the cost (%s)" % no_iron.message)
	WorldState.add_item("item.iron_ingot", 3, "test")
	var r := f.upgrade(p)
	assert_true(r.ok, "the forge reforges the club (%s)" % r.message)
	assert_eq(WorldState.count_of("item.iron_ingot"), 1, "two of three ingots consumed")
	assert_eq(p.equipment.weapon_id(), "weapon.club_reinforced", "the reinforced club is equipped")
	assert_eq(p.equipment.owned(), PackedStringArray(["weapon.club_reinforced"]), "the old club is no longer owned")
	assert_eq(upgrades, [["weapon.club", "weapon.club_reinforced"]], "upgrade_applied")
	assert_true(messages.has("Reforged: Reinforced Club"), "a HUD line")
	await step_ticks(30)
	assert_eq(await _light_damage(p, "test.dummy_forge"), 42, "the reinforced light: round(46 x 1.15 x 100 / 125) = 42")
	var again := f.upgrade(p)
	assert_false(again.ok, "a second upgrade is refused")
	assert_eq(str(again.reason), "no_upgrade", "the reinforced club has no upgrade of its own")
	assert_eq(WorldState.count_of("item.iron_ingot"), 1, "and costs nothing")
	assert_eq(upgrades.size(), 1, "no second upgrade_applied")
	assert_true(p.growth.debug_set_stage(3).ok, "grown to stage 3")
	assert_false(p.equipment.is_too_small(), "the reinforced club is not too small at stage 3")
	assert_near(p.current_weapon_scale(), 2.1667, 1e-4, "it scales with the stage-3 giant")
	assert_eq(p.equipment.weapon_label("weapon.club_reinforced"), "Reinforced Club", "no (too small) label")
	assert_eq(PlayerEquipment.too_small_at(GameData.get_record("weapon.club"), 3), true, "the plain club would be")


func test_the_forge_screen_through_the_interact_key() -> void:
	var p := await _grounded_player(Vector3(0, 0.05, 0))
	var f := _forge(Vector3(0, 0, -5))
	_stack()
	await step_ticks(8)
	assert_eq(p.interact.current_prompt(), "Reforge at the Giantforge", "the prompt")
	p.router.inject_edge(&"interact")
	await step_ticks(1)   # the screen opens deferred and pauses the game: no more ticks after it
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(stack.is_open("forge"), "E opens the forge screen")
	var screen := stack.top() as ForgeScreen
	if screen == null:
		return
	assert_true(get_tree().paused, "it pauses the game")
	assert_eq(screen.info_text(), "Oak Club -> Reinforced Club: x1.15 damage, fits a stage-3 giant.", "the offer")
	assert_true(screen.reforge_button.disabled, "Reforge is disabled without iron")
	assert_true(screen.status_text().contains("Iron Ingot"), "and says why")
	WorldState.add_item("item.iron_ingot", 2, "test")
	screen.refresh()
	assert_false(screen.reforge_button.disabled, "with two ingots it is enabled")
	var out := screen.press_reforge()
	assert_true(out.ok, "Reforge")
	assert_eq(p.equipment.weapon_id(), "weapon.club_reinforced", "reforged while the game is paused")
	assert_eq(screen.info_text(), "Reinforced Club: it cannot be reforged any further.", "nothing more to reforge")
	assert_true(screen.reforge_button.disabled, "Reforge is disabled again")
	stack.close_all()
	assert_false(get_tree().paused, "closing it unpauses")
	assert_eq(f.last_result.get("to", ""), "weapon.club_reinforced", "the forge's last result")


func test_the_village_forge_needs_a_help_outcome() -> void:
	var p := await _grounded_player()
	var f := _forge(Vector3(0, 0, -5), "test.village_forge", VILLAGE_VALUES)
	f.closed_message = "Thornwick's smith works only for friends of the village."
	_stack()
	WorldState.add_item("item.iron_ingot", 2, "test")
	await step_ticks(8)
	assert_false(f.is_open(), "closed without an outcome")
	assert_eq(str(f.can_upgrade(p).reason), "closed", "can_upgrade: closed")
	assert_false(f.upgrade(p).ok, "upgrade refused")
	p.router.inject_edge(&"interact")
	await step_ticks(2)
	await get_tree().process_frame
	assert_false(stack.is_open("forge"), "E does not open a closed forge")
	assert_true(messages.has("Thornwick's smith works only for friends of the village."), "it shows the closed message")
	WorldState.set_flag("quest.village.outcome", "intimidate")
	assert_false(f.is_open(), "intimidation does not open it")
	WorldState.set_flag("quest.village.outcome", "force")
	assert_false(f.is_open(), "neither does force")
	WorldState.set_flag("quest.village.outcome", "help_ogre")
	assert_true(f.is_open(), "helping with the ogre opens it")
	assert_true(f.upgrade(p).ok, "and it reforges")
	assert_eq(WorldState.count_of("item.iron_ingot"), 0, "for the two ingots")
	var flagged := _forge(Vector3(20, 0, 0), "test.flag_forge", {}, PackedStringArray(["test.p12.forge_lit"]))
	assert_false(flagged.is_open(), "requires_flags: closed while the flag is unset")
	WorldState.set_flag("test.p12.forge_lit", true)
	assert_true(flagged.is_open(), "open once it is truthy")
	assert_true(Forge.value_allowed("help_cache", ["help_cache", "help_ogre"]), "a value in the list")
	assert_true(Forge.value_allowed(2, 2.0), "numbers compare by value")
	assert_false(Forge.value_allowed(null, "x"), "an unset flag never matches")


# --------------------------------------------------------------------------- loot

func test_crates_roll_their_loot_table_once_per_world_id() -> void:
	var quarry := _crate(Vector3(0, 0, -4), "test.quarry_chest")
	var armory := _crate(Vector3(4, 0, -4), "test.armory_crate", "loot.crate_armory")
	var odd := _crate(Vector3(-4, 0, -4), "test.odd_crate", "loot.raider")
	await step_ticks(2)
	assert_eq(quarry.loot_table_id(), "loot.crate_quarry", "the record's table")
	assert_eq(armory.loot_table_id(), "loot.crate_armory", "a placed crate's own table")
	for c: BreakableProp in [quarry, armory, odd]:
		queue_hit("tester", c.world_id, c.global_position + Vector3(0, 1, 2), 200.0)
	await step_ticks(2)
	assert_true(quarry.destroyed and armory.destroyed and odd.destroyed, "all three break")
	assert_true(loot.has("test.quarry_chest:item.iron_ingot"), "the quarry chest: an ingot")
	assert_true(loot.has("test.armory_crate:item.iron_ingot"), "the armory crate: an ingot")
	assert_true(loot.has("test.odd_crate:item.wood_scrap"), "the override table: wood scrap, not iron")
	assert_false(loot.has("test.odd_crate:item.iron_ingot"), "no iron from the raider table")
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "two ingots")
	quarry.queue_free()
	await step_ticks(2)
	var again := _crate(Vector3(0, 0, -4), "test.quarry_chest")
	await step_ticks(2)
	assert_true(again.destroyed, "a reloaded chest is broken")
	assert_eq(WorldState.count_of("item.iron_ingot"), 2, "and gives nothing again")


func test_a_raider_drops_its_loot_table_once_even_after_a_reload() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	var s := spawn_soldier(Vector3(0, 0.05, -8), 0.0, "test.raider_1")
	s.loot_table = "loot.raider"
	await step_ticks(2)
	queue_hit("player", "test.raider_1", s.global_position + Vector3(0, 1, 2), 5000.0)
	await step_ticks(2)
	assert_true(deaths.has("test.raider_1"), "the player killed the raider")
	assert_eq(loot.size(), 1, "one drop")
	assert_eq(loot[0], "test.raider_1:item.wood_scrap", "from loot.raider (wood scrap)")
	var scraps := WorldState.count_of("item.wood_scrap")
	assert_true(scraps == 1 or scraps == 2, "1 or 2 scraps (%d)" % scraps)
	assert_true(bool(WorldState.get_delta("test.raider_1").get("loot_awarded", false)), "marked as awarded")
	assert_eq(p.progression.xp, 20, "and its kill XP")
	var saved: Dictionary = JSON.parse_string(JSON.stringify(WorldState.to_save_dict()))
	s.queue_free()
	await step_ticks(2)
	WorldState.clear()
	assert_true(WorldState.from_save_dict(saved), "the world comes back from a save")
	var s2 := spawn_soldier(Vector3(4, 0.05, -8), 0.0, "test.raider_1")
	s2.loot_table = "loot.raider"
	await step_ticks(2)
	queue_hit("player", "test.raider_1", s2.global_position + Vector3(0, 1, 2), 5000.0)
	await step_ticks(2)
	assert_eq(deaths.count("test.raider_1"), 2, "killed again (a respawn after the reload)")
	assert_eq(loot.size(), 1, "no second loot for the same entity id")
	assert_eq(WorldState.count_of("item.wood_scrap"), scraps, "the inventory is unchanged")
	var plain := spawn_soldier(Vector3(-4, 0.05, -8), 0.0, "test.plain_soldier")
	await step_ticks(2)
	queue_hit("player", "test.plain_soldier", plain.global_position + Vector3(0, 1, 2), 5000.0)
	await step_ticks(2)
	assert_eq(loot.size(), 1, "a soldier without a loot table drops nothing")


# --------------------------------------------------------------------------- inventory screen

func test_the_inventory_screen() -> void:
	var p := await _grounded_player()
	p.equipment.grant_weapon("weapon.sword")
	WorldState.add_item("item.iron_ingot", 2, "test")
	WorldState.add_item("item.supply_cache", 1, "test")
	p.progression.add_xp(250, "test")
	_stack()
	await get_tree().process_frame
	var inv := stack.open("inventory") as InventoryScreen
	assert_true(inv != null and stack.is_open("inventory"), "SCREENS[inventory] opens")
	if inv == null:
		return
	assert_true(get_tree().paused, "it pauses the game")
	var rows := InventoryScreen.item_rows()
	assert_eq(rows.size(), 2, "two kinds of items")
	assert_eq(str(rows[0].id), "item.supply_cache", "quest items first")
	assert_true(bool(rows[0].quest), "tagged as a quest item")
	assert_true(InventoryScreen.item_line(rows[0]).begins_with("Thornwick Supply Cache x1  [quest] — "), "with the tag and its description")
	assert_true(InventoryScreen.item_line(rows[1]).begins_with("Iron Ingot x2 — "), "then the iron")
	assert_true(inv.character_text().begins_with("Level 3 (0 / 200 XP)"), "the level line (%s)" % inv.character_text())
	assert_true(inv.character_text().contains("Unspent attribute points: 6"), "and the unspent points")
	assert_eq(inv.talent_text(), "Talent points: 2 (talent trees are a full-game feature)", "talent points")
	assert_true(inv.loadout_text().begins_with("1 Heavy Footfall   2 Sweeping Blow"), "the loadout")
	assert_true(inv.loadout_text().ends_with("Ultimate: Titan Surge"), "with the ultimate")
	var weapons := inv.weapon_rows()
	assert_eq(weapons.size(), 2, "the club and the sword")
	assert_true(bool(weapons[0].equipped), "the club is equipped")
	assert_true(inv.equip_buttons.has("weapon.sword") and not inv.equip_buttons.has("weapon.club"),
		"an Equip button for the sword only")
	var out := inv.press_equip("weapon.sword")
	assert_true(out.ok, "Equip")
	assert_eq(p.equipment.weapon_id(), "weapon.sword", "the sword is equipped")
	var attrs := inv.open_attributes()
	assert_true(attrs != null and stack.top() == attrs, "the Attributes button opens the attributes screen on top")
	stack.close_all()
	assert_true(p.growth.debug_set_stage(3).ok, "stage 3")
	inv = stack.open("inventory") as InventoryScreen
	var labels: Array = []
	for row: Dictionary in inv.weapon_rows():
		labels.append(row.label)
	assert_eq(labels, ["Oak Club (too small)", "Kingsguard Sword (too small)"], "outgrown weapons are marked")
	stack.close_all()
	p.entity.combatant.pools.mark_combat()
	messages.clear()
	var refused := stack.open("inventory")
	await get_tree().process_frame
	assert_false(stack.is_open("inventory"), "in combat the inventory does not stay open")
	assert_true(refused == null or not is_instance_valid(refused) or not refused.is_open(), "it closed itself")
	assert_true(messages.has("Not during combat"), "Not during combat")
	assert_false(get_tree().paused, "and the game is not paused")
	var key := InputEventAction.new()
	key.action = "inventory"
	key.pressed = true
	messages.clear()
	stack._unhandled_input(key)
	await get_tree().process_frame
	assert_false(stack.is_open("inventory"), "the I hotkey is refused in combat too")
	assert_true(messages.has("Not during combat"), "with the same line")
	p.entity.combatant.pools.since_combat = 999.0
	stack._unhandled_input(key)
	assert_true(stack.is_open("inventory"), "out of combat the hotkey opens it")
	stack.close_all()
