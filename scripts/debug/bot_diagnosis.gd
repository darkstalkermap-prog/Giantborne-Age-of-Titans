class_name BotDiagnosis
extends RefCounted
## The Valley bot's checks of the world (plan §5.1 "Diagnosis", §5.2 "Invariants"). Static and
## stateless: the bot passes what it knows.
##
## diagnose() runs on a watchdog breach (an objective timed out, too many deaths, or stuck). It asks
## two questions and records the evidence:
##   1. Is there a path on the giant's navigation layers from where it stands to the objective? The
##      props whose nav links are still closed (the cart barricade, the practice gate, the Deadfall)
##      count as open: a path through one of them is a path (breaking it is the bot's job). Goals
##      the giant only has to come near (a cairn on a ledge, a prop to hit, a pickup) are snapped to
##      the navmesh first and count as reached within the objective's use radius.
##   2. Can the objective's condition still become true in this world? Its targets must be alive or
##      already killed as required (a member of an encounter of this level), a prop to destroy must
##      take a blow the giant can deal at its stage (or will, with the tree it can still get), a
##      flag it waits for must not be set to something else for good, an item must still be held or
##      lying somewhere, and so on through all / any / not.
## world_blocked = no path, or a condition that can no longer hold: a softlock, a stability failure.
## bot_failed = both fine: the bot could not do something possible (reported, tuned in P17b).
##
## check_invariants() runs every tick of a bot run; each failure is a line of text, and any failure
## ends the run with exit code 3 (Autopilot).

const WORLD_BLOCKED := "world_blocked"
const BOT_FAILED := "bot_failed"
const REACH_TOLERANCE_M := 3.0
const LINK_TOLERANCE_M := 2.0
const MAX_PENDING_HITS := 512
const MAX_DEBRIS := 40
const MAX_MELEE_TOKENS := 2
const MAX_RANGED_TOKENS := 2
const MIN_PLAYER_Y := -50.0
const MAX_SCREEN_OPEN_S := 2.0
const NODE_GROWTH_CYCLES := 5
const NODE_GROWTH_FRACTION := 0.10


# --------------------------------------------------------------------------- diagnosis

## The diagnosis of a breach: {"reason", "objective", "classification", "path", "condition",
## "evidence": [lines]}. goal: where the objective is (Vector3.INF: its position); use_radius: how
## near the giant must come (snapped goals farther than this from the objective are off its layer).
static func diagnose(objective: Dictionary, player: GiantPlayer, level: LevelRoot, reason: String,
		goal := Vector3.INF, use_radius := REACH_TOLERANCE_M) -> Dictionary:
	var out := {"reason": reason, "objective": "%s:%s" % [objective.get("quest_id", "?"), objective.get("stage_id", "?")],
		"tick": Sim.tick, "classification": BOT_FAILED, "evidence": []}
	var where := goal
	if not where.is_finite():
		var p: Variant = objective.get("position", Vector3.INF)
		where = p if p is Vector3 else Vector3.INF
	if player == null or not is_instance_valid(player) or level == null or not is_instance_valid(level):
		out.classification = BOT_FAILED
		(out.evidence as Array).append("no player or level to check")
		return out
	var path := {}
	if where.is_finite():
		path = path_check(player, level, where, use_radius)
	else:
		path = {"reachable": true, "note": "the objective has no position (a state to reach, not a place)"}
	out["path"] = path
	var cond := condition_check(_condition_of(objective), player, level)
	out["condition"] = cond
	if not bool(path.get("reachable", true)):
		out.classification = WORLD_BLOCKED
		(out.evidence as Array).append("no path on layers %d to %s" % [player.nav_layers, _v(where)])
	if not bool(cond.get("satisfiable", true)):
		out.classification = WORLD_BLOCKED
		(out.evidence as Array).append("condition cannot hold: %s" % cond.get("why", ""))
	if str(out.classification) == BOT_FAILED:
		(out.evidence as Array).append("a path exists and the condition can still hold: the bot failed")
	return out


static func _condition_of(objective: Dictionary) -> Variant:
	if objective.has("complete_when"):
		return objective.complete_when
	var qid := str(objective.get("quest_id", ""))
	var sid := str(objective.get("stage_id", ""))
	if qid == "" or sid == "":
		return null
	return Quests.stage_record(Quests.quest_record(qid), sid).get("complete_when")


