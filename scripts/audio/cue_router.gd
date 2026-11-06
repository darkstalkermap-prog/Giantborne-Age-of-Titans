class_name CueRouter
extends Node
## Events -> cue requests (P19; plan M6-M9 §2.5, §3.1 design 3, every row of the cue map §4.1). Child
## "Router" of the Audio autoload. One handler per Events signal and per footfall source builds a
## request - the cue's candidates (the most specific first; AudioMath.expand_chain adds each one's
## parents and the family default), the position, the source's height, the priority, the reason
## and, for threat stings, the expected damage and poise ratio - into a queue that Audio drains in
## _process (Audio.play does the rest: resolution, caps, the retrigger guard, the level check,
## variants, voices). Nothing here changes game state: handlers only read.
##
## Conventions (§2.5): enemy and NPC cues use the record's voice (audio_mix.voices, default
## "human"; "none" stays silent), prop cues its material (audio_mix.materials, default "wood"),
## footfalls the size class (giant_s<stage> for the player; audio_mix.steps or the archetype for
## the others: human, paw, hoof, heavy), the surface under the foot (Audio.surface_at) and "wade"
## in water above the foot (the player and heavy bodies); after cruise_after_s of continuous
## walking the player's footfall uses its ".cruise" variant at cruise_duck_db (back to the full cue
## in combat, on stopping, on a jump and on a stomp).
##
## Polled, not signalled (no actor code changes): enemy awareness edges every 0.25 s (unaware ->
## aware within alert_radius_m x scale: one alert bark per encounter per alert_gap_s), ranged aim
## commits every frame (a projectile action's windup passes tracking_fraction: sfx.threat.aim_lock),
## water entries (when the level has water_at). Screens: a UiScreen joining the tree opens
## (sfx.ui.open; the map: sfx.ui.map_open), its `closed` closes; focus moves while a screen is open
## (sfx.ui.move); ui_accept / ui_cancel while a screen is open (sfx.ui.select / sfx.ui.back).
##
## M7-M9 signals (P20 declares them; P28 tests their rows) are connected only when
## Events.has_signal(name) holds; their handlers take their arguments as one array, so a
## signature refined later cannot break the connection.

## Every Events signal the router handles (P21's coverage test: each signal is here or silent).
const ROUTED_SIGNALS := ["hit_resolved", "attack_clanked", "ability_started", "action_rejected",
	"area_pulse", "entity_died", "staggered", "object_destroyed", "loot_awarded", "growth_changed",
	"lock_target_changed", "camera_mode_changed", "hud_message", "status_applied", "status_expired",
	"ability_effect", "projectile_spawned", "projectile_impact", "telegraph_started", "morale_changed",
	"enemy_routed", "boss_engaged", "boss_phase_changed", "boss_defeated", "faction_changed",
	"grab_started", "grab_ended", "growth_blocked", "shrine_activated", "shrine_rested",
	"checkpoint_reached", "checkpoint_saved", "object_stage_changed", "object_opened", "interacted",
	"weapon_equipped", "loadout_changed", "level_changed", "ability_learned", "attributes_changed",
	"item_added", "upgrade_applied", "quest_started", "quest_stage_changed", "quest_completed",
	"dialogue_started", "dialogue_outcome", "tutorial_shown", "slice_completed",
	# M7-M9 (connected when they exist)
	"poi_discovered", "region_changed", "level_leaving", "level_entered", "travel_requested",
	"size_gate_blocked", "trampled", "formation_changed", "siege_engine_fired", "siege_engine_crewed",
	"boss_yielded", "boss_disengaged", "ability_evolved", "talent_learned", "ancestry_chosen",
	"world_event_started", "world_event_ended"]
## Deliberately silent (§4.1; dialogue_ended only lifts the dialogue duck).
const SILENT_SIGNALS := ["area_entered", "area_exited", "flag_changed", "xp_gained", "xp_award_requested",
	"item_removed", "ui_screen_requested", "encounter_activated", "encounter_cleared", "encounter_leashed",
	"healed", "checkpoint_loaded", "reload_checkpoint_requested", "mode_change_requested",
	"dialogue_requested", "dialogue_ended", "tutorial_dismissed", "quest_abandoned", "quest_tracked",
	"wander_spawned", "world_chunk_loaded", "world_chunk_unloading", "world_chunk_unloaded",
	"sandbox_reset_requested"]
## Silent signals the router still listens to for state (dialogue_ended lifts the dialogue duck).
const STATE_SIGNALS := ["dialogue_ended"]
## The signals whose handlers take one array (declared by P20 in W12 and later packages).
const VARIADIC_SIGNALS := ["poi_discovered", "region_changed", "level_leaving", "level_entered",
	"travel_requested", "size_gate_blocked", "trampled", "formation_changed", "siege_engine_fired",
	"siege_engine_crewed", "boss_yielded", "boss_disengaged", "ability_evolved", "talent_learned",
	"ancestry_chosen", "world_event_started", "world_event_ended"]
## Weapon family -> swing family (§4.1 B).
const SWING_FAMILIES := {"club": "blunt", "hammer": "blunt", "natural": "blunt", "sword": "blade",
	"tree": "tree", "fists": "fists", "axe": "axe"}
const ARMOR_HEAVY := 20.0
const HEAVY_POWER := 50.0
const HURT_HEAVY_FRACTION := 0.15
const BODY_LARGE_M := 2.5
const BODY_HUGE_M := 6.0
const BREAK_LARGE_M := 3.0
const SPLASH_DEPTH_M := 0.5
const SCREEN_CUE_QUIET_S := 0.12
const POLL_S := 0.25
const DEFAULT_THREAT := {"offscreen_fov_factor": 0.55, "far_m": 20.0, "windup_near_m": 15.0,
	"alert_radius_m": 70.0, "alert_gap_s": 4.0, "flee_gap_s": 2.0, "wall_merge_s": 0.5, "denied_gap_s": 0.5}
const INTERACT_KINDS := {"ItemPickup": "pickup", "WeaponRack": "weapon", "Forge": "forge",
	"UprootTree": "uproot", "NpcTalker": "talk", "LevelExit": "exit", "Inscription": "inscription"}
const FACTION_CUES := {"warned": "sfx.voice.crowd.gasp", "hostile": "sfx.world.alarm_bell",
	"stood_down": "sfx.voice.crowd.murmur", "reconciled": "sfx.voice.crowd.cheer"}
