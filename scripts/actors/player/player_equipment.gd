class_name PlayerEquipment
extends PlayerComponent
## The giant's weapons (plan §3.8 design 4, decision 3): the weapons it owns, the one it holds, how
## big that weapon is at the current growth stage, and the matching moveset and mesh. The
## `equipment` component of GiantPlayer.COMPONENTS.
##
## - equip_weapon(id): only in LOCOMOTION (never mid-swing: the sweep's length must not change
##   during ACTIVE). Refuses a weapon it does not own, one whose required_stage is above the
##   giant's stage, or whose required_permission the growth profile lacks (reasons in REASONS).
##   On success: player.set_weapon (PlayerAttack re-reads the geometry), the weapon's
##   light_chain / heavy into the loadout (else the player record's), the mesh, the HUD
##   warning when it is too small, Events.weapon_equipped and loadout_changed.
## - Fit: a weapon follows the giant's growth up to its fit_max_stage; above it the weapon keeps
##   that stage's weapon_scale (effective_weapon_scale, which GiantPlayer.current_weapon_scale
##   returns), so the sweep and the mesh stay the size of the stage it fits, and the HUD says
##   "Your <weapon> is too small for you now. Reforge it at a forge to make it fit." when growth
##   or equipping takes the giant past it. Fixed-size weapons (scales_with_growth false: the
##   tree) keep their real length at every stage (scale 1).
## - The mesh (WeaponVisuals) goes under Visual/Body/ShoulderR as "Weapon" at the hand and hides
##   the generated Club. The body is scaled k, so the node is scaled effective_weapon_scale / k
##   and the mesh is exactly as long as the sweep. The tree's canopy is on render layer 2 (hidden
##   in first person) and the tree is carried raised to the right (WeaponVisuals.idle_pose).
## - Save state: "weapon" and "weapons_owned". A restore is silent (no events, no warning).

const STATE_WEAPON := "weapon"
const STATE_OWNED := "weapons_owned"
## The hand in weapon-arm (Body) space: the generated arm is 1.5 m at k = 1.
const HAND_OFFSET := Vector3(0.0, 0.0, -1.5)
const FIT_WARNING := "Your %s is too small for you now. Reforge it at a forge to make it fit."
const TOO_SMALL_SUFFIX := " (too small)"
const REASONS := ["unknown", "not_owned", "busy", "stage", "permission"]

## The equipped weapon's mesh node ("Weapon"), or null without a rig.
var visual: Node3D = null
## The result of the last equip_weapon / grant_weapon.
var last_result: Dictionary = {}
var _owned := PackedStringArray()
var _pending_fit_warning := false
var _was_too_small := false
var _default_idle_pose := Vector2.INF


func setup(p: GiantPlayer) -> void:
	super(p)
	if player.rig != null:
		_default_idle_pose = player.rig.idle_arm_pose
	var id := weapon_id()
	if id != "" and not _owned.has(id):
		_owned.append(id)
	_apply_weapon(player.weapon, false)


# --------------------------------------------------------------------------- queries

func weapon_id() -> String:
	return str(player.weapon.get("id", ""))


func weapon_name(id := "") -> String:
	var rec := player.weapon if id == "" else GameData.get_record(id)
	return str(rec.get("display_name", rec.get("id", "weapon")))


func owned() -> PackedStringArray:
	return _owned.duplicate()


func owns(id: String) -> bool:
	return _owned.has(id)


## The scale of the weapon's length and hit radius now: the weapon_scale of the growth profile of
## min(stage, fit_max_stage); 1.0 for fixed-size weapons (they keep their real length).
func effective_weapon_scale() -> float:
	return scale_for(player.weapon, player.growth_stage, player.profile)


## The stage whose size the weapon has now (its fit cap); the current stage for fixed-size ones.
func fit_stage() -> int:
	var w := player.weapon
	if not bool(w.get("scales_with_growth", true)):
		return player.growth_stage
	return mini(player.growth_stage, int(w.get("fit_max_stage", 10)))


## True when the giant has outgrown its weapon (stage > fit_max_stage).
func is_too_small() -> bool:
	return too_small_at(player.weapon, player.growth_stage)


## The inventory's name for a weapon: "Oak Club (too small)" when it would not fit now.
func weapon_label(id: String) -> String:
	var rec := GameData.get_record(id)
	return weapon_name(id) + (TOO_SMALL_SUFFIX if too_small_at(rec, player.growth_stage) else "")


