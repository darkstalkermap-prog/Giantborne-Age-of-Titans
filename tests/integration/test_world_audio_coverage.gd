extends IntegrationSuite
## P28 (plan M6-M9 §3.11 tests, §4.1 M7-M9 rows, §4.3, §4.5): the world sounds - every region and
## every place of the ambience map resolves its music set and its ambience, by the world's records:
##   * every world region and every place POI of §4.3 (Brannock, Millford, Hollowmere, the war
##     camp, Skarn, the Troll Den, the Titan's Bones, the Moot) wins its own audio_region at its
##     position, whose music set's stems and ambience set's beds, spots and emitters all resolve;
##   * walking from the Crownmarch into Brannock keeps the Crownmarch's set (with the town's
##     quieter melody and longer rests) and cross-fades the beds; on into the Greywood the Greywood's
##     set comes in at the next bar over two bars, at the Crownmarch's place in the shared frame;
##     entering Brannock at stage 4 rings the town bell and gasps once a visit;
##   * the world's audio stays within its 5.5 MB, and the world registers at most 170 s of samples;
##   * every planned voice of §4.1's M7-M9 rows resolves its calls from the world's banks, and the
##     records that will carry them (by archetype or id) find them before the mix names them; every
##     cue the router asks for the M7-M9 events resolves to itself, and a run of those events
##     through the router plays with nothing missing.

const WORLD := "level.world"
## The places of §4.3's ambience map (their POIs), and each one's set and ambience.
const PLACES := {
	"poi.brannock": ["music.crownmarch", "ambience.town"],
	"poi.millford": ["music.crownmarch", "ambience.town"],
	"poi.hollowmere": ["music.greywood", "ambience.greywood"],
	"poi.war_camp": ["music.aldmere", "ambience.camp"],
	"poi.skarn": ["music.stonehold", "ambience.hearth"],
	"poi.troll_den": ["music.greywood", "ambience.cave"],
	"poi.titans_bones": ["music.drowned_steps", "ambience.bones"],
	"poi.the_moot": ["music.stonehold", "ambience.moot"],
}
## A point of each region away from its places (x, z).
const REGION_POINTS := {
	"region.crownmarch": Vector2(-100, 760), "region.greywood": Vector2(-500, -150),
	"region.drowned_steps": Vector2(-60, -150), "region.aldmere": Vector2(600, 0),
	"region.stonehold": Vector2(200, -800),
}
## The Crownmarch 110 m north of Brannock's centre, Brannock's centre, and the Greywood across the
## region line west of Millford (25 m in).
const MARCH := Vector3(60, 10, 640)
const BRANNOCK := Vector3(60, 10, 450)
const GREYWOOD := Vector3(-345, 25, 290)
## §4.1's M7-M9 voices and the calls each makes (the far versions of the big ones included).
const VOICES := {
	"troll": ["alert", "attack", "hurt", "stagger", "death", "flee", "roar", "far"],
	"matriarch": ["alert", "attack", "hurt", "stagger", "death", "flee", "roar", "far"],
	"giant": ["alert", "attack", "hurt", "stagger", "death", "flee", "bellow", "greet", "far"],
	"dire_wolf": ["alert", "attack", "hurt", "stagger", "death", "flee"],
	"horse": ["alert", "attack", "hurt", "stagger", "death", "flee"],
	"crowd": ["flee", "abandon", "gasp", "murmur", "cheer"],
}
const WORLD_BANKS := ["audio_bank.world_steps", "audio_bank.world_voices", "audio_bank.world_threat",
	"audio_bank.world_objects", "audio_bank.world_abilities", "audio_bank.world_ui", "audio_bank.world_stingers",
	"audio_bank.world_ambience"]
## The world adds at most this much audio (plan §4.5).
const WORLD_BUDGET_BYTES := 5.5 * 1048576.0
const WORLD_REGISTERED_CAP_S := 170.0


## A world level without its streamed ground: the world index's regions, and nothing else.
class WorldStub extends LevelRoot:
	func region_at(pos: Vector3) -> String:
		var idx := index()
		return idx.region_at(pos) if idx != null else ""

	func create_runtime_nodes(_entries: Array = RUNTIME_NODES) -> Array[Node]:
		return []


