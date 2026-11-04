class_name GiantPlayer
extends CharacterBody3D
## The player-controlled giant (stage 1: 12 ft / 3.66 m).
##
## Glue only: input intents -> CombatController requests; controller state -> movement,
## weapon sweeps and pulses, lock-on, camera and the procedural rig. Stepped by Sim at 60 Hz
## via sim_step(). The behaviour lives in components (plan §2.7.1): PlayerMotor (sprint,
## facing, movement), PlayerTargeting (lock-on, soft targeting), PlayerAttack (geometry, hit
## queries through AttackRunner + HitFactory) and PlayerInteract (the E key). Later packages
## add their component files to COMPONENTS' pre-declared paths; a path whose file does not
## exist yet is skipped silently.
##
## The public fields below are the actor's shared state; tests, the HUD, the camera, the rig
## and the autopilot read them, and the components write them.

const GRAVITY := 22.0
const KNOCKBACK_DECEL := 28.0
const OUT_OF_WORLD_Y := -30.0
const SOFT_TARGET_CONE_DEG := 45.0

## [name, path]: every planned component. Missing files are skipped (ResourceLoader.exists).
const COMPONENTS := [
	["motor", "res://scripts/actors/player/player_motor.gd"],              # P02
	["targeting", "res://scripts/actors/player/player_targeting.gd"],      # P02
	["attack", "res://scripts/actors/player/player_attack.gd"],            # P02
	["interact", "res://scripts/actors/player/player_interact.gd"],        # P02
	["growth", "res://scripts/actors/player/player_growth.gd"],            # P05
	["equipment", "res://scripts/actors/player/player_equipment.gd"],      # P08
	["grab", "res://scripts/actors/player/player_grab.gd"],                # P07
	["progression", "res://scripts/actors/player/player_progression.gd"],  # P12
]
## apply_character_state order: these first (when present), then every other component in
## COMPONENTS order, then the core keys (loadout, known abilities, level, resources last).
const STATE_ORDER := ["growth", "progression", "equipment"]
const SLOT_KEYS := ["slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6", "slot_7", "slot_8", "ultimate"]
const ACTION_EDGES := [&"light", &"heavy", &"dodge", &"jump", &"block_press", &"block_release", &"ultimate"]

@export var definition_id := "player.giant"

@onready var entity: CombatEntity = $CombatEntity
@onready var camera_rig: CameraRig = $CameraRig
@onready var rig: ActorRig = $Visual
@onready var body_shape: CollisionShape3D = $BodyShape

var router: InputRouter
var controller: CombatController
var lock := LockOnTracker.new()
var record: Dictionary = {}
var profile: Dictionary = {}
var weapon: Dictionary = {}
var sprint_def: ActionDef
var growth_stage := 1
var facing_yaw := 0.0
var sprinting := false
var sprint_toggled := false
var move_velocity := Vector3.ZERO
var knockback_velocity := Vector3.ZERO
var dodge_direction := Vector3.ZERO
var last_intents: Dictionary = {}
var spawn_transform := Transform3D.IDENTITY
var weapon_pivot := Vector3(0.82, 2.9, 0.0)
var attack_origin := Vector3(0.0, 2.6, 0.0)
var arm_length := 1.5
var weapon_length := 1.85
var weapon_radius := 0.45
var stats := {"attacks": 0, "hits_landed": 0, "deaths": 0, "parries": 0, "kills": 0}
## Abilities this character has learned (save data); the loadout slots draw from them.
var known_abilities: Array[String] = []

## Components that always exist (typed) ...
var motor: PlayerMotor
var targeting: PlayerTargeting
var attack: PlayerAttack
var interact: PlayerInteract
## ... and those whose packages may not have landed yet (untyped, null until they exist).
var growth = null
var equipment = null
var grab = null
var progression = null

## The weapon segment of the previous tick (lives in the attack runner).
var prev_segment: PackedVector3Array:
	get:
		return attack.runner.prev_segment if attack != null else PackedVector3Array()
	set(value):
		if attack != null:
			attack.runner.prev_segment = value

var _components: Array[PlayerComponent] = []      ## registration (COMPONENTS) order
var _by_name: Dictionary = {}                     ## StringName -> PlayerComponent
var _edge_order: Array[PlayerComponent] = []      ## sorted by edge_priority, stable
var _state_passthrough: Dictionary = {}           ## last applied character state


