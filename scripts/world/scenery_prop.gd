class_name SceneryProp
extends Node3D
## A placed piece of scenery with a stable id and no behaviour (P26): the Citadel's hoard pile. Its
## world_id makes it a prop of the level like the others: the Valley builder names and sets it from
## the layout, LevelRoot finds it under Props/, and the world index lists it (WorldIndex reads any
## Node3D with a world_id).

## Stable id, e.g. "valley.citadel.hoard" (the layout sets it).
@export var world_id := ""