const ENGINE_VISUALS := ["ballista_bolt", "catapult_stone", "engine"]

var audio: Node = null
## Requests waiting for Audio's _process: [{"chain", "at", "opts"}].
var queue: Array = []
## Rigs whose footfall is connected (instance id -> true).
var connected_rigs: Dictionary = {}

var _connected: Array = []        ## [[Signal, Callable]] to disconnect on teardown
var _aware: Dictionary = {}       ## entity id -> aware at the last poll
var _gap: Dictionary = {}         ## throttle key -> clock time of the last cue
var _aim_seen: Dictionary = {}    ## "<actor>:<instance>" -> true (aim-lock cues played)
var _projectiles: Dictionary = {} ## projectile id -> visual
var _wet: Dictionary = {}         ## entity id -> in deep water at the last poll
var _last_poll_s := -INF
var _walk_since_s := -INF
var _last_step_s := -INF
var _screen_cue_s := -INF
var _dialogue_open := false


func setup(p_audio: Node) -> void:
	audio = p_audio
	for sig_name: String in ROUTED_SIGNALS + STATE_SIGNALS:
		if not Events.has_signal(sig_name):
			continue
		var handler := "_on_" + sig_name
		if not has_method(handler):
			continue
		var callable := Callable(self, handler)
		var sig := Signal(Events, sig_name)
		if not sig.is_connected(callable):
			sig.connect(callable)
			_connected.append([sig, callable])
	var vp := get_viewport()
	if vp != null and not vp.gui_focus_changed.is_connected(_on_focus_changed):
		vp.gui_focus_changed.connect(_on_focus_changed)
		_connected.append([vp.gui_focus_changed, Callable(self, "_on_focus_changed")])


func teardown() -> void:
	for pair: Array in _connected:
		var sig: Signal = pair[0]
		if sig.is_connected(pair[1]):
			sig.disconnect(pair[1])
	_connected.clear()
	reset()


func reset() -> void:
	queue.clear()
	_aware.clear()
	_gap.clear()
	_aim_seen.clear()
	_projectiles.clear()
	_wet.clear()
	_last_poll_s = -INF
	_walk_since_s = -INF
	_last_step_s = -INF
	_screen_cue_s = -INF
	_dialogue_open = false


func dialogue_open() -> bool:
	return _dialogue_open


func _now() -> float:
	return float(audio.clock_s) if audio != null else 0.0


func _mix() -> Dictionary:
	return audio.get("mix") as Dictionary


func _threat_cfg(key: String) -> float:
	var t: Variant = _mix().get("threat")
	if typeof(t) == TYPE_DICTIONARY and (t as Dictionary).has(key):
		return float(t[key])
	return float(DEFAULT_THREAT.get(key, 0.0))


## Queues one request: `chain` the cue candidates (most specific first), `at` the position
## (Vector3.INF = non-positional), opts as Audio.play takes them.
func request(chain: Array, at: Vector3, opts: Dictionary = {}) -> void:
	queue.append({"chain": chain, "at": at, "opts": opts})


## Called by Audio every frame: the polls, then every queued request.
func process_frame() -> void:
	var now := _now()
	_poll_aim_locks()
	if now - _last_poll_s >= POLL_S:
		_last_poll_s = now
		_poll_awareness()
		_poll_water()
	var q := queue
	queue = []
	for r: Dictionary in q:
		audio.call("play_request", r.chain, r.at, r.opts)


## True (and the throttle restarts) when `key` last played at least `gap_s` ago.
func _throttle(key: String, gap_s: float) -> bool:
	var now := _now()
	if now - float(_gap.get(key, -INF)) < gap_s - 1e-6:
		return false
	_gap[key] = now
	return true


# --------------------------------------------------------------------------- lookups

func _player() -> GiantPlayer:
	return audio.call("player") as GiantPlayer


func _player_id() -> String:
	var p := _player()
	return p.entity.entity_id if p != null and p.entity != null else ""


func _entity(id: String) -> CombatEntity:
	return Sim.get_entity(id) if id != "" else null


static func _record(e: CombatEntity) -> Dictionary:
	return GameData.get_record(e.definition_id) if e != null else {}


static func _type_of(e: CombatEntity) -> String:
	return str(_record(e).get("type", ""))


func _is_prop(e: CombatEntity) -> bool:
	return _type_of(e) == "prop"


func _is_player(e: CombatEntity) -> bool:
	return e != null and e.actor != null and e.actor.is_in_group("player")


static func _height(e: CombatEntity) -> float:
	return e.combatant.height_m if e != null and e.combatant != null else 1.8


static func _position(e: CombatEntity) -> Vector3:
	return e.actor.global_position if e != null and is_instance_valid(e.actor) and e.actor.is_inside_tree() \
		else Vector3.INF


static func _chest(e: CombatEntity) -> Vector3:
	var p := _position(e)
	return p + Vector3.UP * _height(e) * 0.6 if p != Vector3.INF else p


## The record's voice (audio_mix.voices; default "human").
func voice_of(definition_id: String) -> String:
	var voices: Dictionary = _mix().get("voices", {})
	return str(voices.get(definition_id, "human"))


## The record's material (audio_mix.materials; default "wood").
func material_of(definition_id: String) -> String:
	var materials: Dictionary = _mix().get("materials", {})
	return str(materials.get(definition_id, "wood"))


## The footfall size class of a non-player body: audio_mix.steps, else by archetype (wolf: paw;
## ogre, boss, troll, rival giant: heavy; cavalry: hoof; everything else: human).
func step_class_of(definition_id: String) -> String:
	var steps: Dictionary = _mix().get("steps", {})
	if steps.has(definition_id):
		return str(steps[definition_id])
	match str(GameData.get_record(definition_id).get("archetype", "")):
		"wolf":
			return "paw"
		"ogre", "boss", "troll", "rival_giant":
			return "heavy"
		"cavalry":
			return "hoof"
	return "human"


func _voice_chain(e: CombatEntity, call: String) -> Array:
	var v := voice_of(e.definition_id) if e != null else "human"
	if v == "none":
		return []
	return ["sfx.voice.%s.%s" % [v, call]]


