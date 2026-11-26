extends IntegrationSuite
## C3 (decision C3-5): the inventory on I - the worn slots, the bag, loot landing in it, putting things on and
## taking them off, the Bastion set worn, and pad and keyboard rows.
##   * empty: eight worn tiles (the seven armour slots and the weapon), the club in hand, an empty bag that says so;
##   * loot: what came since the bag was last looked at is in a cell with its count and marked new; the mark clears
##     once seen; a crate's loot (the real loot path) lands too;
##   * a hide piece in the bag: chosen, then chosen again, it is put on (its slot shows it, the bag no longer holds
##     it); the slot chosen and Take off puts it back in the bag; a weapon cell puts the weapon in hand;
##   * the Bastion set worn: all seven slots show it, armour and poise in the stats;
##   * the rows: the top buttons, four rows of two slots and the bag's row, the bag's other rows, Close; I closes it.

const CRATE := "res://scenes/world/crate.tscn"

var stack: ScreenStack


func before_each() -> void:
	await super()
	GameSession.expansion["equipment"] = Armour.empty()
	InventoryScreen.reset_seen()
	stack = null


func after_each() -> void:
	if stack != null and is_instance_valid(stack):
		stack.close_all()
	stack = null
	GameSession.expansion["equipment"] = Armour.empty()
	InventoryScreen.reset_seen()
	await super()


func _player() -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	await step_ticks(1)
	return p


func _open(p: GiantPlayer) -> InventoryScreen:
	if stack == null:
		var layer := CanvasLayer.new()
		world.add_child(layer)
		stack = ScreenStack.new()
		layer.add_child(stack)
		await get_tree().process_frame
	var inv := stack.open("inventory", {"player": p}) as InventoryScreen
	await get_tree().process_frame
	return inv


func test_empty_then_loot_lands_in_the_bag() -> void:
	var p := await _player()
	var inv := await _open(p)
	assert_true(inv != null and stack.is_open("inventory"), "I's screen opens")
	var tiles := InventoryScreen.worn_tiles(p)
	assert_eq(tiles.size(), 8, "eight worn slots")
	var slots: Array = []
	for t: Dictionary in tiles:
		slots.append(str(t.slot))
	for s: String in ExpansionState.ARMOUR_SLOTS:
		assert_true(slots.has(s), "the %s slot" % s)
	assert_true(slots.has("weapon"), "and the weapon's")
	for t: Dictionary in tiles:
		if str(t.slot) == "weapon":
			assert_eq(str(t.id), "weapon.club", "the club in hand")
		else:
			assert_eq(str(t.id), "", "%s empty" % t.slot)
	assert_eq(inv.cell_ids().size(), 0, "an empty bag")
	assert_true(inv.detail_text().contains("The bag is empty"), "that says so")
	assert_true(inv.stats_text().contains("Health") and inv.stats_text().contains("Armour 0"), "his numbers")
	stack.close_all()   # seen: an empty bag
	WorldState.add_item("item.iron_ingot", 3, "loot")
	WorldState.add_item("item.stoneback_slab", 1, "loot")
	inv = await _open(p)
	var ids := inv.cell_ids()
	assert_eq(ids.size(), 2, "two kinds of things (%s)" % [ids])
	assert_eq(str(ids[0]), "item.iron_ingot", "by kind, then by name")
	var fresh := InventoryScreen.fresh_ids()
	assert_true(fresh.has("item.iron_ingot") and fresh.has("item.stoneback_slab"), "both new")
	var cell := inv.equip_buttons.get("item.iron_ingot") as Button
	assert_true(cell == null, "a material is no weapon")
	var icon := (stack.top() as Node).find_child("Cell_item_iron_ingot", true, false)
	assert_true(icon != null, "the iron's cell")
	if icon != null:
		var ic := icon.get_child(0) as ItemIcon
		assert_true(ic != null and ic.count == 3 and ic.fresh and ic.kind == "ingot", "its icon: an ingot, x3, new")
	inv.choose_cell("item.iron_ingot")
	assert_true(inv.detail_text().begins_with("Iron Ingot  x3"), "chosen: its name and count (%s)" % inv.detail_text())
	assert_true(inv.detail_text().contains("Material  - new"), "its kind, new")
	stack.close_all()
	assert_true(InventoryScreen.fresh_ids().is_empty(), "seen: no longer new")
	# a crate broken: its loot through the real path
	var crate := (load(CRATE) as PackedScene).instantiate() as BreakableProp
	crate.world_id = "c3.crate"
	crate.loot_table = "loot.crate_armory"
	crate.position = Vector3(0, 0, -3)
	world.add_child(crate)
	await step_ticks(2)
	var before := InventoryScreen.bag_entries(p).size()
	var inv_before := WorldState.inventory.duplicate()
	queue_hit("player", crate.entity.entity_id, Vector3(0, 1, -1), 5000.0)
	await step_ticks(4)
	var gained := false
	for id: String in WorldState.inventory:
		if int(WorldState.inventory[id]) > int(inv_before.get(id, 0)):
			gained = true
			assert_true(InventoryScreen.fresh_ids().has(id), "the crate's %s is new in the bag" % id)
	assert_true(gained, "the crate's loot came")
	assert_true(InventoryScreen.bag_entries(p).size() >= before, "and is in the bag")


