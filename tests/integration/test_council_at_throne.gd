extends IntegrationSuite
## Fix (council; docs/systems/fix_council.md): act two's first stage, "Hear the oath-holders at the Stone Throne", at
## the real Moot (its two chunks: the throne and the oath-stone, the rim council's stone west of the throne).
##   * the owner's report: at the stage's marker (world.marker.stone_throne, 14 m before the throne) a giant was offered
##     only "Take the Stone Throne" and E answered "The Stone Throne is yours" - the council's stone stands 30 m off,
##     outside its reach. Now the taken throne opens the rim council there, for a giant of stage 6 to 9, facing any
##     way, ahead of the oath-stone;
##   * the throne between the claim and act two's start (the finale playing) offers nothing; before the claim it is
##     "Take the Stone Throne" as before;
##   * leaving the council's talk early (Esc) strands nothing: the stage stays open and the throne offers it again;
##     heard out, the flag is set and the talk can be heard again;
##   * the oath-stone before the rumour of Harrok's banner is quiet (it spoke of Orrik and sent a spared Harrok's
##     giant to his stone from act one's end) and, while the council waits, points at the throne;
##   * a begun act two with a pledge unanswered (the council's line for it would offer only Leave) is answered on
##     entering the world.

## The two chunks and their origins in the world (the streamer places a chunk at its cell's corner).
const MOOT_PARTS := {"res://scenes/world/chunks/c4_0_0.tscn": Vector3(0, 0, -1024),
	"res://scenes/world/chunks/c3_0_0.tscn": Vector3(-256, 0, -1024)}
const THRONE := "world.stonehold.stone_throne"
const COUNCIL := "world.stonehold.rim_council"
const OATH := "world.stonehold.throne_stone"
const MARKER := Vector2(0.0, -786.0)

var part: Node3D
var requests: Array = []
var huds: Array = []


func before_each() -> void:
	await super()
	requests.clear()
	huds.clear()
	Events.dialogue_requested.connect(_on_requested)
	Events.hud_message.connect(_on_hud)


func after_each() -> void:
	for s: Signal in [Events.dialogue_requested, Events.hud_message]:
		for c: Dictionary in s.get_connections():
			if (c.callable as Callable).get_object() == self:
				s.disconnect(c.callable)
	Quests.end_dialogue()
	part = null
	await super()


func _on_requested(npc: String, dialogue: String) -> void:
	requests.append([npc, dialogue])


func _on_hud(text: String, _kind: String) -> void:
	huds.append(text)


## The Moot's chunks and a giant of `stage`.
func _moot(stage: int) -> GiantPlayer:
	part = Node3D.new()
	world.add_child(part)
	for path: String in MOOT_PARTS:
		var chunk := (load(path) as PackedScene).instantiate() as Node3D
		chunk.position = MOOT_PARTS[path]
		part.add_child(chunk)
	var p := spawn_player(Vector3(0, 0.05, -770), 0.0)
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	p.set_profile(TitanDuel.profile(stage))
	await step_ticks(2)
	return p


func _node(id: String) -> Interactable:
	for n in part.find_children("*", "", true, false):
		if n is Interactable and ((n as Interactable).interact_id == id or ("world_id" in n and str(n.get("world_id")) == id)):
			return n
	return null


## The giant standing at `xz` facing `toward` (its prompt's candidate after a refresh).
func _at(p: GiantPlayer, xz: Vector2, toward: Vector2) -> Dictionary:
	p.global_position = Vector3(xz.x, 0.05, xz.y)
	var d := toward - xz
	p.facing_yaw = atan2(-d.x, -d.y)
	p.rotation.y = p.facing_yaw
	p.interact.refresh()
	return p.interact.current_candidate()


func _act_two(slain := false) -> void:
	WorldState.set_flag("boss.harrok.outcome", "slain" if slain else "spared")
	WorldState.set_flag("world.throne.claimed", true)
	WorldState.flags["campaign.completed"] = true
	ActTwo.begin(Callable(WorldState, "try_set_flag"), Quests.condition_context())


