class_name TitanArenaTest
extends Node3D
## A2: the quarry test arena's root (scenes/test/quarry_test.tscn): Stoneback in a quarry bowl, not yet placed in
## the open world. On its first physics tick it readies the giant for the stage the command line asks for
## (--titan-stage=N, default 5: TitanDuel.prepare - the stage's required level, the bots' attribute spending, the
## campaign's weapon for that stage):
##
##   tools/gd.sh --path . -- --level=res://scenes/test/quarry_test.tscn --titan-stage=4
##
## `stage` set in the scene (or by a test before it enters the tree) wins over the option; 0 leaves the giant as
## the scene made it (tests that set it up themselves).

const PLAYER := "Player"

@export var stage := -1
## What TitanDuel.prepare answered ({} until it ran).
var prepared: Dictionary = {}
var _done := false


func _physics_process(_dt: float) -> void:
	if _done:
		return
	var want := stage if stage >= 0 else TitanDuel.cli_stage()
	var p := get_node_or_null(PLAYER) as GiantPlayer
	if want <= 0 or p == null:
		_done = true
		return
	if not p.is_on_floor():
		return   # (the giant lands first: the growth asks for the floor)
	_done = true
	prepared = TitanDuel.prepare(p, want)
	print("[quarry] the giant at stage %d, level %d, %s (%d health)" % [want, int(prepared.get("level", 0)),
		str(prepared.get("weapon", "")), int(prepared.get("health", 0.0))])
