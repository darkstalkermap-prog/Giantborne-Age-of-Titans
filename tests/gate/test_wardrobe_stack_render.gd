extends TestSuite
## The stack check (P57; plan M11 §3.10 item 4, §1.7 rule 3: rendered option checks run in the gate tier):
## tests/support/wardrobe_render_probe.tscn --stack in a child Godot under Xvfb at 320x240 (the Compatibility renderer,
## two llvmpipe threads, the web tier): LOOKS random slot looks - half as the creator's Randomize dresses him, half with
## nearly every slot and every accessory slot filled - each in three poses (standing relaxed, the run at mid-stride, the
## roar) from the front, behind or three-quarters, every garment and accessory in a flat colour of its own and the
## frame drawn twice with the camera moved by half a millimetre: in no view do more than the floor of the giant's pixels
## change in patches (two surfaces at one depth interleave in patches that move; a moved silhouette changes a line).
## The positive control (FOLLOWUPS, P54's row): the fullest look with a copy of one garment drawn over it, pushed out
## by less than the depth buffer's step - two coincident surfaces made on purpose - must change at least CONTROL_RATIO
## times the floor, so a measure that saw nothing would fail here (the fullest look's own measure, interior pixels
## that flip, saw 48 of the control's speckled pixels against 41 in a clean look: it is kept in the report). Without xvfb-run it is skipped with a note.

const PROBE := "res://tests/support/wardrobe_render_probe.tscn"
const PREFIX := "WARDROBE_STACK "
const CHILD_TIMEOUT_S := 500
const LOOKS := 200
const CONTROL_RATIO := 5.0


static func _have(tool: String) -> bool:
	var out: Array = []
	return OS.execute("sh", ["-c", "command -v %s" % tool], out, true) == 0


func test_random_slot_looks_in_three_poses_draw_without_z_fighting() -> void:
	if not _have("xvfb-run"):
		print("    test_wardrobe_stack_render: skipped - xvfb-run is not installed (the rendered check needs a display)")
		return
	var args := PackedStringArray(["LP_NUM_THREADS=2", "timeout", str(CHILD_TIMEOUT_S), "xvfb-run", "-a", "-s",
		"-screen 0 1280x720x24", OS.get_executable_path(), "--path", ProjectSettings.globalize_path("res://"),
		"--rendering-driver", "opengl3", "--resolution", "320x240", "--audio-driver", "Dummy", PROBE, "--",
		"--giant-tier=web", "--stack=%d" % LOOKS, "--seed=57"])
	var output: Array = []
	var code := OS.execute("env", args, output, true)
	var text := "\n".join(output)
	var line := ""
	var errors := PackedStringArray()
	for l in text.split("\n"):
		if l.begins_with(PREFIX):
			line = l.substr(PREFIX.length()).strip_edges()
		elif l.contains("SHADER ERROR") or l.begins_with("SCRIPT ERROR") or (l.contains("ERROR") and l.contains("giant")):
			errors.append(l.strip_edges())
	assert_eq(code, 0, "the probe ran (exit %d)" % code)
	assert_eq(errors, PackedStringArray(), "every shader and part loads without an error")
	var r: Variant = JSON.parse_string(line)
	assert_true(typeof(r) == TYPE_DICTIONARY and not (r as Dictionary).has("error"), "it reported: %s" % (line if line != ""
		else text.right(800)))
	if typeof(r) != TYPE_DICTIONARY or (r as Dictionary).has("error"):
		return
	var floor_share := float(r.floor)
	assert_eq(int(r.looks), LOOKS, "%d looks drawn" % int(r.looks))
	assert_eq(int(r.views), LOOKS * 3, "each in three poses")
	assert_eq(int(r.over), 0, "no view over the floor of %.4f (the worst %.4f: look %d, %s, %s)" % [floor_share,
		float(r.worst.patch), int(r.worst.get("look", -1)), str(r.worst.get("pose", "")), str(r.worst.get("garments", []))])
	var c: Dictionary = r.control
	assert_true(c.has("patch") and float(c.patch) >= floor_share * CONTROL_RATIO,
		"the positive control: %s drawn twice %.5f m apart changes %.4f of the giant's pixels in patches (at least %.4f)" %
		[str(c.get("garment", "")), float(c.get("push_m", 0.0)), float(c.get("patch", 0.0)), floor_share * CONTROL_RATIO])
	print("    test_wardrobe_stack_render: %d looks (%.1f garments a look), %d views, worst patch share %.4f (%d of %d px, %s), worst interior flicker %.4f; control %.4f (%d px; %s pushed %.5f m); %.1f s on %s" %
		[int(r.looks), float(r.slots_worn) / maxf(1.0, float(r.looks)), int(r.views), float(r.worst.patch), int(r.worst.get("clustered", 0)),
		int(r.worst.get("pixels", 0)), str(r.worst.get("pose", "")), float(r.flicker_worst), float(c.get("patch", 0.0)),
		int(c.get("clustered", 0)), str(c.get("garment", "")), float(c.get("push_m", 0.0)), float(r.ms) / 1000.0, str(r.adapter)])
