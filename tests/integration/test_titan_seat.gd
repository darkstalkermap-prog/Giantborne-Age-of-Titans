extends IntegrationSuite
## A3: a world titan's encounter against the director's rules (EncounterDirector's A3 section; docs/systems/A3.md):
## on scenes/test/bailey_test.tscn with two test encounters - a crowd of five soldiers and a "titan" (a soldier
## standing in for him: the rules read the record, not the archetype) 200 m away whose record sets reserve_seat and
## lod_near_m - and the budget made tight (five):
##   * beyond the titan's activation radius nothing is reserved and he is not in the world;
##   * the giant within it: his seat is reserved, the crowd's farthest member leaves to make room, and he spawns
##     within the budget; the crowd, coming back, waits for room;
##   * 200 m from the giant his AI runs at the near tier (the director's own tiers would put him at the far one);
##   * the giant beyond the radius again: the seat is released; killed, he keeps none.

const BAILEY := "res://scenes/test/bailey_test.tscn"
const CROWD := "encounter.test_seat_crowd"
const TITAN := "encounter.test_seat_titan"
const TITAN_ID := "test.seat.titan"


func after_each() -> void:
	TestFixtures.restore_all()
	await super()


static func _crowd() -> Dictionary:
	var spawns: Array = []
	for i in 5:
		spawns.append({"entity_id": "test.seat.crowd_%d" % (i + 1), "definition": "enemy.soldier",
			"position_m": [10.0 + float(i) * 6.0, 0.05, 40.0], "yaw_deg": 0, "ai_enabled": false, "persist_death": true})
	return {"schema_version": 1, "id": CROWD, "type": "encounter", "level": "level.bailey_test",
		"display_name": "Test: a crowd", "center_m": [22, 0, 40], "activate_radius_m": 10, "deactivate_radius_m": 900,
		"leash_radius_m": 60, "alert_group": false, "requires_flags": ["test.seat.manual"], "forbids_flags": [],
		"counts_toward_budget": true, "spawns": spawns}


static func _titan() -> Dictionary:
	return {"schema_version": 1, "id": TITAN, "type": "encounter", "level": "level.bailey_test",
		"display_name": "Test: a titan's seat", "center_m": [0, 0, -170], "activate_radius_m": 220,
		"deactivate_radius_m": 900, "leash_radius_m": 0, "arena": true, "alert_group": false, "requires_flags": [],
		"forbids_flags": [], "counts_toward_budget": true, "reserve_seat": true, "lod_near_m": 300,
		"spawns": [{"entity_id": TITAN_ID, "definition": "enemy.soldier", "position_m": [0.0, 0.05, -170.0],
			"yaw_deg": 0, "ai_enabled": true, "persist_death": true}]}


func _spawned(d: EncounterDirector, enc: String) -> Array:
	return Array(d.members_of(enc)).filter(func(id: String) -> bool: return d.member_status(id) == EncounterDirector.SPAWNED)


func test_a_titans_seat_and_his_near_tier() -> void:
	TestFixtures.record_override(CROWD, _crowd())
	TestFixtures.record_override(TITAN, _titan())
	var level := (load(BAILEY) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(2)
	var d := level.get_node("EncounterDirector") as EncounterDirector
	assert_true(d.encounter_ids().has(TITAN), "the titan's encounter is the level's")
	d.max_active_enemies = 5
	# the giant beyond his radius: no seat, no titan
	p.global_position = Vector3(0, 0.05, 120)
	await step_ticks(2)
	d.force_activate(CROWD)
	d.update_now()
	assert_eq(_spawned(d, CROWD).size(), 5, "the crowd fills the budget of five")
	d.update_now()
	assert_false(d.a3_seat_reserved(TITAN), "290 m from him: no seat reserved")
	assert_eq(_spawned(d, TITAN).size(), 0, "and he is not in the world")
	# the giant within his radius: his seat
	p.global_position = Vector3(0, 0.05, 30)
	await step_ticks(2)
	d.update_now()
	assert_true(d.a3_seat_reserved(TITAN), "200 m from him: his seat reserved")
	d.update_now()
	assert_eq(_spawned(d, TITAN), [TITAN_ID], "he spawns")
	assert_eq(_spawned(d, CROWD).size(), 4, "the crowd's farthest member left to make room")
	assert_eq(d.member_status("test.seat.crowd_5"), EncounterDirector.DESPAWNED, "the farthest (from his centre) one")
	assert_true(d.active_combatant_count() <= d.max_active_enemies, "within the budget (%d)" % d.active_combatant_count())
	d.force_activate(CROWD)
	d.update_now()
	assert_eq(_spawned(d, CROWD).size(), 4, "the crowd, coming back, waits for room")
	# his near tier at 200 m (the director's tiers: far beyond mid_m 90 m)
	await step_ticks(EncounterDirector.DEFAULT_CHECK_TICKS + 1)
	var t := d.spawned(TITAN_ID)
	assert_eq(d.lod_tier_for(t.global_position, p.global_position, false), 2, "the director's own tier at 200 m: far")
	assert_eq(int(t.get("lod_tier")), 0, "his: near (lod_near_m 300)")
	# the giant away again: the seat released
	p.global_position = Vector3(0, 0.05, 140)
	await step_ticks(2)
	d.update_now()
	assert_false(d.a3_seat_reserved(TITAN), "the giant beyond his radius: the seat released")
	# back, and he dies: he keeps no seat
	p.global_position = Vector3(0, 0.05, 30)
	await step_ticks(2)
	d.update_now()
	assert_true(d.a3_seat_reserved(TITAN), "reserved again")
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "test.nobody"
	h.target_id = TITAN_ID
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = t.global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)
	await step_ticks(3)
	d.update_now()
	assert_true(WorldState.is_killed(TITAN_ID), "killed")
	assert_false(d.a3_seat_reserved(TITAN), "dead, he keeps no seat")
	level.queue_free()
	await step_ticks(2)
