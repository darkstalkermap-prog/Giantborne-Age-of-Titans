class_name NpcTalker
extends Interactable
## Talk to someone (plan §2.7.4, §3.15 design 4): an Interactable whose interact() emits
## Events.dialogue_requested(npc_id, dialogue_id); Quests starts the conversation and the
## dialogue screen opens on it. Usually a child of an NPC actor (P11b's elder), else standing on
## its own (tests, signs that talk).
##
## - npc_id: the speaker's entity id ("valley.village.elder"); empty = the parent's `entity_id`
##   (an NPC spawned by the director gets its id before entering the tree).
## - dialogue_id: the `dialogue` record; empty = the parent's record "dialogue" field (an `npc`
##   record names its dialogue).
## - The prompt is "Talk to <speaker>" (the dialogue's speaker) unless the scene sets another one.
## - Gone (no prompt) once its NPC is dead; E does nothing while the dialogue does not exist.
##   M8 gate (F5): "dead" is the parent's entity dead, the entity_died event for the npc id, or the
##   npc id's death recorded in WorldState (a persist_death kill): a talker made after the death -
##   its chunk loaded again, a reload - starts silent, and a recorded death silences a standing one.
##   A talker standing for a spawned actor names its npc_id (P36's talker kind: Ulfra's, Harrok's
##   challenge stone), so its talk ends with the actor; one that names its own id never does.
## - interact_id defaults to the npc id, so Events.interacted names the NPC (quests, bot).

const DEFAULT_PROMPT := "Talk"

## The speaker's entity id ("" = the parent's entity_id).
@export var npc_id := ""
## The `dialogue` record to run ("" = the parent's record "dialogue").
@export var dialogue_id := ""


func _init() -> void:
	prompt = DEFAULT_PROMPT


func _ready() -> void:
	if interact_id == "":
		interact_id = resolved_npc_id()
	Events.entity_died.connect(_on_entity_died)
	if _npc_recorded_killed():
		enabled = false


## npc_id, else the parent's entity_id (the NPC this talker belongs to).
func resolved_npc_id() -> String:
	if npc_id != "":
		return npc_id
	var p := get_parent()
	if p != null and "entity_id" in p:
		return str(p.get("entity_id"))
	return ""


## dialogue_id, else the "dialogue" field of the parent's record (its CombatEntity's definition).
func resolved_dialogue_id() -> String:
	if dialogue_id != "":
		return dialogue_id
	var p := get_parent()
	if p == null:
		return ""
	var rec: Variant = p.get("record") if "record" in p else null
	if typeof(rec) == TYPE_DICTIONARY:
		return str(rec.get("dialogue", ""))
	var e: Variant = p.get("entity") if "entity" in p else null
	if e is CombatEntity and (e as CombatEntity).combatant != null:
		return str((e as CombatEntity).combatant.base_record.get("dialogue", ""))
	return ""


## The dialogue record ({} when it does not exist).
func dialogue_record() -> Dictionary:
	var rec := GameData.get_record(resolved_dialogue_id())
	return rec if str(rec.get("type", "")) == "dialogue" else {}


func can_interact(_player: GiantPlayer) -> bool:
	return not dialogue_record().is_empty() and _npc_alive()


func blocked_reason(_player: GiantPlayer) -> String:
	if not _npc_alive():
		return ""
	return "They have nothing to say." if dialogue_record().is_empty() else ""


func prompt_text(_player: GiantPlayer) -> String:
	if prompt != DEFAULT_PROMPT:
		return prompt
	var speaker := str(dialogue_record().get("speaker", ""))
	return "%s to %s" % [DEFAULT_PROMPT, speaker] if speaker != "" else DEFAULT_PROMPT


func interact(_player: GiantPlayer) -> void:
	Events.dialogue_requested.emit(resolved_npc_id(), resolved_dialogue_id())


func _npc_alive() -> bool:
	if _npc_recorded_killed():
		return false
	var p := get_parent()
	if p == null or not ("entity" in p):
		return true
	var e: Variant = p.get("entity")
	return not (e is CombatEntity) or (e as CombatEntity).is_alive()


## M8 gate (F5): the npc's death is in WorldState (a persist_death kill, kept by saves and reloads).
func _npc_recorded_killed() -> bool:
	var id := resolved_npc_id()
	return id != "" and WorldState.is_killed(id)


func _on_entity_died(_tick: int, entity_id: String, _killer_id: String) -> void:
	if entity_id != "" and entity_id == resolved_npc_id():
		enabled = false
