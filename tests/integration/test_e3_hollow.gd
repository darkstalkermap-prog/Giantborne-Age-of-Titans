extends IntegrationSuite
## E3 (decision E3-2): the Hollow Titan's hollowness, its rules without his AI - the oath-knot (out of the world while
## his breastplate holds; bare, blows there land knot_mult times as hard, and the lock frames it), his torn plates (a
## shard where each falls; drawn back onto him by its regrowth while an oath-stone stands; crushed by a heavy or a stamp
## within crush_m, hurled back at him by the giant: never back, the hurl strikes his breast as the giant's blow), the
## oath-stones (one brought down staggers him; none standing, nothing regrows), his echo (blows on his shell from his
## second phase build it; its power by how full it rang), his draw (a giant caught in the cone is dragged to his feet,
## the embrace next) and the unbinding (his breastplate thrown off, nothing back), and the preparation (the Oath-stake
## pulled: the plates wait twice as long).

const HOLLOW := "res://scenes/enemies/hollow.tscn"
const PILLAR_KIND := preload("res://tools/world/kinds/oath_pillar.gd")


func before_each() -> void:
	await super()
	GameSession.expansion = ExpansionState.defaults()
	WorldState.clear()


func after_each() -> void:
	GameSession.expansion = ExpansionState.defaults()
	WorldState.clear()
	await super()