## Is `goal` reachable from the giant on its navigation layers? Closed nav links of breakable props
## count as open. {"reachable", "direct", "via_link", "from", "goal", "snapped", "snap_gap_m",
## "layers"}.
static func path_check(player: GiantPlayer, level: LevelRoot, goal: Vector3, use_radius := REACH_TOLERANCE_M) -> Dictionary:
	var map := level.nav_map()
	var layers := player.nav_layers
	var from := player.global_position
	var snapped := snap_to_layer(level, goal, layers)
	var gap := _flat(snapped, goal)
	var out := {"from": _v(from), "goal": _v(goal), "snapped": _v(snapped), "snap_gap_m": snappedf(gap, 0.01),
		"layers": layers, "direct": false, "via_link": "", "reachable": false}
	if not snapped.is_finite() or gap > use_radius + 1e-3:
		out["note"] = "the objective is %.1f m from the nearest point of the giant's layer" % gap
		return out
	if reaches(map, from, snapped, layers):
		out.direct = true
		out.reachable = true
		return out
	for link: NavigationLink3D in closed_links(level, layers):
		var a := link.to_global(link.start_position)
		var b := link.to_global(link.end_position)
		for pair: Array in [[a, b], [b, a]]:
			if reaches(map, from, pair[0], layers, LINK_TOLERANCE_M) and reaches(map, pair[1], snapped, layers):
				out.via_link = str(link.get_path())
				out.reachable = true
				return out
	return out


## The point of the giant's layer nearest `pos` (the lowest set bit's region), else `pos`.
static func snap_to_layer(level: LevelRoot, pos: Vector3, layers: int) -> Vector3:
	var bit := 1
	while bit <= 255 and (layers & bit) == 0:
		bit <<= 1
	var region := level.nav_region(bit)
	if not region.is_valid():
		return pos
	return NavigationServer3D.region_get_closest_point(region, pos)


## True when a path on `layers` from `a` ends within `tolerance` m of `b` (horizontally).
static func reaches(map: RID, a: Vector3, b: Vector3, layers: int, tolerance := REACH_TOLERANCE_M) -> bool:
	if not map.is_valid():
		return false
	var p := NavigationServer3D.map_get_path(map, a, b, true, layers)
	return p.size() > 0 and _flat(p[p.size() - 1], b) <= tolerance


## Disabled NavigationLink3D nodes of the level on `layers` (breakable props not yet broken).
static func closed_links(level: LevelRoot, layers: int) -> Array[NavigationLink3D]:
	var out: Array[NavigationLink3D] = []
	for n in level.find_children("*", "NavigationLink3D", true, false):
		var link := n as NavigationLink3D
		if link != null and not link.enabled and (link.navigation_layers & layers) != 0:
			out.append(link)
	return out


## Can `cond` (a quest condition) still hold in this world? {"satisfiable", "why"}.
static func condition_check(cond: Variant, player: GiantPlayer, level: LevelRoot) -> Dictionary:
	if typeof(cond) != TYPE_DICTIONARY:
		return {"satisfiable": true, "why": "no condition"}
	var c: Dictionary = cond
	var ctx := Quests.condition_context()
	if QuestConditions.holds(c, ctx):
		return {"satisfiable": true, "why": "holds now"}
	match str(c.get("type", "")):
		"all":
			for sub: Variant in c.get("of", []):
				var r := condition_check(sub, player, level)
				if not bool(r.satisfiable):
					return r
			return {"satisfiable": true, "why": "every part can hold"}
		"any":
			var whys := PackedStringArray()
			for sub: Variant in c.get("of", []):
				var r := condition_check(sub, player, level)
				if bool(r.satisfiable):
					return r
				whys.append(str(r.why))
			return {"satisfiable": false, "why": "none can hold: " + "; ".join(whys)}
		"not":
			return {"satisfiable": true, "why": "a negation (not checked)"}
		"killed":
			return _killed_possible(c.get("targets", []), level)
		"encounter_cleared":
			return _encounter_possible(str(c.get("encounter", "")), level)
		"destroyed":
			return _destroy_possible(str(c.get("world_id", "")), player, level)
		"flag":
			return _flag_possible(c)
		"entered":
			var area := level.area(str(c.get("area", "")))
			return {"satisfiable": area != null, "why": "the area exists" if area != null else "no area %s" % c.get("area", "")}
		"has_item":
			return _item_possible(str(c.get("item", "")), level)
		"stage_at_least":
			return _stage_possible(int(c.get("stage", 1)), player, level)
		"weapon_equipped":
			var w := str(c.get("weapon", ""))
			var owned: bool = player.equipment != null and player.equipment.owns(w)
			return {"satisfiable": owned or not GameData.get_record(w).is_empty(), "why": "weapon %s" % w}
		"dialogue_outcome":
			var flag := QuestConditions.outcome_flag(str(c.get("dialogue", "")), str(c.get("outcome", "")))
			return {"satisfiable": not WorldState.has_flag(flag) or QuestConditions.truthy(WorldState.get_flag(flag)),
				"why": "dialogue outcome %s" % flag}
	return {"satisfiable": true, "why": "not checked (%s)" % c.get("type", "?")}


