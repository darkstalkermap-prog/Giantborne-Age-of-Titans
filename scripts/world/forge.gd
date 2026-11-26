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
##   leaves the owned list, Events.upgrade_applied(tick, from, to) and a HUD line.
## - Refit chains and forge tiers (P31, plan M6-M9 §2.11, decision 24): a weapon's upgrade is one
##   step of a chain (base -> reinforced -> titanforged), each step naming the forge tier it needs
##   (upgrade.forge_tier, iron by default). An iron forge (`tier` "iron": the Valley's two, the
##   Kingsgate anvil, Brannock's) does the iron steps; a titan forge ("titan": the Titan Forge, Fort
##   Aldmere's, Skarn's hearth) does both. A titan step at an iron forge is refused with reason
##   "forge_tier" and the forge says where to go; the offer still shows the step (to, cost).
##
## Children (forge.tscn, tools/builders/forge.gd): Hearth and Anvil (StaticBody3D on WORLD), Fire.
## Group "forges".

const REASONS := ["closed", "no_player", "busy", "no_upgrade", "unknown_upgrade", "missing_items", "forge_tier"]
const DEFAULT_CLOSED_MESSAGE := "The forge is cold. Its smith will not work for you."
## P31: the forge tiers in rank order (an iron forge reinforces; a titan forge also titanforges).
const TIERS := ["iron", "titan", "colossus"]   # C4: a colossus forge (Last Hearth's anvil) does every step
const TIER_MESSAGE := "Titanforging needs a titan forge - this forge can only reinforce."
## C4: a step that needs the colossus tier (rimforging: Last Hearth's Colossus Anvil).
const COLOSSUS_MESSAGE := "Rimforging needs the Colossus Anvil at Last Hearth - no smaller forge works at a colossus's size."

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
## P31: "iron" reinforces; "titan" also titanforges (TIERS).
@export var tier := "iron"

## The result of the last upgrade() (the screen shows it).
var last_result: Dictionary = {}


## P31: true when this forge can do a refit step needing `step_tier` (a titan forge does every step).
func does_tier(step_tier: String) -> bool:
	return maxi(0, TIERS.find(tier)) >= maxi(0, TIERS.find(step_tier))


func _ready() -> void:
	add_to_group("forges")
	if interact_id == "":
		interact_id = world_id
	if world_id == "":
		push_error("Forge %s has no world_id" % get_path())
	attach_look()


# --------------------------------------------------------------------------- C3: the smithy

const SMITHY := "res://scenes/world/smithy.tscn"
## A titan-tier forge built at a giant's scale (the condition_forge kind's hearth along -z) wears the smithy this big.
const BIG_SMITHY_SCALE := 1.55
## C4: a forge's own look scale (0: by the rule above) - Last Hearth's Colossus Anvil wears its smithy at a colossus's size.
@export var look_scale := 0.0
const LOOK_POLL_S := 0.5

var look: ForgeLook = null


## C3 (decision C3-6): puts the smithy on (scenes/world/smithy.tscn: ForgeLook) over the forge's old boxes, which
## are hidden (their solids stay): forge.tscn's hearth stands behind its root (+z), a condition forge's at -z and
## larger. Lit while the forge is open (polled every LOOK_POLL_S: a condition or a faction can open it). Once.
func attach_look() -> void:
	if look != null or not ResourceLoader.exists(SMITHY):
		return
	var big := get_node_or_null("Hearth") == null
	look = (load(SMITHY) as PackedScene).instantiate() as ForgeLook
	if look == null:
		return
	look.name = "Smithy"
	if big:
		look.rotation.y = PI
		look.scale = Vector3.ONE * BIG_SMITHY_SCALE
	if look_scale > 0.0:
		look.scale = Vector3.ONE * look_scale
	_hide_old_look(self)
	add_child(look)
	look.set_lit(is_open())
	var t := Timer.new()
	t.name = "LookPoll"
	t.wait_time = LOOK_POLL_S
	t.autostart = true
	t.timeout.connect(_poll_look)
	add_child(t)


func _poll_look() -> void:
	if look != null:
		look.set_lit(is_open())