func _player(stage := 9, at := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(at, 0.0)
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	p.router.use_injection = true
	await step_ticks(2)
	return p


func _titan(at: Vector3) -> HollowEnemy:
	var t := (load(HOLLOW) as PackedScene).instantiate() as HollowEnemy
	t.entity_id = "test.e3.hollow"
	t.position = at
	t.ai_enabled = false
	world.add_child(t)
	await step_ticks(2)
	t.dormant = false
	return t


func _stone(id: String, at: Vector3) -> BreakableProp:
	var n := (load(PILLAR_KIND.SCENE) as PackedScene).instantiate() as BreakableProp
	n.world_id = id
	n.position = at
	world.add_child(n)
	await step_ticks(1)
	return n


func test_the_knot_is_bare_only_without_the_breastplate() -> void:
	var p := await _player(9, Vector3(0, 0.05, 30))
	var t := await _titan(Vector3(0, 0.05, -10))
	assert_false(t.knot_open, "covered at first")
	assert_eq(int(t._knot_boxes[0].collision_layer), 0, "the knot's box out of the world")
	var ids := []
	for c: Dictionary in t.lock_candidates(p.entity.combatant.height_m):
		ids.append(str(c.id))
	assert_false(ids.has("knot"), "the lock cannot frame it while covered")
	assert_true(t.break_plate("cuirass"), "the breastplate torn off")
	await step_ticks(2)
	assert_true(t.knot_open, "the oath-knot bare")
	assert_eq(int(t._knot_boxes[0].collision_layer), HitQueryAdapter.LAYER_HURTBOX, "its box in the world")
	assert_eq(int(t._cover_boxes[0].collision_layer), 0, "the breastplate's box out of it")
	ids.clear()
	for c: Dictionary in t.lock_candidates(p.entity.combatant.height_m):
		ids.append(str(c.id))
	assert_true(ids.has("knot"), "a stage-9 giant's lock may frame it")
	var e := HitEvent.new()
	e.region = "knot"
	e.power = 10.0
	t.entity.plates.prepare(e)
	assert_near(e.region_damage_mult, float(t.hollow.knot_mult), 0.001, "a blow there: knot_mult")
	assert_eq(e.plate_state, PlateRules.STATE_WEAK, "a weak point")
	var hide := HitEvent.new()
	hide.region = "back"
	t.entity.plates.prepare(hide)
	assert_true(hide.region_damage_mult < 0.25, "his hide keeps most of a blow (nothing inside to hurt)")


func test_a_torn_plate_lies_and_comes_back_while_an_oath_stone_stands() -> void:
	var p := await _player(9, Vector3(0, 0.05, 60))
	var t := await _titan(Vector3(0, 0.05, -10))
	var s := await _stone("test.e3.oath_stone", Vector3(70, 0, -10))
	t._pillars_known = t._pillars(false).size()
	assert_eq(t.standing_stones().size(), 1, "one oath-stone near him")
	assert_true(t.break_plate("pauldron_l"), "a pauldron torn off")
	await step_ticks(2)
	assert_eq(t.shard_state("pauldron_l"), HollowEnemy.LYING, "it lies where it fell")
	var at: Vector3 = t.shards["pauldron_l"].p
	var out := Vector2(at.x - t.global_position.x, at.z - t.global_position.z).length()
	assert_near(out, 6.0 + 8.0, 0.5, "shard_out_m beyond his capsule")
	var shard := get_tree().get_nodes_in_group("interactables").filter(func(n: Node) -> bool: return n is HollowShard)
	assert_eq(shard.size(), 1, "the giant may hurl it (an interactable where it lies)")
	var after_s := float((t.entity.plates.plate("pauldron_l").regrow as Dictionary).after_s)
	await step_ticks(int((after_s + 0.2) * 60.0))
	assert_eq(t.shard_state("pauldron_l"), HollowEnemy.RETURNING, "the chains draw it back after regrow.after_s")
	await step_ticks(int(3.5 * 60.0))
	assert_false(t.entity.plates.is_broken("pauldron_l"), "whole on him again")
	assert_eq(t.reforms, 1, "counted")
	assert_false(t.shards.has("pauldron_l"), "no shard left")
	assert_true(p != null and s != null, "the giant and the stone")


func test_crushed_or_hurled_it_never_comes_back() -> void:
	var p := await _player(9, Vector3(0, 0.05, 60))
	var t := await _titan(Vector3(0, 0.05, -10))
	t.break_plate("pauldron_r")
	t.break_plate("cuirass")
	await step_ticks(2)
	assert_true(t.crush_shard("pauldron_r"), "crushed")
	assert_eq(t.entity.plates.wound_state("pauldron_r"), PlateRules.WOUND_SEARED, "its wound never regrows")
	# the hurl: the giant beside the breastplate's shard
	p.global_position = t.shards["cuirass"].p + Vector3(0, 0.5, 6.0)
	await step_ticks(2)
	hits.clear()
	assert_true(t.hurl_shard("cuirass", p), "hurled back at him")
	assert_eq(t.entity.plates.wound_state("cuirass"), PlateRules.WOUND_SEARED, "the breastplate never comes back")
	await step_ticks(int(float(t.hollow.hurl_flight_s) * 60.0) + 3)
	var struck := hits.filter(func(r: HitResult) -> bool: return r.event.action_id == "ability.hollow_hurled")
	assert_eq(struck.size(), 1, "it strikes him")
	assert_eq(str(struck[0].event.attacker_id), p.entity.entity_id, "as the giant's blow")
	assert_eq(str(struck[0].event.region), "knot", "on the bare knot")
	assert_true(int(struck[0].health_damage) > 0, "and hurts him (%d)" % int(struck[0].health_damage))
	var after_s := float((t.entity.plates.plate("cuirass").regrow as Dictionary).after_s)
	await step_ticks(int((after_s + 4.0) * 60.0))
	assert_true(t.entity.plates.is_broken("cuirass"), "still off him")
	assert_eq(t.crushes + t.hurls, 2, "counted")


func test_a_giants_heavy_crushes_a_shard_within_reach() -> void:
	var p := await _player(9, Vector3(0, 0.05, 60))
	var t := await _titan(Vector3(0, 0.05, -10))
	t.break_plate("greave_l")
	await step_ticks(2)
	var at: Vector3 = t.shards["greave_l"].p
	p.global_position = at + Vector3(0, 0.5, 4.0)
	await step_ticks(2)
	var heavy := GameData.get_action(str(p.controller.loadout.get("heavy", "")))
	assert_true(heavy != null and heavy.has_tag("Heavy"), "the giant's heavy")
	t._on_giant_phase(heavy, 1, ActionDef.Phase.ACTIVE, p)
	assert_eq(t.shard_state("greave_l"), HollowEnemy.CRUSHED, "crushed under the giant's heavy")


func test_the_oath_stones_hold_him_and_fall() -> void:
	var p := await _player(9, Vector3(0, 0.05, 60))
	var t := await _titan(Vector3(0, 0.05, -10))
	var s := await _stone("test.e3.oath_stone_b", Vector3(-70, 0, -10))
	t._pillars_known = t._pillars(false).size()
	assert_true(t.holds(), "an oath-stone stands: the oath holds")
	s.on_entity_died(p.entity.entity_id)
	await step_ticks(2)
	assert_true(s.destroyed, "the stone brought down")
	assert_eq(t.stones_felled, 1, "his chain snapped")
	assert_eq(t.controller.stagger_reason, HollowEnemy.PILLAR_REASON, "he reels")
	assert_false(t.holds(), "none standing: nothing comes back")
	t.break_plate("vambrace")
	await step_ticks(2)
	assert_eq(t.entity.plates.wound_state("vambrace"), PlateRules.WOUND_SEARED, "a plate torn off now stays off")


func test_his_echo_builds_and_scales() -> void:
	var p := await _player(9, Vector3(0, 0.05, 40))
	var t := await _titan(Vector3(0, 0.05, -10))
	var full := float(t.hollow.resonance_full)
	t.resonance = 0.0
	assert_near(t.echo_mult(), float(t.hollow.echo_min_mult), 0.001, "struck seldom: a third of its power")
	t.resonance = full
	assert_near(t.echo_mult(), float(t.hollow.echo_max_mult), 0.001, "rung full: half again")
	t.resonance = 0.0
	# blows on his shell build it from his second phase only
	var r := HitResult.new()
	r.event = HitEvent.new()
	r.event.attacker_id = p.entity.entity_id
	r.event.target_id = t.entity.entity_id
	r.event.region = "back"
	r.event.tags = PackedStringArray(["Melee", "Heavy"])
	r.outcome = HitResult.Outcome.HIT
	t._on_any_hit_e3(Sim.tick, r)
	assert_eq(t.resonance, 0.0, "not before his second phase's call")
	t.brain.update_boss_phase(0.5, Sim.tick)
	t._on_any_hit_e3(Sim.tick, r)
	assert_near(t.resonance, float(t.hollow.resonance_heavy), 0.001, "a heavy on his shell rings resonance_heavy")
	r.event.region = "knot"
	t._on_any_hit_e3(Sim.tick, r)
	assert_near(t.resonance, float(t.hollow.resonance_heavy), 0.001, "a blow on the knot does not ring")


func test_his_draw_drags_the_giant_in_and_the_embrace_follows() -> void:
	var p := await _player(9, Vector3(0, 0.05, 50))
	var t := await _titan(Vector3(0, 0.05, -10))
	t.look_at(Vector3(0, 0.05, 50), Vector3.UP)
	t.facing_yaw = t.rotation.y
	var draw := GameData.get_action("ability.hollow_draw")
	t._start_drag(p.entity.entity_id, draw)
	var d0 := HollowEnemy._flat(p.global_position, t.global_position)
	for i in 90:
		t._drag_step(Sim.tick)
		await step_ticks(1)
	var d1 := HollowEnemy._flat(p.global_position, t.global_position)
	assert_true(d1 < d0 - 15.0, "dragged toward him (%.0f m -> %.0f m)" % [d0, d1])
	assert_false(t.is_dragging(), "the drag ends at his feet (or after drag_s)")
	assert_eq((t.brain as TitanBrain).current_sequence_entry(), "ability.hollow_embrace", "the embrace is his next")


func test_the_unbinding_and_the_stake() -> void:
	var t := await _titan(Vector3(0, 0.05, -10))
	var base := float((t.entity.plates.plate("helm").regrow as Dictionary).after_s)
	WorldState.set_flag("world.kingsward.stake_pulled", true)
	t._apply_stake()
	assert_near(float((t.entity.plates.plate("helm").regrow as Dictionary).after_s), base * float(t.hollow.stake_regrow_mult),
		0.001, "the Oath-stake pulled: the plates wait stake_regrow_mult times as long")
	WorldState.set_flag("world.kingsward.stake_pulled", false)
	t._apply_stake()
	assert_near(float((t.entity.plates.plate("helm").regrow as Dictionary).after_s), base, 0.001, "and back")
	t.break_plate("helm")
	await step_ticks(1)
	assert_true(t.unbind(), "his last phase: the unbinding")
	await step_ticks(2)
	assert_true(t.entity.plates.is_broken("cuirass"), "his breastplate thrown off")
	assert_true(t.knot_open, "the knot bare")
	assert_eq(t.entity.plates.wound_state("helm"), PlateRules.WOUND_SEARED, "nothing torn off comes back")
	assert_false(t.holds(), "the oath no longer holds")