## The tip's distance from the grip of the weapon mesh, in world metres (tests: equals
## player.weapon_length).
func visual_length() -> float:
	return WeaponVisuals.world_length(visual) if visual != null and visual.is_inside_tree() else 0.0


static func too_small_at(rec: Dictionary, stage: int) -> bool:
	return bool(rec.get("scales_with_growth", true)) and stage > int(rec.get("fit_max_stage", 10))


## The weapon scale of `rec` for a giant of `stage` whose current profile is `profile`.
static func scale_for(rec: Dictionary, stage: int, profile: Dictionary) -> float:
	if not bool(rec.get("scales_with_growth", true)):
		return 1.0
	var fit := int(rec.get("fit_max_stage", 10))
	if stage <= fit:
		return float(profile.get("weapon_scale", 1.0))
	var capped := PlayerGrowth.find_profile(GameData.records_of_type("growth_profile"), fit)
	return float(capped.get("weapon_scale", profile.get("weapon_scale", 1.0)))


## Cross-record weapon rule (plan §2.8.2): every upgrade.to weapon fits at least as high as its
## source. [] when every weapon record passes (test_weapons runs it on the shipped data; P12 may
## call it from the GameData post-pass).
static func upgrade_problems(records: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var ids := records.keys()
	ids.sort()
	for id: Variant in ids:
		var rec: Dictionary = records[id]
		if str(rec.get("type", "")) != "weapon" or typeof(rec.get("upgrade")) != TYPE_DICTIONARY:
			continue
		var to_id := str((rec.upgrade as Dictionary).get("to", ""))
		var to: Dictionary = records.get(to_id, {})
		if to.is_empty() or str(to.get("type", "")) != "weapon":
			continue   # a missing or mistyped reference is a validation error already
		var from_fit := int(rec.get("fit_max_stage", 10))
		var to_fit := int(to.get("fit_max_stage", 10))
		if to_fit < from_fit:
			out.append("%s: upgrade.to %s fits only up to stage %d, below its source's %d" % [id, to_id, to_fit, from_fit])
	return out


# --------------------------------------------------------------------------- equipping

## {ok, reason, message} for equipping `id` now; changes nothing.
func can_equip(id: String) -> Dictionary:
	var rec := GameData.get_record(id)
	if str(rec.get("type", "")) != "weapon":
		return _fail("unknown", "There is no weapon '%s'." % id)
	if not owns(id):
		return _fail("not_owned", "You do not have the %s." % weapon_name(id))
	if player.controller.state != CombatController.State.LOCOMOTION:
		return _fail("busy", "Finish what you are doing before you change weapons.")
	var need := int(rec.get("required_stage", 1))
	if player.growth_stage < need:
		return _fail("stage", "The %s needs a stage-%d giant." % [weapon_name(id), need])
	var permission := str(rec.get("required_permission", ""))
	if permission != "":
		var perms: Variant = player.profile.get("interaction_permissions", [])
		if typeof(perms) != TYPE_ARRAY or not (perms as Array).has(permission):
			return _fail("permission", "You are too small to wield the %s." % weapon_name(id))
	return {"ok": true, "reason": "", "message": ""}


## Equips an owned weapon (see can_equip for the refusals). {ok, reason, message}.
func equip_weapon(id: String) -> Dictionary:
	var check := can_equip(id)
	if not check.ok:
		last_result = check
		return check
	_apply_weapon(GameData.get_record(id), true)
	last_result = {"ok": true, "reason": "", "message": "You equip the %s." % weapon_name()}
	return last_result


## Adds a weapon to the owned list (once) and, with `equip`, equips it (equip_weapon's result;
## the weapon stays owned when that is refused). {ok, reason, message}.
func grant_weapon(id: String, equip := false) -> Dictionary:
	var rec := GameData.get_record(id)
	if str(rec.get("type", "")) != "weapon":
		last_result = _fail("unknown", "There is no weapon '%s'." % id)
		return last_result
	if not _owned.has(id):
		_owned.append(id)
	if equip:
		return equip_weapon(id)
	last_result = {"ok": true, "reason": "", "message": "You take the %s." % weapon_name(id)}
	return last_result


func _apply_weapon(rec: Dictionary, announce: bool) -> void:
	player.set_weapon(rec)
	_load_moveset(rec)
	_build_visual(rec)
	_was_too_small = is_too_small()
	_pending_fit_warning = false
	if not announce:
		return
	Events.weapon_equipped.emit(Sim.tick, player.entity.entity_id, weapon_id())
	Events.loadout_changed.emit(Sim.tick, player.entity.entity_id)
	if _was_too_small:
		_warn_too_small()
	else:
		Events.hud_message.emit("Equipped: %s" % weapon_name(), "info")


## The weapon's light chain and heavy into the controller's loadout (the player record's when the
## weapon has none), with their chains in the library; an open light chain is forgotten.
func _load_moveset(rec: Dictionary) -> void:
	var lo: Dictionary = player.record.get("loadout", {})
	var light := str(rec.get("light_chain", ""))
	if light == "":
		light = str(lo.get("light_chain", "ability.light_1"))
	var heavy := str(rec.get("heavy", ""))
	if heavy == "":
		heavy = str(lo.get("heavy", "ability.heavy_1"))
	var c := player.controller
	player.ensure_action(light)
	player.ensure_action(heavy)
	c.loadout["light"] = light
	c.loadout["heavy"] = heavy
	c.chain_next_id = ""
	c.chain_expire_tick = -1


func _warn_too_small() -> void:
	Events.hud_message.emit(FIT_WARNING % weapon_name(), "warn")


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message}