## Queues a voice call of entity `e` (nothing for a voiceless body).
func _voice(e: CombatEntity, call: String, reason: String, priority := 70) -> void:
	var chain := _voice_chain(e, call)
	if chain.is_empty() or e == null:
		return
	request(chain, _chest(e), {"source_height_m": _height(e), "priority": priority, "reason": reason})


## A node (shrine, waystone, interactable, checkpoint) by its id, or null.
func _node_by_id(id: String) -> Node3D:
	if id == "" or audio == null:
		return null
	for group: String in ["shrines", "waystones", "checkpoints", "interactables", "breakables"]:
		for n in audio.get_tree().get_nodes_in_group(group):
			if not (n is Node3D) or not (n as Node3D).is_inside_tree():
				continue
			for key: String in ["world_id", "checkpoint_id", "interact_id", "entity_id", "npc_id"]:
				var v: Variant = n.get(key)
				if typeof(v) == TYPE_STRING and v == id:
					return n as Node3D
	return null


func _node_position(id: String) -> Vector3:
	var e := _entity(id)
	if e != null:
		var p := _position(e)
		if p != Vector3.INF:
			return p
	var n := _node_by_id(id)
	return n.global_position if n != null else Vector3.INF


func _player_pos() -> Vector3:
	var p := _player()
	return p.global_position if p != null else Vector3.INF


func _ui(cue: String, reason: String) -> void:
	request([cue], Vector3.INF, {"reason": reason})


# --------------------------------------------------------------------------- A impacts

func _on_hit_resolved(_tick: int, result: HitResult) -> void:
	var hit := result.event
	if hit == null:
		return
	var target := _entity(hit.target_id)
	var attacker := _entity(hit.attacker_id)
	var at := hit.hit_point if hit.hit_point != Vector3.ZERO else _chest(target)
	var player_side := _is_player(attacker) or _is_player(target)
	var prio := 90 if player_side else 70
	match result.outcome:
		HitResult.Outcome.HIT, HitResult.Outcome.GUARD_BROKEN:
			if _is_prop(target):
				request(["sfx.hit.%s" % material_of(target.definition_id)], at,
					{"priority": 60 if not player_side else prio, "reason": "hit_prop", "source_height_m": _height(target)})
			else:
				var armor := "armor" if target != null and target.combatant.armor_total() >= ARMOR_HEAVY else "flesh"
				request(["sfx.hit.%s.%s" % [armor, _weight(hit)]], at,
					{"priority": prio, "reason": "hit", "source_height_m": _height(target)})
			if result.crit:
				request(["sfx.hit.crit"], at, {"priority": prio, "reason": "crit"})
			if result.outcome == HitResult.Outcome.GUARD_BROKEN:
				request(["sfx.guard_break"], _chest(target), {"priority": 85, "reason": "guard_break"})
			if _is_player(target) and result.health_damage > 0:
				var heavy := float(result.health_damage) >= HURT_HEAVY_FRACTION * target.combatant.pools.health_max
				request(["sfx.player.hurt.heavy", "sfx.player.hurt"] if heavy else ["sfx.player.hurt"],
					_chest(target), {"priority": 100, "reason": "hurt"})
		HitResult.Outcome.BLOCKED:
			request(["sfx.block.player"] if _is_player(target) else ["sfx.block.guard"], _chest(target),
				{"priority": 85, "reason": "block"})
		HitResult.Outcome.PARRIED:
			request(["sfx.parry"], _chest(target), {"priority": 85, "reason": "parry"})
		HitResult.Outcome.IMMUNE:
			request(["sfx.hit.immune"], at, {"priority": 60, "reason": "immune"})
		_:
			pass   # EVADED (the dodge has its own sound), IGNORED
	if result.outcome != HitResult.Outcome.IGNORED and audio.get("music") != null:
		var other: CombatEntity = target if _is_player(attacker) else (attacker if _is_player(target) else null)
		if other != null and other.team == CombatEntity.Team.ENEMY and not _is_prop(other):
			var p := _player()
			var ratio := float(((_mix().get("intensity", {})) as Dictionary).get("lesser_height_ratio", 0.3))
			var counts := AudioMath.threat_counts(_height(other), _height(p.entity) if p != null else 3.66,
				MusicDirector.is_special(other.actor) if other.actor != null else false, ratio)
			audio.music.note_player_hit(counts)


## "heavy" for heavies and for anything over power 50, else "light".
static func _weight(hit: HitEvent) -> String:
	var def := GameData.get_action(hit.action_id)
	if def != null and (def.kind == "heavy" or def.power > HEAVY_POWER):
		return "heavy"
	return "light"


func _on_attack_clanked(_tick: int, _actor_id: String, _instance_id: int, point: Vector3) -> void:
	request(["sfx.clank.stone"], point, {"priority": 60, "reason": "clank"})


# --------------------------------------------------------------------------- B swings and movement, D abilities

func _on_ability_started(_tick: int, actor_id: String, action_id: String, _instance_id: int) -> void:
	var e := _entity(actor_id)
	var def := GameData.get_action(action_id)
	if e == null or def == null:
		return
	if _is_player(e):
		_player_action(e, def)
		return
	if def.kind == "enemy_attack" or def.is_attack():
		_voice(e, "attack", "attack")
		if def.hit_shape == "weapon_arc":
			var weapon: Variant = e.actor.get("weapon")
			var fam := str(SWING_FAMILIES.get(str((weapon as Dictionary).get("family", "")), "")) \
				if typeof(weapon) == TYPE_DICTIONARY else ""
			if fam != "":
				request(["sfx.swing.%s.%s" % [fam, "heavy" if def.power > HEAVY_POWER else "light"]], _chest(e),
					{"priority": 70, "reason": "swing", "source_height_m": _height(e)})
		if def.has_tag("Charge") and str(_record(e).get("archetype", "")) == "cavalry":
			request(["sfx.cavalry.charge"], _chest(e), {"priority": 75, "reason": "charge"})


