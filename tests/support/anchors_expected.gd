class_name AnchorsExpected
extends RefCounted
## The package-anchor table of plan §1.5, read by tests/unit/test_anchors.gd. A package that
## must add code to one of these shared files inserts it directly below its own
## "## @anchor <package>" line, so two packages of one wave edit different hunks.
##
## Each file's anchors are written by the package that creates (or first restructures) the
## file. Until that package has landed on the branch, its rows cannot be checked yet: CREATORS
## names, per creator, a file that only exists once that package is merged ("" = this package,
## always checked).

const CREATORS := {
	"P01": "res://scripts/core/schemas/schema_util.gd",
	"P02": "",
	"P03": "res://scripts/world/projectile_system.gd",
	# M6-M9: P20 wrote every anchor of the M6-M9 plan's §1.5 table in W12 (and one in each new
	# schema module of its own for the package that ships the first records).
	"P20": "res://scripts/world/world_index.gd",
}

const EVENTS_PACKAGES := ["P02", "P03", "P04", "P05", "P06", "P07", "P08", "P09", "P10a", "P10b",
	"P11a", "P11b", "P12", "P13", "P14", "P15", "P16", "P17a", "P17b", "P18"]
## The M6-M9 packages with an anchor in events.gd (plan M6-M9 §1.5: P21-P40, P24 split in two).
const EVENTS_PACKAGES_M6 := ["P21", "P22", "P23", "P24a", "P24b", "P25", "P26", "P27", "P28", "P29",
	"P30", "P31", "P32", "P33", "P34", "P35", "P36", "P37", "P38", "P39", "P40"]

## [file, creator, anchors]
const TABLE := [
	["res://scripts/core/events.gd", "P01", EVENTS_PACKAGES],
	["res://scripts/core/schemas/action_schema.gd", "P01", ["P03", "P04", "P07", "P09", "P11a"]],
	["res://scripts/core/schemas/enemy_schema.gd", "P01", ["P04", "P07", "P09", "P10a", "P11a", "P11b", "P12"]],
	["res://scripts/core/schemas/prop_schema.gd", "P01", ["P08", "P12"]],
	["res://scripts/core/schemas/weapon_schema.gd", "P01", ["P08", "P12"]],
	["res://scripts/core/schemas/growth_profile_schema.gd", "P01", ["P05"]],
	["res://scripts/core/schemas/player_schema.gd", "P01", ["P05"]],
	["res://scripts/core/schemas/item_schema.gd", "P01", ["P12"]],
	["res://scripts/core/game_data.gd", "P01", ["P09", "P10a", "P12"]],
	["res://scripts/actors/enemy_actor.gd", "P02", ["P04", "P07", "P09", "P10a", "P11a", "P11b"]],
	["res://scripts/ai/enemy_brain.gd", "P02", ["P04", "P07", "P09", "P10a", "P11a", "P11b"]],
	["res://scripts/actors/attack_runner.gd", "P02", ["P03", "P07", "P09", "P11a"]],
	["res://scripts/combat/hit_factory.gd", "P02", ["P03", "P07"]],
	["res://scripts/combat/attack_context.gd", "P02", ["P03", "P07"]],
	["res://scripts/actors/player/player_targeting.gd", "P02", ["P03", "P11a"]],
	["res://scripts/presentation/actor_rig.gd", "P03", ["P05", "P07", "P08"]],
	["res://scripts/world/projectile_system.gd", "P03", ["P07", "P09"]],
	# M6-M9 (plan M6-M9 §1.5, written by P20)
	["res://scripts/core/events.gd", "P20", EVENTS_PACKAGES_M6],
	["res://scripts/actors/enemy_actor.gd", "P20", ["P22", "P24b", "P30", "P32", "P34", "P37"]],
	["res://scripts/ai/enemy_brain.gd", "P20", ["P22", "P24b", "P30", "P32", "P34", "P37"]],
	["res://scripts/actors/attack_runner.gd", "P20", ["P30", "P31", "P32", "P34"]],
	["res://scripts/combat/hit_factory.gd", "P20", ["P32"]],
	["res://scripts/world/projectile_system.gd", "P20", ["P31", "P32", "P34"]],
	["res://scripts/presentation/telegraph_visuals.gd", "P20", ["P30", "P31", "P32", "P34"]],
	["res://scripts/actors/player/player_targeting.gd", "P20", ["P30"]],
	["res://scripts/world/encounter_director.gd", "P20", ["P24b", "P29", "P30", "P32", "P34", "P37"]],
	["res://scripts/world/level_root.gd", "P20", ["P24a", "P24b", "P25", "P27"]],
	["res://scripts/quests/quests.gd", "P20", ["P27", "P29", "P37"]],
	["res://scripts/quests/quest_conditions.gd", "P20", ["P27", "P29", "P37"]],
	["res://scripts/core/game_data.gd", "P20", ["P24a", "P24b", "P25", "P26", "P29", "P30", "P31", "P32",
		"P33", "P34", "P37"]],
	["res://scripts/core/schemas/action_schema.gd", "P20", ["P26", "P31", "P32", "P34"]],
	["res://scripts/core/schemas/enemy_schema.gd", "P20", ["P22", "P30", "P32", "P34"]],
	["res://scripts/core/schemas/prop_schema.gd", "P20", ["P26", "P30", "P32"]],
	["res://scripts/core/schemas/weapon_schema.gd", "P20", ["P26", "P31", "P32"]],
	["res://scripts/core/schemas/growth_profile_schema.gd", "P20", ["P26", "P30"]],
	["res://scripts/core/schemas/encounter_schema.gd", "P20", ["P24b", "P29", "P30", "P37"]],
	["res://scripts/core/schemas/level_schema.gd", "P20", ["P24a", "P24b", "P25"]],
	["res://scripts/core/schemas/shrine_schema.gd", "P20", ["P26"]],
	["res://scripts/core/schemas/item_schema.gd", "P20", ["P31", "P33"]],
	["res://scripts/core/schemas/ancestry_schema.gd", "P20", ["P31", "P33"]],
	["res://scripts/core/schemas/player_schema.gd", "P20", ["P31", "P33"]],
	["res://scripts/presentation/camera_rig.gd", "P20", ["P24a", "P26", "P30"]],
	# P20's own new schema modules: the packages that ship their first records.
	["res://scripts/core/schemas/region_schema.gd", "P20", ["P25"]],
	["res://scripts/core/schemas/poi_schema.gd", "P20", ["P25", "P27"]],
	["res://scripts/core/schemas/faction_schema.gd", "P20", ["P22", "P29"]],
	["res://scripts/core/schemas/talent_schema.gd", "P20", ["P33"]],
	["res://scripts/core/schemas/wander_table_schema.gd", "P20", ["P37"]],
	["res://scripts/core/schemas/world_event_schema.gd", "P20", ["P37"]],
]


## True when the rows written by `creator` can be checked on this branch.
static func creator_landed(creator: String) -> bool:
	var sentinel := str(CREATORS.get(creator, "?"))
	return sentinel == "" or (sentinel != "?" and FileAccess.file_exists(sentinel))


## The anchor ids found in `text`: lines like "## @anchor P07" (any leading '#'s and
## whitespace; a trailing ':' or ',' after the id is ignored).
static func anchors_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if not line.begins_with("#"):
			continue
		line = line.lstrip("#").strip_edges()
		if not line.begins_with("@anchor"):
			continue
		var rest := line.substr(7).strip_edges()
		if rest == "":
			continue
		var id := rest.split(" ", false)[0].split("\t", false)[0].rstrip(":,")
		if id != "":
			out.append(id)
	return out
