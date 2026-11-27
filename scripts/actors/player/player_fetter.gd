class_name PlayerFetter
extends PlayerComponent
## E1 (decision E1-2): the fetters - chains on a colossus's legs, the Skarn's answer to a giant a hundred feet tall. The
## `fetter` component of GiantPlayer.COMPONENTS.
##
## A fetter is a chain from one of his legs to an anchor: a fetter-winch staked into the ground round the Moot (its
## barbed harpoon struck him: an action with the `fetter` parameter) or Orrik himself (his thrown chain-hook). Each holds
## him to a circle round its anchor (the chain's length, paid out to where he stood when it bit, plus SLACK_M): he cannot
## walk farther than that from it while it holds. How many bind him decides what he can do:
##   * one - he moves at SLOW_BY_COUNT[1] of his speed;
##   * two - slower, and no dodge, jump or sprint (the legs are bound);
##   * three - PINNED: barely able to move (Events.giant_pinned) - Orrik's Throne-breaker comes for a pinned giant.
## How he gets out is how a giant would: **he tears the chain**. Pulling against a taut chain (walking away from its
## anchor) strains it by his size (STRAIN_PER_S_BY_STAGE: a stage-9 colossus tears it in about a second, stage 8 in under
## two, stage 7 in three and more, a smaller giant hardly at all); a heavy blow begun while bound is a heave
## (HEAVE_BY_STAGE: at stage 8 and over it tears the tautest chain at once, at 7 half of one); a chain at full strain
## tears. A torn winch's chain wrenches the winch out of the ground (it breaks: FetterWinch.wrench); a torn hook yanks
## Orrik off balance (HeirEnemy.hook_torn). A chain also goes when its anchor is destroyed (the winch crushed or struck
## to pieces), when Harrok cuts it (HarrokAlly), and Orrik's hook after HOOK_HOLD_S. Never saved: a reload, a death or a
## travel frees him. The armour's `fetter_strain_mult` passive (the Fetterer's set) strains chains faster.

const MAX_FETTERS := 3
## The chain's slack beyond where he stood when it bit (m).
const SLACK_M := 4.0
## His speed with 0..3 chains on him.
const SLOW_BY_COUNT := [1.0, 0.72, 0.45, 0.06]
## From this many chains: no dodge, jump or sprint.
const BOUND_AT := 2
## Strain a second while he pulls against a taut chain, by growth stage (1.0 tears it).
const STRAIN_PER_S_BY_STAGE := {1: 0.04, 2: 0.04, 3: 0.05, 4: 0.06, 5: 0.08, 6: 0.12, 7: 0.3, 8: 0.6, 9: 0.85, 10: 1.1}
## The strain a heavy blow begun while bound puts on the tautest chain, by growth stage (1.0 or more tears it).
const HEAVE_BY_STAGE := {1: 0.1, 2: 0.1, 3: 0.12, 4: 0.15, 5: 0.18, 6: 0.25, 7: 0.5, 8: 1.0, 9: 1.0, 10: 1.0}
## A chain is taut within this much of its length (m); his pull counts only then.
const TAUT_M := 0.6
## A pull counts when his move points this much away from the anchor (the cosine).
const PULL_COS := 0.3
## Orrik's hook lets go after this long (s).
const HOOK_HOLD_S := 12.0
## A chain on him is not added again within this long of the last from the same anchor (one harpoon, one chain).
const REBIND_S := 1.0
const BOUND_EDGES := [&"dodge", &"jump", &"sprint_press"]
const BOUND_TEXT := "Chained! Pull away from the chain or heave (heavy blow) to tear it."
const PINNED_TEXT := "PINNED! Heave (heavy blow) to tear free - the Throne-breaker is coming!"

## [{"anchor": entity id, "kind": "winch" | "hook", "leg": "l" | "r", "length": m, "strain": 0..1, "tick": bound at,
##   "point": Vector3 (the anchor's chain point)}], oldest first.
var fetters: Array = []
## This life's tallies (tests, the duel report): chains bound, torn by pulling, torn by heaving, freed otherwise, pins.
var bound := 0
var torn_pull := 0
var torn_heave := 0
var freed := 0
var pins := 0
## The tick he was pinned (-1: not pinned).
var pinned_since := -1
var _next_leg := "l"
var _last_bind: Dictionary = {}


func edge_priority() -> int:
	return 8


func setup(p: GiantPlayer) -> void:
	super(p)
	if not Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.connect(_on_hit_resolved)
	if not Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.connect(_on_entity_died)
	if DisplayServer.get_name() != "headless" and p.is_inside_tree():
		var fx := FetterChains.new()
		fx.name = "FetterChains"
		p.add_child(fx)
		fx.setup(p)