# --------------------------------------------------------------------------- mesh

func _build_visual(rec: Dictionary) -> void:
	var rig := player.rig
	if rig == null or not rig.has_method("set_weapon_visual"):
		return
	visual = WeaponVisuals.build(rec)
	rig.set_weapon_visual(visual, HAND_OFFSET)
	if _default_idle_pose != Vector2.INF:
		var pose := WeaponVisuals.idle_pose(rec)
		rig.idle_arm_pose = pose if pose != Vector2.INF else _default_idle_pose
	_update_visual_scale()


## Node scale = effective_weapon_scale / k: the (scaled) body times this is the sweep's length.
func _update_visual_scale() -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var k := float(player.rig.get("body_scale")) if player.rig != null and "body_scale" in player.rig \
		else PlayerGrowth.body_scale_for(player.profile)
	visual.scale = Vector3.ONE * (effective_weapon_scale() / maxf(k, 0.01))


# --------------------------------------------------------------------------- component hooks

## Growth (or a restore) changed the stage: the geometry was re-read by PlayerAttack already; the
## mesh follows the new body scale, and outgrowing the weapon queues the HUD warning (shown on the
## next tick, unless a restore - apply_state - cancels it).
func on_profile_changed(_old_profile: Dictionary, _new_profile: Dictionary) -> void:
	_update_visual_scale()
	var small := is_too_small()
	if small and not _was_too_small:
		_pending_fit_warning = true
	_was_too_small = small


func post_movement(_tick: int, _dt: float) -> void:
	if _pending_fit_warning:
		_pending_fit_warning = false
		_warn_too_small()


func apply_state(state: Dictionary) -> void:
	_pending_fit_warning = false
	if typeof(state.get(STATE_OWNED)) == TYPE_ARRAY:
		_owned.clear()
		for v: Variant in state[STATE_OWNED]:
			var id := str(v)
			if id != "" and not _owned.has(id) and str(GameData.get_record(id).get("type", "")) == "weapon":
				_owned.append(id)
	var wanted := str(state.get(STATE_WEAPON, "")) if typeof(state.get(STATE_WEAPON)) == TYPE_STRING else ""
	var rec := GameData.get_record(wanted)
	if wanted != "" and str(rec.get("type", "")) == "weapon":
		if not _owned.has(wanted):
			_owned.append(wanted)
		if wanted != weapon_id():
			_apply_weapon(rec, false)
	elif weapon_id() != "" and not _owned.has(weapon_id()):
		_owned.append(weapon_id())
	_was_too_small = is_too_small()


func capture_state(out: Dictionary) -> void:
	out[STATE_WEAPON] = weapon_id()
	var owned_list: Array = []
	for id in _owned:
		owned_list.append(id)
	out[STATE_OWNED] = owned_list


func debug_info(out: Dictionary) -> void:
	out["weapon"] = "%s x%.2f%s" % [weapon_id(), effective_weapon_scale(), TOO_SMALL_SUFFIX if is_too_small() else ""]
