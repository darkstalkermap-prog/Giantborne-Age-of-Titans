extends IntegrationSuite
## Stage evolutions (P31, plan M6-M9 §2.11, §5.12, decision 23): a Valley character (gated) growing to
## stage 4 learns Titan Stomp and Crag Hurl into Heavy Footfall's and Boulder Hurl's slots and places
## in the known list (the bases stay known, no longer offered for a slot), with ability_learned and
## ability_evolved; the evolution's cooldown is its own (Titan Stomp fires while Footfall recovers)
## and its pulse is 0.9 x the stage's melee reach; Formation Sweep and Titan Roar wait at stage 5
## for level 9 and come with the level-up; Earthquake replaces Titan Stomp at stage 6 and level 11;
## a restore announces nothing. An ungated giant's debug growth moves the growth profile's unlocks
## into their bases' slots too.

const VALLEY := ["ability.heavy_footfall", "ability.sweeping_blow", "ability.stone_skin",
	"ability.crushing_grip", "ability.boulder_hurl", "ability.runic_bolt", "ability.ancestral_mend",
	"ability.thunder_roar"]

var evolved: Array = []
var learned: Array = []


func before_each() -> void:
	await super()
	evolved.clear()
	learned.clear()
	Events.ability_evolved.connect(_on_evolved)
	Events.ability_learned.connect(_on_learned)


func after_each() -> void:
	for sig: Signal in [Events.ability_evolved, Events.ability_learned]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	await super()


func _on_evolved(_t: int, from_id: String, to_id: String, slot: String) -> void:
	evolved.append([from_id, to_id, slot])


func _on_learned(_t: int, id: String, slot: String) -> void:
	learned.append([id, slot])


## The Valley's finished character (gated): stage 3 at `level`, the eight abilities slotted in
## library order and Titan Surge.
func _valley_giant(level: int) -> GiantPlayer:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var st := CharacterState.new_game(GameData.get_record("progression.default"), GameData.get_record("player.giant"))
	st["level"] = level
	st["xp"] = Progression.xp_for_level(level)
	st["growth_stage"] = 3
	st["known_abilities"] = VALLEY + ["ability.titan_surge"]
	st["loadout"] = {"slots": VALLEY.duplicate(), "ultimate": "ability.titan_surge"}
	p.apply_character_state(st)
	await step_ticks(2)
	return p


func _grow(p: GiantPlayer, stage: int) -> void:
	await TestWait.until(self, func() -> bool: return p.controller.state == CombatController.State.LOCOMOTION, 120)
	var r: Dictionary = p.growth.debug_set_stage(stage)
	assert_true(bool(r.ok), "grew to stage %d (%s)" % [stage, r.get("reason", "")])
	await step_ticks(2)


func _slot(p: GiantPlayer, key: String) -> String:
	return str(p.controller.loadout.get(key, ""))