static func _killed_possible(targets: Variant, level: LevelRoot) -> Dictionary:
	var d := level.director()
	for t: Variant in (targets if typeof(targets) == TYPE_ARRAY else []):
		var id := str(t)
		if WorldState.is_killed(id):
			continue
		var e := Sim.get_entity(id)
		if e != null and e.is_alive():
			continue
		if d != null and d.member_status(id) in [EncounterDirector.UNSPAWNED, EncounterDirector.SPAWNED,
				EncounterDirector.DESPAWNED]:
			var enc := _encounter_of(d, id)
			if enc == "" or d.encounter_state(enc) != EncounterDirector.CLEARED or d.member_status(id) == EncounterDirector.SPAWNED:
				continue
		return {"satisfiable": false, "why": "%s can no longer be killed (not alive, not killed, %s)" % [id,
			d.member_status(id) if d != null else "no director"]}
	return {"satisfiable": true, "why": "the targets live or are dead"}


static func _encounter_of(d: EncounterDirector, entity_id: String) -> String:
	for enc in d.encounter_ids():
		if d.members_of(enc).has(entity_id):
			return enc
	return ""


static func _encounter_possible(encounter_id: String, level: LevelRoot) -> Dictionary:
	var d := level.director()
	if d == null or d.encounter_state(encounter_id) == "":
		return {"satisfiable": false, "why": "no encounter %s in this level" % encounter_id}
	if d.encounter_state(encounter_id) == EncounterDirector.DORMANT and not EncounterDirector.flags_allow(GameData.get_record(encounter_id)):
		return {"satisfiable": false, "why": "%s is dormant and its flags forbid it" % encounter_id}
	return {"satisfiable": true, "why": "%s is %s" % [encounter_id, d.encounter_state(encounter_id)]}


static func _destroy_possible(world_id: String, player: GiantPlayer, level: LevelRoot) -> Dictionary:
	var prop := level.get_node_or_null("Props/" + world_id.validate_node_name()) as BreakableProp
	if prop == null:
		for n in level.get_tree().get_nodes_in_group("breakables"):
			if n is BreakableProp and (n as BreakableProp).world_id == world_id:
				prop = n
				break
	if prop == null:
		return {"satisfiable": false, "why": "no prop %s" % world_id}
	if prop.destroyed:
		return {"satisfiable": true, "why": "destroyed"}
	var why := PackedStringArray()
	for hit: HitEvent in _player_hits(player):
		var r := prop.rejection_reason(hit)
		if r == "":
			return {"satisfiable": true, "why": "a %s blow breaks it now" % hit.category}
		why.append("%s: %s" % [hit.category, r])
	# The tree weapon at stage 3 (the Deadfall): satisfiable when the giant can still get one.
	var tags: Array = prop.record.get("required_tags", [])
	if tags.has("TreeWeapon") and (_stage_possible(3, player, level).satisfiable as bool) and _tree_available(player, level):
		return {"satisfiable": true, "why": "the tree weapon (stage 3) breaks it"}
	if int(prop.record.get("min_growth_stage", 1)) > player.current_growth_stage() \
			and bool(_stage_possible(int(prop.record.get("min_growth_stage", 1)), player, level).satisfiable):
		return {"satisfiable": true, "why": "a larger stage breaks it"}
	return {"satisfiable": false, "why": "%s refuses every blow the giant has (%s)" % [world_id, ", ".join(why)]}


