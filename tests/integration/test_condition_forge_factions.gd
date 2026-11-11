extends IntegrationSuite
## M8 gate (F16; plan M6-M9 §5.9 "Settlements anywhere": a faction turned hostile "shuts its forge" until
## it is reconciled): the titan forges a deed opens (ConditionForge) in the shipped chunks follow their
## settlement as Brannock's smithy (TownForge) does - Skarn's hearth-forge, open once Skarn is saved,
## shuts while Skarn is hostile and says why, and opens again once Ulfra has her amends; Fort Aldmere's
## forge, open after the crown's parley, shuts while Aldmere is at war with the giant and opens again
## once Aldmere is reconciled.


func after_each() -> void:
	FactionState.reset_for_tests()
	await super()


func _forge_in_chunk(world_id: String) -> ConditionForge:
	var idx := WorldIndex.for_level("level.world")
	var chunk := str((idx.props.get(world_id, {}) as Dictionary).get("chunk", ""))
	assert_true(chunk != "", "%s is in the index (chunk %s)" % [world_id, chunk])
	var path := "res://scenes/world/chunks/%s_0.tscn" % chunk
	if not ResourceLoader.exists(path):
		return null
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	for n in part.find_children("*", "", true, false):
		if n is ConditionForge and str(n.get("world_id")) == world_id:
			return n
	return null


func test_skarns_hearth_forge_shuts_while_skarn_is_hostile() -> void:
	Quests.test_active = true
	var f := _forge_in_chunk("world.stonehold.skarn_forge")
	assert_true(f != null, "Skarn's hearth-forge is in its chunk")
	if f == null:
		return
	assert_eq(f.faction, "skarn", "it is Skarn's forge")
	assert_false(f.is_open(), "shut before the siege")
	WorldState.set_flag(WorldEvent.flag("event.siege_of_skarn", "done"), true)
	WorldState.set_flag(WorldEvent.flag("event.siege_of_skarn", "outcome"), "saved")
	WorldState.set_flag("world.skarn.saved", true)
	assert_true(f.is_open(), "open once Skarn is saved")
	WorldState.set_flag("faction.skarn.hostile", true)
	assert_true(FactionState.is_hostile("skarn"), "Skarn turned against the giant")
	assert_false(f.is_open(), "Skarn hostile: its hearth-forge shuts")
	assert_eq(f.blocked_reason(null), "Skarn has turned from you: make amends with Ulfra first.", "and says why")
	FactionState.reconcile("skarn")
	assert_true(f.is_open(), "the amends paid: open again")


func test_fort_aldmeres_forge_shuts_while_aldmere_is_at_war() -> void:
	Quests.test_active = true
	var f := _forge_in_chunk("world.aldmere.fort_forge")
	assert_true(f != null, "the fort forge is in its chunk")
	if f == null:
		return
	assert_eq(f.faction, "aldmere", "it is Aldmere's forge")
	WorldState.set_flag("oath.crown.outcome", "parley")
	assert_true(f.is_open(), "open after the parley")
	WorldState.set_flag("faction.aldmere.hostile", true)
	assert_true(FactionState.is_hostile("aldmere"), "Aldmere at war with the giant again")
	assert_false(f.is_open(), "Aldmere hostile: the fort forge shuts")
	assert_eq(f.blocked_reason(null), "At war with Aldmere: the fort's smiths will not work for you.", "and says why")
	FactionState.reconcile("aldmere")
	assert_true(f.is_open(), "reconciled: open again")
