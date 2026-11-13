extends IntegrationSuite
## M9 gate (lane "balance"; docs/BALANCE_LOG.md, "M9 gate"): the Troll Matriarch's second phase against the
## balance target, the conqueror novice. In the M9 confirmation the novice died in her phase 2 in every
## attempt (six on each of three seeds, her lowest 9-14 %): the frenzy and the two whelps her roar called
## killed it as she neared the end. Her phase-2 numbers were eased - regeneration 15 -> 13 hp/s, one whelp,
## the frenzy 55 + 65 -> 35 + 40 with a 3.0 s punish window (45 + 50 and 1.8 s first: the gate's own runs,
## a level lower at the den, still lost all eighteen attempts) - and the novice slew her on all three seeds
## from the gate's den save, within 1, 4 and 2 deaths (docs/BALANCE_LOG.md, "M9 gate"). This suite keeps what
## those numbers mean:
##   * her phase 2 is still the harder phase (the plan, §5.13): it regenerates faster than her first, its
##     roar calls whelps and its frenzy is her heaviest blow;
##   * but the damage it can bring - its sequence's power per second of the sequence's time, plus the
##     whelps the roar calls swiping - stays within PHASE2_LETHALITY_MAX of her first phase's sequence: on
##     the confirmation's numbers it was 3.0x (no novice attempt of 18 survived it), on these 1.7x;
##   * and her phase 2 runs in the test den: entered once, it calls the record's whelps.

const DEN := "res://scenes/test/troll_den_test.tscn"
const PHASE2_LETHALITY_MAX := 2.2


## The power per second of a phase's sequence (an action that chains runs its chain within its entry).
static func _sequence_rate(sequence: Array) -> float:
	var power := 0.0
	var seconds := 0.0
	for id: Variant in sequence:
		var a := GameData.get_action(str(id))
		while a != null:
			power += a.power
			seconds += float(a.windup_ticks + a.active_ticks + a.recovery_ticks) / 60.0
			a = GameData.get_action(a.chain_next) if a.chain_next != "" else null
	return power / seconds if seconds > 0.0 else 0.0


## A whelp's swipe power per second of its swipe.
static func _whelp_rate() -> float:
	var rec := GameData.get_record("enemy.troll_whelp")
	var a := GameData.get_action(str((rec.get("attacks", []) as Array)[0]))
	return a.power / (float(a.windup_ticks + a.active_ticks + a.recovery_ticks) / 60.0)


func test_her_second_phase_stays_within_what_the_novice_survives() -> void:
	var rec := GameData.get_record("enemy.troll_matriarch")
	var phases: Array = rec.boss.phases
	var p1: Dictionary = phases[0]
	var p2: Dictionary = phases[1]
	var regen: Dictionary = rec.regeneration
	assert_true(float(regen.phase_hp_per_s["2"]) > float(regen.hp_per_s),
		"her phase 2 regenerates faster than her first (%s > %s hp/s)" % [regen.phase_hp_per_s["2"], regen.hp_per_s])
	assert_true(int(p2.summon) >= 1, "its roar calls whelps (%d)" % int(p2.summon))
	var frenzy := GameData.get_action("ability.matriarch_frenzy_1")
	var combo := frenzy.power + GameData.get_action(frenzy.chain_next).power
	for id: Variant in p1.attacks:
		assert_true(combo > GameData.get_action(str(id)).power, "the frenzy (%.0f) is her heaviest blow (%s)" % [combo, id])
	var r1 := _sequence_rate(p1.sequence)
	var r2 := _sequence_rate(p2.sequence) + float(p2.summon) * _whelp_rate()
	assert_true(r2 > r1, "her phase 2 brings more than her first (%.1f > %.1f power/s)" % [r2, r1])
	assert_true(r2 <= PHASE2_LETHALITY_MAX * r1,
		"but at most %.1fx her first (%.1f / %.1f = %.2fx; the confirmation's numbers: 3.0x, no novice attempt survived)"
		% [PHASE2_LETHALITY_MAX, r2, r1, r2 / r1])


func test_her_second_phase_in_the_den_calls_the_records_whelps_once() -> void:
	var level := (load(DEN) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var m := level.get_node("TrollMatriarch") as TrollEnemy
	(level.get_node("BossArena") as BossArena).engage()
	p.global_position = m.global_position + Vector3(0, 0, 14)
	m.brain.target_id = p.entity.entity_id
	var pools := m.entity.combatant.pools
	pools.health = pools.health_max * 0.5
	await TestWait.until(self, func() -> bool: return m.boss_phase() == 2 and m.summoned.size() > 0, 240)
	var rec := GameData.get_record("enemy.troll_matriarch")
	assert_eq(m.boss_phase(), 2, "her second phase began at 50 %")
	assert_eq(m.summoned.size(), int(rec.boss.phases[1].summon), "its roar called the record's whelps")
	await step_ticks(120)
	assert_eq(m.summoned.size(), int(rec.boss.phases[1].summon), "and only once")
