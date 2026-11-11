extends IntegrationSuite
## M8 gate (F36): a boss or a big brute standing in its strike reach while something hides the giant
## from its eye - a 1 m world-layer trunk between its eye and the giant's anchor, as the scenery trunks
## of the Troll Den - and being hit every 1.5 s (each blow keeps its memory fresh) no longer freezes:
## it walks round the trunk until it sees the giant, then strikes (EnemyBrain._regain_sight). Before the
## fix the Troll Matriarch, Harrok, a rival giant, the Ogre King (the sequence approach), a troll and an
## ogre (the melee approach) all stood still for the whole run without one attack. The control without
## a trunk is the review's: she strikes as before (the M8 gate change only acts while the sight line is
## blocked; the 30 seeded boss runs of tests/gate/test_bosses_seeded.gd never meet that case).

const RUN_S := 12.0
const BLOW_EVERY_TICKS := 90
## [label, enemy record, the giant's stage, distance from the giant's capsule as a share of the
## record's ai.attack_range_m]
const CASES := [["the Troll Matriarch", "enemy.troll_matriarch", 4], ["Harrok", "enemy.harrok", 6],
	["a rival giant", "enemy.rival_giant", 5], ["the Ogre King", "enemy.ogre_king", 3], ["a troll", "enemy.troll", 4],
	["an ogre", "enemy.ogre", 3]]

var _attacks := 0
var _watch := ""


func before_each() -> void:
	await super()
	WorldState.clear()
	_attacks = 0
	Events.ability_started.connect(_on_ability)


func after_each() -> void:
	if Events.ability_started.is_connected(_on_ability):
		Events.ability_started.disconnect(_on_ability)
	await super()


func _on_ability(_t: int, actor_id: String, _action: String, _inst: int) -> void:
	if actor_id == _watch:
		_attacks += 1


static func _profile(stage: int) -> Dictionary:
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		if int(rec.get("stage", 0)) == stage:
			return rec
	return {}


## The giant at `stage` (taking no damage) and the enemy `record_id` in its reach, 0.8 of its attack
## range from the giant's capsule; with `trunk`, a 1 m trunk in the gap between them, tall enough to
## cut the line from the enemy's eye to the giant's anchor. Then RUN_S of the giant's blows every
## 1.5 s: {"attacks", "hidden_still_s" (seconds in APPROACH with no goal while hidden), "moved",
## "seen_share"}.
func _run(record_id: String, stage: int, trunk: bool) -> Dictionary:
	var p := spawn_player(Vector3(0, 0.05, 0), 0.0)
	p.set_profile(_profile(stage))
	p.entity.apply_status("status.debug_invulnerable", NAN, -1.0, "test")
	await step_ticks(3)
	var rec := GameData.get_record(record_id)
	var e := (load(str(rec.scene)) as PackedScene).instantiate() as EnemyActor
	_watch = "test.%s" % record_id.get_slice(".", 1)
	e.set("entity_id", _watch)
	var giant_r := float(p.profile.get("capsule_radius_m", 1.0))
	var d := giant_r + float((rec.get("ai", {}) as Dictionary).get("attack_range_m", 2.0)) * 0.8
	e.position = Vector3(0, 0.05, -d)
	world.add_child(e)
	var body: StaticBody3D = null
	if trunk:
		var tall := maxf(float(rec.height_m), p.entity.anchor_position().y) + 3.0
		var mid := giant_r + (d - giant_r - float(rec.get("capsule_radius_m", 1.0))) * 0.5
		body = StaticBody3D.new()
		body.collision_layer = HitQueryAdapter.LAYER_WORLD
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 0.5
		cyl.height = tall
		shape.shape = cyl
		body.add_child(shape)
		body.position = Vector3(0.0, tall * 0.5, -mid)
		world.add_child(body)
	await step_ticks(3)
	_attacks = 0
	var start := Sim.tick
	var start_pos := e.global_position
	var still := 0
	var seen := 0
	while Sim.tick - start < int(RUN_S * 60.0):
		if (Sim.tick - start) % BLOW_EVERY_TICKS == 0:
			var h := HitEvent.new()
			h.tick = Sim.tick
			h.instance_id = Sim.new_instance_id()
			h.attacker_id = p.entity.entity_id
			h.target_id = _watch
			h.power = 10.0
			h.attacker_stat = 10.0
			h.damage_split = {"physical": 1.0}
			h.tags = PackedStringArray(["Melee"])
			h.attacker_position = p.global_position
			Sim.queue_hit(h)
		await step_ticks(1)
		var b := e.brain
		if bool(b.perception.get("visible", false)):
			seen += 1
		elif b.state == EnemyBrain.AIState.APPROACH and b.move_target == Vector3.INF:
			still += 1
	var out := {"attacks": _attacks, "hidden_still_s": still / 60.0, "moved": e.global_position.distance_to(start_pos),
		"seen_share": seen / (RUN_S * 60.0)}
	e.queue_free()
	p.queue_free()
	if body != null:
		body.queue_free()
	await step_ticks(2)
	return out


func test_a_trunk_between_no_longer_freezes_them() -> void:
	for c: Array in CASES:
		var r := await _run(str(c[1]), int(c[2]), true)
		print("    %s behind a trunk (stage %d): %s" % [c[0], c[2], r])
		assert_true(int(r.attacks) >= 3, "%s, a trunk between, hit every 1.5 s: strikes back (%d attacks in %.0f s)" % [
			c[0], r.attacks, RUN_S])
		assert_true(float(r.hidden_still_s) < 1.0, "%s: never stands still while hidden (%.2f s)" % [c[0], r.hidden_still_s])
		assert_true(float(r.moved) > 0.5, "%s: it walked round the trunk (%.2f m)" % [c[0], r.moved])
		assert_true(float(r.seen_share) > 0.5, "%s: and saw the giant again (%.2f of the run)" % [c[0], r.seen_share])


func test_the_control_without_a_trunk() -> void:
	var r := await _run("enemy.troll_matriarch", 4, false)
	print("    the Troll Matriarch, no trunk: %s" % [r])
	assert_true(int(r.attacks) >= 3, "with a clear sight line she strikes back (%d attacks)" % r.attacks)
	assert_true(float(r.seen_share) > 0.95, "she sees the giant throughout (%.2f)" % r.seen_share)
