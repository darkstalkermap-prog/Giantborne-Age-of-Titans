extends TestSuite
## The giant's hair, eyes, scars and marks against frames (P51; plan M11 §0.3, §2.13, §3.4), from the look probe
## (tests/support/giant_look_probe.tscn; one child run on the web tier shared with test_skin_tone_render through
## GiantLookProbeRun, and one of the hair alone on the hi tier). Required:
##   * every hair and beard style draws (its pixels above MIN_PX at the Face and Hair framings) on both tiers;
##   * the hair check against M10's frames (M10: the same probe on the W29 tree, whose hair is M10's): for every
##     style at each framing the outline's roughness at least M10's and the scalp share at most M10's, but for the
##     measures KNOWN_MISSES lists with what they read (docs/systems/P51.md) - each of those must still draw;
##   * a beard there from behind (BEHIND_FLOOR_PX of the tile from straight behind the head; M10 hid it: 0);
##   * the eye's highlight at the eye close-up and its `look` moving the iris;
##   * every scar and mark at least as visible in its creator framing as M10's, the brow, cheek and chest scars
##     widened to the 4 cm rule, and every design above the option check's floor in the stage-1 rear Game view or
##     first person but for those neither camera shows (NOT_IN_EITHER_VIEW, with the reason);
##   * a shell style one draw call (as a card style is).
## Without xvfb-run it is skipped with a note.
## M11 (P53, plan M11 §1.7 rule 3; FOLLOWUPS, P51's row): moved from tests/slow/ to the gate tier, unchanged, with
## test_skin_tone_render (they share the probe's child run): about 23 s of the slow tier.

const RUN := preload("res://tests/support/giant_look_probe_run.gd")
const MIN_PX := 300
const BEHIND_FLOOR_PX := 10
const HIGHLIGHT_FLOOR_PX := 4
const LOOK_FLOOR_PX := 200
## The option check's floors in the rear Game view and in first person (tests/gate/test_appearance_render.gd).
const VIEW_FLOOR_PX := {"rear": 18, "fp": 90}
## M10's frames (the probe on the W29 tree, P51's first run; docs/systems/P51.md): [roughness, scalp share].
const M10_HAIR := {
	"Hair_crop": {"face": [1.3609, 0.122], "hair": [1.1993, 0.0059]},
	"Hair_long_back": {"face": [1.5409, 0.165], "hair": [1.5, 0.0069]},
	"Hair_long_braided": {"face": [1.3875, 0.195], "hair": [1.4278, 0.0036]},
	"Hair_warrior_tail": {"face": [1.379, 0.12], "hair": [1.3982, 0.0797]},
	"Hair_wild_mane": {"face": [1.5422, 0.224], "hair": [2.0678, 0.0019]},
	"Beard_braided": {"face": [1.4333, 0.1736]},
	"Beard_forked": {"face": [1.2761, 0.2289]},
	"Beard_full": {"face": [1.5815, 0.2553]},
	"Beard_short": {"face": [1.4408, 0.2029]},
}
## The measures that do not beat M10's, "<style>@<framing>.<rough|scalp>" (P51's final run; docs/systems/P51.md
## gives each one's reading and its reason). A listed measure may come to beat M10's; the list is then stale and
## the test says so.
const KNOWN_MISSES := {
	"Hair_crop@face.rough": "the shells hug the head: a smoother outline than 1,100 standing cards",
	"Hair_crop@hair.rough": "the same",
	"Hair_crop@hair.scalp": "the shells thin out towards the nape where the cards covered it",
	"Hair_long_braided@face.scalp": "the hairline's fringe draws lighter over the paler skin and reads as skin",
	"Hair_long_braided@hair.rough": "the braids' tubes",
	"Hair_long_braided@hair.scalp": "the braids' tubes leave the nape's cards fewer",
	"Hair_warrior_tail@face.scalp": "the same",
	"Hair_wild_mane@face.rough": "outer locks traded for loose strands within the triangle cap",
	"Hair_wild_mane@hair.rough": "outer locks traded for loose strands within the triangle cap",
	"Beard_braided@face.rough": "the braids are tubes, not lobes of cards",
	"Beard_braided@face.scalp": "the same",
	"Beard_forked@face.scalp": "outer cards traded for the under-jaw row within the triangle cap (the full beard's beats M10's since Gate A's warmer skin)",
	"Beard_short@face.rough": "the shells: a dense short beard with a closed edge",
}
## M10's scars and marks in their creator framings (pixels of the 320x240 tile that change against the base).
const M10_FRAMED := {"scar.brow": 48, "scar.cheek": 88, "scar.chest_claws": 242, "scar.forearm_slash": 276,
	"scar.knuckles": 201, "scar.back_lash": 2642, "mark.granite_veins": 981, "mark.lightning_tree": 1081,
	"mark.claw_stripes": 311}
## Gate A: designs that read less in their creator framing on the softer, warmer skin (the wrapped lookup softens the
## relief's shading, the albedo is less grey) - their floor is this share of M10's instead of 0.9, with the reading
## (docs/systems/P51.md, "Gate A").
const GATE_A_FRAMED_SHARE := {"scar.forearm_slash": 0.8, "scar.back_lash": 0.8}
## The designs neither the stage-1 rear Game view nor first person can show above the floor, with the reason
## (each is checked in its creator framing above; docs/systems/P51.md has their readings).
const NOT_IN_EITHER_VIEW := {
	"scar.brow": "on the face: the rear view looks at his back, first person down his arms",
	"scar.cheek": "on the face",
	"mark.claw_stripes": "on the face",
	"scar.chest_claws": "on the chest: first person looks down the arms, the chest is culled with the torso",
	"scar.knuckles": "on the back of the left hand: first person looks down and to the right",
	"scar.forearm_slash": "on the inside of the right forearm, turned away from both cameras in the still pose",
	"mark.granite_veins": "Gate A: first person casts the giant's shadow again and the arms lie in it (13 px, 135 without it)",
}
## Lower is not worse than M10 by more than this share (the frames' own noise between two runs).
const NOISE := 0.03


