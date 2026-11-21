extends "res://tests/gate/test_bosses_seeded.gd"
## P64c (the M13 gate review): the seeded boss runs with the people and the giants drawn (PersonRig.enable_for_tests,
## SkinnedRig.enable_for_tests: the skinned bodies, the creatures' slots, the crowd) and without, compared by a hash of
## every gameplay event - hit_resolved, ability_started, telegraph_started, entity_died, boss_phase_changed,
## staggered - with their ticks counted from the run's start: the presentation never changes the fight. Each boss
## runs SEEDS_TWIN (two seeds of test_bosses_seeded's ten) once without and once with the people. Gate tier, about
## 3 minutes.

const SEEDS_TWIN := [3, 4]

var _trace := PackedStringArray()
var _t0 := -1


func _seeds() -> Array:
	return SEEDS_TWIN


func before_each() -> void:
	await super()
	_trace.clear()
	for pair: Array in _signals():
		(pair[0] as Signal).connect(pair[1])


func after_each() -> void:
	for pair: Array in _signals():
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])
	SkinnedRig.reset_for_tests()
	PersonRig.reset_for_tests()
	await super()


func _signals() -> Array:
	return [[Events.hit_resolved, _t_hit], [Events.ability_started, _t_ab], [Events.telegraph_started, _t_tel],
		[Events.entity_died, _t_died], [Events.boss_phase_changed, _t_phase], [Events.staggered, _t_stag]]


## Ticks from the run's first blow (the level's load before it waits on frames, not ticks).
func _rel(tick: int) -> int:
	return tick - _t0


## The level, then the tick brought to a multiple of ALIGN_TICKS: the brains think on the tick's phase (their
## perception and decision rates), and the two runs share one process, so each starts its fight on the same phase.
const ALIGN_TICKS := 120


func _level(path: String, stage: int) -> Node3D:
	var level: Node3D = await super(path, stage)
	await step_ticks(posmod(-Sim.tick, ALIGN_TICKS))
	# (a troll's regeneration counts its seconds from its spawn: from here in both runs)
	for e: Node in get_tree().get_nodes_in_group("enemies"):
		if "_p34_regen_next" in e:
			e.set("_p34_regen_next", Sim.tick)
	return level


func _blow(target: EnemyActor, amount: float) -> void:
	if _t0 < 0:
		_t0 = Sim.tick
	super(target, amount)


func _keep() -> bool:
	return _t0 >= 0


func _t_hit(tick: int, r: HitResult) -> void:
	if not _keep():
		return
	_trace.append("hit %d %s>%s %s o%d h%d p%.3f s%.3f k%s a%.2f" % [_rel(tick), r.event.attacker_id, r.event.target_id,
		r.event.action_id, r.outcome, r.health_damage, r.poise_damage, r.stagger_s, r.killed, r.defender_health_after])


func _t_ab(tick: int, actor_id: String, action_id: String, _iid: int) -> void:
	if not _keep():
		return
	_trace.append("ab %d %s %s" % [_rel(tick), actor_id, action_id])


func _t_tel(tick: int, actor_id: String, action_id: String, target_id: String, _shape: String, origin: Vector3,
		yaw: float, _r: float, _l: float, _d: float) -> void:
	if not _keep():
		return
	_trace.append("tel %d %s %s %s %.4f,%.4f,%.4f %.4f" % [_rel(tick), actor_id, action_id, target_id, origin.x, origin.y,
		origin.z, yaw])


func _t_died(tick: int, e: String, k: String) -> void:
	if not _keep():
		return
	_trace.append("died %d %s %s" % [_rel(tick), e, k])


func _t_phase(tick: int, b: String, p: int) -> void:
	if not _keep():
		return
	_trace.append("phase %d %s %d" % [_rel(tick), b, p])


func _t_stag(tick: int, e: String, d: float, reason: String) -> void:
	if not _keep():
		return
	_trace.append("stag %d %s %.3f %s" % [_rel(tick), e, d, reason])


## Runs `body` (a parent test) without and with the people; the two traces must be the same events.
func _twin(label: String, body: Callable) -> void:
	var traces: Array = []
	var drawn := 0
	for on: bool in [false, true]:
		if on:
			PersonRig.enable_for_tests()
			SkinnedRig.enable_for_tests()
		else:
			PersonRig.reset_for_tests()
			SkinnedRig.reset_for_tests()
		var frames0 := int(SkinnedRig.totals.get("posed_frames", 0)) + int(CreatureSlots.totals.get("skinned_frames", 0)) \
			+ int(PersonRig.totals.get("skinned_frames", 0))
		_trace.clear()
		_t0 = -1
		await body.call()
		traces.append(_trace.duplicate())
		if on:
			drawn = int(SkinnedRig.totals.get("posed_frames", 0)) + int(CreatureSlots.totals.get("skinned_frames", 0)) \
				+ int(PersonRig.totals.get("skinned_frames", 0)) - frames0
	var a: PackedStringArray = traces[0]
	var b: PackedStringArray = traces[1]
	assert_true(a.size() > 20, "%s: the fight's events traced (%d)" % [label, a.size()])
	var first := -1
	for i in mini(a.size(), b.size()):
		if a[i] != b[i]:
			first = i
			break
	assert_true(a == b, "%s: the same events with the people drawn and not (%d / %d events%s)" % [label, a.size(), b.size(),
		"" if first < 0 else "; first difference at %d: %s | %s" % [first, a[first], b[first]]])
	assert_true(drawn > 100, "%s: the skinned bodies drew (%d frames)" % [label, drawn])
	print("    test_bosses_seeded_people: %s, %d events the same, hash %s, %d skinned frames" % [label, a.size(),
		"\n".join(a).sha256_text().left(12), drawn])


## (the parent's ten-seed runs are test_bosses_seeded's own: not run again here)
func test_the_matriarch_ten_seeds() -> void:
	pass


func test_harrok_ten_seeds() -> void:
	pass


func test_the_iron_regiment_ten_seeds() -> void:
	pass


func test_the_matriarch_twin() -> void:
	await _twin("the Matriarch", _run_matriarch)


func test_harrok_twin() -> void:
	await _twin("Harrok", _run_harrok)


func test_the_iron_regiment_twin() -> void:
	await _twin("the iron regiment", _run_iron_regiment)


## (test_bosses_seeded's ten seeds assert that telegraphed blows landed; two seeds may see none land: here every blow
## that did land is still checked, and none landing is not a failure)
func _check_telegraphed(p: GiantPlayer, actors: Array, label: String) -> int:
	return maxi(1, super(p, actors, label))
