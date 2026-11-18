class_name PlayerAppearance
extends PlayerComponent
## The giant's look (P42; plan M10 §2.2, §2.4, §2.10, §2.11; decisions 5, 14, 15, 16): the character's
## appearance record and the look the rig draws. Presentation only: no edge, no pre-action, no
## movement hook; nothing in the simulation reads it, and it never draws from Sim.rng.
##
##   * apply_state / capture_state move the optional "appearance" key: capture writes it only when the
##     character has a record (old saves, fixtures, the bots and command-line starts carry none, so the
##     exact comparisons of whole characters stay as they were); a later build's record (its "v" above
##     1) is written back unchanged.
##   * record() is the record the giant wears: the character's, else the --appearance= preset's
##     (Appearance.cli_preset: in every mode, the sandbox and the soak included), else the default.
##   * set_record(record) - the shrine's "Keep this look" (P44) - stores it (sanitized), applies it and
##     emits Events.appearance_changed(tick, entity_id): GameSession re-takes the shrine's checkpoint.
##   * On Events.ancestry_chosen the look is resolved again, so a `mark: "auto"` record shows the line's
##     mark at once (no save write); for a look of the player's own (a record, or a save from before M10:
##     the flag appearance.legacy_save) the flag appearance.mark_shown then brings up the one-time
##     tutorial.appearance_mark. Command-line starts and the bots have neither, so their runs set no flag.
##   * The look reaches the giant through player.rig.apply_look(look) when the rig has that method
##     (P43's SkinnedRig); on the stylized rig of W25 it is stored only.

## The flag that shows tutorial.appearance_mark (set once a line's mark first shows on the player's own
## look); the flag GameSession sets when a loaded save had no look.
const MARK_SHOWN_FLAG := "appearance.mark_shown"
const LEGACY_FLAG := "appearance.legacy_save"

var _record: Dictionary = {}     ## the character's own record ({} = none)
var _has_record := false
var _look: Dictionary = {}
var _ancestry := ""


func setup(p: GiantPlayer) -> void:
	super(p)
	if not Events.ancestry_chosen.is_connected(_on_ancestry_chosen):
		Events.ancestry_chosen.connect(_on_ancestry_chosen)
	refresh()


func on_exit() -> void:
	if Events.ancestry_chosen.is_connected(_on_ancestry_chosen):
		Events.ancestry_chosen.disconnect(_on_ancestry_chosen)


func apply_state(state: Dictionary) -> void:
	_has_record = state.has("appearance")
	_ancestry = str(state.get("ancestry", "")) if typeof(state.get("ancestry")) == TYPE_STRING else ""
	if _has_record:
		var raw: Variant = state.appearance
		_record = Appearance.sanitize(raw, _ancestry).record if not Appearance.is_future(raw) \
			else (raw as Dictionary).duplicate(true)
	else:
		_record = {}
	refresh()


func capture_state(out: Dictionary) -> void:
	if _has_record:
		out["appearance"] = _record.duplicate(true)
	else:
		out.erase("appearance")


## True when the character carries a record of its own (the creator wrote one).
func has_record() -> bool:
	return _has_record


## The record the giant wears now (a copy): its own, else the --appearance= preset's, else the default.
func record() -> Dictionary:
	var character := {"ancestry": ancestry()}
	if _has_record:
		character["appearance"] = _record
	return Appearance.resolve(character)


## The concrete look drawn now (Appearance.to_look of record() for the giant's line; a copy).
func look() -> Dictionary:
	return _look.duplicate(true)


## The giant's line now: the progression's ancestry when it has one, else the applied state's.
func ancestry() -> String:
	if player != null and player.progression != null and "ancestry" in player.progression:
		return str(player.progression.get("ancestry"))
	return _ancestry


## The creator's "Keep this look" (P44): stores the record (sanitized; a later build's record as it is),
## applies it and emits Events.appearance_changed so GameSession re-takes the shrine's checkpoint.
func set_record(new_record: Dictionary) -> void:
	_record = Appearance.sanitize(new_record, ancestry()).record if not Appearance.is_future(new_record) \
		else new_record.duplicate(true)
	_has_record = true
	refresh()
	if player != null and player.entity != null:
		Events.appearance_changed.emit(Sim.tick, player.entity.entity_id)


## The creator's Cancel and tests: puts `previous` back as the record without a write or an event
## ({} = no record of its own).
func restore_record(previous: Dictionary) -> void:
	_has_record = not previous.is_empty()
	_record = previous.duplicate(true) if _has_record else {}
	refresh()


## Resolves the look again (record, line) and hands it to the rig when the rig can draw it.
func refresh() -> void:
	_look = Appearance.to_look(record(), ancestry())
	if player == null or player.rig == null:
		return
	if player.rig.has_method("apply_look"):
		player.rig.call("apply_look", _look.duplicate(true))


func _on_ancestry_chosen(_tick: int, ancestry_id: String) -> void:
	if player == null or not is_instance_valid(player) or not player.is_inside_tree():
		return
	var had_mark := not (_look.get("mark", {}) as Dictionary).is_empty()
	_ancestry = ancestry_id
	refresh()
	var shows_mark := not (_look.get("mark", {}) as Dictionary).is_empty()
	if shows_mark and not had_mark and str(record().get("mark", "")) == Appearance.MARK_AUTO \
			and (_has_record or QuestConditions.truthy(WorldState.flags.get(LEGACY_FLAG))):
		WorldState.try_set_flag(MARK_SHOWN_FLAG, true)


func debug_info(out: Dictionary) -> void:
	out["look"] = str(_record.get("preset", "")) if _has_record else ("cli:" + Appearance.cli_preset
		if Appearance.cli_preset != "" else "default")
