class_name FetterWinch
extends SiegeEngine
## E1 (decision E1-2): a fetter-winch - the Skarn's answer to a colossus. A giant's harpoon engine (P32's crewed ballista
## at a giant's scale: a timber sled staked into the ground, a great bow, a drum of chain behind it) crewed by Skarn
## giants. Its barbed harpoon (an action with the `fetter` parameter: ability.fetter_harpoon) trails a chain from the
## drum: where it strikes the giant it bites on his leg and the chain holds him (PlayerFetter). Everything else is the
## SiegeEngine's: the crew, the aim line that follows him until the aim lock (a step aside after it dodges the harpoon),
## the reload, the ranged token and launch slot, breaking it (a heavy blow or two, or a stage-8 giant's stride over it:
## the record's trample_stage).
##
## What a winch adds:
##   * It holds its fire while its own chain is on him (one chain a winch) - the next harpoon comes only once he is free
##     of it.
##   * Torn free (PlayerFetter: a pull or a heave), its chain wrenches it out of the ground: it breaks at once (a trample
##     hit of the giant's through the hit queue: its debris, XP, the crew's flight - the SiegeEngine's death).
##   * `boss_id` / `join_phase`: it holds its fire until that boss's fight is engaged and has reached `join_phase` (1: from
##     the engagement; 2: from his second phase - Orrik's horn calls it in), and again after a new attempt (the fight
##     disengaged). "" = it fights whenever it is crewed (the winch camp's).
##   * chain_point(): where its chain leaves the drum (the PlayerFetter's anchor, the chain's look).

## The drum's height over the engine's origin, as a share of its record's height (the chain's start).
const DRUM_SHARE := 0.55

@export var boss_id := ""
@export var join_phase := 1
## The farthest it draws at (m; 0 = its record's range): the winch camp's reach no farther than its camp.
@export var reach_m := 0.0

## Chains it bit on a giant and how many were torn from it (tests, metrics).
var chains_bound := 0
var wrenched := false
## Orrik has fallen: nobody serves it (a harpoon still in the air when he fell bites on nothing).
var abandoned := false
var _engaged := false
var _phase := 0


func _ready() -> void:
	super()
	add_to_group("fetter_winches")
	if boss_id != "":
		set_fire_held(true)
		if not Events.boss_engaged.is_connected(_on_boss_engaged):
			Events.boss_engaged.connect(_on_boss_engaged)
			Events.boss_phase_changed.connect(_on_boss_phase)
			Events.boss_disengaged.connect(_on_boss_disengaged)
			Events.boss_defeated.connect(_on_boss_defeated)
	if not Events.fetter_bound.is_connected(_on_fetter_bound):
		Events.fetter_bound.connect(_on_fetter_bound)


func _exit_tree() -> void:
	super()
	for pair: Array in [[Events.boss_engaged, _on_boss_engaged], [Events.boss_phase_changed, _on_boss_phase],
			[Events.boss_disengaged, _on_boss_disengaged], [Events.fetter_bound, _on_fetter_bound],
			[Events.boss_defeated, _on_boss_defeated]]:
		if (pair[0] as Signal).is_connected(pair[1]):
			(pair[0] as Signal).disconnect(pair[1])


## Where its chain leaves the drum (global).
func chain_point() -> Vector3:
	return global_position + Vector3.UP * float(record.get("height_m", 6.0)) * DRUM_SHARE


## Its crew are giants: they stand this many times farther out than a man's place by a ballista.
const CREW_SLOT_SCALE := 3.4


func crew_slot(actor: Node) -> Vector3:
	var p := super(actor)
	if p == Vector3.INF:
		return p
	return global_position + (p - global_position) * CREW_SLOT_SCALE


func range_band() -> Vector2:
	var b := super()
	return Vector2(b.x, minf(b.y, reach_m)) if reach_m > 0.0 else b


## Its own chain on a giant now.
func holds_chain() -> bool:
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER and is_instance_valid(e.actor):
			var f: Variant = e.actor.get("fetter")
			if f != null and (f as PlayerFetter).holds(entity.entity_id):
				return true
	return false


func can_shoot() -> bool:
	return super() and not holds_chain()


## PlayerFetter: may its harpoon bind a chain now (not once it is broken or abandoned)?
func can_bind() -> bool:
	return not destroyed and not abandoned


## PlayerFetter: the giant tore its chain - it comes out of the ground and breaks.
func chain_torn(by: Node3D) -> void:
	if destroyed or by == null:
		return
	wrenched = true
	_queue_special_hit(by, TRAMPLE_ACTION)


func _on_fetter_bound(_tick: int, _entity_id: String, anchor_id: String, _kind: String, _count: int) -> void:
	if entity != null and anchor_id == entity.entity_id:
		chains_bound += 1


func _on_boss_engaged(_tick: int, id: String) -> void:
	if id != boss_id:
		return
	_engaged = true
	_phase = maxi(_phase, 1)
	set_fire_held(_phase < join_phase)


func _on_boss_phase(_tick: int, id: String, phase: int) -> void:
	if id != boss_id:
		return
	_phase = maxi(_phase, phase)   # (1-based: his second phase is 2)
	if _engaged:
		set_fire_held(_phase < join_phase)


func _on_boss_disengaged(_tick: int, id: String, _reason: String) -> void:
	if id != boss_id:
		return
	_engaged = false
	_phase = 0
	set_fire_held(true)


## Orrik has fallen: the warband's winches stand abandoned (they never shoot again).
func _on_boss_defeated(_tick: int, id: String) -> void:
	if id != boss_id:
		return
	_engaged = false
	join_phase = 99
	abandoned = true
	set_fire_held(true)
	# the warband breaks: a chain of this winch still on the giant goes slack (he is not left tied to a winch nobody serves)
	for e: CombatEntity in Sim.entities():
		if e.team == CombatEntity.Team.PLAYER and is_instance_valid(e.actor):
			var f: Variant = e.actor.get("fetter")
			if f != null:
				(f as PlayerFetter).release(entity.entity_id, "anchor")
