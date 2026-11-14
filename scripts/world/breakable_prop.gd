class_name BreakableProp
extends StaticBody3D
## A persistent breakable or structural prop (spec section 11, plan §3.8, decision 23): health,
## damage stages, a stable world id, one destruction event, loot and XP once, debris laid out
## from data, nav links that open when it breaks, and its damage saved in WorldState.
##
## Stages (stages_for): a `breakable` has two, Intact and then Broken at 0 health. A `structural`
## prop has the record's damage_stages (intact -> cracked -> broken for the practice gate). After
## every damaging hit the current stage is the last entry whose at_or_below_frac is at least the
## health fraction. A change shows that stage's visual child and hides the others, removes the
## Block* collision shapes when the stage removes_collision, enables the NavLink* links when it
## enables_nav_links, and (structural props) emits object_stage_changed. The last stage is the
## destruction: object_destroyed once, on_destroyed_flags (first write wins), the record's XP
## when the player broke it (Events.xp_award_requested), loot once per world id, debris.
## Loot (P12): the record's inline `loot` list plus a roll of its loot table - this instance's
## `loot_table` export when set (a placed quarry chest or armory crate), else the record's
## `loot_table` (Loot.roll) - all inside the one WorldState.try_award_loot(world_id).
##
## Gating (accepts_hit): a hit is refused (CombatEntity's IMMUNE "not_permitted") when the prop
## is already broken or opened, `protected`, the hit's category is not accepted, it lacks a
## required tag (the Deadfall wants TreeWeapon), the attacker's growth stage is below
## min_growth_stage, or the attacker's profile lacks requires_permission. `last_rejection` names
## the reason ("protected", "category", "tags", "stage", "permission", "destroyed"); a refused
## player hit shows the record's locked_message, at most once every 3 s.
##
## Persistence: every damaging hit calls WorldState.record_damage(world_id, stage, health), so a
## cracked gate reloads cracked: _ready restores the health, stage, visual, collision and nav
## links from the delta, without events, debris, loot or XP. open_when_flag opens the prop
## (force_open) when that flag becomes truthy or is already set at _ready: the final state
## without debris, loot, XP or flags, nav links on, delta `opened`, Events.object_opened.
##
## Required children: CombatEntity, one Node3D per stage visual (Intact/Broken; structural: the
## damage_stages' `visual` names), Block* CollisionShape3Ds, Hurtboxes/*, optional NavLink*
## (NavigationLink3D, disabled until the prop breaks).
##
## Size gates (P26, plan M6-M9 §2.9, §5.5, decision 18):
##   * indestructible (this placement's export, or the record's key): every hit is refused
##     ("indestructible") with the locked message - quest-critical props such as the Kings' Door,
##     which only open_when_flag opens.
##   * trample_stage (record; 0 = never): a giant of that stage or more walking into the prop
##     (PlayerMotor reads its slide collisions) deals it one trample hit through the normal hit path
##     (category melee, TRAMPLE_DAMAGE): it breaks and Events.trampled(tick, world_id, entity_id)
##     goes out. The damage is the player's like a blow's, so FactionState counts a trampled house of
##     a faction as an offence (its node's faction and prop_tags), and a fence as none.
##   * heave: a prop whose record requires_permission "heave" (rockfalls, fallen titan-trees, toppled
##     statues) breaks to any accepted blow of a giant with that permission (stage 5; the existing
##     permission rule), and heave(attacker) - the HeavePoint interaction, the bots - heaves it aside
##     with one heave hit. A smaller giant is refused with the locked message.
##   * A player hit refused for its stage or permission also emits Events.size_gate_blocked(tick,
##     world_id, the stage it needs, the message), with the locked message's 3 s throttle.

const BLOCK_PREFIX := "Block"
const NAV_LINK_PREFIX := "NavLink"
const DEFAULT_DEBRIS_LENGTH_M := 8.0
## A refused player hit shows the locked message at most once in this many ticks (3 s).
const LOCKED_MESSAGE_GAP_TICKS := 180
const PROTECTED_MESSAGE := "This cannot be broken."
## P26: the damage of a trample or heave hit (enough for any prop that can be trampled or heaved).
const TRAMPLE_DAMAGE := 9999.0
const TRAMPLE_ACTION := "trample"
const HEAVE_ACTION := "heave"
const HEAVE_PERMISSION := "heave"
## The implicit stages of a plain breakable.
const BREAKABLE_STAGES := [
	{"id": "intact", "at_or_below_frac": 1.0, "visual": "Intact"},
	{"id": "broken", "at_or_below_frac": 0.0, "visual": "Broken", "removes_collision": true,
		"enables_nav_links": true},
]

