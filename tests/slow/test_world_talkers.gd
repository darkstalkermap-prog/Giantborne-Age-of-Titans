extends IntegrationSuite
## M8 gate (F5): the world's talkers that name a spawned actor (P36's talker kind) end with the actor's
## death after their chunk loads again, as they do live. The real props parts: Skarn's (Ulfra's talk,
## c5_1_0) and the Moot's (Harrok's challenge stone, c3_1_0). Ulfra's talker and the stone talk while
## their speakers live; with each speaker's death recorded (as the director records a persist_death
## kill) the chunk loaded again holds a silent talker - the stone is Harrok's voice and goes with him
## (decided at the gate: its dialogue's "empty" entry is not reached through the stone). Corvane's
## parley horn names its own id, not Corvane's, and keeps answering.

const SKARN := "res://scenes/world/chunks/c5_1_0.tscn"
const MOOT := "res://scenes/world/chunks/c3_1_0.tscn"
const FORT := "res://scenes/world/chunks/c6_3_0.tscn"
const SPEAKERS := {"world.stonehold.ulfra": SKARN, "world.stonehold.harrok": MOOT}


func _talker_for(part: Node, npc: String) -> NpcTalker:
	for n in part.find_children("*", "", true, false):
		if n is NpcTalker and (n as NpcTalker).resolved_npc_id() == npc:
			return n
	return null


func _load(path: String) -> Node3D:
	var part := (load(path) as PackedScene).instantiate() as Node3D
	world.add_child(part)
	await step_ticks(2)
	return part


func test_talkers_of_the_dead_stay_silent_after_their_chunk_loads_again() -> void:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	for npc: String in SPEAKERS:
		var part := await _load(SPEAKERS[npc])
		var t := _talker_for(part, npc)
		assert_true(t != null, "%s's talker is in %s" % [npc, SPEAKERS[npc].get_file()])
		if t == null:
			continue
		assert_true(t.enabled and t.can_interact(p), "%s's talker talks while the speaker lives" % npc)
		part.queue_free()
		await step_ticks(2)
		WorldState.record_killed(npc)
		part = await _load(SPEAKERS[npc])
		t = _talker_for(part, npc)
		assert_true(t != null, "%s's talker is made again" % npc)
		if t == null:
			continue
		assert_false(t.enabled, "%s's talk stays ended after the chunk loads again" % npc)
		assert_false(t.can_interact(p), "%s's talker cannot talk (prompt '%s')" % [npc, t.prompt_text(p)])
		part.queue_free()
		await step_ticks(2)
	var fort := await _load(FORT)
	var horn := _talker_for(fort, "world.aldmere.fort_parley")
	assert_true(horn != null, "the parley horn is in the fort's part")
	if horn != null:
		WorldState.record_killed("world.aldmere.corvane")
		assert_true(horn.enabled and horn.can_interact(p), "the horn names itself: it answers whatever became of Corvane")
