extends IntegrationSuite
## Refit chains and forge tiers (P31, plan M6-M9 §2.11, decision 24): base -> reinforced at an iron
## forge; reinforced -> titanforged refused there with "forge_tier" (nothing taken) and done at a titan
## forge for 2 titan iron and 2 iron ingots, which also reinforces; a titanforged weapon goes no
## further; the axe's one step needs a titan forge; and every shipped chain fits monotonically, never
## loops and never steps down from a titan forge to an iron one.

const FORGE := "res://scenes/world/forge.tscn"

var upgrades: Array = []


func before_each() -> void:
	await super()
	upgrades.clear()
	Events.upgrade_applied.connect(_on_upgrade)


func after_each() -> void:
	for c: Dictionary in Events.upgrade_applied.get_connections():
		if (c.callable as Callable).get_object() == self:
			Events.upgrade_applied.disconnect(c.callable)
	await super()


func _on_upgrade(_tick: int, from_weapon: String, to_weapon: String) -> void:
	upgrades.append([from_weapon, to_weapon])


func _forge(pos: Vector3, world_id: String, tier: String) -> Forge:
	var f := (load(FORGE) as PackedScene).instantiate() as Forge
	f.world_id = world_id
	f.tier = tier
	f.position = pos
	world.add_child(f)
	return f


func test_a_chain_through_an_iron_and_a_titan_forge() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var iron := _forge(Vector3(12, 0, 0), "test.iron_forge", "iron")
	var titan := _forge(Vector3(-12, 0, 0), "test.titan_forge", "titan")
	await step_ticks(1)
	assert_eq([iron.does_tier("iron"), iron.does_tier("titan"), titan.does_tier("iron"), titan.does_tier("titan")],
		[true, false, true, true], "an iron forge reinforces; a titan forge does both")
	WorldState.add_item("item.iron_ingot", 4, "test")
	WorldState.add_item("item.titan_iron", 2, "test")
	assert_true(bool(iron.upgrade(p).ok), "the Oak Club is reinforced at the iron forge")
	assert_eq(p.equipment.weapon_id(), "weapon.club_reinforced", "and equipped")
	var refused := iron.upgrade(p)
	assert_eq([bool(refused.ok), str(refused.reason), str(refused.to), str(refused.forge_tier)],
		[false, "forge_tier", "weapon.club_titan", "titan"], "titanforging is refused at the iron forge")
	assert_eq(str(refused.message), Forge.TIER_MESSAGE, "which says where to go")
	assert_eq([WorldState.count_of("item.iron_ingot"), WorldState.count_of("item.titan_iron")], [2, 2], "nothing taken")
	var offer := titan.can_upgrade(p)
	assert_true(bool(offer.ok), "the titan forge offers it (%s)" % offer.message)
	assert_eq(str(offer.perk), str(GameData.get_record("weapon.club_titan").perk.text), "with the new weapon's perk")
	var names: Array = []
	for c: Dictionary in offer.cost:
		names.append("%d %s" % [int(c.count), str(c.name)])
	assert_eq(names, ["2 Titan Iron", "2 Iron Ingot"], "for 2 titan iron and 2 iron")
	assert_true(bool(titan.upgrade(p).ok), "titanforged")
	assert_eq(p.equipment.weapon_id(), "weapon.club_titan", "the Titanforged Club is equipped")
	assert_eq(p.equipment.owned(), PackedStringArray(["weapon.club_titan"]), "the reinforced club is gone")
	assert_eq([WorldState.count_of("item.iron_ingot"), WorldState.count_of("item.titan_iron")], [0, 0], "the cost is paid")
	assert_eq(upgrades, [["weapon.club", "weapon.club_reinforced"], ["weapon.club_reinforced", "weapon.club_titan"]],
		"upgrade_applied for each step")
	assert_eq(str(titan.upgrade(p).reason), "no_upgrade", "a titanforged weapon goes no further")
	# The axe's only step needs a titan forge; a titan forge also reinforces.
	p.equipment.grant_weapon("weapon.axe", true)
	assert_eq(str(iron.can_upgrade(p).reason), "forge_tier", "the axe cannot be titanforged at an iron forge")
	assert_eq(str(titan.can_upgrade(p).reason), "missing_items", "a titan forge would, given the materials")
	p.equipment.grant_weapon("weapon.sword", true)
	WorldState.add_item("item.iron_ingot", 2, "test")
	assert_true(bool(titan.upgrade(p).ok), "the titan forge reinforces the sword too")
	assert_eq(p.equipment.weapon_id(), "weapon.sword_reinforced", "into the Kingsguard Blade")


func test_the_shipped_chains() -> void:
	assert_eq(Progression.refit_chain_errors(GameData.records, GameData.record_paths), PackedStringArray(),
		"every shipped chain is sound")
	for family: String in ["club", "sword", "hammer"]:
		var base := GameData.get_record("weapon.%s" % family)
		var reinforced := GameData.get_record(str(base.upgrade.to))
		var titan := GameData.get_record(str(reinforced.upgrade.to))
		assert_eq([str(base.upgrade.get("forge_tier", "iron")), str(reinforced.upgrade.forge_tier)], ["iron", "titan"],
			"%s: an iron step, then a titan step" % family)
		assert_eq(str(titan.id), "weapon.%s_titan" % family, "%s ends titanforged" % family)
		assert_true(int(base.fit_max_stage) <= int(reinforced.fit_max_stage) and int(reinforced.fit_max_stage) <= int(titan.fit_max_stage),
			"%s: each step fits at least as high" % family)
		var cost: Array = []
		for c: Dictionary in reinforced.upgrade.cost:
			cost.append([str(c.item), int(c.count)])
		assert_eq(cost, [["item.titan_iron", 2], ["item.iron_ingot", 2]], "%s: 2 titan iron and 2 iron" % family)
	assert_eq(str(GameData.get_record("item.titan_iron").get("type", "")), "item", "titan iron ships")