@export var world_id := ""
## Per-instance loot table override (P12); "" = the record's loot_table.
@export var loot_table := ""
## P26: no hit ever breaks this placement (quest-critical props); the record's indestructible key
## does the same for every placement of the record.
@export var indestructible := false

@onready var entity: CombatEntity = $CombatEntity

## True once the prop is in its final state: broken, or opened by force_open (see `opened`).
var destroyed := false
## Opened without being broken (force_open): no debris, loot, XP or flags were given.
var opened := false
var record: Dictionary = {}
var stages: Array = []
var stage_index := 0
## Why the last refused hit was refused ("" when the last hit was accepted).
var last_rejection := ""
## Locked messages shown so far (tests).
var locked_messages := 0
## P26: size_gate_blocked events sent for refused player hits (tests).
var gate_events := 0
## P26: the tick a trample or heave hit was queued on (it breaks the prop in that tick's resolution).
var _special_tick := -1
var _last_locked_tick := -1000000
var _nav_links: Array[NavigationLink3D] = []


func _ready() -> void:
	add_to_group("breakables")
	record = GameData.get_record(entity.definition_id)
	stages = stages_for(record)
	if world_id == "":
		push_error("BreakableProp %s has no world_id" % get_path())
	for child in get_children():
		if child is NavigationLink3D and child.name.begins_with(NAV_LINK_PREFIX):
			_nav_links.append(child as NavigationLink3D)
	set_nav_links_enabled(false)
	_show_stage_visual(0)
	entity.hit_taken.connect(_on_hit_taken)
	_restore_from_delta()
	var flag := open_flag()
	if flag != "":
		Events.flag_changed.connect(_on_flag_changed)
		if not destroyed and flag_truthy(WorldState.get_flag(flag)):
			force_open("flag")


# --------------------------------------------------------------------------- queries

## The stages of a prop record: a structural prop's damage_stages, else Intact -> Broken.
static func stages_for(rec: Dictionary) -> Array:
	var authored: Variant = rec.get("damage_stages")
	if str(rec.get("category", "")) == "structural" and typeof(authored) == TYPE_ARRAY \
			and (authored as Array).size() >= 2:
		return authored
	return BREAKABLE_STAGES


## The index of the last stage whose at_or_below_frac is at least `frac` (0 when none is).
static func stage_for_fraction(p_stages: Array, frac: float) -> int:
	var out := 0
	for i in p_stages.size():
		if float((p_stages[i] as Dictionary).get("at_or_below_frac", 1.0)) >= frac - 1e-9:
			out = i
	return out


## Flags count as set when true, a non-zero number or a non-empty string.
static func flag_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_NIL:
			return false
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING, TYPE_STRING_NAME:
			return str(v) != ""
	return true


func is_structural() -> bool:
	return str(record.get("category", "")) == "structural"


func stage_id() -> String:
	return str((stages[stage_index] as Dictionary).get("id", "")) if stage_index < stages.size() else ""


func health() -> float:
	return entity.combatant.pools.health


func health_fraction() -> float:
	var pools := entity.combatant.pools
	return pools.health / maxf(pools.health_max, 1e-6)


func open_flag() -> String:
	return str(record.get("open_when_flag", ""))


func locked_message() -> String:
	var msg := str(record.get("locked_message", ""))
	if msg == "" and (bool(record.get("protected", false)) or is_indestructible()):
		return PROTECTED_MESSAGE
	return msg


## P26: true when no hit breaks this prop (the placement's export or the record's key).
func is_indestructible() -> bool:
	return indestructible or bool(record.get("indestructible", false))


## P26: the stage whose giant tramples this prop by walking into it (0 = never).
func trample_stage() -> int:
	return int(record.get("trample_stage", 0))


