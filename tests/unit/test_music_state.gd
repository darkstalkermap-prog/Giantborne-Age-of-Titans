extends TestSuite
## P19 (plan M6-M9 decision 5, decision 6, §4.3): the music director's state rules without
## playing anything - the intensity state machine with its hold times (hysteresis), the threat
## weighting of a polled sequence, which actors always count, and the layer volume each stem gets
## for an intensity, a melody choice, a boss phase and the silence window.

const ZONE_SET := {"id": "music.test_zone", "type": "music_set", "bpm": 96, "beats_per_bar": 4, "bars": 12,
	"frame": "zone_96",
	"stems": {"drone": "res://a.ogg", "melody_a": "res://b.ogg", "melody_b": "res://c.ogg", "pulse": "res://d.ogg",
		"drums": "res://e.ogg", "brass": "res://f.ogg"},
	"layers": {"explore": {"drone": 0, "melody": -2}, "danger": {"drone": 0, "melody": -9, "pulse": -3},
		"combat": {"drone": -4, "melody": -10, "pulse": -5, "drums": 0, "brass": -2}},
	"melody": {"variants": ["melody_a", "melody_b"], "segment_bars": 4, "play_loops": [1, 2], "rest_loops": [1, 3],
		"max_repeat": 2, "min_phrase_gap_s": 60}}
const BOSS_SET := {"id": "music.test_boss", "type": "music_set", "bpm": 104, "beats_per_bar": 4, "bars": 8,
	"frame": "boss_104", "stems": {"drums": "res://a.ogg", "theme": "res://b.ogg", "frenzy": "res://c.ogg"},
	"layers": {"combat": {"drums": 0, "theme": -2}}, "phase_layers": {"2": {"frenzy": 0}}}


class FakeActor:
	extends Node3D
	var record: Dictionary = {}
	var formation_id := ""


func _cfg() -> Dictionary:
	return GameData.get_record("audio_mix.default").intensity


func test_intensity_rises_at_once_and_falls_after_its_hold() -> void:
	var cfg := _cfg()
	assert_eq(MusicDirector.next_intensity("explore", "combat", 0.0, 0.0, cfg), "combat", "rises at once")
	assert_eq(MusicDirector.next_intensity("explore", "danger", 0.0, 0.0, cfg), "danger", "to danger too")
	assert_eq(MusicDirector.next_intensity("combat", "explore", 10.0, 15.9, cfg), "combat", "combat holds 6 s")
	assert_eq(MusicDirector.next_intensity("combat", "explore", 10.0, 16.0, cfg), "explore", "then falls to the target")
	assert_eq(MusicDirector.next_intensity("combat", "danger", 10.0, 16.0, cfg), "danger", "or to danger")
	assert_eq(MusicDirector.next_intensity("danger", "explore", 10.0, 17.9, cfg), "danger", "danger holds 8 s")
	assert_eq(MusicDirector.next_intensity("danger", "explore", 10.0, 18.0, cfg), "explore", "then explore")


## Polls every 0.25 s: the target for each poll comes from `targets` (a function of the time).
func _simulate(targets: Callable, seconds: float) -> Array:
	var cfg := _cfg()
	var intensity := "explore"
	var last_high := 0.0
	var out: Array = []
	var t := 0.0
	while t <= seconds + 1e-9:
		var target: String = targets.call(t)
		intensity = MusicDirector.next_intensity(intensity, target, last_high, t, cfg)
		if AudioMath.intensity_rank(target) >= AudioMath.intensity_rank(intensity):
			last_high = t
		out.append([t, intensity])
		t += 0.25
	return out


func _at(timeline: Array, t: float) -> String:
	for row: Array in timeline:
		if absf(float(row[0]) - t) < 1e-6:
			return str(row[1])
	return "?"


func _short_fight(t: float) -> String:
	return "combat" if t < 2.0 else "explore"


func _flicker(t: float) -> String:
	return "explore" if fmod(t, 4.0) < 1.0 else "combat"


func _ladder(t: float) -> String:
	if t < 1.0:
		return "combat"
	return "danger" if t < 12.0 else "explore"


func test_a_short_fight_holds_combat_then_returns_to_explore() -> void:
	var timeline := _simulate(_short_fight, 20.0)
	assert_eq(_at(timeline, 1.0), "combat", "in the fight")
	assert_eq(_at(timeline, 7.5), "combat", "held 6 s after the last combat poll (1.75 s)")
	assert_eq(_at(timeline, 8.0), "explore", "then explore")


