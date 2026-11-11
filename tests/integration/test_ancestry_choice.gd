extends IntegrationSuite
## P33's ancestry choice and talent learning on a real giant (plan M6-M9 §3.17, §5.7, §5.12, decision
## 22): the ancestry is offered once the Old Kingdom has opened (the flag progress.world_entered) and
## never in the prologue or in combat; choosing it adds its attribute points once, makes its strengths
## lasting passives, teaches its signature (auto-slotted into the first free slot), sets the flag
## ancestry.chosen, emits ancestry_chosen, completes quest.ancestry (started at stage 4) and dismisses
## the prompt a world shrine showed; it can be chosen once and stays chosen through a save and a load
## (the attributes are not added again). A migrated v1 save (a finished prologue) is offered the same
## choice once it reaches the world, and its carried-over talent points buy talents: points spent
## once, talent_learned, a refusal spends nothing.

const Fx := preload("res://tests/support/quest_fixtures.gd")
const FIXTURE := "res://tests/fixtures/saves/v1_force_complete.json"

var chosen: Array = []
var learned: Array = []
var hud: Array = []


func before_each() -> void:
	await super()
	chosen.clear()
	learned.clear()
	hud.clear()
	Events.ancestry_chosen.connect(_on_chosen)
	Events.talent_learned.connect(_on_learned)
	Events.hud_message.connect(_on_hud)


func after_each() -> void:
	for sig: Signal in [Events.ancestry_chosen, Events.talent_learned, Events.hud_message]:
		for c: Dictionary in sig.get_connections():
			if (c.callable as Callable).get_object() == self:
				sig.disconnect(c.callable)
	Quests.reset_for_tests()
	await super()


func _on_chosen(_t: int, id: String) -> void:
	chosen.append(id)


func _on_learned(_t: int, id: String) -> void:
	learned.append(id)


func _on_hud(text: String, _kind: String) -> void:
	hud.append(text)


## A giant with `state` applied (a character dictionary), standing.
func _giant(state: Dictionary, pos := Vector3(0, 0.05, 0)) -> GiantPlayer:
	var p := spawn_player(pos)
	await step_ticks(1)
	p.apply_character_state(CharacterState.normalize(state))
	await step_ticks(1)
	return p


func test_the_ancestry_is_chosen_once_in_the_old_kingdom_and_stays_chosen() -> void:
	var st := CharacterState.world_start(Progression.record(), GameData.get_record("player.giant"))
	(st.loadout.slots as Array)[7] = ""   # one free slot for the signature
	var p := await _giant(st)
	var prog: PlayerProgression = p.progression
	var c := p.entity.combatant
	assert_false(prog.ancestry_chosen, "the world start's giant has no ancestry yet")
	assert_false(prog.ancestry_offered(), "not offered before the Old Kingdom")
	assert_eq(str(prog.choose_ancestry("ancestry.stoneblood").reason), "not_yet", "refused in the prologue")
	assert_eq(prog.ancestry_line(), "Ancestry: Unaligned — your blood awakens when you reach the Old Kingdom",
		"the attribute screens say when")
	WorldState.set_flag(Talents.WORLD_FLAG, true)   # GameSession sets it on entering the world
	assert_true(prog.ancestry_offered(), "offered once the world has opened")
	assert_eq(prog.ancestry_line(), "Ancestry: Unaligned — choose yours at a shrine of the Old Kingdom", "and where")
	assert_eq(str(prog.choose_ancestry("ancestry.neutral").reason), "unknown", "the prologue's ancestry is no choice")
	c.pools.mark_combat()
	assert_eq(str(prog.choose_ancestry("ancestry.stoneblood").reason), "combat", "not during combat")
	c.pools.since_combat = 999.0
	assert_eq(chosen, [], "nothing chosen by a refusal")
	# The prompt at the first shrine of the Old Kingdom, and the quest: stage 4 without an ancestry.
	Fx.activate(["quest.ancestry"], ["tutorial.ancestry"])
	Quests.evaluate_now()   # Quests meet this giant (a new player starts a new level memory)
	Events.shrine_activated.emit(Sim.tick, "world.shrine.kingsgate")
	await step_ticks(1)
	assert_eq(str(Quests.current_tutorial().get("id", "")), "tutorial.ancestry", "a world shrine shows the ancestry prompt")
	assert_eq(Quests.quest_state("quest.ancestry"), Quests.INACTIVE, "not at stage 3")
	p.set_profile(GameData.get_record("growth.04"))
	Quests.evaluate_now()
	assert_eq(Quests.quest_state("quest.ancestry"), Quests.ACTIVE, "stage 4 without an ancestry: the quest starts")
	# The choice.
	var attrs := prog.attributes()
	var hp_max := c.pools.health_max
	var threshold := c.poise.threshold
	var armor := c.armor_total()
	var xp := prog.xp
	var out := prog.choose_ancestry("ancestry.stoneblood")
	assert_true(out.ok, "Stoneblood chosen (%s)" % out.get("message", ""))
	assert_eq(chosen, ["ancestry.stoneblood"], "ancestry_chosen once, with the id")
	assert_eq(str(WorldState.get_flag(Talents.CHOSEN_FLAG)), "ancestry.stoneblood", "the flag ancestry.chosen")
	assert_true(hud.has("Your blood answers: you are Stoneblood"), "the HUD says so (%s)" % [hud])
	var now := prog.attributes()
	assert_eq([int(now.constitution) - int(attrs.constitution), int(now.endurance) - int(attrs.endurance),
		int(now.strength) - int(attrs.strength)], [3, 2, 0], "Constitution +3, Endurance +2, nothing else")
	assert_near(c.pools.health_max, hp_max + 2 * 15.0, 1e-6, "Endurance +2: 30 more health")
	assert_near(c.poise.threshold, threshold + 3 * 3.0 + 20.0, 1e-6, "Constitution +3 and the passive: poise +29")
	assert_near(c.armor_total(), armor + 10.0, 1e-6, "armour +10")
	assert_true(prog.knows("ability.bedrock_ward"), "the signature is learned")
	assert_eq(str(p.controller.loadout.slot_8), "ability.bedrock_ward", "into the free slot")
	assert_eq(str(out.signature), "ability.bedrock_ward", "the result names it")
	assert_eq(prog.ancestry_line(),
		"Ancestry: Stoneblood — Endurance +2, Constitution +3; Armour +10, Poise (staggers less) +20; Bedrock Ward",
		"the attribute screens name what it gives")
	await step_ticks(1)
	assert_eq(Quests.quest_state("quest.ancestry"), Quests.COMPLETED, "the quest completes")
	assert_eq(prog.xp - xp, 30, "for its 30 XP")
	assert_eq(str(Quests.current_tutorial().get("id", "")), "", "and the choice dismisses the prompt")
	# Once.
	assert_eq(str(prog.choose_ancestry("ancestry.wildheart").reason), "chosen", "a second ancestry is refused")
	assert_eq(str(prog.choose_ancestry("ancestry.stoneblood").reason), "chosen", "and the same one again")
	assert_eq(prog.attributes(), now, "nothing added twice")
	assert_false(prog.ancestry_offered(), "no longer offered")
	assert_eq(chosen.size(), 1, "one event in all")
	# A save and a load.
	var json: Dictionary = JSON.parse_string(JSON.stringify(CharacterState.normalize(p.capture_character_state())))
	assert_eq([json.ancestry, json.ancestry_chosen], ["ancestry.stoneblood", true], "saved")
	var passives := c.passives.duplicate()
	p.queue_free()
	await step_ticks(2)
	var q := await _giant(json, Vector3(8, 0.05, 0))
	assert_eq(q.progression.ancestry, "ancestry.stoneblood", "loaded")
	assert_true(q.progression.ancestry_chosen and not q.progression.ancestry_offered(), "chosen, not offered again")
	assert_eq(q.progression.attributes(), now, "the attributes as saved (the bonus not added again)")
	assert_eq(q.entity.combatant.passives, passives, "the same passives")
	assert_true(q.known_abilities.has("ability.bedrock_ward"), "the signature stays known")
	assert_eq(chosen.size(), 1, "a load emits nothing")