## Synthetic hits the giant can deal now: its weapon's light (melee, with the weapon's tags) and,
## with Boulder Hurl known and allowed, a projectile.
static func _player_hits(player: GiantPlayer) -> Array[HitEvent]:
	var out: Array[HitEvent] = []
	var melee := HitEvent.new()
	melee.attacker_id = player.entity.entity_id
	melee.category = "melee"
	melee.attacker_growth_stage = player.current_growth_stage()
	var tags := PackedStringArray(["Melee", "BasicAttack"])
	for t: Variant in player.current_weapon().get("tags", []):
		tags.append(str(t))
	melee.tags = tags
	out.append(melee)
	var perms: Array = player.profile.get("interaction_permissions", [])
	if player.known_abilities.has(PlayerGrab.HURL_ID) and perms.has(PlayerGrab.HURL_PERMISSION):
		var hurl := HitEvent.new()
		hurl.attacker_id = player.entity.entity_id
		hurl.category = "projectile"
		hurl.attacker_growth_stage = player.current_growth_stage()
		hurl.tags = PackedStringArray(["Ability", "Projectile", "Ranged"])
		out.append(hurl)
	return out


static func _tree_available(player: GiantPlayer, level: LevelRoot) -> bool:
	if player.equipment != null and player.equipment.owns("weapon.tree_oak"):
		return true
	for n in level.find_children("*", "", true, false):
		if n is UprootTree and not (n as UprootTree).uprooted:
			return true
	return false


static func _flag_possible(c: Dictionary) -> Dictionary:
	var flag := str(c.get("flag", ""))
	if not WorldState.has_flag(flag):
		return {"satisfiable": true, "why": "%s is not set yet" % flag}
	if c.has("equals") and not QuestConditions.flag_matches(WorldState.get_flag(flag), {"equals": c.equals}):
		# Outcomes and offers are first-write-wins: once set to something else they stay.
		if flag.begins_with("quest.village.") or flag.begins_with("reward."):
			return {"satisfiable": false, "why": "%s is %s for good (wanted %s)" % [flag, WorldState.get_flag(flag), c.equals]}
	return {"satisfiable": true, "why": "%s can still change" % flag}


static func _item_possible(item_id: String, level: LevelRoot) -> Dictionary:
	if WorldState.count_of(item_id) > 0:
		return {"satisfiable": true, "why": "held"}
	for n in level.find_children("*", "", true, false):
		if n is ItemPickup and (n as ItemPickup).item_id == item_id and not (n as ItemPickup).taken:
			return {"satisfiable": true, "why": "%s lies at %s" % [item_id, (n as ItemPickup).world_id]}
	return {"satisfiable": false, "why": "no %s held or lying anywhere" % item_id}


static func _stage_possible(stage: int, player: GiantPlayer, level: LevelRoot) -> Dictionary:
	if player.current_growth_stage() >= stage:
		return {"satisfiable": true, "why": "at stage %d" % player.current_growth_stage()}
	for n in level.get_tree().get_nodes_in_group(Shrine.GROUP):
		var s := n as Shrine
		if s == null or not level.is_ancestor_of(s):
			continue
		var rec := s.record()
		if bool(rec.get("allows_growth", false)) and int(rec.get("max_stage", 1)) >= stage:
			return {"satisfiable": true, "why": "%s grows to stage %d" % [s.world_id, int(rec.get("max_stage", 1))]}
	return {"satisfiable": false, "why": "no shrine grows the giant to stage %d" % stage}


# --------------------------------------------------------------------------- invariants