func before_each() -> void:
	await super()
	Audio.enable_for_tests()
	Audio.music.clock_positions = true


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


func _world() -> WorldStub:
	var lv := WorldStub.new()
	lv.name = "WorldStub"
	lv.level_id = WORLD
	world.add_child(lv)
	Audio.is_ready()   # detects the level and queues its samples
	# The loading gate's registration is test_audio_director's and test_sfx_valley_pass's: here the
	# queue is dropped (registering is a no-op on desktop and plays load lazily), for the time budget.
	Audio._reg_queue.clear()
	return lv


static func _poi_pos(poi_id: String) -> Vector3:
	var c: Array = GameData.get_record(poi_id).get("position_m", [0, 0, 0])
	return Vector3(float(c[0]), float(c[1]), float(c[2]))


## Every cue the set's beds, spots, emitters and flush name resolves; every stem is in the manifest.
func _check_sets(music_id: String, ambience_id: String, where: String) -> void:
	_check_music(music_id, where)
	_check_ambience(ambience_id, where)


func _check_music(music_id: String, where: String) -> void:
	var m := GameData.get_record(music_id)
	assert_eq(str(m.get("type", "")), "music_set", "%s: %s is a music set" % [where, music_id])
	for stem: String in (m.get("stems", {}) as Dictionary):
		var path := str(m.stems[stem])
		assert_false(AudioMath.manifest_entry(path).is_empty(), "%s: %s's %s is built (%s)" % [where, music_id, stem, path])
	for key: String in ["combat_intro", "intro"]:
		if str(m.get(key, "")) != "":
			assert_false(Audio.resolve(str(m[key])).is_empty(), "%s: %s's %s resolves" % [where, music_id, key])


func _check_ambience(ambience_id: String, where: String) -> void:
	var a := GameData.get_record(ambience_id)
	assert_eq(str(a.get("type", "")), "ambience_set", "%s: %s is an ambience set" % [where, ambience_id])
	var cues: Array = []
	for list_key: String in ["beds", "spots", "emitters"]:
		for item: Dictionary in a.get(list_key, []):
			cues.append(str(item.cue))
	if typeof(a.get("reactions")) == TYPE_DICTIONARY and str(a.reactions.get("flush_cue", "")) != "":
		cues.append(str(a.reactions.flush_cue))
	for cue_id: String in cues:
		assert_eq(str(Audio.resolve(cue_id).get("id", "")), cue_id, "%s: %s resolves (%s)" % [where, cue_id, ambience_id])


# --------------------------------------------------------------------------- regions and places

