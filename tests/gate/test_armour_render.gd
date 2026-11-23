extends TestSuite
## B1: every functional armour piece, rendered on the giant at stages 1, 5 and 6 in three poses (the idle, a walk's
## stride, the stomp's raised knee and arms): it draws over the default look, it is not sunk into the body (most of
## it shows where the body could cover it), it reads the same at every stage (the model is scaled whole), and a hidden
## slot draws none of it. The headless runner draws nothing, so this runs tests/support/armour_probe.tscn in a child
## Godot under Xvfb with the Compatibility renderer (opengl3, two llvmpipe threads, 240x240); without xvfb-run it is
## skipped with a note (tools/check.sh --require turns that into a failure).

const PROBE := "res://tests/support/armour_probe.tscn"
const CHILD_TIMEOUT_S := 240
const PREFIX := "ARMOUR_PROBE "
## A piece draws when at least this many of its pixels show over the look (the heart-stone, a hand's width on the
## breastbone, about 14 in the 240 x 240 frame; a slab or a hauberk hundreds to thousands).
const MIN_PX := 8
## A piece is not sunk into the body when, over its three poses, a median of at least this share of it shows with the
## body drawn (its pixels with the body against its pixels alone). The beard covers part of the heart-stone and the
## arms part of a hauberk's skirt: those are occlusion, not clipping, and stay above it.
const MIN_SHOWN_SHARE := 0.45


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_every_piece_draws_fits_and_hides() -> void:
	if not _have("xvfb-run"):
		print("    test_armour_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "240x240", "--audio-driver", "Dummy", PROBE])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or l.contains("SCRIPT ERROR"):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "no shader or script error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != "" else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	var pieces: Dictionary = r.pieces
	var want := 0
	for sid: String in Armour.set_ids():
		want += Armour.set_pieces(sid).size()
	assert_eq(pieces.size(), want, "every piece of every set measured")
	var report := PackedStringArray()
	for id: String in pieces:
		var by_stage: Dictionary = pieces[id]
		assert_eq(by_stage.keys().size(), 3, "%s at stages 1, 5 and 6" % id)
		var shares_at := {}
		for stage: String in by_stage:
			var shares: Array = []
			for pose: String in by_stage[stage]:
				var v: Array = by_stage[stage][pose]
				assert_true(int(v[0]) >= MIN_PX, "%s draws at stage %s, %s (%d px)" % [id, stage, pose, int(v[0])])
				assert_true(int(v[2]) >= 1, "%s: its meshes were marked" % id)
				shares.append(float(v[0]) / maxf(1.0, float(v[1])))
			shares.sort()
			var median: float = shares[shares.size() / 2]
			shares_at[stage] = median
			assert_true(median >= MIN_SHOWN_SHARE, "%s at stage %s is not sunk into the body (%.2f of it shows; %s)" % [
				id, stage, median, str(by_stage[stage])])
		assert_true(absf(float(shares_at["5"]) - float(shares_at["6"])) <= 0.1,
			"%s reads alike at stages 5 and 6 (%.2f, %.2f)" % [id, float(shares_at["5"]), float(shares_at["6"])])
		report.append("%s %.2f" % [id.trim_prefix("armour."), float(shares_at["5"])])
		assert_eq(int((r.hidden as Dictionary).get(id, -1)), 0, "%s: hidden, none of it is drawn" % id)
	print("    test_armour_render: the share of each piece showing at stage 5 (median of three poses): %s; on %s" % [
		", ".join(report), str(r.adapter)])