func on_exit() -> void:
	if Events.hit_resolved.is_connected(_on_hit_resolved):
		Events.hit_resolved.disconnect(_on_hit_resolved)
	if Events.entity_died.is_connected(_on_entity_died):
		Events.entity_died.disconnect(_on_entity_died)


func count() -> int:
	return fetters.size()


func is_bound() -> bool:
	return fetters.size() >= BOUND_AT


func is_pinned() -> bool:
	return fetters.size() >= MAX_FETTERS


func holds(anchor_id: String) -> bool:
	for f: Dictionary in fetters:
		if str(f.anchor) == anchor_id:
			return true
	return false


## The strain of the tautest chain (0 with none).
func max_strain() -> float:
	var m := 0.0
	for f: Dictionary in fetters:
		m = maxf(m, float(f.strain))
	return m


## How fast his pull strains a chain: his stage's rate times his armour's passive.
func strain_rate() -> float:
	var r := float(STRAIN_PER_S_BY_STAGE.get(clampi(int(player.growth_stage), 1, 10), 0.1))
	if player.entity != null and player.entity.combatant != null:
		r *= player.entity.combatant.modifier("fetter_strain_mult")
	return r


func heave_strain() -> float:
	var h := float(HEAVE_BY_STAGE.get(clampi(int(player.growth_stage), 1, 10), 0.1))
	if player.entity != null and player.entity.combatant != null:
		h *= player.entity.combatant.modifier("fetter_strain_mult")
	return h


## Binds a chain from `anchor_id` (an entity whose actor is the anchor; `kind` "winch" or "hook") to one of his legs.
## Refused (false) when he is dead, already holds that anchor's chain, or carries MAX_FETTERS.
func bind(anchor_id: String, kind := "winch") -> bool:
	if player.entity == null or not player.entity.is_alive() or anchor_id == "" or holds(anchor_id):
		return false
	if fetters.size() >= MAX_FETTERS:
		return false
	if Sim.tick - int(_last_bind.get(anchor_id, -100000)) < ActionDef.seconds_to_ticks(REBIND_S):
		return false
	var at := anchor_point(anchor_id)
	if at == Vector3.INF:
		return false
	var flat := Vector2(player.global_position.x - at.x, player.global_position.z - at.z).length()
	fetters.append({"anchor": anchor_id, "kind": kind, "leg": _next_leg, "length": flat + SLACK_M, "strain": 0.0,
		"tick": Sim.tick, "point": at})
	_next_leg = "r" if _next_leg == "l" else "l"
	_last_bind[anchor_id] = Sim.tick
	bound += 1
	Events.fetter_bound.emit(Sim.tick, player.entity.entity_id, anchor_id, kind, fetters.size())
	if is_bound() and player.controller != null and player.controller.action != null \
			and player.controller.action.has_tag("Dodge"):
		player.controller.call("_finish_action", true)
	if is_pinned():
		pinned_since = Sim.tick
		pins += 1
		Events.giant_pinned.emit(Sim.tick, player.entity.entity_id, true)
		Events.hud_message.emit(PINNED_TEXT, "warn")
	elif fetters.size() == 1 or is_bound():
		Events.hud_message.emit(BOUND_TEXT, "warn")
	_apply_slow()
	return true


## Lets the chain of `anchor_id` go: `how` "pull" or "heave" (he tore it: its anchor answers), "cut" (Harrok), "anchor"
## (the anchor is gone), "hook" (Orrik's hook let go), "death". Returns whether a chain went.
func release(anchor_id: String, how := "anchor") -> bool:
	for i in fetters.size():
		var f: Dictionary = fetters[i]
		if str(f.anchor) != anchor_id:
			continue
		var was_pinned := is_pinned()
		fetters.remove_at(i)
		match how:
			"pull":
				torn_pull += 1
			"heave":
				torn_heave += 1
			_:
				freed += 1
		if how == "pull" or how == "heave":
			_answer_tear(f)
		Events.fetter_torn.emit(Sim.tick, player.entity.entity_id, anchor_id, how, fetters.size())
		if was_pinned and not is_pinned():
			pinned_since = -1
			Events.giant_pinned.emit(Sim.tick, player.entity.entity_id, false)
		_apply_slow()
		return true
	return false


func release_all(how := "death") -> void:
	while not fetters.is_empty():
		release(str((fetters[0] as Dictionary).anchor), how)


## The anchor's chain point now (its actor's: FetterWinch.chain_point, HeirEnemy.chain_point, else its position).
func anchor_point(anchor_id: String) -> Vector3:
	var e := Sim.get_entity(anchor_id)
	if e == null or not is_instance_valid(e.actor):
		return Vector3.INF
	var a := e.actor as Node3D
	if a.has_method("chain_point"):
		return a.call("chain_point")
	return a.global_position


