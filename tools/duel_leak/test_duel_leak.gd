extends IntegrationSuite
## B5 (G11): the titans' duel bisection harness - one duel run alone or after another fight in the same process, its
## state dumped every tick, to find the first tick and the first field at which two runs part. Run it as one suite:
##
##   tools/gd.sh --headless --path . --fixed-fps 60 res://tests/run_tests.tscn -- --no-user-settings --no-audio \
##     --suite=res://tools/duel_leak/test_duel_leak.gd --leak-duel=stoneback|grove --leak-pre=none|king|stoneback|grove \
##     [--leak-stage=N] [--leak-seed=N] [--leak-s=SECONDS] [--leak-every=TICKS] [--leak-pre-s=SECONDS] [--leak-legacy] [--leak-shared-space]
##     --leak-out=<file.jsonl>
##
## then compare two dumps: python3 tools/duel_leak/duel_leak_diff.py <alone.jsonl> <after.jsonl> [ignored,keys]
## (it prints the first tick at which they differ and every field that differs there; ticks and the attack instance
## counters are global and differ by design: the diff takes the tick offset out and is told to ignore the counters).
## The dump: the giant, the titan and the duel bot with every script variable of theirs and of the objects they hold
## (three levels deep: the brain, the controllers, the pools, the plates, the camera rig, the bot's BotCombat), their
## places, velocities and RNG states, and Sim's globals (the tick's phase, the crit rng and every named stream, the
## tokens, the launch slots, the attack instance counter), the aim deferral's held swings, NavQuery's count and the
## projectiles' id. --leak-legacy starts the duel as the titans' suites did before B5 (the whole second waited for
## after the level is loaded, Sim's streams not reseeded in the grove): the leak B5 found.
## Debug only; never part of a tier (tools/ is no suite folder).

const QUARRY := "res://scenes/test/quarry_test.tscn"
const ARENA := "res://scenes/test/boss_arena_test.tscn"

var _out: FileAccess


## B5: each duel in its own physics space (TestWait.duel_host) unless --leak-shared-space (as before B5).
func _host() -> Node:
	return world if OS.get_cmdline_user_args().has("--leak-shared-space") else TestWait.duel_host(world)


func _free(n: Node) -> void:
	(n.get_parent() if n.get_parent() is SubViewport else n).queue_free()


func _legacy() -> bool:
	return OS.get_cmdline_user_args().has("--leak-legacy")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


static func _clean(s: String) -> String:
	var re := RegEx.new()
	re.compile("#-?\\d+|<[^>]*>|\\b\\d{8,}\\b")
	return re.sub(s, "#", true)