func _player_action(e: CombatEntity, def: ActionDef) -> void:
	var p := e.actor as GiantPlayer
	var pivot := _chest(e)
	if p != null:
		pivot = p.global_transform * p.weapon_pivot
	match def.kind:
		"light", "heavy":
			var weapon: Dictionary = p.weapon if p != null else {}
			var fam := str(SWING_FAMILIES.get(str(weapon.get("family", "club")), "blunt"))
			request(["sfx.swing.%s.%s" % [fam, def.kind]], pivot, {"priority": 90, "reason": "swing"})
		"dodge":
			var style := str(p.profile.get("dodge_style", "roll")) if p != null else "roll"
			request(["sfx.dodge.%s" % style], _position(e), {"priority": 90, "reason": "dodge"})
		"block":
			request(["sfx.block.raise"], pivot, {"priority": 85, "reason": "block_raise"})
		"jump":
			_walk_since_s = -INF
			request(["sfx.jump"], _position(e), {"priority": 90, "reason": "jump"})
		"ability", "ultimate":
			var short := AudioMath.short_id(def.id)
			request(["sfx.ability.%s.cast" % short, "sfx.ability.default.cast"], _chest(e),
				{"priority": 90, "reason": "cast"})


func _on_area_pulse(_tick: int, actor_id: String, action_id: String, center: Vector3, _radius: float) -> void:
	var e := _entity(actor_id)
	var short := AudioMath.short_id(action_id)
	request(["sfx.ability.%s.impact" % short, "sfx.impact.stomp"], center,
		{"priority": 90 if _is_player(e) else 80, "reason": "pulse", "source_height_m": _height(e)})
	if _is_player(e):
		_walk_since_s = -INF   # a stomp: back to the full footfall
		if audio.get("ambience") != null:
			audio.ambience.on_giant_impact(center)


func _on_ability_effect(_tick: int, actor_id: String, action_id: String, kind: String, center: Vector3,
		_radius: float, _yaw: float, _arc_deg: float) -> void:
	var suffix := str({"sector": "sweep", "roar": "roar", "self_buff": "on", "cast": "cast"}.get(kind, ""))
	if suffix == "":
		return   # aim_preview: a preview, not an effect
	var e := _entity(actor_id)
	var at := center if center != Vector3.ZERO else _chest(e)
	if kind in ["roar", "self_buff"]:
		at = _chest(e)
	var chain: Array = ["sfx.ability.%s.%s" % [AudioMath.short_id(action_id), suffix]]
	if kind == "roar" and e != null:
		var v := "giant" if _is_player(e) else voice_of(e.definition_id)
		if v != "none":
			chain.append("sfx.voice.%s.roar" % v)
	request(chain, at, {"priority": 90 if _is_player(e) else 75, "reason": "effect", "source_height_m": _height(e)})


func _on_status_applied(_tick: int, entity_id: String, status_id: String, _source_id: String, _duration_s: float) -> void:
	var e := _entity(entity_id)
	if e == null:
		return
	var tags: Array = GameData.get_record(status_id).get("tags", [])
	if _is_player(e) and tags.has("Slow"):
		request(["sfx.status.slow"], _chest(e), {"priority": 80, "reason": "status"})
	elif status_id.ends_with("burning") or tags.has("Burning"):
		request(["sfx.status.burning"], _chest(e), {"priority": 60, "reason": "status"})
	elif tags.has("Regeneration") and str(_record(e).get("archetype", "")) == "troll":
		request(["sfx.troll.regrow"], _chest(e), {"priority": 60, "reason": "status"})


func _on_status_expired(_tick: int, entity_id: String, status_id: String) -> void:
	var e := _entity(entity_id)
	if e == null or not _is_player(e):
		return
	var tags: Array = GameData.get_record(status_id).get("tags", [])
	if tags.has("Buff") and not status_id.begins_with("status.debug") and not status_id.begins_with("status.bot"):
		request(["sfx.status.%s.off" % AudioMath.short_id(status_id)], _chest(e), {"priority": 80, "reason": "status_off"})


func _on_projectile_spawned(_tick: int, projectile_id: int, owner_id: String, _action_id: String,
		position: Vector3, _velocity: Vector3, visual: String) -> void:
	_projectiles[projectile_id] = visual
	if _projectiles.size() > 256:
		_projectiles.erase(_projectiles.keys()[0])
	var e := _entity(owner_id)
	var prio := 90 if _is_player(e) else (95 if ENGINE_VISUALS.has(visual) else 70)
	request(["sfx.projectile.%s.launch" % visual], position, {"priority": prio, "reason": "launch"})


func _on_projectile_impact(_tick: int, projectile_id: int, position: Vector3, hit_entity_id: String) -> void:
	var visual := str(_projectiles.get(projectile_id, ""))
	_projectiles.erase(projectile_id)
	if hit_entity_id != "" or visual == "":
		return   # a hit on an entity sounds through hit_resolved
	request(["sfx.impact.%s" % visual], position, {"priority": 70, "reason": "impact"})


func _on_grab_started(_tick: int, holder_id: String, _target_id: String) -> void:
	request(["sfx.grab.seize"], _chest(_entity(holder_id)), {"priority": 90, "reason": "grab"})


func _on_grab_ended(_tick: int, holder_id: String, _target_id: String, reason: String) -> void:
	var cue := str({"thrown": "sfx.grab.throw", "dropped": "sfx.grab.drop", "crushed": "sfx.grab.crush"}.get(reason, ""))
	if cue != "":
		request([cue], _chest(_entity(holder_id)), {"priority": 90, "reason": "grab_" + reason})


# --------------------------------------------------------------------------- E voices

func _on_entity_died(_tick: int, entity_id: String, _killer_id: String) -> void:
	var e := _entity(entity_id)
	if e == null or _is_prop(e):
		return
	if _is_player(e):
		if audio.get("music") != null:
			audio.music.on_player_died()
		request(["sfx.player.death"], _chest(e), {"priority": 100, "reason": "death"})
		return
	_voice(e, "death", "death")
	var h := _height(e)
	var size := "huge" if h >= BODY_HUGE_M else ("large" if h >= BODY_LARGE_M else "small")
	request(["sfx.body.fall.%s" % size], _position(e), {"priority": 60, "reason": "fall", "source_height_m": h})


func _on_staggered(_tick: int, entity_id: String, _duration_s: float, _reason: String) -> void:
	var e := _entity(entity_id)
	if e == null or _is_prop(e):
		return
	if _is_player(e):
		request(["sfx.player.stagger"], _chest(e), {"priority": 100, "reason": "stagger"})
	else:
		_voice(e, "stagger", "stagger")


func _on_morale_changed(_tick: int, entity_id: String, _morale: float, _delta: float, reason: String) -> void:
	if reason == "awe":
		_voice(_entity(entity_id), "awe", "awe")


