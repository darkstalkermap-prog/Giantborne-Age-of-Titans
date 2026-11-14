class_name BroodNest
extends BreakableProp
## A brood nest of the Troll Matriarch (P35; plan M6-M9 §5.7, §5.13): the drive-out resolution of the
## Greywood's oath burns the den's three nests, then the Matriarch flees through the den's back wall
## (DenWall). A BreakableProp (its record prop.brood_nest: XP on burning, the Broken visual a charred
## ring) that only fire destroys:
##   * any hit without fire (no "fire" share in its damage split and no Fire tag) is refused like a
##     wrong category (BreakableProp's IMMUNE "not_permitted", last_rejection "fire") and shows the
##     record's locked message, which says how to burn it;
##   * a prop tagged "fire" (a brazier, a bonfire: P34's brazier rule for trolls) broken within
##     ignite_radius_m spills its coals into the nest: one fire hit, credited to whoever broke it;
##   * a body thrown at it while Burning (a whelp or a troll the giant set down in the den's fire pit:
##     TrollEnemy) burns it the same way, credited to the thrower.
## When it burns and every nest of den_nests (its siblings' world ids, itself included) is destroyed,
## den_flag (world.troll_den.nests_burned: one of the Matriarch's drive_out flags, and the woodfolk's
## signal to pull down the back wall) is set, first write wins, with a line on the HUD.
## Built by the world builder's nest kind (tools/world/kinds/nest.gd) into its chunk's props part.

const FIRE_ACTION := "fire.brood_nest"
const FIRE_POWER := 9999.0
const BURNED_MESSAGE := "The last brood nest burns. The Matriarch has nothing left to guard but her den."

## A fire prop broken this close (or a burning body landing this close) burns the nest.
@export var ignite_radius_m := 9.0
## Set once every nest of den_nests has burned.
@export var den_flag := "world.troll_den.nests_burned"
## The world ids of the den's nests (this one among them).
@export var den_nests := PackedStringArray()

## Fire hits this nest queued (tests, debug).
var burns := 0
var _burn_queued := false


func _ready() -> void:
	super()
	if not Events.object_destroyed.is_connected(_on_object_destroyed):
		Events.object_destroyed.connect(_on_object_destroyed)
	if not Events.projectile_impact.is_connected(_on_projectile_impact):
		Events.projectile_impact.connect(_on_projectile_impact)
	if destroyed:
		check_den()


## True when `hit` carries fire: a fire share in its damage split or the Fire tag.
static func is_fire(hit: HitEvent) -> bool:
	if hit == null:
		return false
	return float(hit.damage_split.get("fire", 0.0)) > 0.0 or hit.has_tag("Fire")


func rejection_reason(hit: HitEvent) -> String:
	var why := super(hit)
	if why != "":
		return why
	return "" if is_fire(hit) else "fire"


## Burns the nest now with one fire hit credited to `by_entity_id` (the player who broke the brazier
## or threw the burning body; the giant when no one is named). False when it has burned already.
func burn(by_entity_id: String = "") -> bool:
	if destroyed or _burn_queued or entity == null:
		return false
	var attacker := by_entity_id
	if attacker == "" or Sim.get_entity(attacker) == null:
		attacker = _player_id()
	var h := HitEvent.new()
	h.tick = Sim.tick
	h.instance_id = Sim.new_instance_id()
	h.attacker_id = attacker
	h.target_id = entity.entity_id
	h.action_id = FIRE_ACTION
	h.power = FIRE_POWER
	h.attacker_stat = 0.0
	h.size_policy = "none"
	h.damage_split = {"fire": 1.0}
	h.tags = PackedStringArray(["Fire", "Unblockable", "Unparryable"])
	h.category = "ability"
	h.attacker_growth_stage = 10
	h.attacker_position = global_position if is_inside_tree() else Vector3.ZERO
	h.hit_point = h.attacker_position
	Sim.queue_hit(h)
	burns += 1
	_burn_queued = true
	return true


func on_entity_died(killer_id: String) -> void:
	super(killer_id)
	_burn_queued = false
	check_den()


## Sets den_flag once every nest of den_nests has burned (true when it holds now).
func check_den() -> bool:
	if den_flag == "":
		return false
	for id in den_nests:
		if id != world_id and not WorldState.is_destroyed(id):
			return false
	if not destroyed:
		return false
	if WorldState.try_set_flag(den_flag, true):
		Events.hud_message.emit(BURNED_MESSAGE, "good")
	return true


func _on_object_destroyed(_tick: int, other_id: String, by_entity_id: String) -> void:
	if destroyed or other_id == world_id or not is_inside_tree():
		return
	for n in get_tree().get_nodes_in_group("breakables"):
		if not (n is Node3D) or str(n.get("world_id")) != other_id:
			continue
		var rec: Variant = n.get("record")
		var tags: Array = (rec as Dictionary).get("prop_tags", []) if typeof(rec) == TYPE_DICTIONARY else []
		if tags.has("fire") and _flat(n as Node3D) <= ignite_radius_m:
			burn(by_entity_id)
		return


func _on_projectile_impact(_tick: int, projectile_id: int, position: Vector3, hit_entity_id: String) -> void:
	if destroyed or not is_inside_tree():
		return
	var near := hit_entity_id == entity.entity_id \
		or Vector2(position.x - global_position.x, position.z - global_position.z).length() <= ignite_radius_m
	if not near:
		return
	var system := ProjectileSystem.instance(get_tree())
	var pr := system.get_projectile(projectile_id) if system != null else null
	if pr == null or pr.held_entity_id == "":
		return
	var body := Sim.get_entity(pr.held_entity_id)
	if body == null or not is_instance_valid(body.actor) or not body.actor.has_method("p34_has_status_tag") \
			or not bool(body.actor.call("p34_has_status_tag", "Burning")):
		return
	burn(pr.owner_id)


func _flat(n: Node3D) -> float:
	return Vector2(n.global_position.x - global_position.x, n.global_position.z - global_position.z).length()


func _player_id() -> String:
	if not is_inside_tree():
		return ""
	var p := get_tree().get_first_node_in_group("player")
	var e: Variant = p.get("entity") if p != null else null
	return (e as CombatEntity).entity_id if e is CombatEntity else ""