func nav_links() -> Array[NavigationLink3D]:
	return _nav_links


func nav_links_enabled() -> bool:
	for link in _nav_links:
		if link.enabled:
			return true
	return false


func set_nav_links_enabled(on: bool) -> void:
	for link in _nav_links:
		if is_instance_valid(link):
			link.enabled = on


## True while any Block* collision shape is still attached.
func has_collision() -> bool:
	for child in get_children():
		if child is CollisionShape3D and child.name.begins_with(BLOCK_PREFIX):
			return true
	return false


# --------------------------------------------------------------------------- hits

func accepts_hit(hit: HitEvent) -> bool:
	last_rejection = rejection_reason(hit)
	return last_rejection == ""


## Why `hit` would be refused now ("" = it would be accepted). Order: destroyed, protected,
## category, tags, stage, permission.
func rejection_reason(hit: HitEvent) -> String:
	if destroyed:
		return "destroyed"
	if is_indestructible():
		return "indestructible"
	if bool(record.get("protected", false)):
		return "protected"
	var categories: Array = record.get("accepted_attack_categories", [])
	if not categories.has(hit.category):
		return "category"
	for tag: Variant in record.get("required_tags", []):
		if not hit.has_tag(str(tag)):
			return "tags"
	if hit.attacker_growth_stage < int(record.get("min_growth_stage", 1)):
		return "stage"
	var permission := str(record.get("requires_permission", ""))
	if permission != "" and not attacker_permissions(hit.attacker_id).has(permission):
		return "permission"
	return ""


## The interaction permissions of an attacker's current growth profile ([] when it has none).
static func attacker_permissions(attacker_id: String) -> Array:
	var e := Sim.get_entity(attacker_id)
	if e == null or e.actor == null or not ("profile" in e.actor):
		return []
	var profile: Variant = e.actor.get("profile")
	if typeof(profile) != TYPE_DICTIONARY:
		return []
	var perms: Variant = (profile as Dictionary).get("interaction_permissions", [])
	return perms if typeof(perms) == TYPE_ARRAY else []


static func is_player_id(entity_id: String) -> bool:
	var e := Sim.get_entity(entity_id)
	return e != null and e.team == CombatEntity.Team.PLAYER


func _on_hit_taken(result: HitResult) -> void:
	if result.outcome == HitResult.Outcome.IMMUNE and result.notes == "not_permitted":
		_on_refused(result.event)
		return
	if destroyed or result.killed or result.health_damage <= 0:
		return
	# Only the destruction (on_entity_died, at 0 health) enters the last stage; stages never go back.
	var idx := mini(stage_for_fraction(stages, health_fraction()), stages.size() - 2)
	if idx > stage_index:
		_set_stage(idx, true)
	WorldState.record_damage(world_id, stage_index, health())


## A refused player hit: the locked message (throttled). Hits on a wreck say nothing. P26: a hit
## refused for the attacker's stage or permission is a size gate too (Events.size_gate_blocked).
func _on_refused(hit: HitEvent) -> void:
	if hit == null or last_rejection == "destroyed" or not is_player_id(hit.attacker_id):
		return
	var msg := locked_message()
	if msg == "" or Sim.tick - _last_locked_tick < LOCKED_MESSAGE_GAP_TICKS:
		return
	_last_locked_tick = Sim.tick
	locked_messages += 1
	Events.hud_message.emit(msg, "warn")
	var needed := needed_stage(last_rejection)
	if needed > 0:
		gate_events += 1
		Events.size_gate_blocked.emit(Sim.tick, world_id, needed, msg)


## P26: the growth stage a refusal of this kind asks for: the record's min_growth_stage for "stage",
## the first stage that grants requires_permission for "permission", 0 for any other reason.
func needed_stage(reason: String) -> int:
	match reason:
		"stage":
			return int(record.get("min_growth_stage", 1))
		"permission":
			return PlayerGrowth.stage_for_permission(str(record.get("requires_permission", "")))
	return 0


# --------------------------------------------------------------------------- trample and heave (P26)