func _on_enemy_routed(_tick: int, entity_id: String, encounter_id: String) -> void:
	var key := "flee:" + (encounter_id if encounter_id != "" else entity_id)
	if _throttle(key, _threat_cfg("flee_gap_s")):
		_voice(_entity(entity_id), "flee", "flee")


func _on_dialogue_started(_tick: int, _dialogue_id: String, npc_id: String) -> void:
	_dialogue_open = true
	var e := _entity(npc_id)
	var at := _chest(e)
	var voice := "talker"
	if e != null:
		voice = voice_of(e.definition_id)
	else:
		var n := _node_by_id(npc_id)
		at = n.global_position + Vector3.UP * 1.5 if n != null else Vector3.INF
		var npc_rec := GameData.get_record(npc_id)
		if not npc_rec.is_empty():
			voice = voice_of(npc_id)
	if voice != "none":
		request(["sfx.voice.%s.greet" % voice], at, {"priority": 70, "reason": "greet"})


func _on_dialogue_outcome(_tick: int, _dialogue_id: String, outcome: String) -> void:
	if outcome == "intimidate":
		request(["sfx.voice.giant.intimidate"], _player_pos() + Vector3.UP * 3.0, {"priority": 90, "reason": "intimidate"})


func _on_dialogue_ended(_tick: int, _dialogue_id: String) -> void:
	_dialogue_open = false


func _on_faction_changed(_tick: int, faction: String, state: String) -> void:
	var cue := str(FACTION_CUES.get(state, ""))
	if cue == "":
		return
	request([cue], _nearest_member(faction), {"priority": 70, "reason": "faction"})


## The position of the faction member nearest the giant (the giant's own when none is near).
func _nearest_member(faction: String) -> Vector3:
	var ppos := _player_pos()
	var best := Vector3.INF
	var best_d := INF
	for group: String in ["npcs", "enemies", "civilians"]:
		for n in audio.get_tree().get_nodes_in_group(group):
			if not (n is Node3D) or str(n.get("faction")) != faction:
				continue
			var d := (n as Node3D).global_position.distance_to(ppos) if ppos != Vector3.INF else 0.0
			if d < best_d:
				best_d = d
				best = (n as Node3D).global_position + Vector3.UP * 1.5
	return best if best != Vector3.INF else ppos


# --------------------------------------------------------------------------- F threat cues

func _on_telegraph_started(_tick: int, actor_id: String, action_id: String, target_id: String, shape: String,
		origin: Vector3, _yaw: float, _radius: float, _length: float, _duration_s: float) -> void:
	var p := _player()
	if p == null or p.entity == null:
		return
	var attacker := _entity(actor_id)
	var def := GameData.get_action(action_id)
	var src := _chest(attacker) if attacker != null else origin
	if src == Vector3.INF:
		src = origin
	# a formation's band brace: one wall cue per formation per brace cycle
	if def != null and def.hit_shape == "band_pulse":
		var fid := _formation_of(attacker, actor_id)
		if _throttle("wall:" + fid, _threat_cfg("wall_merge_s")):
			request(["sfx.threat.windup.wall"], src, {"priority": 100, "reason": "brace"})
			audio.music.note_telegraph()
		return
	if target_id != p.entity.entity_id:
		return
	audio.music.note_telegraph()
	var scale := float(audio.call("distance_scale"))
	var dist := src.distance_to(p.global_position)
	var prio := 80 if dist <= _threat_cfg("windup_near_m") * scale else 70
	request(["sfx.threat.windup.%s" % shape], src, {"priority": prio, "reason": "windup"})
	if def != null and bool(def.param("indirect", false)):
		request(["sfx.threat.incoming"], origin, {"priority": 100, "reason": "incoming"})
	if threat_wants_sting(src, dist, scale):
		var opts := {"priority": 100, "reason": "sting", "max_health": p.entity.combatant.pools.health_max,
			"expected_damage": INF, "poise_ratio": 1.0}
		if attacker != null and def != null:
			var weapon: Variant = attacker.actor.get("weapon") if attacker.actor != null else {}
			opts.expected_damage = AudioMath.expected_damage(def, attacker.combatant,
				weapon if typeof(weapon) == TYPE_DICTIONARY else {}, p.entity.combatant)
			opts.poise_ratio = CombatRules.poise_scale(_height(attacker), _height(p.entity))
		request(["sfx.threat.sting"], src, opts)


## True when a threat at `src` (dist metres from the giant) is off camera or far (decision 7):
## outside offscreen_fov_factor x the camera's field of view, or beyond far_m x the scale.
func threat_wants_sting(src: Vector3, dist: float, scale: float) -> bool:
	if dist > _threat_cfg("far_m") * scale:
		return true
	var cam: Camera3D = null
	var p := _player()
	if p != null and p.camera_rig != null:
		cam = p.camera_rig.camera
	if cam == null and audio.get_viewport() != null:
		cam = audio.get_viewport().get_camera_3d()
	if cam == null or not cam.is_inside_tree():
		return false
	return AudioMath.off_camera(cam.global_position, -cam.global_basis.z, src, cam.fov,
		_threat_cfg("offscreen_fov_factor"))


func _formation_of(e: CombatEntity, actor_id: String) -> String:
	if e != null and e.actor != null:
		for key in ["formation_id", "encounter_id"]:
			var v: Variant = e.actor.get(key)
			if typeof(v) == TYPE_STRING and v != "":
				return v
	return actor_id


## Ranged aim commits (decision 24 of M2-M5): when a projectile action's windup passes
## tracking_fraction, the aim is locked: sfx.threat.aim_lock at the attacker, once per shot.
func _poll_aim_locks() -> void:
	var pid := _player_id()
	if pid == "":
		return
	for n in audio.get_tree().get_nodes_in_group(EnemyActor.RANGED_GROUP):
		var actor := n as EnemyActor
		if actor == null or actor.controller == null or actor.brain == null:
			continue
		var a := actor.controller.action
		if a == null or a.hit_shape != "projectile" or actor.controller.phase() != ActionDef.Phase.WINDUP:
			continue
		if actor.brain.target_id != pid or actor.controller.elapsed < EnemyActor.aim_lock_tick(a):
			continue
		var key := "%s:%d" % [actor.entity.entity_id, actor.controller.instance_id]
		if _aim_seen.has(key):
			continue
		_aim_seen[key] = true
		if _aim_seen.size() > 128:
			_aim_seen.erase(_aim_seen.keys()[0])
		request(["sfx.threat.aim_lock"], _chest(actor.entity), {"priority": 100, "reason": "aim_lock"})