func test_the_hair_eyes_and_designs_against_their_frames() -> void:
	var run: Dictionary = RUN.result("web")
	if str(run.skipped) != "":
		print("    test_hair_render: skipped - %s" % run.skipped)
		return
	assert_eq(run.errors, PackedStringArray(), "no shader or script error")
	var r: Dictionary = run.report
	assert_true(r.has("hair") and r.has("beard"), "the probe reported (exit %d): %s" % [int(run.code), str(run.text)])
	if not (r.has("hair") and r.has("beard")):
		return
	var styles: Dictionary = (r.hair as Dictionary).duplicate()
	styles.merge(r.beard)
	var met := 0
	var missed := PackedStringArray()
	var stale := PackedStringArray()
	for id: String in M10_HAIR:
		assert_true(styles.has(id), "%s was drawn" % id)
		if not styles.has(id):
			continue
		for f: String in M10_HAIR[id]:
			var m: Dictionary = styles[id][f]
			var base: Array = M10_HAIR[id][f]
			assert_true(int(m.px) >= MIN_PX, "%s draws at the %s framing (%d px)" % [id, f, int(m.px)])
			for k in 2:
				var name := "%s@%s.%s" % [id, f, "rough" if k == 0 else "scalp"]
				var v := float(m.rough if k == 0 else m.scalp)
				var better := v >= float(base[0]) * (1.0 - NOISE) if k == 0 else v <= float(base[1]) * (1.0 + NOISE) + 0.002
				if better:
					met += 1
					if KNOWN_MISSES.has(name):
						stale.append(name)
				else:
					assert_true(KNOWN_MISSES.has(name), "%s: %.4f against M10's %.4f" % [name, v, float(base[k])])
					missed.append("%s %.4f (M10 %.4f)" % [name, v, float(base[k])])
		if (r.beard as Dictionary).has(id):
			assert_true(int(r.beard[id].behind.px) >= BEHIND_FLOOR_PX, "%s is there from behind (%d px)" % [id,
				int(r.beard[id].behind.px)])
	if not stale.is_empty():
		print("    test_hair_render: now better than M10, drop from KNOWN_MISSES: %s" % ", ".join(stale))
	# the eyes
	assert_true(int(r.eyes.highlight_px) >= HIGHLIGHT_FLOOR_PX, "the cornea's highlight (%d px)" % int(r.eyes.highlight_px))
	assert_true(int(r.eyes.look_px) >= LOOK_FLOOR_PX, "the eye's look moves the iris (%d px)" % int(r.eyes.look_px))
	# scars and marks
	for id: String in M10_FRAMED:
		var d: Dictionary = (r.designs as Dictionary).get(id, {})
		assert_true(not d.is_empty(), "%s was drawn" % id)
		if d.is_empty():
			continue
		assert_true(int(d.framed) >= int(float(M10_FRAMED[id]) * float(GATE_A_FRAMED_SHARE.get(id, 0.9))), "%s reads in its %s framing (%d px, M10 %d)" % [id,
			str(d.framing), int(d.framed), int(M10_FRAMED[id])])
		var in_view := int(d.rear) >= int(VIEW_FLOOR_PX.rear) or int(d.fp) >= int(VIEW_FLOOR_PX.fp)
		assert_true(in_view or NOT_IN_EITHER_VIEW.has(id), "%s above its floor in the rear view (%d px) or first person (%d px)" % [id,
			int(d.rear), int(d.fp)])
	for id: String in ["scar.brow", "scar.cheek", "scar.chest_claws"]:
		assert_true(int(r.designs[id].framed) >= 2 * int(M10_FRAMED[id]), "%s widened to the 4 cm rule (%d px, M10 %d)" % [id,
			int(r.designs[id].framed), int(M10_FRAMED[id])])
	# shells: one draw call a style, as a card style
	var draws: Dictionary = r.draws
	for id: String in ["Hair_crop", "Beard_short"]:
		assert_eq(int(draws[id]), int(draws.bare) + 1, "%s is one draw call" % id)
	print("    test_hair_render: %d of %d hair measures at least M10's; known misses: %s" % [met, met + missed.size(),
		"; ".join(missed)])


func test_every_style_draws_on_the_hi_tier_too() -> void:
	var run: Dictionary = RUN.result("hi", "hair,beard")
	if str(run.skipped) != "":
		print("    test_hair_render: skipped - %s" % run.skipped)
		return
	assert_eq(run.errors, PackedStringArray(), "no shader or script error on the hi tier")
	var r: Dictionary = run.report
	assert_true(r.has("hair"), "the probe reported on the hi tier (exit %d)" % int(run.code))
	if not r.has("hair"):
		return
	assert_eq(str(r.tier), "hi", "the hi tier was drawn")
	for cat: String in ["hair", "beard"]:
		for id: String in r[cat]:
			assert_true(int(r[cat][id].face.px) >= MIN_PX, "%s draws on the hi tier (%d px)" % [id, int(r[cat][id].face.px)])
