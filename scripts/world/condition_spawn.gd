class_name ConditionSpawn
extends Node3D
## A placed thing that is in the world only once a quest condition holds (P36; plan M6-M9 §5.3, §5.10):
## the siege line before Skarn arrives with the siege (its engines appear when the siege of Skarn
## starts: event.siege_of_skarn.runs), and the toll fort's tower ballista is mounted for a giant of
## stage 5. Until then nothing of it exists - no mesh in the settlements' views (plan §3.8: 40 draw
## calls a view), nothing to lock on, hit or grab. When `when` first holds (checked on entering the
## tree, on every flag change and on the giant's growth) `scene` is instanced as this node's child
## `child_name` with `props` set on it; it then stays while the chunk is loaded, and its own saved state
## (a destroyed engine stays destroyed) takes over. Placed by the world builder (kind "engine" with
## `appears_when`); the child keeps the world id, so the encounters' `engines` lists and the world's
## destroyed set name it as any placed engine. A flag change instances it at once (an event's start
## sets its flag before the event's copies spawn, so their crews find the engine); an engine that
## appears after crews of it spawned takes them (the director binds a crew only as it spawns).

## The scene instanced once `when` holds.
@export var scene := ""
## Properties set on the instance before it enters the tree.
@export var props: Dictionary = {}
## A quest condition (QuestConditions; {} = always).
@export var when: Dictionary = {}
## The instance's node name.
@export var child_name := ""

var spawned: Node3D = null


func _ready() -> void:
	if not Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.connect(_on_flag_changed)
	if not Events.growth_changed.is_connected(_on_growth_changed):
		Events.growth_changed.connect(_on_growth_changed)
	refresh()


func _exit_tree() -> void:
	if Events.flag_changed.is_connected(_on_flag_changed):
		Events.flag_changed.disconnect(_on_flag_changed)
	if Events.growth_changed.is_connected(_on_growth_changed):
		Events.growth_changed.disconnect(_on_growth_changed)


## True while the condition holds.
func holds() -> bool:
	return when.is_empty() or QuestConditions.holds(when, Quests.condition_context())


## Instances the scene once the condition holds (once). Returns the instance (null while waiting).
func refresh() -> Node3D:
	if spawned != null and is_instance_valid(spawned):
		return spawned
	if scene == "" or not holds():
		return null
	var packed := load(scene) as PackedScene
	if packed == null:
		push_error("ConditionSpawn %s: no scene at %s" % [name, scene])
		return null
	var n := packed.instantiate() as Node3D
	n.name = child_name if child_name != "" else "Spawned"
	for key: String in props:
		n.set(key, props[key])
	spawned = n
	add_child(n)
	if n.has_method("add_crew"):
		_take_spawned_crews(n)
	return n


## Gives an engine that just appeared the crews of it that are already in the world.
func _take_spawned_crews(engine: Node) -> void:
	var wid := str(engine.get("world_id"))
	for d in get_tree().get_nodes_in_group(EncounterDirector.GROUP):
		var dir := d as EncounterDirector
		if dir == null:
			continue
		for enc_id: String in dir.encounter_ids():
			for eid: String in dir.members_of(enc_id):
				if dir.p32_engine_of(enc_id, eid) != wid or dir.member_status(eid) != "spawned":
					continue
				var node := dir.spawned(eid)
				if node != null:
					engine.call("add_crew", node)   # (add_crew skips a member it has)


func _on_flag_changed(_tick: int, _flag_id: String, _value: Variant) -> void:
	if spawned == null and is_inside_tree():
		refresh()


func _on_growth_changed(_tick: int, _entity_id: String, _old_stage: int, _new_stage: int) -> void:
	if spawned == null:
		refresh.call_deferred()