func _ready() -> void:
	add_to_group("player")
	record = GameData.get_record(definition_id)
	profile = GameData.get_record(str(record.get("growth_profile", "growth.01")))
	weapon = GameData.get_record(str(record.get("weapon", "weapon.club")))
	growth_stage = int(profile.get("stage", 1))
	_build_controller()
	router = InputRouter.new()
	router.name = "InputRouter"
	add_child(router)
	known_abilities = _initial_known_abilities()
	load_components(COMPONENTS)
	_apply_profile()
	facing_yaw = rotation.y
	camera_rig.yaw = facing_yaw
	camera_rig.setup(self, profile)
	rig.set_weapon_pivot(weapon_pivot)
	spawn_transform = global_transform
	entity.hit_landed.connect(_on_hit_landed)
	entity.hit_taken.connect(_on_hit_taken)
	Events.entity_died.connect(_on_any_entity_died)
	Sim.register_actor(entity.entity_id, self)


func _exit_tree() -> void:
	for c in _components:
		c.on_exit()
	Sim.unregister_actor(entity.entity_id, self)


func _build_controller() -> void:
	controller = CombatController.new(entity.entity_id, entity.combatant)
	controller.growth_stage = growth_stage
	controller.set_instance_source(Sim.new_instance_id)
	var lo: Dictionary = record.get("loadout", {})
	controller.loadout = {
		"light": str(lo.get("light_chain", "")), "heavy": str(lo.get("heavy", "")),
		"dodge": str(lo.get("dodge", "")), "block": str(lo.get("block", "")),
		"jump": str(lo.get("jump", "")), "ultimate": str(lo.get("ultimate", "")),
	}
	var slots: Array = lo.get("slots", [])
	for i in 8:
		controller.loadout["slot_%d" % (i + 1)] = str(slots[i]) if i < slots.size() else ""
	for id: String in controller.loadout.values():
		ensure_action(id)
	sprint_def = GameData.get_action(str(lo.get("sprint", "action.sprint")))
	controller.block_def = GameData.get_action(str(lo.get("block", "action.block")))
	entity.controller = controller
	controller.action_started.connect(_on_action_started)
	controller.action_ended.connect(_on_action_ended)
	controller.request_rejected.connect(_on_request_rejected)


func _initial_known_abilities() -> Array[String]:
	var out: Array[String] = []
	for key: String in SLOT_KEYS:
		var id := str(controller.loadout.get(key, ""))
		if id != "" and not out.has(id):
			out.append(id)
	return out


func _apply_profile() -> void:
	var capsule := (body_shape.shape as CapsuleShape3D).duplicate() as CapsuleShape3D
	capsule.radius = float(profile.get("capsule_radius_m", 0.85))
	capsule.height = float(profile.get("capsule_total_height_m", 3.66))
	body_shape.shape = capsule
	body_shape.position = Vector3(0.0, capsule.height * 0.5, 0.0)
	floor_snap_length = maxf(0.3, float(profile.get("step_height_m", 0.45)))
	floor_max_angle = deg_to_rad(46.0)


# --------------------------------------------------------------------------- components

## Instantiates every [name, path] entry whose file exists and registers it under `name`
## (also as the matching member, e.g. `growth`). Missing files are skipped without an error.
func load_components(entries: Array) -> void:
	for entry: Array in entries:
		var path := str(entry[1])
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null:
			continue
		var instance: Variant = script.new()
		if not instance is PlayerComponent:
			push_warning("GiantPlayer: %s is not a PlayerComponent" % path)
			continue
		add_component(StringName(str(entry[0])), instance)


## Registers (and sets up) a component; a component with the same name is replaced.
func add_component(component_name: StringName, c: PlayerComponent) -> void:
	if c == null:
		return
	remove_component(component_name)
	_components.append(c)
	_by_name[component_name] = c
	if String(component_name) in self:
		set(String(component_name), c)
	c.setup(self)
	_sort_edge_order()


func remove_component(component_name: StringName) -> void:
	var old: PlayerComponent = _by_name.get(component_name)
	if old == null:
		return
	_components.erase(old)
	_by_name.erase(component_name)
	if String(component_name) in self:
		set(String(component_name), null)
	_sort_edge_order()


func component(component_name: StringName) -> PlayerComponent:
	return _by_name.get(component_name)


## Components in registration order.
func components() -> Array[PlayerComponent]:
	return _components.duplicate()


func _sort_edge_order() -> void:
	_edge_order = _components.duplicate()
	var rank := {}
	for i in _components.size():
		rank[_components[i]] = i
	_edge_order.sort_custom(func(a: PlayerComponent, b: PlayerComponent) -> bool:
		var pa := a.edge_priority()
		var pb := b.edge_priority()
		return pa < pb if pa != pb else int(rank[a]) < int(rank[b]))


