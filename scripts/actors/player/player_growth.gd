class_name PlayerGrowth
extends PlayerComponent
## Growth stages 1-6 (spec §9, plan §3.5; stages 4-6 and size gates: plan M6-M9 §2.9, P26): safe
## growth at shrines, and the F6 / F7 debug grow and shrink keys.
##
## A growth is checked first and changes nothing when any check fails (growth_blocked, a HUD
## warning, the reason code and message in the result). The checks, in order:
##   no_profile  there is no growth profile for that stage
##   already     the giant is already that stage (shrines only grow)
##   shrine_max  no shrine, the shrine cannot grow anyone, or not that far (record max_stage)
##   flags       a growth_requires_flags flag of the shrine is not set (Kingsfall: the boss)
##   conditions  a growth_requires_conditions condition of the shrine does not hold (P26: a world
##               shrine waits for world.kingsgate.lit or a count of oaths); the message is the
##               condition's growth_conditions_text entry, so it names the missing one
##   level       controller.level < the profile's required_level (99 = gating off)
##   busy        not standing in LOCOMOTION on the floor (attacking, dodging, staggered, ...)
##   holding     controller.holding_id is set (a grabbed body in hand)
##   combat      pools.in_combat(): a hit was exchanged in the last 10 s; or a living enemy that
##               is aware of the giant stands within the shrine's activation radius (P16)
##   clearance   the new capsule overlaps WORLD | BREAKABLE | BLOCKER | ACTORS (P16: a dummy, an
##               enemy, an NPC), or something is above the head up to the new height
##               (check_clearance)
## The debug path (debug_set_stage) skips shrine_max, flags, level and combat.
##
## A growth that passes is applied in one tick, through GiantPlayer.set_profile: the stage
## (controller gating), capsule and floor snap, camera (zoom fraction kept, arm never snapped),
## navigation layers, weapon geometry x current_weapon_scale(), lock range and half-angle, and
## then this component's on_profile_changed: the combatant's height, the profile's
## resource_bonus as growth_bonus with the resource fractions kept (growth never heals), the
## rig's body scale k = height / 3.6576, and the hurtboxes and anchors rebuilt from their
## stage-1 sizes x k (shapes are duplicated and resized; node scale is never used for
## collision). After that: the profile's unlocks (learned, auto-slotted into the first empty
## slot, ability_learned) and Events.growth_changed.
##
## Save state: "growth_stage" (apply_state restores it silently: no events, no unlocks; the
## saved loadout and resources are applied after it). Footstep shake: each footfall of the
## rig's stride adds the profile's footstep_shake to the camera at stage 2 and above.
##
## Size gates and navigation (P26, plan M6-M9 §2.2): every profile change also sets the giant's
## collision mask to ACTOR_MASK | size_gate_mask() - the invisible size-gate walls of physics layers
## 7-9 stop a giant below their stage (stages 1-3 collide with all three, stage 6 with none) - and
## its navigation layers to effective_nav_layers(): the profile's layer when the level bakes it,
## else the level record's player_nav_fallback (the Valley has no titan layer 16, so stages 4-6
## path on its giant layer 4). nav_query_mask() is the titan layer's query mask in the world (16 |
## the gate bits up to the stage).

const STATE_KEY := "growth_stage"
## Physics layers a growing capsule may not overlap: world, breakables, blockers and (P16, M3
## review) actors - the giant must not grow into a dummy, an enemy or an NPC. Corpses clear their
## layer, and the giant's own body is excluded.
const CLEARANCE_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_BREAKABLE | 32 \
	| HitQueryAdapter.LAYER_ACTORS
## The combat gate's radius around a shrine without an activation_radius_m (P16).
const DEFAULT_SHRINE_RADIUS_M := 14.0
## The clearance capsule is lifted this far off the floor so the floor itself never counts.
const CLEARANCE_LIFT_M := 0.05
const REASONS := ["no_profile", "already", "shrine_max", "flags", "conditions", "level", "busy",
	"holding", "combat", "clearance"]
