extends IntegrationSuite
## P21 (plan M6-M9 §3.3 coverage tests, §4.1): every event that exists today has a sound or is
## deliberately silent, and every record resolves the cues the router asks for - by the P21 banks,
## never by a placeholder or a family default:
##   * every Events signal is routed (with a handler) or in the silent list
##   * every enemy and NPC record resolves its voice's alert, attack, hurt, stagger and death
##     calls (flee for the bodies that rout, awe for the humans, greet for the NPCs)
##   * every action with a telegraph resolves its windup; every ranged one the aim lock
##   * every prop that can be struck resolves its hit, its crack (structural) and its break by
##     material and size; gates their opening
##   * every weapon family the swing map knows resolves its light and heavy swings
##   * every ability of the progression library resolves its cast and its effects; every enemy
##     action its own; every projectile visual its launch and landing
##   * every UI screen resolves open and close; every interface cue the router names resolves
##   * every request the router builds for M6 content, and a run of real events through the
##     router, resolve with nothing missing and nothing from the placeholder bank.

const P21_BANKS := ["audio_bank.combat", "audio_bank.abilities", "audio_bank.steps", "audio_bank.voices",
	"audio_bank.threat", "audio_bank.world", "audio_bank.ui"]
## Node's own signals (not game events).
const CALLS := ["alert", "attack", "hurt", "stagger", "death"]


func before_each() -> void:
	await super()
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)
	await super()


## The cue a request resolves to, which must be a P21 cue (and, when exact, the cue asked for).
func _resolves(chain: Array, what: String, exact := false) -> bool:
	var cue := Audio.resolve_chain(chain)
	if cue.is_empty():
		fail("%s: %s resolves to nothing" % [what, chain])
		return false
	checks += 1
	if not P21_BANKS.has(str(cue.bank)):
		fail("%s: %s resolves to %s from %s, not an effect bank" % [what, chain, cue.id, cue.bank])
		return false
	if exact and str(cue.id) != str(chain[0]):
		fail("%s: %s resolves to %s, not itself" % [what, chain[0], cue.id])
		return false
	if str(cue.id).ends_with(".default") and not str(chain[0]).ends_with(".default") and not chain.has(cue.id):
		fail("%s: %s falls back to the family default %s" % [what, chain, cue.id])
		return false
	return true


# --------------------------------------------------------------------------- signals

func test_every_events_signal_is_routed_or_deliberately_silent() -> void:
	var base := {}
	for s: Dictionary in ClassDB.class_get_signal_list("Node", false):
		base[str(s.name)] = true
	var handled := CueRouter.ROUTED_SIGNALS + CueRouter.STATE_SIGNALS
	var count := 0
	for s: Dictionary in Events.get_signal_list():
		var sig := str(s.name)
		if base.has(sig):
			continue
		count += 1
		var routed := handled.has(sig)
		assert_true(routed or CueRouter.SILENT_SIGNALS.has(sig), "%s is routed or deliberately silent (§4.1)" % sig)
		if routed:
			assert_true(Audio.router.has_method("_on_" + sig), "%s has its handler" % sig)
	assert_true(count >= 90, "every game event is checked (%d)" % count)


# --------------------------------------------------------------------------- records

func test_every_enemy_and_npc_resolves_its_calls() -> void:
	var mix: Dictionary = Audio.mix
	for t: String in ["enemy", "npc"]:
		for rec: Dictionary in GameData.records_of_type(t):
			var voice := str((mix.voices as Dictionary).get(rec.id, "human"))
			if voice == "none":
				# a voiceless body sounds like what it is made of when struck (P21's routing rule)
				_resolves(["sfx.hit.%s" % Audio.router.material_of(str(rec.id))], "%s struck" % rec.id, true)
				continue
			for call: String in CALLS:
				_resolves(["sfx.voice.%s.%s" % [voice, call]], "%s %s" % [rec.id, call], true)
			var tactics: Dictionary = rec.get("tactics", {})
			if t == "enemy" and not bool(rec.get("ignores_morale", false)):
				_resolves(["sfx.voice.%s.flee" % voice], "%s routs" % rec.id, true)
			if tactics.has("awe_ratio"):
				_resolves(["sfx.voice.%s.awe" % voice], "%s is awed" % rec.id, true)
			if t == "npc":
				_resolves(["sfx.voice.%s.greet" % voice], "%s greets" % rec.id, true)
			# its footfalls on every Valley surface
			var step := Audio.router.step_class_of(str(rec.id))
			for surface: String in ["soft", "hard", "wet"]:
				_resolves(["sfx.step.%s.%s" % [step, surface]], "%s steps on %s ground" % [rec.id, surface])
	_resolves(["sfx.voice.giant.intimidate"], "the giant intimidates", true)
	_resolves(["sfx.voice.talker.greet"], "a talker without a body greets", true)
	for state: String in CueRouter.FACTION_CUES:
		_resolves([CueRouter.FACTION_CUES[state]], "the village %s" % state, true)


