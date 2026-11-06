extends TestSuite
## P21 (plan M6-M9 §3.3 gate test; the gate tier of decision 34, tools/check.sh --gate): the
## effect banks beyond the default suite's synthetic events. The "missing" counter - requests that
## resolve to no cue - stays 0 through
##   * the seeded 120 s sandbox soak, run in its own process with the audio engine and
##     --audio-stats (P19's run_soak): more than 100 cues played, no errors;
##   * a scripted Valley pass with the audio engine on: the walkthrough's teleport route (P15's
##     helpers, its force outcome: New Game at the Cradle, the Old Wood's wolves, hunters and ogre,
##     the Grove's shrine and growth, the cairn, the road patrol, Thornwick and its elder, the guards
##     turned hostile, the smashed barricade, a death and a checkpoint reload, the King's Bridge, the
##     practice gate, the courtyard and the armory, Kingsfall's shrine, the Ogre King, growth to
##     stage 3, the oak, the Giantforge, the return patrol, the ambush, the Deadfall, the Barrow's
##     wardens and the crown) with three additions: walks on the Valley's grounds (the Hollow's
##     grass at stage 1, the King's Bridge over the river and the ruins at stage 2) and a real fight
##     with the quarry raiders at stage 1 (their AI on, the giant unkillable) for the threat cues.
##     Every effect played comes from a P21 bank and none falls back to its family's default; every
##     family is heard (hits, voices, falls, breaks, cracks, the world, the interface, steps, threat
##     cues) and the footfalls follow the ground: soft grass, the wet river crossing, hard ruins.
## The pass frees the engine's voices every frame: the Dummy driver plays in real time while the run
## goes several times faster, so most requests would otherwise find their cue's voices still busy
## (capped, not logged). Runs in about a minute and a half with the soak.

const SOAK_S := 120
const SOAK := preload("res://tests/gate/test_audio_determinism.gd")
const WALKTHROUGH := preload("res://tests/slow/test_valley_walkthrough.gd")
const P21_BANKS := ["audio_bank.combat", "audio_bank.abilities", "audio_bank.steps", "audio_bank.voices",
	"audio_bank.threat", "audio_bank.world", "audio_bank.ui"]
## Requested cues (prefixes) the pass must hear.
## (The walkthrough calls interact() directly, which sends no `interacted`; an arrow's launch from
## the quarry's archers, 20 m off, is under the human class's audible level - their bows' twang is
## heard.)
const HEARD := ["sfx.hit.", "sfx.voice.", "sfx.body.fall.", "sfx.break.", "sfx.crack.", "sfx.swing.",
	"sfx.ability.", "sfx.player.death", "sfx.player.hurt", "sfx.world.shrine_wake", "sfx.world.waystone",
	"sfx.world.growth", "sfx.world.forge_upgrade", "sfx.world.gate_iron", "sfx.world.alarm_bell",
	"sfx.ui.saved", "sfx.ui.loot", "sfx.ui.item", "sfx.ui.equip.", "sfx.threat.windup.",
	"sfx.threat.aim_lock", "sfx.threat.sting"]
const RAIDERS := "encounter.quarry_raiders"
const RAIDERS_FIGHT_TICKS := 480
const WALK_TICKS := 360

## Effect cue id -> times played.
var played: Dictionary = {}
## Requested cue id -> times.
var requested: Dictionary = {}
## "<requested> -> <cue>" for every request that fell back to its family's default.
var defaults: Array[String] = []
## Effect cues played from a bank that is not P21's.
var foreign: Array[String] = []
## The player's footfalls: [segment, requested cue, position].
var steps: Array = []
## The pass's current stretch (the footfalls are checked per stretch).
var segment := ""
## Threat cues heard during the raiders' fight.
var fight_cues: Array[String] = []


func before_each() -> void:
	played.clear()
	requested.clear()
	defaults.clear()
	foreign.clear()
	steps.clear()
	fight_cues.clear()
	segment = ""


func after_each() -> void:
	if get_tree().process_frame.is_connected(_harvest):
		get_tree().process_frame.disconnect(_harvest)
	Audio.enable_for_tests(false)


## Takes the cue log (cleared after each read) and frees the voices.
func _harvest() -> void:
	if not Audio.enabled:
		return
	for e: Dictionary in Audio.cue_log():
		var cue := str(e.cue)
		if not cue.begins_with("sfx."):
			continue
		var req := str(e.requested)
		played[cue] = int(played.get(cue, 0)) + 1
		requested[req] = int(requested.get(req, 0)) + 1
		var bank := str(Audio.resolve(cue).get("bank", ""))
		if not P21_BANKS.has(bank) and not foreign.has("%s (%s)" % [cue, bank]):
			foreign.append("%s (%s)" % [cue, bank])
		if cue.ends_with(".default") and req != cue and not defaults.has("%s -> %s" % [req, cue]):
			defaults.append("%s -> %s" % [req, cue])
		if req.begins_with("sfx.step.giant_"):
			steps.append([segment, req, e.pos])
		if segment == "raiders" and cue.begins_with("sfx.threat."):
			fight_cues.append(cue)
	Audio.clear_log()
	Audio.pool.stop_all()


