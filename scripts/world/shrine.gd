class_name Shrine
extends Interactable
## A shrine (P05, plan §2.7.4 and §3.5): heals, saves (through events P06 listens to) and
## grows the giant. One record of type "shrine" (shrine_id) says what it offers; world_id is
## its placed, persistent id and its checkpoint id (valley.shrine.grove).
##
## - Activation: the first time per level visit the player comes within the record's
##   activation_radius_m (14), activate() runs: a free Rest when the record has
##   first_activation_rest, then checkpoint_reached(tick, world_id, "shrine") (records with
##   checkpoint) and shrine_activated(tick, world_id). It is polled from a Sim POST_RESOLVE hook,
##   so it happens inside the deterministic tick. P20 (plan M6-M9 §2.6): "per visit", not per
##   node - GameSession.activated_this_visit / mark_activated - so a shrine whose streamed chunk
##   is freed and made again in the same visit gives no second free rest or checkpoint (a reload
##   or a travel starts a new visit).
## - interact (E): emits ui_screen_requested("shrine", {"shrine": self, ...}); GameSession (P06)
##   takes a checkpoint before the ScreenStack opens the shrine screen.
## - rest(): health, stamina and essence to their maxima and debuffs (slows) removed; fury and
##   cooldowns are kept. Emits shrine_rested.
## - can_grow() / grow(): the Grow tab and the Valley bot; they wrap PlayerGrowth.check_growth
##   and grow_to with this shrine's gates (allows_growth, max_stage, growth_requires_flags, and P26's
##   growth_requires_conditions: a world shrine waits for world.kingsgate.lit or a count of oaths;
##   growth_waiting_text() is the line it shows meanwhile).
## Children: SpawnPoint (a CheckpointMarker whose checkpoint_id is set to world_id) and
## GrowthPad (a Marker3D at an open spot with stage-3 clearance). Group "shrines".
## P39f: Visual/Name (the record's name) hides while a screen is open (ScreenStack.HIDE_UNDER_SCREENS).

const GROUP := "shrines"
const DEFAULT_ACTIVATION_RADIUS_M := 14.0
const HOOK_ORDER := 50   ## POST_RESOLVE; GameSession drains its checkpoint queue at 200

## Placed, persistent id (= the checkpoint id), e.g. "valley.shrine.grove".
@export var world_id := ""
## The "shrine" record this shrine uses, e.g. "shrine.grove".
@export var shrine_id := "shrine.sandbox"

var _activated := false
var _glow: Node3D


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)


func _ready() -> void:
	if interact_id == "":
		interact_id = world_id
	var spawn := get_node_or_null("SpawnPoint")
	if spawn != null and "checkpoint_id" in spawn and world_id != "":
		spawn.set("checkpoint_id", world_id)
	_glow = get_node_or_null("Visual/Glow") as Node3D
	if _glow != null:
		_glow.visible = false
	var label := get_node_or_null("Visual/Name") as Label3D
	if label != null:
		label.text = display_name()
		# P39f: the name keeps one size on screen (the shrine builder), so it read through the shrine window's
		# see-through panel: it hides while a screen is open, as the HUD does (ScreenStack.HIDE_UNDER_SCREENS).
		label.add_to_group(ScreenStack.HIDE_UNDER_SCREENS)
		label.visible = not ScreenStack.any_open_in(get_tree())
	if record().is_empty():
		push_error("Shrine %s: unknown shrine record '%s'" % [world_id, shrine_id])
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_sim_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


# --------------------------------------------------------------------------- record

## The shrine record ({} when shrine_id is unknown).
func record() -> Dictionary:
	return GameData.get_record(shrine_id)


func display_name() -> String:
	return str(record().get("display_name", "Shrine"))


func activation_radius_m() -> float:
	return float(record().get("activation_radius_m", DEFAULT_ACTIVATION_RADIUS_M))


func is_activated() -> bool:
	return _activated


## Where the player stands to grow: GrowthPad, else the SpawnPoint, else the shrine itself.
func growth_pad_position() -> Vector3:
	for n: String in ["GrowthPad", "SpawnPoint"]:
		var m := get_node_or_null(n) as Node3D
		if m != null:
			return m.global_position
	return global_position


# --------------------------------------------------------------------------- activation

