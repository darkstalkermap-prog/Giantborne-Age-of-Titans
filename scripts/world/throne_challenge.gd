class_name ThroneChallenge
extends BossArena
## E1: the challenge for the Stone Throne at the Moot - Orrik the Fetterer's fight (decisions E1-1, E1-4). P34's BossArena
## (the boss bar, the music, the disengage rule and its new attempt, the checkpoint blocker, the fight's end checkpoint)
## with what the challenge adds:
##   * **The warband**: the fetter-winches' Skarn crews are the arena's own (`warband_encounter`): brought in when the
##     fight engages (force-activated), kept when the arena clears intruders, brought back whole with a new attempt
##     (EncounterDirector.p34_reset_encounter), sent away when Orrik falls (the warband breaks: they leave the Moot).
##     The winches themselves are placed props (FetterWinch, `boss_id` this boss): they join by his phases.
##   * **The branch** (branch(): from Harrok's outcome in act one): "ally" - Harrok spared, or knelt to the talk ending -
##     brings Harrok himself to stand beside the giant (`ally_scene` at `ally_at`, a HarrokAlly) for every attempt; he
##     leaves again when the attempt ends; "vengeance" - Harrok slain (or, for a save that never settled him, the nearest:
##     a clan whose champion did not kneel; decision E1-5) - the giant fights alone. Both fight the same Orrik, the same
##     winches, in the same ring.
##   * `outcome_flag` is set when Orrik falls ("slain"), as the boss records' boss_outcome does for the quests.

const ALLY_OUTCOMES := ["spared", "yielded_talk"]
const HARROK_OUTCOME := "boss.harrok.outcome"

@export var warband_encounter := ""
## More of the warband's encounters (the world's reserve winches' crews, absent when the giant broke the winch camp).
@export var warband_encounters := PackedStringArray()
@export var ally_scene := "res://scenes/actors/harrok_ally.tscn"
## Where Harrok comes in (the arena's own frame; INF = no ally here).
@export var ally_at := Vector3.INF
## The clan that stands down when Orrik falls ("" = none) and the flag of Harrok holding the Moot (the ally branch).
@export var clan_faction := ""
@export var holds_flag := ""
## Tests force a branch ("" = by Harrok's outcome).
@export var branch_override := ""

var ally: Node3D = null
var allies_brought := 0


## "ally" when Harrok was spared (or knelt to the talk ending) in act one, else "vengeance".
static func branch_of(outcome: Variant) -> String:
	return "ally" if str(outcome) in ALLY_OUTCOMES else "vengeance"


func branch() -> String:
	return branch_override if branch_override != "" else branch_of(WorldState.get_flag(HARROK_OUTCOME))


func engage(tick: int = -1) -> void:
	var before := state
	super(tick)
	if state != State.ENGAGED or before == State.ENGAGED:
		return
	_bring_warband()
	_bring_ally()


## The warband's encounters (warband_encounter and warband_encounters).
func warbands() -> PackedStringArray:
	var out := PackedStringArray()
	if warband_encounter != "":
		out.append(warband_encounter)
	out.append_array(warband_encounters)
	return out


func _bring_warband() -> void:
	var d := _director()
	if d == null:
		return
	var any := false
	for id: String in warbands():
		if d.encounter_state(id) != "" and EncounterDirector.flags_allow(GameData.get_record(id)):
			d.force_activate(id)
			any = true
	if any:
		d.update_now()


func _bring_ally() -> void:
	if branch() != "ally" or ally_at == Vector3.INF or (ally != null and is_instance_valid(ally)):
		return
	if not ResourceLoader.exists(ally_scene):
		return
	var a := (load(ally_scene) as PackedScene).instantiate() as Node3D
	a.name = "HarrokAlly"
	a.set("boss_id", boss_id)
	get_parent().add_child(a)
	a.global_position = global_transform * ally_at
	ally = a
	allies_brought += 1


func _send_ally_away() -> void:
	if ally != null and is_instance_valid(ally):
		if ally.has_method("leave"):
			ally.call("leave")
		else:
			ally.queue_free()
	ally = null


func _p34_keeps(e: EnemyActor, d: EncounterDirector) -> bool:
	if d != null:
		for id: String in warbands():
			if d.members_of(id).has(e.entity_id):
				return true
	return super(e, d)


func _reset_attempt() -> void:
	super()
	var d := _director()
	if d != null:
		for id: String in warbands():
			if d.encounter_state(id) != "":
				d.p34_reset_encounter(id)
	_send_ally_away()


func _defeat(tick: int) -> void:
	super(tick)
	var d := _director()
	if d != null:
		for id: String in warbands():
			if d.encounter_state(id) != "":
				d.p37_deactivate(id)
	if ally != null and is_instance_valid(ally) and ally.has_method("on_victory"):
		ally.call("on_victory")
	# the world's answer: the clan stands down whatever the branch (with Harrok holding the Moot, or kneeling at the
	# oath-stone); with Harrok spared he holds the Moot from now on (his banner over the throne, him beside it)
	if clan_faction != "":
		FactionState.reconcile(clan_faction)
	if branch() == "ally" and holds_flag != "":
		WorldState.try_set_flag(holds_flag, true)