func test_every_region_place_voice_and_cue_resolves_within_the_budget() -> void:
	_world()
	assert_false(Audio.is_silent_level(WORLD), "the world is no longer silent")
	var idx := WorldIndex.for_level(WORLD)
	for region: String in REGION_POINTS:
		var at := Vector3(REGION_POINTS[region].x, 0.0, REGION_POINTS[region].y)
		assert_eq(idx.region_at(at), region, "the point lies in %s" % region)
		var rec := Audio.region_at(at)
		assert_true((rec.get("regions", []) as Array).has(region), "%s wins its region's record (%s)" % [region, rec.get("id")])
		_check_sets(str(rec.get("music", "")), str(rec.get("ambience", "")), region)
	for poi: String in PLACES:
		var rec := Audio.region_at(_poi_pos(poi))
		assert_true((rec.get("pois", []) as Array).has(poi), "%s wins its place's record (%s)" % [poi, rec.get("id")])
		assert_eq(int(rec.get("priority", 0)), 10, "%s: a place outranks its region" % poi)
		assert_eq(str(rec.get("music", "")), str(PLACES[poi][0]), "%s keeps its region's set" % poi)
		assert_eq(str(rec.get("ambience", "")), str(PLACES[poi][1]), "%s has its place's ambience" % poi)
		_check_sets(str(rec.get("music", "")), str(rec.get("ambience", "")), poi)
	for poi: String in ["poi.brannock", "poi.hollowmere", "poi.skarn"]:
		var rec := Audio.region_at(_poi_pos(poi))
		assert_eq(float(((rec.get("layers", {}) as Dictionary).get("explore", {}) as Dictionary).get("melody", 0.0)), -6.0,
			"%s plays its region's melody 6 dB down" % poi)
		var rests: Array = (rec.get("melody", {}) as Dictionary).get("rest_loops", [])
		assert_eq(rests.map(func(v: Variant) -> int: return int(v)), [2, 4], "%s rests longer" % poi)
	var moot := Audio.region_at(_poi_pos("poi.the_moot"))
	assert_true(float(moot.layers.explore.melody) <= -80.0, "the Moot plays the drone alone")
	for boss: String in ["battle.iron_regiment", "enemy.troll_matriarch", "enemy.harrok"]:
		var rec := Audio.boss_region(boss)
		assert_false(rec.is_empty(), "%s has its boss set" % boss)
		var m := GameData.get_record(str(rec.get("music", "")))
		assert_false(str(m.get("intro", "")).is_empty(), "%s's set enters after its intro" % boss)
		assert_false((m.get("phase_layers", {}) as Dictionary).is_empty(), "%s's set has its phase layer" % boss)
		_check_music(str(rec.music), boss)
	# the budget (plan §4.5): the world adds at most 5.5 MB and registers at most 170 s of samples
	var files: Dictionary = AudioMath.manifest().get("files", {})
	var world_bytes := 0.0
	var world_files := 0
	for path: String in files:
		var e: Dictionary = files[path]
		if str(e.get("scope", "m6")) == "world":
			world_bytes += _imported_bytes(e)
			world_files += 1
	assert_true(world_files >= 150, "the world's files are in the manifest (%d)" % world_files)
	assert_true(world_bytes <= WORLD_BUDGET_BYTES, "the world adds %.3f MB of audio (cap 5.5 MB)" % (world_bytes / 1048576.0))
	var seconds := 0.0
	for path in Audio.sample_paths_for(WORLD):
		seconds += float(AudioMath.manifest_entry(path).get("seconds", 0.0))
	assert_true(seconds <= WORLD_REGISTERED_CAP_S, "the world registers %.1f s of samples (cap 170 s)" % seconds)
	for bank: String in WORLD_BANKS:
		assert_true(GameData.has_record(bank), "%s is shipped" % bank)
	await _check_voices_and_cues()