func _heard(prefix: String) -> bool:
	for req: String in requested:
		if req.begins_with(prefix):
			return true
	return false


# --------------------------------------------------------------------------- the soak

func test_the_seeded_soak_resolves_every_request() -> void:
	var on := SOAK.run_soak(true, SOAK_S)
	assert_eq(int(on.code), 0, "the soak with audio exits cleanly")
	assert_true(str(on.result).contains("\"errors\":0"), "no errors: %s" % str(on.result).left(300))
	var stats: Variant = JSON.parse_string(str(on.stats))
	assert_true(typeof(stats) == TYPE_DICTIONARY, "the audio run printed its stats: %s" % str(on.stats).left(200))
	if typeof(stats) == TYPE_DICTIONARY:
		assert_eq((stats.get("missing", {}) as Dictionary).size(), 0,
			"every request of the soak resolved: %s" % [stats.get("missing")])
		assert_true(int(stats.get("played", 0)) > 100, "the soak played (%d cues)" % int(stats.get("played", 0)))


# --------------------------------------------------------------------------- the Valley pass

func test_the_valley_pass_sounds_from_the_banks() -> void:
	var w: Variant = WALKTHROUGH.new()
	w.name = "Walkthrough"
	add_child(w)
	w.current_test = current_test + " (walkthrough helpers)"
	await w.before_each()
	Audio.enable_for_tests()
	get_tree().process_frame.connect(_harvest)
	w.outcome = "force"
	segment = "new_game"
	await w._new_game()
	assert_true(await TestWait.until(self, func() -> bool: return Audio.is_ready(), 600), "the Valley's samples are registered")
	assert_eq(int(Audio.stats.registered), Audio.sample_paths_for("level.valley").size(), "every sample of the Valley")
	# The Hollow's grass at stage 1.
	var p: GiantPlayer = w.player
	segment = "hollow"
	await _walk_to(p, p.global_position + Vector3(14, 0, -14))
	# The quarry raiders fight for real at stage 1.
	segment = "raiders"
	await _raiders_fight(w)
	segment = "route"
	await w._forest_to_the_grove()
	await w._road_to_thornwick()
	await _force_the_village(w)
	if w.player == null:
		await _finish(w)
		return
	# The King's Bridge over the river at stage 2: wet from bank to bank.
	segment = "bridge"
	p = w.player
	await w._go(Vector3(94, 0, -20), -PI * 0.5)
	await _walk_to(p, Vector3(117, 0, -20))
	segment = "route"
	await w._bridge_to_the_causeway()
	# The ruins at stage 2: hard stone.
	segment = "ruins"
	await w._go(Vector3(140, 0, -20), -PI * 0.5)
	await _walk_to(p, Vector3(155, 0, -6))
	segment = "route"
	await w._kingsfall()
	await w._giantforge("weapon.club")
	await w._return_leg()
	await w._assert_the_end("force")
	_harvest()
	await _finish(w)
	_check_the_pass()


## The walkthrough's force outcome at Thornwick (its own test's steps): the elder is left, two
## blows on a guard turn the village hostile, the guards fall, the elder sends the giant away, the
## barricade is smashed, and a death reloads the Thornwick checkpoint.
func _force_the_village(w: Variant) -> void:
	var s: DialogueSession = await w._talk_to_elder()
	if s == null:
		return
	var leave := -1
	for c: Dictionary in s.choices():
		if str(c.text) == "Not now.":
			leave = int(c.index)
	assert_true(leave >= 0, "the giant may walk away")
	s.choose(leave)
	await w._end_talk()
	var guard := (w.director as EncounterDirector).spawned("valley.village.guard_1") as EnemyActor
	assert_true(guard != null, "a guard stands in the village")
	if guard == null:
		return
	await w._go(guard.global_position + Vector3(-4, 0, 0), -PI * 0.5)
	w._strike("valley.village.guard_1", 1.0)
	await step_ticks(3)
	w._strike("valley.village.guard_1", 1.0)
	await step_ticks(3)
	assert_true(FactionState.is_hostile("village"), "two blows turn the village hostile")
	await w._clear_encounter("encounter.village_guards")
	s = await w._talk_to_elder()
	if s != null:
		await w._end_talk()
	var barricade := w._prop("valley.village.barricade") as BreakableProp
	await w._go(barricade.global_position + Vector3(-7, 0, 0), -PI * 0.5)
	w._strike("valley.village.barricade", 1.0e6)
	await step_ticks(3)
	assert_true(barricade.destroyed, "the barricade is smashed")
	await w._village_settled("force")
	await w._death_and_reload("force", "valley.shrine.thornwick")