## True when a giant of `stage` tramples this prop by walking into it now: intact, a trample stage
## at or below `stage`, breakable by a melee blow of that giant (not indestructible or protected).
func can_trample(stage: int) -> bool:
	var need := trample_stage()
	if destroyed or special_hit_pending() or need <= 0 or stage < need:
		return false
	return _special_hit_reason(stage, PackedStringArray()) == ""


## The giant `attacker` (an actor with an entity and a growth stage) walked into this prop: when it
## may trample it, one trample hit through the hit queue (it breaks this tick) and Events.trampled.
## Returns whether it trampled.
func trample(attacker: Node3D) -> bool:
	var stage := _stage_of(attacker)
	if attacker == null or not can_trample(stage):
		return false
	if not _queue_special_hit(attacker, TRAMPLE_ACTION):
		return false
	Events.trampled.emit(Sim.tick, world_id, _entity_id_of(attacker))
	return true


## True when this prop is heaved aside (its record requires_permission "heave").
func is_heave_prop() -> bool:
	return str(record.get("requires_permission", "")) == HEAVE_PERMISSION


## Heaves the prop aside for `attacker`: {ok, reason, message}. Refused ("not_heavable", "destroyed",
## or the hit's rejection: "permission" when the giant is too small, with the locked message and a
## size_gate_blocked event); otherwise one heave hit that breaks it this tick.
func heave(attacker: Node3D) -> Dictionary:
	if not is_heave_prop():
		return {"ok": false, "reason": "not_heavable", "message": ""}
	if destroyed or special_hit_pending():
		return {"ok": false, "reason": "destroyed", "message": ""}
	var why := _special_hit_reason(_stage_of(attacker), attacker_permissions(_entity_id_of(attacker)))
	if why != "":
		var msg := locked_message()
		last_rejection = why
		var needed := needed_stage(why)
		if needed > 0 and is_player_id(_entity_id_of(attacker)):
			gate_events += 1
			Events.size_gate_blocked.emit(Sim.tick, world_id, needed, msg)
		if msg != "":
			Events.hud_message.emit(msg, "warn")
		return {"ok": false, "reason": why, "message": msg}
	_queue_special_hit(attacker, HEAVE_ACTION)
	return {"ok": true, "reason": "", "message": ""}


## Why a trample or heave (a melee hit of a giant of `stage` with `perms`) would be refused ("" = it
## would land); the order of rejection_reason.
func _special_hit_reason(stage: int, perms: Array) -> String:
	if destroyed:
		return "destroyed"
	if is_indestructible():
		return "indestructible"
	if bool(record.get("protected", false)):
		return "protected"
	if not (record.get("accepted_attack_categories", []) as Array).has("melee"):
		return "category"
	if not (record.get("required_tags", []) as Array).is_empty():
		return "tags"
	if stage < int(record.get("min_growth_stage", 1)):
		return "stage"
	var permission := str(record.get("requires_permission", ""))
	if permission != "" and not perms.has(permission):
		return "permission"
	return ""


## Queues the trample or heave hit of `attacker` on this prop (category melee, TRAMPLE_DAMAGE, no
## size scaling), resolved with the tick's other hits.
func _queue_special_hit(attacker: Node3D, action_id: String) -> bool:
	var attacker_id := _entity_id_of(attacker)
	if attacker_id == "" or entity == null:
		return false
	var e := HitEvent.new()
	e.tick = Sim.tick
	e.instance_id = Sim.new_instance_id()
	e.attacker_id = attacker_id
	e.target_id = entity.entity_id
	e.action_id = action_id
	e.power = TRAMPLE_DAMAGE
	e.attacker_stat = 0.0
	e.size_policy = "none"
	e.damage_split = {"physical": 1.0}
	e.tags = PackedStringArray(["Melee"])
	e.category = "melee"
	e.attacker_growth_stage = _stage_of(attacker)
	var a_entity: Variant = attacker.get("entity")
	if a_entity is CombatEntity and (a_entity as CombatEntity).combatant != null:
		e.attacker_height_m = (a_entity as CombatEntity).combatant.height_m
	e.attacker_position = attacker.global_position
	e.hit_point = global_position
	e.distance = attacker.global_position.distance_to(global_position)
	Sim.queue_hit(e)
	_special_tick = Sim.tick
	return true


## True while a trample or heave hit queued this tick has not resolved yet.
func special_hit_pending() -> bool:
	return _special_tick == Sim.tick