# --------------------------------------------------------------------------- tick

func sim_step(tick: int, dt: float) -> void:
	var intents := router.consume()
	last_intents = intents
	controller.on_floor = is_on_floor()
	controller.block_held = intents.block_held
	controller.begin_tick(tick)
	if controller.state != CombatController.State.DEAD:
		for c in _components:
			c.pre_actions(intents, dt)
		_dispatch_edges(intents)
		if intents.block_held:
			controller.resume_held_block()
	motor.update_sprint(intents, dt)
	motor.update_facing(intents, dt)
	motor.update_movement(intents, dt)
	attack.run_hit_queries(tick)
	for c in _components:
		c.post_movement(tick, dt)
	entity.combatant.pools.tick(dt, controller.stamina_regen_allowed(sprinting))
	entity.combatant.poise.tick(dt)
	targeting.maintain_lock(dt)
	if global_position.y < OUT_OF_WORLD_Y:
		global_transform = spawn_transform
		velocity = Vector3.ZERO
		move_velocity = Vector3.ZERO


## Meta edges first (camera, lock, sprint toggle, interact, ...), then the hold-lock check,
## then action edges (attacks, defence, slots), as in M1. Each edge is first offered to the
## components by edge_priority; an unconsumed edge gets the default mapping.
func _dispatch_edges(intents: Dictionary) -> void:
	var edges: Array = intents.edges
	for e: StringName in edges:
		if not is_action_edge(e) and not _offer_edge(e):
			_default_meta_edge(e)
	targeting.apply_hold_release(intents)
	for e: StringName in edges:
		if is_action_edge(e) and not _offer_edge(e):
			_default_action_edge(e)


static func is_action_edge(e: StringName) -> bool:
	return e in ACTION_EDGES or String(e).begins_with("slot_")


func _offer_edge(e: StringName) -> bool:
	for c in _edge_order:
		if c.handle_edge(e):
			return true
	return false


func _default_meta_edge(e: StringName) -> void:
	match e:
		&"camera_toggle":
			camera_rig.toggle_mode()
		&"sprint_press":
			motor.toggle_sprint()
		_:
			targeting.handle_lock_edge(e)   # lock, target switch / zoom, stick flicks and taps


func _default_action_edge(e: StringName) -> void:
	match e:
		&"light":
			controller.request(&"light")
		&"heavy":
			controller.request(&"heavy")
		&"dodge":
			controller.request(&"dodge")
		&"jump":
			controller.request(&"jump")
		&"block_press":
			controller.request(&"block")
		&"block_release":
			controller.request(&"block_release")
		&"ultimate":
			controller.request(&"ultimate")
		_:
			var s := String(e)
			if s.begins_with("slot_"):
				controller.request(&"slot", {"slot": int(s.substr(5))})


func _on_action_started(action: ActionDef, instance_id: int) -> void:
	Events.ability_started.emit(Sim.tick, entity.entity_id, action.id, instance_id)
	for c in _components:
		c.on_action_started(action, instance_id)


func _on_action_ended(action: ActionDef, instance_id: int, interrupted: bool) -> void:
	for c in _components:
		c.on_action_ended(action, instance_id, interrupted)


func _on_request_rejected(kind: StringName, action_id: String, reason: String) -> void:
	Events.action_rejected.emit(Sim.tick, entity.entity_id, action_id, reason)
	var def := GameData.get_action(action_id)
	var label := def.display_name if def != null else String(kind).capitalize()
	match reason:
		"stamina":
			Events.hud_message.emit("Not enough stamina for %s" % label, "warn")
		"cooldown":
			Events.hud_message.emit("%s is recovering (%.1f s)" % [label,
				controller.cooldowns.remaining_s(action_id, Sim.tick)], "warn")
		"empty_slot":
			if kind == &"ultimate":
				Events.hud_message.emit("No ultimate equipped yet (roadmap)", "info")
			else:
				Events.hud_message.emit("That ability slot is empty", "info")
		"locked":
			Events.hud_message.emit("%s unlocks at a later growth stage" % label, "warn")


# --------------------------------------------------------------------------- actor API

func apply_knockback(direction: Vector3, speed: float) -> void:
	motor.apply_knockback(direction, speed)


func weapon_segment_global(action: ActionDef, f: float) -> PackedVector3Array:
	return attack.weapon_segment_global(action, f)