func test_region_and_place_changes_cross_fade_and_a_town_greets_a_big_giant() -> void:
	_world()
	var p := spawn_player(MARCH)
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == 4:
			p.set_profile(rec)
	Audio.advance_for_tests(0.75, 0.25)
	assert_eq(str(Audio.current_region().get("id", "")), "audio_region.world_crownmarch", "the Crownmarch's region")
	assert_eq(Audio.music.set_id(), "music.crownmarch", "the Crownmarch's set")
	assert_eq(Audio.ambience.set_id, "ambience.crownmarch", "and its ambience")
	assert_eq(Audio.ambience.bed_cues(), PackedStringArray(["amb.bed_farmland"]), "the farmland bed")
	var march: MusicDirector.Deck = Audio.music.deck
	var rests_before := Audio.music.scheduler.rest_loops
	# into Brannock: the same set, the town's melody rules and layers; the beds cross-fade
	Audio.clear_log()
	p.global_position = BRANNOCK
	Audio.advance_for_tests(0.75, 0.25)
	assert_eq(str(Audio.current_region().get("id", "")), "audio_region.world_brannock", "Brannock's place")
	assert_true(Audio.music.deck == march and Audio.music.pending.is_empty(), "the Crownmarch's set plays on")
	assert_eq(Audio.music.scheduler.rest_loops, Vector2i(2, 4), "with the town's longer rests (%s before)" % rests_before)
	var town_layers: Dictionary = (Audio.current_region().get("layers", {}) as Dictionary).get("explore", {})
	assert_eq(float(town_layers.get("melody", 0.0)), -6.0, "the town's melody 6 dB down")
	if march.melody_choice != "":
		assert_eq(Audio.music._target_db(march, march.melody_choice), -6.0, "the melody heard 6 dB down")
	var beds := Audio.ambience.beds.map(func(b: Dictionary) -> String: return "%s>%.0f" % [b.cue, b.target])
	assert_true(beds.has("amb.bed_town>1") and not beds.has("amb.bed_farmland>1"), "the town's bed replaces the farmland's: %s" % [beds])
	for b: Dictionary in Audio.ambience.beds:
		if str(b.cue) == "amb.bed_town":
			assert_true(float(b.gain) > 0.0 and float(b.gain) < 1.0, "fading in over the beds' 3 s (%.2f)" % float(b.gain))
	var gasps := Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.cue) == "sfx.voice.crowd.gasp")
	var bells := Audio.cue_log().filter(func(e: Dictionary) -> bool: return str(e.cue) == "sfx.world.town_bell")
	assert_eq(gasps.size(), 1, "a stage-4 giant entering Brannock: the crowd gasps once")
	assert_eq(bells.size(), 1, "and the town bell rings once")
	if bells.size() == 1:
		assert_true(Vector2((bells[0].pos as Vector3).x - BRANNOCK.x, (bells[0].pos as Vector3).z - BRANNOCK.z).length() < 1.0,
			"the bell rings in the town")
	# out and back in: once a visit
	p.global_position = MARCH
	Audio.advance_for_tests(0.75, 0.25)
	Audio.clear_log()
	p.global_position = BRANNOCK
	Audio.advance_for_tests(0.75, 0.25)
	assert_eq(Audio.logged_cues().count("sfx.world.town_bell"), 0, "once a visit")
	# on into the Greywood: its set at the next bar, cross-faded over two bars in the shared frame
	p.global_position = GREYWOOD
	Audio.advance_for_tests(0.5, 0.25)   # the zone changes (15 m in), the set waits for the next bar
	var to_bar := AudioMath.seconds_to_boundary(Audio.music.deck_position(march), march.bar_s, march.loop_s)
	if to_bar > 0.15:
		Audio.advance_for_tests(to_bar - 0.1, 0.25)
	var changed := -1.0
	for i in 12:
		Audio.advance_for_tests(0.025, 0.025)
		if Audio.music.deck != null and Audio.music.deck.set_id == "music.greywood":
			changed = Audio.clock_s
			break
	assert_true(changed > 0.0, "the Greywood's set comes in (%s)" % Audio.music.set_id())
	var grey: MusicDirector.Deck = Audio.music.deck
	if grey == null or grey.set_id != "music.greywood":
		return
	assert_true(Audio.music.old_decks.has(march), "the Crownmarch's set fades out under it")
	var into_bar := fposmod(Audio.music.deck_position(grey), grey.bar_s)
	assert_near(minf(into_bar, grey.bar_s - into_bar), 0.0, 0.06, "at a bar line")
	assert_near(Audio.music.deck_position(grey), Audio.music.deck_position(march), 0.06,
		"where the Crownmarch's set is (the zone frame)")
	Audio.advance_for_tests(grey.bar_s, grey.bar_s / 2.0)
	assert_true(grey.master > 0.3 and grey.master < 0.7, "halfway in after one bar (%.2f)" % grey.master)
	Audio.advance_for_tests(grey.bar_s + 0.5, (grey.bar_s + 0.5) / 2.0)
	assert_near(grey.master, 1.0, 1e-6, "fully in after two bars")
	assert_false(Audio.music.old_decks.has(march), "the Crownmarch's set is gone")
	assert_eq(Audio.ambience.set_id, "ambience.greywood", "the Greywood's ambience")


# --------------------------------------------------------------------------- voices and cues