static func _stage_of(actor: Node) -> int:
	if actor != null and "growth_stage" in actor:
		return int(actor.get("growth_stage"))
	return 1


static func _entity_id_of(actor: Node) -> String:
	if actor == null:
		return ""
	var e: Variant = actor.get("entity")
	if e is CombatEntity:
		return (e as CombatEntity).entity_id
	return ""


func on_entity_died(killer_id: String) -> void:
	if destroyed:
		return
	var last := stages.size() - 1
	destroyed = true
	_set_stage(last, true)
	_disable_hurtboxes()
	WorldState.record_damage(world_id, last, 0.0)
	WorldState.record_destroyed(world_id, last)
	_spawn_debris()
	Events.object_destroyed.emit(Sim.tick, world_id, killer_id)
	var flags: Variant = record.get("on_destroyed_flags", {})
	if typeof(flags) == TYPE_DICTIONARY:
		for flag: Variant in flags:
			WorldState.try_set_flag(str(flag), flags[flag])
	var xp := int(record.get("xp_reward", 0))
	if xp > 0 and is_player_id(killer_id):
		Events.xp_award_requested.emit(xp, "prop:%s" % world_id)
	if WorldState.try_award_loot(world_id):
		for loot: Dictionary in record.get("loot", []):
			var item := str(loot.get("item", ""))
			var count := int(loot.get("count", 1))
			WorldState.add_item(item, count, "loot")
			Events.loot_awarded.emit(Sim.tick, world_id, item, count, killer_id)
		Loot.give(world_id, Loot.roll(loot_table_id()), killer_id)


## The loot table this prop rolls when it breaks: its own `loot_table`, else the record's ("" = none).
func loot_table_id() -> String:
	return loot_table if loot_table != "" else str(record.get("loot_table", ""))


# --------------------------------------------------------------------------- opening

## Opens the prop without breaking it (the village opening its barricade): the final stage's
## visual, no collision, nav links on, no more hits, delta `opened`, Events.object_opened. No
## debris, loot, XP or flags. Returns false when it is already broken or open.
func force_open(reason := "flag") -> bool:
	if destroyed:
		return false
	opened = true
	_enter_final_state()
	WorldState.record_opened(world_id)
	Events.object_opened.emit(Sim.tick, world_id, reason)
	return true


func _on_flag_changed(_tick: int, flag_id: String, value: Variant) -> void:
	if flag_id == open_flag() and flag_truthy(value):
		force_open("flag")


# --------------------------------------------------------------------------- state

## Restores a saved prop silently: broken or opened props come back in their final state,
## damaged ones with their health and stage (visual, collision, nav links).
func _restore_from_delta() -> void:
	var d := WorldState.get_delta(world_id)
	if d.is_empty():
		return
	if bool(d.get("destroyed", false)):
		_enter_final_state()
		return
	if bool(d.get("opened", false)):
		opened = true
		_enter_final_state()
		return
	if SchemaUtil.is_number(d.get("health")):
		var pools := entity.combatant.pools
		var hp := clampf(float(d.health), 0.0, pools.health_max)
		if hp <= 0.0:
			_enter_final_state()
			return
		pools.health = hp
		var idx := stage_for_fraction(stages, health_fraction())
		if SchemaUtil.is_number(d.get("damage_stage")):
			idx = int(d.damage_stage)
		idx = clampi(idx, 0, stages.size() - 2)
		if idx > 0:
			_set_stage(idx, false)


## The last stage, silently: its visual, no collision, nav links on, hurtboxes off, dead.
func _enter_final_state() -> void:
	destroyed = true
	entity.combatant.dead = true
	_set_stage(stages.size() - 1, false)
	_remove_block_shapes()
	set_nav_links_enabled(true)
	_disable_hurtboxes()


func _set_stage(idx: int, announce: bool) -> void:
	stage_index = clampi(idx, 0, stages.size() - 1)
	var st: Dictionary = stages[stage_index]
	_show_stage_visual(stage_index)
	if bool(st.get("removes_collision", false)):
		_remove_block_shapes()
	if bool(st.get("enables_nav_links", false)):
		set_nav_links_enabled(true)
	if announce and is_structural():
		Events.object_stage_changed.emit(Sim.tick, world_id, stage_index, str(st.get("id", "")))


