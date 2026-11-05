class_name Forge
extends Interactable
## A forge (plan §2.7.4, §3.14 design 6, §4.7): the slice's one upgrade interaction. It reforges
## the equipped weapon into its reinforced variant (the weapon record's `upgrade {to, cost}`): more
## damage, and it fits a stage-3 giant (fit_max_stage 3). The village smithy works only for a
## helpful giant (requires_flag_values {"quest.village.outcome": ["help_cache", "help_ogre"]}); the
## ruins' Giantforge always works.
##
## - E (interact) opens the forge screen (Events.ui_screen_requested("forge", {"forge": self}));
##   a forge closed by its flags shows closed_message instead (blocked_reason).
## - can_upgrade(player) -> {ok, reason, message} + the offer (from, to, names, cost lines): the
##   forge is open (every requires_flags flag truthy; every requires_flag_values flag holds one of
##   its allowed values), the giant can act (LOCOMOTION), the equipped weapon has an upgrade and
##   its cost items are held. Reasons in REASONS order.
## - upgrade(player): can_upgrade, then the cost leaves the inventory (WorldState.remove_item),
##   the reinforced weapon is granted and equipped (PlayerEquipment.grant_weapon), the old weapon
##   leaves the owned list, Events.upgrade_applied(tick, from, to) and a HUD line. The reinforced
##   weapon has no upgrade of its own, so the same weapon cannot be reforged twice.
##
## Children (forge.tscn, tools/builders/forge.gd): Hearth and Anvil (StaticBody3D on WORLD), Fire.
## Group "forges".

const REASONS := ["closed", "no_player", "busy", "no_upgrade", "unknown_upgrade", "missing_items"]
const DEFAULT_CLOSED_MESSAGE := "The forge is cold. Its smith will not work for you."

## Placed, persistent id, e.g. "valley.ruins.giantforge".
@export var world_id := ""
@export var display_name := "Forge"
## Flags that must all be truthy for the forge to work.
@export var requires_flags := PackedStringArray()
## Flag id -> allowed value, or an Array of allowed values ("quest.village.outcome": [help_cache,
## help_ogre]).
@export var requires_flag_values: Dictionary = {}
## Shown (warning) when E is pressed while the forge is closed.
@export var closed_message := DEFAULT_CLOSED_MESSAGE

## The result of the last upgrade() (the screen shows it).
var last_result: Dictionary = {}


func _ready() -> void:
	add_to_group("forges")
	if interact_id == "":
		interact_id = world_id
	if world_id == "":
		push_error("Forge %s has no world_id" % get_path())


# --------------------------------------------------------------------------- state

## True when every requires_flags flag is truthy and every requires_flag_values flag holds one of
## its allowed values.
func is_open() -> bool:
	return flags_allow(requires_flags, requires_flag_values, Callable(WorldState, "get_flag"))


static func flags_allow(flags: PackedStringArray, values: Dictionary, get_flag: Callable) -> bool:
	for f in flags:
		if not BreakableProp.flag_truthy(get_flag.call(f, null)):
			return false
	for f: Variant in values:
		if not value_allowed(get_flag.call(str(f), null), values[f]):
			return false
	return true


## `value` is `allowed` (equal), or one of `allowed` when that is an array.
static func value_allowed(value: Variant, allowed: Variant) -> bool:
	if value == null:
		return false
	if typeof(allowed) == TYPE_ARRAY or typeof(allowed) == TYPE_PACKED_STRING_ARRAY:
		for a: Variant in allowed:
			if _same(value, a):
				return true
		return false
	return _same(value, allowed)


static func _same(a: Variant, b: Variant) -> bool:
	var a_num := typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT
	var b_num := typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT
	if a_num and b_num:
		return float(a) == float(b)
	if typeof(a) in [TYPE_STRING, TYPE_STRING_NAME] and typeof(b) in [TYPE_STRING, TYPE_STRING_NAME]:
		return str(a) == str(b)
	return typeof(a) == typeof(b) and a == b


# --------------------------------------------------------------------------- Interactable

func prompt_text(_player: GiantPlayer) -> String:
	return "Reforge at the %s" % display_name


func can_interact(_player: GiantPlayer) -> bool:
	return is_open()


func blocked_reason(_player: GiantPlayer) -> String:
	return closed_message if closed_message != "" else DEFAULT_CLOSED_MESSAGE


