class_name HudWidgets
extends RefCounted
## Pre-declared registry of HUD widget scripts (plan §2.10.1). Every planned widget is listed
## now; Hud loads each entry whose file exists (ResourceLoader.exists) and skips the others
## silently, so a later package adds its widget file and never edits this list or hud.gd.
## Regions are given relative to the screen anchor named in each comment.
## The list order is the draw order (M4 gate): the two edge overlays come last, the threat arrows
## on top, so no panel (the tutorial prompt's TIP box above all) ever hides an edge warning; they
## keep clear of the panels themselves (Hud.overlay_keep_out, HudEdge.clear_of).

const WIDGETS := [
	"res://ui/hud/interact_prompt.gd",   # P02  centre, y +100..+136 below the crosshair
	"res://ui/hud/status_row.gd",        # P03  bottom-left, (16..340, -196..-170)
	"res://ui/hud/checkpoint_toast.gd",  # P06  top-left under the debug panel line, (12..352, 52..86) (P16; was 52..80)
	"res://ui/hud/xp_bar.gd",            # P12  bottom-left, (16..340, -166..-152), "Lv 3  120 / 200 XP"
	"res://ui/hud/ability_notice.gd",    # P12  top-centre, (-260..260, 162..200) (P27; P16 132..170; was -250..-212 from the bottom); "New ability: Runic Bolt [6]", out of combat
	"res://ui/hud/boss_bar.gd",          # P11a top-centre, (-270..270, 44..88) (P27: under the compass; P16 14..58, was -320..320); Hud hides its target frame for bosses
	"res://ui/hud/quest_tracker.gd",     # P13  top-right, (-356..-16, 14..132)
	"res://ui/hud/tutorial_prompt.gd",   # P13  left-centre, (16..396, -70..70 around vertical centre)
	# M6-M9 (pre-declared by P20, plan M6-M9 §2.14; below the two edge overlays):
	"res://ui/hud/compass.gd",           # P27  top-centre, (-270..270, 4..28) (the plan's -300..300 met the tracker at 1280 px)
	"res://ui/hud/region_banner.gd",     # P27  top-centre, (-320..320, 206..252), 3 s (the plan's 150..196 met the ability notice)
	"res://ui/hud/discovery_toast.gd",   # P27  top-left under the checkpoint toast, (12..352, 92..126)
	"res://ui/hud/objective_marker.gd",  # P13  projected marker + edge clamp (36 px inside the edge, clear of the panels) + distance
	"res://ui/hud/threat_arrows.gd",     # P09  full-rect overlay; draws only edge arrows (24 px inside the edge, clear of the panels)
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
