extends IntegrationSuite
## M8 gate (F21): --walk-stage (WorldWalk's stage option) on the tiny streamed world (tests/support/
## living_world_fixtures.gd). Before, the walk asked PlayerGrowth once, right after placing the giant -
## refused "busy" (not on the floor yet) - and walked at the old stage without a word, so the gate's
## "stage-3 giant walks the Needle" walked a stage-1 giant. Now it asks again until the giant stands on
## the floor and free, walks at the stage, and a stage never reached fails the walk ("stage N not
## reached") and walks nothing. tests/gate/test_world_reachability.gd checks the Needle walk's stage.

const LW := preload("res://tests/support/living_world_fixtures.gd")


## A WorldWalk on the tiny streamed world (two short legs on its road) with `opts`; its report once done
## (at most `max_ticks`).
func _tiny_walk(opts: Dictionary, wait_ticks: int, max_ticks: int) -> Dictionary:
	LW.install()
	var made := LW.make(world)
	var w: WorldRoot = made[0]
	TestSpawn.disable_all_ai(w)
	var walk := WorldWalk.new()
	walk.name = "WorldWalk"
	walk.stage_wait_ticks = wait_ticks
	add_child(walk)
	var o := {"route": PackedVector3Array([Vector3(-96.0, 0.0, 16.0), Vector3(-80.0, 0.0, 16.0)]), "speed": 8.0}
	o.merge(opts, true)
	walk.start(w.player(), w, null, o)
	var ticks := 0
	while not walk.done and ticks < max_ticks:
		await step_ticks(1)
		ticks += 1
	var r := walk.result()
	r["done"] = walk.done
	r["walked_stage"] = w.player().current_growth_stage()
	walk.queue_free()
	w.queue_free()
	await get_tree().process_frame
	LW.reset()
	return r


func test_the_walk_grows_the_giant_to_its_stage_or_fails() -> void:
	# the giant is placed at the route's start and is not on the floor at once: the growth is asked again
	var r: Dictionary = await _tiny_walk({"stage": 2}, WorldWalk.STAGE_WAIT_TICKS, 600)
	assert_true(bool(r.done), "the walk ends")
	assert_eq(str(r.stage_error), "", "no stage error")
	assert_eq(int(r.stage), 2, "it walked at stage 2 (was: refused once as busy and walked at stage 1)")
	assert_true(bool(r.finished), "and finished its route")
	for f: String in r.check_failures:
		assert_false(f.contains("not reached"), "no stage failure (%s)" % f)   # (the tiny world is too small for the 200 m margin)
	# a stage the giant cannot reach (no such profile) fails the walk and walks nothing
	r = await _tiny_walk({"stage": 9}, 30, 300)
	assert_true(bool(r.done), "the walk ends")
	assert_true(str(r.stage_error).begins_with("stage 9 not reached"), "stage 9 not reached: %s" % r.stage_error)
	assert_eq(Array(r.check_failures), [r.stage_error], "the walk fails with it, and only it")
	assert_false(bool(r.finished), "nothing was walked")