func test_every_telegraph_resolves_its_windup_and_every_ranged_attack_its_aim_lock() -> void:
	var shapes := {}
	for rec: Dictionary in GameData.records_of_type("action"):
		var tel: Variant = rec.get("telegraph")
		if typeof(tel) == TYPE_DICTIONARY and str((tel as Dictionary).get("shape", "")) != "":
			shapes[str(tel.shape)] = str(rec.id)
	assert_true(shapes.size() >= 3, "line, circle and cone telegraphs exist (%s)" % [shapes.keys()])
	for shape: String in shapes:
		_resolves(["sfx.threat.windup.%s" % shape], "%s's %s windup" % [shapes[shape], shape], true)
	_resolves(["sfx.threat.sting"], "the off-camera sting", true)
	_resolves(["sfx.threat.aim_lock"], "a ranged aim lock", true)


func test_every_prop_resolves_its_hit_crack_break_and_opening() -> void:
	var mix: Dictionary = Audio.mix
	for rec: Dictionary in GameData.records_of_type("prop"):
		if str(rec.get("category", "")) == "cosmetic":
			continue   # no CombatEntity: never struck (CosmeticProp reacts visually only)
		var mat := str((mix.materials as Dictionary).get(rec.id, "wood"))
		_resolves(["sfx.hit.%s" % mat], "%s struck" % rec.id, true)
		if rec.has("damage_stages"):
			_resolves(["sfx.crack.%s" % mat], "%s cracks" % rec.id, true)
			_resolves(["sfx.world.open.%s" % mat], "%s opens" % rec.id, true)
		if not bool(rec.get("unkillable", false)) and str(rec.get("category", "")) != "training_target":
			var size := "large" if float(rec.get("height_m", 1.0)) >= CueRouter.BREAK_LARGE_M else "small"
			_resolves(["sfx.break.%s.%s" % [mat, size]], "%s breaks" % rec.id, true)


func test_every_weapon_family_resolves_its_swings() -> void:
	var families := {}
	for rec: Dictionary in GameData.records_of_type("weapon"):
		var fam := str(CueRouter.SWING_FAMILIES.get(str(rec.get("family", "")), ""))
		if fam != "":
			families[fam] = str(rec.id)
	for fam: String in ["blunt", "blade", "tree"]:
		assert_true(families.has(fam), "a %s weapon exists" % fam)
	for fam: String in families:
		for weight: String in ["light", "heavy"]:
			_resolves(["sfx.swing.%s.%s" % [fam, weight]], "%s swung %s" % [families[fam], weight], true)
	for rec: Dictionary in GameData.records_of_type("weapon"):
		var family := str(rec.get("family", ""))
		if ["club", "sword", "hammer", "tree"].has(family):
			_resolves(["sfx.ui.equip.%s" % family, "sfx.ui.equip"], "%s equipped" % rec.id)