func test_evolutions_learned_at_their_stage_take_their_bases_slots() -> void:
	var p := await _valley_giant(7)
	var prog: PlayerProgression = p.progression
	assert_true(prog.is_gated(), "a Valley character is gated")
	# Heavy Footfall goes on its cooldown before the growth.
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"slot_1")
	await step_ticks(3)
	assert_true(started.has("player:ability.heavy_footfall"), "Footfall cast at stage 3")
	assert_false(p.controller.cooldowns.is_ready("ability.heavy_footfall", Sim.tick), "and recovering")
	learned.clear()
	await _grow(p, 4)
	assert_eq([_slot(p, "slot_1"), _slot(p, "slot_5")], ["ability.titan_stomp", "ability.crag_hurl"],
		"stage 4 at level 7: Titan Stomp and Crag Hurl in Footfall's and Hurl's slots")
	assert_eq(evolved, [["ability.heavy_footfall", "ability.titan_stomp", "slot_1"],
		["ability.boulder_hurl", "ability.crag_hurl", "slot_5"]], "ability_evolved for each, with its slot")
	assert_eq(learned, [["ability.titan_stomp", "slot_1"], ["ability.crag_hurl", "slot_5"]],
		"ability_learned with the same slots (not the first empty one)")
	var known := p.known_abilities
	assert_eq(known.find("ability.titan_stomp") + 1, known.find("ability.heavy_footfall"),
		"Titan Stomp takes Footfall's place in the known list (%s)" % [known])
	assert_true(known.has("ability.heavy_footfall") and known.has("ability.boulder_hurl"), "the bases stay known")
	assert_eq(prog.evolved_into("ability.heavy_footfall"), "ability.titan_stomp", "Footfall evolved into Titan Stomp")
	assert_false(prog.slot_options("slot_1").has("ability.heavy_footfall"), "an evolved base is not offered for a slot")
	assert_true(prog.slot_options("slot_1").has("ability.titan_stomp"), "its evolution is")
	# Separate cooldowns: Titan Stomp fires while Footfall still recovers.
	assert_false(p.controller.cooldowns.is_ready("ability.heavy_footfall", Sim.tick), "Footfall still recovering")
	assert_true(p.controller.cooldowns.is_ready("ability.titan_stomp", Sim.tick), "Titan Stomp ready")
	var stomp := GameData.get_action("ability.titan_stomp")
	assert_near(p.attack.runner.pulse_radius(stomp), 0.9 * float(p.profile.melee_reach_m), 1e-4,
		"Titan Stomp's pulse: 0.9 x the stage's melee reach")
	p.entity.combatant.pools.stamina = p.entity.combatant.pools.stamina_max
	p.router.inject_edge(&"slot_1")
	await step_ticks(3)
	assert_true(started.has("player:ability.titan_stomp"), "slot 1 casts Titan Stomp (%s)" % [started])
	# Stage 5 at level 7: Formation Sweep and Titan Roar need level 9.
	evolved.clear()
	await _grow(p, 5)
	assert_eq([_slot(p, "slot_2"), _slot(p, "slot_8")], ["ability.sweeping_blow", "ability.thunder_roar"],
		"stage 5 at level 7: Sweep and Roar stay")
	assert_eq(evolved, [], "nothing evolves below its level")
	prog.add_xp(Progression.xp_for_level(9) - prog.xp, "test")
	await step_ticks(1)
	assert_eq(prog.level, 9, "level 9")
	assert_eq([_slot(p, "slot_2"), _slot(p, "slot_8")], ["ability.formation_sweep", "ability.titan_roar"],
		"the level-up evolves them into their bases' slots")
	assert_eq(evolved, [["ability.sweeping_blow", "ability.formation_sweep", "slot_2"],
		["ability.thunder_roar", "ability.titan_roar", "slot_8"]], "ability_evolved with the level-up")
	# Stage 6 and level 11: Earthquake replaces Titan Stomp (the chain's second step).
	prog.add_xp(Progression.xp_for_level(11) - prog.xp, "test")
	evolved.clear()
	await _grow(p, 6)
	assert_eq(_slot(p, "slot_1"), "ability.earthquake", "Earthquake in slot 1")
	assert_eq(evolved, [["ability.titan_stomp", "ability.earthquake", "slot_1"]], "Titan Stomp evolved")
	known = p.known_abilities
	assert_true(known.find("ability.earthquake") < known.find("ability.titan_stomp")
		and known.find("ability.titan_stomp") < known.find("ability.heavy_footfall"),
		"the chain keeps its order in the known list (%s)" % [known])
	assert_eq(Progression.root_of("ability.earthquake"), "ability.heavy_footfall", "Earthquake's chain starts at Footfall")
	assert_eq(Progression.preferred_slot("ability.earthquake", Progression.library()), "slot_1", "and shares its slot")
	# A restore is silent: its loadout follows the save.
	var saved := p.capture_character_state()
	p.queue_free()
	await step_ticks(2)
	evolved.clear()
	learned.clear()
	var q := spawn_player(Vector3(30, 0.05, 0))
	await step_ticks(1)
	q.apply_character_state(saved)
	await step_ticks(2)
	assert_eq([_slot(q, "slot_1"), _slot(q, "slot_2"), _slot(q, "slot_5"), _slot(q, "slot_8")],
		["ability.earthquake", "ability.formation_sweep", "ability.crag_hurl", "ability.titan_roar"], "the save's loadout")
	assert_eq([evolved, learned], [[], []], "a restore announces nothing")


func test_an_ungated_growth_moves_the_unlocked_evolutions_into_their_bases_slots() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0))
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	var prog: PlayerProgression = p.progression
	assert_false(prog.is_gated(), "the sandbox giant is not gated")
	# Taught before its stage (a reward): known, but Footfall keeps its slot until stage 4.
	assert_true(prog.learn_ability("ability.titan_stomp", "reward"), "Titan Stomp taught at stage 1")
	assert_eq(_slot(p, "slot_1"), "ability.heavy_footfall", "Footfall keeps slot 1 below stage 4")
	assert_eq(prog.evolved_into("ability.heavy_footfall"), "", "it has not evolved yet")
	assert_true(prog.slot_options("slot_1").has("ability.heavy_footfall"), "and is still offered")
	assert_eq(evolved, [], "nothing evolved")
	await _grow(p, 4)
	assert_eq([_slot(p, "slot_1"), _slot(p, "slot_5")], ["ability.titan_stomp", "ability.crag_hurl"],
		"growth.04's unlocks take Footfall's and Hurl's slots")
	assert_true(evolved.has(["ability.heavy_footfall", "ability.titan_stomp", "slot_1"]), "announced (%s)" % [evolved])
	var lo := p.controller.loadout.values()
	assert_false(lo.has("ability.heavy_footfall") or lo.has("ability.boulder_hurl"), "the bases left the hotbar (%s)" % [lo])