func interact(player: GiantPlayer) -> void:
	if not can_interact(player):
		return
	Events.ui_screen_requested.emit("forge", {"forge": self, "world_id": world_id, "player": player})


# --------------------------------------------------------------------------- the upgrade

## The equipped weapon's reforge, whether or not it is possible now: {"from", "from_name", "to",
## "to_name", "to_multiplier", "to_fit", "cost": [{"item", "name", "count", "held"}]} ("to" ""
## when the weapon has no upgrade).
func offer(player: GiantPlayer) -> Dictionary:
	var out := {"from": "", "from_name": "", "to": "", "to_name": "", "to_multiplier": 0.0,
		"to_fit": 0, "cost": []}
	if player == null or not is_instance_valid(player):
		return out
	var w := player.current_weapon()
	out.from = str(w.get("id", ""))
	out.from_name = str(w.get("display_name", out.from))
	var up: Variant = w.get("upgrade")
	if typeof(up) != TYPE_DICTIONARY:
		return out
	out.to = str((up as Dictionary).get("to", ""))
	var to := GameData.get_record(out.to)
	out.to_name = str(to.get("display_name", out.to))
	out.to_multiplier = float(to.get("damage_multiplier", 0.0))
	out.to_fit = int(to.get("fit_max_stage", 10))
	var cost: Array = []
	for c: Variant in (up as Dictionary).get("cost", []):
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var item := str(c.get("item", ""))
		cost.append({"item": item, "name": str(GameData.get_record(item).get("display_name", item)),
			"count": int(c.get("count", 1)), "held": WorldState.count_of(item)})
	out.cost = cost
	return out


## {ok, reason, message} for reforging the equipped weapon now, merged with offer(player).
func can_upgrade(player: GiantPlayer) -> Dictionary:
	var o := offer(player)
	var r := _check(player, o)
	o.merge(r, true)
	return o


func _check(player: GiantPlayer, o: Dictionary) -> Dictionary:
	if not is_open():
		return _fail("closed", blocked_reason(player))
	if player == null or not is_instance_valid(player) or player.equipment == null:
		return _fail("no_player", "There is no one to reforge for.")
	if player.controller.state != CombatController.State.LOCOMOTION:
		return _fail("busy", "Finish what you are doing first.")
	if str(o.to) == "":
		return _fail("no_upgrade", "The %s cannot be reforged any further." % str(o.from_name))
	if str(GameData.get_record(str(o.to)).get("type", "")) != "weapon":
		return _fail("unknown_upgrade", "This forge does not know how to reforge the %s." % str(o.from_name))
	var missing := PackedStringArray()
	for c: Dictionary in o.cost:
		if int(c.held) < int(c.count):
			missing.append("%d %s (you have %d)" % [int(c.count), str(c.name), int(c.held)])
	if not missing.is_empty():
		return _fail("missing_items", "Reforging needs %s." % ", ".join(missing))
	return {"ok": true, "reason": "", "message": "Reforge the %s into the %s." % [str(o.from_name), str(o.to_name)]}


## Reforges the equipped weapon (see can_upgrade for the refusals, which change nothing): the cost
## is taken, the reinforced weapon granted, equipped and the old one dropped from the owned list,
## Events.upgrade_applied. {ok, reason, message, from, to}.
func upgrade(player: GiantPlayer) -> Dictionary:
	var check := can_upgrade(player)
	if not check.ok:
		last_result = check
		return check
	var from := str(check.from)
	var to := str(check.to)
	for c: Dictionary in check.cost:
		WorldState.remove_item(str(c.item), int(c.count), "forge:%s" % world_id)
	var equipped: Dictionary = player.equipment.grant_weapon(to, true)
	if not bool(equipped.get("ok", false)):
		push_error("Forge %s: equipping %s failed after paying (%s)" % [world_id, to, equipped.get("message", "")])
	var owned: Array = []
	for id in player.equipment.owned():
		if id != from:
			owned.append(id)
	player.equipment.apply_state({PlayerEquipment.STATE_OWNED: owned})
	Events.upgrade_applied.emit(Sim.tick, from, to)
	var msg := "Reforged: %s" % str(check.to_name)
	Events.hud_message.emit(msg, "good")
	last_result = {"ok": true, "reason": "", "message": msg, "from": from, "to": to}
	return last_result


static func _fail(reason: String, message: String) -> Dictionary:
	return {"ok": false, "reason": reason, "message": message}
