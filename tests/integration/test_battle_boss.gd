extends IntegrationSuite
## A battle as one boss (plan M6-M9 §5.13 boss 1; P34) on scenes/test/bailey_test.tscn: the BattleBoss of
## battle.iron_regiment engages under its battle id, plans the composition this giant meets (20 units
## on desktop) and shows its aggregate on the boss bar - every unit of the battle counts as shown, so
## the HUD hides its target frame for them; each phase begins once per attempt at its fraction of the
## aggregate (60 %, 25 %), activating its encounters through the director, announced by
## boss_phase_changed; when the guard breaks Corvane yields under the battle's id, the rest of the
## battle stands down, and Spare wins it. (The web composition and the attempt reset: the slow battery.)
## M8 screenshot pass (V3): the units of a phase know where the giant is when they come - the Charge's
## riders, 84-90 m from him (beyond their 70 m sight), ride for him at once.

const BAILEY := "res://scenes/test/bailey_test.tscn"
const BB := preload("res://tools/builders/big.gd")
const WALL := "encounter.bailey_test_wall"
const CHARGE := "encounter.bailey_test_charge"
const STAND := "encounter.bailey_test_stand"

var level: Node3D
var log_events: Array = []


func before_each() -> void:
	await super()
	log_events.clear()
	WorldState.clear()
	for pair: Array in [[Events.boss_engaged, "engaged"], [Events.boss_phase_changed, "phase"],
			[Events.boss_yielded, "yielded"], [Events.boss_defeated, "defeated"]]:
		(pair[0] as Signal).connect(_on_event.bind(pair[1]))


func after_each() -> void:
	for sig: Signal in [Events.boss_engaged, Events.boss_phase_changed, Events.boss_yielded, Events.boss_defeated]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	Quests.end_dialogue()
	await super()


func _on_event(...args: Array) -> void:
	var kind: String = args.pop_back()
	log_events.append([kind] + args.slice(1))


func _kill(id: String) -> void:
	var e := Sim.get_entity(id)
	if e == null or not e.is_alive():
		return
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = "player"
	h.target_id = id
	h.power = 1.0e6
	h.size_policy = "none"
	h.damage_split = {"physical": 1.0}
	h.tags = PackedStringArray(["Melee", "Unblockable", "Unparryable"])
	h.attacker_position = e.actor.global_position + Vector3(0, 0, 4)
	Sim.queue_hit(h)


func _kill_encounter(d: EncounterDirector, enc: String) -> void:
	for id in d.members_of(enc):
		_kill(id)
	await step_ticks(2)


