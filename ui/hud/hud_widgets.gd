class_name HudWidgets
extends RefCounted
## Pre-declared registry of HUD widget scripts (plan §2.10.1). Every planned widget is listed
## now; Hud loads each entry whose file exists (ResourceLoader.exists) and skips the others
## silently, so a later package adds its widget file and never edits this list or hud.gd.
## Regions are given relative to the screen anchor named in each comment.

const WIDGETS := [
	"res://ui/hud/interact_prompt.gd",   # P02  centre, y +100..+136 below the crosshair
	"res://ui/hud/status_row.gd",        # P03  bottom-left, (16..340, -196..-170)
	"res://ui/hud/checkpoint_toast.gd",  # P06  top-left under the debug panel line, (12..352, 52..80)
	"res://ui/hud/threat_arrows.gd",     # P09  full-rect overlay; draws only edge arrows (24 px inside the edge)
	"res://ui/hud/xp_bar.gd",            # P12  bottom-left, (16..340, -166..-152), "Lv 3  120 / 200 XP"
	"res://ui/hud/ability_notice.gd",    # P12  centre, (-260..260, -250..-212); "New ability: Runic Bolt [6]", out of combat
	"res://ui/hud/boss_bar.gd",          # P11a top-centre, (-320..320, 14..58); Hud hides its target frame for bosses
	"res://ui/hud/quest_tracker.gd",     # P13  top-right, (-356..-16, 14..132)
	"res://ui/hud/objective_marker.gd",  # P13  projected marker + edge clamp + distance
	"res://ui/hud/tutorial_prompt.gd",   # P13  left-centre, (16..396, -70..70 around vertical centre)
]


## Instantiates every widget of `paths` whose script exists and adds it to `hud`, in list
## order (later entries draw on top). Returns the widgets created.
static func create_all(hud: Hud, paths: Array = WIDGETS) -> Array[HudWidget]:
	var out: Array[HudWidget] = []
	for path: String in paths:
		if not ResourceLoader.exists(path):
			continue
		var script := load(path) as Script
		if script == null:
			continue
		var w := script.new() as HudWidget
		if w == null:
			push_warning("HudWidgets: %s is not a HudWidget" % path)
			continue
		w.name = path.get_file().get_basename().to_pascal_case()
		w.hud = hud
		hud.add_child(w)
		out.append(w)
	return out
