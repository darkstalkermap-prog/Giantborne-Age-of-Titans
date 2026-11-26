extends TestSuite
## The milestone C gate (docs/systems/Cgate.md): progression holes in Last Hearth's development, pure - the shipped
## records on plain flag dictionaries.

const LH := "settlement.last_hearth"


func _ctx(flags := {}) -> Dictionary:
	var c := QuestConditions.empty_context()
	c.flags = flags
	c.stage = 6
	return c


func _raid() -> WorldEvent:
	return WorldEvent.make(GameData.get_record("event.hearth_raid"))


func _start_ctx(flags: Dictionary) -> Dictionary:
	var f := {"settlement.last_hearth.tier_1": true}
	f.merge(flags, true)
	return {"stage": 6, "flags": f, "now_s": 100000.0, "centre_ready": true, "distance_m": 100.0}


## G1: three raids lost (or given up) must not close the beacon for good - the raid comes again until it is beaten
## back once; after that it keeps its three runs.
func test_the_raid_comes_again_until_it_is_beaten_back() -> void:
	var e := _raid()
	var lost := {"event.hearth_raid.runs": 3, "event.hearth_raid.done": true, "event.hearth_raid.outcome": "fell",
		"event.hearth_raid.last_end_s": 1000.0, "world.last_hearth.raid_fell": true}
	assert_eq(e.can_start_with(_start_ctx(lost)), "", "three raids lost: it may still come")
	var many := lost.duplicate()
	many["event.hearth_raid.runs"] = 9
	assert_eq(e.can_start_with(_start_ctx(many)), "", "nine lost or given up: still")
	var won := {"event.hearth_raid.runs": 3, "event.hearth_raid.done": true, "event.hearth_raid.outcome": "defended",
		"event.hearth_raid.last_end_s": 1000.0, "world.last_hearth.raid_defended": true}
	assert_eq(e.can_start_with(_start_ctx(won)), "conditions", "beaten back once and three runs: no more raids")
	won["event.hearth_raid.runs"] = 2
	assert_eq(e.can_start_with(_start_ctx(won)), "", "beaten back once in two runs: a third may come")


## G1: the beacon's deed is the raid beaten back once - a later raid lost does not take it away again.
func test_a_later_raid_lost_does_not_undo_the_beacons_deed() -> void:
	var rec := SettlementRules.record(LH)
	var st := SettlementRules.blank()
	var flags := {"event.hearth_raid.done": true, "event.hearth_raid.outcome": "fell", "world.last_hearth.raid_defended": true,
		"world.last_hearth.raid_fell": true}
	var s := SettlementRules.project_status(rec, "beacon", st, _ctx(flags))
	var deed_met := false
	for n: Dictionary in s.get("needs", []):
		if str(n.get("kind", "")) == "deed" and str(n.get("text", "")).contains("raid"):
			deed_met = bool(n.get("met", false))
	assert_true(deed_met, "defended once, then a raid that fell: the deed still met")