## The effect suffixes an action's hit shape and params make the router ask for.
static func _effect_cues(a: ActionDef) -> Array:
	var short := AudioMath.short_id(a.id)
	var out: Array = []
	match a.hit_shape:
		"cylinder_pulse":
			out.append(["sfx.ability.%s.impact" % short, "sfx.impact.stomp"])
			if float(a.param("morale_damage", 0.0)) > 0.0:
				out.append(["sfx.ability.%s.roar" % short])
		"sector_pulse":
			out.append(["sfx.ability.%s.sweep" % short])
		"projectile":
			out.append(["sfx.ability.%s.cast" % short])
			var spec := Projectile.spec_for(a)
			out.append(["sfx.projectile.%s.launch" % str(spec.visual)])
			out.append(["sfx.impact.%s" % str(spec.visual)])
			if float(spec.impact_radius_m) > 0.0:
				out.append(["sfx.ability.%s.impact" % short, "sfx.impact.stomp"])
	var selfs: Variant = a.param("self_statuses")
	if typeof(selfs) == TYPE_ARRAY and not (selfs as Array).is_empty():
		out.append(["sfx.ability.%s.on" % short])
	return out


func test_every_ability_and_enemy_action_resolves_its_cues() -> void:
	var library: Array = GameData.get_record("progression.default").ability_library
	assert_true(library.size() >= 9, "the library is read (%d abilities)" % library.size())
	for id: Variant in library:
		var a := GameData.get_action(str(id))
		_resolves(["sfx.ability.%s.cast" % AudioMath.short_id(a.id)], "%s cast" % a.id, true)
		for chain: Array in _effect_cues(a):
			_resolves(chain, "%s effect" % a.id, chain.size() == 1)
		var selfs: Variant = a.param("self_statuses")
		if typeof(selfs) == TYPE_ARRAY:
			for entry: Variant in selfs:
				var sid := str((entry as Dictionary).get("status", ""))
				if (GameData.get_record(sid).get("tags", []) as Array).has("Buff"):
					_resolves(["sfx.status.%s.off" % AudioMath.short_id(sid)], "%s wears off" % sid, true)
	for id: String in ["ability.grab_hold", "ability.throw_held"]:
		_resolves(["sfx.ability.%s.cast" % AudioMath.short_id(id)], "%s cast" % id, true)
	for rec: Dictionary in GameData.records_of_type("enemy"):
		for id: Variant in rec.get("attacks", []):
			var a := GameData.get_action(str(id))
			for chain: Array in _effect_cues(a):
				if a.hit_shape == "projectile" and str(chain[0]).ends_with(".cast") or chain.size() == 1:
					_resolves(chain, "%s's %s" % [rec.id, a.id], true)
				else:
					_resolves(chain, "%s's %s" % [rec.id, a.id])
	_resolves(["sfx.ability.mage_barrier.on"], "the mage's barrier", true)
	_resolves(["sfx.voice.ogre_king.roar", "sfx.voice.ogre_king.attack"], "the King's phase roar", true)
	for status: String in ["sfx.status.slow"]:
		_resolves([status], "the giant slowed", true)
	for reason: String in ["seize", "throw", "drop", "crush"]:
		_resolves(["sfx.grab.%s" % reason], "a grab %s" % reason, true)


func test_every_ui_screen_and_interface_cue_resolves() -> void:
	var screens := 0
	for screen: String in ScreenStack.SCREENS:
		if not ResourceLoader.exists(str(ScreenStack.SCREENS[screen])):
			continue
		screens += 1
		_resolves(["sfx.ui.map_open" if screen == "map" else "sfx.ui.open"], "the %s screen opens" % screen, true)
		_resolves(["sfx.ui.close"], "the %s screen closes" % screen, true)
	assert_true(screens >= 8, "every shipped screen is checked (%d)" % screens)
	for cue: String in ["sfx.ui.move", "sfx.ui.select", "sfx.ui.back", "sfx.ui.denied", "sfx.ui.saved", "sfx.ui.loot",
			"sfx.ui.item", "sfx.ui.item.metal", "sfx.ui.item.quest", "sfx.ui.ability_learned", "sfx.ui.quest_new",
			"sfx.ui.tip", "sfx.ui.lock_on", "sfx.ui.lock_off", "sfx.ui.camera", "sfx.ui.warn", "sfx.ui.map_open"]:
		_resolves([cue], cue, true)