func _dump_obj(o: Object, path: String, into: Dictionary, depth: int, seen: Dictionary) -> void:
	if o == null or not is_instance_valid(o) or seen.has(o.get_instance_id()) or depth > 3:
		return
	seen[o.get_instance_id()] = true
	if o is Node3D and (o as Node3D).is_inside_tree():
		var n := o as Node3D
		into[path + ".@pos"] = str(n.global_position)
		into[path + ".@basis"] = str(n.global_basis)
	if o is CharacterBody3D:
		into[path + ".@vel"] = str((o as CharacterBody3D).velocity)
	if o is RandomNumberGenerator:
		into[path + ".@state"] = str((o as RandomNumberGenerator).state)
		into[path + ".@seed"] = str((o as RandomNumberGenerator).seed)
	for prop: Dictionary in o.get_property_list():
		if not (int(prop.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var k := str(prop.name)
		var v: Variant = o.get(k)
		var key := path + "." + k
		match typeof(v):
			TYPE_OBJECT:
				if v != null and is_instance_valid(v) and not (v is Resource and not (v is RandomNumberGenerator)):
					if v is Node and not (v is Node3D or depth < 1):
						continue
					_dump_obj(v, key, into, depth + 1, seen)
			TYPE_ARRAY, TYPE_DICTIONARY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
				var s := _clean(str(v))
				into[key] = "%d:%d" % [s.length(), hash(s)] if s.length() > 200 else s
			TYPE_CALLABLE, TYPE_SIGNAL:
				pass
			_:
				into[key] = str(v)


func _globals(into: Dictionary) -> void:
	into["G.sim.tick60"] = str(Sim.tick % 60)
	into["G.sim.next_instance"] = str(Sim.get("_next_instance_id"))
	into["G.sim.rng"] = str(Sim.rng.state)
	var streams: Dictionary = Sim.get("_streams")
	for k in streams:
		into["G.sim.stream." + str(k)] = str((streams[k] as RandomNumberGenerator).state)
	into["G.sim.tokens"] = _clean(str(Sim.get("_tokens")))
	into["G.sim.launches"] = _clean(str(Sim.get("_launches")))
	into["G.sim.ordered"] = str((Sim.get("_ordered") as Array).size())
	into["G.hitfactory.deferred"] = _clean(str(HitFactory._deferred))
	into["G.nav.total"] = str(NavQuery.queries_total)
	into["G.proj.next"] = str(ProjectileSystem._next_id)


func _king(seed_value: int) -> void:
	await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(ARENA) as PackedScene).instantiate() as Node3D
	_host().add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 60)
	TitanDuel.prepare(p, 2)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, 2)
	var t := level.get_node("OgreKing") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, -10)
	(level.get_node("BossArena") as BossArena).engage()
	var bot := TitanDuelBot.new()
	bot.round_to_back = false
	bot.setup(p, t, "novice", seed_value, false)
	var start := Sim.tick
	while Sim.tick - start < 240 * 60 and p.entity.is_alive() and t.entity.is_alive():
		bot.step(Sim.tick)
		await step_ticks(1)
	bot.teardown()
	print("LEAK_PRE king seed %d: giant %s titan %.3f at %d" % [seed_value, p.entity.is_alive(),
		t.entity.combatant.pools.ratio("health"), Sim.tick - start])
	GameSession.expansion = ExpansionState.defaults()
	_free(level)
	await step_ticks(2)


func _stoneback(stage: int, seed_value: int, max_s: float, dump: bool) -> void:
	if not _legacy():
		await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.expansion = ExpansionState.defaults()
	var level := (load(QUARRY) as PackedScene).instantiate() as Node3D
	level.set("stage", 0)
	_host().add_child(level)
	var p := level.get_node("Player") as GiantPlayer
	await TestWait.until(self, func() -> bool: return p.is_on_floor(), 30)
	TitanDuel.prepare(p, stage)
	await TestWait.until(self, func() -> bool: return Sim.tick % 60 == 59, 70)
	Sim.reseed(Sim.DEFAULT_SEED)
	TitanDuel.prepare(p, stage)
	var t := level.get_node("Stoneback") as TitanEnemy
	t.brain.rng.seed = seed_value
	p.global_position = Vector3(0, 0.05, 22)
	var arena := level.get_node("BossArena") as BossArena
	arena.disengage_s = 1.0e9
	arena.engage()
	var bot := TitanDuelBot.new()
	bot.setup(p, t, "expert", seed_value, true)
	var start := Sim.tick
	while Sim.tick - start < int(max_s * 60):
		if dump and (Sim.tick - start) % maxi(1, int(_arg("leak-every", "1"))) == 0:
			var m := {}
			_globals(m)
			_dump_obj(p, "P", m, 0, {})
			_dump_obj(t, "T", m, 0, {})
			_dump_obj(bot, "B", m, 0, {})
			_out.store_line(JSON.stringify({"t": Sim.tick - start, "m": m}))
		bot.step(Sim.tick)
		await step_ticks(1)
		if not p.entity.is_alive() or not t.entity.is_alive():
			break
	bot.teardown()
	print("LEAK_DUEL stoneback stage %d seed %d: giant %s titan %.3f at %.1f s" % [stage, seed_value,
		p.entity.is_alive(), t.entity.combatant.pools.ratio("health"), (Sim.tick - start) / 60.0])
	GameSession.expansion = ExpansionState.defaults()
	_free(level)
	await step_ticks(2)


const SCENE := "res://scenes/world/world.tscn"