func test_a_migrated_prologue_save_is_offered_the_choice_and_buys_talents() -> void:
	var doc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	assert_eq(int(doc.schema_version), 1, "a v1 save of a finished prologue")
	var m := SaveSlots.migrate(doc)
	var ch: Dictionary = m.character
	assert_eq([ch.talents, ch.ancestry_chosen], [[], false], "migrated: no talents, no ancestry chosen")
	var p := await _giant(ch)
	var prog: PlayerProgression = p.progression
	assert_eq([prog.level, prog.talent_points], [7, int(doc.character.talent_points)],
		"level 7 with the prologue's unspent talent points")
	assert_false(prog.ancestry_offered(), "the Valley does not offer it")
	WorldState.set_flag(Talents.WORLD_FLAG, true)
	assert_true(prog.ancestry_offered(), "the Old Kingdom does: the migrated save gets the same choice")
	var out := prog.choose_ancestry("ancestry.wildheart")
	assert_true(out.ok, "Wildheart chosen")
	assert_near(p.motor.status_speed_mult(), 1.05, 1e-9, "its speed at once")
	assert_true(prog.knows("ability.wild_surge"), "and its signature")
	# Talents with the carried-over points.
	var points := prog.talent_points
	assert_eq(str(prog.learn_talent("talent.guardian_bulwark").reason), "level", "tier 2 waits for level 8")
	assert_eq(prog.talent_points, points, "a refusal spends nothing")
	var r := prog.learn_talent("talent.guardian_stone_hide")
	assert_true(r.ok and int(r.spent) == 1, "Stone Hide learned for one point")
	assert_eq(prog.talent_points, points - 1, "spent once")
	assert_eq(learned, ["talent.guardian_stone_hide"], "talent_learned")
	assert_true(hud.has("Talent learned: Stone Hide"), "announced")
	assert_eq(str(prog.learn_talent("talent.guardian_stone_hide").reason), "known", "a second time: known")
	assert_eq(prog.talent_points, points - 1, "not spent again")
	assert_eq(prog.talent_line(), "Talent points: %d — talents: Stone Hide" % (points - 1), "the inventory's line")
	p.entity.combatant.pools.mark_combat()
	assert_eq(str(prog.learn_talent("talent.guardian_steady_stance").reason), "combat", "never during combat")
