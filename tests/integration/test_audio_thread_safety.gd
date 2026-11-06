extends TestSuite
## P23 (FOLLOWUPS, "the crash in the audio mixing thread"): the engine's frame waits for a mix step
## that is still running (AudioDirector.mix_barrier), so the AudioServer never frees a playback's
## replaced bus details while the mixing thread may still copy them; and the music and ambience
## directors write a player's volume only when it changes (each write replaces those details).
## The race itself needs a preempted mixing thread and is reproduced outside the suite
## (docs/systems/P23.md, "The audio-thread crash").

const HOLD_MS := 40


func before_each() -> void:
	Audio.enable_for_tests()


func after_each() -> void:
	Audio.enable_for_tests(false)


## A helper thread holds the driver's lock, as the mixing thread does for the whole of a mix step:
## the engine's frame must wait for it before it goes on (and so before AudioServer.update()).
func test_a_frame_waits_for_a_running_mix_step() -> void:
	var locked := Semaphore.new()
	var holder := Thread.new()
	holder.start(func() -> void:
		AudioServer.lock()
		locked.post()
		OS.delay_msec(HOLD_MS)
		AudioServer.unlock())
	locked.wait()
	var before := Audio.mix_barriers
	var t0 := Time.get_ticks_usec()
	Audio._process(1.0 / 60.0)
	var waited_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	holder.wait_to_finish()
	assert_eq(Audio.mix_barriers, before + 1, "one barrier a frame")
	assert_true(waited_ms >= HOLD_MS * 0.6, "the frame waited for the mix step holding the lock (%.1f ms)" % waited_ms)


## Without a running mix step the barrier costs nothing noticeable.
func test_the_barrier_is_cheap_when_nothing_mixes() -> void:
	var t0 := Time.get_ticks_usec()
	for i in 200:
		Audio.mix_barrier()
	var per_us := float(Time.get_ticks_usec() - t0) / 200.0
	# The Dummy driver mixes a 4,096-frame buffer every 93 ms; a barrier that meets it waits for it.
	assert_true(per_us < 2000.0, "a barrier costs %.1f us on average" % per_us)


## A disabled engine (the default suite, --no-audio) takes no lock: it has no players.
func test_no_barrier_while_disabled() -> void:
	Audio.enable_for_tests(false)
	var before := Audio.mix_barriers
	Audio._process(1.0 / 60.0)
	assert_eq(Audio.mix_barriers, before, "no barrier while the engine is off")


## MusicDirector.set_volume writes only a change: a steady stem replaces nothing in the server.
func test_volumes_are_written_only_when_they_change() -> void:
	var p := AudioStreamPlayer.new()
	add_child(p)
	p.volume_db = -10.0
	MusicDirector.set_volume(p, -10.004)
	assert_eq(p.volume_db, -10.0, "a change under 0.01 dB is not written")
	MusicDirector.set_volume(p, -12.5)
	assert_near(p.volume_db, -12.5, 1e-5, "a real change is written")
	var p3 := AudioStreamPlayer3D.new()
	add_child(p3)
	p3.volume_db = -3.0
	MusicDirector.set_volume(p3, -3.0)
	assert_eq(p3.volume_db, -3.0, "3D players too")
	p.queue_free()
	p3.queue_free()