func after_each() -> void:
	get_tree().paused = false
	for f in Formation.live():
		f.dissolve()
	FactionState.reset_for_tests()
	WanderDirector.reset_for_tests()
	GameSession.expansion = ExpansionState.defaults()
	await super()


func _warden() -> TitanEnemy:
	for n in get_tree().root.find_children("*", "TitanEnemy", true, false):
		var t := n as TitanEnemy
		if t.entity != null and t.entity.definition_id == "enemy.rootwarden":
			return t
	return null


func _grove(stage: int, seed_value: int, max_s: float, dump: bool) -> void:
	if not _legacy():
		await TestWait.duel_start(self)
	WorldState.clear()
	GameSession.start_world_for_tests("world.cp.hollowmere")
	GameSession.level_id = GameSession.WORLD_LEVEL_ID
	var w := (load(SCENE) as PackedScene).instantiate() as WorldRoot
	_host().add_child(w)
	w.streamer.deterministic = true
	var p := w.player()
	p.router.use_injection = true
	GameSession.on_level_ready(w, p)
	WorldState.try_set_flag("world.rootwarden.called", true)
	WorldState.try_set_flag("world.rootwarden.resin_laid", true)
	var at := Vector3(-770.0, 200.0, 208.0)
	p.process_mode = Node.PROCESS_MODE_DISABLED
	p.global_position = at
	var guard := 0
	while not w.streamer.ring_ready(at) and guard < 900:
		w.streamer.load_ring_slice(at)
		await step_ticks(1)
		guard += 1
	p.global_position = Vector3(at.x, w.height_at(at) + 0.3, at.z)
	p.velocity = Vector3.ZERO
	p.process_mode = Node.PROCESS_MODE_INHERIT
	TitanDuel.prepare(p, stage)
	await step_ticks(30)
	var t := _warden()
	t.brain.rng.seed = seed_value
	var bot := TitanDuelBot.new()
	bot.see_obstacles = true   # (as the grove's duels: tests/titans/test_rootwarden_grove_duels.gd)
	bot.setup(p, t, "expert", seed_value, true)
	var start := Sim.tick
	print("LEAK_GROVE_START guard %d tick %d phase %d" % [guard, Sim.tick, Sim.tick % 60])
	while Sim.tick - start < int(max_s * 60):
		if dump and (Sim.tick - start) % maxi(1, int(_arg("leak-every", "1"))) == 0:
			var m := {}
			_globals(m)
			_dump_obj(p, "P", m, 0, {})
			_dump_obj(t, "T", m, 0, {})
			_dump_obj(bot, "B", m, 0, {})
			_out.store_line(JSON.stringify({"t": Sim.tick - start, "m": m}))
		bot.step(Sim.tick)
		await step_ticks(1)
		if not p.entity.is_alive() or not t.entity.is_alive():
			break
	bot.teardown()
	print("LEAK_DUEL grove stage %d seed %d: giant %s titan %.3f at %.1f s" % [stage, seed_value,
		p.entity.is_alive(), t.entity.combatant.pools.ratio("health"), (Sim.tick - start) / 60.0])
	GameSession.expansion = ExpansionState.defaults()
	_free(w)
	await step_ticks(2)


func test_probe() -> void:
	var pre := _arg("leak-pre", "none")
	_out = FileAccess.open(_arg("leak-out", "user://duel_leak.jsonl"), FileAccess.WRITE)
	if pre == "king":
		await _king(2)
	elif pre == "stoneback":
		await _stoneback(3, 2, 60.0, false)
	elif pre == "grove":
		await _grove(5, 1, float(_arg("leak-pre-s", "60")), false)
	if _arg("leak-duel", "stoneback") == "grove":
		await _grove(int(_arg("leak-stage", "5")), int(_arg("leak-seed", "1")), float(_arg("leak-s", "100")), true)
	else:
		await _stoneback(int(_arg("leak-stage", "3")), int(_arg("leak-seed", "1")), float(_arg("leak-s", "100")), true)
	_out.close()
	assert_true(_out != null, "the dump written")
