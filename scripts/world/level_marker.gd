class_name LevelMarker
extends Marker3D
## A named point of a level (plan §2.7.4, §2.2): objective markers (quest tracker, bot), AI
## cover, elevation and formation points, civilians' safe points, patrol points and bot route
## points. It joins the group of its kind (KIND_GROUPS) and "level_markers"; LevelRoot.marker(id)
## finds it by marker_id. Joined in _notification, so subclasses need no super() calls.
##
## The groups are the contract for the AI: soldiers holding formation search
## "ai_formation_points" (matching faction or none; EnemyActor, P04), archers "ai_cover_points"
## and "ai_elevation_points" (P09), civilians "safe_markers" (P11b). Test scenes may put plain
## Marker3D nodes into these groups instead.

enum Kind { OBJECTIVE, COVER, ELEVATION, FORMATION, SAFE, PATROL, BOT_ROUTE }

## The group each Kind joins (index = Kind value).
const KIND_GROUPS := ["objective_markers", "ai_cover_points", "ai_elevation_points",
	"ai_formation_points", "safe_markers", "patrol_points", "bot_route_points"]
## Every LevelMarker, whatever its kind (LevelRoot lookups).
const GROUP := "level_markers"

## Stable id, e.g. "valley.marker.elder" ("" = anonymous: found by group only).
@export var marker_id := ""
## What the point is for; changing it moves the marker to the new kind's group.
@export var kind: Kind = Kind.OBJECTIVE:
	set(value):
		if value == kind:
			return
		if is_inside_tree():
			remove_from_group(group_for(kind))
		kind = value
		if is_inside_tree():
			add_to_group(group_for(kind))
## "" = anyone; otherwise only actors of this faction use it (formation posts of the village guards).
@export var faction := ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		add_to_group(GROUP)
		add_to_group(group_for(kind))


## The group a marker of `k` joins ("" for an unknown kind).
static func group_for(k: int) -> String:
	return KIND_GROUPS[k] if k >= 0 and k < KIND_GROUPS.size() else ""