## Awareness edges of enemies near the giant: one alert bark per encounter per alert_gap_s.
func _poll_awareness() -> void:
	var ppos := _player_pos()
	if ppos == Vector3.INF:
		_aware.clear()
		return
	var radius := _threat_cfg("alert_radius_m") * float(audio.call("distance_scale"))
	var seen := {}
	for n in audio.get_tree().get_nodes_in_group("enemies"):
		var actor := n as EnemyActor
		if actor == null or actor.brain == null or actor.entity == null or not actor.entity.is_alive():
			continue
		var id := actor.entity.entity_id
		var aware := actor.brain.aware
		seen[id] = aware
		if aware and not bool(_aware.get(id, true)) and actor.global_position.distance_to(ppos) <= radius:
			var key := "alert:" + (actor.encounter_id if actor.encounter_id != "" else id)
			if _throttle(key, _threat_cfg("alert_gap_s")):
				_voice(actor.entity, "alert", "alert")
	_aware = seen


## Water entries (when the level answers water_at): the giant or a heavy body entering water
## deeper than 0.5 m splashes.
func _poll_water() -> void:
	var lv: Node = audio.call("level_node")
	if lv == null or not lv.has_method("water_at"):
		return
	var bodies: Array = []
	var p := _player()
	if p != null and p.entity != null:
		bodies.append(p.entity)
	for n in audio.get_tree().get_nodes_in_group("enemies"):
		var e: Variant = n.get("entity")
		if e is CombatEntity and step_class_of((e as CombatEntity).definition_id) == "heavy":
			bodies.append(e)
	for e: CombatEntity in bodies:
		var pos := _position(e)
		if pos == Vector3.INF:
			continue
		var depth := float(audio.call("water_depth_at", pos))
		var wet := depth > SPLASH_DEPTH_M
		if wet and not bool(_wet.get(e.entity_id, false)):
			var size := "large" if _height(e) >= BREAK_LARGE_M else "small"
			request(["sfx.world.splash.%s" % size], pos, {"priority": 60, "reason": "splash", "source_height_m": _height(e)})
		_wet[e.entity_id] = wet


# --------------------------------------------------------------------------- G world objects

func _prop_material(world_id: String) -> String:
	var e := _entity(world_id)
	if e != null:
		return material_of(e.definition_id)
	var n := _node_by_id(world_id)
	var pid: Variant = n.get("prop_id") if n != null else null
	return material_of(str(pid)) if typeof(pid) == TYPE_STRING else "wood"


func _prop_height(world_id: String) -> float:
	var e := _entity(world_id)
	if e != null:
		return float(_record(e).get("height_m", _height(e)))
	return 1.0


func _on_object_stage_changed(_tick: int, world_id: String, _stage_index: int, _stage_id: String) -> void:
	request(["sfx.crack.%s" % _prop_material(world_id)], _node_position(world_id), {"priority": 60, "reason": "crack"})


func _on_object_destroyed(_tick: int, world_id: String, _by_entity_id: String) -> void:
	var size := "large" if _prop_height(world_id) >= BREAK_LARGE_M else "small"
	request(["sfx.break.%s.%s" % [_prop_material(world_id), size]], _node_position(world_id),
		{"priority": 60, "reason": "break", "source_height_m": _prop_height(world_id)})


func _on_object_opened(_tick: int, world_id: String, _reason: String) -> void:
	request(["sfx.world.open.%s" % _prop_material(world_id)], _node_position(world_id), {"priority": 60, "reason": "open"})


func _on_growth_changed(_tick: int, entity_id: String, _old_stage: int, _new_stage: int) -> void:
	var e := _entity(entity_id)
	if not _is_player(e):
		return
	if audio.get("music") != null:
		audio.music.play_stinger("mus.stinger.growth", 80)
	request(["sfx.world.growth"], _position(e), {"priority": 90, "reason": "growth"})


func _on_shrine_activated(_tick: int, shrine_id: String) -> void:
	request(["sfx.world.shrine_wake"], _node_position(shrine_id), {"priority": 60, "reason": "shrine"})


func _on_shrine_rested(_tick: int, shrine_id: String) -> void:
	request(["sfx.world.shrine_rest"], _node_position(shrine_id), {"priority": 60, "reason": "rest"})


func _on_checkpoint_reached(_tick: int, checkpoint_id: String, kind: String) -> void:
	if kind == "waystone":
		request(["sfx.world.waystone"], _node_position(checkpoint_id), {"priority": 60, "reason": "waystone"})


func _on_interacted(_tick: int, _actor_id: String, interact_id: String) -> void:
	var n := _node_by_id(interact_id)
	if n == null or n is Shrine or n is Waystone:
		return   # shrines and waystones sound through their own events
	var script := n.get_script() as Script
	var kind := ""
	while script != null and kind == "":
		kind = str(INTERACT_KINDS.get(str(script.get_global_name()), ""))
		script = script.get_base_script()
	if kind == "":
		return
	request(["sfx.world.interact.%s" % kind], n.global_position + Vector3.UP, {"priority": 60, "reason": "interact"})


func _on_upgrade_applied(_tick: int, _from_weapon: String, _to_weapon: String) -> void:
	request(["sfx.world.forge_upgrade"], _player_pos(), {"priority": 60, "reason": "upgrade"})


func _on_boss_engaged(_tick: int, boss_id: String) -> void:
	audio.music.on_boss_engaged(boss_id)
	var arena: Node3D = null
	for n in audio.get_tree().get_nodes_in_group(BossArena.GROUP):
		if n is BossArena and (n as BossArena).boss_id == boss_id:
			arena = n
	if arena != null and arena.gate != null:
		request(["sfx.world.gate_iron"], arena.gate.global_position, {"priority": 60, "reason": "arena_gate"})


func _on_boss_phase_changed(_tick: int, boss_id: String, phase: int) -> void:
	audio.music.on_boss_phase_changed(boss_id, phase)


func _on_boss_defeated(_tick: int, boss_id: String) -> void:
	audio.music.on_boss_finished(boss_id, "victory")


