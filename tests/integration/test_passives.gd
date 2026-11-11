extends IntegrationSuite
## P33 passives on a real giant (plan M6-M9 §2.11, §3.17, §5.12, decision 22): every talent's
## modifier moves its number exactly by the record - armour, outgoing damage (heavy, throw and magic
## for the action being performed) and poise, damage taken, stamina and essence costs and cooldowns
## (the controller's library: what is paid and what the hotbar shows), the sprint's drain, the poise
## threshold and the poise damage taken, grab reach, fury on kill and fury gain, heals received,
## elemental resistance, the maxima - and an ancestry's do the same with the statuses' (Wildheart's
## speed beside Wild Surge's). Passives are never statuses, follow the giant through a growth and
## survive a save and load; P31's statuses that use the pre-declared keys work through the same
## accessors (Stonewall Stance: no poise damage; Bedrock Ward: +50 poise threshold while it lasts).

## Every talent whose effect is a passive (the abilities' talents grant, they add no modifier).
const PASSIVE_TALENTS := ["talent.destroyer_heavy_hands", "talent.destroyer_iron_grip",
	"talent.destroyer_bone_breaker", "talent.destroyer_relentless", "talent.destroyer_juggernaut",
	"talent.destroyer_bloodied_fury", "talent.destroyer_titans_wrath", "talent.guardian_stone_hide",
	"talent.guardian_steady_stance", "talent.guardian_tireless", "talent.guardian_unyielding",
	"talent.guardian_grounded", "talent.guardian_protector", "talent.guardian_mountains_heart",
	"talent.primordial_runic_mind", "talent.primordial_kindled", "talent.primordial_quick_runes",
	"talent.primordial_wellspring", "talent.primordial_regrowth", "talent.primordial_worldsong"]


## A gated giant at level 12 from the world start (stage 3, the Valley's abilities), standing.
func _giant(pos: Vector3, ancestry := "ancestry.neutral") -> GiantPlayer:
	var p := spawn_player(pos)
	await step_ticks(1)
	var st := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	st["level"] = 12
	st["xp"] = Progression.xp_for_level(12)
	st["ancestry"] = ancestry
	p.apply_character_state(CharacterState.normalize(st))
	await step_ticks(1)
	return p


## The record's value of `key` in talent `id`.
static func _mod(id: String, key: String) -> float:
	return float(Talents.modifiers_of(id)[key])


## The numbers a passive may move, read from the giant as the game reads them.
func _numbers(p: GiantPlayer) -> Dictionary:
	var c := p.entity.combatant
	var lib := p.controller.library
	return {"armor": c.armor_total(), "poise": c.poise.threshold, "health": c.pools.health_max,
		"stamina": c.pools.stamina_max, "essence": c.pools.essence_max, "fire": c.resistance("fire"),
		"kill_fury": float(c.fury_gain.get("kill", 0.0)), "fury_mult": c.pools.fury_gain_mult,
		"reach": p.grab.grab_reach(), "speed": p.motor.status_speed_mult(),
		"footfall_stamina": (lib["ability.heavy_footfall"] as ActionDef).stamina_cost,
		"footfall_cooldown": (lib["ability.heavy_footfall"] as ActionDef).cooldown_s,
		"bolt_essence": (lib["ability.runic_bolt"] as ActionDef).essence_cost,
		"taken": c.damage_taken_mult(), "out": c.outgoing_damage_mult(), "out_poise": c.outgoing_poise_mult()}