## Every planned voice of §4.1's M7-M9 rows and every cue of their events resolves to itself; a run
## of those events through the router plays with nothing missing.
func _check_voices_and_cues() -> void:
	for voice: String in VOICES:
		for call: String in VOICES[voice]:
			var id := "sfx.voice.%s.%s" % [voice, call]
			var cue := Audio.resolve(id)
			assert_eq(str(cue.get("id", "")), id, "%s resolves to itself" % id)
	for call: String in ["alert", "bellow", "far"]:
		assert_true(WORLD_BANKS.has(str(Audio.resolve("sfx.voice.giant." + call).get("bank", ""))),
			"the rival giants' %s is the world's" % call)
	assert_false(WORLD_BANKS.has(str(Audio.resolve("sfx.voice.giant.roar").get("bank", ""))), "the player's roar stays P21's")
	# records not in the mix yet find their voices (P29-P34 add the records)
	for pair: Array in [["enemy.troll", "troll"], ["enemy.dire_wolf", "dire_wolf"], ["enemy.troll_matriarch", "matriarch"],
			["enemy.harrok", "giant"], ["enemy.cavalry", "horse"], ["enemy.rival_giant", "giant"], ["enemy.siege_crew", "human"]]:
		assert_eq(Audio.router.voice_of(str(pair[0])), str(pair[1]), "%s speaks as %s" % pair)
	TestFixtures.record_override("enemy.test_rider", {"type": "enemy", "archetype": "cavalry"})
	TestFixtures.record_override("enemy.test_brute", {"type": "enemy", "archetype": "troll"})
	TestFixtures.record_override("enemy.test_rival", {"type": "enemy", "archetype": "rival_giant"})
	assert_eq(Audio.router.voice_of("enemy.test_rider"), "horse", "a cavalry archetype neighs")
	assert_eq(Audio.router.voice_of("enemy.test_brute"), "troll", "a troll archetype grunts")
	assert_eq(Audio.router.voice_of("enemy.test_rival"), "giant", "a rival giant speaks as a giant")
	assert_eq(CueRouter.voice_call("giant", "roar", false), "bellow", "and bellows where the player roars")
	assert_eq(CueRouter.voice_call("giant", "roar", true), "roar", "the player roars")
	for id: String in ["enemy.test_rider", "enemy.test_brute"]:
		assert_eq(Audio.router.step_class_of(id), "hoof" if id.ends_with("rider") else "heavy", "%s's footfall class" % id)
	var cues: Array = ["sfx.ui.travel", "sfx.gate.water", "sfx.gate.stone", "sfx.gate.timber", "sfx.trample",
		"sfx.world.splash.small", "sfx.world.splash.large", "sfx.formation.brace", "sfx.formation.horn_broken",
		"sfx.formation.banner_fall", "sfx.voice.crowd.flee", "sfx.voice.crowd.abandon", "sfx.voice.crowd.gasp",
		"sfx.world.town_bell", "sfx.world.horn_alarm", "sfx.siege.ballista.fire", "sfx.siege.catapult.fire",
		"sfx.cavalry.charge", "sfx.status.burning", "sfx.troll.regrow", "sfx.threat.windup.wall", "sfx.threat.incoming",
		"sfx.world.interact.exit", "sfx.world.interact.inscription", "amb.march_loop",
		"mus.stinger.discovery", "mus.stinger.world_reveal", "mus.stinger.yield", "mus.stinger.ancestry",
		"mus.stinger.crowned", "mus.stinger.rout", "mus.stinger.boss_regiment", "mus.stinger.boss_matriarch",
		"mus.stinger.boss_harrok", "sfx.ui.equip.axe", "sfx.ui.equip.fists"]
	for region: String in ["crownmarch", "greywood", "drowned_steps", "aldmere", "stonehold"]:
		cues.append("mus.stinger.combat_" + region)
	for stage in [4, 5, 6]:
		for surface: String in ["soft", "hard", "wet", "wade", "soft.cruise", "hard.cruise"]:
			cues.append("sfx.step.giant_s%d.%s" % [stage, surface])
	cues.append_array(["sfx.step.giant_s3.wade", "sfx.step.heavy.wade", "sfx.step.heavy.wet", "sfx.step.hoof.soft",
		"sfx.step.hoof.hard", "sfx.step.hoof.wet", "sfx.step.paw.wet"])
	for visual: String in ["ballista_bolt", "catapult_stone", "rune_lance", "storm_bolt", "engine"]:
		cues.append_array(["sfx.projectile.%s.launch" % visual, "sfx.impact.%s" % visual])
	for family: String in ["axe", "fists"]:
		cues.append_array(["sfx.swing.%s.light" % family, "sfx.swing.%s.heavy" % family])
	for ability: String in ["titan_stomp", "earthquake", "crag_hurl"]:
		cues.append_array(["sfx.ability.%s.cast" % ability, "sfx.ability.%s.impact" % ability])
	cues.append_array(["sfx.ability.formation_sweep.sweep", "sfx.ability.titan_roar.roar", "sfx.ability.rampart_grip.cast",
		"sfx.ability.shoulder_charge.cast", "sfx.ability.cleave_of_ages.sweep", "sfx.ability.bulwark.on",
		"sfx.status.bulwark.off", "sfx.ability.stonewall_stance.on", "sfx.ability.bedrock_ward.on",
		"sfx.status.bedrock_ward.off", "sfx.ability.rune_lance.cast", "sfx.ability.primal_regrowth.on",
		"sfx.ability.storm_call.impact", "sfx.ability.thunderhead.impact", "sfx.ability.wild_surge.on"])
	for cue_id: String in cues:
		var cue := Audio.resolve(cue_id)
		assert_eq(str(cue.get("id", "")), cue_id, "%s resolves to itself" % cue_id)
	# the M7-M9 rows' requests through the router (no giant: they sound where they happen, or as 2D):
	# nothing missing, nothing from a family default
	Audio.clear_log()
	Audio.missing.clear()
	# a world event's record names its centre `centre_m` (the world_event schema): the horn sounds there
	var raid_centre := Vector3(30, 2, -40)
	TestFixtures.record_override("event.test_raid", {"type": "world_event", "level": WORLD,
		"centre_m": [raid_centre.x, raid_centre.y, raid_centre.z]})
	Audio.router.call("_on_travel_requested", WORLD, "world.cp.millford", "fast_travel")   # (GameSession travels on the event)
	Events.formation_changed.emit(Sim.tick, "test.formation", "braced")
	Events.formation_changed.emit(Sim.tick, "test.formation", "routed")
	Events.siege_engine_fired.emit(Sim.tick, "test.catapult_1", "ability.test", "")
	Events.siege_engine_crewed.emit(Sim.tick, "test.catapult_1", false)
	Events.world_event_started.emit(Sim.tick, "event.test_raid")
	Events.size_gate_blocked.emit(Sim.tick, "world.gate.unknown", 4, "")
	Events.trampled.emit(Sim.tick, "world.prop.unknown", "")
	Events.ancestry_chosen.emit(Sim.tick, "ancestry.test")
	await step_ticks(2)
	var logged := Audio.logged_cues()
	for want: String in ["sfx.ui.travel", "sfx.formation.brace", "sfx.voice.crowd.flee", "sfx.siege.catapult.fire",
			"sfx.voice.crowd.abandon", "sfx.world.horn_alarm", "sfx.gate.stone", "sfx.trample"]:
		assert_true(logged.has(want), "%s plays (%s)" % [want, logged])
	for e: Dictionary in Audio.cue_log():
		if str(e.cue) == "sfx.world.horn_alarm":
			assert_true((e.pos as Vector3).distance_to(raid_centre) < 0.01, "the alarm horn at the event's centre (%s)" % e.pos)
	assert_true(Audio.music.stinger_playing(), "the stingers play (%s)" % [Audio.music.stingers])
	assert_true(Audio.missing.is_empty(), "nothing missing (%s)" % [Audio.missing])


## The imported size of a manifest entry (plan §4.5; test_audio_assets' arithmetic): a WAV by the
## QOA formula plus 370 bytes, an Ogg x 1.11.
static func _imported_bytes(e: Dictionary) -> float:
	if str(e.kind) == "sfx":
		var frames := int(e.frames)
		return float(int(e.channels) * (8 + 24 * ceili(frames / 5120.0) + 8 * ceili(frames / 20.0)) + 370)
	return float(e.size) * 1.11