func _on_slice_completed(_tick: int) -> void:
	audio.music.on_slice_completed()


# --------------------------------------------------------------------------- H interface

func _on_action_rejected(_tick: int, actor_id: String, _action_id: String, _reason: String) -> void:
	if actor_id == _player_id() and _throttle("denied", _threat_cfg("denied_gap_s")):
		_ui("sfx.ui.denied", "rejected")


func _on_growth_blocked(_tick: int, _entity_id: String, _reason: String, _message: String) -> void:
	if _throttle("denied", _threat_cfg("denied_gap_s")):
		_ui("sfx.ui.denied", "growth_blocked")


func _on_checkpoint_saved(_tick: int, _checkpoint_id: String, ok: bool, _message: String) -> void:
	if ok:
		_ui("sfx.ui.saved", "saved")


func _on_loot_awarded(_tick: int, _world_id: String, _item_id: String, _count: int, _recipient_id: String) -> void:
	_ui("sfx.ui.loot", "loot")


func _on_item_added(_tick: int, item_id: String, _count: int, _source: String) -> void:
	var rec := GameData.get_record(item_id)
	var chain: Array = ["sfx.ui.item"]
	if str(rec.get("category", "")) == "quest":
		chain = ["sfx.ui.item.quest", "sfx.ui.item"]
	elif item_id.contains("iron"):
		chain = ["sfx.ui.item.metal", "sfx.ui.item"]
	request(chain, Vector3.INF, {"reason": "item"})


func _on_weapon_equipped(_tick: int, entity_id: String, weapon_id: String) -> void:
	if entity_id != _player_id():
		return
	var fam := str(GameData.get_record(weapon_id).get("family", ""))
	request(["sfx.ui.equip.%s" % fam, "sfx.ui.equip"], Vector3.INF, {"reason": "equip"})


func _on_level_changed(_tick: int, _old_level: int, _new_level: int) -> void:
	audio.music.play_stinger("mus.stinger.level_up", 80)


func _on_ability_learned(_tick: int, _action_id: String, _slot_key: String) -> void:
	_ui("sfx.ui.ability_learned", "learned")


func _on_attributes_changed(_tick: int) -> void:
	_ui("sfx.ui.select", "attributes")


func _on_loadout_changed(_tick: int, entity_id: String) -> void:
	if entity_id == _player_id():
		_ui("sfx.ui.select", "loadout")


func _on_quest_started(_tick: int, _quest_id: String) -> void:
	_ui("sfx.ui.quest_new", "quest")


func _on_quest_stage_changed(_tick: int, _quest_id: String, _stage_id: String) -> void:
	audio.music.play_stinger("mus.stinger.quest", 60)


func _on_quest_completed(_tick: int, _quest_id: String) -> void:
	audio.music.play_stinger("mus.stinger.quest_complete", 70)


func _on_tutorial_shown(_tick: int, _prompt_id: String) -> void:
	_ui("sfx.ui.tip", "tip")


func _on_lock_target_changed(actor_id: String, target_id: String, _reason: String) -> void:
	if actor_id != _player_id():
		return
	_ui("sfx.ui.lock_off" if target_id == "" else "sfx.ui.lock_on", "lock")


func _on_camera_mode_changed(_mode: int) -> void:
	_ui("sfx.ui.camera", "camera")


func _on_hud_message(_text: String, kind: String) -> void:
	if kind in ["warn", "bad"]:
		_ui("sfx.ui.warn", "warn")


## A node joined the tree (Audio's node_added): rigs get their footfalls wired, screens their
## open and close cues.
func on_node_added(node: Node) -> void:
	if node is ActorRig or (node is QuadrupedRig and node.has_signal(&"footfall")):
		var id := node.get_instance_id()
		if not connected_rigs.has(id):
			connected_rigs[id] = true
			node.connect(&"footfall", _on_footfall.bind(node))
			node.tree_exiting.connect(_on_rig_exiting.bind(id), CONNECT_ONE_SHOT)
	elif node is UiScreen:
		var screen := node as UiScreen
		if not screen.closed.is_connected(_on_screen_closed):
			screen.closed.connect(_on_screen_closed.bind(screen.screen_name))
		_screen_cue_s = _now()
		_ui("sfx.ui.map_open" if screen.screen_name == "map" else "sfx.ui.open", "screen_open")


func _on_rig_exiting(id: int) -> void:
	connected_rigs.erase(id)


func _on_screen_closed(_result: Dictionary, _screen_name: String) -> void:
	_screen_cue_s = _now()
	_ui("sfx.ui.close", "screen_close")


func _screen_open() -> bool:
	for n in audio.get_tree().get_nodes_in_group(ScreenStack.GROUP):
		var s := n as ScreenStack
		if s != null and s.any_open():
			return true
	return false


func _on_focus_changed(_control: Control) -> void:
	if _now() - _screen_cue_s < SCREEN_CUE_QUIET_S or not _screen_open():
		return
	_ui("sfx.ui.move", "focus")


## Audio's _input: accept and cancel while a screen is open.
func on_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventJoypadButton) or not event.is_pressed() or event.is_echo():
		return
	if not _screen_open():
		return
	if event.is_action_pressed("ui_accept"):
		_ui("sfx.ui.select", "accept")
	elif event.is_action_pressed("ui_cancel"):
		_ui("sfx.ui.back", "cancel")


# --------------------------------------------------------------------------- C footfalls

func _on_footfall(rig: Node) -> void:
	if not is_instance_valid(rig) or audio == null:
		return
	var actor := rig.get("actor") as Node3D
	if actor == null:
		actor = rig.get_parent() as Node3D
		while actor != null and actor.get("entity") == null:
			actor = actor.get_parent() as Node3D
	if actor == null or not actor.is_inside_tree():
		return
	var e: Variant = actor.get("entity")
	if not (e is CombatEntity):
		return
	if actor is GiantPlayer:
		_player_footfall(actor as GiantPlayer)
	else:
		_actor_footfall(e as CombatEntity, actor)