## The quarry raiders (two soldiers, archers and a mage) against the stage-1 giant with their AI on
## for RAIDERS_FIGHT_TICKS, the camera turned away from them (so blows come from behind it); then
## they fall to the walkthrough's synthetic blows and the giant is made whole again.
func _raiders_fight(w: Variant) -> void:
	var p: GiantPlayer = w.player
	var d: EncounterDirector = w.director
	p.entity.combatant.unkillable = true
	await w._go(w._marker("valley.marker.quarry_cache") + Vector3(0, 0, 14), PI)
	d.force_activate(RAIDERS)
	d.update_now()
	var ids := d.members_of(RAIDERS)
	await TestWait.until(self, func() -> bool:
		for id in ids:
			if d.spawned(id) == null:
				return false
		return true, 30)
	var centre := Vector3.ZERO
	var n := 0
	for id in ids:
		var e := d.spawned(id) as EnemyActor
		if e != null:
			e.ai_enabled = true
			centre += e.global_position
			n += 1
	assert_true(n >= 4, "the raiders are up (%d)" % n)
	if n > 0:
		centre /= float(n)
		var away := p.global_position - centre
		p.camera_rig.yaw = TargetingRules.yaw_of(Vector3(away.x, 0, away.z))
	await step_ticks(RAIDERS_FIGHT_TICKS)
	_harvest()
	await w._clear_encounter(RAIDERS)
	p.entity.combatant.unkillable = false
	var pools := p.entity.combatant.pools
	pools.restore({"health": pools.health_max, "stamina": pools.stamina_max})
	await step_ticks(2)


## Walks `p` straight towards `to` with the stick (camera along the way) until it is within 1.2 m
## or WALK_TICKS pass.
func _walk_to(p: GiantPlayer, to: Vector3) -> void:
	for i in WALK_TICKS:
		var d := to - p.global_position
		d.y = 0.0
		if d.length() < 1.2:
			break
		var yaw := TargetingRules.yaw_of(d)
		p.camera_rig.yaw = yaw
		p.router.set_injected_move(ValleyProbe.stick_toward(d, yaw))
		await step_ticks(1)
	p.router.set_injected_move(Vector2.ZERO)
	await step_ticks(20)
	_harvest()


## Ends the walkthrough helpers' test (its after_each) and takes over its checks and failures.
func _finish(w: Variant) -> void:
	_harvest()
	await w.after_each()
	checks += int(w.checks)
	failures.append_array(w.failures)
	remove_child(w)
	w.queue_free()


func _check_the_pass() -> void:
	assert_eq(Audio.missing.size(), 0, "no request of the Valley pass resolved to nothing: %s" % [Audio.missing])
	assert_eq(foreign, [] as Array[String], "every effect came from a P21 bank")
	assert_eq(defaults, [] as Array[String], "no request fell back to its family's default")
	var total := 0
	for c: String in played:
		total += int(played[c])
	assert_true(total > 150 and played.size() >= 40, "the pass played %d effects (%d different cues)" % [total, played.size()])
	for prefix: String in HEARD:
		assert_true(_heard(prefix), "the pass heard %s*" % prefix)
	assert_true(fight_cues.has("sfx.threat.windup.line") or fight_cues.has("sfx.threat.windup.circle")
		or fight_cues.has("sfx.threat.windup.cone"), "the raiders' blows wind up audibly: %s" % [fight_cues])
	assert_true(fight_cues.has("sfx.threat.aim_lock"), "their archers' aim locks are heard")
	assert_true(fight_cues.has("sfx.threat.sting"), "a blow from behind the camera stings")
	# The footfalls follow the ground.
	for stretch: Array in [["hollow", "giant_s1.soft"], ["bridge", "giant_s2.wet"], ["ruins", "giant_s2.hard"]]:
		var mine := steps.filter(func(s: Array) -> bool: return s[0] == stretch[0])
		assert_true(mine.size() >= 3, "%s: the giant's footfalls are heard (%d)" % [stretch[0], mine.size()])
		for s: Array in mine:
			assert_true(str(s[1]).begins_with("sfx.step." + str(stretch[1])),
				"%s: a footfall at %s sounds %s (%s)" % [stretch[0], s[2], stretch[1], s[1]])
