extends TestSuite
## The rendered option check (P44; plan M10 §3.4 design 4, §2.13, decision 18): tests/support/
## appearance_render_probe.tscn in a child Godot under Xvfb (the Compatibility renderer, two llvmpipe threads,
## the web tier) draws every option of every set in its framed view - grids of sixteen 320x240 GiantPreview tiles
## a frame - against the base look, and every design also in the stage-1 rear Game view and in first person.
## Required: no engine or shader error, GiantLook.validate() empty, no blank tile, every option's changed pixels
## above its set's floor, and at least one option of each design category (tattoo, war paint, scar, ancestry
## mark) above the rear view's or the first-person view's floor - except a category listed in KNOWN_MISSES,
## which must still draw in one of the two views and is reported (none since the look pass, P46). The floors
## were set from the floor catalogue's renders (docs/systems/P44.md) and kept by the look pass, whose measured
## shares with the target catalogue are in docs/systems/P46.md. The grids are saved to user://m10_frames/options/ (with index.json naming every tile) for
## the merges, the sheets and P46. Without xvfb-run it is skipped with a note.
## M11 (P53, plan M11 §1.7 rule 3, §3.10: the rendered option grids go to the gate tier; P57 extends it to grids
## per slot): moved from tests/slow/, unchanged; about 18 s of the slow tier.

const PROBE := "res://tests/support/appearance_render_probe.tscn"
const PREFIX := "APPEARANCE_RENDER "
const CHILD_TIMEOUT_S := 200
const TILE_PX := 320 * 240
## A tile is drawn when at least this share of its pixels is off its backdrop.
const MIN_LIT := 0.02
## The share of a framed tile's pixels an option must change, per set: about half the smallest share the set's
## options measure (llvmpipe, the web tier), P44's rule. The M10 gate (LC-1) put the creator's key light on the
## side of the giant the camera sees and measured every set again in that light, with the same margin (P46.md
## lists the shares before and after): the lit skin, presets and beards change more of a tile than they did in
## the shadow (skin 0.0574 against 0.0160, presets 0.0762 against 0.0436, beards 0.0389 against 0.0283), so
## their floors rose; the hair colours, seen from behind with the key now 35 degrees to one side instead of
## flat on, change less (the nearest brown 0.0170 against 0.0332), so theirs fell. The hair's floor stands (the
## shoulder-length cut, the smallest, changes 0.0580).
## The gate's hair and skin changes (LC-6, OR-1) moved the shares again (skin 0.0594, hair 0.0599, beard 0.0306,
## haircolor 0.0170, presets 0.0793): every floor stands; the beard's is now 0.62 of its set's smallest share.
## P51's look pass (the paler skin, the hair shaded as a volume) brought the hair's smallest shares to 0.0428-0.0439
## (the shoulder-length cut against the long hair, the braided style against the base): the hair's floor is 0.038.
const FLOORS := {"skin": 0.028, "eyes": 0.00025, "hair": 0.038, "beard": 0.019, "haircolor": 0.0085,
	"tattoo": 0.0009, "ink": 0.008, "paint": 0.005, "paintcolor": 0.005, "scar": 0.0003, "mark": 0.0019,
	"outfit": 0.011, "dye": 0.014, "preset": 0.038}