func test_the_iron_regiment_as_one_boss() -> void:
	level = (load(BAILEY) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	var bar: Control = (load("res://ui/hud/boss_bar.gd") as GDScript).new()
	var layer := CanvasLayer.new()
	layer.add_child(bar)
	world.add_child(layer)
	await step_ticks(2)
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	assert_eq(battle.battle_id, BB.BAILEY_ID, "battle.iron_regiment")
	assert_true(battle.is_in_group(BattleBoss.BATTLE_GROUP), "a battle boss")
	p.global_position = Vector3(0, 0.05, 30)
	battle.engage()
	await step_ticks(2)
	assert_eq(log_events[0], ["engaged", BB.BAILEY_ID], "boss_engaged carries the battle's id")
	var planned := battle.planned()
	assert_eq(planned.size(), 20, "12 shields and a banner, 4 riders, 2 guards and Corvane")
	assert_near(battle.total_health(), 13 * 260.0 + 4 * 400.0 + 2 * 300.0 + 600.0, 0.01, "the aggregate's total")
	assert_eq(battle.phase_log, [1] as Array[int], "The Wall")
	assert_eq(d.encounter_state(WALL), "active", "the wall's encounter is the battle's")
	assert_eq(d.encounter_state(CHARGE), "dormant", "the charge waits")
	assert_near(battle.aggregate_fraction(), 1.0, 1e-6, "all there")
	bar._process(0.0)
	assert_true(bar.call("bar_visible"), "the boss bar shows the battle")
	assert_true(str(bar.call("visible_text")).begins_with("The Iron Regiment  6180 / 6180  phase 1/3"),
		"its aggregate: %s" % bar.call("visible_text"))
	assert_eq(bar.call("phase_pips"), [true, false, false], "three phases")
	var wall_unit := Sim.get_entity("test.bailey.wall_1")
	assert_true(wall_unit != null and bool(bar.call("shows_entity", wall_unit)), "a unit of the battle is shown by the bar (no target frame)")
	# The wall falls: The Charge, once.
	await _kill_encounter(d, WALL)
	assert_true(battle.aggregate_fraction() <= 0.6, "at or below 60 %")
	assert_eq(battle.phase_log, [1, 2] as Array[int], "The Charge")
	assert_eq(d.encounter_state(CHARGE), "active", "the riders come")
	var phases := log_events.filter(func(e: Array) -> bool: return e[0] == "phase")
	assert_eq(phases, [["phase", BB.BAILEY_ID, 2]], "announced once")
	await step_ticks(2)
	assert_eq(battle.phase_log, [1, 2] as Array[int], "never twice")
	# The riders fall: The Last Stand.
	for i in 2:
		await _kill_encounter(d, CHARGE)
	assert_eq(battle.phase_log, [1, 2, 3] as Array[int], "The Last Stand")
	var corvane := Sim.get_entity("test.bailey.corvane")
	assert_true(corvane != null and corvane.is_alive(), "Corvane holds the steps")
	bar._process(0.0)
	assert_eq(bar.call("phase_pips"), [true, true, true], "the third pip")
	# His guard breaks: he yields under the battle's id; the rest stands down.
	await _kill_encounter(d, STAND)
	assert_true(corvane.is_alive(), "Corvane cannot be killed before he yields")
	var yielded := log_events.filter(func(e: Array) -> bool: return e[0] == "yielded")
	assert_eq(yielded, [["yielded", BB.BAILEY_ID]], "boss_yielded(battle.iron_regiment)")
	assert_true((corvane.actor as EnemyActor).yielded, "Corvane yields")
	assert_true(battle.surrendered, "the battle surrenders")
	bar._process(0.0)
	assert_true(str(bar.call("visible_text")).ends_with("yields"), "the bar says so")
	assert_true((corvane.actor as EnemyActor).p34_decide("spare"), "Spare")
	await step_ticks(1)
	var defeated := log_events.filter(func(e: Array) -> bool: return e[0] == "defeated")
	assert_eq(defeated, [["defeated", BB.BAILEY_ID]], "the battle is won")
	assert_eq(WorldState.get_flag("boss.corvane.outcome"), "spared", "Corvane spared")
	assert_true(battle.is_defeated(), "the bailey is done")


## M8 screenshot pass (V3): Fort Aldmere's Charge spawned its riders at the stables, 85-110 m from where
## the giant fights the Wall - beyond their 70 m sight and 30 m hearing - and they stood there for the rest
## of the battle (the screenshot pass saw none charge). Here the giant stands where the test bailey's riders
## are 84-90 m off when the Wall falls: they must know where he is at once and ride for him.
func test_the_charge_rides_at_a_giant_beyond_its_sight() -> void:
	level = (load(BAILEY) as PackedScene).instantiate() as Node3D
	world.add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	p.router.use_injection = true
	await step_ticks(2)
	var battle := level.get_node("BattleBoss") as BattleBoss
	var d := level.get_node("EncounterDirector") as EncounterDirector
	p.global_position = Vector3(-20, 0.05, 35)
	battle.engage()
	await step_ticks(2)
	await _kill_encounter(d, WALL)
	assert_eq(battle.phase_log, [1, 2] as Array[int], "The Charge")
	var riders: Array[CavalryEnemy] = []
	for id in d.members_of(CHARGE):
		var e := Sim.get_entity(id)
		if e != null and e.is_alive() and e.actor is CavalryEnemy:
			riders.append(e.actor as CavalryEnemy)
	assert_eq(riders.size(), 4, "the four riders came")
	var start := {}
	for r in riders:
		var off := _flat_distance(r.global_position, p.global_position)
		start[r.entity_id] = off
		assert_true(off > 80.0, "%s comes %.0f m from the giant: beyond its sight (70 m)" % [r.entity_id, off])
	await step_ticks(12)
	for r in riders:
		assert_true(r.brain.aware and r.brain.target_id == p.entity.entity_id,
			"%s knows where the giant is (aware %s, target '%s')" % [r.entity_id, r.brain.aware, r.brain.target_id])
	await step_ticks(180)
	for r in riders:
		var off := _flat_distance(r.global_position, p.global_position)
		assert_true(off < float(start[r.entity_id]) - 20.0 or r.charges_started > 0,
			"%s rides for him (%.0f m -> %.0f m, %d charges)" % [r.entity_id, start[r.entity_id], off, r.charges_started])


static func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