func test_put_on_and_take_off_from_the_bag_and_the_slots() -> void:
	var p := await _player()
	var eq: Dictionary = GameSession.expansion.equipment
	assert_true(Armour.grant(eq, "armour.hide_kilt"), "a hide kilt owned")
	assert_true(bool(p.equipment.grant_weapon("weapon.sword").ok), "and a sword")
	var inv := await _open(p)
	assert_eq(inv.cell_ids(), ["weapon.sword", "armour.hide_kilt"], "weapons, then armour")
	assert_eq(inv.first_focus(), inv.equip_buttons.get("weapon.sword"), "the first cell has the focus")
	inv.choose_cell("armour.hide_kilt")
	assert_true(inv.detail_text().contains("Armour 0 ->"), "its numbers before -> after")
	inv.choose_cell("armour.hide_kilt")
	var waist := ""
	for t: Dictionary in InventoryScreen.worn_tiles(p):
		if str(t.slot) == str(Armour.piece("armour.hide_kilt").slot):
			waist = str(t.id)
	assert_eq(waist, "armour.hide_kilt", "chosen again: put on")
	assert_false(inv.cell_ids().has("armour.hide_kilt"), "no longer in the bag")
	assert_true(inv.result_text().begins_with("Put on"), "said so")
	inv.choose_slot(str(Armour.piece("armour.hide_kilt").slot))
	assert_true(inv.detail_text().contains("Hide"), "the slot chosen: what it wears")
	var out := inv.press_option("-")
	assert_true(bool(out.ok), "Take off")
	assert_true(inv.cell_ids().has("armour.hide_kilt"), "back in the bag")
	inv.choose_cell("weapon.sword")
	inv.choose_cell("weapon.sword")
	assert_eq(p.equipment.weapon_id(), "weapon.sword", "the sword in hand")
	assert_true(inv.cell_ids().has("weapon.club"), "the club in the bag")
	inv.choose_slot("weapon")
	inv.press_option("weapon.club")
	assert_eq(p.equipment.weapon_id(), "weapon.club", "the weapon slot puts the club back")


func test_the_bastion_set_worn_and_the_rows() -> void:
	var p := await _player()
	var eq: Dictionary = GameSession.expansion.equipment
	for id: Variant in Armour.set_pieces("armour_set.bastion"):
		Armour.grant(eq, str(id))
		Armour.equip(eq, str(id))
	Armour.refresh_player(p)
	var inv := await _open(p)
	for t: Dictionary in InventoryScreen.worn_tiles(p):
		if str(t.slot) != "weapon":
			assert_true(str(t.id).begins_with("armour.bastion_"), "%s wears the Bastion's (%s)" % [t.slot, t.id])
	assert_eq(inv.cell_ids().size(), 0, "nothing of it left in the bag")
	assert_false(inv.stats_text().contains("Armour 0 "), "armour in the stats (%s)" % inv.stats_text())
	var rows := inv.focus_rows()
	assert_eq(rows[0], [inv.attributes_button, inv.character_button], "the top buttons first")
	for k in 4:
		assert_true((rows[k + 1] as Array).size() >= 2, "row %d: two slots" % (k + 1))
	assert_eq(rows[rows.size() - 1], [inv.close_button], "Close last")
	var key := InputEventAction.new()
	key.action = "inventory"
	key.pressed = true
	inv._unhandled_input(key)
	await get_tree().process_frame
	assert_false(stack.is_open("inventory"), "I again closes it")