func test_every_m6_request_of_the_router_resolves() -> void:
	# the giant's footfalls, stage by stage and surface by surface (the cruise chain included)
	for stage in range(1, 4):
		for surface: String in ["soft", "hard", "wet"]:
			var base := "sfx.step.giant_s%d.%s" % [stage, surface]
			_resolves([base], "stage %d on %s" % [stage, surface], true)
			_resolves([base + ".cruise", base], "stage %d cruising on %s" % [stage, surface])
	for armor: String in ["flesh", "armor"]:
		for weight: String in ["light", "heavy"]:
			_resolves(["sfx.hit.%s.%s" % [armor, weight]], "a %s hit on %s" % [weight, armor], true)
	for cue: String in ["sfx.hit.crit", "sfx.hit.immune", "sfx.block.player", "sfx.block.guard", "sfx.parry",
			"sfx.guard_break", "sfx.clank.stone", "sfx.body.fall.small", "sfx.body.fall.large", "sfx.body.fall.huge",
			"sfx.dodge.roll", "sfx.dodge.sidestep", "sfx.block.raise", "sfx.jump", "sfx.player.hurt",
			"sfx.player.hurt.heavy", "sfx.player.stagger", "sfx.player.death", "sfx.world.growth",
			"sfx.world.shrine_wake", "sfx.world.shrine_rest", "sfx.world.waystone", "sfx.world.forge_upgrade",
			"sfx.world.gate_iron", "sfx.world.alarm_bell"]:
		_resolves([cue], cue, true)
	for kind: String in ["pickup", "weapon", "forge", "uproot", "talk"]:
		_resolves(["sfx.world.interact.%s" % kind], "interacting: %s" % kind, true)
	for profile: Dictionary in GameData.records_of_type("growth_profile"):
		_resolves(["sfx.dodge.%s" % str(profile.get("dodge_style", "roll"))], "%s's dodge" % profile.id, true)
	# every far version a big cue names resolves
	for cue_id: String in Audio.cue_ids():
		var far := str(Audio.resolve(cue_id).get("far", ""))
		if far != "":
			_resolves([far], "%s's far version" % cue_id, true)


# --------------------------------------------------------------------------- real events through the router

## Lets the router drain its queue, then records the cues started (cue -> requested) and frees
## the voices (the Dummy driver plays in real time while the run is faster).
func _harvest(played: Dictionary) -> void:
	Audio.clock_s += 0.2
	await get_tree().process_frame
	for e: Dictionary in Audio.cue_log():
		played[str(e.cue)] = str(e.requested)
	Audio.clear_log()
	Audio.pool.stop_all()


