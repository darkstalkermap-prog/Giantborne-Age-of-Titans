class_name WorldXp
extends RefCounted
## The world's guaranteed-XP arithmetic for the XP budget tests (P29; plan M6-M9 §5.8): quest XP of
## mandatory stages (without the xp_floor_level lifts, which only add), a resolution's own XP (the
## dialogue choices that write the oath's outcome, plus the XP of the props and kills its declared
## path cannot avoid), the discoveries a mandatory path cannot avoid (the POIs whose radius covers one
## of its points) and the level table. Records and the world's index only. P35 and P36 add their
## oaths' tests with the same helpers.

const LEVEL := "level.world"


## world_start's XP (the Valley's worst guaranteed outcome).
static func world_start_xp() -> int:
	return int((Progression.record().get("world_start", {}) as Dictionary).get("xp", 0))


## The cumulative XP of `level` (Progression's table).
static func xp_for_level(level: int) -> int:
	return Progression.xp_for_level(level)


## The level a growth profile asks for (growth.04 -> 7).
static func growth_level(profile_id: String) -> int:
	return int(GameData.get_record(profile_id).get("required_level", 1))


## The stage record `stage_id` of `quest_id` ({} when there is none).
static func stage(quest_id: String, stage_id: String) -> Dictionary:
	for s: Dictionary in GameData.get_record(quest_id).get("stages", []):
		if str(s.get("id", "")) == stage_id:
			return s
	return {}


## The XP of the named stages of `quest_id` (every stage when `stage_ids` is empty).
static func stages_xp(quest_id: String, stage_ids: Array = []) -> int:
	var total := 0
	for s: Dictionary in GameData.get_record(quest_id).get("stages", []):
		if stage_ids.is_empty() or stage_ids.has(str(s.get("id", ""))):
			total += int(s.get("xp", 0))
	return total


## The XP of the dialogue choice that writes `flag` = `value` (the resolution's own XP: an oath's
## outcome flag is written by the choice that wins it) - the least of them when several do (the worst
## case); 0 when none does.
static func choice_xp_writing(flag: String, value: Variant) -> int:
	var worst := -1
	for rec: Dictionary in GameData.records_of_type("dialogue"):
		for n: Dictionary in rec.get("nodes", []):
			for c: Dictionary in n.get("choices", []):
				var e: Dictionary = c.get("effects", {}) if typeof(c.get("effects")) == TYPE_DICTIONARY else {}
				var flags: Dictionary = e.get("set_flags", {}) if typeof(e.get("set_flags")) == TYPE_DICTIONARY else {}
				if flags.has(flag) and QuestConditions.same_value(flags[flag], value):
					var xp := int(e.get("xp", 0))
					worst = xp if worst < 0 else mini(worst, xp)
	return maxi(worst, 0)


## A prop record's XP on destruction.
static func prop_xp(prop_id: String) -> int:
	return int(GameData.get_record(prop_id).get("xp_reward", 0))


## The kill XP of a spawn (its definition's xp_reward), found through the encounter records.
static func kill_xp(entity_id: String) -> int:
	for rec: Dictionary in GameData.records_of_type("encounter"):
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.get("entity_id", "")) == entity_id:
				return int(GameData.get_record(str(sp.definition)).get("xp_reward", 0))
	return 0


## The XP of an oath's resolution `outcome` (quest.oath_<key>): every stage's XP, the choice that
## writes oath.<key>.outcome = outcome, and `extra` (the declared path's props and kills: an array of
## prop record ids and spawn entity ids).
static func resolution_xp(quest_id: String, outcome: String, extra: Array = []) -> int:
	var key := OathRules.oath_key(quest_id)
	var total := stages_xp(quest_id) + choice_xp_writing(OathRules.outcome_flag(key), outcome)
	for id: Variant in extra:
		var rec := GameData.get_record(str(id))
		total += prop_xp(str(id)) if str(rec.get("type", "")) == "prop" else kill_xp(str(id))
	return total


## The world position of a place id (the world's index: markers, checkpoints, props, POIs...), or of
## a spawn (its record's position); Vector3.INF when unknown.
static func position_of(id: String) -> Vector3:
	var idx := WorldIndex.for_level(LEVEL)
	if idx != null:
		var p := idx.position_of(id)
		if p.is_finite():
			return p
	for rec: Dictionary in GameData.records_of_type("encounter"):
		if str(rec.get("level", "")) != LEVEL:
			continue
		for sp: Dictionary in rec.get("spawns", []):
			if str(sp.get("entity_id", "")) == id:
				var a: Array = sp.position_m
				return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.INF


## poi id -> discovery XP of the world's POIs whose radius covers one of `points` (place ids or
## Vector3s): the discoveries a path through them cannot avoid.
static func discoveries_covering(points: Array) -> Dictionary:
	var out := {}
	for poi: Dictionary in GameData.records_of_type("poi"):
		if str(poi.get("level", "")) != LEVEL:
			continue
		var a: Array = poi.position_m
		var c := Vector2(float(a[0]), float(a[2]))
		for pt: Variant in points:
			var p: Vector3 = pt if pt is Vector3 else position_of(str(pt))
			if p.is_finite() and Vector2(p.x, p.z).distance_to(c) <= float(poi.get("radius_m", 0.0)):
				out[str(poi.id)] = int(poi.get("xp", 0))
				break
	return out


static func sum(d: Dictionary) -> int:
	var total := 0
	for k: Variant in d:
		total += int(d[k])
	return total