func test_every_talent_passive_moves_its_number_by_the_record() -> void:
	var p := await _giant(Vector3(0, 0.05, 0))
	var prog: PlayerProgression = p.progression
	var c := p.entity.combatant
	var before := _numbers(p)
	assert_eq(c.passives, {}, "no passives before a talent")
	prog.apply_state({"talents": PASSIVE_TALENTS})
	var now := _numbers(p)
	assert_near(now.armor, before.armor + _mod("talent.guardian_stone_hide", "armor_flat"), 1e-6, "Stone Hide: armour +15")
	assert_near(now.poise, before.poise + _mod("talent.guardian_steady_stance", "poise_threshold_add"), 1e-6,
		"Steady Stance: poise threshold +25")
	assert_near(now.health, before.health + _mod("talent.guardian_mountains_heart", "health_add"), 1e-6,
		"Mountain's Heart: health +250")
	assert_near(now.essence, before.essence + _mod("talent.primordial_wellspring", "essence_add"), 1e-6, "Wellspring: essence +40")
	assert_near(now.stamina, before.stamina, 1e-6, "no talent adds stamina")
	assert_near(now.fire, before.fire + _mod("talent.guardian_grounded", "elemental_resist_add"), 1e-6,
		"Grounded: elemental resistance +10%")
	assert_near(now.kill_fury, before.kill_fury + _mod("talent.destroyer_bloodied_fury", "fury_on_kill_add"), 1e-6,
		"Bloodied Fury: +6 fury per kill")
	assert_near(now.fury_mult, _mod("talent.primordial_kindled", "fury_gain_mult"), 1e-6, "Kindled: fury gained x1.2")
	assert_near(now.reach, before.reach + _mod("talent.destroyer_iron_grip", "grab_reach_add"), 1e-6, "Iron Grip: grab reach +1.5 m")
	var stamina_mult := _mod("talent.destroyer_relentless", "stamina_cost_mult") * _mod("talent.guardian_tireless", "stamina_cost_mult")
	assert_near(now.footfall_stamina, before.footfall_stamina * stamina_mult, 1e-6, "Relentless x Tireless: stamina costs")
	assert_near(now.bolt_essence, before.bolt_essence * _mod("talent.primordial_runic_mind", "essence_cost_mult"), 1e-6,
		"Runic Mind: essence costs")
	assert_near(now.footfall_cooldown, before.footfall_cooldown * _mod("talent.primordial_quick_runes", "cooldown_mult"), 1e-6,
		"Quick Runes: cooldowns")
	assert_eq(GameData.get_action("ability.heavy_footfall").stamina_cost, before.footfall_stamina,
		"the shared record keeps its cost (the library holds the giant's copy)")
	assert_near(now.taken, _mod("talent.guardian_unyielding", "damage_taken_mult"), 1e-9, "Unyielding: damage taken x0.92")
	assert_near(now.out, _mod("talent.destroyer_titans_wrath", "outgoing_damage_mult"), 1e-9, "Titan's Wrath: damage dealt x1.08")
	assert_near(now.out_poise, _mod("talent.destroyer_heavy_hands", "outgoing_poise_mult")
		* _mod("talent.destroyer_bone_breaker", "outgoing_poise_mult"), 1e-9, "Heavy Hands x Bone Breaker: poise dealt")
	assert_near(now.speed, 1.0, 1e-9, "no talent changes speed")
	# The per-action multipliers, and the one the giant is performing.
	assert_near(c.action_damage_mult(action("ability.heavy_1")), _mod("talent.destroyer_heavy_hands", "heavy_damage_mult"),
		1e-9, "Heavy Hands: heavies x1.10")
	assert_near(c.action_damage_mult(action("ability.light_1")), 1.0, 1e-9, "lights unchanged")
	assert_near(c.action_damage_mult(action("ability.throw_held")), _mod("talent.destroyer_iron_grip", "throw_damage_mult"),
		1e-9, "Iron Grip: throws x1.15")
	assert_near(c.action_damage_mult(action("ability.runic_bolt")), _mod("talent.primordial_worldsong", "magic_damage_mult"),
		1e-9, "Worldsong: magic x1.15")
	p.router.inject_edge(&"heavy")
	await step_ticks(2)
	assert_eq(p.controller.action_id(), "ability.heavy_1", "the giant swings its heavy")
	assert_near(c.outgoing_damage_mult(), 1.08 * 1.10, 1e-9, "its blows carry Titan's Wrath x Heavy Hands")
	await TestWait.until(self, func() -> bool: return p.controller.action == null, 120)
	assert_near(c.outgoing_damage_mult(), 1.08, 1e-9, "and the next action its own")
	# Taken: a real hit, heals and poise.
	var pools := c.pools
	pools.health = pools.health_max * 0.5
	var mid := pools.health
	p.entity.heal(100.0, "test")
	assert_near(pools.health - mid, 100.0 * 1.2 * 1.15, 1e-6, "Protector x Regrowth: a heal of 100 restores 138")
	c.poise.value = 0.0
	c.poise.add(20.0)
	assert_near(c.poise.value, 20.0 * _mod("talent.destroyer_juggernaut", "poise_damage_taken_mult"), 1e-6,
		"Juggernaut: poise damage taken x0.85")
	c.poise.value = 0.0
	var hp := pools.health
	queue_hit("tester", p.entity.entity_id, p.global_position + Vector3(0, 0, -3), 100.0, PackedStringArray())
	await step_ticks(1)
	var got := hits_on(p.entity.entity_id)
	assert_eq(got.size(), 1, "a hit lands on the giant")
	if got.size() == 1:
		var plain_giant := Combatant.from_record("plain", p.record)   # no passive but the same armour
		plain_giant.armor = c.armor_total()
		var plain := DamageResolver.mitigate(got[0].event, plain_giant)
		assert_eq(got[0].health_damage, CombatRules.round_damage(float(plain.total) * 0.92), "Unyielding takes 8% off a real hit")
		assert_near(pools.health, hp - got[0].health_damage, 1e-6, "and that is what the giant lost")
	# The sprint's drain follows the stamina multiplier too.
	pools.stamina = pools.stamina_max
	var drain := float(p.sprint_def.param("drain_per_s", 8.0))
	p.motor.update_sprint({"move": Vector2(0, 1), "sprint_held": true}, 0.5)
	assert_near(pools.stamina_max - pools.stamina, drain * 0.5 * stamina_mult, 1e-6, "Relentless x Tireless: sprinting drains less")
	p.motor.update_sprint({"move": Vector2.ZERO, "sprint_held": false}, 0.0)
	# Never a status, and a growth keeps them (the new profile's reach + Iron Grip).
	assert_true(c.statuses.is_empty(), "passives are no statuses (the HUD's status row stays empty)")
	p.set_profile(GameData.get_record("growth.04"))
	assert_near(p.grab.grab_reach(), float(GameData.get_record("growth.04").grab_reach_m) + 1.5, 1e-6,
		"stage 4: its grab reach + Iron Grip")
	assert_eq(str(p.profile.id), "growth.04", "the profile is the stage's")
	assert_near(c.armor_total(), before.armor + 15.0, 1e-6, "the passives stay")
	# A save and a load (into a new giant: one "player" at a time).
	var json: Dictionary = JSON.parse_string(JSON.stringify(CharacterState.normalize(p.capture_character_state())))
	assert_eq(json.talents, PASSIVE_TALENTS, "the save lists the talents")
	var saved := {"passives": c.passives.duplicate(), "armor": c.armor_total(), "health_max": pools.health_max,
		"health": pools.health, "reach": p.grab.grab_reach()}
	p.queue_free()
	await step_ticks(2)
	var q := spawn_player(Vector3(8, 0.05, 0))
	await step_ticks(1)
	q.apply_character_state(CharacterState.normalize(json))
	var qc := q.entity.combatant
	assert_eq(qc.passives, saved.passives, "the same passives after a load")
	assert_near(qc.armor_total(), saved.armor, 1e-6, "the same armour")
	assert_near(qc.pools.health_max, saved.health_max, 1e-6, "the same health")
	assert_near(q.grab.grab_reach(), saved.reach, 1e-6, "the same reach")
	assert_near((q.controller.library["ability.heavy_footfall"] as ActionDef).stamina_cost, now.footfall_stamina, 1e-6,
		"the same costs")
	assert_near(qc.pools.health, saved.health, 1e-3, "and the saved health within the larger maximum")
	assert_true(qc.statuses.is_empty(), "still no status")