func test_real_events_play_effect_cues_with_nothing_missing() -> void:
	var p := spawn_player(Vector3(0, 0, 6))
	var s := spawn_soldier(Vector3(0, 0, 2), PI, "t.cov_soldier")
	var d := spawn_dummy(Vector3(5, 0, 0), "t.cov_dummy")
	await step_ticks(3)
	Audio.clear_log()
	var pid := p.entity.entity_id
	var sid := s.entity.entity_id
	# hits: the giant on the soldier and on the dummy, the soldier on the giant, a block, a parry
	queue_hit(pid, sid, p.global_position, 40.0)
	queue_hit(pid, (d.get_node("CombatEntity") as CombatEntity).entity_id, p.global_position, 20.0)
	queue_hit(sid, pid, s.global_position, 30.0)
	await step_ticks(2)
	var played := {}
	_harvest(played)
	var events: Array[Callable] = [
		func() -> void: Events.ability_started.emit(Sim.tick, pid, "ability.light_1", Sim.new_instance_id()),
		func() -> void: Events.ability_started.emit(Sim.tick, pid, "action.dodge", Sim.new_instance_id()),
		func() -> void: Events.ability_started.emit(Sim.tick, pid, "ability.thunder_roar", Sim.new_instance_id()),
		func() -> void: Events.ability_started.emit(Sim.tick, sid, "ability.soldier_chop", Sim.new_instance_id()),
		func() -> void: Events.area_pulse.emit(Sim.tick, pid, "ability.heavy_footfall", p.global_position, 6.0),
		func() -> void: Events.ability_effect.emit(Sim.tick, pid, "ability.thunder_roar", "roar", p.global_position, 8.0, 0.0, 360.0),
		func() -> void: Events.ability_effect.emit(Sim.tick, pid, "ability.sweeping_blow", "sector", p.global_position, 6.0, 0.0, 200.0),
		func() -> void: Events.ability_effect.emit(Sim.tick, pid, "ability.stone_skin", "self_buff", p.global_position, 0.0, 0.0, 0.0),
		func() -> void: Events.status_applied.emit(Sim.tick, pid, "status.slow", sid, 3.0),
		func() -> void: Events.status_expired.emit(Sim.tick, pid, "status.stone_skin"),
		func() -> void: Events.grab_started.emit(Sim.tick, pid, sid),
		func() -> void: Events.grab_ended.emit(Sim.tick, pid, sid, "thrown"),
		func() -> void: Events.staggered.emit(Sim.tick, sid, 1.0, "poise"),
		func() -> void: Events.morale_changed.emit(Sim.tick, sid, 20.0, -35.0, "awe"),
		func() -> void: Events.enemy_routed.emit(Sim.tick, sid, ""),
		func() -> void: Events.entity_died.emit(Sim.tick, sid, pid),
		func() -> void: Events.growth_changed.emit(Sim.tick, pid, 1, 2),
		func() -> void: Events.upgrade_applied.emit(Sim.tick, "weapon.club", "weapon.club_reinforced"),
		func() -> void: Events.faction_changed.emit(Sim.tick, "village", "warned"),
		func() -> void: Events.dialogue_outcome.emit(Sim.tick, "dialogue.elder", "intimidate"),
		func() -> void: Events.dialogue_ended.emit(Sim.tick, "dialogue.elder"),
		func() -> void: Events.loot_awarded.emit(Sim.tick, "x", "item.wood_scrap", 1, pid),
		func() -> void: Events.item_added.emit(Sim.tick, "item.iron_ingot", 1, "loot"),
		func() -> void: Events.weapon_equipped.emit(Sim.tick, pid, "weapon.sword"),
		func() -> void: Events.ability_learned.emit(Sim.tick, "ability.runic_bolt", "slot_6"),
		func() -> void: Events.quest_started.emit(Sim.tick, "quest.main"),
		func() -> void: Events.tutorial_shown.emit(Sim.tick, "tutorial.light"),
		func() -> void: Events.lock_target_changed.emit(pid, sid, "press"),
		func() -> void: Events.camera_mode_changed.emit(1),
		func() -> void: Events.hud_message.emit("Not enough stamina", "warn"),
		func() -> void: Events.checkpoint_saved.emit(Sim.tick, "cp", true, ""),
		func() -> void: Events.attack_clanked.emit(Sim.tick, sid, 1, s.global_position),
		func() -> void: Events.telegraph_started.emit(Sim.tick, sid, "ability.soldier_chop", pid, "line", s.global_position,
			0.0, 0.3, 2.5, 0.85),
	]
	# a few events a frame (a frame starts at most starts_per_frame voices), the voices freed between
	for i in range(0, events.size(), 3):
		for k in range(i, mini(i + 3, events.size())):
			events[k].call()
		await _harvest(played)
	assert_eq(Audio.missing, {}, "nothing the router asked for is missing")
	assert_true(played.size() >= 30, "the events played their cues (%d)" % played.size())
	for cue_id: String in played:
		if cue_id.begins_with("mus."):
			continue   # stingers: the placeholder until P23
		assert_true(P21_BANKS.has(str(Audio.resolve(cue_id).get("bank", ""))), "%s (asked as %s) comes from an effect bank" % [
			cue_id, played[cue_id]])
	for expected: String in ["sfx.voice.human.hurt", "sfx.hit.wood", "sfx.player.hurt", "sfx.swing.blunt.light",
			"sfx.ability.thunder_roar.roar", "sfx.voice.human.death", "sfx.body.fall.small", "sfx.threat.windup.line"]:
		assert_true(played.has(expected), "%s played (%s)" % [expected, played.keys()])