## The per-tick invariants of a bot run (plan §5.2); [] when all hold. ctx: "player", "level",
## "metrics" (RunMetrics: duplicate rewards since `dup_seen`), "dup_seen" (int).
static func check_invariants(tree: SceneTree, player: GiantPlayer, level: LevelRoot, metrics: RunMetrics,
		dup_seen: int) -> PackedStringArray:
	var out := PackedStringArray()
	if player != null and is_instance_valid(player) and player.is_inside_tree():
		var pos := player.global_position
		if not pos.is_finite():
			out.append("player position is not finite (%s)" % pos)
		elif pos.y <= MIN_PLAYER_Y:
			out.append("player fell out of the world (y %.1f)" % pos.y)
		var lock_id := player.lock.target_id
		if lock_id != "":
			var t := Sim.get_entity(lock_id)
			if t == null or not t.is_alive():
				out.append("lock target %s is %s" % [lock_id, "gone" if t == null else "dead"])
	if Sim.pending_hit_count() >= MAX_PENDING_HITS:
		out.append("pending hits %d >= %d" % [Sim.pending_hit_count(), MAX_PENDING_HITS])
	var pool := tree.get_first_node_in_group("debris_pool") as DebrisPool if tree != null else null
	if pool != null and pool.active_count() > MAX_DEBRIS:
		out.append("debris %d > %d" % [pool.active_count(), MAX_DEBRIS])
	for e: CombatEntity in Sim.entities():
		var melee := Sim.token_holders(e.entity_id).size()
		if melee > MAX_MELEE_TOKENS:
			out.append("%d melee tokens on %s" % [melee, e.entity_id])
		var ranged := Sim.token_holders(e.entity_id + ":ranged").size()
		if ranged > MAX_RANGED_TOKENS:
			out.append("%d ranged tokens on %s" % [ranged, e.entity_id])
	if metrics != null and metrics.duplicate_rewards.size() > dup_seen:
		for i in range(dup_seen, metrics.duplicate_rewards.size()):
			out.append("reward granted twice: %s" % str(metrics.duplicate_rewards[i][1]))
	if level != null and is_instance_valid(level):
		var d := level.director()
		if d != null and d.active_combatant_count() > d.max_active_enemies:
			out.append("active combatants %d > %d" % [d.active_combatant_count(), d.max_active_enemies])
	if tree != null:
		var seen := {}
		for group: String in ["enemies", "player", "npcs", "dummies"]:
			for n in tree.get_nodes_in_group(group):
				if not (n is Node3D) or not (n as Node3D).is_inside_tree():
					continue
				var ent: Variant = n.get("entity")
				if not (ent is CombatEntity):
					continue
				var id := (ent as CombatEntity).entity_id
				if id == "":
					continue
				if seen.has(id) and seen[id] != n:
					out.append("entity %s registered twice (%s and %s)" % [id, (seen[id] as Node).name, n.name])
				seen[id] = n
				if not n.is_queued_for_deletion() and (ent as CombatEntity).is_inside_tree():
					var reg := Sim.get_entity(id)
					if reg != null and reg != ent:
						out.append("entity %s: the registry holds another node" % id)
		for n in tree.get_nodes_in_group(ScreenStack.GROUP):
			var s := n as ScreenStack
			if s != null and s.open_seconds() > MAX_SCREEN_OPEN_S:
				out.append("a pausing screen (%s) has been open %.1f s" % [_top_name(s), s.open_seconds()])
	return out


static func _top_name(s: ScreenStack) -> String:
	var t := s.top()
	return str(t.get_script().resource_path.get_file()) if t != null and t.get_script() != null else "?"


## Node growth (plan §5.2): the node count sampled after each load (spawned actors left out)
## growing at every one of NODE_GROWTH_CYCLES consecutive reload cycles by more than
## NODE_GROWTH_FRACTION in all is a leak. "" when there is none.
static func node_growth_failure(load_samples: Array) -> String:
	var n := load_samples.size()
	if n < NODE_GROWTH_CYCLES + 1:
		return ""
	var window := load_samples.slice(n - NODE_GROWTH_CYCLES - 1)
	for i in range(1, window.size()):
		if int(window[i][1]) <= int(window[i - 1][1]):
			return ""
	var first := float(window[0][1])
	var last := float(window[window.size() - 1][1])
	if last > first * (1.0 + NODE_GROWTH_FRACTION):
		return "nodes grew at %d consecutive loads: %d -> %d" % [NODE_GROWTH_CYCLES, int(first), int(last)]
	return ""


static func _flat(a: Vector3, b: Vector3) -> float:
	if not a.is_finite() or not b.is_finite():
		return INF
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _v(p: Vector3) -> Array:
	if not p.is_finite():
		return []
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)]