func test_a_flicker_does_not_drop_combat() -> void:
	var timeline := _simulate(_flicker, 20.0)
	for row: Array in timeline:
		if float(row[0]) >= 1.0:
			assert_eq(str(row[1]), "combat", "brief lulls stay in combat (t %.2f)" % row[0])


func test_danger_ladder_down_from_combat() -> void:
	var timeline := _simulate(_ladder, 30.0)
	assert_eq(_at(timeline, 6.5), "combat", "combat held")
	assert_eq(_at(timeline, 7.0), "danger", "then danger while it lasts")
	assert_eq(_at(timeline, 19.5), "danger", "danger held 8 s after its last poll (11.75 s)")
	assert_eq(_at(timeline, 20.0), "explore", "then explore")


func test_threat_weighting_over_a_polled_sequence() -> void:
	var cfg := _cfg()
	var giant := 18.9
	var fleeing: Array = []
	for i in 10:
		fleeing.append({"distance": 6.0 + i, "height": 1.8, "special": false, "aware": true, "engaged": true,
			"fleeing": true, "hostile": true})
	var snap := {"threats": fleeing, "player_height": giant, "scale": AudioMath.distance_scale(giant)}
	var timeline := _simulate(func(_t: float) -> String: return AudioMath.intensity_target(snap, cfg), 10.0)
	for row: Array in timeline:
		assert_eq(str(row[1]), "explore", "a stage-6 giant among ten fleeing soldiers stays in explore")


func test_special_actors_always_count() -> void:
	var a := FakeActor.new()
	assert_false(MusicDirector.is_special(a), "a plain enemy")
	a.record = {"archetype": "rival_giant"}
	assert_true(MusicDirector.is_special(a), "a rival giant")
	a.record = {"archetype": "boss"}
	assert_true(MusicDirector.is_special(a), "a boss")
	a.record = {}
	a.formation_id = "aldmere_patrol.pikes"
	assert_true(MusicDirector.is_special(a), "a formation member")
	a.formation_id = ""
	a.add_to_group("bosses")
	assert_true(MusicDirector.is_special(a), "a node of group bosses")
	a.free()


func _deck(rec: Dictionary, boss := false) -> MusicDirector.Deck:
	var d := MusicDirector.Deck.new()
	d.set_id = str(rec.id)
	d.rec = rec
	d.boss = boss
	return d


func test_layer_volumes_follow_intensity_and_the_melody_choice() -> void:
	var m := MusicDirector.new()
	var d := _deck(ZONE_SET)
	d.melody_choice = "melody_b"
	m.intensity = "explore"
	assert_eq(m._target_db(d, "drone"), 0.0, "explore: drone 0 dB")
	assert_eq(m._target_db(d, "melody_b"), -2.0, "the chosen variant at the melody's -2 dB")
	assert_eq(m._target_db(d, "melody_a"), MusicDirector.SILENT_DB, "the other variants are silent")
	assert_eq(m._target_db(d, "pulse"), MusicDirector.SILENT_DB, "a stem missing from the layer is silent")
	m.intensity = "danger"
	assert_eq(m._target_db(d, "pulse"), -3.0, "danger adds the pulse")
	assert_eq(m._target_db(d, "melody_b"), -9.0, "and lowers the melody")
	m.intensity = "combat"
	assert_eq(m._target_db(d, "drums"), 0.0, "combat adds the drums")
	assert_eq(m._target_db(d, "melody_b"), -10.0, "the region's melody stays in combat at -10 dB")
	d.melody_choice = ""
	assert_eq(m._target_db(d, "melody_b"), MusicDirector.SILENT_DB, "a rested segment silences every variant")
	m.scheduler.silent = true
	m.intensity = "explore"
	assert_eq(m._target_db(d, "drone"), MusicDirector.SILENT_DB, "the silence window fades everything")
	m.free()


func test_boss_sets_play_their_combat_layer_and_add_phase_layers() -> void:
	var m := MusicDirector.new()
	var d := _deck(BOSS_SET, true)
	m.intensity = "explore"
	assert_eq(m._target_db(d, "drums"), 0.0, "a boss set plays its combat layer")
	assert_eq(m._target_db(d, "frenzy"), MusicDirector.SILENT_DB, "phase 1: no frenzy")
	m.boss_phase = 2
	assert_eq(m._target_db(d, "frenzy"), 0.0, "phase 2 adds its layer")
	m.free()


func test_states_and_inputs_without_a_deck() -> void:
	var m := MusicDirector.new()
	assert_eq(m.state_name(), "silent", "the director starts silent")
	assert_eq(m.set_id(), "", "no set")
	assert_eq(MusicDirector.STATE_NAMES, ["silent", "context", "zone", "boss"], "the four states of §4.3")
	m.free()