func _on_sim_tick(_tick: int) -> void:
	if _activated or not is_inside_tree():
		return
	var p := get_tree().get_first_node_in_group("player") as GiantPlayer
	if p == null or not p.is_inside_tree() or not p.entity.is_alive():
		return
	if horizontal_distance(p.global_position, global_position) <= activation_radius_m():
		activate(p)


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## First activation per level visit: the free Rest (first_activation_rest), then
## checkpoint_reached (records with checkpoint) and shrine_activated. Returns true only for that
## first call; a shrine made again in the same visit (GameSession.activated_this_visit) only
## lights its glow.
func activate(player: GiantPlayer) -> bool:
	if _activated:
		return false
	_activated = true
	if world_id != "" and GameSession.activated_this_visit(world_id):
		if _glow != null:
			_glow.visible = true
		return false
	if world_id != "":
		GameSession.mark_activated(world_id)
	var rec := record()
	if bool(rec.get("first_activation_rest", true)) and player != null:
		_restore(player)
	if _glow != null:
		_glow.visible = true
	if bool(rec.get("checkpoint", true)):
		Events.checkpoint_reached.emit(Sim.tick, world_id, "shrine")
	Events.shrine_activated.emit(Sim.tick, world_id)
	return true


# --------------------------------------------------------------------------- interaction

func prompt_text(_player: GiantPlayer) -> String:
	return "Rest at the %s" % display_name()


func interact(player: GiantPlayer) -> void:
	activate(player)
	Events.ui_screen_requested.emit("shrine", {"shrine": self, "world_id": world_id, "shrine_id": shrine_id})


## Rest: health, stamina and essence back to their maxima (records with rest_heals) and
## debuffs removed; fury, buffs and cooldowns are kept. Emits shrine_rested.
## {"ok", "message", "healed"} (healed: the health restored).
func rest(player: GiantPlayer) -> Dictionary:
	if player == null or not player.entity.is_alive():
		return {"ok": false, "message": "The dead cannot rest.", "healed": 0.0}
	var healed := 0.0
	if bool(record().get("rest_heals", true)):
		healed = _restore(player)
	Events.shrine_rested.emit(Sim.tick, world_id)
	return {"ok": true, "message": "You rest at the %s. Health, stamina and essence are restored." % display_name(),
		"healed": healed}


## The pools to their maxima and every Debuff status removed. Returns the health restored.
func _restore(player: GiantPlayer) -> float:
	var c := player.entity.combatant
	var pools := c.pools
	var missing := pools.health_max - pools.health
	if missing > 0.0:
		player.entity.heal(missing, world_id)
	pools.stamina = pools.stamina_max
	pools.essence = pools.essence_max
	for id: String in c.statuses.active_ids():
		var def := GameData.get_status(id)
		if def != null and def.tags.has("Debuff"):
			c.statuses.remove(id)
			Events.status_expired.emit(Sim.tick, player.entity.entity_id, id)
	return maxf(missing, 0.0)


## {ok, reason, message} for growing to `target` here (PlayerGrowth.check_growth).
func can_grow(player: GiantPlayer, target: int) -> Dictionary:
	if player == null or player.growth == null:
		return {"ok": false, "reason": "no_profile", "message": "Nothing here can grow."}
	return player.growth.check_growth(target, self)


## Grows the player to `target` here (PlayerGrowth.grow_to): the result of the checks, plus
## "from", "to" and "summary" on success.
func grow(player: GiantPlayer, target: int) -> Dictionary:
	if player == null or player.growth == null:
		return {"ok": false, "reason": "no_profile", "message": "Nothing here can grow."}
	return player.growth.grow_to(target, self, "shrine")


## P26 (plan M6-M9 §2.9): while one of the record's growth_requires_conditions does not hold, the
## refusal growing here would give (its growth_conditions_text line); "" when they all hold.
func growth_waiting_text() -> String:
	var r := PlayerGrowth.conditions_gate(record(), Quests.condition_context())
	return "" if bool(r.ok) else str(r.message)


## The next stage this shrine offers the player (its stage + 1), or 0 when it offers none
## (no growth here, already at the shrine's limit, or no profile for it).
func offered_stage(player: GiantPlayer) -> int:
	if player == null or player.growth == null:
		return 0
	var rec := record()
	var next: int = player.growth.stage() + 1
	if not bool(rec.get("allows_growth", false)) or next > int(rec.get("max_stage", 1)):
		return 0
	if player.growth.profile_for_stage(next).is_empty():
		return 0
	return next