func attack_origin_global() -> Vector3:
	return to_global(attack_origin)


func current_weapon() -> Dictionary:
	return weapon


func current_growth_stage() -> int:
	return growth_stage


## Scale applied to the weapon's length and hit radius: the profile's weapon_scale (1.0 when
## the profile has none). P08 caps it at the weapon's fit stage.
func current_weapon_scale() -> float:
	return float(profile.get("weapon_scale", 1.0))


func weapon_hit_radius() -> float:
	return weapon_radius


func locked_entity() -> CombatEntity:
	return targeting.locked_entity()


## Adds `id` and its chain_next follow-ups to the controller's library (no gating).
func ensure_action(id: String) -> void:
	var guard := 0
	while id != "" and not controller.library.has(id) and guard < 16:
		var def := GameData.get_action(id)
		if def == null:
			return
		controller.add_action(def)
		id = def.chain_next
		guard += 1


## Puts `action_id` ("" = empty) into "slot_1".."slot_8" or "ultimate". No gating: callers
## (shrine loadout, rewards, saves) decide what may go where.
func set_loadout_slot(slot_key: String, action_id: String) -> void:
	if not slot_key in SLOT_KEYS:
		push_warning("GiantPlayer.set_loadout_slot: unknown slot '%s'" % slot_key)
		return
	ensure_action(action_id)
	controller.loadout[slot_key] = action_id


## Swaps the growth profile record and tells every component (geometry, lock range, ...).
## Gating, clearance, height, camera framing and resource rescaling are PlayerGrowth's job
## (P05); this only re-applies what the components and the capsule read from the profile.
func set_profile(new_profile: Dictionary) -> void:
	var old := profile
	profile = new_profile
	growth_stage = int(new_profile.get("stage", growth_stage))
	controller.growth_stage = growth_stage
	_apply_profile()
	camera_rig.profile = new_profile
	for c in _components:
		c.on_profile_changed(old, new_profile)
	rig.set_weapon_pivot(weapon_pivot)


## Swaps the weapon record and tells every component (geometry). Never mid-swing: equipment
## (P08) checks the controller state first.
func set_weapon(new_weapon: Dictionary) -> void:
	weapon = new_weapon
	for c in _components:
		c.on_weapon_changed(new_weapon)


# --------------------------------------------------------------------------- character state

## Applies a character-state dictionary (the save format, plan §2.9). Order: growth,
## progression, equipment (when those components exist), the other components, then the core
## keys handled here: loadout, known_abilities, level, and resources last. Keys nobody handles
## (ancestry, xp, attributes, ...) are kept and returned unchanged by capture_character_state.
func apply_character_state(state: Dictionary) -> void:
	_state_passthrough = state.duplicate(true)
	for c in _state_components():
		c.apply_state(state)
	if state.has("known_abilities") and typeof(state.known_abilities) == TYPE_ARRAY:
		known_abilities.clear()
		for id: Variant in state.known_abilities:
			var s := str(id)
			if s != "" and not known_abilities.has(s):
				known_abilities.append(s)
				ensure_action(s)
	if state.has("loadout") and typeof(state.loadout) == TYPE_DICTIONARY:
		var lo: Dictionary = state.loadout
		if typeof(lo.get("slots")) == TYPE_ARRAY:
			var slots: Array = lo.slots
			for i in 8:
				set_loadout_slot("slot_%d" % (i + 1), str(slots[i]) if i < slots.size() else "")
		if lo.has("ultimate"):
			set_loadout_slot("ultimate", str(lo.ultimate))
	if state.has("level") and progression == null and "level" in controller:
		controller.set("level", int(state.level))
	if state.has("resources") and typeof(state.resources) == TYPE_DICTIONARY:
		_restore_resources(state.resources)


## The current character state: every passthrough key from the last apply, overwritten by what
## the components and the core own now.
func capture_character_state() -> Dictionary:
	var out := _state_passthrough.duplicate(true)
	for c in _state_components():
		c.capture_state(out)
	var known: Array = []   # plain arrays, like the JSON the state came from
	for id in known_abilities:
		known.append(id)
	out["known_abilities"] = known
	var slots: Array = []
	for i in 8:
		slots.append(str(controller.loadout.get("slot_%d" % (i + 1), "")))
	out["loadout"] = {"slots": slots, "ultimate": str(controller.loadout.get("ultimate", ""))}
	if progression == null and "level" in controller:
		out["level"] = int(controller.get("level"))
	var pools := entity.combatant.pools
	out["resources"] = {"health": pools.health, "stamina": pools.stamina, "essence": pools.essence,
		"fury": pools.fury}
	return out