func _hide_old_look(n: Node) -> void:
	for c in n.get_children():
		if c == look:
			continue
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).visible = false
		_hide_old_look(c)


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
	return "Reforge at %s" % TextUtil.with_the(display_name)   # M9 gate (lane review): not "at the The Giantforge"


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
## "to_name", "to_multiplier", "to_fit", "cost": [{"item", "name", "count", "held"}], "forge_tier"
## (P31: the tier the step needs), "perk" (P31: the new weapon's perk text, "" = none)} ("to" ""
## when the weapon has no upgrade).
func offer(player: GiantPlayer) -> Dictionary:
	var out := {"from": "", "from_name": "", "to": "", "to_name": "", "to_multiplier": 0.0,
		"to_fit": 0, "cost": [], "forge_tier": "iron", "perk": ""}
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
	out.forge_tier = str((up as Dictionary).get("forge_tier", "iron"))
	var perk: Variant = to.get("perk")
	out.perk = str((perk as Dictionary).get("text", "")) if typeof(perk) == TYPE_DICTIONARY else ""
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
	if not does_tier(str(o.get("forge_tier", "iron"))):
		return _fail("forge_tier", COLOSSUS_MESSAGE if str(o.get("forge_tier", "")) == "colossus" else TIER_MESSAGE)
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


# --------------------------------------------------------------------------- B1: armour, titan weapons, refits

## B1: the material traits this forge works beyond iron and hide ("titan_stone": Millford's quarry forge, from the
## world layout's `works`). A recipe or a refit step whose "works" is not here is shown but refused (reason "works").
@export var works := PackedStringArray()

const B1_REASONS := ["closed", "no_player", "busy", "unknown", "owned", "not_owned", "max_tier", "forge_tier", "works",
	"locked", "missing_items", "no_perk", "same_perk"]
const WORKS_MESSAGE := "This forge cannot work it: %s."
const LOCKED_MESSAGE := "Not yet: %s."


## True when this forge works the trait `what` ("" = every forge does).
func does_work(what: String) -> bool:
	return what == "" or works.has(what)


## The recipes of `tab` ("armour" or "weapon"): every recipe record that makes that kind of thing, sorted by its order
## then id, each with can_craft's verdict: [{"recipe", "makes", "name", "slot", "set", "cost", "ok", "reason",
## "message"}]. A recipe this forge cannot work, or whose flag does not hold yet, is listed refused.
func recipes(player: GiantPlayer, tab: String) -> Array:
	var rows: Array = []
	for rec: Dictionary in GameData.records_of_type("recipe"):
		var makes := str(rec.get("makes", ""))
		if (tab == "armour") != makes.begins_with("armour."):
			continue
		rows.append([int(rec.get("order", 500)), str(rec.id)])
	rows.sort()
	var out: Array = []
	for r: Array in rows:
		out.append(can_craft(player, str(r[1])))
	return out


## Whether recipe `recipe_id` can be made here now: {"ok", "reason" (B1_REASONS), "message", "recipe", "makes",
## "name", "slot", "set", "cost": [{"item", "name", "count", "held"}]}.
func can_craft(player: GiantPlayer, recipe_id: String) -> Dictionary:
	var rec := GameData.get_record(recipe_id)
	var makes := str(rec.get("makes", ""))
	var made := GameData.get_record(makes)
	var o := {"recipe": recipe_id, "makes": makes, "name": str(made.get("display_name", makes)),
		"slot": str(made.get("slot", "")), "set": str(made.get("set", "")), "cost": cost_lines(rec.get("cost", [])),
		"ok": false, "reason": "", "message": ""}
	if rec.is_empty() or made.is_empty():
		o.merge(_fail("unknown", "This forge does not know that work."), true)
		return o
	var eq := _equipment()
	if makes.begins_with("armour.") and Armour.owns(eq, makes):
		o.merge(_fail("owned", "You have it already."), true)
		return o
	if makes.begins_with("weapon.") and player != null and is_instance_valid(player) and player.equipment != null \
			and player.equipment.owns(makes):
		o.merge(_fail("owned", "You carry it already."), true)
		return o
	o.merge(_b1_check(player, str(rec.get("forge_tier", "iron")), str(rec.get("works", "")),
		str(rec.get("requires_flag", "")), str(rec.get("where", "")), o.cost), true)
	if bool(o.ok):
		o.message = "Make the %s." % str(o.name)
	return o


