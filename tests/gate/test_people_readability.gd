extends TestSuite
## P60 (plan M11 §2.9 "Readability", §0.3): every telegraphed wind-up of every person role reads at the game
## camera. tests/support/people_probe.gd --probe=readability (a child process under Xvfb, the gl_compatibility
## renderer) stands each role 4 m before a stage-1 giant, seen through the giant's own camera, renders its idle and
## the end of the wind-up of each of its telegraphed attacks (the soldier's chop and brace, the pike's thrust and
## the pike formation's brace, the shield formation's brace for the shieldman and the iron guard, the archer's
## shot, the mage's slow bolt and barrier), and measures the share of the person's screen box (its idle's and its
## wind-up's) that changed: at least 1.5 % each. Skipped with a note without xvfb-run. Gate tier.
## P64 (plan §3.17 design 1): the brutes, the bosses (one by one: the King's combos, slam, charge and phase roar; the
## Matriarch's sweep, stomp, frenzy and roar; P64b: her whelp throw, a whelp of her brood beside her) and the wolves'
## lunges, skinned, the same way (--probe=creatures): their telegraphs read on the realistic bodies.

const RENDER := preload("res://tests/slow/test_people_render.gd")
const MIN_SHARE := 0.015
const EXPECTED := 9
const CREATURES_EXPECTED := 17


func test_every_telegraphed_windup_differs_from_idle_at_the_game_camera() -> void:
	if not RENDER._have("xvfb-run"):
		print("    test_people_readability: rendered check skipped - xvfb-run is not installed (it needs a display)")
		return
	var r: Dictionary = RENDER.run_probe("readability")
	var results: Array = r.get("results", [])
	assert_eq(results.size(), EXPECTED, "every telegraphed attack of every role measured")
	var report := PackedStringArray()
	for x: Dictionary in results:
		assert_true(bool(x.started), "%s starts %s" % [x.role, x.action])
		assert_true(float(x.share) >= MIN_SHARE, "%s %s: the wind-up changes %.1f %% of its screen box (at least %.1f %%)" % [
			x.role, x.action, float(x.share) * 100.0, MIN_SHARE * 100.0])
		report.append("%s %s %.1f %%" % [str(x.role).trim_prefix("enemy."), str(x.action).trim_prefix("ability."), float(x.share) * 100.0])
	print("    test_people_readability: %s" % ", ".join(report))


func test_every_creatures_telegraphed_windup_differs_from_idle_skinned() -> void:
	if not RENDER._have("xvfb-run"):
		print("    test_people_readability: rendered check skipped - xvfb-run is not installed (it needs a display)")
		return
	var r: Dictionary = RENDER.run_probe("creatures")
	var results: Array = r.get("results", [])
	assert_eq(results.size(), CREATURES_EXPECTED, "every telegraphed attack of every brute, boss and wolf measured")
	var report := PackedStringArray()
	for x: Dictionary in results:
		assert_true(bool(x.started), "%s starts %s" % [x.role, x.action])
		assert_true(bool(x.get("skinned", false)), "%s is skinned" % x.role)
		assert_true(float(x.share) >= MIN_SHARE, "%s %s: the wind-up changes %.1f %% of its screen box (at least %.1f %%)" % [
			x.role, x.action, float(x.share) * 100.0, MIN_SHARE * 100.0])
		report.append("%s %s %.1f %%" % [str(x.role).trim_prefix("enemy."), str(x.action).trim_prefix("ability."), float(x.share) * 100.0])
	print("    test_people_readability (creatures): %s" % ", ".join(report))