## Player-facing names of the interaction permissions a stage adds (Grow tab summary).
const PERMISSION_TEXT := {
	"grab_small": "Grab and throw staggered soldiers and wolves",
	"throw_boulder": "Hurl boulders and smash barricades",
	"tree_weapon": "Uproot ancient oaks and wield them",
	"gate_breach": "Breach fortified gates",
	"trample": "Trample fences and palisades underfoot",
	"formation_sweep": "Sweep through soldier formations",
	"heave": "Heave rockfalls, fallen titan-trees and toppled statues aside",
	# M8 gate (F34): blows break an engine at any stage; stage 6 adds seizing one (PlayerGrab, SiegeEngine).
	"siege_disruption": "Seize a staggered or uncrewed siege engine and hurl it",
	"monster_grapple": "Grapple great monsters",
	"titan_execution": "Execute titans",
}
## P26 (plan M6-M9 §2.2): the physics layer of the size-gate walls each gate stage puts up (7: 64,
## 8: 128, 9: 256) and the titan navigation layer's gate bit of the same stage (32, 64, 128).
const SIZE_GATE_LAYERS := {4: 64, 5: 128, 6: 256}
const TITAN_LAYER := 16
const TITAN_GATE_BITS := {4: 32, 5: 64, 6: 128}
## Every actor body's mask without the size gates (SceneKit.ACTOR_MASK: world, actors, breakables,
## blockers).
const ACTOR_MASK := HitQueryAdapter.LAYER_WORLD | HitQueryAdapter.LAYER_ACTORS \
	| HitQueryAdapter.LAYER_BREAKABLE | 32
## The size-gate layers together (layers 7-9).
const ALL_SIZE_GATES := 448

## The result of the last grow_to / debug_set_stage (the Grow tab shows it).
var last_result: Dictionary = {}
var _base_areas: Array = []    ## [{"node": Node3D, "position": Vector3}] hurtbox areas
var _base_shapes: Array = []   ## [{"node": CollisionShape3D, "shape": Shape3D, "position": Vector3}]
var _base_anchors: Array = []  ## [{"node": Node3D, "position": Vector3}]
var _base_k := 1.0             ## the body scale the scene was authored at (stage 1: 1.0)


func setup(p: GiantPlayer) -> void:
	super(p)
	_capture_base_body()
	if player.rig != null and player.rig.has_signal(&"footfall"):
		player.rig.footfall.connect(_on_footfall)
	_sync_body(player.profile)


# --------------------------------------------------------------------------- queries

func stage() -> int:
	return player.growth_stage


## The growth_profile record of `n` ({} when there is none). Looked up each time, so test
## overrides of the records are always seen.
func profile_for_stage(n: int) -> Dictionary:
	return find_profile(GameData.records_of_type("growth_profile"), n)


## The highest stage that has a profile.
func max_stage() -> int:
	var best := 0
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		best = maxi(best, int(rec.get("stage", 0)))
	return best


## Body scale of a profile: its height over the stage-1 giant's (k).
static func body_scale_for(profile: Dictionary) -> float:
	return float(profile.get("height_m", CombatRules.REFERENCE_HEIGHT_M)) / CombatRules.REFERENCE_HEIGHT_M


## The profile's resource_bonus as growth_bonus floats (absolute per stage, not cumulative).
static func resource_bonus(profile: Dictionary) -> Dictionary:
	var out := {}
	var bonus: Variant = profile.get("resource_bonus", {})
	if typeof(bonus) == TYPE_DICTIONARY:
		for key: String in ["health", "stamina", "essence"]:
			if (bonus as Dictionary).has(key):
				out[key] = float(bonus[key])
	return out


static func find_profile(records: Array, n: int) -> Dictionary:
	for rec: Dictionary in records:
		if int(rec.get("stage", -1)) == n:
			return rec
	return {}


## {ok, reason, message} for growing to `target` at `shrine` (a Shrine, or any node with
## record() returning a shrine record; null = no shrine). Changes nothing.
func check_growth(target: int, shrine: Node) -> Dictionary:
	var prof := profile_for_stage(target)
	var basic := _check_target(target, prof)
	if not basic.ok:
		return basic
	var gate := shrine_gate(target, shrine_record(shrine), Callable(WorldState, "get_flag"))
	if not gate.ok:
		return gate
	var conds := conditions_gate(shrine_record(shrine), Quests.condition_context())
	if not conds.ok:
		return conds
	var level := level_gate(prof, player.controller.level)
	if not level.ok:
		return level
	var state := _check_state()
	if not state.ok:
		return state
	var combat := combat_gate(shrine)
	if not combat.ok:
		return combat
	return check_clearance(prof)


## The combat gate of a shrine growth (P16, M3 review: "Enemies are near" now means it): {ok,
## reason "combat", message} while a hit was exchanged in the last 10 s (pools.in_combat()) or
## while aware_enemies_near(shrine) is not empty. Changes nothing.
func combat_gate(shrine: Node) -> Dictionary:
	if player.entity.combatant.pools.in_combat() or not aware_enemies_near(shrine).is_empty():
		return result_fail("combat")
	return result_ok()