## Makes recipe `recipe_id` (see can_craft for the refusals, which change nothing): the cost leaves the inventory; an
## armour piece is owned at tier 1 (not worn: the Character menu puts it on), a weapon is granted and equipped.
## Events.armour_changed(tick, "crafted", made id) and a HUD line. {ok, reason, message, makes}.
func craft(player: GiantPlayer, recipe_id: String) -> Dictionary:
	var check := can_craft(player, recipe_id)
	if not bool(check.ok):
		last_result = check
		return check
	_pay(check.cost)
	var makes := str(check.makes)
	if makes.begins_with("armour."):
		Armour.grant(_equipment(), makes)
	else:
		var r: Dictionary = player.equipment.grant_weapon(makes, true)
		if not bool(r.get("ok", false)):
			push_error("Forge %s: equipping %s failed after paying (%s)" % [world_id, makes, r.get("message", "")])
	Events.armour_changed.emit(Sim.tick, "crafted", makes)
	var msg := "Made: %s%s" % [str(check.name), "" if makes.begins_with("weapon.") else " (put it on in the Character menu)"]
	Events.hud_message.emit(msg, "good")
	last_result = {"ok": true, "reason": "", "message": msg, "makes": makes}
	return last_result


## Whether owned armour piece `armour_id` can be taken to its next tier here now: can_craft's shape with "id",
## "from_tier", "to_tier".
func can_refit(player: GiantPlayer, armour_id: String) -> Dictionary:
	var eq := _equipment()
	var step := Armour.next_refit(eq, armour_id)
	var t := Armour.tier_of(eq, armour_id)
	var o := {"id": armour_id, "name": Armour.piece_name(armour_id, t), "from_tier": t, "to_tier": t + 1,
		"cost": cost_lines(step.get("cost", [])), "ok": false, "reason": "", "message": ""}
	if Armour.piece(armour_id).is_empty():
		o.merge(_fail("unknown", "This forge does not know that piece."), true)
		return o
	if not Armour.owns(eq, armour_id):
		o.merge(_fail("not_owned", "You do not have it."), true)
		return o
	if step.is_empty():
		o.merge(_fail("max_tier", "%s is as good as a forge can make it." % str(o.name)), true)
		return o
	o.merge(_b1_check(player, str(step.get("forge_tier", "iron")), str(step.get("works", "")), "",
		_where_of(armour_id), o.cost), true)
	if bool(o.ok):
		o.message = "Reforge it to %s." % Armour.piece_name(armour_id, t + 1)
	return o


## Takes `armour_id` to its next tier (can_refit's refusals change nothing). Events.armour_changed(tick, "refit", id).
func refit(player: GiantPlayer, armour_id: String) -> Dictionary:
	var check := can_refit(player, armour_id)
	if not bool(check.ok):
		last_result = check
		return check
	_pay(check.cost)
	Armour.set_tier(_equipment(), armour_id, int(check.to_tier))
	_refresh(player)
	Events.armour_changed.emit(Sim.tick, "refit", armour_id)
	var msg := "Reforged: %s" % Armour.piece_name(armour_id, int(check.to_tier))
	Events.hud_message.emit(msg, "good")
	last_result = {"ok": true, "reason": "", "message": msg, "id": armour_id, "tier": int(check.to_tier)}
	return last_result


## Whether perk `perk_id` (one of the piece's own list) can be set on owned piece `armour_id` here now.
func can_set_perk(player: GiantPlayer, armour_id: String, perk_id: String) -> Dictionary:
	var eq := _equipment()
	var o := {"id": armour_id, "perk": perk_id, "name": str(Armour.perk(perk_id).get("display_name", perk_id)),
		"cost": cost_lines(Armour.perk_cost(armour_id)), "ok": false, "reason": "", "message": ""}
	if Armour.piece(armour_id).is_empty():
		o.merge(_fail("unknown", "This forge does not know that piece."), true)
		return o
	if not Armour.owns(eq, armour_id):
		o.merge(_fail("not_owned", "You do not have it."), true)
		return o
	if not (Armour.piece(armour_id).get("perks", []) as Array).has(perk_id):
		o.merge(_fail("no_perk", "That piece cannot take that perk."), true)
		return o
	if Armour.perk_of(eq, armour_id) == perk_id:
		o.merge(_fail("same_perk", "It has that perk already."), true)
		return o
	o.merge(_b1_check(player, "iron", Armour.works_of(armour_id), "", _where_of(armour_id), o.cost), true)
	if bool(o.ok):
		o.message = "Work %s into it." % str(o.name)
	return o