## The torn chain's anchor answers: a winch is wrenched out of the ground, Orrik is yanked off balance.
func _answer_tear(f: Dictionary) -> void:
	var e := Sim.get_entity(str(f.anchor))
	if e == null or not is_instance_valid(e.actor):
		return
	if e.actor.has_method("chain_torn"):
		e.actor.call("chain_torn", player)


func _apply_slow() -> void:
	player.motor.set_speed_mult(&"fetter", float(SLOW_BY_COUNT[clampi(fetters.size(), 0, MAX_FETTERS)]))


func handle_edge(edge: StringName) -> bool:
	return is_bound() and edge in BOUND_EDGES


## A heavy blow begun while bound is a heave: the tautest chain takes heave_strain() (torn at 1).
func on_action_started(action: ActionDef, _instance_id: int) -> void:
	if fetters.is_empty() or action == null or not action.has_tag("Heavy"):
		return
	var best := -1
	var most := -1.0
	for i in fetters.size():
		var s := float((fetters[i] as Dictionary).strain) + (0.001 if str((fetters[i] as Dictionary).kind) == "hook" else 0.0)
		if s > most:
			most = s
			best = i
	if best < 0:
		return
	var f: Dictionary = fetters[best]
	f.strain = float(f.strain) + heave_strain()
	if float(f.strain) >= 1.0 - 1e-4:
		release(str(f.anchor), "heave")


## A blow with a `fetter` parameter that struck him (not blocked) binds its attacker's chain.
func _on_hit_resolved(_tick: int, r: HitResult) -> void:
	if r == null or r.event == null or player == null or player.entity == null:
		return
	if r.event.target_id != player.entity.entity_id or r.outcome == HitResult.Outcome.BLOCKED:
		return
	var a := GameData.get_action(r.event.action_id)
	if a == null:
		return
	var kind := str(a.param("fetter", ""))
	if kind == "":
		return
	bind(r.event.attacker_id, kind)


func _on_entity_died(_tick: int, id: String, _killer: String) -> void:
	if player != null and player.entity != null and id == player.entity.entity_id:
		release_all("death")
	elif holds(id):
		release(id, "anchor")


## Every tick: the chains hold him to their circles, his pull strains the taut ones, Orrik's hook lets go in time.
func post_movement(_tick: int, dt: float) -> void:
	if fetters.is_empty():
		return
	if player.entity == null or not player.entity.is_alive():
		release_all("death")
		return
	var pos := player.global_position
	# his pull is what he means to do (the move he asks for), not what the chain lets him
	var input: Vector2 = player.last_intents.get("move", Vector2.ZERO)
	var want := player.motor.move_dir_world(input) if input.length() > 0.2 else Vector3.ZERO
	var move := Vector2(want.x, want.z)
	var rate := strain_rate()
	var gone: Array = []
	for f: Dictionary in fetters:
		var at := anchor_point(str(f.anchor))
		if at == Vector3.INF:
			gone.append([str(f.anchor), "anchor"])
			continue
		f.point = at
		if str(f.kind) == "hook" and Sim.tick - int(f.tick) >= ActionDef.seconds_to_ticks(HOOK_HOLD_S):
			gone.append([str(f.anchor), "hook"])
			continue
		var rel := Vector2(pos.x - at.x, pos.z - at.z)
		var d := rel.length()
		var out := rel / d if d > 1e-3 else Vector2.ZERO
		var length := float(f.length)
		if d > length:
			# the chain holds: back to its circle (what of his speed went outward is lost)
			var back := out * (d - length)
			pos.x -= back.x
			pos.z -= back.y
			var outward := player.move_velocity.x * out.x + player.move_velocity.z * out.y
			if outward > 0.0:
				player.move_velocity.x -= out.x * outward
				player.move_velocity.z -= out.y * outward
		if d >= length - TAUT_M and move.length() > 0.2 and move.normalized().dot(out) >= PULL_COS:
			f.strain = float(f.strain) + rate * dt
			if float(f.strain) >= 1.0:
				gone.append([str(f.anchor), "pull"])
	player.global_position = pos
	for g: Array in gone:
		release(str(g[0]), str(g[1]))


## Orrik hauls on his hook: its chain shortens by `metres` (at least to `min_m`), so it drags the giant in.
func haul(anchor_id: String, metres: float, min_m := 8.0) -> bool:
	for f: Dictionary in fetters:
		if str(f.anchor) == anchor_id:
			f.length = maxf(min_m, float(f.length) - metres)
			return true
	return false


func rig_state(out: Dictionary) -> void:
	if not fetters.is_empty():
		var list: Array = []
		for f: Dictionary in fetters:
			list.append({"leg": f.leg, "point": f.point, "strain": f.strain, "kind": f.kind})
		out["fetters"] = list


func debug_info(out: Dictionary) -> void:
	if not fetters.is_empty():
		out["fetters"] = "%d%s (strain %.2f)" % [fetters.size(), " PINNED" if is_pinned() else "", max_strain()]