func _show_stage_visual(idx: int) -> void:
	var current := str((stages[idx] as Dictionary).get("visual", ""))
	for st: Dictionary in stages:
		var node := get_node_or_null(str(st.get("visual", ""))) as Node3D
		if node != null:
			node.visible = false
	var shown := get_node_or_null(current) as Node3D
	if shown != null:
		shown.visible = true


func _remove_block_shapes() -> void:
	for child in get_children():
		if child is CollisionShape3D and child.name.begins_with(BLOCK_PREFIX):
			# Disable and detach now (not at end of frame) so a navmesh bake in the same frame -
			# e.g. the sandbox loading with this prop already destroyed - never sees it.
			(child as CollisionShape3D).disabled = true
			remove_child(child)
			child.queue_free()


func _disable_hurtboxes() -> void:
	for hb in entity.hurtboxes:
		hb.set_deferred("monitorable", false)
		for c in hb.get_children():
			if c is CollisionShape3D:
				(c as CollisionShape3D).set_deferred("disabled", true)


# --------------------------------------------------------------------------- debris

func _spawn_debris() -> void:
	var pool := get_tree().get_first_node_in_group("debris_pool") as DebrisPool
	if pool == null:
		return
	var count := int(record.get("debris_count", 6))
	if count <= 0:
		return
	var length := float(record.get("debris_length_m", DEFAULT_DEBRIS_LENGTH_M))
	var layout := str(record.get("debris_layout", "line"))
	var transforms: Array[Transform3D] = []
	var velocities: Array[Vector3] = []
	for piece: Dictionary in debris_pieces(world_id, count, length, layout):
		transforms.append(global_transform * (piece.transform as Transform3D))
		velocities.append(global_transform.basis * (piece.velocity as Vector3))
	pool.spawn(transforms, velocities, debris_piece_size(count, length, layout))


## Debris in the prop's local space, deterministic per world id: {"transform", "velocity"} per
## piece. "line": spread along local X over `length` metres (fences, gates, felled trees);
## "pile": a heap within a quarter of `length` around the centre (cairns, crates, the Deadfall).
static func debris_pieces(seed_id: String, count: int, length: float, layout: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(seed_id)
	var out: Array = []
	for i in count:
		var local: Vector3
		var velocity: Vector3
		if layout == "pile":
			var angle := TAU * float(i) / float(maxi(count, 1)) + rng.randf_range(-0.3, 0.3)
			var dist := rng.randf_range(0.2, 1.0) * length * 0.25
			var out_dir := Vector3(sin(angle), 0.0, cos(angle))
			local = out_dir * dist + Vector3.UP * (0.3 + 0.5 * float(i % 3))
			velocity = out_dir * rng.randf_range(1.0, 3.5) + Vector3.UP * rng.randf_range(2.5, 5.5)
		else:
			var along := (float(i) + 0.5) / float(count) - 0.5
			local = Vector3(along * length, 0.6 + 0.6 * float(i % 2), 0.0)
			var away := Vector3.BACK * (1.0 if rng.randf() < 0.5 else -1.0)
			velocity = away * rng.randf_range(1.5, 4.0) + Vector3.UP * rng.randf_range(2.0, 5.0)
		var tilt := Basis(Vector3.UP, rng.randf_range(-0.3, 0.3)) * Basis(Vector3.FORWARD, PI * 0.5 * float(i % 2))
		out.append({"transform": Transform3D(tilt, local), "velocity": velocity})
	return out


## The size of one debris piece: planks along a line (an 8 m, 8-piece fence gives the M1 plank,
## 0.16 x 0.16 x 1.5 m), chunks in a pile.
static func debris_piece_size(count: int, length: float, layout: String) -> Vector3:
	var per := length / float(maxi(count, 1))
	if layout == "pile":
		var s := clampf(per * 1.2, 0.3, 1.6)
		return Vector3(s, s * 0.6, s * 1.4)
	var plank := clampf(per * 1.5, 0.5, 3.5)
	var t := clampf(plank * 0.107, 0.1, 0.45)
	return Vector3(t, t, plank)
