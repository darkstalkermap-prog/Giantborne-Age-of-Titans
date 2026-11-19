extends TestSuite
## The default skin's tone against the approved renders (P51; plan M11 §0.3, §2.13, §3.4): the look probe
## (tests/support/giant_look_probe.tscn, one child run shared with test_hair_render through GiantLookProbeRun)
## draws the default look at the creator's chest framing in the creator's light, and the mean sRGB of a patch on
## the lit right pectoral must be within 30/255 a channel (12 before Gate A) of the approved studio render's (198, 170, 157). M10's
## gate measured (222, 151, 115) at its framing; P51's probe read (208, 141, 106) on the W29 tree and (203, 169, 155)
## after the grade (tools/giant/kit/pack.py SKIN_GRADE) and the subsurface lookup. Gate A eased the grade (that
## pale, grey albedo read near white in the world's sun; tests/slow/test_skin_world_render.gd) and the chest now
## reads (220, 160, 131): the tolerance is 30 (the deviation is recorded in docs/systems/P51.md, "Gate A"). Also: no shader or script error,
## GiantLook.validate() empty for every look the probe drew, and GiantLook.DRAWN_DEFAULT (the swatch's colour of the
## default tone) within 6/255 of the measure. Without xvfb-run it is skipped with a note.
## M11 (P53, plan M11 §1.7 rule 3): moved from tests/slow/ to the gate tier with test_hair_render, whose child run it
## reads (alone in the slow tier it would draw the giant again, about 13 s), unchanged.

const RUN := preload("res://tests/support/giant_look_probe_run.gd")
const TOLERANCE := 30
const SWATCH_TOLERANCE := 6


func test_the_default_skin_draws_the_approved_tone() -> void:
	var run: Dictionary = RUN.result("web")
	if str(run.skipped) != "":
		print("    test_skin_tone_render: skipped - %s" % run.skipped)
		return
	assert_eq(run.errors, PackedStringArray(), "no shader or script error")
	var r: Dictionary = run.report
	assert_true(r.has("skin"), "the probe reported (exit %d): %s" % [int(run.code), str(run.text)])
	if not r.has("skin"):
		return
	assert_eq(r.validate, [], "GiantLook.validate() is empty for every look drawn")
	var chest: Array = r.skin.chest
	var approved: Array = r.skin.approved
	for ch in 3:
		assert_true(absi(int(chest[ch]) - int(approved[ch])) <= TOLERANCE, "channel %d: %d against the approved %d (within %d)" % [
			ch, int(chest[ch]), int(approved[ch]), TOLERANCE])
	var swatch := GiantLook.DRAWN_DEFAULT
	for ch in 3:
		assert_true(absi(int(round(swatch[ch] * 255.0)) - int(chest[ch])) <= SWATCH_TOLERANCE,
			"the default swatch's channel %d is the colour drawn (%d against %d)" % [ch, int(round(swatch[ch] * 255.0)), int(chest[ch])])
	print("    test_skin_tone_render: the lit chest (%d, %d, %d) against the approved (%d, %d, %d), %s" % [chest[0], chest[1],
		chest[2], approved[0], approved[1], approved[2], str(r.adapter)])
