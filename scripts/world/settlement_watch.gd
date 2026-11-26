class_name SettlementWatch
extends Node
## C4: a runtime node of both campaign levels (LevelRoot.RUNTIME_NODES) that keeps the level's settlements in step
## with their state (decision C4-3):
##   * as the level loads: any flag the state holds that the world lacks is put back (SettlementWork.mend_flags), and
##     every built tier's life is there (its settled flag): a later load of the giant's ground shows it whole;
##   * the life of a tier the giant has just raised - its folk, its fires and smoke, its banners, its garrison - comes
##     once he has gone beyond the settlement's settle_m (A3-4's rule: the settlement changes behind the giant's
##     back), Events.settlement_settled;
##   * the folk mend what a raid took (the record's `mends`): once its event has ended and the giant is beyond
##     settle_m, the dead it names are replaced (WorldState.forget_loss: their encounter spawns them again on its
##     next activation);
##   * a project whose needs have all come to be met (a deed done in the world) is announced once
##     (Events.settlement_ready: the HUD's toast), not at the load itself.
## Every POLL_TICKS of the simulation (POST_RESOLVE, after Discovery).

const HOOK_ORDER := 165
const POLL_TICKS := 30
const DEFAULT_SETTLE_M := 150.0

var level_id := ""
## Tests: the giant's position to judge distances by (INF: the player's).
var position_override := Vector3.INF
var _records: Array = []
var _ready_seen := {}   ## "<settlement>/<project>" -> true once its readiness was seen (announced or at load)
var _started := false


func _ready() -> void:
	if level_id == "":
		var root := get_parent() as LevelRoot
		level_id = root.level_id if root != null else GameSession.current_level_id()
	refresh()
	Sim.add_hook(Sim.Hook.POST_RESOLVE, self, _on_tick, HOOK_ORDER)


func _exit_tree() -> void:
	Sim.remove_hooks(self)


## Re-reads the settlement records (tests that install records): every level's - a settlement on another level is
## always beyond the giant (its auto projects and its tiers' life come while he is away from it).
func refresh() -> void:
	_records = SettlementRules.records()


## Where settlement `rec` stands (its centre_m, else its POI's position; INF when neither).
static func centre_of(rec: Dictionary) -> Vector3:
	var c: Variant = rec.get("centre_m")
	if typeof(c) == TYPE_ARRAY and (c as Array).size() == 3:
		return Vector3(float(c[0]), float(c[1]), float(c[2]))
	var p := GameData.get_record(str(rec.get("poi", "")))
	var pos: Variant = p.get("position_m")
	if typeof(pos) == TYPE_ARRAY and (pos as Array).size() == 3:
		return Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	return Vector3.INF


func _giant_position() -> Vector3:
	if position_override != Vector3.INF:
		return position_override
	var p := GameSession.player()
	return p.global_position if p != null and is_instance_valid(p) and p.is_inside_tree() else Vector3.INF


## The level's first tick: the flags mended and every built tier settled (a later load shows it whole).
func start() -> void:
	_started = true
	SettlementWork.mend_flags("")
	for rec: Dictionary in _records:
		var st := SettlementWork.state(rec)
		for k in range(1, SettlementRules.tier_of(st) + 1):
			WorldState.set_flag(SettlementRules.settled_flag(rec, k), true)
		_mend(rec, true)
		var ctx := SettlementWork.context()
		for p: Dictionary in SettlementRules.current_projects(rec, st):
			if bool(p.get("auto", false)) and bool(SettlementRules.project_status(rec, str(p.id), st, ctx).get("ready", false)):
				SettlementWork.raise(rec, str(p.id), true)
				for k in range(1, SettlementRules.tier_of(st) + 1):
					WorldState.set_flag(SettlementRules.settled_flag(rec, k), true)
		for p: Dictionary in SettlementRules.current_projects(rec, st):
			var s := SettlementRules.project_status(rec, str(p.id), st, ctx)
			if bool(s.get("ready", false)):
				_ready_seen["%s/%s" % [str(rec.id), str(p.id)]] = true


func _on_tick(tick: int) -> void:
	if not _started:
		start()
		return
	if tick % POLL_TICKS != 0:
		return
	poll()


## One poll (tests call it directly).
func poll() -> void:
	var at := _giant_position()
	for rec: Dictionary in _records:
		var st := SettlementWork.state(rec)
		var away := _beyond(rec, at)
		if away:
			for k in range(1, SettlementRules.tier_of(st) + 1):
				var f := SettlementRules.settled_flag(rec, k)
				if not QuestConditions.truthy(WorldState.get_flag(f)):
					WorldState.set_flag(f, true)
					Events.settlement_settled.emit(Sim.tick, str(rec.id), k)
			_mend(rec, false)
			# an auto project (an older settlement's aftermath) raises itself once ready, behind the giant's back
			var actx := SettlementWork.context()
			for p: Dictionary in SettlementRules.current_projects(rec, st):
				if bool(p.get("auto", false)) and bool(SettlementRules.project_status(rec, str(p.id), st, actx).get("ready", false)):
					SettlementWork.raise(rec, str(p.id), true)
		var ctx := SettlementWork.context()
		for p: Dictionary in SettlementRules.current_projects(rec, st):
			var key := "%s/%s" % [str(rec.id), str(p.id)]
			if _ready_seen.has(key):
				continue
			var s := SettlementRules.project_status(rec, str(p.id), st, ctx)
			if bool(s.get("ready", false)) and not bool(s.get("raised", false)) and not bool(s.get("auto", false)):
				_ready_seen[key] = true
				Events.settlement_ready.emit(Sim.tick, str(rec.id), str(p.id))


## True when the giant stands beyond the settlement's settle_m (or no giant / no centre is known, or the settlement is
## on another level).
func _beyond(rec: Dictionary, at: Vector3) -> bool:
	if str(rec.get("level", "")) != level_id:
		return true
	var c := centre_of(rec)
	if at == Vector3.INF or c == Vector3.INF:
		return true
	return Vector2(at.x - c.x, at.z - c.z).length() > float(rec.get("settle_m", DEFAULT_SETTLE_M))


## The record's mends whose event has ended since the last mend: the dead it names forgotten (`now`: at a load, or
## the giant away). Each event end is mended once (<prefix>.mended.<event short> holds the end's play time).
func _mend(rec: Dictionary, _at_load: bool) -> void:
	for m: Dictionary in rec.get("mends", []):
		var ev := str(m.get("after_event", ""))
		var end_s: Variant = WorldState.get_flag(ev + ".last_end_s")
		var start_s: Variant = WorldState.get_flag(ev + ".last_start_s")
		if not SchemaUtil.is_number(end_s):
			continue
		if SchemaUtil.is_number(start_s) and float(start_s) > float(end_s):
			continue   # running again
		var mark := "%s.mended.%s" % [SettlementRules.prefix(rec), QuestConditions.short_of(ev)]
		var done: Variant = WorldState.get_flag(mark)
		if SchemaUtil.is_number(done) and float(done) >= float(end_s):
			continue
		for id: Variant in (m.get("killed", []) as Array) + (m.get("destroyed", []) as Array):
			WorldState.forget_loss(str(id))
		WorldState.set_flag(mark, float(end_s))