## Sets the perk (can_set_perk's refusals change nothing). Events.armour_changed(tick, "perk", armour id).
func set_perk(player: GiantPlayer, armour_id: String, perk_id: String) -> Dictionary:
	var check := can_set_perk(player, armour_id, perk_id)
	if not bool(check.ok):
		last_result = check
		return check
	_pay(check.cost)
	Armour.set_perk(_equipment(), armour_id, perk_id)
	_refresh(player)
	Events.armour_changed.emit(Sim.tick, "perk", armour_id)
	var msg := "%s: %s" % [Armour.display_name(armour_id), str(Armour.perk(perk_id).get("text", check.name))]
	Events.hud_message.emit(msg, "good")
	last_result = {"ok": true, "reason": "", "message": msg, "id": armour_id, "perk": perk_id}
	return last_result


## [{"item", "name", "count", "held"}] of a cost list.
static func cost_lines(cost: Variant) -> Array:
	var out: Array = []
	for c: Variant in cost if typeof(cost) == TYPE_ARRAY else []:
		if typeof(c) != TYPE_DICTIONARY:
			continue
		var item := str(c.get("item", ""))
		out.append({"item": item, "name": str(GameData.get_record(item).get("display_name", item)),
			"count": int(c.get("count", 1)), "held": WorldState.count_of(item)})
	return out


func _b1_check(player: GiantPlayer, step_tier: String, what: String, flag: String, where: String,
		cost: Array) -> Dictionary:
	if not is_open():
		return _fail("closed", blocked_reason(player))
	if player == null or not is_instance_valid(player) or player.equipment == null:
		return _fail("no_player", "There is no one to work for.")
	if player.controller.state != CombatController.State.LOCOMOTION:
		return _fail("busy", "Finish what you are doing first.")
	if not does_tier(step_tier):
		return _fail("forge_tier", "This needs a titan forge - this forge works only iron.")
	if not does_work(what):
		return _fail("works", WORKS_MESSAGE % (where if where != "" else "it needs another forge"))
	if flag != "" and not BreakableProp.flag_truthy(WorldState.get_flag(flag, null)):
		return _fail("locked", LOCKED_MESSAGE % (where if where != "" else "its makers are not ready"))
	var missing := PackedStringArray()
	for c: Dictionary in cost:
		if int(c.held) < int(c.count):
			missing.append("%d %s (you have %d)" % [int(c.count), str(c.name), int(c.held)])
	if not missing.is_empty():
		return _fail("missing_items", "It needs %s." % ", ".join(missing))
	return {"ok": true, "reason": "", "message": ""}


func _pay(cost: Array) -> void:
	for c: Dictionary in cost:
		WorldState.remove_item(str(c.item), int(c.count), "forge:%s" % world_id)


## Where a piece's set is worked (its recipe's "where"), for a refusal.
static func _where_of(armour_id: String) -> String:
	for rec: Dictionary in GameData.records_of_type("recipe"):
		if str(rec.get("makes", "")) == armour_id:
			return str(rec.get("where", ""))
	return ""


static func _equipment() -> Dictionary:
	var eq: Variant = GameSession.expansion.get("equipment")
	if typeof(eq) != TYPE_DICTIONARY:
		GameSession.expansion["equipment"] = Armour.empty()
		eq = GameSession.expansion.equipment
	for k: String in ["slots", "pieces", "hidden"]:
		if typeof((eq as Dictionary).get(k)) != TYPE_DICTIONARY:
			eq[k] = Armour.empty()[k]
	return eq


static func _refresh(player: GiantPlayer) -> void:
	Armour.refresh_player(player)