func _state_components() -> Array[PlayerComponent]:
	var out: Array[PlayerComponent] = []
	for n: String in STATE_ORDER:
		var c: PlayerComponent = _by_name.get(StringName(n))
		if c != null:
			out.append(c)
	for c in _components:
		if not out.has(c):
			out.append(c)
	return out


func _restore_resources(values: Dictionary) -> void:
	var pools := entity.combatant.pools
	if pools.has_method("restore"):
		pools.call("restore", values)
		return
	# Until ResourcePool.restore (P01) exists: assign, clamp to the maxima, timers as if idle.
	if values.has("health"):
		pools.health = clampf(float(values.health), 0.0, pools.health_max)
	if values.has("stamina"):
		pools.stamina = clampf(float(values.stamina), 0.0, pools.stamina_max)
	if values.has("essence"):
		pools.essence = clampf(float(values.essence), 0.0, pools.essence_max)
	if values.has("fury"):
		pools.fury = clampf(float(values.fury), 0.0, pools.fury_max)
	pools.since_stamina_spend = 999.0
	pools.since_essence_spend = 999.0
	pools.since_combat = 999.0


# --------------------------------------------------------------------------- combat hooks

func _on_hit_landed(result: HitResult) -> void:
	if result.dealt_damage():
		stats.hits_landed += 1
	if result.killed:
		stats.kills += 1


func _on_hit_taken(result: HitResult) -> void:
	if result.outcome == HitResult.Outcome.PARRIED:
		stats.parries += 1
		Events.hud_message.emit("Parry!", "good")
	elif result.outcome == HitResult.Outcome.GUARD_BROKEN:
		Events.hud_message.emit("Guard broken!", "bad")


func get_defense_state() -> DefenseState:
	var d := DefenseState.new()
	d.position = global_position
	d.forward = -global_transform.basis.z
	d.height_m = entity.combatant.height_m
	d.is_dead = controller.state == CombatController.State.DEAD
	d.blocking = controller.state == CombatController.State.BLOCKING
	d.block_elapsed_ticks = controller.block_elapsed_ticks()
	d.parry_available = controller.parry_available
	d.invulnerable = controller.is_invulnerable()
	d.stamina = entity.combatant.pools.stamina
	d.stability = entity.combatant.stability
	d.apply_block_def(controller.block_def)
	return d


func on_entity_died(_killer_id: String) -> void:
	stats.deaths += 1
	sprinting = false
	if lock.is_locked():
		targeting.release_lock("player_died")
	Events.hud_message.emit("You were defeated", "bad")


func _on_any_entity_died(_tick: int, id: String, _killer: String) -> void:
	targeting.on_any_entity_died(id)


# --------------------------------------------------------------------------- presentation

func flash(strength: float, color := Color(1.0, 0.95, 0.85)) -> void:
	rig.flash(strength, color)


func get_rig_state() -> Dictionary:
	var local_dodge := global_transform.basis.inverse() * dodge_direction
	var s := {
		"state": controller.state,
		"action": controller.action,
		"phase": controller.phase(),
		"phase_fraction": controller.phase_fraction(),
		"speed": Vector2(velocity.x, velocity.z).length(),
		"dead": controller.state == CombatController.State.DEAD,
		"staggered": controller.state == CombatController.State.STAGGERED,
		"dodging": controller.state == CombatController.State.DODGING,
		"dodge_local": local_dodge,
	}
	for c in _components:
		c.rig_state(s)
	return s


func get_debug_info() -> Dictionary:
	var pools := entity.combatant.pools
	var d := {
		"state": controller.state_name(),
		"phase": ActionDef.PHASE_NAMES[controller.phase()],
		"action": controller.action_id(),
		"instance": controller.instance_id,
		"elapsed": controller.elapsed,
		"queued": String(controller.buffer.kind),
		"stage": growth_stage,
		"health": pools.health, "stamina": pools.stamina, "essence": pools.essence, "fury": pools.fury,
		"poise": entity.combatant.poise.value,
		"sprinting": sprinting,
		"target": lock.target_id,
		"camera": "first person" if camera_rig.is_first_person() else "third person",
		"position": global_position,
		"invulnerable": controller.is_invulnerable(),
		"parry_window": controller.state == CombatController.State.BLOCKING
			and controller.block_elapsed_ticks() < ActionDef.seconds_to_ticks(0.2) and controller.parry_available,
	}
	for c in _components:
		c.debug_info(d)
	return d