## The pixels of a 320x240 tile the best option of a design category must change in the stage-1 rear Game
## view or in first person: about half the weakest reading category's best there (the marks: the lightning
## tree's 37 px from behind, the granite veins' 180 px in first person). 18 px of the tile are about 350 px of a
## 1920x1080 frame; a 4 cm stroke 20 cm long at stage 1 covers about 4 px of the rear tile.
const VIEW_FLOOR_PX := {"rear": 18, "fp": 90}
const DESIGN_SETS := ["tattoo", "paint", "scar", "mark"]
## Design categories that do not yet read in either view, with the reason; each must still draw (a pixel or more)
## in one of them. Empty since the look pass (P46): the back lashes read from behind (63 px of the rear tile), so
## the scars left the list.
const KNOWN_MISSES := {}
## The designs of the catalogue (the floor's 17 and the look pass's 12): each is drawn in its two views.
const DESIGNS := 29


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_every_option_draws_and_reads_in_its_view() -> void:
	if not _have("xvfb-run"):
		print("    test_appearance_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x960x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "1280x960", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=web"])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or l.begins_with("SCRIPT ERROR") or (l.begins_with("ERROR") and (l.contains("giant")
				or l.contains("appearance") or l.contains("creator"))):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "no engine or shader error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and (r as Dictionary).has("results"), "it reported: %s" % (line if line != "" else
		text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or not (r as Dictionary).has("results"):
		return
	assert_eq(r.validate, [], "GiantLook.validate() is empty for every look")
	var results: Dictionary = r.results
	var blank := PackedStringArray()
	var low := PackedStringArray()
	var by_set := {}
	var best_view := {}
	for key: String in results:
		var t: Dictionary = results[key]
		if float(t.lit) < MIN_LIT:
			blank.append("%s (%.3f)" % [key, float(t.lit)])
		var cat := str(t.cat)
		if cat == "base":
			continue
		var changed := float(t.changed)
		if str(t.view) == "framed":
			if changed < float(FLOORS.get(cat, 0.001)):
				low.append("%s %.4f < %.4f (vs %s)" % [key, changed, float(FLOORS.get(cat, 0.001)), t.vs])
			if not by_set.has(cat):
				by_set[cat] = []
			(by_set[cat] as Array).append(changed)
		else:
			var k := "%s@%s" % [cat, t.view]
			best_view[k] = maxf(float(best_view.get(k, 0.0)), changed)
	assert_eq(blank, PackedStringArray(), "no blank tile")
	assert_eq(low, PackedStringArray(), "every option changes its framed view above its set's floor")
	for cat: String in Appearance.CATEGORIES + ["preset"]:
		assert_true(by_set.has(cat), "every set was drawn (%s)" % cat)
	var tiles := 0
	for cat: String in Appearance.CATEGORIES:
		tiles += Appearance.option_ids(cat).size()
	assert_true(int(r.tiles) >= tiles + 2 * DESIGNS, "every option and every design's two views (%d tiles)" % int(r.tiles))
	for cat: String in DESIGN_SETS:
		var reads := PackedStringArray()
		var drawn := 0
		for view: String in VIEW_FLOOR_PX:
			var px := roundi(float(best_view.get("%s@%s" % [cat, view], 0.0)) * TILE_PX)
			drawn = maxi(drawn, px)
			if px >= int(VIEW_FLOOR_PX[view]):
				reads.append("%s %d px" % [view, px])
		if KNOWN_MISSES.has(cat):
			assert_true(drawn > 0, "a %s option still draws from behind or in first person (best %d px)" % [cat, drawn])
			print("    test_appearance_render: KNOWN MISS - no %s option reads from behind or in first person above the floor (best %d px): %s%s" % [
				cat, drawn, KNOWN_MISSES[cat], "" if reads.is_empty() else "; it now reads (%s): take it off KNOWN_MISSES" % ", ".join(reads)])
		else:
			assert_false(reads.is_empty(), "a %s option reads in the rear Game view (%d px) or in first person (%d px)" % [cat,
				roundi(float(best_view.get(cat + "@rear", 0.0)) * TILE_PX), roundi(float(best_view.get(cat + "@fp", 0.0)) * TILE_PX)])
	var lines := PackedStringArray()
	for cat: String in by_set:
		var a: Array = by_set[cat]
		a.sort()
		lines.append("%s min %.4f med %.4f" % [cat, float(a[0]), float(a[a.size() / 2])])
	var views := PackedStringArray()
	for k: String in best_view:
		views.append("%s %d px" % [k, roundi(float(best_view[k]) * TILE_PX)])
	views.sort()
	print("    test_appearance_render: %d tiles in %d grids, %.0f ms a grid (a frame of 16 tiles), %.1f s in all on %s; %s; best in the views: %s" % [
		int(r.tiles), int(r.grids), float(r.grid_ms), float(r.ms) / 1000.0, str(r.adapter), "; ".join(lines), ", ".join(views)])