func test_ancestry_passives_fold_with_statuses() -> void:
	var p := await _giant(Vector3(0, 0.05, 0), "ancestry.wildheart")
	var c := p.entity.combatant
	assert_true(p.progression.ancestry_chosen, "a Wildheart has chosen")
	assert_near(p.motor.status_speed_mult(), 1.05, 1e-9, "Wildheart: speed x1.05")
	assert_near(c.pools.fury_gain_mult, 1.25, 1e-9, "fury gained x1.25")
	var base := Combatant.from_record("plain", p.record)
	base.growth_bonus = c.growth_bonus.duplicate()
	base.set_attributes(c.attributes)
	assert_near(c.pools.stamina_max, base.pools.stamina_max + 20.0, 1e-6, "stamina +20")
	assert_true(p.entity.apply_status("status.wild_surge"), "Wild Surge")
	assert_near(p.motor.status_speed_mult(), 1.05 * 1.15, 1e-9, "Wild Surge and Wildheart multiply (applied once, in the motor)")
	assert_eq(c.statuses.active_ids(), PackedStringArray(["status.wild_surge"]), "only the ability is a status")
	# P31's statuses that use the keys P33 applies.
	var threshold := c.poise.threshold
	assert_true(p.entity.apply_status("status.bedrock_ward"), "Bedrock Ward")
	assert_near(c.poise.threshold, threshold + 50.0, 1e-6, "Bedrock Ward: poise threshold +50 while it lasts")
	assert_near(c.armor_total(), base.armor_total() + 40.0, 1e-6, "and armour +40")
	c.statuses.remove("status.bedrock_ward")
	assert_near(c.poise.threshold, threshold, 1e-6, "back when it ends")
	assert_true(p.entity.apply_status("status.stonewall_stance"), "Stonewall Stance")
	c.poise.value = 0.0
	assert_false(c.poise.add(500.0), "Stonewall Stance: nothing staggers")
	assert_near(c.poise.value, 0.0, 1e-9, "no poise damage at all")
	assert_near(p.motor.status_speed_mult(), 1.05 * 1.15 * 0.7, 1e-9, "and its x0.7 speed joins the product")