## The entity ids of living enemies (group "enemies") whose brain is aware of the giant
## (EnemyBrain.aware, as GameSession's checkpoint deferral reads it) within the shrine's activation
## radius of the shrine, horizontally; without a shrine, within DEFAULT_SHRINE_RADIUS_M of the giant.
## Faction members at peace and the sparring post are never aware, so they never count.
func aware_enemies_near(shrine: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if not player.is_inside_tree():
		return out
	var center := player.global_position
	var radius := DEFAULT_SHRINE_RADIUS_M
	if shrine is Node3D and is_instance_valid(shrine) and (shrine as Node3D).is_inside_tree():
		center = (shrine as Node3D).global_position
		if shrine.has_method("activation_radius_m"):
			radius = float(shrine.call("activation_radius_m"))
		else:
			radius = float(shrine_record(shrine).get("activation_radius_m", DEFAULT_SHRINE_RADIUS_M))
	for n in player.get_tree().get_nodes_in_group("enemies"):
		var enemy := n as Node3D
		if enemy == null or not enemy.is_inside_tree():
			continue
		var e: Variant = enemy.get("entity")
		if e is CombatEntity and not (e as CombatEntity).is_alive():
			continue
		var brain: Variant = enemy.get("brain")
		if brain == null or not (brain is Object) or not ("aware" in brain) or not bool(brain.get("aware")):
			continue
		var d := enemy.global_position - center
		if Vector2(d.x, d.z).length() <= radius:
			out.append(str(enemy.get("entity_id")))
	return out


## Clearance for `profile` at the giant's position (plan §3.5 design 2): a capsule of the new
## radius and height lifted CLEARANCE_LIFT_M off the floor must overlap nothing on
## CLEARANCE_MASK plus the size-gate walls the new stage still collides with (P26: a giant may not
## grow into a gate wall it could not leave) (the giant's own body excluded), and an upward ray
## from the current head to the new head height must be clear. {ok, reason, message, "blocker":
## node name or ""}.
func check_clearance(profile: Dictionary) -> Dictionary:
	if profile.is_empty():
		return result_fail("no_profile")
	var r := float(profile.get("capsule_radius_m", 0.85))
	var h := float(profile.get("capsule_total_height_m", 3.66))
	var space := player.get_world_3d().direct_space_state
	var cap := CapsuleShape3D.new()
	cap.radius = r
	cap.height = maxf(h, 2.0 * r)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = cap
	q.transform = Transform3D(Basis(), player.global_position + Vector3.UP * (cap.height * 0.5 + CLEARANCE_LIFT_M))
	q.collision_mask = CLEARANCE_MASK | size_gate_mask_of(profile)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [player.get_rid()]
	var hits := space.intersect_shape(q, 1)
	if not hits.is_empty():
		var out := result_fail("clearance", _blocker_message(hits[0]))
		out["blocker"] = _collider_name(hits[0])
		return out
	var head := player.global_position + Vector3.UP * float(player.profile.get("capsule_total_height_m", 3.66))
	var top := player.global_position + Vector3.UP * (cap.height + CLEARANCE_LIFT_M)
	if top.y > head.y + 1e-3:
		var ray := PhysicsRayQueryParameters3D.create(head, top, CLEARANCE_MASK, [player.get_rid()])
		ray.collide_with_areas = false
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			var out := result_fail("clearance")
			out["blocker"] = _collider_name(hit)
			return out
	var ok := result_ok()
	ok["blocker"] = ""
	return ok


# --------------------------------------------------------------------------- growing

## Grows to `target` at `shrine` when check_growth passes, all in one tick; otherwise changes
## nothing, emits growth_blocked and a HUD warning. Returns check_growth's dictionary, plus on
## success "from", "to" and "summary" (change_summary()).
func grow_to(target: int, shrine: Node, reason := "shrine") -> Dictionary:
	var check := check_growth(target, shrine)
	if not check.ok:
		_blocked(check)
		last_result = check
		return check
	return _grow(target, reason)


## F6 / F7: any stage that has a profile, with the busy, holding and clearance checks but no
## shrine, level or combat gates. Shows "DEBUG: stage N" and logs it.
func debug_set_stage(target: int) -> Dictionary:
	var prof := profile_for_stage(target)
	var check := _check_target(target, prof)
	if check.ok:
		check = _check_state()
	if check.ok:
		check = check_clearance(prof)
	if not check.ok:
		_blocked(check)
		print("[growth] DEBUG: stage %d -> %d refused (%s)" % [stage(), target, check.reason])
		last_result = check
		return check
	var old := stage()
	var out := _grow(target, "debug")
	print("[growth] DEBUG: stage %d -> %d" % [old, target])
	Events.hud_message.emit("DEBUG: stage %d" % target, "info")
	return out


func _grow(target: int, reason: String) -> Dictionary:
	var old_stage := stage()
	var old_profile := player.profile
	var pools := player.entity.combatant.pools
	var old_max := {"health": pools.health_max, "stamina": pools.stamina_max, "essence": pools.essence_max}
	var prof := profile_for_stage(target)
	player.set_profile(prof)
	var learned := _apply_unlocks(prof)
	var new_max := {"health": pools.health_max, "stamina": pools.stamina_max, "essence": pools.essence_max}
	var summary := change_summary(old_profile, prof, old_max, new_max, learned, player.current_weapon())
	Events.growth_changed.emit(Sim.tick, player.entity.entity_id, old_stage, target)
	if reason != "debug":
		Events.hud_message.emit("You grew: stage %d, %s" % [target, str(prof.get("display_name", ""))], "good")
	var out := result_ok()
	out["from"] = old_stage
	out["to"] = target
	out["reason_applied"] = reason
	out["summary"] = summary
	out["message"] = "You grew to stage %d." % target
	last_result = out
	return out


## The profile's unlocks the giant does not know yet: learned (known_abilities), added to the
## controller's library and put into the first empty slot. Returns [{"id", "slot"}] (slot ""
## when every slot is full).
func _apply_unlocks(prof: Dictionary) -> Array:
	var out: Array = []
	var unlocks: Variant = prof.get("unlocks", [])
	if typeof(unlocks) != TYPE_ARRAY:
		return out
	for id_v: Variant in unlocks:
		var id := str(id_v)
		if id == "" or player.known_abilities.has(id) or GameData.get_action(id) == null:
			continue
		player.known_abilities.append(id)
		player.ensure_action(id)
		var slot := ""
		if not _is_slotted(id):
			slot = first_empty_slot(player.controller.loadout)
			if slot != "":
				player.set_loadout_slot(slot, id)
				Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
		Events.ability_learned.emit(Sim.tick, id, slot)
		out.append({"id": id, "slot": slot})
	return out


func _is_slotted(id: String) -> bool:
	for key: String in GiantPlayer.SLOT_KEYS:
		if str(player.controller.loadout.get(key, "")) == id:
			return true
	return false


## The first of slot_1..slot_8 holding no action ("" when all are full).
static func first_empty_slot(loadout: Dictionary) -> String:
	for i in 8:
		var key := "slot_%d" % (i + 1)
		if str(loadout.get(key, "")) == "":
			return key
	return ""


# --------------------------------------------------------------------------- component hooks

func edge_priority() -> int:
	return 90


## F6 / F7 (debug builds only: the router emits these edges only there).
func handle_edge(edge: StringName) -> bool:
	match edge:
		&"debug_grow":
			debug_set_stage(stage() + 1)
			return true
		&"debug_shrink":
			debug_set_stage(stage() - 1)
			return true
	return false


## Any profile swap (GiantPlayer.set_profile: growth, restores, tests) re-fits the body.
func on_profile_changed(_old_profile: Dictionary, new_profile: Dictionary) -> void:
	_sync_body(new_profile)


func apply_state(state: Dictionary) -> void:
	if not state.has(STATE_KEY):
		return
	var n := int(state[STATE_KEY])
	if n == stage():
		return
	var prof := profile_for_stage(n)
	if prof.is_empty():
		push_warning("PlayerGrowth: the saved growth stage %d has no profile; staying at stage %d" % [n, stage()])
		return
	player.set_profile(prof)


func capture_state(out: Dictionary) -> void:
	out[STATE_KEY] = stage()


func rig_state(out: Dictionary) -> void:
	out["dodge_style"] = str(player.profile.get("dodge_style", "roll"))
	out["body_scale"] = body_scale_for(player.profile)


func debug_info(out: Dictionary) -> void:
	out["growth"] = "%s  k %.2f  nav %d  gates %d  titan %d" % [str(player.profile.get("id", "?")),
		body_scale_for(player.profile), player.nav_layers, size_gate_mask(), nav_query_mask()]


# --------------------------------------------------------------------------- size gates and navigation (P26)

## The size-gate layers a giant of `stage` still collides with: every gate above its stage (stages
## 1-3: 448, stage 4: 384, stage 5: 256, stage 6 and beyond: 0).
static func size_gate_mask_for_stage(stage: int) -> int:
	var mask := 0
	for gate: int in SIZE_GATE_LAYERS:
		if stage < gate:
			mask |= int(SIZE_GATE_LAYERS[gate])
	return mask


## The titan layer's query mask for a giant of `stage`: 16 and the gate bit of every gate stage it
## has reached (stages 1-3: 16, stage 4: 48, stage 5: 112, stage 6 and beyond: 240).
static func nav_query_mask_for_stage(stage: int) -> int:
	var mask := TITAN_LAYER
	for gate: int in TITAN_GATE_BITS:
		if stage >= gate:
			mask |= int(TITAN_GATE_BITS[gate])
	return mask


## A profile's size_gate_mask, else the one of its stage.
static func size_gate_mask_of(profile: Dictionary) -> int:
	if profile.has("size_gate_mask"):
		return int(profile.size_gate_mask)
	return size_gate_mask_for_stage(int(profile.get("stage", 1)))


## A profile's nav_query_mask, else the one of its stage.
static func nav_query_mask_of(profile: Dictionary) -> int:
	if profile.has("nav_query_mask"):
		return int(profile.nav_query_mask)
	return nav_query_mask_for_stage(int(profile.get("stage", 1)))


## The size-gate walls the giant collides with now (layers 7-9 above its stage).
func size_gate_mask() -> int:
	return size_gate_mask_of(player.profile)


## The titan layer's query mask of the giant now (plan M6-M9 §2.2: 16 | 32 | 64 | 128 by stage).
func nav_query_mask() -> int:
	return nav_query_mask_of(player.profile)


## The giant's body mask for `profile`: every actor's mask plus the size gates above its stage.
static func collision_mask_for(profile: Dictionary) -> int:
	return ACTOR_MASK | size_gate_mask_of(profile)


## GameData's cross-record check of the growth profiles (P26, anchor P26 of the post-pass): one
## profile per stage from 1 to the highest, no stage twice; each stage taller, with a capsule at
## least as wide and as tall and a required level no lower than the stage before, keeping every
## interaction permission of the stage before; and a profile's size_gate_mask and nav_query_mask,
## when it has them, those of its stage. `paths` maps record ids to files (messages).
static func profile_chain_errors(profiles: Array, paths: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var by_stage := {}
	for rec: Dictionary in profiles:
		var st := int(rec.get("stage", 0))
		var where := "%s (%s)" % [paths.get(rec.get("id", ""), "?"), rec.get("id", "?")]
		if by_stage.has(st):
			out.append("%s: a second growth profile for stage %d (%s has it)" % [where, st, (by_stage[st] as Dictionary).get("id", "?")])
			continue
		by_stage[st] = rec
		if rec.has("size_gate_mask") and int(rec.size_gate_mask) != size_gate_mask_for_stage(st):
			out.append("%s: size_gate_mask %d is not stage %d's (%d: the gate layers above it)" % [where,
				int(rec.size_gate_mask), st, size_gate_mask_for_stage(st)])
		if rec.has("nav_query_mask") and int(rec.nav_query_mask) != nav_query_mask_for_stage(st):
			out.append("%s: nav_query_mask %d is not stage %d's (%d: the titan layer and its gates up to it)" % [where,
				int(rec.nav_query_mask), st, nav_query_mask_for_stage(st)])
	if by_stage.is_empty():
		return out
	var top := 0
	for st: int in by_stage:
		top = maxi(top, st)
	for st in range(1, top + 1):
		if not by_stage.has(st):
			out.append("growth profiles: no profile for stage %d (stages 1-%d must all have one)" % [st, top])
			continue
		if st == 1 or not by_stage.has(st - 1):
			continue
		var a: Dictionary = by_stage[st - 1]
		var b: Dictionary = by_stage[st]
		var where := "%s (%s)" % [paths.get(b.get("id", ""), "?"), b.get("id", "?")]
		if float(b.get("height_m", 0.0)) <= float(a.get("height_m", 0.0)):
			out.append("%s: stage %d is not taller than stage %d" % [where, st, st - 1])
		for key: String in ["capsule_radius_m", "capsule_total_height_m"]:
			if float(b.get(key, 0.0)) < float(a.get(key, 0.0)):
				out.append("%s: %s shrinks from stage %d" % [where, key, st - 1])
		if int(b.get("required_level", 1)) < int(a.get("required_level", 1)):
			out.append("%s: required_level %d is below stage %d's %d" % [where, int(b.get("required_level", 1)),
				st - 1, int(a.get("required_level", 1))])
		var kept: Variant = b.get("interaction_permissions", [])
		for perm: Variant in a.get("interaction_permissions", []):
			if typeof(kept) != TYPE_ARRAY or not (kept as Array).has(perm):
				out.append("%s: loses the interaction permission '%s' of stage %d" % [where, perm, st - 1])
	return out


## The lowest stage whose profile grants `permission` (0 when none does): the stage a gated prop
## names in its size_gate_blocked event and its messages.
static func stage_for_permission(permission: String) -> int:
	var best := 0
	for rec: Dictionary in GameData.records_of_type("growth_profile"):
		var perms: Variant = rec.get("interaction_permissions", [])
		var st := int(rec.get("stage", 0))
		if typeof(perms) == TYPE_ARRAY and (perms as Array).has(permission) and (best == 0 or st < best):
			best = st
	return best


## The navigation layers the giant paths with in its level: the profile's nav_layers when the level
## bakes that layer (or the giant is in no level with navigation), else the level record's
## player_nav_fallback (the Valley: 4 for stages 4-6, whose titan layer it does not have).
func effective_nav_layers(profile: Dictionary) -> int:
	var want := int(profile.get("nav_layers", 4))
	var level := _level_root()
	if level == null:
		return want
	var have := level_nav_layers(level)
	if have == 0 or (have & want) != 0:
		return want
	var fallback := int(level.call("player_nav_fallback")) if level.has_method("player_nav_fallback") else 0
	return fallback if fallback > 0 else want


## The navigation layers a level bakes: its record's world.nav_layers (a streamed level), else the
## layers of the NavigationRegion3D nodes under its Navigation node (the Valley: 1 | 2 | 4 | 8).
static func level_nav_layers(level: Node) -> int:
	var bits := 0
	var rec: Variant = level.call("level_record") if level.has_method("level_record") else {}
	if typeof(rec) == TYPE_DICTIONARY and typeof((rec as Dictionary).get("world")) == TYPE_DICTIONARY:
		var layers: Variant = (rec.world as Dictionary).get("nav_layers")
		if typeof(layers) == TYPE_ARRAY:
			for b: Variant in layers:
				bits |= int(b)
			return bits
	var nav := level.get_node_or_null("Navigation")
	if nav != null:
		for child in nav.get_children():
			if child is NavigationRegion3D:
				bits |= (child as NavigationRegion3D).navigation_layers
	return bits


## The LevelRoot the giant stands in (its nearest ancestor that answers player_nav_fallback), or null.
func _level_root() -> Node:
	var n: Node = player.get_parent() if player != null else null
	while n != null:
		if n.has_method("player_nav_fallback"):
			return n
		n = n.get_parent()
	return null


# --------------------------------------------------------------------------- body

## Height, growth bonus (fractions kept), rig scale and collision sizes for `profile`; the body's
## size-gate mask and the navigation layers of the level (P26).
func _sync_body(profile: Dictionary) -> void:
	var c := player.entity.combatant
	c.set_height(float(profile.get("height_m", c.height_m)))
	c.growth_bonus = resource_bonus(profile)
	c.recompute_derived()
	var k := body_scale_for(profile)
	if player.rig != null and player.rig.has_method("set_body_scale"):
		player.rig.set_body_scale(k)
	_resize_body(k)
	player.collision_mask = collision_mask_for(profile)
	player.nav_layers = effective_nav_layers(profile)


## Remembers every hurtbox area, hurtbox shape and anchor as authored (the scene is the
## stage-1 giant unless the record starts at another stage; sizes are kept per k = 1).
func _capture_base_body() -> void:
	_base_k = body_scale_for(player.profile)
	_base_areas.clear()
	_base_shapes.clear()
	_base_anchors.clear()
	var hb_root := player.get_node_or_null("Hurtboxes")
	if hb_root != null:
		for area in hb_root.get_children():
			if area is Node3D:
				_base_areas.append({"node": area, "position": (area as Node3D).position / _base_k})
				for cs in area.get_children():
					if cs is CollisionShape3D and (cs as CollisionShape3D).shape != null:
						var shape := (cs as CollisionShape3D).shape
						_base_shapes.append({"node": cs, "shape": scaled_shape(shape, 1.0 / _base_k),
							"position": (cs as CollisionShape3D).position / _base_k})
	var anchor_root := player.get_node_or_null("Anchors")
	if anchor_root != null:
		for a in anchor_root.get_children():
			if a is Node3D:
				_base_anchors.append({"node": a, "position": (a as Node3D).position / _base_k})


## Rebuilds the hurtboxes and anchors at body scale k from their base sizes.
func _resize_body(k: float) -> void:
	for e: Dictionary in _base_areas:
		if is_instance_valid(e.node):
			(e.node as Node3D).position = (e.position as Vector3) * k
	for e: Dictionary in _base_shapes:
		if is_instance_valid(e.node):
			var cs := e.node as CollisionShape3D
			cs.shape = scaled_shape(e.shape, k)
			cs.position = (e.position as Vector3) * k
	for e: Dictionary in _base_anchors:
		if is_instance_valid(e.node):
			(e.node as Node3D).position = (e.position as Vector3) * k


## A copy of `shape` scaled uniformly by k (boxes, spheres, capsules, cylinders).
static func scaled_shape(shape: Shape3D, k: float) -> Shape3D:
	var s := shape.duplicate() as Shape3D
	if s is BoxShape3D:
		(s as BoxShape3D).size = (shape as BoxShape3D).size * k
	elif s is SphereShape3D:
		(s as SphereShape3D).radius = (shape as SphereShape3D).radius * k
	elif s is CapsuleShape3D:
		(s as CapsuleShape3D).radius = (shape as CapsuleShape3D).radius * k
		(s as CapsuleShape3D).height = (shape as CapsuleShape3D).height * k
	elif s is CylinderShape3D:
		(s as CylinderShape3D).radius = (shape as CylinderShape3D).radius * k
		(s as CylinderShape3D).height = (shape as CylinderShape3D).height * k
	return s


func _on_footfall() -> void:
	var amount := float(player.profile.get("footstep_shake", 0.0))
	if amount > 0.0 and stage() >= 2 and player.is_on_floor() and player.camera_rig != null:
		player.camera_rig.add_shake(amount)


# --------------------------------------------------------------------------- checks

func _check_target(target: int, prof: Dictionary) -> Dictionary:
	if prof.is_empty():
		return result_fail("no_profile", "You cannot grow any further." if target > stage()
			else "There is no growth stage %d." % target)
	if target == stage():
		return result_fail("already", "You are already stage %d." % target)
	return result_ok()


func _check_state() -> Dictionary:
	var c := player.controller
	if c.state != CombatController.State.LOCOMOTION or not player.is_on_floor():
		return result_fail("busy")
	if c.holding_id != "":
		return result_fail("holding")
	return result_ok()


## The shrine checks of growing to `target` (rec = the shrine's record; {} = no shrine):
## shrine_max, then flags (get_flag(id) must be truthy for every growth_requires_flags id).
static func shrine_gate(target: int, rec: Dictionary, get_flag: Callable) -> Dictionary:
	if rec.is_empty():
		return result_fail("shrine_max", "Only a shrine can make you grow.")
	if not bool(rec.get("allows_growth", false)):
		return result_fail("shrine_max", "This shrine cannot make you grow.")
	var max_s := int(rec.get("max_stage", 1))
	if target > max_s:
		return result_fail("shrine_max", "This shrine can only make you grow to stage %d." % max_s)
	var flags: Variant = rec.get("growth_requires_flags", [])
	if typeof(flags) == TYPE_ARRAY:
		for f: Variant in flags:
			if not get_flag.call(str(f), false):
				var msg := str(rec.get("growth_locked_message", ""))
				return result_fail("flags", msg if msg != "" else "Something still binds this shrine's power.")
	return result_ok()


## P26 (plan M6-M9 §2.9): every growth_requires_conditions entry of the shrine record `rec` must hold
## in the quest context `ctx` (QuestConditions, the shapes of quests and dialogue). The refusal
## names the first one that does not: its growth_conditions_text entry, else the record's
## growth_locked_message, else the default text. {ok, reason "conditions", message}.
static func conditions_gate(rec: Dictionary, ctx: Dictionary) -> Dictionary:
	var conds: Variant = rec.get("growth_requires_conditions", [])
	if typeof(conds) != TYPE_ARRAY:
		return result_ok()
	var texts: Variant = rec.get("growth_conditions_text", [])
	var list: Array = conds
	for i in list.size():
		if QuestConditions.holds(list[i], ctx):
			continue
		var text := ""
		if typeof(texts) == TYPE_ARRAY and i < (texts as Array).size():
			text = str(texts[i])
		if text == "":
			text = str(rec.get("growth_locked_message", ""))
		return result_fail("conditions", text)
	return result_ok()


## Level gate: the profile's required_level against the character level (99 = gating off).
static func level_gate(prof: Dictionary, level: int) -> Dictionary:
	var need := int(prof.get("required_level", 1))
	if level < need:
		return result_fail("level", "You must reach level %d to grow to stage %d." % [need, int(prof.get("stage", 0))])
	return result_ok()


## The record of a shrine node ({} for null or a node without one).
static func shrine_record(shrine: Node) -> Dictionary:
	if shrine == null or not is_instance_valid(shrine):
		return {}
	if shrine.has_method("record"):
		var rec: Variant = shrine.call("record")
		return rec if typeof(rec) == TYPE_DICTIONARY else {}
	var id: Variant = shrine.get("shrine_id")
	return GameData.get_record(str(id)) if typeof(id) == TYPE_STRING else {}


static func result_ok() -> Dictionary:
	return {"ok": true, "reason": "", "message": ""}


## {ok: false, reason, message}; an empty message uses the reason's default text.
static func result_fail(reason: String, message := "") -> Dictionary:
	return {"ok": false, "reason": reason, "message": message if message != "" else default_message(reason)}


static func default_message(reason: String) -> String:
	match reason:
		"no_profile":
			return "You cannot grow any further."
		"already":
			return "You are already this size."
		"shrine_max":
			return "This shrine cannot make you grow."
		"flags":
			return "Something still binds this shrine's power."
		"conditions":
			return "The shrine waits for a deed not yet done."
		"level":
			return "You are not experienced enough to grow yet."
		"busy":
			return "Stand still on solid ground before you grow."
		"holding":
			return "Put down what you are holding before you grow."
		"combat":
			return "Enemies are near. You cannot grow while fighting."
		"clearance":
			return "Not enough room to grow here. Step into the open."
	return "You cannot grow right now."


func _blocked(check: Dictionary) -> void:
	Events.growth_blocked.emit(Sim.tick, player.entity.entity_id, str(check.reason), str(check.message))
	Events.hud_message.emit(str(check.message), "warn")


static func _collider_name(hit: Dictionary) -> String:
	var n: Variant = hit.get("collider")
	return (n as Node).name if n is Node else ""


## The clearance refusal for a hit: an actor in the way is named ("Soldier is in the way. Step
## into the open to grow."); anything else keeps the default text ("" = default).
static func _blocker_message(hit: Dictionary) -> String:
	var n: Variant = hit.get("collider")
	if not (n is CollisionObject3D) or ((n as CollisionObject3D).collision_layer & HitQueryAdapter.LAYER_ACTORS) == 0:
		return ""
	var e: Variant = (n as Node).get("entity")
	var label := (e as CombatEntity).display_name() if e is CombatEntity else str((n as Node).name)
	return "%s is in the way. Step into the open to grow." % label


# --------------------------------------------------------------------------- summary

## What changed between two profiles, for the Grow tab and the result of grow_to: [old, new]
## pairs for stage, height_m, reach_m and the resource maxima, the interaction permissions
## gained, the abilities learned ([{"id", "slot"}]), and whether the weapon no longer fits
## (its fit_max_stage, P08, is below the new stage). "lines" holds the player-facing text.
static func change_summary(old_profile: Dictionary, new_profile: Dictionary, old_max: Dictionary,
		new_max: Dictionary, learned: Array, weapon: Dictionary) -> Dictionary:
	var gained: Array = []
	var old_perms: Array = old_profile.get("interaction_permissions", [])
	for perm: Variant in new_profile.get("interaction_permissions", []):
		if not old_perms.has(perm):
			gained.append(str(perm))
	var new_stage := int(new_profile.get("stage", 1))
	var fit := int(weapon.get("fit_max_stage", 10))
	# P26: the size gates the new body no longer collides with (their stages).
	var gates_passed: Array = []
	var old_gates := size_gate_mask_of(old_profile) if not old_profile.is_empty() else ALL_SIZE_GATES
	var new_gates := size_gate_mask_of(new_profile)
	for gate: int in SIZE_GATE_LAYERS:
		var bit := int(SIZE_GATE_LAYERS[gate])
		if (old_gates & bit) != 0 and (new_gates & bit) == 0:
			gates_passed.append(gate)
	var s := {
		"stage": [int(old_profile.get("stage", 1)), new_stage],
		"height_m": [float(old_profile.get("height_m", 0.0)), float(new_profile.get("height_m", 0.0))],
		"reach_m": [float(old_profile.get("melee_reach_m", 0.0)), float(new_profile.get("melee_reach_m", 0.0))],
		"health_max": [float(old_max.get("health", 0.0)), float(new_max.get("health", 0.0))],
		"stamina_max": [float(old_max.get("stamina", 0.0)), float(new_max.get("stamina", 0.0))],
		"essence_max": [float(old_max.get("essence", 0.0)), float(new_max.get("essence", 0.0))],
		"permissions": gained,
		"learned": learned.duplicate(true),
		"weapon_too_small": fit < new_stage,
		"weapon": str(weapon.get("display_name", weapon.get("id", ""))),
		"size_gates": gates_passed,
	}
	s["lines"] = summary_lines(s)
	return s


static func summary_lines(s: Dictionary) -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append("Stage %d -> %d" % [int(s.stage[0]), int(s.stage[1])])
	lines.append("Height %.1f m -> %.1f m" % [float(s.height_m[0]), float(s.height_m[1])])
	lines.append("Reach %.1f m -> %.1f m" % [float(s.reach_m[0]), float(s.reach_m[1])])
	lines.append("Health %d -> %d, stamina %d -> %d (the same share of each is kept)" % [
		roundi(float(s.health_max[0])), roundi(float(s.health_max[1])),
		roundi(float(s.stamina_max[0])), roundi(float(s.stamina_max[1]))])
	for perm: String in s.permissions:
		lines.append("New: %s" % str(PERMISSION_TEXT.get(perm, perm.capitalize())))
	for gate: Variant in s.get("size_gates", []):
		lines.append("New: deep water and passes that stop giants below stage %d no longer stop you" % int(gate))
	for entry: Dictionary in s.learned:
		var def := GameData.get_action(str(entry.id))
		var label := def.display_name if def != null else str(entry.id)
		lines.append("Learned %s%s" % [label, " (%s)" % str(entry.slot).replace("_", " ") if str(entry.slot) != "" else ""])
	if bool(s.weapon_too_small):
		lines.append("Your %s is too small for you now. Reforge it at a forge to make it fit." % str(s.weapon))
	return lines