func _player_footfall(p: GiantPlayer) -> void:
	var now := _now()
	var cfg: Dictionary = _mix().get("footfall", {})
	if now - _last_step_s > float(cfg.get("stop_gap_s", 0.9)) or audio.music.intensity == AudioMath.COMBAT:
		_walk_since_s = now   # stopped (or fighting): a new walk starts
	_last_step_s = now
	var pos := p.global_position
	var surface := str(audio.call("surface_at", pos))
	if float(audio.call("water_depth_at", pos)) > 0.05:
		surface = "wade"
	var base := "sfx.step.giant_s%d.%s" % [clampi(p.growth_stage, 1, 10), surface]
	var cruising := now - _walk_since_s >= float(cfg.get("cruise_after_s", 10.0))
	var opts := {"priority": 45 if cruising else 50, "reason": "cruise" if cruising else "step"}
	if cruising:
		opts["volume_db"] = float(cfg.get("cruise_duck_db", -5.0))
	request([base + ".cruise", base] if cruising else [base], pos, opts)
	if audio.get("ambience") != null:
		audio.ambience.on_giant_impact(pos)


func _actor_footfall(e: CombatEntity, actor: Node3D) -> void:
	if not e.is_alive():
		return
	var size := step_class_of(e.definition_id)
	var pos := actor.global_position
	var surface := str(audio.call("surface_at", pos))
	if size == "heavy" and float(audio.call("water_depth_at", pos)) > 0.05:
		surface = "wade"
	request(["sfx.step.%s.%s" % [size, surface]], pos, {"priority": 40, "reason": "step",
		"source_height_m": _height(e)})


## Starts the player's walk anew (tests: the cruise rule's clock).
func set_walk_started(seconds_ago: float) -> void:
	_walk_since_s = _now() - seconds_ago
	_last_step_s = _now()


# --------------------------------------------------------------------------- M7-M9 rows (P20's signals; P28 tests them)

func _arg(args: Array, i: int, fallback: Variant = "") -> Variant:
	return args[i] if i < args.size() else fallback


func _on_poi_discovered(...args: Array) -> void:
	audio.music.note_event()
	var poi := str(_arg(args, 1))
	var kind := str(GameData.get_record(poi).get("kind", ""))
	audio.music.play_stinger("mus.stinger.world_reveal" if kind == "vista" else "mus.stinger.discovery", 70)


func _on_region_changed(..._args: Array) -> void:
	audio.music.note_event()


func _on_level_leaving(..._args: Array) -> void:
	audio.music.fade_to_silence(MusicDirector.LEVEL_FADE_S)


func _on_level_entered(..._args: Array) -> void:
	audio.music.note_event()


func _on_travel_requested(...args: Array) -> void:
	if str(_arg(args, 2)) == "fast_travel":
		_ui("sfx.ui.travel", "travel")


func _on_size_gate_blocked(...args: Array) -> void:
	var gate_id := str(_arg(args, 1))
	var kind := "stone"
	var n := _node_by_id(gate_id)
	if n != null and typeof(n.get("material")) == TYPE_STRING:
		kind = str(n.get("material"))
	request(["sfx.gate.%s" % kind], _node_position(gate_id) if n != null else _player_pos(),
		{"priority": 60, "reason": "size_gate"})


func _on_trampled(...args: Array) -> void:
	var world_id := str(_arg(args, 1))
	var at := _node_position(world_id)
	request(["sfx.trample"], at, {"priority": 60, "reason": "trample"})
	request(["sfx.break.%s.small" % _prop_material(world_id)], at, {"priority": 60, "reason": "trample"})


func _on_formation_changed(...args: Array) -> void:
	var fid := str(_arg(args, 1))
	var state := str(_arg(args, 2))
	var at := _formation_anchor(fid)
	match state:
		"braced":
			request(["sfx.formation.brace"], at, {"priority": 75, "reason": "formation"})
		"broken":
			request(["sfx.formation.horn_broken"], at, {"priority": 75, "reason": "formation"})
		"banner_fell":
			request(["sfx.formation.banner_fall"], at, {"priority": 75, "reason": "formation"})
		"routed":
			request(["sfx.voice.crowd.flee"], at, {"priority": 75, "reason": "formation"})
			audio.music.play_stinger("mus.stinger.rout", 70)


## A formation's anchor: the mean position of the enemies carrying its formation_id.
func _formation_anchor(fid: String) -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for node in audio.get_tree().get_nodes_in_group("enemies"):
		if node is Node3D and str(node.get("formation_id")) == fid:
			sum += (node as Node3D).global_position
			n += 1
	return sum / n if n > 0 else _player_pos()


func _on_siege_engine_fired(...args: Array) -> void:
	var engine_id := str(_arg(args, 1))
	var kind := "catapult" if engine_id.contains("catapult") else "ballista"
	request(["sfx.siege.%s.fire" % kind], _node_position(engine_id), {"priority": 95, "reason": "siege"})


func _on_siege_engine_crewed(...args: Array) -> void:
	if not bool(_arg(args, 2, true)):
		request(["sfx.voice.crowd.abandon"], _node_position(str(_arg(args, 1))), {"priority": 70, "reason": "siege"})


func _on_boss_yielded(...args: Array) -> void:
	audio.music.on_boss_finished(str(_arg(args, 1)), "yield")


func _on_boss_disengaged(...args: Array) -> void:
	audio.music.on_boss_finished(str(_arg(args, 1)), "yield" if str(_arg(args, 2)) == "fled" else "")


func _on_ability_evolved(..._args: Array) -> void:
	_ui("sfx.ui.ability_learned", "evolved")


func _on_talent_learned(..._args: Array) -> void:
	_ui("sfx.ui.ability_learned", "talent")


func _on_ancestry_chosen(..._args: Array) -> void:
	audio.music.play_stinger("mus.stinger.ancestry", 80)


func _on_world_event_started(...args: Array) -> void:
	var event_id := str(_arg(args, 1))
	var rec := GameData.get_record(event_id)
	var c: Variant = rec.get("center_m")
	var at := Vector3(float(c[0]), float(c[1]), float(c[2])) if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3 \
		else _player_pos()
	request(["sfx.world.horn_alarm"], at, {"priority": 70, "reason": "world_event"})


func _on_world_event_ended(...args: Array) -> void:
	var event_id := str(_arg(args, 1))
	var outcome := str(_arg(args, 2))
	var rec := GameData.get_record(event_id)
	var defended := str(rec.get("success_outcome", rec.get("defended_outcome", "defended")))
	if outcome == defended:
		audio.music.play_stinger("mus.stinger.quest_complete", 70)
