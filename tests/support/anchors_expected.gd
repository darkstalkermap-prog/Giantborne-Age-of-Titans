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
}

const EVENTS_PACKAGES := ["P02", "P03", "P04", "P05", "P06", "P07", "P08", "P09", "P10a", "P10b",
	"P11a", "P11b", "P12", "P13", "P14", "P15", "P16", "P17a", "P17b", "P18"]

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