func test_at_the_marker_the_taken_throne_opens_the_council_for_every_size_and_facing() -> void:
	for stage: int in [6, 7, 8, 9]:
		WorldState.clear()
		var p := await _moot(stage)
		var throne := _node(THRONE) as StoneThrone
		assert_true(throne != null and _node(COUNCIL) != null and _node(OATH) != null, "stage %d: the Moot's three" % stage)
		assert_true(Vector2(throne.global_position.x, throne.global_position.z).distance_to(Vector2(0, -800)) < 0.1,
			"(the chunks where the world has them: the throne at (0, -800))")
		var c := _at(p, MARKER, Vector2(0, -800))
		assert_eq(str(c.get("prompt", "")), StoneThrone.DEFAULT_PROMPT, "stage %d: before the claim, the throne to take" % stage)
		WorldState.set_flag("boss.harrok.outcome", "spared")
		WorldState.set_flag("world.throne.claimed", true)
		c = _at(p, MARKER, Vector2(0, -800))
		assert_true(c.is_empty(), "stage %d: taken, before act two begins (the finale), nothing at the throne (%s)" % [stage, c])
		_act_two()
		for toward: Vector2 in [Vector2(0, -800), Vector2(-30, -790), Vector2(22, -792), Vector2(0, -700), Vector2(80, -786),
				Vector2(-80, -786)]:
			c = _at(p, MARKER, toward)
			assert_eq(str(c.get("id", "")), THRONE, "stage %d at the marker facing %s: the throne (%s)" % [stage, toward, c])
			assert_eq(str(c.get("prompt", "")), "Hear the oath-holders at the throne", "stage %d facing %s: the council's prompt" % [stage, toward])
		# beside the oath-stone, the throne still leads (and the stone's own talk, below, points at it)
		c = _at(p, Vector2(14, -790), Vector2(22, -792))
		assert_eq(str(c.get("id", "")), THRONE, "stage %d beside the oath-stone: the throne first (%s)" % [stage, c])
		requests.clear()
		huds.clear()
		_at(p, MARKER, Vector2(0, -800))
		p.interact.use_candidate(p.interact.current_candidate())
		assert_eq(requests, [[COUNCIL, "dialogue.rim_council"]], "stage %d: E opens the rim council" % stage)
		assert_false(huds.has(throne.claimed_message), "stage %d: not 'the throne is yours'" % stage)
		Quests.end_dialogue()
		part.queue_free()
		p.queue_free()
		await step_ticks(2)


func test_leaving_the_council_early_strands_nothing_and_hearing_it_out_completes_it() -> void:
	var p := await _moot(6)
	_act_two(true)
	var s := Quests.start_dialogue("dialogue.rim_council", COUNCIL)
	assert_eq(s.node_id, "open", "the council opens")
	s.choose(0)
	Quests.end_dialogue()   # Esc mid-way
	assert_false(QuestConditions.truthy(WorldState.get_flag("act_two.council_heard")), "left early: not heard")
	var c := _at(p, MARKER, Vector2(0, -800))
	assert_eq(str(c.get("prompt", "")), "Hear the oath-holders at the throne", "the throne offers it again")
	s = Quests.start_dialogue("dialogue.rim_council", COUNCIL)
	assert_eq(s.node_id, "open", "from the start")
	var guard := 0
	while s.is_active() and guard < 20:
		var ch: Array = s.choices()
		if s.node_id != "close":
			assert_false(bool((ch[0] as Dictionary).implicit), "a line of the council at %s, not only Leave" % s.node_id)
		s.choose(0)
		guard += 1
	assert_true(QuestConditions.truthy(WorldState.get_flag("act_two.council_heard")), "heard out")
	c = _at(p, MARKER, Vector2(0, -800))
	assert_eq(str(c.get("id", "")), THRONE, "the throne still answers after")
	s = Quests.start_dialogue("dialogue.rim_council", COUNCIL)
	assert_eq(s.node_id, "heard", "and can be heard again")


func test_the_oath_stone_is_quiet_before_the_rumour_and_points_at_the_throne() -> void:
	var oath := GameData.get_record("dialogue.moot_oath")
	var ctx := QuestConditions.empty_context()
	for ending: String in ["slain", "spared", "yielded_talk"]:
		ctx.flags = {"boss.harrok.outcome": ending, "world.throne.claimed": true, "act.two.begun": true}
		var node := DialogueSession.start_node(oath, ctx)
		assert_eq(node, "quiet_council", "%s, the council waiting: the oath-stone points at the throne" % ending)
		assert_true(str(DialogueSession.node_record(oath, node).text).contains("throne"), "%s: it names the throne" % ending)
		ctx.flags["act_two.council_heard"] = true
		assert_eq(DialogueSession.start_node(oath, ctx), "quiet", "%s, heard, before the rumour: quiet" % ending)
	ctx.flags = {"boss.harrok.outcome": "slain", "lead.harrok.hearth": true}
	assert_eq(DialogueSession.start_node(oath, ctx), "waiting", "the rumour heard, Harrok slain: the eldest tells of Orrik")
	ctx.flags = {"boss.harrok.outcome": "spared", "lead.harrok.hearth": true}
	assert_eq(DialogueSession.start_node(oath, ctx), "harrok_speaks", "spared: Harrok speaks for the clan")


func test_a_begun_act_two_with_a_pledge_unanswered_is_answered_on_entering_the_world() -> void:
	GameSession.start_world_for_tests("world.cp.moot_foot")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	WorldState.set_flag("boss.harrok.outcome", "spared")
	WorldState.set_flag("campaign.completed", true)
	ActTwo.begin(Callable(WorldState, "try_set_flag"), Quests.condition_context())
	var before := str(WorldState.get_flag("pledge.brannock"))
	WorldState.flags.erase("pledge.harrok_clan")
	var ctx := QuestConditions.empty_context()
	ctx.flags = WorldState.flags
	var s := DialogueSession.start_node(GameData.get_record("dialogue.rim_council"), ctx)
	assert_eq(s, "open", "(the council opens)")
	Events.level_entered.emit(Sim.tick, GameSession.WORLD_LEVEL_ID, "continue")
	await step_ticks(2)
	assert_eq(str(WorldState.get_flag("pledge.harrok_clan")), "sends", "the missing pledge answered")
	assert_eq(str(WorldState.get_flag("pledge.brannock")), before, "a given one unchanged")
	GameSession.expansion = ExpansionState.defaults()
